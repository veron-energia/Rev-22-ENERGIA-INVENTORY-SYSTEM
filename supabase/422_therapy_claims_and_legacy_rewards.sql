-- 422_therapy_claims_and_legacy_rewards.sql
--
-- WHAT WAS WRONG (the audit of 9 Oct 2026, section 7: THERAPY-4, -5, -7, -8,
-- -9, -12, -15, -19, -20, -M2, and the therapy part of X-9)
--
--   Legacy claims (THERAPY-4). claim_legacy_therapy added up every voucher
--   quantity, negatives too, but issued only the positive ones, so 15 and -5
--   passed an "exactly 10" check and issued 15. It also took any unclaimed
--   voucher reward (credit-package and bundle rewards too) without reading
--   what had already been handed over or the vouchers it was sold with, so it
--   could issue a whole allowance again. On 9 Oct 2026 that was 11 rewards
--   and 120 vouchers on production (LEG-0000071, LEG-0000120 to 124 and
--   LEG-0000127 to 131), open to any active staff login calling the API. The
--   page sends these rewards to the Vouchers window, so no screen did it.
--
--   Discount vouchers as rewards (THERAPY-7). The reward checks took any
--   active voucher marked as a reward, and every voucher is marked so by
--   default, discount vouchers too. On 9 Oct 2026 the reward list offered 14
--   vouchers, 5 of them discounts (one fixed, two birthday, two staff). None
--   had been given as a reward, and every reward list set up holds only
--   free-session vouchers.
--
--   No voucher list (THERAPY-8). A voucher reward with no record of the
--   vouchers it was sold with showed none to choose, while the panel said any
--   reward voucher could be chosen and the claim would take any. Legacy and
--   affiliate qualification rewards never saved a list, and a reward with no
--   sale and no list could be handed over by any staff member of its store.
--
--   Cancel package (THERAPY-9). refund_purchased_therapy, the page's "Cancel
--   package (no money back)", moves no money, yet it reversed the earned
--   commission of the whole invoice line, products included, while the
--   invoice stayed paid. It also never checked the package's store, so a
--   Manager could close a package of a store they do not work at. (On 10
--   Oct 2026 both active Managers work at both active stores.)
--
--   Refunded sales (THERAPY-20). Claiming, starting, choosing and switching a
--   purchased package, and handing over a reward's vouchers, never looked at
--   the sale. UTP-0000006 (INV-2026-0160) and UTP-0000012 (INV-2026-0304)
--   were refunded and could still be started with Claim.
--
--   Overlaps (THERAPY-M2). A Legacy claim of unlimited therapy could start on
--   top of a period the customer already had. A purchase asks first.
--
--   Days left (THERAPY-15). The Purchased tab left today out of the days
--   left, and counted from today for a unit not started yet, so it showed one
--   day fewer than the customer's holdings (180 against 181 for UTP-0000011).
--
--   The page (THERAPY-5, -12, -19). The Therapy page read whole tables and
--   counted claimed vouchers from claim documents only, so 5 Legacy rewards
--   handed over in full before claim documents existed showed "10 of 10
--   left". Staff of every store could read every purchased package.
--
--   X-9. activate_therapy_beneficiary and can_change_therapy_dates looked at
--   a member of staff's first store only. Only the service role may call
--   them, so nothing changed for anyone yet.
--
-- THE RULES
--
--   1. A voucher reward is handed over in the Vouchers window, a few at a
--      time, up to what is left, from the vouchers it was sold with. Any
--      staff member of the reward's store may hand them over (the Owner, 9 Oct
--      2026, Q16 A), except as rule 10 says; the server stops more going out
--      than the reward allows.
--   2. Every voucher quantity is a whole number of at least 1.
--   3. Only free-session (normal) vouchers are rewards. A discount voucher is
--      never one, whatever its reward switch says.
--   4. A reward with no record of its vouchers offers the active normal
--      reward vouchers, and the panel says to check them against the sale.
--   5. Nothing is claimed, started, chosen or switched on a purchased
--      package, and no reward voucher is handed over, once the sale was
--      refunded, cancelled or deleted. An Owner or Manager closes such a
--      package with Cancel package on the Therapy page.
--   6. A Legacy claim of unlimited therapy that overlaps a running or
--      scheduled period asks first, as a purchase does, and suggests the day
--      after that period ends.
--   7. Days left count today and the expiry day. A unit not started yet
--      counts from its start.
--   8. Active staff read the purchased packages of the stores they work at
--      (Owners and Admins: every store). A pending invitee or a deleted
--      profile reads none, as 407 has it.
--   9. The lists never give or search a deleted customer's name or phone,
--      as the read rule on customers hides them. The row still shows, as
--      "Deleted customer". purchased_therapy_units never gives the name
--      either.
--  10. A voucher reward that records no sale and no voucher list waits for
--      an Owner or Manager to hand it over (the Owner, 9 Oct 2026). Staff
--      see it, and the Vouchers window says why.
--  11. A new Legacy or affiliate qualification voucher reward saves its
--      voucher list the day it is earned (the Owner, 9 Oct 2026). The rules
--      name no vouchers of their own, so the list is the reward vouchers on
--      offer that day: active free-session vouchers marked as rewards, the
--      ones a Legacy claim offers. With none on offer, no list is saved and
--      rule 10 applies. An unlimited reward saves no list.
--      WAITING FOR THE OWNER: this reading of "the rule's voucher list" is
--      not confirmed yet. See DEPLOY ORDER, step 0.
--  12. Cancel package moves no money, so it leaves commission alone.
--      Commission follows the money, and money goes back only through the
--      invoice's Refund / Cancel (the Owner, 9 Oct 2026).
--
-- WHAT THIS DOES
--
--   * therapy_invoice_closed_reason(uuid) (new; internal, the service role's
--     alone, 339): rule 5's one place. 'Invoice ... was refunded' (or
--     cancelled, or deleted), or null.
--   * claim_legacy_therapy gets a seventh argument, p_allow_overlap (default
--     false), and the six-argument one is dropped in the same step, as 386,
--     388 and 390 did; calls that leave it out reach the new one. It refuses
--     a voucher reward (rule 1), checks every quantity (rule 2) and that
--     nothing was handed over or withdrawn on an entitlement taken as
--     vouchers by its rule, takes normal vouchers only (rule 3), and answers
--     an overlap with requires_confirmation and the suggested start, writing
--     nothing (rule 6). It still checks active staff and the store first.
--   * claim_entitlement_vouchers: rule 5 on the reward's sale, rule 10,
--     normal vouchers only, and a quantity read as text so 2.5 is refused
--     plainly.
--   * legacy_reward_voucher_options: normal vouchers only (also the premium
--     bundle voucher picker on Invoices).
--   * entitlement_voucher_state: rule 4, rule 3 in still_offered, and two
--     new keys: blocked_reason (rule 5) and owner_or_manager_only (rule 10).
--     Every key it sent is still sent.
--   * recompute_legacy_qualification, recompute_affiliate_legacy_qualification:
--     rule 11 on the rewards they create. Nothing else changes in them.
--   * refund_purchased_therapy (the page's Cancel package): rule 12, so it no
--     longer reverses commission; 406's require_active_staff() as its first
--     statement; and it now checks the package's store
--     (user_has_store_access), as claim and activate do, so a Manager closes
--     only the packages of the stores they work at. It is still Owners' and
--     Managers' alone, with a reason and an audit row, and still closes the
--     package as refunded.
--   * claim_purchased_therapy, activate_purchased_therapy,
--     choose_therapy_benefit, switch_therapy_benefit: rule 5, and 406's
--     require_active_staff() as their first statement (they relied on the
--     store check alone).
--   * purchased_therapy_units: rule 7 for days_remaining, and rule 9 for
--     customer_name (null for a deleted customer).
--   * activate_legacy_therapy(uuid) is dropped, as 386, 388 and 390 dropped
--     leftovers. It is an old wrapper from 53 and 72 that only calls the
--     claim and returns nothing. Nothing calls it: no function, cron job,
--     page, edge function or script (checked on 10 Oct 2026). With the
--     overlap question it would come back without claiming and without
--     saying so. Only the service role could call it.
--   * therapy_list_page(text,text,text,integer,integer) (new; staff, 406's
--     check first): one page of the Purchased or Legacy list, searched and
--     filtered by status on the server, with the claimed and remaining
--     vouchers, days left, the sale's state, the next free start date and,
--     on the Legacy list, owner_or_manager_only (rule 10). Store-scoped
--     (rule 8). The total counts every matching row, also for a page past
--     the end. A deleted customer's name and phone are left out and not
--     searched (rule 9).
--   * activate_therapy_beneficiary, can_change_therapy_dates: any store the
--     member of staff works at (user_has_store_access), not the first one.
--   * Policy "read pte" on purchased_therapy_entitlements: rule 8
--     (current_user_role() is not null, as before, and
--     user_has_store_access(store_id)); it was every active staff login.
--     current_user_role() stays because user_has_store_access does not yet
--     check for a deleted profile or an accepted invitation.
--
-- NOT CHANGED
--
--   * No row. The repairs are scripts, run once at deploy:
--     scripts/therapy/repair-invoice-0174-test.sql (Q14 A) and
--     scripts/therapy/repair-discount-vouchers-not-rewards.sql (the Owner,
--     9 Oct 2026: untick "can be given as a reward" on the 5 discount
--     vouchers). The units on refunded sales (UTP-0000002, -0006, -0012) are
--     417's repair (Q3 A). Rewards earned before this keep no list (rule 11
--     is for new ones).
--   * A Legacy unlimited reward that a customer takes as vouchers when it is
--     claimed (its rule allows it): any staff member of its store, as before.
--   * Recording each therapy session or reward voucher used at the counter:
--     later (the Owner, 9 Oct 2026). A Dashboard alert for refunded or
--     cancelled sales that still hold credit or rewards is the Dashboard
--     batch's (B13).
--   * The Vouchers page's reward switch (423), the credit-package rules, the
--     invoice's refund and cancel, legacy_reward_options and its diagnostic,
--     the Legacy and purchased refreshes, therapy_customer_summary and
--     therapy_customer_detail (they already count today).
--   * user_has_store_access, as it is: B17's migration (430) makes it check
--     for a deleted profile and an accepted invitation too, which only
--     narrows what this lets through. It is read, not guarded.
--   * Grants of every changed function; the new claim_legacy_therapy gets
--     the old one's (authenticated and service_role). The two recompute
--     functions stay the service role's alone.
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. Every
--   guard and anchor is checked and every new text built before anything is
--   installed. Each changed function must be production's version of 9 Oct
--   2026 (BEFORE) or already this one's (AFTER, left alone, so a re-run
--   changes nothing). The new ones must be missing or already this version,
--   and no other function may take any of these names. The functions relied
--   on must be the versions read on 9 Oct 2026. Every anchor must match once.
--   Each built text must have its AFTER md5 before it is installed. CREATE OR
--   REPLACE keeps owner and grants. The six-argument claim_legacy_therapy is
--   dropped only after the seven-argument one is in, with the same grants.
--   activate_legacy_therapy(uuid) must be the version read on 10 Oct 2026,
--   or already gone; it is dropped RESTRICT, so the drop is refused if
--   anything has come to depend on it.
--   The policy must be the one read on 9 Oct 2026 or already this one.
--   Afterwards the md5s, the grants, the policy and the names are checked,
--   and then, inside a block that is always undone, a made-up Owner, store,
--   customer, deleted customer, vouchers, rewards, a refunded sale, purchased
--   units, a member of staff and a pending invitee (@sig.invalid,
--   '422 check'): rules 1 to 10 hold, a page past the end of a list still
--   gives its total, and, switching role, the anon key and a signed-in login
--   with no profile are refused by the page's functions. Rules 11 and 12,
--   and Cancel package's store check, are the suite's (below); their texts
--   are fixed by their AFTER md5s. Nothing is printed and no row remains.
--
-- BEFORE (production, 9 Oct 2026; md5 of pg_get_functiondef, search_path public):
--   claim_legacy_therapy(uuid,date,uuid,jsonb,text,text)              3957f56f3ea9dc8df6789371a20add66 (dropped)
--   activate_legacy_therapy(uuid) (read 10 Oct 2026)                  e9d9c71e864fc6d22dfb8e8b335b173f (dropped)
--   claim_entitlement_vouchers(uuid,jsonb,text)                       e6958c6052d3dd8d7ea3a175d614b5da
--   legacy_reward_voucher_options(uuid)                               8728d0ba59ddf0a9e7161ed3483c4618
--   entitlement_voucher_state(uuid)                                   f8b6a3a4521e025ed2cd1151cab53ae8
--   claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)
--                                                                     44abcd5d179fa7d24438c4c44cc0be8f
--   activate_purchased_therapy(uuid,date,text,text,text,boolean)      0c4f319294981cd5efef616781d54a2b
--   choose_therapy_benefit(uuid,text,uuid,text)                       676a8a158482c4d68706308574efe92f
--   switch_therapy_benefit(uuid,text,text,uuid)                       0d8df6b39e9f58d6ac249ea180162054
--   activate_therapy_beneficiary(uuid,date,date)                      e71626b41d083a4c7014b1dc55016055
--   can_change_therapy_dates(uuid)                                    dcd3b810e51323b27e348d9c6aadb22a
--   purchased_therapy_units(uuid,uuid,boolean)                        265662fe473dd6d6901843c9ae06f63c
--   refund_purchased_therapy(uuid,text)                               82bfeaa5f54a4ff3b7495bca6e9ed7bf
--   recompute_legacy_qualification(uuid,uuid,date)                    490b1420f18e07daff553c9fa990cfc6
--   recompute_affiliate_legacy_qualification(uuid,date)               754e10e7093f1cb2d4abee8254453d9e
--   therapy_invoice_closed_reason(uuid)                               (missing)
--   therapy_list_page(text,text,text,integer,integer)                 (missing)
--   policy "read pte": (current_user_role() IS NOT NULL)
--   (relied on, not changed)
--   require_active_staff(text[])                                      877b3aa74cea559881979bb161c450e2
--   therapy_next_available_start(uuid,date)                           fb4856596855d1718f446c30c5e36246
--   entitlement_claimed_qty(uuid)                                     89b08265d5303e890569e953d83d2440
--   purchased_therapy_status_on(text,date,date,date,date)             991ec75f0349f61ef1a2f3682fb142b1
--   sg_today()                                                        1c1289f18e24d8370e9a6364c9c06fca
--   public function fingerprint (after 413)                           675ac22c631079b58f06813d0d463fa3
--   public function fingerprint (after 414, 421 and 428; not a guard) 897ad364eff917861989315bb2fa0e43
--   public function fingerprint (and 415, 10 Oct 2026; not a guard)   566e76f702c89c9846968e6fdd89cc45
--   Every BEFORE md5 above was read again on production on 9 Oct 2026,
--   after 414, 421 and 428 went live, and again on 10 Oct 2026, after 415:
--   all unchanged, the two new functions missing, "read pte" as above.
--   activate_legacy_therapy(uuid) on 10 Oct 2026: grants postgres and
--   service_role only; nothing depends on it, no other function or cron job
--   names it, and it is the only function of that name.
-- AFTER (for later guards):
--   therapy_invoice_closed_reason(uuid)                               2286c0c92003643d56b76d8d8827315c
--   therapy_list_page(text,text,text,integer,integer)                 fa78a96f7fbb74d770b54a8b700ad4b4
--   claim_legacy_therapy(uuid,date,uuid,jsonb,text,text,boolean)      164530713b7a52f9b80642bbd0e1ed00
--   claim_entitlement_vouchers(uuid,jsonb,text)                       5a2e078df74a2763b6975bb939847b7a
--   legacy_reward_voucher_options(uuid)                               38a22dd0f89179f5412e575fa2cbd0a8
--   entitlement_voucher_state(uuid)                                   712eaace0a70bcbed47186beb1cd6d7a
--   claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)
--                                                                     c833e4cbfd01b3de4d825b5f6080e73e
--   activate_purchased_therapy(uuid,date,text,text,text,boolean)      1047cc5c2ed136ae4fd22d0b471c4199
--   choose_therapy_benefit(uuid,text,uuid,text)                       bf419bd6487f392a6ab2b5b302cf48f5
--   switch_therapy_benefit(uuid,text,text,uuid)                       aac8021b58fd5d60c7519823904a764c
--   activate_therapy_beneficiary(uuid,date,date)                      9ac0bf428a1e3495e3ea39452feab994
--   can_change_therapy_dates(uuid)                                    716e85614c683208987b660d0c5d35a0
--   purchased_therapy_units(uuid,uuid,boolean)                        9da46e18c367c76b5c3c2c2fe32a332d
--   refund_purchased_therapy(uuid,text)                               c51524d7dc76535111fe4c72e1cbb5ab
--   activate_legacy_therapy(uuid)                                     (absent)
--   recompute_legacy_qualification(uuid,uuid,date)                    588fdaff42b49df16a051af839a2ff38
--   recompute_affiliate_legacy_qualification(uuid,date)               9b94f6008d92d15a61a3286672fdac00
--   policy "read pte": ((current_user_role() IS NOT NULL) AND user_has_store_access(store_id))
--
-- DEPLOY ORDER:
--   0. Before this migration is applied: the Owner confirms rule 11's
--      reading. The rules name no vouchers, so a new reward saves the reward
--      vouchers on offer the day it is earned (on 10 Oct 2026, 9 active
--      free-session vouchers). A backfill of a past day
--      (backfill_legacy_qualification) saves today's list, not that day's.
--      If the Owner wants each rule to name its own vouchers, or has not
--      answered when this is applied, take rule 11 out first: remove the
--      c_lq1 to c_lq4 and c_aq1 to c_aq4 anchors, the two recompute entries
--      in the patch list and in the after-check list, their names in
--      c_patched, and their BEFORE and AFTER lines here; and drop the rule-11
--      savepoint block (and section 1's rule-11 checks) in
--      scripts/therapy/tests/claims-and-legacy-rewards.sql. New rewards then
--      keep no list and wait for an Owner or Manager (rule 10), the safe
--      default until the answer comes.
--   1. This migration. The pages live now keep working against it: they read
--      the tables the policy still lets them read, their calls keep their
--      argument names, and a Legacy claim that overlaps comes back unclaimed
--      with requires_confirmation, which the live page shows as an empty
--      "Claimed" window (nothing was written; the new page asks instead).
--   2. scripts/therapy/repair-invoice-0174-test.sql, STEP 1 (the dry run) and
--      then STEP 2 (Q14 A, approved by the Owner on 9 Oct 2026). It needs
--      nothing from this migration, so it may also run before it. Run it
--      before step 3: LEG-0000071, the 20-voucher reward of the refunded
--      test sale INV-2026-0174, records no sale and no voucher list, so rule
--      5 cannot see the refund. Rule 10 keeps staff from handing it over,
--      but an Owner or Manager still could. STEP 2 cancels it.
--      OWNER TO CONFIRM: INV-2026-0173 and INV-2026-0175 were deleted on 3
--      Sep 2026 (unpaid, no payment). Q14 A asked for them to be cancelled.
--      STEP 2 leaves them deleted and only checks they are still deleted and
--      unpaid. Is that enough, or should STEP 2 also cancel them?
--   3. The pages (pushing to main deploys them). Against a database without
--      this migration they fail to load their lists (therapy_list_page is
--      missing), so step 1 goes first.
--   4. At deploy, any time after step 1 (the Owner, 9 Oct 2026: untick
--      "can be given as a reward" on BD-10, BD-AD, SAVE72, SD-10 and SD-50):
--      scripts/therapy/repair-discount-vouchers-not-rewards.sql, STEP 1 (the
--      dry run) and then STEP 2.
--
-- Test: scripts/therapy/tests/claims-and-legacy-rewards.sql (shows each defect
-- first, rules 10 to 12 included, then applies this twice inside its own
-- rolled-back transaction: the second run changes nothing),
-- scripts/voucher-claims/tests/legacy-claim-quantities.sql (needs this
-- applied), the voucher-claims,
-- therapy-choices and invoice-actions suites, scripts/permissions/tests/
-- function-grants.sql and staff-only-functions.sql; the pages:
-- scripts/therapy/tests/therapy-page-lists.test.mjs and
-- therapy-page-status.test.mjs. scripts/therapy/tests/status-refresh.sql
-- applies 410 itself; on a database that has this migration it skips that
-- step (410's guards would refuse the functions this changes) and checks the
-- rest. scripts/therapy/tests/database.mjs runs 220-226 only; its Legacy
-- claims no longer overlap, and it checks the overlap question when this is
-- applied.

set lock_timeout = '5s';

do $mig$
declare
  -- ── New: why a sale keeps no unused benefit (rule 5) ─────────────────────
  c_closed_def constant text := $def$CREATE OR REPLACE FUNCTION public.therapy_invoice_closed_reason(p_invoice_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 422: why nothing may be claimed, chosen or started on a benefit that came
  -- with this invoice, or null when it may (THERAPY-20). A sale that was
  -- refunded, cancelled or deleted keeps no unused benefit; an Owner or
  -- Manager closes it. The one place this rule is written.
  select case
           when i.deleted_at is not null then 'Invoice ' || i.invoice_no || ' was deleted'
           when i.status::text = 'refunded' then 'Invoice ' || i.invoice_no || ' was refunded'
           when i.status::text = 'cancelled' then 'Invoice ' || i.invoice_no || ' was cancelled'
         end
    from public.invoices i
   where i.id = p_invoice_id
$function$
$def$;
  -- ── New: one page of the Therapy page's Purchased or Legacy list ─────────
  c_list_def constant text := $def$CREATE OR REPLACE FUNCTION public.therapy_list_page(p_tab text, p_search text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_today date := public.sg_today();
  v_q text := nullif(lower(btrim(coalesce(p_search, ''))), '');
  v_status text := nullif(btrim(coalesce(p_status, '')), '');
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_total bigint := 0;
  v_rows jsonb := '[]'::jsonb;
begin
  perform public.require_active_staff();  -- 406: active staff only
  -- 422: one page of the Therapy page's Purchased or Legacy list (THERAPY-19).
  -- The figures are worked out here, not on the page: what was claimed and
  -- what is left (THERAPY-5), the days left (THERAPY-15), whether the sale was
  -- refunded, cancelled or deleted (THERAPY-20) and the next free start date
  -- (THERAPY-M2). Only the stores the caller works at (Owners and Admins:
  -- every store), so a row is never offered with a Claim its store refuses
  -- (THERAPY-12).
  --   p_tab     'purchased' or 'legacy'.
  --   p_search  part of the customer's name or phone, the number, the
  --             package or the invoice number.
  --   p_status  Purchased: all (the default), open, pending_activation,
  --             scheduled, active, expired, closed (cancelled or refunded).
  --             Legacy: open (the default: all but cancelled), all,
  --             pending_activation, scheduled, active, expired, cancelled.
  --             A status is read by its dates, as the checks read it.
  --   p_limit   at most 200 rows (50 by default); p_offset from 0.
  -- A deleted customer's name and phone are neither given nor searched, as
  -- the read rule on customers hides them; the row still shows (null name).
  if p_tab = 'purchased' then
    if v_status is not null
       and v_status not in ('all', 'open', 'pending_activation', 'scheduled', 'active', 'expired', 'closed') then
      raise exception 'Unknown status filter: %', v_status; end if;
    with base as (
      select e.*, case when c.deleted_at is null then c.full_name end as customer_name,
             case when c.deleted_at is null then c.phone end as customer_phone,
             i.invoice_no, i.status::text as invoice_status,
             public.therapy_invoice_closed_reason(e.invoice_id) as invoice_closed_reason,
             public.purchased_therapy_status_on(e.status, e.activation_date, e.expiry_date,
                                                e.activation_deadline, v_today) as status_now,
             ve.voucher_qty as ve_qty, ve.revoked_qty as ve_revoked
        from public.purchased_therapy_entitlements e
        join public.customers c on c.id = e.customer_id
        left join public.invoices i on i.id = e.invoice_id
        left join public.therapy_entitlements ve on ve.id = e.voucher_entitlement_id
       where public.user_has_store_access(e.store_id)
         and (v_q is null
              or (c.deleted_at is null and strpos(lower(coalesce(c.full_name, '')), v_q) > 0)
              or (c.deleted_at is null and strpos(lower(coalesce(c.phone, '')), v_q) > 0)
              or strpos(lower(e.entitlement_no), v_q) > 0
              or strpos(lower(e.package_name), v_q) > 0
              or strpos(lower(coalesce(i.invoice_no, '')), v_q) > 0)
    ), filtered as (
      select b.*
        from base b
       where coalesce(v_status, 'all') = 'all'
          or (v_status = 'open' and b.status_now in ('pending_activation', 'scheduled', 'active'))
          or (v_status = 'closed' and b.status_now in ('cancelled', 'refunded'))
          or b.status_now = v_status
    ), page as (
      select f.*
        from filtered f
       order by f.created_at desc, coalesce(f.unit_index, 1), f.id
       limit v_limit offset v_offset
    )
    -- The total counts every matching row, so a page past the end still
    -- says how many there are.
    select (select count(*) from filtered),
           coalesce(jsonb_agg(jsonb_build_object(
             'id', x.id, 'entitlement_no', x.entitlement_no,
             'customer_id', x.customer_id, 'customer_name', x.customer_name,
             'customer_phone', x.customer_phone, 'store_id', x.store_id,
             'package_id', x.package_id, 'package_name', x.package_name,
             'invoice_id', x.invoice_id, 'invoice_item_id', x.invoice_item_id,
             'invoice_no', x.invoice_no, 'invoice_status', x.invoice_status,
             'invoice_closed_reason', x.invoice_closed_reason,
             'duration_months', x.duration_months, 'price_snapshot', x.price_snapshot,
             'purchase_date', x.purchase_date, 'activation_deadline', x.activation_deadline,
             'scheduled_date', x.scheduled_date, 'activation_date', x.activation_date,
             'expiry_date', x.expiry_date, 'status', x.status, 'status_now', x.status_now,
             'eligible_service_ids', to_jsonb(x.eligible_service_ids),
             'holiday_country', x.holiday_country, 'holiday_region', x.holiday_region,
             'unit_index', coalesce(x.unit_index, 1), 'unit_count', coalesce(x.unit_count, 1),
             'offers_choice', coalesce(array_length(x.offered_choices, 1), 0) > 1,
             'benefit_choice', x.benefit_choice, 'choice_pending', x.benefit_choice is null,
             'choice_deadline', x.choice_deadline,
             'choice_deadline_passed', x.choice_deadline is not null and v_today > x.choice_deadline,
             -- Calendar days, today and the expiry day included; a scheduled
             -- unit counts from its start (THERAPY-15).
             'days_remaining', case when x.expiry_date is not null and x.status_now in ('active', 'scheduled')
                                    then greatest((x.expiry_date - greatest(v_today, coalesce(x.activation_date, v_today))) + 1, 0) end,
             'voucher_entitlement_id', x.voucher_entitlement_id,
             'voucher_entitled', case when x.voucher_entitlement_id is not null then coalesce(x.ve_qty, 0) end,
             'voucher_claimed', case when x.voucher_entitlement_id is not null
                                     then public.entitlement_claimed_qty(x.voucher_entitlement_id) end,
             'voucher_remaining', case when x.voucher_entitlement_id is not null
                                       then greatest(coalesce(x.ve_qty, 0)
                                                     - public.entitlement_claimed_qty(x.voucher_entitlement_id)
                                                     - coalesce(x.ve_revoked, 0), 0) end,
             'created_at', x.created_at)
           order by x.created_at desc, coalesce(x.unit_index, 1), x.id), '[]'::jsonb)
      into v_total, v_rows
      from page x;
  elsif p_tab = 'legacy' then
    if v_status is not null
       and v_status not in ('all', 'open', 'pending_activation', 'scheduled', 'active', 'expired', 'cancelled') then
      raise exception 'Unknown status filter: %', v_status; end if;
    with base as (
      select te.*, case when c.deleted_at is null then c.full_name end as customer_name,
             case when c.deleted_at is null then c.phone end as customer_phone,
             si.invoice_no as source_invoice_no,
             public.therapy_invoice_closed_reason(te.claim_source_invoice_id) as blocked_reason,
             -- By its dates, as the nightly Legacy refresh stores it.
             case when te.status in ('active', 'scheduled') and te.expiry_date is not null
                       and te.expiry_date < v_today then 'expired'
                  when te.status = 'scheduled' and te.activation_date is not null
                       and te.activation_date <= v_today then 'active'
                  else te.status end as status_now
        from public.therapy_entitlements te
        join public.customers c on c.id = te.customer_id
        left join public.invoices si on si.id = te.claim_source_invoice_id
       where public.user_has_store_access(te.store_id)
         and (v_q is null
              or (c.deleted_at is null and strpos(lower(coalesce(c.full_name, '')), v_q) > 0)
              or (c.deleted_at is null and strpos(lower(coalesce(c.phone, '')), v_q) > 0)
              or strpos(lower(te.entitlement_no), v_q) > 0
              or strpos(lower(te.package_name), v_q) > 0
              or strpos(lower(coalesce(si.invoice_no, '')), v_q) > 0)
    ), filtered as (
      select b.*
        from base b
       where (coalesce(v_status, 'open') = 'open' and b.status_now <> 'cancelled')
          or v_status = 'all'
          or b.status_now = v_status
    ), page as (
      select f.*
        from filtered f
       order by f.created_at desc, f.id
       limit v_limit offset v_offset
    )
    select (select count(*) from filtered),
           coalesce(jsonb_agg(jsonb_build_object(
             'id', x.id, 'entitlement_no', x.entitlement_no,
             'customer_id', x.customer_id, 'customer_name', x.customer_name,
             'customer_phone', x.customer_phone, 'store_id', x.store_id,
             'earner_kind', x.earner_kind, 'package_name', x.package_name,
             'entitlement_kind', x.entitlement_kind, 'duration_months', x.duration_months,
             'qualified_value', x.qualified_value, 'voucher_qty', x.voucher_qty,
             -- What was handed over, as entitlement_claimed_qty counts it
             -- (claims and the vouchers issued before claims existed), and what
             -- is left; nothing is left on a cancelled one (THERAPY-5).
             'claimed_qty', public.entitlement_claimed_qty(x.id),
             'revoked_qty', coalesce(x.revoked_qty, 0),
             'remaining', case when x.status = 'cancelled' then 0
                               else greatest(coalesce(x.voucher_qty, 0) - public.entitlement_claimed_qty(x.id)
                                             - coalesce(x.revoked_qty, 0), 0) end,
             'activation_deadline', x.activation_deadline,
             'deadline_passed', x.activation_deadline is not null and v_today > x.activation_deadline,
             'activation_date', x.activation_date, 'expiry_date', x.expiry_date,
             'status', x.status, 'status_now', x.status_now,
             'claim_source_type', x.claim_source_type, 'claim_source_invoice_id', x.claim_source_invoice_id,
             'source_invoice_no', x.source_invoice_no, 'blocked_reason', x.blocked_reason,
             -- A voucher reward that records no sale and no voucher list: an
             -- Owner or Manager hands it over (the Owner, 9 Oct 2026).
             'owner_or_manager_only', coalesce(x.entitlement_kind, 'unlimited') = 'voucher'
                                      and x.claim_source_invoice_id is null and x.eligible_voucher_ids is null,
             'holiday_country', x.holiday_country, 'holiday_region', x.holiday_region,
             -- The day after the customer's running or scheduled unlimited
             -- therapy, or today: where a claim should start (THERAPY-M2).
             'next_free_start', case when x.status = 'pending_activation'
                                          and coalesce(x.entitlement_kind, 'unlimited') = 'unlimited'
                                     then (public.therapy_next_available_start(x.customer_id, v_today)
                                           ->> 'suggested_start')::date end,
             'days_remaining', case when coalesce(x.entitlement_kind, 'unlimited') = 'unlimited'
                                         and x.expiry_date is not null and x.status_now in ('active', 'scheduled')
                                    then greatest((x.expiry_date - greatest(v_today, coalesce(x.activation_date, v_today))) + 1, 0) end,
             'created_at', x.created_at)
           order by x.created_at desc, x.id), '[]'::jsonb)
      into v_total, v_rows
      from page x;
  else
    raise exception 'Unknown list: % (purchased or legacy)', coalesce(p_tab, 'none');
  end if;

  return jsonb_build_object('tab', p_tab, 'total', v_total, 'limit', v_limit, 'offset', v_offset,
                            'status', coalesce(v_status, case when p_tab = 'legacy' then 'open' else 'all' end),
                            'rows', v_rows);
end
$function$
$def$;

  -- ── Anchors and what replaces them, in the order they are applied ────────
  c_legacy1_a constant text := $q$p_holiday_region text DEFAULT NULL::text)
 RETURNS jsonb$q$;
  c_legacy1_r constant text := $q$p_holiday_region text DEFAULT NULL::text, p_allow_overlap boolean DEFAULT false)
 RETURNS jsonb$q$;
  c_legacy2_a constant text := $q$  v_recipient text; v_issued jsonb := '[]'::jsonb;
begin
$q$;
  c_legacy2_r constant text := $q$  v_recipient text; v_issued jsonb := '[]'::jsonb;
  v_next jsonb; v_overlaps boolean := false; v_q_text text;  -- 422
begin
$q$;
  c_legacy3_a constant text := $q$  if e.status <> 'pending_activation' then
    raise exception 'Only an unclaimed entitlement can be claimed (currently %)', e.status; end if;
$q$;
  c_legacy3_r constant text := $q$  if e.status <> 'pending_activation' then
    raise exception 'Only an unclaimed entitlement can be claimed (currently %)', e.status; end if;
  -- 422: a voucher reward is handed over in the Vouchers window
  -- (claim_entitlement_vouchers), which counts what was already handed over
  -- and keeps to the vouchers it was sold with. Claimed here, it issued its
  -- whole allowance again (THERAPY-4).
  if coalesce(e.entitlement_kind, 'unlimited') = 'voucher' or e.claim_source_type is not null then
    raise exception 'This is a voucher reward. Hand its vouchers over with Vouchers on the Legacy tab.';
  end if;
$q$;
  c_legacy4_a constant text := $q$  if v_kind = 'unlimited' then
    -- Closure extension applies to a Legacy reward exactly as it does to a
$q$;
  c_legacy4_r constant text := $q$  if v_kind = 'unlimited' then
    -- 422: a second unlimited period does not start on top of one the
    -- customer already has unless staff confirm it, as a purchase asks
    -- (THERAPY-M2). Nothing is written until then.
    v_next := public.therapy_next_available_start(e.customer_id, v_today);
    v_overlaps := (v_next->>'latest_existing_expiry') is not null
                  and v_act <= (v_next->>'latest_existing_expiry')::date;
    if v_overlaps and not coalesce(p_allow_overlap, false) then
      return jsonb_build_object('success', false, 'claimed', false, 'requires_confirmation', true,
        'reason', 'This customer already has unlimited therapy running on that date.',
        'suggested_start', (v_next->>'suggested_start')::date,
        'existing', v_next->'existing',
        'entitlement_no', e.entitlement_no);
    end if;
    -- Closure extension applies to a Legacy reward exactly as it does to a
$q$;
  c_legacy5_a constant text := $q$  else
    if p_voucher_selections is null or jsonb_array_length(p_voucher_selections) = 0 then
      raise exception 'Choose % voucher(s) to claim this reward', coalesce(v_qty,0); end if;
    for v_sel in select * from jsonb_array_elements(p_voucher_selections) loop
      v_sum := v_sum + coalesce((v_sel->>'quantity')::integer, 0);
    end loop;
$q$;
  c_legacy5_r constant text := $q$  else
    -- 422: only an unlimited entitlement gets here (a voucher one was
    -- refused above), taken as vouchers by its rule. Nothing may have been
    -- handed over or withdrawn on it already (THERAPY-4).
    if public.entitlement_claimed_qty(e.id) > 0 or coalesce(e.revoked_qty, 0) > 0 then
      raise exception 'Vouchers were already handed over or withdrawn on this entitlement, so it cannot be claimed as vouchers again.'; end if;
    if p_voucher_selections is null then
      raise exception 'Choose % voucher(s) to claim this reward', coalesce(v_qty,0); end if;
    if jsonb_typeof(p_voucher_selections) <> 'array' then
      raise exception 'Choose % voucher(s) to claim this reward', coalesce(v_qty,0); end if;
    if jsonb_array_length(p_voucher_selections) = 0 then
      raise exception 'Choose % voucher(s) to claim this reward', coalesce(v_qty,0); end if;
    for v_sel in select * from jsonb_array_elements(p_voucher_selections) loop
      -- 422: every line is a whole number of at least one. A negative line
      -- bought headroom: 15 and -5 counted as 10 and issued 15 (THERAPY-4).
      v_q_text := btrim(coalesce(v_sel->>'quantity', ''));
      if coalesce(substring(v_q_text from '^([0-9]{1,6})$')::integer, 0) < 1 then
        raise exception 'A voucher quantity must be a whole number of at least one; got %',
          coalesce(nullif(v_q_text, ''), 'nothing'); end if;
      v_sum := v_sum + v_q_text::integer;
    end loop;
$q$;
  c_legacy6_a constant text := $q$      if not exists (select 1 from public.vouchers v
                      where v.id = v_vid and v.is_active = true and v.deleted_at is null
                        and coalesce(v.reward_eligible,true)) then
$q$;
  c_legacy6_r constant text := $q$      -- 422: a free-session voucher only; a discount voucher is never a
      -- reward (THERAPY-7).
      if not exists (select 1 from public.vouchers v
                      where v.id = v_vid and v.is_active = true and v.deleted_at is null
                        and coalesce(v.reward_eligible,true) and v.voucher_kind = 'normal') then
$q$;
  c_legacy7_a constant text := $q$      v_q := coalesce((v_sel->>'quantity')::integer, 0);
      if v_q <= 0 then continue; end if;
$q$;
  c_legacy7_r constant text := $q$      v_q := btrim(v_sel->>'quantity')::integer;  -- 422: checked above
$q$;
  c_legacy8_a constant text := $q$                       'base_expiry', v_base_expiry, 'closure_days_added', v_added),
$q$;
  c_legacy8_r constant text := $q$                       'base_expiry', v_base_expiry, 'closure_days_added', v_added,
                       'overlap_confirmed', v_overlaps),
