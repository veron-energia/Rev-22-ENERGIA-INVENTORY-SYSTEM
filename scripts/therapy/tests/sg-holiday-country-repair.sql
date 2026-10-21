-- The 423 data step that sets Singapore as the holiday country of the therapy
-- periods that have none (scripts/therapy/repair/423-sg-holiday-country-on-periods.sql):
-- the read-only PREVIEW at its top, what it refuses, a dry run that changes
-- nothing, the real run, what Recalculate then makes of the period, and a
-- second run that changes nothing.
--
-- Disposable database only; everything is rolled back. Run from the repository
-- root (the real run is the same file with c_apply set to true, made with sed):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/therapy/tests/sg-holiday-country-repair.sql
-- It needs a database with production's schema (no rows needed). Every name,
-- phone and email is invented (T423H, +65 9123 46xx, @sig.invalid).
\set ON_ERROR_STOP on
begin;
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end$$;
create temp table fx(k text primary key, v uuid);
grant select on fx to public;
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.refused(q text) returns text language plpgsql as $$
begin
  execute q;
  return null;
exception when others then
  return sqlerrm;
end $$;
\set apply_sql `sed 's/c_apply constant boolean := false;/c_apply constant boolean := true;/' scripts/therapy/repair/423-sg-holiday-country-on-periods.sql`
\set dry_sql `cat scripts/therapy/repair/423-sg-holiday-country-on-periods.sql`
\set preview_sql `awk '/^-- ── PREVIEW/{f=1;next} /^-- ── The change/{f=0} f' scripts/therapy/repair/423-sg-holiday-country-on-periods.sql`

-- ── Fixture: the periods as on production on 9 Oct 2026, and the Singapore
-- holidays loaded for 1 Sep 2026 to 31 Mar 2027. ─────────────────────────────
do $$
declare v uuid; st uuid; inv uuid; pkg uuid; c uuid; k text;
begin
  perform set_config('request.jwt.claims', '', true);
  insert into auth.users(id, email) values (gen_random_uuid(), 't423h-owner@sig.invalid') returning id into v;
  insert into public.profiles(id, full_name, email, role, is_active) values (v, 'T423H Owner', 't423h-owner@sig.invalid', 'owner', true);
  insert into fx values ('owner', v);
  insert into public.stores(name, code, country_code) values ('T423H Store', 'T423H', 'SG') returning id into st;
  insert into fx values ('store', st);
  insert into public.therapy_holiday_countries(code, name, is_active, requires_region)
  values ('SG', 'Singapore', true, false) on conflict (code) do nothing;
  delete from public.therapy_closure_dates where closure_date between '2026-09-01' and '2027-03-31';
  insert into public.therapy_closure_dates(closure_date, kind, name, country_code, observed_for)
  select d::date, 'public_holiday', n, 'SG', o::date
    from (values ('2026-11-08', 'Deepavali', null), ('2026-11-09', 'Deepavali (observed)', '2026-11-08'),
                 ('2026-12-25', 'Christmas Day', null), ('2027-01-01', 'New Year''s Day', null),
                 ('2027-02-06', 'Chinese New Year', null), ('2027-02-07', 'Chinese New Year', null),
                 ('2027-02-08', 'Chinese New Year (observed)', '2027-02-07'),
                 ('2027-03-10', 'Hari Raya Puasa', null), ('2027-03-26', 'Good Friday', null)) x(d, n, o);
  insert into public.unlimited_therapy_packages(name, duration_months) values ('T423H Six Months', 6) returning id into pkg;

  -- Purchased units: P1 is UTP-0000001 (no country); P2 already has Singapore;
  -- P3 is waiting to start.
  foreach k in array array['P1', 'P2', 'P3'] loop
    insert into public.customers(full_name, phone) values ('T423H Customer ' || k, '+659123460' || right(k, 1)) returning id into c;
    insert into public.invoices(invoice_no, store_id, customer_id, created_by, status)
      values ('T423H-' || k, st, c, pg_temp.fx('owner'), 'paid') returning id into inv;
    insert into public.purchased_therapy_entitlements(entitlement_no, customer_id, store_id, package_id, invoice_id,
        package_name, duration_months, price_snapshot, purchase_date, activation_deadline, activation_date, expiry_date,
        status, benefit_choice, offered_choices, holiday_country, holiday_country_source, base_expiry_date, closure_days_added)
    values (case k when 'P1' then 'UTP-0000001' else 'T423H-' || k end, c, st, pkg, inv, 'T423H Six Months', 6, 1000,
            date '2026-09-01', date '2027-09-01',
            case k when 'P3' then null when 'P1' then date '2026-09-01' else date '2026-10-02' end,
            case k when 'P3' then null when 'P1' then date '2027-02-28' else date '2027-04-08' end,
            case k when 'P3' then 'pending_activation' else 'active' end, 'unlimited', array['unlimited'],
            case k when 'P2' then 'SG' end, case k when 'P2' then 'manual' end,
            case k when 'P2' then date '2027-04-01' end, case k when 'P2' then 7 else 0 end)
    returning id into v;
    insert into fx values (k, v);
  end loop;
  -- Legacy rewards: L1 taken as vouchers (no expiry), L2 cancelled; neither has a country.
  foreach k in array array['L1', 'L2'] loop
    insert into public.customers(full_name, phone) values ('T423H Customer ' || k, '+659123461' || right(k, 1)) returning id into c;
    insert into public.therapy_entitlements(entitlement_no, customer_id, store_id, package_name, entitlement_kind,
        duration_months, qualifying_amount, qualified_value, activation_deadline, activation_date, status)
    values ('T423H-' || k, c, st, 'T423H Legacy', case k when 'L1' then 'voucher' else 'unlimited' end,
            1, 100, 100, date '2027-08-01', case k when 'L1' then date '2026-08-05' end,
            case k when 'L1' then 'active' else 'cancelled' end)
    returning id into v;
    insert into fx values (k, v);
  end loop;
