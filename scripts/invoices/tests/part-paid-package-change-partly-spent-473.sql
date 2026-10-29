-- 473: a 'transfer' customer change of a package paid in part whose credit
-- was partly spent is refused as "Partly spent", as it is for the same
-- package paid in full: the list of what a change can move
-- (invoice_transferable_benefits) judges a lot with the other lots of its
-- package line and credit category (471's NOT COVERED 9, its suite's KNOWN
-- K9; the Owner, 26 Oct 2026: "fix the leftover gaps too").
-- supabase/473_part_paid_package_change_partly_spent.sql (after 462, 463,
-- 470, 471 and 472).
--
-- Every step goes through the app's own calls (471's and 472's suite
-- harness, its steps and readings, renamed): the invoice form
-- (create_invoice_with_details) and the Pay dialog (record_invoice_
-- settlement), Record Payment (in full, or of an amount: 'payp'), Cancel,
-- Reopen, the Finance panel's refund by line and "Record refund paid"
-- (refund_invoice_recorded), Move (transfer_invoice_unused_benefit), the
-- invoice form's customer change (correct_invoice, 'transfer' or 'keep'),
-- a customer merge; an Owner's reversal is reverse_credit_lot called as an
-- active Owner (no page calls it: a stand-in for a direct call). Each app
-- call is followed by what its commit does (462's trigger is deferred; SET
-- CONSTRAINTS ... IMMEDIATE, then DEFERRED).
--
-- The cases (A the buyer, B and C later customers, K a record a merge
-- keeps, F a friend an Owner moved credit to; cp the S$100 Credit Package,
-- cpb with a S$10 Bonus, pbv the S$140 Premium Bundle with 2 vouchers; S1,
-- S2 S$20 sessions paid from the package's credit, svc5 S$5; 'cp 40': S$40
-- of S$100 paid, S$40 of its credit released before full payment):
--   TQ         471's K9: paid S$40, S1 and S2 paid from it, cancelled,
--              reopened, paid in full, a 'transfer' change to B.
--   TQp        the same never cancelled (paid in full after S2).
--   TQ1        S1 only before the cancel (S$20 released again at the
--              reopening): both lots holding credit are named.
--   TQ2, TQk   a second change to C after the first (TQ2), or after a
--              'keep' change to B (TQk).
--   TQv, TQb   the Premium Bundle (its Bonus and vouchers beside it), the
--              Bonus package.
--   TQmb, TQcb the buyer merged into K, or the customer changed to C, before
--              the sessions.
--   TQms       an Owner's Move of the S$60 to A at another store (a store
--              correction), then the change.
--   TQr, TQr0  a S$5 session and an Owner's reversal of the S$35 left (TQr),
--              or the S$40 reversed with nothing spent (TQr0), then paid.
--   W2, W2m, W2k  paid S$20 (released), S1, paid S$20 more (released again on
--              a lot of its own; not paid in full), the change (W2); the
--              buyer merged into K before S1 (W2m); a 'keep' change to C first
--              (W2k).
--   TU1, TQp1  refused before 473 too (a lot partly spent); now both lots
--              holding credit are named.
--   TQm, TQmk, TQkp  K9's state reached otherwise (a merge of A refused, 445's
--              NOT COVERED 1; K the kept record; a 'keep' change): the list now
--              says a 'transfer' change is refused.
--   Controls (the same with and without 473): TQc, TQcp, TQck (paid in full:
--   refused as before, also after a cancel and reopening and after a
--   'keep'), TVc, TBc (the bundle, the Bonus package), TQ0, TQ00, W2c
--   (nothing spent: everything moves), TU (refunds paid back count as not
--   used: everything moves), TQn, W2s (a released lot partly spent: refused
--   as before), TQmv (a Move to someone else: nothing left to move), TCsc
--   (463's store Move of a partly spent package), RVc (a reversal on one
--   lot), TQcx (cancelled).
--   Known (473's NOT COVERED, the same with and without 473 but for what the
--   list says at the end): TQn2 (all released credit spent, nothing on a
--   lot: the change passes, the payment gives B the rest), K1, K2 ('keep'
--   before full payment splits), TQcr, TQcc (a cancelled package changed,
--   reopened and paid: B; the same paid in full).
-- In every case 462's invariants (471's reading of them, the lots a release
-- record's chain reaches counting as named) and Cancel (tried, undone)
-- taking all of the invoice's credit back from whoever holds it.
--
--   S. Where it starts: 462, 463, 470, 471 and 472 in; 473 in (nomig) or
--      not, the list at 463's AFTER.
--   R. Without 473 (skipped with -v nomig=1), undone: each 'fixed' case ends
--      otherwise (the fault reproduced: TQ B S$60, A has used S$40; W2 B
--      S$20; ...); each control and known case as expected.
--   Q. The read-only query in 473's header (the same text), on states made
--      for it and the R states: what it lists, by reason (1 to 4).
--   9. Refusals, each changing nothing: the list neither 463's nor 473's; a
--      function it relies on not as tested (the change, 472's forwarder); an
--      overload of its name; a new caller of it; a new writer of benefit
--      rows; a new writer of the release record. The same grants in another
--      order do not stop it.
--   M. Begun before 473 (K9's state, W2's), the change after it: refused;
--      and a package split before 473 (MTQ): a second change refused.
--  10. 473 installed twice: as tested, the second run changing nothing,
--      nothing added, the grants as before.
--   A. Each case after 473: who holds what, the invoice's customer, the
--      list's rows (blocking and movable), the refusal's words, the
--      invariants, Cancel; the controls exactly as before.
--   P. Probes: the list's rows for K9 (the released lot "Fully spent", the
--      rest "Partly spent") and the correction summary's blocked items, the
--      same as for the package paid in full; before settlement (W2); the
--      store Move's lot blocking (TQms); 'transfer' or 'keep' still asked.
--   K. KNOWN (473's NOT COVERED), checked as they are: 1 (TQn2), 2 (K1,
--      K2), 3 (TQcr, TQcc), 5 (TQ1, TU1, TQp1: two lots named), 6 (MTQ).
--
-- Run on a copy of production as it is with 472 applied (471 in, 26 Oct
-- 2026: fd61e1a1; 472 then: 84308fd1, 1387 functions):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoices/tests/part-paid-package-change-partly-spent-473.sql
-- It installs 473 itself (twice) inside its transaction. Where 473 is in
-- already, add -v nomig=1 (S checks it as tested; R, Q, 9 and M are skipped;
-- every case after 473 is still checked). Section 9 lets the install fail on
-- purpose (psql prints its ERROR); the suite then checks that message.
-- Disposable database only; everything is rolled back. Every name, code and
-- amount is invented (@example.com); the phones are numbers kept for fiction
-- (ACMA, +61491570000 to +61491570999).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '900s';

-- ── Set-up and the app's calls (462's, 470's and 471's suite harness, for 472) ───────
create temp table t473(k text primary key, id uuid);
create temp table t473_res(phase text, k text, v jsonb, primary key (phase, k));
create temp sequence t473_phone;
create function pg_temp.t473_id(p_k text) returns uuid language sql as $f$ select id from t473 where k = p_k $f$;
create function pg_temp.t473_put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t473 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.t473_check(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  if not coalesce(p_ok, false) then raise exception 'FAIL %', p_label; end if;
end $f$;
create function pg_temp.t473_fingerprint() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') $f$;
create function pg_temp.t473_463_in() returns boolean language sql as $f$
  select to_regprocedure('public.invoice_benefit_moved_to_other(uuid)') is not null $f$;
create function pg_temp.t473_462_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and exists (select 1 from pg_trigger where tgname = 'credit_given_back_follows'
                  and tgrelid = 'public.customer_credit_ledger'::regclass) $f$;
-- 471 is in: the forwarder is 471's or keeps its text (472's does).
create function pg_temp.t473_471_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 471 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
-- 472 is in: the forwarder is 472's (its text says so; S checks its md5).
create function pg_temp.t473_472_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 472 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
-- 473 is in: the list is 473's (its text says so; S checks its md5).
create function pg_temp.t473_in() returns boolean language sql as $f$
  select position('-- 473 (the Owner, 26 Oct 2026' in pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) > 0 $f$;
-- 476 is in (it goes in after 473 to 475): a package paid in part is
-- changed as the same package paid in full is (NOT COVERED 1 and 2: TQn2,
-- K1 and K2 are then checked as 476 settles them).
create function pg_temp.t473_476_in() returns boolean language sql as $f$
  select position('-- 476 (the Owner, 27 Oct 2026' in pg_get_functiondef('public.invoice_transferable_benefits(uuid)'::regprocedure)) > 0 $f$;
-- 470 is in (its text is in 471's and 472's too).
create function pg_temp.t473_470_in() returns boolean language sql as $f$
  select to_regprocedure('public.credit_given_back_follows(uuid)') is not null
     and position('-- 470 (the Owner, 24 Oct 2026' in pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure)) > 0 $f$;
-- What a commit does at the end of each app call (each is its own
-- transaction in the app): 462's deferred trigger on the ledger runs (471
-- adds no trigger: its change is in the function that trigger runs). Here
-- the suite is one transaction, so the trigger's queued rows are run at this
-- point. (Not where each step really commits: t473.autocommit 'on', for
-- running the same cases one call per transaction on a disposable copy.)
create function pg_temp.t473_commit() returns void language plpgsql as $f$
begin
  if coalesce(current_setting('t473.autocommit', true), '') = 'on' then return; end if;
  if pg_temp.t473_462_in() then
    execute 'set constraints public.credit_given_back_follows immediate';
    execute 'set constraints public.credit_given_back_follows deferred';
  end if;
end $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; st2 uuid; pm uuid; v uuid; cp uuid; cpb uuid; pbv uuid; svc uuid; svc5 uuid;
begin
  insert into auth.users(id, email) values (own, 't473-owner@example.com');
  insert into profiles(id, full_name, email, role, is_active) values (own, 'T473 Owner', 't473-owner@example.com', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('T473 Store', 'T473S1', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('T473 Other Store', 'T473S2', 'SG') returning id into st2;
  insert into payment_methods(name, is_active) values ('T473 Cash', true) returning id into pm;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T473 Plain 30', 'T473-P30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true), (v, st2, 30, true);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy)
    values ('T473 S$100', 100, 100, false, true, true) returning id into cp;
  insert into credit_package_stores(package_id, store_id) values (cp, st), (cp, st2);
  insert into credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('T473 S$100 + S$10', 100, 100, true, 10, true, true, false) returning id into cpb;
  insert into credit_package_stores(package_id, store_id) values (cpb, st), (cpb, st2);
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T473 Bundle S$140 + 2 vouchers', 140, 100, 40, 2, true) returning id into pbv;
  insert into premium_bundle_stores(bundle_id, store_id) values (pbv, st), (pbv, st2);
  insert into premium_bundle_vouchers(bundle_id, voucher_id) values (pbv, v);
  svc := (upsert_therapy_service(null, 'T473-SESSION', 'T473 Session', 20, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc, st, true, null);
  svc5 := (upsert_therapy_service(null, 'T473-SHORT', 'T473 Short session', 5, 15, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform set_therapy_service_store(svc5, st, true, null);
  insert into t473 values ('own', own), ('store', st), ('store2', st2), ('pm', pm), ('v', v), ('cp', cp), ('cpb', cpb), ('pbv', pbv),
    ('svc', svc), ('svc5', svc5),
    ('wallet', (select id from payment_methods where name = 'Wallet — Credit Package Paid' and is_wallet_credit and deleted_at is null)),
    ('bwallet', (select id from payment_methods where name = 'Wallet — Premium Bundle Paid' and is_wallet_credit and deleted_at is null)),
    ('cbonus', (select id from payment_methods where name = 'Wallet — Credit Package Bonus' and is_wallet_credit and deleted_at is null));
  perform pg_temp.t473_check(pg_temp.t473_id('wallet') is not null and pg_temp.t473_id('bwallet') is not null, 'setup: the wallet methods (443) are there');
end $$;

-- A customer of one run of one case: '<phase>/<case>/<role>'.
create function pg_temp.t473_cust(p_k text) returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into customers(full_name, phone) values ('T473 ' || p_k, '+61491570' || lpad((nextval('t473_phone') % 1000)::text, 3, '0'))
    returning id into c;
  return pg_temp.t473_put(p_k, c);
end $f$;
-- The invoice form with these lines ('cp' / 'cpb' a Credit Package, 'pbv' the
-- Premium Bundle, 'v' a voucher line of p_qty units), with an Owner's manual
-- discount of p_discount (its reason given) where one is given, paid through
-- the Pay dialog: in full, or p_first of it (a part-paid package).
create function pg_temp.t473_sale(p_cust uuid, p_kinds text[], p_first numeric default null, p_qty int default 2,
                                  p_discount numeric default null)
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. cardinality(p_kinds) loop
    v_lines := v_lines || jsonb_build_array(case
      when p_kinds[i] = 'v' then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t473_id('v'), 'quantity', p_qty)
      when p_kinds[i] in ('cp', 'cpb') then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t473_id(p_kinds[i]), 'quantity', 1)
      else jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t473_id('pbv'), 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t473_id('v'), 'quantity', 2))) end);
  end loop;
  inv := create_invoice_with_details(pg_temp.t473_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text)
           || case when p_discount is not null
                   then jsonb_build_object('manual_discount', p_discount, 'manual_discount_reason', 'T473 discount') else '{}'::jsonb end);
  perform record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.t473_id('pm'),
    'amount', coalesce(p_first, (select total_amount from invoices where id = inv)),
    'payment_date', sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid());
  return inv;
