-- 430_policies_store_scoped_and_fast.sql
--
-- THE TABLE RULES: INVOICE LINES FOLLOW THEIR INVOICE'S STORE, EVERY RULE
-- ASKS WHO YOU ARE ONCE PER READ, AND THE ROLE HELPERS ASK WHAT "ACTIVE"
-- MEANS IN FULL (audit of 9 Oct 2026: X-10, X-11, CUSTOMERS-N3)
--
-- This is the last database batch. It is numbered 430 but goes in after
-- every other batch (DEPLOY ORDER), so it sees the final rules.
--
-- WHAT WAS WRONG
--
--   1. X-10. Five tables of invoice detail were readable by any active member
--      of staff for every store: invoice_items ("read invoice items"),
--      invoice_revisions ("read invoice revisions"),
--      invoice_promotion_selections ("read invoice selections"),
--      invoice_refunds ("read refunds") and invoice_credit_splits ("read
--      credit splits"). Their rule was "current_user_role() is not null". The
--      invoices themselves, their payments, hand-overs and the rest are
--      limited to the stores a person works at. 406 already made the seven
--      invoice-detail functions check the store. No effect today: there are
--      2 stores and every Manager and Staff member works at both.
--   2. X-11. A rule that calls a helper such as current_user_role(),
--      is_owner_or_manager() or user_has_store_access(store_id) as it is
--      runs that helper once for every row it looks at. A SECURITY DEFINER
--      function is never folded into the query, so STABLE alone does not
--      help. After all the other batches, 129 rules still did this
--      (current_user_role() in 40 rules, user_has_store_access() in 38,
--      is_owner_or_manager() in 31, is_manager_or_above() in 19, and
--      others). 430 rewrites 127 of them; the other 2 are B05's and B08's.
--      The audit measured, as a staff login on production: all customers
--      190.9 ms (5.9 ms written as "(select current_user_role())"), and
--      stock movements 1,475.8 ms for 1,178 rows (1.25 ms). Pages get slower
--      as the tables grow.
--   3. Supabase's performance advisor also flags 17 "manage" rules (FOR
--      ALL) that run beside the read rule on every read.
--   4. CUSTOMERS-N3 and the X-5 follow-up. is_owner_or_manager(),
--      is_manager_or_above(), is_owner_or_admin(), is_owner(),
--      can_manage_warehouse_stock(), can_view_customer_credit(),
--      invoice_date_recovery_access(), stock_history_global(),
--      stock_history_location() and user_has_store_access() asked only
--      "active" (some also "not deleted"). current_user_role() (406) asks
--      active, not deleted and invitation accepted. Latent: 412 bans the
--      login of a closed profile, and no profile is deleted or pending.
--      The survey half of CUSTOMERS-N3 (health_survey_detail and the old
--      update_survey_particulars) is done by 419 (B05): both start with
--      require_active_staff('{owner,admin,manager,staff}') and the new
--      update_survey_particulars_v2 refuses a deleted customer.
--
-- THE RULES (approved with the audit fixes on 9 Oct 2026; nothing here is a
-- new business rule)
--
--   1. An invoice's lines, revisions, promotion picks, refunds and credit
--      splits are read by whoever may read the invoice: an active Owner or
--      Admin at every store, any other active member of staff at the stores
--      they are assigned to. This is the rule invoices and invoice_payments
--      already have.
--   2. Every other rule lets in exactly the people it let in before.
--   3. "Active" means the same everywhere: active, not deleted, invitation
--      accepted.
--   4. Rules owned by another batch are left as that batch built them.
--
-- WHAT THIS DOES
--
--   * The ten helpers above become STABLE and ask in full what
--     current_user_role() asks: active, not deleted, invitation accepted.
--     Who passes is otherwise unchanged. Each is one read of profiles (and
--     of user_store_assignments where it needs the stores), with no call to
--     another helper. 131 server functions (the Dashboard and Reports ones
--     among them) call user_has_store_access() once per row, and a helper
--     inside a helper is planned again on every call, so a nested call would
--     make them several times slower.
--   * New current_user_store_ids(): every store for an active Owner or
--     Admin, the assigned stores for any other active member of staff,
--     none for anyone else. Signed-in logins may call it (rules call it);
--     signed-out ones may not.
--   * The five X-10 rules become "exists an invoice of this row that the
--     reader may read" (the selections go through invoice_items, as
--     invoice_stock_components does). Signed-in logins keep SELECT on the
--     five tables and lose INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES,
--     TRIGGER and MAINTAIN, which no rule allowed anyway; anon loses all.
--   * 107 other rules are rewritten so each helper runs once per query:
--       f()                          ->  (select f())
--       auth.uid()                   ->  (select auth.uid())
--       user_has_store_access(x)     ->  (select is_owner_or_admin())
--                                        or x = any (S)
--       stock_history_movement(...)  ->  (select stock_history_global())
--                                        or from_store_id = any (S) or to_store_id = any (S)
--       stock_history_location('store', x)      ->  x is not null and
--           ((select stock_history_global()) or x = any (S))
--       stock_history_location('warehouse', x)  ->  x is not null and
--           (select stock_history_global())
--     where S is (select current_user_store_ids())::uuid[] (the cast keeps
--     it one array, asked once, not a list of rows). Each is the same test
--     as before, row for row: stock_history_location's store half is for
--     Staff, the only role stock_history_global() leaves out
--     (scripts/permissions/tests/policy-initplan.sql compares every rule
--     for every role).
--   * The 15 "manage" rules (FOR ALL) of B17's tables become one INSERT,
--     one UPDATE and one DELETE rule each, with the same tests, so a read
--     runs only the read rule. A deleted promotion or voucher stays
--     readable by Owners and Managers, as the "manage" rule allowed: "read
--     promotions" and "read vouchers" add "or (select is_owner_or_manager())".
--   * At the end it sweeps every rule in public and storage: none may call
--     a helper per row except the three named below.
--
-- SPEED (test copies, 18 Oct 2026, median of 7 runs, before 430 -> after).
-- Table reads, at production's row counts, as Staff at both stores
-- (count(*)):
--   customers (13,000)          55.3 ms -> 1.3 ms
--   invoices (410)               4.3 ms -> 0.2 ms
--   invoice_items (630)          2.7 ms -> 0.4 ms
--   invoice_payments (400)       8.7 ms -> 0.4 ms
--   stock_movements (1,270)    453.2 ms -> 0.6 ms
--   The small tables (revisions, picks, refunds) stay under 1 ms; they now
--   also check the invoice's store.
-- Server functions, with 410 invoices, 630 lines and 400 payments, as
-- Staff / Manager / Owner (an earlier draft of 430, whose helpers called
-- current_user_role(), made these 2 to 6 times slower):
--   dashboard_sales                 43.6 / 35.7 / 36.2 ms -> 33.2 / 26.2 / 31.3 ms
--   dashboard_sales_by_store        15.1 /  9.6 / 11.2 ms ->  9.9 /  6.4 /  9.0 ms
--   report_sales_by_service_staff    -   / 14.6 / 16.6 ms ->   -  / 11.4 / 15.1 ms
--   invoice_sales_ledger             5.0 /  4.6 /  3.6 ms ->  3.2 /  3.0 /  2.9 ms
--   user_has_store_access, 2,000 calls, one per row
--                                   22.1 / 21.2 / 15.3 ms -> 13.3 / 13.2 / 11.9 ms
--   stock_history_location, 2,000 calls, one per row
--                                   81.1 / 75.8 / 73.1 ms -> 14.2 / 12.7 / 12.8 ms
--
-- NOT CHANGED
--
--   * The rules of other batches: "read pte" (B08, 422) and "read survey
--     pdfs" (B05, 419) still call user_has_store_access() per row; they are
--     reported (a notice) and left for their batch. So X-11 stays open on
--     these two (and on "read therapy benefit choice history", which reads
--     purchased_therapy_entitlements and so meets "read pte" there). The
--     follow-up (B08 and B05, or one small migration after 430) writes them
--     so, which lets in the same people row for row:
--       "read pte": ((select public.current_user_role()) is not null and
--         ((select public.is_owner_or_admin()) or
--          store_id = any ((select public.current_user_store_ids())::uuid[])))
--       "read survey pdfs": user_has_store_access(s.store_id) becomes
--         ((select public.is_owner_or_admin()) or
--          s.store_id = any ((select public.current_user_store_ids())::uuid[]))
--     It pins 430's AFTER md5s. A re-run of 430 after it refuses and changes
--     nothing (430 pins both rules), as with the other batches.
--     420's rules (products, stores, warehouses, their links, "managers read
--     store inventory") and 419's health rules already ask once per query.
--   * "stock_history_transfer_scope" on transfer_requests: its check takes
--     the row (stock_history_transfer(id)), so it cannot be asked once. It
--     now uses the full active test through stock_history_global() and
--     stock_history_location().
--   * stock_history_movement(), stock_history_transfer(), current_user_role(),
--     my_assigned_store_id(), my_assigned_stores() and every server function.
--   * No row of any table. The pages need no change.
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. Before
--   anything changes, every check passes or nothing does:
--   * every function it relies on, and one function of each batch that must
--     be live first, reads as after that batch;
--   * each helper is the version read on 18 Oct 2026 (BEFORE) or already
--     this one (AFTER, left alone); current_user_store_ids() is missing or
--     already this one, and no other function has its name; each text to
--     install has its AFTER md5;
--   * each rule it changes reads as after every batch (BEFORE) or already as
--     this leaves it (AFTER); each rule it leaves reads as after every batch;
--     a rule it has not seen stops it.
--   Afterwards: every helper, rule and grant reads as tested, and the sweep
--   finds no other per-row call. Then, switching role (no row changes): a
--   signed-in login with no profile reads no row of the five tables and
--   works at no store, the five reads are planned with InitPlans, and an
--   active Owner (when there is one) reads every invoice line, revision,
--   selection and refund and every stock movement. A second run changes
--   nothing.
--
-- BEFORE (production, 18 Oct 2026, head 20261016064105; md5 of
-- pg_get_functiondef with search_path public). None of 417-429 or 431
-- changes them.
--   is_owner_or_manager()                125dec10ce33b84ff5fb40a9bd455235 -> a98e50f1b6d3fa1e6c62cf52a8073cc8
--   is_manager_or_above()                f12b9ed342070fa4defa30e4da2ba655 -> e87f6da4a7284374f0e2bc5b55c502be
--   is_owner_or_admin()                  3856bdf5ed650fe84e2304ec4f0f0a68 -> 9ddf58d83655a349abd2e3a2845ebb09
--   is_owner()                           01d03a86345b4c973da7d93ea40e689e -> 8eb059153c36a23f1d22b122543a7787
--   can_manage_warehouse_stock()         b51c6f1c0e77a277d8757d824cb198dd -> 0fa45b2379faaf6c32ab5429b5b0792b
--   can_view_customer_credit()           170f93e7d4c5166c4230ee2e505de6e7 -> 347f20fdfcbe7e2666f9d6995bb53647
--   invoice_date_recovery_access()       08f78f919c533ebf08af1356b0dfc12d -> 7b9626d4731705e0e34e2f7d1bbd3448
--   stock_history_global()               9e358d4c2fdce30c43d3e9baf8703d4d -> 1836ecae21d53a926b2bb4fb345abc92
--   stock_history_location(text,uuid)    e830c6dba5fcc251f30ae7a282b18ba0 -> 27ceff31cb5587854a31537ca3e2bb0c
--   user_has_store_access(uuid)          8c82c6bcb64f496c5a05a2b8dafa95f8 -> 708992afaa6c3951f6329239b742987c
--   current_user_store_ids()             (new)                            -> 54191b973c31654b903d48bea01ce533
--   relied on, not changed
--   current_user_role()                                       519b0a33a3548f970c5d585b6e76a389  406
--   require_active_staff(text[])                              877b3aa74cea559881979bb161c450e2  406
--   require_store_access(uuid)                                f9332fd2f0092337d64501d8a647c23f  406
--   survey_attachment_store(text)                             58f7d30040f104d240b40ec3e9d9567f  407
--   stock_history_movement(uuid,uuid,uuid,uuid,uuid,uuid)     cb246d3f33256b58e98930058cd14521  421
--   stock_history_transfer(uuid)                              ec6fa8b8bd72ec700a6711e7cdba7f8d  421
--   assert_customer_dob_change(uuid,date,text)                3d9fc369da08a6baf623f842999f0156  batch 418 (B04)
--   can_edit_products()                                       9d157e1434cb0c22a833303bbbade8bb  batch 420 (B06)
--   audit_module(text,text)                                   daf0c43e9e9578e78048b2f6d7cba57e  batch 431 (B14b)
--   invite_user_reusable_login(uuid)                          340580cff28c74eb1b1b8bde967dc8fc  batch 429 (B15)
--   close_invoice_therapy_units(uuid,uuid,uuid[],jsonb,numeric,text,uuid,text)
--                                                             5d79476632fe31145a903d0f267cfafc  batch 417 (B03)
--   claim_legacy_therapy(uuid,date,uuid,jsonb,text,text,boolean)
--                                                             164530713b7a52f9b80642bbd0e1ed00  batch 422 (B08)
--   create_split_credit_package_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)
--                                                             d9219dc95c3f5f598085161d31744d16  batch 423 (B09)
--   exchange_credit_preview(uuid,uuid)                        263bb91b1ed38c6b53767c4d0182595c  batch 424 (B10)
--   review_tiktok_settlement_without_order(uuid[],text)       a47ecdd18eaaa06bb4c9ca613e8164ed  batch 427 (B13)
--   can_view_health_data()                                    5cccb54dd99d2c3d77548cd8242ea126  batch 419 (B05)
--   decide_referral_signup_check(uuid,text,text)              9d6fe2fd52a16a845d776b06caca0063  batch 425 (B11)
--   update_pending_rental(uuid,integer,special_rate_type,integer,date,date,text)
--                                                             1022ecdafb4e1e2f21e7dc051376b028  batch 426 (B12)
--   public function fingerprint, production now (1244 functions)  ff637c8e7adc37a4892a6bf361290c4b
--   public function fingerprint after every batch (no 430)        d0cf560f40c5d1f47cca01b5c52c94c4
-- AFTER: the md5s above; every rule's AFTER md5 is in the arrays below.
--   public function fingerprint after every batch and 430         be589a20fca0f181f648e6e93c45cb4d
--
-- DEPLOY ORDER: LAST of all, after 418, 420, 431, 429, 417, 422, 423, 424,
-- 427, 419, 425 and 426 are live (it refuses until each is: see the
-- "batch" lines above). Then reload the app on the shop's devices (not
-- needed, but the pages read faster at once).
--   * After 430, a re-run of 415, 418, 419, 421, 423, 424, 425 or 427
--     refuses and changes nothing: each pins a helper this changes. So a
--     suite that installs one of them again (\ir :mig) stops there. Run such
--     a suite as a regression test with the install skipped: -v mig=/dev/null.
--   * 430 changes two refusal texts that other suites check. Both are on
--     purpose, and the person is still refused with nothing changed:
--       - scripts/invoices/tests/staff-corrections.sql (B02) S7, a deleted
--         staff profile: "No access to this invoice" with 430, the Owner or
--         Manager refusal without it. This batch changes that file; commit it
--         with 430.
--       - scripts/affiliate-signup/tests/shared-phone-425.sql (B11) D3b, a
--         Manager whose invitation is pending: "Only an Owner or Manager ..."
--         with 430 (referral_campaign_report asks is_owner_or_manager()
--         first), "Only active Energia staff ..." without it. That file is
--         B11's: its D3b check must accept either text before 430 goes live.
--   * If 419, 425 or 426 changes again before it goes live, update its
--     batch line here, test again and record the new md5. The same if a
--     rule is added or changed meanwhile (also a storage rule made in the
--     Supabase dashboard): 430 refuses a rule it has not seen.
--   * It changes the rules of 108 tables, so it waits up to 5 s for
--     each table. Apply it at a quiet time; if it times out, nothing has
--     changed and it can simply run again.
--   * No front-end change and no data repair.
--
-- Test: scripts/permissions/tests/store-scoping.sql (one-store staff and
-- the invoice lines), scripts/permissions/tests/policy-initplan.sql (every
-- rule, row for row, for every role and two affiliate logins, a write on
-- every split rule, the plans, and the helpers called per row and the
-- Dashboard's sales read timed before and after: no slower), and after it
-- function-grants.sql, staff-only-functions.sql, rls-policies.sql and
-- role-guards.sql. Each SQL suite takes -v mig=<this file> and runs in
-- begin ... rollback.

set lock_timeout = '5s';

do $mig$
declare
  -- ── The helpers: signature, BEFORE md5 (null: new), AFTER md5, the text
  -- installed, as pg_get_functiondef prints it (so its md5 is checked first).
  c_fn constant text[][] := array[
    ['is_owner_or_manager()', '125dec10ce33b84ff5fb40a9bd455235', 'a98e50f1b6d3fa1e6c62cf52a8073cc8', $f$CREATE OR REPLACE FUNCTION public.is_owner_or_manager()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 430: an active Owner or Manager. Active means what current_user_role()
  -- (406) means: active, not deleted, invitation accepted. Before 430 this
  -- asked only "active".
  -- One read of profiles and no call to another helper, so a call per row
  -- stays cheap.
  -- STABLE, so a rule that calls it as (select public.is_owner_or_manager())
  -- asks once per query, not per row.
  select exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_active and p.deleted_at is null
                    and coalesce(p.invitation_status, 'accepted') = 'accepted'
                    and p.role in ('owner', 'manager'))
$function$
$f$],
    ['is_manager_or_above()', 'f12b9ed342070fa4defa30e4da2ba655', 'e87f6da4a7284374f0e2bc5b55c502be', $f$CREATE OR REPLACE FUNCTION public.is_manager_or_above()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 430: an active Owner, Admin or Manager (active as in current_user_role():
  -- active, not deleted, invitation accepted). STABLE: once per query in a rule.
  -- One read of profiles and no call to another helper, so a call per row
  -- stays cheap.
  select exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_active and p.deleted_at is null
                    and coalesce(p.invitation_status, 'accepted') = 'accepted'
                    and p.role in ('owner', 'admin', 'manager'))
$function$
$f$],
    ['is_owner_or_admin()', '3856bdf5ed650fe84e2304ec4f0f0a68', '9ddf58d83655a349abd2e3a2845ebb09', $f$CREATE OR REPLACE FUNCTION public.is_owner_or_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 430: an active Owner or Admin (active as in current_user_role(): active,
  -- not deleted, invitation accepted). STABLE: once per query in a rule.
  -- One read of profiles and no call to another helper, so a call per row
  -- stays cheap.
  select exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_active and p.deleted_at is null
                    and coalesce(p.invitation_status, 'accepted') = 'accepted'
                    and p.role in ('owner', 'admin'))
