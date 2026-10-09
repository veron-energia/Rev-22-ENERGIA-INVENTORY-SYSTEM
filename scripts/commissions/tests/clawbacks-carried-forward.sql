-- 410: commission taken back is recovered from later payouts.
--
-- The Owner decided on 3 Oct 2026 that commission already paid out and then
-- taken back (a refund, a cancellation, the sale given to another affiliate)
-- is recovered from the affiliate's future payouts. Before 410 the take-back
-- was dated in the month already paid, and the payout, the balances page,
-- the Affiliates page and the portal each looked at one month at a time: an
-- affiliate at -562.35 for one month was still offered +7.08 for the next.
-- This suite reproduces that (section 1, before 410), applies 410, and checks
-- the netting, the payout cap, the dating of new take-backs (paid-out part
-- today, never-paid part in its own month), what each page reads, and the
-- blocked commission figures (AFFILIATES-3). Sections 11-16 run real sales
-- through the till: a part refund of a sale already paid out leaves the paid
-- month as paid and nets what the sale still earns (11); the refund undone
-- (13); a take-back written whole before 410 (14, as INV-2026-0292 on 3 Oct);
-- a sale given to another affiliate after both were paid out (15); a payout
-- lowered after its take-back (16); and the invoice worked out again in a
-- later month, which moves nothing (12, last: it moves sg_today()).
--
-- Disposable local database only; everything is rolled back. The migration
-- is applied inside this transaction, so run the file on its own:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/commissions/tests/clawbacks-carried-forward.sql
-- On a local database that has drifted from production, pass a file that
-- installs production's functions (410 changes cancel_invoice_recorded and
-- correct_invoice too, and refuses unless they are production's versions),
-- run right after the begin below:
--   psql -X -v ON_ERROR_STOP=1 -v prelude=/path/to/prod_prelude.sql -f ...
-- pg_cron installs only in the database cron.database_name names; elsewhere
-- a stand-in for cron.schedule and cron.job is created (and rolled back), so
-- 410's nightly-job step can run. Every name, phone and amount is invented.
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
-- The error a call raises, or null when it succeeds (rolled back either way).
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
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', pg_temp.fx(key)::text, true); select null::void $$;
create function pg_temp.cur() returns date language sql as $$ select date_trunc('month', public.sg_today())::date $$;
create function pg_temp.bal(ref text, m date) returns numeric language sql as
$$ select coalesce((select balance from public.affiliate_month_balances() where referrer = pg_temp.fx(ref) and month = m), 0) $$;
create function pg_temp.pay(ref text, m date, amt numeric) returns uuid language sql as
$$ select (public.record_affiliate_payout(pg_temp.fx(ref), m, amt, pg_temp.fx('cash'), public.sg_today(),
          'T410', null, gen_random_uuid())->>'id')::uuid $$;
create function pg_temp.commission(ref text, inv text, amt numeric, on_day date, st text default 'earned')
returns uuid language sql as $$
  insert into public.commissions(invoice_id, buyer_customer_id, referrer_customer_id, tier, product_type,
                                 line_amount, rate, commission_amount, invoice_paid_date, status, block_reason)
  values (pg_temp.fx(inv), pg_temp.fx('buyer'), pg_temp.fx(ref), 'tier1', 'own', amt * 10, 10, amt, on_day,
          st::commission_status, case when st = 'blocked' then 'Affiliate Not Activated' end)
  returning id $$;
create function pg_temp.cancel(inv text) returns void language plpgsql as $$
begin
  update public.invoices set status = 'cancelled' where id = pg_temp.fx(inv);
  perform public.reconcile_invoice_commissions(pg_temp.fx(inv), 'T410 cancelled');
end $$;
-- The overview's month row for an affiliate and month, and its affiliate row.
create function pg_temp.group_of(ref text, m date) returns jsonb language sql as $$
  select g from jsonb_array_elements(public.affiliate_payout_overview()->'groups') g
   where g->>'referrer' = pg_temp.fx(ref)::text and (g->>'month')::date = m $$;
create function pg_temp.ref_row(ref text) returns jsonb language sql as $$
  select x from jsonb_array_elements(public.affiliate_payout_overview()->'referrers') x
   where x->>'referrer' = pg_temp.fx(ref)::text $$;

