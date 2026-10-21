-- 425: the affiliate lists in one pass, Tier 1 and Tier 2 only, the portal
-- keeps staff notes, and the legacy affiliate objects go (AFFILIATES-5, -13,
-- -4, -11, -15, and the server parts of -M2 and -10).
--
--   A  Before 425, as an Owner and as the affiliate, every figure the pages
--      read is saved: commission_reporting_rows, the Affiliates page's
--      directory, affiliate_directory, the Reports affiliate report, the
--      Referrers tab, one referrer's downline, and the portal's earnings,
--      dashboard and payouts.
--   M  425 installs twice; the second run changes nothing.
--   S  The same answers: commission_reporting_rows, both directories and the
--      report are identical, row for row.
--   P  One pass: each list reads commission_reporting_rows once (the report
--      twice: itself and the directory it builds on), and the balances once.
--   T  Two tiers: the downline stops at Tier 2, its count on the Referrers tab
--      too; a paid invoice's spend is less its refund; a deleted referrer is
--      left out unless they still owe money back. A login whose invitation is
--      pending is refused the downline, the Affiliates page directory, the
--      Referrers tab and the report (406); so is an affiliate login, and
--      staff still get no rows.
--   R  Recent Activity holds the 10 newest purchases (the fixture has 13).
--   E  The earnings are as before, without by_customer.
--   O  The portal's payouts carry no reference, method or notes.
--   C  A change of commission rates audits the rates before it; a pending
--      invitee is refused, as for the staff directory.
--   L  The legacy tables and create_commission_payout are gone.
--   G  Grants: the changed functions keep theirs; the new ones are for
--      signed-in logins only; the new table is closed to client roles.
--
-- Disposable database only; everything is rolled back. It needs a database
-- without 425 (section A reads every figure before it; A0 says so otherwise).
-- Run with the migration's path (and, on a database without 424, a prelude
-- that installs it):
--   psql -X -v ON_ERROR_STOP=1 -v mig=supabase/425_affiliates_directory_portal_and_cleanup.sql \
--        [-v prelude=supabase/424_exchanges_and_promotions.sql] -f scripts/commissions/tests/affiliates-425.sql
-- Every name, phone and email is invented (T425, ACMA fictional +614915xxxxx
-- numbers, @example.com).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local track_functions = 'all';
\if :{?prelude}
\i :prelude
\endif

create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create temp table snap(k text primary key, v jsonb);
create function pg_temp.snap(key text) returns jsonb language sql as $$ select v from snap where k = key $$;
-- Signed in as one of the fixture's logins (role authenticated), or as the
-- server (no request).
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true),
          set_config('request.jwt.claim.role', case when key is null then '' else 'authenticated' end, true) $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlstate || ' ' || sqlerrm; end$$;
-- How many times a function was called in this transaction so far.
create function pg_temp.calls(fn text) returns bigint language sql as
$$ select coalesce(pg_stat_get_xact_function_calls(to_regprocedure('public.' || fn)), 0) $$;
-- What every page reads, saved under prefix.
create function pg_temp.save_all(prefix text) returns void language plpgsql as
$$begin
  perform pg_temp.as_user('own');
  insert into snap values
    (prefix || 'crr', (select jsonb_agg(to_jsonb(r) order by r.id, r.status::text, r.commission_amount) from public.commission_reporting_rows() r)),
    (prefix || 'admin', public.affiliate_admin_directory()),
    (prefix || 'dir', (select jsonb_agg(to_jsonb(d) order by d.customer_id) from public.affiliate_directory() d)),
    (prefix || 'rep', (select jsonb_agg(to_jsonb(d) order by d.customer_id) from public.report_affiliates() d)),
    (prefix || 'list', (select jsonb_agg(to_jsonb(d) order by d.customer_id) from public.referrer_list() d)),
    (prefix || 'dl', (select jsonb_agg(to_jsonb(d) order by d.depth, d.full_name) from public.referrer_downline(pg_temp.fx('r1')) d));
  perform pg_temp.as_user('aff');
  insert into snap values
    (prefix || 'earn', public.affiliate_portal_earnings()),
    (prefix || 'dash', public.affiliate_portal_dashboard()),
    (prefix || 'pay', public.affiliate_portal_payouts());
  perform pg_temp.as_user(null);
end$$;

