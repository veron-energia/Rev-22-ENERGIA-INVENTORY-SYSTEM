-- =====================================================================
-- ENERGIA — REBASE MUST NOT SKIP AN INVOICE JUST BECAUSE PART OF IT WAS PAID
--
-- The rebase skipped an ENTIRE invoice if any of its commission had been paid
-- out:
--
--     if exists (... payout_id is not null or status = 'paid') then
--       v_skipped := v_skipped + 1; continue;
--     end if;
--
-- The intention was right — never rewrite a payout that has happened. The scope
-- was wrong. After any payout run, most invoices have at least one paid row, so
-- in practice almost nothing was rebased:
--
--   * an Owner's or Manager's row that was PAID stays paid (correct), but
--   * their UNPAID rows survived untouched, and
--   * the store's staff received nothing for that invoice at all.
--
-- Reproduced before fixing: Owner paid out 15.00, Manager holding 15.00 unpaid,
-- Staff A and B on 0.00. After the old rebase: Manager still 15.00, A and B
-- still 0.00.
--
-- Now the guard is per ROW, not per invoice:
--
--   * rows already PAID OUT are left exactly as they are — untouched, and their
--     value is subtracted from what remains to distribute;
--   * every UNPAID row is reversed, whoever holds it;
--   * the REMAINING commission is divided equally among the store's active
--     staff.
--
-- So a Manager's unpaid row is removed and redistributed, while a payout that
-- has already happened is never rewritten.
--
-- Additive and idempotent. Run AFTER 113.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- Re-earn the staff share of ONE invoice, net of anything already paid out.
-- ---------------------------------------------------------------------
create or replace function public.reearn_invoice_staff_commission(
  p_invoice_id uuid, p_reason text default 'Rebased onto the store-staff basis')
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_inv public.invoices%rowtype; v_rate numeric; v_n integer;
  v_already_paid numeric; v_pool numeric; v_share numeric;
  v_reversed integer := 0; v_staff record; v_amt numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return jsonb_build_object('skipped', 'invoice not found'); end if;

  -- Anything already PAID OUT is a fact and stays exactly as it is.
  select coalesce(sum(commission_amount), 0) into v_already_paid
    from public.staff_commissions
   where invoice_id = p_invoice_id
     and (payout_id is not null or status = 'paid');

  -- Every UNPAID row is cleared, whoever holds it — including an Owner or
  -- Manager who should never have had one under the current rule.
  update public.staff_commissions
     set status = 'reversed', reversed_at = now(),
         reversal_reason = p_reason
   where invoice_id = p_invoice_id
     and status = 'earned'
     and payout_id is null;
  get diagnostics v_reversed = row_count;

  select coalesce(staff_commission_rate, 0) into v_rate from public.app_settings where id = true;
  if coalesce(v_rate, 0) <= 0 then
    return jsonb_build_object('reversed', v_reversed, 'earned', 0, 'note', 'rate is zero');
  end if;

  v_n := public.store_commission_staff_count(v_inv.store_id);
  if v_n = 0 then
    return jsonb_build_object('reversed', v_reversed, 'earned', 0,
      'note', 'no active staff assigned to this store');
  end if;

  -- What the invoice owes in total, less what has already been handed over.
  v_pool := round(coalesce(v_inv.total_amount, 0) * v_rate / 100.0, 2) - v_already_paid;
  if v_pool <= 0 then
    return jsonb_build_object('reversed', v_reversed, 'earned', 0,
      'note', 'already fully paid out');
  end if;

  v_share := round(v_pool / v_n, 2);
  if v_share <= 0 then
    return jsonb_build_object('reversed', v_reversed, 'earned', 0, 'note', 'share rounds to zero');
  end if;

  for v_staff in select s.staff_id from public.store_commission_staff(v_inv.store_id) s
  loop
    insert into public.staff_commissions
      (invoice_id, staff_id, store_id, invoice_total, share_ratio, rate,
       commission_amount, status, invoice_paid_date)
    values (p_invoice_id, v_staff.staff_id, v_inv.store_id,
      coalesce(v_inv.total_amount, 0), round(1.0 / v_n, 6), v_rate,
      v_share, 'earned', coalesce(v_inv.paid_at, now())::date);
  end loop;

  return jsonb_build_object('reversed', v_reversed, 'earned', v_n,
    'share_each', v_share, 'already_paid_out', v_already_paid);
