-- 535_only_an_owner_changes_commission_rates_and_an_invoice_keeps_its_own.sql
--
-- ONLY AN OWNER CHANGES THE COMMISSION RATES; AN INVOICE KEEPS THE AFFILIATE RATES IT FIRST
-- EARNED AT; A PACKAGE'S OR BUNDLE'S OWN RATES ARE 0 TO 100 AND THE OWNER'S; THE STAFF
-- COMMISSION REBASE AND RATE CHANGE ARE CLOSED TO LOGINS
--
--   From the security audit of 17 Nov 2026 (finding M12).
--   The BEFORE md5s and the relied-on md5s below are those of production after 537 (530 to 534,
--   536 and 537 live since 24 and 25 Nov 2026, head 20261125065257, function fingerprint
--   7d78ee9e7cb23337dbc64e6a478dffb1/1448; they equal those after 529: 530 to 534, 536 and 537
--   change none of these functions or tables). If production differs when this is applied, it
--   refuses and changes nothing. 536 changed only audit_logs' grants and triggers and who may
--   EXECUTE write_audit and write_audit_ex (their text, pinned below, is unchanged); every
--   function here that writes an audit row runs as its owner, postgres, so 536 does not touch
--   them. It applies the same with or without 537. It needs 532 (it extends 532's
--   trg_audit_direct_change), so not on 529 alone.
--   (The number 535 is this file's name and its errors' prefix; if it changes at commit, change
--   it there, in the 535 comments it writes into the functions below (and so their AFTER md5s,
--   also in scripts/commissions/undo-535.sql and in the suites that know them), and in the name
--   and path of its suite.)
--
-- WHAT WAS WRONG
--
--   Any Owner or Manager could change the four affiliate commission rates (set_commission_rates,
--   the Commissions page's Rates window). Every way commission is worked out read those rates
--   live: settling an invoice, a correction, a reconcile, an affiliate change, a part payment,
--   a package or bundle sale. So after a rate change, the next correction or instalment of an
--   old invoice re-priced its affiliate commission at the new rates, paid-out commission too:
--   410's netting took back from the affiliate, or left owed to them, the difference on what had
--   been paid out (tier 1 15 to 10: -15.00; tier 2 5 to 35: +13.50 left open). A credit package's
--   or premium bundle's own rates (tier1_rate, tier2_rate, staff_commission_rate, which win over
--   the published rates on their own lines) took any number up to 999.999, any Owner or Manager
--   set them, and the audit row kept only the name. And apply_commission_rebase_all() (re-earns
--   every unpaid staff commission at today's rate and roster, no date range) and
--   set_staff_commission_rate(numeric) could be called straight by any signed-in login, though
--   no page calls either. A change made straight on app_settings, credit_packages or
--   premium_bundles with the secret key left no audit entry, and only set_commission_rates kept
--   the four rates within 0 to 100: written straight on app_settings, 150 was taken (and paid).
--
-- THE RULE (the user, 24 Nov 2026)
--
--   1. Only an Owner changes the affiliate commission rates. An Admin is not an Owner. Managers
--      still see them.
--   2. An invoice keeps the affiliate commission rates it first earned at. A correction, a
--      reconcile, a re-earn or a later instalment never re-prices it after a rate change. A new
--      invoice uses the current rates. A package's or bundle's own snapshot rate (on its sale)
--      still comes first on its own lines. Staff commission is not covered: its rate change is
--      closed (4).
--   3. A package's or bundle's own rates are between 0 and 100 (or none), and only an Owner sets
--      or changes them; a Manager keeps editing everything else, and a Manager's save that
--      leaves the three rates as stored passes. The audit row records the old and new rates.
--   4. apply_commission_rebase_all() and set_staff_commission_rate(numeric) are closed to every
--      login (public, anon, authenticated); postgres and the service role keep them.
--
-- WHAT THIS DOES (every role refusal is errcode 42501, in the words the pages show)
--
--   "Not an Owner" is current_user_role() is distinct from 'owner' (an Admin is not an Owner;
--   is_owner() is not executable by signed-in logins), after each function's own first check.
--
--   * set_commission_rates, after require_active_staff() and its Owner-or-Manager check:
--     a caller who is not an Owner: "Only an Owner can change the commission rates." Its range
--     checks and its audit row (old and new rates, since 425) are as before.
--
--   * A new table, public.invoice_affiliate_rates: one row per invoice, the four settings rates
--     (tier 1 own and third-party, tier 2 own and third-party) the invoice first earned
--     affiliate commission at, each 0 to 100, whether the row came from the backfill below, and
--     when. Only its owner (postgres) reads or writes it: row security on, no rule, every grant
--     to public, anon, authenticated and service_role revoked, so the secret key cannot set an
--     invoice's rates ahead of its first earning either; it goes with its invoice. Two helpers
--     only postgres can call (every function that calls them is a postgres-owned SECURITY DEFINER
--     function):
--       invoice_affiliate_rates_for(invoice): the rates kept for the invoice, else the current
--         settings (with the fallbacks earn_invoice_commission always had; the settings columns
--         are not null). Writes nothing.
--       record_invoice_affiliate_rates(invoice, four rates): keeps them for the invoice when
--         none are kept yet; when some are, changes nothing.
--     Every way an invoice's affiliate commission is worked out reads its rates through the
--     first helper, and the ones that write a commission row keep what they used with the
--     second, so the first row an invoice ever has fixes its rates. Until its rates are kept,
--     each earn function locks the invoice row before it reads them (a caller that did not lock
--     it, as the event website's referral check, trg_event_web_referral_check_decided, then
--     waits for another earning of the same invoice to commit and reads what that one kept), so
--     two earnings never keep different rates; sync_instalment_commissions locks it already:
--       - earn_invoice_commission (settling, correcting, reconciling, an affiliate change, an
--         exchange, an FOC confirmation, a sign-up linked later; 489's machine rule is read as
--         before): reads them; at its end, when the invoice has a commission row, keeps them.
--       - earn_credit_package_commission and earn_premium_bundle_commission: the sale's own
--         snapshot rate first, as before; without one, the invoice's rates. When they write a
--         tier 1 row they keep the invoice's four rates.
--       - invoice_affiliate_commission_preview and invoice_package_commission_preview (what a
--         part payment earns, through invoice_instalment_commission_targets): read them.
--         invoice_package_commission_preview also reads a settled line's own rate from its sale's
--         snapshot (the latest sale of that line), as the two earn functions do; before, it read
--         the package's or bundle's rate as it is now. A line not yet settled reads the
--         package's rate, which its settlement will snapshot.
--       - sync_instalment_commissions (every part payment, and the end of every reconcile): the
--         first time its targets hold an affiliate row and nothing is kept for the invoice, it
--         keeps the rates the targets were worked out at and reads the targets again from what
--         it kept. A dry run keeps nothing. Staff rows are as before.
--     reconcile_invoice_commissions reads no rate itself (it calls the functions above) and is
--     unchanged.
--   * Before anything changes it refuses, with nothing changed, when any standing commission row
--     (earned, paid or blocked, adjusting no other row, amount above 0) carries a rate other than
--     today's settings rate for its tier and kind, leaving out a package or bundle row whose sale
--     snapshots its own rate: "535: n standing commission row(s) ... carry a rate other than
--     today's settings". If the rates were changed before this goes in, the backfill would keep
--     the new ones for old invoices; then look before applying.
--   * Backfill: every invoice that has a commission row of any status (earned, paid, blocked or
--     reversed; settlement or part payment) gets the current settings rates, marked backfilled.
--     Before this, every one of those invoices was worked out at the current settings on its next
--     run, so what each would earn on any later run is exactly as before until the rates change.
--     It is not the rate on the invoice's first row: two reversed rows of 10 Sep 2026 carry tier 2
--     own at 5%, and keeping that would re-price those invoices. An invoice with no commission row
--     keeps nothing yet: it keeps the rates in force when it first earns.
--     Production, read only on 24 Nov 2026: 125 invoices have commission rows (122 of them earned,
--     paid or blocked rows); every earned, paid and blocked row's rate is today's settings rate for
--     its tier and kind (tier 1 own 15, third party 4.5; tier 2 35 and 35); only those 2 reversed
--     rows carry another (tier 2 own 5); every sale's snapshot rate is null. So the backfill
--     keeps, for every invoice, the rates its rows already carry, and changes no amount by
--     construction; no rehearsal on production data is needed.
--     scripts/commissions/tests/backfill-rehearsal-535.sql is the local check (made-up rows).
--
--   * Seventeen CHECK constraints, each "null or between 0 and 100" (<table>_<column>_0_100):
--     credit_packages and premium_bundles tier1_rate, tier2_rate and staff_commission_rate; the
--     rates each sale snapshots from them, credit_package_sales and premium_bundle_sales
--     tier1_rate_snapshot, tier2_rate_snapshot and staff_rate_snapshot; and app_settings'
--     commission_tier1_own_rate, commission_tier1_third_rate, commission_tier2_own_rate,
--     commission_tier2_third_rate (numeric, not null) and staff_commission_rate (numeric(6,3),
--     not null, set only by the closed set_staff_commission_rate). Before anything changes it
--     refuses if a stored value is outside 0 to 100: "535: n row(s) of public.<table> have a
--     <column> outside 0 to 100. Look at them before applying; nothing was changed." None is on
--     production (packages, bundles and sales: all null; the settings: 15 / 4.5 / 35 / 35, staff 3).
--     Without the settings' constraint, a rate written straight above 100 would, with 535 in,
--     stop every invoice that first earns (invoice_affiliate_rates refuses it, 23514); before 535
--     it was paid.
--   * upsert_credit_package and upsert_premium_bundle, after their Owner-or-Manager check:
--       - a caller who is not an Owner, whose tier 1, tier 2 or staff commission rate differs
--         from the one stored (for a new package or bundle: any rate given): "Only an Owner can
--         set a package's or bundle's own commission rates." The stored rates are read with the
--         row locked.
--       - a rate below 0 or above 100: "A package's or bundle's Tier 1 rate must be between 0
--         and 100." (Tier 2 rate, Staff commission rate likewise).
--       - the audit row: the old rates (none for a new one) and the new rates as stored, with
--         what it recorded before (the name; for a bundle the amounts and classification).
--   * EXECUTE on apply_commission_rebase_all() and set_staff_commission_rate(numeric) revoked
--     from public, anon and authenticated (postgres and service_role keep it). Their text is
--     unchanged. rebase_staff_commissions(date,date,boolean) is already closed (pinned below).
--   * 532's trg_audit_direct_change() (a change made straight on a table through the table API,
--     by a signed-in login or the secret key, goes in the audit log) is attached, as on its 13
--     tables, to app_settings, credit_packages and premium_bundles (trigger audit_direct_change),
--     so a straight change of a rate there is recorded with its old and new values. Two lines
--     are added to it: their entries' names (settings_updated, credit_package_..., premium_bundle_...),
--     and app_settings, whose id is true and not a uuid, filed under no record (as
--     set_commission_rates files its own entry); its other 13 tables are as before.
--
-- WHAT STAYS
--
--   * How much every commission row is, today: the backfill keeps the current settings. A rate
--     change from now on applies to invoices that first earn affiliate commission after it.
--   * The rate written on each commission row; payouts, take-backs, refunds and 410's netting.
--   * Staff commission, its rate and its rebase functions' text; earn_staff_commission and
--     reearn_invoice_staff_commission; the staff part of sync_instalment_commissions.
--   * A package's or bundle's rate on a line not yet settled: read as it is now (only an Owner
--     can change it from now on).
--   * package_commission_diagnostic() and affiliate_rules_info(): they report the current rates,
--     as before.
--   * As found, not changed here (the user to decide; a later migration if so): a product's kind
--     (own, third party, no commission; 489's machine link; a promotion line's own and third-party
--     split) is still read from the catalogue every time an invoice is worked out again, so a
--     product's kind changed and a later correction re-price an old invoice, paid-out commission
--     too.
--   * First write wins, with no repair in the app: a rate mistyped and put right an hour later
--     stays on every invoice that first earned in that hour. The rate change's audit row
--     (commission_rates_set) gives the hour and invoice_affiliate_rates.recorded_at the invoices;
--     the repair is SQL on invoice_affiliate_rates.
--   * A reopened invoice settled again takes a new snapshot from its package or bundle, as before;
--     a package's or bundle's own rates are the Owner's from now on, and recorded.
--   * commission_instalment_backfill: unchanged; inert on production (instalment_commission_from
--     is set, 25 Sep 2026).
--   * An invoice that never earned (its buyer had no referrer) and gets a referrer later earns at
--     that later day's rates, and keeps those.
--   * The secret key can still change a rate within 0 to 100 straight on app_settings, or a
--     package's or bundle's own rate: that applies to invoices that first earn, and packages or
--     bundles sold, afterwards; it is recorded now (532's trigger, attached above).
--   * A change made as postgres (the SQL editor) is not recorded by that trigger, as on 532's 13
--     tables.
--   * Lock order: the earn functions' invoice lock comes after the caller's own locks in
--     trg_event_web_referral_check_decided and link_affiliate_signup; a payment on the same
--     invoice at that instant that also wants one of those rows could deadlock, and one side
--     would be refused once. No such order was found in the suites.
--   * Every grant but the ones above; who may save a package or bundle otherwise.
--
-- UNDO
--
--   scripts/commissions/undo-535.sql (it refuses unless every function here is exactly 535's,
--   the two helpers, the table and the seventeen constraints are 535's, and the two grants are
--   535's): each function is put back exactly as it was, the two helpers and the seventeen constraints are
--   dropped, the table is dropped with every rate kept in it (backfilled or earned; it says how
--   many, and how many differ from the settings then, which would be re-priced at their next
--   correction), and EXECUTE on the two closed functions is granted to authenticated again.
--   Commission rows already written keep their amounts and rates. The three audit triggers are
--   dropped and 532's function is put back as it was. After an undo, 535 again backfills every
--   invoice with commission rows with the settings of that day. A later migration changing any
--   of these must pin 535's AFTER md5. The undo refuses while another function uses the helpers
--   or reads invoice_affiliate_rates: a later migration that does (538, say) is undone first.
--
-- NO SELF-TEST INSIDE; the suite is scripts/commissions/tests/invoice-keeps-its-rates-535.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Functions the patched ones rely on, as tested: the caller's role, the active-staff and
  -- Owner-or-Manager checks left in place, the audit writers, the package classification, the
  -- part-payment test and targets (which call the two previews), the reconcile that calls the
  -- earn functions, and the staff rebase already closed to logins.
  c_relied constant text[] := array[
    'current_user_role()',
    'require_active_staff(text[])',
    'is_owner_or_manager()',
    'write_audit(text,uuid,text,jsonb,jsonb)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'package_commission_classification()',
    'invoice_instalment_commission_active(uuid)',
    'invoice_instalment_commission_targets(uuid)',
    'reconcile_invoice_commissions(uuid,text)',
    'rebase_staff_commissions(date,date,boolean)'];
  c_relied_md5 constant text[] := array[
    '519b0a33a3548f970c5d585b6e76a389',
    '877b3aa74cea559881979bb161c450e2',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    'b194f839993670c5b5dd28e934c2a829',
    'c705c733e213a27f0dc32d54322cc855',
    '08db9563fd4213315b16b891a53ead7b',
    '1cfc14db26aaef668cee010fadbddfe3',
    'dc47c3c7b9e41d67b89713fce2a4b480',
    '3c267728e215d17ebeb9cfe9cb7db47c',
    '6da328885a2e32744aa301a2e7794c75'];
  c_closed_acl_after constant text := 'postgres=X/postgres,service_role=X/postgres';
  -- The table, made first (the helpers read it).
  c_table_def constant text :=
$d$create table public.invoice_affiliate_rates (
  invoice_id uuid primary key references public.invoices(id) on delete cascade,
  tier1_own_rate numeric not null constraint invoice_affiliate_rates_tier1_own_0_100 check (tier1_own_rate >= 0 and tier1_own_rate <= 100),
  tier1_third_rate numeric not null constraint invoice_affiliate_rates_tier1_third_0_100 check (tier1_third_rate >= 0 and tier1_third_rate <= 100),
  tier2_own_rate numeric not null constraint invoice_affiliate_rates_tier2_own_0_100 check (tier2_own_rate >= 0 and tier2_own_rate <= 100),
  tier2_third_rate numeric not null constraint invoice_affiliate_rates_tier2_third_0_100 check (tier2_third_rate >= 0 and tier2_third_rate <= 100),
  backfilled boolean not null default false,
  recorded_at timestamptz not null default now()
)$d$;
  c_table_comment constant text :=
    '535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026: "An invoice keeps the commission rates it first earned at"): '
    'the four affiliate commission rates (app_settings commission_tier1/2_own/third_rate) an invoice first earned at, kept '
    'by record_invoice_affiliate_rates and read by invoice_affiliate_rates_for in every function that works out affiliate '
    'commission. backfilled: kept by 535 for an invoice that had commission rows before it (the settings then). No login '
    'reads or writes it.';
  c_table_acl constant text := 'postgres=arwdDxtm/postgres';
  -- The two new helpers: their signatures, text and grants (the owner and the service role).
  c_new_sig constant text[] := array[
    'invoice_affiliate_rates_for(uuid)',
    'record_invoice_affiliate_rates(uuid,numeric,numeric,numeric,numeric)'];
  c_new_def constant text[] := array[
$d$CREATE OR REPLACE FUNCTION public.invoice_affiliate_rates_for(p_invoice_id uuid)
 RETURNS TABLE(tier1_own numeric, tier1_third numeric, tier2_own numeric, tier2_third numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026: "An invoice keeps the
  -- commission rates it first earned at"): the affiliate rates an invoice is worked out at: the
  -- ones kept for it when it first earned (invoice_affiliate_rates), else the current settings,
  -- with the fallbacks earn_invoice_commission always had (the columns are not null). One row.
  -- Writes nothing.
  select r.tier1_own_rate, r.tier1_third_rate, r.tier2_own_rate, r.tier2_third_rate
    from public.invoice_affiliate_rates r
   where r.invoice_id = p_invoice_id
  union all
  select coalesce(a.commission_tier1_own_rate, 15), coalesce(a.commission_tier1_third_rate, 4.5),
         coalesce(a.commission_tier2_own_rate, 5), coalesce(a.commission_tier2_third_rate, 5)
    from public.app_settings a
   where a.id = true
     and not exists (select 1 from public.invoice_affiliate_rates r where r.invoice_id = p_invoice_id)
$function$
$d$,
$d$CREATE OR REPLACE FUNCTION public.record_invoice_affiliate_rates(p_invoice_id uuid, p_tier1_own numeric, p_tier1_third numeric, p_tier2_own numeric, p_tier2_third numeric)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'public'
AS $function$
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026: "An invoice keeps the
  -- commission rates it first earned at"): keeps the four settings rates an invoice was just
  -- worked out at, the first time it earns affiliate commission. When rates are kept for it
  -- already this changes nothing: an invoice's rates are kept once.
  insert into public.invoice_affiliate_rates (invoice_id, tier1_own_rate, tier1_third_rate, tier2_own_rate, tier2_third_rate)
  values (p_invoice_id, p_tier1_own, p_tier1_third, p_tier2_own, p_tier2_third)
  on conflict (invoice_id) do nothing
$function$
$d$];
  c_new_md5 constant text[] := array[
    '64e6ed85a8f169477fc85bd8452da453',
    'ae5132e23be0b0acbdec3d92e500bd4c'];
  c_new_acl constant text := 'postgres=X/postgres';
  -- The tables 532's trigger is attached to here, and the trigger as it must read.
  c_trg_table constant text[] := array['app_settings', 'credit_packages', 'premium_bundles'];
  c_trg_def constant text := 'CREATE TRIGGER audit_direct_change AFTER INSERT OR DELETE OR UPDATE ON public.%s FOR EACH ROW '
    || 'WHEN ((CURRENT_USER = ANY (ARRAY[''anon''::name, ''authenticated''::name, ''service_role''::name]))) '
    || 'EXECUTE FUNCTION trg_audit_direct_change()';
  -- The seventeen constraints: the packages' and bundles' own rates, the rates each sale
  -- snapshots from them, and the settings' rates.
  c_con_table constant text[] := array[
    'credit_packages', 'credit_packages', 'credit_packages',
    'premium_bundles', 'premium_bundles', 'premium_bundles',
    'credit_package_sales', 'credit_package_sales', 'credit_package_sales',
    'premium_bundle_sales', 'premium_bundle_sales', 'premium_bundle_sales',
    'app_settings', 'app_settings', 'app_settings', 'app_settings', 'app_settings'];
  c_con_col constant text[] := array[
    'tier1_rate', 'tier2_rate', 'staff_commission_rate',
    'tier1_rate', 'tier2_rate', 'staff_commission_rate',
    'tier1_rate_snapshot', 'tier2_rate_snapshot', 'staff_rate_snapshot',
    'tier1_rate_snapshot', 'tier2_rate_snapshot', 'staff_rate_snapshot',
    'commission_tier1_own_rate', 'commission_tier1_third_rate', 'commission_tier2_own_rate',
    'commission_tier2_third_rate', 'staff_commission_rate'];
  -- The functions patched.
  c_sig constant text[] := array[
    'set_commission_rates(numeric,numeric,numeric,numeric)',
    'earn_invoice_commission(uuid)',
    'earn_credit_package_commission(uuid)',
    'earn_premium_bundle_commission(uuid)',
    'invoice_affiliate_commission_preview(uuid)',
    'invoice_package_commission_preview(uuid)',
    'sync_instalment_commissions(uuid,text,date,boolean,boolean)',
    'upsert_credit_package(uuid,text,numeric,numeric,boolean,date,date,text,boolean,numeric,numeric,numeric,numeric,text,uuid[],uuid[],boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,text,numeric)',
    'upsert_premium_bundle(uuid,text,numeric,numeric,numeric,integer,numeric,boolean,date,date,text,boolean,numeric,numeric,numeric,text,uuid[],uuid[])',
    'trg_audit_direct_change()'];
  c_before constant text[] := array[
    'ce795196aaf6fadb1bfca52e2cafaa88',
    '40b040e35b23940bb19e14e53bdd4daa',
    'ad9bbf2183d6e19da85e7f59ce4a4b6e',
    '39429d3a496274811dce3c3f5f7ca29b',
    '072803880358cb84d7f148a06a27596e',
    '966e8b7166607aa1d986f20fbbbc1e52',
    '88d7b122778801a0d5eea0b6dd8395b7',
    'a2e8ec73a38b60ae7c05f573fba25ea8',
    '2202746851bc5bdd424c1c52fda86056',
    'b2ac8670825d1daf73a27c74e64bd66a'];
  c_after constant text[] := array[
    '6f21984954600ef460aec9bdf4b4fdd2',
    '762c06868e2c2256f008b9468b8a255b',
    '44d10e4bcceb9a94080f1802c1da946f',
    '86ea3b1215ed6fd896bfd63ceba21152',
    '927b9e2129e354c0f061a713083cdb54',
    'ef34e72a6bffaebb33af83f2b38f2ade',
    '98fbe647100e8890957f098c6d90fca4',
    '51dfbba874668b8d0c75c3d72c859aab',
    'c08e7ed4eed6d8d5772dfcb2305439b6',
    '5dcea97b6479d9bb6a53adfa9dfbcba4'];
  -- Their grants, before and after (unchanged).
  c_acl constant text[] := array[
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres'];
  -- The two functions closed to logins, their md5s (unchanged) and their grants before.
  c_closed constant text[] := array[
    'apply_commission_rebase_all()',
    'set_staff_commission_rate(numeric)'];
  c_closed_md5 constant text[] := array[
    '48272cee4f2c9810d66b1e63d0cb8f97',
    '84a406c3d260930b444825f1f694b481'];
  c_closed_acl_before constant text := 'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres';
  -- Twenty-one patches, each found exactly once in its function:
  --    1 set_commission_rates: Owner only
  --    2 earn_invoice_commission: the invoice's rates
  --    3 earn_invoice_commission: keep them once it has a row
  --    4 earn_credit_package_commission: its variables
  --    5 earn_credit_package_commission: the snapshot, else the invoice's rates
  --    6 earn_credit_package_commission: keep them with the tier 1 row
  --    7 earn_premium_bundle_commission: its variables
  --    8 earn_premium_bundle_commission: the snapshot, else the invoice's rates
  --    9 earn_premium_bundle_commission: keep them with the tier 1 row
  --   10 invoice_affiliate_commission_preview: the invoice's rates
  --   11 invoice_package_commission_preview: a settled line's rate from its sale
  --   12 invoice_package_commission_preview: the invoice's rates
  --   13 sync_instalment_commissions: keep them the first time a part payment earns
  --   14 upsert_credit_package: its variables
  --   15 upsert_credit_package: Owner only for the rates, 0 to 100
  --   16 upsert_credit_package: the audit row's old and new rates
  --   17 upsert_premium_bundle: its variables
  --   18 upsert_premium_bundle: Owner only for the rates, 0 to 100
  --   19 upsert_premium_bundle: the audit row's old and new rates
  --   20 trg_audit_direct_change: the three tables' entry names
  --   21 trg_audit_direct_change: app_settings filed under no record
  c_fn constant int[] := array[1, 2, 2, 3, 3, 3, 4, 4, 4, 5, 6, 6, 7, 8, 8, 8, 9, 9, 9, 10, 10];
  c_anchor constant text[] := array[
-- 1 set_commission_rates: Owner only
$a$  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit commission rates'; end if;
$a$,
-- 2 earn_invoice_commission: the invoice's rates
$a$  -- Editable commission rates (fall back to the historical defaults).
  select coalesce(commission_tier1_own_rate, 15), coalesce(commission_tier1_third_rate, 4.5),
         coalesce(commission_tier2_own_rate, 5), coalesce(commission_tier2_third_rate, 5),
         coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_rate_t1_own, v_rate_t1_third, v_rate_t2_own, v_rate_t2_third, v_machine_new
    from public.app_settings where id = true;
$a$,
-- 3 earn_invoice_commission: keep them once it has a row
$a$  perform public.write_audit('commissions', p_invoice_id, 'commission_calculated', null,
$a$,
-- 4 earn_credit_package_commission: its variables
$a$  -- 527: each tier's status and, when blocked, its reason
$a$,
-- 5 earn_credit_package_commission: the snapshot, else the invoice's rates
$a$  v_ptype := public.package_commission_classification();
  select coalesce(s.tier1_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier1_third_rate
                else commission_tier1_own_rate end),
         coalesce(s.tier2_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier2_third_rate
                else commission_tier2_own_rate end)
    into v_r1, v_r2 from public.app_settings where id = true;
$a$,
-- 6 earn_credit_package_commission: keep them with the tier 1 row
$a$    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      v_t1_status::commission_status, v_t1_block, v_paid_date);
$a$,
-- 7 earn_premium_bundle_commission: its variables
$a$  -- 527: each tier's status and, when blocked, its reason
$a$,
-- 8 earn_premium_bundle_commission: the snapshot, else the invoice's rates
$a$  v_ptype := public.package_commission_classification();
  select coalesce(s.tier1_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier1_third_rate
                else commission_tier1_own_rate end),
         coalesce(s.tier2_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier2_third_rate
                else commission_tier2_own_rate end)
    into v_r1, v_r2 from public.app_settings where id = true;
$a$,
-- 9 earn_premium_bundle_commission: keep them with the tier 1 row
$a$    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      v_t1_status::commission_status, v_t1_block, v_paid_date);
$a$,
-- 10 invoice_affiliate_commission_preview: the invoice's rates
$a$  -- Editable commission rates (fall back to the historical defaults).
  select coalesce(commission_tier1_own_rate, 15), coalesce(commission_tier1_third_rate, 4.5),
         coalesce(commission_tier2_own_rate, 5), coalesce(commission_tier2_third_rate, 5),
         coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_rate_t1_own, v_rate_t1_third, v_rate_t2_own, v_rate_t2_third, v_machine_new
    from public.app_settings where id = true;
$a$,
-- 11 invoice_package_commission_preview: a settled line's rate from its sale
$a$    select ii.id as item_id, coalesce(cp.tier1_rate, pb.tier1_rate) as def_r1,
           coalesce(cp.tier2_rate, pb.tier2_rate) as def_r2,
           ii.credit_issued_at is null as unsettled   -- 476
      from public.invoice_items ii
      left join public.credit_packages cp on cp.id = ii.credit_package_id
      left join public.premium_bundles pb on pb.id = ii.premium_bundle_id
$a$,
-- 12 invoice_package_commission_preview: the invoice's rates
$a$    select coalesce(v_it.def_r1, case when v_cls = 'third_party' then a.commission_tier1_third_rate else a.commission_tier1_own_rate end),
           coalesce(v_it.def_r2, case when v_cls = 'third_party' then a.commission_tier2_third_rate else a.commission_tier2_own_rate end)
      into v_r1, v_r2 from public.app_settings a where a.id = true;
$a$,
-- 13 sync_instalment_commissions: keep them the first time a part payment earns
$a$  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_targets
    from public.invoice_instalment_commission_targets(p_invoice_id) t;
$a$,
-- 14 upsert_credit_package: its variables
$a$declare v_id uuid; v_s uuid; v_v uuid;
$a$,
-- 15 upsert_credit_package: Owner only for the rates, 0 to 100
$a$    raise exception 'Only an Owner or Manager can manage credit packages'; end if;
$a$,
-- 16 upsert_credit_package: the audit row's old and new rates
$a$    null, jsonb_build_object('name', trim(p_name)), 'catalogue', null, null);
$a$,
-- 17 upsert_premium_bundle: its variables
$a$declare v_id uuid; v_qual numeric; v_qty integer;
$a$,
-- 18 upsert_premium_bundle: Owner only for the rates, 0 to 100
$a$    raise exception 'Only an Owner or Manager can manage premium bundles'; end if;
$a$,
-- 19 upsert_premium_bundle: the audit row's old and new rates
$a$  perform public.write_audit_ex('premium_bundles', v_id, 'premium_bundle_upserted', null,
    jsonb_build_object('name', p_name, 'payment', p_customer_payment_amount,
      'paid_credit', p_paid_credit_amount, 'bonus_credit', p_bonus_credit_amount,
      'vouchers', v_qty, 'classification', p_commission_classification), 'credit', null, null);
$a$,
-- 20 trg_audit_direct_change: the three tables' entry names
$a$    when 'suppliers' then 'supplier'
    else tg_table_name end;
$a$,
-- 21 trg_audit_direct_change: app_settings filed under no record
$a$  else
    v_record := (v_row ->> 'id')::uuid;
  end if;
$a$];
  c_new constant text[] := array[
-- 1 set_commission_rates: Owner only
$n$  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit commission rates'; end if;
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026): only an Owner changes the
  -- affiliate commission rates (an Admin is not an Owner). Managers still read them.
  if public.current_user_role() is distinct from 'owner' then
    raise exception 'Only an Owner can change the commission rates.' using errcode = '42501'; end if;
$n$,
-- 2 earn_invoice_commission: the invoice's rates
$n$  -- Editable commission rates (fall back to the historical defaults).
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026: "An invoice keeps the
  -- commission rates it first earned at"): the four rates are the ones kept for this invoice
  -- when it first earned affiliate commission; an invoice that has not earned yet reads the
  -- current settings, as before, and keeps them below once it has a commission row. So a
  -- correction, a reconcile or an affiliate change after a rate change works it out at the
  -- rates it first earned at. machine_commission_from (489) is read as before.
  -- Until its rates are kept, the invoice is locked first, so another earning of it (a caller
  -- that did not lock it) waits and then reads the rates this one keeps.
  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = p_invoice_id) then
    perform 1 from public.invoices i535 where i535.id = p_invoice_id for update;
  end if;
  select r.tier1_own, r.tier1_third, r.tier2_own, r.tier2_third
    into v_rate_t1_own, v_rate_t1_third, v_rate_t2_own, v_rate_t2_third
    from public.invoice_affiliate_rates_for(p_invoice_id) r;
  select coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_machine_new
    from public.app_settings where id = true;
$n$,
-- 3 earn_invoice_commission: keep them once it has a row
$n$  -- 535 (security audit of 17 Nov 2026, M12): the first time this invoice has a commission row,
  -- the rates it was worked out at are kept with it (when some are kept already, nothing changes).
  if exists (select 1 from public.commissions c535 where c535.invoice_id = p_invoice_id) then
    perform public.record_invoice_affiliate_rates(p_invoice_id, v_rate_t1_own, v_rate_t1_third,
      v_rate_t2_own, v_rate_t2_third);
  end if;
  perform public.write_audit('commissions', p_invoice_id, 'commission_calculated', null,
$n$,
-- 4 earn_credit_package_commission: its variables
$n$  -- 527: each tier's status and, when blocked, its reason
  -- 535: the invoice's four affiliate rates (invoice_affiliate_rates_for), kept with its first row
  v535_t1_own numeric; v535_t1_third numeric; v535_t2_own numeric; v535_t2_third numeric;
$n$,
-- 5 earn_credit_package_commission: the snapshot, else the invoice's rates
$n$  v_ptype := public.package_commission_classification();
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026): the sale's own snapshot
  -- rate (the package's rate when it was sold) comes first, as before; without one, the
  -- invoice's rates: those kept when it first earned affiliate commission, else the current
  -- settings, kept below with the tier 1 row. Until its rates are kept, the invoice is locked
  -- first, so another earning of it waits and then reads the rates this one keeps.
  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = s.invoice_id) then
    perform 1 from public.invoices i535 where i535.id = s.invoice_id for update;
  end if;
  select coalesce(s.tier1_rate_snapshot,
           case when v_ptype = 'third_party' then r.tier1_third else r.tier1_own end),
         coalesce(s.tier2_rate_snapshot,
           case when v_ptype = 'third_party' then r.tier2_third else r.tier2_own end),
         r.tier1_own, r.tier1_third, r.tier2_own, r.tier2_third
    into v_r1, v_r2, v535_t1_own, v535_t1_third, v535_t2_own, v535_t2_third
    from public.invoice_affiliate_rates_for(s.invoice_id) r;
$n$,
-- 6 earn_credit_package_commission: keep them with the tier 1 row
$n$    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      v_t1_status::commission_status, v_t1_block, v_paid_date);
    -- 535 (security audit of 17 Nov 2026, M12): the invoice keeps the settings rates it first
    -- earned at (when some are kept already, nothing changes).
    perform public.record_invoice_affiliate_rates(s.invoice_id, v535_t1_own, v535_t1_third,
      v535_t2_own, v535_t2_third);