end $f$;
-- Record Payment of what is outstanding (nothing when it is settled).
create function pg_temp.t473_pay(p_inv uuid) returns void language plpgsql as $f$
begin
  if (invoice_financial_position(p_inv)->>'outstanding')::numeric > 0 then
    perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t473_id('pm'),
      'amount', (invoice_financial_position(p_inv)->>'outstanding')::numeric)), gen_random_uuid());
  end if;
end $f$;
-- The receipts that still hold p_amount between them, as the Finance panel
-- splits a refund across them.
create function pg_temp.t473_sources(p_inv uuid, p_amount numeric) returns jsonb language plpgsql as $f$
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
create function pg_temp.t473_line(p_inv uuid, p_n int default 1) returns uuid language sql as $f$
  select id from invoice_items where invoice_id = p_inv order by id offset p_n - 1 limit 1 $f$;
-- The Finance panel's refund by line of line p_n: p_amount off its Paid
-- benefit (the one an Owner did not move, or with p_holder the one p_holder
-- holds), or every unused benefit it still holds (p_amount null).
create function pg_temp.t473_back(p_inv uuid, p_n int, p_amount numeric default null, p_holder uuid default null)
  returns void language plpgsql as $f$
declare opts jsonb; ben jsonb; tot numeric; item uuid := pg_temp.t473_line(p_inv, p_n);
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
  if ben is null then raise exception 'T473: nothing to refund on that line'; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', tot, 'benefits', ben)),
    pg_temp.t473_sources(p_inv, tot), '[]'::jsonb, 'T473 by line', gen_random_uuid());
end $f$;
-- The invoice form's customer change, its lines as they are (and the store,
-- when given), with 'transfer' or 'keep'. The change's Audit Log row is
-- dated now, as a later call's is (the suite is one transaction).
create function pg_temp.t473_lines(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    from invoice_items it where it.invoice_id = p_inv $f$;
create function pg_temp.t473_change(p_inv uuid, p_cust uuid, p_action text default 'transfer', p_store text default null)
  returns void language plpgsql as $f$
begin
  perform correct_invoice(p_inv, pg_temp.t473_lines(p_inv),
    jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = p_inv),
      'customer_id', p_cust, 'store_id', coalesce(pg_temp.t473_id(p_store), (select store_id from invoices where id = p_inv)),
      'benefit_action', p_action),
    'T473 wrong customer', gen_random_uuid());
  update audit_logs set created_at = clock_timestamp()
   where record_id = p_inv and action = 'invoice_benefits_followed_reassignment' and new_data->>'to_customer' = p_cust::text
     and created_at = now();
end $f$;
create function pg_temp.t473_merge(p_keep uuid, p_dup uuid) returns void language plpgsql as $f$
begin
  perform merge_customer_records(p_keep, p_dup, 'T473 the same person', gen_random_uuid());
end $f$;
-- The Finance panel's Move of line p_n's unused benefit (its Paid credit,
-- or its Bonus with p_kind 'bonus', or a voucher) to p_to, at p_store.
create function pg_temp.t473_move(p_inv uuid, p_n int, p_to uuid, p_kind text default 'paid', p_store text default null)
  returns void language plpgsql as $f$
declare b uuid;
begin
  select bv.id into b from invoice_benefit_values bv
    left join customer_reward_vouchers v on v.id = bv.reward_voucher_id
    left join customer_credit_lots l on l.id = bv.lot_id
   where bv.invoice_item_id = pg_temp.t473_line(p_inv, p_n)
     and (v.status = 'held' and p_kind = 'voucher' or l.remaining_amount > 0 and l.category = p_kind)
   order by bv.granted_value desc limit 1;
  if b is null then raise exception 'T473: nothing to move on that line'; end if;
  perform transfer_invoice_unused_benefit(b, p_to, coalesce(pg_temp.t473_id(p_store), (select store_id from invoices where id = p_inv)),
    'T473 move', gen_random_uuid());
end $f$;
-- The invoice form: p_n sessions of S$20 (or S$5 with p_svc 'svc5') for
-- p_cust, paid with the wallet (Credit Package Paid; Premium Bundle Paid with
-- p_wallet 'bwallet') through Record Payment.
create function pg_temp.t473_spend(p_cust uuid, p_n int default 1, p_svc text default 'svc', p_wallet text default 'wallet')
  returns uuid language plpgsql as $f$
declare inv uuid; v_lines jsonb := '[]'; i int;
begin
  for i in 1 .. p_n loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t473_id(p_svc), 'quantity', 1));
  end loop;
  inv := create_invoice_with_details(pg_temp.t473_id('store'), p_cust, v_lines, jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t473_id(p_wallet),
    'amount', (select total_amount from invoices where id = inv))), gen_random_uuid());
  if (select status::text from invoices where id = inv) <> 'paid' then raise exception 'T473: the session paid from credit is not paid'; end if;
  return inv;
end $f$;
-- The session cancelled and "Record refund paid": what its payment took goes
-- back to the lots it came from (refund_invoice_recorded's wallet refund).
create function pg_temp.t473_unspend(p_inv uuid) returns void language plpgsql as $f$
declare due numeric;
begin
  perform cancel_invoice_recorded(p_inv, 'T473 cancel session', gen_random_uuid());
  due := (invoice_financial_position(p_inv)->>'refund_due')::numeric;
  if due is null or due <= 0 then due := (invoice_action_plan(p_inv, 'cancel', '[]')->>'refund_due')::numeric; end if;
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('amount', due)), pg_temp.t473_sources(p_inv, due), '[]'::jsonb,
    'T473 refund paid', gen_random_uuid());
end $f$;
-- The Finance panel's Correct payment on a session's wallet payment: the
-- date only ('date'), a smaller amount ('amount', S$5 less), or another
-- method ('cash').
create function pg_temp.t473_fix(p_inv uuid, p_how text) returns void language plpgsql as $f$
declare p invoice_payments%rowtype;
begin
  select * into p from invoice_payments where invoice_id = p_inv and entry_kind in ('receipt', 'correction_replacement')
     and not exists (select 1 from invoice_payments q where q.corrects_payment_id = invoice_payments.id and q.entry_kind = 'correction_reversal')
   order by created_at desc, id desc limit 1;
  perform correct_invoice_payment(p.id,
    case p_how when 'amount' then p.amount - 5 else p.amount end,
    sg_today() - 1,
    case p_how when 'cash' then pg_temp.t473_id('pm') else p.payment_method_id end,
    'T473 correct payment ' || p_how, gen_random_uuid());
end $f$;
-- A special document's wallet payment as pay_special_with_credit records it
-- (a stand-in: no page calls that function, and no credit category allows a
-- special document today, purchase_category): p_amount off the customer's
-- largest lot ('use', its allocations), so refund_special_credit, the real
-- one, gives it back.
create function pg_temp.t473_special(p_cust uuid, p_kind text, p_doc uuid, p_amount numeric) returns void language plpgsql as $f$
declare l customer_credit_lots%rowtype; e uuid;
begin
  select * into l from customer_credit_lots where customer_id = p_cust and status = 'active' and remaining_amount >= p_amount
   order by remaining_amount desc, id limit 1 for update;
  insert into customer_credit_ledger(wallet_id, customer_id, entry_type, category, amount, lot_id, source_type, source_record_id, store_id, note, created_by)
  values (l.wallet_id, p_cust, 'use', l.category, p_amount, l.id, p_kind, p_doc, l.store_id, 'T473 special', auth.uid()) returning id into e;
  update customer_credit_lots set remaining_amount = remaining_amount - p_amount, updated_at = now() where id = l.id;
  insert into customer_credit_allocations(ledger_entry_id, lot_id, customer_id, amount) values (e, l.id, p_cust, p_amount);
  insert into special_credit_allocations(doc_kind, doc_id, customer_id, lot_id, category, amount, created_by)
  values (p_kind, p_doc, p_cust, l.id, l.category, p_amount, auth.uid());
end $f$;
-- The guided Refund in full / Cancel as an Owner confirms it, with a reason
-- for every override the plan asks for, the money recorded as paid back (or,
-- with p_record false, not: "Record refund paid" left unticked).
create function pg_temp.t473_guided(p_inv uuid, p_action text, p_record boolean default true) returns void language plpgsql as $f$
declare plan jsonb; req jsonb; ov jsonb;
begin
  plan := invoice_action_plan(p_inv, p_action, '[]');
  req := request_invoice_action_v2(p_inv, p_action, '[]', 'T473 ' || p_action, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
           then jsonb_build_object('code', o->>'code', 'reason', 'T473 override', 'amount', (o->>'default_amount')::numeric)
           else jsonb_build_object('code', o->>'code', 'reason', 'T473 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan->'overrides_required', '[]')) o;
  perform resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'T473 ' || p_action, plan->>'plan_hash', ov, null, p_record);
end $f$;


-- ── What the records say ────────────────────────────────────────────────────
-- The lots an invoice's records name: its benefit values, its sale's lots, a
-- split's issued lot, released credit (credit_package_progress_lots) and,
-- 473, the lots a release record's chain reaches (credit_lot_chain: a
-- merge's or customer change's reissue of a lot released before full
-- payment, which the record keeps naming by its first lot; every reader of
-- the record follows the chain: Cancel's write-off, 471's hold,
-- capture_invoice_benefit_values).
create function pg_temp.t473_named(p_inv uuid) returns setof uuid language sql as $f$
  select lot_id from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
  union select x from credit_package_sales s, unnest(array[s.credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select x from premium_bundle_sales s, unnest(array[s.paid_credit_lot_id, s.bonus_credit_lot_id]) x where s.invoice_id = p_inv and x is not null
  union select issued_lot_id from invoice_credit_splits where invoice_id = p_inv and issued_lot_id is not null
  union select lot_id from credit_package_progress_lots where invoice_id = p_inv
  union select x from credit_package_progress_lots pl, unnest(credit_lot_chain(pl.lot_id)) x where pl.invoice_id = p_inv $f$;
-- The invoice's lot family (the critic's 6): every lot its records name and
-- each Move's two lots (from the Move's ledger rows), the lots each replaced
-- and every lot reissued from any of them.
create function pg_temp.t473_family(p_inv uuid) returns setof uuid language sql as $f$
  with recursive seed as (
    select x as id from pg_temp.t473_named(p_inv) x
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
create function pg_temp.t473_behind(p_inv uuid) returns setof uuid language sql as $f$
  with recursive c(id, n) as (
    select lot_id, 0 from invoice_benefit_values where invoice_id = p_inv and lot_id is not null
    union select p.id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
            join customer_credit_lots p on p.id = l.reassigned_from_lot_id
             and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
           where c.n < 12)
  select distinct id from c $f$;
-- How many lots back a lot's chain goes (reassigned_from_lot_id).
create function pg_temp.t473_depth(p_lot uuid) returns int language sql as $f$
  with recursive c(id, n) as (select p_lot, 0 union all
    select l.reassigned_from_lot_id, c.n + 1 from c join customer_credit_lots l on l.id = c.id
     where l.reassigned_from_lot_id is not null and c.n < 40)
  select max(n) from c $f$;
-- A lot's balance by its ledger rows: credit added (grants, increases,
-- credit returned: the 'reverse' rows that put credit back, as the
-- statement reads them, and 'rental_late_fee'), less credit taken (uses,
-- decreases, real reversals).
create function pg_temp.t473_ledger_balance(p_lot uuid) returns numeric language sql as $f$
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
create function pg_temp.t473_invariants(p_inv uuid) returns text language plpgsql as $f$
declare probs text := ''; l record; root record; v uuid; st text := (select status::text from invoices where id = p_inv);
begin
  for l in select cl.* from customer_credit_lots cl where cl.id in (select pg_temp.t473_family(p_inv)) loop
    if l.remaining_amount > 0 and l.id not in (select pg_temp.t473_named(p_inv)) then
      probs := probs || format(' S$%s on a lot no record names (%s);', l.remaining_amount, (select full_name from customers where id = l.customer_id)); end if;
    if l.id not in (select pg_temp.t473_named(p_inv)) and l.id not in (select pg_temp.t473_behind(p_inv))
       and (exists (select 1 from invoice_line_credit_allocations a where a.lot_id = l.id and a.amount > coalesce(a.reversed_amount, 0))
            or exists (select 1 from special_credit_allocations s where s.lot_id = l.id and s.amount > coalesce(s.reversed_amount, 0))) then
      probs := probs || ' a sale paid from a lot no record names can still be refunded (its credit would stay there);'; end if;
    if pg_temp.t473_ledger_balance(l.id) <> l.remaining_amount then
      probs := probs || format(' lot holds %s, its ledger %s;', l.remaining_amount, pg_temp.t473_ledger_balance(l.id)); end if;
    if pg_temp.t473_depth(l.id) > 12 then probs := probs || format(' chain %s lots deep;', pg_temp.t473_depth(l.id)); end if;
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
  if st = 'refunded' and (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t473_family(p_inv))) > 0 then
    probs := probs || format(' refunded, but S$%s of its credit is still held;',
      (select sum(remaining_amount) from customer_credit_lots where id in (select pg_temp.t473_family(p_inv)))); end if;
  return probs;
