-- 446_line_refund_takes_waiting_reopen_voucher.sql
--
-- A VOUCHER OR CREDIT REFUNDED WHILE A REOPENED INVOICE WAITS TO BE SETTLED
-- IS NOT GIVEN AGAIN WHEN IT IS SETTLED (the Owner, 22 Oct 2026: 438's NOT
-- COVERED 4, "Fix it"; and the same for credit, in this file)
--
-- WHO FOUND IT
--
--   Vouchers: the reviews of 438 (21 Oct 2026), written up as 438's NOT
--   COVERED 4 and checked as KNOWN by its suite
--   (scripts/invoices/tests/reopen-recancel-438.sql, case U4). Credit: found
--   while building this file (22 Oct 2026; first written up here as NOT
--   COVERED 2). Both there before 438, not caused by it. Both reproduced for
--   this file on a copy of production as it is now (83a90dbf, 1370
--   functions), through the app's own calls only (the invoice form, the Pay
--   dialog, Cancel, the Finance panel's "Record refund paid" and Reopen, the
--   guided "Refund some items", Record Payment).
--
-- WHAT WAS WRONG
--
--   Vouchers. A cancellation takes an invoice's unused vouchers back (the
--   voucher is revoked; its benefit row's cancelled_unused_value counts the
--   units). A reopening that leaves the invoice part-paid queues those units
--   to be given again (invoice_reopen_vouchers, not yet applied); the payment
--   that settles the invoice gives them (apply_reopened_invoice_vouchers, the
--   trigger invoice_reopen_vouchers_settled). A line refund made while they
--   wait (refund_invoice_recorded; the guided "Refund some items" goes
--   through it) takes the refunded units off cancelled_unused_value and pays
--   the money back, but left the queued row as it was. So:
--   * the payment that settles the invoice gave the refunded unit again: two
--     S$30 vouchers sold and paid, cancelled, S$30 recorded as paid back,
--     reopened (both wait), line A refunded, the S$30 outstanding paid: the
--     customer held 2 vouchers for S$30 net (a limited voucher's stock was
--     taken for both). A line of two with one unit refunded the same way: 2
--     vouchers for S$30;
--   * and a later reopening counted the same line refund again
--     (invoice_voucher_reopen_candidates counts every refund since the last
--     reopening, to give its units back): cancelled again, reopened and paid
--     (with or without money recorded as paid back first), the customer held
--     3 vouchers for two lines of one.
--   It is the same after a completed FOC whose FOC was taken off (416), once
--   the invoice is paid, cancelled and reopened: the waiting rows are the
--   reopening's.
--   Credit. A cancellation takes an invoice's unused Credit Package or
--   Premium Bundle credit back (each lot is emptied with an
--   'invoice_cancel_benefit' ledger row; its benefit row's
--   cancelled_unused_value counts it). A reopening queues every such ledger
--   row of the invoice, and every refund's own 'invoice_benefit_refund' row,
--   not queued yet, to be reinstated (invoice_reopen_benefits, not yet
--   applied); the payment that settles the invoice reinstates them
--   (apply_reopened_invoice_benefits, the trigger
--   invoice_reopen_benefits_settled). A line refund made while they wait
--   takes the refunded credit off cancelled_unused_value and pays the money
--   back, but left the queued rows as they were, so the payment reinstated
--   it anyway: two S$100 Credit Packages sold and paid, cancelled, line B's
--   S$100 recorded as paid back, reopened (all the credit waits), line A
--   refunded, the S$100 outstanding paid: the customer held S$200 of credit
--   for S$100 net. With a S$10 Bonus on each package, S$220; two Premium
--   Bundles of S$100 Paid and S$20 Bonus, S$240; S$40 of line A refunded,
--   S$200 for S$160 net. The same for a part-paid package's released credit
--   once its line was settled (the released lot is then the line's lot).
--   Production, 22 Oct 2026 (counts only): invoice_reopen_vouchers has never
--   had a row; invoice_reopen_benefits has 4 rows, on one invoice (11 Sep
--   2026), none waiting, and no line refund was recorded while one waited.
--   So neither has ever happened; nothing to repair. The file refuses,
--   changing nothing, if a row in that state exists when it is applied
--   (SAFETY).
--
-- THE OWNER'S ANSWERS (22 Oct 2026)
--
--   Vouchers (438's NOT COVERED 4): "Fix it": a line refund made while a
--   reopened invoice's vouchers are still waiting also takes the refunded
--   unit off the waiting row, so the payment that settles the invoice does
--   not give it again, and a later reopening does not count the same line
--   refund again.
--   Credit (this file's first draft, NOT COVERED 2): fix it here, the same
--   way: a line refund made while a reopened invoice's credit waits also
--   takes the refunded amount off the waiting rows.
--   Not here: the false 'voucher_redeemed' override that Cancel and Refund in
--   full still ask for a unit refunded by line (438's NOT COVERED 2) is a
--   separate fix, later (NOT COVERED 1 below).
--
-- WHAT THIS DOES (one function: refund_invoice_recorded; grants kept)
--
--   Vouchers. In refund_invoice_recorded's voucher branch, after the units
--   refunded are taken off the benefit row's cancelled_unused_value
--   (unchanged), the same units come off that benefit's queued rows still
--   waiting (invoice_reopen_vouchers, applied_at null), the most recently
--   queued first: a row is lowered, or removed when nothing is left of it.
--   Each change is written to the invoice's Audit Log
--   ('reopen_voucher_refunded': the queued row as it was, the units refunded
--   and still waiting, the refund's request id), so a removed row stays
--   traceable. So the payment that settles the invoice gives only what still
--   waits, and its stock is taken for that only. A later reopening is
--   unchanged (invoice_voucher_reopen_candidates): it counts the refund once,
--   to give the unit back, as it counts every refund made since the last
--   reopening, and the invoice charges that line again (its refunds before
--   the reopening no longer count); the payment no longer gives the unit
--   first, so it is given once. On the copy: 1 voucher for S$30 net, then 2
--   for S$60 after a second cancel, reopen and payment; the line of two: 1.
--   Credit. In the credit branch, after the credit refunded is taken off the
--   benefit row's cancelled_unused_value (unchanged), the same amount comes
--   off that lot's rows still waiting (the invoice's invoice_reopen_benefits
--   rows whose ledger row is on the lot, applied_at null), the most recently
--   queued first, as if that part had been reinstated and then refunded: the
--   row gives it now (a 'reverse' ledger row, 'invoice_reopen', naming the
--   reopening's request and the ledger row it reinstates, as the settling
--   payment writes) and the refund takes it straight back (one
--   'adjust_decrease' ledger row, 'invoice_benefit_refund', the refund's
--   request id, as any refund of unused credit writes). The row is lowered,
--   or closed as applied when nothing is left of it. The lot does not move,
--   and the customer's credit statement still ends at the credit held (the
--   Customers page lists the two rows: credit returned, then the refund's
--   decrease). Each change is written to the invoice's Audit Log
--   ('reopen_credit_refunded': the queued row as it was, the benefit, the
--   lot, the amount refunded and still waiting, the refund's request id).
--   Paid and Bonus credit each have their own lot, benefit row and queued
--   rows, so each follows its own share of the refund, for a Credit Package
--   and a Premium Bundle alike, and a part-paid package's released lot once
--   its line was settled. So the payment that settles the invoice reinstates
--   only what still waits. A later reopening is unchanged (reopen_invoice):
--   it queues the refund's own row once, as it queues every refund's, and the
--   invoice charges that line again; the cancellation's row is not queued
--   again (its queued row is still there). On the copy: S$100 of credit for
--   S$100 net (S$110 with the Bonus, S$120 for the bundles), S$160 for S$160
--   after S$40 was refunded; cancelled again, reopened and paid: S$200 for
--   S$200 (S$220, S$240), the refund counted once.
--   One block is added to each branch; nothing else in the function changes:
--   its signature, checks, messages, answer, the money, stock and grants
--   (signed-in staff and the service role; it lets only an Owner or Manager
--   through). A refund made with nothing waiting finds no row and does
--   exactly what it did.
--
-- VOUCHERS: TAKEN OFF, NOT MARKED AS GIVEN (why)
--
--   Marking the refunded units as applied with no replacement would have
--   kept 438's counting quiet (it adds every applied row: see NOT COVERED 1),
--   but 417's cancel_invoice_recorded gives limited voucher stock back by
--   counting the units each voucher's chain issued, less those an applied
--   row says were given again in their place (the replacement counts them).
--   With no replacement a refunded unit would drop out of that count, and its
--   stock, back since the first cancellation, would be given back again at
--   every later cancellation (tried on the copy: one unit too many each
--   time). So the units come off the queue, and the invoice then reads as one
--   whose line was refunded in the usual way.
--
-- CREDIT: REINSTATED AND REFUNDED AT ONCE, AND CLOSED, NOT REMOVED (why)
--
--   A reopening queues credit by ledger row: each cancellation row and each
--   refund's row of the invoice not queued yet (reopen_invoice). A refund that
--   takes credit off cancelled_unused_value writes no ledger row. So had the
--   queued row only been lowered, and closed with nothing left, the next
--   reopening would find nothing to give back for the part refunded, though
--   it charges the line again; had it been removed, the reopening would queue
--   the cancellation's row again, whole. Tried on the copy, cancelled again,
--   reopened and paid: lowered and closed, S$100 of credit for S$200 (line A
--   refunded whole) and S$160 for S$200 (S$40 refunded); lowered and removed,
--   right for line A refunded whole but S$160 for S$200 after S$40, and the
--   same when cancelled again before it was settled. Reinstating the refunded
--   part and refunding it at once leaves the refund its own ledger row, which
--   the next reopening queues once, as for a refund made with nothing
--   waiting, while the queued row stays (lowered or closed), so the
--   cancellation's row is not queued again. Nothing reads a closed row's
--   amount: the settling payment reinstates only rows still waiting, and the
--   Reopen dialog and a Move look only at whether a row exists or waits.
--
-- NOT CHANGED
--
--   * apply_reopened_invoice_vouchers, apply_reopened_invoice_benefits,
--     reopen_invoice, invoice_voucher_reopen_candidates,
--     invoice_reopen_preview (the Reopen dialog's "Voucher units to replace
--     after settlement" and its credit to reinstate),
--     invoice_voucher_stock_unrecorded, cancel_invoice_recorded,
--     trg_issue_sold_vouchers_on_paid (416), transfer_invoice_unused_benefit
--     (it refuses a Move while vouchers or credit wait, unchanged),
--     customer_credit_statement (it counts an 'invoice_reopen' reverse as
--     credit returned): they read the queues and the ledger as they now are;
--     pinned below.
--   * A line refund on an invoice with nothing waiting (paid, a reopened
--     invoice already settled, a cancelled one not reopened) does exactly
--     what it did (the loops find no row): the suite compares its outcome
--     whole with and without 446, vouchers and credit.
--   * 438's counting (cancelled_invoice_used_value, invoice_action_plan) and
--     the refund options: not changed, not pinned. A unit a reopening or a
--     payment gave again, or an Owner moved, still counts as not used.
--   * A guided request made before 446 carries a plan that does not read the
--     queues; approved after 446 it takes the units and the credit off, as
--     above (the plan's credit_removed, what comes off the customer, is
--     unchanged: the lot does not move).
--   * The pages: they read the server's answers (InvoiceFinancePanel.tsx,
--     InvoiceGuidedAction.tsx, InvoicesPage.tsx, and CustomersPage.tsx's
--     credit statement, which shows the two new ledger rows as any others);
--     no message or button changes. The Audit Log page shows the new actions
--     as 'reopen voucher refunded' and 'reopen credit refunded' (it has no
--     label map). No table, row, index, grant or other function changes.
--
-- NOT COVERED (found while building and reviewing this; for the Owner; the
-- suite checks each as it is and prints it as KNOWN)
--
--   1. A voucher unit refunded by line reads as "used" in 438's counting, as
--      everywhere (438's NOT COVERED 2), and these units now too: once the
--      invoice is settled, Cancel asks a voucher_redeemed override (and,
--      since 417, "State how much is owed back"), Refund in full asks it when
--      the line still holds something (the line of two), and after a direct
--      cancel "Record refund paid" is refused unless an amount owed was
--      stated. The same for credit: Cancel asks credit_used for a credit line
--      refunded while it waited, as it does for any credit line refunded by
--      line (a paid invoice with line A refunded asks it today); Refund in
--      full asks nothing. While the vouchers or the credit wait it already
--      read so before 446; once settled it read quiet only because the
--      refunded unit or credit had been given again. Nothing is given or kept
--      wrongly; the override is a false prompt. The Owner (22 Oct 2026): a
--      separate fix, later, not part of 446 or 447. It needs 438's NOT
--      COVERED 2's own change (cancelled_invoice_used_value and
--      invoice_action_plan, which 447 pins), or a cancellation that tells a
--      refunded unit from a replaced one (417's cancel_invoice_recorded, which
--      447 pins too).
--   2. A unit a reopening queued because an earlier line refund had taken it
--      (the reopening gives refunded units back) cannot be refunded while it
--      waits: the refund options and refund_invoice_recorded read the held
--      voucher and cancelled_unused_value only ("There is nothing left to
--      refund on this invoice"). The same for credit a reopening queued from
--      a refund's own row, or for a line refunded on the cancelled invoice
--      before the reopening (its credit waits, its cancelled_unused_value is
--      0). Nothing changes; settle first, then refund.
--   3. A completed FOC whose FOC was taken off and that is not yet paid: a
--      line refund is refused (its benefit rows have no paid value: "There is
--      nothing left to refund on this invoice"), so the payment's re-issue
--      (416) has nothing to skip. Not a fault; noted because it was checked.
--   4. A part-paid package whose line was never settled has no benefit row:
--      a cancellation writes its released credit off
--      (writeoff_released_credit_on_close), a reopening queues nothing for it
--      (the payments release it again, 356), and its line cannot be refunded
--      by line before it is settled ("There is nothing left to refund on this
--      invoice"). So its credit never waits; noted because it was checked.
--   5. (found in review, 22 Oct 2026) A customer change that takes the
--      benefits along (the invoice form's customer change, "Move the unused
--      benefits to the new customer": correct_invoice, 'transfer'; 447's
--      area), made after a line was refunded by line, leaves that line's
--      refund with the old customer: its refunded voucher, and the refund's
--      'adjust_decrease' / 'invoice_benefit_refund' ledger row on the old
--      customer's lot (a line refunded whole leaves that lot empty, so it
--      does not move, with or without 447). If the invoice is then cancelled,
--      reopened and settled, the reopening queues that refund to be given
--      back (reopen_invoice) and the payment that settles it gives it to the
--      old customer: the credit is reinstated on the lot the row names
--      (apply_reopened_invoice_benefits), the voucher is replaced for the
--      original voucher's holder (apply_reopened_invoice_vouchers), while the
--      invoice, charged for that line again and paid, is the new customer's.
--      On the copy, with or without 447: two S$100 Credit Packages with a
--      S$10 Bonus, paid, line A refunded, the customer changed to a friend,
--      cancelled, reopened and paid: the invoice is the friend's, S$200 net,
--      and line A's S$110 is back with the buyer; two S$30 vouchers the same
--      way: line A's voucher is back with the buyer, S$60 net. A refund made
--      while the credit or the vouchers wait (this file) leaves the same
--      records as any line refund (for credit, an ordinary refund row), so
--      once the invoice is settled the same applies to it (checked: line A's
--      S$110, or its voucher, back with the buyer; before 446 the refunded
--      credit was reinstated at settlement instead, S$220 held for S$100
--      net). There before 446 and 447 and caused by neither: it is in
--      reopen_invoice and the two functions above, which neither file
--      changes. Production, 22 Oct 2026: the 3 customer changes that took
--      benefits along moved vouchers only (no credit lot was ever
--      reassigned), and no reopening ever queued a voucher; so it has never
--      happened, and there is nothing to repair. For the Owner, a separate
--      fix later: the reopening, or the payment that settles it, would give a
--      queued voucher or credit whose holder is no longer the invoice's
--      customer to the invoice's customer (credit through a reissued lot, as
--      445 and 447 do).
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the text built is the tested one (its AFTER md5);
--   * refund_invoice_recorded is its BEFORE (production, 22 Oct 2026) or this
--     file's AFTER (left alone, so a second run changes nothing); no other
--     function takes its name; its one caller is resolve_invoice_action_v2;
--   * the functions it relies on are as read on production (below); none of
--     them is 447's (447 changes move_invoice_benefits_to_customer only), and
--     447 neither changes nor pins refund_invoice_recorded, so the two go in
--     either order;
--   * invoice_reopen_vouchers' columns and constraints are as read, it has no
--     trigger and no column names it (so a row can be removed);
--     invoice_reopen_benefits' columns and constraints are as read and it has
--     no trigger (its rows are lowered or closed, never removed); the other
--     columns read and written are there with these types; the three
--     triggers on invoices that give the vouchers and reinstate the credit
--     when it is settled are as read;
--   * on the first run only (the BEFORE text in place): no queued voucher row
--     (waiting or given) has a line refund naming its benefit recorded after
--     it was queued, and no queued credit row has a line refund naming the
--     benefit of its lot recorded after it was queued and before it was
--     applied. Such a row is this fault already happened (a unit or credit
--     given again after it was refunded, or still waiting to be): what the
--     customer holds then needs a decision first, so the file stops, changing
--     nothing, and names the invoices. None on production (no voucher row
--     ever; the credit rows' one invoice had no line refund while they
--     waited). (A voucher row given is replaced by a new benefit row, which a
--     later refund names, so any refund naming the old one came while it
--     waited; credit is reinstated into the same lot, so its rows are bounded
--     by when they were applied.) A second run skips this: rows changed by
--     this file look the same, and the first run found none;
--   * who may call it is as read (signed-in staff and the service role,
--     compared as sets: production lists them in another order than a local
--     copy), and is kept.
--   Afterwards: the md5 is the AFTER one; the grants are as before. Then a
--   self-test, in a block that is always undone (it ends by raising P0446, so
--   it leaves no row): a made-up Owner, store, buyer (fictional phone no
--   customer has), S$30 voucher and S$100 Credit Package (S$10 Bonus). (a) Two
--   voucher lines of one, paid, cancelled, S$30 paid back, reopened (both
--   wait), line A refunded: A's queued row is removed, B's waits, the Audit
--   Log has the change; paid: the buyer holds 1 voucher, line B's, for S$30
--   net. (b) A voucher line of two, the same, one unit refunded: the queued
--   row is lowered to one; paid: 1 voucher held. (c) Two package lines, paid,
--   cancelled, line B's S$100 paid back, reopened (S$220 waits), line A
--   refunded: A's two queued rows (Paid and Bonus) are closed, each with its
--   reverse and its refund in the ledger, the lots do not move, B's S$110
--   waits, the Audit Log has both; paid: the buyer holds line B's S$110 for
--   S$100 net; cancelled again, the Reopen dialog would reinstate S$220 (the
--   refund counted once).
--   Its invoice numbers are counted, not drawn from a sequence; its credit
--   ledger rows draw entry numbers (a sequence, which an undone transaction
--   does not give back: a gap, which nothing counts), as 443's and 445's
--   self-tests do. Each run, a dry run or a second run too, leaves these
--   gaps. A second run changes nothing else.
--   Locks: refund_invoice_recorded's catalogue row, held to the end of the
--   apply; the rows the self-test writes and undoes. A refund running at that
--   moment finishes on the text it started with.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (... 444, 445, 449) -> 446. No page, Edge Function or
--   setting changes. 447 (customer change takes the invoice's records along, another
--   session) neither changes nor pins refund_invoice_recorded, and this file
--   neither changes nor pins move_invoice_benefits_to_customer, so 446 and
--   447 go in either order. 449 (the event website, another session; live
--   22 Oct 2026 05:25 UTC, 20261022052511, file md5 33508eab, fingerprint
--   6e368a7e) changes none of the functions this file changes or relies on,
--   and pins none it changes; 448 is unused.
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below, the second changes
--      nothing ("left alone").
--   2. Apply (the CLI, or the MCP's apply_migration with this text verbatim).
--      It checks itself.
--   Afterwards the re-run of 445 (it pins refund_invoice_recorded at
--   e6f6c3cb) refuses, changing nothing, where today it leaves all alone.
--   417, 436 and 438 pin it too, and their re-runs refuse already today on
--   other pins (417 on invoice_action_plan, 436 on record_invoice_payment,
--   438 on transfer_invoice_unused_benefit); 443's still leaves all alone
--   (each checked on a copy, 22 Oct 2026). All are applied, so nothing is
--   lost. scripts/xero/tests/sales-events.sql pins it too and already
--   refuses on a copy of production (its pins are older).
--
-- BEFORE (production, 22 Oct 2026, at 445; md5 of pg_get_functiondef with
-- search_path public)
--   changed
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)      e6f6c3cbf1bda3574d748bde2db5a759  (417's AFTER)
--   relied on, not changed
--   apply_reopened_invoice_vouchers()                                  71d50be41b73decceb0b20f8597dd4fa  (gives what still waits)
--   apply_reopened_invoice_benefits()                                  75489db2b12e60a3104fff9ef76c2d20  (reinstates what still waits)
--   reopen_invoice(uuid,text,uuid)                                     c9fcab7adfccdaeba1eb8dee4134ba47  (queues; 417: only what is more; credit by ledger row)
--   invoice_voucher_reopen_candidates(uuid)                            20405a96c8780eac6425a5dae59c29e1  (counts refunds since the last reopening)
--   invoice_reopen_preview_before_sessions(uuid)                       4723b49b3f27c17254c2987c4bebc17b  (the Reopen dialog's counts)
--   invoice_voucher_stock_unrecorded(uuid,boolean)                     91c8f0fa69ef6337f323b7ac467a8c2b  (counts waiting units as kept)
--   cancel_invoice_recorded(uuid,text,uuid)                            de52d9dbaef8ab15163bef35cb9d733d  (counts applied rows as replaced)
--   trg_issue_sold_vouchers_on_paid()                                  c840d0d2754e7a8e889848ea8269a293  (416; runs after the reopening's trigger)
--   transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)          7aebd7120bc3928db46df0941cb20889  (445's AFTER; no Move while anything waits)
--   resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean) 201f08ebf14a64cd88d411a7cfb4c9c4  (its one caller)
--   invoice_refund_options_before_sessions(uuid)                       bd3afcc79cd2f06f983607d54fed167c  (what the guided refund offers)
--   customer_credit_statement(uuid,date,date)                          1ba4a16a8208906f9e88efbc716bd1dd  (an 'invoice_reopen' reverse is credit returned)
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)       80c80d386a5241e63b353e35e13ef250  (the self-test)
--   record_invoice_payment(uuid,jsonb,uuid)                            9c70097ed4da614fb9dcc66fdfcdb7d6  (the self-test; 443's AFTER)
--   public function fingerprint, after 445                         83a90dbfc238c7f6048c8dc9e435d876 (1370 functions)
--   public function fingerprint, production now (449 in too)       6e368a7e6c22d186edc59798d1d31210 (1370 functions)
-- AFTER (for later guards)
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)      804ecd829cfecf713783a09a05d93c7e
--   public function fingerprint, worked out on a copy of production (22 Oct 2026):
--     after 445 -> 446 (a second run the same)                   8c2843f8a625b15a35c75d5e46988f82 (1370 functions: none new, none dropped)
--     after 445 -> 447 -> 446, or -> 446 -> 447                    fcd9ec302339119c8191aa1940b2e14b (1370 functions)
--     production now (449 in) -> 446 (a second run the same)     f7a8209c8e9d58b3cbffe963fdec226f (1370 functions)
--     production now (449 in) -> 447 -> 446, or -> 446 -> 447      9d2e2fdd5c26b214e5d1a0f867273aff (1370 functions)
--       (447: its comment lines move with the final text, not its code;
--       447 alone after 449 is e2fc58439246052d5ee15941c5d4ea64. Nothing
--       here pins 447.)
--
-- Test: scripts/invoices/tests/reopen-refund-waiting-446.sql (begin ...
-- rollback; it installs this file twice; -v nomig=1 where it is in). It
-- reproduces both faults first (where 446 is not in), then checks the fix.
-- Vouchers: two lines of one and a line of two refunded while waiting, with
-- a plain and a limited voucher (vouchers held, net received, stock), a
-- second cancel, reopen and payment (the refund counted once), a refund
-- while waiting then cancelled again before settling and reopened, an FOC
-- taken off then paid, cancelled and reopened, a Move (refused while units
-- wait, as before; after settling, moved and cancelled). Credit: a Credit
-- Package with and without a Bonus and a Premium Bundle, refunded whole
-- while waiting, part refunded (one S$40, then S$40 and the rest), cancelled
-- again before settling, a refund before the reopening as well as while
-- waiting, a part-paid package's released lot (settled, and never settled),
-- a Move while it waits; each settled, then cancelled, reopened and paid
-- again (the refund counted once), the ledger, the Audit Log and the
-- customer's statement. Refunds with nothing waiting (paid; a reopened
-- invoice already settled; a cancelled one) compared whole with and without
-- 446, the guided Refund in full and Cancel afterwards, both refusals, and
-- the NOT COVERED cases as KNOWN. scripts/invoices/tests/reopen-recancel-438.sql
-- checks its case U4 the fixed way where 446 is in.

set lock_timeout = '5s';

do $mig$
declare
  -- ── The function this changes: signature, BEFORE md5 (production, 22 Oct
  -- 2026: 417's AFTER), AFTER md5, and the text (as pg_get_functiondef gives
  -- it back with search_path public). ───────────────────────────────────────
  c_sig constant text := 'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)';
  c_before constant text := 'e6f6c3cbf1bda3574d748bde2db5a759';
  c_after constant text := '804ecd829cfecf713783a09a05d93c7e';
  c_def constant text :=
$def$CREATE OR REPLACE FUNCTION public.refund_invoice_recorded(p_invoice_id uuid, p_lines jsonb, p_sources jsonb, p_stock jsonb, p_reason text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare i public.invoices%rowtype; it public.invoice_items%rowtype; p public.invoice_payments%rowtype;
 m public.payment_methods%rowtype; b public.invoice_benefit_values%rowtype; l public.customer_credit_lots%rowtype;
 x jsonb; z jsonb; v_amount numeric; v_total numeric:=0; v_source_total numeric:=0; v_remaining numeric;
 v_line_paid numeric; v_refunded numeric; v_grant numeric; v_revoke numeric; a record; v_left numeric; v_take numeric;
 sm public.stock_movements%rowtype; sq int; dq int; nq int; v_resolved int; v_first boolean:=true;
 v_payload jsonb; v_hash text; v_request uuid; v_entry uuid; rv public.customer_reward_vouchers%rowtype; v_units int; v_reserved numeric;
 q446 public.invoice_reopen_vouchers%rowtype; v446_left int; v446_n int;
 qb446 public.invoice_reopen_benefits%rowtype; v446_c numeric; v446_amt numeric; v446_given numeric;
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can record a refund'; end if;
 if nullif(trim(p_reason),'') is null or p_request_id is null then raise exception 'Refund reason and request ID are required'; end if;
 select * into i from public.invoices where id=p_invoice_id for update;
 if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 -- 363: every therapy unit on the invoice and its voucher allowance are
 -- locked before any benefit or voucher stock is touched, in the order the
 -- Claim window takes them (unit, allowance, stock), so the two cannot wait
 -- on each other.
 perform 1 from public.purchased_therapy_entitlements
   where invoice_id=i.id and status not in ('cancelled','refunded') order by id for update;
 perform 1 from public.therapy_entitlements te
   where te.id in (select voucher_entitlement_id from public.purchased_therapy_entitlements
                    where invoice_id=i.id and status not in ('cancelled','refunded'))
   order by te.id for update;
 v_payload:=jsonb_build_object('lines',p_lines,'sources',p_sources,'stock',p_stock,'reason',p_reason);
 v_hash:=md5(v_payload::text);
 if exists(select 1 from public.invoice_refunds where invoice_id=i.id and request_id=p_request_id) then
   if not exists(select 1 from public.invoice_refunds where invoice_id=i.id and request_id=p_request_id and outcome->>'hash'=v_hash) then
     raise exception 'This refund request ID was already used for different details'; end if;
   return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'replayed',true);
 end if;
 if exists(select 1 from public.invoice_refunds where invoice_id=i.id and payment_id is null) then
   raise exception 'Historical refunds need payment-source review before another refund'; end if;
 if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_typeof(p_sources) is distinct from 'array'
   or jsonb_array_length(p_lines)=0 or jsonb_array_length(p_sources)=0 then raise exception 'Allocate the refund to lines and original payment sources'; end if;
 if exists(select j.value->>'invoice_item_id' from jsonb_array_elements(p_lines) j(value) group by 1 having count(*)>1) then raise exception 'Submit each refund line once'; end if;
 for x in select * from jsonb_array_elements(p_lines) loop
   v_amount:=round((x->>'amount')::numeric,2);
   if v_amount is null or v_amount<=0 then raise exception 'Refund amount must be positive'; end if;
   it:=null;
   if nullif(x->>'invoice_item_id','') is null then
     if public.invoice_untracked_voucher(i.id) or exists(select 1 from public.invoice_items where invoice_id=i.id and credit_issued_at is not null) then
       raise exception 'Allocate a correction refund to the original unused purchased benefits; it cannot be cashed out as an unallocated overpayment'; end if;
     -- 409: a cancelled invoice charges nothing any more, so all it still
     -- holds is the refund due (invoice_financial_position); a refunded one,
     -- what it holds above what is still charged. That money going back is
     -- this line. An open invoice is as before: only what was paid above
     -- its total.
     -- But a cancellation keeps what the customer already had (sessions
     -- delivered, therapy started, vouchers redeemed, credit spent: the guided
     -- cancellation leaves them out of its refund due), so on a cancelled
     -- invoice with any of that, not all the money held is owed back, and how
     -- much is has no rule yet: refused.
     -- 417 (the Owner, 9 Oct 2026): the Owner or Manager states how much is
     -- owed back when cancelling (cancel_refund_owed); up to that is recorded
     -- here (the total is checked below). A cancellation with no amount
     -- stated (made before this) is still refused.
     if i.status='cancelled' and i.cancel_refund_owed is null and cardinality(public.cancelled_invoice_used_value(i.id))>0 then
       raise exception 'Part of what % sold has been used (%), and no amount owed back was stated when it was cancelled, so not all the money it still holds is owed back. Nothing was recorded.',
         i.invoice_no, (select string_agg(case c when 'session_used' then 'sessions delivered'
                                         when 'therapy_activated' then 'therapy started or its vouchers collected'
                                         when 'voucher_redeemed' then 'vouchers redeemed' else 'credit spent' end, ', ')
                          from unnest(public.cancelled_invoice_used_value(i.id)) c); end if;
     if v_amount>greatest(public.invoice_net_received(i.id)-case when i.status='cancelled' then 0
          when i.status='refunded' then public.invoice_charge_total(i.id) else i.total_amount end,0) then
       raise exception 'Amount exceeds the correction refund due'; end if;
   else
     select * into it from public.invoice_items where id=(x->>'invoice_item_id')::uuid and invoice_id=i.id for update;
     if not found then raise exception 'Refund line does not belong to this invoice'; end if;
     if public.invoice_untracked_voucher(i.id,it.id) then
      raise exception 'This sold voucher has no source-linked unused/redemption record. Review the original issued units before refunding this line; stock movement alone is insufficient evidence.';
     end if;
     v_line_paid:=coalesce(public.invoice_discounted_line_value(it.id),0);
     select coalesce(sum((e->>'amount')::numeric),0) into v_refunded from public.invoice_refunds r,
       jsonb_array_elements(coalesce(r.outcome->'lines','[]')) e where r.invoice_id=i.id and (i.reopened_at is null or r.created_at>i.reopened_at) and e->>'invoice_item_id'=it.id::text;
     if coalesce((x->>'overpayment')::boolean,false) then
       if it.line_kind not in ('credit_package','premium_bundle') or v_amount>greatest(public.invoice_net_received(i.id)-i.total_amount,0) then
         raise exception 'Allocate correction overpayments to unused purchased benefits within the refund due'; end if;
     elsif v_amount>greatest(v_line_paid-v_refunded,0) then raise exception 'Refund exceeds the remaining discounted line value'; end if;
     if it.line_kind in ('credit_package','premium_bundle') or public.invoice_line_has_issued_vouchers(it.id) then
       if it.line_kind in ('credit_package','premium_bundle') then
         perform public.assert_invoice_credit_source_evidence(i.id,it.id);
       end if;
       if jsonb_typeof(x->'benefits') is distinct from 'array' or jsonb_array_length(x->'benefits')=0 then
         raise exception 'Select the recorded unused benefit allocations for this refund (credit, bundle or issued voucher units)'; end if;
       -- Benefit allocations cover the unused portion. Anything above that is
       -- an authorized exception and must say so in as many words.
       if (select coalesce(sum((q->>'amount')::numeric),0) from jsonb_array_elements(x->'benefits') q)<>v_amount then
         if nullif(x#>>'{override,reason}','') is null
            or coalesce(x->'override'->>'code','') not in ('credit_used','voucher_redeemed','larger_refund')
            or (x->'override'->>'amount') is null then
           raise exception 'Benefit refunds must equal the line refund'; end if;
         if round((x->'override'->>'amount')::numeric,2)<>v_amount then
           raise exception 'The authorized amount must match the refund allocated to this line'; end if;
         if (select coalesce(sum((q->>'amount')::numeric),0) from jsonb_array_elements(x->'benefits') q)>v_amount then
           raise exception 'Benefit reversals cannot exceed the refund for this line'; end if;
         perform public.write_audit_ex('invoice_items',it.id,'authorized_excess',null,
           jsonb_build_object('line_refund',v_amount,'benefit_backed',
             (select coalesce(sum((q->>'amount')::numeric),0) from jsonb_array_elements(x->'benefits') q),
             'excess',v_amount-(select coalesce(sum((q->>'amount')::numeric),0) from jsonb_array_elements(x->'benefits') q),
             'override',x->'override','request_id',p_request_id),
           'refunds',p_reason,i.store_id);
       end if;
       for z in select * from jsonb_array_elements(x->'benefits') loop
         select * into b from public.invoice_benefit_values where id=(z->>'benefit_id')::uuid and invoice_item_id=it.id for update;
         if not found then raise exception 'Recorded benefit allocation not found; historical allocations require review'; end if;
         if b.lot_id is not null then
           select * into l from public.customer_credit_lots where id=b.lot_id for update;
           v_grant:=(z->>'amount')::numeric;
           if v_grant is null or v_grant<=0 or b.paid_value<=0 or v_grant>round(b.paid_value*(l.remaining_amount+b.cancelled_unused_value)/b.granted_value,2) then
             raise exception 'Refund exceeds the unused paid value of this benefit'; end if;
           -- Taking the whole refundable value clears the balance exactly;
           -- deriving it back through a second rounding leaves a crumb.
           if v_grant>=round(b.paid_value*(l.remaining_amount+b.cancelled_unused_value)/b.granted_value,2) then
             v_revoke:=l.remaining_amount+b.cancelled_unused_value;
           else
             v_revoke:=least(l.remaining_amount+b.cancelled_unused_value,round(v_grant*b.granted_value/b.paid_value,2));
           end if;
           v_reserved:=least(b.cancelled_unused_value,v_revoke);
           update public.invoice_benefit_values set cancelled_unused_value=cancelled_unused_value-v_reserved where id=b.id;
           v_revoke:=v_revoke-v_reserved;
           update public.customer_credit_lots set remaining_amount=remaining_amount-v_revoke,updated_at=now() where id=l.id;
           if v_revoke>0 then
           insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
            values(l.wallet_id,l.customer_id,'adjust_decrease',l.category,v_revoke,l.id,'invoice_benefit_refund',p_request_id,l.store_id,p_reason,auth.uid(),auth.uid());
           end if;
           -- 446 (the Owner, 22 Oct 2026): the credit a cancellation took back
           -- may be waiting to be reinstated, on a reopened invoice not yet
           -- settled (invoice_reopen_benefits, not applied). What this refund
           -- took off cancelled_unused_value comes off that queue too, the
           -- most recently queued first, as if that part had been reinstated
           -- and then refunded: the queued row gives it now ('reverse', as the
           -- payment that settles the invoice would) and the refund takes it
           -- back ('adjust_decrease', invoice_benefit_refund), so the lot and
           -- the customer's statement end where they were, the payment that
           -- settles the invoice reinstates only the rest
           -- (apply_reopened_invoice_benefits), and a later reopening gives
           -- the refunded part back once, from the refund's own row, as it does
           -- for any refund since the last reopening. A row given in full is
           -- closed as applied, not removed: a reopening queues every credit
           -- row not queued yet, so a removed row would come back whole, on top
           -- of the refund's row. Each change is in the invoice's Audit Log.
           v446_c:=v_reserved; v446_given:=0;
           for qb446 in select q.* from public.invoice_reopen_benefits q
                          join public.customer_credit_ledger e on e.id=q.source_ledger_id
                         where q.invoice_id=i.id and q.applied_at is null and e.lot_id=l.id
                         order by q.created_at desc,q.id desc for update of q loop
             exit when v446_c<=0;
             v446_amt:=least(qb446.amount,v446_c);
             if v446_amt=qb446.amount then
               update public.invoice_reopen_benefits set applied_at=now() where id=qb446.id;
             else
               update public.invoice_reopen_benefits set amount=amount-v446_amt where id=qb446.id;
             end if;
             insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,reverses_entry_id,created_by,approved_by)
              values(l.wallet_id,l.customer_id,'reverse',l.category,v446_amt,l.id,'invoice_reopen',qb446.request_id,l.store_id,
                'Reopened invoice: refunded before it was settled',qb446.source_ledger_id,auth.uid(),auth.uid());
             perform public.write_audit_ex('invoices',i.id,'reopen_credit_refunded',to_jsonb(qb446),
               jsonb_build_object('reopen_benefit_id',qb446.id,'benefit_id',b.id,'lot_id',l.id,'refunded_amount',v446_amt,
                 'still_waiting',qb446.amount-v446_amt,'request_id',p_request_id),
               'refunds',p_reason,i.store_id);
             v446_c:=v446_c-v446_amt; v446_given:=v446_given+v446_amt;
           end loop;
           if v446_given>0 then
             insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
              values(l.wallet_id,l.customer_id,'adjust_decrease',l.category,v446_given,l.id,'invoice_benefit_refund',p_request_id,l.store_id,p_reason,auth.uid(),auth.uid());
           end if;
         else
           select * into rv from public.customer_reward_vouchers where id=b.reward_voucher_id for update;
           v_grant:=(z->>'amount')::numeric;
           v_remaining:=case when rv.status='held' then rv.quantity else 0 end+b.cancelled_unused_value;
           if v_grant is null or v_grant<=0 or b.paid_value<=0 or v_grant>round(b.paid_value*v_remaining/b.granted_value,2) then
             raise exception 'Refund exceeds the unused paid value of this voucher'; end if;
           v_units:=round(v_grant*b.granted_value/b.paid_value)::int;
           if v_units<=0 or round(v_units*b.paid_value/b.granted_value,2)<>v_grant then
             raise exception 'Voucher refund must cover whole unused units at their allocated paid value'; end if;
           v_reserved:=least(b.cancelled_unused_value,v_units);
           update public.invoice_benefit_values set cancelled_unused_value=cancelled_unused_value-v_reserved where id=b.id;
           -- 446 (the Owner, 22 Oct 2026): the units a cancellation took back
           -- may be waiting to be given again, on a reopened invoice not yet
           -- settled (invoice_reopen_vouchers, not applied). Refunded here, they
           -- come off that queue too, the most recently queued first, so the
           -- payment that settles the invoice gives only the rest
           -- (apply_reopened_invoice_vouchers). A row left with nothing is
           -- removed; each change is in the invoice's Audit Log. Taken off, not
           -- marked as given: 417's cancellation counts a unit given again as
           -- replaced and would give its stock back a second time. A later
           -- reopening counts this refund once, as it counts every refund since
           -- the last reopening (invoice_voucher_reopen_candidates).
           v446_left:=v_reserved::int;
           for q446 in select * from public.invoice_reopen_vouchers
                        where benefit_id=b.id and applied_at is null
                        order by created_at desc,id desc for update loop
             exit when v446_left<=0;
             v446_n:=least(q446.quantity,v446_left);
             if v446_n=q446.quantity then
               delete from public.invoice_reopen_vouchers where id=q446.id;
             else
               update public.invoice_reopen_vouchers set quantity=quantity-v446_n where id=q446.id;
             end if;
             perform public.write_audit_ex('invoices',i.id,'reopen_voucher_refunded',to_jsonb(q446),
               jsonb_build_object('reopen_voucher_id',q446.id,'benefit_id',b.id,'refunded_units',v446_n,
                 'still_waiting',q446.quantity-v446_n,'request_id',p_request_id),
               'refunds',p_reason,i.store_id);
             v446_left:=v446_left-v446_n;
           end loop;
           v_units:=v_units-v_reserved::int;
           if v_units>0 then
             update public.customer_reward_vouchers set status=case when quantity=v_units then 'revoked' else status end,
               quantity=case when quantity=v_units then quantity else quantity-v_units end,
               notes=concat_ws(E'\n',notes,'Refunded '||v_units||' unused unit(s): '||p_reason) where id=rv.id;
             if exists(select 1 from public.vouchers where id=rv.voucher_id and qty_type='limited') then
               update public.voucher_store_stock set current_qty=current_qty+v_units where store_id=rv.store_id and voucher_id=rv.voucher_id;
             end if;
             perform public.write_audit_ex('customer_reward_vouchers',rv.id,'unused_voucher_refund',to_jsonb(rv),
               jsonb_build_object('revoked_units',v_units,'request_id',p_request_id),'refunds',p_reason,rv.store_id);
           end if;
         end if;
       end loop;
     elsif it.therapy_service_id is not null then
       perform public.refund_invoice_therapy_sessions(it.id,v_amount,p_reason,p_request_id);
     elsif it.line_kind='therapy' then
       -- 359: used = therapy started or ended, or vouchers already collected.
       if exists(select 1 from public.purchased_therapy_entitlements where invoice_item_id=it.id and public.therapy_unit_consumed(id)) then
         -- Activated. Only an explicitly authorized termination may proceed.
         if nullif(x#>>'{override,reason}','') is null or coalesce(x->'override'->>'code','')<>'therapy_activated' then
           raise exception 'Consumed or activated therapy cannot be refunded'; end if;
         if (x->'override'->>'amount') is null then
           raise exception 'No unused-period valuation exists for an activated entitlement. An Owner or Manager must state the refund amount with a reason.'; end if;
         if round((x->'override'->>'amount')::numeric,2)<>v_amount then
           raise exception 'The authorized termination amount must match the refund allocated to this line'; end if;
         for a in select * from public.purchased_therapy_entitlements
                   where invoice_item_id=it.id and public.therapy_unit_consumed(id) for update loop
           update public.purchased_therapy_entitlements set status='refunded',updated_by=auth.uid(),updated_at=now() where id=a.id;
           update public.commissions set status='reversed',reversal_reason='Therapy terminated on authorized override: '||p_reason
            where invoice_item_id=it.id and status='earned';
           perform public.write_audit_ex('purchased_therapy_entitlements',a.id,'authorized_termination',
             jsonb_build_object('status',a.status,'activation_date',a.activation_date,'expiry_date',a.expiry_date),
             jsonb_build_object('status','refunded','override',x->'override','request_id',p_request_id,'amount',v_amount),
             'refunds',p_reason,i.store_id);
         end loop;
       else
         if v_amount<>greatest(v_line_paid-v_refunded,0) then raise exception 'Refund the whole unused therapy entitlement'; end if;
         update public.purchased_therapy_entitlements set status='refunded',updated_at=now() where invoice_item_id=it.id and status in ('pending_activation','scheduled');
       end if;
     end if;
   end if;
   -- 363: a promotion (or bundle) line refunded in full closes the therapy it
   -- granted; used units only on the 'therapy_activated' override, for the
   -- amount refunded on this line. A part refund by amount leaves it. The
   -- guided flow has already closed exactly what its reviewed plan listed.
   if it.id is not null and it.line_kind::text<>'therapy'
      and coalesce(current_setting('invoice.therapy_reviewed',true),'') is distinct from p_request_id::text
      and not coalesce((x->>'overpayment')::boolean,false)
      and v_amount>=greatest(v_line_paid-v_refunded,0)
      and exists(select 1 from public.purchased_therapy_entitlements
                  where invoice_item_id=it.id and status not in ('cancelled','refunded')) then
     if coalesce(x->'override'->>'code','')='therapy_activated'
        and (x->'override'->>'amount') is not null
        and round((x->'override'->>'amount')::numeric,2)<>v_amount
        and exists(select 1 from public.purchased_therapy_entitlements
                    where invoice_item_id=it.id and status not in ('cancelled','refunded') and public.therapy_unit_consumed(id)) then
       raise exception 'The authorized termination amount must match the refund allocated to this line'; end if;
     perform public.close_invoice_therapy_units(i.id,it.id,null,x->'override',v_amount,p_reason,p_request_id,'refund');
   end if;
   if it.id is not null and it.line_kind in ('product','promotion') and jsonb_array_length(coalesce(p_stock,'[]'))=0
    and exists(select 1 from public.stock_movements qs where qs.invoice_id=i.id and qs.movement_type::text='store_sale'
      and qs.quantity>coalesce((select sum(d.sellable_quantity+d.damaged_quantity+d.not_returned_quantity) from public.invoice_stock_dispositions d where d.movement_id=qs.id),0)
       +coalesce((select sum(v.quantity) from public.stock_movements v where v.reversed_sale_id=qs.id and v.movement_type::text='invoice_cancel_return'),0)) then
     raise exception 'Record the returned-and-sellable, damaged, or not-returned quantities for this product refund'; end if;
   v_total:=v_total+v_amount;
 end loop;
 if v_total>public.invoice_net_received(i.id) then raise exception 'Refund exceeds net payments still held'; end if;
 -- 417: on a cancelled invoice whose customer had part of it, no more than the
 -- amount stated as owed back; the rest is kept for what was used.
 if i.status='cancelled' and i.cancel_refund_owed is not null and v_total>i.cancel_refund_owed then
   raise exception 'That is more than the S$% still owed back on %. The rest is kept for what the customer used. Nothing was recorded.',
     to_char(i.cancel_refund_owed,'FM999999990.00'), i.invoice_no; end if;
 for x in select * from jsonb_array_elements(p_sources) loop
   select * into p from public.invoice_payments where id=(x->>'payment_id')::uuid and invoice_id=i.id for update;
   if not found or p.entry_kind='correction_reversal' or exists(select 1 from public.invoice_payments where corrects_payment_id=p.id and entry_kind='correction_reversal') then
     raise exception 'Choose a current original payment source'; end if;
   select * into m from public.payment_methods where id=p.payment_method_id;
   v_amount:=round((x->>'amount')::numeric,2);
   v_remaining:=public.invoice_payment_remaining(p.id);
   if v_amount is null or v_amount<=0 or v_amount>v_remaining then raise exception 'Refund exceeds the remaining amount for this payment'; end if;
   if coalesce(m.is_wallet_credit,false) then
     v_left:=v_amount;
     for a in select * from public.invoice_line_credit_allocations where payment_id=p.id and amount>reversed_amount order by id for update loop
       exit when v_left<=0;
       v_take:=least(v_left,a.amount-a.reversed_amount);
       select * into l from public.customer_credit_lots where id=a.lot_id for update;
       update public.customer_credit_lots set remaining_amount=remaining_amount+v_take,status='active',updated_at=now() where id=l.id;
       insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,reverses_entry_id,created_by,approved_by)
         values(l.wallet_id,l.customer_id,'reverse',l.category,v_take,l.id,'invoice_payment_refund',p_request_id,l.store_id,p_reason,a.ledger_entry_id,auth.uid(),auth.uid());
       update public.invoice_line_credit_allocations set reversed_amount=reversed_amount+v_take where id=a.id;
       v_left:=v_left-v_take;
     end loop;
     if v_left>0 then raise exception 'Legacy wallet payment has no exact source allocation; review is required'; end if;
   end if;
   insert into public.invoice_refunds(invoice_id,payment_id,amount,reason,kind,refunded_by,request_id,credit_returned,outcome,created_at)
    values(i.id,p.id,v_amount,p_reason,'allocated',auth.uid(),p_request_id,case when m.is_wallet_credit then v_amount else 0 end,
      jsonb_build_object('hash',v_hash)||case when v_first then jsonb_build_object('lines',p_lines,'stock',p_stock) else '{}'::jsonb end,clock_timestamp());
   v_first:=false; v_source_total:=v_source_total+v_amount;
 end loop;
 if v_source_total<>v_total then raise exception 'Payment-source allocations must equal the refund total'; end if;
 for x in select * from jsonb_array_elements(coalesce(p_stock,'[]')) loop
   select * into sm from public.stock_movements where id=(x->>'movement_id')::uuid and invoice_id=i.id and movement_type::text='store_sale' for update;
   if not found then raise exception 'Stock return must reference an actual invoice deduction'; end if;
   sq:=coalesce((x->>'sellable_quantity')::int,0); dq:=coalesce((x->>'damaged_quantity')::int,0); nq:=coalesce((x->>'not_returned_quantity')::int,0);
   select coalesce(sum(sellable_quantity+damaged_quantity+not_returned_quantity),0) into v_resolved from public.invoice_stock_dispositions where movement_id=sm.id;
   v_resolved:=v_resolved+coalesce((select sum(quantity) from public.stock_movements where reversed_sale_id=sm.id and movement_type::text='invoice_cancel_return'),0);
   if sq<0 or dq<0 or nq<0 or sq+dq+nq<=0 or sq+dq+nq>sm.quantity-v_resolved then raise exception 'Stock disposition exceeds the unresolved deduction'; end if;
   if exists(select 1 from public.stock_movements where invoice_id=i.id and product_id=sm.product_id and reversed_sale_id is null and movement_type::text in ('invoice_cancel_return','invoice_refund_return','refund_return'))
      and not exists(select 1 from public.invoice_stock_dispositions where invoice_id=i.id and movement_id=sm.id) then
     raise exception 'Historical stock returns require source review before another return'; end if;
   insert into public.invoice_stock_dispositions(invoice_id,movement_id,request_id,sellable_quantity,damaged_quantity,not_returned_quantity,reason,created_by)
    values(i.id,sm.id,p_request_id,sq,dq,nq,p_reason,auth.uid());
   if sq>0 then
     update public.store_inventory set current_qty=current_qty+sq,updated_at=now() where store_id=sm.from_store_id and product_id=sm.product_id;
     if not found then raise exception 'Original stock location no longer exists'; end if;
     insert into public.stock_movements(product_id,movement_type,to_store_id,invoice_id,quantity,notes,created_by,reversed_sale_id)
      values(sm.product_id,'invoice_refund_return',sm.from_store_id,i.id,sq,'Confirmed sellable return: '||p_reason,auth.uid(),sm.id);
   end if;
 end loop;
 -- 417: what is recorded here comes off the amount still owed back.
 update public.invoices set cancel_refund_owed=case when status='cancelled' and cancel_refund_owed is not null
                                                    then greatest(cancel_refund_owed-v_total,0) else cancel_refund_owed end,
   paid_amount=public.invoice_net_received(i.id),
   status=case when status<>'cancelled' and public.invoice_charge_total(i.id)<=0 then 'refunded'::invoice_status else status end where id=i.id;
 -- 327: only when the refund has closed the invoice out entirely.
 if (select status from public.invoices where id=i.id) in ('refunded','cancelled') then
   perform public.writeoff_released_credit_on_close(i.id, p_reason, 'refund');
   -- 363: unused therapy no line holds (a correction deleted its line) closes
   -- with a fully refunded invoice, as a cancellation closes it, on every path
   -- (the guided flow has usually closed it already, as its plan listed).
   -- Units still on a line follow their line. Locked first, then checked.
   if true then
     perform 1 from public.purchased_therapy_entitlements
       where invoice_id=i.id and invoice_item_id is null and status in ('pending_activation','scheduled')
       order by id for update;
     perform 1 from public.therapy_entitlements te
       where te.id in (select voucher_entitlement_id from public.purchased_therapy_entitlements
                        where invoice_id=i.id and invoice_item_id is null and status in ('pending_activation','scheduled'))
       order by te.id for update;
     for a in select * from public.purchased_therapy_entitlements
               where invoice_id=i.id and invoice_item_id is null and status in ('pending_activation','scheduled')
                 and not public.therapy_unit_consumed(id) loop
       update public.purchased_therapy_entitlements set status='refunded',updated_by=auth.uid(),updated_at=now() where id=a.id;
       perform public.write_audit_ex('purchased_therapy_entitlements',a.id,'closed_with_invoice',
         jsonb_build_object('status',a.status,'invoice_item_id',a.invoice_item_id),
         jsonb_build_object('status','refunded','request_id',p_request_id),'refunds',p_reason,i.store_id);
     end loop;
   end if;
 end if;
 -- 393: its items still waiting for a warehouse follow the refund: all
 -- cancelled when it closes the invoice, otherwise as staff answered.
 perform public.settle_waiting_special_docs_on_refund(i.id,p_lines,p_reason);
 perform public.reconcile_invoice_commissions(i.id,'Refund: '||p_reason);
 perform public.write_audit_ex('invoices',i.id,'allocated_refund',null,v_payload,'refunds',p_reason,i.store_id);
 return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'refunded_amount',v_total);
end $function$
$def$;
  -- Who may call it: signed-in staff and the server (as read; kept).
  c_acl constant text := '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}';
  -- The functions whose text calls it, as read: the guided Refund / Cancel.
  c_callers constant text[] := array['resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)'];

  -- ── Relied on, not changed (production, 22 Oct 2026) ─────────────────────
  c_relied constant text[] := array[
    'apply_reopened_invoice_vouchers()',
    'apply_reopened_invoice_benefits()',
    'reopen_invoice(uuid,text,uuid)',
    'invoice_voucher_reopen_candidates(uuid)',
    'invoice_reopen_preview_before_sessions(uuid)',
    'invoice_voucher_stock_unrecorded(uuid,boolean)',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'trg_issue_sold_vouchers_on_paid()',
    'transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)',
    'resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)',
    'invoice_refund_options_before_sessions(uuid)',
    'customer_credit_statement(uuid,date,date)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    'record_invoice_payment(uuid,jsonb,uuid)'];
  c_relied_md5 constant text[] := array[
    '71d50be41b73decceb0b20f8597dd4fa',
    '75489db2b12e60a3104fff9ef76c2d20',
    'c9fcab7adfccdaeba1eb8dee4134ba47',
    '20405a96c8780eac6425a5dae59c29e1',
    '4723b49b3f27c17254c2987c4bebc17b',
    '91c8f0fa69ef6337f323b7ac467a8c2b',
    'de52d9dbaef8ab15163bef35cb9d733d',
    'c840d0d2754e7a8e889848ea8269a293',
    '7aebd7120bc3928db46df0941cb20889',
    '201f08ebf14a64cd88d411a7cfb4c9c4',
    'bd3afcc79cd2f06f983607d54fed167c',
    '1ba4a16a8208906f9e88efbc716bd1dd',
    'c705c733e213a27f0dc32d54322cc855',
    '80c80d386a5241e63b353e35e13ef250',
    '9c70097ed4da614fb9dcc66fdfcdb7d6'];

  -- ── Tables and columns, as read on 22 Oct 2026 ───────────────────────────
  c_q_cols constant text :=
    'id uuid, invoice_id uuid, benefit_id uuid, request_id uuid, quantity integer, replacement_voucher_id uuid, '
    'created_at timestamp with time zone, applied_at timestamp with time zone';
  c_q_cons constant text :=
    'invoice_reopen_vouchers_benefit_id_fkey FOREIGN KEY (benefit_id) REFERENCES invoice_benefit_values(id) | '
    'invoice_reopen_vouchers_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES invoices(id) | '
    'invoice_reopen_vouchers_invoice_id_request_id_benefit_id_key UNIQUE (invoice_id, request_id, benefit_id) | '
    'invoice_reopen_vouchers_pkey PRIMARY KEY (id) | '
    'invoice_reopen_vouchers_quantity_check CHECK ((quantity > 0)) | '
    'invoice_reopen_vouchers_replacement_voucher_id_fkey FOREIGN KEY (replacement_voucher_id) REFERENCES customer_reward_vouchers(id)';
  c_qb_cols constant text :=
    'id uuid, invoice_id uuid, source_ledger_id uuid, request_id uuid, amount numeric(12,2), '
    'applied_at timestamp with time zone, created_by uuid, created_at timestamp with time zone';
  c_qb_cons constant text :=
    'invoice_reopen_benefits_amount_check CHECK ((amount > (0)::numeric)) | '
    'invoice_reopen_benefits_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) | '
    'invoice_reopen_benefits_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES invoices(id) | '
    'invoice_reopen_benefits_pkey PRIMARY KEY (id) | '
    'invoice_reopen_benefits_source_ledger_id_fkey FOREIGN KEY (source_ledger_id) REFERENCES customer_credit_ledger(id) | '
    'invoice_reopen_benefits_source_ledger_id_key UNIQUE (source_ledger_id)';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  r record; v text; d text; i int; v_acl text;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_vch uuid; t_buyer uuid;
  t_inv uuid; t_pay uuid; t_a uuid; t_ba uuid; t_q uuid;
  t_pk uuid; t_b uuid; t_req uuid; t_alots uuid[]; t_blots uuid[]; t_aq uuid[];
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The text is the tested one.
  if md5(c_def) <> c_after then
    raise exception '446: the text of public.% is not the tested one (md5 %)', c_sig, md5(c_def); end if;

  -- refund_invoice_recorded is its BEFORE or this file's AFTER; no other
  -- function takes its name.
  if to_regprocedure('public.' || c_sig) is null then
    raise exception '446: public.% is missing', c_sig; end if;
  d := md5(pg_get_functiondef(to_regprocedure('public.' || c_sig)));
  if d <> c_after and d <> c_before then
    raise exception '446: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', c_sig, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'refund_invoice_recorded'
     and p.oid::regprocedure::text <> c_sig;
  if v is not null then raise exception '446: another function takes the name refund_invoice_recorded: %', v; end if;

  -- The functions relied on are as read on production (22 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '446: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if to_regprocedure('auth.uid()') is null then raise exception '446: auth.uid() must be there'; end if;

  -- Only resolve_invoice_action_v2 calls it, so its answer needs no other
  -- caller checked. (A session's own temporary functions, a test suite's
  -- helpers, are not counted.)
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'refund_invoice_recorded\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and not (p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = c_sig);
  if v is distinct from array_to_string(c_callers, ', ') then
    raise exception '446: the functions that call refund_invoice_recorded are not as read on 22 Oct 2026 (%); check each, then re-test', v; end if;

  -- The queue: its columns and constraints as read; no trigger on it and no
  -- column naming it, so a row of it can be removed.
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), ', ' order by a.attnum) into v
    from pg_attribute a
   where a.attrelid = to_regclass('public.invoice_reopen_vouchers') and a.attnum > 0 and not a.attisdropped;
  if v is distinct from c_q_cols then
    raise exception '446: invoice_reopen_vouchers'' columns are not as read on 22 Oct 2026: %', v; end if;
  select string_agg(k.conname || ' ' || pg_get_constraintdef(k.oid), ' | ' order by k.conname) into v
    from pg_constraint k where k.conrelid = 'public.invoice_reopen_vouchers'::regclass;
  if v is distinct from c_q_cons then
    raise exception '446: invoice_reopen_vouchers'' constraints are not as read on 22 Oct 2026: %', v; end if;
  if exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoice_reopen_vouchers'::regclass and not t.tgisinternal) then
    raise exception '446: invoice_reopen_vouchers has a trigger it did not have on 22 Oct 2026'; end if;
  if exists (select 1 from pg_constraint k where k.confrelid = 'public.invoice_reopen_vouchers'::regclass) then
    raise exception '446: a column now names invoice_reopen_vouchers rows (it had none on 22 Oct 2026); decide what removing a row does to it, then re-test'; end if;
  -- The credit queue: its columns and constraints as read; no trigger on it
  -- (its rows are lowered or closed, never removed).
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), ', ' order by a.attnum) into v
    from pg_attribute a
   where a.attrelid = to_regclass('public.invoice_reopen_benefits') and a.attnum > 0 and not a.attisdropped;
  if v is distinct from c_qb_cols then
    raise exception '446: invoice_reopen_benefits'' columns are not as read on 22 Oct 2026: %', v; end if;
  select string_agg(k.conname || ' ' || pg_get_constraintdef(k.oid), ' | ' order by k.conname) into v
    from pg_constraint k where k.conrelid = 'public.invoice_reopen_benefits'::regclass;
  if v is distinct from c_qb_cons then
    raise exception '446: invoice_reopen_benefits'' constraints are not as read on 22 Oct 2026: %', v; end if;
  if exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoice_reopen_benefits'::regclass and not t.tgisinternal) then
    raise exception '446: invoice_reopen_benefits has a trigger it did not have on 22 Oct 2026'; end if;
  -- The other columns read.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('invoice_refunds', 'invoice_id', 'uuid'), ('invoice_refunds', 'outcome', 'jsonb'),
                 ('invoice_refunds', 'created_at', 'timestamp with time zone'),
                 ('invoice_benefit_values', 'id', 'uuid'),
                 ('invoice_benefit_values', 'cancelled_unused_value', 'numeric(12,2)'),
                 ('invoice_benefit_values', 'lot_id', 'uuid'),
                 ('customer_credit_ledger', 'lot_id', 'uuid'), ('customer_credit_ledger', 'amount', 'numeric(12,2)'),
                 ('customer_credit_ledger', 'source_type', 'text'), ('customer_credit_ledger', 'source_record_id', 'uuid'),
                 ('customer_credit_ledger', 'reverses_entry_id', 'uuid')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '446: these columns are missing or not as read on 22 Oct 2026: %', v; end if;
  if (select pg_get_constraintdef(k.oid) from pg_constraint k
       where k.conrelid = 'public.customer_credit_ledger'::regclass and k.conname = 'customer_credit_ledger_entry_type_check')
     is distinct from 'CHECK ((entry_type = ANY (ARRAY[''grant''::text, ''use''::text, ''reverse''::text, ''adjust_increase''::text, ''adjust_decrease''::text])))' then
    raise exception '446: the credit ledger''s entry types are not as read on 22 Oct 2026'; end if;
  -- The settling payment gives what waits (the reopening's triggers), then
  -- 416's runs after them.
  for r in select * from (values
      ('invoice_reopen_benefits_settled', 'CREATE TRIGGER invoice_reopen_benefits_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_benefits()'),
      ('invoice_reopen_vouchers_settled', 'CREATE TRIGGER invoice_reopen_vouchers_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_vouchers()'),
      ('issue_sold_vouchers_on_paid',     'CREATE TRIGGER issue_sold_vouchers_on_paid AFTER UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_issue_sold_vouchers_on_paid()')) x(tg, def)
  loop
    if (select pg_get_triggerdef(t.oid) from pg_trigger t
         where t.tgrelid = 'public.invoices'::regclass and t.tgname = r.tg and t.tgenabled = 'O') is distinct from r.def then
      raise exception '446: the trigger % on public.invoices is not the one read on 22 Oct 2026', r.tg; end if;
  end loop;

  -- On the first run: no queued row whose benefit a line refund named after it
  -- was queued (the fault already happened). None on 22 Oct 2026 (the queue
  -- has never had a row). One needs a decision on what the customer holds,
  -- so nothing is changed. (A second run skips this: the rows this file
  -- lowers look the same.)
  if d = c_before then
    select count(distinct q.invoice_id), string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into i, v
      from public.invoice_reopen_vouchers q
      join public.invoices iv on iv.id = q.invoice_id
     where exists (select 1 from public.invoice_refunds rf
                    cross join lateral jsonb_array_elements(case when jsonb_typeof(rf.outcome->'lines') = 'array'
                                                                 then rf.outcome->'lines' else '[]'::jsonb end) x
                    cross join lateral jsonb_array_elements(case when jsonb_typeof(x->'benefits') = 'array'
                                                                 then x->'benefits' else '[]'::jsonb end) z
                    where rf.invoice_id = q.invoice_id and z->>'benefit_id' = q.benefit_id::text
                      and rf.created_at > q.created_at);
    if i > 0 then
      raise exception '446: % invoice(s) had a voucher line refunded while their reopened vouchers waited (%): the refunded units were, or will be, given again. Decide what each customer should hold, then apply. Nothing was changed.', i, v; end if;
    -- Credit: a line refund naming the benefit of a queued row's lot, recorded
    -- after the row was queued and before it was applied (credit is
    -- reinstated into the same lot, so a refund after that is an ordinary
    -- one). None on 22 Oct 2026 (4 rows, one invoice, no refund while they
    -- waited).
    select count(distinct q.invoice_id), string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into i, v
      from public.invoice_reopen_benefits q
      join public.customer_credit_ledger e on e.id = q.source_ledger_id
      join public.invoices iv on iv.id = q.invoice_id
     where exists (select 1 from public.invoice_refunds rf
                    cross join lateral jsonb_array_elements(case when jsonb_typeof(rf.outcome->'lines') = 'array'
                                                                 then rf.outcome->'lines' else '[]'::jsonb end) x
                    cross join lateral jsonb_array_elements(case when jsonb_typeof(x->'benefits') = 'array'
                                                                 then x->'benefits' else '[]'::jsonb end) z
                    join public.invoice_benefit_values bv on bv.id::text = z->>'benefit_id'
                    where rf.invoice_id = q.invoice_id and bv.lot_id = e.lot_id
                      and rf.created_at > q.created_at and (q.applied_at is null or rf.created_at < q.applied_at));
    if i > 0 then
      raise exception '446: % invoice(s) had a credit line refunded while their reopened credit waited (%): the refunded credit was, or will be, reinstated. Decide what each customer should hold, then apply. Nothing was changed.', i, v; end if;
  end if;

  -- Who may call it, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  select coalesce(proacl::text, '') into v_acl from pg_proc where oid = to_regprocedure('public.' || c_sig);
  if (select array_agg(x::text order by x::text) from unnest(nullif(v_acl, '')::aclitem[]) x)
     is distinct from (select array_agg(x::text order by x::text) from unnest(c_acl::aclitem[]) x) then
    raise exception '446: who may call public.% is not as read on 22 Oct 2026 (%)', c_sig, v_acl; end if;

  -- ── Change ──────────────────────────────────────────────────────────────
  if d <> c_after then
    execute c_def;
  else
    raise notice '446: refund_invoice_recorded already this version; left alone';
  end if;

  -- ── Afterwards ──────────────────────────────────────────────────────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_after then
    raise exception '446: public.% was installed with an md5 other than the tested one', c_sig; end if;
  if (select coalesce(proacl::text, '') from pg_proc where oid = to_regprocedure('public.' || c_sig)) is distinct from v_acl
     or has_function_privilege('anon', to_regprocedure('public.' || c_sig), 'execute')
     or not has_function_privilege('authenticated', to_regprocedure('public.' || c_sig), 'execute')
     or not has_function_privilege('service_role', to_regprocedure('public.' || c_sig), 'execute') then
    raise exception '446: the grants of public.% changed', c_sig; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("446 check", @example.invalid, fictional phones no
  -- customer uses); it ends by raising P0446, which undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from unnest(array['+61491570946', '+61491570947', '+61491570948', '+61491570949']) p
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p limit 1);
    if coalesce(cardinality(t_phones), 0) < 1 then raise exception '446: the self-test found no unused fictional phone'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '446-check-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '446 check', '446-check-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('446 check ' || t_sfx, '446-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('446 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.customers (full_name, phone) values ('446 Check Buyer ' || t_sfx, t_phones[1]) returning id into t_buyer;
    insert into public.vouchers (name, code, voucher_kind, selling_price, qty_type, is_active)
    values ('446 check ' || t_sfx, '446-' || t_sfx, 'normal', 30, 'unlimited', true) returning id into t_vch;
    insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store) values (t_vch, t_store, 30, true);

    -- (a) Two lines of one: paid, cancelled, S$30 paid back, reopened (both
    -- wait), line A refunded while they wait, the S$30 outstanding paid.
    t_inv := public.create_invoice(t_store, t_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', t_vch, 'quantity', 1),
                        jsonb_build_object('kind', 'voucher', 'voucher_id', t_vch, 'quantity', 1)));
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)), gen_random_uuid());
    perform public.cancel_invoice_recorded(t_inv, '446 check', gen_random_uuid());
    select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1;
    perform public.refund_invoice_recorded(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 30)),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 30)), '[]'::jsonb, '446 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '446 check', gen_random_uuid());
    if (select status::text from public.invoices where id = t_inv) is distinct from 'partially_paid'
       or (select count(*) from public.invoice_reopen_vouchers where invoice_id = t_inv and applied_at is null and quantity = 1) <> 2 then
      raise exception '446: the self-test''s invoice is not reopened part-paid with its two vouchers waiting'; end if;
    select it.id into t_a from public.invoice_items it where it.invoice_id = t_inv order by it.id limit 1;
    select b.id into t_ba from public.invoice_benefit_values b where b.invoice_item_id = t_a and b.reward_voucher_id is not null;
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', t_a, 'amount', 30,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_ba, 'amount', 30)))),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 30)), '[]'::jsonb, '446 check', gen_random_uuid());
    if exists (select 1 from public.invoice_reopen_vouchers where benefit_id = t_ba)
       or (select count(*) from public.invoice_reopen_vouchers where invoice_id = t_inv and applied_at is null and quantity = 1) <> 1
       or (select cancelled_unused_value from public.invoice_benefit_values where id = t_ba) <> 0
       or not exists (select 1 from public.audit_logs where table_name = 'invoices' and record_id = t_inv
                        and action = 'reopen_voucher_refunded' and (new_data->>'refunded_units')::int = 1
                        and (new_data->>'still_waiting')::int = 0 and new_data->>'benefit_id' = t_ba::text) then
      raise exception '446: the self-test''s refund did not take line A''s unit off the queue as tested'; end if;
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 30)), gen_random_uuid());
    if (select status::text from public.invoices where id = t_inv) is distinct from 'paid'
       or public.invoice_net_received(t_inv) <> 30
       or (select coalesce(sum(v.quantity), 0) from public.invoice_benefit_values b
             join public.customer_reward_vouchers v on v.id = b.reward_voucher_id
            where b.invoice_id = t_inv and v.status = 'held') <> 1
       or exists (select 1 from public.invoice_benefit_values b
                    join public.customer_reward_vouchers v on v.id = b.reward_voucher_id
                   where b.invoice_id = t_inv and v.status = 'held' and b.invoice_item_id = t_a) then
      raise exception '446: settled, the self-test''s buyer does not hold line B''s voucher alone for S$30'; end if;

    -- (b) A line of two, the same, one unit refunded: the row is lowered.
    t_inv := public.create_invoice(t_store, t_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', t_vch, 'quantity', 2)));
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)), gen_random_uuid());
    perform public.cancel_invoice_recorded(t_inv, '446 check', gen_random_uuid());
    select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1;
    perform public.refund_invoice_recorded(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 30)),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 30)), '[]'::jsonb, '446 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '446 check', gen_random_uuid());
    select q.id into t_q from public.invoice_reopen_vouchers q where q.invoice_id = t_inv and q.applied_at is null and q.quantity = 2;
    select it.id into t_a from public.invoice_items it where it.invoice_id = t_inv;
    select b.id into t_ba from public.invoice_benefit_values b where b.invoice_item_id = t_a and b.reward_voucher_id is not null;
    if t_q is null or t_ba is null then raise exception '446: the self-test''s line of two is not waiting as tested'; end if;
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', t_a, 'amount', 30,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_ba, 'amount', 30)))),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 30)), '[]'::jsonb, '446 check', gen_random_uuid());
    if (select string_agg(q.id::text || ':' || q.quantity, ',') from public.invoice_reopen_vouchers q where q.invoice_id = t_inv)
       is distinct from t_q::text || ':1' then
      raise exception '446: the self-test''s queued row of two was not lowered to one'; end if;
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 30)), gen_random_uuid());
    if (select coalesce(sum(v.quantity), 0) from public.invoice_benefit_values b
          join public.customer_reward_vouchers v on v.id = b.reward_voucher_id
         where b.invoice_id = t_inv and v.status = 'held') <> 1 then
      raise exception '446: settled, the self-test''s line of two does not leave 1 voucher held'; end if;

    -- (c) Credit: two lines of a S$100 Credit Package (S$100 Paid and S$10
    -- Bonus each), paid, cancelled, line B's S$100 paid back, reopened (all
    -- S$220 waits), line A refunded while it waits: A's two queued rows are
    -- closed, each with its reverse and the refund in the ledger, the lots do
    -- not move, B's S$110 waits; paid: line B's S$110 for S$100 net;
    -- cancelled again, a reopening would reinstate S$220 (the refund once).
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, bonus_value,
                                        allow_product, allow_therapy, allow_voucher, grants_reward)
    values ('446 check ' || t_sfx, 100, 100, true, 10, true, true, true, false) returning id into t_pk;
    insert into public.credit_package_stores (package_id, store_id) values (t_pk, t_store);
    t_inv := public.create_invoice(t_store, t_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1),
                        jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)));
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 200)), gen_random_uuid());
    select it.id into t_a from public.invoice_items it where it.invoice_id = t_inv order by it.id limit 1;
    select it.id into t_b from public.invoice_items it where it.invoice_id = t_inv and it.id <> t_a;
    t_alots := array(select b.lot_id from public.invoice_benefit_values b where b.invoice_item_id = t_a and b.lot_id is not null);
    t_blots := array(select b.lot_id from public.invoice_benefit_values b where b.invoice_item_id = t_b and b.lot_id is not null);
    if coalesce(cardinality(t_alots), 0) <> 2 or coalesce(cardinality(t_blots), 0) <> 2
       or (select sum(l.remaining_amount) from public.customer_credit_lots l where l.id = any (t_alots || t_blots)) <> 220 then
      raise exception '446: the self-test''s packages did not give S$110 of Paid and Bonus credit each'; end if;
    perform public.cancel_invoice_recorded(t_inv, '446 check', gen_random_uuid());
    select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1;
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', t_b, 'amount', 100,
        'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', b.id, 'amount', b.paid_value))
                       from public.invoice_benefit_values b where b.invoice_item_id = t_b))),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 100)), '[]'::jsonb, '446 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '446 check', gen_random_uuid());
    if (select status::text from public.invoices where id = t_inv) is distinct from 'partially_paid'
       or (select coalesce(sum(q.amount), 0) from public.invoice_reopen_benefits q where q.invoice_id = t_inv and q.applied_at is null) <> 220 then
      raise exception '446: the self-test''s credit invoice is not reopened part-paid with its S$220 waiting'; end if;
    t_aq := array(select q.id from public.invoice_reopen_benefits q join public.customer_credit_ledger e on e.id = q.source_ledger_id
                   where q.invoice_id = t_inv and e.lot_id = any (t_alots));
    t_req := gen_random_uuid();
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', t_a, 'amount', 100,
        'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', b.id, 'amount', b.paid_value))
                       from public.invoice_benefit_values b where b.invoice_item_id = t_a))),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 100)), '[]'::jsonb, '446 check', t_req);
    if coalesce(cardinality(t_aq), 0) <> 2
       or exists (select 1 from public.invoice_reopen_benefits q where q.id = any (t_aq) and q.applied_at is null)
       or (select string_agg(q.amount::text, ',' order by q.amount) from public.invoice_reopen_benefits q where q.id = any (t_aq)) <> '10.00,100.00'
       or (select coalesce(sum(q.amount), 0) from public.invoice_reopen_benefits q where q.invoice_id = t_inv and q.applied_at is null) <> 110
       or (select sum(l.remaining_amount) from public.customer_credit_lots l where l.id = any (t_alots || t_blots)) <> 0
       or (select coalesce(sum(b.cancelled_unused_value), 0) from public.invoice_benefit_values b where b.invoice_item_id = t_a) <> 0
       or (select count(*) from public.customer_credit_ledger e join public.invoice_reopen_benefits q on q.source_ledger_id = e.reverses_entry_id
            where q.id = any (t_aq) and e.entry_type = 'reverse' and e.source_type = 'invoice_reopen' and e.amount = q.amount
              and e.source_record_id = q.request_id and e.lot_id = any (t_alots)) <> 2
       or (select string_agg(e.amount::text, ',' order by e.amount) from public.customer_credit_ledger e
            where e.source_record_id = t_req and e.entry_type = 'adjust_decrease' and e.source_type = 'invoice_benefit_refund'
              and e.lot_id = any (t_alots)) is distinct from '10.00,100.00'
       or (select count(*) from public.audit_logs a where a.table_name = 'invoices' and a.record_id = t_inv
            and a.action = 'reopen_credit_refunded' and (a.new_data->>'still_waiting')::numeric = 0
            and (a.new_data->>'reopen_benefit_id')::uuid = any (t_aq) and (a.new_data->>'request_id')::uuid = t_req) <> 2 then
      raise exception '446: the self-test''s refund did not take line A''s credit off the queue as tested'; end if;
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
    if (select status::text from public.invoices where id = t_inv) is distinct from 'paid'
       or public.invoice_net_received(t_inv) <> 100
       or (select sum(l.remaining_amount) from public.customer_credit_lots l where l.id = any (t_alots)) <> 0
       or (select sum(l.remaining_amount) from public.customer_credit_lots l where l.id = any (t_blots)) <> 110 then
      raise exception '446: settled, the self-test''s buyer does not hold line B''s S$110 alone for S$100'; end if;
    perform public.cancel_invoice_recorded(t_inv, '446 check', gen_random_uuid());
    if (public.invoice_reopen_preview_before_sessions(t_inv)->>'credit_to_reinstate_after_settlement')::numeric is distinct from 220 then
      raise exception '446: cancelled again, the self-test''s Reopen dialog would not reinstate S$220'; end if;

    raise exception using errcode = 'P0446', message = '446: self-test done, undone';
  exception when sqlstate 'P0446' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
