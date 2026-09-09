-- =====================================================================
-- ENERGIA — SINGAPORE PUBLIC HOLIDAYS, 2026 AND 2027
--
-- Source: Ministry of Manpower, https://www.mom.gov.sg/employment-practices/
-- public-holidays — the gazetted list. Every date carries that source on the
-- row, so a later disagreement can be traced rather than argued about.
--
-- Each weekday stated by the source was recomputed from the date before this
-- file was written; all 26 agreed. A transcription slip here would silently
-- shorten or lengthen customers' access, so it was worth checking rather than
-- trusting the copy.
--
-- Sundays and their substitutes are BOTH recorded, on purpose:
--
--   Vesak Day      Sun 31 May 2026  →  observed Mon 1 Jun 2026
--   National Day   Sun 9 Aug 2026   →  observed Mon 10 Aug 2026
--   Deepavali      Sun 8 Nov 2026   →  observed Mon 9 Nov 2026
--   Chinese New Year Sun 7 Feb 2027 →  observed Mon 8 Feb 2027
--
-- The Sunday earns no replacement day — the business is closed on Sundays
-- anyway — and the Monday earns one. Recording only the Monday would lose the
-- reason; recording only the Sunday would lose the day the customer is owed.
--
-- This file seeds PUBLIC HOLIDAYS only. Company closures are entered by an
-- Owner or Manager in the Therapy page, because only they know about them.
--
-- Coverage is NOT marked verified by this file. A person confirms that in the
-- UI after checking the list against the gazette themselves; a migration
-- asserting its own correctness would defeat the point of recording coverage.
--
-- Additive and idempotent: re-running changes nothing, and it never touches an
-- existing entitlement. Expiry dates move only through the audited
-- recalculation in migration 220. Run AFTER 220.
-- =====================================================================

insert into public.therapy_closure_dates
  (closure_date, kind, name, country_code, observed_for, source, source_reference)
values
  -- 2026
  ('2026-01-01', 'public_holiday', 'New Year''s Day',        'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2026'),
  ('2026-02-17', 'public_holiday', 'Chinese New Year',       'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2026'),
  ('2026-02-18', 'public_holiday', 'Chinese New Year',       'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2026'),
  ('2026-03-21', 'public_holiday', 'Hari Raya Puasa',        'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2026'),
  ('2026-04-03', 'public_holiday', 'Good Friday',            'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2026'),
  ('2026-05-01', 'public_holiday', 'Labour Day',             'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2026'),
  ('2026-05-27', 'public_holiday', 'Hari Raya Haji',         'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2026'),
  ('2026-05-31', 'public_holiday', 'Vesak Day',              'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2026'),
  ('2026-06-01', 'public_holiday', 'Vesak Day (observed)',   'SG', '2026-05-31', 'mom.gov.sg', 'Gazetted public holidays 2026'),
  ('2026-08-09', 'public_holiday', 'National Day',           'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2026'),
  ('2026-08-10', 'public_holiday', 'National Day (observed)','SG', '2026-08-09', 'mom.gov.sg', 'Gazetted public holidays 2026'),
  ('2026-11-08', 'public_holiday', 'Deepavali',              'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2026'),
  ('2026-11-09', 'public_holiday', 'Deepavali (observed)',   'SG', '2026-11-08', 'mom.gov.sg', 'Gazetted public holidays 2026'),
  ('2026-12-25', 'public_holiday', 'Christmas Day',          'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2026'),
  -- 2027
  ('2027-01-01', 'public_holiday', 'New Year''s Day',        'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2027'),
  ('2027-02-06', 'public_holiday', 'Chinese New Year',       'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2027'),
  ('2027-02-07', 'public_holiday', 'Chinese New Year',       'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2027'),
  ('2027-02-08', 'public_holiday', 'Chinese New Year (observed)', 'SG', '2027-02-07', 'mom.gov.sg', 'Gazetted public holidays 2027'),
  ('2027-03-10', 'public_holiday', 'Hari Raya Puasa',        'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2027'),
  ('2027-03-26', 'public_holiday', 'Good Friday',            'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2027'),
  ('2027-05-01', 'public_holiday', 'Labour Day',             'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2027'),
  ('2027-05-17', 'public_holiday', 'Hari Raya Haji',         'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2027'),
  ('2027-05-20', 'public_holiday', 'Vesak Day',              'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2027'),
  ('2027-08-09', 'public_holiday', 'National Day',           'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2027'),
  ('2027-10-28', 'public_holiday', 'Deepavali',              'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2027'),
  ('2027-12-25', 'public_holiday', 'Christmas Day',          'SG', null,         'mom.gov.sg', 'Gazetted public holidays 2027')
on conflict do nothing;

-- The Islamic holidays (Hari Raya Puasa, Hari Raya Haji) are subject to
-- confirmation by sighting and have been revised before. They are recorded here
-- as gazetted; if either moves, correct it in the Therapy page and re-run the
-- recalculation preview, which will show exactly whose expiry changes.
do $$
declare v_2026 integer; v_2027 integer;
begin
  select count(*) into v_2026 from public.therapy_closure_dates
   where country_code = 'SG' and extract(year from closure_date) = 2026 and deleted_at is null;
  select count(*) into v_2027 from public.therapy_closure_dates
   where country_code = 'SG' and extract(year from closure_date) = 2027 and deleted_at is null;
  raise notice 'Singapore calendar: % dates in 2026, % in 2027.', v_2026, v_2027;
  raise notice 'Coverage is still unverified. Confirm each year in the Therapy page once you have checked it against the gazette.';
end $$;