-- ═════ Fixtures (triggers off while they are written: invented history) ═════
do $$
declare k text; i int; v uuid; inv uuid; c uuid; p1 uuid; p3 uuid;
begin
  set local session_replication_role = replica;
  foreach k in array array['own', 'mgr', 'adm', 'stf', 'pend', 'aff'] loop
    insert into fx values (k, gen_random_uuid());
    insert into auth.users(id, email) values (pg_temp.fx(k), 't425-' || k || '@example.com');
  end loop;
  insert into public.profiles(id, full_name, email, role, is_active, invitation_status) values
    (pg_temp.fx('own'), 'T425 Owner', 't425-own@example.com', 'owner', true, 'accepted'),
    (pg_temp.fx('mgr'), 'T425 Manager', 't425-mgr@example.com', 'manager', true, 'accepted'),
    (pg_temp.fx('adm'), 'T425 Admin', 't425-adm@example.com', 'admin', true, 'accepted'),
    (pg_temp.fx('stf'), 'T425 Staff', 't425-stf@example.com', 'staff', true, 'accepted'),
    (pg_temp.fx('pend'), 'T425 Pending', 't425-pend@example.com', 'owner', true, 'pending');
  insert into fx values ('st', gen_random_uuid());
  insert into public.stores(id, name, code, country_code) values (pg_temp.fx('st'), 'T425 Store', 'T425', 'SG');
  insert into public.app_settings(id) values (true) on conflict (id) do nothing;
  update public.app_settings set commission_tier1_own_rate = 15, commission_tier1_third_rate = 4.5,
         commission_tier2_own_rate = 35, commission_tier2_third_rate = 35 where id = true;

  -- Referrers and the chain: R1 > A1 > B1 > C1 > D1 (Tier 1 to 4), R1 > A2
  -- (deleted), A1 > B2; R3 (deleted, owes S$15 back) > X2; R4 (deleted,
  -- nothing owed) > X1.
  insert into fx select key, gen_random_uuid() from (values ('r1'),('r2'),('r3'),('r4'),('r5'),('a1'),('a2'),('b1'),('b2'),('c1'),('d1'),('x1'),('x2')) t(key);
  insert into public.customers(id, full_name, phone, referred_by, referred_at, created_at)
  select pg_temp.fx(key), name, phone, pg_temp.fx(parent), case when parent is not null then now() - interval '60 days' end,
         now() - interval '90 days' + (n || ' minutes')::interval
    from (values
      ('r1', 'T425 Ria Aff', '+61491570006', null, 1), ('r2', 'T425 Rob Aff', '+61491570156', null, 2),
      ('r3', 'T425 Rex Gone', '+61491570157', null, 3), ('r4', 'T425 Roy Gone', '+61491570737', null, 4),
      ('r5', 'T425 Rae Idle', '+61491574118', null, 5),
      ('a1', 'T425 Amy One', '+61491571266', 'r1', 6), ('a2', 'T425 Abe Two', '+61491571491', 'r1', 7),
      ('b1', 'T425 Ben One', '+61491571804', 'a1', 8), ('b2', 'T425 Bea Two', '+61491572549', 'a1', 9),
      ('c1', 'T425 Cal One', '+61491572665', 'b1', 10), ('d1', 'T425 Dan One', '+61491572983', 'c1', 11),
      ('x1', 'T425 Xin Ref', '+61491573087', 'r4', 12), ('x2', 'T425 Xia Buyer', '+61491573770', 'r3', 13)) t(key, name, phone, parent, n);
  update public.customers set deleted_at = now() where id in (pg_temp.fx('a2'), pg_temp.fx('r3'), pg_temp.fx('r4'));
  insert into public.customer_affiliates(customer_id, status, activated_at, referral_code, manually_suspended, store_id)
  values (pg_temp.fx('r1'), 'active', now() - interval '80 days', 'T425R1', false, pg_temp.fx('st')),
         (pg_temp.fx('r2'), 'suspended_manual', now() - interval '80 days', 'T425R2', true, pg_temp.fx('st')),
         (pg_temp.fx('r5'), 'active', now() - interval '80 days', 'T425R5', false, null);
  insert into public.affiliate_accounts(auth_user_id, customer_id, status) values (pg_temp.fx('aff'), pg_temp.fx('r1'), 'claimed');

  -- Payouts: R1's September (S$55, with a reference, a method and a note) and
  -- a cancelled one; R3's (S$50 paid against S$30 earned: S$20 owed back).
  insert into fx values ('p1', gen_random_uuid()), ('p2', gen_random_uuid()), ('p3', gen_random_uuid());
  insert into public.commission_payouts(id, referrer_customer_id, payout_month, total_amount, total_tier1, total_tier2,
         payment_date, payment_method_name, reference, notes, status)
  values (pg_temp.fx('p1'), pg_temp.fx('r1'), '2026-09-01', 55, 55, 0, '2026-10-02', 'Bank Transfer', 'T425-REF', 'T425 internal note', 'paid'),
         (pg_temp.fx('p2'), pg_temp.fx('r1'), '2026-08-01', 7, 7, 0, '2026-09-02', 'Bank Transfer', null, null, 'cancelled'),
         (pg_temp.fx('p3'), pg_temp.fx('r3'), '2026-09-01', 50, 50, 0, '2026-10-02', 'Bank Transfer', null, null, 'paid');

  -- A1's 12 paid invoices, one a day from 1 Sep 2026; each earns R1 S$10 at
  -- Tier 1: 6 paid (the 6th only S$5 of it allocated), 4 earned, 1 reversed,
  -- 1 blocked. B1's invoice earns A1 Tier 1 and R1 Tier 2 (and a cancelled
  -- row); X2's earns R3 S$30, paid. A1's first invoice had S$10 refunded.
  for i in 1 .. 12 loop
    insert into public.invoices(id, invoice_no, store_id, customer_id, created_by, status, total_amount, business_date, created_at, paid_at)
    values (gen_random_uuid(), 'T425-A1-' || i, pg_temp.fx('st'), pg_temp.fx('a1'), pg_temp.fx('own'), 'paid', 100 + i,
            date '2026-09-01' + i - 1, timestamptz '2026-09-01 10:00+08' + (i - 1) * interval '1 day',
            timestamptz '2026-09-01 10:00+08' + (i - 1) * interval '1 day')
    returning id into inv;
    if i = 1 then insert into fx values ('inv1', inv); end if;
    insert into public.commissions(id, invoice_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate,
           commission_amount, status, payout_id, invoice_paid_date)
    values (gen_random_uuid(), inv, pg_temp.fx('a1'), pg_temp.fx('r1'), 'tier1', 'own', 100 + i, 10, 10,
            (case when i <= 6 then 'paid' when i <= 10 then 'earned' when i = 11 then 'reversed' else 'blocked' end)::commission_status,
            case when i <= 6 then pg_temp.fx('p1') end, date '2026-09-01' + i - 1)
    returning id into c;
    if i <= 6 then
      insert into public.commission_payout_allocations(payout_id, commission_id, amount, operation_id)
      values (pg_temp.fx('p1'), c, case when i = 6 then 5 else 10 end, gen_random_uuid());
    end if;
  end loop;
  insert into public.invoice_refunds(invoice_id, amount, reason, kind) values (pg_temp.fx('inv1'), 10, 'T425 part refund', 'allocated');
  insert into public.invoices(id, invoice_no, store_id, customer_id, created_by, status, total_amount, business_date, created_at, paid_at)
  values (gen_random_uuid(), 'T425-B1-1', pg_temp.fx('st'), pg_temp.fx('b1'), pg_temp.fx('own'), 'paid', 200,
          date '2026-10-05', timestamptz '2026-10-05 10:00+08', timestamptz '2026-10-05 10:00+08') returning id into inv;
  insert into public.commissions(invoice_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
  values (inv, pg_temp.fx('b1'), pg_temp.fx('a1'), 'tier1', 'own', 200, 15, 30, 'earned', '2026-10-05'),
         (inv, pg_temp.fx('b1'), pg_temp.fx('r1'), 'tier2', 'own', 30, 35, 10.50, 'earned', '2026-10-05'),
         (inv, pg_temp.fx('b1'), pg_temp.fx('r1'), 'tier2', 'own', 30, 35, 2.25, 'cancelled', '2026-10-05');
  insert into public.invoices(id, invoice_no, store_id, customer_id, created_by, status, total_amount, business_date, created_at, paid_at)
  values (gen_random_uuid(), 'T425-X2-1', pg_temp.fx('st'), pg_temp.fx('x2'), pg_temp.fx('own'), 'paid', 200,
          date '2026-09-10', timestamptz '2026-09-10 10:00+08', timestamptz '2026-09-10 10:00+08') returning id into inv;
  insert into public.commissions(id, invoice_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, payout_id, invoice_paid_date)
  values (gen_random_uuid(), inv, pg_temp.fx('x2'), pg_temp.fx('r3'), 'tier1', 'own', 200, 15, 30, 'paid', pg_temp.fx('p3'), '2026-09-10') returning id into c;
  insert into public.commission_payout_allocations(payout_id, commission_id, amount, operation_id) values (pg_temp.fx('p3'), c, 30, gen_random_uuid());
  -- R3 settled S$5 of the S$20 (414), and a settlement voided: S$15 still owed back.
  insert into public.affiliate_deduction_settlements(referrer_customer_id, amount, settled_on, method, note, created_by, request_id,
         voided_at, voided_by, void_reason, void_request_id)
  values (pg_temp.fx('r3'), 5, '2026-10-10', 'written_off', 'T425 settled by mistake', pg_temp.fx('own'), gen_random_uuid(),
          now(), pg_temp.fx('own'), 'T425 mistake', gen_random_uuid()),
         (pg_temp.fx('r3'), 5, '2026-10-11', 'paid_back', 'T425 paid back in part', pg_temp.fx('own'), gen_random_uuid(),
          null, null, null, null),
         -- One on a live affiliate, so the report's settled column is compared too.
         (pg_temp.fx('r2'), 3, '2026-10-12', 'paid_outside_app', 'T425 taken off a payment outside the app', pg_temp.fx('own'), gen_random_uuid(),
          null, null, null, null);
end $$;

-- ═════ A Before 425 ═════
select pg_temp.check(to_regprocedure('public.referral_signup_checks_pending()') is null
    and to_regclass('public.affiliates') is not null,
  'A0 425 is not installed yet (the legacy affiliates table is there)');
select pg_temp.save_all('before:');
create temp table calls_before as
  select 'admin' k, pg_temp.calls('commission_reporting_rows()') n;
select pg_temp.as_user('own');
select public.affiliate_admin_directory();
select pg_temp.check(pg_temp.calls('commission_reporting_rows()') - (select n from calls_before) = 3,
  'A1 before 425 the Affiliates page read commission_reporting_rows 3 times, once for each sum, and went through them for each affiliate');
select pg_temp.check(jsonb_array_length(pg_temp.snap('before:dash')->'recent') = 13
    and (select count(*) from jsonb_array_elements(pg_temp.snap('before:dl'))) = 5,
  'A2 before 425 Recent Activity held all 13 purchases and the downline went 4 levels down (5 people)');
select pg_temp.as_user(null);

-- ═════ M 425, twice ═════
\if :{?mig}
\else
\set mig ../../../supabase/425_affiliates_directory_portal_and_cleanup.sql
\endif
\ir :mig
create temp table fp1 as select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) fp
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
\ir :mig
select pg_temp.check((select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text))
                        from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') = (select fp from fp1)
    and to_regprocedure('public.referral_signup_checks_pending()') is not null,
  'M1 425 installs, and a second run changes nothing');