$n$,
-- 7 earn_premium_bundle_commission: its variables
$n$  -- 527: each tier's status and, when blocked, its reason
  -- 535: the invoice's four affiliate rates (invoice_affiliate_rates_for), kept with its first row
  v535_t1_own numeric; v535_t1_third numeric; v535_t2_own numeric; v535_t2_third numeric;
$n$,
-- 8 earn_premium_bundle_commission: the snapshot, else the invoice's rates
$n$  v_ptype := public.package_commission_classification();
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026): the sale's own snapshot
  -- rate (the bundle's rate when it was sold) comes first, as before; without one, the
  -- invoice's rates: those kept when it first earned affiliate commission, else the current
  -- settings, kept below with the tier 1 row. Until its rates are kept, the invoice is locked
  -- first, so another earning of it waits and then reads the rates this one keeps.
  if not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = s.invoice_id) then
    perform 1 from public.invoices i535 where i535.id = s.invoice_id for update;
  end if;
  select coalesce(s.tier1_rate_snapshot,
           case when v_ptype = 'third_party' then r.tier1_third else r.tier1_own end),
         coalesce(s.tier2_rate_snapshot,
           case when v_ptype = 'third_party' then r.tier2_third else r.tier2_own end),
         r.tier1_own, r.tier1_third, r.tier2_own, r.tier2_third
    into v_r1, v_r2, v535_t1_own, v535_t1_third, v535_t2_own, v535_t2_third
    from public.invoice_affiliate_rates_for(s.invoice_id) r;
