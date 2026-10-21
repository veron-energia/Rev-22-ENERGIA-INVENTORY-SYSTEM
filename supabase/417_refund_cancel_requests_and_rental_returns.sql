-- 417_refund_cancel_requests_and_rental_returns.sql
--
-- WHAT WAS WRONG (audit of 9 Oct 2026, re-checked on production that day)
--
--   Refund / Cancel and its approvals (INVOICES-AFTER-M1, -M2, -14, -7,
--   -CREATE-14, -409-Q1, S12, and 363, which was never applied):
--   * A credit package whose qualification rewards were still outstanding
--     (INV-2026-0072 and INV-2026-0337, five unclaimed rewards each) showed no
--     warning and could be raised and confirmed; approval then failed inside
--     the refund ("qualification reward entitlements that are still
--     outstanding") and left the request waiting.
--   * One request ID served any request: an Owner or Manager whose approval
--     failed, who then chose another action in the same window, had the
--     first request replayed and carried out.
--   * A rejection could be confirmed with the requester's own words as the
--     reason, or none (Approvals), and nothing on the invoice said a request
--     was waiting or had been rejected.
--   * Two therapy lines needing the same override took the first amount
--     typed for both (the refund engine matched overrides by code only).
--   * A rental still with the customer when its invoice was cancelled could
--     be received into a warehouse only, though both rentals out today
--     (RNT-2026-0004, due 12 Oct; RNT-2026-0006, due 22 Oct) came from a
--     store; and once the invoice was cancelled no screen reached it.
--   * delete_invoice deleted any invoice with no payment and no goods out:
--     completed FOC (a therapy FOC kept its session), the request statuses,
--     with no reason kept.
--   * A cancelled sale the customer had already used part of showed all the
--     money held as owed back, and refused to record any refund of it.
--   * 363 (a refund or cancellation of a promotion closes the therapy it
--     granted) was written on 26 Sep and never applied; its guards no longer
--     match production since 409 and 410. UTP-0000006 (INV-2026-0160) and
--     UTP-0000012 (INV-2026-0304) are open therapy on refunded sales.
--   * Cancelling an invoice paid through Record Payment gave limited voucher
--     stock back twice: once with each voucher the customer still held and
--     again for the invoice's voucher movements (2 sold: 10, 8 when paid,
--     12 when cancelled, where it should be 10; a used voucher came back
--     too). Found in B02's review of production's version. No invoice in
--     production has hit it (9 Oct 2026: no invoice voucher movement has
--     ever been given back, and none is open with a held voucher).
--   * Reopening a cancelled free (FOC) invoice that gave limited vouchers
--     took their stock twice. Confirm FOC takes that stock with no voucher
--     movement row, so the reopening took every unit again
--     (deduct_invoice_stock), and then took again each unit it gave back to
--     the customer (invoice_reopen_vouchers_settled). 2 vouchers given:
--     10, 8 at Confirm FOC, 10 when cancelled, 6 when reopened (should be 8).
--     The same when the FOC was taken off first (416), then the invoice was
--     cancelled, reopened and paid: 6, should be 8. Both happen once 416 has
--     Confirm FOC give the vouchers (today it gives none); 416's own suite
--     measures both as B03's. No invoice in production has hit it (9 Oct
--     2026: 0 completed FOC invoices with a voucher, 0 voucher movements, 0
--     vouchers given again on a reopening).
--   * Found while fixing that (older than 416, in production's
--     reopen_invoice): an invoice reopened, cancelled again before it was
--     settled and reopened again queued its vouchers twice, so paying it
--     gave both lots and took stock for both (a paid sale, half its money
--     paid back after cancelling: 3 vouchers instead of 2, stock 7 instead
--     of 8; after the FOC was taken off (416): 4 vouchers instead of 2).
--     And when an Owner had moved a completed FOC invoice's vouchers to
--     another store, its reopening took the stock at both stores. No
--     invoice in production has hit either (10 Oct 2026: no voucher is
--     limited, 0 vouchers queued by a reopening, 0 vouchers moved by a
--     benefit transfer; the one transfer moved credit).
--   * Found in the review of this migration (10 Oct 2026), when vouchers
--     sit at another store than the invoice's movement rows. A cancellation
--     matched its rows to vouchers store by store. A paid sale corrected to
--     another customer and store (the vouchers move, no stock does) gave 2
--     back twice when cancelled: 22 in the two stores, not 20 (older than
--     417, but 417's single take made each cancel and reopen leave 2 more).
--     A completed FOC whose vouchers were moved to another store, then
--     cancelled, reopened, its FOC taken off (416) and paid, gave 2
--     vouchers and took no stock (20, not 18), and 22 when cancelled again;
--     the same move with the FOC taken off and then paid gave 22 when
--     cancelled. With 416, the FOC taken off with the quantity raised from
--     2 to 3, then paid and cancelled, gave 1 back too many (B02's hand-over:
--     416 gives the third voucher as a replacement, which the count left
--     out). No invoice in production has hit any of them (10 Oct 2026: no
--     voucher is limited, 0 voucher movements, 0 vouchers moved by a
--     benefit transfer).
--   * Found in the second review (10 Oct 2026), in this file as it was
--     then. A cancellation counted the units issued up to what the lines
--     hold, so a paid voucher line lowered after payment (2 sold, then 1;
--     the 2 vouchers stay with the customer) gave 1 more back with each
--     cancel and reopen (11, 12, 13, where it should be 10 each time), and
--     one raised and paid (2, then 3) kept 1 out from the second cancel on
--     (9, not 10). A correction that moves a paid invoice to another
--     customer and store (move_invoice_benefits_to_customer, older than
--     417) moved the vouchers and not their stock, so the first store
--     ended 2 short and the other 2 over. A reopening whose vouchers sit at
--     two stores recorded all its units at one of them, picked by its id.
--     No invoice in production has hit any of them (10 Oct 2026: no
--     voucher is limited, 0 voucher movements; the 2 corrections that
--     moved vouchers with an invoice moved no limited ones).
--
-- THE RULES (the Owner, 9 Oct 2026)
--
--   1. Q3 = A: 363's three rules: a part refund by amount (the Finance
--      panel) leaves a promotion's therapy; a guided part refund of N of M
--      copies closes ceil(units x N / M), unused first, and all of it when it
--      takes what is left of the line; a plain cancellation is refused once
--      that therapy has started (by its dates too, 410). Unused units close
--      with their line; a used one only on the Owner or Manager's
--      'therapy_activated' override with an amount.
--   2. Q2 = A: when cancelling a sale the customer already used part of,
--      the Owner or Manager states how much is owed back. That amount is the
--      refund due and is recorded once it is paid; the rest is kept for what
--      was used.
--   3. Q4 = A: any member of staff of the invoice's store may delete a draft
--      or unpaid invoice, giving a short reason that is kept in the history.
--      Anything else is undone with Refund / Cancel.
--   4. Rewards: those not claimed yet are withdrawn with the refund or
--      cancellation, those already activated or claimed keep their history
--      (the rule resolve_invoice_credit_rewards already has). Never a
--      blocker: staff can still raise the request.
--   5. Reopening a completed FOC invoice that gave limited vouchers takes
--      their stock once, not twice, like any reopening (the Owner, 9 Oct
--      2026: "fix it properly"). So does a reopening after the FOC was
--      taken off, a second reopening before the first was settled, and one
--      whose vouchers were moved to another store; each voucher is given
--      again once.
--
-- WHAT THIS DOES
--
--   * invoices.cancel_refund_owed (new column, numeric(12,2), >= 0): on a
--     cancelled invoice whose customer had part of it, what is still owed
--     back as stated when cancelling, less refunds recorded since. Null: not
--     stated (all the money held is owed back).
--   * close_invoice_therapy_units(...) (new; internal, the service role's
--     alone, 339): 363's, unchanged in substance: closes the therapy units
--     of one invoice line (or those no line holds) by rule 1, all or none,
--     locking the units and their voucher allowances first.
--   * invoice_action_plan (patched; grants kept): 363's therapy units per
--     line (their share on a part refund, unused first), one stock entry per
--     movement, the units no line holds (effects.therapy_closed and
--     therapy_left, detached_therapy); and two non-blocking overrides for a
--     credit package's outstanding rewards on the lines the action covers:
--     reward_withdrawal (with the entitlement numbers withdrawn) and, when
--     any is already activated or claimed, reward_consumed_kept
--     (effects.rewards); and refund_owed (rule 2) on a cancellation that
--     keeps something the customer used while money is held. The plan hash
--     changes only where these add something.
--   * resolve_invoice_action_v2 (patched; grants kept): a rejection needs the
--     approver's reason; overrides that name a line (invoice_item_id) are
--     matched to that line first, then by code; the rewards are settled by
--     resolve_invoice_credit_rewards in the same step, before any money
--     moves, so a refund that fails withdraws nothing; the therapy the
--     reviewed plan lists is closed first (363), and started therapy sold on
--     its own line ends with a cancellation on its override; on a
--     cancellation with something used it records the amount owed back (the
--     'refund_owed' override's amount; without one, the reviewed refund with
--     any amounts stated; S$0 when the refund is recorded at once), refusing
--     less than S$0 or more than is held, and audits it.
--   * request_invoice_action_v2 (patched; grants kept): a request ID used for
--     another invoice, another action or other lines is refused, not replayed.
--   * refund_invoice_recorded (patched; grants kept): 363's locks and rules
--     (a promotion line refunded in full closes its therapy, a used unit only
--     on the override; unused therapy no line holds closes when the invoice
--     closes); on a cancelled invoice with an amount owed back stated, no
--     more than it is recorded, and what is recorded comes off it; one with
--     something used and nothing stated is still refused.
--   * cancel_invoice_recorded (patched; grants kept): 363's locks and rule C
--     on top of 410's date rule: a direct cancellation is refused while
--     therapy on a line has been used (started, ended, by its dates, or
--     vouchers collected); unused units close as before. An amount owed back
--     from an earlier cancellation is cleared. Limited voucher stock goes
--     back once: the units issued to the customer come back with their
--     vouchers (unused ones only), however their stock was taken (Record
--     Payment's movements, Confirm FOC, a credit package or bundle); the
--     invoice's voucher movements give back, and record, only what it took
--     and never issued, as a refund does, so a reopening takes again only
--     what it issues again. Both are counted by voucher, not by store, so a
--     voucher moved to another store is not counted twice. The units issued
--     are counted along each voucher's own chain: what each voucher the
--     invoice gave, gave again or moved (sale, promotion, reopening,
--     transfer) was granted, less what a later reopening gave again in its
--     place or a transfer moved on. So a voucher given again counts once,
--     and a voucher line lowered or raised on a paid invoice does not change
--     what comes back. What is left goes back at the stores its rows are at,
--     the invoice's first.
--   * move_invoice_benefits_to_customer (patched; grants kept: the service
--     role's alone): when a correction moves an invoice to another store,
--     the stock of each limited voucher that moves with it moves too: taken
--     at the new store (refused with 'Not enough voucher stock at the
--     destination store' if it holds too few) and given back at the old
--     one, as an Owner's move of one voucher (transfer_invoice_unused_
--     benefit) already does. The vouchers are locked first.
--   * invoice_financial_position (patched; grants kept): on such a cancelled
--     invoice the refund due is the amount owed back; refund_owed_stated and
--     kept_for_used say so.
--   * receive_returned_rental (replaced whole; grants kept; no new overload):
--     good, with no warehouse named, the rental goes back where it came from,
--     its store or its warehouse, as Return on the Special page does
--     (rental_put_back_stock); another active warehouse when named; damaged
--     and lost move no stock. Only a rental cancelled with its invoice while
--     it was out; once only, as before.
--   * invoice_rentals_awaiting_return (replaced whole; grants kept): adds each
--     rental's invoice line and where it came from.
--   * invoice_request_status(uuid) (new; staff of the invoice's store,
--     require_store_access first): the request waiting on an invoice, else
--     the last one: what, who, when, and a rejection's reason. Not the
--     requester's own reason, which only the requester and Managers read.
--   * delete_invoice(uuid, text) (new, replacing delete_invoice(uuid), which
--     is dropped; staff of the invoice's store, require_store_access first):
--     rule 3, with the payment and goods-out checks kept, write_audit_ex with
--     the reason and the store. A refusal names the status in words ('a
--     completed FOC invoice', 'part paid', 'waiting for a refund decision',
--     'waiting for a cancellation decision', 'paid', 'cancelled', 'refunded').
--   * invoice_voucher_stock_unrecorded(uuid, boolean) (new; internal, the
--     service role's alone): by limited voucher, on the invoice's voucher
--     and promotion lines, the units the customer still has from it
--     (wherever one was moved since) plus those a reopening gives again,
--     never more than it first gave, less what its voucher movement rows
--     record, counted by voucher as deduct_invoice_stock nets them. It is
--     split across the stores that hold those vouchers, by how many each
--     holds, where their stock was taken and is taken again, so each row
--     reopen_invoice writes sits where the stock moved. 416 does the same with its 'Taken at Confirm FOC'
--     rows (B02's file of 10 Oct): it counts them by voucher and writes them
--     at the stores that hold the vouchers, as they were before its save
--     moves any. For a paid invoice that is nothing: its rows record every
--     unit. Rule 5.
--   * reopen_invoice (patched; grants kept): it queues only the voucher
--     units no earlier reopening has queued and is still waiting to give.
--     It then records the units above as taken (a voucher movement row
--     each, no stock moved, the reason saying so). Then, as for a reopened
--     paid invoice, deduct_invoice_stock takes only what the invoice never
--     gave, and invoice_reopen_vouchers_settled takes the stock of the
--     vouchers it gives again, where they are given, when the invoice is
--     settled. Rule 5. A cancellation after that gives back only through
--     the vouchers (cancel_invoice_recorded, above), so every cycle takes
--     the stock once.
--   * invoice_reopen_preview_before_sessions (patched; grants kept): its
--     'stock to issue' leaves out the same units, and its voucher units to
--     give again count those still waiting, so the Finance panel shows what
--     the reopening will do.
--
-- NOT CHANGED
--
--   * resolve_invoice_credit_rewards, assert_invoice_credit_source_evidence,
--     cancelled_invoice_used_value, therapy_unit_consumed (410's dates),
--     rental_awaiting_return, rental_put_back_stock, return_rental_with_fee
--     and the rest relied on below.
--   * confirm_foc_invoice, correct_invoice and the trigger that gives a
--     settled invoice its vouchers (416 changes them; this does not),
--     deduct_invoice_stock, invoice_stock_to_deduct,
--     invoice_voucher_reopen_candidates and apply_reopened_invoice_vouchers.
--     A reopened paid invoice, and one that gave no vouchers, take stock as
--     before. A free invoice confirmed before 416 gave no vouchers, so its
--     cancellation gives nothing back and its reopening takes the stock
--     again; 416 goes before any FOC voucher is given (there is no such
--     invoice: 9 Oct 2026).
--   * A voucher line lowered on a paid invoice keeps its vouchers with the
--     customer (correct_invoice, as in production), and a reopening gives
--     all of them again; the stock follows the vouchers every time.
--     B02's fault with 416 (a voucher line raised or lowered while the
--     invoice stays FOC, then cancelled, reopened and cancelled again: 9 or
--     11 the second time) is fixed by this file's cancellation above: 10
--     both times (B02's sold-voucher-issuance.sql now prints PASS there).
--   * 416's rule for a voucher an Owner moved to another customer: 416 of
--     10 Oct (md5 f79dc285...) counts it as moved only while it is the
--     Owner's move ('invoice_benefit_transfer'). After a cancel and reopen
--     it is given again as 'invoice_reopen', so taking the FOC off takes it
--     back from the friend and the payment gives it to the buyer. Stock
--     stays right. B02 changes that in 416 (any voucher of the invoice
--     another customer holds counts as moved); cancel-voucher-stock-once.sql
--     case 12b prints a KNOWN FAULT notice until then. Whether the friend
--     keeps it is the Owner's to decide (416).
--   * Which roles may do what: Owners and Managers approve, refund, cancel
--     and receive; staff raise requests. The Approvals page's own reject
--     (B06) and the invoice page's banner, bin and delete reason (B16) are
--     the pages' part. The invoice page's Delete sends no reason today, and
--     this refuses a delete with none ("Give a short reason for deleting
--     this invoice"), so this goes in only with B16's delete reason (DEPLOY
--     ORDER, step 0).
--   * Existing data: nothing here changes a row. The nine legacy refunds
--     (scripts/repairs/legacy-refunds-backfill.sql), UTP-0000002/0006/0012
--     (scripts/therapy/repair-promotion-therapy-units.sql) and RENT-2026-0002
--     (scripts/repairs/rent-2026-0002-nothing-to-receive.sql) are one-off
--     repairs, run after this. INV-2026-0072 and INV-2026-0337 are not
--     pre-resolved: their rewards are settled only if a refund or
--     cancellation of them is approved.
--   * 363's file stays in the repository, marked never to apply.
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. It
--   refuses unless each function it changes is the production version read
--   on 9 Oct 2026 (BEFORE) or already this migration's (AFTER, left alone),
--   each new one is missing or already this migration's, every anchor is
--   found exactly once, every text built has its AFTER md5, every function
--   it relies on is at the version read that day, the trigger
--   invoice_reopen_vouchers_settled is the one read that day (it takes the
--   stock of the vouchers a reopening gives again), no other function shares
--   these names, and invoices.cancel_refund_owed is missing or already as
--   this makes it. A request waiting is reported (its revised effects are
--   shown to confirm again; there were none on 9 Oct 2026). Afterwards the
--   md5s, the grants (unchanged for the functions changed; the two new
--   internal ones the service role's alone; the two new client ones
--   signed-in staff and the service role) and the dropped overload are
--   checked by the catalogue. Then, inside a block that is always undone, a
--   made-up Owner and member of staff at a made-up store: a request shows on
--   its invoice without the requester's reason, a replay for another action
--   or another invoice is refused, a rejection needs a reason and shows, a
--   delete needs a reason and keeps it, a completed FOC is refused, the 2
--   made-up vouchers the completed FOC gave are found missing from its
--   movement rows and no longer once a row records them, and a login that
--   is not staff is refused. Nothing is printed and no row remains.
--
-- BEFORE (production, 9 Oct 2026; md5 of pg_get_functiondef, search_path public;
-- every one read there again after 414, 421 and 428 went live, and on 10 Oct
-- 2026 after 415 went live: unchanged):
--   changed
--   invoice_action_plan(uuid,text,jsonb)                         1c8fa5626062d09ba0cc1a4dca9d0e93
--   resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)  87c838d9ef9e23f8e2cc9ef8c60b0787
--   request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)    765a7a0629df4b591ca6718a6c171224
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)    b0a99345c0f2e635391ac1c251634d95
--   cancel_invoice_recorded(uuid,text,uuid)                      e8ce9cc4f62896bff144893fdc42225d  (410's AFTER)
--   invoice_financial_position(uuid)                             8751b7a8749452b0513e475b7fdb05ce
--   receive_returned_rental(uuid,uuid,text,text,uuid)            a58778ccc5defa49d6fefe7a96b7b805
--   invoice_rentals_awaiting_return(uuid)                        d2fe77eb5b2324e27f460e217f678e78
--   delete_invoice(uuid)                                         5b09daf60b404444618197c478842d4a  (dropped)
--   reopen_invoice(uuid,text,uuid)                               64cdf1f76339f7b9c0676b3411e84a83
--   invoice_reopen_preview_before_sessions(uuid)                 17d22eaa8e84a73ad62fd18e0da93ebd
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)       33bc04a081f0f199fca2cbb3d3e1ed3e  (read 10 Oct 2026)
--   new (missing): close_invoice_therapy_units(uuid,uuid,uuid[],jsonb,numeric,text,uuid,text),
--                  invoice_request_status(uuid), delete_invoice(uuid,text),
--                  invoice_voucher_stock_unrecorded(uuid,boolean)
--   relied on, not changed
--   resolve_invoice_credit_rewards(uuid,text,uuid,boolean,uuid)  828a4b535604aef1314f55453d67f6e2
--   assert_invoice_credit_source_evidence(uuid,uuid)             64059b05526f32239ce1e60c6de39508
--   credit_package_reward_group(uuid)                            7f8ac1b8bdc369110be03c8e9d260942
--   cancelled_invoice_used_value(uuid)                           70f684f1a8f0a4f42774394062e4df19
--   invoice_net_received(uuid)                                   f256bea69b7defa38a950753bbc248da
--   therapy_unit_consumed(uuid)                                  9ea1884a2357c1af7f0e9c82a85c73e3  (410's AFTER)
--   purchased_therapy_status_on(text,date,date,date,date)        991ec75f0349f61ef1a2f3682fb142b1
--   revoke_therapy_unit_benefit(uuid,text)                       5b186266e1098bea30a493796eb1fc59
--   invoice_line_stock_products(uuid)                            5ed49163d183fa5ec05673a1bb85e863
--   rental_awaiting_return(uuid)                                 88ba77463d293bc77fba5e5cad3d3210
--   rental_put_back_stock(uuid)                                  8ca55272c76c62b295d5001b0943e85a
--   trg_rental_stock_back()                                      a75c600cd86edc5b43fb464a5bfe34a8
--   invoice_goods_out(uuid)                                      15ffed0ff0d5d9cc5685af8e834302ae
--   require_active_staff(text[])                                 877b3aa74cea559881979bb161c450e2
--   require_store_access(uuid)                                   f9332fd2f0092337d64501d8a647c23f
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)  c705c733e213a27f0dc32d54322cc855
--   deduct_invoice_stock(uuid,text)                              32183fe9e7c15ed0b11307c48289831a
--   invoice_stock_to_deduct(uuid)                                6356494ccb8545d46c56b788f8f85f54
--   apply_reopened_invoice_vouchers()                            71d50be41b73decceb0b20f8597dd4fa
--   invoice_voucher_reopen_candidates(uuid)                      20405a96c8780eac6425a5dae59c29e1
--   public function fingerprint (reference only, not guarded):
--     after 413 (the test copy b03)                              675ac22c631079b58f06813d0d463fa3
--     production on 10 Oct 2026, after 414, 421, 428 and 415
--     (20261010010418; 1237 functions; b03 with those four
--     applied gives the same)                                     566e76f702c89c9846968e6fdd89cc45
-- AFTER (for later guards):
--   invoice_action_plan(uuid,text,jsonb)                         e117890fac11ea11435b691ca4787dec
--   resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)  201f08ebf14a64cd88d411a7cfb4c9c4
--   request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)    4360d74462ed1fc950b6bd8b5157b3ae
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)    e6f6c3cbf1bda3574d748bde2db5a759
--   cancel_invoice_recorded(uuid,text,uuid)                      de52d9dbaef8ab15163bef35cb9d733d
--   invoice_financial_position(uuid)                             ba7eccbfeff217c8b1969b0e55a010ca
--   receive_returned_rental(uuid,uuid,text,text,uuid)            362b0175b60e12c97e427b5180e01960
--   invoice_rentals_awaiting_return(uuid)                        07621bd5ba0b8be5cf69460ac4212017
--   close_invoice_therapy_units(uuid,uuid,uuid[],jsonb,numeric,text,uuid,text)  5d79476632fe31145a903d0f267cfafc
--   invoice_request_status(uuid)                                 3930f9e6de6a53de9bb78302e7fc37e2
--   delete_invoice(uuid,text)                                    530b8217e94c9bbb0765c47da2d8d40e
--   reopen_invoice(uuid,text,uuid)                               c9fcab7adfccdaeba1eb8dee4134ba47
--   invoice_reopen_preview_before_sessions(uuid)                 4723b49b3f27c17254c2987c4bebc17b
--   invoice_voucher_stock_unrecorded(uuid,boolean)               91c8f0fa69ef6337f323b7ac467a8c2b
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)       2c01c460d3af8edd3ad86332aa286ed8
--   public function fingerprint (reference only, worked out on b03, not read
--   on production):
--     after 413 plus this                                        0a6f8ed75ada3a919e9391cacb0bc742
--     after 413 plus 414, 421, 428 and this                      2f740617b19c60f99af8721c3233f05a
--     after 413 plus 414, 421, 428, 415 and this, which is what
--     production should read after this if nothing else goes
--     first (1240 functions)                                      2b0656990c65397be40043f1a092b06c
--     the same plus 416 (B02's file of 10 Oct, md5 f79dc285...),
--     in either order (1240 functions)                            5d4baac3cc4958040b28c528088c5684
--
-- DEPLOY ORDER
--   0. GATE: only in the same release as the invoice page's delete reason
--      (B16: src/pages/InvoicesPage.tsx asks for a short reason and sends
--      p_reason). On the code to be released, from the repository's root:
--        node scripts/invoice-actions/release-gate-417.mjs
--      must print PASS. While it fails (today it names InvoicesPage.tsx),
--      hold this back: once it is in, the page's Delete is refused for
--      every invoice. Keeping the one-argument delete_invoice is not a way
--      round it: the Owner wants a reason (Q4).
--   1. Check no invoice request is waiting (the plan hash changes where the
--      rewards, therapy units or the amount owed back add something):
--        select count(*) from approval_requests
--         where request_type in ('invoice_cancel','invoice_refund') and status = 'pending';
--   2. This migration.
--   3. The front end, at once: the guided Refund / Cancel and the Finance
--      panel (this batch), the invoice page's delete reason, banner and bin
--      (B16, step 0) and the Approvals page's reject reason (B06). Until
--      Approvals asks for a reason, rejecting there without one is refused
--      with a message asking for one.
--   4. The one-off repairs, each once: scripts/therapy/repair-promotion-
--      therapy-units.sql (its dry run first: repair-promotion-therapy-units-
--      dry-run.sql), scripts/repairs/rent-2026-0002-nothing-to-receive.sql
--      and scripts/repairs/legacy-refunds-backfill.sql (Q1; its dry run
--      first: legacy-refunds-backfill-dry-run.sql, read only, which must
--      show 11 payments, S$8,054.47 and ok on every row: it did on
--      production on 10 Oct 2026).
--   5. The legacy refunds backfill (Q1) runs BEFORE the INV-2026-0174
--      clean-up (Q14, batch B08: scripts/therapy/repair-invoice-0174-test.sql
--      STEP 2), and so before 422's Therapy page, which that clean-up must
--      precede; and in any case before the early-November Xero import.
--      INV-2026-0174 is one of the nine: its refund is written in first,
--      then the clean-up withdraws what that sale issued.
--   416 and this may go in either order: neither changes or relies on a
--   function the other changes (416's correct_invoice calls
--   move_invoice_benefits_to_customer, which this changes and 416 does not
--   guard; tested both ways with 416's file of 10 Oct, md5 f79dc285...: the
--   same functions after).
--   Rule 5 matters once 416 has Confirm FOC give the vouchers; 416 goes
--   before any FOC voucher is given (its own deadline: the 19-20 Oct event).
--   The hand-over to B02 is done: 416 now counts its 'Taken at Confirm FOC'
--   rows by voucher, as everything here counts them. So a completed FOC
--   cancelled, reopened, its vouchers then moved to another store, the FOC
--   taken off, paid and cancelled ends at 20 in the two stores, not 22.
--   cancel-voucher-stock-once.sql case 14 now runs and passes, with 416
--   before or after this. One path waits on B02's change to 416 (NOT
--   CHANGED; case 12b).
--   415, live since 10 Oct 2026, changes none of the functions here or
--   relied on.
--
-- Test: scripts/invoice-actions/tests/requests-delete-and-refund-owed.sql,
-- scripts/invoice-actions/tests/cancel-voucher-stock-once.sql (rule 5 in
-- cases 6 to 12, vouchers at another store in 12b to 14 and 16, 416's
-- changed quantities in 15 and 15b, lines lowered or raised after payment
-- in 17 to 21; run it with 416 installed in the same transaction, before
-- or after this, so a completed FOC invoice gives its vouchers as it will:
-- 26 cases, all pass but 12b, which prints KNOWN FAULT until B02's change
-- to 416; without 416, 18 pass and 8 are skipped),
-- scripts/invoice-actions/tests/promotion-therapy.sql (363's suite, run on
-- 417), scripts/invoices/tests/reward-withdrawal.sql,
-- scripts/rentals/tests/receive-to-source.sql, the repairs' tests in
-- scripts/repairs/tests/ and scripts/therapy/tests/repair-promotion-therapy-
-- units.sql, scripts/permissions/tests/function-grants.sql and
-- staff-only-functions.sql (after this, in the same transaction), and the
-- page tests scripts/invoice-actions/tests/guided-interaction.test.mjs,
-- refund-due-panel.test.mjs and scripts/rentals/tests/receive-after-cancel.test.mjs,
-- and the release gate scripts/invoice-actions/release-gate-417.mjs.
-- Earlier suites amended for this: scripts/therapy/tests/status-refresh.sql
-- (does not re-run 410 once this is in; it knows this by the function it
-- adds), scripts/xero/tests/sales-events.sql
-- (also accepts this migration's AFTER md5s), the one-argument delete_invoice calls
-- in scripts/invoices/tests/part-paid-handover.sql and
-- scripts/web-orders/tests/door-orders.sql (now give a reason).
-- Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ New functions, whole ═══════════════════════════════════════════════════

  -- 363, rebuilt here: closes the therapy units of one invoice line by the
  -- rule already set for therapy sold on its own line.
  c_close_def constant text := $def$CREATE OR REPLACE FUNCTION public.close_invoice_therapy_units(p_invoice_id uuid, p_invoice_item_id uuid, p_unit_ids uuid[], p_override jsonb, p_amount numeric, p_reason text, p_request_id uuid, p_context text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 417 (363 rebuilt): the units of one line of the invoice, or (p_invoice_item_id
-- null) the units no line holds. p_unit_ids null = every open one. p_override
-- is the Owner or Manager's 'therapy_activated' override; p_amount what the
-- line refunds under it (recorded with the termination). Closed units are
-- skipped. All or none: if one used unit lacks the override, nothing closes.
declare e public.purchased_therapy_entitlements%rowtype; v_store uuid; v_used text;
        v_refunded jsonb := '[]'; v_ended jsonb := '[]';
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can close therapy with its invoice line'; end if;
  select store_id into v_store from public.invoices where id = p_invoice_id;
  if not found or not public.user_has_store_access(v_store) then
    raise exception 'Invoice not accessible'; end if;
  if p_invoice_item_id is not null and not exists (select 1 from public.invoice_items
                                                    where id = p_invoice_item_id and invoice_id = p_invoice_id) then
    raise exception 'Invoice line not found'; end if;
  if exists (select 1 from unnest(coalesce(p_unit_ids, '{}'::uuid[])) u
              where not exists (select 1 from public.purchased_therapy_entitlements x
                                 where x.id = u and x.invoice_id = p_invoice_id
                                   and x.invoice_item_id is not distinct from p_invoice_item_id)) then
    raise exception 'A therapy unit to close does not belong to this invoice line'; end if;

  -- Lock the units and their voucher allowances first, so nothing is started
  -- and no voucher is collected between the check and the close.
  perform 1 from public.purchased_therapy_entitlements x
    where x.invoice_id = p_invoice_id and x.invoice_item_id is not distinct from p_invoice_item_id
      and (p_unit_ids is null or x.id = any(p_unit_ids)) and x.status not in ('cancelled','refunded')
    order by x.id for update;
  perform 1 from public.therapy_entitlements te
    where te.id in (select x.voucher_entitlement_id from public.purchased_therapy_entitlements x
                     where x.invoice_id = p_invoice_id and x.invoice_item_id is not distinct from p_invoice_item_id
                       and (p_unit_ids is null or x.id = any(p_unit_ids)) and x.status not in ('cancelled','refunded'))
    order by te.id for update;

  select string_agg(x.entitlement_no, ', ' order by x.entitlement_no) into v_used
    from public.purchased_therapy_entitlements x
   where x.invoice_id = p_invoice_id and x.invoice_item_id is not distinct from p_invoice_item_id
     and (p_unit_ids is null or x.id = any(p_unit_ids)) and x.status not in ('cancelled','refunded')
     and public.therapy_unit_consumed(x.id);
  if v_used is not null then
    if coalesce(p_override->>'code','') <> 'therapy_activated'
       or nullif(trim(coalesce(p_override->>'reason','')),'') is null then
      raise exception 'Therapy from this line has been started or has ended, or vouchers from it were collected (%). It ends only on an Owner or Manager''s authorization with an amount: use Refund / Cancel on the invoice.', v_used; end if;
    if (p_override->>'amount') is null or (p_override->>'amount')::numeric < 0 then
      raise exception 'No valuation exists for therapy that has been used (%). An Owner or Manager must state the refund amount with a reason.', v_used; end if;
  end if;

  for e in select * from public.purchased_therapy_entitlements x
            where x.invoice_id = p_invoice_id and x.invoice_item_id is not distinct from p_invoice_item_id
              and (p_unit_ids is null or x.id = any(p_unit_ids)) and x.status not in ('cancelled','refunded')
            order by x.unit_index nulls last, x.entitlement_no
  loop
    if public.therapy_unit_consumed(e.id) then
      update public.purchased_therapy_entitlements
         set status = 'refunded', updated_by = auth.uid(), updated_at = now() where id = e.id;
      perform public.write_audit_ex('purchased_therapy_entitlements', e.id, 'authorized_termination',
        jsonb_build_object('status', e.status, 'activation_date', e.activation_date,
          'expiry_date', e.expiry_date, 'benefit_choice', e.benefit_choice),
        jsonb_build_object('status', 'refunded', 'override', p_override, 'request_id', p_request_id,
          'amount', p_amount, 'invoice_item_id', p_invoice_item_id, 'context', p_context),
        'refunds', p_reason, v_store);
      v_ended := v_ended || to_jsonb(e.entitlement_no);
    else
      update public.purchased_therapy_entitlements
         set status = 'refunded', updated_by = auth.uid(), updated_at = now() where id = e.id;
      perform public.write_audit_ex('purchased_therapy_entitlements', e.id, 'closed_with_invoice_line',
        jsonb_build_object('status', e.status, 'benefit_choice', e.benefit_choice),
        jsonb_build_object('status', 'refunded', 'request_id', p_request_id,
          'invoice_item_id', p_invoice_item_id, 'context', p_context),
        'refunds', p_reason, v_store);
      v_refunded := v_refunded || to_jsonb(e.entitlement_no);
    end if;
  end loop;
  return jsonb_build_object('refunded', v_refunded, 'terminated', v_ended);
end $function$
$def$;

  -- AFTER-14 and AFTER-M2: the request on an invoice, for the banner and for
  -- the dialog to find one already waiting.
  c_status_def constant text := $def$CREATE OR REPLACE FUNCTION public.invoice_request_status(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.approval_requests%rowtype;
begin
  -- 417: the latest refund or cancellation request on one invoice, for staff
  -- of its store: one still waiting first, else the last one resolved. The
  -- invoice shows it ("waiting for approval since ...", "rejected by ...:
  -- reason"), and the Refund / Cancel dialog opens it for review instead of
  -- raising a second one. The table's own rule lets only the requester and
  -- Managers read a request; this says that one exists and what became of it.
  -- The requester's own reason is not given here: it can be private to the
  -- customer. Approvers read it in the request itself.
  perform public.require_store_access((select i.store_id from public.invoices i where i.id = p_invoice_id));
  if not exists (select 1 from public.invoices i where i.id = p_invoice_id and i.deleted_at is null) then
    return null;
  end if;
  select * into r from public.approval_requests a
   where a.related_record_id = p_invoice_id and a.request_type in ('invoice_cancel', 'invoice_refund')
   order by (a.status = 'pending') desc, a.created_at desc, a.id
   limit 1;
  if not found then
    return jsonb_build_object('invoice_id', p_invoice_id, 'pending', false, 'request', null);
  end if;
  return jsonb_build_object('invoice_id', p_invoice_id, 'pending', r.status = 'pending',
    'can_review', coalesce(public.is_owner_or_manager(), false),
    'request', jsonb_build_object(
      'request_id', r.id, 'status', r.status,
      'action', coalesce(r.payload->>'action',
                         case r.request_type when 'invoice_cancel' then 'cancel' else 'refund_full' end),
      'requested_by', (select p.full_name from public.profiles p where p.id = r.requested_by),
      'requested_at', r.created_at,
      'resolved_by', (select p.full_name from public.profiles p where p.id = r.approved_by),
      'resolved_at', r.approved_at,
      'rejection_reason', r.rejection_reason,
      'legacy', r.payload->'plan' is null));
end $function$
$def$;

  -- Rule 5: what a reopening must record before it takes voucher stock.
  c_focv_def constant text := $def$CREATE OR REPLACE FUNCTION public.invoice_voucher_stock_unrecorded(p_invoice_id uuid, p_before_reopen boolean)
 RETURNS TABLE(store_id uuid, voucher_id uuid, quantity integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 -- 417 (the Owner, 9 Oct 2026): a reopening takes voucher stock once. By
 -- limited voucher, on the invoice's voucher and promotion lines: the units
 -- the customer still has from it (wherever one was moved since), and the
 -- units the reopening gives again when the invoice is settled
 -- (invoice_reopen_vouchers_settled takes their stock then), never more than
 -- it first gave, less what its voucher movement rows already record. The
 -- rows are counted by voucher, whatever their store, as
 -- deduct_invoice_stock nets them. The result is split across the stores
 -- that hold those vouchers, by how many each holds (the most first). That
 -- is where their stock was taken and where the reopening takes it again,
 -- so each row sits where the stock moved, as 416's 'Taken at Confirm FOC'
 -- rows do. Confirm FOC (and a correction that completes an invoice as
 -- FOC, 416) takes that stock with no row. Taking the FOC off (416) puts the
 -- unused units back with a row and keeps them to give again. A paid
 -- invoice's rows already record it, so nothing comes back for it.
 -- p_before_reopen: count the units the reopening is about to give again
 -- (its preview): those still waiting from an earlier reopening, or more if
 -- there are more to give.
 with u as (
   select v.voucher_id, v.store_id as at_store,
          case when v.source_type in ('invoice_voucher_sale', 'invoice_promotion_voucher')
               then x.granted_value else 0 end as first_given,
          case when v.status <> 'revoked' then v.quantity else 0 end
          + greatest(coalesce((select sum(r.quantity) from public.invoice_reopen_vouchers r
                                where r.benefit_id = x.id and r.applied_at is null), 0),
                     case when p_before_reopen then coalesce(c.quantity, 0) else 0 end) as kept
     from public.invoice_benefit_values x
     join public.customer_reward_vouchers v on v.id = x.reward_voucher_id
     join public.vouchers vo on vo.id = v.voucher_id
     join public.invoice_items it on it.id = x.invoice_item_id
     left join public.invoice_voucher_reopen_candidates(p_invoice_id) c on p_before_reopen and c.benefit_id = x.id
    where x.invoice_id = p_invoice_id and vo.qty_type = 'limited' and v.store_id is not null
      and it.line_kind in ('voucher', 'promotion')
 ), g as (
   select u.voucher_id, least(sum(u.kept), sum(u.first_given)) as units
     from u group by u.voucher_id
 ), n as (
   select g.voucher_id, g.units - coalesce(m.units, 0) as need
     from g
     left join (select mv.voucher_id, sum(mv.quantity) as units
                  from public.invoice_voucher_movements mv
                 where mv.invoice_id = p_invoice_id
                 group by mv.voucher_id) m
       on m.voucher_id = g.voucher_id
    where g.units > coalesce(m.units, 0)
 ), s as (
   select u.voucher_id, u.at_store, sum(u.kept) as kept,
          coalesce(sum(sum(u.kept)) over (partition by u.voucher_id order by sum(u.kept) desc, u.at_store
                                          rows between unbounded preceding and 1 preceding), 0) as before
     from u group by u.voucher_id, u.at_store
   having sum(u.kept) > 0
 )
 select s.at_store, s.voucher_id, least(s.kept, n.need - s.before)::integer
   from s join n on n.voucher_id = s.voucher_id
  where n.need > s.before
$function$
$def$;

  -- CREATE-14 and Q4: only a draft or unpaid invoice, with a reason kept.
  c_delete_def constant text := $def$CREATE OR REPLACE FUNCTION public.delete_invoice(p_invoice_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_inv public.invoices%rowtype; v_pays integer; v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  -- 417 (the Owner, 9 Oct 2026): any member of staff of the invoice's store
  -- may delete a draft or unpaid invoice made by mistake, giving a short
  -- reason that is kept in the history. Anything else (paid, part paid,
  -- completed FOC, cancelled, refunded, a request status) is undone with
  -- Refund / Cancel, which returns what it issued.
  perform public.require_store_access((select i.store_id from public.invoices i where i.id = p_invoice_id));
  if v_reason is null then
    raise exception 'Give a short reason for deleting this invoice. It is kept in the history.'; end if;
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access'; end if;
  -- Already deleted (a second click, a retry): nothing more to do.
  if v_inv.deleted_at is not null then return; end if;
  if v_inv.status::text not in ('draft', 'unpaid') then
    raise exception '% is %, so it cannot be deleted. Only a draft or unpaid invoice can be deleted. Use Refund / Cancel instead.',
      v_inv.invoice_no, case v_inv.status::text
        when 'completed_foc' then 'a completed FOC invoice'
        when 'partially_paid' then 'part paid'
        when 'paid' then 'paid'
        when 'refund_requested' then 'waiting for a refund decision'
        when 'cancellation_requested' then 'waiting for a cancellation decision'
        when 'cancelled' then 'cancelled'
        when 'refunded' then 'refunded'
        else replace(v_inv.status::text, '_', ' ') end; end if;
  -- Recheck payment existence AFTER the lock (race-safe).
  select count(*) into v_pays from public.invoice_payments where invoice_id = p_invoice_id;
  if coalesce(v_inv.paid_amount,0) > 0 or v_pays > 0 then
    raise exception 'Invoices with a recorded payment cannot be deleted. Use Refund / Cancel instead.';
  end if;
  -- 399: goods handed over before full payment are with the customer; the
  -- invoice stays until they are recorded as returned or written off.
  if exists (select 1 from public.invoice_goods_out(p_invoice_id)) then
    raise exception 'Goods on this invoice were handed over to the customer. Record them as returned or written off first (Record items returned on the invoice, Owner or Manager), then delete it.'; end if;
  update public.invoices set deleted_at = now() where id = p_invoice_id;
  perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_deleted', to_jsonb(v_inv),
    jsonb_build_object('deleted_at', now(), 'reason', v_reason), 'invoices', v_reason, v_inv.store_id);
end $function$
$def$;

  -- AFTER-7: a rental still with the customer after its invoice was
  -- cancelled goes back where it came from.
  c_receive_def constant text := $def$CREATE OR REPLACE FUNCTION public.receive_returned_rental(p_rental_id uuid, p_warehouse_id uuid, p_condition text, p_reason text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.rentals%rowtype; v_prod uuid; v_ok boolean; v_qty int:=0;
 v_put jsonb; v_place text; v_name text; v_note text;
begin
 if not public.is_owner_or_manager() then
  raise exception 'Only an Owner or Manager can receive a returned rental'; end if;
 if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'A note is required'; end if;
 if coalesce(p_condition,'') not in ('good','damaged','lost') then
  raise exception 'Record the condition as good, damaged or lost'; end if;
 select * into r from public.rentals where id=p_rental_id for update;
 if not found then raise exception 'Rental not found'; end if;
 if not public.user_has_store_access(r.store_id) then raise exception 'Rental not accessible'; end if;
 if coalesce(r.stock_returned,false) then
  -- Completion and cancellation cannot both take the same asset back.
  return jsonb_build_object('rental_id',r.id,'already_returned',true,'returned_quantity',0); end if;
 -- 417: only a rental cancelled with its invoice while it was still out. A
 -- rental still running comes back with Return on the Special page.
 if not public.rental_awaiting_return(r.id) then
  raise exception '% is not waiting to come back from a cancelled invoice. A rental that is still running is returned with Return on the Special page.', r.rental_no; end if;

 -- 417: it goes back where it came from, the store it was released from or
 -- its warehouse, as Return on the Special page puts it back
 -- (rental_put_back_stock), unless the person names another active
 -- warehouse. Only goods confirmed back AND sellable rejoin stock. Damaged
 -- and lost are resolved so they cannot be returned twice, but never become
 -- available.
 if p_warehouse_id is not null then
  select w.is_active and w.deleted_at is null, w.name into v_ok, v_name from public.warehouses w where w.id=p_warehouse_id;
  if not coalesce(v_ok,false) then
   raise exception 'Choose an active warehouse to receive this item'; end if;
  v_place:='warehouse';
 end if;
 if p_condition='good' then
  if p_warehouse_id is null then
   v_put:=public.rental_put_back_stock(r.id);
   v_qty:=coalesce((v_put->>'quantity')::int,0);
   v_place:=v_put->>'location_type'; v_name:=v_put->>'location_name'; v_note:=v_put->>'message';
  else
   select product_id into v_prod from public.special_products where id=r.special_product_id;
   if v_prod is not null then
    insert into public.warehouse_inventory(warehouse_id,product_id,current_qty)
     values(p_warehouse_id,v_prod,r.quantity)
     on conflict(warehouse_id,product_id) do update
       set current_qty=public.warehouse_inventory.current_qty+excluded.current_qty,updated_at=now();
    insert into public.stock_movements(product_id,movement_type,to_warehouse_id,quantity,notes,created_by)
     values(v_prod,'invoice_cancel_return'::stock_movement_type,p_warehouse_id,r.quantity,
       'Rental returned in good condition — '||r.rental_no||': '||p_reason,auth.uid());
    v_qty:=r.quantity;
   end if;
  end if;
 end if;

 update public.rentals
    set stock_returned=true,returned_at=coalesce(returned_at,now()),
        return_condition=p_condition::return_condition,
        status=case when status::text='cancelled' then status else 'returned'::rental_status end,
        notes=concat_ws(E'\n',notes,'Received '||p_condition||': '||p_reason)
  where id=r.id;
 perform public.write_audit_ex('rentals',r.id,'rental_received',to_jsonb(r),
   jsonb_build_object('condition',p_condition,'warehouse_id',p_warehouse_id,
     'location_type',v_place,'location_name',v_name,
     'returned_quantity',v_qty,'request_id',p_request_id),'rentals',p_reason,r.store_id);
 return jsonb_build_object('rental_id',r.id,'returned_quantity',v_qty,'condition',p_condition,
   'made_available',p_condition='good','location_type',v_place,'location_name',v_name,'stock_note',v_note);
end $function$
$def$;

  -- AFTER-7: what is still out, with its line and where it came from.
  c_awaiting_def constant text := $def$CREATE OR REPLACE FUNCTION public.invoice_rentals_awaiting_return(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 -- 417: each rental of a cancelled invoice still with the customer, with the
 -- line it was sold on and where it came from (it goes back there unless the
 -- person names another warehouse): the store it was released from, or its
 -- warehouse.
 select coalesce(jsonb_agg(jsonb_build_object(
   'rental_id',r.id,'rental_no',r.rental_no,'quantity',r.quantity,
   'item',coalesce(sp.name,'Special product'),
   'invoice_item_id',r.invoice_item_id,
   'default_warehouse_id',r.warehouse_id,
   'default_warehouse',(select w.name from public.warehouses w where w.id=r.warehouse_id),
   'source_type',case when r.source_store_id is not null then 'store'
                      when r.warehouse_id is not null then 'warehouse' end,
   'source_name',coalesce((select s.name from public.stores s where s.id=r.source_store_id),
                          (select w.name from public.warehouses w where w.id=r.warehouse_id)),
   'cancelled_at',r.cancelled_at,'status',r.status) order by r.rental_no),'[]'::jsonb)
 from public.rentals r
 left join public.special_products sp on sp.id=r.special_product_id
 join public.invoices i on i.id=r.invoice_id
 where r.invoice_id=p_invoice_id and public.user_has_store_access(i.store_id)
   and public.rental_awaiting_return(r.id)
$function$
$def$;

  -- ══ Patches: anchors (each must be found exactly once) ═════════════════════
  --
  -- invoice_action_plan: 363's therapy units, one stock entry per movement,
  -- units no line holds; and 417's reward entitlements and amount owed back.
  c_plan_decl_a constant text := $a$ v_new_sel jsonb; v_cap numeric; v_one numeric; v_removed numeric;$a$;
  c_plan_decl_r constant text := $r$ v_new_sel jsonb; v_cap numeric; v_one numeric; v_removed numeric;
 v363_units jsonb; v363_used text; v363_granted int;
 v363_detached jsonb; v363_bb boolean;
 v417_items jsonb; v417_open text; v417_kept text; v417_codes text[]; v417_owed jsonb;$r$;

  -- 361's promotion branch skipped a movement an earlier line already
  -- listed, so with a product line read first the promotion's goods went
  -- unlisted. Every line now offers its share; the merge below adds them up
  -- and caps the sum at what is outstanding, whatever order the lines come in.
  c_plan_skip_a constant text := $a$       or not ((s->>'product_id')::uuid in (select public.invoice_line_stock_products(it.id)))
       or v_stock @> jsonb_build_array(jsonb_build_object('movement_id', s->>'movement_id'));$a$;
  c_plan_skip_r constant text := $r$       or not ((s->>'product_id')::uuid in (select public.invoice_line_stock_products(it.id)));
     -- 363: a movement another line listed is offered again for this line's
     -- share; the merge before the money section adds and caps them.$r$;

  c_plan_units_a constant text := $a$  if it.therapy_service_id is not null then$a$;
  c_plan_units_r constant text := $r$  -- 363: therapy a promotion (or bundle) granted closes with its line: all of
  -- it for a cancellation, a full refund, or a refund taking what is left of
  -- the line (the refund engine's own "in full"); otherwise its share of the
  -- units the line granted, units not yet used first. A used unit needs the
  -- same override as therapy sold on its own line.
  v363_units:=null; v363_used:=null;
  if it.line_kind::text<>'therapy' then
   select count(*) into v363_granted from public.purchased_therapy_entitlements where invoice_item_id=it.id;
   select jsonb_agg(jsonb_build_object('id',q.id,'entitlement_no',q.entitlement_no,'package',q.package_name,
            'status',q.status,'benefit',q.benefit_choice,'used',q.used,'activation_date',q.activation_date) order by q.rn),
          string_agg(case when q.used then q.entitlement_no end,', ' order by q.rn)
     into v363_units, v363_used
     from (select e.id, e.entitlement_no, e.package_name, e.status, e.benefit_choice, e.activation_date,
                  public.therapy_unit_consumed(e.id) used,
                  row_number() over (order by public.therapy_unit_consumed(e.id), e.unit_index nulls last, e.entitlement_no) rn,
                  count(*) over () cnt
             from public.purchased_therapy_entitlements e
            where e.invoice_item_id=it.id and e.status not in ('cancelled','refunded')) q
    where q.rn<=case when v_qty>=v_full_qty or v_amount>=v_line_rem then q.cnt
                     else ceil(v363_granted*v_qty::numeric/v_full_qty) end;
   if v363_used is not null then
    -- A line whose refund is fixed by its unused vouchers or credit takes no
    -- amount of its own: the refund engine accepts only that figure.
    v363_bb:=v_has_ben or it.line_kind::text in ('credit_package','premium_bundle');
    v_codes:=v_codes||jsonb_build_array('therapy_activated');
    v_over:=v_over||jsonb_build_array(jsonb_build_object('code','therapy_activated','amount_required',not v363_bb,
     'invoice_item_id',it.id,'default_amount',v_amount,
     'message','Therapy from '||coalesce(x->>'name','this promotion')||' has been started or has ended, or vouchers from it have already been collected ('||v363_used||'). Ending it keeps that history and withdraws any vouchers not yet collected. '||
       case when v363_bb
         then 'The refund for this line is the value of its unused vouchers or credit, as shown above; an Owner or Manager must give a reason.'
         else 'Therapy inside a promotion has no price of its own, so an Owner or Manager must state the refund amount for this line with a reason.' end));
   end if;
  end if;
  if it.therapy_service_id is not null then$r$;

  c_plan_line_a constant text := $a$   'benefit_backed',coalesce((select sum((q->>'amount')::numeric) from jsonb_array_elements(v_ben) q),0)));$a$;
  c_plan_line_r constant text := $r$   'benefit_backed',coalesce((select sum((q->>'amount')::numeric) from jsonb_array_elements(v_ben) q),0))
   -- 363: only lines that close therapy carry the key, so other plans hash as before
   ||case when v363_units is not null then jsonb_build_object('therapy_units',v363_units) else '{}'::jsonb end);$r$;

  c_plan_money_a constant text := $a$ -- ---- money that can actually go back ------------------------------------$a$;
  c_plan_money_r constant text := $r$ -- 363: one stock entry per movement. A product line and a promotion (or two
 -- lines of one product) can draw on the same movement, and the screen
 -- confirms one row per movement, so a second row for it was lost.
 select coalesce(jsonb_agg(m.e order by m.first),'[]'::jsonb) into v_stock
   from (select min(t.ord) first,
                (array_agg(t.k order by t.ord))[1]
                  ||jsonb_build_object('proposed_sellable',
                      least(sum((t.k->>'proposed_sellable')::int),max((t.k->>'outstanding')::int))) e
           from jsonb_array_elements(v_stock) with ordinality t(k,ord)
          group by t.k->>'movement_id') m;

 -- ---- money that can actually go back ------------------------------------$r$;

  c_plan_reward_a constant text := $a$ -- ---- a summary a person can check ---------------------------------------$a$;
  c_plan_reward_r constant text := $r$ -- 417: a credit package's qualification rewards, the therapy entitlements it
 -- granted. A refund or cancellation of the package needs them settled first
 -- (assert_invoice_credit_source_evidence). The approval settles them in the
 -- same step, so a refund that fails withdraws nothing: those not claimed
 -- yet are withdrawn, and those already activated or claimed stay with the
 -- customer with their history (resolve_invoice_credit_rewards' own rule).
 -- Only lines this action takes money back on count; a cancellation, all.
 -- Never a blocker: staff can still raise the request.
 select jsonb_agg(distinct it2.id order by it2.id),
        string_agg(distinct e.entitlement_no, ', ' order by e.entitlement_no)
          filter (where e.status='pending_activation' and e.claimed_at is null),
        string_agg(distinct e.entitlement_no, ', ' order by e.entitlement_no)
          filter (where not (e.status='pending_activation' and e.claimed_at is null))
   into v417_items, v417_open, v417_kept
   from public.credit_package_sales cs
   join public.invoice_items it2 on it2.invoice_id=cs.invoice_id and it2.credit_package_id=cs.package_id
   join public.therapy_entitlements e on e.qualification_group_id=public.credit_package_reward_group(cs.id)
  where cs.invoice_id=i.id and (cs.reward_units>0 or coalesce(cs.reward_voucher_qty,0)>0)
    and cs.rewards_resolved_at is null
    and e.status not in ('cancelled','expired','refunded')
    and (p_action='cancel' or exists(select 1 from jsonb_array_elements(v_sel) sl
                                      where sl->>'invoice_item_id'=it2.id::text and (sl->>'amount')::numeric>0));
 if v417_items is not null then
  v_over:=v_over||jsonb_build_array(jsonb_build_object('code','reward_withdrawal',
   'invoice_item_ids',v417_items,
   'entitlements',coalesce(to_jsonb(string_to_array(v417_open,', ')),'[]'::jsonb),
   'message',case when v417_open is not null
     then 'Reward entitlements from this credit package that were not claimed yet ('||v417_open||') are withdrawn with this '
          ||case when p_action='cancel' then 'cancellation' else 'refund' end||'.'
     else 'The reward entitlements from this credit package are settled with this '
          ||case when p_action='cancel' then 'cancellation' else 'refund' end||'.' end));
  if v417_kept is not null then
   v_over:=v_over||jsonb_build_array(jsonb_build_object('code','reward_consumed_kept',
    'entitlements',to_jsonb(string_to_array(v417_kept,', ')),
    'message','Reward entitlements from this credit package were already activated or claimed ('||v417_kept
      ||'). They stay with the customer and keep their history.'));
  end if;
 end if;
 -- 417 (the Owner, 9 Oct 2026): a cancellation that keeps something the
 -- customer already had (sessions delivered, therapy started, vouchers
 -- redeemed, credit spent) does not owe back all the money held. The Owner or
 -- Manager states how much is owed back; the rest is kept for what was used.
 v417_owed:=null;
 if p_action='cancel' and v_held>0 then
  select array_agg(distinct q->>'code' order by q->>'code') into v417_codes
    from jsonb_array_elements(v_over) q
   where q->>'code' in ('session_used','therapy_activated','voucher_redeemed','credit_used');
  if v417_codes is not null then
   v417_owed:=jsonb_build_object('needed',true,'held',round(v_held,2),'used',to_jsonb(v417_codes),
    'message','Part of what this invoice sold has been used, so not all of the S$'||to_char(v_held,'FM999999990.00')
      ||' it holds is owed back. State how much is owed back to the customer. The rest is kept for what was used.');
  end if;
 end if;

 -- ---- a summary a person can check ---------------------------------------$r$;

  c_plan_summary_a constant text := $a$ for x in select * from jsonb_array_elements(v_over) loop$a$;
  c_plan_summary_r constant text := $r$ -- 363: a therapy override's default amount is its line's figure after the
 -- money cap, so the pre-filled amount is one that can be taken.
 v_over:=(select coalesce(jsonb_agg(case when t.ov->>'code'='therapy_activated' and t.ov ? 'invoice_item_id'
            then jsonb_set(t.ov,'{default_amount}',coalesce((select l->'amount' from jsonb_array_elements(v_sel) l
                   where l->>'invoice_item_id'=t.ov->>'invoice_item_id' limit 1),t.ov->'default_amount'))
            else t.ov end order by t.n),'[]'::jsonb)
          from jsonb_array_elements(v_over) with ordinality t(ov,n));
 -- 363: therapy no line holds (a correction deleted its line). An action that
 -- closes the invoice (a cancellation, a full refund, or a part refund that
 -- pays back all that is left) closes the unused ones; a used one is left.
 v363_detached:=null;
 if p_action in ('cancel','refund_full')
    or (p_action='refund_partial' and public.invoice_charge_total(i.id)-v_total<=0) then
  select jsonb_agg(jsonb_build_object('id',e.id,'entitlement_no',e.entitlement_no,'package',e.package_name,
           'status',e.status,'benefit',e.benefit_choice,'used',public.therapy_unit_consumed(e.id)) order by e.entitlement_no)
    into v363_detached
    from public.purchased_therapy_entitlements e
   where e.invoice_id=i.id and e.invoice_item_id is null and e.status not in ('cancelled','refunded');
 end if;
 -- 363: each therapy unit the action closes, by name.
 for x in select * from jsonb_array_elements(v_sel) loop
  for b in select * from jsonb_array_elements(coalesce(x->'therapy_units','[]')) loop
   v_sum:=v_sum||jsonb_build_array(case when (b->>'used')::boolean
     then 'End therapy '||(b->>'entitlement_no')||' ('||coalesce(b->>'package','')||') from '||(x->>'name')||': it has been used, so only on the override below.'
     else 'Close therapy '||(b->>'entitlement_no')||' ('||coalesce(b->>'package','')||') from '||(x->>'name')||': not used yet'||
          case when b->>'benefit'='voucher' then '; vouchers not yet collected are withdrawn' else '' end||'.' end);
  end loop;
 end loop;
 for b in select * from jsonb_array_elements(coalesce(v363_detached,'[]')) loop
  v_sum:=v_sum||jsonb_build_array(case when (b->>'used')::boolean
    then 'Therapy '||(b->>'entitlement_no')||' ('||coalesce(b->>'package','')||') is on no invoice line (a correction removed its line) and has been used, so it is left running.'
    else 'Close therapy '||(b->>'entitlement_no')||' ('||coalesce(b->>'package','')||'), which is on no invoice line: not used yet.' end);
 end loop;
 for x in select * from jsonb_array_elements(v_over) loop$r$;

  c_plan_effects_a constant text := $a$    'stock_returned',v_stock,$a$;
  c_plan_effects_r constant text := $r$    -- 363: therapy units this action closes
    'therapy_closed',(select coalesce(jsonb_agg(q.t order by q.o),'[]'::jsonb) from (
        select 1 o, jsonb_build_object('entitlement_no',tu->>'entitlement_no','package',tu->>'package',
                 'used',(tu->>'used')::boolean,'benefit',tu->>'benefit','line',ll->>'name') t
          from jsonb_array_elements(v_sel) ll,
               jsonb_array_elements(coalesce(ll->'therapy_units','[]'::jsonb)) tu
        union all
        select 2, jsonb_build_object('entitlement_no',du->>'entitlement_no','package',du->>'package',
                 'used',false,'benefit',du->>'benefit','line','no invoice line')
          from jsonb_array_elements(coalesce(v363_detached,'[]'::jsonb)) du
         where not (du->>'used')::boolean) q),
    -- 363: used therapy no line holds, which this action leaves running
    'therapy_left',(select coalesce(jsonb_agg(jsonb_build_object('entitlement_no',du->>'entitlement_no',
          'package',du->>'package','line','no invoice line') order by du->>'entitlement_no'),'[]'::jsonb)
        from jsonb_array_elements(coalesce(v363_detached,'[]'::jsonb)) du where (du->>'used')::boolean),
    -- 417: a credit package's reward entitlements settled with this action
    'rewards',jsonb_build_object(
        'withdrawn',coalesce(to_jsonb(string_to_array(v417_open,', ')),'[]'::jsonb),
        'kept',coalesce(to_jsonb(string_to_array(v417_kept,', ')),'[]'::jsonb)),
    'stock_returned',v_stock,$r$;

  c_plan_result_a constant text := $a$  'overrides_required',v_over,'blockers',v_block,'summary',v_sum,$a$;
  c_plan_result_r constant text := $r$  'overrides_required',v_over,'blockers',v_block,'summary',v_sum,
  'detached_therapy',coalesce(v363_detached,'[]'::jsonb),
  -- 417: on a cancellation whose customer already had part of it, the amount
  -- owed back is stated by the Owner or Manager (null otherwise)
  'refund_owed',v417_owed,$r$;

  c_plan_hash_a constant text := $a$  'plan_hash',md5(jsonb_build_object('a',p_action,'t',v_total,'d',v_due,'l',v_sel,'s',v_src,'k',v_stock,'o',v_over)::text));$a$;
  c_plan_hash_r constant text := $r$  -- 363: units no line holds are hashed only when there are any
  'plan_hash',md5((jsonb_build_object('a',p_action,'t',v_total,'d',v_due,'l',v_sel,'s',v_src,'k',v_stock,'o',v_over)
    ||case when v363_detached is not null then jsonb_build_object('u',v363_detached) else '{}'::jsonb end)::text));$r$;

  -- resolve_invoice_action_v2: 363's per-line overrides and therapy closing;
  -- 417's reject reason, reward settlement and amount owed back.
  c_res_decl_a constant text := $a$ v_exec numeric; v_planned numeric; v_alloc numeric; v_assigned numeric; v_n int; v_idx int;$a$;
  c_res_decl_r constant text := $r$ v_exec numeric; v_planned numeric; v_alloc numeric; v_assigned numeric; v_n int; v_idx int;
 v363_ov jsonb; v363_amt numeric;
 v417_rw jsonb; v417_ov jsonb; v417_ack boolean; v417_owed numeric; v417_held numeric;$r$;

  c_res_reject_a constant text := $a$ if not p_approve then
  update public.approval_requests set status='rejected',approved_by=auth.uid(),approved_at=now(),$a$;
  c_res_reject_r constant text := $r$ if not p_approve then
  -- 417: a rejection says why, in the approver's own words (the screen no
  -- longer fills in the requester's reason for them). The invoice shows it.
  if nullif(trim(coalesce(p_note,'')),'') is null then
   raise exception 'Give a reason for rejecting this request.'; end if;
  update public.approval_requests set status='rejected',approved_by=auth.uid(),approved_at=now(),$r$;

  c_res_missing_a constant text := $a$  select q into ov from jsonb_array_elements(coalesce(p_overrides,'[]')) q
   where q->>'code'=x->>'code' and nullif(trim(coalesce(q->>'reason','')),'') is not null limit 1;$a$;
  c_res_missing_r constant text := $r$  -- 363: an override may name its line (invoice_item_id), so two lines needing
  -- the same override each get their own reason and amount. One that names no
  -- line serves every line with its code, as before.
  select q into ov from jsonb_array_elements(coalesce(p_overrides,'[]')) q
   where q->>'code'=x->>'code' and nullif(trim(coalesce(q->>'reason','')),'') is not null
     and (nullif(q->>'invoice_item_id','') is null or x->>'invoice_item_id' is null
          or q->>'invoice_item_id'=x->>'invoice_item_id')
   order by (q->>'invoice_item_id' is not distinct from x->>'invoice_item_id') desc,
            ((q->>'amount') is not null)=coalesce((x->>'amount_required')::boolean,false) desc limit 1;$r$;

  c_res_lines_a constant text := $a$          coalesce((select round((q->>'amount')::numeric,2) from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                     where (q->>'amount') is not null
                       and coalesce(l->'override_codes','[]') ? (q->>'code') limit 1),
                   (l->>'amount')::numeric),
          'benefits',coalesce(l->'benefits','[]'),
          'override',(select q from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                       where coalesce(l->'override_codes','[]') ? (q->>'code') limit 1))),'[]')
   into v_lines from jsonb_array_elements(v_plan->'lines') l
  where (l->>'amount')::numeric>0
     or exists(select 1 from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                where (q->>'amount') is not null and coalesce(l->'override_codes','[]') ? (q->>'code'));$a$;
  c_res_lines_r constant text := $r$          -- 363: an override naming this line first, then one by code alone
          coalesce((select round((q->>'amount')::numeric,2) from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                     where (q->>'amount') is not null
                       and coalesce(l->'override_codes','[]') ? (q->>'code')
                       and (nullif(q->>'invoice_item_id','') is null or q->>'invoice_item_id'=l->>'invoice_item_id')
                       -- an amount naming no line never lands on a line whose
                       -- refund is fixed by its vouchers or credit
                       and (q->>'invoice_item_id'=l->>'invoice_item_id'
                            or not exists(select 1 from jsonb_array_elements(coalesce(v_plan->'overrides_required','[]')) po
                                           where po->>'code'=q->>'code' and po->>'invoice_item_id'=l->>'invoice_item_id'
                                             and not coalesce((po->>'amount_required')::boolean,true)))
                     order by (q->>'invoice_item_id' is not distinct from l->>'invoice_item_id') desc limit 1),
                   (l->>'amount')::numeric),
          'benefits',coalesce(l->'benefits','[]'),
          'override',(select q from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                       where coalesce(l->'override_codes','[]') ? (q->>'code')
                         and (nullif(q->>'invoice_item_id','') is null or q->>'invoice_item_id'=l->>'invoice_item_id')
                       order by (q->>'invoice_item_id' is not distinct from l->>'invoice_item_id') desc,
                                ((q->>'amount') is not null) desc limit 1))),'[]')
   into v_lines from jsonb_array_elements(v_plan->'lines') l
  where ((l->>'amount')::numeric>0
     or exists(select 1 from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                where (q->>'amount') is not null and coalesce(l->'override_codes','[]') ? (q->>'code')
                  and (nullif(q->>'invoice_item_id','') is null or q->>'invoice_item_id'=l->>'invoice_item_id')
                  and (q->>'invoice_item_id'=l->>'invoice_item_id'
                            or not exists(select 1 from jsonb_array_elements(coalesce(v_plan->'overrides_required','[]')) po
                                           where po->>'code'=q->>'code' and po->>'invoice_item_id'=l->>'invoice_item_id'
                                             and not coalesce((po->>'amount_required')::boolean,true)))))
    -- 363: a line whose used therapy is ended with 0 stated refunds nothing, and
    -- the engine refuses a zero line; its therapy is ended below instead.
    and not (coalesce(l->'override_codes','[]') ? 'therapy_activated'
             and coalesce((select round((q->>'amount')::numeric,2) from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                            where (q->>'amount') is not null and coalesce(l->'override_codes','[]') ? (q->>'code')
                              and (nullif(q->>'invoice_item_id','') is null or q->>'invoice_item_id'=l->>'invoice_item_id')
                              and (q->>'invoice_item_id'=l->>'invoice_item_id'
                            or not exists(select 1 from jsonb_array_elements(coalesce(v_plan->'overrides_required','[]')) po
                                           where po->>'code'=q->>'code' and po->>'invoice_item_id'=l->>'invoice_item_id'
                                             and not coalesce((po->>'amount_required')::boolean,true)))
                            order by (q->>'invoice_item_id' is not distinct from l->>'invoice_item_id') desc limit 1),
                          (l->>'amount')::numeric)<=0);$r$;

  c_res_close_a constant text := $a$ if v_action='cancel' then$a$;
  c_res_close_r constant text := $r$ -- 417: a credit package's reward entitlements are settled in this same step,
 -- before any money moves, as the reviewed plan listed them: those not
 -- claimed yet are withdrawn, and those already activated or claimed keep
 -- their history (only with the reason given for that). A refund or
 -- cancellation that then fails undoes this too.
 select q into v417_rw from jsonb_array_elements(coalesce(v_plan->'overrides_required','[]')) q
  where q->>'code'='reward_withdrawal' limit 1;
 if v417_rw is not null then
  select q into v417_ov from jsonb_array_elements(coalesce(p_overrides,'[]')) q
   where q->>'code'='reward_withdrawal' and nullif(trim(coalesce(q->>'reason','')),'') is not null limit 1;
  v417_ack:=exists(select 1 from jsonb_array_elements(coalesce(p_overrides,'[]')) q
                    where q->>'code'='reward_consumed_kept' and nullif(trim(coalesce(q->>'reason','')),'') is not null);
  if v_action='cancel' then
   perform public.resolve_invoice_credit_rewards(i.id,trim(v417_ov->>'reason'),null,v417_ack,r.id);
  else
   for x in select * from jsonb_array_elements(coalesce(v417_rw->'invoice_item_ids','[]')) loop
    perform public.resolve_invoice_credit_rewards(i.id,trim(v417_ov->>'reason'),(x#>>'{}')::uuid,v417_ack,r.id);
   end loop;
  end if;
 end if;

 -- 363: therapy the reviewed plan closes goes first, exactly as reviewed
 -- (the plan hash covers it), and the refund engine is told so, so it closes
 -- nothing of its own on these lines. The override reaches only a line whose
 -- review asked for it; the amount stated with it is recorded.
 perform set_config('invoice.therapy_reviewed',r.id::text,true);
 for x in select * from jsonb_array_elements(v_plan->'lines') loop
  continue when jsonb_typeof(x->'therapy_units') is distinct from 'array';
  v363_ov:=null;
  if coalesce(x->'override_codes','[]'::jsonb) ? 'therapy_activated' then
   select q into v363_ov from jsonb_array_elements(coalesce(p_overrides,'[]')) q
    where q->>'code'='therapy_activated'
      and (nullif(q->>'invoice_item_id','') is null or q->>'invoice_item_id'=x->>'invoice_item_id')
    order by (q->>'invoice_item_id' is not distinct from x->>'invoice_item_id') desc, ((q->>'amount') is not null) desc limit 1;
  end if;
  -- what this line refunds: the amount stated for it, else the reviewed figure
  v363_amt:=coalesce((select (l->>'amount')::numeric from jsonb_array_elements(v_lines) l
                       where l->>'invoice_item_id'=x->>'invoice_item_id' limit 1),0);
  -- An amount that pays back all of the line must not leave part of its
  -- therapy open: the review has to have listed all of it.
  if coalesce((x->>'remaining_value')::numeric,0)>0 and v363_amt>=(x->>'remaining_value')::numeric
     and exists(select 1 from public.purchased_therapy_entitlements e
                 where e.invoice_item_id=(x->>'invoice_item_id')::uuid and e.status not in ('cancelled','refunded')
                   and e.id::text not in (select u->>'id' from jsonb_array_elements(x->'therapy_units') u)) then
   raise exception 'The amount stated pays back all of %, but the reviewed plan ends only part of its therapy. Refund it with Full refund, or state a smaller amount.', x->>'name'; end if;
  -- A line whose refund is fixed by its vouchers or credit states no amount
  -- (whatever an override naming no line says); the termination records the
  -- line's own figure.
  if v363_ov is not null and ((v363_ov->>'amount') is null
     or exists(select 1 from jsonb_array_elements(coalesce(v_plan->'overrides_required','[]')) po
                where po->>'code'='therapy_activated' and po->>'invoice_item_id'=x->>'invoice_item_id'
                  and not coalesce((po->>'amount_required')::boolean,true))) then
   v363_ov:=v363_ov||jsonb_build_object('amount',v363_amt); end if;
  perform public.close_invoice_therapy_units(i.id,(x->>'invoice_item_id')::uuid,
    array(select (u->>'id')::uuid from jsonb_array_elements(x->'therapy_units') u),
    v363_ov,coalesce(round((v363_ov->>'amount')::numeric,2),v363_amt),coalesce(p_note,r.reason),r.id,v_action);
 end loop;
 -- Unused therapy no line holds, as listed; a used one is left running.
 if jsonb_typeof(v_plan->'detached_therapy')='array'
    and exists(select 1 from jsonb_array_elements(v_plan->'detached_therapy') du where not (du->>'used')::boolean) then
  perform public.close_invoice_therapy_units(i.id,null,
    array(select (du->>'id')::uuid from jsonb_array_elements(v_plan->'detached_therapy') du where not (du->>'used')::boolean),
    null,0,coalesce(p_note,r.reason),r.id,v_action);
 end if;
 -- Started therapy sold on its own line whose line refunds nothing (0 stated)
 -- is not sent to the refund engine, so it ends here on its override.
 for x in select * from jsonb_array_elements(v_plan->'lines') loop
  continue when x->>'line_kind'<>'therapy' or not coalesce(x->'override_codes','[]'::jsonb) ? 'therapy_activated'
             or exists(select 1 from jsonb_array_elements(v_lines) l where l->>'invoice_item_id'=x->>'invoice_item_id');
  select q into v363_ov from jsonb_array_elements(coalesce(p_overrides,'[]')) q
   where q->>'code'='therapy_activated'
     and (nullif(q->>'invoice_item_id','') is null or q->>'invoice_item_id'=x->>'invoice_item_id')
   order by (q->>'invoice_item_id' is not distinct from x->>'invoice_item_id') desc, ((q->>'amount') is not null) desc limit 1;
  perform public.close_invoice_therapy_units(i.id,(x->>'invoice_item_id')::uuid,null,v363_ov,0,
    coalesce(p_note,r.reason),r.id,v_action);
 end loop;

 if v_action='cancel' then$r$;

  c_res_cancel_a constant text := $a$  v_cancel:=public.cancel_invoice_recorded(i.id,coalesce(p_note,r.reason),r.id);$a$;
  c_res_cancel_r constant text := $r$  -- 363: started therapy sold on its own line ends with the cancellation, on
  -- the override the approver gave. A refund recorded above has already ended
  -- it; otherwise the override was asked for and the therapy kept running.
  for x in select * from jsonb_array_elements(v_plan->'lines') loop
   continue when x->>'line_kind'<>'therapy' or not coalesce(x->'override_codes','[]'::jsonb) ? 'therapy_activated';
   select q into v363_ov from jsonb_array_elements(coalesce(p_overrides,'[]')) q
    where q->>'code'='therapy_activated'
      and (nullif(q->>'invoice_item_id','') is null or q->>'invoice_item_id'=x->>'invoice_item_id')
    order by (q->>'invoice_item_id' is not distinct from x->>'invoice_item_id') desc, ((q->>'amount') is not null) desc limit 1;
   perform public.close_invoice_therapy_units(i.id,(x->>'invoice_item_id')::uuid,null,v363_ov,
     round((v363_ov->>'amount')::numeric,2),coalesce(p_note,r.reason),r.id,'cancel');
  end loop;
  v_cancel:=public.cancel_invoice_recorded(i.id,coalesce(p_note,r.reason),r.id);
  -- 417 (the Owner, 9 Oct 2026): when the customer already had part of what
  -- this sold, not all the money held is owed back. The Owner or Manager
  -- states how much is (an override 'refund_owed' with an amount; without
  -- one, the refund the reviewed plan states, with any amounts they gave).
  -- That is the refund due, recorded when it is paid; the rest is kept for
  -- what was used. A refund recorded now was that amount, so nothing more is
  -- owed. With nothing used, all the money held is owed back, as before.
  -- "Used" is what the reviewed plan found (therapy ended just now on its
  -- override no longer reads as running), or what the cancellation kept.
  if jsonb_typeof(v_plan->'refund_owed')='object' or cardinality(public.cancelled_invoice_used_value(i.id))>0 then
   if p_record_refund then
    v417_owed:=0;
   else
    select round((q->>'amount')::numeric,2) into v417_owed from jsonb_array_elements(coalesce(p_overrides,'[]')) q
     where q->>'code'='refund_owed' and (q->>'amount') is not null limit 1;
    v417_owed:=coalesce(v417_owed,v_exec,0);
    v417_held:=public.invoice_net_received(i.id);
    if v417_owed<0 then
     raise exception 'The amount owed back cannot be less than S$0. Nothing was changed.'; end if;
    if v417_owed>v417_held then
     raise exception 'The amount owed back (S$%) is more than the S$% this invoice holds. Nothing was changed.',
       to_char(v417_owed,'FM999999990.00'),to_char(v417_held,'FM999999990.00'); end if;
   end if;
   update public.invoices set cancel_refund_owed=v417_owed where id=i.id;
   perform public.write_audit_ex('invoices',i.id,'cancel_refund_owed_stated',null,
     jsonb_build_object('refund_owed',v417_owed,'held',public.invoice_net_received(i.id),
       'used',to_jsonb(public.cancelled_invoice_used_value(i.id)),'refund_recorded',p_record_refund,'request_id',r.id),
     'invoices',coalesce(p_note,r.reason),i.store_id);
   v_cancel:=v_cancel||public.invoice_financial_position(i.id);
  end if;$r$;

  c_res_payload_a constant text := $a$     'outcome',coalesce(v_cancel,v_refund))
 where id=r.id;$a$;
  c_res_payload_r constant text := $r$     'outcome',coalesce(v_cancel,v_refund),'refund_owed',v417_owed)
 where id=r.id;$r$;

  c_res_due_a constant text := $a$   'refund_still_due',case when v_action='cancel' and v_refund is null
                           then coalesce((v_plan->>'refund_due')::numeric,0) else 0 end,$a$;
  c_res_due_r constant text := $r$   -- 417: on a cancellation whose customer had part of it, what the approver
   -- stated is owed back
   'refund_still_due',case when v_action='cancel' and v_refund is null
                           then coalesce(v417_owed,(v_plan->>'refund_due')::numeric,0) else 0 end,
   'refund_owed',v417_owed,$r$;

  -- request_invoice_action_v2: a replay must be the same request (AFTER-M2).
  c_req_replay_a constant text := $a$ if found then
  return jsonb_build_object('request_id',v_existing.id,'status',v_existing.status,
    'plan',v_existing.payload->'plan','replayed',true); end if;$a$;
  c_req_replay_r constant text := $r$ if found then
  -- 417: the same request ID answers only the same request. One that was
  -- used for another invoice, another action or other items is refused, not
  -- replayed.
  if v_existing.related_record_id is distinct from p_invoice_id
     or v_existing.payload->>'action' is distinct from p_action
     or coalesce(v_existing.payload->'lines','[]'::jsonb) is distinct from coalesce(p_lines,'[]'::jsonb) then
   raise exception 'This request ID was already used for a different request. Nothing was changed. Close this window and start again.'; end if;
  return jsonb_build_object('request_id',v_existing.id,'status',v_existing.status,
    'plan',v_existing.payload->'plan','replayed',true); end if;$r$;

  c_req_race_a constant text := $a$   if v_existing.payload->>'request_id' is distinct from p_request_id::text then
    raise exception 'A request for this invoice is already waiting for approval'; end if;$a$;
  c_req_race_r constant text := $r$   if v_existing.payload->>'request_id' is distinct from p_request_id::text then
    raise exception 'A request for this invoice is already waiting for approval'; end if;
   -- 417: as above, only the same request is replayed.
   if v_existing.related_record_id is distinct from p_invoice_id
      or v_existing.payload->>'action' is distinct from p_action
      or coalesce(v_existing.payload->'lines','[]'::jsonb) is distinct from coalesce(p_lines,'[]'::jsonb) then
    raise exception 'This request ID was already used for a different request. Nothing was changed. Close this window and start again.'; end if;$r$;

  -- refund_invoice_recorded: 363's therapy rules; 417's amount owed back.
  c_ref_lock_a constant text := $a$ if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;$a$;
  c_ref_lock_r constant text := $r$ if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 -- 363: every therapy unit on the invoice and its voucher allowance are
 -- locked before any benefit or voucher stock is touched, in the order the
 -- Claim window takes them (unit, allowance, stock), so the two cannot wait
 -- on each other.
 perform 1 from public.purchased_therapy_entitlements
   where invoice_id=i.id and status not in ('cancelled','refunded') order by id for update;
 perform 1 from public.therapy_entitlements te
   where te.id in (select voucher_entitlement_id from public.purchased_therapy_entitlements
                    where invoice_id=i.id and status not in ('cancelled','refunded'))
   order by te.id for update;$r$;

  c_ref_used_a constant text := $a$     if i.status='cancelled' and cardinality(public.cancelled_invoice_used_value(i.id))>0 then
       raise exception 'Part of what % sold has been used (%), so not all the money it still holds is owed back. It cannot be recorded here until the Owner decides how much goes back; nothing was recorded.',$a$;
  c_ref_used_r constant text := $r$     -- 417 (the Owner, 9 Oct 2026): the Owner or Manager states how much is
     -- owed back when cancelling (cancel_refund_owed); up to that is recorded
     -- here (the total is checked below). A cancellation with no amount
     -- stated (made before this) is still refused.
     if i.status='cancelled' and i.cancel_refund_owed is null and cardinality(public.cancelled_invoice_used_value(i.id))>0 then
       raise exception 'Part of what % sold has been used (%), and no amount owed back was stated when it was cancelled, so not all the money it still holds is owed back. Nothing was recorded.',$r$;

  c_ref_promo_a constant text := $a$   if it.id is not null and it.line_kind in ('product','promotion') and jsonb_array_length(coalesce(p_stock,'[]'))=0$a$;
  c_ref_promo_r constant text := $r$   -- 363: a promotion (or bundle) line refunded in full closes the therapy it
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
   if it.id is not null and it.line_kind in ('product','promotion') and jsonb_array_length(coalesce(p_stock,'[]'))=0$r$;

  c_ref_cap_a constant text := $a$ if v_total>public.invoice_net_received(i.id) then raise exception 'Refund exceeds net payments still held'; end if;$a$;
  c_ref_cap_r constant text := $r$ if v_total>public.invoice_net_received(i.id) then raise exception 'Refund exceeds net payments still held'; end if;
 -- 417: on a cancelled invoice whose customer had part of it, no more than the
 -- amount stated as owed back; the rest is kept for what was used.
 if i.status='cancelled' and i.cancel_refund_owed is not null and v_total>i.cancel_refund_owed then
   raise exception 'That is more than the S$% still owed back on %. The rest is kept for what the customer used. Nothing was recorded.',
     to_char(i.cancel_refund_owed,'FM999999990.00'), i.invoice_no; end if;$r$;

  c_ref_owed_a constant text := $a$ update public.invoices set paid_amount=public.invoice_net_received(i.id),$a$;
  c_ref_owed_r constant text := $r$ -- 417: what is recorded here comes off the amount still owed back.
 update public.invoices set cancel_refund_owed=case when status='cancelled' and cancel_refund_owed is not null
                                                    then greatest(cancel_refund_owed-v_total,0) else cancel_refund_owed end,
   paid_amount=public.invoice_net_received(i.id),$r$;

  c_ref_close_a constant text := $a$   perform public.writeoff_released_credit_on_close(i.id, p_reason, 'refund');$a$;
  c_ref_close_r constant text := $r$   perform public.writeoff_released_credit_on_close(i.id, p_reason, 'refund');
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
   end if;$r$;

  -- cancel_invoice_recorded: 363's therapy rules (keeping 410's dates); 417
  -- clears a stale amount owed back.
  c_can_decl_a constant text := $a$declare i public.invoices%rowtype; v_lot record; v_rev int; r record;$a$;
  c_can_decl_r constant text := $r$declare i public.invoices%rowtype; v_lot record; v_rev int; r record; v363_used text;$r$;

  c_can_lock_a constant text := $a$ if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;$a$;
  c_can_lock_r constant text := $r$ if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 -- 363: every therapy unit on the invoice and its voucher allowance are locked
 -- before any voucher stock is touched, in the order the Claim window takes
 -- them (unit, allowance, stock).
 perform 1 from public.purchased_therapy_entitlements
   where invoice_id=i.id and status not in ('cancelled','refunded') order by id for update;
 perform 1 from public.therapy_entitlements te
   where te.id in (select voucher_entitlement_id from public.purchased_therapy_entitlements
                    where invoice_id=i.id and status not in ('cancelled','refunded'))
   order by te.id for update;$r$;

  c_can_therapy_a constant text := $a$ update public.purchased_therapy_entitlements set status='refunded',updated_at=now() where invoice_id=i.id and status in ('pending_activation','scheduled')
   and public.purchased_therapy_status_on(status,activation_date,expiry_date,activation_deadline,public.sg_today()) in ('pending_activation','scheduled');$a$;
  c_can_therapy_r constant text := $r$ -- 363 (the Owner, 9 Oct 2026, rule 3): therapy on a line that has been used
 -- (started or ended, by its dates too (410), or vouchers collected) ends
 -- only on an Owner or Manager's authorization with an amount, which
 -- Refund / Cancel records before it gets here. It is not closed as if
 -- unused, and the invoice is not cancelled around it while it keeps
 -- running. A used unit no line holds (a correction deleted its line) is
 -- left as it is, as before. The units and their allowances were locked at
 -- the start.
 select string_agg(entitlement_no,', ' order by entitlement_no) into v363_used
   from public.purchased_therapy_entitlements
  where invoice_id=i.id and invoice_item_id is not null and status not in ('cancelled','refunded')
    and public.therapy_unit_consumed(id);
 if v363_used is not null then
   raise exception 'Therapy from this invoice has been started or has ended, or vouchers from it were collected (%). Cancel it with Refund / Cancel on the invoice, where an Owner or Manager authorizes ending it and states the amount.', v363_used; end if;
 update public.purchased_therapy_entitlements set status='refunded',updated_at=now() where invoice_id=i.id and status in ('pending_activation','scheduled')
   and public.purchased_therapy_status_on(status,activation_date,expiry_date,activation_deadline,public.sg_today()) in ('pending_activation','scheduled')
   and not public.therapy_unit_consumed(id);$r$;

  -- 417: limited voucher stock went back twice when the invoice was paid
  -- through Record Payment: once with each voucher the customer still held
  -- (the loop above) and again for the invoice's voucher movements (8 to 12
  -- for 2 sold, where it should be 8 to 10).
  c_can_vstock_a constant text := $a$ for r in select store_id,voucher_id,sum(quantity)::int quantity from public.invoice_voucher_movements where invoice_id=i.id group by store_id,voucher_id having sum(quantity)>0 loop
  update public.voucher_store_stock set current_qty=current_qty+r.quantity where store_id=r.store_id and voucher_id=r.voucher_id;
  insert into public.invoice_voucher_movements(invoice_id,store_id,voucher_id,quantity,reason,created_by) values(i.id,r.store_id,r.voucher_id,-r.quantity,'Cancellation: '||p_reason,auth.uid());
 end loop;$a$;
  c_can_vstock_r constant text := $r$ -- 417: limited voucher stock goes back once. The units this invoice issued
 -- to the customer as vouchers came back above, with the vouchers (the
 -- unused ones; used ones stay out), however their stock was taken: Record
 -- Payment's movements, Confirm FOC, a credit package or a bundle. The
 -- invoice's own voucher movements give back, and record, only what it took
 -- and never issued (no customer to issue to, say), as a refund does. The
 -- rest stays on the movements, so a reopening takes again only the units it
 -- issues again. Both are counted by voucher, not by store: a voucher moved
 -- to another store (an Owner's transfer, or a correction of the invoice's
 -- store and customer) leaves its rows where its stock was taken. The units
 -- issued are counted along each voucher's own chain: what each voucher the
 -- invoice gave, gave again or moved (sale, promotion, reopening, transfer)
 -- was granted, less what a later reopening gave again in its place or a
 -- transfer moved on. So a voucher given again counts once, and a line
 -- lowered or raised after it was paid changes nothing here. What is left
 -- goes back at the stores its rows are at, the invoice's store first.
 for r in with m as (select store_id,voucher_id,sum(quantity)::int quantity from public.invoice_voucher_movements
                      where invoice_id=i.id group by store_id,voucher_id having sum(quantity)>0),
               t as (select x.voucher_id,
                       greatest(coalesce((select sum(mv.quantity) from public.invoice_voucher_movements mv
                                           where mv.invoice_id=i.id and mv.voucher_id=x.voucher_id),0)
                                -coalesce((select sum(greatest(b.granted_value
                                            -coalesce((select sum(q.quantity) from public.invoice_reopen_vouchers q
                                                        where q.benefit_id=b.id and q.applied_at is not null),0)
                                            -coalesce((select sum(t.transferred_value) from public.invoice_benefit_transfers t
                                                        where t.source_benefit_id=b.id and t.replacement_benefit_id is not null),0),0))
                                            from public.invoice_benefit_values b
                                            join public.customer_reward_vouchers v on v.id=b.reward_voucher_id
                                           where b.invoice_id=i.id and v.voucher_id=x.voucher_id
                                             and v.source_type in ('invoice_voucher_sale','invoice_promotion_voucher','invoice_reopen','invoice_benefit_transfer')),0),0) as back
                       from (select distinct voucher_id from m) x),
               d as (select m.store_id,m.voucher_id,m.quantity,t.back,
                            coalesce(sum(m.quantity) over (partition by m.voucher_id order by (m.store_id<>i.store_id),m.store_id
                              rows between unbounded preceding and 1 preceding),0) as before
                       from m join t on t.voucher_id=m.voucher_id)
          select d.store_id,d.voucher_id,least(d.quantity,greatest(d.back-d.before,0))::int quantity from d loop
  continue when r.quantity<=0;
  update public.voucher_store_stock set current_qty=current_qty+r.quantity where store_id=r.store_id and voucher_id=r.voucher_id;
  insert into public.invoice_voucher_movements(invoice_id,store_id,voucher_id,quantity,reason,created_by) values(i.id,r.store_id,r.voucher_id,-r.quantity,'Cancellation: '||p_reason,auth.uid());
 end loop;$r$;

  c_can_owed_a constant text := $a$ update public.invoices set status='cancelled',edited_by=auth.uid(),edited_at=now(),edit_count=coalesce(edit_count,0)+1 where id=i.id;$a$;
  c_can_owed_r constant text := $r$ -- 417: an amount owed back stated at an earlier cancellation (before a
 -- reopening) does not carry over; Refund / Cancel states it again.
 update public.invoices set status='cancelled',edited_by=auth.uid(),edited_at=now(),edit_count=coalesce(edit_count,0)+1,
   cancel_refund_owed=null where id=i.id;$r$;

  -- invoice_financial_position: the refund due follows the amount stated.
  c_pos_a constant text := $a$ 'refund_due',greatest(n-charge,0),'overpayment_refundable',greatest(n-i.total_amount,0),$a$;
  c_pos_r constant text := $r$ -- 417 (the Owner, 9 Oct 2026): a cancelled invoice whose customer had part
 -- of it owes back only what the Owner or Manager stated when cancelling,
 -- less what was recorded since; the rest is kept for what was used.
 'refund_due',case when i.status='cancelled' and i.cancel_refund_owed is not null
                   then least(greatest(n-charge,0),i.cancel_refund_owed) else greatest(n-charge,0) end,
 'refund_owed_stated',i.status='cancelled' and i.cancel_refund_owed is not null,
 'kept_for_used',case when i.status='cancelled' and i.cancel_refund_owed is not null
                      then greatest(n-charge-i.cancel_refund_owed,0) else 0 end,
 'overpayment_refundable',greatest(n-i.total_amount,0),$r$;

  -- reopen_invoice: rule 5, a reopening takes voucher stock once.
  c_reo_decl_a constant text := $a$declare i public.invoices%rowtype; p jsonb; n numeric; v_rev int; v_status invoice_status;$a$;
  c_reo_decl_r constant text := $r$declare i public.invoices%rowtype; p jsonb; n numeric; v_rev int; v_status invoice_status; v417 record;$r$;
  c_reo_queue_a constant text := $a$ insert into public.invoice_reopen_vouchers(invoice_id,benefit_id,request_id,quantity)
 select i.id,c.benefit_id,p_request_id,c.quantity from public.invoice_voucher_reopen_candidates(i.id) c where c.quantity>0;$a$;
  c_reo_queue_r constant text := $r$ -- 417 (the Owner, 9 Oct 2026): units an earlier reopening queued, and still
 -- waiting because the invoice was cancelled again before it was settled,
 -- are given with this one. Only what is more is queued, so each unit is
 -- given, and its stock taken, once. Before, both were given.
 insert into public.invoice_reopen_vouchers(invoice_id,benefit_id,request_id,quantity)
 select i.id,c.benefit_id,p_request_id,c.quantity-coalesce(w.quantity,0)
   from public.invoice_voucher_reopen_candidates(i.id) c
   left join (select q.benefit_id,sum(q.quantity)::int as quantity from public.invoice_reopen_vouchers q
               where q.invoice_id=i.id and q.applied_at is null group by q.benefit_id) w on w.benefit_id=c.benefit_id
  where c.quantity-coalesce(w.quantity,0)>0;$r$;
  c_reo_take_a constant text := $a$ if v_status in ('paid','completed_foc') then perform public.deduct_invoice_stock(i.id,'Explicit invoice reopening: '||p_reason); end if;$a$;
  c_reo_take_r constant text := $r$ -- 417 (the Owner, 9 Oct 2026): a reopening takes voucher stock once. The
 -- vouchers it gives again take their stock when the invoice is settled
 -- (invoice_reopen_vouchers_settled), and deduct_invoice_stock takes what the
 -- movement rows do not record. A paid invoice's rows record every unit it
 -- gave. A completed FOC invoice's do not (Confirm FOC takes the stock with
 -- no row), nor do they once the FOC was taken off (the unused units went
 -- back with a row, kept to give again). So those units are recorded first,
 -- moving no stock. Before, they were taken twice.
 for v417 in select * from public.invoice_voucher_stock_unrecorded(i.id,false) loop
  insert into public.invoice_voucher_movements(invoice_id,voucher_id,store_id,quantity,reason,created_by)
   values(i.id,v417.voucher_id,v417.store_id,v417.quantity,
    'Recorded on reopening, so the stock of these vouchers is taken once: '||p_reason,auth.uid());
 end loop;
 if v_status in ('paid','completed_foc') then perform public.deduct_invoice_stock(i.id,'Explicit invoice reopening: '||p_reason); end if;$r$;

  -- invoice_reopen_preview_before_sessions: the stock to issue follows rule 5.
  c_rpv_a constant text := $a$ from public.invoice_stock_to_deduct(i.id) s where s.quantity>0),$a$;
  c_rpv_r constant text := $r$ from (select t.kind,t.item_id,(t.quantity-case when t.kind='product' then 0 else coalesce((select sum(u.quantity)
          -- 417: less the units reopen_invoice records as taken already, moving no
          -- stock (a completed FOC invoice's vouchers, or those kept to give again).
          from public.invoice_voucher_stock_unrecorded(i.id,true) u where u.voucher_id=t.item_id),0) end)::int as quantity
         from public.invoice_stock_to_deduct(i.id) t) s where s.quantity>0),$r$;
  c_rpv_units_a constant text := $a$'voucher_units_to_reinstate_after_settlement',(select coalesce(sum(quantity),0) from public.invoice_voucher_reopen_candidates(i.id)),$a$;
  c_rpv_units_r constant text := $r$'voucher_units_to_reinstate_after_settlement',
   -- 417: with the units an earlier reopening queued that are still waiting
   -- (reopen_invoice gives those, or more if there are more to give).
   (select coalesce(sum(greatest(c.quantity,coalesce((select sum(q.quantity) from public.invoice_reopen_vouchers q
      where q.invoice_id=i.id and q.benefit_id=c.benefit_id and q.applied_at is null),0))),0)
      from public.invoice_voucher_reopen_candidates(i.id) c),$r$;

  -- move_invoice_benefits_to_customer: a correction that moves an invoice to
  -- another store moves its vouchers' stock with them.
  c_move_decl_a constant text := $a$declare v_blocked text; v_v int := 0; v_c int := 0; v_a int := 0; v_wallet uuid;$a$;
  c_move_decl_r constant text := $r$declare v_blocked text; v_v int := 0; v_c int := 0; v_a int := 0; v_wallet uuid; v417 record;$r$;
  c_move_stock_a constant text := $a$  update public.customer_reward_vouchers
     set customer_id = p_customer_id, store_id = p_store_id$a$;
  c_move_stock_r constant text := $r$  -- 417: the stock of a limited voucher moves with it to the new store, as
  -- an Owner's move of one voucher (transfer_invoice_unused_benefit) moves
  -- it: taken at the new store, given back at the old one. Before, the
  -- vouchers moved and their stock stayed, so a later cancellation gave it
  -- back at the new store and the old one stayed short. The vouchers are
  -- locked first, so none is used in between.
  perform 1 from public.customer_reward_vouchers
   where source_type in ('invoice_voucher_sale','invoice_promotion_voucher')
     and source_id in (select id from public.invoice_items where invoice_id = p_invoice_id)
     and status = 'held' and redeemed_at is null
   order by id for update;
  for v417 in
    select rv.voucher_id, rv.store_id, sum(rv.quantity)::int as quantity
      from public.customer_reward_vouchers rv
      join public.vouchers vo on vo.id = rv.voucher_id and vo.qty_type = 'limited'
     where rv.source_type in ('invoice_voucher_sale','invoice_promotion_voucher')
       and rv.source_id in (select id from public.invoice_items where invoice_id = p_invoice_id)
       and rv.status = 'held' and rv.redeemed_at is null
       and p_store_id is not null and rv.store_id is not null and rv.store_id <> p_store_id
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
     set customer_id = p_customer_id, store_id = p_store_id$r$;

  -- ══ md5s (pg_get_functiondef, search_path public) ══════════════════════════
  c_plan_after     constant text := 'e117890fac11ea11435b691ca4787dec';
  c_res_after      constant text := '201f08ebf14a64cd88d411a7cfb4c9c4';
  c_req_after      constant text := '4360d74462ed1fc950b6bd8b5157b3ae';
  c_ref_after      constant text := 'e6f6c3cbf1bda3574d748bde2db5a759';
  c_can_after      constant text := 'de52d9dbaef8ab15163bef35cb9d733d';
  c_pos_after      constant text := 'ba7eccbfeff217c8b1969b0e55a010ca';
  c_receive_after  constant text := '362b0175b60e12c97e427b5180e01960';
  c_awaiting_after constant text := '07621bd5ba0b8be5cf69460ac4212017';
  c_close_after    constant text := '5d79476632fe31145a903d0f267cfafc';
  c_status_after   constant text := '3930f9e6de6a53de9bb78302e7fc37e2';
  c_delete_after   constant text := '530b8217e94c9bbb0765c47da2d8d40e';
  c_delete_old     constant text := '5b09daf60b404444618197c478842d4a';
  c_reopen_after   constant text := 'c9fcab7adfccdaeba1eb8dee4134ba47';
  c_rpv_after      constant text := '4723b49b3f27c17254c2987c4bebc17b';
  c_focv_after     constant text := '91c8f0fa69ef6337f323b7ac467a8c2b';
  c_move_after     constant text := '2c01c460d3af8edd3ad86332aa286ed8';
  -- Functions this adds, the service role's alone (339), and the ones staff call.
  c_internal constant text[] := array['close_invoice_therapy_units(uuid,uuid,uuid[],jsonb,numeric,text,uuid,text)',
                                      'invoice_voucher_stock_unrecorded(uuid,boolean)'];
  c_client   constant text[] := array['invoice_request_status(uuid)', 'delete_invoice(uuid,text)'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  r record; d text; v text; n int; k int; i int; v_bad text; v_report text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[]; v_col_new boolean;
  -- the behaviour check
  v_owner uuid; v_staff uuid; v_store uuid; v_cust uuid; v_inv uuid; v_foc uuid; v_req jsonb; v_st jsonb;
  v_vch uuid; v_item uuid; v_rv uuid;
begin
  -- The definitions are read and compared with public alone on the search
  -- path, as they were read on 9 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── Guards: nothing changes unless all pass ─────────────────────────────
  -- invoices.cancel_refund_owed: missing, or already as this makes it.
  select format_type(a.atttypid, a.atttypmod) into v from pg_attribute a
   where a.attrelid = 'public.invoices'::regclass and a.attname = 'cancel_refund_owed' and not a.attisdropped;
  v_col_new := v is null;
  if not v_col_new and (v <> 'numeric(12,2)'
     or not exists (select 1 from pg_constraint c where c.conrelid = 'public.invoices'::regclass
                     and c.conname = 'invoices_cancel_refund_owed_check'
                     and pg_get_constraintdef(c.oid) = 'CHECK ((cancel_refund_owed >= (0)::numeric))')) then
    raise exception '417: public.invoices.cancel_refund_owed exists but is not this migration''s (%)', v; end if;

  -- Each function changed or added: the production version read on 9 Oct
  -- 2026 (BEFORE), or already this migration's (AFTER, left alone), or, for
  -- a new one, missing. Every anchor is found exactly once, and every text
  -- built is the tested one.
  for r in select * from (values
    ('close_invoice_therapy_units(uuid,uuid,uuid[],jsonb,numeric,text,uuid,text)', null::text, c_close_after, c_close_def, null::text[]),
    ('invoice_voucher_stock_unrecorded(uuid,boolean)', null::text, c_focv_after, c_focv_def, null::text[]),
    ('reopen_invoice(uuid,text,uuid)', '64cdf1f76339f7b9c0676b3411e84a83', c_reopen_after, null::text,
     array[[c_reo_decl_a, c_reo_decl_r], [c_reo_queue_a, c_reo_queue_r], [c_reo_take_a, c_reo_take_r]]),
    ('invoice_reopen_preview_before_sessions(uuid)', '17d22eaa8e84a73ad62fd18e0da93ebd', c_rpv_after, null::text,
     array[[c_rpv_units_a, c_rpv_units_r], [c_rpv_a, c_rpv_r]]),
    ('invoice_action_plan(uuid,text,jsonb)', '1c8fa5626062d09ba0cc1a4dca9d0e93', c_plan_after, null::text,
     array[[c_plan_decl_a, c_plan_decl_r], [c_plan_skip_a, c_plan_skip_r], [c_plan_units_a, c_plan_units_r],
           [c_plan_line_a, c_plan_line_r], [c_plan_money_a, c_plan_money_r], [c_plan_reward_a, c_plan_reward_r],
           [c_plan_summary_a, c_plan_summary_r], [c_plan_effects_a, c_plan_effects_r],
           [c_plan_result_a, c_plan_result_r], [c_plan_hash_a, c_plan_hash_r]]),
    ('invoice_financial_position(uuid)', '8751b7a8749452b0513e475b7fdb05ce', c_pos_after, null::text,
     array[[c_pos_a, c_pos_r]]),
    ('refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)', 'b0a99345c0f2e635391ac1c251634d95', c_ref_after, null::text,
     array[[c_ref_lock_a, c_ref_lock_r], [c_ref_used_a, c_ref_used_r], [c_ref_promo_a, c_ref_promo_r],
           [c_ref_cap_a, c_ref_cap_r], [c_ref_owed_a, c_ref_owed_r], [c_ref_close_a, c_ref_close_r]]),
    ('cancel_invoice_recorded(uuid,text,uuid)', 'e8ce9cc4f62896bff144893fdc42225d', c_can_after, null::text,
     array[[c_can_decl_a, c_can_decl_r], [c_can_lock_a, c_can_lock_r], [c_can_therapy_a, c_can_therapy_r],
           [c_can_vstock_a, c_can_vstock_r], [c_can_owed_a, c_can_owed_r]]),
    ('resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)', '87c838d9ef9e23f8e2cc9ef8c60b0787', c_res_after, null::text,
     array[[c_res_decl_a, c_res_decl_r], [c_res_reject_a, c_res_reject_r], [c_res_missing_a, c_res_missing_r],
           [c_res_lines_a, c_res_lines_r], [c_res_close_a, c_res_close_r], [c_res_cancel_a, c_res_cancel_r],
           [c_res_payload_a, c_res_payload_r], [c_res_due_a, c_res_due_r]]),
    ('request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)', '765a7a0629df4b591ca6718a6c171224', c_req_after, null::text,
     array[[c_req_replay_a, c_req_replay_r], [c_req_race_a, c_req_race_r]]),
    ('move_invoice_benefits_to_customer(uuid,uuid,uuid,text)', '33bc04a081f0f199fca2cbb3d3e1ed3e', c_move_after, null::text,
     array[[c_move_decl_a, c_move_decl_r], [c_move_stock_a, c_move_stock_r]]),
    ('receive_returned_rental(uuid,uuid,text,text,uuid)', 'a58778ccc5defa49d6fefe7a96b7b805', c_receive_after, c_receive_def, null::text[]),
    ('invoice_rentals_awaiting_return(uuid)', 'd2fe77eb5b2324e27f460e217f678e78', c_awaiting_after, c_awaiting_def, null::text[]),
    ('invoice_request_status(uuid)', null::text, c_status_after, c_status_def, null::text[]),
    ('delete_invoice(uuid,text)', null::text, c_delete_after, c_delete_def, null::text[])
  ) x(fn, before_md5, after_md5, whole, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      if r.before_md5 is not null then
        raise exception '417: public.% is missing', r.fn; end if;
      d := r.whole;
    else
      d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
      v := md5(d);
      if v = r.after_md5 then
        raise notice '417: public.% is already this version; left alone', r.fn;
        continue;
      elsif r.before_md5 is null then
        raise exception '417: public.% already exists with another text (md5 %). Re-read it and re-test before applying.', r.fn, v;
      elsif v <> r.before_md5 then
        raise exception '417: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
      end if;
      if r.edits is null then
        d := r.whole;
      else
        for k in 1 .. array_length(r.edits, 1) loop
          n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
          if n <> 1 then
            raise exception '417: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
          d := replace(d, r.edits[k][1], r.edits[k][2]);
        end loop;
      end if;
    end if;
    if md5(d) <> r.after_md5 then
      v_report := concat_ws('; ', v_report, r.fn || ' ' || md5(d));
    end if;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;
  if v_report is not null then
    raise exception '417: a text built is not the tested one: %', v_report; end if;

  -- The old one-argument delete_invoice: the production version, or gone.
  if to_regprocedure('public.delete_invoice(uuid)') is not null then
    if md5(pg_get_functiondef(to_regprocedure('public.delete_invoice(uuid)'))) <> c_delete_old then
      raise exception '417: public.delete_invoice(uuid) is not the version read on 9 Oct 2026. Re-read it from production and re-test before applying.'; end if;
  end if;

  -- Relied on, not changed: the versions read on 9 Oct 2026.
  for r in select * from (values
    ('resolve_invoice_credit_rewards(uuid,text,uuid,boolean,uuid)', '828a4b535604aef1314f55453d67f6e2'),
    ('assert_invoice_credit_source_evidence(uuid,uuid)', '64059b05526f32239ce1e60c6de39508'),
    ('credit_package_reward_group(uuid)', '7f8ac1b8bdc369110be03c8e9d260942'),
    ('cancelled_invoice_used_value(uuid)', '70f684f1a8f0a4f42774394062e4df19'),
    ('invoice_net_received(uuid)', 'f256bea69b7defa38a950753bbc248da'),
    ('therapy_unit_consumed(uuid)', '9ea1884a2357c1af7f0e9c82a85c73e3'),
    ('purchased_therapy_status_on(text,date,date,date,date)', '991ec75f0349f61ef1a2f3682fb142b1'),
    ('revoke_therapy_unit_benefit(uuid,text)', '5b186266e1098bea30a493796eb1fc59'),
    ('invoice_line_stock_products(uuid)', '5ed49163d183fa5ec05673a1bb85e863'),
    ('rental_awaiting_return(uuid)', '88ba77463d293bc77fba5e5cad3d3210'),
    ('rental_put_back_stock(uuid)', '8ca55272c76c62b295d5001b0943e85a'),
    ('trg_rental_stock_back()', 'a75c600cd86edc5b43fb464a5bfe34a8'),
    ('invoice_goods_out(uuid)', '15ffed0ff0d5d9cc5685af8e834302ae'),
    ('require_active_staff(text[])', '877b3aa74cea559881979bb161c450e2'),
    ('require_store_access(uuid)', 'f9332fd2f0092337d64501d8a647c23f'),
    ('write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'c705c733e213a27f0dc32d54322cc855'),
    -- Rule 5: a reopening takes what the invoice's movement rows do not
    -- cover, and the trigger takes the stock of each voucher given again.
    ('deduct_invoice_stock(uuid,text)', '32183fe9e7c15ed0b11307c48289831a'),
    ('invoice_stock_to_deduct(uuid)', '6356494ccb8545d46c56b788f8f85f54'),
    ('apply_reopened_invoice_vouchers()', '71d50be41b73decceb0b20f8597dd4fa'),
    ('invoice_voucher_reopen_candidates(uuid)', '20405a96c8780eac6425a5dae59c29e1')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '417: public.% is missing or not the version read on 9 Oct 2026. Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;
  -- Rule 5: the trigger that gives a reopened invoice's vouchers again, and
  -- takes their stock, is the one read on 9 Oct 2026.
  if (select pg_get_triggerdef(t.oid) from pg_trigger t
       where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'invoice_reopen_vouchers_settled' and t.tgenabled = 'O')
     is distinct from 'CREATE TRIGGER invoice_reopen_vouchers_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_vouchers()' then
    raise exception '417: the trigger invoice_reopen_vouchers_settled on public.invoices is not the one read on 9 Oct 2026'; end if;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('close_invoice_therapy_units', 'invoice_action_plan', 'invoice_financial_position',
                       'refund_invoice_recorded', 'cancel_invoice_recorded', 'resolve_invoice_action_v2',
                       'request_invoice_action_v2', 'receive_returned_rental', 'invoice_rentals_awaiting_return',
                       'invoice_request_status', 'delete_invoice', 'invoice_voucher_stock_unrecorded',
                       'reopen_invoice', 'invoice_reopen_preview_before_sessions', 'move_invoice_benefits_to_customer')
     and p.oid::regprocedure::text not in (
       'close_invoice_therapy_units(uuid,uuid,uuid[],jsonb,numeric,text,uuid,text)', 'invoice_action_plan(uuid,text,jsonb)',
       'invoice_financial_position(uuid)', 'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
       'cancel_invoice_recorded(uuid,text,uuid)', 'resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)',
       'request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)', 'receive_returned_rental(uuid,uuid,text,text,uuid)',
       'invoice_rentals_awaiting_return(uuid)', 'invoice_request_status(uuid)', 'delete_invoice(uuid,text)',
       'delete_invoice(uuid)', 'invoice_voucher_stock_unrecorded(uuid,boolean)', 'reopen_invoice(uuid,text,uuid)',
       'invoice_reopen_preview_before_sessions(uuid)', 'move_invoice_benefits_to_customer(uuid,uuid,uuid,text)');
  if v_bad is not null then
    raise exception '417: another overload of a function this changes exists: %', v_bad; end if;

  -- A request waiting now is asked to be confirmed again: the plan's hash
  -- changes with this (there were none on 9 Oct 2026).
  select count(*) into n from public.approval_requests
   where request_type in ('invoice_cancel', 'invoice_refund') and status = 'pending';
  if n > 0 then
    raise notice '417: % invoice request(s) are waiting; each will show its revised effects to confirm again', n; end if;

  -- The grants of the functions changed, to compare after.
  select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
    into v_acl
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.oid::regprocedure::text in (
       'invoice_action_plan(uuid,text,jsonb)', 'invoice_financial_position(uuid)',
       'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)', 'cancel_invoice_recorded(uuid,text,uuid)',
       'resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)',
       'request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)', 'receive_returned_rental(uuid,uuid,text,text,uuid)',
       'invoice_rentals_awaiting_return(uuid)', 'reopen_invoice(uuid,text,uuid)',
       'invoice_reopen_preview_before_sessions(uuid)', 'move_invoice_benefits_to_customer(uuid,uuid,uuid,text)');

  -- ── Change ───────────────────────────────────────────────────────────────
  if v_col_new then
    alter table public.invoices add column cancel_refund_owed numeric(12,2);
    alter table public.invoices add constraint invoices_cancel_refund_owed_check check (cancel_refund_owed >= 0);
    comment on column public.invoices.cancel_refund_owed is
      '417: on a cancelled invoice whose customer had part of it, the money still owed back, as the Owner or Manager stated it when cancelling, less refunds recorded since. Null: not stated (all the money held is owed back).';
  end if;
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
    if v_fns[i] = any(c_internal) then
      execute format('revoke all on function public.%s from public, anon, authenticated', v_fns[i]);
      execute format('grant execute on function public.%s to service_role', v_fns[i]);
    elsif v_fns[i] = any(c_client) then
      execute format('revoke all on function public.%s from public, anon', v_fns[i]);
      execute format('grant execute on function public.%s to authenticated, service_role', v_fns[i]);
    end if;
  end loop;
  -- The one-argument delete_invoice goes in the same release: it took no
  -- reason, and two functions of one name confuse the API.
  if to_regprocedure('public.delete_invoice(uuid)') is not null then
    drop function public.delete_invoice(uuid);
  end if;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  for r in select * from (values
    ('close_invoice_therapy_units(uuid,uuid,uuid[],jsonb,numeric,text,uuid,text)', c_close_after),
    ('invoice_action_plan(uuid,text,jsonb)', c_plan_after),
    ('invoice_financial_position(uuid)', c_pos_after),
    ('refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)', c_ref_after),
    ('cancel_invoice_recorded(uuid,text,uuid)', c_can_after),
    ('resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)', c_res_after),
    ('request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)', c_req_after),
    ('receive_returned_rental(uuid,uuid,text,text,uuid)', c_receive_after),
    ('invoice_rentals_awaiting_return(uuid)', c_awaiting_after),
    ('invoice_request_status(uuid)', c_status_after),
    ('delete_invoice(uuid,text)', c_delete_after),
    ('invoice_voucher_stock_unrecorded(uuid,boolean)', c_focv_after),
    ('reopen_invoice(uuid,text,uuid)', c_reopen_after),
    ('invoice_reopen_preview_before_sessions(uuid)', c_rpv_after),
    ('move_invoice_benefits_to_customer(uuid,uuid,uuid,text)', c_move_after)) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '417: installed with md5s other than the tested ones: %', v_bad; end if;
  if to_regprocedure('public.delete_invoice(uuid)') is not null then
    raise exception '417: the one-argument delete_invoice is still there'; end if;
  if (select format_type(a.atttypid, a.atttypmod) from pg_attribute a
       where a.attrelid = 'public.invoices'::regclass and a.attname = 'cancel_refund_owed' and not a.attisdropped)
     is distinct from 'numeric(12,2)' then
    raise exception '417: public.invoices.cancel_refund_owed is not as tested'; end if;

  -- ── Grants, by the catalogue ─────────────────────────────────────────────
  if (select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
        from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.oid::regprocedure::text in (
           'invoice_action_plan(uuid,text,jsonb)', 'invoice_financial_position(uuid)',
           'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)', 'cancel_invoice_recorded(uuid,text,uuid)',
           'resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)',
           'request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)', 'receive_returned_rental(uuid,uuid,text,text,uuid)',
           'invoice_rentals_awaiting_return(uuid)', 'reopen_invoice(uuid,text,uuid)',
           'invoice_reopen_preview_before_sessions(uuid)', 'move_invoice_benefits_to_customer(uuid,uuid,uuid,text)'))
     is distinct from v_acl then
    raise exception '417: the grants of the changed functions changed'; end if;
  foreach v in array c_internal loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '417: public.% is not the service role''s alone', v; end if;
  end loop;
  foreach v in array c_client loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or not has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '417: public.% is not for signed-in staff and the service role only', v; end if;
  end loop;

  -- ── Behaviour, inside a block that is always undone ─────────────────────
  -- A made-up Owner and member of staff (@sig.invalid) at a made-up store, an
  -- unpaid invoice and a completed FOC one. Nothing is printed and no row
  -- remains.
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    insert into auth.users (id, email) values (gen_random_uuid(), '417-check-owner-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_owner;
    insert into auth.users (id, email) values (gen_random_uuid(), '417-check-staff-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_staff;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '417 check', u.email, x.role::public.user_role, true
      from auth.users u join (values (v_owner, 'owner'), (v_staff, 'staff')) x(id, role) on x.id = u.id;
    insert into public.stores (name, code, country_code)
      values ('417 check', '417-' || substr(md5(gen_random_uuid()::text), 1, 8), 'SG') returning id into v_store;
    insert into public.user_store_assignments (user_id, store_id) values (v_staff, v_store);
    -- A valid phone no customer has: a number kept for fiction (ACMA), never
    -- a real person's.
    select c.p into v from (values ('+61491570006'), ('+61491570156'), ('+61491570157'), ('+61491570737'),
                                   ('+61491571266'), ('+61491572549'), ('+61491572665'), ('+61491572983'),
                                   ('+61491573087'), ('+61491573770'), ('+61491574118'), ('+61491574632')) c(p)
     where public.normalize_customer_phone(c.p) = c.p
       and not exists (select 1 from public.customers cu where cu.phone = c.p) limit 1;
    insert into public.customers (full_name, phone) values ('417 check', v) returning id into v_cust;
    insert into public.invoices (invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, business_date)
      values ('417-CHECK-' || substr(md5(gen_random_uuid()::text), 1, 8), v_store, v_cust, v_owner, 'unpaid', 0, 0, public.sg_today())
      returning id into v_inv;
    insert into public.invoices (invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, business_date)
      values ('417-CHECK-' || substr(md5(gen_random_uuid()::text), 1, 8), v_store, v_cust, v_owner, 'completed_foc', 0, 0, public.sg_today())
      returning id into v_foc;

    -- Staff: a request, its status on the invoice, a replay of another request.
    perform set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
    v_req := public.request_invoice_action_v2(v_inv, 'cancel', '[]'::jsonb, '417 check', null, v_owner);
    v_st := public.invoice_request_status(v_inv);
    if not coalesce((v_st->>'pending')::boolean, false) or (v_st->>'can_review')::boolean
       or v_st#>>'{request,request_id}' is distinct from v_req->>'request_id' or v_st->'request' ? 'reason' then
      raise exception '417: the waiting request does not show on the invoice as it should (%)', v_st; end if;
    begin
      perform public.request_invoice_action_v2(v_inv, 'refund_full', '[]'::jsonb, '417 check', null, v_owner);
      raise exception '417: a request ID was replayed for a different request';
    exception when others then
      if sqlerrm not like 'This request ID was already used for a different request%' then raise; end if;
    end;
    begin
      perform public.request_invoice_action_v2(v_foc, 'cancel', '[]'::jsonb, '417 check', null, v_owner);
      raise exception '417: a request ID was replayed for another invoice';
    exception when others then
      if sqlerrm not like 'This request ID was already used for a different request%' then raise; end if;
    end;
    -- Owner: a rejection needs a reason, and the invoice shows it.
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    begin
      perform public.resolve_invoice_action_v2((v_req->>'request_id')::uuid, false, '   ');
      raise exception '417: a request was rejected with no reason';
    exception when others then
      if sqlerrm not like 'Give a reason for rejecting this request%' then raise; end if;
    end;
    perform public.resolve_invoice_action_v2((v_req->>'request_id')::uuid, false, '417 check: not needed');
    v_st := public.invoice_request_status(v_inv);
    if (v_st->>'pending')::boolean or v_st#>>'{request,rejection_reason}' is distinct from '417 check: not needed' then
      raise exception '417: the rejection does not show on the invoice (%)', v_st; end if;
    -- Staff: deleting needs a reason and keeps it; a completed FOC is refused.
    perform set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
    begin
      perform public.delete_invoice(v_inv, ' ');
      raise exception '417: an invoice was deleted with no reason';
    exception when others then
      if sqlerrm not like 'Give a short reason for deleting this invoice%' then raise; end if;
    end;
    begin
      perform public.delete_invoice(v_foc, '417 check');
      raise exception '417: a completed FOC invoice was deleted';
    exception when others then
      if sqlerrm not like '% is a completed FOC invoice, so it cannot be deleted%' then raise; end if;
    end;
    perform public.delete_invoice(v_inv, '417 check: made by mistake');
    if (select deleted_at from public.invoices where id = v_inv) is null
       or not exists (select 1 from public.audit_logs a where a.record_id = v_inv and a.action = 'invoice_deleted'
                       and a.reason = '417 check: made by mistake' and a.store_id = v_store and a.changed_by = v_staff) then
      raise exception '417: deleting an unpaid invoice did not keep its reason'; end if;
    perform public.delete_invoice(v_inv, '417 check: again');
    -- Rule 5: the 2 limited vouchers the made-up completed FOC invoice gave
    -- are found as not recorded on its movement rows, and no longer once a
    -- row records them.
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    insert into public.vouchers (name, code, voucher_kind, selling_price, qty_type, is_active)
      values ('417 check', '417-' || substr(md5(gen_random_uuid()::text), 1, 8), 'normal', 0, 'limited', false)
      returning id into v_vch;
    insert into public.invoice_items (invoice_id, line_kind, voucher_id, quantity, unit_price, line_total)
      values (v_foc, 'voucher', v_vch, 2, 0, 0) returning id into v_item;
    insert into public.customer_reward_vouchers (customer_id, voucher_id, store_id, quantity, status, source_type, source_id, notes)
      values (v_cust, v_vch, v_store, 2, 'held', 'invoice_voucher_sale', v_item, '417 check') returning id into v_rv;
    insert into public.invoice_benefit_values (invoice_id, invoice_item_id, reward_voucher_id, paid_value, granted_value, evidence)
      values (v_foc, v_item, v_rv, 0, 2, '417 check');
    if (select count(*) from public.invoice_voucher_stock_unrecorded(v_foc, false)) <> 1
       or (select u.quantity from public.invoice_voucher_stock_unrecorded(v_foc, false) u
            where u.store_id = v_store and u.voucher_id = v_vch) is distinct from 2 then
      raise exception '417: the vouchers a free invoice gave are not found as missing from its movement rows'; end if;
    insert into public.invoice_voucher_movements (invoice_id, voucher_id, store_id, quantity, reason, created_by)
      values (v_foc, v_vch, v_store, 2, '417 check', v_owner);
    if exists (select 1 from public.invoice_voucher_stock_unrecorded(v_foc, false)) then
      raise exception '417: voucher stock a movement row records is still counted as not recorded'; end if;
    -- A login that is not staff: refused.
    perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
    begin
      perform public.invoice_request_status(v_foc);
      raise exception '417: a login that is not staff read an invoice''s request';
    exception when insufficient_privilege then null;
    end;
    raise exception using errcode = 'P0417', message = '417: check done, undone';
  exception when sqlstate 'P0417' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