end $f$;
-- Credit left on the invoice's family once Cancel has run, the Cancel undone
-- (0 when Cancel takes it all back from whoever holds it); null when the
-- invoice cannot be cancelled now, -1 when Cancel is refused.
create function pg_temp.t473_cancel_left(p_inv uuid) returns numeric language plpgsql as $f$
declare v numeric;
begin
  if (select status::text from invoices where id = p_inv) not in ('paid', 'partially_paid', 'unpaid') then return null; end if;
  begin
    perform cancel_invoice_recorded(p_inv, 'T473 probe', gen_random_uuid());
    perform pg_temp.t473_commit();
    v := (select coalesce(sum(remaining_amount), 0) from customer_credit_lots where id in (select pg_temp.t473_family(p_inv)));
    raise exception using errcode = 'P0461', message = v::text;
  exception when sqlstate 'P0461' then return sqlerrm::numeric;
            when others then return -1;
  end;
end $f$;
create function pg_temp.t473_codes(p_inv uuid, p_action text) returns text language plpgsql as $f$
begin
  return (select coalesce(string_agg(o->>'code', ',' order by o->>'code'), '-')
            from jsonb_array_elements(coalesce(invoice_action_plan(p_inv, p_action, '[]')->'overrides_required', '[]')) o);
exception when others then return 'ERR';
end $f$;
create function pg_temp.t473_due(p_inv uuid, p_action text) returns numeric language plpgsql as $f$
begin
  return (invoice_action_plan(p_inv, p_action, '[]')->>case when p_action = 'cancel' then 'refund_due' else 'refund_amount' end)::numeric;
exception when others then return null;
end $f$;
-- The invoice's money: what is owed back (cancel_refund_owed), the Finance
-- panel's refund due, net received and kept for what was used, what a
-- refund by line can still pay back (the refund options' max_refund, every
-- benefit) and Cancel's refund due (the plan's).
create function pg_temp.t473_money(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_build_object('owed', i.cancel_refund_owed,
    'due', (invoice_financial_position(i.id)->>'refund_due')::numeric,
    'net', (invoice_financial_position(i.id)->>'net_received')::numeric,
    'kept', (invoice_financial_position(i.id)->>'kept_for_used')::numeric,
    'by_line', (select coalesce(sum((b->>'max_refund')::numeric), 0)
                  from jsonb_array_elements(invoice_refund_options_before_sessions(i.id)->'benefits') b),
    'plan_due', pg_temp.t473_due(i.id, 'cancel'))
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
create function pg_temp.t473_role(p_pre text, p_r text) returns uuid language plpgsql as $f$
begin
  return coalesce(pg_temp.t473_id(p_pre || '/' || p_r), pg_temp.t473_cust(p_pre || '/' || p_r));
end $f$;
-- One step of a case (one app call, then what its commit does). Null, or
-- the step and the refusal; a refused step changes nothing.
create function pg_temp.t473_step(p_pre text, p_st text) returns text language plpgsql as $f$
declare w text[] := regexp_split_to_array(btrim(p_st), '\s+'); inv uuid := pg_temp.t473_id(p_pre || '/inv'); x uuid; i int; n int;
begin
  case w[1]
  when 'sale' then
    perform pg_temp.t473_put(p_pre || '/inv', pg_temp.t473_sale(pg_temp.t473_role(p_pre, w[2]), string_to_array(w[3], ','), w[4]::numeric));
  when 'saled' then
    perform pg_temp.t473_put(p_pre || '/inv', pg_temp.t473_sale(pg_temp.t473_role(p_pre, w[2]), string_to_array(w[3], ','), null, 2, w[4]::numeric));
  when 'sale2' then
    perform pg_temp.t473_put(p_pre || '/inv2', pg_temp.t473_sale(pg_temp.t473_role(p_pre, w[2]), array['cp']));
  when 'pay' then perform pg_temp.t473_pay(inv);
  -- 473: Record Payment of an amount (a further part payment)
  when 'payp' then
    perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t473_id('pm'),
      'amount', w[2]::numeric)), gen_random_uuid());
  when 'back' then
    perform pg_temp.t473_back(inv, w[2]::int, case when w[3] = 'all' then null else w[3]::numeric end,
                              case when w[4] is not null then pg_temp.t473_role(p_pre, w[4]) end);
  when 'move' then
    perform pg_temp.t473_move(inv, w[2]::int, pg_temp.t473_role(p_pre, w[3]),
      case when w[4] in ('bonus', 'voucher') then w[4] else 'paid' end,
      case when 'store2' = any (w) then 'store2' end);
  when 'cancel' then perform cancel_invoice_recorded(inv, 'T473 cancel', gen_random_uuid());
  when 'reopen' then perform reopen_invoice(inv, 'T473 reopen', gen_random_uuid());
  when 'wait' then
    perform cancel_invoice_recorded(inv, 'T473 cancel', gen_random_uuid());
    for i in 1 .. (select count(*)::int from invoice_items where invoice_id = inv) loop
      perform pg_temp.t473_back(inv, i);
    end loop;
    perform reopen_invoice(inv, 'T473 reopen', gen_random_uuid());
  when 'refundall' then perform pg_temp.t473_guided(inv, 'refund_full');
  when 'change' then
    perform pg_temp.t473_change(inv, pg_temp.t473_role(p_pre, w[2]), case when 'keep' = any (w) then 'keep' else 'transfer' end,
                                case when 'store2' = any (w) then 'store2' end);
  when 'merge' then perform pg_temp.t473_merge(pg_temp.t473_role(p_pre, w[2]), pg_temp.t473_role(p_pre, w[3]));
  when 'spend' then
    n := (select count(*) from t473 where k ~ ('^' || p_pre || '/S[0-9]+$')) + 1;
    perform pg_temp.t473_put(p_pre || '/S' || n,
      pg_temp.t473_spend(pg_temp.t473_role(p_pre, w[2]), case when w[3] ~ '^[0-9]+$' then w[3]::int else 1 end,
        case when 'svc5' = any (w) then 'svc5' else 'svc' end,
        case when 'bwallet' = any (w) then 'bwallet' when 'cbonus' = any (w) then 'cbonus' else 'wallet' end));
  when 'unspend' then perform pg_temp.t473_unspend(pg_temp.t473_id(p_pre || '/' || w[2]));
  when 'fix' then perform pg_temp.t473_fix(pg_temp.t473_id(p_pre || '/' || w[2]), w[3]);
  when 'delete' then
    x := pg_temp.t473_role(p_pre, w[2]);
    perform delete_customer(x, (select full_name from customers where id = x), 'T473 delete');
  when 'special' then
    n := (select count(*) from t473 where k ~ ('^' || p_pre || '/D[0-9]+$')) + 1; x := gen_random_uuid();
    perform pg_temp.t473_put(p_pre || '/D' || n, x);
    perform pg_temp.t473_put(p_pre || '/D' || n || '/kind:' || w[3], null);
    perform pg_temp.t473_special(pg_temp.t473_role(p_pre, w[2]), w[3], x, w[4]::numeric);
  when 'unspecial' then
    perform refund_special_credit((select split_part(k, 'kind:', 2) from t473 where k like p_pre || '/' || w[2] || '/kind:%'),
                                  pg_temp.t473_id(p_pre || '/' || w[2]));
  when 'reverse' then
    if w[2] = 'closed' then
      -- the released lot a Cancel's write-off closed, once a refund opened it again
      perform reverse_credit_lot(pg_temp.t473_closed_lot(inv), 'T473 reversal');
    else
      x := pg_temp.t473_role(p_pre, w[2]);
      perform reverse_credit_lot((select id from customer_credit_lots where customer_id = x and remaining_amount > 0
                                   order by remaining_amount desc, id limit 1), 'T473 reversal');
    end if;
  when 'guidedcancel' then perform pg_temp.t473_guided(inv, 'cancel');
  when 'guidedkeep' then perform pg_temp.t473_guided(inv, 'cancel', false);
  when 'backo' then
    x := pg_temp.t473_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x,
        'amount', invoice_discounted_line_value(x),
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', pg_temp.t473_own(inv), 'amount', w[3]::numeric)),
        'override', jsonb_build_object('code', 'larger_refund', 'reason', 'T473 larger refund', 'amount', invoice_discounted_line_value(x)))),
      pg_temp.t473_sources(inv, invoice_net_received(inv)), '[]'::jsonb, 'T473 larger refund', gen_random_uuid());
  when 'refundpaid' then
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('amount',
        coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric))),
      pg_temp.t473_sources(inv, coalesce(nullif((invoice_financial_position(inv)->>'refund_due')::numeric, 0), (invoice_action_plan(inv, 'cancel', '[]')->>'refund_due')::numeric)),
      '[]'::jsonb, 'T473 refund paid', gen_random_uuid());
  when 'backx' then
    x := pg_temp.t473_line(inv, w[2]::int);
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x,
        'amount', invoice_discounted_line_value(x) - coalesce((select sum((e->>'amount')::numeric) from invoice_refunds r,
             jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e where r.invoice_id = inv and e->>'invoice_item_id' = x::text), 0),
        'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', b->>'id', 'amount', (b->>'max_refund')::numeric))
                       from jsonb_array_elements(invoice_refund_options_before_sessions(inv)->'benefits') b
                      where b->>'invoice_item_id' = x::text and (b->>'max_refund')::numeric > 0),
        'override', jsonb_build_object('code', 'larger_refund', 'reason', 'T473 larger refund',
          'amount', invoice_discounted_line_value(x) - coalesce((select sum((e->>'amount')::numeric) from invoice_refunds r,
             jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) e where r.invoice_id = inv and e->>'invoice_item_id' = x::text), 0)))),
      pg_temp.t473_sources(inv, invoice_net_received(inv)), '[]'::jsonb, 'T473 larger refund', gen_random_uuid());
  when 'legacy' then
    update invoices set status = w[2]::invoice_status where id = inv;
  when 'repair' then perform repair_credit_package_progress_lots();
  when 'repair328' then perform pg_temp.t473_repair328(inv);
  else raise exception 'T473: unknown step %', p_st;
  end case;
  perform pg_temp.t473_commit();
  return null;
exception when others then
  return btrim(p_st) || ': ' || sqlerrm;
