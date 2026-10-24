-- An invoice whose customer was changed with its benefits taken along still
-- finds its credit (447; the Owner's answer of 22 Oct 2026, GAP 5 = 438's
-- NOT COVERED 5).
--
-- Every case below goes through the app's own calls: the invoice form
-- (create_invoice_with_details) and its customer change (correct_invoice
-- with benefit_action 'transfer'), the Pay dialog (record_invoice_settlement),
-- the guided Refund in full and Cancel (invoice_action_plan,
-- request_invoice_action_v2, resolve_invoice_action_v2), the Finance
-- panel's "Record refund paid" (refund_invoice_recorded with no item, then
-- line by line from the cancel plan as the panel does when that is refused),
-- a line refund of one benefit, and Move (transfer_invoice_unused_benefit).
-- Each case runs twice: with 417's text of move_invoice_benefits_to_customer
-- (rebuilt from 447's and checked by its md5; undone) and with 447's.
--
--   M  447 installs, a second run changes nothing, its self-test leaves no
--      row; the fingerprint moves by its one function; an unknown version of
--      it or of a function it relies on, a new column naming a lot, a
--      trigger on a table it repoints, or an invoice record already naming
--      a lot a customer change emptied stops it, changing nothing; the
--      grants listed in production's order do not.
--   Q  With 417's text, as found (438's NOT COVERED 5): the new customer
--      holds the credit, but the refund options name the first customer's
--      emptied lots (S$0 refundable), the plans ask a false credit_used, the
--      refund blockers say it was used; the guided Refund in full is
--      refused; the guided Cancel also asks an amount owed back and,
--      confirmed with none stated, keeps all S$1,000 "for used" credit;
--      cancelled directly, the new customer keeps the credit, the invoice
--      reads credit_used, the refund due cannot be recorded, and a line
--      refund is over its cap. Each later case shows its 417 result too.
--   P1 Credit Package Paid and Bonus (S$1,000 / S$100) changed A to B: the
--      benefit values and the sale name B's lots, the options and plans read
--      them (no override), the commission source is found; Refund in full
--      pays back the S$1,000 and takes the S$1,100 back from B; Cancel takes
--      it back from B, nothing reads as used, and "Record refund paid"
--      records the S$1,000; a line refund of S$100 of the Paid credit, with
--      the invoice still paid, is capped by B's lot and takes 110 from it.
--   P2 Premium Bundle Paid and Bonus (S$500 / S$50): the same.
--   P3 A part-paid package (S$300 of Paid released, credit_package_progress
--      _lots): (a) changed before it is settled and settled by B: as
--      before 447 (it already worked); (b) settled, then changed: the
--      released credit's benefit value follows too, its commission source is
--      found, and a cancel takes all of it back from B.
--   P4 Credit partly spent at B (S$40 of the Paid credit on a session): the
--      plans ask credit_used for the Paid credit alone (true); a second
--      change is refused as partly spent; a cancel takes what is left back
--      from B and reads credit_used.
--   P5 A second change, A to B to C: the records name C's lots, the chain
--      walks A to B to C, and a cancel takes it back from C.
--   P6 A Move after the change: B's Paid credit moved to D (refused with
--      417's text: nothing left on the lot it named); a cancel takes it back
--      from D and B's Bonus from B.
--   P7 A change after a Move: A's Paid credit moved to D, then the invoice
--      changed to B: B gets the Bonus (its records follow), D keeps the
--      Paid; a cancel takes back both.
--   V  445's V path without a merge: A part-pays (released 300), changed to
--      B, B pays the rest, the released credit moved to Z (Move), the
--      invoice changed to Y: Y gets the 700 Paid and 100 Bonus and their
--      records, Z keeps the moved 300, a refund of S$100 of Z's credit goes
--      through, the chain stays off Z's lot, every commission source is
--      found, and a cancel takes back Y's and Z's.
--   E  A lot whose benefit value was moved on, with all its credit put back
--      (written here directly: rare in the app), moves with the invoice but
--      keeps its records where they were (447's 2., as 445's merge).
--   U  Vouchers move in place, unchanged by 447: a voucher-only invoice
--      changed to B reads and writes exactly as with 417's text.
--   B  An invoice with both a voucher and a Credit Package: the voucher in
--      place, the credit followed; a cancel takes both back from B; the
--      refund due is recorded.
--   S  A shared package (a 141 split, invoice_credit_splits): the split's
--      issued lots and the shares' sales name the new customer's lots.
--   N  The customer change itself writes the same records with both texts
--      (lots, ledger rows, vouchers, benefit values but for their lot, its
--      answer and audit row): 447 only repoints the lot pointers.
--   K  Who may call it: the server alone, as before.
--
-- Disposable database only; everything is rolled back. Run from the
-- repository root on a copy of production:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/invoices/tests/customer-change-credit-447.sql
-- (it installs 447 twice; with -v nomig=1 where 447 is in already). Every
-- name, phone and email below is invented: ACMA fictional mobile numbers
-- (+61491570700..+61491570739) and @example.com addresses.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '600s';

create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.putx(key text, val uuid) returns void language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v $$;
create temp table tx(k text primary key, v text);
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.put(key text, val text) returns void language sql as
$$ insert into tx values (key, val) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end$$;
create function pg_temp.fp() returns text language sql as
$$ select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') $$;
create function pg_temp.md5_of(sig text) returns text language sql as
$$ select md5(pg_get_functiondef(to_regprocedure('public.' || sig))) $$;
create function pg_temp.method(nm text) returns uuid language sql as
$$ select id from public.payment_methods where name = nm and deleted_at is null $$;

-- ── The app's own calls ─────────────────────────────────────────────────
-- A customer of this run (each case has its own).
create function pg_temp.cust(nm text, ph text) returns uuid language plpgsql as
$$declare v uuid; begin
  insert into public.customers(full_name, phone) values ('T447 ' || nm, ph) returning id into v;
  perform pg_temp.putx(nm, v); return v;
end$$;
-- The Pay dialog: one receipt (cash unless a method is named).
create function pg_temp.pay(inv uuid, amount numeric, nm text default 'T447 Cash') returns uuid language plpgsql as
$$declare before uuid[]; begin
  before := array(select id from public.invoice_payments where invoice_id = inv);
  perform public.record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object(
    'key', 'line-0', 'payment_method_id', pg_temp.method(nm), 'amount', amount, 'payment_date', public.sg_today()::text)),
    'arrangements', '[]'::jsonb), gen_random_uuid());
  return (select id from public.invoice_payments where invoice_id = inv and not (id = any (before)) order by created_at limit 1);
end$$;
-- The invoice form: lines for one customer at the store; paid (cash) when pay > 0.
create function pg_temp.sell(cust uuid, lines jsonb, pay numeric) returns uuid language plpgsql as
$$declare inv uuid; begin
  inv := public.create_invoice_with_details(pg_temp.fx('st'), cust, lines, jsonb_build_object('business_date', public.sg_today()::text));
  if pay > 0 then perform pg_temp.pay(inv, pay); end if;
  return inv;
end$$;
create function pg_temp.pkg_line() returns jsonb language sql as
$$ select jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.fx('pk'), 'quantity', 1) $$;
create function pg_temp.bundle_line() returns jsonb language sql as
$$ select jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.fx('pb'), 'quantity', 1, 'voucher_selection', '[]'::jsonb) $$;
create function pg_temp.voucher_line() returns jsonb language sql as
$$ select jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.fx('v30'), 'quantity', 1) $$;
-- The invoice form's customer change, its lines as they are, the benefits
-- taken along ("Move the unused benefits to the new customer").
create function pg_temp.change(inv uuid, cust uuid) returns jsonb language plpgsql as
$$declare x jsonb; begin
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
           'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id, 'voucher_id', it.voucher_id,
           'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
    into x from public.invoice_items it where it.invoice_id = inv;
  return public.correct_invoice(inv, x, jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = inv),
    'customer_id', cust, 'store_id', pg_temp.fx('st'), 'benefit_action', 'transfer'), 'T447 wrong customer', gen_random_uuid());
end$$;
-- The override codes a plan asks for, sorted ('-' for none).
create function pg_temp.codes(inv uuid, act text) returns text language sql as
$$ select coalesce(string_agg(o ->> 'code', ',' order by o ->> 'code'), '-')
     from jsonb_array_elements(coalesce(public.invoice_action_plan(inv, act, '[]'::jsonb) -> 'overrides_required', '[]'::jsonb)) o $$;
create function pg_temp.used(inv uuid) returns text language sql as
$$ select coalesce(nullif(array_to_string(public.cancelled_invoice_used_value(inv), ','), ''), '-') $$;
-- The guided Refund in full or Cancel as an Owner confirms it: the plan,
-- the request, the approval with a reason for every override the plan asks
-- (and its default amount where one is asked); the money recorded as paid
-- back when p_record. The codes asked, or the refusal.
create function pg_temp.guided(inv uuid, act text, p_record boolean) returns text language plpgsql as
$$declare plan jsonb; req jsonb; ov jsonb; stock jsonb; codes text := '?'; begin
  plan := public.invoice_action_plan(inv, act, '[]'::jsonb);
  codes := (select coalesce(string_agg(o ->> 'code', ',' order by o ->> 'code'), '-')
              from jsonb_array_elements(coalesce(plan -> 'overrides_required', '[]'::jsonb)) o);
  req := public.request_invoice_action_v2(inv, act, '[]'::jsonb, 'T447 ' || act, null, gen_random_uuid());
  select coalesce(jsonb_agg(case when coalesce((o ->> 'amount_required')::boolean, false)
           then jsonb_build_object('code', o ->> 'code', 'reason', 'T447 override', 'amount', (o ->> 'default_amount')::numeric)
           else jsonb_build_object('code', o ->> 'code', 'reason', 'T447 override') end), '[]'::jsonb)
    into ov from jsonb_array_elements(coalesce(plan -> 'overrides_required', '[]'::jsonb)) o;
  select jsonb_agg(jsonb_build_object('movement_id', s ->> 'movement_id', 'sellable_quantity', (s ->> 'proposed_sellable')::int,
           'damaged_quantity', 0, 'not_returned_quantity', 0)) into stock
    from jsonb_array_elements(coalesce(plan -> 'stock', '[]'::jsonb)) s;
  perform public.resolve_invoice_action_v2((req ->> 'request_id')::uuid, true, 'T447 ' || act, plan ->> 'plan_hash', ov, stock, p_record);
  return codes;
exception when others then return codes || ' refused: ' || sqlerrm;
end$$;
-- The Finance panel's "Record refund paid" on a cancelled invoice: the
-- refund due as one line with no item, through the receipts in order; when
-- that is refused for the purchase's benefits, line by line as the panel
-- then fills it from the cancel plan (each line's amount and its benefits'
-- amounts, the plan's sources). 'recorded' (and how), or the refusal.
create function pg_temp.record_refund_paid(inv uuid) returns text language plpgsql as
$$declare due numeric := (public.invoice_financial_position(inv) ->> 'refund_due')::numeric; plan jsonb; lines jsonb; src jsonb; begin
  if coalesce(due, 0) <= 0 then return 'nothing due'; end if;
  begin
    perform public.refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', due)),
      (select jsonb_agg(jsonb_build_object('payment_id', p.id, 'amount', least(public.invoice_payment_remaining(p.id), due)) order by p.created_at)
         from public.invoice_payments p where p.invoice_id = inv and p.entry_kind = 'receipt'),
      '[]'::jsonb, 'T447 paid back', gen_random_uuid());
    return 'recorded (one line)';
  exception when others then
    if sqlerrm not like 'Allocate a correction refund to the original unused purchased benefits%' then return 'refused: ' || sqlerrm; end if;
  end;
  plan := public.invoice_action_plan(inv, 'cancel', '[]'::jsonb);
  select jsonb_agg(jsonb_build_object('invoice_item_id', l ->> 'invoice_item_id', 'amount', (l ->> 'amount')::numeric, 'overpayment', false,
           'benefits', coalesce((select jsonb_agg(jsonb_build_object('benefit_id', b ->> 'benefit_id', 'amount', (b ->> 'amount')::numeric))
                                   from jsonb_array_elements(coalesce(l -> 'benefits', '[]'::jsonb)) b where (b ->> 'amount')::numeric > 0), '[]'::jsonb)))
    into lines from jsonb_array_elements(coalesce(plan -> 'lines', '[]'::jsonb)) l where (l ->> 'amount')::numeric > 0;
  select jsonb_agg(jsonb_build_object('payment_id', s ->> 'payment_id', 'amount', (s ->> 'amount')::numeric))
    into src from jsonb_array_elements(coalesce(plan -> 'sources', '[]'::jsonb)) s where (s ->> 'amount')::numeric > 0;
  if lines is null then return 'nothing to allocate: the cancel plan''s lines are S$0 (asks ' || pg_temp.codes(inv, 'cancel') || ')'; end if;
  perform public.refund_invoice_recorded(inv, lines, coalesce(src, '[]'::jsonb), '[]'::jsonb, 'T447 paid back', gen_random_uuid());
  return 'recorded (by line)';
