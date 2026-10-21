-- 423 data step: Singapore as the holiday country of the therapy periods that
-- have none.
--
-- Why: a therapy period's expiry is lengthened by the public holidays of its
-- holiday country. A period with no country gets no holiday days, and
-- Recalculate (Therapy, Diagnostics) skips it ("no holiday country"). The
-- Owner said on 9 Oct 2026: set Singapore on those periods, so that their
-- expiry allows for Singapore public holidays.
--
-- Which periods. A period is what Recalculate works on: a purchased
-- unlimited-therapy unit that is active or scheduled, or a Legacy unlimited
-- therapy reward that is active or scheduled. Read on production (read only,
-- 9 Oct 2026, and again on 10 Oct 2026 after 415, the same), one of them has
-- no holiday country:
--
--   UTP-0000001  purchased, active, 6 months from Tue 1 Sep 2026
--                (its store is in Singapore)
--     expiry now     Sun 28 Feb 2027  (6 months, no holiday days)
--     expiry after   Fri  5 Mar 2027  (28 Feb + 5 days), for these Singapore
--                                      public holidays inside the period:
--       Mon  9 Nov 2026  Deepavali (observed; 8 Nov is a Sunday)
--       Fri 25 Dec 2026  Christmas Day
--       Fri  1 Jan 2027  New Year's Day
--       Sat  6 Feb 2027  Chinese New Year
--       Mon  8 Feb 2027  Chinese New Year (observed; 7 Feb is a Sunday)
--     A holiday on a Sunday adds nothing (the business is closed anyway). No
--     holiday falls in the 5 added days (1 to 5 Mar 2027), so it stops there.
--     The 2027 dates are the ones compared with MOM's list (see
--     423-sg-2027-holidays-checked.sql).
--
--   Not touched, because they are not periods: the 10 purchased units and 72
--   Legacy rewards still waiting to start (the country is chosen when one is
--   started), 5 active Legacy rewards taken as vouchers (no expiry), and the
--   53 cancelled Legacy rewards (over).
--
-- How: the normal way. The new expiry is therapy_adjusted_expiry() with
-- Singapore, as Recalculate and "assign a holiday calendar"
-- (therapy_assign_holiday_country) work it out. The period gets the same
-- fields that function sets (country, region none, source, base expiry,
-- days added, expiry, when calculated), and the same history row in
-- therapy_expiry_adjustments ("country_assigned", old and new expiry, the
-- reason below, the explanation of the dates), which the customer's therapy
-- page shows. One audit row per period as well. An expiry is never made
-- shorter. "Performed by" stays empty because no one signed in did it; the
-- reason says who approved it.
--
-- Guarded: it acts only while the periods with no country are exactly the
-- one above, with the same dates and the same result, and while the
-- functions it follows are the versions read on 9 Oct 2026 (still the same
-- on 10 Oct 2026). Otherwise it stops, changes nothing and shows what it
-- found.
--
-- Run it as the database owner (the SQL editor, the MCP execute_sql tool, or
-- psql as postgres), after 423, with the Owner's go-ahead. First the PREVIEW
-- below on its own: it changes nothing and lists what would change. Then the
-- DO block as it is (c_apply false): a dry run that changes nothing and says
-- what it would do. Then set c_apply to true and run the DO block again. It
-- is one statement, so it is atomic. A second run changes nothing. It prints
-- numbers and dates only.
--
-- The DO block reports by notices. Through the MCP execute_sql tool, notices
-- are not shown: the dry run, the real run and a second run all return [].
-- A refusal is still shown, as an error. So run the PREVIEW first, and the
-- "To look afterwards" selects after. psql shows the notices.
--
-- To look afterwards:
--   select entitlement_no, holiday_country, holiday_country_source, base_expiry_date,
--          closure_days_added, expiry_date
--     from public.purchased_therapy_entitlements where entitlement_no = 'UTP-0000001';
--   -- expected: SG, repair, 2027-02-28, 5, 2027-03-05
--   select action, old_expiry, new_expiry, days_added, reason
--     from public.therapy_expiry_adjustments a
--     join public.purchased_therapy_entitlements p on p.id = a.entitlement_id
--    where p.entitlement_no = 'UTP-0000001';