-- ===== Fixtures =====
do $$
declare v uuid; k text; n int := 0;
begin
  insert into fx values ('owner', gen_random_uuid()), ('portal', gen_random_uuid()), ('portal7', gen_random_uuid());
  insert into auth.users(id, email) values
    (pg_temp.fx('owner'), 't410-owner@sig.invalid'), (pg_temp.fx('portal'), 't410-aff1@sig.invalid'),
    (pg_temp.fx('portal7'), 't410-aff7@sig.invalid');
  insert into public.profiles(id, full_name, email, role)
    values (pg_temp.fx('owner'), 'T410 Owner', 't410-owner@sig.invalid', 'owner');
  perform pg_temp.as_user('owner');
  insert into public.stores(name, code, country_code) values ('T410 Store', 'T410', 'SG') returning id into v;
  insert into fx values ('store', v);
  insert into public.payment_methods(name) values ('T410 Cash') returning id into v;
  insert into fx values ('cash', v);
  insert into public.customers(full_name, phone) values ('T410 Buyer', '+6591400100') returning id into v;
  insert into fx values ('buyer', v);
  foreach k in array array['r1','r2','r3','r4','r5','r6','r7'] loop
    n := n + 1;
    insert into public.customers(full_name, phone) values ('T410 Affiliate ' || upper(k), '+65914001' || lpad((10 + n)::text, 2, '0'))
      returning id into v;
    insert into fx values (k, v);
    insert into public.customer_affiliates(customer_id, store_id, status, activated_at)
      values (v, pg_temp.fx('store'), 'active', now());
  end loop;
  foreach k in array array['i1','i2','i3','i4','i5','i6','i7','i8','i9','i10','i11','i12','i13'] loop
    insert into public.invoices(invoice_no, store_id, customer_id, created_by, status)
      values ('T410-' || upper(k), pg_temp.fx('store'), pg_temp.fx('buyer'), pg_temp.fx('owner'), 'paid')
      returning id into v;
    insert into fx values (k, v);
  end loop;
  insert into public.affiliate_accounts(auth_user_id, customer_id, status) values
    (pg_temp.fx('portal'), pg_temp.fx('r1'), 'claimed'), (pg_temp.fx('portal7'), pg_temp.fx('r7'), 'claimed');

  -- r1: the production case. February paid out in full; a take-back written
  -- the old way, dated in February (as the four rows of 3 Oct 2026 are);
  -- 7.08 earned this month.
  insert into fx values ('r1_c1', pg_temp.commission('r1', 'i1', 1000, '2020-02-10'));
  perform pg_temp.pay('r1', '2020-02-01', 1000);
  insert into public.commissions(invoice_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount,
                                 rate, commission_amount, invoice_paid_date, status, adjusts_commission_id, reversal_reason)
    values (pg_temp.fx('i1'), pg_temp.fx('buyer'), pg_temp.fx('r1'), 'tier1', 'own', -5623.50, 10, -562.35,
            '2020-02-10', 'earned', pg_temp.fx('r1_c1'), 'Future payout adjustment: T410 fixture');
  perform pg_temp.commission('r1', 'i2', 7.08, public.sg_today());

  -- r2: March paid out in full (two invoices); one of them is cancelled below.
  insert into fx values ('r2_c', pg_temp.commission('r2', 'i3', 300, '2020-03-05'));
  perform pg_temp.commission('r2', 'i4', 100, '2020-03-06');
  perform pg_temp.pay('r2', '2020-03-01', 400);

  -- r3: April paid out in part (60 of 100); cancelled below.
  insert into fx values ('r3_c', pg_temp.commission('r3', 'i5', 100, '2020-04-03'));
  perform pg_temp.pay('r3', '2020-04-01', 60);

  -- r4: May 200, 100 paid; June 150 paid out in full, cancelled below.
  perform pg_temp.commission('r4', 'i6', 200, '2020-05-04');
  insert into fx values ('r4_p', pg_temp.pay('r4', '2020-05-01', 100));
  perform pg_temp.commission('r4', 'i7', 150, '2020-06-04');
  perform pg_temp.pay('r4', '2020-06-01', 150);

  -- r5: July 100 unpaid; August 50 with 20 paid, its payout then under review.
  perform pg_temp.commission('r5', 'i8', 100, '2020-07-02');
  perform pg_temp.commission('r5', 'i9', 50, '2020-08-02');
  insert into fx values ('r5_p', pg_temp.pay('r5', '2020-08-01', 20));

  -- r6: September 30 and October 60 unpaid; November 50 paid out, cancelled below.
  perform pg_temp.commission('r6', 'i10', 30, '2020-09-02');
  perform pg_temp.commission('r6', 'i11', 60, '2020-10-02');
  perform pg_temp.commission('r6', 'i12', 50, '2020-11-02');
  perform pg_temp.pay('r6', '2020-11-01', 50);

  -- r7: commission withheld because the affiliate was not activated.
  perform pg_temp.commission('r7', 'i13', 30, '2020-12-02', 'blocked');
  perform pg_temp.commission('r7', 'i13', 39.87, '2020-12-03', 'blocked');
end $$;

-- ===== 1. Before 410: the defects, reproduced =====
-- Only on a database without 410 (affiliate_payout_save still production's
-- version of 9 Oct 2026); everything here is rolled back.
savepoint before410;
do $$
declare e text; v_row record;
begin
  if md5(pg_get_functiondef('public.affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)'::regprocedure))
     <> 'c7356c6021a35eb032a2375e798ace75' then
    raise notice 'SKIP  section 1: this database already has 410'; return; end if;
  perform pg_temp.as_user('owner');
  perform pg_temp.check(pg_temp.bal('r1', '2020-02-01') = -562.35 and pg_temp.bal('r1', pg_temp.cur()) = 7.08,
    'before 410: r1 stands at -562.35 for February and +7.08 for this month');
  e := pg_temp.refused(format('select public.record_affiliate_payout(%L, %L, 7.08, %L, public.sg_today(), null, null, gen_random_uuid())',
         pg_temp.fx('r1'), pg_temp.cur(), pg_temp.fx('cash')));
  perform pg_temp.check(e is null, 'before 410: the 7.08 is paid out while 562.35 is owed back (the defect)');
  perform pg_temp.check((select (x->>'unpaid')::numeric from jsonb_array_elements(public.affiliate_admin_directory()) x
                          where x->>'customer_id' = pg_temp.fx('r1')::text) = -555.27,
    'before 410: the Affiliates page shows Unpaid -555.27');
  perform pg_temp.cancel('i3');
  select c.invoice_paid_date, c.commission_amount into v_row from public.commissions c
   where c.adjusts_commission_id = pg_temp.fx('r2_c') and c.status = 'earned';
  perform pg_temp.check(v_row.invoice_paid_date = '2020-03-05' and v_row.commission_amount = -300,
    'before 410: the take-back is dated in the month already paid (2020-03-05)');
  perform pg_temp.check((select (x->>'blocked')::numeric from jsonb_array_elements(public.affiliate_admin_directory()) x
                          where x->>'customer_id' = pg_temp.fx('r7')::text) = 0,
    'before 410: the Affiliates page shows no blocked commission (the defect)');
  perform pg_temp.as_user('portal7');
  perform pg_temp.check((select bool_and(p->>'status' = 'reversed') from jsonb_array_elements(public.affiliate_portal_purchases()) p),
    'before 410: the portal calls withheld commission "Reversed" (the defect)');
