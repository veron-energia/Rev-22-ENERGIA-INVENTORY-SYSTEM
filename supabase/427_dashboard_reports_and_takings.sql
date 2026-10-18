-- 427_dashboard_reports_and_takings.sql
--
-- WHAT WAS WRONG (the audit of 9 Oct 2026: REPORTS-3, REPORTS-6, REPORTS-7,
-- REPORTS-16, REPORTS-M3, and the Owner's answers Q20 and W2-B08-ALERT; the
-- Owner's answers of 18 Oct 2026, W4-B13-*)
--
--   * The Payment Summary's daily takings added up the payments on deleted
--     invoices. September 2026 on production: S$137,344.57 in all, of which
--     S$4,820.00 was on 5 deleted test invoices (INV-2026-0207, 0236, 0237,
--     0240, 0241) and S$22,080.50 was wallet credit spent, not money taken;
--     the money taken was S$110,444.07. daily_payments_by_method had no
--     deleted filter. (The wallet credit is the page's to keep apart: it is
--     told which methods are wallet credit.) It also had no check that the
--     caller is staff; it answered only for the caller's stores.
--   * The Dashboard's "Settled from credit" panel started "This week" on
--     Sunday while the Sales panel starts it on Monday; it dated credit by the
--     invoice, not by the wallet payment that spent it; it skipped sale
--     invoices waiting for a refund or cancellation; and it gave Managers
--     every store whether they work there or not (dashboard_credit_spend,
--     dashboard_credit_by_store). Nothing shows differently on production
--     today (22 credit allocations, none on a Sunday, every one dated as its
--     invoice; both Managers work at both stores).
--   * The Dashboard counted "Voucher redemptions" from voucher_redemptions:
--     65 rows, all time, from a table written only as a side effect of full
--     payment that misses some uses. The Reports page counts uses from the
--     sale invoices (September 2026: 38).
--   * dashboard_alerts_summary counted transfers awaiting receipt and open
--     discrepancies for every store, by the discrepancy flags, while the
--     Dashboard's Transfers card (transfer_receipt_alerts) counts the
--     transfers the login may see, by status: two figures for one thing. It
--     also worked out an FOC value no page reads (the Dashboard reads the FOC
--     report).
--   * Seven TikTok settlement lines for six orders (five placed 25 to 30
--     July, S$798.46 in six lines, and one on 28 August, Singapore time (the
--     audit's "27 August", read in UTC), S$256.51; S$1,054.97 in all) were
--     paid out by TikTok but no confirmed order file brought their orders in,
--     so their stock was never taken off at Adelphi. (The audit counted "six
--     July orders"; the sixth order is the August one.) Only the TikTok
--     Reconciliation tab listed them; the Dashboard had no alert, and there
--     was no way to say that one needs no stock taken. The tab's rows did not
--     even name the settlement line.
--   * A refunded test sale (INV-2026-0174, refunded 3 Sep 2026) still held
--     S$1,783.34 of credit that could be spent and 20 reward vouchers to be
--     claimed (LEG-0000071). Nothing showed it. Two more refunded sales
--     (INV-2026-0160 and INV-2026-0304) each still hold an unlimited-therapy
--     unit waiting to start (production, read 18 Oct 2026).
--   * The Dashboard's "Customers without source" tile always showed about
--     12,800 (12,847 on 18 Oct 2026): nearly all of them customers imported
--     in July, who were never asked. 120 were added since 1 Aug 2026
--     (REPORTS-16-SOURCE).
--
-- THE RULES
--
--   1. The Payment Summary reports money taken. Payments on deleted invoices
--      are not money taken; wallet credit is shown apart (the page).
--   2. The credit panel follows the Sales panel: its period
--      (resolve_period: Monday weeks, custom ranges checked), its stores
--      (user_has_store_access) and its invoices (invoice_counts_as_sale, live
--      ones). Credit counts on the Singapore day its wallet payment was taken
--      (payment_sales_date); credit with no payment on the invoice's sales day.
--   3. "Voucher uses this month" counts as the Reports page's Vouchers tab
--      counts: each invoice line redeemed with a voucher and each invoice
--      given one as an invoice-level discount, on live sale invoices with
--      money received this month.
--   4. The Owner, 9 Oct 2026 (Q20): the July TikTok orders were sold
--      before the app tracked TikTok stock: leave them. Take the stock off for
--      the 27 August order (TikTok's 28 August, Singapore time), after
--      checking it against the paused September stock count. Add a Dashboard
--      alert. (The two one-off repairs are scripts/tiktok/repair/427-*.sql,
--      not run here.) The Owner, 18 Oct 2026 (W4-B13-JULY-GROUP): yes, the 5
--      July orders (6 lines, S$798.46) are the ones to leave.
--   5. The Owner, 9 Oct 2026 (W2-B08-ALERT): a Dashboard alert for refunded or
--      cancelled sales that still hold credit or rewards, like the
--      INV-2026-0174 test. The Owner, 18 Oct 2026 (W4-B13-ALERT-THERAPY): it
--      also counts unlimited therapy bought on the sale and still open
--      (waiting to start, booked to start, or running).
--   6. The Owner, 18 Oct 2026 (W4-B13-MARK-REVIEWED, answer (a)): who may say
--      a settled TikTok line needs no stock taken off: Owners at every store,
--      Managers at the stores they work at; not Admins. With a reason,
--      audited. It is never undone by deleting it. The TikTok Import page's
--      Reconciliation tab has the "Mark reviewed" button.
--   7. The Owner, 18 Oct 2026 (W4-B13-NO-SOURCE-TILE, answer A): the
--      "Customers without source" tile counts only customers added since
--      1 Aug 2026 (Singapore time), and says so.
--
-- WHAT THIS DOES
--
--   * daily_payments_by_method(date,date,uuid) (replaced; same signature and
--     columns): leaves out payments on deleted invoices. First statement
--     require_store_access(p_store_id) (406): active staff, and a store they
--     work at. payment_methods_in_range calls it and is not changed.
--   * dashboard_credit_spend(text,date,date,uuid) and
--     dashboard_credit_by_store(text,date,date) (replaced; same signatures and
--     columns): rule 2. The first refuses a store the caller does not work at
--     (require_store_access), as dashboard_sales does; the label of a custom
--     range is resolve_period's ("01 Oct 2026 – 10 Oct 2026").
--   * dashboard_summary() (patched): adds 'voucher_uses_month' (rule 3).
--     Every key it sent is still sent.
--   * tiktok_settlement_reviews (new table): one row per settlement line an
--     Owner or Manager reviewed as needing no stock taken off: the decision
--     ('no_stock_needed'), the reason, who and when. Row level security on,
--     no rules; no client role may touch it; the service role may read it.
--   * tiktok_settlement_review_record(uuid[],text,uuid) (new; internal, the
--     service role's alone): rule 6, for a named Owner or Manager: each line
--     must be confirmed, current and still waiting for its order; a line
--     already reviewed is left as it is (a second run changes nothing).
--     Audited (audit_logs, tiktok_settlement_reviewed_no_stock, module
--     tiktok_import).
--   * review_tiktok_settlement_without_order(uuid[],text) (new; for signed-in
--     staff): first statement require_active_staff('{owner,manager}') (406),
--     then the internal function as the caller. The Reconciliation tab's
--     "Mark reviewed" button calls it (rule 6; the page offers it only where
--     the server allows it); the July repair records its reviews through the
--     internal function.
--   * dashboard_alerts_summary() (replaced): 'transfers' now carries
--     transfer_receipt_alerts' counts (the Transfers card's); 'tiktok' adds
--     'settled_without_order' (orders settled with no confirmed order file,
--     less the lines reviewed); 'sales' (new) carries 'holding_benefits' (how
--     many refunded or cancelled sales, or deleted invoices, at the caller's
--     stores still hold credit that can be spent, reward therapy or vouchers
--     still to be claimed, vouchers still held (sold on a line, given by a
--     promotion on a line, given with a bundle, or already claimed from the
--     sale's reward), or unlimited therapy bought on the sale and still open
--     (status pending_activation, scheduled or active)) and 'invoice_nos' (at
--     most ten of them); 'surveys' -> 'customers_without_source' counts only
--     customers added since 1 Aug 2026, Singapore time (rule 7), and
--     'customers_without_source_since' ('2026-08-01') is added for the tile's
--     label; 'foc' is gone. Every other key is as it was.
--   * report_tiktok_recon_exceptions(uuid) (replaced; same argument): a
--     reviewed line is no longer a 'settlement_without_order' exception, and
--     each row also names its store (store_id) and, for a settlement line,
--     the line (settlement_row_id; null for an order without settlement):
--     two columns added at the end, which the "Mark reviewed" button needs.
--     A function's columns cannot be changed in place, so it is dropped and
--     made again in the same transaction, with the grants it had. Nothing
--     depends on it (no view, rule or function on production, 18 Oct 2026);
--     the page reads it by name, and a page that does not know the two new
--     columns ignores them.
--
-- NOT CHANGED
--
--   * No row is written or changed: no payment, credit, reward, voucher,
--     stock or TikTok row. The July lines are reviewed, and the 28 August
--     order (the Owner's "27 August" order) is imported, by the one-off
--     repairs, at deploy, with the Owner's go-ahead.
--   * payment_methods_in_range, transfer_receipt_alerts, resolve_period,
--     dashboard_sales and the rest of the Sales panel, invoice_sales_ledger,
--     the TikTok import and settlement functions, the Xero exports (411).
--   * What is held on a refunded or cancelled sale: the alert reads it, it
--     does not clear it.
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. The
--   definitions are read and compared with the search path set to public.
--   Each changed function must be the production version read on 10 Oct 2026
--   (BEFORE) or already this migration's (AFTER), which is left alone, so a
--   re-run changes nothing; the two new functions and the table must be
--   missing or already exactly this version, and all of them in or none; no
--   other function takes any of these names. The functions relied on must be
--   the versions read on 10 Oct 2026, and the columns read must be there as
--   read. Every anchor must match exactly once, and every text built is
--   checked against its AFTER md5 before anything is installed. Changed
--   functions are installed with CREATE OR REPLACE, which keeps their grants,
--   except report_tiktok_recon_exceptions, whose columns change: it is
--   dropped and made again, and given back the grants read before. The
--   grants of every changed function are checked after against the ones read
--   before, and against the list read on 10 Oct 2026. The new
--   internal function is revoked from public, anon and authenticated and
--   granted to the service role (339); the page function is granted to
--   authenticated and the service role, not anon. Afterwards every md5,
--   grant, the table and its rules are as tested; then, switching role: the
--   anon key and a signed-in login with no profile are refused; and inside a
--   block that is always undone, a made-up Owner and member of staff, store
--   and settlement line: the Dashboard counts the line as settled with no
--   imported order and the Reconciliation tab lists it, with its store and
--   its id; Staff may not review
--   it; the Owner reviews it, the count and the exception go, the review is
--   audited, and a second review changes nothing. Nothing is printed and no
--   row remains.
--
-- BEFORE (production, 10 Oct 2026; md5 of pg_get_functiondef, search_path public):
--   changed
--   daily_payments_by_method(date,date,uuid)        809f7737461f5bd7cb08e929317c137a
--   dashboard_credit_spend(text,date,date,uuid)     540ee810178c15f5c09a6b305bc4bd0d  (406's AFTER)
--   dashboard_credit_by_store(text,date,date)       fe25ab311d6e3655500dea66c07fa0f1  (406's AFTER)
--   dashboard_alerts_summary()                      c3a45ca21c315d5cd6bd1bf36108d905  (406's AFTER)
--   dashboard_summary()                             d29c77f8ce2fda5e81b134bdced16dcc  (414's AFTER)
--   report_tiktok_recon_exceptions(uuid)            c6d208b64fbe097cda1dc20ba1d792bb
--   new (missing): tiktok_settlement_review_record(uuid[],text,uuid),
--     review_tiktok_settlement_without_order(uuid[],text), table tiktok_settlement_reviews
--   relied on, not changed
--   payment_methods_in_range(date,date,uuid)        f2458ea03365bf664691a8f2b3b68589
--   resolve_period(text,date,date)                  8a152d57ade1427d83c424a2c9e0a6a3
--   user_has_store_access(uuid)                     8c82c6bcb64f496c5a05a2b8dafa95f8
--   invoice_counts_as_sale(text)                    fb5eca0dce9a02dc91bd89e21b050ede
--   payment_sales_date(timestamp with time zone,timestamp with time zone)
--                                                   3e5161e4830f5f6fdc8f34a24266fdc9
--   invoice_sales_at(uuid)                          12fcbbceafb72566850f31cd430afee1
--   invoice_sales_ledger()                          6278b7ac91ebbd2ae96a7e2182a29f33
--   transfer_receipt_alerts()                       d6658b8fb23482d3cda9960086de54d6
--   tiktok_settlement_row_reconciled(boolean,text,text,numeric,numeric,numeric,numeric)
--                                                   d727c2199c97adcb25261ee2b27944c7
--   tiktok_negative_stock_alerts()                  e220e1441d930f34f58163ff5993db97
--   credit_package_reward_group(uuid)               7f8ac1b8bdc369110be03c8e9d260942
--   affiliate_referrer_balances()                   54ef098ba8f9e3d81bb45906c4607ab6  (410's AFTER)
--   rematch_tiktok_settlements(uuid,text)           b50a3627d49347019b81b88b75b4528e
--   require_active_staff(text[])                    877b3aa74cea559881979bb161c450e2  (406's AFTER)
--   require_store_access(uuid)                      f9332fd2f0092337d64501d8a647c23f  (406's AFTER)
--   sg_today()                                      1c1289f18e24d8370e9a6364c9c06fca
--   current_user_role()                             519b0a33a3548f970c5d585b6e76a389  (406; added 18 Oct 2026)
--   Every md5 above was read again on production on 18 Oct 2026 (head
--   20261016064105, 433) and is unchanged.
--   public function fingerprint (production, 18 Oct 2026, after 433)
--                                                   ff637c8e7adc37a4892a6bf361290c4b  (1244 functions)
--   (first written and tested against 897ad364eff917861989315bb2fa0e43 and
--   566e76f702c89c9846968e6fdd89cc45, production on 10 Oct 2026. The
--   fingerprint is not guarded: only the md5s above and the columns are.)
-- AFTER (for later guards):
--   daily_payments_by_method(date,date,uuid)        4c9bbd8a0782a86dae87a4484b09b625
--   dashboard_credit_spend(text,date,date,uuid)     6cc3d54d4f26bb5c7e4dda5956a20ac7
--   dashboard_credit_by_store(text,date,date)       631ae7cb8126247acc1036f0c70a4deb
--   dashboard_alerts_summary()                      2b632d0dcc23b82c6ef4e1438271debf  (18 Oct 2026; was d26ff6f6…)
--   dashboard_summary()                             aebb04c288d243798d899af658bf4a19
--   report_tiktok_recon_exceptions(uuid)            25679e40e7ffa5dea26f08876f22178a  (18 Oct 2026; was 45e092d6…)
--   tiktok_settlement_review_record(uuid[],text,uuid)        2d681e62d3c71e35f00bb872603fdf88
--   review_tiktok_settlement_without_order(uuid[],text)      a47ecdd18eaaa06bb4c9ca613e8164ed
--   public function fingerprint, production now (ff637c8e…) + 427 alone
--                                                   a9cc4631f251bdff6c15482e5c3ce2c6  (1246 functions)
--   on the planned stack (production now, then 418, 420, 431, 429, 417, 434,
--   422, 423, 424 and this)                        c7a0b7ff4c2277bd13c70f529cdf4b99  (1276 functions)
--   (18 Oct 2026, with the files then on disk: 431 cf50e4be…, 429 86dbb0e8…,
--   434 3678516a…, the others as in the hand-off; a later change to one of
--   them changes this. The same without 434: c088fd46bbf4235788245e6b88d823a9)
--   (the md5s above are the guards; the fingerprints are for checking only)
--
-- DEPLOY ORDER: this, then the front end (pushing to main deploys it), then,
-- with the Owner's go-ahead, scripts/tiktok/repair/427-july-orders-reviewed.sql
-- once, and scripts/tiktok/repair/427-take-off-27-aug-order.sql once given
-- the order's lines from TikTok Seller Center and checked against the paused
-- September count (the script says how; the app holds no record of what that
-- order contained). Each repair is first given production's ids (the Owner,
-- Adelphi, the settlement lines and orders) in the session: they are kept out
-- of this public repository, and the hand-off lists them. The pages live now
-- keep working against this: every key they read is still sent (the old
-- Dashboard's transfer tiles show the Transfers card's counts; it never read
-- 'foc'), and the old TikTok Import page ignores the Reconciliation tab's two
-- new columns. Until the new front end is out, the old Dashboard's
-- "Customers without source" tile already shows the count since 1 Aug under
-- its old label. The old Payment Summary leaves the deleted invoices'
-- payments out at once. The new pages against a database without this show
-- no voucher uses this month, no two new alerts (each reads 0), no "Mark
-- reviewed" button (no line ids are sent) and the plain "Customers without
-- source" label, so this goes first. The two
-- repairs check dashboard_alerts_summary's AFTER md5 above (2b632d0d…).
--
-- Test: scripts/dashboard/tests/dashboard-427.sql (every function above, as
-- each role, with fixtures; the guards and a re-run),
-- scripts/tiktok/tests/repair-427.sql (the two repairs),
-- scripts/dashboard/tests/dashboard-page.test.mjs (the Dashboard),
-- scripts/tiktok/tests/mark-reviewed.test.mjs (the "Mark reviewed" button),
-- scripts/invoices/tests/payment-summary.test.mjs (the Payment Summary),
-- scripts/reports/tests/reports-page.test.mjs and excel-export-sort.test.mjs,
-- scripts/reports/tests/reports-367.sql (the alerts' TikTok counts and the
-- Reconciliation tab; it needs a system wallet payment method, as production
-- has), scripts/xero/tests/template.test.mjs,
-- scripts/permissions/tests/function-grants.sql and staff-only-functions.sql.

set lock_timeout = '5s';

do $mig$
declare
  -- ── daily_payments_by_method, replaced ───────────────────────────────────
  c_dpm_def constant text := $def$CREATE OR REPLACE FUNCTION public.daily_payments_by_method(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_store_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(pay_date date, payment_method_id uuid, method_name text, amount numeric, payment_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select public.require_store_access(p_store_id);  -- 406: active staff, and a store they work at
 -- 427: the payments taken each day, by method, on live invoices only. A
 -- deleted invoice's payments are left out, as the Xero export leaves them
 -- out. Wallet credit is still listed by its method (payment_methods_in_range
 -- says which methods are wallet credit); the Payment Summary shows it apart
 -- from the money taken.
 select (coalesce(p.effective_at,p.created_at) at time zone 'Asia/Singapore')::date,m.id,m.name,
 round(sum(case when p.entry_kind='correction_reversal' then -p.amount else p.amount end),2),
 sum(case when p.entry_kind='correction_reversal' then -1 else 1 end)::int
 from public.invoice_payments p join public.payment_methods m on m.id=p.payment_method_id join public.invoices i on i.id=p.invoice_id
 where i.deleted_at is null and public.user_has_store_access(i.store_id) and (p_store_id is null or i.store_id=p_store_id)
 and (p_from is null or (coalesce(p.effective_at,p.created_at) at time zone 'Asia/Singapore')::date>=p_from)
 and (p_to is null or (coalesce(p.effective_at,p.created_at) at time zone 'Asia/Singapore')::date<=p_to)
 group by 1,2,3 order by 1,3
$function$
$def$;

  -- ── dashboard_credit_spend, replaced ─────────────────────────────────────
  c_dcs_def constant text := $def$CREATE OR REPLACE FUNCTION public.dashboard_credit_spend(p_period text DEFAULT 'day'::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_store_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r record; v_amount numeric; v_invoices integer;
begin
  perform public.require_store_access(p_store_id);  -- 406: active staff, and a store they work at
  -- 427: the same period as the Sales panel (resolve_period, as dashboard_sales
  -- reads it: weeks start on Monday, and a custom range is checked), the same
  -- stores (user_has_store_access: Managers see the stores they work at), the
  -- same invoices (invoice_counts_as_sale, live ones). Credit counts on the
  -- Singapore day its wallet payment was taken; credit with no payment counts
  -- on the invoice's sales day.
  select * into r from public.resolve_period(p_period, p_from, p_to);

  select coalesce(sum(a.amount - coalesce(a.reversed_amount, 0)), 0),
         count(distinct a.invoice_id)::integer
    into v_amount, v_invoices
    from public.invoice_line_credit_allocations a
    join public.invoices i on i.id = a.invoice_id
    left join public.invoice_payments p on p.id = a.payment_id
    cross join lateral (select coalesce(public.payment_sales_date(p.effective_at, p.created_at),
                                        (public.invoice_sales_at(i.id) at time zone 'Asia/Singapore')::date) as day) d
   where public.invoice_counts_as_sale(i.status::text)
     and i.deleted_at is null
     and public.user_has_store_access(i.store_id)
     and (p_store_id is null or i.store_id = p_store_id)
     and (r.date_from is null or d.day >= r.date_from)
     and (r.date_to   is null or d.day <= r.date_to);

  return jsonb_build_object(
    'label', r.label,
    'credit_spent', round(coalesce(v_amount, 0), 2),
    'invoices', coalesce(v_invoices, 0));
end $function$
$def$;

  -- ── dashboard_credit_by_store, replaced ──────────────────────────────────
  c_dcb_def constant text := $def$CREATE OR REPLACE FUNCTION public.dashboard_credit_by_store(p_period text DEFAULT 'day'::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS TABLE(store_id uuid, store_name text, credit_spent numeric, invoices integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record;
begin
  perform public.require_active_staff();  -- 406: active staff only
  -- 427: as dashboard_credit_spend, store by store: the Sales panel's period,
  -- the stores this login works at, sale invoices only, each credit on the day
  -- its wallet payment was taken.
  select * into r from public.resolve_period(p_period, p_from, p_to);

  return query
  select s.id, s.name,
         round(sum(x.amount), 2),
         count(distinct x.invoice_id)::integer
    from public.stores s
    join (select i.store_id as sid, a.invoice_id, a.amount - coalesce(a.reversed_amount, 0) as amount
            from public.invoice_line_credit_allocations a
            join public.invoices i on i.id = a.invoice_id
            left join public.invoice_payments p on p.id = a.payment_id
            cross join lateral (select coalesce(public.payment_sales_date(p.effective_at, p.created_at),
                                                (public.invoice_sales_at(i.id) at time zone 'Asia/Singapore')::date) as day) d
           where public.invoice_counts_as_sale(i.status::text)
             and i.deleted_at is null
             and (r.date_from is null or d.day >= r.date_from)
             and (r.date_to   is null or d.day <= r.date_to)) x on x.sid = s.id
   where s.deleted_at is null
     and public.user_has_store_access(s.id)
   group by s.id, s.name
  having sum(x.amount) > 0
   order by 3 desc;
end $function$
$def$;

  -- ── dashboard_alerts_summary, replaced ───────────────────────────────────
  c_das_def constant text := $def$CREATE OR REPLACE FUNCTION public.dashboard_alerts_summary()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.require_active_staff();  -- 406: active staff only
  select jsonb_build_object(
    -- 427: the counts of the Dashboard's Transfers card (transfer_receipt_alerts):
    -- the transfers this login may see, by their status. They were every
    -- store's, by the discrepancy flags, so the two could disagree.
    'transfers', (select jsonb_build_object('awaiting_receipt', t -> 'awaiting_receipt', 'overdue_7d', t -> 'overdue',
                                            'open_discrepancies', t -> 'open_discrepancies')
                    from public.transfer_receipt_alerts() t),
    'tiktok', jsonb_build_object(
      'imported_orders', (select count(distinct (store_id, order_id)) from public.tiktok_order_state),
      'unmatched_skus', (select count(distinct (o.store_id, o.seller_sku)) from public.tiktok_order_rows o
                          where o.staging_status = 'Unmatched SKU'
                            and not exists (select 1 from public.tiktok_sku_aliases a
                                             where a.store_id = o.store_id and a.seller_sku = o.seller_sku)),
      'staged_batches', (select count(*) from public.tiktok_import_batches b
                          where b.status = 'staged' and b.deleted_at is null),
      'orders_awaiting_settlement', (select count(*) from public.tiktok_order_state st
                                      where st.deducted_qty > 0
                                        and not exists (select 1 from public.tiktok_settlement_rows r
                                                         where r.store_id = st.store_id and r.matched_order_id = st.order_id
                                                           and r.is_current and r.confirmed)),
      'settlement_mismatches', (select count(*) from public.tiktok_settlement_rows r
                                 -- 367: an ad payment is not a settlement mismatch.
                                 where r.confirmed and r.is_current
                                   and public.tiktok_settlement_row_reconciled(r.reconciled, r.txn_class, r.match_status,
                                         r.settlement_amount, r.revenue_amount, r.fee_amount, r.adjustment_amount) is false),
      -- 427: orders TikTok settled (paid out) that no confirmed order file
      -- brought in, so their stock was never taken off. One an Owner or Manager
      -- reviewed as needing no stock taken off (tiktok_settlement_reviews) is
      -- not counted.
      'settled_without_order', (select count(distinct (r.store_id, coalesce(r.order_id, r.related_order_id, r.adjustment_id, r.id::text)))
                                  from public.tiktok_settlement_rows r
                                 where r.confirmed and r.is_current and r.match_status = 'pending'
                                   and not exists (select 1 from public.tiktok_settlement_reviews v where v.settlement_row_id = r.id)),
      'awaiting_physical_return', (select count(*) from public.tiktok_physical_returns pr where pr.status = 'awaiting'),
      'negative_stock', (select count(*) from public.tiktok_negative_stock_alerts())),
    -- 427 (the Owner, 18 Oct 2026): only customers added since 1 Aug 2026,
    -- Singapore time, with no source. The customers imported in July were
    -- never asked. The date is sent too, so the tile can say it.
    'surveys', jsonb_build_object(
      'customers_without_source', (select count(*) from public.customers c
                                    where c.deleted_at is null and c.source_option_id is null
                                      and c.created_at >= '2026-08-01 00:00:00+08'::timestamptz),
      'customers_without_source_since', '2026-08-01'),
    -- 427: refunded or cancelled sales (and deleted invoices) that still hold
    -- what they gave (the Owner, 9 Oct 2026): credit that can still be spent,
    -- reward therapy or vouchers still to be claimed, vouchers still held, and
    -- (the Owner, 18 Oct 2026) unlimited therapy bought on the sale and still
    -- open. In the stores this login works at; at most ten invoice numbers
    -- are listed.
    -- (The FOC value it used to send is gone: the Dashboard reads the FOC
    -- report itself.)
    'sales', (with x as (
        select i.invoice_no
          from public.invoices i
         where (i.status::text in ('refunded', 'cancelled') or i.deleted_at is not null)
           and public.user_has_store_access(i.store_id)
           and (exists (select 1 from public.customer_credit_lots l
                         where l.status = 'active' and l.remaining_amount > 0
                           and (l.id in (select s.credit_lot_id from public.credit_package_sales s where s.invoice_id = i.id
                                         union all select s.bonus_credit_lot_id from public.credit_package_sales s where s.invoice_id = i.id
                                         union all select b.paid_credit_lot_id from public.premium_bundle_sales b where b.invoice_id = i.id
                                         union all select b.bonus_credit_lot_id from public.premium_bundle_sales b where b.invoice_id = i.id
                                         union all select c.issued_lot_id from public.invoice_credit_splits c where c.invoice_id = i.id)
                                or (l.source_type = 'credit_package_progress'
                                    and l.source_record_id in (select it.id from public.invoice_items it where it.invoice_id = i.id))))
                or exists (select 1 from public.therapy_entitlements e
                            where e.status = 'pending_activation'
                              and (e.qualification_group_id in (select md5('credit_pkg_item:' || it.id::text)::uuid
                                                                  from public.invoice_items it where it.invoice_id = i.id)
                                   or e.qualification_group_id in (select public.credit_package_reward_group(s.id)
                                                                     from public.credit_package_sales s where s.invoice_id = i.id)
                                   or e.id in (select ti.entitlement_id from public.therapy_entitlement_invoices ti
                                                where ti.invoice_id = i.id)))
                -- Unlimited therapy bought on the sale and still open: waiting
                -- to start, booked to start, or running.
                or exists (select 1 from public.purchased_therapy_entitlements u
                            where u.invoice_id = i.id and u.status in ('pending_activation', 'scheduled', 'active'))
                -- Vouchers still held: sold on a line, given by a promotion on a
                -- line, given with a bundle, or claimed from this sale's reward
                -- (whatever that reward's status now).
                or exists (select 1 from public.customer_reward_vouchers v
                            where v.status = 'held'
                              and ((v.source_type in ('invoice_voucher_sale', 'invoice_promotion_voucher')
                                    and v.source_id in (select it.id from public.invoice_items it where it.invoice_id = i.id))
                                   or (v.source_type = 'premium_bundle'
                                       and v.source_id in (select b.id from public.premium_bundle_sales b where b.invoice_id = i.id))
                                   or v.entitlement_id in (select e.id from public.therapy_entitlements e
                                                            where e.qualification_group_id in (select md5('credit_pkg_item:' || it.id::text)::uuid
                                                                                                 from public.invoice_items it where it.invoice_id = i.id)
                                                               or e.qualification_group_id in (select public.credit_package_reward_group(s.id)
                                                                                                 from public.credit_package_sales s where s.invoice_id = i.id)
                                                               or e.id in (select ti.entitlement_id from public.therapy_entitlement_invoices ti
                                                                            where ti.invoice_id = i.id))))))
      select jsonb_build_object('holding_benefits', (select count(*) from x),
                                'invoice_nos', coalesce((select jsonb_agg(y.invoice_no order by y.invoice_no)
                                                           from (select x.invoice_no from x order by x.invoice_no limit 10) y), '[]'::jsonb)))
  )
$function$
$def$;

  -- ── New: a settled TikTok line reviewed, for a named Owner or Manager ────
  c_trr_def constant text := $def$CREATE OR REPLACE FUNCTION public.tiktok_settlement_review_record(p_row_ids uuid[], p_reason text, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text; v_reason text := btrim(coalesce(p_reason, '')); v_ids uuid[]; v_new uuid[] := '{}'; v_old integer := 0;
  r record;
begin
  -- 427: TikTok settled these lines (paid them out), but no confirmed order
  -- file brought their order in, so the app never took their stock off. An
  -- Owner or Manager may record that no stock is to be taken off for them
  -- (sold before the app tracked TikTok stock, or covered by a stock count),
  -- with a reason. The line then leaves the Dashboard's "Settled with no
  -- imported order" and the Reconciliation tab's exceptions. Nothing else
  -- changes: the settlement line, the stock and the order records stay as
  -- they are. An order that was missed is imported instead, through the
  -- TikTok Import page, which takes its stock off. The page reaches this
  -- through review_tiktok_settlement_without_order, as the signed-in Owner or
  -- Manager; a one-off repair names one (p_actor).
  select p.role::text into v_role from public.profiles p
   where p.id = p_actor and p.is_active and p.deleted_at is null
     and coalesce(p.invitation_status, 'accepted') = 'accepted';
  if v_role is null or v_role not in ('owner', 'manager') then
    raise exception 'Only active Owners and Managers can mark a TikTok settlement as needing no stock taken off.' using errcode = '42501'; end if;
  if v_reason = '' then
    raise exception 'A reason is required: say why no stock is to be taken off.'; end if;
  if char_length(v_reason) > 2000 then
    raise exception 'The reason is too long (2,000 characters at most).'; end if;
  select array_agg(distinct x) into v_ids from unnest(p_row_ids) x where x is not null;
  if v_ids is null then
    raise exception 'Choose at least one settlement line.'; end if;
  if cardinality(v_ids) > 500 then
    raise exception 'Choose at most 500 settlement lines at a time.'; end if;
  if (select count(*) from public.tiktok_settlement_rows s where s.id = any (v_ids)) <> cardinality(v_ids) then
    raise exception 'A settlement line was not found. Refresh and try again.'; end if;
  for r in select s.id, s.store_id, s.confirmed, s.is_current, s.match_status,
                  exists (select 1 from public.tiktok_settlement_reviews v where v.settlement_row_id = s.id) as reviewed
             from public.tiktok_settlement_rows s where s.id = any (v_ids)
            order by s.id for update of s loop
    if not (v_role = 'owner'
            or exists (select 1 from public.user_store_assignments usa
                        where usa.user_id = p_actor and usa.store_id = r.store_id)) then
      raise exception 'That settlement line belongs to a store you are not assigned to.' using errcode = '42501'; end if;
    if r.reviewed then
      v_old := v_old + 1;
    elsif not (r.confirmed and r.is_current and r.match_status = 'pending') then
      raise exception 'Settlement line % is not a confirmed line still waiting for its order. Refresh and try again.', r.id;
    else
      v_new := v_new || r.id;
    end if;
  end loop;
  if cardinality(v_new) > 0 then
    insert into public.tiktok_settlement_reviews (settlement_row_id, decision, reason, reviewed_by)
    select x, 'no_stock_needed', v_reason, p_actor from unnest(v_new) x;
    insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by, actor_role, module, reason)
    select 'tiktok_settlement_rows', x, 'tiktok_settlement_reviewed_no_stock', null,
           jsonb_build_object('decision', 'no_stock_needed', 'order_id', s.order_id, 'settlement_amount', s.settlement_amount),
           p_actor, v_role, 'tiktok_import', v_reason
      from unnest(v_new) x join public.tiktok_settlement_rows s on s.id = x;
  end if;
  return jsonb_build_object('reviewed', cardinality(v_new), 'already_reviewed', v_old);
end
$function$
$def$;

  -- ── New: the same, for the signed-in Owner or Manager ────────────────────
  c_rts_def constant text := $def$CREATE OR REPLACE FUNCTION public.review_tiktok_settlement_without_order(p_row_ids uuid[], p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.require_active_staff('{owner,manager}');  -- 406: active Owners and Managers only
  -- 427: a TikTok settlement line marked as needing no stock taken off, as
  -- the signed-in Owner or Manager (tiktok_settlement_review_record holds the
  -- rules).
  if auth.uid() is null then
    raise exception 'Sign in as an Owner or Manager to mark a TikTok settlement as reviewed.' using errcode = '42501'; end if;
  return public.tiktok_settlement_review_record(p_row_ids, p_reason, auth.uid());
end
$function$
$def$;

  -- ── Patched: the Dashboard's voucher uses this month ─────────────────────
  c_dsu_a constant text := $q$  return v_out || jsonb_build_object('today_sales',$q$;
  c_dsu_r constant text := $q$  -- 427: voucher uses this month (Singapore days), counted as the Reports
  -- page's Vouchers tab counts them: each invoice line redeemed with a
  -- voucher, and each invoice given one as an invoice-level discount, on the
  -- live sale invoices with money received this month (invoice_sales_ledger:
  -- the stores this login works at). The Dashboard used to count every row
  -- of voucher_redemptions ever, a table that misses some uses.
  v_out := v_out || (with e as (select l.invoice_id from public.invoice_sales_ledger() l
                                 where l.event_kind <> 'refund'
                                   and l.sales_date between date_trunc('month', v_today)::date and v_today
                                 group by l.invoice_id having sum(l.amount) > 0)
                     select jsonb_build_object('voucher_uses_month',
                              (select count(*) from public.invoice_items it join e on e.invoice_id = it.invoice_id
                                where it.line_voucher_id is not null)
                              + (select count(*) from public.invoices iv join e on e.invoice_id = iv.id
                                  where iv.discount_voucher_id is not null)));
  return v_out || jsonb_build_object('today_sales',$q$;

  -- ── report_tiktok_recon_exceptions, replaced (two columns added) ─────────
  -- A reviewed line is no longer an exception, and each row names its store
  -- and, for a settlement line, the line, which the "Mark reviewed" button
  -- sends.
  c_rec_def constant text := $def$CREATE OR REPLACE FUNCTION public.report_tiktok_recon_exceptions(p_store_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(kind text, store_name text, order_id text, detail text, amount numeric, store_id uuid, settlement_row_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 427: each row also names its store (store_id) and, for a settlement line,
  -- the line itself (settlement_row_id), so the Reconciliation tab can mark a
  -- settled line with no imported order as reviewed.
  -- Imported orders with stock deducted but no current settlement yet.
  select 'order_without_settlement', s.name, st.order_id,
         'net deducted ' || sum(st.deducted_qty)::text || ' unit(s)', null::numeric,
         st.store_id, null::uuid
    from public.tiktok_order_state st
    join public.stores s on s.id = st.store_id
   where st.deducted_qty > 0
     and not exists (select 1 from public.tiktok_settlement_rows r
                      where r.store_id = st.store_id and r.matched_order_id = st.order_id
                        and r.is_current and r.confirmed)
     and (p_store_id is null or st.store_id = p_store_id)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(st.store_id))
   group by s.name, st.store_id, st.order_id
  union all
  -- Confirmed settlements still waiting for their order.
  select 'settlement_without_order', s.name, r.order_id,
         coalesce(r.transaction_type,'') , r.settlement_amount, r.store_id, r.id
    from public.tiktok_settlement_rows r
    join public.stores s on s.id = r.store_id
   where r.confirmed and r.is_current and r.match_status = 'pending'
     -- 427: a line an Owner or Manager reviewed as needing no stock taken off
     -- (tiktok_settlement_reviews) is no longer an exception.
     and not exists (select 1 from public.tiktok_settlement_reviews v where v.settlement_row_id = r.id)
     and (p_store_id is null or r.store_id = p_store_id)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(r.store_id))
  union all
  -- Settlement ≠ Revenue + Fees beyond the $0.01 tolerance.
  select 'reconciliation_difference', s.name, r.order_id,
         -- 367: an ad payment is measured against Revenue + Fees + Adjustment,
         -- the same rule that flags it, so the gap shown is the gap it has.
         case when r.txn_class = 'finance' and r.match_status = 'no_match_needed'
           then 'settlement ' || r.settlement_amount::text || ' vs revenue+fees+adjustment '
             || (coalesce(r.revenue_amount,0) + coalesce(r.fee_amount,0) + coalesce(r.adjustment_amount,0))::text
           else 'settlement ' || r.settlement_amount::text || ' vs revenue+fees '
             || (coalesce(r.revenue_amount,0) + coalesce(r.fee_amount,0))::text end,
         r.settlement_amount - (coalesce(r.revenue_amount,0) + coalesce(r.fee_amount,0)
           + case when r.txn_class = 'finance' and r.match_status = 'no_match_needed'
               then coalesce(r.adjustment_amount,0) else 0 end),
         r.store_id, r.id
    from public.tiktok_settlement_rows r
    join public.stores s on s.id = r.store_id
   -- 367: an ad payment reconciles on its Adjustment; it is not an exception.
   where r.confirmed and r.is_current
     and public.tiktok_settlement_row_reconciled(r.reconciled, r.txn_class, r.match_status,
           r.settlement_amount, r.revenue_amount, r.fee_amount, r.adjustment_amount) is false
     and (p_store_id is null or r.store_id = p_store_id)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(r.store_id))
   order by 1, 3
$function$
$def$;

  -- ── AFTER md5s ───────────────────────────────────────────────────────────
  c_dpm_after constant text := '4c9bbd8a0782a86dae87a4484b09b625';
  c_dcs_after constant text := '6cc3d54d4f26bb5c7e4dda5956a20ac7';
  c_dcb_after constant text := '631ae7cb8126247acc1036f0c70a4deb';
  c_das_after constant text := '2b632d0dcc23b82c6ef4e1438271debf';
  c_dsu_after constant text := 'aebb04c288d243798d899af658bf4a19';
  c_rec_after constant text := '25679e40e7ffa5dea26f08876f22178a';
  c_trr_after constant text := '2d681e62d3c71e35f00bb872603fdf88';
  c_rts_after constant text := 'a47ecdd18eaaa06bb4c9ca613e8164ed';

  -- The table as this makes it: columns in order, then constraints by text.
  c_cols constant text := 'settlement_row_id uuid not null|decision text not null|reason text not null|reviewed_by uuid not null|reviewed_at timestamp with time zone not null default now()';
  c_cons constant text := 'CHECK (((btrim(reason) <> ''''::text) AND (char_length(reason) <= 2000)))|CHECK ((decision = ''no_stock_needed''::text))|FOREIGN KEY (reviewed_by) REFERENCES profiles(id)|FOREIGN KEY (settlement_row_id) REFERENCES tiktok_settlement_rows(id)|PRIMARY KEY (settlement_row_id)';
  c_changed constant text[] := array['daily_payments_by_method(date,date,uuid)', 'dashboard_credit_spend(text,date,date,uuid)',
                                     'dashboard_credit_by_store(text,date,date)', 'dashboard_alerts_summary()',
                                     'dashboard_summary()', 'report_tiktok_recon_exceptions(uuid)'];
  c_new constant text[] := array['tiktok_settlement_review_record(uuid[],text,uuid)',
                                 'review_tiktok_settlement_without_order(uuid[],text)'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  r record; d text; v text; n int; k int; i int; v_bad text;
  v_fns text[] := '{}'; v_defs text[] := '{}';
  v_table_new boolean; v_n_new int;
  v_acl_before text[]; v_acl_after text[];
  v_owner uuid; v_staff uuid; v_store uuid; v_batch uuid; v_row uuid; v_before int; j jsonb;
begin
  perform set_config('search_path', 'public', true);

  -- ── Guards, anchors and new texts: nothing changes unless all pass ───────
  -- In install order: the review functions (the table is made first), then
  -- the changed ones; the alerts and the exceptions read the table.
  for r in select * from (values
    ('tiktok_settlement_review_record(uuid[],text,uuid)', null::text, c_trr_after, c_trr_def, null::text[]),
    ('review_tiktok_settlement_without_order(uuid[],text)', null::text, c_rts_after, c_rts_def, null::text[]),
    ('daily_payments_by_method(date,date,uuid)', '809f7737461f5bd7cb08e929317c137a', c_dpm_after, c_dpm_def, null::text[]),
    ('dashboard_credit_spend(text,date,date,uuid)', '540ee810178c15f5c09a6b305bc4bd0d', c_dcs_after, c_dcs_def, null::text[]),
    ('dashboard_credit_by_store(text,date,date)', 'fe25ab311d6e3655500dea66c07fa0f1', c_dcb_after, c_dcb_def, null::text[]),
    ('dashboard_alerts_summary()', 'c3a45ca21c315d5cd6bd1bf36108d905', c_das_after, c_das_def, null::text[]),
    ('dashboard_summary()', 'd29c77f8ce2fda5e81b134bdced16dcc', c_dsu_after, null::text, array[[c_dsu_a, c_dsu_r]]),
    ('report_tiktok_recon_exceptions(uuid)', 'c6d208b64fbe097cda1dc20ba1d792bb', c_rec_after, c_rec_def, null::text[])
  ) x(fn, before_md5, after_md5, whole, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      if r.before_md5 is not null then
        raise exception '427: public.% is missing', r.fn; end if;
      d := r.whole;
    else
      d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
      v := md5(d);
      if v = r.after_md5 then
        continue;  -- already this version; left alone
      elsif r.before_md5 is null then
        raise exception '427: public.% already exists with another text (md5 %). Re-read it and re-test before applying.', r.fn, v;
      elsif v <> r.before_md5 then
        raise exception '427: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
      end if;
      if r.edits is null then
        d := r.whole;
      else
        for k in 1 .. array_length(r.edits, 1) loop
          n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
          if n <> 1 then
            raise exception '427: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
          d := replace(d, r.edits[k][1], r.edits[k][2]);
        end loop;
      end if;
    end if;
    if md5(d) <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || md5(d)); end if;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;
  if v_bad is not null then
    raise exception '427: a text built is not the tested one: %', v_bad; end if;

  -- The new functions and the table: all in, or none.
  select count(*) into v_n_new from unnest(c_new) f where to_regprocedure('public.' || f) is not null;
  v_table_new := to_regclass('public.tiktok_settlement_reviews') is null;
  if not ((v_n_new = 0 and v_table_new) or (v_n_new = cardinality(c_new) and not v_table_new)) then
    raise exception '427: only part of this migration is installed (% of % new functions, table %); re-read and re-test',
      v_n_new, cardinality(c_new), case when v_table_new then 'missing' else 'there' end; end if;
  if not v_table_new then
    select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
                      || case when a.attnotnull then ' not null' else '' end
                      || coalesce(' default ' || pg_get_expr(dd.adbin, dd.adrelid), ''), '|' order by a.attnum) into v
      from pg_attribute a left join pg_attrdef dd on dd.adrelid = a.attrelid and dd.adnum = a.attnum
     where a.attrelid = 'public.tiktok_settlement_reviews'::regclass and a.attnum > 0 and not a.attisdropped;
    if v is distinct from c_cols then
      raise exception '427: public.tiktok_settlement_reviews exists and is not this migration''s (%)', v; end if;
    select string_agg(pg_get_constraintdef(k2.oid), '|' order by pg_get_constraintdef(k2.oid) collate "C") into v
      from pg_constraint k2 where k2.conrelid = 'public.tiktok_settlement_reviews'::regclass;
    if v is distinct from c_cons then
      raise exception '427: public.tiktok_settlement_reviews has other constraints (%)', v; end if;
    if exists (select 1 from pg_trigger t where t.tgrelid = 'public.tiktok_settlement_reviews'::regclass and not t.tgisinternal) then
      raise exception '427: public.tiktok_settlement_reviews has a trigger; it should have none'; end if;
  end if;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('daily_payments_by_method', 'dashboard_credit_spend', 'dashboard_credit_by_store',
                       'dashboard_alerts_summary', 'dashboard_summary', 'report_tiktok_recon_exceptions',
                       'tiktok_settlement_review_record', 'review_tiktok_settlement_without_order')
     and p.oid::regprocedure::text <> all (c_changed || c_new);
  if v_bad is not null then
    raise exception '427: another function takes one of these names: %', v_bad; end if;

  -- Relied on, not changed: the versions read on 10 Oct 2026.
  for r in select * from (values
    ('payment_methods_in_range(date,date,uuid)', 'f2458ea03365bf664691a8f2b3b68589'),
    ('resolve_period(text,date,date)', '8a152d57ade1427d83c424a2c9e0a6a3'),
    ('user_has_store_access(uuid)', '8c82c6bcb64f496c5a05a2b8dafa95f8'),
    ('invoice_counts_as_sale(text)', 'fb5eca0dce9a02dc91bd89e21b050ede'),
    ('payment_sales_date(timestamp with time zone,timestamp with time zone)', '3e5161e4830f5f6fdc8f34a24266fdc9'),
    ('invoice_sales_at(uuid)', '12fcbbceafb72566850f31cd430afee1'),
    ('invoice_sales_ledger()', '6278b7ac91ebbd2ae96a7e2182a29f33'),
    ('transfer_receipt_alerts()', 'd6658b8fb23482d3cda9960086de54d6'),
    ('tiktok_settlement_row_reconciled(boolean,text,text,numeric,numeric,numeric,numeric)', 'd727c2199c97adcb25261ee2b27944c7'),
    ('tiktok_negative_stock_alerts()', 'e220e1441d930f34f58163ff5993db97'),
    ('credit_package_reward_group(uuid)', '7f8ac1b8bdc369110be03c8e9d260942'),
    ('affiliate_referrer_balances()', '54ef098ba8f9e3d81bb45906c4607ab6'),
    ('rematch_tiktok_settlements(uuid,text)', 'b50a3627d49347019b81b88b75b4528e'),
    ('require_active_staff(text[])', '877b3aa74cea559881979bb161c450e2'),
    ('require_store_access(uuid)', 'f9332fd2f0092337d64501d8a647c23f'),
    ('sg_today()', '1c1289f18e24d8370e9a6364c9c06fca'),
    ('current_user_role()', '519b0a33a3548f970c5d585b6e76a389')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '427: public.% is missing or not the version read on 10 Oct 2026. Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;

  -- The columns read, as read on 10 Oct 2026.
  for r in select * from (values
    ('public.invoices', 'deleted_at timestamp with time zone|discount_voucher_id uuid|id uuid not null|invoice_no text not null|status invoice_status not null|store_id uuid not null',
     array['id', 'invoice_no', 'status', 'deleted_at', 'store_id', 'discount_voucher_id']),
    ('public.invoice_items', 'id uuid not null|invoice_id uuid not null|line_voucher_id uuid',
     array['id', 'invoice_id', 'line_voucher_id']),
    ('public.invoice_payments', 'amount numeric(12,2) not null|created_at timestamp with time zone not null|effective_at timestamp with time zone|entry_kind text not null|id uuid not null|invoice_id uuid not null|payment_method_id uuid not null',
     array['id', 'invoice_id', 'payment_method_id', 'amount', 'entry_kind', 'effective_at', 'created_at']),
    ('public.payment_methods', 'id uuid not null|name text not null',
     array['id', 'name']),
    ('public.invoice_line_credit_allocations', 'amount numeric(12,2) not null|invoice_id uuid not null|payment_id uuid|reversed_amount numeric(12,2) not null',
     array['invoice_id', 'amount', 'reversed_amount', 'payment_id']),
    ('public.stores', 'deleted_at timestamp with time zone|id uuid not null|name text not null',
     array['id', 'name', 'deleted_at']),
    ('public.customer_credit_lots', 'id uuid not null|remaining_amount numeric(12,2) not null|source_record_id uuid|source_type text not null|status text not null',
     array['id', 'status', 'remaining_amount', 'source_type', 'source_record_id']),
    ('public.credit_package_sales', 'bonus_credit_lot_id uuid|credit_lot_id uuid|id uuid not null|invoice_id uuid',
     array['id', 'invoice_id', 'credit_lot_id', 'bonus_credit_lot_id']),
    ('public.premium_bundle_sales', 'bonus_credit_lot_id uuid|id uuid not null|invoice_id uuid|paid_credit_lot_id uuid',
     array['id', 'invoice_id', 'paid_credit_lot_id', 'bonus_credit_lot_id']),
    ('public.invoice_credit_splits', 'invoice_id uuid not null|issued_lot_id uuid',
     array['invoice_id', 'issued_lot_id']),
    ('public.therapy_entitlements', 'id uuid not null|qualification_group_id uuid|status text not null',
     array['id', 'status', 'qualification_group_id']),
    ('public.therapy_entitlement_invoices', 'entitlement_id uuid not null|invoice_id uuid not null',
     array['entitlement_id', 'invoice_id']),
    ('public.customer_reward_vouchers', 'entitlement_id uuid|source_id uuid|source_type text|status text not null',
     array['status', 'source_type', 'source_id', 'entitlement_id']),
    ('public.tiktok_settlement_rows', 'adjustment_id text|confirmed boolean not null|id uuid not null|is_current boolean not null|match_status text not null|order_id text|related_order_id text|settlement_amount numeric(12,2)|store_id uuid not null',
     array['id', 'store_id', 'order_id', 'related_order_id', 'adjustment_id', 'confirmed', 'is_current', 'match_status', 'settlement_amount']),
    ('public.profiles', 'deleted_at timestamp with time zone|id uuid not null|invitation_status text|is_active boolean not null|role user_role not null',
     array['id', 'role', 'is_active', 'deleted_at', 'invitation_status']),
    ('public.user_store_assignments', 'store_id uuid not null|user_id uuid not null',
     array['user_id', 'store_id']),
    ('public.audit_logs', 'action text not null|actor_role text|changed_by uuid|module text|new_data jsonb|old_data jsonb|reason text|record_id uuid|table_name text not null',
     array['table_name', 'record_id', 'action', 'old_data', 'new_data', 'changed_by', 'actor_role', 'module', 'reason']),
    ('public.customers', 'created_at timestamp with time zone not null|deleted_at timestamp with time zone|source_option_id uuid',
     array['created_at', 'deleted_at', 'source_option_id']),
    ('public.purchased_therapy_entitlements', 'invoice_id uuid not null|status text not null',
     array['invoice_id', 'status'])
  ) x(tbl, shape, cols)
  loop
    select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end,
                      '|' order by a.attname) into v
      from pg_attribute a
     where a.attrelid = r.tbl::regclass and a.attnum > 0 and not a.attisdropped and a.attname = any (r.cols);
    if v is distinct from r.shape then
      raise exception '427: % is not shaped as read on 10 Oct 2026 (%)', r.tbl, v; end if;
  end loop;

  -- The grants of what is changed, as a set, to compare after.
  select array_agg(x order by x collate "C") into v_acl_before from (
    select p.oid::regprocedure::text || ':' || coalesce(a.grantee::regrole::text, 'public') || ':' || a.privilege_type x
      from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.pronamespace = 'public'::regnamespace
       and p.oid::regprocedure::text = any (c_changed)
       and a.grantee <> p.proowner) g;

  -- ── Change ───────────────────────────────────────────────────────────────
  if v_table_new then
    create table public.tiktok_settlement_reviews (
      settlement_row_id uuid primary key references public.tiktok_settlement_rows(id),
      decision text not null check (decision = 'no_stock_needed'),
      reason text not null check (btrim(reason) <> '' and char_length(reason) <= 2000),
      reviewed_by uuid not null references public.profiles(id),
      reviewed_at timestamptz not null default now());
    comment on table public.tiktok_settlement_reviews is
      '427: a confirmed TikTok settlement line with no imported order that an Owner or Manager reviewed as needing no stock taken off, with the reason. Written by tiktok_settlement_review_record() only.';
  end if;
  alter table public.tiktok_settlement_reviews enable row level security;
  revoke all on table public.tiktok_settlement_reviews from public, anon, authenticated, service_role;
  grant select on table public.tiktok_settlement_reviews to service_role;

  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    if v_fns[i] = 'report_tiktok_recon_exceptions(uuid)' then
      -- Its columns change (store_id and settlement_row_id are added at the
      -- end), which CREATE OR REPLACE cannot do. So it is dropped and made
      -- again in this same transaction (nothing depends on it), and given
      -- back exactly the grants it had (v_acl_before; checked below).
      execute 'drop function public.report_tiktok_recon_exceptions(uuid)';
      execute v_defs[i];
      execute 'revoke all on function public.report_tiktok_recon_exceptions(uuid) from public, anon, authenticated, service_role';
      for v in select split_part(a, ':', 2) from unnest(v_acl_before) a
                where split_part(a, ':', 1) = 'report_tiktok_recon_exceptions(uuid)' and split_part(a, ':', 3) = 'EXECUTE' loop
        execute format('grant execute on function public.report_tiktok_recon_exceptions(uuid) to %s', v);
      end loop;
    else
      execute v_defs[i];
    end if;
    if v_fns[i] = 'tiktok_settlement_review_record(uuid[],text,uuid)' then
      execute format('revoke all on function public.%s from public, anon, authenticated', v_fns[i]);
      execute format('grant execute on function public.%s to service_role', v_fns[i]);
    elsif v_fns[i] = 'review_tiktok_settlement_without_order(uuid[],text)' then
      execute format('revoke all on function public.%s from public, anon', v_fns[i]);
      execute format('grant execute on function public.%s to authenticated, service_role', v_fns[i]);
    end if;
  end loop;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  v_bad := null;
  for r in select * from (values
    ('daily_payments_by_method(date,date,uuid)', c_dpm_after), ('dashboard_credit_spend(text,date,date,uuid)', c_dcs_after),
    ('dashboard_credit_by_store(text,date,date)', c_dcb_after), ('dashboard_alerts_summary()', c_das_after),
    ('dashboard_summary()', c_dsu_after), ('report_tiktok_recon_exceptions(uuid)', c_rec_after),
    ('tiktok_settlement_review_record(uuid[],text,uuid)', c_trr_after),
    ('review_tiktok_settlement_without_order(uuid[],text)', c_rts_after)) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
    if (select pg_get_userbyid(p.proowner) from pg_proc p where p.oid = to_regprocedure('public.' || r.fn))
       is distinct from current_user then
      raise exception '427: public.% is not owned by the role that checked it', r.fn; end if;
  end loop;
  if v_bad is not null then
    raise exception '427: installed with md5s other than the tested ones: %', v_bad; end if;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.tiktok_settlement_reviews'::regclass) then
    raise exception '427: row level security is off on public.tiktok_settlement_reviews'; end if;
  if exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'tiktok_settlement_reviews') then
    raise exception '427: public.tiktok_settlement_reviews has a rule; it should have none'; end if;

  -- ── Grants, by the catalogue ─────────────────────────────────────────────
  -- What was changed has exactly the grants it had.
  select array_agg(x order by x collate "C") into v_acl_after from (
    select p.oid::regprocedure::text || ':' || coalesce(a.grantee::regrole::text, 'public') || ':' || a.privilege_type x
      from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.pronamespace = 'public'::regnamespace
       and p.oid::regprocedure::text = any (c_changed)
       and a.grantee <> p.proowner) g;
  if v_acl_after is distinct from v_acl_before then
    raise exception '427: the grants of the changed functions changed (% before, % after)', v_acl_before, v_acl_after; end if;
  if v_acl_after is distinct from array[
       'daily_payments_by_method(date,date,uuid):authenticated:EXECUTE', 'daily_payments_by_method(date,date,uuid):service_role:EXECUTE',
       'dashboard_alerts_summary():authenticated:EXECUTE', 'dashboard_alerts_summary():service_role:EXECUTE',
       'dashboard_credit_by_store(text,date,date):authenticated:EXECUTE', 'dashboard_credit_by_store(text,date,date):service_role:EXECUTE',
       'dashboard_credit_spend(text,date,date,uuid):authenticated:EXECUTE', 'dashboard_credit_spend(text,date,date,uuid):service_role:EXECUTE',
       'dashboard_summary():authenticated:EXECUTE', 'dashboard_summary():service_role:EXECUTE',
       'report_tiktok_recon_exceptions(uuid):authenticated:EXECUTE', 'report_tiktok_recon_exceptions(uuid):service_role:EXECUTE'] then
    raise exception '427: the grants of the changed functions are not the ones read on 10 Oct 2026 (%)', v_acl_after; end if;
  -- The internal one is the service role's alone (339); the page's is
  -- signed-in staff's, never the anon key's.
  v := 'public.tiktok_settlement_review_record(uuid[],text,uuid)';
  if has_function_privilege('anon', v, 'execute') or has_function_privilege('authenticated', v, 'execute')
     or not has_function_privilege('service_role', v, 'execute')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = to_regprocedure(v) and a.grantee = 0) then
    raise exception '427: % is not the service role''s alone', v; end if;
  v := 'public.review_tiktok_settlement_without_order(uuid[],text)';
  if has_function_privilege('anon', v, 'execute') or not has_function_privilege('authenticated', v, 'execute')
     or not has_function_privilege('service_role', v, 'execute')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = to_regprocedure(v) and a.grantee = 0) then
    raise exception '427: % is not signed-in staff''s and the service role''s alone', v; end if;
  if has_table_privilege('anon', 'public.tiktok_settlement_reviews', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'public.tiktok_settlement_reviews', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('service_role', 'public.tiktok_settlement_reviews', 'insert,update,delete,truncate,references,trigger')
     or not has_table_privilege('service_role', 'public.tiktok_settlement_reviews', 'select') then
    raise exception '427: the grants on public.tiktok_settlement_reviews are not as tested'; end if;

  -- ── Behaviour, switching role (nothing is printed, no row remains) ───────
  -- The anon key, and a signed-in login with no profile (an affiliate's, say).
  foreach v in array array['anon', 'authenticated'] loop
    perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', v)::text, true);
    execute format('set local role %I', v);
    begin
      perform public.review_tiktok_settlement_without_order(array[gen_random_uuid()], '427 check');
      raise exception '427: % reviewed a TikTok settlement', v;
    exception when insufficient_privilege then null;
    end;
    begin
      perform count(*) from public.daily_payments_by_method(null, null, null);
      raise exception '427: % read the daily takings', v;
    exception when insufficient_privilege then null;
    end;
    begin
      perform count(*) from public.tiktok_settlement_reviews;
      raise exception '427: % read tiktok_settlement_reviews', v;
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';
  end loop;
  perform set_config('request.jwt.claims', '', true);

  -- A made-up Owner, member of staff, store and settlement line (always
  -- undone): the line counts as settled with no imported order and is an
  -- exception; Staff may not review it; the Owner reviews it, and it is
  -- neither; the review is audited; a second review changes nothing.
  begin
    insert into auth.users (id, email) values (gen_random_uuid(), '427-check-owner-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_owner;
    insert into auth.users (id, email) values (gen_random_uuid(), '427-check-staff-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_staff;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '427 check', u.email, x.role::public.user_role, true
      from auth.users u join (values (v_owner, 'owner'), (v_staff, 'staff')) x(id, role) on x.id = u.id;
    insert into public.stores (name, code, country_code) values ('427 check store', 'C427' || substr(md5(random()::text), 1, 6), 'SG')
      returning id into v_store;
    insert into public.user_store_assignments (user_id, store_id) values (v_staff, v_store);
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_before := (public.dashboard_alerts_summary() -> 'tiktok' ->> 'settled_without_order')::int;
    execute 'reset role';
    insert into public.tiktok_import_batches (store_id, file_kind, file_name, status, uploaded_by)
    values (v_store, 'settlement', '427 check', 'confirmed', v_owner) returning id into v_batch;
    insert into public.tiktok_settlement_rows (batch_id, store_id, row_no, order_id, transaction_type, txn_class,
                                               settlement_amount, revenue_amount, fee_amount, match_status, confirmed, is_current)
    values (v_batch, v_store, 1, '427-CHECK-ORDER', 'Order', 'order', 10, 12, -2, 'pending', true, true)
    returning id into v_row;

    execute 'set local role authenticated';
    j := public.dashboard_alerts_summary();
    if (j -> 'tiktok' ->> 'settled_without_order')::int <> v_before + 1
       or not (j ? 'sales') or (j -> 'sales' ->> 'holding_benefits') is null or j ? 'foc'
       or (j -> 'transfers') is distinct from (select jsonb_build_object('awaiting_receipt', t -> 'awaiting_receipt', 'overdue_7d', t -> 'overdue',
                                                                          'open_discrepancies', t -> 'open_discrepancies')
                                                 from public.transfer_receipt_alerts() t) then
      raise exception '427: the Dashboard alerts are not as tested (%)', j; end if;
    if (select count(*) from public.report_tiktok_recon_exceptions(v_store) e
         where e.kind = 'settlement_without_order' and e.order_id = '427-CHECK-ORDER'
           and e.store_id = v_store and e.settlement_row_id = v_row) <> 1 then
      raise exception '427: the Reconciliation tab does not list the line, its store and its id'; end if;
    execute 'reset role';

    perform set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      perform public.review_tiktok_settlement_without_order(array[v_row], '427 check');
      raise exception '427: Staff reviewed a TikTok settlement';
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';

    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      perform public.review_tiktok_settlement_without_order(array[v_row], '   ');
      raise exception '427: a review with no reason was accepted';
    exception when raise_exception then
      if sqlerrm not like 'A reason is required%' then raise; end if;
    end;
    j := public.review_tiktok_settlement_without_order(array[v_row, v_row], '427 check');
    if j is distinct from '{"reviewed": 1, "already_reviewed": 0}'::jsonb then
      raise exception '427: the review answered %', j; end if;
    if (public.dashboard_alerts_summary() -> 'tiktok' ->> 'settled_without_order')::int <> v_before
       or exists (select 1 from public.report_tiktok_recon_exceptions(v_store) e where e.order_id = '427-CHECK-ORDER') then
      raise exception '427: a reviewed line is still counted or listed'; end if;
    if public.review_tiktok_settlement_without_order(array[v_row], '427 check again')
       is distinct from '{"reviewed": 0, "already_reviewed": 1}'::jsonb then
      raise exception '427: a second review was not left as it was'; end if;
    execute 'reset role';
    if (select count(*) from public.tiktok_settlement_reviews v
         where v.settlement_row_id = v_row and v.reviewed_by = v_owner and v.reason = '427 check'
           and v.decision = 'no_stock_needed') <> 1
       or (select count(*) from public.audit_logs al
            where al.record_id = v_row and al.action = 'tiktok_settlement_reviewed_no_stock'
              and al.changed_by = v_owner and al.module = 'tiktok_import') <> 1 then
      raise exception '427: the review was not recorded and audited once'; end if;
    raise exception using errcode = 'P0427', message = '427: check done, undone';
  exception when sqlstate 'P0427' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
