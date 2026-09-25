-- Part-payment commission: re-settlement, take-backs and cancellations (357).
--
-- part-payments-earn.sql covers money arriving in parts. This file covers the
-- fixes to what happens when money goes the other way, or comes back:
--
--   1. 8c   A package / bundle that settled, fell back to part-paid (payment
--           corrected down) and is paid in full again through Record Payment
--           earns its affiliate commission again. Before: Record Payment
--           re-earned only invoice lines and staff, so the package / bundle
--           commission reversed at the fall-back was lost for good (0).
--   1b. 3/8c The same steps, all in one transaction with no timestamp shift.
--           While it is part-paid again the package / bundle line holds its
--           share of the affiliate commission, like a product line: 400/1000
--           of 45.00 + 15.75 = 18.00 + 6.30 (bundle 36.00 + 12.60), staff
--           12.00 (24.00). Before: invoice_package_commission_preview skipped
--           lines whose credit was issued, so the layer held 0. Paid in full
--           again: exactly the full 60.75 / 30.00 (121.50 / 60.00).
--   2. 6    Taking back part of the unpaid staff part-payment commission on a
--           date is shared by everyone holding commission on that date, in
--           proportion, and stays on that date: each holder's rows there are
--           reversed and what they keep is written again as ONE row on the
--           same date. No negative rows for unpaid money. A dry run reports
--           each take-back on the date it lands on. Before: the newest row
--           alone gave the 3.00 back (and before that, it landed today).
--   2b. 6   The same with unequal holdings on one date (a roster change between
--           two registrations): 18.00 / 6.00 give back 3.76 / 1.25 of 5.01,
--           to the cent, the larger holder more.
--   3. 6    A settled invoice whose part payment was registered last month is
--           cancelled: every month squares to 0. Before: the instalment rows
--           netted to zero, sync returned early, and last month kept +60 while
--           this month carried -60.
--   4. 5b/6 40 of last month's 60 was paid out, then the part-paid invoice is
--           cancelled: the unpaid 20 is taken back IN last month (a linked
--           negative row), only the paid-out 40 lands today, and no further
--           payout for last month is possible. Also: a row larger than what is
--           taken back gets a linked negative in its own month, and a dry run
--           reports it dated that row's own date.
--   5. 5    The instalment affiliate target honours line refunds: after a line
--           refund and a payment corrected down, the layer holds the kept
--           settlement x share received. Before: it was computed on the
--           unrefunded line.
--   6. 8c   A FIRST settlement after a line refund recorded while the invoice
--           was part-paid settles through reconcile, so the refund counts:
--           affiliate 364.50 (before: 405.00, the unrefunded lines); staff
--           54.00, the pool on the 1,800 kept. An explicit reconcile afterwards
--           changes no one's amount.
--   7. 6    Part paid AND settled last month (part-payment row +60.00, close
--           row -60.00, settlement 150.00), 30.00 of the +60.00 row paid out,
--           then cancelled this month. The close row's month has had a payout,
--           so it is not reversed: a linked +60.00 cancels it in its own
--           month, the unpaid 30.00 goes by a linked -30.00 in its own month,
--           and only the 30.00 paid out is taken back today (one -30.00
--           'Part-payment commission squared' row). Last month 0, this month
--           -30.00, nothing positive dated this month, no further payout for
--           either month. Before: the close row stood and the squaring row was
--           +30.00 today: last month -60.00, this month +30.00, and a 30.00
--           payout on the cancelled sale was accepted.
--   7b. 6   Part paid two months ago (never paid out), settled last month,
--           last month paid out in full (90.00), cancelled this month: two
--           months ago 0, last month -90.00 (what was paid), this month 0,
--           nothing payable in any month. Before: last month -150.00, this
--           month +60.00 payable.
--   7c. 6   As 7b, but last month counts as paid only because of a 10.00
--           payout that went to ANOTHER invoice of the same referrer. The close
--           row is still cancelled in its own month, so the cancelled invoice
--           nets 0 in every month and last month is exactly the other
--           invoice's 140.00 unpaid. Before: last month 80.00, this month
--           +60.00 payable.
--   8.      Lock order: sync_instalment_commissions takes affiliate_payout_lock
--           then staff_payout_lock (settlement's order), both before its first
--           insert or update (read from its source), and a part payment whose
--           sync writes affiliate rows only (a store with no commission staff)
--           holds both advisory locks. Before: only the affiliate lock, taken
--           by the first affiliate write. Scenario 8 runs FIRST, straight after
--           the fixtures: a transaction-level advisory lock is held until the
--           transaction ends, so once any scenario has written commission both
--           locks are held and the runtime check could prove nothing.
--   9.  a   Referrer R also has invoice Y settled last month (+150.00). X is
--           part paid 400 two months ago (+60.00), and a 60.00 payout for that
--           month is allocated to the +60.00 row. Last month X's payment is
--           corrected to 200: the +60.00 row is fully paid, so the 30.00 goes
--           by a new -30.00 row marked 'Paid-out part-payment commission taken
--           back', dated last month; a 120.00 payout for last month nets it
--           (last month 0). This month X is cancelled: the take-back stands
--           where it is and the squaring takes back only the rest: two months
--           ago 0, last month 0, this month -30.00, no further payout for last
--           month. Before: the take-back was unmarked, so the squaring
--           cancelled it with a linked +30.00 last month (+30.00 payable, and
--           a 30.00 payout accepted) and took back -60.00 today.
--   9b. a   The same with no payout for last month: last month stays 120.00
--           (Y's 150.00 less the take-back), unchanged by the cancel, and the
--           squaring is -30.00. Before: the take-back was reversed, last month
--           150.00, the squaring -60.00.
--   10. b   A payout lowered after the cancel: +60.00 last month, 40.00 of it
--           paid out, cancelled (linked -20.00 last month, -40.00 squaring
--           today); the payout is corrected 40.00 -> 10.00 with
--           affiliate_payout_save (its id and version) and the invoice is
--           reconciled. Last month 0 (the 30.00 unpaid again is taken back
--           there), this month -10.00 (a linked +30.00 against the squaring
--           row, in its month), R owes exactly the 10.00 paid out, nothing
--           payable, no review audit. Before: this month stayed -40.00, and
--           every sync wrote another 'instalment_commission_review_required'
--           audit (left_over -30.00).
--   10b. b  Lowered below what the take-backs recovered: as 9, then the payout
--           for two months ago is corrected 60.00 -> 10.00. The 50.00 unpaid
--           again goes in its month; the recovery rows give the over-recovery
--           back, newest first, each in its own month and never beyond what it
--           takes back: the squaring row +30.00 (this month 0), the take-back
--           +20.00 (last month). X then nets to 0 and R is owed exactly what
--           the other invoice earned less everything paid (150 - 130 = 20.00,
--           in last month, the other invoice's month). No review audit, and a
--           later sync or reconcile writes nothing. Before: this month -60.00,
--           nothing given back, an audit of -50.00 on every sync.
--
-- After each scenario, sync_instalment_commissions(invoice, 'again') returns
-- nothing and writes nothing (no commission row, no audit row). After 7, 7b,
-- 7c, 9, 9b, 10 and 10b a dry run on the cancelled invoice also returns
-- nothing and writes nothing; no 'instalment_commission_review_required' audit
-- was written.
--
-- Scenario 3 runs twice: in a staffed store, and in a store with no
-- commission staff, where only the affiliate rows (netting to zero after
-- settlement) decide whether sync returns early.
--
-- Scenarios 1, 3, 4, 4b and 5 were checked to FAIL against the pre-fix code by
-- re-creating the patched function without its fix inside a rolled-back
-- transaction (Record Payment without the reconcile branch; the closed-invoice
-- early return and squaring block removed; linked negatives dated today;
-- commission_unpaid_amount without allocations; the targets without the
-- line-refund share). So were 1b (the package preview skipping issued lines;
-- 8c deciding by comparing timestamps with transaction_timestamp()) and 6 (8c
-- without its refund condition). 7, 7b and 7c fail against the closed-invoice
-- path as review found it (a negative row whose month had a payout left
-- standing, and the squaring row written as -remainder whatever its sign, so
-- positive); 8 against the sync without its two up-front locks (its source
-- check also fails with the two locks taken staff first). In 7, 7b and 7c the
-- tier-2 checks (tier 2 is never paid out, so its close row is reversed either
-- way), the invoice-total checks, the sum over all months in 7, and the
-- idempotency, dry-run and audit checks are guards: they pass either way.
-- 9, 9b, 10 and 10b were run against the sync as review found it (no marker on
-- a paid-out take-back; a lowered payout only audited, on every sync), and
-- against the current sync with only (a) or only (b) removed: 9 / 9b fail
-- without (a) (the marker, the take-back standing, last month, this month, the
-- only row today, the further payout), 10 fails without (b) (this month, what
-- R owes, the audit, idempotency), 10b without either. Guards: in 9 / 9b the
-- fixture checks, the +60.00 row standing, the sum over all months, tier 2,
-- the audit and idempotency checks; in 10 / 10b the fixture checks (except
-- 10b's first, which needs (a)), the linked take-back in its own month, and
-- "nothing payable" in 10; every dry run.
--
-- NOTE ON TIMESTAMPS. In production every RPC is its own transaction; here
-- everything runs in ONE transaction, so rows written with now() carry the
-- same timestamp. 8c no longer compares timestamps: whether full payment
-- settles through reconcile is decided on entry to Record Payment, before the
-- payment writes anything, from rows that exist (package / bundle sales,
-- settlement commission, a refund since the invoice was opened). One
-- transaction therefore takes the same path as separate requests. Scenario 1
-- still shifts the invoice's sale and commission timestamps back one minute
-- between steps (pg_temp.as_if_earlier), the shape separate requests leave;
-- scenario 1b runs the same steps with no shift and must reach the same
-- totals. Against a Record Payment that compares timestamps (the earlier 8c)
-- scenario 1 still passes and 1b fails, which is what the shift was for. No
-- other scenario needs it any more (the whole file passes with it as a no-op),
-- so no other scenario uses it.
--
-- Everything goes through the real entry points: record_invoice_payment,
-- correct_invoice_payment, cancel_invoice_recorded, refund_invoice_recorded,
-- affiliate_payout_save. "Last month" part payments are registered with
-- sync_instalment_commissions(p_credit_date => the 15th of last month,
-- p_register => true) while the switch is off, then the switch goes back on
-- (7b and 7c: the 15th of the month before). Scenario 7 settles "last month":
-- Record Payment dates the close and settlement rows today, so
-- pg_temp.as_if_settled_on moves the rows that settlement wrote to the 20th of
-- last month (7c moves its other invoice's rows to the 5th), the rows a
-- settlement recorded last month would have left. 9, 9b and 10b register X's
-- part payment two months ago the same way, move Y's settlement to the 5th of
-- last month, and correct X's payment "last month": the correction dates its
-- take-back of paid-out commission today, so pg_temp.as_if_recorded_on moves
-- the one row it dated today to the 15th of last month.
-- Two checks run sync_instalment_commissions as a dry run with a rate lowered
-- (the money unchanged) to read what a take-back would report; scenario 6
-- runs reconcile_invoice_commissions once more as a control.
--
-- Every check prints PASS or FAIL and the run continues; the last block raises
-- if anything failed. Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '60s';
set local statement_timeout = '300s';

create temp table ppt_results(n serial primary key, scenario text, ok boolean, msg text);
create function pg_temp.check(p_scenario text, ok boolean, msg text) returns void language plpgsql as $$
begin
  insert into ppt_results(scenario, ok, msg) values (p_scenario, coalesce(ok, false), msg);
  if ok is distinct from true then raise notice 'FAIL: [%] %', p_scenario, msg;
  else raise notice 'PASS: [%] %', p_scenario, msg; end if;
end $$;
-- A scenario that errors is a failure, recorded after its block rolls back.
create function pg_temp.errored(p_scenario text, p_err text) returns void language plpgsql as $$
begin
  insert into ppt_results(scenario, ok, msg) values (p_scenario, false, 'scenario raised: ' || p_err);
  raise notice 'FAIL: [%] scenario raised: %', p_scenario, p_err;
end $$;

create function pg_temp.sfx() returns text language sql volatile as
$$ select substr(md5(random()::text || clock_timestamp()::text), 1, 8) $$;
create function pg_temp.phone() returns text language sql volatile as
$$ select '+659' || floor(random() * 9)::int::text || lpad(floor(random() * 1000000)::int::text, 6, '0') $$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(p_key text) returns uuid language sql stable as $$ select f.v from fx f where f.k = p_key $$;

-- Live commission on an invoice (both layers).
create function pg_temp.staff_live(p_inv uuid) returns numeric language sql as
$$ select coalesce(sum(sc.commission_amount),0) from staff_commissions sc where sc.invoice_id = p_inv and sc.status in ('earned','paid') $$;
create function pg_temp.aff(p_inv uuid) returns numeric language sql as
$$ select coalesce(sum(c.commission_amount),0) from commissions c where c.invoice_id = p_inv and c.status in ('earned','paid') $$;
create function pg_temp.aff_of(p_inv uuid, p_ref uuid) returns numeric language sql as
$$ select coalesce(sum(c.commission_amount),0) from commissions c
    where c.invoice_id = p_inv and c.referrer_customer_id = p_ref and c.status in ('earned','paid') $$;
create function pg_temp.aff_layer(p_inv uuid, p_basis text) returns numeric language sql as
$$ select coalesce(sum(c.commission_amount),0) from commissions c
    where c.invoice_id = p_inv and c.earning_basis = p_basis and c.status in ('earned','paid') $$;
-- What an affiliate can still be paid for a month (0 when the month has no live rows).
create function pg_temp.balance(p_ref uuid, p_month date) returns numeric language sql as
$$ select coalesce((select b.balance from affiliate_month_balances() b where b.referrer = p_ref and b.month = p_month), 0) $$;

create function pg_temp.prev() returns date language sql stable as
$$ select (date_trunc('month', sg_today()::timestamp) - interval '1 month')::date + 14 $$;
create function pg_temp.prev_m() returns date language sql stable as
$$ select (date_trunc('month', sg_today()::timestamp) - interval '1 month')::date $$;
create function pg_temp.cur_m() returns date language sql stable as
$$ select date_trunc('month', sg_today()::timestamp)::date $$;
-- The month before last (7b, 7c).
create function pg_temp.prev2() returns date language sql stable as
$$ select (date_trunc('month', sg_today()::timestamp) - interval '2 month')::date + 14 $$;
create function pg_temp.prev2_m() returns date language sql stable as
$$ select (date_trunc('month', sg_today()::timestamp) - interval '2 month')::date $$;

create function pg_temp.customer(p_name text, p_referrer uuid default null) returns uuid language plpgsql as $$
declare v_id uuid;
begin
  insert into customers(full_name, phone, referred_by) values (p_name, pg_temp.phone(), p_referrer) returning id into v_id;
  return v_id;
end $$;
-- An active referrer with an active tier-2 referrer above; returns tier 1.
create function pg_temp.referrers(p_label text) returns uuid language plpgsql as $$
declare v_t2 uuid; v_t1 uuid;
begin
  v_t2 := pg_temp.customer('PPT ' || p_label || ' tier2');
  v_t1 := pg_temp.customer('PPT ' || p_label || ' tier1', v_t2);
  insert into customer_affiliates(customer_id, status) values (v_t1, 'active'), (v_t2, 'active');
  return v_t1;
end $$;
create function pg_temp.tier2_of(p_ref uuid) returns uuid language sql stable as
$$ select c.referred_by from customers c where c.id = p_ref $$;
create function pg_temp.product_invoice(p_customer uuid, p_product uuid, p_qty int default 1, p_store uuid default null) returns uuid language sql as
$$ select create_invoice_with_details(coalesce(p_store, pg_temp.fx('st')), p_customer,
     jsonb_build_array(jsonb_build_object('kind','product','product_id',p_product,'quantity',p_qty)),
     jsonb_build_object('business_date', sg_today()::text)) $$;
create function pg_temp.pay(p_inv uuid, p_amount numeric) returns void language plpgsql as $$
begin
  perform record_invoice_payment(p_inv, jsonb_build_array(jsonb_build_object(
    'payment_method_id', pg_temp.fx('m'), 'amount', p_amount)), gen_random_uuid());
end $$;
-- A part payment registered in an earlier month: taken with the switch off (it
-- earns nothing), registered dated p_date, then the switch is on again.
create function pg_temp.pay_registered_on(p_inv uuid, p_amount numeric, p_date date) returns void language plpgsql as $$
begin
  update app_settings set instalment_commission_from = null where id = true;
  perform pg_temp.pay(p_inv, p_amount);
  perform * from sync_instalment_commissions(p_inv, 'Part payment registered in an earlier month (test)', p_date, false, true);
  update app_settings set instalment_commission_from = sg_today() where id = true;
end $$;
-- A part payment registered LAST month, dated the 15th of last month.
create function pg_temp.pay_last_month(p_inv uuid, p_amount numeric) returns void language plpgsql as $$
begin
  perform pg_temp.pay_registered_on(p_inv, p_amount, pg_temp.prev());
end $$;
-- As if the settlement had been recorded on p_date (scenario 7): Record Payment
-- dates the close rows today and the settlement rows by paid_at (the UTC
-- date), so every commission and staff row of the invoice dated after the
-- 15th of last month, i.e. written by the settlement, moves to p_date.
create function pg_temp.as_if_settled_on(p_inv uuid, p_date date) returns void language plpgsql as $$
begin
  update commissions c set invoice_paid_date = p_date where c.invoice_id = p_inv and c.invoice_paid_date > pg_temp.prev();
  update staff_commissions sc set invoice_paid_date = p_date where sc.invoice_id = p_inv and sc.invoice_paid_date > pg_temp.prev();
end $$;
-- As if the change just made to the invoice had been recorded on p_date
-- (scenario 9): the sync dates a take-back of paid-out commission today, so
-- the invoice's rows dated today move to p_date. Returns how many commission
-- rows moved.
create function pg_temp.as_if_recorded_on(p_inv uuid, p_date date) returns int language plpgsql as $$
declare v_n int;
begin
  update commissions c set invoice_paid_date = p_date where c.invoice_id = p_inv and c.invoice_paid_date = sg_today();
  get diagnostics v_n = row_count;
  update staff_commissions sc set invoice_paid_date = p_date where sc.invoice_id = p_inv and sc.invoice_paid_date = sg_today();
  return v_n;
end $$;
-- What affiliate_payout_save answers to a payout for p_month. An accepted
-- payout is rolled back (so a failing check leaves the scenario unchanged) and
-- reported as 'accepted'.
create function pg_temp.payout_attempt(p_ref uuid, p_month date, p_amount numeric) returns text language plpgsql as $$
begin
  perform affiliate_payout_save(null, null, p_ref, p_month, p_amount, pg_temp.fx('m'), sg_today(), 'PPT further payout', null, null, gen_random_uuid());
  raise exception 'accepted';
exception when others then
  return sqlerrm;
end $$;
-- Which of the two commission payout locks (affiliate 728041903110, staff
-- 728041903111; pg_advisory_xact_lock(bigint) shows as classid = high 32 bits,
-- objid = low 32 bits) this transaction holds.
create function pg_temp.commission_locks_held() returns text language sql as $$
  select coalesce(string_agg(x.k::text, ',' order by x.k), 'none')
    from (select (l.classid::bigint << 32) | l.objid::bigint as k from pg_locks l
           where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.granted and l.objsubid = 1) x
   where x.k in (728041903110, 728041903111)
$$;
create function pg_temp.current_payment(p_inv uuid) returns uuid language sql stable as
$$ select p.id from invoice_payments p where p.invoice_id = p_inv and p.entry_kind in ('receipt','correction_replacement')
      and not exists (select 1 from invoice_payments q where q.corrects_payment_id = p.id and q.entry_kind = 'correction_reversal')
    order by p.created_at, p.id limit 1 $$;
create function pg_temp.correct_to(p_inv uuid, p_amount numeric) returns void language plpgsql as $$
begin
  perform correct_invoice_payment(pg_temp.current_payment(p_inv), p_amount, sg_today(), pg_temp.fx('m'),
    'Keyed wrongly', gen_random_uuid());
end $$;
-- As if everything so far on this invoice had been committed by an earlier
-- request (scenario 1 only; see the note on timestamps).
create function pg_temp.as_if_earlier(p_inv uuid) returns void language plpgsql as $$
begin
  update credit_package_sales s set sold_at = s.sold_at - interval '1 minute' where s.invoice_id = p_inv;
  update premium_bundle_sales s set sold_at = s.sold_at - interval '1 minute' where s.invoice_id = p_inv;
  update commissions c set created_at = c.created_at - interval '1 minute' where c.invoice_id = p_inv;
  update staff_commissions sc set created_at = sc.created_at - interval '1 minute' where sc.invoice_id = p_inv;
end $$;
-- Every commission row of the invoice, as it stands (status changes included).
create function pg_temp.fingerprint(p_inv uuid) returns text language sql stable as $$
  select md5(coalesce((select string_agg(concat_ws('|', c.id, c.status, c.commission_amount, c.invoice_paid_date, c.adjusts_commission_id, c.payout_id), ',' order by c.id)
                         from commissions c where c.invoice_id = p_inv), '')
          || '#' || coalesce((select string_agg(concat_ws('|', sc.id, sc.status, sc.commission_amount, sc.invoice_paid_date, sc.payout_id), ',' order by sc.id)
                         from staff_commissions sc where sc.invoice_id = p_inv), ''))
$$;
-- What each beneficiary holds on the invoice, per layer / tier / line / date
-- (row ids and statuses aside). reconcile_invoice_commissions reissues unpaid
-- settlement rows on every call, even on a plainly settled invoice, so a
-- reconcile that changes nothing leaves this equal, not the fingerprint.
create function pg_temp.holdings(p_inv uuid) returns text language sql stable as $$
  select coalesce((select string_agg(k, ',' order by k) from (
            select concat_ws('|', c.referrer_customer_id, c.tier, c.product_type, c.invoice_item_id, c.earning_basis,
                             c.invoice_paid_date, sum(c.commission_amount)) as k
              from commissions c where c.invoice_id = p_inv and c.status in ('earned','paid')
             group by c.referrer_customer_id, c.tier, c.product_type, c.invoice_item_id, c.earning_basis, c.invoice_paid_date) a), '')
      || '#' || coalesce((select string_agg(k, ',' order by k) from (
            select concat_ws('|', sc.staff_id, sc.earning_basis, sc.invoice_paid_date, sum(sc.commission_amount)) as k
              from staff_commissions sc where sc.invoice_id = p_inv and sc.status in ('earned','paid')
             group by sc.staff_id, sc.earning_basis, sc.invoice_paid_date) s), '')
$$;
-- Idempotency: a second sync returns no rows and changes no row. Every audit
-- the sync writes (synced, no staff, review required) is keyed on the invoice.
create function pg_temp.idempotent(p_scenario text, p_inv uuid) returns void language plpgsql as $$
declare v_fp text := pg_temp.fingerprint(p_inv); v_n int;
  v_audit int := (select count(*) from audit_logs a where a.record_id = p_inv);
begin
  select count(*) into v_n from sync_instalment_commissions(p_inv, 'again');
  perform pg_temp.check(p_scenario, v_n = 0 and pg_temp.fingerprint(p_inv) = v_fp
      and (select count(*) from audit_logs a where a.record_id = p_inv) = v_audit,
    format('idempotent: sync_instalment_commissions(invoice, ''again'') returns %s rows and writes nothing (no row, no audit)', v_n));
end $$;
-- A dry run returns nothing and writes nothing.
create function pg_temp.dry_run_quiet(p_scenario text, p_inv uuid) returns void language plpgsql as $$
declare v_fp text := pg_temp.fingerprint(p_inv); v_n int;
  v_audit int := (select count(*) from audit_logs a where a.record_id = p_inv);
begin
  select count(*) into v_n from sync_instalment_commissions(p_inv, 'dry run', null, true);
  perform pg_temp.check(p_scenario, v_n = 0 and pg_temp.fingerprint(p_inv) = v_fp
      and (select count(*) from audit_logs a where a.record_id = p_inv) = v_audit,
    format('dry run on the cancelled invoice returns %s rows and writes nothing (no row, no audit)', v_n));
end $$;

-- ═════ Fixtures ═════
do $$
declare own uuid := gen_random_uuid(); s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid(); sfx text := pg_temp.sfx();
  st uuid; st0 uuid; m uuid; p1000 uuid; p1000b uuid; p500 uuid; cp uuid; pb uuid;
begin
  insert into auth.users(id,email) values (own,'ppt-own-'||sfx||'@tests.invalid'),
    (s1,'ppt-s1-'||sfx||'@tests.invalid'),(s2,'ppt-s2-'||sfx||'@tests.invalid');
  insert into profiles(id,full_name,email,role) values (own,'PPT Owner','ppt-own-'||sfx||'@tests.invalid','owner'),
    (s1,'PPT Staff A','ppt-s1-'||sfx||'@tests.invalid','staff'),(s2,'PPT Staff B','ppt-s2-'||sfx||'@tests.invalid','staff');
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name,code,country_code) values ('PPT Store','PPT-'||sfx,'SG') returning id into st;
  insert into user_store_assignments(user_id,store_id) values (s1,st),(s2,st);
  -- A store with no commission staff: an invoice there carries only affiliate rows.
  insert into stores(name,code,country_code) values ('PPT No Staff','PPT0-'||sfx,'SG') returning id into st0;
  insert into payment_methods(name,is_active) values ('PPT Cash '||sfx,true) returning id into m;
  insert into products(name,sku,product_type) values ('PPT Item 1000','PPT-1000-'||sfx,'own') returning id into p1000;
  insert into products(name,sku,product_type) values ('PPT Item 1000 B','PPT-1000B-'||sfx,'own') returning id into p1000b;
  insert into products(name,sku,product_type) values ('PPT Item 500','PPT-500-'||sfx,'own') returning id into p500;
  insert into store_inventory(store_id,product_id,current_qty) values (st,p1000,50),(st,p1000b,50),(st,p500,50),(st0,p1000,50);
  perform set_product_prices(st,p1000,1000,1000,'available');
  perform set_product_prices(st,p1000b,1000,1000,'available');
  perform set_product_prices(st0,p1000,1000,1000,'available');
  perform set_product_prices(st,p500,500,500,'available');
  insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy)
    values ('PPT Package '||sfx,1000,1000,true,true) returning id into cp;
  insert into credit_package_stores(package_id,store_id) values (cp,st);
  insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,bonus_credit_amount,free_voucher_qty,grants_reward)
    values ('PPT Bundle '||sfx,2000,2000,200,0,false) returning id into pb;
  insert into premium_bundle_stores(bundle_id,store_id) values (pb,st);
  -- Staff 3% split between A and B; products 15% / 35% of tier 1; packages
  -- and bundles are third-party, 4.5% / 35%. Part payments earn (switch on).
  update app_settings set staff_commission_rate=3, commission_tier1_own_rate=15, commission_tier2_own_rate=35,
    commission_tier1_third_rate=4.5, commission_tier2_third_rate=35, instalment_commission_from=sg_today() where id=true;
  insert into fx values ('own',own),('s1',s1),('s2',s2),('st',st),('st0',st0),('m',m),('p1000',p1000),('p1000b',p1000b),('p500',p500),('cp',cp),('pb',pb);
  perform pg_temp.check('fixture', pg_temp.prev() < pg_temp.cur_m() and pg_temp.prev() >= pg_temp.prev_m()
      and pg_temp.prev2() < pg_temp.prev_m() and pg_temp.prev2() >= pg_temp.prev2_m(),
    format('"last month" is %s, "two months ago" %s, this month starts %s', pg_temp.prev(), pg_temp.prev2(), pg_temp.cur_m()));
end $$;

-- ═════ 8. Lock order: the affiliate lock, then the staff lock, before any write (b) ═════
-- FIRST, before any scenario writes commission (see the header).
do $$
declare v_sc text := '8 lock order'; v_src text; v_aff int; v_staff int; v_write int; v_before text;
  v_ref uuid; v_buyer uuid; v_inv uuid;
begin
  -- From the source: commission_write_locks() takes the affiliate lock, then
  -- the staff lock; the sync takes them only right before it writes (every
  -- write block opens with it), so a sync that writes nothing takes no global
  -- lock, and no write can come before both locks.
  v_src := pg_get_functiondef('public.commission_write_locks()'::regprocedure);
  v_aff := strpos(v_src, 'perform public.affiliate_payout_lock()');
  v_staff := strpos(v_src, 'perform public.staff_payout_lock()');
  perform pg_temp.check(v_sc, v_aff > 0 and v_staff > v_aff,
    format('commission_write_locks: affiliate_payout_lock() at %s, then staff_payout_lock() at %s', v_aff, v_staff));
  v_src := pg_get_functiondef('public.sync_instalment_commissions'::regproc);
  v_write := (length(v_src) - length(replace(v_src, 'if not p_dry_run then perform public.commission_write_locks();', '')))
             / length('if not p_dry_run then perform public.commission_write_locks();');
  perform pg_temp.check(v_sc,
    v_write >= 10
    and (length(v_src) - length(replace(v_src, E'if not p_dry_run then\n', ''))) = 0
    and strpos(v_src, 'perform public.affiliate_payout_lock') = 0 and strpos(v_src, 'perform public.staff_payout_lock') = 0,
    format('sync: every write block (%s) takes both locks first through commission_write_locks, none is left without it, and no lock is taken up front', v_write));

  -- At run time: a part payment in the store with no commission staff. Its
  -- sync writes affiliate rows only, so the staff lock can only come from the
  -- sync taking it up front.
  v_before := pg_temp.commission_locks_held();
  perform pg_temp.check(v_sc, v_before = 'none',
    format('fixture: this transaction holds neither commission lock before the payment (got %s)', v_before));
  v_ref := pg_temp.referrers('S8');
  v_buyer := pg_temp.customer('PPT S8 buyer', v_ref);
  v_inv := pg_temp.product_invoice(v_buyer, pg_temp.fx('p1000'), 1, pg_temp.fx('st0'));
  perform pg_temp.pay(v_inv, 400);
  perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'partially_paid'
      and pg_temp.aff_layer(v_inv, 'instalment') = 81 and pg_temp.staff_live(v_inv) = 0
      and not exists (select 1 from staff_commissions sc where sc.invoice_id = v_inv)
      and exists (select 1 from audit_logs a where a.record_id = v_inv and a.action = 'instalment_commission_synced'),
    format('fixture: 400 of 1,000 in the no-staff store: the sync wrote 60.00 + 21.00 affiliate rows and no staff row (got %s / %s)',
      pg_temp.aff_layer(v_inv, 'instalment'), pg_temp.staff_live(v_inv)));
  perform pg_temp.check(v_sc, pg_temp.commission_locks_held() = '728041903110,728041903111',
    format('a sync that writes holds both advisory locks, affiliate 728041903110 and staff 728041903111 (pre-fix: the affiliate lock only); held: %s',
      pg_temp.commission_locks_held()));
  perform pg_temp.idempotent(v_sc, v_inv);
exception when others then
  perform pg_temp.errored(v_sc, sqlerrm);
end $$;

-- ═════ 1. Package / bundle: settled, fell back, paid in full again (8c) ═════
do $$
declare v_kind text; v_price numeric; v_part numeric; v_exp_aff numeric; v_exp_staff numeric;
  v_ref uuid; v_ref2 uuid; v_buyer uuid; v_inv uuid; v_full_aff numeric; v_full_staff numeric; v_sc text;
begin
  foreach v_kind in array array['package','bundle'] loop
    v_sc := '1 ' || v_kind;
    begin
      if v_kind = 'package' then v_price := 1000; v_part := 400; v_exp_aff := 60.75;  v_exp_staff := 30;
      else                        v_price := 2000; v_part := 800; v_exp_aff := 121.50; v_exp_staff := 60; end if;
      v_ref := pg_temp.referrers('S1 ' || v_kind); v_ref2 := pg_temp.tier2_of(v_ref);
      v_buyer := pg_temp.customer('PPT S1 buyer ' || v_kind, v_ref);
      if v_kind = 'package' then
        v_inv := create_invoice(pg_temp.fx('st'), v_buyer, null::uuid, jsonb_build_array(jsonb_build_object(
                   'kind','credit_package','credit_package_id',pg_temp.fx('cp'),'quantity',1)), 0::numeric, null::text, null::uuid, '[]'::jsonb);
      else
        v_inv := create_invoice(pg_temp.fx('st'), v_buyer, null::uuid, jsonb_build_array(jsonb_build_object(
                   'kind','premium_bundle','premium_bundle_id',pg_temp.fx('pb'),'quantity',1,'voucher_selection','[]'::jsonb)),
                   0::numeric, null::text, null::uuid, '[]'::jsonb);
      end if;
      perform pg_temp.pay(v_inv, v_price);
      v_full_aff := pg_temp.aff(v_inv); v_full_staff := pg_temp.staff_live(v_inv);
      perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'paid'
          and v_full_aff = v_exp_aff and v_full_staff = v_exp_staff and pg_temp.aff_layer(v_inv, 'instalment') = 0,
        format('fixture: paid in full, settlement pays %s affiliate / %s staff (got %s / %s)', v_exp_aff, v_exp_staff, v_full_aff, v_full_staff));
      perform pg_temp.as_if_earlier(v_inv);

      perform pg_temp.correct_to(v_inv, v_part);
      perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'partially_paid'
          and pg_temp.aff_layer(v_inv, 'settlement') = 0,
        format('fixture: the payment corrected down to %s leaves it part-paid, settlement commission reversed', v_part));
      perform pg_temp.as_if_earlier(v_inv);

      perform pg_temp.pay(v_inv, v_price - v_part);
      perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'paid', 'fixture: paid in full again through Record Payment');
      perform pg_temp.check(v_sc, pg_temp.aff(v_inv) = v_full_aff,
        format('paid in full again: live affiliate commission is the full settlement %s again (pre-fix 0), got %s', v_full_aff, pg_temp.aff(v_inv)));
      perform pg_temp.check(v_sc, pg_temp.aff_of(v_inv, v_ref) = round(v_price * 4.5 / 100, 2)
          and pg_temp.aff_of(v_inv, v_ref2) = round(round(v_price * 4.5 / 100, 2) * 35 / 100, 2),
        format('both tiers are back: tier 1 %s, tier 2 %s', pg_temp.aff_of(v_inv, v_ref), pg_temp.aff_of(v_inv, v_ref2)));
      perform pg_temp.check(v_sc, pg_temp.aff_layer(v_inv, 'instalment') = 0, 'the affiliate part-payment layer is closed');
      perform pg_temp.check(v_sc, pg_temp.staff_live(v_inv) = v_full_staff,
        format('staff total is the full pool %s, not doubled; got %s', v_full_staff, pg_temp.staff_live(v_inv)));
      perform pg_temp.idempotent(v_sc, v_inv);
    exception when others then
      perform pg_temp.errored(v_sc, sqlerrm);
    end;
  end loop;