end $$;
rollback to savepoint before410;
release savepoint before410;

-- ===== 2. Apply 410; a re-run changes nothing =====
-- 414 changes functions 410 checks (affiliate_month_balances, the overview,
-- the portal's earnings), so on a database that has 414, 410 is in already
-- and running it again refuses by design: this section is skipped there, and
-- the sections after it check 410's rules with 414 in place.
select to_regclass('public.affiliate_deduction_settlements') is null as t410_applies \gset
\if :t410_applies
\ir ../../../supabase/410_clawbacks_carried_forward_and_therapy_status_refresh.sql
create temp table t410_after as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5,
         coalesce(array_to_string(p.proacl, ','), '') as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace;
\ir ../../../supabase/410_clawbacks_carried_forward_and_therapy_status_refresh.sql
do $$
begin
  perform pg_temp.check(not exists (
      select fn, md5, acl from t410_after
      except select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)), coalesce(array_to_string(p.proacl, ','), '')
               from pg_proc p where p.pronamespace = 'public'::regnamespace)
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace) = (select count(*) from t410_after),
    '2: a second run of 410 changes no function or grant');
  perform pg_temp.check((select count(*) from cron.job where jobname = 'therapy-status-refresh') = 1,
    '2: the nightly job is there once after two runs');
  perform pg_temp.check(not has_function_privilege('authenticated', 'public.affiliate_referrer_balances()', 'execute')
    and not has_function_privilege('anon', 'public.affiliate_referrer_balances()', 'execute')
    and has_function_privilege('service_role', 'public.affiliate_referrer_balances()', 'execute'),
    '2: affiliate_referrer_balances is the service role''s alone');
end $$;
-- Another version of a function it changes, and of one it relies on: each
-- run refuses, naming it (psql prints the two refusals as ERROR lines; they
-- are expected and checked below).
savepoint t410_guard;
create or replace function public.affiliate_portal_purchases() returns jsonb language sql stable security definer
  set search_path = public as $f$ select '[]'::jsonb $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/410_clawbacks_carried_forward_and_therapy_status_refresh.sql
\set ON_ERROR_STOP on
rollback to savepoint t410_guard;
release savepoint t410_guard;
select set_config('t410.refused_changed', :'LAST_ERROR_MESSAGE', true) as t410_kept \gset
savepoint t410_guard2;
create or replace function public.commission_unpaid_amount(p_commission_id uuid) returns numeric language sql stable
  security definer set search_path = public as $f$ select 0::numeric $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/410_clawbacks_carried_forward_and_therapy_status_refresh.sql
\set ON_ERROR_STOP on
rollback to savepoint t410_guard2;
release savepoint t410_guard2;
select set_config('t410.refused_relied', :'LAST_ERROR_MESSAGE', true) as t410_kept \gset
do $$
begin
  perform pg_temp.check(current_setting('t410.refused_changed') like '%public.affiliate_portal_purchases() is not the version%',
    '2: a changed function at another version refuses: ' || current_setting('t410.refused_changed'));
  perform pg_temp.check(current_setting('t410.refused_relied') like '%commission_unpaid_amount(uuid) is missing or not the version%',
    '2: a relied-on function at another version refuses: ' || current_setting('t410.refused_relied'));
end $$;
\else
\echo 'SKIP  section 2: this database has 414 (410 is in; its re-run refuses there by design)'
\endif

-- ===== 3. The production case: nothing paid while a deduction is owed =====
do $$
declare e text; g jsonb; x jsonb;
begin
  perform pg_temp.as_user('owner');
  select to_jsonb(b) into x from public.affiliate_referrer_balances() b where b.referrer = pg_temp.fx('r1');
  perform pg_temp.check((x->>'owed')::numeric = -555.27 and (x->>'unpaid')::numeric = 0
                        and (x->>'deduction')::numeric = 555.27 and (x->>'payable')::numeric = 0,
    '3: r1 nets to -555.27: unpaid 0, deduction 555.27, payable 0, got ' || x::text);
  g := pg_temp.group_of('r1', pg_temp.cur());
  perform pg_temp.check((g->>'balance')::numeric = 7.08 and (g->>'payable')::numeric = 0
                        and (g->>'referrer_deduction')::numeric = 555.27 and (g->>'referrer_payable')::numeric = 0
                        and (g->>'referrer_owed')::numeric = -555.27,
    '3: this month shows its 7.08 balance but nothing payable, and the deduction carried, got ' || g::text);
  g := pg_temp.group_of('r1', '2020-02-01');
  perform pg_temp.check((g->>'balance')::numeric = -562.35 and (g->>'payable')::numeric = 0
                        and g ? 'earned' and g ? 'adjustments' and g ? 'paid' and g ? 'tier1' and g ? 'tier2' and g ? 'review_reason',
    '3: February keeps every key it had, and nothing payable');
  x := pg_temp.ref_row('r1');
  perform pg_temp.check((x->>'deduction')::numeric = 555.27 and (x->>'payable')::numeric = 0,
    '3: the overview lists r1 among the affiliates with its deduction');
  e := pg_temp.refused(format('select public.record_affiliate_payout(%L, %L, 7.08, %L, public.sg_today(), null, null, gen_random_uuid())',
         pg_temp.fx('r1'), pg_temp.cur(), pg_temp.fx('cash')));
  perform pg_temp.check(e like 'This affiliate still owes S$555.27 back%',
    '3: Record payout for this month''s 7.08 is refused, naming the 555.27 owed: ' || coalesce(e, 'accepted'));
  x := (select y from jsonb_array_elements(public.affiliate_admin_directory()) y where y->>'customer_id' = pg_temp.fx('r1')::text);
  perform pg_temp.check((x->>'unpaid')::numeric = 0 and (x->>'deduction')::numeric = 555.27,
    '3: the Affiliates page shows Unpaid 0.00 and a deduction of 555.27, got ' || (x - 'name')::text);
  perform pg_temp.check((select unpaid_earned from public.referrer_list() where customer_id = pg_temp.fx('r1')) = -555.27,
    '3: the Referrers tab still reads the signed figure (the page shows it as a deduction)');
  perform pg_temp.as_user('portal');
  x := public.affiliate_portal_earnings()->'summary';
  perform pg_temp.check((x->>'unpaid')::numeric = 0 and (x->>'deduction')::numeric = 555.27
                        and (x->>'lifetime')::numeric = 444.73 and (x->>'paid')::numeric = 1000,
    '3: the portal shows Unpaid 0.00 and "Deduction to be recovered" 555.27, got ' || x::text);
  perform pg_temp.check((public.affiliate_portal_dashboard()->'earnings'->>'deduction')::numeric = 555.27,
    '3: the portal dashboard carries the deduction too');
