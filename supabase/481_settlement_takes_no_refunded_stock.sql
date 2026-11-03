-- 481_settlement_takes_no_refunded_stock.sql
--
-- THE PAYMENT THAT SETTLES AN INVOICE (A REOPENED ONE, OR ONE PAID IN PART
-- AND SETTLED LATER) TAKES FROM STOCK ONLY WHAT WAS NOT REFUNDED BY LINE: A
-- PRODUCT LINE REFUNDED BY LINE SINCE THE SALE OR SINCE THE LAST REOPENING
-- IS NOT TAKEN FROM STOCK AGAIN (NO SECOND STORE SALE); THE SAME HOLDS FOR
-- EVERY OTHER WAY AN INVOICE TAKES STOCK FOR ITS LINES (A HAND-OVER BEFORE
-- FULL PAYMENT, A CORRECTION THAT CHANGES ITS STOCK, ITS FULFILMENT FROM A
-- WAREHOUSE), AND invoice_stock_to_deduct NO LONGER REPORTS SUCH UNITS AS
-- STILL TO TAKE (479's NOT COVERED 1; the Owner, 29 Oct 2026, ~18:45 SGT,
-- Q2: "Fix it separately")
--
-- (The number 481 is this file's name, its errors' prefix, its self-test's
-- error code P0481 and its suite's; if it changes at commit, change it in
-- these places alone: the file name, the "481:" messages, P0481, the suite,
-- and the "-- 481 (the Owner" lines the suites find its functions by.)
--
-- WHO FOUND IT
--
--   The review of 479 (29 Oct 2026, each app call committed, on copies of
--   production at 478 and with 479): its NOT COVERED 1 (a product taken from
--   stock again by the payment that settles a reopened invoice) and the side
--   observation PRpd (invoice_stock_to_deduct reporting a unit for a
--   product refunded by line with its stock returned), put to the Owner with
--   479's other questions (THE OWNER'S ANSWERS). Reproduced for this file
--   (30 Oct 2026) on copies of production at 478 (eae7f82f, 1390 functions)
--   and at 478 with 479 (de0b2b08: fbc67a29, 1390 functions), made-up
--   records, the app's own calls, each its own committed transaction: the
--   invoice form (create_invoice_with_details) and the Pay dialog
--   (record_invoice_settlement), Record Payment in full or of an amount,
--   Correct payment (correct_invoice_payment), Cancel, Reopen, the Finance
--   panel's refund by line (of a product line by money, with the stock
--   outcome it asks for: returned and sellable, damaged or not returned; of
--   a credit line; of voucher units; of a therapy line's sessions),
--   "Record refund paid" with no line, the guided Refund in full and Cancel
--   (requested, an Owner approving them), "Hand over items", "Fulfil from" a
--   warehouse, the invoice form's correction moving it to another store; and
--   checked again with this file in. The same cases are this file's suite.
--   Re-based (2 Nov 2026) on production as it was then (485): another
--   session's 483 (31 Oct 2026, with the Owner's go-ahead) changed
--   capture_invoice_stock_components, which this file pinned at its 478
--   text, so that a promotion picked in a choice group (a blind box's prize)
--   records its products as the line's stock components; this file now pins
--   483's text, and was checked with blind boxes on copies of production at
--   485 and at 485 with 479 and this file, each app call committed (WHAT
--   THIS DOES; the suite's BX cases). No function text of this file changed
--   for it: the units a refund by line paid back were already counted from
--   the line's stock components, which since 483 hold the prize.
--   The review of that build (2 Nov 2026, each app call committed, on copies
--   of production at 478 with 479 and 481): the count of whole units lost a
--   unit to the cent where a unit's paid value is not whole cents (3 of the
--   product and 2 vouchers with an Owner's S$30 discount, the product's line
--   S$100.00, S$33.333 a unit: S$66.66 refunded by line, in one refund or
--   two of S$33.33, counted 1 unit, so the payment that settled the invoice
--   took 2 of the 3 though 2 were paid back; S$99.99 counted 2, so 1 went out
--   for the S$0.01 the line still charged; RD1, RD4, RD10, RD11): the
--   half-cent allowance counted once a line, not once a unit. Paid in full,
--   2 units returned with S$66.66 (RD6): 1 still reported to take, and a
--   correction moving the store took it again. This build (2 Nov 2026)
--   counts each unit at its paid value cut down to the cent (WHAT THIS DOES).
--   The same review confirmed two findings for the Owner that change no
--   function text (each by three checks, each app call committed): an Edit
--   Invoice that lowers a line a refund by line paid back (NOT COVERED 13,
--   new), and a settled invoice fulfilled from a warehouse sent again by
--   any move back to paid (NOT COVERED 3, widened). They were re-checked
--   (3 Nov 2026) on copies of production at 486 and at 486 with 479
--   and this file, made-up records, each app call committed, by default,
--   with hash and merge joins off and with nested loops off; the suite
--   checks F1 and E4w3 of them as KNOWN.
--   Re-based (3 Nov 2026) on production as it is now (486, since 2 Nov
--   2026: another session's, the customer merge preview alone, with the
--   Owner's go-ahead): nothing in this file's function texts or pins
--   changed for it (DEPLOY ORDER).
--
-- WHAT WAS WRONG
--
--   What a settlement takes from stock for an invoice's product lines (and
--   the products of its promotion lines) is worked out from the lines'
--   quantities and the invoice's stock movements alone:
--   invoice_stock_to_deduct (the lines less what is out with the customer:
--   the store sales less the returns of a Cancel, of a refund and the units
--   written off), which the payment that settles the invoice takes through
--   deduct_invoice_stock (invoice_record_payments_internal: Record Payment
--   and the Pay dialog), a correction that changes the invoice's stock takes
--   after putting its sale back (correct_invoice), and a hand-over before
--   full payment may take; and, as the backstop for every other way an
--   invoice becomes paid (Correct payment, a correction), what
--   ensure_invoice_stock_deducted takes when the status turns paid (the
--   lines less the sales not put back by a Cancel,
--   invoice_product_net_deducted). A refund by line changes neither figure,
--   so units a refund by line paid back were taken from stock all the same:
--   * Cancelled (the Cancel puts the product back), refunded by line after
--     the reopening, then paid: taken again, a second store sale. VPR: a S$40
--     product and 2 vouchers at S$30, paid, cancelled, 1 voucher refunded by
--     line, reopened, the guided Refund in full (the product's S$40 and the
--     voucher's S$30), paid S$30: A holds 1 voucher, and the product went out
--     again (S$70 of goods for S$30 net). CPR: with a S$100 Credit Package,
--     S$50 of it refunded by line while cancelled, reopened, Refund in full
--     (the product's S$40 and the package's S$50), paid S$50: S$50 of credit
--     and the product for S$50. PRxk (PRxk1 in the review, run at 478; PRxk2
--     the lines written the other way): with 3 sessions, the product's S$40
--     refunded by line while cancelled and again after the reopening, paid
--     S$40: 3 sessions and the product for S$60. PV1: 1 voucher paid back by line while cancelled, reopened,
--     the product's S$40 refunded by line, paid: the voucher and the product
--     for S$30. P3, P1a, P4a, P5a (479's NOT COVERED 17: the guided flows
--     refund a product line refunded before the reopening a second time):
--     after that second refund the payment took the product again.
--   * New with 479 (its guided Refund in full goes through where 478 refused
--     it): the product and 3 sessions, cancelled, 1 session refunded by line,
--     reopened, the Refund in full (the product's S$40 and 2 sessions,
--     either line first), paid S$20: 1 of 3 sessions and the product for S$20
--     (PRn1, PRn2; 478 refused the Refund in full). (PRx1 and PRnl1, the
--     product listed first, reached it with 479's previous build; the rebuilt
--     479 refuses them as 478 does, NOT COVERED 4, so the payment there
--     delivers what the reopening charged, rightly.)
--   * Paid in part (nothing taken yet), the product refunded by line, then
--     paid: taken, though refunded (PRpp: 2 vouchers and the product for
--     S$60). The same where Correct payment settles it (L6), where a
--     warehouse fulfils it (W2: the warehouse sent the product), and for one
--     unit of a line of two refunded S$40 of its S$80 (L7: both taken; M2 the
--     same with two lines of one unit).
--   * Handed over before full payment, then refunded by line (its unit
--     returned), then paid: taken again (H2; H4 a line of two, one handed
--     over). Paid in part, refunded by line, then handed over: allowed, "1
--     still to collect" (H3).
--   * Paid, the product refunded by line with its unit returned as sellable
--     (or written off as damaged): invoice_stock_to_deduct still reported 1
--     unit to take (PRpd; the Goods panel's figures read it), and a
--     correction that changes the invoice's stock (moving it to another
--     store) took it again (PRpds; PRpdd damaged: a second store sale, and
--     invoice_stock_gaps then listing a surplus of 1).
--   No stock report flagged these: once a second sale was made, the sales
--   matched the lines (invoice_stock_to_deduct and invoice_stock_gaps saw
--   nothing). So the customer held products a refund had paid back, and the
--   store's stock was short of them.
--   Production (as given to this builder, 29 Oct 2026): not read for this
--   file then; the header's query (DEPLOY ORDER, step 1) lists any invoice
--   where it happened, for the Owner.
--   Production, 3 Nov 2026 (read only, 486 in, no 479 or 481 row; counts
--   only): the header's query returned no rows (no unit a refund by line
--   paid back since the last reopening or sale was with the customer
--   again or still to take); the warehouse query (NOT COVERED 3) returned
--   no rows; no invoice had "Fulfil from" a warehouse set. Its fingerprint
--   (987d9ea6, 1398 functions), grant list (e68aa1ab), head
--   (20261102143942) and the four BEFORE md5s were as stated below;
--   invoice_refunded_stock did not exist.
--
-- THE OWNER'S ANSWERS
--
--   9 Oct 2026 (417) and 22 Oct 2026 (446, 451): after any sequence of line
--   refunds, cancels, reopenings and settlements the customer holds exactly
--   what the net payment buys. 24 Oct 2026 (462, 463): refunds paid back
--   count as not used. 29 Oct 2026 (~18:45 SGT), asked from the review of
--   479 (its NOT COVERED 1, a product line):
--   Q2, "Fix it separately": a new migration, 481, after 479: the payment
--   that settles a reopened invoice (and, by the same rule, a part-paid
--   invoice that is settled later) takes from stock only what was not
--   refunded by line; a product line refunded since the sale or since the
--   last reopening is not taken from stock again (no second store sale).
--   The cases of the review: VPR, CPR, PRxk, PRxk1, PRpp (already so at
--   478), PRn1, PRn2, PRx1, PRnl1 (new routes with 479), and the side
--   observation PRpd. It goes in after 479 and pins 479's AFTERs. Its
--   header's read-only production query lists (invoice numbers and counts
--   only) any invoice where a product line refunded by line was later taken
--   from stock again, for an Owner decision; no data repair in the file.
--   Also answered then (479's): Q1, "Keep today's refusal" (479, rebuilt);
--   Q3 and Q4 (479's NOT COVERED 15 and 14): leave them documented,
--   unchanged. The standing rules: a cancel or refund takes back what the
--   invoice gave from whoever holds it now; stock moves follow what was
--   really handed over and returned; Correct payment keeps working; no other
--   business rule is changed by guessing (NOT COVERED).
--
-- WHAT THIS DOES (four functions changed, whole texts, and one added; no
-- table, column, trigger or grant of an existing function changed)
--
--   * invoice_refunded_stock(uuid) (new; the server's alone): per line and
--     product, the stock units a refund by line paid back since the invoice
--     was last reopened (or since the sale):
--     - of a product or promotion line, the lines a refund by line asks the
--       stock outcome of (refund_invoice_recorded), counted as
--       invoice_required_stock counts them (not an exchange's replacement
--       line: the exchange took its stock);
--     - its refunds by line since the last reopening, as invoice_charge_total
--       and the refund's own check of the line count them (the reopening
--       charges the line again, so refunds before it count no more), in
--       whole units at the line's paid value (invoice_discounted_line_value):
--       S$40 of a S$40 line is its unit, S$40 of a 2-unit S$80 line one unit,
--       S$10 of a S$40 line none (the line still charges S$30: NOT COVERED 1);
--       a unit whose paid value is not whole cents at that value cut down to
--       the cent, as a refund can only be whole cents (S$66.66 of a 3-unit
--       S$100.00 line, S$33.333 a unit, in one refund or two of S$33.33, is 2
--       units: RD1, RD4; S$99.99 is 3: RD10), never more units than the
--       money pays for at that value, with half a cent to spare (S$99.98 of
--       a 4-unit S$100.00 line is 3 units: RW25);
--     - per product: the line's own (a product line), or each product a
--       promotion line takes (invoice_stock_components where the invoice
--       keeps component snapshots: its fixed contents and its picks, since
--       483 a promotion picked in a choice group, a blind box's prize, among
--       them; its fixed contents and products picked directly otherwise, as
--       invoice_required_stock_legacy counts them, on invoices older than
--       any promotion offered in a choice group), for the units refunded,
--       rounded down;
--     - none on a cancelled or refunded invoice: it charges nothing and takes
--       nothing, and a reopening charges every line again, so what it would
--       take once reopened is what its lines take (the Reopen dialog's "Stock
--       to issue", invoice_reopen_preview, and the reopening itself where the
--       money held settles the invoice at once: as before 481, PRc, L3, RC1);
--     - none on an invoice with no refund at all (most invoices), which it
--       reads first (one index read; plpgsql, so its query is planned once a
--       session).
--   * invoice_stock_to_deduct(uuid): less those units. So the payment that
--     settles the invoice (deduct_invoice_stock), its stock check before it,
--     a hand-over before full payment ("still to collect"), a correction's
--     new deduction and the Goods panel's "To collect" leave them out; the
--     rest as before (vouchers not at all).
--   * invoice_product_net_deducted(uuid,uuid): plus the units refunded by
--     line since the last reopening that the invoice no longer takes (what
--     its lines take less what it took less what invoice_stock_to_deduct
--     says is left, where that is more than 0), counted as taken. So the
--     backstop when an invoice becomes paid by any other way
--     (ensure_invoice_stock_deducted: Correct payment, a correction) does not
--     take them either, and the stock reports (invoice_stock_gaps and
--     repair_invoice_stock_gap, invoice_stock_diagnostic) do not list them
--     as missing; with no such refund, word for word as before.
--   * trg_fulfil_from_warehouse(): the warehouse sends each product line
--     less those units of it, and the store gets back the same (the payment
--     took no store stock for them); a line left with nothing is skipped.
--   * invoice_goods_status(uuid) (the Goods panel): with such a refund, a
--     product's "Collected" is what the customer has of it (out with them,
--     or kept as Not returned), up to what the lines take; otherwise, and
--     every other figure, as before ("To collect" is invoice_stock_to_deduct).
--   On the copies (each app call committed), with 481 in: VPR, CPR, PRxk,
--   PRxk2, PRn1, PRn2, PV1, P3a, P3b, P1a, P4a, P5a: one store sale and the
--   Cancel's return, nothing out, nothing left to take (VPR: 1 voucher for
--   S$30; CPR: S$50 of credit for S$50; PRxk: 3 sessions for S$60; PRn1,
--   PRn2: 1 of 3 sessions for S$20); PRpp, L6: no store sale (2 vouchers for
--   S$60); W2: nothing from the warehouse or the store; L7, M2: 1 unit; H2:
--   the hand-over's sale only; H4: 1 unit out; H3: the hand-over refused,
--   "Only 0 of ... is still to collect"; PRpd: nothing to take; PRpds, PRpdd:
--   the correction takes nothing again. The same, before 481 and after it
--   (controls): a sale paid at once (L1), paid in part then settled (L2), by
--   Correct payment (L5), handed over then paid (H1), fulfilled from a
--   warehouse (W1), cancelled and reopened straight to paid (L3, W3),
--   refunded by line while cancelled, reopened and paid again (L4, PRx1,
--   PRnl1, W4: the reopening charges it again, so it is delivered again), S$10
--   of S$40 refunded (P1b, P5b) or S$20 of a 2-unit line (L8): taken;
--   refunded with the unit Not returned, then the store moved (PRpdn);
--   cancelled with the product refunded (PRc: the Reopen dialog's "Stock to
--   issue" 1) and reopened (PRcb: 1 to collect); Correct payment raising a
--   cancelled invoice's money, then reopened straight to paid (RC1, RC2).
--   Blind boxes (483; 2 Nov 2026, each app call committed, on a copy of
--   production at 485 and on one at 485 with 479 and this file; a S$50 box,
--   prize A two products, prize B two of a third): the box's prize is
--   counted as a product line's unit is. With 481, its S$50 refunded by line,
--   the prize is not taken: paid in part, then settled by Record Payment
--   (BPP), by Correct payment (BFX), with a product picked
--   directly too (BDP: the one summed component), on an invoice fulfilled
--   from a warehouse (BWH: the store gives a promotion's contents, the
--   warehouse product lines only; BWHp: a product line there too, sent by the
--   warehouse as before), two boxes on one line or two box lines, one box
--   refunded (BTW, BTL: one prize taken); handed over, refunded with the
--   prize returned, paid (BHO: the hand-over's sales only), or refunded then
--   handed over (BH3: refused, "Only 0 of ... is still to collect"); paid,
--   refunded with the prize returned (BPD: nothing left to take, before 481
--   its two units), then the store moved (BPDs; BPDd damaged: the correction
--   takes nothing again); reopened straight to paid, refunded, the store
--   moved (BCRs); refunded by line while cancelled and again after the
--   reopening (BXK); the guided Refund in full after the reopening (BVPR); at
--   485 each of these took the prize again. The same before 481 and after it
--   (every key): a box paid at once, in part then paid, by Correct payment,
--   handed over, fulfilled from a warehouse, with a product picked directly,
--   two boxes, the guided Refund in full of a paid box (its prize back),
--   cancelled and reopened straight to paid, refunded while cancelled then
--   reopened and paid (BL4: delivered again), S$25 of the S$50 box refunded
--   (BPart, BTWp: taken, NOT COVERED 1), and Edit Invoice changing the prize
--   (BPC1: not saved, NOT COVERED 11). Two boxes on one line with different
--   prizes, one box's value refunded: NOT COVERED 10 (BMX).
--   A unit whose paid value is not whole cents (2 Nov 2026; this file's
--   suite, and RD1, RD2, RD3, RD4, RD6, RD6s, RD7, RD8, RD10, RD11, RD12,
--   RW67, RW67b, RW25 run on copies of production at 485 with 479: before
--   481, with this file's previous build and with this one): 3 of the
--   product and 2 vouchers with an Owner's S$30 discount (the product's line
--   S$100.00), S$66.66 refunded by line in one refund or two of S$33.33,
--   then paid: 1 unit taken (the previous build 2; before 481, 3); S$99.99
--   in three refunds or one: none taken (the previous build 1); paid in
--   full, 2 units returned with S$66.66: nothing left to take (the previous
--   build 1; before 481, 2), a store move then taking 1 (the previous
--   build 2); S$33.33 of a 2-unit S$66.67 line: 1 unit, as the previous
--   build; S$99.98 of a 4-unit S$100.00 line: 3 units, as the previous
--   build.
--
--   3 Nov 2026, with the go-ahead for 479 and this file: the Owner kept the
--   readings the final checks put to them. A product whose line was
--   refunded by line before full payment can no longer be handed over (H3),
--   and only whole units count (NOT COVERED 1). NOT COVERED 3, "Fix in its
--   own update": a separate update is to send a warehouse invoice's goods
--   once per settlement, and to write no 'sent' row where nothing moves
--   (WT4, WT5, WTF); until it is in, NOT COVERED 3 stands as written. The
--   other open items keep this file's result.
--
-- WHY THIS WAY
--
--   * One rule, read by every way an invoice takes stock for its lines:
--     invoice_stock_to_deduct is what the payment that settles the invoice,
--     the stock check before it, a hand-over, a correction's new deduction,
--     Confirm FOC and the Goods panel read, so taking the refunded units off
--     it there stops every one of them; the backstop and the stock reports
--     read invoice_product_net_deducted, so counting them there as taken
--     keeps the two in step (the backstop never takes what
--     invoice_stock_to_deduct says is not to take), and with no such refund
--     both give what they gave before (proved: what invoice_stock_to_deduct
--     leaves is never less than what the backstop would take, the returns
--     and write-offs it counts including the hand-over's damaged units the
--     backstop counts). The warehouse trigger counts the product lines
--     itself, so it takes the units off itself.
--   * Since the sale or the last reopening, in whole units at the line's paid
--     value: the window invoice_charge_total, the refund's own check of the
--     line and 479 use (a reopening charges every line again, and the money
--     held pays for it, so its settlement delivers it again: L4, PRx1); the
--     money is what a refund by line records of a line it cannot see the
--     stock of (a product not yet taken, or put back by a Cancel); a part of
--     a unit's value refunded leaves the line charging for it, so its unit
--     is still taken (NOT COVERED 1). A unit's paid value that is not whole
--     cents can only be refunded at a whole number of cents, so each unit is
--     counted at that value cut down to the cent (the review of 2 Nov 2026:
--     the half-cent allowance taken once a line lost a unit wherever two or
--     more units were refunded at the cent below their value, and the
--     payment then took it); a unit whose value is whole cents has nothing
--     to round, so a refund short of it by a cent or more does not count it
--     (half a cent allowed per unit regardless would have counted S$99.98
--     of four S$25.00 units as 4).
--   * None on a cancelled or refunded invoice: what is read there is what a
--     reopening would take (it charges every line again), and the reopening
--     takes it before it stamps the new reopening; so the Reopen dialog and
--     a reopening straight to paid are as before (PRc, RC1), and nothing on
--     a cancelled invoice takes stock.
--   * A new function rather than more text in each: four functions read the
--     same units, and the header's query writes the same rule out.
--   * Other ways, not taken: a column or a stock movement recording the
--     units a refund by line paid back (a table change, and a refund of a
--     product not taken has no movement to point at); taking the units off
--     invoice_required_stock (what the lines take: the Goods panel's "On
--     invoice", the hand-over's and a correction's checks, the store change's
--     preview and the promotion reports read it, and the stock reports would
--     then list a surplus wherever a refund by line returned a unit, PRpd);
--     changing what a refund by line or the guided flows refund (a money rule;
--     479's NOT COVERED 17 is open for the Owner).
--
-- NOT CHANGED
--
--   * Pinned (below), unchanged: what reads invoice_stock_to_deduct and
--     invoice_product_net_deducted (deduct_invoice_stock,
--     ensure_invoice_stock_deducted, invoice_record_payments_internal,
--     invoice_handover_internal, correct_invoice, confirm_foc_invoice,
--     give_raised_voucher_units, invoice_reopen_preview_before_sessions,
--     invoice_stock_gaps, invoice_stock_diagnostic, repair_invoice_stock_gap),
--     what the lines take (invoice_required_stock and its legacy form,
--     invoice_stock_components and capture_invoice_stock_components, at
--     483's text: a blind box's prize among a line's components,
--     promotion_stock_items), the line's value and the money's window
--     (invoice_discounted_line_value, invoice_charge_total), the refund by
--     line (refund_invoice_recorded: its lines and their time), Cancel,
--     Reopen and its dialog, what is out with the customer (invoice_goods_out,
--     restore_invoice_stock, the stock returns), the payments and Correct
--     payment, "Fulfil from" (set_invoice_fulfilment_warehouse), 479's three.
--   * The money, the refund options and the guided plans, vouchers and their
--     stock, credit, therapy sessions, commissions, exchanges (an invoice
--     whose money was refunded cannot be exchanged, 408; an exchange's
--     replacement lines are left out as before), transfers, rentals and
--     special products, TikTok orders, Edge Functions, settings.
--   * Pages: none. The Goods panel shows the refunded units as not to
--     collect (NOT COVERED 7); the Pay dialog's words follow its figures.
--
-- NOT COVERED (for the Owner; the suite checks 1 to 5, 8, 10, 12 and 13 as
-- they are and prints them as KNOWN; 11 was checked on the copies, 2 Nov
-- 2026)
--
--   1. Whole units at the line's paid value. A refund by line of less than a
--      unit's value leaves the unit to be taken (the line still charges the
--      rest): S$10 of a S$40 product refunded (the guided plan cut to the
--      money held gave it S$10, P1b, P5b) or S$20 of a 2-unit S$80 line (L8):
--      the product is taken, the customer paying S$30 (P1b) or S$60 (L8) for
--      it. S$40 of the 2-unit line is one unit (L7). A refund by line records
--      money, not units, so this is the rule as asked read in whole units; the
--      Owner may want instead only a line refunded in full to count (L7 then
--      takes both units again), or staff to state the units refunded. A
--      blind box the same: S$25 of the S$50 box refunded, its prize is taken
--      (BXpt; BPart, and BTWp, S$25 of a line of two boxes, on the copies).
--      Cents: a unit's paid value that is not whole cents is counted at that
--      value cut down to the cent (S$66.66 of a 3-unit S$100.00 line: 2
--      units, RD1, RD4; S$33.33 of a 2-unit S$66.67 line: 1, RW67; S$66.66 of
--      it: 2, RW67b), so where all of a line's units are counted the line may
--      still charge a cent or two that no unit stands for (RD10: S$99.99 of
--      the S$100.00 line, all 3 units, S$0.01 still charged; RW67b S$0.01).
--      The Owner may want instead the units stated with the refund.
--   2. A product refunded by line with its unit returned, the invoice then
--      cancelled and reopened (which charges the line again): settled by
--      Record Payment it is delivered again (CPr, as before 481); settled by
--      Correct payment it is not (CPd: the backstop counts the first sale,
--      ignoring the refund's return; invoice_stock_to_deduct reports 1 to
--      take on the paid invoice). Not 481's (the same before it); for the
--      Owner: the backstop could count a refund's returns too.
--   3. Any move back to paid of a warehouse-fulfilled invoice that was
--      already settled sends its goods from the warehouse again (widened
--      from the review of 2 Nov 2026). Not 481's (the same before it); for
--      the Owner. trg_fulfil_from_warehouse, on every change of status to
--      paid (or
--      completed FOC), sends the product lines from the warehouse and gives
--      the store back what the payment took from it, with no test of whether
--      it sent them already. Each repeat leaves the warehouse short and the
--      store over by the product lines' units (from 481 less the units
--      refunded by line since the sale or the last reopening), with no stock
--      movement row, so no stock report lists it; its only trace is another
--      'invoice_fulfilled_from_warehouse' audit row. The total across the
--      warehouse and the stores stays right; the money, credit, vouchers and
--      sessions are not touched. The routes:
--      * Cancel, then Reopen: the Cancel puts the product back into the
--        store, the reopening's settlement (straight to paid, or by a
--        payment) takes it from the store and the warehouse sends it again
--        (W3, W4: the warehouse -2, the store +1, the customer holding 1).
--      * Found by the review of 2 Nov 2026 (three checks) and re-checked (3
--        Nov 2026, on copies of production at 486 and at 486 with 479
--        and 481, made-up records, each app call committed, by default, with
--        hash and merge joins off and with nested loops off: the same in
--        each): a S$40 product, "Fulfil from" the warehouse, paid S$40 (the
--        warehouse -1, the store 0, one send), then
--        - Correct payment of the receipt S$40 -> S$30 (part-paid), then
--          back to S$40 (E4), or the S$10 left paid (E4p);
--        - Edit Invoice correcting the payment to S$30, then the S$10 paid
--          (E4f), or removing the payment, then paid again (E4e); or
--          remove_invoice_payment itself (the server's; correct_invoice
--          calls it for a removal), then paid again (E4x);
--        - paid from wallet credit (Credit Package Paid, the package's
--          spending rules letting its paid credit buy products), then ONE
--          Correct payment of that receipt, even of its date alone (E4w3):
--          correct_invoice_payment sets the invoice partially paid for the
--          credit allocator and back to paid inside the one call, so it never
--          shows anything but paid; two such corrections send it twice more
--          (E4w2: the warehouse -3, the store +2);
--        each ends with the warehouse -2 and the store +1 for one unit sold
--        (one store sale, two sends; in E4w3 S$60 of the S$100 credit left),
--        the same at 486 and with 479 and 481. With a unit refunded by line
--        (E4r: 2 units, S$40 paid, one unit's S$40 refunded by line, the rest
--        paid, then Correct payment -S$10 and +S$10): at 486 the warehouse
--        sends 2 and 2 again (-4, the store +2), with 481 1 and 1 again (-2,
--        +1): 481 takes the refunded units off each send and adds none.
--        Controls: paid once (one send); a cash receipt's date alone
--        corrected (E4m: the status does not move, no send); paid from the
--        wallet once (one send). 409 refuses the same re-send where a
--        rejected guided request would put a warehouse invoice back to paid
--        ("takes its goods from the fulfilling warehouse a second time").
--      For the Owner (the checks' options), in a file of its own: skip the
--      warehouse step when the invoice was already settled since its last
--      reopening (409's test: locked_at or paid_at after reopened_at, or no
--      reopening; paid_at and locked_at stay set while a Correct payment
--      leaves it part-paid, E4), or when it has an
--      'invoice_fulfilled_from_warehouse' audit row since then; or refuse
--      these corrections on a warehouse-fulfilled invoice; or keep this. (A
--      fix in correct_invoice_payment's wallet branch alone would leave the
--      other routes; a test of the old status cannot see the wallet route,
--      whose status changes twice in one call.) Invoices where it happened:
--      the second read-only query (DEPLOY ORDER, step 1) lists them for the
--      Owner's stock adjustment; no record is changed. The suite checks W3,
--      W4 and E4w3 as KNOWN (K3).
--      After 481 the trigger still writes its audit row when every product
--      unit was refunded by line and it sends nothing (found by the final
--      checks, 3 Nov 2026: WT4, WT5 and WTF, sent once, then reopened, the
--      product refunded by the guided Refund in full and the invoice
--      settled again: a second row, nothing sent; WQ1, the product refunded
--      by line while part-paid, settled, then Correct payment down and back
--      up: two rows, nothing sent at all, where 486 sends it twice). 481's
--      stock figures are right; only the row is extra. So that query, run
--      after 481, can list an invoice as sent more than once that needs no
--      adjustment: run it before 481, when it is accurate; run later, read
--      each listed invoice's stock movements and refunds by line before any
--      adjustment. For the Owner: stop writing that row when nothing is
--      sent, in a small follow-up update, or leave it. Production, 3 Nov
--      2026: no invoice had "Fulfil from" a warehouse set, so none has been
--      affected yet.
--   4. 479's NOT COVERED 17 (not 481's, open for the Owner): the guided
--      Refund in full and Cancel refund again, at its value, a product line a
--      refund paid back before the reopening, wherever their plan gives it
--      money and no waiting session (P3a, P3b, P1a, P4a: S$80 refunded on the
--      S$40 line; P5a: S$40 again after S$40 paid back with no line); 478 does
--      the same. 481 changes its stock side, as Q2 asked: the payment that
--      settles the invoice no longer takes the product again, so there the
--      customer ends holding what the net payment buys (the second refund pays
--      back the line's second charge: P3 3 sessions for S$60, P1a and P5a 1
--      voucher for S$30, P4a 3 sessions for S$60). The money rule is unchanged
--      and stays the Owner's: offering such a line again at its full value,
--      and, where the plan is cut to the money held, which item the line order
--      pays back (P1a: the product's S$40 and a voucher; P1b, the vouchers
--      listed first: both vouchers and S$10 of the product, which is then
--      taken for S$30, NOT COVERED 1). Checked
--      for this file (30 Oct 2026, committed, both line orders): NOT COVERED
--      10's product shapes (PRxr, PRx, PRnl, PRxc: the product's S$40 refunded
--      by line, or paid back with no line, while cancelled, reopened, the
--      guided flows) are refused at 478 in both orders ("Settle the reopened
--      invoice before changing its queued sessions"), so 478 does not refund
--      the product a second time there; 479's previous build did (S$80 on the
--      S$40 line, with the product listed first) and the rebuilt 479 refuses
--      them as 478 does. So the second refund there was 479's previous
--      build's, and is stopped; where no session waits it is 478's own
--      (above). The same where the plan is not cut (the fix review of 479, 2
--      Nov 2026: AC, AGC, a package, the sessions and a product refunded by
--      line before the reopening, with S$20 of the package's credit spent;
--      TPr, the sessions and the product alone, S$40 paid again): 479's
--      build before refunded the product again there with the waiting
--      sessions, and 479 now refuses them as 478 does, in either line order;
--      with no sessions at all it is 478's own (ACnC, AGCnC: all the money
--      paid back while a session paid from the package's credit is kept),
--      and 481 changes only its stock side (ACnCp: paid, the product not
--      taken again).
--   5. Promotion lines follow the same rule (each product they take, for
--      their units refunded, rounded down: PRM; PRM2 half refunded, both
--      taken), since 483 a blind box's prize among them (the products of the
--      promotion picked in its choice group: BX1, BX2, BXD, BXF, BXW, BXP); a
--      premium bundle line's stock contents (only on invoices made before
--      component snapshots, which cannot be reopened) are not counted;
--      vouchers are not changed (a limited voucher line cannot be refunded by
--      line before its vouchers are given, "This sold voucher has no
--      source-linked unused/redemption record", LV1, and once given its
--      refund returns their stock itself).
--   6. Invoices where it already happened: no record is changed (the header's
--      query, reason 1, lists them for the Owner: the product with the
--      customer though refunded; recovering it, charging for it or writing
--      it off is the Owner's decision). Reason 1 can also list an invoice
--      whose refunded line a later Edit Invoice lowered (NOT COVERED 13),
--      where nothing was taken after the refund but by that correction, or
--      nothing at all: each listed invoice's revisions and stock history are
--      to be read before a charge, a recovery or a write-off.
--   7. The Goods panel lists a refunded product as "On invoice" with nothing
--      collected and nothing to collect (no "refunded" figure; the page is not
--      changed). "Fulfil from" a warehouse still asks the warehouse to cover
--      the product lines' full quantity, refunded units too (a check only). A
--      promotion line's contents, a blind box's prize among them, come from
--      the store even on an invoice fulfilled from a warehouse (the warehouse
--      sends product lines only), as before 481; a refund by line keeps them
--      from being taken from the store (BXW).
--   8. The promotions' stock report (promotion_stock_gaps, which no page
--      calls) counts a settled invoice's store sales against what its lines
--      take, ignoring returns: a promotion line refunded by line and so not
--      taken (PRM) is listed there as missing its units from 481 (before, the
--      second sale made them match). It already listed promotions whose units
--      came back or were taken twice. Not changed (a report; the Owner may
--      want it to read invoice_stock_to_deduct instead).
--   9. A refund, payment or correction still open when 481 commits finishes
--      on the texts it started with.
--  10. Two or more blind boxes on one line with different prizes (one line
--      of two boxes, prize A picked for one and prize B for the other: 483
--      records both prizes' products as the line's components), part of the
--      line refunded by line (one box's S$50 of the S$100 line): a refund by
--      line records money, not which box, so 481 counts each prize's products
--      in proportion to the boxes refunded, rounded down: 1 of prize B's 2
--      belts is not taken, prize A's two products are (BXM; BMX on the
--      copies): the customer holds prize A and 1 belt for the line's S$50
--      (before 481, prize A and 2 belts). Neither is clearly right: which box
--      came back is not recorded. Any promotion line of several units whose
--      picks differ is counted the same way (before 483 too). For the Owner:
--      staff to say which box (or which picks) a refund by line is for; or
--      count nothing until the whole line is refunded; or keep this.
--  11. Edit Invoice cannot change a blind box's prize (not 481's: found
--      checking 481 with 483, the same at 485 and with 479 and 481). The
--      invoice form sends the line with its id, and the server compares a
--      promotion line's picks by group, product, voucher and quantity, not
--      by the promotion picked (invoice_line_matches), so a changed prize
--      counts as no change: the save goes through and the old prize stays
--      (BPC1: a revision row is written, but the edit count is not raised and
--      the Audit Log has no correction; BPC2, after the box was refunded by
--      line: the same, and with 481 nothing taken). 483's
--      suite changed a prize (its B5) because it sent the line without its
--      id, which writes the line again. For the Owner (another file): compare
--      the promotion picked too.
--  12. More units returned with a refund by line than its money pays for
--      (not 481's: found checking the review's RD6, 2 Nov 2026; the same
--      before 481). The refund records money and, for a product taken from
--      stock, the units it returns; 481 counts the money (whole units at the
--      line's paid value), not the units returned. S$10 of the S$40 product
--      refunded, its unit returned as sellable: the line still charges S$30,
--      so the paid invoice still reports the unit to take (RDp1), and a
--      correction that changes its stock (a store move) takes it again, the
--      stock report then listing a surplus of 1 (RDp2); S$33.33 of a 3-unit
--      S$100.00 line with 2 units returned: 1 unit counted, 1 still to take
--      (RDp3; before 481, 2). Where the money pays for the units returned
--      (RD6: S$66.66, 2 units) nothing is left to take. For the Owner: count
--      the units a refund returns as refunded too (the line then charging
--      for units the customer no longer has), or refuse a return of more
--      units than the refund's money pays for, or keep this.
--  13. An Edit Invoice that lowers a product or promotion line a refund by
--      line paid back since the last reopening: its quantity, unit price or
--      line discount, or the invoice's manual discount (found by the review
--      of 2 Nov 2026, three checks; re-checked 3 Nov 2026 on copies
--      of production at 486 and at 486 with 479 and 481, made-up records,
--      each app call committed, by default, with hash and merge joins off and
--      with nested loops off: each case the same in each). A refund by line
--      records money, not units, so 481 counts its units against the line as
--      it reads after the correction, as invoice_charge_total counts its
--      money; the correction puts back what is out and takes the line again
--      (restore_invoice_stock, then deduct_invoice_stock reading
--      invoice_stock_to_deduct), and a later store move or settling payment
--      reads the same. The money is the same at 486 and with 481 in every
--      case, so what is odd in it was there before 481. Cases (the S$40
--      product):
--      * F1: 3 paid, one unit's S$40 refunded with the unit returned, then
--        the line cut to 2: at 486 the correction takes 2 again (5 store
--        sales, 2 returns of the correction, 1 of the refund: 2 out, the
--        store -2, the stock report a surplus of 1); with 481 it takes 1 (1
--        out, the store -1, the Goods panel 2 on the invoice and 1 collected,
--        nothing listed). Money at both: total S$80, charge S$40, S$80 net,
--        S$40 shown as due back.
--      * E1: 2 paid, one returned with S$40, the line cut to 1: 1 out at 486
--        (a surplus of 1 listed), 0 with 481; at both total S$40, charge S$0,
--        S$40 net and S$40 due back.
--      * G3: F1, then the invoice moved to the other store: the new store -2
--        at 486, -1 with 481.
--      * F1u: F1, then the line put back to 3: at 486 the correction takes
--        the refunded unit again (3 out, a surplus of 1 listed); with 481 2
--        out, as the goods are; at both total S$120, charge S$80, S$80 net,
--        nothing due.
--      * P1: 3 paid, one returned with S$40, then the unit price cut to S$20:
--        nothing moves at either, but with 481 the S$40 now counts 2 units
--        (nothing left to take; at 486 the 1 the refund returned), so a later
--        store move (P1s) takes 1 of the 2 the customer holds, nothing
--        listed, where 486 takes 3 (a surplus of 1 listed). The same with a
--        S$60 line discount or a S$60 manual discount in place of the price
--        cut (LD60, MD60; then a store move, LD60s, MD60s). Money at both:
--        total S$60, charge S$20, S$80 net, S$60 due back.
--      * G1: 2 of the product and a S$40 pair of gloves, S$50 paid, S$40
--        refunded by line on the product's line (nothing out yet), then an
--        Owner's S$60 manual discount added (its reason given), then the S$10
--        outstanding paid: S$20 net at both; 486 takes the 2 products and the
--        gloves (the refunded unit too: Q2's fault); 481 the gloves alone
--        (the S$40 now counts 2 units at S$20 after the discount): right if
--        the discount was for every line, one unit short if for the goods
--        kept.
--      * PP: 3 of the product, S$50 paid, one unit's S$40 refunded by line,
--        the line cut to 2, then paid (S$40 net): 486 hands over 2, 481 1,
--        what the net payment buys at the invoice's values.
--      Controls: F0 (no refund, 3 cut to 2): at both the correction puts a
--      unit back and shows S$40 due back, so the app reads a cut on a paid
--      invoice as a further return; S1 (refunded with the unit returned,
--      then a store move only: PRpds' shape, Q2): 3 out at 486, 2 with 481.
--      So 481's stock follows the money and that reading: right where the cut
--      was a further return; one unit short in the books, and unlisted, where
--      it only tidied the invoice to the units the customer kept, where 486
--      matched the goods by taking the refunded unit again. The header's
--      query (reason 1) lists, at 486, F1, E1, G3, F1u and PP (1 each), G1 (2)
--      and P1, LD60 and MD60 (1 each, with nothing taken after their refunds,
--      which it still lists with 481 in): its caveat, DEPLOY ORDER step 1.
--      For the Owner (the checks' options): refuse, or flag, an Edit Invoice
--      that lowers the quantity or value of a product or promotion line
--      holding refunds by line since the last reopening (a file of its own;
--      the only one that reaches F1, E1 and G3); count a refund's units at
--      the line's per-unit value and quantity when it was recorded (stored
--      with the refund, or read from the invoice's revision in force then), a
--      later cut taking them first (valuing at the refund's time alone
--      reaches the value cuts only: G1, P1, LD60, MD60); or keep this. The
--      suite checks F1 as KNOWN (K13).
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the texts are the tested ones (their AFTER md5s); the four are their
--     BEFORE (production at 478, at 485 and at 486, with 479: replaced, the
--     new one made) or all five their AFTER (left alone), anything else
--     refused; no other function takes their names; who calls each is as
--     read;
--   * the functions they rely on are as read on a copy of production at 485
--     with 479 in (2 Nov 2026, and the same at 486; pinned, below: 479's
--     three AFTERs and 483's
--     capture_invoice_stock_components among them), so 481 goes in after 479
--     and 483 (it refuses on a copy at 478, before 483); the triggers that
--     run the warehouse fulfilment and the backstop as read; the columns
--     read, with these types; what writes a refund (refund_invoice_recorded
--     alone), sets reopened_at (reopen_invoice alone), writes a stock
--     outcome, or names a store sale: as read (30 Oct 2026, and the same at
--     485, 2 Nov 2026, and at 486, 3 Nov 2026);
--   * on the first run nothing is refused for the data (481 needs no decision
--     before it goes in); the invoices of the header's query are named in a
--     notice (invoice numbers only);
--   * who may call each changed function is as read, compared as sets, and
--     kept; the new one: postgres and the service role (never anon or
--     signed-in staff);
--   * afterwards: the AFTER md5s and the grants as tested.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0481, so it leaves no row): a made-up Owner, store, cash method, S$40
--   product stocked nowhere (so no store's stock moves: no stock history
--   row and no sequence is used) and S$30 voucher, customers with fictional
--   ACMA phones no customer has: (a) the product and a voucher, S$40 paid,
--   the product refunded by line, the rest paid: settled with no store sale
--   and nothing to take (before 481 that payment was refused for lack of
--   stock: it would have taken the product), the Goods panel 1 on the
--   invoice, 0 collected; (b) S$50 paid, the product refunded by line:
--   nothing to take or to collect, and handing it over refused ("Only 0
--   of ... is still to collect"); (c) the product alone, S$20 paid: 1 to take,
--   and the payment that would settle it refused for lack of stock, as
--   before; (d) 2 of the product, S$50 paid, cancelled, one unit's S$40
--   refunded by line while cancelled: the Reopen dialog's "Stock to issue"
--   2, as before; reopened (the line charged again): 2 to take again; (e) 3
--   of the product and 2 S$30 vouchers with an Owner's S$30 discount (its
--   reason handed over as the invoice form hands it over; the product's line
--   S$100.00, S$33.333 a unit), S$100 paid, S$66.66 of the product refunded
--   by line: 2 units not to take, 1 to take (the review of 2 Nov 2026:
--   before this build 1 and 2).
--   Locks: the five functions' catalogue rows to the end of the apply, and
--   the rows the self-test writes and undoes; no table is locked against
--   ordinary writes. The self-test takes the commission advisory locks
--   (through its payments, cancel, refunds and reopening) and new invoice
--   numbers, so it waits for any app cancel, refund, correction,
--   commission-writing payment or invoice creation still open, and those
--   wait for it, for under a second. If one stays open longer than the 5 s
--   lock timeout, or an invoice created at the same moment takes the
--   self-test's invoice number, the apply stops, changing nothing, and can
--   be run again. Apply at a quiet time.
--   In the app: the functions changed read, and take no lock beyond what
--   their callers take (the payment, the correction and the hand-over lock
--   the invoice first, as before); the warehouse trigger locks the
--   warehouse's row as before.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (486, 2 Nov 2026: 987d9ea6, 1398 functions; the grant
--   list e68aa1ab, to be compared as sets (370ed899); head 20261102143942)
--   -> 479 (8928dd46) -> 481 (e15db582): 479, then 481, on top of 486.
--   Applied since 478 (29 Oct 2026: eae7f82f, 1390 functions; head
--   20261029060840) by other sessions, each with the Owner's go-ahead, in
--   version order: 480 (cal.com bookings), 483 (a promotion picked in a
--   choice group takes its stock: capture_invoice_stock_components 9f68df58
--   -> a7922878, which 481 pins: re-pinned here, WHO FOUND IT), 482, 484 and
--   485 (the downline's "Came in", My Network's phones, forms' emails), and
--   486 (2 Nov 2026, 22:39 SGT: the customer merge preview,
--   preview_customer_merge f66c9d63 -> b98004c9, one function, no grant);
--   none of them changes another function 481 changes, relies on or reads,
--   or what its catalogue checks read (checked 2 Nov 2026 on copies of
--   production at 485, and again, 3 Nov 2026, at 486: on a copy at 486
--   with the merge preview put back to its text at 485, the public function
--   fingerprint is 485's, d5bcc0ce, and the grant list is the same at both,
--   e68aa1ab).
--   481 pins 479's three AFTERs and 483's capture_invoice_stock_components,
--   so it refuses, changing nothing, before 479 is in, and on a copy at 478.
--   It checks the functions it changes and relies on, not the whole
--   fingerprint, so a later file that changes none of them does not stop
--   it; the fingerprints below are then worked out again on a copy of
--   production as it is (step 2).
--   Files that pinned what 481 changes: invoice_stock_to_deduct (399, 408,
--   416, 417, 434, 451, 457, 464, 474, 478), trg_fulfil_from_warehouse (399,
--   470, 471, 472, 477), invoice_product_net_deducted and
--   invoice_goods_status (399). 481 does not change
--   ensure_invoice_stock_deducted (the backstop); it pins it (3c7ca789), as
--   399 did. Checked (30
--   Oct 2026, each re-run inside begin ... rollback, on copies at 478 with
--   479 and with 481): the re-runs of 399, 408, 416, 417, 434, 438, 446 to
--   448, 451 to 458 and 460 to 479 end the same with 481 in as without it
--   (refused on a pin a later file already moved, or left alone: 452 to 455,
--   465 to 469, 479), but 478's, left alone before 481, refuses once 481 is
--   in (on its pin of invoice_stock_to_deduct), changing nothing; 481's own
--   is left alone; the fingerprint stays the same. Checked again (2 Nov
--   2026, on copies of production at 485, at 485 with 479 and with 479 and
--   481): the re-runs of 478 (as above), 480 and 482 (refused on 484's
--   affiliate_portal_network), 483 and 484 (left alone) and 485 (its
--   functions left alone, its self-test refused on a copy with no store) end
--   the same with 479 and 481 in as without them, 478's as above.
--   1. Before it, read only (invoice numbers and counts only; run on
--      production on 3 Nov 2026: no rows from either query, WHAT WAS
--      WRONG): 1 lists, for the Owner, a product refunded
--      by line since its invoice was last reopened (or since the sale) that
--      is with the customer again (481 changes no record); 2 lists the units
--      whose figure 481 changes (invoice_stock_to_deduct: from 481 not to
--      take):
--     with
--     -- per product or promotion line (as invoice_required_stock counts it), on an
--     -- invoice not cancelled or refunded: the whole units its refunds by line
--     -- since the invoice was last reopened (or since the sale) paid back, at the
--     -- line's paid value, and the products they take (481's rule,
--     -- invoice_refunded_stock, written out: the function is 481's)
--     l as (
--       select i.id as invoice_id, it.id as item_id, it.line_kind::text as lk, it.quantity, it.product_id, it.promotion_id,
--              i.stock_snapshot_version as snap, public.invoice_discounted_line_value(it.id) as worth,
--              coalesce((select sum((x->>'amount')::numeric)
--                          from public.invoice_refunds r cross join lateral jsonb_array_elements(coalesce(r.outcome->'lines', '[]'::jsonb)) x
--                         where r.invoice_id = i.id and x->>'invoice_item_id' = it.id::text
--                           and not coalesce((x->>'overpayment')::boolean, false)
--                           and (i.reopened_at is null or r.created_at > i.reopened_at)), 0) as refunded
--         from public.invoices i join public.invoice_items it on it.invoice_id = i.id
--        where i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
--          and it.line_kind::text in ('product', 'promotion') and it.quantity > 0
--          and (it.price_source is distinct from 'exchange' or not i.is_exchange)),
--     u as (
--       select l.*, least(l.quantity, floor((l.refunded + 0.005)
--                / case when trunc(l.worth / l.quantity, 2) > 0
--                       then trunc(l.worth / l.quantity, 2) else l.worth / l.quantity end))::integer as n
--         from l where l.refunded > 0 and l.worth > 0),
--     c as (
--       select u.invoice_id, s.item_id as product_id, floor(s.quantity::numeric * u.n / u.quantity)::integer as q
--         from u join public.invoice_stock_components s on s.invoice_item_id = u.item_id and s.kind = 'product'
--        where u.n > 0 and u.snap = 1
--       union all
--       select u.invoice_id, u.product_id, u.n
--         from u where u.n > 0 and u.snap is distinct from 1 and u.lk = 'product' and u.product_id is not null
--       union all
--       select u.invoice_id, s.item_id, floor(s.quantity::numeric * u.n / u.quantity)::integer
--         from u cross join lateral public.promotion_stock_items(u.promotion_id, u.quantity) s
--        where u.n > 0 and u.snap is distinct from 1 and u.lk = 'promotion' and u.promotion_id is not null and s.kind = 'product'
--       union all
--       select u.invoice_id, s.product_id, floor(s.quantity::numeric * u.n / u.quantity)::integer
--         from u join public.invoice_promotion_selections s on s.invoice_item_id = u.item_id
--        where u.n > 0 and u.snap is distinct from 1 and u.lk = 'promotion' and s.product_id is not null),
--     -- per invoice and product: the units refunded, what its lines take
--     -- (invoice_required_stock), what is with the customer, not returned or
--     -- written off (invoice_goods_out), and what is out counting the units kept as
--     -- Not returned (its sales less the returns and write-offs, as
--     -- invoice_stock_to_deduct reads them before 481)
--     st as (
--       select f.invoice_id, f.product_id, f.units,
--              coalesce((select sum(r.quantity) from public.invoice_required_stock(f.invoice_id) r
--                         where r.kind = 'product' and r.item_id = f.product_id), 0) as lines,
--              coalesce((select sum(g.quantity) from public.invoice_goods_out(f.invoice_id) g
--                         where g.product_id = f.product_id), 0) as with_customer,
--              coalesce((select sum(case when m.movement_type::text = 'store_sale' then m.quantity else -m.quantity end)
--                          from public.stock_movements m
--                         where m.invoice_id = f.invoice_id and m.product_id = f.product_id
--                           and m.movement_type::text in ('store_sale', 'invoice_cancel_return', 'invoice_refund_return', 'refund_return')), 0)
--                - coalesce((select sum(d.damaged_quantity) from public.invoice_stock_dispositions d
--                             join public.stock_movements m on m.id = d.movement_id
--                            where d.invoice_id = f.invoice_id and m.product_id = f.product_id), 0) as out_
--         from (select c.invoice_id, c.product_id, sum(c.q) as units from c where c.product_id is not null
--                group by c.invoice_id, c.product_id having sum(c.q) > 0) f),
--     found(reason, invoice_id, n) as (
--       -- (1 can also list an invoice whose refunded line a later Edit Invoice
--       -- lowered, its quantity, unit price or line discount or the invoice's
--       -- manual discount, with nothing taken after the refund but by that
--       -- correction, or nothing at all: 481's NOT COVERED 13; read its
--       -- revisions and stock history before a charge, a recovery or a write-off)
--       select '1 for the Owner (481 changes no record): a product refunded by line since its invoice was last reopened (or since the sale) is with the customer again beyond what its lines still charge, taken from stock after its refund (by the payment that settled the invoice, a correction that changed its stock, or a hand-over before full payment) and not returned; from 481 a refund by line keeps its units from being taken (the count is of units)', st.invoice_id, sum(least(st.units, st.with_customer - (st.lines - st.units)))
--         from st where st.with_customer > st.lines - st.units
--        group by st.invoice_id
--       union all
--       select '2 changes: units a refund by line paid back since the invoice was last reopened (or since the sale) that invoice_stock_to_deduct reported as still to take before 481 (the payment that settles the invoice, a hand-over, a correction that changes its stock, or its fulfilment from a warehouse took them); from 481 they are not taken (the count is of units)', st.invoice_id, sum(least(st.units, st.lines - st.out_))
--         from st where st.lines - st.out_ > 0
--        group by st.invoice_id)
--     select f.reason, i.invoice_no, f.n
--       from found f join public.invoices i on i.id = f.invoice_id
--      order by f.reason, i.invoice_no
--      (The DO block below and the suite run this same text.)
--      Reason 1 can also list an invoice whose refunded line a later Edit
--      Invoice lowered (NOT COVERED 13: F1, E1, G3, F1u, PP and G1, and P1,
--      LD60 and MD60 even with 481 in, nothing taken after their refunds):
--      read each listed invoice's revisions and stock history before a
--      charge, a recovery or a write-off (the query's own comment says so).
--      And for NOT COVERED 3 (481 changes no record; invoice numbers and
--      counts only): an invoice sent from the warehouse more than once since
--      it was last reopened, or since the sale (1: each send after the first
--      left the warehouse short and the store over), or more than once in
--      all (2: a reopening's settlement sent it again, or a send under 1
--      came before the reopening), for the Owner's stock adjustment:
--     with
--     -- per invoice, the warehouse's sends: trg_fulfil_from_warehouse writes one
--     -- 'invoice_fulfilled_from_warehouse' audit row each time an invoice with
--     -- "Fulfil from" set moves to paid (or completed FOC); counted in all, and
--     -- since the invoice was last reopened (from the time of its last
--     -- 'invoice_reopened' audit row, which a send by the reopening itself shares,
--     -- one transaction; every row where it was never reopened)
--     s as (
--       select a.record_id as invoice_id, count(*) as sends,
--              count(*) filter (where a.created_at >= coalesce(
--                (select max(r.created_at) from public.audit_logs r
--                  where r.table_name = 'invoices' and r.record_id = a.record_id and r.action = 'invoice_reopened'),
--                '-infinity'::timestamptz)) as since
--         from public.audit_logs a
--        where a.table_name = 'invoices' and a.action = 'invoice_fulfilled_from_warehouse'
--        group by a.record_id)
--     select case when s.since > 1
--                 then '1 for the Owner (481 changes no record): sent from the warehouse more than once since the invoice was last reopened (or since the sale), taken off paid and back by Correct payment, Edit Invoice or a removed payment, or by a Correct payment of a wallet-credit receipt; each send after the first left the warehouse short and the store over by the product lines'' units (from 481 less the units refunded by line) (the counts are of sends: since the last reopening, and in all)'
--                 else '2 for the Owner (481 changes no record): sent from the warehouse more than once in all but at most once since the invoice was last reopened: the reopening''s settlement sent it again (NOT COVERED 3''s Cancel and Reopen), or a send counted under 1 came before the reopening (the counts are of sends: since the last reopening, and in all)' end as reason,
--            i.invoice_no, s.since, s.sends
--       from s join public.invoices i on i.id = s.invoice_id
--      where i.deleted_at is null and (s.since > 1 or s.sends > 1)
--      order by 1, 2
--      (The suite runs this same text, K3. On copies with each app call
--      committed, 3 Nov 2026: E4, E4p, E4f, E4e, E4x, E4w3 and E4r listed
--      under 1 with 2 sends, E4w2 with 3; W3 and W4 under 2, one send since
--      the reopening of two; paid once, a cash receipt's date corrected and
--      a wallet payment alone not listed. In the suite, one transaction,
--      every audit row has the same time, so it checks E4w3, W1 and L1 only.)
--      Run it before 481, when it is accurate. After 481 a send that moves
--      nothing (every product unit refunded by line) still writes its audit
--      row (NOT COVERED 3), so, run later, read each listed invoice's stock
--      movements and refunds by line before any adjustment. On production,
--      3 Nov 2026, it returned no rows, and no invoice had "Fulfil from" set.
--   2. Dry run on a copy of production as it is then: work out its
--      fingerprint and grant list first (they must be the BEFORE figures
--      below, or be worked out again on that copy); apply this file twice;
--      the first run ends at the AFTER fingerprint below, the second
--      changes nothing ("left alone"); and the suite, with the earlier
--      suites below.
--   3. Apply (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself.
--   4. No page change goes with it (NOT CHANGED).
--   Checked for the first build (30 Oct 2026), on copies of production at
--   478 with 479 applied (fbc67a29, 1390 functions), each dropped afterwards:
--   * applied twice: 228bf316, 1391 functions (invoice_refunded_stock
--     added); the second run left alone; every function before it keeps its
--     grants (the list without the new one c05bd82e, as sets 5752c2df), the
--     new one postgres and the service role; the self-test's four cases
--     pass, leaving no row and moving no sequence (every table's row count
--     and every sequence the same before and after), and run alone at 478
--     and at 479 its (a) is refused as the fault predicts ("Insufficient
--     store stock ... Payment blocked": that payment would take the refunded
--     product);
--   * its suite in install mode three times on this text (6 to 7 s, every
--     section passing) and with -v nomig=1 where 481 is in (7 PASS, 6
--     KNOWN); the header's query, its copies the same text (here, the DO
--     block's, the suite's two), read only on the cases' states: before 481
--     it lists under 1 the 23 cases whose refunded product was taken again
--     and under 2 PRpd, after 481 nothing under 1;
--   * the app's calls one by one, each its own committed transaction, on
--     copies at 478, at 479 and with this file (56 cases: those above, NOT
--     COVERED 10's product shapes in both line orders, 17's, the controls):
--     with 481 every case ends as at 479 but for its stock (the stock
--     movements, what is out, what is left to take, the Goods panel, the
--     stock reports) and H3's hand-over, refused; 30 end exactly as at 478
--     (the controls, the refused shapes in both orders, the partial refunds,
--     the known ones), the 26 others with no store sale of a unit a refund by
--     line paid back since the sale or the last reopening; at 479 only PRn1
--     and PRn2 differ from 478 (479's route);
--   * the re-runs above (DEPLOY ORDER);
--   * 225 suites (begin ... rollback, -v nomig=1 and skip_install=1: every
--     scripts/*/tests file that starts and rolls back a transaction, and
--     invoices/regression.sql) on a copy at 479 and on one with this file:
--     224 end exactly the same (exit code, PASS, KNOWN and FIXED counts,
--     first error), among them 479's, 478's, 477's, 476's, 475's, 474,
--     471, 470, 463, 462, 461, 460, 458, 451, 448, 447, 446, 438 and 417's,
--     every invoice-actions, credit-policy and customer-merge suite, the
--     therapy, stock, stock history, stock-in, stock loans, transfer, rental,
--     exchange and voucher-claim suites and permissions' staff-only-functions,
--     role-guards and rls-policies; the one meant to differ is this file's
--     suite (refused at its start without 481; with it, every section
--     passing); 457's and 464's suites pass on both once their pin of
--     invoice_stock_to_deduct also accepts 481's AFTER, and 479's once its
--     product cases' stock expectations follow 481 where it is in (and its
--     K10 check reads the line order its case ran with; read again later,
--     the order is not fixed); 63 fail on both at the same first error, as
--     before (fixtures or seeds a schema-only copy lacks, or their own
--     install's pins of an earlier stack); with an app settings row added in
--     the same rolled-back transaction (a schema-only copy has none), the
--     exchanges' money-and-stock and commission suites pass on both, the
--     same. (The machine slept during the run; the two suites that ran out
--     of time on both copies then, 471's and 479's, were run again on fresh
--     copies: the same on both.)
--     permissions' function-grants read only: anon 5 signed-out endpoints,
--     staff 490 functions, as before 481 (the new one is the server's);
--   * the page tests (node --test, every scripts/*/tests/*.test.mjs; 481 has
--     no page change): 1314 of 1316 pass, 1 skipped, and the one failure
--     needs a database of its own (voucher-claims' migration-compilation),
--     as before.
--   Cost, on a copy holding the 56 cases' records: invoice_stock_to_deduct
--   of an invoice with no refund 0.15 -> 0.24 ms a call, with refunds 0.15
--   -> 0.45 ms; invoice_product_net_deducted 0.06 -> 0.12 ms and 0.06 ->
--   0.87 ms (it reads the lines and what is left to take once a refund by
--   line is found); invoice_stock_gaps over the copy's 56 invoices 3 ->
--   34 ms; the suites above took the same time with 481 as without it.
--   (Those copies had capture_invoice_stock_components at its 478 text,
--   9f68df58, as this file pinned it then.)
--   Re-checked for the re-base of that build (2 Nov 2026), on copies of
--   production at 485 with 479's previous build applied (bda210db, 1398
--   functions), each dropped afterwards:
--   every function it changes or relies on as pinned (483's
--   capture_invoice_stock_components a7922878; the rest as on 30 Oct 2026);
--   applied twice: 3d476df5, 1399 functions (invoice_refunded_stock added),
--   the second run left alone; every function before it keeps its grants
--   (the list without the new one e68aa1ab, as sets 370ed899), the new one
--   postgres and the service role; the self-test's four cases pass, every
--   table's row count and every sequence as before; its suite in install
--   mode on this file (every section passing: 11 PASS, 7 KNOWN; with the
--   blind box cases, 7 fixed, 2 controls, 1 known) and with -v nomig=1
--   where 481 is in (7 PASS, 7 KNOWN); the 31 blind box cases of WHAT THIS
--   DOES, each app call committed, on a copy at 485 and on one with 479 and
--   481: 17 with no store sale of a prize refunded by line (only their stock
--   figures differ, and BH3's hand-over is refused), 14 exactly as at 485,
--   every key; 483's suite the same with 479 and 481 in as without them;
--   the re-runs (DEPLOY ORDER); the 47 suites of 479's re-check (40 exactly
--   the same, 5 only in random values, a timestamp or a print order, 479's
--   and 475's as meant); function-grants read only at 485, with 479 and with
--   479 and 481: 491 staff functions, invoice_refunded_stock callable by
--   neither anon nor signed-in staff (in its list of internals since this
--   re-base; granted to staff, the test names it). Not re-run at 485: the
--   page tests (481 has no page change), the cost figures and the full
--   sweep.
--   Checked for this build at 486 (3 Nov 2026: the re-base onto production
--   at 486, and NOT COVERED 3, widened, and 13, new, from the review of 2
--   Nov 2026; nothing in 481's function texts or pins changed, only this
--   header, a comment in its header's query (the same in each of its four
--   copies) and its suite: its fingerprint pair, the pair at 485 still
--   accepted, F1 and E4w3 as KNOWN, the second query), on copies of
--   production at 486 (rc486_live: 987d9ea6, 1398 functions; grants
--   e68aa1ab, as sets 370ed899), each dropped afterwards: with the merge
--   preview put back to its text at 485 the fingerprint is 485's, d5bcc0ce,
--   and the grant list the same, so 486 changed no other function and no
--   grant; 479 then this file applied, each twice (8928dd46, 1398
--   functions, then e15db582, 1399; the grant list unchanged by 479, then
--   0f4b7be6, as sets 80e531b7, every function before 481 keeping its grants
--   and the new one postgres and the service role; each second run left
--   alone; every table's row count and every sequence as before each apply,
--   the self-tests' rows undone); its suite in install mode on a copy with
--   479 by default, with hash and merge joins off (11 PASS, 9 KNOWN each,
--   the same notices word for word; 12 and 20 s) and with nested loops off
--   (11 PASS, 9 KNOWN, 46 s: P1b, P5b and P4b listing the product first,
--   each as expected for it), and with -v nomig=1 on a copy with 479 and
--   481 (7 PASS, 9 KNOWN); NOT COVERED 3's and 13's cases (29, F1 and E4w3
--   among them), each app call committed, at 486 and with 479 and 481, by
--   default, with hash and merge joins off and with nested loops off: each
--   case the same in every setting, the money the same at both (F1 and E4w3
--   have one product line each, so no line order to vary); the two
--   read-only queries, their copies the same text; permissions'
--   function-grants read only at 486, with 479 and with 479 and 481 (6
--   signed-out endpoints, 491 staff functions); the customer-merge suites
--   (486's merge-guard-486 among them, with -v skip_install=1; 445's with -v
--   nomig=1) and the other suites 486's commit edited (event-website 439
--   and 441 and affiliate-network-phone-484, with -v skip_install=1), each on
--   a copy at 486 and on one with 479 and 481: the same exit code and the
--   same PASS lines on both, but for random fixture values (referral codes,
--   email suffixes, phones), the order an unordered list prints (445's B3)
--   and the number of functions (1398 -> 1399, 481's); phone-capture-stays
--   fails on both at the same first error (a commission with no rate: a
--   setting a schema-only copy lacks). The final checks of this build (3
--   Nov 2026, on this file before its header was last corrected, 22c7ac20:
--   only comments changed since), on fresh copies of production at 486,
--   each dropped afterwards:
--   * 479 then this file applied twice each: e15db582 (1399); each second
--     run left alone; row counts and sequences as before (the self-test
--     made 5 invoices and called invoice_refunded_stock 20 times each run);
--     the same with a settings row like production's (staff commission 3%);
--   * a schema diff (pg_dump -s of every schema; every function's md5 and
--     grants): only the four bodies changed and invoice_refunded_stock was
--     added (postgres and the service role). Every function that calls it
--     (invoice_stock_to_deduct, invoice_product_net_deducted,
--     invoice_goods_status and trg_fulfil_from_warehouse, the warehouse
--     trigger) is SECURITY DEFINER, owned by postgres, so whatever a
--     signed-in user calls that leads to it runs it as postgres (the Goods
--     panel, the Pay dialog, Correct payment, Edit Invoice, Confirm FOC, a
--     hand-over, Reopen and its dialog among them): staff lose nothing;
--   * its suite in install mode on a copy with 479 (11 PASS, 9 KNOWN, by
--     default and with hash and merge joins off) and with -v nomig=1 (7
--     PASS, 9 KNOWN); 457's and 464's edited suites at 486 and with 479 and
--     481 (71 and 46 PASS);
--   * 125 cases (the suite's 75 and 50 more: cents, blind boxes, Edit
--     Invoice, warehouse resends, a warehouse or a box with sessions), each
--     app call committed, in 10 runs (486 four times, with 479 twice, with
--     479 and 481 four times): 48 the same, 65 only in stock, 12 changed on
--     purpose (PRn1, PRn2, H3 and 9 new combinations); every control and
--     known case as at 486 but F1 (NOT COVERED 13). Cents: RD1 takes 1 unit
--     where 486 takes 3, RD10 none. Blind boxes: the prize is not taken
--     again (BX1, BXT1), two prizes count in proportion (BXM), no stock
--     surplus is listed (BXHd). Warehouses: nothing sent for a refunded unit
--     (W2, WT8); NOT COVERED 3's resends less the refunded units (E4r: 2
--     sent, 4 at 486). The same 4 cases follow the line order at 486 and
--     with 479 and 481;
--   * on settled invoices with no discount, bundle, merge or spent credit,
--     across the final checks' committed runs (not these 125 cases alone:
--     479's cases are among them), the customer holds what the net payment
--     buys in 536 of 556 runs with 479 and 481 (the 20 others documented:
--     P1 and P5, NOT COVERED 1; 479's PRT, its NOT COVERED 2), and in 101 of
--     172 at 486;
--   * old invoices made before component snapshots, which the suite does
--     not reach (LG1, refunded by line while part-paid, then paid; LG2, a
--     promotion; LG3, handed over, refunded, paid): no refunded unit taken
--     (486 took 1, 2 and 1 more), the header's query and
--     invoice_refunded_stock counting the same units;
--   * the warehouse query after 481 (WQ1; WT4, WT5, WTF): NOT COVERED 3;
--   * the go-live rehearsal (479's DEPLOY ORDER): the first payment after
--     481 takes no refunded unit, and a hand-over of a refunded unit is
--     refused (GS7);
--   * the re-runs of the earlier files (479's DEPLOY ORDER: 478 refused
--     once 481 is in; 481 refused at 486 and left alone once in); 399's
--     part-paid-handover suite (94 PASS), 410's status-refresh (33) and
--     423's split-replay (35), run without their stale installs: the same
--     at 486 and with 479 and 481; the full sweep, the 135 suites with a
--     settings row and the page tests (1359 of 1361): as 479's DEPLOY
--     ORDER says;
--   * cost: invoice_stock_to_deduct 0.18 ms a call at 486, 0.24 ms with
--     481; invoice_product_net_deducted 0.07 ms, 0.46 ms where refunds
--     exist; invoice_stock_gaps over 22 invoices 3.7 ms.
--   Not shown: behaviour at production's data size; the apply itself (the
--   CLI or the MCP); anything past the first error of the suites that
--   still stop there on a schema-only copy.
--   Checked for this build at 485 (3 Nov 2026, before the re-base onto 486:
--   nothing in 481's own text
--   changed but 479's refund's AFTER, which it pins, now 35d3f1ba (479's
--   third fix review: where only the session's line has anything to refund,
--   at its turn and in the plan the request saved, the guided flows go
--   through again as answer F asked), and this header), on copies of
--   production at 485 with 479 applied (5695d246, 1398 functions), each
--   dropped afterwards: applied twice (20ef063d, 1399 functions; the grant
--   list 0f4b7be6, as sets 80e531b7, every function before it keeping its
--   grants; the second run left alone; the self-test's five cases pass,
--   every table's row count and every sequence as before); its suite in
--   install mode (11 PASS, 8 KNOWN) and with -v nomig=1 on a copy with 479
--   and 481 (7 PASS, 8 KNOWN); the 192 cases of 479's suite, each app call
--   committed, by default and with nested loops off, at 485, with 479's
--   build before and this 481 and with this build of both, as 479's DEPLOY
--   ORDER says (481's effect, as with the build before: the stock of VPR,
--   PRxk, PRpp, P3, P1, P4 and P5, a product's line refunded and the
--   invoice then settled); the 56 suites of 479's check for this build, each
--   on a fresh copy at 485 and on one with 479 and 481 (45 exactly the same,
--   the others only as 479's DEPLOY ORDER says).
--   Not re-run for this build at 485 (the final checks ran them at 486,
--   above): the cent cases, the blind box cases, the cost figures, the
--   re-runs, the full sweep and the page tests (481 has no page change).
--   Checked for the build before this one (3 Nov 2026: nothing in 481's own
--   text changed but 479's refund's AFTER, which it pins, then 2c6ace5b
--   (479's second fix review: the plan a guided request saved is read also
--   where no other line offers anything at the session's turn), and this
--   header), on copies of
--   production at 485 with 479 applied (270aa323, 1398 functions), each
--   dropped afterwards: applied twice (41f202f2, 1399 functions; the grant
--   list 0f4b7be6, as sets 80e531b7, every function before it keeping its
--   grants; the second run left alone; the self-test's five cases pass,
--   every table's row count and every sequence as before); its suite in
--   install mode (11 PASS, 8 KNOWN) and again with hash and merge joins off
--   (the same notices word for word), and with -v nomig=1 on a copy with
--   479 and 481 (7 PASS, 8 KNOWN); the 177 cases of 479's suite, each app
--   call committed, in three planner settings, at 485, with 479's build
--   before and this 481 and with this build of both, as 479's DEPLOY ORDER
--   says (481's effect, as with the build before: the stock of VPR, PRxk,
--   PRpp, P3, P1, P4 and P5, a product's line refunded and the invoice then
--   settled); the 54 suites of 479's check for this build, each on a fresh
--   copy at 485 and on one with 479 and 481 (51 exactly the same, the
--   three others only as 479's DEPLOY ORDER says).
--   Not re-run for that build: the cent cases, the blind box cases, the cost
--   figures, the re-runs, the full sweep and the page tests (481 has no page
--   change).
--   Checked for the build before that (2 Nov 2026, late: nothing in
--   481's own text
--   changed but 479's refund's AFTER, which it pins, then b02dcb46, and this
--   header), on copies of production at 485 with 479 applied (ca96dde5,
--   1398 functions), each dropped afterwards: applied twice (7987f0d2, 1399
--   functions; the grant list 0f4b7be6, as sets 80e531b7, every function
--   before it keeping its grants; the second run left alone; the self-test's
--   five cases pass, every table's row count and every sequence as before);
--   its suite in install mode (11 PASS, 8 KNOWN) and again with hash and
--   merge joins off (the same notices), and with nested loops off (11 PASS,
--   8 KNOWN: P1b, P5b and P4b listing the product first, each as expected
--   for it); with -v nomig=1 on a copy with 479 and 481 (7 PASS, 8 KNOWN)
--   and again with the refund options' lines planned by hash joins (the
--   same, P1b, P5b and P4b the product first); its readings of the Goods
--   panel and of the stock report ('goods', 'gap') now sorted, as their
--   order is not fixed (the expectations of BX1 to BXM and K10 written
--   sorted); the cases of 479's suite and 71 more, each app call committed,
--   in three line orders, as 479's DEPLOY ORDER says (481's effect: the
--   stock of P1a, P1b, P4a, P4b, P5a, P5b, P3, P3b, ACnCp, PRn1, PRn2, VPR,
--   PRxk, PRpp and of 479's answer F cases settled after a guided refund of
--   the product's line); the 39 suites and function-grants of 479's check,
--   on copies at 485 and with 479 and 481. Not re-run for that build: the
--   cent cases, the cost figures, the re-runs, the full sweep and the page
--   tests (481 has no page change).
--   Checked for the build before those (2 Nov 2026: a unit counted at its
--   paid value cut down to the cent; 479's AFTERs of then pinned), on copies
--   of production at 485 with 479 applied (082badac, 1398 functions), each dropped
--   afterwards: applied twice (ff40ea0a, 1399 functions: invoice_refunded_
--   stock added, its AFTER f12af401; the other four at the AFTERs above,
--   unchanged), the second run left alone; every function before it keeps
--   its grants (without the new one e68aa1ab, as sets 370ed899; with it
--   0f4b7be6, as sets 80e531b7), the new one postgres and the service role;
--   the self-test's five cases pass (its (e) the review's case: 2 units not
--   to take, 1 to take), every table's row count and every sequence as
--   before; the header's query, its copies the same text (here, the DO
--   block's, the suite's two); its suite in install mode on this file (every
--   section passing: 11 PASS, 8 KNOWN, K12 new) and with -v nomig=1 with 479
--   and 481 in (7 PASS, 8 KNOWN); the cent cases RD1 to RD12, RW67, RW67b,
--   RW25 (WHAT THIS DOES) at 485 with 479, with this file's previous build and
--   with this one; the re-runs and the sweep of 479's check for this build
--   (230 suites, the last 108 each on a fresh copy: none fails only with 479
--   and 481; the three meant to differ: 479's, this file's and 475's);
--   function-grants read only (6 signed-out endpoints, 491 staff functions,
--   invoice_refunded_stock callable by neither anon nor signed-in staff).
--
-- BEFORE (production at 486 with 479 in, as on its copy, 3 Nov 2026: the
-- same as at 485 with 479 (486 changed the merge preview alone), and as at
-- 478 with 479, 30 Oct 2026, but capture_invoice_stock_components, 483's
-- since 31 Oct 2026; md5 of pg_get_functiondef with search_path public)
--   changed
--   invoice_stock_to_deduct(uuid)                                       6356494ccb8545d46c56b788f8f85f54
--   invoice_product_net_deducted(uuid,uuid)                             f6288d8eb44af4cd4dbed11f63d3427a  (399's)
--   trg_fulfil_from_warehouse()                                         4abf4bf68e4f00658a8da66469e7059e
--   invoice_goods_status(uuid)                                          651039eac932b5d1f51fc75313ed4320  (399's)
--   added
--   invoice_refunded_stock(uuid)                                        (none)
--   relied on, not changed (pinned)
--   invoice_required_stock(uuid)                                        c91dc1eb4f2b7b465de5fe4a8fb2ca0c  (what the lines take (408's))
--   invoice_required_stock_legacy(uuid)                                 2e0bc2497901c2690a74205bdd3a0a5f  (the same without component snapshots)
--   promotion_stock_items(uuid,integer)                                 82dd6bdac5566fce0b75470eb45444d1  (a promotion's fixed contents)
--   capture_invoice_stock_components()                                  a7922878b6b73925de975bb7fa51ea1d  (the component snapshots: 483's AFTER, a pick's promotion recorded with what it holds; was 9f68df58 at 478)
--   invoice_discounted_line_value(uuid)                                 ead4a430c3abd1e3f953912867ca4fe6  (a line's paid value)
--   invoice_charge_total(uuid)                                          8297147511ba285db2279598f3d727fb  (the refunds' window)
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)           804ecd829cfecf713783a09a05d93c7e  (the refund by line: its lines, their time, the stock outcome)
--   deduct_invoice_stock(uuid,text)                                     32183fe9e7c15ed0b11307c48289831a  (takes what invoice_stock_to_deduct says)
--   ensure_invoice_stock_deducted(uuid,text)                            3c7ca7893f359f380a340cec07f21a1f  (the backstop (152's, pinned by 399; reads invoice_product_net_deducted))
--   trg_guarantee_invoice_stock()                                       b4d922c6238f50137941a85a590600c8  (runs the backstop when an invoice is settled)
--   invoice_record_payments_internal(uuid,jsonb)                        21890d84bcb0b9c00a2bc98aff313d0b  (the payment that settles: its stock check and deduction)
--   record_invoice_payment(uuid,jsonb,uuid)                             9c70097ed4da614fb9dcc66fdfcdb7d6  (Record Payment (and the self-test))
--   record_invoice_settlement(uuid,jsonb,uuid)                          8c8778af82899c6aaada62371d13802f  (the Pay dialog)
--   correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)           af99337094edb6d73b9cc0ae00fbf138  (Correct payment)
--   invoice_handover_internal(uuid,jsonb,uuid,text,uuid)                51f5adaddbe447e8fcbeaabab03a054a  (the hand-over before full payment (399's))
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                         04d647e13e9424a9375942e5812e91a2  (a correction's stock)
--   confirm_foc_invoice(uuid,text)                                      ba8b1ce2a5671989b927891f0cb7b1a2  (Confirm FOC)
--   give_raised_voucher_units(uuid,uuid[],boolean,text)                 84d4c7bbd39a754d61cbe4f778777a33  (reads the voucher rows only)
--   reopen_invoice(uuid,text,uuid)                                      30066e137b9b75b5789a050c14debc04  (takes stock before it stamps reopened_at (475's AFTER))
--   invoice_reopen_preview(uuid)                                        e09ebf9c0841ef5463f96b26f4933541  (the Reopen dialog)
--   invoice_reopen_preview_before_sessions(uuid)                        acbfc38a20a000e1af0e78d26fc7fc4c  (its "Stock to issue" (478's AFTER))
--   cancel_invoice_recorded(uuid,text,uuid)                             de52d9dbaef8ab15163bef35cb9d733d  (Cancel)
--   restore_invoice_stock(uuid,text)                                    092316c3af22361f80d186e38fe49bf3  (what Cancel and a correction put back)
--   invoice_goods_out(uuid)                                             15ffed0ff0d5d9cc5685af8e834302ae  (what is out with the customer (399's))
--   invoice_before_full_payment(uuid)                                   532d7690367fc674737b20420e7fb16c  (the Goods panel's "open")
--   record_invoice_stock_return(uuid,jsonb,text,uuid)                   6b125cb5df1eb103781662bef41e9417  (a stock return)
--   record_invoice_goods_return(uuid,jsonb,text,uuid)                   e1a3242f7bfc66fb4f6ea162d823137f  ("Record items returned" (399's))
--   set_invoice_fulfilment_warehouse(uuid,uuid)                         66bf7f38e06bf48116b63b71ca7663cb  ("Fulfil from")
--   invoice_stock_gaps(text,uuid,date,date)                             109e846c4e4f3bac3b5e374ebf44bcb7  (the stock report)
--   invoice_stock_diagnostic(text)                                      dbc65c84b70ed1fe67eebe5602ae1332  (the stock diagnostic)
--   repair_invoice_stock_gap(uuid,boolean)                              8c9a1d837da6e4326f00b11d41127090  (the gap repair (calls the backstop))
--   refund_invoice_therapy_sessions(uuid,numeric,text,uuid)             35d3f1ba4c906a66a8deb131c777dab8  (479's AFTER)
--   correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid)    32df6441a3f5e37e164b1279f8dc502b  (479's AFTER)
--   trg_create_therapy_sessions_on_paid()                               15f4bbc260e53ba538debc0947082f43  (479's AFTER)
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)        80c80d386a5241e63b353e35e13ef250  (the self-test)
--   set_product_prices(uuid,uuid,numeric,numeric,text)                  aef4792013bc3a56f8ee62bc1a7d686a  (the self-test)
--   invoice_financial_position(uuid)                                    ba7eccbfeff217c8b1969b0e55a010ca  (the self-test)
--   invoice_net_received(uuid)                                          f256bea69b7defa38a950753bbc248da  (the self-test)
--   normalize_customer_phone(text)                                      b2bfac910e0c9eff402ba44e19750bee  (the self-test)
--   is_owner_or_manager()                                               a98e50f1b6d3fa1e6c62cf52a8073cc8  (the refund's and the reopening's guard)
--   user_has_store_access(uuid)                                         708992afaa6c3951f6329239b742987c  (the Goods panel's guard)
--   trg_invoice_manual_discount_reason()                                bfed9e779a89ed9b149b6be80217775a  (the self-test's (e): the reason handed over)
--   public function fingerprint, production now (486, 2 Nov 2026)      987d9ea60beaec88fb6146d3db6f9441 (1398 functions)
--   the same with 479 in (its copy, 3 Nov 2026)                         8928dd465d7bfd1125d42a983735e226 (1398 functions)
--     (at 485, 2 Nov 2026: d5bcc0ce, with 479 5695d246 (3 Nov 2026; with 479's previous builds bda210db, 082badac,
--      ca96dde5, 270aa323); at 478, 30 Oct 2026: eae7f82f, with 479 fbc67a29, 1390 functions; 481 now refuses there,
--      on 483's pin)
--   grant list (string_agg(signature '=' proacl, '|'), sorted)          e68aa1abc012f3e4539dd315b96a1ea1 (production at 486 and its copy, the same at 485; 486 and 479 change no grant); as sets
--                                                                      (each proacl's items sorted) 370ed89994c39b2d544b3d39a26412d2
--                                                                      (at 478: c05bd82e, as sets 5752c2df)
--                                                                      (compare as sets: the same grants may be listed in another order)
-- AFTER (for later guards)
--   invoice_stock_to_deduct(uuid)                                       5480e6042b4521829ebce1ef14937162  (grants kept)
--   invoice_product_net_deducted(uuid,uuid)                             e42acff8d87d5d2299159fa9ce6805ae  (grants kept)
--   trg_fulfil_from_warehouse()                                         e1d41bce9c53d21ac2ab727042663cfb  (grants kept)
--   invoice_goods_status(uuid)                                          ca966a2c6a1949afc98503862263b58d  (grants kept: signed-in staff too)
--   invoice_refunded_stock(uuid)                                        f12af401547ce01e2b95ec3a5c230bad  (postgres and the service role)
--   public function fingerprint, worked out on copies of production at 486 with 479 (3 Nov 2026, rc486_live; a second run the same):
--     486 -> 479 -> 481                                                e15db5824bcbea2c4001b047ba151389 (1399 functions: invoice_refunded_stock added)
--     (at 485 with 479, 3 Nov 2026: 20ef063d; with 479's previous build 270aa323: 41f202f2; with its build ca96dde5: 7987f0d2; with its build 082badac: ff40ea0a; this file's previous build, invoice_refunded_stock 0a11e8c2, with 479's build before that: 3d476df5;
--      at 478 with 479, 30 Oct 2026: 228bf316, 1391 functions)
--   grant list after 481                                               0f4b7be625fb254e90a0efc361334dfe (as sets 80e531b7413d32e1529c0c304ad2d95d; the same at 486 and at 485): every function before it keeps its grants (without the new one: e68aa1ab, as sets 370ed899); the new one postgres and the service role
--     (at 478 with 479: 8ff91fbc, as sets b47e5f59)
--
-- UNDO (with the Owner's go-ahead; before 479's UNDO: 481 was built and
-- checked only on top of 479)
--   Before the apply, save the four functions' texts from production
--   (pg_get_functiondef, search_path public); each md5 must be its BEFORE
--   one. To undo, in one transaction: stop unless the five functions are
--   at their AFTER md5s; put each BEFORE text back (the saved text):
--   invoice_stock_to_deduct 6356494c is 184's (its CREATE OR REPLACE
--   statement gives that md5); invoice_goods_status 651039ea is 399's (its
--   c_status_def statement gives that md5); invoice_product_net_deducted
--   f6288d8e and trg_fulfil_from_warehouse 4abf4bf6 are 399's AFTERs,
--   made by editing the texts before them, so no statement in that file
--   holds them whole. CREATE OR REPLACE keeps the grants and the trigger.
--   Then drop invoice_refunded_stock(uuid), which no function calls once
--   the four are back, and delete 481's row in
--   supabase_migrations.schema_migrations, guarded on
--   md5(array_to_string(statements, '')) being this file's md5 as applied.
--   Checked 3 Nov 2026 on a copy of production at 486 with 479 and 481 in:
--   the fingerprint is 8928dd46 (1398 functions) again, as with 479 alone,
--   and the grant list e68aa1ab.
--   Undone, the figures before 481 come back for every invoice, those
--   settled under 481 too (WHAT WAS WRONG). Run the header's query first:
--   its reason 2 lists the units a refund by line paid back that those
--   figures read as still to take.
--
-- Test: scripts/invoices/tests/refunded-stock-not-taken-481.sql
-- (begin ... rollback; it installs this file twice; -v nomig=1 where it is
-- in; on a copy of production at 486 with 479, or at 485 with 479). It
-- reproduces the cases before 481 (the units taken), then checks the
-- header's query, the refusals of this file, the install, every case after
-- 481 (what each takes from the store and the warehouse, what is out, what
-- is left to take, the Goods panel, the stock reports, the money), a blind
-- box's prize (483) as a product line's unit (the BX cases), the controls
-- exactly as before 481 (every key), the four texts beside 481's parts
-- exactly as before (worked back, by md5), the header's query's rule equal
-- to invoice_refunded_stock, and NOT COVERED 1 to 5, 8, 10, 12 and 13 as
-- KNOWN (3 with E4w3 and the second read-only query, 13 with F1). Each app
-- call is followed by what its commit does (462's trigger is deferred); the
-- cases were also run with a real COMMIT after every app call, on copies of
-- production at 478, with 479 and with this file (30 Oct 2026), the blind
-- boxes on copies at 485, with 479 and this file (2 Nov 2026), and NOT
-- COVERED 3's and 13's on copies at 486 and with 479 and this file (3 Nov
-- 2026). Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The functions this changes: BEFORE (production at 478 with 479 in, 30
  -- Oct 2026, and at 485 with 479 in, 2 Nov 2026, as on their copies) and
  -- AFTER md5s; who may call each, as read (kept) ═══════════════════════════
  c_sigs constant text[] := array[
    'invoice_stock_to_deduct(uuid)',
    'invoice_product_net_deducted(uuid,uuid)',
    'trg_fulfil_from_warehouse()',
    'invoice_goods_status(uuid)'];
  c_names constant text[] := array['invoice_stock_to_deduct', 'invoice_product_net_deducted', 'trg_fulfil_from_warehouse',
                                   'invoice_goods_status'];
  c_before constant text[] := array[
    '6356494ccb8545d46c56b788f8f85f54',
    'f6288d8eb44af4cd4dbed11f63d3427a',
    '4abf4bf68e4f00658a8da66469e7059e',
    '651039eac932b5d1f51fc75313ed4320'];
  c_after constant text[] := array[
    '5480e6042b4521829ebce1ef14937162',
    'e42acff8d87d5d2299159fa9ce6805ae',
    'e1d41bce9c53d21ac2ab727042663cfb',
    'ca966a2c6a1949afc98503862263b58d'];
  c_acl constant text[] := array[
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'];
  -- ══ The function this adds: the server's alone ═══════════════════════════
  c_new constant text := 'invoice_refunded_stock(uuid)';
  c_new_name constant text := 'invoice_refunded_stock';
  c_new_after constant text := 'f12af401547ce01e2b95ec3a5c230bad';
  c_new_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';

  -- ══ The whole texts (each exactly as the database prints it back) ═══════
  c_def_refunded constant text := $d0$CREATE OR REPLACE FUNCTION public.invoice_refunded_stock(p_invoice_id uuid)
 RETURNS TABLE(invoice_item_id uuid, line_kind text, kind text, item_id uuid, quantity integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- 481 (the Owner, 29 Oct 2026, Q2 "Fix it separately"): the stock units a
  -- refund by line paid back since the invoice was last reopened (or since
  -- the sale), per line and product, which the payment that settles the
  -- invoice (or any settlement, a hand-over before it, a correction's new
  -- deduction) no longer takes from stock (invoice_stock_to_deduct).
  -- * A product or promotion line (the lines a refund by line asks the stock
  --   outcome of, refund_invoice_recorded), counted as invoice_required_stock
  --   counts it (an exchange's replacement line is not: the exchange took its
  --   stock).
  -- * Its refunds by line since the reopening, as invoice_charge_total and
  --   the refund's own line check count them (the reopening charges the line
  --   again, so refunds before it count no more), in whole units at the
  --   line's paid value (invoice_discounted_line_value): S$40 of a S$40 line
  --   is its 1 unit, S$40 of a 2-unit S$80 line 1, S$10 of a S$40 line none
  --   (the line still charges S$30 and its unit is still taken). A unit
  --   whose paid value is not whole cents counts at that value cut down to
  --   the cent (a refund can only be whole cents), so no unit is lost to cent
  --   rounding: S$66.66 of a 3-unit S$100.00 line (S$33.333 a unit), in one
  --   refund or two of S$33.33, is 2 units, and S$66.66 of a 3-unit S$200.00
  --   line (S$66.667) 1; never more units than the money refunded pays for
  --   at that value, with half a cent to spare (S$99.98 of a 4-unit S$100.00
  --   line is 3 units: S$25.00 a unit, nothing to round).
  -- * Per product: the line's own (a product line), or each component it
  --   takes (a promotion line: invoice_stock_components on an invoice with
  --   component snapshots, its fixed contents and picks otherwise), for the
  --   units refunded, rounded down.
  -- * None on a cancelled or refunded invoice: it charges nothing and takes
  --   nothing, and what it would take once reopened is what its lines take,
  --   refunds before the reopening not counted (the Reopen dialog's "Stock to
  --   issue", and the reopening itself where it settles the invoice at once).
  -- An invoice with no refund at all has none: most invoices, so that is read
  -- first.
  if not exists (select 1 from public.invoice_refunds r where r.invoice_id = p_invoice_id) then return; end if;
  return query
  with i as (
    select v.* from public.invoices v
     where v.id = p_invoice_id and v.status::text not in ('cancelled', 'refunded')),
  l as (
    select it.id, it.line_kind::text as lk, it.quantity, it.product_id, it.promotion_id, i.stock_snapshot_version as snap,
           public.invoice_discounted_line_value(it.id) as worth,
           coalesce((select sum((x->>'amount')::numeric)
                       from public.invoice_refunds r cross join lateral jsonb_array_elements(coalesce(r.outcome->'lines', '[]'::jsonb)) x
                      where r.invoice_id = i.id and x->>'invoice_item_id' = it.id::text
                        and not coalesce((x->>'overpayment')::boolean, false)
                        and (i.reopened_at is null or r.created_at > i.reopened_at)), 0) as refunded
      from i join public.invoice_items it on it.invoice_id = i.id
     where it.line_kind::text in ('product', 'promotion') and it.quantity > 0
       and (it.price_source is distinct from 'exchange' or not i.is_exchange)),
  u as (
    select l.*, least(l.quantity, floor((l.refunded + 0.005)
             / case when trunc(l.worth / l.quantity, 2) > 0
                    then trunc(l.worth / l.quantity, 2) else l.worth / l.quantity end))::integer as n
      from l where l.refunded > 0 and l.worth > 0),
  c as (
    select u.id, u.lk, s.item_id, floor(s.quantity::numeric * u.n / u.quantity)::integer as q
      from u join public.invoice_stock_components s on s.invoice_item_id = u.id and s.kind = 'product'
     where u.n > 0 and u.snap = 1
    union all
    select u.id, u.lk, u.product_id, u.n
      from u where u.n > 0 and u.snap is distinct from 1 and u.lk = 'product' and u.product_id is not null
    union all
    select u.id, u.lk, s.item_id, floor(s.quantity::numeric * u.n / u.quantity)::integer
      from u cross join lateral public.promotion_stock_items(u.promotion_id, u.quantity) s
     where u.n > 0 and u.snap is distinct from 1 and u.lk = 'promotion' and u.promotion_id is not null and s.kind = 'product'
    union all
    select u.id, u.lk, s.product_id, floor(s.quantity::numeric * u.n / u.quantity)::integer
      from u join public.invoice_promotion_selections s on s.invoice_item_id = u.id
     where u.n > 0 and u.snap is distinct from 1 and u.lk = 'promotion' and s.product_id is not null)
  select c.id, c.lk, 'product'::text, c.item_id, sum(c.q)::integer
    from c where c.item_id is not null
   group by c.id, c.lk, c.item_id
  having sum(c.q) > 0;
end $function$
$d0$;
  c_def_todo constant text := $d1$CREATE OR REPLACE FUNCTION public.invoice_stock_to_deduct(p_invoice_id uuid)
 RETURNS TABLE(kind text, item_id uuid, quantity integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select r.kind,r.item_id,greatest(0,r.quantity-case when r.kind='product' then
 coalesce((select sum(case when m.movement_type::text='store_sale' then m.quantity else -m.quantity end)
 from public.stock_movements m where m.invoice_id=p_invoice_id and m.product_id=r.item_id
 and m.movement_type::text in ('store_sale','invoice_cancel_return','invoice_refund_return','refund_return')),0)
 -coalesce((select sum(d.damaged_quantity) from public.invoice_stock_dispositions d join public.stock_movements m on m.id=d.movement_id
 where d.invoice_id=p_invoice_id and m.product_id=r.item_id),0)
 else coalesce((select sum(m.quantity) from public.invoice_voucher_movements m where m.invoice_id=p_invoice_id and m.voucher_id=r.item_id),0) end
 -- 481 (the Owner, 29 Oct 2026, Q2 "Fix it separately"): less the units a
 -- refund by line paid back since the invoice was last reopened (or since the
 -- sale), so the payment that settles it does not take them from stock
 -- (invoice_refunded_stock: none on a cancelled or refunded invoice).
 -coalesce((select sum(u.quantity) from public.invoice_refunded_stock(p_invoice_id) u where u.kind=r.kind and u.item_id=r.item_id),0))::int
 from public.invoice_required_stock(p_invoice_id) r
$function$
$d1$;
  c_def_net constant text := $d2$CREATE OR REPLACE FUNCTION public.invoice_product_net_deducted(p_invoice_id uuid, p_product_id uuid)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with n as (
  select coalesce(sum(
           case sm.movement_type
             when 'store_sale'            then sm.quantity
             when 'invoice_cancel_return' then -sm.quantity
             else 0
           end), 0)::bigint
         -- 399: less the units "Record items returned" wrote off as Damaged
         -- before full payment: they came back, and the invoice still owes
         -- the customer them, as invoice_stock_to_deduct says. So a settlement
         -- that runs no deduction (Correct amount, a header-only correction)
         -- has the guarantee take the replacement. Other dispositions (a
         -- refund's, a cancellation's) are not taken off, as before.
         - coalesce((select sum(rl.damaged_quantity) from public.invoice_handover_return_lines rl
                      where rl.invoice_id = p_invoice_id and rl.product_id = p_product_id), 0)::bigint as net
    from public.stock_movements sm
   where sm.invoice_id = p_invoice_id
     and sm.product_id = p_product_id)
  -- 481 (the Owner, 29 Oct 2026, Q2 "Fix it separately"): plus the units a
  -- refund by line paid back since the last reopening (or the sale) that the
  -- invoice no longer takes (invoice_stock_to_deduct, less them, says nothing
  -- is left to take of them), counted as taken: so the backstop
  -- (ensure_invoice_stock_deducted) does not take them either, and the stock
  -- reports (invoice_stock_gaps, invoice_stock_diagnostic) do not list them as
  -- missing. With no such refund, as before.
  select n.net + case
           when coalesce((select sum(u.quantity) from public.invoice_refunded_stock(p_invoice_id) u
                           where u.kind = 'product' and u.item_id = p_product_id), 0) > 0
           then greatest(0, coalesce((select sum(r.quantity) from public.invoice_required_stock(p_invoice_id) r
                                       where r.kind = 'product' and r.item_id = p_product_id), 0)
                            - n.net
                            - coalesce((select sum(t.quantity) from public.invoice_stock_to_deduct(p_invoice_id) t
                                         where t.kind = 'product' and t.item_id = p_product_id), 0))
           else 0 end::bigint
    from n
$function$
$d2$;
  c_def_wh constant text := $d3$CREATE OR REPLACE FUNCTION public.trg_fulfil_from_warehouse()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_it record; v_have integer;
begin
  if new.fulfil_warehouse_id is null then return null; end if;
  if new.status not in ('paid','completed_foc') or old.status is not distinct from new.status then
    return null; end if;
  -- 399: goods handed over from the store before full payment are out of
  -- the store already (still out, or kept as Not returned); taking every
  -- line from the warehouse as well would count them twice. The setter
  -- and the hand-over refuse the combination; this is the backstop. Only
  -- the hand-over movements: the payment's own deduction is on the invoice
  -- by now.
  if exists (select 1 from public.invoice_handover_lines hl
               join public.stock_movements m on m.id = hl.movement_id
              where hl.invoice_id = new.id
                and m.quantity
                    - coalesce((select sum(v.quantity) from public.stock_movements v
                                 where v.reversed_sale_id = m.id and v.movement_type::text = 'invoice_cancel_return'), 0)
                    - coalesce((select sum(d.sellable_quantity + d.damaged_quantity) from public.invoice_stock_dispositions d
                                 where d.movement_id = m.id), 0) > 0) then
    raise exception 'Goods on % were handed over from the store before it was paid in full, so it cannot also be fulfilled from a warehouse. Set "Fulfil from" back to the store''s stock and try again.', new.invoice_no; end if;

  -- 481 (the Owner, 29 Oct 2026, Q2 "Fix it separately"): each product line
  -- less the units a refund by line paid back since the last reopening (or
  -- the sale): the payment took no store stock for them
  -- (invoice_stock_to_deduct), so none comes from the warehouse.
  for v_it in
    select ii.product_id,
           sum(ii.quantity) - coalesce((select sum(u.quantity) from public.invoice_refunded_stock(new.id) u
                                         where u.line_kind = 'product' and u.item_id = ii.product_id), 0) as qty,
           p.name
      from public.invoice_items ii join public.products p on p.id = ii.product_id
     where ii.invoice_id = new.id and ii.line_kind = 'product' and ii.product_id is not null
     group by ii.product_id, p.name
  loop
    continue when v_it.qty <= 0;
    select coalesce(current_qty,0) into v_have from public.warehouse_inventory
     where warehouse_id = new.fulfil_warehouse_id and product_id = v_it.product_id for update;
    if coalesce(v_have,0) < v_it.qty then
      raise exception 'Warehouse stock ran out for "%" (need %, have %)',
        v_it.name, v_it.qty, coalesce(v_have,0);
    end if;
    update public.warehouse_inventory
       set current_qty = current_qty - v_it.qty, updated_at = now()
     where warehouse_id = new.fulfil_warehouse_id and product_id = v_it.product_id;

    -- Give back the store stock the normal paid-invoice flow removed, so the
    -- goods are only ever counted out once.
    update public.store_inventory
       set current_qty = current_qty + v_it.qty, updated_at = now()
     where store_id = new.store_id and product_id = v_it.product_id;
  end loop;

  perform public.write_audit_ex('invoices', new.id, 'invoice_fulfilled_from_warehouse', null,
    jsonb_build_object('warehouse', new.fulfil_warehouse_id), 'inventory', null, new.store_id);
  return null;
end $function$
$d3$;
  c_def_goods constant text := $d4$CREATE OR REPLACE FUNCTION public.invoice_goods_status(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 399: the goods of an invoice for its page and its copies (the Owner, 6 Oct
-- 2026). Per product: required (lines, promotion contents and picks),
-- collected and still to collect (invoice_stock_to_deduct: what full payment
-- would take), out with the customer and not yet returned or written off
-- (invoice_goods_out: what "Record items returned" can take back), in the
-- store now, and the promotions it comes through; then every hand-over,
-- "Nothing taken" and return, oldest first, with who recorded it. Only an
-- invoice before full payment ("open") has anything to collect: once paid,
-- completed FOC, cancelled or refunded, "to collect" is 0 and "collected" is
-- what the customer is counted as having (0 after a cancellation that put the
-- goods back; less a refund's returns).
declare
  i public.invoices%rowtype; v_products jsonb; v_history jsonb;
  v_required integer; v_collected integer; v_to_collect integer; v_out integer;
  v_open boolean;
begin
  select * into i from public.invoices where id = p_invoice_id and deleted_at is null;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(i.store_id) then
    raise exception 'No access to this invoice' using errcode = '42501'; end if;
  v_open := i.status::text in ('draft', 'unpaid', 'partially_paid') and public.invoice_before_full_payment(i.id);

  with req as (select r.item_id as product_id, sum(r.quantity)::integer as qty
                 from public.invoice_required_stock(i.id) r where r.kind = 'product' group by 1),
       tod as (select t.item_id as product_id, sum(t.quantity)::integer as qty
                 from public.invoice_stock_to_deduct(i.id) t where t.kind = 'product' group by 1),
       gone as (select g.product_id, sum(g.quantity)::integer as qty
                  from public.invoice_goods_out(i.id) g group by 1),
       -- 481 (the Owner, 29 Oct 2026, Q2): the units a refund by line paid
       -- back since the last reopening (or the sale), no longer to collect
       -- (invoice_stock_to_deduct takes them off), and those the customer
       -- kept (Not returned).
       refd as (select u.item_id as product_id, sum(u.quantity)::integer as qty
                  from public.invoice_refunded_stock(i.id) u where u.kind = 'product' group by 1),
       kept as (select m.product_id, sum(d.not_returned_quantity)::integer as qty
                  from public.invoice_stock_dispositions d join public.stock_movements m on m.id = d.movement_id
                 where d.invoice_id = i.id group by 1),
       via as (select c.item_id as product_id,
                      jsonb_agg(distinct coalesce(pr.name, 'Promotion'))
                        filter (where it.line_kind::text <> 'product') as names
                 from public.invoice_stock_components c
                 join public.invoice_items it on it.id = c.invoice_item_id
                 left join public.promotions pr on pr.id = it.promotion_id
                where it.invoice_id = i.id and c.kind = 'product' group by 1),
       ids as (select req.product_id from req union select gone.product_id from gone)
  select coalesce(jsonb_agg(jsonb_build_object(
           'product_id', ids.product_id,
           'name', coalesce(p.name, 'Unknown product'),
           'required', coalesce(req.qty, 0),
           -- 481: with a refund by line since the last reopening, what the
           -- customer has (out, or kept as Not returned), up to the lines'.
           'collected', case when coalesce(refd.qty, 0) = 0 then greatest(coalesce(req.qty, 0) - coalesce(tod.qty, 0), 0)
                             else greatest(least(coalesce(req.qty, 0), coalesce(gone.qty, 0) + coalesce(kept.qty, 0)), 0) end,
           'to_collect', case when v_open then coalesce(tod.qty, 0) else 0 end,
           'out', coalesce(gone.qty, 0),
           'in_store', coalesce(si.current_qty, 0),
           'via', coalesce(via.names, '[]'::jsonb))
           order by p.name, ids.product_id), '[]'::jsonb)
    into v_products
    from ids
    left join req on req.product_id = ids.product_id
    left join tod on tod.product_id = ids.product_id
    left join gone on gone.product_id = ids.product_id
    left join refd on refd.product_id = ids.product_id
    left join kept on kept.product_id = ids.product_id
    left join via on via.product_id = ids.product_id
    left join public.products p on p.id = ids.product_id
    left join public.store_inventory si on si.store_id = i.store_id and si.product_id = ids.product_id;

  select coalesce(sum((e->>'required')::integer), 0), coalesce(sum((e->>'collected')::integer), 0),
         coalesce(sum((e->>'to_collect')::integer), 0), coalesce(sum((e->>'out')::integer), 0)
    into v_required, v_collected, v_to_collect, v_out
    from jsonb_array_elements(v_products) e;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', h.id, 'kind', h.kind, 'source', h.source, 'created_at', h.created_at,
           'created_by_name', pf.full_name, 'reason', h.reason,
           'items', case when h.kind = 'return' then
               coalesce((select jsonb_agg(jsonb_build_object('product_id', r.product_id, 'name', p.name,
                                            'good', r.good, 'damaged', r.damaged, 'not_returned', r.not_returned)
                                          order by p.name, r.product_id)
                           from (select rl.product_id, sum(rl.good_quantity)::integer as good,
                                        sum(rl.damaged_quantity)::integer as damaged,
                                        sum(rl.not_returned_quantity)::integer as not_returned
                                   from public.invoice_handover_return_lines rl
                                  where rl.handover_id = h.id group by rl.product_id) r
                           left join public.products p on p.id = r.product_id), '[]'::jsonb)
             else
               coalesce((select jsonb_agg(jsonb_build_object('product_id', l.product_id, 'name', p.name,
                                            'quantity', l.quantity) order by p.name, l.product_id)
                           from public.invoice_handover_lines l
                           left join public.products p on p.id = l.product_id
                          where l.handover_id = h.id), '[]'::jsonb) end)
           order by h.created_at, h.id), '[]'::jsonb)
    into v_history
    from public.invoice_handovers h
    left join public.profiles pf on pf.id = h.created_by
   where h.invoice_id = i.id;

  return jsonb_build_object(
    'invoice_id', i.id, 'invoice_no', i.invoice_no, 'status', i.status, 'store_id', i.store_id,
    'store_name', (select s.name from public.stores s where s.id = i.store_id),
    'open', v_open, 'fulfil_from_warehouse', i.fulfil_warehouse_id is not null,
    'required_total', v_required, 'collected_total', v_collected,
    'to_collect_total', v_to_collect, 'out_total', v_out,
    'can_hand_over', i.status::text in ('unpaid', 'partially_paid') and i.fulfil_warehouse_id is null
                     and v_to_collect > 0,
    'can_record_return', v_open and v_out > 0 and public.is_owner_or_manager(),
    'products', v_products, 'history', v_history);
end $function$
$d4$;

  -- ══ Relied on, not changed (production at 485 with 479 in, 2 Nov 2026,
  -- as on its copy: as at 478 with 479, 30 Oct 2026, but
  -- capture_invoice_stock_components, 483's): what reads
  -- invoice_stock_to_deduct and invoice_product_net_deducted; what the lines
  -- take and the line's value and window; the refund by line, Cancel, Reopen
  -- and its dialog, what is out with the customer; the payments and Correct
  -- payment; "Fulfil from"; 479's three (481 goes in after 479 and 483); the
  -- self-test's calls ════════════════════════════════════════════════════
  c_relied constant text[] := array[
    'invoice_required_stock(uuid)',
    'invoice_required_stock_legacy(uuid)',
    'promotion_stock_items(uuid,integer)',
    'capture_invoice_stock_components()',
    'invoice_discounted_line_value(uuid)',
    'invoice_charge_total(uuid)',
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'deduct_invoice_stock(uuid,text)',
    'ensure_invoice_stock_deducted(uuid,text)',
    'trg_guarantee_invoice_stock()',
    'invoice_record_payments_internal(uuid,jsonb)',
    'record_invoice_payment(uuid,jsonb,uuid)',
    'record_invoice_settlement(uuid,jsonb,uuid)',
    'correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)',
    'invoice_handover_internal(uuid,jsonb,uuid,text,uuid)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'confirm_foc_invoice(uuid,text)',
    'give_raised_voucher_units(uuid,uuid[],boolean,text)',
    'reopen_invoice(uuid,text,uuid)',
    'invoice_reopen_preview(uuid)',
    'invoice_reopen_preview_before_sessions(uuid)',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'restore_invoice_stock(uuid,text)',
    'invoice_goods_out(uuid)',
    'invoice_before_full_payment(uuid)',
    'record_invoice_stock_return(uuid,jsonb,text,uuid)',
    'record_invoice_goods_return(uuid,jsonb,text,uuid)',
    'set_invoice_fulfilment_warehouse(uuid,uuid)',
    'invoice_stock_gaps(text,uuid,date,date)',
    'invoice_stock_diagnostic(text)',
    'repair_invoice_stock_gap(uuid,boolean)',
    'refund_invoice_therapy_sessions(uuid,numeric,text,uuid)',
    'correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid)',
    'trg_create_therapy_sessions_on_paid()',
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    'set_product_prices(uuid,uuid,numeric,numeric,text)',
    'invoice_financial_position(uuid)',
    'invoice_net_received(uuid)',
    'normalize_customer_phone(text)',
    'is_owner_or_manager()',
    'user_has_store_access(uuid)',
    'trg_invoice_manual_discount_reason()'];
  c_relied_md5 constant text[] := array[
    'c91dc1eb4f2b7b465de5fe4a8fb2ca0c',
    '2e0bc2497901c2690a74205bdd3a0a5f',
    '82dd6bdac5566fce0b75470eb45444d1',
    'a7922878b6b73925de975bb7fa51ea1d',
    'ead4a430c3abd1e3f953912867ca4fe6',
    '8297147511ba285db2279598f3d727fb',
    '804ecd829cfecf713783a09a05d93c7e',
    '32183fe9e7c15ed0b11307c48289831a',
    '3c7ca7893f359f380a340cec07f21a1f',
    'b4d922c6238f50137941a85a590600c8',
    '21890d84bcb0b9c00a2bc98aff313d0b',
    '9c70097ed4da614fb9dcc66fdfcdb7d6',
    '8c8778af82899c6aaada62371d13802f',
    'af99337094edb6d73b9cc0ae00fbf138',
    '51f5adaddbe447e8fcbeaabab03a054a',
    '04d647e13e9424a9375942e5812e91a2',
    'ba8b1ce2a5671989b927891f0cb7b1a2',
    '84d4c7bbd39a754d61cbe4f778777a33',
    '30066e137b9b75b5789a050c14debc04',
    'e09ebf9c0841ef5463f96b26f4933541',
    'acbfc38a20a000e1af0e78d26fc7fc4c',
    'de52d9dbaef8ab15163bef35cb9d733d',
    '092316c3af22361f80d186e38fe49bf3',
    '15ffed0ff0d5d9cc5685af8e834302ae',
    '532d7690367fc674737b20420e7fb16c',
    '6b125cb5df1eb103781662bef41e9417',
    'e1a3242f7bfc66fb4f6ea162d823137f',
    '66bf7f38e06bf48116b63b71ca7663cb',
    '109e846c4e4f3bac3b5e374ebf44bcb7',
    'dbc65c84b70ed1fe67eebe5602ae1332',
    '8c9a1d837da6e4326f00b11d41127090',
    '35d3f1ba4c906a66a8deb131c777dab8',
    '32df6441a3f5e37e164b1279f8dc502b',
    '15f4bbc260e53ba538debc0947082f43',
    '80c80d386a5241e63b353e35e13ef250',
    'aef4792013bc3a56f8ee62bc1a7d686a',
    'ba7eccbfeff217c8b1969b0e55a010ca',
    'f256bea69b7defa38a950753bbc248da',
    'b2bfac910e0c9eff402ba44e19750bee',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    '708992afaa6c3951f6329239b742987c',
    'bfed9e779a89ed9b149b6be80217775a'];
  -- The triggers that run the backstop and the warehouse fulfilment, as read.
  c_trigger_wh constant text := 'CREATE TRIGGER fulfil_from_warehouse AFTER UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_fulfil_from_warehouse()';
  c_trigger_guarantee constant text := 'CREATE TRIGGER guarantee_invoice_stock AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_guarantee_invoice_stock()';
  -- Who calls the four and the new one (by name; the trigger's by the
  -- trigger alone): before 481, and as 481 leaves them.
  c_callers_before constant text[] := array[
    'confirm_foc_invoice(uuid,text), correct_invoice(uuid,jsonb,jsonb,text,uuid), deduct_invoice_stock(uuid,text), give_raised_voucher_units(uuid,uuid[],boolean,text), invoice_goods_status(uuid), invoice_handover_internal(uuid,jsonb,uuid,text,uuid), invoice_record_payments_internal(uuid,jsonb), invoice_reopen_preview_before_sessions(uuid)',
    'ensure_invoice_stock_deducted(uuid,text), invoice_stock_diagnostic(text), invoice_stock_gaps(text,uuid,date,date)',
    null,
    null];
  c_callers_after constant text[] := array[
    'confirm_foc_invoice(uuid,text), correct_invoice(uuid,jsonb,jsonb,text,uuid), deduct_invoice_stock(uuid,text), give_raised_voucher_units(uuid,uuid[],boolean,text), invoice_goods_status(uuid), invoice_handover_internal(uuid,jsonb,uuid,text,uuid), invoice_product_net_deducted(uuid,uuid), invoice_record_payments_internal(uuid,jsonb), invoice_reopen_preview_before_sessions(uuid)',
    'ensure_invoice_stock_deducted(uuid,text), invoice_stock_diagnostic(text), invoice_stock_gaps(text,uuid,date,date)',
    null,
    null];
  c_new_callers constant text := 'invoice_goods_status(uuid), invoice_product_net_deducted(uuid,uuid), invoice_stock_to_deduct(uuid), trg_fulfil_from_warehouse()';
  -- What writes a refund, sets reopened_at, writes a stock outcome, or names
  -- a store sale (by name; a session's own temporary functions are not
  -- counted): as read, before 481 and after it alike.
  c_refund_writers constant text := 'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)';
  c_reopened_writers constant text := 'reopen_invoice(uuid,text,uuid)';
  c_outcome_writers constant text := 'record_invoice_goods_return(uuid,jsonb,text,uuid), record_invoice_stock_return(uuid,jsonb,text,uuid), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)';
  c_sale_users constant text := 'apply_tiktok_stock_delta(uuid,text,uuid,integer,uuid,text,text,text), confirm_foc_invoice(uuid,text), correct_invoice(uuid,jsonb,jsonb,text,uuid), deduct_invoice_stock(uuid,text), ensure_invoice_stock_deducted(uuid,text), fulfil_special_doc(text,uuid,uuid,text), invoice_goods_out(uuid), invoice_handover_internal(uuid,jsonb,uuid,text,uuid), invoice_product_net_deducted(uuid,uuid), invoice_refund_options_before_sessions(uuid), invoice_stock_to_deduct(uuid), promotion_stock_gaps(date,date,uuid), record_invoice_stock_return(uuid,jsonb,text,uuid), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), restore_invoice_stock(uuid,text), set_invoice_fulfilment_warehouse(uuid,uuid), stock_history_type_label(text), trg_stock_return_exchange_hold()';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; i int; n_before int := 0; n_after int := 0; v_first boolean; v_acl text[] := '{}';
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_prod uuid; t_vou uuid;
  t_case int; t_a uuid; t_inv uuid; t_pitem uuid; t_pay uuid; t_goods jsonb; t_msg text;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The texts are the tested ones.
  if md5(c_def_todo) <> c_after[1] or md5(c_def_net) <> c_after[2] or md5(c_def_wh) <> c_after[3]
     or md5(c_def_goods) <> c_after[4] or md5(c_def_refunded) <> c_new_after then
    raise exception '481: the texts in this file are not the tested ones'; end if;

  -- The functions relied on are as read (production at 485 with 479 in, 2
  -- Nov 2026: 483's capture_invoice_stock_components among them).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '481: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying (481 goes in after 479).',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if (select string_agg(pg_get_triggerdef(t.oid), E'\n' order by t.tgname) from pg_trigger t
       where t.tgfoid = 'public.trg_fulfil_from_warehouse()'::regprocedure) is distinct from c_trigger_wh
     or (select string_agg(pg_get_triggerdef(t.oid), E'\n' order by t.tgname) from pg_trigger t
          where t.tgfoid = 'public.trg_guarantee_invoice_stock()'::regprocedure) is distinct from c_trigger_guarantee then
    raise exception '481: the triggers that run the warehouse fulfilment and the stock backstop when an invoice is settled are not as read on 30 Oct 2026'; end if;

  -- The columns read, with these types.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('invoices', 'id', 'uuid'), ('invoices', 'status', 'invoice_status'), ('invoices', 'reopened_at', 'timestamp with time zone'),
                 ('invoices', 'stock_snapshot_version', 'integer'), ('invoices', 'is_exchange', 'boolean'),
                 ('invoices', 'deleted_at', 'timestamp with time zone'), ('invoices', 'store_id', 'uuid'),
                 ('invoices', 'fulfil_warehouse_id', 'uuid'),
                 ('invoice_items', 'id', 'uuid'), ('invoice_items', 'invoice_id', 'uuid'), ('invoice_items', 'line_kind', 'invoice_line_kind'),
                 ('invoice_items', 'quantity', 'integer'), ('invoice_items', 'product_id', 'uuid'), ('invoice_items', 'promotion_id', 'uuid'),
                 ('invoice_items', 'price_source', 'text'),
                 ('invoice_refunds', 'invoice_id', 'uuid'), ('invoice_refunds', 'outcome', 'jsonb'),
                 ('invoice_refunds', 'created_at', 'timestamp with time zone'),
                 ('invoice_stock_components', 'invoice_item_id', 'uuid'), ('invoice_stock_components', 'kind', 'text'),
                 ('invoice_stock_components', 'item_id', 'uuid'), ('invoice_stock_components', 'quantity', 'integer'),
                 ('invoice_promotion_selections', 'invoice_item_id', 'uuid'), ('invoice_promotion_selections', 'product_id', 'uuid'),
                 ('invoice_promotion_selections', 'quantity', 'integer'),
                 ('invoice_stock_dispositions', 'invoice_id', 'uuid'), ('invoice_stock_dispositions', 'movement_id', 'uuid'),
                 ('invoice_stock_dispositions', 'damaged_quantity', 'integer'), ('invoice_stock_dispositions', 'not_returned_quantity', 'integer'),
                 ('stock_movements', 'id', 'uuid'), ('stock_movements', 'product_id', 'uuid'), ('stock_movements', 'invoice_id', 'uuid'),
                 ('stock_movements', 'movement_type', 'stock_movement_type'), ('stock_movements', 'quantity', 'integer'),
                 ('invoice_handover_return_lines', 'invoice_id', 'uuid'), ('invoice_handover_return_lines', 'product_id', 'uuid'),
                 ('invoice_handover_return_lines', 'damaged_quantity', 'integer'),
                 ('warehouse_inventory', 'warehouse_id', 'uuid'), ('warehouse_inventory', 'product_id', 'uuid'),
                 ('warehouse_inventory', 'current_qty', 'integer'),
                 ('store_inventory', 'store_id', 'uuid'), ('store_inventory', 'product_id', 'uuid'), ('store_inventory', 'current_qty', 'integer')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '481: these columns are missing or not as read on 30 Oct 2026: %', v; end if;

  -- No other function takes their names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname = any (c_names) and not (p.oid::regprocedure::text = any (c_sigs))
          or p.proname = c_new_name and p.oid::regprocedure::text <> c_new);
  if v is not null then raise exception '481: another function takes the name of one this changes or adds: %', v; end if;

  -- The four: all at their BEFORE and the new one not there (replaced and
  -- made), or all five at their AFTER (left alone); anything else refused.
  for i in 1 .. cardinality(c_sigs) loop
    d := pg_get_functiondef(to_regprocedure('public.' || c_sigs[i]));
    if md5(d) = c_before[i] then n_before := n_before + 1;
    elsif md5(d) = c_after[i] then n_after := n_after + 1;
    else
      raise exception '481: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sigs[i], md5(d);
    end if;
  end loop;
  if n_after = cardinality(c_sigs) and to_regprocedure('public.' || c_new) is not null
     and md5(pg_get_functiondef(to_regprocedure('public.' || c_new))) = c_new_after then
    raise notice '481: the five functions are already this version; left alone';
    v_first := false;
  elsif n_before = cardinality(c_sigs) and to_regprocedure('public.' || c_new) is null then
    v_first := true;
  else
    raise exception '481: of the four functions % are at their BEFORE and % at their AFTER, and invoice_refunded_stock is % (md5 %); a partial install, not as tested',
      n_before, n_after, case when to_regprocedure('public.' || c_new) is null then 'not there' else 'there' end,
      case when to_regprocedure('public.' || c_new) is not null then md5(pg_get_functiondef(to_regprocedure('public.' || c_new))) end;
  end if;

  -- Who calls them, as read (before 481, or as 481 leaves them).
  for i in 1 .. cardinality(c_sigs) loop
    select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where p.prosrc ~ (c_names[i] || '\s*\(') and ns.nspname not like 'pg\_temp\_%' and p.proname <> c_names[i];
    if v is distinct from (case when v_first then c_callers_before[i] else c_callers_after[i] end) then
      raise exception '481: public.% is called by % (as read on 30 Oct 2026: %); check how each reads it, then re-test', c_sigs[i], coalesce(v, 'nothing'),
        coalesce(case when v_first then c_callers_before[i] else c_callers_after[i] end, 'nothing'); end if;
  end loop;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ (c_new_name || '\s*\(') and ns.nspname not like 'pg\_temp\_%' and p.proname <> c_new_name;
  if v is distinct from (case when v_first then null else c_new_callers end) then
    raise exception '481: public.% is called by % (481 alone calls it, from %)', c_new, coalesce(v, 'nothing'), c_new_callers; end if;
  if (select count(*) from pg_trigger t where t.tgfoid = 'public.trg_fulfil_from_warehouse()'::regprocedure) <> 1 then
    raise exception '481: trg_fulfil_from_warehouse runs from other triggers than the one read on 30 Oct 2026'; end if;

  -- What writes a refund, sets reopened_at, writes a stock outcome, or names
  -- a store sale: as read (a new way would need the same care).
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'insert\s+into\s+(public\.)?invoice_refunds' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_refund_writers then
    raise exception '481: what writes a refund (invoice_refunds) is not as read on 30 Oct 2026 (%); the units refunded by line are read from its lines, so check it, then re-test', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'reopened_at\s*=' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_reopened_writers then
    raise exception '481: what sets an invoice''s reopened_at is not as read on 30 Oct 2026 (%); the units refunded since a reopening are read by it, so check it, then re-test', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+(public\.)?invoice_stock_dispositions' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_outcome_writers then
    raise exception '481: what writes a stock outcome (invoice_stock_dispositions) is not as read on 30 Oct 2026 (%); check it, then re-test', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* '''store_sale''' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_sale_users then
    raise exception '481: what names a store sale (stock_movements of kind store_sale) is not as read on 30 Oct 2026 (%); check what it takes or reads, then re-test', v; end if;

  -- ── On the first run: nothing is refused for the data (481 needs no
  -- decision before it goes in), but what is for the Owner and what changes
  -- is named (the header's read-only query, the same text: 1 is for the
  -- Owner, 2 changes).
  if v_first then
    select string_agg(format('%s: %s invoice(s) (%s)', f.reason, f.n, f.nos), '; ' order by f.reason) into v
      from (select left(q.reason, 1) as reason, count(*) as n, string_agg(q.invoice_no, ', ' order by q.invoice_no) as nos
              from (
with
-- per product or promotion line (as invoice_required_stock counts it), on an
-- invoice not cancelled or refunded: the whole units its refunds by line
-- since the invoice was last reopened (or since the sale) paid back, at the
-- line's paid value, and the products they take (481's rule,
-- invoice_refunded_stock, written out: the function is 481's)
l as (
  select i.id as invoice_id, it.id as item_id, it.line_kind::text as lk, it.quantity, it.product_id, it.promotion_id,
         i.stock_snapshot_version as snap, public.invoice_discounted_line_value(it.id) as worth,
         coalesce((select sum((x->>'amount')::numeric)
                     from public.invoice_refunds r cross join lateral jsonb_array_elements(coalesce(r.outcome->'lines', '[]'::jsonb)) x
                    where r.invoice_id = i.id and x->>'invoice_item_id' = it.id::text
                      and not coalesce((x->>'overpayment')::boolean, false)
                      and (i.reopened_at is null or r.created_at > i.reopened_at)), 0) as refunded
    from public.invoices i join public.invoice_items it on it.invoice_id = i.id
   where i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
     and it.line_kind::text in ('product', 'promotion') and it.quantity > 0
     and (it.price_source is distinct from 'exchange' or not i.is_exchange)),
u as (
  select l.*, least(l.quantity, floor((l.refunded + 0.005)
           / case when trunc(l.worth / l.quantity, 2) > 0
                  then trunc(l.worth / l.quantity, 2) else l.worth / l.quantity end))::integer as n
    from l where l.refunded > 0 and l.worth > 0),
c as (
  select u.invoice_id, s.item_id as product_id, floor(s.quantity::numeric * u.n / u.quantity)::integer as q
    from u join public.invoice_stock_components s on s.invoice_item_id = u.item_id and s.kind = 'product'
   where u.n > 0 and u.snap = 1
  union all
  select u.invoice_id, u.product_id, u.n
    from u where u.n > 0 and u.snap is distinct from 1 and u.lk = 'product' and u.product_id is not null
  union all
  select u.invoice_id, s.item_id, floor(s.quantity::numeric * u.n / u.quantity)::integer
    from u cross join lateral public.promotion_stock_items(u.promotion_id, u.quantity) s
   where u.n > 0 and u.snap is distinct from 1 and u.lk = 'promotion' and u.promotion_id is not null and s.kind = 'product'
  union all
  select u.invoice_id, s.product_id, floor(s.quantity::numeric * u.n / u.quantity)::integer
    from u join public.invoice_promotion_selections s on s.invoice_item_id = u.item_id
   where u.n > 0 and u.snap is distinct from 1 and u.lk = 'promotion' and s.product_id is not null),
-- per invoice and product: the units refunded, what its lines take
-- (invoice_required_stock), what is with the customer, not returned or
-- written off (invoice_goods_out), and what is out counting the units kept as
-- Not returned (its sales less the returns and write-offs, as
-- invoice_stock_to_deduct reads them before 481)
st as (
  select f.invoice_id, f.product_id, f.units,
         coalesce((select sum(r.quantity) from public.invoice_required_stock(f.invoice_id) r
                    where r.kind = 'product' and r.item_id = f.product_id), 0) as lines,
         coalesce((select sum(g.quantity) from public.invoice_goods_out(f.invoice_id) g
                    where g.product_id = f.product_id), 0) as with_customer,
         coalesce((select sum(case when m.movement_type::text = 'store_sale' then m.quantity else -m.quantity end)
                     from public.stock_movements m
                    where m.invoice_id = f.invoice_id and m.product_id = f.product_id
                      and m.movement_type::text in ('store_sale', 'invoice_cancel_return', 'invoice_refund_return', 'refund_return')), 0)
           - coalesce((select sum(d.damaged_quantity) from public.invoice_stock_dispositions d
                        join public.stock_movements m on m.id = d.movement_id
                       where d.invoice_id = f.invoice_id and m.product_id = f.product_id), 0) as out_
    from (select c.invoice_id, c.product_id, sum(c.q) as units from c where c.product_id is not null
           group by c.invoice_id, c.product_id having sum(c.q) > 0) f),
found(reason, invoice_id, n) as (
  -- (1 can also list an invoice whose refunded line a later Edit Invoice
  -- lowered, its quantity, unit price or line discount or the invoice's
  -- manual discount, with nothing taken after the refund but by that
  -- correction, or nothing at all: 481's NOT COVERED 13; read its
  -- revisions and stock history before a charge, a recovery or a write-off)
  select '1 for the Owner (481 changes no record): a product refunded by line since its invoice was last reopened (or since the sale) is with the customer again beyond what its lines still charge, taken from stock after its refund (by the payment that settled the invoice, a correction that changed its stock, or a hand-over before full payment) and not returned; from 481 a refund by line keeps its units from being taken (the count is of units)', st.invoice_id, sum(least(st.units, st.with_customer - (st.lines - st.units)))
    from st where st.with_customer > st.lines - st.units
   group by st.invoice_id
  union all
  select '2 changes: units a refund by line paid back since the invoice was last reopened (or since the sale) that invoice_stock_to_deduct reported as still to take before 481 (the payment that settles the invoice, a hand-over, a correction that changes its stock, or its fulfilment from a warehouse took them); from 481 they are not taken (the count is of units)', st.invoice_id, sum(least(st.units, st.lines - st.out_))
    from st where st.lines - st.out_ > 0
   group by st.invoice_id)
select f.reason, i.invoice_no, f.n
  from found f join public.invoices i on i.id = f.invoice_id
 order by f.reason, i.invoice_no
                   ) q
             group by left(q.reason, 1)) f;
    if v is not null then
      raise notice '481: the header''s query lists %: 1 is for the Owner (a product refunded by line with the customer again; 481 changes no record); 2, the units invoice_stock_to_deduct reported as still to take are, from 481, not taken', v;
    end if;
  end if;

  -- Who may call each, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  for i in 1 .. cardinality(c_sigs) loop
    if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i]))
       is distinct from (select array_agg(x::text order by x::text) from unnest(c_acl[i]::aclitem[]) x) then
      raise exception '481: who may call public.% is not as read on 30 Oct 2026 (%)', c_sigs[i],
        (select proacl::text from pg_proc where oid = to_regprocedure('public.' || c_sigs[i])); end if;
    v_acl := v_acl || (select coalesce(string_agg(x::text, ',' order by x::text), '')
                         from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i]));
  end loop;
  if not v_first
     and (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new))
         is distinct from (select array_agg(x::text order by x::text) from unnest(c_new_acl::aclitem[]) x) then
    raise exception '481: who may call public.% is not as 481 left it (%)', c_new,
      (select proacl::text from pg_proc where oid = to_regprocedure('public.' || c_new)); end if;

  -- ── Change ──────────────────────────────────────────────────────────────
  if v_first then
    -- The new one first: the four read it.
    execute c_def_refunded;
    execute 'revoke all on function public.invoice_refunded_stock(uuid) from public, anon, authenticated';
    execute 'grant execute on function public.invoice_refunded_stock(uuid) to service_role';
    execute c_def_todo;
    execute c_def_net;
    execute c_def_wh;
    execute c_def_goods;
  end if;

  -- ── Afterwards: installed exactly as tested, grants as before ───────────
  for i in 1 .. cardinality(c_sigs) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[i]))) <> c_after[i] then
      raise exception '481: public.% is not at its AFTER md5 (%)', c_sigs[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[i]))); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i])) is distinct from v_acl[i] then
      raise exception '481: the grants of public.% changed', c_sigs[i]; end if;
  end loop;
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_new))) <> c_new_after
     or (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new))
        is distinct from (select array_agg(x::text order by x::text) from unnest(c_new_acl::aclitem[]) x)
     or has_function_privilege('anon', 'public.' || c_new, 'execute')
     or has_function_privilege('authenticated', 'public.' || c_new, 'execute') then
    raise exception '481: public.% is not as tested, or not callable as tested', c_new; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("481 check", @example.com, fictional ACMA phones
  -- no customer uses); it ends by raising P0481, which undoes all it wrote.
  -- Its product is stocked nowhere, so no store's stock moves (no stock
  -- history row and no sequence is used): a unit to take is seen in what
  -- invoice_stock_to_deduct reports and in the payment refused for lack of
  -- stock. 462's trigger runs at commit; here at each step's end (SET
  -- CONSTRAINTS ... IMMEDIATE), as a commit would.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from generate_series(600, 699) g, lateral (select '+61491570' || g::text as p) x
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p desc limit 5);
    if coalesce(cardinality(t_phones), 0) < 5 then raise exception '481: the self-test found no five unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '481-check-' || t_sfx || '@example.com') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '481 check', '481-check-' || t_sfx || '@example.com', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('481 check ' || t_sfx, '481-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('481 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.products (name, sku, product_type) values ('481 check ' || t_sfx, '481-' || t_sfx, 'own') returning id into t_prod;
    perform public.set_product_prices(t_store, t_prod, 40, 40, 'available');
    insert into public.vouchers (name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('481 check ' || t_sfx, '481-' || t_sfx, 'normal', 'unlimited', 30, true) returning id into t_vou;
    insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store) values (t_vou, t_store, 30, true);
    if exists (select 1 from public.store_inventory where product_id = t_prod) then
      raise exception '481: the self-test''s product is stocked somewhere'; end if;

    for t_case in 1 .. 5 loop
      -- The S$40 product (2 of it in (d), 3 in (e)) and, in (a) and (b), a
      -- S$30 voucher line (in (e) 2 vouchers, with an Owner's S$30 discount,
      -- its reason handed over as the invoice form hands it over), sold to a
      -- made-up customer; S$40 (in (c) S$20, in (b) and (d) S$50, in (e)
      -- S$100) paid.
      insert into public.customers (full_name, phone) values ('481 Check Buyer ' || t_case || ' ' || t_sfx, t_phones[t_case])
      returning id into t_a;
      perform set_config('invoice.manual_discount_reason', case when t_case = 5 then '481 check' else '' end, true);
      t_inv := public.create_invoice(t_store, t_a, null::uuid,
        jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', t_prod, 'quantity', case t_case when 4 then 2 when 5 then 3 else 1 end))
          || case when t_case <= 2 or t_case = 5
                  then jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', t_vou, 'quantity', case when t_case = 5 then 2 else 1 end))
                  else '[]'::jsonb end,
        case when t_case = 5 then 30 else 0 end::numeric, null::text, null::uuid, '[]'::jsonb);
      perform set_config('invoice.manual_discount_reason', '', true);
      select it.id into t_pitem from public.invoice_items it where it.invoice_id = t_inv and it.line_kind::text = 'product';
      if (select stock_snapshot_version from public.invoices where id = t_inv) is distinct from 1 or t_pitem is null then
        raise exception '481: the self-test''s invoice was not made as tested'; end if;
      perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
        'amount', case t_case when 1 then 40 when 3 then 20 when 5 then 100 else 50 end)), gen_random_uuid());
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt';
      if t_case = 1 then
        -- (a) the product refunded by line, the rest paid: settled, no
        -- store sale and nothing to take (before 481 the payment was refused
        -- for lack of stock: it would have taken the product); the Goods
        -- panel 1 on the invoice, 0 collected.
        perform public.refund_invoice_recorded(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', t_pitem, 'amount', 40)),
          jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 40)), '[]'::jsonb, '481 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
          'amount', (public.invoice_financial_position(t_inv)->>'outstanding')::numeric)), gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        t_goods := (select p from jsonb_array_elements(public.invoice_goods_status(t_inv)->'products') p where p->>'product_id' = t_prod::text);
        if (select status::text from public.invoices where id = t_inv) <> 'paid'
           or exists (select 1 from public.stock_movements m where m.invoice_id = t_inv)
           or exists (select 1 from public.invoice_stock_to_deduct(t_inv) s where s.quantity > 0)
           or public.invoice_net_received(t_inv) <> 30
           or (t_goods->>'required')::int is distinct from 1 or (t_goods->>'collected')::int is distinct from 0 then
          raise exception '481: (a) the payment that settled it did not leave the refunded product as tested (status %, the Goods panel %)',
            (select status::text from public.invoices where id = t_inv), t_goods; end if;
      elsif t_case = 2 then
        -- (b) the product refunded by line before full payment: nothing to
        -- take or to collect (before 481: 1), and handing it over is refused.
        perform public.refund_invoice_recorded(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', t_pitem, 'amount', 40)),
          jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 40)), '[]'::jsonb, '481 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        t_goods := (select p from jsonb_array_elements(public.invoice_goods_status(t_inv)->'products') p where p->>'product_id' = t_prod::text);
        t_msg := null;
        begin
          perform public.invoice_handover_internal(t_inv, jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', t_prod, 'qty', 1))),
            gen_random_uuid(), 'button');
        exception when others then t_msg := sqlerrm;
        end;
        if exists (select 1 from public.invoice_stock_to_deduct(t_inv) s where s.quantity > 0)
           or (t_goods->>'to_collect')::int is distinct from 0 or (t_goods->>'collected')::int is distinct from 0
           or t_msg is null or t_msg not like 'Only 0 of %' then
          raise exception '481: (b) a product refunded by line before full payment is still to collect (the Goods panel %; the hand-over %)',
            t_goods, coalesce(t_msg, 'went through'); end if;
      elsif t_case = 3 then
        -- (c) the product alone, not refunded: still 1 to take, and the
        -- payment that would settle it is refused for lack of stock, as
        -- before 481.
        t_msg := null;
        begin
          perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 20)), gen_random_uuid());
        exception when others then t_msg := sqlerrm;
        end;
        if (select coalesce(sum(s.quantity), 0) from public.invoice_stock_to_deduct(t_inv) s where s.kind = 'product') <> 1
           or t_msg is null or t_msg not like 'Insufficient store stock for %' then
          raise exception '481: (c) a product not refunded is not taken as before (%)', coalesce(t_msg, 'the payment went through'); end if;
      elsif t_case = 4 then
        -- (d) cancelled, one unit's S$40 refunded by line while cancelled:
        -- the Reopen dialog's "Stock to issue" is 2, as before; reopened (the
        -- line charged again): 2 to take again.
        perform public.cancel_invoice_recorded(t_inv, '481 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        perform public.refund_invoice_recorded(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', t_pitem, 'amount', 40)),
          jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 40)), '[]'::jsonb, '481 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if (select coalesce(sum((s->>'quantity')::int), 0) from jsonb_array_elements(public.invoice_reopen_preview(t_inv)->'stock_to_issue') s
             where s->>'item_id' = t_prod::text) <> 2 then
          raise exception '481: (d) the Reopen dialog does not show 2 to issue'; end if;
        perform public.reopen_invoice(t_inv, '481 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if (select status::text from public.invoices where id = t_inv) <> 'partially_paid'
           or (select coalesce(sum(s.quantity), 0) from public.invoice_stock_to_deduct(t_inv) s where s.kind = 'product') <> 2 then
          raise exception '481: (d) the reopened invoice does not take its product again (status %)', (select status::text from public.invoices where id = t_inv); end if;
      else
        -- (e) a unit whose paid value is not whole cents (the review of 2 Nov
        -- 2026): the product's line S$100.00 (S$33.333 a unit), S$66.66 of it
        -- refunded by line: 2 units the payment will not take, 1 it will
        -- (before this build 1 and 2: a unit lost to the cent).
        if public.invoice_discounted_line_value(t_pitem) is distinct from 100.00 then
          raise exception '481: (e) the product''s line is not S$100.00 as tested (%)', public.invoice_discounted_line_value(t_pitem); end if;
        perform public.refund_invoice_recorded(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', t_pitem, 'amount', 66.66)),
          jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 66.66)), '[]'::jsonb, '481 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if (select coalesce(sum(u.quantity), 0) from public.invoice_refunded_stock(t_inv) u where u.item_id = t_prod) <> 2
           or (select coalesce(sum(s.quantity), 0) from public.invoice_stock_to_deduct(t_inv) s where s.kind = 'product') <> 1 then
          raise exception '481: (e) S$66.66 of a 3-unit S$100.00 line is not 2 units not to take and 1 to take (% and %)',
            (select coalesce(sum(u.quantity), 0) from public.invoice_refunded_stock(t_inv) u where u.item_id = t_prod),
            (select coalesce(sum(s.quantity), 0) from public.invoice_stock_to_deduct(t_inv) s where s.kind = 'product'); end if;
      end if;
    end loop;
    raise exception using errcode = 'P0481', message = '481: self-test done, undone';
  exception when sqlstate 'P0481' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
