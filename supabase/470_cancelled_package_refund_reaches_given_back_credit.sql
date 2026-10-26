-- 470_cancelled_package_refund_reaches_given_back_credit.sql
--
-- CREDIT A REFUNDED SALE GIVES BACK WHILE ITS PACKAGE IS CANCELLED, REFUNDED
-- OR WAITING FOR ITS REOPENING'S PAYMENT IS HELD BACK BY THE CANCELLATION FOR
-- WHOEVER HOLDS THE PACKAGE'S BENEFITS, ON THE LOT THE RECORDS NAME, SO A
-- REFUND BY LINE OF THE PACKAGE PAYS IT BACK AND ITS REOPENING'S PAYMENT
-- GIVES IT TO THEM (462's NOT COVERED 10, K7b; the Owner, 24 Oct 2026: "Go
-- live now, fix the gap next")
--
-- WHO FOUND IT
--
--   462's builders (its NOT COVERED 10 and its suite's KNOWN K7b, 24 Oct
--   2026). Reproduced on copies of production at 463 (6d96407c, 1387
--   functions, 466 and 467 in) with the siblings the Owner's task named and
--   those found on the way (this file's suite): made-up records, the app's
--   own calls, each followed by what its commit does. Two designs were built
--   and run against every suite listed below (WHY THIS WAY). Run again on
--   copies of production at 469 (f9d0ddcb, 26 Oct 2026; 468 and 469 changed
--   none of what this reads). A review (26 Oct 2026) found that the first
--   text of this file (AFTER 837a0aaa) added the credit drawn to the amount
--   owed back, which is money: on a S$100 + S$10 Bonus package, a Premium
--   Bundle or a discounted one S$20 of credit was owed back as S$20 where a
--   refund by line can pay back only S$18.18 or S$14.00, so after that
--   refund the Finance panel still showed S$1.82 or S$6.00 'Owed back' that
--   nothing could pay, and kept that much less for what was used; this text
--   adds the money (the suite's K7gcx, K7gcv, K7gcd and P2). The review's
--   other findings changed only this header: the figures of production now
--   (DEPLOY ORDER, BEFORE, AFTER), NOT COVERED 5 and SAFETY's locks.
--
-- WHAT WAS WRONG
--
--   462's forwarder (credit_given_back_follows) did nothing while the
--   package's invoice was cancelled, refunded, asked to be, or its reopening
--   waited, so credit a refunded sale gave back then stayed on the lot it
--   went back to; where a reissue (462's own forward, a customer change, a
--   merge, a reopening's payment) had replaced that lot, no record names it.
--   On copies, a S$100 package sold to A; two S$20 sessions paid from it; the
--   S$60 left moved by an Owner to F; a 'transfer' customer change to B; the
--   first session refunded (its S$20 forwarded to B):
--   * cancelled; the second session refunded while cancelled; a refund by
--     line of the package ('back 1 all'): S$80 of S$100 paid back, A keeps
--     S$20 spendable on a lot no record names (K7b; before 462 the full S$100
--     was paid back). The same with three sessions (S$40), a S$10 Bonus
--     package, the second session's wallet payment corrected to cash or to
--     S$5 less instead of refunded (S$20, S$5), the new holder merged into a
--     kept record before the cancel or while cancelled, a customer change
--     while cancelled, the holder deleted while cancelled, a special
--     document's credit refunded instead;
--   * the guided Cancel with "Record refund paid" (S$80 paid back, S$0 owed
--     after), then the second session refunded: A keeps S$20 on a lot no
--     record names, and nothing more can be paid back (K7gc);
--   * cancelled, F's S$60 refunded by line, reopened (it waits), the second
--     session refunded while it waits: A keeps S$20 while it waits and can
--     spend it, Cancel again and a refund by line leave it with A (K7wc), the
--     guided Refund in full leaves it with A (K7wg), and a refund by line
--     while it waits does not reach it (Z1w: paid, B then holds S$20 though
--     the line was refunded in full); the same with the session refunded
--     while cancelled before the reopening (Z1, Z2, Z5) or a merge while
--     cancelled (M1);
--   * Refund in full with an Owner's override (what was spent paid back too),
--     then the second session refunded: A keeps S$20 on a lot no record
--     names of a refunded invoice (RX1).
--   Nothing was lost while the package was reopened and paid in the end (the
--   payment gave it to the holder, X2p), but the package's refund paid back
--   short and the old customer could spend credit of a cancelled package.
--
-- THE OWNER'S ANSWERS
--
--   22 Oct 2026: credit follows a merge and a 'transfer' customer change; a
--   Move's recipient keeps what was moved; refunds paid back count as not
--   used. 24 Oct 2026: decision 1, credit a refunded sale gives back goes to
--   "B, the package's holder now", on the lot the records name; and for this
--   gap: a cancel or refund takes back what the invoice gave from whoever
--   holds it now; the customer holds exactly what the net payment buys;
--   nothing stranded on a lot no record names; Correct payment keeps
--   working; "Go live now, fix the gap next".
--
-- WHAT THIS DOES (one function changed, whole text; nothing added; no table,
-- column, trigger or grant changes)
--
--   credit_given_back_follows(uuid) (462's, with 463's holder rule). As
--   before, it runs at commit for each ledger row giving credit back on a lot
--   (462's deferred trigger on customer_credit_ledger, unchanged), and where
--   that lot is one an invoice's benefit row names or one such a lot
--   replaced, and something sits on a replaced lot or the named lot's holder
--   is not whoever holds the benefits now, it draws those lots down and
--   grants the holder ONE new lot the records name. What changes:
--   * While the invoice is cancelled or refunded, or a reopening of it waits
--     to be settled, it no longer does nothing. It forwards as above, but the
--     new lot is held back by the cancellation for the holder: it is granted
--     what is drawn plus what the cancellation already holds back for that
--     benefit row on the lots drawn (its 'invoice_cancel_benefit' ledger rows
--     there not given back by a reopening), and holds nothing; both are taken
--     back on it as the cancellation's own ledger rows ('adjust_decrease',
--     'invoice_cancel_benefit', the invoice; reason "Held back by the
--     invoice's cancellation for whoever holds its benefits now"). The
--     cancellation's rows it carries are closed where they were (a reopening
--     queue row, invoice_reopen_benefits, marked applied, as 446 closes a row
--     given in full; one not queued yet gets such a row, so no reopening
--     queues it again) and, where a reopening's payment waits for them,
--     queued again for the row taken on the new lot (same request, same
--     amount). While a reopening waits, what is drawn is queued for its
--     payment too (the latest waiting request). What is drawn is added to the
--     row's cancelled_unused_value and, on a cancelled invoice whose Owner or
--     Manager stated what is owed back (cancel_refund_owed), its money is
--     added to that: it was kept for credit that was spent, and is not spent
--     now. The money is what a refund by line of the row pays back for it:
--     the row's paid value for its granted credit, rounded on all the row
--     holds back before and after, as refund_invoice_recorded rounds it (S$20
--     of credit is S$20 on a S$100 package, S$18.18 on the S$100 + S$10 Bonus
--     package, S$14.00 on the S$140 Premium Bundle; the Audit Log row gives
--     both), so what is owed back is what the refund options offer and is
--     S$0 once the refund by line has paid it.
--     So everything the cancellation holds back for the row is on the lot
--     the records name, held by the benefits' holder: a refund by line of the
--     cancelled package pays it all back; a refund by line made while a
--     reopening waits finds it (446's matching reads the queue on that lot);
--     the reopening's payment gives it to the holder
--     (apply_reopened_invoice_benefits, unchanged); a merge or a customer
--     change has nothing spendable to move; Cancel again takes nothing more.
--   * A new lot this made and nothing touched since (its grant and these
--     held-back rows only) is replaced in place, as 462 does for its own
--     lots, so many such refunds keep the chain as it is (CH5: two lots down
--     after five).
--   * Asked to be cancelled or refunded (the legacy statuses
--     cancellation_requested and refund_requested, which the app's v2
--     requests no longer set): it follows as for a paid invoice (before,
--     nothing; credit then waited for the next refund that was forwarded).
--   Otherwise as 462 and 463 made it (while paid, to the holder, spendable;
--   nothing where the named lot alone holds it and its holder is the
--   benefits'). Correct payment is unchanged: the forwarder still runs at
--   commit, after the correction re-spends what it keeps.
--   Money afterwards (the suite, each case): the package's refund by line
--   pays back what was received less what is still spent; nobody holds
--   credit of a cancelled package; reopened and paid, the holder holds it;
--   nothing on a lot no record names; Cancel takes it all back.
--
-- WHY THIS WAY (the two ways the task named, and the two builds)
--
--   (a) Making the cancelled package's refund by line (and Cancel, "Record
--   refund paid", Refund in full) reach credit on a replaced lot needs
--   refund_invoice_recorded, cancel_invoice_recorded and the plans (their
--   checks read the named lot and what is held back, pinned by 446, 457,
--   458, 462, 463 and 464; the page's refund options read the same): not
--   changed. (b) The forwarder bringing the credit onto the lot the records
--   name. Spendable (as it lands on the package's own lot without a
--   reissue; the first build tried it): exact for the refund by line, but a
--   merge or a change of the holder while cancelled then reissues it without
--   the cancellation's rows, and a refund by line while a later reopening
--   waits gives it back twice (M1: K S$20 too many, as that build found). So
--   held back by the cancellation instead, with
--   what the cancellation already held on the lots drawn: 446, 448, 451, 460
--   and 462 count it as any cancellation's. Two builds of (b) were made:
--   * the first kept 462's rule of doing nothing while a reopening waits and
--     added a function and a DEFERRABLE INITIALLY DEFERRED constraint trigger
--     on invoices (on a status change of a reopened invoice) to sweep credit
--     given back during the wait when the reopening was paid or the invoice
--     closed again. It left credit given back during a wait spendable by the
--     old customer until then, out of reach of a refund by line made while it
--     waited (Z1w: B S$20 after the line was refunded in full) and of a guided
--     Refund in full of the waiting invoice (K7wg: A kept S$20); and while
--     its event is queued (a reopened invoice paid, cancelled or refunded,
--     until the commit) the same transaction cannot ALTER TABLE invoices
--     ("cannot ALTER TABLE "invoices" because it has pending trigger
--     events"), a trap for a later migration or self-test that changes such
--     an invoice and then alters that table (its own NOT COVERED). An
--     earlier version of that trigger, which queued an event on every status
--     change, made the credit-policy suite releases-as-it-is-paid stop there
--     (it disables a trigger of invoices around a payment); the final
--     version, limited to reopened invoices, passes it;
--   * this one (W2-H) holds and queues credit given back during a wait on the
--     lot the records name at once, in the forwarder alone: no new trigger,
--     no new function, nothing queued on invoices, and the waiting cases are
--     fixed too (Z1w, K7wg, K7w2). Every suite run for it gives the same
--     result with it as without it (the 462, 463, 460, 461, 448, 446, 451,
--     447, 445, 464, 458 and 457 suites, cancel-voucher-stock-once, the
--     credit-policy, invoice-actions, customer-merge, permissions and
--     exchanges suites; 462's and 463's where K7b and P7 now end the 470
--     way; the copies' known failures, which have nothing to do with credit
--     given back, the same before and after), releases-as-it-is-paid among
--     them.
--
-- NOT CHANGED
--
--   * refund_invoice_recorded (804ecd82; 458 relies on its call of
--     settle_waiting_special_docs_on_refund), cancel_invoice_recorded
--     (de52d9db), reopen_invoice (0ff61e4e), correct_invoice (04d647e1),
--     correct_invoice_payment, refund_special_credit,
--     apply_reopened_invoice_benefits (463's), merge_customer_records,
--     move_invoice_benefits_to_customer, invoice_transferable_benefits,
--     invoice_action_plan, invoice_financial_position,
--     resolve_invoice_action_v2, invoice_benefit_unused_elsewhere,
--     cancelled_invoice_used_value, invoice_reopen_preview(_before_sessions),
--     the refund options, 462's ancestry, holder, trace and ledger trigger,
--     463's helpers, the triggers on invoices: pinned, unchanged.
--   * The pages: no wording a page matches on changes. No page, Edge Function
--     or setting changes. The Finance panel's refund by line of the cancelled
--     package now offers the held-back credit (its options read what the row
--     holds back); the Reopen dialog's "credit to reinstate" counts it.
--   * Statements: the old holder's shows the credit returned and taken off
--     ("Credit returned", "Adjustment — decrease"); the new holder's "Credit
--     added" and "Adjustment — decrease" ("Held back by the invoice's
--     cancellation..."), a balance of S$0.
--
-- NOT COVERED (for the Owner; the suite checks 1 to 3 as they are)
--
--   1. Without a reissue (the package's own lot, its holder the benefits'),
--      credit given back while the package is cancelled or refunded still
--      lands on that lot and can be spent, as before 462 (the forwarder does
--      nothing where the named lot alone holds it and its holder is the
--      benefits'). After a guided Cancel that recorded the refund, that
--      customer keeps it as credit (G2, G3: A S$20, net S$20, nothing more can
--      be paid back), where with a reissue 470 holds it back and adds it to
--      what is owed back (K7gc); after a Refund in full with an override, a
--      refunded invoice leaves A S$20 (RX0). An Owner decision whether the
--      plain case should be held back too (it changes what staff have seen
--      since before 462).
--   2. A package refunded in full with an override (what was spent paid back
--      too) whose spent part then comes back: held back for the holder (RX1),
--      owed to nobody (it was paid back), kept on the lot the records name
--      until a reopening.
--   3. Credit given back while a reopening waits is not spendable until its
--      payment (before 470 the customer it went back to could spend it; the
--      holder cannot spend it before the payment either, K7w2), as credit the
--      cancellation took back waits for that payment.
--   4. Refusals at commit, for the Owner, now also while cancelled or
--      waiting: every record deleted (the benefits' holder, the invoice's
--      customer and the customer it went back to: the refund is refused,
--      nothing recorded, P9c), and 462's chain limit.
--   5. 462's NOT COVERED 9 (a deadlock) now also while cancelled or waiting:
--      a refund or Correct payment of a sale paid from the package's lot
--      that is forwarded locks the package's invoice at commit, after the
--      lot; a refund by line, Cancel, Move, change or reopening's payment of
--      that package committing at the same moment takes the invoice first.
--      One is stopped with "deadlock detected" and rolled back whole; staff
--      do it again. A refund that moves nothing still locks nothing here.
--      This is new risk, not 462's alone: before 470 the forwarder took
--      no lock while the package was cancelled or waiting, so these
--      pairs did not deadlock. On copies of production at 469 (a review,
--      26 Oct 2026), a refund of a session paid from the package,
--      against the package's reopening payment or against a refund by
--      line of the cancelled package, deadlocked with 470 whenever the
--      two overlapped (8 of 8 tries; either can be the one rolled back,
--      mostly the payment) and never without it (where both then commit,
--      but the session's credit is left on a lot no record names: K7b).
--      Nothing is lost: the one rolled back, done again on its own, ends
--      as it would have. A "busy, try again" message instead would not
--      make it rarer; a real fix changes the lock order of
--      refund_invoice_recorded or of the reopening's payment, which this
--      does not change. For the Owner to accept as a known trade-off.
--   6. A summary, a Finance panel or a Reopen dialog open on a screen when
--      this goes in shows the old answer until it is opened again; the server
--      checks again.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the text is the tested one (its AFTER md5); the function is its BEFORE
--     (replaced) or its AFTER (left alone), anything else refused; no other
--     function takes its name; so a second run changes nothing;
--   * the functions it relies on are as read on production (pinned, below),
--     among them every trigger function an update of invoices runs (it sets
--     cancel_refund_owed), and the triggers on invoices and 462's ledger
--     trigger as read; the columns read and written have these types; one
--     queue row per ledger row; a lot never holds more than it was granted;
--     lots and the ledger keep their history; who calls the forwarder, who
--     reads or writes a cancellation's ledger rows, the reopening queue and
--     the amount owed back, and what gives credit back on a lot, as read;
--   * on the first run, nothing already in a state this reads differently
--     and that needs a decision first (each stops it, changing nothing, and
--     names the invoices; the read-only query below lists them, 1 and 2):
--     (1) credit on a lot an invoice's records replaced (K7b's state, and
--     Z1's: no record names it, so a refund by line, a Cancel or a refund in
--     full of the invoice does not reach it; 462's install refused the same
--     on 24 Oct, so it can only have come from this gap since); (2) a
--     cancelled, refunded or waiting invoice with what its cancellation holds
--     back on a lot its records replaced. Any repair is a separate data fix,
--     each with the Owner's yes;
--   * who may call the function is as read, compared as sets, and kept;
--   * afterwards: the AFTER md5 and the grants as tested.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0470, so it leaves no row): a made-up Owner, store, S$100 package, S$20
--   session and eighteen customers (fictional ACMA phones no customer has),
--   six times: the package sold to A, two sessions paid from it, the S$60
--   left moved to F, the benefits moved to B, the first session refunded (B
--   S$20), the package cancelled; then (a) the second session refunded: at
--   the commit point A and B hold nothing, the lot the records name is B's
--   (S$40 granted, S$0 held), the row holds back S$40; refunded by line, S$0
--   held; (b) the same, reopened (paid at once): B S$40, F S$60, nothing held
--   back, nothing asked, due S$100; (c) the same after F's S$60 was refunded
--   by line, reopened (it waits), B's S$40 refunded by line while it waits,
--   paid: B S$0, F S$60, nothing waiting, nothing held back; (d) F's S$60
--   refunded by line, reopened (it waits), the second session refunded while
--   it waits: held back for B as in (a), queued for the reopening's payment
--   (two rows, S$40, on B's lot); cancelled again and refunded by line, S$0
--   held; (e) S$80 stated owed back (a stand-in for a guided Cancel that kept
--   S$20 for the spent session), the second session refunded: S$100 owed
--   back, due S$100; (f) as (d), then paid: B S$40, F S$60, nothing waiting,
--   nothing held back, due S$100. Its credit ledger rows draw entry numbers
--   (a sequence, which an undone transaction does not give back: a gap, as
--   443 to 464's self-tests). Locks: the function's catalogue row to the end
--   of the apply, and the rows the self-test writes and undoes; no table is
--   locked against ordinary writes. The self-test takes the commission
--   advisory locks (affiliate_payout_lock and staff_payout_lock, through its
--   cancels and refunds) and new invoice numbers, so it waits for any app
--   cancel, refund, commission-writing payment or invoice creation still
--   open, and those wait for it, for under a second. If one stays open
--   longer than the 5 s lock timeout, or an invoice created at the same
--   moment takes the self-test's invoice number, the apply stops, changing
--   nothing, and can be run again; if what blocked it was a refund of this
--   gap, the re-run is refused by check (1) until the Owner's data fix.
--   Credit given back by a refund still open when 470 commits is forwarded
--   by 470's text at that refund's commit (the forwarder reads everything
--   again then), not by the text it started with. Apply at a quiet time.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (469 in, 26 Oct 2026: f9d0ddcb, 1387 functions; the
--   grant list 381ef69c; head 20261024125556) -> 470. 462 and 463 are in;
--   470 replaces 463's credit_given_back_follows (its AFTER is 470's BEFORE)
--   and pins the rest. This was built on 463 with 466 and 467 (6d96407c,
--   head 20261024102018); 468 and 469 (another session's) went in after:
--   they changed five functions only (affiliate_referral_signup,
--   complete_affiliate_onboarding, event_web_match_customer,
--   event_web_register, submit_health_survey), none pinned or read here, no
--   trigger and no grant, and on copies of production at 469 every pin and
--   every 'as read' list below still matches (the install passes its
--   checks). If anything else goes in first, work the fingerprints out again
--   and check that it changes none of the functions or triggers pinned below.
--   1. Before it, read only (invoice numbers and counts only; production
--      was not read for this file, so what it lists is not known yet): what
--      would stop the install (1, 2) and whose answer changes (3 to 5):
--     with recursive
--     st as (
--       select i.id, i.status::text as status,
--              exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = i.id and q.applied_at is null) as waiting
--         from public.invoices i where i.deleted_at is null),
--     chain(benefit_id, invoice_id, named_lot, id, depth) as (
--       select b.id, b.invoice_id, b.lot_id, b.lot_id, 0 from public.invoice_benefit_values b where b.lot_id is not null
--       union all
--       select c.benefit_id, c.invoice_id, c.named_lot, p.id, c.depth + 1
--         from chain c join public.customer_credit_lots l on l.id = c.id
--         join public.customer_credit_lots p on p.id = l.reassigned_from_lot_id
--          and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
--        where c.depth < 12),
--     found(reason, invoice_id, n) as (
--       -- 470 refuses to install (each needs a decision first; a data fix):
--       select '1 refuses: credit on a lot its records replaced (no record names it: a refund by line, a Cancel or a refund in full of the invoice does not reach it)', c.invoice_id, count(*)
--         from chain c join st on st.id = c.invoice_id join public.customer_credit_lots l on l.id = c.id
--        where c.depth > 0 and l.remaining_amount > 0 and l.status = 'active'
--        group by c.invoice_id
--       union all
--       select '2 refuses: cancelled, refunded or waiting for a reopening''s payment, with what its cancellation holds back on a lot its records replaced (a refund by line while a reopening waits would not find it)', c.invoice_id, count(*)
--         from chain c join st on st.id = c.invoice_id
--         join public.customer_credit_ledger e on e.lot_id = c.id and e.entry_type = 'adjust_decrease'
--          and e.source_type = 'invoice_cancel_benefit' and e.source_record_id = c.invoice_id
--         left join public.invoice_reopen_benefits q on q.source_ledger_id = e.id
--        where c.depth > 0 and (st.status in ('cancelled', 'refunded') or st.waiting) and q.applied_at is null
--        group by c.invoice_id
--       union all
--       -- 470 changes the answer (no refusal):
--       select '3 changes: cancelled, refunded or waiting for a reopening''s payment, with credit on the lot its records name held by someone other than whoever holds the benefits (the next credit given back on its lots is held back for the holder, with it)', b.invoice_id, count(*)
--         from public.invoice_benefit_values b join st on st.id = b.invoice_id join public.customer_credit_lots l on l.id = b.lot_id
--        where (st.status in ('cancelled', 'refunded') or st.waiting) and l.remaining_amount > 0 and l.status = 'active'
--          and l.customer_id is distinct from public.invoice_credit_live_holder(b.invoice_id, l.customer_id,
--                case when public.invoice_benefit_moved_to_other(b.id) then 'infinity'::timestamptz else l.created_at end)
--        group by b.invoice_id
--       union all
--       select '4 changes: cancelled, refunded or waiting for a reopening''s payment, with sales paid from a lot its records replaced that can still be refunded or corrected (their credit is now held back for whoever holds the benefits: on a cancelled invoice it adds to an amount owed back an Owner or Manager stated; while a reopening waits it is queued for its payment)', c.invoice_id, count(distinct c.id)
--         from chain c join st on st.id = c.invoice_id
--        where c.depth > 0 and (st.status in ('cancelled', 'refunded') or st.waiting)
--          and (exists (select 1 from public.invoice_line_credit_allocations a where a.lot_id = c.id and a.amount > coalesce(a.reversed_amount, 0))
--               or exists (select 1 from public.special_credit_allocations s where s.lot_id = c.id and s.amount > coalesce(s.reversed_amount, 0)))
--        group by c.invoice_id
--       union all
--       select '5 changes: asked to be cancelled or refunded (the legacy statuses), with sales paid from its lots that can still be refunded or corrected (their credit now follows to whoever holds the benefits as for a paid invoice; before, it stayed where it went back)', c.invoice_id, count(distinct c.id)
--         from chain c join st on st.id = c.invoice_id
--        where st.status in ('cancellation_requested', 'refund_requested')
--          and (exists (select 1 from public.invoice_line_credit_allocations a where a.lot_id = c.id and a.amount > coalesce(a.reversed_amount, 0))
--               or exists (select 1 from public.special_credit_allocations s where s.lot_id = c.id and s.amount > coalesce(s.reversed_amount, 0)))
--        group by c.invoice_id)
--     select f.reason, i.invoice_no, f.n
--       from found f join public.invoices i on i.id = f.invoice_id
--      order by f.reason, i.invoice_no
--      (The suite runs this same text on its cases' states before 470 and
--      checks what it lists.)
--   2. Dry run on a copy of production as it is then: work out its
--      fingerprint and grant list first (they must be the BEFORE figures
--      below, or be worked out again on that copy); apply this file twice;
--      the first run ends at the AFTER fingerprint below, the second changes
--      nothing ("left alone"); and the suite, with the earlier suites below.
--   3. Apply (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself.
--   Afterwards (checked on copies, 24 Oct 2026, and at 469 on 26 Oct): a
--   re-run of 462 refuses (already on 463's functions) and one of 463 on
--   470's credit_given_back_follows, changing nothing; 470's own leaves all
--   alone.
--   Both are applied, so nothing is lost. Their suites check 470 where it is
--   in (-v nomig=1): move-merge-leftovers-462 (S; P7 and KNOWN K7b the 470
--   way) and change-store-moves-bundle-vouchers-463 (S). function-grants is
--   unchanged (nothing is added).
--
-- BEFORE (production at 469, 26 Oct 2026; the same as at 463 with 466 and
-- 467 in, 24 Oct, where this was built; md5 of pg_get_functiondef with
-- search_path public)
--   changed
--   credit_given_back_follows(uuid)                                    844b73106bbf362768ed4a899ceb00d5  (463's)
--   relied on, not changed (pinned)
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)          804ecd829cfecf713783a09a05d93c7e
--   cancel_invoice_recorded(uuid,text,uuid)                            de52d9dbaef8ab15163bef35cb9d733d
--   reopen_invoice(uuid,text,uuid)                                     0ff61e4ead121c198ea7f90a7fc78274
--   correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)          af99337094edb6d73b9cc0ae00fbf138
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                        04d647e13e9424a9375942e5812e91a2
--   refund_special_credit(text,uuid)                                   e019e28ad79539d771376c9b38d7e27e
--   apply_reopened_invoice_benefits()                                  36eaa7224e514d3e7e42e3eeb51acfb5
--   invoice_reopen_preview_before_sessions(uuid)                       12206ed066495024421b3b44a6a9d8e2
--   invoice_reopen_preview(uuid)                                       e09ebf9c0841ef5463f96b26f4933541
--   invoice_benefit_unused_elsewhere(uuid)                             d35d7c8ae7187985ea64f8a5c38a7d79
--   cancelled_invoice_used_value(uuid)                                 055a3b07b1c15ffb1ac19039fa6cb650
--   invoice_action_plan(uuid,text,jsonb)                               383d618edb28c3c9a360242d038a022c
--   invoice_financial_position(uuid)                                   ba7eccbfeff217c8b1969b0e55a010ca
--   resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean) 201f08ebf14a64cd88d411a7cfb4c9c4
--   merge_customer_records(uuid,uuid,text,uuid)                        ba05c2b1fb4c0e14d369c01d06a635b0
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)             c01606c84ee13ddcd88c15521d6d9aed
--   invoice_transferable_benefits(uuid)                                68736a39ed765ee787242bc62bbaeebb
--   transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)          7aebd7120bc3928db46df0941cb20889
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
--   (the trigger functions an update of invoices runs)
--   trg_legacy_refund_guard()                                          089965ef41a18fe3c54dd622e743075a
--   trg_lock_on_settle()                                               39c6478cdaec553c2ab8ceaf55058960
--   validate_invoice_business_metadata()                               c6e4436575e1c5ec8580d2b3d9d11d50
--   track_invoice_business_date_version()                              2c1e7ac8c5c2cfea8ddc5122adfc5d92
--   trg_create_therapy_on_paid()                                       012ae4e305b9870fa5596f740c0427b9
--   trg_fulfil_from_warehouse()                                        4abf4bf68e4f00658a8da66469e7059e
--   trg_issue_sold_vouchers_on_paid()                                  cf0b5610b77edfea2683751d5c25ca1d
--   the triggers on invoices (md5 of their definitions, by name)       92c94e3ebc6113a68d972330bbca8938 (19 triggers)
--   public function fingerprint, production now (469)                  f9d0ddcb2dceb08fd4ba502d8487f0bf (1387 functions; head 20261024125556)
--     (history: the build base, 463 with 466 and 467, before 468/469)  6d96407cdeb903712a2d7be7016aa9a6 (1387 functions)
--   grant list (string_agg(signature '=' proacl, '|'), sorted)          381ef69cb44f960ff981585ff8402fa1 (production lists the same
--                                                                      grants in another order: compare as sets)
-- AFTER (for later guards)
--   credit_given_back_follows(uuid)                                    b7720a148f5371bd2bd844d3076ea3b2  (grants kept: the service role)
--     (the first text, before the review's owed-back fix: 837a0aaa0b17c361446c1ba924ce1c77)
--   public function fingerprint, worked out on a copy of production at 469 (26 Oct 2026; a second run the same):
--     production now (469) -> 470                                      0f5816140d494a8085c6f4f255795c00 (1387 functions: none added, none dropped)
--     (history, the build base: 6d96407c -> d1a4af1252530b724ecb454f461d9934 with this text; 0c83ca5b4deec9a264671c5ce3792cdf with the first)
--   grant list after 470                                               381ef69cb44f960ff981585ff8402fa1 (unchanged)
--   the triggers on invoices                                           92c94e3ebc6113a68d972330bbca8938 (19, unchanged)
--
-- Test: scripts/invoices/tests/cancelled-package-refund-470.sql (begin ...
-- rollback; it installs this file twice; -v nomig=1 where it is in). It
-- reproduces K7b and its siblings first, then checks the header's query,
-- the refusals, the install, every case after 470 with 462's invariants and
-- Cancel, the held-back rows, the queue while a reopening waits, the amount
-- owed back (by the money of what is held back, on the S$100 package, the
-- Bonus package, the Premium Bundle and that bundle discounted: what the
-- refund options offer, the Finance panel's and Cancel's refund due, S$0
-- after the refund by line), 446's matching, cases begun before 470 and
-- finished after, the controls unchanged, ALTER TABLE invoices with a
-- reopened invoice paid in the same transaction, and NOT COVERED 1 to 3 as
-- KNOWN. Each app call is
-- followed by what its commit does (462's trigger is deferred). Fixtures only
-- (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The function this changes: BEFORE (production, 24 Oct 2026: 463's
  -- AFTER) and AFTER md5s; who may call it, as read (kept) ══════════════════
  c_sig constant text := 'credit_given_back_follows(uuid)';
  c_before constant text := '844b73106bbf362768ed4a899ceb00d5';
  c_after constant text := 'b7720a148f5371bd2bd844d3076ea3b2';
  c_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';

  -- ══ The whole text (exactly as the database prints it back) ═════════════
  c_def_follows constant text := $d1$CREATE OR REPLACE FUNCTION public.credit_given_back_follows(p_lot_id uuid)
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
-- holder is the benefits' holder (as before), nor for a lot no invoice's
-- benefit row names or replaced (wallet credit of other kinds). The holder:
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
-- Whether anything needs doing is read first without locks (a refund that
-- moves nothing takes no lock here); only then are the invoice, its benefit
-- row and the lots locked, in the order Cancel and Reopen take them (then
-- the reopening's queue rows on those lots), and everything read again.
declare v_try int:=0; v_k int; v_cur uuid; v_prev uuid; v_inv uuid; v_locked boolean:=false; v_status text;
 b public.invoice_benefit_values%rowtype; n public.customer_credit_lots%rowtype; x record;
 v_chain uuid[]; v_h uuid; v_more boolean; v_total numeric:=0; v_new uuid; v_wallet uuid; v_cap numeric;
 v_from jsonb:='[]'::jsonb; v_parent uuid; v_up uuid; v_depth int; v_replace boolean;
 -- 470
 v_hold boolean:=false; v_wait uuid; v_carry numeric:=0; v_held jsonb:='[]'::jsonb; v_mark uuid; v_take uuid; hb record;
 v_owed numeric; v_owed_new numeric; v_owed_add numeric;
 c_reason constant text:='Credit given back goes to whoever holds the invoice''s benefits now';
 c_held constant text:='Held back by the invoice''s cancellation for whoever holds its benefits now';
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
  if n.status<>'active' or n.is_locked then return; end if;
  v_chain:=public.credit_lot_ancestry(n.id);
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
           where l.id=any(v_chain) and l.remaining_amount>0 and l.status='active' and not l.is_locked
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
$d1$;

  -- ══ 462's ledger trigger, the reopening's settlement trigger and the
  -- triggers on invoices (an update of invoices runs them), as read ═════════
  c_ledger_trg_def constant text := $t$CREATE CONSTRAINT TRIGGER credit_given_back_follows AFTER INSERT ON public.customer_credit_ledger DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (((new.entry_type = 'reverse'::text) AND (new.lot_id IS NOT NULL) AND (new.source_type = ANY (ARRAY['invoice_payment_refund'::text, 'payment_correction'::text, 'special_sale'::text, 'rental'::text, 'rental_late_fee'::text])))) EXECUTE FUNCTION trg_credit_given_back_follows()$t$;
  c_settle_trg_def constant text := $t$CREATE TRIGGER invoice_reopen_benefits_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_benefits()$t$;
  c_inv_trg_md5 constant text := '92c94e3ebc6113a68d972330bbca8938';
  c_inv_trg_n constant int := 19;

  -- ══ Relied on, not changed (production, 24 Oct 2026) ════════════════════
  c_relied constant text[] := array[
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'reopen_invoice(uuid,text,uuid)',
    'correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'refund_special_credit(text,uuid)',
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
    'transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)',
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
    'trg_legacy_refund_guard()',
    'trg_lock_on_settle()',
    'validate_invoice_business_metadata()',
    'track_invoice_business_date_version()',
    'trg_create_therapy_on_paid()',
    'trg_fulfil_from_warehouse()',
    'trg_issue_sold_vouchers_on_paid()'];
  c_relied_md5 constant text[] := array[
    '804ecd829cfecf713783a09a05d93c7e',
    'de52d9dbaef8ab15163bef35cb9d733d',
    '0ff61e4ead121c198ea7f90a7fc78274',
    'af99337094edb6d73b9cc0ae00fbf138',
    '04d647e13e9424a9375942e5812e91a2',
    'e019e28ad79539d771376c9b38d7e27e',
    '36eaa7224e514d3e7e42e3eeb51acfb5',
    '12206ed066495024421b3b44a6a9d8e2',
    'e09ebf9c0841ef5463f96b26f4933541',
    'd35d7c8ae7187985ea64f8a5c38a7d79',
    '055a3b07b1c15ffb1ac19039fa6cb650',
    '383d618edb28c3c9a360242d038a022c',
    'ba7eccbfeff217c8b1969b0e55a010ca',
    '201f08ebf14a64cd88d411a7cfb4c9c4',
    'ba05c2b1fb4c0e14d369c01d06a635b0',
    'c01606c84ee13ddcd88c15521d6d9aed',
    '68736a39ed765ee787242bc62bbaeebb',
    '7aebd7120bc3928db46df0941cb20889',
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
    '089965ef41a18fe3c54dd622e743075a',
    '39c6478cdaec553c2ab8ceaf55058960',
    'c6e4436575e1c5ec8580d2b3d9d11d50',
    '2c1e7ac8c5c2cfea8ddc5122adfc5d92',
    '012ae4e305b9870fa5596f740c0427b9',
    '4abf4bf68e4f00658a8da66469e7059e',
    'cf0b5610b77edfea2683751d5c25ca1d'];
  -- Who calls the forwarder; who reads or writes a cancellation's ledger
  -- rows, the reopening queue and the amount owed back; what writes a
  -- 'reverse' ledger row and what raises a lot's balance (by name; a
  -- session's own temporary functions and the forwarder itself are not
  -- counted), as read on 24 Oct 2026.
  c_callers constant text := 'trg_credit_given_back_follows()';
  c_cancel_rows constant text := 'cancel_invoice_recorded(uuid,text,uuid), credit_lot_policy(text,text,boolean), invoice_benefit_unused_elsewhere(uuid), invoice_reopen_preview_before_sessions(uuid), reopen_invoice(uuid,text,uuid)';
  c_queue_inserts constant text := 'reopen_invoice(uuid,text,uuid)';
  c_queue_updates constant text := 'apply_reopened_invoice_benefits(), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)';
  c_owed_writers constant text := 'cancel_invoice_recorded(uuid,text,uuid), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)';
  c_reverse_writers constant text := 'apply_reopened_invoice_benefits(), correct_invoice_payment(uuid,numeric,date,uuid,text,uuid), customer_credit_statement(uuid,date,date), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), refund_special_credit(text,uuid), repair_credit_package_progress_lots(), reverse_credit_lot(uuid,text,text,text), reverse_invoice_date_recovery(uuid,uuid,text)';
  c_raisers constant text := 'apply_reopened_invoice_benefits(), correct_invoice_payment(uuid,numeric,date,uuid,text,uuid), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), refund_special_credit(text,uuid)';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; n int; i int; v_first boolean; v_acl text;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_pk uuid; t_svc uuid; t_wallet uuid;
  t_case int; t_a uuid; t_b uuid; t_f uuid; t_inv uuid; t_s1 uuid; t_s2 uuid; t_item uuid; t_ben uuid; t_fben uuid;
  t_rcpt uuid; t_lines jsonb; t_amt numeric; t_lot record;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The text is the tested one.
  if md5(c_def_follows) <> c_after then
    raise exception '470: the text in this file is not the tested one'; end if;

  -- The functions relied on are as read on production (24 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '470: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if to_regprocedure('auth.uid()') is null then raise exception '470: auth.uid() must be there'; end if;

  -- The columns read and written, with these types.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('customer_credit_lots', 'id', 'uuid'), ('customer_credit_lots', 'customer_id', 'uuid'),
                 ('customer_credit_lots', 'category', 'text'), ('customer_credit_lots', 'status', 'text'),
                 ('customer_credit_lots', 'is_locked', 'boolean'), ('customer_credit_lots', 'original_amount', 'numeric(12,2)'),
                 ('customer_credit_lots', 'remaining_amount', 'numeric(12,2)'), ('customer_credit_lots', 'reassigned_from_lot_id', 'uuid'),
                 ('customer_credit_lots', 'source_type', 'text'), ('customer_credit_lots', 'source_record_id', 'uuid'),
                 ('customer_credit_lots', 'created_at', 'timestamp with time zone'),
                 ('customer_credit_ledger', 'id', 'uuid'), ('customer_credit_ledger', 'lot_id', 'uuid'),
                 ('customer_credit_ledger', 'entry_type', 'text'), ('customer_credit_ledger', 'source_type', 'text'),
                 ('customer_credit_ledger', 'source_record_id', 'uuid'), ('customer_credit_ledger', 'amount', 'numeric(12,2)'),
                 ('customer_credit_ledger', 'reason', 'text'), ('customer_credit_ledger', 'entry_seq', 'bigint'),
                 ('invoice_benefit_values', 'id', 'uuid'), ('invoice_benefit_values', 'invoice_id', 'uuid'),
                 ('invoice_benefit_values', 'lot_id', 'uuid'), ('invoice_benefit_values', 'cancelled_unused_value', 'numeric(12,2)'),
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
                 ('special_credit_allocations', 'lot_id', 'uuid'), ('special_credit_allocations', 'amount', 'numeric(14,2)'),
                 ('special_credit_allocations', 'reversed_amount', 'numeric(14,2)')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '470: these columns are missing or not as read on 24 Oct 2026: %', v; end if;
  -- One queue row per ledger row; a lot never holds more than it was
  -- granted; lots and the ledger keep their history.
  if not exists (select 1 from pg_constraint where conrelid = 'public.invoice_reopen_benefits'::regclass and contype = 'u'
                  and pg_get_constraintdef(oid) = 'UNIQUE (source_ledger_id)')
     or not exists (select 1 from pg_constraint where conrelid = 'public.customer_credit_lots'::regclass
                     and conname = 'credit_lot_remaining_within_original' and pg_get_constraintdef(oid) = 'CHECK ((remaining_amount <= original_amount))')
     or not exists (select 1 from pg_trigger where tgrelid = 'public.customer_credit_ledger'::regclass and tgname = 'credit_ledger_immutable'
                     and not tgisinternal and tgenabled = 'O')
     or not exists (select 1 from pg_trigger where tgrelid = 'public.customer_credit_lots'::regclass and tgname = 'credit_lot_immutable'
                     and not tgisinternal and tgenabled = 'O') then
    raise exception '470: the queue''s one row per ledger row, a lot''s ceiling or the history guards are not as read on 24 Oct 2026'; end if;
  -- 462's ledger trigger, the reopening's settlement and the triggers on
  -- invoices, as they were read (the forwarder updates invoices).
  if (select pg_get_triggerdef(oid) from pg_trigger where tgrelid = 'public.customer_credit_ledger'::regclass
       and tgname = 'credit_given_back_follows') is distinct from c_ledger_trg_def
     or (select pg_get_triggerdef(oid) from pg_trigger where tgrelid = 'public.invoices'::regclass
          and tgname = 'invoice_reopen_benefits_settled') is distinct from c_settle_trg_def then
    raise exception '470: 462''s trigger credit_given_back_follows or the reopening''s settlement trigger is not as made; 470 goes in after 462 and 463'; end if;
  select md5(string_agg(pg_get_triggerdef(oid), E'\n' order by tgname)), count(*) into v, n
    from pg_trigger where tgrelid = 'public.invoices'::regclass and not tgisinternal;
  if v is distinct from c_inv_trg_md5 or n <> c_inv_trg_n then
    raise exception '470: the triggers on invoices are not as read on 24 Oct 2026 (% triggers, md5 %); check what an update of an invoice''s amount owed back runs, then re-test', n, v; end if;

  -- No other function takes the name (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'credit_given_back_follows'
     and p.oid::regprocedure::text <> c_sig;
  if v is not null then raise exception '470: another function takes the name of the one this changes: %', v; end if;

  -- Who calls the forwarder; who reads or writes a cancellation's rows, the
  -- queue and the amount owed back; what gives credit back on a lot: as read
  -- (a new way would need the same care).
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'credit_given_back_follows\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  if v is distinct from c_callers then
    raise exception '470: the functions that call credit_given_back_follows are not as read on 24 Oct 2026 (%)', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ '''invoice_cancel_benefit''' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  if v is distinct from c_cancel_rows then
    raise exception '470: what reads or writes a cancellation''s ledger rows is not as read on 24 Oct 2026 (%)', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'insert\s+into\s+public\.invoice_reopen_benefits' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'update\s+public\.invoice_reopen_benefits' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  if v is distinct from c_queue_inserts or d is distinct from c_queue_updates then
    raise exception '470: what writes the reopening''s queue is not as read on 24 Oct 2026 (% / %)', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'cancel_refund_owed\s*=' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  if v is distinct from c_owed_writers then
    raise exception '470: what writes the amount owed back is not as read on 24 Oct 2026 (%)', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ '''reverse''' and ns.nspname not like 'pg\_temp\_%';
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'remaining_amount\s*=\s*(\w+\.)?remaining_amount\s*\+' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_reverse_writers or d is distinct from c_raisers then
    raise exception '470: what gives credit back on a lot is not as read on 24 Oct 2026 (% / %); check that 462''s trigger forwards each, then re-test', v, d; end if;

  -- The function: its BEFORE (replaced) or its AFTER (left alone).
  d := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  if md5(d) = c_after then
    raise notice '470: public.% is already this version; left alone', c_sig;
    v_first := false;
  elsif md5(d) = c_before then
    v_first := true;
  else
    raise exception '470: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig, md5(d);
  end if;

  -- ── On the first run: nothing already in a state 470 reads differently
  -- and that needs a decision first (the header's read-only query lists
  -- each, 1 and 2; a repair is a separate data fix, with the Owner's yes).
  if v_first then
    -- (1) Credit on a lot an invoice's records replaced (K7b's state and
    -- Z1's: no record names it, so a refund by line, a Cancel or a refund in
    -- full of the invoice does not reach it).
    with recursive chain(invoice_id, id, depth) as (
      select b.invoice_id, b.lot_id, 0 from public.invoice_benefit_values b where b.lot_id is not null
      union all
      select c.invoice_id, p.id, c.depth + 1
        from chain c join public.customer_credit_lots l on l.id = c.id
        join public.customer_credit_lots p on p.id = l.reassigned_from_lot_id
         and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
       where c.depth < 12)
    select count(distinct c.invoice_id), string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into n, v
      from chain c join public.invoices iv on iv.id = c.invoice_id and iv.deleted_at is null
      join public.customer_credit_lots l on l.id = c.id
     where c.depth > 0 and l.remaining_amount > 0 and l.status = 'active';
    if n > 0 then
      raise exception '470: % invoice(s) have credit on a lot their records replaced (%): no record names it, so a refund by line, a Cancel or a refund in full of the invoice does not reach it. Decide where it belongs (a data fix), then apply. Nothing was changed.', n, v; end if;
    -- (2) A cancelled, refunded or waiting invoice with what its
    -- cancellation holds back on a lot its records replaced (a refund by line
    -- while a reopening waits matches the queue on the lot the row names).
    with recursive chain(invoice_id, id, depth) as (
      select b.invoice_id, b.lot_id, 0 from public.invoice_benefit_values b where b.lot_id is not null
      union all
      select c.invoice_id, p.id, c.depth + 1
        from chain c join public.customer_credit_lots l on l.id = c.id
        join public.customer_credit_lots p on p.id = l.reassigned_from_lot_id
         and (p.source_type, p.source_record_id) is not distinct from (l.source_type, l.source_record_id)
       where c.depth < 12)
    select count(distinct c.invoice_id), string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into n, v
      from chain c join public.invoices iv on iv.id = c.invoice_id and iv.deleted_at is null
      join public.customer_credit_ledger e on e.lot_id = c.id and e.entry_type = 'adjust_decrease'
       and e.source_type = 'invoice_cancel_benefit' and e.source_record_id = c.invoice_id
      left join public.invoice_reopen_benefits q on q.source_ledger_id = e.id
     where c.depth > 0 and q.applied_at is null
       and (iv.status in ('cancelled', 'refunded')
            or exists (select 1 from public.invoice_reopen_benefits w where w.invoice_id = iv.id and w.applied_at is null));
    if n > 0 then
      raise exception '470: % invoice(s) cancelled, refunded or waiting for a reopening''s payment have what their cancellation holds back on a lot their records replaced (%). Decide where it belongs (a data fix), then apply. Nothing was changed.', n, v; end if;
  end if;

  -- Who may call it, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig))
     is distinct from (select array_agg(x::text order by x::text) from unnest(c_acl::aclitem[]) x) then
    raise exception '470: who may call public.% is not as read on 24 Oct 2026 (%)', c_sig,
      (select proacl::text from pg_proc where oid = to_regprocedure('public.' || c_sig)); end if;
  v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig));

  -- ── Change ──────────────────────────────────────────────────────────────
  if v_first then
    execute c_def_follows;
  end if;

  -- ── Afterwards: installed exactly as tested, grants as before ───────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_after then
    raise exception '470: public.% is not at its AFTER md5 (%)', c_sig, md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))); end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig)) is distinct from v_acl then
    raise exception '470: the grants of public.% changed', c_sig; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("470 check", @example.invalid, fictional ACMA
  -- phones no customer uses); it ends by raising P0470, which undoes all it
  -- wrote. 462's trigger runs at commit; here at each step's end (SET
  -- CONSTRAINTS ... IMMEDIATE), as a commit would.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from generate_series(900, 999) g, lateral (select '+61491570' || g::text as p) x
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p desc limit 18);
    if coalesce(cardinality(t_phones), 0) < 18 then raise exception '470: the self-test found no eighteen unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '470-check-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '470 check', '470-check-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('470 check ' || t_sfx, '470-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('470 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy, grants_reward)
    values ('470 check ' || t_sfx, 100, 100, false, true, true, false) returning id into t_pk;
    insert into public.credit_package_stores (package_id, store_id) values (t_pk, t_store);
    insert into public.therapy_services (service_code, name, standard_price, duration_minutes, is_active)
    values ('470-' || t_sfx, '470 check ' || t_sfx, 20, 30, true) returning id into t_svc;
    insert into public.therapy_service_stores (service_id, store_id, is_available) values (t_svc, t_store, true);
    select pm.id into t_wallet from public.payment_methods pm
     where pm.name = 'Wallet — Credit Package Paid' and pm.is_wallet_credit and pm.deleted_at is null;
    if t_wallet is null then raise exception '470: the wallet method "Wallet — Credit Package Paid" (443) is not there'; end if;

    for t_case in 1 .. 6 loop
      -- The common part: the package sold to A, two S$20 sessions paid from
      -- it, the S$60 left moved to F, the benefits moved to B (the customer
      -- change's step), the first session refunded (B S$20), cancelled.
      insert into public.customers (full_name, phone) values ('470 Check Buyer ' || t_case || ' ' || t_sfx, t_phones[3 * t_case - 2]) returning id into t_a;
      insert into public.customers (full_name, phone) values ('470 Check Holder ' || t_case || ' ' || t_sfx, t_phones[3 * t_case - 1]) returning id into t_b;
      insert into public.customers (full_name, phone) values ('470 Check Friend ' || t_case || ' ' || t_sfx, t_phones[3 * t_case]) returning id into t_f;
      t_inv := public.create_invoice(t_store, t_a, null::uuid,
        jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
      perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
      select b.id into t_ben from public.invoice_benefit_values b where b.invoice_id = t_inv;
      select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv;
      select p.id into t_rcpt from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1;
      t_s1 := public.create_invoice(t_store, t_a, null::uuid,
        jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
      perform public.record_invoice_payment(t_s1, jsonb_build_array(jsonb_build_object('payment_method_id', t_wallet, 'amount', 20)), gen_random_uuid());
      t_s2 := public.create_invoice(t_store, t_a, null::uuid,
        jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
      perform public.record_invoice_payment(t_s2, jsonb_build_array(jsonb_build_object('payment_method_id', t_wallet, 'amount', 20)), gen_random_uuid());
      perform public.transfer_invoice_unused_benefit(t_ben, t_f, t_store, '470 check', gen_random_uuid());
      select b.id into t_fben from public.invoice_benefit_values b join public.invoice_benefit_transfers t on t.replacement_benefit_id = b.id
       where t.source_benefit_id = t_ben;
      perform public.move_invoice_benefits_to_customer(t_inv, t_b, t_store, '470 check');
      perform public.cancel_invoice_recorded(t_s1, '470 check', gen_random_uuid());
      perform public.refund_invoice_recorded(t_s1, jsonb_build_array(jsonb_build_object('amount', 20)),
        jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_s1 and p.entry_kind = 'receipt'
                                                             order by p.created_at limit 1), 'amount', 20)), '[]'::jsonb, '470 check', gen_random_uuid());
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      if (select l.customer_id from public.invoice_benefit_values b join public.customer_credit_lots l on l.id = b.lot_id where b.id = t_ben) <> t_b
         or (select l.remaining_amount from public.invoice_benefit_values b join public.customer_credit_lots l on l.id = b.lot_id where b.id = t_ben) <> 20 then
        raise exception '470: (%) the first session''s S$20 did not go to the holder (462)', t_case; end if;
      perform public.cancel_invoice_recorded(t_inv, '470 check', gen_random_uuid());
      if t_case = 5 then
        -- a stand-in for a guided Cancel that kept S$20 for the spent session
        update public.invoices set cancel_refund_owed = 80 where id = t_inv;
      end if;
      if t_case in (3, 4, 6) then
        -- F's S$60 refunded by line.
        perform public.refund_invoice_recorded(t_inv,
          jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 60,
            'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_fben, 'amount', 60)))),
          jsonb_build_array(jsonb_build_object('payment_id', t_rcpt, 'amount', 60)), '[]'::jsonb, '470 check', gen_random_uuid());
      end if;
      if t_case in (4, 6) then
        -- reopened: it waits for S$60.
        perform public.reopen_invoice(t_inv, '470 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
      end if;
      -- The second session cancelled and refunded (while cancelled; in (d)
      -- and (f) while the reopening waits).
      perform public.cancel_invoice_recorded(t_s2, '470 check', gen_random_uuid());
      perform public.refund_invoice_recorded(t_s2, jsonb_build_array(jsonb_build_object('amount', 20)),
        jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_s2 and p.entry_kind = 'receipt'
                                                             order by p.created_at limit 1), 'amount', 20)), '[]'::jsonb, '470 check', gen_random_uuid());
      if (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> 20 then
        raise exception '470: (%) the second session''s refund did not go back where it was paid from before the commit point', t_case; end if;
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      -- Held back for B, on a lot the records name: A and B hold nothing.
      select l.* into t_lot from public.invoice_benefit_values b join public.customer_credit_lots l on l.id = b.lot_id where b.id = t_ben;
      if ((select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id in (t_a, t_b)) <> 0
          or t_lot.customer_id <> t_b or t_lot.remaining_amount <> 0 or t_lot.original_amount <> 40
          or (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben) <> 40
          or (select s.credit_lot_id from public.credit_package_sales s where s.invoice_id = t_inv) <> t_lot.id) then
        raise exception '470: (%) the credit given back was not held back for the holder on a lot the records name (%)', t_case,
          (select jsonb_agg(jsonb_build_object('customer', l.customer_id, 'remaining', l.remaining_amount, 'original', l.original_amount))
             from public.customer_credit_lots l where l.customer_id in (t_a, t_b)); end if;
      if t_case in (4, 6) then
        -- (d), (f) queued for the reopening's payment on the lot the records
        -- name: the cancellation's S$20 carried over and the S$20 given back.
        if (select count(*) from public.invoice_reopen_benefits q join public.customer_credit_ledger e on e.id = q.source_ledger_id
             where q.invoice_id = t_inv and q.applied_at is null and e.lot_id = t_lot.id) <> 2
           or (select sum(q.amount) from public.invoice_reopen_benefits q join public.customer_credit_ledger e on e.id = q.source_ledger_id
                where q.invoice_id = t_inv and q.applied_at is null and e.lot_id = t_lot.id) <> 40
           or (select count(distinct q.request_id) from public.invoice_reopen_benefits q where q.invoice_id = t_inv and q.applied_at is null) <> 1 then
          raise exception '470: (%) the held-back credit is not queued for the reopening''s payment on the lot the records name', t_case; end if;
      end if;
      if t_case = 4 then
        -- (d) cancelled again: nothing more to take.
        perform public.cancel_invoice_recorded(t_inv, '470 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
      end if;
      if t_case = 5 then
        -- (e) what is owed back grows by the money of what is held back (on
        -- this S$100 package S$20 of credit is S$20; the suite checks the
        -- Bonus package and the Premium Bundle).
        if (select cancel_refund_owed from public.invoices where id = t_inv) <> 100
           or (public.invoice_financial_position(t_inv)->>'refund_due')::numeric <> 100 then
          raise exception '470: (e) the amount owed back is % (due %), not S$100', (select cancel_refund_owed from public.invoices where id = t_inv),
            public.invoice_financial_position(t_inv)->>'refund_due'; end if;
      end if;
      if t_case in (1, 4) then
        -- (a), (d) the package refunded by line: all of it paid back.
        select jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', sum((x->>'max_refund')::numeric),
                 'benefits', jsonb_agg(jsonb_build_object('benefit_id', x->>'id', 'amount', (x->>'max_refund')::numeric)))),
               sum((x->>'max_refund')::numeric)
          into t_lines, t_amt
          from jsonb_array_elements(public.invoice_refund_options_before_sessions(t_inv)->'benefits') x where (x->>'max_refund')::numeric > 0;
        perform public.refund_invoice_recorded(t_inv, t_lines, jsonb_build_array(jsonb_build_object('payment_id', t_rcpt, 'amount', t_amt)),
          '[]'::jsonb, '470 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if public.invoice_net_received(t_inv) <> 0
           or (select coalesce(sum(cancelled_unused_value), 0) from public.invoice_benefit_values where invoice_id = t_inv) <> 0
           or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id in (t_a, t_b, t_f)) <> 0 then
          raise exception '470: (%) the refund by line did not pay all of it back (net %)', t_case, public.invoice_net_received(t_inv); end if;
      elsif t_case in (2, 6) then
        -- (b) reopened (paid at once), (f) paid: B S$40, F S$60.
        if t_case = 2 then
          perform public.reopen_invoice(t_inv, '470 check', gen_random_uuid());
        else
          perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
            'amount', (public.invoice_financial_position(t_inv)->>'outstanding')::numeric)), gen_random_uuid());
        end if;
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_b) <> 40
           or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_f) <> 60
           or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> 0
           or (select coalesce(sum(cancelled_unused_value), 0) from public.invoice_benefit_values where invoice_id = t_inv) <> 0
           or exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = t_inv and q.applied_at is null)
           or exists (select 1 from jsonb_array_elements(coalesce(public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->'overrides_required', '[]'::jsonb)) o
                       where o->>'code' = 'credit_used')
           or (public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->>'refund_due')::numeric <> 100 then
          raise exception '470: (%) the reopening''s payment did not give the S$40 to the holder', t_case; end if;
      elsif t_case = 3 then
        -- (c) reopened (it waits); B's S$40 refunded by line while it waits;
        -- paid: B S$0, F S$60 (446's matching found all of it).
        perform public.reopen_invoice(t_inv, '470 check', gen_random_uuid());
        perform public.refund_invoice_recorded(t_inv,
          jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 40,
            'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_ben, 'amount', 40)))),
          jsonb_build_array(jsonb_build_object('payment_id', t_rcpt, 'amount', 40)), '[]'::jsonb, '470 check', gen_random_uuid());
        perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
          'amount', (public.invoice_financial_position(t_inv)->>'outstanding')::numeric)), gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id in (t_a, t_b)) <> 0
           or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_f) <> 60
           or public.invoice_net_received(t_inv) <> 60
           or exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = t_inv and q.applied_at is null)
           or (select coalesce(sum(cancelled_unused_value), 0) from public.invoice_benefit_values where invoice_id = t_inv) <> 0 then
          raise exception '470: (c) a refund by line while the reopening waited was given back again (B %, F %, net %)',
            (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_b),
            (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_f),
            public.invoice_net_received(t_inv); end if;
      end if;
    end loop;
    raise exception using errcode = 'P0470', message = '470: self-test done, undone';
  exception when sqlstate 'P0470' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