select pg_temp.save_all('after:');

-- ═════ S The same answers ═════
select pg_temp.check(pg_temp.snap('after:crr') = pg_temp.snap('before:crr')
    and jsonb_array_length(pg_temp.snap('after:crr')) = 17,
  'S1 commission_reporting_rows gives the same rows (the 6th paid row split S$5 paid, S$5 earned)');
select pg_temp.check(pg_temp.snap('after:admin') = pg_temp.snap('before:admin'), 'S2 the Affiliates page''s directory is the same');
select pg_temp.check(pg_temp.snap('after:dir') = pg_temp.snap('before:dir'), 'S3 affiliate_directory is the same');
select pg_temp.check(pg_temp.snap('after:rep') = pg_temp.snap('before:rep'), 'S4 the Reports affiliate report is the same');
select pg_temp.check((select (e->>'lifetime')::numeric = 110.50 and (e->>'unpaid')::numeric = 55.50 and (e->>'tier2')::int = 2
                             and (e->>'direct_referrals')::int = 1 and (e->>'blocked')::numeric = 12.25
                        from jsonb_array_elements(pg_temp.snap('after:admin')) e where e->>'customer_id' = pg_temp.fx('r1')::text),
  'S5 R1''s figures: lifetime S$110.50, unpaid S$55.50 (S$45 of September after its S$55 payout, S$10.50 of October), blocked S$12.25 (blocked and cancelled), 1 direct, 2 at Tier 2');

