-- 410_clawbacks_carried_forward_and_therapy_status_refresh.sql
--
-- WHAT WAS WRONG (the audit of 8 Oct 2026: AFFILIATES-1, AFFILIATES-3,
-- THERAPY-1, THERAPY-10)
--
--   Affiliate commission taken back was never taken from later payouts
--   (AFFILIATES-1). When a sale whose commission was already paid out is
--   refunded, cancelled or given to another affiliate,
--   reconcile_invoice_commissions writes a negative "Future payout
--   adjustment" row. It copied the paid row's date, so the take-back landed
--   in the month already paid, and every page and the payout itself looked
--   at one month at a time:
--     * Record payout stayed open for the affiliate's next month while the
--       month before owed money back. On production on 8 Oct 2026 one
--       affiliate stood at -562.35 for September (four take-backs written on
--       3 Oct, all dated in September) and +7.08 for October, and the 7.08
--       was offered as payable. affiliate_payout_save checked the month's
--       balance only.
--     * "Remaining payable" added up each month's positive balance, so it
--       counted that 7.08.
--     * The pages disagreed: Balances showed S$0.00 and "Overpaid
--       adjustment"; the Affiliates page, the Referrers tab, its export and
--       the affiliate's own portal showed "Unpaid S$-555.27" with nothing to
--       say what it was.
--   The Owner decided on 3 Oct 2026 that such commission is recovered from
--   the affiliate's future payouts.
--
--   Commission withheld because the affiliate was not activated is written
--   with status 'blocked' (AFFILIATES-3). The Affiliates page's "Blocked"
--   and the portal's "Blocked" counted status 'cancelled', which no row has,
--   so they showed nothing (production, 8 Oct 2026: one affiliate, 5 rows,
--   S$69.87), and the portal listed those purchases as "Reversed".
--
--   Purchased therapy statuses never moved with the calendar (THERAPY-1).
--   refresh_purchased_therapy_statuses and refresh_legacy_therapy_statuses
--   exist, but nothing ever ran them: no cron job, no caller. Every check
--   read the stored status, so a unit scheduled to start on 2 Oct
--   (UTP-0000010; production, 9 Oct 2026, still 'scheduled') could be
--   claimed again to start later (its days already used given back), moved,
--   or refunded as unused, from the Refund button, from the invoice's
--   refund, which asks therapy_unit_consumed, and from the invoice's Cancel,
--   which closes as refunded every unit still stored as not started (the
--   refund that follows then finds nothing used). Correct Invoice would move
--   such a unit to another customer. Legacy LEG-0000081 ends on 13 Oct and
--   would have stayed active.
--
--   Reschedule changed only the date shown once a start date was set
--   (THERAPY-10): it wrote scheduled_date, while the start, the expiry and
--   the closure days stayed as they were. Only a new Claim works them out.
--
-- THE RULES
--
--   1. (the Owner, 3 Oct 2026) Commission already paid out and then taken
--      back is recovered from the affiliate's later commission. An affiliate
--      is paid nothing more while their months, added up, owe it back.
--   2. An affiliate's months are netted: what they are owed is every month's
--      balance added up (earned, less adjustments, less what was paid out).
--      Shown as "Unpaid" when it is above 0, and as "Deduction to be
--      recovered" when it is below 0; never as a negative "Unpaid".
--   3. A new payout, or a payout raised, may not be more than the month's own
--      balance (as before) nor more than what the affiliate can be paid now:
--      their months netted, where a month whose payouts need review (or a
--      row with no date) counts only when it is negative, since its positive
--      balance cannot be paid until it is reviewed.
--   4. What can be paid now is shown against the affiliate's months with a
--      positive balance, oldest first, so the months add up to it. "Remaining
--      payable" is the sum over affiliates.
--   5. A month already paid stays as it was paid. When commission already
--      paid out is taken back, then per affiliate and tier on the invoice:
--      a. as far as the sale still earns them commission (a part refund, a
--         correction), what was paid out is netted against that commission,
--         in that commission's own month, so it is not paid a second time;
--      b. the rest is taken back from the next month to be paid: dated the
--         day it is first written (Singapore), and it keeps that date every
--         time the invoice is worked out again (a later payment correction,
--         refund or reopening). Only what is taken back beyond it is dated
--         that later day;
--      c. take-backs already made stay where they are when the sale earns
--         more again (a refund undone): that commission is owed in the sale's
--         own month, like any commission not yet paid. They are lowered,
--         newest first, only when they come to more than was paid out (a
--         payout lowered, or a row taken back whole before 410);
--      d. the part of a paid row never paid out (a payout that covered only
--         part of it) is not money to recover: it is cancelled in the row's
--         own month, as the part-payment layer already does (357).
--   6. Commission withheld ('blocked') is counted as blocked, and a purchase
--      whose commission was all withheld is shown as "Blocked", not
--      "Reversed".
--   7. A purchased therapy unit's status follows its dates: one scheduled to
--      start on or before today has started (and has ended if its expiry is
--      past too); an active one past its expiry has ended; one never started
--      (pending, or scheduled without a start date) past its activation
--      deadline has expired. Every check on claiming, starting, refunding,
--      rescheduling, cancelling the invoice and correcting it uses this, so
--      none depends on a refresh having run.
--   8. The statuses are refreshed every night at 00:05 Singapore time, Legacy
--      included.
--   9. Once a unit has a start date, Reschedule refuses and says to use Claim,
--      which works out the start and the expiry again.
--
-- WHAT THIS DOES
--
--   Affiliates
--   * affiliate_referrer_balances() (new; internal, the service role's alone,
--     339): one row per affiliate: owed (every month's balance added up),
--     unpaid (owed, never below 0), deduction (-owed, never below 0) and
--     payable (rule 3). The netting is written here and nowhere else.
--   * affiliate_payout_overview() (patched): each month in 'groups' also
--     carries payable (rule 4) and the affiliate's referrer_owed,
--     referrer_payable and referrer_deduction; 'referrers' (new key) lists
--     every affiliate's figures. Every key it sent before is still sent, with
--     the same value.
--   * affiliate_payout_save(...) (patched): a payout added or raised beyond
--     the affiliate's payable is refused, naming the deduction still to be
--     recovered (rule 3). The month check before it, the allocation and
--     everything else is as before. record_affiliate_payout and
--     correct_affiliate_payout reach it as before.
--   * reconcile_invoice_commissions(uuid,text) (patched; rule 5). It still
--     reverses every unpaid row of the invoice, earns again what the invoice
--     earns now, and takes back every paid row: per affiliate and tier, the
--     paid rows come to the same amount as the one row each before, now
--     written as
--       - "Already paid out on this sale: ...": the part of what was paid out
--         that the sale still earns, linked to the row earned again and in its
--         month (that row is then never paid again, so it cannot become
--         another paid row);
--       - "Future payout adjustment: ...": the rest of what was paid out. The
--         rows of that reason standing before the run are read before they are
--         reversed and written again on their own dates; only the part beyond
--         them is dated sg_today(). So the four rows of 3 Oct 2026 stay in
--         September, and a take-back never moves to a later month because the
--         invoice was worked out again;
--       - "Unpaid commission cancelled: ...": what a paid row never paid out,
--         in its own month.
--     Staff commission's take-back is not changed.
--   * affiliate_admin_directory() (patched): 'unpaid' is the affiliate's
--     unpaid (rule 2; it was the signed sum), 'deduction' is new, and
--     'blocked' counts status 'blocked' (and 'cancelled', as before).
--   * affiliate_portal_earnings() (patched): the summary's 'unpaid' is never
--     below 0, 'deduction' is new, and 'blocked' counts status 'blocked'.
--     affiliate_portal_dashboard passes the summary on unchanged.
--   * affiliate_portal_purchases() (patched): a purchase with no commission
--     earned or paid and some blocked is 'blocked' (rule 6).
--
--   Therapy
--   * purchased_therapy_status_on(status, activation, expiry, deadline, on)
--     (new; internal; immutable): rule 7, the one place it is written.
--   * refresh_purchased_therapy_statuses() (replaced whole): each unit takes
--     purchased_therapy_status_on(...) for today, units that end first; a
--     unit that cannot be moved is left with a warning in the database log
--     and the rest still move. Before 410 it moved the same units, except
--     that a unit rescheduled without a start date never expired at its
--     deadline, and one unit it could not move (a clash with the same-package
--     rule) stopped the whole refresh; it returned how many started, now how
--     many changed. Nothing calls it but run_therapy_status_refresh.
--   * run_therapy_status_refresh() (new; internal): the purchased refresh,
--     then refresh_legacy_therapy_statuses() (not changed); returns what
--     changed and any purchased unit still out of step with its dates.
--   * The cron job 'therapy-status-refresh' (new), '5 16 * * *' in pg_cron's
--     GMT: 00:05 in Singapore every day, running run_therapy_status_refresh().
--   * therapy_unit_consumed(uuid) (patched): started or ended by its dates
--     (rule 7). The Refund button and the invoice's refund read it.
--   * refund_purchased_therapy(uuid,text), claim_purchased_therapy(...),
--     activate_purchased_therapy(...) (patched): their "already started or
--     ended" checks read rule 7. Refund names a unit never started by its
--     deadline as expired, rather than "after activation".
--   * reschedule_purchased_therapy(uuid,date,text) (patched): rule 7 for
--     "before activation", and rule 9.
--   * cancel_invoice_recorded(uuid,text,uuid) (patched): closes as refunded
--     only the units not started by their dates (rule 7). One whose start date
--     has been reached is left, as an active one already is, for the
--     invoice's refund, where an Owner or Manager authorizes ending it.
--   * correct_invoice(uuid,jsonb,jsonb,text,uuid) (patched): "Resolve the
--     consumed therapy entitlement" reads rule 7, so a unit whose start date
--     has been reached is not moved to another customer or line.
--
-- NOT CHANGED
--
--   * affiliate_month_balances (each month on its own, as the balances page
--     shows it), affiliate_payout_review, the allocation of a payout to its
--     commission rows, commission_reporting_rows, referrer_list and
--     referrer_earnings (their unpaid figures stay the signed sum; the page
--     shows a negative one as a deduction), report_affiliates, staff
--     commission, the commission rates and every rule of earning.
--   * No row of the app's tables is changed. The four take-backs written on
--     3 Oct 2026 stay dated in September, and keep that date when their
--     invoices are worked out again; netting already gives the right figures
--     for them (re-dating them is a question for the Owner). The statuses are
--     not refreshed by this migration: the first run is at 00:05 the night
--     after it is applied, or when the Owner says to run it once now.
--   * refresh_legacy_therapy_statuses, refresh_therapy_statuses (the
--     beneficiaries' table, which has no rows on production), the legacy
--     claim, and invoice_transferable_benefits (the correction's preview of
--     what moves with the customer; it still lists the stored status, which
--     the nightly job keeps current, and the correction itself refuses).
--   * No table, column, index or constraint. Grants of every changed function
--     are kept; the three new functions are the service role's alone.
--
-- SAFETY
--
-- Apart from the lock timeout, the migration is one statement (a DO block),
-- so it is atomic however it is run. Every guard and anchor is checked, and
-- every new text built, before anything is installed. md5(pg_get_
-- functiondef) of each changed function must be the production version read
-- on 9 Oct 2026 (BEFORE), or already this migration's version (AFTER), which
-- is left alone so a re-run changes nothing; each new function must be
-- missing or already this version. The functions relied on but not changed
-- must be the versions read on 9 Oct 2026; the unit statuses allowed must be
-- the six read then and the commission statuses the five; pg_cron must be
-- installed and run on GMT. Every anchor must match exactly once. The new
-- texts are executed as CREATE OR REPLACE with the same arguments and result
-- types, which keeps owner and grants; no overload is added (another function
-- of any of these names refuses). The new functions are revoked from public,
-- anon and authenticated and granted to service_role (339). The cron job is
-- written only when it is not already there as this migration writes it, and
-- must then be there exactly once. The definitions are read and compared with
-- the search path set to public. After installing, every function must have
-- its AFTER md5 and the grants it had. No row of the app's tables changes; the
-- one row written is the cron job's (cron.job).
--
-- BEFORE (production, 9 Oct 2026, md5 of pg_get_functiondef):
--   affiliate_payout_overview()                                   b0884684b09cb5df6e9d5a3031b27b58
--   affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)
--                                                                 c7356c6021a35eb032a2375e798ace75
--   reconcile_invoice_commissions(uuid,text)                      50cb0727bbf7a5eb7d6b9ab983e973bc
--   affiliate_admin_directory()                                   4ed68f450ba136b2c3159455199c6467
--   affiliate_portal_earnings()                                   1a30d78f3e7010085ce9260a7502b713
--   affiliate_portal_purchases()                                  d8cb2232a7a0281fd0016b4b087a445c
--   therapy_unit_consumed(uuid)                                   7fe942b73bd10d566383d38c923162fe
--   refund_purchased_therapy(uuid,text)                           139dae3f12c5aeda0b1fff81cac0cc4b
--   reschedule_purchased_therapy(uuid,date,text)                  488e5fa3a10614820944a4205be76fac
--   claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)
--                                                                 cfd7e80d1db321cb7ee14a9acc786c55
--   activate_purchased_therapy(uuid,date,text,text,text,boolean)  22e9a92ab0c6bf578cef7cad0e363949
--   refresh_purchased_therapy_statuses()                          62040e83c7a24cd6028da29e8713fa86
--   cancel_invoice_recorded(uuid,text,uuid)                       30d643c7890c12d885ad83ba61ccf49a
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                   5158303778516180bab171ba951d8385
--   affiliate_referrer_balances()                                 (missing)
--   purchased_therapy_status_on(text,date,date,date,date)         (missing)
--   run_therapy_status_refresh()                                  (missing)
--   (relied on, not changed)
--   affiliate_month_balances()                                    2860675d40499f788036b76be3094702
--   affiliate_payout_review(uuid,date)                            b8e330efcb88277f965f67386406e0a4
--   commission_reporting_rows()                                   96962fa272f3eb35111c6ac199255410
--   commission_unpaid_amount(uuid)                                302f1439553092dbbd5009e3969f7ef2
--   sync_instalment_commissions(uuid,text,date,boolean,boolean)   88d7b122778801a0d5eea0b6dd8395b7
--   record_affiliate_payout(uuid,date,numeric,uuid,date,text,text,uuid)
--                                                                 e67ff1478637e77c379a18dcb8797a2b
--   correct_affiliate_payout(uuid,integer,numeric,uuid,date,text,text,text,uuid)
--                                                                 e69c904cd0d5f9b806dc2be97870c0ab
--   referrer_list()                                               c2596f5b32f26ae4c9f737b9e0320a09
--   referrer_earnings(uuid)                                       b74826ed6ccfbc82cff8258b0678ec12
--   refresh_legacy_therapy_statuses()                             6de4ab99525f70a282f2889b7694ac41
--   sg_today()                                                    1c1289f18e24d8370e9a6364c9c06fca
-- AFTER (for later guards):
--   affiliate_referrer_balances()                                 54ef098ba8f9e3d81bb45906c4607ab6
--   purchased_therapy_status_on(text,date,date,date,date)         991ec75f0349f61ef1a2f3682fb142b1
--   run_therapy_status_refresh()                                  0d10378270574e2ba7d15f9626b7300d
--   affiliate_payout_overview()                                   9a1c584766b2aaefb07012895932c0c8
--   affiliate_payout_save(...)                                    59707475f768cbd500a47912524bd947
--   reconcile_invoice_commissions(uuid,text)                      3c267728e215d17ebeb9cfe9cb7db47c
--   affiliate_admin_directory()                                   f3cd99cefb5931b0266d1fba6fde53b3
--   affiliate_portal_earnings()                                   248af74df2f705e43ee110dbaaf4f6fa
--   affiliate_portal_purchases()                                  a5e5c99ae092d2fbea35f3f7d8dc90f0
--   therapy_unit_consumed(uuid)                                   9ea1884a2357c1af7f0e9c82a85c73e3
--   refund_purchased_therapy(uuid,text)                           82bfeaa5f54a4ff3b7495bca6e9ed7bf
--   reschedule_purchased_therapy(uuid,date,text)                  52b37e85c1677199a2335b31f24ac4a3
--   claim_purchased_therapy(...)                                  44abcd5d179fa7d24438c4c44cc0be8f
--   activate_purchased_therapy(...)                               0c4f319294981cd5efef616781d54a2b
--   refresh_purchased_therapy_statuses()                          0f9076a6456eaf7cdc995d5b7fbbb8d2
--   cancel_invoice_recorded(uuid,text,uuid)                       e8ce9cc4f62896bff144893fdc42225d
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                   5f3f317dfb226be09055142dc44bdec7
--
-- DEPLOY ORDER: this, then the pages (pushing to main deploys them). The
-- pages live now keep working against it: every key they read is still sent,
-- the Affiliates page's Unpaid shows S$0.00 rather than a negative figure,
-- and a payout they offer beyond what is payable is refused with the reason.
-- The new pages against a database without this work the payable and the
-- deduction out themselves from the months and the signed figures sent, the
-- same way (the payout itself is then still capped by the month alone, as
-- before). After applying, with the Owner's go-ahead, run
-- the refresh once (select public.run_therapy_status_refresh();) rather than
-- waiting for 00:05.
--
-- Test: scripts/commissions/tests/clawbacks-carried-forward.sql and
-- scripts/therapy/tests/status-refresh.sql (each applies this inside its own
-- rolled-back transaction; on a local database that has drifted from
-- production, pass a prelude that installs production's functions); the
-- pages: scripts/commissions/tests/clawback-presentation.test.mjs,
-- payout-panel-deductions.test.mjs, scripts/reports/tests/
-- reports-page.test.mjs and scripts/therapy/tests/status.test.mjs,
-- therapy-page-status.test.mjs. To rebase on new production texts:
-- scripts/commissions/tests/refill-410-md5s.py refills the AFTER md5s, and
-- scripts/commissions/tests/mutate-410.py re-runs the mutation checks.

set lock_timeout = '5s';

do $mig$
declare
  -- ── New: an affiliate's months netted ───────────────────────────────────────
  c_refbal_def constant text := $def$
create or replace function public.affiliate_referrer_balances()
returns table(referrer uuid, owed numeric, unpaid numeric, deduction numeric, payable numeric)
language sql
stable
security definer
set search_path = public
as $fn$
  -- 410: each affiliate's commission netted across months (the Owner, 3 Oct
  -- 2026: commission already paid out and then taken back is recovered from
  -- the affiliate's later commission). The one place the netting is written.
  --   owed       every month's balance added up (affiliate_month_balances:
  --              earned, less adjustments, less what was paid out); below 0
  --              while commission paid out and taken back is still to be
  --              recovered.
  --   unpaid     what is still owed to the affiliate: owed, never below 0.
  --   deduction  what is still to be recovered from them: -owed, never
  --              below 0.
  --   payable    the most a payout added now may come to: owed, where a
  --              month whose payouts need review, or a row with no date,
  --              counts only when it is negative (its positive balance is not
  --              paid until it is reviewed); never below 0.
  select b.referrer,
         sum(b.balance),
         greatest(sum(b.balance), 0),
         greatest(-sum(b.balance), 0),
         greatest(sum(case when b.month is not null and b.review_reason is null then b.balance
                           else least(b.balance, 0) end), 0)
    from public.affiliate_month_balances() b
   group by b.referrer