end $$;

-- ===== 4. Later commission recovers it; then only the rest is payable =====
do $$
declare e text; g jsonb;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.commission('r1', 'i2', 600, public.sg_today());
  g := pg_temp.group_of('r1', pg_temp.cur());
  perform pg_temp.check((g->>'balance')::numeric = 607.08 and (g->>'payable')::numeric = 44.73
                        and (g->>'referrer_deduction')::numeric = 0,
    '4: 600 more this month: 44.73 payable (607.08 less the 562.35 owed), got ' || g::text);
  e := pg_temp.refused(format('select public.record_affiliate_payout(%L, %L, 44.74, %L, public.sg_today(), null, null, gen_random_uuid())',
         pg_temp.fx('r1'), pg_temp.cur(), pg_temp.fx('cash')));
  perform pg_temp.check(e like 'Amount exceeds what this affiliate can be paid now once all their months are counted, S$44.73.%',
    '4: one cent more than 44.73 is refused: ' || coalesce(e, 'accepted'));
  perform pg_temp.pay('r1', pg_temp.cur(), 44.73);
  perform pg_temp.check((select owed = 0 and payable = 0 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('r1')),
    '4: 44.73 is paid; r1 now nets to 0');
  perform pg_temp.check((pg_temp.group_of('r1', pg_temp.cur())->>'payable')::numeric = 0
                        and pg_temp.bal('r1', pg_temp.cur()) = 562.35,
    '4: this month still shows 562.35 of balance, none of it payable (it covers February''s take-back)');
end $$;

-- ===== 5. A new take-back of commission paid out in full is dated today =====
do $$
declare n int; v_on date; v_amt numeric; v_line numeric; v_why text;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.cancel('i3');
  select count(*), min(c.invoice_paid_date), sum(c.commission_amount), min(c.reversal_reason), sum(c.line_amount)
    into n, v_on, v_amt, v_why, v_line
    from public.commissions c where c.adjusts_commission_id = pg_temp.fx('r2_c') and c.status = 'earned';
  perform pg_temp.check(n = 1 and v_on = public.sg_today() and v_amt = -300
                        and v_line = -3000 and v_why = 'Future payout adjustment: T410 cancelled',
    '5: one take-back of -300, dated today, reason "Future payout adjustment"');
  perform pg_temp.check(pg_temp.bal('r2', '2020-03-01') = 0 and pg_temp.bal('r2', pg_temp.cur()) = -300,
    '5: March stays as paid (0); the 300 is owed back in this month');
  perform pg_temp.check((select deduction = 300 and payable = 0 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('r2')),
    '5: r2''s deduction is 300');
  -- Recalculated again (a later correction): the take-back is written afresh,
  -- still once and still today.
  perform public.reconcile_invoice_commissions(pg_temp.fx('i3'), 'T410 again');
  perform pg_temp.check((select count(*) = 1 and sum(commission_amount) = -300 and min(invoice_paid_date) = public.sg_today()
                           from public.commissions where adjusts_commission_id = pg_temp.fx('r2_c') and status = 'earned'),
    '5: run again, the take-back is still one row of -300 dated today');
  perform pg_temp.check((select owed = -300 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('r2')),
    '5: and r2 still owes 300');
end $$;

-- ===== 6. Paid out in part: the paid part today, the rest in its own month =====
do $$
declare v_today record; v_own record;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.cancel('i5');
  select c.commission_amount, c.line_amount, c.invoice_paid_date, c.reversal_reason into v_today
    from public.commissions c where c.adjusts_commission_id = pg_temp.fx('r3_c') and c.status = 'earned'
     and c.reversal_reason like 'Future payout adjustment%';
  select c.commission_amount, c.line_amount, c.invoice_paid_date, c.reversal_reason into v_own
    from public.commissions c where c.adjusts_commission_id = pg_temp.fx('r3_c') and c.status = 'earned'
     and c.reversal_reason like 'Unpaid commission cancelled%';
  perform pg_temp.check(v_today.commission_amount = -60 and v_today.line_amount = -600 and v_today.invoice_paid_date = public.sg_today(),
    '6: the 60 paid out is taken back today');
  perform pg_temp.check(v_own.commission_amount = -40 and v_own.line_amount = -400 and v_own.invoice_paid_date = '2020-04-03'
                        and v_own.reversal_reason = 'Unpaid commission cancelled: T410 cancelled',
    '6: the 40 never paid out is cancelled in April');
  perform pg_temp.check((select count(*) from public.commissions where adjusts_commission_id = pg_temp.fx('r3_c') and status = 'earned') = 2,
    '6: two rows, together the whole 100');
  perform pg_temp.check(pg_temp.bal('r3', '2020-04-01') = 0 and pg_temp.bal('r3', pg_temp.cur()) = -60,
    '6: April shows 0, not 40 owed; this month shows the 60 owed back');
  perform pg_temp.check((select deduction = 60 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('r3')),
    '6: r3''s deduction is 60, what was paid out');
  perform pg_temp.check(public.commission_unpaid_amount(pg_temp.fx('r3_c')) = -60,
    '6: the row itself is now 60 over-paid (it is never paid again)');
