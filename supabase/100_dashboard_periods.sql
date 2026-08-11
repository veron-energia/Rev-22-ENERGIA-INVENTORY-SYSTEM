-- =====================================================================
-- ENERGIA — DASHBOARD SALES BY PERIOD
--
-- dashboard_summary() only ever reported TODAY. This adds daily, weekly,
-- monthly, all-time and an arbitrary date range, with a comparison against the
-- preceding period of the same length so a figure has something to be judged
-- against.
--
-- All dates are resolved in the store timezone via sg_today(), so "today" means
-- today in Singapore rather than in UTC — a distinction that otherwise moves
-- eight hours of evening trade into the wrong day.
--
-- Additive and idempotent. Run AFTER 99.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- Resolve a named period into a date range.
--   'day' | 'week' | 'month' | 'year' | 'all' | 'custom'
-- Week starts Monday, which is how retail weeks are usually read here.
-- ---------------------------------------------------------------------
create or replace function public.resolve_period(
  p_period text, p_from date default null, p_to date default null)
returns table(date_from date, date_to date, prev_from date, prev_to date, label text)
language plpgsql stable as $function$
declare v_today date := public.sg_today(); v_f date; v_t date; v_len integer;
begin
  case lower(coalesce(p_period,'day'))
    when 'day'   then v_f := v_today; v_t := v_today;
    when 'week'  then v_f := date_trunc('week', v_today)::date; v_t := v_today;
    when 'month' then v_f := date_trunc('month', v_today)::date; v_t := v_today;
    when 'year'  then v_f := date_trunc('year', v_today)::date; v_t := v_today;
    when 'all'   then v_f := null; v_t := null;
    when 'custom' then
      v_f := p_from; v_t := coalesce(p_to, v_today);
      if v_f is null then raise exception 'A start date is required for a custom range'; end if;
      if v_t < v_f then raise exception 'The end date cannot be before the start date'; end if;
    else raise exception 'Unknown period "%"', p_period;
  end case;

  -- The preceding window of the same length, for comparison.
  if v_f is not null then
    v_len := (v_t - v_f) + 1;
    return query select v_f, v_t, (v_f - v_len)::date, (v_f - 1)::date,
      case lower(coalesce(p_period,'day'))
        when 'day' then 'Today' when 'week' then 'This week'
        when 'month' then 'This month' when 'year' then 'This year'
        else to_char(v_f,'DD Mon YYYY') || ' – ' || to_char(v_t,'DD Mon YYYY') end;
  else
    return query select null::date, null::date, null::date, null::date, 'All time'::text;
  end if;
end $function$;