$q$;
  c_legacy9_a constant text := $q$  return jsonb_build_object('success', true, 'status', v_status, 'kind', v_kind,
$q$;
  c_legacy9_r constant text := $q$  return jsonb_build_object('success', true, 'claimed', true, 'overlapped', v_overlaps,
    'status', v_status, 'kind', v_kind,
$q$;
  c_vclaim1_a constant text := $q$  v_inv uuid; v_no text; v_claim uuid; v_issued jsonb := '[]'::jsonb;
begin
$q$;
  c_vclaim1_r constant text := $q$  v_inv uuid; v_no text; v_claim uuid; v_issued jsonb := '[]'::jsonb;
  v_closed text; v_q_text text;  -- 422
begin
$q$;
  c_vclaim2_a constant text := $q$  if v_remaining <= 0 then raise exception 'Nothing left to claim on this entitlement'; end if;
$q$;
  c_vclaim2_r constant text := $q$  if v_remaining <= 0 then raise exception 'Nothing left to claim on this entitlement'; end if;
  -- 422: nothing is handed over on a sale that was refunded, cancelled or
  -- deleted (THERAPY-20). Any staff member of the store may hand vouchers
  -- over (the Owner, 9 Oct 2026); the checks here stop more going out than
  -- the reward allows.
  v_closed := public.therapy_invoice_closed_reason(e.claim_source_invoice_id);
  if v_closed is not null then
    raise exception '%, so nothing can be claimed on this reward.', v_closed; end if;
  -- 422: a reward that records no sale and no voucher list waits for an
  -- Owner or Manager (the Owner, 9 Oct 2026). Nothing shows what it was
  -- given for, or which vouchers it may take.
  if e.claim_source_invoice_id is null and e.eligible_voucher_ids is null then
    begin
      perform public.require_active_staff('{owner,manager}');
    exception when insufficient_privilege then
      raise exception 'No sale and no voucher list is recorded for this reward, so an Owner or Manager hands it over.'
        using errcode = '42501';
    end;
  end if;
$q$;
  c_vclaim3_a constant text := $q$    v_q := coalesce((v_sel->>'quantity')::integer, 0);
    if v_q < 1 then
      raise exception 'A voucher quantity must be a whole number of at least one; got %', v_q;
    end if;
$q$;
  c_vclaim3_r constant text := $q$    -- 422: read as text, so 2.5 or "two" is refused with this message too.
    v_q_text := btrim(coalesce(v_sel->>'quantity', ''));
    if coalesce(substring(v_q_text from '^([0-9]{1,6})$')::integer, 0) < 1 then
      raise exception 'A voucher quantity must be a whole number of at least one; got %',
        coalesce(nullif(v_q_text, ''), 'nothing');
    end if;
    v_q := v_q_text::integer;
$q$;
  c_vclaim4_a constant text := $q$    v_q   := coalesce((v_sel->>'quantity')::integer,0);
$q$;
  c_vclaim4_r constant text := $q$    v_q   := btrim(v_sel->>'quantity')::integer;  -- 422: checked above
$q$;
  c_vclaim5_a constant text := $q$                    where v.id = v_vid and v.is_active and v.deleted_at is null
                      and coalesce(v.reward_eligible,true)) then
$q$;
  c_vclaim5_r constant text := $q$                    where v.id = v_vid and v.is_active and v.deleted_at is null
                      and coalesce(v.reward_eligible,true)
                      and v.voucher_kind = 'normal') then  -- 422: never a discount voucher (THERAPY-7)