$fn$
$def$;

  -- ── New: a purchased therapy unit's status by its dates ──────────────────
  c_status_on_def constant text := $def$
create or replace function public.purchased_therapy_status_on(p_status text, p_activation date, p_expiry date,
                                                              p_deadline date, p_on date)
returns text
language sql
immutable
set search_path = public
as $fn$
  -- 410: the status a purchased therapy unit has on p_on by its dates, the
  -- one place the rule is written. The nightly refresh stores it
  -- (refresh_purchased_therapy_statuses), and the checks on claiming,
  -- starting, refunding and rescheduling read it, so none of them depends on
  -- the refresh having run.
  --   * scheduled, with a start date on or before p_on: started (active), or
  --     ended (expired) if its expiry is before p_on too;
  --   * active, with an expiry before p_on: expired;
  --   * never started (pending, or scheduled with no start date) and past its
  --     activation deadline: expired;
  --   * otherwise as it is (cancelled and refunded included).
  select case
    when p_status = 'scheduled' and p_activation is not null and p_activation <= p_on then
      case when p_expiry is not null and p_expiry < p_on then 'expired' else 'active' end
    when p_status = 'active' and p_expiry is not null and p_expiry < p_on then 'expired'
    when p_status in ('pending_activation', 'scheduled') and p_activation is null
         and p_deadline is not null and p_deadline < p_on then 'expired'
    else p_status
  end
