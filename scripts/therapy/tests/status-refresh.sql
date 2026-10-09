-- 410: therapy statuses follow the calendar.
--
-- Before 410 nothing ran refresh_purchased_therapy_statuses or
-- refresh_legacy_therapy_statuses, and every check read the stored status: a
-- unit scheduled to start a week ago was still 'scheduled', so it could be
-- claimed again to start later, moved, or refunded as unused (THERAPY-1).
-- Reschedule on a unit with a start date changed only the date shown
-- (THERAPY-10). The invoice's Cancel closed such a unit as refunded (unused),
-- and Correct Invoice moved it to another customer. This suite reproduces
-- them (section 1, before 410), applies 410, and checks the rule
-- (purchased_therapy_status_on), every guard that reads it, the nightly
-- refresh and its job.
--
-- Disposable local database only; everything is rolled back. The migration
-- is applied inside this transaction, so run the file on its own:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/therapy/tests/status-refresh.sql
-- On a local database that has drifted from production, pass a file that
-- installs production's functions (cancel_invoice_recorded and
-- correct_invoice among them, with what they call), run right after the
-- begin below:
--   psql -X -v ON_ERROR_STOP=1 -v prelude=/path/to/prod_prelude.sql -f ...
-- pg_cron installs only in the database cron.database_name names; elsewhere
-- a stand-in for cron.schedule and cron.job is created (and rolled back).
-- Every name, phone and number is invented.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif

do $stub$
begin
  if to_regclass('cron.job') is null then
    create schema cron;
    create table cron.job(jobid bigserial primary key, schedule text not null, command text not null,
      nodename text not null default 'localhost', nodeport int not null default 5432,
      database text not null default current_database(), username text not null default current_user,
      active boolean not null default true, jobname text);
    create function cron.schedule(job_name text, schedule text, command text) returns bigint
    language plpgsql as $f$
    declare v bigint;
    begin
      update cron.job j set schedule = $2, command = $3, database = current_database(), username = current_user
       where j.jobname = $1 returning j.jobid into v;
      if v is null then
        insert into cron.job(schedule, command, jobname) values ($2, $3, $1) returning jobid into v; end if;
      return v;
    end $f$;
  end if;
end $stub$;

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
-- The error a call raises, or null when it succeeds; rolled back either way.
create function pg_temp.refused(q text) returns text language plpgsql as $$
begin
  begin
    execute q;
    raise exception 'T410: accepted';
  exception when others then
    if sqlerrm = 'T410: accepted' then return null; end if;
    return sqlerrm;
  end;
end $$;
create function pg_temp.t(n int default 0) returns date language sql as $$ select public.sg_today() + n $$;
-- One purchased unit for its own customer (so no two share a package period
-- unless a test means them to).
create function pg_temp.unit(no text, st text, act date, exp date, deadline date, benefit text default 'unlimited',
                             cust text default null, sched date default null, inv text default 'inv')
returns uuid language plpgsql as $$
declare v uuid; c uuid;
begin
  c := pg_temp.fx(coalesce(cust, 'c_' || no));
  if c is null then
    insert into public.customers(full_name, phone)
      values ('T410 Customer ' || no, '+659140' || lpad((200 + (select count(*) from fx))::text, 4, '0'))
      returning id into c;
    insert into fx values (coalesce(cust, 'c_' || no), c);
  end if;
  insert into public.purchased_therapy_entitlements(entitlement_no, customer_id, store_id, package_id, invoice_id,
      package_name, duration_months, price_snapshot, purchase_date, activation_deadline, scheduled_date,
      activation_date, expiry_date, status, benefit_choice, offered_choices)
    values ('T410-' || no, c, pg_temp.fx('store'), pg_temp.fx('pkg'), pg_temp.fx(inv), 'T410 Six Months', 6, 1000,
            pg_temp.t(-30), deadline, coalesce(sched, act), act, exp, st, benefit, array['unlimited'])
    returning id into v;
  insert into fx values (no, v);
  return v;