-- ── PREVIEW (read only; shows in every tool, the MCP one included) ──────────
-- Run this select on its own call. Expected on 9 and 10 Oct 2026: one row,
--   purchased | UTP-0000001 | active | 2026-09-01 | 6 | 2027-02-28 | 2027-03-05 | 5
-- No row: already done (every period has a holiday country).
select x.k, x.entitlement_no, x.status, x.activation_date, x.duration_months,
       x.expiry_date as expiry_now, c.adjusted_expiry as expiry_after, c.added_days
  from (select 'purchased'::text as k, p.entitlement_no, p.status, p.activation_date, p.duration_months, p.expiry_date
          from public.purchased_therapy_entitlements p
         where p.status in ('active', 'scheduled') and p.holiday_country is null
        union all
        select 'legacy', l.entitlement_no, l.status, l.activation_date, l.duration_months, l.expiry_date
          from public.therapy_entitlements l
         where l.status in ('active', 'scheduled') and coalesce(l.entitlement_kind, 'unlimited') = 'unlimited'
           and l.holiday_country is null) x
  left join lateral public.therapy_adjusted_expiry(x.activation_date, x.duration_months, 'SG', null, x.k) c on true
 order by x.entitlement_no;

-- ── The change (a dry run while c_apply is false) ───────────────────────────
do $repair$
declare
  c_apply constant boolean := false;  -- set to true to make the change
  -- kind|number|status|start|months|expiry now|expiry after|days added, as read on 9 Oct 2026.
  c_expected constant text := 'purchased|UTP-0000001|active|2026-09-01|6|2027-02-28|2027-03-05|5';
  c_country constant text := 'SG';
  c_source constant text := 'repair';
  c_reason constant text := 'Singapore set as the holiday country with the Owner''s approval (9 Oct 2026), '
                            'so the expiry allows for Singapore public holidays.';
  v_path text := current_setting('search_path');
  r record; v_found text; v_n integer; v_done integer := 0; v_tbl text; v_list text;
