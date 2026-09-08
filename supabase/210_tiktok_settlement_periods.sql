-- =====================================================================
-- 210_tiktok_settlement_periods.sql
--
-- TikTok settlement reporting: continuous monthly periods, a financial
-- classification with more resolution than txn_class, and the aggregates the
-- import page and the TikTok report both read.
--
-- Numbered 210 to stay clear of the in-flight invoice series (170-184) and of
-- this agent's earlier work (200, 201).
--
-- ADDITIVE ONLY. No existing table gains or loses a column, and no existing
-- function changes behaviour. In particular `tiktok_txn_class` is left exactly
-- as it is: migration 66's check constraint and every stored row depend on its
-- four values, so the finer categories live in a NEW function beside it rather
-- than as a redefinition.
--
-- Settlement processing moves no stock. Nothing here touches
-- tiktok_adjust_product_stock, tiktok_adjust_voucher_stock, or any inventory
-- table; the order lifecycle continues to govern stock on its own.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Periods
--
-- A reporting month ENDS on the last Wednesday of that month and STARTS the day
-- after the previous month's last Wednesday. Consecutive periods therefore tile
-- the calendar with no gap and no overlap, so every settled transaction falls in
-- exactly one month.
--
--   August 2026     30 Jul - 26 Aug
--   September 2026  27 Aug - 30 Sep   (September ends ON a Wednesday)
--   October 2026     1 Oct - 28 Oct   (so October starts on the 1st)
--
-- September is why the start is defined as "the day after the previous period's
-- end" rather than "the previous month's last Thursday": when a month ends on a
-- Wednesday, the naive reading overlaps the neighbouring period by a week.
--
-- Mirrored exactly by src/lib/tiktok/settlementPeriod.mjs; a test asserts the
-- two agree across a multi-year sweep.
-- ---------------------------------------------------------------------
create or replace function public.tiktok_last_wednesday(p_year integer, p_month integer)
returns date language sql immutable as $function$
  -- extract(isodow) is 1=Mon .. 7=Sun, so Wednesday is 3.
  select d - ((extract(isodow from d)::integer - 3 + 7) % 7)
  from (select (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date as d) s
$function$;

create or replace function public.tiktok_settlement_period(p_year integer, p_month integer)
returns table (start_date date, end_date date)
language sql immutable as $function$
  select
    public.tiktok_last_wednesday(
      case when p_month = 1 then p_year - 1 else p_year end,
      case when p_month = 1 then 12 else p_month - 1 end) + 1,
    public.tiktok_last_wednesday(p_year, p_month)
$function$;

-- The half-open instant range, in Singapore time: from the start of the first
-- day up to but NOT including the start of the day after the last day.
--
-- Half-open deliberately. A closed range written as `<= end 23:59:59` drops
-- anything in the final second, and drops more than that against a timestamp
-- with sub-second precision.
create or replace function public.tiktok_settlement_period_range(p_year integer, p_month integer)
returns table (start_at timestamptz, end_at_exclusive timestamptz)
language sql stable as $function$
  select (p.start_date::timestamp at time zone 'Asia/Singapore'),
         ((p.end_date + 1)::timestamp at time zone 'Asia/Singapore')
  from public.tiktok_settlement_period(p_year, p_month) p
$function$;

-- Which reporting month a settled instant belongs to.
create or replace function public.tiktok_reporting_month(p_settled timestamptz)
returns table (year integer, month integer)
language sql stable as $function$
  with d as (select (p_settled at time zone 'Asia/Singapore')::date as sgt_date)
  select y, m from d,
    lateral (select extract(year from sgt_date)::integer as y0, extract(month from sgt_date)::integer as m0) b,
    lateral (
      -- The candidate months a date can fall into: its own, and its neighbours.
      select y, m from (values
        (b.y0, b.m0),
        (case when b.m0 = 12 then b.y0 + 1 else b.y0 end, case when b.m0 = 12 then 1 else b.m0 + 1 end),
        (case when b.m0 = 1 then b.y0 - 1 else b.y0 end, case when b.m0 = 1 then 12 else b.m0 - 1 end)
      ) as c(y, m)
      where d.sgt_date between (select start_date from public.tiktok_settlement_period(c.y, c.m))
                           and (select end_date   from public.tiktok_settlement_period(c.y, c.m))
      limit 1
    ) pick
$function$;

-- ---------------------------------------------------------------------
-- 2. Financial classification
--
-- Finer than txn_class, which cannot tell an advertising payment from a bank
-- transfer -- both are 'finance' -- and so cannot answer "what did we spend".
--
-- Classified by documented economic meaning, not by whether a label contains a
-- word. "Affiliate Shop Ads commission" is commission on a sale, so it is a fee;
-- matching on "ads" alone would move real commission into advertising spend.
-- ---------------------------------------------------------------------
create or replace function public.tiktok_finance_category(
  p_type text, p_adjustment numeric default 0)
returns text language sql immutable as $function$
  with s as (select lower(coalesce(p_type, '')) as t,
                    coalesce(p_adjustment, 0) as adj),
       f as (select t, adj,
                    (t ~ 'refund|reversal|rebate|credited back|returned') as reversing
             from s)
  select case
    -- Advertising and operating payments, before the fee family so that
    -- "subscription fee" reads as an operating cost rather than a platform fee.
    when t like '%gmv payment for tiktok ads%' or t like '%payment for tiktok ads%'
      or t like '%advertising payment%' or t ~ '\yads? *(payment|top ?up|charge|spend)\y'
      or t like '%subscription fee%'
      then case when reversing or adj > 0 then 'expense_reversal' else 'ad_expense' end
    -- The fee family, including commissions, before the generic refund branch so
    -- "Affiliate commission refund" is a fee coming back rather than a customer
    -- refund -- they sit on opposite sides of the report.
    when t like '%commission%' or t like '%fee%' or t like '%penalt%' or t like '%fine%'
      then case when reversing or adj > 0 then 'fee_reversal' else 'fee' end
    -- Money between the seller's own balances: neither income nor expense.
    when t like '%withdraw%' or t like '%transfer%' or t like '%payout%'
      or t like '%remittance%' or t like '%reserve%' or t like '%hold release%'
      or t like '%loan%' or t like '%financing%' or t like '%repayment%'
      or t like '%deposit%'
      then 'balance_movement'
    when t like '%refund%' or t like '%return%' then 'sale_refund'
    when t = 'order' or t like '%order%' then 'sale'
    when t = '' then 'unknown'
    else 'unknown'
  end
  from f
$function$;

-- ---------------------------------------------------------------------
-- 3. Which rows count
--
-- Confirmed, current and not excluded. A PENDING order match still counts:
-- money that has settled is money received, and whether the order has been
-- matched to a local record is a separate question that must not erase it.
--
-- Staged, unconfirmed, excluded and superseded rows are all left out.
-- ---------------------------------------------------------------------
create or replace function public.tiktok_settlement_eligible(p_store_id uuid default null)
returns table (
  id uuid, store_id uuid, settled_time timestamptz, transaction_type text,
  category text, order_id text, adjustment_id text,
  revenue_amount numeric, fee_amount numeric, adjustment_amount numeric,
  settlement_amount numeric, currency text, match_status text
)
language sql stable security definer set search_path to 'public' as $function$
  select r.id, r.store_id, r.settled_time, r.transaction_type,
         public.tiktok_finance_category(r.transaction_type, r.adjustment_amount),
         r.order_id, r.adjustment_id,
         r.revenue_amount, r.fee_amount, r.adjustment_amount,
         r.settlement_amount, r.currency, r.match_status
    from public.tiktok_settlement_rows r
   where r.is_current
     and r.confirmed
     and not r.excluded
     and (p_store_id is null or r.store_id = p_store_id)
     -- Store visibility: an owner/manager sees every store, a staff member only
     -- the stores they are assigned to. Enforced here rather than left to the
     -- caller, so a report cannot widen its own scope.
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(r.store_id))
$function$;