end $$;
create function pg_temp.st(no text) returns text language sql as
$$ select status from public.purchased_therapy_entitlements where id = pg_temp.fx(no) $$;
-- Correct Invoice moving K1's invoice to another customer, lines unchanged:
-- the error it raises, or null.
create function pg_temp.move_k1() returns text language sql as $$
  select pg_temp.refused(format(
    'select public.correct_invoice(%L, %L::jsonb, %L::jsonb, %L, gen_random_uuid())', pg_temp.fx('inv_k'),
    (select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind::text, 'quantity', it.quantity,
                                         'product_id', it.product_id, 'unit_price', it.unit_price))
       from public.invoice_items it where it.invoice_id = pg_temp.fx('inv_k')),
    jsonb_build_object('customer_id', pg_temp.fx('other'), 'benefit_action', 'transfer',
                       'expected_edit_count', (select coalesce(edit_count, 0) from public.invoices where id = pg_temp.fx('inv_k'))),
    'T410 wrong customer')) $$;

-- ===== Fixtures =====
do $$
declare v uuid;
begin
  insert into fx values ('owner', gen_random_uuid());
  insert into auth.users(id, email) values (pg_temp.fx('owner'), 't410-therapy-owner@sig.invalid');
  insert into public.profiles(id, full_name, email, role)
    values (pg_temp.fx('owner'), 'T410 Therapy Owner', 't410-therapy-owner@sig.invalid', 'owner');
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  insert into public.stores(name, code, country_code) values ('T410 Therapy Store', 'T410T', 'SG') returning id into v;
  insert into fx values ('store', v);
  insert into public.customers(full_name, phone) values ('T410 Buyer', '+6591400199') returning id into v;
  insert into fx values ('buyer', v);
  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status)
    values ('T410-THERAPY', pg_temp.fx('store'), pg_temp.fx('buyer'), pg_temp.fx('owner'), 'paid') returning id into v;
  insert into fx values ('inv', v);
  insert into public.unlimited_therapy_packages(name, duration_months) values ('T410 Six Months', 6) returning id into v;
  insert into fx values ('pkg', v);

  -- U1: scheduled to start a week ago (as UTP-0000010 on 9 Oct 2026).
  perform pg_temp.unit('U1', 'scheduled', pg_temp.t(-7), pg_temp.t(170), pg_temp.t(300));
  -- U2, U3: scheduled to start in ten days.
  perform pg_temp.unit('U2', 'scheduled', pg_temp.t(10), pg_temp.t(190), pg_temp.t(300));
  perform pg_temp.unit('U3', 'scheduled', pg_temp.t(10), pg_temp.t(190), pg_temp.t(300));
  -- U4: not claimed yet, deadline far off.
  perform pg_temp.unit('U4', 'pending_activation', null, null, pg_temp.t(300), null);
  -- U5: not claimed, its deadline was yesterday.
  perform pg_temp.unit('U5', 'pending_activation', null, null, pg_temp.t(-1));
  -- U6: rescheduled without a start date, its deadline was yesterday.
  perform pg_temp.unit('U6', 'scheduled', null, null, pg_temp.t(-1), 'unlimited', null, pg_temp.t(-20));
  -- U7: active, ended yesterday.
  perform pg_temp.unit('U7', 'active', pg_temp.t(-200), pg_temp.t(-1), pg_temp.t(100));
  -- U8: scheduled, started and ended while nothing refreshed it.
  perform pg_temp.unit('U8', 'scheduled', pg_temp.t(-200), pg_temp.t(-2), pg_temp.t(100));
  -- U9 running, and U10 of the same package and customer scheduled over it
  -- (the same-package rule refuses U10's start): the refresh leaves U10.
  perform pg_temp.unit('U9', 'active', pg_temp.t(-30), pg_temp.t(30), pg_temp.t(100), 'unlimited', 'c_shared');
  perform pg_temp.unit('U10', 'scheduled', pg_temp.t(-1), pg_temp.t(100), pg_temp.t(100), 'unlimited', 'c_shared');

  -- The invoice's Cancel: C1 scheduled to start three days ago, C2 to start
  -- in ten days, C3 never claimed and past its deadline.
  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status)
    values ('T410-CANCEL', pg_temp.fx('store'), pg_temp.fx('buyer'), pg_temp.fx('owner'), 'paid') returning id into v;
  insert into fx values ('inv_c', v);
  perform pg_temp.unit('C1', 'scheduled', pg_temp.t(-3), pg_temp.t(177), pg_temp.t(300), 'unlimited', null, null, 'inv_c');
  perform pg_temp.unit('C2', 'scheduled', pg_temp.t(10), pg_temp.t(190), pg_temp.t(300), 'unlimited', null, null, 'inv_c');
  perform pg_temp.unit('C3', 'pending_activation', null, null, pg_temp.t(-1), 'unlimited', null, null, 'inv_c');
  -- Correct Invoice: a sale through the till whose unit K1 was scheduled to
  -- start three days ago; the correction moves the invoice to another customer.
  insert into public.payment_methods(name) values ('T410 Therapy Cash') returning id into v;
  insert into fx values ('cash', v);
  insert into public.products(name, sku, product_type) values ('T410 Therapy Product', 'T410-TP', 'own') returning id into v;
  insert into fx values ('product', v);
  insert into public.store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('store'), v, 10);
  perform public.set_product_prices(pg_temp.fx('store'), v, 50, 50, 'available');
  v := public.create_invoice(pg_temp.fx('store'), pg_temp.fx('buyer'), null,
         jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('product'), 'quantity', 1)));
  insert into fx values ('inv_k', v);
  perform public.record_invoice_payment(v, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 50)),
                                        gen_random_uuid());
  perform pg_temp.unit('K1', 'scheduled', pg_temp.t(-3), pg_temp.t(177), pg_temp.t(300), 'unlimited', 'buyer', null, 'inv_k');
  insert into public.customers(full_name, phone) values ('T410 Other Customer', '+6591400198') returning id into v;
  insert into fx values ('other', v);

  -- Legacy: L1 scheduled to start three days ago; L2 active, ended yesterday;
  -- L3 unclaimed past its deadline (the Legacy refresh leaves those).
  insert into public.therapy_entitlements(entitlement_no, customer_id, store_id, package_name, entitlement_kind,
      duration_months, qualifying_amount, qualified_value, activation_deadline, status, activation_date, expiry_date)
    values ('T410-L1', pg_temp.fx('buyer'), pg_temp.fx('store'), 'T410 Legacy', 'unlimited', 3, 0, 0, pg_temp.t(100),
            'scheduled', pg_temp.t(-3), pg_temp.t(90)),
           ('T410-L2', pg_temp.fx('buyer'), pg_temp.fx('store'), 'T410 Legacy', 'unlimited', 3, 0, 0, pg_temp.t(100),
            'active', pg_temp.t(-100), pg_temp.t(-1)),
           ('T410-L3', pg_temp.fx('buyer'), pg_temp.fx('store'), 'T410 Legacy', 'unlimited', 3, 0, 0, pg_temp.t(-5),
            'pending_activation', null, null);
