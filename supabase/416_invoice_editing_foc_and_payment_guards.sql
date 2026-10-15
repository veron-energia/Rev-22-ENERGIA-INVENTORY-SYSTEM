-- 416_invoice_editing_foc_and_payment_guards.sql
--
-- WHAT WAS WRONG (the audit of 9 Oct 2026, re-checked on production that day;
-- batch B02: INVOICES-CREATE-4, -7, -8, -9, -11, -12, -15, -16, -17, -M1,
-- -M2, -M3, INVOICES-AFTER-16 and SALES-EXTRAS-9, server parts)
--
--   Promotions (CREATE-4, CREATE-17, SALES-EXTRAS-9). create_invoice and
--   update_invoice_internal checked a promotion line's choices only against
--   the promotion's own groups, and saved every group they were sent. A
--   cashier who switched a line from one bundle to another sent the first
--   bundle's picks too: a new invoice failed with a database error, and an
--   edited one saved them, so they printed as "(chosen)" and took stock or
--   vouchers. Choices sent with a line that is not a promotion were ignored.
--   Promotion start and end dates were compared with now()::date, the UTC
--   day, so from midnight to 8 am an ended promotion was still sold and one
--   starting that day was refused. A promotion with no items and no choice
--   groups could be sold (production: one such promotion, active, offered
--   inside a blind box; never sold, never picked).
--
--   Dates (CREATE-11, AFTER-16). Correct Invoice could clear an invoice's
--   date ("date pending review") and could date it in the future, and so
--   could the New Invoice form. A corrected or split payment could be dated
--   in the future; a new payment already could not.
--
--   Creating twice (CREATE-15). Payments, corrections and hand-overs carry a
--   request id; creating an invoice did not. A lost reply and a second press
--   of Create made a second invoice.
--
--   The correction summary (CREATE-M1). preview_invoice_correction was sent
--   the header only. It said nothing about what changed lines or discounts
--   do to the total, and its "still paid / part paid" verdict used the total
--   before the correction.
--
--   Payment amounts (CREATE-9). A payment of 99.995 on a S$100 invoice was
--   summed as 99.995 but stored as 100.00: the invoice stayed part paid with
--   S$0.00 owing, nothing was released, and every further payment was refused
--   as more than the balance.
--
--   FOC (CREATE-7, CREATE-8). Confirming a fully FOC invoice took voucher
--   stock but issued no vouchers, raised no special-order item and no rental
--   (the voucher trigger fired on 'paid' only; confirm_foc_invoice never
--   raised special items; a correction raised them for 'paid' only). A
--   correction that completed an invoice as FOC (Edit Invoice with every line
--   free, or any edit after Make FOC) issued nothing either. Make FOC worked
--   on a part-paid invoice, and Remove FOC on a deleted or locked one.
--
--   Taking the FOC off a completed FOC invoice (Edit Invoice, an Owner or
--   Manager) made it unpaid again but left the vouchers it gave with the
--   customer, and paying it then took their stock a second time: two
--   vouchers, stock 10 -> 8 at Confirm FOC, still 8 after the FOC came off,
--   6 once paid. A correction that made a part-paid voucher invoice paid in
--   full issued its vouchers and took no stock at all (deduct_invoice_stock
--   ran there only for an invoice that had already taken products).
--
--   Stale edits (CREATE-M2). Make FOC, Remove FOC, the affiliate picker and
--   Fulfil from warehouse did not raise edit_count, so another user's open
--   Edit Invoice saved over them without noticing.
--
--   Fulfil from warehouse (CREATE-16) did not check the invoice's store or
--   refuse a deleted invoice.
--
--   Instalment terms (CREATE-M3). Any staff member of the store could change
--   or clear the terms on any invoice, paid, cancelled or refunded, by a
--   direct call, with nothing recorded.
--
--   The invoice list (CREATE-12). An undated invoice shows its Singapore
--   creation day as DD/MM/YYYY, but search matched that form for business
--   dates only, and the creation day in UTC. The rows of a page were put
--   together without an order.
--
--   Production on 9 Oct 2026: no invoice is affected by any of these. 0
--   selections of another promotion's group, 0 future-dated invoices or
--   payments, 0 payments with more than 2 decimal places, 0 stuck part-paid
--   invoices, 6 completed FOC invoices (none with a voucher, promotion,
--   special or rental line), 0 part-paid invoices with FOC, 6 invoices with
--   instalment terms (all paid, in-house, with receipts). Read again after
--   414, 421 and 428: 0 completed FOC invoices that gave vouchers, 0 that
--   are unpaid again after Confirm FOC, 0 vouchers taken back and waiting
--   to be given again, 0 invoice_voucher_movements rows. All 18 vouchers
--   are unlimited and no store holds voucher stock, so every voucher stock
--   step below is latent today; which vouchers a customer holds is not.
--   0 vouchers moved to another customer by a benefit transfer, 0
--   'invoice_reopen' vouchers, 0 therapy vouchers with a session used.
--   Read again on 10 Oct after 415: 0 limited vouchers, 0 premium bundle
--   lines with FOC, 0 vouchers moved by a benefit transfer (to any
--   customer or store), 0 'invoice_reopen' vouchers, 0 movement rows.
--
-- THE RULES
--
--   1. A promotion line's choices belong to that promotion's own groups. A
--      group sent with nothing picked writes nothing and is let through; the
--      "Other product" pick, inside the promotion's own group, is unchanged.
--      A line that is not a promotion carries no choices.
--   2. Promotion dates are Singapore days, compared with the invoice's own
--      day: its business date (an undated invoice: the Singapore day it was
--      made; a new invoice with none: today). A back-dated invoice may use
--      a promotion that ran on its date (the Owner, 9 Oct 2026). A promotion
--      switched off is refused whatever the date, as before. A promotion
--      with no items and no choice groups is not sold, and is not chosen
--      inside another promotion.
--   3. An invoice's date is never after today in Singapore. A date once set
--      cannot be cleared. An invoice saved with no date (178, from before
--      dates were required) may stay undated or be given a past date.
--   4. A payment, a corrected payment and each part of a split are never
--      dated after today, and have at most 2 decimal places. They are
--      refused, never rounded.
--   5. Creating an invoice with a request id: the same request again returns
--      the invoice it made; the same id with other contents is refused, naming
--      the invoice it made. No request id: as before.
--   6. A completed FOC invoice is settled like a paid one: its vouchers are
--      issued, its special items and rentals are raised. However it is
--      completed (Confirm FOC, or a correction), the vouchers it gives are
--      taken from the store's stock once, as Confirm FOC takes them, with no
--      invoice_voucher_movements row, so a cancel puts them back once. Too
--      little stock refuses it. A later correction that takes stock again
--      (its products changed) does not take them again.
--   7. FOC is made or removed only on a draft or unpaid invoice with no
--      payment, never on a deleted or locked one.
--   8. Make FOC, Remove FOC, the affiliate and the fulfilment warehouse raise
--      edit_count, so a stale Edit Invoice gets the existing "changed by
--      another user" review.
--   9. Fulfil from warehouse: an Owner or Manager of the invoice's store, on
--      an invoice that is not deleted.
--  10. Instalment terms: set with a payment on an invoice that has a receipt
--      and is not cancelled, refunded or completed FOC. Terms already there
--      are changed or cleared by an Owner or Manager only (staff use Correct
--      Invoice, which keeps a revision). The same terms again change nothing.
--      Every change is audited with the terms before and after.
--  11. The correction summary, when sent the corrected lines, says what the
--      total and status become and any refund due, worked out by the save
--      itself and then undone. Its outcome.checked means the lines,
--      discounts, stock, goods kept, birthday discounts and the vouchers
--      taken when the corrected lines settle the invoice (as FOC, or as paid
--      with the money it holds) passed as the save checks them. Payment
--      changes, and the stock and commission they move, are not tried:
--      checked is not a promise that the save goes through, and the page
--      must not show it as one.
--  12. List search finds the day the list shows in DD/MM/YYYY, YYYY-MM-DD and
--      "8 Aug 2026" (that day only, not 18 or 28 Aug; "8 Aug" that day in
--      any year; "Aug 2026" finds the month); the creation day is the
--      Singapore day. A month name counts as a date only when the search
--      also has a number: "Jun" alone stays a name search (the Owner,
--      9 Oct 2026).
--  13. A correction that makes an invoice paid in full takes the stock of the
--      vouchers it gives as Record Payment does, with an
--      invoice_voucher_movements row, and only what the invoice has not taken
--      already, so never twice (the Owner, 9 Oct 2026). Too little stock
--      refuses it.
--  14. Taking the FOC off a completed FOC invoice (it is unpaid or part-paid
--      again) takes back, in the same save, the vouchers it gave that are
--      still unused, and returns their stock. Used ones (redeemed, or a
--      therapy voucher with sessions used) stay with the customer and stay
--      recorded; one moved to another customer stays with them. One the
--      customer had moved to another of their own stores is unused, so it is
--      taken back like the others. These are the vouchers of voucher lines
--      and promotion lines; a premium bundle's vouchers are not taken back,
--      moved or given again on a reopening or not, as before. The save
--      returns both lists for the page to show, the correction summary
--      lists them before the save, and the audit records each voucher taken
--      back and both lists (the Owner, 9 Oct 2026). When the invoice is
--      settled again, each line that had vouchers taken back gives what the
--      corrected line gives, less what is still out on it (used or moved), so
--      a quantity, voucher or pick changed in the same save is followed;
--      their stock is taken by that payment, once. Taking the FOC off a
--      completed FOC invoice is a correction (Edit Invoice); Remove FOC is
--      refused on it (rule 7).
--
-- WHAT THIS DOES
--
--   * invoices: two new columns, create_request_id uuid and
--     create_request_hash text (both empty for every invoice made so far),
--     and the unique index invoices_create_request_id_key on
--     create_request_id where it is not null.
--   * create_invoice(...) and update_invoice_internal(...) (patched): pass 1
--     refuses choices on a line that is not a promotion, choices for a group
--     of another promotion (rule 1), a promotion with nothing in it, and a
--     chosen promotion with nothing in it; promotion dates are compared
--     with the invoice's own day (rule 2): create_invoice's v_bdate, and in
--     an edit coalesce(business_date, the Singapore day it was made), as 384
--     reads it for a line's Discount. A back-dated refusal names the date.
--     Pass 2 is unchanged. update_invoice_internal also refuses, in a plain
--     sentence, an edit that removes a line that gave the customer vouchers
--     (its invoice_benefit_values rows are evidence and are never deleted);
--     before, the save stopped with a foreign-key error. Paid and part-paid
--     invoices get the same sentence.
--   * create_invoice_with_details(...) (replaced whole): p_header.request_id
--     (rule 5), with a lock on the request id so two presses at once make one
--     invoice; a date after today is refused (rule 3). Website orders and
--     event tickets send no request id and are dated by their payment day.
--   * correct_invoice(...) (patched): rule 3; completed_foc raises special
--     and rental items as paid does, and an invoice it settles takes its
--     voucher stock before the status change has the vouchers issued: as
--     Confirm FOC does when it completes it as FOC (rule 6), as Record
--     Payment does when it makes it paid (rule 13). Before it takes stock
--     on a completed FOC invoice (its products changed), or takes its FOC
--     off, it records what Confirm FOC took as invoice_voucher_movements
--     rows ('Taken at Confirm FOC'), so deduct_invoice_stock, which nets
--     voucher stock against those rows, does not take it again (rule 6);
--     if the invoice stays FOC the same rows are cancelled out after the
--     deduction, so it keeps none. How many: by voucher, as
--     deduct_invoice_stock counts them, the units the customer still has
--     from the invoice's voucher and promotion lines less what its rows
--     hold, wherever either sits. A premium bundle's vouchers do not count:
--     the bundle took their stock itself, and Confirm FOC took none for
--     them (417's invoice_voucher_stock_unrecorded counts the same lines).
--     Where: at the stores that hold those vouchers, as they were before
--     the save moves any, where their stock is out, so each store's rows
--     add up to what is out there (one row per store when a voucher's
--     units sit at two; the store whose rows lack the most first). This is
--     done once, before the correction summary's stop, so the summary's
--     try records them the same way. A save that keeps the invoice
--     completed FOC gives no voucher for a voucher line raised or added,
--     so it keeps no voucher stock for it either: what
--     deduct_invoice_stock takes for it is put back at once, with a row
--     ('Still FOC, nothing given for the change') that cancels its row.
--     Three faults in this file before 10 Oct, all fixed here: counted
--     store by store, a row a reopening wrote at one store did not count
--     once an Owner had moved the vouchers to another, so it was recorded
--     again (FOC, cancel, reopen, vouchers moved, FOC off, paid, cancelled
--     ended at 22 in the two stores, not 20, with 417; B03's hand-over);
--     a voucher line raised while the invoice stayed FOC had its unit taken
--     with a row, the FOC-off count read that row as part of what Confirm
--     FOC took, and the payment took the unit again (10 -> 8 -> 7, FOC off
--     9, paid 6 with 3 held, not 7); and written at the invoice's store,
--     the row did not match where rule 14 gives the stock back once an
--     Owner had moved the invoice to another store, so with 416 alone a
--     cancel then gave 2 back at a store that never lost them (22, not
--     20). Three more, fixed the same day: a premium bundle's voucher moved
--     to a friend (or given again on a reopening) counted as taken at
--     Confirm FOC, so the payment after the FOC came off the voucher line
--     took one unit too few (9 and 9 with 3 held, not 8 and 9); rule 14
--     took back a bundle's voucher given again on a reopening, and it was
--     never given again (2 held, not 3); and a voucher moved to another
--     store of the same customer was called "moved to another customer"
--     and left with them while the invoice was unpaid. Taking the FOC off
--     a completed FOC
--     invoice takes back its unused vouchers and returns their stock, each
--     with a negative movement row, so the rows hold what is still out; it
--     leaves used vouchers and those moved to another customer
--     ('invoice_benefit_transfer' held by a customer other than the
--     invoice's), audits it, and returns 'foc_vouchers'
--     {taken_back, kept_used}, a moved one marked as moved (rule 14). It
--     looks at voucher and promotion lines only. Only
--     when invoice.correction_preview is on, it makes the later checks no
--     payment change alters (stock, goods kept, birthday discounts, the
--     voucher stock taken when the corrected lines settle the invoice), then
--     stops before any payment change and hands back the corrected lines
--     (error P0416).
--   * preview_invoice_correction(uuid,jsonb) (patched; now VOLATILE, as it
--     runs the save to undo it): with p_header.items, rule 11. Its result
--     gains an 'outcome' key (checked, totals, status before and after,
--     outstanding, refund due, the lines that change), a 'total' entry in
--     'effects', and a 'correction' entry in 'needs_review' when one of the
--     checks of rule 11 refuses the save (checked is then false), and a
--     'vouchers' entry when the corrected lines take the FOC off a completed
--     FOC invoice (rule 14): its detail names what is taken back, and its
--     items list once each voucher that stays (used, or moved to another
--     customer), chosen as the save chooses them. Without items, its
--     result is as before. Its
--     payment checks gain rule 4, and its payments verdict uses the
--     corrected total.
--   * invoice_list_page(...) (patched): rule 12, and jsonb_agg in the page's
--     order. Every key it returned is returned with the same value.
--   * apply_line_foc(...), remove_line_foc(...) (patched): rules 7 and 8.
--   * set_invoice_affiliate(uuid,uuid) (patched): rule 8; a deleted invoice
--     is not found.
--   * set_invoice_fulfilment_warehouse(uuid,uuid) (patched): rules 8 and 9.
--   * confirm_foc_invoice(uuid,text) (patched): raises special and rental
--     items after completing the invoice (rule 6).
--   * trg_issue_sold_vouchers_on_paid() (replaced whole): fires on 'paid' or
--     'completed_foc' (rule 6); issue_sold_vouchers_for_invoice is
--     idempotent. Then it gives again what rule 14 took back, as the
--     corrected lines give it: on each line with a voucher revoked and
--     still marked taken back unused (cancelled_unused_value), for each
--     voucher the line now gives (its quantity, or its promotion's voucher
--     picks), what it gives less what is still out on that line (any
--     voucher not revoked: used, moved, or just issued for a new pick).
--     Units of a voucher taken back on that line are replacements, recorded
--     as a reopened invoice's are (an invoice_reopen_vouchers row, applied
--     at once; source 'invoice_reopen'), each no larger than the voucher it
--     replaces, so a therapy voucher carries its recorded rights; a voucher
--     the line did not give before (swapped in on the same line) is issued
--     as the line's sale. A voucher the customer had moved to another of
--     their stores ('invoice_benefit_transfer') and rule 14 took back is
--     replaced the same way, at the invoice's store, where the payment took
--     its stock. Each is worth its share of what the line now
--     charges. Then every voucher taken back is marked settled
--     (cancelled_unused_value 0), given again or no longer owed. No stock is
--     taken here (the payment or FOC that settles the invoice took it). A
--     cancelled invoice's vouchers are replaced by its reopening, in
--     invoice_reopen_vouchers_settled, which runs first and clears what it
--     replaces.
--   * record_invoice_payment(...), invoice_record_payments_internal(...)
--     (patched): rule 4's decimals. return_rental_with_fee reaches the second.
--   * correct_invoice_payment(...), split_invoice_payment(...) (patched):
--     rule 4.
--   * set_invoice_instalment_label(uuid,uuid,integer) (replaced whole):
--     rule 10.
--
-- NOT CHANGED
--
--   * The pages, but for rule 14's note: after a correction the invoice page
--     says which vouchers were taken back and which used or moved ones stay
--     (InvoicesPage.tsx), and the summary labels the 'vouchers' entry
--     (CorrectionPreview.tsx). Every other change works with the pages live
--     now; the page wiring (a request id per New Invoice form, the corrected
--     lines sent to the summary, max dates, decimal checks) is batch B16's.
--     Each refusal is a plain sentence the current page shows as it is.
--   * Who may do what, beyond rules 7, 9 and 10. No grant changes. No new
--     function. create_invoice stays callable by staff, as before (it is not
--     called by any page; whether to take that away is for the permissions
--     sweep, B17). record_invoice_payment_with_instalment, which also sets
--     terms, is the service role's alone and unchanged.
--   * Cancel, refund and reopen of a completed FOC invoice (batch B03's
--     functions). Cancelling one, recorded or guided, takes back the vouchers,
--     special items and rentals this now issues, as for a paid invoice
--     (tested in sold-voucher-issuance.sql and rental-lifecycle.sql).
--   * A voucher stock fault older than this, in cancel_invoice_recorded
--     (batch B03's): it puts limited voucher stock back once for each held
--     voucher it takes back and again for the invoice's net
--     invoice_voucher_movements. Stock taken with a movement row (Record
--     Payment, and now rule 13 and the payment after rule 14) therefore
--     comes back twice for unused vouchers, and once for used ones the
--     customer keeps. Two vouchers: paid, 10 -> 8; cancelled, 12 (should be
--     10). One of two used, FOC taken off, then paid: 10 -> 8 -> 9 -> 8;
--     cancelled, 11 (should be 9). The same, cancelled while still unpaid:
--     9 -> 10 (should stay 9). Confirm FOC and rule 6 take stock without a
--     movement row, so a completed FOC invoice is cancelled right: 8 -> 10.
--   * A second voucher stock fault older than this, in the reopening (batch
--     B03's reopen_invoice and apply_reopened_invoice_vouchers): reopening a
--     cancelled completed FOC invoice, or one whose FOC was taken off, takes
--     its voucher stock twice: deduct_invoice_stock with a movement row, then
--     apply_reopened_invoice_vouchers. Two vouchers: FOC -> cancel -> reopen,
--     10 -> 8 -> 10 -> 6; FOC off -> cancel -> reopen -> pay, 10 -> 8 -> 10
--     -> 10 -> 6 (should end at 8). A paid invoice is not affected once 417
--     is in: paid -> cancel -> reopen goes 10 -> 8 -> 10 -> 8. Rule 14 does
--     not cause it (FOC -> cancel -> reopen does it alone). With 417 as
--     written on 9 Oct (worktree wf_df3da377-9e7-2), in either order with
--     this, FOC -> cancel -> reopen ends right, at 8, and the FOC-off path
--     still ends at 6. 417 as of 10 Oct (B03; file md5 c5c96d76...) ends
--     both paths at 8 and fixes the cancel fault above in its own
--     functions: its reopening records, as a movement row, the stock
--     Confirm FOC and rule 6 took before it takes any
--     (invoice_voucher_stock_unrecorded), and its cancel gives voucher
--     stock back once, counted by voucher, however it was taken. Both paths
--     are in sold-voucher-issuance.sql as KNOWN FAULT notices (measured,
--     expected 8, never a failure); with 417 in they print "now right".
--     This file's 'Taken at Confirm FOC' rows are counted by voucher too
--     (WHAT THIS DOES), so B03's cancel-voucher-stock-once.sql case 14
--     runs with 417 and passes: FOC, cancel, reopen, vouchers moved to
--     another store, FOC off, paid 18, cancelled 20 (not 22). All 19 of its
--     cases pass with 417 before or after this (10 Oct, after the six
--     fixes in WHAT THIS DOES).
--   * A fault of 417's earlier 10 Oct file (0beaeaac...) with this, now
--     fixed by B03 in 417's file c5c96d76... (found 10 Oct; latent: 0
--     limited vouchers in production). A
--     save that keeps a completed FOC invoice FOC gives nothing and takes
--     nothing back when it raises or lowers a voucher line (rule 6's still
--     FOC step; as on a paid invoice), so the line and the vouchers held
--     differ. 417's reopening then takes the line's units but gives again
--     only the vouchers held, and its cancel gives back the held vouchers
--     and the rows both. Two vouchers given free, the line raised to 3 while
--     FOC, cancel (10), reopen, cancel again: 9, not 10; lowered to 1: 11.
--     With this alone both end at 10 (B03's older reopen fault hides it);
--     with 417 alone Confirm FOC gives no voucher at all. The change belongs
--     in 417: its reopen_invoice, on a completed FOC invoice, puts back what
--     it took beyond what it gives again, with a negative row, as this
--     file's still FOC step does; its cancel gives back, by voucher and
--     store, what is out, not the held vouchers and the rows both. Both
--     cases are in sold-voucher-issuance.sql: KNOWN FAULT notices while
--     417's reopen_invoice or cancel_invoice_recorded is its earlier 10 Oct
--     text, and a failure with any other text that does not end at 10. With
--     417's file c5c96d76... both print PASS (10 both times), in either
--     order with this.
--   * Only correct_invoice's 'Taken at Confirm FOC' rows were counted store
--     by store (checked 10 Oct). Nothing else this changes counts the
--     movement rows that way: rule 13, the summary's stock check and the payment
--     (invoice_record_payments_internal) use invoice_stock_to_deduct and
--     deduct_invoice_stock, by voucher; rule 14 gives each voucher back at
--     its own store with its own row; confirm_foc_invoice still takes what
--     the lines need at the invoice's store with no row, as before; the
--     trigger, remove_line_foc and apply_line_foc take no stock.
--   * A correction that keeps an invoice settled (paid, or still completed
--     FOC) and changes a voucher line's quantity or voucher, or a
--     promotion's voucher pick, gives no voucher for the change and takes
--     none back: the issuers skip a line that gave vouchers before, and the
--     trigger runs only when the invoice becomes settled. Older than this.
--     On a paid invoice, voucher stock moves for it only when the save also
--     takes product stock (deduct_invoice_stock): then a rise is taken,
--     with a movement row, and nothing is issued for it. On an invoice that
--     stays completed FOC nothing is kept for it now (WHAT THIS DOES), but
--     deduct_invoice_stock still takes the unit before it is put back, so
--     too little stock at the invoice's store refuses the save, as before,
--     and the summary says so. Whether a voucher raised or added on a
--     completed FOC invoice should be given at once is the Owner's to say
--     (asked 10 Oct); until then it is given only if the FOC comes off and
--     the invoice is paid. Likewise, when the FOC comes off, a line whose
--     vouchers were all used has none taken back, so a quantity raised on
--     it in that save is not given at payment.
--   * Two older moves that leave voucher stock and the vouchers' store
--     apart (not this file's functions). A correction that moves an invoice
--     to another customer and store with benefit_action 'transfer'
--     (move_invoice_benefits_to_customer) moves the vouchers' store but not
--     their stock (B03's case 13). When the same save takes the FOC off,
--     the 'Taken at Confirm FOC' row sits where Confirm FOC took the stock,
--     the first store, and rule 14 gives the stock back at the vouchers'
--     new store: 8 and 12 in the two stores, not 10 and 10 (with 417, 20 in
--     all; with 416 alone, cancelled unpaid, 10 and 12). An Owner's
--     transfer_invoice_unused_benefit moves a voucher's stock to its new
--     store with no row, so a row a reopening wrote before the move stays at
--     the first store: counted by voucher nothing is recorded twice, but
--     that row does not follow the voucher. Both are B03's to change.
--   * A correction cannot remove a line that gave the customer vouchers (a
--     known limit, as before; now said in a plain sentence). The vouchers
--     are taken back with Refund / Cancel, or the line is kept.
--   * A voucher an Owner or Manager moved to another customer
--     (transfer_invoice_unused_benefit) stays with them when the FOC comes
--     off; it is reported, counted as still out, and not given again. Not
--     yet decided by the Owner. One moved to another store of the same
--     customer is taken back (rule 14) and given again when the invoice is
--     paid at the invoice's store, where the payment takes its stock, not
--     at the store it was moved to (asked 10 Oct). After a cancel and a
--     reopen, the reopening gives a voucher moved to another customer back
--     to them as 'invoice_reopen', and rule 14 then takes it back like the
--     buyer's own, and the payment gives it to the buyer (found 10 Oct;
--     latent: 0 moved vouchers in production; stock stays right). Left for
--     the Owner's answer on moved vouchers; B03's
--     cancel-voucher-stock-once.sql case 12b prints it as KNOWN FAULT.
--   * Rule 14 touches vouchers only, and only those of voucher and
--     promotion lines: a premium bundle's vouchers stay with the customer
--     when the FOC comes off, as its credit does (asked 10 Oct, for the
--     FOC taken off the bundle line itself). Special items, rentals, therapy and
--     credit a completed FOC invoice raised stay as they are when its FOC is
--     taken off; the invoice keeps the lock Confirm FOC gave it, so Edit
--     Invoice then refuses it ("You cannot edit this invoice") until it is
--     paid; Record Payment and Refund / Cancel still work. Both as before.
--   * No row of the app's tables is changed. The 178 undated invoices stay
--     undated; the one empty promotion is the Owner's to fill or switch off.
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. Every
--   changed function must be the production version read on 9 Oct 2026
--   (BEFORE), or already this migration's version (AFTER), which is left
--   alone so a re-run changes nothing. The functions relied on and not
--   changed (sg_today, create_special_docs_for_invoice,
--   issue_sold_vouchers_for_invoice, issue_promotion_vouchers_for_invoice,
--   invoice_stock_to_deduct, apply_reopened_invoice_vouchers,
--   invoice_discounted_line_value, invoice_promotion_voucher_components,
--   snapshot_therapy_voucher_issue, and deduct_invoice_stock, read again on
--   10 Oct) must be the versions read that day: the
--   two issuers must still be idempotent and have no status gate (a voucher
--   line that gave vouchers is skipped; a promotion's pick once it gave that
--   voucher), the stock still owed must still be net of the invoice's
--   movement rows, a reopened invoice's replacements must still clear what
--   they replace, a replacement must still carry the therapy rights of
--   the voucher it replaces when it is the same voucher with no more units,
--   and deduct_invoice_stock must still take voucher stock at the invoice's
--   store with a movement row there, so a save that keeps an invoice FOC
--   can put back what it took by those rows.
--   The trigger invoice_reopen_vouchers_settled must be the one
--   read that day, so it runs before issue_sold_vouchers_on_paid. Every anchor
--   must occur exactly once, and every new text must have its AFTER md5
--   before anything is installed. No other function may share a changed
--   function's name. The two columns and the index must be missing or exactly
--   as this makes them. The texts run as CREATE OR REPLACE with the same
--   arguments and result types, which keeps owner and grants; afterwards
--   every md5 is checked against AFTER and every grant against what it was.
--   Then, inside a block that is always undone, a made-up Owner, store,
--   customer (a number from a range kept for fiction) and undated invoice
--   made at 01:30 on 1 Jan 1999 Singapore time: a payment of 99.995 is
--   refused by both payment functions; terms without a receipt are refused;
--   a new invoice dated tomorrow is refused; the list finds the invoice by
--   01/01/1999, 1999-01-01, 1 Jan 1999, 1 Jan and Jan 1999 (the UTC day was
--   31 Dec 1998), and not by Jan alone; a payment
--   corrected to tomorrow is refused; Fulfil from warehouse on a deleted
--   invoice is not found. Nothing is printed and no row remains.
--
-- BEFORE (md5 of pg_get_functiondef, search_path public; read on production
-- 9 Oct 2026, and all twenty-six read there again after 414, 421 and 428
-- went live and again on 10 Oct after 415 went live: unchanged):
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)  ca369228b873e4b7f7ffcb0a4ca13fa2
--   update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)
--                                                                 ae651ca1f5d80f46172f7601d9691966
--   create_invoice_with_details(uuid,uuid,jsonb,jsonb)            e5b1c9ddb9404439123cd2fdb49f6b21
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                   5f3f317dfb226be09055142dc44bdec7
--   preview_invoice_correction(uuid,jsonb)                        99b1b39d63cdcfd306fdc5da19557cc8
--   invoice_list_page(text,text,text,date,date,uuid,text,text,integer,integer)
--                                                                 dffff0e40dc8874759b8f0160df7f6db
--   apply_line_foc(uuid,integer,uuid,text)                        eba9ffa077208c809001d30fdbaad409
--   remove_line_foc(uuid,text)                                    488b7a79857426e8cbecbe9630c4f298
--   set_invoice_affiliate(uuid,uuid)                              499606008bead7309a3fa49810f568b1
--   set_invoice_fulfilment_warehouse(uuid,uuid)                   389eea0434e50337c9a90bc79937f5e2
--   confirm_foc_invoice(uuid,text)                                42a6bdb4a1a693c5c83a4fa601abc551
--   trg_issue_sold_vouchers_on_paid()                             6e1b4743788b0f6913205b233c1559b3
--   record_invoice_payment(uuid,jsonb,uuid)                       95a02a1685af524ecf0201b4ed7f9a67
--   invoice_record_payments_internal(uuid,jsonb)                  5c2559f7cf4dbca5dec4fdd55d00ae34
--   correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)     63efea7ed4721721b598f2e1237b8f6c
--   split_invoice_payment(uuid,jsonb,text,uuid)                   5c13c5d9a0461097bf74dec4414aaf4c
--   set_invoice_instalment_label(uuid,uuid,integer)               f6b3103528e779bcb738abc122d2a2c1
--   (relied on, not changed)
--   sg_today()                                                    1c1289f18e24d8370e9a6364c9c06fca
--   create_special_docs_for_invoice(uuid)                         e5503f03bf5b615ec9b948fecdc52b55
--   issue_sold_vouchers_for_invoice(uuid)                         0dbb4bc74411b6d4f0535f661a8c09ee
--   issue_promotion_vouchers_for_invoice(uuid)                    e47e5f623b1fa3f6eafe83086f0c9776
--   invoice_stock_to_deduct(uuid)                                 6356494ccb8545d46c56b788f8f85f54
--   apply_reopened_invoice_vouchers()                             71d50be41b73decceb0b20f8597dd4fa
--   invoice_discounted_line_value(uuid)                           ead4a430c3abd1e3f953912867ca4fe6
--   invoice_promotion_voucher_components(uuid)                    88abd9576481edb759d6e433408c6275
--   snapshot_therapy_voucher_issue(uuid,boolean)                  12ba32611ad001781862d82b1ae13c8e
--   deduct_invoice_stock(uuid,text)                               32183fe9e7c15ed0b11307c48289831a  (read 10 Oct 2026)
--   public function fingerprint (md5 of each public function's md5, in
--   regprocedure order; for reference only, this does not guard on it):
--     base after 413 (test copy), which the tests ran on          675ac22c631079b58f06813d0d463fa3
--     production after 414, 421 and 428 (20261009084737,
--     20261009104732, 20261009104830; 1235 functions)            897ad364eff917861989315bb2fa0e43
--     production now, after 415 too (20261010010418; 1237
--     functions; the test copy with all four applied gives the
--     same)                                                       566e76f702c89c9846968e6fdd89cc45
-- AFTER (for later guards):
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)  80c80d386a5241e63b353e35e13ef250
--   update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)
--                                                                 8e674fe0d5e35ed5c2e93d417f14c05a
--   create_invoice_with_details(uuid,uuid,jsonb,jsonb)            0f408a1a350b68fd86cd24109c85c05b
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                   8a126ade5710d340378ac4e75931b05b
--   preview_invoice_correction(uuid,jsonb)                        be5d652d71df0499d41edeba1c395717
--   invoice_list_page(text,text,text,date,date,uuid,text,text,integer,integer)
--                                                                 2c0017c93df1d7eb10f6eb44f63fb7b7
--   apply_line_foc(uuid,integer,uuid,text)                        5fbd0b6feb36e11dea6be231ffa0e952
--   remove_line_foc(uuid,text)                                    9f9f31876bbf3c13d5838d183ef41b8d
--   set_invoice_affiliate(uuid,uuid)                              eb4dc4b9b7eda73ef75a122d48dcdb6a
--   set_invoice_fulfilment_warehouse(uuid,uuid)                   66bf7f38e06bf48116b63b71ca7663cb
--   confirm_foc_invoice(uuid,text)                                ba8b1ce2a5671989b927891f0cb7b1a2
--   trg_issue_sold_vouchers_on_paid()                             c840d0d2754e7a8e889848ea8269a293
--   record_invoice_payment(uuid,jsonb,uuid)                       c3da81f28d5a24a1c5f336527cfc33a4
--   invoice_record_payments_internal(uuid,jsonb)                  21890d84bcb0b9c00a2bc98aff313d0b
--   correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)     f3c96d9916a95a68a9202cdb25d8017b
--   split_invoice_payment(uuid,jsonb,text,uuid)                   e385a9958c78dc9dc2aa82737958689e
--   set_invoice_instalment_label(uuid,uuid,integer)               8ff9ae95f434a0123d130b46527207ef
--   public function fingerprint (reference only, not guarded), worked out
--   on the test copy on 10 Oct 2026, after the six fixes in WHAT THIS
--   DOES, not read on production:
--     base after 413 (test copy) plus this (1229 functions)       68b6397e0722aa500b54373e5a2c4fe2
--     base after 413 (test copy) plus 414, 421, 428 and this
--     (either order; 1235 functions)                              e02fb79c9c8246b74eff5915c5c9b8b2
--     base after 413 (test copy) plus 414, 421, 428, 415 and this
--     (415 before or after this; 1237 functions), which is what
--     production should read after this if nothing else goes
--     first                                                       2d8adfa50cb541fe5582f4e6f9bbe9f3
--     the same plus B03's 417 (its file of 10 Oct, md5
--     c5c96d76...), 417 before or after this (1240 functions)     5d4baac3cc4958040b28c528088c5684
--
-- DEPLOY ORDER: this, then the invoice page (B16). The page live now works
-- against this unchanged: it sends no request id and no corrected lines to
-- the summary, so both behave as before, and each new refusal is shown as
-- the plain sentence it is. The new page against a database without this
-- would send request ids that are ignored and get summaries without totals,
-- so this goes first. Time-sensitive: rule 6 before staff give away
-- vouchers, bundles, special items or rentals (the 19-20 Oct event). 414,
-- 421, 428 and 415, live in production, change none of the functions here
-- or relied on; this was tested on a copy of production after 413 and again
-- with 414, 421, 428 and 415 applied first. 415 checks by content that
-- create_invoice_with_details still calls public.create_invoice( and that
-- create_invoice still calls event_ticket_line_check(; this keeps both.
-- 417 (B03) may go before or after this: both orders give the same
-- functions (tested again on 10 Oct with 417's file c5c96d76..., after the
-- six fixes in WHAT THIS DOES; B03's cancel-voucher-stock-once.sql passes
-- every case in either order, case 14 included, and prints case 12b as
-- KNOWN FAULT for the open question on moved vouchers; 417 relies on
-- deduct_invoice_stock as this does and changes neither it nor
-- correct_invoice). Ship 417 with or soon after this, before any voucher is set
-- to limited stock: until 417 is in, a cancel gives back twice the voucher
-- stock taken with a movement row (NOT CHANGED). 417's file c5c96d76...
-- also makes the change to its reopen and cancel for a voucher line changed
-- while FOC (NOT CHANGED); ship that 417, not an earlier one. The page should present
-- outcome.checked as rule 11 says (B16), and show the 'vouchers' entry of
-- the summary (rule 14) as it shows the others.
--
-- Test: scripts/invoices/tests/promotion-switch.sql, foc-guards.sql,
-- payment-decimals.sql, instalment-label.sql, create-request-id.sql,
-- correction-preview.sql, scripts/invoices/tests/staff-corrections.sql
-- (dates), sold-voucher-issuance.sql (FOC, rules 13 and 14, the FOC taken
-- off with changed lines, a moved voucher, a removed line, therapy vouchers,
-- the 'Taken at Confirm FOC' rows counted by voucher after a reopening and a
-- move to another store; then a save that keeps the invoice FOC (S1 to S7):
-- a raised voucher line keeps no stock and the payment takes each unit
-- once, and where the 'Taken at Confirm FOC' rows sit, store by store, with
-- the summary refusing what the save refuses; with 417 in, it also cancels
-- and checks 10 at each store; then premium bundle vouchers moved or
-- given again on a reopening, and a voucher moved to the same customer's
-- other store (B1 to B3), with 417 also cancelled to 10 and 10; then, with
-- 417 only, a voucher line raised or lowered while FOC, cancel, reopen,
-- cancel (KNOWN FAULT notices for 417's 10 Oct text, see NOT CHANGED).
-- Changing correct_invoice back in any of 11
-- ways makes it fail (checked 10 Oct, with and without 417): the stock kept
-- for a raise, the rows counted by store or not subtracted, written at the
-- invoice's store before or after the save or at one store only, more than
-- the voucher lacks written, the rows not written for the summary, or not
-- for a FOC-off or a stock change, or the raise put back at the wrong
-- store; so does undoing any of 6 later changes (the line kind in the
-- 'Taken at Confirm FOC' count, in rule 14 or in the summary; the same
-- customer's store move in rule 14 or in the summary; the trigger giving
-- it again). Its last block prints B03's reopening fault as KNOWN FAULT notices
-- and never fails) and rental-lifecycle.sql (FOC), promotion-switch.sql (rule 2,
-- back-dated and undated),
-- scripts/invoice-pagination/tests/list-page.sql (search and order),
-- scripts/promotions/tests/no-empty-promises.sql, and
-- scripts/permissions/tests/function-grants.sql and staff-only-functions.sql
-- after this in the same transaction; scripts/invoices/tests/concurrency.mjs
-- with create-request-race.mjs (four creates racing with one request id). Each
-- SQL suite installs this after "begin;" when run with
-- psql -v mig=supabase/416_invoice_editing_foc_and_payment_guards.sql, and is
-- rolled back. With 417: B03's
-- scripts/invoice-actions/tests/cancel-voucher-stock-once.sql, with 417 and
-- this installed in the same transaction first, in either order (all 19
-- cases run and pass; case 14 checks the rows are counted by voucher).
-- Once this is live, three older suites stop at a guard that takes only the
-- pre-416 text: scripts/therapy/tests/status-refresh.sql and
-- scripts/commissions/tests/clawbacks-carried-forward.sql (410's guard on
-- correct_invoice) and scripts/xero/tests/sales-events.sql (its own check of
-- correct_invoice_payment and record_invoice_payment). (10 Oct: main's copy
-- of clawbacks-carried-forward.sql skips the 410 replay where 414 is in, so
-- it passes either way; status-refresh.sql cannot pass on a copy of
-- production after 414 at all, prelude or not, because 410's guard on
-- affiliate_payout_overview predates 414.) Run them with
-- psql -v prelude=scripts/invoices/tests/before-416-prelude.sql, which puts
-- those three functions back as they were before 416 inside the suite's
-- transaction (it changes nothing where 416 is not installed).

set lock_timeout = '5s';

do $mig$
declare
  -- ── The edits: each anchor (…_a) occurs once in the production text and is
  -- replaced by its …_r. Two functions are replaced whole (…_def). ──────────
  c_promo_a constant text := $q$    if v_kind = 'promotion' then
      v_has_promo := true;
      v_promo_id := (v_item->>'promotion_id')::uuid;
      select * into v_promo from public.promotions where id = v_promo_id and deleted_at is null;
      if not found then raise exception 'Promotion not found'; end if;
      if not v_promo.is_active then raise exception 'Promotion "%" is not active', v_promo.name; end if;
      if v_promo.start_date is not null and now()::date < v_promo.start_date then raise exception 'Promotion "%" has not started yet', v_promo.name; end if;
      if v_promo.end_date is not null and now()::date > v_promo.end_date then raise exception 'Promotion "%" has ended', v_promo.name; end if;
$q$;
  c_promo_r constant text := $q$    -- 416: choices are sent with a promotion line only (INVOICES-CREATE-4).
    -- Nothing would be saved for them, so they can only be left over from
    -- a line that was a promotion before.
    if v_kind <> 'promotion' and jsonb_typeof(v_item->'selections') = 'array'
       and exists (select 1 from jsonb_array_elements(v_item->'selections') s416,
                                 jsonb_array_elements(case when jsonb_typeof(s416->'options') = 'array'
                                                           then s416->'options' else '[]'::jsonb end) o416
                    where coalesce((o416->>'quantity')::integer, 0) > 0) then
      raise exception 'Choices were sent with a line that is not a promotion. Remove the line and add it again.'; end if;
    if v_kind = 'promotion' then
      v_has_promo := true;
      v_promo_id := (v_item->>'promotion_id')::uuid;
      select * into v_promo from public.promotions where id = v_promo_id and deleted_at is null;
      if not found then raise exception 'Promotion not found'; end if;
      if not v_promo.is_active then raise exception 'Promotion "%" is not active', v_promo.name; end if;
      -- 416: a promotion's start and end dates are Singapore days. The
      -- database clock is UTC, so now()::date was the day before until 8 am
      -- (INVOICES-CREATE-17, SALES-EXTRAS-9). They are compared with the
      -- invoice's own day, so a back-dated invoice may use a promotion that
      -- ran on its date (the Owner, 9 Oct 2026).
      if v_promo.start_date is not null and @DAY@ < v_promo.start_date then
        if @DAY@ < public.sg_today() then
          raise exception 'Promotion "%" had not started on the invoice date, %.', v_promo.name, to_char(@DAY@, 'DD/MM/YYYY'); end if;
        raise exception 'Promotion "%" has not started yet', v_promo.name; end if;
      if v_promo.end_date is not null and @DAY@ > v_promo.end_date then
        if @DAY@ < public.sg_today() then
          raise exception 'Promotion "%" had ended by the invoice date, %.', v_promo.name, to_char(@DAY@, 'DD/MM/YYYY'); end if;
        raise exception 'Promotion "%" has ended', v_promo.name; end if;
      -- 416: a promotion with no items and no choice groups gives the customer
      -- nothing, so it is not sold (SALES-EXTRAS-9).
      if not exists (select 1 from public.promotion_items pi416 where pi416.promotion_id = v_promo_id)
         and not exists (select 1 from public.promotion_choice_groups g416 where g416.promotion_id = v_promo_id) then
        raise exception 'Promotion "%" has nothing in it, so it cannot be sold. Ask an Owner or Manager to add its items.', v_promo.name; end if;
      -- 416: every choice sent belongs to one of this promotion's own groups
      -- (INVOICES-CREATE-4). Picks left over from another promotion, when the
      -- line was switched, would be saved, printed and taken from stock. A
      -- group sent with nothing picked writes nothing and is let through.
      if jsonb_typeof(v_item->'selections') = 'array'
         and exists (select 1 from jsonb_array_elements(v_item->'selections') s416
                      where exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s416->'options') = 'array'
                                                                          then s416->'options' else '[]'::jsonb end) o416
                                     where coalesce((o416->>'quantity')::integer, 0) > 0)
                        and not exists (select 1 from public.promotion_choice_groups g416
                                         where g416.promotion_id = v_promo_id and g416.id::text = s416->>'group_id')) then
        raise exception 'Picks from another promotion were sent with "%". Remove the line and add it again.', v_promo.name; end if;
