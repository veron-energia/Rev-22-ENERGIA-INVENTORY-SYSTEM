-- 414's one-off repair, rehearsed: scripts/commissions/repair/414-settle-a79499b7.sql
--
-- The repair records the S$555.27 one affiliate owed back on 9 Oct 2026 as
-- settled outside the app (the Owner's decision of that day), and only while
-- that affiliate still owes exactly that. This checks that it refuses when
-- the affiliate owes something else or already has a settlement in force,
-- records exactly one settlement (how, amount, date, note, who, audited) that
-- leaves the affiliate owing nothing and owed nothing, and that a second run,
-- and a run after the settlement was voided, change nothing.
--
-- Disposable database only; everything is rolled back. 414 is applied inside
-- this transaction when the database does not have it. On a copy of
-- production the affiliate's own rows are used as they are; elsewhere they
-- are built with production's figures of 9 Oct 2026 under the affiliate's and
-- the Owner's ids, with invented names (T414R, +65914140xx, @sig.invalid).
--   psql -X -v ON_ERROR_STOP=1 -f scripts/commissions/tests/settle-repair-414.sql
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif
select to_regclass('public.affiliate_deduction_settlements') is null as t414r_apply \gset
\if :t414r_apply
\ir ../../../supabase/414_affiliate_deduction_settlements.sql
\endif

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end$$;
create temp table fx(k text primary key, v uuid);
insert into fx values ('aff', 'a79499b7-e02d-4330-9007-8deaa82d67ef'), ('owner', '0e857a04-89f4-4b3e-adf2-c9fbd799d46c');
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.as_owner() returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx('owner'), 'role', 'authenticated')::text, true);
  select null::void $$;
create function pg_temp.commission(inv text, amt numeric, on_day date) returns uuid language sql as $$
  insert into public.commissions(invoice_id, buyer_customer_id, referrer_customer_id, tier, product_type,
                                 line_amount, rate, commission_amount, invoice_paid_date, status)
  values (pg_temp.fx(inv), pg_temp.fx('buyer'), pg_temp.fx('aff'), 'tier1', 'own', amt * 10, 10, amt, on_day, 'earned')
  returning id $$;
create function pg_temp.months() returns text language sql as $$
  select string_agg(to_char(b.month, 'YYYY-MM') || ' ' || b.balance || ' settled ' || b.settled, '; ' order by b.month)
    from public.affiliate_month_balances() b where b.referrer = pg_temp.fx('aff') $$;

-- ===== Fixture (only where the affiliate is not there: not a copy of production) =====
do $$
declare v uuid; k text; c1 uuid;
begin
  if not exists (select 1 from public.profiles where id = pg_temp.fx('owner')) then
    insert into auth.users(id, email) values (pg_temp.fx('owner'), 't414r-owner@sig.invalid');
    insert into public.profiles(id, full_name, email, role, is_active) values (pg_temp.fx('owner'), 'T414R Owner', 't414r-owner@sig.invalid', 'owner', true);
  end if;
  if exists (select 1 from public.customers where id = pg_temp.fx('aff')) then
    raise notice 'NOTE  the affiliate is there: its own rows are used (a copy of production)'; return; end if;
  perform pg_temp.as_owner();
  insert into public.stores(name, code, country_code) values ('T414R Store', 'T414R', 'SG') returning id into v;
  insert into fx values ('store', v);
  insert into public.payment_methods(name) values ('T414R Cash') returning id into v;
  insert into fx values ('cash', v);
  insert into public.customers(full_name, phone) values ('T414R Buyer', '+6591414050') returning id into v;
  insert into fx values ('buyer', v);
  insert into public.customers(id, full_name, phone) values (pg_temp.fx('aff'), 'T414R Affiliate', '+6591414051');
  insert into public.customer_affiliates(customer_id, store_id, status, activated_at) values (pg_temp.fx('aff'), pg_temp.fx('store'), 'active', now());
  foreach k in array array['i1','i2','i3','i4','i5','i6'] loop
    insert into public.invoices(invoice_no, store_id, customer_id, created_by, status)
      values ('T414R-' || upper(k), pg_temp.fx('store'), pg_temp.fx('buyer'), pg_temp.fx('owner'), 'paid') returning id into v;
    insert into fx values (k, v);
  end loop;
  c1 := pg_temp.commission('i1', 991.64, '2026-09-02');
  perform pg_temp.commission('i2', 284.66, '2026-09-03');
  perform pg_temp.commission('i3', 429.29, '2026-09-20');
  perform public.record_affiliate_payout(pg_temp.fx('aff'), '2026-09-01', 1276.30, pg_temp.fx('cash'), '2026-10-03', 'T414R', null, gen_random_uuid());
  perform pg_temp.commission('i4', 93.72, '2026-10-02');
  perform pg_temp.commission('i5', 7.08, '2026-10-05');
  perform public.record_affiliate_payout(pg_temp.fx('aff'), '2026-10-01', 93.72, pg_temp.fx('cash'), '2026-10-06', 'T414R', null, gen_random_uuid());
  insert into public.commissions(invoice_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate,
                                 commission_amount, invoice_paid_date, status, adjusts_commission_id, reversal_reason)
  values (pg_temp.fx('i1'), pg_temp.fx('buyer'), pg_temp.fx('aff'), 'tier1', 'own', -9916.40, 10, -991.64, '2026-09-02', 'earned', c1,
          'Future payout adjustment: T414R fixture');
  perform set_config('request.jwt.claims', '', true);