end $$;

-- ===== 1. Before 410: the defects, reproduced =====
-- Only on a database without 410; everything here is rolled back.
savepoint before410;
do $$
declare e text;
begin
  if md5(pg_get_functiondef('public.therapy_unit_consumed(uuid)'::regprocedure)) <> '7fe942b73bd10d566383d38c923162fe' then
    raise notice 'SKIP  section 1: this database already has 410'; return; end if;
  perform pg_temp.check(not public.therapy_unit_consumed(pg_temp.fx('U1')),
    'before 410: a unit that started a week ago does not count as used (the defect)');
  e := pg_temp.refused(format('select public.refund_purchased_therapy(%L, %L)', pg_temp.fx('U1'), 'T410'));
  perform pg_temp.check(e is null, 'before 410: it can be refunded as unused (the defect)');
  e := pg_temp.refused(format('select public.claim_purchased_therapy(%L, ''unlimited'', %L)', pg_temp.fx('U1'), pg_temp.t(20)));
  perform pg_temp.check(e is null, 'before 410: it can be started again three weeks later (the defect)');
  perform public.reschedule_purchased_therapy(pg_temp.fx('U2'), pg_temp.t(15), 'T410');
  perform pg_temp.check((select scheduled_date = pg_temp.t(15) and activation_date = pg_temp.t(10)
                           from public.purchased_therapy_entitlements where id = pg_temp.fx('U2')),
    'before 410: Reschedule moves only the date shown; the start stays (THERAPY-10)');
  e := pg_temp.refused('select public.refresh_purchased_therapy_statuses()');
  perform pg_temp.check(e like '%excl_pte_same_package_no_overlap%',
    'before 410: one unit the same-package rule will not start stops the whole refresh: ' || coalesce(e, 'ran'));
  update public.purchased_therapy_entitlements set status = 'expired' where id = pg_temp.fx('U10');
  perform public.refresh_purchased_therapy_statuses();
  perform pg_temp.check(pg_temp.st('U6') = 'scheduled' and pg_temp.st('U1') = 'active',
    'before 410: a unit rescheduled without a start date never expires at its deadline');
