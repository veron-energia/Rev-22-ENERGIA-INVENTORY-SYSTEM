-- 443_credit_package_and_premium_bundle_credit_apart.sql
--
-- CREDIT PACKAGE CREDIT AND PREMIUM BUNDLE CREDIT KEPT APART: SHOWN APART,
-- AND PAID FROM WITH A WALLET METHOD OF THEIR OWN (the Owner's answers, 21
-- Oct 2026, CREDIT-SPLIT-1..14)
--
-- WHAT WAS WRONG
--
--   * A customer's wallet is one set of lots (customer_credit_lots, 77). Each
--     lot already says where it came from (source_type 'credit_package' or
--     'premium_bundle', and the package or bundle), but every balance added
--     the lots up by category alone (customer_credit_balances, 77): "Paid"
--     was package Paid credit + bundle Paid credit + Paid opening balances,
--     "Bonus" package Bonus + bundle Bonus. On production, 21 Oct 2026: Paid
--     S$28,251 = package S$13,958 + bundle S$11,259 + opening balance S$3,034;
--     Bonus S$3,050 = package S$1,050 + bundle S$2,000 (counts and sums only).
--     The customer page, the Record Payment figures and the printed, PDF and
--     WhatsApp/email "Credit balance" line all showed those mixed figures.
--   * At the till staff chose a category, never a source: the five wallet
--     methods of 82 ('Wallet — Paid Credit', ...) passed their category to
--     allocate_invoice_wallet_credit (82/175, patched in place by 180, 242
--     and 309), which took the oldest eligible lot of that category from
--     any source. One customer holds both kinds today.
--   * Record Payment's "S$X available" was the whole category, also credit
--     that cannot pay this invoice's items (package Paid credit buys therapy
--     sessions only, by credit_package_default_rules, 309), which the server
--     then refused ("Only 0.00 of the requested ... could be funded by
--     eligible credit"). Its note "Bonus Credit is always spent first" did
--     not describe what happens (each method draws its own category only).
--
-- THE OWNER'S ANSWERS (21 Oct 2026; keys CREDIT-SPLIT-1..14)
--
--   1. "Premium package" is the Premium Bundle.
--   2. Show AND choose. Not in scope: the Adjust and Opening balance windows,
--      the credit statement, the Dashboard and Reports, spending rules,
--      expiry.
--   3. Split both Paid and Bonus, for both sources.
--   4. Grouped by type (Credit Package / Premium Bundle / Other); the
--      customer page also lists each package and bundle bought, underneath,
--      with what is left.
--   5. New wallet payment methods per source.
--   6. Credit Package first by default when both could pay; staff can
--      switch.
--   7. One invoice may be paid from both, one payment row per source.
--   8. The payment screen's "available" per method counts only credit that
--      can pay THIS invoice's items; the wrong note goes.
--   9. 'Wallet — Paid Credit' and 'Wallet — Bonus Credit' stay, and pay from
--      'other' credit only (neither package nor bundle: opening balances,
--      Adjust increases); past payments keep their names; the Legacy,
--      Promotional/FOC and Exchange methods are unchanged.
--   10. The new methods: 'Wallet — Credit Package Paid', 'Wallet — Credit
--       Package Bonus', 'Wallet — Premium Bundle Paid', 'Wallet — Premium
--       Bundle Bonus' (system, protected like the five).
--   11. The printed invoice, PDF and WhatsApp/email image read 'Credit
--       Package S$… · Premium Bundle S$… · Other S$…' (non-zero only) in
--       place of 'Paid S$… · Bonus S$…' (the pages; nothing here).
--   12. The 3 Legacy lots linked through credit_package_progress_lots to
--       Premium Bundle invoice lines show as Premium Bundle (records
--       unchanged; they still pay through the Legacy method).
--   13. Past wallet payments show their source in brackets, worked out from
--       the lots they used, e.g. 'Wallet — Paid Credit (Premium Bundle)'; no
--       record changes.
--   14. Merged credit losing its source (merge_customer_records, 425) is NOT
--       part of this; later, after 441.
--
-- HOW IT READS (decided here, 21 Oct 2026)
--
--   * No new credit category and no lot touched: the lots already say where
--     they came from. A source dimension is added to the payment methods
--     (payment_methods.wallet_source: null, 'credit_package' or
--     'premium_bundle'), and one helper names a lot's source.
--   * credit_lot_source_group(lot): 'credit_package', 'premium_bundle' or
--     'other'. Moved credit (Move, 186) counts as its origin
--     (invoice_credit_transfer_origin, 250, as the spending rules read it);
--     an invoice reassigned to another customer keeps source_type (321);
--     otherwise a lot recorded as a package's or bundle's released credit
--     (credit_package_progress_lots, 328), or granted against such a line
--     (327's 'credit_package_progress'), or reassigned from such a lot,
--     belongs to that line's kind: this is how the 3 Legacy lots read as
--     Premium Bundle (12). Everything else is 'other': opening balances,
--     Adjust, exchange credit, merged credit ('customer_merge', 14).
--   * What a method pays from (wallet_method_source_filter): a method of a
--     source, that source; a Paid or Bonus method naming none ('Wallet —
--     Paid Credit', 'Wallet — Bonus Credit', and any other Paid or Bonus
--     wallet method), 'other' only (9); Legacy, Promotional/FOC, Exchange,
--     and a wallet method with no category: any source, as before (9).
--   * Default (6): a method of any source takes Bonus first (as before),
--     then Credit Package credit, then the oldest. On the payment screen the
--     methods are listed Credit Package first, then Premium Bundle, then the
--     rest; the server names the first method that can pay anything as the
--     default ('default_method_id'). Nothing is chosen for staff.
--   * "Available" (8) is what the allocator would draw from that method
--     alone if asked for everything: the same lines, lots, rules and order
--     (credit_lot_snapshot_allows, credit_lot_line_allowed), read without
--     writing. Paying exactly that is accepted, a cent more is refused.
--   * Corrections: a correction through another wallet method pays from that
--     method's source. Through the same method it keeps its source: for a
--     Paid or Bonus method naming none, the source its lots came from, so a
--     payment taken from Premium Bundle credit through 'Wallet — Paid Credit'
--     before 443 is corrected from Premium Bundle credit (13) (one that drew
--     on several sources, from any). A refunded wallet payment cannot change
--     where its credit comes from (as it could not change its category).
--     Refunds and reopenings return credit to the very lot, as before.
--
-- WHAT THIS DOES
--
--   1. payment_methods.wallet_source (text, null), checked: 'credit_package'
--      or 'premium_bundle', and then only on a system Paid or Bonus wallet
--      method. The four methods of 10, system and on, like the five.
--   2. trg_protect_system_payment_methods(): a system method's source cannot
--      be changed either (with its category, wallet flag, name, on/off).
--   3. New, the server's alone: credit_lot_source_group(uuid) and
--      wallet_method_source_filter(text,text).
--   4. allocate_invoice_wallet_credit(uuid,numeric,text) becomes
--      allocate_invoice_wallet_credit(uuid,numeric,text,text): p_source
--      (default null: any) filters the lots by source, and Credit Package
--      credit comes before older credit (after Bonus). The three-argument one
--      is dropped (no overload left); its only callers are the two below. The
--      server's alone, as before.
--   5. record_invoice_payment(uuid,jsonb,uuid): a wallet payment draws from
--      its method's source. correct_invoice_payment(...): as above (keeps the
--      source; a refunded one cannot change it). Same signatures and grants.
--   6. customer_credit_balances(uuid): as before ('categories',
--      'available_total'), plus 'sources' (credit_package, premium_bundle,
--      other; each by category and total) and 'purchases' (each package and
--      bundle bought, with what is left: source, name, invoice, date,
--      received, paid, bonus, legacy, total; Credit Package first). A
--      purchase used up is listed too, at 0; one refunded in full or
--      cancelled with nothing left, or gone with its invoice to another
--      customer (reassigned, 321), is not; 'received' marks credit moved in
--      from another customer's invoice (Move, 186). Same grants.
--   7. New, for signed-in staff (require_active_staff first):
--      invoice_wallet_availability(uuid) for Record Payment (each wallet
--      method on: what it can pay of this invoice, what it holds, its rank,
--      and the default); invoice_payment_credit_sources(uuid) for the
--      invoice's payment rows (each wallet payment's sources, from its
--      lots; a correction's reversal answers for the payment it reverses).
--
-- NOT CHANGED
--
--   * No lot, ledger row, allocation, payment or invoice: past payments keep
--     their methods and names (13 is worked out when shown).
--   * The categories and their CHECKs (4 tables), the five methods of 82,
--     refunds (refund_invoice_recorded returns to the lot), reopening,
--     record_invoice_settlement, the spending rules, the statement
--     (customer_credit_statement), Adjust and Opening balance
--     (adjust_customer_credit, add_legacy_credit), consume_customer_credit
--     (special sales and rentals: no screen since 426), the Dashboard,
--     Reports, the Payment Summary (each new method gets its own wallet
--     column there by itself), Xero (wallet payments left out, as before),
--     merge_customer_records.
--   * None of the functions 441 pins (event_web_*, the name, phone and email
--     matchers, merge_customer_records): 441 goes before or after this file.
--
-- NOT COVERED (told to the Owner)
--
--   * Merged credit (merge_customer_records, 425) reissues lots as
--     'customer_merge': they read as Other, and cannot be spent anyway
--     (credit_lot_policy: needs_review). 14: later, after 441. None exist.
--   * Adjust decreases and Opening balance still take or add credit by
--     category (2): an Adjust increase is Other credit, paid through 'Wallet
--     — Paid Credit' / 'Wallet — Bonus Credit'; a decrease takes the oldest
--     credit of the category, from any source.
--   * The credit statement, the Dashboard's "Settled from credit", Reports,
--     the Payment Summary and the Invoices list and export ("Payment"
--     column) keep one name per method: past payments are not bracketed
--     there (2, 13 apply to the invoice and its copies).
--   * The default (6) is the order and the server's default_method_id; the
--     page lists Credit Package first and says so, and staff choose.
--     Nothing moves on to the other source by itself when one runs out (7).
--   * A past 'Wallet — Paid Credit' payment that drew on several sources is,
--     corrected through that method, drawn from any source (none on 21 Oct
--     2026: no payment mixed sources).
--   * "Available" is worked out per method alone: two wallet rows of
--     different methods on one invoice may each show the same line's
--     amount; the server takes them in turn and refuses what no credit can
--     pay. It is not capped at what the invoice still owes. The Credit
--     Package first reminder on a Premium Bundle row takes off what the
--     payment's other rows already put on Credit Package credit; it cannot
--     tell which lines each could pay, so when Credit Package credit could
--     still pay other lines than those it may stay quiet.
--   * The customer page's list of packages and bundles bought (4) starts
--     from the credit they released: one whose invoice is not paid yet has
--     released none and is listed once it does. A purchase refunded in full,
--     or cancelled, with nothing left is not listed; the purchase history
--     beside it still lists every invoice line.
--   * Approvals: the guided review of a refund or cancellation request
--     opened from Approvals names a wallet payment by its method alone, as
--     the server's plan does; opened from the invoice it carries the
--     bracket (13).
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * each text built is the tested one (its AFTER md5);
--   * each changed function is its BEFORE (production, 21 Oct 2026, after
--     442) or this file's AFTER (left alone); each new one is missing or the
--     AFTER; the three-argument allocator is production's or gone; no other
--     function takes one of these names;
--   * the functions relied on and not changed are as read on production (21
--     Oct 2026), below; auth.uid() and auth.role() are there;
--   * besides this file's own, only consume_customer_credit names the
--     allocator (in a comment), and only issue_customer_credit_statement
--     reads customer_credit_balances (its 'categories' and 'available_total',
--     unchanged);
--   * the columns read and written are as read; payment_methods' category
--     check and its one trigger are as read; wallet_source is missing or
--     exactly this file's column and check;
--   * no live method other than this file's own has one of the four names
--     (else it stops, naming it); the five of 82, where they are, are system
--     wallet methods of their category naming no source (production has all
--     five; a copy without them is told so and goes on);
--   * the grants of the changed functions are kept; the three-argument
--     allocator's are the server's alone, as read.
--   Afterwards: every md5 is the AFTER one; the changed functions keep their
--   grants; the new page functions are for signed-in logins (and the
--   server), the helpers and the allocator for the server alone; one
--   allocator; the four methods there, system and on. Then a self-test, in a
--   block that is always undone (it ends by raising P0443, so it leaves no
--   row): a made-up Owner, store, customer (a fictional phone no customer
--   has), product, package and bundle; package Paid 50 and Bonus 30, bundle
--   Paid 40, an opening balance Paid 7; on a product of 40, what each method
--   can pay (Credit Package Paid none of it, the default Credit Package
--   Bonus); one Record Payment from Credit Package Bonus and Premium Bundle
--   Paid makes two rows, each from its own source; a Paid method naming no
--   source pays 7 and refuses 7.01; the balance by source; renaming a new
--   method is refused. No therapy is sold (no therapy number is used), and
--   the invoice number it takes is counted, not drawn from a sequence; its
--   seven credit ledger rows draw seven entry numbers (a sequence, which an
--   undone transaction does not give back: a gap, which nothing counts), and
--   its stock row (the store_inventory insert, through the
--   stock_history_store_delta trigger) draws one stock-history id
--   (stock_history_inventory_changes_id_seq; the same: a gap nothing
--   counts). Each run, a dry run or a second run too, leaves these gaps. A
--   second run changes nothing else.
--   Locks: payment_methods (ALTER TABLE, the first run only; brief, the
--   table has a few rows), the replaced functions' catalogue rows, held to
--   the end of the apply; the rows the self-test writes and undoes. A
--   payment running at that moment finishes on the text it started with.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (... 440, 442) -> 443, before or after 441 (it pins none
--   of 441's functions, nor 441 any of this file's; both orders checked).
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below, the second changes
--      nothing ("left alone").
--   2. Apply (the CLI, or the MCP's apply_migration with this text verbatim).
--      It checks itself.
--   3. The pages, straight after (push main; Vercel): src/pages/InvoicesPage.tsx,
--      src/pages/CustomersPage.tsx, src/pages/PaymentMethodsPage.tsx,
--      src/pages/TherapyPage.tsx (the Credit Package editor's Bonus note),
--      src/components/invoices/InvoiceFinancePanel.tsx,
--      src/components/invoices/InvoiceGuidedAction.tsx,
--      src/lib/invoices/creditBalanceLine.mjs (and .d.mts),
--      src/lib/invoices/walletSources.mjs (and .d.mts), src/types/index.ts
--      (and comments in src/lib/invoicePdf.ts and invoiceImage.ts). The new
--      pages work before step 2 as the old ones did (no source figures, the
--      kinds on the print line, "available" from the balance). Between steps
--      2 and 3 the old pages list the four new methods with the category's
--      whole balance as "available", and 'Wallet — Paid Credit' / 'Wallet —
--      Bonus Credit' with package and bundle credit in their figure, which
--      the server now refuses ("Only 0.00 of the requested ... could be
--      funded by eligible credit"): staff then choose the Credit Package or
--      Premium Bundle method. No Edge Function or setting changes.
--
-- BEFORE (production, 21 Oct 2026, after 442; md5 of pg_get_functiondef with
-- search_path public)
--   changed
--   record_invoice_payment(uuid,jsonb,uuid)                        c3da81f28d5a24a1c5f336527cfc33a4
--   correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)      f3c96d9916a95a68a9202cdb25d8017b
--   trg_protect_system_payment_methods()                           9c1af002437091b7ef61b04221b254eb  (429's AFTER)
--   customer_credit_balances(uuid)                                 1b4620e97195b99fae3d8086051bc5b7
--   dropped (replaced by a four-argument one)
--   allocate_invoice_wallet_credit(uuid,numeric,text)              c19614b318e5d071cdac381517e63df8
--   relied on, not changed
--   invoice_credit_transfer_origin(uuid)                           e778a9e4ff81567a493b8ca479d8222b
--   credit_lot_snapshot_allows(uuid,jsonb,text,uuid)               1d78a592687366f98b52adcb655c51fb
--   credit_lot_line_allowed(uuid,uuid)                             7d81252612104b1012b6d78513092091
--   invoice_line_credit_purpose(text)                              ff61d218e5bd8f272885216e23c0a1a6
--   ensure_customer_wallet(uuid)                                   8ef18daebbbe3c12f2024290ea8416e8
--   can_view_customer_credit()                                     347f20fdfcbe7e2666f9d6995bb53647
--   user_has_store_access(uuid)                                    708992afaa6c3951f6329239b742987c
--   require_active_staff(text[])                                   877b3aa74cea559881979bb161c450e2
--   invoice_record_payments_internal(uuid,jsonb)                   21890d84bcb0b9c00a2bc98aff313d0b
--   invoice_financial_position(uuid)                               ba7eccbfeff217c8b1969b0e55a010ca
--   is_owner_or_manager()                                          a98e50f1b6d3fa1e6c62cf52a8073cc8
--   sg_today()                                                     1c1289f18e24d8370e9a6364c9c06fca
--   invoice_payment_remaining(uuid)                                aad3ba468c8d7ddec8791e172d6ac16f
--   invoice_net_received(uuid)                                     f256bea69b7defa38a950753bbc248da
--   invoice_charge_total(uuid)                                     8297147511ba285db2279598f3d727fb
--   reconcile_invoice_commissions(uuid,text)                       3c267728e215d17ebeb9cfe9cb7db47c
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   grant_customer_credit(uuid,text,numeric,text,uuid,uuid,date,text,text,text,date,uuid,jsonb)
--                                                                  ac0de5530624ee533aacf93aec389910  (the self-test)
--   public function fingerprint, production now (442 in)           c2dac6760bd1be258563f69203c30279 (1366 functions)
-- AFTER (for later guards)
--   credit_lot_source_group(uuid)                                  6b902cb426210eb10ee9a15344ff100b  (new)
--   wallet_method_source_filter(text,text)                         e292157a96bf91bf54f1ef0ed19498c0  (new)
--   allocate_invoice_wallet_credit(uuid,numeric,text,text)         da8aa986c92d765a8028741f33bf56b0  (new signature)
--   record_invoice_payment(uuid,jsonb,uuid)                        9c70097ed4da614fb9dcc66fdfcdb7d6
--   correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)      af99337094edb6d73b9cc0ae00fbf138
--   trg_protect_system_payment_methods()                           74bca50e1b15f8b5b61a17ce6a350c5a
--   customer_credit_balances(uuid)                                 c2287779ce0ec9c52eeec41952055f78
--   invoice_wallet_availability(uuid)                              8d828727572b013bc54a2b07e6a3f7a0  (new)
--   invoice_payment_credit_sources(uuid)                           bf9f73f9363614794da78d24cd118dcc  (new)
--   public function fingerprint, worked out on copies of production (21 Oct 2026):
--     production now -> 443 (a second run the same)              1fbce365ba02d5ccf3956045a7982ac0 (1370 functions: 5 new, 1 dropped)
--     production now -> 443 -> 441                                d8bfc0b83af95d114f2d9f8f2489d3e0 (1370)
--     production now -> 441 -> 443                                d8bfc0b83af95d114f2d9f8f2489d3e0 (1370; 441 alone 12bce2915a6566e4e5da73f1c69a0306, 1366)
--
-- Test: scripts/invoices/tests/credit-sources-443.sql (begin ... rollback; it
-- installs this file twice; -v nomig=1 where it is in). The pages:
-- scripts/invoices/tests/wallet-sources-443.test.mjs,
-- scripts/customers/tests/customers-page.test.mjs and
-- scripts/invoices/tests/credit-balance-print-browser.mjs. Suites that paid
-- package or bundle credit through 'Wallet — Paid Credit' / 'Wallet — Bonus
-- Credit' now pick the method of the credit's source (the same lookup finds
-- the old method before 443): credit-policy's bundle-releases-as-it-is-paid,
-- released-credit-paths, releases-as-it-is-paid, requested-flow-audit and
-- snapshot-does-not-gate, invoice-correction's reassignment-owns-one-purchase,
-- invoices' benefit-corrections and credit-transfer-policy, and integration's
-- cross-feature, and invoices/regression.sql. Suites that pay Other credit
-- (opening balances, Adjust) look up 'Wallet — Paid Credit' as the system
-- Paid method naming no source, oldest first (before 443, the one Paid
-- method), never the first Paid method in table order: credit-policy's
-- adjusted-credit-spends (and released-credit-paths' fixture), events,
-- reports' reports-367 and sales-by-service-staff, commissions'
-- part-payments-earn. payment-methods.sql and the before-416 prelude accept
-- this file's AFTER md5s; scripts/permissions/tests/function-grants.sql lists
-- the two helpers and the allocator as the server's alone, and (check 15)
-- keeps the three-argument allocator gone once this file is in.

set lock_timeout = '5s';

do $mig$
declare
  -- ── The functions this installs, in order: signature, BEFORE md5 (null:
  -- new), AFTER md5, who may call a new one (true: signed-in staff; false:
  -- the server alone; a changed one keeps its grants), and the text (as
  -- pg_get_functiondef gives it back with search_path public). ──────────────
  c_sig constant text[] := array[
    'credit_lot_source_group(uuid)',
    'wallet_method_source_filter(text,text)',
    'allocate_invoice_wallet_credit(uuid,numeric,text,text)',
    'record_invoice_payment(uuid,jsonb,uuid)',
    'correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)',
    'trg_protect_system_payment_methods()',
    'customer_credit_balances(uuid)',
    'invoice_wallet_availability(uuid)',
    'invoice_payment_credit_sources(uuid)'];
  c_before constant text[] := array[null, null, null,
    'c3da81f28d5a24a1c5f336527cfc33a4',
    'f3c96d9916a95a68a9202cdb25d8017b',
    '9c1af002437091b7ef61b04221b254eb',
    '1b4620e97195b99fae3d8086051bc5b7',
    null, null];
  c_after constant text[] := array[
    '6b902cb426210eb10ee9a15344ff100b',
    'e292157a96bf91bf54f1ef0ed19498c0',
    'da8aa986c92d765a8028741f33bf56b0',
    '9c70097ed4da614fb9dcc66fdfcdb7d6',
    'af99337094edb6d73b9cc0ae00fbf138',
    '74bca50e1b15f8b5b61a17ce6a350c5a',
    'c2287779ce0ec9c52eeec41952055f78',
    '8d828727572b013bc54a2b07e6a3f7a0',
    'bf9f73f9363614794da78d24cd118dcc'];
  c_client constant boolean[] := array[false, false, false, null, null, null, null, true, true];
  c_def constant text[] := array[
$def$CREATE OR REPLACE FUNCTION public.credit_lot_source_group(p_lot_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lot public.customer_credit_lots%rowtype; v_chain uuid[]; v_prev uuid; v_kind text;
begin
  -- 443 (the Owner, 21 Oct 2026, CREDIT-SPLIT-3..13): where a lot's credit
  -- came from, for the wallet methods per source, the balances, the payment
  -- screen and the labels of past wallet payments: 'credit_package',
  -- 'premium_bundle' or 'other' (neither: opening balances, Adjust increases,
  -- exchange credit, merged credit). Null: no such lot. Nothing is written.
  --   * Credit moved to another customer (Move, 186) is its origin's, as the
  --     spending rules read it (invoice_credit_transfer_origin, 250).
  --   * A lot's own source_type says Credit Package or Premium Bundle; an
  --     invoice reassigned to another customer keeps it (321).
  --   * Otherwise a lot recorded as the released credit of a Credit Package
  --     or Premium Bundle invoice line (credit_package_progress_lots, 328),
  --     or granted against such a line (327's credit_package_progress),
  --     belongs to that line's kind, and so does a lot reassigned from one
  --     (321): the 3 Legacy lots linked to Premium Bundle lines on 25 Sep
  --     2026 show as Premium Bundle (CREDIT-SPLIT-12; still Legacy credit).
  select * into v_lot from public.customer_credit_lots
   where id = coalesce(public.invoice_credit_transfer_origin(p_lot_id), p_lot_id);
  if not found then return null; end if;
  if v_lot.source_type in ('credit_package', 'premium_bundle') then return v_lot.source_type; end if;
  v_chain := array[v_lot.id];
  loop
    select l.reassigned_from_lot_id into v_prev from public.customer_credit_lots l
     where l.id = v_chain[cardinality(v_chain)];
    exit when v_prev is null or v_prev = any (v_chain) or cardinality(v_chain) > 12;
    v_chain := v_chain || v_prev;
  end loop;
  select ii.line_kind::text into v_kind
    from public.credit_package_progress_lots pl
    join public.invoice_items ii on ii.id = pl.invoice_item_id
   where pl.lot_id = any (v_chain) and ii.line_kind::text in ('credit_package', 'premium_bundle')
   order by array_position(v_chain, pl.lot_id), pl.created_at
   limit 1;
  if v_kind is null then
    select ii.line_kind::text into v_kind
      from public.customer_credit_lots l
      join public.invoice_items ii on ii.id = l.source_record_id
     where l.id = any (v_chain) and l.source_type = 'credit_package_progress'
       and ii.line_kind::text in ('credit_package', 'premium_bundle')
     order by array_position(v_chain, l.id)
     limit 1;
  end if;
  return coalesce(v_kind, 'other');
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.wallet_method_source_filter(p_category text, p_source text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  -- 443 (the Owner, 21 Oct 2026, CREDIT-SPLIT-5, 9, 10): the credit a wallet
  -- payment method pays from, by source (credit_lot_source_group). A method
  -- of a source ('Wallet — Credit Package Paid' and the three others) pays
  -- from that source alone; a Paid or Bonus method naming no source ('Wallet
  -- — Paid Credit', 'Wallet — Bonus Credit') from 'other' credit alone; the
  -- Legacy, Promotional/FOC and Exchange methods, and a method with no
  -- category, from any source, as before (null).
  select case when p_source is not null then p_source
              when p_category in ('paid', 'bonus') then 'other' end
$function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.allocate_invoice_wallet_credit(p_invoice_id uuid, p_amount numeric, p_category text DEFAULT NULL::text, p_source text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_inv public.invoices%rowtype; v_it record; v_lot record;
  v_remaining numeric; v_line_open numeric; v_take numeric;
  v_wallet uuid; v_entry uuid; v_alloc jsonb := '[]'::jsonb; v_total numeric := 0;
  v_purpose text; v_vid uuid;
begin
  -- 443 (the Owner, 21 Oct 2026): p_source, where the credit comes from
  -- (credit_lot_source_group: 'credit_package', 'premium_bundle' or 'other';
  -- null: any), as the wallet method's wallet_method_source_filter says.
  if p_source is not null and p_source not in ('credit_package', 'premium_bundle', 'other') then
    raise exception 'Unknown wallet credit source %', p_source; end if;
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if v_inv.customer_id is null then
    raise exception 'Wallet credit needs a customer on the invoice'; end if;
  if v_inv.status not in ('draft','unpaid','partially_paid') then
    raise exception 'Wallet credit can only be applied to an unsettled invoice'; end if;
  if coalesce(p_amount,0) <= 0 then raise exception 'The wallet amount must be positive'; end if;

  v_wallet := public.ensure_customer_wallet(v_inv.customer_id);
  v_remaining := round(p_amount, 2);

  for v_it in
    select ii.*, public.invoice_line_credit_purpose(ii.line_kind::text) as purpose
      from public.invoice_items ii
     where ii.invoice_id = p_invoice_id
       and coalesce(ii.line_total,0) > 0
     order by ii.id
  loop
    exit when v_remaining <= 0;

    -- A credit product can never be funded by wallet credit.
    if v_it.purpose in ('credit_package','premium_bundle') then continue; end if;

    -- How much of this line is still unfunded by credit.
    select round(coalesce(v_it.line_total,0) - coalesce(v_it.line_discount,0)
                 - coalesce(sum(a.amount-a.reversed_amount),0), 2)
      into v_line_open
      from public.invoice_line_credit_allocations a
     where a.invoice_item_id = v_it.id;
    if coalesce(v_line_open,0) <= 0 then continue; end if;

    v_purpose := v_it.purpose;
    v_vid := v_it.voucher_id;

    -- Bonus Credit first, then Credit Package credit (443, CREDIT-SPLIT-6),
    -- then the oldest eligible lot.
    for v_lot in
      select l.* from public.customer_credit_lots l
       where l.customer_id = v_inv.customer_id and l.status = 'active'
         and l.remaining_amount > 0
         and (p_category is null or l.category = p_category)
         and (p_source is null or public.credit_lot_source_group(l.id) = p_source)
         and public.credit_lot_snapshot_allows(l.id, l.usage_restrictions, v_purpose, v_vid)
         -- Migration 242: the source-and-category matrix. A lot may only
         -- fund a line its provenance permits.
         and public.credit_lot_line_allowed(l.id, v_it.id)
       order by (l.category = 'bonus') desc, (public.credit_lot_source_group(l.id) = 'credit_package') desc,
                l.effective_date, l.created_at
       for update
    loop
      exit when v_remaining <= 0 or v_line_open <= 0;
      v_take := least(v_lot.remaining_amount, v_line_open, v_remaining);
      if v_take <= 0 then continue; end if;

      insert into public.customer_credit_ledger (
        wallet_id, customer_id, entry_type, category, amount, lot_id,
        source_type, source_record_id, store_id, note, created_by)
      values (v_wallet, v_inv.customer_id, 'use', v_lot.category, v_take, v_lot.id,
        'invoice_payment', p_invoice_id, v_inv.store_id,
        'Invoice ' || v_inv.invoice_no, auth.uid())
      returning id into v_entry;

      update public.customer_credit_lots
         set remaining_amount = remaining_amount - v_take, updated_at = now()
       where id = v_lot.id;

      insert into public.customer_credit_allocations (ledger_entry_id, lot_id, customer_id, amount)
      values (v_entry, v_lot.id, v_inv.customer_id, v_take);

      insert into public.invoice_line_credit_allocations (
        invoice_id, invoice_item_id, lot_id, ledger_entry_id, customer_id,
        category, amount, created_by)
      values (p_invoice_id, v_it.id, v_lot.id, v_entry, v_inv.customer_id,
        v_lot.category, v_take, auth.uid());

      v_alloc := v_alloc || jsonb_build_object('invoice_item_id', v_it.id,
        'lot_id', v_lot.id, 'category', v_lot.category, 'amount', v_take);
      v_line_open := v_line_open - v_take;
      v_remaining := v_remaining - v_take;
      v_total := v_total + v_take;
    end loop;
  end loop;

  if v_remaining > 0.001 then
    raise exception 'Only % of the requested % could be funded by eligible credit', v_total, round(p_amount,2);
  end if;

  return jsonb_build_object('allocated', round(v_total,2), 'allocations', v_alloc);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.record_invoice_payment(p_invoice_id uuid, p_payments jsonb, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare i public.invoices%rowtype; x jsonb; m public.payment_methods%rowtype; v_id uuid; v_ids uuid[];
 v_all jsonb:='[]'; v_res jsonb; v_hash text:=md5(p_payments::text);
begin
 select * into i from public.invoices where id=p_invoice_id for update;
 if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 if p_request_id is null then raise exception 'Payment request ID is required'; end if;
 if exists(select 1 from public.invoice_payments where invoice_id=i.id and receipt_request_id=p_request_id) then
  if not exists(select 1 from public.invoice_payments where invoice_id=i.id and receipt_request_id=p_request_id and receipt_request_hash=v_hash) then
   raise exception 'Payment request ID was already used with different amounts'; end if;
  return jsonb_build_object('success',true,'replayed',true)||public.invoice_financial_position(i.id);
 end if;
 if i.status not in ('unpaid','draft','partially_paid') then raise exception 'Invoice is not open for payment'; end if;
 if jsonb_typeof(p_payments) is distinct from 'array' or jsonb_array_length(p_payments)=0 then raise exception 'Record at least one payment'; end if;
 for x in select * from jsonb_array_elements(p_payments) loop
  -- 416: money is kept in cents. A third decimal place was stored rounded
  -- and could leave the invoice part paid with S$0.00 owing (INVOICES-CREATE-9).
  if (x->>'amount')::numeric <> round((x->>'amount')::numeric, 2) then
   raise exception 'Payment amounts can have at most 2 decimal places.'; end if;
  select * into m from public.payment_methods where id=(x->>'payment_method_id')::uuid and is_active and deleted_at is null;
  if not found then raise exception 'Choose an active payment method'; end if;
  if nullif(x->>'payment_date','') is not null then
   if (x->>'payment_date')::date > (now() at time zone 'Asia/Singapore')::date then
    raise exception 'A payment cannot be dated in the future'; end if;
  end if;
  v_id:=gen_random_uuid();
  if m.is_wallet_credit then
   select array_agg(id) into v_ids from public.invoice_line_credit_allocations where invoice_id=i.id;
   -- 443: and from the method's source (wallet_method_source_filter).
   perform public.allocate_invoice_wallet_credit(i.id,(x->>'amount')::numeric,m.wallet_category,
     public.wallet_method_source_filter(m.wallet_category,m.wallet_source));
   update public.invoice_line_credit_allocations set payment_id=v_id where invoice_id=i.id and not(id=any(coalesce(v_ids,'{}'::uuid[])));
  end if;
  v_all:=v_all||jsonb_build_array(x||jsonb_build_object('payment_id',v_id));
 end loop;
 v_res:=public.invoice_record_payments_internal(i.id,v_all);
 if v_res->>'success' is distinct from 'true' then raise exception 'Payment could not be recorded: %',v_res; end if;
 update public.invoice_payments set receipt_request_id=p_request_id,receipt_request_hash=v_hash
   where id in(select (j.value->>'payment_id')::uuid from jsonb_array_elements(v_all) j(value));
 return v_res;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.correct_invoice_payment(p_payment_id uuid, p_amount numeric, p_date date, p_method_id uuid, p_reason text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.invoice_payments%rowtype; i public.invoices%rowtype; m public.payment_methods%rowtype;
 old_m public.payment_methods%rowtype; a record; l public.customer_credit_lots%rowtype;
 v_refunded numeric; v_reverse uuid:=gen_random_uuid(); v_replace uuid:=gen_random_uuid(); v_ids uuid[]; n numeric;
 v_old_source text; v_source text; v_used text[];
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can correct a payment'; end if;
 if nullif(trim(p_reason),'') is null or p_request_id is null then raise exception 'A payment correction reason and request ID are required'; end if;
 select * into p from public.invoice_payments where id=p_payment_id;
 if not found then raise exception 'Payment not found'; end if;
 select * into i from public.invoices where id=p.invoice_id for update;
 if not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 if exists(select 1 from public.invoice_payments where invoice_id=i.id and correction_request_id=p_request_id) then
  if not exists(select 1 from public.invoice_payments q where q.invoice_id=i.id and q.correction_request_id=p_request_id
    and q.entry_kind='correction_replacement' and q.corrects_payment_id=p.id and q.amount=round(p_amount,2)
    and q.payment_method_id=p_method_id and (q.effective_at at time zone 'Asia/Singapore')::date=p_date and q.correction_reason=p_reason) then
    raise exception 'This correction request ID was already used for different payment details'; end if;
  return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'replayed',true); end if;
 if p.entry_kind='correction_reversal' or exists(select 1 from public.invoice_payments where corrects_payment_id=p.id and entry_kind='correction_reversal') then raise exception 'Select the current replacement payment'; end if;
 if p_amount is null or p_amount<=0 or p_date is null then raise exception 'A positive corrected amount and actual payment date are required'; end if;
 -- 416: never dated after today in Singapore, as a new payment is not
 -- (INVOICES-AFTER-16), and in cents (INVOICES-CREATE-9).
 if p_date > public.sg_today() then raise exception 'A payment cannot be dated in the future'; end if;
 if p_amount <> round(p_amount, 2) then raise exception 'Payment amounts can have at most 2 decimal places.'; end if;
 select * into m from public.payment_methods where id=p_method_id and is_active and deleted_at is null;
 if not found then raise exception 'Choose an active payment method'; end if;
 select * into old_m from public.payment_methods where id=p.payment_method_id;
 -- 443 (the Owner, 21 Oct 2026): the source the payment's credit came from
 -- (wallet_method_source_filter; null: any). A payment through a Paid or
 -- Bonus method naming no source keeps the source its credit was drawn
 -- from (credit_lot_source_group of its lots, CREDIT-SPLIT-13): one taken
 -- from Premium Bundle credit before 443 through 'Wallet — Paid Credit' is
 -- corrected, through that method, from Premium Bundle credit; one that drew
 -- on several sources, from any. Corrected through another method, the
 -- payment pays from that method's source.
 v_old_source:=public.wallet_method_source_filter(old_m.wallet_category,old_m.wallet_source);
 if old_m.is_wallet_credit and v_old_source='other' then
  select array_agg(distinct public.credit_lot_source_group(a2.lot_id)) into v_used
    from public.invoice_line_credit_allocations a2 where a2.payment_id=p.id;
  if cardinality(v_used)=1 then v_old_source:=v_used[1]; elsif cardinality(v_used)>1 then v_old_source:=null; end if;
 end if;
 v_source:=case when m.id=old_m.id then v_old_source else public.wallet_method_source_filter(m.wallet_category,m.wallet_source) end;
 v_refunded:=p.amount-public.invoice_payment_remaining(p.id);
 if p_amount<v_refunded then raise exception 'Corrected payment cannot be less than refunds already issued'; end if;
 if v_refunded>0 and (m.is_wallet_credit,m.wallet_category) is distinct from (old_m.is_wallet_credit,old_m.wallet_category) then
  raise exception 'A refunded wallet payment requires source review before changing its funding category'; end if;
 if v_refunded>0 and m.is_wallet_credit and v_source is distinct from v_old_source then
  raise exception 'A refunded wallet payment requires source review before changing where its credit comes from'; end if;
 if old_m.is_wallet_credit then
  if (select coalesce(sum(amount-reversed_amount),0) from public.invoice_line_credit_allocations where payment_id=p.id)<>p.amount-v_refunded then
   raise exception 'Legacy wallet allocation is ambiguous; review exact source lots first'; end if;
  for a in select * from public.invoice_line_credit_allocations where payment_id=p.id and amount>reversed_amount order by id for update loop
   select * into l from public.customer_credit_lots where id=a.lot_id for update;
   update public.customer_credit_lots set remaining_amount=remaining_amount+a.amount-a.reversed_amount,status='active',updated_at=now() where id=l.id;
   insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,reverses_entry_id,created_by,approved_by)
    values(l.wallet_id,l.customer_id,'reverse',l.category,a.amount-a.reversed_amount,l.id,'payment_correction',p_request_id,l.store_id,p_reason,a.ledger_entry_id,auth.uid(),auth.uid());
   update public.invoice_line_credit_allocations set reversed_amount=amount where id=a.id;
  end loop;
 end if;
 -- These are bookkeeping ledger entries. Neither creates an invoice_refunds row.
 insert into public.invoice_payments(id,invoice_id,payment_method_id,amount,entry_kind,corrects_payment_id,correction_reason,correction_request_id,effective_at,received_by)
  values(v_reverse,i.id,p.payment_method_id,p.amount,'correction_reversal',p.id,p_reason,p_request_id,coalesce(p.effective_at,p.created_at),auth.uid());
 insert into public.invoice_payments(id,invoice_id,payment_method_id,amount,entry_kind,corrects_payment_id,correction_reason,correction_request_id,effective_at,received_by)
  values(v_replace,i.id,m.id,round(p_amount,2),'correction_replacement',p.id,p_reason,p_request_id,p_date::timestamp at time zone 'Asia/Singapore',auth.uid());
 if m.is_wallet_credit and p_amount>v_refunded then
  select array_agg(id) into v_ids from public.invoice_line_credit_allocations where invoice_id=i.id;
  -- Only the allocator needs a payable state. This header update does not settle
  -- or reissue benefits; the final state below restores terminal states.
  update public.invoices set status='partially_paid' where id=i.id;
  perform public.allocate_invoice_wallet_credit(i.id,p_amount-v_refunded,m.wallet_category,v_source);
  update public.invoice_line_credit_allocations set payment_id=v_replace where invoice_id=i.id and not(id=any(coalesce(v_ids,'{}'::uuid[])));
 end if;
 n:=public.invoice_net_received(i.id);
 update public.invoices set paid_amount=n,status=case when i.status in ('cancelled','refunded','cancellation_requested','refund_requested') then i.status
  when n>=public.invoice_charge_total(i.id) then 'paid'::invoice_status when n>0 then 'partially_paid'::invoice_status else 'unpaid'::invoice_status end where id=i.id;
 perform public.reconcile_invoice_commissions(i.id,'Payment correction: '||p_reason);
 perform public.write_audit_ex('invoice_payments',p.id,'payment_corrected',to_jsonb(p),jsonb_build_object('reversal',v_reverse,'replacement',v_replace,'amount',p_amount,'effective_date',p_date,'method_id',m.id),'payments',p_reason,i.store_id);
 return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'replacement_id',v_replace);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.trg_protect_system_payment_methods()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if tg_op = 'DELETE' then
    if coalesce(old.is_system,false) then
      raise exception 'System wallet payment methods cannot be deleted'; end if;
    return old;
  end if;
  if coalesce(old.is_system,false) then
    if new.deleted_at is not null then
      raise exception 'System wallet payment methods cannot be deleted'; end if;
    if new.is_wallet_credit is distinct from old.is_wallet_credit
       or new.wallet_category is distinct from old.wallet_category
       or new.is_system is distinct from old.is_system
       -- 443: nor the source a wallet method pays from (wallet_source).
       or new.wallet_source is distinct from old.wallet_source then
      raise exception 'A system wallet payment method cannot be reconfigured';
    end if;
    -- 429: nor renamed. Staff and the reports know the wallet credit types
    -- by these names (the five of 82, and since 443 one Paid and one Bonus
    -- method each for Credit Package and Premium Bundle credit).
    if new.name is distinct from old.name then
      raise exception 'A system wallet payment method cannot be renamed';
    end if;
    -- 429: nor switched off (the Owner, 10 Oct 2026). Customers spend their
    -- credit through these methods, so they are always on.
    if old.is_active and not new.is_active then
      raise exception 'A system wallet payment method cannot be switched off';
    end if;
  end if;
  return new;
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.customer_credit_balances(p_customer_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_cats jsonb; v_total numeric; v_sources jsonb; v_purchases jsonb;
begin
  if not public.can_view_customer_credit() then
    raise exception 'You do not have access to customer credit';
  end if;
  select coalesce(jsonb_object_agg(c.category, c.bal), '{}'::jsonb), coalesce(sum(c.bal),0)
    into v_cats, v_total
    from (select l.category, sum(l.remaining_amount) as bal
            from public.customer_credit_lots l
           where l.customer_id = p_customer_id and l.status = 'active'
           group by l.category) c;

  -- 443 (the Owner, 21 Oct 2026, CREDIT-SPLIT-3, 4, 12): the same credit by
  -- where it came from (credit_lot_source_group): Credit Package, Premium
  -- Bundle and Other, each by category. Moved credit counts as its origin;
  -- the 3 Legacy lots linked to Premium Bundle lines count as Premium
  -- Bundle (their category stays Legacy). The categories and the total
  -- above are as before.
  with lots as (
    select public.credit_lot_source_group(l.id) as grp, l.category, l.remaining_amount as bal
      from public.customer_credit_lots l
     where l.customer_id = p_customer_id and l.status = 'active' and l.remaining_amount <> 0)
  select jsonb_object_agg(s.grp, jsonb_build_object(
           'paid', coalesce((select sum(x.bal) from lots x where x.grp = s.grp and x.category = 'paid'), 0),
           'bonus', coalesce((select sum(x.bal) from lots x where x.grp = s.grp and x.category = 'bonus'), 0),
           'legacy', coalesce((select sum(x.bal) from lots x where x.grp = s.grp and x.category = 'legacy'), 0),
           'promotional', coalesce((select sum(x.bal) from lots x where x.grp = s.grp and x.category = 'promotional'), 0),
           'exchange', coalesce((select sum(x.bal) from lots x where x.grp = s.grp and x.category = 'exchange'), 0),
           'total', coalesce((select sum(x.bal) from lots x where x.grp = s.grp), 0)))
    into v_sources
    from unnest(array['credit_package', 'premium_bundle', 'other']) s(grp);

  -- Each Credit Package and Premium Bundle bought, with what is left of it
  -- (CREDIT-SPLIT-4, for the customer page), one used up too ('total' 0). A
  -- lot is found from its sale (credit_package_sales, premium_bundle_sales),
  -- else from the invoice line it was released for
  -- (credit_package_progress_lots), else from its package or bundle alone;
  -- moved and reassigned credit through the lot it came from. Left out: credit
  -- that went with its invoice to another customer (reassigned, 321: the
  -- purchase is theirs now), a reversed lot, and a purchase with nothing left
  -- whose invoice was cancelled or refunded (its credit was taken back).
  -- 'received': credit moved in from another customer's invoice (Move, 186).
  -- A package or bundle that has released no credit yet (not paid) has no lot
  -- and is not listed.
  with lots as (
    select l.id, l.category, l.remaining_amount as bal, public.credit_lot_source_group(l.id) as grp,
           coalesce(public.invoice_credit_transfer_origin(l.id), l.id) as origin
      from public.customer_credit_lots l
     where l.customer_id = p_customer_id and l.status = 'active'
       and not exists (select 1 from public.customer_credit_lots y where y.reassigned_from_lot_id = l.id)),
  chained as (
    select x.*, array(with recursive back(id, depth) as (
                        select x.origin, 0
                        union all
                        select y.reassigned_from_lot_id, b.depth + 1
                          from back b join public.customer_credit_lots y on y.id = b.id
                         where y.reassigned_from_lot_id is not null and b.depth < 12)
                      select back.id from back order by back.depth) as chain
      from lots x where x.grp in ('credit_package', 'premium_bundle')),
  bought as (
    select c.id, c.category, c.bal, c.grp,
           coalesce(
             (select jsonb_build_object('key', 'cps:' || s.id, 'name', s.package_name_snapshot,
                                        'invoice_id', s.invoice_id, 'at', s.sold_at)
                from public.credit_package_sales s
               where c.grp = 'credit_package' and (s.credit_lot_id = any (c.chain) or s.bonus_credit_lot_id = any (c.chain))
               order by s.sold_at, s.id limit 1),
             (select jsonb_build_object('key', 'pbs:' || b.id, 'name', b.bundle_name_snapshot,
                                        'invoice_id', b.invoice_id, 'at', b.sold_at)
                from public.premium_bundle_sales b
               where c.grp = 'premium_bundle' and (b.paid_credit_lot_id = any (c.chain) or b.bonus_credit_lot_id = any (c.chain))
               order by b.sold_at, b.id limit 1),
             (select jsonb_build_object(
                       'key', coalesce('cps:' || s.id, 'pbs:' || b.id, 'line:' || ii.id),
                       'name', coalesce(s.package_name_snapshot, b.bundle_name_snapshot,
                                        nullif(btrim(ii.plan_name_snapshot), ''), nullif(btrim(ii.item_name_snapshot), '')),
                       'invoice_id', pl.invoice_id, 'at', coalesce(s.sold_at, b.sold_at, iv.created_at))
                from public.credit_package_progress_lots pl
                join public.invoice_items ii on ii.id = pl.invoice_item_id
                join public.invoices iv on iv.id = pl.invoice_id
                left join public.credit_package_sales s on s.invoice_item_id = ii.id and ii.line_kind::text = 'credit_package'
                left join public.premium_bundle_sales b on b.invoice_item_id = ii.id and ii.line_kind::text = 'premium_bundle'
               where pl.lot_id = any (c.chain) and ii.line_kind::text = c.grp
               order by array_position(c.chain, pl.lot_id), pl.created_at limit 1),
             (select jsonb_build_object('key', 'catalogue:' || r.source_record_id,
                                        'name', coalesce(cp.name, pb.name), 'invoice_id', null, 'at', null)
                from public.customer_credit_lots r
                left join public.credit_packages cp on cp.id = r.source_record_id and r.source_type = 'credit_package'
                left join public.premium_bundles pb on pb.id = r.source_record_id and r.source_type = 'premium_bundle'
               where r.id = c.chain[cardinality(c.chain)] and r.source_type = c.grp),
             jsonb_build_object('key', 'unknown:' || c.grp, 'name', null, 'invoice_id', null, 'at', null)) as buy
      from chained c)
  select coalesce(jsonb_agg(p.row order by p.rank, p.at nulls last, p.name nulls last, p.key), '[]'::jsonb)
    into v_purchases
    from (select case b.grp when 'credit_package' then 0 else 1 end as rank, b.buy->>'key' as key,
                 min((b.buy->>'at')::timestamptz) as at, min(b.buy->>'name') as name,
                 jsonb_build_object(
                   'source', b.grp,
                   'name', min(b.buy->>'name'),
                   'invoice_id', min(b.buy->>'invoice_id'),
                   'invoice_no', (select i.invoice_no from public.invoices i where i.id::text = min(b.buy->>'invoice_id')),
                   'bought_on', (min((b.buy->>'at')::timestamptz) at time zone 'Asia/Singapore')::date,
                   'received', coalesce((select i.customer_id is distinct from p_customer_id
                                           from public.invoices i where i.id::text = min(b.buy->>'invoice_id')), false),
                   'paid', coalesce(sum(b.bal) filter (where b.category = 'paid'), 0),
                   'bonus', coalesce(sum(b.bal) filter (where b.category = 'bonus'), 0),
                   'legacy', coalesce(sum(b.bal) filter (where b.category = 'legacy'), 0),
                   'total', sum(b.bal)) as row
            from bought b
           group by b.grp, b.buy->>'key'
          having sum(b.bal) > 0
              or not exists (select 1 from public.invoices i where i.id::text = min(b.buy->>'invoice_id')
                                and i.status::text in ('cancelled', 'refunded'))) p;

  return jsonb_build_object(
    'customer_id', p_customer_id,
    'categories', jsonb_build_object(
      'paid', coalesce((v_cats->>'paid')::numeric, 0),
      'bonus', coalesce((v_cats->>'bonus')::numeric, 0),
      'legacy', coalesce((v_cats->>'legacy')::numeric, 0),
      'promotional', coalesce((v_cats->>'promotional')::numeric, 0),
      'exchange', coalesce((v_cats->>'exchange')::numeric, 0)),
    'available_total', coalesce(v_total,0),
    'sources', v_sources,
    'purchases', v_purchases);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.invoice_wallet_availability(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_inv public.invoices%rowtype; m record; v_it record; v_lot record;
  v_payable boolean; v_credit_line boolean; v_open numeric; v_take numeric; v_used jsonb;
  v_avail numeric; v_held numeric; v_out jsonb := '[]'::jsonb; v_default uuid;
begin
  -- 443 (the Owner, 21 Oct 2026, CREDIT-SPLIT-5..8): for Record Payment, each
  -- wallet payment method on, with the credit it could pay of THIS invoice
  -- now ('available'), and what of its category and source the customer holds
  -- at all ('held'). 'available' is what allocate_invoice_wallet_credit would
  -- draw if asked for everything: the same lines, lots, rules
  -- (credit_lot_snapshot_allows, credit_lot_line_allowed) and order, each
  -- method on its own; nothing is written or locked. Methods are listed
  -- Credit Package first, then Premium Bundle, then the rest (CREDIT-SPLIT-6);
  -- 'default_method_id' is the first that can pay anything.
  perform public.require_active_staff();
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found or not public.user_has_store_access(v_inv.store_id) then
    raise exception 'Invoice not accessible'; end if;
  if not public.can_view_customer_credit() then
    raise exception 'You do not have access to customer credit'; end if;
  v_payable := v_inv.customer_id is not null and v_inv.status in ('draft', 'unpaid', 'partially_paid');
  -- Wallet credit never pays an invoice that sells credit (81).
  v_credit_line := exists (select 1 from public.invoice_items ii where ii.invoice_id = v_inv.id
                             and public.invoice_line_credit_purpose(ii.line_kind::text) in ('credit_package', 'premium_bundle'));
  for m in
    select pm.id, pm.name, pm.wallet_category, pm.wallet_source,
           public.wallet_method_source_filter(pm.wallet_category, pm.wallet_source) as pays_from,
           row_number() over (order by case pm.wallet_source when 'credit_package' then 0 when 'premium_bundle' then 1 else 2 end,
                                       coalesce(array_position(array['paid', 'bonus', 'legacy', 'promotional', 'exchange'], pm.wallet_category), 6),
                                       pm.name, pm.id) as rank
      from public.payment_methods pm
     where pm.is_wallet_credit and pm.is_active and pm.deleted_at is null
     order by rank
  loop
    v_held := 0; v_avail := 0;
    if v_inv.customer_id is not null then
      select coalesce(sum(l.remaining_amount), 0) into v_held
        from public.customer_credit_lots l
       where l.customer_id = v_inv.customer_id and l.status = 'active' and l.remaining_amount > 0
         and (m.wallet_category is null or l.category = m.wallet_category)
         and (m.pays_from is null or public.credit_lot_source_group(l.id) = m.pays_from);
    end if;
    if v_payable and not v_credit_line and v_held > 0 then
      -- What each lot has given in this reckoning (lot id -> amount).
      v_used := '{}'::jsonb;
      for v_it in
        select ii.*, public.invoice_line_credit_purpose(ii.line_kind::text) as purpose
          from public.invoice_items ii
         where ii.invoice_id = v_inv.id and coalesce(ii.line_total, 0) > 0
         order by ii.id
      loop
        if v_it.purpose in ('credit_package', 'premium_bundle') then continue; end if;
        select round(coalesce(v_it.line_total, 0) - coalesce(v_it.line_discount, 0)
                     - coalesce(sum(a.amount - a.reversed_amount), 0), 2)
          into v_open
          from public.invoice_line_credit_allocations a
         where a.invoice_item_id = v_it.id;
        if coalesce(v_open, 0) <= 0 then continue; end if;
        for v_lot in
          select l.id, l.remaining_amount from public.customer_credit_lots l
           where l.customer_id = v_inv.customer_id and l.status = 'active'
             and l.remaining_amount > 0
             and (m.wallet_category is null or l.category = m.wallet_category)
             and (m.pays_from is null or public.credit_lot_source_group(l.id) = m.pays_from)
             and public.credit_lot_snapshot_allows(l.id, l.usage_restrictions, v_it.purpose, v_it.voucher_id)
             and public.credit_lot_line_allowed(l.id, v_it.id)
           order by (l.category = 'bonus') desc, (public.credit_lot_source_group(l.id) = 'credit_package') desc,
                    l.effective_date, l.created_at
        loop
          exit when v_open <= 0;
          v_take := least(v_lot.remaining_amount - coalesce((v_used ->> v_lot.id::text)::numeric, 0), v_open);
          if v_take <= 0 then continue; end if;
          v_used := v_used || jsonb_build_object(v_lot.id::text, coalesce((v_used ->> v_lot.id::text)::numeric, 0) + v_take);
          v_open := v_open - v_take;
          v_avail := v_avail + v_take;
        end loop;
      end loop;
    end if;
    if v_default is null and v_avail > 0 then v_default := m.id; end if;
    v_out := v_out || jsonb_build_object(
      'payment_method_id', m.id, 'name', m.name, 'wallet_category', m.wallet_category,
      'wallet_source', m.wallet_source, 'pays_from', coalesce(m.pays_from, 'any'),
      'available', round(v_avail, 2), 'held', round(v_held, 2), 'rank', m.rank);
  end loop;
  return jsonb_build_object('invoice_id', v_inv.id, 'customer_id', v_inv.customer_id,
    'payable', v_payable and not v_credit_line, 'credit_line', v_credit_line,
    'default_method_id', v_default, 'methods', v_out);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.invoice_payment_credit_sources(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_inv public.invoices%rowtype;
begin
  -- 443 (the Owner, 21 Oct 2026, CREDIT-SPLIT-13): for each wallet payment of
  -- the invoice, the sources its credit came from (credit_lot_source_group of
  -- the lots it drew on, invoice_line_credit_allocations), so the invoice can
  -- show a past payment as, say, 'Wallet — Paid Credit (Premium Bundle)'. A
  -- correction's reversal row answers for the payment it reverses. Nothing
  -- is changed; a payment that drew on no lot is left out.
  perform public.require_active_staff();
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return '{}'::jsonb; end if;
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'Invoice not accessible'; end if;
  return coalesce((
    select jsonb_object_agg(p.id::text, s.groups)
      from public.invoice_payments p
      join public.payment_methods m on m.id = p.payment_method_id and m.is_wallet_credit
      cross join lateral (
        select jsonb_agg(g.grp order by case g.grp when 'credit_package' then 0 when 'premium_bundle' then 1 else 2 end) as groups
          from (select distinct public.credit_lot_source_group(a.lot_id) as grp
                  from public.invoice_line_credit_allocations a
                 where a.payment_id = case when p.entry_kind = 'correction_reversal' then p.corrects_payment_id else p.id end) g
         where g.grp is not null) s
     where p.invoice_id = v_inv.id and s.groups is not null), '{}'::jsonb);
end $function$
$def$];
  -- The allocator's signature before 443, which the four-argument one
  -- replaces (dropped; no overload is left).
  c_old_sig constant text := 'allocate_invoice_wallet_credit(uuid,numeric,text)';
  c_old_md5 constant text := 'c19614b318e5d071cdac381517e63df8';
  -- Who may call the allocator: the server alone (as before 443).
  c_alloc_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';
  -- Besides this file's own, the functions whose text names the allocator,
  -- as read: consume_customer_credit, in a comment (the two that call it,
  -- record_invoice_payment and correct_invoice_payment, are this file's).
  c_alloc_callers constant text[] := array['consume_customer_credit(uuid,numeric,text,uuid,uuid,text,text,text,uuid)'];
  -- Besides this file's own, the functions whose text names
  -- customer_credit_balances, as read (it keeps 'categories' and
  -- 'available_total' as they were).
  c_bal_readers constant text[] := array['issue_customer_credit_statement(uuid,date,date)'];

  -- ── Relied on, not changed (production, 21 Oct 2026, after 442) ──────────
  c_relied constant text[] := array[
    'invoice_credit_transfer_origin(uuid)', 'credit_lot_snapshot_allows(uuid,jsonb,text,uuid)',
    'credit_lot_line_allowed(uuid,uuid)', 'invoice_line_credit_purpose(text)', 'ensure_customer_wallet(uuid)',
    'can_view_customer_credit()', 'user_has_store_access(uuid)', 'require_active_staff(text[])',
    'invoice_record_payments_internal(uuid,jsonb)', 'invoice_financial_position(uuid)', 'is_owner_or_manager()',
    'sg_today()', 'invoice_payment_remaining(uuid)', 'invoice_net_received(uuid)', 'invoice_charge_total(uuid)',
    'reconcile_invoice_commissions(uuid,text)', 'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'grant_customer_credit(uuid,text,numeric,text,uuid,uuid,date,text,text,text,date,uuid,jsonb)'];
  c_relied_md5 constant text[] := array[
    'e778a9e4ff81567a493b8ca479d8222b', '1d78a592687366f98b52adcb655c51fb',
    '7d81252612104b1012b6d78513092091', 'ff61d218e5bd8f272885216e23c0a1a6', '8ef18daebbbe3c12f2024290ea8416e8',
    '347f20fdfcbe7e2666f9d6995bb53647', '708992afaa6c3951f6329239b742987c', '877b3aa74cea559881979bb161c450e2',
    '21890d84bcb0b9c00a2bc98aff313d0b', 'ba7eccbfeff217c8b1969b0e55a010ca', 'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    '1c1289f18e24d8370e9a6364c9c06fca', 'aad3ba468c8d7ddec8791e172d6ac16f', 'f256bea69b7defa38a950753bbc248da',
    '8297147511ba285db2279598f3d727fb', '3c267728e215d17ebeb9cfe9cb7db47c', 'c705c733e213a27f0dc32d54322cc855',
    'ac0de5530624ee533aacf93aec389910'];

  -- ── The wallet methods: the four this adds (CREDIT-SPLIT-10) and the five
  -- of 82, kept as they are (CREDIT-SPLIT-9) ────────────────────────────────
  c_new_name constant text[] := array['Wallet — Credit Package Paid', 'Wallet — Credit Package Bonus',
                                      'Wallet — Premium Bundle Paid', 'Wallet — Premium Bundle Bonus'];
  c_new_cat constant text[] := array['paid', 'bonus', 'paid', 'bonus'];
  c_new_src constant text[] := array['credit_package', 'credit_package', 'premium_bundle', 'premium_bundle'];
  c_old_name constant text[] := array['Wallet — Paid Credit', 'Wallet — Bonus Credit', 'Wallet — Legacy Credit',
                                      'Wallet — Promotional/FOC Credit', 'Wallet — Exchange Credit'];
  c_old_cat constant text[] := array['paid', 'bonus', 'legacy', 'promotional', 'exchange'];
  c_source_check constant text := 'CHECK (((wallet_source IS NULL) OR ((wallet_source = ANY (ARRAY[''credit_package''::text, ''premium_bundle''::text])) AND is_wallet_credit AND (wallet_category = ANY (ARRAY[''paid''::text, ''bonus''::text])) AND is_system)))';
  c_category_check constant text := 'CHECK (((wallet_category IS NULL) OR (wallet_category = ANY (ARRAY[''paid''::text, ''bonus''::text, ''legacy''::text, ''promotional''::text, ''exchange''::text]))))';
  c_trigger constant text := 'CREATE TRIGGER protect_system_payment_methods BEFORE DELETE OR UPDATE ON public.payment_methods FOR EACH ROW EXECUTE FUNCTION trg_protect_system_payment_methods()';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v_acls text[] := '{}'::text[]; v_names text[]; v text; d text; i int; n int; v_has_col boolean;
  v_changed boolean := false;
  -- the self-test's made-up records
  t_sfx text; t_phone text; t_owner uuid; t_store uuid; t_cust uuid; t_prod uuid; t_pk uuid; t_pb uuid;
  t_any uuid; t_inv uuid; t_ans jsonb; t_err text; t_pays uuid[];
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- Each text is the tested one.
  for i in 1 .. cardinality(c_sig) loop
    if md5(c_def[i]) <> c_after[i] then
      raise exception '443: the text of public.% is not the tested one (md5 %)', c_sig[i], md5(c_def[i]); end if;
  end loop;

  -- Each changed function is its BEFORE (production, 21 Oct 2026) or this
  -- file's AFTER (left alone); each new one is missing or the AFTER.
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then
      if c_before[i] is not null then raise exception '443: public.% is missing', c_sig[i]; end if;
    else
      d := md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i])));
      if d <> c_after[i] and d is distinct from c_before[i] then
        raise exception '443: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', c_sig[i], d;
      end if;
    end if;
  end loop;
  -- The allocator before 443: production's, or gone (this file ran before).
  if to_regprocedure('public.' || c_old_sig) is not null
     and md5(pg_get_functiondef(to_regprocedure('public.' || c_old_sig))) <> c_old_md5 then
    raise exception '443: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.',
      c_old_sig, md5(pg_get_functiondef(to_regprocedure('public.' || c_old_sig))); end if;
  if to_regprocedure('public.' || c_old_sig) is null
     and md5(pg_get_functiondef(to_regprocedure('public.allocate_invoice_wallet_credit(uuid,numeric,text,text)'))) is distinct from c_after[3] then
    raise exception '443: public.% is missing, and this file''s allocator is not there either', c_old_sig; end if;
  -- No other function takes one of these names (the old allocator apart).
  v_names := array(select split_part(s, '(', 1) from unnest(c_sig) s);
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = any (v_names)
     and p.oid::regprocedure::text <> all (c_sig) and p.oid::regprocedure::text <> c_old_sig;
  if v is not null then raise exception '443: another function takes one of these names: %', v; end if;

  -- The functions relied on are as read on production (21 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '443: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if to_regprocedure('auth.uid()') is null or to_regprocedure('auth.role()') is null then
    raise exception '443: auth.uid() and auth.role() must be there'; end if;

  -- Nothing else calls the allocator, so its new argument needs no other
  -- caller changed; nothing else reads customer_credit_balances. (A
  -- session's own temporary functions, a test suite's helpers, are not
  -- counted.)
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc like '%allocate_invoice_wallet_credit%' and ns.nspname not like 'pg\_temp\_%'
     and not (p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = any (c_sig || c_old_sig));
  if v is distinct from array_to_string(c_alloc_callers, ', ') then
    raise exception '443: the functions that name allocate_invoice_wallet_credit are not as read on 21 Oct 2026 (%); check each, then re-test', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc like '%customer_credit_balances%' and ns.nspname not like 'pg\_temp\_%'
     and not (p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = any (c_sig));
  if v is distinct from array_to_string(c_bal_readers, ', ') then
    raise exception '443: the functions that read customer_credit_balances are not as read on 21 Oct 2026 (%); check each, then re-test', v; end if;

  -- The columns read and written, as read on 21 Oct 2026.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values
      ('payment_methods', 'id', 'uuid'), ('payment_methods', 'name', 'text'), ('payment_methods', 'is_active', 'boolean'),
      ('payment_methods', 'deleted_at', 'timestamp with time zone'), ('payment_methods', 'is_wallet_credit', 'boolean'),
      ('payment_methods', 'wallet_category', 'text'), ('payment_methods', 'is_system', 'boolean'),
      ('customer_credit_lots', 'id', 'uuid'), ('customer_credit_lots', 'customer_id', 'uuid'),
      ('customer_credit_lots', 'category', 'text'), ('customer_credit_lots', 'remaining_amount', 'numeric(12,2)'),
      ('customer_credit_lots', 'status', 'text'), ('customer_credit_lots', 'source_type', 'text'),
      ('customer_credit_lots', 'source_record_id', 'uuid'), ('customer_credit_lots', 'reassigned_from_lot_id', 'uuid'),
      ('customer_credit_lots', 'usage_restrictions', 'jsonb'), ('customer_credit_lots', 'effective_date', 'date'),
      ('customer_credit_lots', 'created_at', 'timestamp with time zone'),
      ('credit_package_progress_lots', 'lot_id', 'uuid'), ('credit_package_progress_lots', 'invoice_item_id', 'uuid'),
      ('credit_package_progress_lots', 'invoice_id', 'uuid'), ('credit_package_progress_lots', 'created_at', 'timestamp with time zone'),
      ('invoice_items', 'id', 'uuid'), ('invoice_items', 'invoice_id', 'uuid'), ('invoice_items', 'line_kind', 'invoice_line_kind'),
      ('invoice_items', 'line_total', 'numeric(12,2)'), ('invoice_items', 'line_discount', 'numeric(12,2)'),
      ('invoice_items', 'voucher_id', 'uuid'), ('invoice_items', 'plan_name_snapshot', 'text'), ('invoice_items', 'item_name_snapshot', 'text'),
      ('invoice_line_credit_allocations', 'invoice_item_id', 'uuid'), ('invoice_line_credit_allocations', 'lot_id', 'uuid'),
      ('invoice_line_credit_allocations', 'payment_id', 'uuid'), ('invoice_line_credit_allocations', 'amount', 'numeric(12,2)'),
      ('invoice_line_credit_allocations', 'reversed_amount', 'numeric(12,2)'),
      ('invoice_payments', 'id', 'uuid'), ('invoice_payments', 'invoice_id', 'uuid'), ('invoice_payments', 'payment_method_id', 'uuid'),
      ('invoice_payments', 'entry_kind', 'text'), ('invoice_payments', 'corrects_payment_id', 'uuid'),
      ('credit_package_sales', 'id', 'uuid'), ('credit_package_sales', 'invoice_id', 'uuid'), ('credit_package_sales', 'invoice_item_id', 'uuid'),
      ('credit_package_sales', 'credit_lot_id', 'uuid'), ('credit_package_sales', 'bonus_credit_lot_id', 'uuid'),
      ('credit_package_sales', 'package_name_snapshot', 'text'), ('credit_package_sales', 'sold_at', 'timestamp with time zone'),
      ('premium_bundle_sales', 'id', 'uuid'), ('premium_bundle_sales', 'invoice_id', 'uuid'), ('premium_bundle_sales', 'invoice_item_id', 'uuid'),
      ('premium_bundle_sales', 'paid_credit_lot_id', 'uuid'), ('premium_bundle_sales', 'bonus_credit_lot_id', 'uuid'),
      ('premium_bundle_sales', 'bundle_name_snapshot', 'text'), ('premium_bundle_sales', 'sold_at', 'timestamp with time zone'),
      ('credit_packages', 'name', 'text'), ('premium_bundles', 'name', 'text'),
      ('invoices', 'invoice_no', 'text'), ('invoices', 'created_at', 'timestamp with time zone'),
      ('invoices', 'customer_id', 'uuid'), ('invoices', 'store_id', 'uuid'), ('invoices', 'status', 'invoice_status')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '443: these columns are missing or not as read on 21 Oct 2026: %', v; end if;

  -- payment_methods: its category check and its protecting trigger as read;
  -- wallet_source missing, or exactly this file's column and check.
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'public.payment_methods'::regclass and c.conname = 'payment_methods_wallet_category_check')
     is distinct from c_category_check then
    raise exception '443: payment_methods'' wallet category check is not as read on 21 Oct 2026'; end if;
  if (select string_agg(pg_get_triggerdef(t.oid), ' | ') from pg_trigger t
       where t.tgrelid = 'public.payment_methods'::regclass and not t.tgisinternal) is distinct from c_trigger then
    raise exception '443: the triggers on payment_methods are not as read on 21 Oct 2026'; end if;
  select c.data_type || ' ' || c.is_nullable || ' ' || coalesce(c.column_default, '') into v
    from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'payment_methods' and c.column_name = 'wallet_source';
  v_has_col := v is not null;
  if v_has_col and (v <> 'text YES '
       or (select pg_get_constraintdef(c.oid) from pg_constraint c
            where c.conrelid = 'public.payment_methods'::regclass and c.conname = 'payment_methods_wallet_source_check')
          is distinct from c_source_check) then
    raise exception '443: payment_methods.wallet_source exists and is not this migration''s column (%)', v; end if;
  if not v_has_col and exists (select 1 from pg_constraint c where c.conrelid = 'public.payment_methods'::regclass
                                  and c.conname = 'payment_methods_wallet_source_check') then
    raise exception '443: payment_methods has a constraint payment_methods_wallet_source_check but no wallet_source'; end if;

  -- The four names: free among live methods, or already this file's methods.
  for i in 1 .. cardinality(c_new_name) loop
    if exists (select 1 from public.payment_methods m
                where m.deleted_at is null and lower(btrim(m.name)) = lower(btrim(c_new_name[i]))
                  and not (m.name = c_new_name[i] and m.is_system and m.is_wallet_credit and m.wallet_category = c_new_cat[i]
                           and v_has_col and (to_jsonb(m) ->> 'wallet_source') = c_new_src[i])) then
      raise exception '443: a live payment method is already called "%"; rename or delete it, then re-run', c_new_name[i]; end if;
  end loop;
  -- The five of 82, where they are (production has all five): system wallet
  -- methods of their category, naming no source.
  for i in 1 .. cardinality(c_old_name) loop
    if exists (select 1 from public.payment_methods m
                where m.deleted_at is null and m.name = c_old_name[i]
                  and not (m.is_system and m.is_wallet_credit and m.wallet_category = c_old_cat[i]
                           and (to_jsonb(m) ->> 'wallet_source') is null)) then
      raise exception '443: the payment method "%" is not as read on 21 Oct 2026 (a system wallet method of category %, naming no source)',
        c_old_name[i], c_old_cat[i]; end if;
    if not exists (select 1 from public.payment_methods m where m.deleted_at is null and m.name = c_old_name[i]) then
      raise notice '443: there is no live payment method "%" here (production has it); nothing is done about it', c_old_name[i]; end if;
  end loop;

  -- What may call each function now (a changed one keeps it).
  for i in 1 .. cardinality(c_sig) loop
    v_acls := v_acls || (select coalesce(proacl::text, '') from pg_proc where oid = to_regprocedure('public.' || c_sig[i]));
  end loop;
  if to_regprocedure('public.' || c_old_sig) is not null
     and (select coalesce(proacl::text, '') from pg_proc where oid = to_regprocedure('public.' || c_old_sig)) <> c_alloc_acl then
    raise exception '443: who may call public.% is not as read on 21 Oct 2026', c_old_sig; end if;

  -- ── Changes ─────────────────────────────────────────────────────────────
  -- The source a wallet method pays from (CREDIT-SPLIT-5): null, or a Credit
  -- Package's or a Premium Bundle's credit, on a system Paid or Bonus
  -- wallet method only.
  if not v_has_col then
    v_changed := true;
    alter table public.payment_methods add column wallet_source text;
    alter table public.payment_methods add constraint payment_methods_wallet_source_check
      check (wallet_source is null or (wallet_source in ('credit_package', 'premium_bundle')
                                       and is_wallet_credit and wallet_category in ('paid', 'bonus') and is_system));
  end if;
  comment on column public.payment_methods.wallet_source is
    '443: the source a wallet method pays from: credit_package or premium_bundle (credit_lot_source_group), on the four '
    'system methods Wallet — Credit Package Paid/Bonus and Wallet — Premium Bundle Paid/Bonus. Null: the Paid and Bonus '
    'methods pay other credit only (opening balances, Adjust), the rest any source (wallet_method_source_filter).';

  -- The functions, each left alone when it is already this version. The
  -- helpers first; the allocator replaces its three-argument self.
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      execute c_def[i];
      v_changed := true;
    end if;
    if c_before[i] is null then
      if c_client[i] then
        execute format('revoke all on function public.%s from public, anon', c_sig[i]);
        execute format('grant execute on function public.%s to authenticated, service_role', c_sig[i]);
      else
        execute format('revoke all on function public.%s from public, anon, authenticated', c_sig[i]);
        execute format('grant execute on function public.%s to service_role', c_sig[i]);
      end if;
    end if;
  end loop;
  if to_regprocedure('public.' || c_old_sig) is not null then
    execute format('drop function public.%s', c_old_sig);
    v_changed := true;
  end if;

  -- The four methods (CREDIT-SPLIT-10), system and on like the five.
  for i in 1 .. cardinality(c_new_name) loop
    if not exists (select 1 from public.payment_methods m where m.deleted_at is null and m.name = c_new_name[i]) then
      insert into public.payment_methods (name, is_active, is_wallet_credit, wallet_category, wallet_source, is_system)
      values (c_new_name[i], true, true, c_new_cat[i], c_new_src[i], true);
      v_changed := true;
    end if;
  end loop;
  if not v_changed then raise notice '443: already this version; left alone'; end if;

  -- ── Afterwards ──────────────────────────────────────────────────────────
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '443: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if c_before[i] is not null then
      if (select coalesce(proacl::text, '') from pg_proc where oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acls[i] then
        raise exception '443: the grants of public.% changed', c_sig[i]; end if;
    elsif has_function_privilege('anon', to_regprocedure('public.' || c_sig[i]), 'execute')
       or has_function_privilege('authenticated', to_regprocedure('public.' || c_sig[i]), 'execute') <> c_client[i]
       or not has_function_privilege('service_role', to_regprocedure('public.' || c_sig[i]), 'execute') then
      raise exception '443: public.% is not callable by exactly whom it is for', c_sig[i];
    end if;
  end loop;
  if (select coalesce(proacl::text, '') from pg_proc where oid = to_regprocedure('public.' || c_sig[3])) <> c_alloc_acl then
    raise exception '443: public.% is not the server''s alone, as the allocator was', c_sig[3]; end if;
  if to_regprocedure('public.' || c_old_sig) is not null
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'allocate_invoice_wallet_credit') <> 1 then
    raise exception '443: the three-argument allocator is still there'; end if;
  if (select count(*) from public.payment_methods m
       where m.deleted_at is null and m.is_system and m.is_active and m.is_wallet_credit
         and (m.name, m.wallet_category, m.wallet_source) in (select * from unnest(c_new_name, c_new_cat, c_new_src))) <> 4 then
    raise exception '443: the four wallet methods per source are not all there, system and on'; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("443 check", @example.invalid, a fictional phone
  -- no customer uses); it ends by raising P0443, which undoes all it wrote.
  -- No therapy line is sold, so no therapy number is used.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    select p into t_phone
      from unnest(array['+61491570870', '+61491570871', '+61491570872', '+61491570873', '+61491570874']) p
     where not exists (select 1 from public.customers c where c.phone = p)
     limit 1;
    if t_phone is null then raise exception '443: the self-test found no unused fictional phone'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '443-check-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '443 check', '443-check-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('443 check ' || t_sfx, '443-' || t_sfx, 'SG') returning id into t_store;
    insert into public.customers (full_name, phone) values ('443 Check ' || t_sfx, t_phone) returning id into t_cust;
    insert into public.products (name, sku, product_type) values ('443 check ' || t_sfx, '443-' || t_sfx, 'own') returning id into t_prod;
    insert into public.store_inventory (store_id, product_id, current_qty) values (t_store, t_prod, 5);
    perform public.set_product_prices(t_store, t_prod, 40, 40, 'available');
    insert into public.credit_packages (name, customer_price, paid_credit_amount) values ('443 check ' || t_sfx, 100, 100) returning id into t_pk;
    insert into public.premium_bundles (name, customer_payment_amount) values ('443 check ' || t_sfx, 100) returning id into t_pb;
    -- Package Paid 50 and Bonus 30, bundle Paid 40, an opening balance Paid 7.
    perform public.grant_customer_credit(t_cust, 'paid', 50, 'credit_package', t_pk, t_store);
    perform public.grant_customer_credit(t_cust, 'bonus', 30, 'credit_package', t_pk, t_store);
    perform public.grant_customer_credit(t_cust, 'paid', 40, 'premium_bundle', t_pb, t_store);
    perform public.grant_customer_credit(t_cust, 'paid', 7, 'manual_legacy', null, t_store);
    -- A Paid wallet method naming no source, as 'Wallet — Paid Credit' is.
    insert into public.payment_methods (name, is_wallet_credit, wallet_category)
    values ('443 check paid ' || t_sfx, true, 'paid') returning id into t_any;
    t_inv := public.create_invoice(t_store, t_cust, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', t_prod, 'quantity', 1)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    -- What each can pay of a product of 40: Credit Package Paid (therapy
    -- sessions) none of it; the default is Credit Package Bonus.
    t_ans := public.invoice_wallet_availability(t_inv);
    if (select string_agg(x ->> 'name' || '=' || trim_scale((x ->> 'available')::numeric) || '/' || trim_scale((x ->> 'held')::numeric),
                          '; ' order by (x ->> 'rank')::int)
          from jsonb_array_elements(t_ans -> 'methods') x where x ->> 'name' = any (c_new_name) or x ->> 'name' like '443 check%')
         is distinct from 'Wallet — Credit Package Paid=0/50; Wallet — Credit Package Bonus=30/30; Wallet — Premium Bundle Paid=40/40; '
                          || 'Wallet — Premium Bundle Bonus=0/0; 443 check paid ' || t_sfx || '=7/7'
       or (t_ans ->> 'default_method_id') is distinct from
          (select m.id::text from public.payment_methods m where m.name = 'Wallet — Credit Package Bonus' and m.deleted_at is null) then
      raise exception '443: the self-test''s available credit is not as tested: %', t_ans; end if;
    -- One Record Payment from both sources: two payment rows, each from its own.
    perform public.record_invoice_payment(t_inv, jsonb_build_array(
      jsonb_build_object('payment_method_id', (select m.id from public.payment_methods m where m.name = 'Wallet — Credit Package Bonus' and m.deleted_at is null), 'amount', 10),
      jsonb_build_object('payment_method_id', (select m.id from public.payment_methods m where m.name = 'Wallet — Premium Bundle Paid' and m.deleted_at is null), 'amount', 10)),
      gen_random_uuid());
    t_pays := array(select p.id from public.invoice_payments p where p.invoice_id = t_inv order by p.id);
    t_ans := public.invoice_payment_credit_sources(t_inv);
    if cardinality(t_pays) <> 2
       or (select string_agg(t_ans ->> p::text, ',' order by t_ans ->> p::text) from unnest(t_pays) p)
          is distinct from '["credit_package"],["premium_bundle"]'
       or (select string_agg(l.category || ':' || public.credit_lot_source_group(l.id), ',' order by l.category)
             from public.invoice_line_credit_allocations a join public.customer_credit_lots l on l.id = a.lot_id
            where a.invoice_id = t_inv) is distinct from 'bonus:credit_package,paid:premium_bundle' then
      raise exception '443: the self-test''s two sources were not paid as two rows, each from its own: %', t_ans; end if;
    -- A Paid method naming no source pays other credit alone: 7 of it, not 7.01.
    begin
      perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_any, 'amount', 7.01)), gen_random_uuid());
      t_err := 'accepted';
    exception when others then t_err := sqlerrm;
    end;
    if t_err not like 'Only 7.00 of the requested 7.01 could be funded by eligible credit%' then
      raise exception '443: the self-test''s Paid method naming no source reached package or bundle credit: %', t_err; end if;
    -- The balance by source; the categories as before.
    t_ans := public.customer_credit_balances(t_cust);
    if (t_ans -> 'categories' ->> 'paid')::numeric <> 87 or (t_ans -> 'categories' ->> 'bonus')::numeric <> 20
       or (t_ans -> 'sources' -> 'credit_package' ->> 'total')::numeric <> 70
       or (t_ans -> 'sources' -> 'premium_bundle' ->> 'paid')::numeric <> 30
       or (t_ans -> 'sources' -> 'other' ->> 'paid')::numeric <> 7
       or jsonb_array_length(t_ans -> 'purchases') <> 2 then
      raise exception '443: the self-test''s balance by source is not as tested: %', t_ans; end if;
    -- The new methods are protected like the five.
    begin
      update public.payment_methods set name = name || ' x' where name = 'Wallet — Premium Bundle Bonus' and deleted_at is null;
      t_err := 'renamed';
    exception when others then t_err := sqlerrm;
    end;
    if t_err is distinct from 'A system wallet payment method cannot be renamed' then
      raise exception '443: the self-test renamed a new wallet method: %', t_err; end if;
    raise exception using errcode = 'P0443', message = '443: self-test done, undone';
  exception when sqlstate 'P0443' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