$q$;
  c_child_a constant text := $q$                if not v_ok then
                  raise exception 'A selected % does not belong to choice group "%"',
                    replace(v_grp.item_kind, '_', ' '), v_grp.label;
                end if;
$q$;
  c_child_r constant text := $q$                if not v_ok then
                  raise exception 'A selected % does not belong to choice group "%"',
                    replace(v_grp.item_kind, '_', ' '), v_grp.label;
                end if;
                -- 416: a promotion chosen in a group must have something in it
                -- (SALES-EXTRAS-9).
                if v_grp.item_kind = 'promotion'
                   and not exists (select 1 from public.promotion_items pi416
                                    where pi416.promotion_id = (v_opt->>'child_promotion_id')::uuid)
                   and not exists (select 1 from public.promotion_choice_groups g416
                                    where g416.promotion_id = (v_opt->>'child_promotion_id')::uuid) then
                  raise exception '"%" in "%" has nothing in it, so it cannot be chosen. Ask an Owner or Manager to add its items.',
                    coalesce((select p416.name from public.promotions p416 where p416.id = (v_opt->>'child_promotion_id')::uuid), 'A promotion'),
                    v_grp.label;
                end if;
$q$;
  c_uii_del_a constant text := $q$  delete from public.invoice_items ii where invoice_id = p_invoice_id
    and not exists(select 1 from jsonb_array_elements(p_items) x where nullif(x->>'invoice_item_id','')::uuid=ii.id);
