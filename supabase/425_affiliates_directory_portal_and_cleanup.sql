-- 425_affiliates_directory_portal_and_cleanup.sql
--
-- AFFILIATES: ONE PASS FOR THE LISTS, TIER 1 AND TIER 2 ONLY, THE PORTAL
-- KEEPS STAFF NOTES, A SHARED-PHONE SIGN-UP IS CHECKED BEFORE IT COUNTS, AND
-- THE LEGACY AFFILIATE TABLES GO (audit of 9 Oct 2026, section 6: AFFILIATES-5,
-- -13, -4, -11, -12, -15, -M2 and -10)
--
-- WHAT WAS WRONG
--
--   1. AFFILIATES-5. The Affiliates page, the Referrers tab and the Reports
--      affiliate report read every commission row once for each affiliate,
--      several times over, and the balances once for each row. On 9 Oct the
--      report took 1.2 s, on 18 Oct 2.2 s (59 rows); it grows with affiliates
--      times commission rows. Written the new way, the same report took
--      0.19 s on production's data (read-only, 18 Oct).
--      commission_reporting_rows added up each commission's payout
--      allocations one commission at a time.
--   2. AFFILIATES-13. The Referrers tab followed the referral chain 50 levels
--      down and called them Tier 3, Tier 4 and Tier 5 (34 rows beyond Tier 2
--      on 9 Oct), though commission is paid on 2 tiers. It listed deleted
--      customers as referrers, and its spend did not take refunds off.
--   3. AFFILIATES-4. The portal Dashboard's Recent Activity listed every
--      purchase (25 for the busiest affiliate), not the last 10, and read the
--      purchases twice.
--   4. AFFILIATES-11. The portal's payout list sent each payout's reference,
--      payment method and internal notes to the affiliate's browser. The
--      portal never showed them. (21 payouts, none with notes yet.)
--   5. AFFILIATES-12. Through a referral link (/r/:code), someone with an
--      existing customer's phone and a differently written name got a new
--      customer record. As a new record with no purchases, they counted as a
--      new friend in a referral promotion, so a past customer could slip in
--      under a new spelling. A link had no limit on sign-ups.
--   6. AFFILIATES-15. The legacy tables affiliates and affiliate_commissions
--      (both empty, read by nothing) and create_commission_payout (it only
--      said the screen needs an update) were still there. The portal's
--      earnings built a by_customer list, reading each customer's spend one
--      by one, that the portal never showed.
--   7. AFFILIATES-M2 (server part). A change of commission rates was audited
--      without the rates before it.
--   8. AFFILIATES-10 (server part). affiliate_staff_directory checked only
--      that the profile is active, not 406's accepted invitation.
--
-- THE RULES
--
--   * The downline is Tier 1 and Tier 2, the levels that earn commission (the
--     Owner, 6 Oct 2026).
--   * Q19 = A (the Owner, 9 Oct 2026): a referral sign-up with an existing
--     customer's phone but a different name is not counted automatically. It
--     is flagged for staff to confirm, then counted.
--   * Same person or not is 432's rule (16 Oct 2026), not a new one: the same
--     words in any order, words written together or apart, a note in
--     brackets left out (customer_names_match).
--   * Affiliates are not subject to staff rules (the Owner, 9 Oct 2026).
--   * 414 is live: deductions marked as settled count as recovered.
--
-- WHAT THIS DOES
--
--   1. One pass (AFFILIATES-5). commission_reporting_rows adds up the
--      allocations once for all commissions. affiliate_admin_directory,
--      affiliate_directory, report_affiliates and referrer_list each read
--      commission_reporting_rows once, grouped by referrer, the balances once
--      (affiliate_referrer_balances, whose owed is the sum of
--      affiliate_month_balances they used to add up per row), and the
--      referral counts once, grouped. Every column, key and figure is as
--      before; ties in a name are now ordered by id.
--   2. Two tiers (AFFILIATES-13). referrer_downline stops at Tier 2, and each
--      paid invoice's spend is less what was refunded on it. referrer_list
--      counts the same two levels as its downline. A deleted referrer is left
--      out, unless they are still owed money or still owe some back.
--   3. Recent Activity (AFFILIATES-4). affiliate_portal_dashboard reads the
--      earnings once and takes the 10 newest of its purchases.
--   4. The portal keeps staff notes (AFFILIATES-11). affiliate_portal_payouts
--      no longer returns reference, method or notes.
--   5. Shared phone (AFFILIATES-12).
--      * affiliate_referral_signup: when no customer with the phone has the
--        name exactly as typed, one with the same words is the same person:
--        "already registered", nothing made. When the phone belongs to a
--        customer in use under another name, the record is still made (it
--        may be a family member), the event is 'phone_shared', and a pending
--        check is saved in the new table referral_signup_checks with the
--        customers who had the phone. What the person sees is unchanged, so
--        the form does not tell anyone whose phone it is.
--        A customer whose phone is stored as 8 digits that could be Singapore
--        or Malaysia has the phone when it could be this one (as
--        require_resolved_customer_identity already does; 46 such customers in
--        production on 18 Oct 2026).
--      * At most 20 new customers through one link in an hour, counted from
--        referral_signup_events by the link's owner, so spaces typed around
--        the code do not start a new count. A lock on the link makes two
--        sign-ups at once wait for each other (always after the phone's lock).
--        The next is told to try later ('link_limit'). Each event keeps the
--        code as the link reads it (spaces trimmed).
--      * referral_campaign_friends: a friend with a pending check is listed,
--        not counted; one checked as the same person is neither counted nor
--        listed; one checked as a different person counts as before.
--        referral_campaign_report marks each such friend needs_check and
--        gives each referrer waiting_check.
--      * New, for an Owner or a Manager (the Affiliates page):
--        referral_signup_checks_pending() lists the pending checks, and
--        decide_referral_signup_check(id, 'different_person' or
--        'same_person', note) records the answer, with a note, in the Audit
--        Log. A check already answered is left as it is.
--   6. Clean-up (AFFILIATES-15). The by_customer list is gone from
--      affiliate_portal_earnings, which now reads its rows once.
--      create_commission_payout and the empty legacy tables affiliate_commissions
--      and affiliates are dropped (424 dropped product_exchanges.affiliate_id,
--      their last link).
--   7. set_commission_rates also audits the rates before the change, and
--      starts with require_active_staff().
--   8. affiliate_staff_directory, referrer_list and report_affiliates start
--      with require_active_staff() (406: an accepted invitation). The last two
--      become plpgsql for it; their rows are as before, and a login that is not
--      active staff is now refused instead of getting no rows.
--      affiliate_admin_directory, referrer_downline and
--      referral_campaign_report call it after their own check, on purpose, so
--      the refusals they give a staff or affiliate login are as before.
--   9. merge_customer_records leaves a referral sign-up check with the record
--      it was made for, as it leaves a phone-review capture (362). The
--      retired record keeps it, so it no longer counts or waits; the kept
--      customer keeps their own check, or none. Moving it would put the kept
--      customer out of their own referrer's promotion (or make them wait for a
--      check), and merging two records that both have a check would fail on
--      the one-check-per-customer key. The foreign key stays, so deleting a
--      customer still deletes their check.
--
-- NOT CHANGED
--
--   * affiliate_month_balances and affiliate_referrer_balances (418 and 427
--     guard them), every commission rule, payouts, settlements and the
--     portal's figures.
--   * Who may call what. Every changed function keeps its grants; the two new
--     ones are for signed-in staff, and refuse anyone but an active Owner or
--     Manager.
--   * Customers already made through a link before this. The 2 that share an
--     older customer's phone under another name (production, 18 Oct 2026; 1
--     listed in a promotion, none counted) are flagged only by the separate
--     script scripts/referrals/repair-425-flag-shared-phone-signups.sql, run
--     with the Owner's sign-off.
--   * "Same person" does not merge the two records; merging stays a separate
--     step. Everything else merge_customer_records moves, keeps or refuses is
--     as before.
--   * The commission side of a shared-phone sign-up (Q19 was about counting
--     in a referral promotion).
--   * suspend_affiliate and reassign_customer_referrer (the page now asks for
--     the reason and shows the current referrer).
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. Every
--   check comes before anything is changed:
--   * 424 must be in (product_exchanges.affiliate_id gone).
--   * Each changed function must be the version read from production on 18
--     Oct 2026 (BEFORE) or already this one (AFTER, left alone), and each new
--     one missing or already this one. No other function may take any of
--     these names. Each text is checked against its AFTER md5 before it is
--     installed.
--   * The functions relied on and not changed must be as read that day.
--   * referral_signup_checks must be missing or exactly this shape.
--   * create_commission_payout must be the version read that day, or gone.
--     Each legacy table must be empty, and nothing but the other may point at
--     it or read it (no foreign key, view or function), or it must be gone.
--   Afterwards every function has its AFTER md5, the changed ones keep their
--   grants, the new ones are callable by signed-in logins and not by anon,
--   the new table is closed to anon and signed-in logins (row-level security,
--   no grant; only these functions reach it), and the legacy objects are
--   gone. A second run changes nothing.
--
-- BEFORE (production, 18 Oct 2026, head 20261016064105; md5 of
-- pg_get_functiondef with search_path public):
--   changed
--   commission_reporting_rows()                                   96962fa272f3eb35111c6ac199255410
--   affiliate_admin_directory()                                   f3cd99cefb5931b0266d1fba6fde53b3
--   affiliate_directory()                                         308a1721fce357e9aede2d4d9b06a6af
--   report_affiliates()                                           84aa4032d794ecdd58e1ec4ae9b9adbc
--   referrer_list()                                               c2596f5b32f26ae4c9f737b9e0320a09
--   referrer_downline(uuid)                                       e471bc0a0107bc1f70e8c01eea2e74d8
--   affiliate_portal_dashboard()                                  5414c7e3c0727f80548eb1e6ae674604
--   affiliate_portal_earnings()                                   adc91a9be47aff2d0c1bc60eb4834cef
--   affiliate_portal_payouts()                                    f9de582ac38238ae5f71eb66dbfcab18
--   set_commission_rates(numeric,numeric,numeric,numeric)         f95afd05da9bb6581eae7f2f35024570
--   affiliate_staff_directory(text,integer,integer)               3e762a7fbcbcba2964475514690d5650
--   affiliate_referral_signup(text,text,text,text,text,text)      5b8363a3f87a4c89f2866f3ba0f32b55
--   referral_campaign_friends(uuid)                               1e1b7dd4fca94364b1c840915c1f61db
--   referral_campaign_report(text)                                d09b6aa2147125d9d4571de774fa1bcf
--   merge_customer_records(uuid,uuid,text,uuid)                   a09b99d88585b5b3ab68f081fcdf01c8
--   dropped
--   create_commission_payout(uuid,date,uuid,text,text)            7cf61414f6bda12f87a24c0df27bf50e
--   relied on, not changed
--   customer_names_match(text,text)                              ef1af52e4888cefb6037a2291f4e011d  (432's AFTER)
--   normalize_customer_phone(text)                               b2bfac910e0c9eff402ba44e19750bee
--   customer_phone_name_matches(text,text)                       1bdf8322972b6671b7cbb08bc8211f8a
--   require_resolved_customer_identity(text,text)                5bde1a418363442ec27e2944442f5874
--   require_active_staff(text[])                                 877b3aa74cea559881979bb161c450e2  (406's AFTER)
--   is_owner_or_manager()                                        125dec10ce33b84ff5fb40a9bd455235
--   affiliate_payout_access(boolean)                             90b7399378a7604afd4af97c059d0703
--   affiliate_referrer_balances()                                54ef098ba8f9e3d81bb45906c4607ab6  (410's AFTER)
--   affiliate_month_balances()                                   84c0741e983c8f483d677353c732d891  (414's AFTER)
--   affiliate_portal_purchases()                                 a5e5c99ae092d2fbea35f3f7d8dc90f0
--   current_affiliate_customer_id()                              51695acf5f26ce3918d6003d0c980b0f
--   customer_affiliate_state(uuid)                               887d0b58f4d1f6670adbaf10591e0f9c
--   inspect_customer_phone(text,text)                            6672c4d1963996f3b601896f4a55916e
--   public function fingerprint (production, 18 Oct 2026)         ff637c8e7adc37a4892a6bf361290c4b
-- AFTER (for later guards):
--   commission_reporting_rows()                                  cfbc75b5eef6697c3716fefe2ee7577e
--   affiliate_admin_directory()                                  0b796c740e42a6f76fc36f0d9a5b6fb4
--   affiliate_directory()                                        dc1f5c1aeb0e9fc3ad88bc41847fc643
--   report_affiliates()                                          6528401b1a0b1555705fad846c6a83b8
--   referrer_list()                                              ec398b2bcf22a7a987623cd6be4f5d5e
--   referrer_downline(uuid)                                      a48f44ea378f05c79bf78dd4c8a71b3c
--   affiliate_portal_dashboard()                                 c2b341ff3f06f4b59111d7d7c4e72c5b
--   affiliate_portal_earnings()                                  b3db0cbb15706d57b0b4726406a176b7
--   affiliate_portal_payouts()                                   4d0a55938ac39876c1a9cd94d4673991
--   set_commission_rates(numeric,numeric,numeric,numeric)        ce795196aaf6fadb1bfca52e2cafaa88
--   affiliate_staff_directory(text,integer,integer)              1db82f16aa93d1e2f967be0be3be62db
--   affiliate_referral_signup(text,text,text,text,text,text)     35def9a1a663d6180d15ab8ea049de35
--   referral_campaign_friends(uuid)                              b5f4f76d7d22369ee4706a4b5f9dd465
--   referral_campaign_report(text)                               018b34673b2f32fd146d8d5e9c791d1a
--   referral_signup_checks_pending()                             25f52c94f9fe27d14c1289e0c7c79410  (new)
--   decide_referral_signup_check(uuid,text,text)                 9d6fe2fd52a16a845d776b06caca0063  (new)
--   merge_customer_records(uuid,uuid,text,uuid)                  099ecf3aae30b5faaf8fb36bc15ce888
--   public function fingerprint, worked out on a copy of production (18 Oct 2026):
--     after 424 then 425 on production as it is now               35ff98e28f7f69b8b932fa12f0069ae2  (1248 functions)
--     after the planned order 418, 420, 431, 429, 417, 422, 423,
--     424 (acff03f9...), then 425                                   a723e64ee0a9891f16c1e87d4302baa7
--     and then 427                                                   34f4b08483b86ac0b55f425e976f58cd
--
-- DEPLOY ORDER
--
--   After 424 (B10), which drops product_exchanges.affiliate_id; this refuses
--   to run before it. Independent of 417-423, 427, 429 and 431 (none changes
--   a function this guards; 418 and 427 guard affiliate_month_balances and
--   affiliate_referrer_balances, which this leaves alone). Before 430 (B17).
--   The pages (CommissionsPage, AffiliatesPage, the portal pages,
--   ReferralSignupPage, ReferralPromotionPanel, AffiliatePayoutPanel) work
--   with or without 425: before it the Affiliates page hides the "Check these
--   sign-ups" list, and the old pages read no key this removes. Push them
--   straight after 425.
--   Once 425 is in, 392 and 414 cannot be run again (they guard
--   affiliate_referral_signup, report_affiliates and affiliate_portal_earnings
--   at their own AFTER md5s), as with 398, 404 and 409 before. So
--   scripts/commissions/tests/deduction-settlement.sql, which installs 414
--   itself, runs only on a database before 425;
--   scripts/affiliate-signup/tests/booking-label.sql skips 392 once 425 is in.
--   merge_customer_records: no built migration (417-431) changes it (checked
--   18 Oct 2026); 398 records it at a09b99d8... and already cannot be run
--   again. A later change to it must start from this AFTER md5.
--   Website seminar orders (rev22-energia-seminar, src/lib/referrals.ts) call
--   affiliate_referral_signup with the anon key, so the same limit applies:
--   above 20 new customers through one link in an hour, the website's
--   Referrals tab lists the guest as "Not added" with this message, and staff
--   add them under the affiliate by hand. Wording for it on the website is a
--   separate deploy there.
--
-- Test: scripts/commissions/tests/affiliates-425.sql and
-- scripts/affiliate-signup/tests/shared-phone-425.sql (begin ... rollback,
-- run with -v mig=<this file>; each installs it twice).

set lock_timeout = '5s';

do $mig$
declare
  -- The functions this installs, in order: signature, BEFORE md5 (null: new),
  -- AFTER md5, and the text (as pg_get_functiondef gives it back).
  c_sig constant text[] := array['commission_reporting_rows()',
    'affiliate_admin_directory()',
    'affiliate_directory()',
    'report_affiliates()',
    'referrer_list()',
    'referrer_downline(uuid)',
    'affiliate_portal_dashboard()',
    'affiliate_portal_earnings()',
    'affiliate_portal_payouts()',
    'set_commission_rates(numeric,numeric,numeric,numeric)',
    'affiliate_staff_directory(text,integer,integer)',
    'affiliate_referral_signup(text,text,text,text,text,text)',
    'referral_campaign_friends(uuid)',
    'referral_campaign_report(text)',
    'referral_signup_checks_pending()',
    'decide_referral_signup_check(uuid,text,text)',
    'merge_customer_records(uuid,uuid,text,uuid)'];
  c_before constant text[] := array['96962fa272f3eb35111c6ac199255410',
    'f3cd99cefb5931b0266d1fba6fde53b3',
    '308a1721fce357e9aede2d4d9b06a6af',
    '84aa4032d794ecdd58e1ec4ae9b9adbc',
    'c2596f5b32f26ae4c9f737b9e0320a09',
    'e471bc0a0107bc1f70e8c01eea2e74d8',
    '5414c7e3c0727f80548eb1e6ae674604',
    'adc91a9be47aff2d0c1bc60eb4834cef',
    'f9de582ac38238ae5f71eb66dbfcab18',
    'f95afd05da9bb6581eae7f2f35024570',
    '3e762a7fbcbcba2964475514690d5650',
    '5b8363a3f87a4c89f2866f3ba0f32b55',
    '1e1b7dd4fca94364b1c840915c1f61db',
    'd09b6aa2147125d9d4571de774fa1bcf',
    null,
    null,
    'a09b99d88585b5b3ab68f081fcdf01c8'];
  c_after constant text[] := array['cfbc75b5eef6697c3716fefe2ee7577e',
    '0b796c740e42a6f76fc36f0d9a5b6fb4',
    'dc1f5c1aeb0e9fc3ad88bc41847fc643',
    '6528401b1a0b1555705fad846c6a83b8',
    'ec398b2bcf22a7a987623cd6be4f5d5e',
    'a48f44ea378f05c79bf78dd4c8a71b3c',
    'c2b341ff3f06f4b59111d7d7c4e72c5b',
    'b3db0cbb15706d57b0b4726406a176b7',
    '4d0a55938ac39876c1a9cd94d4673991',
    'ce795196aaf6fadb1bfca52e2cafaa88',
    '1db82f16aa93d1e2f967be0be3be62db',
    '35def9a1a663d6180d15ab8ea049de35',
    'b5f4f76d7d22369ee4706a4b5f9dd465',
    '018b34673b2f32fd146d8d5e9c791d1a',
    '25f52c94f9fe27d14c1289e0c7c79410',
    '9d6fe2fd52a16a845d776b06caca0063',
    '099ecf3aae30b5faaf8fb36bc15ce888'];
  c_def constant text[] := array[
$def$CREATE OR REPLACE FUNCTION public.commission_reporting_rows()
 RETURNS SETOF commissions
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 -- 425: what was paid out of each commission is added up in one pass over
 -- the allocations, not once for each commission. The rows are as before.
 with al as(select a.commission_id,sum(a.amount) amount from public.commission_payout_allocations a group by a.commission_id),
 c as(select c.*,coalesce(al.amount,
  case when c.status='paid' then c.commission_amount else 0 end) paid_amount from public.commissions c left join al on al.commission_id=c.id),
 parts as(select c,to_jsonb(c)-'paid_amount' base,v.amount,v.status from c cross join lateral(
  select c.paid_amount amount,'paid'::text status where c.status in ('paid','earned') and c.paid_amount<>0
  union all select c.commission_amount-c.paid_amount,'earned' where c.status in ('paid','earned') and c.commission_amount<>c.paid_amount
  union all select c.commission_amount,c.status::text where c.status not in ('paid','earned')) v)
 select (jsonb_populate_record(null::public.commissions,base||jsonb_build_object('commission_amount',amount,'status',status,
  'payout_id',case when status='paid' then base->>'payout_id' end))).* from parts
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.affiliate_admin_directory()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_rows jsonb;
begin
  if not public.affiliate_payout_access(true) then raise exception 'Owner or Manager only'; end if;
  perform public.require_active_staff();  -- 425: and an accepted invitation (406)
  -- 425: the commission figures, the balances and the referral counts are
  -- each worked out once for all affiliates, then joined. The page gets the
  -- same keys and figures as before.
  with cm as (
    select r.referrer_customer_id as referrer,
           sum(r.commission_amount) filter (where r.status in ('earned','paid')) as lifetime,
           -- 410: commission withheld is written 'blocked' ('cancelled' kept as before).
           sum(r.commission_amount) filter (where r.status in ('blocked','cancelled')) as blocked,
           max(r.created_at) as last_commission
      from public.commission_reporting_rows() r
     group by r.referrer_customer_id),
  t1 as (
    select x.referred_by as referrer, count(*) as n
      from public.customers x
     where x.referred_by is not null and x.deleted_at is null
     group by x.referred_by),
  t2 as (
    select p.referred_by as referrer, count(*) as n
      from public.customers x join public.customers p on p.id = x.referred_by
     where p.referred_by is not null and x.deleted_at is null and p.deleted_at is null
     group by p.referred_by)
  select coalesce(jsonb_agg(jsonb_build_object(
    'customer_id', ca.customer_id, 'name', c.full_name,
    'status', case when ca.manually_suspended then 'suspended' else ca.status end,
    'manually_suspended', ca.manually_suspended,
    'referral_code', ca.referral_code,
    'portal_account', case when acc.id is null then 'not_claimed'
                           when acc.status = 'disabled' then 'disabled' else 'claimed' end,
    'direct_referrals', coalesce(t1.n, 0),
    'tier2', coalesce(t2.n, 0),
    'lifetime', coalesce(cm.lifetime, 0),
    -- 410: what the affiliate is still owed and what is still to be recovered
    -- from them, their months netted (affiliate_referrer_balances).
    'unpaid', coalesce(rb.unpaid, 0), 'deduction', coalesce(rb.deduction, 0),
    'blocked', coalesce(cm.blocked, 0),
    'last_commission', cm.last_commission
  ) order by c.full_name, ca.customer_id), '[]'::jsonb) into v_rows
  from public.customer_affiliates ca
  join public.customers c on c.id = ca.customer_id
  left join public.affiliate_accounts acc on acc.customer_id = ca.customer_id
  left join public.affiliate_referrer_balances() rb on rb.referrer = ca.customer_id  -- 410
  left join cm on cm.referrer = ca.customer_id
  left join t1 on t1.referrer = ca.customer_id
  left join t2 on t2.referrer = ca.customer_id
  where ca.deleted_at is null;
  return v_rows;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.affiliate_directory()
 RETURNS TABLE(customer_id uuid, full_name text, phone text, member_id text, membership_status text, membership_plan text, membership_expiry date, affiliate_state text, block_reason text, store_id uuid, store_name text, direct_referrals integer, downline integer, lifetime_earned numeric, unpaid_payable numeric, blocked_commission numeric, last_commission_date date, has_profile boolean, manually_suspended boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 425: the commission figures, the balances and the referral counts are
  -- each worked out once for everyone, then joined. The rows are as before.
  with cm as (
    select r.referrer_customer_id as referrer,
           sum(r.commission_amount) filter (where r.status in ('earned','paid')) as lifetime,
           sum(r.commission_amount) filter (where r.status = 'blocked') as blocked,
           max(r.invoice_paid_date) as last_date
      from public.commission_reporting_rows() r
     group by r.referrer_customer_id
  ),
  affs as (
    select c.id as customer_id
    from public.customers c
    where c.deleted_at is null and (
      exists (select 1 from public.customer_affiliates a where a.customer_id = c.id and a.deleted_at is null)
      or exists (select 1 from public.customers r where r.referred_by = c.id)
      or exists (select 1 from cm where cm.referrer = c.id)
    )
  ),
  -- 367: live referred customers only, as referrer_list counts them; a deleted
  -- or merged-away customer is no longer a referral.
  t1 as (
    select x.referred_by as referrer, count(*)::int as n
      from public.customers x
     where x.referred_by is not null and x.deleted_at is null
     group by x.referred_by
  ),
  -- The downline: live Tier 1, and live Tier 2 under a live Tier 1, each
  -- customer once.
  dl as (
    select k.referrer, count(distinct k.id)::int as n
      from (select x.referred_by as referrer, x.id
              from public.customers x
             where x.referred_by is not null and x.deleted_at is null
            union all
            select p.referred_by, x.id
              from public.customers x
              join public.customers p on p.id = x.referred_by and p.deleted_at is null
             where p.referred_by is not null and x.deleted_at is null) k
     group by k.referrer
  )
  select
    c.id, c.full_name, c.phone,
    null::text, null::text, null::text, null::date,
    st->>'state', st->>'block_reason',
    a.store_id, s.name,
    coalesce(t1.n, 0),
    coalesce(dl.n, 0),
    coalesce(cm.lifetime, 0),
    coalesce(rb.owed, 0),
    coalesce(cm.blocked, 0),
    cm.last_date,
    a.id is not null, coalesce(a.manually_suspended,false)
  from affs
  join public.customers c on c.id = affs.customer_id
  left join public.customer_affiliates a on a.customer_id = c.id and a.deleted_at is null
  left join public.stores s on s.id = a.store_id
  left join cm on cm.referrer = c.id
  left join t1 on t1.referrer = c.id
  left join dl on dl.referrer = c.id
  left join public.affiliate_referrer_balances() rb on rb.referrer = c.id
  cross join lateral public.customer_affiliate_state(c.id) st
  where public.affiliate_payout_access()
  order by c.full_name, c.id;
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.report_affiliates()
 RETURNS TABLE(customer_id uuid, customer_name text, member_id text, affiliate_state text, block_reason text, store_name text, direct_referrals integer, downline integer, earned numeric, paid numeric, reversed numeric, blocked numeric, tier1_earned numeric, tier2_earned numeric, settled numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
begin
  perform public.require_active_staff();  -- 425: an accepted invitation (406)
  -- 425: reversed, tier 1, tier 2, payouts and settlements are each added up
  -- once for everyone, then joined. The rows are as before.
  return query
  with cm as (
    select r.referrer_customer_id as referrer,
           sum(r.commission_amount) filter (where r.status = 'reversed') as reversed,
           sum(r.commission_amount) filter (where r.tier = 'tier1' and r.status in ('earned','paid')) as tier1,
           sum(r.commission_amount) filter (where r.tier = 'tier2' and r.status in ('earned','paid')) as tier2
      from public.commission_reporting_rows() r
     group by r.referrer_customer_id
  ),
  po as (
    select p.referrer_customer_id as referrer, sum(p.total_amount) as paid
      from public.commission_payouts p where p.status = 'paid'
     group by p.referrer_customer_id
  ),
  -- 414: deductions settled (paid back, written off, or taken off a payment
  -- outside the app); the Commission tab counts them in Outstanding.
  st as (
    select s.referrer_customer_id as referrer, sum(s.amount) as settled
      from public.affiliate_deduction_settlements s where s.voided_at is null
     group by s.referrer_customer_id
  )
  select
    d.customer_id, d.full_name, d.member_id, d.affiliate_state, d.block_reason,
    d.store_name, d.direct_referrals, d.downline,
    d.lifetime_earned, coalesce(po.paid, 0),
    coalesce(cm.reversed, 0),
    d.blocked_commission,
    coalesce(cm.tier1, 0),
    coalesce(cm.tier2, 0),
    coalesce(st.settled, 0)
  from public.affiliate_directory() d
  left join cm on cm.referrer = d.customer_id
  left join po on po.referrer = d.customer_id
  left join st on st.referrer = d.customer_id
  order by d.full_name, d.customer_id;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.referrer_list()
 RETURNS TABLE(customer_id uuid, full_name text, phone text, direct_referrals integer, total_downline integer, lifetime_earned numeric, unpaid_earned numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
begin
  perform public.require_active_staff();  -- 425: an accepted invitation (406)
  -- 425: every figure is worked out once for all referrers, then joined.
  -- The downline is Tier 1 and Tier 2, the levels that earn commission (the
  -- Owner, 6 Oct 2026), as on the Affiliates page and in Reports. A deleted
  -- referrer is left out, unless they are still owed money or still owe some
  -- back (money is never hidden).
  return query
  with referrers as (
    -- customers who have referred at least one person
    select distinct referred_by as cid from public.customers
    where referred_by is not null
    union
    -- customers who have earned commission
    select distinct referrer_customer_id as cid from public.commissions
  ),
  t1 as (
    select x.referred_by as referrer, count(*) as n
      from public.customers x
     where x.referred_by is not null and x.deleted_at is null
     group by x.referred_by
  ),
  -- The rows referrer_downline gives: live Tier 1, and live Tier 2 under a
  -- live Tier 1.
  dl as (
    select k.referrer, count(*) as n
      from (select x.referred_by as referrer
              from public.customers x
             where x.referred_by is not null and x.deleted_at is null
            union all
            select p.referred_by
              from public.customers x
              join public.customers p on p.id = x.referred_by and p.deleted_at is null
             where p.referred_by is not null and x.deleted_at is null) k
     group by k.referrer
  ),
  cm as (
    select r.referrer_customer_id as referrer,
           sum(r.commission_amount) filter (where r.status in ('earned','paid')) as lifetime
      from public.commission_reporting_rows() r
     group by r.referrer_customer_id
  )
  select
    c.id, c.full_name, c.phone,
    coalesce(t1.n, 0)::integer as direct_referrals,
    coalesce(dl.n, 0)::integer as total_downline,
    coalesce(cm.lifetime, 0) as lifetime_earned,
    coalesce(rb.owed, 0) as unpaid_earned
  from referrers r
  join public.customers c on c.id = r.cid
  left join t1 on t1.referrer = c.id
  left join dl on dl.referrer = c.id
  left join cm on cm.referrer = c.id
  left join public.affiliate_referrer_balances() rb on rb.referrer = c.id
  where public.affiliate_payout_access()
    and (c.deleted_at is null or coalesce(rb.owed, 0) <> 0)
  order by coalesce(cm.lifetime, 0) desc, c.full_name, c.id;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.referrer_downline(p_customer_id uuid)
 RETURNS TABLE(customer_id uuid, full_name text, phone text, referred_by uuid, depth integer, paid_purchases integer, total_spend numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
-- 398: the Commissions page's Referrers tab, the same rows as before, now
-- only for an Owner, a Manager or an Admin (affiliate_payout_access(), as
-- referrer_earnings beside it). It was granted to every signed-in login,
-- affiliate portal logins included, and checked nothing.
-- 425: Tier 1 and Tier 2 only, the levels that earn commission (the Owner,
-- 6 Oct 2026); it used to follow the chain 50 levels down. The spend of
-- each paid invoice is less what was refunded on it.
begin
  if not public.affiliate_payout_access() then
    raise exception 'Commission access denied' using errcode = '42501'; end if;
  perform public.require_active_staff();  -- 425: and an accepted invitation (406)
  return query
  with recursive tree as (
    select c.id, c.full_name, c.phone, c.referred_by, 1 as depth
    from public.customers c
    where c.referred_by = p_customer_id and c.deleted_at is null
    union all
    select c.id, c.full_name, c.phone, c.referred_by, t.depth + 1
    from public.customers c
    join tree t on c.referred_by = t.id
    where c.deleted_at is null and t.depth < 2   -- 425: Tier 2 is the last level
  )
  select
    t.id, t.full_name, t.phone, t.referred_by, t.depth,
    coalesce(inv.cnt, 0)::integer as paid_purchases,
    coalesce(inv.spend, 0)::numeric as total_spend
  from tree t
  left join lateral (
    select count(*) as cnt,
           sum(i.total_amount - coalesce((select sum(r.amount) from public.invoice_refunds r
                                           where r.invoice_id = i.id), 0)) as spend
    from public.invoices i
    where i.customer_id = t.id and i.status = 'paid' and i.deleted_at is null
  ) inv on true
  order by t.depth, t.full_name;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.affiliate_portal_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_me uuid := public.current_affiliate_customer_id();
        v_t1 int; v_t2 int; v_earn jsonb; v_recent jsonb;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;
  select count(*) into v_t1 from public.customers where referred_by = v_me and deleted_at is null;
  select count(*) into v_t2 from public.customers c join public.customers p on p.id = c.referred_by
    where p.referred_by = v_me and c.deleted_at is null and p.deleted_at is null;
  v_earn := public.affiliate_portal_earnings();
  -- 425: Recent Activity is the 10 newest purchases. They come from the
  -- purchases the earnings above already read, so they are read once. The
  -- limit used to apply to the one row of the list, so every purchase came.
  select coalesce(jsonb_agg(x.e order by (x.e->>'purchase_date') desc, x.n), '[]'::jsonb)
    into v_recent
    from (select t.e, t.n
            from jsonb_array_elements(coalesce(v_earn->'by_purchase', '[]'::jsonb)) with ordinality as t(e, n)
           order by (t.e->>'purchase_date') desc, t.n
           limit 10) x;
  return jsonb_build_object(
    'network', jsonb_build_object('tier1', v_t1, 'tier2', v_t2, 'total', v_t1 + v_t2),
    'earnings', v_earn->'summary', 'by_tier', v_earn->'by_tier', 'recent', v_recent);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.affiliate_portal_earnings()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_me uuid := public.current_affiliate_customer_id();
        v_unpaid numeric; v_paid numeric; v_reversed numeric; v_blocked numeric; v_lifetime numeric;
        v_settled numeric;  -- 414: deductions settled
        v_t1 numeric; v_t2 numeric; v_by_month jsonb; v_by_purchase jsonb;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;

  -- 425: the affiliate's commission rows are read once, for the totals and
  -- the months together. by_customer is gone: the portal never showed it,
  -- and it read each customer's spend one by one.
  with r as materialized (
    select commission_amount, status, tier, invoice_paid_date, created_at
      from public.commission_reporting_rows() where referrer_customer_id = v_me
  )
  select
    coalesce(sum(commission_amount) filter (where status='earned'),0),
    coalesce(sum(commission_amount) filter (where status='paid'),0),
    coalesce(sum(commission_amount) filter (where status='reversed'),0),
    coalesce(sum(commission_amount) filter (where status in ('blocked','cancelled')),0),  -- 410: withheld is 'blocked'
    coalesce(sum(commission_amount) filter (where status='paid' and tier='tier1'),0)
           + coalesce(sum(commission_amount) filter (where status='earned' and tier='tier1'),0),
    coalesce(sum(commission_amount) filter (where status='paid' and tier='tier2'),0)
           + coalesce(sum(commission_amount) filter (where status='earned' and tier='tier2'),0),
    (select coalesce(jsonb_agg(jsonb_build_object('month', m, 'tier1', t1, 'tier2', t2, 'total', t1+t2) order by m desc),'[]'::jsonb)
       from (select to_char(date_trunc('month', coalesce(r2.invoice_paid_date, r2.created_at::date)),'YYYY-MM') as m,
                    coalesce(sum(r2.commission_amount) filter (where r2.tier='tier1' and r2.status in ('earned','paid')),0) as t1,
                    coalesce(sum(r2.commission_amount) filter (where r2.tier='tier2' and r2.status in ('earned','paid')),0) as t2
               from r r2 group by 1) mm)
    into v_unpaid, v_paid, v_reversed, v_blocked, v_t1, v_t2, v_by_month
  from r;
  v_lifetime := v_unpaid + v_paid;
  select coalesce(sum(total_amount),0) into v_paid from public.commission_payouts where referrer_customer_id=v_me and status='paid';
  -- 414: a deduction settled (paid back, written off, or taken off a payment
  -- outside the app) is recovered; a settlement voided is not.
  select coalesce(sum(s.amount),0) into v_settled from public.affiliate_deduction_settlements s
   where s.referrer_customer_id=v_me and s.voided_at is null;
  v_unpaid:=v_lifetime-v_paid+v_settled;

  v_by_purchase := public.affiliate_portal_purchases();

  return jsonb_build_object(
    -- 410: never a negative Unpaid; what is still to be recovered from the
    -- affiliate (commission paid out and then taken back) is the deduction.
    'summary', jsonb_build_object('lifetime', v_lifetime, 'unpaid', greatest(v_unpaid, 0),
      'deduction', greatest(-v_unpaid, 0), 'paid', v_paid,
      'settled', v_settled,  -- 414: the amount only, never the note or how
      'reversed', v_reversed, 'blocked', v_blocked),
    'by_tier', jsonb_build_object('tier1', v_t1, 'tier2', v_t2),
    'by_month', v_by_month, 'by_purchase', v_by_purchase);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.affiliate_portal_payouts()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_me uuid := public.current_affiliate_customer_id(); v_rows jsonb;
begin
  if v_me is null then raise exception 'Not an affiliate account'; end if;
  -- 425: the payout's reference, payment method and notes stay with staff.
  -- The portal never showed them, and the notes are internal.
  select coalesce(jsonb_agg(jsonb_build_object(
           'payout_month', to_char(payout_month,'YYYY-MM'),
           'tier1', total_tier1, 'tier2', total_tier2, 'total', total_amount,
           'paid_date', payment_date, 'status', status) order by payout_month desc), '[]'::jsonb)
    into v_rows from public.commission_payouts where referrer_customer_id = v_me;
  return v_rows;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.set_commission_rates(p_tier1_own numeric, p_tier1_third numeric, p_tier2_own numeric, p_tier2_third numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_old jsonb;
begin
  perform public.require_active_staff();  -- 425: active, accepted staff only
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit commission rates'; end if;
  if p_tier1_own   is null or p_tier1_own   < 0 or p_tier1_own   > 100 then raise exception 'Tier 1 Own rate must be between 0 and 100'; end if;
  if p_tier1_third is null or p_tier1_third < 0 or p_tier1_third > 100 then raise exception 'Tier 1 Third-party rate must be between 0 and 100'; end if;
  if p_tier2_own   is null or p_tier2_own   < 0 or p_tier2_own   > 100 then raise exception 'Tier 2 Own rate must be between 0 and 100'; end if;
  if p_tier2_third is null or p_tier2_third < 0 or p_tier2_third > 100 then raise exception 'Tier 2 Third-party rate must be between 0 and 100'; end if;
  -- 425: the rates before the change go into the Audit Log too.
  select jsonb_build_object('tier1_own', commission_tier1_own_rate, 'tier1_third', commission_tier1_third_rate,
                            'tier2_own', commission_tier2_own_rate, 'tier2_third', commission_tier2_third_rate)
    into v_old
    from public.app_settings where id = true for update;
  update public.app_settings
     set commission_tier1_own_rate = p_tier1_own,
         commission_tier1_third_rate = p_tier1_third,
         commission_tier2_own_rate = p_tier2_own,
         commission_tier2_third_rate = p_tier2_third,
         updated_at = now()
   where id = true;
  perform public.write_audit('app_settings', null, 'commission_rates_set', v_old,
    jsonb_build_object('tier1_own', p_tier1_own, 'tier1_third', p_tier1_third,
                       'tier2_own', p_tier2_own, 'tier2_third', p_tier2_third));
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.affiliate_staff_directory(p_search text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_q text := nullif(btrim(coalesce(p_search, '')), '');
  v_limit int := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
  v_rows jsonb; v_total bigint;
begin
  -- 425: active, accepted staff only (406's check, which also turns away a
  -- login whose invitation is not accepted yet).
  perform public.require_active_staff();
  -- An active staff login of any role. Not a public endpoint.
  if auth.uid() is null or not exists (
       select 1 from public.profiles p where p.id = auth.uid() and p.is_active and p.deleted_at is null) then
    raise exception 'Sign in to view the affiliate directory' using errcode = '42501';
  end if;

  with matched as (
    select ca.customer_id, c.full_name, ca.referral_code,
           case when ca.manually_suspended then 'suspended' else ca.status end as status,
           -- The same rule public_affiliate_referral_info applies when a
           -- customer opens the link: usable means it will register a referral.
           (ca.referral_code is not null and not ca.manually_suspended and ca.status = 'active') as link_usable
      from public.customer_affiliates ca
      join public.customers c on c.id = ca.customer_id and c.deleted_at is null
     where ca.deleted_at is null
       and (v_q is null or c.full_name ilike '%' || v_q || '%' or ca.referral_code ilike '%' || v_q || '%')
  )
  select count(*),
         coalesce((select jsonb_agg(to_jsonb(o)) from (
            select * from matched order by full_name, customer_id offset v_offset limit v_limit) o), '[]'::jsonb)
    into v_total, v_rows
    from matched;

  return jsonb_build_object('rows', v_rows, 'total', v_total, 'limit', v_limit, 'offset', v_offset);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.affiliate_referral_signup(p_code text, p_first_name text, p_last_name text, p_phone text, p_email text, p_honeypot text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ca public.customer_affiliates%rowtype; v_ref_cust uuid; v_phone text; v_norm text; v_email text;
  v_name text; v_new uuid; v_recent int; v_matches uuid[];
  v_holders uuid[];  -- 425: the customers in use who have this phone already
begin
  if coalesce(btrim(p_honeypot),'') <> '' then
    insert into public.referral_signup_events(referral_code, outcome) values (btrim(p_code), 'honeypot');
    return jsonb_build_object('ok', true, 'outcome', 'registered');
  end if;

  v_phone := regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g');
  v_norm  := public.normalize_customer_phone(p_phone);
  v_email := nullif(lower(btrim(coalesce(p_email,''))), '');
  v_name := btrim(coalesce(p_first_name,'') || ' ' || coalesce(p_last_name,''));
  if v_norm is null then raise exception 'CUSTOMER_PHONE_REVIEW: Enter a valid international phone number.'; end if;
  if v_name = '' then raise exception 'Please enter your name'; end if;
  perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || v_norm,0));


  select * into v_ca from public.customer_affiliates where referral_code = btrim(p_code) and deleted_at is null;
  if not found or v_ca.manually_suspended or v_ca.status <> 'active' then
    insert into public.referral_signup_events(referral_code, normalized_phone, outcome) values (btrim(p_code), v_norm, 'rejected');
    return jsonb_build_object('ok', false,
      'message', 'This referral link is not accepting new registrations right now. Please contact Energia.');
  end if;
  v_ref_cust := v_ca.customer_id;

  perform public.require_resolved_customer_identity(v_norm,v_name);
  v_matches := public.customer_phone_name_matches(v_norm,v_name);
  if cardinality(v_matches) > 1 then raise exception 'AMBIGUOUS_CUSTOMER_MATCH'; end if;
  -- 425: the customers in use who have this phone already. A phone stored as
  -- 8 digits that could be Singapore or Malaysia counts when it could be this
  -- one (as in require_resolved_customer_identity); only a phone of digits
  -- and separators can be one, so the others are not inspected.
  select coalesce(array_agg(x.id order by x.created_at, x.id), '{}'::uuid[]) into v_holders
    from (select c.id, c.created_at from public.customers c
           where c.deleted_at is null and public.normalize_customer_phone(c.phone) = v_norm
          union
          select c.id, c.created_at from public.customers c
           where c.deleted_at is null and public.normalize_customer_phone(c.phone) is null
             and c.phone ~ '^[\s().0-9-]+$'
             and (public.inspect_customer_phone(c.phone)->'candidates') ? v_norm) x;
  -- 425: no customer with this phone has the name exactly as typed. One
  -- whose name has the same words (432's rule: any order, words written
  -- together or apart, a note in brackets left out) is the same person too.
  if cardinality(v_matches) = 0 then
    select coalesce(array_agg(c.id order by c.id), '{}'::uuid[]) into v_matches
      from public.customers c
     where c.id = any (v_holders) and public.customer_names_match(c.full_name, v_name);
  end if;
  -- A shared household phone alone does not identify the referrer. Check the
  -- uniquely matched customer ID only after ambiguity has been ruled out.
  if v_ref_cust = any (v_matches) then
    return jsonb_build_object('ok',false,'message','You cannot refer yourself.');
  end if;

  -- Existing identity: never change referral ownership from an anonymous form.
  if cardinality(v_matches) >= 1 then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome)
      values (btrim(p_code), v_ref_cust, v_norm, 'duplicate');
    return jsonb_build_object('ok', true, 'outcome', 'already_registered',
      'message', 'This phone number is already registered with Energia, so no new registration was created. Nothing about your existing record has changed.');
  end if;

  if (select used from public.customer_phone_capacity where phone=v_norm) >= 3 then
    raise exception 'CUSTOMER_PHONE_LIMIT: This phone number already belongs to 3 non-deleted customers across Energia. Enter a different valid number.';
  end if;
  select count(*) into v_recent from public.referral_signup_events
   where normalized_phone=v_norm and created_at > now()-interval '10 minutes';
  if v_recent >= 3 then
    return jsonb_build_object('ok',false,'message','Too many registration attempts for this phone number. Please wait 10 minutes or contact Energia.');
  end if;
  -- 425: at most 20 new customers through one link in an hour, counted by
  -- the link's owner (however the code was typed). The lock makes two
  -- sign-ups through the link wait for each other (always after the phone's
  -- lock, so they cannot deadlock).
  perform pg_advisory_xact_lock(hashtextextended('referral-link:' || v_ref_cust::text, 0));
  if (select count(*) from public.referral_signup_events e
       where e.referrer_customer_id = v_ref_cust and e.outcome in ('created', 'phone_shared')
         and e.created_at > now() - interval '1 hour') >= 20 then
    insert into public.referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome)
      values (btrim(p_code), v_ref_cust, v_norm, 'link_limit');
    return jsonb_build_object('ok', false, 'message',
      'This referral link has had many registrations in the last hour. Please try again later or contact Energia.');
  end if;

  -- 425: the phone belongs to a customer in use under another name
  -- (v_holders). It may be a family member or the same person. The record is
  -- made, and staff check it before the friend counts for a referral
  -- promotion (the Owner, Q19 = A, 9 Oct 2026).
  insert into public.customers (full_name, phone, email, is_active, referred_by,
      referred_at, referral_source, referral_code_used)
    values (v_name, coalesce(v_norm, v_phone), v_email, true, v_ref_cust, now(), 'affiliate_link', btrim(p_code))
    returning id into v_new;

  insert into public.referral_signup_events(referral_code, referrer_customer_id, new_customer_id, normalized_phone, outcome)
    values (btrim(p_code), v_ref_cust, v_new, v_norm, case when cardinality(v_holders) > 0 then 'phone_shared' else 'created' end);
  if cardinality(v_holders) > 0 then
    insert into public.referral_signup_checks(customer_id, referrer_customer_id, referral_code, normalized_phone, phone_shared_with)
      values (v_new, v_ref_cust, btrim(p_code), v_norm, v_holders);
  end if;

  begin
    perform public.write_audit_ex('customers', v_new, 'referral_registered', null,
      jsonb_build_object('referred_by', v_ref_cust, 'referral_code', btrim(p_code), 'source', 'affiliate_link')
        || case when cardinality(v_holders) > 0 then jsonb_build_object('phone_shared_with', to_jsonb(v_holders)) else '{}'::jsonb end,
      'affiliate', null, null);
  exception when others then null; end;

  -- 392: the outcome, as 319 meant, and the referrer as a booking prints
  -- them, which the referral page passes on to the booking page.
  return jsonb_build_object('ok', true, 'outcome', 'registered',
    'message', 'Registration successful.',
    'affiliate_label', (select public.affiliate_calendar_label(c.full_name)
                          from public.customers c
                         where c.id = v_ref_cust and c.deleted_at is null));
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.referral_campaign_friends(p_campaign_id uuid)
 RETURNS TABLE(referrer_customer_id uuid, friend_customer_id uuid, referred_on date, first_visit_on date, counted boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 404: a referral promotion's counting (the Owner, 8 Oct 2026), the only
  -- place it is written. A Tier 1 friend (customers.referred_by, the
  -- referrer not deleted) counts for their referrer when their first visit
  -- for the promotion (below) is in the window, whenever they were referred,
  -- as long as the referral was recorded by the window's last day: a
  -- referrer set after the window does not raise its count. The referral's
  -- date is the Singapore date of referred_at, else of created_at for older
  -- links without a date. The rows are the friends who count and, not
  -- counted, the friends referred in the window who have not visited yet (no
  -- visit at all). Nobody else is listed: not a friend whose first visit is
  -- before the window or after it, nor one referred after it. A Tier 2
  -- friend is nobody's Tier 1 here and counts for no one but their own
  -- referrer. (398 counted only friends referred in the window and listed
  -- every one of them.)
  -- A past customer is neither counted nor listed: a friend with an invoice,
  -- not deleted, whose status shows money was taken (paid or
  -- partially_paid) and whose business date, else the Singapore date it was
  -- created, is before the window's first day. Cancelled, refunded, unpaid,
  -- draft and FOC invoices, and a request to cancel or refund, do not make a
  -- past customer.
  -- The first visit for the promotion is the earliest of the friend's visits
  -- (customer_centre_visit_days, the visit rule), each on its own date,
  -- except that a visit through the centre's own link counts on the
  -- Singapore day the form was sent, never the date typed on it. It can
  -- differ from the first visit the Customers page shows
  -- (customer_centre_visits), which keeps the date on the form.
  -- 425: a friend who signed up through a link with the phone of a customer
  -- already there, under another name, counts only once staff have checked
  -- that they are a different person (the Owner, Q19 = A, 9 Oct 2026). Until
  -- then they are listed, not counted. One found to be the same person is
  -- neither counted nor listed.
  with v as (
    select d.customer_id,
           min(case when d.visit_kind = 'centre_link' then d.sent_on else d.visit_on end) as first_visit_on
      from public.customer_centre_visit_days() d
     group by d.customer_id
  ),
  f as (
    select c.referred_by, c.id,
           (coalesce(c.referred_at, c.created_at) at time zone 'Asia/Singapore')::date as referred_on,
           v.first_visit_on, rc.starts_on, rc.ends_on, chk.status as check_status
      from public.referral_campaigns rc
      join public.customers c on c.deleted_at is null and c.referred_by is not null
      join public.customers r on r.id = c.referred_by and r.deleted_at is null
      left join v on v.customer_id = c.id
      left join public.referral_signup_checks chk on chk.customer_id = c.id
     where rc.id = p_campaign_id
       and chk.status is distinct from 'same_person'
       and not exists (select 1 from public.invoices i
                        where i.customer_id = c.id and i.deleted_at is null
                          and i.status in ('paid', 'partially_paid')
                          and coalesce(i.business_date, (i.created_at at time zone 'Asia/Singapore')::date)
                              < rc.starts_on)
  ),
  k as (
    select f.*, coalesce(f.first_visit_on between f.starts_on and f.ends_on
                         and f.referred_on <= f.ends_on, false) as counts
      from f
  )
  select k.referred_by, k.id, k.referred_on, k.first_visit_on,
         k.counts and k.check_status is distinct from 'pending'
    from k
   where k.counts
      or (k.first_visit_on is null and k.referred_on between k.starts_on and k.ends_on)
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.referral_campaign_report(p_campaign text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 398: a referral promotion's report (the Owner, 6 Oct 2026), Owner/Manager
-- only. p_campaign is a promotion's code; none: the latest that has started
-- (else the first). Every referrer with a friend listed (404: one who
-- counts, or one referred in the window who has not visited yet; see
-- referral_campaign_friends): friends counted, friends not yet visited,
-- tier reached, next tier, the reward if given, and each friend (the
-- drill-down). "provisional" until the window has ended.
-- 425: a friend whose link sign-up shares a customer's phone under another
-- name is not counted until staff check them (referral_campaign_friends).
-- Such a friend has needs_check, and each referrer has waiting_check, the
-- number of their friends waiting for that check.
declare
  rc public.referral_campaigns%rowtype; v_today date := public.sg_today(); v_rows jsonb; v_list jsonb;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can see the referral promotion' using errcode = '42501'; end if;
  perform public.require_active_staff();  -- 425: and an accepted invitation (406)
  if nullif(btrim(coalesce(p_campaign, '')), '') is null then
    select * into rc from public.referral_campaigns where starts_on <= v_today order by starts_on desc limit 1;
    if not found then
      select * into rc from public.referral_campaigns order by starts_on limit 1; end if;
  else
    select * into rc from public.referral_campaigns where code = btrim(p_campaign);
  end if;
  if rc.id is null then raise exception 'Referral promotion not found'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('code', x.code, 'title', x.title,
           'starts_on', x.starts_on, 'ends_on', x.ends_on) order by x.starts_on desc), '[]'::jsonb)
    into v_list from public.referral_campaigns x;

  with f as (select * from public.referral_campaign_friends(rc.id)),
  per as (
    -- 404: beside the friends counted, the friends referred in the window
    -- who have not visited yet (the Owner, 8 Oct 2026). referred_in_window,
    -- kept for the page before 404, is the friends listed who were referred
    -- in the window.
    select f.referrer_customer_id as rid, (count(*) filter (where f.counted))::int as counted,
           (count(*) filter (where f.first_visit_on is null))::int as not_yet_visited,
           (count(*) filter (where f.referred_on between rc.starts_on and rc.ends_on))::int as referred,
           (count(*) filter (where pc.id is not null))::int as waiting_check
      from f
      left join public.referral_signup_checks pc on pc.customer_id = f.friend_customer_id and pc.status = 'pending'
     group by f.referrer_customer_id
  )
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'referrer_customer_id', r.id, 'name', r.full_name, 'phone', r.phone,
             'is_affiliate', exists (select 1 from public.customer_affiliates ca
                                      where ca.customer_id = r.id and ca.deleted_at is null),
             'counted', per.counted, 'not_yet_visited', per.not_yet_visited,
             'referred_in_window', per.referred, 'waiting_check', per.waiting_check)
           || public.referral_campaign_standing(rc.tiers, per.counted)
           || jsonb_build_object(
             'reward', (select jsonb_build_object(
                          'reward_id', w.id, 'tier', w.tier, 'friends_counted', w.friends_counted,
                          'given_at', w.given_at, 'given_by_name', gp.full_name,
                          'store_id', w.store_id, 'store_name', s.name, 'note', w.note,
                          'items', (select coalesce(jsonb_agg(jsonb_build_object(
                                       'product_id', i.product_id, 'product_name', p.name,
                                       'quantity', i.quantity, 'use_no', u.use_no) order by p.name, i.id), '[]'::jsonb)
                                      from public.referral_campaign_reward_items i
                                      join public.products p on p.id = i.product_id
                                      left join public.stock_uses u on u.id = i.stock_use_id
                                     where i.reward_id = w.id))
                          from public.referral_campaign_rewards w
                          left join public.profiles gp on gp.id = w.given_by
                          left join public.stores s on s.id = w.store_id
                         where w.campaign_id = rc.id and w.referrer_customer_id = r.id
                           and w.voided_at is null),
             'friends', (select coalesce(jsonb_agg(jsonb_build_object(
                            'customer_id', c.id, 'name', c.full_name, 'phone', c.phone,
                            'referred_on', f2.referred_on, 'first_visit_on', f2.first_visit_on,
                            'counted', f2.counted,
                            'needs_check', exists (select 1 from public.referral_signup_checks pc
                                                    where pc.customer_id = c.id and pc.status = 'pending'))
                            order by f2.counted desc, f2.referred_on, c.full_name, c.id), '[]'::jsonb)
                           from f f2 join public.customers c on c.id = f2.friend_customer_id
                          where f2.referrer_customer_id = r.id))
           order by per.counted desc, r.full_name, r.id), '[]'::jsonb)
    into v_rows
    from per join public.customers r on r.id = per.rid;

  return jsonb_build_object(
    'campaign', jsonb_build_object('code', rc.code, 'title', rc.title, 'reward_reason', rc.reward_reason,
      'starts_on', rc.starts_on, 'ends_on', rc.ends_on, 'tiers', to_jsonb(rc.tiers), 'today', v_today,
      'status', case when v_today > rc.ends_on then 'final'
                     when v_today < rc.starts_on then 'not_started' else 'provisional' end),
    'campaigns', v_list,
    'referrers', v_rows);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.referral_signup_checks_pending()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 425: the Affiliates page's "Check these sign-ups" list, for an Owner or a
-- Manager. Each is a customer made through a referral link with the phone of
-- a customer already there, under another name (the Owner, Q19 = A, 9 Oct
-- 2026). They count for a referral promotion once checked as a different
-- person. Oldest first. With each: who referred them, and the customers who
-- had the phone, with how many paid or part-paid invoices each has.
begin
  perform public.require_active_staff('{owner,manager}');
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'check_id', k.id, 'customer_id', c.id, 'customer_name', c.full_name, 'phone', c.phone,
             'customer_deleted', c.deleted_at is not null,
             'referrer_customer_id', k.referrer_customer_id, 'referrer_name', r.full_name,
             'referral_code', k.referral_code, 'signed_up_at', k.created_at,
             'shares_with', (
               select coalesce(jsonb_agg(jsonb_build_object(
                        'customer_id', o.id, 'name', o.full_name, 'deleted', o.deleted_at is not null,
                        'paid_invoices', (select count(*) from public.invoices i
                                           where i.customer_id = o.id and i.deleted_at is null
                                             and i.status in ('paid', 'partially_paid')))
                        order by u.n), '[]'::jsonb)
                 from unnest(k.phone_shared_with) with ordinality as u(id, n)
                 join public.customers o on o.id = u.id))
             order by k.created_at, k.id), '[]'::jsonb)
      from public.referral_signup_checks k
      join public.customers c on c.id = k.customer_id
      left join public.customers r on r.id = k.referrer_customer_id
     where k.status = 'pending');
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.decide_referral_signup_check(p_check_id uuid, p_decision text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 425: an Owner or a Manager checks a referral sign-up that shares a
-- customer's phone under another name (the Owner, Q19 = A, 9 Oct 2026).
--   different_person  they count for a referral promotion from now on.
--   same_person       they never count. Merging the two records is a
--                     separate step, as before.
-- A note on how it was checked is required. A sign-up already checked is
-- left as it is. The Audit Log keeps who checked it and the note.
declare k public.referral_signup_checks%rowtype; v_note text := btrim(coalesce(p_note, ''));
begin
  perform public.require_active_staff('{owner,manager}');
  if p_decision is null or p_decision not in ('different_person', 'same_person') then
    raise exception 'Choose different person or same person.'; end if;
  if v_note = '' then raise exception 'Write how you checked this sign-up.'; end if;
  select * into k from public.referral_signup_checks where id = p_check_id for update;
  if not found then raise exception 'This sign-up check was not found.'; end if;
  if k.status <> 'pending' then
    return jsonb_build_object('ok', false, 'already', true, 'status', k.status,
      'message', 'This sign-up was already checked. Refresh the page.');
  end if;
  update public.referral_signup_checks
     set status = p_decision, decided_at = now(), decided_by = auth.uid(), decision_note = v_note
   where id = k.id;
  perform public.write_audit('referral_signup_checks', k.id, 'referral_signup_checked',
    jsonb_build_object('status', k.status, 'customer_id', k.customer_id),
    jsonb_build_object('status', p_decision, 'customer_id', k.customer_id,
                       'referrer_customer_id', k.referrer_customer_id, 'note', v_note));
  return jsonb_build_object('ok', true, 'status', p_decision);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.merge_customer_records(p_keep uuid, p_merge uuid, p_reason text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_preview jsonb; k public.customers%rowtype; m public.customers%rowtype;
        r record; r_lot public.customer_credit_lots%rowtype; v_new_lot uuid;
        v_moved jsonb := '{}'::jsonb; n bigint; v_keep_wallet uuid;
        v_sql text;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can merge customer records' using errcode='42501'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then
    raise exception 'Give a reason; it is kept with the merge'; end if;
  if p_request_id is null then raise exception 'A request id is required'; end if;

  -- A retry returns the original outcome instead of merging a second time.
  if exists (select 1 from public.audit_logs
              where action = 'customers_merged'
                and record_id = p_keep
                and new_data->>'request_id' = p_request_id::text) then
    return jsonb_build_object('success', true, 'replayed', true,
      'detail','This merge was already applied.'); end if;

  -- Lock both, keeper first, so two merges cannot interleave.
  select * into k from public.customers where id = least(p_keep,p_merge) for update;
  select * into m from public.customers where id = greatest(p_keep,p_merge) for update;
  select * into k from public.customers where id = p_keep;
  select * into m from public.customers where id = p_merge;

  v_preview := public.preview_customer_merge(p_keep, p_merge);
  if not (v_preview->>'can_merge')::boolean then
    raise exception 'This merge needs review first: %',
      (select string_agg(x->>'detail',' ') from jsonb_array_elements(v_preview->'blocking') x); end if;

  -- ---- credit: drawn down and reissued, never repointed -------------------
  --
  -- A posted lot is immutable -- customer, category, original amount, source
  -- and store cannot be edited -- and the ledger behind it is append-only. So
  -- the surviving record is granted a replacement carrying the same category,
  -- restrictions and dates, and the duplicate's lot is drawn down to nothing,
  -- with both movements written to the ledger. The balance is carried; it is
  -- never recreated, and bonus credit cannot become paid credit on the way.
  --
  -- The duplicate's wallet and its ledger entries stay as they are. Those
  -- entries record that, at the time, this credit moved under that record, and
  -- that remains true; the retired customer row keeps them resolvable.
  v_keep_wallet := public.ensure_customer_wallet(p_keep);
  for r_lot in
    select l.* from public.customer_credit_lots l
     where l.customer_id = p_merge and l.status = 'active' and l.remaining_amount > 0
     for update
  loop
    v_new_lot := gen_random_uuid();
    update public.customer_credit_lots
       set remaining_amount = 0, updated_at = now() where id = r_lot.id;
    insert into public.customer_credit_ledger
      (wallet_id, customer_id, entry_type, category, amount, lot_id,
       source_type, source_record_id, store_id, reason, created_by, approved_by)
    values (r_lot.wallet_id, r_lot.customer_id, 'adjust_decrease', r_lot.category,
            r_lot.remaining_amount, r_lot.id, 'customer_merge_out', p_keep,
            r_lot.store_id, p_reason, auth.uid(), auth.uid());

    insert into public.customer_credit_lots
    select (jsonb_populate_record(null::public.customer_credit_lots, to_jsonb(r_lot) || jsonb_build_object(
      'id', v_new_lot, 'wallet_id', v_keep_wallet, 'customer_id', p_keep,
      'original_amount', r_lot.remaining_amount, 'remaining_amount', r_lot.remaining_amount,
      'source_type', 'customer_merge', 'source_record_id', p_merge,
      'reference_no', null, 'reason', p_reason, 'reversal_of_lot_id', null,
      'created_by', auth.uid(), 'approved_by', auth.uid(),
      'created_at', now(), 'updated_at', now()))).*;
    insert into public.customer_credit_ledger
      (wallet_id, customer_id, entry_type, category, amount, lot_id,
       source_type, source_record_id, store_id, reason, created_by, approved_by)
    values (v_keep_wallet, p_keep, 'grant', r_lot.category, r_lot.remaining_amount,
            v_new_lot, 'customer_merge_in', p_merge, r_lot.store_id,
            p_reason, auth.uid(), auth.uid());
  end loop;

  -- ---- referrals go through the path that owns them -----------------------
  --
  -- customers.referred_by is protected by enforce_referral_ownership and by a
  -- no-self-referral trigger, and reassign_customer_referrer is what may change
  -- it: it locks the row, walks the chain for cycles and records the reason.
  -- Repointing it directly would be going round all of that.
  if k.referred_by = p_merge then
    perform public.reassign_customer_referrer(p_keep, null,
      'Merged duplicate ' || p_merge::text || ': ' || trim(p_reason));
  end if;
  -- 398: the duplicate's friends are the same referrals, made when they
  -- were made: each keeps their referral date (tg_customers_referral_date).
  perform set_config('energia.keep_referral_date', '1', true);
  for r in select id from public.customers
            where referred_by = p_merge and id <> p_keep and deleted_at is null
  loop
    perform public.reassign_customer_referrer(r.id, p_keep,
      'Referrer merged from duplicate ' || p_merge::text || ': ' || trim(p_reason));
  end loop;
  perform set_config('energia.keep_referral_date', '0', true);

  -- ---- affiliate record, when only the duplicate has one ------------------
  update public.customer_affiliates set customer_id = p_keep
   where customer_id = p_merge
     and not exists (select 1 from public.customer_affiliates where customer_id = p_keep);

  -- ---- everything else, from the catalogue --------------------------------
  for r in
    select c.relname as tbl, a.attname as col
      from pg_constraint kk
      join pg_class c on c.oid = kk.conrelid and c.relkind = 'r'
      join pg_attribute a on a.attrelid = kk.conrelid and a.attnum = any(kk.conkey)
      join pg_class f on f.oid = kk.confrelid
      join pg_namespace ns on ns.oid = c.relnamespace
     where kk.contype = 'f' and f.relname = 'customers' and ns.nspname = 'public'
       -- Handled above, or deliberately not moved:
       and not (c.relname = 'customer_credit_wallets')            -- UNIQUE per customer
       and not (c.relname = 'customer_credit_ledger')             -- append-only by design
       and not (c.relname = 'customer_credit_lots')               -- immutable; reissued above
       and not (c.relname = 'customers' and a.attname = 'referred_by') -- reassigned above
       and not (c.relname = 'customer_affiliates' and a.attname = 'customer_id')
       -- 362: a phone-review capture describes its own record's phone (one row
       -- per customer); it stays with the retired record.
       and not (c.relname = 'customer_phone_migration_map')
       -- 425: a referral sign-up check stays with the sign-up it was made for.
       -- The retired record keeps it, so it no longer counts or waits; the kept
       -- customer keeps their own check, or none (one check per customer).
       and not (c.relname = 'referral_signup_checks' and a.attname = 'customer_id')
     order by c.relname, a.attname
  loop
    v_sql := format('update public.%I set %I = $1 where %I = $2', r.tbl, r.col, r.col);
    execute v_sql using p_keep, p_merge;
    get diagnostics n = row_count;
    if n > 0 then
      v_moved := v_moved || jsonb_build_object(r.tbl || '.' || r.col, n);
    end if;
  end loop;

  -- The duplicate is retired, not destroyed: it is the evidence that those
  -- older records were always this person.
  update public.customers
     set deleted_at = now(),
         notes = coalesce(notes || E'\n', '') ||
                 'Merged into ' || coalesce(k.full_name, p_keep::text) ||
                 ' (' || p_keep::text || ') — ' || trim(p_reason)
   where id = p_merge;

  perform public.write_audit('customers', p_keep, 'customers_merged',
    jsonb_build_object('kept', to_jsonb(k), 'merged', to_jsonb(m)),
    jsonb_build_object('merged_from', p_merge, 'moved', v_moved,
                       'reason', trim(p_reason), 'request_id', p_request_id));

  return jsonb_build_object('success', true, 'kept', p_keep, 'retired', p_merge,
    'moved', v_moved);
end $function$
$def$
  ];
  -- Relied on, not changed.
  c_relied constant text[] := array['customer_names_match(text,text)',
    'normalize_customer_phone(text)',
    'customer_phone_name_matches(text,text)',
    'require_resolved_customer_identity(text,text)',
    'require_active_staff(text[])',
    'is_owner_or_manager()',
    'affiliate_payout_access(boolean)',
    'affiliate_referrer_balances()',
    'affiliate_month_balances()',
    'affiliate_portal_purchases()',
    'current_affiliate_customer_id()',
    'customer_affiliate_state(uuid)',
    'inspect_customer_phone(text,text)'];
  c_relied_md5 constant text[] := array['ef1af52e4888cefb6037a2291f4e011d',
    'b2bfac910e0c9eff402ba44e19750bee',
    '1bdf8322972b6671b7cbb08bc8211f8a',
    '5bde1a418363442ec27e2944442f5874',
    '877b3aa74cea559881979bb161c450e2',
    '125dec10ce33b84ff5fb40a9bd455235',
    '90b7399378a7604afd4af97c059d0703',
    '54ef098ba8f9e3d81bb45906c4607ab6',
    '84c0741e983c8f483d677353c732d891',
    'a5e5c99ae092d2fbea35f3f7d8dc90f0',
    '51695acf5f26ce3918d6003d0c980b0f',
    '887d0b58f4d1f6670adbaf10591e0f9c',
    '6672c4d1963996f3b601896f4a55916e'];
  -- The new table's columns, as information_schema gives them.
  c_table_shape constant text :=
    'id uuid NO gen_random_uuid()|customer_id uuid NO |referrer_customer_id uuid YES |referral_code text YES '
    || '|normalized_phone text NO |phone_shared_with ARRAY NO ''{}''::uuid[]|status text NO ''pending''::text'
    || '|created_at timestamp with time zone NO now()|decided_at timestamp with time zone YES '
    || '|decided_by uuid YES |decision_note text YES ';
  c_legacy_fn constant text := 'create_commission_payout(uuid,date,uuid,text,text)';
  c_legacy_fn_md5 constant text := '7cf61414f6bda12f87a24c0df27bf50e';
  c_legacy_tables constant text[] := array['affiliate_commissions', 'affiliates'];
  v_path text := current_setting('search_path');
  v_acl jsonb := '{}'::jsonb;
  v_names text[];
  v text; d text; n bigint; t text; i int;
begin
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- 424 first: it drops product_exchanges.affiliate_id, the last link to the
  -- legacy affiliates table.
  if exists (select 1 from pg_attribute where attrelid = 'public.product_exchanges'::regclass
              and attname = 'affiliate_id' and not attisdropped) then
    raise exception '425: apply 424 first (product_exchanges.affiliate_id still points at the legacy affiliates table)';
  end if;

  -- Each text is the tested one.
  for i in 1 .. cardinality(c_sig) loop
    if md5(c_def[i]) <> c_after[i] then
      raise exception '425: the text of public.% is not the tested one (md5 %)', c_sig[i], md5(c_def[i]); end if;
  end loop;

  -- Each changed function is the BEFORE or the AFTER version; each new one
  -- is missing or the AFTER version.
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then
      if c_before[i] is not null then raise exception '425: public.% is missing', c_sig[i]; end if;
    else
      d := md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i])));
      if d <> c_after[i] and d is distinct from c_before[i] then
        raise exception '425: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', c_sig[i], d;
      end if;
    end if;
  end loop;

  -- No other function takes one of these names.
  v_names := array(select split_part(s, '(', 1) from unnest(c_sig) s);
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = any (v_names)
     and p.oid::regprocedure::text <> all (c_sig);
  if v is not null then raise exception '425: another function takes one of these names: %', v; end if;

  -- The functions relied on are as read on 18 Oct 2026.
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '425: public.% is missing or not the version this was tested against. Re-read it from production and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- referral_signup_checks: missing, or exactly this shape.
  if to_regclass('public.referral_signup_checks') is not null then
    select string_agg(c.column_name || ' ' || c.data_type || ' ' || c.is_nullable || ' ' || coalesce(c.column_default, ''), '|'
                      order by c.ordinal_position) into v
      from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = 'referral_signup_checks';
    if v is distinct from c_table_shape then
      raise exception '425: public.referral_signup_checks exists and is not this migration''s table (%)', v; end if;
    if (select count(*) from pg_constraint where conrelid = 'public.referral_signup_checks'::regclass
          and conname in ('referral_signup_checks_customer_key', 'referral_signup_checks_status_check',
                          'referral_signup_checks_decided_check')) <> 3 then
      raise exception '425: public.referral_signup_checks is missing one of its constraints'; end if;
  end if;

  -- The legacy writer: the version read that day, or gone.
  if to_regprocedure('public.' || c_legacy_fn) is not null
     and md5(pg_get_functiondef(to_regprocedure('public.' || c_legacy_fn))) <> c_legacy_fn_md5 then
    raise exception '425: public.% is not the version read on 18 Oct 2026', c_legacy_fn; end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'create_commission_payout'
     and p.oid::regprocedure::text <> c_legacy_fn;
  if v is not null then raise exception '425: another create_commission_payout exists: %', v; end if;

  -- The legacy tables: empty, and nothing but each other points at them or
  -- reads them; or gone.
  foreach t in array c_legacy_tables loop
    continue when to_regclass('public.' || t) is null;
    execute format('select count(*) from public.%I', t) into n;
    if n <> 0 then raise exception '425: public.% has % row(s); it was empty on 18 Oct 2026', t, n; end if;
    select string_agg(k.conname || ' on ' || k.conrelid::regclass::text, ', ') into v
      from pg_constraint k
     where k.confrelid = to_regclass('public.' || t)
       and k.conrelid not in (select to_regclass('public.' || x) from unnest(c_legacy_tables) x where to_regclass('public.' || x) is not null);
    if v is not null then raise exception '425: something else points at public.%: %', t, v; end if;
    select string_agg(distinct c.relname, ', ') into v
      from pg_depend dp
      join pg_rewrite w on dp.classid = 'pg_rewrite'::regclass and w.oid = dp.objid
      join pg_class c on c.oid = w.ev_class
     where dp.refobjid = to_regclass('public.' || t) and c.oid <> to_regclass('public.' || t);
    if v is not null then raise exception '425: a view reads public.%: %', t, v; end if;
    select string_agg(p.oid::regprocedure::text, ', ') into v
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.prosrc ~* ('\m(from|join|into|update|table|references)\s+(public\.)?' || t || '\M');
    if v is not null then raise exception '425: a function reads public.%: %', t, v; end if;
  end loop;

  -- What may call the changed functions now.
  for i in 1 .. cardinality(c_sig) loop
    if c_before[i] is not null then
      v_acl := v_acl || jsonb_build_object(c_sig[i],
        (select coalesce(proacl::text, '') from pg_proc where oid = to_regprocedure('public.' || c_sig[i])));
    end if;
  end loop;

  -- ── Changes ─────────────────────────────────────────────────────────────
  -- The checks of shared-phone referral sign-ups (AFFILIATES-12).
  if to_regclass('public.referral_signup_checks') is null then
    create table public.referral_signup_checks (
      id uuid primary key default gen_random_uuid(),
      customer_id uuid not null references public.customers(id) on delete cascade,
      referrer_customer_id uuid references public.customers(id) on delete set null,
      referral_code text,
      normalized_phone text not null,
      phone_shared_with uuid[] not null default '{}'::uuid[],
      status text not null default 'pending',
      created_at timestamptz not null default now(),
      decided_at timestamptz,
      decided_by uuid references public.profiles(id),
      decision_note text,
      constraint referral_signup_checks_customer_key unique (customer_id),
      constraint referral_signup_checks_status_check check (status in ('pending', 'different_person', 'same_person')),
      constraint referral_signup_checks_decided_check check ((status = 'pending') = (decided_at is null))
    );
    comment on table public.referral_signup_checks is
      '425: a customer made through a referral link with the phone of a customer already there, under another name. '
      'They count for a referral promotion once an Owner or Manager checks them as a different person (Q19 = A, 9 Oct 2026). '
      'Read and written only through affiliate_referral_signup, referral_signup_checks_pending and decide_referral_signup_check.';
  end if;
  alter table public.referral_signup_checks enable row level security;
  revoke all on table public.referral_signup_checks from public, anon, authenticated;
  grant all on table public.referral_signup_checks to service_role;

  -- The functions, each left alone when it is already this version.
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      execute c_def[i];
    end if;
    if c_before[i] is null then
      execute format('revoke all on function public.%s from public, anon', c_sig[i]);
      execute format('grant execute on function public.%s to authenticated, service_role', c_sig[i]);
    end if;
  end loop;

  -- The legacy writer and tables (AFFILIATES-15).
  execute 'drop function if exists public.' || c_legacy_fn;
  drop table if exists public.affiliate_commissions;
  drop table if exists public.affiliates;

  -- ── Afterwards ──────────────────────────────────────────────────────────
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '425: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if c_before[i] is not null then
      if (select coalesce(proacl::text, '') from pg_proc where oid = to_regprocedure('public.' || c_sig[i]))
         is distinct from v_acl->>c_sig[i] then
        raise exception '425: the grants of public.% changed', c_sig[i]; end if;
    else
      if has_function_privilege('anon', to_regprocedure('public.' || c_sig[i]), 'execute')
         or not has_function_privilege('authenticated', to_regprocedure('public.' || c_sig[i]), 'execute') then
        raise exception '425: public.% is not for signed-in logins alone', c_sig[i]; end if;
    end if;
  end loop;
  if has_table_privilege('anon', 'public.referral_signup_checks', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'public.referral_signup_checks', 'select,insert,update,delete,truncate,references,trigger')
     or not (select relrowsecurity from pg_class where oid = 'public.referral_signup_checks'::regclass) then
    raise exception '425: public.referral_signup_checks is open to a client role'; end if;
  if to_regprocedure('public.' || c_legacy_fn) is not null
     or to_regclass('public.affiliate_commissions') is not null or to_regclass('public.affiliates') is not null then
    raise exception '425: a legacy object is still there'; end if;

  perform set_config('search_path', v_path, true);
end $mig$;