$function$
$f$],
    ['is_owner()', '01d03a86345b4c973da7d93ea40e689e', '8eb059153c36a23f1d22b122543a7787', $f$CREATE OR REPLACE FUNCTION public.is_owner()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 430: an active Owner (active as in current_user_role(): active, not
  -- deleted, invitation accepted). Server functions call it; no client does.
  -- One read of profiles and no call to another helper, so a call per row
  -- stays cheap.
  select exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_active and p.deleted_at is null
                    and coalesce(p.invitation_status, 'accepted') = 'accepted'
                    and p.role in ('owner'))
$function$
$f$],
    ['can_manage_warehouse_stock()', 'b51c6f1c0e77a277d8757d824cb198dd', '0fa45b2379faaf6c32ab5429b5b0792b', $f$CREATE OR REPLACE FUNCTION public.can_manage_warehouse_stock()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 430: an active Owner, Manager or Inventory Manager (active as in
  -- current_user_role(): active, not deleted, invitation accepted).
  -- One read of profiles and no call to another helper, so a call per row
  -- stays cheap.
  select exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_active and p.deleted_at is null
                    and coalesce(p.invitation_status, 'accepted') = 'accepted'
                    and p.role in ('owner', 'manager', 'inventory_manager'))
$function$
$f$],
    ['can_view_customer_credit()', '170f93e7d4c5166c4230ee2e505de6e7', '347f20fdfcbe7e2666f9d6995bb53647', $f$CREATE OR REPLACE FUNCTION public.can_view_customer_credit()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 430: who reads customer credit, as before: an active Owner or Manager, or
  -- active Staff assigned to a store. Active as in current_user_role():
  -- active, not deleted, invitation accepted.
  -- One read of profiles and no call to another helper, so a call per row
  -- stays cheap.
  select exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_active and p.deleted_at is null
                    and coalesce(p.invitation_status, 'accepted') = 'accepted'
                    and (p.role in ('owner', 'manager')
                         or (p.role = 'staff'
                             and exists (select 1 from public.user_store_assignments usa
                                          where usa.user_id = p.id))))
$function$
$f$],
    ['invoice_date_recovery_access()', '08f78f919c533ebf08af1356b0dfc12d', '7b9626d4731705e0e34e2f7d1bbd3448', $f$CREATE OR REPLACE FUNCTION public.invoice_date_recovery_access()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 430: an active Owner or Manager (active as in current_user_role(): active,
  -- not deleted, invitation accepted).
  -- One read of profiles and no call to another helper, so a call per row
  -- stays cheap.
  select exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_active and p.deleted_at is null
                    and coalesce(p.invitation_status, 'accepted') = 'accepted'
                    and p.role in ('owner', 'manager'))