$fn$
$def$;

  -- ── The purchased refresh, replaced whole ────────────────────────────────
  c_refresh_def constant text := $def$
create or replace function public.refresh_purchased_therapy_statuses()
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare v_n integer := 0; v_today date := public.sg_today(); r record;
begin
  -- 410: every unit takes the status its dates give it today
  -- (purchased_therapy_status_on, where the rule is written). Run every night
  -- at 00:05 Singapore time by run_therapy_status_refresh (cron job
  -- 'therapy-status-refresh'). Units that end go first, so a period that has
  -- ended gives up its days before one that starts takes them. A unit that
  -- cannot be moved (the same-package rule refusing its start, say) is left
  -- as it is, with a warning in the database log, and the others still move:
  -- the checks on claiming, refunding and rescheduling read its dates, not
  -- this status. Returns how many units changed (before 410: how many
  -- started).
  for r in
    select x.id, x.entitlement_no, x.status, x.new_status
      from (select e.id, e.entitlement_no, e.status, e.activation_date,
                   public.purchased_therapy_status_on(e.status, e.activation_date, e.expiry_date,
                                                      e.activation_deadline, v_today) as new_status
              from public.purchased_therapy_entitlements e
             where e.status in ('pending_activation', 'scheduled', 'active')) x
     where x.new_status is distinct from x.status
     order by (x.new_status = 'expired') desc, x.activation_date nulls last, x.id
  loop
    begin
      update public.purchased_therapy_entitlements
         set status = r.new_status, updated_at = now()
       where id = r.id and status = r.status;
      if found then v_n := v_n + 1; end if;
    exception when others then
      raise warning 'Therapy unit % stays % (by its dates it is %): %',
        r.entitlement_no, r.status, r.new_status, sqlerrm;
    end;
  end loop;
  return v_n;
end
$fn$
$def$;

  -- ── New: the nightly run ─────────────────────────────────────────────────
  c_run_def constant text := $def$
