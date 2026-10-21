-- 423 data step: mark the Singapore 2027 holiday calendar as checked.
--
-- Why: the 12 Singapore public-holiday dates for 2027 are loaded, but the year
-- was never marked as checked, so every therapy period that runs into 2027
-- shows "calendar not verified". The Owner approved marking it checked after
-- a comparison with the official list (Q14, 9 Oct 2026).
--
-- The comparison (done 9 Oct 2026). Official source: Ministry of Manpower,
-- press release "Public holidays for 2027", 18 Jun 2026
-- (mom.gov.sg/newsroom/press-releases/2026/0618-public-holidays-for-2027),
-- and the MOM public holidays page (updated 19 Jun 2026).
--
--   Official (MOM)                         Loaded in the app (production)
--   New Year's Day      Fri 1 Jan 2027     1 Jan 2027                       same
--   Chinese New Year    Sat 6 Feb 2027     6 Feb 2027                       same
--   Chinese New Year    Sun 7 Feb 2027     7 Feb 2027                       same
--   (Mon 8 Feb 2027 is a public holiday,   8 Feb 2027, observed for 7 Feb   same
--    as 7 Feb is a Sunday)
--   Hari Raya Puasa     Wed 10 Mar 2027    10 Mar 2027                      same
--   Good Friday         Fri 26 Mar 2027    26 Mar 2027                      same
--   Labour Day          Sat 1 May 2027     1 May 2027                       same
--   Hari Raya Haji      Mon 17 May 2027    17 May 2027                      same
--   Vesak Day           Thu 20 May 2027    20 May 2027                      same
--   National Day        Mon 9 Aug 2027     9 Aug 2027                       same
--   Deepavali           Thu 28 Oct 2027    28 Oct 2027                      same
--   Christmas Day       Sat 25 Dec 2027    25 Dec 2027                      same
--
--   12 dates on each side, none missing and none extra. A holiday on a
--   Saturday gives no extra weekday, so 1 May and 25 Dec have none, as MOM
--   lists them.
--
-- What it does: checks that the Singapore 2027 public holidays in the app are
-- exactly these 12 dates (not deleted, for Singapore as a whole, 8 Feb
-- observed for 7 Feb), and stops without changing anything if they are not.
-- Then, only when c_apply is true, it records Singapore 2027 as checked in
-- therapy_calendar_coverage (region '*', the whole country, as the Holidays
-- page does) with the source and a note, and writes one audit row. The dates
-- themselves are not changed. Company closures are not read.
--
-- Run it as the database owner (the SQL editor, the MCP execute_sql tool, or
-- psql as postgres). First the PREVIEW below on its own: it changes nothing
-- and lists the dates compared. Then the DO block as it is (c_apply false): a
-- dry run that changes nothing and says what it would do. Then set c_apply to
-- true and run the DO block again. It is one statement, so it is atomic. A
-- second run changes nothing. It prints counts and dates only. It needs no
-- migration (423 does not touch these tables); "checked by" stays empty
-- because no one signed in did it, and the note says who approved it.
--
-- The DO block reports by notices. Through the MCP execute_sql tool, notices
-- are not shown: the dry run, the real run and a second run all return [].
-- A refusal is still shown, as an error. So run the PREVIEW first, and the
-- "To look afterwards" selects after. psql shows the notices.
--
-- To look afterwards:
--   select country_code, year, region, is_verified, source, confirmed_at, notes
--     from public.therapy_calendar_coverage where country_code = 'SG' order by year;
--   select public.therapy_calendar_gaps(date '2026-10-09', date '2027-10-31', 'SG', null);
--   -- expected: "verified": true