end $f$;
-- What a case ends with: the invoice's status and money, who holds what
-- (credit, '/n' held vouchers), the plans' codes and refund due (Cancel's
-- refund due; Refund in full's amount), the refusal that stopped it, what is
-- wrong with its credit, and the credit Cancel would leave behind.
create function pg_temp.t473_outcome(p_pre text, p_err text) returns jsonb language sql as $f$
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
              from t473 t where t.k like p_pre || '/%' and split_part(t.k, '/', 4) = ''
                and split_part(t.k, '/', 3) !~ '^(inv|inv2|S[0-9]+|D[0-9]+|err)$'),
    'cancel', pg_temp.t473_codes(i.id, 'cancel'),
    'due', pg_temp.t473_due(i.id, 'cancel'),
    'refund', pg_temp.t473_codes(i.id, 'refund_full'),
    'rdue', pg_temp.t473_due(i.id, 'refund_full'),
    'error', p_err,
    -- 473: the invoice's customer now (its role in the case), and what the
    -- list of what a customer change can move says of its credit: the rows
    -- blocking it (with why) and the rows that would move.
    'customer', (select split_part(t.k, '/', 3) from invoices iv join t473 t on t.id = iv.customer_id and t.k like p_pre || '/%'
                  where iv.id = i.id limit 1),
    'blocked', (select coalesce(string_agg(x.description || ' (' || coalesce(x.blocked_reason, '-') || ')', '; ' order by x.description), '-')
                  from invoice_transferable_benefits(i.id) x where x.kind = 'credit' and x.blocking),
    'movable', (select coalesce(string_agg(x.description, '; ' order by x.description), '-')
                  from invoice_transferable_benefits(i.id) x where x.kind = 'credit' and x.movable),
    'invariants', pg_temp.t473_invariants(i.id),
    'cancel_left', pg_temp.t473_cancel_left(i.id))
    from (select pg_temp.t473_id(p_pre || '/inv') as id) i $f$;
-- A case's steps p_from to p_to (all by default), stopping at a refusal;
-- with p_to null, its outcome (kept in t473_res under p_phase).
create temp table t473_err(pre text primary key, err text);
create function pg_temp.t473_run(p_phase text, p_case text, p_steps text, p_from int default 1, p_to int default null)
  returns jsonb language plpgsql as $f$
declare v_pre text := p_phase || '/' || p_case; st text[] := string_to_array(p_steps, ';'); i int; v_err text; v_out jsonb;
begin
  v_err := (select e.err from t473_err e where e.pre = v_pre);
  for i in p_from .. least(coalesce(p_to, cardinality(st)), cardinality(st)) loop
    exit when v_err is not null;
    continue when btrim(st[i]) = '';
    v_err := pg_temp.t473_step(v_pre, st[i]);
  end loop;
  insert into t473_err values (v_pre, v_err) on conflict (pre) do update set err = excluded.err;
  if p_to is not null then return null; end if;
  v_out := pg_temp.t473_outcome(v_pre, v_err);
  insert into t473_res values (p_phase, p_case, v_out) on conflict (phase, k) do update set v = excluded.v;
  return v_out;
end $f$;