end $$;

-- ===== 7. A payout raised while a deduction is owed; lowered is allowed =====
do $$
declare e text;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.cancel('i7');
  perform pg_temp.check((select owed = -50 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('r4')),
    '7: r4 nets to -50 (May 100 unpaid, June''s 150 owed back)');
  e := pg_temp.refused(format('select public.correct_affiliate_payout(%L, 1, 150, %L, public.sg_today(), null, null, %L, gen_random_uuid())',
         pg_temp.fx('r4_p'), pg_temp.fx('cash'), 'T410 raise'));
  perform pg_temp.check(e like 'This affiliate still owes S$50.00 back%',
    '7: raising May''s payout from 100 to 150 is refused: ' || coalesce(e, 'accepted'));
  e := pg_temp.refused(format('select public.record_affiliate_payout(%L, %L, 10, %L, public.sg_today(), null, null, gen_random_uuid())',
         pg_temp.fx('r4'), '2020-05-01', pg_temp.fx('cash')));
  perform pg_temp.check(e like 'This affiliate still owes S$50.00 back%',
    '7: a new payout for May is refused too: ' || coalesce(e, 'accepted'));
  perform public.correct_affiliate_payout(pg_temp.fx('r4_p'), 1, 80, pg_temp.fx('cash'), public.sg_today(), null, null,
                                          'T410 lower', gen_random_uuid());
  perform pg_temp.check((select owed = -30 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('r4')),
    '7: lowering it to 80 is allowed; r4 then owes 30');
end $$;

-- ===== 8. A month under review counts only when negative =====
do $$
declare e text;
begin
  perform pg_temp.as_user('owner');
  update public.commission_payouts set allocation_state = 'review' where id = pg_temp.fx('r5_p');
  perform pg_temp.check((select owed = 130 and unpaid = 130 and payable = 100 from public.affiliate_referrer_balances()
                          where referrer = pg_temp.fx('r5')),
    '8: r5 is owed 130, of which 100 is payable (August''s 30 is under review)');
  perform pg_temp.check((pg_temp.group_of('r5', '2020-07-01')->>'payable')::numeric = 100
                        and (pg_temp.group_of('r5', '2020-08-01')->>'payable')::numeric = 0,
    '8: July shows 100 payable, August none');
  perform pg_temp.pay('r5', '2020-07-01', 100);
  perform pg_temp.check((select payable = 0 and owed = 30 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('r5')),
    '8: July paid; the 30 under review stays owed, not payable');
end $$;

-- ===== 9. What is payable is shown against the oldest months first =====
do $$
declare e text;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.cancel('i12');
  perform pg_temp.check((select owed = 40 and payable = 40 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('r6')),
    '9: r6 nets to 40 (30 + 60, less the 50 owed back)');
  perform pg_temp.check((pg_temp.group_of('r6', '2020-09-01')->>'payable')::numeric = 30
                        and (pg_temp.group_of('r6', '2020-10-01')->>'payable')::numeric = 10
                        and (pg_temp.group_of('r6', pg_temp.cur())->>'payable')::numeric = 0,
    '9: September 30, October 10, this month none: they add up to the 40');
  e := pg_temp.refused(format('select public.record_affiliate_payout(%L, %L, 40.01, %L, public.sg_today(), null, null, gen_random_uuid())',
         pg_temp.fx('r6'), '2020-10-01', pg_temp.fx('cash')));
  perform pg_temp.check(e like 'Amount exceeds what this affiliate can be paid now%S$40.00.%',
    '9: October may take up to the 40 the affiliate nets to, not its own 60: ' || coalesce(e, 'accepted'));
  perform pg_temp.pay('r6', '2020-10-01', 40);
  perform pg_temp.check((pg_temp.group_of('r6', '2020-09-01')->>'payable')::numeric = 0
                        and (select payable = 0 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('r6')),
    '9: paid against October, September then shows none payable');
  -- Remaining payable: the months' payable add up to the affiliates'.
  perform pg_temp.check((select sum((g->>'payable')::numeric) from jsonb_array_elements(public.affiliate_payout_overview()->'groups') g)
                        = (select sum((x->>'payable')::numeric) from jsonb_array_elements(public.affiliate_payout_overview()->'referrers') x),
    '9: every month''s payable adds up to the affiliates'' payable');
end $$;

-- ===== 10. Blocked commission is counted and shown as blocked (AFFILIATES-3) =====
do $$
declare x jsonb;
begin
  perform pg_temp.as_user('owner');
  x := (select y from jsonb_array_elements(public.affiliate_admin_directory()) y where y->>'customer_id' = pg_temp.fx('r7')::text);
  perform pg_temp.check((x->>'blocked')::numeric = 69.87 and (x->>'unpaid')::numeric = 0,
    '10: the Affiliates page shows 69.87 blocked');
  perform pg_temp.check((select blocked from public.report_affiliates() where customer_id = pg_temp.fx('r7')) = 69.87,
    '10: and agrees with the Reports page');
  perform pg_temp.as_user('portal7');
  perform pg_temp.check((public.affiliate_portal_earnings()->'summary'->>'blocked')::numeric = 69.87,
    '10: the portal shows 69.87 blocked');
  perform pg_temp.check((select count(*) = 1 and bool_and(p->>'status' = 'blocked')
                           from jsonb_array_elements(public.affiliate_portal_purchases()) p),
    '10: the portal lists the purchase as Blocked, not Reversed');
  perform pg_temp.as_user('portal');
  perform pg_temp.check((select bool_and(p->>'status' <> 'blocked') from jsonb_array_elements(public.affiliate_portal_purchases()) p),
    '10: an affiliate with earned and taken-back commission has no Blocked purchase');