$q$;
  c_voptions1_a constant text := $q$   where v.is_active = true and v.deleted_at is null and coalesce(v.reward_eligible,true)
$q$;
  c_voptions1_r constant text := $q$   where v.is_active = true and v.deleted_at is null and coalesce(v.reward_eligible,true)
     and v.voucher_kind = 'normal'  -- 422: a free-session voucher only (THERAPY-7)
$q$;
  c_vstate1_a constant text := $q$           'still_offered', v.is_active and v.deleted_at is null and coalesce(v.reward_eligible,true))
$q$;
  c_vstate1_r constant text := $q$           'still_offered', v.is_active and v.deleted_at is null and coalesce(v.reward_eligible,true)
                            and v.voucher_kind = 'normal')  -- 422 (THERAPY-7)
$q$;
  c_vstate2_a constant text := $q$   where v.id = any(coalesce(e.eligible_voucher_ids,'{}'::uuid[]));
$q$;
  c_vstate2_r constant text := $q$   where v.id = any(coalesce(e.eligible_voucher_ids,'{}'::uuid[]))
      -- 422: with no record of what it was sold with, the vouchers a claim
      -- accepts (THERAPY-8). snapshot_present stays false, so the panel still
      -- says to check them against the purchase.
      or (e.eligible_voucher_ids is null and v.is_active and v.deleted_at is null
          and coalesce(v.reward_eligible,true) and v.voucher_kind = 'normal');
