-- =====================================================================
-- ENERGIA — BACKFILL PAST STOCK USES · FIRST-NAME REFERRER · REBASE HELPER
--
-- 1. Stock uses recorded BEFORE migration 111 deducted stock but wrote no
--    stock movement, so they are missing from Stock Movement History. They are
--    backfilled here, matched one-to-one so a re-run cannot duplicate them.
--
-- 2. The printed Bill To shows the affiliate's FIRST NAME only.
--
-- 3. rebase_staff_commissions() already exists (migration 103). A convenience
--    wrapper is added so the whole outstanding balance can be moved onto the
--    store-staff basis in one call, and a report shows the before-and-after per
--    staff member so the change can be checked before it is committed.
--
-- Additive and idempotent. Run AFTER 111.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Backfill the movements for past stock uses.
--
--    Matched on the use number in the note, so a movement is written once and
--    only once however many times this runs. The stock itself is NOT touched:
--    it was already deducted when the use was recorded. Only the missing
--    history line is added.
-- ---------------------------------------------------------------------
do $$
declare v_n integer := 0; u record;
begin
  for u in
    select su.* from public.stock_uses su
     where not exists (
       select 1 from public.stock_movements sm
        where sm.product_id = su.product_id
          and sm.notes like 'Stock use ' || su.use_no || ' %'
     )
     order by su.created_at
  loop
    insert into public.stock_movements
      (product_id, movement_type, from_store_id, from_warehouse_id,
       quantity, notes, created_by, created_at)
    values (u.product_id, 'inventory_adjustment'::stock_movement_type,
      u.store_id, u.warehouse_id, u.quantity,
      'Stock use ' || u.use_no || ' — ' || coalesce(u.reason, 'recorded use')
        || coalesce(' (' || nullif(trim(u.note), '') || ')', '')
        || ' [backfilled]',
      u.used_by,
      -- The ORIGINAL timestamp, so the movement sits where it belongs in the
      -- history rather than appearing as if it happened today.
      u.created_at);
    v_n := v_n + 1;
  end loop;

  if v_n > 0 then
    raise notice 'Backfilled % past stock use(s) into Stock Movement History', v_n;
  else
    raise notice 'No past stock uses needed backfilling';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. The printed Bill To shows the affiliate's FIRST NAME only.
--    Customer sources are left in full: "TikTok" or "Roadshow" is not a name.
-- ---------------------------------------------------------------------
create or replace function public.invoice_bill_to_source(p_invoice_id uuid)
returns text language sql stable security definer set search_path to 'public' as $function$
  select coalesce(
    -- An affiliate on the invoice wins, by FIRST NAME only. Falls back to the
    -- first word of full_name for a record that predates the name split.
    nullif(trim(ac.first_name), ''),
    nullif(trim(split_part(trim(ac.full_name), ' ', 1)), ''),
    -- Otherwise how the customer came to us, in full: a source is not a name.
    nullif(trim(c.source_label), ''),
    nullif(trim(so.label), ''),
    '-')
  from public.invoices i
  left join public.customer_affiliates ca on ca.id = i.affiliate_id
  left join public.customers ac on ac.id = ca.customer_id
  left join public.customers c on c.id = i.customer_id
  left join public.customer_source_options so on so.id = c.source_option_id
  where i.id = p_invoice_id
$function$;

-- ---------------------------------------------------------------------
-- 3. Moving the outstanding commission onto the store-staff basis.
--
--    A report first: what each staff member is owed now, and what they would be
--    owed after. Financially consequential changes should be readable before
--    they are made, not explained afterwards.
-- ---------------------------------------------------------------------
create or replace function public.preview_commission_rebase_effect(
  p_from date default null, p_to date default null)
returns table(staff_name text, current_unpaid numeric, projected_unpaid numeric,
              difference numeric, invoices integer)
language sql stable security definer set search_path to 'public' as $function$
  with unpaid as (
    -- Invoices whose commission is entirely unpaid: the only ones a rebase
    -- touches. Anything part-paid is skipped and must not be projected either.
    select sc.invoice_id, sc.store_id, sc.invoice_total
      from public.staff_commissions sc
     where sc.status = 'earned' and sc.payout_id is null
       and (p_from is null or sc.invoice_paid_date >= p_from)
       and (p_to   is null or sc.invoice_paid_date <= p_to)
       and not exists (select 1 from public.staff_commissions s2
                        where s2.invoice_id = sc.invoice_id
                          and (s2.payout_id is not null or s2.status = 'paid'))
     group by sc.invoice_id, sc.store_id, sc.invoice_total
  ),
  rate as (select coalesce(staff_commission_rate, 0) as r from public.app_settings where id = true),
  -- What each store's active staff would receive under the new basis.
  projected as (
    select s.staff_id, sum(round(u.invoice_total / nullif(cnt.n, 0) * rate.r / 100.0, 2)) as amt,
           count(distinct u.invoice_id)::integer as invs
      from unpaid u
      cross join rate
      cross join lateral (select count(*)::integer as n
                            from public.store_commission_staff(u.store_id)) cnt
      join lateral public.store_commission_staff(u.store_id) s on true
     group by s.staff_id
  ),
  current_amounts as (
    select sc.staff_id, sum(sc.commission_amount) as amt
      from public.staff_commissions sc
      join unpaid u on u.invoice_id = sc.invoice_id
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

-- Commit the rebase across everything outstanding. Deliberately a separate,
-- explicitly named function: rebase_staff_commissions() still defaults to a dry
-- run, so nothing changes by accident.
create or replace function public.apply_commission_rebase_all()
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_res jsonb;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can rebase commission'; end if;
  v_res := public.rebase_staff_commissions(null, null, false);
  return v_res || jsonb_build_object('note',
    'Commission already paid out was skipped and left untouched.');
end $function$;

notify pgrst, 'reload schema';
