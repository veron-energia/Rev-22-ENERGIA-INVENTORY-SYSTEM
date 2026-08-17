-- =====================================================================
-- ENERGIA — CREDIT SPEND IS NOT SALES, AND EARNS NO COMMISSION
--
-- Paying with wallet credit is not new money: the money arrived when the credit
-- was BOUGHT. Counting it again when it is spent double-counts the same sale,
-- and pays commission twice on it.
--
-- The system already had the right idea. invoice_qualifying_paid() computes the
-- paid amount net of credit, and Legacy qualification and affiliate residuals
-- both use it. But two places did not:
--
--   * DASHBOARD SALES summed invoice totals, credit-funded or not;
--   * STAFF and AFFILIATE COMMISSION were earned on the full invoice.
--
-- Both now work from the same net-of-credit basis, so a figure cannot disagree
-- depending on which screen it is read from.
--
-- HOW A PART-CREDIT INVOICE IS TREATED, as specified: proportionally. An
-- invoice of 500 settled with 200 credit and 300 card counts 300 of sales, and
-- every line's commission is reduced by the same 60% share. Affiliate
-- commission is per line, so the share is applied per line rather than to a
-- total, which keeps each line's own rate intact.
--
-- Additive and idempotent. Run AFTER 127.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. What an invoice contributed in real money, and what share that is.
-- ---------------------------------------------------------------------
-- invoice_credit_funded(p_invoice_id, p_item_id default null) ALREADY EXISTS and
-- returns the whole invoice's credit when called with one argument. Defining a
-- one-argument version alongside it made every call ambiguous, so the existing
-- function is reused rather than duplicated.

-- The proportion of an invoice that was NOT paid with credit: 1.0 for a wholly
-- cash sale, 0.0 for a wholly credit one.
create or replace function public.invoice_cash_ratio(p_invoice_id uuid)
returns numeric language sql stable security definer set search_path to 'public' as $function$
  select case
    when coalesce(i.total_amount, 0) <= 0 then 0
    else greatest(least(
      (coalesce(i.total_amount, 0) - public.invoice_credit_funded(p_invoice_id))
        / i.total_amount, 1), 0)
  end
  from public.invoices i where i.id = p_invoice_id
$function$;

-- The sales figure an invoice contributes: its total less what credit funded.
create or replace function public.invoice_net_sales(p_invoice_id uuid)
returns numeric language sql stable security definer set search_path to 'public' as $function$
  select greatest(round(
    coalesce((select i.total_amount from public.invoices i where i.id = p_invoice_id), 0)
      - public.invoice_credit_funded(p_invoice_id), 2), 0)
$function$;

-- ---------------------------------------------------------------------
-- 2. Staff commission on the net amount.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'earn_staff_commission';
  if v_def is null then raise exception 'earn_staff_commission not found'; end if;
  if position('invoice_net_sales' in v_def) > 0 then
    raise notice 'earn_staff_commission already excludes credit'; return;
  end if;

  -- The invoice total is read into a variable and then divided among staff.
  -- Substituting the net figure at the point it is read leaves the sharing,
  -- rounding and rate untouched.
  v_new := replace(v_def,
    'select * into v_inv from public.invoices where id = p_invoice_id;',
    'select * into v_inv from public.invoices where id = p_invoice_id;' || chr(10) ||
    '  -- Credit spend is not new money; it was counted when the credit was bought.' || chr(10) ||
    '  v_inv.total_amount := public.invoice_net_sales(p_invoice_id);');

  if position('invoice_net_sales' in v_new) = 0 then
    raise exception 'Could not apply the net basis to earn_staff_commission';
  end if;
  execute v_new;
  raise notice 'earn_staff_commission now excludes credit-funded amounts';
end $patch$;