end $$;

-- ===== Sales paid through the till: a part refund and a sale worked out again =====
-- Real invoices from here on (create_invoice, record_invoice_payment,
-- refund_invoice_recorded): 3 units at S$100.00, 15% commission = 45.00,
-- paid two months ago and paid out in full.
do $$
declare v uuid; k text; n int := 30; v_inv uuid; v_aff uuid; pm date := (pg_temp.cur() - interval '2 months')::date;
begin
  perform pg_temp.as_user('owner');
  update public.app_settings set commission_tier1_own_rate = 15 where id = true;
  insert into public.products(name, sku, product_type) values ('T410 Product', 'T410-P', 'own') returning id into v;
  insert into fx values ('product', v);
  insert into public.store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('store'), v, 100);
  perform public.set_product_prices(pg_temp.fx('store'), v, 100, 100, 'available');
  foreach k in array array['r11','r13','r14'] loop
    n := n + 1;
    insert into public.customers(full_name, phone) values ('T410 Affiliate ' || upper(k), '+65914001' || n::text)
      returning id into v;
    insert into fx values (k, v);
    insert into public.customer_affiliates(customer_id, store_id, status, activated_at)
      values (v, pg_temp.fx('store'), 'active', now()) returning id into v_aff;
    insert into fx values (k || '_aff', v_aff);
  end loop;
  v_inv := public.create_invoice(pg_temp.fx('store'), pg_temp.fx('buyer'), pg_temp.fx('r11_aff'),
             jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('product'), 'quantity', 3)));
  insert into fx values ('s1', v_inv);
  perform public.record_invoice_payment(v_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 300)),
                                        gen_random_uuid());
  update public.invoices set paid_at = (pm + 9)::timestamp at time zone 'Asia/Singapore' where id = v_inv;
  update public.commissions set invoice_paid_date = pm + 9 where invoice_id = v_inv;
  select id into v from public.commissions where invoice_id = v_inv and referrer_customer_id = pg_temp.fx('r11') and status = 'earned';
  insert into fx values ('s1_c', v);
  perform pg_temp.pay('r11', pm, 45);
  perform pg_temp.check((select status::text from public.commissions where id = pg_temp.fx('s1_c')) = 'paid'
                        and pg_temp.bal('r11', pm) = 0, 'fixture: the 45.00 paid out in full two months ago');
end $$;

-- ===== 11. A part refund of a sale already paid out keeps the paid month as paid =====
do $$
declare pm date := (pg_temp.cur() - interval '2 months')::date; v_item uuid; v_pay uuid; v_mov uuid; v_new uuid; r record;
begin
  perform pg_temp.as_user('owner');
  select id into v_item from public.invoice_items where invoice_id = pg_temp.fx('s1');
  select id into v_pay from public.invoice_payments where invoice_id = pg_temp.fx('s1');
  select id into v_mov from public.stock_movements where invoice_id = pg_temp.fx('s1') and movement_type = 'store_sale';
  perform public.refund_invoice_recorded(pg_temp.fx('s1'),
    jsonb_build_array(jsonb_build_object('invoice_item_id', v_item, 'amount', 100)),
    jsonb_build_array(jsonb_build_object('payment_id', v_pay, 'amount', 100)),
    jsonb_build_array(jsonb_build_object('movement_id', v_mov, 'sellable_quantity', 1)), 'T410 one unit back', gen_random_uuid());
  perform pg_temp.check(pg_temp.bal('r11', pm) = 0 and pg_temp.bal('r11', pg_temp.cur()) = -15,
    format('11: one unit refunded this month: the month paid stays 0, this month owes 15 back (before the fix +30 / -45), got %s / %s',
           pg_temp.bal('r11', pm), pg_temp.bal('r11', pg_temp.cur())));
  select c.id, c.commission_amount into r from public.commissions c
   where c.invoice_id = pg_temp.fx('s1') and c.referrer_customer_id = pg_temp.fx('r11') and c.status = 'earned'
     and c.adjusts_commission_id is null and c.commission_amount > 0;
  v_new := r.id;
  perform pg_temp.check(r.commission_amount = 30, '11: the sale earns 30.00 again for the two units kept');
  perform pg_temp.check((select count(*) = 1 and sum(commission_amount) = -30 and min(invoice_paid_date) = pm + 9
                                and min(reversal_reason) like 'Already paid out on this sale: %'
                           from public.commissions where adjusts_commission_id = v_new and status = 'earned'),
    '11: that 30.00 is netted against what was paid out, linked to it and in its own month');
  perform pg_temp.check(public.commission_unpaid_amount(v_new) = 0,
    '11: so the 30.00 earned again can never be paid a second time');
  perform pg_temp.check((select count(*) = 1 and sum(commission_amount) = -15 and min(invoice_paid_date) = public.sg_today()
                           from public.commissions where adjusts_commission_id = pg_temp.fx('s1_c') and status = 'earned'
                            and reversal_reason like 'Future payout adjustment%'),
    '11: the 15.00 no longer earned is taken back today');
  perform pg_temp.check((pg_temp.group_of('r11', pm)->>'payable')::numeric = 0
                        and (select deduction = 15 and payable = 0 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('r11')),
    '11: nothing payable for the month already paid; r11 owes 15 back');
  perform public.reconcile_invoice_commissions(pg_temp.fx('s1'), 'T410 worked out again');
  perform pg_temp.check(pg_temp.bal('r11', pm) = 0 and pg_temp.bal('r11', pg_temp.cur()) = -15
                        and (select count(*) from public.commissions where invoice_id = pg_temp.fx('s1') and status = 'earned') = 3,
    '11: worked out again the same day: the same three rows, the same months');
