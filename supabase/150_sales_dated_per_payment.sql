-- =====================================================================
-- ENERGIA — INSTALMENTS ALL LANDED ON THE LATEST PAYMENT DATE
--
--   Invoice 5,000.  1,000 paid 01/01.  2,000 paid 01/02.
--   Reported: 3,000 on 01/02, nothing on 01/01.
--
-- Migration 135 gave every invoice a single sales date — paid_at, or its most
-- recent payment. That fixed partially paid invoices being ignored entirely,
-- but it dates the WHOLE invoice by ONE payment, so instalments collapse onto
-- the last one. I noted that limitation at the time; this removes it.
--
-- THE CHANGE: sales are measured from the PAYMENTS THEMSELVES, each on its own
-- date, rather than from the invoice gated by a single date.
--
--     sales(period) = payments received in that period,
--                     excluding wallet-credit methods
--
-- Credit stays excluded exactly as before — paying with credit records a
-- payment against a wallet-credit method, and those are left out, so the money
-- is still counted when the credit was BOUGHT rather than when it was spent.
--
-- For an invoice settled in one payment nothing changes at all: one payment,
-- one date, same figure. Only instalments move, and they move to where the
-- money actually arrived.
--
-- The Payment Summary export has always worked this way, which is why it and
-- the dashboard disagreed on instalments.
--
-- Additive and idempotent.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. What an invoice contributed WITHIN a period.
--
--    Replaces "the invoice's whole value, if its one date falls in range".
-- ---------------------------------------------------------------------
create or replace function public.invoice_net_sales_between(
  p_invoice_id uuid, p_from date, p_to date)
returns numeric language sql stable security definer set search_path to 'public' as $function$
  select round(coalesce(sum(ip.amount), 0), 2)
    from public.invoice_payments ip
    join public.payment_methods pm on pm.id = ip.payment_method_id
   where ip.invoice_id = p_invoice_id
     -- Wallet credit is not new money: it was counted when the credit was bought.
     and not coalesce(pm.is_wallet_credit, false)
     and (p_from is null
          or (ip.created_at at time zone 'Asia/Singapore')::date >= p_from)
     and (p_to is null
          or (ip.created_at at time zone 'Asia/Singapore')::date <= p_to)
$function$;

-- ---------------------------------------------------------------------
-- 2. Total real money taken in a period, across a store or all of them.
--
--    This is the figure the dashboard should show, and it is built from the
--    same rows the Payment Summary export reads — so the two now agree by
--    construction rather than by coincidence.
-- ---------------------------------------------------------------------
create or replace function public.sales_between(
  p_from date, p_to date, p_store_id uuid default null)
returns numeric language sql stable security definer set search_path to 'public' as $function$
  select round(coalesce(sum(ip.amount), 0), 2)
    from public.invoice_payments ip
    join public.payment_methods pm on pm.id = ip.payment_method_id
    join public.invoices i on i.id = ip.invoice_id
   where i.deleted_at is null
     and i.status in ('paid', 'partially_paid', 'completed_foc')
     and not coalesce(pm.is_wallet_credit, false)
     and (p_store_id is null or i.store_id = p_store_id)
     and (p_from is null or (ip.created_at at time zone 'Asia/Singapore')::date >= p_from)
     and (p_to   is null or (ip.created_at at time zone 'Asia/Singapore')::date <= p_to)
$function$;

-- ---------------------------------------------------------------------
-- 3. Point the dashboard at it.
--
--    The sums are of the form
--        sum(case when <date in range> then s.net_sales end)
--    where net_sales is the invoice's whole value. Each becomes the amount that
--    invoice contributed WITHIN that range, which needs no date test at all.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text; v_name text; v_n integer := 0;
begin
  foreach v_name in array array[
    'dashboard_sales', 'dashboard_sales_series', 'dashboard_sales_by_store'
  ] loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_name;
    if v_def is null then raise notice '% not found', v_name; continue; end if;
    if position('invoice_net_sales_between' in v_def) > 0 then
      raise notice '% already dates each payment separately', v_name; continue;
    end if;

    -- The current-period sums.
    v_new := replace(v_def,
      'case when r.date_from is null
                       or (public.invoice_sales_at(s.id) at time zone ''Asia/Singapore'')::date between r.date_from and r.date_to
                      then s.net_sales end',
      'public.invoice_net_sales_between(s.id, r.date_from, r.date_to)');

    -- The comparison-period sums.
    v_new := replace(v_new,
      'case when r.date_from is not null
                       and (public.invoice_sales_at(s.id) at time zone ''Asia/Singapore'')::date between r.prev_from and r.prev_to
                      then s.net_sales end',
      'public.invoice_net_sales_between(s.id, r.prev_from, r.prev_to)');

    -- Also handle the pre-135 form, where the date came straight from paid_at.
    -- Without this the patch would silently do nothing on a database where 135
    -- was never applied — which is exactly the kind of quiet no-op that has
    -- wasted a deploy here before.
    if v_new = v_def then
      v_new := replace(v_def,
        'case when r.date_from is null
                       or (s.paid_at at time zone ''Asia/Singapore'')::date between r.date_from and r.date_to
                      then s.net_sales end',
        'public.invoice_net_sales_between(s.id, r.date_from, r.date_to)');
      v_new := replace(v_new,
        'case when r.date_from is not null
                       and (s.paid_at at time zone ''Asia/Singapore'')::date between r.prev_from and r.prev_to
                      then s.net_sales end',
        'public.invoice_net_sales_between(s.id, r.prev_from, r.prev_to)');
    end if;

    if v_new = v_def then
      raise notice '% did not match either expected shape — left unchanged; use sales_between() directly', v_name;
      continue;
    end if;
    execute v_new;
    v_n := v_n + 1;
    raise notice '% now dates each payment separately', v_name;
  end loop;

  if v_n = 0 then
    raise notice 'NOTE: no dashboard function was changed. sales_between() is available and correct; tell me and I will match the exact shape.';
  end if;
end $patch$;

-- ---------------------------------------------------------------------
-- 4. Show any invoice whose payments span more than one day, so the effect of
--    this change can be seen rather than taken on trust.
-- ---------------------------------------------------------------------
create or replace function public.report_instalment_invoices()
returns table(invoice_no text, store_name text, total numeric,
              payments integer, first_payment date, last_payment date,
              spread_days integer)
language sql stable security definer set search_path to 'public' as $function$
  select i.invoice_no, s.name, i.total_amount,
         count(*)::integer,
         min((ip.created_at at time zone 'Asia/Singapore')::date),
         max((ip.created_at at time zone 'Asia/Singapore')::date),
         (max((ip.created_at at time zone 'Asia/Singapore')::date)
          - min((ip.created_at at time zone 'Asia/Singapore')::date))::integer
    from public.invoice_payments ip
    join public.invoices i on i.id = ip.invoice_id
    left join public.stores s on s.id = i.store_id
   where i.deleted_at is null
   group by i.id, i.invoice_no, s.name, i.total_amount
  having max((ip.created_at at time zone 'Asia/Singapore')::date)
       > min((ip.created_at at time zone 'Asia/Singapore')::date)
   order by 7 desc, 6 desc
$function$;

do $$
declare v_n integer;
begin
  select count(*) into v_n from public.report_instalment_invoices();
  if v_n > 0 then
    raise notice 'NOTE: % invoice(s) were paid across more than one day — their figures will now move to the correct dates. See report_instalment_invoices()', v_n;
  else
    raise notice 'No invoice has payments spanning more than one day';
  end if;
end $$;

notify pgrst, 'reload schema';