exception when others then return 'refused: ' || sqlerrm;
end$$;
-- A line refund of one benefit (the Finance panel's "Record money or credit
-- actually returned"), through the first receipt.
create function pg_temp.benefit_refund(inv uuid, ben uuid, amount numeric) returns text language plpgsql as
$$begin
  perform public.refund_invoice_recorded(inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', (select invoice_item_id from public.invoice_benefit_values where id = ben),
      'amount', amount, 'benefits', jsonb_build_array(jsonb_build_object('benefit_id', ben, 'amount', amount)))),
    jsonb_build_array(jsonb_build_object('payment_id', (select id from public.invoice_payments where invoice_id = inv and entry_kind = 'receipt'
                                                         order by created_at limit 1), 'amount', amount)),
    '[]'::jsonb, 'T447 part refund', gen_random_uuid());
  return 'ok';
exception when others then return 'refused: ' || sqlerrm;
end$$;
-- Move (the Finance panel): one benefit's unused value to another customer.
create function pg_temp.move(ben uuid, cust uuid) returns text language plpgsql as
$$declare r jsonb; begin
  r := public.transfer_invoice_unused_benefit(ben, cust, pg_temp.fx('st'), 'T447 move', gen_random_uuid());
  return 'ok ' || (r ->> 'benefit_id');
exception when others then return 'refused: ' || sqlerrm;
end$$;
-- What a customer holds (active credit), and what a run reads.
create function pg_temp.holds(cust uuid) returns numeric language sql as
$$ select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = cust and status = 'active' $$;
create function pg_temp.name_of(cust uuid) returns text language sql as
$$ select coalesce((select regexp_replace(full_name, '^.* ', '') from public.customers where id = cust), '?') $$;
-- Who holds each of the invoice's benefit values' lots: 'holder category
-- remaining/granted', sorted.
create function pg_temp.benefits(inv uuid) returns text language sql as
$$ select coalesce(string_agg(pg_temp.name_of(l.customer_id) || ' ' || l.category || ' ' || l.remaining_amount || '/' || b.granted_value, ', '
                              order by pg_temp.name_of(l.customer_id), l.category, l.remaining_amount, b.granted_value), '-')
     from public.invoice_benefit_values b join public.customer_credit_lots l on l.id = b.lot_id where b.invoice_id = inv $$;
-- Who holds the sale's lots.
create function pg_temp.sale(inv uuid) returns text language sql as
$$ select coalesce(string_agg(pg_temp.name_of(l.customer_id) || ' ' || l.category, ', ' order by pg_temp.name_of(l.customer_id), l.category), '-')
     from (select s.credit_lot_id x from public.credit_package_sales s where s.invoice_id = inv
           union all select s.bonus_credit_lot_id from public.credit_package_sales s where s.invoice_id = inv
           union all select s.paid_credit_lot_id from public.premium_bundle_sales s where s.invoice_id = inv
           union all select s.bonus_credit_lot_id from public.premium_bundle_sales s where s.invoice_id = inv) q
     join public.customer_credit_lots l on l.id = q.x $$;
-- The refund options' benefits: 'holder max_refund', sorted.
create function pg_temp.options(inv uuid) returns text language sql as
$$ select coalesce(string_agg(regexp_replace(x ->> 'customer_name', '^.* ', '') || ' ' || (x ->> 'max_refund'), ', '
                              order by regexp_replace(x ->> 'customer_name', '^.* ', ''), (x ->> 'max_refund')::numeric), '-')
     from jsonb_array_elements(public.invoice_refund_options(inv) -> 'benefits') x where x ->> 'lot_id' is not null $$;
-- Each benefit value's commission source: its sale kind, or the refusal.
create function pg_temp.sources(inv uuid) returns text language plpgsql as
$$declare r record; acc text[] := '{}'; begin
  for r in select b.id from public.invoice_benefit_values b where b.invoice_id = inv order by b.created_at, b.id loop
    begin acc := acc || (public.invoice_commission_benefit_source(r.id) ->> 'sale_kind');
    exception when others then acc := acc || ('refused: ' || sqlerrm); end;
  end loop;
  return coalesce((select string_agg(x, ',' order by x) from unnest(acc) x), '-');
end$$;
create function pg_temp.due(inv uuid) returns text language sql as
$$ select (f ->> 'refund_due') || case when coalesce((f ->> 'kept_for_used')::numeric, 0) <> 0
                                       then ' (kept for used ' || (f ->> 'kept_for_used') || ')' else '' end
     from (select public.invoice_financial_position(inv) f) x $$;
create function pg_temp.status(inv uuid) returns text language sql as
$$ select status::text from public.invoices where id = inv $$;
-- Undo what a block did (it ends by raising this), keeping what it read.
create function pg_temp.undo() returns void language plpgsql as
$$begin raise exception using errcode = 'P0447', message = 'T447 undo'; end$$;

-- ═════ Fixtures (before 447 is installed, where the suite installs it) ═════
do $$
declare o uuid := gen_random_uuid(); st uuid; pk uuid; pb uuid; v uuid; svc uuid;
begin
  if exists (select 1 from public.customers where phone like '+614915707__' and phone between '+61491570700' and '+61491570739') then
    raise exception 'FIXTURE: a customer already uses the test phones +61491570700..739'; end if;
  insert into auth.users(id, email) values (o, 't447-owner@example.com');
  insert into public.profiles(id, full_name, email, role, is_active) values (o, 'T447 Owner', 't447-owner@example.com', 'owner', true);
  perform pg_temp.putx('owner', o);
  perform set_config('request.jwt.claims', json_build_object('sub', o, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into public.stores(name, code, country_code) values ('T447 Store', 'T447S', 'SG') returning id into st;
  perform pg_temp.putx('st', st);
  insert into public.payment_methods(name, is_active) values ('T447 Cash', true);
  -- A S$1,000 Credit Package (S$1,000 Paid, S$100 Bonus) and a S$500 Premium
  -- Bundle (S$500 Paid, S$50 Bonus, no vouchers).
  insert into public.credit_packages(name, customer_price, paid_credit_amount, bonus_enabled, bonus_value,
                                     allow_product, allow_therapy, allow_voucher, grants_reward)
  values ('T447 Package', 1000, 1000, true, 100, true, true, true, false) returning id into pk;
  insert into public.credit_package_stores(package_id, store_id) values (pk, st);
  insert into public.premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
  values ('T447 Bundle', 500, 500, 50, 0, false) returning id into pb;
  insert into public.premium_bundle_stores(bundle_id, store_id) values (pb, st);
  perform pg_temp.putx('pk', pk); perform pg_temp.putx('pb', pb);
  -- A plain S$30 voucher, and a S$40 therapy session (package Paid credit
  -- pays therapy sessions).
  insert into public.vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('T447 Voucher 30', 'T447-V30', 'normal', 'unlimited', 30, true) returning id into v;
  insert into public.voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 30, true);
  perform pg_temp.putx('v30', v);
  svc := (public.upsert_therapy_service(null, 'T447-S', 'T447 Session', 40, 30, 'per_hours', 1, 5, null, true, null) ->> 'id')::uuid;
  perform public.set_therapy_service_store(svc, st, true, null);
  perform pg_temp.putx('svc', svc);
end $$;

-- Where 460 is in (it changes move_invoice_benefits_to_customer at four
-- places: the vouchers it moves, three times, and its Audit Log row), its
-- text with those four changes taken out: 447's.
create function pg_temp.without_460(p_t text) returns text language plpgsql as
$$declare t text := p_t; r text[]; a text[]; i int;
begin
  if position('-- 460 (the Owner' in t) = 0 then return t; end if;
  r := array[
$r1$  -- 460 (the Owner, 22 Oct 2026: "fix the other two rare gaps too"): the
  -- invoice's own vouchers (invoice_own_voucher_ids): its voucher and
  -- promotion lines', and those given again in place of one of them by a
  -- reopening or by the payment after an FOC came off ('invoice_reopen').
  -- Before, only the first two sources, so a voucher given again stayed
  -- with the old customer. Not one an Owner moved to someone (434), nor a
  -- Premium Bundle's, as before.
  perform 1 from public.customer_reward_vouchers
   where id in (select o.voucher_id from public.invoice_own_voucher_ids(p_invoice_id) o)
$r1$,
$r2$     where rv.id in (select o.voucher_id from public.invoice_own_voucher_ids(p_invoice_id) o)   -- 460
$r2$,
$r3$     set customer_id = p_customer_id, store_id = p_store_id
   where id in (select o.voucher_id from public.invoice_own_voucher_ids(p_invoice_id) o)   -- 460
$r3$,
$r4$  -- 460 (the Owner, 22 Oct 2026): recorded for every change that takes the
  -- benefits along, also when nothing was left to move (a reopened invoice
  -- whose vouchers and credit wait, a line refunded before the change): what
  -- a reopening gives back later goes to this customer
  -- (invoice_benefits_holder reads it). Before, only when something moved.
  perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_benefits_followed_reassignment',
    null, jsonb_build_object('vouchers', v_v, 'credit_lots', v_c, 'allowances', v_a,
                             'to_customer', p_customer_id, 'reason', p_reason),
    'invoices', p_reason, p_store_id);
$r4$];
  a := array[
$a1$  perform 1 from public.customer_reward_vouchers
   where source_type in ('invoice_voucher_sale','invoice_promotion_voucher')
     and source_id in (select id from public.invoice_items where invoice_id = p_invoice_id)
$a1$,
$a2$     where rv.source_type in ('invoice_voucher_sale','invoice_promotion_voucher')
       and rv.source_id in (select id from public.invoice_items where invoice_id = p_invoice_id)
$a2$,
$a3$     set customer_id = p_customer_id, store_id = p_store_id
   where source_type in ('invoice_voucher_sale','invoice_promotion_voucher')
     and source_id in (select id from public.invoice_items where invoice_id = p_invoice_id)
$a3$,
$a4$  if v_v + v_c + v_a > 0 then
    perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_benefits_followed_reassignment',
      null, jsonb_build_object('vouchers', v_v, 'credit_lots', v_c, 'allowances', v_a,
                               'to_customer', p_customer_id, 'reason', p_reason),
      'invoices', p_reason, p_store_id);
  end if;
$a4$];
  for i in 1 .. 4 loop
    if position(r[i] in t) = 0 then raise exception 'FIXTURE: 460''s change % not found in move_invoice_benefits_to_customer', i; end if;
    t := replace(t, r[i], a[i]);
  end loop;
  return t;
end$$;

-- Where 461 is in (it changes move_invoice_benefits_to_customer at one place:
-- the lots it moves), its text with that change taken out: 447's three lines
-- back, whatever 461's lines say (from its marker to the lot's status test).
create function pg_temp.without_461(p_t text) returns text language plpgsql as
$$declare t text := p_t; a int; b int;
begin
  a := position('       -- 461 (the Owner, 22 Oct 2026)' in t);
  if a = 0 then return t; end if;
  b := position(E'       and l.status = ''active''\n' in substr(t, a));
  if b = 0 then raise exception 'FIXTURE: 461''s lines not found in move_invoice_benefits_to_customer'; end if;
  return substr(t, 1, a - 1)
         || E'       and l.remaining_amount = l.original_amount\n       and l.remaining_amount > 0\n'
         || substr(t, a + b - 1);