begin
  perform set_config('search_path', 'public', true);

  -- The functions this follows, as read on production on 9 Oct 2026.
  for r in select * from (values
    ('therapy_adjusted_expiry(date,integer,text,text,text)', '12d69563210a78965edb1c7d2e096173'),
    ('therapy_expiry_explanation(date,integer,text,text,text)', 'c1a269f01bd06c715234440261e263ae'),
    ('therapy_assign_holiday_country(text,uuid,text,text,text,text)', '6220b8efce6cb28a38c437f6b2d4f40c'),
    ('therapy_recalculation_preview(text,uuid)', 'a8b19d4965bc2e153cff00159234d3c0')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '423 holiday country: public.% is not the version read on 9 Oct 2026; nothing was changed. Re-read this script with the new version.', r.fn;
    end if;
  end loop;
  if not exists (select 1 from public.therapy_holiday_countries h
                  where h.code = c_country and h.is_active and not coalesce(h.requires_region, false)) then
    raise exception '423 holiday country: Singapore is not an active holiday country without regions; nothing was changed'; end if;

  -- The periods with no holiday country (as Recalculate picks them), and
  -- what the normal calculation gives them with Singapore.
  if to_regclass('pg_temp.t423_periods') is not null then
    drop table pg_temp.t423_periods; end if;
  create temp table t423_periods on commit drop as
  select x.k, x.tbl, x.id, x.entitlement_no, x.customer_id, x.store_id, x.status, x.activation_date,
         x.duration_months, x.holiday_region, x.expiry_date, x.base_expiry_date, x.closure_days_added,
         c.base_expiry, c.adjusted_expiry, c.added_days
    from (select 'purchased'::text as k, 'purchased_therapy_entitlements'::text as tbl, p.id, p.entitlement_no,
                 p.customer_id, p.store_id, p.status, p.activation_date, p.duration_months, p.holiday_region,
                 p.expiry_date, p.base_expiry_date, p.closure_days_added
            from public.purchased_therapy_entitlements p
           where p.status in ('active', 'scheduled') and p.holiday_country is null
          union all
          select 'legacy', 'therapy_entitlements', l.id, l.entitlement_no, l.customer_id, l.store_id, l.status,
                 l.activation_date, l.duration_months, l.holiday_region, l.expiry_date, l.base_expiry_date,
                 l.closure_days_added
            from public.therapy_entitlements l
           where l.status in ('active', 'scheduled') and coalesce(l.entitlement_kind, 'unlimited') = 'unlimited'
             and l.holiday_country is null) x
    left join lateral public.therapy_adjusted_expiry(x.activation_date, x.duration_months, c_country, null, x.k) c on true;

  select string_agg(concat_ws('|', t.k, t.entitlement_no, t.status, t.activation_date, t.duration_months,
                              t.expiry_date, t.adjusted_expiry, t.added_days), '; ' order by t.entitlement_no)
    into v_found from t423_periods t;

  if v_found is null then
    if exists (select 1 from public.therapy_expiry_adjustments a where a.reason = c_reason) then
      raise notice '423 holiday country: already done; every therapy period has a holiday country. Nothing changed.';
    else
      raise notice '423 holiday country: every therapy period already has a holiday country. Nothing changed.';
    end if;
    perform set_config('search_path', v_path, true);
    return;
  end if;
  if v_found is distinct from c_expected then
    raise exception E'423 holiday country: the periods with no holiday country are not the ones read on 9 Oct 2026; nothing was changed. Re-read them with the Owner.\n  expected %\n  found    %',
      c_expected, v_found;
  end if;
  -- Never shorter, and never nothing (the same rule as assigning a calendar on the page).
  if exists (select 1 from t423_periods t
              where t.adjusted_expiry is null or t.expiry_date is null or t.adjusted_expiry < t.expiry_date) then
    raise exception '423 holiday country: a period would get no expiry or a shorter one; nothing was changed'; end if;

  select string_agg(t.entitlement_no || ' ' || t.expiry_date || ' -> ' || t.adjusted_expiry
                    || ' (+' || t.added_days || ' holiday days)', '; ' order by t.entitlement_no)
    into v_list from t423_periods t;
  if not c_apply then
    raise notice '423 holiday country (dry run): would set Singapore on %. Set c_apply to true to make the change. Nothing changed.', v_list;
    perform set_config('search_path', v_path, true);
    return;
  end if;

  for r in select * from t423_periods order by entitlement_no loop
    -- The fields therapy_assign_holiday_country sets.
    execute format($f$
      update public.%I
         set holiday_country = $1, holiday_region = null, holiday_country_source = $2,
             base_expiry_date = $3, closure_days_added = $4, expiry_date = $5,
             expiry_calculated_at = now()
       where id = $6 and holiday_country is null and expiry_date = $7
    $f$, r.tbl)
      using c_country, c_source, r.base_expiry, r.added_days, r.adjusted_expiry, r.id, r.expiry_date;
    get diagnostics v_n = row_count;
    if v_n <> 1 then
      raise exception '423 holiday country: % changed while this ran; nothing was changed', r.entitlement_no; end if;

    -- The history row the customer's therapy page shows, as that function writes it.
    insert into public.therapy_expiry_adjustments (
      entitlement_kind, entitlement_id, customer_id, action, reason,
      old_country, new_country, old_region, new_region,
      old_expiry, new_expiry, base_expiry, days_added, performed_by, detail)
    values (r.k, r.id, r.customer_id, 'country_assigned', c_reason,
      null, c_country, r.holiday_region, null,
      r.expiry_date, r.adjusted_expiry, r.base_expiry, r.added_days, null,
      public.therapy_expiry_explanation(r.activation_date, r.duration_months, c_country, null, r.k));

    insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by, actor_role, module, reason, store_id)
    values (r.tbl, r.id, 'holiday_country_assigned',
            jsonb_build_object('holiday_country', null, 'expiry_date', r.expiry_date,
                               'base_expiry_date', r.base_expiry_date, 'closure_days_added', r.closure_days_added),
            jsonb_build_object('entitlement_no', r.entitlement_no, 'holiday_country', c_country,
                               'holiday_country_source', c_source, 'expiry_date', r.adjusted_expiry,
                               'base_expiry_date', r.base_expiry, 'closure_days_added', r.added_days),
            null, 'system', 'therapy', c_reason, r.store_id);
    v_done := v_done + 1;
  end loop;

  -- Afterwards: no period without a country, and each one is where
  -- Recalculate would put it (so a later Recalculate leaves it alone).
  if exists (select 1 from public.purchased_therapy_entitlements p
              where p.status in ('active', 'scheduled') and p.holiday_country is null)
     or exists (select 1 from public.therapy_entitlements l
                 where l.status in ('active', 'scheduled') and coalesce(l.entitlement_kind, 'unlimited') = 'unlimited'
                   and l.holiday_country is null) then
    raise exception '423 holiday country: a period still has no holiday country; nothing was changed'; end if;
  if exists (select 1 from t423_periods t
               join lateral public.therapy_adjusted_expiry(t.activation_date, t.duration_months, c_country, null, t.k) c on true
              where c.adjusted_expiry is distinct from t.adjusted_expiry) then
    raise exception '423 holiday country: a new expiry is not what Recalculate gives; nothing was changed'; end if;

  raise notice '423 holiday country: Singapore set on % period(s): %.', v_done, v_list;
  perform set_config('search_path', v_path, true);
end $repair$;
