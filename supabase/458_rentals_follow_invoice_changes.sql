-- 458_rentals_follow_invoice_changes.sql
--
-- RENTALS FOLLOW THEIR INVOICE'S EDIT, CANCEL AND REFUND (the Owner, 22 Oct
-- 2026, item 1)
--
-- WHAT WAS WRONG / WHY
--
--   Cancel already ended a rental (cancel_invoice_rentals, 300): one waiting
--   for a warehouse was cancelled, one out with the customer became
--   "cancelled, still with customer" and was received back with 417's step.
--   Nothing else followed the invoice:
--   * Refund. refund_invoice_recorded hands rentals to 393's
--     settle_waiting_special_docs_on_refund, which only touches rentals still
--     waiting. A full refund of the invoice, or of the rental line, left a
--     rental that was out 'active': still counted as out on the Dashboard,
--     still offered Return on the Special page, which charged a late fee
--     (S$45 in a probe on a refunded invoice), and nothing to receive
--     (invoice_rentals_awaiting_return was empty), so the refund's receive
--     step showed nothing. A refund of 1 of 2 machines could only keep both
--     or cancel both.
--   * Edit. correct_invoice rewrote the rental line in place
--     (update_invoice_internal) and never touched the rental: a waiting
--     rental kept its old machine, quantity, periods, fee and due date (and
--     could be released on them), and stayed with the old customer and store
--     after the invoice moved. While a rental was out, every change to the
--     lines, the customer or the store was refused ("Return or resolve the
--     outstanding rental before changing its invoice allocation"), even an
--     extension or a strap added on another line, and update_pending_rental
--     refuses rentals that are out: a running rental could be extended
--     nowhere.
--   * Reopen. A rental cancelled with its invoice while out stayed
--     cancelled when the invoice was reopened; one received back by then got
--     no new rental (create_special_docs_for_invoice counted any rental ever
--     released as the line's for good); a reopened FOC invoice raised none
--     (reopen_invoice raised items only when it reopened as paid).
--   * "Due back" left blank on the invoice (the page allows it) was saved as
--     today + the periods counted as DAYS, whatever the rate type and the
--     start: a 2-month rental starting 25 Oct was due back 24 Oct. Late fees
--     count from that date.
--
-- THE RULES (binding; the Owner's answers, 22 Oct 2026, the recommended answer
-- to every question)
--
--   1. A full refund of the invoice, or of the rental line, while the machine
--      is still with the customer ENDS the rental like Cancel: it stops
--      running (no late fee), shows 'still with customer' and is received
--      back (or recorded damaged/lost) with the receive step Cancel already
--      uses (receive_returned_rental / invoice_rentals_awaiting_return), and
--      the refund's done screen offers it.
--   2. A partial refund of some units of a multi-machine rental: still
--      waiting for a warehouse: lower the rental's quantity and fee to what
--      the customer keeps; already out: keep it running for what is kept, and
--      the refunded units are to be received back as above.
--   3. Editing a paid invoice's rental line (machine, quantity, rate,
--      periods, start, Due back) while the rental still waits for a
--      warehouse: the rental follows the line, including the invoice's
--      customer and store; the correction summary says so before saving.
--   4. While the rental is out, Edit Invoice may change its rate, periods and
--      Due back (an extension or a shortening, the difference on the invoice)
--      plus any other line; a change of machine or quantity of a rental that
--      is out is refused with a plain message ('RNT-... is out with the
--      customer: Return it first'). The blanket guard that refuses every
--      change while any rental is out goes; only changes to the out rental's
--      machine/quantity are refused.
--   5. A correction that moves the invoice to another customer or store moves
--      a WAITING rental with it; it is refused while a rental is out.
--   6. Reopening a cancelled invoice whose rental was cancelled while out:
--      not back yet -> it runs again with the same due date; already received
--      back -> a new rental waits for a warehouse. A reopened FOC invoice
--      raises its rentals too.
--   7. 'Due back' left blank: compute it from the start date + periods by the
--      rate type (426's update_pending_rental math), not today + periods in
--      days. Existing wrong ones: a read-only list first, no repair here.
--   How it reads (this file, 24 Oct 2026):
--   * "Waiting" is 393's: awaiting_fulfilment, released from no warehouse or
--     store. "Out" is rental_is_outstanding (paid, active, overdue). A rental
--     returned, or cancelled (ended), is left as it is by a correction.
--   * A refund's units are read from the money: the whole units of the
--     line's value (invoice_discounted_line_value, as 393 reads it) that the
--     money refunded on the line since it was last reopened covers (this
--     refund included; within a cent of the whole value is every unit). A
--     guided refund of 1 of 2 machines refunds half the line's value, so it
--     is one unit; an amount short of one unit ends and lowers nothing.
--   * The units refunded come off what the line's rentals still hold (out,
--     or waiting), counted across them: a waiting one first (no machine to
--     bring back), then one out, then a waiting one staff answered "still
--     taking". Units refunded off a rental that is out become a rental
--     number of their own (split off: same machine, released from the same
--     place, ended at once), received back like any other; the rental keeps
--     running for the rest with its fee lowered in proportion.
--   * A waiting rental the customer still takes (393's answer "still taking",
--     or no answer) is lowered to the units not refunded (cancelled as 393
--     does when none are left); one answered "not taking", or whose line went
--     back whole with no answer, is cancelled as 393 does; one answered
--     "still taking" whose line went back whole stays as it is (393).
--   * The rental follows a corrected line only when this correction changed
--     the line (its machine, quantity, rate type, periods, start, Due back or
--     value); one whose terms were changed on the Special page keeps them
--     until its line is corrected. A waiting rental then holds the line's
--     machines less those that are not its own: on the line's other rentals
--     that still count, and those a refund took off a waiting rental since
--     the invoice was last reopened (so a machine refunded, or one on
--     another rental, is never put back on it); none left is refused in
--     words. Its fee and rate are its share of the line as the invoice raises
--     them (create_special_docs_for_invoice: the line's value before its
--     discount, over the periods), so 426's "fee as sold" reads the line. A
--     waiting rental also follows the invoice's customer and store whenever
--     they differ. Out: its rate, periods, Due back, fee and rate follow; its
--     machine, quantity, start, customer and store stay.
--   * A rental waits for its invoice to be paid in full before it is
--     released (393: items wait for the payment). An invoice raises its
--     rentals only once paid, so this holds a rental a correction left
--     owing: one that followed its line to more machines, longer or another
--     machine, or one beside a line added unpaid. The correction summary
--     says "released once the invoice is paid in full".
--   * "Due back" blank: the start (the line's, else the rental's; for a
--     rental out, its own) plus the periods by rate type; never before the
--     start (refused in words).
--   * Running again on reopening (rule 6) happens when the reopened invoice
--     is settled: at once when it reopens paid or completed FOC, otherwise
--     at the payment that settles it (the same step raises waiting items
--     again, 393). No stock moves: the unit never came back.
--
-- WHAT THIS DOES (four functions added, the service role's alone; six
-- patched at anchors, their grants kept; no table, column, row or other
-- function changes)
--
--   1. invoice_rental_correction_check(uuid,jsonb,uuid,uuid) (new): the
--      rule 4 and 5 refusals, for each rental out: the invoice to another
--      customer or store, its line removed, its machine or quantity changed
--      ("RNT-... is out with the customer: Return it first. ..."). A rental
--      out that names no line keeps the old refusal word for word.
--   2. invoice_rentals_follow_lines(uuid,jsonb,text) (new): rules 3, 4, 5
--      and 7 for a correction: each waiting or out rental on a line this
--      correction changed, or a waiting one whose customer or store is not
--      the invoice's, follows as above (a waiting one: the line's machines
--      less those not its own); an audit row each
--      ('rental_follows_invoice_line', before and after) and a note; answers
--      [{rental_id, rental_no, state, what}], "what" in words for the page
--      (with "released once the invoice is paid in full" while it owes).
--   3. rental_end_on_refund(uuid,integer,text) (new): ends a rental out with
--      the customer, whole or for some of its units (the split), as Cancel
--      does, with the note "Refunded while still out; awaiting physical
--      return: ..." and the audit row 'rental_refunded_awaiting_return'
--      ('rental_part_refunded' on the one that keeps running). No stock.
--   4. rentals_follow_refund(uuid,jsonb,text) (new): rules 1 and 2 for a
--      recorded refund: a refund that leaves the invoice refunded (or
--      cancelled) ends every rental out; otherwise, per rental line it names,
--      the units its rentals hold (out and waiting) beyond what is kept come
--      off: waiting ones lowered ('rental_part_refunded_waiting') or
--      cancelled, then out ones ended (rental_end_on_refund).
--   5. correct_invoice(uuid,jsonb,jsonb,text,uuid) (457's text), five
--      anchors: a variable; the blanket guard becomes item 1 (still asked
--      only when the lines, customer or store change); item 2 runs once the
--      corrected lines and header are saved, before the correction summary
--      stops (so the summary says what it does), its list in the summary's
--      detail and in the answer ('rentals').
--   6. preview_invoice_correction(uuid,jsonb): the summary lists those
--      rentals (an effect 'rentals', each in words). One anchor.
--   7. settle_waiting_special_docs_on_refund(uuid,jsonb,text) (393's, which
--      refund_invoice_recorded calls after it sets the status): item 4 after
--      393's own steps, on both paths (the invoice closed, or by line). Two
--      anchors. refund_invoice_recorded itself is not changed.
--   8. create_special_docs_for_invoice(uuid): rule 6: on a rental line, a
--      rental ended while out before the last reopening and not back yet
--      runs again ('active', cancelled_at cleared, its due date kept, a note
--      and the audit row 'rental_running_again'); one received back (stock
--      returned) before the last reopening no longer counts, so its units
--      get a new waiting rental (all the line's when nothing else counts, or
--      the units missing beside rentals that still count, at their share of
--      the line's value); rule 7: "Due back" blank is the start plus the
--      periods by rate type. Three anchors.
--   9. reopen_invoice(uuid,text,uuid) (451's text): raises the items when it
--      reopens as paid OR completed FOC (rule 6; so a reopened FOC invoice's
--      special products too, as Confirm FOC raises both). One anchor.
--  10. fulfil_special_doc(text,uuid,uuid,text) (393's text): a rental whose
--      invoice is unpaid or part-paid with money owing is not released
--      ("RNT-... cannot be released yet: its invoice INV-... has S$...
--      owing. Take the payment first, then release it."), after 393's own
--      refusal and before any stock moves. Special sales are not touched.
--      Two anchors.
--   The pages (not this file): the guided refund's done screen offers the
--   receive step for rentals the refund ended and says so in its review;
--   the invoice's finance section lists rentals still with the customer
--   after a refund too; the correction summary lists the rentals that
--   follow and the save says what changed; "Due back" follows the start,
--   rate and periods on the invoice form; the Special page reads "Refunded,
--   still with customer".
--
-- NOT CHANGED
--
--   cancel_invoice_rentals (Cancel ends rentals exactly as before),
--   cancel_invoice_recorded, rental_awaiting_return,
--   invoice_rentals_awaiting_return, receive_returned_rental (they already
--   take any rental cancelled while out, so a refunded one too),
--   rental_put_back_stock, return_rental_with_fee (it refuses a cancelled
--   rental, so an ended one is never Returned with a late fee),
--   update_pending_rental (the Special page's "Change rental terms" for a
--   waiting rental), cancel_waiting_special_docs and the line-removed trigger
--   (393), refund_invoice_recorded (446/451's; another session's), the
--   guided actions (request/resolve_invoice_action_v2) and invoice_action_plan
--   (448's: its plan, effects and plan_hash are unchanged, so no pending
--   request is invalidated), cancelled_invoice_used_value, update_invoice_
--   internal (457's), special_doc_invoice_problem and the waiting list
--   (special_docs_awaiting_fulfilment: a rental held for the payment is still
--   listed; Release says why), special sales (special products): their
--   waiting items keep 393's rules, invoice_transferable_benefits and
--   move_invoice_benefits_to_customer (not pinned), every table, column,
--   policy and grant. Money: the rental fee is charged on the invoice, so
--   nothing here moves money; an extension's difference is owing on the
--   invoice like any raised line. Stock: only Receive and Return move it.
--   Commission: reconcile_invoice_commissions runs as before.
--
-- NOT COVERED (to tell the Owner)
--
--   1. Special products sold on a line (special_sales) keep 393's rules: a
--      corrected line's waiting item keeps its old machine and quantity; only
--      rentals follow (the Owner's item was rentals).
--   2. A rental out keeps the start it went out with; a changed start on its
--      line is not copied (only its rate, periods and Due back follow).
--   3. A refund's units are read from the money refunded on the line. A
--      goodwill amount that comes to a whole unit's value on a several-
--      machine line ends that unit; one short of a unit ends nothing. The
--      guided refund's review (invoice_action_plan, unchanged) does not list
--      rental effects; the page says in words what a refund does to a rental
--      out, and its done screen lists what to receive. A line partly
--      refunded and then corrected to other terms is read against its new
--      value, so a later refund on it may end fewer machines than it names;
--      the done screen and the Special page show what is still out.
--  3a. A rental line partly refunded and then corrected (say extended): the
--      invoice still charges the line's whole quantity at the new terms less
--      the money refunded (the invoice's money rules, not changed here), so
--      the extension is charged for the refunded machine too, while the
--      rental takes only the machines kept. Lowering that line to the
--      machines kept is refused while its rental waits ("... are refunded or
--      on other rentals ..."): the refund took them off already. Put such a
--      difference right with a line discount until the Owner decides.
--   4. The guided refund's question "Is the customer still taking this
--      item?" for a waiting rental: Yes keeps the units not refunded waiting,
--      No cancels the whole rental (393's answer, unchanged).
--   5. A rental already ended and still with the customer (cancelled,
--      awaiting return) stays with its customer and store when the invoice
--      is moved; only a rental out (running) refuses the move. A returned or
--      cancelled rental is not changed by a correction of its line.
--   6. Reopened to unpaid or part-paid: a rental cancelled while out reads
--      "still with customer" until the payment that settles the invoice, then
--      runs again (or, received back meanwhile, a new rental waits). An item
--      received as lost also gets a new waiting rental (its record is
--      closed); cancel that one on the Special page if no machine goes out.
--   7. A guided Cancel that records its refund in the same step ends the
--      rental at the refund, so its note and audit row say refunded; the
--      rental ends the same way (still with customer, received the same).
--   8. Existing records are not repaired (rule 7 and the read-only lists in
--      the report): rentals left 'active' on invoices refunded before this
--      file, or whose line was refunded in full (Return still offers a late
--      fee on them); waiting rentals whose terms, customer or store differ
--      from their line and invoice; rentals still 'cancelled, still with
--      customer' on an invoice reopened and settled before this file (they
--      stay so: nothing settles a paid invoice again); and "Due back" dates
--      saved as today + periods in days.
--   9. Return's late fee counts from the rental's Due back; an extension or a
--      shortening by Edit Invoice moves it.
--  10. A rental out is extended or shortened through its invoice line (Edit /
--      Correct Invoice); the Special page's "Change rental terms"
--      (update_pending_rental) still takes waiting rentals only.
--  11. Release waits for the whole invoice, not for the rental's part of it:
--      a waiting rental beside a line added unpaid (a strap) is held too
--      until the invoice is paid in full, and so is one on an invoice a
--      correction before this file left owing (the read-only list in the
--      report). The waiting list still shows them; Release says why. If the
--      Owner wants only the extra machines held, that is a later file.
--  12. A line with two waiting rentals (rare: a machine raised again beside
--      one waiting) changes the first of them when its quantity changes; a
--      correction that would leave one of them none is refused in words.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (451-455, 460 and 461 in: 037095a507480dafd8381a6d3d8add90,
--   1374 functions) -> 456 -> 457 -> 458 (this file).
--   * 457 must be in first: this file's BEFORE for correct_invoice is 457's
--     AFTER (45e7f523...). 456 and 457 pin preview_invoice_correction
--     (2bb7c0a5...) as relied on and their suites pin correct_invoice's
--     AFTER: run after this file, 456 and 457 refuse (as they should: they
--     are in already), and their suites (print-note-456.sql,
--     foc-correct-again-457.sql) take this file's AFTERs too.
--   * Shared with another session's 460 and 461. They went live first (24 Oct
--     2026: 20261024003624 and 20261024003655) and changed no function this
--     file changes or pins: reopen_invoice is still cb647331..., correct_
--     invoice, refund_invoice_recorded and fulfil_special_doc as below; 460
--     changed apply_reopened_invoice_benefits / _vouchers, invoice_reopen_
--     preview, move_invoice_benefits_to_customer and invoice_transferable_
--     benefits (none pinned here). Nothing was re-pinned. 460's install
--     checks that only apply_reopened_invoice_benefits, correct_invoice_
--     payment, refund_invoice_recorded and refund_special_credit raise a
--     credit lot's balance; this file adds none and changes none of them
--     (460 installed cleanly on a copy with this file in first). What was
--     planned for either order:
--     - reopen_invoice (451's cb647331...): 460 may change it. This file
--       changes one line of it (where it raises the items, not the
--       benefits). If 460 goes first and changes it, this file refuses,
--       naming it, and changes nothing: re-read reopen_invoice after 460,
--       re-check the anchor, re-pin the BEFORE (460's AFTER) and the AFTER
--       here and in the suite, and re-test. If this file goes first, 460
--       must take this file's AFTER as its BEFORE.
--     - correct_invoice (457's): 460 may change its transfer path. This file
--       changes five other places (the declare section, the outstanding-
--       rental guard, before the 416 preview stop, the preview's detail and
--       the answer; not the transfer path). The same re-pin, either order.
--     - fulfil_special_doc (393's 76f9495c...): not known to be changed by
--       460 or 461; the same re-pin if any file changes it first.
--     - 461 (invoice_transferable_benefits, maybe move_invoice_benefits_to_
--       customer): neither changed nor pinned here: either order.
--     - apply_reopened_invoice_benefits / apply_reopened_invoice_vouchers:
--       not pinned.
--     The same holds for any other file that changes a function this file
--     changes or pins (refund_invoice_recorded among them: this file relies
--     on it calling settle_waiting_special_docs_on_refund after it sets the
--     status).
--   1. Dry run on a copy of production as it is then (456 and 457 in): apply
--      this file twice; the first run ends at the fingerprint below, the
--      second changes nothing ("already this version; left alone" ten
--      times).
--   2. Apply (the CLI, or the MCP's apply_migration with this text verbatim).
--      It checks itself.
--   3. Then deploy the pages. An open page from before 458 keeps working: the
--      server is what follows; it only does not show the rental list in the
--      summary or the refund's receive step for refunds (the finance section
--      did not list them after a refund). Release on the Special page shows
--      the server's words when a rental waits for its payment.
--   4. Then run the read-only lists in the report on production and bring
--      them to the Owner (no repair without a go-ahead).
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the functions it relies on are as read on production with 456 and 457
--     in (24 Oct 2026, on a copy of it); the rentals, invoice_items,
--     invoices, invoice_refunds and audit_logs columns it reads and writes
--     are there with these types; the rental number sequence is there;
--   * each new function's text is the tested one (its AFTER md5); it is
--     absent (created) or this version (left alone);
--   * each patched function is its BEFORE (patched; each anchor found once;
--     the text built has the tested AFTER md5) or its AFTER (left alone), so
--     a second run changes nothing; no other function takes the ten names;
--   * afterwards: the ten md5s are the AFTER ones; the six patched keep
--     their grants (compared as sets: production lists them in another order
--     than a local copy); correct_invoice, preview_invoice_correction,
--     reopen_invoice and fulfil_special_doc stay callable by signed-in staff
--     (never anon) and keep their access checks first; the four new ones and
--     the two patched internals are the service role's alone;
--   * then a self-test, in a block that is always undone (it ends by raising
--     P0458, so it leaves no row): a made-up Owner, two stores, a warehouse,
--     two customers (fictional ACMA phones no customer has) and a rental
--     machine (S$30 a day, S$500 a month). A paid two-day rental waiting
--     is corrected to 2 machines x 3 days at the other store for the other
--     customer: the rental follows (2 x 3, S$180, due back start + 3,
--     the new customer and store). Owing the S$120 difference it is not
--     released ("... cannot be released yet: ... S$120.00 owing ...");
--     paid, it is released from the warehouse, extended to 5 days (due back
--     moves, S$300) and a change to 3 machines is refused ("... is out with
--     the customer: Return it first. ...").
--     Paid up and its line refunded in full, it ends: cancelled, still with
--     the customer, listed to receive, no stock moved. A one-month rental
--     from 31 Jan with Due back blank is due back 28 Feb (not 1 Feb).
--   It reads only, apart from the ten functions and the self-test's rows
--   (undone). Locks: the ten functions' catalogue rows, to the end of the
--   apply, and the self-test's own rows. A correction, refund or reopening
--   running at that moment finishes on the text it started with.
--
-- BEFORE (production now with 456 and 457 in, read on a copy of it, 24 Oct
-- 2026; md5 of pg_get_functiondef with search_path public)
--   changed
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                    45e7f523e50a6b423b6e1d9f8836ebb6  (457's AFTER)
--   preview_invoice_correction(uuid,jsonb)                         2bb7c0a5769050d5b2f9247a3aa05ecd  (as at 434; 456/457 pin it)
--   settle_waiting_special_docs_on_refund(uuid,jsonb,text)         307f671efc73adf5ebf8fedd9c880812  (393's)
--   create_special_docs_for_invoice(uuid)                          e5503f03bf5b615ec9b948fecdc52b55  (426's)
--   reopen_invoice(uuid,text,uuid)                                 cb647331300b0a476c1da7b2cb599889  (451's)
--   fulfil_special_doc(text,uuid,uuid,text)                        76f9495c44e017beb5275ed8a8112fda  (393's)
--   invoice_rental_correction_check(uuid,jsonb,uuid,uuid)          (not there)
--   invoice_rentals_follow_lines(uuid,jsonb,text)                  (not there)
--   rental_end_on_refund(uuid,integer,text)                        (not there)
--   rentals_follow_refund(uuid,jsonb,text)                         (not there)
--   relied on, not changed
--   cancel_invoice_rentals(uuid,text)                              15aef6f8c9ef2022810f2181f512b150  (300's: Cancel ends rentals)
--   rental_awaiting_return(uuid)                                   88ba77463d293bc77fba5e5cad3d3210  (still with customer)
--   rental_is_outstanding(text)                                    076549a44bc057cd529aac5542c4d06e  (out)
--   rental_is_unfulfilled(text)                                    2cff280461925fefc88dcc9776f3bfd1
--   invoice_rentals_awaiting_return(uuid)                          07621bd5ba0b8be5cf69460ac4212017  (the receive list)
--   receive_returned_rental(uuid,uuid,text,text,uuid)              362b0175b60e12c97e427b5180e01960  (the receive step)
--   rental_put_back_stock(uuid)                                    8ca55272c76c62b295d5001b0943e85a
--   return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text)  659a74da796b7360a3730347730e0d65  (refuses an ended rental)
--   trg_rental_stock_back()                                        a75c600cd86edc5b43fb464a5bfe34a8
--   update_pending_rental(uuid,integer,special_rate_type,integer,date,date,text)  1022ecdafb4e1e2f21e7dc051376b028  (426's due-date math and fee as sold)
--   cancel_waiting_special_docs(uuid,text,text,uuid,uuid[])        fe4753fffded2cc463dbe24571a9675c  (393's)
--   trg_special_docs_follow_line_removed()                         25b2fac3612be3ab56151f3e109c3574  (393's)
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)      804ecd829cfecf713783a09a05d93c7e  (446/451's: calls settle_waiting_special_docs_on_refund last)
--   cancel_invoice_recorded(uuid,text,uuid)                        de52d9dbaef8ab15163bef35cb9d733d
--   invoice_discounted_line_value(uuid)                            ead4a430c3abd1e3f953912867ca4fe6  (a line's value, as 393 reads it)
--   invoice_charge_total(uuid)                                     8297147511ba285db2279598f3d727fb  (what the invoice charges, less its line refunds)
--   invoice_net_received(uuid)                                     f256bea69b7defa38a950753bbc248da  (the money it holds)
--   invoice_action_plan(uuid,text,jsonb)                           383d618edb28c3c9a360242d038a022c  (448's: a line's refund amount by quantity)
--   resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)  201f08ebf14a64cd88d411a7cfb4c9c4  (the guided refund and cancel)
--   update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)  1f034561a461bdb46a1e6274e0d04606  (457's AFTER: the rental line kept by id)
--   invoice_line_matches(uuid,jsonb)                               0c32f7c591efb9864ff5b1cb2201b744  (compares a rental line's terms)
--   invoice_record_payments_internal(uuid,jsonb)                   21890d84bcb0b9c00a2bc98aff313d0b  (the payment that settles raises the items)
--   confirm_foc_invoice(uuid,text)                                 ba8b1ce2a5671989b927891f0cb7b1a2  (raises the items)
--   special_doc_invoice_problem(uuid,uuid)                         be2b8ec5a4003a1dca34e17a82f89932  (release refuses an item its invoice no longer sells (393))
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)  c705c733e213a27f0dc32d54322cc855
--   sg_today()                                                     1c1289f18e24d8370e9a6364c9c06fca
--   user_has_store_access(uuid)                                    708992afaa6c3951f6329239b742987c
--   is_owner_or_manager()                                          a98e50f1b6d3fa1e6c62cf52a8073cc8
--   normalize_customer_phone(text)                                 b2bfac910e0c9eff402ba44e19750bee  (the self-test)
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)   80c80d386a5241e63b353e35e13ef250  (the self-test)
--   pay_invoice(uuid,jsonb)                                        19baf63628acbce946961f4031e3da73  (the self-test)
--   upsert_special_product_from_product(uuid,uuid,numeric,numeric,numeric,numeric,numeric,numeric,text,boolean)  312e25496c17975e56065e968a9b6c59  (the self-test)
--   public function fingerprint, 451-455 in (before 460 and 461)   b43a0781217fd1b4027749deafbddca7 (1372 functions)
--   public function fingerprint, production now (460 and 461 in)   037095a507480dafd8381a6d3d8add90 (1374 functions)
--   public function fingerprint, production now -> 456 -> 457      11840d5ac3aa7f5fc4a26020a7b2d0ce (1374 functions)
-- AFTER (for later guards: 460, 461 and any later file)
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                    af9451fa15c2cf790edd70f799bae336
--   preview_invoice_correction(uuid,jsonb)                         3047239c7418179e84927f6f00e7f2eb
--   settle_waiting_special_docs_on_refund(uuid,jsonb,text)         edfd1f1beb7ab3b6739096a618cd6a96
--   create_special_docs_for_invoice(uuid)                          429f4ac315cb5d0557c2005807bad115
--   reopen_invoice(uuid,text,uuid)                                 0ff61e4ead121c198ea7f90a7fc78274
--   fulfil_special_doc(text,uuid,uuid,text)                        9c3072e11013e8943b28d8a46854edc4
--   invoice_rental_correction_check(uuid,jsonb,uuid,uuid)          a7dca029412e83a9fb06d7499d68fa1f  (new; the service role's alone)
--   invoice_rentals_follow_lines(uuid,jsonb,text)                  e195b8e16322325b7790392ed827cec2  (new; the service role's alone)
--   rental_end_on_refund(uuid,integer,text)                        e8770411643bb293b8029539b1ff4fcb  (new; the service role's alone)
--   rentals_follow_refund(uuid,jsonb,text)                         0426b050207ccb4fe0a991b3cafc9769  (new; the service role's alone)
--   public function fingerprint, worked out on a copy of production (24 Oct 2026):
--     production now -> 456 -> 457 -> 458 (a second run the same)  ebee207bfe916c8b32d71cf366ca30a4 (1378 functions: four new, none dropped)
--     (on 451-455 alone: 0a508e264d8afd0f9b4a7da8ca10abe9, 1376)
--
-- Test: scripts/rentals/tests/invoice-follows-458.sql (begin ... rollback; it
-- installs this file twice, or -v skip_install=1 where it is installed):
-- each rule above, Cancel unchanged, and the md5s and grants.
-- scripts/permissions/tests/function-grants.sql lists the four new functions
-- among the internals no client role may call. Node tests:
-- scripts/rentals/tests/rentals-follow-458.test.mjs (the page helpers).
-- Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The six functions this patches: BEFORE (production now, 456 and 457
  -- in) and AFTER md5s ══════════════════════════════════════════════════════
  c_sigs constant text[] := array[
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'preview_invoice_correction(uuid,jsonb)',
    'settle_waiting_special_docs_on_refund(uuid,jsonb,text)',
    'create_special_docs_for_invoice(uuid)',
    'reopen_invoice(uuid,text,uuid)',
    'fulfil_special_doc(text,uuid,uuid,text)'];
  c_before constant text[] := array[
    '45e7f523e50a6b423b6e1d9f8836ebb6',
    '2bb7c0a5769050d5b2f9247a3aa05ecd',
    '307f671efc73adf5ebf8fedd9c880812',
    'e5503f03bf5b615ec9b948fecdc52b55',
    'cb647331300b0a476c1da7b2cb599889',
    '76f9495c44e017beb5275ed8a8112fda'];
  c_after constant text[] := array[
    'af9451fa15c2cf790edd70f799bae336',
    '3047239c7418179e84927f6f00e7f2eb',
    'edfd1f1beb7ab3b6739096a618cd6a96',
    '429f4ac315cb5d0557c2005807bad115',
    '0ff61e4ead121c198ea7f90a7fc78274',
    '9c3072e11013e8943b28d8a46854edc4'];
  -- each anchor (found once in its function's BEFORE text), the function it
  -- is in (an index into c_sigs) and its patch, in order
  c_fn constant int[] := array[1, 1, 1, 1, 1, 2, 3, 3, 4, 4, 4, 5, 6, 6];
  c_anchor constant text[] := array[
$a1$ v457_settled boolean;  -- 457: corrected as a settled invoice (an Owner or Manager, a reason)
$a1$,
$a2$ if v_operational and exists(select 1 from public.rentals where invoice_id=i.id and public.rental_is_outstanding(status::text)) then
   raise exception 'Return or resolve the outstanding rental before changing its invoice allocation'; end if;
$a2$,
$a3$ -- 416: preview_invoice_correction tries the correction up to here, inside
$a3$,
$a4$     detail = (select jsonb_build_object('total', v.total_amount, 'has_foc', coalesce(v.has_foc, false),
$a4$,
$a5$ return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'revision',v_rev,'therapy',v362_therapy)
$a5$,
$a6$    -- 416: taking the FOC off a completed FOC invoice takes back the
$a6$,
$a7$  if v_inv.status in ('refunded', 'cancelled') then
    return public.cancel_waiting_special_docs(p_invoice_id, 'refunded', p_reason);
  end if;
$a7$,
$a8$  end loop;
  return n;
end $function$
$a8$,
$a9$declare v_inv public.invoices%rowtype; v_it record; v_n integer := 0; v_i integer;
$a9$,
$a10$    if exists (select 1 from public.special_sales where invoice_item_id = v_it.id
                and (status <> 'cancelled' or warehouse_id is not null or source_store_id is not null
                     or coalesce(cancelled_at, 'infinity') > coalesce(v_inv.reopened_at, '-infinity')))
       or exists (select 1 from public.rentals where invoice_item_id = v_it.id
                and (status <> 'cancelled' or warehouse_id is not null or source_store_id is not null
                     or coalesce(cancelled_at, 'infinity') > coalesce(v_inv.reopened_at, '-infinity'))) then
      continue;
    end if;
$a10$,
$a11$         v_inv.customer_id, v_inv.store_id, greatest(coalesce(v_it.quantity,1),1),
         coalesce(v_it.rental_rate_type,'day'),
         round(coalesce(v_it.line_total,0) / greatest(coalesce(v_it.rental_periods,1),1), 2),
         greatest(coalesce(v_it.rental_periods,1),1), round(coalesce(v_it.line_total,0),2),
         coalesce(v_it.rental_start_date, public.sg_today()),
         coalesce(v_it.rental_return_date, public.sg_today() + greatest(coalesce(v_it.rental_periods,1),1)),
$a11$,
$a12$ if v_status='paid' then perform public.create_special_docs_for_invoice(i.id); end if;
$a12$,
$a13$  v_problem text;  -- 393
$a13$,
$a14$  if v_problem is not null then
    raise exception '% cannot be released: %. It is no longer waiting for a warehouse.', v_no, v_problem;
  end if;
$a14$];
  c_patch constant text[] := array[
$p1$ v457_settled boolean;  -- 457: corrected as a settled invoice (an Owner or Manager, a reason)
 v458_rentals jsonb := '[]'::jsonb;  -- 458: what this correction did to the invoice's rentals
$p1$,
$p2$ -- 458 (the Owner, 22 Oct 2026, rules 4 and 5): while a rental is out with
 -- the customer a correction may change its rate, periods and "Due back" and
 -- any other line; not its machine or quantity, nor remove its line, nor move
 -- the invoice to another customer or store, each refused in words. Before,
 -- every change to the lines, customer or store was refused while any rental
 -- was out.
 if v_operational then perform public.invoice_rental_correction_check(i.id,p_items,n.customer_id,n.store_id); end if;
$p2$,
$p3$ -- 458 (the Owner, 22 Oct 2026, rules 3, 4, 5 and 7): the invoice's rentals
 -- follow the corrected lines, customer and store, here so the correction
 -- summary below says what they become before anyone saves.
 v458_rentals := public.invoice_rentals_follow_lines(i.id,v_snapshot->'items',p_reason);
 -- 416: preview_invoice_correction tries the correction up to here, inside
$p3$,
$p4$     detail = (select jsonb_build_object('rentals', v458_rentals,  -- 458
                        'total', v.total_amount, 'has_foc', coalesce(v.has_foc, false),
$p4$,
$p5$ return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'revision',v_rev,'therapy',v362_therapy,
     'rentals',v458_rentals)  -- 458: what the correction did to the invoice's rentals, for the page to say
$p5$,
$p6$    -- 458 (the Owner, 22 Oct 2026, rule 3): the rentals that follow the
    -- corrected lines, customer and store, as the correction answers them.
    if jsonb_array_length(coalesce(v416_dry->'rentals', '[]'::jsonb)) > 0 then
      v_effects := v_effects || jsonb_build_array(jsonb_build_object(
        'area', 'rentals', 'change', 'changed',
        'detail', 'Each rental below changes with its line. No stock moves; a rental out with the customer keeps its machine and quantity.',
        'items', (select jsonb_agg(jsonb_build_object('kind', 'rental', 'what', e->>'what') order by e->>'rental_no')
                    from jsonb_array_elements(v416_dry->'rentals') e)));
    end if;
    -- 416: taking the FOC off a completed FOC invoice takes back the
$p6$,
$p7$  if v_inv.status in ('refunded', 'cancelled') then
    -- 458 (the Owner, 22 Oct 2026, rule 1): and every rental still out with
    -- the customer ends, as Cancel ends it (rentals_follow_refund).
    return public.cancel_waiting_special_docs(p_invoice_id, 'refunded', p_reason)
         + public.rentals_follow_refund(p_invoice_id, p_lines, p_reason);
  end if;
$p7$,
$p8$  end loop;
  -- 458 (the Owner, 22 Oct 2026, rules 1 and 2): a rental out on a line this
  -- refund takes back ends for the units refunded (all of them: the whole
  -- rental), and a waiting one still taken is lowered to the units kept.
  n := n + public.rentals_follow_refund(p_invoice_id, p_lines, p_reason);
  return n;
end $function$
$p8$,
$p9$declare v_inv public.invoices%rowtype; v_it record; v_n integer := 0; v_i integer;
  v458_units integer; v458_have integer; v458_cnt integer; v458_r public.rentals%rowtype;  -- 458
$p9$,
$p10$    if exists (select 1 from public.special_sales where invoice_item_id = v_it.id
                and (status <> 'cancelled' or warehouse_id is not null or source_store_id is not null
                     or coalesce(cancelled_at, 'infinity') > coalesce(v_inv.reopened_at, '-infinity'))) then
      continue;
    end if;
    -- 458 (the Owner, 22 Oct 2026, rule 6): a rental ended while out (with
    -- its invoice cancelled or refunded) before the invoice was last
    -- reopened, and not back yet, runs again with its due date; no stock
    -- moves, the unit never came back. One received back by then no longer
    -- counts, so its units wait for a warehouse again: the whole line when
    -- nothing else counts, otherwise the units missing. The rest as 393: a
    -- waiting rental cancelled before the reopening does not count; one
    -- cancelled since, running or returned does.
    v458_units := greatest(coalesce(v_it.quantity,1),1);
    if v_it.line_kind::text = 'rental' then
      for v458_r in select * from public.rentals
                     where invoice_item_id = v_it.id and status = 'cancelled' and not coalesce(stock_returned, false)
                       and (fulfilled_at is not null or activated_at is not null)
                       and v_inv.reopened_at is not null and cancelled_at <= v_inv.reopened_at
                     order by rental_no for update
      loop
        update public.rentals set status = 'active', cancelled_at = null,
               notes = concat_ws(E'\n', notes, 'Running again: invoice ' || coalesce(v_inv.invoice_no, '')
                       || ' was reopened before the item came back; due back as before')
         where id = v458_r.id;
        perform public.write_audit_ex('rentals', v458_r.id, 'rental_running_again', to_jsonb(v458_r),
          jsonb_build_object('status', 'active', 'invoice_id', p_invoice_id, 'invoice_no', v_inv.invoice_no,
            'expected_return_date', v458_r.expected_return_date), 'rentals', null, v458_r.store_id);
      end loop;
      select coalesce(sum(quantity), 0)::integer, count(*)::integer into v458_have, v458_cnt
        from public.rentals
       where invoice_item_id = v_it.id
         and (status <> 'cancelled' or coalesce(cancelled_at, 'infinity') > coalesce(v_inv.reopened_at, '-infinity')
              or ((warehouse_id is not null or source_store_id is not null) and not coalesce(stock_returned, false)));
      if v458_cnt > 0 and (v458_have >= v458_units or not exists (
           select 1 from public.rentals
            where invoice_item_id = v_it.id and status = 'cancelled' and coalesce(stock_returned, false)
              and (warehouse_id is not null or source_store_id is not null)
              and coalesce(cancelled_at, 'infinity') <= coalesce(v_inv.reopened_at, '-infinity'))) then
        continue;
      end if;
      v458_units := v458_units - v458_have;
      continue when v458_units <= 0;
    end if;
$p10$,
$p11$         v_inv.customer_id, v_inv.store_id, v458_units,  -- 458: the units to raise
         coalesce(v_it.rental_rate_type,'day'),
         round(round(coalesce(v_it.line_total,0) * v458_units / greatest(coalesce(v_it.quantity,1),1), 2)
               / greatest(coalesce(v_it.rental_periods,1),1), 2),
         greatest(coalesce(v_it.rental_periods,1),1),
         round(coalesce(v_it.line_total,0) * v458_units / greatest(coalesce(v_it.quantity,1),1), 2),
         coalesce(v_it.rental_start_date, public.sg_today()),
         -- 458 (the Owner, 22 Oct 2026, rule 7): "Due back" left blank is the
         -- start plus the periods by the rate type (426's update_pending_rental),
         -- not today plus the periods counted as days.
         coalesce(v_it.rental_return_date,
           (coalesce(v_it.rental_start_date, public.sg_today()) + case coalesce(v_it.rental_rate_type,'day')
              when 'day' then make_interval(days => greatest(coalesce(v_it.rental_periods,1),1))
              when 'week' then make_interval(days => 7 * greatest(coalesce(v_it.rental_periods,1),1))
              when 'month' then make_interval(months => greatest(coalesce(v_it.rental_periods,1),1))
              else make_interval(years => greatest(coalesce(v_it.rental_periods,1),1)) end)::date),
$p11$,
$p12$ -- 458 (the Owner, 22 Oct 2026, rule 6): and reopened as completed FOC, as
 -- Confirm FOC raises them; create_special_docs_for_invoice also sets a
 -- rental ended while out running again, or raises a new one for a unit
 -- received back.
 if v_status in ('paid','completed_foc') then perform public.create_special_docs_for_invoice(i.id); end if;
$p12$,
$p13$  v_problem text;  -- 393
  v458_inv text; v458_owing numeric;  -- 458
$p13$,
$p14$  if v_problem is not null then
    raise exception '% cannot be released: %. It is no longer waiting for a warehouse.', v_no, v_problem;
  end if;
  -- 458 (the Owner, 22 Oct 2026, rule 3): a rental waits for its invoice to
  -- be paid in full before it goes out, as 393's items wait for the payment.
  -- A rental is raised only once its invoice is paid, so this is an invoice
  -- a correction (or a payment taken back) left owing: a waiting rental that
  -- followed its line to more machines, a longer rental or another machine,
  -- or one beside a line added unpaid. Released once the rest is paid.
  if p_doc_kind = 'rental' then
    select i.invoice_no, greatest(public.invoice_charge_total(i.id) - public.invoice_net_received(i.id), 0)
      into v458_inv, v458_owing
      from public.rentals x join public.invoices i on i.id = x.invoice_id
     where x.id = p_doc_id and i.status in ('unpaid', 'partially_paid');
    if coalesce(v458_owing, 0) > 0 then
      raise exception '% cannot be released yet: its invoice % has S$% owing. Take the payment first, then release it.',
        v_no, v458_inv, to_char(v458_owing, 'FM999999990.00');
    end if;
  end if;
$p14$];

  -- ══ The four functions this adds (the server's alone) ═════════════════════
  c_new constant text[] := array[
    'invoice_rental_correction_check(uuid,jsonb,uuid,uuid)',
    'invoice_rentals_follow_lines(uuid,jsonb,text)',
    'rental_end_on_refund(uuid,integer,text)',
    'rentals_follow_refund(uuid,jsonb,text)'];
  c_new_after constant text[] := array[
    'a7dca029412e83a9fb06d7499d68fa1f',
    'e195b8e16322325b7790392ed827cec2',
    'e8770411643bb293b8029539b1ff4fcb',
    '0426b050207ccb4fe0a991b3cafc9769'];
  c_internal_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';
  c_new_def constant text[] := array[
$d1$CREATE OR REPLACE FUNCTION public.invoice_rental_correction_check(p_invoice_id uuid, p_items jsonb, p_customer_id uuid, p_store_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 458 (the Owner, 22 Oct 2026, rules 4 and 5): what a correction may do while
-- a rental of the invoice is out with the customer. Its rate, periods and
-- "Due back" may change, and any other line, the notes and the payments. Its
-- machine and quantity may not (they went out with the customer), its line
-- may not go, and the invoice may not move to another customer or store
-- (the machine is with this customer; a late fee would go to the other).
-- correct_invoice asks this when the correction changes the lines, the
-- customer or the store; before 458 it refused all of those while any rental
-- was out. p_items are the corrected lines; p_customer_id and p_store_id the
-- invoice's customer and store after the correction.
declare v_inv public.invoices%rowtype; r public.rentals%rowtype; li public.invoice_items%rowtype; x jsonb;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  for r in select * from public.rentals
            where invoice_id = p_invoice_id and public.rental_is_outstanding(status::text)
            order by rental_no
  loop
    if (p_customer_id, p_store_id) is distinct from (v_inv.customer_id, v_inv.store_id) then
      raise exception '% is out with the customer: Return it first. The invoice cannot move to another customer or store while its rental is out.',
        r.rental_no;
    end if;
    select * into li from public.invoice_items where id = r.invoice_item_id and invoice_id = p_invoice_id;
    if li.id is null then
      -- A rental out that names no line of this invoice: refused as before 458.
      raise exception 'Return or resolve the outstanding rental before changing its invoice allocation';
    end if;
    x := (select e from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) e
           where nullif(e->>'invoice_item_id', '') = li.id::text limit 1);
    if x is null then
      raise exception '% is out with the customer: Return it first. Its line cannot be removed while it is out.', r.rental_no;
    end if;
    if nullif(x->>'special_product_id', '')::uuid is distinct from li.special_product_id
       or coalesce(nullif(x->>'quantity', '')::integer, 0) <> li.quantity then
      raise exception '% is out with the customer: Return it first. Its machine and quantity stay as they went out; its rate, periods and "Due back" can change.',
        r.rental_no;
    end if;
  end loop;
end $function$
$d1$,
$d2$CREATE OR REPLACE FUNCTION public.invoice_rentals_follow_lines(p_invoice_id uuid, p_before jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 458 (the Owner, 22 Oct 2026, rules 3, 4, 5 and 7): an invoice's rentals
-- follow a correction of its lines, customer and store. correct_invoice calls
-- it once the corrected lines and header are saved (p_before: the lines as
-- they were, as its revision snapshot holds them); the correction summary
-- shows what it answers.
--   * Waiting for a warehouse (not released): the rental is its line's again:
--     its machine, rate type, periods, start and "Due back", and the line's
--     machines less those that are not this rental's: on the line's other
--     rentals that still count (out, back, ended since the invoice was last
--     reopened, or ended and not back) and those a refund took off a waiting
--     rental since then ('rental_part_refunded_waiting'); refused in words
--     when that leaves none. Its fee and rate are its share of the line as
--     the invoice raises them (create_special_docs_for_invoice: the line's
--     value before its discount, over the periods), so 426's "fee as sold"
--     reads the line; and the invoice's customer and store whenever they
--     differ. While the invoice owes money it waits for the payment
--     (fulfil_special_doc), and its words say so.
--   * Out with the customer: its rate type, periods and "Due back" follow,
--     with the fee (its share of the line, for the units it holds) and rate;
--     its machine, quantity, start, customer and store stay
--     (invoice_rental_correction_check refused a change to them first).
--   * "Due back" blank: the start plus the periods by the rate type (426's
--     update_pending_rental), never before the start (refused in words).
--   * Only a rental whose line this correction changed follows the line: one
--     whose terms were changed on the Special page keeps them until its line
--     is corrected. A returned or cancelled rental, and every rental of a
--     cancelled or refunded invoice, is left as it is.
-- Each change is noted on the rental and audited ('rental_follows_invoice_
-- line', before and after). Answers [{rental_id, rental_no, state, what}].
declare
  v_inv public.invoices%rowtype; r public.rentals%rowtype; li public.invoice_items%rowtype; b jsonb;
  v_out boolean; v_terms boolean; v_moved boolean; v_type public.special_rate_type; v_per integer;
  v_qty integer; v_start date; v_due date; v_fee numeric; v_new public.rentals%rowtype;
  v_list jsonb := '[]'::jsonb; v_what text; v_owes boolean;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found or v_inv.status in ('cancelled', 'refunded') then return v_list; end if;
  -- The corrected invoice owes money (before any payment this correction
  -- records): a waiting rental is released once it is paid in full.
  v_owes := public.invoice_charge_total(p_invoice_id) > public.invoice_net_received(p_invoice_id);
  for r in select x.* from public.rentals x
            where x.invoice_id = p_invoice_id and x.invoice_item_id is not null
              and ((x.status = 'awaiting_fulfilment' and x.warehouse_id is null and x.source_store_id is null)
                   or public.rental_is_outstanding(x.status::text))
            order by x.rental_no
            for update
  loop
    select * into li from public.invoice_items where id = r.invoice_item_id and invoice_id = p_invoice_id;
    continue when li.id is null;
    v_out := public.rental_is_outstanding(r.status::text);
    b := (select e from jsonb_array_elements(coalesce(p_before, '[]'::jsonb)) e where e->>'id' = li.id::text limit 1);
    v_terms := b is not null and (
        nullif(b->>'special_product_id', '')::uuid, nullif(b->>'quantity', '')::integer,
        nullif(b->>'rental_rate_type', ''), nullif(b->>'rental_periods', '')::integer,
        nullif(b->>'rental_start_date', '')::date, nullif(b->>'rental_return_date', '')::date,
        nullif(b->>'line_total', '')::numeric)
      is distinct from (li.special_product_id, li.quantity, li.rental_rate_type::text, li.rental_periods,
        li.rental_start_date, li.rental_return_date, li.line_total);
    v_moved := not v_out and (r.customer_id, r.store_id) is distinct from (v_inv.customer_id, v_inv.store_id);
    continue when not v_terms and not v_moved;

    v_new := r;
    if not v_out then
      v_new.customer_id := v_inv.customer_id;
      v_new.store_id := v_inv.store_id;
    end if;
    if v_terms then
      v_type := coalesce(li.rental_rate_type, 'day');
      v_per := greatest(coalesce(li.rental_periods, 1), 1);
      if v_out then
        v_qty := r.quantity;
        v_start := r.start_date;
      else
        -- The line's machines less those that are not this rental's: on the
        -- line's other rentals that still count (as create_special_docs_for_
        -- invoice counts them: out, back, ended since the invoice was last
        -- reopened, or ended and not back), and those a refund took off a
        -- waiting rental since then. A quantity change of the line is this
        -- rental's alone (a line with a rental out keeps its quantity).
        v_qty := greatest(coalesce(li.quantity, 1), 1)
          - (select coalesce(sum(x.quantity), 0)::integer from public.rentals x
              where x.invoice_item_id = li.id and x.id <> r.id
                and (x.status <> 'cancelled'
                     or coalesce(x.cancelled_at, 'infinity') > coalesce(v_inv.reopened_at, '-infinity')
                     or ((x.warehouse_id is not null or x.source_store_id is not null)
                         and not coalesce(x.stock_returned, false))))
          - (select coalesce(sum((a.new_data->>'refunded_units')::integer), 0)::integer from public.audit_logs a
              where a.table_name = 'rentals' and a.action = 'rental_part_refunded_waiting'
                and a.new_data->>'invoice_item_id' = li.id::text
                and a.created_at > coalesce(v_inv.reopened_at, '-infinity'));
        if v_qty < 1 then
          raise exception '%: % of this line''s machines are refunded or on other rentals, so with % on the line it would hold none. Keep at least % on the line, or cancel % on the Special page.',
            r.rental_no, greatest(coalesce(li.quantity, 1), 1) - v_qty, greatest(coalesce(li.quantity, 1), 1),
            greatest(coalesce(li.quantity, 1), 1) - v_qty + 1, r.rental_no;
        end if;
        v_start := coalesce(li.rental_start_date, r.start_date);
        v_new.special_product_id := li.special_product_id;
        if li.special_product_id is distinct from r.special_product_id then
          v_new.late_fee_per_day := coalesce((select sp.late_fee_per_day from public.special_products sp
                                               where sp.id = li.special_product_id), 0);
        end if;
      end if;
      v_due := coalesce(li.rental_return_date, (v_start + case v_type
                 when 'day' then make_interval(days => v_per)
                 when 'week' then make_interval(days => 7 * v_per)
                 when 'month' then make_interval(months => v_per)
                 else make_interval(years => v_per) end)::date);
      if v_due < v_start then
        raise exception '%: "Due back" (%) cannot be before the rental''s start (%).', r.rental_no,
          to_char(v_due, 'DD/MM/YYYY'), to_char(v_start, 'DD/MM/YYYY');
      end if;
      -- As the invoice raises it: the line's value before its discount, for
      -- the units this rental holds.
      v_fee := case when v_qty = greatest(coalesce(li.quantity, 1), 1) then round(coalesce(li.line_total, 0), 2)
                    else round(coalesce(li.line_total, 0) * v_qty / greatest(coalesce(li.quantity, 1), 1), 2) end;
      v_new.quantity := v_qty;
      v_new.rate_type := v_type;
      v_new.periods := v_per;
      v_new.rental_fee := v_fee;
      v_new.rate_amount := round(v_fee / v_per, 2);
      v_new.start_date := v_start;
      v_new.expected_return_date := v_due;
    end if;
    continue when (v_new.special_product_id, v_new.customer_id, v_new.store_id, v_new.quantity, v_new.rate_type,
                   v_new.periods, v_new.rental_fee, v_new.rate_amount, v_new.start_date, v_new.expected_return_date,
                   v_new.late_fee_per_day)
                  is not distinct from
                  (r.special_product_id, r.customer_id, r.store_id, r.quantity, r.rate_type,
                   r.periods, r.rental_fee, r.rate_amount, r.start_date, r.expected_return_date,
                   r.late_fee_per_day);
    update public.rentals set
      special_product_id = v_new.special_product_id, customer_id = v_new.customer_id, store_id = v_new.store_id,
      quantity = v_new.quantity, rate_type = v_new.rate_type, periods = v_new.periods,
      rental_fee = v_new.rental_fee, rate_amount = v_new.rate_amount,
      start_date = v_new.start_date, expected_return_date = v_new.expected_return_date,
      late_fee_per_day = v_new.late_fee_per_day,
      notes = concat_ws(E'\n', notes, 'Follows invoice ' || coalesce(v_inv.invoice_no, '') || ' as corrected: '
              || coalesce(nullif(btrim(p_reason), ''), 'Invoice corrected'))
     where id = r.id;
    v_what := r.rental_no || case when v_out then ' (out with the customer)' else ' (waiting for a warehouse)' end || ': '
      || concat_ws('; ',
           case when v_terms then
             v_new.quantity || ' × ' || v_new.periods || ' ' || v_new.rate_type::text
             || case when v_new.periods = 1 then '' else 's' end
             || ', S$' || to_char(v_new.rental_fee, 'FM999999990.00')
             || ', due back ' || to_char(v_new.expected_return_date, 'DD/MM/YYYY')
             || case when v_new.expected_return_date is distinct from r.expected_return_date
                     then ' (was ' || to_char(r.expected_return_date, 'DD/MM/YYYY') || ')' else '' end end,
           case when v_new.special_product_id is distinct from r.special_product_id then
             'now ' || coalesce((select sp.name from public.special_products sp where sp.id = v_new.special_product_id),
                                'another machine') end,
           case when v_new.customer_id is distinct from r.customer_id then
             'moves to ' || coalesce((select c.full_name from public.customers c where c.id = v_new.customer_id),
                                     'the invoice''s customer') end,
           case when v_new.store_id is distinct from r.store_id then
             'moves to ' || coalesce((select s.name from public.stores s where s.id = v_new.store_id),
                                     'the invoice''s store') end,
           case when not v_out and v_owes then 'released once the invoice is paid in full' end);
    perform public.write_audit_ex('rentals', r.id, 'rental_follows_invoice_line',
      jsonb_build_object('special_product_id', r.special_product_id, 'customer_id', r.customer_id, 'store_id', r.store_id,
        'quantity', r.quantity, 'rate_type', r.rate_type, 'periods', r.periods, 'rental_fee', r.rental_fee,
        'rate_amount', r.rate_amount, 'start_date', r.start_date, 'expected_return_date', r.expected_return_date),
      jsonb_build_object('special_product_id', v_new.special_product_id, 'customer_id', v_new.customer_id,
        'store_id', v_new.store_id, 'quantity', v_new.quantity, 'rate_type', v_new.rate_type, 'periods', v_new.periods,
        'rental_fee', v_new.rental_fee, 'rate_amount', v_new.rate_amount, 'start_date', v_new.start_date,
        'expected_return_date', v_new.expected_return_date, 'invoice_id', p_invoice_id, 'invoice_item_id', li.id,
        'state', case when v_out then 'out' else 'waiting' end),
      'rentals', p_reason, v_new.store_id);
    v_list := v_list || jsonb_build_array(jsonb_build_object('rental_id', r.id, 'rental_no', r.rental_no,
      'state', case when v_out then 'out' else 'waiting' end, 'what', v_what));
  end loop;
  return v_list;
end $function$
$d2$,
$d3$CREATE OR REPLACE FUNCTION public.rental_end_on_refund(p_rental_id uuid, p_units integer, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 458 (the Owner, 22 Oct 2026, rules 1 and 2): a refund ends a rental out with
-- the customer as Cancel ends it (cancel_invoice_rentals, 300): it stops
-- running (Return refuses it, so no late fee), reads "still with customer"
-- (rental_awaiting_return) and is received back, damaged or lost with the
-- receive step Cancel uses (receive_returned_rental), which puts it back
-- where it came from. No stock moves here.
--   * p_units null, or all the rental holds: the rental itself ends.
--   * Fewer: it keeps running for the rest (its quantity, fee and rate
--     lowered in proportion), and the units refunded become a rental number
--     of their own: the same machine, released from the same place, ended at
--     once, so they are received back on their own.
-- Answers the rental now waiting to come back (null: nothing ended).
declare r public.rentals%rowtype; v_id uuid; v_no text; v_fee numeric; v_rate numeric; v_note text;
begin
  select * into r from public.rentals where id = p_rental_id for update;
  if not found or not public.rental_is_outstanding(r.status::text) or coalesce(p_units, r.quantity) <= 0 then
    return null;
  end if;
  v_note := 'Refunded while still out; awaiting physical return: ' || coalesce(nullif(btrim(p_reason), ''), 'Refund');
  if coalesce(p_units, r.quantity) >= r.quantity then
    update public.rentals set status = 'cancelled', cancelled_at = now(), notes = concat_ws(E'\n', notes, v_note)
     where id = r.id;
    perform public.write_audit_ex('rentals', r.id, 'rental_refunded_awaiting_return', to_jsonb(r),
      jsonb_build_object('status', 'cancelled', 'invoice_id', r.invoice_id, 'invoice_item_id', r.invoice_item_id,
        'quantity', r.quantity, 'reason', p_reason, 'stock_returned', coalesce(r.stock_returned, false)),
      'rentals', p_reason, r.store_id);
    return r.id;
  end if;
  v_fee := round(r.rental_fee * p_units / r.quantity, 2);
  v_rate := round(r.rate_amount * p_units / r.quantity, 2);
  v_no := 'RNT-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.rental_no_seq')::text, 4, '0');
  insert into public.rentals
    (rental_no, special_product_id, warehouse_id, customer_id, store_id, quantity, rate_type, rate_amount, periods,
     rental_fee, start_date, expected_return_date, status, payment_method_id, payment_reference, paid_at,
     activated_at, stock_returned, late_fee_per_day, notes, created_by, cancelled_at, is_foc, invoice_id,
     invoice_item_id, fulfilled_at, fulfilled_by, source_type, source_store_id)
  values (v_no, r.special_product_id, r.warehouse_id, r.customer_id, r.store_id, p_units, r.rate_type, v_rate, r.periods,
     v_fee, r.start_date, r.expected_return_date, 'cancelled', r.payment_method_id, r.payment_reference, r.paid_at,
     r.activated_at, r.stock_returned, r.late_fee_per_day,
     'Split from ' || r.rental_no || ': ' || p_units || ' of its ' || r.quantity || ' refunded.' || E'\n' || v_note,
     auth.uid(), now(), r.is_foc, r.invoice_id,
     r.invoice_item_id, r.fulfilled_at, r.fulfilled_by, r.source_type, r.source_store_id)
  returning id into v_id;
  update public.rentals set quantity = quantity - p_units, rental_fee = rental_fee - v_fee, rate_amount = rate_amount - v_rate,
         notes = concat_ws(E'\n', notes, p_units || ' of ' || r.quantity || ' refunded while still out (' || v_no
                 || ', awaiting physical return); ' || (r.quantity - p_units) || ' still rented: '
                 || coalesce(nullif(btrim(p_reason), ''), 'Refund'))
   where id = r.id;
  perform public.write_audit_ex('rentals', r.id, 'rental_part_refunded',
    jsonb_build_object('quantity', r.quantity, 'rental_fee', r.rental_fee, 'rate_amount', r.rate_amount),
    jsonb_build_object('quantity', r.quantity - p_units, 'rental_fee', r.rental_fee - v_fee,
      'rate_amount', r.rate_amount - v_rate, 'refunded_units', p_units, 'split_rental_id', v_id,
      'split_rental_no', v_no, 'reason', p_reason),
    'rentals', p_reason, r.store_id);
  perform public.write_audit_ex('rentals', v_id, 'rental_refunded_awaiting_return', null,
    jsonb_build_object('status', 'cancelled', 'invoice_id', r.invoice_id, 'invoice_item_id', r.invoice_item_id,
      'quantity', p_units, 'split_from', r.id, 'split_from_no', r.rental_no, 'reason', p_reason),
    'rentals', p_reason, r.store_id);
  return v_id;
end $function$
$d3$,
$d4$CREATE OR REPLACE FUNCTION public.rentals_follow_refund(p_invoice_id uuid, p_lines jsonb, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 458 (the Owner, 22 Oct 2026, rules 1 and 2): what a recorded refund does to
-- the invoice's rentals, after 393 has dealt with those waiting
-- (settle_waiting_special_docs_on_refund calls this last, on both its paths).
--   * A refund that leaves the invoice refunded (or one on a cancelled
--     invoice) ends every rental still out with the customer.
--   * Otherwise, by rental line the refund names: the whole units of the
--     line's value (invoice_discounted_line_value, as 393 reads it) that the
--     money refunded on the line since it was last reopened covers, this
--     refund included (within a cent of the whole value is every unit), come
--     off what the customer keeps. What the line's rentals still hold (out
--     with the customer, or waiting for a warehouse and still taken: 393
--     cancelled one answered "not taking", or whose line went back whole
--     with no answer) beyond what is kept comes off, counted across them:
--     - first a waiting one (the newest first; no machine to bring back): its
--       quantity, fee and rate lowered ('rental_part_refunded_waiting'), or
--       cancelled as 393 cancels (cancel_waiting_special_docs) when all of it
--       goes;
--     - then a rental out (the newest first): the units end
--       (rental_end_on_refund: the whole rental, or the units refunded split
--       off); the rest keeps running;
--     - last a waiting one staff answered "still taking" (393's question);
--       kept whole when the line went back in full (393's answer).
--     An amount short of one unit ends and lowers nothing.
-- Answers how many rentals it changed.
declare
  v_inv public.invoices%rowtype; li public.invoice_items%rowtype; r public.rentals%rowtype;
  v_value numeric; v_refunded numeric; v_units integer; v_keep integer; v_held integer; v_left integer;
  v_take integer; v_fee numeric; v_taking jsonb; n integer := 0;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return 0; end if;
  if v_inv.status in ('refunded', 'cancelled') then
    for r in select * from public.rentals
              where invoice_id = p_invoice_id and public.rental_is_outstanding(status::text)
              order by rental_no for update
    loop
      if public.rental_end_on_refund(r.id, null, p_reason) is not null then n := n + 1; end if;
    end loop;
    return n;
  end if;
  -- 393's answers "still taking" (settle_waiting_special_docs_on_refund
  -- checked them first).
  select coalesce(jsonb_object_agg(lower(q->>'doc_id'), true), '{}'::jsonb) into v_taking
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) e,
         jsonb_array_elements(case when jsonb_typeof(e->'waiting') = 'array' then e->'waiting' else '[]'::jsonb end) q
   where q->'still_taking' = 'true'::jsonb;
  for li in select it.* from public.invoice_items it
             where it.invoice_id = p_invoice_id and it.line_kind::text = 'rental'
               and exists (select 1 from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) e
                            where e->>'invoice_item_id' = it.id::text and e ? 'amount')
             order by it.id
  loop
    v_value := coalesce(public.invoice_discounted_line_value(li.id), 0);
    continue when v_value <= 0 or coalesce(li.quantity, 0) <= 0;
    select coalesce(sum((e->>'amount')::numeric), 0) into v_refunded
      from public.invoice_refunds rf, jsonb_array_elements(coalesce(rf.outcome->'lines', '[]'::jsonb)) e
     where rf.invoice_id = p_invoice_id
       and (v_inv.reopened_at is null or rf.created_at > v_inv.reopened_at)
       and e->>'invoice_item_id' = li.id::text;
    v_units := case when v_refunded >= v_value - 0.01 then li.quantity
                    else least(floor((v_refunded + 0.01) * li.quantity / v_value)::integer, li.quantity) end;
    continue when v_units <= 0;
    v_keep := li.quantity - v_units;
    -- What the line's rentals still hold, out or waiting, beyond what is kept.
    select coalesce(sum(x.quantity), 0)::integer into v_held from public.rentals x
     where x.invoice_id = p_invoice_id and x.invoice_item_id = li.id
       and (public.rental_is_outstanding(x.status::text)
            or (x.status = 'awaiting_fulfilment' and x.warehouse_id is null and x.source_store_id is null));
    v_left := v_held - v_keep;
    for r in select x.* from public.rentals x
              where x.invoice_id = p_invoice_id and x.invoice_item_id = li.id
                and (public.rental_is_outstanding(x.status::text)
                     or (x.status = 'awaiting_fulfilment' and x.warehouse_id is null and x.source_store_id is null))
              order by case when public.rental_is_outstanding(x.status::text) then 1
                            when v_taking ? x.id::text then 2 else 0 end, x.rental_no desc
              for update
    loop
      exit when v_left <= 0;
      -- Answered "still taking" and its line refunded in full: kept (393).
      continue when v_keep <= 0 and v_taking ? r.id::text;
      v_take := least(v_left, r.quantity);
      if public.rental_is_outstanding(r.status::text) then
        -- Out: the units end (all of them: the rental itself).
        if public.rental_end_on_refund(r.id, v_take, p_reason) is not null then n := n + 1; end if;
      elsif v_take >= r.quantity then
        -- Waiting, all of it refunded: cancelled as 393 cancels it.
        n := n + public.cancel_waiting_special_docs(p_invoice_id, 'refunded', p_reason, null, array[r.id]);
      else
        -- Waiting, some of it: lowered to what it keeps.
        v_fee := round(r.rental_fee * (r.quantity - v_take) / r.quantity, 2);
        update public.rentals set quantity = r.quantity - v_take, rental_fee = v_fee,
               rate_amount = round(v_fee / greatest(r.periods, 1), 2),
               notes = concat_ws(E'\n', notes, 'Part refunded while waiting: ' || (r.quantity - v_take) || ' of ' || r.quantity
                       || ' kept: ' || coalesce(nullif(btrim(p_reason), ''), 'Refund'))
         where id = r.id;
        perform public.write_audit_ex('rentals', r.id, 'rental_part_refunded_waiting',
          jsonb_build_object('quantity', r.quantity, 'rental_fee', r.rental_fee, 'rate_amount', r.rate_amount),
          jsonb_build_object('quantity', r.quantity - v_take, 'rental_fee', v_fee,
            'rate_amount', round(v_fee / greatest(r.periods, 1), 2),
            'refunded_units', v_take, 'invoice_id', p_invoice_id, 'invoice_item_id', li.id,
            'reason', p_reason),
          'rentals', p_reason, r.store_id);
        n := n + 1;
      end if;
      v_left := v_left - v_take;
    end loop;
  end loop;
  return n;
end $function$
$d4$];

  -- ══ Relied on, not changed (production now, 456 and 457 in) ═════════════
  c_relied constant text[] := array[
    'cancel_invoice_rentals(uuid,text)',
    'rental_awaiting_return(uuid)',
    'rental_is_outstanding(text)',
    'rental_is_unfulfilled(text)',
    'invoice_rentals_awaiting_return(uuid)',
    'receive_returned_rental(uuid,uuid,text,text,uuid)',
    'rental_put_back_stock(uuid)',
    'return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text)',
    'trg_rental_stock_back()',
    'update_pending_rental(uuid,integer,special_rate_type,integer,date,date,text)',
    'cancel_waiting_special_docs(uuid,text,text,uuid,uuid[])',
    'trg_special_docs_follow_line_removed()',
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'invoice_discounted_line_value(uuid)',
    'invoice_charge_total(uuid)',
    'invoice_net_received(uuid)',
    'invoice_action_plan(uuid,text,jsonb)',
    'resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)',
    'update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)',
    'invoice_line_matches(uuid,jsonb)',
    'invoice_record_payments_internal(uuid,jsonb)',
    'confirm_foc_invoice(uuid,text)',
    'special_doc_invoice_problem(uuid,uuid)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'sg_today()',
    'user_has_store_access(uuid)',
    'is_owner_or_manager()',
    'normalize_customer_phone(text)',
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    'pay_invoice(uuid,jsonb)',
    'upsert_special_product_from_product(uuid,uuid,numeric,numeric,numeric,numeric,numeric,numeric,text,boolean)'];
  c_relied_md5 constant text[] := array[
    '15aef6f8c9ef2022810f2181f512b150',
    '88ba77463d293bc77fba5e5cad3d3210',
    '076549a44bc057cd529aac5542c4d06e',
    '2cff280461925fefc88dcc9776f3bfd1',
    '07621bd5ba0b8be5cf69460ac4212017',
    '362b0175b60e12c97e427b5180e01960',
    '8ca55272c76c62b295d5001b0943e85a',
    '659a74da796b7360a3730347730e0d65',
    'a75c600cd86edc5b43fb464a5bfe34a8',
    '1022ecdafb4e1e2f21e7dc051376b028',
    'fe4753fffded2cc463dbe24571a9675c',
    '25b2fac3612be3ab56151f3e109c3574',
    '804ecd829cfecf713783a09a05d93c7e',
    'de52d9dbaef8ab15163bef35cb9d733d',
    'ead4a430c3abd1e3f953912867ca4fe6',
    '8297147511ba285db2279598f3d727fb',
    'f256bea69b7defa38a950753bbc248da',
    '383d618edb28c3c9a360242d038a022c',
    '201f08ebf14a64cd88d411a7cfb4c9c4',
    '1f034561a461bdb46a1e6274e0d04606',
    '0c32f7c591efb9864ff5b1cb2201b744',
    '21890d84bcb0b9c00a2bc98aff313d0b',
    'ba8b1ce2a5671989b927891f0cb7b1a2',
    'be2b8ec5a4003a1dca34e17a82f89932',
    'c705c733e213a27f0dc32d54322cc855',
    '1c1289f18e24d8370e9a6364c9c06fca',
    '708992afaa6c3951f6329239b742987c',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    'b2bfac910e0c9eff402ba44e19750bee',
    '80c80d386a5241e63b353e35e13ef250',
    '19baf63628acbce946961f4031e3da73',
    '312e25496c17975e56065e968a9b6c59'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; n int; i int; k int;
  v_texts text[] := array[null, null, null, null, null, null]::text[];
  v_acls text[] := array[null, null, null, null, null, null]::text[];
  v_make boolean[] := array[false, false, false, false]::boolean[];
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_sa uuid; t_sb uuid; t_wh uuid; t_ca uuid; t_cb uuid; t_cash uuid;
  t_prod uuid; t_sp uuid; t_inv uuid; t_line uuid; t_r uuid; t_res jsonb; t_msg text; t_wq int; t_due date;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── 1. Checks: nothing is changed before all of them pass ──────────────
  -- What it relies on and does not change: as read on production with 456
  -- and 457 in, 24 Oct 2026.
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '458: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  -- 393's line-removed trigger, which cancels a waiting rental whose line goes.
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoice_items'::regclass
                   and t.tgname = 'special_docs_follow_line_removed'
                   and t.tgfoid = 'public.trg_special_docs_follow_line_removed()'::regprocedure and t.tgenabled = 'O') then
    raise exception '458: the trigger special_docs_follow_line_removed on invoice_items is missing or not as read on 24 Oct 2026'; end if;
  if to_regclass('public.rental_no_seq') is null then
    raise exception '458: the sequence public.rental_no_seq is missing'; end if;

  -- The columns it reads and writes, with these types.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('rentals', 'id', 'uuid'), ('rentals', 'rental_no', 'text'), ('rentals', 'special_product_id', 'uuid'),
                 ('rentals', 'warehouse_id', 'uuid'), ('rentals', 'customer_id', 'uuid'), ('rentals', 'store_id', 'uuid'),
                 ('rentals', 'quantity', 'integer'), ('rentals', 'rate_type', 'special_rate_type'),
                 ('rentals', 'rate_amount', 'numeric(12,2)'), ('rentals', 'periods', 'integer'),
                 ('rentals', 'rental_fee', 'numeric(12,2)'), ('rentals', 'start_date', 'date'),
                 ('rentals', 'expected_return_date', 'date'), ('rentals', 'status', 'rental_status'),
                 ('rentals', 'payment_method_id', 'uuid'), ('rentals', 'payment_reference', 'text'),
                 ('rentals', 'paid_at', 'timestamp with time zone'), ('rentals', 'activated_at', 'timestamp with time zone'),
                 ('rentals', 'stock_returned', 'boolean'), ('rentals', 'late_fee_per_day', 'numeric(12,2)'),
                 ('rentals', 'notes', 'text'), ('rentals', 'created_by', 'uuid'),
                 ('rentals', 'cancelled_at', 'timestamp with time zone'), ('rentals', 'is_foc', 'boolean'),
                 ('rentals', 'invoice_id', 'uuid'), ('rentals', 'invoice_item_id', 'uuid'),
                 ('rentals', 'fulfilled_at', 'timestamp with time zone'), ('rentals', 'fulfilled_by', 'uuid'),
                 ('rentals', 'source_type', 'location_type'), ('rentals', 'source_store_id', 'uuid'),
                 ('invoice_items', 'id', 'uuid'), ('invoice_items', 'invoice_id', 'uuid'),
                 ('invoice_items', 'line_kind', 'invoice_line_kind'), ('invoice_items', 'quantity', 'integer'),
                 ('invoice_items', 'line_total', 'numeric(12,2)'), ('invoice_items', 'special_product_id', 'uuid'),
                 ('invoice_items', 'rental_rate_type', 'special_rate_type'), ('invoice_items', 'rental_periods', 'integer'),
                 ('invoice_items', 'rental_start_date', 'date'), ('invoice_items', 'rental_return_date', 'date'),
                 ('invoices', 'id', 'uuid'), ('invoices', 'invoice_no', 'text'), ('invoices', 'status', 'invoice_status'),
                 ('invoices', 'customer_id', 'uuid'), ('invoices', 'store_id', 'uuid'),
                 ('invoices', 'reopened_at', 'timestamp with time zone'),
                 ('invoice_refunds', 'invoice_id', 'uuid'), ('invoice_refunds', 'outcome', 'jsonb'),
                 ('invoice_refunds', 'created_at', 'timestamp with time zone'),
                 ('special_products', 'id', 'uuid'), ('special_products', 'name', 'text'),
                 ('special_products', 'late_fee_per_day', 'numeric(12,2)'),
                 ('customers', 'full_name', 'text'), ('stores', 'name', 'text'),
                 ('audit_logs', 'table_name', 'text'), ('audit_logs', 'action', 'text'),
                 ('audit_logs', 'new_data', 'jsonb'), ('audit_logs', 'created_at', 'timestamp with time zone')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '458: these columns are missing or not as read on 24 Oct 2026: %', v; end if;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('correct_invoice', 'preview_invoice_correction', 'settle_waiting_special_docs_on_refund',
                       'create_special_docs_for_invoice', 'reopen_invoice', 'fulfil_special_doc', 'invoice_rental_correction_check',
                       'invoice_rentals_follow_lines', 'rental_end_on_refund', 'rentals_follow_refund')
     and p.oid::regprocedure::text <> all (c_sigs || c_new);
  if v is not null then raise exception '458: another function takes the name of one this changes: %', v; end if;

  -- Each new function: its text is the tested one; not there yet (made), or
  -- this version (left alone).
  for k in 1 .. cardinality(c_new) loop
    if md5(c_new_def[k]) <> c_new_after[k] then
      raise exception '458: the text of public.% is not the tested one (md5 %)', c_new[k], md5(c_new_def[k]); end if;
    if to_regprocedure('public.' || c_new[k]) is null then
      v_make[k] := true;
    elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_new[k]))) <> c_new_after[k] then
      raise exception '458: public.% is there but not this version (md5 %). Nothing was changed.',
        c_new[k], md5(pg_get_functiondef(to_regprocedure('public.' || c_new[k])));
    end if;
  end loop;

  -- Each patched function: its BEFORE (patched; each anchor found once; the
  -- text built has its AFTER md5) or its AFTER (left alone).
  for k in 1 .. cardinality(c_sigs) loop
    if to_regprocedure('public.' || c_sigs[k]) is null then raise exception '458: public.% is missing', c_sigs[k]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sigs[k]));
    -- its grants, to compare after (as sets: production lists them in
    -- another order than a local copy does)
    v_acls[k] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                    from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[k]));
    if md5(d) = c_after[k] then
      raise notice '458: public.% is already this version; left alone', c_sigs[k];
      continue;
    end if;
    if md5(d) <> c_before[k] then
      raise exception '458: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sigs[k], md5(d); end if;
    for i in 1 .. cardinality(c_anchor) loop
      continue when c_fn[i] <> k;
      n := (length(d) - length(replace(d, c_anchor[i], ''))) / length(c_anchor[i]);
      if n <> 1 then raise exception '458: anchor % of public.% was found % times, not once', i, c_sigs[k], n; end if;
      d := replace(d, c_anchor[i], c_patch[i]);
    end loop;
    if md5(d) <> c_after[k] then
      raise exception '458: the text built for public.% is not the tested one (md5 %)', c_sigs[k], md5(d); end if;
    v_texts[k] := d;
  end loop;

  -- ── 2. Install: the new functions first (the patched ones call them) ────
  for k in 1 .. cardinality(c_new) loop
    if v_make[k] then
      execute c_new_def[k];
      execute format('revoke all on function public.%s from public, anon, authenticated', c_new[k]);
      execute format('grant execute on function public.%s to service_role', c_new[k]);
    else
      raise notice '458: public.% is already this version; left alone', c_new[k];
    end if;
  end loop;
  for k in 1 .. cardinality(c_sigs) loop
    if v_texts[k] is not null then execute v_texts[k]; end if;
  end loop;

  -- ── 3. Checks after installing ──────────────────────────────────────────
  for k in 1 .. cardinality(c_new) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_new[k]))) <> c_new_after[k] then
      raise exception '458: public.% was installed with an md5 other than the tested one', c_new[k]; end if;
    if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new[k]))
       is distinct from (select array_agg(x::text order by x::text) from unnest(c_internal_acl::aclitem[]) x)
       or has_function_privilege('anon', 'public.' || c_new[k], 'execute')
       or has_function_privilege('authenticated', 'public.' || c_new[k], 'execute')
       or not has_function_privilege('service_role', 'public.' || c_new[k], 'execute') then
      raise exception '458: public.% is not the server''s alone', c_new[k]; end if;
  end loop;
  for k in 1 .. cardinality(c_sigs) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[k]))) <> c_after[k] then
      raise exception '458: public.% was installed with an md5 other than the tested one', c_sigs[k]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[k])) is distinct from v_acls[k]
       or has_function_privilege('anon', 'public.' || c_sigs[k], 'execute')
       or not has_function_privilege('service_role', 'public.' || c_sigs[k], 'execute') then
      raise exception '458: the grants of public.% changed', c_sigs[k]; end if;
  end loop;
  -- correct_invoice, preview_invoice_correction, reopen_invoice and
  -- fulfil_special_doc: signed-in staff may call them; the two internals
  -- patched: never.
  if not has_function_privilege('authenticated', 'public.' || c_sigs[1], 'execute')
     or not has_function_privilege('authenticated', 'public.' || c_sigs[2], 'execute')
     or not has_function_privilege('authenticated', 'public.' || c_sigs[5], 'execute')
     or not has_function_privilege('authenticated', 'public.' || c_sigs[6], 'execute')
     or has_function_privilege('authenticated', 'public.' || c_sigs[3], 'execute')
     or has_function_privilege('authenticated', 'public.' || c_sigs[4], 'execute') then
    raise exception '458: who may call the patched functions is not as before'; end if;
  -- Their access checks still come first.
  d := pg_get_functiondef(to_regprocedure('public.' || c_sigs[1]));
  if position(E'\nbegin\n select * into i from public.invoices where id=p_invoice_id for update;\n'
              || E' if not found or i.deleted_at is not null then raise exception ''Invoice not found''; end if;\n'
              || E' if not public.user_has_store_access(i.store_id) then raise exception ''No access to this invoice''; end if;\n' in d) = 0 then
    raise exception '458: public.% no longer checks store access first', c_sigs[1]; end if;
  d := pg_get_functiondef(to_regprocedure('public.' || c_sigs[2]));
  if position(E'\nbegin\n  select * into i from public.invoices where id = p_invoice_id;\n'
              || E'  if not found then raise exception ''Invoice not found''; end if;\n'
              || E'  if not public.user_has_store_access(i.store_id) then\n' in d) = 0 then
    raise exception '458: public.% no longer checks store access first', c_sigs[2]; end if;
  d := pg_get_functiondef(to_regprocedure('public.' || c_sigs[5]));
  if position(E'\nbegin\n if not public.is_owner_or_manager() then raise exception ''Only an Owner or Manager can reopen invoices''; end if;\n' in d) = 0 then
    raise exception '458: public.% no longer checks for an Owner or Manager first', c_sigs[5]; end if;
  d := pg_get_functiondef(to_regprocedure('public.' || c_sigs[6]));
  if position(E'\nbegin\n  if not public.is_owner_or_manager() then\n'
              || E'    raise exception ''Only an Owner or Manager can choose where stock is released from''; end if;\n' in d) = 0 then
    raise exception '458: public.% no longer checks for an Owner or Manager first', c_sigs[6]; end if;

  -- ── 4. Self-test, in a block that is always undone ─────────────────────
  -- Made-up records only ("458 check", @example.com, fictional ACMA phones
  -- no customer uses); it ends by raising P0458, which undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select y.x from (select '+6125550' || lpad(g::text, 4, '0') as x from generate_series(4580, 4619) g) y
                       where public.normalize_customer_phone(y.x) = y.x
                         and not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = y.x)
                       order by y.x limit 2);
    if coalesce(cardinality(t_phones), 0) < 2 then raise exception '458: the self-test found no two unused fictional phones'; end if;
    -- The shared settings row (commission rates) production has; a bare local
    -- copy may lack it.
    insert into public.app_settings default values on conflict do nothing;
    insert into auth.users (id, email) values (gen_random_uuid(), '458-check-' || t_sfx || '@example.com') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '458 check', '458-check-' || t_sfx || '@example.com', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('458 check A ' || t_sfx, '458A-' || t_sfx, 'SG') returning id into t_sa;
    insert into public.stores (name, code, country_code) values ('458 check B ' || t_sfx, '458B-' || t_sfx, 'SG') returning id into t_sb;
    insert into public.warehouses (name, code) values ('458 check ' || t_sfx, '458W-' || t_sfx) returning id into t_wh;
    insert into public.payment_methods (name, is_active) values ('458 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.customers (full_name, phone) values ('458 Check Customer A ' || t_sfx, t_phones[1]) returning id into t_ca;
    insert into public.customers (full_name, phone) values ('458 Check Customer B ' || t_sfx, t_phones[2]) returning id into t_cb;
    insert into public.products (name, sku, product_type) values ('458 check machine ' || t_sfx, '458M-' || t_sfx, 'own') returning id into t_prod;
    insert into public.warehouse_inventory (warehouse_id, product_id, current_qty) values (t_wh, t_prod, 5);
    t_sp := public.upsert_special_product_from_product(null, t_prod, 300, 30, null, 500, null, 0);

    -- A paid two-day rental, waiting, corrected to 2 machines x 3 days at
    -- Store B for Customer B: the rental follows.
    t_inv := public.create_invoice(t_sa, t_ca, null, jsonb_build_array(jsonb_build_object('kind', 'rental',
      'special_product_id', t_sp, 'quantity', 1, 'rental_rate_type', 'day', 'rental_periods', 2)));
    perform public.pay_invoice(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)));
    select id into t_line from public.invoice_items where invoice_id = t_inv;
    select id into t_r from public.rentals where invoice_id = t_inv;
    if t_r is null or (select status::text from public.rentals where id = t_r) <> 'awaiting_fulfilment' then
      raise exception '458: the self-test''s paid rental is not waiting for a warehouse'; end if;
    t_res := public.correct_invoice(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', t_line, 'kind', 'rental',
        'special_product_id', t_sp, 'quantity', 2, 'rental_rate_type', 'day', 'rental_periods', 3)),
      jsonb_build_object('customer_id', t_cb, 'store_id', t_sb), '458 check: two machines, three days', gen_random_uuid());
    if (select (quantity, periods, rental_fee, expected_return_date - start_date, customer_id, store_id)
          is distinct from (2, 3, 180::numeric, 3, t_cb, t_sb) from public.rentals where id = t_r)
       or jsonb_array_length(coalesce(t_res->'rentals', '[]'::jsonb)) <> 1 then
      raise exception '458: the waiting rental did not follow its corrected line, customer and store (%; %)',
        (select to_jsonb(x) - 'notes' from public.rentals x where id = t_r), t_res->'rentals'; end if;

    -- Owing the S$120 difference, it waits for the payment; paid, it is
    -- released from the warehouse, extended to five days; three machines
    -- refused.
    t_msg := null;
    begin
      perform public.fulfil_special_doc('rental', t_r, t_wh, 'warehouse');
    exception when others then t_msg := sqlerrm;
    end;
    if t_msg is distinct from (select rental_no from public.rentals where id = t_r) || ' cannot be released yet: its invoice '
         || (select invoice_no from public.invoices where id = t_inv) || ' has S$120.00 owing. Take the payment first, then release it.' then
      raise exception '458: a rental whose invoice owes money was not held for the payment (%)', coalesce(t_msg, 'released'); end if;
    perform public.pay_invoice(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 120)));
    perform public.fulfil_special_doc('rental', t_r, t_wh, 'warehouse');
    t_wq := (select current_qty from public.warehouse_inventory where warehouse_id = t_wh and product_id = t_prod);
    perform public.correct_invoice(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', t_line, 'kind', 'rental',
        'special_product_id', t_sp, 'quantity', 2, 'rental_rate_type', 'day', 'rental_periods', 5)),
      '{}'::jsonb, '458 check: extended', gen_random_uuid());
    if (select (status::text, quantity, periods, rental_fee, expected_return_date - start_date)
          is distinct from ('active'::text, 2, 5, 300::numeric, 5) from public.rentals where id = t_r) then
      raise exception '458: the rental out was not extended (%)', (select to_jsonb(x) - 'notes' from public.rentals x where id = t_r); end if;
    t_msg := null;
    begin
      perform public.correct_invoice(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', t_line, 'kind', 'rental',
          'special_product_id', t_sp, 'quantity', 3, 'rental_rate_type', 'day', 'rental_periods', 5)),
        '{}'::jsonb, '458 check: three machines', gen_random_uuid());
    exception when others then t_msg := sqlerrm;
    end;
    if t_msg is null or t_msg not like (select rental_no from public.rentals where id = t_r) || ' is out with the customer: Return it first.%' then
      raise exception '458: a change of quantity of a rental out was not refused in words (%)', coalesce(t_msg, 'saved'); end if;

    -- Paid up, its line refunded in full: the rental ends, still with the
    -- customer, to be received; no stock moves.
    perform public.pay_invoice(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 120)));
    perform public.refund_invoice_recorded(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', t_line, 'amount', 300)),
      (select jsonb_agg(jsonb_build_object('payment_id', p.id, 'amount', p.amount) order by p.id)
         from public.invoice_payments p where p.invoice_id = t_inv),
      '[]'::jsonb, '458 check: refunded', gen_random_uuid());
    if (select status::text from public.rentals where id = t_r) <> 'cancelled' or not public.rental_awaiting_return(t_r)
       or jsonb_array_length(public.invoice_rentals_awaiting_return(t_inv)) <> 1
       or (select current_qty from public.warehouse_inventory where warehouse_id = t_wh and product_id = t_prod) <> t_wq then
      raise exception '458: the full refund did not end the rental out as Cancel does (%)',
        (select to_jsonb(x) - 'notes' from public.rentals x where id = t_r); end if;

    -- A one-month rental from 31 Jan with "Due back" blank: 28 Feb.
    t_inv := public.create_invoice(t_sa, t_ca, null, jsonb_build_array(jsonb_build_object('kind', 'rental',
      'special_product_id', t_sp, 'quantity', 1, 'rental_rate_type', 'month', 'rental_periods', 1,
      'rental_start_date', '2027-01-31')));
    perform public.pay_invoice(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 500)));
    t_due := (select expected_return_date from public.rentals where invoice_id = t_inv);
    if t_due is distinct from date '2027-02-28' then
      raise exception '458: a month''s rental from 31 Jan with "Due back" blank is due back % (expected 28 Feb)', t_due; end if;

    raise exception using errcode = 'P0458', message = '458: self-test done, undone';
  exception when sqlstate 'P0458' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