end $$;

-- ═════ 1b. The same in ONE transaction, no timestamp shift; the part-paid layer holds the line's share (3, 8c) ═════
do $$
declare v_kind text; v_price numeric; v_part numeric; v_exp_aff numeric; v_exp_staff numeric; v_sc text;
  v_ref uuid; v_ref2 uuid; v_buyer uuid; v_inv uuid; v_t1 numeric; v_t2 numeric; v_held1 numeric; v_held2 numeric; v_target numeric;
begin
  foreach v_kind in array array['package','bundle'] loop
    v_sc := '1b ' || v_kind;
    begin
      if v_kind = 'package' then v_price := 1000; v_part := 400; v_exp_aff := 60.75;  v_exp_staff := 30;
      else                        v_price := 2000; v_part := 800; v_exp_aff := 121.50; v_exp_staff := 60; end if;
      v_ref := pg_temp.referrers('S1b ' || v_kind); v_ref2 := pg_temp.tier2_of(v_ref);
      v_buyer := pg_temp.customer('PPT S1b buyer ' || v_kind, v_ref);
      if v_kind = 'package' then
        v_inv := create_invoice(pg_temp.fx('st'), v_buyer, null::uuid, jsonb_build_array(jsonb_build_object(
                   'kind','credit_package','credit_package_id',pg_temp.fx('cp'),'quantity',1)), 0::numeric, null::text, null::uuid, '[]'::jsonb);
      else
        v_inv := create_invoice(pg_temp.fx('st'), v_buyer, null::uuid, jsonb_build_array(jsonb_build_object(
                   'kind','premium_bundle','premium_bundle_id',pg_temp.fx('pb'),'quantity',1,'voucher_selection','[]'::jsonb)),
                   0::numeric, null::text, null::uuid, '[]'::jsonb);
      end if;
      perform pg_temp.pay(v_inv, v_price);
      v_t1 := pg_temp.aff_of(v_inv, v_ref); v_t2 := pg_temp.aff_of(v_inv, v_ref2);
      perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'paid'
          and v_t1 + v_t2 = v_exp_aff and pg_temp.aff(v_inv) = v_exp_aff and pg_temp.staff_live(v_inv) = v_exp_staff,
        format('fixture: paid in full: %s tier 1 + %s tier 2 = %s affiliate, %s staff', v_t1, v_t2, pg_temp.aff(v_inv), pg_temp.staff_live(v_inv)));

      -- No pg_temp.as_if_earlier anywhere in this scenario.
      perform pg_temp.correct_to(v_inv, v_part);
      perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'partially_paid'
          and invoice_net_received(v_inv) = v_part and pg_temp.aff_layer(v_inv, 'settlement') = 0,
        format('fixture: corrected down to %s: part-paid again, settlement commission reversed', v_part));
      -- Each tier's full commission x money received / money due, rounded per row as the targets round it.
      v_held1 := round(v_t1 * v_part / v_price, 2); v_held2 := round(v_t2 * v_part / v_price, 2);
      perform pg_temp.check(v_sc, pg_temp.aff_of(v_inv, v_ref) = v_held1 and pg_temp.aff_of(v_inv, v_ref2) = v_held2
          and pg_temp.aff_layer(v_inv, 'instalment') = v_held1 + v_held2 and pg_temp.aff(v_inv) = v_held1 + v_held2,
        format('part-paid again, the %s line holds %s/%s of its commission like a product line: %s + %s = %s (pre-fix 0), got %s + %s',
          v_kind, v_part, v_price, v_held1, v_held2, v_held1 + v_held2, pg_temp.aff_of(v_inv, v_ref), pg_temp.aff_of(v_inv, v_ref2)));
      select coalesce(sum(t.amount),0) into v_target from invoice_instalment_commission_targets(v_inv) t where t.ledger = 'affiliate';
      perform pg_temp.check(v_sc, v_target = v_held1 + v_held2,
        format('invoice_instalment_commission_targets agrees: %s', v_target));
      perform pg_temp.check(v_sc, pg_temp.staff_live(v_inv) = round(v_part * 3 / 100, 2),
        format('staff holds 3%% of the %s held: %s, got %s', v_part, round(v_part * 3 / 100, 2), pg_temp.staff_live(v_inv)));
      perform pg_temp.idempotent(v_sc, v_inv);

      perform pg_temp.pay(v_inv, v_price - v_part);
      perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'paid',
        'fixture: paid in full again through Record Payment, in the same transaction');
      perform pg_temp.check(v_sc, pg_temp.aff(v_inv) = v_exp_aff and pg_temp.aff_of(v_inv, v_ref) = v_t1 and pg_temp.aff_of(v_inv, v_ref2) = v_t2,
        format('re-settled with no timestamp shift: exactly the full %s (%s + %s) again, got %s (%s + %s)',
          v_exp_aff, v_t1, v_t2, pg_temp.aff(v_inv), pg_temp.aff_of(v_inv, v_ref), pg_temp.aff_of(v_inv, v_ref2)));
      perform pg_temp.check(v_sc, pg_temp.aff_layer(v_inv, 'instalment') = 0 and pg_temp.aff_layer(v_inv, 'settlement') = v_exp_aff,
        format('the part-payment layer closes to 0; settlement holds %s', pg_temp.aff_layer(v_inv, 'settlement')));
      perform pg_temp.check(v_sc, pg_temp.staff_live(v_inv) = v_exp_staff,
        format('staff total is exactly the full pool %s, got %s', v_exp_staff, pg_temp.staff_live(v_inv)));
      perform pg_temp.idempotent(v_sc, v_inv);
    exception when others then
      perform pg_temp.errored(v_sc, sqlerrm);
    end;
  end loop;