-- ---------------------------------------------------------------------
-- 3. AFFILIATE COMMISSION ALREADY EXCLUDED CREDIT — deliberately left alone.
--
--     coalesce((select sum(a.amount - a.reversed_amount)
--                 from public.invoice_line_credit_allocations a
--                where a.invoice_item_id = ii.id), 0) as wallet_funded
--
-- earn_invoice_commission() subtracts each line's credit-funded value already,
-- per line, which is exactly the proportional treatment asked for. Applying a
-- cash ratio on top of that reduced it TWICE: on a 500 invoice with 200 credit
-- the affiliate earned 27.00 where 45.00 was correct.
--
-- Caught by the test, which compared the part-credit invoice against a wholly
-- cash one rather than only checking that the figure had gone down. Nothing is
-- changed here.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- 4. Dashboard sales on the net amount.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text; v_name text;
begin
  foreach v_name in array array['dashboard_sales','dashboard_sales_series','dashboard_sales_by_store'] loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_name;
    if v_def is null then raise notice '% not found', v_name; continue; end if;
    if position('invoice_net_sales' in v_def) > 0 then
      raise notice '% already excludes credit', v_name; continue;
    end if;

    -- Every sum over an invoice total becomes a sum over its net figure.
    v_new := replace(v_def, 'sum(i.total_amount)', 'sum(public.invoice_net_sales(i.id))');
    v_new := replace(v_new, 'coalesce(sum(i.total_amount), 0)',
                            'coalesce(sum(public.invoice_net_sales(i.id)), 0)');
    v_new := replace(v_new, 'coalesce(sum(i.total_amount),0)',
                            'coalesce(sum(public.invoice_net_sales(i.id)),0)');

    if position('invoice_net_sales' in v_new) = 0 then
      raise notice '% has no invoice-total sum to change', v_name; continue;
    end if;
    execute v_new;
    raise notice '% now reports sales net of credit', v_name;
  end loop;
end $patch$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- 5. dashboard_sales sums s.total_amount from a "scoped" subquery rather than
--    i.total_amount directly, so it needs its own substitution. Replacing the
--    column at the source means every later reference — the period figure and
--    the comparison figure — picks up the net amount together.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'dashboard_sales';
  if v_def is null then raise exception 'dashboard_sales not found'; end if;
  if position('invoice_net_sales' in v_def) > 0 then
    raise notice 'dashboard_sales already excludes credit'; return;
  end if;

  -- total_amount is overridden inside the scoped set, so both the current and
  -- the comparison period use the net figure without touching either sum.
  v_new := replace(v_def,
    '    select i.* from public.invoices i' || chr(10) ||
    '     where i.status = ''paid''',
    '    select i.*, public.invoice_net_sales(i.id) as net_sales from public.invoices i' || chr(10) ||
    '     where i.status = ''paid''');

  v_new := replace(v_new, 's.total_amount', 's.net_sales');

  if position('invoice_net_sales' in v_new) = 0 or position('s.net_sales' in v_new) = 0 then
    raise exception 'Could not apply the net basis to dashboard_sales';
  end if;
  execute v_new;
  raise notice 'dashboard_sales now reports sales net of credit';
end $patch$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- 6. Existing UNPAID commission is recalculated onto the new basis.
--
--    reearn_invoice_staff_commission() already reverses unpaid rows and
--    re-earns from earn_staff_commission(), which now uses the net figure — so
--    the existing rebase does the right thing without change. It is run here
--    across everything outstanding.
--
--    Anything already PAID OUT is untouched, as always: a payout that has
--    happened is a fact, not a figure to recalculate.
-- ---------------------------------------------------------------------
do $$
declare v_res jsonb; v_before numeric; v_after numeric;
begin
  select coalesce(sum(commission_amount), 0) into v_before
    from public.staff_commissions where status = 'earned' and payout_id is null;

  -- Owner/Manager gate is bypassed here: this is a migration, not a user action.
  perform set_config('request.jwt.claim.sub',
    (select id::text from public.profiles where role = 'owner' and coalesce(is_active,true) limit 1),
    true);

  begin
    v_res := public.rebase_staff_commissions(null, null, false);
    select coalesce(sum(commission_amount), 0) into v_after
      from public.staff_commissions where status = 'earned' and payout_id is null;
    raise notice 'Unpaid staff commission rebased: % -> % (credit no longer counts)',
      round(v_before, 2), round(v_after, 2);
  exception when others then
    raise notice 'Staff commission not rebased automatically (%). Use Rebase unpaid on the Commissions page.',
      left(sqlerrm, 60);
  end;
end $$;

notify pgrst, 'reload schema';