$n$,
-- 9 earn_premium_bundle_commission: keep them with the tier 1 row
$n$    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      v_t1_status::commission_status, v_t1_block, v_paid_date);
    -- 535 (security audit of 17 Nov 2026, M12): the invoice keeps the settings rates it first
    -- earned at (when some are kept already, nothing changes).
    perform public.record_invoice_affiliate_rates(s.invoice_id, v535_t1_own, v535_t1_third,
      v535_t2_own, v535_t2_third);
$n$,
-- 10 invoice_affiliate_commission_preview: the invoice's rates
$n$  -- Editable commission rates (fall back to the historical defaults).
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026): the invoice's rates, as
  -- earn_invoice_commission reads them: those kept when it first earned affiliate commission,
  -- else the current settings. A part payment after a rate change earns at the same rates.
  select r.tier1_own, r.tier1_third, r.tier2_own, r.tier2_third
    into v_rate_t1_own, v_rate_t1_third, v_rate_t2_own, v_rate_t2_third
    from public.invoice_affiliate_rates_for(p_invoice_id) r;
  select coalesce(v_inv.created_at >= machine_commission_from, false)
    into v_machine_new
    from public.app_settings where id = true;
$n$,
-- 11 invoice_package_commission_preview: a settled line's rate from its sale
$n$    -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026): a settled line's own rate
    -- is its sale's snapshot (the package's or bundle's rate when it was sold, or none), as
    -- earn_credit_package_commission and earn_premium_bundle_commission read it, so a later change
    -- to the package does not re-price it; the line's latest sale. A line not yet settled reads
    -- the package's rate, which its settlement will snapshot.
    select ii.id as item_id,
           case when sl535.found then sl535.r1 else coalesce(cp.tier1_rate, pb.tier1_rate) end as def_r1,
           case when sl535.found then sl535.r2 else coalesce(cp.tier2_rate, pb.tier2_rate) end as def_r2,
           ii.credit_issued_at is null as unsettled   -- 476
      from public.invoice_items ii
      left join public.credit_packages cp on cp.id = ii.credit_package_id
      left join public.premium_bundles pb on pb.id = ii.premium_bundle_id
      left join lateral (
             select true as found, x.r1, x.r2
               from (select cs.tier1_rate_snapshot as r1, cs.tier2_rate_snapshot as r2, cs.sold_at, cs.id
                       from public.credit_package_sales cs
                      where cs.invoice_item_id = ii.id and ii.line_kind = 'credit_package'
                     union all
                     select bs.tier1_rate_snapshot, bs.tier2_rate_snapshot, bs.sold_at, bs.id
                       from public.premium_bundle_sales bs
                      where bs.invoice_item_id = ii.id and ii.line_kind = 'premium_bundle') x
              order by x.sold_at desc nulls last, x.id desc
              limit 1) sl535 on true