end $$;

-- ═════ 2. Staff: a take-back is shared by the holders on that date, in its own month (6) ═════
do $$
declare v_sc text := '2 staff'; v_buyer uuid; v_inv uuid; v_n int; v_fp text; v_dry jsonb;
begin
  v_buyer := pg_temp.customer('PPT S2 buyer');
  v_inv := pg_temp.product_invoice(v_buyer, pg_temp.fx('p1000'));
  perform pg_temp.pay_last_month(v_inv, 400);
  perform pg_temp.check(v_sc, pg_temp.staff_live(v_inv) = 12
      and (select count(*) from staff_commissions sc where sc.invoice_id = v_inv and sc.status = 'earned'
             and sc.earning_basis = 'instalment' and sc.invoice_paid_date = pg_temp.prev() and sc.commission_amount = 6
             and sc.staff_id in (pg_temp.fx('s1'), pg_temp.fx('s2'))) = 2,
    format('fixture: 400 of 1000 registered last month: 6.00 each for staff A and B, dated %s', pg_temp.prev()));

  -- Dry run of the same take-back (the rate lowered to 2.25%, so 9.00 on the
  -- 400 held): each holder's share is reported on the date it lands on.
  v_fp := pg_temp.fingerprint(v_inv);
  update app_settings set staff_commission_rate = 2.25 where id = true;
  select coalesce(jsonb_agg(jsonb_build_object('who', d.o_beneficiary, 'amt', d.o_amount, 'date', d.o_date) order by d.o_beneficiary), '[]'::jsonb)
    into v_dry from sync_instalment_commissions(v_inv, 'dry run', null, true) d where d.o_ledger = 'staff';
  update app_settings set staff_commission_rate = 3 where id = true;
  perform pg_temp.check(v_sc, jsonb_array_length(v_dry) = 2
      and not exists (select 1 from jsonb_array_elements(v_dry) e
                       where (e->>'amt')::numeric <> -1.50 or (e->>'date')::date <> pg_temp.prev())
      and pg_temp.fingerprint(v_inv) = v_fp,
    format('dry run: each holder gives back -1.50, reported dated last month (%s), nothing written; got %s', pg_temp.prev(), v_dry));

  perform pg_temp.correct_to(v_inv, 300);   -- 12.00 -> 9.00: 3.00 goes, shared 1.50 / 1.50 on last month's date
  perform pg_temp.check(v_sc, pg_temp.staff_live(v_inv) = 9, format('the pool follows the money: 9.00 on 300 received, got %s', pg_temp.staff_live(v_inv)));
  select count(*) into v_n from staff_commissions sc where sc.invoice_id = v_inv and sc.status = 'reversed';
  perform pg_temp.check(v_sc, v_n = 2
      and (select count(distinct sc.staff_id) from staff_commissions sc where sc.invoice_id = v_inv and sc.status = 'reversed'
             and sc.commission_amount = 6 and sc.invoice_paid_date = pg_temp.prev()) = 2,
    format('both holders'' 6.00 rows dated last month are reversed (the take-back is shared, not the newest row alone); %s reversed', v_n));
  perform pg_temp.check(v_sc, (select count(*) from staff_commissions sc where sc.invoice_id = v_inv and sc.status in ('earned','paid')) = 2
      and (select count(*) from staff_commissions sc where sc.invoice_id = v_inv and sc.status = 'earned' and sc.earning_basis = 'instalment'
             and sc.commission_amount = 4.50 and sc.invoice_paid_date = pg_temp.prev()
             and sc.staff_id in (pg_temp.fx('s1'), pg_temp.fx('s2'))) = 2,
    'each keeps 4.50 as ONE row with the SAME invoice_paid_date (last month); each gave back 1.50 of the 3.00');
  perform pg_temp.check(v_sc, not exists (select 1 from staff_commissions sc where sc.invoice_id = v_inv and sc.invoice_paid_date >= pg_temp.cur_m()),
    'no staff row of any status is dated this month (nothing lands today)');
  perform pg_temp.check(v_sc, not exists (select 1 from staff_commissions sc where sc.invoice_id = v_inv and sc.commission_amount < 0),
    'no negative staff rows at all');
  perform pg_temp.check(v_sc, (select coalesce(sum(sc.commission_amount),0) from staff_commissions sc where sc.invoice_id = v_inv
                                 and sc.status in ('earned','paid') and sc.invoice_paid_date = pg_temp.prev()) = 9,
    'last month holds exactly the 9.00 still earned');
  perform pg_temp.idempotent(v_sc, v_inv);