$q$;
  c_vstate3_a constant text := $q$    'snapshot_present', e.eligible_voucher_ids is not null);
$q$;
  c_vstate3_r constant text := $q$    'snapshot_present', e.eligible_voucher_ids is not null,
    -- 422: why nothing can be claimed: the sale was refunded, cancelled or
    -- deleted (THERAPY-20); null when it can.
    'blocked_reason', public.therapy_invoice_closed_reason(e.claim_source_invoice_id),
    -- 422: no sale and no voucher list are recorded, so an Owner or Manager
    -- hands it over (the Owner, 9 Oct 2026).
    'owner_or_manager_only', e.claim_source_invoice_id is null and e.eligible_voucher_ids is null);
$q$;
  c_pclaim1_a constant text := $q$        v_now text;  -- 410: the unit's status by its dates
begin
$q$;
  c_pclaim1_r constant text := $q$        v_now text;  -- 410: the unit's status by its dates
        v_closed text;  -- 422
begin
  perform public.require_active_staff();  -- 422: active staff only (406)
$q$;
  c_pclaim2_a constant text := $q$  if e.status in ('cancelled','refunded') then
    raise exception 'This purchase was %; nothing can be claimed against it', e.status; end if;
$q$;
  c_pclaim2_r constant text := $q$  if e.status in ('cancelled','refunded') then
    raise exception 'This purchase was %; nothing can be claimed against it', e.status; end if;
  -- 422: nor on a package whose sale was refunded, cancelled or deleted
  -- (THERAPY-20). An Owner or Manager closes it with Cancel package.
  v_closed := public.therapy_invoice_closed_reason(e.invoice_id);
  if v_closed is not null then
    raise exception '%, so nothing can be claimed on this package.', v_closed; end if;
$q$;
  c_pactivate1_a constant text := $q$  v_now text;  -- 410: the unit's status by its dates
begin
$q$;
  c_pactivate1_r constant text := $q$  v_now text;  -- 410: the unit's status by its dates
  v_closed text;  -- 422
begin
  perform public.require_active_staff();  -- 422: active staff only (406)
$q$;
  c_pactivate2_a constant text := $q$  if not public.user_has_store_access(e.store_id) then raise exception 'No access to this store'; end if;
$q$;
  c_pactivate2_r constant text := $q$  if not public.user_has_store_access(e.store_id) then raise exception 'No access to this store'; end if;
  -- 422: therapy does not start on a package whose sale was refunded,
  -- cancelled or deleted (THERAPY-20).
  v_closed := public.therapy_invoice_closed_reason(e.invoice_id);
  if v_closed is not null then
    raise exception '%, so therapy cannot start on this package.', v_closed; end if;
$q$;
  c_choose1_a constant text := $q$declare e public.purchased_therapy_entitlements%rowtype; v_ent uuid; v_no text;