end$$;
-- Where 462 is in (move-merge-leftovers-462.sql: it changes the lots' selection,
-- in 461's part, which without_461 takes out whatever it says, and takes off
-- the guard that kept a moved-on row's records), its text with the guard put
-- back: 460's and 461's.
create function pg_temp.without_462(p_t text) returns text language plpgsql as
$$declare t text := p_t; r text; a text;
begin
  if position('    -- 462 (the Owner, 24 Oct 2026): a lot whose benefit value an Owner moved' in t) = 0 then return t; end if;
  r :=
$r$    -- 462 (the Owner, 24 Oct 2026): a lot whose benefit value an Owner moved
    -- on (Move) too, now: the moved credit is traced through the Move's own
    -- ledger rows (invoice_credit_transfer_origin), not through this lot, so
    -- its records follow like any other's (as in a merge, 462).
    update public.invoice_benefit_values set lot_id = v_new_lot where lot_id = r_lot.id;
    update public.credit_package_sales set credit_lot_id = v_new_lot where credit_lot_id = r_lot.id;
    update public.credit_package_sales set bonus_credit_lot_id = v_new_lot where bonus_credit_lot_id = r_lot.id;
    update public.premium_bundle_sales set paid_credit_lot_id = v_new_lot where paid_credit_lot_id = r_lot.id;
    update public.premium_bundle_sales set bonus_credit_lot_id = v_new_lot where bonus_credit_lot_id = r_lot.id;
    update public.invoice_credit_splits set issued_lot_id = v_new_lot where issued_lot_id = r_lot.id;
$r$;
  a :=
$a$    if not exists (select 1 from public.invoice_benefit_values b
                     join public.invoice_benefit_transfers t on t.source_benefit_id = b.id
                    where b.lot_id = r_lot.id) then
      update public.invoice_benefit_values set lot_id = v_new_lot where lot_id = r_lot.id;
      update public.credit_package_sales set credit_lot_id = v_new_lot where credit_lot_id = r_lot.id;
      update public.credit_package_sales set bonus_credit_lot_id = v_new_lot where bonus_credit_lot_id = r_lot.id;
      update public.premium_bundle_sales set paid_credit_lot_id = v_new_lot where paid_credit_lot_id = r_lot.id;
      update public.premium_bundle_sales set bonus_credit_lot_id = v_new_lot where bonus_credit_lot_id = r_lot.id;
      update public.invoice_credit_splits set issued_lot_id = v_new_lot where issued_lot_id = r_lot.id;
    end if;
$a$;
  if position(r in t) = 0 then raise exception 'FIXTURE: 462''s change not found in move_invoice_benefits_to_customer'; end if;
  return replace(t, r, a);
end$$;
-- Where 463 is in (change-store-moves-bundle-vouchers-463.sql: it adds the
-- credit an Owner moved to the same customer at another store to the lots'
-- selection, and keeps the store of such a voucher and of a Premium Bundle's),
-- its text with its six changes taken out: 462's (the sixth: credit so
-- moved from a row partly spent before the Move does not move).
create function pg_temp.without_463(p_t text) returns text language plpgsql as
$$declare t text := p_t; r text[]; a text[]; i int;
begin
  if position('v463_kept' in t) = 0 then return t; end if;
  r := array[
$w1$        r_lot public.customer_credit_lots%rowtype; v_new_lot uuid;
        v463_kept uuid[];  -- 463: vouchers that keep their store
$w1$,
$w2$   order by id for update;
  -- 463 (the Owner, 24 Oct 2026, decisions 2 and 3): a voucher an Owner
  -- moved to the same customer at another store (a store correction, which
  -- a customer change that takes the benefits along takes along), and a
  -- Premium Bundle's (they follow such a change as the bundle's credit
  -- does), and one given again in place of either, is one of the invoice's
  -- own now (invoice_own_voucher_ids): it moves to the new customer and
  -- keeps its store, as credit keeps its store: no stock moves for it. The
  -- voucher and promotion lines' go to the invoice's store, as before (417).
  v463_kept := array(
    with recursive k(id, n) as (
      select o.voucher_id, 0
        from public.invoice_own_voucher_ids(p_invoice_id) o
        join public.customer_reward_vouchers c on c.id = o.voucher_id
       where c.source_type in ('invoice_benefit_transfer', 'premium_bundle')
      union all
      select q.replacement_voucher_id, k.n + 1
        from k
        join public.invoice_benefit_values b on b.reward_voucher_id = k.id and b.invoice_id = p_invoice_id
        join public.invoice_reopen_vouchers q on q.benefit_id = b.id and q.invoice_id = p_invoice_id
       where q.replacement_voucher_id is not null and k.n < 64)
    select distinct k.id from k);
  for v417 in
$w2$,
$w3$       and p_store_id is not null and rv.store_id is not null and rv.store_id <> p_store_id
       and rv.id <> all (v463_kept)   -- 463
$w3$,
$w4$  update public.customer_reward_vouchers
     set customer_id = p_customer_id,
         store_id = case when id = any (v463_kept) then store_id else p_store_id end   -- 463
$w4$,
$w5$     where (l.id in (select lot_id from public.invoice_credit_lot_ids(p_invoice_id))
            -- 463 (the Owner, 24 Oct 2026, decision 2): and credit an Owner
            -- moved to the same customer at another store (a store
            -- correction): the lot its benefit row names now, which stays
            -- the invoice's own (invoice_benefit_moved_to_other), so it
            -- moves with its records, keeping its store, as the invoice's
            -- own credit does. Not a Move to someone else (its recipient
            -- keeps it, 434).
            or l.id in (select b.lot_id from public.invoice_benefit_values b
                         where b.invoice_id = p_invoice_id and b.lot_id is not null
                           and exists (select 1 from public.invoice_benefit_transfers t
                                        where t.replacement_benefit_id = b.id)
                           and not public.invoice_benefit_moved_to_other(b.id)))
$w5$,
$w6$       and l.remaining_amount > 0
       and l.status = 'active'
       -- 463: nor credit an Owner moved to the same customer at another
       -- store from a benefit row partly spent before the Move
       -- (invoice_benefit_moved_from_spent: the list blocks the change for
       -- it, "Partly spent", as for the invoice's own credit), read again
       -- once the lot is locked.
       and not exists (select 1 from public.invoice_benefit_values b
                        where b.lot_id = l.id and b.invoice_id = p_invoice_id
                          and public.invoice_benefit_moved_from_spent(b.id))
$w6$];
  a := array[
$v1$        r_lot public.customer_credit_lots%rowtype; v_new_lot uuid;
$v1$,
$v2$   order by id for update;
  for v417 in
$v2$,
$v3$       and p_store_id is not null and rv.store_id is not null and rv.store_id <> p_store_id
$v3$,
$v4$  update public.customer_reward_vouchers
     set customer_id = p_customer_id, store_id = p_store_id
$v4$,
$v5$     where l.id in (select lot_id from public.invoice_credit_lot_ids(p_invoice_id))
$v5$,
$v6$       and l.remaining_amount > 0
       and l.status = 'active'
$v6$];
  for i in 1 .. 6 loop
    if position(r[i] in t) = 0 then raise exception 'FIXTURE: 463''s change % not found in move_invoice_benefits_to_customer', i; end if;
    t := replace(t, r[i], a[i]);
  end loop;
  return t;
end$$;
-- Whether 462 is in (its merge text).
create function pg_temp.with_462() returns boolean language sql as
$$ select to_regprocedure('public.credit_given_back_follows(uuid)') is not null $$;
-- 447's text, read from what is installed: 455's, or 460's or 461's (or
-- both, or 462 over both, or 463 over 462) with their changes taken out.
create function pg_temp.as_447() returns text language sql as
$$ select pg_temp.without_461(pg_temp.without_460(pg_temp.without_462(pg_temp.without_463(
          pg_get_functiondef('public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure))))) $$;

-- 417's text of move_invoice_benefits_to_customer, rebuilt from 447's (the
-- block 447 adds taken out; where 460 or 461 is in, from their text with
-- their changes taken out first) and checked by its md5. Its own
-- transaction step: run inside a savepoint that is rolled back.
create function pg_temp.use_417() returns void language plpgsql as
$$declare t text := pg_get_functiondef('public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure);
  a int; b int;
begin
  if md5(t) = '2c01c460d3af8edd3ad86332aa286ed8' then return; end if;
  t := pg_temp.as_447();
  if md5(t) <> 'e313e87b4ab4c0063d924430996ffbd3' then
    raise exception 'FIXTURE: 447''s text could not be rebuilt from what is installed (md5 %)', md5(t); end if;
  a := position('    -- 447 (the Owner, 22 Oct 2026)' in t);
  b := position(E'    end if;\n\n    v_c := v_c + 1;' in t);
  if a = 0 or b = 0 or b < a then raise exception 'FIXTURE: 447''s block not found in move_invoice_benefits_to_customer'; end if;
  t := substr(t, 1, a - 1) || substr(t, b + length(E'    end if;\n\n'));
  if md5(t) <> '2c01c460d3af8edd3ad86332aa286ed8' then
    raise exception 'FIXTURE: 417''s text could not be rebuilt (md5 %)', md5(t); end if;
  execute t;
end$$;

-- ═════ M Install ═════
create temp table m447(fp_before text, n_lots int, n_ledger int, n_cust int, n_inv int, n_benefit int, n_audit int,
                       lots_hash text, sales_hash text, benefits_hash text);
insert into m447 select pg_temp.fp(), (select count(*) from public.customer_credit_lots), (select count(*) from public.customer_credit_ledger),
                        (select count(*) from public.customers), (select count(*) from public.invoices),
                        (select count(*) from public.invoice_benefit_values), (select count(*) from public.audit_logs),
                        (select md5(string_agg(to_jsonb(l)::text, '|' order by l.id)) from public.customer_credit_lots l),
                        (select md5(string_agg(to_jsonb(s)::text, '|' order by s.id)) from public.credit_package_sales s),
                        (select md5(string_agg(to_jsonb(b)::text, '|' order by b.id)) from public.invoice_benefit_values b);
\if :{?nomig}
-- 460 and 461 (where they are in) change the function again (460 the
-- vouchers it moves and its Audit Log row, 461 the lots it moves) and keep
-- 447's records step as it is: with their changes taken out it is 447's.
select pg_temp.check(md5(pg_temp.as_447()) = 'e313e87b4ab4c0063d924430996ffbd3',
  'M0 447 is installed (nomig; 460''s and 461''s changes taken out where they are in)');
\else
select pg_temp.check(pg_temp.md5_of('move_invoice_benefits_to_customer(uuid,uuid,uuid,text)') = '2c01c460d3af8edd3ad86332aa286ed8',
  'M0 447 is not in yet: move_invoice_benefits_to_customer is 417''s (this suite installs it; use -v nomig=1 where it is in)');
-- M5 an unknown version of move_invoice_benefits_to_customer stops it.
savepoint m5;
do $$ begin
  execute replace(pg_get_functiondef('public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure),
                  'declare v_blocked text;', 'declare /* another version */ v_blocked text;');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/447_customer_change_invoice_follows_credit.sql
\set m5_failed :ERROR
\set m5_msg :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint m5;
-- M6 an unknown version of a function it relies on stops it.
savepoint m6;
do $$ begin
  execute replace(pg_get_functiondef('public.invoice_credit_lot_ids(uuid)'::regprocedure),
                  '-- The exact lots the credit package sale issued.', '-- The exact lots the credit package sale issued (another version).');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/447_customer_change_invoice_follows_credit.sql
\set m6_failed :ERROR
\set m6_msg :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint m6;
-- M7 a new column naming a lot stops it (a customer change would have to decide it).
savepoint m7;
alter table public.invoice_items add column t447_lot uuid references public.customer_credit_lots(id);
\set ON_ERROR_STOP off
\ir ../../../supabase/447_customer_change_invoice_follows_credit.sql
\set m7_failed :ERROR
\set m7_msg :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint m7;
-- M8 a trigger on a table it repoints stops it.
savepoint m8;
create function pg_temp.t447_noop() returns trigger language plpgsql as $f$ begin return new; end $f$;
create trigger t447_noop before update on public.premium_bundle_sales for each row execute function pg_temp.t447_noop();
\set ON_ERROR_STOP off
\ir ../../../supabase/447_customer_change_invoice_follows_credit.sql
\set m8_failed :ERROR
\set m8_msg :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint m8;
-- M11 an invoice already changed with 417's text (its records name the
-- emptied lots: the state 447 prevents) stops it, changing nothing.
savepoint m11;
do $$ declare a uuid; b uuid; inv uuid; begin
  a := pg_temp.cust('M11 Alpha', '+61491570738'); b := pg_temp.cust('M11 Bravo', '+61491570739');
  inv := pg_temp.sell(a, jsonb_build_array(pg_temp.pkg_line()), 1000);
  perform pg_temp.change(inv, b);
  perform pg_temp.putx('m11_inv', inv);
end $$;
savepoint m11_apply;
\set ON_ERROR_STOP off
\ir ../../../supabase/447_customer_change_invoice_follows_credit.sql
\set m11_failed :ERROR
\set m11_msg :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint m11_apply;
select pg_temp.check(pg_temp.md5_of('move_invoice_benefits_to_customer(uuid,uuid,uuid,text)') = '2c01c460d3af8edd3ad86332aa286ed8'
    and pg_temp.benefits(pg_temp.fx('m11_inv')) = 'Alpha bonus 0.00/100.00, Alpha paid 0.00/1000.00',
  'M9 a stopped run changed nothing (move_invoice_benefits_to_customer is still 417''s; the records it found are as they were): '
  || pg_temp.benefits(pg_temp.fx('m11_inv')));
rollback to savepoint m11;
select pg_temp.check(:'m5_failed' = 'true' and :'m5_msg' like '447: public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text) is not the version this was tested against%',
  'M5 an unknown version of move_invoice_benefits_to_customer stops it: ' || :'m5_msg');
select pg_temp.check(:'m6_failed' = 'true' and :'m6_msg' like '447: public.invoice_credit_lot_ids(uuid) is missing or not the version this was tested against%',
  'M6 an unknown version of a function it relies on stops it: ' || :'m6_msg');
select pg_temp.check(:'m7_failed' = 'true' and :'m7_msg' like '447: the columns that name a credit lot are not as read%invoice_items.t447_lot%',
  'M7 a new column naming a lot stops it: ' || :'m7_msg');
select pg_temp.check(:'m8_failed' = 'true' and :'m8_msg' like '447: these tables have triggers they did not have on 22 Oct 2026: premium_bundle_sales t447_noop%',
  'M8 a trigger on a table it repoints stops it: ' || :'m8_msg');
select pg_temp.check(:'m11_failed' = 'true' and :'m11_msg' like '447: 2 lot(s) emptied by a customer change are still named by their invoice''s records%',
  'M11 an invoice already changed with 417''s text (its records on the emptied lots) stops it: ' || :'m11_msg');
\ir ../../../supabase/447_customer_change_invoice_follows_credit.sql
do $$ begin perform pg_temp.put('fp1', pg_temp.fp()); end $$;
\ir ../../../supabase/447_customer_change_invoice_follows_credit.sql
select pg_temp.check(pg_temp.fp() = pg_temp.tx('fp1') and pg_temp.fp() <> (select fp_before from m447)
    and split_part(pg_temp.fp(), ' ', 2) = split_part((select fp_before from m447), ' ', 2),
  'M1 447 installs (no function more or less) and a second run changes nothing: ' || pg_temp.fp());
select pg_temp.check((select count(*) from public.customer_credit_lots) = (select n_lots from m447)
    and (select md5(string_agg(to_jsonb(l)::text, '|' order by l.id)) from public.customer_credit_lots l) is not distinct from (select lots_hash from m447)
    and (select md5(string_agg(to_jsonb(s)::text, '|' order by s.id)) from public.credit_package_sales s) is not distinct from (select sales_hash from m447)
    and (select md5(string_agg(to_jsonb(b)::text, '|' order by b.id)) from public.invoice_benefit_values b) is not distinct from (select benefits_hash from m447)
    and (select count(*) from public.customer_credit_ledger) = (select n_ledger from m447)
    and (select count(*) from public.customers) = (select n_cust from m447)
    and (select count(*) from public.invoices) = (select n_inv from m447)
    and (select count(*) from public.invoice_benefit_values) = (select n_benefit from m447)
    and (select count(*) from public.audit_logs) = (select n_audit from m447),
  'M2 installing changes no record: no lot, ledger row, sale, benefit value, customer, invoice or audit row (its self-test, twice, left none)');
-- M12 who may call it is compared as a set: the same grants listed in
-- another order (as production lists them) do not stop it.
savepoint m12;
revoke execute on function public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text) from postgres;
grant execute on function public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text) to postgres;
select proacl::text as m12_acl from pg_proc where oid = 'public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure \gset
\set ON_ERROR_STOP off
\ir ../../../supabase/447_customer_change_invoice_follows_credit.sql
\set m12_failed :ERROR
\set m12_msg :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP on
rollback to savepoint m12;
select pg_temp.check(:'m12_failed' = 'false' and :'m12_acl' = '{service_role=X/postgres,postgres=X/postgres}',
  'M12 the same grants listed in another order do not stop it: ' || :'m12_acl'
  || case when :'m12_failed' = 'true' then ' ' || :'m12_msg' else '' end);
\endif
select pg_temp.check(md5(pg_temp.as_447()) = 'e313e87b4ab4c0063d924430996ffbd3'
    and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'move_invoice_benefits_to_customer') = 1
    and pg_temp.md5_of('merge_customer_records(uuid,uuid,text,uuid)')
        = case when pg_temp.with_462() then 'ba05c2b1fb4c0e14d369c01d06a635b0' else '2e0c9852099ab88d8f27827b5f9a3846' end
    and pg_temp.md5_of('transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)') = '7aebd7120bc3928db46df0941cb20889',
  'M3 move_invoice_benefits_to_customer is 447''s (e313e87b4ab4c0063d924430996ffbd3; where 460, 461 or 462 is in, with their changes taken out), with no overload; 445''s merge (462''s where it is in) and Move are unchanged');
select pg_temp.check((select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x
                       where p.oid = 'public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'::regprocedure)
      = (select array_agg(x::text order by x::text) from unnest('{postgres=X/postgres,service_role=X/postgres}'::aclitem[]) x)
    and not has_function_privilege('anon', 'public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)', 'execute')
    and has_function_privilege('service_role', 'public.move_invoice_benefits_to_customer(uuid,uuid,uuid,text)', 'execute'),
  'K1 move_invoice_benefits_to_customer is still the server''s alone (postgres, service_role)');

-- ═════ The cases (each returns what it read) ═════
-- P1 and Q: a S$1,000 Credit Package, paid, changed from Alpha to Bravo.
create function pg_temp.p1() returns jsonb language plpgsql as
$$declare a uuid; b uuid; inv uuid; ben uuid; r jsonb := '{}'; t text; begin
  a := pg_temp.cust('P1 Alpha', '+61491570700'); b := pg_temp.cust('P1 Bravo', '+61491570701');
  inv := pg_temp.sell(a, jsonb_build_array(pg_temp.pkg_line()), 1000);
  perform pg_temp.change(inv, b);
  r := r || jsonb_build_object('holds', 'Alpha ' || pg_temp.holds(a) || ' Bravo ' || pg_temp.holds(b),
    'benefits', pg_temp.benefits(inv), 'sale', pg_temp.sale(inv), 'options', pg_temp.options(inv),
    'plans', pg_temp.codes(inv, 'refund_full') || ' / ' || pg_temp.codes(inv, 'cancel'),
    -- Whether the guided Cancel asks "State how much is owed back" (417).
    'owed_asked', coalesce(public.invoice_action_plan(inv, 'cancel', '[]'::jsonb) -> 'refund_owed' ->> 'needed', 'false'),
    'blockers', public.credit_purchase_refund_blockers(inv) -> 'blockers',
    'listed', (select count(*) from public.invoice_transferable_benefits(inv)),
    'sources', pg_temp.sources(inv),
    -- The customer page's purchases (customer_credit_balances), each customer's.
    'purchases', (select coalesce(string_agg(pg_temp.name_of(c) || ': ' || coalesce((
                     select string_agg((x ->> 'name') || ' paid ' || (x ->> 'paid') || ' bonus ' || (x ->> 'bonus')
                                       || case when (x ->> 'received')::boolean then ' received' else '' end, ', ')
                       from jsonb_array_elements(public.customer_credit_balances(c) -> 'purchases') x), '-'), ' | ' order by o), '-')
                    from unnest(array[a, b]) with ordinality u(c, o)));
  -- The guided Refund in full, recorded as paid back (undone after).
  begin
    t := pg_temp.guided(inv, 'refund_full', true);
    r := r || jsonb_build_object('refund_full', t || ' -> ' || pg_temp.status(inv) || ', net ' || public.invoice_net_received(inv)
      || ', Bravo ' || pg_temp.holds(b));
    perform pg_temp.undo();
  exception when sqlstate 'P0447' then null;
  end;
  -- The guided Cancel, then "Record refund paid" (undone after).
  begin
    t := pg_temp.guided(inv, 'cancel', false);
    r := r || jsonb_build_object('cancel', t || ' -> ' || pg_temp.status(inv) || ', Bravo ' || pg_temp.holds(b) || ', used ' || pg_temp.used(inv)
      || ', due ' || pg_temp.due(inv));
    t := pg_temp.record_refund_paid(inv);
    r := r || jsonb_build_object('record', t || ', due ' || pg_temp.due(inv));
    perform pg_temp.undo();
  exception when sqlstate 'P0447' then null;
  end;
  -- A direct cancel (no amount owed stated), then "Record refund paid" (undone
  -- after); and instead a line refund of the Paid benefit at its paid value
  -- (undone after).
  begin
    perform public.cancel_invoice_recorded(inv, 'T447 cancel', gen_random_uuid());
    r := r || jsonb_build_object('direct_cancel', 'Bravo ' || pg_temp.holds(b) || ', used ' || pg_temp.used(inv) || ', due ' || pg_temp.due(inv));
    t := pg_temp.record_refund_paid(inv);
    r := r || jsonb_build_object('direct_record', t || ', due ' || pg_temp.due(inv));
    perform pg_temp.undo();
  exception when sqlstate 'P0447' then null;
  end;
  begin
    perform public.cancel_invoice_recorded(inv, 'T447 cancel', gen_random_uuid());
    select bv.id into ben from public.invoice_benefit_values bv join public.customer_credit_lots l on l.id = bv.lot_id
     where bv.invoice_id = inv and l.category = 'paid';
    t := pg_temp.benefit_refund(inv, ben, (select paid_value from public.invoice_benefit_values where id = ben));
    r := r || jsonb_build_object('cancelled_line_refund', t);
    perform pg_temp.undo();
  exception when sqlstate 'P0447' then null;
  end;
  -- Still paid: S$100 of the Paid credit refunded by line (undone after).
  begin
    select bv.id into ben from public.invoice_benefit_values bv join public.customer_credit_lots l on l.id = bv.lot_id
     where bv.invoice_id = inv and l.category = 'paid';
    t := pg_temp.benefit_refund(inv, ben, 100);
    r := r || jsonb_build_object('line_refund', t || ', Bravo ' || pg_temp.holds(b) || ', net ' || public.invoice_net_received(inv));
    perform pg_temp.undo();
  exception when sqlstate 'P0447' then null;
  end;
  return r;
end$$;

-- P2: a S$500 Premium Bundle, paid, changed.
create function pg_temp.p2() returns jsonb language plpgsql as
$$declare a uuid; b uuid; inv uuid; r jsonb := '{}'; t text; begin
  a := pg_temp.cust('P2 Alpha', '+61491570702'); b := pg_temp.cust('P2 Bravo', '+61491570703');
  inv := pg_temp.sell(a, jsonb_build_array(pg_temp.bundle_line()), 500);
  perform pg_temp.change(inv, b);
  r := r || jsonb_build_object('holds', 'Alpha ' || pg_temp.holds(a) || ' Bravo ' || pg_temp.holds(b),
    'benefits', pg_temp.benefits(inv), 'sale', pg_temp.sale(inv), 'options', pg_temp.options(inv),
    'plans', pg_temp.codes(inv, 'refund_full') || ' / ' || pg_temp.codes(inv, 'cancel'), 'sources', pg_temp.sources(inv));
  t := pg_temp.guided(inv, 'cancel', false);
  r := r || jsonb_build_object('cancel', t || ' -> ' || pg_temp.status(inv) || ', Bravo ' || pg_temp.holds(b) || ', used ' || pg_temp.used(inv)
    || ', due ' || pg_temp.due(inv));
  t := pg_temp.record_refund_paid(inv);
  r := r || jsonb_build_object('record', t || ', due ' || pg_temp.due(inv));
  return r;
end$$;

-- P3: a part-paid package: S$300 paid (S$300 Paid released); (a) changed,
-- then settled by Bravo; (b) settled by Alpha, then changed.
create function pg_temp.p3() returns jsonb language plpgsql as
$$declare a uuid; b uuid; a2 uuid; b2 uuid; inv uuid; inv2 uuid; rel uuid; r jsonb := '{}'; t text; begin
  a := pg_temp.cust('P3 Alpha', '+61491570704'); b := pg_temp.cust('P3 Bravo', '+61491570705');
  inv := pg_temp.sell(a, jsonb_build_array(pg_temp.pkg_line()), 300);
  perform pg_temp.change(inv, b);
  r := r || jsonb_build_object('a_part_paid', 'Alpha ' || pg_temp.holds(a) || ' Bravo ' || pg_temp.holds(b));
  perform pg_temp.pay(inv, 700);
  r := r || jsonb_build_object('a_settled', pg_temp.status(inv) || ', Alpha ' || pg_temp.holds(a) || ' Bravo ' || pg_temp.holds(b),
    'a_benefits', pg_temp.benefits(inv), 'a_sources', pg_temp.sources(inv),
    'a_plans', pg_temp.codes(inv, 'refund_full') || ' / ' || pg_temp.codes(inv, 'cancel'));
  perform public.cancel_invoice_recorded(inv, 'T447 cancel', gen_random_uuid());
  r := r || jsonb_build_object('a_cancel', 'Bravo ' || pg_temp.holds(b) || ', used ' || pg_temp.used(inv) || ', due ' || pg_temp.due(inv));
  t := pg_temp.record_refund_paid(inv);
  r := r || jsonb_build_object('a_record', t || ', due ' || pg_temp.due(inv));
  a2 := pg_temp.cust('P3 Charlie', '+61491570706'); b2 := pg_temp.cust('P3 Delta', '+61491570707');
  inv2 := pg_temp.sell(a2, jsonb_build_array(pg_temp.pkg_line()), 300);
  select lot_id into rel from public.credit_package_progress_lots where invoice_id = inv2;
  perform pg_temp.pay(inv2, 700);
  perform pg_temp.change(inv2, b2);
  r := r || jsonb_build_object('b_changed', 'Charlie ' || pg_temp.holds(a2) || ' Delta ' || pg_temp.holds(b2),
    'b_benefits', pg_temp.benefits(inv2), 'b_sale', pg_temp.sale(inv2), 'b_sources', pg_temp.sources(inv2),
    'b_plans', pg_temp.codes(inv2, 'refund_full') || ' / ' || pg_temp.codes(inv2, 'cancel'),
    'b_chain', cardinality(public.credit_lot_chain(rel)) || ' ' || pg_temp.name_of((select customer_id from public.customer_credit_lots
                                                                              where id = public.credit_lot_current(rel))),
    'b_progress_kept', (select count(*) from public.credit_package_progress_lots where invoice_id = inv2 and lot_id = rel));
  t := pg_temp.guided(inv2, 'cancel', false);
  r := r || jsonb_build_object('b_cancel', t || ' -> Delta ' || pg_temp.holds(b2) || ', used ' || pg_temp.used(inv2) || ', due ' || pg_temp.due(inv2));
  t := pg_temp.record_refund_paid(inv2);
  r := r || jsonb_build_object('b_record', t || ', due ' || pg_temp.due(inv2));
  return r;
end$$;

-- P4: changed to Bravo, who spends S$40 of the Paid credit on a therapy session.
create function pg_temp.p4() returns jsonb language plpgsql as
$$declare a uuid; b uuid; c uuid; inv uuid; spend uuid; r jsonb := '{}'; t text; begin
  a := pg_temp.cust('P4 Alpha', '+61491570708'); b := pg_temp.cust('P4 Bravo', '+61491570709'); c := pg_temp.cust('P4 Charlie', '+61491570710');
  inv := pg_temp.sell(a, jsonb_build_array(pg_temp.pkg_line()), 1000);
  perform pg_temp.change(inv, b);
  spend := pg_temp.sell(b, jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.fx('svc'), 'quantity', 1)), 0);
  perform pg_temp.pay(spend, 40, 'Wallet — Credit Package Paid');
  r := r || jsonb_build_object('spent', pg_temp.status(spend) || ', Bravo ' || pg_temp.holds(b),
    'benefits', pg_temp.benefits(inv),
    'plans', pg_temp.codes(inv, 'refund_full') || ' / ' || pg_temp.codes(inv, 'cancel'));
  t := pg_temp.err(format('select pg_temp.change(%L, %L)', inv, c));
  r := r || jsonb_build_object('second_change', t);
  perform public.cancel_invoice_recorded(inv, 'T447 cancel', gen_random_uuid());
  r := r || jsonb_build_object('cancel', 'Bravo ' || pg_temp.holds(b) || ', used ' || pg_temp.used(inv) || ', due ' || pg_temp.due(inv));
  return r;
end$$;

-- P5: changed twice, Alpha to Bravo to Charlie.
create function pg_temp.p5() returns jsonb language plpgsql as
$$declare a uuid; b uuid; c uuid; inv uuid; paid uuid; r jsonb := '{}'; t text; begin
  a := pg_temp.cust('P5 Alpha', '+61491570711'); b := pg_temp.cust('P5 Bravo', '+61491570712'); c := pg_temp.cust('P5 Charlie', '+61491570713');
  inv := pg_temp.sell(a, jsonb_build_array(pg_temp.pkg_line()), 1000);
  select credit_lot_id into paid from public.credit_package_sales where invoice_id = inv;
  perform pg_temp.change(inv, b);
  perform pg_temp.change(inv, c);
  r := r || jsonb_build_object('holds', 'Alpha ' || pg_temp.holds(a) || ' Bravo ' || pg_temp.holds(b) || ' Charlie ' || pg_temp.holds(c),
    'benefits', pg_temp.benefits(inv), 'sale', pg_temp.sale(inv), 'sources', pg_temp.sources(inv),
    'chain', cardinality(public.credit_lot_chain(paid)) || ' ' || pg_temp.name_of((select customer_id from public.customer_credit_lots
                                                                           where id = public.credit_lot_current(paid))),
    'plans', pg_temp.codes(inv, 'refund_full') || ' / ' || pg_temp.codes(inv, 'cancel'));
  t := pg_temp.guided(inv, 'cancel', false);
  r := r || jsonb_build_object('cancel', t || ' -> Charlie ' || pg_temp.holds(c) || ', used ' || pg_temp.used(inv) || ', due ' || pg_temp.due(inv));
  t := pg_temp.record_refund_paid(inv);
  r := r || jsonb_build_object('record', t || ', due ' || pg_temp.due(inv));
  return r;
end$$;

-- P6: changed to Bravo, then Bravo's Paid credit moved to Delta (Move).
create function pg_temp.p6() returns jsonb language plpgsql as
$$declare a uuid; b uuid; d uuid; inv uuid; ben uuid; mv text; r jsonb := '{}'; t text; begin
  a := pg_temp.cust('P6 Alpha', '+61491570714'); b := pg_temp.cust('P6 Bravo', '+61491570715'); d := pg_temp.cust('P6 Delta', '+61491570716');
  inv := pg_temp.sell(a, jsonb_build_array(pg_temp.pkg_line()), 1000);
  perform pg_temp.change(inv, b);
  -- The Paid benefit (the one a Move would pick in the Finance panel).
  select bv.id into ben from public.invoice_benefit_values bv where bv.invoice_id = inv and bv.granted_value = 1000;
  mv := pg_temp.move(ben, d);
  r := r || jsonb_build_object('move', case when mv like 'refused%' then mv else split_part(mv, ' ', 1) end,
    'holds', 'Alpha ' || pg_temp.holds(a) || ' Bravo ' || pg_temp.holds(b) || ' Delta ' || pg_temp.holds(d),
    'benefits', pg_temp.benefits(inv), 'sources', pg_temp.sources(inv),
    'plans', pg_temp.codes(inv, 'refund_full') || ' / ' || pg_temp.codes(inv, 'cancel'));
  t := pg_temp.guided(inv, 'cancel', false);
  r := r || jsonb_build_object('cancel', t || ' -> Bravo ' || pg_temp.holds(b) || ' Delta ' || pg_temp.holds(d) || ', used ' || pg_temp.used(inv)
    || ', due ' || pg_temp.due(inv));
  t := pg_temp.record_refund_paid(inv);
  r := r || jsonb_build_object('record', t || ', due ' || pg_temp.due(inv));
  return r;
end$$;

-- P7: Alpha's Paid credit moved to Delta (Move), then the invoice changed to Bravo.
create function pg_temp.p7() returns jsonb language plpgsql as
$$declare a uuid; b uuid; d uuid; inv uuid; ben uuid; mv text; r jsonb := '{}'; t text; begin
  a := pg_temp.cust('P7 Alpha', '+61491570717'); b := pg_temp.cust('P7 Bravo', '+61491570718'); d := pg_temp.cust('P7 Delta', '+61491570719');
  inv := pg_temp.sell(a, jsonb_build_array(pg_temp.pkg_line()), 1000);
  select bv.id into ben from public.invoice_benefit_values bv where bv.invoice_id = inv and bv.granted_value = 1000;
  mv := pg_temp.move(ben, d);
  perform pg_temp.change(inv, b);
  r := r || jsonb_build_object('move', split_part(mv, ' ', 1),
    'holds', 'Alpha ' || pg_temp.holds(a) || ' Bravo ' || pg_temp.holds(b) || ' Delta ' || pg_temp.holds(d),
    'benefits', pg_temp.benefits(inv), 'sale', pg_temp.sale(inv), 'sources', pg_temp.sources(inv),
    'plans', pg_temp.codes(inv, 'refund_full') || ' / ' || pg_temp.codes(inv, 'cancel'));
  t := pg_temp.guided(inv, 'cancel', false);
  r := r || jsonb_build_object('cancel', t || ' -> Bravo ' || pg_temp.holds(b) || ' Delta ' || pg_temp.holds(d) || ', used ' || pg_temp.used(inv)
    || ', due ' || pg_temp.due(inv));
  t := pg_temp.record_refund_paid(inv);
  r := r || jsonb_build_object('record', t || ', due ' || pg_temp.due(inv));
  return r;
end$$;

-- V: 445's V path, without a merge.
create function pg_temp.v() returns jsonb language plpgsql as
$$declare a uuid; b uuid; z uuid; y uuid; inv uuid; rel uuid; pay uuid; rel_b uuid; zb uuid; zl uuid; mv text; r jsonb := '{}'; t text; begin
  a := pg_temp.cust('V Alpha', '+61491570720'); b := pg_temp.cust('V Bravo', '+61491570721');
  z := pg_temp.cust('V Zulu', '+61491570722'); y := pg_temp.cust('V Yankee', '+61491570723');
  inv := pg_temp.sell(a, jsonb_build_array(pg_temp.pkg_line()), 300);
  select lot_id into rel from public.credit_package_progress_lots where invoice_id = inv;
  perform pg_temp.change(inv, b);
  pay := pg_temp.pay(inv, 700);
  select bv.id into rel_b from public.invoice_benefit_values bv where bv.invoice_id = inv and bv.lot_id = public.credit_lot_current(rel);
  mv := pg_temp.move(rel_b, z);
  zb := nullif(split_part(mv, ' ', 2), '')::uuid;
  select lot_id into zl from public.invoice_benefit_values where id = zb;
  perform pg_temp.change(inv, y);
  r := r || jsonb_build_object('move', split_part(mv, ' ', 1),
    'holds', 'Alpha ' || pg_temp.holds(a) || ' Bravo ' || pg_temp.holds(b) || ' Zulu ' || pg_temp.holds(z) || ' Yankee ' || pg_temp.holds(y),
    'z_link_is_null', (select reassigned_from_lot_id is null from public.customer_credit_lots where id = zl),
    'chain', cardinality(public.credit_lot_chain(rel)) || ' ' || pg_temp.name_of((select customer_id from public.customer_credit_lots
                                                                         where id = public.credit_lot_current(rel))),
    'benefits', pg_temp.benefits(inv), 'sale', pg_temp.sale(inv), 'sources', pg_temp.sources(inv),
    'plans', pg_temp.codes(inv, 'refund_full') || ' / ' || pg_temp.codes(inv, 'cancel'));
  -- S$100 of Zulu's moved credit refunded (undone after).
  begin
    t := pg_temp.benefit_refund(inv, zb, 100);
    r := r || jsonb_build_object('z_refund', t || ', Zulu ' || pg_temp.holds(z) || ', Yankee ' || pg_temp.holds(y));
    perform pg_temp.undo();
  exception when sqlstate 'P0447' then null;
  end;
  t := pg_temp.guided(inv, 'cancel', false);
  r := r || jsonb_build_object('cancel', t || ' -> Yankee ' || pg_temp.holds(y) || ' Zulu ' || pg_temp.holds(z) || ', used ' || pg_temp.used(inv)
    || ', due ' || pg_temp.due(inv));
  t := pg_temp.record_refund_paid(inv);
  r := r || jsonb_build_object('record', t || ', due ' || pg_temp.due(inv));
  return r;
end$$;

-- E: Alpha's Paid credit moved to Delta, then all S$1,000 of it put back on
-- Alpha's lot (written directly: credit put back on a lot after its Move),
-- then the invoice changed to Bravo.
create function pg_temp.e() returns jsonb language plpgsql as
$$declare a uuid; b uuid; d uuid; inv uuid; ben uuid; paid uuid; mv text; r jsonb := '{}'; begin
  a := pg_temp.cust('E Alpha', '+61491570724'); b := pg_temp.cust('E Bravo', '+61491570725'); d := pg_temp.cust('E Delta', '+61491570726');
  inv := pg_temp.sell(a, jsonb_build_array(pg_temp.pkg_line()), 1000);
  select credit_lot_id into paid from public.credit_package_sales where invoice_id = inv;
  select bv.id into ben from public.invoice_benefit_values bv where bv.invoice_id = inv and bv.lot_id = paid;
  mv := pg_temp.move(ben, d);
  update public.customer_credit_lots set remaining_amount = original_amount, updated_at = now() where id = paid;
  insert into public.customer_credit_ledger(wallet_id, customer_id, entry_type, category, amount, lot_id, source_type, store_id, reason, created_by)
  select l.wallet_id, l.customer_id, 'adjust_increase', l.category, l.original_amount, l.id, 't447_fixture', l.store_id,
         'T447 fixture: all of it back on a moved-out lot', pg_temp.fx('owner')
    from public.customer_credit_lots l where l.id = paid;
  perform pg_temp.change(inv, b);
  r := r || jsonb_build_object('move', split_part(mv, ' ', 1),
    'holds', 'Alpha ' || pg_temp.holds(a) || ' Bravo ' || pg_temp.holds(b) || ' Delta ' || pg_temp.holds(d),
    'paid_kept', (select credit_lot_id = paid from public.credit_package_sales where invoice_id = inv)
                 and exists (select 1 from public.invoice_benefit_values where id = ben and lot_id = paid),
    'benefits', pg_temp.benefits(inv), 'sale', pg_temp.sale(inv));
  return r;
end$$;

-- U: a voucher-only invoice changed: the voucher moves in place.
create function pg_temp.u() returns jsonb language plpgsql as
$$declare a uuid; b uuid; inv uuid; vrow jsonb; brow jsonb; r jsonb := '{}'; ans jsonb; t text; begin
  a := pg_temp.cust('U Alpha', '+61491570727'); b := pg_temp.cust('U Bravo', '+61491570728');
  inv := pg_temp.sell(a, jsonb_build_array(pg_temp.voucher_line()), 30);
  select to_jsonb(v) - 'customer_id' - 'store_id' - 'updated_at' into vrow
    from public.invoice_benefit_values bv join public.customer_reward_vouchers v on v.id = bv.reward_voucher_id where bv.invoice_id = inv;
  select to_jsonb(bv) into brow from public.invoice_benefit_values bv where bv.invoice_id = inv;
  ans := pg_temp.change(inv, b);
  r := r || jsonb_build_object(
    'voucher', (select pg_temp.name_of(v.customer_id) || ' ' || v.status || ' ' || v.quantity
                         || case when (to_jsonb(v) - 'customer_id' - 'store_id' - 'updated_at') = vrow then ' same row' else ' changed' end
                  from public.invoice_benefit_values bv join public.customer_reward_vouchers v on v.id = bv.reward_voucher_id
                 where bv.invoice_id = inv),
    'benefit_row_same', (select to_jsonb(bv) = brow from public.invoice_benefit_values bv where bv.invoice_id = inv),
    'audit', (select new_data - 'to_customer' - 'reason' from public.audit_logs where record_id = inv
                and action = 'invoice_benefits_followed_reassignment' order by created_at desc limit 1),
    'plans', pg_temp.codes(inv, 'refund_full') || ' / ' || pg_temp.codes(inv, 'cancel'));
  perform public.cancel_invoice_recorded(inv, 'T447 cancel', gen_random_uuid());
  r := r || jsonb_build_object('cancel', (select string_agg(v.status, ',') from public.invoice_benefit_values bv
                                            join public.customer_reward_vouchers v on v.id = bv.reward_voucher_id where bv.invoice_id = inv)
    || ', used ' || pg_temp.used(inv) || ', due ' || pg_temp.due(inv));
  t := pg_temp.record_refund_paid(inv);
  r := r || jsonb_build_object('record', t || ', due ' || pg_temp.due(inv));
  return r;
end$$;

-- B (and N): a voucher and a Credit Package on one invoice, changed.
create function pg_temp.world(inv uuid, p_a uuid, p_b uuid) returns jsonb language sql as
$$ select jsonb_build_object(
     'lots', (select jsonb_agg(to_jsonb(l) - 'id' - 'wallet_id' - 'customer_id' - 'reassigned_from_lot_id' - 'created_at' - 'updated_at'
                               || jsonb_build_object('holder', pg_temp.name_of(l.customer_id)) order by l.customer_id = p_b, l.category, l.remaining_amount)
                from public.customer_credit_lots l where l.customer_id in (p_a, p_b)),
     'ledger', (select jsonb_agg(to_jsonb(e) - 'id' - 'entry_seq' - 'lot_id' - 'wallet_id' - 'customer_id' - 'created_at' - 'source_record_id'
                                 || jsonb_build_object('holder', pg_temp.name_of(e.customer_id)) order by e.customer_id = p_b, e.entry_type, e.category, e.amount, e.source_type)
                  from public.customer_credit_ledger e where e.customer_id in (p_a, p_b)),
     'vouchers', (select jsonb_agg(to_jsonb(v) - 'id' - 'customer_id' - 'source_id' - 'created_at' - 'updated_at' - 'issued_at'
                                   || jsonb_build_object('holder', pg_temp.name_of(v.customer_id)) order by v.status)
                    from public.customer_reward_vouchers v where v.customer_id in (p_a, p_b)),
     'benefits', (select jsonb_agg(to_jsonb(b) - 'id' - 'lot_id' - 'reward_voucher_id' - 'invoice_id' - 'invoice_item_id' - 'created_at' - 'evidence'
                                   order by b.granted_value)
                    from public.invoice_benefit_values b where b.invoice_id = inv),
     'audit', (select jsonb_agg(a.new_data - 'to_customer' order by a.created_at) from public.audit_logs a
                where a.record_id = inv and a.action = 'invoice_benefits_followed_reassignment')) $$;
create function pg_temp.both() returns jsonb language plpgsql as
$$declare a uuid; b uuid; inv uuid; ans jsonb; r jsonb := '{}'; t text; begin
  a := pg_temp.cust('B Alpha', '+61491570729'); b := pg_temp.cust('B Bravo', '+61491570730');
  inv := pg_temp.sell(a, jsonb_build_array(pg_temp.voucher_line(), pg_temp.pkg_line()), 1030);
  perform public.write_audit_ex('invoices', inv, 't447_marker', null, null, 'invoices', 'T447', pg_temp.fx('st'));
  ans := pg_temp.change(inv, b);
  r := r || jsonb_build_object('world', pg_temp.world(inv, a, b),
    'holds', 'Alpha ' || pg_temp.holds(a) || ' Bravo ' || pg_temp.holds(b),
    'voucher', (select pg_temp.name_of(v.customer_id) || ' ' || v.status from public.invoice_benefit_values bv
                  join public.customer_reward_vouchers v on v.id = bv.reward_voucher_id where bv.invoice_id = inv),
    'benefits', pg_temp.benefits(inv), 'sale', pg_temp.sale(inv),
    'plans', pg_temp.codes(inv, 'refund_full') || ' / ' || pg_temp.codes(inv, 'cancel'));
  t := pg_temp.guided(inv, 'cancel', false);
  r := r || jsonb_build_object('cancel', t || ' -> Bravo ' || pg_temp.holds(b) || ', voucher '
    || (select v.status from public.invoice_benefit_values bv join public.customer_reward_vouchers v on v.id = bv.reward_voucher_id
         where bv.invoice_id = inv) || ', used ' || pg_temp.used(inv) || ', due ' || pg_temp.due(inv));
  t := pg_temp.record_refund_paid(inv);
  r := r || jsonb_build_object('record', t || ', due ' || pg_temp.due(inv));
  return r;
end$$;

-- S: a shared package (141 split: Quebec 400, Oscar 600, on one line), paid,
-- changed to Bravo.
create function pg_temp.s() returns jsonb language plpgsql as
$$declare q uuid; o uuid; b uuid; inv uuid; item uuid; r jsonb := '{}'; begin
  q := pg_temp.cust('S Quebec', '+61491570731'); o := pg_temp.cust('S Oscar', '+61491570732'); b := pg_temp.cust('S Bravo', '+61491570733');
  inv := pg_temp.sell(q, jsonb_build_array(pg_temp.pkg_line()), 0);
  select id into item from public.invoice_items where invoice_id = inv;
  perform public.set_invoice_credit_split(item, jsonb_build_array(jsonb_build_object('customer_id', q, 'amount', 400),
                                                                  jsonb_build_object('customer_id', o, 'amount', 600)));
  perform pg_temp.pay(inv, 1000);
  perform pg_temp.change(inv, b);
  r := r || jsonb_build_object('holds', 'Quebec ' || pg_temp.holds(q) || ' Oscar ' || pg_temp.holds(o) || ' Bravo ' || pg_temp.holds(b),
    'split_lots', (select string_agg(pg_temp.name_of(s.customer_id) || ' ' || s.amount || ' -> ' || coalesce(pg_temp.name_of(l.customer_id), '-')
                                     || ' ' || coalesce(l.remaining_amount::text, '-'), ', ' order by s.amount)
                     from public.invoice_credit_splits s left join public.customer_credit_lots l on l.id = s.issued_lot_id where s.invoice_id = inv),
    'sale', pg_temp.sale(inv));
  return r;
end$$;

create function pg_temp.run_all() returns jsonb language plpgsql as
$$begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  return jsonb_build_object('P1', pg_temp.p1(), 'P2', pg_temp.p2(), 'P3', pg_temp.p3(), 'P4', pg_temp.p4(), 'P5', pg_temp.p5(),
    'P6', pg_temp.p6(), 'P7', pg_temp.p7(), 'V', pg_temp.v(), 'E', pg_temp.e(), 'U', pg_temp.u(), 'B', pg_temp.both(), 'S', pg_temp.s());
end$$;

-- ═════ With 417's text (undone) ═════
savepoint old_text;
select pg_temp.use_417();
select pg_temp.md5_of('move_invoice_benefits_to_customer(uuid,uuid,uuid,text)') = '2c01c460d3af8edd3ad86332aa286ed8' as old_ok \gset
select pg_temp.run_all()::text as r_old \gset
rollback to savepoint old_text;
-- ═════ With 447's ═════
select pg_temp.run_all()::text as r_new \gset
select pg_temp.put('old', :'r_old'), pg_temp.put('new', :'r_new');
select pg_temp.check(:'old_ok'::boolean, 'FIXTURE 417''s text rebuilt from 447''s by its md5 (2c01c460d3af8edd3ad86332aa286ed8)');
create function pg_temp.o(k text) returns jsonb language sql as $$ select pg_temp.tx('old')::jsonb #> string_to_array(k, '.') $$;
create function pg_temp.n(k text) returns jsonb language sql as $$ select pg_temp.tx('new')::jsonb #> string_to_array(k, '.') $$;
create function pg_temp.ot(k text) returns text language sql as $$ select pg_temp.tx('old')::jsonb #>> string_to_array(k, '.') $$;
create function pg_temp.nt(k text) returns text language sql as $$ select pg_temp.tx('new')::jsonb #>> string_to_array(k, '.') $$;

-- ═════ Q With 417's text, as found ═════
select pg_temp.check(pg_temp.ot('P1.holds') = 'Alpha 0.00 Bravo 1100.00'
    and pg_temp.ot('P1.benefits') = 'Alpha bonus 0.00/100.00, Alpha paid 0.00/1000.00'
    and pg_temp.ot('P1.sale') = 'Alpha bonus, Alpha paid'
    and pg_temp.ot('P1.options') = 'Alpha 0.00, Alpha 0.00'
    and pg_temp.ot('P1.plans') = 'credit_used,credit_used / credit_used,credit_used'
    and pg_temp.o('P1.blockers') = '["Credit from this purchase has already been used"]',
  'Q1 with 417''s text Bravo holds the S$1,100, but the benefit values and the sale name Alpha''s emptied lots, the refund options show S$0, '
  || 'both plans ask a false credit_used and the blockers say it was used: '
  || (pg_temp.o('P1') - 'refund_full' - 'cancel' - 'record' - 'line_refund' - 'cancelled_line_refund' - 'direct_cancel' - 'direct_record')::text);
select pg_temp.check(pg_temp.ot('P1.owed_asked') = 'true'
    and pg_temp.ot('P1.cancel') = 'credit_used,credit_used -> cancelled, Bravo 1100.00, used credit_used, due 0.00 (kept for used 1000.00)'
    and pg_temp.ot('P1.record') = 'nothing due, due 0.00 (kept for used 1000.00)',
  'Q2 with 417''s text the guided Cancel asks credit_used for both lots and "State how much is owed back"; confirmed with no amount stated, '
  || 'it keeps all S$1,000 for "used" credit (refund due 0) while Bravo keeps the S$1,100: ' || pg_temp.ot('P1.cancel'));
select pg_temp.check(pg_temp.ot('P1.direct_cancel') = 'Bravo 1100.00, used credit_used, due 1000.00'
    and pg_temp.ot('P1.direct_record') = 'nothing to allocate: the cancel plan''s lines are S$0 (asks credit_used,credit_used), due 1000.00'
    and pg_temp.ot('P1.cancelled_line_refund') = 'refused: Refund exceeds the unused paid value of this benefit'
    and pg_temp.ot('P1.line_refund') like 'refused: Refund exceeds the unused paid value of this benefit%',
  'Q3 with 417''s text a direct cancel leaves Bravo the S$1,100 and reads credit_used, and the S$1,000 due cannot be recorded ("Record refund paid" '
  || 'is refused for credit and the cancel plan''s line is S$0; a line refund is over its cap); a part refund before any cancel is refused the same: '
  || pg_temp.ot('P1.direct_cancel') || ' | ' || pg_temp.ot('P1.direct_record') || ' | ' || pg_temp.ot('P1.cancelled_line_refund') || ' | ' || pg_temp.ot('P1.line_refund'));
select pg_temp.check(pg_temp.ot('P1.refund_full') = 'credit_used,credit_used refused: There is nothing left to refund on this invoice -> paid, net 1000.00, Bravo 1100.00',
  'Q4 with 417''s text the guided Refund in full asks credit_used for both lots and is refused: ' || pg_temp.ot('P1.refund_full'));

-- ═════ P1 Credit Package Paid and Bonus ═════
select pg_temp.check(pg_temp.nt('P1.holds') = 'Alpha 0.00 Bravo 1100.00'
    and pg_temp.nt('P1.benefits') = 'Bravo bonus 100.00/100.00, Bravo paid 1000.00/1000.00'
    and pg_temp.nt('P1.sale') = 'Bravo bonus, Bravo paid'
    and pg_temp.nt('P1.options') = 'Bravo 90.91, Bravo 909.09'
    and pg_temp.nt('P1.plans') = '- / -'
    and pg_temp.nt('P1.owed_asked') = 'false'
    and pg_temp.n('P1.blockers') = '[]'
    and pg_temp.nt('P1.listed') = '2'
    and pg_temp.nt('P1.sources') = 'credit_package,credit_package'
    and pg_temp.nt('P1.purchases') = 'Alpha: - | Bravo: T447 Package paid 1000.00 bonus 100.00'
    and pg_temp.nt('P1.purchases') = pg_temp.ot('P1.purchases'),
  'P1a changed to Bravo: the benefit values and the sale name Bravo''s lots, the refund options show them as Bravo''s at their paid value, '
  || 'no plan asks an override, no blocker, the invoice lists Bravo''s two lots only, both commission sources found: '
  || (pg_temp.n('P1') - 'refund_full' - 'cancel' - 'record' - 'line_refund' - 'cancelled_line_refund' - 'direct_cancel' - 'direct_record')::text);
select pg_temp.check(pg_temp.nt('P1.refund_full') = '- -> refunded, net 0.00, Bravo 0.00',
  'P1b the guided Refund in full asks nothing, pays back the S$1,000 and takes the S$1,100 back from Bravo: ' || pg_temp.nt('P1.refund_full'));
select pg_temp.check(pg_temp.nt('P1.cancel') = '- -> cancelled, Bravo 0.00, used -, due 1000.00'
    and pg_temp.nt('P1.record') = 'recorded (by line), due 0.00'
    and pg_temp.nt('P1.direct_cancel') = 'Bravo 0.00, used -, due 1000.00'
    and pg_temp.nt('P1.direct_record') = 'recorded (by line), due 0.00'
    and pg_temp.nt('P1.cancelled_line_refund') = 'ok',
  'P1c the guided Cancel asks nothing and takes the S$1,100 back from Bravo, nothing reads as used, and "Record refund paid" records the S$1,000 '
  || '(line by line, as the panel does for credit); the same after a direct cancel, and a line refund at the paid value goes through: '
  || pg_temp.nt('P1.cancel') || ' | ' || pg_temp.nt('P1.record') || ' | ' || pg_temp.nt('P1.direct_cancel') || ' | ' || pg_temp.nt('P1.direct_record')
  || ' | ' || pg_temp.nt('P1.cancelled_line_refund'));
select pg_temp.check(pg_temp.nt('P1.line_refund') = 'ok, Bravo 990.00, net 900.00',
  'P1d still paid, S$100 of the Paid credit refunded by line is capped by Bravo''s lot and takes 110 from it: ' || pg_temp.nt('P1.line_refund'));

-- ═════ P2 Premium Bundle Paid and Bonus ═════
select pg_temp.check(pg_temp.ot('P2.benefits') = 'Alpha bonus 0.00/50.00, Alpha paid 0.00/500.00'
    and pg_temp.ot('P2.cancel') = 'credit_used,credit_used -> cancelled, Bravo 550.00, used credit_used, due 0.00 (kept for used 500.00)',
  'P2q with 417''s text the bundle''s records stay on Alpha''s emptied lots and a cancel leaves Bravo the S$550: ' || pg_temp.ot('P2.cancel'));
select pg_temp.check(pg_temp.nt('P2.holds') = 'Alpha 0.00 Bravo 550.00'
    and pg_temp.nt('P2.benefits') = 'Bravo bonus 50.00/50.00, Bravo paid 500.00/500.00'
    and pg_temp.nt('P2.sale') = 'Bravo bonus, Bravo paid'
    and pg_temp.nt('P2.options') = 'Bravo 45.45, Bravo 454.55'
    and pg_temp.nt('P2.plans') = '- / -'
    and pg_temp.nt('P2.sources') = 'premium_bundle,premium_bundle'
    and pg_temp.nt('P2.cancel') = '- -> cancelled, Bravo 0.00, used -, due 500.00'
    and pg_temp.nt('P2.record') = 'recorded (by line), due 0.00',
  'P2 a Premium Bundle changed to Bravo: its records name Bravo''s lots, no override, the commission sources found; cancelled, '
  || 'the S$550 comes back from Bravo, nothing used, the S$500 recorded: ' || pg_temp.n('P2')::text);

-- ═════ P3 A part-paid package ═════
select pg_temp.check(pg_temp.n('P3') - 'b_changed' - 'b_benefits' - 'b_sale' - 'b_sources' - 'b_plans' - 'b_chain' - 'b_progress_kept' - 'b_cancel' - 'b_record'
       = pg_temp.o('P3') - 'b_changed' - 'b_benefits' - 'b_sale' - 'b_sources' - 'b_plans' - 'b_chain' - 'b_progress_kept' - 'b_cancel' - 'b_record'
    and pg_temp.nt('P3.a_part_paid') = 'Alpha 0.00 Bravo 300.00'
    and pg_temp.nt('P3.a_settled') = 'paid, Alpha 0.00 Bravo 1100.00'
    and pg_temp.nt('P3.a_benefits') = 'Bravo bonus 100.00/100.00, Bravo paid 300.00/300.00, Bravo paid 700.00/700.00'
    and pg_temp.nt('P3.a_sources') = 'credit_package,credit_package,credit_package'
    and pg_temp.nt('P3.a_plans') = '- / -'
    and pg_temp.nt('P3.a_cancel') = 'Bravo 0.00, used -, due 1000.00'
    and pg_temp.nt('P3.a_record') = 'recorded (by line), due 0.00',
  'P3a changed while part-paid (S$300 released moves to Bravo), then settled by Bravo: the same with both texts (it worked already): '
  || 'Bravo''s lots hold the benefits, the commission sources found; cancelled, all of it back from Bravo, the S$1,000 recorded: '
  || (pg_temp.n('P3') - 'b_changed' - 'b_benefits' - 'b_sale' - 'b_sources' - 'b_plans' - 'b_chain' - 'b_progress_kept' - 'b_cancel' - 'b_record')::text);
select pg_temp.check(pg_temp.ot('P3.b_benefits') = 'Charlie bonus 0.00/100.00, Charlie paid 0.00/300.00, Charlie paid 0.00/700.00'
    and pg_temp.ot('P3.b_cancel') = 'credit_used,credit_used,credit_used -> Delta 1100.00, used credit_used, due 0.00 (kept for used 1000.00)',
  'P3q with 417''s text, settled then changed, all three records stay on Charlie''s emptied lots and a cancel leaves Delta the S$1,100: '
  || pg_temp.ot('P3.b_cancel'));
select pg_temp.check(pg_temp.nt('P3.b_changed') = 'Charlie 0.00 Delta 1100.00'
    and pg_temp.nt('P3.b_benefits') = 'Delta bonus 100.00/100.00, Delta paid 300.00/300.00, Delta paid 700.00/700.00'
    and pg_temp.nt('P3.b_sale') = 'Delta bonus, Delta paid'
    and pg_temp.nt('P3.b_sources') = 'credit_package,credit_package,credit_package'
    and pg_temp.nt('P3.b_plans') = '- / -'
    and pg_temp.nt('P3.b_chain') = '2 Delta' and pg_temp.nt('P3.b_progress_kept') = '1'
    and pg_temp.nt('P3.b_cancel') = '- -> Delta 0.00, used -, due 1000.00'
    and pg_temp.nt('P3.b_record') = 'recorded (by line), due 0.00',
  'P3b settled, then changed to Delta: the released credit''s benefit value follows too (its release record still names the first lot, '
  || 'followed to Delta''s), every commission source found; cancelled, all S$1,100 back from Delta, nothing used, the S$1,000 recorded: '
  || (pg_temp.n('P3') - 'a_part_paid' - 'a_settled' - 'a_benefits' - 'a_sources' - 'a_plans' - 'a_cancel' - 'a_record')::text);

-- ═════ P4 Credit partly spent at the new customer ═════
select pg_temp.check(pg_temp.ot('P4.plans') = 'credit_used,credit_used / credit_used,credit_used'
    and pg_temp.ot('P4.cancel') = 'Bravo 1060.00, used credit_used, due 1000.00',
  'P4q with 417''s text both lots read spent and a cancel leaves Bravo the S$1,060 left: ' || pg_temp.o('P4')::text);
select pg_temp.check(pg_temp.nt('P4.spent') = 'paid, Bravo 1060.00'
    and pg_temp.nt('P4.benefits') = 'Bravo bonus 100.00/100.00, Bravo paid 960.00/1000.00'
    and pg_temp.nt('P4.plans') = 'credit_used / credit_used'
    and pg_temp.nt('P4.second_change') like 'P0001 These benefits have already been used and cannot move with the invoice: Paid credit 960.00 (Partly spent)%'
    and pg_temp.nt('P4.cancel') = 'Bravo 0.00, used credit_used, due 1000.00',
  'P4 Bravo spends S$40 of the Paid credit: the plans ask credit_used for it alone (true), a second change is refused as partly spent, '
  || 'a cancel takes the S$1,060 left back from Bravo and reads credit_used: ' || pg_temp.n('P4')::text);

-- ═════ P5 A second change ═════
select pg_temp.check(pg_temp.ot('P5.holds') = 'Alpha 0.00 Bravo 0.00 Charlie 1100.00'
    and pg_temp.ot('P5.benefits') = 'Alpha bonus 0.00/100.00, Alpha paid 0.00/1000.00'
    and pg_temp.ot('P5.cancel') = 'credit_used,credit_used -> Charlie 1100.00, used credit_used, due 0.00 (kept for used 1000.00)',
  'P5q with 417''s text, after Alpha to Bravo to Charlie the records still name Alpha''s lots and a cancel leaves Charlie the S$1,100: ' || pg_temp.ot('P5.cancel'));
select pg_temp.check(pg_temp.nt('P5.holds') = 'Alpha 0.00 Bravo 0.00 Charlie 1100.00'
    and pg_temp.nt('P5.benefits') = 'Charlie bonus 100.00/100.00, Charlie paid 1000.00/1000.00'
    and pg_temp.nt('P5.sale') = 'Charlie bonus, Charlie paid'
    and pg_temp.nt('P5.sources') = 'credit_package,credit_package'
    and pg_temp.nt('P5.chain') = '3 Charlie'
    and pg_temp.nt('P5.plans') = '- / -'
    and pg_temp.nt('P5.cancel') = '- -> Charlie 0.00, used -, due 1000.00'
    and pg_temp.nt('P5.record') = 'recorded (by line), due 0.00',
  'P5 Alpha to Bravo to Charlie: the records name Charlie''s lots, the chain walks Alpha, Bravo, Charlie; cancelled, back from Charlie, the S$1,000 recorded: '
  || pg_temp.n('P5')::text);

-- ═════ P6 A Move after the change ═════
select pg_temp.check(pg_temp.ot('P6.move') = 'refused: No unused value remains to move',
  'P6q with 417''s text, after the change the Move of the Paid credit is refused (the benefit names Alpha''s emptied lot): ' || pg_temp.ot('P6.move'));
select pg_temp.check(pg_temp.nt('P6.move') = 'ok'
    and pg_temp.nt('P6.holds') = 'Alpha 0.00 Bravo 100.00 Delta 1000.00'
    and pg_temp.nt('P6.benefits') = 'Bravo bonus 100.00/100.00, Bravo paid 0.00/1000.00, Delta paid 1000.00/1000.00'
    and pg_temp.nt('P6.sources') = 'credit_package,credit_package,credit_package'
    and pg_temp.nt('P6.plans') = '- / -'
    and pg_temp.nt('P6.cancel') = '- -> Bravo 0.00 Delta 0.00, used -, due 1000.00'
    and pg_temp.nt('P6.record') = 'recorded (by line), due 0.00',
  'P6 changed to Bravo, then Bravo''s Paid credit moved to Delta: the Move works, no override; cancelled, Delta''s S$1,000 and Bravo''s S$100 come back, '
  || 'nothing used, the S$1,000 recorded: ' || pg_temp.n('P6')::text);

-- ═════ P7 A change after a Move ═════
select pg_temp.check(pg_temp.ot('P7.cancel') = 'credit_used -> Bravo 100.00 Delta 0.00, used credit_used, due 909.09 (kept for used 90.91)',
  'P7q with 417''s text Bravo keeps the S$100 Bonus after a cancel: ' || pg_temp.ot('P7.cancel'));
select pg_temp.check(pg_temp.nt('P7.move') = 'ok'
    and pg_temp.nt('P7.holds') = 'Alpha 0.00 Bravo 100.00 Delta 1000.00'
    and pg_temp.nt('P7.benefits') = 'Alpha paid 0.00/1000.00, Bravo bonus 100.00/100.00, Delta paid 1000.00/1000.00'
    and pg_temp.nt('P7.sale') = 'Alpha paid, Bravo bonus'
    and pg_temp.nt('P7.sources') = 'credit_package,credit_package,credit_package'
    and pg_temp.nt('P7.plans') = '- / -'
    and pg_temp.nt('P7.cancel') = '- -> Bravo 0.00 Delta 0.00, used -, due 1000.00'
    and pg_temp.nt('P7.record') = 'recorded (by line), due 0.00',
  'P7 Alpha''s Paid credit moved to Delta, then the invoice changed to Bravo: Bravo gets the Bonus and its records, Delta keeps the Paid '
  || '(the emptied lot it came from keeps its records); cancelled, both come back, the S$1,000 recorded: ' || pg_temp.n('P7')::text);

-- ═════ V 445's V path without a merge ═════
select pg_temp.check(pg_temp.ot('V.holds') = 'Alpha 0.00 Bravo 0.00 Zulu 300.00 Yankee 800.00'
    and pg_temp.ot('V.cancel') = 'credit_used,credit_used -> Yankee 800.00 Zulu 0.00, used credit_used, due 272.73 (kept for used 727.27)',
  'Vq with 417''s text Yankee keeps the S$800 after a cancel: ' || pg_temp.ot('V.cancel'));
select pg_temp.check(pg_temp.nt('V.move') = 'ok'
    and pg_temp.nt('V.holds') = 'Alpha 0.00 Bravo 0.00 Zulu 300.00 Yankee 800.00'
    and pg_temp.n('V.z_link_is_null') = 'true'
    and pg_temp.nt('V.chain') = '2 Bravo'
    and pg_temp.nt('V.benefits') = 'Bravo paid 0.00/300.00, Yankee bonus 100.00/100.00, Yankee paid 700.00/700.00, Zulu paid 300.00/300.00'
    and pg_temp.nt('V.sale') = 'Yankee bonus, Yankee paid'
    and pg_temp.nt('V.sources') = 'credit_package,credit_package,credit_package,credit_package'
    and pg_temp.nt('V.plans') = '- / -'
    and pg_temp.nt('V.z_refund') = 'ok, Zulu 190.00, Yankee 800.00'
    and pg_temp.nt('V.cancel') = '- -> Yankee 0.00 Zulu 0.00, used -, due 1000.00'
    and pg_temp.nt('V.record') = 'recorded (by line), due 0.00',
  'V part-paid by Alpha, changed to Bravo, settled, the released credit moved to Zulu, changed to Yankee: Yankee gets the 700 Paid and 100 Bonus '
  || 'and their records, Zulu keeps the moved 300 (no link; the chain stays off it), every commission source found, a refund of S$100 of Zulu''s '
  || 'credit goes through; cancelled, back from Yankee and Zulu, the S$1,000 recorded: ' || pg_temp.n('V')::text);

-- ═════ E A lot whose benefit value was moved on ═════
-- (Where 462 is in, its records follow too: the Move's credit is traced
-- through the Move's own ledger rows, not through that lot.)
select pg_temp.check(pg_temp.nt('E.move') = 'ok'
    and pg_temp.nt('E.holds') = 'Alpha 0.00 Bravo 1100.00 Delta 1000.00'
    and case when pg_temp.with_462()
             then pg_temp.n('E.paid_kept') = 'false'
                  and pg_temp.nt('E.benefits') = 'Bravo bonus 100.00/100.00, Bravo paid 1000.00/1000.00, Delta paid 1000.00/1000.00'
                  and pg_temp.nt('E.sale') = 'Bravo bonus, Bravo paid'
             else pg_temp.n('E.paid_kept') = 'true'
                  and pg_temp.nt('E.benefits') = 'Alpha paid 0.00/1000.00, Bravo bonus 100.00/100.00, Delta paid 1000.00/1000.00'
                  and pg_temp.nt('E.sale') = 'Alpha paid, Bravo bonus' end
    and pg_temp.o('E') - 'benefits' - 'sale' - 'paid_kept' = pg_temp.n('E') - 'benefits' - 'sale' - 'paid_kept',
  'E a lot whose benefit value was moved on (all its credit put back) moves with the invoice but keeps its records where they were (447''s 2.; '
  || 'with 462 in, its records follow too); the Bonus''s follow: ' || pg_temp.n('E')::text
  || case when pg_temp.o('E') - 'benefits' - 'sale' - 'paid_kept' = pg_temp.n('E') - 'benefits' - 'sale' - 'paid_kept' then ''
          else ' (with 417''s text: ' || pg_temp.o('E')::text || ')' end);

-- ═════ U Vouchers move in place ═════
select pg_temp.check(pg_temp.n('U') = pg_temp.o('U')
    and pg_temp.nt('U.voucher') = 'Bravo held 1 same row'
    and pg_temp.n('U.benefit_row_same') = 'true'
    and pg_temp.n('U.audit') = '{"vouchers": 1, "allowances": 0, "credit_lots": 0}'
    and pg_temp.nt('U.plans') = '- / -'
    and pg_temp.nt('U.cancel') = 'revoked, used -, due 30.00'
    and pg_temp.nt('U.record') = 'recorded (one line), due 0.00',
  'U a voucher-only invoice changed to Bravo: the voucher moves in place (the same row, held), its benefit value is untouched; exactly as with 417''s text: '
  || pg_temp.n('U')::text || case when pg_temp.n('U') = pg_temp.o('U') then '' else ' (with 417''s text: ' || pg_temp.o('U')::text || ')' end);

-- ═════ B A voucher and a Credit Package on one invoice ═════
select pg_temp.check(pg_temp.ot('B.cancel') = 'credit_used,credit_used -> Bravo 1100.00, voucher revoked, used credit_used, due 30.00 (kept for used 1000.00)',
  'Bq with 417''s text the voucher comes back but Bravo keeps the S$1,100: ' || pg_temp.ot('B.cancel'));
select pg_temp.check(pg_temp.nt('B.holds') = 'Alpha 0.00 Bravo 1100.00'
    and pg_temp.nt('B.voucher') = 'Bravo held'
    and pg_temp.nt('B.benefits') = 'Bravo bonus 100.00/100.00, Bravo paid 1000.00/1000.00'
    and pg_temp.nt('B.sale') = 'Bravo bonus, Bravo paid'
    and pg_temp.nt('B.plans') = '- / -'
    and pg_temp.nt('B.cancel') = '- -> Bravo 0.00, voucher revoked, used -, due 1030.00'
    and pg_temp.nt('B.record') = 'recorded (by line), due 0.00',
  'B a voucher and a package changed to Bravo: the voucher in place, the credit''s records follow; cancelled, both come back from Bravo, '
  || 'nothing used, the S$1,030 recorded: ' || (pg_temp.n('B') - 'world')::text);

-- ═════ N The customer change writes the same records ═════
select pg_temp.check(pg_temp.n('B.world') = pg_temp.o('B.world')
    and jsonb_array_length(pg_temp.n('B.world.lots')) = 4 and jsonb_array_length(pg_temp.n('B.world.ledger')) >= 6,
  'N the customer change writes the same records with 447''s text as with 417''s: the lots, the ledger rows, the voucher, the benefit values '
  || '(but for their lot) and its audit row (' || (pg_temp.n('B.world') -> 'audit')::text || ')'
  || case when pg_temp.n('B.world') = pg_temp.o('B.world') then ''
          else E'\n  447: ' || pg_temp.n('B.world')::text || E'\n  417: ' || pg_temp.o('B.world')::text end);

-- ═════ S A shared package (141 split) ═════
select pg_temp.check(pg_temp.ot('S.split_lots') = 'Quebec 400.00 -> Quebec 0.00, Oscar 600.00 -> Oscar 0.00',
  'Sq with 417''s text the split names the shares'' emptied lots: ' || pg_temp.ot('S.split_lots'));
select pg_temp.check(pg_temp.nt('S.holds') = pg_temp.ot('S.holds')
    and pg_temp.nt('S.split_lots') = 'Quebec 400.00 -> Bravo 1000.00, Oscar 600.00 -> Bravo 1000.00'
    and pg_temp.nt('S.sale') not like '%Quebec%' and pg_temp.nt('S.sale') not like '%Oscar%',
  'S a shared package changed to Bravo (every share goes, as since 321): the split''s issued lots and the shares'' sales name Bravo''s lots '
  || '(the split keeps naming the share''s customer: NOT COVERED): ' || pg_temp.n('S')::text);

do $$
declare n int; m text;
begin
  select count(*), string_agg(msg, E'\n  ') into n, m from failed;
  if n > 0 then raise exception E'customer-change-credit-447: % check(s) failed:\n  %', n, m; end if;
  raise notice 'customer-change-credit-447: all checks passed';
end $$;
rollback;