$q$;
  c_uii_del_r constant text := $q$  -- 416: a line that gave the customer vouchers keeps them as evidence
  -- (invoice_benefit_values), so it cannot be removed. Before, the save
  -- stopped with a database error; now it says what to do.
  if exists (select 1 from public.invoice_items ii
               join public.invoice_benefit_values b416 on b416.invoice_item_id = ii.id
              where ii.invoice_id = p_invoice_id and b416.reward_voucher_id is not null
                and not exists (select 1 from jsonb_array_elements(p_items) x
                                 where nullif(x->>'invoice_item_id','')::uuid = ii.id)) then
    raise exception 'A line you removed gave vouchers to the customer. Keep the line, or take the vouchers back with Refund / Cancel.'; end if;
  delete from public.invoice_items ii where invoice_id = p_invoice_id
    and not exists(select 1 from jsonb_array_elements(p_items) x where nullif(x->>'invoice_item_id','')::uuid=ii.id);
$q$;
  c_ciwd_def constant text := $q$CREATE OR REPLACE FUNCTION public.create_invoice_with_details(p_store_id uuid, p_customer_id uuid, p_items jsonb, p_header jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;
 v_req uuid; v_hash text; v_prev public.invoices%rowtype;  -- 416: the form's request
begin
 if nullif(p_header->>'business_date','') is null then raise exception 'Invoice business date is required'; end if;
 -- 416: the same request sent again (its reply was lost and Create was
 -- pressed again) gets back the invoice it already made, not a second one.
 -- The same request id with other contents is refused (INVOICES-CREATE-15).
 -- A request with no request_id is made as before.
 v_req := nullif(p_header->>'request_id','')::uuid;
 if v_req is not null then
   v_hash := md5(jsonb_build_object('store_id', p_store_id, 'customer_id', p_customer_id,
                                    'items', p_items, 'header', p_header - 'request_id')::text);
   perform pg_advisory_xact_lock(hashtextextended('create_invoice_with_details:' || v_req::text, 0));
   select * into v_prev from public.invoices where create_request_id = v_req;
   if found then
     if not public.user_has_store_access(v_prev.store_id) then
       raise exception 'You do not have access to this store'; end if;
     if v_prev.deleted_at is not null then
       raise exception 'The invoice this request made (%) has been deleted. Open New Invoice again to make another.', v_prev.invoice_no; end if;
     -- The form was changed after its first save went through: that save
     -- made this invoice, so it is named, not made again.
     if v_prev.create_request_hash is distinct from v_hash then
       raise exception 'This form already made %. Open that invoice to change it, instead of creating another.', v_prev.invoice_no; end if;
     return v_prev.id;
   end if;
 end if;
 -- 416: never dated after today in Singapore (INVOICES-CREATE-11).
 if (p_header->>'business_date')::date > public.sg_today() then
   raise exception 'The invoice date cannot be after today.'; end if;
 if coalesce((p_header->>'manual_discount')::numeric,0) > 0
    and nullif(btrim(coalesce(p_header->>'manual_discount_reason','')),'') is null then
   raise exception 'MANUAL_DISCOUNT_REASON_REQUIRED: Give the internal reason for the manual discount.'; end if;
 perform set_config('invoice.manual_discount_reason', coalesce(p_header->>'manual_discount_reason',''), true);
 -- 370: event tickets are priced on this date.
 perform set_config('invoice.business_date', coalesce(p_header->>'business_date', ''), true);
 v_id:=public.create_invoice(p_store_id,p_customer_id,nullif(p_header->>'affiliate_id','')::uuid,p_items,
  coalesce((p_header->>'manual_discount')::numeric,0),p_header->>'notes',nullif(p_header->>'discount_voucher_id','')::uuid,
  coalesce(p_header->'service_staff','[]'));
 perform set_config('invoice.business_date', '', true);
 update public.invoices set business_date=(p_header->>'business_date')::date,
  instalment_category=nullif(p_header->>'instalment_category',''),
  instalment_method_id=nullif(p_header->>'instalment_method_id','')::uuid,
  instalment_months=nullif(p_header->>'instalment_months','')::int,
  manual_discount_reason=case when coalesce((p_header->>'manual_discount')::numeric,0) > 0
                              then nullif(btrim(p_header->>'manual_discount_reason'),'') end,
  create_request_id=v_req, create_request_hash=v_hash  -- 416
  where id=v_id;
 return v_id;
end $function$
$q$;
  c_ci_decl_a constant text := $q$ v399_open boolean := false;  -- 399: not yet paid in full: stock moves only if this settles it
$q$;
  c_ci_decl_r constant text := $q$ v399_open boolean := false;  -- 399: not yet paid in full: stock moves only if this settles it
 v416_v record; v416_have integer;  -- 416: a voucher's stock when a correction settles the invoice
 v416_r record; v416_back jsonb; v416_kept jsonb; v416_settles text;  -- 416: vouchers when the FOC is removed
 v416_pre uuid[];  -- 416: the movement rows that record what Confirm FOC took, written by this save
 v416_seen uuid[];  -- 416: the invoice's movement rows before this save takes stock
$q$;
  c_ci_date_a constant text := $q$ if p_header ? 'business_date' then n.business_date:=(p_header->>'business_date')::date; end if;
$q$;
  c_ci_date_r constant text := $q$ if p_header ? 'business_date' then n.business_date:=(p_header->>'business_date')::date; end if;
 -- 416: a date once set is kept, and a new date is never after today in
 -- Singapore (INVOICES-CREATE-11). An invoice saved with no date (before
 -- dates were required) may stay undated or be given a past date.
 if n.business_date is null and i.business_date is not null then
   raise exception 'Keep the invoice date; it cannot be cleared.'; end if;
 if n.business_date is distinct from i.business_date and n.business_date > public.sg_today() then
   raise exception 'The invoice date cannot be after today.'; end if;
$q$;
  c_ci_preview_a constant text := $q$  -- 356: money already received counts toward a credit line this correction added or swapped in.
  perform public.release_credit_package_paid_credit(i.id);
 end if;
$q$;
  c_ci_preview_r constant text := $q$  -- 356: money already received counts toward a credit line this correction added or swapped in.
  perform public.release_credit_package_paid_credit(i.id);
 end if;
 -- 416: Confirm FOC, and a correction that completed the invoice as FOC,
 -- took the limited vouchers it gave from stock with no
 -- invoice_voucher_movements row (rule 6), and deduct_invoice_stock nets
 -- voucher stock against those rows only. So before a save takes stock on
 -- a completed FOC invoice (its products change), or takes its FOC off, it
 -- records that take as rows ('Taken at Confirm FOC'): stock is not taken
 -- twice, a change to its products is not refused for want of the units it
 -- already took, and what rule 14 puts back comes off the rows. This is done
 -- here, before the correction summary stops, so its try records them the
 -- same way.
 -- How many: by voucher, the units the customer still has from the invoice
 -- less what its rows hold, wherever either sits, as deduct_invoice_stock
 -- nets them. (Counted store by store, a reopening's row at one store did
 -- not count for vouchers since moved to another, and was recorded again.)
 -- Where: at the stores that hold those vouchers, as they were before this
 -- save moves any, where their stock is out; the store whose rows lack the
 -- most first. Rule 14 and a cancel give that stock back at the vouchers'
 -- store, so each store's rows still add up. (Written at the invoice's
 -- store, they did not once an Owner had moved the invoice.)
 -- Which: only vouchers from voucher lines and promotion lines, the ones
 -- Confirm FOC takes stock for. A premium bundle takes its own vouchers'
 -- stock, and its vouchers keep the bundle line's id when they are moved
 -- or given again on a reopening, so the line's kind tells them apart.
 if i.status = 'completed_foc'
    and ((v_stock_change and v_had_stock)
         or not coalesce((select v.total_amount = 0 and v.has_foc from public.invoices v where v.id = i.id), false)) then
   with h as (  -- the vouchers the customer still has from the invoice's voucher and promotion lines
     select crv.voucher_id, crv.store_id, crv.quantity
       from public.invoice_benefit_values b
       join public.customer_reward_vouchers crv on crv.id = b.reward_voucher_id
       join public.vouchers vo on vo.id = crv.voucher_id
       join public.invoice_items it416 on it416.id = b.invoice_item_id
      where b.invoice_id = i.id and crv.status <> 'revoked' and vo.qty_type = 'limited' and crv.store_id is not null
        and it416.line_kind in ('voucher','promotion')
        and crv.source_type in ('invoice_voucher_sale','invoice_promotion_voucher','invoice_reopen','invoice_benefit_transfer')),
   l as (  -- by voucher and store: the units held there less what the rows hold there
     select u.voucher_id, u.store_id, sum(u.quantity)::integer as lack
       from (select h.voucher_id, h.store_id, h.quantity from h
             union all
             select mv.voucher_id, mv.store_id, -mv.quantity from public.invoice_voucher_movements mv
              where mv.invoice_id = i.id and mv.voucher_id in (select h.voucher_id from h)) u
      group by u.voucher_id, u.store_id),
   x as (  -- missing: what the voucher lacks in all; before: what the stores ahead of this one take of it
     select l.voucher_id, l.store_id, l.lack,
            sum(l.lack) over (partition by l.voucher_id) as missing,
            coalesce(sum(l.lack) over (partition by l.voucher_id order by l.lack desc, l.store_id
                                       rows between unbounded preceding and 1 preceding), 0) as before
       from l),
   ins as (
     insert into public.invoice_voucher_movements(invoice_id, voucher_id, store_id, quantity, reason, created_by)
     select i.id, x.voucher_id, x.store_id, least(x.lack, x.missing - x.before), 'Taken at Confirm FOC: ' || p_reason, auth.uid()
       from x where x.lack > 0 and x.missing > x.before
     returning id)
   select coalesce(array_agg(ins.id), '{}'::uuid[]) into v416_pre from ins;
 end if;
 -- 416: preview_invoice_correction tries the correction up to here, inside
 -- a block it always undoes, to show the corrected total and status before
 -- anyone saves (INVOICES-CREATE-M1). It stops here, before any payment
 -- change, status, document or commission, and hands back the corrected
 -- invoice. Nothing it did is kept.
 if current_setting('invoice.correction_preview', true) = 'on' then
   -- First the checks the save makes further down that no payment change
   -- can alter, so a refusal they raise reaches the summary too: the stock
   -- the corrected lines take (what they took was put back above, and what
   -- Confirm FOC took was recorded just above), the goods a part-paid
   -- customer has kept, a birthday discount for a changed customer or date,
   -- and the vouchers taken when the corrected lines settle the invoice, as
   -- FOC or as paid with the money it holds. Stock that moves only because a
   -- payment change settles a part-paid invoice is not tried.
   if v_stock_change and i.status not in ('cancelled','refunded') and v_had_stock and not v399_open then
     perform public.deduct_invoice_stock(i.id, 'Correction preview'); end if;
   if v399_open then perform public.invoice_goods_kept_check(i.id); end if;
   if (n.customer_id, n.business_date) is distinct from (i.customer_id, i.business_date) then
     perform public.invoice_birthday_lines_check(i.id); end if;
   if i.status not in ('paid','completed_foc','cancelled','refunded','cancellation_requested','refund_requested') then
     v416_settles := case when exists (select 1 from public.invoices v where v.id = i.id and v.total_amount = 0 and v.has_foc)
                            then 'completed_foc'
                          when public.invoice_net_received(i.id) > 0
                               and public.invoice_net_received(i.id) >= public.invoice_charge_total(i.id)
                            then 'paid' end;
   end if;
   if v416_settles is not null then
     for v416_v in select t.item_id, t.quantity from public.invoice_stock_to_deduct(i.id) t
                    where t.kind <> 'product' and t.quantity > 0 loop
       v416_have := coalesce((select s.current_qty from public.voucher_store_stock s
                               where s.store_id = n.store_id and s.voucher_id = v416_v.item_id), 0);
       if v416_have < v416_v.quantity then
         raise exception 'Not enough stock of the voucher "%" in this store%: % left, % needed.',
           (select vo.name from public.vouchers vo where vo.id = v416_v.item_id),
           case when v416_settles = 'completed_foc' then ' to give it free' else '' end, v416_have, v416_v.quantity; end if;
     end loop;
   end if;
   raise exception using errcode = 'P0416', message = 'Correction preview',
     detail = (select jsonb_build_object('total', v.total_amount, 'has_foc', coalesce(v.has_foc, false),
                        'charge', public.invoice_charge_total(v.id),
                        'lines', coalesce((select jsonb_agg(jsonb_build_object('id', it.id,
                                     'label', public.invoice_line_label(it.id), 'quantity', it.quantity,
                                     'line_total', it.line_total, 'foc_amount', coalesce(it.foc_amount, 0),
                                     'line_discount', coalesce(it.line_discount, 0)) order by it.id)
                                   from public.invoice_items it where it.invoice_id = v.id), '[]'::jsonb))::text
                 from public.invoices v where v.id = i.id);
 end if;