end $$;

-- ===== 13. The refund undone: the take-back stays, the commission is owed in its month =====
-- adjust_invoice_line_commission_refunds is what scales the commission earned
-- again down for the refund; stubbed out here (rolled back) it is as if the
-- refund were undone, so the sale earns the whole 45.00 again.
savepoint t410_undone;
create or replace function public.adjust_invoice_line_commission_refunds(p_invoice_id uuid, p_previous_ids uuid[])
  returns void language sql security definer set search_path = public as $f$ select null::void $f$;
do $$
declare pm date := (pg_temp.cur() - interval '2 months')::date;
begin
  perform pg_temp.as_user('owner');
  perform public.reconcile_invoice_commissions(pg_temp.fx('s1'), 'T410 refund undone');
  perform pg_temp.check((select sum(commission_amount) = -15 and min(invoice_paid_date) = public.sg_today()
                           from public.commissions where adjusts_commission_id = pg_temp.fx('s1_c') and status = 'earned'
                            and reversal_reason like 'Future payout adjustment%'),
    '13: the 15.00 taken back this month stays as it was');
  perform pg_temp.check(pg_temp.bal('r11', pm) = 15 and pg_temp.bal('r11', pg_temp.cur()) = -15,
    format('13: the 15.00 earned again is owed in the sale''s own month; got %s / %s', pg_temp.bal('r11', pm), pg_temp.bal('r11', pg_temp.cur())));
  perform pg_temp.check((select owed = 0 and payable = 0 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('r11')),
    '13: r11 nets to 0: nothing owed either way');
end $$;
rollback to savepoint t410_undone;
release savepoint t410_undone;

-- ===== 14. A take-back written whole before 410, of a row paid out in part =====
-- As INV-2026-0292 on 3 Oct 2026: 100 earned, 60 paid out, -100 taken back in
-- the row's own month. Worked out again, its month stays as it is.
do $$
declare v uuid; n_today int;
begin
  perform pg_temp.as_user('owner');
  insert into public.customers(full_name, phone) values ('T410 Affiliate R12', '+6591400140') returning id into v;
  insert into fx values ('r12', v);
  insert into public.customer_affiliates(customer_id, store_id, status, activated_at) values (v, pg_temp.fx('store'), 'active', now());
  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status)
    values ('T410-I14', pg_temp.fx('store'), pg_temp.fx('buyer'), pg_temp.fx('owner'), 'paid') returning id into v;
  insert into fx values ('i14', v);
  insert into fx values ('r12_c', pg_temp.commission('r12', 'i14', 100, '2020-01-10'));
  perform pg_temp.pay('r12', '2020-01-01', 60);
  insert into public.commissions(invoice_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount,
                                 rate, commission_amount, invoice_paid_date, status, adjusts_commission_id, reversal_reason)
    values (pg_temp.fx('i14'), pg_temp.fx('buyer'), pg_temp.fx('r12'), 'tier1', 'own', -1000, 10, -100,
            '2020-01-10', 'earned', pg_temp.fx('r12_c'), 'Future payout adjustment: T410 fixture');
  perform pg_temp.check(pg_temp.bal('r12', '2020-01-01') = -60, 'fixture: January stands at -60 (100 - 100 - 60 paid)');
  perform pg_temp.cancel('i14');
  select count(*) into n_today from public.commissions where invoice_id = pg_temp.fx('i14') and status = 'earned'
     and invoice_paid_date >= pg_temp.cur();
  perform pg_temp.check(pg_temp.bal('r12', '2020-01-01') = -60 and n_today = 0,
    '14: January still -60 and nothing dated this month');
  perform pg_temp.check((select sum(commission_amount) filter (where reversal_reason like 'Future payout adjustment%') = -60
                                and sum(commission_amount) filter (where reversal_reason like 'Unpaid commission cancelled%') = -40
                           from public.commissions where adjusts_commission_id = pg_temp.fx('r12_c') and status = 'earned'),
    '14: written as the 60 paid out (kept in January) and the 40 never paid out (cancelled there)');
end $$;