exception when others then
  perform pg_temp.errored(v_sc, sqlerrm);
end $$;

-- 2b. Unequal holdings on one date: a roster change between two registrations.
-- In a store of its own, so the roster change touches no other scenario.
do $$
declare v_sc text := '2b staff, unequal'; sfx text := pg_temp.sfx(); v_a uuid := gen_random_uuid(); v_b uuid := gen_random_uuid();
  v_st uuid; v_buyer uuid; v_inv uuid; v_keep_a numeric; v_keep_b numeric; v_give_a numeric; v_give_b numeric;
begin
  insert into auth.users(id,email) values (v_a,'ppt-2ba-'||sfx||'@tests.invalid'),(v_b,'ppt-2bb-'||sfx||'@tests.invalid');
  insert into profiles(id,full_name,email,role) values (v_a,'PPT 2b Staff A','ppt-2ba-'||sfx||'@tests.invalid','staff'),
    (v_b,'PPT 2b Staff B','ppt-2bb-'||sfx||'@tests.invalid','staff');
  insert into stores(name,code,country_code) values ('PPT 2b Store','PPT2B-'||sfx,'SG') returning id into v_st;
  insert into user_store_assignments(user_id,store_id) values (v_a,v_st),(v_b,v_st);
  insert into store_inventory(store_id,product_id,current_qty) values (v_st,pg_temp.fx('p1000'),10);
  perform set_product_prices(v_st,pg_temp.fx('p1000'),1000,1000,'available');

  v_buyer := pg_temp.customer('PPT S2b buyer');
  v_inv := pg_temp.product_invoice(v_buyer, pg_temp.fx('p1000'), 1, v_st);
  perform pg_temp.pay_last_month(v_inv, 400);                      -- 12.00: A 6.00, B 6.00
  delete from user_store_assignments where user_id = v_b and store_id = v_st;   -- B leaves the store
  perform pg_temp.pay_last_month(v_inv, 400);                      -- 12.00 more, all to A
  perform pg_temp.check(v_sc, pg_temp.staff_live(v_inv) = 24
      and (select sum(sc.commission_amount) from staff_commissions sc where sc.invoice_id = v_inv and sc.staff_id = v_a
             and sc.status = 'earned' and sc.invoice_paid_date = pg_temp.prev()) = 18
      and (select count(*) from staff_commissions sc where sc.invoice_id = v_inv and sc.staff_id = v_a and sc.status = 'earned') = 2
      and (select sum(sc.commission_amount) from staff_commissions sc where sc.invoice_id = v_inv and sc.staff_id = v_b
             and sc.status = 'earned' and sc.invoice_paid_date = pg_temp.prev()) = 6,
    'fixture: two registrations dated last month: A holds 6.00 + 12.00 = 18.00 (two rows), B 6.00');

  -- The first payment 400 -> 233: 633 held, pool 18.99, 5.01 goes, all from last month.
  -- A: 5.01 x 18/24 = 3.7575 -> 3.76; B: the rest, 5.01 - 3.76 = 1.25 (5.01 x 6/24 = 1.2525).
  perform pg_temp.correct_to(v_inv, 233);
  select sum(sc.commission_amount) filter (where sc.staff_id = v_a and sc.status = 'earned'),
         sum(sc.commission_amount) filter (where sc.staff_id = v_b and sc.status = 'earned'),
         sum(sc.commission_amount) filter (where sc.staff_id = v_a and sc.status = 'reversed')
           - sum(sc.commission_amount) filter (where sc.staff_id = v_a and sc.status = 'earned'),
         sum(sc.commission_amount) filter (where sc.staff_id = v_b and sc.status = 'reversed')
           - sum(sc.commission_amount) filter (where sc.staff_id = v_b and sc.status = 'earned')
    into v_keep_a, v_keep_b, v_give_a, v_give_b
    from staff_commissions sc where sc.invoice_id = v_inv;
  perform pg_temp.check(v_sc, pg_temp.staff_live(v_inv) = 18.99, format('the pool follows the money: 18.99 on 633 held, got %s', pg_temp.staff_live(v_inv)));
  perform pg_temp.check(v_sc, v_give_a = 3.76 and v_give_b = 1.25 and v_keep_a = 14.24 and v_keep_b = 4.75,
    format('shared in proportion to what each held on that date: A gives back 3.76 (keeps 14.24), B 1.25 (keeps 4.75); got %s (%s) / %s (%s)',
      v_give_a, v_keep_a, v_give_b, v_keep_b));
  perform pg_temp.check(v_sc, v_give_a + v_give_b = 5.01 and v_give_a > v_give_b,
    format('the cents add up to exactly the 5.01 taken back, and the larger holder gives back more (%s + %s)', v_give_a, v_give_b));
  perform pg_temp.check(v_sc, (select count(*) from staff_commissions sc where sc.invoice_id = v_inv and sc.status = 'reversed') = 3
      and (select count(*) from staff_commissions sc where sc.invoice_id = v_inv and sc.status = 'earned' and sc.staff_id = v_a
             and sc.invoice_paid_date = pg_temp.prev() and sc.earning_basis = 'instalment') = 1
      and (select count(*) from staff_commissions sc where sc.invoice_id = v_inv and sc.status = 'earned' and sc.staff_id = v_b
             and sc.invoice_paid_date = pg_temp.prev() and sc.earning_basis = 'instalment') = 1,
    'all three rows are reversed; each holder keeps ONE row dated last month (A''s two rows became one)');
  perform pg_temp.check(v_sc, not exists (select 1 from staff_commissions sc where sc.invoice_id = v_inv
                                            and (sc.commission_amount < 0 or sc.invoice_paid_date >= pg_temp.cur_m())),
    'no negative rows, nothing dated this month');
  perform pg_temp.idempotent(v_sc, v_inv);
exception when others then
  perform pg_temp.errored(v_sc, sqlerrm);
end $$;

-- ═════ 3. Affiliate: part paid last month, settled this month, then cancelled (6) ═════
-- Twice: in the staffed store, and in a store with no commission staff, where
-- the invoice's only part-payment rows are affiliate rows that net to zero
-- after settlement (the early-return case).
do $$
declare v_store text; v_sc text; v_ref uuid; v_ref2 uuid; v_buyer uuid; v_inv uuid; v_staff numeric;
begin
  foreach v_store in array array['st','st0'] loop
    v_sc := case v_store when 'st' then '3 settled+cancel' else '3 settled+cancel, no staff' end;
    v_staff := case v_store when 'st' then 12 else 0 end;
    begin
      v_ref := pg_temp.referrers('S3 ' || v_store); v_ref2 := pg_temp.tier2_of(v_ref);
      v_buyer := pg_temp.customer('PPT S3 buyer ' || v_store, v_ref);
      v_inv := pg_temp.product_invoice(v_buyer, pg_temp.fx('p1000'), 1, pg_temp.fx(v_store));
      perform pg_temp.pay_last_month(v_inv, 400);
      perform pg_temp.check(v_sc, pg_temp.balance(v_ref, pg_temp.prev_m()) = 60 and pg_temp.balance(v_ref2, pg_temp.prev_m()) = 21
          and pg_temp.staff_live(v_inv) = v_staff,
        format('fixture: last month holds the part payment''s 60.00 tier 1 / 21.00 tier 2, staff %s', v_staff));
      perform pg_temp.pay(v_inv, 600);
      perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'paid' and pg_temp.aff(v_inv) = 202.50
          and pg_temp.aff_layer(v_inv, 'instalment') = 0
          and exists (select 1 from commissions c where c.invoice_id = v_inv and c.earning_basis = 'instalment' and c.commission_amount = -60
                        and c.status = 'earned' and c.invoice_paid_date = sg_today())
          and exists (select 1 from commissions c where c.invoice_id = v_inv and c.earning_basis = 'settlement' and c.commission_amount = 150
                        and c.status = 'earned'),
        'fixture: settled this month: close row -60.00 today + settlement 150.00; total 202.50; the part-payment layer nets to 0');
      if date_trunc('month', (now() at time zone 'UTC')) = date_trunc('month', sg_today()::timestamp) then
        perform pg_temp.check(v_sc, pg_temp.balance(v_ref, pg_temp.prev_m()) = 60 and pg_temp.balance(v_ref, pg_temp.cur_m()) = 90,
          'fixture: before the cancel, last month 60.00 and this month 90.00');
      else
        raise notice 'SKIP  [%] month split fixture check (settlement rows use the UTC date; run outside 00:00-07:59 SG on the 1st)', v_sc;
      end if;

      perform cancel_invoice_recorded(v_inv, 'Customer withdrew', gen_random_uuid());
      perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'cancelled', 'fixture: cancelled');
      perform pg_temp.check(v_sc, pg_temp.balance(v_ref, pg_temp.prev_m()) = 0 and pg_temp.balance(v_ref2, pg_temp.prev_m()) = 0,
        format('last month squares to 0 for both tiers (pre-fix +60.00 / +21.00), got %s / %s',
          pg_temp.balance(v_ref, pg_temp.prev_m()), pg_temp.balance(v_ref2, pg_temp.prev_m())));
      perform pg_temp.check(v_sc, pg_temp.balance(v_ref, pg_temp.cur_m()) = 0 and pg_temp.balance(v_ref2, pg_temp.cur_m()) = 0,
        format('this month squares to 0 for both tiers (pre-fix -60.00 / -21.00), got %s / %s',
          pg_temp.balance(v_ref, pg_temp.cur_m()), pg_temp.balance(v_ref2, pg_temp.cur_m())));
      perform pg_temp.check(v_sc, pg_temp.aff(v_inv) = 0 and pg_temp.staff_live(v_inv) = 0,
        format('the cancelled invoice holds 0 affiliate and 0 staff, got %s / %s', pg_temp.aff(v_inv), pg_temp.staff_live(v_inv)));
      perform pg_temp.check(v_sc, not exists (select 1 from commissions c where c.invoice_id = v_inv and c.status in ('earned','paid')),
        'nothing was paid out, so every affiliate row is reversed where it stands; no new squaring row');
      perform pg_temp.idempotent(v_sc, v_inv);
    exception when others then
      perform pg_temp.errored(v_sc, sqlerrm);
    end;
  end loop;
end $$;

-- ═════ 4. Affiliate: 40 of last month's 60 paid out, then the part-paid invoice is cancelled (5b, 6) ═════
do $$
declare v_sc text := '4 paid-out+cancel'; v_ref uuid; v_ref2 uuid; v_buyer uuid; v_inv uuid; v_row uuid; v_payout jsonb; v_msg text;
begin
  v_ref := pg_temp.referrers('S4'); v_ref2 := pg_temp.tier2_of(v_ref);
  v_buyer := pg_temp.customer('PPT S4 buyer', v_ref);
  v_inv := pg_temp.product_invoice(v_buyer, pg_temp.fx('p1000'));
  perform pg_temp.pay_last_month(v_inv, 400);
  select c.id into v_row from commissions c where c.invoice_id = v_inv and c.referrer_customer_id = v_ref
     and c.commission_amount = 60 and c.invoice_paid_date = pg_temp.prev();
  perform pg_temp.check(v_sc, v_row is not null, 'fixture: a 60.00 tier-1 part-payment row dated last month');
  v_payout := affiliate_payout_save(null, null, v_ref, pg_temp.prev_m(), 40, pg_temp.fx('m'), sg_today(),
                'PPT partial', null, null, gen_random_uuid());
  perform pg_temp.check(v_sc, (select coalesce(sum(a.amount),0) from commission_payout_allocations a where a.commission_id = v_row) = 40
      and commission_unpaid_amount(v_row) = 20 and pg_temp.balance(v_ref, pg_temp.prev_m()) = 20,
    format('fixture: 40 of the 60 paid out (partial allocation); 20 unpaid; last month balance %s', pg_temp.balance(v_ref, pg_temp.prev_m())));

  perform cancel_invoice_recorded(v_inv, 'Customer withdrew', gen_random_uuid());
  perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'cancelled', 'fixture: cancelled while part-paid');
  perform pg_temp.check(v_sc, pg_temp.balance(v_ref, pg_temp.prev_m()) = 0,
    format('last month''s balance is 0 (pre-fix 20.00 still payable), got %s', pg_temp.balance(v_ref, pg_temp.prev_m())));
  perform pg_temp.check(v_sc, exists (select 1 from commissions c where c.invoice_id = v_inv and c.adjusts_commission_id = v_row
                                        and c.commission_amount = -20 and c.invoice_paid_date = pg_temp.prev() and c.status = 'earned'),
    'the unpaid 20.00 is taken back by a linked negative row dated last month (adjusts_commission_id = the 60.00 row)');
  perform pg_temp.check(v_sc, (select count(*) from commissions c where c.invoice_id = v_inv and c.referrer_customer_id = v_ref
                                 and c.status in ('earned','paid') and c.invoice_paid_date >= pg_temp.cur_m()) = 1
      and (select coalesce(sum(c.commission_amount),0) from commissions c where c.invoice_id = v_inv and c.referrer_customer_id = v_ref
             and c.status in ('earned','paid') and c.invoice_paid_date = sg_today() and c.adjusts_commission_id is null) = -40,
    format('only the paid-out 40.00 is taken back as one new row dated today; this month balance %s', pg_temp.balance(v_ref, pg_temp.cur_m())));
  perform pg_temp.check(v_sc, pg_temp.balance(v_ref2, pg_temp.prev_m()) = 0 and pg_temp.balance(v_ref2, pg_temp.cur_m()) = 0,
    'tier 2 (nothing paid out) squares to 0 in both months');
  perform pg_temp.check(v_sc, pg_temp.aff(v_inv) = 0 and pg_temp.aff_of(v_inv, v_ref) = 0,
    format('the invoice''s affiliate total is 0 (60 - 20 - 40), got %s', pg_temp.aff(v_inv)));
  -- No further payout for last month.
  begin
    perform affiliate_payout_save(null, null, v_ref, pg_temp.prev_m(), 20, pg_temp.fx('m'), sg_today(), 'PPT more', null, null, gen_random_uuid());
    v_msg := 'accepted';
  exception when others then
    v_msg := sqlerrm;
  end;
  perform pg_temp.check(v_sc, v_msg like 'Amount exceeds the remaining payable balance%',
    format('a further 20.00 payout for last month is refused (got: %s)', v_msg));
  perform pg_temp.idempotent(v_sc, v_inv);