-- ---------------------------------------------------------------------
-- 4. The reported figures
--
--   Total Revenue     after seller discounts and customer refunds, before fees
--   Total Fee         net transaction fees, excluding refunds and expenses
--   Total Settlement  Revenue - Fee          (BEFORE operating expenses)
--   Total Expense     advertising and operating payments, net of reversals
--   Total Income      Settlement - Expense
--
-- Total Settlement is intentionally NOT TikTok's own "Total settlement amount",
-- which already has advertising deducted. Both are returned so they can be
-- compared rather than confused, and tiktok_net_settlement is labelled as the
-- imported source total -- not as cash in the bank, which arrives separately
-- through withdrawals.
--
-- Aggregates the whole eligible set, never a page of it.
-- ---------------------------------------------------------------------
create or replace function public.tiktok_settlement_totals(
  p_year integer, p_month integer, p_store_id uuid default null)
returns jsonb
language sql stable security definer set search_path to 'public' as $function$
  with rng as (select * from public.tiktok_settlement_period_range(p_year, p_month)),
       per as (select * from public.tiktok_settlement_period(p_year, p_month)),
       e as (
         select * from public.tiktok_settlement_eligible(p_store_id) x, rng
          where x.settled_time is not null
            and x.settled_time >= rng.start_at
            and x.settled_time <  rng.end_at_exclusive
       ),
       agg as (
         select
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
           count(*) filter (where match_status = 'pending')::int as pending_match_count,
           count(distinct currency)::int as currency_count,
           coalesce(jsonb_object_agg(category, n) filter (where category is not null), '{}'::jsonb) as by_category
         from (select category, revenue_amount, fee_amount, adjustment_amount,
                      settlement_amount, currency, match_status,
                      count(*) over (partition by category) as n
                 from e) z
       ),
       -- Rows in this store's data with no usable settled date cannot be placed
       -- in any period. Reported so the caller can say the totals are incomplete
       -- rather than quietly showing a smaller number.
       undated as (
         select count(*)::int as n
           from public.tiktok_settlement_eligible(p_store_id)
          where settled_time is null
       )
  select jsonb_build_object(
    'year', p_year, 'month', p_month,
    'period_start', (select start_date from per),
    'period_end', (select end_date from per),
    'timezone', 'Asia/Singapore',
    'row_count', a.row_count,
    'revenue', round(a.revenue, 2),
    'fee', round(a.fee, 2),
    'settlement', round(a.revenue - a.fee, 2),
    'expense', round(a.expense, 2),
    'income', round((a.revenue - a.fee) - a.expense, 2),
    'tiktok_net_settlement', round(a.tiktok_net, 2),
    'by_category', a.by_category,
    'unknown_count', a.unknown_count,
    'balance_movement_count', a.balance_movement_count,
    'pending_match_count', a.pending_match_count,
    'currency_count', a.currency_count,
    'undated_count', u.n,
    -- Only a period with nothing awaiting a human is safe to describe as
    -- reconciled. Anything else must not read as "fully reconciled".
    'needs_review', (a.unknown_count > 0 or u.n > 0 or a.currency_count > 1)
  ) from agg a, undated u