-- Whether an outcome has what is expected: each key equal ('holds' as a
-- containment of who holds what), a key ending in '~' as a LIKE pattern of
-- that key's text.
create function pg_temp.t473_meets(p_out jsonb, p_exp jsonb) returns boolean language sql as $f$
  select coalesce(bool_and(case
           when e.key like '%~' then coalesce(p_out->>left(e.key, -1), '') like (e.value #>> '{}')
           when e.key = 'holds' then coalesce(p_out->'holds', '{}') @> e.value
           when jsonb_typeof(e.value) = 'number' then coalesce((p_out->>e.key)::numeric = (e.value #>> '{}')::numeric, false)
           else (p_out->e.key) is not distinct from e.value end), true)
    from jsonb_each(p_exp) e $f$;
-- What differs between an outcome and what is expected (for the FAIL line).
create function pg_temp.t473_diff(p_out jsonb, p_exp jsonb) returns text language sql as $f$
  select string_agg(e.key || ': wanted ' || e.value::text || ', got ' || coalesce(p_out->left(e.key, case when e.key like '%~' then -1 else 1000 end), 'null')::text, '; ')
    from jsonb_each(p_exp) e where not pg_temp.t473_meets(p_out, jsonb_build_object(e.key, e.value)) $f$;

-- ── 471's own readings ──────────────────────────────────────────────────────
-- The held-back reason (470's, which 471 writes too), and its rows on a lot.
create function pg_temp.t473_held(p_lot uuid) returns numeric language sql as $f$
  select coalesce(sum(e.amount), 0) from customer_credit_ledger e
   where e.lot_id = p_lot and e.entry_type = 'adjust_decrease' and e.source_type = 'invoice_cancel_benefit'
     and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now' $f$;
-- (B) what is held back on a lot of credit released before full payment
-- (Cancel's write-off's kind of row, 471's reason).
create function pg_temp.t473_held_rel(p_lot uuid) returns numeric language sql as $f$
  select coalesce(sum(e.amount), 0) from customer_credit_ledger e
   where e.lot_id = p_lot and e.entry_type = 'adjust_decrease' and e.source_type in ('invoice_cancel_released_credit', 'invoice_refund_released_credit')
     and e.reason = 'Held back by the invoice''s cancellation: credit released before it was paid in full' $f$;
-- The release record of an invoice (its first; the cases have one) and its lot.
create function pg_temp.t473_rel_lot(p_inv uuid) returns uuid language sql as $f$
  select lot_id from credit_package_progress_lots where invoice_id = p_inv order by created_at, lot_id limit 1 $f$;
-- The lot of an invoice's release record that a Cancel's write-off closed
-- (locked; after a reopening the release record has a second, open lot).
create function pg_temp.t473_closed_lot(p_inv uuid) returns uuid language sql as $f$
  select pl.lot_id from credit_package_progress_lots pl join customer_credit_lots l on l.id = pl.lot_id
   where pl.invoice_id = p_inv and l.is_locked order by pl.lot_id limit 1 $f$;
create function pg_temp.t473_held_n(p_lot uuid) returns int language sql as $f$
  select count(*)::int from customer_credit_ledger e
   where e.lot_id = p_lot and e.entry_type = 'adjust_decrease' and e.source_type = 'invoice_cancel_benefit'
     and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now' $f$;
-- The package's own benefit row (the one an Owner did not move in), and the
-- lot it names.
create function pg_temp.t473_own(p_inv uuid) returns uuid language sql as $f$
  select bv.id from invoice_benefit_values bv
   where bv.invoice_id = p_inv and bv.lot_id is not null
     and not exists (select 1 from invoice_benefit_transfers t where t.replacement_benefit_id = bv.id)
   order by bv.created_at, bv.id limit 1 $f$;
create function pg_temp.t473_own_lot(p_inv uuid) returns uuid language sql as $f$
  select lot_id from invoice_benefit_values where id = pg_temp.t473_own(p_inv) $f$;
-- Unapplied queue rows of an invoice on a lot (count, sum, requests).
create function pg_temp.t473_waiting(p_inv uuid, p_lot uuid) returns text language sql as $f$
  select count(*) || '/' || coalesce(sum(q.amount), 0) || '/' || count(distinct q.request_id)
    from invoice_reopen_benefits q join customer_credit_ledger e on e.id = q.source_ledger_id
   where q.invoice_id = p_inv and q.applied_at is null and e.lot_id = p_lot $f$;
-- The triggers on invoices (their definitions, by name; search_path public,
-- as the migration reads them).
create function pg_temp.t473_inv_triggers() returns text language plpgsql as $f$
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
create function pg_temp.t473_repair328(p_inv uuid) returns uuid language plpgsql as $f$
declare r record; pk credit_packages%rowtype; v_new uuid; v_rem numeric;
begin
  select l.*, it.id as invoice_item_id, it.invoice_id, it.credit_package_id into r
    from credit_package_progress_lots pl
    join customer_credit_lots l on l.id = pl.lot_id
    join invoice_items it on it.id = pl.invoice_item_id
   where pl.invoice_id = p_inv order by pl.created_at, pl.lot_id limit 1;
  if r.id is null or r.remaining_amount <= 0 then raise exception 'T473: no released lot holding credit to repair'; end if;
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


-- ── 473's cases ─────────────────────────────────────────────────────────────
-- (k, kind, steps, what 473 gives). kind: 'fixed' (before 473 it ends
-- otherwise: the fault is reproduced first), 'control' (the same with and
-- without 473, every key of the outcome), 'known' (a NOT COVERED item,
-- checked as it is: the same with and without 473 but for what the list
-- says at its end, which K checks). Every case also checks the invariants
-- and that Cancel takes everything back from whoever holds it. A refused
-- step undoes itself (a customer it made is not there afterwards).
create temp table t473_cases(k text primary key, kind text not null, steps text not null, expect jsonb not null, ord serial);
insert into t473_cases(k, kind, steps, expect) values
-- 471's K9 and the same never cancelled: refused with the words of the
-- package paid in full; nothing moves.
('TQ', 'fixed', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; change B',
  '{"holds":{"A":"60.00"},"status":"paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","movable":"-","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve each one through the benefit transfer review before reassigning.%"}'),
('TQp', 'fixed', 'sale A cp 40; spend A; spend A; pay; change B',
  '{"holds":{"A":"60.00"},"status":"paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","movable":"-","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
-- S1 only before the cancel: S$20 released again at the reopening, so two
-- lots hold credit beside the spent one; both are named (NOT COVERED 5).
('TQ1', 'fixed', 'sale A cp 40; spend A; cancel; reopen; pay; change B',
  '{"holds":{"A":"80.00"},"status":"paid","customer":"A","blocked":"Paid credit 20.00 (Partly spent); Paid credit 60.00 (Partly spent)","movable":"-","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit %0.00 (Partly spent); Paid credit %0.00 (Partly spent). Resolve%"}'),
-- a second change: after the first (refused now at the first), after a
-- 'keep' change (refused at the second, as for the package paid in full).
('TQ2', 'fixed', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; change B; change C',
  '{"holds":{"A":"60.00"},"status":"paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
('TQk', 'fixed', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; change B keep; change C',
  '{"holds":{"A":"60.00","B":"0.00"},"status":"paid","customer":"B","blocked":"Paid credit 60.00 (Partly spent)","error~":"change C: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
-- the Premium Bundle and the Bonus package: the paid credit blocks; the
-- Bonus lot, judged apart as always, still reads as movable.
('TQv', 'fixed', 'sale A pbv 40; spend A 1 svc bwallet; spend A 1 svc bwallet; cancel; reopen; pay; change B',
  '{"holds":{"A":"100.00/2"},"status":"paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","movable":"Bonus credit 40.00","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
('TQb', 'fixed', 'sale A cpb 40; spend A; spend A; cancel; reopen; pay; change B',
  '{"holds":{"A":"70.00"},"status":"paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","movable":"Bonus credit 10.00","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
-- the buyer merged into K, or the customer changed to C, before the
-- sessions (the lots reissued, the rows following them).
('TQmb', 'fixed', 'sale A cp 40; merge K A; spend K; spend K; cancel; reopen; pay; change B',
  '{"holds":{"A":"0.00","K":"60.00"},"status":"paid","customer":"K","blocked":"Paid credit 60.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
('TQcb', 'fixed', 'sale A cp 40; change C; spend C; spend C; cancel; reopen; pay; change B',
  '{"holds":{"A":"0.00","C":"60.00"},"status":"paid","customer":"C","blocked":"Paid credit 60.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
-- an Owner's Move of the S$60 to A at another store (463's decision 2: the
-- change takes it along), then the change: the moved lot blocks.
('TQms', 'fixed', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; move 1 A store2; change B',
  '{"holds":{"A":"60.00"},"status":"paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","movable":"-","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
-- an Owner's reversal of the released lot reads as used, as on one lot (RVc).
('TQr', 'fixed', 'sale A cp 40; spend A 1 svc5; reverse A; pay; change B',
  '{"holds":{"A":"60.00"},"status":"paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
('TQr0', 'fixed', 'sale A cp 40; reverse A; pay; change B',
  '{"holds":{"A":"60.00"},"status":"paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
-- paid in part twice, not settled: the second release's lot blocks.
('W2', 'fixed', 'sale A cp 20; spend A; payp 20; change B',
  '{"holds":{"A":"20.00"},"status":"partially_paid","customer":"A","blocked":"Paid credit 20.00 (Partly spent)","movable":"-","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 20.00 (Partly spent). Resolve%"}'),
('W2m', 'fixed', 'sale A cp 20; merge K A; spend K; payp 20; change B',
  '{"holds":{"A":"0.00","K":"20.00"},"status":"partially_paid","customer":"K","blocked":"Paid credit 20.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 20.00 (Partly spent). Resolve%"}'),
('W2k', 'fixed', 'sale A cp 20; spend A; payp 20; change C keep; change B',
  '{"holds":{"A":"20.00","C":"0.00"},"status":"partially_paid","customer":"C","blocked":"Paid credit 20.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 20.00 (Partly spent). Resolve%"}'),
-- refused before 473 too (the released lot partly spent, S$20 left); now
-- the untouched S$60 lot is named as well.
('TU1', 'fixed', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; unspend S1; change B',
  '{"holds":{"A":"80.00"},"status":"paid","customer":"A","blocked":"Paid credit 20.00 (Partly spent); Paid credit 60.00 (Partly spent)","movable":"-","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit %0.00 (Partly spent); Paid credit %0.00 (Partly spent). Resolve%"}'),
('TQp1', 'fixed', 'sale A cp 40; spend A; pay; change B',
  '{"holds":{"A":"80.00"},"status":"paid","customer":"A","blocked":"Paid credit 20.00 (Partly spent); Paid credit 60.00 (Partly spent)","movable":"-","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit %0.00 (Partly spent); Paid credit %0.00 (Partly spent). Resolve%"}'),
-- K9's state reached otherwise: a merge of A refused (445's NOT COVERED 1,
-- before and after); K the kept record; a 'keep' change to B (it still
-- passes): the list now says a 'transfer' change is refused.
('TQm', 'fixed', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; merge K A',
  '{"holds":{"A":"60.00"},"status":"paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","movable":"-","error~":"merge K A: Credit allocations cannot be changed once recorded%"}'),
('TQmk', 'fixed', 'sale A cp 40; merge K A; spend K; spend K; cancel; reopen; pay',
  '{"holds":{"A":"0.00","K":"60.00"},"status":"paid","customer":"K","blocked":"Paid credit 60.00 (Partly spent)","movable":"-","error":null}'),
('TQkp', 'fixed', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; change B keep',
  '{"holds":{"A":"60.00","B":"0.00"},"status":"paid","customer":"B","blocked":"Paid credit 60.00 (Partly spent)","movable":"-","error":null}'),
-- Controls: the same with and without 473.
('TQc', 'control', 'sale A cp; spend A; spend A; change B',
  '{"holds":{"A":"60.00"},"status":"paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
('TQcp', 'control', 'sale A cp; spend A; spend A; cancel; reopen; pay; change B',
  '{"holds":{"A":"60.00"},"status":"paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
('TQck', 'control', 'sale A cp; spend A; spend A; change B keep; change C',
  '{"holds":{"A":"60.00","B":"0.00"},"status":"paid","customer":"B","error~":"change C: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
('TVc', 'control', 'sale A pbv; spend A 1 svc bwallet; spend A 1 svc bwallet; change B',
  '{"holds":{"A":"100.00/2"},"status":"paid","blocked":"Paid credit 60.00 (Partly spent)","movable":"Bonus credit 40.00","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
('TBc', 'control', 'sale A cpb; spend A; spend A; change B',
  '{"holds":{"A":"70.00"},"status":"paid","blocked":"Paid credit 60.00 (Partly spent)","movable":"Bonus credit 10.00","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}'),
('TQ0', 'control', 'sale A cp 40; cancel; reopen; pay; change B',
  '{"holds":{"A":"0.00","B":"100.00"},"status":"paid","customer":"B","blocked":"-","error":null}'),
('TQ00', 'control', 'sale A cp 40; pay; change B',
  '{"holds":{"A":"0.00","B":"100.00"},"status":"paid","customer":"B","blocked":"-","error":null}'),
('W2c', 'control', 'sale A cp 20; payp 20; change B',
  '{"holds":{"A":"0.00","B":"40.00"},"status":"partially_paid","customer":"B","blocked":"-","error":null}'),
('TU', 'control', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; unspend S1; unspend S2; change B',
  '{"holds":{"A":"0.00","B":"100.00"},"status":"paid","customer":"B","blocked":"-","error":null}'),
('TQn', 'control', 'sale A cp 40; spend A; change B',
  '{"holds":{"A":"20.00"},"status":"partially_paid","customer":"A","blocked":"Paid credit 20.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 20.00 (Partly spent). Resolve%"}'),
('W2s', 'control', 'sale A cp 20; spend A; payp 20; spend A 1 svc5; change B',
  '{"holds":{"A":"15.00"},"status":"partially_paid","customer":"A","blocked":"Paid credit 15.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 15.00 (Partly spent). Resolve%"}'),
('TQmv', 'control', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; move 1 F; change B',
  '{"holds":{"A":"0.00","B":"0.00","F":"60.00"},"status":"paid","customer":"B","blocked":"-","movable":"-","error":null}'),
('TCsc', 'control', 'sale A cp; spend A; move 1 A store2; change B',
  '{"holds":{"A":"80.00"},"status":"paid","customer":"A","blocked":"Paid credit 80.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 80.00 (Partly spent). Resolve%"}'),
('RVc', 'control', 'sale A cp; spend A; reverse A; unspend S1; change B',
  '{"holds":{"A":"20.00"},"status":"paid","customer":"A","blocked":"Paid credit 20.00 (Partly spent)","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 20.00 (Partly spent). Resolve%"}'),
('TQcx', 'control', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; cancel',
  '{"holds":{"A":"0.00"},"status":"cancelled","blocked":"-","movable":"-","error":null}'),
-- Known (473's NOT COVERED): the same with and without 473 but for what the
-- list says at the end (K checks it).
('TQn2', 'known', 'sale A cp 40; spend A; spend A; change B; pay',
  '{"holds":{"A":"0.00","B":"60.00"},"status":"paid","customer":"B","error":null}'),
('K1', 'known', 'sale A cp 40; change B keep; pay',
  '{"holds":{"A":"40.00","B":"60.00"},"status":"paid","customer":"B","error":null}'),
('K2', 'known', 'sale A cp 20; spend A; payp 20; change B keep; pay',
  '{"holds":{"A":"20.00","B":"60.00"},"status":"paid","customer":"B","error":null}'),
('TQcr', 'known', 'sale A cp 40; spend A; spend A; cancel; reopen; pay; cancel; change B; reopen; pay',
  '{"holds":{"A":"0.00","B":"60.00"},"status":"paid","customer":"B","error":null}'),
('TQcc', 'known', 'sale A cp; spend A; spend A; cancel; change B; reopen; pay',
  '{"holds":{"A":"0.00","B":"60.00"},"status":"paid","customer":"B","error":null}');
-- 476 (the Owner, 27 Oct 2026: "Same as paid-in-full"; NOT COVERED 1 and 2):
-- where 476 is in, TQn2's 'transfer' change is refused as "Partly spent" (the
-- credit still to be released listed, blocking: nothing moves, the payment
-- after it is not made), and K1's and K2's later payment gives the credit to
-- whoever holds the package's benefits (A), not to the invoice's new
-- customer: they are checked as 476 settles them. Where 476 is in, 473 is in
-- too, so R never runs (-v nomig=1) and nothing compares them with before
-- 473.
update t473_cases set kind = 'fixed', expect = case k
    when 'TQn2' then '{"holds":{"A":"0.00"},"status":"partially_paid","customer":"A","blocked":"Paid credit 60.00 (Partly spent)","movable":"-","error~":"change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve each one through the benefit transfer review before reassigning.%"}'
    when 'K1' then '{"holds":{"A":"100.00","B":"0.00"},"status":"paid","customer":"B","error":null}'
    else '{"holds":{"A":"80.00","B":"0.00"},"status":"paid","customer":"B","error":null}' end::jsonb
 where k in ('TQn2', 'K1', 'K2') and pg_temp.t473_476_in();

-- States made for the header's query (each where a 'transfer' change would
-- be tried next): its reasons and counts ('-': listed nowhere).
create temp table t473_qstates(k text primary key, steps text not null, expect text not null);
insert into t473_qstates values
  ('QA', 'sale A cp 40; spend A; spend A; cancel; reopen; pay', '1:1'),
  ('QB', 'sale A cp 40; spend A; spend A; pay', '1:1'),
  ('QC', 'sale A cp 20; spend A; payp 20', '2:1'),
  ('QD', 'sale A cp 40; spend A; spend A', '3:1'),
  ('QE', 'sale A cp 40; change B keep; pay', '4:1'),
  ('QF', 'sale A cp 40; spend A; spend A; pay; change B', '1:1,4:1'),
  ('QG', 'sale A cp 40; pay', '-'),
  ('QH', 'sale A cp; spend A; spend A', '-'),
  ('QI', 'sale A cp 40; spend A', '-'),
  ('QJ', 'sale A cp 20; payp 20', '-');

-- The read-only query in 473's header (the same text).
create function pg_temp.t473_header_query() returns table(reason text, invoice_no text, n bigint) language sql as $hq$
with
-- each credit benefit row of an invoice's own (not what an Owner moved
-- to someone else), its lot, and whether 461's test reads it as spent
r as (
  select b.id, b.invoice_id, b.invoice_item_id, l.id as lot_id, l.customer_id, l.category, l.status as lot_status,
         l.remaining_amount, l.original_amount, l.reassigned_from_lot_id, b.cancelled_unused_value,
         l.remaining_amount + b.cancelled_unused_value + public.invoice_benefit_unused_elsewhere(b.id) < b.granted_value as spent,
         i.status::text in ('cancelled', 'refunded')
         or exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = i.id and q.applied_at is null) as held
    from public.invoice_benefit_values b
    join public.customer_credit_lots l on l.id = b.lot_id
    join public.invoices i on i.id = b.invoice_id and i.deleted_at is null
   where not public.invoice_benefit_moved_to_other(b.id)),
-- a settled package line (and credit category) one of whose rows reads as spent
sl as (
  select r.invoice_id, r.invoice_item_id, r.category from r group by 1, 2, 3 having bool_or(r.spent)),
-- release records before settlement (no benefit row names a lot of their chain),
-- with the lot each reaches now (credit_lot_current) and whether it reads as spent
pre as (
  select pl.invoice_id, pl.invoice_item_id, pl.lot_id, pl.released_amount, c.id as cur_id, c.customer_id, c.remaining_amount,
         c.original_amount, c.status as lot_status,
         pl.released_amount > 0 and coalesce(case when c.status = 'active' then c.remaining_amount end, 0) < pl.released_amount as spent
    from public.credit_package_progress_lots pl
    join public.invoices i on i.id = pl.invoice_id and i.deleted_at is null
    join public.customer_credit_lots c on c.id = public.credit_lot_current(pl.lot_id)
   where not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = any (public.credit_lot_chain(pl.lot_id)))),
found(reason, invoice_id, n) as (
  select '1 changes: a settled package line part of whose paid (or bonus) credit was spent, with a lot of it holding credit that a ''transfer'' customer change moves today (untouched, or its own row unspent), and no lot of the invoice holding credit that blocks the change today; from 473 it reads "Partly spent" and the change is refused, as for the same package paid in full (the count is of lots)', r.invoice_id, count(*)
    from r join sl using (invoice_id, invoice_item_id, category)
   where not r.spent and r.lot_status = 'active' and r.remaining_amount > 0
     and (r.remaining_amount = r.original_amount and r.reassigned_from_lot_id is null
          or r.cancelled_unused_value = 0 and not r.held)
     and not public.invoice_benefit_moved_from_spent(r.id)
     and not exists (select 1 from r r2 where r2.invoice_id = r.invoice_id and r2.spent
                      and r2.lot_status = 'active' and r2.remaining_amount > 0)
   group by r.invoice_id
  union all
  select '2 changes: a package paid in part, not settled, with a lot of its released credit holding credit, untouched, beside another release of the same line that was spent; from 473 it reads "Partly spent" and a ''transfer'' customer change is refused (the count is of lots)', p.invoice_id, count(*)
    from pre p
   where not p.spent and p.lot_status = 'active' and p.remaining_amount > 0 and p.remaining_amount = p.original_amount
     and exists (select 1 from pre q where q.invoice_id = p.invoice_id and q.invoice_item_id = p.invoice_item_id and q.spent)
   group by p.invoice_id
  union all
  select '3 for the Owner (not changed by 473: NOT COVERED 1): a package paid in part, not settled, whose released credit was spent with nothing left on its lots and more still to be released: a ''transfer'' change passes, and the next payment''s credit goes to the invoice''s customer, ''transfer'' or ''keep'' (the count is of lines)', p.invoice_id, count(distinct p.invoice_item_id)
    from pre p
    join public.invoice_items it on it.id = p.invoice_item_id and it.credit_issued_at is null
   where p.spent
     and not exists (select 1 from pre q where q.invoice_id = p.invoice_id and q.invoice_item_id = p.invoice_item_id
                      and q.lot_status = 'active' and q.remaining_amount > 0)
     and public.credit_line_paid_entitlement(p.invoice_item_id) > public.credit_package_released_paid_credit(p.invoice_item_id)
   group by p.invoice_id
  union all
  select '4 for the Owner (not changed by 473: NOT COVERED 2 and 6): a package line whose credit is held by more than one customer (a ''transfer'' change before 473 moved the untouched part of a partly spent package, or a ''keep'' change left the released part with the buyer and gave the rest to the new customer): a data fix, or left as it is (the count is of lines)', x.invoice_id, count(*)
    from (select r.invoice_id, r.invoice_item_id from r group by 1, 2 having count(distinct r.customer_id) > 1
          union
          select p.invoice_id, p.invoice_item_id from pre p
           group by 1, 2 having count(distinct p.customer_id) > 1) x
   group by x.invoice_id)
select f.reason, i.invoice_no, f.n
  from found f join public.invoices i on i.id = f.invoice_id
 order by f.reason, i.invoice_no
$hq$;

-- The first run's notice's query in 473's file (its own text).
create function pg_temp.t473_notice_query() returns table(reason int, invoice_id uuid) language sql as $nq$
with
r as (
  select b.id, b.invoice_id, b.invoice_item_id, l.customer_id, l.category, l.status as lot_status,
         l.remaining_amount, l.original_amount, l.reassigned_from_lot_id, b.cancelled_unused_value,
         l.remaining_amount + b.cancelled_unused_value + public.invoice_benefit_unused_elsewhere(b.id) < b.granted_value as spent,
         i.status::text in ('cancelled', 'refunded')
         or exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = i.id and q.applied_at is null) as held
    from public.invoice_benefit_values b
    join public.customer_credit_lots l on l.id = b.lot_id
    join public.invoices i on i.id = b.invoice_id and i.deleted_at is null
   where not public.invoice_benefit_moved_to_other(b.id)),
sl as (
  select r.invoice_id, r.invoice_item_id, r.category from r group by 1, 2, 3 having bool_or(r.spent)),
pre as (
  select pl.invoice_id, pl.invoice_item_id, pl.lot_id, c.customer_id, c.remaining_amount, c.original_amount, c.status as lot_status,
         pl.released_amount > 0 and coalesce(case when c.status = 'active' then c.remaining_amount end, 0) < pl.released_amount as spent
    from public.credit_package_progress_lots pl
    join public.invoices i on i.id = pl.invoice_id and i.deleted_at is null
    join public.customer_credit_lots c on c.id = public.credit_lot_current(pl.lot_id)
   where not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = any (public.credit_lot_chain(pl.lot_id)))),
found(reason, invoice_id) as (
  select 1, r.invoice_id
    from r join sl using (invoice_id, invoice_item_id, category)
   where not r.spent and r.lot_status = 'active' and r.remaining_amount > 0
     and (r.remaining_amount = r.original_amount and r.reassigned_from_lot_id is null
          or r.cancelled_unused_value = 0 and not r.held)
     and not public.invoice_benefit_moved_from_spent(r.id)
     and not exists (select 1 from r r2 where r2.invoice_id = r.invoice_id and r2.spent
                      and r2.lot_status = 'active' and r2.remaining_amount > 0)
  union
  select 2, p.invoice_id from pre p
   where not p.spent and p.lot_status = 'active' and p.remaining_amount > 0 and p.remaining_amount = p.original_amount
     and exists (select 1 from pre q where q.invoice_id = p.invoice_id and q.invoice_item_id = p.invoice_item_id and q.spent)
  union
  select 3, p.invoice_id from pre p
    join public.invoice_items it on it.id = p.invoice_item_id and it.credit_issued_at is null
   where p.spent
     and not exists (select 1 from pre q where q.invoice_id = p.invoice_id and q.invoice_item_id = p.invoice_item_id
                      and q.lot_status = 'active' and q.remaining_amount > 0)
     and public.credit_line_paid_entitlement(p.invoice_item_id) > public.credit_package_released_paid_credit(p.invoice_item_id)
  union
  select 4, x.invoice_id
    from (select r.invoice_id, r.invoice_item_id from r group by 1, 2 having count(distinct r.customer_id) > 1
          union
          select p.invoice_id, p.invoice_item_id from pre p
           group by 1, 2 having count(distinct p.customer_id) > 1) x)
select f.reason, f.invoice_id from found f
$nq$;

-- ===== S. Where it starts =====
create temp table t473_fp(k text primary key, v text);
create function pg_temp.t473_grants(p_without text[] default '{}') returns text language sql as $f$
  select md5(string_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'public'::regnamespace and not (p.proname = any (p_without)) $f$;
create function pg_temp.t473_grant_set(p_sig text) returns text[] language sql as $f$
  select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || p_sig) $f$;
insert into t473_fp values ('start', pg_temp.t473_fingerprint()), ('grants', pg_temp.t473_grants()), ('triggers', pg_temp.t473_inv_triggers());
-- The function 473 changes: BEFORE (production at 471 with 472 in, 26 Oct
-- 2026: 463's AFTER) and AFTER. It adds nothing.
create temp table t473_md5(sig text primary key, before text, after text, after476 text);
insert into t473_md5 values
  ('invoice_transferable_benefits(uuid)', '68736a39ed765ee787242bc62bbaeebb', 'a2332a22fe9975667e848de0d1e4480b',
   -- 476, where it is in (it keeps 473's text, adds a row and judges a lot
   -- of credit released before full payment by its release record: its AFTER)
   '1546de1f83d970424d26e65941f4dcb8');
create function pg_temp.t473_at(p_col text) returns boolean language plpgsql as $f$
declare p text := current_setting('search_path'); v boolean;
begin
  perform set_config('search_path', 'public', true);
  select bool_and(case when p_col = 'before' then md5(pg_get_functiondef(to_regprocedure('public.' || m.sig))) = m.before
                       else md5(pg_get_functiondef(to_regprocedure('public.' || m.sig)))
                            = case when pg_temp.t473_476_in() then m.after476 else m.after end end) into v
    from t473_md5 m;
  perform set_config('search_path', p, true);
  return v;
end $f$;
do $$ begin
  perform pg_temp.t473_check(pg_temp.t473_462_in() and pg_temp.t473_463_in() and pg_temp.t473_470_in() and pg_temp.t473_471_in()
      and pg_temp.t473_472_in()
      -- (or at 477's AFTER, where 477 is in: it keeps 472's text)
      and md5(pg_get_functiondef('public.credit_given_back_follows(uuid)'::regprocedure))
          in ('f2a7a4d1ca28f0865b14e3f1e5e02bbb', 'a0f2f5ece30be439049dca275802237a'),
    'S 462, 463, 470, 471 and 472 are in, the forwarder at 472''s AFTER or 477''s (473 goes in after 472)');
end $$;
\if :{?nomig}
do $$ begin
  perform pg_temp.t473_check(pg_temp.t473_in() and pg_temp.t473_at('after'), 'S -v nomig=1: 473 is in, as tested');
end $$;
\else
do $$ begin
  perform pg_temp.t473_check(not pg_temp.t473_in() and pg_temp.t473_at('before'),
    'S 473 is not in yet and the list is 463''s (this suite installs it; use -v nomig=1 where it is in)');
end $$;

-- ===== R. Before 473: each case reproduced (undone afterwards) =====
-- A 'fixed' case does not end as 473 makes it; a control or known case
-- does, exactly.
savepoint t473_r;
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t473_cases order by ord loop
    o := pg_temp.t473_run('before', c.k, c.steps);
    if c.kind = 'fixed' then
      perform pg_temp.t473_check(not (pg_temp.t473_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''),
        'R ' || c.k || ' already ends as 473 makes it, without 473: ' || o::text);
      res := res || format(E'\n  %s: %s; customer %s; blocked %s; movable %s%s%s', c.k,
        (select string_agg(h.key || ' ' || (h.value #>> '{}'), ', ' order by h.key) from jsonb_each(o->'holds') h),
        o->>'customer', o->>'blocked', o->>'movable', coalesce('; ' || nullif(o->>'invariants', ''), ''),
        coalesce('; refused: ' || left(o->>'error', 150), ''));
    else
      perform pg_temp.t473_check(pg_temp.t473_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
          and coalesce((o->>'cancel_left')::numeric, 0) = 0,
        'R ' || c.kind || ' ' || c.k || ' without 473: ' || coalesce(pg_temp.t473_diff(o, c.expect), '') || ' ' || o::text);
    end if;
  end loop;
  for c in select * from t473_qstates loop
    perform pg_temp.t473_run('before', c.k, c.steps);
  end loop;
  raise notice 'PASS R: without 473 every fixed case ends otherwise (the faults reproduced), the controls and the known cases as expected:%', res;
end $$;

-- ===== Q. The header's read-only query, on these states =====
create temp table t473_q as select * from pg_temp.t473_header_query();
create function pg_temp.t473_q_of(p_case text) returns text language sql as $f$
  select coalesce(string_agg(left(q.reason, 1) || ':' || q.n, ',' order by q.reason), '-')
    from t473_q q join invoices i on i.invoice_no = q.invoice_no
   where i.id = pg_temp.t473_id('before/' || p_case || '/inv') $f$;
create function pg_temp.t473_q_list(p_reason text) returns text language sql as $f$
  select coalesce(string_agg(c.k, ',' order by c.k), '-')
    from (select k from t473_cases union select k from t473_qstates) c
    join invoices i on i.id = pg_temp.t473_id('before/' || c.k || '/inv')
   where exists (select 1 from t473_q q where q.invoice_no = i.invoice_no and left(q.reason, 1) = p_reason) $f$;
do $$
declare c record;
begin
  -- The states made for it: each under its reasons with its counts; those
  -- that need nothing (nothing spent; paid in full; one released lot partly
  -- spent) nowhere.
  for c in select * from t473_qstates order by k loop
    perform pg_temp.t473_check(pg_temp.t473_q_of(c.k) = c.expect,
      'Q ' || c.k || ' is listed as ' || pg_temp.t473_q_of(c.k) || ' (wanted ' || c.expect || ')');
  end loop;
  raise notice 'Q lists: 1 %; 2 %; 3 %; 4 %', pg_temp.t473_q_list('1'), pg_temp.t473_q_list('2'), pg_temp.t473_q_list('3'), pg_temp.t473_q_list('4');
  -- 1: settled lines with a lot a 'transfer' change moves today beside a
  -- spent one: QA, QB, QF and the R states that end so (K9's state, and the
  -- fixed cases whose change passed before 473: the new holder's lot);
  -- 2: before settlement (QC, W2...); 3: all released credit spent (QD,
  -- and TQn2 before its payment is not a state here: it ends paid); 4: a
  -- line held by two customers (a split: QE, QF, K1, K2 and the fixed cases
  -- whose change passed).
  perform pg_temp.t473_check(pg_temp.t473_q_list('1') = 'K2,QA,QB,QF,TQ,TQ1,TQ2,TQb,TQcb,TQcr,TQk,TQkp,TQm,TQmb,TQmk,TQms,TQn2,TQp,TQr,TQr0,TQv',
    'Q 1 lists ' || pg_temp.t473_q_list('1'));
  perform pg_temp.t473_check(pg_temp.t473_q_list('2') = 'QC,W2,W2k,W2m', 'Q 2 lists ' || pg_temp.t473_q_list('2'));
  perform pg_temp.t473_check(pg_temp.t473_q_list('3') = 'QD', 'Q 3 lists ' || pg_temp.t473_q_list('3'));
  perform pg_temp.t473_check(pg_temp.t473_q_list('4') = 'K1,K2,QE,QF,TQ,TQ1,TQ2,TQb,TQcb,TQcr,TQk,TQmb,TQms,TQn2,TQp,TQr,TQr0,TQv,W2,W2k,W2m',
    'Q 4 lists ' || pg_temp.t473_q_list('4'));
  -- the controls are listed nowhere (but TQmv: a Move to someone else is
  -- its recipient's, so nothing there)
  perform pg_temp.t473_check(not exists (select 1 from t473_q q join invoices i on i.invoice_no = q.invoice_no
                                          join t473_cases tc on i.id = pg_temp.t473_id('before/' || tc.k || '/inv')
                                         where tc.kind = 'control'),
    'Q a control is listed');
  -- The first run's notice names the same invoices under the same reasons
  -- (its own text of the query, from the migration file).
  perform pg_temp.t473_check(
        (select array_agg(x order by x) from (select left(q.reason, 1) || ' ' || q.invoice_no as x from t473_q q) d)
      = (select array_agg(x order by x) from (select f.reason || ' ' || i.invoice_no as x
                                                from pg_temp.t473_notice_query() f join invoices i on i.id = f.invoice_id) d),
    'Q the first run''s notice does not name what the header''s query lists: only the query '
    || coalesce((select string_agg(x, ', ') from (select left(q.reason, 1) || ' ' || q.invoice_no as x from t473_q q
                  except select f.reason || ' ' || i.invoice_no from pg_temp.t473_notice_query() f join invoices i on i.id = f.invoice_id) d), '-')
    || '; only the notice ' || coalesce((select string_agg(x, ', ') from (select f.reason || ' ' || i.invoice_no as x
                  from pg_temp.t473_notice_query() f join invoices i on i.id = f.invoice_id
                  except select left(q.reason, 1) || ' ' || q.invoice_no from t473_q q) d), '-'));
  raise notice 'PASS Q: the header''s read-only query lists % invoices (%), each reason as expected; the first run''s notice names the same',
    (select count(distinct invoice_no) from t473_q),
    (select string_agg(left(reason, 1) || ' ' || n, ', ' order by left(reason, 1)) from (select reason, count(*) n from t473_q group by reason) x);
end $$;
-- 473 installed on these states (undone): its first run reads them (the
-- notice above, for the Owner) and its self-test runs beside them.
savepoint t473_qn;
\ir ../../../supabase/473_part_paid_package_change_partly_spent.sql
do $$ begin
  perform pg_temp.t473_check(pg_temp.t473_in() and pg_temp.t473_at('after'), 'Q 473 did not install on the R states');
end $$;
rollback to savepoint t473_qn;
-- Keep R's outcomes; undo its records.
select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)::text as t473_rbefore from t473_res where phase = 'before' \gset
rollback to savepoint t473_r;
insert into t473_res select 'before', key, value from jsonb_each(:'t473_rbefore'::jsonb);
do $$ begin
  perform pg_temp.t473_check((select count(*) from t473_res where phase = 'before') = (select count(*) from t473_cases) + (select count(*) from t473_qstates)
      and pg_temp.t473_fingerprint() = (select v from t473_fp where k = 'start'),
    'R undone, its outcomes kept');
end $$;

-- ===== 9. The refusals, each changing nothing =====
-- 9a The list is neither 463's nor 473's.
savepoint t473_9;
alter function public.invoice_transferable_benefits(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/473_part_paid_package_change_partly_spent.sql
\set ON_ERROR_STOP on
rollback to savepoint t473_9;
select set_config('t473.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t473_check(current_setting('t473.msg') like '473: public.invoice_transferable_benefits(uuid) is not the version this was tested against (md5 %). Re-read it and re-test before applying.'
      and not pg_temp.t473_in(), '9a refused with: ' || current_setting('t473.msg'));
end $$;
-- 9b A function it relies on is not as read (a setting added to it): the
-- change that refuses on it, and 472's forwarder (473 goes in after 472).
savepoint t473_9;
alter function public.move_invoice_benefits_to_customer(uuid, uuid, uuid, text) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/473_part_paid_package_change_partly_spent.sql
\set ON_ERROR_STOP on
rollback to savepoint t473_9;
select set_config('t473.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t473_check(current_setting('t473.msg') like '473: public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text) is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying (473 goes in after 472).'
      and not pg_temp.t473_in(), '9b refused with: ' || current_setting('t473.msg'));
end $$;
savepoint t473_9;
alter function public.credit_given_back_follows(uuid) set work_mem = '64kB';
\set ON_ERROR_STOP off
\ir ../../../supabase/473_part_paid_package_change_partly_spent.sql
\set ON_ERROR_STOP on
rollback to savepoint t473_9;
select set_config('t473.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t473_check(current_setting('t473.msg') like '473: public.credit_given_back_follows(uuid) is missing or not the version this was tested against (md5 %)%'
      and not pg_temp.t473_in(), '9b2 refused with: ' || current_setting('t473.msg'));
end $$;
-- 9c Another function takes its name (an overload).
savepoint t473_9;
create function public.invoice_transferable_benefits(p text) returns setof text language sql as $f$ select p $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/473_part_paid_package_change_partly_spent.sql
\set ON_ERROR_STOP on
rollback to savepoint t473_9;
select set_config('t473.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t473_check(current_setting('t473.msg') = '473: another function takes the name of the one this changes: invoice_transferable_benefits(text)'
      and not pg_temp.t473_in(), '9c refused with: ' || current_setting('t473.msg'));
end $$;
-- 9d A new caller of the list (it would read its flags its own way).
savepoint t473_9;
create function public.t473_probe_caller(p uuid) returns bigint language sql as $f$
  select count(*) from public.invoice_transferable_benefits(p) $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/473_part_paid_package_change_partly_spent.sql
\set ON_ERROR_STOP on
rollback to savepoint t473_9;
select set_config('t473.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t473_check(current_setting('t473.msg') like '473: the functions that call invoice_transferable_benefits are not as read on 26 Oct 2026 (%t473_probe_caller(uuid)%'
      and not pg_temp.t473_in(), '9d refused with: ' || current_setting('t473.msg'));
end $$;
-- 9e A new writer of benefit rows (which line a row names is what 473 reads).
savepoint t473_9;
create function public.t473_probe_rows() returns void language sql as $f$
  update public.invoice_benefit_values set cancelled_unused_value = cancelled_unused_value where false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/473_part_paid_package_change_partly_spent.sql
\set ON_ERROR_STOP on
rollback to savepoint t473_9;
select set_config('t473.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t473_check(current_setting('t473.msg') like '473: what writes invoice_benefit_values is not as read on 26 Oct 2026 (%t473_probe_rows()%'
      and not pg_temp.t473_in(), '9e refused with: ' || current_setting('t473.msg'));
end $$;
-- 9f A new writer of the release record.
savepoint t473_9;
create function public.t473_probe_release() returns void language sql as $f$
  update public.credit_package_progress_lots set released_amount = released_amount where false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/473_part_paid_package_change_partly_spent.sql
\set ON_ERROR_STOP on
rollback to savepoint t473_9;
select set_config('t473.msg', :'LAST_ERROR_MESSAGE', false);
do $$ begin
  perform pg_temp.t473_check(current_setting('t473.msg') like '473: what writes the release record of credit released before full payment, or an Owner''s Move, is not as read on 26 Oct 2026 (%t473_probe_release()%'
      and not pg_temp.t473_in(), '9f refused with: ' || current_setting('t473.msg'));
end $$;
-- 9g The same grants in another order: installs (compared as sets).
savepoint t473_9;
revoke execute on function public.invoice_transferable_benefits(uuid) from authenticated;
grant execute on function public.invoice_transferable_benefits(uuid) to authenticated;
\ir ../../../supabase/473_part_paid_package_change_partly_spent.sql
do $$ begin
  perform pg_temp.t473_check(pg_temp.t473_in() and pg_temp.t473_at('after'), '9g the same grants in another order stopped it');
end $$;
rollback to savepoint t473_9;
do $$ begin
  perform pg_temp.t473_check(pg_temp.t473_fingerprint() = (select v from t473_fp where k = 'start') and not pg_temp.t473_in()
      and pg_temp.t473_grants() = (select v from t473_fp where k = 'grants'),
    '9 the refusals left a change');
  raise notice 'PASS 9: refused, changing nothing: the list not 463''s, a function it relies on not as tested (the change, 472''s forwarder), an overload of its name, a new caller of it, a new writer of benefit rows, a new writer of the release record. The same grants in another order do not stop it';
end $$;

-- ===== M. Begun before 473, finished after it (the mid set) =====
-- K9's state and W2's reached before 473, the change made after it:
-- refused (the whole case's outcome after 473); and a package split before
-- 473 by a 'transfer' change that passed then: a second change after 473 is
-- refused (MTQ: B keeps S$60, the use stays A's; NOT COVERED 6).
create temp table t473_mid(k text primary key, ord serial, split int, steps text, expect jsonb);
insert into t473_mid(k, split, steps, expect) select 'm' || k, s, steps, expect from (values
  ('TQ', 6), ('TQp', 4), ('TQv', 6), ('W2', 3), ('TQms', 7)) x(k, s)
  join t473_cases c using (k);
insert into t473_mid(k, split, steps, expect) values
  ('MTQ', 7, 'sale A cp 40; spend A; spend A; cancel; reopen; pay; change B; change C',
    '{"holds":{"A":"0.00","B":"60.00"},"status":"paid","customer":"B","blocked":"Paid credit 60.00 (Partly spent)","movable":"-","error~":"change C: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent). Resolve%"}');
do $$ declare c record; begin
  for c in select * from t473_mid order by ord loop
    perform pg_temp.t473_run('mid', c.k, c.steps, 1, c.split);
  end loop;
end $$;
\endif

-- ===== 10. Install 473, twice =====
\if :{?nomig}
do $$ begin raise notice 'NOTE 10: -v nomig=1, so 473 is not installed here (R, Q, 9 and M are skipped)'; end $$;
\else
\ir ../../../supabase/473_part_paid_package_change_partly_spent.sql
do $$ begin insert into t473_fp values ('first', pg_temp.t473_fingerprint()); end $$;
\ir ../../../supabase/473_part_paid_package_change_partly_spent.sql
do $$ begin insert into t473_fp values ('second', pg_temp.t473_fingerprint()); end $$;
\endif
do $$
begin
  perform pg_temp.t473_check(pg_temp.t473_in() and pg_temp.t473_at('after'), '10 473 is not installed as tested');
  perform pg_temp.t473_check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace
                               and proname = 'invoice_transferable_benefits') = 1, '10 an overload exists');
  perform pg_temp.t473_check(pg_temp.t473_inv_triggers() = (select v from t473_fp where k = 'triggers'),
    '10 a trigger on invoices was added or changed: ' || pg_temp.t473_inv_triggers());
  perform pg_temp.t473_check(pg_temp.t473_grant_set('invoice_transferable_benefits(uuid)') = '{authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}'
      and not has_function_privilege('anon', 'public.invoice_transferable_benefits(uuid)', 'execute'),
    '10 who may call it is not as before (active staff through authenticated; the function checks the store)');
  if exists (select 1 from t473_fp where k = 'first') then
    perform pg_temp.t473_check((select v from t473_fp where k = 'second') = (select v from t473_fp where k = 'first'),
      '10 the second run of 473 changed functions');
    perform pg_temp.t473_check(split_part((select v from t473_fp where k = 'first'), ' ', 2)::int
                               = split_part((select v from t473_fp where k = 'start'), ' ', 2)::int,
      '10 473 added or dropped a function');
    perform pg_temp.t473_check(pg_temp.t473_grants() = (select v from t473_fp where k = 'grants'),
      '10 the grants changed');
  end if;
  raise notice 'PASS 10: 473 installed as tested (%); the list at its AFTER, its grants as before; nothing added (no function, no trigger); %',
    pg_temp.t473_fingerprint(),
    coalesce((select 'the second run changed nothing, the grants as before' from t473_fp where k = 'first'), 'it was in before the suite (nomig)');
end $$;

-- ===== A. Each case after 473 =====
do $$
declare c record; o jsonb; b jsonb; res text := '';
begin
  for c in select * from t473_cases order by ord loop
    o := pg_temp.t473_run('after', c.k, c.steps);
    perform pg_temp.t473_check(pg_temp.t473_meets(o, c.expect),
      'A ' || c.k || ': ' || coalesce(pg_temp.t473_diff(o, c.expect), '') || ' ' || o::text);
    perform pg_temp.t473_check(coalesce(o->>'invariants', '') = '', 'A ' || c.k || ' invariants: ' || (o->>'invariants'));
    perform pg_temp.t473_check(coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'A ' || c.k || ': Cancel leaves S$' || (o->>'cancel_left') || ' of the invoice''s credit behind');
    b := (select v from t473_res where phase = 'before' and k = c.k);
    -- (a refusal's text names its invoice, numbered differently in each run;
    -- a known case's list at its end is K's)
    if c.kind in ('control', 'known') and b is not null then
      perform pg_temp.t473_check(o - 'error' - case when c.kind = 'known' then array['blocked', 'movable'] else '{}'::text[] end
                                 = b - 'error' - case when c.kind = 'known' then array['blocked', 'movable'] else '{}'::text[] end
          and regexp_replace(coalesce(o->>'error', ''), 'INV-[0-9-]+', 'INV', 'g') = regexp_replace(coalesce(b->>'error', ''), 'INV-[0-9-]+', 'INV', 'g'),
        'A ' || c.kind || ' ' || c.k || ' changed with 473: before ' || b::text || ', after ' || o::text);
    end if;
    res := res || format(E'\n  %s %s: %s; customer %s; blocked %s%s', c.kind, c.k,
      (select string_agg(h.key || ' ' || (h.value #>> '{}'), ', ' order by h.key) from jsonb_each(o->'holds') h),
      o->>'customer', o->>'blocked', coalesce('; refused: ' || left(o->>'error', 60), ''));
  end loop;
  raise notice 'PASS A: after 473 each case ends by the Owner''s rule (a ''transfer'' change of a partly spent package refused as "Partly spent", as for the package paid in full; the known cases as NOT COVERED 1 to 3 say), the invariants hold in every case and Cancel takes all of it back; the controls and the known cases are exactly as before 473%:%',
    case when exists (select 1 from t473_res where phase = 'before') then '' else ' (no before figures: -v nomig=1)' end, res;
end $$;

-- ===== M (after). The mid set finished with 473 in =====
\if :{?nomig}
\else
do $$
declare c record; o jsonb; res text := '';
begin
  for c in select * from t473_mid order by ord loop
    o := pg_temp.t473_run('mid', c.k, c.steps, c.split + 1);
    perform pg_temp.t473_check(pg_temp.t473_meets(o, c.expect) and coalesce(o->>'invariants', '') = ''
        and coalesce((o->>'cancel_left')::numeric, 0) = 0,
      'M ' || c.k || ': ' || coalesce(pg_temp.t473_diff(o, c.expect), '') || ' ' || o::text);
    res := res || ' ' || c.k;
  end loop;
  raise notice 'PASS M: begun before 473 and finished after it, each ends as the whole case does after 473 (the change refused); a package split before 473 stays split, and its second change is refused (MTQ: B S$60):%', res;
end $$;
\endif

-- ===== P. Probes =====
do $$
declare inv uuid; invc uuid; a uuid; b uuid; lot uuid; rows_ text; m jsonb; mc jsonb; v_err text;
begin
  -- P1 TQ (K9): the list's credit rows: the released lot the Cancel closed,
  -- spent in full, "Fully spent" (nothing on it, not blocking); the rest's
  -- S$60 "Partly spent", blocking, not movable (it was movable before 473).
  -- The correction summary for a change to B with 'transfer': the S$60
  -- under "These have already been used and will not move", nothing under
  -- what moves; the same items, words and detail as for the package paid in
  -- full (TQc).
  inv := pg_temp.t473_id('after/TQ/inv'); invc := pg_temp.t473_id('after/TQc/inv');
  select string_agg(x.description || ':' || x.movable || ':' || x.blocking || ':' || coalesce(x.blocked_reason, '-'), ', ' order by x.units, x.description)
    into rows_ from invoice_transferable_benefits(inv) x where x.kind = 'credit';
  perform pg_temp.t473_check(rows_ = 'Paid credit 0.00:false:false:Fully spent; it stays with the original customer, Paid credit 60.00:false:true:Partly spent',
    'P1 TQ: the list reads ' || coalesce(rows_, '(nothing)'));
  if exists (select 1 from t473_res where phase = 'before' and k = 'TQ') then
    perform pg_temp.t473_check((select v->>'movable' from t473_res where phase = 'before' and k = 'TQ') = 'Paid credit 60.00',
      'P1 TQ: before 473 the S$60 was not movable');
  end if;
  m := preview_invoice_correction(inv, jsonb_build_object('customer_id', pg_temp.t473_cust('P/TQ/B'),
         'store_id', pg_temp.t473_id('store'), 'benefit_action', 'transfer'));
  mc := preview_invoice_correction(invc, jsonb_build_object('customer_id', pg_temp.t473_cust('P/TQc/B'),
         'store_id', pg_temp.t473_id('store'), 'benefit_action', 'transfer'));
  perform pg_temp.t473_check(
        (select jsonb_agg(r) from jsonb_array_elements(m->'needs_review') r where r->>'area' = 'benefits')
        = '[{"area": "benefits", "items": [{"why": "Partly spent", "kind": "credit", "what": "Paid credit 60.00"}], "detail": "These have already been used and will not move. The correction is refused until each is resolved through the benefit transfer review."}]'::jsonb
    and not exists (select 1 from jsonb_array_elements(m->'effects') e where e->>'area' = 'benefits' and e->>'change' = 'transferring')
    and (select jsonb_agg(r) from jsonb_array_elements(m->'needs_review') r where r->>'area' = 'benefits')
        = (select jsonb_agg(r) from jsonb_array_elements(mc->'needs_review') r where r->>'area' = 'benefits'),
    'P1 TQ: the correction summary is not the paid-in-full package''s: ' || coalesce((m->'needs_review')::text, 'null') || ' / ' || coalesce((mc->'needs_review')::text, 'null'));
  -- P2 W2 (before settlement): the first release's lot (S$0) "Fully spent",
  -- not blocking; the second's S$20 "Partly spent", blocking; no benefit row
  -- names either.
  inv := pg_temp.t473_id('after/W2/inv');
  select string_agg(x.description || ':' || x.movable || ':' || x.blocking || ':' || coalesce(x.blocked_reason, '-'), ', ' order by x.units, x.description)
    into rows_ from invoice_transferable_benefits(inv) x where x.kind = 'credit';
  perform pg_temp.t473_check(rows_ = 'Paid credit 0.00:false:false:Fully spent; it stays with the original customer, Paid credit 20.00:false:true:Partly spent'
      and not exists (select 1 from invoice_benefit_values bv where bv.invoice_id = inv and bv.lot_id is not null)
      and (select count(*) from credit_package_progress_lots pl where pl.invoice_id = inv and pl.released_amount = 20) = 2,
    'P2 W2: the list reads ' || coalesce(rows_, '(nothing)'));
  -- P3 TQms: the lot blocking is the one the Owner's Move made (A's, at the
  -- other store, its row a Move's replacement): 463's store correction,
  -- judged with the line's other lots.
  inv := pg_temp.t473_id('after/TQms/inv');
  select x.record_id into lot from invoice_transferable_benefits(inv) x where x.kind = 'credit' and x.blocking;
  perform pg_temp.t473_check(lot is not null
      and (select store_id from customer_credit_lots where id = lot) = pg_temp.t473_id('store2')
      and (select customer_id from customer_credit_lots where id = lot) = pg_temp.t473_id('after/TQms/A')
      and exists (select 1 from invoice_benefit_values bv join invoice_benefit_transfers t on t.replacement_benefit_id = bv.id
                   where bv.lot_id = lot and bv.invoice_id = inv),
    'P3 TQms: the blocking lot is not the store Move''s');
  -- P4 The form still asks 'transfer' or 'keep' (the list has rows): a
  -- change of K9's state with neither is refused with BENEFIT_ACTION_REQUIRED.
  inv := pg_temp.t473_id('after/TQ/inv');
  begin
    perform correct_invoice(inv, pg_temp.t473_lines(inv),
      jsonb_build_object('expected_edit_count', (select edit_count from invoices where id = inv),
        'customer_id', pg_temp.t473_cust('P/TQ/C'), 'store_id', (select store_id from invoices where id = inv)),
      'T473 wrong customer', gen_random_uuid());
    v_err := null;
  exception when others then v_err := sqlerrm;
  end;
  perform pg_temp.t473_check(v_err like 'BENEFIT_ACTION_REQUIRED:%', 'P4 TQ: the form is not asked to choose: ' || coalesce(v_err, 'no refusal'));
  raise notice 'PASS P: K9''s list (the closed released lot "Fully spent", the S$60 "Partly spent") and its correction summary, the same as the package paid in full''s; W2''s before settlement; TQms''s blocking lot the store Move''s; the form still asked ''transfer'' or ''keep''';
end $$;

-- ===== K. KNOWN: 473's NOT COVERED (each checked as it is) =====
do $$
declare o jsonb;
begin
  -- K1 (NOT COVERED 1): all the credit released so far spent, nothing on a
  -- lot: the 'transfer' change passes (nothing to move; the list had
  -- nothing to block), and the payment gives B the rest (S$60), A having
  -- used S$40; once paid, the list blocks a further change.
  o := pg_temp.t473_run('K', 'N1', 'sale A cp 40; spend A; spend A');
  if pg_temp.t473_476_in() then
    -- 476 (the Owner, 27 Oct 2026: "Same as paid-in-full"): fixed where 476
    -- is in: the list blocks the credit still to be released, "Partly
    -- spent", and TQn2's change is refused with the paid-in-full package's
    -- words, nothing moving.
    perform pg_temp.t473_check(o->>'blocked' = 'Paid credit 60.00 (Partly spent)' and o->>'movable' = '-',
      'K1 N1 (476 in): the list does not block the credit still to be released: ' || o::text);
    perform pg_temp.t473_check((select v->'holds' from t473_res where phase = 'after' and k = 'TQn2') @> '{"A":"0.00"}'
        and not (select v->'holds' from t473_res where phase = 'after' and k = 'TQn2') ? 'B'
        and (select v->>'error' from t473_res where phase = 'after' and k = 'TQn2')
            like 'change B: These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent).%',
      'K1 TQn2 (476 in): the change is not refused as "Partly spent"');
  else
  perform pg_temp.t473_check(o->>'blocked' = '-' and o->>'movable' = '-', 'K1 N1: the list blocks something: ' || o::text);
  perform pg_temp.t473_check((select v->'holds' from t473_res where phase = 'after' and k = 'TQn2') @> '{"A":"0.00","B":"60.00"}'
      and (select v->>'error' from t473_res where phase = 'after' and k = 'TQn2') is null
      and (select v->>'blocked' from t473_res where phase = 'after' and k = 'TQn2') = 'Paid credit 60.00 (Partly spent)',
    'K1 TQn2: look at NOT COVERED 1 again');
  end if;
  -- K2 (NOT COVERED 2): 'keep' before full payment: the released credit
  -- stays with A, what the payment releases goes to B (K1: A S$40, B S$60;
  -- K2: A S$20, B S$60).
  if pg_temp.t473_476_in() then
    -- 476: fixed where 476 is in: what the payment releases goes to A, who
    -- holds the package's benefits (K1: A S$100; K2: A S$80, S$20 used).
    perform pg_temp.t473_check((select v->'holds' from t473_res where phase = 'after' and k = 'K1') @> '{"A":"100.00","B":"0.00"}'
        and (select v->'holds' from t473_res where phase = 'after' and k = 'K2') @> '{"A":"80.00","B":"0.00"}',
      'K2 K1/K2 (476 in): the later credit did not go to whoever holds the package''s benefits');
  else
  perform pg_temp.t473_check((select v->'holds' from t473_res where phase = 'after' and k = 'K1') @> '{"A":"40.00","B":"60.00"}'
      and (select v->'holds' from t473_res where phase = 'after' and k = 'K2') @> '{"A":"20.00","B":"60.00"}',
    'K2 K1/K2: look at NOT COVERED 2 again');
  end if;
  -- K3 (NOT COVERED 3): a cancelled partly spent package changed, reopened
  -- and paid: B S$60, as for the package paid in full.
  perform pg_temp.t473_check((select v->'holds' from t473_res where phase = 'after' and k = 'TQcr') @> '{"A":"0.00","B":"60.00"}'
      and (select v->'holds' from t473_res where phase = 'after' and k = 'TQcc') @> '{"A":"0.00","B":"60.00"}',
    'K3 TQcr/TQcc: look at NOT COVERED 3 again');
  -- K5 (NOT COVERED 5): two lots holding credit, both named (TQ1, TU1,
  -- TQp1); the package paid in full names one.
  perform pg_temp.t473_check((select count(*) from t473_res where phase = 'after' and k in ('TQ1', 'TU1', 'TQp1')
                                and v->>'error' like '%Paid credit %0.00 (Partly spent); Paid credit %0.00 (Partly spent)%') = 3,
    'K5 TQ1/TU1/TQp1: look at NOT COVERED 5 again');
  -- K6 (NOT COVERED 6): split before 473, left split; a second change refused.
  if exists (select 1 from t473_res where phase = 'mid' and k = 'MTQ') then
    perform pg_temp.t473_check((select v->'holds' from t473_res where phase = 'mid' and k = 'MTQ') @> '{"A":"0.00","B":"60.00"}'
        and (select v->>'error' from t473_res where phase = 'mid' and k = 'MTQ') like 'change C: %(Partly spent)%',
      'K6 MTQ: look at NOT COVERED 6 again');
  end if;
  raise notice 'KNOWN K: (473''s NOT COVERED) %; (3) a cancelled partly spent package changed, then reopened and paid: B S$60, as paid in full (TQcr, TQcc); (5) two lots named in the refusal (TQ1, TU1, TQp1); (6) split before 473 stays split, a second change refused%',
    case when pg_temp.t473_476_in()
         then '(1) and (2) fixed by 476 (TQn2 refused as "Partly spent", nothing moved; K1: A S$100; K2: A S$80)'
         else '(1) all released credit spent, nothing on a lot: the change passes and the payment gives the new customer the rest (TQn2: B S$60); (2) ''keep'' before full payment splits too (K1: A S$40, B S$60; K2: A S$20, B S$60)' end,
    case when exists (select 1 from t473_res where phase = 'mid' and k = 'MTQ') then ' (MTQ)' else ' (not tried: -v nomig=1)' end;
end $$;

rollback;
