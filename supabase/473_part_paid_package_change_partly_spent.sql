-- 473_part_paid_package_change_partly_spent.sql
--
-- A 'TRANSFER' CUSTOMER CHANGE OF A PACKAGE PAID IN PART WHOSE CREDIT WAS
-- PARTLY SPENT IS REFUSED AS "PARTLY SPENT", AS IT IS FOR THE SAME PACKAGE
-- PAID IN FULL: ITS PAID CREDIT IS JUDGED AS ONE, NOT LOT BY LOT (471's NOT
-- COVERED 9; the Owner, 26 Oct 2026: "fix the leftover gaps too")
--
-- (The number 473 is this file's name, its errors' prefix, its self-test's
-- error code P0473 and its suite's; if it changes at commit, change it in
-- these places alone: the file name, the "473:" messages, P0473, the suite,
-- and the "-- 473 (the Owner" line the suites find the list by.)
--
-- WHO FOUND IT
--
--   471's review (its NOT COVERED 9 and its suite's KNOWN K9, 26 Oct 2026),
--   put to the Owner with 471, then (26 Oct 2026) "fix the leftover gaps
--   too". Reproduced on copies of production at 471 with 472 in (fd61e1a1
--   then 84308fd1, 1387 functions, 26 Oct 2026) with K9's case and its
--   siblings (this file's suite, section R): made-up records, the app's own
--   calls (the invoice form's customer change, correct_invoice with
--   'transfer'), each followed by what its commit does. Building 473 found,
--   on the same copies, that the cancel and reopening K9 names are not
--   needed (paid in part, the credit released spent, then paid in full: TQp),
--   that a package paid in part twice before it is paid in full splits the
--   same way (W2), and that the Premium Bundle, the Bonus package, a buyer
--   merged or changed before the spending, a Move to the same customer at
--   another store and a second change after a 'keep' all do (TQv, TQb, TQmb,
--   TQcb, TQms, TQk).
--
-- WHAT WAS WRONG
--
--   A Credit Package or Premium Bundle paid in part releases its paid credit
--   as the money comes in (327, 356: S$1 of credit for each S$1 received),
--   on a lot of its own for each payment (credit_package_progress_lots, the
--   release record); once paid in full the rest is granted on another lot,
--   and a benefit row names each (capture_invoice_benefit_values). So the
--   paid credit of one package line is on two lots or more, where a package
--   paid in full has it on one. The list of what a customer change can move
--   (invoice_transferable_benefits, which the change, move_invoice_benefits_
--   to_customer, refuses on and the correction summary reads) judged each lot
--   on its own: a lot whose credit was spent in full reads "Fully spent; it
--   stays with the original customer" (nothing to move, so no refusal), and
--   an untouched lot moves. Where the credit released before full payment
--   was all spent and the rest untouched, a 'transfer' customer change moved
--   the rest to the new customer and left the spending with the buyer: the
--   one package split between two customers. The same package paid in full
--   with the same spending, one lot partly spent, is refused ("These
--   benefits have already been used and cannot move with the invoice: Paid
--   credit 60.00 (Partly spent)"). On copies, a S$100 package sold to A,
--   S$40 paid (S$40 released), two S$20 sessions paid from it, then:
--   * cancelled, reopened and paid in full, a 'transfer' change to B: B
--     holds S$60, A has used S$40 (TQ, 471's K9); the same without the
--     cancel and the reopening (TQp), with a second change to C after it (C
--     S$60: TQ2) or after a 'keep' change to B first (TQk: C S$60);
--   * the Premium Bundle (S$140; S$40 paid, S$40 of its S$100 paid credit
--     released): B holds the S$60 paid, the S$40 Bonus and the 2 vouchers
--     (TQv); the S$100 + S$10 Bonus package: B S$70 (TQb);
--   * the buyer merged into K, or the customer changed to C, before the
--     sessions (K or C spent the S$40): B S$60 (TQmb, TQcb);
--   * an Owner's Move of the S$60 to A at another store (a store correction,
--     463's decision 2), then the change: B S$60 (TQms);
--   * a S$5 session paid from the S$40, then an Owner reversed the S$35
--     left (reverse_credit_lot: no page calls it), then paid in full: B S$60
--     (TQr; nothing spent and the S$40 reversed, TQr0; on one lot the
--     reversal reads as used: a lot reversed, a session refunded onto it, is
--     refused "Partly spent", RVc);
--   * S$20 paid (S$20 released), a S$20 session paid from it, S$20 more paid
--     (S$20 released again, on a lot of its own; not paid in full yet): B
--     holds S$20, and the full payment would grant B the S$60 left (W2);
--     the buyer merged into K before the session (W2m), a 'keep' change to C
--     first (W2k).
--   The money is right (nothing is given twice; the net payment buys what
--   the lots hold), but the package was split between two customers where
--   the Owner's rule for a partly spent package is that the change is
--   refused and the benefits are resolved one by one (an Owner's Move, or
--   the change made with 'keep').
--
-- THE OWNER'S ANSWERS
--
--   22 Oct 2026: credit follows a merge and a 'transfer' customer change; a
--   Move's recipient keeps what was moved; refunds paid back count as not
--   used. 24 Oct 2026 (462, 463, 470): a cancel or refund takes back what
--   the invoice gave from whoever holds it now; the customer holds exactly
--   what the net payment buys; nothing stranded on a lot no record names;
--   nothing paid twice; Correct payment keeps working; a Move to the same
--   customer at another store is a store correction, which a change that
--   takes the benefits along takes along (463, decision 2). 26 Oct 2026
--   (471, 472): the deadlock trade-off, S$1 owed back per S$1 held for credit
--   released before full payment, RX0/RX1 owed to nobody, held while a
--   reopening waits: accepted. 26 Oct 2026, after choosing "Fix it later,
--   separately" for 471's NOT COVERED 7 and 10: "fix the leftover gaps too",
--   with this rule for this one: a transfer change of a partly spent package
--   is refused as "Partly spent", the existing rule for a fully paid
--   package, applied the same way; no business rule is changed beyond these
--   by guessing.
--
-- WHAT THIS DOES (one function changed, whole text; nothing added; no table,
-- column, trigger or grant changes)
--
--   invoice_transferable_benefits(uuid) (463's text; 471 and 472 pinned
--   it). Its credit rows (one per lot the invoice's records reach) now judge
--   a lot with the other lots of its package line and credit category ('paid'
--   or 'bonus'), as the same package paid in full is judged on its one lot:
--   * once the line is settled (a benefit row names each of its lots): a lot
--     holding credit is "Partly spent", blocking and not movable, where any
--     benefit row of the same line whose lot is of its category reads as
--     spent by 461's test (what its lot holds, what a cancellation took back
--     and what is not used although it is no longer on it, less than the row
--     granted). A row an Owner moved to someone else is its recipient's (434,
--     463) and is not read; one moved to the same customer at another store
--     is the invoice's own and is (463, decision 2). So K9's S$60 lot is
--     "Paid credit 60.00 (Partly spent)", and the change is refused with
--     exactly the paid-in-full package's words; a lot spent in full still
--     reads "Fully spent" (nothing on it to move), and a package nothing was
--     spent from moves as before (TQ0: B S$100);
--   * before it is settled (no benefit row names its lots): a lot of the
--     line's release record holding credit is "Partly spent" where another
--     release record of the same line whose lots no benefit row names reads
--     as spent: its lot (credit_lot_current: a merge's or change's reissue
--     followed) holds less than the record still counts as released (a
--     Cancel's write-off, a trim, 356, and 471's hold lower what it counts,
--     so only spending is left) (W2: "Paid credit 20.00 (Partly spent)").
--   Everything else is 463's text unchanged: the vouchers, the allowances,
--   therapy units, the lots listed and how each is described, the tests a
--   lot made before (461's refund, 462's reissue, 463's store Move).
--   Who reads it: the customer change (move_invoice_benefits_to_customer
--   refuses where any row blocks, before it moves anything), the correction
--   summary (preview_invoice_correction: the blocked rows under "These have
--   already been used and will not move. The correction is refused until
--   each is resolved through the benefit transfer review."), and the
--   invoice form (InvoicesPage.tsx asks only whether rows exist, to offer
--   'transfer' or 'keep'; the rows are the same, only their flags change).
--   A 'keep' change is not read against the list and still goes through;
--   the Owner's Move (transfer_invoice_unused_benefit) does not read it.
--   Money afterwards (the suite, each case): nothing moves, nothing is paid
--   or taken; a refused change leaves everything as it was.
--
-- WHY THIS WAY
--
--   In the list, the one place the rule is made (the change refuses on its
--   rows; the summary shows them), so the refusal, its words and the summary
--   come from one test. Judged by line and category because that is what
--   one lot is for a package paid in full: a package's paid credit and its
--   Bonus are two lots and always were judged apart (the Bonus lot still
--   reads as movable beside a partly spent paid credit, as for the package
--   paid in full: TQv, TQb; TVc, TBc).
--   Each row by 461's test, not a sum, so a refund paid back, a cancellation
--   and an Owner's Move read as they do on one lot (refunds paid back count
--   as not used: TU, both sessions refunded, moves S$100). Before
--   settlement by the release record, which is how every reader of credit
--   released before full payment counts it (cancelled_invoice_used_value,
--   Cancel's write-off, 471's hold). The other ways:
--   * changing move_invoice_benefits_to_customer's own lot test: it moves
--     only when the list blocks nothing, so the list's answer is enough; its
--     re-read of each lot once locked is per lot as before (NOT COVERED 4);
--   * one row per line in the list (a "Paid credit 80.00" for the line):
--     the change, the summary and 463's Move test read the list's rows as
--     lots (record_id is a lot); the words differ only where a line has two
--     lots holding credit (NOT COVERED 5).
--
-- NOT CHANGED
--
--   * move_invoice_benefits_to_customer (c01606c8), correct_invoice
--     (04d647e1), preview_invoice_correction (f2675223),
--     transfer_invoice_unused_benefit (7aebd712), merge_customer_records
--     (ba05c2b1), invoice_benefit_moved_from_spent (901fde96),
--     invoice_benefit_unused_elsewhere (d35d7c8a), invoice_credit_lot_ids,
--     the release record's readers and writers, 472's forwarder (f2a7a4d1):
--     pinned (below), unchanged. invoice_reopen_preview(_before_sessions)
--     (471's NOT COVERED 7, 474's to change): not read by the list, not
--     pinned, unchanged.
--   * Edge Functions, settings, pages: no change. Read from src: the invoice
--     form asks invoice_transferable_benefits only whether it has rows
--     (InvoicesPage.tsx), which 473 does not change; the refusal and the
--     summary's blocked rows are the server's words, the same as for a
--     package paid in full (CorrectionPreview.tsx shows "what — why"). The
--     form's 'transfer' choice says "Anything already used stays with
--     whoever used it, and a partly used benefit stops the correction for
--     review" (InvoicesPage.tsx): before 473 that did not hold for a package
--     paid in part (K9); with 473 it does, so it stays as it is.
--
-- NOT COVERED (for the Owner; the suite checks each as it is)
--
--   1. A package paid in part whose credit released so far was spent in full,
--      with nothing on a lot: a 'transfer' change passes (nothing moves; the
--      list has nothing to block, before 473 and after), and the next
--      payment's credit goes to the new customer, as it does with 'keep'
--      (release_credit_package_paid_credit and the settlement grant the
--      invoice's customer): TQn2 (S$40 paid, all spent, changed to B, then
--      paid: B S$60, A has used S$40, the K9 split by another order). The
--      Owner's rule refuses a change that would move part of a partly spent
--      package; here the change moves nothing, and refusing 'transfer' would
--      leave 'keep', which ends the same. What the later payment's credit
--      should do (go to whoever used the package, or to the invoice's new
--      customer) is for the Owner; a fix is its own migration. The header's
--      query lists such packages (3).
--   2. A 'keep' change of a package paid in part leaves what was released
--      with the buyer and gives what the later payments release to the new
--      customer (K1: S$40 paid, 'keep' to B, paid: A S$40, B S$60; K2, the
--      W2 state: A S$20, B S$60): the package splits with 'keep' too, before
--      473 and after. So once 473 refuses W2's 'transfer', 'keep' (the other
--      choice) also splits it, and the form's words for 'keep' ("Keep the
--      benefits with who holds them now ... Only the invoice's customer
--      changes") do not say that what is still to be released goes to the
--      new customer. Unchanged (what 'keep' does with credit not yet
--      released is not in the Owner's rules); the header's query lists
--      packages split so (4).
--   3. A cancelled partly spent package (Cancel took its credit back, so
--      nothing is on a lot) can be changed with 'transfer', and its
--      reopening's payment then gives what is left to the new customer
--      (TQcr: B S$60), as for the same package paid in full (TQcc: B S$60;
--      460's rule, the reopening gives back to whoever holds the benefits):
--      the existing rule for a fully paid package, unchanged.
--   4. The list is read before the change locks the lots, and the change
--      re-reads each lot's own figures once locked (461): a session paid
--      from the line's other lot committing in that moment would let the
--      untouched lot move, as before 473 (for a package paid in full the
--      same moment keeps all its credit with the buyer). Read from the code,
--      not timed on copies.
--   5. The refusal names each lot holding credit ("Paid credit 20.00 (Partly
--      spent); Paid credit 60.00 (Partly spent)"; the order is not fixed),
--      where the same package paid in full names one ("Paid credit 80.00
--      (Partly spent)"): TQ1, TU1.
--   6. Packages already split before 473 (a 'transfer' change of such a
--      package made before it): left as they are; the buyer keeps the use,
--      the new customer the rest; a later 'transfer' change of it is refused
--      from now on (MTQ: B to C refused, B S$60). The header's query lists
--      them (4), for the Owner: a data fix, or left as they are.
--   7. A summary or form open on a screen when this goes in shows the old
--      answer until it is opened again; the server checks again on save.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the text is the tested one (its AFTER md5); the function is its BEFORE
--     (463's AFTER, as 471 and 472 pinned it: replaced) or its AFTER (left
--     alone), anything else refused; no other function takes its name; so a
--     second run changes nothing;
--   * the functions it relies on are as read on production at 471 with 472
--     in (pinned, below): what it calls, who calls it, what writes benefit
--     rows, the release record and its lots, an Owner's Move, a merge and
--     472's forwarder; the columns read have these types; who calls the list,
--     who writes benefit rows, the release record and an Owner's Move, as
--     read (a new way would need the same care);
--   * on the first run nothing is refused for the data (473 needs no
--     decision before it goes in); the invoices of the header's query are
--     named in a notice (invoice numbers only): 1 and 2 (a 'transfer' change
--     now refused), 3 and 4 (for the Owner);
--   * who may call the function is as read, compared as sets, and kept;
--   * afterwards: the AFTER md5 and the grants as tested.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0473, so it leaves no row): a made-up Owner, store, S$100 package, S$20
--   session and ten customers (fictional ACMA phones no customer has), five
--   times, the package sold to A: (a) S$40 paid, two sessions paid from it,
--   cancelled, reopened and paid in full: the S$60 lot blocks as "Partly
--   spent", and a 'transfer' change to B is refused with "Paid credit 60.00
--   (Partly spent)", A still holding S$60; (b) the same never cancelled; (c)
--   S$20 paid, one session, S$20 more paid: the second S$20 lot blocks and
--   the change is refused with "Paid credit 20.00 (Partly spent)"; (d) S$40
--   paid, nothing spent, paid in full (a control): the change moves S$100 to
--   B; (e) paid in full, two sessions (a control): refused as before, "Paid
--   credit 60.00 (Partly spent)".
--   Its credit ledger rows draw entry numbers (a sequence, which an undone
--   transaction does not give back: a gap, as 443 to 472's self-tests).
--   Locks: the function's catalogue row to the end of the apply, and the
--   rows the self-test writes and undoes; no table is locked against
--   ordinary writes. The self-test takes the commission advisory locks
--   (through its cancels and customer changes) and new invoice numbers, so
--   it waits for any app cancel, refund, commission-writing payment or
--   invoice creation still open, and those wait for it, for under a second.
--   If one stays open longer than the 5 s lock timeout, or an invoice
--   created at the same moment takes the self-test's invoice number, the
--   apply stops, changing nothing, and can be run again. A customer change
--   still open when 473 commits reads the list as it was when it read it.
--   Apply at a quiet time.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (471 in, 26 Oct 2026: fd61e1a1, 1387 functions; the grant
--   list 381ef69c; head 20261026142140) -> 472 (84308fd1) -> 473. 473 pins
--   472's forwarder (its AFTER) and changes invoice_transferable_benefits,
--   which 471 and 472 pin: after 473 a re-run of 471 or 472 refuses (that
--   pin), changing nothing. 474 (471's NOT COVERED 7: the Reopen dialog)
--   goes after 473, or its pins are worked out again. If anything else goes
--   in first, work the fingerprints out again and check that it changes none
--   of the functions pinned below.
--   1. Before it, read only (invoice numbers and counts only; production was
--      not read for this file). 473 refuses no state, so this lists whose
--      answer changes (1, 2: a 'transfer' change now refused) and what needs
--      the Owner (3, 4). On the production facts known (26 Oct 2026: 6
--      part-paid release records, none cancelled) 1 to 4 may list invoices:
--     with
--     -- each credit benefit row of an invoice's own (not what an Owner moved
--     -- to someone else), its lot, and whether 461's test reads it as spent
--     r as (
--       select b.id, b.invoice_id, b.invoice_item_id, l.id as lot_id, l.customer_id, l.category, l.status as lot_status,
--              l.remaining_amount, l.original_amount, l.reassigned_from_lot_id, b.cancelled_unused_value,
--              l.remaining_amount + b.cancelled_unused_value + public.invoice_benefit_unused_elsewhere(b.id) < b.granted_value as spent,
--              i.status::text in ('cancelled', 'refunded')
--              or exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = i.id and q.applied_at is null) as held
--         from public.invoice_benefit_values b
--         join public.customer_credit_lots l on l.id = b.lot_id
--         join public.invoices i on i.id = b.invoice_id and i.deleted_at is null
--        where not public.invoice_benefit_moved_to_other(b.id)),
--     -- a settled package line (and credit category) one of whose rows reads as spent
--     sl as (
--       select r.invoice_id, r.invoice_item_id, r.category from r group by 1, 2, 3 having bool_or(r.spent)),
--     -- release records before settlement (no benefit row names a lot of their chain),
--     -- with the lot each reaches now (credit_lot_current) and whether it reads as spent
--     pre as (
--       select pl.invoice_id, pl.invoice_item_id, pl.lot_id, pl.released_amount, c.id as cur_id, c.customer_id, c.remaining_amount,
--              c.original_amount, c.status as lot_status,
--              pl.released_amount > 0 and coalesce(case when c.status = 'active' then c.remaining_amount end, 0) < pl.released_amount as spent
--         from public.credit_package_progress_lots pl
--         join public.invoices i on i.id = pl.invoice_id and i.deleted_at is null
--         join public.customer_credit_lots c on c.id = public.credit_lot_current(pl.lot_id)
--        where not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = any (public.credit_lot_chain(pl.lot_id)))),
--     found(reason, invoice_id, n) as (
--       select '1 changes: a settled package line part of whose paid (or bonus) credit was spent, with a lot of it holding credit that a ''transfer'' customer change moves today (untouched, or its own row unspent), and no lot of the invoice holding credit that blocks the change today; from 473 it reads "Partly spent" and the change is refused, as for the same package paid in full (the count is of lots)', r.invoice_id, count(*)
--         from r join sl using (invoice_id, invoice_item_id, category)
--        where not r.spent and r.lot_status = 'active' and r.remaining_amount > 0
--          and (r.remaining_amount = r.original_amount and r.reassigned_from_lot_id is null
--               or r.cancelled_unused_value = 0 and not r.held)
--          and not public.invoice_benefit_moved_from_spent(r.id)
--          and not exists (select 1 from r r2 where r2.invoice_id = r.invoice_id and r2.spent
--                           and r2.lot_status = 'active' and r2.remaining_amount > 0)
--        group by r.invoice_id
--       union all
--       select '2 changes: a package paid in part, not settled, with a lot of its released credit holding credit, untouched, beside another release of the same line that was spent; from 473 it reads "Partly spent" and a ''transfer'' customer change is refused (the count is of lots)', p.invoice_id, count(*)
--         from pre p
--        where not p.spent and p.lot_status = 'active' and p.remaining_amount > 0 and p.remaining_amount = p.original_amount
--          and exists (select 1 from pre q where q.invoice_id = p.invoice_id and q.invoice_item_id = p.invoice_item_id and q.spent)
--        group by p.invoice_id
--       union all
--       select '3 for the Owner (not changed by 473: NOT COVERED 1): a package paid in part, not settled, whose released credit was spent with nothing left on its lots and more still to be released: a ''transfer'' change passes, and the next payment''s credit goes to the invoice''s customer, ''transfer'' or ''keep'' (the count is of lines)', p.invoice_id, count(distinct p.invoice_item_id)
--         from pre p
--         join public.invoice_items it on it.id = p.invoice_item_id and it.credit_issued_at is null
--        where p.spent
--          and not exists (select 1 from pre q where q.invoice_id = p.invoice_id and q.invoice_item_id = p.invoice_item_id
--                           and q.lot_status = 'active' and q.remaining_amount > 0)
--          and public.credit_line_paid_entitlement(p.invoice_item_id) > public.credit_package_released_paid_credit(p.invoice_item_id)
--        group by p.invoice_id
--       union all
--       select '4 for the Owner (not changed by 473: NOT COVERED 2 and 6): a package line whose credit is held by more than one customer (a ''transfer'' change before 473 moved the untouched part of a partly spent package, or a ''keep'' change left the released part with the buyer and gave the rest to the new customer): a data fix, or left as it is (the count is of lines)', x.invoice_id, count(*)
--         from (select r.invoice_id, r.invoice_item_id from r group by 1, 2 having count(distinct r.customer_id) > 1
--               union
--               select p.invoice_id, p.invoice_item_id from pre p
--                group by 1, 2 having count(distinct p.customer_id) > 1) x
--        group by x.invoice_id)
--     select f.reason, i.invoice_no, f.n
--       from found f join public.invoices i on i.id = f.invoice_id
--      order by f.reason, i.invoice_no
--      (The suite runs this same text on its cases' states before 473 and
--      checks what it lists.)
--   2. Dry run on a copy of production as it is then (471, then 472 applied
--      to it): work out its fingerprint and grant list first (they must be
--      the BEFORE figures below, or be worked out again on that copy); apply
--      this file twice; the first run ends at the AFTER fingerprint below,
--      the second changes nothing ("left alone"); and the suite, with the
--      earlier suites below.
--   3. Apply (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself.
--   4. No page change goes with it (NOT CHANGED).
--   Afterwards (checked on copies of production at 471 with 472 in, 26 Oct
--   2026): a re-run of 471 or 472 refuses (their pin of the list), changing
--   nothing; 473's own leaves all alone. The suites that read the list
--   where 473 is in (-v nomig=1): plain-cancelled-package-credit-471 (KNOWN
--   K9 checked as 473 settles it: TQ refused "Paid credit 60.00 (Partly
--   spent)"; PTRh and PTRhp, which make such a change, end refused at it,
--   and its P10 reads PTRhp's forwarding on PTRhc, the change made while
--   cancelled), reversed-lot-credit-held-back-472 (R328c refused at its
--   change; R328cc, added, makes it while cancelled and ends as R328c did),
--   customer-change-refunded-461 (10), move-merge-leftovers-462 and
--   change-store-moves-bundle-vouchers-463 (S), by 473's AFTER md5 or its
--   text. function-grants is unchanged (nothing is added).
--
-- BEFORE (production at 471 with 472 in, 26 Oct 2026; md5 of
-- pg_get_functiondef with search_path public)
--   changed
--   invoice_transferable_benefits(uuid)                                68736a39ed765ee787242bc62bbaeebb  (463's)
--   relied on, not changed (pinned)
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                        04d647e13e9424a9375942e5812e91a2
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)             c01606c84ee13ddcd88c15521d6d9aed
--   preview_invoice_correction(uuid,jsonb)                             f26752231c100461e11caddc03c98a33
--   invoice_benefit_unused_elsewhere(uuid)                             d35d7c8ae7187985ea64f8a5c38a7d79
--   invoice_benefit_moved_to_other(uuid)                               7016bed898e1bbe9d0ac4a05037d07c2
--   invoice_benefit_moved_from_spent(uuid)                             901fde963b051cfd93fcd9f7dab7149e
--   invoice_credit_lot_ids(uuid)                                       50346a2e9aea50b31d4207c43b2f197c
--   credit_lot_chain(uuid)                                             556e725784154cbffc23d3ad900f9366
--   credit_lot_current(uuid)                                           d48fb24e6eb9733d7f867e42fa703e7b
--   require_store_access(uuid)                                         f9332fd2f0092337d64501d8a647c23f
--   invoice_own_voucher_ids(uuid)                                      ee0202627b9500dcbad103d3ade2401f
--   entitlement_claimed_qty(uuid)                                      89b08265d5303e890569e953d83d2440
--   capture_invoice_benefit_values(uuid)                               d5e061945c2921a1af86f8c99a349e98
--   record_invoice_benefit_values(uuid,jsonb,text)                     931af0352136ab39689af21a993f67b3
--   release_credit_package_paid_credit(uuid)                           530521c100163445e5a0b99799fbcccc
--   credit_package_released_paid_credit(uuid)                          6b27388462747e3c13f3da0b9ad165c0
--   trim_released_paid_credit(uuid,text,boolean)                       14ded4342c3e65eb98547d224263519f
--   writeoff_released_credit_on_close(uuid,text,text)                  284a89cfb965e8028136b5f8a4f2bf08
--   repair_credit_package_progress_lots()                              ebd2a1a9f8ce7a9c1c272168b30b5ce3
--   reclaim_released_credit_of_removed_lines(uuid,jsonb,text)          823cd6a96c813b43bf2767dc1644e943
--   transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)          7aebd7120bc3928db46df0941cb20889
--   merge_customer_records(uuid,uuid,text,uuid)                        ba05c2b1fb4c0e14d369c01d06a635b0
--   credit_given_back_follows(uuid)                                    f2a7a4d1ca28f0865b14e3f1e5e02bbb  (472's AFTER)
--   cancel_invoice_recorded(uuid,text,uuid)                            de52d9dbaef8ab15163bef35cb9d733d
--   reopen_invoice(uuid,text,uuid)                                     0ff61e4ead121c198ea7f90a7fc78274
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)          804ecd829cfecf713783a09a05d93c7e
--   apply_reopened_invoice_benefits()                                  36eaa7224e514d3e7e42e3eeb51acfb5
--   apply_reopened_invoice_vouchers()                                  6684840544d1ad8a28e2415934300054
--   correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)          af99337094edb6d73b9cc0ae00fbf138
--   reverse_credit_lot(uuid,text,text,text)                            10c1a3d8e3bb003fbaf01cf879f97c5e
--   trg_create_therapy_on_paid()                                       012ae4e305b9870fa5596f740c0427b9
--   give_raised_voucher_units(uuid,uuid[],boolean,text)                84d4c7bbd39a754d61cbe4f778777a33
--   issue_promotion_vouchers_for_invoice(uuid)                         e47e5f623b1fa3f6eafe83086f0c9776
--   issue_sold_vouchers_for_invoice(uuid)                              0dbb4bc74411b6d4f0535f661a8c09ee
--   trg_event_vip_refund_vouchers()                                    f4ccb7ac32b395bda577169ad1e4f484
--   trg_issue_sold_vouchers_on_paid()                                  cf0b5610b77edfea2683751d5c25ca1d
--   credit_line_paid_entitlement(uuid)                                 da2404a1db281b46a44231bd071a069a
--   public function fingerprint, production now (471)                  fd61e1a11dce76dd9ad4348f6bb99180 (1387 functions; head 20261026142140)
--   public function fingerprint, 471 -> 472 (472's AFTER, on a copy)   84308fd1c3570babf682c472bd6f95b2 (1387 functions)
--   grant list (string_agg(signature '=' proacl, '|'), sorted)          381ef69cb44f960ff981585ff8402fa1 (production lists the same
--                                                                      grants in another order: compare as sets)
-- AFTER (for later guards)
--   invoice_transferable_benefits(uuid)                                a2332a22fe9975667e848de0d1e4480b  (grants kept: authenticated, the service role)
--   public function fingerprint, worked out on a copy of production at 471 with 472 applied (26 Oct 2026; a second run the same):
--     production now (471) -> 472 -> 473                               eb7399d17225fcc55142a773e35b12b6 (1387 functions: none added, none dropped)
--   grant list after 473                                               381ef69cb44f960ff981585ff8402fa1 (unchanged)
--
-- Test: scripts/invoices/tests/part-paid-package-change-partly-spent-473.sql
-- (begin ... rollback; it installs this file twice; -v nomig=1 where it is
-- in). It reproduces K9 (TQ) and its siblings first (paid in part and paid
-- in full since, with or without a cancel; a second change; a 'keep' first;
-- the Premium Bundle and the Bonus package; the buyer merged or changed
-- before; a Move to the same customer at another store; an Owner's
-- reversal; paid in part twice, not settled), then checks the header's
-- query (1 to 4), the refusals, the install, every case after 473 with
-- 462's invariants (471's reading of them, the lots a release record's chain
-- reaches counting as named) and Cancel, the list's rows and the correction
-- summary's blocked items, the paid-in-full controls exactly as before (and
-- a merge, a Move to someone else, refunds paid back, a package nothing was
-- spent from, the cancelled package), cases begun before 473 and finished
-- after, and NOT COVERED 1 to 3, 5 and 6 as KNOWN. Each app call is followed
-- by what its commit does (462's trigger is deferred). Fixtures only (the
-- repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The function this changes: BEFORE (production, 26 Oct 2026: 463's
  -- AFTER, as 471 and 472 pinned it) and AFTER md5s; who may call it, as
  -- read (kept) ═══════════════════════════════════════════════════════════
  c_sig constant text := 'invoice_transferable_benefits(uuid)';
  c_before constant text := '68736a39ed765ee787242bc62bbaeebb';
  c_after constant text := 'a2332a22fe9975667e848de0d1e4480b';
  c_acl constant text := '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}';

  -- ══ The whole text (exactly as the database prints it back) ═════════════
  c_def_list constant text := $d1$CREATE OR REPLACE FUNCTION public.invoice_transferable_benefits(p_invoice_id uuid)
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
           and (w.untouched or coalesce(u.moves, false)) and not s.spent_before
           and not ls.line_spent,   -- 473
         l.remaining_amount > 0 and (not w.untouched and not coalesce(u.moves, false) or s.spent_before
                                     or ls.line_spent),   -- 473
         case when l.remaining_amount = 0 and u.unspent and u.refunded then 'Refunded; nothing is left to move'
              when l.remaining_amount = 0 then 'Fully spent; it stays with the original customer'
              when not w.untouched and not coalesce(u.moves, false) or s.spent_before
                   or ls.line_spent then 'Partly spent'   -- 473
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
$d1$;

  -- ══ Relied on, not changed (production at 471 with 472 in, 26 Oct 2026):
  -- what the list calls; who calls it and reads its flags; what writes the
  -- benefit rows, the release record and its lots, an Owner's Move, a merge
  -- (the lots and rows the list reads), and 472's forwarder ═══════════════
  c_relied constant text[] := array[
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'move_invoice_benefits_to_customer(uuid,uuid,uuid,text)',
    'preview_invoice_correction(uuid,jsonb)',
    'invoice_benefit_unused_elsewhere(uuid)',
    'invoice_benefit_moved_to_other(uuid)',
    'invoice_benefit_moved_from_spent(uuid)',
    'invoice_credit_lot_ids(uuid)',
    'credit_lot_chain(uuid)',
    'credit_lot_current(uuid)',
    'require_store_access(uuid)',
    'invoice_own_voucher_ids(uuid)',
    'entitlement_claimed_qty(uuid)',
    'capture_invoice_benefit_values(uuid)',
    'record_invoice_benefit_values(uuid,jsonb,text)',
    'release_credit_package_paid_credit(uuid)',
    'credit_package_released_paid_credit(uuid)',
    'trim_released_paid_credit(uuid,text,boolean)',
    'writeoff_released_credit_on_close(uuid,text,text)',
    'repair_credit_package_progress_lots()',
    'reclaim_released_credit_of_removed_lines(uuid,jsonb,text)',
    'transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)',
    'merge_customer_records(uuid,uuid,text,uuid)',
    'credit_given_back_follows(uuid)',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'reopen_invoice(uuid,text,uuid)',
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'apply_reopened_invoice_benefits()',
    'apply_reopened_invoice_vouchers()',
    'correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)',
    'reverse_credit_lot(uuid,text,text,text)',
    'trg_create_therapy_on_paid()',
    'give_raised_voucher_units(uuid,uuid[],boolean,text)',
    'issue_promotion_vouchers_for_invoice(uuid)',
    'issue_sold_vouchers_for_invoice(uuid)',
    'trg_event_vip_refund_vouchers()',
    'trg_issue_sold_vouchers_on_paid()',
    'credit_line_paid_entitlement(uuid)'];
  c_relied_md5 constant text[] := array[
    '04d647e13e9424a9375942e5812e91a2',
    'c01606c84ee13ddcd88c15521d6d9aed',
    'f26752231c100461e11caddc03c98a33',
    'd35d7c8ae7187985ea64f8a5c38a7d79',
    '7016bed898e1bbe9d0ac4a05037d07c2',
    '901fde963b051cfd93fcd9f7dab7149e',
    '50346a2e9aea50b31d4207c43b2f197c',
    '556e725784154cbffc23d3ad900f9366',
    'd48fb24e6eb9733d7f867e42fa703e7b',
    'f9332fd2f0092337d64501d8a647c23f',
    'ee0202627b9500dcbad103d3ade2401f',
    '89b08265d5303e890569e953d83d2440',
    'd5e061945c2921a1af86f8c99a349e98',
    '931af0352136ab39689af21a993f67b3',
    '530521c100163445e5a0b99799fbcccc',
    '6b27388462747e3c13f3da0b9ad165c0',
    '14ded4342c3e65eb98547d224263519f',
    '284a89cfb965e8028136b5f8a4f2bf08',
    'ebd2a1a9f8ce7a9c1c272168b30b5ce3',
    '823cd6a96c813b43bf2767dc1644e943',
    '7aebd7120bc3928db46df0941cb20889',
    'ba05c2b1fb4c0e14d369c01d06a635b0',
    'f2a7a4d1ca28f0865b14e3f1e5e02bbb',
    'de52d9dbaef8ab15163bef35cb9d733d',
    '0ff61e4ead121c198ea7f90a7fc78274',
    '804ecd829cfecf713783a09a05d93c7e',
    '36eaa7224e514d3e7e42e3eeb51acfb5',
    '6684840544d1ad8a28e2415934300054',
    'af99337094edb6d73b9cc0ae00fbf138',
    '10c1a3d8e3bb003fbaf01cf879f97c5e',
    '012ae4e305b9870fa5596f740c0427b9',
    '84d4c7bbd39a754d61cbe4f778777a33',
    'e47e5f623b1fa3f6eafe83086f0c9776',
    '0dbb4bc74411b6d4f0535f661a8c09ee',
    'f4ccb7ac32b395bda577169ad1e4f484',
    'cf0b5610b77edfea2683751d5c25ca1d',
    'da2404a1db281b46a44231bd071a069a'];
  -- Who calls the list; who writes benefit rows, the release record and an
  -- Owner's Move (by name; a session's own temporary functions and the list
  -- itself are not counted), as read on production at 471 with 472 in.
  c_callers constant text := 'correct_invoice(uuid,jsonb,jsonb,text,uuid), move_invoice_benefits_to_customer(uuid,uuid,uuid,text), preview_invoice_correction(uuid,jsonb)';
  c_row_writers constant text := 'apply_reopened_invoice_benefits(), apply_reopened_invoice_vouchers(), cancel_invoice_recorded(uuid,text,uuid), capture_invoice_benefit_values(uuid), correct_invoice(uuid,jsonb,jsonb,text,uuid), credit_given_back_follows(uuid), give_raised_voucher_units(uuid,uuid[],boolean,text), issue_promotion_vouchers_for_invoice(uuid), issue_sold_vouchers_for_invoice(uuid), merge_customer_records(uuid,uuid,text,uuid), move_invoice_benefits_to_customer(uuid,uuid,uuid,text), record_invoice_benefit_values(uuid,jsonb,text), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid), trg_event_vip_refund_vouchers(), trg_issue_sold_vouchers_on_paid()';
  c_release_writers constant text := 'credit_given_back_follows(uuid), release_credit_package_paid_credit(uuid), repair_credit_package_progress_lots(), trim_released_paid_credit(uuid,text,boolean), writeoff_released_credit_on_close(uuid,text,text)';
  c_move_writers constant text := 'transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; n int; i int; v_first boolean; v_acl text;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_pk uuid; t_svc uuid; t_wallet uuid;
  t_case int; t_a uuid; t_b uuid; t_inv uuid; t_s uuid; t_k int; t_err text; t_want text; t_rows text;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The text is the tested one.
  if md5(c_def_list) <> c_after then
    raise exception '473: the text in this file is not the tested one'; end if;

  -- The functions relied on are as read on production (at 471 with 472 in,
  -- 26 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '473: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying (473 goes in after 472).',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;

  -- The columns read, with these types.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('customer_credit_lots', 'id', 'uuid'), ('customer_credit_lots', 'customer_id', 'uuid'),
                 ('customer_credit_lots', 'category', 'text'), ('customer_credit_lots', 'status', 'text'),
                 ('customer_credit_lots', 'original_amount', 'numeric(12,2)'), ('customer_credit_lots', 'remaining_amount', 'numeric(12,2)'),
                 ('customer_credit_lots', 'reassigned_from_lot_id', 'uuid'),
                 ('invoice_benefit_values', 'id', 'uuid'), ('invoice_benefit_values', 'invoice_id', 'uuid'),
                 ('invoice_benefit_values', 'invoice_item_id', 'uuid'), ('invoice_benefit_values', 'lot_id', 'uuid'),
                 ('invoice_benefit_values', 'granted_value', 'numeric(12,2)'), ('invoice_benefit_values', 'cancelled_unused_value', 'numeric(12,2)'),
                 ('credit_package_progress_lots', 'lot_id', 'uuid'), ('credit_package_progress_lots', 'invoice_id', 'uuid'),
                 ('credit_package_progress_lots', 'invoice_item_id', 'uuid'), ('credit_package_progress_lots', 'released_amount', 'numeric(12,2)'),
                 ('invoice_benefit_transfers', 'source_benefit_id', 'uuid'), ('invoice_benefit_transfers', 'replacement_benefit_id', 'uuid')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '473: these columns are missing or not as read on 26 Oct 2026: %', v; end if;
  -- A lot is 'active' or 'reversed' (what the release test reads as holding).
  if not exists (select 1 from pg_constraint where conrelid = 'public.customer_credit_lots'::regclass and contype = 'c'
                  and pg_get_constraintdef(oid) = 'CHECK ((status = ANY (ARRAY[''active''::text, ''reversed''::text])))') then
    raise exception '473: a credit lot''s statuses are not as read on 26 Oct 2026'; end if;

  -- No other function takes the name (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'invoice_transferable_benefits'
     and p.oid::regprocedure::text <> c_sig;
  if v is not null then raise exception '473: another function takes the name of the one this changes: %', v; end if;

  -- Who calls the list; who writes benefit rows, the release record and an
  -- Owner's Move: as read (a new way would need the same care).
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'invoice_transferable_benefits\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'invoice_transferable_benefits';
  if v is distinct from c_callers then
    raise exception '473: the functions that call invoice_transferable_benefits are not as read on 26 Oct 2026 (%); check how each reads its flags, then re-test', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* '(insert\s+into|update)\s+public\.invoice_benefit_values' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_row_writers then
    raise exception '473: what writes invoice_benefit_values is not as read on 26 Oct 2026 (%); check which line a row names, then re-test', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* '(insert\s+into|update)\s+public\.credit_package_progress_lots' and ns.nspname not like 'pg\_temp\_%';
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* '(insert\s+into|update)\s+public\.invoice_benefit_transfers' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_release_writers or d is distinct from c_move_writers then
    raise exception '473: what writes the release record of credit released before full payment, or an Owner''s Move, is not as read on 26 Oct 2026 (% / %); check what the record still counts as released, then re-test', v, d; end if;

  -- The function: its BEFORE (replaced) or its AFTER (left alone).
  d := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  if md5(d) = c_after then
    raise notice '473: public.% is already this version; left alone', c_sig;
    v_first := false;
  elsif md5(d) = c_before then
    v_first := true;
  else
    raise exception '473: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig, md5(d);
  end if;

  -- ── On the first run: nothing is refused for the data (473 needs no
  -- decision before it goes in), but whose answer changes and what needs the
  -- Owner is named (the header's read-only query: 1 and 2, a 'transfer'
  -- customer change now refused as "Partly spent"; 3 and 4, for the Owner).
  if v_first then
    with
    r as (
      select b.id, b.invoice_id, b.invoice_item_id, l.customer_id, l.category, l.status as lot_status,
             l.remaining_amount, l.original_amount, l.reassigned_from_lot_id, b.cancelled_unused_value,
             l.remaining_amount + b.cancelled_unused_value + public.invoice_benefit_unused_elsewhere(b.id) < b.granted_value as spent,
             i.status::text in ('cancelled', 'refunded')
             or exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = i.id and q.applied_at is null) as held
        from public.invoice_benefit_values b
        join public.customer_credit_lots l on l.id = b.lot_id
        join public.invoices i on i.id = b.invoice_id and i.deleted_at is null
       where not public.invoice_benefit_moved_to_other(b.id)),
    sl as (
      select r.invoice_id, r.invoice_item_id, r.category from r group by 1, 2, 3 having bool_or(r.spent)),
    pre as (
      select pl.invoice_id, pl.invoice_item_id, pl.lot_id, c.customer_id, c.remaining_amount, c.original_amount, c.status as lot_status,
             pl.released_amount > 0 and coalesce(case when c.status = 'active' then c.remaining_amount end, 0) < pl.released_amount as spent
        from public.credit_package_progress_lots pl
        join public.invoices i on i.id = pl.invoice_id and i.deleted_at is null
        join public.customer_credit_lots c on c.id = public.credit_lot_current(pl.lot_id)
       where not exists (select 1 from public.invoice_benefit_values bv where bv.lot_id = any (public.credit_lot_chain(pl.lot_id)))),
    found(reason, invoice_id) as (
      select 1, r.invoice_id
        from r join sl using (invoice_id, invoice_item_id, category)
       where not r.spent and r.lot_status = 'active' and r.remaining_amount > 0
         and (r.remaining_amount = r.original_amount and r.reassigned_from_lot_id is null
              or r.cancelled_unused_value = 0 and not r.held)
         and not public.invoice_benefit_moved_from_spent(r.id)
         and not exists (select 1 from r r2 where r2.invoice_id = r.invoice_id and r2.spent
                          and r2.lot_status = 'active' and r2.remaining_amount > 0)
      union
      select 2, p.invoice_id from pre p
       where not p.spent and p.lot_status = 'active' and p.remaining_amount > 0 and p.remaining_amount = p.original_amount
         and exists (select 1 from pre q where q.invoice_id = p.invoice_id and q.invoice_item_id = p.invoice_item_id and q.spent)
      union
      select 3, p.invoice_id from pre p
        join public.invoice_items it on it.id = p.invoice_item_id and it.credit_issued_at is null
       where p.spent
         and not exists (select 1 from pre q where q.invoice_id = p.invoice_id and q.invoice_item_id = p.invoice_item_id
                          and q.lot_status = 'active' and q.remaining_amount > 0)
         and public.credit_line_paid_entitlement(p.invoice_item_id) > public.credit_package_released_paid_credit(p.invoice_item_id)
      union
      select 4, x.invoice_id
        from (select r.invoice_id, r.invoice_item_id from r group by 1, 2 having count(distinct r.customer_id) > 1
              union
              select p.invoice_id, p.invoice_item_id from pre p
               group by 1, 2 having count(distinct p.customer_id) > 1) x)
    select string_agg(format('%s: %s invoice(s) (%s)', f.reason, f.n, f.nos), '; ' order by f.reason) into v
      from (select f.reason, count(*) as n, string_agg(i.invoice_no, ', ' order by i.invoice_no) as nos
              from found f join public.invoices i on i.id = f.invoice_id group by f.reason) f;
    if v is not null then
      raise notice '473: the header''s query lists %: 1 and 2, a ''transfer'' customer change of a partly spent package paid in part is now refused as "Partly spent"; 3 and 4 are for the Owner (NOT COVERED 1, 2 and 6), not changed by 473', v;
    end if;
  end if;

  -- Who may call it, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig))
     is distinct from (select array_agg(x::text order by x::text) from unnest(c_acl::aclitem[]) x) then
    raise exception '473: who may call public.% is not as read on 26 Oct 2026 (%)', c_sig,
      (select proacl::text from pg_proc where oid = to_regprocedure('public.' || c_sig)); end if;
  v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig));

  -- ── Change ──────────────────────────────────────────────────────────────
  if v_first then
    execute c_def_list;
  end if;

  -- ── Afterwards: installed exactly as tested, grants as before ───────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_after then
    raise exception '473: public.% is not at its AFTER md5 (%)', c_sig, md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))); end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig)) is distinct from v_acl then
    raise exception '473: the grants of public.% changed', c_sig; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("473 check", @example.invalid, fictional ACMA
  -- phones no customer uses); it ends by raising P0473, which undoes all it
  -- wrote. 462's trigger runs at commit; here at each step's end (SET
  -- CONSTRAINTS ... IMMEDIATE), as a commit would.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from generate_series(800, 899) g, lateral (select '+61491570' || g::text as p) x
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p desc limit 10);
    if coalesce(cardinality(t_phones), 0) < 10 then raise exception '473: the self-test found no ten unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '473-check-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '473 check', '473-check-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('473 check ' || t_sfx, '473-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('473 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy, grants_reward)
    values ('473 check ' || t_sfx, 100, 100, false, true, true, false) returning id into t_pk;
    insert into public.credit_package_stores (package_id, store_id) values (t_pk, t_store);
    insert into public.therapy_services (service_code, name, standard_price, duration_minutes, is_active)
    values ('473-' || t_sfx, '473 check ' || t_sfx, 20, 30, true) returning id into t_svc;
    insert into public.therapy_service_stores (service_id, store_id, is_available) values (t_svc, t_store, true);
    select pm.id into t_wallet from public.payment_methods pm
     where pm.name = 'Wallet — Credit Package Paid' and pm.is_wallet_credit and pm.deleted_at is null;
    if t_wallet is null then raise exception '473: the wallet method "Wallet — Credit Package Paid" (443) is not there'; end if;

    for t_case in 1 .. 5 loop
      -- The package sold to A: (a), (b), (d) S$40 paid (S$40 of its credit
      -- released); (c) S$20; (e) paid in full.
      insert into public.customers (full_name, phone) values ('473 Check Buyer ' || t_case || ' ' || t_sfx, t_phones[2 * t_case - 1]) returning id into t_a;
      insert into public.customers (full_name, phone) values ('473 Check Holder ' || t_case || ' ' || t_sfx, t_phones[2 * t_case]) returning id into t_b;
      t_inv := public.create_invoice(t_store, t_a, null::uuid,
        jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
      perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
        'amount', case t_case when 3 then 20 when 5 then 100 else 40 end)), gen_random_uuid());
      -- Sessions of S$20 paid from it: two in (a), (b), (e); one in (c); none in (d).
      for t_k in 1 .. (case t_case when 3 then 1 when 4 then 0 else 2 end) loop
        t_s := public.create_invoice(t_store, t_a, null::uuid,
          jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 1)),
          0::numeric, null::text, null::uuid, '[]'::jsonb);
        perform public.record_invoice_payment(t_s, jsonb_build_array(jsonb_build_object('payment_method_id', t_wallet, 'amount', 20)), gen_random_uuid());
      end loop;
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      if t_case = 1 then
        -- (a) cancelled (the released lot closed), reopened, then paid in full.
        perform public.cancel_invoice_recorded(t_inv, '473 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        perform public.reopen_invoice(t_inv, '473 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
      end if;
      if t_case = 3 then
        -- (c) S$20 more paid: S$20 released again, on a lot of its own.
        perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 20)), gen_random_uuid());
      elsif t_case <> 5 then
        perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
          'amount', (public.invoice_financial_position(t_inv)->>'outstanding')::numeric)), gen_random_uuid());
      end if;
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      if (select status::text from public.invoices where id = t_inv) <> (case t_case when 3 then 'partially_paid' else 'paid' end)
         or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a)
            <> (case t_case when 3 then 20 when 4 then 100 else 60 end) then
        raise exception '473: (%) the package was not set up as meant (status %, A holds %)', chr(96 + t_case),
          (select status::text from public.invoices where id = t_inv),
          (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a); end if;
      -- What the list says of its credit holding credit.
      select string_agg(x.description || ':' || x.movable || ':' || x.blocking || ':' || coalesce(x.blocked_reason, '-'), ', ' order by x.description)
        into t_rows from public.invoice_transferable_benefits(t_inv) x where x.kind = 'credit' and x.units > 0;
      t_want := case t_case when 3 then 'Paid credit 20.00:false:true:Partly spent'
                            when 4 then 'Paid credit 40.00:true:false:-, Paid credit 60.00:true:false:-'
                            else 'Paid credit 60.00:false:true:Partly spent' end;
      if t_rows is distinct from t_want then
        raise exception '473: (%) the list reads % (wanted %)', chr(96 + t_case), t_rows, t_want; end if;
      -- The invoice form's customer change to B, 'transfer'.
      t_err := null;
      begin
        perform public.correct_invoice(t_inv,
          (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
                    'credit_package_id', it.credit_package_id, 'quantity', it.quantity, 'unit_price', it.unit_price)) order by it.id)
             from public.invoice_items it where it.invoice_id = t_inv),
          jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = t_inv),
            'customer_id', t_b, 'store_id', t_store, 'benefit_action', 'transfer'),
          '473 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
      exception when sqlstate 'P0001' then t_err := sqlerrm;
      end;
      if t_case = 4 then
        -- (d) nothing spent: the change moves it all to B, as before.
        if t_err is not null
           or (select customer_id from public.invoices where id = t_inv) <> t_b
           or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_b) <> 100
           or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> 0 then
          raise exception '473: (d) the change of a package nothing was spent from did not move it to B (%)', coalesce(t_err, 'no refusal'); end if;
      else
        -- (a), (b), (c), (e) refused as "Partly spent", with the words of the
        -- package paid in full; nothing moved.
        if t_err is null
           or t_err not like 'These benefits have already been used and cannot move with the invoice: '
                             || (case t_case when 3 then 'Paid credit 20.00' else 'Paid credit 60.00' end) || ' (Partly spent).%'
           or (select customer_id from public.invoices where id = t_inv) <> t_a
           or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_b) <> 0
           or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a)
              <> (case t_case when 3 then 20 else 60 end) then
          raise exception '473: (%) the change of a partly spent package was not refused as "Partly spent" (%)', chr(96 + t_case), coalesce(t_err, 'no refusal'); end if;
      end if;
    end loop;
    raise exception using errcode = 'P0473', message = '473: self-test done, undone';
  exception when sqlstate 'P0473' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