$function$;

-- Daily breakdown on the same basis, for the report's day table and exports.
create or replace function public.tiktok_settlement_daily(
  p_year integer, p_month integer, p_store_id uuid default null)
returns table (settled_date date, row_count integer,
               revenue numeric, fee numeric, settlement numeric,
               expense numeric, income numeric)
language sql stable security definer set search_path to 'public' as $function$
  with rng as (select * from public.tiktok_settlement_period_range(p_year, p_month)),
       e as (
         select (x.settled_time at time zone 'Asia/Singapore')::date as d, x.*
           from public.tiktok_settlement_eligible(p_store_id) x, rng
          where x.settled_time is not null
            and x.settled_time >= rng.start_at
            and x.settled_time <  rng.end_at_exclusive
       )
  select d, count(*)::int,
         round(coalesce(sum(case when category in ('sale','sale_refund') then revenue_amount else 0 end), 0), 2),
         round(coalesce(sum(case when category in ('sale','sale_refund') then -fee_amount
                                 when category in ('fee','fee_reversal')
                                   then -coalesce(nullif(fee_amount, 0), adjustment_amount)
                                 else 0 end), 0), 2) as fee,
         round(coalesce(sum(case when category in ('sale','sale_refund') then revenue_amount else 0 end), 0)
             - coalesce(sum(case when category in ('sale','sale_refund') then -fee_amount
                                 when category in ('fee','fee_reversal')
                                   then -coalesce(nullif(fee_amount, 0), adjustment_amount)
                                 else 0 end), 0), 2),
         round(coalesce(sum(case when category in ('ad_expense','expense_reversal') then -adjustment_amount else 0 end), 0), 2),
         round(coalesce(sum(case when category in ('sale','sale_refund') then revenue_amount else 0 end), 0)
             - coalesce(sum(case when category in ('sale','sale_refund') then -fee_amount
                                 when category in ('fee','fee_reversal')
                                   then -coalesce(nullif(fee_amount, 0), adjustment_amount)
                                 else 0 end), 0)
             - coalesce(sum(case when category in ('ad_expense','expense_reversal') then -adjustment_amount else 0 end), 0), 2)
    from e group by d order by d
$function$;