-- ═════ P One pass ═════
select pg_temp.as_user('own');
create temp table c0 as select pg_temp.calls('commission_reporting_rows()') crr, pg_temp.calls('affiliate_month_balances()') mb;
select public.affiliate_admin_directory();
create temp table c1 as select pg_temp.calls('commission_reporting_rows()') crr, pg_temp.calls('affiliate_month_balances()') mb;
select count(*) from public.affiliate_directory();
create temp table c2 as select pg_temp.calls('commission_reporting_rows()') crr, pg_temp.calls('affiliate_month_balances()') mb;
select count(*) from public.report_affiliates();
create temp table c3 as select pg_temp.calls('commission_reporting_rows()') crr, pg_temp.calls('affiliate_month_balances()') mb;
select count(*) from public.referrer_list();
create temp table c4 as select pg_temp.calls('commission_reporting_rows()') crr, pg_temp.calls('affiliate_month_balances()') mb;
select pg_temp.check((select c1.crr - c0.crr = 1 and c1.mb - c0.mb = 1 from c0, c1)
    and (select c2.crr - c1.crr = 1 and c2.mb - c1.mb = 1 from c1, c2)
    and (select c3.crr - c2.crr = 2 and c3.mb - c2.mb = 1 from c2, c3)
    and (select c4.crr - c3.crr = 1 and c4.mb - c3.mb = 1 from c3, c4),
  'P1 the directory, affiliate_directory and the Referrers tab read the commission rows once and the balances once; the report reads the rows twice (itself and the directory)');