$q$;
  c_ci_deduct_a constant text := $q$ if v_stock_change and i.status not in ('cancelled','refunded') and v_had_stock
    and (not v399_open or v_status in ('paid','completed_foc')) then
   perform public.deduct_invoice_stock(i.id,'Invoice correction: '||p_reason); end if;
$q$;
  c_ci_deduct_r constant text := $q$ -- 416: what Confirm FOC took is recorded as rows further up, before the
 -- correction summary stops (rule 6).
 if v_stock_change and i.status not in ('cancelled','refunded') and v_had_stock
    and (not v399_open or v_status in ('paid','completed_foc')) then
   v416_seen := array(select mv.id from public.invoice_voucher_movements mv where mv.invoice_id = i.id);
   perform public.deduct_invoice_stock(i.id,'Invoice correction: '||p_reason);
   -- 416: a save that keeps the invoice completed FOC gives no voucher (they
   -- are given only when an invoice becomes settled), so it keeps no voucher
   -- stock either. What deduct_invoice_stock just took for a voucher line
   -- raised or added goes back, with a row that cancels its row. Kept, that
   -- row would later count as part of what Confirm FOC took, and the payment
   -- would take the unit again.
   if i.status = 'completed_foc' and v_status = 'completed_foc' then
     for v416_v in select mv.voucher_id, mv.store_id, mv.quantity from public.invoice_voucher_movements mv
                    where mv.invoice_id = i.id and mv.quantity > 0 and not (mv.id = any(v416_seen)) loop
       update public.voucher_store_stock set current_qty = current_qty + v416_v.quantity, updated_at = now()
        where voucher_id = v416_v.voucher_id and store_id = v416_v.store_id;
       insert into public.invoice_voucher_movements(invoice_id, voucher_id, store_id, quantity, reason, created_by)
       values (i.id, v416_v.voucher_id, v416_v.store_id, -v416_v.quantity,
               'Still FOC, nothing given for the change: ' || p_reason, auth.uid());
     end loop;
   end if;
 end if;
 -- 416: an invoice that stays completed FOC keeps no movement row for what
 -- Confirm FOC took (rule 6), so a cancel puts that stock back once.
 if v_status = 'completed_foc' and coalesce(cardinality(v416_pre), 0) > 0 then
   insert into public.invoice_voucher_movements(invoice_id, voucher_id, store_id, quantity, reason, created_by)
   select mv.invoice_id, mv.voucher_id, mv.store_id, -mv.quantity, 'Still FOC, so no row is kept: ' || p_reason, auth.uid()
     from public.invoice_voucher_movements mv where mv.id = any(v416_pre);
 end if;
$q$;
  c_ci_focv_a constant text := $q$ update public.invoices set status=v_status,paid_amount=v_paid,edit_count=coalesce(i.edit_count,0)+1,edited_by=auth.uid(),edited_at=now() where id=i.id;
$q$;
  c_ci_focv_r constant text := $q$ -- 416: a correction that settles the invoice gives its vouchers (voucher
 -- lines and a promotion's voucher picks) from this store's stock, before
 -- the status change below has them issued, and takes only what the invoice
 -- has not taken already (invoice_stock_to_deduct is net), so never twice.
 -- Completed as FOC, it takes them as Confirm FOC does, with no
 -- invoice_voucher_movements row (INVOICES-CREATE-7). Made paid in full, it
 -- takes them as Record Payment does, with that row (the Owner, 9 Oct 2026).
 -- Before, deduct_invoice_stock ran here only for an invoice that had
 -- already taken products, so a voucher invoice was made paid with its
 -- vouchers issued and no stock taken.
 if v_status in ('paid','completed_foc') and i.status not in ('paid','completed_foc') then
   for v416_v in select t.item_id, t.quantity from public.invoice_stock_to_deduct(i.id) t
                  where t.kind <> 'product' and t.quantity > 0 loop
     select s.current_qty into v416_have from public.voucher_store_stock s
      where s.store_id = n.store_id and s.voucher_id = v416_v.item_id for update;
     if coalesce(v416_have, 0) < v416_v.quantity then
       raise exception 'Not enough stock of the voucher "%" in this store%: % left, % needed.',
         (select vo.name from public.vouchers vo where vo.id = v416_v.item_id),
         case when v_status = 'completed_foc' then ' to give it free' else '' end,
         coalesce(v416_have, 0), v416_v.quantity; end if;
     update public.voucher_store_stock set current_qty = current_qty - v416_v.quantity, updated_at = now()
      where store_id = n.store_id and voucher_id = v416_v.item_id;
     if v_status = 'paid' then
       insert into public.invoice_voucher_movements(invoice_id, voucher_id, store_id, quantity, reason, created_by)
       values (i.id, v416_v.item_id, n.store_id, v416_v.quantity, 'Invoice correction settled it: ' || p_reason, auth.uid());
     else
       perform public.write_audit('vouchers', v416_v.item_id, 'voucher_sold', null,
         jsonb_build_object('invoice_no', n.invoice_no, 'qty', v416_v.quantity, 'foc', true, 'correction', true));
     end if;
   end loop;
 end if;
 -- 416: a correction that takes the FOC off a completed FOC invoice (it is
 -- unpaid or part-paid again) takes back the vouchers it gave that are still
 -- unused, and returns their stock. Used ones (redeemed, or a therapy
 -- voucher with sessions used) stay with the customer, and one moved to
 -- another customer stays with them; both are reported. All of it is
 -- audited (the Owner, 9 Oct 2026). What Confirm FOC took was recorded as
 -- movement rows above, and each voucher returned comes off them, so the
 -- rows hold what is still out: the payment that settles the invoice takes
 -- only the rest, once, and the vouchers the corrected lines give are given
 -- then (trg_issue_sold_vouchers_on_paid).
 -- Only vouchers from voucher lines and promotion lines are taken back: the
 -- FOC on a premium bundle line is not being removed, and its vouchers
 -- (moved, or given again on a reopening) keep the bundle line's id. A
 -- voucher moved to another store of the same customer is not "moved to
 -- another customer": it is unused and taken back like the others.
 if i.status = 'completed_foc' and v_status in ('unpaid','partially_paid') then
   v416_back := '[]'::jsonb; v416_kept := '[]'::jsonb;
   for v416_r in select crv.id, crv.voucher_id, crv.store_id, crv.quantity, b.id as benefit_id,
                        vo.name as voucher_name, vo.qty_type::text as qty_type,
                        (crv.source_type = 'invoice_benefit_transfer'
                         and crv.customer_id is distinct from i.customer_id) as moved,
                        (crv.status <> 'held' or crv.redeemed_at is not null
                         or exists (select 1 from public.therapy_voucher_issues t
                                     where t.reward_voucher_id = crv.id and t.sessions_used > 0)) as used
                   from public.invoice_benefit_values b
                   join public.customer_reward_vouchers crv on crv.id = b.reward_voucher_id
                   join public.vouchers vo on vo.id = crv.voucher_id
                   join public.invoice_items it416 on it416.id = b.invoice_item_id
                  where b.invoice_id = i.id and crv.status <> 'revoked'
                    and it416.line_kind in ('voucher','promotion')
                    and crv.source_type in ('invoice_voucher_sale','invoice_promotion_voucher','invoice_reopen','invoice_benefit_transfer')
                  order by crv.id
                    for update of crv, b loop
     if v416_r.moved then
       v416_kept := v416_kept || jsonb_build_array(v416_r.voucher_name || ' × ' || v416_r.quantity
                                                   || ' — moved to another customer; it stays with them');
       continue;
     end if;
     if v416_r.used then
       v416_kept := v416_kept || jsonb_build_array(v416_r.voucher_name || ' × ' || v416_r.quantity);
       continue;
     end if;
     update public.customer_reward_vouchers set status = 'revoked',
            notes = concat_ws(E'\n', notes, 'FOC removed from invoice ' || coalesce(n.invoice_no, '(no number)') || ': ' || p_reason)
      where id = v416_r.id;
     update public.invoice_benefit_values set cancelled_unused_value = cancelled_unused_value + v416_r.quantity
      where id = v416_r.benefit_id;
     if v416_r.qty_type = 'limited' and v416_r.store_id is not null then
       insert into public.voucher_store_stock as s (voucher_id, store_id, current_qty)
       values (v416_r.voucher_id, v416_r.store_id, v416_r.quantity)
       on conflict (voucher_id, store_id) do update set current_qty = s.current_qty + excluded.current_qty, updated_at = now();
       insert into public.invoice_voucher_movements(invoice_id, voucher_id, store_id, quantity, reason, created_by)
       values (i.id, v416_r.voucher_id, v416_r.store_id, -v416_r.quantity,
               'FOC removed: unused voucher back in stock: ' || p_reason, auth.uid());
     end if;
     perform public.write_audit_ex('customer_reward_vouchers', v416_r.id, 'foc_removed_voucher_taken_back',
       jsonb_build_object('status', 'held', 'quantity', v416_r.quantity),
       jsonb_build_object('status', 'revoked', 'invoice_no', n.invoice_no,
                          'stock_returned', case when v416_r.qty_type = 'limited' then v416_r.quantity else 0 end),
       'invoices', p_reason, v416_r.store_id);
     v416_back := v416_back || jsonb_build_array(v416_r.voucher_name || ' × ' || v416_r.quantity);
   end loop;
   if jsonb_array_length(v416_back) + jsonb_array_length(v416_kept) > 0 then
     perform public.write_audit_ex('invoices', i.id, 'foc_removed_vouchers', null,
       jsonb_build_object('invoice_no', n.invoice_no, 'taken_back', v416_back, 'kept_used', v416_kept),
       'invoices', p_reason, n.store_id);
   end if;
 end if;
 update public.invoices set status=v_status,paid_amount=v_paid,edit_count=coalesce(i.edit_count,0)+1,edited_by=auth.uid(),edited_at=now() where id=i.id;
$q$;
  c_ci_ret_a constant text := $q$ return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'revision',v_rev,'therapy',v362_therapy);
