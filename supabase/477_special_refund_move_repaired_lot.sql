-- 477_special_refund_move_repaired_lot.sql
--
-- CREDIT GIVEN BACK ON A CLOSED, LOCKED OR REPAIRED LOT FOLLOWS THE SAME
-- RULES AS ANY OTHER: A SPECIAL DOCUMENT'S REFUND OPENS THE LOT IT GIVES
-- BACK ON, AN OWNER MAY MOVE CREDIT A REFUND PUT BACK ON A LOT AN OWNER HAD
-- REVERSED OR CANCEL'S WRITE-OFF HAD LOCKED, AND CREDIT GIVEN BACK ON A LOT
-- 328's REPAIR REPLACED GOES TO THE LOT THE RECORDS NAME (472's NOT COVERED
-- 2, 4 and 1, and this file's first build's NOT COVERED 1; the Owner, 27
-- Oct 2026: all three ticked, and answer D; 28 Oct 2026: copies too)
--
-- (The number 477 is this file's name, its errors' prefix, its self-test's
-- error code P0477 and its suite's; if it changes at commit, change it in
-- these places alone: the file name, the "477:" messages, P0477, the suite,
-- and the "-- 477 (the Owner" lines the suites find its functions by.)
--
-- WHO FOUND IT
--
--   472's builders (its NOT COVERED 1, 2 and 4, its suite's KNOWN K1, K2 and
--   K4: R328..., PTsx, PTsxs, PTsxp, MVX, 26 Oct 2026), put to the Owner with
--   472 to 474's questions; this file's first build (its NOT COVERED 1: MVW,
--   the Move of a lot only Cancel's write-off locked, still refused) and the
--   review of 475 to 478 (27 Oct 2026), put to the Owner with 476 to 478's
--   questions. Reproduced for this file on copies of production at 475 with
--   476 applied (e948504d, then cc718597, 1390 functions, 27 and 28 Oct 2026) with
--   those cases and their siblings (this file's suite, section R): made-up
--   records, the app's own calls (the invoice form and the Pay dialog,
--   Record Payment, Cancel, Reopen, the Finance panel's refund by line,
--   "Record refund paid" and Correct payment, an Owner's Move, the invoice
--   form's customer change with 'transfer' or 'keep', the guided Cancel),
--   an Owner's reversal as a direct call (reverse_credit_lot: no page calls
--   it), a special document's wallet payment as a stand-in for
--   pay_special_with_credit (no page calls it) and its refund the real
--   refund_special_credit, 328's repair of a lot as a stand-in with its own
--   statements (472's: 327's lots, which the real repair reads, can no
--   longer be made), each followed by what its commit does; all 76 of the
--   suite's cases (66 before answer D, 10 for it) were also run one app call
--   per real transaction on such copies (real commits, so 462's deferred
--   trigger at each COMMIT), with and without this file: the same outcomes
--   as the suite's, both ways (without it, every fixed case ends otherwise
--   and every control as expected). Building 477 found (on the same kind of
--   copies, the same way) that credit given back on a lot 328's repair
--   replaced before the package is settled is not reached by Cancel's
--   write-off nor named at the settlement either (R328u..., below). The
--   review of 475 to 478 (27 Oct 2026) found, on copies with a real commit
--   after each step, that credit given back before settlement on the lot of
--   credit released before full payment stayed with the buyer after a
--   'transfer' change (4, below); TQx1, TQx1p, TQx2, TQx1k, TQx1cc and TQx1F
--   were run that way with this file's fix too, ending as the suite's cases
--   do.
--
-- WHAT WAS WRONG
--
--   (1) A special document's wallet refund (refund_special_credit) put the
--   credit back on its lot without opening it. Where an Owner had reversed
--   that lot ('reversed', locked), the credit stayed on a closed lot. On
--   copies, a S$100 package sold to A and paid, a S$20 special document and
--   a S$20 session paid from it, the S$60 left reversed by an Owner:
--   * cancelled, the document refunded: A holds S$20 of a cancelled package
--     on the closed lot (PTsx; a rental, PTsxr; a rental's late fee, PTsxl);
--     no one can spend it (PTsxs), though a refund by line can pay it back
--     (PTsxb: net S$80);
--   * paid, the document refunded: A holds S$20 that A cannot spend
--     ("Only 0 of the requested 20.00 could be funded": PTsxp; reopened and
--     paid first, PTsxo), nor an Owner move it (MVXd);
--   * cancelled, a 'transfer' change to B, reopened and paid, the document
--     refunded: the S$20 stays A's on the closed lot, though B holds the
--     benefits (PTsxh; cancelled again, PTsxhc).
--   (2) An Owner's Move (transfer_invoice_unused_benefit, the Finance
--   panel's Move) refused any lot that is locked: "This credit lot is locked
--   or reversed". A refund or a correction of a sale paid from a lot an
--   Owner reversed opens it again ('active') and leaves the lock, so credit
--   it puts back could not be moved: paid, two sessions, the S$60 left
--   reversed, S1 refunded: the Move of A's S$20 to F refused (MVX); the same
--   after a reopening's payment (MVXr, MVXc), on B's copy of A's lot that
--   the reopening's payment made after a 'transfer' change (MVXh: a reissue
--   copies the lock), with the lot reversed twice (MVXrr), and on a lot a
--   Cancel's write-off had closed and an Owner reversed after a refund
--   opened it (MVS2: S$5).
--   (3) 328's repair reversed what a lot of 327's source held ('reversed',
--   locked, its 'credit_lot_provenance_repair' row) and granted it again as
--   a lot that carries its package, which the release record names in its
--   place (credit_package_progress_lots.replaces_lot_id, not the lot's
--   reassigned_from_lot_id). Credit given back on the old lot (a stand-in
--   that keeps the package's source, so a sale can be paid from it: S$40
--   paid of S$100, S1 S$20 paid from the released lot, the repair) was not
--   followed to the lot the records name:
--   * settled, cancelled, S1 refunded: A holds S$20 of a cancelled package
--     and spends it (R328, R328s); refunded by line, A keeps S$20 (R328b:
--     net S$20); after a guided Cancel (S$0 owed back) the refund by line
--     finds nothing to pay back and A keeps S$20 (R328g, R328gb);
--   * settled and paid: Cancel leaves S$20 (R328p; after a 'keep' change
--     R328k; Correct payment instead of the refund R328f; two S$5 sessions
--     refunded, S$10, R3282; cancelled, S1 refunded, reopened and paid,
--     R328r; S1 refunded while a reopening waits, then paid, R328wp, and
--     while it waits A can spend it, R328w; after the guided Refund in full,
--     R328x); changed to B while cancelled, reopened and paid: A S$20, B
--     S$80, Cancel leaves A's S$20 (R328cc);
--   * not settled (paid in part), S1 refunded: Cancel's write-off reads only
--     the lot the release record reaches now (credit_lot_current), so a
--     Cancel leaves S$20 (R328u; Correct payment R328uf; two refunds S$10
--     R328u2; after a Cancel and a reopening, R328ur), and the settlement
--     names only that lot, so once paid Cancel leaves it too (R328up,
--     R328urp; after a 'keep' change, R328uk).
--   (4) (There since 471; production at 475 does the same.) Before the
--   package is settled, credit given back while the invoice was open on the
--   lot its release record reaches now stayed with that lot's customer, also
--   where that customer no longer held the invoice's benefits: two S$100
--   packages on one invoice, S$100 paid (the first released in full, the
--   second nothing), five S$20 sessions paid from it, a 'transfer' change to
--   B (the lot held nothing, so the change reissued nothing and nothing
--   blocked it: "Fully spent"; 476's row is for credit still to be released,
--   and the first line had none), S1 refunded: A S$20, B S$0 though the
--   invoice and its benefits were B's (TQx1); then paid in full: A S$20, B
--   S$100, 462's invariant reading S$20 held by A, not by the benefits'
--   holder B (TQx1p). A package paid in full with the same spending, the
--   same change and the same refund gives the S$20 to B (TQx1F). Only a lot
--   328's repair replaced was followed forward there.
--   (5) (This file's first build's NOT COVERED 1; there since 471.) An
--   Owner's Move refused credit on a lot that only Cancel's write-off of
--   credit released before full payment had locked: S$40 paid of S$100, a
--   S$20 and a S$5 session paid from the released lot, Cancel (its write-off
--   takes the S$15 left and closes and locks the lot), Reopen, paid in full,
--   S1 refunded (S$20 back on that lot, opened, still locked): the Move of
--   A's S$20 to F refused, "This credit lot is locked or reversed" (MVW); the
--   same where all of it was spent when cancelled (the write-off locks the
--   lot though it takes nothing, and then writes no row on it: MVW0); on B's
--   copy after a 'transfer' change of the lot nothing on which was used
--   (476's TQcru, then paid: MVWt; a reissue copies the lock); after a
--   'keep' change (MVWk); with Correct payment instead of the refund
--   (MVWf); where a refund while cancelled had locked it again (the
--   forwarder's hold, 471: MVWh); and so for what follows a Move (MVWs,
--   MVWsf, MVWcc, MVWcr). A could spend that credit; only an Owner could not
--   move it, as an Owner can move any other credit of the invoice.
--   So the customer of a cancelled package held credit its net payment does
--   not buy, or credit it could not spend; credit did not follow the
--   benefits' holder; Cancel did not take back all the invoice gave; an
--   Owner could not move what a customer could spend.
--   Production, 27 Oct 2026 (read-only, as given to this builder): 2 lots
--   carry an Owner's 'reversal' row, 1 lot a 'credit_lot_provenance_repair'
--   row (holding S$0), none holding credit; 6 release records of packages
--   paid in part, none cancelled; no special document is paid with credit
--   by any page; no sale can draw on the repaired lot (327's source). So no
--   invoice on production is known to be in the states of (1) to (3); 477
--   is defensive there, as the Owner asked. (4) needs a package line
--   released in full on an invoice not settled (another credit line still
--   unpaid), its credit spent, a 'transfer' change and then a refund; (5) a
--   package paid in part that was cancelled, reopened and paid, and then a
--   refund of a sale paid from its released credit; production was not read
--   for either (the header's query, 6 to 8).
--
-- THE OWNER'S ANSWERS
--
--   22 Oct 2026: credit follows a merge and a 'transfer' customer change; a
--   Move's recipient keeps what was moved; refunds paid back count as not
--   used. 24 Oct 2026 (462, 470): a cancel or refund takes back what the
--   invoice gave from whoever holds it now; the customer holds exactly what
--   the net payment buys; nothing stranded on a lot no record names;
--   nothing paid twice; Correct payment keeps working. 26 Oct 2026 (471,
--   472): an Owner's reversal stays reversed (what it took stays taken);
--   credit a refund gives back after it follows 471's rules; the deadlock
--   trade-off (470's NOT COVERED 5) accepted for all packages; S$1 owed back
--   per S$1 held for credit released before full payment; RX0/RX1 owed to
--   nobody; credit held while a reopening waits; staff are told what the
--   payment will actually give. 27 Oct 2026, answering 472's NOT COVERED 2,
--   4 and 1, all three ticked: (a) refund_special_credit opens the lot it
--   gives credit back on, as refund_invoice_recorded and
--   correct_invoice_payment do, so the forwarder's rules apply; (b) an
--   Owner's Move of credit that a refund put back on a lot an Owner had
--   reversed is allowed, of what the lot holds now (what the reversal took
--   stays taken), every other refusal kept; (c) credit given back on a lot
--   328's repair replaced follows the same rules as any other lot (prove it
--   with a stand-in lot, as 472's R328 does). (4) applies rules already
--   decided: credit follows a 'transfer' customer change (22 Oct), and a
--   package paid in part is changed as the same package paid in full is
--   ("Same as paid-in-full", 27 Oct, 476). 27 Oct 2026, about 16:20 SGT,
--   answering this file's first build and the review of 475 to 478:
--   D. "Move Cancel-locked credit" (477's NOT COVERED 1): an Owner's Move of
--      credit on a lot locked only by Cancel's write-off of credit released
--      before full payment (MVW) is allowed, as 477 already allows for a lot
--      an Owner reversed; every other refusal stays. (A to C and E are 476's
--      and 478's, F is 479's.)
--   28 Oct 2026, about 10:15 SGT, answering this file's reading of answer D:
--   "Yes, copies too": the Move of Cancel-locked credit covers the copies of
--   such a lot that a 'transfer' change, a merge or a reopening's payment
--   made (a reissue copies the lock; MVWt: B's copy after a 'transfer'
--   change), as built: the test walks credit_lot_ancestry to the lot the
--   release record names. (The same day, for 476 and 478: 476's line
--   grouping and its 'transfer' sale record as built; the Reopen dialog's
--   note names who receives all of its credit.)
--   No other business rule is changed by guessing.
--
-- WHAT THIS DOES (three functions changed, whole texts; nothing added; no
-- table, column, trigger or grant changes)
--
--   * refund_special_credit(text,uuid) (95's): the credit goes back on its
--     lot and opens it ('active'), as the other two refunds do; the lock is
--     left, as they leave it. 462's trigger already runs the forwarder at
--     commit for its ledger row ('reverse', 'special_sale' or 'rental'), so
--     the credit is held back while the package is cancelled, refunded or
--     waiting for its reopening's payment (PTsx: A S$0, S$20 held back, the
--     refund by line pays it back), goes to whoever holds the benefits
--     (PTsxh: B S$20), or is the buyer's to spend, or an Owner's to move,
--     while paid (PTsxp, PTsxo, MVXd). On a lot a Cancel's write-off closed
--     while the package is still cancelled it is taken back as 471 does
--     (PTsp, unchanged). Everything else is as before (the ledger row, the
--     allocations, the document's credit_funded).
--   * transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid) (445's): a
--     locked lot can be moved where an Owner's reversal is on it or on a lot
--     it was reissued from (credit_lot_ancestry: a reissue copies the lock),
--     or (answer D) where a release record (credit_package_progress_lots)
--     names it or such a lot (what Cancel's write-off of credit released
--     before full payment locks, also where it took nothing and wrote no
--     row: MVW0), and 328's repair is on none of them: what the lot holds
--     now moves (the reversal's or the write-off's rows and the S$ they took
--     stay as they were); the recipient's lot is not locked. Every other
--     refusal is kept: a closed lot, 328's repair's lock (P10), a lock no
--     Owner's reversal and no release record explains (MVL, a stand-in: no
--     function makes one), and the rest of the function unchanged (a
--     cancelled or waiting invoice, credit held back, the store, the
--     recipient, nothing left to move). On copies: MVW F S$20, A S$75;
--     MVW0 F S$20, A S$60; MVWt F S$20, B S$80; MVWk F S$20, A S$75 (B
--     S$0); MVWh F S$20, A S$80; then S2 refunded, A S$80 (MVWs: the lot
--     moved from is A's); cancelled, Cancel takes it back from F and A
--     (MVWcc: S$100 held back), reopened and paid, F's again (MVWcr).
--   * credit_given_back_follows(uuid) (472's): 328's link is read as a
--     reissue's. The lot the records name is found across it (from the old
--     lot, the lot its release record names in its place), and the old lot
--     is one of the lots behind the named lot (the chain back from the named
--     lot crosses it), so what it holds is held back where the package is
--     cancelled, refunded or waiting, or goes with the named lot's credit to
--     whoever holds the benefits as one new lot that replaces the named lot
--     (462's reissue: R328 S$100 held back, paid back by line, R328b; after a
--     guided Cancel S$20 owed back, R328g; R328p A S$100 on one lot; R328cc
--     B S$100; while a reopening waits, queued for its payment, R328w). 472's
--     test that passed over a lot 328's repair replaced is gone; nothing
--     else in it changes but the path before settlement. And before the package
--     is settled (no benefit row names its lots yet; 471's release-record
--     path): credit given back while the invoice is neither cancelled nor
--     refunded on a lot 328's repair replaced, or on any other lot behind
--     the lot the release record reaches now, or on that lot where its
--     customer no longer holds the invoice's benefits by 462's rule ((4): a
--     'transfer' change made once it held nothing), goes to whoever holds
--     the lot the release record reaches now (credit_lot_current; 462's
--     invoice_credit_live_holder, else that lot's customer), as one new lot
--     that replaces that lot (or takes its place where the forwarder made it
--     and nothing touched it since, so two refunds do not lengthen the
--     chain): the lots from the old one forward are drawn
--     ('credit_given_back_reassignment_out'), the holder granted the total
--     ('credit_given_back_reassignment_in'; the new lot copies that lot's
--     source, category, restrictions, store and dates), the Audit Log row is
--     471's 'credit_given_back_followed' (released_credit, release_lot_id).
--     Cancel's write-off and the settlement then find it (R328u: A S$40,
--     Cancel takes it all; R328up: A S$100 on lots the records name; TQx1:
--     B S$20, A S$0; TQx1p: B S$120; TQx2, two sessions refunded: B S$40,
--     one lot). Where the lot's customer still holds the benefits (a 'keep'
--     change; no change) nothing is done, as before (TQx1k: A keeps the
--     S$20, A S$120 once paid). While
--     cancelled or refunded it is taken back as 471 does (R328uc,
--     unchanged). The release record's amounts are not changed (credit
--     moves between lots of the same release; nothing is released again).
--   Money afterwards (the suite, each case): nobody holds credit of a
--   cancelled or refunded package; the holder holds what the net payment
--   buys less what was used, reversed or moved to someone else (a Move's
--   recipient keeps what was moved); Cancel takes all the invoice's credit
--   back (cancel_left S$0 in every case); 462's invariants hold (473's
--   reading of what the records name: the release records' chains too).
--
-- WHY THIS WAY
--
--   (a) In refund_special_credit itself, by the same means as the other two
--   refunds (status 'active', the lock left), because then 472's forwarder
--   gives the special document's credit exactly the rules it gives a
--   session's: the closed lot holding credit, which 472 had to pass over,
--   no longer arises from a refund. The other way, the forwarder opening a
--   closed lot holding credit, would leave the refund itself writing credit
--   onto a closed lot, and a closed lot holding credit from before 477 would
--   be read as fresh credit (NOT COVERED 2).
--   (b) In the Move's own refusal, by the lot's history (the 'reversal' row
--   reverse_credit_lot writes, on the lot or a lot it was reissued from),
--   because the lock does not say who put it there; 328's repair's lock is
--   told apart by its repair row, as 471 and 472 tell it. Unlocking the lot
--   where the refund opens it would change what 471's write-off test and the
--   reopening's give-back read (both read the lock). The recipient's lot is
--   made unlocked, as a Move's lot always was (only unlocked lots could be
--   moved before 477): the lock stays on the lot moved from, with what
--   explains it.
--   (D) By the release record on the lot's history, not by a ledger row on
--   the lot: the write-off (writeoff_released_credit_on_close, which Cancel
--   and a refund that ends the invoice run) closes and locks every lot of
--   credit released before full payment that it reaches, and writes a row
--   only where it takes something, so a lot all spent when cancelled
--   carries no row of its own (MVW0). What else locks such a lot is an
--   Owner's reversal (moved already since this file's first build), 328's
--   repair (refused by its row) and the forwarder's hold of credit that
--   came back while cancelled (471: the write-off's own kind of row, on a
--   lot of the same release), and apart from reverse_credit_lot no function
--   locks a lot that is not such a lot or a reissue of one (as read: who
--   writes is_locked = true; the write-off passes over a release whose lots
--   a benefit row names, so it never reaches a Move's lot); a reissue copies
--   the lock and keeps the source, so credit_lot_ancestry reaches the lot
--   the release record names (MVWt). The release record and the
--   ancestry are what the write-off, the forwarder and 461 to 476 already
--   read. The other ways: the write-off writing a row of S$0 or a marker on
--   the lot would change writeoff_released_credit_on_close, which Cancel and
--   every refund run, and leave the lots it locked before 477 unexplained;
--   unlocking such a lot when it is opened again would change what 471's
--   and 472's readers of the lock see.
--   (c) In the forwarder, the one function 462 to 472 changed for the same
--   rule, so 328's lot gets exactly the rules of a lot behind a reissue
--   (held back, owed back, queued, reissued, the readers kept right as 470
--   to 472 keep them). By reading 328's link where the forwarder walks a
--   chain, not by changing credit_lot_ancestry (read by apply_reopened_
--   invoice_benefits, invoice_credit_transfer_origin and
--   preview_invoice_correction, which this does not decide) or the release
--   record. The path before settlement because the same rule (Cancel takes
--   back all; nothing on a lot the records do not reach) fails there in the
--   same way, and only the forwarder sees the credit come back. (4) in that
--   path by the rule a settled lot's give-back follows (462's holder),
--   because it is the same credit: the other way, the customer change
--   reissuing a release lot that holds S$0 so the record reaches the new
--   customer's lot, would change move_invoice_benefits_to_customer, which
--   every customer change runs, and leave an empty lot for each.
--
-- NOT CHANGED
--
--   * Pinned (below), unchanged: refund_invoice_recorded,
--     correct_invoice_payment, cancel_invoice_recorded, reopen_invoice (475's
--     AFTER), apply_reopened_invoice_benefits, writeoff_released_credit_on_
--     close, repair_credit_package_progress_lots, reverse_credit_lot,
--     credit_lot_chain, credit_lot_current, credit_lot_ancestry,
--     capture_invoice_benefit_values, release_credit_package_paid_credit,
--     invoice_transferable_benefits, move_invoice_benefits_to_customer,
--     issue_credit_package, sell_premium_bundle, credit_line_benefits_holder
--     (476's AFTERs), the Reopen dialog's previews (474's),
--     invoice_credit_live_holder, pay_special_with_credit, the credit
--     policy, 462's trigger and its function, the triggers on invoices. The
--     write-off is unchanged: what it takes, the rows it writes and the lock
--     it puts stay as they are (answer D reads them).
--   * Edge Functions, settings, pages: no change. Read from src: the Finance
--     panel's Move lists every benefit with credit left and nothing held
--     back (InvoiceFinancePanel.tsx), so it already offered the Move that
--     was refused (after a Cancel and a Reopen too: answer D); the
--     refusal's words are the server's. No page reverses a
--     lot, runs 328's repair, pays a special document with credit or
--     refunds one (refund_special_credit, reverse_credit_lot and
--     pay_special_with_credit are the server's alone: postgres and the
--     service role). The wording 471 put on the Finance panel ("held back
--     there while that package is cancelled or refunded, or, if it was paid
--     in full before, while its reopening waits for payment") now holds for
--     a special document's credit and a lot 328's repair replaced too.
--
-- NOT COVERED (for the Owner; the suite checks 1 to 3 as they are and
-- prints them as KNOWN; 4 to 8 are read from the code)
--
--   1. (The Owner's answer D settles what this said in the first build:
--      MVW is moved now; and on 28 Oct 2026 the Owner confirmed, as built,
--      that copies of such a lot a 'transfer' change, a merge or a
--      reopening's payment made are moved too, MVWt.) A Move of credit on a
--      lot that 328's repair locked
--      (its row on the lot or on a lot it was reissued from), or that is
--      locked with no Owner's reversal and no release record to explain it,
--      is still refused, "This credit lot is locked or reversed". No app
--      call is known to reach either: credit given back on a lot 328's
--      repair replaced now follows to the lot the records name ((c)), and,
--      read from the code, nothing locks a lot but the write-off, an Owner's
--      reversal, 328's repair and the forwarder's hold (a reissue copies a
--      lock); so the suite checks them with stand-ins (P10: a repair row on
--      the lot's history; MVL: a lock and no row). A lot both locked by the
--      write-off and reversed by an Owner reads as either (MVS2: moved, F
--      S$5). The header's query lists such locked lots holding credit (9);
--      the Owner may want them looked at one by one.
--   2. Credit a special document's refund put on a closed lot before 477
--      stays there: no one can spend it (a refund by line can still pay it
--      back, as before), until a refund or correction of a sale or special
--      document paid from that lot opens it, when it is read with the new
--      credit (MPTs2: S$30 held back). Production has no lot an Owner
--      reversed holding credit (27 Oct 2026); the header's query lists any
--      (4).
--   3. Credit given back on a lot 328's repair replaced before 477 stays
--      there until the next refund or correction of a sale paid from that
--      lot or from a lot that replaced it, which takes it along (MR328p: A
--      S$100 on the named lot, Cancel takes it all). Production's one such
--      lot holds S$0; the header's query lists any (5). Before the
--      settlement the same for (4): credit given back before 477 on the lot
--      its release record reaches now, kept by a customer who no longer
--      holds the benefits, stays there until the next refund or correction
--      of a sale paid from that lot, which takes it along (MTQx: B S$40 on
--      one lot); the header's query lists such lots (8). A lot behind the
--      release record's lot by a reissue other than this one's or 328's (a
--      merge, a customer change) is followed too now; read from the code, no
--      app call gives credit back there (a merge of a buyer whose credit paid
--      a sale is refused, 445's NOT COVERED 1; a 'transfer' change of a
--      partly spent package paid in part is refused, 473 and 476; with every
--      sale refunded first nothing more is given back on the old lot).
--   4. 470's NOT COVERED 5 (a deadlock), accepted by the Owner for all
--      packages, now also for a special document's refund held back at
--      commit, and for credit given back on a lot 328's repair replaced
--      while the package is open (the forwarder locks the invoice after the
--      refund locked the lot, as 471's release-record path does). Read from
--      the code, not timed on copies.
--   5. No page reaches (a) or (c) (above); (b) is reached from the Finance
--      panel's Move only after an Owner's reversal, which only a direct call
--      makes; (D) from the Finance panel's Move after a Cancel and a Reopen
--      of a package paid in part, then a refund of a session paid from its
--      released credit. The suite's stand-ins (a special document's payment,
--      328's repair, a lock no record explains) are written with the
--      statements the real functions use.
--   6. A Move from such a lot leaves the lot moved from locked at S$0; a
--      later refund of a sale paid from it gives credit back there, which
--      stays with the lot's holder while the package is paid (MVXs: A S$20,
--      F keeps the S$20 moved; MVWs: A S$80, F S$20), as for any Move
--      (463's rule: a Move's recipient keeps what was moved).
--   7. 472's NOT COVERED 3 and 5 to 7, and 471's, are unchanged by 477.
--   8. A summary, Finance panel or Reopen dialog open on a screen when this
--      goes in shows the old answer until it is opened again; the server
--      checks again.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the texts are the tested ones (their AFTER md5s); the three functions
--     are all at their BEFORE (replaced) or all at their AFTER (left alone);
--     anything else, a mix included, is refused; no other function takes
--     their names; so a second run changes nothing;
--   * the functions it relies on are as read on a copy of production at 475
--     with 476 applied (pinned, below: 472's list as 475 and 476 left it,
--     then what the Move, a special document's credit, 476's holder and the
--     self-test use; the write-off, whose lock answer D reads, among them);
--     462's ledger trigger (it forwards a special document's refund), the
--     reopening's settlement and the triggers on invoices as read; a lot's
--     statuses and ceiling; one queue row per ledger row; lots and the
--     ledger keep their history; the columns read have these types; who
--     calls the forwarder, who reads or writes a cancellation's rows, the
--     queue, the amount owed back and the release record (the Move now
--     reads it too), what gives credit back on a lot, what locks a lot (the
--     list answer D relies on), what writes 328's repair row and its link,
--     what names an Owner's reversal row, who writes a special document's
--     credit, and that no function calls the two app functions changed, all
--     as read;
--   * on the first run nothing is refused for the data (477 needs no
--     decision before it goes in); the invoices of the header's query are
--     named in a notice (invoice numbers only);
--   * who may call the three is as read, compared as sets, and kept;
--   * afterwards: the AFTER md5s and the grants as tested.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0477, so it leaves no row): a made-up Owner, store, cash method, S$100
--   package and S$20 session, and customers with fictional ACMA phones no
--   customer has, eight times, the package sold to A: (a) paid, a S$20
--   special document and a session paid from it, an Owner reverses the S$60
--   left, cancelled, the document refunded: the lot opened, A S$0, S$20 held
--   back (one held-back row), the reversal's S$60 row as it was; (b) the
--   same, still paid: A S$20 on the open lot, nothing held back; (c) paid,
--   two sessions, the S$60 left reversed, S1 refunded, an Owner's Move to F:
--   F S$20 on a lot not locked, A's lot S$0 and still locked, the reversal's
--   row as it was; (d) S$40 paid, S1, cancelled (the write-off takes the
--   S$20 left), reopened, paid, S1 refunded (the released lot Cancel closed,
--   open again, locked; answer D): an Owner's Move to F: F S$20 on a lot not
--   locked, A's lot S$0 and still locked, the write-off's S$20 row as it
--   was; (e) S$40 paid, S1 from the released lot, 328's repair (a
--   stand-in), paid in full, S1 refunded: one new lot of A's holding S$40
--   replaces the repair's lot, the old lots S$0, A S$100, then Cancel takes
--   it all; (f) the same, not paid in full:
--   the new lot is the one the release record reaches now, A S$40; (g) two
--   packages on one invoice, S$100 paid (the first released in full), five
--   sessions paid from it, a 'transfer' change to B, S1 refunded: B S$20 on
--   one new lot that the release record reaches now, A S$0; (h) paid, S1, a
--   lock that no Owner's reversal and no release record explains (a
--   stand-in: no function makes one), S1 refunded: the Move refused, "This
--   credit lot is locked or reversed", F nothing.
--   Its credit ledger rows draw entry numbers (a sequence, which an undone
--   transaction does not give back: a gap, as 443 to 476's self-tests).
--   Locks: the three functions' catalogue rows to the end of the apply, and
--   the rows the self-test writes and undoes; no table is locked against
--   ordinary writes. The self-test takes the commission advisory locks
--   (through its cancels, refunds and settlements) and new invoice numbers,
--   so it waits for any app cancel, refund, commission-writing payment or
--   invoice creation still open, and those wait for it, for under a second.
--   If one stays open longer than the 5 s lock timeout, or an invoice
--   created at the same moment takes the self-test's invoice number, the
--   apply stops, changing nothing, and can be run again. A refund or Move
--   still open when 477 commits runs on the text it started with. Apply at
--   a quiet time.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (475 in, 27 Oct 2026: e948504d, 1387 functions; the grant
--   list 381ef69c; head 20261027082304) -> 476 (cc718597, 1390 functions; on
--   a copy the grant list c05bd82e) -> 477 (-> 478, built after this file in
--   the same batch, which pins what it finds, 477's AFTERs among it). 477
--   pins 475's reopen_invoice and seven of 476's functions (their AFTERs:
--   the list, the mover, the release, the two issuers, the holder and the
--   sale marker it calls), and changes refund_special_credit (462 and 470 to 472 pin it),
--   transfer_invoice_unused_benefit (445 to 448, 451, 460, 462, 463, 470 to
--   473 and 476 pin it) and the forwarder (472's AFTER; 473 to 476 pin it):
--   after 477 a re-run of any of 445 to 448, 451, 460, 462, 463 and 470 to
--   476 refuses (on one of its pins), changing nothing (checked on a copy:
--   each refused, the fingerprint unchanged); all are applied, so nothing
--   is lost; 477's own re-run leaves all alone. This file's first build
--   pinned 476's first build: it is re-pinned here on 476's AFTERs (the
--   functions changed, and the Move for answer D, its AFTER 720d296a, was
--   95322bb1 in the first build; the special refund's and the forwarder's
--   AFTERs are as they were). If anything else goes in first, work the
--   fingerprints out again and check that it changes none of the functions
--   pinned below.
--   1. Before it, read only (invoice numbers and counts only; production was
--      not read for this file). 477 refuses no state; this lists whose
--      answer changes (1 to 3, 6, 7) and what needs the Owner (4, 5, 8, 9).
--      On the production facts known (27 Oct 2026, above) it is expected to
--      list nothing, but 6 and 9 (locked lots holding credit), 7 and 8 (not
--      read) may list invoices:
--     with
--     -- lots 328's repair replaced (its ledger row), and lots an Owner reversed
--     -- (reverse_credit_lot's 'reversal' row)
--     rp as (
--       select distinct e.lot_id from public.customer_credit_ledger e
--        where e.source_type = 'credit_lot_provenance_repair' and e.lot_id is not null),
--     rv as (
--       select distinct e.lot_id from public.customer_credit_ledger e
--        where e.entry_type = 'reverse' and e.source_type = 'reversal' and e.lot_id is not null),
--     -- the invoice whose records reach a lot: a benefit row that names it or a
--     -- lot reissued from it, or a release record whose chain reaches it
--     own as (
--       select b.invoice_id, a.lot_id
--         from public.invoice_benefit_values b
--         cross join lateral unnest(public.credit_lot_ancestry(b.lot_id)) a(lot_id)
--        where b.lot_id is not null
--       union
--       select pl.invoice_id, c.lot_id
--         from public.credit_package_progress_lots pl
--         cross join lateral unnest(public.credit_lot_chain(pl.lot_id)) c(lot_id)),
--     -- the lots a benefit row names that are open, locked and hold credit, and
--     -- whether an Owner's reversal, a release record (a lot of credit released
--     -- before full payment: what Cancel's write-off locks) or 328's repair is on
--     -- them or a lot they were reissued from
--     locked as (
--       select b.invoice_id, l.id,
--              exists (select 1 from unnest(public.credit_lot_ancestry(l.id)) a(id) join rv on rv.lot_id = a.id) as reversed,
--              exists (select 1 from unnest(public.credit_lot_ancestry(l.id)) a(id)
--                       join public.credit_package_progress_lots pl on pl.lot_id = a.id) as released,
--              exists (select 1 from unnest(public.credit_lot_ancestry(l.id)) a(id) join rp on rp.lot_id = a.id) as repaired
--         from public.invoice_benefit_values b
--         join public.customer_credit_lots l on l.id = b.lot_id
--        where l.status = 'active' and l.is_locked and l.remaining_amount > 0),
--     -- (4) the lots of credit released before full payment of package lines not
--     -- settled, of invoices neither cancelled nor refunded, behind the lot their
--     -- release record reaches now (not 328's: 3), or that lot where its customer
--     -- no longer holds the invoice's benefits (462's rule)
--     astray as (
--       select pl.invoice_id, l.id
--         from public.credit_package_progress_lots pl
--         join public.invoices i on i.id = pl.invoice_id and i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
--         join public.invoice_items it on it.id = pl.invoice_item_id and it.credit_issued_at is null
--         cross join lateral unnest(public.credit_lot_chain(pl.lot_id)) c(lot_id)
--         join public.customer_credit_lots l on l.id = c.lot_id
--        where not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = any (public.credit_lot_chain(pl.lot_id)))
--          and not exists (select 1 from rp where rp.lot_id = l.id)
--          and (l.id <> public.credit_lot_current(pl.lot_id)
--               or coalesce(public.invoice_credit_live_holder(pl.invoice_id, l.customer_id, l.created_at), l.customer_id) <> l.customer_id)),
--     found(reason, invoice_id, n) as (
--       select '1 changes: special documents paid with credit from a lot that is closed now, which can still be refunded (their refund now opens the lot: the credit is then held back, goes to whoever holds the benefits, or is spendable, by the forwarder''s rules; on a lot a Cancel closed while the package is still cancelled it is taken back as before; before, it stayed on the closed lot, which no one could spend) (the count is of documents'' allocations)', o.invoice_id, count(*)
--         from public.special_credit_allocations s
--         join public.customer_credit_lots l on l.id = s.lot_id
--         left join own o on o.lot_id = l.id
--        where s.amount > coalesce(s.reversed_amount, 0) and l.status <> 'active'
--        group by o.invoice_id
--       union all
--       select '2 changes: credit an Owner reversed and a refund or correction then put back, held on a lot the records name (locked): an Owner''s Move of it is now allowed (before, refused: "This credit lot is locked or reversed") (the count is of lots)', k.invoice_id, count(*)
--         from locked k where k.reversed and not k.repaired
--        group by k.invoice_id
--       union all
--       select '3 changes: sales paid from a lot 328''s repair replaced that can still be refunded or corrected (the credit they give back now goes to the lot the records name, and is held back there or goes to whoever holds the benefits; before, it stayed on the replaced lot) (the count is of sales)', o.invoice_id,
--              sum((select count(*) from public.invoice_line_credit_allocations a where a.lot_id = rp.lot_id and a.amount > coalesce(a.reversed_amount, 0))
--                  + (select count(*) from public.special_credit_allocations s where s.lot_id = rp.lot_id and s.amount > coalesce(s.reversed_amount, 0)))
--         from rp left join own o on o.lot_id = rp.lot_id
--        group by o.invoice_id
--       having sum((select count(*) from public.invoice_line_credit_allocations a where a.lot_id = rp.lot_id and a.amount > coalesce(a.reversed_amount, 0))
--                  + (select count(*) from public.special_credit_allocations s where s.lot_id = rp.lot_id and s.amount > coalesce(s.reversed_amount, 0))) > 0
--       union all
--       select '4 for the Owner (not changed by 477: NOT COVERED 2): credit on a closed lot today (a special document''s refund before 477), which no one can spend; it stays until a refund of a sale paid from that lot opens it (the count is of lots)', o.invoice_id, count(distinct l.id)
--         from public.customer_credit_lots l
--         left join own o on o.lot_id = l.id
--        where l.status <> 'active' and l.remaining_amount > 0
--        group by o.invoice_id
--       union all
--       select '5 for the Owner (not changed by 477: NOT COVERED 3): credit on a lot 328''s repair replaced today, given back before 477; it stays until the next refund or correction of a sale paid from that lot or a lot that replaced it, which takes it along (the count is of lots)', o.invoice_id, count(distinct l.id)
--         from rp join public.customer_credit_lots l on l.id = rp.lot_id
--         left join own o on o.lot_id = l.id
--        where l.status = 'active' and l.remaining_amount > 0
--        group by o.invoice_id
--       union all
--       select '6 changes (the Owner''s answer D): credit held on a lot the records name that a Cancel''s write-off of credit released before full payment locked (a release record names it or a lot it was reissued from; no Owner''s reversal, no 328 repair): an Owner''s Move of it is now allowed (before, refused: "This credit lot is locked or reversed") (the count is of lots)', k.invoice_id, count(*)
--         from locked k where k.released and not k.reversed and not k.repaired
--        group by k.invoice_id
--       union all
--       select '7 changes: sales paid from a lot of credit released before full payment, of a package not settled on an invoice neither cancelled nor refunded, that is behind the lot its release record reaches now or held by someone other than whoever holds the invoice''s benefits now (a ''transfer'' change made once it held nothing), which can still be refunded or corrected (the credit they give back now goes to whoever holds the benefits, on the lot the release record reaches; before, it stayed on that lot with its customer) (the count is of sales)', a.invoice_id,
--              sum((select count(*) from public.invoice_line_credit_allocations x where x.lot_id = a.id and x.amount > coalesce(x.reversed_amount, 0))
--                  + (select count(*) from public.special_credit_allocations s where s.lot_id = a.id and s.amount > coalesce(s.reversed_amount, 0)))
--         from astray a
--        group by a.invoice_id
--       having sum((select count(*) from public.invoice_line_credit_allocations x where x.lot_id = a.id and x.amount > coalesce(x.reversed_amount, 0))
--                  + (select count(*) from public.special_credit_allocations s where s.lot_id = a.id and s.amount > coalesce(s.reversed_amount, 0))) > 0
--       union all
--       select '8 for the Owner (not changed by 477: NOT COVERED 3): credit on such a lot today, given back before 477 and kept by a customer who no longer holds the benefits (or behind the lot the release record reaches); it stays until the next refund or correction of a sale paid from that lot, which takes it along (the count is of lots)', a.invoice_id, count(*)
--         from astray a join public.customer_credit_lots l on l.id = a.id
--        where l.status = 'active' and l.remaining_amount > 0
--        group by a.invoice_id
--       union all
--       select '9 for the Owner (not changed by 477: NOT COVERED 1): credit held on a lot the records name that 328''s repair locked, or that is locked with no Owner''s reversal and no release record to explain it: an Owner''s Move of it is still refused (the count is of lots)', k.invoice_id, count(*)
--         from locked k where k.repaired or not (k.reversed or k.released)
--        group by k.invoice_id)
--     select f.reason, coalesce(i.invoice_no, '(no invoice)') as invoice_no, f.n
--       from found f left join public.invoices i on i.id = f.invoice_id
--      order by f.reason, 2
--      (The suite runs this same text on its cases' states before 477 and
--      checks what it lists.)
--   2. Dry run on a copy of production as it is then (476 applied to it):
--      work out its fingerprint and grant list first (they must be
--      the BEFORE figures below, or be worked out again on that copy); apply
--      this file twice; the first run ends at the AFTER fingerprint below,
--      the second changes nothing ("left alone"); and the suite, with the
--      earlier suites below.
--   3. Apply (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself.
--   4. No page change goes with it (NOT CHANGED).
--   Afterwards (checked on copies of production at 475 with 476 applied,
--   27 Oct 2026): the suites that read what 477 changes, where it is in (-v
--   nomig=1): reversed-lot-credit-held-back-472 (its KNOWN K1, K2 and K4 and
--   its known cases PTsx, PTsxs, PTsxp and R328... checked as 477 settles
--   them), plain-cancelled-package-credit-471, cancelled-package-refund-470,
--   move-merge-leftovers-462, change-store-moves-bundle-vouchers-463,
--   part-paid-package-change-partly-spent-473,
--   part-paid-change-same-as-paid-in-full-476 (its start check takes 477's
--   forwarder; its K9 finds the Move of TQcru's lot, once paid, made where
--   477 is in and refused where not), merge-credit-origin-445 and
--   customer-change-credit-447
--   (their version checks take 477's AFTERs, the Move's 720d296a; no case of
--   theirs gives credit back on a closed or repaired lot or moves a locked
--   one, so every case ends as before). function-grants is unchanged
--   (nothing is added). 478's suite and file pin this file's first build
--   (and 476's): they must be re-pinned on these AFTERs before 478 goes in.
--
-- BEFORE (a copy of production at 475 with 476 applied, 27 Oct 2026; md5
-- of pg_get_functiondef with search_path public)
--   changed
--   refund_special_credit(text,uuid)                                   e019e28ad79539d771376c9b38d7e27e  (95's, as 462 and 470 to 472 pinned it)
--   transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)          7aebd7120bc3928db46df0941cb20889  (445's)
--   credit_given_back_follows(uuid)                                    f2a7a4d1ca28f0865b14e3f1e5e02bbb  (472's AFTER)
--   relied on, not changed (pinned)
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)          804ecd829cfecf713783a09a05d93c7e
--   cancel_invoice_recorded(uuid,text,uuid)                            de52d9dbaef8ab15163bef35cb9d733d
--   reopen_invoice(uuid,text,uuid)                                     30066e137b9b75b5789a050c14debc04  (475's AFTER)
--   correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)          af99337094edb6d73b9cc0ae00fbf138
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                        04d647e13e9424a9375942e5812e91a2
--   apply_reopened_invoice_benefits()                                  36eaa7224e514d3e7e42e3eeb51acfb5
--   invoice_reopen_preview_before_sessions(uuid)                       7e1ef2d25415e69b3f770fe2efd45190
--   invoice_reopen_preview(uuid)                                       e09ebf9c0841ef5463f96b26f4933541
--   invoice_benefit_unused_elsewhere(uuid)                             d35d7c8ae7187985ea64f8a5c38a7d79
--   cancelled_invoice_used_value(uuid)                                 055a3b07b1c15ffb1ac19039fa6cb650
--   invoice_action_plan(uuid,text,jsonb)                               383d618edb28c3c9a360242d038a022c
--   invoice_financial_position(uuid)                                   ba7eccbfeff217c8b1969b0e55a010ca
--   resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean) 201f08ebf14a64cd88d411a7cfb4c9c4
--   merge_customer_records(uuid,uuid,text,uuid)                        ba05c2b1fb4c0e14d369c01d06a635b0
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)             142dd3252911480bd4a17e7c55b488d3  (476's AFTER)
--   invoice_transferable_benefits(uuid)                                1546de1f83d970424d26e65941f4dcb8  (476's AFTER)
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
--   trg_legacy_refund_guard()                                          089965ef41a18fe3c54dd622e743075a
--   trg_lock_on_settle()                                               39c6478cdaec553c2ab8ceaf55058960
--   validate_invoice_business_metadata()                               c6e4436575e1c5ec8580d2b3d9d11d50
--   track_invoice_business_date_version()                              2c1e7ac8c5c2cfea8ddc5122adfc5d92
--   trg_create_therapy_on_paid()                                       012ae4e305b9870fa5596f740c0427b9
--   trg_fulfil_from_warehouse()                                        4abf4bf68e4f00658a8da66469e7059e
--   trg_issue_sold_vouchers_on_paid()                                  cf0b5610b77edfea2683751d5c25ca1d
--   writeoff_released_credit_on_close(uuid,text,text)                  284a89cfb965e8028136b5f8a4f2bf08
--   release_credit_package_paid_credit(uuid)                           f6685d987e998575c3c1e5917493dc24  (476's AFTER)
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
--   reverse_credit_lot(uuid,text,text,text)                            10c1a3d8e3bb003fbaf01cf879f97c5e
--   credit_lot_line_allowed(uuid,uuid)                                 7d81252612104b1012b6d78513092091
--   credit_lot_allows_category(uuid,text)                              935acacb64f836a97f0a1b4458d70d96
--   credit_lot_policy(text,text,boolean)                               d9a97af64871c4ebcff8d1f6c15f68a6
--   credit_policy_allows(text,text)                                    504f3055b3f1c1a038c5cae217e37fd6
--   credit_lot_policy_for(uuid)                                        ccdd506e78c7cdca97194fde87cdcc42
--   credit_line_benefits_holder(uuid)                                  45865ed52a5f24ebe6b8e435ba10e9e9  (476's AFTER)
--   credit_line_sale_group(uuid)                                       9c0e2931b672a763235d3d9839b2f02a  (476's AFTER; the holder calls it)
--   issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid)             5654ef9249cf5c6a943beb7890574f20  (476's AFTER)
--   sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid) 72d4ba2c35703b336f3b2e9114a6af6e  (476's AFTER)
--   pay_special_with_credit(text,uuid,uuid,numeric,uuid)               5496ea7f657d49629653defc905c88f2
--   assert_invoice_credit_source_evidence(uuid,uuid)                   64059b05526f32239ce1e60c6de39508
--   invoice_refund_options(uuid)                                       689a71c246260d2c10ec44dd94eb7139
--   grant_customer_credit(uuid,text,numeric,text,uuid,uuid,date,text,text,text,date,uuid,jsonb) ac0de5530624ee533aacf93aec389910
--   is_owner_or_manager()                                              a98e50f1b6d3fa1e6c62cf52a8073cc8
--   can_manage_customer_credit()                                       a576249272a4c7fb68965d0f62649ed4
--   user_has_store_access(uuid)                                        708992afaa6c3951f6329239b742987c
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)       80c80d386a5241e63b353e35e13ef250
--   record_invoice_payment(uuid,jsonb,uuid)                            9c70097ed4da614fb9dcc66fdfcdb7d6
--   the triggers on invoices (md5 of their definitions, by name)       92c94e3ebc6113a68d972330bbca8938 (19 triggers)
--   public function fingerprint, production now (475)                  e948504da4c17c1c15ff871fcb1e5631 (1387 functions; head 20261027082304)
--   public function fingerprint, 475 -> 476 (476's AFTER, on a copy)   cc7185970e4a01c0a225e114e0769691 (1390 functions)
--   grant list after 476 (string_agg(signature '=' proacl, '|'), sorted, on that copy)
--                                                                      c05bd82edeafa1bf1e7165a406fcb043 (production lists the same
--                                                                      grants in another order: compare as sets)
--   grant list after 476 as sets (each proacl's items sorted)          5752c2df613b8a673831d1797636e3d7
-- AFTER (for later guards)
--   refund_special_credit(text,uuid)                                   42e436aa44046d4cb1748641cd8a5257  (grants kept: postgres, the service role;
--                                                                      as in this file's first build)
--   transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)          720d296a43524e7ac8843c6062030819  (grants kept: signed-in staff, postgres, the service role;
--                                                                      the first build's 95322bb1 and answer D)
--   credit_given_back_follows(uuid)                                    a0f2f5ece30be439049dca275802237a  (grants kept: postgres, the service role;
--                                                                      as in this file's first build, after its fix)
--   public function fingerprint, worked out on a copy of production at 475 with 476 applied (worked out again on 28 Oct 2026,
--   after 476's Pay dialog read gained the credit a reopened invoice gives back; a second run the same):
--     production now (475) -> 476 -> 477                               88ba82ccc06315d862081fba55ce725d (1390 functions: none added, none dropped)
--     (on 476's build of 27 Oct 2026: 8c16bb63 -> c5faaa1f; 477 does not pin that read)
--   grant list after 477                                               c05bd82edeafa1bf1e7165a406fcb043 (unchanged; as sets 5752c2df, unchanged)
--   the triggers on invoices                                           92c94e3ebc6113a68d972330bbca8938 (19, unchanged)
--
-- Test: scripts/invoices/tests/special-refund-move-repaired-lot-477.sql
-- (begin ... rollback; it installs this file twice; -v nomig=1 where it is
-- in). It reproduces PTsx..., MVX..., R328..., TQx... and MVW... first, then
-- checks the header's query (1 to 9), the refusals, the install, every case
-- after 477 with 462's invariants (473's reading of them) and Cancel, the
-- controls exactly as before, cases begun before 477 and finished after it,
-- probes (the lot opened and held back in place, its reversal row as it
-- was; the moved lot unlocked and traced to its origin, the lot moved from
-- locked at S$0 with its reversal's or write-off's row; a lot the write-off
-- locked without a row moved by its release record; 328's repair on the
-- history refused; the new lot replacing the repair's lot, the release
-- record's lot it reaches now, the Audit Log; a lot outside any invoice
-- opened by a special document's refund), and NOT COVERED 1 to 3 as KNOWN.
-- Each app call is followed by what its commit does (462's trigger is
-- deferred). Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The functions this changes: BEFORE (a copy of production at 475 with
  -- 476 applied, 27 Oct 2026) and AFTER md5s; who may call each, as read
  -- (kept) ════════════════════════════════════════════════════════════════
  c_sigs constant text[] := array[
    'refund_special_credit(text,uuid)',
    'transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)',
    'credit_given_back_follows(uuid)'];
  c_names constant text[] := array['refund_special_credit', 'transfer_invoice_unused_benefit', 'credit_given_back_follows'];
  c_before constant text[] := array[
    'e019e28ad79539d771376c9b38d7e27e',
    '7aebd7120bc3928db46df0941cb20889',
    'f2a7a4d1ca28f0865b14e3f1e5e02bbb'];
  c_after constant text[] := array[
    '42e436aa44046d4cb1748641cd8a5257',
    '720d296a43524e7ac8843c6062030819',
    'a0f2f5ece30be439049dca275802237a'];
  c_acl constant text[] := array[
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}'];

  -- ══ The whole texts (exactly as the database prints them back) ══════════
  c_def_special constant text := $d1$CREATE OR REPLACE FUNCTION public.refund_special_credit(p_doc_kind text, p_doc_id uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 477 (the Owner, 27 Oct 2026, answering 472's NOT COVERED 2): the credit
-- a special document's wallet payment took goes back on its lot and opens
-- it ('active'), as refund_invoice_recorded and correct_invoice_payment do,
-- so 462's forwarder (at commit) holds it back, or moves it to whoever holds
-- the benefits, by the same rules. Before, it went back on the lot without
-- opening it: on a lot an Owner had reversed ('reversed') it stayed on a
-- closed lot that no one could spend, paid or cancelled. The lock is left,
-- as those two leave it; what the reversal took stays taken.
declare v_a record; v_total numeric := 0;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can refund wallet credit'; end if;

  for v_a in
    select * from public.special_credit_allocations
     where doc_kind = p_doc_kind and doc_id = p_doc_id
       and amount > coalesce(reversed_amount, 0)
  loop
    update public.customer_credit_lots
       set remaining_amount = remaining_amount + (v_a.amount - v_a.reversed_amount),
           status = 'active',
           updated_at = now()
     where id = v_a.lot_id;

    insert into public.customer_credit_ledger
      (wallet_id, customer_id, lot_id, entry_type, category, amount, source_type,
       source_record_id, note, created_by)
    select l.wallet_id, v_a.customer_id, v_a.lot_id, 'reverse', v_a.category,
           (v_a.amount - v_a.reversed_amount), p_doc_kind, p_doc_id,
           'Refund of wallet-funded ' || replace(p_doc_kind,'_',' '), auth.uid()
      from public.customer_credit_lots l where l.id = v_a.lot_id;

    v_total := round(v_total + (v_a.amount - v_a.reversed_amount), 2);
    update public.special_credit_allocations set reversed_amount = amount where id = v_a.id;
  end loop;

  if p_doc_kind = 'special_sale' then
    update public.special_sales set credit_funded = greatest(credit_funded - v_total, 0) where id = p_doc_id;
  else
    update public.rentals set credit_funded = greatest(credit_funded - v_total, 0) where id = p_doc_id;
  end if;

  return v_total;
end $function$
$d1$;
  c_def_move constant text := $d2$CREATE OR REPLACE FUNCTION public.transfer_invoice_unused_benefit(p_benefit_id uuid, p_customer_id uuid, p_store_id uuid, p_reason text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b public.invoice_benefit_values%rowtype; i public.invoices%rowtype;
 l public.customer_credit_lots%rowtype; v public.customer_reward_vouchers%rowtype;
 t public.invoice_benefit_transfers%rowtype; moved numeric; wallet uuid; replacement uuid;
 new_benefit uuid; transfer_id uuid:=gen_random_uuid(); h text; old_snapshot jsonb; new_snapshot jsonb;
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can correct benefit recipients'; end if;
 if nullif(trim(p_reason),'') is null or p_request_id is null then raise exception 'A reason and request ID are required'; end if;
 select * into b from public.invoice_benefit_values where id=p_benefit_id;
 select * into i from public.invoices where id=b.invoice_id for update;
 if not found or i.deleted_at is not null or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 if not public.user_has_store_access(p_store_id) then raise exception 'No access to the destination store'; end if;
 h:=md5(jsonb_build_object('benefit',p_benefit_id,'customer',p_customer_id,'store',p_store_id,'reason',p_reason)::text);
 select * into t from public.invoice_benefit_transfers where invoice_id=i.id and request_id=p_request_id;
 if found then
  if t.request_hash<>h then raise exception 'This transfer request ID was already used for different details'; end if;
  return jsonb_build_object('success',true,'replayed',true,'transferred_value',t.transferred_value,'benefit_id',t.replacement_benefit_id);
 end if;
 if not exists(select 1 from public.customers where id=p_customer_id and deleted_at is null) then raise exception 'Choose a non-deleted recipient'; end if;
 if i.status in ('cancelled','refunded','cancellation_requested','refund_requested') then
  raise exception 'Resolve the invoice status and explicitly reopen it before moving spendable benefits'; end if;
 if exists(select 1 from public.invoice_reopen_benefits where invoice_id=i.id and applied_at is null)
  or exists(select 1 from public.invoice_reopen_vouchers where invoice_id=i.id and applied_at is null) then
  raise exception 'Settle the reopened invoice before moving its reinstated benefits'; end if;
 select * into b from public.invoice_benefit_values where id=p_benefit_id for update;
 perform public.assert_invoice_credit_source_evidence(i.id,b.invoice_item_id);
 if b.cancelled_unused_value>0 then raise exception 'Resolve reserved cancelled benefits before moving this allocation'; end if;
 if b.lot_id is not null then
  select * into l from public.customer_credit_lots where id=b.lot_id for update;
  -- 477 (the Owner, 27 Oct 2026, answering 472's NOT COVERED 4): credit a
  -- refund or a correction put back on a lot an Owner had reversed
  -- (reverse_credit_lot's 'reversal' row, on this lot or a lot it was
  -- reissued from: a reissue copies the lock) can be moved: what the lot
  -- holds now, so what the reversal took stays taken. 477 also (the Owner,
  -- 27 Oct 2026, answer D, 477's NOT COVERED 1): so can credit on a lot
  -- Cancel's write-off of credit released before full payment locked
  -- (writeoff_released_credit_on_close, or what the forwarder holds back
  -- the same way while the invoice is cancelled): a release record
  -- (credit_package_progress_lots) names this lot or a lot it was reissued
  -- from. The write-off locks such a lot also where it took nothing (all of
  -- it was spent), so no ledger row of its own need be on it; what it took
  -- stays taken. Every other lock is still refused: 328's repair
  -- ('credit_lot_provenance_repair', on any of them), and a lock that no
  -- Owner's reversal and no release record explains.
  if l.status<>'active'
     or l.is_locked
        and not ((exists(select 1 from public.customer_credit_lots c join public.customer_credit_ledger e
                                  on e.customer_id=c.customer_id and e.lot_id=c.id
                          where c.id=any(public.credit_lot_ancestry(l.id))
                            and e.entry_type='reverse' and e.source_type='reversal')
                  or exists(select 1 from public.credit_package_progress_lots pl
                             where pl.lot_id=any(public.credit_lot_ancestry(l.id))))
                 and not exists(select 1 from public.customer_credit_lots c join public.customer_credit_ledger e
                                     on e.customer_id=c.customer_id and e.lot_id=c.id
                                 where c.id=any(public.credit_lot_ancestry(l.id))
                                   and e.source_type='credit_lot_provenance_repair')) then
   raise exception 'This credit lot is locked or reversed'; end if;
  if (l.customer_id,l.store_id) is not distinct from (p_customer_id,p_store_id) then raise exception 'Choose a different recipient or store'; end if;
  moved:=l.remaining_amount; old_snapshot:=to_jsonb(l);
 else
  select * into v from public.customer_reward_vouchers where id=b.reward_voucher_id for update;
  if v.status<>'held' then raise exception 'Only unused held vouchers can move; redeemed records remain with their original recipient'; end if;
  if (v.customer_id,v.store_id) is not distinct from (p_customer_id,p_store_id) then raise exception 'Choose a different recipient or store'; end if;
  moved:=v.quantity; old_snapshot:=to_jsonb(v);
 end if;
 if moved is null or moved<=0 then raise exception 'No unused value remains to move'; end if;
 insert into public.invoice_benefit_transfers(id,invoice_id,source_benefit_id,customer_id,store_id,transferred_value,request_id,request_hash,reason,before_snapshot,created_by)
  values(transfer_id,i.id,b.id,p_customer_id,p_store_id,moved,p_request_id,h,p_reason,old_snapshot,auth.uid());
 replacement:=gen_random_uuid();
 if b.lot_id is not null then
  insert into public.customer_credit_wallets(customer_id) values(p_customer_id) on conflict(customer_id) do nothing;
  select id into wallet from public.customer_credit_wallets where customer_id=p_customer_id;
  update public.customer_credit_lots set remaining_amount=0,updated_at=now() where id=l.id;
  insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
   values(l.wallet_id,l.customer_id,'adjust_decrease',l.category,moved,l.id,'invoice_benefit_transfer_out',transfer_id,l.store_id,p_reason,auth.uid(),auth.uid());
  -- Carry eligibility, expiry/restrictions and original purchase date, so a
  -- recipient correction cannot turn bonus credit into unrestricted paid credit.
  -- 445: but not its link to a lot it replaced (reassigned_from_lot_id: an
  -- invoice reassignment's, 321, or a merge's): moved credit is traced through
  -- its transfer (invoice_credit_transfer_origin). A copied link made the
  -- recipient's lot read as the invoice's own credit (credit_lot_chain,
  -- invoice_credit_lot_ids).
  insert into public.customer_credit_lots select (jsonb_populate_record(null::public.customer_credit_lots,to_jsonb(l)||jsonb_build_object(
   'id',replacement,'wallet_id',wallet,'customer_id',p_customer_id,'store_id',p_store_id,
   'original_amount',moved,'remaining_amount',moved,'source_type','invoice_benefit_transfer','source_record_id',transfer_id,
   -- 477: the recipient's lot is not locked (the lock stays on the lot
   -- moved from, with the Owner's reversal row or the write-off it came from)
   'is_locked',false,
   'reference_no',null,'reason',p_reason,'reversal_of_lot_id',null,'reassigned_from_lot_id',null,'created_by',auth.uid(),'approved_by',auth.uid(),'created_at',now(),'updated_at',now()))).*;
  insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
   values(wallet,p_customer_id,'grant',l.category,moved,replacement,'invoice_benefit_transfer_in',transfer_id,p_store_id,p_reason,auth.uid(),auth.uid());
  select to_jsonb(q) into new_snapshot from public.customer_credit_lots q where id=replacement;
 else
  if v.store_id is distinct from p_store_id and exists(select 1 from public.vouchers where id=v.voucher_id and qty_type='limited') then
   update public.voucher_store_stock set current_qty=current_qty-v.quantity where voucher_id=v.voucher_id and store_id=p_store_id and current_qty>=v.quantity;
   if not found then raise exception 'Not enough voucher stock at the destination store'; end if;
   insert into public.voucher_store_stock(voucher_id,store_id,current_qty) values(v.voucher_id,v.store_id,v.quantity)
    on conflict(voucher_id,store_id) do update set current_qty=public.voucher_store_stock.current_qty+excluded.current_qty;
  end if;
  update public.customer_reward_vouchers set status='revoked',notes=concat_ws(E'\n',notes,'Unused units moved by invoice correction '||transfer_id) where id=v.id;
  insert into public.customer_reward_vouchers(id,customer_id,voucher_id,store_id,quantity,status,issued_by,source_type,source_id,notes)
   values(replacement,p_customer_id,v.voucher_id,p_store_id,v.quantity,'held',auth.uid(),'invoice_benefit_transfer',transfer_id,'Original voucher '||v.id||': '||p_reason);
  select to_jsonb(q) into new_snapshot from public.customer_reward_vouchers q where id=replacement;
 end if;
 insert into public.invoice_benefit_values(invoice_id,invoice_item_id,lot_id,reward_voucher_id,paid_value,granted_value,evidence,created_by)
  values(i.id,b.invoice_item_id,case when b.lot_id is not null then replacement end,case when b.reward_voucher_id is not null then replacement end,
   round(b.paid_value*moved/b.granted_value,2),moved,'Unused portion transferred from recorded allocation '||b.id||'; transfer '||transfer_id,auth.uid()) returning id into new_benefit;
 update public.invoice_benefit_transfers set replacement_benefit_id=new_benefit,after_snapshot=new_snapshot where id=transfer_id;
 update public.invoices set edit_count=coalesce(edit_count,0)+1,edited_at=now(),edited_by=auth.uid() where id=i.id;
 perform public.write_audit_ex('invoices',i.id,'unused_benefit_recipient_corrected',old_snapshot,new_snapshot,'invoices',p_reason,i.store_id);
 return jsonb_build_object('success',true,'transferred_value',moved,'benefit_id',new_benefit);
end $function$
$d2$;
  c_def_follows constant text := $d3$CREATE OR REPLACE FUNCTION public.credit_given_back_follows(p_lot_id uuid)
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
-- 472 (the Owner, 26 Oct 2026: "fix the leftover gaps too", 471's NOT
-- COVERED 10: an Owner's reversal stays reversed, what it took stays taken,
-- and credit a refund gives back after it is the session's credit and
-- follows the same rules as 471's): a lot an Owner reversed
-- (reverse_credit_lot: 'reversed', locked, its 'reversal' ledger row) that a
-- refund or a correction of a sale paid from it opened again ('active',
-- still locked) was passed over, so while its invoice was cancelled, refunded
-- or waiting that credit stayed there for its holder to spend (after a guided
-- Cancel nothing more could be paid back), and it did not follow the
-- benefits' holder; and where the lot the records name was closed at S$0 (an
-- Owner reversed it), credit given back on a lot behind it stayed there. Now
-- a lock is no reason to pass a lot over, but 328's repair's (its
-- 'credit_lot_provenance_repair' row: such a lot carries 327's source, which
-- no credit payment could draw on, and no lot an invoice's records name
-- continues it); a lot the records name that is closed and holds nothing is
-- read too, so what is behind it follows; a closed lot holding credit
-- (refund_special_credit puts credit back without opening the lot) is passed
-- over, as before. Only what a lot holds is drawn, and an Owner's reversal
-- left nothing on it: what the reversal took stays taken.
-- 477 (the Owner, 27 Oct 2026, answering 472's NOT COVERED 1: credit given
-- back on a lot 328's repair replaced follows the same rules as any other
-- lot): 328's repair reversed what a lot of 327's source held and granted it
-- again as a lot that carries its package, which its release record names
-- (credit_package_progress_lots.replaces_lot_id), not reassigned_from_lot_id;
-- so credit given back on the old lot was not followed to the lot the
-- records name: it stayed on the old lot (cancelled, its buyer could spend
-- it; paid, Cancel left it; after a 'transfer' change it stayed the
-- buyer's), and 472 also passed that lot over by its lock. Now 328's link
-- is read as a reissue's: the lot the records name is found across it, the
-- old lot is one of the lots behind that lot, and its lock is no reason to
-- pass it over: it is held back, or follows the benefits' holder, as above.
-- Before the package is settled (no benefit row names its lots yet), credit
-- given back on such a lot while the invoice is neither cancelled nor
-- refunded goes to whoever holds the lot its release record reaches now
-- (credit_lot_current), as one new lot that replaces that lot, so Cancel's
-- write-off and the settlement find it there (they read that lot); while
-- cancelled or refunded it is taken back as before (471).
-- 477 also (the review of 475 to 478, 27 Oct 2026, by the Owner's rules:
-- credit follows a 'transfer' customer change; "Same as paid-in-full"):
-- the same before the package is settled for any lot of credit released
-- before full payment, not only one 328's repair replaced. Credit a refund
-- gave back, while the invoice was open, on the lot its release record
-- reaches now stayed with that lot's customer also where that customer no
-- longer holds the invoice's benefits by 462's rule (a 'transfer' change
-- made once what the lot held was spent in full: a lot holding nothing is
-- not reissued, so the change moved nothing), where the same package paid
-- in full gives it to whoever holds the benefits. Now it goes to that
-- holder as one new lot the release record reaches, as above; and so does
-- credit given back on any lot behind that lot.
declare v_try int:=0; v_k int; v_cur uuid; v_prev uuid; v_inv uuid; v_locked boolean:=false; v_status text;
 b public.invoice_benefit_values%rowtype; n public.customer_credit_lots%rowtype; x record;
 v_chain uuid[]; v_h uuid; v_more boolean; v_total numeric:=0; v_new uuid; v_wallet uuid; v_cap numeric;
 v_from jsonb:='[]'::jsonb; v_parent uuid; v_up uuid; v_depth int; v_replace boolean;
 -- 470
 v_hold boolean:=false; v_wait uuid; v_carry numeric:=0; v_held jsonb:='[]'::jsonb; v_mark uuid; v_take uuid; hb record;
 v_owed numeric; v_owed_new numeric; v_owed_add numeric;
 -- 471
 v_plain boolean:=false; v_rel uuid; v_rel_amt numeric;
 -- 477
 v_link uuid; v_last public.customer_credit_lots%rowtype; v_lots uuid[];
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
    select nx.id,w.k+1 from w join public.customer_credit_lots o on o.id=w.id
      cross join lateral (
        select l.id from public.customer_credit_lots l
         where l.reassigned_from_lot_id=o.id
           and (l.source_type,l.source_record_id) is not distinct from (o.source_type,o.source_record_id)
        union all
        -- 477: the lot 328's repair granted in place of this one
        select pl.lot_id from public.credit_package_progress_lots pl
         where pl.replaces_lot_id=o.id
           and exists(select 1 from public.customer_credit_ledger e
                       where e.customer_id=o.customer_id and e.lot_id=o.id
                         and e.source_type='credit_lot_provenance_repair')) nx
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
  -- reopened and paid in full. 472: so is a lot an Owner reversed (opened
  -- again so, or closed at S$0 and named, with credit behind it). 477: and a
  -- lot 328's repair replaced. A closed lot holding credit is passed over,
  -- as before (since 477 every refund opens the lot it gives back on).
  if n.status<>'active' and n.remaining_amount>0 then return; end if;
  v_chain:=public.credit_lot_ancestry(n.id);
  -- 477: and back across 328's repair: the lot it replaced (its release
  -- record names it; its repair row), then the lots that one replaced.
  loop
   v_link:=(select pl.replaces_lot_id from public.credit_package_progress_lots pl
             join public.customer_credit_lots r on r.id=pl.replaces_lot_id
            where pl.lot_id=v_chain[cardinality(v_chain)]
              and exists(select 1 from public.customer_credit_ledger e
                          where e.customer_id=r.customer_id and e.lot_id=r.id
                            and e.source_type='credit_lot_provenance_repair'));
   exit when v_link is null or v_link=any(v_chain) or cardinality(v_chain)>12;
   v_chain:=v_chain||public.credit_lot_ancestry(v_link);
  end loop;
  v_chain:=v_chain[1:13];
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
                  where l.id=any(v_chain) and l.id<>n.id and l.remaining_amount>0 and l.status='active');
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
     and (select i.status::text from public.invoices i where i.id=v_inv) is distinct from 'refunded' then
   -- 477: credit given back, while the invoice is open, on a lot behind the
   -- lot its release record reaches now (328's repair replaced it, or a
   -- reissue did), or on that lot where its customer no longer holds the
   -- invoice's benefits (462's rule): to whoever holds that lot, as one new
   -- lot that replaces it (what the lots from this one forward hold is
   -- drawn; the holder is granted the total; the new lot copies that lot's
   -- source, category, restrictions, store and dates), or takes its place
   -- where this made it and nothing has touched it since. Read first without
   -- locks; then the invoice and the lots locked, and read again.
   v_lots:=public.credit_lot_chain(p_lot_id);
   if coalesce((select l.remaining_amount from public.customer_credit_lots l where l.id=p_lot_id and l.status='active'),0)<=0 then
    return;
   end if;
   if cardinality(v_lots)<2
      and (select coalesce(public.invoice_credit_live_holder(v_inv,l.customer_id,l.created_at),l.customer_id)=l.customer_id
             from public.customer_credit_lots l where l.id=p_lot_id) then
    return;
   end if;
   perform 1 from public.invoices where id=v_inv for update;
   perform 1 from public.customer_credit_lots where id=any(v_lots) order by created_at,id for update;
   if public.credit_lot_chain(p_lot_id) is distinct from v_lots then
    raise exception 'Credit given back on lot % could not be matched to the invoice that names it (it kept changing). Nothing was recorded; try again.',p_lot_id;
   end if;
   select i.status::text into v_status from public.invoices i where i.id=v_inv;
   if v_status in ('cancelled','refunded') then
    raise exception 'Credit given back on lot % could not be matched to the invoice that names it (it kept changing). Nothing was recorded; try again.',p_lot_id;
   end if;
   select * into v_last from public.customer_credit_lots where id=v_lots[cardinality(v_lots)];
   v_h:=coalesce(public.invoice_credit_live_holder(v_inv,v_last.customer_id,v_last.created_at),
                 (select c.id from public.customers c where c.id=v_last.customer_id and c.deleted_at is null),
                 (select c.id from public.customer_credit_lots pl join public.customers c on c.id=pl.customer_id
                   where pl.id=p_lot_id and c.deleted_at is null));
   if v_h is null then
    raise exception 'Credit given back on lot % belongs with the benefits of invoice %, but whoever holds them, the invoice''s customer and the customer it went back to are all deleted. Nothing was recorded; ask the Owner.',
     p_lot_id,(select invoice_no from public.invoices where id=v_inv);
   end if;
   if cardinality(v_lots)<2 and v_h=v_last.customer_id then return; end if;
   if exists(select 1 from public.customer_credit_lots l
              where l.id=any(v_lots) and l.remaining_amount>0 and l.status='active'
                and l.category is distinct from v_last.category) then
    raise exception 'Credit given back on lot % is not of the category of the lot invoice % names for it. Nothing was recorded; ask the Owner.',
     p_lot_id,(select invoice_no from public.invoices where id=v_inv);
   end if;
   v_replace:=v_last.reassigned_from_lot_id is not null
     and (select count(*) from public.customer_credit_ledger e where e.lot_id=v_last.id)=1
     and exists(select 1 from public.customer_credit_ledger e
                 where e.lot_id=v_last.id and e.entry_type='grant' and e.source_type='credit_given_back_reassignment_in')
     and v_last.remaining_amount=v_last.original_amount;
   v_parent:=case when v_replace then v_last.reassigned_from_lot_id else v_last.id end;
   v_depth:=0; v_up:=v_parent;
   loop
    select l.reassigned_from_lot_id into v_up from public.customer_credit_lots l where l.id=v_up;
    exit when v_up is null or v_depth>=12;
    v_depth:=v_depth+1;
   end loop;
   if v_depth>=12 then
    raise exception 'Credit given back on lot % would make the chain of lots of invoice % longer than 12, further than the app follows. Nothing was recorded; ask the Owner.',
     p_lot_id,(select invoice_no from public.invoices where id=v_inv);
   end if;
   v_new:=gen_random_uuid(); v_wallet:=public.ensure_customer_wallet(v_h);
   for x in select l.* from public.customer_credit_lots l
             where l.id=any(v_lots) and l.remaining_amount>0 and l.status='active'
             order by l.created_at,l.id loop
    update public.customer_credit_lots set remaining_amount=0,updated_at=now() where id=x.id;
    insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
     values(x.wallet_id,x.customer_id,'adjust_decrease',x.category,x.remaining_amount,x.id,'credit_given_back_reassignment_out',v_inv,x.store_id,c_reason,auth.uid(),auth.uid());
    v_total:=v_total+x.remaining_amount;
    v_from:=v_from||jsonb_build_object('lot_id',x.id,'customer_id',x.customer_id,'amount',x.remaining_amount);
   end loop;
   if v_total<=0 then return; end if;
   insert into public.customer_credit_lots
   select (jsonb_populate_record(null::public.customer_credit_lots,to_jsonb(v_last)||jsonb_build_object(
     'id',v_new,'wallet_id',v_wallet,'customer_id',v_h,
     'original_amount',v_total,'remaining_amount',v_total,
     'status','active','is_locked',false,
     'reassigned_from_lot_id',v_parent,'reference_no',null,'reason',c_reason,'reversal_of_lot_id',null,
     'created_by',auth.uid(),'approved_by',auth.uid(),'created_at',clock_timestamp(),'updated_at',clock_timestamp()))).*;
   insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
    values(v_wallet,v_h,'grant',v_last.category,v_total,v_new,'credit_given_back_reassignment_in',v_inv,v_last.store_id,c_reason,auth.uid(),auth.uid());
   perform public.write_audit_ex('invoices',v_inv,'credit_given_back_followed',null,
     jsonb_build_object('lot_id',v_new,'to_customer',v_h,'amount',v_total,'from',v_from,'benefit_id',null,
       'replaces_lot_id',v_last.id,'in_place_of_lot_id',case when v_replace then v_last.id end,
       'released_credit',true,'release_lot_id',v_rel),
     'invoices',c_reason,(select store_id from public.invoices where id=v_inv));
   return;
  end if;
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
            where l.id=any(v_chain) and l.remaining_amount>0 and l.status='active'
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
           where l.id=any(v_chain) and l.remaining_amount>0 and l.status='active'
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
$d3$;

  -- ══ 462's ledger trigger, the reopening's settlement trigger and the
  -- triggers on invoices (an update of invoices runs them), as read ═════════
  c_ledger_trg_def constant text := $t$CREATE CONSTRAINT TRIGGER credit_given_back_follows AFTER INSERT ON public.customer_credit_ledger DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (((new.entry_type = 'reverse'::text) AND (new.lot_id IS NOT NULL) AND (new.source_type = ANY (ARRAY['invoice_payment_refund'::text, 'payment_correction'::text, 'special_sale'::text, 'rental'::text, 'rental_late_fee'::text])))) EXECUTE FUNCTION trg_credit_given_back_follows()$t$;
  c_settle_trg_def constant text := $t$CREATE TRIGGER invoice_reopen_benefits_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_benefits()$t$;
  c_inv_trg_md5 constant text := '92c94e3ebc6113a68d972330bbca8938';
  c_inv_trg_n constant int := 19;

  -- ══ Relied on, not changed (a copy of production at 475 with 476 applied,
  -- 27 Oct 2026): 472's list as 475 and 476 left it, then what the Move, a
  -- special document's credit, 476's holder and the self-test use ═════════
  c_relied constant text[] := array[
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'reopen_invoice(uuid,text,uuid)',
    'correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
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
    'reverse_credit_lot(uuid,text,text,text)',
    'credit_lot_line_allowed(uuid,uuid)',
    'credit_lot_allows_category(uuid,text)',
    'credit_lot_policy(text,text,boolean)',
    'credit_policy_allows(text,text)',
    'credit_lot_policy_for(uuid)',
    'credit_line_benefits_holder(uuid)',
    'credit_line_sale_group(uuid)',
    'issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid)',
    'sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid)',
    'pay_special_with_credit(text,uuid,uuid,numeric,uuid)',
    'assert_invoice_credit_source_evidence(uuid,uuid)',
    'invoice_refund_options(uuid)',
    'grant_customer_credit(uuid,text,numeric,text,uuid,uuid,date,text,text,text,date,uuid,jsonb)',
    'is_owner_or_manager()',
    'can_manage_customer_credit()',
    'user_has_store_access(uuid)',
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    'record_invoice_payment(uuid,jsonb,uuid)'];
  c_relied_md5 constant text[] := array[
    '804ecd829cfecf713783a09a05d93c7e',
    'de52d9dbaef8ab15163bef35cb9d733d',
    '30066e137b9b75b5789a050c14debc04',
    'af99337094edb6d73b9cc0ae00fbf138',
    '04d647e13e9424a9375942e5812e91a2',
    '36eaa7224e514d3e7e42e3eeb51acfb5',
    '7e1ef2d25415e69b3f770fe2efd45190',
    'e09ebf9c0841ef5463f96b26f4933541',
    'd35d7c8ae7187985ea64f8a5c38a7d79',
    '055a3b07b1c15ffb1ac19039fa6cb650',
    '383d618edb28c3c9a360242d038a022c',
    'ba7eccbfeff217c8b1969b0e55a010ca',
    '201f08ebf14a64cd88d411a7cfb4c9c4',
    'ba05c2b1fb4c0e14d369c01d06a635b0',
    '142dd3252911480bd4a17e7c55b488d3',
    '1546de1f83d970424d26e65941f4dcb8',
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
    'f6685d987e998575c3c1e5917493dc24',
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
    '10c1a3d8e3bb003fbaf01cf879f97c5e',
    '7d81252612104b1012b6d78513092091',
    '935acacb64f836a97f0a1b4458d70d96',
    'd9a97af64871c4ebcff8d1f6c15f68a6',
    '504f3055b3f1c1a038c5cae217e37fd6',
    'ccdd506e78c7cdca97194fde87cdcc42',
    '45865ed52a5f24ebe6b8e435ba10e9e9',
    '9c0e2931b672a763235d3d9839b2f02a',
    '5654ef9249cf5c6a943beb7890574f20',
    '72d4ba2c35703b336f3b2e9114a6af6e',
    '5496ea7f657d49629653defc905c88f2',
    '64059b05526f32239ce1e60c6de39508',
    '689a71c246260d2c10ec44dd94eb7139',
    'ac0de5530624ee533aacf93aec389910',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    'a576249272a4c7fb68965d0f62649ed4',
    '708992afaa6c3951f6329239b742987c',
    '80c80d386a5241e63b353e35e13ef250',
    '9c70097ed4da614fb9dcc66fdfcdb7d6'];
  -- Who calls the forwarder; who reads or writes a cancellation's ledger
  -- rows, the reopening queue and the amount owed back; what writes a
  -- 'reverse' ledger row and what raises a lot's balance; who reads or
  -- writes the release record and its write-off rows; what locks a lot; what
  -- writes 328's repair row and its link (replaces_lot_id); what names an
  -- Owner's reversal row; who writes a special document's credit; who calls
  -- the two changed app functions (by name; a session's own temporary
  -- functions and the three functions this changes are not counted), as read
  -- on a copy of production at 475 with 476 applied (27 Oct 2026).
  c_callers constant text := 'trg_credit_given_back_follows()';
  c_cancel_rows constant text := 'cancel_invoice_recorded(uuid,text,uuid), credit_lot_policy(text,text,boolean), invoice_benefit_unused_elsewhere(uuid), invoice_reopen_preview_before_sessions(uuid), reopen_invoice(uuid,text,uuid)';
  c_queue_inserts constant text := 'reopen_invoice(uuid,text,uuid)';
  c_queue_updates constant text := 'apply_reopened_invoice_benefits(), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)';
  c_owed_writers constant text := 'cancel_invoice_recorded(uuid,text,uuid), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)';
  c_reverse_writers constant text := 'apply_reopened_invoice_benefits(), correct_invoice_payment(uuid,numeric,date,uuid,text,uuid), customer_credit_statement(uuid,date,date), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), repair_credit_package_progress_lots(), reverse_credit_lot(uuid,text,text,text), reverse_invoice_date_recovery(uuid,uuid,text)';
  c_raisers constant text := 'apply_reopened_invoice_benefits(), correct_invoice_payment(uuid,numeric,date,uuid,text,uuid), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)';
  c_release_rw constant text := 'cancelled_invoice_used_value(uuid), capture_invoice_benefit_values(uuid), credit_line_benefits_holder(uuid), credit_lot_chain(uuid), credit_lot_source_group(uuid), credit_package_money_toward_line(uuid), credit_package_released_paid_credit(uuid), customer_credit_balances(uuid), invoice_commission_benefit_source(uuid), invoice_credit_lot_ids(uuid), invoice_transferable_benefits(uuid), move_invoice_benefits_to_customer(uuid,uuid,uuid,text), reclaim_released_credit_of_removed_lines(uuid,jsonb,text), release_credit_package_paid_credit(uuid), repair_credit_package_progress_lots(), trg_create_therapy_on_paid(), trim_released_paid_credit(uuid,text,boolean), writeoff_released_credit_on_close(uuid,text,text)';
  c_release_kinds constant text := 'cancel_invoice_recorded(uuid,text,uuid), cancelled_invoice_used_value(uuid), reclaim_released_credit_of_removed_lines(uuid,jsonb,text), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), trim_released_paid_credit(uuid,text,boolean), update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean), writeoff_released_credit_on_close(uuid,text,text)';
  c_lockers constant text := 'repair_credit_package_progress_lots(), reverse_credit_lot(uuid,text,text,text), writeoff_released_credit_on_close(uuid,text,text)';
  c_repair_rows constant text := 'repair_credit_package_progress_lots()';
  c_replaces constant text := 'credit_lot_chain(uuid), repair_credit_package_progress_lots()';
  c_reversal_rows constant text := 'correct_invoice_payment(uuid,numeric,date,uuid,text,uuid), remove_invoice_payment(uuid,text,uuid), reverse_credit_lot(uuid,text,text,text), split_invoice_payment(uuid,jsonb,text,uuid)';
  c_special_writers constant text := 'pay_special_with_credit(text,uuid,uuid,numeric,uuid)';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; n int; i int; v_first boolean; v_state text[] := '{}'; v_acl text[] := '{}';
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_pk uuid; t_svc uuid; t_wallet uuid;
  t_case int; t_a uuid; t_f uuid; t_inv uuid; t_s1 uuid; t_s2 uuid; t_ben uuid; t_lot uuid; t_lot1 uuid; t_lot2 uuid;
  t_new uuid; t_doc uuid; t_rev uuid; t_l record; t_err text; t_sum numeric; t_b uuid; t_k int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The texts are the tested ones.
  if md5(c_def_special) <> c_after[1] or md5(c_def_move) <> c_after[2] or md5(c_def_follows) <> c_after[3] then
    raise exception '477: the texts in this file are not the tested ones'; end if;

  -- The functions relied on are as read (a copy of production at 475 with
  -- 476 applied, 27 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '477: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if to_regprocedure('auth.uid()') is null then raise exception '477: auth.uid() must be there'; end if;

  -- The columns read and written, with these types (472's list, and what
  -- a special document's credit, the release record's link and a Move read).
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
                 ('special_credit_allocations', 'id', 'uuid'), ('special_credit_allocations', 'doc_kind', 'text'),
                 ('special_credit_allocations', 'doc_id', 'uuid'), ('special_credit_allocations', 'customer_id', 'uuid'),
                 ('special_credit_allocations', 'lot_id', 'uuid'), ('special_credit_allocations', 'category', 'text'),
                 ('special_credit_allocations', 'amount', 'numeric(14,2)'), ('special_credit_allocations', 'reversed_amount', 'numeric(14,2)'),
                 ('credit_package_progress_lots', 'lot_id', 'uuid'), ('credit_package_progress_lots', 'invoice_id', 'uuid'),
                 ('credit_package_progress_lots', 'released_amount', 'numeric(12,2)'), ('credit_package_progress_lots', 'replaces_lot_id', 'uuid'),
                 ('credit_package_progress_lots', 'created_at', 'timestamp with time zone'),
                 ('invoice_benefit_transfers', 'id', 'uuid'), ('invoice_benefit_transfers', 'replacement_benefit_id', 'uuid')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '477: these columns are missing or not as read on 27 Oct 2026: %', v; end if;
  -- One queue row per ledger row; a lot never holds more than it was
  -- granted; a lot is 'active' or 'reversed'; lots and the ledger keep their
  -- history.
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
    raise exception '477: the queue''s one row per ledger row, a lot''s ceiling or statuses, or the history guards are not as read on 27 Oct 2026'; end if;
  -- 462's ledger trigger (it forwards a special document's refund too), the
  -- reopening's settlement and the triggers on invoices, as they were read.
  if (select pg_get_triggerdef(oid) from pg_trigger where tgrelid = 'public.customer_credit_ledger'::regclass
       and tgname = 'credit_given_back_follows') is distinct from c_ledger_trg_def
     or (select pg_get_triggerdef(oid) from pg_trigger where tgrelid = 'public.invoices'::regclass
          and tgname = 'invoice_reopen_benefits_settled') is distinct from c_settle_trg_def then
    raise exception '477: 462''s trigger credit_given_back_follows or the reopening''s settlement trigger is not as made; 477 goes in after 462 to 476'; end if;
  select md5(string_agg(pg_get_triggerdef(oid), E'\n' order by tgname)), count(*) into v, n
    from pg_trigger where tgrelid = 'public.invoices'::regclass and not tgisinternal;
  if v is distinct from c_inv_trg_md5 or n <> c_inv_trg_n then
    raise exception '477: the triggers on invoices are not as read on 27 Oct 2026 (% triggers, md5 %); check what an update of an invoice''s amount owed back runs, then re-test', n, v; end if;

  -- No other function takes their names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = any (c_names)
     and not (p.oid::regprocedure::text = any (c_sigs));
  if v is not null then raise exception '477: another function takes the name of one this changes: %', v; end if;

  -- What the three are read with, as read (a new way would need the same care).
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'credit_given_back_follows\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and not (p.proname = any (c_names));
  if v is distinct from c_callers then
    raise exception '477: the functions that call credit_given_back_follows are not as read on 27 Oct 2026 (%)', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ '(refund_special_credit|transfer_invoice_unused_benefit)\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and not (p.proname = any (c_names));
  if v is not null then
    raise exception '477: a function calls refund_special_credit or transfer_invoice_unused_benefit (%); none did on 27 Oct 2026', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ '''invoice_cancel_benefit''' and ns.nspname not like 'pg\_temp\_%'
     and not (p.proname = any (c_names));
  if v is distinct from c_cancel_rows then
    raise exception '477: what reads or writes a cancellation''s ledger rows is not as read on 27 Oct 2026 (%)', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'insert\s+into\s+public\.invoice_reopen_benefits' and ns.nspname not like 'pg\_temp\_%'
     and not (p.proname = any (c_names));
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'update\s+public\.invoice_reopen_benefits' and ns.nspname not like 'pg\_temp\_%'
     and not (p.proname = any (c_names));
  if v is distinct from c_queue_inserts or d is distinct from c_queue_updates then
    raise exception '477: what writes the reopening''s queue is not as read on 27 Oct 2026 (% / %)', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'cancel_refund_owed\s*=' and ns.nspname not like 'pg\_temp\_%'
     and not (p.proname = any (c_names));
  if v is distinct from c_owed_writers then
    raise exception '477: what writes the amount owed back is not as read on 27 Oct 2026 (%)', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ '''reverse''' and ns.nspname not like 'pg\_temp\_%'
     and not (p.proname = any (c_names));
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'remaining_amount\s*=\s*(\w+\.)?remaining_amount\s*\+' and ns.nspname not like 'pg\_temp\_%'
     and not (p.proname = any (c_names));
  if v is distinct from c_reverse_writers or d is distinct from c_raisers then
    raise exception '477: what gives credit back on a lot is not as read on 27 Oct 2026 (% / %); check that 462''s trigger forwards each, and which opens the lot, then re-test', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'credit_package_progress_lots' and ns.nspname not like 'pg\_temp\_%'
     and not (p.proname = any (c_names));
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ '_released_credit' and ns.nspname not like 'pg\_temp\_%'
     and not (p.proname = any (c_names));
  if v is distinct from c_release_rw or d is distinct from c_release_kinds then
    raise exception '477: what reads or writes the release record of credit released before full payment, or its write-off rows, is not as read on 27 Oct 2026 (% / %)', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'is_locked\s*=\s*true' and ns.nspname not like 'pg\_temp\_%'
     and not (p.proname = any (c_names));
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ '''credit_lot_provenance_repair''' and ns.nspname not like 'pg\_temp\_%'
     and not (p.proname = any (c_names));
  if v is distinct from c_lockers or d is distinct from c_repair_rows then
    raise exception '477: what locks a credit lot, or writes 328''s repair row, is not as read on 27 Oct 2026 (% / %); check whether the forwarder and the Move may read past that lock, then re-test', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'replaces_lot_id' and ns.nspname not like 'pg\_temp\_%'
     and not (p.proname = any (c_names));
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ '''reversal''' and ns.nspname not like 'pg\_temp\_%'
     and not (p.proname = any (c_names));
  if v is distinct from c_replaces or d is distinct from c_reversal_rows then
    raise exception '477: what reads or writes 328''s link, or names an Owner''s reversal row, is not as read on 27 Oct 2026 (% / %)', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'insert\s+into\s+public\.special_credit_allocations' and ns.nspname not like 'pg\_temp\_%'
     and not (p.proname = any (c_names));
  if v is distinct from c_special_writers then
    raise exception '477: what writes a special document''s credit is not as read on 27 Oct 2026 (%)', v; end if;

  -- The three: all at their BEFORE (replaced), or all at their AFTER (left
  -- alone); anything else, a mix included, refused.
  for i in 1 .. 3 loop
    d := md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[i])));
    v_state := v_state || case when d = c_after[i] then 'after' when d = c_before[i] then 'before' else d end;
  end loop;
  if v_state = array['after', 'after', 'after'] then
    raise notice '477: public.%, public.% and public.% are already this version; left alone', c_sigs[1], c_sigs[2], c_sigs[3];
    v_first := false;
  elsif v_state = array['before', 'before', 'before'] then
    v_first := true;
  else
    raise exception '477: the functions this changes are not the versions this was tested against (%: %). Re-read them and re-test before applying.',
      array_to_string(c_sigs, ', '), array_to_string(v_state, ', ');
  end if;

  -- ── On the first run: nothing is refused for the data (477 needs no
  -- decision before it goes in), but whose answer changes, and what needs
  -- the Owner's decision, is named (the header's read-only query: invoice
  -- numbers only).
  if v_first then
    select string_agg(x.r || ': ' || x.list, '; ' order by x.r) into v
      from (select left(q.reason, 1) as r, string_agg(q.invoice_no, ', ' order by q.invoice_no) as list
              from (
                with
                -- lots 328's repair replaced (its ledger row), and lots an Owner reversed
                -- (reverse_credit_lot's 'reversal' row)
                rp as (
                  select distinct e.lot_id from public.customer_credit_ledger e
                   where e.source_type = 'credit_lot_provenance_repair' and e.lot_id is not null),
                rv as (
                  select distinct e.lot_id from public.customer_credit_ledger e
                   where e.entry_type = 'reverse' and e.source_type = 'reversal' and e.lot_id is not null),
                -- the invoice whose records reach a lot: a benefit row that names it or a
                -- lot reissued from it, or a release record whose chain reaches it
                own as (
                  select b.invoice_id, a.lot_id
                    from public.invoice_benefit_values b
                    cross join lateral unnest(public.credit_lot_ancestry(b.lot_id)) a(lot_id)
                   where b.lot_id is not null
                  union
                  select pl.invoice_id, c.lot_id
                    from public.credit_package_progress_lots pl
                    cross join lateral unnest(public.credit_lot_chain(pl.lot_id)) c(lot_id)),
                -- the lots a benefit row names that are open, locked and hold credit, and
                -- whether an Owner's reversal, a release record (a lot of credit released
                -- before full payment: what Cancel's write-off locks) or 328's repair is on
                -- them or a lot they were reissued from
                locked as (
                  select b.invoice_id, l.id,
                         exists (select 1 from unnest(public.credit_lot_ancestry(l.id)) a(id) join rv on rv.lot_id = a.id) as reversed,
                         exists (select 1 from unnest(public.credit_lot_ancestry(l.id)) a(id)
                                  join public.credit_package_progress_lots pl on pl.lot_id = a.id) as released,
                         exists (select 1 from unnest(public.credit_lot_ancestry(l.id)) a(id) join rp on rp.lot_id = a.id) as repaired
                    from public.invoice_benefit_values b
                    join public.customer_credit_lots l on l.id = b.lot_id
                   where l.status = 'active' and l.is_locked and l.remaining_amount > 0),
                -- (4) the lots of credit released before full payment of package lines not
                -- settled, of invoices neither cancelled nor refunded, behind the lot their
                -- release record reaches now (not 328's: 3), or that lot where its customer
                -- no longer holds the invoice's benefits (462's rule)
                astray as (
                  select pl.invoice_id, l.id
                    from public.credit_package_progress_lots pl
                    join public.invoices i on i.id = pl.invoice_id and i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
                    join public.invoice_items it on it.id = pl.invoice_item_id and it.credit_issued_at is null
                    cross join lateral unnest(public.credit_lot_chain(pl.lot_id)) c(lot_id)
                    join public.customer_credit_lots l on l.id = c.lot_id
                   where not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = any (public.credit_lot_chain(pl.lot_id)))
                     and not exists (select 1 from rp where rp.lot_id = l.id)
                     and (l.id <> public.credit_lot_current(pl.lot_id)
                          or coalesce(public.invoice_credit_live_holder(pl.invoice_id, l.customer_id, l.created_at), l.customer_id) <> l.customer_id)),
                found(reason, invoice_id, n) as (
                  select '1 changes: special documents paid with credit from a lot that is closed now, which can still be refunded (their refund now opens the lot: the credit is then held back, goes to whoever holds the benefits, or is spendable, by the forwarder''s rules; on a lot a Cancel closed while the package is still cancelled it is taken back as before; before, it stayed on the closed lot, which no one could spend) (the count is of documents'' allocations)', o.invoice_id, count(*)
                    from public.special_credit_allocations s
                    join public.customer_credit_lots l on l.id = s.lot_id
                    left join own o on o.lot_id = l.id
                   where s.amount > coalesce(s.reversed_amount, 0) and l.status <> 'active'
                   group by o.invoice_id
                  union all
                  select '2 changes: credit an Owner reversed and a refund or correction then put back, held on a lot the records name (locked): an Owner''s Move of it is now allowed (before, refused: "This credit lot is locked or reversed") (the count is of lots)', k.invoice_id, count(*)
                    from locked k where k.reversed and not k.repaired
                   group by k.invoice_id
                  union all
                  select '3 changes: sales paid from a lot 328''s repair replaced that can still be refunded or corrected (the credit they give back now goes to the lot the records name, and is held back there or goes to whoever holds the benefits; before, it stayed on the replaced lot) (the count is of sales)', o.invoice_id,
                         sum((select count(*) from public.invoice_line_credit_allocations a where a.lot_id = rp.lot_id and a.amount > coalesce(a.reversed_amount, 0))
                             + (select count(*) from public.special_credit_allocations s where s.lot_id = rp.lot_id and s.amount > coalesce(s.reversed_amount, 0)))
                    from rp left join own o on o.lot_id = rp.lot_id
                   group by o.invoice_id
                  having sum((select count(*) from public.invoice_line_credit_allocations a where a.lot_id = rp.lot_id and a.amount > coalesce(a.reversed_amount, 0))
                             + (select count(*) from public.special_credit_allocations s where s.lot_id = rp.lot_id and s.amount > coalesce(s.reversed_amount, 0))) > 0
                  union all
                  select '4 for the Owner (not changed by 477: NOT COVERED 2): credit on a closed lot today (a special document''s refund before 477), which no one can spend; it stays until a refund of a sale paid from that lot opens it (the count is of lots)', o.invoice_id, count(distinct l.id)
                    from public.customer_credit_lots l
                    left join own o on o.lot_id = l.id
                   where l.status <> 'active' and l.remaining_amount > 0
                   group by o.invoice_id
                  union all
                  select '5 for the Owner (not changed by 477: NOT COVERED 3): credit on a lot 328''s repair replaced today, given back before 477; it stays until the next refund or correction of a sale paid from that lot or a lot that replaced it, which takes it along (the count is of lots)', o.invoice_id, count(distinct l.id)
                    from rp join public.customer_credit_lots l on l.id = rp.lot_id
                    left join own o on o.lot_id = l.id
                   where l.status = 'active' and l.remaining_amount > 0
                   group by o.invoice_id
                  union all
                  select '6 changes (the Owner''s answer D): credit held on a lot the records name that a Cancel''s write-off of credit released before full payment locked (a release record names it or a lot it was reissued from; no Owner''s reversal, no 328 repair): an Owner''s Move of it is now allowed (before, refused: "This credit lot is locked or reversed") (the count is of lots)', k.invoice_id, count(*)
                    from locked k where k.released and not k.reversed and not k.repaired
                   group by k.invoice_id
                  union all
                  select '7 changes: sales paid from a lot of credit released before full payment, of a package not settled on an invoice neither cancelled nor refunded, that is behind the lot its release record reaches now or held by someone other than whoever holds the invoice''s benefits now (a ''transfer'' change made once it held nothing), which can still be refunded or corrected (the credit they give back now goes to whoever holds the benefits, on the lot the release record reaches; before, it stayed on that lot with its customer) (the count is of sales)', a.invoice_id,
                         sum((select count(*) from public.invoice_line_credit_allocations x where x.lot_id = a.id and x.amount > coalesce(x.reversed_amount, 0))
                             + (select count(*) from public.special_credit_allocations s where s.lot_id = a.id and s.amount > coalesce(s.reversed_amount, 0)))
                    from astray a
                   group by a.invoice_id
                  having sum((select count(*) from public.invoice_line_credit_allocations x where x.lot_id = a.id and x.amount > coalesce(x.reversed_amount, 0))
                             + (select count(*) from public.special_credit_allocations s where s.lot_id = a.id and s.amount > coalesce(s.reversed_amount, 0))) > 0
                  union all
                  select '8 for the Owner (not changed by 477: NOT COVERED 3): credit on such a lot today, given back before 477 and kept by a customer who no longer holds the benefits (or behind the lot the release record reaches); it stays until the next refund or correction of a sale paid from that lot, which takes it along (the count is of lots)', a.invoice_id, count(*)
                    from astray a join public.customer_credit_lots l on l.id = a.id
                   where l.status = 'active' and l.remaining_amount > 0
                   group by a.invoice_id
                  union all
                  select '9 for the Owner (not changed by 477: NOT COVERED 1): credit held on a lot the records name that 328''s repair locked, or that is locked with no Owner''s reversal and no release record to explain it: an Owner''s Move of it is still refused (the count is of lots)', k.invoice_id, count(*)
                    from locked k where k.repaired or not (k.reversed or k.released)
                   group by k.invoice_id)
                select f.reason, coalesce(i.invoice_no, '(no invoice)') as invoice_no, f.n
                  from found f left join public.invoices i on i.id = f.invoice_id
                 order by f.reason, 2
                   ) q
             group by left(q.reason, 1)) x;
    if v is not null then
      raise notice '477: the header''s query lists (1 to 3, 6 and 7: whose answer changes; 4, 5, 8 and 9: for the Owner, not changed by 477) %', v;
    end if;
  end if;

  -- Who may call them, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  for i in 1 .. 3 loop
    if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i]))
       is distinct from (select array_agg(x::text order by x::text) from unnest(c_acl[i]::aclitem[]) x) then
      raise exception '477: who may call public.% is not as read on 27 Oct 2026 (%)', c_sigs[i],
        (select proacl::text from pg_proc where oid = to_regprocedure('public.' || c_sigs[i])); end if;
    v_acl := v_acl || (select coalesce(string_agg(x::text, ',' order by x::text), '')
                         from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i]));
  end loop;

  -- ── Change ──────────────────────────────────────────────────────────────
  if v_first then
    execute c_def_special;
    execute c_def_move;
    execute c_def_follows;
  end if;

  -- ── Afterwards: installed exactly as tested, grants as before ───────────
  for i in 1 .. 3 loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[i]))) <> c_after[i] then
      raise exception '477: public.% is not at its AFTER md5 (%)', c_sigs[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[i]))); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i])) is distinct from v_acl[i] then
      raise exception '477: the grants of public.% changed', c_sigs[i]; end if;
  end loop;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("477 check", @example.com, fictional ACMA phones
  -- no customer uses); it ends by raising P0477, which undoes all it wrote.
  -- 462's trigger runs at commit; here at each step's end (SET CONSTRAINTS
  -- ... IMMEDIATE), as a commit would.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from generate_series(700, 799) g, lateral (select '+61491570' || g::text as p) x
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p desc limit 12);
    if coalesce(cardinality(t_phones), 0) < 12 then raise exception '477: the self-test found no twelve unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '477-check-' || t_sfx || '@example.com') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '477 check', '477-check-' || t_sfx || '@example.com', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('477 check ' || t_sfx, '477-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('477 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy, grants_reward)
    values ('477 check ' || t_sfx, 100, 100, false, true, true, false) returning id into t_pk;
    insert into public.credit_package_stores (package_id, store_id) values (t_pk, t_store);
    insert into public.therapy_services (service_code, name, standard_price, duration_minutes, is_active)
    values ('477-' || t_sfx, '477 check ' || t_sfx, 20, 30, true) returning id into t_svc;
    insert into public.therapy_service_stores (service_id, store_id, is_available) values (t_svc, t_store, true);
    select pm.id into t_wallet from public.payment_methods pm
     where pm.name = 'Wallet — Credit Package Paid' and pm.is_wallet_credit and pm.deleted_at is null;
    if t_wallet is null then raise exception '477: the wallet method "Wallet — Credit Package Paid" (443) is not there'; end if;

    for t_case in 1 .. 8 loop
      -- The common part: the S$100 package sold to A, paid in full ((a) to
      -- (c)) or S$40 of it ((d) to (f)); a S$20 session paid from it.
      insert into public.customers (full_name, phone) values ('477 Check Buyer ' || t_case || ' ' || t_sfx, t_phones[t_case]) returning id into t_a;
      if t_case = 7 then
        -- (g) two packages on one invoice, S$100 paid (the first line
        -- released in full, the second nothing), five S$20 sessions paid
        -- from it (all of it spent), a 'transfer' change to B (the lot holds
        -- nothing: not reissued, nothing blocks), S1 refunded: the S$20 goes
        -- to B on one new lot the release record reaches now; A S$0.
        insert into public.customers (full_name, phone) values ('477 Check Holder ' || t_case || ' ' || t_sfx, t_phones[12]) returning id into t_b;
        t_inv := public.create_invoice(t_store, t_a, null::uuid,
          jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1),
                            jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
          0::numeric, null::text, null::uuid, '[]'::jsonb);
        perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        for t_k in 1 .. 5 loop
          t_s2 := public.create_invoice(t_store, t_a, null::uuid,
            jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 1)),
            0::numeric, null::text, null::uuid, '[]'::jsonb);
          perform public.record_invoice_payment(t_s2, jsonb_build_array(jsonb_build_object('payment_method_id', t_wallet, 'amount', 20)), gen_random_uuid());
          if t_k = 1 then t_s1 := t_s2; end if;
        end loop;
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        select pl.lot_id into t_lot from public.credit_package_progress_lots pl where pl.invoice_id = t_inv;
        perform public.correct_invoice(t_inv,
          (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
                    'credit_package_id', it.credit_package_id, 'quantity', it.quantity, 'unit_price', it.unit_price)) order by it.id)
             from public.invoice_items it where it.invoice_id = t_inv),
          jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = t_inv),
            'customer_id', t_b, 'store_id', t_store, 'benefit_action', 'transfer'),
          '477 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        perform public.cancel_invoice_recorded(t_s1, '477 check', gen_random_uuid());
        perform public.refund_invoice_recorded(t_s1, jsonb_build_array(jsonb_build_object('amount', 20)),
          jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_s1 and p.entry_kind = 'receipt'
                                                               order by p.created_at limit 1), 'amount', 20)), '[]'::jsonb, '477 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        t_new := public.credit_lot_current(t_lot);
        if (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> 0
           or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_b) <> 20
           or t_new = t_lot
           or (select customer_id from public.customer_credit_lots where id = t_new) <> t_b
           or (select remaining_amount from public.customer_credit_lots where id = t_new) <> 20
           or (select reassigned_from_lot_id from public.customer_credit_lots where id = t_new) <> t_lot then
          raise exception '477: (g) credit given back after a ''transfer'' change, before settlement, did not go to the benefits'' holder (A %, B %)',
            (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a),
            (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_b); end if;
        continue;
      end if;
      t_inv := public.create_invoice(t_store, t_a, null::uuid,
        jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
      perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
        'amount', case when t_case <= 3 or t_case = 8 then 100 else 40 end)), gen_random_uuid());
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      if t_case <= 2 then
        -- (a), (b): a special document paid S$20 from A's lot (a stand-in for
        -- pay_special_with_credit: no page calls it), a session S$20; an
        -- Owner reverses the S$60 left; (a) cancelled; the document's credit
        -- refunded (refund_special_credit, the real one).
        select b.id, b.lot_id into t_ben, t_lot from public.invoice_benefit_values b where b.invoice_id = t_inv;
        t_doc := gen_random_uuid();
        select * into t_l from public.customer_credit_lots where id = t_lot;
        insert into public.customer_credit_ledger (wallet_id, customer_id, entry_type, category, amount, lot_id, source_type, source_record_id, store_id, note, created_by)
        values (t_l.wallet_id, t_a, 'use', t_l.category, 20, t_lot, 'special_sale', t_doc, t_l.store_id, '477 check', auth.uid());
        update public.customer_credit_lots set remaining_amount = remaining_amount - 20, updated_at = now() where id = t_lot;
        insert into public.special_credit_allocations (doc_kind, doc_id, customer_id, lot_id, category, amount, created_by)
        values ('special_sale', t_doc, t_a, t_lot, t_l.category, 20, auth.uid());
        t_s1 := public.create_invoice(t_store, t_a, null::uuid,
          jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 1)),
          0::numeric, null::text, null::uuid, '[]'::jsonb);
        perform public.record_invoice_payment(t_s1, jsonb_build_array(jsonb_build_object('payment_method_id', t_wallet, 'amount', 20)), gen_random_uuid());
        t_rev := public.reverse_credit_lot(t_lot, '477 check');
        if t_case = 1 then
          perform public.cancel_invoice_recorded(t_inv, '477 check', gen_random_uuid());
        end if;
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        perform public.refund_special_credit('special_sale', t_doc);
        if (select status from public.customer_credit_lots where id = t_lot) <> 'active' then
          raise exception '477: (%) the special document''s refund did not open the lot', chr(96 + t_case); end if;
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if t_case = 1 and ((select remaining_amount from public.customer_credit_lots where id = t_lot) <> 0
             or (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben) <> 20
             or (select count(*) from public.customer_credit_ledger e where e.lot_id = t_lot and e.entry_type = 'adjust_decrease'
                  and e.source_type = 'invoice_cancel_benefit' and e.amount = 20) <> 1
             or (select amount from public.customer_credit_ledger where id = t_rev) <> 60) then
          raise exception '477: (a) the special document''s refund onto the lot an Owner reversed was not held back for the cancellation (A %, held back %)',
            (select remaining_amount from public.customer_credit_lots where id = t_lot),
            (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben); end if;
        if t_case = 2 and ((select remaining_amount from public.customer_credit_lots where id = t_lot) <> 20
             or (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben) <> 0) then
          raise exception '477: (b) the special document''s refund onto the lot an Owner reversed, the package paid, did not stay with A to spend'; end if;
        continue;
      end if;
      t_s1 := public.create_invoice(t_store, t_a, null::uuid,
        jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
      perform public.record_invoice_payment(t_s1, jsonb_build_array(jsonb_build_object('payment_method_id', t_wallet, 'amount', 20)), gen_random_uuid());
      if t_case = 3 then
        -- (c) a second session, an Owner reverses the S$60 left, S1 refunded
        -- (S$20 back on the lot, opened, still locked), then an Owner's Move
        -- of it to F: F holds S$20 on a lot that is not locked, A S$0, the
        -- reversal's S$60 row as it was.
        t_s2 := public.create_invoice(t_store, t_a, null::uuid,
          jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 1)),
          0::numeric, null::text, null::uuid, '[]'::jsonb);
        perform public.record_invoice_payment(t_s2, jsonb_build_array(jsonb_build_object('payment_method_id', t_wallet, 'amount', 20)), gen_random_uuid());
        select b.id, b.lot_id into t_ben, t_lot from public.invoice_benefit_values b where b.invoice_id = t_inv;
        t_rev := public.reverse_credit_lot(t_lot, '477 check');
      elsif t_case = 4 then
        -- (d) paid in part: cancelled (its write-off takes the S$20 left and
        -- closes the released lot), reopened, paid in full; S1 refunded while
        -- paid opens it again (locked by the write-off, no reversal): an
        -- Owner's Move of it to F (answer D): F holds S$20 on a lot that is
        -- not locked, A's lot S$0 and still locked, the write-off's row as it
        -- was.
        perform public.cancel_invoice_recorded(t_inv, '477 check', gen_random_uuid());
        perform public.reopen_invoice(t_inv, '477 check', gen_random_uuid());
        perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)), gen_random_uuid());
        select pl.lot_id into t_lot from public.credit_package_progress_lots pl
          join public.customer_credit_lots l on l.id = pl.lot_id
         where pl.invoice_id = t_inv and l.is_locked order by pl.lot_id limit 1;
        select b.id into t_ben from public.invoice_benefit_values b where b.invoice_id = t_inv and b.lot_id = t_lot;
        if t_ben is null then raise exception '477: (d) no benefit row names the lot the Cancel closed'; end if;
      elsif t_case = 8 then
        -- (h) paid in full, S1 paid from its lot; a lock that no Owner's
        -- reversal and no release record explains (a stand-in: no function
        -- locks such a lot): the Move is still refused, "This credit lot is
        -- locked or reversed".
        select b.id, b.lot_id into t_ben, t_lot from public.invoice_benefit_values b where b.invoice_id = t_inv;
        if exists (select 1 from public.credit_package_progress_lots pl where pl.invoice_id = t_inv) then
          raise exception '477: (h) a package paid in full at once has a release record'; end if;
        update public.customer_credit_lots set is_locked = true, updated_at = now() where id = t_lot;
      else
        -- (e), (f) paid in part, S1 paid from the released lot; 328's repair
        -- of that lot (a stand-in with its own statements: what the lot holds
        -- reversed with a 'credit_lot_provenance_repair' row, locked, granted
        -- again as a lot its release record names in its place); (e) paid in
        -- full.
        select pl.lot_id into t_lot1 from public.credit_package_progress_lots pl where pl.invoice_id = t_inv;
        select * into t_l from public.customer_credit_lots where id = t_lot1;
        insert into public.customer_credit_ledger (wallet_id, customer_id, entry_type, category, amount, lot_id,
          source_type, source_record_id, store_id, effective_date, reason, created_by, approved_by)
        values (t_l.wallet_id, t_a, 'reverse', t_l.category, t_l.remaining_amount, t_lot1,
          'credit_lot_provenance_repair', t_lot1, t_l.store_id, public.sg_today(), '477 check', auth.uid(), auth.uid());
        update public.customer_credit_lots set remaining_amount = 0, status = 'reversed', is_locked = true, updated_at = now() where id = t_lot1;
        t_lot2 := public.grant_customer_credit(t_a, t_l.category, t_l.remaining_amount, 'credit_package', t_pk, t_store,
          t_l.effective_date, null, '477 check', '477 check', t_l.original_purchase_date, auth.uid(), t_l.usage_restrictions);
        insert into public.credit_package_progress_lots (lot_id, invoice_item_id, invoice_id, released_amount, replaces_lot_id)
        select t_lot2, pl.invoice_item_id, pl.invoice_id, 0, t_lot1 from public.credit_package_progress_lots pl where pl.lot_id = t_lot1;
        if t_case = 5 then
          perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)), gen_random_uuid());
        end if;
      end if;
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      -- S1 cancelled and refunded: S$20 back on the lot it was paid from.
      perform public.cancel_invoice_recorded(t_s1, '477 check', gen_random_uuid());
      perform public.refund_invoice_recorded(t_s1, jsonb_build_array(jsonb_build_object('amount', 20)),
        jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_s1 and p.entry_kind = 'receipt'
                                                             order by p.created_at limit 1), 'amount', 20)), '[]'::jsonb, '477 check', gen_random_uuid());
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      if t_case in (3, 4, 8) then
        insert into public.customers (full_name, phone)
        values ('477 Check Friend ' || t_case || ' ' || t_sfx, t_phones[case when t_case = 8 then 11 else t_case + 6 end]) returning id into t_f;
        t_err := null;
        begin
          perform public.transfer_invoice_unused_benefit(t_ben, t_f, t_store, '477 check', gen_random_uuid());
        exception when others then t_err := sqlerrm;
        end;
        if t_case = 3 and (t_err is not null
             or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_f) <> 20
             or exists (select 1 from public.customer_credit_lots where customer_id = t_f and is_locked)
             or (select remaining_amount from public.customer_credit_lots where id = t_lot) <> 0
             or not (select is_locked from public.customer_credit_lots where id = t_lot)
             or (select amount from public.customer_credit_ledger where id = t_rev) <> 60) then
          raise exception '477: (c) the Move of credit given back on a lot an Owner reversed was not made as tested (%)', coalesce(t_err, 'moved'); end if;
        if t_case = 4 and (t_err is not null
             or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_f) <> 20
             or exists (select 1 from public.customer_credit_lots where customer_id = t_f and is_locked)
             or (select remaining_amount from public.customer_credit_lots where id = t_lot) <> 0
             or not (select is_locked from public.customer_credit_lots where id = t_lot)
             or (select count(*) from public.customer_credit_ledger e where e.lot_id = t_lot and e.entry_type = 'adjust_decrease'
                  and e.source_type = 'invoice_cancel_released_credit' and e.amount = 20) <> 1) then
          raise exception '477: (d) the Move of credit given back on a lot a Cancel''s write-off locked was not made as tested (%)', coalesce(t_err, 'moved'); end if;
        if t_case = 8 and (t_err is distinct from 'This credit lot is locked or reversed'
             or exists (select 1 from public.customer_credit_lots where customer_id = t_f)) then
          raise exception '477: (h) the Move of a lot locked by nothing a record explains was not refused (%)', coalesce(t_err, 'moved'); end if;
        continue;
      end if;
      -- (e) settled: the S$20 on the old lot goes to A as one new lot that
      -- replaces the lot the records name (328's replacement), which a
      -- Cancel takes back; (f) not settled: one new lot that replaces the
      -- lot the release record reaches now, which its write-off reads.
      select coalesce(sum(remaining_amount), 0) into t_sum from public.customer_credit_lots where customer_id = t_a;
      if t_case = 5 then
        select b.lot_id into t_new from public.invoice_benefit_values b
         where b.invoice_id = t_inv and b.lot_id in (select x from unnest(public.credit_lot_chain(t_lot2)) x);
      else
        t_new := public.credit_lot_current(t_lot1);
      end if;
      if (select remaining_amount from public.customer_credit_lots where id = t_lot1) <> 0
         or (select remaining_amount from public.customer_credit_lots where id = t_lot2) <> 0
         or t_new is null or t_new = t_lot2
         or (select reassigned_from_lot_id from public.customer_credit_lots where id = t_new) <> t_lot2
         or (select customer_id from public.customer_credit_lots where id = t_new) <> t_a
         or (select remaining_amount from public.customer_credit_lots where id = t_new) <> 40
         or t_sum <> (case t_case when 5 then 100 else 40 end) then
        raise exception '477: (%) the credit given back on the lot 328''s repair replaced did not follow to the lot the records name (A %)', chr(96 + t_case), t_sum; end if;
      if t_case = 5 then
        perform public.cancel_invoice_recorded(t_inv, '477 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> 0 then
          raise exception '477: (e) Cancel left credit behind'; end if;
      end if;
    end loop;
    raise exception using errcode = 'P0477', message = '477: self-test done, undone';
  exception when sqlstate 'P0477' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