select pg_temp.as_user('aff');
create temp table c5 as select pg_temp.calls('commission_reporting_rows()') crr;
select public.affiliate_portal_dashboard();
select pg_temp.check((select pg_temp.calls('commission_reporting_rows()') - c5.crr from c5) = 2,
  'P2 the portal dashboard reads the commission rows twice (the totals and months, then the purchases), not five times');
select pg_temp.as_user(null);

-- ═════ T Two tiers ═════
select pg_temp.check((select string_agg((e->>'depth') || ':' || (e->>'full_name'), ',' order by e->>'depth', e->>'full_name')
                        from jsonb_array_elements(pg_temp.snap('after:dl')) e) = '1:T425 Amy One,2:T425 Bea Two,2:T425 Ben One',
  'T1 R1''s downline is Amy (Tier 1), Ben and Bea (Tier 2); Cal (Tier 3) and Dan (Tier 4) are no longer listed');
select pg_temp.check((select (a->>'total_spend')::numeric from jsonb_array_elements(pg_temp.snap('after:dl')) a where a->>'full_name' = 'T425 Amy One')
                     = (select (b->>'total_spend')::numeric from jsonb_array_elements(pg_temp.snap('before:dl')) b where b->>'full_name' = 'T425 Amy One') - 10
    and (select (a->>'paid_purchases')::int from jsonb_array_elements(pg_temp.snap('after:dl')) a where a->>'full_name' = 'T425 Amy One') = 12,
  'T2 Amy''s spend is S$10 less (the refund on her first invoice); her 12 paid purchases are still counted');
select pg_temp.check((select (e->>'total_downline')::int from jsonb_array_elements(pg_temp.snap('after:list')) e where e->>'customer_id' = pg_temp.fx('r1')::text) = 3
    and (select (e->>'total_downline')::int from jsonb_array_elements(pg_temp.snap('before:list')) e where e->>'customer_id' = pg_temp.fx('r1')::text) = 5,
  'T3 the Referrers tab counts R1''s downline as 3 (was 5), as the Affiliates page and Reports count it');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(pg_temp.snap('after:list')) e where e->>'customer_id' = pg_temp.fx('r4')::text)
    and exists (select 1 from jsonb_array_elements(pg_temp.snap('before:list')) e where e->>'customer_id' = pg_temp.fx('r4')::text)
    and (select (e->>'unpaid_earned')::numeric from jsonb_array_elements(pg_temp.snap('after:list')) e where e->>'customer_id' = pg_temp.fx('r3')::text) = -15,
  'T4 a deleted referrer with nothing owed is left out; one who still owes S$15 back (S$20 less S$5 settled) is listed');
