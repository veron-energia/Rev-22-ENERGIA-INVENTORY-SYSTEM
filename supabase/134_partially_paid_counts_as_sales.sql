-- =====================================================================
-- ENERGIA — PARTIALLY PAID SALES NOW COUNT, ON A CASH BASIS
--
-- Dashboard sales and the payment summary both filtered "status = 'paid'", so a
-- partially paid invoice contributed NOTHING — even though the customer had
-- handed over real money. A S$1,000 invoice with S$400 taken showed S$0 of
-- sales.
--
-- Two decisions, as specified:
--
--   * sales count WHAT WAS ACTUALLY RECEIVED, not what was invoiced. So that
--     invoice contributes S$400 while the balance is outstanding, and the
--     remaining S$600 counts later, on the day it is paid.
--   * the same basis applies to the Xero export (handled in the frontend).
--
-- This makes the reported figure a CASH BASIS one throughout: money in the till,
-- not money billed. It agrees with the Payment Summary, which has always
-- counted actual payments.
--
-- Credit is still excluded, per migration 128: paid_amount includes a wallet
-- credit payment, and that money arrived when the credit was bought.
--
-- So:  sales = paid_amount - credit_funded
--
-- For a fully paid invoice paid_amount equals total_amount, so nothing about
-- existing figures changes; only partially paid invoices start counting.
--
-- Additive and idempotent. Run AFTER 133.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Net sales follow the money received.
-- ---------------------------------------------------------------------
create or replace function public.invoice_net_sales(p_invoice_id uuid)
returns numeric language sql stable security definer set search_path to 'public' as $function$
  -- paid_amount, not total_amount: a partially paid invoice contributes what
  -- has actually been taken. Credit is netted off because it was counted when
  -- the credit was purchased.
  select greatest(round(
    coalesce((select i.paid_amount from public.invoices i where i.id = p_invoice_id), 0)
      - public.invoice_credit_funded(p_invoice_id), 2), 0)
$function$;

-- ---------------------------------------------------------------------
-- 2. Partially paid invoices are included wherever sales are counted.
--
--    Each function filters status = 'paid'; the filter is widened rather than
--    removed, so drafts, cancellations and refunds stay out.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text; v_name text; v_n integer := 0;
begin
  foreach v_name in array array[
    'dashboard_sales', 'dashboard_sales_series', 'dashboard_sales_by_store',
    'dashboard_credit_spend', 'dashboard_credit_by_store'
  ] loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_name;
    if v_def is null then raise notice '% not found', v_name; continue; end if;
    if position('''partially_paid''' in v_def) > 0 then
      raise notice '% already includes partially paid invoices', v_name; continue;
    end if;

    v_new := replace(v_def, 'i.status = ''paid''',
                            'i.status in (''paid'', ''partially_paid'')');
    v_new := replace(v_new, 'status = ''paid''',
                            'status in (''paid'', ''partially_paid'')');

    if position('''partially_paid''' in v_new) = 0 then
      raise notice '% has no status filter to widen', v_name; continue;
    end if;
    execute v_new;
    v_n := v_n + 1;
    raise notice '% now counts partially paid invoices', v_name;
  end loop;
  if v_n = 0 then raise notice 'No sales function needed widening'; end if;
end $patch$;

-- ---------------------------------------------------------------------
-- 3. Commission follows the same basis automatically.
--
--    earn_staff_commission() and the rebase both read invoice_net_sales(), so
--    a staff member now earns on what the customer has actually paid, and earns
--    the rest when the balance is settled. That is the consistent reading of
--    "commission on money received" and needs no separate change here.
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'earn_staff_commission'
       and p.prosrc like '%invoice_net_sales%'
  ) then
    raise notice 'NOTE: earn_staff_commission does not use invoice_net_sales — check migration 128';
  else
    raise notice 'Commission follows the same paid-amount basis';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. Prove the basis, so this fails here rather than in a report.
-- ---------------------------------------------------------------------
do $$
declare v_src text;
begin
  select prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'invoice_net_sales';
  if v_src is null or position('paid_amount' in v_src) = 0 then
    raise exception 'invoice_net_sales does not read paid_amount — partial payments would still be ignored';
  end if;
  raise notice 'Confirmed: sales count the amount actually received';
end $$;

notify pgrst, 'reload schema';
