-- =====================================================================
-- ENERGIA — DAILY TAKINGS BY PAYMENT METHOD
--
-- A cross-tab for the Invoices page: one row per day, one column per payment
-- method, with totals down the right and along the bottom.
--
-- Dated by WHEN THE PAYMENT WAS TAKEN, not by the invoice date. The two can
-- differ — a partially paid invoice raised on Monday and settled on Tuesday
-- puts money in the till on Tuesday — and this is a report of daily takings, so
-- the day the money arrived is the one that matters.
--
-- Every day in the range appears, including days with no takings, so a gap is
-- visibly zero rather than a missing row someone has to notice.
--
-- Refunds are NOT netted off here: this reports what was collected. Refunds
-- have their own records and their own dates, and mixing them in would make a
-- day's figure disagree with the payments actually recorded against it.
--
-- Additive and idempotent. Run AFTER 126.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. The methods that appear as columns, in a stable order.
--
--    Only methods that actually took money in the range, so the sheet is not
--    padded with columns of zeroes for methods no longer in use.
-- ---------------------------------------------------------------------
create or replace function public.payment_methods_in_range(
  p_from date default null, p_to date default null, p_store_id uuid default null)
returns table(payment_method_id uuid, method_name text, is_wallet_credit boolean)
language sql stable security definer set search_path to 'public' as $function$
  select pm.id, pm.name, coalesce(pm.is_wallet_credit, false)
    from public.payment_methods pm
   where exists (
     select 1
       from public.invoice_payments ip
       join public.invoices i on i.id = ip.invoice_id
      where ip.payment_method_id = pm.id
        and i.deleted_at is null
        and (p_store_id is null or i.store_id = p_store_id)
        and (p_from is null or (ip.created_at at time zone 'Asia/Singapore')::date >= p_from)
        and (p_to   is null or (ip.created_at at time zone 'Asia/Singapore')::date <= p_to)
   )
   order by coalesce(pm.is_wallet_credit, false), pm.name
$function$;

-- ---------------------------------------------------------------------
-- 2. The figures: one row per day and method.
--
--    Returned long rather than pivoted, because the columns are not known in
--    advance. The caller pivots, which also keeps the column order under the
--    control of payment_methods_in_range() above.
-- ---------------------------------------------------------------------
create or replace function public.daily_payments_by_method(
  p_from date default null, p_to date default null, p_store_id uuid default null)
returns table(pay_date date, payment_method_id uuid, method_name text,
              amount numeric, payment_count integer)
language sql stable security definer set search_path to 'public' as $function$
  with bounds as (
    select
      coalesce(p_from, (select min((ip.created_at at time zone 'Asia/Singapore')::date)
                          from public.invoice_payments ip
                          join public.invoices i on i.id = ip.invoice_id
                         where i.deleted_at is null
                           and (p_store_id is null or i.store_id = p_store_id)),
               public.sg_today()) as d_from,
      coalesce(p_to, public.sg_today()) as d_to
  ),
  days as (
    select generate_series(b.d_from, b.d_to, interval '1 day')::date as d from bounds b
  ),
  methods as (
    select * from public.payment_methods_in_range(p_from, p_to, p_store_id)
  ),
  taken as (
    select (ip.created_at at time zone 'Asia/Singapore')::date as d,
           ip.payment_method_id as mid,
           sum(ip.amount) as amt,
           count(*)::integer as n
      from public.invoice_payments ip
      join public.invoices i on i.id = ip.invoice_id
     where i.deleted_at is null
       and (p_store_id is null or i.store_id = p_store_id)
       and (p_from is null or (ip.created_at at time zone 'Asia/Singapore')::date >= p_from)
       and (p_to   is null or (ip.created_at at time zone 'Asia/Singapore')::date <= p_to)
     group by 1, 2
  )
  -- Every day crossed with every method, so a day with no takings still has a
  -- row of zeroes rather than vanishing from the sheet.
  select d.d, m.payment_method_id, m.method_name,
         round(coalesce(t.amt, 0), 2), coalesce(t.n, 0)
    from days d
    cross join methods m
    left join taken t on t.d = d.d and t.mid = m.payment_method_id
   order by d.d, m.method_name
$function$;

notify pgrst, 'reload schema';
