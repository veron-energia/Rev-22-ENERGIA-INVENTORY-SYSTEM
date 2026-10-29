-- 476_part_paid_change_same_as_paid_in_full.sql
--
-- A PACKAGE PAID IN PART IS CHANGED TO ANOTHER CUSTOMER AS THE SAME PACKAGE
-- PAID IN FULL IS: A 'TRANSFER' CHANGE IS REFUSED ONCE ANY OF IT WAS USED,
-- AND MOVES IT WHEN NOTHING WAS; AFTER A 'KEEP' CHANGE ALL IT GIVES LATER
-- (ITS CREDIT AND BONUS, ITS VOUCHERS, ITS SALE RECORD AND SO ITS
-- COMMISSION) GOES TO WHOEVER HOLDS ITS BENEFITS, WITH THE LINES SOLD WITH
-- IT, WHILE A LINE A CORRECTION ADDED GOES TO THE INVOICE'S CUSTOMER WHO PAYS
-- FOR IT; AND THE PAY DIALOG SAYS WHO RECEIVES IT (473's NOT COVERED 1 and
-- 2, the review of 475 to 478; the Owner, 27 Oct 2026: "Same as
-- paid-in-full", answers A, B, C and E; 28 Oct 2026: the line grouping and
-- 'transfer' as built)
--
-- (The number 476 is this file's name, its errors' prefix, its self-test's
-- error code P0476 and its suite's; if it changes at commit, change it in
-- these places alone: the file name, the "476:" messages, P0476, the suite,
-- the page test, and the "-- 476 (the Owner" lines the suites find its
-- functions by.)
--
-- WHO FOUND IT
--
--   473's builders (its NOT COVERED 1 and 2, its suite's KNOWN TQn2, K1 and
--   K2, 26 Oct 2026); this file's first build and the review of 475 to 478
--   (27 Oct 2026: X1, a second line that released nothing; KAL, KAL1 and
--   KAP, a line a correction added; K1v, the rest of the sale; TQfix and
--   TQcru, refused though nothing was used; the Pay dialog), put to the
--   Owner with 476 to 478's questions; the review of 476 to 479 (28 Oct
--   2026: the part-payment commission of a settled package that falls back
--   to part-paid, G5, C3c, NOT COVERED 7; the Pay dialog silent on the
--   credit a reopened invoice gives back, and naming a Bonus and vouchers a
--   package may not have; a release counting money that paid for lines
--   already delivered, NOT COVERED 13). Reproduced for this file on copies
--   of production at 475 (e948504d, 1387 functions, 27 Oct 2026) with the
--   cases of this file's suite, section R: made-up records, the app's own
--   calls (the invoice form, its edit of an unpaid invoice and its
--   correction of a part-paid one adding a line, alone or in the same save
--   as the customer change; the Pay dialog, Record Payment in full or of an
--   amount, Cancel, Reopen, the invoice form's customer change with
--   'transfer' or 'keep' and its review summary, a customer merge, Correct
--   payment, an Owner's Move, the guided Refund in full, delete_customer,
--   an Owner's reversal as a direct call), each followed by what its commit
--   does, with the commission rows each settlement and part payment writes
--   (referrers set on the made-up customers, the rates set in the copy's
--   settings, the part-payment layer registered or not).
--
-- WHAT WAS WRONG
--
--   A Credit Package or Premium Bundle paid in part releases its paid credit
--   as the money comes in (327, 356: S$1 for each S$1 received; one lot per
--   payment, named by the release record credit_package_progress_lots), and
--   gives the rest of its paid credit, its Bonus, its vouchers and voucher
--   allowance and its sale record (which the commission reads) when it is
--   settled. Against the rule for the same package paid in full:
--   (1) The list of what a customer change can move (invoice_transferable_
--   benefits, which the change refuses on) read a lot holding nothing as
--   "Fully spent; it stays with the original customer" (nothing to move,
--   nothing blocking). Where all that was released was spent and more was
--   still to come, a 'transfer' change went through, moving nothing, and
--   the later payments gave the rest to the new customer: S$100 sold to A,
--   S$40 paid and spent on two S$20 sessions, 'transfer' to B, paid: B S$60,
--   A had used S$40 (TQn2); paid in full it is refused ("Paid credit 60.00
--   (Partly spent)"). The same with the Premium Bundle, the Bonus package,
--   two part payments, a merge, a Cancel and Reopen first, an Owner's
--   reversal (TQn2v, TQn2b, TQn2w, TQn2w2, TQn2m, TQn2r, TQn2x).
--   (2) After a 'keep' change (322: "Keep the benefits with who holds them
--   now ... Only the invoice's customer changes") the credit a later
--   payment released and what the settlement gave went to the invoice's new
--   customer, splitting the package: S$40 paid, 'keep' to B, paid: A S$40,
--   B S$60 (K1); the Bonus package (K1b: B S$70); the Premium Bundle (K1v:
--   A S$40, B S$100 and its 2 vouchers); two packages on one invoice, S$40
--   paid (the money goes to the credit lines one after another, so the
--   second released nothing): A S$40, B S$160 (X1), paid in full first: A
--   S$200. And with them (K1v, X4) the sale record, and so the commission:
--   with no affiliate on the invoice the new customer's referrer earned
--   it, where paid in full first the buyer's referrer does (the change
--   leaves the sale record with the buyer). With the part-payment
--   commission registered (357), the 'keep' change moved what the buyer's
--   referrer held for the package line to the new customer's referrer.
--   (3) This file's first build gave a line that released nothing to the
--   holder of what the invoice's other lines released, whatever the line:
--   also a line a correction added, before the change or after it (KAP,
--   KAL; KAL1 in the same save as the change), which the new customer pays
--   for: A S$200, B S$0, where the same with the first package paid in full
--   gives A S$100, B S$100 (KAPF, KALF, KALF1).
--   (4) A lot of credit released before full payment that holds less than
--   it was granted though nothing on it was used was read as "Partly spent"
--   (461's test for a lot no benefit row names: it holds all it was
--   granted), so a 'transfer' change was refused: the invoice's payment
--   corrected S$5 lower (the lot S$35 of S$40, nothing used: TQfix); S$40
--   paid, a session paid from it, Cancel, Reopen (S$20 released again on a
--   new lot), the session refunded (the lot Cancel closed open again,
--   locked, S$20 of S$40, nothing used: TQcru).
--   (5) The Pay dialog (Record Payment) did not say who receives a
--   package's credit; after a 'keep' change it is not the invoice's
--   customer. Nor, on a reopened invoice, who receives the credit the
--   payment that settles it gives back (the review of 476 to 479: 'keep' to
--   B, cancelled, S$20 refunded by line, reopened: B's S$20 gives A S$100,
--   the Reopen dialog named A, Record Payment nobody).
--   The money was right in every case (nothing given twice, the net payment
--   buys what the lots hold, Cancel takes it all back), but the package was
--   split between two customers, or kept from one, where paid in full it is
--   not.
--   Production, 27 Oct 2026 (read-only, as given to this builder): 6 release
--   records of packages paid in part, none cancelled; one package (S$15,000,
--   S$200 paid and used) whose released credit was all spent with more still
--   to be released: (1) applies to it (the header's query, 1).
--
-- THE OWNER'S ANSWERS
--
--   22 Oct 2026: credit follows a merge and a 'transfer' customer change; a
--   Move's recipient keeps what was moved; refunds paid back count as not
--   used. 24 Oct 2026 (462, 463, 470): a cancel or refund takes back what
--   the invoice gave from whoever holds it now; the customer holds exactly
--   what the net payment buys; nothing stranded on a lot no record names;
--   nothing paid twice; Correct payment keeps working. 26 Oct 2026 (471 to
--   473): the deadlock trade-off, S$1 owed back per S$1 held for credit
--   released before full payment, RX0/RX1 owed to nobody, held while a
--   reopening waits: accepted; a 'transfer' change of a partly spent package
--   is refused as "Partly spent". 27 Oct 2026, answering 473's NOT COVERED
--   1 and 2: "Same as paid-in-full" (a 'transfer' change refused once any of
--   it was used, with the paid-in-full words; with 'keep' the credit
--   released later goes to whoever holds the benefits). 27 Oct 2026, about
--   16:20 SGT, answering this file's first build and its review:
--   A. "Same as paid-in-full": after a 'keep' change of a part-paid
--      invoice, a package or bundle line sold together with the first one
--      (part of the original sale; it released nothing only because money is
--      applied line by line) goes to the original buyer (whoever holds the
--      benefits); a line added later by editing the invoice (a correction,
--      before or after the change: KAP, KAL, KAL1) goes to the invoice's
--      customer who pays for it, exactly as when the first package was paid
--      in full (KALF, KALF1, KAPF).
--   B. "All with the buyer": after such a 'keep' change, the Premium
--      Bundle's free vouchers and their allowance, any Credit Package reward
--      vouchers, the sale record and the commission follow the credit to the
--      buyer (the holder); when the invoice has no affiliate, the buyer's
--      referrer earns, as when the package was paid in full before the
--      change.
--   C. "Part-paid wrongly 'used'": a 'transfer' change of a part-paid
--      package is allowed when nothing was used (TQfix; TQcru, the lot
--      Cancel closed open again but locked), judging such a lot by what its
--      release record counts, in both the list and the change, so the change
--      really moves it (no split).
--   E. "Dialogs name the receiver": the Pay dialog / Record Payment says
--      which customer receives a package's credit when that is not the
--      invoice's customer. (E's Reopen dialog part is 478's; D is 477's; F,
--      refunds while sessions wait, is 479's.)
--   28 Oct 2026, about 10:15 SGT, answering this file's NOT COVERED 1 and 2,
--   both "as built":
--   (1) "Yes, as built": which lines were sold together, where answer A does
--      not say, is as this file reads it (NOT COVERED 1 (a) to (e)): an edit
--      before any money is part of the original sale (KAE); the lines one
--      edit added are one sale (KAT2); separate edits are separate sales,
--      and a package nobody has paid towards yet goes to whoever pays for it
--      (KAT3: A S$200, B S$100); an edit made after every payment was removed
--      counts as before any money; a line swapped to another package keeps
--      its sale.
--   (2) "Keep it": a 'transfer' change before full payment moves the sale
--      record and so the commission to the new customer (CKT: the new
--      customer's referrer earns); after full payment they stay with the
--      buyer (CKTF: the buyer's referrer), as this file leaves them (NOT
--      COVERED 2).
--   (The same day, for 477 and 478: an Owner's Move of Cancel-locked credit
--   covers copies a 'transfer' change, a merge or a reopening's payment made
--   (477, MVWt); the Reopen dialog's note names who receives all of its
--   credit, the credit reinstated after settlement included (478).)
--   No other business rule is changed by guessing.
--
-- WHAT THIS DOES (six functions changed and three added, whole texts; no
-- table, column, trigger or grant of an existing function changed)
--
--   * credit_line_sale_group(uuid) (new, the server's alone): which sale a
--     line was sold in (answer A's marker). 0: the invoice's own sale, the
--     lines it was made with and those an edit added before any money was
--     received; otherwise the revision_no of the correction that added the
--     line once money had been received or the invoice settled. Read from
--     invoice_revisions: correct_invoice is the only way a line is added to
--     an invoice that exists (update_invoice_internal, which it alone
--     calls), and before every edit of the lines it saves the lines as they
--     were ('items', every row with its id) and the invoice as it was
--     ('invoice': status, paid_amount, locked_at); a line keeps its id while
--     it stays. So the latest revision whose lines before lack the line is
--     the edit that added it.
--   * credit_line_benefits_holder(uuid) (new, the server's alone): whom all
--     a package line paid in part gives later goes to: the holder of what
--     it released before (its release records, each followed to the lot it
--     reaches now, credit_lot_current), by 462's rule (invoice_credit_live_
--     holder: the customer the latest change that took the benefits along
--     moved them to since that lot was made, then the record a merge kept;
--     never a deleted record); for a line that released nothing yet, the
--     holder of what the lines of its sale released (answer A: the
--     invoice's own sale, or one correction's lines). Null where nothing was
--     released yet by the line or its sale, or what was released is held by
--     more than one customer: the callers then give to the invoice's
--     customer, as before (a line a correction added: the customer who pays
--     for it).
--   * release_credit_package_paid_credit(uuid) (327/356's text): the credit
--     a payment releases (Record Payment, the Pay dialog, Correct payment
--     raising an amount, a correction moving money between lines, the
--     reopening of a cancelled package) goes to that holder, else the
--     invoice's customer.
--   * issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid) and
--     sell_premium_bundle(...) (355's texts): settled from an invoice line,
--     the package or bundle goes to that holder, else the customer it is
--     given (the invoice's): its paid credit not yet released and its Bonus,
--     its sale record (credit_package_sales / premium_bundle_sales
--     customer_id), a Credit Package's reward vouchers, a Premium Bundle's
--     vouchers chosen at the till and the allowance of those still to
--     choose (answer B). The commission reads the sale's customer
--     (earn_credit_package_commission, earn_premium_bundle_commission,
--     unchanged): with no affiliate on the invoice, the holder's referrer
--     earns, as when the package was paid in full before the change. Called
--     without a line (sell_credit_package_with_vouchers, the legacy 141
--     split) nothing changes; the stock of a bundle's vouchers is the
--     invoice's store's, as before.
--   * invoice_package_commission_preview(uuid) (357's text, the
--     part-payment commission layer's figure for a package line): a line not
--     settled is read as its holder's (credit_line_benefits_holder), as its
--     settlement will make its sale record, so the part-payment commission
--     it holds is for the referrer its settlement will pay; each line on its
--     own (before, the invoice's customer's referrer, read once). A settled
--     line is read as the invoice's customer's, as before 476, also where
--     its sale record is now the buyer's: so after a 'keep' change, once
--     settled, an invoice that falls back to part-paid (a line added, a
--     payment corrected lower) has that line's commission with the invoice's
--     customer's referrer until it is paid in full again (NOT COVERED 7).
--   * invoice_transferable_benefits(uuid) (473's text): two changes. (a) For
--     a package line paid in part, not settled, of an invoice neither
--     cancelled nor refunded, with credit still to be released, one of
--     whose release records reads as spent by 473's test while none of its
--     lots holds credit: one more row, "Paid credit <still to be released>",
--     not movable, blocking, "Partly spent" (TQn2's change is refused with
--     the paid-in-full words; its record_id is the line's). (b) Answer C: a
--     lot no benefit row of the invoice names that holds all the release
--     records whose lot it is now count as released (credit_lot_current;
--     the record no longer counts what a trim or a Cancel's write-off took
--     back), with no reopening waiting and the invoice neither cancelled
--     nor refunded, is untouched (movable, not blocking), as 461 judges a
--     lot a benefit row names; 473's test of the line's other releases still
--     blocks it where any of them was spent. The rest is 473's text.
--   * move_invoice_benefits_to_customer(uuid,uuid,uuid,text) (463's text):
--     the same test as (b) in the lots it moves, so a 'transfer' change
--     moves what the list says moves (TQfix: B S$35, then paid B S$100;
--     TQcru: B S$40, then paid B S$100). The lot is reissued to the new
--     customer as every lot is (its fields carried over, Cancel's lock
--     included).
--   * invoice_credit_receivers(uuid) (new; signed-in staff of the invoice's
--     store, 406's require_store_access, as the list): for the Pay dialog,
--     the invoice's package and bundle lines not settled whose credit (and
--     at settlement the rest) a payment gives to a customer other than the
--     invoice's, and that customer (its id and name); and ('reinstated') on
--     a reopened invoice, the credit the payment that settles it gives back
--     (invoice_reopen_benefits not applied) by each customer other than the
--     invoice's who receives it, read as apply_reopened_invoice_benefits
--     gives it and as the Reopen dialog reads it (478). The page reads it
--     with the invoice and says so under Record Payment (answer E; staff
--     are told what the payment will give): "Credit from <line> goes to
--     <name>, who holds its benefits, not to this invoice's customer. Any
--     Bonus or vouchers it gives once paid in full go to <name> too." (a
--     package may have neither), and "S$<n> of credit reinstated once this
--     invoice is paid in full goes to <name>, who holds the benefits, not
--     to this invoice's customer." (the Reopen dialog's word, 478)
--   On copies, after 476 (the suite, section A): TQn2 and its siblings
--   refused, nothing moved; K1 A S$100, B S$0; K2 A S$80 (S$20 used); K1b A
--   S$110; K1v A S$140 and the 2 vouchers, the sale record A's, the
--   commission A's referrer's (CK1v), also with the part-payment layer
--   registered (IK1, IK1m: A's referrer holds the part-payment commission
--   after the change); K1p (a part payment after the change) A S$60; KK A
--   S$100; TK B S$100; K1m K S$100; Kfix A S$100; K1cr A S$80; K1t, K1can,
--   K1mv the sale record A's; X1 A S$200; X2 B S$200; X4 A S$240 and the 2
--   vouchers; X5 A S$300; KAL, KAL1, KAP, KALp A S$100, B S$100 (as KALF,
--   KALF1, KAPF; CKAL: each referrer earns on its own line); KAE (a line an
--   edit added before any money) A S$200; KAT2 (two lines one correction
--   added) A S$300; TQfix and TQcru B S$35 and B S$40 once changed, B S$100
--   once paid. In every case 462's invariants hold and Cancel takes all the
--   invoice's credit back from whoever holds it. Controls, the same
--   before 476 and after it: nothing spent and a 'transfer' change (TQ00:
--   B S$100), a session refunded first (TQu), 'keep' then 'transfer' (KT:
--   C S$100), paid in full then 'keep' (KF: A S$100), 473's controls, and
--   changed while cancelled, then reopened and paid (TQn2cx, TQcr, TQcc: B
--   S$60, 473's NOT COVERED 3).
--
-- WHY THIS WAY
--
--   (1) and (4) in the list, as 473 does, so the refusal, its words and the
--   review summary come from one test, and the change makes the same test
--   on each lot it moves, so it never moves less than the list says (a
--   split) or more. By a row for the credit still to be released, because
--   that is what the same package paid in full holds on its lot; by what the
--   release record counts, because the record already counts what a trim,
--   a write-off or 471's hold took back as no longer released (473's test
--   reads it so), so only spending is left.
--   (2) and (3) in the three places that give a package line its credit
--   (and in the settlement, all of the rest), by one helper, so a payment,
--   a reopening and the settlement give to the same customer, by 462's
--   rule, the rule a reopening's give-back and credit given back follow.
--   The sale marker from the invoice's revisions, because nothing else
--   records it: invoice_items has no created_at, a timestamp would tie
--   within one transaction (a payment and a correction can be one save)
--   and can be out of order between two, while the revision's snapshot was
--   read under the invoice's lock with the lines it held. An edit before
--   any money is part of the sale the customer starts paying for (paid in
--   full at that payment, every line would be the buyer's); a correction's
--   lines were sold together with each other (paid in full they would be
--   the payer's alike), and with nothing else.
--   (B) by the sale record's customer, because the settlement's commission
--   already reads it and a paid-in-full package changed with 'keep' keeps
--   its sale record with the buyer: so no function that earns, re-earns,
--   takes back or pays out commission changes, and paid and unpaid
--   commission, payouts and their deductions stay with 357, 383, 384, 391,
--   410, 414's rules. Only the part-payment layer's figure for a package
--   line not settled (invoice_package_commission_preview) reads the same
--   holder, so what that layer holds for such a line is for the referrer its
--   settlement will pay; a settled line it reads as before (the invoice's
--   customer's), as for a package paid in full and then changed with
--   'keep' (NOT COVERED 7: reading it from the sale record would change
--   that rule too, for the Owner); its writer (sync_instalment_commissions)
--   is unchanged.
--   (E) a read of its own, so no function the money path pins changes for
--   the page (invoice_financial_position, invoice_wallet_availability); the
--   credit a reopened invoice gives back by the reads the Reopen dialog
--   makes (478), so the two dialogs name the same customer; "Any Bonus or
--   vouchers" in the page's words rather than a figure, so no reward rule
--   is read again for the note.
--   The other ways:
--   * moving the credit after the settlement gave it to the invoice's
--     customer (as a 'transfer' change reissues a lot): a grant and a
--     reissue on the new customer's wallet for every payment, and a second
--     place deciding the holder;
--   * recording at a 'keep' change whom it left the benefits with (a new
--     column or table): the holder rule already says it, by 462's rule,
--     through merges and later changes;
--   * a line's place in the money queue, or the release records' times,
--     against the first payment, to tell a line of the sale: the queue
--     changes with corrections, and times tie in one transaction;
--   * changing earn_credit_package_commission / earn_premium_bundle_
--     commission to read the holder: pinned by many migrations (383, 384,
--     391, 414, 452 to 458), and they would then disagree with the sale
--     record the reports read.
--
-- NOT CHANGED
--
--   * Pinned (below), unchanged: correct_invoice and update_invoice_internal
--     (they write the lines and the revisions the marker reads),
--     issue_credit_lines_for_invoice (it calls the two issuers with the
--     invoice's customer, as before), trg_create_therapy_on_paid,
--     preview_invoice_correction, capture_invoice_benefit_values (it names
--     the release lots and the sale's lots, whoever holds them), the
--     release record's readers and writers (trim, write-off, 328's repair,
--     reclaim), the holder rules (invoice_credit_live_holder,
--     invoice_benefits_holder), 472's forwarder, merge_customer_records,
--     transfer_invoice_unused_benefit (an Owner's Move refuses a locked lot,
--     as before: 477's answer D), the split issuers, sell_credit_package_
--     with_vouchers, the commission (earn_credit_package_commission,
--     earn_premium_bundle_commission, earn_invoice_commission, which leaves
--     credit lines out, reconcile_invoice_commissions, which earns the
--     sales' commission again from their records, sync_instalment_
--     commissions and invoice_instalment_commission_targets, the
--     part-payment layer, invoice_package_retained_commission_basis),
--     cancel_invoice_recorded, reopen_invoice (475's AFTER), the Reopen
--     dialog's preview (474's).
--   * Edge Functions, settings: no change. Pages (read from src): the
--     invoice form offers 'transfer' or 'keep' when the list has rows
--     (InvoicesPage.tsx), as before; its words for 'keep' ("Keep the
--     benefits with who holds them now ... Only the invoice's customer
--     changes") and the review summary's now hold for all a package gives
--     later; the refusal and the summary's blocked rows are the server's
--     words. One page change goes with this file: Record Payment says who
--     receives a package's credit when it is not the invoice's customer,
--     and who receives the credit a reopened invoice gives back once paid
--     in full (InvoicesPage.tsx, src/lib/invoices/creditReceivers.mjs;
--     DEPLOY ORDER 4).
--
-- NOT COVERED (for the Owner; 1 and 2 the Owner confirmed on 28 Oct 2026,
-- as built, and they stay here as the record of the rule; the suite checks
-- 1 to 4, 7, 9 and 13 as they are and prints them as KNOWN; 5, 6, 8, 10 to
-- 12 and 14 are read from the code)
--
--   1. (Confirmed by the Owner, 28 Oct 2026: "Yes, as built".) Which lines
--      were sold together (answer A's marker), where the Owner's words of 27
--      Oct do not say: (a) a line an edit added before any money was
--      received belongs to the invoice's own sale (KAE: A S$200, as paid in
--      full at that first payment); (b) lines one correction added once money
--      was received were sold together with each other (KAT2: two packages
--      added to a paid invoice, S$40 paid, 'keep' to B, paid: A S$300, as
--      paid in full), with nothing else; (c) lines two separate corrections
--      added, each once money was received, are two sales even where no money
--      reached either before the change: the one that released nothing goes
--      to the invoice's customer (KAT3: A S$200, B S$100; paid in full after
--      both corrections: A S$300); (d) an edit made after every payment was
--      removed again (nothing received, unpaid, never settled) counts as
--      before any money; (e) a line that kept its id but was swapped to
--      another package by a correction stays a line of its sale. The header's
--      query lists lines of (b) and (c) under 6 and 9.
--   2. (Confirmed by the Owner, 28 Oct 2026: "Keep it".) 'Transfer' and the
--      sale record: a package paid in full and then
--      changed with 'transfer' keeps its sale record (and, with no
--      affiliate, its referrer's commission) with the buyer
--      (move_invoice_benefits_to_customer moves no sale record); paid in
--      part, changed with 'transfer', then settled, the sale record is the
--      new customer's (the holder's), as before 476 (CKT: the new
--      customer's referrer earns). The same after a 'transfer' then a 'keep'
--      (TK). Not changed: answer B names 'keep', and the Owner kept this on
--      28 Oct 2026.
--   3. A package line whose released credit is held by more than one
--      customer (split before 476: a 'keep' change and then a part payment,
--      MK1p), or, for a line that released nothing, the lines of its sale:
--      no one holds its benefits, so all it gives later still goes to the
--      invoice's customer (MK1p: B S$60). The header's query lists them (3,
--      5): a data fix, or left as it is. Packages settled already and split
--      so are left as they are.
--   4. The holder is never a deleted record (462's rule): where the buyer
--      used everything released, was deleted and the package was then paid,
--      all of it goes to the invoice's customer (Kdel: B S$60).
--   5. The list is read before the change locks the lots, as 473's NOT
--      COVERED 4: a payment or a session committing in that moment is read
--      by the next change. The mover reads each lot again once locked.
--   6. A payment, a reopening or a correction still open when 476 commits
--      gives on the text it started with. A form, review summary or Pay
--      dialog open on a screen shows the old answer until opened again; the
--      server decides again on save or payment. Part-payment commission a
--      'keep' change moved to the new customer's referrer before 476 moves
--      back at the invoice's next sync (taken back where unpaid; where paid
--      out, recovered from that referrer's later commission by 357 and 410's
--      rules); the header's query lists such lines (8).
--   7. The part-payment layer (registered in production: instalment_
--      commission_from 2026-09-25, as read on 3 Oct 2026, not read again for
--      this file) reads a settled package line as the invoice's customer's,
--      as before 476, and the rows it writes name the invoice's customer as
--      buyer (sync_instalment_commissions). Not as before on one path: a
--      package paid in part, changed with 'keep' and then settled has its
--      sale record and its commission with the buyer (answer B: RA S$4.50);
--      if the invoice then falls back to part-paid (Edit Invoice adding a
--      line, Correct payment lowering an amount), the layer comes back on,
--      takes back the settlement's commission from the buyer's referrer and
--      gives the line's share to the invoice's customer's referrer, while
--      the credit, the vouchers and the sale record stay with the buyer
--      (G5: RB S$2.25 for the line and S$2.25 for the added one, RA S$0;
--      C3c: RB S$4.28; C5, two packages: RB S$8.78; L4, the Premium Bundle:
--      RB S$6.08). Paid in full again, the buyer's referrer has it back (G5p:
--      RA S$4.50 and RB S$4.50 for the added line; C3cp: RA S$4.50). A
--      payout in that window pays the invoice customer's referrer, and that
--      is taken back from their later commission as a deduction (357, 410's
--      rules; P1: RB paid S$4.28 and then owing it back). Before 476 the
--      same steps paid the invoice customer's referrer throughout (the sale
--      record was theirs). A package paid in full and then changed with
--      'keep' does the same, before 476 and after it (G5F, C3cF), so on this
--      path 476 makes the part-paid package the same as the paid-in-full one
--      (answer A). Reading a settled line's buyer from its sale record
--      (credit_package_sales / premium_bundle_sales of the line) would keep
--      the buyer's referrer in that window for both, but it changes the
--      paid-in-full rule too: for the Owner. The suite checks these cases
--      (K7).
--   8. The customer page lists the buyer's package with "received from
--      another customer" once the invoice's customer is someone else
--      (customer_credit_balances' 'received'), as it already does for the
--      same package paid in full and then changed with 'keep'; the refund
--      blockers of a credit purchase (credit_purchase_refund_blockers) read
--      the invoice's customer for claimed reward units, as for that package.
--   9. TQcru's lot moves to the new customer still locked by Cancel's
--      write-off (every reissue carries the lot's fields), as it was locked
--      for the buyer: it can be spent, but an Owner's Move of it is
--      refused ("locked or reversed") until 477 (answer D) allows it.
--   10. After settlement a lot a benefit row names is judged by 461's test,
--      as before: the release record no longer decides once the line is
--      settled.
--   11. The Pay dialog's note is read with the invoice; a payment recorded
--      elsewhere meanwhile (another tab) can change who receives the next
--      one, as for every figure on that screen until it is opened again.
--   12. The Reopen dialog's part of answer E is 478's (it names who receives
--      all of the dialog's credit, the vouchers and the reward units: the
--      Owner, 27 and 28 Oct 2026), and a refund while sessions wait is 479's
--      (answer F).
--   13. Not caused by 476 (the same before it and after it, on copies of
--      production at 475): a Credit Package or Premium Bundle line added by a correction
--      to an invoice already paid in full releases at once credit for the
--      money that paid for the lines already delivered, because
--      credit_package_money_toward_line counts only other credit lines ahead
--      of it (vouchers issued, sessions created and goods handed over at the
--      earlier full payment are not counted). KV13: 2 vouchers sold for S$60,
--      paid, a S$100 package added: part-paid (S$100 owing), the customer
--      holds S$60 of credit and the 2 vouchers for S$60 net; paid, S$100 of
--      credit and the vouchers for S$160. Spend that credit and then use
--      the guided Cancel: its plan refunds the S$60 against the delivered
--      line and the package line gets nothing, so the customer is paid back
--      S$60 and keeps what the credit bought (the review: S$60 paid back,
--      three sessions bought with the credit kept, S$0 net). And a refund by
--      line of the delivered line does not trim the credit released for it
--      (the money held falls, the credit stays). 478's
--      Reopen dialog counts the same way (it shows what happens). For the
--      Owner: count delivered lines ahead of credit lines (here, in the
--      Reopen dialog and in the guided plans), or refuse adding a credit line
--      by correction to an invoice whose other lines were delivered (a new
--      invoice instead). The correction's review summary does not say that
--      credit becomes usable at once.
--   14. The Pay dialog names who receives credit (lines not settled, and the
--      credit a reopened invoice gives back), not who receives the therapy
--      sessions or voucher units a reopened invoice's settling payment
--      reinstates (after a 'keep' change while they wait, 479: the holder);
--      those are not credit (answer E's words), for the Owner.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the texts are the tested ones (their AFTER md5s); the six functions
--     are all at their BEFORE (473's list; 463's mover; 327/356's release;
--     355's issuers; 357's preview) and the three new ones absent (all
--     replaced, the new ones made), or all at their AFTER with the new ones
--     at their AFTER (left alone); anything else, a mix included, is
--     refused; no other function takes their names; so a second run changes
--     nothing;
--   * the functions it relies on are as read on a copy of production at 475
--     (pinned, below): what the nine call and who calls them, the holder
--     rules and what writes what they read, what adds invoice lines and
--     writes the revisions the marker reads (correct_invoice,
--     update_invoice_internal; no page may write a revision), the release
--     record's readers and writers, the settlement and the commission it
--     earns (and the part-payment layer), a merge, an Owner's Move, 472's
--     forwarder, 475's reopening; the trigger that releases and settles on
--     invoices is as read; the columns read have these types; who calls the
--     changed functions, who grants credit and makes lots, who writes the
--     release record, the revisions, the invoice lines and the sale
--     records, who calls update_invoice_internal, and what reads the
--     change's Audit Log row, as read (a new way would need the same care);
--   * on the first run nothing is refused for the data (476 needs no
--     decision before it goes in); the invoices of the header's query are
--     named in a notice (invoice numbers only): 1 (a 'transfer' change now
--     refused), 2, 4, 6 and 8 (what is given later now goes to the holder),
--     7 (a 'transfer' change now moves the lot), 3 and 5 (for the Owner), 9
--     (unchanged);
--   * who may call the six is as read, compared as sets, and kept; of the
--     new ones, credit_line_sale_group and credit_line_benefits_holder are
--     the server's alone (revoked from public, anon and signed-in staff; the
--     service role), as 460 and 462 made theirs; invoice_credit_receivers
--     is signed-in staff's (the Pay dialog reads it) and the service role's,
--     not anon's, and refuses anyone but active staff of the invoice's store
--     (require_store_access, 406), as the list does;
--   * afterwards: the AFTER md5s, the grants as tested.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0476, so it leaves no row): a made-up Owner, store, cash method, S$100
--   package, S$100 + S$10 package, unlimited voucher (S$30 at the store),
--   S$140 Premium Bundle (S$100 + S$40 and one reward voucher, chosen at the
--   till), S$20 session and twenty customers (fictional ACMA phones no
--   customer has; two of them the referrers of case e), nine times, sold to
--   A, S$40 paid: (a) two sessions paid from it, a 'transfer' change to B:
--   refused with "Paid credit 60.00 (Partly spent)", A S$0, B nothing, the
--   invoice still A's; (b) the same, 'keep' to B, paid in full: A S$60, B
--   nothing; (c) 'keep' to B, S$20 more paid, then paid in full: A S$100; (d)
--   the Bonus package, 'keep', paid: A S$110; (e) the Premium Bundle, A and B
--   each referred, 'keep', paid: A S$140 and the voucher, the sale record
--   A's, no commission row for B's referrer; (f) a control: 'transfer' to B,
--   paid: B S$100, A S$0; (g) two S$100 packages on one invoice (the S$40
--   released on the first only), 'keep' to B: the Pay dialog's read names A
--   for both lines; paid: A S$200, B nothing; (h) 'keep' to B, a second
--   package added by a correction: the Pay dialog's read names A for the
--   first line alone; paid: A S$100, B S$100; (i) the S$40 payment corrected
--   to S$35, 'transfer' to B: B S$35, A S$0; paid: B S$100.
--   Its credit ledger rows draw entry numbers (a sequence, which an undone
--   transaction does not give back: a gap, as 443 to 475's self-tests).
--   Locks: the nine functions' catalogue rows to the end of the apply, and
--   the rows the self-test writes and undoes; no table is locked against
--   ordinary writes. The self-test takes the commission advisory locks
--   (through its settlements, customer changes and corrections) and new
--   invoice numbers, so it waits for any app cancel, refund,
--   commission-writing payment or invoice creation still open, and those
--   wait for it, for under a second. If one stays open longer than the 5 s
--   lock timeout, or an invoice created at the same moment takes the
--   self-test's invoice number, the apply stops, changing nothing, and can
--   be run again. A payment still open when 476 commits gives on the old
--   text (NOT COVERED 6). Apply at a quiet time.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (475 in, 27 Oct 2026: e948504d, 1387 functions; the grant
--   list 381ef69c; head 20261027082304) -> 476. 476 pins 475's
--   reopen_invoice (its AFTER) and changes invoice_transferable_benefits
--   (473 wrote it; 463 pins it), move_invoice_benefits_to_customer (463
--   wrote it; 470 to 473 pin it), release_credit_package_paid_credit (471 to
--   473 pin it), issue_credit_package, sell_premium_bundle (463 pins it) and
--   invoice_package_commission_preview (357 wrote it): a re-run of 463 or
--   470 to 474 refuses already at 475 (their pin of reopen_invoice, 475's
--   AFTER) and after 476 too (473's now first on its pin of the mover),
--   changing nothing; 475's re-run leaves all alone (it pins none of the six).
--   All are applied, so nothing is lost. 477, 478 and 479 (built in the
--   same batch) pin this file's AFTERs and were checked on this fingerprint
--   (28 Oct 2026: 476's Pay dialog read changed once more, the credit a
--   reopened invoice gives back; none of them pins it); if anything else
--   goes in first, work the fingerprints out again and check that it
--   changes none of the functions pinned below.
--   1. Before it, read only (invoice numbers and counts only; production was
--      not read for this file). 476 refuses no state; this lists whose answer
--      changes (1, 2, 4, 6, 7, 8), what needs the Owner (3, 5) and what stays
--      as it is (9). On the production facts known (27 Oct 2026: 6 part-paid
--      release records, none cancelled; one package whose released credit
--      was all spent with more to be released) 1 lists that invoice; 2 to 9
--      may list invoices:
--     with
--     -- the release records of package lines not settled, each followed to
--     -- the lot it reaches now (credit_lot_current), whom 462's rule says
--     -- holds it, and whether it reads as spent (473's test)
--     pre as (
--       select pl.invoice_id, pl.invoice_item_id, c.customer_id, c.remaining_amount,
--              public.invoice_credit_live_holder(pl.invoice_id, c.customer_id, c.created_at) as holder,
--              pl.released_amount > 0 and coalesce(case when c.status = 'active' then c.remaining_amount end, 0) < pl.released_amount as spent
--         from public.credit_package_progress_lots pl
--         join public.invoices i on i.id = pl.invoice_id and i.deleted_at is null
--         join public.invoice_items it on it.id = pl.invoice_item_id and it.credit_issued_at is null
--         join public.customer_credit_lots c on c.id = public.credit_lot_current(pl.lot_id)
--        where not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = any (public.credit_lot_chain(pl.lot_id)))),
--     -- each package or bundle line's sale, as 476's credit_line_sale_group works
--     -- it out (0: the invoice's own sale; else the revision of the correction
--     -- that added it once money had been received)
--     grp as (
--       select it.invoice_id, it.id as invoice_item_id,
--              coalesce((select case when coalesce(r.snapshot->'invoice'->>'status', '') in ('draft', 'unpaid')
--                                         and coalesce((r.snapshot->'invoice'->>'paid_amount')::numeric, 0) = 0
--                                         and r.snapshot->'invoice'->>'locked_at' is null
--                                    then 0 else r.revision_no end
--                          from public.invoice_revisions r
--                         where r.invoice_id = it.invoice_id and jsonb_typeof(r.snapshot->'items') = 'array'
--                           and not (r.snapshot->'items' @> jsonb_build_array(jsonb_build_object('id', it.id)))
--                         order by r.revision_no desc limit 1), 0) as sale
--         from public.invoice_items it
--         join public.invoices i on i.id = it.invoice_id and i.deleted_at is null
--        where it.line_kind::text in ('credit_package', 'premium_bundle')),
--     -- the unsettled package and bundle lines that released nothing yet, not
--     -- split, of an invoice neither cancelled nor refunded
--     bare0 as (
--       select it.invoice_id, it.id as invoice_item_id, g.sale
--         from public.invoice_items it
--         join grp g on g.invoice_item_id = it.id
--         join public.invoices i on i.id = it.invoice_id and i.status::text not in ('cancelled', 'refunded')
--        where it.credit_issued_at is null
--          and it.credit_split_allocation_id is null and it.bundle_split_allocation_id is null
--          and not exists (select 1 from public.invoice_credit_splits sp where sp.invoice_item_id = it.id)
--          and not exists (select 1 from public.credit_package_progress_lots x where x.invoice_item_id = it.id)),
--     -- whom the release records of the lines sold with such a line name (each
--     -- followed to the lot it reaches now), by 462's rule
--     bare as (
--       select b.invoice_id, b.invoice_item_id, i.customer_id as invoice_customer,
--              count(distinct h.holder) as holders, count(*) filter (where h.holder is null) as no_holder,
--              (array_agg(h.holder) filter (where h.holder is not null))[1] as holder
--         from bare0 b
--         join public.invoices i on i.id = b.invoice_id
--         join grp o on o.invoice_id = b.invoice_id and o.invoice_item_id <> b.invoice_item_id and o.sale = b.sale
--         join public.credit_package_progress_lots pl on pl.invoice_item_id = o.invoice_item_id
--         join public.customer_credit_lots c on c.id = public.credit_lot_current(pl.lot_id)
--         cross join lateral (select public.invoice_credit_live_holder(pl.invoice_id, c.customer_id, c.created_at) as holder) h
--        group by b.invoice_id, b.invoice_item_id, i.customer_id),
--     -- per line with releases of its own: its holders, whether a release reads as
--     -- spent or a lot of it holds credit, the credit still to be released
--     own as (
--       select p.invoice_id, p.invoice_item_id, i.customer_id as invoice_customer, i.status::text as status,
--              count(distinct p.holder) as holders, count(*) filter (where p.holder is null) as no_holder,
--              (array_agg(p.holder) filter (where p.holder is not null))[1] as holder,
--              bool_or(p.spent) as spent, bool_or(p.remaining_amount > 0) as holding,
--              round(public.credit_line_paid_entitlement(p.invoice_item_id)
--                    - public.credit_package_released_paid_credit(p.invoice_item_id), 2) as to_come
--         from pre p
--         join public.invoices i on i.id = p.invoice_id
--        group by p.invoice_id, p.invoice_item_id, i.customer_id, i.status),
--     -- the lines whose later credit, Bonus, vouchers, sale record and commission
--     -- go to a holder other than the invoice's customer from 476: with releases
--     -- of their own (held by one customer), or with none, sold with lines whose
--     -- releases are (one customer); with what that changes for the vouchers and
--     -- the commission
--     moved as (
--       select x.invoice_id, x.invoice_item_id, x.holder, x.invoice_customer, x.why,
--              -- its settlement gives vouchers (a Premium Bundle's, a Credit Package's reward vouchers
--              -- as issue_credit_package counts them)
--              (it.line_kind::text = 'premium_bundle' and coalesce(pb.free_voucher_qty, 0) > 0
--               or it.line_kind::text = 'credit_package' and coalesce(pk.grants_reward, false)
--                  and floor(coalesce(pk.customer_price, 0)
--                            / nullif(coalesce(pk.reward_qualifying_amount,
--                                              (public.legacy_lowest_rule(i.store_id, public.sg_today())).qualifying_amount, 994), 0)) >= 1) as vouchers,
--              -- the invoice has no affiliate (none chosen, not cleared) and the holder's referrer is not
--              -- the invoice's customer's: whose referrer earns changes
--              i.affiliate_id is null and not coalesce(i.affiliate_selection_explicit, false)
--                and (select c.referred_by from public.customers c where c.id = x.holder)
--                    is distinct from (select c.referred_by from public.customers c where c.id = x.invoice_customer) as referrer
--         from (select o.invoice_id, o.invoice_item_id, o.holder, o.invoice_customer, 2 as why from own o
--                where o.holders = 1 and o.no_holder = 0 and o.holder is distinct from o.invoice_customer
--               union all
--               select b.invoice_id, b.invoice_item_id, b.holder, b.invoice_customer, 6 from bare b
--                where b.holders = 1 and b.no_holder = 0 and b.holder is distinct from b.invoice_customer) x
--         join public.invoices i on i.id = x.invoice_id
--         join public.invoice_items it on it.id = x.invoice_item_id
--         left join public.premium_bundles pb on pb.id = it.premium_bundle_id
--         left join public.credit_packages pk on pk.id = it.credit_package_id),
--     -- the package lines whose credit lots (settled: those its benefit rows name,
--     -- not what an Owner moved to someone else; not settled: its release records'
--     -- lots now) are held by more than one customer, merges followed
--     split as (
--       select x.invoice_id, x.invoice_item_id
--         from (select b.invoice_id, b.invoice_item_id, l.customer_id
--                 from public.invoice_benefit_values b
--                 join public.customer_credit_lots l on l.id = b.lot_id
--                 join public.invoice_items it on it.id = b.invoice_item_id and it.line_kind::text in ('credit_package', 'premium_bundle')
--                where not public.invoice_benefit_moved_to_other(b.id)
--               union all
--               select p.invoice_id, p.invoice_item_id, p.customer_id from pre p) x
--         join public.invoices i on i.id = x.invoice_id and i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
--        group by x.invoice_id, x.invoice_item_id
--       having count(distinct public.invoice_benefits_holder(x.invoice_id, x.customer_id, 'infinity')) > 1),
--     -- lots of credit released before full payment that no benefit row names,
--     -- holding less than they were granted but all that the release records
--     -- whose lot they are now count as released (nothing on them used), of an
--     -- invoice neither cancelled nor refunded with no reopening waiting
--     relunspent as (
--       select pl.invoice_id, pl.invoice_item_id, c.id as lot_id
--         from public.credit_package_progress_lots pl
--         join public.invoices i on i.id = pl.invoice_id and i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
--         join public.customer_credit_lots c on c.id = public.credit_lot_current(pl.lot_id)
--        where c.status = 'active' and c.remaining_amount > 0 and c.remaining_amount < c.original_amount
--          and not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = any (public.credit_lot_chain(pl.lot_id)))
--          and not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = c.id and bv.invoice_id = pl.invoice_id)
--          and not exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = pl.invoice_id and q.applied_at is null)
--        group by pl.invoice_id, pl.invoice_item_id, c.id, c.remaining_amount
--       having c.remaining_amount >= sum(pl.released_amount) and sum(pl.released_amount) > 0),
--     found(reason, invoice_id, n) as (
--       select '1 changes: a package paid in part, not settled, of an invoice neither cancelled nor refunded, whose released credit was spent with nothing left on its lots and more still to be released; a ''transfer'' customer change passed (moving nothing, the later payments giving the rest to the new customer), from 476 it is refused as "Partly spent", as for the same package paid in full (the count is of lines)', o.invoice_id, count(*)
--         from own o
--        where o.status not in ('cancelled', 'refunded') and o.to_come > 0 and o.spent and not o.holding
--        group by o.invoice_id
--       union all
--       select '2 changes: a package paid in part, not settled, whose released credit is held by one customer other than the invoice''s customer (a ''keep'' change, or a ''transfer'' and then a ''keep''): its next payments, its reopening and its settlement gave the invoice''s customer its credit (paid, and the Bonus), its vouchers and allowance and its sale record, from 476 that holder (the count is of lines)', m.invoice_id, count(*)
--         from moved m where m.why = 2
--        group by m.invoice_id
--       union all
--       select '3 for the Owner (not changed by 476: NOT COVERED 3): a package paid in part, not settled, whose released credit is held by more than one customer (split before 476): all it gives later still goes to the invoice''s customer; a data fix, or left as it is (the count is of lines)', o.invoice_id, count(*)
--         from own o
--        where o.holders > 1
--        group by o.invoice_id
--       union all
--       select '4 changes: of 2 and 6, its settlement gives vouchers (a Premium Bundle''s vouchers and allowance, a Credit Package''s reward vouchers): from 476 to the holder, before to the invoice''s customer (the count is of lines)', m.invoice_id, count(*)
--         from moved m where m.vouchers
--        group by m.invoice_id
--       union all
--       select '5 for the Owner (not changed by 476: NOT COVERED 3): a package line, of an invoice neither cancelled nor refunded, whose credit lots are held by more than one customer (split before 476 by a ''keep'' change before full payment, or by a ''transfer'' change of a partly spent package before 473 or 476): a data fix, or left as it is (the count is of lines)', s.invoice_id, count(*)
--         from split s
--        group by s.invoice_id
--       union all
--       select '6 changes: a package or bundle line paid in part, not settled, that released nothing yet, sold with lines (the invoice''s own sale, or one correction''s lines) whose released credit is held by one customer other than the invoice''s customer: its payments and settlement gave the invoice''s customer all of it, from 476 that holder (the count is of lines)', m.invoice_id, count(*)
--         from moved m where m.why = 6
--        group by m.invoice_id
--       union all
--       select '7 changes: a lot of credit released before full payment that holds less than it was granted though nothing on it was used (a payment corrected lower; a Cancel, a reopening and a refund paid back onto it): a ''transfer'' customer change was refused as "Partly spent", from 476 it moves the lot where nothing else of the line was used (the count is of lots)', r.invoice_id, count(*)
--         from relunspent r
--        where not exists (select 1 from pre p where p.invoice_item_id = r.invoice_item_id and p.spent)
--        group by r.invoice_id
--       union all
--       select '8 changes: of 2 and 6, the invoice has no affiliate and the holder''s referrer is not the invoice''s customer''s: from 476 the holder''s referrer earns its commission at settlement, and the part-payment commission it holds already moves to them at the next sync (the count is of lines)', m.invoice_id, count(*)
--         from moved m where m.referrer
--        group by m.invoice_id
--       union all
--       select '9 not changed (the Owner''s answer A): a package or bundle line a correction added once money had been received, not settled, that released nothing yet, on an invoice whose other lines'' released credit is held by someone other than the invoice''s customer: it goes to the invoice''s customer who pays for it, as before 476 (the count is of lines)', b.invoice_id, count(*)
--         from bare0 b
--         join public.invoices i on i.id = b.invoice_id
--        where b.sale > 0
--          and not exists (select 1 from bare x where x.invoice_item_id = b.invoice_item_id)
--          and exists (select 1 from pre p where p.invoice_id = b.invoice_id and p.holder is distinct from i.customer_id)
--        group by b.invoice_id)
--     select f.reason, i.invoice_no, f.n
--       from found f join public.invoices i on i.id = f.invoice_id
--      order by f.reason, i.invoice_no
--      (The suite runs this same text on its cases' states before 476 and
--      checks what it lists.)
--   2. Dry run on a copy of production as it is then (475 applied to it):
--      work out its fingerprint and grant list first (they must be the
--      BEFORE figures below, or be worked out again on that copy); apply this
--      file twice; the first run ends at the AFTER fingerprint below, the
--      second changes nothing ("left alone"); and the suite, with the earlier
--      suites below.
--   3. Apply (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself.
--   4. The page change (src/pages/InvoicesPage.tsx,
--      src/lib/invoices/creditReceivers.mjs and .d.mts; its test
--      scripts/invoices/tests/credit-receivers-476.test.mjs) ships with it,
--      deployed right after 476 is applied. Either order is safe: before
--      476 the page's read of invoice_credit_receivers fails and Record
--      Payment shows no note, as today; 476 without the page gives the
--      credit to the holder with no note, as the form's 'keep' words say.
--   Afterwards (checked on copies of production at 475, 27 Oct 2026): a
--   re-run of 463 or 470 to 474 refuses on its pin of reopen_invoice (as at
--   475; 473's first on its pin of the mover), each changing nothing; 475's
--   leaves all alone; 476's own leaves all alone.
--   The suites that read what 476 changes, where it is in (-v nomig=1):
--   part-paid-package-change-partly-spent-473 (its KNOWN TQn2, K1 and K2,
--   and its N1, checked as 476 settles them; its version check takes 476's
--   AFTER of the list), reopen-follows-customer-460 (its check of the list
--   leaves 476's parts out, as it does 461's), customer-change-refunded-461,
--   move-merge-leftovers-462 and change-store-moves-bundle-vouchers-463
--   (their version checks take 476's AFTERs of the list and the mover; no
--   case of theirs is a package paid in part, so every case ends as
--   before), function-grants (the two new helpers among the server's own).
--
-- BEFORE (a copy of production at 475, 27 Oct 2026; md5 of
-- pg_get_functiondef with search_path public)
--   changed
--   invoice_transferable_benefits(uuid)                               a2332a22fe9975667e848de0d1e4480b  (473's AFTER)
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)            c01606c84ee13ddcd88c15521d6d9aed  (463's AFTER)
--   release_credit_package_paid_credit(uuid)                          530521c100163445e5a0b99799fbcccc  (327/356's, as 471 to 473 pinned it)
--   issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid)            cc3737e39249ea9ebfed729a1e221f84  (355's)
--   sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid) 3cee8de4ce6361744a9d57b172e84563  (355's, as 463 pinned it)
--   invoice_package_commission_preview(uuid)                          906791a4de678bd2d1dcac59838d17f1  (357's)
--   credit_line_sale_group(uuid)                                      (absent: added)
--   credit_line_benefits_holder(uuid)                                 (absent: added)
--   invoice_credit_receivers(uuid)                                    (absent: added)
--   relied on, not changed (pinned)
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                       04d647e13e9424a9375942e5812e91a2
--   update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean) 1f034561a461bdb46a1e6274e0d04606
--   preview_invoice_correction(uuid,jsonb)                            f26752231c100461e11caddc03c98a33
--   invoice_benefit_unused_elsewhere(uuid)                            d35d7c8ae7187985ea64f8a5c38a7d79
--   invoice_benefit_moved_to_other(uuid)                              7016bed898e1bbe9d0ac4a05037d07c2
--   invoice_benefit_moved_from_spent(uuid)                            901fde963b051cfd93fcd9f7dab7149e
--   invoice_credit_lot_ids(uuid)                                      50346a2e9aea50b31d4207c43b2f197c
--   credit_lot_chain(uuid)                                            556e725784154cbffc23d3ad900f9366
--   credit_lot_current(uuid)                                          d48fb24e6eb9733d7f867e42fa703e7b
--   credit_lot_ancestry(uuid)                                         52b3cae789b6b52a12bb2f798af40cbe  (the Pay dialog's read of the credit to reinstate)
--   require_store_access(uuid)                                        f9332fd2f0092337d64501d8a647c23f
--   invoice_line_label(uuid)                                          a9ba8c6cb4632087e3e9ac297d998ff5
--   invoice_own_voucher_ids(uuid)                                     ee0202627b9500dcbad103d3ade2401f
--   entitlement_claimed_qty(uuid)                                     89b08265d5303e890569e953d83d2440
--   capture_invoice_benefit_values(uuid)                              d5e061945c2921a1af86f8c99a349e98
--   record_invoice_benefit_values(uuid,jsonb,text)                    931af0352136ab39689af21a993f67b3
--   credit_package_released_paid_credit(uuid)                         6b27388462747e3c13f3da0b9ad165c0
--   credit_line_paid_entitlement(uuid)                                da2404a1db281b46a44231bd071a069a
--   credit_package_money_toward_line(uuid)                            798c2d67d55bb1d140232ff06ffb1034
--   credit_package_bonus_amount(uuid)                                 45031fdc18cdc6ed4a3e2a8275a8cbd5
--   invoice_item_external_value(uuid)                                 e1d12f5bf03e92e669d139f0405362af
--   trim_released_paid_credit(uuid,text,boolean)                      14ded4342c3e65eb98547d224263519f
--   writeoff_released_credit_on_close(uuid,text,text)                 284a89cfb965e8028136b5f8a4f2bf08
--   repair_credit_package_progress_lots()                             ebd2a1a9f8ce7a9c1c272168b30b5ce3
--   reclaim_released_credit_of_removed_lines(uuid,jsonb,text)         823cd6a96c813b43bf2767dc1644e943
--   invoice_credit_live_holder(uuid,uuid,timestamp with time zone)    a5692590ef3e8a7a7dd7e8ff7cfa9568
--   invoice_benefits_holder(uuid,uuid,timestamp with time zone)       55995ff6e1ffd4a1172cb930512a34b0
--   grant_customer_credit(uuid,text,numeric,text,uuid,uuid,date,text,text,text,date,uuid,jsonb) ac0de5530624ee533aacf93aec389910
--   ensure_customer_wallet(uuid)                                      8ef18daebbbe3c12f2024290ea8416e8
--   issue_credit_lines_for_invoice(uuid)                              303f45e12e88b8de58e95aa0f877b875
--   trg_create_therapy_on_paid()                                      012ae4e305b9870fa5596f740c0427b9
--   sell_credit_package_with_vouchers(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid) 2d1e5eaf623ea56835c528df8ad418e9
--   issue_credit_package_invoice_item(uuid)                           08caec99c467334527af99eee5e6b00e
--   issue_premium_bundle_invoice_item(uuid)                           9981515e45c3e79a41d36f96acbf000b
--   validate_bundle_voucher_selection(uuid,uuid,jsonb)                16e707758a4d771c49c403ef8983570f
--   earn_credit_package_commission(uuid)                              13ce59fd892c027338a41de4113ae55d  (383)
--   earn_premium_bundle_commission(uuid)                              b75ffbea70fd020e75d1ddf4f7b06ba1  (383)
--   earn_invoice_commission(uuid)                                     6156b2e1ee51da5146a5a7acc16091ce
--   invoice_package_retained_commission_basis(text,uuid,numeric)      74b5e488d656af58a2e3f41c58eb365f
--   package_commission_classification()                               08db9563fd4213315b16b891a53ead7b
--   reconcile_invoice_commissions(uuid,text)                          3c267728e215d17ebeb9cfe9cb7db47c
--   sync_instalment_commissions(uuid,text,date,boolean,boolean)       88d7b122778801a0d5eea0b6dd8395b7  (357)
--   invoice_instalment_commission_targets(uuid)                       dc47c3c7b9e41d67b89713fce2a4b480  (357)
--   invoice_instalment_commission_active(uuid)                        1cfc14db26aaef668cee010fadbddfe3  (357)
--   transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)         7aebd7120bc3928db46df0941cb20889
--   merge_customer_records(uuid,uuid,text,uuid)                       ba05c2b1fb4c0e14d369c01d06a635b0
--   credit_given_back_follows(uuid)                                   f2a7a4d1ca28f0865b14e3f1e5e02bbb  (472's AFTER)
--   cancel_invoice_recorded(uuid,text,uuid)                           de52d9dbaef8ab15163bef35cb9d733d
--   reopen_invoice(uuid,text,uuid)                                    30066e137b9b75b5789a050c14debc04  (475's AFTER)
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)         804ecd829cfecf713783a09a05d93c7e
--   apply_reopened_invoice_benefits()                                 36eaa7224e514d3e7e42e3eeb51acfb5
--   correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)         af99337094edb6d73b9cc0ae00fbf138  (the self-test too)
--   reverse_credit_lot(uuid,text,text,text)                           10c1a3d8e3bb003fbaf01cf879f97c5e
--   delete_customer(uuid,text,text)                                   5b407735574fc3cacd8067c4dc8213f4
--   allocate_invoice_wallet_credit(uuid,numeric,text,text)            da8aa986c92d765a8028741f33bf56b0  (443)
--   invoice_reopen_preview(uuid)                                      e09ebf9c0841ef5463f96b26f4933541  (474's)
--   invoice_reopen_preview_before_sessions(uuid)                      7e1ef2d25415e69b3f770fe2efd45190  (474's AFTER)
--   invoice_financial_position(uuid)                                  ba7eccbfeff217c8b1969b0e55a010ca  (the self-test)
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)      80c80d386a5241e63b353e35e13ef250  (the self-test)
--   record_invoice_payment(uuid,jsonb,uuid)                           9c70097ed4da614fb9dcc66fdfcdb7d6  (the self-test)
--   public function fingerprint, production now (475)                 e948504da4c17c1c15ff871fcb1e5631 (1387 functions; head 20261027082304)
--   grant list (string_agg(signature '=' proacl, '|'), sorted)        381ef69cb44f960ff981585ff8402fa1 (production lists the same
--                                                                      grants in another order: compare as sets)
--   grant list as sets (each proacl's items sorted)                   eff827bcb9881954d60c42c2d02475fe
-- AFTER (for later guards)
--   invoice_transferable_benefits(uuid)                               1546de1f83d970424d26e65941f4dcb8  (grants kept: signed-in staff, postgres, the service role)
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)            142dd3252911480bd4a17e7c55b488d3  (grants kept: postgres, the service role)
--   release_credit_package_paid_credit(uuid)                          f6685d987e998575c3c1e5917493dc24  (grants kept: postgres, the service role)
--   issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid)            5654ef9249cf5c6a943beb7890574f20  (grants kept: postgres, the service role)
--   sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid) 72d4ba2c35703b336f3b2e9114a6af6e  (grants kept: postgres, the service role)
--   invoice_package_commission_preview(uuid)                          5ed13af2d3104dd04b4739b3ab8507bc  (grants kept: postgres, the service role)
--   credit_line_sale_group(uuid)                                      9c0e2931b672a763235d3d9839b2f02a  (added: postgres, the service role)
--   credit_line_benefits_holder(uuid)                                 45865ed52a5f24ebe6b8e435ba10e9e9  (added: postgres, the service role)
--   invoice_credit_receivers(uuid)                                    ecdd2c5a5051cca33a9cedd0a5c07666  (added: signed-in staff, postgres, the service role)
--   public function fingerprint, worked out on a copy of production at 475 (28 Oct 2026; a second run the same):
--     production now (475) -> 476                                     cc7185970e4a01c0a225e114e0769691 (1390 functions: three added, none dropped)
--     (this file's build of 27 Oct 2026, with the Pay dialog's read before its 'reinstated' part: 8c16bb63)
--   grant list after 476 (on that copy)                               c05bd82edeafa1bf1e7165a406fcb043 (in the copy's order; the six functions' grants
--                                                                      as before, compared as sets; the three new ones as above)
--   grant list as sets after 476                                      5752c2df613b8a673831d1797636e3d7
--
-- Test: scripts/invoices/tests/part-paid-change-same-as-paid-in-full-476.sql
-- (begin ... rollback; it installs this file twice; -v nomig=1 where it is
-- in). It reproduces the faults first (TQn2 and its siblings; K1, K2 and
-- theirs; X1 to X10, two or more package or bundle lines; KAL, KAL1, KAP,
-- KALp, a line a correction added, and their paid-in-full counterparts;
-- KAE and KAT2, a line an edit added before any money, two lines one
-- correction added; K1v, Kvb, X4 with their vouchers, sale records and the
-- commission rows of referrers set on the made-up customers, with and
-- without the part-payment layer registered; G5, C3c, C5, L4, a package
-- settled after the change and falling back to part-paid, beside their
-- paid-in-full counterparts G5F, C3cF; TQfix, TQcru and theirs), then
-- checks the header's query (1 to 9), the refusals, the install, every case
-- after 476 with 462's invariants (471's and 473's reading of them) and
-- Cancel, the list's rows and the review summary's blocked items beside
-- the paid-in-full package's, the Pay dialog's read (and its refusal of
-- anyone but staff of the store; on a reopened invoice the credit its
-- settling payment gives back, by receiver, beside what that payment
-- gives), the controls exactly as before (473's included), cases begun
-- before 476 and finished after it, and NOT COVERED 1 to 4, 7 (with a
-- payout in the window), 9 and 13 as KNOWN. Each app call is followed by what its commit does
-- (462's trigger is deferred). Fixtures only (the repository is public).
-- Page: scripts/invoices/tests/credit-receivers-476.test.mjs (node --test).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The functions this changes: BEFORE (a copy of production at 475, 27 Oct
  -- 2026) and AFTER md5s; who may call each, as read (kept) ════════════════
  c_sigs constant text[] := array[
    'invoice_transferable_benefits(uuid)',
    'move_invoice_benefits_to_customer(uuid,uuid,uuid,text)',
    'release_credit_package_paid_credit(uuid)',
    'issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid)',
    'sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid)',
    'invoice_package_commission_preview(uuid)'];
  c_names constant text[] := array['invoice_transferable_benefits', 'move_invoice_benefits_to_customer',
                                   'release_credit_package_paid_credit', 'issue_credit_package',
                                   'sell_premium_bundle', 'invoice_package_commission_preview'];
  c_before constant text[] := array[
    'a2332a22fe9975667e848de0d1e4480b',
    'c01606c84ee13ddcd88c15521d6d9aed',
    '530521c100163445e5a0b99799fbcccc',
    'cc3737e39249ea9ebfed729a1e221f84',
    '3cee8de4ce6361744a9d57b172e84563',
    '906791a4de678bd2d1dcac59838d17f1'];
  c_after constant text[] := array[
    '1546de1f83d970424d26e65941f4dcb8',
    '142dd3252911480bd4a17e7c55b488d3',
    'f6685d987e998575c3c1e5917493dc24',
    '5654ef9249cf5c6a943beb7890574f20',
    '72d4ba2c35703b336f3b2e9114a6af6e',
    '5ed13af2d3104dd04b4739b3ab8507bc'];
  c_acl constant text[] := array[
    '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}'];
  -- ══ The functions this adds: two the server's alone; the Pay dialog's read
  -- for signed-in staff (it checks the store itself, 406) ══════════════════
  c_new constant text[] := array[
    'credit_line_sale_group(uuid)',
    'credit_line_benefits_holder(uuid)',
    'invoice_credit_receivers(uuid)'];
  c_new_names constant text[] := array['credit_line_sale_group', 'credit_line_benefits_holder', 'invoice_credit_receivers'];
  c_new_after constant text[] := array[
    '9c0e2931b672a763235d3d9839b2f02a',
    '45865ed52a5f24ebe6b8e435ba10e9e9',
    'ecdd2c5a5051cca33a9cedd0a5c07666'];
  c_new_acl constant text[] := array[
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'];

  -- ══ The whole texts (each exactly as the database prints it back) ═══════
  c_def_group constant text := $d0$CREATE OR REPLACE FUNCTION public.credit_line_sale_group(p_invoice_item_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 476 (the Owner, 27 Oct 2026, answer A: "Same as paid-in-full"): which
  -- sale an invoice line was sold in. 0: the invoice's own sale, the lines it
  -- was made with and those an edit added before any money was received (the
  -- sale as the customer started paying for it). Otherwise the revision_no
  -- of the correction that added the line once money had been received or
  -- the invoice had been settled: lines one correction added were sold
  -- together, and with nothing else.
  -- Read from the invoice's revisions. correct_invoice is the only way a line
  -- is added to an invoice that exists (update_invoice_internal, which it
  -- alone calls), and before every edit of the lines it saves the lines as
  -- they were (invoice_revisions.snapshot 'items', every row with its id)
  -- with the invoice as it was ('invoice': its status, paid_amount and
  -- locked_at); a line keeps its id while it stays on the invoice. So the
  -- latest revision whose lines before do not include this one is the edit
  -- that added it; none: it was there when the invoice was made. That edit
  -- came before any money when the invoice was then a draft or unpaid, with
  -- nothing received and never settled (not locked).
  select coalesce((
    select case when coalesce(r.snapshot->'invoice'->>'status', '') in ('draft', 'unpaid')
                     and coalesce((r.snapshot->'invoice'->>'paid_amount')::numeric, 0) = 0
                     and r.snapshot->'invoice'->>'locked_at' is null
                then 0 else r.revision_no end
      from public.invoice_items it
      join public.invoice_revisions r on r.invoice_id = it.invoice_id
     where it.id = p_invoice_item_id
       and jsonb_typeof(r.snapshot->'items') = 'array'
       and not (r.snapshot->'items' @> jsonb_build_array(jsonb_build_object('id', it.id)))
     order by r.revision_no desc
     limit 1), 0)
$function$
$d0$;
  c_def_holder constant text := $d1$CREATE OR REPLACE FUNCTION public.credit_line_benefits_holder(p_invoice_item_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 476 (the Owner, 27 Oct 2026: "Same as paid-in-full", answers A and B):
  -- whom what a Credit Package or Premium Bundle line paid in part gives
  -- later goes to (the credit a further payment or its reopening releases;
  -- at settlement the paid credit not yet released, the Bonus, the vouchers
  -- and their allowance and the sale record, which the commission reads):
  -- whoever holds the package's benefits now. That is the holder of the
  -- credit the line released before (its release records,
  -- credit_package_progress_lots, each followed to the lot it reaches now,
  -- credit_lot_current: a merge's or a customer change's reissue), by 462's
  -- rule (invoice_credit_live_holder: the customer the latest change that
  -- took the invoice's benefits along moved them to since that lot was made,
  -- then the record a merge kept; never a deleted record). So after a 'keep'
  -- change it is the buyer, after a 'transfer' change or a merge whoever
  -- they went to.
  -- A line that released nothing yet goes with the lines sold with it
  -- (credit_line_sale_group: the invoice's own sale, or the lines one
  -- correction added after money was received): to the holder of what they
  -- released, by the same rule. The money goes to the credit lines one after
  -- another (credit_package_money_toward_line), so a part payment can
  -- release credit on one line and nothing on the next; paid in full both
  -- would be the buyer's, and a 'keep' change leaves them so. A line a
  -- correction added after money was received, before the change or after
  -- it, was not sold with the others: it goes to the invoice's customer who
  -- pays for it, as when the first package was paid in full.
  -- Null where nothing was released yet by the line or the lines sold with
  -- it, or what was released is held by more than one customer (a package
  -- split before 476; for the Owner): the callers then give to the invoice's
  -- customer, as before.
  with me as (
    select it.id, it.invoice_id, public.credit_line_sale_group(it.id) as sale
      from public.invoice_items it
     where it.id = p_invoice_item_id),
  h as (
    select pl.invoice_item_id = me.id as own,
           public.invoice_credit_live_holder(pl.invoice_id, c.customer_id, c.created_at) as id
      from me
      join public.invoice_items o on o.invoice_id = me.invoice_id
                                 and (o.id = me.id
                                      or o.line_kind in ('credit_package', 'premium_bundle')
                                         and public.credit_line_sale_group(o.id) = me.sale)
      join public.credit_package_progress_lots pl on pl.invoice_item_id = o.id
      join public.customer_credit_lots c on c.id = public.credit_lot_current(pl.lot_id)),
  s as (
    select h.id from h where h.own or not exists (select 1 from h x where x.own))
  select case when count(*) > 0 and count(s.id) = count(*) and count(distinct s.id) = 1
              then (array_agg(s.id))[1] end
    from s
$function$
$d1$;
  c_def_receivers constant text := $d2$CREATE OR REPLACE FUNCTION public.invoice_credit_receivers(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.require_store_access((select i.store_id from public.invoices i where i.id = p_invoice_id));  -- 406: active staff of the invoice's store only
  -- 476 (the Owner, 27 Oct 2026, answer E: "Dialogs name the receiver"), for
  -- the Pay dialog (Record Payment): the invoice's Credit Package and
  -- Premium Bundle lines not yet settled whose credit a payment gives to a
  -- customer other than the invoice's (and their Bonus, vouchers, sale
  -- record and commission at settlement): whoever holds the package's
  -- benefits (credit_line_benefits_holder), as the payment itself gives
  -- them (release_credit_package_paid_credit, issue_credit_package,
  -- sell_premium_bundle). A line whose receiver is the invoice's customer is
  -- not listed, nor a split line (each part has its own customer). Read
  -- with the invoice: what a payment then gives is decided again by the
  -- payment itself.
  -- And ('reinstated'), so staff are told what the payment will give: on a
  -- reopened invoice, the credit the payment that settles it reinstates
  -- (invoice_reopen_benefits not applied yet) goes back on the lot each
  -- ledger row took it from and on to whoever holds the invoice's benefits
  -- now (apply_reopened_invoice_benefits: 460's and 462's rule, read as the
  -- Reopen dialog reads it, 478): each customer other than the invoice's,
  -- with the amount (the buyer after a 'keep' change, someone an Owner
  -- moved credit to).
  select jsonb_build_object(
           'invoice_id', i.id, 'customer_id', i.customer_id,
           'lines', coalesce((
             select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'label', public.invoice_line_label(it.id),
                                                 'customer_id', c.id, 'customer_name', c.full_name) order by it.id)
               from public.invoice_items it
               cross join lateral (select public.credit_line_benefits_holder(it.id) as id) h
               join public.customers c on c.id = h.id
              where it.invoice_id = i.id
                and it.line_kind in ('credit_package', 'premium_bundle')
                and it.credit_issued_at is null
                and it.credit_split_allocation_id is null
                and it.bundle_split_allocation_id is null
                and not exists (select 1 from public.invoice_credit_splits sp where sp.invoice_item_id = it.id)
                and h.id is distinct from i.customer_id), '[]'::jsonb),
           'reinstated', coalesce((
             select jsonb_agg(jsonb_build_object('customer_id', r.receiver, 'customer_name', c.full_name, 'amount', r.amount)
                              order by c.full_name, r.receiver)
               from (select k.receiver, sum(k.amount) as amount
                       from (select coalesce(public.invoice_credit_live_holder(i.id, tl.customer_id,
                                               case when exists (select 1 from public.invoice_benefit_values bv
                                                                  where bv.invoice_id = i.id and bv.lot_id = tl.id
                                                                    and public.invoice_benefit_moved_to_other(bv.id))
                                                    then 'infinity'::timestamptz else tl.created_at end),
                                             (select c2.id from public.customer_credit_lots pl join public.customers c2 on c2.id = pl.customer_id
                                               where pl.id = any (g.lots) and c2.deleted_at is null order by pl.created_at, pl.id limit 1),
                                             tl.customer_id) as receiver, g.amount
                               from (select t.target, sum(t.amount) as amount, array_agg(t.lot_id) as lots
                                       from (select lg.lot_id, rb.amount,
                                                    coalesce((select bv.lot_id from public.invoice_benefit_values bv
                                                               where bv.invoice_id = i.id and bv.lot_id is not null
                                                                 and lg.lot_id = any (public.credit_lot_ancestry(bv.lot_id))
                                                               order by (bv.lot_id = lg.lot_id) desc, bv.created_at, bv.id limit 1), lg.lot_id) as target
                                               from public.invoice_reopen_benefits rb
                                               join public.customer_credit_ledger lg on lg.id = rb.source_ledger_id
                                              where rb.invoice_id = i.id and rb.applied_at is null) t
                                      group by t.target) g
                               join public.customer_credit_lots tl on tl.id = g.target) k
                      group by k.receiver) r
               join public.customers c on c.id = r.receiver
              where r.receiver is distinct from i.customer_id and r.amount > 0), '[]'::jsonb))
    from public.invoices i
   where i.id = p_invoice_id
$function$
$d2$;
  c_def_list constant text := $d3$CREATE OR REPLACE FUNCTION public.invoice_transferable_benefits(p_invoice_id uuid)
 RETURNS TABLE(kind text, record_id uuid, description text, units numeric, movable boolean, blocking boolean, blocked_reason text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.require_store_access((select i.store_id from public.invoices i where i.id = p_invoice_id));  -- 406: active staff of the invoice's store only
  -- Three states, not two. A benefit is either still wholly unused (it moves
  -- with the invoice), wholly consumed (there is nothing to move and nothing
  -- to strand, so the usage stays where it happened), or PARTLY used -- the
  -- only genuinely ambiguous case, and the only one that stops the correction.
  select 'voucher', crv.id,
         v.name || ' × ' || crv.quantity, crv.quantity::numeric,
         crv.status = 'held' and crv.redeemed_at is null,
         false,
         case when crv.status <> 'held' or crv.redeemed_at is not null
              then 'Already ' || coalesce(nullif(crv.status,''),'used')
                   || '; it stays with the original customer' end
    from public.customer_reward_vouchers crv
    join public.vouchers v on v.id = crv.voucher_id
   -- 460 (the Owner, 22 Oct 2026): the invoice's own vouchers, as a
   -- customer change moves them (invoice_own_voucher_ids): also those given
   -- again in place of one of them, so the review summary lists every
   -- voucher that moves.
   where crv.id in (select o.voucher_id from public.invoice_own_voucher_ids(p_invoice_id) o)
  union all
  -- 461 (the Owner, 22 Oct 2026: "fix the other two rare gaps too"; 448's
  -- NOT COVERED 3): credit a line refund paid back is not spent, as 448
  -- decided for the cancel plans. A lot is spent when what it holds, what a
  -- cancellation took back and what is not used although it is no longer on
  -- it (invoice_benefit_unused_elsewhere: what a line refund paid back, what
  -- an Owner moved) come to less than its benefit row granted: the test
  -- cancelled_invoice_used_value and invoice_action_plan make. So a lot
  -- partly refunded and not spent moves what it holds, as an untouched lot
  -- does (move_invoice_benefits_to_customer makes the same test), and one a
  -- refund emptied reads "Refunded", not "Fully spent". It moves only when
  -- nothing else holds a claim on it: no cancellation still holds credit
  -- back for it (cancelled_unused_value 0) and no reopening of the invoice
  -- waits to give credit back (invoice_reopen_benefits: the payment puts
  -- either back on the lot it was taken from), and the invoice is neither
  -- cancelled nor refunded. Otherwise, and for a lot with real spending or
  -- with no benefit row of this invoice (older invoices, credit released
  -- before settlement), it reads as before: "Partly spent", blocking.
  -- 462 (the Owner, 24 Oct 2026): an Owner's Move of the row's benefit is no
  -- claim any more (the moved credit is traced through the Move's own ledger
  -- rows, so the records follow the change). And a lot a merge, a customer
  -- change or a give-back reissued, which a benefit row of this invoice
  -- names, is judged by that row alone (it was granted only what was left):
  -- untouched only when that row's test says nothing was spent.
  select 'credit', l.id,
         initcap(l.category) || ' credit ' || l.remaining_amount::text,
         l.remaining_amount,
         l.status = 'active' and l.remaining_amount > 0
           and (w.untouched or coalesce(u.moves, false) or r.unspent) and not s.spent_before   -- 476: r
           and not ls.line_spent,   -- 473
         l.remaining_amount > 0 and (not w.untouched and not coalesce(u.moves, false) and not r.unspent   -- 476: r
                                     or s.spent_before or ls.line_spent),   -- 473
         case when l.remaining_amount = 0 and u.unspent and u.refunded then 'Refunded; nothing is left to move'
              when l.remaining_amount = 0 then 'Fully spent; it stays with the original customer'
              when not w.untouched and not coalesce(u.moves, false) and not r.unspent   -- 476: r
                   or s.spent_before or ls.line_spent then 'Partly spent'   -- 473
              when l.status <> 'active' then 'Not active' end
    from public.customer_credit_lots l
    left join lateral (
      select true as named,
             l.remaining_amount + b.cancelled_unused_value + e.unused >= b.granted_value as unspent,
             l.remaining_amount + b.cancelled_unused_value + e.unused >= b.granted_value
               and b.cancelled_unused_value = 0
               and not exists (select 1 from public.invoice_reopen_benefits q
                                where q.invoice_id = p_invoice_id and q.applied_at is null)
               and not exists (select 1 from public.invoices iv
                                where iv.id = p_invoice_id and iv.status in ('cancelled', 'refunded')) as moves,
             e.unused > 0 and not exists (select 1 from public.invoice_benefit_transfers t
                                           where t.source_benefit_id = b.id and t.replacement_benefit_id is not null) as refunded
        from public.invoice_benefit_values b
        cross join lateral (select public.invoice_benefit_unused_elsewhere(b.id) as unused) e
       where b.lot_id = l.id and b.invoice_id = p_invoice_id) u on true
    cross join lateral (select l.remaining_amount = l.original_amount
                               and (l.reassigned_from_lot_id is null or u.named is null) as untouched) w
    -- 476 (the Owner, 27 Oct 2026, answer C: "Same as paid-in-full"; a
    -- 'transfer' change is refused only once something was used, and refunds
    -- paid back count as not used): a lot of credit released before full
    -- payment that no benefit row names (the line not settled) holds less
    -- than it was granted where some of it was taken back without being used:
    -- the invoice's payment corrected lower (the trim takes S$5 off a S$40
    -- lot), or a Cancel's write-off of it then a reopening and a refund paid
    -- back onto it (the lot Cancel closed open again, locked, holding what
    -- its release record still counts). Judged as untouched only when it
    -- held all it was granted, such a lot read "Partly spent" and blocked a
    -- 'transfer' change though nothing on it was used. Now such a lot is
    -- judged by what the release records whose lot it is now
    -- (credit_lot_current: a merge's or a change's reissue followed) count as
    -- released: it holds all of that, nothing on it was used, and it moves
    -- with the change (move_invoice_benefits_to_customer makes the same test),
    -- when nothing else holds a claim on it, as 461's test asks of a lot a
    -- benefit row names: no reopening of the invoice waits to give credit
    -- back, and the invoice is neither cancelled nor refunded. 473's test of
    -- the line's other release records (below) still blocks it where any of
    -- them was spent.
    cross join lateral (select coalesce(u.named is null and l.remaining_amount >= nullif(x.counted, 0)
                                        and not exists (select 1 from public.invoice_reopen_benefits q
                                                         where q.invoice_id = p_invoice_id and q.applied_at is null)
                                        and not exists (select 1 from public.invoices iv
                                                         where iv.id = p_invoice_id and iv.status in ('cancelled', 'refunded')),
                                        false) as unspent
                          from (select sum(pl.released_amount) as counted
                                  from public.credit_package_progress_lots pl
                                 where pl.invoice_id = p_invoice_id and public.credit_lot_current(pl.lot_id) = l.id
                                   and not exists (select 1 from public.invoice_benefit_values bv
                                                    where bv.lot_id = any (public.credit_lot_chain(pl.lot_id)))) x) r
    -- 463: credit an Owner moved to the same customer at another store (a
    -- store correction) from a benefit row partly spent before the Move:
    -- the Move gave its row only what was left, so the row alone looks
    -- untouched; it is judged by the rows it was moved from too
    -- (invoice_benefit_moved_from_spent), so it blocks the change as
    -- "Partly spent", as the same credit without the Move does (461).
    cross join lateral (select exists (select 1 from public.invoice_benefit_values b
                                        where b.lot_id = l.id and b.invoice_id = p_invoice_id
                                          and public.invoice_benefit_moved_from_spent(b.id)) as spent_before) s
    -- 473 (the Owner, 26 Oct 2026: "fix the leftover gaps too"; 471's NOT
    -- COVERED 9: a 'transfer' change of a partly spent package is refused as
    -- "Partly spent", the rule for a package paid in full applied the same
    -- way): the paid credit of a package paid in part is on more than one
    -- lot, the credit released before it was paid in full (327, 356: S$1 for
    -- each S$1 received) and the rest; once settled, a benefit row names
    -- each (capture_invoice_benefit_values). Each lot was judged on its own,
    -- so where what was released was spent in full and the rest untouched,
    -- the first read "Fully spent" and the rest moved, the change splitting
    -- one package between two customers (S$40 used by the buyer, S$60 moved),
    -- where the same package paid in full with the same spending, one lot,
    -- is refused. Now a lot is judged with the line's other lots of its
    -- category: it is partly spent, and blocks, while it holds credit and
    -- any of them reads as spent by 461's test (what its lot holds, what a
    -- cancellation took back and what is not used although it is no longer
    -- on it, less than its row granted; a row an Owner moved to someone else
    -- is its recipient's and is not read, 434, 463). Before settlement no
    -- benefit row names a released lot: a lot of the line's release record
    -- (credit_package_progress_lots) is judged with the line's other release
    -- records whose lots no benefit row names, one reading as spent where its
    -- lot (credit_lot_current: a merge's or change's reissue followed) holds
    -- less than the record still counts as released (the record counts what
    -- a Cancel's write-off, a trim or 471's hold took back as no longer
    -- released, so only spending is left).
    cross join lateral (select
        exists (select 1 from public.invoice_benefit_values b
                  join public.invoice_benefit_values g on g.invoice_id = b.invoice_id and g.invoice_item_id = b.invoice_item_id
                  join public.customer_credit_lots gl on gl.id = g.lot_id
                 where b.lot_id = l.id and b.invoice_id = p_invoice_id
                   and gl.category is not distinct from l.category
                   and not public.invoice_benefit_moved_to_other(g.id)
                   and gl.remaining_amount + g.cancelled_unused_value
                       + public.invoice_benefit_unused_elsewhere(g.id) < g.granted_value)
        or u.named is null
           and exists (select 1 from public.credit_package_progress_lots pl
                         join public.credit_package_progress_lots g on g.invoice_id = pl.invoice_id and g.invoice_item_id = pl.invoice_item_id
                        where pl.invoice_id = p_invoice_id and l.id = any (public.credit_lot_chain(pl.lot_id))
                          and g.released_amount > 0
                          and not exists (select 1 from public.invoice_benefit_values bv
                                           where bv.lot_id = any (public.credit_lot_chain(g.lot_id)))
                          and coalesce((select c.remaining_amount from public.customer_credit_lots c
                                         where c.id = public.credit_lot_current(g.lot_id) and c.status = 'active'), 0)
                              < g.released_amount) as line_spent) ls
   where (l.id in (select lot_id from public.invoice_credit_lot_ids(p_invoice_id))
          -- 463 (the Owner, 24 Oct 2026, decision 2): and credit an Owner
          -- moved to the same customer at another store, which stays the
          -- invoice's own (invoice_benefit_moved_to_other), as the change
          -- moves it (move_invoice_benefits_to_customer).
          or l.id in (select b.lot_id from public.invoice_benefit_values b
                       where b.invoice_id = p_invoice_id and b.lot_id is not null
                         and exists (select 1 from public.invoice_benefit_transfers t
                                      where t.replacement_benefit_id = b.id)
                         and not public.invoice_benefit_moved_to_other(b.id)))
  union all
  -- 476 (the Owner, 27 Oct 2026, answering 473's NOT COVERED 1: "Same as
  -- paid-in-full"): a package line paid in part, not settled, whose released
  -- credit was spent with nothing left on its lots and more still to be
  -- released listed nothing that blocks (each lot "Fully spent"), so a
  -- 'transfer' change went through and the next payment's credit went to the
  -- new customer: S$40 paid and used by the buyer, S$60 to the new customer,
  -- where the same package paid in full with the same spending is refused.
  -- Now the credit such a line has still to release (what it is entitled to,
  -- less what its release record counts as released) is listed as the lot
  -- holding what is left is for the package paid in full: "Paid credit
  -- 60.00", not movable, blocking, "Partly spent", so the change is refused
  -- with the paid-in-full package's words. A release record reads as spent
  -- by 473's test (its lot, followed to where it is now, holds less than the
  -- record counts as released). Where a lot of the line's releases still
  -- holds credit, that lot's own row blocks already (473). Not for an
  -- invoice cancelled or refunded (its payments release nothing; changed
  -- then, its reopening's payment gives to whoever holds the benefits, as
  -- for a package paid in full: 473's NOT COVERED 3). Its record_id is the
  -- line's (no lot holds that credit yet).
  select 'credit', it.id,
         'Paid credit ' || x.to_come::text, x.to_come,
         false, true, 'Partly spent'
    from public.invoice_items it
    cross join lateral (select round(public.credit_line_paid_entitlement(it.id)
                                     - public.credit_package_released_paid_credit(it.id), 2) as to_come) x
   where it.invoice_id = p_invoice_id
     and it.line_kind in ('credit_package', 'premium_bundle')
     and it.credit_issued_at is null
     and it.credit_split_allocation_id is null
     and it.bundle_split_allocation_id is null
     and not exists (select 1 from public.invoice_credit_splits sp where sp.invoice_item_id = it.id)
     and x.to_come > 0
     and not exists (select 1 from public.invoices iv
                      where iv.id = p_invoice_id and iv.status in ('cancelled', 'refunded'))
     and exists (select 1 from public.credit_package_progress_lots g
                  where g.invoice_item_id = it.id and g.released_amount > 0
                    and not exists (select 1 from public.invoice_benefit_values bv
                                     where bv.lot_id = any (public.credit_lot_chain(g.lot_id)))
                    and coalesce((select c.remaining_amount from public.customer_credit_lots c
                                   where c.id = public.credit_lot_current(g.lot_id) and c.status = 'active'), 0)
                        < g.released_amount)
     and not exists (select 1 from public.credit_package_progress_lots g
                      join public.customer_credit_lots c on c.id = public.credit_lot_current(g.lot_id)
                     where g.invoice_item_id = it.id and c.remaining_amount > 0)
  union all
  select 'voucher_allowance', e.id,
         e.package_name || ' — ' || coalesce(e.voucher_qty,0) || ' voucher(s)',
         coalesce(e.voucher_qty,0)::numeric,
         public.entitlement_claimed_qty(e.id) = 0 and e.status <> 'cancelled',
         public.entitlement_claimed_qty(e.id) > 0
           and public.entitlement_claimed_qty(e.id) < coalesce(e.voucher_qty,0),
         case when public.entitlement_claimed_qty(e.id) >= coalesce(e.voucher_qty,0)
                   and coalesce(e.voucher_qty,0) > 0
                then 'Fully claimed; it stays with the original customer'
              when public.entitlement_claimed_qty(e.id) > 0 then 'Partly claimed'
              when e.status = 'cancelled' then 'Cancelled' end
    from public.therapy_entitlements e
   where e.claim_source_invoice_id = p_invoice_id
  union all
  select 'therapy_unit', p.id,
         p.package_name || ' — ' || coalesce(p.status,''), 1,
         p.status in ('pending_activation','scheduled'),
         false,
         case when p.status not in ('pending_activation','scheduled')
              then 'Therapy is ' || p.status end
    from public.purchased_therapy_entitlements p
   where p.invoice_id = p_invoice_id
$function$
$d3$;
  c_def_move constant text := $d4$CREATE OR REPLACE FUNCTION public.move_invoice_benefits_to_customer(p_invoice_id uuid, p_customer_id uuid, p_store_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_blocked text; v_v int := 0; v_c int := 0; v_a int := 0; v_wallet uuid; v417 record;
        r_lot public.customer_credit_lots%rowtype; v_new_lot uuid;
        v463_kept uuid[];  -- 463: vouchers that keep their store
begin
  select string_agg(description || ' (' || blocked_reason || ')', '; ')
    into v_blocked
    from public.invoice_transferable_benefits(p_invoice_id)
   where blocking;
  if v_blocked is not null then
    raise exception 'These benefits have already been used and cannot move with the invoice: %. Resolve each one through the benefit transfer review before reassigning.', v_blocked
      using errcode='P0001'; end if;

  -- 417: the stock of a limited voucher moves with it to the new store, as
  -- an Owner's move of one voucher (transfer_invoice_unused_benefit) moves
  -- it: taken at the new store, given back at the old one. Before, the
  -- vouchers moved and their stock stayed, so a later cancellation gave it
  -- back at the new store and the old one stayed short. The vouchers are
  -- locked first, so none is used in between.
  -- 460 (the Owner, 22 Oct 2026: "fix the other two rare gaps too"): the
  -- invoice's own vouchers (invoice_own_voucher_ids): its voucher and
  -- promotion lines', and those given again in place of one of them by a
  -- reopening or by the payment after an FOC came off ('invoice_reopen').
  -- Before, only the first two sources, so a voucher given again stayed
  -- with the old customer. Not one an Owner moved to someone (434), nor a
  -- Premium Bundle's, as before.
  perform 1 from public.customer_reward_vouchers
   where id in (select o.voucher_id from public.invoice_own_voucher_ids(p_invoice_id) o)
     and status = 'held' and redeemed_at is null
   order by id for update;
  -- 463 (the Owner, 24 Oct 2026, decisions 2 and 3): a voucher an Owner
  -- moved to the same customer at another store (a store correction, which
  -- a customer change that takes the benefits along takes along), and a
  -- Premium Bundle's (they follow such a change as the bundle's credit
  -- does), and one given again in place of either, is one of the invoice's
  -- own now (invoice_own_voucher_ids): it moves to the new customer and
  -- keeps its store, as credit keeps its store: no stock moves for it. The
  -- voucher and promotion lines' go to the invoice's store, as before (417).
  v463_kept := array(
    with recursive k(id, n) as (
      select o.voucher_id, 0
        from public.invoice_own_voucher_ids(p_invoice_id) o
        join public.customer_reward_vouchers c on c.id = o.voucher_id
       where c.source_type in ('invoice_benefit_transfer', 'premium_bundle')
      union all
      select q.replacement_voucher_id, k.n + 1
        from k
        join public.invoice_benefit_values b on b.reward_voucher_id = k.id and b.invoice_id = p_invoice_id
        join public.invoice_reopen_vouchers q on q.benefit_id = b.id and q.invoice_id = p_invoice_id
       where q.replacement_voucher_id is not null and k.n < 64)
    select distinct k.id from k);
  for v417 in
    select rv.voucher_id, rv.store_id, sum(rv.quantity)::int as quantity
      from public.customer_reward_vouchers rv
      join public.vouchers vo on vo.id = rv.voucher_id and vo.qty_type = 'limited'
     where rv.id in (select o.voucher_id from public.invoice_own_voucher_ids(p_invoice_id) o)   -- 460
       and rv.status = 'held' and rv.redeemed_at is null
       and p_store_id is not null and rv.store_id is not null and rv.store_id <> p_store_id
       and rv.id <> all (v463_kept)   -- 463
     group by rv.voucher_id, rv.store_id
     order by rv.voucher_id, rv.store_id
  loop
    update public.voucher_store_stock set current_qty = current_qty - v417.quantity
     where voucher_id = v417.voucher_id and store_id = p_store_id and current_qty >= v417.quantity;
    if not found then raise exception 'Not enough voucher stock at the destination store'; end if;
    insert into public.voucher_store_stock(voucher_id, store_id, current_qty)
      values (v417.voucher_id, v417.store_id, v417.quantity)
      on conflict (voucher_id, store_id) do update
        set current_qty = public.voucher_store_stock.current_qty + excluded.current_qty;
  end loop;

  update public.customer_reward_vouchers
     set customer_id = p_customer_id,
         store_id = case when id = any (v463_kept) then store_id else p_store_id end   -- 463
   where id in (select o.voucher_id from public.invoice_own_voucher_ids(p_invoice_id) o)   -- 460
     and status = 'held' and redeemed_at is null;
  get diagnostics v_v = row_count;

  v_wallet := public.ensure_customer_wallet(p_customer_id);
  for r_lot in
    select l.* from public.customer_credit_lots l
     where (l.id in (select lot_id from public.invoice_credit_lot_ids(p_invoice_id))
            -- 463 (the Owner, 24 Oct 2026, decision 2): and credit an Owner
            -- moved to the same customer at another store (a store
            -- correction): the lot its benefit row names now, which stays
            -- the invoice's own (invoice_benefit_moved_to_other), so it
            -- moves with its records, keeping its store, as the invoice's
            -- own credit does. Not a Move to someone else (its recipient
            -- keeps it, 434).
            or l.id in (select b.lot_id from public.invoice_benefit_values b
                         where b.invoice_id = p_invoice_id and b.lot_id is not null
                           and exists (select 1 from public.invoice_benefit_transfers t
                                        where t.replacement_benefit_id = b.id)
                           and not public.invoice_benefit_moved_to_other(b.id)))
       -- 461 (the Owner, 22 Oct 2026): or nothing on it was spent. Credit a
       -- line refund paid back is not spent (448's test, made here as the
       -- list makes it, invoice_transferable_benefits), so what the lot
       -- still holds moves, as an untouched lot's credit does, keeping its
       -- origin (447), when nothing else holds a claim on it: no
       -- cancellation still holds credit back for it, no reopening waits to
       -- give credit back, the invoice neither cancelled nor refunded.
       -- Tested on the lot's own figures, which are read again once it is
       -- locked, so credit spent meanwhile keeps it here.
       -- 462 (the Owner, 24 Oct 2026): an Owner's Move of its benefit is no
       -- claim any more (the moved credit is traced through the Move's own
       -- ledger rows, so the records follow, below). And a lot a merge, a
       -- customer change or a give-back reissued, which a benefit row of this
       -- invoice names, is judged by that row alone: such a lot was granted
       -- only what was left, so holding all of it says nothing about what
       -- the row's earlier lots spent.
       and (l.remaining_amount = l.original_amount
              and (l.reassigned_from_lot_id is null
                   or not exists (select 1 from public.invoice_benefit_values b
                                   where b.lot_id = l.id and b.invoice_id = p_invoice_id))
            or exists (select 1 from public.invoice_benefit_values b
                        where b.lot_id = l.id and b.invoice_id = p_invoice_id
                          and l.remaining_amount + b.cancelled_unused_value
                              + public.invoice_benefit_unused_elsewhere(b.id) >= b.granted_value
                          and b.cancelled_unused_value = 0)
               and not exists (select 1 from public.invoice_reopen_benefits q
                                where q.invoice_id = p_invoice_id and q.applied_at is null)
               and not exists (select 1 from public.invoices iv
                                where iv.id = p_invoice_id and iv.status in ('cancelled', 'refunded'))
            -- 476 (the Owner, 27 Oct 2026, answer C): or, for credit released
            -- before full payment that no benefit row names (the line not
            -- settled), it holds all that the release records whose lot it is
            -- now (credit_lot_current) count as released: what was taken back
            -- without being used (the payment corrected lower; a Cancel's
            -- write-off, then a reopening and a refund paid back onto it) is
            -- no longer counted, so nothing on it was used and it moves, as the
            -- list (invoice_transferable_benefits) makes the same test, on the
            -- same conditions as 461's (no reopening waits, the invoice
            -- neither cancelled nor refunded). Read again once the lot is
            -- locked. A lot Cancel's write-off locked keeps its lock on the
            -- new customer's lot, as every reissue here carries the lot's
            -- fields over.
            or not exists (select 1 from public.invoice_benefit_values b
                            where b.lot_id = l.id and b.invoice_id = p_invoice_id)
               and l.remaining_amount >= nullif((select sum(pl.released_amount)
                                                   from public.credit_package_progress_lots pl
                                                  where pl.invoice_id = p_invoice_id and public.credit_lot_current(pl.lot_id) = l.id
                                                    and not exists (select 1 from public.invoice_benefit_values bv
                                                                     where bv.lot_id = any (public.credit_lot_chain(pl.lot_id)))), 0)
               and not exists (select 1 from public.invoice_reopen_benefits q
                                where q.invoice_id = p_invoice_id and q.applied_at is null)
               and not exists (select 1 from public.invoices iv
                                where iv.id = p_invoice_id and iv.status in ('cancelled', 'refunded')))
       and l.remaining_amount > 0
       and l.status = 'active'
       -- 463: nor credit an Owner moved to the same customer at another
       -- store from a benefit row partly spent before the Move
       -- (invoice_benefit_moved_from_spent: the list blocks the change for
       -- it, "Partly spent", as for the invoice's own credit), read again
       -- once the lot is locked.
       and not exists (select 1 from public.invoice_benefit_values b
                        where b.lot_id = l.id and b.invoice_id = p_invoice_id
                          and public.invoice_benefit_moved_from_spent(b.id))
       -- Already the new owner's (a repeated request, or a no-op move).
       and l.customer_id is distinct from p_customer_id
     for update
  loop
    v_new_lot := gen_random_uuid();

    update public.customer_credit_lots
       set remaining_amount = 0, updated_at = now() where id = r_lot.id;
    insert into public.customer_credit_ledger
      (wallet_id, customer_id, entry_type, category, amount, lot_id,
       source_type, source_record_id, store_id, reason, created_by, approved_by)
    values (r_lot.wallet_id, r_lot.customer_id, 'adjust_decrease', r_lot.category,
            r_lot.remaining_amount, r_lot.id, 'invoice_reassignment_out', p_invoice_id,
            r_lot.store_id, p_reason, auth.uid(), auth.uid());

    insert into public.customer_credit_lots
    select (jsonb_populate_record(null::public.customer_credit_lots, to_jsonb(r_lot) || jsonb_build_object(
      'id', v_new_lot, 'wallet_id', v_wallet, 'customer_id', p_customer_id,
      'original_amount', r_lot.remaining_amount, 'remaining_amount', r_lot.remaining_amount,
      -- source_type, source_record_id, usage_restrictions, category, store_id,
      -- effective_date and original_purchase_date are carried unchanged.
      'reassigned_from_lot_id', r_lot.id,
      'reference_no', null, 'reason', p_reason, 'reversal_of_lot_id', null,
      'created_by', auth.uid(), 'approved_by', auth.uid(),
      'created_at', now(), 'updated_at', now()))).*;
    insert into public.customer_credit_ledger
      (wallet_id, customer_id, entry_type, category, amount, lot_id,
       source_type, source_record_id, store_id, reason, created_by, approved_by)
    values (v_wallet, p_customer_id, 'grant', r_lot.category, r_lot.remaining_amount,
            v_new_lot, 'invoice_reassignment_in', p_invoice_id, r_lot.store_id,
            p_reason, auth.uid(), auth.uid());

    -- 447 (the Owner, 22 Oct 2026): the invoice's own records follow the
    -- credit to the new customer's lot, as a merge's do (445): its benefit
    -- value (what a cancellation, a refund and its cap, a Move and the
    -- "credit spent" checks read), its sale's lots (what a refund's
    -- commission is traced back through) and a shared package's issued lot.
    -- So a cancellation takes the credit back from the new customer and the
    -- refund due can be recorded. Credit released before settlement is
    -- followed along as before (credit_package_progress_lots keeps its lot).
    -- A lot whose benefit value was moved on to someone else (Move: their
    -- credit is traced back through it) keeps all of these, as in a merge.
    -- 462 (the Owner, 24 Oct 2026): a lot whose benefit value an Owner moved
    -- on (Move) too, now: the moved credit is traced through the Move's own
    -- ledger rows (invoice_credit_transfer_origin), not through this lot, so
    -- its records follow like any other's (as in a merge, 462).
    update public.invoice_benefit_values set lot_id = v_new_lot where lot_id = r_lot.id;
    update public.credit_package_sales set credit_lot_id = v_new_lot where credit_lot_id = r_lot.id;
    update public.credit_package_sales set bonus_credit_lot_id = v_new_lot where bonus_credit_lot_id = r_lot.id;
    update public.premium_bundle_sales set paid_credit_lot_id = v_new_lot where paid_credit_lot_id = r_lot.id;
    update public.premium_bundle_sales set bonus_credit_lot_id = v_new_lot where bonus_credit_lot_id = r_lot.id;
    update public.invoice_credit_splits set issued_lot_id = v_new_lot where issued_lot_id = r_lot.id;

    v_c := v_c + 1;
  end loop;

  update public.therapy_entitlements
     set customer_id = p_customer_id, store_id = p_store_id
   where claim_source_invoice_id = p_invoice_id
     and status <> 'cancelled'
     and public.entitlement_claimed_qty(id) = 0;
  get diagnostics v_a = row_count;

  -- 460 (the Owner, 22 Oct 2026): recorded for every change that takes the
  -- benefits along, also when nothing was left to move (a reopened invoice
  -- whose vouchers and credit wait, a line refunded before the change): what
  -- a reopening gives back later goes to this customer
  -- (invoice_benefits_holder reads it). Before, only when something moved.
  perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_benefits_followed_reassignment',
    null, jsonb_build_object('vouchers', v_v, 'credit_lots', v_c, 'allowances', v_a,
                             'to_customer', p_customer_id, 'reason', p_reason),
    'invoices', p_reason, p_store_id);

  return jsonb_build_object('vouchers', v_v, 'credit_lots', v_c, 'allowances', v_a);
end $function$
$d4$;
  c_def_release constant text := $d5$CREATE OR REPLACE FUNCTION public.release_credit_package_paid_credit(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_inv public.invoices%rowtype; v_it record;
  pk public.credit_packages%rowtype; pb public.premium_bundles%rowtype;
  v_entitled numeric; v_target numeric; v_already numeric; v_delta numeric;
  v_restrict jsonb; v_vouchers uuid[]; v_lot uuid; v_out jsonb := '[]'::jsonb;
  v476_to uuid;  -- 476
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return jsonb_build_object('skipped', true, 'reason', 'no invoice'); end if;
  if v_inv.status in ('cancelled','refunded') then
    return jsonb_build_object('skipped', true, 'reason', 'invoice ' || v_inv.status); end if;
  if v_inv.customer_id is null then
    return jsonb_build_object('skipped', true, 'reason', 'no customer'); end if;

  -- 356: money can move between credit lines without any payment changing: a
  -- correction withdraws a discount, raises a price or adds a line, and the
  -- money queue shifts. Released credit above the money that now counts toward
  -- its line goes back first (unspent credit only; credit already spent stays,
  -- as credit ahead of payment), so the release below never hands the same
  -- money out twice. An invoice with money refunded keeps the refund's rules
  -- (refunding part of an open invoice does not take released credit back; see
  -- NOT CHANGED), not just in the refund's own transaction: the money queue
  -- does not know which line a refund was for, so capping to it afterwards
  -- would take credit back at the next payment. Settlement squares it.
  if not exists (select 1 from public.invoice_refunds r join public.invoices ri on ri.id = r.invoice_id
                  where r.invoice_id = p_invoice_id
                    and (ri.reopened_at is null or r.created_at > ri.reopened_at)) then
    perform public.trim_released_paid_credit(p_invoice_id, 'Released credit above the money counted toward the line', true);
  end if;

  for v_it in
    select * from public.invoice_items
     where invoice_id = p_invoice_id
       -- 356: premium bundles release their paid credit as the money arrives,
       -- exactly as credit packages have since 327.
       and line_kind in ('credit_package','premium_bundle')
       -- Once the full issuance has run the line is settled; both branches of
       -- trg_create_therapy_on_paid fire on the final payment.
       and credit_issued_at is null
       -- Split lines of either kind keep full-payment issuance.
       and credit_split_allocation_id is null
       and bundle_split_allocation_id is null
       and not exists (select 1 from public.invoice_credit_splits s where s.invoice_item_id = invoice_items.id)
     order by id
     for update
  loop
    v_entitled := public.credit_line_paid_entitlement(v_it.id);
    if v_entitled <= 0 then continue; end if;
    v_target  := least(public.credit_package_money_toward_line(v_it.id), v_entitled);
    v_already := public.credit_package_released_paid_credit(v_it.id);
    v_delta   := round(v_target - v_already, 2);
    if v_delta <= 0 then continue; end if;
    -- 476 (the Owner, 27 Oct 2026: "Same as paid-in-full", answers A and B):
    -- the credit goes to whoever holds the package's benefits now
    -- (credit_line_benefits_holder): the holder of what this line released
    -- before; for a line that released nothing yet, of what the lines sold
    -- with it released (the invoice's own sale, or one correction's lines). So
    -- after a 'keep' change it stays with the buyer (only the invoice's
    -- customer changes), and after a 'transfer' change it goes where the
    -- benefits went. The invoice's customer where nothing was released yet
    -- by the line or the lines sold with it (a line a correction added after
    -- money was received: the customer who pays for it), or where what was
    -- released is held by more than one customer (split before 476; for the
    -- Owner).
    v476_to := coalesce(public.credit_line_benefits_holder(v_it.id), v_inv.customer_id);

    if v_it.line_kind = 'credit_package' then
      select * into pk from public.credit_packages where id = v_it.credit_package_id;
      if not found then continue; end if;
      -- The same restrictions the full issuer snapshots.
      select coalesce(array_agg(voucher_id), '{}') into v_vouchers
        from public.credit_package_vouchers where package_id = pk.id;
      v_restrict := jsonb_build_object('allowed_purposes', public.credit_package_purposes(pk.id),
                                       'source', 'credit_package');
      if array_length(v_vouchers, 1) is not null and not pk.allow_voucher then
        v_restrict := v_restrict || jsonb_build_object(
          'allowed_voucher_ids', (select jsonb_agg(v::text) from unnest(v_vouchers) v));
      end if;
      -- Provenance identical to the full issuance: 242 places it as
      -- package_paid, and 309 finds the package's own rules through it.
      v_lot := public.grant_customer_credit(
        v476_to, 'paid', v_delta, 'credit_package', pk.id, v_inv.store_id,
        public.sg_today(), null,
        'Credit package (paid so far): ' || pk.name, null, null, auth.uid(), v_restrict);
    else
      select * into pb from public.premium_bundles where id = v_it.premium_bundle_id;
      if not found then continue; end if;
      -- Exactly what sell_premium_bundle gives the bundle's paid credit at
      -- settlement: same source, same restriction. credit_lot_policy reads a
      -- premium_bundle lot with a source record as 'bundle_any', so it spends.
      v_restrict := jsonb_build_object(
        'allowed_purposes', jsonb_build_array('product','voucher','promotion','therapy','rental'),
        'allowed_voucher_ids', '[]'::jsonb, 'source', 'premium_bundle');
      v_lot := public.grant_customer_credit(
        v476_to, 'paid', v_delta, 'premium_bundle', pb.id, v_inv.store_id,
        public.sg_today(), null,
        'Premium bundle (paid so far): ' || pb.name, null, null, auth.uid(), v_restrict);
    end if;

    insert into public.credit_package_progress_lots (lot_id, invoice_item_id, invoice_id, released_amount)
    values (v_lot, v_it.id, p_invoice_id, v_delta);

    v_out := v_out || jsonb_build_object(
      'invoice_item_id', v_it.id, 'kind', v_it.line_kind, 'lot_id', v_lot, 'released', v_delta,
      'released_total', v_already + v_delta, 'entitled', v_entitled);
  end loop;

  return jsonb_build_object('released', v_out);
end
$function$
$d5$;
  c_def_issue constant text := $d6$CREATE OR REPLACE FUNCTION public.issue_credit_package(p_package_id uuid, p_customer_id uuid, p_store_id uuid, p_external_paid numeric, p_invoice_id uuid DEFAULT NULL::uuid, p_invoice_item_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  pk public.credit_packages%rowtype;
  v_vouchers uuid[]; v_lot uuid; v_bonus_lot uuid; v_sale uuid;
  v_qual numeric; v_units integer; v_group uuid; v_deadline date;
  v_restrict jsonb; v_rule public.therapy_package_rules; i integer;
  v_bonus numeric; v_credit numeric;
  v476_to uuid;  -- 476
begin
  select * into pk from public.credit_packages where id = p_package_id and deleted_at is null;
  if not found then raise exception 'Credit package not found'; end if;
  if p_customer_id is null then raise exception 'A customer is required to issue package credit'; end if;
  -- 355: without a line this is the full package (legacy and non-invoice paths).
  v_credit := coalesce(pk.paid_credit_amount, 0);
  -- 476 (the Owner, 27 Oct 2026: "Same as paid-in-full", answers A and B):
  -- settled from an invoice line, the package goes to whoever holds its
  -- benefits now (credit_line_benefits_holder: the holder of the credit the
  -- line released before full payment, or for a line that released nothing,
  -- of what the lines sold with it released), not to the invoice's
  -- customer: its paid credit not yet released and its Bonus, the sale record
  -- (credit_package_sales.customer_id, which the commission reads: when the
  -- invoice has no affiliate, that customer's referrer earns) and its reward
  -- vouchers. So after a 'keep' change all of it is the buyer's, as when the
  -- package was paid in full before the change. With nothing released by
  -- the line or the lines sold with it (a line a correction added after money
  -- was received), or what was released held by more than one customer, the
  -- customer it is given (the invoice's), as before. Without a line
  -- (sell_credit_package_with_vouchers, the legacy 141 split) nothing changes.
  v476_to := p_customer_id;
  if p_invoice_item_id is not null then
    v476_to := coalesce(public.credit_line_benefits_holder(p_invoice_item_id), p_customer_id);
  end if;

  select coalesce(array_agg(voucher_id), '{}') into v_vouchers
    from public.credit_package_vouchers where package_id = p_package_id;

  -- The category set is SNAPSHOTTED here. Editing the package later cannot
  -- change what already-issued credit is allowed to buy.
  v_restrict := jsonb_build_object(
    'allowed_purposes', public.credit_package_purposes(p_package_id),
    'source', 'credit_package');

  -- Enabling the voucher category allows every active sellable voucher, so no
  -- voucher id list is attached; an explicit list is only kept when the
  -- package was configured with one.
  if array_length(v_vouchers, 1) is not null and not pk.allow_voucher then
    v_restrict := v_restrict || jsonb_build_object(
      'allowed_voucher_ids', (select jsonb_agg(v::text) from unnest(v_vouchers) v));
  end if;

  -- 327: whatever this invoice already released as it was paid down is credit
  -- the customer is holding now. Grant the remainder only.
  declare v_released numeric := 0; v_remaining numeric;
  begin
    if p_invoice_item_id is not null then
      -- 355: this line's own entitlement (what was actually paid for it), less
      -- what THIS line has already released — never another line's.
      v_credit := public.credit_line_paid_entitlement(p_invoice_item_id);
      v_released := public.credit_package_released_paid_credit(p_invoice_item_id);
    elsif p_invoice_id is not null then
      select coalesce(sum(public.credit_package_released_paid_credit(it.id)), 0) into v_released
        from public.invoice_items it
       where it.invoice_id = p_invoice_id
         and it.line_kind = 'credit_package'
         and it.credit_package_id = p_package_id
         and it.credit_split_allocation_id is null;
    end if;
    v_remaining := round(v_credit - v_released, 2);
    if v_remaining > 0 then
      v_lot := public.grant_customer_credit(
        v476_to, 'paid', v_remaining, 'credit_package', p_package_id, p_store_id,
        public.sg_today(), null, 'Credit package: ' || pk.name, null, null, auth.uid(), v_restrict);
    end if;
  end;

  -- Bonus Credit, spendable on everything ordinary.
  v_bonus := public.credit_package_bonus_amount(p_package_id);
  if v_bonus > 0 then
    v_bonus_lot := public.grant_customer_credit(
      v476_to, 'bonus', v_bonus, 'credit_package', p_package_id, p_store_id,
      public.sg_today(), null, 'Credit package bonus: ' || pk.name, null, null, auth.uid(),
      jsonb_build_object('allowed_purposes', public.bonus_credit_purposes(),
                         'source', 'credit_package_bonus'));
  end if;

  v_rule := public.legacy_lowest_rule(p_store_id, public.sg_today());
  v_qual := coalesce(pk.reward_qualifying_amount, v_rule.qualifying_amount, 994);

  -- Reward units come from the CUSTOMER PRICE, not the credit issued: the
  -- customer is rewarded for what they spent, not for the credit they hold.
  v_units := case
    when not coalesce(pk.grants_reward, false) then 0
    when v_qual > 0 then floor(coalesce(pk.customer_price,0) / v_qual)::integer
    else 0 end;

  insert into public.credit_package_sales (
    package_id, customer_id, store_id, invoice_id, package_name_snapshot,
    price_snapshot, credit_snapshot, classification_snapshot,
    tier1_rate_snapshot, tier2_rate_snapshot, staff_rate_snapshot,
    reward_qualifying_snapshot, eligible_voucher_ids, external_paid,
    credit_lot_id, reward_units, created_by)
  values (p_package_id, v476_to, p_store_id, p_invoice_id, pk.name,
    pk.customer_price, v_credit, pk.commission_classification,
    pk.tier1_rate, pk.tier2_rate, pk.staff_commission_rate,
    v_qual, v_vouchers, coalesce(p_external_paid,0), v_lot, v_units, auth.uid())
  returning id into v_sale;

  if v_units > 0 then
    v_group := md5('credit_pkg:' || v_sale::text)::uuid;
    v_deadline := public.sg_today() + coalesce(v_rule.activation_deadline_days, 365);
    for i in 1 .. v_units loop
      insert into public.therapy_entitlements (
        entitlement_no, customer_id, store_id, rule_id, package_name,
        entitlement_kind, duration_months, voucher_qty, qualifying_amount,
        qualified_value, forfeited_value, activation_deadline, status,
        created_by, qualification_group_id, earner_kind,
        eligible_voucher_ids, claim_source_type, claim_source_invoice_id)
      values (public.next_legacy_entitlement_no(), v476_to, p_store_id, null,
        'Credit package reward — ' || pk.name,
        'voucher', coalesce(v_rule.duration_months, 1), 10, v_qual,
        v_qual, round(coalesce(pk.customer_price,0) - (v_units * v_qual), 2), v_deadline,
        'pending_activation', auth.uid(), v_group, 'credit_package',
        v_vouchers, 'credit_package', p_invoice_id);
    end loop;
  end if;

  perform public.write_audit_ex('credit_package_sales', v_sale, 'credit_package_issued', null,
    jsonb_build_object('package', pk.name, 'credit', v_credit,
      'bonus', v_bonus, 'external_paid', p_external_paid, 'reward_units', v_units,
      'purposes', public.credit_package_purposes(p_package_id)), 'credit', null, p_store_id);

  update public.credit_package_sales set bonus_credit_lot_id=v_bonus_lot,original_sources_verified_at=now(),original_sources_evidence='Exact paid/bonus lot IDs recorded by the issuing transaction' where id=v_sale;
  return jsonb_build_object('sale_id', v_sale, 'credit_lot_id', v_lot,
    'bonus_lot_id', v_bonus_lot, 'credit_issued', v_credit,
    'bonus_issued', v_bonus, 'reward_units', v_units,
    'grants_reward', coalesce(pk.grants_reward,false),
    'qualifying_amount', v_qual,
    'remainder', case when v_units > 0
                 then round(coalesce(pk.customer_price,0) - (v_units * v_qual), 2) else 0 end);
end $function$
$d6$;
  c_def_bundle constant text := $d7$CREATE OR REPLACE FUNCTION public.sell_premium_bundle(p_bundle_id uuid, p_customer_id uuid, p_store_id uuid, p_payments jsonb, p_voucher_selections jsonb, p_discount numeric DEFAULT 0, p_foc_amount numeric DEFAULT 0, p_invoice_id uuid DEFAULT NULL::uuid, p_is_completed_foc boolean DEFAULT false, p_invoice_item_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  b public.premium_bundles%rowtype;
  v_check jsonb; v_external numeric := 0; v_p jsonb; v_due numeric;
  v_paid_lot uuid; v_bonus_lot uuid; v_sale uuid; v_restrict jsonb;
  v_sel jsonb; v_vid uuid; v_qty integer; v_stock integer; v_issued integer := 0;
  v_vouchers uuid[]; v_qual numeric; v_units integer; v_remainder numeric;
  v_comm jsonb; v_paid_total numeric; v_paid_credit numeric;
  v476_to uuid;  -- 476
begin
  select * into b from public.premium_bundles where id = p_bundle_id and deleted_at is null;
  if not found then raise exception 'Premium bundle not found'; end if;
  if p_customer_id is null then raise exception 'A customer is required'; end if;
  if not exists (select 1 from public.premium_bundles_for_store(p_store_id) x where x.id = p_bundle_id) then
    raise exception 'That premium bundle is not available at this store'; end if;

  -- The bundle itself is a paid offer: wallet credit may not fund it.
  for v_p in select * from jsonb_array_elements(coalesce(p_payments,'[]'::jsonb)) loop
    if coalesce(v_p->>'method','') = 'wallet_credit' or (v_p->>'use_wallet_credit')::boolean is true then
      raise exception 'A premium bundle cannot be paid for with wallet credit';
    end if;
    v_external := v_external + coalesce((v_p->>'amount')::numeric, 0);
  end loop;

  -- Validate the chosen mixture and its stock BEFORE anything is committed.
  v_check := public.validate_bundle_voucher_selection(p_bundle_id, p_store_id, p_voucher_selections);
  if (v_check->>'selected_qty')::int > (v_check->>'required_qty')::int then
    raise exception 'That is more reward voucher(s) than this bundle grants — % available, % chosen',
      v_check->>'required_qty', v_check->>'selected_qty';
  end if;
  if not (v_check->>'stock_ok')::boolean then
    raise exception 'Payment blocked — not enough voucher stock: %',
      array_to_string(array(select jsonb_array_elements_text(v_check->'shortages')), '; ');
  end if;

  -- Money due after discount and any FOC portion.
  v_due := greatest(round(b.customer_payment_amount - coalesce(p_discount,0) - coalesce(p_foc_amount,0), 2), 0);
  -- 355: sold on an invoice, the line's own charge after its discount and
  -- FOC is what is due, and its paid credit is what was actually paid. Before
  -- this the discount was ignored here, so a discounted bundle was refused.
  v_paid_total := coalesce(b.paid_credit_amount, 0);
  if p_invoice_item_id is not null then
    v_due := public.invoice_item_external_value(p_invoice_item_id);
    v_paid_total := public.credit_line_paid_entitlement(p_invoice_item_id);
  end if;
  v_paid_credit := greatest(round(v_paid_total - case when p_invoice_item_id is null then 0
    else public.credit_package_released_paid_credit(p_invoice_item_id) end, 2), 0);
  -- 476 (the Owner, 27 Oct 2026: "Same as paid-in-full", answers A and B):
  -- settled from an invoice line, the bundle goes to whoever holds its
  -- benefits now (credit_line_benefits_holder: the holder of the credit the
  -- line released before full payment, or for a line that released nothing,
  -- of what the lines sold with it released), not to the invoice's
  -- customer: its paid credit not yet released and its Bonus, the sale record
  -- (premium_bundle_sales.customer_id, which the commission below reads: when
  -- the invoice has no affiliate, that customer's referrer earns), the
  -- vouchers chosen at the till and the allowance of those still to choose.
  -- So after a 'keep' change all of it is the buyer's, as when the bundle was
  -- paid in full before the change. With nothing released by the line or the
  -- lines sold with it (a line a correction added after money was received),
  -- or what was released held by more than one customer, the customer it is
  -- given (the invoice's), as before. The vouchers' stock is the invoice's
  -- store's, as before.
  v476_to := p_customer_id;
  if p_invoice_item_id is not null then
    v476_to := coalesce(public.credit_line_benefits_holder(p_invoice_item_id), p_customer_id);
  end if;
  if not coalesce(p_is_completed_foc,false) and round(v_external,2) < v_due then
    raise exception 'The bundle needs % but only % was paid externally', v_due, round(v_external,2);
  end if;

  select coalesce(array_agg(voucher_id),'{}') into v_vouchers
    from public.premium_bundle_vouchers where bundle_id = p_bundle_id;

  -- Bundle credit is broadly usable, but never on another credit product.
  v_restrict := jsonb_build_object(
    'allowed_purposes', jsonb_build_array('product','voucher','promotion','therapy','rental'),
    'allowed_voucher_ids', '[]'::jsonb, 'source', 'premium_bundle');

  if v_paid_credit > 0 then
    v_paid_lot := public.grant_customer_credit(v476_to, 'paid', v_paid_credit,
      'premium_bundle', p_bundle_id, p_store_id, public.sg_today(), null,
      'Premium bundle: ' || b.name, null, null, auth.uid(), v_restrict);
  end if;
  if b.bonus_credit_amount > 0 then
    v_bonus_lot := public.grant_customer_credit(v476_to, 'bonus', b.bonus_credit_amount,
      'premium_bundle', p_bundle_id, p_store_id, public.sg_today(), null,
      'Premium bundle bonus: ' || b.name, null, null, auth.uid(), v_restrict);
  end if;

  v_qual := coalesce(b.reward_qualifying_amount, 994);
  v_units := case when v_qual > 0 then floor(b.customer_payment_amount / v_qual)::integer else 0 end;
  v_remainder := round(b.customer_payment_amount - (v_units * v_qual), 2);

  insert into public.premium_bundle_sales (
    bundle_id, customer_id, store_id, invoice_id, bundle_name_snapshot,
    payment_snapshot, paid_credit_snapshot, bonus_credit_snapshot, voucher_qty_snapshot,
    classification_snapshot, tier1_rate_snapshot, tier2_rate_snapshot, staff_rate_snapshot,
    reward_qualifying_snapshot, forfeited_remainder, eligible_voucher_ids,
    external_paid, paid_credit_lot_id, bonus_credit_lot_id, created_by)
  values (p_bundle_id, v476_to, p_store_id, p_invoice_id, b.name,
    b.customer_payment_amount, v_paid_total, b.bonus_credit_amount, b.free_voucher_qty,
    b.commission_classification, b.tier1_rate, b.tier2_rate, b.staff_commission_rate,
    v_qual, v_remainder, v_vouchers, round(v_external,2), v_paid_lot, v_bonus_lot, auth.uid())
  returning id into v_sale;

  -- Issue the reward vouchers immediately and deduct stock. Vouchers never expire.
  for v_sel in select * from jsonb_array_elements(coalesce(p_voucher_selections,'[]'::jsonb)) loop
    v_vid := (v_sel->>'voucher_id')::uuid;
    v_qty := coalesce((v_sel->>'quantity')::integer, 0);
    if v_qty <= 0 then continue; end if;
    if exists (select 1 from public.vouchers where id = v_vid and qty_type <> 'unlimited') then
      select current_qty into v_stock from public.voucher_store_stock
       where voucher_id = v_vid and store_id = p_store_id for update;
      if coalesce(v_stock,0) < v_qty then
        raise exception 'Payment blocked — stock of "%" ran out',
          (select name from public.vouchers where id = v_vid); end if;
      update public.voucher_store_stock set current_qty = current_qty - v_qty, updated_at = now()
       where voucher_id = v_vid and store_id = p_store_id;
    end if;
    insert into public.customer_reward_vouchers
      (customer_id, voucher_id, entitlement_id, store_id, quantity, issued_by, notes,
       source_type, source_id)
    values (v476_to, v_vid, null, p_store_id, v_qty, auth.uid(),
      'Premium bundle reward — never expires, not transferable', 'premium_bundle', v_sale);
    v_issued := v_issued + v_qty;
  end loop;

  update public.premium_bundle_sales set vouchers_issued = v_issued where id = v_sale;

  -- bundle_deferred_single: whatever was not chosen at the till is still owed,
  -- and stays claimable until the deadline. Dated from this purchase.
  if coalesce(b.free_voucher_qty,0) - v_issued > 0 then
    insert into public.therapy_entitlements (
      entitlement_no, customer_id, store_id, rule_id, package_name,
      entitlement_kind, duration_months, voucher_qty, qualifying_amount,
      qualified_value, forfeited_value, activation_deadline, status,
      created_by, qualification_group_id, earner_kind,
      eligible_voucher_ids, claim_source_type, claim_source_invoice_id)
    values (public.next_legacy_entitlement_no(), v476_to, p_store_id, null,
      'Premium bundle reward — ' || b.name,
      'voucher', 1, coalesce(b.free_voucher_qty,0) - v_issued, 0,
      coalesce(b.customer_payment_amount,0), 0,
      (public.sg_today() + interval '1 year')::date,
      'pending_activation', auth.uid(),
      md5('bundle_sale:' || v_sale::text)::uuid, 'premium_bundle',
      (select coalesce(array_agg(voucher_id),'{}') from public.premium_bundle_vouchers where bundle_id = b.id),
      'premium_bundle', p_invoice_id);
  end if;

  v_comm := public.earn_premium_bundle_commission(v_sale);

  perform public.write_audit_ex('premium_bundle_sales', v_sale, 'premium_bundle_sold', null,
    jsonb_build_object('bundle', b.name, 'paid_credit', v_paid_total,
      'bonus_credit', b.bonus_credit_amount, 'vouchers', v_issued,
      'external_paid', round(v_external,2)), 'credit', null, p_store_id);

  return jsonb_build_object('sale_id', v_sale,
    'paid_credit', v_paid_total, 'bonus_credit', b.bonus_credit_amount,
    'vouchers_issued', v_issued, 'voucher_entitlement', b.free_voucher_qty,
    'qualifying_amount', v_qual, 'reward_units', v_units, 'forfeited_remainder', v_remainder,
    'external_paid', round(v_external,2), 'commission', v_comm);
end $function$
$d7$;
  c_def_pkgprev constant text := $d8$CREATE OR REPLACE FUNCTION public.invoice_package_commission_preview(p_invoice_id uuid)
 RETURNS TABLE(o_invoice_item_id uuid, o_buyer uuid, o_referrer uuid, o_tier text, o_product_type text, o_line_amount numeric, o_rate numeric, o_amount numeric, o_status text, o_block_reason text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 357: what package/bundle settlement commission is, for the instalment layer.
declare v_inv public.invoices%rowtype; v_it record; v_t1 uuid; v_t2 uuid; v_cls text;
        v_r1 numeric; v_r2 numeric; v_base numeric; v_a1 numeric; v_a2 numeric;
        v476_buyer uuid;  -- 476
begin
  select * into v_inv from public.invoices i where i.id = p_invoice_id;
  if not found then return; end if;
  if v_inv.affiliate_selection_explicit and v_inv.affiliate_id is null then return; end if;
  v_cls := public.package_commission_classification();

  for v_it in
    select ii.id as item_id, coalesce(cp.tier1_rate, pb.tier1_rate) as def_r1,
           coalesce(cp.tier2_rate, pb.tier2_rate) as def_r2,
           ii.credit_issued_at is null as unsettled   -- 476
      from public.invoice_items ii
      left join public.credit_packages cp on cp.id = ii.credit_package_id
      left join public.premium_bundles pb on pb.id = ii.premium_bundle_id
     where ii.invoice_id = p_invoice_id
       and ii.line_kind in ('credit_package','premium_bundle')
       -- A legacy one-line split issues to several customers; it earns at settlement.
       and not exists (select 1 from public.invoice_credit_splits s where s.invoice_item_id = ii.id)
     order by ii.id
  loop
    -- 476 (the Owner, 27 Oct 2026, answer B: "the commission follows the
    -- credit to the buyer"): a line not yet settled is the buyer's who holds
    -- its benefits (credit_line_benefits_holder), as its settlement will make
    -- its sale record (issue_credit_package, sell_premium_bundle), so the
    -- part-payment layer holds what the settlement will earn, for the same
    -- referrer: after a 'keep' change, the buyer's referrer when the invoice
    -- has no affiliate. Otherwise, and for a settled line, the invoice's
    -- customer, as before. Each line is read on its own: before, the
    -- referrer was read once, for the invoice's customer.
    v476_buyer := v_inv.customer_id;
    if v_it.unsettled then
      v476_buyer := coalesce(public.credit_line_benefits_holder(v_it.item_id), v_inv.customer_id);
    end if;
    if v_inv.affiliate_id is not null then
      select a.customer_id into v_t1 from public.customer_affiliates a where a.id = v_inv.affiliate_id;
    else
      select c.referred_by into v_t1 from public.customers c where c.id = v476_buyer;
    end if;
    if v_t1 is null or v_t1 = v476_buyer then continue; end if;
    v_t2 := null;
    select c.referred_by into v_t2 from public.customers c where c.id = v_t1;
    select coalesce(v_it.def_r1, case when v_cls = 'third_party' then a.commission_tier1_third_rate else a.commission_tier1_own_rate end),
           coalesce(v_it.def_r2, case when v_cls = 'third_party' then a.commission_tier2_third_rate else a.commission_tier2_own_rate end)
      into v_r1, v_r2 from public.app_settings a where a.id = true;
    v_base := public.invoice_item_external_value(v_it.item_id);
    v_a1 := round(v_base * v_r1 / 100.0, 2);
    if coalesce(v_a1, 0) <= 0 then continue; end if;
    -- 'earned', as the package functions record it today (they do not check activation).
    return query select v_it.item_id, v476_buyer, v_t1, 'tier1'::text, v_cls, v_base, v_r1, v_a1, 'earned'::text, null::text;
    if v_t2 is not null then
      v_a2 := round(v_a1 * v_r2 / 100.0, 2);
      if v_a2 > 0 then
        return query select v_it.item_id, v476_buyer, v_t2, 'tier2'::text, v_cls, v_a1, v_r2, v_a2, 'earned'::text, null::text;
      end if;
    end if;
  end loop;
end $function$
$d8$;

  -- ══ Relied on, not changed (a copy of production at 475, 27 Oct 2026):
  -- what the nine call; who calls them; the holder rules and what writes
  -- what they read; what writes the lines and revisions the marker reads;
  -- the release record's readers and writers; the settlement and the
  -- commission it earns; a merge, an Owner's Move, 472's forwarder, 475's
  -- reopening; and what the self-test calls ══════════════════════════════
  c_relied constant text[] := array[
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)',
    'preview_invoice_correction(uuid,jsonb)',
    'invoice_benefit_unused_elsewhere(uuid)',
    'invoice_benefit_moved_to_other(uuid)',
    'invoice_benefit_moved_from_spent(uuid)',
    'invoice_credit_lot_ids(uuid)',
    'credit_lot_chain(uuid)',
    'credit_lot_current(uuid)',
    'credit_lot_ancestry(uuid)',
    'require_store_access(uuid)',
    'invoice_line_label(uuid)',
    'invoice_own_voucher_ids(uuid)',
    'entitlement_claimed_qty(uuid)',
    'capture_invoice_benefit_values(uuid)',
    'record_invoice_benefit_values(uuid,jsonb,text)',
    'credit_package_released_paid_credit(uuid)',
    'credit_line_paid_entitlement(uuid)',
    'credit_package_money_toward_line(uuid)',
    'credit_package_bonus_amount(uuid)',
    'invoice_item_external_value(uuid)',
    'trim_released_paid_credit(uuid,text,boolean)',
    'writeoff_released_credit_on_close(uuid,text,text)',
    'repair_credit_package_progress_lots()',
    'reclaim_released_credit_of_removed_lines(uuid,jsonb,text)',
    'invoice_credit_live_holder(uuid,uuid,timestamp with time zone)',
    'invoice_benefits_holder(uuid,uuid,timestamp with time zone)',
    'grant_customer_credit(uuid,text,numeric,text,uuid,uuid,date,text,text,text,date,uuid,jsonb)',
    'ensure_customer_wallet(uuid)',
    'issue_credit_lines_for_invoice(uuid)',
    'trg_create_therapy_on_paid()',
    'sell_credit_package_with_vouchers(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid)',
    'issue_credit_package_invoice_item(uuid)',
    'issue_premium_bundle_invoice_item(uuid)',
    'validate_bundle_voucher_selection(uuid,uuid,jsonb)',
    'earn_credit_package_commission(uuid)',
    'earn_premium_bundle_commission(uuid)',
    'earn_invoice_commission(uuid)',
    'invoice_package_retained_commission_basis(text,uuid,numeric)',
    'package_commission_classification()',
    'reconcile_invoice_commissions(uuid,text)',
    'sync_instalment_commissions(uuid,text,date,boolean,boolean)',
    'invoice_instalment_commission_targets(uuid)',
    'invoice_instalment_commission_active(uuid)',
    'transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)',
    'merge_customer_records(uuid,uuid,text,uuid)',
    'credit_given_back_follows(uuid)',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'reopen_invoice(uuid,text,uuid)',
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'apply_reopened_invoice_benefits()',
    'correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)',
    'reverse_credit_lot(uuid,text,text,text)',
    'delete_customer(uuid,text,text)',
    'allocate_invoice_wallet_credit(uuid,numeric,text,text)',
    'invoice_reopen_preview(uuid)',
    'invoice_reopen_preview_before_sessions(uuid)',
    'invoice_financial_position(uuid)',
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    'record_invoice_payment(uuid,jsonb,uuid)'];
  c_relied_md5 constant text[] := array[
    '04d647e13e9424a9375942e5812e91a2',
    '1f034561a461bdb46a1e6274e0d04606',
    'f26752231c100461e11caddc03c98a33',
    'd35d7c8ae7187985ea64f8a5c38a7d79',
    '7016bed898e1bbe9d0ac4a05037d07c2',
    '901fde963b051cfd93fcd9f7dab7149e',
    '50346a2e9aea50b31d4207c43b2f197c',
    '556e725784154cbffc23d3ad900f9366',
    'd48fb24e6eb9733d7f867e42fa703e7b',
    '52b3cae789b6b52a12bb2f798af40cbe',
    'f9332fd2f0092337d64501d8a647c23f',
    'a9ba8c6cb4632087e3e9ac297d998ff5',
    'ee0202627b9500dcbad103d3ade2401f',
    '89b08265d5303e890569e953d83d2440',
    'd5e061945c2921a1af86f8c99a349e98',
    '931af0352136ab39689af21a993f67b3',
    '6b27388462747e3c13f3da0b9ad165c0',
    'da2404a1db281b46a44231bd071a069a',
    '798c2d67d55bb1d140232ff06ffb1034',
    '45031fdc18cdc6ed4a3e2a8275a8cbd5',
    'e1d12f5bf03e92e669d139f0405362af',
    '14ded4342c3e65eb98547d224263519f',
    '284a89cfb965e8028136b5f8a4f2bf08',
    'ebd2a1a9f8ce7a9c1c272168b30b5ce3',
    '823cd6a96c813b43bf2767dc1644e943',
    'a5692590ef3e8a7a7dd7e8ff7cfa9568',
    '55995ff6e1ffd4a1172cb930512a34b0',
    'ac0de5530624ee533aacf93aec389910',
    '8ef18daebbbe3c12f2024290ea8416e8',
    '303f45e12e88b8de58e95aa0f877b875',
    '012ae4e305b9870fa5596f740c0427b9',
    '2d1e5eaf623ea56835c528df8ad418e9',
    '08caec99c467334527af99eee5e6b00e',
    '9981515e45c3e79a41d36f96acbf000b',
    '16e707758a4d771c49c403ef8983570f',
    '13ce59fd892c027338a41de4113ae55d',
    'b75ffbea70fd020e75d1ddf4f7b06ba1',
    '6156b2e1ee51da5146a5a7acc16091ce',
    '74b5e488d656af58a2e3f41c58eb365f',
    '08db9563fd4213315b16b891a53ead7b',
    '3c267728e215d17ebeb9cfe9cb7db47c',
    '88d7b122778801a0d5eea0b6dd8395b7',
    'dc47c3c7b9e41d67b89713fce2a4b480',
    '1cfc14db26aaef668cee010fadbddfe3',
    '7aebd7120bc3928db46df0941cb20889',
    'ba05c2b1fb4c0e14d369c01d06a635b0',
    'f2a7a4d1ca28f0865b14e3f1e5e02bbb',
    'de52d9dbaef8ab15163bef35cb9d733d',
    '30066e137b9b75b5789a050c14debc04',
    '804ecd829cfecf713783a09a05d93c7e',
    '36eaa7224e514d3e7e42e3eeb51acfb5',
    'af99337094edb6d73b9cc0ae00fbf138',
    '10c1a3d8e3bb003fbaf01cf879f97c5e',
    '5b407735574fc3cacd8067c4dc8213f4',
    'da8aa986c92d765a8028741f33bf56b0',
    'e09ebf9c0841ef5463f96b26f4933541',
    '7e1ef2d25415e69b3f770fe2efd45190',
    'ba7eccbfeff217c8b1969b0e55a010ca',
    '80c80d386a5241e63b353e35e13ef250',
    '9c70097ed4da614fb9dcc66fdfcdb7d6'];
  -- Who calls the six; who grants credit, makes lots, writes the release
  -- record, adds invoice lines, writes revisions, writes the sale records,
  -- calls update_invoice_internal; what reads or writes the change's Audit
  -- Log row the holder rule reads (by name; a session's own temporary
  -- functions, the function itself and the three this adds are not
  -- counted), as read on a copy of production at 475.
  c_callers constant text[] := array[
    'correct_invoice(uuid,jsonb,jsonb,text,uuid), move_invoice_benefits_to_customer(uuid,uuid,uuid,text), preview_invoice_correction(uuid,jsonb)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid), trg_create_therapy_on_paid()',
    'issue_credit_lines_for_invoice(uuid), sell_credit_package_with_vouchers(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid)',
    'issue_credit_lines_for_invoice(uuid)',
    'invoice_instalment_commission_targets(uuid)'];
  c_granters constant text := 'add_legacy_credit(uuid,text,numeric,date,uuid,text,text,date,uuid), adjust_customer_credit(uuid,text,text,numeric,text,text,date,text,uuid,uuid), grant_exchange_credit(uuid,uuid,numeric,uuid,uuid,jsonb), issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid), issue_credit_package_invoice_item(uuid), issue_premium_bundle_invoice_item(uuid), release_credit_package_paid_credit(uuid), repair_credit_package_progress_lots(), sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid)';
  c_lot_writers constant text := 'apply_reopened_invoice_benefits(), credit_given_back_follows(uuid), grant_customer_credit(uuid,text,numeric,text,uuid,uuid,date,text,text,text,date,uuid,jsonb), merge_customer_records(uuid,uuid,text,uuid), move_invoice_benefits_to_customer(uuid,uuid,uuid,text), transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)';
  c_release_writers constant text := 'credit_given_back_follows(uuid), release_credit_package_paid_credit(uuid), repair_credit_package_progress_lots(), trim_released_paid_credit(uuid,text,boolean), writeoff_released_credit_on_close(uuid,text,text)';
  c_audit_readers constant text := 'invoice_benefits_holder(uuid,uuid,timestamp with time zone), move_invoice_benefits_to_customer(uuid,uuid,uuid,text)';
  c_line_writers constant text := 'add_therapy_line(uuid,uuid,text), create_credit_purchase_invoice(uuid,uuid,jsonb,uuid,numeric,text), create_exchange_invoice(uuid), create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb), create_split_credit_package_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid), create_split_premium_bundle_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid), create_topup_invoice(uuid,numeric,text), repair_create_invoice_package_branches(), return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text), update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)';
  c_revision_writers constant text := 'cancel_invoice_recorded(uuid,text,uuid), correct_invoice(uuid,jsonb,jsonb,text,uuid), reopen_invoice(uuid,text,uuid), set_invoice_affiliate(uuid,uuid), write_recovered_invoice_date(uuid,date,uuid,jsonb,jsonb,text,uuid)';
  c_sale_writers constant text := 'apply_reopened_invoice_benefits(), capture_invoice_benefit_values(uuid), credit_given_back_follows(uuid), issue_credit_package(uuid,uuid,uuid,numeric,uuid,uuid), issue_credit_package_invoice_item(uuid), issue_premium_bundle_invoice_item(uuid), merge_customer_records(uuid,uuid,text,uuid), move_invoice_benefits_to_customer(uuid,uuid,uuid,text), resolve_invoice_credit_rewards(uuid,text,uuid,boolean,uuid), sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid), verify_invoice_credit_sale_sources(uuid,uuid,boolean,text)';
  c_internal_callers constant text := 'correct_invoice(uuid,jsonb,jsonb,text,uuid)';
  -- The trigger that releases and settles a package line's credit.
  c_trg_def constant text := 'CREATE TRIGGER create_therapy_on_paid AFTER UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_create_therapy_on_paid()';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; n int; i int; v_first boolean; v_at_before int := 0; v_at_after int := 0; v_new_at int := 0;
  v_acl text[] := '{}'; v_have text[]; v_have2 text[];
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_pk uuid; t_pkb uuid; t_pb uuid; t_v uuid;
  t_svc uuid; t_wallet uuid; t_ra uuid; t_rb uuid;
  t_case int; t_a uuid; t_b uuid; t_inv uuid; t_s uuid; t_k int; t_err text; t_line jsonb; t_r jsonb; t_pay uuid;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The texts are the tested ones.
  if md5(c_def_group) <> c_new_after[1] or md5(c_def_holder) <> c_new_after[2] or md5(c_def_receivers) <> c_new_after[3]
     or md5(c_def_list) <> c_after[1] or md5(c_def_move) <> c_after[2] or md5(c_def_release) <> c_after[3]
     or md5(c_def_issue) <> c_after[4] or md5(c_def_bundle) <> c_after[5] or md5(c_def_pkgprev) <> c_after[6] then
    raise exception '476: the texts in this file are not the tested ones'; end if;

  -- The functions relied on are as read on a copy of production at 475.
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '476: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying (476 goes in after 475).',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  -- The trigger that releases and settles a package line's credit, as read.
  if (select string_agg(pg_get_triggerdef(t.oid), ' | ') from pg_trigger t
       where t.tgfoid = 'public.trg_create_therapy_on_paid()'::regprocedure and not t.tgisinternal) is distinct from c_trg_def then
    raise exception '476: the trigger that releases and settles package credit on invoices is not as read on 27 Oct 2026'; end if;

  -- The columns read, with these types.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('customer_credit_lots', 'id', 'uuid'), ('customer_credit_lots', 'customer_id', 'uuid'),
                 ('customer_credit_lots', 'status', 'text'), ('customer_credit_lots', 'remaining_amount', 'numeric(12,2)'),
                 ('customer_credit_lots', 'original_amount', 'numeric(12,2)'), ('customer_credit_lots', 'created_at', 'timestamp with time zone'),
                 ('customer_credit_lots', 'is_locked', 'boolean'),
                 ('credit_package_progress_lots', 'lot_id', 'uuid'), ('credit_package_progress_lots', 'invoice_id', 'uuid'),
                 ('credit_package_progress_lots', 'invoice_item_id', 'uuid'), ('credit_package_progress_lots', 'released_amount', 'numeric(12,2)'),
                 ('invoice_items', 'id', 'uuid'), ('invoice_items', 'invoice_id', 'uuid'), ('invoice_items', 'line_kind', 'invoice_line_kind'),
                 ('invoice_items', 'credit_issued_at', 'timestamp with time zone'), ('invoice_items', 'credit_split_allocation_id', 'uuid'),
                 ('invoice_items', 'bundle_split_allocation_id', 'uuid'), ('invoice_credit_splits', 'invoice_item_id', 'uuid'),
                 ('invoice_benefit_values', 'lot_id', 'uuid'), ('invoice_benefit_values', 'invoice_id', 'uuid'),
                 ('invoice_reopen_benefits', 'invoice_id', 'uuid'), ('invoice_reopen_benefits', 'applied_at', 'timestamp with time zone'),
                 ('invoice_reopen_benefits', 'amount', 'numeric(12,2)'), ('invoice_reopen_benefits', 'source_ledger_id', 'uuid'),
                 ('customer_credit_ledger', 'id', 'uuid'), ('customer_credit_ledger', 'lot_id', 'uuid'),
                 ('invoice_benefit_values', 'id', 'uuid'), ('invoice_benefit_values', 'created_at', 'timestamp with time zone'),
                 ('customers', 'deleted_at', 'timestamp with time zone'),
                 ('invoices', 'status', 'invoice_status'), ('invoices', 'customer_id', 'uuid'), ('invoices', 'store_id', 'uuid'),
                 ('invoices', 'paid_amount', 'numeric(12,2)'), ('invoices', 'locked_at', 'timestamp with time zone'),
                 ('invoices', 'affiliate_id', 'uuid'), ('invoices', 'affiliate_selection_explicit', 'boolean'),
                 ('invoice_revisions', 'invoice_id', 'uuid'), ('invoice_revisions', 'revision_no', 'integer'),
                 ('invoice_revisions', 'snapshot', 'jsonb'),
                 ('customers', 'id', 'uuid'), ('customers', 'full_name', 'text'), ('customers', 'referred_by', 'uuid'),
                 ('credit_package_sales', 'customer_id', 'uuid'), ('premium_bundle_sales', 'customer_id', 'uuid'),
                 ('customer_reward_vouchers', 'customer_id', 'uuid'), ('therapy_entitlements', 'customer_id', 'uuid')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '476: these columns are missing or not as read on 27 Oct 2026: %', v; end if;
  -- The revisions are written only by the functions read (no row policy
  -- lets a page write them), so what the marker reads is what they saved.
  if exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'invoice_revisions' and p.cmd <> 'SELECT')
     or has_table_privilege('authenticated', 'public.invoice_revisions', 'insert,update,delete')
        and exists (select 1 from pg_class c where c.oid = 'public.invoice_revisions'::regclass and not c.relrowsecurity) then
    raise exception '476: invoice revisions can be written by a page, not as read on 27 Oct 2026'; end if;

  -- No other function takes the names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname = any (c_names) and not (p.oid::regprocedure::text = any (c_sigs))
          or p.proname = any (c_new_names) and not (p.oid::regprocedure::text = any (c_new)));
  if v is not null then raise exception '476: another function takes the name of one this changes or adds: %', v; end if;

  -- Who calls the six; who grants credit and makes lots; who writes the
  -- release record; what reads the change's Audit Log row; who adds invoice
  -- lines, writes revisions or the sale records, and calls
  -- update_invoice_internal: as read (a new way would need the same care).
  -- Compared as sets (each sorted here), so the collation's order does not
  -- matter.
  for i in 1 .. cardinality(c_names) loop
    v_have := array(select p.oid::regprocedure::text
                      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                     where p.prosrc ~ (c_names[i] || '\s*\(') and ns.nspname not like 'pg\_temp\_%'
                       and p.proname <> c_names[i] and not (p.proname = any (c_new_names)) order by 1);
    if v_have is distinct from array(select x from unnest(string_to_array(c_callers[i], ', ')) x order by 1) then
      raise exception '476: the functions that call % are not as read on 27 Oct 2026 (%); check whom each gives credit to, then re-test',
        c_names[i], array_to_string(v_have, ', '); end if;
  end loop;
  v_have := array(select p.oid::regprocedure::text
                    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                   where p.prosrc ~ 'grant_customer_credit\s*\(' and ns.nspname not like 'pg\_temp\_%'
                     and p.proname <> 'grant_customer_credit' order by 1);
  v_have2 := array(select p.oid::regprocedure::text
                     from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                    where p.prosrc ~* 'insert\s+into\s+public\.customer_credit_lots' and ns.nspname not like 'pg\_temp\_%' order by 1);
  if v_have is distinct from array(select x from unnest(string_to_array(c_granters, ', ')) x order by 1)
     or v_have2 is distinct from array(select x from unnest(string_to_array(c_lot_writers, ', ')) x order by 1) then
    raise exception '476: what grants credit or makes a credit lot is not as read on 27 Oct 2026 (% / %); check whom it gives a package line''s credit to, then re-test',
      array_to_string(v_have, ', '), array_to_string(v_have2, ', '); end if;
  v_have := array(select p.oid::regprocedure::text
                    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                   where p.prosrc ~* '(insert\s+into|update)\s+public\.credit_package_progress_lots' and ns.nspname not like 'pg\_temp\_%' order by 1);
  v_have2 := array(select p.oid::regprocedure::text
                     from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                    where p.prosrc ~ 'invoice_benefits_followed_reassignment' and ns.nspname not like 'pg\_temp\_%' order by 1);
  if v_have is distinct from array(select x from unnest(string_to_array(c_release_writers, ', ')) x order by 1)
     or v_have2 is distinct from array(select x from unnest(string_to_array(c_audit_readers, ', ')) x order by 1) then
    raise exception '476: what writes the release record, or reads or writes the customer change''s Audit Log row, is not as read on 27 Oct 2026 (% / %); check whom the holder rule names, then re-test',
      array_to_string(v_have, ', '), array_to_string(v_have2, ', '); end if;
  v_have := array(select p.oid::regprocedure::text
                    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                   where p.prosrc ~* 'insert\s+into\s+public\.invoice_items' and ns.nspname not like 'pg\_temp\_%' order by 1);
  v_have2 := array(select p.oid::regprocedure::text
                     from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                    where p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+public\.invoice_revisions' and ns.nspname not like 'pg\_temp\_%' order by 1);
  if v_have is distinct from array(select x from unnest(string_to_array(c_line_writers, ', ')) x order by 1)
     or v_have2 is distinct from array(select x from unnest(string_to_array(c_revision_writers, ', ')) x order by 1) then
    raise exception '476: what adds invoice lines or writes invoice revisions is not as read on 27 Oct 2026 (% / %); check that a line added to an invoice is still saved in a revision first, then re-test',
      array_to_string(v_have, ', '), array_to_string(v_have2, ', '); end if;
  v_have := array(select p.oid::regprocedure::text
                    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                   where p.prosrc ~ 'update_invoice_internal\s*\(' and ns.nspname not like 'pg\_temp\_%'
                     and p.proname <> 'update_invoice_internal' order by 1);
  v_have2 := array(select p.oid::regprocedure::text
                     from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                    where p.prosrc ~* '(insert\s+into|update)\s+public\.(credit_package_sales|premium_bundle_sales)' and ns.nspname not like 'pg\_temp\_%'
                      and not (p.proname = any (c_new_names)) order by 1);
  if v_have is distinct from array(select x from unnest(string_to_array(c_internal_callers, ', ')) x order by 1)
     or v_have2 is distinct from array(select x from unnest(string_to_array(c_sale_writers, ', ')) x order by 1) then
    raise exception '476: what calls update_invoice_internal or writes the package and bundle sale records is not as read on 27 Oct 2026 (% / %); check whose sale record and commission it gives, then re-test',
      array_to_string(v_have, ', '), array_to_string(v_have2, ', '); end if;

  -- The six: all at their BEFORE and the three new ones absent (replaced,
  -- made), or all at their AFTER and the three at their AFTER (left alone).
  for i in 1 .. cardinality(c_sigs) loop
    d := md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[i])));
    if d = c_before[i] then v_at_before := v_at_before + 1;
    elsif d = c_after[i] then v_at_after := v_at_after + 1;
    else
      raise exception '476: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sigs[i], d;
    end if;
  end loop;
  for i in 1 .. cardinality(c_new) loop
    if to_regprocedure('public.' || c_new[i]) is not null
       and md5(pg_get_functiondef(to_regprocedure('public.' || c_new[i]))) = c_new_after[i] then
      v_new_at := v_new_at + 1; end if;
  end loop;
  if v_at_before = cardinality(c_sigs)
     and not exists (select 1 from unnest(c_new) x where to_regprocedure('public.' || x) is not null) then
    v_first := true;
  elsif v_at_after = cardinality(c_sigs) and v_new_at = cardinality(c_new) then
    raise notice '476: the six functions and the three it adds are already this version; left alone';
    v_first := false;
  else
    raise exception '476: the functions are partly this version (% of 6 at their BEFORE, % at their AFTER; of the three it adds % at their AFTER, % present). Re-read them and re-test before applying.',
      v_at_before, v_at_after, v_new_at, (select count(*) from unnest(c_new) x where to_regprocedure('public.' || x) is not null);
  end if;

  -- ── On the first run: nothing is refused for the data (476 needs no
  -- decision before it goes in), but whose answer changes and what needs the
  -- Owner is named (the header's read-only query: 1, a 'transfer' change now
  -- refused; 2, 4, 6 and 8, what is given later now goes to the holder; 7, a
  -- 'transfer' change now moves the lot; 3, 5, for the Owner; 9, unchanged).
  if v_first then
    with
    -- the release records of package lines not settled, each followed to
    -- the lot it reaches now (credit_lot_current), whom 462's rule says
    -- holds it, and whether it reads as spent (473's test)
    pre as (
      select pl.invoice_id, pl.invoice_item_id, c.customer_id, c.remaining_amount,
             public.invoice_credit_live_holder(pl.invoice_id, c.customer_id, c.created_at) as holder,
             pl.released_amount > 0 and coalesce(case when c.status = 'active' then c.remaining_amount end, 0) < pl.released_amount as spent
        from public.credit_package_progress_lots pl
        join public.invoices i on i.id = pl.invoice_id and i.deleted_at is null
        join public.invoice_items it on it.id = pl.invoice_item_id and it.credit_issued_at is null
        join public.customer_credit_lots c on c.id = public.credit_lot_current(pl.lot_id)
       where not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = any (public.credit_lot_chain(pl.lot_id)))),
    -- each package or bundle line's sale, as 476's credit_line_sale_group works
    -- it out (0: the invoice's own sale; else the revision of the correction
    -- that added it once money had been received)
    grp as (
      select it.invoice_id, it.id as invoice_item_id,
             coalesce((select case when coalesce(r.snapshot->'invoice'->>'status', '') in ('draft', 'unpaid')
                                        and coalesce((r.snapshot->'invoice'->>'paid_amount')::numeric, 0) = 0
                                        and r.snapshot->'invoice'->>'locked_at' is null
                                   then 0 else r.revision_no end
                         from public.invoice_revisions r
                        where r.invoice_id = it.invoice_id and jsonb_typeof(r.snapshot->'items') = 'array'
                          and not (r.snapshot->'items' @> jsonb_build_array(jsonb_build_object('id', it.id)))
                        order by r.revision_no desc limit 1), 0) as sale
        from public.invoice_items it
        join public.invoices i on i.id = it.invoice_id and i.deleted_at is null
       where it.line_kind::text in ('credit_package', 'premium_bundle')),
    -- the unsettled package and bundle lines that released nothing yet, not
    -- split, of an invoice neither cancelled nor refunded
    bare0 as (
      select it.invoice_id, it.id as invoice_item_id, g.sale
        from public.invoice_items it
        join grp g on g.invoice_item_id = it.id
        join public.invoices i on i.id = it.invoice_id and i.status::text not in ('cancelled', 'refunded')
       where it.credit_issued_at is null
         and it.credit_split_allocation_id is null and it.bundle_split_allocation_id is null
         and not exists (select 1 from public.invoice_credit_splits sp where sp.invoice_item_id = it.id)
         and not exists (select 1 from public.credit_package_progress_lots x where x.invoice_item_id = it.id)),
    -- whom the release records of the lines sold with such a line name (each
    -- followed to the lot it reaches now), by 462's rule
    bare as (
      select b.invoice_id, b.invoice_item_id, i.customer_id as invoice_customer,
             count(distinct h.holder) as holders, count(*) filter (where h.holder is null) as no_holder,
             (array_agg(h.holder) filter (where h.holder is not null))[1] as holder
        from bare0 b
        join public.invoices i on i.id = b.invoice_id
        join grp o on o.invoice_id = b.invoice_id and o.invoice_item_id <> b.invoice_item_id and o.sale = b.sale
        join public.credit_package_progress_lots pl on pl.invoice_item_id = o.invoice_item_id
        join public.customer_credit_lots c on c.id = public.credit_lot_current(pl.lot_id)
        cross join lateral (select public.invoice_credit_live_holder(pl.invoice_id, c.customer_id, c.created_at) as holder) h
       group by b.invoice_id, b.invoice_item_id, i.customer_id),
    -- per line with releases of its own: its holders, whether a release reads as
    -- spent or a lot of it holds credit, the credit still to be released
    own as (
      select p.invoice_id, p.invoice_item_id, i.customer_id as invoice_customer, i.status::text as status,
             count(distinct p.holder) as holders, count(*) filter (where p.holder is null) as no_holder,
             (array_agg(p.holder) filter (where p.holder is not null))[1] as holder,
             bool_or(p.spent) as spent, bool_or(p.remaining_amount > 0) as holding,
             round(public.credit_line_paid_entitlement(p.invoice_item_id)
                   - public.credit_package_released_paid_credit(p.invoice_item_id), 2) as to_come
        from pre p
        join public.invoices i on i.id = p.invoice_id
       group by p.invoice_id, p.invoice_item_id, i.customer_id, i.status),
    -- the lines whose later credit, Bonus, vouchers, sale record and commission
    -- go to a holder other than the invoice's customer from 476: with releases
    -- of their own (held by one customer), or with none, sold with lines whose
    -- releases are (one customer); with what that changes for the vouchers and
    -- the commission
    moved as (
      select x.invoice_id, x.invoice_item_id, x.holder, x.invoice_customer, x.why,
             -- its settlement gives vouchers (a Premium Bundle's, a Credit Package's reward vouchers
             -- as issue_credit_package counts them)
             (it.line_kind::text = 'premium_bundle' and coalesce(pb.free_voucher_qty, 0) > 0
              or it.line_kind::text = 'credit_package' and coalesce(pk.grants_reward, false)
                 and floor(coalesce(pk.customer_price, 0)
                           / nullif(coalesce(pk.reward_qualifying_amount,
                                             (public.legacy_lowest_rule(i.store_id, public.sg_today())).qualifying_amount, 994), 0)) >= 1) as vouchers,
             -- the invoice has no affiliate (none chosen, not cleared) and the holder's referrer is not
             -- the invoice's customer's: whose referrer earns changes
             i.affiliate_id is null and not coalesce(i.affiliate_selection_explicit, false)
               and (select c.referred_by from public.customers c where c.id = x.holder)
                   is distinct from (select c.referred_by from public.customers c where c.id = x.invoice_customer) as referrer
        from (select o.invoice_id, o.invoice_item_id, o.holder, o.invoice_customer, 2 as why from own o
               where o.holders = 1 and o.no_holder = 0 and o.holder is distinct from o.invoice_customer
              union all
              select b.invoice_id, b.invoice_item_id, b.holder, b.invoice_customer, 6 from bare b
               where b.holders = 1 and b.no_holder = 0 and b.holder is distinct from b.invoice_customer) x
        join public.invoices i on i.id = x.invoice_id
        join public.invoice_items it on it.id = x.invoice_item_id
        left join public.premium_bundles pb on pb.id = it.premium_bundle_id
        left join public.credit_packages pk on pk.id = it.credit_package_id),
    -- the package lines whose credit lots (settled: those its benefit rows name,
    -- not what an Owner moved to someone else; not settled: its release records'
    -- lots now) are held by more than one customer, merges followed
    split as (
      select x.invoice_id, x.invoice_item_id
        from (select b.invoice_id, b.invoice_item_id, l.customer_id
                from public.invoice_benefit_values b
                join public.customer_credit_lots l on l.id = b.lot_id
                join public.invoice_items it on it.id = b.invoice_item_id and it.line_kind::text in ('credit_package', 'premium_bundle')
               where not public.invoice_benefit_moved_to_other(b.id)
              union all
              select p.invoice_id, p.invoice_item_id, p.customer_id from pre p) x
        join public.invoices i on i.id = x.invoice_id and i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
       group by x.invoice_id, x.invoice_item_id
      having count(distinct public.invoice_benefits_holder(x.invoice_id, x.customer_id, 'infinity')) > 1),
    -- lots of credit released before full payment that no benefit row names,
    -- holding less than they were granted but all that the release records
    -- whose lot they are now count as released (nothing on them used), of an
    -- invoice neither cancelled nor refunded with no reopening waiting
    relunspent as (
      select pl.invoice_id, pl.invoice_item_id, c.id as lot_id
        from public.credit_package_progress_lots pl
        join public.invoices i on i.id = pl.invoice_id and i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
        join public.customer_credit_lots c on c.id = public.credit_lot_current(pl.lot_id)
       where c.status = 'active' and c.remaining_amount > 0 and c.remaining_amount < c.original_amount
         and not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = any (public.credit_lot_chain(pl.lot_id)))
         and not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = c.id and bv.invoice_id = pl.invoice_id)
         and not exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = pl.invoice_id and q.applied_at is null)
       group by pl.invoice_id, pl.invoice_item_id, c.id, c.remaining_amount
      having c.remaining_amount >= sum(pl.released_amount) and sum(pl.released_amount) > 0),
    found(reason, invoice_id, n) as (
      select '1 changes: a package paid in part, not settled, of an invoice neither cancelled nor refunded, whose released credit was spent with nothing left on its lots and more still to be released; a ''transfer'' customer change passed (moving nothing, the later payments giving the rest to the new customer), from 476 it is refused as "Partly spent", as for the same package paid in full (the count is of lines)', o.invoice_id, count(*)
        from own o
       where o.status not in ('cancelled', 'refunded') and o.to_come > 0 and o.spent and not o.holding
       group by o.invoice_id
      union all
      select '2 changes: a package paid in part, not settled, whose released credit is held by one customer other than the invoice''s customer (a ''keep'' change, or a ''transfer'' and then a ''keep''): its next payments, its reopening and its settlement gave the invoice''s customer its credit (paid, and the Bonus), its vouchers and allowance and its sale record, from 476 that holder (the count is of lines)', m.invoice_id, count(*)
        from moved m where m.why = 2
       group by m.invoice_id
      union all
      select '3 for the Owner (not changed by 476: NOT COVERED 3): a package paid in part, not settled, whose released credit is held by more than one customer (split before 476): all it gives later still goes to the invoice''s customer; a data fix, or left as it is (the count is of lines)', o.invoice_id, count(*)
        from own o
       where o.holders > 1
       group by o.invoice_id
      union all
      select '4 changes: of 2 and 6, its settlement gives vouchers (a Premium Bundle''s vouchers and allowance, a Credit Package''s reward vouchers): from 476 to the holder, before to the invoice''s customer (the count is of lines)', m.invoice_id, count(*)
        from moved m where m.vouchers
       group by m.invoice_id
      union all
      select '5 for the Owner (not changed by 476: NOT COVERED 3): a package line, of an invoice neither cancelled nor refunded, whose credit lots are held by more than one customer (split before 476 by a ''keep'' change before full payment, or by a ''transfer'' change of a partly spent package before 473 or 476): a data fix, or left as it is (the count is of lines)', s.invoice_id, count(*)
        from split s
       group by s.invoice_id
      union all
      select '6 changes: a package or bundle line paid in part, not settled, that released nothing yet, sold with lines (the invoice''s own sale, or one correction''s lines) whose released credit is held by one customer other than the invoice''s customer: its payments and settlement gave the invoice''s customer all of it, from 476 that holder (the count is of lines)', m.invoice_id, count(*)
        from moved m where m.why = 6
       group by m.invoice_id
      union all
      select '7 changes: a lot of credit released before full payment that holds less than it was granted though nothing on it was used (a payment corrected lower; a Cancel, a reopening and a refund paid back onto it): a ''transfer'' customer change was refused as "Partly spent", from 476 it moves the lot where nothing else of the line was used (the count is of lots)', r.invoice_id, count(*)
        from relunspent r
       where not exists (select 1 from pre p where p.invoice_item_id = r.invoice_item_id and p.spent)
       group by r.invoice_id
      union all
      select '8 changes: of 2 and 6, the invoice has no affiliate and the holder''s referrer is not the invoice''s customer''s: from 476 the holder''s referrer earns its commission at settlement, and the part-payment commission it holds already moves to them at the next sync (the count is of lines)', m.invoice_id, count(*)
        from moved m where m.referrer
       group by m.invoice_id
      union all
      select '9 not changed (the Owner''s answer A): a package or bundle line a correction added once money had been received, not settled, that released nothing yet, on an invoice whose other lines'' released credit is held by someone other than the invoice''s customer: it goes to the invoice''s customer who pays for it, as before 476 (the count is of lines)', b.invoice_id, count(*)
        from bare0 b
        join public.invoices i on i.id = b.invoice_id
       where b.sale > 0
         and not exists (select 1 from bare x where x.invoice_item_id = b.invoice_item_id)
         and exists (select 1 from pre p where p.invoice_id = b.invoice_id and p.holder is distinct from i.customer_id)
       group by b.invoice_id)
    select string_agg(format('%s: %s invoice(s) (%s)', f.reason, f.n, f.nos), '; ' order by f.reason) into v
      from (select left(f.reason, 1) as reason, count(distinct f.invoice_id) as n,
                   string_agg(distinct i.invoice_no, ', ' order by i.invoice_no) as nos
              from found f join public.invoices i on i.id = f.invoice_id group by left(f.reason, 1)) f;
    if v is not null then
      raise notice '476: the header''s query lists %: 1, a ''transfer'' customer change now refused as "Partly spent"; 2, 4, 6 and 8, what is given later (credit, Bonus, vouchers, sale record, commission) now goes to whoever holds the package''s benefits; 7, a ''transfer'' change now moves a lot nothing on which was used; 3 and 5 are for the Owner (NOT COVERED 3); 9 is unchanged (answer A)', v;
    end if;
  end if;

  -- Who may call each, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  for i in 1 .. cardinality(c_sigs) loop
    if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i]))
       is distinct from (select array_agg(x::text order by x::text) from unnest(c_acl[i]::aclitem[]) x) then
      raise exception '476: who may call public.% is not as read on 27 Oct 2026 (%)', c_sigs[i],
        (select proacl::text from pg_proc where oid = to_regprocedure('public.' || c_sigs[i])); end if;
    v_acl := v_acl || (select coalesce(string_agg(x::text, ',' order by x::text), '')
                         from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i]));
  end loop;

  -- ── Change ──────────────────────────────────────────────────────────────
  if v_first then
    -- The helpers first: the functions that give credit call them.
    execute c_def_group;
    execute c_def_holder;
    execute c_def_receivers;
    execute 'revoke all on function public.credit_line_sale_group(uuid) from public, anon, authenticated';
    execute 'grant execute on function public.credit_line_sale_group(uuid) to service_role';
    execute 'revoke all on function public.credit_line_benefits_holder(uuid) from public, anon, authenticated';
    execute 'grant execute on function public.credit_line_benefits_holder(uuid) to service_role';
    -- (the Pay dialog reads it: signed-in staff; it checks the store, 406)
    execute 'revoke all on function public.invoice_credit_receivers(uuid) from public, anon';
    execute 'grant execute on function public.invoice_credit_receivers(uuid) to authenticated, service_role';
    execute c_def_list;
    execute c_def_move;
    execute c_def_release;
    execute c_def_issue;
    execute c_def_bundle;
    execute c_def_pkgprev;
  end if;

  -- ── Afterwards: installed exactly as tested, grants as before ───────────
  for i in 1 .. cardinality(c_sigs) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[i]))) <> c_after[i] then
      raise exception '476: public.% is not at its AFTER md5 (%)', c_sigs[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[i]))); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i])) is distinct from v_acl[i] then
      raise exception '476: the grants of public.% changed', c_sigs[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_new) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_new[i]))) <> c_new_after[i]
       or (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new[i]))
          is distinct from (select array_agg(x::text order by x::text) from unnest(c_new_acl[i]::aclitem[]) x)
       or has_function_privilege('anon', 'public.' || c_new[i], 'execute')
       or i < 3 and has_function_privilege('authenticated', 'public.' || c_new[i], 'execute') then
      raise exception '476: public.% is not as tested, or not callable as tested', c_new[i]; end if;
  end loop;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("476 check", @example.invalid, fictional ACMA
  -- phones no customer uses); it ends by raising P0476, which undoes all it
  -- wrote. 462's trigger runs at commit; here at each step's end (SET
  -- CONSTRAINTS ... IMMEDIATE), as a commit would.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from generate_series(700, 799) g, lateral (select '+61491570' || g::text as p) x
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p desc limit 20);
    if coalesce(cardinality(t_phones), 0) < 20 then raise exception '476: the self-test found no twenty unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '476-check-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '476 check', '476-check-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('476 check ' || t_sfx, '476-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('476 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy, grants_reward)
    values ('476 check ' || t_sfx, 100, 100, false, true, true, false) returning id into t_pk;
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, bonus_value, allow_product, allow_therapy, grants_reward)
    values ('476 check bonus ' || t_sfx, 100, 100, true, 10, true, true, false) returning id into t_pkb;
    insert into public.credit_package_stores (package_id, store_id) values (t_pk, t_store), (t_pkb, t_store);
    insert into public.vouchers (name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('476 check voucher ' || t_sfx, '476V-' || t_sfx, 'normal', 'unlimited', 30, true) returning id into t_v;
    insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store) values (t_v, t_store, 30, true);
    insert into public.premium_bundles (name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('476 check bundle ' || t_sfx, 140, 100, 40, 1, true) returning id into t_pb;
    insert into public.premium_bundle_stores (bundle_id, store_id) values (t_pb, t_store);
    insert into public.premium_bundle_vouchers (bundle_id, voucher_id) values (t_pb, t_v);
    insert into public.therapy_services (service_code, name, standard_price, duration_minutes, is_active)
    values ('476-' || t_sfx, '476 check ' || t_sfx, 20, 30, true) returning id into t_svc;
    insert into public.therapy_service_stores (service_id, store_id, is_available) values (t_svc, t_store, true);
    select pm.id into t_wallet from public.payment_methods pm
     where pm.name = 'Wallet — Credit Package Paid' and pm.is_wallet_credit and pm.deleted_at is null;
    if t_wallet is null then raise exception '476: the wallet method "Wallet — Credit Package Paid" (443) is not there'; end if;
    -- the buyer's and the new customer's referrers (case e)
    insert into public.customers (full_name, phone) values ('476 Check Referrer A ' || t_sfx, t_phones[19]) returning id into t_ra;
    insert into public.customers (full_name, phone) values ('476 Check Referrer B ' || t_sfx, t_phones[20]) returning id into t_rb;

    for t_case in 1 .. 9 loop
      -- Sold to A, S$40 paid (S$40 of its paid credit released to A): (d)
      -- the Bonus package, (e) the Premium Bundle with its voucher chosen,
      -- (g) two S$100 packages on one invoice (the S$40 released on the
      -- first only), else the S$100 package.
      insert into public.customers (full_name, phone, referred_by)
      values ('476 Check Buyer ' || t_case || ' ' || t_sfx, t_phones[2 * t_case - 1], case when t_case = 5 then t_ra end) returning id into t_a;
      insert into public.customers (full_name, phone, referred_by)
      values ('476 Check Holder ' || t_case || ' ' || t_sfx, t_phones[2 * t_case], case when t_case = 5 then t_rb end) returning id into t_b;
      t_line := case t_case when 4 then jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pkb, 'quantity', 1)
                            when 5 then jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', t_pb, 'quantity', 1,
                                          'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', t_v, 'quantity', 1)))
                            else jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1) end;
      t_inv := public.create_invoice(t_store, t_a, null::uuid,
        case when t_case = 7 then jsonb_build_array(t_line, t_line) else jsonb_build_array(t_line) end,
        0::numeric, null::text, null::uuid, '[]'::jsonb);
      perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 40)), gen_random_uuid());
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      -- (a), (b): two S$20 sessions paid from it (all of it spent).
      if t_case in (1, 2) then
        for t_k in 1 .. 2 loop
          t_s := public.create_invoice(t_store, t_a, null::uuid,
            jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 1)),
            0::numeric, null::text, null::uuid, '[]'::jsonb);
          perform public.record_invoice_payment(t_s, jsonb_build_array(jsonb_build_object('payment_method_id', t_wallet, 'amount', 20)), gen_random_uuid());
          set constraints public.credit_given_back_follows immediate;
          set constraints public.credit_given_back_follows deferred;
        end loop;
      end if;
      -- (i): the invoice's S$40 payment corrected to S$35 (Correct payment):
      -- S$5 of the released credit taken back, nothing used.
      if t_case = 9 then
        select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt';
        perform public.correct_invoice_payment(t_pay, 35, public.sg_today(), t_cash, '476 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
      end if;
      -- The invoice form's customer change to B: 'transfer' in (a), (f) and
      -- (i), 'keep' otherwise.
      t_err := null;
      begin
        perform public.correct_invoice(t_inv,
          (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
                    'credit_package_id', it.credit_package_id, 'premium_bundle_id', it.premium_bundle_id,
                    'quantity', it.quantity, 'unit_price', it.unit_price, 'voucher_selection', it.bundle_voucher_selection)) order by it.id)
             from public.invoice_items it where it.invoice_id = t_inv),
          jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = t_inv),
            'customer_id', t_b, 'store_id', t_store, 'benefit_action', case when t_case in (1, 6, 9) then 'transfer' else 'keep' end),
          '476 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
      exception when sqlstate 'P0001' then t_err := sqlerrm;
      end;
      if t_case = 1 then
        -- (a) refused with the paid-in-full package's words; nothing moved.
        if t_err is null
           or t_err not like 'These benefits have already been used and cannot move with the invoice: Paid credit 60.00 (Partly spent).%'
           or (select customer_id from public.invoices where id = t_inv) <> t_a
           or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id in (t_a, t_b)) <> 0
           or exists (select 1 from public.customer_credit_lots where customer_id = t_b) then
          raise exception '476: (a) the change of a package paid in part whose released credit was spent was not refused as "Partly spent" (%)', coalesce(t_err, 'no refusal'); end if;
        continue;
      end if;
      if t_err is not null or (select customer_id from public.invoices where id = t_inv) <> t_b then
        raise exception '476: (%) the customer change was refused (%)', chr(96 + t_case), t_err; end if;
      -- (i) the lot nothing on which was used moved with the change.
      if t_case = 9 and ((select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_b) <> 35
                         or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> 0) then
        raise exception '476: (i) the S$35 left of a S$40 lot after its payment was corrected lower, nothing on it used, did not move with the ''transfer'' change'; end if;
      -- (c) S$20 more paid after the change (released again).
      if t_case = 3 then
        perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 20)), gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
      end if;
      -- (h) a second package added by a correction after the change.
      if t_case = 8 then
        perform public.correct_invoice(t_inv,
          (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
                    'credit_package_id', it.credit_package_id, 'quantity', it.quantity, 'unit_price', it.unit_price)) order by it.id)
             from public.invoice_items it where it.invoice_id = t_inv)
            || jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
          jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = t_inv), 'store_id', t_store),
          '476 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
      end if;
      -- The Pay dialog's read: (g) both lines to A; (h) the first line to A,
      -- the added one not listed (the invoice's customer's).
      if t_case in (7, 8) then
        t_r := public.invoice_credit_receivers(t_inv);
        if jsonb_array_length(t_r->'lines') <> (case t_case when 7 then 2 else 1 end)
           or exists (select 1 from jsonb_array_elements(t_r->'lines') x where (x->>'customer_id')::uuid is distinct from t_a) then
          raise exception '476: (%) the Pay dialog''s read does not name whoever holds the benefits (%)', chr(96 + t_case), t_r; end if;
      end if;
      -- Paid in full (settled: the rest of its paid credit, its Bonus, its
      -- vouchers and its sale record).
      perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
        'amount', (public.invoice_financial_position(t_inv)->>'outstanding')::numeric)), gen_random_uuid());
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      if (select status::text from public.invoices where id = t_inv) <> 'paid'
         or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a)
            <> (case t_case when 2 then 60 when 4 then 110 when 5 then 140 when 6 then 0 when 7 then 200 when 9 then 0 else 100 end)
         or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_b)
            <> (case t_case when 6 then 100 when 8 then 100 when 9 then 100 else 0 end) then
        raise exception '476: (%) the credit did not go to whoever holds the package''s benefits (status %, A holds %, B holds %)', chr(96 + t_case),
          (select status::text from public.invoices where id = t_inv),
          (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a),
          (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_b); end if;
      -- (e) the voucher, the sale record and the commission with the buyer.
      if t_case = 5 and ((select coalesce(sum(quantity), 0) from public.customer_reward_vouchers where customer_id = t_a and status = 'held') <> 1
                         or exists (select 1 from public.customer_reward_vouchers where customer_id = t_b)
                         or exists (select 1 from public.premium_bundle_sales where invoice_id = t_inv and customer_id is distinct from t_a)
                         or exists (select 1 from public.commissions where invoice_id = t_inv and referrer_customer_id = t_rb)) then
        raise exception '476: (e) the Premium Bundle''s voucher, sale record or commission did not follow its credit to the buyer'; end if;
    end loop;
    raise exception using errcode = 'P0476', message = '476: self-test done, undone';
  exception when sqlstate 'P0476' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
