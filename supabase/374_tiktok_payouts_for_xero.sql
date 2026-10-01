-- 374_tiktok_payouts_for_xero.sql
--
-- TIKTOK PAYOUTS FOR XERO (asked for on 1 Oct 2026; the owner's rules)
--
--   TikTok pays the shop's balance into the bank every Wednesday. Each payout
--   is everything TikTok settled from the Thursday before through that
--   Wednesday, less the ads (GMV Pay) taken from the balance in that week.
--   TikTok's own files show this to the cent for every payout of August 2026
--   (5, 12, 19 and 26 Aug); together they are August's Total Income.
--
--   tiktok_xero_payouts(year, month) gives a reporting month's Wednesdays,
--   each with the week it pays out, worked out from the settled lines the app
--   counts:
--     - the week is Thursday to Wednesday by TikTok's settled date in
--       Singapore; a line settled on a Wednesday is in that Wednesday's payout.
--       A reporting month ends on its last Wednesday (210), so its weeks are
--       exactly its Wednesdays' weeks;
--     - sales, fees and ads are Total Revenue, Total Fee and Total Expense
--       (210, the same rows and the same sums), and the payout is Total Income.
--       So a month's payouts add up to its Total Income;
--     - all stores together: TikTok pays the whole shop at once, whichever
--       store a file was imported into.
--   For each week it also says what a person should know before exporting it:
--     - whether its Wednesday is over (today's and later ones are not exported);
--     - days of the week that no confirmed settlement file reaches (a file
--       reaches from its first to its last settled date), so a missing file
--       shows rather than a short invoice;
--     - lines left unticked at confirmation (368), which it does not count;
--     - lines of an unknown TikTok type, which add nothing;
--     - lines moving money in or out of the TikTok balance (reserves,
--       withdrawals, financing), which are not sales, fees or ads;
--     - lines not in SGD.
--   It also gives settled lines with no date, which are in no week, and the
--   month's Total Income for every store as tiktok_settlement_totals works it
--   out, to compare with.
--
-- Read only, and for active Owners and Managers only, like the invoice Xero
-- export.
-- Nothing existing is changed.

set lock_timeout = '5s';

do $$ begin
  if to_regprocedure('public.tiktok_settlement_left_out_rows(uuid)') is null then
    raise exception '374: apply 368 (TikTok settlement lines) first'; end if;
end $$;

create or replace function public.tiktok_xero_payouts(p_year integer, p_month integer)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $f$
declare
  per record; rng record;
  v_today date := public.sg_today();
  v_weeks jsonb; v_undated integer;
begin
  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_active and p.deleted_at is null
                   and p.role in ('owner', 'manager')) then
    raise exception 'Only an Owner or Manager can export TikTok payouts for Xero'; end if;
  if p_month is null or p_month not between 1 and 12 or p_year is null or p_year not between 2000 and 2100 then
    raise exception 'Choose a reporting month'; end if;
  select * into per from public.tiktok_settlement_period(p_year, p_month);
  select * into rng from public.tiktok_settlement_period_range(p_year, p_month);

  with wk as (
    -- The month's Wednesdays: it starts on a Thursday and ends on a Wednesday.
    select w::date as payout_date
      from generate_series((per.start_date + ((3 - extract(isodow from per.start_date)::int + 7) % 7))::timestamp,
                           per.end_date::timestamp, interval '7 days') w
  ),
  e as (
    -- The rows tiktok_settlement_totals counts, over the same range.
    select x.*, (x.settled_time at time zone 'Asia/Singapore')::date as d
      from public.tiktok_settlement_eligible(null) x
     where x.settled_time is not null
       and x.settled_time >= rng.start_at
       and x.settled_time <  rng.end_at_exclusive
  ),
  ew as (
    select e.*, e.d + ((3 - extract(isodow from e.d)::int + 7) % 7) as payout_date from e
  ),
  agg as (
    select payout_date,
           count(*)::int as row_count,
           coalesce(sum(case when category in ('sale','sale_refund') then revenue_amount else 0 end), 0) as revenue,
           coalesce(sum(case when category in ('sale','sale_refund') then -fee_amount
                             when category in ('fee','fee_reversal')
                               then -coalesce(nullif(fee_amount, 0), adjustment_amount)
                             else 0 end), 0) as fee,
           coalesce(sum(case when category in ('ad_expense','expense_reversal')
                             then -adjustment_amount else 0 end), 0) as expense,
           coalesce(sum(settlement_amount), 0) as tiktok_net,
           count(*) filter (where category = 'unknown')::int as unknown_count,
           count(*) filter (where category = 'balance_movement')::int as balance_movement_count,
           count(*) filter (where currency is not null and currency <> 'SGD')::int as other_currency_count
      from ew group by payout_date
  ),
  lo as (
    -- Left out at confirmation, as tiktok_settlement_totals counts them (368).
    select d + ((3 - extract(isodow from d)::int + 7) % 7) as payout_date,
           count(*)::int as n, coalesce(sum(amount), 0) as amount
      from (select (r.settled_time at time zone 'Asia/Singapore')::date as d,
                   r.settlement_amount - coalesce(p.settlement_amount, 0) as amount
              from public.tiktok_settlement_left_out_rows(null) l
              join public.tiktok_settlement_rows r on r.id = l.id
              left join public.tiktok_settlement_rows p
                on p.id = r.previous_row_id and r.staging_status = 'Updated — Requires Confirmation'
             where l.k <= l.left_out
               and r.settled_time >= rng.start_at
               and r.settled_time <  rng.end_at_exclusive) z
     group by 1
  ),
  files as (
    -- What each confirmed settlement file reaches: its first to last settled day.
    select min((r.settled_time at time zone 'Asia/Singapore')::date) as first_day,
           max((r.settled_time at time zone 'Asia/Singapore')::date) as last_day
      from public.tiktok_import_batches b
      join public.tiktok_settlement_rows r on r.batch_id = b.id
     where b.status = 'confirmed' and b.deleted_at is null and b.file_kind = 'settlement'
       and r.settled_time is not null
     group by b.id
  ),
  gaps as (
    select wk.payout_date,
           array_agg(g.day::date order by g.day) as days
      from wk cross join lateral generate_series((wk.payout_date - 6)::timestamp, wk.payout_date::timestamp, interval '1 day') g(day)
     where not exists (select 1 from files f where g.day::date between f.first_day and f.last_day)
     group by wk.payout_date
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'payout_date', wk.payout_date,
           'week_start', wk.payout_date - 6,
           'week_end', wk.payout_date,
           'finished', wk.payout_date < v_today,
           'row_count', coalesce(a.row_count, 0),
           'revenue', round(coalesce(a.revenue, 0), 2),
           'fee', round(coalesce(a.fee, 0), 2),
           'expense', round(coalesce(a.expense, 0), 2),
           'payout', round(coalesce(a.revenue - a.fee - a.expense, 0), 2),
           'tiktok_net', round(coalesce(a.tiktok_net, 0), 2),
           'unknown_count', coalesce(a.unknown_count, 0),
           'balance_movement_count', coalesce(a.balance_movement_count, 0),
           'other_currency_count', coalesce(a.other_currency_count, 0),
           'left_out_count', coalesce(lo.n, 0),
           'left_out_settlement', round(coalesce(lo.amount, 0), 2),
           'uncovered_days', coalesce(to_jsonb(gp.days), '[]'::jsonb))
         order by wk.payout_date), '[]'::jsonb)
    into v_weeks
    from wk left join agg a using (payout_date) left join lo using (payout_date) left join gaps gp using (payout_date);

  select count(*)::int into v_undated from public.tiktok_settlement_eligible(null) where settled_time is null;

  return jsonb_build_object(
    'year', p_year, 'month', p_month,
    'period_start', per.start_date, 'period_end', per.end_date,
    'today', v_today, 'timezone', 'Asia/Singapore',
    'weeks', v_weeks,
    'undated_count', v_undated,
    'income', (select round(coalesce(sum((w->>'payout')::numeric), 0), 2) from jsonb_array_elements(v_weeks) w),
    -- The month's Total Income for every store, worked out by tiktok_settlement_totals.
    'month_income', (public.tiktok_settlement_totals(p_year, p_month, null)->>'income')::numeric);
end $f$;

revoke all on function public.tiktok_xero_payouts(integer, integer) from public, anon;
grant execute on function public.tiktok_xero_payouts(integer, integer) to authenticated, service_role;

notify pgrst, 'reload schema';