-- ── PREVIEW (read only; shows in every tool, the MCP one included) ──────────
-- Run this select on its own call. Expected: the 12 dates in the table above
-- (8 Feb observed for 7 Feb), country SG, region empty, and already_checked
-- empty or false. already_checked true: already done.
select d.closure_date, d.observed_for, d.country_code, d.region,
       (select c.is_verified from public.therapy_calendar_coverage c
         where c.country_code = 'SG' and c.year = 2027 and c.region = '*') as already_checked
  from public.therapy_closure_dates d
 where d.deleted_at is null and d.kind = 'public_holiday'
   and d.closure_date between date '2027-01-01' and date '2027-12-31'
   and (d.country_code = 'SG' or d.country_code is null)
 order by d.closure_date;

-- ── The change (a dry run while c_apply is false) ───────────────────────────
do $repair$
declare
  c_apply constant boolean := false;  -- set to true to record the check
  c_expected constant text :=
    '2027-01-01|2027-02-06|2027-02-07|2027-02-08>2027-02-07|2027-03-10|2027-03-26|2027-05-01|'
    '2027-05-17|2027-05-20|2027-08-09|2027-10-28|2027-12-25';
  c_source constant text := 'mom.gov.sg';
  c_reference constant text := 'MOM press release "Public holidays for 2027", 18 Jun 2026';
  c_notes constant text := 'The 12 dates were compared with the official MOM list on 9 Oct 2026 and all match. '
                           'Marked checked with the Owner''s approval (Q14, 9 Oct 2026).';
  v_found text; v_cov record;
begin
  select string_agg(d.closure_date::text || coalesce('>' || d.observed_for::text, ''), '|' order by d.closure_date)
    into v_found
    from public.therapy_closure_dates d
   where d.deleted_at is null and d.kind = 'public_holiday'
     and d.closure_date between date '2027-01-01' and date '2027-12-31'
     and (d.country_code = 'SG' or d.country_code is null);
  if v_found is distinct from c_expected then
    raise exception E'423 SG 2027: the Singapore 2027 public holidays in the app are not the 12 compared with MOM; nothing was changed.\n  expected %\n  found    %',
      c_expected, coalesce(v_found, '(none)');
  end if;
  if exists (select 1 from public.therapy_closure_dates d
              where d.deleted_at is null and d.kind = 'public_holiday' and d.country_code = 'SG'
                and d.closure_date between date '2027-01-01' and date '2027-12-31' and d.region is not null) then
    raise exception '423 SG 2027: a Singapore 2027 holiday has a region; nothing was changed'; end if;

  select * into v_cov from public.therapy_calendar_coverage
   where country_code = 'SG' and year = 2027 and region = '*';
  if found and v_cov.is_verified then
    raise notice '423 SG 2027: the 12 dates match; Singapore 2027 is already marked checked (source %). Nothing changed.', v_cov.source;
    return;
  end if;

  if not c_apply then
    raise notice '423 SG 2027 (dry run): the 12 dates match MOM''s list. Set c_apply to true to mark Singapore 2027 as checked. Nothing changed.';
    return;
  end if;

  insert into public.therapy_calendar_coverage
    (country_code, year, region, is_verified, source, source_reference, notes, confirmed_by, confirmed_at)
  values ('SG', 2027, '*', true, c_source, c_reference, c_notes, null, now())
  on conflict (country_code, year, region) do update
    set is_verified = true, source = excluded.source, source_reference = excluded.source_reference,
        notes = excluded.notes, confirmed_by = null, confirmed_at = excluded.confirmed_at;
  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by, actor_role, module, reason)
  values ('therapy_calendar_coverage', null, 'calendar_coverage_confirmed',
          case when v_cov.country_code is null then null
               else jsonb_build_object('is_verified', v_cov.is_verified, 'source', v_cov.source) end,
          jsonb_build_object('country', 'SG', 'year', 2027, 'region', '*', 'is_verified', true,
                             'source', c_source, 'source_reference', c_reference, 'dates', 12),
          null, 'system', 'therapy', c_notes);
  raise notice '423 SG 2027: the 12 dates match; Singapore 2027 is now marked checked against %.', c_source;
end $repair$;