end $$;
rollback to savepoint before410;
do $$
declare e text;
begin
  if md5(pg_get_functiondef('public.therapy_unit_consumed(uuid)'::regprocedure)) <> '7fe942b73bd10d566383d38c923162fe' then
    return; end if;
  perform public.cancel_invoice_recorded(pg_temp.fx('inv_c'), 'T410 cancelled', gen_random_uuid());
  perform pg_temp.check(pg_temp.st('C1') = 'refunded' and pg_temp.st('C3') = 'refunded'
                        and not public.therapy_unit_consumed(pg_temp.fx('C1')),
    'before 410: Cancel closes a unit that started three days ago as refunded, so the refund finds nothing used (the defect)');
  e := pg_temp.move_k1();
  perform pg_temp.check(e is null or e not like 'Resolve the consumed therapy entitlement%',
    'before 410: Correct Invoice does not stop at K1, started three days ago (the defect): ' || coalesce(e, 'corrected'));
end $$;
rollback to savepoint before410;
release savepoint before410;

-- ===== 2. Apply 410 =====
\ir ../../../supabase/410_clawbacks_carried_forward_and_therapy_status_refresh.sql

-- ===== 3. The rule =====
do $$
declare d date := '2026-10-09';
begin
  perform pg_temp.check(
        public.purchased_therapy_status_on('scheduled', '2026-10-02', '2027-04-08', '2027-09-08', d) = 'active'
    and public.purchased_therapy_status_on('scheduled', '2026-10-09', '2027-04-08', '2027-09-08', d) = 'active'
    and public.purchased_therapy_status_on('scheduled', '2026-10-10', '2027-04-08', '2027-09-08', d) = 'scheduled'
    and public.purchased_therapy_status_on('scheduled', '2026-01-01', '2026-10-08', '2027-01-01', d) = 'expired'
    and public.purchased_therapy_status_on('active', '2026-01-01', '2026-10-09', '2027-01-01', d) = 'active'
    and public.purchased_therapy_status_on('active', '2026-01-01', '2026-10-08', '2027-01-01', d) = 'expired'
    and public.purchased_therapy_status_on('active', '2026-10-01', null, '2027-01-01', d) = 'active'
    and public.purchased_therapy_status_on('pending_activation', null, null, '2026-10-09', d) = 'pending_activation'
    and public.purchased_therapy_status_on('pending_activation', null, null, '2026-10-08', d) = 'expired'
    and public.purchased_therapy_status_on('scheduled', null, null, '2026-10-08', d) = 'expired'
    and public.purchased_therapy_status_on('scheduled', null, null, '2026-10-09', d) = 'scheduled'
    and public.purchased_therapy_status_on('cancelled', '2026-01-01', '2026-02-01', '2026-03-01', d) = 'cancelled'
    and public.purchased_therapy_status_on('refunded', null, null, '2026-03-01', d) = 'refunded'
    and public.purchased_therapy_status_on('expired', null, null, '2026-03-01', d) = 'expired',
    '3: purchased_therapy_status_on: start reached is active, expiry passed is expired, never started past the deadline is expired');
  perform pg_temp.check(not has_function_privilege('authenticated', 'public.purchased_therapy_status_on(text,date,date,date,date)', 'execute')
    and not has_function_privilege('anon', 'public.purchased_therapy_status_on(text,date,date,date,date)', 'execute')
    and not has_function_privilege('authenticated', 'public.run_therapy_status_refresh()', 'execute')
    and not has_function_privilege('anon', 'public.run_therapy_status_refresh()', 'execute')
    and has_function_privilege('service_role', 'public.run_therapy_status_refresh()', 'execute')
    and has_function_privilege('service_role', 'public.purchased_therapy_status_on(text,date,date,date,date)', 'execute'),
    '3: the rule and the nightly run are the service role''s alone');
  perform pg_temp.check(has_function_privilege('authenticated',
      'public.claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)', 'execute')
    and has_function_privilege('authenticated', 'public.refund_purchased_therapy(uuid,text)', 'execute')
    and has_function_privilege('authenticated', 'public.reschedule_purchased_therapy(uuid,date,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.therapy_unit_consumed(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.refresh_purchased_therapy_statuses()', 'execute'),
    '3: the patched functions keep their grants');