create or replace function public.run_therapy_status_refresh()
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare v_purchased integer; v_legacy integer;
begin
  -- 410: the nightly therapy status refresh (cron job
  -- 'therapy-status-refresh', 00:05 Singapore time): purchased units, then
  -- Legacy entitlements. The checks on claiming, refunding and rescheduling
  -- read the dates themselves, so a night this does not run leaves only the
  -- statuses shown out of date. Returns what changed, and the purchased units
  -- still out of step with their dates (one the refresh could not move).
  v_purchased := public.refresh_purchased_therapy_statuses();
  v_legacy := public.refresh_legacy_therapy_statuses();
  return jsonb_build_object(
    'on', public.sg_today(),
    'purchased_changed', v_purchased,
    'legacy_expired', v_legacy,
    'purchased_left', (select coalesce(jsonb_agg(e.entitlement_no order by e.entitlement_no), '[]'::jsonb)
                         from public.purchased_therapy_entitlements e
                        where e.status is distinct from public.purchased_therapy_status_on(
                                e.status, e.activation_date, e.expiry_date, e.activation_deadline,
                                public.sg_today())));
end
$fn$
$def$;

  -- ── Anchors and their replacements ─────────────────────────────────────────
  -- affiliate_payout_overview: each month's payable, the affiliate's figures.
  c_overview_a constant text := $q$  'groups',(select coalesce(jsonb_agg(to_jsonb(b) order by month desc nulls last,referrer),'[]') from public.affiliate_month_balances() b),
$q$;
  c_overview_r constant text := $q$  -- 410: each month also carries what may be paid for it now (payable): the
  -- affiliate's payable (affiliate_referrer_balances) shown against their
  -- months with a positive balance, oldest first, so their months add up to
  -- it; a month under review, or with no date, gets none. And the affiliate's
  -- own figures on every month; 'referrers' lists them once each.
  'groups',(select coalesce(jsonb_agg(to_jsonb(b) order by month desc nulls last,referrer),'[]') from (
   select m.*,
    greatest(least(case when m.month is not null and m.review_reason is null then greatest(m.balance,0) else 0 end,
     r.payable-coalesce(sum(case when m.month is not null and m.review_reason is null then greatest(m.balance,0) else 0 end)
      over(partition by m.referrer order by m.month nulls last rows between unbounded preceding and 1 preceding),0)),0) as payable,
    r.owed as referrer_owed,r.payable as referrer_payable,r.deduction as referrer_deduction
   from public.affiliate_month_balances() m join public.affiliate_referrer_balances() r on r.referrer=m.referrer) b),
  'referrers',(select coalesce(jsonb_agg(to_jsonb(r) order by r.referrer),'[]') from public.affiliate_referrer_balances() r),
$q$;

  -- affiliate_payout_save: never beyond what the affiliate can be paid now.
  c_save_decl_a constant text := $q$ available numeric; delta numeric; issue text; entry record; v_id uuid; v_referrer uuid; v_month date;
$q$;
  c_save_decl_r constant text := $q$ available numeric; delta numeric; issue text; entry record; v_id uuid; v_referrer uuid; v_month date;
 v_payable numeric; v_deduction numeric;  -- 410: the affiliate's months netted
$q$;
  c_save_cap_a constant text := $q$  if delta>0 and delta>coalesce(available,0) then raise exception 'Amount exceeds the remaining payable balance of S$%. Refresh the summary.',greatest(coalesce(available,0),0); end if;
$q$;
  c_save_cap_r constant text := $q$  if delta>0 and delta>coalesce(available,0) then raise exception 'Amount exceeds the remaining payable balance of S$%. Refresh the summary.',greatest(coalesce(available,0),0); end if;
  -- 410: commission already paid out and then taken back is recovered from
  -- the affiliate's later commission (the Owner, 3 Oct 2026): nothing more is
  -- paid while their months, netted, owe it back, and never more than they
  -- net to (affiliate_referrer_balances).
  if delta>0 then
   select r.payable,r.deduction into v_payable,v_deduction from public.affiliate_referrer_balances() r where r.referrer=v_referrer;
   if delta>coalesce(v_payable,0) then
    if coalesce(v_deduction,0)>0 then
     raise exception 'This affiliate still owes S$% back from commission already paid out and then taken back. It is recovered from their later commission first, so nothing more can be paid yet. Refresh the summary.',v_deduction; end if;
    raise exception 'Amount exceeds what this affiliate can be paid now once all their months are counted, S$%. Refresh the summary.',greatest(coalesce(v_payable,0),0); end if;
  end if;
$q$;

  -- reconcile_invoice_commissions: what was paid out is taken back today.
  c_rec_decl_a constant text := $q$declare i public.invoices%rowtype; c record; v_share numeric; v_before uuid[]; v_staff_before uuid[];
$q$;
  c_rec_decl_r constant text := $q$declare i public.invoices%rowtype; c record; v_share numeric; v_before uuid[]; v_staff_before uuid[];
 -- 410: taking back commission already paid out (the loop near the end)
 g record; m record; v_carried uuid[]; v_a jsonb; v_left numeric; v_paid numeric; v_q numeric; v_mem numeric;
 v_kept numeric; v_take numeric; v_off numeric; v_drop numeric; v_cut numeric;
$q$;
  c_rec_before_a constant text := $q$ select array_agg(id) into v_before from public.commissions where invoice_id=i.id;
$q$;
  c_rec_before_r constant text := $q$ select array_agg(id) into v_before from public.commissions where invoice_id=i.id;
 -- 410: the take-backs of commission already paid out that stand before this
 -- run. The update below reverses them; the loop near the end writes them
 -- again on the dates they had.
 select array_agg(id) into v_carried from public.commissions
  where invoice_id=i.id and earning_basis='settlement' and status='earned' and payout_id is null
    and adjusts_commission_id is not null and commission_amount<0
    and reversal_reason like 'Future payout adjustment: %';
$q$;
  c_rec_loop_a constant text := $q$ for c in select * from public.commissions where invoice_id=i.id and (payout_id is not null or status='paid') and earning_basis='settlement' loop
   insert into public.commissions select (jsonb_populate_record(null::public.commissions,to_jsonb(c)||jsonb_build_object(
    'id',gen_random_uuid(),'payout_id',null,'status','earned','commission_amount',-c.commission_amount,
    'line_amount',-c.line_amount,'adjusts_commission_id',c.id,'created_at',now(),
    'reversed_at',null,'reversal_reason','Future payout adjustment: '||p_reason))).*;
 end loop;