$n$,
-- 12 invoice_package_commission_preview: the invoice's rates
$n$    -- 535 (security audit of 17 Nov 2026, M12): without the line's own rate, the invoice's rates:
    -- those kept when it first earned affiliate commission, else the current settings.
    select coalesce(v_it.def_r1, case when v_cls = 'third_party' then a.tier1_third else a.tier1_own end),
           coalesce(v_it.def_r2, case when v_cls = 'third_party' then a.tier2_third else a.tier2_own end)
      into v_r1, v_r2 from public.invoice_affiliate_rates_for(p_invoice_id) a;
$n$,
-- 13 sync_instalment_commissions: keep them the first time a part payment earns
$n$  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_targets
    from public.invoice_instalment_commission_targets(p_invoice_id) t;
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026: "An invoice keeps the
  -- commission rates it first earned at"): the first time a part payment earns this invoice
  -- affiliate commission (an affiliate target, none kept yet), the rates the targets were worked
  -- out at are kept with it and the targets are read again from what was kept, so the next
  -- instalment, a correction or a reconcile after a rate change pays the rest at the same rates.
  -- A dry run keeps nothing.
  if not p_dry_run
     and exists (select 1 from jsonb_array_elements(v_targets) t535 where t535->>'ledger' = 'affiliate')
     and not exists (select 1 from public.invoice_affiliate_rates k535 where k535.invoice_id = p_invoice_id) then
    perform public.record_invoice_affiliate_rates(p_invoice_id, r535.tier1_own, r535.tier1_third,
              r535.tier2_own, r535.tier2_third)
       from public.invoice_affiliate_rates_for(p_invoice_id) r535;
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_targets
      from public.invoice_instalment_commission_targets(p_invoice_id) t;
  end if;