end $$;

-- ===== 4. A start date already reached counts as started =====
do $$
declare e text;
begin
  perform pg_temp.check(pg_temp.st('U1') = 'scheduled', '4: U1 is still stored as scheduled (nothing has refreshed it)');
  perform pg_temp.check(public.therapy_unit_consumed(pg_temp.fx('U1')) and not public.therapy_unit_consumed(pg_temp.fx('U2'))
                        and public.therapy_unit_consumed(pg_temp.fx('U5')) and not public.therapy_unit_consumed(pg_temp.fx('U4')),
    '4: therapy_unit_consumed: started a week ago yes, starts in ten days no, deadline passed yes, still open no');
  e := pg_temp.refused(format('select public.refund_purchased_therapy(%L, %L)', pg_temp.fx('U1'), 'T410'));
  perform pg_temp.check(e like 'Therapy cannot be refunded after activation from here.%',
    '4: Refund on U1 is refused: ' || coalesce(e, 'accepted'));
  e := pg_temp.refused(format('select public.refund_purchased_therapy(%L, %L)', pg_temp.fx('U5'), 'T410'));
  perform pg_temp.check(e like 'This therapy was not started by its activation deadline (' || pg_temp.t(-1)
                               || '), so it has expired and cannot be refunded from here.%',
    '4: Refund on a unit never started by its deadline is refused, and says it expired: ' || coalesce(e, 'accepted'));
  e := pg_temp.refused(format('select public.claim_purchased_therapy(%L, ''unlimited'', %L)', pg_temp.fx('U1'), pg_temp.t(20)));
  perform pg_temp.check(e = 'Unlimited therapy on this purchase has already started',
    '4: Claim cannot start U1 again later: ' || coalesce(e, 'accepted'));
  e := pg_temp.refused(format('select public.claim_purchased_therapy(%L, ''unlimited'', %L)', pg_temp.fx('U5'), pg_temp.t(0)));
  perform pg_temp.check(e = 'Unlimited therapy on this purchase has already expired: it was not started by its deadline, '
                            || pg_temp.t(-1),
    '4: Claim on a unit never started by its deadline says so: ' || coalesce(e, 'accepted'));
  e := pg_temp.refused(format('select public.activate_purchased_therapy(%L, %L)', pg_temp.fx('U1'), pg_temp.t(20)));
  perform pg_temp.check(e = 'Entitlement is already active',
    '4: Activate called directly cannot move U1''s start either: ' || coalesce(e, 'accepted'));
  e := pg_temp.refused(format('select public.reschedule_purchased_therapy(%L, %L, %L)', pg_temp.fx('U1'), pg_temp.t(5), 'T410'));
  perform pg_temp.check(e = 'Dates can only be changed before activation',
    '4: Reschedule on U1 is refused: ' || coalesce(e, 'accepted'));
  perform pg_temp.check((select activation_date = pg_temp.t(-7) and expiry_date = pg_temp.t(170) and status = 'scheduled'
                           from public.purchased_therapy_entitlements where id = pg_temp.fx('U1')),
    '4: U1 is left exactly as it was');
