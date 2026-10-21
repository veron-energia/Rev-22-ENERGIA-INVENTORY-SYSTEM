-- The 423 data step that marks Singapore 2027 as checked
-- (scripts/therapy/repair/423-sg-2027-holidays-checked.sql): the read-only
-- PREVIEW at its top, a dry run that changes nothing, the real run, a second
-- run that changes nothing, and a calendar that differs from MOM's list,
-- which is refused.
--
-- Disposable database only; everything is rolled back. Run from the repository
-- root (the real run is the same file with c_apply set to true, made with sed):
--   psql -X -v ON_ERROR_STOP=1 -f scripts/therapy/tests/sg-2027-holidays-repair.sql
-- It needs a database with production's schema (no rows needed).
\set ON_ERROR_STOP on
begin;
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end$$;

-- The 2027 dates as loaded on production (9 Oct 2026), and a 2026 year that
-- is already checked.
insert into public.therapy_holiday_countries(code, name, is_active, requires_region)
values ('SG', 'Singapore', true, false) on conflict (code) do nothing;
delete from public.therapy_calendar_coverage where country_code = 'SG' and year = 2027;
delete from public.therapy_closure_dates where country_code = 'SG' and closure_date between '2027-01-01' and '2027-12-31';
insert into public.therapy_closure_dates(closure_date, kind, name, country_code, observed_for, source, source_reference)
select d::date, 'public_holiday', n, 'SG', o::date, 'mom.gov.sg', 'Gazetted public holidays 2027'
  from (values ('2027-01-01', 'New Year''s Day', null), ('2027-02-06', 'Chinese New Year', null),
               ('2027-02-07', 'Chinese New Year', null), ('2027-02-08', 'Chinese New Year (observed)', '2027-02-07'),
               ('2027-03-10', 'Hari Raya Puasa', null), ('2027-03-26', 'Good Friday', null),
               ('2027-05-01', 'Labour Day', null), ('2027-05-17', 'Hari Raya Haji', null),
               ('2027-05-20', 'Vesak Day', null), ('2027-08-09', 'National Day', null),
               ('2027-10-28', 'Deepavali', null), ('2027-12-25', 'Christmas Day', null)) x(d, n, o);
-- A company closure in 2027 is not a public holiday and is not compared.
insert into public.therapy_closure_dates(closure_date, kind, name, country_code)
values ('2027-12-31', 'company_closure', 'T423 year-end closure', null);

select pg_temp.check(not (public.therapy_calendar_gaps(date '2026-10-09', date '2027-10-31', 'SG', null) ->> 'verified')::boolean,
  'before: a period running into 2027 is not verified');

-- The PREVIEW (read only), as the MCP tool shows it.
\set preview_sql `awk '/^-- ── PREVIEW/{f=1;next} /^-- ── The change/{f=0} f' scripts/therapy/repair/423-sg-2027-holidays-checked.sql`
create temp view t423_preview as
:preview_sql
select pg_temp.check((select string_agg(closure_date::text || coalesce('>' || observed_for::text, ''), '|' order by closure_date)
                        from t423_preview)
                     = '2027-01-01|2027-02-06|2027-02-07|2027-02-08>2027-02-07|2027-03-10|2027-03-26|2027-05-01|'
                       '2027-05-17|2027-05-20|2027-08-09|2027-10-28|2027-12-25'
                     and (select bool_and(country_code = 'SG' and region is null and already_checked is null) from t423_preview),
  'the PREVIEW lists the 12 dates, Singapore, no region, not yet checked');

-- Dry run.
\ir ../repair/423-sg-2027-holidays-checked.sql
select pg_temp.check(not exists (select 1 from public.therapy_calendar_coverage where country_code = 'SG' and year = 2027),
  'the dry run changes nothing');

-- The real run.
\set apply_sql `sed 's/c_apply constant boolean := false;/c_apply constant boolean := true;/' scripts/therapy/repair/423-sg-2027-holidays-checked.sql`
:apply_sql
select pg_temp.check((select is_verified and region = '*' and source = 'mom.gov.sg' and confirmed_by is null
                             and notes like 'The 12 dates were compared with the official MOM list%'
                        from public.therapy_calendar_coverage where country_code = 'SG' and year = 2027),
  'the real run marks Singapore 2027 checked, with the source and the note');
select pg_temp.check((select count(*) from public.audit_logs where action = 'calendar_coverage_confirmed'
                        and new_data ->> 'year' = '2027') = 1,
  'one audit row');
select pg_temp.check((public.therapy_calendar_gaps(date '2027-01-01', date '2027-10-31', 'SG', null) ->> 'verified')::boolean,
  'after: a 2027 period in Singapore is verified');
select pg_temp.check((select count(*) from public.therapy_closure_dates where country_code = 'SG'
                        and closure_date between '2027-01-01' and '2027-12-31' and deleted_at is null) = 12,
  'the dates themselves are not changed');
select pg_temp.check((select count(*) = 12 and bool_and(already_checked) from t423_preview),
  'after the real run the PREVIEW shows already_checked true');

-- A second run changes nothing.
:apply_sql
select pg_temp.check((select count(*) from public.audit_logs where action = 'calendar_coverage_confirmed') = 1,
  'a second run changes nothing');

-- A calendar that differs from MOM's list is refused, and nothing changes.
delete from public.therapy_calendar_coverage where country_code = 'SG' and year = 2027;
update public.therapy_closure_dates set deleted_at = now() where country_code = 'SG' and closure_date = '2027-05-20';
create function pg_temp.refused(q text) returns text language plpgsql as $$
begin
  execute q;
  return null;
exception when others then
  return sqlerrm;
end $$;
select pg_temp.check(pg_temp.refused(:'apply_sql') like '423 SG 2027: the Singapore 2027 public holidays in the app are not the 12 compared with MOM%',
  'with Vesak Day missing the run is refused');
select pg_temp.check(not exists (select 1 from public.therapy_calendar_coverage where country_code = 'SG' and year = 2027),
  'and nothing is marked');
rollback;
