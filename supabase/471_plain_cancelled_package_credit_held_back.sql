-- 471_plain_cancelled_package_credit_held_back.sql
--
-- CREDIT A REFUNDED OR CORRECTED SALE GIVES BACK WHILE ITS PACKAGE IS
-- CANCELLED, REFUNDED OR WAITING FOR ITS REOPENING'S PAYMENT IS HELD BACK BY
-- THE CANCELLATION ALSO WHERE THE PACKAGE NEVER CHANGED HANDS; WHILE IT IS
-- CANCELLED OR REFUNDED, ALSO WHERE ITS CREDIT WAS RELEASED BEFORE IT WAS
-- PAID IN FULL; AND THE LOCK CANCEL PUTS ON SUCH CREDIT NO LONGER KEEPS IT
-- WITH ITS BUYER ONCE THE PACKAGE IS REOPENED AND PAID IN FULL (470's NOT
-- COVERED 1: G2, G3, RX0; the Owner, 26 Oct 2026: "Yes, fix it after 470")
--
-- (The number 471 is this file's name, its errors' prefix, its self-test's
-- error code P0471 and its suite's; if it changes at commit, change it in
-- these places alone: the file name, the "471:" messages, P0471, the suite.)
--
-- WHO FOUND IT
--
--   470's builders (its NOT COVERED 1 and its suite's KNOWN K (1), 26 Oct
--   2026), put to the Owner with 470. Reproduced on copies of production at
--   470 (0f581614, 1387 functions, 26 Oct 2026) with the cases the Owner's
--   task named and their plain siblings (this file's suite): made-up
--   records, the app's own calls, each followed by what its commit does.
--   Seventeen of them were also run one app call per real transaction on
--   copies (real commits, so 462's deferred trigger at each COMMIT), with
--   and without this file: the same outcomes as the suite's, both ways.
--   The part-paid case (paid credit released before full payment, which no
--   benefit row names) was found by 471's review (26 Oct 2026), reproduced
--   on copies with and without 471's first text (the same both ways: 470
--   did not reach it either), and is covered here since (B below). The
--   same review's second round (26 Oct 2026) found that a package paid in
--   part, cancelled, reopened and paid in full, then cancelled or refunded
--   again, still left the credit a session's refund gave back spendable,
--   and that a 'transfer' customer change after the payment left it with
--   the old customer (the lock below), reproduced on copies with 471's
--   second text and with 470 alone (the same both ways, also one app call
--   per real transaction): covered here since (C below). Its third round
--   (26 Oct 2026) found, on copies with 471's third text and with 470
--   alone, that credit a refund gives back on a lot an Owner reversed is
--   not held back while its package is cancelled (the same both ways: NOT
--   COVERED 10, for the Owner), and that the query below and the first
--   run's notices missed a released lot a Cancel closed that sits behind
--   the lot the records name (a reissue copied it, lock and all): listed
--   since (the query's 4, 7, 8 and 9); the function is unchanged by it.
--
-- WHAT WAS WRONG
--
--   462's forwarder (credit_given_back_follows, 470's text) holds credit
--   given back while a package is cancelled, refunded or waiting for its
--   reopening's payment only where the package's lot was reissued (a customer
--   change, a merge, a reopening's give-back, 462's own forward: the lot the
--   credit went back on is not the one the records name), or the named lot's
--   holder is not whoever holds the benefits. Where the package never
--   changed hands (its own lot, held by its buyer A, who holds the benefits)
--   it did nothing, and the credit stayed on that lot for A to spend. On
--   copies, a S$100 package sold to A, two S$20 sessions paid from it (where
--   it says so the S$60 left moved by an Owner to F, and the first session
--   refunded while paid):
--   * the guided Cancel with "Record refund paid" (S$80 paid back, nothing
--     owed after), then the second session refunded: A holds S$20 of a
--     cancelled package, net S$20, the refund due S$0, and a refund by line
--     is refused ("That is more than the S$0.00 still owed back"): G2, G3.
--     The same without the Move (GN; S$40 kept, then S$20 spendable), with a
--     third session refunded too (P2s: A S$40), with the second session's
--     wallet payment corrected to cash or to S$5 less instead (PFc, PFa: A
--     S$20, S$5), and where S$20 of credit is worth less than S$20: the S$100
--     + S$10 Bonus package (PCx: A S$20, nothing owed back where a refund by
--     line pays back S$18.18), the S$140 Premium Bundle (PCv: S$14.00) and
--     that bundle S$7 off (PCd: S$13.64);
--   * refunded by line in full with an Owner's override (what was spent paid
--     back too, 'refunded'), then the session refunded: A holds S$20 of a
--     refunded invoice, net S$0 (RX0);
--   * a plain Cancel, the session refunded: A can spend it (PCs) before the
--     refund by line (which pays it back: PC, as before);
--   * cancelled, S$60 refunded by line, reopened (it waits), the second
--     session refunded while it waits: A can spend it before the payment
--     (PWs); paid, A holds S$80 (PW, as before);
--   * cancelled, the session refunded, then a 'transfer' customer change of
--     the cancelled package: refused, "Paid credit 20.00 (Partly spent)",
--     though nothing was spent (PCh);
--   * paid in part (S$40 of S$100: S$40 of its credit released before full
--     payment, 327 and 356), a S$20 session paid from it, cancelled, the
--     session refunded: A can spend S$20 of a cancelled package (PTs), and
--     the release record still counts it as spent, so the package reads as
--     used and "Record refund paid" of the S$40 held is refused ("Part of
--     what ... sold has been used (credit spent)": PT1r); after a guided
--     Cancel that kept it all (S$0 owed back), A holds S$20 while S$40 is
--     kept for what was used (PTg); the same with Correct payment instead
--     (PTf, PTfa), on the Premium Bundle (PTv), and with the buyer merged or
--     the customer changed before the session (PTmb, PTcb);
--   * paid in part (S$40), a session paid from its released credit,
--     cancelled (Cancel's write-off closes that lot: 'reversed', locked),
--     reopened and paid in full (a benefit row then names that lot), then
--     cancelled again and the session refunded: the refund opened the lot
--     again ('active', still locked) and, the lot being locked, 462's
--     forwarder did nothing: A could spend S$20 of a cancelled package
--     (PTRc, PTRcs; Cancel once more left it too, PTRa); the same after a
--     guided Cancel (A S$20, S$0 owed back, the refund by line refused:
--     PTRg, PTRgb, PTRgs), refunded in full with an override (A S$20 of a
--     refunded invoice: PTRx), with a reopening waiting (PTRw), with Correct
--     payment instead (PTRf, PTRfb) and on the Premium Bundle (PTRv, PTRvb);
--     and with a 'transfer' customer change after the payment the S$20
--     stayed with A, not with B who holds the benefits, paid (PTRhp: A S$20,
--     B S$80) or cancelled (PTRh).
--   Nothing was lost while the package was reopened and paid in the end (the
--   payment gave it all), but the customer of a cancelled or refunded
--   package held credit its net payment does not buy, after a guided
--   Cancel what it was owed back could not be paid back, and credit did not
--   follow a 'transfer' change.
--
-- THE OWNER'S ANSWERS
--
--   22 Oct 2026: credit follows a merge and a 'transfer' customer change; a
--   Move's recipient keeps what was moved; refunds paid back count as not
--   used. 24 Oct 2026 (462, 470): a cancel or refund takes back what the
--   invoice gave from whoever holds it now; the customer holds exactly what
--   the net payment buys; nothing stranded on a lot no record names; Correct
--   payment keeps working. 26 Oct 2026, answering 470's NOT COVERED:
--   (1) "Yes, fix it after 470": the plain case works the same way as 470's
--   reissue case (this file; also where the package was paid in part, B
--   and C below, the same rule: a cancel takes back what the invoice gave, the
--   customer holds what the net payment buys); (2) a package refunded in
--   full with an override whose spent part then comes back: held back, owed
--   to nobody,
--   the Finance panel offering a refund by line that is refused: accepted,
--   so RX0 now ends as RX1 does; (3) credit given back while a reopening
--   waits is held for that reopening's payment, nobody can spend it until
--   then: accepted, and this file applies the same rule to the plain case
--   (queued for that payment, as 470 does); (5) the deadlock 470 added for
--   its reissue case (a session's refund overlapping the package's refund
--   by line or reopening's payment: one is rolled back, staff do it again):
--   accepted for that case (471 extends it to the plain case: NOT COVERED 5).
--
-- WHAT THIS DOES (one function changed, whole text; nothing added; no table,
-- column, trigger or grant changes)
--
--   credit_given_back_follows(uuid) (470's). As before it runs at commit for
--   each ledger row giving credit back on a lot (462's deferred trigger on
--   customer_credit_ledger, unchanged: a 'reverse' row of a refunded or
--   corrected sale paid from the lot, 'invoice_payment_refund',
--   'payment_correction', 'special_sale', 'rental', 'rental_late_fee'). Two
--   branches change, and one lock is read past (C).
--   (A) Where the lot the records name alone holds the credit and its
--   holder is whoever holds the benefits (or no live record is left to give
--   it to), while the invoice is cancelled or refunded, or a reopening of it
--   waits to be settled. Before, it did nothing; now what that lot holds is
--   held back for the cancellation where it is:
--   * taken back on that lot as the cancellation's own ledger row, the kind
--     and reason 470 writes ('adjust_decrease', 'invoice_cancel_benefit',
--     the invoice; "Held back by the invoice's cancellation for whoever holds
--     its benefits now"), the lot at S$0;
--   * added to what the row holds back (cancelled_unused_value) and, on a
--     cancelled invoice whose Owner or Manager stated what is owed back
--     (cancel_refund_owed), its money added to that by 470's rule (the row's
--     paid value for its granted credit, rounded on all the row holds back
--     before and after, as refund_invoice_recorded rounds it: S$20 of credit
--     is S$20 on the S$100 package, S$18.18 on the Bonus package, S$14.00 on
--     the Premium Bundle, S$13.64 on it discounted);
--   * while a reopening waits, queued for its payment (the latest waiting
--     request, invoice_reopen_benefits, as 470 queues), which gives it back
--     (apply_reopened_invoice_benefits, unchanged); while cancelled, not
--     queued, so the next reopening queues it with the cancellation's other
--     rows (reopen_invoice, unchanged);
--   * the invoice's Audit Log row 'credit_given_back_followed', as 470
--     writes it, with 'held_in_place' true (the lot, the holder, the credit
--     held back, the request it is queued for, the amount owed back before,
--     added and after).
--   Nothing is reissued: no new lot, no record repointed, nothing carried or
--   closed. Everything else is 470's text unchanged (the reissue branch,
--   apart from the lock C reads past, the locks taken, the holder, the
--   chain limit, the refusals).
--   So everything the cancellation holds back for the row is on the lot the
--   records name, held by the benefits' holder, as with a reissue: a refund
--   by line of the cancelled package pays it back (what is owed back is what
--   the refund options offer, S$0 once paid); a refund by line while a
--   reopening waits finds it (446's matching reads the queue on that lot);
--   the reopening's payment gives it to the holder; a customer change or
--   Cancel again has nothing spendable to move or take; nobody can spend
--   credit of a cancelled or refunded package, nor of one whose reopening
--   waits (credit released before full payment while the invoice is open
--   again is the buyer's: B, NOT COVERED 8; credit given back on a lot an
--   Owner reversed or 328's repair replaced is not held back, as before:
--   NOT COVERED 10). A refunded invoice's
--   held-back credit is owed to nobody (it was paid back; RX0 as RX1, the
--   Owner's answer 2).
--   (B) Where no benefit row names the lot (before, nothing was done): the
--   release record whose lots reach it (credit_package_progress_lots, paid
--   credit released before full payment: the lot or one it replaced, as
--   credit_lot_chain reads them), while its invoice is cancelled or refunded
--   and no benefit row names a lot of that chain (Cancel's write-off's own
--   test): what the lot holds is taken back as Cancel's write-off takes it
--   ('adjust_decrease', 'invoice_cancel_released_credit', or
--   'invoice_refund_released_credit' when refunded, the invoice; "Held back
--   by the invoice's cancellation: credit released before it was paid in
--   full"), the release record counts that much less as spent
--   (released_amount, never below S$0), the lot is closed again ('reversed',
--   locked, as Cancel left it), and on a cancelled invoice whose Owner or
--   Manager stated what is owed back S$1 is added to that for each S$1 held
--   back (release_credit_package_paid_credit releases S$1 of credit for
--   each S$1 received; NOT COVERED 8); the Audit Log row as in (A), with
--   'released_credit' true, the release record and what it counted as
--   spent before and after. So the package stops reading as used once
--   nothing it released is spent (cancelled_invoice_used_value reads the
--   release record) and "Record refund paid" records the money held.
--   Nothing is queued and nothing is held while the invoice is open again:
--   a reopening releases again what its money buys (356).
--   (C) The lock Cancel's write-off puts on a lot of credit released before
--   full payment (writeoff_released_credit_on_close: 'reversed', locked)
--   is no longer a reason to pass that lot over. Once the invoice is
--   reopened and paid in full a benefit row names that lot
--   (capture_invoice_benefit_values names the lot the release record
--   reaches), and a refund or correction of a sale paid from it opens it
--   again ('active', the lock left as it was: refund_invoice_recorded,
--   correct_invoice_payment); before, the forwarder returned there. Now the
--   named lot, the lots it replaced (what still holds credit), the category
--   check and what is drawn read such a lot as any other: a lot of a chain
--   of the invoice's release record (credit_lot_chain), locked, with no
--   ledger row of an Owner's reversal ('reversal', reverse_credit_lot) or
--   328's repair ('credit_lot_provenance_repair'); those two locks are
--   passed over as before (so credit a refund or correction gives back on
--   such a lot stays there, spendable, while the package is cancelled,
--   refunded or waiting, as with 470: NOT COVERED 10). A reissue copies a
--   lot whole, its lock with it but not its ledger rows (the reopening's
--   payment to another customer, apply_reopened_invoice_benefits; a
--   customer change, move_invoice_benefits_to_customer; a merge,
--   merge_customer_records): such a copy in the chain is read as Cancel's
--   write-off's too, also where it was an Owner's reversal that locked the
--   lot it copies (O1: B's session refunded while cancelled gives S$20
--   back on B's copy, held back there, where 470 left it with B), and the
--   lot it replaced, behind it, is drawn with it (HQ1: a 'transfer' change
--   while cancelled, then the reopening's payment reissues A's lot to B;
--   S2, paid from A's lot, refunded while paid: B S$100, where 470 left A
--   S$20 that Cancel could not take back; HQ3, cancelled again first: held
--   back, S$100). So while the invoice is cancelled, refunded or
--   waiting what it holds is held back where it is (A: the cancellation's
--   own row, the benefit row's cancelled_unused_value, its money added to
--   what is owed back by the row's paid value; S$20 on the S$100 package,
--   S$14.00 on the Premium Bundle); where whoever holds the benefits is
--   someone else (a 'transfer' customer change) it goes to them as 462 and
--   470 do: paid, as credit to spend (PTRhp: B S$100); cancelled, held back
--   for the cancellation (PTRh). The lot stays locked (at S$0, or with what
--   a reopening's payment gives back on it, which its holder can spend:
--   allocate_invoice_wallet_credit does not read the lock, as before).
--   Money afterwards (the suite, each case): the package's refund by line
--   pays back what was received less what is still spent; nobody holds
--   credit of a cancelled or refunded package (but on a lot an Owner
--   reversed: NOT COVERED 10); reopened and paid, the holder
--   holds what the net payment buys; Cancel takes it all back; paid in part
--   and cancelled, the buyer holds nothing and the money held is recorded as
--   paid back once nothing released is spent.
--
-- WHY THIS WAY
--
--   Held back where it is, by the forwarder, with the cancellation's own
--   ledger row, because every reader already counts that row exactly as it
--   counts what Cancel took back on the same lot: refund_invoice_recorded's
--   refund by line and 446's matching (the row's cancelled_unused_value and
--   the queue on the lot it names), 448's invoice_benefit_unused_elsewhere
--   and cancelled_invoice_used_value (the row's cancellation rows not queued,
--   or queued and waiting, less what it holds back: unchanged by a row taken
--   and held back alike, so nothing reads as spent that is not), 451's and
--   reopen_invoice's queueing (every cancellation row not queued yet),
--   460's and 462's apply_reopened_invoice_benefits (a queued row given back
--   on its lot and off the row it belongs to), the Reopen dialog's credit to
--   reinstate (what is not queued yet: NOT COVERED 7), and 470's own branch
--   (its in-place replacement reads the held rows by the same reason). The
--   other ways:
--   * changing refund_invoice_recorded, cancel_invoice_recorded or
--     reopen_invoice (they would have to tell a sale's refund on a cancelled
--     package from their own rows, and are pinned by 446, 448, 451, 457,
--     458, 462, 463, 464 and 470): not changed;
--   * reissuing the plain lot as 470 does (a new lot for the same holder):
--     the same outcome with a longer chain and a new lot for every refund
--     (462's chain limit), and the records repointed for nothing;
--   * holding back only what this transaction gave back (the trigger knows
--     each row's amount, the forwarder only the lot): needs 462's trigger
--     function and a second forwarder signature, and differs where the lot
--     already holds credit at that commit: credit given back before 471 that
--     still sits spendable (the header's query, 4 and 6: an Owner decision),
--     and credit a refund in full with an Owner's 'larger_refund' override
--     left on a refunded package (NOT COVERED 4). 470's reissue branch
--     already sweeps both with the new credit; swept the same way here, as
--     the Owner asked the plain case to work as the reissue case does.
--   The trigger and its WHEN stay as they are: the forwarder runs only for a
--   refunded or corrected sale's row (never for Cancel's, a refund by line's,
--   a reopening's, a merge's, a change's or a Move's), and while a package is
--   cancelled, refunded or waiting nothing else raises the lot its records
--   name (Cancel takes it all; a reopening's payment gives back only when the
--   invoice is settled, and then nothing is held), so what the lot holds at
--   commit is what such refunds and corrections gave back, apart from what
--   NOT COVERED 4 names.
--   For credit released before full payment (B): Cancel's own write-off row
--   and the release record, because that is how Cancel closes such credit.
--   After the hold the lot and the release record are as they would be had
--   the session been refunded before the Cancel (the suite's PTB): so every
--   reader of the release record counts it as it counts that state:
--   cancelled_invoice_used_value (nothing spent: the money can be recorded
--   as paid back), a reopening's release (release_credit_package_paid_
--   credit: what the money counts toward the line less what the record
--   still counts), settlement (capture_invoice_benefit_values: what the
--   record counts), Cancel again (a record at S$0 or a reversed lot is
--   passed over). The one difference is a guided Cancel's stated amount
--   owed back: it stays stated and grows by what is held back (470's rule).
--   A benefit row for released credit instead would make it a settled
--   line's, which it is not.
--   For the lock (C): read past in the forwarder, the one function this
--   changes, rather than unlocked where the benefit row is made
--   (capture_invoice_benefit_values, at settlement) or where the refund
--   opens the lot (refund_invoice_recorded, correct_invoice_payment): those
--   are pinned by 446 to 470 and the settlement and refund paths are not
--   this file's to change. Cancel's write-off is told from an Owner's
--   reversal and 328's repair by their ledger rows, not by its own: it
--   writes none when the lot was spent in full, and it locks only lots of
--   the release record. Who locks a lot is checked as read (SAFETY). A
--   copy a reissue made carries the lock and no ledger row of it, so it
--   reads as Cancel's write-off's whichever lock it copied (O1; NOT
--   COVERED 10).
--
-- NOT CHANGED
--
--   * refund_invoice_recorded (804ecd82), cancel_invoice_recorded (de52d9db),
--     reopen_invoice (0ff61e4e), correct_invoice (04d647e1),
--     correct_invoice_payment (af993370), apply_reopened_invoice_benefits
--     (36eaa722), refund_special_credit, merge_customer_records,
--     move_invoice_benefits_to_customer, invoice_transferable_benefits (NOT
--     COVERED 9), reverse_credit_lot,
--     invoice_action_plan, invoice_financial_position,
--     resolve_invoice_action_v2, invoice_benefit_unused_elsewhere,
--     cancelled_invoice_used_value, invoice_reopen_preview(_before_sessions),
--     the refund options, the credit statement, 462's ancestry, holder,
--     trace, ledger trigger and its trigger function (84e2d978), 463's
--     helpers, the triggers on invoices, the release record's readers and
--     writers (writeoff_released_credit_on_close, release_credit_package_
--     paid_credit, capture_invoice_benefit_values, trim_released_paid_credit,
--     reclaim_released_credit_of_removed_lines, repair_credit_package_
--     progress_lots, credit_lot_chain, credit_lot_current and the rest named
--     below): pinned, unchanged.
--   * Edge Functions, settings: no change. What staff see (read from src;
--     the page change that goes with this file, wording only; true once 471
--     is in: with 470 alone it is true only for 470's reissue case, so it
--     goes out with 471 or after it, never before): a session's wallet
--     payment refunded or corrected while the package it was paid from is
--     cancelled or refunded, or, where that package was paid in full before,
--     while its reopening waits for payment, is held back there (credit
--     released before full payment is not held while the invoice is open
--     again: NOT COVERED 8, PTr2), so the guided refund's wallet destination
--     no longer says only "restores the original credit"
--     (InvoiceGuidedAction.tsx: " — back to the credit it was paid from
--     (held back there while that package is cancelled or refunded, or, if
--     it was paid in full before, while its reopening waits for payment: see
--     that package's invoice)"), and the Finance panel's "Record refund
--     paid" ("a payment made with credit gives that credit back (held back
--     there while the package it came from is cancelled or refunded, or, if
--     it was paid in full before, while its reopening waits for payment: see
--     that package's invoice)"), its sources ('credit restored or held
--     back') and the refund by line's note ("Wallet portions return to their
--     original credit source (held back there while ...)") say the same
--     (InvoiceFinancePanel.tsx); the cancelled package's amount owed back
--     reads "Owed back to the customer: S$20.00 (what was stated when it was
--     cancelled, less what has been recorded since, plus the value of any of
--     its credit a refund has given back since)", the total of its parts
--     (refund-owed-stated: after G2 the S$80 stated was recorded paid and the
--     S$20 is the session's refund held back). The wording does not hold for
--     a lot an Owner reversed or 328's repair replaced (NOT COVERED 10:
--     such credit is not held back; no page reverses a lot); it is kept
--     as it is, for the Owner to decide with that item. Their page tests are updated
--     with them (refund-due-panel, wallet-sources-443, and the browser check
--     credit-balance-print-browser, not run here). Not changed:
--     invoice_action_plan's summary line "(restores the original credit)"
--     (pinned; the guided page shows the summary only for a plan without
--     effects, and a refund's plan always has them); the customer's
--     statement shows "Credit returned" then "Adjustment — decrease — Held
--     back by the invoice's cancellation for whoever holds its benefits now"
--     (for released credit: "... cancellation: credit released before it was
--     paid in full"), the wallet balance S$0; the package's Finance panel
--     shows the larger amount owed back and offers it in the refund by line
--     (its options read what the row holds back); the Reopen dialog's
--     "Revoked credit to reinstate after settlement" counts what is held
--     back and not queued for a reopening yet (NOT COVERED 7).
--
-- NOT COVERED (for the Owner; the suite checks 1 to 4 and 7 to 10 as they are)
--
--   1. 470's NOT COVERED 2, now also without a reissue (accepted by the
--      Owner, 26 Oct 2026): a package refunded in full with an override (what
--      was spent paid back too) whose spent part then comes back: held back,
--      owed to nobody (it was paid back), the Finance panel offering a refund
--      by line that is refused, until a reopening (RX0, as RX1).
--   2. 470's NOT COVERED 3, now also without a reissue (accepted, 26 Oct):
--      credit given back while a reopening waits cannot be spent until that
--      reopening's payment (PWs; before, the buyer could spend it).
--   3. 445's NOT COVERED 1: merging the buyer, who spent the package's credit,
--      into another record is still refused ("Credit allocations cannot be
--      changed once recorded"), before and after the hold alike (PM, PMg);
--      a 'transfer' customer change of the cancelled package now passes
--      once the credit is held back (PCh: before, refused "Partly spent").
--   4. Credit given back before 471 while a package was cancelled, refunded
--      or waiting (G2's state on production today), and credit released
--      before full payment given back so (PT1's state), is not repaired: it
--      stays spendable on the lot the records name. The header's query lists
--      those invoices (4, 6), for the Owner: a data fix (held back, its money
--      added to what is owed back), or left with the customer (then reissued
--      as other credit by a data fix, so it is no longer the package's).
--      Until then, the next refund or correction of a sale paid from that
--      lot, even a date-only correction, holds it back with the new credit,
--      as 470 does with a reissue (its query's 3): the amount owed back then
--      grows by both (the suite's M cases MG2x, MG2d, MPTa). The same
--      happens to credit that a refund in full with an Owner's
--      'larger_refund' override left on a refunded package because it took
--      back less credit than was unused (an API call: no page sends that
--      override): it stays spendable until the next refund or correction of
--      a sale paid from that lot, which holds it back with the new credit,
--      owed to nobody (as RX1), though no sale's refund gave it back
--      (KNOWN K6: S$50 left, then S$70 held back at the session's refund;
--      before 471 the buyer kept S$70). The query lists such a package under
--      4 too. And credit given back before 471 on the released lot a Cancel
--      closed that a benefit row names (paid in part, cancelled, reopened
--      and paid in full, then cancelled or refunded again, or its customer
--      changed): it stays where it went (MPTRs: A spends it), and the next
--      refund or correction of a sale paid from that lot holds it back, or
--      moves it to whoever holds the benefits, with the new credit (MPTRa:
--      S$40 owed back). The query lists it under 4, or under 8 where the
--      benefits are someone else's. The same where that lot is behind the
--      lot the records name (a reissue copied it, lock and all: a 'transfer'
--      change, then the reopening's payment reissues A's lot to B): HQ3
--      (cancelled again), then S2, paid from A's lot, refunded before 471:
--      A S$20 of a cancelled package, which A can spend (MHQ3s); reopened
--      and paid, it stays with A, B S$80, and Cancel cannot take A's S$20
--      back (MHQ3r); listed under 8 (under 4 where that lot's holder holds
--      the benefits), before 471 and after.
--   5. 470's NOT COVERED 5 (a deadlock; the Owner accepted it for 470's
--      reissue case), now also without a reissue, which is most packages,
--      for credit released before full payment (B) and for the released lot
--      a Cancel closed (C; for B and C the same lock order, read from the
--      code, not timed on copies), while cancelled, refunded
--      or waiting: a refund or Correct payment of a session paid from the
--      package's lot that is held back locks the package's invoice at
--      commit, after the lot (refund_invoice_recorded took the lot first); a
--      refund by line, Cancel, Move, change or reopening's payment of that
--      package committing at the same moment takes the invoice first, then
--      the lot. One is stopped with "deadlock
--      detected" and rolled back whole (nothing of it recorded); staff do it
--      again, and it then ends as it would have. On copies (26 Oct 2026, two
--      sessions, the session's refund held open 3 s): with 471, against the
--      package's refund by line and against its reopening's payment, 4 of 4
--      tries deadlocked (the session's refund was the one rolled back each
--      time); without 471 (470 alone), 0 of 4 (both committed). Before 471
--      the plain case took no lock here. A session refund while the package
--      is paid (the usual case) still moves nothing and locks nothing here,
--      as before. A real fix changes the lock order of
--      refund_invoice_recorded or of the reopening's payment, which this
--      does not change. For the Owner to accept for the plain case too.
--   6. A summary, a Finance panel or a Reopen dialog open on a screen when
--      this goes in shows the old answer until it is opened again; the server
--      checks again.
--   7. The Reopen dialog's "Revoked credit to reinstate after settlement"
--      (invoice_reopen_preview, pinned) counts the cancellation's rows not
--      queued for a reopening yet. Credit held back while a reopening waits
--      is queued for it (2); if the invoice is then cancelled again and
--      reopened, the dialog leaves it out, as it already leaves out Cancel's
--      own rows queued by the earlier reopening (an older gap, 417 and 451):
--      cancelled, S$60 refunded by line, reopened (S$60 queued), S2 refunded
--      (S$20 held back, queued), cancelled again: the dialog says S$0.00
--      (S$20.00 without 471, S$80.00 would be right), and the payment gives
--      A S$80 both ways (KNOWN K5). The money is right; what staff are told
--      is short. A fix reads the unapplied queue in the preview, as 417 does
--      for voucher units (its own migration).
--   8. Credit released before full payment (B): what is owed back grows by
--      S$1 for each S$1 held back, the release's own rate. Where the money
--      paid toward the line was more than its paid credit before settlement
--      (a Premium Bundle paid past it: S$120 of S$140 released S$100), the
--      money behind that credit is more than S$1 for S$1, and the Owner or
--      Manager states the rest. A guided Cancel of a part-paid package with
--      credit spent records S$0 owed back (its plan offers no money back for
--      a line no benefit row names and asks for no amount: before 471 and
--      unchanged); what is held back is added to that (PTg: S$0, then S$20;
--      the rest stays kept for what was used until an Owner states more).
--      Nothing is held while the invoice is open again and has not been paid
--      in full since: the reopening released again what its money buys, and
--      credit given back then on the lot Cancel closed is the buyer's, as
--      before (PTr2: A S$40, what S$40 buys). The page wording says so (it
--      names a waiting reopening only for a package paid in full before).
--   9. A 'transfer' customer change of a package paid in part whose
--      released credit was spent, then cancelled, reopened and paid in full,
--      is allowed: the released lot the Cancel closed ('reversed', S$0)
--      does not read as "Partly spent" (invoice_transferable_benefits,
--      pinned, unchanged by 471), so the change moves the S$60 left to B
--      and the S$40 spent stays A's use (KNOWN K9); the same package paid in
--      full with the same spending is refused ("Paid credit 60.00 (Partly
--      spent)"). The same with and without 471 (an older gap, found by 471's
--      review). Once changed, credit a later refund gives back on that lot
--      follows B (C). A fix judges such a lot by its benefit row in
--      invoice_transferable_benefits (its own migration); for the Owner.
--  10. Credit given back on a lot an Owner reversed (reverse_credit_lot:
--      'reversed', locked, its 'reversal' ledger row) or 328's repair
--      replaced (its 'credit_lot_provenance_repair' row), by a later refund
--      or correction of a sale paid from that lot (refund_invoice_recorded
--      and correct_invoice_payment set the lot 'active' again and leave the
--      lock): 471 passes such a lot over, as 470 does, so while its package
--      is cancelled, refunded or waiting that credit is not held back and
--      its holder can spend it (allocate_invoice_wallet_credit does not read
--      the lock); after a guided Cancel the refund by line is then refused
--      at S$0.00 still owed back. The same with and without 471, on copies
--      (26 Oct 2026, the suite's cases): paid in full, an Owner reversed the
--      S$60 left, cancelled, S1 refunded: A S$20, which A spends (PX, PXs);
--      paid in part, the released lot's S$15 reversed, cancelled, reopened
--      and paid, a guided Cancel (S$0 owed back), S1 refunded: A S$20, the
--      refund by line refused, A spends it (S8gb, S8gs); the released lot a
--      Cancel closed, opened by S1's refund while paid, then reversed (S$20),
--      a guided Cancel, S2 refunded: A S$5, refused (S2gb). The reversal
--      itself stays reversed: what is left is only what was given back
--      after it. The page wording ("held back there while that package is
--      cancelled or refunded") does not hold for such a lot. A copy of such
--      a lot that a reissue made (a customer change, the reopening's
--      payment to another customer, a merge) has no reversal row of its own
--      and is read as Cancel's write-off's (C): O1, S$20 given back on B's
--      copy is held back there (470 left it with B), while the original
--      lot, had it held any, would be passed over. No page or Edge Function
--      reverses a lot or runs the repair (read from src and
--      supabase/functions): both functions are the server's alone (their
--      grant: postgres and the service role; 339 made them internal), and
--      the reversal needs the caller to be an active Owner or Manager
--      (auth.uid()), so only a direct SQL call (a data fix) or a reversal
--      made before 339 does it; whether production has such a lot was not
--      read. The header's query lists them (9), and the first
--      run names their invoices, for the Owner: a data fix, or left with
--      the customer. A fix (while the package is cancelled, refunded or
--      waiting, hold back what such a lot holds; the reversed amount stays
--      reversed, as only what the lot holds is drawn) is an Owner decision
--      and its own migration: it changes the forwarder's lock test for the
--      package's own lot too (PX has no release record).
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the text is the tested one (its AFTER md5); the function is its BEFORE
--     (470's AFTER: replaced) or its AFTER (left alone), anything else
--     refused; no other function takes its name; so a second run changes
--     nothing;
--   * the functions it relies on are as read on production at 470 (pinned,
--     below; 470's list, allocate_invoice_wallet_credit, which re-spends a
--     corrected payment, every reader and writer of the release record, and
--     reverse_credit_lot, whose ledger rows tell an Owner's reversal),
--     among them every trigger function an update of invoices runs (it sets
--     cancel_refund_owed), the triggers on invoices and 462's ledger trigger
--     as read; a lot's statuses ('active', 'reversed'); the columns read and
--     written have these types; one queue row per ledger row; a lot never
--     holds more than it was granted; lots and the ledger keep their
--     history; who calls the forwarder, who reads or writes a cancellation's
--     ledger rows, the reopening queue, the amount owed back, the release
--     record and its write-off rows, what gives credit back on a lot, and
--     what locks a lot (Cancel's write-off, an Owner's reversal, 328's
--     repair), as read (a reissue copies a lot whole, its lock with it:
--     apply_reopened_invoice_benefits, move_invoice_benefits_to_customer
--     and merge_customer_records, pinned; 462's own reissue unlocks, and a
--     Move refuses a locked lot);
--   * on the first run nothing is refused for the data (471 needs no
--     decision before it goes in); the invoices of the header's query 4, 6,
--     8 and 9 are named in a notice (invoice numbers only), for the Owner;
--   * who may call the function is as read, compared as sets, and kept;
--   * afterwards: the AFTER md5 and the grants as tested.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0471, so it leaves no row): a made-up Owner, store, S$100 package, S$20
--   session and eight customers (fictional ACMA phones no customer has),
--   eight times: the package sold to A, two sessions paid from it (one in
--   (b), (g) and (h)); (a) cancelled, S$60 stated owed back (a stand-in for a
--   guided Cancel that kept S$40 for the two sessions) and refunded by line,
--   the second session refunded: at the commit point A holds nothing, the
--   package's own lot (no lot reissued) holds S$0 with one held-back row,
--   the row holds back S$20, S$20 owed back and due; refunded by line: net
--   S$20, nothing held back or owed; (b) refunded by line in full with an
--   Owner's override, the session refunded: held back, net S$0 (owed to
--   nobody); (c) cancelled,
--   S$60 refunded by line, reopened (it waits), the second session refunded:
--   held back and queued for that reopening's request; paid: A S$80,
--   nothing waiting or held back; (d) cancelled, the second session
--   refunded, reopened (paid at once): A S$80, Cancel's refund due S$80; (e)
--   paid (a control), the second session refunded: A S$80 to spend, nothing
--   held back; (f) as (a), the second session's wallet payment corrected to
--   S$5 less instead: S$5 held back and owed; refunded by line: net S$35;
--   (g) paid S$40 of S$100 (S$40 of credit released), cancelled, the session
--   refunded: held back as Cancel's write-off on the released lot (closed
--   again, no lot made), the release record at S$0, nothing reads as used,
--   and the S$40 is then recorded as paid back (net S$0); (h) paid S$40 of
--   S$100, the session paid from it, cancelled (the released lot closed:
--   'reversed', locked), reopened and paid in full (a benefit row names
--   that lot), cancelled again, the session refunded: held back where it is
--   on that lot (one held-back row of S$20, the row holds back S$20, A
--   holds nothing, no lot made).
--   Its credit ledger rows draw entry numbers (a sequence, which an undone
--   transaction does not give back: a gap, as 443 to 470's self-tests).
--   Locks: the function's catalogue row to the end of the apply, and the
--   rows the self-test writes and undoes; no table is locked against
--   ordinary writes. The self-test takes the commission advisory locks
--   (affiliate_payout_lock and staff_payout_lock, through its cancels and
--   refunds) and new invoice numbers, so it waits for any app cancel,
--   refund, commission-writing payment or invoice creation still open, and
--   those wait for it, for under a second. If one stays open longer than
--   the 5 s lock timeout, or an invoice created at the same moment takes
--   the self-test's invoice number, the apply stops, changing nothing, and
--   can be run again. Credit given back by a refund still open when 471
--   commits is handled by 471's text at that refund's commit (the forwarder
--   reads everything again then). Apply at a quiet time.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (470 in, 26 Oct 2026: 0f581614, 1387 functions; the
--   grant list 381ef69c; head 20261026070425) -> 471. 462, 463 and 470 are
--   in; 471 replaces 470's credit_given_back_follows (its AFTER is 471's
--   BEFORE) and pins the rest. If anything else goes in first, work the
--   fingerprints out again and check that it changes none of the functions
--   or triggers pinned below.
--   1. Before it, read only (invoice numbers and counts only; production
--      was not read for this file, so what it lists is not known yet). 471
--      refuses no state (only code that is not as read), so this lists
--      whose answer changes (1 to 3, 5, 7) and what needs the Owner (4, 6,
--      8, 9). Run this text, not an earlier one: it also reads the lots
--      behind the lot the records name (a reissue copied them, lock and
--      all) and 9, and a package cancelled, reopened and paid since reads
--      'paid', so a read of an earlier text that listed nothing does not
--      rule these out:
--     with recursive
--     st as (
--       select i.id, i.status::text as status, i.cancel_refund_owed is not null as owed_stated,
--              exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = i.id and q.applied_at is null) as waiting
--         from public.invoices i where i.deleted_at is null),
--     -- the lots of an invoice's credit released before full payment that a
--     -- Cancel's write-off closed (locked; not an Owner's reversal nor 328's
--     -- repair): 471 reads them as any other lot (a refund opens them again);
--     -- also a copy of one that a reissue made (the reopening's payment, a
--     -- customer change, a merge: each copies the lot whole, its lock with it)
--     wo as (
--       select pl.invoice_id, w.lot_id
--         from public.credit_package_progress_lots pl
--         cross join lateral unnest(public.credit_lot_chain(pl.lot_id)) w(lot_id)
--         join public.customer_credit_lots c on c.id = w.lot_id
--        where c.is_locked
--          and not exists (select 1 from public.customer_credit_ledger e
--                           where e.customer_id = c.customer_id and e.lot_id = c.id
--                             and e.source_type in ('reversal', 'credit_lot_provenance_repair'))),
--     -- the lots an invoice's benefit rows name on which 471 holds back where
--     -- it is: no lot they replaced holds credit, held by whoever holds the
--     -- benefits (or by the last live record), the invoice cancelled,
--     -- refunded or waiting for a reopening's payment
--     plain as (
--       select b.invoice_id, l.id as lot_id, l.remaining_amount, st.status, st.owed_stated, st.waiting
--         from public.invoice_benefit_values b
--         join st on st.id = b.invoice_id
--         join public.customer_credit_lots l on l.id = b.lot_id
--        where (st.status in ('cancelled', 'refunded') or st.waiting)
--          and (l.status = 'active' and not l.is_locked
--               or exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = l.id))
--          and not exists (select 1 from public.customer_credit_lots p
--                           where p.id = any (public.credit_lot_ancestry(l.id)) and p.id <> l.id
--                             and p.remaining_amount > 0 and p.status = 'active'
--                             and (not p.is_locked or exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = p.id)))
--          and coalesce(public.invoice_credit_live_holder(b.invoice_id, l.customer_id,
--                case when public.invoice_benefit_moved_to_other(b.id) then 'infinity'::timestamptz else l.created_at end),
--                l.customer_id) = l.customer_id),
--     -- such a closed lot (or its copy) behind the lot a benefit row names (one
--     -- the named lot replaced), the named lot one 471 reads, the invoice
--     -- cancelled, refunded or waiting, or that lot held by someone other than
--     -- whoever holds the benefits now: what it holds is drawn with the named
--     -- lot (before, the lock kept it where it was)
--     behind as (
--       select b.invoice_id, p.id as lot_id, p.remaining_amount, p.status as lot_status, st.status, st.owed_stated, st.waiting,
--              p.customer_id <> h.holder as elsewhere
--         from public.invoice_benefit_values b
--         join st on st.id = b.invoice_id
--         join public.customer_credit_lots l on l.id = b.lot_id
--         cross join lateral (select coalesce(public.invoice_credit_live_holder(b.invoice_id, l.customer_id,
--                               case when public.invoice_benefit_moved_to_other(b.id) then 'infinity'::timestamptz else l.created_at end),
--                               l.customer_id) as holder) h
--         join public.customer_credit_lots p on p.id = any (public.credit_lot_ancestry(l.id)) and p.id <> l.id
--        where exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = p.id)
--          and l.status = 'active'
--          and (not l.is_locked or exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = l.id))
--          and (st.status in ('cancelled', 'refunded') or st.waiting or p.customer_id <> h.holder)),
--     -- such a closed lot a benefit row names (paid in part, cancelled, reopened
--     -- and paid in full since), held by someone other than whoever holds the
--     -- benefits now (a 'transfer' customer change, a merge), any status; and
--     -- such a lot behind it held so
--     other as (
--       select b.invoice_id, l.id as lot_id, l.remaining_amount, l.status as lot_status
--         from public.invoice_benefit_values b
--         join st on st.id = b.invoice_id
--         join public.customer_credit_lots l on l.id = b.lot_id
--        where exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = l.id)
--          and coalesce(public.invoice_credit_live_holder(b.invoice_id, l.customer_id,
--                case when public.invoice_benefit_moved_to_other(b.id) then 'infinity'::timestamptz else l.created_at end),
--                l.customer_id) <> l.customer_id
--       union all
--       select x.invoice_id, x.lot_id, x.remaining_amount, x.lot_status from behind x where x.elsewhere),
--     osold(invoice_id, n) as (
--       select o.invoice_id,
--              (select count(*) from public.invoice_line_credit_allocations a where a.lot_id = o.lot_id and a.amount > coalesce(a.reversed_amount, 0))
--              + (select count(*) from public.special_credit_allocations s where s.lot_id = o.lot_id and s.amount > coalesce(s.reversed_amount, 0))
--         from other o),
--     -- (B) the release records of cancelled or refunded invoices (paid
--     -- credit released before full payment) that Cancel's write-off reads
--     -- (no benefit row names a lot of their chain), with each chain's lots
--     rel as (
--       select pl.invoice_id, x.lot_id, l.remaining_amount, l.status as lot_status
--         from public.credit_package_progress_lots pl
--         join st on st.id = pl.invoice_id
--         cross join lateral unnest(public.credit_lot_chain(pl.lot_id)) x(lot_id)
--         join public.customer_credit_lots l on l.id = x.lot_id
--        where pl.released_amount > 0 and st.status in ('cancelled', 'refunded')
--          and not exists (select 1 from public.invoice_benefit_values b where b.lot_id = any (public.credit_lot_chain(pl.lot_id)))),
--     rsold(invoice_id, n) as (
--       select r.invoice_id,
--              (select count(*) from public.invoice_line_credit_allocations a where a.lot_id = r.lot_id and a.amount > coalesce(a.reversed_amount, 0))
--              + (select count(*) from public.special_credit_allocations s where s.lot_id = r.lot_id and s.amount > coalesce(s.reversed_amount, 0))
--         from rel r),
--     sold(invoice_id, lot_id, status, owed_stated, waiting, n) as (
--       select p.invoice_id, p.lot_id, p.status, p.owed_stated, p.waiting,
--              (select count(*) from public.invoice_line_credit_allocations a where a.lot_id = p.lot_id and a.amount > coalesce(a.reversed_amount, 0))
--              + (select count(*) from public.special_credit_allocations s where s.lot_id = p.lot_id and s.amount > coalesce(s.reversed_amount, 0))
--         from plain p
--       union all
--       select x.invoice_id, x.lot_id, x.status, x.owed_stated, x.waiting,
--              (select count(*) from public.invoice_line_credit_allocations a where a.lot_id = x.lot_id and a.amount > coalesce(a.reversed_amount, 0))
--              + (select count(*) from public.special_credit_allocations s where s.lot_id = x.lot_id and s.amount > coalesce(s.reversed_amount, 0))
--         from behind x where not x.elsewhere),
--     -- the lots an invoice's benefit rows name, or lots they replaced, that an
--     -- Owner reversed or 328's repair replaced (locked, with that ledger row),
--     -- holding credit again (a refund or correction gave it back since) while
--     -- the invoice is cancelled, refunded or waiting: 471 passes them over
--     rv as (
--       select distinct b.invoice_id, p.id as lot_id
--         from public.invoice_benefit_values b
--         join st on st.id = b.invoice_id
--         join public.customer_credit_lots p on p.id = any (public.credit_lot_ancestry(b.lot_id))
--        where (st.status in ('cancelled', 'refunded') or st.waiting)
--          and p.is_locked and p.status = 'active' and p.remaining_amount > 0
--          and exists (select 1 from public.customer_credit_ledger e
--                       where e.customer_id = p.customer_id and e.lot_id = p.id
--                         and e.source_type in ('reversal', 'credit_lot_provenance_repair'))),
--     found(reason, invoice_id, n) as (
--       select '1 changes: cancelled, with an amount owed back stated (a guided Cancel), and sales paid from the lot its records name (or, behind it, a lot of its credit released before full payment that a Cancel closed) that can still be refunded or corrected (the credit they give back is now held back and its money added to what is owed back; before, the customer could spend it and nothing more could be paid back)', s.invoice_id, sum(s.n)
--         from sold s where s.n > 0 and s.status = 'cancelled' and s.owed_stated
--        group by s.invoice_id
--       union all
--       select '2 changes: cancelled with no amount owed back stated, or refunded, and sales paid from the lot its records name (or, behind it, a lot of its credit released before full payment that a Cancel closed) that can still be refunded or corrected (the credit they give back is now held back: a refund by line pays it back; on a refunded invoice it is owed to nobody, 470''s NOT COVERED 2; before, the customer could spend it)', s.invoice_id, sum(s.n)
--         from sold s where s.n > 0 and (s.status = 'cancelled' and not s.owed_stated or s.status = 'refunded')
--        group by s.invoice_id
--       union all
--       select '3 changes: waiting for a reopening''s payment, with sales paid from the lot its records name (or, behind it, a lot of its credit released before full payment that a Cancel closed) that can still be refunded or corrected (the credit they give back is now held back and queued for that payment, which gives it back; before, the customer could spend it while it waited)', s.invoice_id, sum(s.n)
--         from sold s where s.n > 0 and s.status not in ('cancelled', 'refunded') and s.waiting
--        group by s.invoice_id
--       union all
--       select '4 for the Owner (not changed by 471): cancelled, refunded or waiting for a reopening''s payment, with credit spendable today on the lot its records name, or behind it on a lot of its credit released before full payment that a Cancel closed (given back after the cancel before 471, or left on a refunded package by an Owner''s ''larger_refund'' override): a data fix, or left with the customer; until then the next refund or correction of a sale paid from that lot holds it back with the new credit (on a refunded invoice owed to nobody) (the count is of lots)', p.invoice_id, count(*)
--         from (select p.invoice_id from plain p where p.remaining_amount > 0
--               union all
--               select x.invoice_id from behind x where not x.elsewhere and x.remaining_amount > 0 and x.lot_status = 'active') p
--        group by p.invoice_id
--       union all
--       select '5 changes: cancelled or refunded, paid in part, with sales paid from its credit released before full payment that can still be refunded or corrected (the credit they give back is now taken back as Cancel''s write-off and no longer counted as spent, so the money held can be recorded as paid back once nothing released is spent; where an amount owed back was stated, S$1 is added to it for each S$1; before, the customer could spend it and the package read as used)', r.invoice_id, sum(r.n)
--         from rsold r where r.n > 0
--        group by r.invoice_id
--       union all
--       select '6 for the Owner (not changed by 471): cancelled or refunded, paid in part, with credit spendable today on a lot of its credit released before full payment (given back after the cancel, before 471): a data fix, or left with the customer; until then the next refund or correction of a sale paid from that lot holds it back with the new credit (the count is of lots)', r.invoice_id, count(*)
--         from rel r where r.remaining_amount > 0 and r.lot_status = 'active'
--        group by r.invoice_id
--       union all
--       select '7 changes: paid in part, cancelled, reopened and paid in full since (a benefit row names the lot of its credit released before full payment that the Cancel closed, or a copy of it that a reissue made, with that lot behind it), that lot held by someone other than whoever holds the benefits now, with sales paid from it that can still be refunded or corrected (the credit they give back now goes to whoever holds the benefits, held back while the invoice is cancelled, refunded or waiting; before, it stayed with the customer it went back to) (the count is of sales)', o.invoice_id, sum(o.n)
--         from osold o where o.n > 0
--        group by o.invoice_id
--       union all
--       select '8 for the Owner (not changed by 471): as 7, with credit spendable today on that lot (given back before 471): a data fix, or left with the customer; until then the next refund or correction of a sale paid from that lot moves it with the new credit (the count is of lots)', o.invoice_id, count(*)
--         from other o where o.remaining_amount > 0 and o.lot_status = 'active'
--        group by o.invoice_id
--       union all
--       select '9 for the Owner (not changed by 471: NOT COVERED 10): cancelled, refunded or waiting for a reopening''s payment, with credit spendable today on the lot its records name, or one it replaced, that an Owner reversed (reverse_credit_lot) or 328''s repair replaced, given back on it since by a refund or correction: 471 passes such a lot over, so that credit stays spendable, and so does what the next refund or correction of a sale paid from it gives back: a data fix, or left with the customer (the count is of lots)', r.invoice_id, count(*)
--         from rv r
--        group by r.invoice_id)
--     select f.reason, i.invoice_no, f.n
--       from found f join public.invoices i on i.id = f.invoice_id
--      order by f.reason, i.invoice_no
--      (The suite runs this same text on its cases' states before 471 and
--      checks what it lists.)
--   2. Dry run on a copy of production as it is then: work out its
--      fingerprint and grant list first (they must be the BEFORE figures
--      below, or be worked out again on that copy); apply this file twice;
--      the first run ends at the AFTER fingerprint below, the second changes
--      nothing ("left alone"); and the suite, with the earlier suites below.
--   3. Apply (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself.
--   4. The page change (InvoiceGuidedAction.tsx, InvoiceFinancePanel.tsx and
--      their page tests) goes out with 471 or after it, never before: with
--      470 alone its wording is not true for a package that never changed
--      hands (NOT CHANGED).
--   Afterwards (checked on copies of production at 470, 26 Oct 2026): a
--   re-run of 470 refuses (its forwarder is neither its BEFORE nor its
--   AFTER), changing nothing; 471's own leaves all alone. Both are applied,
--   so nothing is lost. The suites that check the forwarder where 471 is in
--   (-v nomig=1): cancelled-package-refund-470 (S; P6's C0 and C0r, held in
--   place; KNOWN K (1) the 471 way), move-merge-leftovers-462 (S) and
--   change-store-moves-bundle-vouchers-463 (S), each by 471's AFTER md5.
--   function-grants is unchanged (nothing is added). The page tests that
--   read the wording changed with it: refund-due-panel and
--   wallet-sources-443 (run), credit-balance-print-browser (a browser check,
--   updated, not run).
--
-- BEFORE (production at 470, 26 Oct 2026; md5 of pg_get_functiondef with
-- search_path public)
--   changed
--   credit_given_back_follows(uuid)                                    b7720a148f5371bd2bd844d3076ea3b2  (470's)
--   relied on, not changed (pinned)
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)          804ecd829cfecf713783a09a05d93c7e
--   cancel_invoice_recorded(uuid,text,uuid)                            de52d9dbaef8ab15163bef35cb9d733d
--   reopen_invoice(uuid,text,uuid)                                     0ff61e4ead121c198ea7f90a7fc78274
--   correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)          af99337094edb6d73b9cc0ae00fbf138
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                        04d647e13e9424a9375942e5812e91a2
--   refund_special_credit(text,uuid)                                   e019e28ad79539d771376c9b38d7e27e
--   apply_reopened_invoice_benefits()                                  36eaa7224e514d3e7e42e3eeb51acfb5
--   invoice_reopen_preview_before_sessions(uuid)                       12206ed066495024421b3b44a6a9d8e2
--   invoice_reopen_preview(uuid)                                       e09ebf9c0841ef5463f96b26f4933541
--   invoice_benefit_unused_elsewhere(uuid)                             d35d7c8ae7187985ea64f8a5c38a7d79
--   cancelled_invoice_used_value(uuid)                                 055a3b07b1c15ffb1ac19039fa6cb650
--   invoice_action_plan(uuid,text,jsonb)                               383d618edb28c3c9a360242d038a022c
--   invoice_financial_position(uuid)                                   ba7eccbfeff217c8b1969b0e55a010ca
--   resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean) 201f08ebf14a64cd88d411a7cfb4c9c4
--   merge_customer_records(uuid,uuid,text,uuid)                        ba05c2b1fb4c0e14d369c01d06a635b0
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)             c01606c84ee13ddcd88c15521d6d9aed
--   invoice_transferable_benefits(uuid)                                68736a39ed765ee787242bc62bbaeebb
--   transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)          7aebd7120bc3928db46df0941cb20889
--   invoice_benefits_holder(uuid,uuid,timestamp with time zone)        55995ff6e1ffd4a1172cb930512a34b0
--   invoice_credit_live_holder(uuid,uuid,timestamp with time zone)     a5692590ef3e8a7a7dd7e8ff7cfa9568
--   credit_lot_ancestry(uuid)                                          52b3cae789b6b52a12bb2f798af40cbe
--   invoice_benefit_moved_to_other(uuid)                               7016bed898e1bbe9d0ac4a05037d07c2
--   invoice_credit_transfer_origin(uuid)                               1e8beeccfbf7e432edffc1598acddb53
--   trg_credit_given_back_follows()                                    84e2d978b74b56a9508e4f4f5b518c22
--   invoice_credit_lot_ids(uuid)                                       50346a2e9aea50b31d4207c43b2f197c
--   ensure_customer_wallet(uuid)                                       8ef18daebbbe3c12f2024290ea8416e8
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   trg_credit_lot_immutable()                                         0fc74da0dcc9b436dfd26c4582542f6c
--   trg_credit_ledger_immutable()                                      071ec0ccd5fc13107de0d11f85ba8c28
--   customer_credit_statement(uuid,date,date)                          1ba4a16a8208906f9e88efbc716bd1dd
--   invoice_refund_options_before_sessions(uuid)                       bd3afcc79cd2f06f983607d54fed167c
--   apply_reopened_invoice_vouchers()                                  6684840544d1ad8a28e2415934300054
--   delete_customer(uuid,text,text)                                    5b407735574fc3cacd8067c4dc8213f4
--   allocate_invoice_wallet_credit(uuid,numeric,text,text)             da8aa986c92d765a8028741f33bf56b0
--   (the release record's readers and writers: credit released before full payment, 327 to 356)
--   writeoff_released_credit_on_close(uuid,text,text)                  284a89cfb965e8028136b5f8a4f2bf08
--   release_credit_package_paid_credit(uuid)                           530521c100163445e5a0b99799fbcccc
--   credit_package_released_paid_credit(uuid)                          6b27388462747e3c13f3da0b9ad165c0
--   capture_invoice_benefit_values(uuid)                               d5e061945c2921a1af86f8c99a349e98
--   credit_lot_chain(uuid)                                             556e725784154cbffc23d3ad900f9366
--   credit_lot_current(uuid)                                           d48fb24e6eb9733d7f867e42fa703e7b
--   trim_released_paid_credit(uuid,text,boolean)                       14ded4342c3e65eb98547d224263519f
--   reclaim_released_credit_of_removed_lines(uuid,jsonb,text)          823cd6a96c813b43bf2767dc1644e943
--   repair_credit_package_progress_lots()                              ebd2a1a9f8ce7a9c1c272168b30b5ce3
--   credit_package_money_toward_line(uuid)                             798c2d67d55bb1d140232ff06ffb1034
--   credit_line_paid_entitlement(uuid)                                 da2404a1db281b46a44231bd071a069a
--   credit_lot_source_group(uuid)                                      6b902cb426210eb10ee9a15344ff100b
--   customer_credit_balances(uuid)                                     c2287779ce0ec9c52eeec41952055f78
--   invoice_commission_benefit_source(uuid)                            f8d3d29fae79065a252a8c5231cc2d4b
--   update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean) 1f034561a461bdb46a1e6274e0d04606
--   (an Owner's reversal, told by its ledger rows from Cancel's write-off's lock)
--   reverse_credit_lot(uuid,text,text,text)                            10c1a3d8e3bb003fbaf01cf879f97c5e
--   (the trigger functions an update of invoices runs)
--   trg_legacy_refund_guard()                                          089965ef41a18fe3c54dd622e743075a
--   trg_lock_on_settle()                                               39c6478cdaec553c2ab8ceaf55058960
--   validate_invoice_business_metadata()                               c6e4436575e1c5ec8580d2b3d9d11d50
--   track_invoice_business_date_version()                              2c1e7ac8c5c2cfea8ddc5122adfc5d92
--   trg_create_therapy_on_paid()                                       012ae4e305b9870fa5596f740c0427b9
--   trg_fulfil_from_warehouse()                                        4abf4bf68e4f00658a8da66469e7059e
--   trg_issue_sold_vouchers_on_paid()                                  cf0b5610b77edfea2683751d5c25ca1d
--   the triggers on invoices (md5 of their definitions, by name)       92c94e3ebc6113a68d972330bbca8938 (19 triggers)
--   public function fingerprint, production now (470)                  0f5816140d494a8085c6f4f255795c00 (1387 functions; head 20261026070425)
--   grant list (string_agg(signature '=' proacl, '|'), sorted)          381ef69cb44f960ff981585ff8402fa1 (production lists the same
--                                                                      grants in another order: compare as sets)
-- AFTER (for later guards)
--   credit_given_back_follows(uuid)                                    1417d83e7d7be49209f5cd1369d07ec7  (grants kept: the service role)
--   public function fingerprint, worked out on a copy of production at 470 (26 Oct 2026; a second run the same):
--     production now (470) -> 471                                      fd61e1a11dce76dd9ad4348f6bb99180 (1387 functions: none added, none dropped)
--   grant list after 471                                               381ef69cb44f960ff981585ff8402fa1 (unchanged)
--   the triggers on invoices                                           92c94e3ebc6113a68d972330bbca8938 (19, unchanged)
--
-- Test: scripts/invoices/tests/plain-cancelled-package-credit-471.sql (begin
-- ... rollback; it installs this file twice; -v nomig=1 where it is in). It
-- reproduces G2, G3, RX0, their plain siblings, the part-paid cases (PT...)
-- and those reopened and paid in full since (PTR...) first, then checks the
-- header's query (1 to 9, also lots behind the lot the records name: HQ...),
-- the refusals, the
-- install, every case after 471 with 462's invariants and Cancel, the
-- held-back row in place (no lot reissued), the amount owed back by its
-- money (the S$100 package, the Bonus package, the Premium Bundle and that
-- bundle discounted), the queue while a reopening waits and its payment,
-- 446's matching, Cancel again, a customer change after the hold, paid in
-- part: Cancel's write-off row on the released lot, the release record and
-- "Record refund paid"; reopened and paid in full since: held back on the
-- released lot the Cancel closed, or forwarded from it to whoever holds the
-- benefits, and from a copy of it (O1); cases begun before 471 and finished
-- after (MHQ3...: the lot behind the named lot), the controls unchanged,
-- and NOT COVERED 1 to 4 and 7 to 10 as KNOWN (10: a lot an Owner reversed,
-- the same with and without 471: PX, S8gb, S2gb). Each app
-- call is followed by what its commit does (462's trigger is deferred).
-- Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The function this changes: BEFORE (production, 26 Oct 2026: 470's
  -- AFTER) and AFTER md5s; who may call it, as read (kept) ══════════════════
  c_sig constant text := 'credit_given_back_follows(uuid)';
  c_before constant text := 'b7720a148f5371bd2bd844d3076ea3b2';
  c_after constant text := '1417d83e7d7be49209f5cd1369d07ec7';
  c_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';

  -- ══ The whole text (exactly as the database prints it back) ═════════════
  c_def_follows constant text := $d1$CREATE OR REPLACE FUNCTION public.credit_given_back_follows(p_lot_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 462 (the Owner, 24 Oct 2026: credit and vouchers follow a merge and a
-- customer change that takes the benefits along; "B, the package's holder
-- now"): credit given back on a lot by a refund or a correction of a sale
-- paid from it (refund_invoice_recorded's wallet refund, correct_invoice_
-- payment, refund_special_credit) belongs to whoever holds the benefits of
-- the invoice that lot's credit came from. Run at commit, once per such
-- ledger row (the trigger credit_given_back_follows), after whatever the
-- same transaction did with that credit (a payment correction re-spends it
-- first). Where the lot is one an invoice's benefit row names, or one such
-- a lot replaced (a merge, a customer change, a reopening's give-back, or
-- this), what that lot and the lots it replaced still hold goes to the
-- benefits' holder as ONE new lot: they are drawn down (ledger
-- 'adjust_decrease', 'credit_given_back_reassignment_out'), the holder is
-- granted the total (ledger 'grant', 'credit_given_back_reassignment_in';
-- the lot copies the named lot's source, category, restrictions, store and
-- dates), and the invoice's records name the new lot (its benefit value, its
-- sale's lots, a split's issued lot), as 445, 447 and 460 do. The new lot
-- replaces the named lot (reassigned_from_lot_id naming it); where the named
-- lot is one this made and nothing has touched since (its grant, and what
-- it holds back for a cancellation, 470, its only ledger rows), the new lot
-- takes its place instead (reassigned_from_lot_id naming the lot it
-- replaced), so separate refunds do not make the chain longer; a chain is
-- never made longer than 12 lots (the readers' limit): that is refused, for
-- the Owner. Nothing is done where the named lot alone holds it and its
-- holder is the benefits' holder while the invoice is paid (as before; 471:
-- otherwise it is held back where it is, below), nor for a lot no invoice's
-- benefit row names or replaced (wallet credit of other kinds; 471: credit
-- released before the invoice was paid in full, below). The holder:
-- invoice_credit_live_holder (460's rule; a Move's recipient keeps what was
-- moved, following merges alone; never a deleted record), else the holder of
-- the lot the credit went back on, if not deleted; with none, the credit
-- stays only where it is on the named lot, and otherwise this is refused.
-- 470 (the Owner, 24 Oct 2026: "Go live now, fix the gap next"; 462's NOT
-- COVERED 10, K7b: a cancel or refund takes back what the invoice gave from
-- whoever holds it now, nothing stranded on a lot no record names): before,
-- nothing was done while the invoice was cancelled or refunded, or a
-- reopening of it waited to be settled, and credit given back then onto a
-- lot the chain had replaced stayed there, with that lot's holder, out of
-- reach of a refund by line of the cancelled invoice (S$80 of S$100 paid
-- back; the old customer kept S$20). Now, while the invoice is cancelled or
-- refunded, or a reopening of it waits, such credit goes to the benefits'
-- holder in the same way, but held back for the cancellation: the new lot
-- is granted what is drawn and what the cancellation already holds back for
-- the row on these lots (its 'invoice_cancel_benefit' rows, not given back
-- by a reopening), and holds nothing; both are taken back on it (the same
-- kind of row). What the cancellation held there is closed where it was
-- (its reopening queue row, invoice_reopen_benefits, marked applied, as 446
-- closes a row given in full; one not queued yet gets such a row, so no
-- reopening queues it again) and queued again on the new lot where a
-- reopening's payment waits for it; what is drawn is queued for that
-- payment too, while a reopening waits. What is drawn is added to what the
-- row holds back (cancelled_unused_value) and, on a cancelled invoice whose
-- Owner or Manager stated what is owed back (cancel_refund_owed), its money
-- value is added to that (what a refund by line of the row pays back for
-- it): it was kept for credit that was spent, and is not spent now. So
-- everything the cancellation holds back for the row is on the lot the
-- records name, where a refund by line of the cancelled invoice pays it
-- back, a refund by line made while a reopening waits finds it (446 reads
-- the queue on that lot), and the reopening's payment gives it to the
-- holder. Asked to be cancelled or refunded (the legacy statuses), it
-- follows as for a paid invoice: the benefits are still the invoice's.
-- 471 (the Owner, 26 Oct 2026, answering 470's NOT COVERED 1: "Yes, fix it
-- after 470": the plain case works as the reissue case does; a cancel or
-- refund takes back what the invoice gave, the customer holds exactly what
-- the net payment buys, refunds paid back count as not used): where nothing
-- was reissued (the named lot alone holds it and its holder is whoever holds
-- the benefits, or no live record is left), credit given back while the
-- invoice is cancelled or refunded, or a reopening of it waits, stayed on
-- that lot and could be spent (after a guided Cancel that recorded the
-- refund, the customer kept S$20 and nothing more could be paid back; a
-- package refunded in full with an override left S$20). Now it is held back
-- for the cancellation where it is: what the named lot holds is taken back
-- on it with the cancellation's own ledger row (the same kind and reason as
-- above), added to cancelled_unused_value and, where an amount owed back is
-- stated on a cancelled invoice, its money added to that, by the same rule;
-- while a reopening waits it is queued for its payment (the latest waiting
-- request; the Owner, 26 Oct 2026, accepting 470's NOT COVERED 3), which
-- gives it back. Nothing is reissued, so nothing else is carried or closed.
-- Whether anything needs doing is read first without locks (a refund that
-- moves nothing takes no lock here); only then are the invoice, its benefit
-- row and the lots locked, in the order Cancel and Reopen take them (then
-- the reopening's queue rows on those lots), and everything read again.
-- 471 also (the same answer): paid credit released before the invoice was
-- paid in full (327, 356: no benefit row names its lot; the release record,
-- credit_package_progress_lots, does). Credit given back on such a lot while
-- its invoice is cancelled or refunded stayed there for the buyer to spend,
-- and the release record still counted it as spent, so a plain Cancel could
-- not record the money paid back. Now it is taken back as Cancel's write-off
-- takes it (writeoff_released_credit_on_close's kind of row:
-- 'adjust_decrease', 'invoice_cancel_released_credit', or
-- 'invoice_refund_released_credit' when refunded, the invoice), the release
-- record counts that much less as spent, and the lot is closed again
-- ('reversed', locked), as Cancel left it; where an amount owed back is
-- stated on a cancelled invoice, S$1 is added to it for each S$1 held back
-- (credit is released S$1 for each S$1 received). Nothing is held while the
-- invoice is open again: its reopening released again the credit its money
-- buys (356). Read first without locks, then the invoice, the lot and the
-- release record locked in Cancel's order, and read again.
-- 471 also: such a lot that Cancel's write-off closed ('reversed', locked)
-- and a benefit row names once the invoice was reopened and paid in full
-- (capture_invoice_benefit_values names it) is opened again by a refund or
-- a correction of a sale paid from it ('active', still locked); it was
-- passed over as locked, so the credit stayed there for its holder to
-- spend, cancelled or not, and did not follow a 'transfer' change. Such a
-- lock is no longer a reason to pass it over (an Owner's reversal and
-- 328's repair still are): it is held back, or follows the benefits'
-- holder, as above.
declare v_try int:=0; v_k int; v_cur uuid; v_prev uuid; v_inv uuid; v_locked boolean:=false; v_status text;
 b public.invoice_benefit_values%rowtype; n public.customer_credit_lots%rowtype; x record;
 v_chain uuid[]; v_h uuid; v_more boolean; v_total numeric:=0; v_new uuid; v_wallet uuid; v_cap numeric;
 v_from jsonb:='[]'::jsonb; v_parent uuid; v_up uuid; v_depth int; v_replace boolean;
 -- 470
 v_hold boolean:=false; v_wait uuid; v_carry numeric:=0; v_held jsonb:='[]'::jsonb; v_mark uuid; v_take uuid; hb record;
 v_owed numeric; v_owed_new numeric; v_owed_add numeric;
 -- 471
 v_plain boolean:=false; v_rel uuid; v_rel_amt numeric; v_wo uuid[]:='{}';
 c_reason constant text:='Credit given back goes to whoever holds the invoice''s benefits now';
 c_held constant text:='Held back by the invoice''s cancellation for whoever holds its benefits now';
 c_held_rel constant text:='Held back by the invoice''s cancellation: credit released before it was paid in full';
begin
 if p_lot_id is null then return; end if;
 loop
  v_try:=v_try+1;
  if v_try>4 then
   raise exception 'Credit given back on lot % could not be matched to the invoice that names it (it kept changing). Nothing was recorded; try again.',p_lot_id;
  end if;
  -- The lot the records name: this lot, or the nearest lot reissued from it
  -- (a reissue carries the source of the lot it replaces; a Move's lot,
  -- which before 445 copied its source lot's link, is not one) that a
  -- benefit row names.
  v_cur:=null; v_inv:=null; v_k:=null;
  with recursive w(id,k) as (
    select p_lot_id,0
    union all
    select l.id,w.k+1 from w join public.customer_credit_lots o on o.id=w.id
      join public.customer_credit_lots l on l.reassigned_from_lot_id=o.id
       and (l.source_type,l.source_record_id) is not distinct from (o.source_type,o.source_record_id)
     where w.k<40)
  select w.id,w.k,bv.invoice_id into v_cur,v_k,v_inv
    from w join public.invoice_benefit_values bv on bv.lot_id=w.id
    join public.customer_credit_lots cl on cl.id=w.id
   order by w.k,cl.created_at desc,cl.id desc limit 1;
  if v_cur is null then exit; end if;
  if v_k>12 then
   raise exception 'Credit given back on lot % is more than 12 lots down from the lot invoice % names for it, further than the app follows. Nothing was recorded; ask the Owner.',
    p_lot_id,(select invoice_no from public.invoices where id=v_inv);
  end if;
  -- 470: whether the invoice's cancellation holds back what it gave: the
  -- invoice cancelled or refunded, or a reopening of it waiting to be
  -- settled (then the latest such reopening's request, to queue for).
  select i.status::text into v_status from public.invoices i where i.id=v_inv;
  v_wait:=null;
  if v_status not in ('cancelled','refunded') then
   select q.request_id into v_wait from public.invoice_reopen_benefits q
    where q.invoice_id=v_inv and q.applied_at is null
    order by q.created_at desc,q.id desc limit 1;
  end if;
  v_hold:=coalesce(v_status in ('cancelled','refunded'),false) or v_wait is not null;
  select * into b from public.invoice_benefit_values where lot_id=v_cur and invoice_id=v_inv;
  if not found then continue; end if;
  select * into n from public.customer_credit_lots where id=v_cur;
  -- 471: a lot of the invoice's credit released before full payment that a
  -- Cancel's write-off closed ('reversed', locked), and that a refund or a
  -- correction has opened again ('active', still locked), is read as any
  -- other lot here, also where a benefit row names it after the invoice was
  -- reopened and paid in full; a lot an Owner reversed or 328's repair
  -- replaced is not (as before).
  v_wo:=array(select c.id from public.credit_package_progress_lots pl
               cross join lateral unnest(public.credit_lot_chain(pl.lot_id)) w(id)
               join public.customer_credit_lots c on c.id=w.id
              where pl.invoice_id=v_inv and c.is_locked
                and not exists(select 1 from public.customer_credit_ledger e
                                where e.customer_id=c.customer_id and e.lot_id=c.id
                                  and e.source_type in ('reversal','credit_lot_provenance_repair')));
  if n.status<>'active' or (n.is_locked and not (n.id=any(v_wo))) then return; end if;
  v_chain:=public.credit_lot_ancestry(n.id);
  if not (p_lot_id=any(v_chain)) then
   raise exception 'Credit given back on lot % is more than 12 lots down from the lot invoice % names for it, further than the app follows. Nothing was recorded; ask the Owner.',
    p_lot_id,(select invoice_no from public.invoices where id=v_inv);
  end if;
  v_h:=coalesce(public.invoice_credit_live_holder(b.invoice_id,n.customer_id,
                  -- 463 (the Owner, 24 Oct 2026, decision 2): only a Move to
                  -- someone else stays with its recipient (merges followed);
                  -- a Move to the same customer at another store is the
                  -- invoice's own (invoice_benefit_moved_to_other).
                  case when public.invoice_benefit_moved_to_other(b.id)
                       then 'infinity'::timestamptz else n.created_at end),
                (select c.id from public.customer_credit_lots pl join public.customers c on c.id=pl.customer_id
                  where pl.id=p_lot_id and c.deleted_at is null));
  v_more:=exists(select 1 from public.customer_credit_lots l
                  where l.id=any(v_chain) and l.id<>n.id and l.remaining_amount>0 and l.status='active'
                    and (not l.is_locked or l.id=any(v_wo)));
  -- 471: the named lot alone holds it and its holder is the benefits' (or no
  -- live record is left), while the cancellation holds back what the invoice
  -- gave: held back where it is.
  v_plain:=v_hold and not v_more and n.remaining_amount>0 and (v_h is null or n.customer_id=v_h);
  if not v_plain and not v_more and (n.remaining_amount<=0 or n.customer_id=v_h or v_h is null) then return; end if;
  if v_h is null and not v_plain then
   raise exception 'Credit given back on lot % belongs with the benefits of invoice %, but whoever holds them, the invoice''s customer and the customer it went back to are all deleted. Nothing was recorded; ask the Owner.',
    p_lot_id,(select invoice_no from public.invoices where id=v_inv);
  end if;
  exit when v_locked and v_cur=v_prev;
  -- Something moves: lock the invoice, then its benefit row, then the lots,
  -- as Cancel and Reopen take them; then read everything again.
  perform 1 from public.invoices where id=v_inv for update;
  perform 1 from public.invoice_benefit_values where id=b.id for update;
  perform 1 from public.customer_credit_lots where id=any(v_chain) order by created_at,id for update;
  v_locked:=true; v_prev:=v_cur;
 end loop;
 if v_cur is null then
  -- 471: no benefit row names it. The release record whose lots reach it:
  -- this lot or one it replaced (a merge's or customer change's reissue,
  -- or 328's replacement), as credit_lot_chain reads them forward.
  v_up:=p_lot_id; v_depth:=0; v_rel:=null;
  loop
   select pl.lot_id,pl.invoice_id into v_rel,v_inv from public.credit_package_progress_lots pl
    where pl.lot_id=v_up and pl.released_amount>0;
   exit when v_rel is not null;
   v_parent:=(select l.reassigned_from_lot_id from public.customer_credit_lots l where l.id=v_up);
   if v_parent is null then
    v_parent:=(select pl.replaces_lot_id from public.credit_package_progress_lots pl where pl.lot_id=v_up);
   end if;
   v_depth:=v_depth+1;
   exit when v_parent is null or v_depth>12;
   v_up:=v_parent;
  end loop;
  if v_rel is null or not (p_lot_id=any(public.credit_lot_chain(v_rel))) then return; end if;
  -- As Cancel's write-off: a settled line's benefit rows own its lots.
  if exists(select 1 from public.invoice_benefit_values bv where bv.lot_id=any(public.credit_lot_chain(v_rel))) then return; end if;
  if (select i.status::text from public.invoices i where i.id=v_inv) is distinct from 'cancelled'
     and (select i.status::text from public.invoices i where i.id=v_inv) is distinct from 'refunded' then return; end if;
  if coalesce((select l.remaining_amount from public.customer_credit_lots l where l.id=p_lot_id),0)<=0 then return; end if;
  perform 1 from public.invoices where id=v_inv for update;
  select * into n from public.customer_credit_lots where id=p_lot_id for update;
  select pl.released_amount into v_rel_amt from public.credit_package_progress_lots pl where pl.lot_id=v_rel for update;
  select i.status::text,i.cancel_refund_owed into v_status,v_owed from public.invoices i where i.id=v_inv;
  if coalesce(v_status,'') not in ('cancelled','refunded') or coalesce(n.remaining_amount,0)<=0 then return; end if;
  v_total:=n.remaining_amount;
  insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
   values(n.wallet_id,n.customer_id,'adjust_decrease',n.category,v_total,n.id,
          case when v_status='cancelled' then 'invoice_cancel_released_credit' else 'invoice_refund_released_credit' end,
          v_inv,n.store_id,c_held_rel,auth.uid(),auth.uid());
  update public.credit_package_progress_lots set released_amount=greatest(released_amount-v_total,0) where lot_id=v_rel;
  update public.customer_credit_lots set remaining_amount=0,status='reversed',is_locked=true,updated_at=now() where id=n.id;
  if v_status='cancelled' and v_owed is not null then
   v_owed_add:=v_total;
   v_owed_new:=v_owed+v_owed_add;
   update public.invoices set cancel_refund_owed=v_owed_new where id=v_inv;
  end if;
  perform public.write_audit_ex('invoices',v_inv,'credit_given_back_followed',null,
    jsonb_build_object('lot_id',n.id,'to_customer',n.customer_id,'amount',v_total,
      'from',jsonb_build_array(jsonb_build_object('lot_id',n.id,'customer_id',n.customer_id,'amount',v_total)),
      'benefit_id',null,'replaces_lot_id',null,'in_place_of_lot_id',null,'held_in_place',true,
      'released_credit',true,'release_lot_id',v_rel,'released_before',v_rel_amt,
      'released_after',greatest(coalesce(v_rel_amt,0)-v_total,0),
      'held_back',v_total,'queued_for_request',null,
      'refund_owed',v_owed,'refund_owed_added',v_owed_add,'refund_owed_now',v_owed_new),
    'invoices',c_held_rel,(select store_id from public.invoices where id=v_inv));
  return;
 end if;
 if v_plain then
  -- 471: held back where it is, for the cancellation: taken back on the
  -- named lot as the cancellation's own row (queued for a waiting
  -- reopening's payment), held back by the row and, where an amount owed
  -- back is stated on a cancelled invoice, owed back in money (as below).
  v_total:=n.remaining_amount;
  update public.customer_credit_lots set remaining_amount=0,updated_at=now() where id=n.id;
  insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
   values(n.wallet_id,n.customer_id,'adjust_decrease',n.category,v_total,n.id,'invoice_cancel_benefit',b.invoice_id,n.store_id,c_held,auth.uid(),auth.uid())
   returning id into v_take;
  if v_wait is not null then
   insert into public.invoice_reopen_benefits(invoice_id,source_ledger_id,request_id,amount,created_by)
    values(b.invoice_id,v_take,v_wait,v_total,auth.uid());
  end if;
  update public.invoice_benefit_values set cancelled_unused_value=cancelled_unused_value+v_total where id=b.id;
  select cancel_refund_owed into v_owed from public.invoices where id=b.invoice_id;
  if v_status='cancelled' and v_owed is not null then
   v_owed_add:=case when b.paid_value>0 and b.granted_value>0
                    then round(b.paid_value*(b.cancelled_unused_value+v_total)/b.granted_value,2)
                         -round(b.paid_value*b.cancelled_unused_value/b.granted_value,2)
                    else 0 end;
   v_owed_new:=v_owed+v_owed_add;
   update public.invoices set cancel_refund_owed=v_owed_new where id=b.invoice_id;
  end if;
  perform public.write_audit_ex('invoices',b.invoice_id,'credit_given_back_followed',null,
    jsonb_build_object('lot_id',n.id,'to_customer',n.customer_id,'amount',v_total,
      'from',jsonb_build_array(jsonb_build_object('lot_id',n.id,'customer_id',n.customer_id,'amount',v_total)),
      'benefit_id',b.id,'replaces_lot_id',null,'in_place_of_lot_id',null,'held_in_place',true,
      'held_back',v_total,'held_back_before',0,'held_back_rows','[]'::jsonb,'held_back_mark',null,'queued_for_request',v_wait,
      'refund_owed',v_owed,'refund_owed_added',v_owed_add,'refund_owed_now',v_owed_new),
    'invoices',c_held,(select store_id from public.invoices where id=b.invoice_id));
  return;
 end if;
 if exists(select 1 from public.customer_credit_lots l
            where l.id=any(v_chain) and l.remaining_amount>0 and l.status='active' and (not l.is_locked or l.id=any(v_wo))
              and l.category is distinct from n.category) then
  raise exception 'Credit given back on lot % is not of the category of the lot invoice % names for it. Nothing was recorded; ask the Owner.',
   p_lot_id,(select invoice_no from public.invoices where id=b.invoice_id);
 end if;
 -- The new lot replaces the named lot, or takes its place where this made it
 -- and nothing has touched it since (its grant, and what it holds back for
 -- the cancellation, 470, its only ledger rows), so the chain does not grow.
 v_replace:=n.reassigned_from_lot_id is not null
   and not exists(select 1 from public.customer_credit_lots c where c.reassigned_from_lot_id=n.id)
   and (select count(*) from public.customer_credit_ledger e
         where e.lot_id=n.id and e.entry_type='grant' and e.source_type='credit_given_back_reassignment_in')=1
   and not exists(select 1 from public.customer_credit_ledger e
                   where e.lot_id=n.id
                     and not (e.entry_type='grant' and e.source_type='credit_given_back_reassignment_in'
                              or e.entry_type='adjust_decrease' and e.source_type='invoice_cancel_benefit'
                                 and e.source_record_id=b.invoice_id and e.reason=c_held))
   and n.remaining_amount=n.original_amount
         -coalesce((select sum(e.amount) from public.customer_credit_ledger e
                     where e.lot_id=n.id and e.entry_type='adjust_decrease' and e.source_type='invoice_cancel_benefit'
                       and e.source_record_id=b.invoice_id and e.reason=c_held),0);
 v_parent:=case when v_replace then n.reassigned_from_lot_id else n.id end;
 v_depth:=0; v_up:=v_parent;
 loop
  select l.reassigned_from_lot_id into v_up from public.customer_credit_lots l where l.id=v_up;
  exit when v_up is null or v_depth>=12;
  v_depth:=v_depth+1;
 end loop;
 if v_depth>=12 then
  raise exception 'Credit given back on lot % would make the chain of lots of invoice % longer than 12, further than the app follows. Nothing was recorded; ask the Owner.',
   p_lot_id,(select invoice_no from public.invoices where id=b.invoice_id);
 end if;
 v_new:=gen_random_uuid(); v_wallet:=public.ensure_customer_wallet(v_h);
 for x in select l.* from public.customer_credit_lots l
           where l.id=any(v_chain) and l.remaining_amount>0 and l.status='active' and (not l.is_locked or l.id=any(v_wo))
           order by l.created_at,l.id loop
  update public.customer_credit_lots set remaining_amount=0,updated_at=now() where id=x.id;
  insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
   values(x.wallet_id,x.customer_id,'adjust_decrease',x.category,x.remaining_amount,x.id,'credit_given_back_reassignment_out',b.invoice_id,x.store_id,c_reason,auth.uid(),auth.uid());
  v_total:=v_total+x.remaining_amount;
  v_from:=v_from||jsonb_build_object('lot_id',x.id,'customer_id',x.customer_id,'amount',x.remaining_amount);
 end loop;
 if v_total<=0 then return; end if;
 -- 470: what the cancellation already holds back for the row on these lots,
 -- not given back by a reopening (queued for a waiting one, or not queued yet).
 if v_hold then
  perform 1 from public.invoice_reopen_benefits q join public.customer_credit_ledger e on e.id=q.source_ledger_id
    where q.invoice_id=b.invoice_id and e.lot_id=any(v_chain) order by q.id for update of q;
  for hb in select e.id,e.amount,q.id as qid,q.amount as qamount,q.request_id
              from public.customer_credit_ledger e
              left join public.invoice_reopen_benefits q on q.source_ledger_id=e.id
             where e.lot_id=any(v_chain) and e.entry_type='adjust_decrease' and e.source_type='invoice_cancel_benefit'
               and e.source_record_id=b.invoice_id and q.applied_at is null
             order by e.entry_seq loop
   v_carry:=v_carry+coalesce(hb.qamount,hb.amount);
   v_held:=v_held||jsonb_build_object('ledger_id',hb.id,'amount',coalesce(hb.qamount,hb.amount),'queued_request_id',hb.request_id);
  end loop;
 end if;
 -- A Move's credit never comes to more than was moved (its trace needs it).
 if n.source_type='invoice_benefit_transfer' then
  select g.original_amount into v_cap
    from public.customer_credit_ledger e join public.customer_credit_lots g on g.id=e.lot_id
   where e.source_type='invoice_benefit_transfer_in' and e.source_record_id=n.source_record_id
   order by e.entry_seq limit 1;
  if v_cap is not null and v_total+v_carry>v_cap then
   raise exception 'Credit given back on lot % would come to S$% of credit an Owner moved, more than the S$% moved. Nothing was recorded; ask the Owner.',
    p_lot_id,to_char(v_total+v_carry,'FM999999990.00'),to_char(v_cap,'FM999999990.00');
  end if;
 end if;
 insert into public.customer_credit_lots
 select (jsonb_populate_record(null::public.customer_credit_lots,to_jsonb(n)||jsonb_build_object(
   'id',v_new,'wallet_id',v_wallet,'customer_id',v_h,
   'original_amount',v_total+v_carry,'remaining_amount',case when v_hold then 0 else v_total end,
   'status','active','is_locked',false,
   'reassigned_from_lot_id',v_parent,'reference_no',null,'reason',c_reason,'reversal_of_lot_id',null,
   'created_by',auth.uid(),'approved_by',auth.uid(),'created_at',clock_timestamp(),'updated_at',clock_timestamp()))).*;
 insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
  values(v_wallet,v_h,'grant',n.category,v_total+v_carry,v_new,'credit_given_back_reassignment_in',b.invoice_id,n.store_id,c_reason,auth.uid(),auth.uid());
 if v_hold then
  -- 470: what the cancellation held back is closed where it was and taken
  -- again on the new lot (queued again where a reopening's payment waits for
  -- it); then what was drawn is taken back too (queued while a reopening
  -- waits), and the row holds it back.
  v_mark:=gen_random_uuid();
  for hb in select (h->>'ledger_id')::uuid as ledger_id,(h->>'amount')::numeric as amount,
                   nullif(h->>'queued_request_id','')::uuid as request_id
              from jsonb_array_elements(v_held) h loop
   if hb.request_id is null then
    insert into public.invoice_reopen_benefits(invoice_id,source_ledger_id,request_id,amount,created_by,applied_at)
     values(b.invoice_id,hb.ledger_id,v_mark,hb.amount,auth.uid(),clock_timestamp());
   else
    update public.invoice_reopen_benefits set applied_at=clock_timestamp() where source_ledger_id=hb.ledger_id;
   end if;
   insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
    values(v_wallet,v_h,'adjust_decrease',n.category,hb.amount,v_new,'invoice_cancel_benefit',b.invoice_id,n.store_id,c_held,auth.uid(),auth.uid())
    returning id into v_take;
   if hb.request_id is not null then
    insert into public.invoice_reopen_benefits(invoice_id,source_ledger_id,request_id,amount,created_by)
     values(b.invoice_id,v_take,hb.request_id,hb.amount,auth.uid());
   end if;
  end loop;
  insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
   values(v_wallet,v_h,'adjust_decrease',n.category,v_total,v_new,'invoice_cancel_benefit',b.invoice_id,n.store_id,c_held,auth.uid(),auth.uid())
   returning id into v_take;
  if v_wait is not null then
   insert into public.invoice_reopen_benefits(invoice_id,source_ledger_id,request_id,amount,created_by)
    values(b.invoice_id,v_take,v_wait,v_total,auth.uid());
  end if;
  update public.invoice_benefit_values set cancelled_unused_value=cancelled_unused_value+v_total where id=b.id;
  select cancel_refund_owed into v_owed from public.invoices where id=b.invoice_id;
  if v_status='cancelled' and v_owed is not null then
   -- What is owed back is money: what was drawn adds what a refund by line
   -- of the row pays back for it (the row's paid value for its granted
   -- credit, rounded on all the row holds back, before and after, as
   -- refund_invoice_recorded rounds it), not its credit (with a Bonus, a
   -- Premium Bundle's other parts or a discount, credit is worth less).
   v_owed_add:=case when b.paid_value>0 and b.granted_value>0
                    then round(b.paid_value*(b.cancelled_unused_value+v_total)/b.granted_value,2)
                         -round(b.paid_value*b.cancelled_unused_value/b.granted_value,2)
                    else 0 end;
   v_owed_new:=v_owed+v_owed_add;
   update public.invoices set cancel_refund_owed=v_owed_new where id=b.invoice_id;
  end if;
 end if;
 update public.invoice_benefit_values set lot_id=v_new where lot_id=n.id;
 update public.credit_package_sales set credit_lot_id=v_new where credit_lot_id=n.id;
 update public.credit_package_sales set bonus_credit_lot_id=v_new where bonus_credit_lot_id=n.id;
 update public.premium_bundle_sales set paid_credit_lot_id=v_new where paid_credit_lot_id=n.id;
 update public.premium_bundle_sales set bonus_credit_lot_id=v_new where bonus_credit_lot_id=n.id;
 update public.invoice_credit_splits set issued_lot_id=v_new where issued_lot_id=n.id;
 perform public.write_audit_ex('invoices',b.invoice_id,'credit_given_back_followed',null,
   jsonb_build_object('lot_id',v_new,'to_customer',v_h,'amount',v_total,'from',v_from,'benefit_id',b.id,
     'replaces_lot_id',n.id,'in_place_of_lot_id',case when v_replace then n.id end)
   ||case when v_hold then jsonb_build_object('held_back',v_total,'held_back_before',v_carry,'held_back_rows',v_held,
                                              'held_back_mark',v_mark,'queued_for_request',v_wait,
                                              'refund_owed',v_owed,'refund_owed_added',v_owed_add,'refund_owed_now',v_owed_new)
          else '{}'::jsonb end,
   'invoices',case when v_hold then c_held else c_reason end,(select store_id from public.invoices where id=b.invoice_id));
end $function$
$d1$;

  -- ══ 462's ledger trigger, the reopening's settlement trigger and the
  -- triggers on invoices (an update of invoices runs them), as read ═════════
  c_ledger_trg_def constant text := $t$CREATE CONSTRAINT TRIGGER credit_given_back_follows AFTER INSERT ON public.customer_credit_ledger DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (((new.entry_type = 'reverse'::text) AND (new.lot_id IS NOT NULL) AND (new.source_type = ANY (ARRAY['invoice_payment_refund'::text, 'payment_correction'::text, 'special_sale'::text, 'rental'::text, 'rental_late_fee'::text])))) EXECUTE FUNCTION trg_credit_given_back_follows()$t$;
  c_settle_trg_def constant text := $t$CREATE TRIGGER invoice_reopen_benefits_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_benefits()$t$;
  c_inv_trg_md5 constant text := '92c94e3ebc6113a68d972330bbca8938';
  c_inv_trg_n constant int := 19;

  -- ══ Relied on, not changed (production at 470, 26 Oct 2026; the same as
  -- 470 pinned them, then the release record's readers and writers) ══════
  c_relied constant text[] := array[
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'reopen_invoice(uuid,text,uuid)',
    'correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'refund_special_credit(text,uuid)',
    'apply_reopened_invoice_benefits()',
    'invoice_reopen_preview_before_sessions(uuid)',
    'invoice_reopen_preview(uuid)',
    'invoice_benefit_unused_elsewhere(uuid)',
    'cancelled_invoice_used_value(uuid)',
    'invoice_action_plan(uuid,text,jsonb)',
    'invoice_financial_position(uuid)',
    'resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)',
    'merge_customer_records(uuid,uuid,text,uuid)',
    'move_invoice_benefits_to_customer(uuid,uuid,uuid,text)',
    'invoice_transferable_benefits(uuid)',
    'transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)',
    'invoice_benefits_holder(uuid,uuid,timestamp with time zone)',
    'invoice_credit_live_holder(uuid,uuid,timestamp with time zone)',
    'credit_lot_ancestry(uuid)',
    'invoice_benefit_moved_to_other(uuid)',
    'invoice_credit_transfer_origin(uuid)',
    'trg_credit_given_back_follows()',
    'invoice_credit_lot_ids(uuid)',
    'ensure_customer_wallet(uuid)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'trg_credit_lot_immutable()',
    'trg_credit_ledger_immutable()',
    'customer_credit_statement(uuid,date,date)',
    'invoice_refund_options_before_sessions(uuid)',
    'apply_reopened_invoice_vouchers()',
    'delete_customer(uuid,text,text)',
    'allocate_invoice_wallet_credit(uuid,numeric,text,text)',
    'trg_legacy_refund_guard()',
    'trg_lock_on_settle()',
    'validate_invoice_business_metadata()',
    'track_invoice_business_date_version()',
    'trg_create_therapy_on_paid()',
    'trg_fulfil_from_warehouse()',
    'trg_issue_sold_vouchers_on_paid()',
    'writeoff_released_credit_on_close(uuid,text,text)',
    'release_credit_package_paid_credit(uuid)',
    'credit_package_released_paid_credit(uuid)',
    'capture_invoice_benefit_values(uuid)',
    'credit_lot_chain(uuid)',
    'credit_lot_current(uuid)',
    'trim_released_paid_credit(uuid,text,boolean)',
    'reclaim_released_credit_of_removed_lines(uuid,jsonb,text)',
    'repair_credit_package_progress_lots()',
    'credit_package_money_toward_line(uuid)',
    'credit_line_paid_entitlement(uuid)',
    'credit_lot_source_group(uuid)',
    'customer_credit_balances(uuid)',
    'invoice_commission_benefit_source(uuid)',
    'update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)',
    'reverse_credit_lot(uuid,text,text,text)'];
  c_relied_md5 constant text[] := array[
    '804ecd829cfecf713783a09a05d93c7e',
    'de52d9dbaef8ab15163bef35cb9d733d',
    '0ff61e4ead121c198ea7f90a7fc78274',
    'af99337094edb6d73b9cc0ae00fbf138',
    '04d647e13e9424a9375942e5812e91a2',
    'e019e28ad79539d771376c9b38d7e27e',
    '36eaa7224e514d3e7e42e3eeb51acfb5',
    '12206ed066495024421b3b44a6a9d8e2',
    'e09ebf9c0841ef5463f96b26f4933541',
    'd35d7c8ae7187985ea64f8a5c38a7d79',
    '055a3b07b1c15ffb1ac19039fa6cb650',
    '383d618edb28c3c9a360242d038a022c',
    'ba7eccbfeff217c8b1969b0e55a010ca',
    '201f08ebf14a64cd88d411a7cfb4c9c4',
    'ba05c2b1fb4c0e14d369c01d06a635b0',
    'c01606c84ee13ddcd88c15521d6d9aed',
    '68736a39ed765ee787242bc62bbaeebb',
    '7aebd7120bc3928db46df0941cb20889',
    '55995ff6e1ffd4a1172cb930512a34b0',
    'a5692590ef3e8a7a7dd7e8ff7cfa9568',
    '52b3cae789b6b52a12bb2f798af40cbe',
    '7016bed898e1bbe9d0ac4a05037d07c2',
    '1e8beeccfbf7e432edffc1598acddb53',
    '84e2d978b74b56a9508e4f4f5b518c22',
    '50346a2e9aea50b31d4207c43b2f197c',
    '8ef18daebbbe3c12f2024290ea8416e8',
    'c705c733e213a27f0dc32d54322cc855',
    '0fc74da0dcc9b436dfd26c4582542f6c',
    '071ec0ccd5fc13107de0d11f85ba8c28',
    '1ba4a16a8208906f9e88efbc716bd1dd',
    'bd3afcc79cd2f06f983607d54fed167c',
    '6684840544d1ad8a28e2415934300054',
    '5b407735574fc3cacd8067c4dc8213f4',
    'da8aa986c92d765a8028741f33bf56b0',
    '089965ef41a18fe3c54dd622e743075a',
    '39c6478cdaec553c2ab8ceaf55058960',
    'c6e4436575e1c5ec8580d2b3d9d11d50',
    '2c1e7ac8c5c2cfea8ddc5122adfc5d92',
    '012ae4e305b9870fa5596f740c0427b9',
    '4abf4bf68e4f00658a8da66469e7059e',
    'cf0b5610b77edfea2683751d5c25ca1d',
    '284a89cfb965e8028136b5f8a4f2bf08',
    '530521c100163445e5a0b99799fbcccc',
    '6b27388462747e3c13f3da0b9ad165c0',
    'd5e061945c2921a1af86f8c99a349e98',
    '556e725784154cbffc23d3ad900f9366',
    'd48fb24e6eb9733d7f867e42fa703e7b',
    '14ded4342c3e65eb98547d224263519f',
    '823cd6a96c813b43bf2767dc1644e943',
    'ebd2a1a9f8ce7a9c1c272168b30b5ce3',
    '798c2d67d55bb1d140232ff06ffb1034',
    'da2404a1db281b46a44231bd071a069a',
    '6b902cb426210eb10ee9a15344ff100b',
    'c2287779ce0ec9c52eeec41952055f78',
    'f8d3d29fae79065a252a8c5231cc2d4b',
    '1f034561a461bdb46a1e6274e0d04606',
    '10c1a3d8e3bb003fbaf01cf879f97c5e'];
  -- Who calls the forwarder; who reads or writes a cancellation's ledger
  -- rows, the reopening queue and the amount owed back; what writes a
  -- 'reverse' ledger row and what raises a lot's balance (by name; a
  -- session's own temporary functions and the forwarder itself are not
  -- counted), as read on production at 470 (26 Oct 2026; as 470 read them).
  c_callers constant text := 'trg_credit_given_back_follows()';
  c_cancel_rows constant text := 'cancel_invoice_recorded(uuid,text,uuid), credit_lot_policy(text,text,boolean), invoice_benefit_unused_elsewhere(uuid), invoice_reopen_preview_before_sessions(uuid), reopen_invoice(uuid,text,uuid)';
  c_queue_inserts constant text := 'reopen_invoice(uuid,text,uuid)';
  c_queue_updates constant text := 'apply_reopened_invoice_benefits(), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)';
  c_owed_writers constant text := 'cancel_invoice_recorded(uuid,text,uuid), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)';
  c_reverse_writers constant text := 'apply_reopened_invoice_benefits(), correct_invoice_payment(uuid,numeric,date,uuid,text,uuid), customer_credit_statement(uuid,date,date), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), refund_special_credit(text,uuid), repair_credit_package_progress_lots(), reverse_credit_lot(uuid,text,text,text), reverse_invoice_date_recovery(uuid,uuid,text)';
  c_raisers constant text := 'apply_reopened_invoice_benefits(), correct_invoice_payment(uuid,numeric,date,uuid,text,uuid), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), refund_special_credit(text,uuid)';
  -- Who reads or writes the release record (credit released before full
  -- payment) and its write-off rows (by name), as read.
  c_release_rw constant text := 'cancelled_invoice_used_value(uuid), capture_invoice_benefit_values(uuid), credit_lot_chain(uuid), credit_lot_source_group(uuid), credit_package_money_toward_line(uuid), credit_package_released_paid_credit(uuid), customer_credit_balances(uuid), invoice_commission_benefit_source(uuid), invoice_credit_lot_ids(uuid), move_invoice_benefits_to_customer(uuid,uuid,uuid,text), reclaim_released_credit_of_removed_lines(uuid,jsonb,text), release_credit_package_paid_credit(uuid), repair_credit_package_progress_lots(), trg_create_therapy_on_paid(), trim_released_paid_credit(uuid,text,boolean), writeoff_released_credit_on_close(uuid,text,text)';
  c_release_kinds constant text := 'cancel_invoice_recorded(uuid,text,uuid), cancelled_invoice_used_value(uuid), reclaim_released_credit_of_removed_lines(uuid,jsonb,text), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), trim_released_paid_credit(uuid,text,boolean), update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean), writeoff_released_credit_on_close(uuid,text,text)';
  -- What locks a lot (by name), as read: Cancel's write-off, whose lock the
  -- forwarder reads past on a lot of the release record, an Owner's
  -- reversal and 328's repair (both told by their ledger rows' kind). A
  -- reissue copies a lot whole, its lock with it but not its ledger rows
  -- (apply_reopened_invoice_benefits, move_invoice_benefits_to_customer,
  -- merge_customer_records: pinned above), so such a copy in the release
  -- record's chain is read past too, whichever lock it copied (NOT COVERED
  -- 10).
  c_lockers constant text := 'repair_credit_package_progress_lots(), reverse_credit_lot(uuid,text,text,text), writeoff_released_credit_on_close(uuid,text,text)';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; n int; i int; v_first boolean; v_acl text; n8 int; v8 text;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_pk uuid; t_svc uuid; t_wallet uuid;
  t_case int; t_a uuid; t_inv uuid; t_s1 uuid; t_s2 uuid; t_item uuid; t_ben uuid; t_rcpt uuid; t_lot uuid; t_lot0 uuid;
  t_pay uuid; t_req uuid;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The text is the tested one.
  if md5(c_def_follows) <> c_after then
    raise exception '471: the text in this file is not the tested one'; end if;

  -- The functions relied on are as read on production (at 470, 26 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '471: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if to_regprocedure('auth.uid()') is null then raise exception '471: auth.uid() must be there'; end if;

  -- The columns read and written, with these types.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('customer_credit_lots', 'id', 'uuid'), ('customer_credit_lots', 'customer_id', 'uuid'),
                 ('customer_credit_lots', 'wallet_id', 'uuid'), ('customer_credit_lots', 'store_id', 'uuid'),
                 ('customer_credit_lots', 'category', 'text'), ('customer_credit_lots', 'status', 'text'),
                 ('customer_credit_lots', 'is_locked', 'boolean'), ('customer_credit_lots', 'original_amount', 'numeric(12,2)'),
                 ('customer_credit_lots', 'remaining_amount', 'numeric(12,2)'), ('customer_credit_lots', 'reassigned_from_lot_id', 'uuid'),
                 ('customer_credit_lots', 'source_type', 'text'), ('customer_credit_lots', 'source_record_id', 'uuid'),
                 ('customer_credit_lots', 'created_at', 'timestamp with time zone'),
                 ('customer_credit_ledger', 'id', 'uuid'), ('customer_credit_ledger', 'lot_id', 'uuid'),
                 ('customer_credit_ledger', 'wallet_id', 'uuid'), ('customer_credit_ledger', 'customer_id', 'uuid'),
                 ('customer_credit_ledger', 'category', 'text'), ('customer_credit_ledger', 'store_id', 'uuid'),
                 ('customer_credit_ledger', 'entry_type', 'text'), ('customer_credit_ledger', 'source_type', 'text'),
                 ('customer_credit_ledger', 'source_record_id', 'uuid'), ('customer_credit_ledger', 'amount', 'numeric(12,2)'),
                 ('customer_credit_ledger', 'reason', 'text'), ('customer_credit_ledger', 'entry_seq', 'bigint'),
                 ('invoice_benefit_values', 'id', 'uuid'), ('invoice_benefit_values', 'invoice_id', 'uuid'),
                 ('invoice_benefit_values', 'lot_id', 'uuid'), ('invoice_benefit_values', 'cancelled_unused_value', 'numeric(12,2)'),
                 ('invoice_benefit_values', 'paid_value', 'numeric(12,2)'), ('invoice_benefit_values', 'granted_value', 'numeric(12,2)'),
                 ('invoice_benefit_values', 'created_at', 'timestamp with time zone'),
                 ('invoice_reopen_benefits', 'id', 'uuid'), ('invoice_reopen_benefits', 'invoice_id', 'uuid'),
                 ('invoice_reopen_benefits', 'source_ledger_id', 'uuid'), ('invoice_reopen_benefits', 'request_id', 'uuid'),
                 ('invoice_reopen_benefits', 'amount', 'numeric(12,2)'), ('invoice_reopen_benefits', 'applied_at', 'timestamp with time zone'),
                 ('invoice_reopen_benefits', 'created_by', 'uuid'), ('invoice_reopen_benefits', 'created_at', 'timestamp with time zone'),
                 ('invoices', 'id', 'uuid'), ('invoices', 'status', 'invoice_status'), ('invoices', 'invoice_no', 'text'),
                 ('invoices', 'store_id', 'uuid'), ('invoices', 'deleted_at', 'timestamp with time zone'),
                 ('invoices', 'cancel_refund_owed', 'numeric(12,2)'),
                 ('invoice_line_credit_allocations', 'lot_id', 'uuid'), ('invoice_line_credit_allocations', 'amount', 'numeric(12,2)'),
                 ('invoice_line_credit_allocations', 'reversed_amount', 'numeric(12,2)'),
                 ('special_credit_allocations', 'lot_id', 'uuid'), ('special_credit_allocations', 'amount', 'numeric(14,2)'),
                 ('special_credit_allocations', 'reversed_amount', 'numeric(14,2)'),
                 ('credit_package_progress_lots', 'lot_id', 'uuid'), ('credit_package_progress_lots', 'invoice_id', 'uuid'),
                 ('credit_package_progress_lots', 'released_amount', 'numeric(12,2)'), ('credit_package_progress_lots', 'replaces_lot_id', 'uuid')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '471: these columns are missing or not as read on 26 Oct 2026: %', v; end if;
  -- One queue row per ledger row; a lot never holds more than it was
  -- granted; lots and the ledger keep their history.
  if not exists (select 1 from pg_constraint where conrelid = 'public.invoice_reopen_benefits'::regclass and contype = 'u'
                  and pg_get_constraintdef(oid) = 'UNIQUE (source_ledger_id)')
     or not exists (select 1 from pg_constraint where conrelid = 'public.customer_credit_lots'::regclass
                     and conname = 'credit_lot_remaining_within_original' and pg_get_constraintdef(oid) = 'CHECK ((remaining_amount <= original_amount))')
     or not exists (select 1 from pg_constraint where conrelid = 'public.customer_credit_lots'::regclass and contype = 'c'
                     and pg_get_constraintdef(oid) = 'CHECK ((status = ANY (ARRAY[''active''::text, ''reversed''::text])))')
     or not exists (select 1 from pg_trigger where tgrelid = 'public.customer_credit_ledger'::regclass and tgname = 'credit_ledger_immutable'
                     and not tgisinternal and tgenabled = 'O')
     or not exists (select 1 from pg_trigger where tgrelid = 'public.customer_credit_lots'::regclass and tgname = 'credit_lot_immutable'
                     and not tgisinternal and tgenabled = 'O') then
    raise exception '471: the queue''s one row per ledger row, a lot''s ceiling or statuses, or the history guards are not as read on 26 Oct 2026'; end if;
  -- 462's ledger trigger, the reopening's settlement and the triggers on
  -- invoices, as they were read (the forwarder updates invoices).
  if (select pg_get_triggerdef(oid) from pg_trigger where tgrelid = 'public.customer_credit_ledger'::regclass
       and tgname = 'credit_given_back_follows') is distinct from c_ledger_trg_def
     or (select pg_get_triggerdef(oid) from pg_trigger where tgrelid = 'public.invoices'::regclass
          and tgname = 'invoice_reopen_benefits_settled') is distinct from c_settle_trg_def then
    raise exception '471: 462''s trigger credit_given_back_follows or the reopening''s settlement trigger is not as made; 471 goes in after 462, 463 and 470'; end if;
  select md5(string_agg(pg_get_triggerdef(oid), E'\n' order by tgname)), count(*) into v, n
    from pg_trigger where tgrelid = 'public.invoices'::regclass and not tgisinternal;
  if v is distinct from c_inv_trg_md5 or n <> c_inv_trg_n then
    raise exception '471: the triggers on invoices are not as read on 26 Oct 2026 (% triggers, md5 %); check what an update of an invoice''s amount owed back runs, then re-test', n, v; end if;

  -- No other function takes the name (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'credit_given_back_follows'
     and p.oid::regprocedure::text <> c_sig;
  if v is not null then raise exception '471: another function takes the name of the one this changes: %', v; end if;

  -- Who calls the forwarder; who reads or writes a cancellation's rows, the
  -- queue and the amount owed back; what gives credit back on a lot: as read
  -- (a new way would need the same care).
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'credit_given_back_follows\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  if v is distinct from c_callers then
    raise exception '471: the functions that call credit_given_back_follows are not as read on 26 Oct 2026 (%)', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ '''invoice_cancel_benefit''' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  if v is distinct from c_cancel_rows then
    raise exception '471: what reads or writes a cancellation''s ledger rows is not as read on 26 Oct 2026 (%)', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'insert\s+into\s+public\.invoice_reopen_benefits' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'update\s+public\.invoice_reopen_benefits' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  if v is distinct from c_queue_inserts or d is distinct from c_queue_updates then
    raise exception '471: what writes the reopening''s queue is not as read on 26 Oct 2026 (% / %)', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'cancel_refund_owed\s*=' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  if v is distinct from c_owed_writers then
    raise exception '471: what writes the amount owed back is not as read on 26 Oct 2026 (%)', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ '''reverse''' and ns.nspname not like 'pg\_temp\_%';
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'remaining_amount\s*=\s*(\w+\.)?remaining_amount\s*\+' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_reverse_writers or d is distinct from c_raisers then
    raise exception '471: what gives credit back on a lot is not as read on 26 Oct 2026 (% / %); check that 462''s trigger forwards each and that none raises a lot of a cancelled package''s records outside it, then re-test', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'credit_package_progress_lots' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ '_released_credit' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  if v is distinct from c_release_rw or d is distinct from c_release_kinds then
    raise exception '471: what reads or writes the release record of credit released before full payment, or its write-off rows, is not as read on 26 Oct 2026 (% / %)', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'is_locked\s*=\s*true' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  if v is distinct from c_lockers then
    raise exception '471: what locks a credit lot is not as read on 26 Oct 2026 (%); check whether the forwarder may read past that lock, then re-test', v; end if;

  -- The function: its BEFORE (470's AFTER: replaced) or its AFTER (left alone).
  d := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  if md5(d) = c_after then
    raise notice '471: public.% is already this version; left alone', c_sig;
    v_first := false;
  elsif md5(d) = c_before then
    v_first := true;
  else
    raise exception '471: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig, md5(d);
  end if;

  -- ── On the first run: nothing is refused for the data (471 reads no state
  -- that needs a decision before it can go in), but what needs the Owner's
  -- decision is named (the header's read-only query, 4, 6, 8 and 9): credit
  -- spendable today on the lot the records of a cancelled, refunded or
  -- waiting invoice name (also a lot of its credit released before full
  -- payment that a Cancel's write-off closed, a refund opened again and a
  -- benefit row names, or that is behind the lot a benefit row names: a
  -- reissue copied it, lock and all). 471 does not change it; the next
  -- refund or correction of a sale paid from that lot holds it back with the
  -- new credit (on a lot an Owner reversed it does not: 9, NOT COVERED 10).
  if v_first then
    -- The query's 4 and 8: a lot holding credit that the forwarder reads,
    -- the one a benefit row names or one behind it of the release record's
    -- chain (the query's wo), who holds it and who holds the benefits.
    with wo as (
      select pl.invoice_id, w.lot_id
        from public.credit_package_progress_lots pl
        cross join lateral unnest(public.credit_lot_chain(pl.lot_id)) w(lot_id)
        join public.customer_credit_lots c on c.id = w.lot_id
       where c.is_locked
         and not exists (select 1 from public.customer_credit_ledger e
                          where e.customer_id = c.customer_id and e.lot_id = c.id
                            and e.source_type in ('reversal', 'credit_lot_provenance_repair'))),
    -- (the holder is worked out in the select list, so only for the lots
    -- found; the lots behind are read only for invoices with such a lot)
    x as (
      select b.invoice_id, l.customer_id as on_lot,
             coalesce(public.invoice_credit_live_holder(b.invoice_id, l.customer_id,
               case when public.invoice_benefit_moved_to_other(b.id) then 'infinity'::timestamptz else l.created_at end),
               l.customer_id) as holder,
             exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = l.id) as closed
        from public.invoice_benefit_values b
        join public.customer_credit_lots l on l.id = b.lot_id
       where l.remaining_amount > 0 and l.status = 'active'
         and (not l.is_locked or exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = l.id))
      union all
      select b.invoice_id, p.customer_id,
             coalesce(public.invoice_credit_live_holder(b.invoice_id, l.customer_id,
               case when public.invoice_benefit_moved_to_other(b.id) then 'infinity'::timestamptz else l.created_at end),
               l.customer_id),
             true
        from (select distinct invoice_id from wo) wi
        join public.invoice_benefit_values b on b.invoice_id = wi.invoice_id
        join public.customer_credit_lots l on l.id = b.lot_id
        join public.customer_credit_lots p on p.id = any (public.credit_lot_ancestry(l.id)) and p.id <> l.id
       where p.remaining_amount > 0 and p.status = 'active'
         and exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = p.id)
         and l.status = 'active'
         and (not l.is_locked or exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = l.id)))
    select count(distinct x.invoice_id) filter (where x.on_lot = x.holder
                                                  and (iv.status in ('cancelled', 'refunded')
                                                       or exists (select 1 from public.invoice_reopen_benefits w where w.invoice_id = iv.id and w.applied_at is null))),
           string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no)
             filter (where x.on_lot = x.holder
                       and (iv.status in ('cancelled', 'refunded')
                            or exists (select 1 from public.invoice_reopen_benefits w where w.invoice_id = iv.id and w.applied_at is null))),
           count(distinct x.invoice_id) filter (where x.on_lot <> x.holder and x.closed),
           string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) filter (where x.on_lot <> x.holder and x.closed)
      into n, v, n8, v8
      from x join public.invoices iv on iv.id = x.invoice_id and iv.deleted_at is null;
    if n > 0 then
      raise notice '471: % invoice(s) cancelled, refunded or waiting for a reopening''s payment hold credit spendable on a lot their records name, or behind it (%): for the Owner (a data fix, or left as it is); not changed by 471', n, v;
    end if;
    -- (B) paid in part: credit spendable on a lot of a cancelled or refunded
    -- invoice's credit released before full payment (the query's 6).
    select count(distinct pl.invoice_id), string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into n, v
      from public.credit_package_progress_lots pl
      join public.invoices iv on iv.id = pl.invoice_id and iv.deleted_at is null and iv.status in ('cancelled', 'refunded')
      cross join lateral unnest(public.credit_lot_chain(pl.lot_id)) x(lot_id)
      join public.customer_credit_lots l on l.id = x.lot_id
     where pl.released_amount > 0 and l.remaining_amount > 0 and l.status = 'active'
       and not exists (select 1 from public.invoice_benefit_values b where b.lot_id = any (public.credit_lot_chain(pl.lot_id)));
    if n > 0 then
      raise notice '471: % invoice(s) cancelled or refunded and paid in part hold credit spendable on a lot of their credit released before full payment (%): for the Owner (a data fix, or left as it is); not changed by 471', n, v;
    end if;
    -- Paid in part, cancelled, reopened and paid in full since: credit
    -- spendable on the released lot the Cancel closed that a benefit row
    -- names (or a copy of it, or one behind it), held by someone other than
    -- whoever holds the benefits (the query's 8; read above).
    if n8 > 0 then
      raise notice '471: % invoice(s) paid in part, cancelled, reopened and paid in full hold credit spendable on the released lot the Cancel closed (or a copy of it, or behind it), by someone other than whoever holds their benefits (%): for the Owner (a data fix, or left as it is); not changed by 471', n8, v8;
    end if;
    -- A lot an Owner reversed or 328's repair replaced, holding credit given
    -- back on it since, of a cancelled, refunded or waiting invoice (the
    -- query's 9): the forwarder passes it over (NOT COVERED 10).
    select count(distinct b.invoice_id), string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into n, v
      from public.invoice_benefit_values b
      join public.invoices iv on iv.id = b.invoice_id and iv.deleted_at is null
      join public.customer_credit_lots p on b.lot_id is not null and p.id = any (public.credit_lot_ancestry(b.lot_id))
     where p.is_locked and p.status = 'active' and p.remaining_amount > 0
       and exists (select 1 from public.customer_credit_ledger e
                    where e.customer_id = p.customer_id and e.lot_id = p.id
                      and e.source_type in ('reversal', 'credit_lot_provenance_repair'))
       and (iv.status in ('cancelled', 'refunded')
            or exists (select 1 from public.invoice_reopen_benefits w where w.invoice_id = iv.id and w.applied_at is null));
    if n > 0 then
      raise notice '471: % invoice(s) cancelled, refunded or waiting for a reopening''s payment hold credit spendable on a lot an Owner reversed or 328''s repair replaced, given back on it since (%): for the Owner (a data fix, or left as it is); 471 passes such a lot over (NOT COVERED 10)', n, v;
    end if;
  end if;

  -- Who may call it, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig))
     is distinct from (select array_agg(x::text order by x::text) from unnest(c_acl::aclitem[]) x) then
    raise exception '471: who may call public.% is not as read on 26 Oct 2026 (%)', c_sig,
      (select proacl::text from pg_proc where oid = to_regprocedure('public.' || c_sig)); end if;
  v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig));

  -- ── Change ──────────────────────────────────────────────────────────────
  if v_first then
    execute c_def_follows;
  end if;

  -- ── Afterwards: installed exactly as tested, grants as before ───────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_after then
    raise exception '471: public.% is not at its AFTER md5 (%)', c_sig, md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))); end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig)) is distinct from v_acl then
    raise exception '471: the grants of public.% changed', c_sig; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("471 check", @example.invalid, fictional ACMA
  -- phones no customer uses); it ends by raising P0471, which undoes all it
  -- wrote. 462's trigger runs at commit; here at each step's end (SET
  -- CONSTRAINTS ... IMMEDIATE), as a commit would.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from generate_series(800, 899) g, lateral (select '+61491570' || g::text as p) x
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p desc limit 8);
    if coalesce(cardinality(t_phones), 0) < 8 then raise exception '471: the self-test found no eight unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '471-check-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '471 check', '471-check-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('471 check ' || t_sfx, '471-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('471 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy, grants_reward)
    values ('471 check ' || t_sfx, 100, 100, false, true, true, false) returning id into t_pk;
    insert into public.credit_package_stores (package_id, store_id) values (t_pk, t_store);
    insert into public.therapy_services (service_code, name, standard_price, duration_minutes, is_active)
    values ('471-' || t_sfx, '471 check ' || t_sfx, 20, 30, true) returning id into t_svc;
    insert into public.therapy_service_stores (service_id, store_id, is_available) values (t_svc, t_store, true);
    select pm.id into t_wallet from public.payment_methods pm
     where pm.name = 'Wallet — Credit Package Paid' and pm.is_wallet_credit and pm.deleted_at is null;
    if t_wallet is null then raise exception '471: the wallet method "Wallet — Credit Package Paid" (443) is not there'; end if;

    for t_case in 1 .. 8 loop
      -- The common part: the package sold to A (no Move, no change, no
      -- merge: its own lot), two S$20 sessions paid from it (one in (b), (g)
      -- and (h); in (g) and (h) S$40 of it paid, so S$40 of its credit
      -- released).
      insert into public.customers (full_name, phone) values ('471 Check Buyer ' || t_case || ' ' || t_sfx, t_phones[t_case]) returning id into t_a;
      t_inv := public.create_invoice(t_store, t_a, null::uuid,
        jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
      perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
        'amount', case when t_case in (7, 8) then 40 else 100 end)), gen_random_uuid());
      select b.id, b.lot_id into t_ben, t_lot0 from public.invoice_benefit_values b where b.invoice_id = t_inv;
      if t_case in (7, 8) then
        select pl.lot_id into t_lot0 from public.credit_package_progress_lots pl where pl.invoice_id = t_inv;
        if t_ben is not null or t_lot0 is null or (select remaining_amount from public.customer_credit_lots where id = t_lot0) <> 40 then
          raise exception '471: (%) paying S$40 of the package did not release S$40 of its credit', case t_case when 7 then 'g' else 'h' end; end if;
      end if;
      select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv;
      select p.id into t_rcpt from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1;
      t_s1 := public.create_invoice(t_store, t_a, null::uuid,
        jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
      perform public.record_invoice_payment(t_s1, jsonb_build_array(jsonb_build_object('payment_method_id', t_wallet, 'amount', 20)), gen_random_uuid());
      if t_case not in (2, 7, 8) then
        t_s2 := public.create_invoice(t_store, t_a, null::uuid,
          jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 1)),
          0::numeric, null::text, null::uuid, '[]'::jsonb);
        perform public.record_invoice_payment(t_s2, jsonb_build_array(jsonb_build_object('payment_method_id', t_wallet, 'amount', 20)), gen_random_uuid());
      else
        t_s2 := t_s1;
      end if;
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      if t_case in (1, 3, 4, 6, 7, 8) then
        perform public.cancel_invoice_recorded(t_inv, '471 check', gen_random_uuid());
      end if;
      if t_case in (1, 6) then
        -- A stand-in for the guided Cancel that kept S$40 for the two
        -- sessions and recorded S$60 paid back (by line, as on a package).
        update public.invoices set cancel_refund_owed = 60 where id = t_inv;
      end if;
      if t_case in (1, 3, 6) then
        perform public.refund_invoice_recorded(t_inv,
          jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 60,
            'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_ben, 'amount', 60)))),
          jsonb_build_array(jsonb_build_object('payment_id', t_rcpt, 'amount', 60)), '[]'::jsonb, '471 check', gen_random_uuid());
      end if;
      if t_case = 2 then
        -- (b) refunded by line in full with an Owner's override (what was
        -- spent paid back too): refunded.
        perform public.refund_invoice_recorded(t_inv,
          jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 100,
            'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_ben, 'amount', 80)),
            'override', jsonb_build_object('code', 'larger_refund', 'reason', '471 check', 'amount', 100))),
          jsonb_build_array(jsonb_build_object('payment_id', t_rcpt, 'amount', 100)), '[]'::jsonb, '471 check', gen_random_uuid());
        if (select status::text from public.invoices where id = t_inv) <> 'refunded' then
          raise exception '471: (b) the refund in full with an override did not leave the package refunded'; end if;
      end if;
      if t_case = 3 then
        -- (c) reopened: it waits for S$60.
        t_req := gen_random_uuid();
        perform public.reopen_invoice(t_inv, '471 check', t_req);
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
      end if;
      if t_case = 8 then
        -- (h) reopened and paid in full (a benefit row now names the
        -- released lot the Cancel's write-off closed: 'reversed', locked),
        -- then cancelled again.
        perform public.reopen_invoice(t_inv, '471 check', gen_random_uuid());
        perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
          'amount', (public.invoice_financial_position(t_inv)->>'outstanding')::numeric)), gen_random_uuid());
        perform public.cancel_invoice_recorded(t_inv, '471 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        select b.id into t_ben from public.invoice_benefit_values b where b.invoice_id = t_inv and b.lot_id = t_lot0;
        if t_ben is null or (select status::text from public.invoices where id = t_inv) <> 'cancelled'
           or not (select is_locked from public.customer_credit_lots where id = t_lot0) then
          raise exception '471: (h) reopened, paid in full and cancelled again, no benefit row names the closed released lot'; end if;
      end if;
      -- The second session (in (b) the only one) given back: cancelled and
      -- refunded, or (f) its wallet payment corrected to S$5 less.
      if t_case = 6 then
        select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_s2 and p.entry_kind = 'receipt' order by p.created_at limit 1;
        perform public.correct_invoice_payment(t_pay, 15, public.sg_today() - 1, t_wallet, '471 check', gen_random_uuid());
      else
        perform public.cancel_invoice_recorded(t_s2, '471 check', gen_random_uuid());
        perform public.refund_invoice_recorded(t_s2, jsonb_build_array(jsonb_build_object('amount', 20)),
          jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_s2 and p.entry_kind = 'receipt'
                                                               order by p.created_at limit 1), 'amount', 20)), '[]'::jsonb, '471 check', gen_random_uuid());
      end if;
      if t_case <> 6 and (select remaining_amount from public.customer_credit_lots where id = t_lot0)
                         <> (case t_case when 5 then 80 else 20 end) then
        raise exception '471: (%) the session''s refund did not go back where it was paid from before the commit point', t_case; end if;
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      if t_case = 7 then
        -- (g) paid in part: held back as Cancel's write-off on the released
        -- lot (closed again, no lot made), the release record at S$0, A
        -- holds nothing, nothing reads as used; the S$40 then recorded as
        -- paid back ("Record refund paid"): net S$0.
        if (select remaining_amount from public.customer_credit_lots where id = t_lot0) <> 0
           or (select status from public.customer_credit_lots where id = t_lot0) <> 'reversed'
           or not (select is_locked from public.customer_credit_lots where id = t_lot0)
           or (select released_amount from public.credit_package_progress_lots where lot_id = t_lot0) <> 0
           or (select count(*) from public.customer_credit_lots where customer_id = t_a) <> 1
           or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> 0
           or (select count(*) from public.customer_credit_ledger e where e.lot_id = t_lot0 and e.entry_type = 'adjust_decrease'
                and e.source_type = 'invoice_cancel_released_credit' and e.source_record_id = t_inv and e.amount = 20
                and e.reason = 'Held back by the invoice''s cancellation: credit released before it was paid in full') <> 1
           or cardinality(public.cancelled_invoice_used_value(t_inv)) <> 0 then
          raise exception '471: (g) the credit given back on the released lot was not held back as Cancel''s write-off (A %, released %)',
            (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a),
            (select released_amount from public.credit_package_progress_lots where lot_id = t_lot0); end if;
        perform public.refund_invoice_recorded(t_inv, jsonb_build_array(jsonb_build_object('amount', 40)),
          jsonb_build_array(jsonb_build_object('payment_id', t_rcpt, 'amount', 40)), '[]'::jsonb, '471 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if public.invoice_net_received(t_inv) <> 0 then
          raise exception '471: (g) the S$40 held was not recorded as paid back (net %)', public.invoice_net_received(t_inv); end if;
        continue;
      end if;
      if t_case = 8 then
        -- (h) held back where it is, on the released lot the benefit row
        -- names (the lock is the first Cancel's write-off's): A holds
        -- nothing, one held-back row of S$20, the row holds it back, no lot
        -- made.
        if (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> 0
           or (select remaining_amount from public.customer_credit_lots where id = t_lot0) <> 0
           or (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben) <> 20
           or (select lot_id from public.invoice_benefit_values where id = t_ben) <> t_lot0
           or (select count(*) from public.customer_credit_ledger e where e.lot_id = t_lot0 and e.entry_type = 'adjust_decrease'
                and e.source_type = 'invoice_cancel_benefit' and e.source_record_id = t_inv and e.amount = 20
                and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now') <> 1
           or exists (select 1 from public.customer_credit_ledger e where e.source_record_id = t_inv
                       and e.source_type in ('credit_given_back_reassignment_in', 'credit_given_back_reassignment_out')) then
          raise exception '471: (h) the credit given back on the closed released lot was not held back where it is (A %, held back %)',
            (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a),
            (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben); end if;
        continue;
      end if;
      select lot_id into t_lot from public.invoice_benefit_values where id = t_ben;
      if t_lot is distinct from t_lot0
         or exists (select 1 from public.customer_credit_ledger e where e.source_record_id = t_inv
                     and e.source_type in ('credit_given_back_reassignment_in', 'credit_given_back_reassignment_out')) then
        raise exception '471: (%) a lot was reissued where none should be', t_case; end if;
      if t_case = 5 then
        -- (e) a paid package (a control): the S$20 is A's to spend, nothing
        -- held back.
        if (select remaining_amount from public.customer_credit_lots where id = t_lot) <> 80
           or (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben) <> 0
           or exists (select 1 from public.customer_credit_ledger e where e.lot_id = t_lot and e.source_type = 'invoice_cancel_benefit') then
          raise exception '471: (e) credit given back while the package is paid was held back'; end if;
        continue;
      end if;
      -- Held back where it is: A holds nothing, the row holds it back, one
      -- held row on the package's own lot.
      if (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> 0
         or (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben)
            <> (case t_case when 4 then 80 when 6 then 5 else 20 end)
         or (select count(*) from public.customer_credit_ledger e where e.lot_id = t_lot and e.entry_type = 'adjust_decrease'
              and e.source_type = 'invoice_cancel_benefit' and e.source_record_id = t_inv
              and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now'
              and e.amount = case t_case when 6 then 5 else 20 end) <> 1 then
        raise exception '471: (%) the credit given back was not held back where it is (A %, held back %)', t_case,
          (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a),
          (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben); end if;
      if t_case in (1, 6) then
        -- (a), (f) owed back: S$20 (S$5), what a refund by line pays back for
        -- it; refunded by line: nothing more held or owed, net S$40 (S$45)
        -- kept for what was used.
        if (select cancel_refund_owed from public.invoices where id = t_inv) <> (case t_case when 6 then 5 else 20 end)
           or (public.invoice_financial_position(t_inv)->>'refund_due')::numeric <> (case t_case when 6 then 5 else 20 end) then
          raise exception '471: (%) the amount owed back is % (due %)', t_case, (select cancel_refund_owed from public.invoices where id = t_inv),
            public.invoice_financial_position(t_inv)->>'refund_due'; end if;
        perform public.refund_invoice_recorded(t_inv,
          jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', case t_case when 6 then 5 else 20 end,
            'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_ben, 'amount', case t_case when 6 then 5 else 20 end)))),
          jsonb_build_array(jsonb_build_object('payment_id', t_rcpt, 'amount', case t_case when 6 then 5 else 20 end)), '[]'::jsonb, '471 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if public.invoice_net_received(t_inv) <> (case t_case when 6 then 35 else 20 end)
           or (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben) <> 0
           or (select cancel_refund_owed from public.invoices where id = t_inv) <> 0
           or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> 0 then
          raise exception '471: (%) the refund by line did not pay the held-back credit back (net %)', t_case, public.invoice_net_received(t_inv); end if;
      elsif t_case = 2 then
        -- (b) refunded in full: held back, owed to nobody (470's NOT COVERED
        -- 2, accepted 26 Oct 2026), net S$0.
        if public.invoice_net_received(t_inv) <> 0 or (select status::text from public.invoices where id = t_inv) <> 'refunded' then
          raise exception '471: (b) the refunded package changed (net %)', public.invoice_net_received(t_inv); end if;
      elsif t_case = 3 then
        -- (c) while the reopening waits: queued for its payment (its request);
        -- paid: A S$80, nothing waiting, nothing held back.
        if (select count(*) from public.invoice_reopen_benefits q join public.customer_credit_ledger e on e.id = q.source_ledger_id
             where q.invoice_id = t_inv and q.applied_at is null and e.lot_id = t_lot and q.request_id = t_req
               and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now' and q.amount = 20) <> 1 then
          raise exception '471: (c) the held-back credit is not queued for the reopening''s payment'; end if;
        perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
          'amount', (public.invoice_financial_position(t_inv)->>'outstanding')::numeric)), gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> 80
           or exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = t_inv and q.applied_at is null)
           or (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben) <> 0
           or public.invoice_net_received(t_inv) <> 100 then
          raise exception '471: (c) the reopening''s payment did not give the S$80 back to A'; end if;
      elsif t_case = 4 then
        -- (d) cancelled, the second session refunded, reopened (paid at
        -- once): A S$80, nothing held back or waiting, nothing asked, due S$80.
        perform public.reopen_invoice(t_inv, '471 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> 80
           or exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = t_inv and q.applied_at is null)
           or (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben) <> 0
           or (public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->>'refund_due')::numeric <> 80 then
          raise exception '471: (d) the reopening did not give A the S$80'; end if;
      end if;
    end loop;
    raise exception using errcode = 'P0471', message = '471: self-test done, undone';
  exception when sqlstate 'P0471' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