end $$;

-- ===== 5. Reschedule and Claim on units that have not started =====
do $$
declare e text; v_old date;
begin
  e := pg_temp.refused(format('select public.reschedule_purchased_therapy(%L, %L, %L)', pg_temp.fx('U2'), pg_temp.t(15), 'T410'));
  perform pg_temp.check(e = 'This therapy is set to start on ' || pg_temp.t(10)
                            || '. To move its start, use Claim, which works out the expiry again.',
    '5: Reschedule on a unit with a start date points to Claim (THERAPY-10): ' || coalesce(e, 'accepted'));
  select expiry_date into v_old from public.purchased_therapy_entitlements where id = pg_temp.fx('U2');
  perform public.claim_purchased_therapy(pg_temp.fx('U2'), 'unlimited', pg_temp.t(20));
  perform pg_temp.check((select status = 'scheduled' and activation_date = pg_temp.t(20) and expiry_date > v_old
                           from public.purchased_therapy_entitlements where id = pg_temp.fx('U2')),
    '5: Claim moves a start not yet reached, and works out the expiry again');
  perform public.reschedule_purchased_therapy(pg_temp.fx('U4'), pg_temp.t(5), 'T410');
  perform pg_temp.check((select status = 'scheduled' and scheduled_date = pg_temp.t(5) and activation_date is null
                           from public.purchased_therapy_entitlements where id = pg_temp.fx('U4')),
    '5: Reschedule still plans a date for a unit not yet claimed');
  perform public.refund_purchased_therapy(pg_temp.fx('U3'), 'T410 not started');
  perform pg_temp.check(pg_temp.st('U3') = 'refunded', '5: a unit that has not started can still be refunded');
end $$;

-- ===== 8. Cancel and Correct Invoice read the dates too =====
-- Before the refresh below, so the stored statuses are still the old ones.
do $$
declare e text;
begin
  perform pg_temp.check(pg_temp.st('C1') = 'scheduled' and pg_temp.st('K1') = 'scheduled',
    '8: C1 and K1 are still stored as scheduled (nothing has refreshed them)');
  perform public.cancel_invoice_recorded(pg_temp.fx('inv_c'), 'T410 cancelled', gen_random_uuid());
  perform pg_temp.check((select status::text from public.invoices where id = pg_temp.fx('inv_c')) = 'cancelled',
    '8: the invoice is cancelled');
  perform pg_temp.check(pg_temp.st('C2') = 'refunded', '8: Cancel closes the unit not started (C2) as refunded, as before');
  perform pg_temp.check(pg_temp.st('C1') = 'scheduled' and public.therapy_unit_consumed(pg_temp.fx('C1')),
    '8: C1, started three days ago, is not closed as unused: the refund will need the Owner''s authorization, as for an active unit');
  perform pg_temp.check(pg_temp.st('C3') = 'pending_activation' and public.therapy_unit_consumed(pg_temp.fx('C3')),
    '8: C3, never started by its deadline, has expired and is not refunded as unused either');
  e := pg_temp.move_k1();
  perform pg_temp.check(e like 'Resolve the consumed therapy entitlement before changing its customer, store or invoice lines%',
    '8: Correct Invoice refuses to move K1 to another customer: ' || coalesce(e, 'corrected'));
  perform pg_temp.check((select customer_id = pg_temp.fx('buyer') from public.purchased_therapy_entitlements where id = pg_temp.fx('K1'))
                        and (select customer_id = pg_temp.fx('buyer') from public.invoices where id = pg_temp.fx('inv_k')),
    '8: K1 and its invoice stay with the buyer');