-- ---------------------------------------------------------------------
-- 5. Historical dry run
--
-- Reports what applying these rules to existing confirmed data would change.
-- Read-only: it rewrites nothing, and it invents nothing to make a total look
-- tidy. Rows that cannot be placed are counted, not hidden.
-- ---------------------------------------------------------------------
create or replace function public.tiktok_settlement_diagnostic(p_store_id uuid default null)
returns jsonb
language sql stable security definer set search_path to 'public' as $function$
  with e as (select * from public.tiktok_settlement_eligible(p_store_id)),
       placed as (
         select x.*, (select year from public.tiktok_reporting_month(x.settled_time)) as ry,
                     (select month from public.tiktok_reporting_month(x.settled_time)) as rm,
                extract(year from (x.settled_time at time zone 'Asia/Singapore'))::int as cy,
                extract(month from (x.settled_time at time zone 'Asia/Singapore'))::int as cm
           from e x where x.settled_time is not null
       )
  select jsonb_build_object(
    'eligible_rows', (select count(*) from e),
    -- Rows whose reporting month differs from their plain calendar month: these
    -- move when the last-Wednesday rule is applied.
    'moving_period', (select count(*) from placed where ry is distinct from cy or rm is distinct from cm),
    -- Advertising that used to sit among settlement adjustments and now becomes
    -- an operating expense.
    'ads_reclassified_to_expense', (select count(*) from e where category in ('ad_expense','expense_reversal')),
    'missing_settled_date', (select count(*) from e where settled_time is null),
    'missing_revenue_or_fee', (select count(*) from e
                                where category in ('sale','sale_refund')
                                  and (revenue_amount is null or fee_amount is null)),
    'unknown_classification', (select count(*) from e where category = 'unknown'),
    'balance_movements_excluded', (select count(*) from e where category = 'balance_movement'),
    'currencies', (select coalesce(jsonb_agg(distinct currency), '[]'::jsonb) from e where currency is not null),
    'unknown_types', (select coalesce(jsonb_agg(distinct transaction_type), '[]'::jsonb)
                        from e where category = 'unknown'),
    -- A period cannot be called complete while any of these are outstanding.
    'requires_reimport', (select count(*) from e
                           where settled_time is null
                              or (category in ('sale','sale_refund') and revenue_amount is null))
  )
$function$;

-- ---------------------------------------------------------------------
-- 6. Grants
-- ---------------------------------------------------------------------
revoke all on function public.tiktok_settlement_eligible(uuid) from public, anon;
revoke all on function public.tiktok_settlement_totals(integer,integer,uuid) from public, anon;
revoke all on function public.tiktok_settlement_daily(integer,integer,uuid) from public, anon;
revoke all on function public.tiktok_settlement_diagnostic(uuid) from public, anon;