$q$;
  c_ci_ret_r constant text := $q$ return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'revision',v_rev,'therapy',v362_therapy)
   -- 416: what removing the FOC did to the vouchers it gave, for the page to say.
   || case when v416_back is null then '{}'::jsonb
           else jsonb_build_object('foc_vouchers', jsonb_build_object('taken_back', v416_back, 'kept_used', v416_kept)) end;
$q$;
  c_ci_docs_a constant text := $q$ if v_status='paid' and i.status is distinct from 'paid' then
   perform public.create_special_docs_for_invoice(i.id);
 elsif v_status='paid' and not same_lines then
$q$;
  c_ci_docs_r constant text := $q$ -- 416: an invoice completed as FOC is settled like a paid one, so its
 -- special and rental items are raised too (INVOICES-CREATE-7).
 if v_status in ('paid','completed_foc') and i.status not in ('paid','completed_foc') then
   perform public.create_special_docs_for_invoice(i.id);
 elsif v_status in ('paid','completed_foc') and not same_lines then
$q$;
  c_pv_vol_a constant text := $q$ LANGUAGE plpgsql
 STABLE SECURITY DEFINER
$q$;
  c_pv_vol_r constant text := $q$ LANGUAGE plpgsql
 SECURITY DEFINER
$q$;
  c_pv_decl_a constant text := $q$        v_moving jsonb; v_blocked jsonb; r record; v_net numeric; v_charge numeric; v_amount numeric; p public.invoice_payments%rowtype; pm public.payment_methods%rowtype; part record;
$q$;
  c_pv_decl_r constant text := $q$        v_moving jsonb; v_blocked jsonb; r record; v_net numeric; v_charge numeric; v_amount numeric; p public.invoice_payments%rowtype; pm public.payment_methods%rowtype; part record;
        -- 416: the corrected invoice, from a try of correct_invoice that is undone.
        v416_before jsonb; v416_dry jsonb; v416_detail text; v416_refusal text; v416_lines jsonb;
        v416_total numeric; v416_charge numeric; v416_net numeric; v416_status text;
        v416_owing numeric; v416_due numeric;
        v416_back jsonb; v416_kept jsonb;  -- 416: the vouchers removing the FOC takes back or leaves
$q$;
  c_pv_dry_a constant text := $q$  v_new_cust  := coalesce(nullif(p_header->>'customer_id','')::uuid, i.customer_id);
$q$;
  c_pv_dry_r constant text := $q$  -- 416: with the corrected lines (p_header.items) the correction is tried
  -- for real inside a block that is always undone, so the summary can say
  -- what it does to the total, the status and any refund due
  -- (INVOICES-CREATE-M1). correct_invoice stops itself when
  -- invoice.correction_preview is on, before any payment change, status,
  -- stock, document or commission, and hands back the corrected invoice. A
  -- refusal is what the save would be told. Without items, as before.
  if jsonb_typeof(p_header->'items') = 'array' then
    v416_before := (select coalesce(jsonb_agg(jsonb_build_object('id', it.id,
                       'label', public.invoice_line_label(it.id), 'quantity', it.quantity,
                       'line_total', it.line_total, 'foc_amount', coalesce(it.foc_amount, 0),
                       'line_discount', coalesce(it.line_discount, 0)) order by it.id), '[]'::jsonb)
                      from public.invoice_items it where it.invoice_id = i.id);
    begin
      perform set_config('invoice.correction_preview', 'on', true);
      perform public.correct_invoice(i.id, p_header->'items',
        p_header - 'items' - 'reason' - 'payment_methods' - 'payment_corrections' - 'payment_removals',
        coalesce(nullif(btrim(p_header->>'reason'), ''), 'Correction preview'), null);
      -- Nothing to change: correct_invoice returned before the stop. Undone too.
      raise exception using errcode = 'P0416', message = 'Correction preview',
        detail = jsonb_build_object('total', i.total_amount, 'has_foc', coalesce(i.has_foc, false),
                   'charge', public.invoice_charge_total(i.id), 'lines', v416_before)::text;
    exception
      when sqlstate 'P0416' then
        get stacked diagnostics v416_detail = pg_exception_detail;
        v416_dry := v416_detail::jsonb;
      when others then
        v416_refusal := sqlerrm;
    end;
    perform set_config('invoice.correction_preview', '', true);
  end if;

  v_new_cust  := coalesce(nullif(p_header->>'customer_id','')::uuid, i.customer_id);
$q$;
  c_pv_pay1_a constant text := $q$      if nullif(r.value->>'date','') is null then
        v_reviews := v_reviews || jsonb_build_array(jsonb_build_object('area','payments','detail',format('The %s payment needs the date the money was actually received.', pm.name)));
        continue; end if;
$q$;
  c_pv_pay1_r constant text := $q$      if nullif(r.value->>'date','') is null then
        v_reviews := v_reviews || jsonb_build_array(jsonb_build_object('area','payments','detail',format('The %s payment needs the date the money was actually received.', pm.name)));
        continue; end if;
      -- 416: as correct_invoice_payment refuses them.
      if (r.value->>'date')::date > public.sg_today() then
        v_reviews := v_reviews || jsonb_build_array(jsonb_build_object('area','payments','detail',format('The %s payment cannot be dated in the future.', pm.name)));
        continue; end if;
      if v_amount <> round(v_amount, 2) then
        v_reviews := v_reviews || jsonb_build_array(jsonb_build_object('area','payments','detail',format('The %s payment''s amount can have at most 2 decimal places.', pm.name)));
        continue; end if;
$q$;
  c_pv_pay2_a constant text := $q$          if exists (select 1 from public.payment_methods where id = nullif(part.value->>'payment_method_id','')::uuid and coalesce(is_wallet_credit,false)) then
            v_reviews := v_reviews || jsonb_build_array(jsonb_build_object('area','payments','detail','A part of a split cannot be wallet credit: a correction never consumes credit. Refund and re-take the payment instead.'));
            v_amount := -1; exit; end if;
$q$;
  c_pv_pay2_r constant text := $q$          if exists (select 1 from public.payment_methods where id = nullif(part.value->>'payment_method_id','')::uuid and coalesce(is_wallet_credit,false)) then
            v_reviews := v_reviews || jsonb_build_array(jsonb_build_object('area','payments','detail','A part of a split cannot be wallet credit: a correction never consumes credit. Refund and re-take the payment instead.'));
            v_amount := -1; exit; end if;
          -- 416: as split_invoice_payment refuses them.
          if (part.value->>'date')::date > public.sg_today()
             or (part.value->>'amount')::numeric <> round((part.value->>'amount')::numeric, 2) then
            v_reviews := v_reviews || jsonb_build_array(jsonb_build_object('area','payments','detail',format('Each part of the %s payment needs a date that is not in the future and an amount with at most 2 decimal places.', pm.name)));
            v_amount := -1; exit; end if;
$q$;
  c_pv_charge_a constant text := $q$    v_charge := public.invoice_charge_total(i.id);
$q$;
  c_pv_charge_r constant text := $q$    -- 416: against the corrected total when the correction was tried.
    v_charge := coalesce((v416_dry->>'charge')::numeric, public.invoice_charge_total(i.id));
$q$;
  c_pv_ret_a constant text := $q$  return jsonb_build_object(
    'invoice_id', i.id, 'invoice_no', i.invoice_no, 'status', i.status,
    'edit_count', coalesce(i.edit_count,0),
    'effects', v_effects,
    'needs_review', v_reviews,
    'blocking', jsonb_array_length(v_reviews) > 0,
    'affiliate', public.diagnose_invoice_affiliate(p_invoice_id));
$q$;
  c_pv_ret_r constant text := $q$  -- ---- 416: the corrected total, status and refund due ------------------
  if v416_refusal is not null then
    -- The save would be refused with this. The benefit question is asked above.
    if v416_refusal not like 'BENEFIT_ACTION_REQUIRED:%' then
      v_reviews := v_reviews || jsonb_build_array(jsonb_build_object('area','correction',
        'code', substring(v416_refusal from '^([A-Z_]+):'),
        'detail', regexp_replace(v416_refusal, '^[A-Z_]+:\s*', '')));
    end if;
  elsif v416_dry is not null then
    v416_total := (v416_dry->>'total')::numeric;
    v416_charge := (v416_dry->>'charge')::numeric;
    v416_net := coalesce(v_net, public.invoice_net_received(i.id));
    -- As correct_invoice works out the status.
    v416_status := case when i.status in ('cancelled','refunded','cancellation_requested','refund_requested') then i.status::text
                        when v416_total = 0 and coalesce((v416_dry->>'has_foc')::boolean, false) then 'completed_foc'
                        when v416_net >= v416_charge and v416_net > 0 then 'paid'
                        when v416_net > 0 then 'partially_paid' else 'unpaid' end;
    -- As invoice_financial_position shows what is owed and what is due back.
    v416_owing := case when v416_status in ('cancelled','refunded') then 0
                       else greatest(v416_charge - v416_net, 0) end;
    v416_due := greatest(v416_net - case when v416_status = 'cancelled' then 0 else v416_charge end, 0);
    v416_lines := (select coalesce(jsonb_agg(jsonb_build_object(
                      'change', case when b.e is null then 'added' when a.e is null then 'removed' else 'changed' end,
                      'label', coalesce(a.e->>'label', b.e->>'label'),
                      'quantity_before', (b.e->>'quantity')::integer, 'quantity_after', (a.e->>'quantity')::integer,
                      'charged_before', (b.e->>'line_total')::numeric - (b.e->>'line_discount')::numeric,
                      'charged_after', (a.e->>'line_total')::numeric - (a.e->>'line_discount')::numeric)
                      order by coalesce(a.e->>'label', b.e->>'label')), '[]'::jsonb)
                     from jsonb_array_elements(v416_before) b(e)
                     full join jsonb_array_elements(v416_dry->'lines') a(e) on a.e->>'id' = b.e->>'id'
                    where b.e is null or a.e is null
                       or (b.e->'quantity', b.e->'line_total', b.e->'foc_amount', b.e->'line_discount')
                          is distinct from (a.e->'quantity', a.e->'line_total', a.e->'foc_amount', a.e->'line_discount'));
    v_effects := v_effects || jsonb_build_array(jsonb_build_object(
      'area', 'total',
      'change', case when v416_total = coalesce(i.total_amount, 0) and v416_status = i.status::text then 'unchanged' else 'changed' end,
      'from', to_char(coalesce(i.total_amount, 0), 'FM999999990.00'), 'to', to_char(v416_total, 'FM999999990.00'),
      'detail',
        case when v416_total = coalesce(i.total_amount, 0)
             then format('The total stays S$%s.', to_char(v416_total, 'FM999999990.00'))
             else format('The total goes from S$%s to S$%s.', to_char(coalesce(i.total_amount, 0), 'FM999999990.00'),
                         to_char(v416_total, 'FM999999990.00')) end
        || ' ' ||
        case when v416_status in ('cancelled','refunded','cancellation_requested','refund_requested')
               then format('The invoice stays %s.', replace(v416_status, '_', ' '))
                    || case when v416_due > 0 then format(' S$%s is due back.', to_char(v416_due, 'FM999999990.00')) else '' end
             when v416_status = 'completed_foc'
               then 'The invoice becomes fully FOC.'
                    || case when v416_due > 0 then format(' S$%s becomes refund due.', to_char(v416_due, 'FM999999990.00')) else '' end
             when v416_status = 'paid' and v416_due > 0
               then format('S$%s becomes refund due.', to_char(v416_due, 'FM999999990.00'))
             when v416_status = 'paid'
               then case when i.status = 'paid' then 'It stays paid.' else 'It becomes paid.' end
             when v416_status = 'partially_paid'
               then format('The invoice %s part-paid with S$%s owing.',
                           case when i.status = 'partially_paid' then 'stays' else 'becomes' end,
                           to_char(v416_owing, 'FM999999990.00'))
             else format('Nothing is paid, so S$%s is owing.', to_char(v416_owing, 'FM999999990.00')) end));
    -- 416: taking the FOC off a completed FOC invoice takes back the
    -- vouchers it gave that are still unused, as correct_invoice does; used
    -- ones stay with the customer, and one moved to another customer stays
    -- with them (the Owner, 9 Oct 2026). Each is listed once, in 'items'.
    -- As in the save: voucher and promotion lines only, and a voucher moved
    -- to another store of the same customer is taken back.
    if i.status = 'completed_foc' and v416_status in ('unpaid','partially_paid') then
      select coalesce(jsonb_agg(x.what order by x.what) filter (where x.why is null), '[]'::jsonb),
             coalesce(jsonb_agg(jsonb_build_object('kind', 'voucher', 'what', x.what, 'why', x.why)
                                order by x.what) filter (where x.why is not null), '[]'::jsonb)
        into v416_back, v416_kept
        from (select vo.name || ' × ' || crv.quantity as what,
                     case when crv.source_type = 'invoice_benefit_transfer'
                               and crv.customer_id is distinct from i.customer_id
                            then 'moved to another customer; it stays with them'
                          when crv.status <> 'held' or crv.redeemed_at is not null
                               or exists (select 1 from public.therapy_voucher_issues t
                                           where t.reward_voucher_id = crv.id and t.sessions_used > 0)
                            then 'used; it stays with the customer' end as why
                from public.invoice_benefit_values b
                join public.customer_reward_vouchers crv on crv.id = b.reward_voucher_id
                join public.vouchers vo on vo.id = crv.voucher_id
                join public.invoice_items it416 on it416.id = b.invoice_item_id
               where b.invoice_id = i.id and crv.status <> 'revoked'
                 and it416.line_kind in ('voucher','promotion')
                 and crv.source_type in ('invoice_voucher_sale','invoice_promotion_voucher','invoice_reopen','invoice_benefit_transfer')) x;
      if jsonb_array_length(v416_back) + jsonb_array_length(v416_kept) > 0 then
        v_effects := v_effects || jsonb_build_array(jsonb_build_object(
          'area', 'vouchers', 'change', 'changed',
          'detail', case when jsonb_array_length(v416_back) > 0
                         then format('Removing the FOC takes back the unused vouchers it gave (%s). They are given again as the corrected lines give them when the invoice is paid.',
                                     (select string_agg(e, ', ') from jsonb_array_elements_text(v416_back) e))
                         when v416_kept @> '[{"why": "moved to another customer; it stays with them"}]'
                         then 'Removing the FOC takes back no voucher: the vouchers it gave have been used or moved to another customer.'
                         else 'Removing the FOC takes back no voucher: the vouchers it gave have been used.' end,
          'items', v416_kept));
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'invoice_id', i.id, 'invoice_no', i.invoice_no, 'status', i.status,
    'edit_count', coalesce(i.edit_count,0),
    'effects', v_effects,
    'needs_review', v_reviews,
    'blocking', jsonb_array_length(v_reviews) > 0,
    'affiliate', public.diagnose_invoice_affiliate(p_invoice_id))
    -- 416: only when the corrected lines were sent.
    || case when v416_dry is null and v416_refusal is null then '{}'::jsonb
            else jsonb_build_object('outcome', case when v416_refusal is not null
              then jsonb_build_object('checked', false, 'refusal', v416_refusal)
              else jsonb_build_object('checked', true,
                     'total_before', coalesce(i.total_amount, 0), 'total_after', v416_total,
                     'status_before', i.status, 'status_after', v416_status,
                     'charge_after', v416_charge, 'paid_after', v416_net,
                     'outstanding_after', v416_owing, 'refund_due_after', v416_due,
                     'lines', v416_lines) end) end;
