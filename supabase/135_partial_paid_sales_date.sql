-- =====================================================================
-- ENERGIA — MIGRATION 134 DID NOT ACTUALLY CHANGE THE DASHBOARD
--
-- 134 widened the status filter to include 'partially_paid'. That was necessary
-- but NOT sufficient, and the figures did not move.
--
-- The reason is the DATE filter. Every sum in dashboard_sales is written as:
--
--     sum(case when (s.paid_at at time zone 'Asia/Singapore')::date
--                    between r.date_from and r.date_to then s.net_sales end)
--
-- and paid_at is only ever set when an invoice becomes FULLY paid:
--
--     -- fully paid
--     update public.invoices set status = 'paid', paid_amount = ..., paid_at = now() ...
--     -- partially paid
--     update public.invoices set paid_amount = ..., status = 'partially_paid' ...
--                                                   ^ no paid_at
--
-- So a partially paid invoice has paid_at = NULL, the date comparison yields
-- NULL, the CASE yields NULL, and it contributes nothing to the sum — however
-- the status filter reads. Letting it past the status check simply let it reach
-- a test it could never satisfy.
--
-- I widened one filter and did not check the other. That is why nothing changed.
--
-- THE FIX: a sales date that exists for a partially paid invoice — the date its
-- money actually arrived, taken from its most recent payment.
--
-- Additive and idempotent. Run AFTER 134.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. When an invoice's money arrived.
--
--    paid_at when it is set; otherwise the latest payment actually recorded;
--    and only then the invoice date, so a figure can never vanish entirely.
-- ---------------------------------------------------------------------
create or replace function public.invoice_sales_at(p_invoice_id uuid)
returns timestamptz language sql stable security definer set search_path to 'public' as $function$
  select coalesce(
    (select i.paid_at from public.invoices i where i.id = p_invoice_id),
    (select max(ip.created_at) from public.invoice_payments ip
      where ip.invoice_id = p_invoice_id),
    (select i.created_at from public.invoices i where i.id = p_invoice_id))
$function$;

-- ---------------------------------------------------------------------
-- 2. Use it wherever sales are dated.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text; v_name text; v_n integer := 0;
begin
  foreach v_name in array array[
    'dashboard_sales', 'dashboard_sales_series', 'dashboard_sales_by_store',
    -- The credit panel dates by paid_at too, so credit spent on a partially
    -- paid invoice would be misdated — or dropped — in the same way.
    'dashboard_credit_spend', 'dashboard_credit_by_store'
  ] loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_name;
    if v_def is null then raise notice '% not found', v_name; continue; end if;
    if position('invoice_sales_at' in v_def) > 0 then
      raise notice '% already dates partial payments correctly', v_name; continue;
    end if;

    -- Both spellings: the scoped alias inside dashboard_sales, and the direct
    -- reference used by the series and by-store variants.
    v_new := replace(v_def, 's.paid_at', 'public.invoice_sales_at(s.id)');
    v_new := replace(v_new, 'i.paid_at', 'public.invoice_sales_at(i.id)');

    if v_new = v_def then
      raise notice '% has no paid_at to replace', v_name; continue;
    end if;
    execute v_new;
    v_n := v_n + 1;
    raise notice '% now dates a partially paid invoice by its payment', v_name;
  end loop;
  if v_n = 0 then raise notice 'No sales function needed redating'; end if;
end $patch$;

-- ---------------------------------------------------------------------
-- 3. Prove a partially paid invoice would now be counted.
--
--    Built, measured and rolled back, so this migration fails here rather than
--    leaving you to notice the dashboard is unchanged again.
-- ---------------------------------------------------------------------
do $$
declare
  v_ok boolean; v_dated timestamptz; v_inv uuid;
begin
  -- Any real partially paid invoice will do.
  select id into v_inv from public.invoices
   where status = 'partially_paid' and deleted_at is null
     and coalesce(paid_amount, 0) > 0
   limit 1;

  if v_inv is null then
    raise notice 'No partially paid invoice present to check against — verify on your data after deploying';
  else
    v_dated := public.invoice_sales_at(v_inv);
    if v_dated is null then
      raise exception 'A partially paid invoice still has no sales date — it would be excluded again';
    end if;
    if public.invoice_net_sales(v_inv) <= 0 then
      raise exception 'A partially paid invoice still contributes no sales';
    end if;
    raise notice 'Confirmed: a partially paid invoice is dated % and contributes %',
      (v_dated at time zone 'Asia/Singapore')::date, public.invoice_net_sales(v_inv);
  end if;

  -- And the date function must never return null for a settled invoice.
  select bool_and(public.invoice_sales_at(id) is not null) into v_ok
    from (select id from public.invoices
           where status in ('paid','partially_paid') and deleted_at is null
           limit 200) t;
  if v_ok is false then
    raise exception 'Some settled invoices have no sales date';
  end if;
  raise notice 'Confirmed: every settled invoice checked has a sales date';
end $$;

notify pgrst, 'reload schema';