exception when others then
  perform pg_temp.errored(v_sc, sqlerrm);
end $$;

-- 4b. A row larger than what must go: corrected down a little.
do $$
declare v_sc text := '4b corrected a little'; v_ref uuid; v_ref2 uuid; v_buyer uuid; v_inv uuid; v_r1 uuid; v_r2 uuid; v_fp text; v_dry jsonb;
begin
  v_ref := pg_temp.referrers('S4b'); v_ref2 := pg_temp.tier2_of(v_ref);
  v_buyer := pg_temp.customer('PPT S4b buyer', v_ref);
  v_inv := pg_temp.product_invoice(v_buyer, pg_temp.fx('p1000'));
  perform pg_temp.pay_last_month(v_inv, 400);
  select c.id into v_r1 from commissions c where c.invoice_id = v_inv and c.referrer_customer_id = v_ref and c.commission_amount = 60;
  select c.id into v_r2 from commissions c where c.invoice_id = v_inv and c.referrer_customer_id = v_ref2 and c.commission_amount = 21;
  perform pg_temp.check(v_sc, v_r1 is not null and v_r2 is not null, 'fixture: 60.00 / 21.00 part-payment rows dated last month');

  -- Dry run of the same take-back (tier 1 own rate lowered to 13.5%, the money
  -- unchanged: 54.00 / 18.90 on the 400 held): reported on the row's own date.
  v_fp := pg_temp.fingerprint(v_inv);
  update app_settings set commission_tier1_own_rate = 13.5 where id = true;
  select coalesce(jsonb_agg(jsonb_build_object('tier', d.o_tier, 'amt', d.o_amount, 'date', d.o_date) order by d.o_tier), '[]'::jsonb)
    into v_dry from sync_instalment_commissions(v_inv, 'dry run', null, true) d where d.o_ledger = 'affiliate';
  update app_settings set commission_tier1_own_rate = 15 where id = true;
  perform pg_temp.check(v_sc, v_dry = jsonb_build_array(
        jsonb_build_object('tier', 'tier1', 'amt', -6.00, 'date', pg_temp.prev()),
        jsonb_build_object('tier', 'tier2', 'amt', -2.10, 'date', pg_temp.prev()))
      and pg_temp.fingerprint(v_inv) = v_fp,
    format('dry run: -6.00 / -2.10 reported dated the rows'' own date, last month (%s), nothing written; got %s', pg_temp.prev(), v_dry));

  perform pg_temp.correct_to(v_inv, 360);   -- 60.00 -> 54.00 and 21.00 -> 18.90
  perform pg_temp.check(v_sc, pg_temp.aff(v_inv) = 72.90, format('the layer follows the money: 54.00 + 18.90 = 72.90, got %s', pg_temp.aff(v_inv)));
  perform pg_temp.check(v_sc,
    exists (select 1 from commissions c where c.invoice_id = v_inv and c.adjusts_commission_id = v_r1 and c.commission_amount = -6
              and c.invoice_paid_date = pg_temp.prev() and c.status = 'earned')
    and exists (select 1 from commissions c where c.invoice_id = v_inv and c.adjusts_commission_id = v_r2 and c.commission_amount = -2.10
              and c.invoice_paid_date = pg_temp.prev() and c.status = 'earned'),
    'each larger row gets a linked negative (-6.00, -2.10) in its own month, last month');
  perform pg_temp.check(v_sc, (select c.status::text from commissions c where c.id = v_r1) = 'earned'
      and (select c.status::text from commissions c where c.id = v_r2) = 'earned', 'the original rows stand (not reversed)');
  perform pg_temp.check(v_sc, not exists (select 1 from commissions c where c.invoice_id = v_inv and c.status in ('earned','paid')
                                            and c.invoice_paid_date >= pg_temp.cur_m()),
    'no affiliate row is dated this month');
  perform pg_temp.check(v_sc, pg_temp.balance(v_ref, pg_temp.prev_m()) = 54 and pg_temp.balance(v_ref, pg_temp.cur_m()) = 0,
    format('last month holds 54.00, this month 0; got %s / %s', pg_temp.balance(v_ref, pg_temp.prev_m()), pg_temp.balance(v_ref, pg_temp.cur_m())));
  perform pg_temp.check(v_sc, pg_temp.staff_live(v_inv) = 10.80
      and not exists (select 1 from staff_commissions sc where sc.invoice_id = v_inv and sc.status in ('earned','paid')
                        and (sc.commission_amount < 0 or sc.invoice_paid_date >= pg_temp.cur_m())),
    format('staff 12.00 -> 10.80, all of it still last month, no negative rows; got %s', pg_temp.staff_live(v_inv)));
  perform pg_temp.idempotent(v_sc, v_inv);
exception when others then
  perform pg_temp.errored(v_sc, sqlerrm);
end $$;

-- ═════ 5. The instalment affiliate target honours line refunds (5) ═════
do $$
declare v_sc text := '5 line refund'; v_ref uuid; v_ref2 uuid; v_buyer uuid; v_inv uuid; v_item uuid; v_pay uuid; v_move uuid;
  v_kept numeric; v_kept1 numeric; v_kept2 numeric; v_target numeric;
begin
  v_ref := pg_temp.referrers('S5'); v_ref2 := pg_temp.tier2_of(v_ref);
  v_buyer := pg_temp.customer('PPT S5 buyer', v_ref);
  v_inv := pg_temp.product_invoice(v_buyer, pg_temp.fx('p500'), 2);     -- one line, 2 x 500
  select x.id into v_item from invoice_items x where x.invoice_id = v_inv;
  perform pg_temp.pay(v_inv, 1000);
  perform pg_temp.check(v_sc, pg_temp.aff(v_inv) = 202.50, format('fixture: settled at 150.00 + 52.50, got %s', pg_temp.aff(v_inv)));

  -- A 200 refund on the line (one unit not returned), from the original payment.
  v_pay := pg_temp.current_payment(v_inv);
  select sm.id into v_move from stock_movements sm where sm.invoice_id = v_inv and sm.movement_type::text = 'store_sale' limit 1;
  perform refund_invoice_recorded(v_inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', v_item, 'amount', 200)),
    jsonb_build_array(jsonb_build_object('payment_id', v_pay, 'amount', 200)),
    jsonb_build_array(jsonb_build_object('movement_id', v_move, 'sellable_quantity', 0, 'damaged_quantity', 0, 'not_returned_quantity', 1)),
    'Price adjustment on one unit', gen_random_uuid());
  v_kept := pg_temp.aff(v_inv); v_kept1 := pg_temp.aff_of(v_inv, v_ref); v_kept2 := pg_temp.aff_of(v_inv, v_ref2);
  perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'paid' and v_kept = 162
      and invoice_charge_total(v_inv) = 800,
    format('fixture: after the 200 line refund settlement keeps 800/1000 of the line: 120.00 + 42.00 = 162.00, got %s', v_kept));

  -- The payment is corrected down: 400 of the 800 now due is held; being paid again.
  perform pg_temp.correct_to(v_inv, 600);
  perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'partially_paid'
      and invoice_net_received(v_inv) = 400 and pg_temp.aff_layer(v_inv, 'settlement') = 0,
    'fixture: 600 - 200 refunded = 400 of 800 held; part-paid; settlement reversed');
  select coalesce(sum(t.amount),0) into v_target from invoice_instalment_commission_targets(v_inv) t where t.ledger = 'affiliate';
  perform pg_temp.check(v_sc, v_target = round(v_kept * 400 / 800, 2),
    format('target: kept settlement x share received = 162.00 x 400/800 = %s (pre-fix 101.25 on the unrefunded line), got %s',
      round(v_kept * 400 / 800, 2), v_target));
  perform pg_temp.check(v_sc, pg_temp.aff(v_inv) = round(v_kept * 400 / 800, 2)
      and pg_temp.aff_of(v_inv, v_ref) = round(v_kept1 * 400 / 800, 2) and pg_temp.aff_of(v_inv, v_ref2) = round(v_kept2 * 400 / 800, 2),
    format('the instalment layer holds it: %s = %s tier 1 + %s tier 2 (pre-fix 75.00 + 26.25)',
      pg_temp.aff(v_inv), pg_temp.aff_of(v_inv, v_ref), pg_temp.aff_of(v_inv, v_ref2)));
  perform pg_temp.check(v_sc, pg_temp.staff_live(v_inv) = 12, format('staff holds 3%% of the 400 held: 12.00, got %s', pg_temp.staff_live(v_inv)));
  perform pg_temp.idempotent(v_sc, v_inv);

  -- Paid in full again (8c): settlement honours the refund, the layer closes.
  perform pg_temp.pay(v_inv, 400);
  perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'paid'
      and pg_temp.aff(v_inv) = v_kept and pg_temp.aff_layer(v_inv, 'instalment') = 0,
    format('paid in full again: exactly the kept settlement %s, part-payment layer closed (pre-fix 202.50), got %s', v_kept, pg_temp.aff(v_inv)));
  perform pg_temp.check(v_sc, pg_temp.staff_live(v_inv) = 24, format('staff: 3%% of the 800 kept = 24.00, got %s', pg_temp.staff_live(v_inv)));
  perform pg_temp.idempotent(v_sc, v_inv);
exception when others then
  perform pg_temp.errored(v_sc, sqlerrm);
end $$;

-- ═════ 6. A FIRST settlement after a line refund recorded while part-paid (8c) ═════
-- Two 1,000 lines, 15% tier 1 / 35% tier 2: 150.00 + 52.50 each, 405.00 in
-- all. 200 of line 1 is refunded while 1,200 of 2,000 is held; the last 800
-- then settles it. Line 1 keeps 800/1000 of its commission: 120.00 + 42.00,
-- line 2 150.00 + 52.50, so 364.50. Staff: 3% of the 1,800 kept = 54.00.
do $$
declare v_sc text := '6 refund while part-paid'; v_ref uuid; v_ref2 uuid; v_buyer uuid; v_inv uuid; v_item1 uuid; v_pay uuid;
  v_target numeric; v_fp text; v_aff numeric; v_staff numeric;
begin
  v_ref := pg_temp.referrers('S6'); v_ref2 := pg_temp.tier2_of(v_ref);
  v_buyer := pg_temp.customer('PPT S6 buyer', v_ref);
  v_inv := create_invoice_with_details(pg_temp.fx('st'), v_buyer, jsonb_build_array(
             jsonb_build_object('kind','product','product_id',pg_temp.fx('p1000'),'quantity',1),
             jsonb_build_object('kind','product','product_id',pg_temp.fx('p1000b'),'quantity',1)),
           jsonb_build_object('business_date', sg_today()::text));
  select x.id into v_item1 from invoice_items x where x.invoice_id = v_inv and x.product_id = pg_temp.fx('p1000');
  perform pg_temp.pay(v_inv, 1200);
  perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'partially_paid'
      and pg_temp.aff(v_inv) = 243 and pg_temp.staff_live(v_inv) = 36 and pg_temp.aff_layer(v_inv, 'settlement') = 0,
    format('fixture: 1,200 of 2,000 held: 405.00 x 0.6 = 243.00 affiliate, 36.00 staff, all part-payment; got %s / %s',
      pg_temp.aff(v_inv), pg_temp.staff_live(v_inv)));

  -- 200 refunded on line 1, from the 1,200 payment, while part-paid. A part-paid
  -- invoice has deducted no stock yet (that happens at settlement), so there is
  -- no stock disposition to record.
  v_pay := pg_temp.current_payment(v_inv);
  perform pg_temp.check(v_sc, not exists (select 1 from stock_movements sm where sm.invoice_id = v_inv),
    'fixture: no stock deducted while part-paid');
  perform refund_invoice_recorded(v_inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', v_item1, 'amount', 200)),
    jsonb_build_array(jsonb_build_object('payment_id', v_pay, 'amount', 200)),
    '[]'::jsonb, 'Price adjustment on line 1', gen_random_uuid());
  select coalesce(sum(t.amount),0) into v_target from invoice_instalment_commission_targets(v_inv) t where t.ledger = 'affiliate';
  perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'partially_paid'
      and invoice_net_received(v_inv) = 1000 and invoice_charge_total(v_inv) = 1800
      and pg_temp.aff_layer(v_inv, 'settlement') = 0 and pg_temp.staff_live(v_inv) = 30
      and pg_temp.aff(v_inv) = v_target,
    format('fixture: refunded while part-paid: 1,000 of 1,800 held, never settled; staff 30.00, affiliate layer %s = its target %s',
      pg_temp.aff(v_inv), v_target));

  -- The rest arrives through Record Payment: the first settlement.
  perform pg_temp.pay(v_inv, 800);
  perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'paid', 'fixture: paid in full');
  perform pg_temp.check(v_sc, pg_temp.aff(v_inv) = 364.50 and pg_temp.aff_of(v_inv, v_ref) = 270 and pg_temp.aff_of(v_inv, v_ref2) = 94.50,
    format('settled: the line refund counts: 270.00 + 94.50 = 364.50 (pre-fix 405.00), got %s + %s = %s',
      pg_temp.aff_of(v_inv, v_ref), pg_temp.aff_of(v_inv, v_ref2), pg_temp.aff(v_inv)));
  perform pg_temp.check(v_sc, pg_temp.aff_layer(v_inv, 'instalment') = 0 and pg_temp.aff_layer(v_inv, 'settlement') = 364.50,
    format('the part-payment layer closes to 0; settlement holds %s', pg_temp.aff_layer(v_inv, 'settlement')));
  perform pg_temp.check(v_sc, pg_temp.staff_live(v_inv) = 54,
    format('staff: the pool on the money kept, 3%% of 1,800 = 54.00, got %s', pg_temp.staff_live(v_inv)));

  -- Control: an explicit reconcile now must find nothing to change. (It
  -- reissues the unpaid settlement rows, as it does on any settled invoice, so
  -- what everyone holds is compared, not row ids.)
  v_fp := pg_temp.holdings(v_inv); v_aff := pg_temp.aff(v_inv); v_staff := pg_temp.staff_live(v_inv);
  perform reconcile_invoice_commissions(v_inv, 'Control: explicit reconcile');
  perform pg_temp.check(v_sc, pg_temp.holdings(v_inv) = v_fp and pg_temp.aff(v_inv) = v_aff and pg_temp.staff_live(v_inv) = v_staff
      and pg_temp.aff_layer(v_inv, 'instalment') = 0,
    format('control: an explicit reconcile afterwards changes no amount for anyone, on any layer, line or date (affiliate %s -> %s, staff %s -> %s)',
      v_aff, pg_temp.aff(v_inv), v_staff, pg_temp.staff_live(v_inv)));
  perform pg_temp.idempotent(v_sc, v_inv);