end $function$;

-- ---------------------------------------------------------------------
-- The rebase itself: every settled invoice, per-row protection for payouts.
-- ---------------------------------------------------------------------
create or replace function public.rebase_staff_commissions(
  p_from date default null, p_to date default null, p_dry_run boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_inv record; v_n integer := 0; v_created integer := 0;
  v_part_paid integer := 0; v_no_staff integer := 0; v_after numeric := 0; v_res jsonb;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can rebase commission'; end if;

  for v_inv in
    select i.id as invoice_id, i.store_id,
           (select count(*) from public.staff_commissions sc
             where sc.invoice_id = i.id and sc.status = 'earned') as earned_rows,
           exists (select 1 from public.staff_commissions sc2
                    where sc2.invoice_id = i.id
                      and (sc2.payout_id is not null or sc2.status = 'paid')) as has_paid
      from public.invoices i
     where i.status in ('paid','completed_foc')
       and i.deleted_at is null
       and (p_from is null or (i.paid_at at time zone 'Asia/Singapore')::date >= p_from)
       and (p_to   is null or (i.paid_at at time zone 'Asia/Singapore')::date <= p_to)
     order by i.paid_at
  loop
    if v_inv.has_paid then v_part_paid := v_part_paid + 1; end if;
    if v_inv.earned_rows = 0 then v_created := v_created + 1; end if;

    if not p_dry_run then
      v_res := public.reearn_invoice_staff_commission(v_inv.invoice_id);
      if (v_res->>'note') = 'no active staff assigned to this store' then
        v_no_staff := v_no_staff + 1;
      end if;
    end if;
    v_n := v_n + 1;
  end loop;

  if not p_dry_run then
    select coalesce(sum(sc.commission_amount), 0) into v_after
      from public.staff_commissions sc
     where sc.status = 'earned' and sc.payout_id is null;

    perform public.write_audit_ex('staff_commissions', null, 'staff_commission_rebased', null,
      jsonb_build_object('invoices', v_n, 'had_no_commission_before', v_created,
        'part_paid_kept', v_part_paid, 'stores_without_staff', v_no_staff,
        'from', p_from, 'to', p_to), 'commission', null, null);
  end if;

  return jsonb_build_object(
    'dry_run', p_dry_run,
    'invoices_affected', v_n,
    'invoices_with_no_commission_before', v_created,
    'invoices_with_some_already_paid', v_part_paid,
    'invoices_no_staff_at_store', v_no_staff,
    'unpaid_total_after', case when p_dry_run then null else round(v_after, 2) end);
end $function$;

-- ---------------------------------------------------------------------
-- The preview must model the same arithmetic, including netting off payouts.
-- ---------------------------------------------------------------------
create or replace function public.preview_commission_rebase_effect(
  p_from date default null, p_to date default null)
returns table(staff_name text, current_unpaid numeric, projected_unpaid numeric,
              difference numeric, invoices integer)
language sql stable security definer set search_path to 'public' as $function$
  with rate as (select coalesce(staff_commission_rate, 0) as r from public.app_settings where id = true),
  eligible as (
    select i.id as invoice_id, i.store_id,
           greatest(round(coalesce(i.total_amount,0) * (select r from rate) / 100.0, 2)
                    - coalesce((select sum(sc.commission_amount) from public.staff_commissions sc
                                 where sc.invoice_id = i.id
                                   and (sc.payout_id is not null or sc.status = 'paid')), 0), 0) as pool
      from public.invoices i
     where i.status in ('paid','completed_foc')
       and i.deleted_at is null
       and (p_from is null or (i.paid_at at time zone 'Asia/Singapore')::date >= p_from)
       and (p_to   is null or (i.paid_at at time zone 'Asia/Singapore')::date <= p_to)
  ),
  projected as (
    select s.staff_id, sum(round(e.pool / nullif(cnt.n, 0), 2)) as amt,
           count(distinct e.invoice_id)::integer as invs
      from eligible e
      cross join lateral (select count(*)::integer as n
                            from public.store_commission_staff(e.store_id)) cnt
      join lateral public.store_commission_staff(e.store_id) s on true
     where e.pool > 0 and cnt.n > 0
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