$q$;
  c_lp_search_a constant text := $q$             or to_char(i.business_date,'YYYY-MM-DD')  ilike '%'||v_q||'%'
             or to_char(i.business_date,'DD/MM/YYYY')  ilike '%'||v_q||'%'
             or to_char(i.created_at,'YYYY-MM-DD')     ilike '%'||v_q||'%'
$q$;
  c_lp_search_r constant text := $q$             -- 416: the day the list shows (the business date, or for an
             -- undated invoice the Singapore day it was made) as shown,
             -- DD/MM/YYYY, and as YYYY-MM-DD or 8 Aug 2026; and, as before,
             -- the day it was made, now the Singapore day rather than UTC's
             -- (INVOICES-CREATE-12).
             or to_char(coalesce(i.business_date, (i.created_at at time zone 'Asia/Singapore')::date), 'DD/MM/YYYY') ilike '%'||v_q||'%'
             or to_char(coalesce(i.business_date, (i.created_at at time zone 'Asia/Singapore')::date), 'YYYY-MM-DD') ilike '%'||v_q||'%'
             -- A whole day, "8 Aug 2026" or "08 Aug 2026", finds that day
             -- only, not 18 or 28 Aug; so does "8 Aug", in any year. Part
             -- of one with a number, "Aug 2026", finds any day it is part
             -- of. A month name counts as a date only with a number: "Jun"
             -- alone stays a name search (the Owner, 9 Oct 2026).
             or case when v_q ~* '^[0-9]{1,2} [a-z]{3} [0-9]{4}$'
                     then lower(v_q) in (lower(to_char(coalesce(i.business_date, (i.created_at at time zone 'Asia/Singapore')::date), 'FMDD Mon YYYY')),
                                         lower(to_char(coalesce(i.business_date, (i.created_at at time zone 'Asia/Singapore')::date), 'DD Mon YYYY')))
                     when v_q ~* '^[0-9]{1,2} [a-z]{3}$'
                     then lower(v_q) in (lower(to_char(coalesce(i.business_date, (i.created_at at time zone 'Asia/Singapore')::date), 'FMDD Mon')),
                                         lower(to_char(coalesce(i.business_date, (i.created_at at time zone 'Asia/Singapore')::date), 'DD Mon')))
                     when v_q ~ '[0-9]'
                     then to_char(coalesce(i.business_date, (i.created_at at time zone 'Asia/Singapore')::date), 'DD Mon YYYY') ilike '%'||v_q||'%'
                     else false end
             or to_char((i.created_at at time zone 'Asia/Singapore')::date, 'YYYY-MM-DD') ilike '%'||v_q||'%'
$q$;
  c_lp_ord1_a constant text := $q$  ), ordered as (
    select m.* from matched m
     order by
$q$;
  c_lp_ord1_r constant text := $q$  ), ordered as (
    -- 416: each row is numbered in the page's order, and the page's rows are
    -- put together in that order (INVOICES-CREATE-12).
    select x.* from (select m.*, row_number() over (order by
$q$;
  c_lp_ord2_a constant text := $q$       m.sort_no desc
     offset v_offset limit v_limit
  )
$q$;
  c_lp_ord2_r constant text := $q$       m.sort_no desc) as rn
      from matched m) x
     order by x.rn
     offset v_offset limit v_limit
  )
$q$;
  c_lp_agg_a constant text := $q$  select coalesce(jsonb_agg(to_jsonb(o) - 'sort_no'), '[]'::jsonb),
$q$;
  c_lp_agg_r constant text := $q$  select coalesce(jsonb_agg(to_jsonb(o) - 'sort_no' - 'rn' order by o.rn), '[]'::jsonb),
$q$;
  c_af_state_a constant text := $q$  if v_inv.deleted_at is not null then raise exception 'Invoice has been deleted'; end if;
  if v_inv.status in ('paid','cancelled','refunded','completed_foc') then
    raise exception 'FOC cannot be changed on a % invoice', v_inv.status; end if;
  if v_inv.locked_at is not null then raise exception 'Invoice is locked'; end if;
$q$;
  c_af_state_r constant text := $q$  if v_inv.deleted_at is not null then raise exception 'Invoice has been deleted'; end if;
  if v_inv.status in ('paid','cancelled','refunded','completed_foc') then
    raise exception 'FOC cannot be changed on a % invoice', v_inv.status; end if;
  if v_inv.locked_at is not null then raise exception 'Invoice is locked'; end if;
  -- 416: as on screen, only while nothing is paid: a draft or unpaid invoice
  -- with no payment recorded (INVOICES-CREATE-8). On a part-paid invoice it
  -- would leave more paid than the invoice charges.
  if v_inv.status not in ('draft','unpaid') or coalesce(v_inv.paid_amount,0) <> 0
     or exists (select 1 from public.invoice_payments ip416 where ip416.invoice_id = v_inv.id) then
    raise exception 'FOC can only be changed before any payment is recorded on the invoice.'; end if;
$q$;
  c_foc_recalc_a constant text := $q$  perform public.recalc_invoice_foc(v_li.invoice_id);
$q$;
  c_foc_recalc_r constant text := $q$  -- 416: an Edit Invoice another user has open must notice this change
  -- (INVOICES-CREATE-M2).
  update public.invoices set edit_count = coalesce(edit_count, 0) + 1 where id = v_li.invoice_id;
  perform public.recalc_invoice_foc(v_li.invoice_id);
$q$;
  c_rf_found_a constant text := $q$  select * into v_inv from public.invoices where id = v_li.invoice_id for update;

  if auth.uid() is not null then
$q$;
  c_rf_found_r constant text := $q$  select * into v_inv from public.invoices where id = v_li.invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;  -- 416

  if auth.uid() is not null then
$q$;
  c_rf_state_a constant text := $q$  if v_inv.status in ('paid','cancelled','refunded','completed_foc') then
    raise exception 'FOC cannot be changed on a % invoice', v_inv.status; end if;
  if coalesce(v_li.foc_quantity,0) = 0 then raise exception 'This line has no FOC to remove'; end if;
$q$;
  c_rf_state_r constant text := $q$  -- 416: a deleted or locked invoice is refused, as by Make FOC (INVOICES-CREATE-8).
  if v_inv.deleted_at is not null then raise exception 'Invoice has been deleted'; end if;
  if v_inv.status in ('paid','cancelled','refunded','completed_foc') then
    raise exception 'FOC cannot be changed on a % invoice', v_inv.status; end if;
  if v_inv.locked_at is not null then raise exception 'Invoice is locked'; end if;
  -- 416: as on screen, only while nothing is paid: a draft or unpaid invoice
  -- with no payment recorded (INVOICES-CREATE-8). On a part-paid invoice it
  -- would leave more paid than the invoice charges.
  if v_inv.status not in ('draft','unpaid') or coalesce(v_inv.paid_amount,0) <> 0
     or exists (select 1 from public.invoice_payments ip416 where ip416.invoice_id = v_inv.id) then
    raise exception 'FOC can only be changed before any payment is recorded on the invoice.'; end if;
  if coalesce(v_li.foc_quantity,0) = 0 then raise exception 'This line has no FOC to remove'; end if;
$q$;
  c_sa_found_a constant text := $q$  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if v_inv.locked_at is not null or v_inv.status not in ('draft','unpaid')
$q$;
  c_sa_found_r constant text := $q$  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found or v_inv.deleted_at is not null then raise exception 'Invoice not found'; end if;  -- 416: a deleted one too
  if v_inv.locked_at is not null or v_inv.status not in ('draft','unpaid')
$q$;
  c_sa_upd_a constant text := $q$  update public.invoices set affiliate_selection_explicit=true, affiliate_id = p_affiliate_id where id = p_invoice_id;
$q$;
  c_sa_upd_r constant text := $q$  -- 416: with edit_count, so an Edit Invoice another user has open notices
  -- (INVOICES-CREATE-M2).
  update public.invoices set affiliate_selection_explicit=true, affiliate_id = p_affiliate_id,
         edit_count = coalesce(edit_count, 0) + 1 where id = p_invoice_id;
$q$;
  c_sf_found_a constant text := $q$  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if v_inv.status not in ('draft','unpaid','partially_paid') then
$q$;
  c_sf_found_r constant text := $q$  select * into v_inv from public.invoices where id = p_invoice_id for update;
  -- 416: a deleted invoice is not found, and the invoice must be of one of
  -- the caller's stores (INVOICES-CREATE-16).
  if not found or v_inv.deleted_at is not null then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then
    raise exception 'You do not have access to this invoice''s store'; end if;
  if v_inv.status not in ('draft','unpaid','partially_paid') then
$q$;
  c_sf_clear_a constant text := $q$    update public.invoices set fulfil_warehouse_id = null where id = p_invoice_id;
$q$;
  c_sf_clear_r constant text := $q$    -- 416: with edit_count when it changes (INVOICES-CREATE-M2).
    update public.invoices set fulfil_warehouse_id = null,
           edit_count = coalesce(edit_count, 0) + (fulfil_warehouse_id is not null)::integer
     where id = p_invoice_id;
$q$;
  c_sf_set_a constant text := $q$  update public.invoices set fulfil_warehouse_id = p_warehouse_id where id = p_invoice_id;
$q$;
  c_sf_set_r constant text := $q$  -- 416: with edit_count when it changes (INVOICES-CREATE-M2).
  update public.invoices set fulfil_warehouse_id = p_warehouse_id,
         edit_count = coalesce(edit_count, 0) + (fulfil_warehouse_id is distinct from p_warehouse_id)::integer
   where id = p_invoice_id;
$q$;
  c_cf_a constant text := $q$  update public.invoices
     set status = 'completed_foc', paid_amount = 0, paid_at = now(), locked_at = now(),
         foc_confirmed_at = now(), foc_confirmed_by = auth.uid()
   where id = p_invoice_id;
$q$;
  c_cf_r constant text := $q$  update public.invoices
     set status = 'completed_foc', paid_amount = 0, paid_at = now(), locked_at = now(),
         foc_confirmed_at = now(), foc_confirmed_by = auth.uid()
   where id = p_invoice_id;
  -- 416: special products and rentals given free still go to the warehouse
  -- queue and to rental tracking, as when an invoice is paid. The vouchers it
  -- gives are issued by trg_issue_sold_vouchers_on_paid (INVOICES-CREATE-7).
  perform public.create_special_docs_for_invoice(p_invoice_id);
$q$;
  c_tv_def constant text := $q$CREATE OR REPLACE FUNCTION public.trg_issue_sold_vouchers_on_paid()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l record; b record; v_left integer; v_units integer; q uuid; rv uuid; n integer := 0;  -- 416
begin
 -- 416: an invoice completed as FOC is settled too, so the vouchers it gives
 -- (voucher lines and a promotion's voucher picks) are issued as for a paid
 -- one (INVOICES-CREATE-7). Issuing again adds nothing.
 if new.status::text in ('paid','completed_foc') and old.status::text not in ('paid','completed_foc') then
  perform public.issue_sold_vouchers_for_invoice(new.id);
  -- 416: vouchers taken back when the FOC was removed (correct_invoice) are
  -- given again now the invoice is settled again, as the corrected lines give
  -- them (the Owner, 9 Oct 2026). The issuers above skip a line that gave
  -- vouchers before, so on each line that had vouchers taken back this gives
  -- what the line gives now, less what is still out on it (used, moved to
  -- another customer, or just issued for a new pick). A quantity raised or
  -- lowered, or a voucher swapped, in the save that took the FOC off is
  -- followed. Each unit is a replacement of a voucher of the same kind taken
  -- back on that line, recorded as a reopened invoice's are (an
  -- invoice_reopen_vouchers row, applied at once; source 'invoice_reopen'),
  -- never more units at once than that voucher had, so a therapy voucher
  -- keeps its recorded rights. A voucher the line did not give before is
  -- issued as the line's sale. Each is worth its share of what the line now
  -- charges. No stock is taken here: the payment or FOC that settles the
  -- invoice took it. A voucher taken back by a cancellation is replaced by
  -- its reopening: that trigger (invoice_reopen_vouchers_settled) runs before
  -- this one and clears what it replaces, so nothing is given twice. A
  -- voucher the customer had moved to another of their stores
  -- ('invoice_benefit_transfer') and that was taken back is given again
  -- here too, at the invoice's store, where the payment took its stock.
  if new.customer_id is not null then
   for l in with taken as (
              select distinct bv.invoice_item_id
                from public.invoice_benefit_values bv
                join public.customer_reward_vouchers crv on crv.id = bv.reward_voucher_id
               where bv.invoice_id = new.id and crv.status = 'revoked' and bv.cancelled_unused_value > 0
                 and crv.source_type in ('invoice_voucher_sale','invoice_promotion_voucher','invoice_reopen','invoice_benefit_transfer')),
            owed as (
              select it.id as item_id, it.voucher_id, 'voucher'::text as line_kind,
                     greatest(coalesce(it.quantity, 1), 1)::integer as units
                from public.invoice_items it join taken t on t.invoice_item_id = it.id
               where it.line_kind = 'voucher' and it.voucher_id is not null
              union all
              select c.invoice_item_id, c.voucher_id, 'promotion', c.units
                from public.invoice_promotion_voucher_components(new.id) c
                join taken t on t.invoice_item_id = c.invoice_item_id)
            select o.item_id, o.voucher_id, o.line_kind,
                   (o.units - coalesce((select sum(crv.quantity)
                                          from public.invoice_benefit_values bv
                                          join public.customer_reward_vouchers crv on crv.id = bv.reward_voucher_id
                                         where bv.invoice_id = new.id and bv.invoice_item_id = o.item_id
                                           and crv.voucher_id = o.voucher_id and crv.status <> 'revoked'), 0))::integer as give,
                   (sum(o.units) over (partition by o.item_id))::integer as line_units
              from owed o
             order by o.item_id, o.voucher_id loop
    continue when l.give <= 0;
    v_left := l.give;
    -- Replacements of the vouchers of this kind taken back on this line.
    while v_left > 0 and exists (select 1 from public.invoice_benefit_values bv
                                   join public.customer_reward_vouchers crv on crv.id = bv.reward_voucher_id
                                  where bv.invoice_id = new.id and bv.invoice_item_id = l.item_id
                                    and crv.voucher_id = l.voucher_id and crv.status = 'revoked'
                                    and least(bv.cancelled_unused_value, bv.granted_value)::integer > 0
                                    and crv.source_type in ('invoice_voucher_sale','invoice_promotion_voucher','invoice_reopen','invoice_benefit_transfer')) loop
     for b in select bv.id, least(bv.cancelled_unused_value, bv.granted_value)::integer as units
                from public.invoice_benefit_values bv
                join public.customer_reward_vouchers crv on crv.id = bv.reward_voucher_id
               where bv.invoice_id = new.id and bv.invoice_item_id = l.item_id
                 and crv.voucher_id = l.voucher_id and crv.status = 'revoked'
                 and least(bv.cancelled_unused_value, bv.granted_value)::integer > 0
                 and crv.source_type in ('invoice_voucher_sale','invoice_promotion_voucher','invoice_reopen','invoice_benefit_transfer')
               order by bv.id loop
      exit when v_left <= 0;
      v_units := least(v_left, b.units);
      insert into public.invoice_reopen_vouchers(invoice_id, benefit_id, request_id, quantity, applied_at)
      values (new.id, b.id, gen_random_uuid(), v_units, now()) returning id into q;
      insert into public.customer_reward_vouchers
        (customer_id, voucher_id, store_id, quantity, status, issued_by, source_type, source_id, notes)
      values (new.customer_id, l.voucher_id, new.store_id, v_units, 'held', auth.uid(), 'invoice_reopen', q,
              'Given again when invoice ' || coalesce(new.invoice_no, '(no number)')
              || ' was settled; taken back when its FOC was removed')
      returning id into rv;
      insert into public.invoice_benefit_values
        (invoice_id, invoice_item_id, reward_voucher_id, paid_value, granted_value, evidence, created_by)
      values (new.id, l.item_id, rv,
              round(coalesce(public.invoice_discounted_line_value(l.item_id), 0) * v_units / l.line_units, 2),
              v_units, 'Given again after the FOC was removed; original allocation ' || b.id, auth.uid());
      update public.invoice_reopen_vouchers set replacement_voucher_id = rv where id = q;
      v_left := v_left - v_units;
      n := n + 1;
     end loop;
    end loop;
    -- A voucher this line did not give before (its voucher was swapped).
    if v_left > 0 then
     insert into public.customer_reward_vouchers
       (customer_id, voucher_id, store_id, quantity, status, issued_by, source_type, source_id, notes)
     values (new.customer_id, l.voucher_id, new.store_id, v_left, 'held', auth.uid(),
             case when l.line_kind = 'voucher' then 'invoice_voucher_sale' else 'invoice_promotion_voucher' end, l.item_id,
             'Sold on invoice ' || coalesce(new.invoice_no, '(no number)') || ', as corrected when its FOC was removed')
     returning id into rv;
     insert into public.invoice_benefit_values
       (invoice_id, invoice_item_id, reward_voucher_id, paid_value, granted_value, evidence, created_by)
     values (new.id, l.item_id, rv,
             round(coalesce(public.invoice_discounted_line_value(l.item_id), 0) * v_left / l.line_units, 2),
             v_left, 'Issued when the invoice was settled after its FOC was removed', auth.uid());
     n := n + 1;
    end if;
   end loop;
   -- Every voucher taken back is settled now: given again, or no longer owed
   -- by the corrected lines.
   update public.invoice_benefit_values bv set cancelled_unused_value = 0
     from public.customer_reward_vouchers crv
    where crv.id = bv.reward_voucher_id and bv.invoice_id = new.id and crv.status = 'revoked'
      and bv.cancelled_unused_value > 0
      and crv.source_type in ('invoice_voucher_sale','invoice_promotion_voucher','invoice_reopen','invoice_benefit_transfer');
   if n > 0 then
    perform public.write_audit_ex('invoices', new.id, 'foc_removed_vouchers_given_again', null,
      jsonb_build_object('records', n, 'invoice_no', new.invoice_no), 'invoices', null, new.store_id);
   end if;
  end if;
 end if;
 return null;