-- ===== 15. A sale given to another affiliate, both paid out (3 Oct 2026) =====
-- The new affiliate's commission was paid out too. Worked out again, nothing
-- of theirs is taken back, and the old affiliate's take-back keeps its month.
do $$
declare p2 date := (pg_temp.cur() - interval '3 months')::date; v_inv uuid; v uuid;
begin
  perform pg_temp.as_user('owner');
  v_inv := public.create_invoice(pg_temp.fx('store'), pg_temp.fx('buyer'), pg_temp.fx('r14_aff'),
             jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('product'), 'quantity', 2)));
  insert into fx values ('s2', v_inv);
  perform public.record_invoice_payment(v_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 200)),
                                        gen_random_uuid());
  update public.invoices set paid_at = (p2 + 14)::timestamp at time zone 'Asia/Singapore' where id = v_inv;
  update public.commissions set invoice_paid_date = p2 + 14 where invoice_id = v_inv;
  -- the old affiliate's row, paid out, and its take-back as 3 Oct wrote it
  insert into fx values ('r13_c', pg_temp.commission('r13', 's2', 30, p2 + 14));
  perform pg_temp.pay('r13', p2, 30);
  insert into public.commissions(invoice_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount,
                                 rate, commission_amount, invoice_paid_date, status, adjusts_commission_id, reversal_reason)
    values (v_inv, pg_temp.fx('buyer'), pg_temp.fx('r13'), 'tier1', 'own', -300, 10, -30,
            p2 + 14, 'earned', pg_temp.fx('r13_c'), 'Future payout adjustment: Affiliate changed');
  perform pg_temp.pay('r14', p2, 30);
  perform pg_temp.check(pg_temp.bal('r14', p2) = 0 and pg_temp.bal('r13', p2) = -30,
    'fixture: the new affiliate paid 30 for the month, the old one at -30 there');
  perform public.reconcile_invoice_commissions(v_inv, 'T410 payment corrected');
  perform pg_temp.check(pg_temp.bal('r14', p2) = 0 and pg_temp.bal('r14', pg_temp.cur()) = 0,
    format('15: the new affiliate''s paid month stays 0 and nothing is taken back today (before the fix +30 / -30), got %s / %s',
           pg_temp.bal('r14', p2), pg_temp.bal('r14', pg_temp.cur())));
  perform pg_temp.check(pg_temp.bal('r13', p2) = -30 and pg_temp.bal('r13', pg_temp.cur()) = 0,
    '15: the old affiliate''s take-back keeps its month');
end $$;

-- ===== 16. A payout lowered after its take-back: the take-back follows =====
do $$
declare v_p uuid; v_ver int;
begin
  perform pg_temp.as_user('owner');
  select id, version into v_p, v_ver from public.commission_payouts where referrer_customer_id = pg_temp.fx('r3') and status = 'paid';
  perform public.correct_affiliate_payout(v_p, v_ver, 50, pg_temp.fx('cash'), public.sg_today(), null, null,
                                          'T410 paid 50, not 60', gen_random_uuid());
  perform public.reconcile_invoice_commissions(pg_temp.fx('i5'), 'T410 again');
  perform pg_temp.check(pg_temp.bal('r3', '2020-04-01') = 0 and pg_temp.bal('r3', pg_temp.cur()) = -50,
    format('16: April stays 0; what is owed back this month follows the payout down to 50, got %s / %s',
           pg_temp.bal('r3', '2020-04-01'), pg_temp.bal('r3', pg_temp.cur())));
  perform pg_temp.check((select min(invoice_paid_date) = public.sg_today() from public.commissions
                          where adjusts_commission_id = pg_temp.fx('r3_c') and status = 'earned'
                            and reversal_reason like 'Future payout adjustment%'),
    '16: still dated the day it was first written');
end $$;

-- ===== 12. Worked out again in a later month: nothing moves =====
-- Last, because sg_today() is moved to the 5th of next month (rolled back).
do $$
declare pm date := (pg_temp.cur() - interval '2 months')::date; v_cur date := pg_temp.cur(); v_inv uuid; g jsonb; v_first date;
begin
  perform pg_temp.as_user('owner');
  -- this month: 4 more units for r11 (60.00), and what the overview offers is paid
  v_inv := public.create_invoice(pg_temp.fx('store'), pg_temp.fx('buyer'), pg_temp.fx('r11_aff'),
             jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('product'), 'quantity', 4)));
  perform public.record_invoice_payment(v_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 400)),
                                        gen_random_uuid());
  perform pg_temp.check((pg_temp.group_of('r11', pm)->>'payable')::numeric = 0
                        and (pg_temp.group_of('r11', pg_temp.cur())->>'payable')::numeric = 45,
    '12: offered: nothing for the month already paid, 45.00 this month (60 less the 15 owed back)');
  for g in select x from jsonb_array_elements(public.affiliate_payout_overview()->'groups') x
            where x->>'referrer' = pg_temp.fx('r11')::text and (x->>'payable')::numeric > 0 loop
    perform pg_temp.pay('r11', (g->>'month')::date, (g->>'payable')::numeric);
  end loop;
  select min(invoice_paid_date) into v_first from public.commissions
   where adjusts_commission_id = pg_temp.fx('s1_c') and status = 'earned' and reversal_reason like 'Future payout adjustment%';
  execute $f$create or replace function public.sg_today() returns date language sql stable as
    $q$ select (date_trunc('month', (now() at time zone 'Asia/Singapore')) + interval '1 month 4 days')::date $q$ $f$;
  perform public.reconcile_invoice_commissions(pg_temp.fx('s1'), 'T410 payment method corrected next month');
  perform pg_temp.check(pg_temp.cur() = (v_cur + interval '1 month')::date, '12: (today is now next month)');
  perform pg_temp.check(pg_temp.bal('r11', pm) = 0 and pg_temp.bal('r11', v_cur) = 0
                        and pg_temp.bal('r11', (v_cur + interval '1 month')::date) = 0,
    format('12: next month, worked out again: every month stays 0 (before the fix +30 / +45 / -75), got %s / %s / %s',
           pg_temp.bal('r11', pm), pg_temp.bal('r11', v_cur), pg_temp.bal('r11', (v_cur + interval '1 month')::date)));
  perform pg_temp.check((select min(invoice_paid_date) = v_first and max(invoice_paid_date) = v_first from public.commissions
                          where adjusts_commission_id = pg_temp.fx('s1_c') and status = 'earned'
                            and reversal_reason like 'Future payout adjustment%'),
    '12: the take-back keeps the day it was first written');
  perform pg_temp.check((select count(*) from public.commissions where invoice_id = pg_temp.fx('s1') and status = 'paid') = 1,
    '12: and no commission earned again was paid out (nothing to take back twice)');
end $$;

rollback;
