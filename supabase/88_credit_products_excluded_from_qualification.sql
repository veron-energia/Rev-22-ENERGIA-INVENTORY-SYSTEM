-- =====================================================================
-- ENERGIA — CREDIT PRODUCTS MUST NOT CREATE LEGACY QUALIFICATION
--
-- Two corrections.
--
-- 1. THE REAL BUG. Buying a Credit Package or Premium Bundle on an invoice
--    generated Legacy *qualification* entitlements — the "Legacy Qualification
--    (per month)" rows on the Therapy page. A $15,000 bundle produced
--    floor(15000 / 994) = 15 of them.
--
--    Phases 27 and 28 both specified that these products stay out of Legacy
--    daily qualification, and their tests asserted it — but those tests called
--    the issuing functions directly, with no invoice. Once Phase 28 made them
--    real invoice lines, the invoice became an ordinary paid invoice and
--    recompute_legacy_qualification, which sums every paid invoice for the
--    customer and day, started counting it. The exclusion was never applied to
--    the invoice path.
--
--    Both the customer same-day total and the Affiliate residual now ignore the
--    value of credit_package and premium_bundle lines.
--
-- 2. UNDOING THE PREVIOUS CHANGE. Migration 87 switched grants_reward off,
--    which stopped the reward vouchers a bundle is sold on — the Buy Credit
--    dialog then offered 150 vouchers while refusing anything but 0. That was
--    a misreading of the request: the rewards on the invoice were wanted; the
--    qualification entitlements were not. grants_reward returns to ON.
--
-- Additive and idempotent. Run AFTER 87.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Reward vouchers / units are granted again.
-- ---------------------------------------------------------------------
alter table public.credit_packages alter column grants_reward set default true;
alter table public.premium_bundles alter column grants_reward set default true;
update public.credit_packages set grants_reward = true where grants_reward is distinct from true;
update public.premium_bundles set grants_reward = true where grants_reward is distinct from true;

-- ---------------------------------------------------------------------
-- 2. How much of an invoice counts toward Legacy qualification.
--    Everything except what was spent on a Credit Package or Premium Bundle.
--    The paid amount is pro-rated, so a part-paid invoice is handled too.
-- ---------------------------------------------------------------------
create or replace function public.invoice_qualifying_paid(p_invoice_id uuid)
returns numeric language sql stable security definer set search_path to 'public' as $function$
  with inv as (
    select i.paid_amount, i.subtotal from public.invoices i where i.id = p_invoice_id
  ),
  credit_lines as (
    select coalesce(sum(ii.line_total), 0) as amt
      from public.invoice_items ii
     where ii.invoice_id = p_invoice_id
       and ii.line_kind in ('credit_package','premium_bundle')
  )
  select greatest(round(
           coalesce(inv.paid_amount, 0) *
           case when coalesce(inv.subtotal, 0) > 0
                then greatest(inv.subtotal - credit_lines.amt, 0) / inv.subtotal
                else 1 end, 2), 0)
    from inv, credit_lines
$function$;

-- ---------------------------------------------------------------------
-- 3. Apply the exclusion everywhere a day's qualifying total is summed.
-- ---------------------------------------------------------------------
do $patch$
declare r record; v_def text; v_new text; v_count integer := 0;
begin
  for r in
    select p.oid, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('recompute_legacy_qualification','affiliate_residual_for_day',
                         'legacy_qualification_progress','legacy_qualification_diagnose')
  loop
    v_def := pg_get_functiondef(r.oid);
    if position('invoice_qualifying_paid' in v_def) > 0 then continue; end if;

    v_new := replace(v_def, 'coalesce(sum(i.paid_amount), 0)',
                            'coalesce(sum(public.invoice_qualifying_paid(i.id)), 0)');
    v_new := replace(v_new, 'coalesce(sum(i.paid_amount),0)',
                            'coalesce(sum(public.invoice_qualifying_paid(i.id)),0)');

    if position('invoice_qualifying_paid' in v_new) = 0 then
      raise exception 'Could not apply the credit-product exclusion to %', r.proname;
    end if;
    execute v_new;
    v_count := v_count + 1;
  end loop;

  if v_count = 0 then
    raise notice 'Credit-product exclusion already present on all qualification functions';
  else
    raise notice 'Credit-product exclusion applied to % function(s)', v_count;
  end if;
end $patch$;

notify pgrst, 'reload schema';