end $$;

-- ===== 6. The nightly refresh =====
do $$
declare r jsonb; x record;
begin
  r := public.run_therapy_status_refresh();
  perform pg_temp.check((r->>'on')::date = public.sg_today(), '6: the run reports today');
  perform pg_temp.check(pg_temp.st('U1') = 'active' and pg_temp.st('U2') = 'scheduled' and pg_temp.st('U4') = 'scheduled'
                        and pg_temp.st('U5') = 'expired' and pg_temp.st('U6') = 'expired' and pg_temp.st('U7') = 'expired'
                        and pg_temp.st('U8') = 'expired' and pg_temp.st('U9') = 'active' and pg_temp.st('U3') = 'refunded',
    '6: started -> active; ended, or never started by the deadline -> expired; the rest as they were');
  perform pg_temp.check(pg_temp.st('U10') = 'scheduled' and r->'purchased_left' ? 'T410-U10',
    '6: a unit the same-package rule will not start is left, and reported: ' || (r->'purchased_left')::text);
  perform pg_temp.check((r->>'purchased_changed')::int
                        >= (select count(*) from public.purchased_therapy_entitlements e
                             where e.entitlement_no in ('T410-U1','T410-U5','T410-U6','T410-U7','T410-U8')),
    '6: it counts the units it changed: ' || r::text);
  perform pg_temp.check(not exists (
      select 1 from public.purchased_therapy_entitlements e
       where e.entitlement_no like 'T410-U%' and e.entitlement_no <> 'T410-U10'
         and e.status <> public.purchased_therapy_status_on(e.status, e.activation_date, e.expiry_date,
                                                            e.activation_deadline, public.sg_today())),
    '6: afterwards every unit''s stored status is the one its dates give');
  perform pg_temp.check((select status from public.therapy_entitlements where entitlement_no = 'T410-L1') = 'active'
                        and (select status from public.therapy_entitlements where entitlement_no = 'T410-L2') = 'expired'
                        and (select status from public.therapy_entitlements where entitlement_no = 'T410-L3') = 'pending_activation',
    '6: Legacy too: started -> active, ended -> expired, unclaimed left to its deadline display');
  perform pg_temp.check((select updated_at = now() from public.purchased_therapy_entitlements where id = pg_temp.fx('U1')),
    '6: a unit moved is stamped updated');
  r := public.run_therapy_status_refresh();
  perform pg_temp.check((r->>'purchased_changed')::int = 0 and (r->>'legacy_expired')::int = 0,
    '6: run again the same day, it changes nothing: ' || r::text);
  perform pg_temp.check(public.therapy_unit_consumed(pg_temp.fx('U10')),
    '6: the unit left behind still counts as started for every check');
end $$;

-- ===== 7. The nightly job =====
do $$
begin
  perform pg_temp.check((select count(*) from cron.job where jobname = 'therapy-status-refresh') = 1
                        and exists (select 1 from cron.job where jobname = 'therapy-status-refresh'
                                      and schedule = '5 16 * * *' and command = 'select public.run_therapy_status_refresh()'
                                      and active and database = current_database()),
    '7: one job, 16:05 GMT (00:05 in Singapore), running run_therapy_status_refresh()');
end $$;

rollback;