exception when others then
  perform pg_temp.errored(v_sc, sqlerrm);
end $$;

-- ═════ 7. Affiliate: part paid and settled last month, 30 paid out, cancelled this month (6) ═════
-- Tier 1 15% on 1,000: the 400 part payment earns 60.00 / 21.00 on the 15th of
-- last month; settlement on the 20th of last month writes the close rows
-- -60.00 / -21.00 and 150.00 / 52.50. 30.00 is paid out for last month (it
-- lands on the 60.00 row). This month the invoice is cancelled.
do $$
declare v_sc text := '7 settled last month, paid out, cancelled'; v_settled date := pg_temp.prev() + 5;
  v_ref uuid; v_ref2 uuid; v_buyer uuid; v_inv uuid; v_row uuid; v_close uuid; v_msg_now text; v_msg_last text; v_owed numeric;
begin
  v_ref := pg_temp.referrers('S7'); v_ref2 := pg_temp.tier2_of(v_ref);
  v_buyer := pg_temp.customer('PPT S7 buyer', v_ref);
  v_inv := pg_temp.product_invoice(v_buyer, pg_temp.fx('p1000'));
  perform pg_temp.pay_last_month(v_inv, 400);
  perform pg_temp.pay(v_inv, 600);
  perform pg_temp.as_if_settled_on(v_inv, v_settled);
  select c.id into v_row from commissions c where c.invoice_id = v_inv and c.referrer_customer_id = v_ref
     and c.earning_basis = 'instalment' and c.commission_amount = 60 and c.invoice_paid_date = pg_temp.prev();
  select c.id into v_close from commissions c where c.invoice_id = v_inv and c.referrer_customer_id = v_ref
     and c.earning_basis = 'instalment' and c.commission_amount = -60 and c.invoice_paid_date = v_settled;
  perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'paid'
      and v_row is not null and v_close is not null and pg_temp.aff_layer(v_inv, 'settlement') = 202.50
      and pg_temp.aff_layer(v_inv, 'instalment') = 0
      and pg_temp.balance(v_ref, pg_temp.prev_m()) = 150 and pg_temp.balance(v_ref2, pg_temp.prev_m()) = 52.50
      and not exists (select 1 from commissions c where c.invoice_id = v_inv and c.invoice_paid_date >= pg_temp.cur_m()),
    format('fixture: part paid on %s (+60.00) and settled on %s (close -60.00, settlement 150.00): last month holds 150.00 / 52.50, nothing this month',
      pg_temp.prev(), v_settled));
  perform affiliate_payout_save(null, null, v_ref, pg_temp.prev_m(), 30, pg_temp.fx('m'), sg_today(),
            'PPT S7 partial', null, null, gen_random_uuid());
  perform pg_temp.check(v_sc, (select coalesce(sum(a.amount),0) from commission_payout_allocations a where a.commission_id = v_row) = 30
      and (select coalesce(sum(a.amount),0) from commission_payout_allocations a join commissions c on c.id = a.commission_id
            where c.invoice_id = v_inv) = 30
      and pg_temp.balance(v_ref, pg_temp.prev_m()) = 120,
    format('fixture: a 30.00 payout for last month is allocated to the 60.00 part-payment row; last month %s still payable',
      pg_temp.balance(v_ref, pg_temp.prev_m())));

  perform cancel_invoice_recorded(v_inv, 'Customer withdrew', gen_random_uuid());
  perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'cancelled', 'fixture: cancelled this month');
  perform pg_temp.check(v_sc, not exists (select 1 from commissions c where c.invoice_id = v_inv
                                            and c.invoice_paid_date >= pg_temp.cur_m() and c.commission_amount > 0),
    'no commission row of any status dated this month is positive (pre-fix: a +30.00 squaring row today)');
  perform pg_temp.check(v_sc, pg_temp.balance(v_ref, pg_temp.prev_m()) = 0,
    format('last month''s balance is 0 (pre-fix -60.00: the close row stood), got %s', pg_temp.balance(v_ref, pg_temp.prev_m())));
  perform pg_temp.check(v_sc, pg_temp.balance(v_ref, pg_temp.cur_m()) = -30,
    format('this month''s balance is exactly -30.00, what was paid out (pre-fix +30.00 payable), got %s', pg_temp.balance(v_ref, pg_temp.cur_m())));
  perform pg_temp.check(v_sc, (select count(*) from commissions c where c.invoice_id = v_inv and c.invoice_paid_date >= pg_temp.cur_m()) = 1
      and exists (select 1 from commissions c where c.invoice_id = v_inv and c.referrer_customer_id = v_ref
                    and c.invoice_paid_date = sg_today() and c.commission_amount = -30 and c.status = 'earned'
                    and c.adjusts_commission_id is null and c.reversal_reason like 'Part-payment commission squared%'),
    'the only row dated this month is one -30.00 ''Part-payment commission squared'' row (the paid-out 30.00 taken back today)');
  perform pg_temp.check(v_sc, (select c.status::text from commissions c where c.id = v_close) = 'earned'
      and exists (select 1 from commissions c where c.invoice_id = v_inv and c.adjusts_commission_id = v_close
                    and c.commission_amount = 60 and c.invoice_paid_date = v_settled and c.status = 'earned')
      and exists (select 1 from commissions c where c.invoice_id = v_inv and c.adjusts_commission_id = v_row
                    and c.commission_amount = -30 and c.invoice_paid_date = pg_temp.prev() and c.status = 'earned'),
    'last month squares in place: the close row (its month had a payout) is cancelled by a linked +60.00 on its own date, and the unpaid 30.00 of the 60.00 row goes by a linked -30.00 on its date');
  perform pg_temp.check(v_sc, pg_temp.balance(v_ref2, pg_temp.prev_m()) = 0 and pg_temp.balance(v_ref2, pg_temp.cur_m()) = 0,
    format('tier 2 (nothing paid out) squares to 0 in both months, got %s / %s',
      pg_temp.balance(v_ref2, pg_temp.prev_m()), pg_temp.balance(v_ref2, pg_temp.cur_m())));
  select coalesce(sum(b.balance), 0) into v_owed from affiliate_month_balances() b where b.referrer = v_ref;
  perform pg_temp.check(v_sc, pg_temp.aff(v_inv) = 0 and pg_temp.aff_of(v_inv, v_ref) = 0 and v_owed = -30,
    format('the cancelled invoice''s commission (both layers, both tiers) nets to 0 and the referrer owes exactly the 30.00 paid out: all months %s', v_owed));
  v_msg_now := pg_temp.payout_attempt(v_ref, pg_temp.cur_m(), 30);
  v_msg_last := pg_temp.payout_attempt(v_ref, pg_temp.prev_m(), 0.01);
  perform pg_temp.check(v_sc, v_msg_now like 'Amount exceeds the remaining payable balance%'
      and v_msg_last like 'Amount exceeds the remaining payable balance%',
    format('no further payout: 30.00 for this month (pre-fix accepted) -> %s; 0.01 for last month -> %s', v_msg_now, v_msg_last));
  perform pg_temp.check(v_sc, not exists (select 1 from audit_logs a where a.record_id = v_inv and a.action = 'instalment_commission_review_required'),
    'no instalment_commission_review_required audit (nothing was left over)');
  perform pg_temp.idempotent(v_sc, v_inv);
  perform pg_temp.dry_run_quiet(v_sc, v_inv);
exception when others then
  perform pg_temp.errored(v_sc, sqlerrm);
end $$;

-- 7b. Part paid two months ago (never paid out), settled last month, last
-- month paid out in full, cancelled this month.
do $$
declare v_sc text := '7b settlement month paid out'; v_settled date := pg_temp.prev() + 5;
  v_ref uuid; v_ref2 uuid; v_buyer uuid; v_inv uuid; v_close uuid; v_paid numeric; v_m date; v_msg text; v_msgs text := '';
begin
  v_ref := pg_temp.referrers('S7b'); v_ref2 := pg_temp.tier2_of(v_ref);
  v_buyer := pg_temp.customer('PPT S7b buyer', v_ref);
  v_inv := pg_temp.product_invoice(v_buyer, pg_temp.fx('p1000'));
  perform pg_temp.pay_registered_on(v_inv, 400, pg_temp.prev2());
  perform pg_temp.pay(v_inv, 600);
  perform pg_temp.as_if_settled_on(v_inv, v_settled);
  select c.id into v_close from commissions c where c.invoice_id = v_inv and c.referrer_customer_id = v_ref
     and c.earning_basis = 'instalment' and c.commission_amount = -60 and c.invoice_paid_date = v_settled;
  perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'paid' and v_close is not null
      and pg_temp.balance(v_ref, pg_temp.prev2_m()) = 60 and pg_temp.balance(v_ref, pg_temp.prev_m()) = 90
      and pg_temp.balance(v_ref2, pg_temp.prev2_m()) = 21 and pg_temp.balance(v_ref2, pg_temp.prev_m()) = 31.50
      and not exists (select 1 from commissions c where c.invoice_id = v_inv and c.invoice_paid_date >= pg_temp.cur_m()),
    format('fixture: +60.00 on %s, settled on %s (close -60.00, settlement 150.00): two months ago 60.00, last month 90.00; tier 2 21.00 / 31.50',
      pg_temp.prev2(), v_settled));
  v_paid := pg_temp.balance(v_ref, pg_temp.prev_m());
  perform affiliate_payout_save(null, null, v_ref, pg_temp.prev_m(), v_paid, pg_temp.fx('m'), sg_today(),
            'PPT S7b last month in full', null, null, gen_random_uuid());
  perform pg_temp.check(v_sc, v_paid = 90 and pg_temp.balance(v_ref, pg_temp.prev_m()) = 0
      and (select coalesce(sum(a.amount),0) from commission_payout_allocations a join commissions c on c.id = a.commission_id
            where c.invoice_id = v_inv and c.earning_basis = 'settlement') = 90,
    format('fixture: last month paid out in full (%s, allocated to the settlement row); two months ago still unpaid', v_paid));

  perform cancel_invoice_recorded(v_inv, 'Customer withdrew', gen_random_uuid());
  perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'cancelled', 'fixture: cancelled this month');
  perform pg_temp.check(v_sc, pg_temp.balance(v_ref, pg_temp.prev2_m()) = 0 and pg_temp.balance(v_ref, pg_temp.prev_m()) = -v_paid
      and pg_temp.balance(v_ref, pg_temp.cur_m()) = 0,
    format('two months ago 0, last month exactly -%s (what was paid), this month 0 (pre-fix 0 / -150.00 / +60.00), got %s / %s / %s',
      v_paid, pg_temp.balance(v_ref, pg_temp.prev2_m()), pg_temp.balance(v_ref, pg_temp.prev_m()), pg_temp.balance(v_ref, pg_temp.cur_m())));
  perform pg_temp.check(v_sc, not exists (select 1 from commissions c where c.invoice_id = v_inv
                                            and c.invoice_paid_date >= pg_temp.cur_m() and c.commission_amount > 0),
    'no commission row of any status dated this month is positive (pre-fix: a +60.00 squaring row today)');
  perform pg_temp.check(v_sc, (select c.status::text from commissions c where c.id = v_close) = 'earned'
      and exists (select 1 from commissions c where c.invoice_id = v_inv and c.adjusts_commission_id = v_close
                    and c.commission_amount = 60 and c.invoice_paid_date = v_settled and c.status = 'earned'),
    'the close row (its month was paid out) is cancelled by a linked +60.00 on its own date');
  perform pg_temp.check(v_sc, pg_temp.balance(v_ref2, pg_temp.prev2_m()) = 0 and pg_temp.balance(v_ref2, pg_temp.prev_m()) = 0
      and pg_temp.balance(v_ref2, pg_temp.cur_m()) = 0,
    'tier 2 (nothing paid out) is 0 in all three months');
  foreach v_m in array array[pg_temp.prev2_m(), pg_temp.prev_m(), pg_temp.cur_m()] loop
    v_msg := pg_temp.payout_attempt(v_ref, v_m, 0.01);
    if v_msg not like 'Amount exceeds the remaining payable balance%' then v_msgs := v_msgs || format('%s: %s; ', v_m, v_msg); end if;
    v_msg := pg_temp.payout_attempt(v_ref2, v_m, 0.01);
    if v_msg not like 'Amount exceeds the remaining payable balance%' then v_msgs := v_msgs || format('%s tier 2: %s; ', v_m, v_msg); end if;
  end loop;
  perform pg_temp.check(v_sc, v_msgs = ''
      and not exists (select 1 from affiliate_month_balances() b where b.referrer in (v_ref, v_ref2) and b.balance > 0),
    format('nothing is payable in any month, either tier: no positive balance, a 0.01 payout refused for each month (pre-fix: this month accepted) %s', v_msgs));
  perform pg_temp.check(v_sc, pg_temp.aff(v_inv) = 0, format('the cancelled invoice''s commission nets to 0, got %s', pg_temp.aff(v_inv)));
  perform pg_temp.check(v_sc, not exists (select 1 from audit_logs a where a.record_id = v_inv and a.action = 'instalment_commission_review_required'),
    'no instalment_commission_review_required audit');
  perform pg_temp.idempotent(v_sc, v_inv);
  perform pg_temp.dry_run_quiet(v_sc, v_inv);
exception when others then
  perform pg_temp.errored(v_sc, sqlerrm);
end $$;

-- 7c. As 7b, but last month counts as paid only because of a small payout on
-- ANOTHER invoice of the same referrer.
do $$
declare v_sc text := '7c another invoice''s payout'; v_settled date := pg_temp.prev() + 5;
  v_ref uuid; v_ref2 uuid; v_buyer uuid; v_other uuid; v_inv uuid; v_close uuid;