begin
$q$;
  c_choose1_r constant text := $q$declare e public.purchased_therapy_entitlements%rowtype; v_ent uuid; v_no text;
        v_closed text;  -- 422
begin
  perform public.require_active_staff();  -- 422: active staff only (406)
$q$;
  c_choose2_a constant text := $q$  if e.status in ('cancelled','refunded') then
    raise exception 'This purchase was %; nothing can be chosen against it', e.status; end if;
$q$;
  c_choose2_r constant text := $q$  if e.status in ('cancelled','refunded') then
    raise exception 'This purchase was %; nothing can be chosen against it', e.status; end if;
  -- 422: nor on a package whose sale was refunded, cancelled or deleted
  -- (THERAPY-20).
  v_closed := public.therapy_invoice_closed_reason(e.invoice_id);
  if v_closed is not null then
    raise exception '%, so no benefit can be chosen on this package.', v_closed; end if;
$q$;
  c_switch1_a constant text := $q$        v_prev text; v_old_ent uuid; v_new_ent uuid; v_claimed int;
begin
$q$;
  c_switch1_r constant text := $q$        v_prev text; v_old_ent uuid; v_new_ent uuid; v_claimed int;
        v_closed text;  -- 422
begin
  perform public.require_active_staff();  -- 422: active staff only (406)
$q$;
  c_switch2_a constant text := $q$  if not public.user_has_store_access(e.store_id) then
    raise exception 'No access to this store'; end if;

  v_state := public.purchased_therapy_unit_state(p_purchased_id);
$q$;
  c_switch2_r constant text := $q$  if not public.user_has_store_access(e.store_id) then
    raise exception 'No access to this store'; end if;
  -- 422: nothing is switched on a package whose sale was refunded,
  -- cancelled or deleted (THERAPY-20).
  v_closed := public.therapy_invoice_closed_reason(e.invoice_id);
  if v_closed is not null then
    raise exception '%, so this package cannot be switched.', v_closed; end if;

  v_state := public.purchased_therapy_unit_state(p_purchased_id);
$q$;
  c_benef1_a constant text := $q$    if public.my_assigned_store_id() is distinct from v_ent.store_id then
$q$;
  c_benef1_r constant text := $q$    -- 422: any store they work at, not only the first one they were given (X-9).
    if not public.user_has_store_access(v_ent.store_id) then
$q$;
  c_dates1_a constant text := $q$    return public.my_assigned_store_id() is not distinct from p_store_id;
$q$;
  c_dates1_r constant text := $q$    -- 422: any store they work at, not only the first one they were given (X-9).
    return public.user_has_store_access(p_store_id);
$q$;
  c_units1_a constant text := $q$         case when e.expiry_date is not null and e.status in ('active','scheduled')
              then greatest((e.expiry_date - public.sg_today())::integer, 0) end,
$q$;
  c_units1_r constant text := $q$         -- 422: calendar days left, today and the expiry day included, as the
         -- holdings summary counts them; a scheduled unit counts from its
         -- start (THERAPY-15).
         case when e.expiry_date is not null and e.status in ('active','scheduled')
              then greatest((e.expiry_date - greatest(public.sg_today(),
                                                      coalesce(e.activation_date, public.sg_today())))::integer + 1, 0) end,
$q$;
  c_units2_a constant text := $q$  select e.id, e.entitlement_no, e.customer_id, c.full_name, e.store_id,
$q$;
  c_units2_r constant text := $q$  select e.id, e.entitlement_no, e.customer_id,
         case when c.deleted_at is null then c.full_name end,  -- 422: never a deleted customer's name
         e.store_id,
$q$;
  c_refund1_a constant text := $q$declare e public.purchased_therapy_entitlements%rowtype;
begin
$q$;
  c_refund1_r constant text := $q$declare e public.purchased_therapy_entitlements%rowtype;
begin
  perform public.require_active_staff();  -- 422: active staff only (406)
$q$;
  c_refund2_a constant text := $q$  update public.commissions
     set status = 'reversed', reversal_reason = 'Therapy refunded: ' || p_reason
   where invoice_item_id = e.invoice_item_id and status in ('earned');
$q$;
  c_refund2_r constant text := $q$  -- 422: commission is left alone. It follows the money, and no money moves
  -- here; money goes back only through the invoice's Refund / Cancel (the
  -- Owner, 9 Oct 2026). This used to reverse the earned commission of the
  -- whole invoice line, products included, while the invoice stayed paid
  -- (THERAPY-9).
$q$;
  c_refund3_a constant text := $q$  if not found then raise exception 'Entitlement not found'; end if;
$q$;
  c_refund3_r constant text := $q$  if not found then raise exception 'Entitlement not found'; end if;
  -- 422: the package's own store, as the other package functions check.
  if not public.user_has_store_access(e.store_id) then raise exception 'No access to this store'; end if;
$q$;
  -- Rule 11: the voucher list a new qualification voucher reward keeps.
  c_lq1_a constant text := $q$  v_created integer := 0; v_cancelled integer := 0;
begin
$q$;
  c_lq1_r constant text := $q$  v_created integer := 0; v_cancelled integer := 0;
  v_list uuid[];  -- 422
begin
$q$;
  c_lq2_a constant text := $q$    v_deadline := p_day + coalesce(v_rule.activation_deadline_days, 365);
    for i in 1 .. (v_pending_needed - v_pending_have) loop
$q$;
  c_lq2_r constant text := $q$    v_deadline := p_day + coalesce(v_rule.activation_deadline_days, 365);
    -- 422: a voucher reward keeps its voucher list from the day it is earned
    -- (the Owner, 9 Oct 2026). The rules name no vouchers of their own, so
    -- it is the reward vouchers on offer that day, the ones a Legacy claim
    -- offers: active free-session vouchers marked as rewards. With none on
    -- offer it keeps no list, and an Owner or Manager hands it over.
    if coalesce(v_rule.entitlement_kind, 'unlimited') = 'voucher' then
      select array_agg(v.id order by v.id) into v_list
        from public.vouchers v
       where v.is_active and v.deleted_at is null
         and coalesce(v.reward_eligible, true) and v.voucher_kind = 'normal';
    end if;
    for i in 1 .. (v_pending_needed - v_pending_have) loop
$q$;
  c_lq3_a constant text := $q$        created_by, qualification_group_id)
      values (
$q$;
  c_lq3_r constant text := $q$        created_by, qualification_group_id, eligible_voucher_ids)
      values (
$q$;
  c_lq4_a constant text := $q$        auth.uid(), v_group);
$q$;
  c_lq4_r constant text := $q$        auth.uid(), v_group, v_list);
$q$;
  c_aq1_a constant text := $q$  v_e record; v_created integer := 0; v_cancelled integer := 0; v_deadline date;
begin
$q$;
  c_aq1_r constant text := $q$  v_e record; v_created integer := 0; v_cancelled integer := 0; v_deadline date;
  v_list uuid[];  -- 422
begin
$q$;
  c_aq2_a constant text := $q$    v_deadline := p_day + coalesce(v_rule.activation_deadline_days, 365);
    for i in 1 .. (v_needed - v_have) loop
$q$;
  c_aq2_r constant text := $q$    v_deadline := p_day + coalesce(v_rule.activation_deadline_days, 365);
    -- 422: the reward keeps its voucher list from the day it is earned (the
    -- Owner, 9 Oct 2026): the reward vouchers on offer that day, as for a
    -- customer's Legacy voucher reward. With none on offer it keeps no list.
    select array_agg(v.id order by v.id) into v_list
      from public.vouchers v
     where v.is_active and v.deleted_at is null
       and coalesce(v.reward_eligible, true) and v.voucher_kind = 'normal';
    for i in 1 .. (v_needed - v_have) loop
$q$;
  c_aq3_a constant text := $q$        status, created_by, qualification_group_id, earner_kind)
$q$;
  c_aq3_r constant text := $q$        status, created_by, qualification_group_id, earner_kind, eligible_voucher_ids)
$q$;
  c_aq4_a constant text := $q$        'pending_activation', auth.uid(), v_group, 'affiliate');
$q$;
  c_aq4_r constant text := $q$        'pending_activation', auth.uid(), v_group, 'affiliate', v_list);
$q$;

  c_closed_after  constant text := '2286c0c92003643d56b76d8d8827315c';
  c_list_after    constant text := 'fa78a96f7fbb74d770b54a8b700ad4b4';
  c_legacy_old    constant text := 'claim_legacy_therapy(uuid,date,uuid,jsonb,text,text)';
  c_legacy_new    constant text := 'claim_legacy_therapy(uuid,date,uuid,jsonb,text,text,boolean)';
  c_legacy_before constant text := '3957f56f3ea9dc8df6789371a20add66';
  c_legacy_after  constant text := '164530713b7a52f9b80642bbd0e1ed00';
  c_vclaim_after  constant text := '5a2e078df74a2763b6975bb939847b7a';
  c_vstate_after  constant text := '712eaace0a70bcbed47186beb1cd6d7a';
  c_refund_after  constant text := 'c51524d7dc76535111fe4c72e1cbb5ab';
  c_units_after   constant text := '9da46e18c367c76b5c3c2c2fe32a332d';
  -- An old wrapper of the six-argument claim (53, 72) that nothing calls.
  c_actleg        constant text := 'activate_legacy_therapy(uuid)';
  c_actleg_before constant text := 'e9d9c71e864fc6d22dfb8e8b335b173f';
  c_lq_after      constant text := '588fdaff42b49df16a051af839a2ff38';
  c_aq_after      constant text := '9b94f6008d92d15a61a3286672fdac00';
  c_patched constant text[] := array['claim_entitlement_vouchers(uuid,jsonb,text)', 'legacy_reward_voucher_options(uuid)', 'entitlement_voucher_state(uuid)', 'claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)', 'activate_purchased_therapy(uuid,date,text,text,text,boolean)', 'choose_therapy_benefit(uuid,text,uuid,text)', 'switch_therapy_benefit(uuid,text,text,uuid)', 'activate_therapy_beneficiary(uuid,date,date)', 'can_change_therapy_dates(uuid)', 'purchased_therapy_units(uuid,uuid,boolean)', 'refund_purchased_therapy(uuid,text)', 'recompute_legacy_qualification(uuid,uuid,date)', 'recompute_affiliate_legacy_qualification(uuid,date)'];
  -- The read rule on purchased_therapy_entitlements, before and after.
  c_pte_before constant text := '(current_user_role() IS NOT NULL)';
  c_pte_after  constant text := '((current_user_role() IS NOT NULL) AND user_has_store_access(store_id))';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_claim_sub text := current_setting('request.jwt.claim.sub', true);
  v_claim_role text := current_setting('request.jwt.claim.role', true);
  r record; d text; v text; n int; k int; i int; v_bad text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[]; v_edits text[];
  v_closed_new boolean; v_list_new boolean; v_legacy_new boolean; v_pte_new boolean; v_actleg_drop boolean;
  v_legacy_def text; v_legacy_acl text;
  -- The behaviour check.
  v_tag text; v_owner uuid; v_store uuid; v_cust uuid; v_normal uuid; v_discount uuid;
  v_inv uuid; v_pkg uuid; v_te_v uuid; v_te_run uuid; v_te_pend uuid; v_te_closed uuid;
  v_unit uuid; v_res jsonb; v_msg text; v_who text; v_invitee uuid;
  v_gone uuid; v_gone_phone text; v_te_gone uuid; v_staff uuid; v_te_list uuid; v_unit_gone uuid;
