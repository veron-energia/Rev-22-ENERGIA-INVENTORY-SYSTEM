-- 461_refunded_credit_is_not_spent_for_customer_change.sql
--
-- CREDIT A LINE REFUND PAID BACK IS NOT "SPENT" WHEN AN INVOICE'S CUSTOMER IS
-- CHANGED: A PARTLY REFUNDED CREDIT LOT MOVES WITH THE BENEFITS, A WHOLLY
-- REFUNDED ONE READS "REFUNDED" (the Owner, 22 Oct 2026: "fix the other two
-- rare gaps too"; 448's NOT COVERED 3)
--
-- WHO FOUND IT
--
--   Found while 448 was built (22 Oct 2026), written up as 448's NOT COVERED
--   3 and checked as KNOWN by its suite
--   (scripts/invoices/tests/refunded-units-not-used-448.sql, case 8 (3)).
--   Reproduced for this file on 23 Oct 2026 on a copy of production as it is
--   now (b43a0781, 1372 functions: 452 to 455 in), with made-up records,
--   through the app's own calls only: the invoice form and the Pay dialog
--   (create_invoice_with_details, record_invoice_settlement), the Finance
--   panel's refund by line (refund_invoice_recorded with the line's
--   benefits), the guided Refund in full and Cancel (invoice_action_plan,
--   request_invoice_action_v2, resolve_invoice_action_v2), Cancel, Reopen,
--   Record Payment, Move, a customer merge, and the invoice form's customer
--   change (correct_invoice with benefit_action 'transfer' or 'keep', the
--   list it is offered from, invoice_transferable_benefits, and its summary,
--   preview_invoice_correction).
--   The review of this file (23-24 Oct 2026, on copies of production with
--   461 alone and with 460) found that the first draft moved a lot something
--   else still had a claim on, and that it refused to install after 460; the
--   claims are listed under WHAT THIS DOES (each a suite control, K11 to
--   K14 and CW), the install order under DEPLOY ORDER.
--
-- WHAT WAS WRONG
--
--   The customer change's list (invoice_transferable_benefits, 321; last
--   406) reads a credit lot by its own two figures only: what it holds equal
--   to what it was granted moves, less blocks the change as "Partly spent",
--   nothing reads "Fully spent; it stays with the original customer". A line
--   refund (the Finance panel's refund by line, the guided Refund in full)
--   takes the credit it pays back off the lot, so a lot partly refunded read
--   as partly spent and one a refund emptied as spent, although none of it
--   was spent (448 decided this for the cancel plans: credit a line refund
--   paid back is not spent). The move itself (move_invoice_benefits_to_
--   customer, 321; last 447) moves only a lot holding all it was granted. On
--   the copy:
--   * a S$100 Credit Package with a S$10 Bonus, paid, S$40 of its Paid
--     benefit refunded by line (S$44 of credit taken back, S$56 left): the
--     summary listed "Paid credit 56.00 — Partly spent" under "Needs
--     attention first", and saving was refused: "These benefits have already
--     been used and cannot move with the invoice: Paid credit 56.00 (Partly
--     spent). Resolve each one through the benefit transfer review before
--     reassigning." The same for a Premium Bundle's Paid credit (S$52 left
--     of S$100), and for the Paid and the Bonus both partly refunded (both
--     blocked);
--   * two such packages, line A wholly refunded by line, or one package
--     refunded S$40 by line and then in full (the guided Refund in full):
--     the emptied lots were listed "Fully spent; it stays with the original
--     customer" (the change went through: nothing is left on them). No page
--     shows that label (the summary lists what moves and what blocks only).
--   Nothing was given or kept wrongly: the change was refused, so nothing
--   moved. The only way through was to change the customer and keep the
--   benefits with whoever held them ('keep'), leaving the credit with the
--   earlier customer (SAFETY: the file stops if that has happened).
--   Vouchers: no such mislabel. A line refund lowers the held voucher's
--   units (the units left move, as before) or revokes it ("Already revoked;
--   it stays with the original customer", which says what happened), and a
--   voucher never blocks the change. Nothing changed for them.
--   Production, 22 Oct 2026 (counts only): 3 customer changes took benefits
--   along, 1 voucher each and no credit lot; no lot was ever reassigned
--   (reassigned_from_lot_id 0). So nothing to repair. The query under DEPLOY
--   ORDER lists, read only, every invoice whose list this changes.
--
-- THE OWNER'S ANSWER (22 Oct 2026)
--
--   "Fix the other two rare gaps too". The rule: credit a line refund paid
--   back is not spent (as 448 decided for the cancel plans). A lot that is
--   partly refunded and not spent moves its remaining credit with a customer
--   change that takes the benefits along, exactly as an untouched lot does
--   (keeping its origin, as 447 does). A wholly refunded lot is shown as
--   refunded with nothing to move, never as spent. A lot with real spending
--   keeps today's rule (blocked as partly spent, or fully spent). The same
--   for vouchers if they had the mislabel (they do not: above).
--
-- WHAT THIS DOES (two functions patched at one anchor each; no table, row,
-- grant or other function changes)
--
--   * invoice_transferable_benefits(uuid): its credit rows. A lot is spent
--     when what it holds, what a cancellation took back
--     (cancelled_unused_value) and what is not used although it is no longer
--     on it (448's invoice_benefit_unused_elsewhere: what a line refund paid
--     back, what an Owner moved) come to less than its benefit row granted:
--     the test cancelled_invoice_used_value and invoice_action_plan make
--     (448), called, not copied. A lot one of this invoice's benefit rows
--     names, partly drawn down and not spent, is listed as moving (not
--     blocking, no reason) when nothing else holds a claim on it:
--     - no cancellation still holds credit back for it (the row's
--       cancelled_unused_value is 0): a reopening's payment puts what a
--       cancellation holds back on the lot it was taken from, so a moved lot
--       would be given it twice, once by the move and once by the payment
--       (the review: S$30 spent on a session, Cancel with the credit_used
--       override and the due not recorded, the session refunded, the
--       customer changed, reopened, Refund in full: S$100 paid back and the
--       first customer kept S$70 of Paid credit);
--     - no reopening of the invoice waits to give credit back
--       (invoice_reopen_benefits not yet applied), for the same reason
--       (S$40 refunded by line, the S$56 left spent on a session, Cancel
--       with credit_used and the due recorded, reopened, the session
--       refunded: S$56 back on the lot while the reopening waits; changed
--       and paid, the payment put the S$44 refunded and the S$10 Bonus back
--       on the first customer's lots, and Refund in full asked credit_used
--       and paid back S$60 of the S$100);
--     - no Owner moved the row's benefit (Move, invoice_benefit_transfers):
--       447 keeps such a row's records on this lot, so after the change a
--       cancellation or a refund would read the emptied lot and the new
--       customer keep the credit (the review: S$30 spent, the rest moved, the
--       session refunded, changed, Cancel asked credit_used and left the new
--       customer S$30);
--     - the invoice is neither cancelled nor refunded (what its
--       cancellation or refund settled stays as settled).
--     One a refund emptied reads "Refunded; nothing is left to move" (not
--     moving, not blocking), whatever the invoice's status. A lot with real
--     spending, or with one of the claims above, blocks as "Partly spent" or
--     reads "Fully spent" as before 461; so does a lot an Owner moved or a
--     cancellation alone emptied (NOT COVERED 2), and a lot with no benefit
--     row of the invoice (older invoices, credit released before
--     settlement), read by its own figures as before. Its voucher,
--     allowance and therapy rows are unchanged.
--   * move_invoice_benefits_to_customer(uuid,uuid,uuid,text): the lots it
--     moves: a lot holding all it was granted, as before, or one that passes
--     the same test with the same claims left out, each read again once it
--     is locked (so credit spent meanwhile keeps it where it is, as before).
--     What the lot holds moves as 447 moves an untouched lot: drawn to 0 for
--     the earlier customer, granted to the new one as a new lot naming the
--     lot it replaces, with the same origin (source, category, restrictions,
--     store, dates), and the invoice's records (its benefit value, its
--     sale's lots, a shared package's issued lot) name the new lot. The
--     refunded part stays refunded: its refund row stays on the earlier lot,
--     which 448's helper still finds through the new lot (it follows
--     reassigned_from_lot_id), so the plans, a cancellation and a further
--     refund read the moved lot right; the refund options (what can still
--     be refunded) are the same before and after the change.
--   Money, once changed (on the copy): Refund in full pays back the S$60
--   still held and takes the S$66 left from the new customer; Cancel takes
--   it back from the new customer and the S$60 due is recorded by line; a
--   second change moves it again; credit spent at the new customer blocks a
--   second change as partly spent and Cancel asks credit_used for it; a
--   refund after the change comes off the new customer's lot and what is
--   left still moves; credit a refunded session gave back to a lot whose
--   package was otherwise refunded in full (credit_used) moves, and Refund
--   in full then takes it from the new customer and pays back the S$27.27
--   left. Where a claim keeps the change refused, what follows (a reopening
--   and Refund in full, or Cancel) takes everything back from whoever holds
--   it, as before 461.
--
-- NOT CHANGED
--
--   * 448's test and helper (invoice_benefit_unused_elsewhere,
--     cancelled_invoice_used_value, invoice_action_plan), the refund options,
--     refund_invoice_recorded, cancel_invoice_recorded, reopen_invoice and
--     the payments that settle a reopening, Move
--     (transfer_invoice_unused_benefit), the merge (merge_customer_records),
--     correct_invoice and preview_invoice_correction (they read the list's
--     movable and blocking as before).
--   * The pages. The invoice form asks the list only whether the invoice
--     issued benefits (InvoicesPage.tsx); the summary (CorrectionPreview.tsx)
--     prints the server's items and reasons as given; no page has these
--     words. The dialog's note ("Only the unused benefits this invoice
--     issued. Anything already used stays with whoever used it, and a partly
--     used benefit stops the correction for review.") stays true: refunded
--     credit is not used. No page change.
--
-- NOT COVERED (for the Owner; the suite checks 1 and 2 as they are and prints
-- them as KNOWN, and 6's first-run stop as its case 9g)
--
--   1. (446's NOT COVERED 5 and 448's NOT COVERED 2: 460, built beside this,
--      fixes it) A refunded part goes back to the EARLIER customer when the
--      changed invoice is cancelled, reopened and settled: the reopening
--      queues the refund's row, and the payment puts it back on the lot it
--      came from, the earlier customer's emptied one (S$40 refunded,
--      changed, cancelled, reopened, paid: the earlier customer holds S$44
--      of Paid credit, the new one S$56, and Cancel asks credit_used). There
--      before 461 for a line wholly refunded beside another (446's case);
--      since 461 it is reached by a partly refunded lot too, whose change
--      was refused before. With 460 in (either order), the suite checks it
--      the fixed way (FIXED 8 CN). Production, 22 Oct 2026: no credit lot
--      was ever moved by a customer change and no reopening is waiting, so
--      it has not happened. Deploy 460 with 461 (DEPLOY ORDER).
--      The same with an Owner's Move between the change and the cancel (the
--      check of 460 and 461 together, 24 Oct 2026: S$40 refunded, changed,
--      the new customer's S$56 moved to a friend, cancelled, reopened, paid:
--      the S$44 went back on the earlier customer's lot, which no record
--      names, Cancel asked credit_used and its refund due was S$60) is also
--      460's: with 460's text of 24 Oct 2026 the S$44 goes on the new
--      customer's lot the records name, and where what would go back fills
--      that lot or more, counting what of that lot's credit paid for other
--      sales and can still come back onto it (S$55 of credit for S$50
--      refunded; S$44 with S$20 of that lot paid for a session), the
--      reopening is refused (460's NOT COVERED 4; its suite's X9 to X13 and
--      sections 5 and 6, where 461 is in).
--   2. A lot an Owner moved (Move), one refunded and then moved, and one a
--      cancellation alone emptied still read "Fully spent; it stays with the
--      original customer". None was spent, nothing moves either way, and no
--      page shows that reason; not the Owner's rule (refunds), so left.
--   3. A lot partly refunded and not spent that one of the claims above
--      keeps (a cancellation holding credit back, a reopening waiting, an
--      Owner's Move, a cancelled or refunded invoice) still blocks the change
--      as "Partly spent", as before 461, although nothing on it was spent.
--      The safe side: settle the reopening first, or decide with the
--      benefit transfer review. Such a lot needs credit given back to it
--      after the claim was made (a session it paid for refunded, or a
--      reopening settled after a Move).
--   4. A refund recorded before the refund rows of the ledger were written
--      (448's NOT COVERED 4; older engines, if any) cannot be told from
--      spending, so such a lot still blocks as "Partly spent": the safe side.
--   5. A summary already open on a screen when this goes in shows the old
--      answer until the form is opened again; the save checks on the server.
--   6. A shared package (141, older invoices; set_invoice_credit_split, which
--      no page calls): a change taking the benefits along moves every
--      share's credit to the new customer (321; 447's NOT COVERED), and now a
--      partly refunded share's too. Unchanged otherwise; where such a share
--      exists when this is applied, the first run stops (SAFETY).
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * each function is its BEFORE (patched; its anchor found once; the text
--     built has the tested AFTER md5) or its AFTER (left alone), each in one
--     of two tested pairs: at 455 (406's and 447's AFTERs, production on
--     22 Oct 2026) or with 460 in first (460's AFTERs of 23 Oct 2026; 460
--     leaves 461's anchors untouched, and the same patch gives the text 460
--     gives when it goes second); afterwards both functions are in the same
--     pair. So a second run changes nothing, in either order. No other
--     function takes the two names; the functions that call them are as read
--     (the list: correct_invoice, the move and preview_invoice_correction;
--     the move: correct_invoice), by name, not by md5;
--   * the functions it relies on are as read on production (below); 448's
--     helper is there, STABLE, returning numeric, the service role's alone,
--     and the cancel plans still call it in their test (by their text; its
--     md5 and theirs are not pinned); the columns read are there with these
--     types, and an invoice can still be 'cancelled' or 'refunded';
--     invoice_benefit_values has one row per lot (invoice_benefit_lot_unique);
--   * on the first run only (a function at its BEFORE): no invoice carries
--     the gap's footprint: a lot of its benefit rows partly refunded and not
--     spent, with none of the claims above, still active, held by someone
--     other than the invoice's customer. Before 461 such a lot blocked a
--     change taking the benefits along, so it is there because the customer
--     was changed keeping them ('keep'), or it is a shared package's share
--     (141, older invoices; no page makes one), held by its share's customer
--     by design (a change taking the benefits along moves every share, 321).
--     After 461 a later change taking the benefits along would move it from
--     whoever holds it. The file cannot tell a choice from a way round the
--     refusal, so where one exists it stops, changing nothing, and names the
--     invoices: decide where that credit belongs first. (An untouched lot
--     kept, a wholly refunded one, one spent beside a refund, and one a
--     claim keeps are not listed: the suite, 9g and 9h.) A second run skips
--     this;
--   * who may call each is as read (the list: signed-in staff and the service
--     role; the move: the service role alone), compared as sets (production
--     lists them in another order than a local copy), and kept.
--   Afterwards: both md5s are one tested AFTER pair; the grants are as
--   before. Then a self-test, in a block that is always undone (it ends by
--   raising P0461, so it leaves no row): a made-up Owner, store, buyer and
--   friend (fictional ACMA phones no customer has) and a S$100 Credit Package
--   with a S$10 Bonus. (a) Paid, S$40 of its Paid refunded by line: the S$56
--   lot is listed as moving; moved to the friend, both lots move, the
--   friend's lot names the lot it replaces with its origin, the sale names
--   it, Cancel asks no credit_used; cancelled, the friend holds nothing and
--   nothing reads as used. (d) Then credit back on the friend's lot (as a
--   refunded session gives it back) while the cancellation holds S$56 back:
--   "Partly spent", blocking, and the move refuses it. (b) Two packages,
--   line A's benefits wholly refunded: its two lots read "Refunded; nothing
--   is left to move", line B's two move. (c) S$40 refunded and S$10 of the
--   rest spent: "Partly spent", blocking, and the move is refused naming it.
--   (e) S$40 refunded, the rest moved to the friend by an Owner (Move), then
--   credit back on the buyer's lot: "Partly spent", blocking, refused. It
--   calls create_invoice, record_invoice_payment, refund_invoice_recorded,
--   cancel_invoice_recorded and transfer_invoice_unused_benefit without
--   pinning them and checks what they give, so a change that matters stops
--   it. Its credit ledger rows draw entry numbers (a sequence, which an
--   undone transaction does not give back: a gap, which nothing counts), as
--   443's to 448's self-tests do. Locks: the two functions' catalogue rows,
--   to the end of the apply; the rows the self-test writes and undoes. A
--   customer change running at that moment finishes on the text it started
--   with.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (... 451, 452, 453, 454, 455: b43a0781, 1372 functions,
--   head 20261022115409) -> 461. No page, Edge Function or setting changes.
--   * 460 (the other rare gap, built beside this) changes both of 461's
--     functions outside 461's part (the list's vouchers; the move's vouchers
--     and its Audit Log row). Each file accepts the other's text: 461 takes
--     460's AFTERs of 23 Oct 2026 as a second BEFORE (pinned: if 460's text
--     changes again, 461 refuses after it, changing nothing, and its pair is
--     updated); 460 compares these two with 461's part left out. Both orders
--     were installed on copies (23-24 Oct 2026), each file run twice: 461
--     then 460, and 460 then 461, end at the same texts and the same
--     fingerprint, 037095a507480dafd8381a6d3d8add90 with 460's text of 24
--     Oct 2026 (db0a6ec2 with its first draft, 78d539ab with its second,
--     a0679713 with its third; 1374 functions; the list 362d6d07, the move
--     c1827889), grant list
--     acc689cefa349b1ed9588d7d8bb92ce7 (local order; compare as sets), and
--     a second run of either file leaves all alone. 461 pins neither the
--     reopening's functions nor 448's helper nor the cancel plans by md5.
--     NOT COVERED 1 stays open while 461 is in and 460 is not: deploy 460
--     first or together (one after the other, the same day).
--   * 456 to 458 (another session: create_invoice, update_invoice_internal,
--     correct_invoice; rentals following Edit, Refund and Reopen): 461 pins
--     none of those. Its self-test calls create_invoice,
--     record_invoice_payment, refund_invoice_recorded, cancel_invoice_
--     recorded and transfer_invoice_unused_benefit without pinning them, and
--     checks what they give, so a change that matters stops it. If 458
--     changes either of 461's two functions or adds a caller of them, 461
--     refuses, changing nothing, and is rebased on it. 459 (event_* only)
--     touches nothing here.
--   1. Before it, read only, to know which invoices change (an invoice is
--      listed when its list changes: lots_no_longer_blocking, partly refunded
--      and not spent with no claim on them, now moving;
--      lots_now_read_refunded, emptied by a refund, now "Refunded";
--      held_by_another_customer > 0 would stop the apply: SAFETY):
--        select i.invoice_no, i.status::text as status,
--               count(*) filter (where l.remaining_amount > 0) as lots_no_longer_blocking,
--               count(*) filter (where l.remaining_amount = 0) as lots_now_read_refunded,
--               count(*) filter (where l.remaining_amount > 0 and l.status = 'active' and i.deleted_at is null
--                                  and l.customer_id is distinct from i.customer_id) as held_by_another_customer
--          from public.invoice_benefit_values b
--          join public.invoices i on i.id = b.invoice_id
--          join public.customer_credit_lots l on l.id = b.lot_id
--         where l.id in (select x.lot_id from public.invoice_credit_lot_ids(b.invoice_id) x)
--           and l.remaining_amount < l.original_amount
--           and l.remaining_amount + b.cancelled_unused_value + public.invoice_benefit_unused_elsewhere(b.id) >= b.granted_value
--           and (l.remaining_amount > 0 and b.cancelled_unused_value = 0 and i.status not in ('cancelled', 'refunded')
--                  and not exists (select 1 from public.invoice_benefit_transfers t where t.source_benefit_id = b.id)
--                  and not exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = i.id and q.applied_at is null)
--                or l.remaining_amount = 0 and public.invoice_benefit_unused_elsewhere(b.id) > 0
--                  and not exists (select 1 from public.invoice_benefit_transfers t
--                                   where t.source_benefit_id = b.id and t.replacement_benefit_id is not null))
--         group by i.id, i.invoice_no, i.status
--         order by i.invoice_no;
--      (Invoice numbers and counts only. The suite runs this same text
--      before installing 461 and checks it lists exactly the invoices whose
--      list changes.)
--   2. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below, the second changes
--      nothing ("left alone" twice). If 460 goes first, the same with 460 in
--      (its fingerprint below).
--   3. Apply (the CLI, or the MCP's apply_migration with this text verbatim).
--      It checks itself.
--   Afterwards (each checked on a copy, 24 Oct 2026): the re-run of 447 (it
--   pins the move at e313e87b and the list at e3a4b753) refuses on the move,
--   where today it refuses already on cancelled_invoice_used_value (448's);
--   406's (bundle_line_components), 445's (refund_invoice_recorded), 446's
--   and 448's (reopen_invoice) and 449's (event_registration_close, changed
--   by 450) re-runs refuse already today, as before; 450 to 455's re-runs
--   (451's included) leave all alone. Each refusal changes nothing. All are
--   applied, so nothing is lost. scripts/invoices/tests/customer-change-
--   credit-447.sql pinned the move's md5 in its -v nomig=1 mode; it now
--   takes 460's and 461's changes out first (447's records step is in both,
--   unchanged), and refunded-units-not-used-448.sql checks its 8 (2) and
--   8 (3) the fixed way where 460 and 461 are in: one version of each for
--   455, 461, 460 and both.
--
-- BEFORE (production, 22 Oct 2026, at 455; md5 of pg_get_functiondef with
-- search_path public)
--   changed
--   invoice_transferable_benefits(uuid)                                e3a4b753d87546a1a73342baf02bee70  (406's AFTER)
--     or, with 460 in first (460's AFTER)                              c568df874f2667f6a313d7aac0b4c086
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)             e313e87b4ab4c0063d924430996ffbd3  (447's AFTER)
--     or, with 460 in first (460's AFTER)                              5a165f7035151f8f711fc2ac293e9b62
--   relied on, not changed (pinned)
--   invoice_credit_lot_ids(uuid)                                       50346a2e9aea50b31d4207c43b2f197c  (the lots listed and moved)
--   require_store_access(uuid)                                         f9332fd2f0092337d64501d8a647c23f  (the list's first step)
--   entitlement_claimed_qty(uuid)                                      89b08265d5303e890569e953d83d2440  (the list's allowance rows)
--   ensure_customer_wallet(uuid)                                       8ef18daebbbe3c12f2024290ea8416e8  (the move)
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855  (the move)
--   trg_credit_lot_immutable()                                         0fc74da0dcc9b436dfd26c4582542f6c  (a posted lot cannot change customer)
--   relied on, checked by what they are, not pinned
--   invoice_benefit_unused_elsewhere(uuid)                             d35d7c8ae7187985ea64f8a5c38a7d79  (448's helper: STABLE, numeric, service role)
--   cancelled_invoice_used_value(uuid)                                 055a3b07b1c15ffb1ac19039fa6cb650  (calls the helper in its test)
--   invoice_action_plan(uuid,text,jsonb)                               383d618edb28c3c9a360242d038a022c  (calls the helper in its test)
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                        422682d6e1ada0e5d98053e74ab9f007  (a caller, by name)
--   preview_invoice_correction(uuid,jsonb)                             2bb7c0a5769050d5b2f9247a3aa05ecd  (a caller, by name)
--   public function fingerprint, production now (455 in)               b43a0781217fd1b4027749deafbddca7 (1372 functions)
-- AFTER (for later guards)
--   invoice_transferable_benefits(uuid)                                ab86a3fa6305d1efd49d0ee7d7e688f6
--     with 460 in too (either order)                                   362d6d076c4751ab5dbe760f6d7a0d37
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)             dd592a5cf2383c84bcf0986dd0f01523
--     with 460 in too (either order)                                   c1827889748d29f7a6626294333bd94f
--   public function fingerprint, worked out on copies of production (24 Oct 2026):
--     production now (455 in) -> 461 (a second run the same)           79015cfc9d55a0816cc16ed7fa7d6d17 (1372 functions: none new, none dropped)
--     with 460 (461 then 460, or 460 then 461)                         037095a507480dafd8381a6d3d8add90 (1374 functions: 460's two new;
--       460's text of 24 Oct 2026; with its earlier drafts db0a6ec2 / 78d539ab / a0679713)
--   grant list (proacl by signature) unchanged by 461                  02ccc9f63f575db7df6d390b30bf7d22
--     with 460 (460's two helpers), on the copy, either order          acc689cefa349b1ed9588d7d8bb92ce7
--
-- Test: scripts/invoices/tests/customer-change-refunded-461.sql (begin ...
-- rollback; it installs this file twice; -v nomig=1 where it is in; on a
-- copy with 460 in first it installs 461 over it, and -v also460=<460's
-- file> installs the real 460 after it). It reproduces the false "Partly
-- spent" and "Fully spent" first (where 461 is not in), on 14 cases (Credit
-- Packages and Premium Bundles, Paid and Bonus, by line, the guided Refund
-- in full, a cancellation, a reopening waiting, changes in a row, spending
-- and a refund after the change, credit a refunded session gave back) and
-- 17 controls (untouched, spent, spent beside a refund, moved by an Owner, a
-- merge, released credit, reopened and settled, vouchers, and the review's
-- four claims: a cancellation holding credit back, an Owner's Move before
-- credit came back, twice, a cancelled invoice), then checks the refusals
-- (9a to 9h, the footprint included, and the claims kept out of it), the
-- install (either order), the controls unchanged (the whole list and the
-- change's outcome, compared before and after), each case after 461 (the
-- list, the summary, the change, what each customer holds, the lot's
-- origin, the invoice's records, the refund options, the plans, the money
-- afterwards), the money after 461 where a claim keeps the change refused
-- (a reopening and Refund in full, Cancel), the header's query, NOT COVERED
-- 1 (FIXED where 460 is in, KNOWN where not) and 2 as KNOWN. Where 461 is
-- in, refunded-units-not-used-448.sql checks its case 8 (3) the fixed way.
-- Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The two functions this patches: BEFORE (production, 22 Oct 2026, at
  -- 455: 406's and 447's AFTERs) and AFTER md5s; and the same with 460 in
  -- first (460, built beside this, changes both outside 461's part: its
  -- AFTERs of 23 Oct 2026 as BEFORE, and the texts both give as AFTER, the
  -- same in either order) ══════════════════════════════════════════════════
  c_tb constant text := 'invoice_transferable_benefits(uuid)';
  c_mv constant text := 'move_invoice_benefits_to_customer(uuid,uuid,uuid,text)';
  c_tb_before    constant text := 'e3a4b753d87546a1a73342baf02bee70';
  c_tb_after     constant text := 'ab86a3fa6305d1efd49d0ee7d7e688f6';
  c_tb_before460 constant text := 'c568df874f2667f6a313d7aac0b4c086';
  c_tb_after460  constant text := '362d6d076c4751ab5dbe760f6d7a0d37';
  c_mv_before    constant text := 'e313e87b4ab4c0063d924430996ffbd3';
  c_mv_after     constant text := 'dd592a5cf2383c84bcf0986dd0f01523';
  c_mv_before460 constant text := '5a165f7035151f8f711fc2ac293e9b62';
  c_mv_after460  constant text := 'c1827889748d29f7a6626294333bd94f';
  -- Who may call each, as read (kept).
  c_tb_acl constant text := '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}';
  c_mv_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';

  -- ══ 448's helper, called, not changed (and not pinned by its md5: below) ═
  c_h constant text := 'invoice_benefit_unused_elsewhere(uuid)';
  c_h_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';

  -- ══ invoice_transferable_benefits: its credit rows ═══════════════════════
  c_tb_a constant text := $a$  select 'credit', l.id,
         initcap(l.category) || ' credit ' || l.remaining_amount::text,
         l.remaining_amount,
         l.remaining_amount = l.original_amount and l.status = 'active',
         l.remaining_amount > 0 and l.remaining_amount < l.original_amount,
         case when l.remaining_amount = 0 then 'Fully spent; it stays with the original customer'
              when l.remaining_amount < l.original_amount then 'Partly spent'
              when l.status <> 'active' then 'Not active' end
    from public.customer_credit_lots l
   where l.id in (select lot_id from public.invoice_credit_lot_ids(p_invoice_id))
$a$;
  c_tb_r constant text := $r$  -- 461 (the Owner, 22 Oct 2026: "fix the other two rare gaps too"; 448's
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
$r$;

  -- ══ move_invoice_benefits_to_customer: the lots it moves ═════════════════
  c_mv_a constant text := $a$       and l.remaining_amount = l.original_amount
       and l.remaining_amount > 0
       and l.status = 'active'
$a$;
  c_mv_r constant text := $r$       -- 461 (the Owner, 22 Oct 2026): or nothing on it was spent. Credit a
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
$r$;

  -- ══ Relied on, not changed (production, 22 Oct 2026, at 455) ════════════
  c_relied constant text[] := array[
    'invoice_credit_lot_ids(uuid)',
    'require_store_access(uuid)',
    'entitlement_claimed_qty(uuid)',
    'ensure_customer_wallet(uuid)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'trg_credit_lot_immutable()'];
  c_relied_md5 constant text[] := array[
    '50346a2e9aea50b31d4207c43b2f197c',
    'f9332fd2f0092337d64501d8a647c23f',
    '89b08265d5303e890569e953d83d2440',
    '8ef18daebbbe3c12f2024290ea8416e8',
    'c705c733e213a27f0dc32d54322cc855',
    '0fc74da0dcc9b436dfd26c4582542f6c'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  r record; v text; d text; d2 text; n int; k int; i int;
  v_anchor text; v_patch text; v_before text; v_after text; v_before460 text; v_after460 text; v_want text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[] := '{}';
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_buyer uuid; t_friend uuid; t_pk uuid;
  t_inv uuid; t_item uuid; t_b uuid; t_pay uuid; t_lot uuid; t_new uuid; t_msg text; t_res jsonb;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The functions relied on are as read on production (22 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '461: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if to_regprocedure('auth.uid()') is null then raise exception '461: auth.uid() must be there'; end if;

  -- 448's helper: there, returning numeric, STABLE, the server's alone. Its
  -- md5 is not pinned (460, built beside this file, may change it); the
  -- cancel plans' test calls it, so the list and the plans keep one rule.
  if to_regprocedure('public.' || c_h) is null
     or pg_get_function_result(to_regprocedure('public.' || c_h)) is distinct from 'numeric'
     or (select p.provolatile from pg_proc p where p.oid = to_regprocedure('public.' || c_h)) <> 's' then
    raise exception '461: public.% is missing or not a STABLE function returning numeric (448 must be in)', c_h; end if;
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_h))
     is distinct from (select array_agg(x::text order by x::text) from unnest(c_h_acl::aclitem[]) x) then
    raise exception '461: who may call public.% is not as read on 22 Oct 2026 (%)', c_h,
      (select proacl::text from pg_proc where oid = to_regprocedure('public.' || c_h)); end if;
  if position('+ public.invoice_benefit_unused_elsewhere(b.id)' in pg_get_functiondef('public.cancelled_invoice_used_value(uuid)'::regprocedure)) = 0
     or position('+public.invoice_benefit_unused_elsewhere((b->>''id'')::uuid)' in pg_get_functiondef('public.invoice_action_plan(uuid,text,jsonb)'::regprocedure)) = 0 then
    raise exception '461: the cancel plans no longer test a benefit with invoice_benefit_unused_elsewhere (448), so this list would not follow their rule. Re-read them and re-test before applying.'; end if;

  -- The columns read, with these types.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('invoice_benefit_values', 'id', 'uuid'), ('invoice_benefit_values', 'invoice_id', 'uuid'),
                 ('invoice_benefit_values', 'lot_id', 'uuid'),
                 ('invoice_benefit_values', 'cancelled_unused_value', 'numeric(12,2)'),
                 ('invoice_benefit_values', 'granted_value', 'numeric(12,2)'),
                 ('invoice_benefit_transfers', 'source_benefit_id', 'uuid'),
                 ('invoice_benefit_transfers', 'replacement_benefit_id', 'uuid'),
                 ('invoice_reopen_benefits', 'invoice_id', 'uuid'),
                 ('invoice_reopen_benefits', 'applied_at', 'timestamp with time zone'),
                 ('customer_credit_lots', 'id', 'uuid'), ('customer_credit_lots', 'customer_id', 'uuid'),
                 ('customer_credit_lots', 'category', 'text'), ('customer_credit_lots', 'status', 'text'),
                 ('customer_credit_lots', 'original_amount', 'numeric(12,2)'),
                 ('customer_credit_lots', 'remaining_amount', 'numeric(12,2)'),
                 ('customer_credit_lots', 'reassigned_from_lot_id', 'uuid'),
                 ('invoices', 'id', 'uuid'), ('invoices', 'customer_id', 'uuid'), ('invoices', 'status', 'invoice_status'),
                 ('invoices', 'invoice_no', 'text'), ('invoices', 'deleted_at', 'timestamp with time zone')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '461: these columns are missing or not as read on 22 Oct 2026: %', v; end if;
  if not (array['cancelled', 'refunded'] <@ enum_range(null::public.invoice_status)::text[]) then
    raise exception '461: an invoice is no longer ''cancelled'' or ''refunded'' (invoice_status: %)', enum_range(null::public.invoice_status); end if;
  -- One benefit row per lot (the list joins a lot to its row).
  if not exists (select 1 from pg_indexes where schemaname = 'public' and tablename = 'invoice_benefit_values'
                  and indexname = 'invoice_benefit_lot_unique'
                  and indexdef = 'CREATE UNIQUE INDEX invoice_benefit_lot_unique ON public.invoice_benefit_values USING btree (lot_id) WHERE (lot_id IS NOT NULL)') then
    raise exception '461: invoice_benefit_values no longer has one row per lot (invoice_benefit_lot_unique)'; end if;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('invoice_transferable_benefits', 'move_invoice_benefits_to_customer')
     and p.oid::regprocedure::text not in (c_tb, c_mv);
  if v is not null then raise exception '461: another function takes the name of one this changes: %', v; end if;

  -- Who calls them, as read: the list by the invoice form (the page), the
  -- correction preview, the invoice save and the move; the move by the
  -- invoice save alone. (A session's own temporary functions are not
  -- counted.)
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'invoice_transferable_benefits\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and not (p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = c_tb);
  if v is distinct from 'correct_invoice(uuid,jsonb,jsonb,text,uuid), move_invoice_benefits_to_customer(uuid,uuid,uuid,text), preview_invoice_correction(uuid,jsonb)' then
    raise exception '461: the functions that call invoice_transferable_benefits are not as read on 22 Oct 2026 (%); check each, then re-test', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'move_invoice_benefits_to_customer\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and not (p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = c_mv);
  if v is distinct from 'correct_invoice(uuid,jsonb,jsonb,text,uuid)' then
    raise exception '461: the functions that call move_invoice_benefits_to_customer are not as read on 22 Oct 2026 (%); check each, then re-test', v; end if;

  -- Each patched function: its BEFORE (patched; its anchor found once; the
  -- text built has its AFTER md5) or its AFTER (left alone), each either as
  -- at 455 or with 460 in (460's AFTER as BEFORE; 460 leaves 461's anchors
  -- as they are, so the same patch gives the text 460 gives over 461).
  foreach v in array array[c_tb, c_mv] loop
    if to_regprocedure('public.' || v) is null then raise exception '461: public.% is missing', v; end if;
    if v = c_tb then
      v_anchor := c_tb_a; v_patch := c_tb_r; v_before := c_tb_before; v_after := c_tb_after;
      v_before460 := c_tb_before460; v_after460 := c_tb_after460;
    else
      v_anchor := c_mv_a; v_patch := c_mv_r; v_before := c_mv_before; v_after := c_mv_after;
      v_before460 := c_mv_before460; v_after460 := c_mv_after460;
    end if;
    d := pg_get_functiondef(to_regprocedure('public.' || v));
    if md5(d) in (v_after, v_after460) then
      raise notice '461: public.% is already this version%; left alone', v,
        case when md5(d) = v_after460 then ' (with 460 in)' else '' end;
      continue;
    end if;
    n := (length(d) - length(replace(d, v_anchor, ''))) / length(v_anchor);
    if n <> 1 then
      raise exception '461: the anchor of public.% is found % times, not once (md5 %). Re-read it and re-test before applying.', v, n, md5(d); end if;
    d2 := replace(d, v_anchor, v_patch);
    v_want := case md5(d) when v_before then v_after when v_before460 then v_after460 end;
    if v_want is null then
      raise exception '461: public.% is not the version this was tested against (md5 %; patched it would be md5 %). Re-read it and re-test before applying.', v, md5(d), md5(d2); end if;
    if md5(d2) <> v_want then
      raise exception '461: the text built for public.% is not the tested one (md5 %)', v, md5(d2); end if;
    v_fns := v_fns || v;
    v_defs := v_defs || d2;
  end loop;

  -- On the first run (a function at its BEFORE): no invoice carries the
  -- gap's footprint. Before 461 a customer change that took the benefits
  -- along was refused for a partly refunded lot, so the way through was to
  -- change the customer and keep the benefits with whoever held them: the
  -- lot stayed with the earlier customer. 461 lists such a lot as moving,
  -- held by someone other than the invoice's customer, so a later change
  -- that takes the benefits along would move it (as it moves an untouched
  -- lot that was kept). A shared package's share (141, older invoices) is
  -- held by its share's customer by design and is listed too: a change
  -- taking the benefits along moves every share (321). Whether such credit
  -- should follow needs a decision first; the file cannot tell a choice from
  -- a way round the refusal, so it stops, changing nothing, and names the
  -- invoices. Only the lots 461 lists as moving are looked at (no
  -- cancellation holding credit back, no reopening waiting, no Move, the
  -- invoice neither cancelled nor refunded): the others block as before. A
  -- second run skips this (changes since were made with 461 in).
  if coalesce(cardinality(v_fns), 0) > 0 then
    select count(distinct iv.id), string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into n, v
      from public.invoice_benefit_values b
      join public.invoices iv on iv.id = b.invoice_id
      join public.customer_credit_lots l on l.id = b.lot_id
     where iv.deleted_at is null
       and l.customer_id is distinct from iv.customer_id
       and l.status = 'active' and l.remaining_amount > 0 and l.remaining_amount < l.original_amount
       and l.remaining_amount + b.cancelled_unused_value + public.invoice_benefit_unused_elsewhere(b.id) >= b.granted_value
       and b.cancelled_unused_value = 0
       and not exists (select 1 from public.invoice_benefit_transfers t where t.source_benefit_id = b.id)
       and not exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = iv.id and q.applied_at is null)
       and iv.status not in ('cancelled', 'refunded')
       and l.id in (select x.lot_id from public.invoice_credit_lot_ids(b.invoice_id) x);
    if n > 0 then
      raise exception '461: % invoice(s) have a partly refunded credit lot, not spent, held by someone other than the invoice''s customer (%): the customer was changed keeping the benefits, or the lot is a shared package''s share. 461 would list that credit as moving with a later change. Decide where each should be, then apply. Nothing was changed.', n, v; end if;
  end if;

  -- Who may call each, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  foreach v in array array[c_tb, c_mv] loop
    v_want := c_mv_acl;
    if v = c_tb then v_want := c_tb_acl; end if;
    if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || v))
       is distinct from (select array_agg(x::text order by x::text) from unnest(v_want::aclitem[]) x) then
      raise exception '461: who may call public.% is not as read on 22 Oct 2026 (%)', v,
        (select proacl::text from pg_proc where oid = to_regprocedure('public.' || v)); end if;
    v_acl := v_acl || (select coalesce(string_agg(x::text, ',' order by x::text), '')
                         from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || v));
  end loop;

  -- ── Change ──────────────────────────────────────────────────────────────
  for k in 1 .. coalesce(cardinality(v_fns), 0) loop
    execute v_defs[k];
  end loop;

  -- ── Afterwards: installed exactly as tested (both as at 455 with 461, or
  -- both with 460 in too), grants as before ────────────────────────────────
  if (md5(pg_get_functiondef(to_regprocedure('public.' || c_tb))), md5(pg_get_functiondef(to_regprocedure('public.' || c_mv))))
     not in ((c_tb_after, c_mv_after), (c_tb_after460, c_mv_after460)) then
    raise exception '461: public.% and public.% are not at their AFTER md5s (% / %)', c_tb, c_mv,
      md5(pg_get_functiondef(to_regprocedure('public.' || c_tb))), md5(pg_get_functiondef(to_regprocedure('public.' || c_mv))); end if;
  k := 0;
  foreach v in array array[c_tb, c_mv] loop
    k := k + 1;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || v)) is distinct from v_acl[k] then
      raise exception '461: the grants of public.% changed', v; end if;
  end loop;
  if has_function_privilege('anon', 'public.' || c_tb, 'execute')
     or not has_function_privilege('authenticated', 'public.' || c_tb, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_tb, 'execute')
     or has_function_privilege('anon', 'public.' || c_mv, 'execute')
     or has_function_privilege('authenticated', 'public.' || c_mv, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_mv, 'execute') then
    raise exception '461: who may call public.% or public.% is not as before', c_tb, c_mv; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("461 check", @example.invalid, fictional ACMA phones
  -- no customer uses); it ends by raising P0461, which undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from unnest(array['+61491570961', '+61491570962', '+61491570963', '+61491570964', '+61491570965']) p
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p limit 2);
    if coalesce(cardinality(t_phones), 0) < 2 then raise exception '461: the self-test found no two unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '461-check-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '461 check', '461-check-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('461 check ' || t_sfx, '461-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('461 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.customers (full_name, phone) values ('461 Check Buyer ' || t_sfx, t_phones[1]) returning id into t_buyer;
    insert into public.customers (full_name, phone) values ('461 Check Friend ' || t_sfx, t_phones[2]) returning id into t_friend;
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, bonus_value,
                                        allow_product, allow_therapy, allow_voucher, grants_reward)
    values ('461 check ' || t_sfx, 100, 100, true, 10, true, true, true, false) returning id into t_pk;
    insert into public.credit_package_stores (package_id, store_id) values (t_pk, t_store);

    -- (a) A S$100 Credit Package (S$10 Bonus), paid; S$40 of its Paid benefit
    -- refunded by line (S$44 of credit): the Paid lot is listed as moving,
    -- not blocking; moved to the friend, it keeps its origin, the benefit
    -- row names the friend's lot, and the plans ask nothing; cancelled, the
    -- friend's lot is emptied and nothing reads as used.
    t_inv := public.create_invoice(t_store, t_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)));
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
    select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv;
    select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1;
    select b.id, b.lot_id into t_b, t_lot from public.invoice_benefit_values b
      join public.customer_credit_lots l on l.id = b.lot_id where b.invoice_id = t_inv and l.category = 'paid';
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 40,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_b, 'amount', 40)))),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 40)), '[]'::jsonb, '461 check', gen_random_uuid());
    if (select remaining_amount from public.customer_credit_lots where id = t_lot) <> 56
       or not exists (select 1 from public.invoice_transferable_benefits(t_inv) x
                       where x.record_id = t_lot and x.movable and not x.blocking and x.blocked_reason is null and x.units = 56) then
      raise exception '461: a partly refunded lot is not listed as moving (%)',
        (select jsonb_agg(to_jsonb(x)) from public.invoice_transferable_benefits(t_inv) x); end if;
    t_res := public.move_invoice_benefits_to_customer(t_inv, t_friend, t_store, '461 check');
    select b.lot_id into t_new from public.invoice_benefit_values b where b.id = t_b;
    if (t_res->>'credit_lots')::int <> 2
       or (select remaining_amount from public.customer_credit_lots where id = t_lot) <> 0
       or not exists (select 1 from public.customer_credit_lots n2 join public.customer_credit_lots o on o.id = t_lot
                       where n2.id = t_new and n2.customer_id = t_friend and n2.reassigned_from_lot_id = t_lot
                         and n2.original_amount = 56 and n2.remaining_amount = 56 and n2.category = o.category
                         and n2.source_type = o.source_type and n2.source_record_id is not distinct from o.source_record_id
                         and n2.usage_restrictions = o.usage_restrictions and n2.store_id is not distinct from o.store_id)
       or (select credit_lot_id from public.credit_package_sales where invoice_id = t_inv) is distinct from t_new
       or exists (select 1 from jsonb_array_elements(coalesce(public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->'overrides_required', '[]'::jsonb)) o
                   where o->>'code' = 'credit_used') then
      raise exception '461: the partly refunded lot did not move with its origin and records (% / %)', t_res,
        (select jsonb_agg(to_jsonb(l)) from public.customer_credit_lots l where l.customer_id = t_friend); end if;
    perform public.cancel_invoice_recorded(t_inv, '461 check', gen_random_uuid());
    if (select coalesce(sum(l.remaining_amount), 0) from public.customer_credit_lots l where l.customer_id = t_friend) <> 0
       or cardinality(public.cancelled_invoice_used_value(t_inv)) <> 0 then
      raise exception '461: cancelled, the friend still holds credit or the invoice reads %', public.cancelled_invoice_used_value(t_inv); end if;
    -- (d) That cancellation still holds the S$56 back (cancelled_unused_value):
    -- credit come back to the lot (as when an invoice that spent it is
    -- refunded) blocks as "Partly spent", and the move refuses it.
    update public.customer_credit_lots set remaining_amount = 30 where id = t_new;
    if not exists (select 1 from public.invoice_transferable_benefits(t_inv) x
                    where x.record_id = t_new and not x.movable and x.blocking and x.blocked_reason = 'Partly spent') then
      raise exception '461: a lot a cancellation still holds credit back for is not blocking (%)',
        (select jsonb_agg(to_jsonb(x)) from public.invoice_transferable_benefits(t_inv) x); end if;
    t_msg := null;
    begin
      perform public.move_invoice_benefits_to_customer(t_inv, t_buyer, t_store, '461 check');
    exception when others then t_msg := sqlerrm;
    end;
    if t_msg is null or t_msg not like 'These benefits have already been used and cannot move with the invoice: Paid credit 30.00 (Partly spent).%' then
      raise exception '461: a lot a cancellation still holds credit back for was not refused (%)', coalesce(t_msg, 'moved'); end if;

    -- (b) Two packages, paid; line A's benefits wholly refunded by line: its
    -- two lots read "Refunded", neither moving nor blocking.
    t_inv := public.create_invoice(t_store, t_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1),
                        jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)));
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 200)), gen_random_uuid());
    select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv order by it.id limit 1;
    select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1;
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 100,
        'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', b.id, 'amount', b.paid_value))
                       from public.invoice_benefit_values b where b.invoice_item_id = t_item))),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 100)), '[]'::jsonb, '461 check', gen_random_uuid());
    if (select count(*) from public.invoice_transferable_benefits(t_inv) x
         where x.record_id in (select b.lot_id from public.invoice_benefit_values b where b.invoice_item_id = t_item)
           and x.blocked_reason = 'Refunded; nothing is left to move' and not x.movable and not x.blocking and x.units = 0) <> 2
       or (select count(*) from public.invoice_transferable_benefits(t_inv) x where x.movable) <> 2 then
      raise exception '461: a wholly refunded lot is not read as refunded (%)',
        (select jsonb_agg(to_jsonb(x)) from public.invoice_transferable_benefits(t_inv) x); end if;

    -- (c) S$40 refunded and S$10 of the rest spent: still "Partly spent",
    -- blocking, and the move refuses, naming it.
    t_inv := public.create_invoice(t_store, t_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)));
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
    select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv;
    select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1;
    select b.id, b.lot_id into t_b, t_lot from public.invoice_benefit_values b
      join public.customer_credit_lots l on l.id = b.lot_id where b.invoice_id = t_inv and l.category = 'paid';
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 40,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_b, 'amount', 40)))),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 40)), '[]'::jsonb, '461 check', gen_random_uuid());
    update public.customer_credit_lots set remaining_amount = remaining_amount - 10 where id = t_lot;
    if not exists (select 1 from public.invoice_transferable_benefits(t_inv) x
                    where x.record_id = t_lot and not x.movable and x.blocking and x.blocked_reason = 'Partly spent') then
      raise exception '461: credit spent beside credit refunded is not blocking as partly spent (%)',
        (select jsonb_agg(to_jsonb(x)) from public.invoice_transferable_benefits(t_inv) x); end if;
    t_msg := null;
    begin
      perform public.move_invoice_benefits_to_customer(t_inv, t_friend, t_store, '461 check');
    exception when others then t_msg := sqlerrm;
    end;
    if t_msg is null or t_msg not like 'These benefits have already been used and cannot move with the invoice: Paid credit 46.00 (Partly spent).%' then
      raise exception '461: a lot with credit spent was not refused as partly spent (%)', coalesce(t_msg, 'moved'); end if;

    -- (e) S$40 refunded, the rest moved to the friend by an Owner (Move: the
    -- invoice's records stay on the buyer's lot): credit come back to that
    -- lot still blocks as "Partly spent", and the move refuses it.
    t_inv := public.create_invoice(t_store, t_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)));
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
    select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv;
    select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1;
    select b.id, b.lot_id into t_b, t_lot from public.invoice_benefit_values b
      join public.customer_credit_lots l on l.id = b.lot_id where b.invoice_id = t_inv and l.category = 'paid';
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 40,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_b, 'amount', 40)))),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 40)), '[]'::jsonb, '461 check', gen_random_uuid());
    perform public.transfer_invoice_unused_benefit(t_b, t_friend, t_store, '461 check', gen_random_uuid());
    if (select remaining_amount from public.customer_credit_lots where id = t_lot) <> 0 then
      raise exception '461: the Move left % on the buyer''s lot', (select remaining_amount from public.customer_credit_lots where id = t_lot); end if;
    update public.customer_credit_lots set remaining_amount = 30 where id = t_lot;
    if not exists (select 1 from public.invoice_transferable_benefits(t_inv) x
                    where x.record_id = t_lot and not x.movable and x.blocking and x.blocked_reason = 'Partly spent') then
      raise exception '461: a lot whose benefit an Owner moved is not blocking (%)',
        (select jsonb_agg(to_jsonb(x)) from public.invoice_transferable_benefits(t_inv) x); end if;
    t_msg := null;
    begin
      perform public.move_invoice_benefits_to_customer(t_inv, t_friend, t_store, '461 check');
    exception when others then t_msg := sqlerrm;
    end;
    if t_msg is null or t_msg not like 'These benefits have already been used and cannot move with the invoice: Paid credit 30.00 (Partly spent).%' then
      raise exception '461: a lot whose benefit an Owner moved was not refused (%)', coalesce(t_msg, 'moved'); end if;

    raise exception using errcode = 'P0461', message = '461: self-test done, undone';
  exception when sqlstate 'P0461' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