begin
  v_ref := pg_temp.referrers('S7c'); v_ref2 := pg_temp.tier2_of(v_ref);
  v_buyer := pg_temp.customer('PPT S7c buyer', v_ref);
  -- The other invoice: paid in full, settled on the 5th of last month (150.00 / 52.50).
  v_other := pg_temp.product_invoice(pg_temp.customer('PPT S7c other buyer', v_ref), pg_temp.fx('p1000'));
  perform pg_temp.pay(v_other, 1000);
  perform pg_temp.as_if_settled_on(v_other, pg_temp.prev() - 10);
  v_inv := pg_temp.product_invoice(v_buyer, pg_temp.fx('p1000'));
  perform pg_temp.pay_registered_on(v_inv, 400, pg_temp.prev2());
  perform pg_temp.pay(v_inv, 600);
  perform pg_temp.as_if_settled_on(v_inv, v_settled);
  select c.id into v_close from commissions c where c.invoice_id = v_inv and c.referrer_customer_id = v_ref
     and c.earning_basis = 'instalment' and c.commission_amount = -60 and c.invoice_paid_date = v_settled;
  perform affiliate_payout_save(null, null, v_ref, pg_temp.prev_m(), 10, pg_temp.fx('m'), sg_today(),
            'PPT S7c small payout', null, null, gen_random_uuid());
  perform pg_temp.check(v_sc, v_close is not null
      and pg_temp.balance(v_ref, pg_temp.prev2_m()) = 60 and pg_temp.balance(v_ref, pg_temp.prev_m()) = 230
      and (select coalesce(sum(a.amount),0) from commission_payout_allocations a join commissions c on c.id = a.commission_id
            where c.invoice_id = v_other) = 10
      and not exists (select 1 from commission_payout_allocations a join commissions c on c.id = a.commission_id where c.invoice_id = v_inv),
    format('fixture: the 10.00 payout for last month went to the other invoice''s row, none to this one; two months ago 60.00, last month %s',
      pg_temp.balance(v_ref, pg_temp.prev_m())));

  perform cancel_invoice_recorded(v_inv, 'Customer withdrew', gen_random_uuid());
  perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'cancelled', 'fixture: cancelled this month');
  perform pg_temp.check(v_sc, (select c.status::text from commissions c where c.id = v_close) = 'earned'
      and exists (select 1 from commissions c where c.invoice_id = v_inv and c.adjusts_commission_id = v_close
                    and c.commission_amount = 60 and c.invoice_paid_date = v_settled and c.status = 'earned'),
    'the other invoice''s payout blocks reversing the close row, and a linked +60.00 on its own date cancels it instead');
  perform pg_temp.check(v_sc, not exists (select 1 from commissions c where c.invoice_id = v_inv and c.status in ('earned','paid')
                                           group by c.referrer_customer_id, date_trunc('month', c.invoice_paid_date)
                                          having sum(c.commission_amount) <> 0),
    'the cancelled invoice nets to 0 in every month, both tiers (pre-fix: last month -60.00, this month +60.00)');
  perform pg_temp.check(v_sc, not exists (select 1 from commissions c where c.invoice_id = v_inv
                                            and c.invoice_paid_date >= pg_temp.cur_m() and c.commission_amount > 0),
    'no commission row of any status dated this month is positive');
  perform pg_temp.check(v_sc, pg_temp.balance(v_ref, pg_temp.prev2_m()) = 0 and pg_temp.balance(v_ref, pg_temp.prev_m()) = 140
      and pg_temp.balance(v_ref, pg_temp.cur_m()) = 0,
    format('the referrer: two months ago 0, last month exactly the other invoice''s 150.00 less the 10.00 paid = 140.00, this month 0 (pre-fix 0 / 80.00 / +60.00), got %s / %s / %s',
      pg_temp.balance(v_ref, pg_temp.prev2_m()), pg_temp.balance(v_ref, pg_temp.prev_m()), pg_temp.balance(v_ref, pg_temp.cur_m())));
  perform pg_temp.check(v_sc, pg_temp.balance(v_ref2, pg_temp.prev2_m()) = 0 and pg_temp.balance(v_ref2, pg_temp.prev_m()) = 52.50
      and pg_temp.balance(v_ref2, pg_temp.cur_m()) = 0,
    format('tier 2: 0 / 52.50 (the other invoice only) / 0, got %s / %s / %s',
      pg_temp.balance(v_ref2, pg_temp.prev2_m()), pg_temp.balance(v_ref2, pg_temp.prev_m()), pg_temp.balance(v_ref2, pg_temp.cur_m())));
  perform pg_temp.check(v_sc, not exists (select 1 from audit_logs a where a.record_id = v_inv and a.action = 'instalment_commission_review_required'),
    'no instalment_commission_review_required audit');
  perform pg_temp.idempotent(v_sc, v_inv);
  perform pg_temp.dry_run_quiet(v_sc, v_inv);
exception when others then
  perform pg_temp.errored(v_sc, sqlerrm);
end $$;

-- ═════ 9. A paid-out take-back while part-paid stands where it is; the cancel squares only the rest (a) ═════
-- Referrer R: invoice Y paid in full, settled on the 5th of last month (150.00
-- / 52.50). Invoice X: 400 of 1,000 part paid two months ago (+60.00 /
-- +21.00), and a 60.00 payout for that month is allocated to the +60.00 row.
-- Last month X's payment is corrected down to 200: the +60.00 row is fully
-- paid, so the 30.00 no longer earned is taken back by a new -30.00 row marked
-- 'Paid-out part-payment commission taken back' (the sync dates it today;
-- pg_temp.as_if_recorded_on moves it to the 15th of last month). 9: a 120.00
-- payout for last month nets it against Y (last month 0). 9b: no payout for
-- last month (120.00 payable). This month X is cancelled.
do $$
declare v_paid_m1 boolean; v_sc text; v_ref uuid; v_ref2 uuid; v_x uuid; v_y uuid; v_row uuid; v_tb uuid;
  v_moved int; v_m1 numeric; v_owed numeric; v_msg_last text; v_msg_now text;
begin
  foreach v_paid_m1 in array array[true, false] loop
    v_sc := case when v_paid_m1 then '9 paid-out take-back, last month paid' else '9b paid-out take-back, last month unpaid' end;
    begin
      v_ref := pg_temp.referrers(case when v_paid_m1 then 'S9' else 'S9b' end); v_ref2 := pg_temp.tier2_of(v_ref);
      v_y := pg_temp.product_invoice(pg_temp.customer('PPT S9 other buyer', v_ref), pg_temp.fx('p1000'));
      perform pg_temp.pay(v_y, 1000);
      perform pg_temp.as_if_settled_on(v_y, pg_temp.prev() - 10);
      v_x := pg_temp.product_invoice(pg_temp.customer('PPT S9 buyer', v_ref), pg_temp.fx('p1000'));
      perform pg_temp.pay_registered_on(v_x, 400, pg_temp.prev2());
      select c.id into v_row from commissions c where c.invoice_id = v_x and c.referrer_customer_id = v_ref
         and c.earning_basis = 'instalment' and c.commission_amount = 60 and c.invoice_paid_date = pg_temp.prev2();
      perform affiliate_payout_save(null, null, v_ref, pg_temp.prev2_m(), 60, pg_temp.fx('m'), sg_today(),
                'PPT S9 two months ago', null, null, gen_random_uuid());
      perform pg_temp.check(v_sc, v_row is not null
          and (select coalesce(sum(a.amount),0) from commission_payout_allocations a where a.commission_id = v_row) = 60
          and commission_unpaid_amount(v_row) = 0
          and pg_temp.balance(v_ref, pg_temp.prev2_m()) = 0 and pg_temp.balance(v_ref, pg_temp.prev_m()) = 150,
        format('fixture: X +60.00 on %s, paid out in full (60.00 allocated to it); Y 150.00 on %s; two months ago 0, last month %s',
          pg_temp.prev2(), pg_temp.prev() - 10, pg_temp.balance(v_ref, pg_temp.prev_m())));

      -- Last month: X's payment corrected down to 200 (60.00 -> 30.00, 21.00 -> 10.50).
      perform pg_temp.correct_to(v_x, 200);
      v_moved := pg_temp.as_if_recorded_on(v_x, pg_temp.prev());
      select c.id into v_tb from commissions c where c.invoice_id = v_x and c.referrer_customer_id = v_ref
         and c.status = 'earned' and c.commission_amount = -30 and c.invoice_paid_date = pg_temp.prev() and c.adjusts_commission_id is null;
      perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_x) = 'partially_paid'
          and v_moved = 1 and v_tb is not null and pg_temp.aff_of(v_x, v_ref) = 30 and pg_temp.aff_of(v_x, v_ref2) = 10.50
          and pg_temp.balance(v_ref, pg_temp.prev2_m()) = 0 and pg_temp.balance(v_ref, pg_temp.prev_m()) = 120,
        format('fixture: corrected to 200 last month: the fully paid +60.00 keeps standing and ONE new -30.00 row (dated last month) takes back the paid-out 30.00; X holds 30.00 / 10.50; last month 150.00 - 30.00 = %s',
          pg_temp.balance(v_ref, pg_temp.prev_m())));
      perform pg_temp.check(v_sc, (select c.reversal_reason from commissions c where c.id = v_tb) like 'Paid-out part-payment commission taken back%',
        format('the take-back of paid-out commission while part-paid is marked ''Paid-out part-payment commission taken back'' (pre-fix: unmarked), got %L',
          (select c.reversal_reason from commissions c where c.id = v_tb)));
      if v_paid_m1 then
        perform affiliate_payout_save(null, null, v_ref, pg_temp.prev_m(), 120, pg_temp.fx('m'), sg_today(),
                  'PPT S9 last month', null, null, gen_random_uuid());
        perform pg_temp.check(v_sc, pg_temp.balance(v_ref, pg_temp.prev_m()) = 0
            and (select coalesce(sum(a.amount),0) from commission_payout_allocations a join commissions c on c.id = a.commission_id
                  where c.invoice_id = v_y) = 120
            and not exists (select 1 from commission_payout_allocations a where a.commission_id = v_tb),
          'fixture: a 120.00 payout for last month (allocated to Y''s row) nets the -30.00 take-back: last month 0');
      end if;
      v_m1 := pg_temp.balance(v_ref, pg_temp.prev_m());

      perform cancel_invoice_recorded(v_x, 'Customer withdrew', gen_random_uuid());
      perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_x) = 'cancelled', 'fixture: X cancelled this month');
      perform pg_temp.check(v_sc, (select c.status::text from commissions c where c.id = v_tb) = 'earned'
          and not exists (select 1 from commissions c where c.adjusts_commission_id = v_tb),
        format('the -30.00 take-back stands where it is: not reversed, nothing linked to it (pre-fix: %s)',
          case when v_paid_m1 then 'a linked +30.00 last month, its month had a payout' else 'reversed' end));
      perform pg_temp.check(v_sc, pg_temp.balance(v_ref, pg_temp.prev2_m()) = 0 and pg_temp.balance(v_ref, pg_temp.prev_m()) = v_m1,
        format('two months ago 0, last month unchanged by the cancel at %s (pre-fix %s), got %s / %s', v_m1,
          case when v_paid_m1 then '+30.00 payable' else '150.00' end,
          pg_temp.balance(v_ref, pg_temp.prev2_m()), pg_temp.balance(v_ref, pg_temp.prev_m())));
      perform pg_temp.check(v_sc, pg_temp.balance(v_ref, pg_temp.cur_m()) = -30,
        format('this month exactly -30.00: the 60.00 paid out on X less the 30.00 already taken back (pre-fix -60.00), got %s',
          pg_temp.balance(v_ref, pg_temp.cur_m())));
      perform pg_temp.check(v_sc, (select count(*) from commissions c where c.invoice_id = v_x and c.invoice_paid_date >= pg_temp.cur_m()) = 1
          and exists (select 1 from commissions c where c.invoice_id = v_x and c.referrer_customer_id = v_ref
                        and c.invoice_paid_date = sg_today() and c.commission_amount = -30 and c.status = 'earned'
                        and c.adjusts_commission_id is null and c.reversal_reason like 'Part-payment commission squared%'),
        'the only row dated this month is one -30.00 ''Part-payment commission squared'' row (pre-fix -60.00)');
      perform pg_temp.check(v_sc, exists (select 1 from commissions c where c.invoice_id = v_x and c.adjusts_commission_id = v_row
                                            and c.status in ('earned','paid')) is false
          and (select c.status::text from commissions c where c.id = v_row) = 'paid',
        'the fully paid +60.00 row stands untouched (nothing of it is unpaid)');
      select coalesce(sum(b.balance), 0) into v_owed from affiliate_month_balances() b where b.referrer = v_ref;
      perform pg_temp.check(v_sc, pg_temp.aff_of(v_x, v_ref) = 0 and pg_temp.aff(v_x) = 0
          and v_owed = case when v_paid_m1 then -30 else 90 end,
        format('X nets to 0, both tiers; over all months R %s (Y''s 150.00 less the 60.00 paid out on X%s), got %s',
          case when v_paid_m1 then 'owes exactly -30.00' else 'is owed 90.00' end,
          case when v_paid_m1 then ' and the 120.00 paid for last month' else '' end, v_owed));
      perform pg_temp.check(v_sc, pg_temp.balance(v_ref2, pg_temp.prev2_m()) = 0 and pg_temp.balance(v_ref2, pg_temp.prev_m()) = 52.50
          and pg_temp.balance(v_ref2, pg_temp.cur_m()) = 0,
        format('tier 2 (nothing paid out): 0 / 52.50 (Y only) / 0, got %s / %s / %s',
          pg_temp.balance(v_ref2, pg_temp.prev2_m()), pg_temp.balance(v_ref2, pg_temp.prev_m()), pg_temp.balance(v_ref2, pg_temp.cur_m())));
      v_msg_last := pg_temp.payout_attempt(v_ref, pg_temp.prev_m(), v_m1 + 0.01);
      v_msg_now := pg_temp.payout_attempt(v_ref, pg_temp.cur_m(), 0.01);
      perform pg_temp.check(v_sc, v_msg_last like 'Amount exceeds the remaining payable balance%'
          and v_msg_now like 'Amount exceeds the remaining payable balance%',
        format('no further payout: %s for last month (pre-fix accepted) -> %s; 0.01 for this month -> %s', v_m1 + 0.01, v_msg_last, v_msg_now));
      perform pg_temp.check(v_sc, not exists (select 1 from audit_logs a where a.record_id = v_x and a.action = 'instalment_commission_review_required'),
        'no instalment_commission_review_required audit');
      perform pg_temp.idempotent(v_sc, v_x);
      perform pg_temp.dry_run_quiet(v_sc, v_x);
    exception when others then
      perform pg_temp.errored(v_sc, sqlerrm);
    end;
  end loop;
end $$;

-- ═════ 10. A payout lowered after the cancel: the difference is given back against the squaring row (b) ═════
-- +60.00 part payment last month, 40.00 of it paid out, cancelled: a linked
-- -20.00 last month and a -40.00 squaring row today. Then the payout is
-- corrected 40.00 -> 10.00 (affiliate_payout_save with its id and version),
-- which leaves 30.00 of the +60.00 row unpaid (last month +30.00 payable),
-- and the cancelled invoice is reconciled.
do $$
declare v_sc text := '10 payout lowered after the cancel'; v_ref uuid; v_ref2 uuid; v_inv uuid; v_row uuid; v_sq uuid; v_po jsonb;
  v_owed numeric; v_msg_last text; v_msg_now text;