begin
  -- Read and compared with public alone on the search path, as on 9 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── Guards, anchors and new texts: nothing is installed unless all pass ───
  -- The two new functions: missing, or already this version.
  v_closed_new := to_regprocedure('public.therapy_invoice_closed_reason(uuid)') is null;
  if not v_closed_new
     and md5(pg_get_functiondef(to_regprocedure('public.therapy_invoice_closed_reason(uuid)'))) <> c_closed_after then
    raise exception '422: public.therapy_invoice_closed_reason(uuid) exists and is not this migration''s version'; end if;
  v_list_new := to_regprocedure('public.therapy_list_page(text,text,text,integer,integer)') is null;
  if not v_list_new
     and md5(pg_get_functiondef(to_regprocedure('public.therapy_list_page(text,text,text,integer,integer)'))) <> c_list_after then
    raise exception '422: public.therapy_list_page(text,text,text,integer,integer) exists and is not this migration''s version'; end if;
  if md5(c_closed_def) <> c_closed_after or md5(c_list_def) <> c_list_after then
    raise exception '422: a new function text is not the tested one'; end if;

  -- claim_legacy_therapy: the six-argument one as read on 9 Oct 2026 and no
  -- seven-argument one; or, on a re-run, only the seven-argument one as this
  -- migration makes it.
  if to_regprocedure('public.' || c_legacy_old) is not null and to_regprocedure('public.' || c_legacy_new) is null then
    d := pg_get_functiondef(to_regprocedure('public.' || c_legacy_old));
    if md5(d) <> c_legacy_before then
      raise exception '422: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.',
        c_legacy_old, md5(d); end if;
    v_edits := array[[c_legacy1_a, c_legacy1_r], [c_legacy2_a, c_legacy2_r], [c_legacy3_a, c_legacy3_r], [c_legacy4_a, c_legacy4_r], [c_legacy5_a, c_legacy5_r], [c_legacy6_a, c_legacy6_r], [c_legacy7_a, c_legacy7_r], [c_legacy8_a, c_legacy8_r], [c_legacy9_a, c_legacy9_r]];
    for k in 1 .. array_length(v_edits, 1) loop
      n := (length(d) - length(replace(d, v_edits[k][1], ''))) / length(v_edits[k][1]);
      if n <> 1 then
        raise exception '422: anchor % of public.% was found % times, not once', k, c_legacy_old, n; end if;
      d := replace(d, v_edits[k][1], v_edits[k][2]);
    end loop;
    if md5(d) <> c_legacy_after then
      raise exception '422: the new text of claim_legacy_therapy is not the tested one'; end if;
    v_legacy_def := d;
    v_legacy_new := true;
    -- Its grants, for the seven-argument one.
    select string_agg(case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end
                      || ':' || a.privilege_type, ',' order by a.grantee::regrole::text, a.privilege_type)
      into v_legacy_acl
      from aclexplode((select p.proacl from pg_proc p where p.oid = to_regprocedure('public.' || c_legacy_old))) a;
  elsif to_regprocedure('public.' || c_legacy_old) is null and to_regprocedure('public.' || c_legacy_new) is not null
        and md5(pg_get_functiondef(to_regprocedure('public.' || c_legacy_new))) = c_legacy_after then
    v_legacy_new := false;
    raise notice '422: public.% is already this version; left alone', c_legacy_new;
  else
    raise exception '422: claim_legacy_therapy is neither the six-argument version read on 9 Oct 2026 alone nor this migration''s seven-argument one alone. Re-read it and re-test before applying.';
  end if;

  -- activate_legacy_therapy(uuid): the old wrapper as read on 10 Oct 2026,
  -- or already gone (a re-run).
  v_actleg_drop := to_regprocedure('public.' || c_actleg) is not null;
  if v_actleg_drop then
    d := pg_get_functiondef(to_regprocedure('public.' || c_actleg));
    if md5(d) <> c_actleg_before then
      raise exception '422: public.% is not the version read on 10 Oct 2026 (md5 %). Re-read it from production and re-test before applying.',
        c_actleg, md5(d); end if;
  else
    raise notice '422: public.% is already gone; left alone', c_actleg;
  end if;

  -- The functions changed in place.
  for r in select * from (values
    ('claim_entitlement_vouchers(uuid,jsonb,text)', 'e6958c6052d3dd8d7ea3a175d614b5da', c_vclaim_after, array[[c_vclaim1_a, c_vclaim1_r], [c_vclaim2_a, c_vclaim2_r], [c_vclaim3_a, c_vclaim3_r], [c_vclaim4_a, c_vclaim4_r], [c_vclaim5_a, c_vclaim5_r]]),
    ('legacy_reward_voucher_options(uuid)', '8728d0ba59ddf0a9e7161ed3483c4618', '38a22dd0f89179f5412e575fa2cbd0a8', array[[c_voptions1_a, c_voptions1_r]]),
    ('entitlement_voucher_state(uuid)', 'f8b6a3a4521e025ed2cd1151cab53ae8', c_vstate_after, array[[c_vstate1_a, c_vstate1_r], [c_vstate2_a, c_vstate2_r], [c_vstate3_a, c_vstate3_r]]),
    ('claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)', '44abcd5d179fa7d24438c4c44cc0be8f', 'c833e4cbfd01b3de4d825b5f6080e73e', array[[c_pclaim1_a, c_pclaim1_r], [c_pclaim2_a, c_pclaim2_r]]),
    ('activate_purchased_therapy(uuid,date,text,text,text,boolean)', '0c4f319294981cd5efef616781d54a2b', '1047cc5c2ed136ae4fd22d0b471c4199', array[[c_pactivate1_a, c_pactivate1_r], [c_pactivate2_a, c_pactivate2_r]]),
    ('choose_therapy_benefit(uuid,text,uuid,text)', '676a8a158482c4d68706308574efe92f', 'bf419bd6487f392a6ab2b5b302cf48f5', array[[c_choose1_a, c_choose1_r], [c_choose2_a, c_choose2_r]]),
    ('switch_therapy_benefit(uuid,text,text,uuid)', '0d8df6b39e9f58d6ac249ea180162054', 'aac8021b58fd5d60c7519823904a764c', array[[c_switch1_a, c_switch1_r], [c_switch2_a, c_switch2_r]]),
    ('activate_therapy_beneficiary(uuid,date,date)', 'e71626b41d083a4c7014b1dc55016055', '9ac0bf428a1e3495e3ea39452feab994', array[[c_benef1_a, c_benef1_r]]),
    ('can_change_therapy_dates(uuid)', 'dcd3b810e51323b27e348d9c6aadb22a', '716e85614c683208987b660d0c5d35a0', array[[c_dates1_a, c_dates1_r]]),
    ('purchased_therapy_units(uuid,uuid,boolean)', '265662fe473dd6d6901843c9ae06f63c', c_units_after, array[[c_units1_a, c_units1_r], [c_units2_a, c_units2_r]]),
    ('refund_purchased_therapy(uuid,text)', '82bfeaa5f54a4ff3b7495bca6e9ed7bf', c_refund_after, array[[c_refund1_a, c_refund1_r], [c_refund2_a, c_refund2_r], [c_refund3_a, c_refund3_r]]),
    ('recompute_legacy_qualification(uuid,uuid,date)', '490b1420f18e07daff553c9fa990cfc6', c_lq_after, array[[c_lq1_a, c_lq1_r], [c_lq2_a, c_lq2_r], [c_lq3_a, c_lq3_r], [c_lq4_a, c_lq4_r]]),
    ('recompute_affiliate_legacy_qualification(uuid,date)', '754e10e7093f1cb2d4abee8254453d9e', c_aq_after, array[[c_aq1_a, c_aq1_r], [c_aq2_a, c_aq2_r], [c_aq3_a, c_aq3_r], [c_aq4_a, c_aq4_r]])
  ) x(fn, before_md5, after_md5, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '422: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '422: public.% is already this version; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '422: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    for k in 1 .. array_length(r.edits, 1) loop
      n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
      if n <> 1 then
        raise exception '422: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
      d := replace(d, r.edits[k][1], r.edits[k][2]);
    end loop;
    if md5(d) <> r.after_md5 then
      raise exception '422: the new text of public.% is not the tested one', r.fn; end if;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;

  -- Relied on, not changed: the active-staff check, the next free start (its
  -- keys suggested_start, latest_existing_expiry, existing), what was claimed
  -- on an entitlement, a unit's status by its dates, today in Singapore.
  for r in select * from (values
    ('require_active_staff(text[])', '877b3aa74cea559881979bb161c450e2'),
    ('therapy_next_available_start(uuid,date)', 'fb4856596855d1718f446c30c5e36246'),
    ('entitlement_claimed_qty(uuid)', '89b08265d5303e890569e953d83d2440'),
    ('purchased_therapy_status_on(text,date,date,date,date)', '991ec75f0349f61ef1a2f3682fb142b1'),
    ('sg_today()', '1c1289f18e24d8370e9a6364c9c06fca')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '422: public.% is missing or not the version read on 9 Oct 2026. Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;
  if not exists (select 1 from pg_enum e where e.enumtypid = 'public.voucher_kind'::regtype and e.enumlabel = 'normal') then
    raise exception '422: vouchers have no ''normal'' kind'; end if;
  if (select count(*) from pg_enum e where e.enumtypid = 'public.invoice_status'::regtype
       and e.enumlabel in ('refunded', 'cancelled')) <> 2 then
    raise exception '422: invoices have no ''refunded'' or ''cancelled'' status'; end if;

  -- No other function takes any of these names (the API picks one by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in (select split_part(x, '(', 1) from unnest(c_patched || array[c_legacy_old, c_actleg,
                         'therapy_invoice_closed_reason(uuid)', 'therapy_list_page(text,text,text,integer,integer)']) x)
     and p.oid::regprocedure::text <> all (c_patched || array[c_legacy_old, c_legacy_new, c_actleg,
                         'therapy_invoice_closed_reason(uuid)', 'therapy_list_page(text,text,text,integer,integer)']);
  if v_bad is not null then
    raise exception '422: another function takes one of these names: %', v_bad; end if;

  -- The read rule on purchased packages: the one read on 9 Oct 2026 or this
  -- one, alone, for signed-in logins, with row level security on.
  select pg_get_expr(p.polqual, p.polrelid) into v
    from pg_policy p
   where p.polrelid = 'public.purchased_therapy_entitlements'::regclass and p.polname = 'read pte'
     and p.polcmd = 'r' and p.polpermissive and p.polroles::regrole[]::text = '{authenticated}';
  if v = c_pte_before then
    v_pte_new := true;
  elsif v = c_pte_after then
    v_pte_new := false;
  else
    raise exception '422: policy "read pte" on purchased_therapy_entitlements is not the one read on 9 Oct 2026 (%)', coalesce(v, 'missing'); end if;
  if exists (select 1 from pg_policy p where p.polrelid = 'public.purchased_therapy_entitlements'::regclass
              and p.polname <> 'read pte' and p.polcmd in ('r', '*')) then
    raise exception '422: purchased_therapy_entitlements has another read rule; re-read it before applying'; end if;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.purchased_therapy_entitlements'::regclass) then
    raise exception '422: row level security is off on purchased_therapy_entitlements'; end if;

  -- The grants of the functions changed in place, to compare after.
  select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
    into v_acl
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = any (c_patched);

  -- ── Install ───────────────────────────────────────────────────────────────
  -- The helper first: the others call it.
  if v_closed_new then
    execute c_closed_def;
    revoke all on function public.therapy_invoice_closed_reason(uuid) from public, anon, authenticated;
    grant execute on function public.therapy_invoice_closed_reason(uuid) to service_role;
  end if;
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
  end loop;
  -- The seven-argument claim, with the six-argument one's grants; then the
  -- six-argument one goes (386, 388, 390).
  if v_legacy_new then
    execute v_legacy_def;
    revoke all on function public.claim_legacy_therapy(uuid,date,uuid,jsonb,text,text,boolean) from public, anon;
    grant execute on function public.claim_legacy_therapy(uuid,date,uuid,jsonb,text,text,boolean) to authenticated, service_role;
    drop function public.claim_legacy_therapy(uuid,date,uuid,jsonb,text,text);
  end if;
  -- The old wrapper goes too (386, 388, 390). RESTRICT: refused if anything
  -- has come to depend on it.
  if v_actleg_drop then
    drop function public.activate_legacy_therapy(uuid) restrict;
  end if;
  if v_list_new then
    execute c_list_def;
    revoke all on function public.therapy_list_page(text,text,text,integer,integer) from public, anon;
    grant execute on function public.therapy_list_page(text,text,text,integer,integer) to authenticated, service_role;
  end if;
  if v_pte_new then
    drop policy "read pte" on public.purchased_therapy_entitlements;
    create policy "read pte" on public.purchased_therapy_entitlements
      for select to authenticated
      using (public.current_user_role() is not null and public.user_has_store_access(store_id));
  end if;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  v_bad := null;
  for r in select * from (values
    ('therapy_invoice_closed_reason(uuid)', c_closed_after),
    ('therapy_list_page(text,text,text,integer,integer)', c_list_after),
    (c_legacy_new, c_legacy_after),
    ('claim_entitlement_vouchers(uuid,jsonb,text)', c_vclaim_after),
    ('legacy_reward_voucher_options(uuid)', '38a22dd0f89179f5412e575fa2cbd0a8'),
    ('entitlement_voucher_state(uuid)', c_vstate_after),
    ('claim_purchased_therapy(uuid,text,date,text,text,boolean,jsonb,uuid,text)', 'c833e4cbfd01b3de4d825b5f6080e73e'),
    ('activate_purchased_therapy(uuid,date,text,text,text,boolean)', '1047cc5c2ed136ae4fd22d0b471c4199'),
    ('choose_therapy_benefit(uuid,text,uuid,text)', 'bf419bd6487f392a6ab2b5b302cf48f5'),
    ('switch_therapy_benefit(uuid,text,text,uuid)', 'aac8021b58fd5d60c7519823904a764c'),
    ('activate_therapy_beneficiary(uuid,date,date)', '9ac0bf428a1e3495e3ea39452feab994'),
    ('can_change_therapy_dates(uuid)', '716e85614c683208987b660d0c5d35a0'),
    ('purchased_therapy_units(uuid,uuid,boolean)', c_units_after),
    ('refund_purchased_therapy(uuid,text)', c_refund_after),
    ('recompute_legacy_qualification(uuid,uuid,date)', c_lq_after),
    ('recompute_affiliate_legacy_qualification(uuid,date)', c_aq_after)
  ) x(fn, after_md5)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      v_bad := concat_ws('; ', v_bad, r.fn || ' missing');
    elsif md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))));
    end if;
  end loop;
  if v_bad is not null then
    raise exception '422: installed with md5s other than the tested ones: %', v_bad; end if;
  if to_regprocedure('public.' || c_legacy_old) is not null then
    raise exception '422: the six-argument claim_legacy_therapy is still there'; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'activate_legacy_therapy') then
    raise exception '422: activate_legacy_therapy is still there'; end if;
  -- Grants: the functions changed in place keep theirs exactly.
  if (select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
        from pg_proc p
       where p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = any (c_patched))
     is distinct from v_acl then
    raise exception '422: the grants of the changed functions changed'; end if;
  -- The seven-argument claim has the six-argument one's grants.
  if v_legacy_new and (select string_agg(case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end
                                         || ':' || a.privilege_type, ',' order by a.grantee::regrole::text, a.privilege_type)
                         from aclexplode((select p.proacl from pg_proc p
                                           where p.oid = to_regprocedure('public.' || c_legacy_new))) a)
                      is distinct from v_legacy_acl then
    raise exception '422: the new claim_legacy_therapy does not have the old one''s grants'; end if;
  -- The page's functions: staff (authenticated) and the server; never anon.
  foreach v in array array[c_legacy_new, 'therapy_list_page(text,text,text,integer,integer)'] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or not has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute')
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                   where p.oid = to_regprocedure('public.' || v) and a.grantee = 0) then
      raise exception '422: public.% is not granted to staff and the server alone', v; end if;
  end loop;
  -- The helper is the service role's alone (339).
  if has_function_privilege('anon', 'public.therapy_invoice_closed_reason(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.therapy_invoice_closed_reason(uuid)', 'execute')
     or not has_function_privilege('service_role', 'public.therapy_invoice_closed_reason(uuid)', 'execute')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                 where p.oid = to_regprocedure('public.therapy_invoice_closed_reason(uuid)') and a.grantee = 0) then
    raise exception '422: public.therapy_invoice_closed_reason(uuid) is not the service role''s alone'; end if;
  -- The read rule.
  if (select pg_get_expr(p.polqual, p.polrelid) from pg_policy p
       where p.polrelid = 'public.purchased_therapy_entitlements'::regclass and p.polname = 'read pte'
         and p.polcmd = 'r' and p.polpermissive and p.polroles::regrole[]::text = '{authenticated}')
     is distinct from c_pte_after then
    raise exception '422: policy "read pte" is not as tested'; end if;

  -- ── Behaviour, inside a block that is always undone ───────────────────────
  -- A made-up Owner, member of staff, store, customer, deleted customer, two
  -- vouchers (a session, a discount), a refunded sale, Legacy rewards, a
  -- purchased unit and a pending invitee. Nothing is printed and no row
  -- remains.
  begin
    -- Who is asking comes from request.jwt.claims alone here (auth.uid()
    -- reads the older single settings first).
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
    v_tag := left(md5(random()::text || clock_timestamp()::text), 8);
    insert into auth.users (id, email)
    values (gen_random_uuid(), '422-check-owner-' || v_tag || '@sig.invalid') returning id into v_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (v_owner, '422 check', '422-check-owner-' || v_tag || '@sig.invalid', 'owner', true);
    insert into public.stores (name, code, country_code)
    values ('422 check store', '422CHK-' || v_tag, 'SG') returning id into v_store;
    -- A member of staff of that store (rule 10).
    insert into auth.users (id, email)
    values (gen_random_uuid(), '422-check-staff-' || v_tag || '@sig.invalid') returning id into v_staff;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (v_staff, '422 check staff', '422-check-staff-' || v_tag || '@sig.invalid', 'staff', true);
    insert into public.user_store_assignments (user_id, store_id) values (v_staff, v_store);
    insert into public.customers (full_name, phone)
    values ('422 check customer', '+6591422' || lpad(floor(random() * 1000)::int::text, 3, '0')) returning id into v_cust;
    -- A customer deleted since (rule 9).
    insert into public.customers (full_name, phone, deleted_at)
    values ('422 check gone ' || v_tag, '+6591423' || lpad(floor(random() * 1000)::int::text, 3, '0'), now())
    returning id, phone into v_gone, v_gone_phone;
    insert into public.vouchers (name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('422 check session', '422CHK-S-' || v_tag, 'normal', 'unlimited', 0, true) returning id into v_normal;
    insert into public.vouchers (name, code, voucher_kind, qty_type, selling_price, is_active, discount_amount)
    values ('422 check discount', '422CHK-D-' || v_tag, 'fixed_discount', 'unlimited', 0, true, 5) returning id into v_discount;
    insert into public.invoices (invoice_no, store_id, customer_id, created_by, status)
    values ('422-CHECK-' || v_tag, v_store, v_cust, v_owner, 'refunded') returning id into v_inv;
    insert into public.therapy_entitlements (entitlement_no, customer_id, store_id, package_name, entitlement_kind,
        duration_months, voucher_qty, qualifying_amount, qualified_value, activation_deadline, status,
        activation_date, expiry_date, claim_source_type, claim_source_invoice_id)
    values ('422-CHECK-V-' || v_tag, v_cust, v_store, '422 check vouchers', 'voucher', 1, 3, 0, 0,
            public.sg_today() + 30, 'pending_activation', null, null, null, null)
    returning id into v_te_v;
    insert into public.therapy_entitlements (entitlement_no, customer_id, store_id, package_name, entitlement_kind,
        duration_months, voucher_qty, qualifying_amount, qualified_value, activation_deadline, status,
        activation_date, expiry_date)
    values ('422-CHECK-R-' || v_tag, v_cust, v_store, '422 check running', 'unlimited', 1, null, 0, 0,
            public.sg_today() + 30, 'active', public.sg_today() - 5, public.sg_today() + 20)
    returning id into v_te_run;
    insert into public.therapy_entitlements (entitlement_no, customer_id, store_id, package_name, entitlement_kind,
        duration_months, voucher_qty, qualifying_amount, qualified_value, activation_deadline, status)
    values ('422-CHECK-P-' || v_tag, v_cust, v_store, '422 check pending', 'unlimited', 1, null, 0, 0,
            public.sg_today() + 60, 'pending_activation')
    returning id into v_te_pend;
    insert into public.therapy_entitlements (entitlement_no, customer_id, store_id, package_name, entitlement_kind,
        duration_months, voucher_qty, qualifying_amount, qualified_value, activation_deadline, status,
        claim_source_type, claim_source_invoice_id)
    values ('422-CHECK-C-' || v_tag, v_cust, v_store, '422 check refunded sale', 'voucher', 1, 2, 0, 0,
            public.sg_today() + 30, 'pending_activation', 'credit_package', v_inv)
    returning id into v_te_closed;
    insert into public.therapy_entitlements (entitlement_no, customer_id, store_id, package_name, entitlement_kind,
        duration_months, voucher_qty, qualifying_amount, qualified_value, activation_deadline, status)
    values ('422-CHECK-G-' || v_tag, v_gone, v_store, '422 check gone', 'voucher', 1, 1, 0, 0,
            public.sg_today() + 30, 'pending_activation')
    returning id into v_te_gone;
    -- A voucher reward with a voucher list and no sale (rule 10: staff may).
    insert into public.therapy_entitlements (entitlement_no, customer_id, store_id, package_name, entitlement_kind,
        duration_months, voucher_qty, qualifying_amount, qualified_value, activation_deadline, status,
        eligible_voucher_ids)
    values ('422-CHECK-L-' || v_tag, v_cust, v_store, '422 check listed', 'voucher', 1, 2, 0, 0,
            public.sg_today() + 30, 'pending_activation', array[v_normal])
    returning id into v_te_list;
    insert into public.unlimited_therapy_packages (name, duration_months)
    values ('422 check package', 1) returning id into v_pkg;
    insert into public.purchased_therapy_entitlements (entitlement_no, customer_id, store_id, package_id, invoice_id,
        package_name, duration_months, price_snapshot, purchase_date, activation_deadline, status,
        benefit_choice, offered_choices)
    values ('422-CHECK-U-' || v_tag, v_cust, v_store, v_pkg, v_inv, '422 check package', 1, 0, public.sg_today(),
            public.sg_today() + 300, 'pending_activation', 'unlimited', array['unlimited'])
    returning id into v_unit;
    -- The deleted customer's package (rule 9).
    insert into public.purchased_therapy_entitlements (entitlement_no, customer_id, store_id, package_id, invoice_id,
        package_name, duration_months, price_snapshot, purchase_date, activation_deadline, status,
        benefit_choice, offered_choices)
    values ('422-CHECK-G2-' || v_tag, v_gone, v_store, v_pkg, v_inv, '422 check package', 1, 0, public.sg_today(),
            public.sg_today() + 300, 'pending_activation', 'unlimited', array['unlimited'])
    returning id into v_unit_gone;

    -- As the made-up Owner, signed in.
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);

    -- Rule 3: the reward list holds the session voucher, not the discount.
    if exists (select 1 from public.legacy_reward_voucher_options(v_store) o where o.voucher_id = v_discount)
       or not exists (select 1 from public.legacy_reward_voucher_options(v_store) o where o.voucher_id = v_normal) then
      raise exception '422: the reward voucher list is not the normal vouchers'; end if;
    -- Rule 4: no record of its vouchers offers the normal reward vouchers.
    v_res := public.entitlement_voucher_state(v_te_v);
    if (v_res->>'snapshot_present')::boolean
       or not (v_res->'eligible') @> jsonb_build_array(jsonb_build_object('voucher_id', v_normal))
       or (v_res->'eligible') @> jsonb_build_array(jsonb_build_object('voucher_id', v_discount))
       or v_res->>'blocked_reason' is not null then
      raise exception '422: a reward with no voucher list does not offer the normal reward vouchers'; end if;
    -- Rule 10: with no sale and no voucher list as well, an Owner or Manager
    -- hands it over. A member of staff of its store is refused, and hands
    -- over a reward that has a list.
    if not coalesce((v_res->>'owner_or_manager_only')::boolean, false)
       or coalesce((public.entitlement_voucher_state(v_te_list)->>'owner_or_manager_only')::boolean, true) then
      raise exception '422: the Vouchers window does not say which rewards wait for an Owner or Manager'; end if;
    perform set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
    v_msg := null;
    begin
      perform public.claim_entitlement_vouchers(v_te_v, jsonb_build_array(jsonb_build_object('voucher_id', v_normal, 'quantity', 1)), null);
    exception when others then v_msg := sqlerrm;
    end;
    if v_msg is distinct from 'No sale and no voucher list is recorded for this reward, so an Owner or Manager hands it over.' then
      raise exception '422: a member of staff handed over a reward with no sale and no voucher list (%)', coalesce(v_msg, 'accepted'); end if;
    v_res := public.claim_entitlement_vouchers(v_te_list, jsonb_build_array(jsonb_build_object('voucher_id', v_normal, 'quantity', 1)), null);
    if (v_res->>'claimed_now')::int is distinct from 1 then
      raise exception '422: a member of staff could not hand over a reward with a voucher list'; end if;
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    -- Rule 3 at the claim.
    v_msg := null;
    begin
      perform public.claim_entitlement_vouchers(v_te_v, jsonb_build_array(jsonb_build_object('voucher_id', v_discount, 'quantity', 1)), null);
    exception when others then v_msg := sqlerrm;
    end;
    if v_msg is null or v_msg not like 'That voucher cannot be given as a reward%' then
      raise exception '422: a discount voucher was handed over as a reward (%)', coalesce(v_msg, 'accepted'); end if;
    -- Rule 2: 2 and -1, and 1.5.
    foreach v in array array['[{"q": 2}, {"q": -1}]', '[{"q": 1.5}]'] loop
      v_msg := null;
      begin
        perform public.claim_entitlement_vouchers(v_te_v,
          (select jsonb_agg(jsonb_build_object('voucher_id', v_normal, 'quantity', x->'q')) from jsonb_array_elements(v::jsonb) x), null);
      exception when others then v_msg := sqlerrm;
      end;
      if v_msg is null or v_msg not like 'A voucher quantity must be a whole number%' then
        raise exception '422: a voucher quantity that is not a whole number of at least one was taken (%)', coalesce(v_msg, 'accepted'); end if;
    end loop;
    -- Rule 1: handed over in the Vouchers window, a few at a time.
    perform public.claim_entitlement_vouchers(v_te_v, jsonb_build_array(jsonb_build_object('voucher_id', v_normal, 'quantity', 1)), null);
    v_res := public.therapy_list_page('legacy', '422-check-v-' || v_tag, 'all', 50, 0);
    if (v_res->>'total')::int <> 1 or (v_res->'rows'->0->>'claimed_qty')::int <> 1
       or (v_res->'rows'->0->>'remaining')::int <> 2 then
      raise exception '422: the Legacy list does not show what was claimed and is left'; end if;
    if not coalesce((v_res->'rows'->0->>'owner_or_manager_only')::boolean, false) then
      raise exception '422: the Legacy list does not say the reward waits for an Owner or Manager'; end if;
    -- A page past the end still gives the full total.
    v_res := public.therapy_list_page('legacy', '422-check-v-' || v_tag, 'all', 50, 5);
    if (v_res->>'total')::int <> 1 or jsonb_array_length(v_res->'rows') <> 0 then
      raise exception '422: a Legacy page past the end does not give the full total'; end if;
    -- Rule 9: a deleted customer's row shows with no name or phone, and is
    -- not found by them.
    v_res := public.therapy_list_page('legacy', '422-check-g-' || v_tag, 'all', 50, 0);
    if (v_res->>'total')::int <> 1 or v_res->'rows'->0->>'customer_name' is not null
       or v_res->'rows'->0->>'customer_phone' is not null then
      raise exception '422: the Legacy list gives a deleted customer''s name or phone'; end if;
    foreach v in array array['422 check gone ' || v_tag, v_gone_phone] loop
      if exists (select 1 from jsonb_array_elements(public.therapy_list_page('legacy', v, 'all', 200, 0)->'rows') x
                  where (x->>'id')::uuid = v_te_gone) then
        raise exception '422: the Legacy list finds a deleted customer by name or phone'; end if;
    end loop;
    -- Rule 9 in purchased_therapy_units: no name for the deleted customer,
    -- the name as before for a live one.
    if (select count(*) from public.purchased_therapy_units(v_store, null, false) u
         where (u.purchased_id = v_unit_gone and u.customer_name is null)
            or (u.purchased_id = v_unit and u.customer_name = '422 check customer')) <> 2 then
      raise exception '422: purchased_therapy_units gives a deleted customer''s name'; end if;
    -- Rule 1: never as a Legacy claim.
    v_msg := null;
    begin
      perform public.claim_legacy_therapy(v_te_v, null, null,
        jsonb_build_array(jsonb_build_object('voucher_id', v_normal, 'quantity', 2)));
    exception when others then v_msg := sqlerrm;
    end;
    if v_msg is null or v_msg not like 'This is a voucher reward%' then
      raise exception '422: a voucher reward was claimed as a Legacy claim (%)', coalesce(v_msg, 'accepted'); end if;
    -- Rule 6: an overlap asks first and writes nothing; confirmed, it claims.
    v_res := public.claim_legacy_therapy(v_te_pend, public.sg_today());
    if not coalesce((v_res->>'requires_confirmation')::boolean, false)
       or (v_res->>'suggested_start')::date <> public.sg_today() + 21
       or (select status from public.therapy_entitlements where id = v_te_pend) <> 'pending_activation' then
      raise exception '422: an overlapping Legacy claim did not ask first'; end if;
    v_res := public.therapy_list_page('legacy', '422-check-p-' || v_tag, null, 50, 0);
    if (v_res->'rows'->0->>'next_free_start')::date <> public.sg_today() + 21 then
      raise exception '422: the Legacy list does not give the next free start'; end if;
    v_res := public.claim_legacy_therapy(v_te_pend, public.sg_today(), null, null, null, null, true);
    if not coalesce((v_res->>'claimed')::boolean, false) or not coalesce((v_res->>'overlapped')::boolean, false)
       or (select status from public.therapy_entitlements where id = v_te_pend) <> 'active' then
      raise exception '422: a confirmed overlapping Legacy claim was not made'; end if;
    -- Rule 5: a refunded sale's reward and package.
    v_msg := null;
    begin
      perform public.claim_entitlement_vouchers(v_te_closed, jsonb_build_array(jsonb_build_object('voucher_id', v_normal, 'quantity', 1)), null);
    exception when others then v_msg := sqlerrm;
    end;
    if v_msg is null or v_msg not like 'Invoice 422-CHECK-% was refunded, so nothing can be claimed on this reward.' then
      raise exception '422: a reward on a refunded sale was handed over (%)', coalesce(v_msg, 'accepted'); end if;
    if public.entitlement_voucher_state(v_te_closed)->>'blocked_reason' is distinct from 'Invoice 422-CHECK-' || v_tag || ' was refunded' then
      raise exception '422: the voucher window does not say the sale was refunded'; end if;
    v_msg := null;
    begin
      perform public.claim_purchased_therapy(v_unit, 'unlimited', public.sg_today());
    exception when others then v_msg := sqlerrm;
    end;
    if v_msg is null or v_msg not like 'Invoice 422-CHECK-% was refunded, so nothing can be claimed on this package.' then
      raise exception '422: a package on a refunded sale was claimed (%)', coalesce(v_msg, 'accepted'); end if;
    v_res := public.therapy_list_page('purchased', '422-check-u-' || v_tag, null, 50, 0);
    if (v_res->>'total')::int <> 1 or v_res->'rows'->0->>'invoice_closed_reason' is null then
      raise exception '422: the Purchased list does not say the sale was refunded'; end if;
    v_res := public.therapy_list_page('purchased', '422-check-u-' || v_tag, null, 50, 50);
    if (v_res->>'total')::int <> 1 or jsonb_array_length(v_res->'rows') <> 0 then
      raise exception '422: a Purchased page past the end does not give the full total'; end if;

    -- Rule 8: the made-up Owner reads the unit; a pending invitee assigned to
    -- its store reads nothing.
    if has_table_privilege('authenticated', 'public.purchased_therapy_entitlements', 'select') then
      insert into auth.users (id, email)
      values (gen_random_uuid(), '422-check-invitee-' || v_tag || '@sig.invalid') returning id into v_invitee;
      insert into public.profiles (id, full_name, email, role, is_active, invitation_status)
      values (v_invitee, '422 check invitee', '422-check-invitee-' || v_tag || '@sig.invalid', 'staff', true, 'pending');
      insert into public.user_store_assignments (user_id, store_id) values (v_invitee, v_store);
      -- The Owner reads 1; the invitee 0.
      foreach v_who in array array['owner', 'invitee'] loop
        k := (v_who = 'owner')::int;
        perform set_config('request.jwt.claims', json_build_object('sub',
          (array[v_invitee, v_owner])[k + 1], 'role', 'authenticated')::text, true);
        execute 'set local role authenticated';
        select count(*) into n from public.purchased_therapy_entitlements where id = v_unit;
        execute 'reset role';
        if n <> k then
          raise exception '422: the % reads % purchased package(s) of the store, not %', v_who, n, k; end if;
      end loop;
      perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    end if;

    -- Switching role: the anon key, and a signed-in login with no profile.
    foreach v_who in array array['anon', 'authenticated'] loop
      perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', v_who)::text, true);
      execute format('set local role %I', v_who);
      foreach v in array array['select public.therapy_list_page(''legacy'')',
                               format('select public.claim_legacy_therapy(%L)', v_te_pend),
                               format('select public.therapy_invoice_closed_reason(%L)', v_inv)] loop
        v_msg := null;
        begin
          execute v;
        exception when insufficient_privilege then v_msg := 'refused';
        end;
        if v_msg is null then
          execute 'reset role';
          raise exception '422: % was answered for % (not staff)', v, v_who; end if;
      end loop;
      execute 'reset role';
    end loop;
    perform set_config('request.jwt.claims', '', true);

    raise exception using errcode = 'P0422', message = '422: check done, undone';
  exception when sqlstate 'P0422' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_claim_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_claim_role, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