grant execute on function public.tiktok_last_wednesday(integer,integer) to authenticated;
grant execute on function public.tiktok_settlement_period(integer,integer) to authenticated;
grant execute on function public.tiktok_settlement_period_range(integer,integer) to authenticated;
grant execute on function public.tiktok_reporting_month(timestamptz) to authenticated;
grant execute on function public.tiktok_finance_category(text,numeric) to authenticated;
grant execute on function public.tiktok_settlement_eligible(uuid) to authenticated;
grant execute on function public.tiktok_settlement_totals(integer,integer,uuid) to authenticated;
grant execute on function public.tiktok_settlement_daily(integer,integer,uuid) to authenticated;
grant execute on function public.tiktok_settlement_diagnostic(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 7. Verification
-- ---------------------------------------------------------------------
do $$
begin
  if (select end_date from public.tiktok_settlement_period(2026, 8)) <> date '2026-08-26'
     or (select start_date from public.tiktok_settlement_period(2026, 8)) <> date '2026-07-30' then
    raise exception 'migration 210: August 2026 period is wrong';
  end if;
  if (select start_date from public.tiktok_settlement_period(2026, 10)) <> date '2026-10-01' then
    raise exception 'migration 210: a month ending on a Wednesday must not overlap the next period';
  end if;
  if (select start_date from public.tiktok_settlement_period(2027, 1)) <> date '2026-12-31' then
    raise exception 'migration 210: the year boundary is wrong';
  end if;
  if public.tiktok_finance_category('Affiliate Shop Ads commission', -5) <> 'fee' then
    raise exception 'migration 210: a commission mentioning Ads must stay a fee';
  end if;
  if public.tiktok_finance_category('GMV payment for TikTok Ads', -283.30) <> 'ad_expense' then
    raise exception 'migration 210: advertising payment must classify as expense';
  end if;
  if public.tiktok_finance_category('Withdrawal', -500) <> 'balance_movement' then
    raise exception 'migration 210: a withdrawal must not be an expense';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 8. Put the existing TikTok payment reports on the settled-date basis
--
-- These were written as `coalesce(order_created_time, settled_time)` — order
-- created date PREFERRED, settled only as a fallback — and the daily report took
-- a `p_basis` argument defaulting to 'created'.
--
-- That is the wrong basis for a payment report. An order placed on 26 August and
-- settled on 31 August is money received in the September settlement period; on
-- the created basis it lands in August and the period never ties to what TikTok
-- actually paid. In the reference export, 24 of 44 rows have a created date that
-- differs from the settled date and 7 of them change reporting period.
--
-- The alternative basis is removed rather than re-defaulted: leaving a toggle
-- that produces a figure which cannot reconcile invites someone to use it.
--
-- Operational reporting — quantities sold, order statuses — is unaffected and
-- continues to work from the order lifecycle. It is a different question and
-- does not reconcile to settled money.
-- ---------------------------------------------------------------------
-- Migration 66 already defines this function, and this version adds a
-- finance_category column. `create or replace` cannot change a function's OUT
-- parameters, so the old one has to go first. Safe to drop: no view, function
-- or policy references it, and the grant is reissued at the end of this file.
drop function if exists public.report_tiktok_settlement(uuid, date, date);

create or replace function public.report_tiktok_settlement(
  p_store_id uuid default null, p_from date default null, p_to date default null
) returns table (
  row_id uuid, store_name text, financial_date date,
  order_adjustment_id text, txn_class text, transaction_type text,
  finance_category text,
  matched_order_id text, match_status text,
  settlement_amount numeric, revenue_amount numeric, fee_amount numeric,
  adjustment_amount numeric, refund_amount numeric, currency text,
  reconciled boolean, version_no integer
) language sql stable security definer set search_path = public as $function$
  select r.id, s.name,
         (r.settled_time at time zone 'Asia/Singapore')::date,
         coalesce(r.order_id, r.adjustment_id), r.txn_class, r.transaction_type,
         public.tiktok_finance_category(r.transaction_type, r.adjustment_amount),
         r.matched_order_id, r.match_status,
         r.settlement_amount, r.revenue_amount, r.fee_amount,
         r.adjustment_amount, r.refund_amount, r.currency,
         r.reconciled, r.version_no
    from public.tiktok_settlement_rows r
    join public.stores s on s.id = r.store_id
   where r.is_current and r.confirmed and not r.excluded
     and (p_store_id is null or r.store_id = p_store_id)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(r.store_id))
     -- Settled date only. A row with no settled date is still returned, so it can
     -- be seen and fixed rather than vanishing from the list it belongs on.
     and (p_from is null or (r.settled_time at time zone 'Asia/Singapore')::date >= p_from)
     and (p_to   is null or (r.settled_time at time zone 'Asia/Singapore')::date <= p_to)
   order by r.settled_time desc nulls first, r.row_no
$function$;

-- The 4-argument form (migration 67) carried the basis toggle; drop it so no
-- caller can keep asking for the created basis. The 3-argument form is dropped
-- too: it does not exist yet on a first run, but dropping it makes re-running
-- this file safe, since the new one adds expense and income columns.
drop function if exists public.report_tiktok_settlement_daily(uuid, date, date, text);
drop function if exists public.report_tiktok_settlement_daily(uuid, date, date);

create or replace function public.report_tiktok_settlement_daily(
  p_store_id uuid default null, p_from date default null, p_to date default null
) returns table (day date, transactions bigint, settlement numeric,
                 revenue numeric, fees numeric, expense numeric, income numeric)
