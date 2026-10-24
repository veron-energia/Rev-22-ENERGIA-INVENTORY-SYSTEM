-- 462_moved_and_merged_credit_follows_its_records.sql
--
-- CREDIT AN OWNER MOVED, A MERGE KEPT OR A REOPENING GAVE BACK FOLLOWS ITS
-- RECORDS; CREDIT A REFUNDED OR CORRECTED SALE GIVES BACK GOES TO WHOEVER
-- HOLDS THE INVOICE'S BENEFITS NOW (460's NOT COVERED 4 (a) to (d), 461's
-- NOT COVERED 3, 445's moved lot partly taken back; the Owner, 22 Oct 2026:
-- "fix the other two rare gaps too", and 24 Oct 2026: "B, the package's
-- holder now")
--
-- WHO FOUND IT
--
--   The builders of 445, 447, 460 and 461 (their NOT COVERED lists and the
--   KNOWN cases of their suites). Catalogued and reproduced on 24 Oct 2026
--   on copies of production (20 cases with variants), three designs were
--   built and judged (the winner: "repoint everything, retrace along the
--   chain"), and a critic's review of the plan (24 Oct 2026) found eight
--   things, handled here: the forwarder (P5 below) runs at commit, after a
--   payment correction re-spends the credit, and gives one new lot per lot
--   per transaction (an immediate trigger refused the Finance panel's
--   Correct payment on a wallet payment, or moved the payer's other credit,
--   and a 13-line sale's refund made a chain longer than the readers
--   follow); the base is production at 464; the Owner answered the open
--   decision (B); a deleted holder never gets credit; the suite's invariant
--   reads the invoice's whole lot family; the trace's install check allows
--   a lot it newly traces and refuses a Move without its two ledger rows;
--   'rental_late_fee' is forwarded and the invoice is locked first.
--   A second review of the built file (24 Oct 2026; five critics, each
--   finding reproduced on copies of its own) found, and this handles: (1)
--   credit given back while the package's invoice was cancelled or its
--   reopening waited was forwarded and the records repointed, but the
--   reopening's records read the lots its cancellation took from: a reserve
--   (cancelled_unused_value) stayed, so Refund in full then left the new
--   customer S$40 of credit, a Move or a change was refused, a cancel held
--   back S$140 of S$100, and a refund by line made while it waited was given
--   back twice (V1, V3, X1, X2, W3F); (2) each separate refund that was
--   forwarded made the chain one lot longer, so after 13 a Move's recipient
--   could not spend its credit and from the 14th the credit stayed on a lot
--   no record names (DEEP13, DEEP14, CH1, CH2); (3) once the benefits' holder
--   had a reissued lot and was deleted, credit given back stayed on a lot no
--   record names (DH3); (4) every wallet refund locked the package's invoice
--   at commit, even when nothing moved, so a plain refund racing a Cancel of
--   the package deadlocked, and the app does not retry; (5) the install did
--   not refuse K9's state where the kept record had spent the reissued lot
--   to S$0, whose refund then stayed there; (6) the header was out of date
--   (production is at 467). Rebuilt and tested on copies of production at
--   464 (432fcb99, 1379 functions; 465 and 467 change only TikTok
--   functions, and 462 installs and passes on them too), made-up records,
--   the app's own calls, every app call with its commit.
--
-- WHAT WAS WRONG
--
--   An Owner's Move (transfer_invoice_unused_benefit, 186) of a benefit
--   row's credit leaves that row naming the emptied lot, and the moved
--   credit's origin was traced through that lot (invoice_credit_transfer_
--   origin: the lot asked about must be the one granted, the source row's
--   lot must hold at least what was moved). So the row could never be
--   repointed: a merge (merge_customer_records, 445), a customer change
--   that takes the benefits along (move_invoice_benefits_to_customer, 447
--   and 461) and a reopening's give-back (apply_reopened_invoice_benefits,
--   460) left its records where they were, and 460 refused a reopening
--   where what went back would not fit on that lot. On copies, each with a
--   S$100 package (S$100 + S$10 where it says so), S$40 refunded by line and
--   the S$60 left moved to a friend F:
--   * cancelled, reopened, the customer changed A to B, paid: the S$40 went
--     back to A, B got nothing (K5; the same with the change before the
--     cancel, or the guided Refund in full; A could then spend it, and B's
--     Cancel then asked credit_used with its due S$80); paid first, then
--     changed: refused as "Partly spent" (K5b; the same after a merge, and
--     a second change of a S$100 + S$10 package: S$44);
--   * merged A into K while it waited, or before the cancel: the S$40 went
--     to the retired record, K could not spend it (K6, K6b; merged into F:
--     F got only the S$60);
--   * settled, then A merged into K: K got the S$40 on a lot no record
--     names: Cancel asked credit_used, its refund due was S$60 of S$100,
--     Refund in full kept S$40 "for used credit", a refund by line said
--     nothing was left to refund (K9, K9r, K9b, a merge chain M7b, X9c);
--   * the benefits leaving the named lot's holder after the Move (a merge
--     chain while it waits, M7; the new customer merged or changed again,
--     X10 to X13): the S$40 (S$44) stayed with that holder, often a retired
--     record;
--   * S$50 or more refunded before the merge or the change that reissued
--     the lot: the reopening was refused (R1, R1b, R2, L3, R5; and where
--     S$20 of the lot had paid for a session, R3, R3b, S3);
--   * a session paid from the lot, the rest moved, the session refunded:
--     the change was refused "Partly spent" though nothing was spent (S1,
--     S2, R4), or, after the change, the S$20 went back to the old customer
--     (S4); refunded after a reissue (no Move needed: G1b, R3n): the S$20
--     stayed on a lot no record names, Cancel asked credit_used, due S$80;
--   * a moved lot partly refunded, then its holder merged: the kept record
--     could not spend it ("needs review", F3a);
--   * a lot a reopening's payment reissued to the new customer after a
--     session was paid from the package read as untouched (it was granted
--     only what was left), so a second customer change moved the S$80 as if
--     nothing had been spent (R3c; 461's rule is that real spending blocks
--     the change).
--   Nothing was ever lost (Cancel took everything back from whoever held
--   it), but credit sat with the wrong customer or on a lot no record
--   names, the plans asked overrides they should not, refund dues were
--   short, and reopenings and changes were refused.
--
-- THE OWNER'S ANSWERS
--
--   22 Oct 2026: credit and vouchers follow a merge, and follow a customer
--   change that takes the benefits along ('transfer'), not 'keep'; a Move's
--   recipient keeps what was moved; refunds already paid back are not used.
--   24 Oct 2026, decision 1: credit a refunded sale gives back after a
--   'transfer' change goes to "B, the package's holder now", on the lot the
--   records name (S4, S4m, G1b; the D1 paths). Decisions 2 (a Move to the
--   same customer at another store is taken along by a later change) and 3
--   (Premium Bundle vouchers follow a change) are for 463 (NOT COVERED 1).
--
-- WHAT THIS DOES (four functions added, six changed, one trigger, one index;
-- no table or column changes; grants of the six kept)
--
--   * P1 invoice_credit_transfer_origin(uuid) (whole text): the Move's
--     credit is traced through the two lots the Move itself wrote in the
--     append-only ledger, the lot it drew from ('invoice_benefit_transfer_
--     out') and the lot it granted ('invoice_benefit_transfer_in'). The lot
--     asked about is the granted lot or one reissued from it, on the chain
--     of the lot the Move's replacement row names now; the lot drawn from is
--     on the chain of the lot its source row names now; the granted lot
--     holds what was moved at the transfer's store; what was moved is no
--     more than the drawn-from lot was granted; the lot asked about holds no
--     more than was granted, at the same store, with the drawn-from lot's
--     category and restrictions. A Move without both ledger rows keeps the
--     old rule (none may exist when this is applied: SAFETY).
--     credit_lot_ancestry(uuid) (new, the server's alone): a lot and the
--     lots it was reissued from (a link to a lot of another source, which a
--     Move before 445 copied, is not a reissue), at most 12 back.
--   * P2 merge_customer_records (one anchor): the records of a row moved
--     on follow the reissued lot like any other's.
--   * P3 move_invoice_benefits_to_customer (two anchors) and
--     invoice_transferable_benefits (its credit rows; 461's markers kept):
--     a Move is no claim on a lot any more and its records follow; P3b: a
--     reissued lot a benefit row of the invoice names is judged by that row
--     (448's test), so real spending on an earlier lot still blocks the
--     change as "Partly spent" instead of letting the rest move as
--     untouched.
--   * P4 apply_reopened_invoice_benefits (whole text): 460's way for a row
--     moved on (the credit added onto the named lot, or the payment refused)
--     is gone; such a row reissues to whoever holds the benefits like any
--     other, on a new lot the records name. What the cancellation held back
--     (cancelled_unused_value) comes off the benefit row the lot's chain
--     leads to, not only a row naming that very lot (a merge while it waits
--     reissues it). Everything the named lot and the lots it replaced hold
--     goes to the holder, not only what was put back (credit given back on
--     a replaced lot while the invoice was cancelled, or while it waited,
--     waits for this payment: P5). A new lot more than 12 down its chain is
--     refused, for the Owner, as is credit off a named lot with no live
--     record to give it to. invoice_reopen_preview (whole text): 460's
--     refusal is gone (it always fits now).
--   * P5 credit_given_back_follows(uuid) and trg_credit_given_back_follows()
--     (new, the server's alone), run by the constraint trigger
--     credit_given_back_follows, AFTER INSERT ON customer_credit_ledger,
--     DEFERRABLE INITIALLY DEFERRED (at commit), for each 'reverse' row of
--     the sources customer_credit_statement lists as credit returned
--     ('invoice_payment_refund', 'payment_correction', 'special_sale',
--     'rental'), with 'rental_late_fee' (a special document's kind), not
--     'invoice_reopen' (the reopening's own, which P4 settles in the same
--     statement, and 446's queued pair, which raises nothing), nor a
--     reversal or a provenance repair. At commit, where the lot the credit
--     went back on is one an invoice's benefit row names, or one such a lot
--     was reissued from (the nearest named lot reissued from it): if
--     anything is on a lot it replaced, or the named lot's holder is not
--     whoever holds the benefits now, what those lots and the named lot hold
--     goes to that holder as ONE new lot (drawn down,
--     'credit_given_back_reassignment_out'; granted, '..._in'; copying the
--     named lot's source, category, restrictions, store and dates), the
--     records name it, and the invoice's Audit Log says so
--     ('credit_given_back_followed'). The new lot replaces the named lot
--     (reassigned_from_lot_id naming it); where the named lot is one this
--     made and nothing has touched since (its grant its only ledger row), the
--     new lot takes its place instead (reassigned_from_lot_id naming what it
--     replaced), so separate refunds keep the chain as it is: it grows only
--     where the holder spent from the lot between them. A lot more than 12
--     down its chain, or credit given back more than 12 lots up from the lot
--     the records name, is refused at commit, for the Owner (the readers
--     follow 12). Nothing happens while that invoice is cancelled, refunded
--     or asked to be, or a reopening of it waits to be settled: the credit
--     stays where it went back and the payment that settles the reopening
--     gives it to the holder (P4; NOT COVERED 10). Otherwise nothing
--     happens. Because it runs at commit it sees what the whole call did: a
--     Correct payment that keeps a wallet method re-spends the credit first,
--     so a date-only correction leaves everything where it was, and a refund
--     of a sale with many lines gives one new lot, not one per line. It
--     never raises an existing lot. Whether anything needs doing is read
--     first without a lock (a refund that moves nothing locks nothing here);
--     only then are the named invoice, its benefit row and the lots locked,
--     in that order, as Cancel and Reopen take them, and everything read
--     again. A Move's lot is held by its recipient (merges followed).
--   * The holder (both P4 and P5): invoice_credit_live_holder (new, the
--     server's alone): 460's invoice_benefits_holder, but never a deleted
--     record that was not merged (delete_customer refuses only while a
--     customer holds credit, so a holder with nothing left can be deleted):
--     then the invoice's customer if not deleted, else the named lot's
--     holder if not deleted; then (P5, P4) the holder of the lot the credit
--     went back on, if not deleted. With none, credit on the named lot stays
--     there, and credit on a lot it replaced is refused, for the Owner
--     (NOT COVERED 7).
--   * A partial index on customer_credit_ledger(source_record_id) for the
--     two Move source types (the trace reads them).
--   Money afterwards (the suite, each case): the credit is with whoever
--   holds the benefits, on a lot the records name, with its origin; nothing
--   reads as spent unless it was; Cancel's refund due and Refund in full are
--   what was received less real spending; Cancel takes it back from them.
--
-- NOT CHANGED
--
--   * refund_invoice_recorded, correct_invoice_payment, refund_special_
--     credit (they raise the lot and write the 'reverse' row, as before; the
--     trigger reacts at commit), cancel_invoice_recorded, reopen_invoice,
--     correct_invoice, invoice_action_plan, cancelled_invoice_used_value,
--     invoice_benefit_unused_elsewhere, invoice_credit_lot_ids, invoice_
--     benefits_holder, transfer_invoice_unused_benefit, create_invoice_with_
--     details, update_invoice_internal, cancel_invoice_rentals, 464's and
--     460's voucher functions (invoice_own_voucher_ids, apply_reopened_
--     invoice_vouchers), preview_invoice_correction: pinned, unchanged.
--   * The pages: the Reopen dialog shows fewer blockers (the server's own
--     list); the customer change's list and summary print the server's
--     reasons; no wording a page matches on changes. No page, Edge Function
--     or setting changes.
--   * Statements: the old holder's shows the credit returned and taken off
--     ("Credit returned", "Adjustment — decrease"), the new holder's "Credit
--     added", each with its reason.
--
-- NOT COVERED (for the Owner; the suite checks 1 to 6 as they are)
--
--   1. 463 (built after this, the Owner's decisions of 24 Oct 2026): a Move
--      to the same customer at another store stays with that customer after
--      a 'transfer' change (T1: A S$100; T1r: the reinstated S$40 follows,
--      the S$60 moved stays); a Premium Bundle's vouchers stay with the old
--      customer (V3, V4); the review summary of a change made while a
--      reopening waits lists no benefits (W1, 460's NOT COVERED 7); and the
--      optional guard: create_invoice_with_details takes a retired record
--      (K6s; the pages cannot pick one).
--   2. 445's NOT COVERED 1: merging a duplicate who spent wallet credit is
--      still refused ("Credit allocations cannot be changed once recorded",
--      S1m). Its own design.
--   3. 461's NOT COVERED 2: a lot an Owner moved still reads "Fully spent;
--      it stays with the original customer" in the change's list (no page
--      shows it).
--   4. A Correct payment that keeps a wallet method re-spends from the
--      payer's lots in the allocator's order. Where another of the payer's
--      lots comes first and holds credit then (it held none when the sale
--      was paid: a refund put some back on it since), that lot pays, and
--      what the correction put back on the package's lot follows to the
--      benefits' holder (decision 1). Not reached by the cases on a copy
--      (an older lot is used first when the sale is paid, too).
--   5. A sale paid from a package's credit with real spending left on it
--      still blocks a 'transfer' change as "Partly spent" (461's rule; L5);
--      with an Owner's Move of the rest the change passes and the spending,
--      once refunded, follows to the new customer (S4: decision 1).
--   6. customer_credit_statement lists a 'rental_late_fee' credit refund as
--      "Credit reversed" though it adds to the lot (dormant: no page calls
--      pay_special_with_credit, and no credit category allows a special
--      document today).
--   7. A deleted holder: deleting the benefits' holder alone is enough
--      once it holds a reissued lot (it is then also that lot's holder, and
--      after a 'transfer' change the invoice's customer). Credit given back
--      then goes to the customer it went back to, if not deleted (DH3: A
--      S$20, on a lot the records name). Where that customer is deleted too,
--      the refund (or the reopening's payment) is refused at commit, for the
--      Owner, rather than leaving credit on a lot no record names (P9). A
--      voucher a reopening gives again still goes to invoice_benefits_holder
--      (460's), deleted or not.
--   8. A summary or a Reopen dialog open on a screen when this goes in shows
--      the old answer until it is opened again; the server checks again.
--   9. A deadlock: where credit is forwarded (after a Move, a customer
--      change or a merge), a refund or a Correct payment of a sale paid from
--      the package's lot already holds that lot when this locks the
--      package's invoice at commit; a Cancel, a refund by line, a Move, a
--      customer change or a reopening's payment of that package committing
--      at the same moment takes the invoice first and then the lot. One of
--      the two is then stopped with "deadlock detected" and rolled back
--      whole (nothing of it is recorded); the app does not retry, so staff
--      do it again (checked with two sessions on a copy: the refund was the
--      one stopped). A refund that moves nothing locks nothing here, so the
--      plain case (no Move, change or merge) waits as before (checked).
--  10. Credit a refunded sale gives back while the package's invoice is
--      cancelled, refunded or asked to be, or its reopening waits, stays on
--      the lot it went back to, with that lot's holder (the reopening's own
--      records read the lots its cancellation took from, and refund_
--      invoice_recorded's 446 matching, pinned, reads the lot a row names).
--      Reopened and paid, the holder gets it (X2p: B S$40). But where that
--      lot is one a reissue replaced and the package stays cancelled, a
--      refund by line of the cancelled package does not reach it: K7b, S$80
--      of S$100 paid back, A keeps the S$20 as credit, on a lot no record
--      names (before 462 it was on the named lot and paid back; the suite
--      checks it as KNOWN). The legacy statuses cancellation_requested and
--      refund_requested (the app's v2 requests leave the invoice paid) are
--      treated as cancelled: credit given back meanwhile follows at the next
--      refund or correction that is forwarded.
--  11. The chain limit: merges (445) and customer changes (447) make the
--      chain longer without a check, so after twelve of them on one
--      package a refund of a sale paid before is refused (P8b), as is a
--      thirteenth reopening's payment with the benefits changed each time
--      (P8c); each needs the Owner (a data fix). 462 itself never makes a
--      chain longer than 12, and keeps it as it is for refunds the holder
--      did not spend between (CH1: fourteen refunds, one lot down).
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the texts are the tested ones (their AFTER md5s); each of the six is
--     its BEFORE (changed; each anchor found once; the text built has its
--     AFTER md5) or its AFTER (left alone), all six or none; the four added
--     are absent (added) or this version (left alone); the trigger and the
--     index are absent (added) or exactly these; no other function takes
--     the ten names; so a second run changes nothing;
--   * the functions it relies on are as read on production (pinned, below);
--     the columns read have these types; one benefit row per lot; the ledger
--     is append-only; who calls the six is as read; what writes a 'reverse'
--     ledger row and what raises a lot's balance are as read (a new way
--     would need the same forwarding), and the statement's list of credit
--     returned is as read;
--   * on the first run, nothing already in a state this reads differently
--     and that needs a decision first (each stops it, changing nothing, and
--     names the invoices; the read-only query below lists them):
--     (1) a credit Move without exactly its two ledger rows, naming the lots
--     its snapshots name, for what it moved; (2) credit on a lot of an
--     invoice's family that none of its records names, or a sale paid from
--     such a lot, still refundable, where the lot is behind no lot a benefit
--     row names (K9's merge, then the kept record spent the reissued lot to
--     S$0: its refund would give the credit back there); (3) a lot more than
--     12 reissues down its chain; (4) credit on a lot the records name held
--     by someone other than whoever holds the benefits now (460's NOT
--     COVERED 4 states, or a deleted record). Any repair is a separate data
--     fix, each with the Owner's yes;
--   * who may call the six is as read, compared as sets, and kept; the four
--     added are revoked from public, anon and signed-in staff and granted to
--     the service role;
--   * afterwards: the AFTER md5s, the grants, the trigger and the index as
--     tested; and the trace gives every moved lot the origin it gave before,
--     or, where it gave none (a moved lot partly taken back and then merged;
--     an older lot of a row moved on that a merge emptied), only the lot the
--     Move's own ledger rows lead back to: listed in a notice; anything else
--     stops it.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0462, so it leaves no row): a made-up Owner, store, package, S$20
--   session and eight customers (fictional ACMA phones no customer has).
--   (a) S$40 refunded, the rest moved to a friend, cancelled, reopened, the
--   benefits moved to a second customer while it waits, paid: the second
--   holds the S$40 on a lot replacing the buyer's that the benefit row and
--   the sale name, with its origin; the friend's S$60 traces to the package
--   (package_paid); nothing asked, due S$100. (b) The second merged into a
--   kept record: the kept record holds it with its records. (c) Then moved
--   to a third: not blocking; moved with its records. (d) A second package;
--   a S$20 session paid from it; the rest moved on; the benefits moved to
--   another customer; the session cancelled and refunded: the S$20 is on
--   the package's lot until the commit point, then on a new lot of the
--   benefits' holder the records name, nothing asked. (e) S$60 refunded,
--   the buyer merged, the rest moved on, cancelled: the preview allows the
--   reopening; paid, the kept record holds the S$60. (f) A third package; a
--   S$20 session paid from it; cancelled; S$40 of it refunded by line;
--   reopened; the benefits moved to a kept record; the session cancelled and
--   refunded while it waits: at the commit point the S$20 is still on the
--   package's lot, nothing forwarded; paid: the kept record holds S$100 on a
--   lot the benefit row names, nothing held back, nothing asked, due S$100.
--   Its credit ledger rows draw entry numbers (a sequence, 38 per run, which
--   an undone transaction does not give back: a gap, as 443 to 464's
--   self-tests). Locks: the
--   ledger table while the trigger and the index are added (SHARE: writes
--   wait, a few seconds at most), the ten functions' catalogue rows to the
--   end of the apply, and the rows the self-test writes and undoes. A
--   refund, payment, merge or customer change running at that moment
--   finishes on the text it started with.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (467 in: 732a3805, 1380 functions, head 20261024045047;
--   as read from main's commits, 24 Oct 2026) -> 462 -> 463 (built on 462's
--   AFTERs). 456 to 458, 464, 465 and 467 are in; 462 changes none of their
--   functions and pins those it relies on (below); 465 and 467 change only
--   TikTok functions, none of which 462 reads. If anything else goes in
--   first (466 is being built), work the fingerprints out again.
--   1. Before it, read only (invoice numbers and counts only; production
--      was not read for this file, so what it lists is not known yet): what
--      would
--      stop the install (1 to 4) and whose answer changes (5 to 9):
--     with recursive
--     named(invoice_id, id) as (
--       select b.invoice_id, b.lot_id from public.invoice_benefit_values b where b.lot_id is not null
--       union select s.invoice_id, x from public.credit_package_sales s, unnest(array[s.credit_lot_id, s.bonus_credit_lot_id]) x where x is not null
--       union select s.invoice_id, x from public.premium_bundle_sales s, unnest(array[s.paid_credit_lot_id, s.bonus_credit_lot_id]) x where x is not null
--       union select c.invoice_id, c.issued_lot_id from public.invoice_credit_splits c where c.issued_lot_id is not null
--       union select p.invoice_id, p.lot_id from public.credit_package_progress_lots p),
--     seed(invoice_id, id) as (
--       select invoice_id, id from named
--       union select t.invoice_id, e.lot_id from public.invoice_benefit_transfers t
--               join public.customer_credit_ledger e on e.source_record_id = t.id
--              where e.source_type in ('invoice_benefit_transfer_out', 'invoice_benefit_transfer_in')),
--     up(invoice_id, id, depth) as (
--       select invoice_id, id, 0 from seed
--       union select up.invoice_id, l.reassigned_from_lot_id, up.depth + 1 from up join public.customer_credit_lots l on l.id = up.id
--              where l.reassigned_from_lot_id is not null and up.depth < 30),
--     down(invoice_id, id, depth) as (
--       select invoice_id, id, 0 from up
--       union select down.invoice_id, l.id, down.depth + 1 from down join public.customer_credit_lots l on l.reassigned_from_lot_id = down.id
--              where down.depth < 30),
--     behind(invoice_id, id, depth) as (
--       select b.invoice_id, b.lot_id, 0 from public.invoice_benefit_values b where b.lot_id is not null
--       union select behind.invoice_id, p.id, behind.depth + 1 from behind join public.customer_credit_lots l on l.id = behind.id
--               join public.customer_credit_lots p on p.id = l.reassigned_from_lot_id
--                and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
--              where behind.depth < 12),
--     chain(start, id, depth) as (
--       select l.id, l.id, 0 from public.customer_credit_lots l where l.reassigned_from_lot_id is not null
--       union all
--       select chain.start, l.reassigned_from_lot_id, chain.depth + 1 from chain join public.customer_credit_lots l on l.id = chain.id
--        where l.reassigned_from_lot_id is not null and chain.depth < 13),
--     holder as (
--       select b.id as benefit_id, b.invoice_id, l.id as lot_id, l.customer_id, l.remaining_amount, l.status,
--              exists (select 1 from public.invoice_benefit_transfers t where t.replacement_benefit_id = b.id) as moved_in,
--              coalesce((select c.id from public.customers c where c.deleted_at is null and c.id = public.invoice_benefits_holder(b.invoice_id, l.customer_id,
--                          case when exists (select 1 from public.invoice_benefit_transfers t where t.replacement_benefit_id = b.id)
--                               then 'infinity'::timestamptz else l.created_at end)),
--                       (select c.id from public.invoices iv join public.customers c on c.id = iv.customer_id and c.deleted_at is null where iv.id = b.invoice_id),
--                       (select c.id from public.customers c where c.id = l.customer_id and c.deleted_at is null)) as live_holder
--         from public.invoice_benefit_values b join public.customer_credit_lots l on l.id = b.lot_id),
--     found(reason, invoice_id, n) as (
--       -- 462 refuses to install (each needs a decision first; a data fix):
--       select '1 refuses: an Owner''s Move of credit without exactly its two ledger rows', t.invoice_id, count(*)
--         from public.invoice_benefit_transfers t left join public.invoice_benefit_values rb on rb.id = t.replacement_benefit_id
--        where (rb.lot_id is not null or t.before_snapshot ? 'remaining_amount')
--          and not ((select count(*) from public.customer_credit_ledger e where e.source_type = 'invoice_benefit_transfer_out' and e.source_record_id = t.id) = 1
--               and (select count(*) from public.customer_credit_ledger e where e.source_type = 'invoice_benefit_transfer_in' and e.source_record_id = t.id) = 1
--               and exists (select 1 from public.customer_credit_ledger e where e.source_type = 'invoice_benefit_transfer_out' and e.source_record_id = t.id
--                            and e.lot_id::text = t.before_snapshot->>'id' and e.amount = t.transferred_value)
--               and exists (select 1 from public.customer_credit_ledger e where e.source_type = 'invoice_benefit_transfer_in' and e.source_record_id = t.id
--                            and e.lot_id::text = t.after_snapshot->>'id' and e.amount = t.transferred_value and rb.lot_id is not null))
--        group by t.invoice_id
--       union all
--       select '2 refuses: credit on a lot of the invoice none of its records names, or a sale paid from such a lot (behind no lot a benefit row names) that a refund would give back there', f.invoice_id, count(*)
--         from (select distinct invoice_id, id from down) f join public.customer_credit_lots l on l.id = f.id
--        where not exists (select 1 from named nm where nm.invoice_id = f.invoice_id and nm.id = f.id)
--          and (l.remaining_amount > 0
--               or not exists (select 1 from behind bh where bh.invoice_id = f.invoice_id and bh.id = f.id)
--                  and (exists (select 1 from public.invoice_line_credit_allocations a where a.lot_id = f.id and a.amount > coalesce(a.reversed_amount, 0))
--                       or exists (select 1 from public.special_credit_allocations s where s.lot_id = f.id and s.amount > coalesce(s.reversed_amount, 0))))
--        group by f.invoice_id
--       union all
--       select '3 refuses: a lot more than 12 reissues down its chain', f.invoice_id, count(distinct c.start)
--         from chain c join (select distinct invoice_id, id from down) f on f.id = c.start where c.depth >= 13 group by f.invoice_id
--       union all
--       select '4 refuses: credit on a lot the records name held by someone other than whoever holds the benefits now', h.invoice_id, count(*)
--         from holder h where h.remaining_amount > 0 and h.status = 'active' and h.customer_id is distinct from h.live_holder
--        group by h.invoice_id
--       union all
--       -- 462 changes the answer (no refusal):
--       select '5 changes: a moved lot held for review now traced to its origin (spendable)', t.invoice_id, count(*)
--         from public.customer_credit_lots l join public.invoice_benefit_transfers t on t.id = l.source_record_id
--        where l.source_type = 'invoice_benefit_transfer' and l.remaining_amount > 0 and public.invoice_credit_transfer_origin(l.id) is null
--        group by t.invoice_id
--       union all
--       select '6 changes: a reopening waiting on an invoice whose benefit an Owner moved (its payment gives back to the benefits'' holder on a new lot)', q.invoice_id, count(*)
--         from public.invoice_reopen_benefits q
--        where q.applied_at is null
--          and exists (select 1 from public.invoice_benefit_values b join public.invoice_benefit_transfers t on t.source_benefit_id = b.id where b.invoice_id = q.invoice_id)
--        group by q.invoice_id
--       union all
--       select '7 changes: a lot the records name held by someone other than the benefits'' holder, with sales paid from it that can still be refunded (their credit then goes to the holder)', h.invoice_id, count(*)
--         from holder h
--        where h.customer_id is distinct from h.live_holder
--          and (exists (select 1 from public.invoice_line_credit_allocations a where a.lot_id = h.lot_id and a.amount > coalesce(a.reversed_amount, 0))
--               or exists (select 1 from public.special_credit_allocations s where s.lot_id = h.lot_id and s.amount > coalesce(s.reversed_amount, 0)))
--        group by h.invoice_id
--       union all
--       select '8 changes: the customer-change list (a lot whose benefit an Owner moved now moves; a reissued lot with spending on an earlier lot now "Partly spent")', b.invoice_id, count(*)
--         from public.invoice_benefit_values b
--         join public.customer_credit_lots l on l.id = b.lot_id
--         join public.invoices iv on iv.id = b.invoice_id
--        where l.status = 'active' and l.remaining_amount > 0 and iv.deleted_at is null
--          and l.id in (select x.lot_id from public.invoice_credit_lot_ids(b.invoice_id) x)
--          and ((exists (select 1 from public.invoice_benefit_transfers t where t.source_benefit_id = b.id)
--                and l.remaining_amount < l.original_amount
--                and l.remaining_amount + b.cancelled_unused_value + public.invoice_benefit_unused_elsewhere(b.id) >= b.granted_value
--                and b.cancelled_unused_value = 0 and iv.status not in ('cancelled', 'refunded')
--                and not exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = iv.id and q.applied_at is null))
--            or (l.reassigned_from_lot_id is not null and l.remaining_amount = l.original_amount
--                and l.remaining_amount + b.cancelled_unused_value + public.invoice_benefit_unused_elsewhere(b.id) < b.granted_value))
--        group by b.invoice_id
--       union all
--       select '9 changes: a cancelled or refunded invoice whose benefit an Owner moved after a merge or a change reissued its lot (460 may refuse to reopen it; 462 does not)', b.invoice_id, count(*)
--         from public.invoice_benefit_values b
--         join public.customer_credit_lots l on l.id = b.lot_id
--         join public.invoices iv on iv.id = b.invoice_id
--        where iv.status in ('cancelled', 'refunded') and iv.deleted_at is null and l.reassigned_from_lot_id is not null
--          and exists (select 1 from public.invoice_benefit_transfers t where t.source_benefit_id = b.id)
--        group by b.invoice_id)
--     select f.reason, i.invoice_no, f.n
--       from found f join public.invoices i on i.id = f.invoice_id
--      order by f.reason, i.invoice_no
--      (The suite runs this same text on its cases' states before 462 and
--      checks what it lists.)
--   2. Dry run on a copy of production as it is then: work out its
--      fingerprint and grant list first (they must be the BEFORE figures
--      below, or be worked out again on that copy); apply this file twice;
--      the first run ends at the AFTER fingerprint below (worked out on a
--      copy at 467), the second changes nothing ("left alone" six times);
--      and the suite, with the earlier suites below.
--   3. Apply (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself.
--   Afterwards (checked on a copy, 24 Oct 2026) the re-runs of 445 (the
--   merge), 447 (the move), 460 (the merge, which it pins) and 461 (the
--   list's anchor) refuse on 462's changes, changing nothing; those of 446,
--   448, 451 and 456 to 458 refuse already today on other pins; 464's and
--   462's own leave all alone. All are applied, so nothing is lost. Their
--   suites check 462 where it is in: merge-credit-origin-445
--   (M0, M3, E1), customer-change-credit-447 (its fixture takes 462's change
--   out; E), reopen-follows-customer-460 (10; X10, K5, K6; 5, 6 and 8 (4)
--   the fixed way) and customer-change-refunded-461 (10; K12, K13 move);
--   function-grants lists the four helpers.
--
-- BEFORE (production, 24 Oct 2026, at 464, and the same at 467; md5 of
-- pg_get_functiondef with search_path public)
--   changed
--   invoice_credit_transfer_origin(uuid)                               e778a9e4ff81567a493b8ca479d8222b
--   apply_reopened_invoice_benefits()                                  3e659dafdbacb00ad953f99d00c3c6c9  (460's)
--   invoice_reopen_preview(uuid)                                       4b49c0c64eeb1b5962b605bbf56ea159  (460's)
--   merge_customer_records(uuid,uuid,text,uuid)                        2e0c9852099ab88d8f27827b5f9a3846  (445's)
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)             c1827889748d29f7a6626294333bd94f  (460's and 461's)
--   invoice_transferable_benefits(uuid)                                362d6d076c4751ab5dbe760f6d7a0d37  (460's and 461's)
--   credit_lot_ancestry(uuid), invoice_credit_live_holder(uuid,uuid,timestamp with time zone),
--   credit_given_back_follows(uuid), trg_credit_given_back_follows()   (not there)
--   relied on, not changed (pinned)
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)          804ecd829cfecf713783a09a05d93c7e
--   correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)          af99337094edb6d73b9cc0ae00fbf138
--   refund_special_credit(text,uuid)                                   e019e28ad79539d771376c9b38d7e27e
--   allocate_invoice_wallet_credit(uuid,numeric,text,text)             da8aa986c92d765a8028741f33bf56b0
--   cancel_invoice_recorded(uuid,text,uuid)                            de52d9dbaef8ab15163bef35cb9d733d
--   reopen_invoice(uuid,text,uuid)                                     0ff61e4ead121c198ea7f90a7fc78274
--   invoice_reopen_preview_before_sessions(uuid)                       12206ed066495024421b3b44a6a9d8e2
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                        04d647e13e9424a9375942e5812e91a2  (464's)
--   invoice_action_plan(uuid,text,jsonb)                               383d618edb28c3c9a360242d038a022c
--   cancelled_invoice_used_value(uuid)                                 055a3b07b1c15ffb1ac19039fa6cb650
--   invoice_benefit_unused_elsewhere(uuid)                             d35d7c8ae7187985ea64f8a5c38a7d79
--   invoice_credit_lot_ids(uuid)                                       50346a2e9aea50b31d4207c43b2f197c
--   invoice_benefits_holder(uuid,uuid,timestamp with time zone)        55995ff6e1ffd4a1172cb930512a34b0
--   transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)          7aebd7120bc3928db46df0941cb20889
--   preview_customer_merge(uuid,uuid)                                  f66c9d63369ef3b831ca74906a99b587
--   delete_customer(uuid,text,text)                                    5b407735574fc3cacd8067c4dc8213f4
--   credit_lot_policy_for(uuid)                                        ccdd506e78c7cdca97194fde87cdcc42
--   credit_lot_source_group(uuid)                                      6b902cb426210eb10ee9a15344ff100b
--   customer_credit_statement(uuid,date,date)                          1ba4a16a8208906f9e88efbc716bd1dd
--   reverse_credit_lot(uuid,text,text,text)                            10c1a3d8e3bb003fbaf01cf879f97c5e
--   repair_credit_package_progress_lots()                              ebd2a1a9f8ce7a9c1c272168b30b5ce3
--   apply_reopened_invoice_vouchers()                                  28d3b7a69b91ddebcdb200559d96a0ef  (460's, pinned by 464)
--   invoice_own_voucher_ids(uuid)                                      9340840f1ce4e031ec3613198688ba2e  (460's, pinned by 464)
--   ensure_customer_wallet(uuid)                                       8ef18daebbbe3c12f2024290ea8416e8
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   trg_credit_lot_immutable()                                         0fc74da0dcc9b436dfd26c4582542f6c
--   trg_credit_ledger_immutable()                                      071ec0ccd5fc13107de0d11f85ba8c28
--   public function fingerprint, production now (467 in)               732a3805a2fafa035c5a46068026c81f (1380 functions; at 464: 432fcb99, 1379)
--   grant list (string_agg(signature '=' proacl, '|'), a copy at 467)  79145051f64bd117bb4a7ab2fb9eb573 (at 464: 6f3be95e; production lists
--                                                                      the same grants in another order: compare as sets)
-- AFTER (for later guards)
--   invoice_credit_transfer_origin(uuid)                               1e8beeccfbf7e432edffc1598acddb53
--   apply_reopened_invoice_benefits()                                  4efef2f1e97bed6a3f0eed0df4e2df51
--   invoice_reopen_preview(uuid)                                       e09ebf9c0841ef5463f96b26f4933541  (grants kept: signed-in staff, service role)
--   merge_customer_records(uuid,uuid,text,uuid)                        ba05c2b1fb4c0e14d369c01d06a635b0
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)             130c25c6ce3d91b7b421e6f4c3d02353
--     outside 461's part (the lots' selection; 460's suite)            225376878d90f952966d524255f5ade6
--   invoice_transferable_benefits(uuid)                                d0d19b7c765337c3cd68096fdc6de7dd
--     outside the credit rows (460's suite; unchanged)                 e5df1d68f73847f5d9faa7b04bfd81fe
--   credit_lot_ancestry(uuid)                                          52b3cae789b6b52a12bb2f798af40cbe  (new; service role alone)
--   invoice_credit_live_holder(uuid,uuid,timestamp with time zone)     a5692590ef3e8a7a7dd7e8ff7cfa9568  (new; service role alone)
--   credit_given_back_follows(uuid)                                    9d75978de5b247a8de1aaee4e894a698  (new; service role alone)
--   trg_credit_given_back_follows()                                    84e2d978b74b56a9508e4f4f5b518c22  (new; service role alone)
--   trigger credit_given_back_follows on customer_credit_ledger (constraint, DEFERRABLE INITIALLY DEFERRED, for each row)
--   index customer_credit_ledger_transfer_lots_idx (source_record_id, the two Move source types)
--   public function fingerprint, worked out on copies (24 Oct 2026; a second run the same):
--     production now (467 in) -> 462                                   43aeae86af2c9a9c824182284fbdbbdd (1384 functions: four new, none dropped)
--     464 (the suites' copy) -> 462                                    055ad62ecb57d228932cb70900dcc077 (1383)
--   grant list on the copy at 467 after 462                            95be5abc774a6fb5d9e998614c6eb5b5 (at 464 after 462: 6e250747; compare as sets)
--
-- Test: scripts/invoices/tests/move-merge-leftovers-462.sql (begin ...
-- rollback; it installs this file twice; -v nomig=1 where it is in). It
-- reproduces each case first, then checks the refusals, the header's query,
-- the install, every case after 462 with the invariants (the invoice's lot
-- family, ledger balances, chain depth, the trace, the holder, sales paid
-- from a lot no record names, what a cancellation holds back, a refunded
-- invoice's credit) and Cancel, the controls unchanged, cases begun before
-- 462 and finished after, the forwarder at commit (separate refunds, the
-- chain limit, nothing while cancelled or waiting, every record deleted),
-- and NOT COVERED 1 to 3 and 10 as KNOWN. Each app call is
-- followed by what its commit does (the trigger is deferred). The same
-- cases were also run one app call per real transaction on a copy (real
-- commits and timestamps), with the same outcomes. Fixtures only (the
-- repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The six functions this changes: BEFORE (production, 24 Oct 2026, at
  -- 464: 432fcb99, 1379 functions) and AFTER md5s; who may call each, as
  -- read (kept). 1 to 3 are replaced whole (their texts below); 4 to 6 are
  -- patched at anchors (below) ═══════════════════════════════════════════════
  c_sigs constant text[] := array[
    'invoice_credit_transfer_origin(uuid)',
    'apply_reopened_invoice_benefits()',
    'invoice_reopen_preview(uuid)',
    'merge_customer_records(uuid,uuid,text,uuid)',
    'move_invoice_benefits_to_customer(uuid,uuid,uuid,text)',
    'invoice_transferable_benefits(uuid)'];
  c_before constant text[] := array[
    'e778a9e4ff81567a493b8ca479d8222b',
    '3e659dafdbacb00ad953f99d00c3c6c9',
    '4b49c0c64eeb1b5962b605bbf56ea159',
    '2e0c9852099ab88d8f27827b5f9a3846',
    'c1827889748d29f7a6626294333bd94f',
    '362d6d076c4751ab5dbe760f6d7a0d37'];
  c_after constant text[] := array[
    '1e8beeccfbf7e432edffc1598acddb53',
    '4efef2f1e97bed6a3f0eed0df4e2df51',
    'e09ebf9c0841ef5463f96b26f4933541',
    'ba05c2b1fb4c0e14d369c01d06a635b0',
    '130c25c6ce3d91b7b421e6f4c3d02353',
    'd0d19b7c765337c3cd68096fdc6de7dd'];
  c_acl constant text[] := array[
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'];
  -- ══ The four functions this adds (the server's alone) ════════════════════
  c_new constant text[] := array[
    'credit_lot_ancestry(uuid)',
    'invoice_credit_live_holder(uuid,uuid,timestamp with time zone)',
    'credit_given_back_follows(uuid)',
    'trg_credit_given_back_follows()'];
  c_new_after constant text[] := array[
    '52b3cae789b6b52a12bb2f798af40cbe',
    'a5692590ef3e8a7a7dd7e8ff7cfa9568',
    '9d75978de5b247a8de1aaee4e894a698',
    '84e2d978b74b56a9508e4f4f5b518c22'];
  c_new_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';

  -- ══ The whole texts (each exactly as the database prints it back) ═══════
  c_def_ancestry constant text := $d1$CREATE OR REPLACE FUNCTION public.credit_lot_ancestry(p_lot_id uuid)
 RETURNS uuid[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 462 (the Owner, 24 Oct 2026): a lot and the lots it was reissued from,
-- newest first: what reassigned_from_lot_id names, back along the chain (a
-- merge, 445; a customer change, 447 and 461; a reopening's give-back, 460;
-- credit given back after a reissue, 462), each of which carries the source
-- of the lot it replaces. A link to a lot of another source is not a
-- reissue (a Move before 445 copied its source lot's link) and ends the
-- chain. At most 12 steps back, as every reader of the chain walks it
-- (invoice_credit_lot_ids, credit_lot_chain, invoice_benefit_unused_elsewhere).
-- Empty when there is no such lot.
declare v_chain uuid[]; c public.customer_credit_lots%rowtype; p public.customer_credit_lots%rowtype;
begin
  select * into c from public.customer_credit_lots where id = p_lot_id;
  if not found then return '{}'::uuid[]; end if;
  v_chain := array[c.id];
  loop
    exit when c.reassigned_from_lot_id is null or c.reassigned_from_lot_id = any (v_chain) or cardinality(v_chain) > 12;
    select * into p from public.customer_credit_lots where id = c.reassigned_from_lot_id;
    exit when not found or (p.source_type, p.source_record_id) is distinct from (c.source_type, c.source_record_id);
    v_chain := v_chain || p.id;
    c := p;
  end loop;
  return v_chain;
end $function$
$d1$;
  c_def_holder constant text := $d2$CREATE OR REPLACE FUNCTION public.invoice_credit_live_holder(p_invoice_id uuid, p_customer_id uuid, p_since timestamp with time zone)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 462 (the Owner, 24 Oct 2026): whom credit an invoice's benefits get back
  -- goes to: whoever holds the benefits now (invoice_benefits_holder, 460:
  -- the customer the latest customer change that took them along moved them
  -- to, then the record a merge kept), as long as that record is not
  -- deleted. A customer deleted without a merge (delete_customer: it refuses
  -- only while the customer holds credit, so a holder with nothing left can
  -- be deleted) never gets credit: then the invoice's customer, if not
  -- deleted, or else p_customer_id (the lot's holder), if not deleted.
  -- Null when all three are deleted (the credit then stays where it is).
  select coalesce(
           (select c.id from public.customers c where c.id = h.id and c.deleted_at is null),
           (select c.id from public.invoices i join public.customers c on c.id = i.customer_id
             where i.id = p_invoice_id and c.deleted_at is null),
           (select c.id from public.customers c where c.id = p_customer_id and c.deleted_at is null))
    from (select public.invoice_benefits_holder(p_invoice_id, p_customer_id, p_since) as id) h
$function$
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
-- lot is one this made and nothing has touched since (its grant its only
-- ledger row), the new lot takes its place instead (reassigned_from_lot_id
-- naming the lot it replaced), so separate refunds do not make the chain
-- longer; a chain is never made longer than 12 lots (the readers' limit):
-- that is refused, for the Owner. Nothing is done where the named lot alone
-- holds it and its holder is the benefits' holder (as before), nor for a lot
-- no invoice's benefit row names or replaced (wallet credit of other kinds),
-- nor while that invoice is cancelled, refunded or asked to be, or a
-- reopening of it waits to be settled: the reopening's own records read the
-- lots its cancellation took from, so the credit stays where it went back,
-- and the payment that settles the reopening gives it to the benefits'
-- holder (apply_reopened_invoice_benefits). The holder:
-- invoice_credit_live_holder (460's rule; a Move's recipient keeps what was
-- moved, following merges alone; never a deleted record), else the holder of
-- the lot the credit went back on, if not deleted; with none, the credit
-- stays only where it is on the named lot, and otherwise this is refused.
-- Whether anything needs doing is read first without locks (a refund that
-- moves nothing takes no lock here); only then are the invoice, its benefit
-- row and the lots locked, in the order Cancel and Reopen take them, and
-- everything read again.
declare v_try int:=0; v_k int; v_cur uuid; v_prev uuid; v_inv uuid; v_locked boolean:=false; v_status text;
 b public.invoice_benefit_values%rowtype; n public.customer_credit_lots%rowtype; x record;
 v_chain uuid[]; v_h uuid; v_more boolean; v_total numeric:=0; v_new uuid; v_wallet uuid; v_cap numeric;
 v_from jsonb:='[]'::jsonb; v_parent uuid; v_up uuid; v_depth int; v_replace boolean;
 c_reason constant text:='Credit given back goes to whoever holds the invoice''s benefits now';
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
  if v_cur is null then return; end if;
  if v_k>12 then
   raise exception 'Credit given back on lot % is more than 12 lots down from the lot invoice % names for it, further than the app follows. Nothing was recorded; ask the Owner.',
    p_lot_id,(select invoice_no from public.invoices where id=v_inv);
  end if;
  -- Not while the invoice is cancelled, refunded or asked to be, or a
  -- reopening of it waits to be settled.
  select i.status::text into v_status from public.invoices i where i.id=v_inv;
  if v_status in ('cancelled','refunded','cancellation_requested','refund_requested')
     or exists(select 1 from public.invoice_reopen_benefits q where q.invoice_id=v_inv and q.applied_at is null) then
   return;
  end if;
  select * into b from public.invoice_benefit_values where lot_id=v_cur and invoice_id=v_inv;
  if not found then continue; end if;
  select * into n from public.customer_credit_lots where id=v_cur;
  if n.status<>'active' or n.is_locked then return; end if;
  v_chain:=public.credit_lot_ancestry(n.id);
  if not (p_lot_id=any(v_chain)) then
   raise exception 'Credit given back on lot % is more than 12 lots down from the lot invoice % names for it, further than the app follows. Nothing was recorded; ask the Owner.',
    p_lot_id,(select invoice_no from public.invoices where id=v_inv);
  end if;
  v_h:=coalesce(public.invoice_credit_live_holder(b.invoice_id,n.customer_id,
                  case when exists(select 1 from public.invoice_benefit_transfers t where t.replacement_benefit_id=b.id)
                       then 'infinity'::timestamptz else n.created_at end),
                (select c.id from public.customer_credit_lots pl join public.customers c on c.id=pl.customer_id
                  where pl.id=p_lot_id and c.deleted_at is null));
  v_more:=exists(select 1 from public.customer_credit_lots l
                  where l.id=any(v_chain) and l.id<>n.id and l.remaining_amount>0 and l.status='active' and not l.is_locked);
  if not v_more and (n.remaining_amount<=0 or n.customer_id=v_h or v_h is null) then return; end if;
  if v_h is null then
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
 if exists(select 1 from public.customer_credit_lots l
            where l.id=any(v_chain) and l.remaining_amount>0 and l.status='active' and not l.is_locked and l.category is distinct from n.category) then
  raise exception 'Credit given back on lot % is not of the category of the lot invoice % names for it. Nothing was recorded; ask the Owner.',
   p_lot_id,(select invoice_no from public.invoices where id=b.invoice_id);
 end if;
 -- The new lot replaces the named lot, or takes its place where this made it
 -- and nothing has touched it since (so the chain does not grow).
 v_replace:=n.reassigned_from_lot_id is not null and n.remaining_amount=n.original_amount
   and (select count(*) from public.customer_credit_ledger e where e.lot_id=n.id)=1
   and exists(select 1 from public.customer_credit_ledger e
               where e.lot_id=n.id and e.entry_type='grant' and e.source_type='credit_given_back_reassignment_in')
   and not exists(select 1 from public.customer_credit_lots c where c.reassigned_from_lot_id=n.id);
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
           where l.id=any(v_chain) and l.remaining_amount>0 and l.status='active' and not l.is_locked
           order by l.created_at,l.id loop
  update public.customer_credit_lots set remaining_amount=0,updated_at=now() where id=x.id;
  insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
   values(x.wallet_id,x.customer_id,'adjust_decrease',x.category,x.remaining_amount,x.id,'credit_given_back_reassignment_out',b.invoice_id,x.store_id,c_reason,auth.uid(),auth.uid());
  v_total:=v_total+x.remaining_amount;
  v_from:=v_from||jsonb_build_object('lot_id',x.id,'customer_id',x.customer_id,'amount',x.remaining_amount);
 end loop;
 if v_total<=0 then return; end if;
 -- A Move's credit never comes to more than was moved (its trace needs it).
 if n.source_type='invoice_benefit_transfer' then
  select g.original_amount into v_cap
    from public.customer_credit_ledger e join public.customer_credit_lots g on g.id=e.lot_id
   where e.source_type='invoice_benefit_transfer_in' and e.source_record_id=n.source_record_id
   order by e.entry_seq limit 1;
  if v_cap is not null and v_total>v_cap then
   raise exception 'Credit given back on lot % would come to S$% of credit an Owner moved, more than the S$% moved. Nothing was recorded; ask the Owner.',
    p_lot_id,to_char(v_total,'FM999999990.00'),to_char(v_cap,'FM999999990.00');
  end if;
 end if;
 insert into public.customer_credit_lots
 select (jsonb_populate_record(null::public.customer_credit_lots,to_jsonb(n)||jsonb_build_object(
   'id',v_new,'wallet_id',v_wallet,'customer_id',v_h,
   'original_amount',v_total,'remaining_amount',v_total,'status','active','is_locked',false,
   'reassigned_from_lot_id',v_parent,'reference_no',null,'reason',c_reason,'reversal_of_lot_id',null,
   'created_by',auth.uid(),'approved_by',auth.uid(),'created_at',clock_timestamp(),'updated_at',clock_timestamp()))).*;
 insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
  values(v_wallet,v_h,'grant',n.category,v_total,v_new,'credit_given_back_reassignment_in',b.invoice_id,n.store_id,c_reason,auth.uid(),auth.uid());
 update public.invoice_benefit_values set lot_id=v_new where lot_id=n.id;
 update public.credit_package_sales set credit_lot_id=v_new where credit_lot_id=n.id;
 update public.credit_package_sales set bonus_credit_lot_id=v_new where bonus_credit_lot_id=n.id;
 update public.premium_bundle_sales set paid_credit_lot_id=v_new where paid_credit_lot_id=n.id;
 update public.premium_bundle_sales set bonus_credit_lot_id=v_new where bonus_credit_lot_id=n.id;
 update public.invoice_credit_splits set issued_lot_id=v_new where issued_lot_id=n.id;
 perform public.write_audit_ex('invoices',b.invoice_id,'credit_given_back_followed',null,
   jsonb_build_object('lot_id',v_new,'to_customer',v_h,'amount',v_total,'from',v_from,'benefit_id',b.id,
     'replaces_lot_id',n.id,'in_place_of_lot_id',case when v_replace then n.id end),
   'invoices',c_reason,(select store_id from public.invoices where id=b.invoice_id));
end $function$
$d3$;
  c_def_trg constant text := $d4$CREATE OR REPLACE FUNCTION public.trg_credit_given_back_follows()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- 462 (the Owner, 24 Oct 2026): credit given back on a lot follows the
  -- invoice's benefits it came from (credit_given_back_follows). The
  -- trigger credit_given_back_follows runs this at commit, once per ledger
  -- row giving back credit a refunded or corrected sale was paid with,
  -- after anything else the transaction did.
  perform public.credit_given_back_follows(new.lot_id);
  return null;
end $function$
$d4$;
  c_def_trace constant text := $d5$CREATE OR REPLACE FUNCTION public.invoice_credit_transfer_origin(p_lot_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 462 (the Owner, 24 Oct 2026: credit and vouchers follow a merge and a
-- customer change that takes the benefits along, and a Move's recipient
-- keeps what was moved): the lot credit an Owner moved (Move, 186) comes
-- from, traced through the two lots the Move itself recorded in the
-- append-only ledger: the lot it drew from ('invoice_benefit_transfer_out')
-- and the lot it granted ('invoice_benefit_transfer_in'). The lot asked about
-- is the lot granted, or one a merge, a customer change, a reopening's
-- give-back or credit given back reissued from it (reassigned_from_lot_id),
-- on the chain of the lot the Move's replacement row names now; the lot
-- drawn from is on the chain of the lot its source row names now. Amounts
-- are compared on those two lots, which never change: the lot granted holds
-- what was moved (transferred_value) at the transfer's store, which the lot
-- drawn from held at least; the lot asked about never holds more than was
-- granted, at the same store, with the same category and restrictions as
-- the lot drawn from. Before, the trace needed the source row to keep naming
-- the lot drawn from and the lot asked about to be the one granted, so a
-- merge, a customer change and a reopening left such rows on emptied lots,
-- and a moved lot partly taken back and then merged lost its origin (445's
-- NOT COVERED). A Move recorded without those two ledger rows (every Move
-- writes both since 186; 462 refuses to install while one has not) is
-- traced by the old rule.
declare current_id uuid:=p_lot_id; visited uuid[]:='{}';
 child public.customer_credit_lots%rowtype; parent public.customer_credit_lots%rowtype;
 granted public.customer_credit_lots%rowtype; drawn public.customer_credit_lots%rowtype;
 transfer public.invoice_benefit_transfers%rowtype;
 source_benefit public.invoice_benefit_values%rowtype; replacement_benefit public.invoice_benefit_values%rowtype;
 v_out uuid[]; v_in uuid[];
begin
 loop
  if current_id is null or current_id=any(visited) then return null; end if;
  visited:=array_append(visited,current_id);
  select * into child from public.customer_credit_lots where id=current_id;
  if not found then return null; end if;
  if child.source_type<>'invoice_benefit_transfer' then return child.id; end if;
  select * into transfer from public.invoice_benefit_transfers where id=child.source_record_id;
  if not found then return null; end if;
  select * into replacement_benefit from public.invoice_benefit_values where id=transfer.replacement_benefit_id;
  if not found or replacement_benefit.invoice_id is distinct from transfer.invoice_id then return null; end if;
  select * into source_benefit from public.invoice_benefit_values where id=transfer.source_benefit_id;
  if not found or source_benefit.lot_id is null
   or source_benefit.invoice_id is distinct from transfer.invoice_id
   or source_benefit.invoice_item_id is distinct from replacement_benefit.invoice_item_id then return null; end if;
  select array_agg(e.lot_id) filter (where e.source_type='invoice_benefit_transfer_out'),
         array_agg(e.lot_id) filter (where e.source_type='invoice_benefit_transfer_in')
    into v_out,v_in
    from public.customer_credit_ledger e
   where e.source_record_id=transfer.id
     and e.source_type in ('invoice_benefit_transfer_out','invoice_benefit_transfer_in');
  if coalesce(cardinality(v_out),0)=1 and coalesce(cardinality(v_in),0)=1 then
   select * into granted from public.customer_credit_lots where id=v_in[1];
   if not found then return null; end if;
   select * into drawn from public.customer_credit_lots where id=v_out[1];
   if not found then return null; end if;
   if granted.source_type<>'invoice_benefit_transfer'
    or granted.source_record_id is distinct from transfer.id
    or granted.original_amount is distinct from transfer.transferred_value
    or granted.store_id is distinct from transfer.store_id
    or not (granted.id=any(public.credit_lot_ancestry(child.id)))
    or not (child.id=any(public.credit_lot_ancestry(replacement_benefit.lot_id)))
    or child.original_amount>granted.original_amount
    or child.store_id is distinct from transfer.store_id
    or not (drawn.id=any(public.credit_lot_ancestry(source_benefit.lot_id)))
    or transfer.transferred_value>drawn.original_amount
    or drawn.category is distinct from child.category
    or drawn.usage_restrictions is distinct from child.usage_restrictions then return null; end if;
   current_id:=drawn.id;
  else
   -- The old rule (before the Move wrote both ledger rows).
   if replacement_benefit.lot_id is distinct from child.id
    or child.customer_id is distinct from transfer.customer_id
    or child.store_id is distinct from transfer.store_id
    or child.original_amount is distinct from transfer.transferred_value then return null; end if;
   select * into parent from public.customer_credit_lots where id=source_benefit.lot_id;
   if not found or parent.category is distinct from child.category
    or parent.usage_restrictions is distinct from child.usage_restrictions
    or child.original_amount>parent.original_amount then return null; end if;
   current_id:=parent.id;
  end if;
 end loop;
end $function$
$d5$;
  c_def_apply constant text := $d6$CREATE OR REPLACE FUNCTION public.apply_reopened_invoice_benefits()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; l public.customer_credit_lots%rowtype;
 -- 460
 v460_put jsonb:='{}'::jsonb; g record; t public.customer_credit_lots%rowtype; x record;
 v460_h uuid; v460_total numeric; v460_new uuid; v460_wallet uuid;
 -- 462
 v462_chain uuid[]; v462_more boolean; v462_up uuid; v462_depth int;
 v460_reason constant text:='Reopened invoice settled; the credit it gives back goes to whoever holds its benefits now';
begin
 if new.status not in ('paid','completed_foc') then return new; end if;
 for r in select b.*,e.lot_id from public.invoice_reopen_benefits b join public.customer_credit_ledger e on e.id=b.source_ledger_id
   where b.invoice_id=new.id and b.applied_at is null order by b.id for update of b loop
   select * into l from public.customer_credit_lots where id=r.lot_id for update;
   update public.customer_credit_lots set remaining_amount=remaining_amount+r.amount,status='active',updated_at=now() where id=l.id;
   insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,reverses_entry_id,created_by,approved_by)
    values(l.wallet_id,l.customer_id,'reverse',l.category,r.amount,l.id,'invoice_reopen',r.request_id,l.store_id,'Reopened invoice settled',r.source_ledger_id,auth.uid(),auth.uid());
   update public.invoice_reopen_benefits set applied_at=now() where id=r.id;
   -- 462: what the cancellation took back, and this gives back, comes off
   -- the benefit row it was taken for: the row naming this lot, or a lot
   -- reissued from it (a merge or a customer change while the reopening
   -- waited reissues the lot and the records follow; before, the row was
   -- matched by this lot alone, so its reserve stayed and a later refund,
   -- Move or change read it as still held back).
   update public.invoice_benefit_values set cancelled_unused_value=greatest(0,cancelled_unused_value-r.amount)
    where id=(select b2.id from public.invoice_benefit_values b2
               where b2.invoice_id=new.id and b2.lot_id is not null
                 and l.id=any(public.credit_lot_ancestry(b2.lot_id))
               order by (b2.lot_id=l.id) desc,b2.created_at,b2.id limit 1);
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
 -- its holder is the benefits', nothing more happens, as before.
 -- 462 (the Owner, 24 Oct 2026): also where the named lot's benefit row was
 -- moved on by an Owner (Move): the Move's credit is traced through the
 -- Move's own ledger rows now (invoice_credit_transfer_origin), not through
 -- that row's lot, so its records follow like any other's. 460's way for
 -- such a row (the credit added onto the named lot, or the payment refused
 -- where it did not fit, with whoever held that lot) is gone. And the holder
 -- is never a deleted record (invoice_credit_live_holder: the invoice's
 -- customer then, else the holder of the lot it went back on, if not
 -- deleted). Everything the named lot and the lots it replaced hold goes
 -- along (credit given back on a lot it replaced while the invoice was
 -- cancelled, or while this reopening waited, stayed there for this
 -- payment: credit_given_back_follows), and the chain is never made longer
 -- than 12 lots (refused, for the Owner); with no live record to give it
 -- to, credit on a lot the records do not name is refused, for the Owner.
 for g in
  select s.target,jsonb_object_agg(s.lot_id::text,s.amount) as lots
    from (select p.key::uuid as lot_id,p.value::numeric as amount,
                 coalesce((select b.lot_id from public.invoice_benefit_values b
                            where b.invoice_id=new.id and b.lot_id is not null
                              and p.key::uuid=any(public.credit_lot_ancestry(b.lot_id))
                            order by (b.lot_id=p.key::uuid) desc,b.created_at,b.id limit 1),p.key::uuid) as target
            from jsonb_each_text(v460_put) p) s
   group by s.target order by s.target
 loop
  v462_chain:=public.credit_lot_ancestry(g.target);
  perform 1 from public.customer_credit_lots where id=any(v462_chain) order by created_at,id for update;
  select * into t from public.customer_credit_lots where id=g.target for update;
  v460_h:=coalesce(public.invoice_credit_live_holder(new.id,t.customer_id,
            case when exists(select 1 from public.invoice_benefit_values b
                               join public.invoice_benefit_transfers bt on bt.replacement_benefit_id=b.id
                              where b.invoice_id=new.id and b.lot_id=t.id) then 'infinity'::timestamptz
                 else t.created_at end),
            (select c.id from public.customer_credit_lots pl join public.customers c on c.id=pl.customer_id
              where pl.id in (select k::uuid from jsonb_object_keys(g.lots) k) and c.deleted_at is null
              order by pl.created_at,pl.id limit 1));
  v462_more:=exists(select 1 from public.customer_credit_lots cl
                     where cl.id<>t.id and cl.remaining_amount>0
                       and (cl.id in (select k::uuid from jsonb_object_keys(g.lots) k)
                            or cl.id=any(v462_chain) and cl.status='active' and not cl.is_locked));
  if v460_h is null and v462_more then
   raise exception 'Reopened invoice %: the credit it gives back belongs with its benefits, but whoever holds them, the invoice''s customer and the customer it went back to are all deleted. Nothing was recorded; ask the Owner.',
    new.invoice_no;
  end if;
  continue when v460_h is null or v460_h=t.customer_id and not v462_more;
  v462_depth:=0; v462_up:=t.id;
  loop
   select cl.reassigned_from_lot_id into v462_up from public.customer_credit_lots cl where cl.id=v462_up;
   exit when v462_up is null or v462_depth>=12;
   v462_depth:=v462_depth+1;
  end loop;
  if v462_depth>=12 then
   raise exception 'Reopened invoice %: giving back its credit would make its chain of lots longer than 12, further than the app follows. Nothing was recorded; ask the Owner.',
    new.invoice_no;
  end if;
  v460_new:=gen_random_uuid(); v460_wallet:=public.ensure_customer_wallet(v460_h); v460_total:=0;
  for x in select cl.*,cl.remaining_amount as amt
             from public.customer_credit_lots cl
            where cl.id=t.id or cl.id in (select k::uuid from jsonb_object_keys(g.lots) k)
               or cl.id=any(v462_chain) and cl.status='active' and not cl.is_locked
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
$d6$;
  c_def_preview constant text := $d7$CREATE OR REPLACE FUNCTION public.invoice_reopen_preview(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb; begin
 result:=public.invoice_reopen_preview_before_sessions(p_invoice_id);
 -- 462 (the Owner, 24 Oct 2026): 460's refusal is gone (credit refunded
 -- before a merge or a customer change reissued its lot, the rest then moved
 -- to someone else by a Move, where it would not fit back on the lot the
 -- invoice names). The payment that settles the reopened invoice now gives
 -- such credit to whoever holds the invoice's benefits, on a new lot the
 -- invoice's records name (apply_reopened_invoice_benefits), as for any
 -- other benefit row, so it always fits; and credit a refund of a sale paid
 -- from that lot gives back later follows the same way
 -- (credit_given_back_follows).
 return result||jsonb_build_object('sessions_to_reinstate_after_settlement',(select coalesce(sum(quantity_refunded+quantity_cancelled),0)
  from public.customer_therapy_sessions where invoice_id=p_invoice_id and is_current));
end $function$
$d7$;

  -- ══ The anchors (each found once in its function's BEFORE text), the
  -- function each is in (an index into c_sigs) and its patch, in order ═════
  c_fn constant int[] := array[4, 5, 5, 6];
  c_anchor constant text[] := array[
$a1$    if not exists (select 1 from public.invoice_benefit_values b
                     join public.invoice_benefit_transfers t on t.source_benefit_id = b.id
                    where b.lot_id = r_lot.id) then
      update public.invoice_benefit_values set lot_id = v_new_lot where lot_id = r_lot.id;
      update public.credit_package_sales set credit_lot_id = v_new_lot where credit_lot_id = r_lot.id;
      update public.credit_package_sales set bonus_credit_lot_id = v_new_lot where bonus_credit_lot_id = r_lot.id;
      update public.premium_bundle_sales set paid_credit_lot_id = v_new_lot where paid_credit_lot_id = r_lot.id;
      update public.premium_bundle_sales set bonus_credit_lot_id = v_new_lot where bonus_credit_lot_id = r_lot.id;
      update public.invoice_credit_splits set issued_lot_id = v_new_lot where issued_lot_id = r_lot.id;
    end if;
$a1$,
$a2$       -- 461 (the Owner, 22 Oct 2026): or nothing on it was spent. Credit a
       -- line refund paid back is not spent (448's test, made here as the
       -- list makes it, invoice_transferable_benefits), so what the lot
       -- still holds moves, as an untouched lot's credit does, keeping its
       -- origin (447), when nothing else holds a claim on it: no
       -- cancellation still holds credit back for it, no reopening waits to
       -- give credit back, no Owner moved its benefit (its records stay
       -- here, below), the invoice neither cancelled nor refunded. Tested on
       -- the lot's own figures, which are read again once it is locked, so
       -- credit spent meanwhile keeps it here.
       and (l.remaining_amount = l.original_amount
            or exists (select 1 from public.invoice_benefit_values b
                        where b.lot_id = l.id and b.invoice_id = p_invoice_id
                          and l.remaining_amount + b.cancelled_unused_value
                              + public.invoice_benefit_unused_elsewhere(b.id) >= b.granted_value
                          and b.cancelled_unused_value = 0
                          and not exists (select 1 from public.invoice_benefit_transfers t where t.source_benefit_id = b.id))
               and not exists (select 1 from public.invoice_reopen_benefits q
                                where q.invoice_id = p_invoice_id and q.applied_at is null)
               and not exists (select 1 from public.invoices iv
                                where iv.id = p_invoice_id and iv.status in ('cancelled', 'refunded')))
       and l.remaining_amount > 0
       and l.status = 'active'
$a2$,
$a3$    if not exists (select 1 from public.invoice_benefit_values b
                     join public.invoice_benefit_transfers t on t.source_benefit_id = b.id
                    where b.lot_id = r_lot.id) then
      update public.invoice_benefit_values set lot_id = v_new_lot where lot_id = r_lot.id;
      update public.credit_package_sales set credit_lot_id = v_new_lot where credit_lot_id = r_lot.id;
      update public.credit_package_sales set bonus_credit_lot_id = v_new_lot where bonus_credit_lot_id = r_lot.id;
      update public.premium_bundle_sales set paid_credit_lot_id = v_new_lot where paid_credit_lot_id = r_lot.id;
      update public.premium_bundle_sales set bonus_credit_lot_id = v_new_lot where bonus_credit_lot_id = r_lot.id;
      update public.invoice_credit_splits set issued_lot_id = v_new_lot where issued_lot_id = r_lot.id;
    end if;
$a3$,
$a4$  -- 461 (the Owner, 22 Oct 2026: "fix the other two rare gaps too"; 448's
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
  -- either back on the lot it was taken from), no Owner moved its benefit
  -- (Move: its records then stay on this lot, 447), and the invoice is
  -- neither cancelled nor refunded. Otherwise, and for a lot with real
  -- spending or with no benefit row of this invoice (older invoices, credit
  -- released before settlement), it reads as before: "Partly spent",
  -- blocking.
  select 'credit', l.id,
         initcap(l.category) || ' credit ' || l.remaining_amount::text,
         l.remaining_amount,
         l.status = 'active' and l.remaining_amount > 0
           and (l.remaining_amount = l.original_amount or coalesce(u.moves, false)),
         l.remaining_amount > 0 and l.remaining_amount < l.original_amount and not coalesce(u.moves, false),
         case when l.remaining_amount = 0 and u.unspent and u.refunded then 'Refunded; nothing is left to move'
              when l.remaining_amount = 0 then 'Fully spent; it stays with the original customer'
              when l.remaining_amount < l.original_amount and not coalesce(u.moves, false) then 'Partly spent'
              when l.status <> 'active' then 'Not active' end
    from public.customer_credit_lots l
    left join lateral (
      select l.remaining_amount + b.cancelled_unused_value + e.unused >= b.granted_value as unspent,
             l.remaining_amount + b.cancelled_unused_value + e.unused >= b.granted_value
               and b.cancelled_unused_value = 0
               and not exists (select 1 from public.invoice_benefit_transfers t where t.source_benefit_id = b.id)
               and not exists (select 1 from public.invoice_reopen_benefits q
                                where q.invoice_id = p_invoice_id and q.applied_at is null)
               and not exists (select 1 from public.invoices iv
                                where iv.id = p_invoice_id and iv.status in ('cancelled', 'refunded')) as moves,
             e.unused > 0 and not exists (select 1 from public.invoice_benefit_transfers t
                                           where t.source_benefit_id = b.id and t.replacement_benefit_id is not null) as refunded
        from public.invoice_benefit_values b
        cross join lateral (select public.invoice_benefit_unused_elsewhere(b.id) as unused) e
       where b.lot_id = l.id and b.invoice_id = p_invoice_id) u on true
   where l.id in (select lot_id from public.invoice_credit_lot_ids(p_invoice_id))
$a4$];
  c_patch constant text[] := array[
$p1$    -- 462 (the Owner, 24 Oct 2026): a lot whose benefit value an Owner moved
    -- on (Move) too, now: the moved credit is traced through the Move's own
    -- ledger rows (invoice_credit_transfer_origin), not through this lot, so
    -- its records follow the credit to the kept record like any other's.
    -- Before, they stayed on the duplicate's emptied lot, so Cancel asked a
    -- false credit_used, its refund due fell and the kept record kept credit
    -- Cancel did not take back (460's NOT COVERED 4 (d)).
    update public.invoice_benefit_values set lot_id = v_new_lot where lot_id = r_lot.id;
    update public.credit_package_sales set credit_lot_id = v_new_lot where credit_lot_id = r_lot.id;
    update public.credit_package_sales set bonus_credit_lot_id = v_new_lot where bonus_credit_lot_id = r_lot.id;
    update public.premium_bundle_sales set paid_credit_lot_id = v_new_lot where paid_credit_lot_id = r_lot.id;
    update public.premium_bundle_sales set bonus_credit_lot_id = v_new_lot where bonus_credit_lot_id = r_lot.id;
    update public.invoice_credit_splits set issued_lot_id = v_new_lot where issued_lot_id = r_lot.id;
$p1$,
$p2$       -- 461 (the Owner, 22 Oct 2026): or nothing on it was spent. Credit a
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
                                where iv.id = p_invoice_id and iv.status in ('cancelled', 'refunded')))
       and l.remaining_amount > 0
       and l.status = 'active'
$p2$,
$p3$    -- 462 (the Owner, 24 Oct 2026): a lot whose benefit value an Owner moved
    -- on (Move) too, now: the moved credit is traced through the Move's own
    -- ledger rows (invoice_credit_transfer_origin), not through this lot, so
    -- its records follow like any other's (as in a merge, 462).
    update public.invoice_benefit_values set lot_id = v_new_lot where lot_id = r_lot.id;
    update public.credit_package_sales set credit_lot_id = v_new_lot where credit_lot_id = r_lot.id;
    update public.credit_package_sales set bonus_credit_lot_id = v_new_lot where bonus_credit_lot_id = r_lot.id;
    update public.premium_bundle_sales set paid_credit_lot_id = v_new_lot where paid_credit_lot_id = r_lot.id;
    update public.premium_bundle_sales set bonus_credit_lot_id = v_new_lot where bonus_credit_lot_id = r_lot.id;
    update public.invoice_credit_splits set issued_lot_id = v_new_lot where issued_lot_id = r_lot.id;
$p3$,
$p4$  -- 461 (the Owner, 22 Oct 2026: "fix the other two rare gaps too"; 448's
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
           and (w.untouched or coalesce(u.moves, false)),
         l.remaining_amount > 0 and not w.untouched and not coalesce(u.moves, false),
         case when l.remaining_amount = 0 and u.unspent and u.refunded then 'Refunded; nothing is left to move'
              when l.remaining_amount = 0 then 'Fully spent; it stays with the original customer'
              when not w.untouched and not coalesce(u.moves, false) then 'Partly spent'
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
   where l.id in (select lot_id from public.invoice_credit_lot_ids(p_invoice_id))
$p4$];

  -- ══ The trigger and the index this adds, as the database prints them ════
  c_trg_sql constant text := $t$create constraint trigger credit_given_back_follows after insert on public.customer_credit_ledger
  deferrable initially deferred for each row
  when (new.entry_type = 'reverse' and new.lot_id is not null
        and new.source_type in ('invoice_payment_refund', 'payment_correction', 'special_sale', 'rental', 'rental_late_fee'))
  execute function public.trg_credit_given_back_follows()$t$;
  c_trg_def constant text := $t$CREATE CONSTRAINT TRIGGER credit_given_back_follows AFTER INSERT ON public.customer_credit_ledger DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (((new.entry_type = 'reverse'::text) AND (new.lot_id IS NOT NULL) AND (new.source_type = ANY (ARRAY['invoice_payment_refund'::text, 'payment_correction'::text, 'special_sale'::text, 'rental'::text, 'rental_late_fee'::text])))) EXECUTE FUNCTION trg_credit_given_back_follows()$t$;
  c_idx_sql constant text := $i$create index customer_credit_ledger_transfer_lots_idx on public.customer_credit_ledger (source_record_id)
  where source_type in ('invoice_benefit_transfer_out', 'invoice_benefit_transfer_in')$i$;
  c_idx_def constant text := $i$CREATE INDEX customer_credit_ledger_transfer_lots_idx ON public.customer_credit_ledger USING btree (source_record_id) WHERE (source_type = ANY (ARRAY['invoice_benefit_transfer_out'::text, 'invoice_benefit_transfer_in'::text]))$i$;

  -- ══ Relied on, not changed (production, 24 Oct 2026, at 464) ════════════
  c_relied constant text[] := array[
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)',
    'refund_special_credit(text,uuid)',
    'allocate_invoice_wallet_credit(uuid,numeric,text,text)',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'reopen_invoice(uuid,text,uuid)',
    'invoice_reopen_preview_before_sessions(uuid)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'invoice_action_plan(uuid,text,jsonb)',
    'cancelled_invoice_used_value(uuid)',
    'invoice_benefit_unused_elsewhere(uuid)',
    'invoice_credit_lot_ids(uuid)',
    'invoice_benefits_holder(uuid,uuid,timestamp with time zone)',
    'transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)',
    'preview_customer_merge(uuid,uuid)',
    'delete_customer(uuid,text,text)',
    'credit_lot_policy_for(uuid)',
    'credit_lot_source_group(uuid)',
    'customer_credit_statement(uuid,date,date)',
    'reverse_credit_lot(uuid,text,text,text)',
    'repair_credit_package_progress_lots()',
    'apply_reopened_invoice_vouchers()',
    'invoice_own_voucher_ids(uuid)',
    'ensure_customer_wallet(uuid)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'trg_credit_lot_immutable()',
    'trg_credit_ledger_immutable()'];
  c_relied_md5 constant text[] := array[
    '804ecd829cfecf713783a09a05d93c7e',
    'af99337094edb6d73b9cc0ae00fbf138',
    'e019e28ad79539d771376c9b38d7e27e',
    'da8aa986c92d765a8028741f33bf56b0',
    'de52d9dbaef8ab15163bef35cb9d733d',
    '0ff61e4ead121c198ea7f90a7fc78274',
    '12206ed066495024421b3b44a6a9d8e2',
    '04d647e13e9424a9375942e5812e91a2',
    '383d618edb28c3c9a360242d038a022c',
    '055a3b07b1c15ffb1ac19039fa6cb650',
    'd35d7c8ae7187985ea64f8a5c38a7d79',
    '50346a2e9aea50b31d4207c43b2f197c',
    '55995ff6e1ffd4a1172cb930512a34b0',
    '7aebd7120bc3928db46df0941cb20889',
    'f66c9d63369ef3b831ca74906a99b587',
    '5b407735574fc3cacd8067c4dc8213f4',
    'ccdd506e78c7cdca97194fde87cdcc42',
    '6b902cb426210eb10ee9a15344ff100b',
    '1ba4a16a8208906f9e88efbc716bd1dd',
    '10c1a3d8e3bb003fbaf01cf879f97c5e',
    'ebd2a1a9f8ce7a9c1c272168b30b5ce3',
    '28d3b7a69b91ddebcdb200559d96a0ef',
    '9340840f1ce4e031ec3613198688ba2e',
    '8ef18daebbbe3c12f2024290ea8416e8',
    'c705c733e213a27f0dc32d54322cc855',
    '0fc74da0dcc9b436dfd26c4582542f6c',
    '071ec0ccd5fc13107de0d11f85ba8c28'];
  -- Who calls the changed functions, as read (by name; a session's own
  -- temporary functions are not counted).
  c_callers constant text[] := array[
    'invoice_credit_transfer_origin=credit_lot_allows_category(uuid,text), credit_lot_policy_for(uuid), credit_lot_snapshot_allows(uuid,jsonb,text,uuid), credit_lot_source_group(uuid), credit_lot_spending_summary(uuid), customer_credit_balances(uuid), customer_credit_eligibility(uuid)',
    'merge_customer_records=link_affiliate_signup(uuid,uuid,text,uuid,boolean)',
    'move_invoice_benefits_to_customer=correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'invoice_transferable_benefits=correct_invoice(uuid,jsonb,jsonb,text,uuid), move_invoice_benefits_to_customer(uuid,uuid,uuid,text), preview_invoice_correction(uuid,jsonb)',
    'invoice_reopen_preview=reopen_invoice(uuid,text,uuid)',
    'apply_reopened_invoice_benefits='];
  -- What writes a 'reverse' ledger row, and what raises a lot's balance by
  -- an amount, as read (24 Oct 2026).
  c_reverse_writers constant text := 'apply_reopened_invoice_benefits(), correct_invoice_payment(uuid,numeric,date,uuid,text,uuid), customer_credit_statement(uuid,date,date), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), refund_special_credit(text,uuid), repair_credit_package_progress_lots(), reverse_credit_lot(uuid,text,text,text), reverse_invoice_date_recovery(uuid,uuid,text)';
  c_raisers constant text := 'apply_reopened_invoice_benefits(), correct_invoice_payment(uuid,numeric,date,uuid,text,uuid), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), refund_special_credit(text,uuid)';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  r record; v text; d text; n int; k int; i int; v_first boolean; v_left int := 0;
  v_defs text[] := '{}'; v_fns text[] := '{}'; v_acl text[] := '{}'; v_built text[]; v_old jsonb; v_new uuid; v_root uuid;
  v_cur uuid; v_lots text := ''; v_nlots int := 0;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_pk uuid; t_svc uuid; t_wallet uuid;
  t_a uuid; t_b uuid; t_k uuid; t_f uuid; t_c uuid; t_d uuid; t_e uuid; t_g uuid; t_inv uuid; t_inv2 uuid; t_lot uuid; t_ben uuid;
  t_ans jsonb; t_msg text;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The texts are the tested ones.
  if md5(c_def_trace) <> c_after[1] or md5(c_def_apply) <> c_after[2] or md5(c_def_preview) <> c_after[3]
     or md5(c_def_ancestry) <> c_new_after[1] or md5(c_def_holder) <> c_new_after[2]
     or md5(c_def_follows) <> c_new_after[3] or md5(c_def_trg) <> c_new_after[4] then
    raise exception '462: a text in this file is not the tested one'; end if;

  -- The functions relied on are as read on production (24 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '462: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if to_regprocedure('auth.uid()') is null then raise exception '462: auth.uid() must be there'; end if;

  -- The columns read, with these types.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('customer_credit_lots', 'id', 'uuid'), ('customer_credit_lots', 'customer_id', 'uuid'),
                 ('customer_credit_lots', 'wallet_id', 'uuid'), ('customer_credit_lots', 'category', 'text'),
                 ('customer_credit_lots', 'status', 'text'), ('customer_credit_lots', 'is_locked', 'boolean'),
                 ('customer_credit_lots', 'original_amount', 'numeric(12,2)'), ('customer_credit_lots', 'remaining_amount', 'numeric(12,2)'),
                 ('customer_credit_lots', 'source_type', 'text'), ('customer_credit_lots', 'source_record_id', 'uuid'),
                 ('customer_credit_lots', 'store_id', 'uuid'), ('customer_credit_lots', 'usage_restrictions', 'jsonb'),
                 ('customer_credit_lots', 'reassigned_from_lot_id', 'uuid'), ('customer_credit_lots', 'created_at', 'timestamp with time zone'),
                 ('customer_credit_ledger', 'lot_id', 'uuid'), ('customer_credit_ledger', 'entry_type', 'text'),
                 ('customer_credit_ledger', 'source_type', 'text'), ('customer_credit_ledger', 'source_record_id', 'uuid'),
                 ('customer_credit_ledger', 'amount', 'numeric(12,2)'), ('customer_credit_ledger', 'entry_seq', 'bigint'),
                 ('invoice_benefit_values', 'id', 'uuid'), ('invoice_benefit_values', 'invoice_id', 'uuid'),
                 ('invoice_benefit_values', 'lot_id', 'uuid'), ('invoice_benefit_values', 'invoice_item_id', 'uuid'),
                 ('invoice_benefit_values', 'cancelled_unused_value', 'numeric(12,2)'), ('invoice_benefit_values', 'granted_value', 'numeric(12,2)'),
                 ('invoice_benefit_transfers', 'id', 'uuid'), ('invoice_benefit_transfers', 'invoice_id', 'uuid'),
                 ('invoice_benefit_transfers', 'source_benefit_id', 'uuid'), ('invoice_benefit_transfers', 'replacement_benefit_id', 'uuid'),
                 ('invoice_benefit_transfers', 'store_id', 'uuid'), ('invoice_benefit_transfers', 'transferred_value', 'numeric(12,2)'),
                 ('invoice_benefit_transfers', 'before_snapshot', 'jsonb'), ('invoice_benefit_transfers', 'after_snapshot', 'jsonb'),
                 ('credit_package_sales', 'invoice_id', 'uuid'), ('credit_package_sales', 'credit_lot_id', 'uuid'),
                 ('credit_package_sales', 'bonus_credit_lot_id', 'uuid'), ('premium_bundle_sales', 'invoice_id', 'uuid'),
                 ('premium_bundle_sales', 'paid_credit_lot_id', 'uuid'), ('premium_bundle_sales', 'bonus_credit_lot_id', 'uuid'),
                 ('invoice_credit_splits', 'invoice_id', 'uuid'), ('invoice_credit_splits', 'issued_lot_id', 'uuid'),
                 ('credit_package_progress_lots', 'invoice_id', 'uuid'), ('credit_package_progress_lots', 'lot_id', 'uuid'),
                 ('invoice_reopen_benefits', 'invoice_id', 'uuid'), ('invoice_reopen_benefits', 'applied_at', 'timestamp with time zone'),
                 ('customers', 'id', 'uuid'), ('customers', 'deleted_at', 'timestamp with time zone'),
                 ('invoices', 'id', 'uuid'), ('invoices', 'customer_id', 'uuid'), ('invoices', 'invoice_no', 'text'),
                 ('invoices', 'store_id', 'uuid'), ('invoices', 'status', 'invoice_status'),
                 ('invoice_benefit_values', 'created_at', 'timestamp with time zone'),
                 ('invoice_line_credit_allocations', 'lot_id', 'uuid'), ('invoice_line_credit_allocations', 'amount', 'numeric(12,2)'),
                 ('invoice_line_credit_allocations', 'reversed_amount', 'numeric(12,2)'),
                 ('special_credit_allocations', 'lot_id', 'uuid'), ('special_credit_allocations', 'amount', 'numeric(14,2)'),
                 ('special_credit_allocations', 'reversed_amount', 'numeric(14,2)')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '462: these columns are missing or not as read on 24 Oct 2026: %', v; end if;
  -- One benefit row per lot (a lot names the row it belongs to).
  if not exists (select 1 from pg_indexes where schemaname = 'public' and tablename = 'invoice_benefit_values'
                  and indexname = 'invoice_benefit_lot_unique'
                  and indexdef = 'CREATE UNIQUE INDEX invoice_benefit_lot_unique ON public.invoice_benefit_values USING btree (lot_id) WHERE (lot_id IS NOT NULL)') then
    raise exception '462: invoice_benefit_values no longer has one row per lot (invoice_benefit_lot_unique)'; end if;
  -- The ledger is append-only (the Move's two rows the trace reads never change).
  if not exists (select 1 from pg_trigger where tgrelid = 'public.customer_credit_ledger'::regclass and tgname = 'credit_ledger_immutable'
                  and not tgisinternal and tgenabled = 'O') then
    raise exception '462: the credit ledger is no longer append-only (credit_ledger_immutable)'; end if;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('invoice_credit_transfer_origin', 'apply_reopened_invoice_benefits', 'invoice_reopen_preview',
                       'merge_customer_records', 'move_invoice_benefits_to_customer', 'invoice_transferable_benefits',
                       'credit_lot_ancestry', 'invoice_credit_live_holder', 'credit_given_back_follows', 'trg_credit_given_back_follows')
     and p.oid::regprocedure::text <> all (c_sigs || c_new);
  if v is not null then raise exception '462: another function takes the name of one this changes or adds: %', v; end if;

  -- Who calls them, as read.
  foreach v in array c_callers loop
    select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where p.prosrc ~ (split_part(v, '=', 1) || '\s*\(') and ns.nspname not like 'pg\_temp\_%'
       and p.proname <> split_part(v, '=', 1)
       and p.proname not in ('credit_lot_ancestry', 'invoice_credit_live_holder', 'credit_given_back_follows', 'trg_credit_given_back_follows');
    if coalesce(d, '') is distinct from split_part(v, '=', 2) then
      raise exception '462: the functions that call % are not as read on 24 Oct 2026 (%); check each, then re-test', split_part(v, '=', 1), d; end if;
  end loop;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.invoices'::regclass and tgname = 'invoice_reopen_benefits_settled'
                  and tgfoid = 'public.apply_reopened_invoice_benefits()'::regprocedure and not tgisinternal) then
    raise exception '462: apply_reopened_invoice_benefits is no longer run by invoice_reopen_benefits_settled'; end if;

  -- What writes a 'reverse' ledger row, and what raises a lot's balance, as
  -- read on 24 Oct 2026. The trigger forwards the 'reverse' rows of four of
  -- them (by their source types): a refund or a correction of a sale paid
  -- with credit (refund_invoice_recorded, correct_invoice_payment) and a
  -- special document's credit refunded (refund_special_credit), each of which
  -- raises the lot and then writes the row; not the reopening's own
  -- ('invoice_reopen': the settlement, and 446's queued pair, which raises
  -- nothing), nor a reversal or a provenance repair (they take credit off).
  -- The statement lists the same sources as credit returned
  -- (customer_credit_statement; 'rental_late_fee' is a special document's
  -- kind it does not list, NOT COVERED). A new way would need the same
  -- forwarding: the file stops.
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ '''reverse''' and ns.nspname not like 'pg\_temp\_%';
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'remaining_amount\s*=\s*(\w+\.)?remaining_amount\s*\+' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_reverse_writers or d is distinct from c_raisers
     or (length(pg_get_functiondef('public.customer_credit_statement(uuid,date,date)'::regprocedure))
         - length(replace(pg_get_functiondef('public.customer_credit_statement(uuid,date,date)'::regprocedure),
                          'e.source_type in (''invoice_payment_refund'',''payment_correction'',''invoice_reopen'',''special_sale'',''rental'')', '')))
        <> 2 * length('e.source_type in (''invoice_payment_refund'',''payment_correction'',''invoice_reopen'',''special_sale'',''rental'')') then
    raise exception '462: what writes credit back on a lot is not as read on 24 Oct 2026 (% / %); check that the trigger forwards each, then re-test', v, d; end if;

  -- The trigger and the index: absent (added) or as this file makes them.
  if exists (select 1 from pg_trigger where tgrelid = 'public.customer_credit_ledger'::regclass and tgname = 'credit_given_back_follows')
     and (select pg_get_triggerdef(oid) from pg_trigger where tgrelid = 'public.customer_credit_ledger'::regclass
           and tgname = 'credit_given_back_follows') is distinct from c_trg_def then
    raise exception '462: a trigger credit_given_back_follows is there but not this one'; end if;
  if exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'customer_credit_ledger_transfer_lots_idx')
     and (select indexdef from pg_indexes where schemaname = 'public' and indexname = 'customer_credit_ledger_transfer_lots_idx') is distinct from c_idx_def then
    raise exception '462: an index customer_credit_ledger_transfer_lots_idx is there but not this one'; end if;

  -- The added functions: absent (added) or this version (left alone).
  for i in 1 .. cardinality(c_new) loop
    if to_regprocedure('public.' || c_new[i]) is not null
       and md5(pg_get_functiondef(to_regprocedure('public.' || c_new[i]))) <> c_new_after[i] then
      raise exception '462: public.% is there but not this version (md5 %)', c_new[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_new[i]))); end if;
  end loop;

  -- Each changed function: its BEFORE (changed; each anchor found once; the
  -- text built has its AFTER md5) or its AFTER (left alone).
  v_built := array[c_def_trace, c_def_apply, c_def_preview, null, null, null];
  for i in 1 .. cardinality(c_sigs) loop
    if to_regprocedure('public.' || c_sigs[i]) is null then raise exception '462: public.% is missing', c_sigs[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sigs[i]));
    if md5(d) = c_after[i] then
      raise notice '462: public.% is already this version; left alone', c_sigs[i]; v_left := v_left + 1;
      continue;
    end if;
    if md5(d) <> c_before[i] then
      raise exception '462: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sigs[i], md5(d); end if;
    if i >= 4 then
      for k in 1 .. cardinality(c_fn) loop
        continue when c_fn[k] <> i;
        n := (length(d) - length(replace(d, c_anchor[k], ''))) / length(c_anchor[k]);
        if n <> 1 then
          raise exception '462: anchor % of public.% is found % times, not once (md5 %)', k, c_sigs[i], n, md5(d); end if;
        d := replace(d, c_anchor[k], c_patch[k]);
      end loop;
      if md5(d) <> c_after[i] then
        raise exception '462: the text built for public.% is not the tested one (md5 %)', c_sigs[i], md5(d); end if;
      v_built[i] := d;
    end if;
    v_fns := v_fns || c_sigs[i];
    v_defs := v_defs || v_built[i];
  end loop;
  -- All six, or none: a part-way state is not one this was tested in.
  if v_left not in (0, cardinality(c_sigs)) then
    raise exception '462: only % of the six functions are already this version; not a state this was tested in', v_left; end if;
  v_first := v_left = 0;
  if not v_first and (not exists (select 1 from pg_trigger where tgrelid = 'public.customer_credit_ledger'::regclass and tgname = 'credit_given_back_follows')
                      or to_regprocedure('public.credit_given_back_follows(uuid)') is null) then
    raise exception '462: the functions are this version but the trigger or its functions are missing; not a state this was tested in'; end if;

  -- ── On the first run: nothing already in a state 462 reads differently
  -- and that needs a decision first (the header's read-only query lists
  -- each; a repair is a separate data fix, each with the Owner's yes).
  if v_first then
    -- (1) Every credit Move has exactly one 'invoice_benefit_transfer_out'
    -- and one 'invoice_benefit_transfer_in' ledger row, naming the lots its
    -- snapshots name, for what it moved: the trace reads them.
    select count(distinct t.invoice_id), string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into n, v
      from public.invoice_benefit_transfers t
      join public.invoices iv on iv.id = t.invoice_id
      left join public.invoice_benefit_values rb on rb.id = t.replacement_benefit_id
     where (rb.lot_id is not null or t.before_snapshot ? 'remaining_amount')
       and not ((select count(*) from public.customer_credit_ledger e
                  where e.source_type = 'invoice_benefit_transfer_out' and e.source_record_id = t.id) = 1
            and (select count(*) from public.customer_credit_ledger e
                  where e.source_type = 'invoice_benefit_transfer_in' and e.source_record_id = t.id) = 1
            and exists (select 1 from public.customer_credit_ledger e
                         where e.source_type = 'invoice_benefit_transfer_out' and e.source_record_id = t.id
                           and e.lot_id::text = t.before_snapshot->>'id' and e.amount = t.transferred_value)
            and exists (select 1 from public.customer_credit_ledger e
                         where e.source_type = 'invoice_benefit_transfer_in' and e.source_record_id = t.id
                           and e.lot_id::text = t.after_snapshot->>'id' and e.amount = t.transferred_value
                           and rb.lot_id is not null));
    if n > 0 then
      raise exception '462: % invoice(s) have an Owner''s Move of credit whose two ledger rows are not as every Move writes them (%): the new trace reads them. Nothing was changed.', n, v; end if;
    -- (2) No credit on a lot of an invoice's family that none of its
    -- records names (its benefit values, its sale's lots, a split's issued
    -- lot, released credit): the lots they name, each Move's two lots, the
    -- lots each replaced and every lot reissued from them. Nor a sale paid
    -- from such a lot, still refundable, where the lot is behind no lot a
    -- benefit row names (a merge before 462 reissued a lot whose records
    -- stayed, and the kept record spent it): its refund would give the
    -- credit back there, where nothing moves it.
    with recursive named(invoice_id, id) as (
      select b.invoice_id, b.lot_id from public.invoice_benefit_values b where b.lot_id is not null
      union select s.invoice_id, x from public.credit_package_sales s, unnest(array[s.credit_lot_id, s.bonus_credit_lot_id]) x where x is not null
      union select s.invoice_id, x from public.premium_bundle_sales s, unnest(array[s.paid_credit_lot_id, s.bonus_credit_lot_id]) x where x is not null
      union select c.invoice_id, c.issued_lot_id from public.invoice_credit_splits c where c.issued_lot_id is not null
      union select p.invoice_id, p.lot_id from public.credit_package_progress_lots p),
    seed(invoice_id, id) as (
      select invoice_id, id from named
      union select t.invoice_id, e.lot_id from public.invoice_benefit_transfers t
              join public.customer_credit_ledger e on e.source_record_id = t.id
             where e.source_type in ('invoice_benefit_transfer_out', 'invoice_benefit_transfer_in')),
    up(invoice_id, id, depth) as (
      select invoice_id, id, 0 from seed
      union select up.invoice_id, l.reassigned_from_lot_id, up.depth + 1 from up join public.customer_credit_lots l on l.id = up.id
             where l.reassigned_from_lot_id is not null and up.depth < 30),
    down(invoice_id, id, depth) as (
      select invoice_id, id, 0 from up
      union select down.invoice_id, l.id, down.depth + 1 from down join public.customer_credit_lots l on l.reassigned_from_lot_id = down.id
             where down.depth < 30),
    behind(invoice_id, id, depth) as (
      select b.invoice_id, b.lot_id, 0 from public.invoice_benefit_values b where b.lot_id is not null
      union select behind.invoice_id, p.id, behind.depth + 1 from behind join public.customer_credit_lots l on l.id = behind.id
              join public.customer_credit_lots p on p.id = l.reassigned_from_lot_id
               and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
             where behind.depth < 12)
    select count(distinct f.invoice_id), string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into n, v
      from (select distinct invoice_id, id from down) f
      join public.customer_credit_lots l on l.id = f.id
      join public.invoices iv on iv.id = f.invoice_id
     where not exists (select 1 from named nm where nm.invoice_id = f.invoice_id and nm.id = f.id)
       and (l.remaining_amount > 0
            or not exists (select 1 from behind bh where bh.invoice_id = f.invoice_id and bh.id = f.id)
               and (exists (select 1 from public.invoice_line_credit_allocations a
                             where a.lot_id = f.id and a.amount > coalesce(a.reversed_amount, 0))
                    or exists (select 1 from public.special_credit_allocations s
                                where s.lot_id = f.id and s.amount > coalesce(s.reversed_amount, 0))));
    if n > 0 then
      raise exception '462: % invoice(s) have credit on a lot none of their records names, or a sale paid from such a lot that a refund would give back there (%): Cancel and Refund in full read it as spent. Decide where it belongs (a data fix), then apply. Nothing was changed.', n, v; end if;
    -- (3) No lot more than 12 lots down a chain (the readers' limit).
    with recursive c(start, id, depth) as (
      select l.id, l.id, 0 from public.customer_credit_lots l where l.reassigned_from_lot_id is not null
      union all
      select c.start, l.reassigned_from_lot_id, c.depth + 1 from c join public.customer_credit_lots l on l.id = c.id
       where l.reassigned_from_lot_id is not null and c.depth < 13)
    select count(distinct start) into n from c where depth >= 13;
    if n > 0 then
      raise exception '462: % credit lot(s) are more than 12 reissues down their chain, further than the readers follow. Nothing was changed.', n; end if;
    -- (4) No credit on a lot the records name held by someone other than
    -- whoever holds the invoice's benefits now (460's NOT COVERED 4 (a) and
    -- (b): a merge or a customer change after a Move; or a deleted record).
    select count(distinct b.invoice_id), string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into n, v
      from public.invoice_benefit_values b
      join public.customer_credit_lots l on l.id = b.lot_id
      join public.invoices iv on iv.id = b.invoice_id
      cross join lateral (select public.invoice_benefits_holder(b.invoice_id, l.customer_id,
                                   case when exists (select 1 from public.invoice_benefit_transfers t where t.replacement_benefit_id = b.id)
                                        then 'infinity'::timestamptz else l.created_at end) as id) h
     where l.remaining_amount > 0 and l.status = 'active'
       and l.customer_id is distinct from coalesce(
             (select c.id from public.customers c where c.id = h.id and c.deleted_at is null),
             (select c.id from public.customers c where c.id = iv.customer_id and c.deleted_at is null),
             (select c.id from public.customers c where c.id = l.customer_id and c.deleted_at is null));
    if n > 0 then
      raise exception '462: % invoice(s) have credit on a lot their records name held by someone other than whoever holds their benefits now (%): a merge or a customer change after an Owner''s Move, or a deleted record. Decide where it belongs (a data fix), then apply. Nothing was changed.', n, v; end if;
    -- What the trace says now, for every moved lot (compared afterwards).
    select coalesce(jsonb_object_agg(l.id::text, public.invoice_credit_transfer_origin(l.id)), '{}'::jsonb) into v_old
      from public.customer_credit_lots l where l.source_type = 'invoice_benefit_transfer';
  end if;

  -- Who may call each, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  for i in 1 .. cardinality(c_sigs) loop
    if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i]))
       is distinct from (select array_agg(x::text order by x::text) from unnest(c_acl[i]::aclitem[]) x) then
      raise exception '462: who may call public.% is not as read on 24 Oct 2026 (%)', c_sigs[i],
        (select proacl::text from pg_proc where oid = to_regprocedure('public.' || c_sigs[i])); end if;
    v_acl := v_acl || (select coalesce(string_agg(x::text, ',' order by x::text), '')
                         from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i]));
  end loop;

  -- ── Change ──────────────────────────────────────────────────────────────
  for i in 1 .. cardinality(c_new) loop
    continue when to_regprocedure('public.' || c_new[i]) is not null;
    execute case i when 1 then c_def_ancestry when 2 then c_def_holder when 3 then c_def_follows else c_def_trg end;
    execute format('revoke all on function public.%s from public, anon, authenticated', c_new[i]);
    execute format('grant execute on function public.%s to service_role', c_new[i]);
  end loop;
  for k in 1 .. coalesce(cardinality(v_defs), 0) loop
    execute v_defs[k];
  end loop;
  if not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'customer_credit_ledger_transfer_lots_idx') then
    execute c_idx_sql; end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.customer_credit_ledger'::regclass and tgname = 'credit_given_back_follows') then
    execute c_trg_sql; end if;

  -- ── Afterwards: installed exactly as tested, grants as before ───────────
  for i in 1 .. cardinality(c_sigs) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[i]))) <> c_after[i] then
      raise exception '462: public.% is not at its AFTER md5 (%)', c_sigs[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[i]))); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i])) is distinct from v_acl[i] then
      raise exception '462: the grants of public.% changed', c_sigs[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_new) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_new[i]))) <> c_new_after[i]
       or (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new[i]))
          is distinct from (select array_agg(x::text order by x::text) from unnest(c_new_acl::aclitem[]) x)
       or has_function_privilege('anon', 'public.' || c_new[i], 'execute')
       or has_function_privilege('authenticated', 'public.' || c_new[i], 'execute') then
      raise exception '462: public.% is not as tested, or not the server''s alone', c_new[i]; end if;
  end loop;
  if (select pg_get_triggerdef(oid) from pg_trigger where tgrelid = 'public.customer_credit_ledger'::regclass
       and tgname = 'credit_given_back_follows') is distinct from c_trg_def
     or (select indexdef from pg_indexes where schemaname = 'public' and indexname = 'customer_credit_ledger_transfer_lots_idx') is distinct from c_idx_def then
    raise exception '462: the trigger or the index is not as tested'; end if;

  -- The trace gives every moved lot the origin it gave before; where it
  -- gave none (a moved lot partly taken back and then merged, 445's NOT
  -- COVERED; an older lot of a moved row a merge emptied), the new one may
  -- only be the lot the Move's own ledger rows lead back to. Listed.
  if v_first then
    for r in select o.key::uuid as lot_id, case when o.value = 'null'::jsonb then null else (o.value #>> '{}')::uuid end as old
               from jsonb_each(v_old) o loop
      v_new := public.invoice_credit_transfer_origin(r.lot_id);
      if r.old is not null and v_new is distinct from r.old then
        raise exception '462: the trace of moved lot % would change from % to %. Nothing was changed.', r.lot_id, r.old, v_new; end if;
      if r.old is null and v_new is not null then
        v_cur := r.lot_id; v_root := null;
        for k in 1 .. 20 loop
          select l.id into v_root from public.customer_credit_lots l where l.id = v_cur and l.source_type <> 'invoice_benefit_transfer';
          exit when v_root is not null;
          select e.lot_id into v_cur from public.customer_credit_ledger e join public.customer_credit_lots l on l.id = v_cur
           where e.source_type = 'invoice_benefit_transfer_out' and e.source_record_id = l.source_record_id;
          exit when v_cur is null;
        end loop;
        if v_new is distinct from v_root then
          raise exception '462: the trace of moved lot % would newly give % where its Move leads back to %. Nothing was changed.', r.lot_id, v_new, v_root; end if;
        v_nlots := v_nlots + 1; v_lots := v_lots || ' ' || r.lot_id::text;
      end if;
    end loop;
    if v_nlots > 0 then
      raise notice '462: % moved lot(s) now traced to their origin (before: held for review):%', v_nlots, v_lots; end if;
  end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("462 check", @example.invalid, fictional ACMA
  -- phones no customer uses); it ends by raising P0462, which undoes all it
  -- wrote. The trigger runs at commit; here it is run at each step's end
  -- (SET CONSTRAINTS ... IMMEDIATE), as a commit would.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from unnest(array['+61491570981', '+61491570982', '+61491570983', '+61491570984', '+61491570985',
                                                 '+61491570986', '+61491570987', '+61491570988', '+61491570989', '+61491570990',
                                                 '+61491570991', '+61491570992']) p
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p limit 8);
    if coalesce(cardinality(t_phones), 0) < 8 then raise exception '462: the self-test found no eight unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '462-check-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '462 check', '462-check-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('462 check ' || t_sfx, '462-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('462 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy, grants_reward)
    values ('462 check ' || t_sfx, 100, 100, false, true, true, false) returning id into t_pk;
    insert into public.credit_package_stores (package_id, store_id) values (t_pk, t_store);
    insert into public.therapy_services (service_code, name, standard_price, duration_minutes, is_active)
    values ('462-' || t_sfx, '462 check ' || t_sfx, 20, 30, true) returning id into t_svc;
    insert into public.therapy_service_stores (service_id, store_id, is_available) values (t_svc, t_store, true);
    select pm.id into t_wallet from public.payment_methods pm
     where pm.name = 'Wallet — Credit Package Paid' and pm.is_wallet_credit and pm.deleted_at is null;
    if t_wallet is null then raise exception '462: the wallet method "Wallet — Credit Package Paid" (443) is not there'; end if;
    insert into public.customers (full_name, phone) values ('462 Check Buyer ' || t_sfx, t_phones[1]) returning id into t_a;
    insert into public.customers (full_name, phone) values ('462 Check Second ' || t_sfx, t_phones[2]) returning id into t_b;
    insert into public.customers (full_name, phone) values ('462 Check Kept ' || t_sfx, t_phones[3]) returning id into t_k;
    insert into public.customers (full_name, phone) values ('462 Check Friend ' || t_sfx, t_phones[4]) returning id into t_f;
    insert into public.customers (full_name, phone) values ('462 Check Third ' || t_sfx, t_phones[5]) returning id into t_c;
    insert into public.customers (full_name, phone) values ('462 Check Fourth ' || t_sfx, t_phones[6]) returning id into t_d;
    insert into public.customers (full_name, phone) values ('462 Check Fifth ' || t_sfx, t_phones[7]) returning id into t_e;
    insert into public.customers (full_name, phone) values ('462 Check Sixth ' || t_sfx, t_phones[8]) returning id into t_g;

    -- (a) 460's NOT COVERED 4 (a): S$40 of the package refunded by line, the
    -- S$60 left moved to the friend (Move), cancelled, reopened, the
    -- benefits moved to a second customer while it waits (the customer
    -- change's step), paid: the second customer holds the S$40 on a lot that
    -- replaces the buyer's and that the benefit row and the sale name, with
    -- its origin; the friend's S$60 traces to the package; nothing reads as
    -- spent and the cancel's refund due is S$100.
    t_inv := public.create_invoice(t_store, t_a, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
    select b.id, b.lot_id into t_ben, t_lot from public.invoice_benefit_values b where b.invoice_id = t_inv;
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', (select it.id from public.invoice_items it where it.invoice_id = t_inv), 'amount', 40,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_ben, 'amount', 40)))),
      jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt'
                                                           order by p.created_at limit 1), 'amount', 40)), '[]'::jsonb, '462 check', gen_random_uuid());
    perform public.transfer_invoice_unused_benefit(t_ben, t_f, t_store, '462 check', gen_random_uuid());
    perform public.cancel_invoice_recorded(t_inv, '462 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '462 check', gen_random_uuid());
    perform public.move_invoice_benefits_to_customer(t_inv, t_b, t_store, '462 check');
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 40)), gen_random_uuid());
    set constraints public.credit_given_back_follows immediate;
    set constraints public.credit_given_back_follows deferred;
    if (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> 0
       or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_f) <> 60
       or not exists (select 1 from public.customer_credit_lots n2
                        join public.invoice_benefit_values b on b.lot_id = n2.id and b.id = t_ben
                        join public.credit_package_sales s on s.invoice_id = t_inv and s.credit_lot_id = n2.id
                        join public.customer_credit_lots o on o.id = t_lot
                       where n2.customer_id = t_b and n2.remaining_amount = 40 and n2.reassigned_from_lot_id = t_lot
                         and (n2.source_type, n2.source_record_id, n2.category, n2.usage_restrictions, n2.store_id)
                             is not distinct from (o.source_type, o.source_record_id, o.category, o.usage_restrictions, o.store_id))
       or (select public.invoice_credit_transfer_origin(l.id) from public.customer_credit_lots l where l.customer_id = t_f) is distinct from t_lot
       or (select public.credit_lot_policy_for(l.id) from public.customer_credit_lots l where l.customer_id = t_f) <> 'package_paid'
       or exists (select 1 from jsonb_array_elements(coalesce(public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->'overrides_required', '[]'::jsonb)) o
                   where o->>'code' = 'credit_used')
       or (public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->>'refund_due')::numeric <> 100 then
      raise exception '462: (a) the reinstated credit did not go to the second customer with its records (%)',
        (select jsonb_agg(jsonb_build_object('customer', l.customer_id, 'remaining', l.remaining_amount)) from public.customer_credit_lots l
          where l.customer_id in (t_a, t_b, t_f)); end if;
    -- (b) 460's NOT COVERED 4 (d): then the second customer merged into a
    -- kept record: the kept record holds the S$40 on a lot the records
    -- name; the Move's trace still finds the package.
    perform public.merge_customer_records(t_k, t_b, '462 check: the same person', gen_random_uuid());
    if not exists (select 1 from public.customer_credit_lots l join public.invoice_benefit_values b on b.lot_id = l.id and b.id = t_ben
                    where l.customer_id = t_k and l.remaining_amount = 40)
       or (select public.invoice_credit_transfer_origin(l.id) from public.customer_credit_lots l where l.customer_id = t_f) is distinct from t_lot
       or (public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->>'refund_due')::numeric <> 100 then
      raise exception '462: (b) the merge did not take the credit with its records'; end if;
    -- (c) Then a change to a third customer moves it (it is not "Partly
    -- spent"): S$40 to the third, with its records.
    if exists (select 1 from public.invoice_transferable_benefits(t_inv) x where x.blocking) then
      raise exception '462: (c) the lot is still listed as blocking (%)',
        (select jsonb_agg(to_jsonb(x)) from public.invoice_transferable_benefits(t_inv) x); end if;
    perform public.move_invoice_benefits_to_customer(t_inv, t_c, t_store, '462 check');
    if not exists (select 1 from public.customer_credit_lots l join public.invoice_benefit_values b on b.lot_id = l.id and b.id = t_ben
                    where l.customer_id = t_c and l.remaining_amount = 40) then
      raise exception '462: (c) the change did not move the credit with its records'; end if;

    -- (d) The Owner (24 Oct 2026: "B, the package's holder now"): a second
    -- package; a fourth customer pays a S$20 session from it (the wallet),
    -- the S$80 left moved to the friend, the benefits moved to a fifth
    -- customer (nothing is left to move), then the session cancelled and its
    -- refund recorded: at commit the S$20 goes to the fifth customer, on a
    -- new lot the records name; the fourth holds nothing of it.
    t_inv := public.create_invoice(t_store, t_d, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
    select b.id, b.lot_id into t_ben, t_lot from public.invoice_benefit_values b where b.invoice_id = t_inv;
    t_inv2 := public.create_invoice(t_store, t_d, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 1)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv2, jsonb_build_array(jsonb_build_object('payment_method_id', t_wallet, 'amount', 20)), gen_random_uuid());
    if (select remaining_amount from public.customer_credit_lots where id = t_lot) <> 80 then
      raise exception '462: (d) the session was not paid from the package''s lot'; end if;
    perform public.transfer_invoice_unused_benefit(t_ben, t_f, t_store, '462 check', gen_random_uuid());
    perform public.move_invoice_benefits_to_customer(t_inv, t_e, t_store, '462 check');
    perform public.cancel_invoice_recorded(t_inv2, '462 check', gen_random_uuid());
    perform public.refund_invoice_recorded(t_inv2, jsonb_build_array(jsonb_build_object('amount', 20)),
      jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_inv2 and p.entry_kind = 'receipt'
                                                           order by p.created_at limit 1), 'amount', 20)), '[]'::jsonb, '462 check', gen_random_uuid());
    if (select remaining_amount from public.customer_credit_lots where id = t_lot) <> 20 then
      raise exception '462: (d) the session''s refund did not go back on the package''s lot before commit'; end if;
    set constraints public.credit_given_back_follows immediate;
    set constraints public.credit_given_back_follows deferred;
    if (select remaining_amount from public.customer_credit_lots where id = t_lot) <> 0
       or not exists (select 1 from public.customer_credit_lots n2
                        join public.invoice_benefit_values b on b.lot_id = n2.id and b.id = t_ben
                        join public.credit_package_sales s on s.invoice_id = t_inv and s.credit_lot_id = n2.id
                       where n2.customer_id = t_e and n2.remaining_amount = 20 and n2.original_amount = 20 and n2.reassigned_from_lot_id = t_lot)
       or (select count(*) from public.customer_credit_ledger e where e.lot_id = t_lot and e.source_type = 'credit_given_back_reassignment_out') <> 1
       or exists (select 1 from jsonb_array_elements(coalesce(public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->'overrides_required', '[]'::jsonb)) o
                   where o->>'code' = 'credit_used') then
      raise exception '462: (d) the session''s refund did not follow to the package''s holder (%)',
        (select jsonb_agg(jsonb_build_object('customer', l.customer_id, 'remaining', l.remaining_amount)) from public.customer_credit_lots l
          where l.customer_id in (t_d, t_e)); end if;

    -- (e) 460's refusal is gone: S$60 refunded, the buyer merged away, the
    -- S$40 left moved to the friend, cancelled: the preview allows the
    -- reopening, and once paid the kept record holds the S$60.
    t_inv := public.create_invoice(t_store, t_a, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
    select b.id into t_ben from public.invoice_benefit_values b where b.invoice_id = t_inv;
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', (select it.id from public.invoice_items it where it.invoice_id = t_inv), 'amount', 60,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_ben, 'amount', 60)))),
      jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt'
                                                           order by p.created_at limit 1), 'amount', 60)), '[]'::jsonb, '462 check', gen_random_uuid());
    perform public.merge_customer_records(t_g, t_a, '462 check: the same person', gen_random_uuid());
    perform public.transfer_invoice_unused_benefit(t_ben, t_f, t_store, '462 check', gen_random_uuid());
    perform public.cancel_invoice_recorded(t_inv, '462 check', gen_random_uuid());
    t_ans := public.invoice_reopen_preview(t_inv);
    if not coalesce((t_ans->>'can_reopen')::boolean, false) then
      raise exception '462: (e) the reopening is still refused (%)', t_ans->'blockers'; end if;
    perform public.reopen_invoice(t_inv, '462 check', gen_random_uuid());
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)), gen_random_uuid());
    if not exists (select 1 from public.customer_credit_lots l join public.invoice_benefit_values b on b.lot_id = l.id and b.id = t_ben
                    where l.customer_id = t_g and l.remaining_amount = 60)
       or (public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->>'refund_due')::numeric <> 100 then
      raise exception '462: (e) the reopened invoice did not give the S$60 to the kept record'; end if;

    -- (f) The critics' review (24 Oct 2026): credit given back while a
    -- reopening waits stays where it went back, and the payment that
    -- settles the reopening gives it to the benefits' holder, its reserve
    -- released. A third package; a S$20 session paid from it; cancelled; S$40
    -- of it refunded by line; reopened; the benefits moved to a kept record
    -- (the change's step); the session cancelled and refunded while it waits:
    -- at the commit point the S$20 is on the package's lot, nothing
    -- forwarded; paid: the kept record holds S$100 on a lot the benefit row
    -- names, nothing held back, nothing asked, due S$100.
    t_inv := public.create_invoice(t_store, t_d, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
    select b.id, b.lot_id into t_ben, t_lot from public.invoice_benefit_values b where b.invoice_id = t_inv;
    t_inv2 := public.create_invoice(t_store, t_d, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 1)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv2, jsonb_build_array(jsonb_build_object('payment_method_id', t_wallet, 'amount', 20)), gen_random_uuid());
    if (select remaining_amount from public.customer_credit_lots where id = t_lot) <> 80 then
      raise exception '462: (f) the session was not paid from the package''s lot'; end if;
    perform public.cancel_invoice_recorded(t_inv, '462 check', gen_random_uuid());
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', (select it.id from public.invoice_items it where it.invoice_id = t_inv), 'amount', 40,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_ben, 'amount', 40)))),
      jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt'
                                                           order by p.created_at limit 1), 'amount', 40)), '[]'::jsonb, '462 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '462 check', gen_random_uuid());
    perform public.move_invoice_benefits_to_customer(t_inv, t_k, t_store, '462 check');
    perform public.cancel_invoice_recorded(t_inv2, '462 check', gen_random_uuid());
    perform public.refund_invoice_recorded(t_inv2, jsonb_build_array(jsonb_build_object('amount', 20)),
      jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_inv2 and p.entry_kind = 'receipt'
                                                           order by p.created_at limit 1), 'amount', 20)), '[]'::jsonb, '462 check', gen_random_uuid());
    set constraints public.credit_given_back_follows immediate;
    set constraints public.credit_given_back_follows deferred;
    if (select remaining_amount from public.customer_credit_lots where id = t_lot) <> 20
       or exists (select 1 from public.customer_credit_ledger e where e.source_record_id = t_inv and e.source_type = 'credit_given_back_reassignment_out') then
      raise exception '462: (f) credit given back while the reopening waits did not stay where it went back'; end if;
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
      'amount', (public.invoice_financial_position(t_inv)->>'outstanding')::numeric)), gen_random_uuid());
    if (select remaining_amount from public.customer_credit_lots where id = t_lot) <> 0
       or not exists (select 1 from public.customer_credit_lots n2
                        join public.invoice_benefit_values b on b.lot_id = n2.id and b.id = t_ben and b.cancelled_unused_value = 0
                        join public.credit_package_sales s on s.invoice_id = t_inv and s.credit_lot_id = n2.id
                       where n2.customer_id = t_k and n2.remaining_amount = 100)
       or exists (select 1 from jsonb_array_elements(coalesce(public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->'overrides_required', '[]'::jsonb)) o
                   where o->>'code' = 'credit_used')
       or (public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->>'refund_due')::numeric <> 100 then
      raise exception '462: (f) the reopening''s payment did not give the S$100 to the benefits'' holder, its reserve released (%)',
        (select jsonb_agg(jsonb_build_object('customer', l.customer_id, 'remaining', l.remaining_amount)) from public.customer_credit_lots l
          where l.customer_id in (t_d, t_k)); end if;
    raise exception using errcode = 'P0462', message = '462: self-test done, undone';
  exception when sqlstate 'P0462' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