begin
  v_ref := pg_temp.referrers('S10'); v_ref2 := pg_temp.tier2_of(v_ref);
  v_inv := pg_temp.product_invoice(pg_temp.customer('PPT S10 buyer', v_ref), pg_temp.fx('p1000'));
  perform pg_temp.pay_last_month(v_inv, 400);
  select c.id into v_row from commissions c where c.invoice_id = v_inv and c.referrer_customer_id = v_ref
     and c.commission_amount = 60 and c.invoice_paid_date = pg_temp.prev();
  v_po := affiliate_payout_save(null, null, v_ref, pg_temp.prev_m(), 40, pg_temp.fx('m'), sg_today(),
            'PPT S10 partial', null, null, gen_random_uuid());
  perform cancel_invoice_recorded(v_inv, 'Customer withdrew', gen_random_uuid());
  select c.id into v_sq from commissions c where c.invoice_id = v_inv and c.referrer_customer_id = v_ref
     and c.status = 'earned' and c.commission_amount = -40 and c.invoice_paid_date = sg_today()
     and c.reversal_reason like 'Part-payment commission squared%';
  perform pg_temp.check(v_sc, (select i.status::text from invoices i where i.id = v_inv) = 'cancelled' and v_row is not null and v_sq is not null
      and exists (select 1 from commissions c where c.adjusts_commission_id = v_row and c.commission_amount = -20
                    and c.invoice_paid_date = pg_temp.prev() and c.status = 'earned')
      and pg_temp.balance(v_ref, pg_temp.prev_m()) = 0 and pg_temp.balance(v_ref, pg_temp.cur_m()) = -40,
    'fixture: 40.00 of last month''s 60.00 paid out, cancelled: linked -20.00 last month, -40.00 squaring row today; last month 0, this month -40.00');

  v_po := affiliate_payout_save((v_po->>'id')::uuid, (v_po->>'version')::int, null, null, 10, pg_temp.fx('m'), sg_today(),
            'PPT S10 partial', null, 'Only 10.00 was transferred', gen_random_uuid());
  perform pg_temp.check(v_sc, (v_po->>'amount')::numeric = 10
      and (select coalesce(sum(a.amount),0) from commission_payout_allocations a where a.commission_id = v_row) = 10
      and commission_unpaid_amount(v_row) = 30 and pg_temp.balance(v_ref, pg_temp.prev_m()) = 30,
    format('fixture: the payout corrected 40.00 -> 10.00: 30.00 of the +60.00 row is unpaid again, last month %s payable before any sync',
      pg_temp.balance(v_ref, pg_temp.prev_m())));

  perform reconcile_invoice_commissions(v_inv, 'Payout corrected');
  perform pg_temp.check(v_sc, pg_temp.balance(v_ref, pg_temp.prev_m()) = 0
      and exists (select 1 from commissions c where c.adjusts_commission_id = v_row and c.commission_amount = -30
                    and c.invoice_paid_date = pg_temp.prev() and c.status = 'earned'),
    format('last month 0: the newly unpaid 30.00 is taken back there by a linked -30.00, got %s', pg_temp.balance(v_ref, pg_temp.prev_m())));
  perform pg_temp.check(v_sc, pg_temp.balance(v_ref, pg_temp.cur_m()) = -10
      and (select c.status::text from commissions c where c.id = v_sq) = 'earned'
      and (select count(*) from commissions c where c.adjusts_commission_id = v_sq and c.status in ('earned','paid')) = 1
      and exists (select 1 from commissions c where c.adjusts_commission_id = v_sq and c.commission_amount = 30
                    and c.invoice_paid_date = sg_today() and c.status = 'earned'),
    format('this month -10.00: a linked +30.00 against the squaring row, dated in its month (today), gives back what it took beyond the 10.00 paid out (pre-fix -40.00, nothing given back), got %s',
      pg_temp.balance(v_ref, pg_temp.cur_m())));
  select coalesce(sum(b.balance), 0) into v_owed from affiliate_month_balances() b where b.referrer = v_ref;
  perform pg_temp.check(v_sc, v_owed = -10 and pg_temp.aff_of(v_inv, v_ref) = 0 and pg_temp.aff(v_inv) = 0,
    format('R owes exactly the 10.00 paid out and the cancelled invoice nets to 0 (pre-fix: owes 40.00, invoice -30.00); owed %s, invoice %s',
      v_owed, pg_temp.aff(v_inv)));
  perform pg_temp.check(v_sc, not exists (select 1 from commissions c where c.invoice_id = v_inv and c.status in ('earned','paid')
                                           and c.commission_amount > 0 and c.adjusts_commission_id is null and c.invoice_paid_date >= pg_temp.cur_m()),
    'nothing positive stands on its own this month (the +30.00 is linked to the squaring row)');
  v_msg_last := pg_temp.payout_attempt(v_ref, pg_temp.prev_m(), 0.01);
  v_msg_now := pg_temp.payout_attempt(v_ref, pg_temp.cur_m(), 0.01);
  perform pg_temp.check(v_sc, v_msg_last like 'Amount exceeds the remaining payable balance%'
      and v_msg_now like 'Amount exceeds the remaining payable balance%'
      and not exists (select 1 from affiliate_month_balances() b where b.referrer in (v_ref, v_ref2) and b.balance > 0),
    format('nothing payable: no positive balance, either tier; 0.01 for last month -> %s; for this month -> %s', v_msg_last, v_msg_now));
  perform pg_temp.check(v_sc, not exists (select 1 from audit_logs a where a.record_id = v_inv and a.action = 'instalment_commission_review_required'),
    format('no instalment_commission_review_required audit (pre-fix: one per sync, left_over -30.00), got %s',
      (select count(*) from audit_logs a where a.record_id = v_inv and a.action = 'instalment_commission_review_required')));
  perform pg_temp.idempotent(v_sc, v_inv);
  perform pg_temp.dry_run_quiet(v_sc, v_inv);
exception when others then
  perform pg_temp.errored(v_sc, sqlerrm);
end $$;

-- 10b. Lowered below what the take-backs already recovered. As 9 (X +60.00
-- two months ago, paid out in full; a -30.00 take-back last month, netted by
-- last month's 120.00 payout; cancelled: -30.00 squaring row today), then the
-- payout for two months ago is corrected 60.00 -> 10.00. The 50.00 unpaid
-- again is taken back in its month; the squaring row gives back all it still
-- takes back (+30.00) and the take-back the remaining 20.00, each in its own
-- month, so X nets to 0 and R is owed exactly the other invoice's 150.00 less
-- the 130.00 paid in all.
do $$
declare v_sc text := '10b payout lowered below the take-backs'; v_ref uuid; v_ref2 uuid; v_x uuid; v_y uuid; v_row uuid; v_tb uuid; v_sq uuid;
  v_po jsonb; v_msgs text := ''; v_msg text; v_m date; v_audits int;
begin
  v_ref := pg_temp.referrers('S10b'); v_ref2 := pg_temp.tier2_of(v_ref);
  v_y := pg_temp.product_invoice(pg_temp.customer('PPT S10b other buyer', v_ref), pg_temp.fx('p1000'));
  perform pg_temp.pay(v_y, 1000);
  perform pg_temp.as_if_settled_on(v_y, pg_temp.prev() - 10);
  v_x := pg_temp.product_invoice(pg_temp.customer('PPT S10b buyer', v_ref), pg_temp.fx('p1000'));
  perform pg_temp.pay_registered_on(v_x, 400, pg_temp.prev2());
  select c.id into v_row from commissions c where c.invoice_id = v_x and c.referrer_customer_id = v_ref
     and c.earning_basis = 'instalment' and c.commission_amount = 60 and c.invoice_paid_date = pg_temp.prev2();
  v_po := affiliate_payout_save(null, null, v_ref, pg_temp.prev2_m(), 60, pg_temp.fx('m'), sg_today(),
            'PPT S10b two months ago', null, null, gen_random_uuid());
  perform pg_temp.correct_to(v_x, 200);
  perform pg_temp.as_if_recorded_on(v_x, pg_temp.prev());
  select c.id into v_tb from commissions c where c.invoice_id = v_x and c.referrer_customer_id = v_ref
     and c.status = 'earned' and c.commission_amount = -30 and c.invoice_paid_date = pg_temp.prev() and c.adjusts_commission_id is null;
  perform affiliate_payout_save(null, null, v_ref, pg_temp.prev_m(), 120, pg_temp.fx('m'), sg_today(),
            'PPT S10b last month', null, null, gen_random_uuid());
  perform cancel_invoice_recorded(v_x, 'Customer withdrew', gen_random_uuid());
  select c.id into v_sq from commissions c where c.invoice_id = v_x and c.referrer_customer_id = v_ref
     and c.status = 'earned' and c.commission_amount = -30 and c.invoice_paid_date = sg_today()
     and c.reversal_reason like 'Part-payment commission squared%';
  perform pg_temp.check(v_sc, v_row is not null and v_tb is not null and v_sq is not null
      and (select i.status::text from invoices i where i.id = v_x) = 'cancelled'
      and pg_temp.balance(v_ref, pg_temp.prev2_m()) = 0 and pg_temp.balance(v_ref, pg_temp.prev_m()) = 0
      and pg_temp.balance(v_ref, pg_temp.cur_m()) = -30,
    format('fixture: as 9: +60.00 paid out, -30.00 take-back last month (netted by its payout), cancelled: -30.00 squaring row today; got %s / %s / %s',
      pg_temp.balance(v_ref, pg_temp.prev2_m()), pg_temp.balance(v_ref, pg_temp.prev_m()), pg_temp.balance(v_ref, pg_temp.cur_m())));

  v_po := affiliate_payout_save((v_po->>'id')::uuid, (v_po->>'version')::int, null, null, 10, pg_temp.fx('m'), sg_today(),
            'PPT S10b two months ago', null, 'Only 10.00 was transferred', gen_random_uuid());
  perform pg_temp.check(v_sc, commission_unpaid_amount(v_row) = 50 and pg_temp.balance(v_ref, pg_temp.prev2_m()) = 50,
    format('fixture: the payout for two months ago corrected 60.00 -> 10.00: 50.00 of the +60.00 row unpaid again, that month %s payable before any sync',
      pg_temp.balance(v_ref, pg_temp.prev2_m())));

  perform reconcile_invoice_commissions(v_x, 'Payout corrected');
  perform pg_temp.check(v_sc, pg_temp.balance(v_ref, pg_temp.prev2_m()) = 0
      and exists (select 1 from commissions c where c.adjusts_commission_id = v_row and c.commission_amount = -50
                    and c.invoice_paid_date = pg_temp.prev2() and c.status = 'earned'),
    format('two months ago 0: the 50.00 unpaid again is taken back there by a linked -50.00, got %s', pg_temp.balance(v_ref, pg_temp.prev2_m())));
  perform pg_temp.check(v_sc, (select coalesce(sum(c.commission_amount),0) from commissions c
                                 where c.adjusts_commission_id = v_sq and c.status in ('earned','paid')) = 30
      and exists (select 1 from commissions c where c.adjusts_commission_id = v_sq and c.commission_amount = 30
                    and c.invoice_paid_date = sg_today() and c.status = 'earned')
      and pg_temp.balance(v_ref, pg_temp.cur_m()) = 0,
    format('the squaring row gives back exactly the 30.00 it takes back (a linked +30.00 today), not the 50.00: this month 0, never payable (pre-fix -60.00, nothing given back), got %s',
      pg_temp.balance(v_ref, pg_temp.cur_m())));
  perform pg_temp.check(v_sc, (select c.status::text from commissions c where c.id = v_tb) = 'earned'
      and exists (select 1 from commissions c where c.adjusts_commission_id = v_tb and c.commission_amount = 20
                    and c.invoice_paid_date = pg_temp.prev() and c.status = 'earned')
      and (select sum(c.commission_amount) from commissions c
            where c.invoice_id = v_x and c.referrer_customer_id = v_ref and c.status in ('earned','paid')) = 0,
    format('the -30.00 take-back last month gives back the remaining 20.00 in its own month (linked +20.00), and X nets to 0 for R; last month now %s',
      pg_temp.balance(v_ref, pg_temp.prev_m())));
  foreach v_m in array array[pg_temp.prev2_m(), pg_temp.prev_m(), pg_temp.cur_m()] loop
    v_msg := pg_temp.payout_attempt(v_ref, v_m, 0.01);
    if v_msg not like 'Amount exceeds the remaining payable balance%' then v_msgs := v_msgs || format('%s: %s; ', v_m, v_msg); end if;
  end loop;
  perform pg_temp.check(v_sc,
      pg_temp.balance(v_ref, pg_temp.prev2_m()) = 0 and pg_temp.balance(v_ref, pg_temp.cur_m()) = 0
      and pg_temp.balance(v_ref, pg_temp.prev_m()) = 20
      and (select sum(b.balance) from affiliate_month_balances() b where b.referrer = v_ref) = 20
      and pg_temp.balance(v_ref2, pg_temp.prev2_m()) = 0 and pg_temp.balance(v_ref2, pg_temp.cur_m()) = 0,
    format('R is owed exactly 20.00 overall (the other invoice''s 150.00 less the 130.00 paid), all of it last month, the other invoice''s month; two months ago and this month 0: %s / %s / %s',
      pg_temp.balance(v_ref, pg_temp.prev2_m()), pg_temp.balance(v_ref, pg_temp.prev_m()), pg_temp.balance(v_ref, pg_temp.cur_m())));
  select count(*) into v_audits from audit_logs a where a.record_id = v_x and a.action = 'instalment_commission_review_required';
  perform pg_temp.check(v_sc, v_audits = 0,
    format('everything was given back against a recovery row, so nothing is left for review (pre-fix: an audit of -50.00 on every sync); got %s', v_audits));
  perform pg_temp.idempotent(v_sc, v_x);
  perform reconcile_invoice_commissions(v_x, 'Checked again');
  perform pg_temp.check(v_sc, (select count(*) from audit_logs a where a.record_id = v_x and a.action = 'instalment_commission_review_required') = 0,
    format('a further reconcile writes no review audit either (pre-fix: one more per sync), got %s',
      (select count(*) from audit_logs a where a.record_id = v_x and a.action = 'instalment_commission_review_required')));
  perform pg_temp.dry_run_quiet(v_sc, v_x);
exception when others then
  perform pg_temp.errored(v_sc, sqlerrm);
end $$;

-- ═════ Summary ═════
do $$
declare r record; v_fail int;
begin
  for r in select scenario, count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed
             from ppt_results group by scenario order by min(n) loop
    raise notice 'SUMMARY  [%] pass=% fail=%', r.scenario, r.passed, r.failed;
  end loop;
  select count(*) into v_fail from ppt_results where not ok;
  if v_fail > 0 then raise exception 'FAIL: % check(s) failed', v_fail; end if;
  raise notice 'PASS: every take-back and re-settlement check passed (% checks)', (select count(*) from ppt_results);
end $$;

rollback;