select pg_temp.check((select jsonb_agg(e - 'total_downline' order by e->>'customer_id') from jsonb_array_elements(pg_temp.snap('after:list')) e)
                     = (select jsonb_agg(e - 'total_downline' order by e->>'customer_id') from jsonb_array_elements(pg_temp.snap('before:list')) e
                         where e->>'customer_id' <> pg_temp.fx('r4')::text),
  'T5 every other figure on the Referrers tab is as before');
select pg_temp.as_user('adm');
select pg_temp.check((select count(*) from public.referrer_downline(pg_temp.fx('r1'))) = 3
    and (select count(*) from public.referrer_list()) = (select jsonb_array_length(pg_temp.snap('after:list')))
    and (select settled from public.report_affiliates() where customer_id = pg_temp.fx('r3')) is null
    and pg_temp.err('select public.affiliate_admin_directory()') like '%Owner or Manager only%',
  'T5b an Admin still reads the Referrers tab and the downline; the Affiliates page directory stays Owner or Manager');
select pg_temp.check((select (e->>'settled')::numeric from jsonb_array_elements(pg_temp.snap('after:rep')) e where e->>'customer_id' = pg_temp.fx('r2')::text) = 3
    and not exists (select 1 from jsonb_array_elements(pg_temp.snap('after:rep')) e where e->>'customer_id' = pg_temp.fx('r3')::text),
  'T5c the report still counts a settlement (S$3 for R2) and, as before, leaves out a deleted referrer');
select pg_temp.as_user('stf');
select pg_temp.check(pg_temp.err(format('select * from public.referrer_downline(%L)', pg_temp.fx('r1'))) like '42501 Commission access denied%',
  'T6 staff are still refused the downline with the same words');
select pg_temp.as_user('pend');
select pg_temp.check(pg_temp.err(format('select * from public.referrer_downline(%L)', pg_temp.fx('r1'))) like '42501 Only active Energia staff%',
  'T7 an Owner whose invitation is still pending is refused the downline');
select pg_temp.check(pg_temp.err('select public.affiliate_admin_directory()') like '42501 Only active Energia staff%',
  'T7b an Owner whose invitation is pending is refused the Affiliates page directory');
select pg_temp.check(pg_temp.err('select count(*) from public.referrer_list()') like '42501 Only active Energia staff%'
    and pg_temp.err('select count(*) from public.report_affiliates()') like '42501 Only active Energia staff%',
  'T7c an Owner whose invitation is pending is refused the Referrers tab and the Reports affiliate report');
select pg_temp.as_user('aff');
select pg_temp.check(pg_temp.err('select count(*) from public.referrer_list()') like '42501 Only active Energia staff%'
    and pg_temp.err('select count(*) from public.report_affiliates()') like '42501 Only active Energia staff%',
  'T7d an affiliate login is refused the Referrers tab and the report (it got no rows before)');
select pg_temp.as_user('stf');
select pg_temp.check((select count(*) from public.referrer_list()) = 0 and (select count(*) from public.report_affiliates()) = 0,
  'T7e staff still get no rows from the Referrers tab or the report, as before');
select pg_temp.as_user(null);

-- ═════ R Recent Activity ═════
select pg_temp.check(pg_temp.snap('after:dash')->'recent' = jsonb_path_query_array(pg_temp.snap('before:dash')->'recent', '$[0 to 9]')
    and pg_temp.snap('after:dash')->'recent'->0->>'purchase_date' = '2026-10-05'
    and pg_temp.snap('after:dash')->'recent'->9->>'purchase_date' = '2026-09-04',
  'R1 Recent Activity is the 10 newest purchases, newest first (5 Oct back to 4 Sep)');
select pg_temp.check(pg_temp.snap('after:dash') - 'recent' = pg_temp.snap('before:dash') - 'recent',
  'R2 the rest of the dashboard is as before');