$q$;
  c_rec_loop_r constant text := $q$ -- 410: commission already paid out and then taken back is recovered from the
 -- affiliate's later commission (the Owner, 3 Oct 2026), and a month already
 -- paid stays as it was paid. Per affiliate and tier on this invoice, what its
 -- paid rows paid out (commission_unpaid_amount tells the rest) is
 --   * netted against what the sale still earns them (the rows earned again
 --     above), by a row linked to the row earned again and in its month, so
 --     that commission is never paid a second time ("Already paid out on this
 --     sale");
 --   * for the rest, taken back from their later commission ("Future payout
 --     adjustment"). These rows are written again on every run, so the ones
 --     standing before this run (v_carried) are written again on the dates
 --     they had, and only what is taken back beyond them is dated today in
 --     Singapore: a take-back never moves to a later month because the invoice
 --     was worked out again. They are lowered, newest first, only when they
 --     come to more than was paid out (a payout lowered, or a row taken back
 --     whole before 410). When the sale earns more again (a refund undone),
 --     they stay, and what is earned again is owed in its own month.
 -- What a paid row never paid out is cancelled in its own month ("Unpaid
 -- commission cancelled"), as the part-payment layer does (357). Before 410
 -- every paid row was taken back whole in its own month.
 for g in select x.referrer_customer_id as referrer, x.tier from public.commissions x
           where x.invoice_id=i.id and (x.payout_id is not null or x.status='paid') and x.earning_basis='settlement'
           group by 1,2 order by 1,2 loop
   v_paid:=0; v_a:=null;
   for c in select * from public.commissions where invoice_id=i.id and (payout_id is not null or status='paid')
              and earning_basis='settlement' and referrer_customer_id=g.referrer and tier=g.tier
            order by invoice_paid_date,created_at,id loop
     if c.commission_amount<=0 then
       -- a paid row that is not positive (none on production, 9 Oct 2026):
       -- taken back in its own month, as before 410
       if c.commission_amount<0 then
       insert into public.commissions select (jsonb_populate_record(null::public.commissions,to_jsonb(c)||jsonb_build_object(
        'id',gen_random_uuid(),'payout_id',null,'status','earned','commission_amount',-c.commission_amount,
        'line_amount',-c.line_amount,'adjusts_commission_id',c.id,'created_at',now(),
        'reversed_at',null,'reversal_reason','Future payout adjustment: '||p_reason))).*;
       end if;
       continue;
     end if;
     v_left:=least(greatest(coalesce(public.commission_unpaid_amount(c.id),0),0),c.commission_amount);
     v_paid:=v_paid+c.commission_amount-v_left;
     if v_a is null and c.commission_amount>v_left then v_a:=to_jsonb(c); end if;
     if v_left<>0 then
     insert into public.commissions select (jsonb_populate_record(null::public.commissions,to_jsonb(c)||jsonb_build_object(
      'id',gen_random_uuid(),'payout_id',null,'status','earned','commission_amount',-v_left,
      'line_amount',-round(c.line_amount*v_left/c.commission_amount,2),'adjusts_commission_id',c.id,'created_at',now(),
      'reversed_at',null,'reversal_reason','Unpaid commission cancelled: '||coalesce(p_reason,'')))).*;
     end if;
   end loop;
   -- what the sale earns them now, and what was taken back before this run
   select coalesce(sum(n.commission_amount),0) into v_q from public.commissions n
    where n.invoice_id=i.id and n.earning_basis='settlement' and n.status='earned' and n.payout_id is null
      and n.adjusts_commission_id is null and n.commission_amount>0
      and n.referrer_customer_id=g.referrer and n.tier=g.tier and not (n.id=any(coalesce(v_before,'{}'::uuid[])));
   select coalesce(-sum(t.commission_amount),0) into v_mem from public.commissions t
    where t.id=any(coalesce(v_carried,'{}'::uuid[])) and t.referrer_customer_id=g.referrer and t.tier=g.tier;
   v_kept:=least(v_mem,v_paid);              -- never more than was paid out
   v_take:=v_paid-least(v_paid,v_q);         -- what the sale no longer earns of it
   v_off:=v_paid-greatest(v_take,v_kept);    -- netted against what it still earns
   v_drop:=v_mem-v_kept;
   for m in select * from public.commissions t
             where t.id=any(coalesce(v_carried,'{}'::uuid[])) and t.referrer_customer_id=g.referrer and t.tier=g.tier
             order by t.invoice_paid_date desc,t.created_at desc,t.id desc loop
     v_cut:=least(v_drop,-m.commission_amount); v_drop:=v_drop-v_cut;
     if m.commission_amount+v_cut<0 then
     insert into public.commissions select (jsonb_populate_record(null::public.commissions,to_jsonb(m)||jsonb_build_object(
      'id',gen_random_uuid(),'payout_id',null,'status','earned','commission_amount',m.commission_amount+v_cut,
      'line_amount',round(m.line_amount*(m.commission_amount+v_cut)/m.commission_amount,2),'created_at',now(),
      'reversed_at',null,'reversal_reason','Future payout adjustment: '||coalesce(p_reason,'')))).*;
     end if;
   end loop;
   if v_take>v_kept then
   insert into public.commissions select (jsonb_populate_record(null::public.commissions,v_a||jsonb_build_object(
    'id',gen_random_uuid(),'payout_id',null,'status','earned','commission_amount',-(v_take-v_kept),
    'line_amount',-round((v_a->>'line_amount')::numeric*(v_take-v_kept)/(v_a->>'commission_amount')::numeric,2),
    'adjusts_commission_id',v_a->>'id','invoice_paid_date',public.sg_today(),'created_at',now(),
    'reversed_at',null,'reversal_reason','Future payout adjustment: '||coalesce(p_reason,'')))).*;
   end if;
   for m in select * from public.commissions n
             where n.invoice_id=i.id and n.earning_basis='settlement' and n.status='earned' and n.payout_id is null
               and n.adjusts_commission_id is null and n.commission_amount>0
               and n.referrer_customer_id=g.referrer and n.tier=g.tier and not (n.id=any(coalesce(v_before,'{}'::uuid[])))
             order by n.invoice_paid_date,n.created_at,n.id loop
     exit when v_off<=0;
     v_cut:=least(v_off,m.commission_amount); v_off:=v_off-v_cut;
     insert into public.commissions select (jsonb_populate_record(null::public.commissions,to_jsonb(m)||jsonb_build_object(
      'id',gen_random_uuid(),'payout_id',null,'status','earned','commission_amount',-v_cut,
      'line_amount',-round(m.line_amount*v_cut/m.commission_amount,2),'adjusts_commission_id',m.id,'created_at',now(),
      'reversed_at',null,'reversal_reason','Already paid out on this sale: '||coalesce(p_reason,'')))).*;
   end loop;
 end loop;
$q$;

  -- affiliate_admin_directory: unpaid and the deduction netted; blocked.
  c_dir_unpaid_a constant text := $q$    'unpaid', (select coalesce(sum(balance),0) from public.affiliate_month_balances() where referrer = ca.customer_id),
$q$;
  c_dir_unpaid_r constant text := $q$    -- 410: what the affiliate is still owed and what is still to be recovered
    -- from them, their months netted (affiliate_referrer_balances).
    'unpaid', coalesce(rb.unpaid, 0), 'deduction', coalesce(rb.deduction, 0),
$q$;
  c_dir_blocked_a constant text := $q$    'blocked', (select coalesce(sum(commission_amount),0) from public.commission_reporting_rows() where referrer_customer_id = ca.customer_id and status = 'cancelled'),
$q$;
  c_dir_blocked_r constant text := $q$    -- 410: commission withheld is written 'blocked' ('cancelled' kept as before).
    'blocked', (select coalesce(sum(commission_amount),0) from public.commission_reporting_rows() where referrer_customer_id = ca.customer_id and status in ('blocked','cancelled')),
$q$;
  c_dir_join_a constant text := $q$  left join public.affiliate_accounts acc on acc.customer_id = ca.customer_id
$q$;
  c_dir_join_r constant text := $q$  left join public.affiliate_accounts acc on acc.customer_id = ca.customer_id
  left join public.affiliate_referrer_balances() rb on rb.referrer = ca.customer_id  -- 410
$q$;

  -- affiliate_portal_earnings: never a negative Unpaid; the deduction; blocked.
  c_earn_blocked_a constant text := $q$    coalesce(sum(commission_amount) filter (where status='cancelled'),0),
$q$;
  c_earn_blocked_r constant text := $q$    coalesce(sum(commission_amount) filter (where status in ('blocked','cancelled')),0),  -- 410: withheld is 'blocked'
$q$;
  c_earn_sum_a constant text := $q$    'summary', jsonb_build_object('lifetime', v_lifetime, 'unpaid', v_unpaid, 'paid', v_paid,
$q$;
  c_earn_sum_r constant text := $q$    -- 410: never a negative Unpaid; what is still to be recovered from the
    -- affiliate (commission paid out and then taken back) is the deduction.
    'summary', jsonb_build_object('lifetime', v_lifetime, 'unpaid', greatest(v_unpaid, 0),
      'deduction', greatest(-v_unpaid, 0), 'paid', v_paid,
$q$;

  -- affiliate_portal_purchases: withheld is Blocked, not Reversed.
  c_purch_a constant text := $q$      case when coalesce(sum(cm.commission_amount) filter(where cm.status in ('earned','paid')),0)<=0 then 'reversed'
$q$;
  c_purch_r constant text := $q$      -- 410: all of it withheld (the affiliate not activated, say) is 'blocked'.
      case when not bool_or(cm.status in ('earned','paid')) and bool_or(cm.status in ('blocked','cancelled')) then 'blocked'
        when coalesce(sum(cm.commission_amount) filter(where cm.status in ('earned','paid')),0)<=0 then 'reversed'
$q$;

  -- therapy_unit_consumed: started or ended by its dates.
  c_consumed_a constant text := $q$       and (e.status in ('active','expired')
$q$;
  c_consumed_r constant text := $q$       -- 410: by its dates, whether or not the nightly refresh has run
       and (public.purchased_therapy_status_on(e.status, e.activation_date, e.expiry_date,
                                               e.activation_deadline, public.sg_today()) in ('active','expired')
$q$;

  -- refund_purchased_therapy: started or ended by its dates.
  c_refund_v_a constant text := $q$     and e.status not in ('active','expired')
$q$;
  c_refund_v_r constant text := $q$     and public.purchased_therapy_status_on(e.status, e.activation_date, e.expiry_date,
                                           e.activation_deadline, public.sg_today()) not in ('active','expired')  -- 410
$q$;
  c_refund_a constant text := $q$  if e.status in ('active','expired') then
    -- Money is not moved here; this terminates the entitlement only. Refunding
    -- the money for an activated entitlement goes through the invoice, where
    -- the payment ceiling and prior refunds are enforced.
    raise exception 'Therapy cannot be refunded after activation from here. Use the invoice''s Refund / Cancel flow, where an Owner/Manager can authorize the termination and state the amount.';
$q$;
  c_refund_r constant text := $q$  -- 410: by its dates as well (the nightly refresh may not have run yet): a
  -- start date already reached has started; one never started by its
  -- deadline has expired.
  if public.purchased_therapy_status_on(e.status, e.activation_date, e.expiry_date,
                                        e.activation_deadline, public.sg_today()) in ('active','expired') then
    -- Money is not moved here; this terminates the entitlement only. Refunding
    -- the money for an activated entitlement goes through the invoice, where
    -- the payment ceiling and prior refunds are enforced.
    if e.activation_date is null then
      raise exception 'This therapy was not started by its activation deadline%, so it has expired and cannot be refunded from here. Use the invoice''s Refund / Cancel flow, where an Owner/Manager can authorize the termination and state the amount.',
        coalesce(' (' || e.activation_deadline::text || ')', ''); end if;
    raise exception 'Therapy cannot be refunded after activation from here. Use the invoice''s Refund / Cancel flow, where an Owner/Manager can authorize the termination and state the amount.';
$q$;

  -- cancel_invoice_recorded: only units not started by their dates close as refunded.
  c_cancel_a constant text := $q$ update public.purchased_therapy_entitlements set status='refunded',updated_at=now() where invoice_id=i.id and status in ('pending_activation','scheduled');
$q$;
  c_cancel_r constant text := $q$ -- 410: by its dates as well (the nightly refresh may not have run yet): a
 -- unit whose start date has been reached has started, and one never started
 -- by its deadline has expired, so neither is closed here as unused. Like an
 -- active one, it is left for the invoice's refund, where an Owner or Manager
 -- authorizes ending it (therapy_unit_consumed reads the same rule).
 update public.purchased_therapy_entitlements set status='refunded',updated_at=now() where invoice_id=i.id and status in ('pending_activation','scheduled')
   and public.purchased_therapy_status_on(status,activation_date,expiry_date,activation_deadline,public.sg_today()) in ('pending_activation','scheduled');
$q$;

  -- correct_invoice: started or ended by its dates.
  c_correct_a constant text := $q$ if v_operational and exists(select 1 from public.purchased_therapy_entitlements where invoice_id=i.id and status in ('active','expired')) then
$q$;
  c_correct_r constant text := $q$ -- 410: by its dates as well (the nightly refresh may not have run yet).
 if v_operational and exists(select 1 from public.purchased_therapy_entitlements where invoice_id=i.id
     and public.purchased_therapy_status_on(status,activation_date,expiry_date,activation_deadline,public.sg_today()) in ('active','expired')) then
$q$;

  -- reschedule_purchased_therapy: before activation by its dates; no start date.
  c_resched_a constant text := $q$  if e.status not in ('pending_activation','scheduled') then
    raise exception 'Dates can only be changed before activation'; end if;
$q$;
  c_resched_r constant text := $q$  -- 410: by its dates as well (the nightly refresh may not have run yet): a
  -- start date already reached has started.
  if public.purchased_therapy_status_on(e.status, e.activation_date, e.expiry_date,
                                        e.activation_deadline, v_today) not in ('pending_activation','scheduled') then
    raise exception 'Dates can only be changed before activation'; end if;
  -- 410: with a start date set (Claim), this would change only the date
  -- shown, not the start, the expiry or the closure days. Moving the start is
  -- a new Claim, which works them out again.
  if e.activation_date is not null then
    raise exception 'This therapy is set to start on %. To move its start, use Claim, which works out the expiry again.',
      e.activation_date; end if;
$q$;

  -- claim_purchased_therapy: started or ended by its dates.
  c_claim_decl_a constant text := $q$        v_label text;
$q$;
  c_claim_decl_r constant text := $q$        v_label text;
        v_now text;  -- 410: the unit's status by its dates
$q$;
  c_claim_a constant text := $q$    if e.status in ('active','expired') then
      raise exception 'Unlimited therapy on this purchase has already %',
        case e.status when 'active' then 'started' else 'ended' end; end if;
$q$;
  c_claim_r constant text := $q$    -- 410: by its dates as well (the nightly refresh may not have run yet): a
    -- scheduled start already reached has started, so it is not started
    -- again or moved.
    v_now := public.purchased_therapy_status_on(e.status, e.activation_date, e.expiry_date,
                                                e.activation_deadline, public.sg_today());
    if v_now in ('active','expired') then
      raise exception 'Unlimited therapy on this purchase has already %',
        case when v_now = 'active' then 'started'
             when e.activation_date is null then 'expired: it was not started by its deadline, ' || e.activation_deadline
             else 'ended' end; end if;
$q$;

  -- activate_purchased_therapy: started or ended by its dates.
  c_act_decl_a constant text := $q$  v_next jsonb; v_overlaps boolean;
$q$;
  c_act_decl_r constant text := $q$  v_next jsonb; v_overlaps boolean;
  v_now text;  -- 410: the unit's status by its dates
$q$;
  c_act_a constant text := $q$  if e.status in ('active','expired','cancelled','refunded') then
    raise exception 'Entitlement is already %', e.status; end if;
$q$;
  c_act_r constant text := $q$  -- 410: by its dates as well (the nightly refresh may not have run yet): a
  -- scheduled start already reached has started.
  v_now := public.purchased_therapy_status_on(e.status, e.activation_date, e.expiry_date,
                                              e.activation_deadline, v_today);
  if v_now in ('active','expired','cancelled','refunded') then
    raise exception 'Entitlement is already %', v_now; end if;
$q$;

  c_refbal_after constant text := '54ef098ba8f9e3d81bb45906c4607ab6';
  c_status_on_after constant text := '991ec75f0349f61ef1a2f3682fb142b1';
  c_run_after constant text := '0d10378270574e2ba7d15f9626b7300d';
  c_overview_after constant text := '9a1c584766b2aaefb07012895932c0c8';
  c_save_after constant text := '59707475f768cbd500a47912524bd947';
  c_reconcile_after constant text := '3c267728e215d17ebeb9cfe9cb7db47c';
  c_directory_after constant text := 'f3cd99cefb5931b0266d1fba6fde53b3';
  c_earnings_after constant text := '248af74df2f705e43ee110dbaaf4f6fa';
  c_purchases_after constant text := 'a5e5c99ae092d2fbea35f3f7d8dc90f0';
  c_consumed_after constant text := '9ea1884a2357c1af7f0e9c82a85c73e3';
  c_refund_after constant text := '82bfeaa5f54a4ff3b7495bca6e9ed7bf';
  c_resched_after constant text := '52b37e85c1677199a2335b31f24ac4a3';
  c_claim_after constant text := '44abcd5d179fa7d24438c4c44cc0be8f';
  c_activate_after constant text := '0c4f319294981cd5efef616781d54a2b';
  c_refresh_after constant text := '0f9076a6456eaf7cdc995d5b7fbbb8d2';
  c_cancel_after constant text := 'e8ce9cc4f62896bff144893fdc42225d';
  c_correct_after constant text := '5f3f317dfb226be09055142dc44bdec7';

  -- The unit and commission statuses read on 9 Oct 2026 (rule 7 and the
  -- netting are written for these). The commission statuses are compared as a
  -- set: production's enum lists them in another order than a fresh install.
  c_unit_statuses constant text :=
    'CHECK ((status = ANY (ARRAY[''pending_activation''::text, ''scheduled''::text, ''active''::text, ''expired''::text, ''cancelled''::text, ''refunded''::text])))';
  c_commission_statuses constant text := 'blocked,cancelled,earned,paid,reversed';
  -- The nightly job: 16:05 GMT is 00:05 in Singapore.
  c_job constant text := 'therapy-status-refresh';
  c_job_schedule constant text := '5 16 * * *';
  c_job_command constant text := 'select public.run_therapy_status_refresh()';
  c_new constant text[] := array['affiliate_referrer_balances()', 'purchased_therapy_status_on(text,date,date,date,date)',
                                 'run_therapy_status_refresh()'];

  v_path text := current_setting('search_path');
  r record; d text; v text; n int; k int; i int; v_bad text; v_tz text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[]; v_changed text[] := '{}';
begin
  -- The definitions are read and compared with public alone on the search
  -- path, as they were read on 9 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── Guards, anchors and new texts: nothing is installed unless all pass ────
  -- In install order: the two helpers, what reads them, the refresh, then the
  -- nightly run that calls the refresh.
  for r in select * from (values
    ('affiliate_referrer_balances()', null::text, c_refbal_after, c_refbal_def, null::text[]),
    ('purchased_therapy_status_on(text,date,date,date,date)', null::text, c_status_on_after, c_status_on_def, null::text[]),
    ('affiliate_payout_overview()', 'b0884684b09cb5df6e9d5a3031b27b58', c_overview_after, null::text,
     array[[c_overview_a, c_overview_r]]),
    ('affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)',
     'c7356c6021a35eb032a2375e798ace75', c_save_after, null::text,
     array[[c_save_decl_a, c_save_decl_r], [c_save_cap_a, c_save_cap_r]]),
    ('reconcile_invoice_commissions(uuid,text)', '50cb0727bbf7a5eb7d6b9ab983e973bc', c_reconcile_after, null::text,
     array[[c_rec_decl_a, c_rec_decl_r], [c_rec_before_a, c_rec_before_r], [c_rec_loop_a, c_rec_loop_r]]),
    ('affiliate_admin_directory()', '4ed68f450ba136b2c3159455199c6467', c_directory_after, null::text,
     array[[c_dir_unpaid_a, c_dir_unpaid_r], [c_dir_blocked_a, c_dir_blocked_r], [c_dir_join_a, c_dir_join_r]]),
    ('affiliate_portal_earnings()', '1a30d78f3e7010085ce9260a7502b713', c_earnings_after, null::text,
     array[[c_earn_blocked_a, c_earn_blocked_r], [c_earn_sum_a, c_earn_sum_r]]),
    ('affiliate_portal_purchases()', 'd8cb2232a7a0281fd0016b4b087a445c', c_purchases_after, null::text,
     array[[c_purch_a, c_purch_r]]),
    ('therapy_unit_consumed(uuid)', '7fe942b73bd10d566383d38c923162fe', c_consumed_after, null::text,
     array[[c_consumed_a, c_consumed_r]]),
    ('refund_purchased_therapy(uuid,text)', '139dae3f12c5aeda0b1fff81cac0cc4b', c_refund_after, null::text,
     array[[c_refund_v_a, c_refund_v_r], [c_refund_a, c_refund_r]]),
    ('reschedule_purchased_therapy(uuid,date,text)', '488e5fa3a10614820944a4205be76fac', c_resched_after, null::text,
     array[[c_resched_a, c_resched_r]]),
    ('claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)', 'cfd7e80d1db321cb7ee14a9acc786c55',
     c_claim_after, null::text, array[[c_claim_decl_a, c_claim_decl_r], [c_claim_a, c_claim_r]]),
    ('activate_purchased_therapy(uuid,date,text,text,text,boolean)', '22e9a92ab0c6bf578cef7cad0e363949',
     c_activate_after, null::text, array[[c_act_decl_a, c_act_decl_r], [c_act_a, c_act_r]]),
    ('refresh_purchased_therapy_statuses()', '62040e83c7a24cd6028da29e8713fa86', c_refresh_after, c_refresh_def, null::text[]),
    ('cancel_invoice_recorded(uuid,text,uuid)', '30d643c7890c12d885ad83ba61ccf49a', c_cancel_after, null::text,
     array[[c_cancel_a, c_cancel_r]]),
    ('correct_invoice(uuid,jsonb,jsonb,text,uuid)', '5158303778516180bab171ba951d8385', c_correct_after, null::text,
     array[[c_correct_a, c_correct_r]]),
    ('run_therapy_status_refresh()', null::text, c_run_after, c_run_def, null::text[])
  ) x(fn, before_md5, after_md5, whole, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      if r.before_md5 is not null then
        raise exception '410: public.% is missing', r.fn; end if;
      -- A new function, not there yet.
      v_fns := v_fns || r.fn;
      v_defs := v_defs || r.whole;
      continue;
    end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '410: public.% is already this version; left alone', r.fn;
      continue;
    elsif r.before_md5 is null then
      raise exception '410: public.% already exists with another text (md5 %). Re-read it and re-test before applying.', r.fn, v;
    elsif v <> r.before_md5 then
      raise exception '410: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    if r.edits is null then
      d := r.whole;
    else
      for k in 1 .. array_length(r.edits, 1) loop
        n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
        if n <> 1 then
          raise exception '410: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
        d := replace(d, r.edits[k][1], r.edits[k][2]);
      end loop;
    end if;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;

  -- Relied on, not changed: the versions read on 9 Oct 2026 (a month's
  -- balance, the review of a month, the reporting rows, what of a row is
  -- unpaid, the part-payment layer's take-backs, the payout wrappers, the
  -- figures the Referrers tab shows as a deduction when negative, the Legacy
  -- refresh, today in Singapore).
  for r in select * from (values
    ('affiliate_month_balances()', '2860675d40499f788036b76be3094702'),
    ('affiliate_payout_review(uuid,date)', 'b8e330efcb88277f965f67386406e0a4'),
    ('commission_reporting_rows()', '96962fa272f3eb35111c6ac199255410'),
    ('commission_unpaid_amount(uuid)', '302f1439553092dbbd5009e3969f7ef2'),
    ('sync_instalment_commissions(uuid,text,date,boolean,boolean)', '88d7b122778801a0d5eea0b6dd8395b7'),
    ('record_affiliate_payout(uuid,date,numeric,uuid,date,text,text,uuid)', 'e67ff1478637e77c379a18dcb8797a2b'),
    ('correct_affiliate_payout(uuid,integer,numeric,uuid,date,text,text,text,uuid)', 'e69c904cd0d5f9b806dc2be97870c0ab'),
    ('referrer_list()', 'c2596f5b32f26ae4c9f737b9e0320a09'),
    ('referrer_earnings(uuid)', 'b74826ed6ccfbc82cff8258b0678ec12'),
    ('refresh_legacy_therapy_statuses()', '6de4ab99525f70a282f2889b7694ac41'),
    ('sg_today()', '1c1289f18e24d8370e9a6364c9c06fca')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '410: public.% is missing or not the version read on 9 Oct 2026. Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'public.purchased_therapy_entitlements'::regclass
         and c.conname = 'purchased_therapy_entitlements_status_check') is distinct from c_unit_statuses then
    raise exception '410: the purchased therapy statuses are not the six read on 9 Oct 2026'; end if;
  if (select string_agg(e.enumlabel::text, ',' order by e.enumlabel::text) from pg_enum e
       where e.enumtypid = 'public.commission_status'::regtype) is distinct from c_commission_statuses then
    raise exception '410: the commission statuses are not the five read on 9 Oct 2026'; end if;
  -- The nightly job needs pg_cron, on GMT (production: GMT, 9 Oct 2026).
  if to_regprocedure('cron.schedule(text,text,text)') is null or to_regclass('cron.job') is null then
    raise exception '410: pg_cron is not installed (cron.schedule and cron.job are missing)'; end if;
  v_tz := coalesce(current_setting('cron.timezone', true), 'GMT');
  if v_tz not in ('GMT', 'UTC', 'Etc/UTC', 'Etc/GMT') then
    raise exception '410: pg_cron runs on % time, so % would not be 00:05 in Singapore', v_tz, c_job_schedule; end if;
  -- No other function takes these names (the API picks an overload by name).
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('affiliate_referrer_balances', 'purchased_therapy_status_on', 'run_therapy_status_refresh',
                                'affiliate_payout_overview', 'affiliate_payout_save', 'reconcile_invoice_commissions',
                                'affiliate_admin_directory', 'affiliate_portal_earnings', 'affiliate_portal_purchases',
                                'therapy_unit_consumed', 'refund_purchased_therapy', 'reschedule_purchased_therapy',
                                'claim_purchased_therapy', 'activate_purchased_therapy',
                                'refresh_purchased_therapy_statuses', 'cancel_invoice_recorded', 'correct_invoice')
              and p.oid::regprocedure::text not in (
                'affiliate_referrer_balances()', 'purchased_therapy_status_on(text,date,date,date,date)',
                'run_therapy_status_refresh()', 'affiliate_payout_overview()',
                'affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)',
                'reconcile_invoice_commissions(uuid,text)', 'affiliate_admin_directory()',
                'affiliate_portal_earnings()', 'affiliate_portal_purchases()', 'therapy_unit_consumed(uuid)',
                'refund_purchased_therapy(uuid,text)', 'reschedule_purchased_therapy(uuid,date,text)',
                'claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)',
                'activate_purchased_therapy(uuid,date,text,text,text,boolean)',
                'refresh_purchased_therapy_statuses()', 'cancel_invoice_recorded(uuid,text,uuid)',
                'correct_invoice(uuid,jsonb,jsonb,text,uuid)')) then
    raise exception '410: another overload of a function this changes exists'; end if;
  -- The grants of the functions changed, to compare after.
  select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
    into v_acl
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.oid::regprocedure::text in (
       'affiliate_payout_overview()', 'affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)',
       'reconcile_invoice_commissions(uuid,text)', 'affiliate_admin_directory()', 'affiliate_portal_earnings()',
       'affiliate_portal_purchases()', 'therapy_unit_consumed(uuid)', 'refund_purchased_therapy(uuid,text)',
       'reschedule_purchased_therapy(uuid,date,text)',
       'claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)',
       'activate_purchased_therapy(uuid,date,text,text,text,boolean)', 'refresh_purchased_therapy_statuses()',
       'cancel_invoice_recorded(uuid,text,uuid)', 'correct_invoice(uuid,jsonb,jsonb,text,uuid)');

  -- ── Install: the helpers first, then what reads them ─────────────────────
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
    if v_fns[i] = any(c_new) then
      v_changed := v_changed || v_fns[i];
      execute format('revoke all on function public.%s from public, anon, authenticated', v_fns[i]);
      execute format('grant execute on function public.%s to service_role', v_fns[i]);
    end if;
  end loop;

  -- ── The nightly job, written only when it is not already this one ────────
  if not exists (select 1 from cron.job j
                  where j.jobname = c_job and j.schedule = c_job_schedule and j.command = c_job_command
                    and j.active and j.database = current_database()) then
    perform cron.schedule(c_job, c_job_schedule, c_job_command);
  end if;
  if (select count(*) from cron.job j where j.jobname = c_job) <> 1
     or not exists (select 1 from cron.job j
                     where j.jobname = c_job and j.schedule = c_job_schedule and j.command = c_job_command
                       and j.active and j.database = current_database()) then
    raise exception '410: the cron job % is not there exactly once, active, as "%" running "%"',
      c_job, c_job_schedule, c_job_command; end if;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  for r in select * from (values
    ('affiliate_referrer_balances()', c_refbal_after),
    ('purchased_therapy_status_on(text,date,date,date,date)', c_status_on_after),
    ('run_therapy_status_refresh()', c_run_after),
    ('affiliate_payout_overview()', c_overview_after),
    ('affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)', c_save_after),
    ('reconcile_invoice_commissions(uuid,text)', c_reconcile_after),
    ('affiliate_admin_directory()', c_directory_after),
    ('affiliate_portal_earnings()', c_earnings_after),
    ('affiliate_portal_purchases()', c_purchases_after),
    ('therapy_unit_consumed(uuid)', c_consumed_after),
    ('refund_purchased_therapy(uuid,text)', c_refund_after),
    ('reschedule_purchased_therapy(uuid,date,text)', c_resched_after),
    ('claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)', c_claim_after),
    ('activate_purchased_therapy(uuid,date,text,text,text,boolean)', c_activate_after),
    ('refresh_purchased_therapy_statuses()', c_refresh_after),
    ('cancel_invoice_recorded(uuid,text,uuid)', c_cancel_after),
    ('correct_invoice(uuid,jsonb,jsonb,text,uuid)', c_correct_after)) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '410: installed with md5s other than the tested ones: %', v_bad; end if;
  -- The grants they had: every changed function's exactly as before.
  if (select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
        from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.oid::regprocedure::text in (
           'affiliate_payout_overview()', 'affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)',
           'reconcile_invoice_commissions(uuid,text)', 'affiliate_admin_directory()', 'affiliate_portal_earnings()',
           'affiliate_portal_purchases()', 'therapy_unit_consumed(uuid)', 'refund_purchased_therapy(uuid,text)',
           'reschedule_purchased_therapy(uuid,date,text)',
           'claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)',
           'activate_purchased_therapy(uuid,date,text,text,text,boolean)', 'refresh_purchased_therapy_statuses()',
           'cancel_invoice_recorded(uuid,text,uuid)', 'correct_invoice(uuid,jsonb,jsonb,text,uuid)'))
     is distinct from v_acl then
    raise exception '410: the grants of the changed functions changed'; end if;
  -- The new functions are the service role's alone (339).
  foreach v in array c_new loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute')
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                   where p.oid = to_regprocedure('public.' || v) and a.grantee = 0) then
      raise exception '410: public.% is not the service role''s alone', v; end if;
  end loop;
  if cardinality(v_changed) > 0 then
    raise notice '410: new functions installed: %', array_to_string(v_changed, ', '); end if;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