end $function$
$q$;
  c_rp_a constant text := $q$ for x in select * from jsonb_array_elements(p_payments) loop
  select * into m from public.payment_methods where id=(x->>'payment_method_id')::uuid and is_active and deleted_at is null;
$q$;
  c_rp_r constant text := $q$ for x in select * from jsonb_array_elements(p_payments) loop
  -- 416: money is kept in cents. A third decimal place was stored rounded
  -- and could leave the invoice part paid with S$0.00 owing (INVOICES-CREATE-9).
  if (x->>'amount')::numeric <> round((x->>'amount')::numeric, 2) then
   raise exception 'Payment amounts can have at most 2 decimal places.'; end if;
  select * into m from public.payment_methods where id=(x->>'payment_method_id')::uuid and is_active and deleted_at is null;
$q$;
  c_ri_a constant text := $q$    if v_amount is null or v_amount <= 0 then raise exception 'Payment amount must be positive'; end if;
$q$;
  c_ri_r constant text := $q$    if v_amount is null or v_amount <= 0 then raise exception 'Payment amount must be positive'; end if;
    -- 416: in cents (INVOICES-CREATE-9). A late fee's payment comes here too.
    if v_amount <> round(v_amount, 2) then
      raise exception 'Payment amounts can have at most 2 decimal places.'; end if;
$q$;
  c_cp_a constant text := $q$ if p_amount is null or p_amount<=0 or p_date is null then raise exception 'A positive corrected amount and actual payment date are required'; end if;
$q$;
  c_cp_r constant text := $q$ if p_amount is null or p_amount<=0 or p_date is null then raise exception 'A positive corrected amount and actual payment date are required'; end if;
 -- 416: never dated after today in Singapore, as a new payment is not
 -- (INVOICES-AFTER-16), and in cents (INVOICES-CREATE-9).
 if p_date > public.sg_today() then raise exception 'A payment cannot be dated in the future'; end if;
 if p_amount <> round(p_amount, 2) then raise exception 'Payment amounts can have at most 2 decimal places.'; end if;
$q$;
  c_sp_a constant text := $q$    if coalesce((part.value->>'amount')::numeric, 0) <= 0 or nullif(part.value->>'date', '') is null then
      raise exception 'Each part of a split needs a positive amount and the date the money was received'; end if;
$q$;
  c_sp_r constant text := $q$    if coalesce((part.value->>'amount')::numeric, 0) <= 0 or nullif(part.value->>'date', '') is null then
      raise exception 'Each part of a split needs a positive amount and the date the money was received'; end if;
    -- 416: never dated after today in Singapore (INVOICES-AFTER-16), and in
    -- cents (INVOICES-CREATE-9).
    if (part.value->>'date')::date > public.sg_today() then
      raise exception 'A payment cannot be dated in the future'; end if;
    if (part.value->>'amount')::numeric <> round((part.value->>'amount')::numeric, 2) then
      raise exception 'Payment amounts can have at most 2 decimal places.'; end if;