$n$,
-- 14 upsert_credit_package: its variables
$n$declare v_id uuid; v_s uuid; v_v uuid;
  -- 535: the package's own rates as stored before this save, and the audit row's old rates
  v535_t1 numeric; v535_t2 numeric; v535_staff numeric; v535_old jsonb;
$n$,
-- 15 upsert_credit_package: Owner only for the rates, 0 to 100
$n$    raise exception 'Only an Owner or Manager can manage credit packages'; end if;
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026): a package's own commission
  -- rates (tier 1, tier 2, staff) are the Owner's: anyone else's save must leave them as stored
  -- (read with the row locked; a new package: none given). And they are none, or 0 to 100.
  if p_id is not null then
    select cp.tier1_rate, cp.tier2_rate, cp.staff_commission_rate
      into v535_t1, v535_t2, v535_staff
      from public.credit_packages cp where cp.id = p_id for update;
    if found then
      v535_old := jsonb_build_object('tier1_rate', v535_t1, 'tier2_rate', v535_t2,
                                     'staff_commission_rate', v535_staff);
    end if;
  end if;
  if public.current_user_role() is distinct from 'owner'
     and (p_tier1_rate is distinct from v535_t1 or p_tier2_rate is distinct from v535_t2
          or p_staff_commission_rate is distinct from v535_staff) then
    raise exception 'Only an Owner can set a package''s or bundle''s own commission rates.' using errcode = '42501'; end if;
  if p_tier1_rate < 0 or p_tier1_rate > 100 then
    raise exception 'A package''s or bundle''s Tier 1 rate must be between 0 and 100.'; end if;
  if p_tier2_rate < 0 or p_tier2_rate > 100 then
    raise exception 'A package''s or bundle''s Tier 2 rate must be between 0 and 100.'; end if;
  if p_staff_commission_rate < 0 or p_staff_commission_rate > 100 then
    raise exception 'A package''s or bundle''s Staff commission rate must be between 0 and 100.'; end if;
