-- 424_exchanges_and_promotions.sql
--
-- WHAT WAS WRONG (audit of 9 Oct 2026: X-9, SALES-EXTRAS-5, -10, -11, -13,
-- -14, and the exchange part of AFFILIATES-15; production read on 9 Oct 2026)
--
--   1. Staff on two stores could not exchange at their second store (X-9).
--      All 3 active staff work at both stores, but the three exchange
--      creators still refused a member of staff whose FIRST assigned store
--      was not the processing store ("You can only process exchanges for your
--      assigned store"), at the very last step, after everything was typed.
--      The next check (user_has_store_access) already allowed every store
--      they work at.
--   2. An exchanged item always counted at today's full shelf price
--      (SALES-EXTRAS-5). A discounted or free item gave the customer its
--      discount again. Production has 6 exchanges (read on 9 Oct 2026; the
--      last at 08:06 UTC), and every one gave more credit than rule 2 gives:
--        * 3 product lines: S$218.91 more than what was paid
--          (invoice_discounted_line_value): EX-20260808-b3686f (74.91),
--          EX-20260912-82a2a4 (72.00) and EX-20260925-1053cb (72.00).
--        * 3 bundle components, each counted at its full price: S$512.22 more
--          than its share of what the bundle was paid: EXC-20260916-cce209
--          (220.33), EXC-20261009-03f0c9 (83.49) and EXC-20261009-ca5e81
--          (208.40). Both bundles also gave 10 vouchers chosen at the till,
--          about half of their value today. (Split by the products alone,
--          the excess would be S$227.68.)
--   3. The promotion builder's "Original" and "Savings" ignored choice groups
--      (SALES-EXTRAS-13): of 20 choice-group promotions, 17 showed an
--      Original below their price and 7 showed S$0. bundle_line_components
--      read the bundle as it is today, so a component exchange of a bundle
--      edited after the sale offered items that were never sold.
--   4. An exchange's instalment label was dropped (SALES-EXTRAS-14): the page
--      sent the money under its real method and nothing else, so the
--      replacement invoice never recorded the instalment's method and months,
--      unlike any other invoice. create_exchange_with_details, which the page
--      calls, did not begin with 406's staff check (the creators under it
--      refused a login with no profile, but not as 406 does).
--   5. Nothing stopped two live promotions sharing a code (SALES-EXTRAS-11):
--      the only indexes were the primary key and idx_promotions_active.
--      Production: no live duplicate (case-insensitive) on 9 Oct 2026.
--   6. Setting one price at every store also switched every store on
--      (SALES-EXTRAS-10): set_promotion_price_all_stores always passed
--      "available", so a store an Owner had switched off came back on.
--      Production: no store is switched off or priced differently today.
--   7. product_exchanges.affiliate_id still pointed at the empty legacy
--      affiliates table (AFFILIATES-15). Nothing has written it since 408
--      (exchange_affiliate_id replaced it), no row uses it, and nothing reads
--      it; it is the last link that keeps the legacy table from being removed.
--   8. An exchange typed in late still counted on the day it was typed in
--      (SALES-EXTRAS-M3). Staff could pick an earlier exchange date, and
--      set_exchange_details stored it, but create_exchange_invoice never read
--      it: the replacement invoice took today's date, its paid date (which
--      commission reads, 384) was the moment it was saved, and so were its
--      payments (which the Sales reports and the Xero export read, 292 and
--      411). The Exchange Invoices report also listed it on the day it was
--      saved. Nothing stopped a date in a month already sent to Xero.
--      Production (9 Oct 2026): 6 exchanges, none dated before the day it was
--      saved (2 have no exchange date), so no past sale moves.
--
-- THE RULES (the Owner, 9 Oct 2026: Q17 = A; exchanges are final, 408;
-- the wave-2 answers W2-B10-EXCHANGE-DATE, -BUNDLE-SHARE and -VOUCHER-BASE)
--
--   1. Staff process an exchange at any store they work at (as
--      require_store_access already says), not only their first one.
--   2. What a returned item counts for (its credit) is the lower of today's
--      price at the processing store and what the customer paid for it. A free
--      item gives no credit.
--        * What was paid for a line is its share of what the invoice charged,
--          after its discounts and FOC (invoice_discounted_line_value, the
--          figure refunds use). A line of a replacement invoice was also paid
--          by the credit the earlier exchange carried into it, so its share of
--          that credit counts as paid too.
--        * A product line is returned whole: today's price x quantity against
--          the line's paid value.
--        * A whole bundle: its value today (promotion_original_total, as
--          before) against the line's paid value.
--        * One product of a bundle: today's price x quantity against its
--          share of the line's paid value. The share is split by the value
--          today of everything the line gave: its products (the sale's own
--          record where there is one), and its vouchers, therapy, credit
--          packages and bundles chosen at the till, priced as the bundle's
--          Original prices them. (The sale recorded only its stock, so what
--          the line gave besides products is read from the bundle as it is
--          now, with the choices made at the till.) The Owner confirmed this
--          share on 9 Oct 2026 (W2-B10-BUNDLE-SHARE): split by today's value of
--          everything the bundle gave, vouchers chosen at the till included;
--          past exchanges stay as history.
--      The replacement is still valued at today's prices, and the top-up is
--      the replacement less the credit, as before.
--   3. A promotion's Original counts each choice group at its base option
--      (the cheapest, or the dearest for a products group set that way),
--      choose_qty times, priced like the fixed items. Options with no price at
--      the store are left out. As at the till (promotion_selections_topup), the
--      "dearest" setting counts for products groups only; any other group
--      counts at its cheapest option whatever it is set to.
--   4. What a bundle line holds, for an exchange, is what the sale recorded
--      (invoice_stock_components, when the invoice has stock_snapshot_version
--      1). Older sales fall back to the bundle as it is now, with the choices
--      made at the till, as before.
--   5. An instalment on an exchange's additional payment is a label on money
--      taken now, as on any invoice: the replacement invoice records its
--      method and months (in_house). Its method must be one the money was
--      taken through.
--   6. Two live promotions (not deleted) never share a code, ignoring case
--      and surrounding spaces.
--   7. A promotion price set at every store with "available" sent as null
--      keeps each store's on/off choice; a store with no price yet starts on.
--      Given true or false, it is set as before; left out, it is true as
--      before (the Prices window always gives it).
--   8. (the Owner, 9 Oct 2026, W2-B10-EXCHANGE-DATE: SALES-EXTRAS-M3 = A) An
--      exchange typed in late counts on the exchange date staff choose, in
--      the sales reports and in commission, but never before the 1st of the
--      current month in Singapore, so a month already sent to Xero is not
--      changed. It is never before the original sale either (its invoice
--      date), nor in the future (as before).
--        * The replacement invoice is dated that day: its date (business_
--          date), its paid date (commission is dated by it, 384), and its
--          payments' date (effective_at, which the Sales reports and the Xero
--          export date a receipt by, 292 and 411; a back-dated invoice payment
--          is written the same way). Part-payment commission on it is dated
--          that day too.
--        * Saved on the exchange date itself, nothing changes from before.
--        * Once the replacement invoice is made, the exchange date stays.
--        * The Exchange Invoices report lists an exchange on that day (the
--          Singapore date it was saved when it has no exchange date, as 367).
--        * The 5-day window reads the invoice's paid date, so a replacement's
--          own window runs from the exchange date: typed in k days late, it is
--          k days shorter; dated before the original sale was fully paid, it
--          can already be closed when saved.
--
-- WHAT THIS DOES
--
--   New, internal (revoked from public, anon and authenticated; the service
--   role's, 339):
--   * exchange_credit_value(item, store, product, qty): rule 2's figures for
--     one line, or one product of a bundle line: todays, paid and credit.
--   * promotion_non_product_value(promotion, store): what one bundle holds
--     besides products (vouchers, therapy, credit packages, and the same parts
--     of each bundle inside it), priced as promotion_original_total prices
--     them; for rule 2's split.
--   New, staff's (authenticated and the service role; 406's check first):
--   * exchange_credit_preview(invoice, store): what each product line, and
--     each product of each bundle line (for every quantity that can be
--     returned), would count for at this store, for the Exchanges page to show
--     before Confirm. For active staff with access to the processing store
--     and the invoice's store, as exchange_bundle_preview. Reads only.
--   Patched (exact-once anchors; CREATE OR REPLACE keeps owner and grants):
--   * create_product_exchange, create_bundle_component_exchange,
--     create_bundle_exchange (internal): rule 1 (the first-store check is
--     removed); rule 2 (the credit, and each returned row records the credit
--     it gave, not today's price; a whole bundle's rows add up to its credit,
--     the last row taking what rounding left); the audit entry keeps both
--     figures.
--   * exchange_bundle_quote (internal): rule 2 for the whole bundle, and it
--     answers todays_value and paid beside credit. Its "changed since the
--     sale" check now compares the sale's record with the bundle as it is now
--     (promotion_stock_items), because bundle_line_components now reads the
--     sale's record itself (rule 4).
--   * promotion_original_total (staff): rule 3.
--   * bundle_line_components (staff): rule 4.
--   * create_exchange_with_details (staff): 406's check as its first
--     statement; rule 5.
--   * set_promotion_prices, set_promotion_price_all_stores (Owner and
--     Manager, as before): rule 7.
--   * set_exchange_details (internal): rule 8's limits (the 1st of this
--     month, the original sale, and a date that stays once invoiced).
--   * create_exchange_invoice (internal): rule 8's dating of the replacement
--     invoice, its paid date and its payments.
--   Replaced (DROP and CREATE, its return gains a column; its grants are put
--   back exactly as they were):
--   * report_exchange_invoices (staff, rows filtered as before): rule 8's day,
--     returned as the new last column exchange_date, and the period and
--     order read it. The Reports page's Exchange Invoices tab shows that day,
--     in its table and its export, and sorts by it; without the column it
--     shows the day the exchange was saved, as before.
--   Tables:
--   * promotions: the unique index promotions_code_live_key on
--     lower(btrim(code)) where deleted_at is null (rule 6).
--   * product_exchanges: the column affiliate_id is dropped, and its foreign
--     key product_exchanges_affiliate_id_fkey with it.
--
-- NOT CHANGED
--
--   * The 6 exchanges already done keep the credit they gave (owner: leave
--     them as history; that decision now covers 6, S$731.13 in all, see
--     WHAT WAS WRONG 2). No row is changed.
--   * The dates of the 6 exchanges already done and of their invoices (each
--     was saved on its own exchange date, or has none). The original
--     invoice's date. The stock moves, the exchange's own record and the
--     replacement invoice's created_at keep the moment it was saved.
--   * How the reports and the Xero export date money (292, 367, 411): rule 8
--     only gives the replacement invoice's payments their day, as a
--     back-dated invoice payment already is. A receipt dated into a period
--     already downloaded for Xero shows in the export review's "missed" list
--     (411), as any back-dated payment does.
--   * Who may exchange, the 5-day window's rule, the exact top-up of a whole
--     bundle, the part-payment of product and component exchanges through the
--     API (the page never sends one), exchanges being final (408), how the
--     replacement is valued, and the stock moves.
--   * my_assigned_store_id() (InvoicesPage uses it as a one-store fallback).
--   * Promotion dates at the till and on invoices (B02, 415), and the
--     promotion data: the 12 promotions that ended on 1 Oct and the empty
--     "4 Vouchers x 2" in the 50BB blind box are switched by the repair script
--     scripts/promotions/repair-ended-promotions-and-blind-box.sql (Q18 = A),
--     run separately with the Owner's sign-off.
--   * public.affiliates itself (the affiliates migration after this one
--     removes the legacy tables).
--   * The choice groups' settings. Two live vouchers groups are set to the
--     dearest (in B-C-(Corset3.0)-V, choose 15, and Energia16BundleC&Vouchers,
--     choose 30; both ended on 1 Oct 2026), almost certainly by a slip in the
--     Add window. The till never read that setting for vouchers, and rule 3
--     does not either. The Owner, 9 Oct 2026 (W2-B10-VOUCHER-BASE): leave
--     them as they are (their promotions are switched off by the Q18 repair).
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. Every
--   guard and anchor is checked, and every function text built and checked
--   against its AFTER md5, before anything is installed. md5(pg_get_
--   functiondef) of each patched function must be the production version read
--   on 9 Oct 2026 (BEFORE) or already this migration's (AFTER), which is left
--   alone, so a re-run changes nothing. The functions relied on but not
--   changed must be the versions read that day. Each new function must be
--   missing or already this version; no other function takes any of these
--   names. The columns read must exist. product_exchanges.affiliate_id is
--   dropped only while no row uses it, no view or rule depends on it, no
--   function names it beside product_exchanges (comments aside) other than the
--   five known ones, none of which reads it, and its one constraint is the
--   foreign key to affiliates; the index is made only
--   while no two live promotions share a code (a list of the codes is given if
--   they do), or it is already exactly this one. report_exchange_invoices is
--   dropped and made again only when it is the BEFORE version, nothing
--   depends on it, and its new text is the tested one; its grants are put
--   back as they were. After installing: every md5
--   is the AFTER one, the patched functions keep their grants, the new
--   internal ones are the service role's alone, the preview staff's and not
--   signed out's. Then, as the server, inside a block that is always undone,
--   a made-up sale at a made-up store: a line paid S$75 for an item priced
--   S$100 counts for S$75, and for S$60 once the price is S$60; a S$50 product
--   of a bundle sold for S$100 that also gave a S$150 voucher counts for S$25;
--   a bundle with
--   a choice group of 2 (S$30 and S$50 options) on S$60 of fixed items is
--   worth S$120 with the cheapest base and S$160 with the dearest, and a
--   vouchers group set to its dearest (S$150 and S$10) adds only S$10; a bundle
--   line keeps what it sold after the bundle is edited; a price set with
--   "available" null keeps a store switched off; an exchange dated the month
--   before is refused, and one stored with that date is invoiced on the 1st
--   of this month (its date, its paid date, its payment's date and its Xero
--   receipt), or on the day it is saved when that is the 1st; anon and a
--   signed-in login with no profile cannot preview or reach the internal
--   helpers.
--   Nothing is printed and no row remains.
--
-- BEFORE (production, 9 Oct 2026; md5 of pg_get_functiondef read with
-- search_path public; the creators and the quote are 408's AFTER). Read after
-- 413 when this was built, and read again later on 9 Oct 2026 after 414, 421
-- and 428 were applied (20261009084737, 20261009104732, 20261009104830;
-- public function fingerprint 897ad364eff917861989315bb2fa0e43): every md5
-- below was still the same. Read again on 10 Oct 2026 after 415 was applied
-- (20261010010418; fingerprint 566e76f702c89c9846968e6fdd89cc45): still the
-- same, and the three new functions still missing.
--   create_product_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text,boolean,uuid,text)         74be7ea5da53738cbc81db4e69ed8362
--   create_bundle_component_exchange(uuid,uuid,uuid,uuid,integer,jsonb,jsonb,text,text)      35af27479da6083ce5297b4a86e7d8cb
--   create_bundle_exchange(uuid,uuid,uuid,uuid,jsonb,text,text)                              ef9775bc5650a8e0da377af9b9fdd18f
--   exchange_bundle_quote(uuid,uuid,uuid,uuid)                                               cf07451f61cc45b1cef2bd8e31141330
--   promotion_original_total(uuid,uuid)                                                      2480074e2b77e313b052cc225493087c
--   bundle_line_components(uuid)                                                             93ebc0e25991428c5e94a71879bbef41
--   create_exchange_with_details(text,jsonb)                                                 b804b14bd80fff3e813d801eb789e83d
--   set_promotion_prices(uuid,uuid,numeric,numeric,boolean)                                  c9eb607b3e3b5b63b035478a28a080c0
--   set_promotion_price_all_stores(uuid,numeric,boolean)                                     08bf621e2bf2459566c28e6fd515ade0
--   create_exchange_invoice(uuid)                                                            d30f8a2740154353e9f65e2bb64963fa
--   set_exchange_details(uuid,jsonb,jsonb,uuid,date,text)                                    352b1277be6e3ef60dda4cce80949aff
--   report_exchange_invoices(uuid,date,date)                                                 9b36b621a0d46fdb0d5384560e48b6d3
--   (new, missing) exchange_credit_value, exchange_credit_preview, promotion_non_product_value
--   (relied on, not changed)
--   invoice_discounted_line_value(uuid)                                                      ead4a430c3abd1e3f953912867ca4fe6
--   promotion_stock_items(uuid,integer)                                                      82dd6bdac5566fce0b75470eb45444d1
--   capture_invoice_stock_components()                                                       9f68df58f5cefced3cd68eb62a8877a7
--   exchange_bundle_preview(uuid,uuid,uuid,uuid)                                             c09fce506c8b92c321e8cf0f589691ff
--   trg_exchange_invoice()                                                                   f4a84ead2fd5fa51d2e50d70da206e38
--   validate_invoice_business_metadata()                                                     c6e4436575e1c5ec8580d2b3d9d11d50
--   require_active_staff(text[])                                                             877b3aa74cea559881979bb161c450e2
--   user_has_store_access(uuid)                                                              8c82c6bcb64f496c5a05a2b8dafa95f8
--   earn_invoice_commission(uuid)                                                            6156b2e1ee51da5146a5a7acc16091ce
--   earn_staff_commission(uuid)                                                              03e4de1a5ba3d372e6cbb4de64b2c92d
--   sync_instalment_commissions(uuid,text,date,boolean,boolean)                              88d7b122778801a0d5eea0b6dd8395b7
--   payment_sales_date(timestamp with time zone,timestamp with time zone)                    3e5161e4830f5f6fdc8f34a24266fdc9
--   invoice_sales_ledger()                                                                   6278b7ac91ebbd2ae96a7e2182a29f33
--   xero_sales_event_rows(date,date)                                                         18858e023c44d06814e617299456084b
-- AFTER (for later guards):
--   create_product_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text,boolean,uuid,text)         48679d09a214c9dcf8850be51110d8bc
--   create_bundle_component_exchange(uuid,uuid,uuid,uuid,integer,jsonb,jsonb,text,text)      8d588d7f856fca85356e293a8af3ecef
--   create_bundle_exchange(uuid,uuid,uuid,uuid,jsonb,text,text)                              c552d1734cd4e8052b113a6026d8a6b2
--   exchange_bundle_quote(uuid,uuid,uuid,uuid)                                               447b48555da3e278bf2adb4cde3c155b
--   promotion_original_total(uuid,uuid)                                                      eb869e4103102af779c13b2d5640b621
--   bundle_line_components(uuid)                                                             794ad28556de3e53d945e9ff742697a0
--   create_exchange_with_details(text,jsonb)                                                 bceb96b473d2c153c871e9547769bb29
--   set_promotion_prices(uuid,uuid,numeric,numeric,boolean)                                  5887f9956247b2efb2a881a8cde7a842
--   set_promotion_price_all_stores(uuid,numeric,boolean)                                     860718f00a97dc109d7b2914a4a2f27a
--   exchange_credit_value(uuid,uuid,uuid,integer)                                            8998ee93a6fce8ce3a82e2a8c49aa95a
--   exchange_credit_preview(uuid,uuid)                                                       263bb91b1ed38c6b53767c4d0182595c
--   promotion_non_product_value(uuid,uuid)                                                   5c38814c34dfe1424cb4e4647f906e8a
--   create_exchange_invoice(uuid)                                                            6392abd80baad4b1a2a5069654c994c1
--   set_exchange_details(uuid,jsonb,jsonb,uuid,date,text)                                    f317e42aae09809c46625f47eb884298
--   report_exchange_invoices(uuid,date,date)                                                 298d3f07deab82be159e64855c03ada4
--
-- DEPLOY ORDER: after 406-413 (it guards on 408's exchange functions); before
-- the affiliates clean-up that drops the legacy affiliates table (it needs
-- this column gone). The pages go first, then this, in the same session:
--   1. Deploy the pages (ExchangesPage, PromotionsPage, and ReportsPage for
--      the Exchange Invoices day) to Vercel.
--   2. Ask staff to reload any open Exchanges tab (an open tab keeps the old
--      page until it is reloaded).
--   3. Apply this.
-- Why: the old Exchanges page counts a returned item at today's price, and
-- this gives the lower figure. Under this, the old page's top-up is too low
-- where they differ, and the server books the gap on the replacement invoice
-- as unpaid (product and component exchanges take a smaller payment as part
-- of the top-up), a balance the customer never agreed to. The new pages
-- against a database without this are safe: they cannot price a product or
-- component exchange (the preview is missing), so they say so and refuse
-- Confirm; a whole-bundle exchange is priced by the server as before, and its
-- new figures stay hidden; a price set at every store switches every store on,
-- as today; the old server ignores the instalment label, as today; the
-- Reports page shows the day an exchange was saved, as today; and an
-- earlier exchange date still counts on the day it is saved until this is
-- applied (the page lets staff choose from the 1st of this month only). An
-- old page under this server is refused a date before the 1st of this month
-- or before the original sale, with the reason shown.
--
-- Test: scripts/exchanges/tests/credit-and-stores.sql (this migration's
-- rules) and exchange-date.sql (rule 8), with money-and-stock.sql (brought
-- to rule 2), attribution.sql, commission.sql and instalments.sql (npm run
-- test:exchanges); scripts/reports/tests/reports-367.sql (the Exchange
-- Invoices report's period);
-- scripts/promotions/tests/original-and-codes.sql and
-- choice-group-promotions.sql (npm run test:promotions); the pages:
-- scripts/exchanges/tests/exchanges-page.test.mjs, rules.test.mjs,
-- scripts/promotions/tests/promotions-page.test.mjs, status.test.mjs,
-- scripts/reports/tests/reports-page.test.mjs (the Exchange Invoices day);
-- scripts/permissions/tests/function-grants.sql and staff-only-functions.sql,
-- run after this in the same transaction.

set lock_timeout = '5s';

do $mig$
declare
  -- ── New functions, as pg_get_functiondef shows them ───────────────────────
  c_value_def constant text := $def$CREATE OR REPLACE FUNCTION public.exchange_credit_value(p_invoice_item_id uuid, p_store_id uuid, p_product_id uuid DEFAULT NULL::uuid, p_qty integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 424 (the Owner, 9 Oct 2026, Q17): what a returned item counts for in an
-- exchange: the lower of today's price at the processing store and what the
-- customer paid for it. A free item gives no credit.
--   * A product line, returned whole: today's price x quantity, against the
--     line's paid value.
--   * A bundle line, whole (no product given): the bundle's value today
--     (promotion_original_total) x quantity, against the line's paid value.
--   * One product of a bundle line (p_product_id, p_qty): today's price x
--     p_qty, against its share of the line's paid value. The share is split
--     by the value today of everything the line gave: the products it sold
--     (bundle_line_components), and its vouchers, therapy, credit packages
--     and bundles chosen at the till, priced as promotion_original_total
--     prices them (promotion_non_product_value, and the line's choices).
-- The paid value is the line's share of what the invoice charged, after its
-- discounts and FOC (invoice_discounted_line_value, as refunds use). A line
-- of a replacement invoice was also paid by the credit the earlier exchange
-- carried into it, so its share of that credit counts as paid.
-- Answers todays (null when there is no price here), paid and credit (null
-- when todays is null). Null for a line that is neither kind.
declare
  it public.invoice_items%rowtype; v_inv public.invoices%rowtype;
  v_paid numeric; v_todays numeric; v_price numeric; v_weight numeric; v_lines numeric;
begin
  select * into it from public.invoice_items where id = p_invoice_item_id;
  if not found then return null; end if;
  select * into v_inv from public.invoices where id = it.invoice_id;
  v_paid := greatest(coalesce(public.invoice_discounted_line_value(it.id), 0), 0);
  if coalesce(v_inv.is_exchange, false) and it.price_source = 'exchange'
     and coalesce(v_inv.exchange_credit_total, 0) > 0 then
    select sum(l.line_total) into v_lines from public.invoice_items l
     where l.invoice_id = v_inv.id and l.price_source = 'exchange';
    if coalesce(v_lines, 0) > 0 then
      v_paid := v_paid + v_inv.exchange_credit_total * greatest(coalesce(it.line_total, 0), 0) / v_lines;
    end if;
  end if;
  v_paid := round(v_paid, 2);

  if it.line_kind::text = 'product' and p_product_id is null then
    select selling_price into v_price from public.store_product_prices
     where store_id = p_store_id and product_id = it.product_id and is_active = true;
    v_todays := round(v_price * it.quantity, 2);
  elsif it.line_kind::text = 'promotion' and p_product_id is null then
    v_todays := round(public.promotion_original_total(it.promotion_id, p_store_id) * it.quantity, 2);
  elsif it.line_kind::text = 'promotion' then
    select selling_price into v_price from public.store_product_prices
     where store_id = p_store_id and product_id = p_product_id and is_active = true;
    v_todays := round(v_price * coalesce(p_qty, 0), 2);
    select sum(coalesce(pr.selling_price, 0) * b.quantity) into v_weight
      from public.bundle_line_components(it.id) b
      left join public.store_product_prices pr
        on pr.store_id = p_store_id and pr.product_id = b.product_id and pr.is_active = true;
    -- What else the line gave: the bundle's own vouchers, therapy and credit
    -- packages (per bundle), and what was chosen at the till that is not a
    -- product (the choices' quantities are for the whole line).
    v_weight := coalesce(v_weight, 0)
      + coalesce(public.promotion_non_product_value(it.promotion_id, p_store_id), 0) * it.quantity
      + coalesce((select sum(s.quantity * coalesce(case
            when s.voucher_id is not null then
              (select v.selling_price from public.vouchers v where v.id = s.voucher_id)
            when s.therapy_package_id is not null then
              (select tp.selling_price from public.unlimited_therapy_store_prices tp
                where tp.store_id = p_store_id and tp.package_id = s.therapy_package_id
                  and coalesce(tp.available_at_store, true) and tp.deleted_at is null)
            when s.credit_package_id is not null then
              (select cp.customer_price from public.credit_packages cp
                where cp.id = s.credit_package_id and cp.deleted_at is null)
            when s.child_promotion_id is not null then
              public.promotion_original_total(s.child_promotion_id, p_store_id)
          end, 0))
          from public.invoice_promotion_selections s
         where s.invoice_item_id = it.id and s.product_id is null), 0);
    v_paid := case when coalesce(v_weight, 0) > 0 and v_price is not null
                   then round(v_paid * v_price * coalesce(p_qty, 0) / v_weight, 2) else 0 end;
  else
    return null;
  end if;
  return jsonb_build_object('todays', v_todays, 'paid', v_paid,
    'credit', case when v_todays is null then null else least(v_todays, v_paid) end);
end $function$
$def$;

  c_npv_def constant text := $def$CREATE OR REPLACE FUNCTION public.promotion_non_product_value(p_promotion_id uuid, p_store_id uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 424: what one bundle holds besides products, at today's prices at a store:
-- its vouchers, therapy and credit packages, priced as promotion_original_total
-- prices them, and the same parts of each bundle inside it. Its products are
-- left out: they are the bundle line's products (bundle_line_components).
-- exchange_credit_value uses it to split what a bundle line was paid by the
-- value of everything the line gave. Internal.
declare v_item record; v_total numeric := 0; v_price numeric;
begin
  for v_item in select * from public.promotion_items where promotion_id = p_promotion_id
  loop
    v_price := null;
    if v_item.item_type = 'voucher' then
      select selling_price into v_price from public.vouchers where id = v_item.voucher_id;
    elsif v_item.item_type = 'promotion' then
      v_price := public.promotion_non_product_value(v_item.child_promotion_id, p_store_id);
    elsif v_item.item_type = 'therapy' then
      select selling_price into v_price from public.unlimited_therapy_store_prices
        where store_id = p_store_id and package_id = v_item.therapy_package_id
          and coalesce(available_at_store, true) and deleted_at is null;
    elsif v_item.item_type = 'credit_package' then
      select customer_price into v_price from public.credit_packages
        where id = v_item.credit_package_id and deleted_at is null;
    end if;  -- products are the line's products; treatment counts 0
    v_total := v_total + coalesce(v_price, 0) * v_item.quantity;
  end loop;
  return v_total;
end $function$
$def$;

  c_preview_def constant text := $def$CREATE OR REPLACE FUNCTION public.exchange_credit_preview(p_original_invoice_id uuid, p_processing_store_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 424: what each item of an invoice would count for in an exchange at this
-- store (exchange_credit_value), for the Exchanges page to show before
-- Confirm: today's price, what was paid, and the credit (the lower). Each
-- product line whole; each product of each bundle line for every quantity
-- that can be returned. For active staff (406's check) with access to the
-- processing store and to the invoice's store, as exchange_bundle_preview.
-- Reads only.
declare
  v_store uuid; it record; c record; q integer;
  v_lines jsonb := '[]'::jsonb; v_comps jsonb; v_opts jsonb;
begin
  perform public.require_active_staff();  -- 406: active staff only, else 42501
  if p_processing_store_id is null or not public.user_has_store_access(p_processing_store_id) then
    raise exception 'You do not have access to the processing store' using errcode = '42501'; end if;
  select store_id into v_store from public.invoices where id = p_original_invoice_id;
  if v_store is null or not public.user_has_store_access(v_store) then
    raise exception 'Invoice not accessible' using errcode = '42501'; end if;
  for it in select * from public.invoice_items
             where invoice_id = p_original_invoice_id and line_kind::text in ('product', 'promotion')
             order by id loop
    if it.line_kind::text = 'product' then
      v_lines := v_lines || jsonb_build_array(
        jsonb_build_object('invoice_item_id', it.id, 'line_kind', 'product', 'quantity', it.quantity)
        || coalesce(public.exchange_credit_value(it.id, p_processing_store_id, null, null), '{}'::jsonb));
    else
      v_comps := '[]'::jsonb;
      for c in select b.product_id, b.quantity from public.bundle_line_components(it.id) b order by b.product_id loop
        v_opts := '[]'::jsonb;
        for q in 1 .. least(c.quantity, 100)::integer loop
          v_opts := v_opts || jsonb_build_array(jsonb_build_object('quantity', q)
            || coalesce(public.exchange_credit_value(it.id, p_processing_store_id, c.product_id, q), '{}'::jsonb));
        end loop;
        v_comps := v_comps || jsonb_build_array(
          jsonb_build_object('product_id', c.product_id, 'quantity', c.quantity, 'options', v_opts));
      end loop;
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'invoice_item_id', it.id, 'line_kind', 'promotion', 'quantity', it.quantity, 'components', v_comps)
        || coalesce(public.exchange_credit_value(it.id, p_processing_store_id, null, null), '{}'::jsonb));
    end if;
  end loop;
  return jsonb_build_object('lines', v_lines);
end $function$
$def$;

  -- ── Anchors and their replacements ─────────────────────────────────────────
  -- X-9: the first-store check of the three creators.
  c_store_prod_a constant text :=
       E'  -- Staff may only process for their assigned store.\n'
    || E'  if v_role = ''staff'' and public.my_assigned_store_id() is distinct from p_processing_store_id then\n'
    || E'    raise exception ''You can only process exchanges for your assigned store'';\n'
    || E'  end if;\n';
  c_store_a constant text :=
       E'  if v_role = ''staff'' and public.my_assigned_store_id() is distinct from p_processing_store_id then\n'
    || E'    raise exception ''You can only process exchanges for your assigned store''; end if;\n';
  c_store_r constant text :=
       E'  -- 424 (X-9): staff exchange at any store they work at (the check below),\n'
    || E'  -- not only at the first store they were given.\n';

  -- create_product_exchange: the credit (rule 2) and what the returned rows record.
  c_prod_decl_a constant text :=
       E'  v_foc_amt numeric := 0; v_foc_text text;\n';
  c_prod_decl_r constant text :=
       E'  v_foc_amt numeric := 0; v_foc_text text;\n'
    || E'  v424_credit jsonb; v424_todays numeric := 0; v424_paid numeric := 0;  -- 424: the credit rule''s figures\n';
  c_prod_credit_a constant text :=
       E'    -- Credit = current processing-store price * qty.\n'
    || E'    select selling_price into v_price from public.store_product_prices\n'
    || E'      where store_id = p_processing_store_id and product_id = v_item.product_id and is_active = true;\n'
    || E'    if v_price is null then raise exception ''Returned product has no active price at the processing store''; end if;\n'
    || E'    v_credit := v_credit + v_price * v_item.quantity;\n';
  c_prod_credit_r constant text :=
       E'    -- 424 (the Owner, Q17): credit = the lower of today''s price at the\n'
    || E'    -- processing store and what the customer paid for the line; a free item\n'
    || E'    -- gives none (exchange_credit_value).\n'
    || E'    select selling_price into v_price from public.store_product_prices\n'
    || E'      where store_id = p_processing_store_id and product_id = v_item.product_id and is_active = true;\n'
    || E'    if v_price is null then raise exception ''Returned product has no active price at the processing store''; end if;\n'
    || E'    v424_credit := public.exchange_credit_value(v_item.id, p_processing_store_id, null, null);\n'
    || E'    v_credit := v_credit + (v424_credit->>''credit'')::numeric;\n'
    || E'    v424_todays := v424_todays + (v424_credit->>''todays'')::numeric;\n'
    || E'    v424_paid := v424_paid + (v424_credit->>''paid'')::numeric;\n';
  c_prod_row_a constant text :=
       E'    insert into public.product_exchange_items (exchange_id, direction, original_invoice_item_id, product_id, quantity, unit_price, line_total)\n'
    || E'    values (v_ex_id, ''returned'', v_item.id, v_item.product_id, v_item.quantity, v_price, v_price * v_item.quantity);\n';
  c_prod_row_r constant text :=
       E'    -- 424: the returned row records the credit it gave, not today''s price.\n'
    || E'    v424_credit := public.exchange_credit_value(v_item.id, p_processing_store_id, null, null);\n'
    || E'    insert into public.product_exchange_items (exchange_id, direction, original_invoice_item_id, product_id, quantity, unit_price, line_total)\n'
    || E'    values (v_ex_id, ''returned'', v_item.id, v_item.product_id, v_item.quantity,\n'
    || E'            round((v424_credit->>''credit'')::numeric / v_item.quantity, 2), (v424_credit->>''credit'')::numeric);\n';
  c_prod_audit_a constant text :=
       E'    jsonb_build_object(''exchange_no'', v_no, ''credit'', v_credit, ''replacement'', v_repl, ''topup'', v_topup, ''nonrefundable'', v_nonref, ''foc_amount'', v_foc_amt),\n';
  c_prod_audit_r constant text :=
       E'    jsonb_build_object(''exchange_no'', v_no, ''credit'', v_credit, ''replacement'', v_repl, ''topup'', v_topup, ''nonrefundable'', v_nonref, ''foc_amount'', v_foc_amt,\n'
    || E'                       -- 424: the two figures behind the credit\n'
    || E'                       ''credit_todays_price'', v424_todays, ''credit_paid'', v424_paid),\n';

  -- create_bundle_component_exchange: the credit (rule 2).
  c_comp_decl_a constant text :=
       E'  v_comp_type product_type; v_repl_type product_type; v_have bigint; v_done jsonb; v_already boolean;\n';
  c_comp_decl_r constant text :=
       E'  v_comp_type product_type; v_repl_type product_type; v_have bigint; v_done jsonb; v_already boolean;\n'
    || E'  v424_credit jsonb;  -- 424: the credit rule''s figures\n';
  c_comp_credit_a constant text :=
       E'  -- Credit = component current store price * qty.\n'
    || E'  select selling_price into v_price from public.store_product_prices where store_id = p_processing_store_id and product_id = p_component_product_id and is_active = true;\n'
    || E'  if v_price is null then raise exception ''Component has no active price at the processing store''; end if;\n'
    || E'  v_credit := v_price * p_component_qty;\n';
  c_comp_credit_r constant text :=
       E'  -- 424 (the Owner, Q17): credit = the lower of the component''s price today\n'
    || E'  -- and its share of what the customer paid for the bundle line\n'
    || E'  -- (exchange_credit_value). The returned row below records it.\n'
    || E'  select selling_price into v_price from public.store_product_prices where store_id = p_processing_store_id and product_id = p_component_product_id and is_active = true;\n'
    || E'  if v_price is null then raise exception ''Component has no active price at the processing store''; end if;\n'
    || E'  v424_credit := public.exchange_credit_value(p_original_invoice_item_id, p_processing_store_id,\n'
    || E'    p_component_product_id, p_component_qty);\n'
    || E'  v_credit := (v424_credit->>''credit'')::numeric;\n';
  c_comp_audit_a constant text :=
       E'    jsonb_build_object(''exchange_no'', v_no, ''component'', p_component_product_id, ''credit'', v_credit, ''replacement'', v_repl, ''topup'', v_topup),\n';
  c_comp_audit_r constant text :=
       E'    jsonb_build_object(''exchange_no'', v_no, ''component'', p_component_product_id, ''credit'', v_credit, ''replacement'', v_repl, ''topup'', v_topup,\n'
    || E'                       -- 424: the two figures behind the credit\n'
    || E'                       ''credit_todays_price'', (v424_credit->>''todays'')::numeric, ''credit_paid'', (v424_credit->>''paid'')::numeric),\n';

  -- create_bundle_exchange: the quote's credit (rule 2), and the returned rows.
  c_bund_decl_a constant text :=
       E'  v408_quote jsonb;  -- 408: what the swap credits and charges, or why it cannot be done\n';
  c_bund_decl_r constant text :=
       E'  v408_quote jsonb;  -- 408: what the swap credits and charges, or why it cannot be done\n'
    || E'  v424_ratio numeric;  -- 424: the credit over the bundle''s value today, for the returned rows\n'
    || E'  v424_rows integer := 0; v424_n integer := 0; v424_line numeric; v424_given numeric := 0;  -- 424: the rows add up to the credit\n';
  c_bund_credit_a constant text :=
       E'  -- Credit = current regular total of bundle A; replacement = bundle B.\n'
    || E'  v_credit := public.promotion_original_total(v_item.promotion_id, p_processing_store_id);\n'
    || E'  v_repl := public.promotion_original_total(p_new_promotion_id, p_processing_store_id);\n';
  c_bund_credit_r constant text :=
       E'  -- 424 (the Owner, Q17): the quote''s figures. Credit = the lower of bundle\n'
    || E'  -- A''s value today and what the customer paid for the line; replacement =\n'
    || E'  -- bundle B''s value today.\n'
    || E'  v_credit := (v408_quote->>''credit'')::numeric;\n'
    || E'  v_repl := (v408_quote->>''replacement'')::numeric;\n'
    || E'  v424_ratio := case when coalesce((v408_quote->>''todays_value'')::numeric, 0) > 0\n'
    || E'                     then v_credit / (v408_quote->>''todays_value'')::numeric else 0 end;\n'
    || E'  v424_rows := (select count(*) from public.bundle_line_components(p_original_invoice_item_id));\n';
  c_bund_row_a constant text :=
       E'    insert into public.product_exchange_items (exchange_id, direction, original_invoice_item_id, product_id, quantity, unit_price, line_total)\n'
    || E'    values (v_ex_id, ''returned'', p_original_invoice_item_id, v_comp.product_id, v_comp.quantity, coalesce(v_price,0), coalesce(v_price,0)*v_comp.quantity);\n';
  c_bund_row_r constant text :=
       E'    -- 424: each returned item records its part of the credit, not today''s\n'
    || E'    -- price, rounded to the cent. The last one takes what is left, so the\n'
    || E'    -- rows add up to the credit.\n'
    || E'    v424_n := v424_n + 1;\n'
    || E'    v424_line := case when v424_n = v424_rows then greatest(v_credit - v424_given, 0)\n'
    || E'                      else round(coalesce(v_price,0) * v_comp.quantity * v424_ratio, 2) end;\n'
    || E'    v424_given := v424_given + v424_line;\n'
    || E'    insert into public.product_exchange_items (exchange_id, direction, original_invoice_item_id, product_id, quantity, unit_price, line_total)\n'
    || E'    values (v_ex_id, ''returned'', p_original_invoice_item_id, v_comp.product_id, v_comp.quantity,\n'
    || E'            round(v424_line / v_comp.quantity, 2), v424_line);\n';
  c_bund_audit_a constant text :=
       E'    jsonb_build_object(''exchange_no'', v_no, ''credit'', v_credit, ''replacement'', v_repl, ''topup'', v_topup, ''nonrefundable'', v_nonref),\n';
  c_bund_audit_r constant text :=
       E'    jsonb_build_object(''exchange_no'', v_no, ''credit'', v_credit, ''replacement'', v_repl, ''topup'', v_topup, ''nonrefundable'', v_nonref,\n'
    || E'                       -- 424: the two figures behind the credit\n'
    || E'                       ''credit_todays_price'', (v408_quote->>''todays_value'')::numeric, ''credit_paid'', (v408_quote->>''paid'')::numeric),\n';

  -- exchange_bundle_quote: rule 2 for the whole bundle; the sale's record is
  -- compared with the bundle as it is now (rule 4 makes bundle_line_components
  -- the sale's record itself).
  c_quote_decl_a constant text :=
       E'  v_topup numeric; v_have integer; r record;\n';
  c_quote_decl_r constant text :=
       E'  v_topup numeric; v_have integer; r record;\n'
    || E'  v424_value jsonb;  -- 424: what the returned bundle counts for (exchange_credit_value)\n';
  c_quote_snap_a constant text :=
       E'    (select c.kind, c.item_id, sum(c.quantity)::bigint\n'
    || E'       from public.invoice_stock_components c where c.invoice_item_id = it.id group by c.kind, c.item_id\n'
    || E'     except\n'
    || E'     select ''product''::text, b.product_id, b.quantity::bigint from public.bundle_line_components(it.id) b)\n'
    || E'    union all\n'
    || E'    (select ''product''::text, b.product_id, b.quantity::bigint from public.bundle_line_components(it.id) b\n'
    || E'     except\n'
    || E'     select c.kind, c.item_id, sum(c.quantity)::bigint\n'
    || E'       from public.invoice_stock_components c where c.invoice_item_id = it.id group by c.kind, c.item_id)) then\n';
  c_quote_snap_r constant text :=
       E'    -- 424: bundle_line_components now reads the sale''s record itself, so the\n'
    || E'    -- record is compared with the bundle as it is now (promotion_stock_items).\n'
    || E'    (select c.kind, c.item_id, sum(c.quantity)::bigint\n'
    || E'       from public.invoice_stock_components c where c.invoice_item_id = it.id group by c.kind, c.item_id\n'
    || E'     except\n'
    || E'     select s.kind, s.item_id, sum(s.quantity)::bigint\n'
    || E'       from public.promotion_stock_items(it.promotion_id, it.quantity) s group by s.kind, s.item_id)\n'
    || E'    union all\n'
    || E'    (select s.kind, s.item_id, sum(s.quantity)::bigint\n'
    || E'       from public.promotion_stock_items(it.promotion_id, it.quantity) s group by s.kind, s.item_id\n'
    || E'     except\n'
    || E'     select c.kind, c.item_id, sum(c.quantity)::bigint\n'
    || E'       from public.invoice_stock_components c where c.invoice_item_id = it.id group by c.kind, c.item_id)) then\n';
  c_quote_credit_a constant text :=
       E'  if v_credit is null or v_repl is null then\n'
    || E'    return jsonb_build_object(''problem'', ''Bundle price unavailable at the processing store''); end if;\n';
  c_quote_credit_r constant text :=
       E'  if v_credit is null or v_repl is null then\n'
    || E'    return jsonb_build_object(''problem'', ''Bundle price unavailable at the processing store''); end if;\n'
    || E'  -- 424 (the Owner, Q17): the returned bundle counts for the lower of its\n'
    || E'  -- value today and what the customer paid for the line.\n'
    || E'  v424_value := public.exchange_credit_value(it.id, p_processing_store_id, null, null);\n'
    || E'  v_credit := (v424_value->>''credit'')::numeric;\n';
  c_quote_ret_a constant text :=
       E'    ''credit'', v_credit,\n';
  c_quote_ret_r constant text :=
       E'    ''credit'', v_credit,\n'
    || E'    -- 424: the two figures behind the credit\n'
    || E'    ''todays_value'', (v424_value->>''todays'')::numeric,\n'
    || E'    ''paid'', (v424_value->>''paid'')::numeric,\n';

  -- promotion_original_total: each choice group at its base option (rule 3).
  c_orig_decl_a constant text :=
       E'declare v_item record; v_total numeric := 0; v_price numeric;\n';
  c_orig_decl_r constant text :=
       E'declare v_item record; v_total numeric := 0; v_price numeric; v_grp record;\n';
  c_orig_ret_a constant text :=
       E'  return v_total;\n';
  c_orig_ret_r constant text :=
       E'  -- 424: each choice group counts at its base option (the cheapest, or the\n'
    || E'  -- dearest for a products group set that way: the till''s top-up reads the\n'
    || E'  -- setting for products only), choose_qty times, priced like the fixed\n'
    || E'  -- items. Options with no price here are left out.\n'
    || E'  for v_grp in select * from public.promotion_choice_groups where promotion_id = p_promotion_id\n'
    || E'  loop\n'
    || E'    select case when v_grp.item_kind = ''product'' and coalesce(v_grp.base_mode, ''cheapest'') = ''highest''\n'
    || E'                then max(x.price) else min(x.price) end\n'
    || E'      into v_price\n'
    || E'      from (select case\n'
    || E'              when o.product_id is not null then\n'
    || E'                (select sp.selling_price from public.store_product_prices sp\n'
    || E'                  where sp.store_id = p_store_id and sp.product_id = o.product_id\n'
    || E'                    and sp.is_active = true and sp.deleted_at is null)\n'
    || E'              when o.voucher_id is not null then\n'
    || E'                (select v.selling_price from public.vouchers v where v.id = o.voucher_id)\n'
    || E'              when o.therapy_package_id is not null then\n'
    || E'                (select tp.selling_price from public.unlimited_therapy_store_prices tp\n'
    || E'                  where tp.store_id = p_store_id and tp.package_id = o.therapy_package_id\n'
    || E'                    and coalesce(tp.available_at_store, true) and tp.deleted_at is null)\n'
    || E'              when o.credit_package_id is not null then\n'
    || E'                (select cp.customer_price from public.credit_packages cp\n'
    || E'                  where cp.id = o.credit_package_id and cp.deleted_at is null)\n'
    || E'              when o.child_promotion_id is not null then\n'
    || E'                public.promotion_original_total(o.child_promotion_id, p_store_id)\n'
    || E'            end as price\n'
    || E'            from public.promotion_choice_options o where o.group_id = v_grp.id) x\n'
    || E'     where x.price is not null;\n'
    || E'    v_total := v_total + coalesce(v_price, 0) * coalesce(v_grp.choose_qty, 0);\n'
    || E'  end loop;\n'
    || E'  return v_total;\n';

  -- bundle_line_components: the sale's own record where there is one (rule 4).
  c_blc_with_a constant text :=
       E'  with fixed as (\n';
  c_blc_with_r constant text :=
       E'  -- 424: a sale with the stock record (stock_snapshot_version 1) is read from\n'
    || E'  -- what it recorded selling, so a bundle edited after the sale still shows\n'
    || E'  -- what was sold. Older sales fall back to the bundle as it is now, with the\n'
    || E'  -- choices made at the till.\n'
    || E'  with recorded as (\n'
    || E'    select exists (select 1 from public.invoice_items ii join public.invoices i on i.id = ii.invoice_id\n'
    || E'                    where ii.id = p_invoice_item_id and i.stock_snapshot_version = 1) as yes\n'
    || E'  ),\n'
    || E'  sold as (\n'
    || E'    select c.item_id as product_id, c.quantity::bigint as quantity\n'
    || E'    from public.invoice_stock_components c\n'
    || E'    join public.invoice_items ii on ii.id = c.invoice_item_id\n'
    || E'    where c.invoice_item_id = p_invoice_item_id and ii.line_kind = ''promotion'' and c.kind = ''product''\n'
    || E'      and (select yes from recorded)\n'
    || E'  ),\n'
    || E'  fixed as (\n';
  c_blc_fixed_a constant text :=
       E'    where ii.id = p_invoice_item_id and ii.line_kind = ''promotion'' and s.kind = ''product''\n';
  c_blc_fixed_r constant text :=
       E'    where ii.id = p_invoice_item_id and ii.line_kind = ''promotion'' and s.kind = ''product''\n'
    || E'      and not (select yes from recorded)\n';
  c_blc_chosen_a constant text :=
       E'    where ips.invoice_item_id = p_invoice_item_id and ips.product_id is not null\n';
  c_blc_chosen_r constant text :=
       E'    where ips.invoice_item_id = p_invoice_item_id and ips.product_id is not null\n'
    || E'      and not (select yes from recorded)\n';
  c_blc_union_a constant text :=
       E'(select * from fixed union all select * from chosen) u\n';
  c_blc_union_r constant text :=
       E'(select * from sold union all select * from fixed union all select * from chosen) u\n';

  -- create_exchange_with_details: 406's check first; the instalment label (rule 5).
  c_det_begin_a constant text :=
       E'declare v_res jsonb; v_id uuid; v_inv uuid; v_arr jsonb; v_settle jsonb;\n'
    || E'begin\n';
  c_det_begin_r constant text :=
       E'declare v_res jsonb; v_id uuid; v_inv uuid; v_arr jsonb; v_settle jsonb;\n'
    || E' v424_inst jsonb; v424_method uuid; v424_months numeric;  -- 424: the instalment label\n'
    || E'begin\n'
    || E' perform public.require_active_staff();  -- 424 (406''s check): active staff only, else 42501\n';
  c_det_inst_a constant text :=
       E' v_arr:=coalesce(p_payload->''arrangements'',''[]''::jsonb);\n';
  c_det_inst_r constant text :=
       E' -- 424: an instalment on the additional payment is a label on money taken\n'
    || E' -- now, as on any invoice: the replacement invoice records its method and\n'
    || E' -- months. Its method must be one the money was taken through.\n'
    || E' v424_inst:=p_payload->''instalment'';\n'
    || E' if v424_inst is not null and jsonb_typeof(v424_inst)<>''null'' then\n'
    || E'  if jsonb_typeof(v424_inst)<>''object'' then\n'
    || E'   raise exception ''The instalment must say its payment method and months''; end if;\n'
    || E'  v424_method:=nullif(v424_inst->>''method_id'','''')::uuid;\n'
    || E'  v424_months:=nullif(v424_inst->>''months'','''')::numeric;\n'
    || E'  if v424_method is null or v424_months is null or v424_months<=0 or v424_months<>trunc(v424_months) then\n'
    || E'   raise exception ''An instalment needs its payment method and a positive whole number of months''; end if;\n'
    || E'  if not exists(select 1 from jsonb_array_elements(coalesce(p_payload->''payments'',''[]''::jsonb)) x\n'
    || E'                 where nullif(x->>''payment_method_id'','''')::uuid=v424_method\n'
    || E'                   and coalesce(nullif(x->>''amount'','''')::numeric,0)>0) then\n'
    || E'   raise exception ''The instalment''''s payment method must be one the money was taken through''; end if;\n'
    || E'  set constraints public.exchange_creates_invoice immediate;\n'
    || E'  select id into v_inv from public.invoices where exchange_id=v_id and is_exchange;\n'
    || E'  if v_inv is null then\n'
    || E'   raise exception ''This exchange has no replacement invoice, so its instalment cannot be recorded''; end if;\n'
    || E'  update public.invoices\n'
    || E'     set instalment_category=''in_house'',instalment_method_id=v424_method,instalment_months=v424_months::integer\n'
    || E'   where id=v_inv;\n'
    || E'  v_res:=v_res||jsonb_build_object(''exchange_invoice_id'',v_inv,\n'
    || E'    ''instalment'',jsonb_build_object(''method_id'',v424_method,''months'',v424_months::integer));\n'
    || E' end if;\n'
    || E'\n'
    || E' v_arr:=coalesce(p_payload->''arrangements'',''[]''::jsonb);\n';

  -- set_promotion_prices and set_promotion_price_all_stores: rule 7.
  c_price_set_a constant text :=
       E'    set selling_price = excluded.selling_price, available_at_store = excluded.available_at_store,\n';
  c_price_set_r constant text :=
       E'    -- 424: with null given for "available", the store keeps its on/off choice.\n'
    || E'    set selling_price = excluded.selling_price,\n'
    || E'        available_at_store = coalesce(p_available, promotion_store_prices.available_at_store),\n';
  c_all_call_a constant text :=
       E'    perform public.set_promotion_prices(p_promotion_id, v_s.id, p_price, p_price, coalesce(p_available,true));\n';
  c_all_call_r constant text :=
       E'    -- 424: "available" is passed as given; with null given, each store keeps its\n'
    || E'    -- on/off choice and a store with no price yet starts on.\n'
    || E'    perform public.set_promotion_prices(p_promotion_id, v_s.id, p_price, p_price, p_available);\n';

  -- set_exchange_details: the days an exchange may be dated (rule 8).
  c_det_decl_a constant text :=
       E' v_mode text; v_aff uuid; v_aff_customer uuid; v_explicit boolean:=false; v_raised uuid; v_date date; v_n int:=0;\n';
  c_det_decl_r constant text :=
       E' v_mode text; v_aff uuid; v_aff_customer uuid; v_explicit boolean:=false; v_raised uuid; v_date date; v_n int:=0;\n'
    || E' v424_first date; v424_sale date; v424_inv_day date;  -- 424: the days an exchange may be dated\n';
  c_det_when_a constant text :=
       E' if v_date>public.sg_today() then\n'
    || E'  raise exception ''An exchange cannot be dated in the future''; end if;\n';
  c_det_when_r constant text :=
       E' if v_date>public.sg_today() then\n'
    || E'  raise exception ''An exchange cannot be dated in the future''; end if;\n'
    || E' -- 424 (the Owner, 9 Oct 2026): the replacement sale counts on this date in\n'
    || E' -- the sales reports and commission (create_exchange_invoice). So it is never\n'
    || E' -- before the 1st of this month in Singapore (a month already sent to Xero is\n'
    || E' -- not changed), nor before the original sale.\n'
    || E' v424_first:=date_trunc(''month'',public.sg_today()::timestamp)::date;\n'
    || E' if v_date<v424_first then\n'
    || E'  raise exception ''An exchange can be dated from the 1st of this month (%) at the earliest. An earlier month may already be in Xero.'',\n'
    || E'   to_char(v424_first,''FMDD Mon YYYY''); end if;\n'
    || E' select coalesce(i.business_date,(i.created_at at time zone ''Asia/Singapore'')::date) into v424_sale\n'
    || E'   from public.invoices i where i.id=e.original_invoice_id;\n'
    || E' if v_date<v424_sale then\n'
    || E'  raise exception ''An exchange cannot be dated before the original sale (%).'',to_char(v424_sale,''FMDD Mon YYYY''); end if;\n'
    || E' -- The replacement invoice is dated by it, so once that invoice is made the\n'
    || E' -- date stays.\n'
    || E' if e.exchange_invoice_id is not null then\n'
    || E'  select business_date into v424_inv_day from public.invoices where id=e.exchange_invoice_id;\n'
    || E'  if v_date is distinct from v424_inv_day then\n'
    || E'   raise exception ''This exchange''''s replacement invoice is already made, so its date cannot change.''; end if;\n'
    || E' end if;\n';

  -- create_exchange_invoice: the replacement invoice is dated the exchange date (rule 8).
  c_cei_decl_a constant text :=
       E'  v_creator_role user_role;\n';
  c_cei_decl_r constant text :=
       E'  v_creator_role user_role;\n'
    || E'  v424_day date; v424_at timestamptz;  -- 424: the day the replacement sale counts on\n';
  c_cei_day_a constant text :=
       E'  v_no := public.next_exchange_invoice_no(v_ex.processing_store_id);\n';
  c_cei_day_r constant text :=
       E'  v_no := public.next_exchange_invoice_no(v_ex.processing_store_id);\n'
    || E'\n'
    || E'  -- 424 (the Owner, 9 Oct 2026): the replacement sale counts on the exchange\n'
    || E'  -- date staff chose (set_exchange_details), never before the 1st of this\n'
    || E'  -- month in Singapore, so a month already sent to Xero is not changed. On\n'
    || E'  -- any day other than the one it is saved, the invoice''s date, its paid date\n'
    || E'  -- (commission) and its payments'' date (the Sales reports and the Xero\n'
    || E'  -- export) are that day, at its start, as a back-dated invoice payment is\n'
    || E'  -- written. Saved on that day, nothing changes.\n'
    || E'  v424_day := greatest(coalesce(v_ex.exchange_date, (v_ex.created_at at time zone ''Asia/Singapore'')::date),\n'
    || E'                       date_trunc(''month'', public.sg_today()::timestamp)::date);\n'
    || E'  if v424_day <> (v_ex.created_at at time zone ''Asia/Singapore'')::date then\n'
    || E'    v424_at := v424_day::timestamp at time zone ''Asia/Singapore'';\n'
    || E'  end if;\n';
  c_cei_cols_a constant text :=
       E'     paid_at, locked_at, created_at)\n';
  c_cei_cols_r constant text :=
       E'     paid_at, locked_at, created_at, business_date)\n';
  c_cei_vals_a constant text :=
       E'          then v_ex.created_at end, now(), v_ex.created_at)\n';
  c_cei_vals_r constant text :=
       E'          then coalesce(v424_at, v_ex.created_at) end, now(), v_ex.created_at,\n'
    || E'     v424_day)  -- 424: the exchange''s day\n';
  c_cei_pay_a constant text :=
       E'    (invoice_id, payment_method_id, amount, payment_reference, received_by, created_at, locked_at)\n'
    || E'  select v_inv_id, payment_method_id, amount, reference, v_ex.created_by, created_at, now()\n';
  c_cei_pay_r constant text :=
       E'    (invoice_id, payment_method_id, amount, payment_reference, received_by, created_at, locked_at, effective_at)\n'
    || E'  select v_inv_id, payment_method_id, amount, reference, v_ex.created_by, created_at, now(),\n'
    || E'         v424_at  -- 424: the exchange''s day, when it is not the day it was saved\n';
  c_cei_sync_a constant text :=
       E'  perform public.sync_instalment_commissions(v_inv_id, ''Exchange top-up received'');\n';
  c_cei_sync_r constant text :=
       E'  perform public.sync_instalment_commissions(v_inv_id, ''Exchange top-up received'', v424_day);  -- 424: on the exchange''s day\n';
  c_cei_audit_a constant text :=
       E'                       ''net_topup'', coalesce(v_ex.topup_amount,0)),\n';
  c_cei_audit_r constant text :=
       E'                       ''net_topup'', coalesce(v_ex.topup_amount,0),\n'
    || E'                       ''business_date'', v424_day),  -- 424: the day it counts on\n';

  -- report_exchange_invoices: an exchange is listed on its day (rule 8).
  c_rei_ret_a constant text :=
       E' foc_amount numeric)\n';
  c_rei_ret_r constant text :=
       E' foc_amount numeric, exchange_date date)\n';
  c_rei_sel_a constant text :=
       E'         e.nonrefundable_amount, coalesce(e.is_foc,false), coalesce(e.foc_amount,0)\n';
  c_rei_sel_r constant text :=
       E'         e.nonrefundable_amount, coalesce(e.is_foc,false), coalesce(e.foc_amount,0),\n'
    || E'         -- 424: the exchange''s day: the exchange date staff chose, else the\n'
    || E'         -- Singapore date it was saved. Its replacement sale counts on it.\n'
    || E'         coalesce(e.exchange_date, (e.created_at at time zone ''Asia/Singapore'')::date)\n';
  c_rei_where_a constant text :=
       E'     -- 367: the Singapore date of the exchange.\n'
    || E'     and (p_from is null or (e.created_at at time zone ''Asia/Singapore'')::date >= p_from)\n'
    || E'     and (p_to is null or (e.created_at at time zone ''Asia/Singapore'')::date <= p_to)\n';
  c_rei_where_r constant text :=
       E'     -- 424: the exchange''s day (367: the Singapore date it was saved, when it\n'
    || E'     -- has no exchange date).\n'
    || E'     and (p_from is null or coalesce(e.exchange_date, (e.created_at at time zone ''Asia/Singapore'')::date) >= p_from)\n'
    || E'     and (p_to is null or coalesce(e.exchange_date, (e.created_at at time zone ''Asia/Singapore'')::date) <= p_to)\n';
  c_rei_order_a constant text :=
       E'   order by e.created_at desc\n';
  c_rei_order_r constant text :=
       E'   order by coalesce(e.exchange_date, (e.created_at at time zone ''Asia/Singapore'')::date) desc, e.created_at desc\n';

  -- ── Signatures, BEFORE and AFTER md5s ──────────────────────────────────────
  c_fns constant text[] := array[
    'create_product_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text,boolean,uuid,text)',
    'create_bundle_component_exchange(uuid,uuid,uuid,uuid,integer,jsonb,jsonb,text,text)',
    'create_bundle_exchange(uuid,uuid,uuid,uuid,jsonb,text,text)',
    'exchange_bundle_quote(uuid,uuid,uuid,uuid)',
    'promotion_original_total(uuid,uuid)',
    'bundle_line_components(uuid)',
    'create_exchange_with_details(text,jsonb)',
    'set_promotion_prices(uuid,uuid,numeric,numeric,boolean)',
    'set_promotion_price_all_stores(uuid,numeric,boolean)',
    'exchange_credit_value(uuid,uuid,uuid,integer)',
    'exchange_credit_preview(uuid,uuid)',
    'promotion_non_product_value(uuid,uuid)',
    'create_exchange_invoice(uuid)',
    'set_exchange_details(uuid,jsonb,jsonb,uuid,date,text)',
    'report_exchange_invoices(uuid,date,date)'];
  c_after constant text[] := array[
    '48679d09a214c9dcf8850be51110d8bc', '8d588d7f856fca85356e293a8af3ecef', 'c552d1734cd4e8052b113a6026d8a6b2', '447b48555da3e278bf2adb4cde3c155b', 'eb869e4103102af779c13b2d5640b621',
    '794ad28556de3e53d945e9ff742697a0', 'bceb96b473d2c153c871e9547769bb29', '5887f9956247b2efb2a881a8cde7a842', '860718f00a97dc109d7b2914a4a2f27a', '8998ee93a6fce8ce3a82e2a8c49aa95a', '263bb91b1ed38c6b53767c4d0182595c',
    '5c38814c34dfe1424cb4e4647f906e8a', '6392abd80baad4b1a2a5069654c994c1', 'f317e42aae09809c46625f47eb884298', '298d3f07deab82be159e64855c03ada4'];
  c_names constant text[] := array[
    'create_product_exchange', 'create_bundle_component_exchange', 'create_bundle_exchange',
    'exchange_bundle_quote', 'promotion_original_total', 'bundle_line_components',
    'create_exchange_with_details', 'set_promotion_prices', 'set_promotion_price_all_stores',
    'exchange_credit_value', 'exchange_credit_preview', 'promotion_non_product_value',
    'create_exchange_invoice', 'set_exchange_details', 'report_exchange_invoices'];
  -- Callable by no client role (the internal ones); every other one is staff's.
  c_internal constant text[] := array[
    'create_product_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text,boolean,uuid,text)',
    'create_bundle_component_exchange(uuid,uuid,uuid,uuid,integer,jsonb,jsonb,text,text)',
    'create_bundle_exchange(uuid,uuid,uuid,uuid,jsonb,text,text)',
    'exchange_bundle_quote(uuid,uuid,uuid,uuid)', 'exchange_credit_value(uuid,uuid,uuid,integer)',
    'promotion_non_product_value(uuid,uuid)', 'create_exchange_invoice(uuid)',
    'set_exchange_details(uuid,jsonb,jsonb,uuid,date,text)'];
  -- Patched in place (CREATE OR REPLACE keeps their grants); report_exchange_invoices
  -- (15) is dropped and made again, and its grants are put back.
  c_in_place constant int[] := array[1, 2, 3, 4, 5, 6, 7, 8, 9, 13, 14];
  c_index_def constant text :=
    'CREATE UNIQUE INDEX promotions_code_live_key ON public.promotions USING btree (lower(btrim(code))) WHERE (deleted_at IS NULL)';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  r record; d text; v text; n int; k int; i int; v_bad text; v_mismatch text;
  v_defs text[] := '{}';
  v_acl text[]; v_drop_column boolean; v_make_index boolean;
  v_rei_acl text[];  -- report_exchange_invoices' grants, as grantee=privilege
  -- the self-test's made-up records
  v_owner uuid; v_st uuid; v_pa uuid; v_pb uuid; v_pc uuid; v_cust uuid; v_inv uuid; v_li uuid; v_li2 uuid;
  v_pr uuid; v_g uuid; v_val jsonb; v_num numeric; v_who text;
  v_vo uuid; v_pr2 uuid; v_inv2 uuid; v_li3 uuid; v_vo2 uuid; v_g2 uuid;
  v_pm uuid; v_ex uuid; v_inv3 uuid; v_first date;
begin
  -- pg_get_functiondef names a parameter's type as the search path shows it,
  -- so the definitions are read and compared with public alone, as they were
  -- read on 9 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── What the functions read ────────────────────────────────────────────────
  for r in select * from (values
    ('invoice_items', 'price_source'), ('invoice_items', 'line_total'), ('invoice_items', 'line_kind'),
    ('invoice_items', 'promotion_id'), ('invoices', 'is_exchange'), ('invoices', 'exchange_credit_total'),
    ('invoices', 'stock_snapshot_version'), ('invoices', 'instalment_category'),
    ('invoices', 'instalment_method_id'), ('invoices', 'instalment_months'),
    ('invoice_stock_components', 'invoice_item_id'), ('invoice_stock_components', 'kind'),
    ('invoice_stock_components', 'item_id'), ('invoice_stock_components', 'quantity'),
    ('promotion_choice_groups', 'base_mode'), ('promotion_choice_groups', 'choose_qty'),
    ('promotion_choice_groups', 'item_kind'),
    ('promotion_choice_options', 'product_id'), ('promotion_choice_options', 'voucher_id'),
    ('promotion_choice_options', 'therapy_package_id'), ('promotion_choice_options', 'credit_package_id'),
    ('promotion_choice_options', 'child_promotion_id'), ('unlimited_therapy_store_prices', 'available_at_store'),
    ('credit_packages', 'customer_price'), ('vouchers', 'selling_price'),
    ('store_product_prices', 'deleted_at'), ('promotion_store_prices', 'available_at_store'),
    ('promotions', 'code'), ('promotions', 'deleted_at'),
    ('promotion_items', 'item_type'), ('promotion_items', 'voucher_id'), ('promotion_items', 'child_promotion_id'),
    ('promotion_items', 'therapy_package_id'), ('promotion_items', 'credit_package_id'),
    ('invoice_promotion_selections', 'invoice_item_id'), ('invoice_promotion_selections', 'product_id'),
    ('invoice_promotion_selections', 'voucher_id'), ('invoice_promotion_selections', 'therapy_package_id'),
    ('invoice_promotion_selections', 'credit_package_id'), ('invoice_promotion_selections', 'child_promotion_id'),
    ('invoice_promotion_selections', 'quantity')) x(t, c)
  loop
    if not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = r.t and column_name = r.c) then
      raise exception '424: public.%.% is missing', r.t, r.c; end if;
  end loop;

  -- ── Guards, anchors and texts: nothing is installed unless all pass ───────
  for r in select * from (values
    (1, '74be7ea5da53738cbc81db4e69ed8362', null::text,
     array[[c_store_prod_a, c_store_r], [c_prod_decl_a, c_prod_decl_r], [c_prod_credit_a, c_prod_credit_r],
           [c_prod_row_a, c_prod_row_r], [c_prod_audit_a, c_prod_audit_r]]),
    (2, '35af27479da6083ce5297b4a86e7d8cb', null::text,
     array[[c_store_a, c_store_r], [c_comp_decl_a, c_comp_decl_r], [c_comp_credit_a, c_comp_credit_r],
           [c_comp_audit_a, c_comp_audit_r]]),
    (3, 'ef9775bc5650a8e0da377af9b9fdd18f', null::text,
     array[[c_store_a, c_store_r], [c_bund_decl_a, c_bund_decl_r], [c_bund_credit_a, c_bund_credit_r],
           [c_bund_row_a, c_bund_row_r], [c_bund_audit_a, c_bund_audit_r]]),
    (4, 'cf07451f61cc45b1cef2bd8e31141330', null::text,
     array[[c_quote_decl_a, c_quote_decl_r], [c_quote_snap_a, c_quote_snap_r],
           [c_quote_credit_a, c_quote_credit_r], [c_quote_ret_a, c_quote_ret_r]]),
    (5, '2480074e2b77e313b052cc225493087c', null::text,
     array[[c_orig_decl_a, c_orig_decl_r], [c_orig_ret_a, c_orig_ret_r]]),
    (6, '93ebc0e25991428c5e94a71879bbef41', null::text,
     array[[c_blc_with_a, c_blc_with_r], [c_blc_fixed_a, c_blc_fixed_r], [c_blc_chosen_a, c_blc_chosen_r],
           [c_blc_union_a, c_blc_union_r]]),
    (7, 'b804b14bd80fff3e813d801eb789e83d', null::text,
     array[[c_det_begin_a, c_det_begin_r], [c_det_inst_a, c_det_inst_r]]),
    (8, 'c9eb607b3e3b5b63b035478a28a080c0', null::text,
     array[[c_price_set_a, c_price_set_r]]),
    (9, '08bf621e2bf2459566c28e6fd515ade0', null::text,
     array[[c_all_call_a, c_all_call_r]]),
    (10, null::text, c_value_def, null::text[]),
    (11, null::text, c_preview_def, null::text[]),
    (12, null::text, c_npv_def, null::text[]),
    (13, 'd30f8a2740154353e9f65e2bb64963fa', null::text,
     array[[c_cei_decl_a, c_cei_decl_r], [c_cei_day_a, c_cei_day_r], [c_cei_cols_a, c_cei_cols_r],
           [c_cei_vals_a, c_cei_vals_r], [c_cei_pay_a, c_cei_pay_r], [c_cei_sync_a, c_cei_sync_r],
           [c_cei_audit_a, c_cei_audit_r]]),
    (14, '352b1277be6e3ef60dda4cce80949aff', null::text,
     array[[c_det_decl_a, c_det_decl_r], [c_det_when_a, c_det_when_r]]),
    (15, '9b36b621a0d46fdb0d5384560e48b6d3', null::text,
     array[[c_rei_ret_a, c_rei_ret_r], [c_rei_sel_a, c_rei_sel_r], [c_rei_where_a, c_rei_where_r],
           [c_rei_order_a, c_rei_order_r]])
  ) x(idx, before_md5, whole, edits)
  order by idx
  loop
    if to_regprocedure('public.' || c_fns[r.idx]) is null then
      if r.before_md5 is not null then
        raise exception '424: public.% is missing', c_fns[r.idx]; end if;
      d := r.whole;     -- a new function, not there yet
    else
      d := pg_get_functiondef(to_regprocedure('public.' || c_fns[r.idx]));
      v := md5(d);
      if v = c_after[r.idx] then
        raise notice '424: public.% is already this version; left alone', c_fns[r.idx];
        v_defs := v_defs || null::text;
        continue;
      elsif r.before_md5 is null then
        raise exception '424: public.% already exists with another text (md5 %). Re-read it and re-test before applying.', c_fns[r.idx], v;
      elsif v <> r.before_md5 then
        raise exception '424: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', c_fns[r.idx], v;
      end if;
      for k in 1 .. array_length(r.edits, 1) loop
        n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
        if n <> 1 then
          raise exception '424: anchor % of public.% was found % times, not once', k, c_fns[r.idx], n; end if;
        d := replace(d, r.edits[k][1], r.edits[k][2]);
      end loop;
    end if;
    -- Every text is the tested one before anything is installed.
    if md5(d) <> c_after[r.idx] then
      v_mismatch := concat_ws('; ', v_mismatch, c_fns[r.idx] || ' ' || md5(d));
    end if;
    v_defs := v_defs || d;
  end loop;
  if v_mismatch is not null then
    raise exception '424: a built function text is not the tested one: %', v_mismatch; end if;

  -- Relied on, not changed: the versions read on 9 Oct 2026 (a line's paid
  -- value; a bundle's stock items and the sale's record of them; the
  -- whole-bundle preview and the trigger that makes the replacement invoice;
  -- the invoice instalment check; who is asking; and, for rule 8, what dates
  -- money and commission: commission by the paid date, part-payment
  -- commission by the date it is given, the Sales reports and the Xero export
  -- by each payment's date).
  for r in select * from (values
    ('invoice_discounted_line_value(uuid)', 'ead4a430c3abd1e3f953912867ca4fe6'),
    ('promotion_stock_items(uuid,integer)', '82dd6bdac5566fce0b75470eb45444d1'),
    ('capture_invoice_stock_components()', '9f68df58f5cefced3cd68eb62a8877a7'),
    ('exchange_bundle_preview(uuid,uuid,uuid,uuid)', 'c09fce506c8b92c321e8cf0f589691ff'),
    ('trg_exchange_invoice()', 'f4a84ead2fd5fa51d2e50d70da206e38'),
    ('validate_invoice_business_metadata()', 'c6e4436575e1c5ec8580d2b3d9d11d50'),
    ('require_active_staff(text[])', '877b3aa74cea559881979bb161c450e2'),
    ('user_has_store_access(uuid)', '8c82c6bcb64f496c5a05a2b8dafa95f8'),
    ('earn_invoice_commission(uuid)', '6156b2e1ee51da5146a5a7acc16091ce'),
    ('earn_staff_commission(uuid)', '03e4de1a5ba3d372e6cbb4de64b2c92d'),
    ('sync_instalment_commissions(uuid,text,date,boolean,boolean)', '88d7b122778801a0d5eea0b6dd8395b7'),
    ('payment_sales_date(timestamp with time zone,timestamp with time zone)', '3e5161e4830f5f6fdc8f34a24266fdc9'),
    ('invoice_sales_ledger()', '6278b7ac91ebbd2ae96a7e2182a29f33'),
    ('xero_sales_event_rows(date,date)', '18858e023c44d06814e617299456084b')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '424: public.% is missing or not the version read on 9 Oct 2026. Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;
  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = any (c_names)
     and p.oid::regprocedure::text <> all (c_fns);
  if v_bad is not null then
    raise exception '424: another overload exists: %', v_bad; end if;

  -- product_exchanges.affiliate_id: unused, nothing depends on it, and its one
  -- constraint is the foreign key to the legacy affiliates table.
  v_drop_column := exists (select 1 from pg_attribute where attrelid = 'public.product_exchanges'::regclass
                            and attname = 'affiliate_id' and not attisdropped);
  if v_drop_column then
    if exists (select 1 from public.product_exchanges where affiliate_id is not null) then
      raise exception '424: product_exchanges.affiliate_id is used by % exchange(s); it was empty on 9 Oct 2026',
        (select count(*) from public.product_exchanges where affiliate_id is not null); end if;
    select string_agg(distinct coalesce(c.relname, d2.classid::regclass::text), ', ') into v_bad
      from pg_depend d2
      left join pg_rewrite w on d2.classid = 'pg_rewrite'::regclass and w.oid = d2.objid
      left join pg_class c on c.oid = w.ev_class
     where d2.refobjid = 'public.product_exchanges'::regclass
       and d2.refobjsubid = (select attnum from pg_attribute where attrelid = 'public.product_exchanges'::regclass
                               and attname = 'affiliate_id')
       and d2.classid <> 'pg_constraint'::regclass;
    if v_bad is not null then
      raise exception '424: something depends on product_exchanges.affiliate_id: %', v_bad; end if;
    select string_agg(k2.conname || ' ' || pg_get_constraintdef(k2.oid), '; ') into v_bad
      from pg_constraint k2
     where k2.conrelid = 'public.product_exchanges'::regclass
       and (select attnum from pg_attribute where attrelid = 'public.product_exchanges'::regclass
              and attname = 'affiliate_id') = any (k2.conkey)
       and not (k2.conname = 'product_exchanges_affiliate_id_fkey'
                and pg_get_constraintdef(k2.oid) = 'FOREIGN KEY (affiliate_id) REFERENCES affiliates(id)');
    if v_bad is not null then
      raise exception '424: product_exchanges.affiliate_id has other constraints: %', v_bad; end if;
    if exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'product_exchanges'
                and coalesce(p.qual, '') || ' ' || coalesce(p.with_check, '') ~ '(^|[^_])affiliate_id') then
      raise exception '424: a rule on product_exchanges reads affiliate_id'; end if;
    -- A function's text records no dependency, so the functions that name
    -- product_exchanges are read too. Only five name an affiliate_id beside
    -- it, and none reads this column: the three creators,
    -- create_exchange_invoice and set_exchange_details (all five guarded
    -- above). Any other is refused, comments aside.
    select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v_bad
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.prosrc ~* 'product_exchanges'
       and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* '\maffiliate_id\M'
       and p.oid::regprocedure::text <> all (c_fns[1:3] || array['create_exchange_invoice(uuid)',
                                                               'set_exchange_details(uuid,jsonb,jsonb,uuid,date,text)']);
    if v_bad is not null then
      raise exception '424: a function may read product_exchanges.affiliate_id: %', v_bad; end if;
  end if;

  -- The code index: already exactly this one, or no two live promotions share a code.
  v_make_index := to_regclass('public.promotions_code_live_key') is null;
  if not v_make_index then
    if (select pg_get_indexdef(to_regclass('public.promotions_code_live_key'))) is distinct from c_index_def then
      raise exception '424: public.promotions_code_live_key exists and is not this index: %',
        pg_get_indexdef(to_regclass('public.promotions_code_live_key')); end if;
  else
    select string_agg(x.code, ', ' order by x.code) into v_bad
      from (select lower(btrim(code)) as code from public.promotions
             where deleted_at is null group by 1 having count(*) > 1) x;
    if v_bad is not null then
      raise exception '424: live promotions share a code (%); rename or delete one of each before applying', v_bad; end if;
  end if;

  select array_agg(coalesce(p.proacl::text, '') order by p.oid::regprocedure::text) into v_acl
    from pg_proc p where p.oid = any (array(select to_regprocedure('public.' || c_fns[x]) from unnest(c_in_place) x));
  -- report_exchange_invoices is dropped and made again (its return gains a
  -- column): only while nothing depends on it, and its grants are kept here
  -- to be put back.
  select array_agg(g order by g) into v_rei_acl
    from (select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end || '=' || a.privilege_type as g
            from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
           where p.oid = to_regprocedure('public.' || c_fns[15]) and a.grantee <> p.proowner) q;
  if v_defs[15] is not null then
    select string_agg(d2.classid::regclass::text || ' ' || d2.objid::text, ', ') into v_bad
      from pg_depend d2 where d2.refclassid = 'pg_proc'::regclass and d2.refobjid = to_regprocedure('public.' || c_fns[15]);
    if v_bad is not null then
      raise exception '424: something depends on public.%: %', c_fns[15], v_bad; end if;
  end if;

  -- ── Install: the new functions first, then the patched ones that call them ──
  foreach i in array array[12, 10, 11, 1, 2, 3, 4, 5, 6, 7, 8, 9, 13, 14, 15] loop
    if v_defs[i] is not null then
      if i = 15 then
        execute 'drop function public.report_exchange_invoices(uuid,date,date)';
      end if;
      execute v_defs[i];
    end if;
  end loop;
  -- report_exchange_invoices: its grants exactly as they were (a new function
  -- would otherwise take the schema's defaults).
  if v_defs[15] is not null then
    execute 'revoke all on function public.report_exchange_invoices(uuid,date,date) from public, anon, authenticated, service_role';
    foreach v in array coalesce(v_rei_acl, '{}') loop
      execute format('grant %s on function public.report_exchange_invoices(uuid,date,date) to %s',
                     split_part(v, '=', 2), split_part(v, '=', 1));
    end loop;
  end if;
  -- The internal helpers: the service role's alone (339). The preview: staff's.
  revoke all on function public.exchange_credit_value(uuid,uuid,uuid,integer) from public, anon, authenticated;
  grant execute on function public.exchange_credit_value(uuid,uuid,uuid,integer) to service_role;
  revoke all on function public.promotion_non_product_value(uuid,uuid) from public, anon, authenticated;
  grant execute on function public.promotion_non_product_value(uuid,uuid) to service_role;
  revoke all on function public.exchange_credit_preview(uuid,uuid) from public, anon;
  grant execute on function public.exchange_credit_preview(uuid,uuid) to authenticated, service_role;

  if v_drop_column then
    alter table public.product_exchanges drop column affiliate_id;
  end if;
  if v_make_index then
    create unique index promotions_code_live_key on public.promotions (lower(btrim(code))) where deleted_at is null;
  end if;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  v_bad := null;
  for i in 1 .. array_length(c_fns, 1) loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || c_fns[i])));
    if v <> c_after[i] then
      v_bad := concat_ws('; ', v_bad, c_fns[i] || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '424: installed with md5s other than the tested ones: %', v_bad; end if;
  if (select array_agg(coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
        from pg_proc p where p.oid = any (array(select to_regprocedure('public.' || c_fns[x]) from unnest(c_in_place) x)))
     is distinct from v_acl
     or (select array_agg(g order by g)
           from (select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end || '=' || a.privilege_type as g
                   from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                  where p.oid = to_regprocedure('public.' || c_fns[15]) and a.grantee <> p.proowner) q)
        is distinct from v_rei_acl then
    raise exception '424: the grants of a patched function changed'; end if;
  foreach v in array c_fns loop
    if has_function_privilege('anon', 'public.' || v, 'execute') then
      raise exception '424: public.% is callable signed out', v; end if;
    if not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '424: public.% is not the service role''s', v; end if;
    if v = any (c_internal) then
      if has_function_privilege('authenticated', 'public.' || v, 'execute') then
        raise exception '424: public.% is callable by a client role', v; end if;
    elsif not has_function_privilege('authenticated', 'public.' || v, 'execute') then
      raise exception '424: public.% is not callable by staff', v;
    end if;
  end loop;
  if exists (select 1 from pg_attribute where attrelid = 'public.product_exchanges'::regclass
              and attname = 'affiliate_id' and not attisdropped)
     or exists (select 1 from pg_constraint where conname = 'product_exchanges_affiliate_id_fkey') then
    raise exception '424: product_exchanges.affiliate_id or its foreign key is still there'; end if;
  if (select pg_get_indexdef(to_regclass('public.promotions_code_live_key'))) is distinct from c_index_def then
    raise exception '424: the promotion code index is not as tested'; end if;

  -- ── Behaviour, as the server, in a block that is always undone ───────────
  -- Made-up records only (named "424 check", @sig.invalid); nothing printed.
  begin
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
    insert into auth.users (id, email) values (gen_random_uuid(), '424-check-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '424 check', u.email, 'owner', true from auth.users u where u.id = v_owner;
    insert into public.stores (name, code, country_code)
      values ('424 check', '424-' || substr(md5(gen_random_uuid()::text), 1, 10), 'SG') returning id into v_st;
    insert into public.products (name, sku, product_type)
      values ('424 check A', '424A-' || substr(md5(gen_random_uuid()::text), 1, 10), 'own') returning id into v_pa;
    insert into public.products (name, sku, product_type)
      values ('424 check B', '424B-' || substr(md5(gen_random_uuid()::text), 1, 10), 'own') returning id into v_pb;
    insert into public.products (name, sku, product_type)
      values ('424 check C', '424C-' || substr(md5(gen_random_uuid()::text), 1, 10), 'own') returning id into v_pc;
    insert into public.store_product_prices (store_id, product_id, selling_price, is_active)
      values (v_st, v_pa, 100, true), (v_st, v_pb, 30, true), (v_st, v_pc, 50, true);
    -- A deleted customer: never listed, and no phone is claimed.
    insert into public.customers (full_name, phone, deleted_at)
      values ('424 check', '+61491579760', now()) returning id into v_cust;
    insert into public.invoices (invoice_no, store_id, customer_id, created_by, status,
                                 subtotal, total_amount, paid_amount, paid_at)
      values ('424-CHECK-' || substr(md5(gen_random_uuid()::text), 1, 10), v_st, v_cust, v_owner, 'paid',
              100, 75, 75, now()) returning id into v_inv;
    insert into public.invoice_items (invoice_id, line_kind, product_id, quantity, unit_price, line_total)
      values (v_inv, 'product', v_pa, 1, 100, 100) returning id into v_li;
    -- Paid S$75 for an item priced S$100: it counts for S$75 ...
    v_val := public.exchange_credit_value(v_li, v_st, null, null);
    if (v_val->>'todays')::numeric <> 100 or (v_val->>'paid')::numeric <> 75 or (v_val->>'credit')::numeric <> 75 then
      raise exception '424: a line paid S$75 at S$100 today does not count for S$75: %', v_val; end if;
    -- ... and for S$60 once today's price is S$60.
    update public.store_product_prices set selling_price = 60 where store_id = v_st and product_id = v_pa;
    v_val := public.exchange_credit_value(v_li, v_st, null, null);
    if (v_val->>'credit')::numeric <> 60 then
      raise exception '424: a line paid S$75 at S$60 today does not count for S$60: %', v_val; end if;
    -- A bundle of A (S$60 now) and a choice of 2 from B (S$30) or C (S$50).
    insert into public.promotions (name, code, fixed_price)
      values ('424 check bundle', '424-' || substr(md5(gen_random_uuid()::text), 1, 10), 100) returning id into v_pr;
    insert into public.promotion_items (promotion_id, item_type, product_id, quantity) values (v_pr, 'product', v_pa, 1);
    insert into public.promotion_choice_groups (promotion_id, label, item_kind, choose_qty, base_mode)
      values (v_pr, '424 check', 'product', 2, 'cheapest') returning id into v_g;
    insert into public.promotion_choice_options (group_id, product_id) values (v_g, v_pb), (v_g, v_pc);
    v_num := public.promotion_original_total(v_pr, v_st);
    if v_num <> 120 then
      raise exception '424: the bundle''s Original with the cheapest base is %, not 120', v_num; end if;
    update public.promotion_choice_groups set base_mode = 'highest' where id = v_g;
    v_num := public.promotion_original_total(v_pr, v_st);
    if v_num <> 160 then
      raise exception '424: the bundle''s Original with the dearest base is %, not 160', v_num; end if;
    -- A vouchers group set to its dearest still counts its cheapest (S$10 of
    -- S$150 and S$10), as the till's top-up reads the setting for products only.
    insert into public.vouchers (name, code, selling_price)
      values ('424 check', '424V-' || substr(md5(gen_random_uuid()::text), 1, 10), 150) returning id into v_vo;
    insert into public.vouchers (name, code, selling_price)
      values ('424 check', '424V-' || substr(md5(gen_random_uuid()::text), 1, 10), 10) returning id into v_vo2;
    insert into public.promotion_choice_groups (promotion_id, label, item_kind, choose_qty, base_mode)
      values (v_pr, '424 check vouchers', 'voucher', 1, 'highest') returning id into v_g2;
    insert into public.promotion_choice_options (group_id, voucher_id) values (v_g2, v_vo), (v_g2, v_vo2);
    v_num := public.promotion_original_total(v_pr, v_st);
    if v_num <> 170 then
      raise exception '424: a vouchers group set to its dearest counts %, not its cheapest (Original 170)', v_num; end if;
    -- A bundle line keeps what it sold after the bundle is edited.
    delete from public.promotion_choice_groups where id in (v_g, v_g2);
    insert into public.invoice_items (invoice_id, line_kind, promotion_id, quantity, unit_price, line_total)
      values (v_inv, 'promotion', v_pr, 1, 100, 100) returning id into v_li2;
    update public.promotion_items set product_id = v_pb where promotion_id = v_pr;
    if (select string_agg(b.product_id::text || 'x' || b.quantity, ',') from public.bundle_line_components(v_li2) b)
       is distinct from v_pa::text || 'x1' then
      raise exception '424: a bundle line does not keep what it sold after the bundle was edited'; end if;
    -- One product of a bundle that also gives a voucher counts for its share
    -- of everything the line gave: C (S$50) and a S$150 voucher, sold for
    -- S$100, so C counts for S$25.
    insert into public.promotions (name, code, fixed_price)
      values ('424 check mixed', '424-' || substr(md5(gen_random_uuid()::text), 1, 10), 100) returning id into v_pr2;
    insert into public.promotion_items (promotion_id, item_type, product_id, quantity) values (v_pr2, 'product', v_pc, 1);
    insert into public.promotion_items (promotion_id, item_type, voucher_id, quantity) values (v_pr2, 'voucher', v_vo, 1);
    insert into public.invoices (invoice_no, store_id, customer_id, created_by, status,
                                 subtotal, total_amount, paid_amount, paid_at)
      values ('424-CHECK-' || substr(md5(gen_random_uuid()::text), 1, 10), v_st, v_cust, v_owner, 'paid',
              100, 100, 100, now()) returning id into v_inv2;
    insert into public.invoice_items (invoice_id, line_kind, promotion_id, quantity, unit_price, line_total)
      values (v_inv2, 'promotion', v_pr2, 1, 100, 100) returning id into v_li3;
    v_val := public.exchange_credit_value(v_li3, v_st, v_pc, 1);
    if (v_val->>'todays')::numeric <> 50 or (v_val->>'paid')::numeric <> 25 or (v_val->>'credit')::numeric <> 25 then
      raise exception '424: a S$50 product of a S$100 bundle that also gave a S$150 voucher does not count for S$25: %', v_val; end if;
    -- An exchange stored with a date in the month before is invoiced on the
    -- 1st of this month (on the day it is saved, when that is the 1st): its
    -- date, its paid date, its payment's date and its Xero receipt.
    v_first := date_trunc('month', public.sg_today()::timestamp)::date;
    insert into public.payment_methods (name, is_active) values ('424 check', true) returning id into v_pm;
    insert into public.product_exchanges (exchange_no, original_invoice_id, customer_id, processing_store_id,
                                          replacement_total, topup_amount, status, created_by, exchange_date)
      values ('424-CHECK-' || substr(md5(gen_random_uuid()::text), 1, 10), v_inv, v_cust, v_st,
              30, 30, 'completed', v_owner, v_first - 1) returning id into v_ex;
    insert into public.product_exchange_items (exchange_id, direction, product_id, quantity, unit_price, line_total)
      values (v_ex, 'replacement', v_pb, 1, 30, 30);
    insert into public.product_exchange_payments (exchange_id, payment_method_id, amount) values (v_ex, v_pm, 30);
    v_inv3 := public.create_exchange_invoice(v_ex);
    if (select business_date from public.invoices where id = v_inv3) is distinct from v_first
       or (select (paid_at at time zone 'Asia/Singapore')::date from public.invoices where id = v_inv3) is distinct from v_first
       or (select count(*) from public.invoice_payments p where p.invoice_id = v_inv3
            and public.payment_sales_date(p.effective_at, p.created_at) = v_first) <> 1
       or not exists (select 1 from public.xero_sales_event_rows(v_first, v_first) x
                       where x.invoice_id = v_inv3 and x.event_kind = 'receipt' and x.amount = 30) then
      raise exception '424: an exchange dated in the month before is not invoiced on the 1st of this month'; end if;
    -- A price set with "available" null keeps a store switched off (as the owner).
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_owner::text, true);
    perform public.set_promotion_prices(v_pr, v_st, 90, 90, false);
    perform public.set_promotion_prices(v_pr, v_st, 95, 95, null);
    if (select selling_price::numeric || '/' || available_at_store::text from public.promotion_store_prices
         where promotion_id = v_pr and store_id = v_st) is distinct from '95.00/false' then
      raise exception '424: a promotion price set with "available" null did not keep the store switched off'; end if;
    perform public.set_promotion_prices(v_pr, v_st, 95, 95, true);
    if not (select available_at_store from public.promotion_store_prices where promotion_id = v_pr and store_id = v_st) then
      raise exception '424: a promotion price set with "available" true did not switch the store on'; end if;
    -- An exchange cannot be dated in the month before (as the owner).
    begin
      perform public.set_exchange_details(v_ex, jsonb_build_array(v_owner), '{"mode":"none"}'::jsonb, v_owner, v_first - 1, null);
      raise exception '424: a date in the month before was taken for an exchange';
    exception when others then
      if sqlerrm not like 'An exchange can be dated from the 1st of this month%' then raise; end if;
    end;
    -- Neither signed out nor a login with no profile may preview, or reach the helper.
    foreach v_who in array array['anon', 'authenticated'] loop
      perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', v_who)::text, true);
      perform set_config('request.jwt.claim.sub', '', true);
      execute format('set local role %I', v_who);
      begin
        perform public.exchange_credit_preview(v_inv, v_st);
        raise exception '424: % may preview an exchange''s credit', v_who;
      exception when insufficient_privilege then null;
      end;
      begin
        perform public.exchange_credit_value(v_li, v_st, null, null);
        raise exception '424: % may call exchange_credit_value', v_who;
      exception when insufficient_privilege then null;
      end;
      begin
        perform public.promotion_non_product_value(v_pr2, v_st);
        raise exception '424: % may call promotion_non_product_value', v_who;
      exception when insufficient_privilege then null;
      end;
      execute 'reset role';
    end loop;
    raise exception using errcode = 'P0424', message = '424: check done, undone';
  exception when sqlstate 'P0424' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
