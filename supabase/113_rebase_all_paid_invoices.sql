-- =====================================================================
-- ENERGIA — REBASE EVERY PAID INVOICE, NOT JUST THOSE WITH COMMISSION ROWS
--
-- rebase_staff_commissions() looped over rows in staff_commissions:
--
--     for v_inv in select distinct sc.invoice_id ... from staff_commissions sc
--
-- so it could only correct invoices that ALREADY had a commission row. Under
-- the old rule an invoice produced rows only for the people named in
-- "Served by", which means:
--
--   * an invoice served by nobody produced NO rows, and was therefore
--     invisible to the rebase — its staff share was never created at all;
--   * an invoice served only by a Manager or Owner produced rows for them and
--     none for staff, so it was corrected, but any invoice with no row was not.
--
-- Verified before fixing: two paid invoices of 300 each, 3% rate, two staff.
-- Staff A should end on 9.00 and ended on 4.50 — half the sales were skipped.
--
-- The loop now walks PAID INVOICES themselves, so every settled sale is
-- brought onto the store-staff basis whether or not it had a row before.
--
-- What is unchanged, deliberately:
--   * anything already PAID OUT is skipped and left exactly as it is;
--   * original rows are reversed and KEPT, never deleted;
--   * the default is still a dry run.
--
-- Additive and idempotent. Run AFTER 112.
-- =====================================================================

set check_function_bodies = off;

create or replace function public.rebase_staff_commissions(
  p_from date default null, p_to date default null, p_dry_run boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_inv record; v_n integer := 0; v_skipped integer := 0; v_created integer := 0;
  v_after numeric := 0;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can rebase commission'; end if;

  -- Every SETTLED invoice in range, whether or not it has commission rows. This
  -- is the correction: an invoice nobody was named on still owes the store's
  -- staff their share.
  for v_inv in
    select i.id as invoice_id, i.store_id,
           (select count(*) from public.staff_commissions sc
             where sc.invoice_id = i.id) as existing_rows
      from public.invoices i
     where i.status in ('paid','completed_foc')
       and i.deleted_at is null
       and (p_from is null or (i.paid_at at time zone 'Asia/Singapore')::date >= p_from)
       and (p_to   is null or (i.paid_at at time zone 'Asia/Singapore')::date <= p_to)
     order by i.paid_at
  loop
    -- Any commission already PAID OUT on this invoice: leave the whole invoice
    -- alone rather than half-rewriting a settled payout.
    if exists (select 1 from public.staff_commissions sc2
                where sc2.invoice_id = v_inv.invoice_id
                  and (sc2.payout_id is not null or sc2.status = 'paid')) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    if not p_dry_run then
      -- Reverse whatever is there (possibly nothing), then earn on the current
      -- basis: the invoice total divided equally among the store's active staff.
      if v_inv.existing_rows > 0 then
        perform public.reverse_staff_commission(v_inv.invoice_id,
          'Rebased onto the store-staff basis');
      end if;
      perform public.earn_staff_commission(v_inv.invoice_id);
    end if;

    if v_inv.existing_rows = 0 then v_created := v_created + 1; end if;
    v_n := v_n + 1;
  end loop;

  if not p_dry_run then
    select coalesce(sum(sc.commission_amount), 0) into v_after
      from public.staff_commissions sc
     where sc.status = 'earned' and sc.payout_id is null;

    perform public.write_audit_ex('staff_commissions', null, 'staff_commission_rebased', null,
      jsonb_build_object('invoices', v_n, 'skipped_paid', v_skipped,
        'had_no_commission_before', v_created, 'from', p_from, 'to', p_to),
      'commission', null, null);
  end if;

  return jsonb_build_object(
    'dry_run', p_dry_run,
    'invoices_affected', v_n,
    'invoices_skipped_already_paid', v_skipped,
    'invoices_with_no_commission_before', v_created,
    'unpaid_total_after', case when p_dry_run then null else round(v_after, 2) end);
end $function$;

-- ---------------------------------------------------------------------
-- The preview must cover the same invoices, or it would understate the change
-- by exactly the invoices that were missing rows in the first place.
-- ---------------------------------------------------------------------
create or replace function public.preview_commission_rebase_effect(
  p_from date default null, p_to date default null)
returns table(staff_name text, current_unpaid numeric, projected_unpaid numeric,
              difference numeric, invoices integer)
language sql stable security definer set search_path to 'public' as $function$
  with eligible as (
    -- Settled invoices with no paid-out commission: exactly what a rebase touches.
    select i.id as invoice_id, i.store_id, i.total_amount
      from public.invoices i
     where i.status in ('paid','completed_foc')
       and i.deleted_at is null
       and (p_from is null or (i.paid_at at time zone 'Asia/Singapore')::date >= p_from)
       and (p_to   is null or (i.paid_at at time zone 'Asia/Singapore')::date <= p_to)
       and not exists (select 1 from public.staff_commissions s2
                        where s2.invoice_id = i.id
                          and (s2.payout_id is not null or s2.status = 'paid'))
  ),
  rate as (select coalesce(staff_commission_rate, 0) as r from public.app_settings where id = true),
  projected as (
    select s.staff_id,
           sum(round(e.total_amount / nullif(cnt.n, 0) * rate.r / 100.0, 2)) as amt,
           count(distinct e.invoice_id)::integer as invs
      from eligible e
      cross join rate
      cross join lateral (select count(*)::integer as n
                            from public.store_commission_staff(e.store_id)) cnt
      join lateral public.store_commission_staff(e.store_id) s on true
     group by s.staff_id
  ),
  current_amounts as (
    select sc.staff_id, sum(sc.commission_amount) as amt
      from public.staff_commissions sc
      join eligible e on e.invoice_id = sc.invoice_id
     where sc.status = 'earned' and sc.payout_id is null
     group by sc.staff_id
  )
  select p.full_name,
         round(coalesce(c.amt, 0), 2),
         round(coalesce(pr.amt, 0), 2),
         round(coalesce(pr.amt, 0) - coalesce(c.amt, 0), 2),
         coalesce(pr.invs, 0)
    from public.profiles p
    left join current_amounts c on c.staff_id = p.id
    left join projected pr on pr.staff_id = p.id
   where coalesce(c.amt, 0) <> 0 or coalesce(pr.amt, 0) <> 0
   order by abs(round(coalesce(pr.amt, 0) - coalesce(c.amt, 0), 2)) desc, p.full_name
$function$;

notify pgrst, 'reload schema';