-- ---------------------------------------------------------------------
-- Sales for a period, optionally for one store.
--
-- Owners and Managers see every store; a staff member is restricted to the
-- stores they are assigned to, so the dashboard cannot become a way to read
-- another store's takings.
-- ---------------------------------------------------------------------
create or replace function public.dashboard_sales(
  p_period text default 'day', p_from date default null, p_to date default null,
  p_store_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare
  r record; v_role text := public.current_user_role();
  v_sales numeric; v_count integer; v_disc numeric; v_items integer;
  v_prev numeric; v_prev_count integer; v_avg numeric;
begin
  select * into r from public.resolve_period(p_period, p_from, p_to);

  if p_store_id is not null and not public.user_has_store_access(p_store_id) then
    raise exception 'You do not have access to that store';
  end if;

  with scoped as (
    select i.* from public.invoices i
     where i.status = 'paid'
       and (p_store_id is null or i.store_id = p_store_id)
       -- Staff see only their own stores.
       and (v_role in ('owner','admin','manager')
            or exists (select 1 from public.user_store_assignments usa
                        where usa.user_id = auth.uid() and usa.store_id = i.store_id))
  )
  select
    coalesce(sum(case when r.date_from is null
                       or (s.paid_at at time zone 'Asia/Singapore')::date between r.date_from and r.date_to
                      then s.total_amount end), 0),
    coalesce(count(case when r.date_from is null
                       or (s.paid_at at time zone 'Asia/Singapore')::date between r.date_from and r.date_to
                      then 1 end), 0),
    coalesce(sum(case when r.date_from is null
                       or (s.paid_at at time zone 'Asia/Singapore')::date between r.date_from and r.date_to
                      then s.discount_total end), 0),
    coalesce(sum(case when r.date_from is not null
                       and (s.paid_at at time zone 'Asia/Singapore')::date between r.prev_from and r.prev_to
                      then s.total_amount end), 0),
    coalesce(count(case when r.date_from is not null
                       and (s.paid_at at time zone 'Asia/Singapore')::date between r.prev_from and r.prev_to
                      then 1 end), 0)
  into v_sales, v_count, v_disc, v_prev, v_prev_count
  from scoped s;

  select coalesce(sum(ii.quantity), 0) into v_items
    from public.invoice_items ii
    join public.invoices i on i.id = ii.invoice_id
   where i.status = 'paid'
     and (p_store_id is null or i.store_id = p_store_id)
     and (r.date_from is null
          or (i.paid_at at time zone 'Asia/Singapore')::date between r.date_from and r.date_to)
     and (v_role in ('owner','admin','manager')
          or exists (select 1 from public.user_store_assignments usa
                      where usa.user_id = auth.uid() and usa.store_id = i.store_id));

  v_avg := case when v_count > 0 then round(v_sales / v_count, 2) else 0 end;

  return jsonb_build_object(
    'period', lower(coalesce(p_period,'day')),
    'label', r.label,
    'date_from', r.date_from, 'date_to', r.date_to,
    'sales', round(v_sales, 2),
    'invoice_count', v_count,
    'items_sold', v_items,
    'discount_total', round(v_disc, 2),
    'average_invoice', v_avg,
    'previous_sales', round(v_prev, 2),
    'previous_count', v_prev_count,
    -- Null rather than a fabricated 100% when there is nothing to compare to.
    'change_percent', case when r.date_from is null or v_prev = 0 then null
                           else round((v_sales - v_prev) / v_prev * 100, 1) end,
    'store_id', p_store_id);
end $function$;

-- ---------------------------------------------------------------------
-- Sales per day across the period, for a chart.
-- ---------------------------------------------------------------------
create or replace function public.dashboard_sales_series(
  p_period text default 'month', p_from date default null, p_to date default null,
  p_store_id uuid default null)
returns table(day date, sales numeric, invoice_count integer)
language plpgsql stable security definer set search_path to 'public' as $function$
declare r record; v_role text := public.current_user_role(); v_start date;
begin
  select * into r from public.resolve_period(p_period, p_from, p_to);
  if p_store_id is not null and not public.user_has_store_access(p_store_id) then
    raise exception 'You do not have access to that store';
  end if;

  -- All time still needs a start: use the first paid invoice.
  v_start := coalesce(r.date_from,
    (select min((i.paid_at at time zone 'Asia/Singapore')::date)
       from public.invoices i where i.status = 'paid'));
  if v_start is null then return; end if;

  return query
  select d::date,
         coalesce(sum(i.total_amount), 0)::numeric,
         count(i.id)::integer
    from generate_series(v_start, coalesce(r.date_to, public.sg_today()), interval '1 day') d
    left join public.invoices i
      on i.status = 'paid'
     and (i.paid_at at time zone 'Asia/Singapore')::date = d::date
     and (p_store_id is null or i.store_id = p_store_id)
     and (v_role in ('owner','admin','manager')
          or exists (select 1 from public.user_store_assignments usa
                      where usa.user_id = auth.uid() and usa.store_id = i.store_id))
   group by d
   order by d;
end $function$;

-- Sales split by store for the period, so an Owner can compare them.
create or replace function public.dashboard_sales_by_store(
  p_period text default 'month', p_from date default null, p_to date default null)
returns table(store_id uuid, store_name text, sales numeric, invoice_count integer)
language plpgsql stable security definer set search_path to 'public' as $function$
declare r record; v_role text := public.current_user_role();
begin
  select * into r from public.resolve_period(p_period, p_from, p_to);
  return query
  select s.id, s.name,
         coalesce(sum(i.total_amount), 0)::numeric,
         count(i.id)::integer
    from public.stores s
    left join public.invoices i
      on i.store_id = s.id and i.status = 'paid'
     and (r.date_from is null
          or (i.paid_at at time zone 'Asia/Singapore')::date between r.date_from and r.date_to)
   where s.deleted_at is null
     and (v_role in ('owner','admin','manager')
          or exists (select 1 from public.user_store_assignments usa
                      where usa.user_id = auth.uid() and usa.store_id = s.id))
   group by s.id, s.name
   order by coalesce(sum(i.total_amount), 0) desc, s.name;
end $function$;

notify pgrst, 'reload schema';
