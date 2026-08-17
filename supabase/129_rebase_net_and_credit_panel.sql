-- =====================================================================
-- ENERGIA — THE REBASE IGNORED CREDIT, AND CREDIT NEEDS ITS OWN FIGURE
--
-- 1. reearn_invoice_staff_commission() computes its own pool:
--
--        v_pool := round(coalesce(v_inv.total_amount, 0) * v_rate / 100.0, 2)
--                  - v_already_paid;
--
--    It never calls earn_staff_commission(), so migration 128's net-of-credit
--    basis never reached it. Settlement produced the right figure while
--    "Rebase unpaid" put the old one back.
--
--    Reproduced: a 500 invoice with 200 of credit earned 30.00 on settlement,
--    and 50.00 after rebasing.
--
-- 2. The dashboard reported sales net of credit, which is right, but gave no
--    way to see what the credit itself came to. Both figures are now
--    available, so a day can be read as "300 taken, 200 settled from credit"
--    rather than one number that quietly excludes the other.
--
-- Additive and idempotent. Run AFTER 128.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. The rebase pool uses the net figure.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'reearn_invoice_staff_commission';
  if v_def is null then raise exception 'reearn_invoice_staff_commission not found'; end if;
  if position('invoice_net_sales' in v_def) > 0 then
    raise notice 'the rebase already excludes credit'; return;
  end if;

  -- The commission pool, on the amount that was real money.
  v_new := replace(v_def,
    '  v_pool := round(coalesce(v_inv.total_amount, 0) * v_rate / 100.0, 2) - v_already_paid;',
    '  -- Net of credit, matching what settlement now earns. Without this the' || chr(10) ||
    '  -- rebase silently restored the pre-128 figure.' || chr(10) ||
    '  v_pool := round(public.invoice_net_sales(p_invoice_id) * v_rate / 100.0, 2) - v_already_paid;');

  -- The stored invoice_total should reflect the same basis, or the Commissions
  -- page shows a total the commission does not follow from.
  v_new := replace(v_new,
    '      coalesce(v_inv.total_amount, 0), round(1.0 / v_n, 6), v_rate,',
    '      public.invoice_net_sales(p_invoice_id), round(1.0 / v_n, 6), v_rate,');

  if position('invoice_net_sales' in v_new) = 0 then
    raise exception 'Could not apply the net basis to the rebase';
  end if;
  execute v_new;
  raise notice 'the rebase now excludes credit-funded amounts';
end $patch$;

-- The preview must model the same arithmetic, or it promises a figure the
-- rebase will not produce.
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'preview_commission_rebase_effect';
  if v_def is null then raise notice 'preview not found'; return; end if;
  if position('invoice_net_sales' in v_def) > 0 then
    raise notice 'the preview already excludes credit'; return;
  end if;

  v_new := replace(v_def,
    'greatest(round(coalesce(i.total_amount,0) * (select r from rate) / 100.0, 2)',
    'greatest(round(public.invoice_net_sales(i.id) * (select r from rate) / 100.0, 2)');

  if position('invoice_net_sales' in v_new) = 0 then
    raise notice 'the preview has no total to change — check it manually';
    return;
  end if;
  execute v_new;
  raise notice 'the rebase preview now excludes credit too';
end $patch$;

-- ---------------------------------------------------------------------
-- 2. What credit was spent, so the dashboard can show it separately.
-- ---------------------------------------------------------------------
create or replace function public.dashboard_credit_spend(
  p_period text default 'day', p_from date default null, p_to date default null,
  p_store_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare
  v_role text; v_from date; v_to date; v_label text;
  v_amount numeric; v_invoices integer;
begin
  select role into v_role from public.profiles where id = auth.uid();

  -- The same period arithmetic the sales panel uses, so the two agree.
  case coalesce(p_period, 'day')
    when 'day'    then v_from := public.sg_today(); v_to := v_from; v_label := 'Today';
    when 'week'   then v_from := public.sg_today() - extract(dow from public.sg_today())::integer;
                       v_to := public.sg_today(); v_label := 'This week';
    when 'month'  then v_from := date_trunc('month', public.sg_today())::date;
                       v_to := public.sg_today(); v_label := 'This month';
    when 'year'   then v_from := date_trunc('year', public.sg_today())::date;
                       v_to := public.sg_today(); v_label := 'This year';
    when 'custom' then v_from := p_from; v_to := coalesce(p_to, public.sg_today()); v_label := 'Custom range';
    else               v_from := null; v_to := null; v_label := 'All time';
  end case;

  select coalesce(sum(a.amount - coalesce(a.reversed_amount, 0)), 0),
         count(distinct a.invoice_id)::integer
    into v_amount, v_invoices
    from public.invoice_line_credit_allocations a
    join public.invoices i on i.id = a.invoice_id
   where i.status = 'paid'
     and i.deleted_at is null
     and (p_store_id is null or i.store_id = p_store_id)
     and (v_from is null or (i.paid_at at time zone 'Asia/Singapore')::date >= v_from)
     and (v_to   is null or (i.paid_at at time zone 'Asia/Singapore')::date <= v_to)
     -- Staff see only their own stores, matching dashboard_sales.
     and (v_role in ('owner','admin','manager')
          or exists (select 1 from public.user_store_assignments usa
                      where usa.user_id = auth.uid() and usa.store_id = i.store_id));

  return jsonb_build_object(
    'label', v_label,
    'credit_spent', round(coalesce(v_amount, 0), 2),
    'invoices', coalesce(v_invoices, 0));
end $function$;

-- Credit spend per store, to sit alongside the by-store sales bars.
create or replace function public.dashboard_credit_by_store(
  p_period text default 'day', p_from date default null, p_to date default null)
returns table(store_id uuid, store_name text, credit_spent numeric, invoices integer)
language plpgsql stable security definer set search_path to 'public' as $function$
declare v_role text; v_from date; v_to date;
begin
  select role into v_role from public.profiles where id = auth.uid();

  case coalesce(p_period, 'day')
    when 'day'    then v_from := public.sg_today(); v_to := v_from;
    when 'week'   then v_from := public.sg_today() - extract(dow from public.sg_today())::integer;
                       v_to := public.sg_today();
    when 'month'  then v_from := date_trunc('month', public.sg_today())::date; v_to := public.sg_today();
    when 'year'   then v_from := date_trunc('year', public.sg_today())::date; v_to := public.sg_today();
    when 'custom' then v_from := p_from; v_to := coalesce(p_to, public.sg_today());
    else               v_from := null; v_to := null;
  end case;

  return query
  select s.id, s.name,
         round(coalesce(sum(a.amount - coalesce(a.reversed_amount, 0)), 0), 2),
         count(distinct a.invoice_id)::integer
    from public.stores s
    left join public.invoices i
      on i.store_id = s.id and i.status = 'paid' and i.deleted_at is null
     and (v_from is null or (i.paid_at at time zone 'Asia/Singapore')::date >= v_from)
     and (v_to   is null or (i.paid_at at time zone 'Asia/Singapore')::date <= v_to)
    left join public.invoice_line_credit_allocations a on a.invoice_id = i.id
   where s.deleted_at is null
     and (v_role in ('owner','admin','manager')
          or exists (select 1 from public.user_store_assignments usa
                      where usa.user_id = auth.uid() and usa.store_id = s.id))
   group by s.id, s.name
  having coalesce(sum(a.amount - coalesce(a.reversed_amount, 0)), 0) > 0
   order by 3 desc;
end $function$;

notify pgrst, 'reload schema';