end $$;
create temp table before_rows as
  select id, holiday_country, expiry_date, base_expiry_date, closure_days_added from public.purchased_therapy_entitlements
  union all
  select id, holiday_country, expiry_date, base_expiry_date, closure_days_added from public.therapy_entitlements;

-- ── The PREVIEW (read only), as the MCP tool shows it ───────────────────────
create temp view t423_preview as
:preview_sql
select pg_temp.check((select string_agg(concat_ws('|', k, entitlement_no, status, activation_date, duration_months,
                                                  expiry_now, expiry_after, added_days), '; ')
                        from t423_preview)
                     = 'purchased|UTP-0000001|active|2026-09-01|6|2027-02-28|2027-03-05|5',
  'the PREVIEW shows the one period and its new expiry, as the header says');
select pg_temp.check(not exists (select 1 from public.therapy_expiry_adjustments)
                     and (select holiday_country is null from public.purchased_therapy_entitlements where id = pg_temp.fx('P1')),
  'the PREVIEW changes nothing');

-- ── What it refuses (each tried and undone) ──────────────────────────────────
-- Another period with no country, not the one read on 9 Oct 2026.
savepoint s1;
update public.purchased_therapy_entitlements set holiday_country = null where id = pg_temp.fx('P2');
select pg_temp.check(pg_temp.refused(:'apply_sql') like '423 holiday country: the periods with no holiday country are not the ones read on 9 Oct 2026%T423H-P2%',
  'a second period with no country stops it, and it shows what it found');
rollback to savepoint s1;
-- Another calendar: Christmas taken out, so the result is not the one read.
savepoint s2;
delete from public.therapy_closure_dates where closure_date = '2026-12-25';
select pg_temp.check(pg_temp.refused(:'apply_sql') like '%found    purchased|UTP-0000001|active|2026-09-01|6|2027-02-28|2027-03-04|4',
  'a different holiday calendar (a new result) stops it');
rollback to savepoint s2;
-- A changed calculation function.
savepoint s3;
create or replace function public.therapy_expiry_explanation(p_activation date, p_months integer, p_country text DEFAULT NULL::text,
  p_region text DEFAULT NULL::text, p_convention text DEFAULT 'legacy'::text) returns jsonb language sql as $f$ select '{}'::jsonb $f$;
select pg_temp.check(pg_temp.refused(:'apply_sql') like '423 holiday country: public.therapy_expiry_explanation(date,integer,text,text,text) is not the version read on 9 Oct 2026%',
  'a function it follows that has changed stops it');
rollback to savepoint s3;
select pg_temp.check(not exists (select 1 from public.therapy_expiry_adjustments) and not exists (select 1 from public.audit_logs
                       where action = 'holiday_country_assigned'),
  'the refusals changed nothing');

