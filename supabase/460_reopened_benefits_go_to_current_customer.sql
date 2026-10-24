-- 460_reopened_benefits_go_to_current_customer.sql
--
-- WHAT A REOPENED INVOICE GIVES BACK, AND THE VOUCHERS IT GIVES AGAIN, GO TO
-- WHOEVER THE INVOICE'S BENEFITS BELONG TO NOW: THE RECORD A MERGE KEPT, OR
-- THE CUSTOMER A CUSTOMER CHANGE MOVED THEM TO; A LATER CUSTOMER CHANGE
-- TAKES THE VOUCHERS A REOPENING GAVE (the Owner, 22 Oct 2026: "fix the
-- other two rare gaps too"; gap A = 448's NOT COVERED 2, with 446's NOT
-- COVERED 5 and the items 447's NOT COVERED lists as "found when 446 and 447
-- were checked together")
--
-- WHO FOUND IT
--
--   448's builder (22 Oct 2026, 448's NOT COVERED 2, checked as KNOWN by
--   scripts/invoices/tests/refunded-units-not-used-448.sql, case 8 (2)),
--   446's (NOT COVERED 5, its suite's case 8b) and the check of 446 and 447
--   together (447's NOT COVERED, last item). Reproduced for this file on a
--   copy of production as it is (455 in: b43a0781, 1372 functions), with
--   made-up records, through the app's own calls only: the invoice form and
--   the Pay dialog, Cancel, the Finance panel's refund by line and "Record
--   refund paid", Reopen, Record Payment, Move, the invoice form's customer
--   change (correct_invoice with benefit_action 'transfer' or 'keep') and its
--   review summary, and a customer merge (merge_customer_records).
--   A review of the first draft (24 Oct 2026) found three things, handled
--   here: (1) where the lot the invoice's records name had its benefit
--   row moved on by a Move, the draft gave the credit back to the holder on
--   a new lot no record named, so Cancel and Refund in full asked a false
--   credit_used override, the cancel's refund due fell (S$100 to S$60 on a
--   copy) and Cancel did not take it back: such a lot is now left as before
--   (NOT COVERED 4); (2) the review summary does not list what a reopened
--   invoice still waiting gives the new customer (now NOT COVERED 7; its
--   function is not changed here: DEPLOY ORDER); (3) the earlier suites'
--   edits failed with 461 in: they are now the same files as 461's.
--   The check of 460 and 461 together (24 Oct 2026, on copies, one
--   transaction per app call) found THE GAP, newly reachable with 461 and
--   there at 455 by a merge (this file's suite K7, now its case M6): S$100 +
--   S$10 package, S$40 refunded by line (S$44 of credit taken back, S$56
--   left), the customer changed A to B ('transfer': 461 moves the S$56 to a
--   new lot for B and the records name it), B's S$56 moved to a friend
--   (Move), Cancel, Reopen, Record Payment: the S$44 went back on A's lot,
--   which no record names; Cancel and Refund in full asked a false
--   credit_used, the cancel's refund due was S$60 although S$100 was
--   received, and a later Cancel left A the S$44 (the same with B merged
--   into K before the cancel). Handled here: WHAT THIS DOES, NOT COVERED 4.
--   A review of that fix (24 Oct 2026, on copies with 460 alone and with
--   461, one transaction per app call) found four things, handled here:
--   (1) the S$44 went onto the lot the records name although its holder had
--   paid for something else from that lot before the Move (a S$20 session,
--   from the wallet), and a refund of that sale gives its credit back on
--   that lot, so the refund could not be recorded (a raw error: the lot
--   would hold more than it was granted; at 455 it went through), or it
--   filled the lot back to all it was granted and a later customer change
--   ('transfer') moved it without its records (THE GAP again: S$60 on a
--   copy); (2) the reopening allowed while that sale was not refunded, a
--   refund of it while the reopening waited left the S$44 not fitting when
--   the payment came, and the payment left it, silently, on the lot no
--   record names (THE GAP in full; the header called this "not reached on
--   a copy"). So credit that paid for other sales and can still come back
--   onto that lot now counts as taken, and the payment is refused rather
--   than leaving credit behind silently (WHAT THIS DOES, NOT COVERED 4 (c));
--   (3) NOT COVERED 4 did not name every order in which the S$44 stays with
--   the holder of the lot the records name rather than with the benefits'
--   current holder (now 4 (b)); (4) the Test paragraph miscounted its
--   controls.
--
-- WHAT WAS WRONG
--
--   A reopening queues what the invoice's cancellation and line refunds took
--   back (reopen_invoice): credit by the ledger rows that took it, on the lot
--   they took it from; vouchers by benefit row. The payment that settles the
--   invoice gives it back (the triggers apply_reopened_invoice_benefits and
--   apply_reopened_invoice_vouchers): the credit on that same lot, the
--   voucher to whoever holds the voucher it replaces. Neither looked at whom
--   the invoice's benefits belong to now. A lot cannot change customer (77),
--   so a merge (445) and a customer change that takes the benefits along
--   (447) draw a lot down and give its holder a new one, but only a lot that
--   still holds credit, and they repoint the invoice's records to it; a
--   voucher a merge moves in place, any status, but a customer change only a
--   held one of the invoice's voucher and promotion lines. So, on the copy:
--   (i)  a merge before or while a reopening waits. S$40 of a S$100 package
--        refunded by line, the buyer merged into another record, cancelled,
--        reopened, paid: the S$40 went back on the retired record's lot, the
--        kept record held S$60, and Cancel asked credit_used (448's NOT
--        COVERED 2). Cancelled, paid back, reopened, then merged while it
--        waited, paid: all S$110 of a S$100 + S$10 package went back to the
--        retired record (its vouchers to the kept one: a merge moves them).
--        The same with a line refunded whole before the merge, after two
--        merges (A into B, B into C), and for credit an Owner had moved to a
--        friend who was then merged away;
--   (ii) a customer change ('transfer') after a line refund, then cancelled,
--        reopened and paid (446's NOT COVERED 5): two S$100 + S$10 packages,
--        line 1 refunded: line 1's S$110 went back to the old customer's
--        emptied lot; two voucher lines of one, line 1 refunded: its voucher
--        given again to the old customer;
--   (iii) a customer change ('transfer') made while a reopened invoice waits:
--        correct_invoice accepts it and moves nothing (nothing is held), and
--        records nothing; once paid, all of it (S$110 and two vouchers) went
--        to the OLD customer. The same after a second change with 'keep',
--        and with the new customer then merged away;
--   (iv) a customer change ('transfer') after a reopening was settled: the
--        two vouchers it gave (source 'invoice_reopen') stayed with the old
--        customer (move_invoice_benefits_to_customer moves only sources
--        'invoice_voucher_sale' and 'invoice_promotion_voucher'), and the
--        review summary did not list them; the same for a limited voucher
--        with the store changed (its stock stayed too).
--   A change with 'keep' (322: leave the benefits with whoever holds them)
--   gave back to the old customer, rightly; it still does.
--   Production, 22 Oct 2026 (counts only): invoice_reopen_vouchers has never
--   had a row; invoice_reopen_benefits has 4 rows, on one invoice (11 Sep
--   2026), none waiting; 16 customer merges; the 3 customer changes that
--   took benefits along moved 1 voucher each and no credit lot; no lot has
--   reassigned_from_lot_id. So nothing to repair: the file refuses, changing
--   nothing, if a record in the broken state exists when it is applied
--   (SAFETY).
--
-- THE OWNER'S ANSWER (22 Oct 2026)
--
--   "Fix the other two rare gaps too". The rule since 445 and 447: credit
--   and vouchers follow a merge, and follow a customer change that takes the
--   benefits along. So what a reopened invoice gives back, and its
--   replacement vouchers, belong to whoever the invoice's benefits belong to
--   now: the kept record after a merge; the new customer after a customer
--   change that took the benefits along ('transfer'); not when staff left
--   them with their holder ('keep'). Credit given back keeps its origin
--   (source, Credit Package / Premium Bundle group, the link back), as 445
--   and 447 do, and the invoice's records name the lot that holds it, so a
--   later cancel, refund or Move finds it.
--
-- HOW THE CHOICE IS KNOWN
--
--   correct_invoice calls move_invoice_benefits_to_customer only on
--   'transfer' (322, 321), and it writes the invoice's Audit Log row
--   'invoice_benefits_followed_reassignment' (to_customer), but before this
--   file only when something moved. 'keep' writes none. So from now on the
--   row is written for every change that takes the benefits along, and
--   whom a benefit given back belongs to is: the to_customer of the latest
--   such row made since the voucher it replaces was given, or the lot it
--   goes back on was made; otherwise that voucher's or lot's holder; then,
--   if that record was retired by a merge, the record that kept it (followed
--   along a chain, read from the kept record's 'customers_merged' row, as
--   439 reads it). The time bound keeps a change made before the benefits
--   were given (an unpaid invoice) from counting.
--
-- WHAT THIS DOES (two functions added; five changed; grants kept)
--
--   * invoice_own_voucher_ids(uuid) (new; the server's alone): the
--     invoice's own vouchers: its voucher and promotion lines', and each
--     voucher given again in place of one of them (by a reopening, or by the
--     payment after an FOC came off, 416), however many times. Not a
--     voucher an Owner moved to someone (434: it stays with them) nor one
--     given again in its place, and not a Premium Bundle's (never taken
--     along by a customer change: "not transferable").
--   * invoice_benefits_holder(uuid,uuid,timestamptz) (new; the server's
--     alone): the rule above.
--   * apply_reopened_invoice_vouchers() (one statement): the voucher given
--     again in place of one of the invoice's own goes to its benefits'
--     holder; in place of any other, to whoever holds the one it replaces,
--     as before. At the store of the one it replaces, as before.
--   * apply_reopened_invoice_benefits() (the whole text; it is short): each
--     amount goes back on the lot it came from, as before; then, where that
--     lot is not the one the invoice's records name (it was reissued) or is
--     held by a record the benefits have left, what the benefit row holds on
--     its lot and on the lots it replaced goes to the holder as ONE lot: the
--     lots drawn down (ledger 'adjust_decrease', 'invoice_reopen_
--     reassignment_out'), the holder granted the total (ledger 'grant',
--     'invoice_reopen_reassignment_in'; the lot copies the named lot's
--     source, category, restrictions, store and dates, with reassigned_from_
--     lot_id naming it), and the invoice's records repointed to it (its
--     benefit values, its sale's lots, a split's issued lot), as 445 and 447
--     do. A lot an Owner moved to someone follows merges alone. Where the
--     lot is the one named and its holder is the benefits', nothing more
--     happens: as before, to the row. So every lot this issues is one the
--     invoice's records name. Where the named lot's benefit row was moved on
--     by a Move, its records stay (445, 447: the credit moved is traced back
--     through that lot, invoice_credit_transfer_origin, which needs the lot
--     moved from to hold at least what was moved), so nothing is reissued:
--     what goes back on that lot stays there, as before (NOT COVERED 4), and
--     what goes back on a lot it replaced (a refund before the merge or the
--     customer change that reissued it, the Move after: THE GAP) goes onto
--     the named lot: drawn down where it went back (ledger 'adjust_decrease',
--     'invoice_reopen_reassignment_out'), added to the named lot (ledger
--     'adjust_increase', 'invoice_reopen_reassignment_in'; a lot's amount may
--     change, its customer, origin and original amount may not, 77), as long
--     as the named lot then holds less than it was granted, counting as
--     taken what of its credit paid for other sales and can still come back
--     onto it: the open part (amount less what was reversed) of its invoice
--     line allocations (a wallet payment refunded, refund_invoice_recorded,
--     or corrected, correct_invoice_payment) and of its special allocations
--     (refund_special_credit), each of which gives it back on that lot. So a
--     refund of such a sale always fits on it, and it never reads as
--     untouched, even after every such refund, so a later customer change
--     still refuses it as partly spent instead of moving its credit without
--     its records (447, 461). So the records name the lot that holds it:
--     nothing reads as spent, the cancel's refund due is what was received,
--     and Cancel and Refund in full take it back. A lot cannot hold more than
--     it was granted, so where what goes back would not fit so, the reopening
--     is refused (below) and this is not reached. If it is all the same
--     (credit came back on that lot while the reopening waited, in a way not
--     found on a copy; SAFETY checks that those three are the only ways
--     credit comes back on a lot), the payment that would settle the invoice
--     is refused, changing nothing: "Invoice … cannot be settled: it would
--     give back S$… of credit refunded before its customer was changed or
--     merged, the rest of which was then moved to someone else (Move), and
--     the credit lot the invoice names for it cannot take that much back (it
--     holds S$… of S$… granted, and S$… of its credit paid for other sales,
--     which a refund puts back there). Nothing was recorded. Cancel the
--     invoice again (its refund due stands), or ask the Owner." (The first
--     text of this fix left that credit, silently, where it went back.)
--   * invoice_reopen_preview(uuid) (the whole text; it is short): the
--     reopening is refused (a blocker, as for an outstanding rental: the
--     Reopen dialog shows it and keeps "Confirm reopening" off;
--     reopen_invoice refuses with it), changing nothing, where for a benefit
--     row moved on by a Move whose lot a merge or a customer change reissued,
--     what the settling payment would put back on the lots it replaced is,
--     with what it holds, what would go back on it and what of its credit
--     paid for other sales and can still come back onto it (above), as much
--     as it was granted or more: "Reopening would give back S$… of credit
--     refunded before this invoice's customer was changed or merged, the
--     rest of which was then moved to someone else (Move); the credit lot the
--     invoice names for it cannot take that much back[ (S$… of its credit
--     paid for other sales, which a refund puts back there)]. Keep the
--     invoice cancelled (its refund due stands), or ask the Owner." (the
--     bracketed part only where some is). What would go back is read as
--     reopen_invoice queues it (the invoice's cancellation and refund rows
--     not queued yet) and as it waits (the queue's amounts not applied). On a
--     copy: S$60 or S$50 of S$100 refunded, merged, the rest moved on,
--     cancelled: refused; S$49.99: reopened, the S$49.99 on the kept
--     record's lot; S$40 refunded, merged, S$20 of the kept record's lot
--     paid for a session, the rest moved on, cancelled: refused (S$40 + S$20
--     of S$60; without the session it is reopened), and the session's refund
--     then goes back on that lot. Everything else in it is as before.
--   * move_invoice_benefits_to_customer (four places): the vouchers it moves
--     (and whose stock it moves) are the invoice's own
--     (invoice_own_voucher_ids), so those a reopening gave go along; its
--     Audit Log row is written every time it runs. Its credit (the lots'
--     selection, which 461 changes) is not touched.
--   * invoice_transferable_benefits (its vouchers' part): lists the
--     invoice's own vouchers, so the review summary (preview_invoice_
--     correction) lists those a reopening gave as moving. Its credit rows
--     (which 461 changes) are not touched.
--
-- NOT CHANGED
--
--   * reopen_invoice (it refuses on the preview's blockers, as before),
--     invoice_reopen_preview_before_sessions (451's),
--     cancel_invoice_recorded, refund_invoice_recorded
--     (446's step; its refund of a wallet payment), correct_invoice_payment
--     and refund_special_credit (each gives credit back on the lot it came
--     from, as before: the settlement and the preview leave room for it),
--     the queues and what they count (417, 446, 451), 448's
--     counting (invoice_benefit_unused_elsewhere follows the lot a benefit
--     row names back through reassigned_from_lot_id; every lot this file
--     issues is the one its benefit row then names, so the counting finds it
--     and its history),
--     merge_customer_records, transfer_invoice_unused_benefit (the Move and
--     its trace, invoice_credit_transfer_origin, unchanged: the named lot is
--     never repointed), correct_invoice and its 416 / 434 rules,
--     trg_issue_sold_vouchers_on_paid.
--   * The pages: the invoice form's "Move the unused benefits to the new
--     customer" / "Keep the benefits with who holds them now" now hold for
--     what a reopening gives back too. The review summary lists what moves
--     now from the server (InvoicesPage.tsx and preview_invoice_correction,
--     unchanged), including the vouchers a settled reopening gave; not what
--     a reopened invoice still waiting will give the new customer when it is
--     paid (NOT COVERED 7). The page's "The review summary lists exactly
--     what moves before anything is saved" is therefore not exact in that
--     case only. The Reopen dialog (InvoiceFinancePanel.tsx) prints the
--     preview's blockers and keeps its button off while there is one, so
--     the new refusal shows there as it is. A payment the settlement refuses
--     (WHAT THIS DOES; not reached on a copy without a stand-in) shows as
--     the Pay dialog's error, the server's message as it is, as for any
--     refused payment (InvoicesPage.tsx, setPayErr). No page, Edge Function
--     or setting changes.
--   * The old holder's credit statement shows what went back and moved on
--     (+ and -, ending where its lots are); the new holder's, the grant (or,
--     on the named lot of a benefit moved on, "Adjustment — increase").
--
-- NOT COVERED (for the Owner; the suite checks 2, 3, 4 and 7 as they are)
--
--   1. A customer change with 'transfer' made before 460 that moved nothing
--      left no record, so what a later reopening of that invoice gives back
--      goes where it did before. Production: the 3 such changes each moved a
--      voucher (recorded); the file refuses while such an invoice waits.
--   2. A Premium Bundle's vouchers, which a customer change has never taken
--      along ("not transferable"), are given back to whoever holds the voucher
--      they replace (the bundle's credit follows). If the Owner wants them to
--      follow too, that is a change to what a customer change moves.
--   3. A voucher given again is given at the store of the one it replaces
--      (as before), also after a change that moved the store.
--   4. A lot whose benefit row was moved on by an Owner (Move) keeps its
--      records (445, 447: the credit moved is traced back through that row's
--      lot, invoice_credit_transfer_origin, so the row cannot name another
--      lot). So:
--      (a) What a reopening gives back on that lot stays with whoever holds
--      it, as before 460: the old customer after a customer change
--      ('transfer'), the retired record after a merge. Nothing reads as
--      spent, the cancel's refund due is what the invoice holds and a later
--      cancel takes it back. Needs a refund by line, then a Move, then a
--      change or a merge, a cancel and a reopening (on a copy: S$40 of S$100
--      refunded, the S$60 left moved to a friend, cancelled, reopened,
--      changed or merged, paid: the S$40 is on the buyer's lot; the suite's
--      K5 and K6).
--      (b) What goes back on a lot it replaced (THE GAP: the refund before a
--      merge or a customer change, the Move after; there at 455 by the
--      merge) now goes onto it, so the records name it (the suite's M6, and
--      X9 with 461). It is that lot's holder's: B after the change; when B
--      was then merged into K after the Move, still B's lot, the retired
--      record's (a merge moves only a lot that holds credit, and this one
--      was empty then; the suite's X10: the S$44 on B's lot, nothing reads
--      as spent, the refund due is S$100, Cancel takes it back). Giving it to
--      K would need the row to name a lot of K's, which the Move's trace
--      does not allow. The same in every order in which the benefits leave
--      that lot's holder after the Move (checked on copies, one transaction
--      per app call, and by the suite as KNOWN): B changed to C ('transfer')
--      before the cancel (X11) or while the reopening waits (X12), B merged
--      into K while it waits (X13), and on the merge route the kept record K
--      merged into K2 while it waits (M7, without 461 too). The S$44 (S$40)
--      stays on the named lot, B's (K's), a retired record's after a merge,
--      not with C or K (K2), the benefits' current holder (who gets the S$10
--      Bonus where there is one). Nothing reads as spent, the refund due is
--      what was received, and Cancel takes it all back; but credit on a
--      retired record cannot be spent, and a customer's statement shows it
--      on the record it is on, until an Owner moves it: a Move of that
--      benefit row to the current holder puts it right (on a copy, X13: K
--      then holds the S$44 and the S$10, the refund due S$100). Blocking
--      these orders instead (a blocker in the preview where that lot's holder
--      is not invoice_benefits_holder's; a customer change or a merge refused
--      while such a reopening waits) would turn a recoverable outcome into a
--      refusal and change correct_invoice and merge_customer_records: a
--      decision for the Owner, not made here.
--      (c) Where it would not fit on that lot (it would hold all it was
--      granted or more, counting what of its credit paid for other sales and
--      can still come back onto it: WHAT THIS DOES), the reopening is refused
--      (invoice_reopen_preview, with its reason) and the invoice stays
--      cancelled with its refund due: S$50 or more of S$100 refunded before;
--      S$55 of credit for S$50 refunded of a S$100 + S$10 package; S$44 with
--      S$20 of that lot's credit paid for a session after the change or the
--      merge, or S$40 with S$20 of a S$60 lot (on a copy; the suite's
--      section 6). A lot cannot hold more than it was granted, a refund of
--      such a sale must go through, and a lot holding all of it would read as
--      untouched, which a later customer change would move without its
--      records. So the reopening is refused also where that sale is never
--      refunded, although the S$44 would fit then (it cannot be known
--      beforehand): the invoice stays cancelled with its refund due, and the
--      Owner can refund the session first, or decide. If credit still came
--      back on that lot while the reopening waits, so that it would not fit
--      when the payment comes, that payment is refused with its reason,
--      changing nothing (the first text of this fix left the credit,
--      silently, on the lot no record names: reached on a copy by a refund
--      of the session while the reopening waited, which the counting now
--      refuses at the reopening). With the counting no app call reaches it
--      on a copy (a refund or a correction of a sale paid from that lot gives
--      back only what was counted); the suite reaches it by a stand-in
--      (section 6). Nothing waits on production.
--      (d) A merge after such credit is back on the lot the records name, as
--      in (a) or (b), moves it to the kept record without its records (445;
--      the same at 455, checked on a copy, the suite's K9): Cancel then asks
--      credit_used, its refund due is S$60 of S$100 and it does not take the
--      S$40 back. A customer change refuses such a lot as partly spent
--      (461's NOT COVERED 3), so it is not moved. Following a lot forward in
--      the counting (448), Cancel and the Move's trace is a change of its
--      own.
--   5. 461's gap (a partly refunded lot blocks a customer change as "Partly
--      spent"): not this. With 461's draft of 22 Oct 2026 in, the S$40 of a
--      refund made before such a change goes to the new customer on one lot
--      with the rest (checked on a copy).
--   6. Therapy sessions a reopening gives back (invoice_reopen_sessions)
--      follow the invoice's lines as before; not part of this.
--   7. The review summary of a customer change made while a reopened
--      invoice waits (preview_invoice_correction) shows the customer change
--      and, with 'transfer', no benefits entry: nothing is held to move then
--      (the list's rows read "Already revoked" / "Fully spent; it stays with
--      the original customer", which the page does not show). Once the
--      invoice is paid, the new customer holds what waited (on a copy: S$110
--      and two vouchers). The page's note says the summary lists exactly
--      what moves. Not changed here: preview_invoice_correction is pinned by
--      456 (another session's) and the list's credit rows are 461's part, so
--      a line for it is a later change. Production: nothing waits.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the texts are the tested ones (their AFTER md5s); each changed
--     function is its BEFORE (changed; each anchor found once; the text built
--     has its AFTER md5) or its AFTER (left alone); the helpers are absent
--     (added) or this version (left alone); no other function takes the
--     seven names; so a second run changes nothing;
--   * move_invoice_benefits_to_customer and invoice_transferable_benefits are
--     compared with the part 461 changes left out (the lots' selection
--     between two fixed lines; the second of the list's four parts): outside
--     it they must be 447's / 417's text, or this file's, exactly; so 460
--     installs with or without 461 in, and changes nothing in 461's part;
--   * the functions it relies on are as read on production (below);
--     correct_invoice, reopen_invoice and refund_invoice_recorded (456 to 458
--     may change them) are checked by the text this relies on, not pinned
--     (reopen_invoice also: it refuses on the preview's blockers), and the
--     preview before sessions by what it gives (can_reopen, blockers);
--     who calls the changed functions, the two triggers on invoices, the
--     fifteen columns that name a lot (as 445 and 447 read them), the
--     columns read and the tables repointed (no trigger) are as read;
--   * what can put credit back on a lot (a lot's balance raised by an
--     amount) is as read on 24 Oct 2026: the settlement itself, and
--     refund_invoice_recorded, correct_invoice_payment and
--     refund_special_credit, each by reversing an invoice line or a special
--     allocation, whose open part the settlement and the preview count (read
--     by name and by the allocation each reverses, not pinned); another way
--     would need the same counting, so the file stops;
--   * on the first run (apply_reopened_invoice_benefits its BEFORE), nothing
--     already in the state this file prevents: (1) credit a settlement put
--     back on a lot that had been reissued, or of a record a merge had
--     retired, or of a customer the benefits had left by a recorded change;
--     (2) a voucher a reopening gave again to someone other than the
--     customer a recorded change had moved the benefits to; (3) a voucher a
--     reopening gave, held when such a change was made after it; (4) a
--     reopened invoice waiting with credit or vouchers held by someone other
--     than its customer. Any of them needs a decision first: the file stops,
--     changing nothing, and names the invoices. (1) includes credit put back
--     on a lot that the lot of a benefit row moved on (Move) replaced (THE
--     GAP, there at 455 by a merge and with 461 alone by a change: on a lot
--     no record names), not on the lot such a row names (NOT COVERED 4 (a):
--     this file leaves that as it is). A reopening waiting for THE GAP is
--     (4). None on production (above);
--   * who may call each is as read, compared as sets (production lists them
--     in another order than a local copy), and kept; the helpers are revoked
--     from public, anon and signed-in staff and granted to the service role.
--   Afterwards: the md5s are the AFTER ones; the grants are as before. Then
--   a self-test, in a block that is always undone (it ends by raising P0460,
--   so it leaves no row): a made-up Owner, store, S$100 package, S$30
--   voucher, S$20 therapy service and eleven customers (fictional ACMA
--   phones no customer has); it pays a session with the wallet method
--   'Wallet — Credit Package Paid' (443's; the file stops if it is not
--   there).
--   (a) S$40 refunded, the buyer merged away, cancelled, reopened, paid: the
--   kept record holds S$100 on the lot the benefit and the sale name, the
--   retired one nothing, nothing reads as spent. (b) A package and two
--   vouchers cancelled, paid back, reopened; changed ('transfer') while
--   waiting (recorded), paid: the new customer holds the S$100 and the two.
--   (c) Two vouchers cancelled and reopened (settled at once), changed
--   ('transfer'): the two move. (d) (b) with 'keep': the old customer holds
--   the two. (e) NOT COVERED 4: S$40 refunded, the S$60 left moved to a
--   friend (Move), cancelled, reopened, changed ('transfer'), paid: the S$40
--   is back on the buyer's lot the benefit and the sale name, no lot is
--   added, nothing reads as spent, the cancel's refund due is S$100. (f)
--   THE GAP by a merge: S$40 refunded, the buyer merged into another
--   record, its S$60 moved to a friend (Move), cancelled, reopened, paid: the
--   S$40 is on the kept record's lot the benefit and the sale name, no lot
--   is added, the buyer holds nothing, the friend S$60, nothing reads as
--   spent, the refund due is S$100. (g) The same with S$60 refunded: the
--   preview's can_reopen is false and reopen_invoice refuses with the
--   reason; still cancelled, nothing queued. (h) S$40 refunded, the buyer
--   merged into another record, which pays S$20 for a session from the lot
--   the invoice names, the S$40 left moved to a friend, cancelled: the
--   preview's can_reopen is false and reopen_invoice refuses with the
--   reason naming the S$20; still cancelled, nothing queued; the session
--   cancelled and refunded, the S$20 is back on that lot. Its invoice
--   numbers are counted, not drawn from a sequence;
--   its credit ledger rows draw entry numbers (a gap, as 443 to 451's).
--   Locks: the seven functions' catalogue rows, to the end of the apply; the
--   rows the self-test writes and undoes. A settlement or a customer change
--   running at that moment finishes on the text it started with, and so
--   does a reopening.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (455: b43a0781, 1372 functions, head 20261022115409) ->
--   460. 452 to 455 change and pin none of the seven functions. 456 to 458
--   (another session) may change correct_invoice, refund_invoice_recorded or
--   reopen_invoice: not pinned here; if one changes the text this checks
--   (above), or invoice_reopen_preview (pinned: 451's text, 7cb2805a), or
--   adds a way of putting credit back on a lot (above), the file refuses
--   and needs a re-test. 459 changes event_*
--   only. 461 (gap B, another builder) changes move_invoice_benefits_to_
--   customer and invoice_transferable_benefits in the parts left out above:
--   460 installs before or after it. 461 must accept, as its BEFORE, this
--   file's AFTER of those two (below; its anchors are untouched in them).
--   1. Dry run on a copy of production as it is then: apply this file
--      twice; the first run ends at the fingerprint below, the second
--      changes nothing ("left alone" seven times); and its suite (it passes
--      with 461 in first, or not).
--   2. Apply (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself.
--   Afterwards the re-run of 451 (it pins apply_reopened_invoice_vouchers
--   and _benefits, and invoice_reopen_preview) refuses, changing nothing,
--   where today it leaves all alone; those of 445 to 448 refuse already
--   today on other pins (checked on a copy). All are applied, so nothing is
--   lost. Earlier suites that
--   printed these gaps as KNOWN check them the fixed way where 460 is in:
--   refunded-units-not-used-448.sql 8 (2), reopen-refund-waiting-446.sql 8b,
--   cancel-voucher-stock-once.sql 12e (the reopening's vouchers move with
--   the change); function-grants.sql lists the helpers.
--   customer-change-credit-447.sql (rebuilds 417's text with 460's and 461's
--   changes taken out) and refunded-units-not-used-448.sql (8 (2) FIXED
--   where 460 is in, 8 (3) where 461 is) are ONE version shared with 461's
--   worktree (461's of 24 Oct 2026 00:30, md5 d8d70372 / ea463737): it
--   passes at 455, with 460, with 461 and with both; whichever of 460 and
--   461 is committed second keeps that version.
--   461's header gave the fingerprint with both in as db0a6ec2 (this file's
--   first draft), 78d539ab (its second, 24 Oct 2026 01:14, md5 ab858625)
--   and a0679713 (its third, md5 53baa1c1); with this text it is 037095a5
--   (below), and 461's header (a comment change only: its texts and md5s
--   are as they were) says so.
--
-- BEFORE (production, 22 Oct 2026, at 455; md5 of pg_get_functiondef with
-- search_path public)
--   changed
--   apply_reopened_invoice_benefits()                                  75489db2b12e60a3104fff9ef76c2d20  (417's)
--   invoice_reopen_preview(uuid)                                       7cb2805a10d92c41626e85a3542cc1f8  (as 451 read it)
--   apply_reopened_invoice_vouchers()                                  71d50be41b73decceb0b20f8597dd4fa  (417's)
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)             e313e87b4ab4c0063d924430996ffbd3  (447's AFTER)
--     outside the lots' selection                                      a58d8344fccaeef481ca17fdf583b8bc
--   invoice_transferable_benefits(uuid)                                e3a4b753d87546a1a73342baf02bee70  (417's)
--     outside the credit rows                                          f76166f80a84df5fbee2a3056d017f4b
--   invoice_own_voucher_ids(uuid), invoice_benefits_holder(uuid,uuid,timestamp with time zone)   (not there)
--   relied on, not changed
--   merge_customer_records(uuid,uuid,text,uuid)                        2e0c9852099ab88d8f27827b5f9a3846  (445's AFTER)
--   transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)          7aebd7120bc3928db46df0941cb20889  (445's AFTER)
--   trg_issue_sold_vouchers_on_paid()                                  c840d0d2754e7a8e889848ea8269a293  (416)
--   cancel_invoice_recorded(uuid,text,uuid)                            de52d9dbaef8ab15163bef35cb9d733d
--   invoice_benefit_unused_elsewhere(uuid)                             d35d7c8ae7187985ea64f8a5c38a7d79  (448)
--   invoice_commission_benefit_source(uuid)                            f8d3d29fae79065a252a8c5231cc2d4b
--   ensure_customer_wallet(uuid)                                       8ef18daebbbe3c12f2024290ea8416e8
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   trg_credit_lot_immutable()                                         0fc74da0dcc9b436dfd26c4582542f6c
--   checked by their text (at 455): correct_invoice 422682d6, reopen_invoice cb647331, refund_invoice_recorded 804ecd82,
--     invoice_reopen_preview_before_sessions 12206ed0 (451's)
--   what can put credit back on a lot, by name (24 Oct 2026): apply_reopened_invoice_benefits, and, each by the
--     allocation it reverses, correct_invoice_payment (invoice line), refund_invoice_recorded (invoice line),
--     refund_special_credit (special)
--   public function fingerprint, production now (455 in)               b43a0781217fd1b4027749deafbddca7 (1372 functions)
--   grant list (string_agg(signature '=' proacl, '|'), production)     02ccc9f63f575db7df6d390b30bf7d22
-- AFTER (for later guards)
--   apply_reopened_invoice_benefits()                                  3e659dafdbacb00ad953f99d00c3c6c9  (drafts d7aaaaf4, af41420e, 14df4851)
--   invoice_reopen_preview(uuid)                                       4b49c0c64eeb1b5962b605bbf56ea159  (draft ebde15e6; grants kept: signed-in staff, service role)
--   apply_reopened_invoice_vouchers()                                  28d3b7a69b91ddebcdb200559d96a0ef
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)             5a165f7035151f8f711fc2ac293e9b62  (without 461)
--     outside the lots' selection                                      b434f77373e6ba07cc4b1fb30a2f4d50  (with or without 461)
--   invoice_transferable_benefits(uuid)                                c568df874f2667f6a313d7aac0b4c086  (without 461)
--     outside the credit rows                                          e5df1d68f73847f5d9faa7b04bfd81fe  (with or without 461)
--   invoice_own_voucher_ids(uuid)                                      9340840f1ce4e031ec3613198688ba2e  (new; service role alone)
--   invoice_benefits_holder(uuid,uuid,timestamp with time zone)        55995ff6e1ffd4a1172cb930512a34b0  (new; service role alone)
--   public function fingerprint, worked out on a copy of production (24 Oct 2026):
--     production now (455 in) -> 460 (a second run the same)           2b290d5d8f1579cf7831a3ce9837035e (1374 functions: two new, none dropped)
--     with 461 (md5 309d7450, 24 Oct 2026: f56e72ca with its header brought up to date; 5a6edbb7 before), 461 then 460 or 460 then 461 (either
--       order the same; a second run of 460 "left alone" seven times, of 461 twice)
--                                                                      037095a507480dafd8381a6d3d8add90 (1374 functions; the two shared
--       functions then c1827889748d29f7a6626294333bd94f / 362d6d076c4751ab5dbe760f6d7a0d37; re-work it out if 461's text changes)
--     (this file's second draft, md5 ab858625: 955856b2 alone, 78d539ab with 461; its third, md5 53baa1c1: abf5330e alone,
--       a0679713 with 461)
--   grant list on the copy after 460 (with or without 461)             acc689cefa349b1ed9588d7d8bb92ce7 (the two helpers' grants
--       may be listed in another order on production; compare as sets; the preview's are kept as they are)
--
-- Test: scripts/invoices/tests/reopen-follows-customer-460.sql (begin ...
-- rollback; it installs this file twice; -v nomig=1 where it is in). It
-- reproduces each case first (where 460 is not in: fourteen cases, and two
-- more where 461 is in, undone; THE GAP's credit_used and S$60 due among
-- them), records eight controls (K1 to K6, K8, K9), checks the refusal on
-- each broken state, installs 460 over a stand-in for 461 (on top of the
-- real 461 where it is in; and refuses a change elsewhere), then checks
-- each case after 460 (who holds what, the records and the origin, the
-- commission source, the credit statements, nothing read as used, a further
-- cancel and reopen, a refund by line and a Move afterwards, stock), the
-- controls exactly as before (with the cancel's refund due; K5, K6 are
-- NOT COVERED 4 (a): nothing reads as spent and Cancel takes it all back,
-- as in the plain Move, K8; K9, a merge after such a reopening, reads as at
-- 455), the record of a change, the review summary, the reopening refused
-- where what would go back fills the lot (S$60 and S$50 of S$100 by a
-- merge; with 461 S$55 by a change; S$49.99 allowed, then a change refuses
-- the lot as partly spent), credit of that lot that paid for a session
-- counted as taken (its section 6, by the merge and, with 461, by the
-- change: S$44 with S$20 of S$56 and S$40 with S$20 of S$60 refused, the
-- session's refund then going through; S$22 with S$20 of S$78 reopened,
-- the session refunded afterwards, the lot below what it was granted,
-- nothing read as spent, the refund due S$100, a change refused as partly
-- spent, Cancel taking it all back; and the payment refused, nothing
-- recorded, where a stand-in puts credit back on that lot while it waits),
-- and NOT COVERED 2, 3, 4 (with 4 (b)'s orders: M7, and X10 to X13 with
-- 461) and 7 as KNOWN.
-- Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ Four of the five functions this changes: BEFORE (production, 22 Oct
  -- 2026, at 455) and AFTER md5s (the fifth, invoice_reopen_preview, below)
  c_rb constant text := 'apply_reopened_invoice_benefits()';
  c_rv constant text := 'apply_reopened_invoice_vouchers()';
  c_mv constant text := 'move_invoice_benefits_to_customer(uuid,uuid,uuid,text)';
  c_tb constant text := 'invoice_transferable_benefits(uuid)';
  c_rb_before constant text := '75489db2b12e60a3104fff9ef76c2d20';
  c_rb_after  constant text := '3e659dafdbacb00ad953f99d00c3c6c9';
  c_rv_before constant text := '71d50be41b73decceb0b20f8597dd4fa';
  c_rv_after  constant text := '28d3b7a69b91ddebcdb200559d96a0ef';
  c_mv_before constant text := 'e313e87b4ab4c0063d924430996ffbd3';
  c_mv_after  constant text := '5a165f7035151f8f711fc2ac293e9b62';
  c_tb_before constant text := 'e3a4b753d87546a1a73342baf02bee70';
  c_tb_after  constant text := 'c568df874f2667f6a313d7aac0b4c086';
  -- 461 (another builder's, the same day) changes, in these two, only the
  -- lots a customer change moves (move_invoice_benefits_to_customer, between
  -- the two markers below) and the list's credit rows
  -- (invoice_transferable_benefits, its second of four parts). So each is
  -- compared with that part left out: as 447's / 417's (BEFORE) or this
  -- file's (AFTER), whatever that part holds. Everything else in them must be
  -- exactly as tested, and this file changes nothing in that part.
  c_mv_s constant text := E'  for r_lot in\n    select l.* from public.customer_credit_lots l\n';
  c_mv_e constant text := E'     for update\n  loop\n';
  c_tb_sep constant text := E'\n  union all\n';
  c_mv_nb constant text := 'a58d8344fccaeef481ca17fdf583b8bc';   -- 447's text, the lots' selection left out
  c_mv_na constant text := 'b434f77373e6ba07cc4b1fb30a2f4d50';   -- this file's, the same
  c_tb_nb constant text := 'f76166f80a84df5fbee2a3056d017f4b';   -- 417's text, the credit rows left out
  c_tb_na constant text := 'e5df1d68f73847f5d9faa7b04bfd81fe';   -- this file's, the same
  -- Who may call each, as read (kept).
  c_rb_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';
  c_rv_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';
  c_mv_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';
  c_tb_acl constant text := '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}';

  -- ══ The two helpers this adds (the server's alone) ═══════════════════════
  c_ov constant text := 'invoice_own_voucher_ids(uuid)';
  c_ov_after constant text := '9340840f1ce4e031ec3613198688ba2e';
  c_hd constant text := 'invoice_benefits_holder(uuid,uuid,timestamp with time zone)';
  c_hd_after constant text := '55995ff6e1ffd4a1172cb930512a34b0';
  c_h_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';
  c_ov_def constant text :=
$def$CREATE OR REPLACE FUNCTION public.invoice_own_voucher_ids(p_invoice_id uuid)
 RETURNS TABLE(voucher_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 460 (the Owner, 22 Oct 2026: "fix the other two rare gaps too"): the
  -- invoice's own vouchers, which a customer change that takes the benefits
  -- along moves (move_invoice_benefits_to_customer) and lists
  -- (invoice_transferable_benefits): what its voucher and promotion lines
  -- gave (sources 'invoice_voucher_sale', 'invoice_promotion_voucher'), and
  -- every voucher given again in place of one of them, by a reopening or by
  -- the payment after an FOC was taken off (source 'invoice_reopen', named
  -- by invoice_reopen_vouchers.replacement_voucher_id), however many times.
  -- Not a voucher an Owner moved to someone (source
  -- 'invoice_benefit_transfer': it stays with them, 434) nor one given again
  -- in its place, and not a Premium Bundle's (not transferable: a customer
  -- change leaves them where they are).
  with recursive own(id, n) as (
    select crv.id, 0
      from public.customer_reward_vouchers crv
     where crv.source_type in ('invoice_voucher_sale','invoice_promotion_voucher')
       and crv.source_id in (select it.id from public.invoice_items it where it.invoice_id = p_invoice_id)
    union all
    select q.replacement_voucher_id, o.n + 1
      from own o
      join public.invoice_benefit_values b on b.reward_voucher_id = o.id and b.invoice_id = p_invoice_id
      join public.invoice_reopen_vouchers q on q.benefit_id = b.id and q.invoice_id = p_invoice_id
     where q.replacement_voucher_id is not null and o.n < 64)
  select distinct o.id from own o
$function$
$def$;
  c_hd_def constant text :=
$def$CREATE OR REPLACE FUNCTION public.invoice_benefits_holder(p_invoice_id uuid, p_customer_id uuid, p_since timestamp with time zone)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 460 (the Owner, 22 Oct 2026: "fix the other two rare gaps too"): whom one
  -- of an invoice's own benefits belongs to now, when a reopening gives it
  -- back: held by p_customer_id (the voucher it replaces, or the lot the
  -- credit goes back on) since p_since (when that voucher or lot was made).
  -- Credit and vouchers follow a customer change that took the invoice's
  -- benefits along, and a merge (445, 447). So: the customer the latest such
  -- change moved them to, if one was made since p_since
  -- (move_invoice_benefits_to_customer records each in the invoice's Audit
  -- Log, 'invoice_benefits_followed_reassignment', 'to_customer'); a change
  -- that left them with their holder ('keep', 322) records none and moves
  -- nothing. Otherwise p_customer_id. Then, if that record was retired by a
  -- merge (merge_customer_records: the kept record's 'customers_merged' row
  -- names it in merged_from; its note names the kept record, so that row is
  -- looked up by the kept record's id first), the record that kept it,
  -- followed along a chain (A into B, then B into C: C). A p_since of
  -- 'infinity' follows merges alone (a Move's credit stays with whoever it
  -- was moved to, 434).
  with recursive k(id, n) as (
    select coalesce(
             (select (a.new_data->>'to_customer')::uuid from public.audit_logs a
               where a.record_id = p_invoice_id and a.table_name = 'invoices'
                 and a.action = 'invoice_benefits_followed_reassignment'
                 and a.created_at >= p_since
                 and coalesce(a.new_data->>'to_customer', '')
                     ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
               order by a.created_at desc, a.id desc limit 1),
             p_customer_id), 0
    union all
    select m.kept, k.n + 1
      from k
      join public.customers c on c.id = k.id and c.deleted_at is not null
      cross join lateral (
        select coalesce(
          (select l.record_id from public.audit_logs l
            where l.record_id in (select (x[1])::uuid
                                    from regexp_matches(coalesce(c.notes, ''),
                                           '\(([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\)', 'g') x)
              and l.action = 'customers_merged' and l.new_data->>'merged_from' = k.id::text
            order by l.created_at desc, l.id desc limit 1),
          (select l.record_id from public.audit_logs l
            where l.action = 'customers_merged' and l.new_data->>'merged_from' = k.id::text
            order by l.created_at desc, l.id desc limit 1)) as kept) m
     where k.n < 20 and m.kept is not null and m.kept <> k.id)
  select k.id from k order by k.n desc limit 1
$function$
$def$;

  -- ══ apply_reopened_invoice_benefits: the whole text (it is short) ═══════
  c_rb_def constant text :=
$def$CREATE OR REPLACE FUNCTION public.apply_reopened_invoice_benefits()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; l public.customer_credit_lots%rowtype;
 -- 460
 v460_put jsonb:='{}'::jsonb; g record; t public.customer_credit_lots%rowtype; x record;
 v460_h uuid; v460_total numeric; v460_new uuid; v460_wallet uuid; v460_spent numeric;
 v460_reason constant text:='Reopened invoice settled; the credit it gives back goes to whoever holds its benefits now';
 v460_named constant text:='Reopened invoice settled; credit refunded before its lot was reissued goes back on the lot the invoice names';
begin
 if new.status not in ('paid','completed_foc') then return new; end if;
 for r in select b.*,e.lot_id from public.invoice_reopen_benefits b join public.customer_credit_ledger e on e.id=b.source_ledger_id
   where b.invoice_id=new.id and b.applied_at is null order by b.id for update of b loop
   select * into l from public.customer_credit_lots where id=r.lot_id for update;
   update public.customer_credit_lots set remaining_amount=remaining_amount+r.amount,status='active',updated_at=now() where id=l.id;
   insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,reverses_entry_id,created_by,approved_by)
    values(l.wallet_id,l.customer_id,'reverse',l.category,r.amount,l.id,'invoice_reopen',r.request_id,l.store_id,'Reopened invoice settled',r.source_ledger_id,auth.uid(),auth.uid());
   update public.invoice_reopen_benefits set applied_at=now() where id=r.id;
   update public.invoice_benefit_values set cancelled_unused_value=greatest(0,cancelled_unused_value-r.amount) where lot_id=l.id;
   v460_put:=v460_put||jsonb_build_object(l.id::text,coalesce((v460_put->>l.id::text)::numeric,0)+r.amount);
 end loop;
 -- 460 (the Owner, 22 Oct 2026: "fix the other two rare gaps too"): what a
 -- reopened invoice gives back belongs to whoever its benefits belong to
 -- now. Above, each amount goes back on the lot it was taken from, as
 -- before. That lot may no longer be the one the invoice's records name
 -- (a merge or a customer change reissued what was left on it, 445, 447),
 -- or may be held by a record the benefits have left: one a merge retired,
 -- or the old customer after a customer change that took the benefits
 -- along (invoice_benefits_holder). Then what each benefit row holds, on its
 -- lot and on the lots it replaced, goes to that holder as one lot, carrying
 -- its origin (source, category, restrictions, store and dates, as 445 and
 -- 447 do) with reassigned_from_lot_id naming the lot it replaces, and the
 -- invoice's records name the new lot, so a later cancel, refund or Move
 -- finds it. A lot an Owner moved to someone (its benefit row replaced one
 -- of the invoice's) follows merges alone. Where the lot is the one named and
 -- its holder is the benefits', nothing more happens, as before. Where the
 -- named lot's benefit row was moved on, see below.
 for g in
  select s.target,jsonb_object_agg(s.lot_id::text,s.amount) as lots
    from (select p.key::uuid as lot_id,p.value::numeric as amount,
                 coalesce((select b.lot_id from public.invoice_benefit_values b
                            where b.invoice_id=new.id and b.lot_id is not null
                              and p.key::uuid in (with recursive c(id,n) as (
                                                    select b.lot_id,0
                                                    union all
                                                    select cl.reassigned_from_lot_id,c.n+1
                                                      from c join public.customer_credit_lots cl on cl.id=c.id
                                                     where cl.reassigned_from_lot_id is not null and c.n<12)
                                                  select c.id from c)
                            order by (b.lot_id=p.key::uuid) desc,b.created_at,b.id limit 1),p.key::uuid) as target
            from jsonb_each_text(v460_put) p) s
   group by s.target order by s.target
 loop
  select * into t from public.customer_credit_lots where id=g.target for update;
  -- A lot whose benefit row an Owner moved on (Move, 186) keeps its records,
  -- as in a merge (445) and a customer change (447): the credit moved is
  -- traced back through that row's lot (invoice_credit_transfer_origin), so
  -- the row cannot name another lot. What goes back on it stays there, as
  -- before (with whoever holds it: NOT COVERED 4). What goes back on a lot it
  -- replaced (a refund before a merge or a customer change reissued it, the
  -- Move after) goes onto it, where the records find it: drawn down there
  -- ('invoice_reopen_reassignment_out'), added to it ('adjust_increase',
  -- 'invoice_reopen_reassignment_in'), only while it then holds less than it
  -- was granted, counting what of its credit paid for other sales and can
  -- still come back onto it (the open part of its invoice line and special
  -- allocations: refund_invoice_recorded, correct_invoice_payment and
  -- refund_special_credit give it back on that lot). So a refund of such a
  -- sale always fits (a lot cannot hold more than it was granted), and the
  -- lot never reads as untouched, even after every such refund, so a
  -- customer change still refuses it as partly spent rather than moving it
  -- without its records (447, 461). Before, it stayed on the lot it was
  -- taken from, which no record names: Cancel and Refund in full asked a
  -- false credit_used, the cancel's refund due fell (S$100 to S$60 on a
  -- copy) and Cancel did not take it back. Where it would not fit, the
  -- reopening is refused (invoice_reopen_preview), so it does not get here;
  -- if it does all the same (credit came back on that lot while the
  -- reopening waited, by a way not found on a copy), this payment is
  -- refused with the reason, changing nothing. (The first text left the
  -- credit where it went back, silently: THE GAP again.)
  if exists(select 1 from public.invoice_benefit_values b
              join public.invoice_benefit_transfers bt on bt.source_benefit_id=b.id
             where b.lot_id=t.id) then
   select coalesce(sum(least(cl.remaining_amount,(g.lots->>cl.id::text)::numeric)),0) into v460_total
     from public.customer_credit_lots cl
    where cl.id<>t.id and cl.id in (select k::uuid from jsonb_object_keys(g.lots) k);
   continue when v460_total<=0;
   v460_spent:=coalesce((select sum(a.amount-coalesce(a.reversed_amount,0)) from public.invoice_line_credit_allocations a
                          where a.lot_id=t.id and a.amount>coalesce(a.reversed_amount,0)),0)
              +coalesce((select sum(s.amount-coalesce(s.reversed_amount,0)) from public.special_credit_allocations s
                          where s.lot_id=t.id and s.amount>coalesce(s.reversed_amount,0)),0);
   if t.remaining_amount+v460_total+v460_spent>=t.original_amount then
    raise exception 'Invoice % cannot be settled: it would give back S$% of credit refunded before its customer was changed or merged, the rest of which was then moved to someone else (Move), and the credit lot the invoice names for it cannot take that much back (it holds S$% of S$% granted, and S$% of its credit paid for other sales, which a refund puts back there). Nothing was recorded. Cancel the invoice again (its refund due stands), or ask the Owner.',
     new.invoice_no,to_char(v460_total,'FM999999990.00'),to_char(t.remaining_amount,'FM999999990.00'),
     to_char(t.original_amount,'FM999999990.00'),to_char(v460_spent,'FM999999990.00');
   end if;
   for x in select cl.*,least(cl.remaining_amount,(g.lots->>cl.id::text)::numeric) as amt
              from public.customer_credit_lots cl
             where cl.id<>t.id and cl.id in (select k::uuid from jsonb_object_keys(g.lots) k)
             order by cl.created_at,cl.id for update of cl loop
    continue when x.amt<=0;
    update public.customer_credit_lots set remaining_amount=remaining_amount-x.amt,updated_at=now() where id=x.id;
    insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
     values(x.wallet_id,x.customer_id,'adjust_decrease',x.category,x.amt,x.id,'invoice_reopen_reassignment_out',new.id,x.store_id,v460_named,auth.uid(),auth.uid());
   end loop;
   update public.customer_credit_lots set remaining_amount=remaining_amount+v460_total,status='active',updated_at=now() where id=t.id;
   insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
    values(t.wallet_id,t.customer_id,'adjust_increase',t.category,v460_total,t.id,'invoice_reopen_reassignment_in',new.id,t.store_id,v460_named,auth.uid(),auth.uid());
   continue;
  end if;
  v460_h:=public.invoice_benefits_holder(new.id,t.customer_id,
            case when exists(select 1 from public.invoice_benefit_values b
                               join public.invoice_benefit_transfers bt on bt.replacement_benefit_id=b.id
                              where b.invoice_id=new.id and b.lot_id=t.id) then 'infinity'::timestamptz
                 else t.created_at end);
  continue when v460_h=t.customer_id and not exists(select 1 from jsonb_object_keys(g.lots) k where k::uuid<>t.id);
  v460_new:=gen_random_uuid(); v460_wallet:=public.ensure_customer_wallet(v460_h); v460_total:=0;
  for x in select cl.*,case when cl.id=t.id then cl.remaining_amount
                            else least(cl.remaining_amount,(g.lots->>cl.id::text)::numeric) end as amt
             from public.customer_credit_lots cl
            where cl.id=t.id or cl.id in (select k::uuid from jsonb_object_keys(g.lots) k)
            order by cl.created_at,cl.id for update of cl loop
   continue when x.amt<=0;
   update public.customer_credit_lots set remaining_amount=remaining_amount-x.amt,updated_at=now() where id=x.id;
   insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
    values(x.wallet_id,x.customer_id,'adjust_decrease',x.category,x.amt,x.id,'invoice_reopen_reassignment_out',new.id,x.store_id,v460_reason,auth.uid(),auth.uid());
   v460_total:=v460_total+x.amt;
  end loop;
  continue when v460_total<=0;
  insert into public.customer_credit_lots
  select (jsonb_populate_record(null::public.customer_credit_lots,to_jsonb(t)||jsonb_build_object(
    'id',v460_new,'wallet_id',v460_wallet,'customer_id',v460_h,
    'original_amount',v460_total,'remaining_amount',v460_total,'status','active',
    'reassigned_from_lot_id',t.id,'reference_no',null,'reason',v460_reason,'reversal_of_lot_id',null,
    'created_by',auth.uid(),'approved_by',auth.uid(),'created_at',now(),'updated_at',now()))).*;
  insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
   values(v460_wallet,v460_h,'grant',t.category,v460_total,v460_new,'invoice_reopen_reassignment_in',new.id,t.store_id,v460_reason,auth.uid(),auth.uid());
  update public.invoice_benefit_values set lot_id=v460_new where lot_id=t.id;
  update public.credit_package_sales set credit_lot_id=v460_new where credit_lot_id=t.id;
  update public.credit_package_sales set bonus_credit_lot_id=v460_new where bonus_credit_lot_id=t.id;
  update public.premium_bundle_sales set paid_credit_lot_id=v460_new where paid_credit_lot_id=t.id;
  update public.premium_bundle_sales set bonus_credit_lot_id=v460_new where bonus_credit_lot_id=t.id;
  update public.invoice_credit_splits set issued_lot_id=v460_new where issued_lot_id=t.id;
 end loop;
 return new;
end $function$
$def$;

  -- ══ invoice_reopen_preview: the whole text (it is short) ═══════════════
  -- The Reopen dialog shows its blockers and keeps "Confirm reopening" off
  -- while there is one; reopen_invoice refuses with them.
  c_pv constant text := 'invoice_reopen_preview(uuid)';
  c_pv_before constant text := '7cb2805a10d92c41626e85a3542cc1f8';
  c_pv_after  constant text := '4b49c0c64eeb1b5962b605bbf56ea159';
  c_pv_acl constant text := '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}';
  c_pv_def constant text :=
$def$CREATE OR REPLACE FUNCTION public.invoice_reopen_preview(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb; v460 text; begin
 result:=public.invoice_reopen_preview_before_sessions(p_invoice_id);
 -- 460 (the Owner, 22 Oct 2026: "fix the other two rare gaps too"): credit
 -- refunded by line before a merge or a customer change reissued its lot,
 -- the rest then moved to someone else (Move): the payment that settles the
 -- reopened invoice puts it on the lot the invoice names for it
 -- (apply_reopened_invoice_benefits), which can take back only what keeps it
 -- below what it was granted, counting what of its credit paid for other
 -- sales and can still come back onto it (the open part of its invoice line
 -- and special allocations: a refund of such a sale gives it back there).
 -- It cannot be repointed: the moved credit is traced back through it.
 -- Where what would go back is that much or more, the reopening is refused,
 -- changing nothing; the invoice stays cancelled with its refund due.
 -- (Otherwise the credit was left on a lot no record names, so Cancel and
 -- Refund in full asked a false credit_used, the refund due fell and Cancel
 -- did not take it back; or a later refund of such a sale could not be
 -- recorded, the lot being full, or filled it, and a customer change then
 -- moved it without its records.) What goes back is what the payment would
 -- put back: the rows reopen_invoice queues (the invoice's cancellation and
 -- its refunds, on the lot and the lots it replaced) not queued yet, and
 -- those still waiting.
 with recursive mv as (
   select b.id as benefit_id, l.id as lot_id, l.remaining_amount, l.original_amount,
          coalesce((select sum(a.amount-coalesce(a.reversed_amount,0)) from public.invoice_line_credit_allocations a
                     where a.lot_id=l.id and a.amount>coalesce(a.reversed_amount,0)),0)
          +coalesce((select sum(s.amount-coalesce(s.reversed_amount,0)) from public.special_credit_allocations s
                     where s.lot_id=l.id and s.amount>coalesce(s.reversed_amount,0)),0) as spent
     from public.invoice_benefit_values b
     join public.customer_credit_lots l on l.id=b.lot_id
    where b.invoice_id=p_invoice_id and l.reassigned_from_lot_id is not null
      and exists(select 1 from public.invoice_benefit_transfers bt where bt.source_benefit_id=b.id)),
 ch(benefit_id,id,n) as (
   select mv.benefit_id,mv.lot_id,0 from mv
   union all
   select ch.benefit_id,cl.reassigned_from_lot_id,ch.n+1
     from ch join public.customer_credit_lots cl on cl.id=ch.id
    where cl.reassigned_from_lot_id is not null and ch.n<12),
 bk as (
   select ch.benefit_id,ch.id as lot_id,
          sum(case when q.id is null then e.amount when q.applied_at is null then q.amount else 0 end) as amount
     from ch
     join public.customer_credit_ledger e on e.lot_id=ch.id
     left join public.invoice_reopen_benefits q on q.source_ledger_id=e.id
    where e.source_type='invoice_cancel_benefit' and e.source_record_id=p_invoice_id
       or e.source_type='invoice_benefit_refund'
          and exists(select 1 from public.invoice_refunds r where r.invoice_id=p_invoice_id and r.request_id=e.source_record_id)
    group by ch.benefit_id,ch.id)
 select string_agg(format('Reopening would give back S$%s of credit refunded before this invoice''s customer was changed or merged, the rest of which was then moved to someone else (Move); the credit lot the invoice names for it cannot take that much back%s. Keep the invoice cancelled (its refund due stands), or ask the Owner.',
          to_char(s.older,'FM999999990.00'),
          case when mv.spent>0 then format(' (S$%s of its credit paid for other sales, which a refund puts back there)',
                                           to_char(mv.spent,'FM999999990.00')) else '' end),' ' order by mv.benefit_id) into v460
   from mv
   cross join lateral (select coalesce(sum(bk.amount) filter (where bk.lot_id<>mv.lot_id),0) as older,
                              coalesce(sum(bk.amount) filter (where bk.lot_id=mv.lot_id),0) as own
                         from bk where bk.benefit_id=mv.benefit_id) s
  where s.older>0 and mv.remaining_amount+s.own+s.older+mv.spent>=mv.original_amount;
 if v460 is not null then
  result:=result||jsonb_build_object('can_reopen',false,'blockers',coalesce(result->'blockers','[]'::jsonb)||jsonb_build_array(v460));
 end if;
 return result||jsonb_build_object('sessions_to_reinstate_after_settlement',(select coalesce(sum(quantity_refunded+quantity_cancelled),0)
  from public.customer_therapy_sessions where invoice_id=p_invoice_id and is_current));
end $function$
$def$;

  -- ══ apply_reopened_invoice_vouchers: whom the voucher given again goes to ═
  c_rv_a constant text := $a$  insert into public.customer_reward_vouchers(customer_id,voucher_id,store_id,quantity,status,issued_by,source_type,source_id,notes)
   values(v.customer_id,v.voucher_id,v.store_id,q.quantity,'held',auth.uid(),'invoice_reopen',q.id,'Replacement after explicit reopening; original voucher '||v.id)
$a$;
  c_rv_r constant text := $r$  -- 460 (the Owner, 22 Oct 2026: "fix the other two rare gaps too"): the
  -- voucher given again belongs to whoever holds the invoice's benefits now.
  -- In place of one of the invoice's own (its voucher or promotion lines',
  -- or one given again in place of one of them: invoice_own_voucher_ids),
  -- it goes to the customer a customer change that took the benefits along
  -- moved them to after the voucher it replaces was given, and to the record
  -- a merge kept (invoice_benefits_holder). Before, it went to whoever held
  -- the voucher it replaces: the old customer after such a change. In place
  -- of a voucher an Owner moved to someone, or a Premium Bundle's, it goes
  -- to whoever holds the one it replaces, as before (a merge moved that).
  -- At that voucher's store, as before.
  insert into public.customer_reward_vouchers(customer_id,voucher_id,store_id,quantity,status,issued_by,source_type,source_id,notes)
   values(case when v.id in (select o.voucher_id from public.invoice_own_voucher_ids(new.id) o)
               then public.invoice_benefits_holder(new.id,v.customer_id,v.issued_at) else v.customer_id end,
          v.voucher_id,v.store_id,q.quantity,'held',auth.uid(),'invoice_reopen',q.id,'Replacement after explicit reopening; original voucher '||v.id)
$r$;

  -- ══ move_invoice_benefits_to_customer: the vouchers it moves; its record ═
  c_mv_a1 constant text := $a$  perform 1 from public.customer_reward_vouchers
   where source_type in ('invoice_voucher_sale','invoice_promotion_voucher')
     and source_id in (select id from public.invoice_items where invoice_id = p_invoice_id)
$a$;
  c_mv_r1 constant text := $r$  -- 460 (the Owner, 22 Oct 2026: "fix the other two rare gaps too"): the
  -- invoice's own vouchers (invoice_own_voucher_ids): its voucher and
  -- promotion lines', and those given again in place of one of them by a
  -- reopening or by the payment after an FOC came off ('invoice_reopen').
  -- Before, only the first two sources, so a voucher given again stayed
  -- with the old customer. Not one an Owner moved to someone (434), nor a
  -- Premium Bundle's, as before.
  perform 1 from public.customer_reward_vouchers
   where id in (select o.voucher_id from public.invoice_own_voucher_ids(p_invoice_id) o)
$r$;
  c_mv_a2 constant text := $a$     where rv.source_type in ('invoice_voucher_sale','invoice_promotion_voucher')
       and rv.source_id in (select id from public.invoice_items where invoice_id = p_invoice_id)
$a$;
  c_mv_r2 constant text := $r$     where rv.id in (select o.voucher_id from public.invoice_own_voucher_ids(p_invoice_id) o)   -- 460
$r$;
  c_mv_a3 constant text := $a$     set customer_id = p_customer_id, store_id = p_store_id
   where source_type in ('invoice_voucher_sale','invoice_promotion_voucher')
     and source_id in (select id from public.invoice_items where invoice_id = p_invoice_id)
$a$;
  c_mv_r3 constant text := $r$     set customer_id = p_customer_id, store_id = p_store_id
   where id in (select o.voucher_id from public.invoice_own_voucher_ids(p_invoice_id) o)   -- 460
$r$;
  c_mv_a4 constant text := $a$  if v_v + v_c + v_a > 0 then
    perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_benefits_followed_reassignment',
      null, jsonb_build_object('vouchers', v_v, 'credit_lots', v_c, 'allowances', v_a,
                               'to_customer', p_customer_id, 'reason', p_reason),
      'invoices', p_reason, p_store_id);
  end if;
$a$;
  c_mv_r4 constant text := $r$  -- 460 (the Owner, 22 Oct 2026): recorded for every change that takes the
  -- benefits along, also when nothing was left to move (a reopened invoice
  -- whose vouchers and credit wait, a line refunded before the change): what
  -- a reopening gives back later goes to this customer
  -- (invoice_benefits_holder reads it). Before, only when something moved.
  perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_benefits_followed_reassignment',
    null, jsonb_build_object('vouchers', v_v, 'credit_lots', v_c, 'allowances', v_a,
                             'to_customer', p_customer_id, 'reason', p_reason),
    'invoices', p_reason, p_store_id);
$r$;

  -- ══ invoice_transferable_benefits: the vouchers it lists ═══════════════
  c_tb_a constant text := $a$   where crv.source_type in ('invoice_voucher_sale','invoice_promotion_voucher')
     and crv.source_id in (select id from public.invoice_items where invoice_id = p_invoice_id)
$a$;
  c_tb_r constant text := $r$   -- 460 (the Owner, 22 Oct 2026): the invoice's own vouchers, as a
   -- customer change moves them (invoice_own_voucher_ids): also those given
   -- again in place of one of them, so the review summary lists every
   -- voucher that moves.
   where crv.id in (select o.voucher_id from public.invoice_own_voucher_ids(p_invoice_id) o)
$r$;

  -- ══ Relied on, not changed (production, 22 Oct 2026, at 455) ════════════
  -- Not pinned: correct_invoice, refund_invoice_recorded and reopen_invoice
  -- (456 to 458, another session's, may change them; what this relies on in
  -- them is checked by its text below), create_invoice and
  -- record_invoice_payment (the self-test runs them), and 461's two.
  c_relied constant text[] := array[
    'merge_customer_records(uuid,uuid,text,uuid)',
    'transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)',
    'trg_issue_sold_vouchers_on_paid()',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'invoice_benefit_unused_elsewhere(uuid)',
    'invoice_commission_benefit_source(uuid)',
    'ensure_customer_wallet(uuid)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'trg_credit_lot_immutable()'];
  c_relied_md5 constant text[] := array[
    '2e0c9852099ab88d8f27827b5f9a3846',
    '7aebd7120bc3928db46df0941cb20889',
    'c840d0d2754e7a8e889848ea8269a293',
    'de52d9dbaef8ab15163bef35cb9d733d',
    'd35d7c8ae7187985ea64f8a5c38a7d79',
    'f8d3d29fae79065a252a8c5231cc2d4b',
    '8ef18daebbbe3c12f2024290ea8416e8',
    'c705c733e213a27f0dc32d54322cc855',
    '0fc74da0dcc9b436dfd26c4582542f6c'];
  -- Every column that names a lot, as 445 and 447 read them: the five this
  -- repoints, and the ten that record what happened to a lot or are
  -- followed along (kept).
  c_lot_refs constant text :=
    'credit_package_progress_lots.lot_id, credit_package_progress_lots.replaces_lot_id, '
    'credit_package_sales.bonus_credit_lot_id, credit_package_sales.credit_lot_id, customer_credit_adjustments.lot_id, '
    'customer_credit_allocations.lot_id, customer_credit_ledger.lot_id, customer_credit_lots.reassigned_from_lot_id, '
    'customer_credit_lots.reversal_of_lot_id, invoice_benefit_values.lot_id, invoice_credit_splits.issued_lot_id, '
    'invoice_line_credit_allocations.lot_id, premium_bundle_sales.bonus_credit_lot_id, '
    'premium_bundle_sales.paid_credit_lot_id, special_credit_allocations.lot_id';
  c_lot_trigger constant text := 'CREATE TRIGGER credit_lot_immutable BEFORE DELETE OR UPDATE ON public.customer_credit_lots FOR EACH ROW EXECUTE FUNCTION trg_credit_lot_immutable()';
  c_plain constant text[] := array['invoice_benefit_values', 'credit_package_sales', 'premium_bundle_sales',
                                   'invoice_credit_splits', 'invoice_benefit_transfers', 'invoice_reopen_vouchers'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  r record; v text; d text; d2 text; n int; k int; i int; v_first boolean; v_parts text[];
  v_sig text; v_after text; v_want text; v_norm text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[] := '{}'; v_mk text[] := '{}';
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_pk uuid; t_vch uuid;
  t_a uuid; t_k uuid; t_b uuid; t_c uuid; t_inv uuid; t_lot uuid; t_ans jsonb; t_lines jsonb;
  t_d uuid; t_e uuid; t_f uuid; t_g uuid; t_h uuid; t_msg text;
  t_i uuid; t_j uuid; t_svc uuid; t_inv2 uuid; t_wallet uuid;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The texts are the tested ones.
  if md5(c_ov_def) <> c_ov_after or md5(c_hd_def) <> c_hd_after or md5(c_rb_def) <> c_rb_after or md5(c_pv_def) <> c_pv_after then
    raise exception '460: a text in this file is not the tested one (% % % %)', md5(c_ov_def), md5(c_hd_def), md5(c_rb_def), md5(c_pv_def); end if;

  -- The functions relied on are as read on production (22 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '460: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if to_regprocedure('auth.uid()') is null then raise exception '460: auth.uid() must be there'; end if;

  -- What it relies on in the three not pinned, read from their text:
  -- correct_invoice moves the benefits only on 'transfer' (322);
  -- reopen_invoice queues credit by the ledger rows a cancellation and the
  -- refunds wrote (on the lots they took it from); refund_invoice_recorded's
  -- 446 step gives a waiting row back on the benefit's own lot.
  if position(E'   if coalesce(p_header->>''benefit_action'','''') = ''transfer'' then\n     perform public.move_invoice_benefits_to_customer(i.id,n.customer_id,n.store_id,'
              in pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure)) = 0 then
    raise exception '460: correct_invoice no longer moves the benefits only on ''transfer'' as read on 22 Oct 2026; re-read it and re-test'; end if;
  if position($q$ insert into public.invoice_reopen_benefits(invoice_id,source_ledger_id,request_id,amount,created_by)
  select i.id,l.id,p_request_id,l.amount,auth.uid() from public.customer_credit_ledger l$q$
              in pg_get_functiondef('public.reopen_invoice(uuid,text,uuid)'::regprocedure)) = 0 then
    raise exception '460: reopen_invoice no longer queues credit by ledger row as read on 22 Oct 2026; re-read it and re-test'; end if;
  if position($q$where q.invoice_id=i.id and q.applied_at is null and e.lot_id=l.id$q$
              in pg_get_functiondef('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'::regprocedure)) = 0 then
    raise exception '460: refund_invoice_recorded''s 446 step is not as read on 22 Oct 2026; re-read it and re-test'; end if;

  -- No other function takes the names this changes or adds (the API picks
  -- an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('apply_reopened_invoice_benefits', 'apply_reopened_invoice_vouchers', 'move_invoice_benefits_to_customer',
                       'invoice_transferable_benefits', 'invoice_own_voucher_ids', 'invoice_benefits_holder',
                       'invoice_reopen_preview')
     and p.oid::regprocedure::text not in (c_rb, c_rv, c_mv, c_tb, c_ov, c_hd, c_pv);
  if v is not null then raise exception '460: another function takes the name of one this changes or adds: %', v; end if;

  -- Who calls them, as read: move_invoice_benefits_to_customer only
  -- correct_invoice; the list correct_invoice and preview_invoice_correction
  -- (and, with 461, move_invoice_benefits_to_customer); the two triggers no
  -- function. (A session's own temporary functions are not counted.)
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'move_invoice_benefits_to_customer\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and not (p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = c_mv);
  if v is distinct from 'correct_invoice(uuid,jsonb,jsonb,text,uuid)' then
    raise exception '460: the functions that call move_invoice_benefits_to_customer are not as read on 22 Oct 2026 (%); check each, then re-test', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'invoice_transferable_benefits\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and not (p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text in (c_tb, c_mv));
  if v is distinct from 'correct_invoice(uuid,jsonb,jsonb,text,uuid), preview_invoice_correction(uuid,jsonb)' then
    raise exception '460: the functions that call invoice_transferable_benefits are not as read on 22 Oct 2026 (%); check each, then re-test', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'apply_reopened_invoice_(benefits|vouchers)\s*\(' and ns.nspname not like 'pg\_temp\_%';
  if v is not null then
    raise exception '460: a function calls the reopening''s triggers (%; none did on 22 Oct 2026); check it, then re-test', v; end if;
  -- invoice_reopen_preview: reopen_invoice refuses on its blockers (and the
  -- Reopen dialog shows them); it builds on the preview before sessions,
  -- which gives can_reopen and blockers (read by name, not pinned: 456 to
  -- 458 may change it).
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'invoice_reopen_preview\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and not (p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = c_pv);
  if v is distinct from 'reopen_invoice(uuid,text,uuid)' then
    raise exception '460: the functions that call invoice_reopen_preview are not as read on 24 Oct 2026 (%); check each, then re-test', v; end if;
  if position($q$ p:=public.invoice_reopen_preview(i.id);
 if not (p->>'can_reopen')::boolean then raise exception 'Reopening requires resolution: %',p->'blockers'; end if;$q$
              in pg_get_functiondef('public.reopen_invoice(uuid,text,uuid)'::regprocedure)) = 0 then
    raise exception '460: reopen_invoice no longer refuses on the preview''s blockers as read on 24 Oct 2026; re-read it and re-test'; end if;
  if to_regprocedure('public.invoice_reopen_preview_before_sessions(uuid)') is null
     or (select prorettype from pg_proc where oid = to_regprocedure('public.invoice_reopen_preview_before_sessions(uuid)')) <> 'jsonb'::regtype
     or position($q$jsonb_build_object('can_reopen',cardinality(blockers)=0,'blockers',to_jsonb(blockers),$q$
                 in pg_get_functiondef(to_regprocedure('public.invoice_reopen_preview_before_sessions(uuid)'))) = 0 then
    raise exception '460: invoice_reopen_preview_before_sessions does not give can_reopen and blockers as read on 24 Oct 2026; re-read it and re-test'; end if;
  -- The settling payment runs them, as read.
  for r in select * from (values
      ('invoice_reopen_benefits_settled', 'CREATE TRIGGER invoice_reopen_benefits_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_benefits()'),
      ('invoice_reopen_vouchers_settled', 'CREATE TRIGGER invoice_reopen_vouchers_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_vouchers()')) x(tg, def)
  loop
    if (select pg_get_triggerdef(t.oid) from pg_trigger t
         where t.tgrelid = 'public.invoices'::regclass and t.tgname = r.tg and t.tgenabled = 'O') is distinct from r.def then
      raise exception '460: the trigger % on public.invoices is not the one read on 22 Oct 2026', r.tg; end if;
  end loop;

  -- Tables and columns, as read on 22 Oct 2026.
  select string_agg(c.relname || '.' || a.attname, ', ' order by c.relname || '.' || a.attname) into v
    from pg_constraint kc
    join pg_class c on c.oid = kc.conrelid
    join pg_attribute a on a.attrelid = kc.conrelid and a.attnum = any (kc.conkey)
   where kc.contype = 'f' and kc.confrelid = 'public.customer_credit_lots'::regclass;
  if v is distinct from c_lot_refs then
    raise exception '460: the columns that name a credit lot are not as read on 22 Oct 2026 (%); decide for each new one whether the lot given back repoints it, then re-test', v; end if;
  if (select string_agg(pg_get_triggerdef(t.oid), ' | ') from pg_trigger t
       where t.tgrelid = 'public.customer_credit_lots'::regclass and not t.tgisinternal) is distinct from c_lot_trigger then
    raise exception '460: the triggers on customer_credit_lots are not as read on 22 Oct 2026'; end if;
  select string_agg(t.tgrelid::regclass::text || ' ' || t.tgname, ', ') into v
    from pg_trigger t
   where t.tgrelid in (select to_regclass('public.' || x) from unnest(c_plain) x) and not t.tgisinternal;
  if v is not null then raise exception '460: these tables have triggers they did not have on 22 Oct 2026: %', v; end if;
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('customer_reward_vouchers', 'id', 'uuid'), ('customer_reward_vouchers', 'customer_id', 'uuid'),
                 ('customer_reward_vouchers', 'source_type', 'text'), ('customer_reward_vouchers', 'source_id', 'uuid'),
                 ('customer_reward_vouchers', 'status', 'text'), ('customer_reward_vouchers', 'issued_at', 'timestamp with time zone'),
                 ('customer_reward_vouchers', 'notes', 'text'),
                 ('invoice_reopen_vouchers', 'invoice_id', 'uuid'), ('invoice_reopen_vouchers', 'benefit_id', 'uuid'),
                 ('invoice_reopen_vouchers', 'replacement_voucher_id', 'uuid'), ('invoice_reopen_vouchers', 'applied_at', 'timestamp with time zone'),
                 ('invoice_reopen_benefits', 'invoice_id', 'uuid'), ('invoice_reopen_benefits', 'source_ledger_id', 'uuid'),
                 ('invoice_reopen_benefits', 'amount', 'numeric(12,2)'), ('invoice_reopen_benefits', 'applied_at', 'timestamp with time zone'),
                 ('invoice_benefit_values', 'lot_id', 'uuid'), ('invoice_benefit_values', 'reward_voucher_id', 'uuid'),
                 ('invoice_benefit_values', 'created_at', 'timestamp with time zone'),
                 ('invoice_benefit_transfers', 'source_benefit_id', 'uuid'), ('invoice_benefit_transfers', 'replacement_benefit_id', 'uuid'),
                 ('customer_credit_lots', 'reassigned_from_lot_id', 'uuid'), ('customer_credit_lots', 'created_at', 'timestamp with time zone'),
                 ('customer_credit_lots', 'customer_id', 'uuid'), ('customer_credit_lots', 'source_type', 'text'),
                 ('customer_credit_ledger', 'reverses_entry_id', 'uuid'), ('customer_credit_ledger', 'reason', 'text'),
                 ('customers', 'deleted_at', 'timestamp with time zone'), ('customers', 'notes', 'text'),
                 ('audit_logs', 'table_name', 'text'), ('audit_logs', 'record_id', 'uuid'), ('audit_logs', 'action', 'text'),
                 ('audit_logs', 'new_data', 'jsonb'), ('audit_logs', 'created_at', 'timestamp with time zone'),
                 ('invoices', 'invoice_no', 'text'),
                 ('invoice_line_credit_allocations', 'lot_id', 'uuid'), ('invoice_line_credit_allocations', 'amount', 'numeric(12,2)'),
                 ('invoice_line_credit_allocations', 'reversed_amount', 'numeric(12,2)'),
                 ('special_credit_allocations', 'lot_id', 'uuid'), ('special_credit_allocations', 'amount', 'numeric(14,2)'),
                 ('special_credit_allocations', 'reversed_amount', 'numeric(14,2)')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '460: these columns are missing or not as read on 22 Oct 2026: %', v; end if;
  -- What can put credit back on a lot (a lot's balance raised by an amount),
  -- as read on 24 Oct 2026: the reopening's own settlement, and three that
  -- give back what a sale paid with credit by reversing its allocation (an
  -- invoice's wallet payment refunded or corrected: invoice_line_credit_
  -- allocations; a special document's credit refunded: special_credit_
  -- allocations). The settlement and the preview count the open part of
  -- those allocations on the lot the invoice names for a benefit moved on,
  -- so a refund of such a sale always fits on it. A new way would need the
  -- same counting: the file stops.
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'remaining_amount\s*=\s*(\w+\.)?remaining_amount\s*\+' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from 'apply_reopened_invoice_benefits(), correct_invoice_payment(uuid,numeric,date,uuid,text,uuid), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), refund_special_credit(text,uuid)'
     or position('invoice_line_credit_allocations' in pg_get_functiondef('public.correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)'::regprocedure)) = 0
     or position('invoice_line_credit_allocations' in pg_get_functiondef('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'::regprocedure)) = 0
     or position('special_credit_allocations' in pg_get_functiondef('public.refund_special_credit(text,uuid)'::regprocedure)) = 0 then
    raise exception '460: the functions that can put credit back on a lot are not as read on 24 Oct 2026 (%); check that each gives back only by reversing an allocation the settlement counts, then re-test', v; end if;

  -- The two helpers: absent (added) or this version (left alone).
  foreach v_sig in array array[c_ov, c_hd] loop
    v_after := case when v_sig = c_ov then c_ov_after else c_hd_after end;
    if to_regprocedure('public.' || v_sig) is not null
       and md5(pg_get_functiondef(to_regprocedure('public.' || v_sig))) <> v_after then
      raise exception '460: public.% is there but not this version (md5 %)', v_sig,
        md5(pg_get_functiondef(to_regprocedure('public.' || v_sig))); end if;
  end loop;

  -- Each changed function: its BEFORE (changed; each anchor found once; the
  -- text built has its AFTER md5) or its AFTER (left alone). The two 461
  -- changes are compared with 461's part left out (above).
  foreach v_sig in array array[c_rb, c_pv, c_rv, c_mv, c_tb] loop
    if to_regprocedure('public.' || v_sig) is null then raise exception '460: public.% is missing', v_sig; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || v_sig));
    if v_sig = c_rb then
      if md5(d) = c_rb_after then v_first := false; raise notice '460: public.% is already this version; left alone', v_sig; continue; end if;
      if md5(d) <> c_rb_before then
        raise exception '460: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', v_sig, md5(d); end if;
      v_first := true;
      v_fns := v_fns || v_sig; v_defs := v_defs || c_rb_def;
    elsif v_sig = c_pv then
      if md5(d) = c_pv_after then raise notice '460: public.% is already this version; left alone', v_sig; continue; end if;
      if md5(d) <> c_pv_before then
        raise exception '460: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', v_sig, md5(d); end if;
      v_fns := v_fns || v_sig; v_defs := v_defs || c_pv_def;
    elsif v_sig = c_rv then
      if md5(d) = c_rv_after then raise notice '460: public.% is already this version; left alone', v_sig; continue; end if;
      n := (length(d) - length(replace(d, c_rv_a, ''))) / length(c_rv_a);
      if n <> 1 then raise exception '460: the anchor of public.% is found % times, not once (md5 %)', v_sig, n, md5(d); end if;
      d2 := replace(d, c_rv_a, c_rv_r);
      if md5(d) <> c_rv_before then
        raise exception '460: public.% is not the version this was tested against (md5 %; changed it would be md5 %). Re-read it and re-test before applying.', v_sig, md5(d), md5(d2); end if;
      if md5(d2) <> c_rv_after then raise exception '460: the text built for public.% is not the tested one (md5 %)', v_sig, md5(d2); end if;
      v_fns := v_fns || v_sig; v_defs := v_defs || d2;
    elsif v_sig = c_mv then
      if (length(d) - length(replace(d, c_mv_s, ''))) / length(c_mv_s) <> 1
         or (length(d) - length(replace(d, c_mv_e, ''))) / length(c_mv_e) <> 1
         or strpos(d, c_mv_s) > strpos(d, c_mv_e) then
        raise exception '460: public.% has not one lots'' selection where 447 has it (md5 %). Re-read it and re-test before applying.', v_sig, md5(d); end if;
      v_norm := left(d, strpos(d, c_mv_s) + length(c_mv_s) - 1) || '…' || substr(d, strpos(d, c_mv_e));
      if md5(v_norm) = c_mv_na then raise notice '460: public.% is already this version; left alone', v_sig; continue; end if;
      if md5(v_norm) <> c_mv_nb then
        raise exception '460: public.% is not the version this was tested against, outside the lots'' selection 461 may change (md5 %, there %). Re-read it and re-test before applying.', v_sig, md5(d), md5(v_norm); end if;
      d2 := d;
      foreach v in array array['1', '2', '3', '4'] loop
        n := (length(d2) - length(replace(d2, case v when '1' then c_mv_a1 when '2' then c_mv_a2 when '3' then c_mv_a3 else c_mv_a4 end, '')))
             / length(case v when '1' then c_mv_a1 when '2' then c_mv_a2 when '3' then c_mv_a3 else c_mv_a4 end);
        if n <> 1 then raise exception '460: anchor % of public.% is found % times, not once', v, v_sig, n; end if;
        d2 := replace(d2, case v when '1' then c_mv_a1 when '2' then c_mv_a2 when '3' then c_mv_a3 else c_mv_a4 end,
                          case v when '1' then c_mv_r1 when '2' then c_mv_r2 when '3' then c_mv_r3 else c_mv_r4 end);
      end loop;
      v_norm := left(d2, strpos(d2, c_mv_s) + length(c_mv_s) - 1) || '…' || substr(d2, strpos(d2, c_mv_e));
      if md5(v_norm) <> c_mv_na or (md5(d) = c_mv_before and md5(d2) <> c_mv_after) then
        raise exception '460: the text built for public.% is not the tested one (md5 %, outside the lots'' selection %)', v_sig, md5(d2), md5(v_norm); end if;
      v_fns := v_fns || v_sig; v_defs := v_defs || d2;
    else
      v_parts := string_to_array(d, c_tb_sep);
      if cardinality(v_parts) <> 4 then
        raise exception '460: public.% is not four parts as on 22 Oct 2026 (md5 %). Re-read it and re-test before applying.', v_sig, md5(d); end if;
      v_parts[2] := '…';
      v_norm := array_to_string(v_parts, c_tb_sep);
      if md5(v_norm) = c_tb_na then raise notice '460: public.% is already this version; left alone', v_sig; continue; end if;
      if md5(v_norm) <> c_tb_nb then
        raise exception '460: public.% is not the version this was tested against, outside the credit rows 461 may change (md5 %, there %). Re-read it and re-test before applying.', v_sig, md5(d), md5(v_norm); end if;
      n := (length(d) - length(replace(d, c_tb_a, ''))) / length(c_tb_a);
      if n <> 1 or strpos(d, c_tb_a) > strpos(d, c_tb_sep) then
        raise exception '460: the anchor of public.% is found % times, not once in its vouchers'' part', v_sig, n; end if;
      d2 := replace(d, c_tb_a, c_tb_r);
      v_parts := string_to_array(d2, c_tb_sep); v_parts[2] := '…';
      v_norm := array_to_string(v_parts, c_tb_sep);
      if md5(v_norm) <> c_tb_na or (md5(d) = c_tb_before and md5(d2) <> c_tb_after) then
        raise exception '460: the text built for public.% is not the tested one (md5 %, outside the credit rows %)', v_sig, md5(d2), md5(v_norm); end if;
      v_fns := v_fns || v_sig; v_defs := v_defs || d2;
    end if;
  end loop;

  -- On the first run (apply_reopened_invoice_benefits its BEFORE): nothing
  -- a reopening gave back went to a record the benefits had left, nothing
  -- waits that may, and no voucher given again stayed behind a customer
  -- change. Each is the state this file prevents, already there: what the
  -- customers hold then needs a decision first, so the file stops, changing
  -- nothing, and names the invoices. None on 22 Oct 2026 (the voucher queue
  -- has never had a row; the credit queue's four rows, on one invoice, were
  -- settled on 11 Sep 2026 and nothing waits). A second run skips this: what
  -- the reopenings since gave back went where this file says.
  if v_first then
    -- (1) Credit put back, at a settlement, on a lot that was no longer the
    -- one the invoice's records named (a merge or a customer change had
    -- reissued it), or of a record a merge had retired, or of a customer the
    -- benefits had left by a customer change made since the lot was made.
    -- Not on the lot a benefit row moved on by a Move names: this file
    -- leaves that credit where it goes back (NOT COVERED 4), so it is not a
    -- state this file prevents. On a lot that one replaced (a refund before
    -- a merge or a customer change, the Move after) it is: the credit is on
    -- a lot no record names.
    select count(distinct iv.id), string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into i, v
      from public.invoice_reopen_benefits q
      join public.invoices iv on iv.id = q.invoice_id
      join public.customer_credit_ledger e on e.reverses_entry_id = q.source_ledger_id
                                          and e.entry_type = 'reverse' and e.source_type = 'invoice_reopen'
                                          and e.reason = 'Reopened invoice settled'
      join public.customer_credit_lots l on l.id = e.lot_id
     where q.applied_at is not null
       and not exists (select 1 from public.invoice_benefit_values b
                         join public.invoice_benefit_transfers bt on bt.source_benefit_id = b.id
                        where b.invoice_id = q.invoice_id and b.lot_id = l.id)
       and (exists (select 1 from public.customer_credit_lots nl where nl.reassigned_from_lot_id = l.id and nl.created_at <= e.created_at)
            or exists (select 1 from public.audit_logs a where a.action = 'customers_merged'
                        and a.new_data->>'merged_from' = l.customer_id::text and a.created_at <= e.created_at)
            or (l.source_type is distinct from 'invoice_benefit_transfer'
                and coalesce((select a.new_data->>'to_customer' from public.audit_logs a
                               where a.record_id = q.invoice_id and a.table_name = 'invoices'
                                 and a.action = 'invoice_benefits_followed_reassignment'
                                 and a.created_at >= l.created_at and a.created_at <= e.created_at
                               order by a.created_at desc, a.id desc limit 1), l.customer_id::text) <> l.customer_id::text));
    if i > 0 then
      raise exception '460: % invoice(s) had credit put back by a reopening on a record its benefits had left (%). Decide what each customer should hold, then apply. Nothing was changed.', i, v; end if;
    -- (2) A voucher given again by a reopening to someone other than the
    -- customer a customer change (made after the voucher it replaced was
    -- given) had moved the benefits to; (3) a voucher given again and held
    -- when such a change was made after it, which stayed behind.
    select count(distinct iv.id), string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into i, v
      from public.invoice_reopen_vouchers q
      join public.invoices iv on iv.id = q.invoice_id
      join public.customer_reward_vouchers rv on rv.id = q.replacement_voucher_id
      join public.invoice_benefit_values b on b.id = q.benefit_id
      join public.customer_reward_vouchers ov on ov.id = b.reward_voucher_id
     where q.applied_at is not null
       and ov.source_type not in ('invoice_benefit_transfer', 'premium_bundle')
       and ((rv.notes like 'Replacement after explicit reopening;%'
             and coalesce((select a.new_data->>'to_customer' from public.audit_logs a
                            where a.record_id = q.invoice_id and a.table_name = 'invoices'
                              and a.action = 'invoice_benefits_followed_reassignment'
                              and a.created_at >= ov.issued_at and a.created_at <= q.applied_at
                            order by a.created_at desc, a.id desc limit 1), rv.customer_id::text) <> rv.customer_id::text)
            or (rv.status = 'held'
                and coalesce((select a.new_data->>'to_customer' from public.audit_logs a
                               where a.record_id = q.invoice_id and a.table_name = 'invoices'
                                 and a.action = 'invoice_benefits_followed_reassignment'
                                 and a.created_at > rv.issued_at
                               order by a.created_at desc, a.id desc limit 1), rv.customer_id::text) <> rv.customer_id::text));
    if i > 0 then
      raise exception '460: % invoice(s) have a voucher a reopening gave again held by a customer its benefits had left (%). Decide what each customer should hold, then apply. Nothing was changed.', i, v; end if;
    -- (4) A reopened invoice still waiting (credit or vouchers) whose
    -- customer is not the one what waits would go to: a change made while it
    -- waited, before this file, left no record of whether the benefits were
    -- taken along.
    select count(distinct iv.id), string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into i, v
      from public.invoices iv
     where (exists (select 1 from public.invoice_reopen_benefits q
                      join public.customer_credit_ledger e on e.id = q.source_ledger_id
                      join public.customer_credit_lots l on l.id = e.lot_id
                     where q.invoice_id = iv.id and q.applied_at is null and l.customer_id is distinct from iv.customer_id)
            or exists (select 1 from public.invoice_reopen_vouchers q
                         join public.invoice_benefit_values b on b.id = q.benefit_id
                         join public.customer_reward_vouchers ov on ov.id = b.reward_voucher_id
                        where q.invoice_id = iv.id and q.applied_at is null and ov.customer_id is distinct from iv.customer_id));
    if i > 0 then
      raise exception '460: % reopened invoice(s) wait with credit or vouchers held by someone other than their customer (%). Decide who should receive them, then apply. Nothing was changed.', i, v; end if;
  end if;

  -- Who may call each, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  foreach v_sig in array array[c_rb, c_pv, c_rv, c_mv, c_tb] loop
    v_want := case v_sig when c_rb then c_rb_acl when c_pv then c_pv_acl when c_rv then c_rv_acl when c_mv then c_mv_acl else c_tb_acl end;
    if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || v_sig))
       is distinct from (select array_agg(x::text order by x::text) from unnest(v_want::aclitem[]) x) then
      raise exception '460: who may call public.% is not as read on 22 Oct 2026 (%)', v_sig,
        (select proacl::text from pg_proc where oid = to_regprocedure('public.' || v_sig)); end if;
    v_acl := v_acl || (select coalesce(string_agg(x::text, ',' order by x::text), '')
                         from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || v_sig));
  end loop;

  -- ── Change ──────────────────────────────────────────────────────────────
  -- The helpers first (the others call them), the server's alone.
  foreach v_sig in array array[c_ov, c_hd] loop
    if to_regprocedure('public.' || v_sig) is null then
      execute case when v_sig = c_ov then c_ov_def else c_hd_def end;
      execute format('revoke all on function public.%s from public, anon, authenticated', v_sig);
      execute format('grant execute on function public.%s to service_role', v_sig);
    else
      raise notice '460: public.% is already this version; left alone', v_sig;
    end if;
  end loop;
  for k in 1 .. coalesce(cardinality(v_fns), 0) loop
    execute v_defs[k];
  end loop;

  -- ── Afterwards: installed exactly as tested, grants as before ────────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_ov))) <> c_ov_after
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_hd))) <> c_hd_after
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_rb))) <> c_rb_after
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_rv))) <> c_rv_after
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_pv))) <> c_pv_after then
    raise exception '460: a function is not at its AFTER md5'; end if;
  d := pg_get_functiondef(to_regprocedure('public.' || c_mv));
  if md5(left(d, strpos(d, c_mv_s) + length(c_mv_s) - 1) || '…' || substr(d, strpos(d, c_mv_e))) <> c_mv_na then
    raise exception '460: public.% is not at its AFTER (md5 %)', c_mv, md5(d); end if;
  d := pg_get_functiondef(to_regprocedure('public.' || c_tb));
  v_parts := string_to_array(d, c_tb_sep); v_parts[2] := '…';
  if md5(array_to_string(v_parts, c_tb_sep)) <> c_tb_na then
    raise exception '460: public.% is not at its AFTER (md5 %)', c_tb, md5(d); end if;
  k := 0;
  foreach v_sig in array array[c_rb, c_pv, c_rv, c_mv, c_tb] loop
    k := k + 1;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || v_sig)) is distinct from v_acl[k] then
      raise exception '460: the grants of public.% changed', v_sig; end if;
  end loop;
  foreach v_sig in array array[c_ov, c_hd] loop
    if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || v_sig))
       is distinct from (select array_agg(x::text order by x::text) from unnest(c_h_acl::aclitem[]) x) then
      raise exception '460: who may call public.% is not the server alone', v_sig; end if;
  end loop;
  if has_function_privilege('anon', 'public.' || c_tb, 'execute')
     or not has_function_privilege('authenticated', 'public.' || c_tb, 'execute')
     or has_function_privilege('authenticated', 'public.' || c_mv, 'execute')
     or has_function_privilege('authenticated', 'public.' || c_ov, 'execute')
     or has_function_privilege('authenticated', 'public.' || c_hd, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_hd, 'execute')
     or has_function_privilege('anon', 'public.' || c_pv, 'execute')
     or not has_function_privilege('authenticated', 'public.' || c_pv, 'execute') then
    raise exception '460: who may call the functions is not as intended'; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("460 check", @example.invalid, fictional ACMA phones
  -- no customer uses); it ends by raising P0460, which undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from unnest(array['+61491570960', '+61491570961', '+61491570962', '+61491570963',
                                                 '+61491570964', '+61491570965', '+61491570966', '+61491570967',
                                                 '+61491570968', '+61491570969', '+61491570970', '+61491570971',
                                                 '+61491570972', '+61491570973', '+61491570974', '+61491570975']) p
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p limit 11);
    if coalesce(cardinality(t_phones), 0) < 11 then raise exception '460: the self-test found no eleven unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '460-check-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '460 check', '460-check-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('460 check ' || t_sfx, '460-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('460 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy, grants_reward)
    values ('460 check ' || t_sfx, 100, 100, false, true, true, false) returning id into t_pk;
    insert into public.credit_package_stores (package_id, store_id) values (t_pk, t_store);
    insert into public.vouchers (name, code, voucher_kind, selling_price, qty_type, is_active)
    values ('460 check ' || t_sfx, '460-' || t_sfx, 'normal', 30, 'unlimited', true) returning id into t_vch;
    insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store) values (t_vch, t_store, 30, true);
    insert into public.customers (full_name, phone) values ('460 Check First ' || t_sfx, t_phones[1]) returning id into t_a;
    insert into public.customers (full_name, phone) values ('460 Check Kept ' || t_sfx, t_phones[2]) returning id into t_k;
    insert into public.customers (full_name, phone) values ('460 Check Second ' || t_sfx, t_phones[3]) returning id into t_b;
    insert into public.customers (full_name, phone) values ('460 Check Third ' || t_sfx, t_phones[4]) returning id into t_c;
    insert into public.customers (full_name, phone) values ('460 Check Fourth ' || t_sfx, t_phones[5]) returning id into t_d;
    insert into public.customers (full_name, phone) values ('460 Check Fourth Kept ' || t_sfx, t_phones[6]) returning id into t_e;
    insert into public.customers (full_name, phone) values ('460 Check Friend ' || t_sfx, t_phones[7]) returning id into t_f;
    insert into public.customers (full_name, phone) values ('460 Check Fifth ' || t_sfx, t_phones[8]) returning id into t_g;
    insert into public.customers (full_name, phone) values ('460 Check Fifth Kept ' || t_sfx, t_phones[9]) returning id into t_h;
    insert into public.customers (full_name, phone) values ('460 Check Sixth ' || t_sfx, t_phones[10]) returning id into t_i;
    insert into public.customers (full_name, phone) values ('460 Check Sixth Kept ' || t_sfx, t_phones[11]) returning id into t_j;

    -- (a) 448's NOT COVERED 2: S$40 of the package refunded by line, the
    -- buyer merged into the kept record, cancelled, reopened, paid: the kept
    -- record holds the S$100 on one lot the benefit and the sale name, the
    -- retired record nothing, and nothing reads as spent.
    t_inv := public.create_invoice(t_store, t_a, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', (select it.id from public.invoice_items it where it.invoice_id = t_inv), 'amount', 40,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', (select b.id from public.invoice_benefit_values b where b.invoice_id = t_inv), 'amount', 40)))),
      jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt'
                                                           order by p.created_at limit 1), 'amount', 40)), '[]'::jsonb, '460 check', gen_random_uuid());
    perform public.merge_customer_records(t_k, t_a, '460 check: the same person', gen_random_uuid());
    perform public.cancel_invoice_recorded(t_inv, '460 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '460 check', gen_random_uuid());
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 40)), gen_random_uuid());
    select b.lot_id into t_lot from public.invoice_benefit_values b where b.invoice_id = t_inv;
    if (select status::text from public.invoices where id = t_inv) is distinct from 'paid'
       or (select l.customer_id from public.customer_credit_lots l where l.id = t_lot) is distinct from t_k
       or (select l.remaining_amount from public.customer_credit_lots l where l.id = t_lot) is distinct from 100.00
       or (select s.credit_lot_id from public.credit_package_sales s where s.invoice_id = t_inv) is distinct from t_lot
       or (select coalesce(sum(l.remaining_amount), 0) from public.customer_credit_lots l where l.customer_id = t_a) <> 0
       or exists (select 1 from jsonb_array_elements(coalesce(public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->'overrides_required', '[]'::jsonb)) o
                   where o->>'code' = 'credit_used') then
      raise exception '460: (a) merged after a refund, settled: the kept record does not hold the S$100 on the lot the invoice names'; end if;

    -- (b) A customer change with the benefits taken along while the
    -- reopened invoice waits (credit and vouchers): paid, the new customer
    -- holds what waited, the old customer nothing.
    t_inv := public.create_invoice(t_store, t_b, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1),
                        jsonb_build_object('kind', 'voucher', 'voucher_id', t_vch, 'quantity', 2)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 160)), gen_random_uuid());
    perform public.cancel_invoice_recorded(t_inv, '460 check', gen_random_uuid());
    select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'amount', case when it.line_kind::text = 'voucher' then 60 else 100 end,
             'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', b.id, 'amount', b.paid_value))
                            from public.invoice_benefit_values b where b.invoice_item_id = it.id)))
      into t_lines from public.invoice_items it where it.invoice_id = t_inv;
    perform public.refund_invoice_recorded(t_inv, t_lines,
      jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt'
                                                           order by p.created_at limit 1), 'amount', 160)), '[]'::jsonb, '460 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '460 check', gen_random_uuid());
    t_ans := public.correct_invoice(t_inv,
      (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind, 'credit_package_id', it.credit_package_id,
                 'voucher_id', it.voucher_id, 'quantity', it.quantity, 'unit_price', it.unit_price)) order by it.id)
         from public.invoice_items it where it.invoice_id = t_inv),
      jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = t_inv),
                         'customer_id', t_c, 'benefit_action', 'transfer'), '460 check', gen_random_uuid());
    if not exists (select 1 from public.audit_logs a where a.record_id = t_inv and a.action = 'invoice_benefits_followed_reassignment'
                    and a.new_data->>'to_customer' = t_c::text) then
      raise exception '460: (b) the customer change while it waits was not recorded: %', t_ans; end if;
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 160)), gen_random_uuid());
    select b.lot_id into t_lot from public.invoice_benefit_values b where b.invoice_id = t_inv and b.lot_id is not null;
    if (select status::text from public.invoices where id = t_inv) is distinct from 'paid'
       or (select l.customer_id from public.customer_credit_lots l where l.id = t_lot) is distinct from t_c
       or (select l.remaining_amount from public.customer_credit_lots l where l.id = t_lot) is distinct from 100.00
       or (select s.credit_lot_id from public.credit_package_sales s where s.invoice_id = t_inv) is distinct from t_lot
       or (select coalesce(sum(l.remaining_amount), 0) from public.customer_credit_lots l where l.customer_id = t_b) <> 0
       or (select coalesce(sum(v.quantity), 0) from public.customer_reward_vouchers v where v.customer_id = t_c and v.status = 'held') <> 2
       or exists (select 1 from public.customer_reward_vouchers v where v.customer_id = t_b and v.status = 'held') then
      raise exception '460: (b) changed while waiting, settled: the new customer does not hold the S$100 and the 2 vouchers'; end if;

    -- (c) Settled (the reopening's 2 vouchers given), then the customer
    -- changed with the benefits taken along: the 2 move.
    t_inv := public.create_invoice(t_store, t_k, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', t_vch, 'quantity', 2)), 0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)), gen_random_uuid());
    perform public.cancel_invoice_recorded(t_inv, '460 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '460 check', gen_random_uuid());
    perform public.correct_invoice(t_inv,
      (select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id, 'quantity', 2, 'unit_price', 30))
         from public.invoice_items it where it.invoice_id = t_inv),
      jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = t_inv),
                         'customer_id', t_b, 'benefit_action', 'transfer'), '460 check', gen_random_uuid());
    if (select coalesce(sum(v.quantity), 0) from public.invoice_benefit_values b join public.customer_reward_vouchers v on v.id = b.reward_voucher_id
         where b.invoice_id = t_inv and v.status = 'held' and v.customer_id = t_b and v.source_type = 'invoice_reopen') <> 2 then
      raise exception '460: (c) the vouchers the reopening gave did not move with the customer change'; end if;

    -- (d) The same wait as (b), the customer changed with the benefits left
    -- where they are ('keep'): paid, the old customer holds the 2, as before.
    t_inv := public.create_invoice(t_store, t_c, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', t_vch, 'quantity', 2)), 0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)), gen_random_uuid());
    perform public.cancel_invoice_recorded(t_inv, '460 check', gen_random_uuid());
    perform public.refund_invoice_recorded(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 60)),
      jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt'
                                                           order by p.created_at limit 1), 'amount', 60)), '[]'::jsonb, '460 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '460 check', gen_random_uuid());
    perform public.correct_invoice(t_inv,
      (select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id, 'quantity', 2, 'unit_price', 30))
         from public.invoice_items it where it.invoice_id = t_inv),
      jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = t_inv),
                         'customer_id', t_k, 'benefit_action', 'keep'), '460 check', gen_random_uuid());
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)), gen_random_uuid());
    if (select coalesce(sum(v.quantity), 0) from public.invoice_benefit_values b join public.customer_reward_vouchers v on v.id = b.reward_voucher_id
         where b.invoice_id = t_inv and v.status = 'held' and v.customer_id = t_c) <> 2 then
      raise exception '460: (d) kept with the old customer while waiting, settled: the old customer does not hold the 2'; end if;

    -- (e) NOT COVERED 4, as before: S$40 of the package refunded by line,
    -- the S$60 left moved to a friend (Move), cancelled, reopened, the
    -- customer changed ('transfer'), paid: the S$40 is back on the lot the
    -- benefit row and the sale name, with the buyer; no lot is added for it;
    -- nothing reads as spent, and the cancel's refund due is the S$100.
    t_inv := public.create_invoice(t_store, t_b, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
    select b.lot_id into t_lot from public.invoice_benefit_values b where b.invoice_id = t_inv;
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', (select it.id from public.invoice_items it where it.invoice_id = t_inv), 'amount', 40,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', (select b.id from public.invoice_benefit_values b where b.invoice_id = t_inv), 'amount', 40)))),
      jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt'
                                                           order by p.created_at limit 1), 'amount', 40)), '[]'::jsonb, '460 check', gen_random_uuid());
    perform public.transfer_invoice_unused_benefit((select b.id from public.invoice_benefit_values b where b.invoice_id = t_inv),
      t_c, t_store, '460 check', gen_random_uuid());
    perform public.cancel_invoice_recorded(t_inv, '460 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '460 check', gen_random_uuid());
    perform public.correct_invoice(t_inv,
      (select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'credit_package', 'credit_package_id', it.credit_package_id,
                                           'quantity', 1, 'unit_price', it.unit_price))
         from public.invoice_items it where it.invoice_id = t_inv),
      jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = t_inv),
                         'customer_id', t_k, 'benefit_action', 'transfer'), '460 check', gen_random_uuid());
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 40)), gen_random_uuid());
    t_ans := public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb);
    if (select status::text from public.invoices where id = t_inv) is distinct from 'paid'
       or (select l.customer_id from public.customer_credit_lots l where l.id = t_lot) is distinct from t_b
       or (select l.remaining_amount from public.customer_credit_lots l where l.id = t_lot) is distinct from 40.00
       or (select s.credit_lot_id from public.credit_package_sales s where s.invoice_id = t_inv) is distinct from t_lot
       or exists (select 1 from public.customer_credit_lots l where l.reassigned_from_lot_id = t_lot)
       or exists (select 1 from jsonb_array_elements(coalesce(t_ans->'overrides_required', '[]'::jsonb)) o where o->>'code' = 'credit_used')
       or (t_ans->>'refund_due')::numeric is distinct from 100.00 then
      raise exception '460: (e) refunded, moved, changed, settled: the S$40 is not back with the buyer on the lot the invoice names, or it reads as spent (%)', t_ans->'refund_due'; end if;

    -- (f) THE GAP of 460 with 461 (the together check, 24 Oct 2026), by the
    -- merge (there at 455): S$40 refunded by line, the buyer merged into the
    -- kept record, the kept record's S$60 moved to a friend (Move),
    -- cancelled, reopened, paid: the S$40 is on the kept record's lot, which
    -- the benefit row and the sale name; no lot is added; the buyer holds
    -- nothing; nothing reads as spent; the cancel's refund due is S$100.
    t_inv := public.create_invoice(t_store, t_d, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', (select it.id from public.invoice_items it where it.invoice_id = t_inv), 'amount', 40,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', (select b.id from public.invoice_benefit_values b where b.invoice_id = t_inv), 'amount', 40)))),
      jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt'
                                                           order by p.created_at limit 1), 'amount', 40)), '[]'::jsonb, '460 check', gen_random_uuid());
    perform public.merge_customer_records(t_e, t_d, '460 check: the same person', gen_random_uuid());
    select b.lot_id into t_lot from public.invoice_benefit_values b where b.invoice_id = t_inv;
    perform public.transfer_invoice_unused_benefit((select b.id from public.invoice_benefit_values b where b.invoice_id = t_inv and b.lot_id = t_lot),
      t_f, t_store, '460 check', gen_random_uuid());
    perform public.cancel_invoice_recorded(t_inv, '460 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '460 check', gen_random_uuid());
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 40)), gen_random_uuid());
    t_ans := public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb);
    if (select status::text from public.invoices where id = t_inv) is distinct from 'paid'
       or (select l.customer_id from public.customer_credit_lots l where l.id = t_lot) is distinct from t_e
       or (select l.remaining_amount from public.customer_credit_lots l where l.id = t_lot) is distinct from 40.00
       or (select s.credit_lot_id from public.credit_package_sales s where s.invoice_id = t_inv) is distinct from t_lot
       or exists (select 1 from public.customer_credit_lots l where l.reassigned_from_lot_id = t_lot)
       or (select coalesce(sum(l.remaining_amount), 0) from public.customer_credit_lots l where l.customer_id = t_d) <> 0
       or (select coalesce(sum(l.remaining_amount), 0) from public.customer_credit_lots l where l.customer_id = t_f) <> 60
       or exists (select 1 from jsonb_array_elements(coalesce(t_ans->'overrides_required', '[]'::jsonb)) o where o->>'code' = 'credit_used')
       or (t_ans->>'refund_due')::numeric is distinct from 100.00 then
      raise exception '460: (f) refunded, merged, moved, settled: the S$40 is not on the lot the invoice names, or it reads as spent (%)', t_ans->'refund_due'; end if;

    -- (g) The same with S$60 refunded (S$40 left and moved on): giving the
    -- S$60 back would fill the lot the invoice names or more, so the
    -- reopening is refused, changing nothing.
    t_inv := public.create_invoice(t_store, t_g, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', (select it.id from public.invoice_items it where it.invoice_id = t_inv), 'amount', 60,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', (select b.id from public.invoice_benefit_values b where b.invoice_id = t_inv), 'amount', 60)))),
      jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt'
                                                           order by p.created_at limit 1), 'amount', 60)), '[]'::jsonb, '460 check', gen_random_uuid());
    perform public.merge_customer_records(t_h, t_g, '460 check: the same person', gen_random_uuid());
    perform public.transfer_invoice_unused_benefit((select b.id from public.invoice_benefit_values b where b.invoice_id = t_inv),
      t_f, t_store, '460 check', gen_random_uuid());
    perform public.cancel_invoice_recorded(t_inv, '460 check', gen_random_uuid());
    t_ans := public.invoice_reopen_preview(t_inv);
    t_msg := null;
    begin
      perform public.reopen_invoice(t_inv, '460 check', gen_random_uuid());
    exception when others then t_msg := sqlerrm;
    end;
    if (t_ans->>'can_reopen')::boolean or t_msg is null
       or position('Reopening would give back S$60.00 of credit refunded before this invoice''s customer was changed or merged' in t_msg) = 0
       or (select status::text from public.invoices where id = t_inv) is distinct from 'cancelled'
       or exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = t_inv) then
      raise exception '460: (g) a reopening that would leave credit on no record was not refused (%; %)', t_ans->'blockers', t_msg; end if;

    -- (h) The review of 24 Oct 2026: credit of the lot the records name that
    -- paid for another sale counts as taken, since a refund of that sale
    -- gives it back there. S$40 refunded by line, the buyer merged into the
    -- kept record, which pays S$20 for a session from that lot (its wallet),
    -- the S$40 left moved to a friend, cancelled: S$40 to go back and S$20
    -- that can come back would fill the S$60 lot, so the reopening is
    -- refused, changing nothing; the session's refund then goes back on that
    -- lot (S$20 of S$60).
    insert into public.therapy_services (service_code, name, standard_price, duration_minutes, is_active)
    values ('460-' || t_sfx, '460 check ' || t_sfx, 20, 30, true) returning id into t_svc;
    insert into public.therapy_service_stores (service_id, store_id, is_available) values (t_svc, t_store, true);
    select pm.id into t_wallet from public.payment_methods pm
     where pm.name = 'Wallet — Credit Package Paid' and pm.is_wallet_credit and pm.deleted_at is null;
    if t_wallet is null then raise exception '460: (h) the wallet method "Wallet — Credit Package Paid" is not there'; end if;
    t_inv := public.create_invoice(t_store, t_i, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', (select it.id from public.invoice_items it where it.invoice_id = t_inv), 'amount', 40,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', (select b.id from public.invoice_benefit_values b where b.invoice_id = t_inv), 'amount', 40)))),
      jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt'
                                                           order by p.created_at limit 1), 'amount', 40)), '[]'::jsonb, '460 check', gen_random_uuid());
    perform public.merge_customer_records(t_j, t_i, '460 check: the same person', gen_random_uuid());
    select b.lot_id into t_lot from public.invoice_benefit_values b where b.invoice_id = t_inv;
    t_inv2 := public.create_invoice(t_store, t_j, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 1)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv2, jsonb_build_array(jsonb_build_object('payment_method_id', t_wallet, 'amount', 20)), gen_random_uuid());
    if (select l.remaining_amount from public.customer_credit_lots l where l.id = t_lot) is distinct from 40.00 then
      raise exception '460: (h) the session was not paid from the lot the invoice names'; end if;
    perform public.transfer_invoice_unused_benefit((select b.id from public.invoice_benefit_values b where b.invoice_id = t_inv and b.lot_id = t_lot),
      t_f, t_store, '460 check', gen_random_uuid());
    perform public.cancel_invoice_recorded(t_inv, '460 check', gen_random_uuid());
    t_ans := public.invoice_reopen_preview(t_inv);
    t_msg := null;
    begin
      perform public.reopen_invoice(t_inv, '460 check', gen_random_uuid());
    exception when others then t_msg := sqlerrm;
    end;
    if (t_ans->>'can_reopen')::boolean or t_msg is null
       or position('Reopening would give back S$40.00 of credit refunded before this invoice''s customer was changed or merged' in t_msg) = 0
       or position('(S$20.00 of its credit paid for other sales, which a refund puts back there)' in t_msg) = 0
       or (select status::text from public.invoices where id = t_inv) is distinct from 'cancelled'
       or exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = t_inv) then
      raise exception '460: (h) a reopening that would leave no room for a refund of credit spent from the lot was not refused (%; %)', t_ans->'blockers', t_msg; end if;
    perform public.cancel_invoice_recorded(t_inv2, '460 check', gen_random_uuid());
    perform public.refund_invoice_recorded(t_inv2, jsonb_build_array(jsonb_build_object('amount', 20)),
      jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_inv2 and p.entry_kind = 'receipt'
                                                           order by p.created_at limit 1), 'amount', 20)), '[]'::jsonb, '460 check', gen_random_uuid());
    if (select l.remaining_amount from public.customer_credit_lots l where l.id = t_lot) is distinct from 20.00
       or (select l.customer_id from public.customer_credit_lots l where l.id = t_lot) is distinct from t_j then
      raise exception '460: (h) the session''s refund did not go back on the lot the invoice names'; end if;

    raise exception using errcode = 'P0460', message = '460: self-test done, undone';
  exception when sqlstate 'P0460' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