language sql stable security definer set search_path = public as $function$
  select (r.settled_time at time zone 'Asia/Singapore')::date as day,
         count(*),
         round(coalesce(sum(r.settlement_amount), 0), 2),
         round(coalesce(sum(case when public.tiktok_finance_category(r.transaction_type, r.adjustment_amount)
                                      in ('sale','sale_refund') then r.revenue_amount else 0 end), 0), 2),
         round(coalesce(sum(case when public.tiktok_finance_category(r.transaction_type, r.adjustment_amount)
                                      in ('sale','sale_refund') then -r.fee_amount
                                 when public.tiktok_finance_category(r.transaction_type, r.adjustment_amount)
                                      in ('fee','fee_reversal')
                                   then -coalesce(nullif(r.fee_amount, 0), r.adjustment_amount)
                                 else 0 end), 0), 2),
         round(coalesce(sum(case when public.tiktok_finance_category(r.transaction_type, r.adjustment_amount)
                                      in ('ad_expense','expense_reversal') then -r.adjustment_amount else 0 end), 0), 2),
         round(coalesce(sum(case when public.tiktok_finance_category(r.transaction_type, r.adjustment_amount)
                                      in ('sale','sale_refund') then r.revenue_amount else 0 end), 0)
             - coalesce(sum(case when public.tiktok_finance_category(r.transaction_type, r.adjustment_amount)
                                      in ('sale','sale_refund') then -r.fee_amount
                                 when public.tiktok_finance_category(r.transaction_type, r.adjustment_amount)
                                      in ('fee','fee_reversal')
                                   then -coalesce(nullif(r.fee_amount, 0), r.adjustment_amount)
                                 else 0 end), 0)
             - coalesce(sum(case when public.tiktok_finance_category(r.transaction_type, r.adjustment_amount)
                                      in ('ad_expense','expense_reversal') then -r.adjustment_amount else 0 end), 0), 2)
    from public.tiktok_settlement_rows r
   where r.is_current and r.confirmed and not r.excluded
     and r.settled_time is not null
     and (p_store_id is null or r.store_id = p_store_id)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(r.store_id))
     and (p_from is null or (r.settled_time at time zone 'Asia/Singapore')::date >= p_from)
     and (p_to   is null or (r.settled_time at time zone 'Asia/Singapore')::date <= p_to)
   group by 1 order by 1
$function$;

-- Same reason as above: migration 67's version has no expense or income
-- column, so the row type changes and a replace is not enough.
drop function if exists public.report_tiktok_settlement_by_store(date, date);

create or replace function public.report_tiktok_settlement_by_store(
  p_from date default null, p_to date default null
) returns table (store_name text, transactions bigint, settlement numeric,
                 revenue numeric, fees numeric, expense numeric, income numeric,
                 pending_count bigint, unreconciled_count bigint)
language sql stable security definer set search_path = public as $function$
  with c as (
    select s.name, r.*,
           public.tiktok_finance_category(r.transaction_type, r.adjustment_amount) as cat
      from public.tiktok_settlement_rows r
      join public.stores s on s.id = r.store_id
     where r.is_current and r.confirmed and not r.excluded
       and r.settled_time is not null
       and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
            or public.user_has_store_access(r.store_id))
       and (p_from is null or (r.settled_time at time zone 'Asia/Singapore')::date >= p_from)
       and (p_to   is null or (r.settled_time at time zone 'Asia/Singapore')::date <= p_to)
  )
  select name, count(*),
         round(coalesce(sum(settlement_amount), 0), 2),
         round(coalesce(sum(case when cat in ('sale','sale_refund') then revenue_amount else 0 end), 0), 2),
         round(coalesce(sum(case when cat in ('sale','sale_refund') then -fee_amount
                                 when cat in ('fee','fee_reversal') then -coalesce(nullif(fee_amount, 0), adjustment_amount)
                                 else 0 end), 0), 2),
         round(coalesce(sum(case when cat in ('ad_expense','expense_reversal') then -adjustment_amount else 0 end), 0), 2),
         round(coalesce(sum(case when cat in ('sale','sale_refund') then revenue_amount else 0 end), 0)
             - coalesce(sum(case when cat in ('sale','sale_refund') then -fee_amount
                                 when cat in ('fee','fee_reversal') then -coalesce(nullif(fee_amount, 0), adjustment_amount)
                                 else 0 end), 0)
             - coalesce(sum(case when cat in ('ad_expense','expense_reversal') then -adjustment_amount else 0 end), 0), 2),
         count(*) filter (where match_status = 'pending'),
         count(*) filter (where reconciled is false)
    from c group by name order by name
$function$;

grant execute on function public.report_tiktok_settlement(uuid,date,date) to authenticated;
grant execute on function public.report_tiktok_settlement_daily(uuid,date,date) to authenticated;
grant execute on function public.report_tiktok_settlement_by_store(date,date) to authenticated;

do $$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'report_tiktok_settlement_daily'
                and pg_get_function_identity_arguments(p.oid) like '%text%') then
    raise exception 'migration 210: the created-date basis toggle is still present';
  end if;
  if (select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname='public' and p.proname='report_tiktok_settlement') like '%order_created_time%' then
    raise exception 'migration 210: report_tiktok_settlement still reads order_created_time';
  end if;
end $$;