$n$,
-- 16 upsert_credit_package: the audit row's old and new rates
$n$    -- 535 (security audit of 17 Nov 2026, M12): the old rates (none for a new package) and the
    -- new ones as stored, with the name as before.
    v535_old,
    (select jsonb_build_object('name', trim(p_name), 'tier1_rate', cp.tier1_rate, 'tier2_rate', cp.tier2_rate,
                               'staff_commission_rate', cp.staff_commission_rate)
       from public.credit_packages cp where cp.id = v_id),
    'catalogue', null, null);
$n$,
-- 17 upsert_premium_bundle: its variables
$n$declare v_id uuid; v_qual numeric; v_qty integer;
  -- 535: the bundle's own rates as stored before this save, and the audit row's old rates
  v535_t1 numeric; v535_t2 numeric; v535_staff numeric; v535_old jsonb;
$n$,
-- 18 upsert_premium_bundle: Owner only for the rates, 0 to 100
$n$    raise exception 'Only an Owner or Manager can manage premium bundles'; end if;
  -- 535 (security audit of 17 Nov 2026, M12; the user, 24 Nov 2026): a bundle's own commission
  -- rates (tier 1, tier 2, staff) are the Owner's: anyone else's save must leave them as stored
  -- (read with the row locked; a new bundle: none given). And they are none, or 0 to 100.
  if p_id is not null then
    select pb.tier1_rate, pb.tier2_rate, pb.staff_commission_rate
      into v535_t1, v535_t2, v535_staff
      from public.premium_bundles pb where pb.id = p_id for update;
    if found then
      v535_old := jsonb_build_object('tier1_rate', v535_t1, 'tier2_rate', v535_t2,
                                     'staff_commission_rate', v535_staff);
    end if;
  end if;
  if public.current_user_role() is distinct from 'owner'
     and (p_tier1_rate is distinct from v535_t1 or p_tier2_rate is distinct from v535_t2
          or p_staff_commission_rate is distinct from v535_staff) then
    raise exception 'Only an Owner can set a package''s or bundle''s own commission rates.' using errcode = '42501'; end if;
  if p_tier1_rate < 0 or p_tier1_rate > 100 then
    raise exception 'A package''s or bundle''s Tier 1 rate must be between 0 and 100.'; end if;
  if p_tier2_rate < 0 or p_tier2_rate > 100 then
    raise exception 'A package''s or bundle''s Tier 2 rate must be between 0 and 100.'; end if;
  if p_staff_commission_rate < 0 or p_staff_commission_rate > 100 then
    raise exception 'A package''s or bundle''s Staff commission rate must be between 0 and 100.'; end if;