$q$;
  c_il_def constant text := $q$CREATE OR REPLACE FUNCTION public.set_invoice_instalment_label(p_invoice_id uuid, p_method_id uuid, p_months integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_inv public.invoices%rowtype; v_old jsonb; v_new jsonb;
begin
  select * into v_inv from public.invoices
   where id = p_invoice_id and deleted_at is null for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then
    raise exception 'No access to this invoice' using errcode = '42501'; end if;

  -- 416: terms go with money taken on an invoice that is still open or paid
  -- (INVOICES-CREATE-M3). Record Payment stamps them after the payment it
  -- records, so the receipt is there already.
  if v_inv.status in ('cancelled','refunded','completed_foc') then
    raise exception 'Instalment terms cannot be set on a % invoice.', case v_inv.status when 'completed_foc' then 'free (FOC)' else v_inv.status::text end; end if;
  if not exists (select 1 from public.invoice_payments ip where ip.invoice_id = v_inv.id) then
    raise exception 'Record a payment first. Instalment terms are set with the payment they belong to.'; end if;

  -- Clearing the label is a legitimate request: a payment corrected back to an
  -- ordinary method should not leave instalment terms behind.
  if p_method_id is null or p_months is null then
    v_new := jsonb_build_object('instalment_category', null, 'instalment_method_id', null, 'instalment_months', null);
  else
    if p_months <= 0 then
      raise exception 'An instalment needs a positive whole number of months'; end if;

    -- The same rule the metadata trigger enforces, raised here where it can be
    -- said in terms of the field the operator actually chose.
    if not exists (select 1 from public.payment_methods
                    where id = p_method_id and is_active and deleted_at is null
                      and not coalesce(is_wallet_credit, false)) then
      raise exception 'Choose an active payment method for the instalment'; end if;

    -- in_house is the only category these screens now offer. The column keeps its
    -- check constraint and provider_funded stays valid for the rows that carry it.
    v_new := jsonb_build_object('instalment_category', 'in_house', 'instalment_method_id', p_method_id,
                                'instalment_months', p_months);
  end if;
  v_old := jsonb_build_object('instalment_category', v_inv.instalment_category,
                              'instalment_method_id', v_inv.instalment_method_id,
                              'instalment_months', v_inv.instalment_months);
  -- 416: the same terms again (a later instalment paid) change nothing.
  if v_new = v_old then return; end if;
  -- 416: terms already on the invoice are changed or cleared by an Owner or
  -- Manager only. Staff change them with Correct Invoice, which keeps a
  -- revision.
  if (v_inv.instalment_category, v_inv.instalment_method_id, v_inv.instalment_months) is distinct from (null, null, null)
     and not public.is_owner_or_manager() then
    raise exception 'This invoice already has instalment terms. To change them, use Correct Invoice, or ask an Owner or Manager.'; end if;

  update public.invoices
     set instalment_category  = v_new->>'instalment_category',
         instalment_method_id = (v_new->>'instalment_method_id')::uuid,
         instalment_months    = (v_new->>'instalment_months')::integer
   where id = p_invoice_id;
  -- 416: every change is in the history, with the terms before and after.
  perform public.write_audit_ex('invoices', p_invoice_id, 'instalment_terms_set', v_old, v_new,
    'invoice', null, v_inv.store_id);
end $function$
$q$;

  c_after_create_invoice constant text := '80c80d386a5241e63b353e35e13ef250';
  c_after_update_invoice_internal constant text := '8e674fe0d5e35ed5c2e93d417f14c05a';
  c_after_create_invoice_with_details constant text := '0f408a1a350b68fd86cd24109c85c05b';
  c_after_correct_invoice constant text := '8a126ade5710d340378ac4e75931b05b';
  c_after_preview_invoice_correction constant text := 'be5d652d71df0499d41edeba1c395717';
  c_after_invoice_list_page constant text := '2c0017c93df1d7eb10f6eb44f63fb7b7';
  c_after_apply_line_foc constant text := '5fbd0b6feb36e11dea6be231ffa0e952';
  c_after_remove_line_foc constant text := '9f9f31876bbf3c13d5838d183ef41b8d';
  c_after_set_invoice_affiliate constant text := 'eb4dc4b9b7eda73ef75a122d48dcdb6a';
  c_after_set_invoice_fulfilment_warehouse constant text := '66bf7f38e06bf48116b63b71ca7663cb';
  c_after_confirm_foc_invoice constant text := 'ba8b1ce2a5671989b927891f0cb7b1a2';
  c_after_trg_issue_sold_vouchers_on_paid constant text := 'c840d0d2754e7a8e889848ea8269a293';
  c_after_record_invoice_payment constant text := 'c3da81f28d5a24a1c5f336527cfc33a4';
  c_after_invoice_record_payments_internal constant text := '21890d84bcb0b9c00a2bc98aff313d0b';
  c_after_correct_invoice_payment constant text := 'f3c96d9916a95a68a9202cdb25d8017b';
  c_after_split_invoice_payment constant text := 'e385a9958c78dc9dc2aa82737958689e';
  c_after_set_invoice_instalment_label constant text := '8ff9ae95f434a0123d130b46527207ef';

  -- invoices' two new columns, and the index, as this makes them.
  c_cols constant text := 'create_request_hash text|create_request_id uuid';
  c_index constant text := 'CREATE UNIQUE INDEX invoices_create_request_id_key ON public.invoices USING btree (create_request_id) WHERE (create_request_id IS NOT NULL)';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  r record; d text; v text; n int; k int; i int; v_bad text; v_acl text[];
  v_fns text[] := '{}'; v_defs text[] := '{}';
  v_owner uuid; v_store uuid; v_cust uuid; v_pm uuid; v_inv uuid; v_pay uuid; v_res jsonb; v_err text;
begin
  -- The definitions are read and compared with public alone on the search
  -- path, as they were read on 9 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── Guards, anchors and new texts: nothing is installed unless all pass ────
  for r in select * from (values
    -- The invoice's own day: create_invoice's v_bdate (the business date
    -- create_invoice_with_details passes in, or today); in an edit, the
    -- invoice's business date, or the Singapore day an undated one was made,
    -- as 384 reads it for a line's Discount.
    ('create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)', 'ca369228b873e4b7f7ffcb0a4ca13fa2', c_after_create_invoice, null::text,
     array[[c_promo_a, replace(c_promo_r, '@DAY@', 'v_bdate')], [c_child_a, c_child_r]]),
    ('update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)', 'ae651ca1f5d80f46172f7601d9691966', c_after_update_invoice_internal, null::text,
     array[[c_promo_a, replace(c_promo_r, '@DAY@', 'coalesce(v_old.business_date, (v_old.created_at at time zone ''Asia/Singapore'')::date)')], [c_child_a, c_child_r], [c_uii_del_a, c_uii_del_r]]),
    ('create_invoice_with_details(uuid,uuid,jsonb,jsonb)', 'e5b1c9ddb9404439123cd2fdb49f6b21', c_after_create_invoice_with_details, c_ciwd_def,
     null::text[]),
    ('correct_invoice(uuid,jsonb,jsonb,text,uuid)', '5f3f317dfb226be09055142dc44bdec7', c_after_correct_invoice, null::text,
     array[[c_ci_decl_a, c_ci_decl_r], [c_ci_date_a, c_ci_date_r], [c_ci_preview_a, c_ci_preview_r], [c_ci_deduct_a, c_ci_deduct_r], [c_ci_focv_a, c_ci_focv_r], [c_ci_docs_a, c_ci_docs_r], [c_ci_ret_a, c_ci_ret_r]]),
    ('preview_invoice_correction(uuid,jsonb)', '99b1b39d63cdcfd306fdc5da19557cc8', c_after_preview_invoice_correction, null::text,
     array[[c_pv_vol_a, c_pv_vol_r], [c_pv_decl_a, c_pv_decl_r], [c_pv_dry_a, c_pv_dry_r], [c_pv_pay1_a, c_pv_pay1_r], [c_pv_pay2_a, c_pv_pay2_r], [c_pv_charge_a, c_pv_charge_r], [c_pv_ret_a, c_pv_ret_r]]),
    ('invoice_list_page(text,text,text,date,date,uuid,text,text,integer,integer)', 'dffff0e40dc8874759b8f0160df7f6db', c_after_invoice_list_page, null::text,
     array[[c_lp_search_a, c_lp_search_r], [c_lp_ord1_a, c_lp_ord1_r], [c_lp_ord2_a, c_lp_ord2_r], [c_lp_agg_a, c_lp_agg_r]]),
    ('apply_line_foc(uuid,integer,uuid,text)', 'eba9ffa077208c809001d30fdbaad409', c_after_apply_line_foc, null::text,
     array[[c_af_state_a, c_af_state_r], [c_foc_recalc_a, c_foc_recalc_r]]),
    ('remove_line_foc(uuid,text)', '488b7a79857426e8cbecbe9630c4f298', c_after_remove_line_foc, null::text,
     array[[c_rf_found_a, c_rf_found_r], [c_rf_state_a, c_rf_state_r], [c_foc_recalc_a, c_foc_recalc_r]]),
    ('set_invoice_affiliate(uuid,uuid)', '499606008bead7309a3fa49810f568b1', c_after_set_invoice_affiliate, null::text,
     array[[c_sa_found_a, c_sa_found_r], [c_sa_upd_a, c_sa_upd_r]]),
    ('set_invoice_fulfilment_warehouse(uuid,uuid)', '389eea0434e50337c9a90bc79937f5e2', c_after_set_invoice_fulfilment_warehouse, null::text,
     array[[c_sf_found_a, c_sf_found_r], [c_sf_clear_a, c_sf_clear_r], [c_sf_set_a, c_sf_set_r]]),
    ('confirm_foc_invoice(uuid,text)', '42a6bdb4a1a693c5c83a4fa601abc551', c_after_confirm_foc_invoice, null::text,
     array[[c_cf_a, c_cf_r]]),
    ('trg_issue_sold_vouchers_on_paid()', '6e1b4743788b0f6913205b233c1559b3', c_after_trg_issue_sold_vouchers_on_paid, c_tv_def,
     null::text[]),
    ('record_invoice_payment(uuid,jsonb,uuid)', '95a02a1685af524ecf0201b4ed7f9a67', c_after_record_invoice_payment, null::text,
     array[[c_rp_a, c_rp_r]]),
    ('invoice_record_payments_internal(uuid,jsonb)', '5c2559f7cf4dbca5dec4fdd55d00ae34', c_after_invoice_record_payments_internal, null::text,
     array[[c_ri_a, c_ri_r]]),
    ('correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)', '63efea7ed4721721b598f2e1237b8f6c', c_after_correct_invoice_payment, null::text,
     array[[c_cp_a, c_cp_r]]),
    ('split_invoice_payment(uuid,jsonb,text,uuid)', '5c13c5d9a0461097bf74dec4414aaf4c', c_after_split_invoice_payment, null::text,
     array[[c_sp_a, c_sp_r]]),
    ('set_invoice_instalment_label(uuid,uuid,integer)', 'f6b3103528e779bcb738abc122d2a2c1', c_after_set_invoice_instalment_label, c_il_def,
     null::text[])
  ) x(fn, before_md5, after_md5, whole, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '416: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '416: public.% is already this version; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '416: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    if r.edits is null then
      d := r.whole;
    else
      for k in 1 .. array_length(r.edits, 1) loop
        n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
        if n <> 1 then
          raise exception '416: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
        d := replace(d, r.edits[k][1], r.edits[k][2]);
      end loop;
    end if;
    if md5(d) <> r.after_md5 then
      raise exception '416: the new text of public.% is not the tested one (md5 %)', r.fn, md5(d); end if;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;

  -- Relied on, not changed: today in Singapore, and the two issuers the FOC
  -- path now calls, as read on 9 Oct 2026 (idempotent, no status gate; a
  -- voucher line that gave vouchers is skipped, a promotion's pick only once
  -- it gave that voucher); the voucher stock still owed, net of the
  -- invoice's movement rows; a reopened invoice's replacements, which clear
  -- what they replace; a line's charged value and promotion voucher units,
  -- for a voucher given again; the therapy rights a replacement carries
  -- from the voucher it replaces (same voucher, no more units); and
  -- deduct_invoice_stock, which takes voucher stock at the invoice's store
  -- with a movement row there (read again on 10 Oct 2026), so a save that
  -- keeps an invoice FOC can give back what it took by those rows.
  for r in select * from (values
    ('sg_today()', '1c1289f18e24d8370e9a6364c9c06fca'),
    ('deduct_invoice_stock(uuid,text)', '32183fe9e7c15ed0b11307c48289831a'),
    ('create_special_docs_for_invoice(uuid)', 'e5503f03bf5b615ec9b948fecdc52b55'),
    ('issue_sold_vouchers_for_invoice(uuid)', '0dbb4bc74411b6d4f0535f661a8c09ee'),
    ('issue_promotion_vouchers_for_invoice(uuid)', 'e47e5f623b1fa3f6eafe83086f0c9776'),
    ('snapshot_therapy_voucher_issue(uuid,boolean)', '12ba32611ad001781862d82b1ae13c8e'),
    ('invoice_stock_to_deduct(uuid)', '6356494ccb8545d46c56b788f8f85f54'),
    ('apply_reopened_invoice_vouchers()', '71d50be41b73decceb0b20f8597dd4fa'),
    ('invoice_discounted_line_value(uuid)', 'ead4a430c3abd1e3f953912867ca4fe6'),
    ('invoice_promotion_voucher_components(uuid)', '88abd9576481edb759d6e433408c6275')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '416: public.% is missing or not the version read on production (9 or 10 Oct 2026). Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;
  -- No other function shares a name with one this changes (the API picks an
  -- overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('create_invoice', 'update_invoice_internal', 'create_invoice_with_details', 'correct_invoice', 'preview_invoice_correction', 'invoice_list_page', 'apply_line_foc', 'remove_line_foc', 'set_invoice_affiliate', 'set_invoice_fulfilment_warehouse', 'confirm_foc_invoice', 'trg_issue_sold_vouchers_on_paid', 'record_invoice_payment', 'invoice_record_payments_internal', 'correct_invoice_payment', 'split_invoice_payment', 'set_invoice_instalment_label')
     and p.oid::regprocedure::text not in (
      'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
      'update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)',
      'create_invoice_with_details(uuid,uuid,jsonb,jsonb)',
      'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
      'preview_invoice_correction(uuid,jsonb)',
      'invoice_list_page(text,text,text,date,date,uuid,text,text,integer,integer)',
      'apply_line_foc(uuid,integer,uuid,text)',
      'remove_line_foc(uuid,text)',
      'set_invoice_affiliate(uuid,uuid)',
      'set_invoice_fulfilment_warehouse(uuid,uuid)',
      'confirm_foc_invoice(uuid,text)',
      'trg_issue_sold_vouchers_on_paid()',
      'record_invoice_payment(uuid,jsonb,uuid)',
      'invoice_record_payments_internal(uuid,jsonb)',
      'correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)',
      'split_invoice_payment(uuid,jsonb,text,uuid)',
      'set_invoice_instalment_label(uuid,uuid,integer)');
  if v_bad is not null then
    raise exception '416: another overload of a function this changes exists: %', v_bad; end if;
  -- The trigger that calls trg_issue_sold_vouchers_on_paid is the one read on 9 Oct 2026.
  if (select pg_get_triggerdef(t.oid) from pg_trigger t
       where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'issue_sold_vouchers_on_paid' and t.tgenabled = 'O')
     is distinct from 'CREATE TRIGGER issue_sold_vouchers_on_paid AFTER UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_issue_sold_vouchers_on_paid()' then
    raise exception '416: the trigger issue_sold_vouchers_on_paid on public.invoices is not the one read on 9 Oct 2026'; end if;
  -- A reopened invoice's replacements are made by this trigger, which runs
  -- before issue_sold_vouchers_on_paid (triggers run in name order), so a
  -- voucher it replaces is not given again there.
  if (select pg_get_triggerdef(t.oid) from pg_trigger t
       where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'invoice_reopen_vouchers_settled' and t.tgenabled = 'O')
     is distinct from 'CREATE TRIGGER invoice_reopen_vouchers_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_vouchers()' then
    raise exception '416: the trigger invoice_reopen_vouchers_settled on public.invoices is not the one read on 9 Oct 2026'; end if;
  -- The statuses this names are the nine read on 9 Oct 2026.
  if (select string_agg(e.enumlabel::text, ',' order by e.enumlabel::text) from pg_enum e
       where e.enumtypid = 'public.invoice_status'::regtype)
     is distinct from 'cancellation_requested,cancelled,completed_foc,draft,paid,partially_paid,refund_requested,refunded,unpaid' then
    raise exception '416: the invoice statuses are not the nine read on 9 Oct 2026'; end if;
  -- The two columns and the index: both missing, or exactly as this makes them.
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
                    || case when a.attnotnull then ' not null' else '' end
                    || coalesce(' default ' || pg_get_expr(df.adbin, df.adrelid), ''), '|' order by a.attname) into v
    from pg_attribute a left join pg_attrdef df on df.adrelid = a.attrelid and df.adnum = a.attnum
   where a.attrelid = 'public.invoices'::regclass and a.attnum > 0 and not a.attisdropped
     and a.attname in ('create_request_id', 'create_request_hash');
  if v is not null and v <> c_cols then
    raise exception '416: public.invoices has create_request_id or create_request_hash, not as this makes them (%)', v; end if;
  if to_regclass('public.invoices_create_request_id_key') is not null
     and (v is null or pg_get_indexdef(to_regclass('public.invoices_create_request_id_key')) <> c_index) then
    raise exception '416: an index invoices_create_request_id_key exists and is not this migration''s'; end if;
  -- The grants of the functions changed, to compare after.
  select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
    into v_acl
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.oid::regprocedure::text in (
      'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
      'update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)',
      'create_invoice_with_details(uuid,uuid,jsonb,jsonb)',
      'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
      'preview_invoice_correction(uuid,jsonb)',
      'invoice_list_page(text,text,text,date,date,uuid,text,text,integer,integer)',
      'apply_line_foc(uuid,integer,uuid,text)',
      'remove_line_foc(uuid,text)',
      'set_invoice_affiliate(uuid,uuid)',
      'set_invoice_fulfilment_warehouse(uuid,uuid)',
      'confirm_foc_invoice(uuid,text)',
      'trg_issue_sold_vouchers_on_paid()',
      'record_invoice_payment(uuid,jsonb,uuid)',
      'invoice_record_payments_internal(uuid,jsonb)',
      'correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)',
      'split_invoice_payment(uuid,jsonb,text,uuid)',
      'set_invoice_instalment_label(uuid,uuid,integer)');

  -- ── Change ───────────────────────────────────────────────────────────────
  alter table public.invoices
    add column if not exists create_request_id uuid,
    add column if not exists create_request_hash text;
  comment on column public.invoices.create_request_id is
    '416: the New Invoice form''s request id. The same request again returns this invoice (create_invoice_with_details).';
  comment on column public.invoices.create_request_hash is
    '416: md5 of what that request asked for; the same id with other contents is refused.';
  create unique index if not exists invoices_create_request_id_key
    on public.invoices (create_request_id) where create_request_id is not null;

  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
  end loop;

  -- ── Installed exactly as tested ─────────────────────────────────────────
  for r in select * from (values
    ('create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)', c_after_create_invoice),
    ('update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)', c_after_update_invoice_internal),
    ('create_invoice_with_details(uuid,uuid,jsonb,jsonb)', c_after_create_invoice_with_details),
    ('correct_invoice(uuid,jsonb,jsonb,text,uuid)', c_after_correct_invoice),
    ('preview_invoice_correction(uuid,jsonb)', c_after_preview_invoice_correction),
    ('invoice_list_page(text,text,text,date,date,uuid,text,text,integer,integer)', c_after_invoice_list_page),
    ('apply_line_foc(uuid,integer,uuid,text)', c_after_apply_line_foc),
    ('remove_line_foc(uuid,text)', c_after_remove_line_foc),
    ('set_invoice_affiliate(uuid,uuid)', c_after_set_invoice_affiliate),
    ('set_invoice_fulfilment_warehouse(uuid,uuid)', c_after_set_invoice_fulfilment_warehouse),
    ('confirm_foc_invoice(uuid,text)', c_after_confirm_foc_invoice),
    ('trg_issue_sold_vouchers_on_paid()', c_after_trg_issue_sold_vouchers_on_paid),
    ('record_invoice_payment(uuid,jsonb,uuid)', c_after_record_invoice_payment),
    ('invoice_record_payments_internal(uuid,jsonb)', c_after_invoice_record_payments_internal),
    ('correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)', c_after_correct_invoice_payment),
    ('split_invoice_payment(uuid,jsonb,text,uuid)', c_after_split_invoice_payment),
    ('set_invoice_instalment_label(uuid,uuid,integer)', c_after_set_invoice_instalment_label)
  ) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '416: installed with md5s other than the tested ones: %', v_bad; end if;
  if (select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
        from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.oid::regprocedure::text in (
          'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
      'update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)',
      'create_invoice_with_details(uuid,uuid,jsonb,jsonb)',
      'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
      'preview_invoice_correction(uuid,jsonb)',
      'invoice_list_page(text,text,text,date,date,uuid,text,text,integer,integer)',
      'apply_line_foc(uuid,integer,uuid,text)',
      'remove_line_foc(uuid,text)',
      'set_invoice_affiliate(uuid,uuid)',
      'set_invoice_fulfilment_warehouse(uuid,uuid)',
      'confirm_foc_invoice(uuid,text)',
      'trg_issue_sold_vouchers_on_paid()',
      'record_invoice_payment(uuid,jsonb,uuid)',
      'invoice_record_payments_internal(uuid,jsonb)',
      'correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)',
      'split_invoice_payment(uuid,jsonb,text,uuid)',
      'set_invoice_instalment_label(uuid,uuid,integer)'))
     is distinct from v_acl then
    raise exception '416: the grants of the changed functions changed'; end if;
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
                    || case when a.attnotnull then ' not null' else '' end
                    || coalesce(' default ' || pg_get_expr(df.adbin, df.adrelid), ''), '|' order by a.attname) into v
    from pg_attribute a left join pg_attrdef df on df.adrelid = a.attrelid and df.adnum = a.attnum
   where a.attrelid = 'public.invoices'::regclass and a.attnum > 0 and not a.attisdropped
     and a.attname in ('create_request_id', 'create_request_hash');
  if v is distinct from c_cols or pg_get_indexdef(to_regclass('public.invoices_create_request_id_key')) is distinct from c_index then
    raise exception '416: the request columns or their index are not as tested'; end if;

  -- ── Behaviour, inside a block that is always undone ──────────────────────
  -- A made-up Owner, store, customer (a number from a range kept for
  -- fiction) and payment method, and an undated invoice made at 01:30 on
  -- 1 Jan 1999 in Singapore (still 31 Dec 1998 in UTC). Nothing is printed.
  begin
    insert into auth.users (id, email)
    values (gen_random_uuid(), '416-check-owner-' || gen_random_uuid() || '@sig.invalid') returning id into v_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '416 check', u.email, 'owner'::public.user_role, true from auth.users u where u.id = v_owner;
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    insert into public.stores (name, code, country_code)
    values ('416 check', '416-' || left(gen_random_uuid()::text, 8), 'SG') returning id into v_store;
    insert into public.customers (full_name, phone) values ('416 check', '+61491570156') returning id into v_cust;
    insert into public.payment_methods (name, is_active) values ('416 check cash', true) returning id into v_pm;
    insert into public.invoices (invoice_no, store_id, customer_id, created_by, status, subtotal, discount_total,
                                 manual_discount, total_amount, paid_amount, created_at, business_date)
    values ('416-CHECK-' || left(gen_random_uuid()::text, 8), v_store, v_cust, v_owner, 'unpaid', 100, 0,
            0, 100, 0, timestamptz '1999-01-01 01:30:00+08', null)
    returning id into v_inv;

    -- Rule 4: a third decimal place is refused by both payment functions.
    foreach v in array array['internal', 'record'] loop
      v_err := null;
      begin
        if v = 'internal' then
          perform public.invoice_record_payments_internal(v_inv,
            jsonb_build_array(jsonb_build_object('payment_method_id', v_pm, 'amount', 99.995)));
        else
          perform public.record_invoice_payment(v_inv,
            jsonb_build_array(jsonb_build_object('payment_method_id', v_pm, 'amount', 99.995)), gen_random_uuid());
        end if;
      exception when others then v_err := sqlerrm;
      end;
      if v_err is distinct from 'Payment amounts can have at most 2 decimal places.' then
        raise exception '416: a payment of 99.995 was not refused as it should be (%: %)', v, v_err; end if;
    end loop;

    -- Rule 10: no terms without a receipt.
    v_err := null;
    begin
      perform public.set_invoice_instalment_label(v_inv, v_pm, 6);
    exception when others then v_err := sqlerrm;
    end;
    if v_err is distinct from 'Record a payment first. Instalment terms are set with the payment they belong to.' then
      raise exception '416: instalment terms without a receipt were not refused (%)', v_err; end if;

    -- Rule 3: a new invoice dated tomorrow.
    v_err := null;
    begin
      perform public.create_invoice_with_details(v_store, v_cust, '[]'::jsonb,
        jsonb_build_object('business_date', (public.sg_today() + 1)::text));
    exception when others then v_err := sqlerrm;
    end;
    if v_err is distinct from 'The invoice date cannot be after today.' then
      raise exception '416: an invoice dated tomorrow was not refused (%)', v_err; end if;

    -- Rule 12: the list finds the undated invoice by its Singapore day.
    foreach v in array array['01/01/1999', '1999-01-01', '1 Jan 1999', '1 Jan', 'Jan 1999'] loop
      v_res := public.invoice_list_page(v, null, 'all', null, null, v_store, 'created_at', 'desc', 25, 0);
      if (v_res->>'total')::int <> 1 or v_res->'rows'->0->>'id' <> v_inv::text then
        raise exception '416: the list did not find the invoice by "%"', v; end if;
    end loop;
    -- A month name alone is a name search, not a date.
    v_res := public.invoice_list_page('Jan', null, 'all', null, null, v_store, 'created_at', 'desc', 25, 0);
    if (v_res->>'total')::int <> 0 then
      raise exception '416: the list found an invoice by "Jan" alone, as a date'; end if;

    -- Rule 4: a payment corrected to tomorrow.
    insert into public.invoice_payments (invoice_id, payment_method_id, amount, received_by)
    values (v_inv, v_pm, 50, v_owner) returning id into v_pay;
    v_err := null;
    begin
      perform public.correct_invoice_payment(v_pay, 50, public.sg_today() + 1, v_pm, '416 check', gen_random_uuid());
    exception when others then v_err := sqlerrm;
    end;
    if v_err is distinct from 'A payment cannot be dated in the future' then
      raise exception '416: a payment corrected to tomorrow was not refused (%)', v_err; end if;

    -- Rule 9: a deleted invoice is not found by Fulfil from warehouse.
    update public.invoices set deleted_at = now() where id = v_inv;
    v_err := null;
    begin
      perform public.set_invoice_fulfilment_warehouse(v_inv, null);
    exception when others then v_err := sqlerrm;
    end;
    if v_err is distinct from 'Invoice not found' then
      raise exception '416: Fulfil from warehouse found a deleted invoice (%)', v_err; end if;

    raise exception using errcode = 'P4160', message = '416: check done, undone';
  exception when sqlstate 'P4160' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