end $$;
do $$
begin
  perform pg_temp.check((select deduction = 555.27 and owed = -555.27 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('aff'))
                        and pg_temp.months() = '2026-09 -562.35 settled 0; 2026-10 7.08 settled 0',
    'the affiliate owes S$555.27 back: ' || pg_temp.months());
end $$;

-- ===== 1. It refuses when the affiliate owes something else =====
savepoint t414r_other;
do $$ begin
  if pg_temp.fx('i6') is not null then perform pg_temp.commission('i6', 1.00, '2026-10-06');
  else update public.commission_payouts set total_amount = total_amount where false; end if;
end $$;
\set ON_ERROR_STOP off
\ir ../repair/414-settle-a79499b7.sql
\set ON_ERROR_STOP on
rollback to savepoint t414r_other;
release savepoint t414r_other;
select set_config('t414r.refused_other', :'LAST_ERROR_MESSAGE', true) as t414r_kept \gset

-- ===== 2. It refuses when a settlement is already in force (made on the page) =====
savepoint t414r_page;
do $$ begin
  perform pg_temp.as_owner();
  perform public.affiliate_deduction_settlement_record(pg_temp.fx('aff'), 100, '2026-10-09', 'paid_back', 'T414R made on the page',
                                                       gen_random_uuid(), pg_temp.fx('owner'));
  perform set_config('request.jwt.claims', '', true);
end $$;
\set ON_ERROR_STOP off
\ir ../repair/414-settle-a79499b7.sql
\set ON_ERROR_STOP on
rollback to savepoint t414r_page;
release savepoint t414r_page;
select set_config('t414r.refused_page', :'LAST_ERROR_MESSAGE', true) as t414r_kept \gset
do $$
begin
  perform pg_temp.check(current_setting('t414r.refused_page') like '414 repair: the affiliate already has a settlement in force%',
    '2: refused while a settlement is in force: ' || current_setting('t414r.refused_page'));
  if pg_temp.fx('i6') is not null then
    perform pg_temp.check(current_setting('t414r.refused_other') like '414 repair: the affiliate owes back S$554.27 (net -554.27), not S$555.27%',
      '1: refused when the affiliate owes S$554.27: ' || current_setting('t414r.refused_other'));
  end if;
  perform pg_temp.check(not exists (select 1 from public.affiliate_deduction_settlements where referrer_customer_id = pg_temp.fx('aff')),
    '1-2: nothing was written by either refusal');
end $$;

-- ===== 3. It records the settlement =====
\ir ../repair/414-settle-a79499b7.sql
do $$
declare s public.affiliate_deduction_settlements;
begin
  select * into s from public.affiliate_deduction_settlements where referrer_customer_id = pg_temp.fx('aff');
  perform pg_temp.check(s.amount = 555.27 and s.settled_on = '2026-10-09' and s.method = 'paid_outside_app'
                        and s.note = 'Settled outside the app (the Owner, 9 Oct 2026).' and s.created_by = pg_temp.fx('owner')
                        and s.voided_at is null and s.request_id = '41400000-a794-49b7-8000-000000555270'
                        and (select count(*) from public.affiliate_deduction_settlements where referrer_customer_id = pg_temp.fx('aff')) = 1,
    '3: one settlement: S$555.27, paid off outside the app, 9 Oct 2026, the note, the Owner');
  perform pg_temp.check((select owed = 0 and unpaid = 0 and deduction = 0 and payable = 0 from public.affiliate_referrer_balances()
                          where referrer = pg_temp.fx('aff'))
                        and pg_temp.months() = '2026-09 -7.08 settled 555.27; 2026-10 7.08 settled 0',
    '3: the affiliate owes nothing and is owed nothing; October''s 7.08 counted against the debt: ' || pg_temp.months());
  perform pg_temp.check((select count(*) from public.audit_logs where record_id = s.id and action = 'affiliate_deduction_settled'
                          and changed_by = pg_temp.fx('owner') and actor_role = 'owner'
                          and reason = 'Settled outside the app (the Owner, 9 Oct 2026).') = 1,
    '3: audited as the Owner');
end $$;

-- ===== 4. A second run changes nothing; nor does one after a void =====
\ir ../repair/414-settle-a79499b7.sql
do $$
begin
  perform pg_temp.check((select count(*) from public.affiliate_deduction_settlements where referrer_customer_id = pg_temp.fx('aff')) = 1
                        and (select count(*) from public.audit_logs a join public.affiliate_deduction_settlements s on s.id = a.record_id
                              where s.referrer_customer_id = pg_temp.fx('aff')) = 1,
    '4: a second run records nothing more');
  perform pg_temp.as_owner();
  perform public.affiliate_deduction_settlement_void(
    (select id from public.affiliate_deduction_settlements where referrer_customer_id = pg_temp.fx('aff')),
    'T414R voided to rehearse', gen_random_uuid(), pg_temp.fx('owner'));
  perform set_config('request.jwt.claims', '', true);
end $$;
\ir ../repair/414-settle-a79499b7.sql
do $$
begin
  perform pg_temp.check((select count(*) from public.affiliate_deduction_settlements where referrer_customer_id = pg_temp.fx('aff')) = 1
                        and (select deduction from public.affiliate_referrer_balances() where referrer = pg_temp.fx('aff')) = 555.27,
    '4: once an Owner voided it, a run does not record it again');
end $$;

rollback;