-- ═════ E Earnings ═════
select pg_temp.check(pg_temp.snap('after:earn') = pg_temp.snap('before:earn') - 'by_customer'
    and pg_temp.snap('before:earn') ? 'by_customer' and not pg_temp.snap('after:earn') ? 'by_customer',
  'E1 the portal earnings are as before, without by_customer');

-- ═════ O Payouts ═════
select pg_temp.check(not exists (select 1 from jsonb_array_elements(pg_temp.snap('after:pay')) e where e ?| array['reference', 'method', 'notes'])
    and (select jsonb_agg(e - array['reference', 'method', 'notes']) from jsonb_array_elements(pg_temp.snap('before:pay')) e) = pg_temp.snap('after:pay')
    and pg_temp.snap('after:pay')::text not like '%T425 internal note%' and pg_temp.snap('after:pay')::text not like '%T425-REF%',
  'O1 the portal''s payouts carry no reference, method or notes; the rest is as before');

-- ═════ C Rates and the staff directory ═════
select pg_temp.as_user('mgr');
select public.set_commission_rates(15, 4.5, 30, 35);
select pg_temp.check((select l.old_data = jsonb_build_object('tier1_own', 15, 'tier1_third', 4.5, 'tier2_own', 35, 'tier2_third', 35)
                             and l.new_data = jsonb_build_object('tier1_own', 15, 'tier1_third', 4.5, 'tier2_own', 30, 'tier2_third', 35)
                        from public.audit_logs l where l.action = 'commission_rates_set' order by l.created_at desc limit 1),
  'C1 a change of rates is audited with the rates before it (Tier 2 Own 35 to 30)');
select pg_temp.as_user('pend');
select pg_temp.check(pg_temp.err('select public.set_commission_rates(15, 4.5, 5, 5)') like '42501 %'
    and (select commission_tier2_own_rate from public.app_settings where id = true) = 30,
  'C2 an Owner whose invitation is pending cannot change the rates');
select pg_temp.as_user('stf');
select pg_temp.check(pg_temp.err('select public.set_commission_rates(15, 4.5, 5, 5)') like '%Only an Owner or Manager can edit commission rates%',
  'C3 staff are refused the rates with the same words as before');
select pg_temp.check((public.affiliate_staff_directory('T425', 50, 0)->>'total')::int = 3, 'C4 staff still use the staff directory');
update public.profiles set role = 'staff' where id = pg_temp.fx('pend');
select pg_temp.as_user('pend');
select pg_temp.check(pg_temp.err('select public.affiliate_staff_directory(null, 50, 0)') like '42501 Only active Energia staff%',
  'C5 a staff login whose invitation is pending is refused the staff directory');
select pg_temp.as_user(null);

-- ═════ L Legacy ═════
select pg_temp.check(to_regclass('public.affiliates') is null and to_regclass('public.affiliate_commissions') is null
    and to_regprocedure('public.create_commission_payout(uuid,date,uuid,text,text)') is null
    and not exists (select 1 from pg_proc where proname = 'create_commission_payout'),
  'L1 the legacy tables and create_commission_payout are gone');

-- ═════ G Grants ═════
select pg_temp.check(not has_function_privilege('anon', 'public.referral_signup_checks_pending()', 'execute')
    and not has_function_privilege('anon', 'public.decide_referral_signup_check(uuid,text,text)', 'execute')
    and has_function_privilege('authenticated', 'public.referral_signup_checks_pending()', 'execute')
    and has_function_privilege('authenticated', 'public.decide_referral_signup_check(uuid,text,text)', 'execute')
    and has_function_privilege('anon', 'public.affiliate_referral_signup(text,text,text,text,text,text)', 'execute')
    and not has_function_privilege('anon', 'public.referrer_list()', 'execute')
    and not has_table_privilege('anon', 'public.referral_signup_checks', 'select,insert,update,delete')
    and not has_table_privilege('authenticated', 'public.referral_signup_checks', 'select,insert,update,delete'),
  'G1 the new functions are for signed-in logins only, sign-up stays public, the new table is closed');

do $$ begin
  if exists (select 1 from failed) then
    raise exception '425 affiliates: % check(s) failed: %', (select count(*) from failed), (select string_agg(msg, ' | ' order by n) from failed);
  end if;
  raise notice 'ALL PASS: 425 affiliates (one pass, two tiers, recent 10, earnings, payouts, rates, legacy, grants)';
end $$;
rollback;