-- ── Dry run ──────────────────────────────────────────────────────────────────
:dry_sql
select pg_temp.check((select holiday_country is null and expiry_date = '2027-02-28' from public.purchased_therapy_entitlements
                       where id = pg_temp.fx('P1'))
                     and not exists (select 1 from public.therapy_expiry_adjustments),
  'the dry run changes nothing');

-- ── The real run ─────────────────────────────────────────────────────────────
:apply_sql
select pg_temp.check((select holiday_country = 'SG' and holiday_region is null and holiday_country_source = 'repair'
                             and base_expiry_date = '2027-02-28' and closure_days_added = 5 and expiry_date = '2027-03-05'
                             and status = 'active' and activation_date = '2026-09-01' and expiry_calculated_at is not null
                        from public.purchased_therapy_entitlements where id = pg_temp.fx('P1')),
  'UTP-0000001: Singapore, 28 Feb 2027 + 5 holiday days = 5 Mar 2027, still active from 1 Sep 2026');
select pg_temp.check((select count(*) = 1 and bool_and(action = 'country_assigned' and entitlement_kind = 'purchased'
                             and old_country is null and new_country = 'SG' and old_expiry = '2027-02-28'
                             and new_expiry = '2027-03-05' and base_expiry = '2027-02-28' and days_added = 5
                             and performed_by is null and reason like 'Singapore set as the holiday country with the Owner''s approval%'
                             and jsonb_array_length(detail -> 'applied') = 5
                             and detail -> 'applied' -> 0 ->> 'date' = '2026-11-09')
                        from public.therapy_expiry_adjustments where entitlement_id = pg_temp.fx('P1')),
  'one history row on the period, as assigning a calendar writes it (5 holidays: 9 Nov, 25 Dec, 1 Jan, 6 Feb, 8 Feb)');
select pg_temp.check((select count(*) from public.audit_logs where action = 'holiday_country_assigned') = 1
                     and exists (select 1 from public.audit_logs where record_id = pg_temp.fx('P1')
                                   and table_name = 'purchased_therapy_entitlements' and module = 'therapy'
                                   and actor_role = 'system' and changed_by is null and store_id = pg_temp.fx('store')
                                   and old_data ->> 'expiry_date' = '2027-02-28' and new_data ->> 'expiry_date' = '2027-03-05'),
  'one audit row, with the expiry before and after');
select pg_temp.check(not exists (select 1 from before_rows b
                                   left join (select id, holiday_country, expiry_date, base_expiry_date, closure_days_added
                                                from public.purchased_therapy_entitlements
                                              union all
                                              select id, holiday_country, expiry_date, base_expiry_date, closure_days_added
                                                from public.therapy_entitlements) a on a.id = b.id
                                  where b.id <> pg_temp.fx('P1') and (a.id is null or row(a.*) is distinct from row(b.*))),
  'nothing else changes: the unit that has Singapore, the one waiting to start, the voucher reward and the cancelled one');
select pg_temp.check(not exists (select 1 from t423_preview),
  'after the real run the PREVIEW shows no row (already done)');

-- Recalculate (as an Owner) now finds the period with its country, already at
-- the right date, and nothing with no country.
select set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx('owner'), 'role', 'authenticated')::text, true);
set local role authenticated;
select pg_temp.check((select not needs_country and change_days = 0 and proposed_expiry = '2027-03-05'
                        from public.therapy_recalculation_preview('purchased', null) where entitlement_id = pg_temp.fx('P1')),
  'Recalculate sees UTP-0000001 with a country and no change to make');
select pg_temp.check((public.therapy_apply_recalculation(null, null, false, null) ->> 'skipped_needs_country')::int = 0,
  'Recalculate skips no period for want of a country');
reset role;
select set_config('request.jwt.claims', '', true);

-- ── A second run changes nothing ─────────────────────────────────────────────
:apply_sql
select pg_temp.check((select count(*) from public.therapy_expiry_adjustments where action = 'country_assigned') = 1
                     and (select count(*) from public.audit_logs where action = 'holiday_country_assigned') = 1
                     and (select expiry_date from public.purchased_therapy_entitlements where id = pg_temp.fx('P1')) = '2027-03-05',
  'a second run changes nothing');
rollback;
