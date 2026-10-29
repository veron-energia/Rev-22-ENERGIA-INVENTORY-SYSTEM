-- 478_reopen_dialog_credit_released_at_once.sql
--
-- THE REOPEN DIALOG SAYS WHAT THE REOPENING AND THE PAYMENT THAT SETTLES IT
-- GIVE, AND TO WHOM: THE CREDIT A PACKAGE OR BUNDLE PAID IN PART GETS BACK AT
-- ONCE (ITS OWN FIGURE AND LINE, BESIDE THE CREDIT TO REINSTATE AFTER
-- SETTLEMENT), A BUNDLE'S VOUCHERS GIVEN AT ONCE, THE PAID CREDIT NOT YET
-- RELEASED AND THE BONUS THE SETTLING PAYMENT GIVES, THE VOUCHERS IT GIVES
-- (A BUNDLE'S, AND A CREDIT PACKAGE'S REWARD UNITS, ALSO WHERE THE REOPENING
-- GIVES THEM AT ONCE), AND WHO RECEIVES EACH WHEN IT IS NOT THE INVOICE'S
-- CUSTOMER (474's NOT COVERED 2 and 3; this file's first build's NOT
-- COVERED 2 to 4 and its second build's NOT COVERED 2; the Owner, 27 Oct
-- 2026, answer E, and 28 Oct 2026)
--
-- (The number 478 is this file's name, its errors' prefix, its self-test's
-- error code P0478 and its suite's; if it changes at commit, change it in
-- these places alone: the file name, the "478:" messages, P0478, the suite,
-- the page test, and the "-- 478 (the Owner" line the suites find the
-- preview's version by.)
--
-- WHO FOUND IT
--
--   474's builders (its NOT COVERED 2 and 3 and its suite's KNOWN K2, PT0,
--   26 and 27 Oct 2026), then this file's first build (its NOT COVERED 2 to
--   4, 27 Oct 2026), put to the Owner with 472 to 474's and 476 to 478's
--   questions, then this file's second build (its NOT COVERED 2 and its
--   suite's KNOWN K2a and K2b, PTv and PTr2, 27 Oct 2026), which the Owner's
--   answer E as ticked covers. Reproduced for this file on copies of
--   production at 475 with 476 and 477 applied (e948504d, then cc718597 and
--   88ba82cc: 1390 functions, 27 and 28 Oct 2026) with PT0 and its siblings
--   (this file's suite): made-up records, the app's own calls (the invoice
--   form and the Pay
--   dialog, Record Payment in full or of an amount, Cancel, the guided
--   Cancel, Reopen, the Finance panel's Correct payment and "Record refund
--   paid", an Owner's Move, a session paid from the package's credit and its
--   refund, the invoice form's customer change with 'transfer' or 'keep' and
--   a correction adding or taking off a line, a customer merge), each
--   followed by what its commit does. Every figure of the Reopen dialog
--   (invoice_reopen_preview, as InvoiceFinancePanel.tsx shows it) was read
--   before each reopening and compared with what the reopening gave at once
--   and to whom, and with what the payments that settled it gave and to
--   whom.
--
-- WHAT WAS WRONG
--
--   A Credit Package or Premium Bundle paid in part releases its paid credit
--   as the money comes in (327, 356: S$1 for each S$1 received). Cancelled,
--   the credit released and not spent is taken back (356's write-off); the
--   credit spent stays counted as released. A reopening sets the invoice's
--   status, and that runs the release again (trg_create_therapy_on_paid ->
--   release_credit_package_paid_credit): the paid credit the net payments
--   buy, less what is still counted as released, is given at once, by the
--   reopening itself (to whoever holds the package's benefits, 476). The
--   Reopen dialog said nothing of it: its only credit figure is "Revoked
--   credit to reinstate after settlement" (the reopening queue, 474), and
--   its explanation says "Previously revoked credit is reinstated once the
--   reopened invoice is fully settled". On copies, a S$100 package sold to A
--   and S$40 paid (S$40 released), one S$20 session paid from it, cancelled:
--   the dialog said S$0.00 to reinstate after settlement and S$60 to pay;
--   the reopening gave A S$20 at once; paid, A held S$80 (PT0, 474's K2).
--   Its siblings, each the same before 478 (the dialog silent; given at once):
--   * nothing spent: S$40 (PTn); the S$100 + S$10 Bonus package: S$20 (PTb);
--     the S$140 Premium Bundle (S$100 paid credit, S$40 Bonus, 2 vouchers),
--     S$40 paid: S$20 (PTv); a manual discount of S$20 (the entitlement
--     S$80): S$20 (PTd); two packages, S$140 paid: S$120 (PT2); beside a
--     therapy line: S$20 (PTth, PTth2: S$80);
--   * released in two payments (S$20 and S$20; the bundle S$30 and S$30):
--     S$20, S$40 (PTp, PTvp);
--   * cancelled again: each reopening S$20 (PTq); S$20 more paid while the
--     reopening waited, cancelled again: S$40 (PTqp); a 'keep' change while
--     it waited (PTqk: S$20; PTkw, with S$20 more paid: S$40); the session
--     refunded while it waited (PTuq: S$40);
--   * a customer change: 'keep' to B before or while cancelled, S$20 to A,
--     who holds the benefits (PTk, PTkc); 'transfer' to B before the session
--     or while cancelled, S$20 to B (PTt, PTtc); the buyer merged into K
--     (PTm: S$40 to K; PTm2: S$20);
--   * the session refunded while cancelled: S$40 (PTu); the guided Cancel
--     with "Record refund paid" not ticked: S$20 (PTgk);
--   * Correct payment raising the S$40 receipt while cancelled: to S$70,
--     S$50 (PTr); to S$100, the reopening settles the invoice at once and
--     gives S$80 (PTs), S$90 with the Bonus package (PTsb, PTks after a
--     'keep' change), S$120 and the 2 vouchers with the bundle (PTsv; PTkv
--     after a 'keep' change; PTsv1, one voucher chosen at the till, the other
--     to choose later); with a manual discount, S$70 (PTdb); a correction
--     taking a therapy line off while cancelled (S$120 paid of S$160, S$100
--     left): S$80 (PTcr);
--   * a correction added a second package to a paid package invoice, S$40
--     more paid, cancelled: S$40 at once beside S$60 to reinstate after
--     settlement (AL: the two figures).
--   And the dialog never said (474's NOT COVERED 3; this file's first
--   build's NOT COVERED 2 to 4):
--   * the vouchers a Premium Bundle settled at once by the reopening gives
--     then (sell_premium_bundle): PTsv: 2 vouchers given at once while the
--     dialog's "Voucher units to replace after settlement" said 0 (it counts
--     the units a reopening queues); PTsv1: 1, and 1 to choose later;
--   * what the payment that settles the reopened invoice gives: the
--     package's paid credit not yet released and its Bonus (PT0: the S$60
--     payment gave S$60, the dialog showed only "Payment required to settle
--     again: S$60.00"; PTb: S$70; PTv: S$100; all released credit spent,
--     PTall: S$60; the money paid back while cancelled, PTrp: S$100; KAL:
--     S$160 in all);
--   * (the second build's NOT COVERED 2, after its own lines were added)
--     the vouchers the settling payment gives: PTv's S$100 payment also
--     gave the bundle's 2 vouchers (chosen at the till), the dialog showed
--     the S$100 (PTvp, released in two payments: the same; PTv1, one chosen
--     and one to choose later: 1 voucher and an allowance of 1); a Credit
--     Package that grants reward units (S$100, a unit for each S$50: 2):
--     settled at once by the reopening after Correct payment raised its
--     receipt while cancelled, its 2 units given then, the dialog showing its
--     S$80 credit only (PTr2), or left to be paid, its 2 units given by the
--     settling payment (PTr2p);
--   * to whom: after a 'keep' change all of it goes to the buyer A, who
--     holds the benefits (476), while the invoice shows B (PTk: S$20 at once
--     and S$60 from the settling payment; PTkc, PTqk, PTks, PTkv, PTkw; the
--     vouchers and reward units too: PTkvl, PTkr, PTkrp); a line a
--     correction added after the change goes to B, who pays for it, the line
--     sold before to A (KAL: A S$20 and S$60, B S$100; KALv, the added line
--     the bundle: B S$140 and its 2 vouchers); the credit to reinstate after
--     settlement of a package paid in full goes to whoever holds the
--     invoice's benefits (460, 462): A after a 'keep' change while cancelled
--     (CTLk: S$60) or before a Refund in full or a refund by line of all of
--     it (RFk, RFkb: S$100), F to whom an Owner had moved the credit (CTLmv:
--     S$80), A beside B's line (KALr: A S$80 reinstated; B S$40 at once and
--     S$60 from the settling payment).
--   Right before 478 and after it (controls: nothing more to show): a
--   package settled before (CTL0, CTL1; a bundle, CTLv), refunded in full
--   (RF0), 'transfer' while cancelled (CTLt: B, the invoice's customer), a
--   merge while cancelled (CTLm: K, the invoice's customer), a voucher line
--   (VQ), a therapy line (TH0). The money was right (the reopening and the
--   payments gave what the net payments buy, to whoever holds the
--   benefits); what staff were told was short.
--
-- THE OWNER'S ANSWERS
--
--   22 Oct 2026: credit follows a merge and a 'transfer' customer change;
--   refunds paid back count as not used. 24 Oct 2026 (462, 463, 470): a
--   cancel or refund takes back what the invoice gave from whoever holds it
--   now; the customer holds exactly what the net payment buys; nothing
--   paid twice; Correct payment keeps working. 26 Oct 2026 (474): staff are
--   told what the payment will actually give. 27 Oct 2026, answering 474's
--   NOT COVERED 2: the Reopen dialog shows, for a package paid in part, the
--   credit the reopening itself releases at once (PT0: the reopening gives A
--   S$20 at once) as its own figure and page line, beside "credit to
--   reinstate after settlement"; the explanation says when each comes back.
--   27 Oct 2026, about 16:20 SGT, answering 476 to 478's first build (answer
--   E, "Dialogs name the receiver"): the Reopen dialog names who receives
--   the credit (this file's first build's NOT COVERED 4, as 474's NOT
--   COVERED 3), shows a bundle's vouchers given at once (NOT COVERED 2) and
--   what the settling payment gives (the paid credit not yet released and
--   the Bonus: NOT COVERED 3); the smallest page changes, with page tests;
--   the server's keys in the preview. (E's Pay dialog part is 476's; A to C
--   are 476's, D is 477's, F is 479's.) As the Owner ticked it that day:
--   "The Pay and Reopen dialogs say which customer gets the credit, plus the
--   vouchers and extra credit the payment will give": so also the vouchers
--   the settling payment gives (this file's second build's NOT COVERED 2: a
--   Premium Bundle's free vouchers, PTv; a reward-granting Credit Package's
--   reward units, PTr2), with the receiver named in the same note as the
--   other figures when it is not the invoice's customer, each shown only
--   when above 0; the sale record and the commission stay out of the dialog
--   (not asked).
--   28 Oct 2026, about 10:15 SGT, all "as built": the Reopen dialog's
--   receiver note covers all of its credit, the credit 474 reinstates after
--   settlement included ("All of the credit": CTLk, CTLmv, RFk, RFkb, KALr;
--   this file's second build's open point). (The same day, for 476 and 477:
--   476's line grouping (KAE, KAT2, KAT3) and its 'transfer' sale record
--   (CKT, CKTF) as built; 477's Move of Cancel-locked credit covers the
--   copies a 'transfer' change, a merge or a reopening's payment made,
--   MVWt.) No other business rule is changed by guessing.
--
-- WHAT THIS DOES (one function changed, whole text; the Reopen dialog's
-- lines; no table, column, trigger or grant changes; nothing given, taken or
-- queued changes)
--
--   invoice_reopen_preview_before_sessions(uuid) (474's text). For a
--   cancelled or refunded invoice with a customer it adds, for each Credit
--   Package or Premium Bundle line not settled and not split (the lines
--   release_credit_package_paid_credit releases and the settlement gives):
--   * 'credit_released_on_reopen' (as this file's first build): where the
--     reopening leaves the invoice partly paid or unpaid (the net payments
--     less than its total), what that release gives, the paid credit the net
--     payments buy (the money toward the line worked out as
--     credit_package_money_toward_line does, with the net payments the
--     reopening records, up to the line's entitlement) less what the line
--     still counts as released, where above 0; where the reopening settles
--     it (the net payments cover the total, reachable after a correction or
--     Correct payment while cancelled), what the settlement gives
--     (issue_credit_lines_for_invoice -> issue_credit_package or
--     sell_premium_bundle): the paid credit not released yet and the Bonus;
--   * 'bundle_vouchers_given_on_reopen' and
--     'bundle_vouchers_to_choose_on_reopen': where the reopening settles it,
--     what each Premium Bundle line gives at once (sell_premium_bundle): the
--     vouchers chosen at the till (the line's bundle_voucher_selection), and
--     the rest of its free vouchers as an allowance to choose later;
--   * 'reward_units_given_on_reopen': where the reopening settles it, the
--     reward units each Credit Package line that grants rewards gives then
--     (issue_credit_package: one for each whole reward threshold of the
--     package's customer price, its own threshold, else the store's lowest
--     Legacy rule on the day, else 994; a package that grants none, 0);
--   * 'credit_from_settling_payment': where the reopening leaves it to be
--     paid, what the payment that settles it gives (all the payments up to
--     its total, together: each part payment releases its share, the
--     settlement the rest): each line's paid credit not released yet once
--     the reopening has released what it gives at once, and its Bonus;
--   * 'bundle_vouchers_from_settling_payment',
--     'bundle_vouchers_to_choose_from_settling_payment' and
--     'reward_units_from_settling_payment': there too, the vouchers that
--     payment gives at the settlement: each Premium Bundle line's vouchers
--     chosen at the till and the rest of its free vouchers as an allowance
--     to choose later (sell_premium_bundle), each Credit Package line's
--     reward units (as above);
--   * 'credit_receivers': who receives what, one entry per customer
--     ('customer_id', 'customer_name', 'invoice_customer': whether it is the
--     invoice's customer, and its part of each figure: the eight above and
--     'credit_to_reinstate_after_settlement'), the invoice's customer first,
--     then by name. A line's credit, Bonus, vouchers and reward units go to
--     whoever holds its benefits (credit_line_benefits_holder, 476: the
--     buyer after a 'keep' change, whoever the benefits went to after a
--     'transfer' change or a merge; a line a correction added after money was
--     received, to the invoice's customer), else the invoice's customer, as
--     the release and the settlement give them. The credit to reinstate after
--     settlement (474's figure, its own rows: the cancellation's rows
--     reopen_invoice queues and
--     the queue's rows still waiting) goes back on the lot each ledger row
--     took it from and on to whoever holds the invoice's benefits now, as
--     apply_reopened_invoice_benefits gives it (460's and 462's rule: the
--     rows grouped by the lot a benefit row names whose chain holds their
--     lot; that lot's holder by invoice_credit_live_holder, a lot an Owner
--     moved to someone following merges alone; else the first live customer
--     of the lots it goes back on; else that lot's customer).
--   0 and an empty list for every other invoice. The explanation as this
--   file's first build: where the credit released at once is above 0, it
--   says so between its two last sentences ("Package or bundle credit the
--   net payments already pay for is released at once when the invoice is
--   reopened."); otherwise it is 474's word for word. Everything else is
--   474's text unchanged: who may open it, the blockers and can_reopen, the
--   credit to reinstate after settlement, the voucher units, the stock to
--   issue and the money figures. invoice_reopen_preview (it adds the
--   sessions) is unchanged.
--   The page (src/components/invoices/InvoiceFinancePanel.tsx, the Finance
--   panel's Reopen dialog; its words in src/lib/invoices/reopenReceivers.mjs
--   and .d.mts): "Credit released at once on reopening: S$20.00", then
--   "Bundle vouchers given at once on reopening: 2" (or "1 (and 1 more to
--   choose later)") and "Credit Package reward units given at once on
--   reopening: 2", just above "Revoked credit to reinstate after
--   settlement"; just below it "Credit the settling payment gives (package
--   or bundle paid credit not yet released, and the Bonus): S$60.00" and
--   "Vouchers the settling payment gives: 2 bundle vouchers" (or "1 bundle
--   voucher (and 1 more to choose later)", "2 Credit Package reward units",
--   or both, joined by "and"); then a note for each customer other than the
--   invoice's who receives any of it ("S$20.00 released at once, S$100.00
--   from the settling payment and 2 bundle vouchers from the settling
--   payment go to <name>, who holds the benefits, not to this invoice's
--   customer."; "2 reward units given at once", "2 reward units from the
--   settling payment" the same way). Each shown only where there is
--   something to show (above 0); the explanation is the server's. Its page
--   test: scripts/invoices/tests/reopen-dialog-478.test.mjs.
--   Who reads the preview (read from src and the database): the Reopen
--   dialog; reopen_invoice, which records it in the revision's snapshot
--   ('reopen_preview') and its Audit Log row ('invoice_reopened'): those
--   record the new keys from 478 on, the receivers' names among them. No
--   other function, page or Edge Function reads it.
--   On copies, after 478: every Reopen of every case of the suite shows
--   exactly what it gave at once, and to whom; at its last Reopen, what the
--   payments that settled it gave and to whom, and to whom the credit
--   reinstated after settlement went (PT0: A S$20 at once and S$60 from the
--   settling payment; PTk the same, A named; KAL: A S$20 and S$60, B S$100,
--   A named; PTsv: S$120 and 2 vouchers at once; CTLmv: F S$80 reinstated,
--   F named; PTv: S$20 at once, S$100 and 2 vouchers from the settling
--   payment; PTv1: 1 voucher and 1 to choose later from it; PTr2: S$80 and
--   2 reward units at once; PTr2p: S$20 at once, S$60 and 2 reward units
--   from the settling payment; PTkvl, PTkr, PTkrp the same, A named; KALv: A
--   S$20 and S$60, B S$140 and 2 vouchers, A named); the controls nothing
--   new and no note; who holds what, the money, the queue, the sessions and
--   vouchers exactly as before 478.
--
-- WHY THIS WAY
--
--   In the preview, because the money is right: the reopening and the
--   payments already give what the net payments buy, to whoever holds the
--   benefits; only what staff are told was short. Its own figures, not
--   added to "Revoked credit to reinstate after settlement", because each
--   comes at another time (at once; with the settling payment; after
--   settlement) and from another place (the release or the settlement of a
--   line; the reopening queue), as the Owner asked. Worked out from the same
--   reads the release, the settlement and the queue's give-back make
--   (credit_line_paid_entitlement, credit_package_released_paid_credit,
--   invoice_item_external_value, invoice_net_received,
--   credit_package_bonus_amount, the bundle's selection and free vouchers,
--   credit_line_benefits_holder, invoice_credit_live_holder,
--   credit_lot_ancestry, invoice_benefit_moved_to_other), and the money
--   toward each line by credit_package_money_toward_line's own order, with
--   the net payments the reopening records (reopen_invoice sets paid_amount
--   to them before the release runs), so it is what the reopening and the
--   payment give, not an estimate; the release's trim that runs first
--   (trim_released_paid_credit, capped to the money) never changes what it
--   releases (it only takes released credit above that cap back, and then
--   nothing is released; NOT COVERED 5). All of these are pinned (below); a
--   later change to any of them refuses 478's re-run and must re-check these
--   figures. The receivers for all the dialog's credit, not only the new
--   figures, because the Owner asked the dialog to name who receives the
--   credit and the credit to reinstate after settlement goes to whoever
--   holds the benefits too (474's NOT COVERED 3), so one list says it for
--   all of it (the Owner confirmed it on 28 Oct 2026: "All of the credit");
--   one entry per customer with each figure's part, so the page
--   says it in one note per customer, as the Pay dialog does (476). The
--   names come with the preview (one read, as invoice_credit_receivers
--   does for the Pay dialog), and are what the reopening records with it.
--   The vouchers the settling payment gives and a package's reward units as
--   their own figures, split as the at-once figures are (vouchers chosen at
--   the till; the allowance to choose later; reward units, which are
--   entitlements to activate, not vouchers held), because each is another
--   thing the customer gets and the dialog's at-once lines already split
--   them so; on one page line for the settling payment (beside its credit)
--   and one for reward units at once (beside the bundle's vouchers at once),
--   as few lines as say it. Reward units worked out with
--   issue_credit_package's own rule (the package's threshold, else
--   legacy_lowest_rule for the invoice's store on the day, else 994;
--   legacy_lowest_rule and sg_today pinned, below), so the figure is what
--   the settlement gives that day.
--   The sale record and its commission are left out: the Owner's answer
--   names the credit, the vouchers and who receives them.
--   Each page line only where there is something to show, and the
--   explanation's sentence only where credit comes at once, so the dialog of
--   every other invoice stays as it was. The other ways:
--   * running the reopening and undoing it to read what it gives: the
--     preview is read-only (STABLE) and would take the reopening's locks;
--   * adding the new figures to the after-settlement figure: one amount,
--     but the dialog would say all of it comes after settlement, which it
--     does not;
--   * a read of its own for the receivers (as 476's for the Pay dialog): a
--     second call from the dialog, worked out apart from the figures it
--     names;
--   * one count for all the vouchers the settling payment gives (the
--     bundle's and the reward units together): fewer keys, but the dialog
--     could not say which is a voucher to use and which a reward to
--     activate, nor what is still to choose.
--
-- NOT CHANGED
--
--   * Pinned (below), unchanged: invoice_reopen_preview (e09ebf9c), what
--     the reopening runs and gives (reopen_invoice: 475's AFTER;
--     trg_create_therapy_on_paid; release_credit_package_paid_credit,
--     issue_credit_package and sell_premium_bundle: 476's AFTERs;
--     validate_bundle_voucher_selection; trim_released_paid_credit;
--     issue_credit_lines_for_invoice), to whom (credit_line_benefits_holder
--     and credit_line_sale_group, 476's; invoice_credit_live_holder and
--     invoice_benefits_holder, 462's and 460's; credit_lot_current,
--     credit_lot_chain, credit_lot_ancestry, invoice_benefit_moved_to_other),
--     what the figures read (credit_package_money_toward_line,
--     credit_line_paid_entitlement, credit_package_released_paid_credit,
--     invoice_item_external_value, invoice_net_received,
--     credit_package_bonus_amount; for the reward units legacy_lowest_rule
--     and sg_today), what a cancellation leaves counted as
--     released (writeoff_released_credit_on_close), and what 474's text calls
--     and relies on (apply_reopened_invoice_benefits, refund_invoice_recorded,
--     cancel_invoice_recorded, credit_given_back_follows: 477's AFTER, the
--     voucher and stock readers, invoice_financial_position).
--   * Nothing given, taken or queued changes: no function that writes is
--     changed (who receives the vouchers and reward units, and what the sale
--     record and the commission are, stay 476's). Edge Functions and
--     settings: no change. The page: the lines above; its other lines read
--     the same keys as before; the Pay dialog's note is 476's.
--
-- NOT COVERED (for the Owner; the suite checks 2, 5, 9 and 10 as they are
-- and prints them as KNOWN; 1, 3, 4, 6 to 8, 11 and 12 are read from the
-- code. The second build's NOT COVERED 2, the vouchers the settling payment
-- gives and a package's reward units, is built now: the Owner's answer E
-- as ticked.)
--
--   1. A split package or bundle line (a multi-customer allocation, or 141's
--      legacy split) releases nothing before full payment and gives its
--      whole allocation, to each part's customer, when the invoice is
--      settled. None of the dialog's new figures counts it, nor names those
--      customers: where the reopening settles the invoice at once (after a
--      correction or Correct payment while it was cancelled), or later with
--      the settling payment. Read from the code (issue_credit_lines_for_
--      invoice); not reached on a copy through a page. The header's query
--      lists such invoices settled at once (2).
--   2. The sale record and its commission (whose referrer earns) are not
--      named in the dialog: not asked (the Owner's answer E as ticked names
--      the credit, the vouchers and who receives them). They follow 476's
--      rule (the holder's sale record after a 'keep' change: PTkvl, A's).
--   3. The settling payment's figures (its credit, vouchers and reward
--      units) are what the payments up to the invoice's total give together.
--      A refund recorded after the reopening (a refund by line while it
--      waits) or a Correct payment changes what the money buys, as for the
--      other figures (6).
--   4. The receivers are named as the release, the settlement and the
--      queue's give-back read them when the dialog is opened (6): a customer
--      change, a merge, a Move or a customer deleted between opening it and
--      the payment that settles the invoice changes who receives, as it does
--      for that payment. A line whose released credit is held by more than
--      one customer (split before 476) goes to the invoice's customer, as the
--      release and the settlement give it (476's NOT COVERED 3).
--   5. A release lot holding credit after the cancellation while the line
--      counts more released credit than the net payments buy: the
--      reopening's trim (trim_released_paid_credit) takes that credit back
--      at once, and the figures count what is still counted as released (the
--      credit released at once S$0.00; the settling payment's figure short
--      by what the trim takes back: T5, S$90 shown, S$100 given). No path the
--      pages offer leaves such a state (a cancellation reverses the release
--      lots; credit given back onto one is held back, 471, 472 and 477; every
--      reopening of the suite trimmed nothing); the suite makes it by hand
--      and checks it. The header's query lists such invoices (3).
--   6. The dialog shows what the reopening gives when it is opened: a
--      Correct payment, a payment, a customer change or a merge between
--      opening it and confirming changes what is given and to whom, as for
--      474's figure; what a later step changes (credit given back while the
--      reopening waits, 474's NOT COVERED 4) is not in it.
--   7. A Reopen dialog open on a screen when this goes in shows the old
--      figures until it is opened again; the page before its change ignores
--      the new keys (the explanation's sentence still says it, as in the
--      first build).
--   8. A bundle's vouchers, given at once or by the settling payment, are
--      counted as the settlement gives them (the selection made at the till,
--      the rest to choose later); the settlement's own checks are its own:
--      short of stock of a chosen voucher, or with more chosen than the
--      bundle grants now (its reward setting changed since the sale), the
--      reopening or the settling payment is refused ("Payment blocked ...
--      stock"; "That is more reward voucher(s) than this bundle grants"), as
--      before 478, and the dialog does not say so beforehand.
--   9. The receivers' names come from the customer records as they are when
--      the dialog is opened, and are recorded with the preview in the
--      reopening's revision and Audit Log row, as the other figures are.
--   10. The voucher units to replace after settlement (451 and 474's
--      figure, "Voucher units to replace after settlement") are counted, not
--      named by receiver: apply_reopened_invoice_vouchers gives them to
--      whoever holds the benefits (460 and 463), so after a 'keep' change
--      while cancelled a bundle's 2 vouchers given again are A's while the
--      note names A for the S$120 credit only (CTLvk). The Owner's answer of
--      28 Oct names all of the credit; whether the note should name these
--      vouchers too is for the Owner.
--   11. What a payment gives besides the invoice's own lines is not counted:
--      the day's Legacy qualification (recompute_legacy_qualification, which
--      every payment and a reopening run for the invoice's customer and
--      store, from the day's qualifying payments) may grant or withdraw
--      Legacy reward entitlements; the Pay dialog does not say beforehand
--      what it will grant either (the invoice's page shows what it earned
--      once paid). Read from the code (trg_create_therapy_on_paid).
--   12. A package's reward units are worked out as the settlement would on
--      the day the dialog is opened: a Legacy rule that takes effect, or a
--      package's threshold, reward setting or price changed before the
--      settling payment, changes them (as 6); a package deleted since has
--      none shown (its settlement is then refused, "Credit package not
--      found", as before 478).
--   13. 476's NOT COVERED 13 (not caused by 478): a package line a
--      correction added to an invoice already paid in full is counted as the
--      release counts it (credit_package_money_toward_line: only other credit
--      lines ahead of it), so the dialog's credit released at once includes
--      money that paid for lines already delivered (vouchers issued, sessions
--      created) beside those lines' own vouchers and sessions to reinstate:
--      it shows what the reopening gives, and both are short of "the
--      customer holds exactly what the net payment buys" the same way (the
--      review: S$60 released at once beside 3 sessions to reinstate). For
--      the Owner, with 476's.
--   14. The Pay dialog (476's read, invoice_credit_receivers) names who
--      receives the credit a reopened invoice gives back once paid in full,
--      by the same reads as this dialog (the receivers' 'credit to
--      reinstate after settlement'); the vouchers and sessions it reinstates
--      it does not name (476's NOT COVERED 14, 10 above).
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the text is the tested one (its AFTER md5); the function is its BEFORE
--     (474's AFTER, as 475 to 477 pinned it: replaced) or its AFTER (left
--     alone), anything else refused (this file's first and second builds'
--     AFTERs, 224855ab and b2d745cb, included: neither went in); no other
--     function takes its name; so a second run changes nothing;
--   * the functions it relies on are as read on a copy of production at 475
--     with 476 and 477 applied (pinned, below); the triggers on invoices as
--     read (the reopening's status change runs them: the release, the
--     settlement, the queue's give-back); the columns read have these types;
--     one queue row per ledger row; who calls the preview and
--     invoice_reopen_preview, who calls the release and the settlement, who
--     writes the release records and who writes the reopening queue, as read
--     (a new way would need the same care);
--   * on the first run nothing is refused for the data (478 needs no
--     decision before it goes in); the invoices of the header's query are
--     named in a notice (invoice numbers only): 1, 4, 5, 6 and 7 (the
--     dialog now shows or names more), 2 and 3 (for the Owner, NOT COVERED 1
--     and 5);
--   * who may call the function is as read (postgres and the service role),
--     compared as sets, and kept;
--   * afterwards: the AFTER md5 and the grants as tested.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0478, so it leaves no row): a made-up Owner, store, cash method, S$100
--   package, S$100 + S$10 Bonus package, S$140 Premium Bundle (S$100 paid
--   credit, S$40 Bonus, 2 free vouchers of a made-up voucher with no stock
--   count, both chosen at the till), S$20 session and eight customers
--   (fictional ACMA phones no customer has), six times: (a) the package
--   sold to A, S$40 paid, a session paid from its credit, cancelled: the
--   dialog's figures S$20 at once with the sentence, S$60 from the settling
--   payment, S$0.00 to reinstate after settlement, A (the invoice's
--   customer) the one receiver; reopened: A gets S$20; paid: S$60 more, A
--   S$80; (b) nothing spent: S$40 and S$60; reopened: A gets S$40; paid: S$60
--   more; (c) the Bonus package, a session, cancelled, its S$40 receipt
--   corrected to S$100: S$90 at once, nothing from a settling payment;
--   reopened straight to paid: A gets S$90; (d) a control: the package paid
--   in full, a session, cancelled: nothing at once nor from a settling
--   payment, 474's explanation word for word, S$80 to reinstate after
--   settlement, A its receiver; reopened straight to paid: A gets S$80; (e)
--   S$40 paid, a 'keep' change to B, a session paid by A from its credit,
--   cancelled: S$20 at once and S$60 from the settling payment, A the one
--   receiver and not the invoice's customer; reopened: A gets S$20; paid: A
--   S$80, B nothing; (f) the bundle sold to A, S$40 paid, a 'keep' change to
--   B, cancelled: S$40 at once, S$100 and the 2 vouchers from the settling
--   payment, A the one receiver and not the invoice's customer; reopened: A
--   gets S$40; paid: A S$100 more and the 2 vouchers, B nothing.
--   Its credit ledger rows draw entry numbers (a sequence, which an undone
--   transaction does not give back: a gap, as 443 to 477's self-tests). It
--   gives no reward units: they would draw Legacy entitlement numbers
--   (LEG-, next_legacy_entitlement_no), which an undone transaction does not
--   give back either (the suite checks them: PTr2 and its siblings); its
--   packages grant no reward, and its bundle's vouchers are all chosen at
--   the till (an allowance to choose later draws such a number too).
--   Locks: the function's catalogue row to the end of the apply, and the
--   rows the self-test writes and undoes; no table is locked against
--   ordinary writes. The self-test takes the commission advisory locks
--   (through its payments, customer change, cancels and reopenings) and new
--   invoice numbers, so it waits for any app cancel, refund,
--   commission-writing payment or invoice creation still open, and those
--   wait for it, for under a second. If one stays open longer than the 5 s
--   lock timeout, or an invoice created at the same moment takes the
--   self-test's invoice number, the apply stops, changing nothing, and can
--   be run again. A reopening still open when 478 commits records the
--   preview it read. Apply at a quiet time.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (475 in, 27 Oct 2026: e948504d, 1387 functions; the grant
--   list 381ef69c; head 20261027082304) -> 476 (cc718597, 1390 functions; the
--   grant list c05bd82e, as sets 5752c2df) -> 477 (88ba82cc) -> 478. 478
--   pins 475's reopen_invoice, 476's release, issuers and holder, and 477's
--   forwarder (their AFTERs). It changes the preview, which 475, 476 and
--   477 pin at 474's AFTER (and 471, 472 before them): after 478 a re-run of
--   475 or 477 refuses on that pin, 476's already refuses at 477 (its pin of
--   transfer_invoice_unused_benefit, 445's), 471's, 472's and 474's at 475
--   (reopen_invoice) and 473's at 476 (move_invoice_benefits_to_customer),
--   each changing nothing; all are applied, so nothing is lost. If anything
--   else goes in first (479 among them), work the fingerprints out again
--   and check that it changes none of the functions pinned below.
--   1. Before it, read only (invoice numbers and counts only; production was
--      not read for this file). 478 refuses no state; this lists whose
--      dialog changes (1, 4, 5, 6, 7) and what needs the Owner (2, 3). On
--      the production facts known (27 Oct 2026: 6 release records of
--      packages paid in part, none cancelled) it lists nothing under 1, 2, 3
--      and 5; 4 and 7 list any cancelled or refunded invoice with a package
--      or bundle line never paid towards (the settling payment would give
--      all of it, and a package's reward units by its own threshold or the
--      store's Legacy rules: PTnp, Q4n; this file's second build said
--      "nothing under 1 to 5", which missed these under 4); 6 may list a
--      cancelled invoice whose credit to reinstate goes to someone other
--      than its customer:
--     with
--     -- Credit Package and Premium Bundle lines of cancelled or refunded invoices
--     -- (the Reopen dialog is offered for them), in the order the money toward
--     -- them is counted (credit_package_money_toward_line)
--     l as (
--       select i.id as invoice_id, i.customer_id, i.store_id, x.id, x.line_kind, x.credit_package_id, x.premium_bundle_id,
--              x.credit_issued_at is null as unsettled,
--              (x.credit_split_allocation_id is not null or x.bundle_split_allocation_id is not null
--               or exists (select 1 from public.invoice_credit_splits c where c.invoice_item_id = x.id)) as split,
--              public.invoice_item_external_value(x.id) as line_value,
--              (select min(pl.created_at) from public.credit_package_progress_lots pl where pl.invoice_item_id = x.id) as first_release,
--              public.invoice_net_received(i.id) as n,
--              (i.total_amount = 0 and i.has_foc) or public.invoice_net_received(i.id) >= i.total_amount as settles
--         from public.invoices i join public.invoice_items x on x.invoice_id = i.id
--        where i.deleted_at is null and i.status::text in ('cancelled', 'refunded') and i.customer_id is not null
--          and x.line_kind in ('credit_package', 'premium_bundle')),
--     q as (
--       select l.*, coalesce(sum(l.line_value) over (partition by l.invoice_id order by l.unsettled, l.first_release nulls last, l.id
--                                                    rows between unbounded preceding and 1 preceding), 0) as ahead
--         from l),
--     -- for each line, as 478's preview works them out: what a reopening gives at
--     -- once, what the payment that settles it gives, a bundle's free vouchers
--     -- given at once or with the settling payment, a package's reward units, and
--     -- to whom; and the released credit it still counts above what the net
--     -- payments buy
--     r as (
--       select q.invoice_id, q.customer_id, q.id, q.unsettled, q.split, q.settles,
--              case when q.settles then greatest(round(e.entitled - e.released, 2), 0) + e.bonus
--                   when e.entitled > 0 then greatest(round(e.bought - e.released, 2), 0) else 0 end as at_once,
--              case when q.settles then 0
--                   else greatest(round(e.entitled - case when e.entitled > 0 then greatest(e.released, e.bought) else e.released end, 2), 0)
--                        + e.bonus end as later,
--              case when q.settles and q.line_kind = 'premium_bundle'
--                   then coalesce((select pb.free_voucher_qty from public.premium_bundles pb where pb.id = q.premium_bundle_id), 0)
--                   else 0 end as vouchers,
--              case when not q.settles and q.line_kind = 'premium_bundle'
--                   then coalesce((select pb.free_voucher_qty from public.premium_bundles pb where pb.id = q.premium_bundle_id), 0)
--                   else 0 end as later_vouchers,
--              case when q.line_kind = 'credit_package'
--                   then coalesce((select case when coalesce(pk.grants_reward, false) and u.qual > 0
--                                              then floor(coalesce(pk.customer_price, 0) / u.qual)::int else 0 end
--                                    from public.credit_packages pk
--                                    cross join lateral (select coalesce(pk.reward_qualifying_amount,
--                                                                        (public.legacy_lowest_rule(q.store_id, public.sg_today())).qualifying_amount, 994) as qual) u
--                                   where pk.id = q.credit_package_id and pk.deleted_at is null), 0)
--                   else 0 end as units,
--              round(e.released - e.bought, 2) as above,
--              case when q.unsettled and not q.split then coalesce(public.credit_line_benefits_holder(q.id), q.customer_id) end as receiver
--         from q cross join lateral (
--           select x.entitled, x.released, least(least(greatest(q.n - q.ahead, 0), q.line_value), x.entitled) as bought,
--                  case when q.line_kind = 'credit_package'
--                       then greatest(coalesce(public.credit_package_bonus_amount(q.credit_package_id), 0), 0)
--                       else greatest(coalesce((select pb.bonus_credit_amount from public.premium_bundles pb where pb.id = q.premium_bundle_id), 0), 0) end as bonus
--             from (select public.credit_line_paid_entitlement(q.id) as entitled,
--                          public.credit_package_released_paid_credit(q.id) as released) x) e),
--     -- the credit to reinstate after settlement (474's figure), row by row: each
--     -- ledger row's credit goes back on its lot, grouped by the lot a benefit row
--     -- of the invoice names whose chain holds it, and on to that group's holder
--     -- (apply_reopened_invoice_benefits, as 478's preview reads it)
--     w as (
--       select i.id as invoice_id, i.customer_id, lg.lot_id, lg.amount
--         from public.invoices i
--         join public.customer_credit_ledger lg
--           on lg.source_type = 'invoice_cancel_benefit' and lg.source_record_id = i.id
--              or lg.source_type = 'invoice_benefit_refund'
--                 and exists (select 1 from public.invoice_refunds f where f.invoice_id = i.id and f.request_id = lg.source_record_id)
--        where i.deleted_at is null and i.status::text in ('cancelled', 'refunded') and i.customer_id is not null
--          and not exists (select 1 from public.invoice_reopen_benefits rb where rb.source_ledger_id = lg.id)
--       union all
--       select i.id, i.customer_id, lg.lot_id, rb.amount
--         from public.invoices i
--         join public.invoice_reopen_benefits rb on rb.invoice_id = i.id and rb.applied_at is null
--         join public.customer_credit_ledger lg on lg.id = rb.source_ledger_id
--        where i.deleted_at is null and i.status::text in ('cancelled', 'refunded') and i.customer_id is not null),
--     k as (
--       select t.invoice_id, t.customer_id, t.target, sum(t.amount) as amount, array_agg(t.lot_id) as lots
--         from (select w.*, coalesce((select bv.lot_id from public.invoice_benefit_values bv
--                                      where bv.invoice_id = w.invoice_id and bv.lot_id is not null
--                                        and w.lot_id = any (public.credit_lot_ancestry(bv.lot_id))
--                                      order by (bv.lot_id = w.lot_id) desc, bv.created_at, bv.id limit 1), w.lot_id) as target
--                 from w) t
--        group by t.invoice_id, t.customer_id, t.target),
--     bk as (
--       select k.invoice_id, k.customer_id, k.amount,
--              coalesce(public.invoice_credit_live_holder(k.invoice_id, tl.customer_id,
--                         case when exists (select 1 from public.invoice_benefit_values bv
--                                            where bv.invoice_id = k.invoice_id and bv.lot_id = tl.id
--                                              and public.invoice_benefit_moved_to_other(bv.id)) then 'infinity'::timestamptz
--                              else tl.created_at end),
--                       (select c.id from public.customer_credit_lots pl join public.customers c on c.id = pl.customer_id
--                         where pl.id = any (k.lots) and c.deleted_at is null order by pl.created_at, pl.id limit 1),
--                       tl.customer_id) as receiver
--         from k join public.customer_credit_lots tl on tl.id = k.target),
--     found(reason, invoice_id, n) as (
--       select '1 changes: cancelled or refunded, with a package or bundle line paid in part whose reopening gives credit at once (released again, or the line settled where the net payments cover the invoice); from 478 the Reopen dialog shows it as "Credit released at once on reopening" and its explanation says so (the count is of lines)', r.invoice_id, count(*)
--         from r where r.unsettled and not r.split and r.at_once > 0 group by r.invoice_id
--       union all
--       select '2 for the Owner (not changed by 478: NOT COVERED 1): cancelled or refunded, with a split package or bundle line not settled whose reopening would settle it at once (the net payments cover the invoice); the dialog''s figures do not count it (the count is of lines)', r.invoice_id, count(*)
--         from r where r.unsettled and r.split and r.settles group by r.invoice_id
--       union all
--       select '3 for the Owner (not changed by 478: NOT COVERED 5): cancelled or refunded, with a package or bundle line paid in part whose released credit still counted is above what the net payments buy while one of its release lots holds credit; the reopening would take that credit back (trim_released_paid_credit), which the dialog does not show (the count is of lines)', r.invoice_id, count(*)
--         from r
--        where r.unsettled and not r.split and not r.settles and r.above > 0
--          and exists (select 1 from public.credit_package_progress_lots pl
--                        join public.customer_credit_lots cl on cl.id = public.credit_lot_current(pl.lot_id)
--                       where pl.invoice_item_id = r.id and pl.released_amount > 0 and cl.status = 'active' and cl.remaining_amount > 0)
--        group by r.invoice_id
--       union all
--       select '4 changes: cancelled or refunded, with a package or bundle line not settled that the reopening leaves to be paid: from 478 the Reopen dialog shows what the payment that settles it gives (its paid credit not yet released, and the Bonus) as "Credit the settling payment gives" (the count is of lines)', r.invoice_id, count(*)
--         from r where r.unsettled and not r.split and not r.settles and r.later > 0 group by r.invoice_id
--       union all
--       select '5 changes: cancelled or refunded, with a Premium Bundle line the reopening would settle at once: from 478 the Reopen dialog shows the free vouchers it gives then, as "Bundle vouchers given at once on reopening" (the count is of lines)', r.invoice_id, count(*)
--         from r where r.unsettled and not r.split and r.settles and r.vouchers > 0 group by r.invoice_id
--       union all
--       select '6 changes: cancelled or refunded, whose reopening or settling payment gives credit, a Bonus, vouchers or reward units, or whose credit to reinstate after settlement goes, to a customer other than the invoice''s (whoever holds the benefits: the buyer after a ''keep'' change, someone an Owner moved credit to): from 478 the Reopen dialog names them (the count is of customers)', x.invoice_id, count(distinct x.receiver)
--         from (select r.invoice_id, r.customer_id, r.receiver from r
--                where r.unsettled and not r.split and (r.at_once > 0 or r.later > 0 or r.vouchers > 0 or r.later_vouchers > 0 or r.units > 0)
--               union all
--               select bk.invoice_id, bk.customer_id, bk.receiver from bk where bk.amount > 0) x
--        where x.receiver is distinct from x.customer_id
--        group by x.invoice_id
--       union all
--       select '7 changes: cancelled or refunded, with a Premium Bundle line not settled that the reopening leaves to be paid (its free vouchers come with the settling payment), or a Credit Package line not settled that grants reward units (given at once where the reopening settles it, else with the settling payment): from 478 the Reopen dialog shows them, as "Vouchers the settling payment gives" and "Credit Package reward units given at once on reopening" (the count is of lines)', r.invoice_id, count(*)
--         from r where r.unsettled and not r.split and (r.later_vouchers > 0 or r.units > 0) group by r.invoice_id)
--     select f.reason, i.invoice_no, f.n
--       from found f join public.invoices i on i.id = f.invoice_id
--      order by f.reason, i.invoice_no
--      (The suite runs this same text on its cases' states before 478 and
--      checks what it lists.)
--   2. Dry run on a copy of production as it is then (475, then 476 and 477
--      applied to it): work out its fingerprint and grant list first (they
--      must be the BEFORE figures below, or be worked out again on that
--      copy); apply this file twice; the first run ends at the AFTER
--      fingerprint below, the second changes nothing ("left alone"); and the
--      suite, with the earlier suites below.
--   3. Apply (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself.
--   4. Then the page change (InvoiceFinancePanel.tsx,
--      src/lib/invoices/reopenReceivers.mjs and .d.mts; with its page test
--      and tsc) goes out with the app. Before it, the dialog shows the old
--      lines and the new explanation; nothing else depends on the order (the
--      page before 478 shows none of the new lines: the keys are absent).
--   Afterwards (checked on copies of production at 475 with 476 and 477
--   applied, 27 and 28 Oct 2026): a re-run of 475 or 477 refuses on its pin
--   of the preview, 476's on its pin of transfer_invoice_unused_benefit
--   (477's), 471's, 472's and 474's on reopen_invoice (475's), 473's on the
--   mover (476's), each changing nothing (the fingerprint and the grants as
--   before); 478's own leaves all alone. The suites that read the
--   preview's version, its keys or its explanation, where 478 is in (-v
--   nomig=1): reopen-dialog-waiting-credit-474 (S and 10 take 478's AFTER,
--   P1 works 474's text back from 478's, its new keys among the lines
--   taken out, KNOWN K2 (PT0) checked as 478 settles it, with the settling
--   payment's S$60 and A as its receiver), reopen-refund-cycles-451 (10: the
--   preview at 478's AFTER). function-grants is unchanged (nothing is
--   added).
--
-- BEFORE (a copy of production at 475 with 476 and 477 applied, 27 Oct 2026;
-- md5 of pg_get_functiondef with search_path public)
--   changed
--   invoice_reopen_preview_before_sessions(uuid)                       7e1ef2d25415e69b3f770fe2efd45190  (474's AFTER)
--   relied on, not changed (pinned)
--   invoice_reopen_preview(uuid)                                       e09ebf9c0841ef5463f96b26f4933541
--   reopen_invoice(uuid,text,uuid)                                     30066e137b9b75b5789a050c14debc04  (475's AFTER)
--   trg_create_therapy_on_paid()                                       012ae4e305b9870fa5596f740c0427b9
--   release_credit_package_paid_credit(uuid)                           f6685d987e998575c3c1e5917493dc24  (476's AFTER)
--   trim_released_paid_credit(uuid,text,boolean)                       14ded4342c3e65eb98547d224263519f
--   issue_credit_lines_for_invoice(uuid)                               303f45e12e88b8de58e95aa0f877b875
--   issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid)             5654ef9249cf5c6a943beb7890574f20  (476's AFTER)
--   sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid)  72d4ba2c35703b336f3b2e9114a6af6e  (476's AFTER)
--   validate_bundle_voucher_selection(uuid,uuid,jsonb)                 16e707758a4d771c49c403ef8983570f
--   credit_package_money_toward_line(uuid)                             798c2d67d55bb1d140232ff06ffb1034
--   credit_line_paid_entitlement(uuid)                                 da2404a1db281b46a44231bd071a069a
--   credit_package_released_paid_credit(uuid)                          6b27388462747e3c13f3da0b9ad165c0
--   invoice_item_external_value(uuid)                                  e1d12f5bf03e92e669d139f0405362af
--   invoice_net_received(uuid)                                         f256bea69b7defa38a950753bbc248da
--   credit_package_bonus_amount(uuid)                                  45031fdc18cdc6ed4a3e2a8275a8cbd5
--   legacy_lowest_rule(uuid,date)                                      3549988e36b6696e43ac2a4f248bd326  (the reward units)
--   sg_today()                                                         1c1289f18e24d8370e9a6364c9c06fca  (the reward units)
--   credit_line_benefits_holder(uuid)                                  45865ed52a5f24ebe6b8e435ba10e9e9  (476's)
--   credit_line_sale_group(uuid)                                       9c0e2931b672a763235d3d9839b2f02a  (476's)
--   invoice_credit_live_holder(uuid,uuid,timestamp with time zone)     a5692590ef3e8a7a7dd7e8ff7cfa9568
--   invoice_benefits_holder(uuid,uuid,timestamp with time zone)        55995ff6e1ffd4a1172cb930512a34b0
--   credit_lot_current(uuid)                                           d48fb24e6eb9733d7f867e42fa703e7b
--   credit_lot_chain(uuid)                                             556e725784154cbffc23d3ad900f9366
--   credit_lot_ancestry(uuid)                                          52b3cae789b6b52a12bb2f798af40cbe
--   invoice_benefit_moved_to_other(uuid)                               7016bed898e1bbe9d0ac4a05037d07c2
--   writeoff_released_credit_on_close(uuid,text,text)                  284a89cfb965e8028136b5f8a4f2bf08
--   apply_reopened_invoice_benefits()                                  36eaa7224e514d3e7e42e3eeb51acfb5
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)          804ecd829cfecf713783a09a05d93c7e
--   cancel_invoice_recorded(uuid,text,uuid)                            de52d9dbaef8ab15163bef35cb9d733d
--   credit_given_back_follows(uuid)                                    a0f2f5ece30be439049dca275802237a  (477's AFTER)
--   apply_reopened_invoice_vouchers()                                  6684840544d1ad8a28e2415934300054
--   invoice_voucher_reopen_candidates(uuid)                            20405a96c8780eac6425a5dae59c29e1
--   invoice_voucher_stock_unrecorded(uuid,boolean)                     91c8f0fa69ef6337f323b7ac467a8c2b
--   invoice_stock_to_deduct(uuid)                                      6356494ccb8545d46c56b788f8f85f54
--   invoice_financial_position(uuid)                                   ba7eccbfeff217c8b1969b0e55a010ca
--   is_owner_or_manager()                                              a98e50f1b6d3fa1e6c62cf52a8073cc8
--   user_has_store_access(uuid)                                        708992afaa6c3951f6329239b742987c
--   rental_is_outstanding(text)                                        076549a44bc057cd529aac5542c4d06e
--   correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)          af99337094edb6d73b9cc0ae00fbf138  (the self-test)
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                        04d647e13e9424a9375942e5812e91a2  (the self-test)
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)       80c80d386a5241e63b353e35e13ef250  (the self-test)
--   record_invoice_payment(uuid,jsonb,uuid)                            9c70097ed4da614fb9dcc66fdfcdb7d6  (the self-test)
--   the triggers on invoices (md5 of their definitions, by name)       92c94e3ebc6113a68d972330bbca8938 (19 triggers)
--   public function fingerprint, production now (475)                  e948504da4c17c1c15ff871fcb1e5631 (1387 functions; head 20261027082304)
--   public function fingerprint, 475 -> 476 (476's AFTER, on a copy)   cc7185970e4a01c0a225e114e0769691 (1390 functions)
--   public function fingerprint, 475 -> 476 -> 477 (on a copy)         88ba82ccc06315d862081fba55ce725d (1390 functions)
--   grant list after 477 (string_agg(signature '=' proacl, '|'), sorted, on that copy)
--                                                                      c05bd82edeafa1bf1e7165a406fcb043 (production lists the same
--                                                                      grants in another order: compare as sets)
--   grant list after 477 as sets (each proacl's items sorted)          5752c2df613b8a673831d1797636e3d7
-- AFTER (for later guards)
--   invoice_reopen_preview_before_sessions(uuid)                       acbfc38a20a000e1af0e78d26fc7fc4c  (grants kept: postgres, the service role;
--                                                                      this file's first build's AFTER was 224855ab, its second's
--                                                                      b2d745cb: neither went in)
--   public function fingerprint, worked out on a copy of production at 475 with 476 and 477 applied (28 Oct 2026, again
--   after 476's Pay dialog read gained the credit a reopened invoice gives back; a second run the same):
--     production now (475) -> 476 -> 477 -> 478                        eae7f82fcf73b53d97945020e755721a (1390 functions: none added, none dropped)
--     (on 476's build of 27 Oct 2026: 8c16bb63 -> c5faaa1f -> 3afb86c7; 478 does not pin that read)
--   grant list after 478                                               c05bd82edeafa1bf1e7165a406fcb043 (unchanged; as sets 5752c2df)
--
-- Test: scripts/invoices/tests/reopen-dialog-credit-released-478.sql
-- (begin ... rollback; it installs this file twice; -v nomig=1 where it is
-- in), and the page test scripts/invoices/tests/reopen-dialog-478.test.mjs.
-- The suite reproduces PT0 and its siblings first (nothing spent, the Bonus
-- package and the Premium Bundle, a discount, two packages, beside a
-- therapy line, released in two payments, cancelled again with and without
-- a payment or a session refund between, a 'keep' and a 'transfer' change
-- before, while cancelled or while a reopening waited, a merge, a session
-- refunded while cancelled, the guided Cancel, Correct payment raising the
-- money while cancelled up to settling the invoice at once, the bundle's
-- vouchers chosen at the till or to choose later, given at once or by the
-- settling payment, a Credit Package's reward units at once or by the
-- settling payment, a correction adding a package or the bundle beside one
-- settled or after a 'keep' change, an Owner's Move), with every figure of
-- the Reopen dialog read before each reopening and compared with what the
-- reopening gave at once and to whom, and at the last reopening with what
-- the payments that settled it gave and to whom; then checks the header's
-- query (1 to 7), the refusals, the install, every case after 478 (each
-- figure and each receiver's part is what was given; the explanation says
-- so; everything else, the money and who holds what, exactly as before
-- 478), the preview's other figures exactly 474's (474's text worked back
-- from 478's), what a reopening records, cases begun before 478 and read
-- after, and NOT COVERED 2, 5, 9 and 10 as KNOWN. Each app call is followed
-- by what its commit does (462's trigger is deferred). Fixtures only (the
-- repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The function this changes: BEFORE (474's AFTER, as 475 to 477 pinned
  -- it) and AFTER md5s; who may call it, as read (kept) ═══════════════════
  c_sig constant text := 'invoice_reopen_preview_before_sessions(uuid)';
  c_before constant text := '7e1ef2d25415e69b3f770fe2efd45190';
  c_after constant text := 'acbfc38a20a000e1af0e78d26fc7fc4c';
  c_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';

  -- ══ The whole text (exactly as the database prints it back) ═════════════
  c_def constant text := $d1$CREATE OR REPLACE FUNCTION public.invoice_reopen_preview_before_sessions(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare i public.invoices%rowtype; blockers text[]:='{}'; credits numeric; v478 numeric:=0;
 v478s numeric:=0; v478v int:=0; v478a int:=0; v478r jsonb:='[]'::jsonb;  -- 478
 v478u int:=0; v478sv int:=0; v478sa int:=0; v478su int:=0;  -- 478 (vouchers and reward units)
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can reopen invoices'; end if;
 select * into i from public.invoices where id=p_invoice_id;
 if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 if i.status not in ('cancelled','refunded') then blockers:=array_append(blockers,'Only cancelled or refunded invoices can be reopened'); end if;
 if i.status='refunded' and not exists(select 1 from public.invoice_refunds where invoice_id=i.id) then
  blockers:=array_append(blockers,'Historical refunded status has no payment-source refund evidence'); end if;
 if exists(select 1 from public.invoice_refunds where invoice_id=i.id and payment_id is null) then blockers:=array_append(blockers,'Resolve historical refund payment sources first'); end if;
 if i.stock_snapshot_version is null and exists(select 1 from public.invoice_items where invoice_id=i.id and line_kind in ('promotion','premium_bundle','voucher')) then
  blockers:=array_append(blockers,'Historical component/stock snapshots require review before reopening'); end if;
 if exists(select 1 from public.rentals where invoice_id=i.id and public.rental_is_outstanding(status::text)) then
  blockers:=array_append(blockers,'Resolve the outstanding rental in Rentals before reopening'); end if;
 select coalesce(sum(l.amount),0) into credits from public.customer_credit_ledger l
 where (l.source_type='invoice_cancel_benefit' and l.source_record_id=i.id
   or l.source_type='invoice_benefit_refund' and exists(select 1 from public.invoice_refunds r where r.invoice_id=i.id and r.request_id=l.source_record_id))
   and not exists(select 1 from public.invoice_reopen_benefits b where b.source_ledger_id=l.id);
 -- 474 (the Owner, 26 Oct 2026: "fix the leftover gaps too"; 471's NOT
 -- COVERED 7): with the credit an earlier reopening queued that still waits
 -- (invoice_reopen_benefits, not applied: the reopening was cancelled again
 -- before it was settled), as 417 counts such voucher units. The payment
 -- that settles the invoice gives every row still waiting, whichever
 -- reopening queued it (apply_reopened_invoice_benefits), and reopen_invoice
 -- queues only the rows not queued yet, so this is what that payment gives:
 -- the cancellation's rows the earlier reopening queued, credit held back
 -- and queued while it waited (credit_given_back_follows), less what a
 -- refund by line took off the queue since (446). Before, the dialog left
 -- them out (cancelled, S$60 refunded by line, reopened, a session refunded
 -- while it waited, cancelled again: S$0.00 shown, S$80 given).
 credits:=credits+coalesce((select sum(q.amount) from public.invoice_reopen_benefits q
   where q.invoice_id=i.id and q.applied_at is null),0);
 -- 478 (the Owner, 27 Oct 2026, answering 474's NOT COVERED 2): the credit
 -- the reopening itself gives at once, its own figure beside the credit to
 -- reinstate after settlement. A Credit Package or Premium Bundle line paid
 -- in part (not settled; a split line releases nothing before it is) has
 -- its paid credit released again when the reopening sets the invoice's
 -- status (trg_create_therapy_on_paid -> release_credit_package_paid_credit):
 -- what the net payments buy, less what it released before and still counts
 -- as released (what was spent; the cancellation took the rest back). The
 -- money toward each line is worked out as credit_package_money_toward_line
 -- does, with the net payments the reopening records. Where those cover the
 -- invoice (a correction or Correct payment while it was cancelled), the
 -- reopening settles it (issue_credit_lines_for_invoice) and gives the
 -- line's paid credit not released yet and its Bonus. Before, the dialog
 -- left it out (S$40 paid of S$100, S$20 spent, cancelled: the reopening
 -- gave S$20 at once, the dialog said nothing of it).
 -- 478 (the Owner, 27 Oct 2026, answer E: "Dialogs name the receiver"; 478's
 -- first build's NOT COVERED 2 to 4, and 474's NOT COVERED 3): and, from the
 -- same reads, what else the reopening and the payment that settles it give,
 -- and to whom:
 -- * a Premium Bundle settled at once by the reopening gives its vouchers
 --   at once (sell_premium_bundle): those chosen at the till (the line's
 --   bundle_voucher_selection), and the rest of its free vouchers as an
 --   allowance to choose later;
 -- * left partly paid or unpaid, the payment that settles it (all the
 --   payments up to its total, together) gives each such line's paid credit
 --   not released yet and its Bonus (each part payment releases its share,
 --   release_credit_package_paid_credit; the settlement the rest,
 --   issue_credit_package, sell_premium_bundle);
 -- * who receives it: a line's credit, Bonus and vouchers go to whoever holds
 --   its benefits (credit_line_benefits_holder, 476: the buyer after a
 --   'keep' change, whoever the benefits went to after a 'transfer' change or
 --   a merge), else the invoice's customer, as the release and the
 --   settlement give them; the credit to reinstate after settlement goes
 --   back on the lot each ledger row took it from and on to whoever holds the
 --   invoice's benefits now (apply_reopened_invoice_benefits: 460's and 462's
 --   rule, read the same way here).
 -- Before, the dialog said none of it: a bundle settled at once gave its 2
 -- vouchers while the dialog counted 0 voucher units; S$40 paid of S$100,
 -- S$20 spent, cancelled: the S$60 payment gave the S$60 paid credit not
 -- released yet, the dialog showed only the S$60 to pay; after a 'keep'
 -- change all of it went to the buyer, the dialog named no one.
 -- 478 (the Owner, 27 Oct 2026, answer E as ticked: "The Pay and Reopen
 -- dialogs say which customer gets the credit, plus the vouchers and extra
 -- credit the payment will give"; this file's second build's NOT COVERED
 -- 2): and the vouchers, from the same reads, to the same receiver as the
 -- line's credit:
 -- * a Premium Bundle left to be paid gives its vouchers with the settling
 --   payment, as sell_premium_bundle gives them at its settlement (those
 --   chosen at the till, and the rest of its free vouchers as an allowance
 --   to choose later);
 -- * a Credit Package that grants rewards gives its reward units at its
 --   settlement, at once where the reopening settles it, else with the
 --   settling payment, as issue_credit_package works them out: one for each
 --   whole reward threshold of the package's customer price (its own
 --   threshold, else the store's lowest Legacy rule on the day, else 994).
 -- Before, the dialog left them out: S$40 paid of a S$140 bundle, cancelled:
 -- the S$100 payment also gave its 2 vouchers, the dialog showed the S$100;
 -- a package granting 2 reward units settled at once by the reopening gave
 -- them, the dialog showed its credit only. The receivers cover all of the
 -- dialog's credit, the credit to reinstate after settlement included (the
 -- Owner, 28 Oct 2026: "All of the credit"). The sale record and its
 -- commission are not in the dialog (not asked).
 if i.status in ('cancelled','refunded') and i.customer_id is not null then
  with n as (select public.invoice_net_received(i.id) as n),
  l as (select x.id,x.line_kind,x.credit_package_id,x.premium_bundle_id,x.bundle_voucher_selection,x.credit_issued_at is null as unsettled,
               (x.credit_split_allocation_id is not null or x.bundle_split_allocation_id is not null
                or exists(select 1 from public.invoice_credit_splits c where c.invoice_item_id=x.id)) as split,
               public.invoice_item_external_value(x.id) as line_value,
               (select min(pl.created_at) from public.credit_package_progress_lots pl where pl.invoice_item_id=x.id) as first_release
          from public.invoice_items x where x.invoice_id=i.id and x.line_kind in ('credit_package','premium_bundle')),
  q as (select l.*,coalesce(sum(l.line_value) over (order by l.unsettled,l.first_release nulls last,l.id
                                                    rows between unbounded preceding and 1 preceding),0) as ahead from l),
  e as (select q.id,q.line_kind,q.premium_bundle_id,q.bundle_voucher_selection,
               (i.total_amount=0 and i.has_foc) or n.n>=i.total_amount as settles,
               x.entitled,x.released,least(least(greatest(n.n-q.ahead,0),q.line_value),x.entitled) as bought,
               case when q.line_kind='credit_package' then greatest(coalesce(public.credit_package_bonus_amount(q.credit_package_id),0),0)
                    else greatest(coalesce((select pb.bonus_credit_amount from public.premium_bundles pb where pb.id=q.premium_bundle_id),0),0) end as bonus,
               -- (a Credit Package's reward units, as issue_credit_package works
               -- them out at its settlement: the invoice's store, the day)
               case when q.line_kind='credit_package' then coalesce((
                 select case when coalesce(pk.grants_reward,false) and u.qual>0 then floor(coalesce(pk.customer_price,0)/u.qual)::int else 0 end
                   from public.credit_packages pk
                   cross join lateral (select coalesce(pk.reward_qualifying_amount,
                                                       (public.legacy_lowest_rule(i.store_id,public.sg_today())).qualifying_amount,994) as qual) u
                  where pk.id=q.credit_package_id and pk.deleted_at is null),0) else 0 end as units,
               coalesce(public.credit_line_benefits_holder(q.id),i.customer_id) as receiver
          from q cross join n
          cross join lateral (select public.credit_line_paid_entitlement(q.id) as entitled,public.credit_package_released_paid_credit(q.id) as released) x
         where q.unsettled and not q.split),
  g as (select e.receiver,
               case when e.settles then greatest(round(e.entitled-e.released,2),0)+e.bonus
                    when e.entitled>0 then greatest(round(e.bought-e.released,2),0) else 0 end as at_once,
               case when e.settles then 0
                    else greatest(round(e.entitled-case when e.entitled>0 then greatest(e.released,e.bought) else e.released end,2),0)+e.bonus end as later,
               case when e.settles then v.chosen else 0 end as vouchers,
               case when e.settles then greatest(v.free-v.chosen,0) else 0 end as allowance,
               case when e.settles then e.units else 0 end as units,
               case when e.settles then 0 else v.chosen end as later_vouchers,
               case when e.settles then 0 else greatest(v.free-v.chosen,0) end as later_allowance,
               case when e.settles then 0 else e.units end as later_units
          -- (a bundle's vouchers as sell_premium_bundle reads them at its
          -- settlement: at once where the reopening settles it, else with the
          -- settling payment)
          from e cross join lateral (
            select case when e.line_kind='premium_bundle' and jsonb_typeof(e.bundle_voucher_selection)='array'
                        then coalesce((select sum(greatest(coalesce((s->>'quantity')::int,0),0)) from jsonb_array_elements(e.bundle_voucher_selection) s),0)
                        else 0 end::int as chosen,
                   case when e.line_kind='premium_bundle'
                        then coalesce((select pb.free_voucher_qty from public.premium_bundles pb where pb.id=e.premium_bundle_id),0)
                        else 0 end as free) v),
  -- 474's figure row by row (its own reads above): each ledger row's credit
  -- goes back on its lot, grouped by the lot a benefit row names whose chain
  -- holds it, and on to that group's holder
  w as (select lg.lot_id,lg.amount from public.customer_credit_ledger lg
         where (lg.source_type='invoice_cancel_benefit' and lg.source_record_id=i.id
           or lg.source_type='invoice_benefit_refund' and exists(select 1 from public.invoice_refunds f where f.invoice_id=i.id and f.request_id=lg.source_record_id))
           and not exists(select 1 from public.invoice_reopen_benefits rb where rb.source_ledger_id=lg.id)
        union all
        select lg.lot_id,rb.amount from public.invoice_reopen_benefits rb join public.customer_credit_ledger lg on lg.id=rb.source_ledger_id
         where rb.invoice_id=i.id and rb.applied_at is null),
  t as (select w.amount,w.lot_id,coalesce((select bv.lot_id from public.invoice_benefit_values bv
                                           where bv.invoice_id=i.id and bv.lot_id is not null and w.lot_id=any(public.credit_lot_ancestry(bv.lot_id))
                                           order by (bv.lot_id=w.lot_id) desc,bv.created_at,bv.id limit 1),w.lot_id) as target from w),
  k as (select t.target,sum(t.amount) as amount,array_agg(t.lot_id) as lots from t group by t.target),
  bk as (select coalesce(public.invoice_credit_live_holder(i.id,tl.customer_id,
                          case when exists(select 1 from public.invoice_benefit_values bv where bv.invoice_id=i.id and bv.lot_id=tl.id
                                            and public.invoice_benefit_moved_to_other(bv.id)) then 'infinity'::timestamptz
                               else tl.created_at end),
                        (select c.id from public.customer_credit_lots pl join public.customers c on c.id=pl.customer_id
                          where pl.id=any(k.lots) and c.deleted_at is null order by pl.created_at,pl.id limit 1),
                        tl.customer_id) as receiver,k.amount
          from k join public.customer_credit_lots tl on tl.id=k.target),
  r as (select y.receiver,sum(y.at_once) as at_once,sum(y.vouchers)::int as vouchers,sum(y.allowance)::int as allowance,
               sum(y.units)::int as units,sum(y.later) as later,sum(y.later_vouchers)::int as later_vouchers,
               sum(y.later_allowance)::int as later_allowance,sum(y.later_units)::int as later_units,sum(y.back) as back
          from (select g.receiver,g.at_once,g.vouchers,g.allowance,g.units,g.later,g.later_vouchers,g.later_allowance,g.later_units,
                       0::numeric as back from g
                union all
                select bk.receiver,0,0,0,0,0,0,0,0,bk.amount from bk) y
         group by y.receiver)
  select coalesce(sum(r.at_once),0),coalesce(sum(r.later),0),coalesce(sum(r.vouchers),0),coalesce(sum(r.allowance),0),
         coalesce(sum(r.units),0),coalesce(sum(r.later_vouchers),0),coalesce(sum(r.later_allowance),0),coalesce(sum(r.later_units),0),
         coalesce(jsonb_agg(jsonb_build_object('customer_id',r.receiver,'customer_name',c.full_name,'invoice_customer',r.receiver=i.customer_id,
                    'credit_released_on_reopen',r.at_once,'bundle_vouchers_given_on_reopen',r.vouchers,
                    'bundle_vouchers_to_choose_on_reopen',r.allowance,'reward_units_given_on_reopen',r.units,
                    'credit_from_settling_payment',r.later,'bundle_vouchers_from_settling_payment',r.later_vouchers,
                    'bundle_vouchers_to_choose_from_settling_payment',r.later_allowance,'reward_units_from_settling_payment',r.later_units,
                    'credit_to_reinstate_after_settlement',r.back)
                  order by r.receiver=i.customer_id desc,c.full_name,r.receiver)
                  filter (where r.at_once>0 or r.vouchers>0 or r.allowance>0 or r.units>0 or r.later>0 or r.later_vouchers>0
                             or r.later_allowance>0 or r.later_units>0 or r.back>0),'[]'::jsonb)
    into v478,v478s,v478v,v478a,v478u,v478sv,v478sa,v478su,v478r
    from r left join public.customers c on c.id=r.receiver;
 end if;
 return public.invoice_financial_position(i.id)||jsonb_build_object('can_reopen',cardinality(blockers)=0,'blockers',to_jsonb(blockers),
   'credit_to_reinstate_after_settlement',credits,'credit_released_on_reopen',v478,
   'bundle_vouchers_given_on_reopen',v478v,'bundle_vouchers_to_choose_on_reopen',v478a,'credit_from_settling_payment',v478s,'credit_receivers',v478r,
   'reward_units_given_on_reopen',v478u,'bundle_vouchers_from_settling_payment',v478sv,
   'bundle_vouchers_to_choose_from_settling_payment',v478sa,'reward_units_from_settling_payment',v478su,
   'voucher_units_to_reinstate_after_settlement',
   -- 417: with the units an earlier reopening queued that are still waiting
   -- (reopen_invoice gives those, or more if there are more to give).
   -- 451: and what reopen_invoice queues beside them, by its rule: the
   -- candidates less the cancellation's part of what waits (up to
   -- cancelled_unused_value).
   (select coalesce(sum(w.quantity+greatest(c.quantity-least(w.quantity,b.cancelled_unused_value::int),0)),0)
      from public.invoice_voucher_reopen_candidates(i.id) c
      join public.invoice_benefit_values b on b.id=c.benefit_id
      cross join lateral (select coalesce(sum(q.quantity),0)::int as quantity from public.invoice_reopen_vouchers q
                           where q.invoice_id=i.id and q.benefit_id=c.benefit_id and q.applied_at is null) w),'stock_to_issue',(select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('item_name',case when s.kind='product' then (select name from public.products where id=s.item_id) else (select name from public.vouchers where id=s.item_id) end)),'[]') from (select t.kind,t.item_id,(t.quantity-case when t.kind='product' then 0 else coalesce((select sum(u.quantity)
          -- 417: less the units reopen_invoice records as taken already, moving no
          -- stock (a completed FOC invoice's vouchers, or those kept to give again).
          from public.invoice_voucher_stock_unrecorded(i.id,true) u where u.voucher_id=t.item_id),0) end)::int as quantity
         from public.invoice_stock_to_deduct(i.id) t) s where s.quantity>0),
   'explanation','Existing refunds remain recorded. Only net unrefunded payments settle the reopened invoice. '
     ||case when v478>0 then 'Package or bundle credit the net payments already pay for is released at once when the invoice is reopened. ' else '' end
     ||'Previously revoked credit is reinstated once the reopened invoice is fully settled.');
end $function$
$d1$;

  -- ══ Relied on, not changed (a copy of production at 475 with 476 and 477
  -- applied, 27 Oct 2026): its caller; what the reopening runs and gives at
  -- once (the figures are what they give); to whom (the receivers are whom
  -- they give to); what the figures read; what a cancellation leaves counted
  -- as released; what the rest of its text calls and relies on; the
  -- self-test's calls ════════════════════════════════════════════════════
  c_relied constant text[] := array[
    'invoice_reopen_preview(uuid)',
    'reopen_invoice(uuid,text,uuid)',
    'trg_create_therapy_on_paid()',
    'release_credit_package_paid_credit(uuid)',
    'trim_released_paid_credit(uuid,text,boolean)',
    'issue_credit_lines_for_invoice(uuid)',
    'issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid)',
    'sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid)',
    'validate_bundle_voucher_selection(uuid,uuid,jsonb)',
    'credit_package_money_toward_line(uuid)',
    'credit_line_paid_entitlement(uuid)',
    'credit_package_released_paid_credit(uuid)',
    'invoice_item_external_value(uuid)',
    'invoice_net_received(uuid)',
    'credit_package_bonus_amount(uuid)',
    'legacy_lowest_rule(uuid,date)',
    'sg_today()',
    'credit_line_benefits_holder(uuid)',
    'credit_line_sale_group(uuid)',
    'invoice_credit_live_holder(uuid,uuid,timestamp with time zone)',
    'invoice_benefits_holder(uuid,uuid,timestamp with time zone)',
    'credit_lot_current(uuid)',
    'credit_lot_chain(uuid)',
    'credit_lot_ancestry(uuid)',
    'invoice_benefit_moved_to_other(uuid)',
    'writeoff_released_credit_on_close(uuid,text,text)',
    'apply_reopened_invoice_benefits()',
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'credit_given_back_follows(uuid)',
    'apply_reopened_invoice_vouchers()',
    'invoice_voucher_reopen_candidates(uuid)',
    'invoice_voucher_stock_unrecorded(uuid,boolean)',
    'invoice_stock_to_deduct(uuid)',
    'invoice_financial_position(uuid)',
    'is_owner_or_manager()',
    'user_has_store_access(uuid)',
    'rental_is_outstanding(text)',
    'correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    'record_invoice_payment(uuid,jsonb,uuid)'];
  c_relied_md5 constant text[] := array[
    'e09ebf9c0841ef5463f96b26f4933541',
    '30066e137b9b75b5789a050c14debc04',
    '012ae4e305b9870fa5596f740c0427b9',
    'f6685d987e998575c3c1e5917493dc24',
    '14ded4342c3e65eb98547d224263519f',
    '303f45e12e88b8de58e95aa0f877b875',
    '5654ef9249cf5c6a943beb7890574f20',
    '72d4ba2c35703b336f3b2e9114a6af6e',
    '16e707758a4d771c49c403ef8983570f',
    '798c2d67d55bb1d140232ff06ffb1034',
    'da2404a1db281b46a44231bd071a069a',
    '6b27388462747e3c13f3da0b9ad165c0',
    'e1d12f5bf03e92e669d139f0405362af',
    'f256bea69b7defa38a950753bbc248da',
    '45031fdc18cdc6ed4a3e2a8275a8cbd5',
    '3549988e36b6696e43ac2a4f248bd326',
    '1c1289f18e24d8370e9a6364c9c06fca',
    '45865ed52a5f24ebe6b8e435ba10e9e9',
    '9c0e2931b672a763235d3d9839b2f02a',
    'a5692590ef3e8a7a7dd7e8ff7cfa9568',
    '55995ff6e1ffd4a1172cb930512a34b0',
    'd48fb24e6eb9733d7f867e42fa703e7b',
    '556e725784154cbffc23d3ad900f9366',
    '52b3cae789b6b52a12bb2f798af40cbe',
    '7016bed898e1bbe9d0ac4a05037d07c2',
    '284a89cfb965e8028136b5f8a4f2bf08',
    '36eaa7224e514d3e7e42e3eeb51acfb5',
    '804ecd829cfecf713783a09a05d93c7e',
    'de52d9dbaef8ab15163bef35cb9d733d',
    'a0f2f5ece30be439049dca275802237a',
    '6684840544d1ad8a28e2415934300054',
    '20405a96c8780eac6425a5dae59c29e1',
    '91c8f0fa69ef6337f323b7ac467a8c2b',
    '6356494ccb8545d46c56b788f8f85f54',
    'ba7eccbfeff217c8b1969b0e55a010ca',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    '708992afaa6c3951f6329239b742987c',
    '076549a44bc057cd529aac5542c4d06e',
    'af99337094edb6d73b9cc0ae00fbf138',
    '04d647e13e9424a9375942e5812e91a2',
    '80c80d386a5241e63b353e35e13ef250',
    '9c70097ed4da614fb9dcc66fdfcdb7d6'];
  -- The triggers on invoices, as read (a reopening's status change runs
  -- them: the release, the settlement, the queue's give-back).
  c_inv_trg_md5 constant text := '92c94e3ebc6113a68d972330bbca8938';
  c_inv_trg_n constant int := 19;
  c_release_trg constant text := 'CREATE TRIGGER create_therapy_on_paid AFTER UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_create_therapy_on_paid()';
  c_queue_trg constant text := 'CREATE TRIGGER invoice_reopen_benefits_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_benefits()';
  -- Who calls the preview and invoice_reopen_preview; who calls the release
  -- and the settlement; who writes the release records and the reopening
  -- queue (by name; a session's own temporary functions and the function
  -- itself are not counted), as read.
  c_callers constant text := 'invoice_reopen_preview(uuid)';
  c_pv_callers constant text := 'reopen_invoice(uuid,text,uuid)';
  c_release_callers constant text := 'correct_invoice(uuid,jsonb,jsonb,text,uuid), trg_create_therapy_on_paid()';
  c_issue_callers constant text := 'trg_create_therapy_on_paid()';
  c_progress_writers constant text := 'credit_given_back_follows(uuid), reclaim_released_credit_of_removed_lines(uuid,jsonb,text), release_credit_package_paid_credit(uuid), repair_credit_package_progress_lots(), trim_released_paid_credit(uuid,text,boolean), writeoff_released_credit_on_close(uuid,text,text)';
  c_queue_writers constant text := 'apply_reopened_invoice_benefits(), credit_given_back_follows(uuid), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), reopen_invoice(uuid,text,uuid)';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; i int; n int; v_first boolean; v_acl text;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_pk uuid; t_pkb uuid; t_svc uuid; t_wallet uuid;
  t_case int; t_a uuid; t_b uuid; t_inv uuid; t_s uuid; t_pay uuid; t_pv jsonb; t_want numeric; t_later numeric; t_back numeric;
  t_held numeric; t_expl text; t_rcv jsonb; t_v uuid; t_pb uuid; t_vo int; t_line jsonb;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The text is the tested one.
  if md5(c_def) <> c_after then
    raise exception '478: the text in this file is not the tested one'; end if;

  -- The functions relied on are as read (a copy of production at 475 with
  -- 476 and 477 applied, 27 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '478: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying (478 goes in after 475, 476 and 477).',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  select md5(string_agg(pg_get_triggerdef(oid), E'\n' order by tgname)), count(*) into v, n
    from pg_trigger where tgrelid = 'public.invoices'::regclass and not tgisinternal;
  if v is distinct from c_inv_trg_md5 or n <> c_inv_trg_n
     or (select pg_get_triggerdef(oid) from pg_trigger where tgrelid = 'public.invoices'::regclass
          and tgname = 'create_therapy_on_paid') is distinct from c_release_trg
     or (select pg_get_triggerdef(oid) from pg_trigger where tgrelid = 'public.invoices'::regclass
          and tgname = 'invoice_reopen_benefits_settled') is distinct from c_queue_trg then
    raise exception '478: the triggers on invoices are not as read on 27 Oct 2026 (% triggers, md5 %); check what a reopening''s status change runs, then re-test', n, v; end if;

  -- The columns read, with these types; one queue row per ledger row.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('invoice_reopen_benefits', 'invoice_id', 'uuid'), ('invoice_reopen_benefits', 'source_ledger_id', 'uuid'),
                 ('invoice_reopen_benefits', 'amount', 'numeric(12,2)'), ('invoice_reopen_benefits', 'applied_at', 'timestamp with time zone'),
                 ('customer_credit_ledger', 'id', 'uuid'), ('customer_credit_ledger', 'amount', 'numeric(12,2)'),
                 ('customer_credit_ledger', 'source_type', 'text'), ('customer_credit_ledger', 'source_record_id', 'uuid'),
                 ('customer_credit_ledger', 'lot_id', 'uuid'),
                 ('customer_credit_lots', 'id', 'uuid'), ('customer_credit_lots', 'customer_id', 'uuid'),
                 ('customer_credit_lots', 'created_at', 'timestamp with time zone'),
                 ('customers', 'id', 'uuid'), ('customers', 'full_name', 'text'), ('customers', 'deleted_at', 'timestamp with time zone'),
                 ('invoice_benefit_values', 'id', 'uuid'), ('invoice_benefit_values', 'invoice_id', 'uuid'),
                 ('invoice_benefit_values', 'lot_id', 'uuid'), ('invoice_benefit_values', 'created_at', 'timestamp with time zone'),
                 ('invoice_refunds', 'invoice_id', 'uuid'), ('invoice_refunds', 'request_id', 'uuid'),
                 ('invoices', 'id', 'uuid'), ('invoices', 'status', 'invoice_status'), ('invoices', 'customer_id', 'uuid'),
                 ('invoices', 'total_amount', 'numeric(12,2)'), ('invoices', 'has_foc', 'boolean'),
                 ('invoice_items', 'id', 'uuid'), ('invoice_items', 'invoice_id', 'uuid'), ('invoice_items', 'line_kind', 'invoice_line_kind'),
                 ('invoice_items', 'credit_package_id', 'uuid'), ('invoice_items', 'premium_bundle_id', 'uuid'),
                 ('invoice_items', 'bundle_voucher_selection', 'jsonb'),
                 ('invoice_items', 'credit_issued_at', 'timestamp with time zone'),
                 ('invoice_items', 'credit_split_allocation_id', 'uuid'), ('invoice_items', 'bundle_split_allocation_id', 'uuid'),
                 ('invoice_credit_splits', 'invoice_item_id', 'uuid'),
                 ('credit_package_progress_lots', 'invoice_item_id', 'uuid'), ('credit_package_progress_lots', 'created_at', 'timestamp with time zone'),
                 ('premium_bundles', 'id', 'uuid'), ('premium_bundles', 'bonus_credit_amount', 'numeric(12,2)'),
                 ('premium_bundles', 'free_voucher_qty', 'integer'),
                 ('credit_packages', 'id', 'uuid'), ('credit_packages', 'grants_reward', 'boolean'),
                 ('credit_packages', 'customer_price', 'numeric(12,2)'), ('credit_packages', 'reward_qualifying_amount', 'numeric(12,2)'),
                 ('credit_packages', 'deleted_at', 'timestamp with time zone'),
                 ('therapy_package_rules', 'qualifying_amount', 'numeric(12,2)'), ('invoices', 'store_id', 'uuid')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '478: these columns are missing or not as read on 27 Oct 2026: %', v; end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.invoice_reopen_benefits'::regclass and contype = 'u'
                  and pg_get_constraintdef(oid) = 'UNIQUE (source_ledger_id)') then
    raise exception '478: the reopening queue no longer holds one row per ledger row (its unique key is not as read on 27 Oct 2026)'; end if;

  -- No other function takes the name (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'invoice_reopen_preview_before_sessions'
     and p.oid::regprocedure::text <> c_sig;
  if v is not null then raise exception '478: another function takes the name of the one this changes: %', v; end if;

  -- Who calls the preview and invoice_reopen_preview; who calls the release
  -- and the settlement; who writes the release records and the reopening
  -- queue: as read (a new way would need the same care).
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'invoice_reopen_preview_before_sessions\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'invoice_reopen_preview_before_sessions';
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'invoice_reopen_preview\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'invoice_reopen_preview';
  if v is distinct from c_callers or d is distinct from c_pv_callers then
    raise exception '478: the functions that call the Reopen dialog''s preview are not as read on 27 Oct 2026 (% / %); check how each reads its figures, then re-test', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'release_credit_package_paid_credit\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'release_credit_package_paid_credit';
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'issue_credit_lines_for_invoice\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'issue_credit_lines_for_invoice';
  if v is distinct from c_release_callers or d is distinct from c_issue_callers then
    raise exception '478: what releases or settles a package line''s credit is not as read on 27 Oct 2026 (% / %); check what a reopening gives at once, then re-test', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+(public\.)?credit_package_progress_lots' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_progress_writers then
    raise exception '478: what writes the release records (credit_package_progress_lots) is not as read on 27 Oct 2026 (%); check what a line counts as released, then re-test', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+(public\.)?invoice_reopen_benefits' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_queue_writers then
    raise exception '478: what writes the reopening queue (invoice_reopen_benefits) is not as read on 27 Oct 2026 (%); check what the settling payment gives back and to whom, then re-test', v; end if;

  -- The function: its BEFORE (replaced) or its AFTER (left alone).
  d := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  if md5(d) = c_after then
    raise notice '478: public.% is already this version; left alone', c_sig;
    v_first := false;
  elsif md5(d) = c_before then
    v_first := true;
  else
    raise exception '478: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig, md5(d);
  end if;

  -- ── On the first run: nothing is refused for the data (478 needs no
  -- decision before it goes in), but whose dialog changes and what needs the
  -- Owner is named (the header's read-only query: 1, 4, 5, 6 and 7, the
  -- dialog now shows or names more; 2 and 3, for the Owner).
  if v_first then
    with
    -- Credit Package and Premium Bundle lines of cancelled or refunded invoices
    -- (the Reopen dialog is offered for them), in the order the money toward
    -- them is counted (credit_package_money_toward_line)
    l as (
      select i.id as invoice_id, i.customer_id, i.store_id, x.id, x.line_kind, x.credit_package_id, x.premium_bundle_id,
             x.credit_issued_at is null as unsettled,
             (x.credit_split_allocation_id is not null or x.bundle_split_allocation_id is not null
              or exists (select 1 from public.invoice_credit_splits c where c.invoice_item_id = x.id)) as split,
             public.invoice_item_external_value(x.id) as line_value,
             (select min(pl.created_at) from public.credit_package_progress_lots pl where pl.invoice_item_id = x.id) as first_release,
             public.invoice_net_received(i.id) as n,
             (i.total_amount = 0 and i.has_foc) or public.invoice_net_received(i.id) >= i.total_amount as settles
        from public.invoices i join public.invoice_items x on x.invoice_id = i.id
       where i.deleted_at is null and i.status::text in ('cancelled', 'refunded') and i.customer_id is not null
         and x.line_kind in ('credit_package', 'premium_bundle')),
    q as (
      select l.*, coalesce(sum(l.line_value) over (partition by l.invoice_id order by l.unsettled, l.first_release nulls last, l.id
                                                   rows between unbounded preceding and 1 preceding), 0) as ahead
        from l),
    -- for each line, as 478's preview works them out: what a reopening gives at
    -- once, what the payment that settles it gives, a bundle's free vouchers
    -- given at once or with the settling payment, a package's reward units, and
    -- to whom; and the released credit it still counts above what the net
    -- payments buy
    r as (
      select q.invoice_id, q.customer_id, q.id, q.unsettled, q.split, q.settles,
             case when q.settles then greatest(round(e.entitled - e.released, 2), 0) + e.bonus
                  when e.entitled > 0 then greatest(round(e.bought - e.released, 2), 0) else 0 end as at_once,
             case when q.settles then 0
                  else greatest(round(e.entitled - case when e.entitled > 0 then greatest(e.released, e.bought) else e.released end, 2), 0)
                       + e.bonus end as later,
             case when q.settles and q.line_kind = 'premium_bundle'
                  then coalesce((select pb.free_voucher_qty from public.premium_bundles pb where pb.id = q.premium_bundle_id), 0)
                  else 0 end as vouchers,
             case when not q.settles and q.line_kind = 'premium_bundle'
                  then coalesce((select pb.free_voucher_qty from public.premium_bundles pb where pb.id = q.premium_bundle_id), 0)
                  else 0 end as later_vouchers,
             case when q.line_kind = 'credit_package'
                  then coalesce((select case when coalesce(pk.grants_reward, false) and u.qual > 0
                                             then floor(coalesce(pk.customer_price, 0) / u.qual)::int else 0 end
                                   from public.credit_packages pk
                                   cross join lateral (select coalesce(pk.reward_qualifying_amount,
                                                                       (public.legacy_lowest_rule(q.store_id, public.sg_today())).qualifying_amount, 994) as qual) u
                                  where pk.id = q.credit_package_id and pk.deleted_at is null), 0)
                  else 0 end as units,
             round(e.released - e.bought, 2) as above,
             case when q.unsettled and not q.split then coalesce(public.credit_line_benefits_holder(q.id), q.customer_id) end as receiver
        from q cross join lateral (
          select x.entitled, x.released, least(least(greatest(q.n - q.ahead, 0), q.line_value), x.entitled) as bought,
                 case when q.line_kind = 'credit_package'
                      then greatest(coalesce(public.credit_package_bonus_amount(q.credit_package_id), 0), 0)
                      else greatest(coalesce((select pb.bonus_credit_amount from public.premium_bundles pb where pb.id = q.premium_bundle_id), 0), 0) end as bonus
            from (select public.credit_line_paid_entitlement(q.id) as entitled,
                         public.credit_package_released_paid_credit(q.id) as released) x) e),
    -- the credit to reinstate after settlement (474's figure), row by row: each
    -- ledger row's credit goes back on its lot, grouped by the lot a benefit row
    -- of the invoice names whose chain holds it, and on to that group's holder
    -- (apply_reopened_invoice_benefits, as 478's preview reads it)
    w as (
      select i.id as invoice_id, i.customer_id, lg.lot_id, lg.amount
        from public.invoices i
        join public.customer_credit_ledger lg
          on lg.source_type = 'invoice_cancel_benefit' and lg.source_record_id = i.id
             or lg.source_type = 'invoice_benefit_refund'
                and exists (select 1 from public.invoice_refunds f where f.invoice_id = i.id and f.request_id = lg.source_record_id)
       where i.deleted_at is null and i.status::text in ('cancelled', 'refunded') and i.customer_id is not null
         and not exists (select 1 from public.invoice_reopen_benefits rb where rb.source_ledger_id = lg.id)
      union all
      select i.id, i.customer_id, lg.lot_id, rb.amount
        from public.invoices i
        join public.invoice_reopen_benefits rb on rb.invoice_id = i.id and rb.applied_at is null
        join public.customer_credit_ledger lg on lg.id = rb.source_ledger_id
       where i.deleted_at is null and i.status::text in ('cancelled', 'refunded') and i.customer_id is not null),
    k as (
      select t.invoice_id, t.customer_id, t.target, sum(t.amount) as amount, array_agg(t.lot_id) as lots
        from (select w.*, coalesce((select bv.lot_id from public.invoice_benefit_values bv
                                     where bv.invoice_id = w.invoice_id and bv.lot_id is not null
                                       and w.lot_id = any (public.credit_lot_ancestry(bv.lot_id))
                                     order by (bv.lot_id = w.lot_id) desc, bv.created_at, bv.id limit 1), w.lot_id) as target
                from w) t
       group by t.invoice_id, t.customer_id, t.target),
    bk as (
      select k.invoice_id, k.customer_id, k.amount,
             coalesce(public.invoice_credit_live_holder(k.invoice_id, tl.customer_id,
                        case when exists (select 1 from public.invoice_benefit_values bv
                                           where bv.invoice_id = k.invoice_id and bv.lot_id = tl.id
                                             and public.invoice_benefit_moved_to_other(bv.id)) then 'infinity'::timestamptz
                             else tl.created_at end),
                      (select c.id from public.customer_credit_lots pl join public.customers c on c.id = pl.customer_id
                        where pl.id = any (k.lots) and c.deleted_at is null order by pl.created_at, pl.id limit 1),
                      tl.customer_id) as receiver
        from k join public.customer_credit_lots tl on tl.id = k.target),
    found(reason, invoice_id, n) as (
      select '1 changes: cancelled or refunded, with a package or bundle line paid in part whose reopening gives credit at once (released again, or the line settled where the net payments cover the invoice); from 478 the Reopen dialog shows it as "Credit released at once on reopening" and its explanation says so (the count is of lines)', r.invoice_id, count(*)
        from r where r.unsettled and not r.split and r.at_once > 0 group by r.invoice_id
      union all
      select '2 for the Owner (not changed by 478: NOT COVERED 1): cancelled or refunded, with a split package or bundle line not settled whose reopening would settle it at once (the net payments cover the invoice); the dialog''s figures do not count it (the count is of lines)', r.invoice_id, count(*)
        from r where r.unsettled and r.split and r.settles group by r.invoice_id
      union all
      select '3 for the Owner (not changed by 478: NOT COVERED 5): cancelled or refunded, with a package or bundle line paid in part whose released credit still counted is above what the net payments buy while one of its release lots holds credit; the reopening would take that credit back (trim_released_paid_credit), which the dialog does not show (the count is of lines)', r.invoice_id, count(*)
        from r
       where r.unsettled and not r.split and not r.settles and r.above > 0
         and exists (select 1 from public.credit_package_progress_lots pl
                       join public.customer_credit_lots cl on cl.id = public.credit_lot_current(pl.lot_id)
                      where pl.invoice_item_id = r.id and pl.released_amount > 0 and cl.status = 'active' and cl.remaining_amount > 0)
       group by r.invoice_id
      union all
      select '4 changes: cancelled or refunded, with a package or bundle line not settled that the reopening leaves to be paid: from 478 the Reopen dialog shows what the payment that settles it gives (its paid credit not yet released, and the Bonus) as "Credit the settling payment gives" (the count is of lines)', r.invoice_id, count(*)
        from r where r.unsettled and not r.split and not r.settles and r.later > 0 group by r.invoice_id
      union all
      select '5 changes: cancelled or refunded, with a Premium Bundle line the reopening would settle at once: from 478 the Reopen dialog shows the free vouchers it gives then, as "Bundle vouchers given at once on reopening" (the count is of lines)', r.invoice_id, count(*)
        from r where r.unsettled and not r.split and r.settles and r.vouchers > 0 group by r.invoice_id
      union all
      select '6 changes: cancelled or refunded, whose reopening or settling payment gives credit, a Bonus, vouchers or reward units, or whose credit to reinstate after settlement goes, to a customer other than the invoice''s (whoever holds the benefits: the buyer after a ''keep'' change, someone an Owner moved credit to): from 478 the Reopen dialog names them (the count is of customers)', x.invoice_id, count(distinct x.receiver)
        from (select r.invoice_id, r.customer_id, r.receiver from r
               where r.unsettled and not r.split and (r.at_once > 0 or r.later > 0 or r.vouchers > 0 or r.later_vouchers > 0 or r.units > 0)
              union all
              select bk.invoice_id, bk.customer_id, bk.receiver from bk where bk.amount > 0) x
       where x.receiver is distinct from x.customer_id
       group by x.invoice_id
      union all
      select '7 changes: cancelled or refunded, with a Premium Bundle line not settled that the reopening leaves to be paid (its free vouchers come with the settling payment), or a Credit Package line not settled that grants reward units (given at once where the reopening settles it, else with the settling payment): from 478 the Reopen dialog shows them, as "Vouchers the settling payment gives" and "Credit Package reward units given at once on reopening" (the count is of lines)', r.invoice_id, count(*)
        from r where r.unsettled and not r.split and (r.later_vouchers > 0 or r.units > 0) group by r.invoice_id)
    select string_agg(format('%s: %s invoice(s) (%s)', f.reason, f.n, f.nos), '; ' order by f.reason) into v
      from (select left(f.reason, 1) as reason, count(*) as n, string_agg(i.invoice_no, ', ' order by i.invoice_no) as nos
              from found f join public.invoices i on i.id = f.invoice_id group by left(f.reason, 1)) f;
    if v is not null then
      raise notice '478: the header''s query lists %: 1, 4, 5, 6 and 7, the Reopen dialog now shows what its reopening and the settling payment give, vouchers and reward units among them, and names whoever else receives it; 2 and 3 are for the Owner (NOT COVERED 1 and 5), not changed by 478', v;
    end if;
  end if;

  -- Who may call it, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig))
     is distinct from (select array_agg(x::text order by x::text) from unnest(c_acl::aclitem[]) x) then
    raise exception '478: who may call public.% is not as read on 27 Oct 2026 (%)', c_sig,
      (select proacl::text from pg_proc where oid = to_regprocedure('public.' || c_sig)); end if;
  v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig));

  -- ── Change ──────────────────────────────────────────────────────────────
  if v_first then
    execute c_def;
  end if;

  -- ── Afterwards: installed exactly as tested, grants as before ───────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_after then
    raise exception '478: public.% is not at its AFTER md5 (%)', c_sig, md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))); end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig)) is distinct from v_acl then
    raise exception '478: the grants of public.% changed', c_sig; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("478 check", @example.com, fictional ACMA
  -- phones no customer uses); it ends by raising P0478, which undoes all it
  -- wrote. 462's trigger runs at commit; here at each step's end (SET
  -- CONSTRAINTS ... IMMEDIATE), as a commit would.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from generate_series(600, 699) g, lateral (select '+61491570' || g::text as p) x
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p desc limit 8);
    if coalesce(cardinality(t_phones), 0) < 8 then raise exception '478: the self-test found no eight unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '478-check-' || t_sfx || '@example.com') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '478 check', '478-check-' || t_sfx || '@example.com', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('478 check ' || t_sfx, '478-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('478 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy, grants_reward)
    values ('478 check ' || t_sfx, 100, 100, false, true, true, false) returning id into t_pk;
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('478 check bonus ' || t_sfx, 100, 100, true, 10, true, true, false) returning id into t_pkb;
    insert into public.credit_package_stores (package_id, store_id) values (t_pk, t_store), (t_pkb, t_store);
    -- (f) a S$140 Premium Bundle (S$100 paid credit, S$40 Bonus) with two
    -- free vouchers, both chosen at the till (a voucher with no stock count).
    insert into public.vouchers (name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('478 check voucher ' || t_sfx, '478V-' || t_sfx, 'normal', 'unlimited', 30, true) returning id into t_v;
    insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store) values (t_v, t_store, 30, true);
    insert into public.premium_bundles (name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('478 check bundle ' || t_sfx, 140, 100, 40, 2, true) returning id into t_pb;
    insert into public.premium_bundle_stores (bundle_id, store_id) values (t_pb, t_store);
    insert into public.premium_bundle_vouchers (bundle_id, voucher_id) values (t_pb, t_v);
    insert into public.therapy_services (service_code, name, standard_price, duration_minutes, is_active)
    values ('478-' || t_sfx, '478 check ' || t_sfx, 20, 30, true) returning id into t_svc;
    insert into public.therapy_service_stores (service_id, store_id, is_available) values (t_svc, t_store, true);
    select pm.id into t_wallet from public.payment_methods pm
     where pm.name = 'Wallet — Credit Package Paid' and pm.is_wallet_credit and pm.deleted_at is null;
    if t_wallet is null then raise exception '478: the wallet method "Wallet — Credit Package Paid" (443) is not there'; end if;

    for t_case in 1 .. 6 loop
      -- The package (the Bonus package in (c); the Premium Bundle in (f))
      -- sold to A and paid S$40 (in full in (d)); in (e) and (f) the invoice
      -- changed to B with 'keep'; a S$20 session paid from its credit by A
      -- (none in (b) and (f)); cancelled (the credit released and not spent
      -- is taken back).
      insert into public.customers (full_name, phone) values ('478 Check Buyer ' || t_case || ' ' || t_sfx, t_phones[t_case]) returning id into t_a;
      t_line := case when t_case = 6
                     then jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', t_pb, 'quantity', 1,
                                             'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', t_v, 'quantity', 2)))
                     else jsonb_build_object('kind', 'credit_package', 'credit_package_id', case when t_case = 3 then t_pkb else t_pk end, 'quantity', 1) end;
      t_inv := public.create_invoice(t_store, t_a, null::uuid, jsonb_build_array(t_line), 0::numeric, null::text, null::uuid, '[]'::jsonb);
      perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
        'amount', case when t_case = 4 then 100 else 40 end)), gen_random_uuid());
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      t_b := null;
      if t_case in (5, 6) then
        -- (e), (f) The invoice form's customer change to B, keeping the
        -- benefits with whoever holds them ('keep'): only the invoice's
        -- customer changes.
        insert into public.customers (full_name, phone)
        values ('478 Check Other ' || t_case || ' ' || t_sfx, t_phones[t_case + 2]) returning id into t_b;
        perform public.correct_invoice(t_inv,
          (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
                    'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id,
                    'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
             from public.invoice_items it where it.invoice_id = t_inv),
          jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = t_inv),
            'customer_id', t_b, 'store_id', t_store, 'benefit_action', 'keep'),
          '478 check keep', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if (select customer_id from public.invoices where id = t_inv) is distinct from t_b then
          raise exception '478: (%) the customer change to B did not go through', chr(96 + t_case); end if;
      end if;
      if t_case not in (2, 6) then
        t_s := public.create_invoice(t_store, t_a, null::uuid,
          jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 1)),
          0::numeric, null::text, null::uuid, '[]'::jsonb);
        perform public.record_invoice_payment(t_s, jsonb_build_array(jsonb_build_object('payment_method_id', t_wallet, 'amount', 20)), gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
      end if;
      perform public.cancel_invoice_recorded(t_inv, '478 check', gen_random_uuid());
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      if t_case = 3 then
        -- (c) Correct payment raises the S$40 receipt to S$100 while it is
        -- cancelled: the reopening settles it at once.
        select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt';
        perform public.correct_invoice_payment(t_pay, 100, public.sg_today(), t_cash, '478 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
      end if;
      -- The Reopen dialog: the credit the reopening gives at once, what the
      -- settling payment gives (in (f) also the bundle's 2 vouchers), the
      -- credit to reinstate after settlement, the explanation, and who
      -- receives it (A alone; in (e) and (f) not the invoice's customer).
      t_pv := public.invoice_reopen_preview(t_inv);
      t_want := case t_case when 1 then 20 when 2 then 40 when 3 then 90 when 4 then 0 when 5 then 20 else 40 end;
      t_later := case t_case when 1 then 60 when 2 then 60 when 5 then 60 when 6 then 100 else 0 end;
      t_back := case when t_case = 4 then 80 else 0 end;
      t_vo := case when t_case = 6 then 2 else 0 end;
      t_expl := 'Existing refunds remain recorded. Only net unrefunded payments settle the reopened invoice. '
        || case when t_want > 0 then 'Package or bundle credit the net payments already pay for is released at once when the invoice is reopened. ' else '' end
        || 'Previously revoked credit is reinstated once the reopened invoice is fully settled.';
      t_rcv := t_pv->'credit_receivers';
      if (t_pv->>'credit_released_on_reopen')::numeric is distinct from t_want
         or (t_pv->>'credit_from_settling_payment')::numeric is distinct from t_later
         or (t_pv->>'credit_to_reinstate_after_settlement')::numeric is distinct from t_back
         or (t_pv->>'bundle_vouchers_given_on_reopen')::int is distinct from 0
         or (t_pv->>'bundle_vouchers_to_choose_on_reopen')::int is distinct from 0
         or (t_pv->>'reward_units_given_on_reopen')::int is distinct from 0
         or (t_pv->>'bundle_vouchers_from_settling_payment')::int is distinct from t_vo
         or (t_pv->>'bundle_vouchers_to_choose_from_settling_payment')::int is distinct from 0
         or (t_pv->>'reward_units_from_settling_payment')::int is distinct from 0
         or t_pv->>'explanation' is distinct from t_expl
         or jsonb_typeof(t_rcv) is distinct from 'array' or jsonb_array_length(t_rcv) <> 1
         or (t_rcv->0->>'customer_id')::uuid is distinct from t_a
         or (t_rcv->0->>'customer_name') is distinct from ('478 Check Buyer ' || t_case || ' ' || t_sfx)
         or (t_rcv->0->>'invoice_customer')::boolean is distinct from (t_case not in (5, 6))
         or (t_rcv->0->>'credit_released_on_reopen')::numeric is distinct from t_want
         or (t_rcv->0->>'credit_from_settling_payment')::numeric is distinct from t_later
         or (t_rcv->0->>'bundle_vouchers_from_settling_payment')::int is distinct from t_vo
         or (t_rcv->0->>'credit_to_reinstate_after_settlement')::numeric is distinct from t_back then
        raise exception '478: (%) the Reopen dialog says % at once, % and % vouchers from the settling payment, % after settlement, "%", receivers % (wanted %, %, %, %)',
          chr(96 + t_case), t_pv->>'credit_released_on_reopen', t_pv->>'credit_from_settling_payment', t_pv->>'bundle_vouchers_from_settling_payment',
          t_pv->>'credit_to_reinstate_after_settlement', t_pv->>'explanation', t_rcv, t_want, t_later, t_vo, t_back; end if;
      -- Reopened: A gets what the dialog said it gives at once (and, in (d),
      -- what it reinstates, the reopening settling it at once).
      t_held := (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a);
      perform public.reopen_invoice(t_inv, '478 check', gen_random_uuid());
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      if (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) - t_held
         is distinct from t_want + t_back then
        raise exception '478: (%) the reopening gave A % at once (the dialog said %)', chr(96 + t_case),
          (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) - t_held, t_want; end if;
      -- (a), (b), (e), (f) Paid: A gets what the dialog said the settling
      -- payment gives (in (f) its 2 vouchers too; in (e) and (f) A, not B, the
      -- invoice's customer).
      if t_later > 0 then
        t_held := (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a);
        perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
          'amount', (public.invoice_financial_position(t_inv)->>'outstanding')::numeric)), gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if (select status::text from public.invoices where id = t_inv) <> 'paid'
           or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) - t_held <> t_later
           or (select coalesce(sum(quantity), 0) from public.customer_reward_vouchers where customer_id = t_a and status = 'held') <> t_vo
           or (t_b is not null and ((select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_b) <> 0
                                    or exists (select 1 from public.customer_reward_vouchers where customer_id = t_b))) then
          raise exception '478: (%) paid, A got % and % vouchers (wanted %, %), B holds %', chr(96 + t_case),
            (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) - t_held,
            (select coalesce(sum(quantity), 0) from public.customer_reward_vouchers where customer_id = t_a and status = 'held'), t_later, t_vo,
            (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_b); end if;
      end if;
    end loop;
    raise exception using errcode = 'P0478', message = '478: self-test done, undone';
  exception when sqlstate 'P0478' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
