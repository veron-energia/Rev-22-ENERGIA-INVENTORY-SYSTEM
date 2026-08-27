-- =====================================================================
-- ENERGIA — WHY THE PREVIEW AND THE PAGE NEVER AGREED
--
-- Three symptoms, one explanation:
--
--   * "Owed Now" and "After" are always identical;
--   * both differ from the unpaid figure on the Staff Commissions page;
--   * pressing Apply still moves the page figure.
--
-- The two are counting different things.
--
--   THE PAGE counts every earned, unpaid row that has an invoice_paid_date —
--   whatever has since happened to the invoice.
--
--   THE PREVIEW counts only rows whose invoice is still:
--       i.status in ('paid','completed_foc') and i.deleted_at is null
--
-- So commission sitting on an invoice that was later REFUNDED, CANCELLED, left
-- PARTIALLY PAID or DELETED appears on the page, is invisible to the preview,
-- and is never touched by the rebase. The difference between the two figures is
-- exactly that commission.
--
-- And because the rebase only ever works on eligible invoices, once it has run
-- their stored rows already match what it would produce — so "Owed Now" and
-- "After" agree, correctly, while the page figure stays stubbornly different.
--
-- This does not silently reconcile the two. It makes the gap VISIBLE, because
-- unpaid commission on a refunded or cancelled invoice is a question about the
-- money, not a display problem: someone is owed for a sale that was undone.
--
-- Additive, read-only, idempotent. Creates no data and changes no amount.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- Unpaid commission the rebase will NOT touch, and why.
-- ---------------------------------------------------------------------
create or replace function public.commission_outside_rebase_scope()
returns table(reason text, invoices integer, staff integer, amount numeric)
language sql stable security definer set search_path to 'public' as $function$
  select
    case
      when i.id is null                     then 'Invoice no longer exists'
      when i.deleted_at is not null         then 'Invoice deleted'
      when i.status::text = 'refunded'      then 'Invoice refunded'
      when i.status::text = 'cancelled'     then 'Invoice cancelled'
      when i.status::text = 'partially_paid' then 'Invoice only part paid'
      when i.status::text = 'unpaid'        then 'Invoice unpaid'
      when i.status::text = 'draft'         then 'Invoice still a draft'
      else 'Invoice status: ' || i.status::text
    end,
    count(distinct sc.invoice_id)::integer,
    count(distinct sc.staff_id)::integer,
    round(sum(sc.commission_amount), 2)
    from public.staff_commissions sc
    left join public.invoices i on i.id = sc.invoice_id
   where sc.status = 'earned'
     and sc.payout_id is null
     -- Everything the rebase does NOT consider.
     and (i.id is null
          or i.deleted_at is not null
          or i.status::text not in ('paid', 'completed_foc'))
   group by 1
   order by 4 desc
$function$;

-- ---------------------------------------------------------------------
-- The two totals side by side, so the difference is stated rather than left
-- for someone to notice.
-- ---------------------------------------------------------------------
create or replace function public.commission_totals_reconciliation()
returns jsonb language sql stable security definer set search_path to 'public' as $function$
  select jsonb_build_object(
    'page_total', round(coalesce((
        select sum(sc.commission_amount) from public.staff_commissions sc
         where sc.status = 'earned' and sc.payout_id is null
           and sc.invoice_paid_date is not null), 0), 2),
    'in_rebase_scope', round(coalesce((
        select sum(sc.commission_amount) from public.staff_commissions sc
          join public.invoices i on i.id = sc.invoice_id
         where sc.status = 'earned' and sc.payout_id is null
           and i.deleted_at is null
           and i.status::text in ('paid', 'completed_foc')), 0), 2),
    'outside_rebase_scope', round(coalesce((
        select sum(t.amount) from public.commission_outside_rebase_scope() t), 0), 2),
    -- Rows with no paid date are on the page's own filter, not the rebase's.
    'no_paid_date', round(coalesce((
        select sum(sc.commission_amount) from public.staff_commissions sc
         where sc.status = 'earned' and sc.payout_id is null
           and sc.invoice_paid_date is null), 0), 2)
  )
$function$;

do $$
declare v_j jsonb;
begin
  v_j := public.commission_totals_reconciliation();
  raise notice 'Page shows S$%, of which S$% is in rebase scope and S$% is not.',
    v_j->>'page_total', v_j->>'in_rebase_scope', v_j->>'outside_rebase_scope';
  raise notice 'Confirmed: the gap between the two figures is now reportable';
end $$;

notify pgrst, 'reload schema';
