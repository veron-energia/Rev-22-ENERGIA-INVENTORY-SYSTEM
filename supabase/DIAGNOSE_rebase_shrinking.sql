-- =====================================================================
-- DIAGNOSTIC — WHY "APPLY TO ALL UNPAID" SHRINKS THE TOTAL
--
-- Read-only. Run BEFORE applying migration 141, so you can see the cause on
-- your own data, and again after to confirm it has stopped.
-- =====================================================================

-- 1. THE TRUE TOTAL, AND WHY THE PAGE DISAGREED.
--
--    The Staff Commissions page read staff_commissions in ONE call. PostgREST
--    caps that at 1000 rows, and the table grows with every rebase — each press
--    reverses the old rows (which remain) and inserts new ones. Once past 1000,
--    the page saw only a fraction of the earned rows, so its total fell with
--    every press while the stored commission never changed.
--
--    Compare these two figures. If total_rows is over 1000, that is the cause.
select round(coalesce(sum(commission_amount), 0), 2) as true_unpaid_commission,
       count(*)                                      as earned_rows,
       (select count(*) from public.staff_commissions) as total_rows_in_table,
       case when (select count(*) from public.staff_commissions) > 1000
            then 'OVER THE 1000-ROW CAP — the page was under-reporting'
            else 'under the cap' end                 as verdict
  from public.staff_commissions
 where status = 'earned' and payout_id is null;

-- 1b. HOW MUCH OF THE TABLE IS SUPERSEDED REBASE HISTORY.
select count(*) filter (where status = 'reversed' and payout_id is null
                          and coalesce(reversal_reason,'') ilike '%rebase%') as superseded_reversals,
       count(*) filter (where status = 'earned')                              as earned,
       count(*)                                                              as total
  from public.staff_commissions;
-- prune_superseded_rebase_reversals() removes the first column safely.

-- 2. INVOICES THAT WOULD BE STRIPPED ON THE NEXT RUN.
--    A paid invoice with unpaid commission whose store has NO active
--    commission staff. The rebase clears these and returns "no active staff",
--    so the commission is gone and nothing replaces it.
select s.name                        as store,
       count(distinct i.id)          as invoices,
       round(sum(sc.commission_amount), 2) as commission_at_risk
  from public.staff_commissions sc
  join public.invoices i on i.id = sc.invoice_id
  join public.stores s on s.id = i.store_id
 where sc.status = 'earned'
   and sc.payout_id is null
   and i.deleted_at is null
   and (select count(*) from public.store_commission_staff(i.store_id)) = 0
 group by s.name
 order by 3 desc;
-- ANY ROWS HERE ARE THE CAUSE. That commission disappears on the next press.

-- 3. THE COMMISSION RATE. If this is zero, EVERY invoice takes the
--    "rate is zero" exit — after clearing — so one press wipes everything.
select coalesce(staff_commission_rate, 0) as staff_commission_rate,
       case when coalesce(staff_commission_rate, 0) <= 0
            then 'ZERO — a rebase would clear all unpaid commission'
            else 'set' end as verdict
  from public.app_settings where id = true;

-- 4. WHAT EARLIER RUNS MAY ALREADY HAVE DESTROYED.
--    Invoices holding only reversed, never-paid commission and nothing earned.
select i.invoice_no, s.name as store,
       round(sum(sc.commission_amount), 2) as reversed_amount,
       max(sc.reversed_at)                 as reversed_at,
       (select count(*) from public.store_commission_staff(i.store_id)) as active_staff
  from public.staff_commissions sc
  join public.invoices i on i.id = sc.invoice_id
  join public.stores s on s.id = i.store_id
 where sc.status = 'reversed'
   and sc.payout_id is null
   and i.deleted_at is null
   and not exists (select 1 from public.staff_commissions x
                    where x.invoice_id = i.id and x.status = 'earned')
 group by i.invoice_no, s.name, i.store_id
 order by 3 desc
 limit 50;

-- 5. AFTER APPLYING MIGRATION 141:
--    press Apply twice more and re-run section 1. The total must not change.