$function$
$f$],
    ['stock_history_global()', '9e358d4c2fdce30c43d3e9baf8703d4d', '1836ecae21d53a926b2bb4fb345abc92', $f$CREATE OR REPLACE FUNCTION public.stock_history_global()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 430: who sees every place's stock history, as before: an active Owner,
  -- Admin, Manager or Inventory Manager. Active as in current_user_role():
  -- active, not deleted, invitation accepted.
  -- One read of profiles and no call to another helper, so a call per row
  -- stays cheap.
  select exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_active and p.deleted_at is null
                    and coalesce(p.invitation_status, 'accepted') = 'accepted'
                    and p.role in ('owner', 'admin', 'manager', 'inventory_manager'))
$function$
$f$],
    ['stock_history_location(text,uuid)', 'e830c6dba5fcc251f30ae7a282b18ba0', '27ceff31cb5587854a31537ca3e2bb0c', $f$CREATE OR REPLACE FUNCTION public.stock_history_location(p_kind text, p_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 430: as before, everyone stock_history_global() lets in, and Staff at
  -- their own stores. Active as in current_user_role(): active, not deleted,
  -- invitation accepted.
  -- One read of profiles and no call to another helper, so a call per row
  -- stays cheap.
  select p_id is not null
     and exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_active and p.deleted_at is null
                    and coalesce(p.invitation_status, 'accepted') = 'accepted'
                    and (p.role in ('owner', 'admin', 'manager', 'inventory_manager')
                         or (p_kind = 'store' and p.role = 'staff'
                             and exists (select 1 from public.user_store_assignments a
                                          where a.user_id = p.id and a.store_id = p_id))))
$function$
$f$],
    ['user_has_store_access(uuid)', '8c82c6bcb64f496c5a05a2b8dafa95f8', '708992afaa6c3951f6329239b742987c', $f$CREATE OR REPLACE FUNCTION public.user_has_store_access(target_store_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 430: as before, every store for an active Owner or Admin, and their
  -- assigned stores for any other active member of staff. Active as in
  -- current_user_role(): active, not deleted, invitation accepted (before
  -- 430 it asked only "active").
  -- One read of profiles and no call to another helper, so a call per row
  -- stays cheap.
  -- STABLE. A read rule asks current_user_store_ids() once per query instead
  -- of calling this per row.
  select exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_active and p.deleted_at is null
                    and coalesce(p.invitation_status, 'accepted') = 'accepted'
                    and (p.role in ('owner', 'admin')
                         or exists (select 1 from public.user_store_assignments usa
                                     where usa.user_id = p.id and usa.store_id = target_store_id)))
$function$
$f$],
    ['current_user_store_ids()', null, '54191b973c31654b903d48bea01ce533', $f$CREATE OR REPLACE FUNCTION public.current_user_store_ids()
 RETURNS uuid[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 430 (new): the stores the caller works at, for read rules. Every store
  -- for an active Owner or Admin, the assigned stores for any other active
  -- member of staff, and none for anyone else. user_has_store_access(x) is
  -- the same as "is_owner_or_admin() or x = any (current_user_store_ids())".
  -- A rule asks it once per query: x = any ((select current_user_store_ids())::uuid[]).
  -- One read of profiles and no call to another helper.
  select coalesce((select case when p.role in ('owner', 'admin')
                               then (select array_agg(s.id order by s.id) from public.stores s)
                               else (select array_agg(usa.store_id order by usa.store_id)
                                       from public.user_store_assignments usa
                                      where usa.user_id = p.id)
                          end
                     from public.profiles p
                    where p.id = auth.uid() and p.is_active and p.deleted_at is null
                      and coalesce(p.invitation_status, 'accepted') = 'accepted'),
                  '{}'::uuid[])
$function$
$f$]];
  -- ── Relied on, not changed: signature, md5, from which batch. The batch
  -- lines are one function of each batch that must be live first.
  c_rely constant text[][] := array[
    ['current_user_role()', '519b0a33a3548f970c5d585b6e76a389', '406'],
    ['require_active_staff(text[])', '877b3aa74cea559881979bb161c450e2', '406'],
    ['require_store_access(uuid)', 'f9332fd2f0092337d64501d8a647c23f', '406'],
    ['survey_attachment_store(text)', '58f7d30040f104d240b40ec3e9d9567f', '407'],
    ['stock_history_movement(uuid,uuid,uuid,uuid,uuid,uuid)', 'cb246d3f33256b58e98930058cd14521', '421'],
    ['stock_history_transfer(uuid)', 'ec6fa8b8bd72ec700a6711e7cdba7f8d', '421'],
    ['assert_customer_dob_change(uuid,date,text)', '3d9fc369da08a6baf623f842999f0156', 'batch 418 (B04)'],
    ['can_edit_products()', '9d157e1434cb0c22a833303bbbade8bb', 'batch 420 (B06)'],
    ['audit_module(text,text)', 'daf0c43e9e9578e78048b2f6d7cba57e', 'batch 431 (B14b)'],
    ['invite_user_reusable_login(uuid)', '340580cff28c74eb1b1b8bde967dc8fc', 'batch 429 (B15)'],
    ['close_invoice_therapy_units(uuid,uuid,uuid[],jsonb,numeric,text,uuid,text)', '5d79476632fe31145a903d0f267cfafc', 'batch 417 (B03)'],
    ['claim_legacy_therapy(uuid,date,uuid,jsonb,text,text,boolean)', '164530713b7a52f9b80642bbd0e1ed00', 'batch 422 (B08)'],
    ['create_split_credit_package_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)', 'd9219dc95c3f5f598085161d31744d16', 'batch 423 (B09)'],
    ['exchange_credit_preview(uuid,uuid)', '263bb91b1ed38c6b53767c4d0182595c', 'batch 424 (B10)'],
    ['review_tiktok_settlement_without_order(uuid[],text)', 'a47ecdd18eaaa06bb4c9ca613e8164ed', 'batch 427 (B13)'],
    ['can_view_health_data()', '5cccb54dd99d2c3d77548cd8242ea126', 'batch 419 (B05)'],
    ['decide_referral_signup_check(uuid,text,text)', '9d6fe2fd52a16a845d776b06caca0063', 'batch 425 (B11)'],
    ['update_pending_rental(uuid,integer,special_rate_type,integer,date,date,text)', '1022ecdafb4e1e2f21e7dc051376b028', 'batch 426 (B12)']];
  c_x10 constant text[] := array['invoice_items', 'invoice_revisions', 'invoice_promotion_selections',
                                 'invoice_refunds', 'invoice_credit_splits'];
  -- ── Rules that still ask per row, on purpose: reported, not changed.
  c_left constant text[][] := array[
    ['public', 'purchased_therapy_entitlements', 'read pte', 'B08 (422) built it so; for B08 to change'],
    ['public', 'health_survey_pdfs', 'read survey pdfs', 'B05 (419) built it so; for B05 to change'],
    ['public', 'transfer_requests', 'stock_history_transfer_scope', 'its check takes the row']];
  -- A helper called per row: any of these names not inside "(select ...)".
  c_helpers constant text := 'current_user_role|is_owner_or_manager|is_manager_or_above|is_owner_or_admin|is_owner'
    || '|can_manage_warehouse_stock|can_view_customer_credit|invoice_date_recovery_access|user_admin_role'
    || '|user_has_store_access|stock_history_global|stock_history_location|stock_history_movement'
    || '|stock_history_transfer|current_user_store_ids|can_view_health_data|can_edit_products';
  -- One rule each: schema, table, rule, its md5 as read (BEFORE), the new USING, the
  -- new WITH CHECK, and its md5 as this leaves it (AFTER). md5 of
  -- permissive|roles|cmd|qual|with_check, as pg_policies prints them with search_path public.
  c_pol constant text[][] := array[
    ['public', 'affiliate_account_claims', 'aff_claims_self_read', 'b7c64d635093aceeefd5c0d41176abd9', '((auth_user_id = (select auth.uid())) OR (select public.is_owner_or_manager()))', null, '93f6ee9bdff14855ed8f266480a6b4ec'],
    ['public', 'affiliate_accounts', 'aff_accounts_self_read', 'b7c64d635093aceeefd5c0d41176abd9', '((auth_user_id = (select auth.uid())) OR (select public.is_owner_or_manager()))', null, '93f6ee9bdff14855ed8f266480a6b4ec'],
    ['public', 'approval_requests', 'read approval requests', 'd54f1154986cb004edcfbf12c62d9efd', '(((requested_by = (select auth.uid())) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL)) OR (select public.is_manager_or_above()))', null, 'b6b03e4a6dca020d3b935ef8f6ed0faa'],
    ['public', 'audit_logs', 'read audit logs', '5ec7baf4f60634c6bf7a07ed39ff039f', '(select public.is_manager_or_above())', null, 'f04510e433d3f6364cabf32be22f9367'],
    ['public', 'commission_payouts', 'read payouts', '5ec7baf4f60634c6bf7a07ed39ff039f', '(select public.is_manager_or_above())', null, 'f04510e433d3f6364cabf32be22f9367'],
    ['public', 'commissions', 'read commissions new', '5ec7baf4f60634c6bf7a07ed39ff039f', '(select public.is_manager_or_above())', null, 'f04510e433d3f6364cabf32be22f9367'],
    ['public', 'credit_package_sales', 'read package sales', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'credit_package_spending_rule_history', 'read credit package rule history', '32228a390cfe022aea537e42ce19919a', '(select public.is_owner_or_manager())', null, '5ff7d30139686be7e5cf7aead121b0da'],
    ['public', 'customer_affiliates', 'read affiliates', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'customer_credit_adjustments', 'view customer credit', 'ba3a6dec22bc6ae2ba82a3dffaee4b1f', '(select public.can_view_customer_credit())', null, '1a91235770f9a9a9949f92bbe6823e98'],
    ['public', 'customer_credit_allocations', 'view customer credit', 'ba3a6dec22bc6ae2ba82a3dffaee4b1f', '(select public.can_view_customer_credit())', null, '1a91235770f9a9a9949f92bbe6823e98'],
    ['public', 'customer_credit_ledger', 'view customer credit', 'ba3a6dec22bc6ae2ba82a3dffaee4b1f', '(select public.can_view_customer_credit())', null, '1a91235770f9a9a9949f92bbe6823e98'],
    ['public', 'customer_credit_lots', 'view customer credit', 'ba3a6dec22bc6ae2ba82a3dffaee4b1f', '(select public.can_view_customer_credit())', null, '1a91235770f9a9a9949f92bbe6823e98'],
    ['public', 'customer_credit_statements', 'view customer credit', 'ba3a6dec22bc6ae2ba82a3dffaee4b1f', '(select public.can_view_customer_credit())', null, '1a91235770f9a9a9949f92bbe6823e98'],
    ['public', 'customer_credit_wallets', 'view customer credit', 'ba3a6dec22bc6ae2ba82a3dffaee4b1f', '(select public.can_view_customer_credit())', null, '1a91235770f9a9a9949f92bbe6823e98'],
    ['public', 'customer_phone_history', 'read phone history', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'customer_reward_vouchers', 'read reward vouchers', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'customer_therapy_sessions', 'read therapy sessions', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'customers', 'read customers', '279f6de0074823de4a5331c4cde3cc67', '((deleted_at IS NULL) AND ((select public.current_user_role()) IS NOT NULL))', null, '311ccbdb7e6e076d5e822d9135ae68fe'],
    ['public', 'data_removal_reconciliation', 'read data removal log', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'document_sends', 'read document sends', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'health_survey_attachments', 'read survey attachments', 'a5656f3a878b155c1d96131c89c58ae1', '(((select public.current_user_role()) <> ''inventory_manager''::user_role) AND (EXISTS ( SELECT 1
 FROM health_surveys s
 WHERE ((s.id = health_survey_attachments.survey_id) AND ((select public.is_manager_or_above()) OR ((select public.is_owner_or_admin()) OR (s.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))))', null, '4be43ce57b1fc942f4bf96a25e612556'],
    ['public', 'health_surveys', 'update surveys', '7106cce1fb68708398998da2e709f11f', '(select public.is_owner_or_manager())', '(select public.is_owner_or_manager())', 'dd74f6a05f35c39806c27a3b93751af1'],
    ['public', 'invoice_arrangement_receipts', 'read arrangement receipts', 'e6cf9134bab7fdf0af0d99bd8d3267d0', '(EXISTS ( SELECT 1
 FROM (invoice_payment_arrangements a
 JOIN invoices i ON ((i.id = a.invoice_id)))
 WHERE ((a.id = invoice_arrangement_receipts.arrangement_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, '65849bc2ae112fa9c5b011fd015a0bc4'],
    ['public', 'invoice_benefit_transfers', 'invoice_benefit_transfers_read', 'c9056c0c38700862628f101c91040a04', '(EXISTS ( SELECT 1
 FROM invoices i
 WHERE ((i.id = invoice_benefit_transfers.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, '13cb9d283e75b8e95161db6099be9fd2'],
    ['public', 'invoice_benefit_values', 'invoice_benefit_values_read', 'd10602e2020cd039bb4704f7af3e71ec', '(EXISTS ( SELECT 1
 FROM invoices i
 WHERE ((i.id = invoice_benefit_values.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, '7c0cce72d04fa6c3b6ae8df87b933773'],
    ['public', 'invoice_credit_splits', 'read credit splits', 'fc3de3d18264cf30d81e835dc34521c8', '(EXISTS (SELECT 1 FROM public.invoices i WHERE ((i.id = invoice_credit_splits.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, 'b861c436e0b991c59932291f902b6e33'],
    ['public', 'invoice_date_recovery_batches', 'invoice_date_batch_read', '3f206c42daf03b9ef42a38082c847563', '((select public.invoice_date_recovery_access()) AND (created_by = (select auth.uid())))', null, '73fb3c52dd2d3027c362a18110d28653'],
    ['public', 'invoice_date_recovery_events', 'invoice_date_event_read', 'e5f77935c0160a25d20e687732cdb58b', '((select public.invoice_date_recovery_access()) AND (EXISTS ( SELECT 1
 FROM invoices i
 WHERE ((i.id = invoice_date_recovery_events.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[])))))))', null, '30ace8fc571b71dc03333b18cbb6f76e'],
    ['public', 'invoice_handover_lines', 'invoice_handover_lines_read', '613dd6f3c4d83b91a98b3174e23fa236', '(EXISTS ( SELECT 1
 FROM invoices i
 WHERE ((i.id = invoice_handover_lines.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, 'd6b3a72b7802eb0867483c341ab9888a'],
    ['public', 'invoice_handover_return_lines', 'invoice_handover_return_lines_read', '56d8261c5e620ba10b924ec16f20453f', '(EXISTS ( SELECT 1
 FROM invoices i
 WHERE ((i.id = invoice_handover_return_lines.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, '9f670b20265f8b5d10d0fc3bb586df47'],
    ['public', 'invoice_handovers', 'invoice_handovers_read', 'f651b1d6a998f58ecf1d95ea2c92e5d0', '((select public.is_owner_or_admin()) OR (store_id = ANY ((select public.current_user_store_ids())::uuid[])))', null, 'c6f21b88d0e58c693cb623bd552b51ea'],
    ['public', 'invoice_items', 'read invoice items', 'fc3de3d18264cf30d81e835dc34521c8', '(EXISTS (SELECT 1 FROM public.invoices i WHERE ((i.id = invoice_items.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, '13ac0d3495009f4bc2abc3d3c5c21df8'],
    ['public', 'invoice_line_credit_allocations', 'read line credit allocations', 'ba3a6dec22bc6ae2ba82a3dffaee4b1f', '(select public.can_view_customer_credit())', null, '1a91235770f9a9a9949f92bbe6823e98'],
    ['public', 'invoice_payment_arrangements', 'read invoice payment arrangements', '885994d2cf003f0a25f9637d1366001a', '(EXISTS ( SELECT 1
 FROM invoices i
 WHERE ((i.id = invoice_payment_arrangements.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, 'e18d8d8efed311d2398592258c1bfb8c'],
    ['public', 'invoice_payments', 'read invoice payments', '937e493c6fbb108f567cf0f4be44ec80', '(EXISTS ( SELECT 1
 FROM invoices i
 WHERE ((i.id = invoice_payments.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, '62969c8aa24062aa5f7393cbc7ed7e8a'],
    ['public', 'invoice_promotion_selections', 'read invoice selections', 'fc3de3d18264cf30d81e835dc34521c8', '(EXISTS (SELECT 1 FROM (public.invoice_items it JOIN public.invoices i ON ((i.id = it.invoice_id))) WHERE ((it.id = invoice_promotion_selections.invoice_item_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, 'ab31706e46495d2b08f8f21c79ed06b7'],
    ['public', 'invoice_refunds', 'read refunds', 'fc3de3d18264cf30d81e835dc34521c8', '(EXISTS (SELECT 1 FROM public.invoices i WHERE ((i.id = invoice_refunds.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, 'bb3b65e96aeaa6f7b53b09809ffc52f4'],
    ['public', 'invoice_reopen_benefits', 'reopen_benefits_read', '6080738d8401de837b3942283ed193b4', '(EXISTS ( SELECT 1
 FROM invoices i
 WHERE ((i.id = invoice_reopen_benefits.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, 'c6ed29c5f3711caa8ee506d9884b7872'],
    ['public', 'invoice_reopen_sessions', 'invoice_reopen_sessions_read', '52329c0bc94993a39d5cd322766390b1', '(EXISTS ( SELECT 1
 FROM invoices i
 WHERE ((i.id = invoice_reopen_sessions.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, '6c071d1f4f5c18b5833a8e47988c479c'],
    ['public', 'invoice_reopen_vouchers', 'reopen_vouchers_read', '9ea6f5e050fb559b7e460e3ae2ac6945', '(EXISTS ( SELECT 1
 FROM invoices i
 WHERE ((i.id = invoice_reopen_vouchers.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, 'd5d75fd16f42f228dc4003015e9d4610'],
    ['public', 'invoice_revisions', 'read invoice revisions', 'fc3de3d18264cf30d81e835dc34521c8', '(EXISTS (SELECT 1 FROM public.invoices i WHERE ((i.id = invoice_revisions.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, '92b121a7d93e51e0eee0df9f4085d67f'],
    ['public', 'invoice_service_staff', 'read invoice service staff', 'f3e2e266b672dc485b398ab55292e4a9', '(EXISTS ( SELECT 1
 FROM invoices i
 WHERE ((i.id = invoice_service_staff.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, 'f60d1f50db1e7b0ad6167dfb5f436ca2'],
    ['public', 'invoice_stock_component_rebuilds', 'read stock rebuilds', '7544e9c5fe130c2b55b68abe804cd786', '(EXISTS ( SELECT 1
 FROM invoices i
 WHERE ((i.id = invoice_stock_component_rebuilds.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, 'a5cdd7aeb3e73173c294c5a844be4b56'],
    ['public', 'invoice_stock_components', 'invoice_components_read', '19f898710519e52fae7c6b836bc1fd8f', '(EXISTS ( SELECT 1
 FROM (invoice_items it
 JOIN invoices i ON ((i.id = it.invoice_id)))
 WHERE ((it.id = invoice_stock_components.invoice_item_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, 'd61ad062f9c89f8fcf819a410595ca09'],
    ['public', 'invoice_stock_dispositions', 'invoice_stock_dispositions_read', '8396c69238ba3220ef7bba2607332e71', '(EXISTS ( SELECT 1
 FROM invoices i
 WHERE ((i.id = invoice_stock_dispositions.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, '8919fdb64fb14805de71a16eb5844996'],
    ['public', 'invoice_therapy_session_events', 'invoice_therapy_session_events_read', '3383ae7a5be4983aafd894800e0733ef', '(EXISTS ( SELECT 1
 FROM invoices i
 WHERE ((i.id = invoice_therapy_session_events.invoice_id) AND ((select public.is_owner_or_admin()) OR (i.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, '0bb98ec36804990f013d342e9a038973'],
    ['public', 'invoice_voucher_movements', 'invoice_voucher_movements_read', 'f651b1d6a998f58ecf1d95ea2c92e5d0', '((select public.is_owner_or_admin()) OR (store_id = ANY ((select public.current_user_store_ids())::uuid[])))', null, 'c6f21b88d0e58c693cb623bd552b51ea'],
    ['public', 'invoices', 'read invoices', 'f651b1d6a998f58ecf1d95ea2c92e5d0', '((select public.is_owner_or_admin()) OR (store_id = ANY ((select public.current_user_store_ids())::uuid[])))', null, 'c6f21b88d0e58c693cb623bd552b51ea'],
    ['public', 'premium_bundle_sales', 'read premium bundles', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'product_exchange_items', 'read exchange items', '8c098ad2eba815f8a58afd2b79ad9d14', '(EXISTS ( SELECT 1
 FROM product_exchanges e
 WHERE ((e.id = product_exchange_items.exchange_id) AND ((select public.is_manager_or_above()) OR ((select public.is_owner_or_admin()) OR (e.processing_store_id = ANY ((select public.current_user_store_ids())::uuid[])))))))', null, '2a8056130bb0b6edeac0146fb4760113'],
    ['public', 'product_exchange_payments', 'read exchange payments', 'f464f0ebf9fd5fdc12e2a303a5011a16', '(EXISTS ( SELECT 1
 FROM product_exchanges e
 WHERE ((e.id = product_exchange_payments.exchange_id) AND ((select public.is_manager_or_above()) OR ((select public.is_owner_or_admin()) OR (e.processing_store_id = ANY ((select public.current_user_store_ids())::uuid[])))))))', null, '572301f25c4867660f423679d6030f4b'],
    ['public', 'product_exchange_service_staff', 'read exchange service staff', '6e3d64e6221d562aae7134635504f4e2', '(EXISTS ( SELECT 1
 FROM product_exchanges e
 WHERE ((e.id = product_exchange_service_staff.exchange_id) AND ((select public.is_owner_or_admin()) OR (e.processing_store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, 'a9a9288cf36a69aebc942eed30e4db2d'],
    ['public', 'product_exchanges', 'read exchanges', '8e52ead06f0f40c4857fd3ce9604d50f', '((select public.is_manager_or_above()) OR ((select public.is_owner_or_admin()) OR (processing_store_id = ANY ((select public.current_user_store_ids())::uuid[]))))', null, 'af7bd1fa36e0ac7357cfc2447fe26a90'],
    ['public', 'profiles', 'read profiles', 'a4ceb103cac2934c1aa7ef6d69b86a24', '((id = (select auth.uid())) OR ((select public.current_user_role()) IS NOT NULL))', null, 'd1c60362f48ff8eeb4494283b4f71c31'],
    ['public', 'profiles', 'update profiles', '4e3bce15fd6c881b892fa034dc351056', '(((id = (select auth.uid())) AND ((select public.current_user_role()) IS NOT NULL)) OR (select public.is_owner_or_admin()) OR (((select public.current_user_role()) = ''manager''::user_role) AND (role = ANY (ARRAY[''inventory_manager''::user_role, ''staff''::user_role]))))', '(((id = (select auth.uid())) AND ((select public.current_user_role()) IS NOT NULL)) OR (select public.is_owner_or_admin()) OR (((select public.current_user_role()) = ''manager''::user_role) AND (role = ANY (ARRAY[''inventory_manager''::user_role, ''staff''::user_role]))))', 'e19fdba7b7a8d9a1ed95648b99b74dfb'],
    ['public', 'referral_signup_events', 'aff_events_mgr_read', '32228a390cfe022aea537e42ce19919a', '(select public.is_owner_or_manager())', null, '5ff7d30139686be7e5cf7aead121b0da'],
    ['public', 'rentals', 'read rentals', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'sales_credit_backfill', 'managers read sales credit backfill', '5ec7baf4f60634c6bf7a07ed39ff039f', '(select public.is_manager_or_above())', null, 'f04510e433d3f6364cabf32be22f9367'],
    ['public', 'special_credit_allocations', 'read special credit allocations', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'special_products', 'delete special products', '085e6fea96ad935b6d49b4df04c63225', '(select public.is_owner_or_manager())', null, '46401c445ca86903998080ba908caec1'],
    ['public', 'special_products', 'insert special products', 'dfde55d1737a791710bdd70427aadc8a', null, '(select public.is_owner_or_manager())', '973265359f5b16d9873cf24bdf4d93f4'],
    ['public', 'special_products', 'update special products', '7106cce1fb68708398998da2e709f11f', '(select public.is_owner_or_manager())', '(select public.is_owner_or_manager())', 'dd74f6a05f35c39806c27a3b93751af1'],
    ['public', 'special_sales', 'read special sales', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'staff_commission_payouts', 'read staff payouts', '288c03ad9c8bc0f1321a0af710961156', '((select public.is_manager_or_above()) OR ((staff_id = (select auth.uid())) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL)))', null, '623596db24e1858ed7d431a6f0b3c9b6'],
    ['public', 'staff_commissions', 'read staff commissions', '288c03ad9c8bc0f1321a0af710961156', '((select public.is_manager_or_above()) OR ((staff_id = (select auth.uid())) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL)))', null, '623596db24e1858ed7d431a6f0b3c9b6'],
    ['public', 'stock_loans', 'read stock loans', '19b7a9cc9086f278a07e36636c36bd5f', '((select public.is_manager_or_above()) OR ((store_id IS NOT NULL) AND ((select public.is_owner_or_admin()) OR (store_id = ANY ((select public.current_user_store_ids())::uuid[])))) OR ((warehouse_id IS NOT NULL) AND (select public.can_manage_warehouse_stock())))', null, '5ec4ddcb46a9d0141867b4ff2ff96260'],
    ['public', 'stock_movements', 'read stock movements', 'eaf1d1573634b6e228db68007e8e8c54', '((select public.is_manager_or_above()) OR ((from_store_id IS NOT NULL) AND ((select public.is_owner_or_admin()) OR (from_store_id = ANY ((select public.current_user_store_ids())::uuid[])))) OR ((to_store_id IS NOT NULL) AND ((select public.is_owner_or_admin()) OR (to_store_id = ANY ((select public.current_user_store_ids())::uuid[])))))', null, '122a2cb9365bdf8fdbfa0173481bb692'],
    ['public', 'stock_movements', 'stock_history_read', '86252cf5b693838656d61c0a48898f5f', '((select public.stock_history_global()) OR (from_store_id = ANY ((select public.current_user_store_ids())::uuid[])) OR (to_store_id = ANY ((select public.current_user_store_ids())::uuid[])))', null, '5ee99544e7fd1a52a24aa505219b8201'],
    ['public', 'stock_movements', 'stock_history_scope', '9b880a8bb10f802bf59b8f59a19c08ea', '((select public.stock_history_global()) OR (from_store_id = ANY ((select public.current_user_store_ids())::uuid[])) OR (to_store_id = ANY ((select public.current_user_store_ids())::uuid[])))', null, '2b469e88ffcac929467f3ebeb33f5e34'],
    ['public', 'stock_uses', 'read stock uses', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'store_inventory', 'read store inventory', 'f651b1d6a998f58ecf1d95ea2c92e5d0', '((select public.is_owner_or_admin()) OR (store_id = ANY ((select public.current_user_store_ids())::uuid[])))', null, 'c6f21b88d0e58c693cb623bd552b51ea'],
    ['public', 'store_inventory', 'stock_history_store_scope', 'daaa6db92a7471a461b7cbb8d211d4e0', '((store_id IS NOT NULL) AND ((select public.stock_history_global()) OR (store_id = ANY ((select public.current_user_store_ids())::uuid[]))))', null, '47215170f4dc880b6c47c32537854c55'],
    ['public', 'survey_links', 'read survey links', 'ee2ee037a35844dd9e0fd7ad0aca2ca4', '((select public.is_manager_or_above()) OR ((select public.is_owner_or_admin()) OR (store_id = ANY ((select public.current_user_store_ids())::uuid[]))))', null, 'c5f15237813ac3dddf1d8097c4d3d398'],
    ['public', 'therapy_benefit_choice_history', 'read therapy benefit choice history', 'd84c5c5877253abb3545e1a49f6ffd89', '(EXISTS ( SELECT 1
 FROM purchased_therapy_entitlements p
 WHERE ((p.id = therapy_benefit_choice_history.purchased_entitlement_id) AND ((select public.is_owner_or_admin()) OR (p.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, '7466725e9e55e12377121bdbf8085fdc'],
    ['public', 'therapy_date_change_requests', 'read date changes', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'therapy_entitlement_beneficiaries', 'read beneficiaries', 'bedde57929511ca71c7ff99be052a513', '(EXISTS ( SELECT 1
 FROM therapy_entitlements e
 WHERE ((e.id = therapy_entitlement_beneficiaries.entitlement_id) AND ((select public.is_manager_or_above()) OR ((select public.is_owner_or_admin()) OR (e.store_id = ANY ((select public.current_user_store_ids())::uuid[])))))))', null, 'cb01216018b3519bed9dca402605a967'],
    ['public', 'therapy_entitlement_invoices', 'read ent invoices', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'therapy_entitlements', 'read entitlements', 'ee2ee037a35844dd9e0fd7ad0aca2ca4', '((select public.is_manager_or_above()) OR ((select public.is_owner_or_admin()) OR (store_id = ANY ((select public.current_user_store_ids())::uuid[]))))', null, 'c5f15237813ac3dddf1d8097c4d3d398'],
    ['public', 'therapy_expiry_adjustments', 'read_adjustments', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'therapy_qualification_topups', 'read qual topups', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'therapy_voucher_issues', 'read voucher issues', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'therapy_voucher_unit_changes', 'therapy_voucher_unit_changes_read', '242b41345b9edd1b44e448849214de47', '(EXISTS ( SELECT 1
 FROM customer_reward_vouchers v
 WHERE ((v.id = therapy_voucher_unit_changes.reward_voucher_id) AND ((select public.is_owner_or_admin()) OR (v.store_id = ANY ((select public.current_user_store_ids())::uuid[]))))))', null, '4a3c3f95a249ec29cddcf5ad1fc92ab3'],
    ['public', 'tiktok_corrections', 'read tiktok_corrections', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'tiktok_import_batches', 'read tiktok_import_batches', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'tiktok_order_rows', 'read tiktok_order_rows', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'tiktok_order_state', 'read tiktok_order_state', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'tiktok_physical_returns', 'read tiktok_physical_returns', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'tiktok_settlement_rows', 'read tiktok_settlement_rows', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'tiktok_sku_aliases', 'read tiktok_sku_aliases', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'tiktok_status_mappings', 'read tiktok_status_mappings', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'tiktok_voucher_sales', 'read tiktok_voucher_sales', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'transfer_line_sources', 'read transfer line sources', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'transfer_line_sources', 'stock_history_source_scope', 'be5c7ee1479b847d798d35cc7824001c', '((select public.stock_history_global()) OR ((source_id IS NOT NULL) AND ((select public.stock_history_global()) OR (((source_type)::text = ''store''::text) AND (source_id = ANY ((select public.current_user_store_ids())::uuid[]))))) OR (EXISTS ( SELECT 1
 FROM (transfer_request_lines l
 JOIN transfer_requests r ON ((r.id = l.transfer_request_id)))
 WHERE ((l.id = transfer_line_sources.line_id) AND ((r.dest_id IS NOT NULL) AND ((select public.stock_history_global()) OR (((r.dest_type)::text = ''store''::text) AND (r.dest_id = ANY ((select public.current_user_store_ids())::uuid[])))))))))', null, '4d9a0f4533129dfbc5cff13c0ab9319b'],
    ['public', 'transfer_request_lines', 'read transfer lines', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'transfer_request_lines', 'stock_history_line_scope', '5f76039e8196f498f45c3a20a0abcd28', '((select public.stock_history_global()) OR (EXISTS ( SELECT 1
 FROM transfer_requests r
 WHERE ((r.id = transfer_request_lines.transfer_request_id) AND ((r.dest_id IS NOT NULL) AND ((select public.stock_history_global()) OR (((r.dest_type)::text = ''store''::text) AND (r.dest_id = ANY ((select public.current_user_store_ids())::uuid[])))))))))', null, 'd4ec3b47d4a7352b9cca112515c9b9f7'],
    ['public', 'transfer_request_revisions', 'stock_history_revision_scope', '2c668e8d868dc8fa1b4da39cc0f4388c', '(select public.stock_history_global())', null, '43b22771e623f129fefd18a9b6536a6b'],
    ['public', 'user_invitations', 'user admins read invitations', '7e024934620579138b88d94392e1b57b', '((select public.user_admin_role()) IS NOT NULL)', null, 'a73e5dcf1b3bceb24a7a00e7679f40df'],
    ['public', 'user_store_assignments', 'read assignments', 'fc3de3d18264cf30d81e835dc34521c8', '((select public.current_user_role()) IS NOT NULL)', null, '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'voucher_claims', 'read voucher claims', 'f651b1d6a998f58ecf1d95ea2c92e5d0', '((select public.is_owner_or_admin()) OR (store_id = ANY ((select public.current_user_store_ids())::uuid[])))', null, 'c6f21b88d0e58c693cb623bd552b51ea'],
    ['public', 'warehouse_inventory', 'stock_history_warehouse_scope', '89b28128f63847971d18e0c0ea20e57a', '((warehouse_id IS NOT NULL) AND (select public.stock_history_global()))', null, '89e1017734989ff5fe9980640d461724'],
    ['storage', 'objects', 'invoice pdfs delete', 'a6337f1bcc11fa32a704932f2b98c1ad', '((bucket_id = ''invoice-pdfs''::text) AND (select public.is_owner_or_manager()))', null, 'f1482b061008c4717513615730dac45b'],
    ['storage', 'objects', 'invoice pdfs insert', '6e1b8ed84ad19f9ad4402b77b1bd8fb7', null, '((bucket_id = ''invoice-pdfs''::text) AND ((select public.is_manager_or_above()) OR ((select public.is_owner_or_admin()) OR (survey_attachment_store(name) = ANY ((select public.current_user_store_ids())::uuid[])))))', '83d2f462a716e373b72c46811bc7275b'],
    ['storage', 'objects', 'invoice pdfs read', 'c601fc5e438016a9a0f40765fb14072c', '((bucket_id = ''invoice-pdfs''::text) AND ((select public.is_manager_or_above()) OR ((select public.is_owner_or_admin()) OR (survey_attachment_store(name) = ANY ((select public.current_user_store_ids())::uuid[])))))', null, 'e7667ce6cc530a7b28a0097b68211210'],
    ['storage', 'objects', 'invoice pdfs update', '14cf8cd103b95d7b54dc9cabf4f96b41', '((bucket_id = ''invoice-pdfs''::text) AND (select public.is_owner_or_manager()))', '((bucket_id = ''invoice-pdfs''::text) AND (select public.is_owner_or_manager()))', '33f0c1d2d1f63aaa2f74aed566c2cc98'],
    ['storage', 'objects', 'store-assets delete', 'd942105788a0d09ef4e8448335ff4d77', '((bucket_id = ''store-assets''::text) AND (select public.is_owner_or_manager()))', null, 'fee979ca6a98c792274fcd8bb9cdc810'],
    ['storage', 'objects', 'store-assets update', '984ac2e4d8ced183078744a76f0bda07', '((bucket_id = ''store-assets''::text) AND (select public.is_owner_or_manager()))', null, 'b84700c3e65b94ba7dbc8c053bd55678'],
    ['storage', 'objects', 'store-assets write', '244d10bd554f97556766427140e1f40f', null, '((bucket_id = ''store-assets''::text) AND (select public.is_owner_or_manager()))', 'e1fbe7e89a271c224525c7f20aa3c31f'],
    ['storage', 'objects', 'survey-attachments delete', '83c677bdd5dc974c90ff36c2d8465648', '((bucket_id = ''survey-attachments''::text) AND (select public.is_owner_or_manager()))', null, '8be7eb341ccc53fbf832cb37e72cac83'],
    ['storage', 'objects', 'survey-attachments read', '8e8f454d2516f3fc139803f28b080acd', '((bucket_id = ''survey-attachments''::text) AND ((select public.current_user_role()) <> ''inventory_manager''::user_role) AND ((select public.is_manager_or_above()) OR ((select public.is_owner_or_admin()) OR (survey_attachment_store(name) = ANY ((select public.current_user_store_ids())::uuid[])))))', null, '6634d1edee48089748bdbf5186dd6242'],
    ['storage', 'objects', 'survey-attachments update', '7571d306a51137094c07b165b2d81d78', '((bucket_id = ''survey-attachments''::text) AND (select public.is_owner_or_manager()))', null, 'fd68b090fbaeb174d957b89ef54edcae'],
    ['storage', 'objects', 'survey-attachments write', '3a34005a25badc58b7e806e5caedbb8a', null, '((bucket_id = ''survey-attachments''::text) AND (select public.is_owner_or_manager()))', '51ef76599c4e6e4ff3ccaecbbaef4c0e'],
    ['public', 'promotions', 'read promotions', '311ccbdb7e6e076d5e822d9135ae68fe', '(((deleted_at IS NULL) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL)) OR (select public.is_owner_or_manager()))', null, 'd9a95a2e534d11870f0ba0474f3d9ebb'],
    ['public', 'vouchers', 'read vouchers', '311ccbdb7e6e076d5e822d9135ae68fe', '(((deleted_at IS NULL) AND (( SELECT current_user_role() AS current_user_role) IS NOT NULL)) OR (select public.is_owner_or_manager()))', null, 'd9a95a2e534d11870f0ba0474f3d9ebb']];
  -- The "manage" rules that also answered every read: table, rule, md5 as read, and
  -- the three rules that replace it, each with its USING / WITH CHECK and AFTER md5.
  c_split constant text[][] := array[
    ['brands', 'brands write', '6c9fac5a21cd465c163da8a57ae98763', '(select public.is_owner_or_manager())', '(select public.is_owner_or_manager())', 'brands insert', '973265359f5b16d9873cf24bdf4d93f4', 'brands update', 'dd74f6a05f35c39806c27a3b93751af1', 'brands delete', '46401c445ca86903998080ba908caec1'],
    ['categories', 'categories write', '6c9fac5a21cd465c163da8a57ae98763', '(select public.is_owner_or_manager())', '(select public.is_owner_or_manager())', 'categories insert', '973265359f5b16d9873cf24bdf4d93f4', 'categories update', 'dd74f6a05f35c39806c27a3b93751af1', 'categories delete', '46401c445ca86903998080ba908caec1'],
    ['health_symptom_options', 'write symptom options', '6c9fac5a21cd465c163da8a57ae98763', '(select public.is_owner_or_manager())', '(select public.is_owner_or_manager())', 'insert symptom options', '973265359f5b16d9873cf24bdf4d93f4', 'update symptom options', 'dd74f6a05f35c39806c27a3b93751af1', 'delete symptom options', '46401c445ca86903998080ba908caec1'],
    ['payment_methods', 'manage payment methods', '6c9fac5a21cd465c163da8a57ae98763', '(select public.is_owner_or_manager())', '(select public.is_owner_or_manager())', 'insert payment methods', '973265359f5b16d9873cf24bdf4d93f4', 'update payment methods', 'dd74f6a05f35c39806c27a3b93751af1', 'delete payment methods', '46401c445ca86903998080ba908caec1'],
    ['promotion_choice_groups', 'manage choice groups', '6c9fac5a21cd465c163da8a57ae98763', '(select public.is_owner_or_manager())', '(select public.is_owner_or_manager())', 'insert choice groups', '973265359f5b16d9873cf24bdf4d93f4', 'update choice groups', 'dd74f6a05f35c39806c27a3b93751af1', 'delete choice groups', '46401c445ca86903998080ba908caec1'],
    ['promotion_choice_options', 'manage choice options', '6c9fac5a21cd465c163da8a57ae98763', '(select public.is_owner_or_manager())', '(select public.is_owner_or_manager())', 'insert choice options', '973265359f5b16d9873cf24bdf4d93f4', 'update choice options', 'dd74f6a05f35c39806c27a3b93751af1', 'delete choice options', '46401c445ca86903998080ba908caec1'],
    ['promotion_items', 'manage promotion items', '6c9fac5a21cd465c163da8a57ae98763', '(select public.is_owner_or_manager())', '(select public.is_owner_or_manager())', 'insert promotion items', '973265359f5b16d9873cf24bdf4d93f4', 'update promotion items', 'dd74f6a05f35c39806c27a3b93751af1', 'delete promotion items', '46401c445ca86903998080ba908caec1'],
    ['promotion_store_prices', 'write promotion prices', '6c9fac5a21cd465c163da8a57ae98763', '(select public.is_owner_or_manager())', '(select public.is_owner_or_manager())', 'insert promotion prices', '973265359f5b16d9873cf24bdf4d93f4', 'update promotion prices', 'dd74f6a05f35c39806c27a3b93751af1', 'delete promotion prices', '46401c445ca86903998080ba908caec1'],
    ['promotions', 'manage promotions', '6c9fac5a21cd465c163da8a57ae98763', '(select public.is_owner_or_manager())', '(select public.is_owner_or_manager())', 'insert promotions', '973265359f5b16d9873cf24bdf4d93f4', 'update promotions', 'dd74f6a05f35c39806c27a3b93751af1', 'delete promotions', '46401c445ca86903998080ba908caec1'],
    ['store_product_prices', 'manage store prices', '6c9fac5a21cd465c163da8a57ae98763', '(select public.is_owner_or_manager())', '(select public.is_owner_or_manager())', 'insert store prices', '973265359f5b16d9873cf24bdf4d93f4', 'update store prices', 'dd74f6a05f35c39806c27a3b93751af1', 'delete store prices', '46401c445ca86903998080ba908caec1'],
    ['suppliers', 'suppliers write', '6c9fac5a21cd465c163da8a57ae98763', '(select public.is_owner_or_manager())', '(select public.is_owner_or_manager())', 'suppliers insert', '973265359f5b16d9873cf24bdf4d93f4', 'suppliers update', 'dd74f6a05f35c39806c27a3b93751af1', 'suppliers delete', '46401c445ca86903998080ba908caec1'],
    ['survey_links', 'write survey links', '6c9fac5a21cd465c163da8a57ae98763', '(select public.is_owner_or_manager())', '(select public.is_owner_or_manager())', 'insert survey links', '973265359f5b16d9873cf24bdf4d93f4', 'update survey links', 'dd74f6a05f35c39806c27a3b93751af1', 'delete survey links', '46401c445ca86903998080ba908caec1'],
    ['voucher_store_prices', 'write voucher prices', '6c9fac5a21cd465c163da8a57ae98763', '(select public.is_owner_or_manager())', '(select public.is_owner_or_manager())', 'insert voucher prices', '973265359f5b16d9873cf24bdf4d93f4', 'update voucher prices', 'dd74f6a05f35c39806c27a3b93751af1', 'delete voucher prices', '46401c445ca86903998080ba908caec1'],
    ['voucher_store_stock', 'manage voucher stock', '6c9fac5a21cd465c163da8a57ae98763', '(select public.is_owner_or_manager())', '(select public.is_owner_or_manager())', 'insert voucher stock', '973265359f5b16d9873cf24bdf4d93f4', 'update voucher stock', 'dd74f6a05f35c39806c27a3b93751af1', 'delete voucher stock', '46401c445ca86903998080ba908caec1'],
    ['vouchers', 'manage vouchers', '6c9fac5a21cd465c163da8a57ae98763', '(select public.is_owner_or_manager())', '(select public.is_owner_or_manager())', 'insert vouchers', '973265359f5b16d9873cf24bdf4d93f4', 'update vouchers', 'dd74f6a05f35c39806c27a3b93751af1', 'delete vouchers', '46401c445ca86903998080ba908caec1']];
  -- Rules left exactly as they are (another batch's, or nothing to change):
  -- schema, table, rule, md5. A rule not named here or above stops the migration.
  c_keep constant text[][] := array[
    ['public', 'app_settings', 'read settings', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'brands', 'brands read', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'categories', 'categories read', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'consultant_notes', 'read consultant notes', 'd6f1ba03f7572d5824cccdd4c3f501b3'],
    ['public', 'credit_package_spending_rules', 'read credit package spending rules', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'credit_package_split_allocations', 'read split allocations', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'credit_package_split_groups', 'read split groups', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'credit_package_stores', 'read credit packages', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'credit_package_vouchers', 'read credit packages', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'credit_packages', 'read credit packages', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'customer_remarks', 'read customer remarks', 'd6f1ba03f7572d5824cccdd4c3f501b3'],
    ['public', 'customer_source_options', 'read source options', '58d828e82c60408ffeb03a96154117f6'],
    ['public', 'foc_reasons', 'read foc reasons', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'health_survey_pdfs', 'read survey pdfs', '0cd2aa4d2fb1c3c55b259d432b8f4608'],
    ['public', 'health_survey_symptoms', 'read survey symptoms', 'd6f1ba03f7572d5824cccdd4c3f501b3'],
    ['public', 'health_surveys', 'read surveys', 'd6f1ba03f7572d5824cccdd4c3f501b3'],
    ['public', 'health_symptom_options', 'read symptom options', 'fbb2b368e7e449e332843c862514fbcd'],
    ['public', 'payment_methods', 'read payment methods', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'premium_bundle_split_allocations', 'read bundle split allocations', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'premium_bundle_split_groups', 'read bundle split groups', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'premium_bundle_stores', 'read premium bundles', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'premium_bundle_vouchers', 'read premium bundles', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'premium_bundles', 'read premium bundles', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'product_categories', 'product_categories read', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'product_categories', 'product_categories write', '2ad26ae72ebcbc9c0fa07c436cdd68b1'],
    ['public', 'product_suppliers', 'product_suppliers read', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'product_suppliers', 'product_suppliers write', '2ad26ae72ebcbc9c0fa07c436cdd68b1'],
    ['public', 'products', 'insert products', 'edfdba66ff98f4fd5b7629a986b8f782'],
    ['public', 'products', 'read products', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'products', 'update products', 'df954f111126a29facb6f7af40e34eb6'],
    ['public', 'promotion_choice_groups', 'read choice groups', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'promotion_choice_options', 'read choice options', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'promotion_items', 'read promotion items', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'promotion_store_prices', 'read promotion prices', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'purchased_therapy_entitlements', 'read pte', '7d837f08a358ad0b5ea9b33181419bd5'],
    ['public', 'special_product_stock', 'read special stock', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'special_products', 'read special products', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'stock_loan_events', 'read stock loan events', '8cd6fcbf33c01bbda6db89256b3585da'],
    ['public', 'stock_loan_lines', 'read stock loan lines', '3b09b3abec886e01a7ce0e7934ec5a0d'],
    ['public', 'store_inventory', 'managers read store inventory', 'f04510e433d3f6364cabf32be22f9367'],
    ['public', 'store_product_prices', 'read store prices', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'stores', 'insert stores', '973265359f5b16d9873cf24bdf4d93f4'],
    ['public', 'stores', 'read stores', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'stores', 'update stores', 'dd74f6a05f35c39806c27a3b93751af1'],
    ['public', 'suppliers', 'suppliers read', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'therapy_calendar_coverage', 'read_coverage', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'therapy_closure_dates', 'read_closures', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'therapy_holiday_countries', 'read_countries', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'therapy_package_rules', 'read therapy rules', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'therapy_package_services', 'read therapy package services', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'therapy_package_vouchers', 'read therapy package vouchers', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'therapy_service_stores', 'read service stores', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'therapy_services', 'read services', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'therapy_voucher_component_services', 'read voucher component services', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'therapy_voucher_components', 'read voucher components', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'therapy_voucher_definitions', 'read voucher definitions', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'transfer_request_revisions', 'read transfer revisions', 'fc472d4d7f3823a7cdfd10aed521bfa6'],
    ['public', 'transfer_requests', 'read transfer requests', 'fc472d4d7f3823a7cdfd10aed521bfa6'],
    ['public', 'transfer_requests', 'stock_history_transfer_scope', '2afe082d2990589f0c0c882705e9c553'],
    ['public', 'unlimited_therapy_packages', 'read utp', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'unlimited_therapy_store_prices', 'read utsp', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'voucher_redemptions', 'read voucher redemptions', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'voucher_store_prices', 'read voucher prices', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'voucher_store_stock', 'read voucher stock', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'warehouse_inventory', 'read warehouse inventory', 'fc472d4d7f3823a7cdfd10aed521bfa6'],
    ['public', 'warehouses', 'insert warehouses', '973265359f5b16d9873cf24bdf4d93f4'],
    ['public', 'warehouses', 'read warehouses', '2f9e57ec8d25e270aa347b49e262c598'],
    ['public', 'warehouses', 'update warehouses', 'dd74f6a05f35c39806c27a3b93751af1'],
    ['storage', 'objects', 'store-assets read', 'c71ca5ab442adee9e25b42068745c1e2']];
  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_fn_todo boolean[] := '{}';
  v_pol_todo boolean[] := '{}';
  v_split_todo boolean[] := '{}';
  v_known text[] := '{}';
  v_md5 text; v_md5b text; v_md5c text; v_md5d text; v_bad text; v_plan text; v_text text;
  i int; j int; n bigint; n2 bigint; r record; v_owner uuid;
begin
  perform set_config('search_path', 'public', true);

  -- ── Guards: nothing changes unless all pass ──────────────────────────────
  for i in 1 .. array_length(c_rely, 1) loop
    if to_regprocedure('public.' || c_rely[i][1]) is null
       or md5(pg_get_functiondef(('public.' || c_rely[i][1])::regprocedure)) <> c_rely[i][2] then
      raise exception '430: public.% is not as % leaves it. 430 goes in last, after every other batch', c_rely[i][1], c_rely[i][3];
    end if;
  end loop;

  for i in 1 .. array_length(c_fn, 1) loop
    if md5(c_fn[i][4]) <> c_fn[i][3] then
      raise exception '430: the text for public.% is not the one tested (md5 %)', c_fn[i][1], md5(c_fn[i][4]); end if;
    if to_regprocedure('public.' || c_fn[i][1]) is null then
      if c_fn[i][2] is not null then
        raise exception '430: public.% is missing', c_fn[i][1]; end if;
      if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                  and p.proname = split_part(c_fn[i][1], '(', 1)) then
        raise exception '430: another function is already called public.%', split_part(c_fn[i][1], '(', 1); end if;
      v_fn_todo := v_fn_todo || true;
    else
      v_md5 := md5(pg_get_functiondef(('public.' || c_fn[i][1])::regprocedure));
      if v_md5 = c_fn[i][3] then
        v_fn_todo := v_fn_todo || false;
      elsif v_md5 = c_fn[i][2] then
        v_fn_todo := v_fn_todo || true;
      else
        raise exception '430: public.% is not the version read on 18 Oct 2026 (md5 %)', c_fn[i][1], v_md5;
      end if;
    end if;
  end loop;

  for i in 1 .. array_length(c_pol, 1) loop
    v_md5 := null;
    select md5(p.permissive || '|' || array_to_string(p.roles, ',') || '|' || p.cmd || '|'
               || coalesce(p.qual, '') || '|' || coalesce(p.with_check, ''))
      into v_md5 from pg_policies p
     where p.schemaname = c_pol[i][1] and p.tablename = c_pol[i][2] and p.policyname = c_pol[i][3];
    if v_md5 is null then
      raise exception '430: the rule "%" on %.% is missing', c_pol[i][3], c_pol[i][1], c_pol[i][2];
    elsif v_md5 = c_pol[i][7] then
      v_pol_todo := v_pol_todo || false;
    elsif v_md5 = c_pol[i][4] then
      v_pol_todo := v_pol_todo || true;
    else
      raise exception '430: the rule "%" on %.% is not the one read after every batch (md5 %)',
        c_pol[i][3], c_pol[i][1], c_pol[i][2], v_md5;
    end if;
    v_known := v_known || (c_pol[i][1] || '|' || c_pol[i][2] || '|' || c_pol[i][3]);
  end loop;

  for i in 1 .. array_length(c_split, 1) loop
    select md5(p.permissive || '|' || array_to_string(p.roles, ',') || '|' || p.cmd || '|'
               || coalesce(p.qual, '') || '|' || coalesce(p.with_check, '')) into v_md5
      from pg_policies p where p.schemaname = 'public' and p.tablename = c_split[i][1] and p.policyname = c_split[i][2];
    select md5(p.permissive || '|' || array_to_string(p.roles, ',') || '|' || p.cmd || '|'
               || coalesce(p.qual, '') || '|' || coalesce(p.with_check, '')) into v_md5b
      from pg_policies p where p.schemaname = 'public' and p.tablename = c_split[i][1] and p.policyname = c_split[i][6];
    select md5(p.permissive || '|' || array_to_string(p.roles, ',') || '|' || p.cmd || '|'
               || coalesce(p.qual, '') || '|' || coalesce(p.with_check, '')) into v_md5c
      from pg_policies p where p.schemaname = 'public' and p.tablename = c_split[i][1] and p.policyname = c_split[i][8];
    select md5(p.permissive || '|' || array_to_string(p.roles, ',') || '|' || p.cmd || '|'
               || coalesce(p.qual, '') || '|' || coalesce(p.with_check, '')) into v_md5d
      from pg_policies p where p.schemaname = 'public' and p.tablename = c_split[i][1] and p.policyname = c_split[i][10];
    if v_md5 = c_split[i][3] and v_md5b is null and v_md5c is null and v_md5d is null then
      v_split_todo := v_split_todo || true;
    elsif v_md5 is null and v_md5b = c_split[i][7] and v_md5c = c_split[i][9] and v_md5d = c_split[i][11] then
      v_split_todo := v_split_todo || false;
    else
      raise exception '430: the rule "%" on public.% is not the one read after every batch, nor split as tested',
        c_split[i][2], c_split[i][1];
    end if;
    v_md5 := null; v_md5b := null; v_md5c := null; v_md5d := null;
    v_known := v_known || array['public|' || c_split[i][1] || '|' || c_split[i][2],
                                'public|' || c_split[i][1] || '|' || c_split[i][6],
                                'public|' || c_split[i][1] || '|' || c_split[i][8],
                                'public|' || c_split[i][1] || '|' || c_split[i][10]];
  end loop;

  for i in 1 .. array_length(c_keep, 1) loop
    v_md5 := null;
    select md5(p.permissive || '|' || array_to_string(p.roles, ',') || '|' || p.cmd || '|'
               || coalesce(p.qual, '') || '|' || coalesce(p.with_check, ''))
      into v_md5 from pg_policies p
     where p.schemaname = c_keep[i][1] and p.tablename = c_keep[i][2] and p.policyname = c_keep[i][3];
    if v_md5 is distinct from c_keep[i][4] then
      raise exception '430: the rule "%" on %.% is not the one read after every batch (md5 %)',
        c_keep[i][3], c_keep[i][1], c_keep[i][2], coalesce(v_md5, 'missing'); end if;
    v_known := v_known || (c_keep[i][1] || '|' || c_keep[i][2] || '|' || c_keep[i][3]);
  end loop;

  select string_agg(p.schemaname || '.' || p.tablename || ' "' || p.policyname || '"', ', ' order by 1) into v_bad
    from pg_policies p
   where p.schemaname in ('public', 'storage')
     and not ((p.schemaname || '|' || p.tablename || '|' || p.policyname) = any (v_known));
  if v_bad is not null then
    raise exception '430: rules it has not seen (a batch not yet live, or a later change): %', v_bad; end if;

  foreach v_text in array c_x10 loop
    if not exists (select 1 from pg_class c where c.oid = to_regclass('public.' || v_text) and c.relrowsecurity) then
      raise exception '430: public.% is missing or has row-level security off', v_text; end if;
  end loop;

  -- ── Change ───────────────────────────────────────────────────────────────
  for i in 1 .. array_length(c_fn, 1) loop
    if v_fn_todo[i] then execute c_fn[i][4]; end if;
  end loop;
  revoke all on function public.current_user_store_ids() from public, anon;
  grant execute on function public.current_user_store_ids() to authenticated, service_role;

  for i in 1 .. array_length(c_pol, 1) loop
    if v_pol_todo[i] then
      if c_pol[i][5] is not null and c_pol[i][6] is not null then
        execute format('alter policy %I on %I.%I using (%s) with check (%s)',
                       c_pol[i][3], c_pol[i][1], c_pol[i][2], c_pol[i][5], c_pol[i][6]);
      elsif c_pol[i][5] is not null then
        execute format('alter policy %I on %I.%I using (%s)', c_pol[i][3], c_pol[i][1], c_pol[i][2], c_pol[i][5]);
      else
        execute format('alter policy %I on %I.%I with check (%s)', c_pol[i][3], c_pol[i][1], c_pol[i][2], c_pol[i][6]);
      end if;
    end if;
  end loop;

  for i in 1 .. array_length(c_split, 1) loop
    if v_split_todo[i] then
      execute format('drop policy %I on public.%I', c_split[i][2], c_split[i][1]);
      execute format('create policy %I on public.%I for insert to authenticated with check (%s)',
                     c_split[i][6], c_split[i][1], c_split[i][5]);
      execute format('create policy %I on public.%I for update to authenticated using (%s) with check (%s)',
                     c_split[i][8], c_split[i][1], c_split[i][4], c_split[i][5]);
      execute format('create policy %I on public.%I for delete to authenticated using (%s)',
                     c_split[i][10], c_split[i][1], c_split[i][4]);
    end if;
  end loop;

  revoke all on table public.invoice_items, public.invoice_revisions, public.invoice_promotion_selections,
    public.invoice_refunds, public.invoice_credit_splits from anon;
  revoke insert, update, delete, truncate, references, trigger, maintain
    on table public.invoice_items, public.invoice_revisions, public.invoice_promotion_selections,
             public.invoice_refunds, public.invoice_credit_splits from authenticated;

  -- ── As tested ────────────────────────────────────────────────────────────
  for i in 1 .. array_length(c_fn, 1) loop
    if md5(pg_get_functiondef(('public.' || c_fn[i][1])::regprocedure)) <> c_fn[i][3]
       or (select p.provolatile from pg_proc p where p.oid = ('public.' || c_fn[i][1])::regprocedure) <> 's'
       or has_function_privilege('anon', ('public.' || c_fn[i][1])::regprocedure, 'execute')
       or not has_function_privilege('service_role', ('public.' || c_fn[i][1])::regprocedure, 'execute')
       or has_function_privilege('authenticated', ('public.' || c_fn[i][1])::regprocedure, 'execute')
          <> (c_fn[i][1] <> 'is_owner()') then
      raise exception '430: public.% is not as tested (text, STABLE or grants)', c_fn[i][1]; end if;
  end loop;

  for i in 1 .. array_length(c_pol, 1) loop
    select md5(p.permissive || '|' || array_to_string(p.roles, ',') || '|' || p.cmd || '|'
               || coalesce(p.qual, '') || '|' || coalesce(p.with_check, ''))
      into v_md5 from pg_policies p
     where p.schemaname = c_pol[i][1] and p.tablename = c_pol[i][2] and p.policyname = c_pol[i][3];
    if v_md5 is distinct from c_pol[i][7] then
      raise exception '430: the rule "%" on %.% is not as tested (md5 %)', c_pol[i][3], c_pol[i][1], c_pol[i][2], v_md5; end if;
  end loop;
  for i in 1 .. array_length(c_split, 1) loop
    if exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c_split[i][1]
                and p.policyname = c_split[i][2]) then
      raise exception '430: the rule "%" on public.% is still there', c_split[i][2], c_split[i][1]; end if;
    for j in 0 .. 2 loop
      select md5(p.permissive || '|' || array_to_string(p.roles, ',') || '|' || p.cmd || '|'
                 || coalesce(p.qual, '') || '|' || coalesce(p.with_check, ''))
        into v_md5 from pg_policies p
       where p.schemaname = 'public' and p.tablename = c_split[i][1] and p.policyname = c_split[i][6 + 2 * j];
      if v_md5 is distinct from c_split[i][7 + 2 * j] then
        raise exception '430: the rule "%" on public.% is not as tested', c_split[i][6 + 2 * j], c_split[i][1]; end if;
    end loop;
  end loop;
  for i in 1 .. array_length(c_keep, 1) loop
    select md5(p.permissive || '|' || array_to_string(p.roles, ',') || '|' || p.cmd || '|'
               || coalesce(p.qual, '') || '|' || coalesce(p.with_check, ''))
      into v_md5 from pg_policies p
     where p.schemaname = c_keep[i][1] and p.tablename = c_keep[i][2] and p.policyname = c_keep[i][3];
    if v_md5 is distinct from c_keep[i][4] then
      raise exception '430: the rule "%" on %.% changed', c_keep[i][3], c_keep[i][1], c_keep[i][2]; end if;
  end loop;

  -- The sweep: no rule in public or storage calls a helper per row, but the
  -- three named in c_left (reported).
  for r in
    select p.schemaname s, p.tablename t, p.policyname pol
      from pg_policies p
     where p.schemaname in ('public', 'storage')
       and (regexp_replace(coalesce(p.qual, '') || ' ' || coalesce(p.with_check, ''),
                           '\( SELECT [a-z_.]+\(\) AS [a-z_]+\)', '', 'g')
              ~ ('(^|[^a-z_.])(' || c_helpers || ')\(')
            or regexp_replace(coalesce(p.qual, '') || ' ' || coalesce(p.with_check, ''),
                              '\( SELECT [a-z_.]+\(\) AS [a-z_]+\)', '', 'g') ~ 'auth\.uid\(\)')
     order by 1, 2, 3
  loop
    if exists (select 1 from generate_subscripts(c_left, 1) k
                where c_left[k][1] = r.s and c_left[k][2] = r.t and c_left[k][3] = r.pol) then
      raise notice '430: left as it is, still asks per row: %.% "%"', r.s, r.t, r.pol;
    else
      raise exception '430: the rule "%" on %.% still asks per row', r.pol, r.s, r.t;
    end if;
  end loop;

  foreach v_text in array c_x10 loop
    if has_table_privilege('anon', 'public.' || v_text, 'select,insert,update,delete,truncate,references,trigger,maintain')
       or has_table_privilege('authenticated', 'public.' || v_text, 'insert,update,delete,truncate,references,trigger,maintain')
       or not has_table_privilege('authenticated', 'public.' || v_text, 'select')
       or not has_table_privilege('service_role', 'public.' || v_text, 'select,insert,update,delete') then
      raise exception '430: the grants on public.% are not as tested', v_text; end if;
  end loop;

  -- ── Behaviour, switching role (nothing is printed, no row changes) ───────
  perform set_config('request.jwt.claims',
    json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  if public.current_user_store_ids() <> '{}'::uuid[] or public.user_has_store_access(gen_random_uuid())
     or public.is_owner_or_manager() or public.is_manager_or_above() or public.is_owner_or_admin()
     or public.can_manage_warehouse_stock() or public.can_view_customer_credit()
     or public.stock_history_global() then
    raise exception '430: a login with no profile still passes a helper'; end if;
  foreach v_text in array c_x10 loop
    execute format('select count(*) from public.%I', v_text) into n;
    if n > 0 then raise exception '430: a login with no profile still reads public.%', v_text; end if;
    v_plan := '';
    for r in execute format('explain (costs off) select count(*) from public.%I', v_text) loop
      v_plan := v_plan || r."QUERY PLAN" || E'\n';
    end loop;
    if v_plan !~ 'InitPlan' then
      raise exception '430: the read of public.% is not planned with InitPlans', v_text; end if;
  end loop;
  execute 'reset role';

  select p.id into v_owner from public.profiles p
   where p.role = 'owner' and p.is_active and p.deleted_at is null
     and coalesce(p.invitation_status, 'accepted') = 'accepted'
   order by p.created_at limit 1;
  if v_owner is not null then
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    foreach v_text in array c_x10 || array['stock_movements'] loop
      execute format('select count(*) from public.%I', v_text) into n2;
      execute 'set local role authenticated';
      execute format('select count(*) from public.%I', v_text) into n;
      execute 'reset role';
      if n <> n2 then raise exception '430: an Owner no longer reads every row of public.%', v_text; end if;
    end loop;
    execute 'set local role authenticated';
    if not public.user_has_store_access((select s.id from public.stores s order by s.id limit 1))
       or cardinality(public.current_user_store_ids()) <> (select count(*) from public.stores) then
      raise exception '430: an Owner no longer works at every store'; end if;
    execute 'reset role';
  end if;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