$n$,
-- 19 upsert_premium_bundle: the audit row's old and new rates
$n$  -- 535 (security audit of 17 Nov 2026, M12): the old rates (none for a new bundle) and the new
  -- ones as stored, with what it recorded before.
  perform public.write_audit_ex('premium_bundles', v_id, 'premium_bundle_upserted', v535_old,
    jsonb_build_object('name', p_name, 'payment', p_customer_payment_amount,
      'paid_credit', p_paid_credit_amount, 'bonus_credit', p_bonus_credit_amount,
      'vouchers', v_qty, 'classification', p_commission_classification)
    || (select jsonb_build_object('tier1_rate', pb.tier1_rate, 'tier2_rate', pb.tier2_rate,
                                  'staff_commission_rate', pb.staff_commission_rate)
          from public.premium_bundles pb where pb.id = v_id),
    'credit', null, null);
$n$,
-- 20 trg_audit_direct_change: the three tables' entry names
$n$    when 'suppliers' then 'supplier'
    -- 535 (security audit of 17 Nov 2026, M12): the commission rates and the packages' and
    -- bundles' own rates, changed straight on their tables
    when 'app_settings' then 'settings'
    when 'credit_packages' then 'credit_package'
    when 'premium_bundles' then 'premium_bundle'
    else tg_table_name end;
$n$,
-- 21 trg_audit_direct_change: app_settings filed under no record
$n$  elsif tg_table_name = 'app_settings' then
    -- 535 (security audit of 17 Nov 2026, M12): the one settings row's id is true, not a uuid; its
    -- entry is filed under no record, as set_commission_rates files its own.
    v_record := null;
  else
    v_record := (v_row ->> 'id')::uuid;
  end if;
$n$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[10]);
  v_done int := 0; v_new_done int := 0; v_closed_done int := 0; v_con_done int := 0; v_trg_done int := 0;
  v_off int; v_off_inv int;
  v_table_done boolean;
  v_acl text; v_bad text := '';
  v_backfilled int;
  d text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy function or table waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '535: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.rebase_staff_commissions(date,date,boolean)'))
     is distinct from c_closed_acl_after then
    raise exception '535: public.rebase_staff_commissions(date,date,boolean) is not closed to logins as tested. Re-read its grants before applying.'; end if;
  if to_regclass('public.app_settings') is null or to_regclass('public.commissions') is null
     or to_regclass('public.invoices') is null or to_regclass('public.credit_packages') is null
     or to_regclass('public.premium_bundles') is null or to_regclass('public.credit_package_sales') is null
     or to_regclass('public.premium_bundle_sales') is null then
    raise exception '535: a table it reads (app_settings, commissions, invoices, credit_packages, premium_bundles, credit_package_sales, premium_bundle_sales) is missing'; end if;
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '535: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception '535: the grants of public.% are not the tested ones. Re-read them before applying.', c_sig[i]; end if;
    if md5(d) = c_after[i] then
      v_done := v_done + 1;
    elsif md5(d) = c_before[i] then
      v_def[i] := d;
    else
      raise exception '535: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is not null then
      if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
        raise exception '535: a function public.% is there, but not 535''s. Re-read it before applying.', c_new_sig[i]; end if;
      v_new_done := v_new_done + 1;
    end if;
  end loop;
  v_table_done := to_regclass('public.invoice_affiliate_rates') is not null;
  if v_table_done and obj_description(to_regclass('public.invoice_affiliate_rates'), 'pg_class') is distinct from c_table_comment then
    raise exception '535: a table public.invoice_affiliate_rates is there, but not 535''s. Re-read it before applying.'; end if;
  for i in 1 .. cardinality(c_con_table) loop
    if exists (select 1 from pg_constraint k
                where k.conrelid = to_regclass('public.' || c_con_table[i])
                  and k.conname = c_con_table[i] || '_' || c_con_col[i] || '_0_100') then
      v_con_done := v_con_done + 1;
    end if;
  end loop;
  for i in 1 .. cardinality(c_closed) loop
    if to_regprocedure('public.' || c_closed[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_closed[i]))) <> c_closed_md5[i] then
      raise exception '535: public.% is missing or not the version this was tested against. Re-read it before applying.', c_closed[i]; end if;
    v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_closed[i]));
    if v_acl = c_closed_acl_after then v_closed_done := v_closed_done + 1;
    elsif v_acl is distinct from c_closed_acl_before then
      raise exception '535: the grants of public.% are not the tested ones (%). Re-read them before applying.', c_closed[i], v_acl; end if;
  end loop;
  for i in 1 .. cardinality(c_trg_table) loop
    if exists (select 1 from pg_trigger t where t.tgrelid = to_regclass('public.' || c_trg_table[i])
                  and t.tgname = 'audit_direct_change' and not t.tgisinternal) then
      if (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = to_regclass('public.' || c_trg_table[i])
             and t.tgname = 'audit_direct_change') is distinct from format(c_trg_def, c_trg_table[i]) then
        raise exception '535: a trigger audit_direct_change on public.% is there, but not 535''s. Re-read it before applying.', c_trg_table[i]; end if;
      v_trg_done := v_trg_done + 1;
    end if;
  end loop;
  if v_done = cardinality(c_sig) and v_new_done = cardinality(c_new_sig) and v_table_done
     and v_con_done = cardinality(c_con_table) and v_closed_done = cardinality(c_closed)
     and v_trg_done = cardinality(c_trg_table) then
    raise exception '535 is already in on this database; nothing was changed.'; end if;
  if v_done > 0 or v_new_done > 0 or v_table_done or v_con_done > 0 or v_closed_done > 0 or v_trg_done > 0 then
    raise exception '535: only part of it is in on this database (% of % functions patched, % of % helpers, table %, % of % constraints, % of % grants closed, % of % audit triggers). Re-read them before applying; nothing was changed.',
      v_done, cardinality(c_sig), v_new_done, cardinality(c_new_sig), case when v_table_done then 'there' else 'missing' end,
      v_con_done, cardinality(c_con_table), v_closed_done, cardinality(c_closed), v_trg_done, cardinality(c_trg_table); end if;
  -- The backfill keeps today's settings for every invoice with commission rows; that is what
  -- every standing row carries, or it refuses (a standing row: earned, paid or blocked, adjusting
  -- no other row, above 0; a package or bundle row whose sale snapshots its own rate is left out).
  select count(*), count(distinct c.invoice_id) into v_off, v_off_inv
    from public.commissions c cross join public.app_settings a
   where a.id = true and c.status::text in ('earned', 'paid', 'blocked')
     and c.adjusts_commission_id is null and c.commission_amount > 0
     and c.rate is distinct from case when c.tier::text = 'tier1' and c.product_type::text = 'third_party' then a.commission_tier1_third_rate
                                      when c.tier::text = 'tier1' then a.commission_tier1_own_rate
                                      when c.product_type::text = 'third_party' then a.commission_tier2_third_rate
                                      else a.commission_tier2_own_rate end
     and not (c.invoice_item_id is null
              and (exists (select 1 from public.credit_package_sales s where s.invoice_id = c.invoice_id
                             and case when c.tier::text = 'tier1' then s.tier1_rate_snapshot else s.tier2_rate_snapshot end is not null)
                   or exists (select 1 from public.premium_bundle_sales s where s.invoice_id = c.invoice_id
                             and case when c.tier::text = 'tier1' then s.tier1_rate_snapshot else s.tier2_rate_snapshot end is not null)));
  if v_off > 0 then
    raise exception '535: % standing commission row(s) on % invoice(s) carry a rate other than today''s settings for their tier and kind, so the backfill would keep other rates than they earned at. Look at them (and the rates'' last change) before applying; nothing was changed.',
      v_off, v_off_inv; end if;
  for i in 1 .. cardinality(c_con_table) loop
    execute format('select count(*) from public.%I where %I < 0 or %I > 100', c_con_table[i], c_con_col[i], c_con_col[i]) into v_acl;
    if v_acl::int > 0 then
      raise exception '535: % row(s) of public.% have a % outside 0 to 100. Look at them before applying; nothing was changed.',
        v_acl, c_con_table[i], c_con_col[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
      raise exception '535: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_after[i] then
      v_bad := v_bad || format(' %s=%s', c_sig[i], md5(v_def[i])); end if;
    if position('535 (security audit' in v_def[i]) = 0 then
      raise exception '535: the patched text of public.% has no 535 marker', c_sig[i]; end if;
  end loop;
  if v_bad <> '' then
    raise exception '535: the patched text is not the tested one:%', v_bad; end if;

  -- 2. Install: the table, then the helpers (the patched functions call them)
  execute c_table_def;
  execute format('comment on table public.invoice_affiliate_rates is %L', c_table_comment);
  alter table public.invoice_affiliate_rates enable row level security;
  revoke all on table public.invoice_affiliate_rates from public, anon, authenticated, service_role;
  for i in 1 .. cardinality(c_new_sig) loop
    execute c_new_def[i];
    execute format('revoke all on function public.%s from public, anon, authenticated, service_role', c_new_sig[i]);
  end loop;
  -- The backfill: every invoice that has a commission row keeps the current settings rates.
  insert into public.invoice_affiliate_rates
         (invoice_id, tier1_own_rate, tier1_third_rate, tier2_own_rate, tier2_third_rate, backfilled)
  select c.invoice_id, r.tier1_own, r.tier1_third, r.tier2_own, r.tier2_third, true
    from (select distinct x.invoice_id from public.commissions x where x.invoice_id is not null) c
   cross join lateral public.invoice_affiliate_rates_for(c.invoice_id) r;
  get diagnostics v_backfilled = row_count;
  raise notice '535: % invoice(s) with commission rows keep the current settings rates.', v_backfilled;
  -- The constraints on the packages' and bundles' own rates.
  for i in 1 .. cardinality(c_con_table) loop
    execute format('alter table public.%I add constraint %I check (%I is null or (%I >= 0 and %I <= 100))',
      c_con_table[i], c_con_table[i] || '_' || c_con_col[i] || '_0_100', c_con_col[i], c_con_col[i], c_con_col[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    execute v_def[i];
  end loop;
  for i in 1 .. cardinality(c_closed) loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', c_closed[i]);
  end loop;
  for i in 1 .. cardinality(c_trg_table) loop
    execute format('create trigger audit_direct_change after insert or delete or update on public.%I for each row '
                   || 'when (current_user = any (array[''anon''::name, ''authenticated''::name, ''service_role''::name])) '
                   || 'execute function public.trg_audit_direct_change()', c_trg_table[i]);
  end loop;

  -- 3. Checks after installing
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_class c, unnest(c.relacl) x where c.oid = 'public.invoice_affiliate_rates'::regclass) is distinct from c_table_acl
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.invoice_affiliate_rates'::regclass)
     or has_table_privilege('authenticated', 'public.invoice_affiliate_rates', 'select')
     or has_table_privilege('anon', 'public.invoice_affiliate_rates', 'select')
     or has_table_privilege('service_role', 'public.invoice_affiliate_rates', 'select')
     or has_table_privilege('service_role', 'public.invoice_affiliate_rates', 'insert')
     or has_table_privilege('service_role', 'public.invoice_affiliate_rates', 'update') then
    raise exception '535: public.invoice_affiliate_rates can be read or written by a login or the service role'; end if;
  if (select count(*) from public.invoice_affiliate_rates)
     <> (select count(distinct x.invoice_id) from public.commissions x where x.invoice_id is not null) then
    raise exception '535: the backfill does not cover every invoice with commission rows'; end if;
  for i in 1 .. cardinality(c_new_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception '535: public.% was made with an md5 other than the tested one (md5 %)', c_new_sig[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new_sig[i])) is distinct from c_new_acl
       or has_function_privilege('authenticated', to_regprocedure('public.' || c_new_sig[i]), 'execute')
       or has_function_privilege('anon', to_regprocedure('public.' || c_new_sig[i]), 'execute')
       or has_function_privilege('service_role', to_regprocedure('public.' || c_new_sig[i]), 'execute') then
      raise exception '535: public.% can be called by a login or the service role', c_new_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '535: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from c_acl[i] then
      raise exception '535: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_closed) loop
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_closed[i])) is distinct from c_closed_acl_after
       or has_function_privilege('authenticated', to_regprocedure('public.' || c_closed[i]), 'execute')
       or has_function_privilege('anon', to_regprocedure('public.' || c_closed[i]), 'execute')
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_closed[i]))) <> c_closed_md5[i] then
      raise exception '535: public.% can still be called by a login, or its text changed', c_closed[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '535: public.% changed', c_relied[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_trg_table) loop
    if (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = to_regclass('public.' || c_trg_table[i])
           and t.tgname = 'audit_direct_change') is distinct from format(c_trg_def, c_trg_table[i]) then
      raise exception '535: the audit trigger on public.% is not the tested one', c_trg_table[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
