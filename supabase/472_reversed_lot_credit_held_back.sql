-- 472_reversed_lot_credit_held_back.sql
--
-- CREDIT A REFUNDED OR CORRECTED SALE GIVES BACK ON A LOT AN OWNER REVERSED
-- IS HELD BACK WHILE ITS PACKAGE IS CANCELLED, REFUNDED OR WAITING FOR ITS
-- REOPENING'S PAYMENT, AND FOLLOWS WHOEVER HOLDS THE BENEFITS WHILE IT IS
-- PAID, AS 471 DOES FOR ANY OTHER LOT; AND CREDIT GIVEN BACK BEHIND A LOT THE
-- RECORDS NAME THAT IS CLOSED AT S$0 FOLLOWS TOO (471's NOT COVERED 10; the
-- Owner, 26 Oct 2026: "fix the leftover gaps too")
--
-- (The number 472 is this file's name, its errors' prefix, its self-test's
-- error code P0472 and its suite's; if it changes at commit, change it in
-- these places alone: the file name, the "472:" messages, P0472, the suite,
-- and the "-- 472 (the Owner" line the suites find the forwarder by.)
--
-- WHO FOUND IT
--
--   471's builders and review (its NOT COVERED 10 and its suite's KNOWN K10,
--   26 Oct 2026), put to the Owner with 471, who chose "Fix it later,
--   separately", then (26 Oct 2026) "fix the leftover gaps too". Reproduced
--   on copies of production at 471 (fd61e1a1, 1387 functions, 26 Oct 2026)
--   with the cases 471 named (PX, PXs, S8gb, S8gs, S2gb) and the original lot
--   of its O1 (O1o): made-up records, the app's own calls, each followed by
--   what its commit does (this file's suite, section R); 26 of the suite's
--   cases were also run one app call per real transaction on copies (real
--   commits, so 462's deferred trigger at each COMMIT), with and without this
--   file: the same outcomes as the suite's, both ways. Building 472 found
--   (on the same copies, the same way) that 471's forwarder also stops where
--   the lot the records name is closed ('reversed', S$0: an Owner reversed
--   the lot a reissue gave the new customer), so credit given back on the
--   old customer's lot behind it stays there, on a lot no record names
--   (RV1, RV1b, RV1r, RV1p, PXh, PXhc); and judged, by reading the code and
--   with stand-ins on copies, the two questions the Owner's task left open:
--   a lot 328's repair replaced (NOT COVERED 1) and a special document's
--   refund onto a closed lot (471's PTsp's sibling: NOT COVERED 2).
--
-- WHAT WAS WRONG
--
--   An Owner's reversal (reverse_credit_lot; no page calls it: a direct call
--   by an active Owner or Manager, or one made before 339) takes what a lot
--   holds and closes it ('reversed', locked, a 'reverse' ledger row of source
--   'reversal'). A later refund or Correct payment of a sale paid from that
--   lot gives the sale's credit back on it and opens it again ('active'; the
--   lock is left: refund_invoice_recorded, correct_invoice_payment). 471's
--   forwarder (credit_given_back_follows, at commit) read past only the lock
--   Cancel's write-off puts on credit released before full payment; it passed
--   every other locked lot over, and returned wherever the lot the records
--   name was closed. On copies, a S$100 package sold to A, two S$20 sessions
--   paid from it, an Owner reversing the S$60 left:
--   * cancelled, S1 refunded: A holds S$20 of a cancelled package and can
--     spend it (PX, PXs); the same with S2's wallet payment corrected to cash
--     (PXc), with S1's refund made while it was paid and S2's after the
--     Cancel (PXpc; with the S$20 reversed again before the Cancel, PXrr),
--     after a refund in full with an Owner's override (PXx: S$20 of a package
--     whose money was all paid back);
--   * cancelled, S1 refunded and its S$20 refunded by line, reopened (it
--     waits for S$20), S2 refunded while it waits: A can spend it before the
--     payment (PXw);
--   * paid S$40 of S$100, the released lot's S$15 reversed, cancelled,
--     reopened and paid, a guided Cancel (S$0 owed back), S1 refunded: A
--     holds S$20, and the refund by line is refused ("That is more than the
--     S$0.00 still owed back") (S8g, S8gb, S8gs); the released lot a Cancel
--     closed, opened by S1's refund while paid, then reversed (S$20), a
--     guided Cancel, S2 refunded: A S$5, refused (S2g, S2gb);
--   * 471's O1: a copy of such a lot that a reissue made carries the lock
--     and no reversal row, so 471 held back what was given back on it; on
--     the original lot it did not (O1o: A S$20);
--   * cancelled, a 'transfer' customer change to B, reopened (the
--     reopening's payment gives B a lot that replaces A's), an Owner reverses
--     B's S$80 (the lot the records name, now closed at S$0), then S1, paid
--     from A's lot behind it, refunded: A holds S$20 on a lot no record
--     names, cancelled (RV1; the refund by line then finds nothing, RV1b;
--     reopened and paid, it stays with A, RV1r) or paid (RV1p: the benefits
--     are B's, Cancel cannot take A's S$20 back); the same with A's lot
--     reversed before the change (PXh, PXhc).
--   So the customer of a cancelled or refunded package held credit its net
--   payment does not buy, after a guided Cancel what it was owed back could
--   not be paid back, and credit did not follow the benefits' holder.
--
-- THE OWNER'S ANSWERS
--
--   22 Oct 2026: credit follows a merge and a 'transfer' customer change; a
--   Move's recipient keeps what was moved; refunds paid back count as not
--   used. 24 Oct 2026 (462, 470): a cancel or refund takes back what the
--   invoice gave from whoever holds it now; the customer holds exactly what
--   the net payment buys; nothing stranded on a lot no record names; nothing
--   paid twice; Correct payment keeps working. 26 Oct 2026 (471): the plain
--   case works as the reissue case does; a package refunded in full with an
--   override whose spent part then comes back: held back, owed to nobody,
--   accepted; credit given back while a reopening waits is held for that
--   payment, accepted; the deadlock trade-off (470's NOT COVERED 5)
--   accepted for all packages; for credit released before full payment, S$1
--   owed back per S$1 held back. 26 Oct 2026, after choosing "Fix it later,
--   separately" for 471's NOT COVERED 7 and 10: "fix the leftover gaps too",
--   with these rules for this one: an Owner's reversal stays reversed (what
--   it took stays taken); credit a refund gives back AFTER it is the
--   session's credit and follows the same rules as 471's: held back while the
--   package is cancelled, refunded or waiting, follows the benefits' holder
--   while it is paid; staff are told what the payment will actually give;
--   no business rule is changed beyond these by guessing.
--
-- WHAT THIS DOES (one function changed, whole text; nothing added; no table,
-- column, trigger or grant changes)
--
--   credit_given_back_follows(uuid) (471's). As before it runs at commit for
--   each ledger row giving credit back on a lot (462's deferred trigger,
--   unchanged). Two tests change; everything else is 471's text unchanged:
--   (A) The lock. Before, a locked lot was passed over (the lot the records
--   name: nothing done; a lot behind it: not drawn, not counted) unless it
--   was a lot of the invoice's release record that Cancel's write-off locked
--   (471's C). Now a lock is no reason to pass a lot over, but the lock 328's
--   repair put on the lot it replaced (told by its 'credit_lot_provenance_
--   repair' ledger row, as 471 told it): a lot an Owner reversed, opened
--   again by a refund or correction, is read as any other lot, and so is a
--   copy of one a reissue made (with no reversal row of its own: 471 read it
--   only inside a release record's chain). So, as 471 does for any lot:
--   * while the invoice is cancelled or refunded, or a reopening of it waits
--     to be settled, what that lot holds is held back where it is (the
--     cancellation's own ledger row, 'adjust_decrease',
--     'invoice_cancel_benefit', "Held back by the invoice's cancellation for
--     whoever holds its benefits now"; the benefit row's cancelled_unused_
--     value; on a cancelled invoice whose Owner or Manager stated what is
--     owed back, its money added to that by 470's rule: S$20 on the S$100
--     package, S8g; while a reopening waits, queued for its payment, PXw; on
--     a refunded invoice owed to nobody, PXx, as the Owner accepted for RX0
--     and RX1);
--   * where whoever holds the benefits is someone else, or credit sits on a
--     lot behind the one the records name, it goes to the benefits' holder
--     as one new lot (462's and 470's reissue; held back on it while
--     cancelled, refunded or waiting).
--   The reversal itself is not touched: it left the lot at S$0, and only
--   what a lot holds is drawn, so what the reversal took stays taken (its
--   ledger row as it was; the refund by line pays back only what is held
--   back: PX's S$20, not the S$60; S8gb's S$20, not the S$15).
--   (B) A closed lot the records name. Before, the forwarder returned where
--   the lot a benefit row names is closed ('reversed'), whatever lots behind
--   it held. Now a closed lot that holds nothing is read: credit given back
--   on a lot behind it (one it replaced) goes to whoever holds the benefits,
--   or is held back for the cancellation, as one new lot that replaces the
--   closed one (RV1p: B S$20; RV1: held back for B). A closed lot that holds
--   credit is passed over as before (only refund_special_credit puts credit
--   back on a lot without opening it: NOT COVERED 2).
--   The lot stays locked once read (held at S$0, or holding what a
--   reopening's payment gives back on it, which its holder can spend:
--   allocate_invoice_wallet_credit does not read the lock, as before; a
--   Move of it is refused: NOT COVERED 4). The audit rows are 471's
--   ('credit_given_back_followed', held_in_place, held_back, replaces_lot_id
--   and the amounts owed back).
--   Money afterwards (the suite, each case): the package's refund by line
--   pays back what was received less what is still spent or reversed;
--   nobody holds credit of a cancelled or refunded package (but NOT
--   COVERED 1 to 3); reopened and paid, the holder holds what the net
--   payment buys less what the reversal took (PXwp: A S$40; PXr: A S$20);
--   Cancel takes all the invoice's credit back.
--
-- WHY THIS WAY
--
--   In the forwarder, the one function 471 changed for the same rule, and by
--   the same means: 471 already reads past Cancel's write-off's lock, holds
--   back in place, forwards to the holder and keeps every reader right (its
--   WHY THIS WAY: refund_invoice_recorded's refund by line and 446's matching,
--   448's readers, the reopening's queue and payment, Cancel again). An
--   Owner's reversal, once a refund opened the lot again, leaves a lot in
--   exactly the state 471 reads for Cancel's write-off: 'active', locked, at
--   what the refunds gave back; so the same reading gives the Owner's rule
--   (the reversal stays reversed, what comes back after it follows 471's
--   rules) without telling one lock from the other. The other ways:
--   * unlocking the lot where the refund opens it (refund_invoice_recorded,
--     correct_invoice_payment) or where it is reversed (reverse_credit_lot):
--     pinned by 446 to 471, and a lock also stops a Move
--     (transfer_invoice_unused_benefit) and the reopening's drawing of lots
--     behind (apply_reopened_invoice_benefits), which this does not decide;
--   * holding back only what was given back after the reversal (the ledger
--     rows since it): what the lot holds is exactly that (the reversal took
--     the rest to S$0), apart from credit given back before 472 (NOT COVERED
--     3), which 471's sweep already takes with the next refund on any lot.
--   328's repair's lock stays a reason to pass a lot over: the lot it
--   replaced carries 327's source, which no credit payment could draw on
--   (credit_lot_policy reads it as needs_review, which allows nothing), so
--   no sale is paid from one and nothing is given back on it (NOT COVERED 1);
--   reading it would change nothing anyone can reach, and what such credit
--   should do is not clear from the Owner's rules.
--   A closed lot holding credit stays passed over: holding it back would
--   leave it on a closed lot that no one can spend once the package is paid
--   again; opening it is refund_special_credit's to do (NOT COVERED 2).
--
-- NOT CHANGED
--
--   * refund_invoice_recorded (804ecd82), cancel_invoice_recorded (de52d9db),
--     reopen_invoice (0ff61e4e), correct_invoice (04d647e1),
--     correct_invoice_payment (af993370), apply_reopened_invoice_benefits
--     (36eaa722), refund_special_credit (e019e28a), reverse_credit_lot
--     (10c1a3d8), repair_credit_package_progress_lots, merge_customer_records,
--     move_invoice_benefits_to_customer, invoice_transferable_benefits,
--     transfer_invoice_unused_benefit, invoice_reopen_preview(_before_
--     sessions), the release record's readers and writers, the credit
--     policy, 462's trigger and its function, the triggers on invoices: all
--     pinned (below), unchanged.
--   * Edge Functions, settings, pages: no change (read from src and
--     supabase/functions: no page or Edge Function reverses a lot or runs
--     328's repair). The wording 471 put on the guided refund's wallet
--     destination and the Finance panel ("held back there while that package
--     is cancelled or refunded, or, if it was paid in full before, while its
--     reopening waits for payment") did not hold for a lot an Owner reversed
--     (471's NOT CHANGED, left for the Owner with NOT COVERED 10); with 472
--     in it holds for it too (PX, S8g, PXw), so it stays as it is; the two
--     cases it does not hold for (NOT COVERED 1 and 2) no page can reach.
--     The customer's statement shows "Credit returned" then "Adjustment —
--     decrease — Held back by the invoice's cancellation for whoever holds
--     its benefits now", as 471's.
--
-- NOT COVERED (for the Owner; the suite checks each as it is)
--
--   1. A lot 328's repair replaced (its 'credit_lot_provenance_repair' row)
--      is passed over as before. 328 repaired lots released with 327's
--      source ('credit_package_progress'), which no credit payment could draw
--      on (credit_lot_line_allowed refuses it: 328's own header, and the
--      suite's L327 check), so no sale's payment names such a lot and no
--      refund or correction gives credit back on it. Were one given back
--      (a stand-in lot that keeps the package's source, the suite's R328:
--      paid in part, a session paid from the released lot, the repair, paid
--      in full, then the session refunded), it would stay where it went: on
--      a cancelled package its buyer could spend it, while paid Cancel would
--      leave it, after a 'transfer' change it would stay the buyer's; before
--      472 and after alike. Production has one such lot, holding no credit
--      (26 Oct 2026); whether a sale paid from it can still be refunded was
--      not read (the header's query, 5, lists it). If it lists one, what that
--      credit should do (go to the package's current lot, which the records
--      name, or stay) is the Owner's to decide, and a fix is its own
--      migration.
--   2. A special document's wallet refund (refund_special_credit) puts the
--      credit back on its lot without opening it: on a lot an Owner reversed
--      it stays on a closed lot that no one can spend, paid or cancelled
--      (PTsx, PTsxs, PTsxp), and the forwarder passes a closed lot holding
--      credit over, before 472 and after. (Paid in part, 471 holds such
--      credit back as Cancel's write-off: PTsp, unchanged.) No page pays a
--      special document with credit (pay_special_with_credit has no caller
--      in src) and no credit category allows a special document today
--      (purchase_category), so no one reaches it. A fix opens the lot as the
--      other two refunds do (refund_special_credit's own migration); for the
--      Owner. The header's query, 4, lists such credit.
--   3. Credit given back before 472 on such a lot (on a lot an Owner
--      reversed, or behind a closed lot the records name), while its package
--      was cancelled, refunded or waiting, or behind the named lot, is not
--      repaired: it stays where it went (MPXs: A spends it). The next refund
--      or correction of a sale paid from that chain holds it back, or moves
--      it, with the new credit, as 471 does (MPX2, MRV2: S$40; MRV2p: B S$40).
--      Production has no lot an Owner reversed holding credit (26 Oct 2026);
--      the header's query, 3, lists any, and the first run names them.
--   4. The lot stays locked: its holder can spend what it holds once paid
--      (allocate_invoice_wallet_credit does not read the lock), but a Move
--      of it is refused ("This credit lot is locked or reversed": MVX), as for
--      471's lots a Cancel closed (transfer_invoice_unused_benefit, pinned,
--      unchanged); for the Owner, with the Move.
--   5. 470's NOT COVERED 5 (a deadlock: a session's refund held back at
--      commit against the package's refund by line or reopening's payment at
--      the same moment; one is rolled back, staff do it again), accepted by
--      the Owner for all packages (26 Oct 2026), now also for these lots (the
--      same lock order as 471's, read from the code, not timed on copies).
--   6. 471's NOT COVERED 1 to 9 are unchanged by 472 (7, the Reopen dialog's
--      credit to reinstate, and 9, a 'transfer' change of a part-paid package
--      whose released credit was spent, are their own migrations).
--   7. A summary, Finance panel or Reopen dialog open on a screen when this
--      goes in shows the old answer until it is opened again; the server
--      checks again.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the text is the tested one (its AFTER md5); the function is its BEFORE
--     (471's AFTER: replaced) or its AFTER (left alone), anything else
--     refused; no other function takes its name; so a second run changes
--     nothing;
--   * the functions it relies on are as read on production at 471 (pinned,
--     below: 471's list, unchanged by 471, and what makes 327's source
--     unspendable: credit_lot_line_allowed, credit_lot_allows_category,
--     credit_lot_policy, credit_policy_allows, credit_lot_policy_for), among
--     them every trigger function an update of invoices runs, the triggers on
--     invoices and 462's ledger trigger as read; a lot's statuses; the
--     columns read and written; one queue row per ledger row; a lot never
--     holds more than it was granted; lots and the ledger keep their history;
--     who calls the forwarder, who reads or writes a cancellation's ledger
--     rows, the queue, the amount owed back and the release record, what
--     gives credit back on a lot (and so whether it opens it), what locks a
--     lot (Cancel's write-off, an Owner's reversal, 328's repair) and what
--     writes 328's repair row, all as read;
--   * on the first run nothing is refused for the data (472 needs no
--     decision before it goes in); the invoices of the header's query 3, 4
--     and 5 are named in a notice (invoice numbers only), for the Owner;
--   * who may call the function is as read, compared as sets, and kept;
--   * afterwards: the AFTER md5 and the grants as tested.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0472, so it leaves no row): a made-up Owner, store, S$100 package, S$20
--   session and seven customers (fictional ACMA phones no customer has),
--   five times: the package sold to A and paid, sessions paid from it; (a)
--   two sessions, an Owner reverses the S$60 left, cancelled, S1 refunded: at
--   the commit point A holds nothing, the package's own lot (no lot made) at
--   S$0, 'active' and still locked, one held-back row of S$20, the reversal's
--   S$60 row as it was, the row holds back S$20; refunded by line: net S$80;
--   (b) as (a) with S$0 stated owed back (a stand-in for a guided Cancel that
--   kept it all): owed S$20, due S$20; refunded by line: net S$80; (c) as (a)
--   but still paid (a control): A's S$20 to spend, nothing held back; (d)
--   one session, cancelled, the customer changed to B ('transfer'),
--   reopened (paid at once: B's lot of S$80 replaces A's), an Owner reverses
--   B's lot, S1 refunded: B holds S$20 on a new lot that replaces B's closed
--   one, which the records name, A nothing, the reversal's row as it was;
--   (e) as (d), cancelled again before S1's refund: held back for B on that
--   new lot (S$0, the row holds back S$20).
--   Its credit ledger rows draw entry numbers (a sequence, which an undone
--   transaction does not give back: a gap, as 443 to 471's self-tests).
--   Locks: the function's catalogue row to the end of the apply, and the
--   rows the self-test writes and undoes; no table is locked against
--   ordinary writes. The self-test takes the commission advisory locks
--   (through its cancels, refunds and customer change) and new invoice
--   numbers, so it waits for any app cancel, refund, commission-writing
--   payment or invoice creation still open, and those wait for it, for under
--   a second. If one stays open longer than the 5 s lock timeout, or an
--   invoice created at the same moment takes the self-test's invoice
--   number, the apply stops, changing nothing, and can be run again. Credit
--   given back by a refund still open when 472 commits is handled by 472's
--   text at that refund's commit. Apply at a quiet time.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (471 in, 26 Oct 2026: fd61e1a1, 1387 functions; the grant
--   list 381ef69c; head 20261026142140) -> 472. 462, 463, 470 and 471 are
--   in; 472 replaces 471's credit_given_back_follows (its AFTER is 472's
--   BEFORE) and pins the rest, among them invoice_transferable_benefits and
--   invoice_reopen_preview(_before_sessions) as they are at 471: a migration
--   that changes one of them (the leftover gaps 9 and 7 of 471) goes in
--   after 472, or 472's pins are worked out again. If anything else goes in
--   first, work the fingerprints out again and check that it changes none
--   of the functions or triggers pinned below.
--   1. Before it, read only (invoice numbers and counts only; production was
--      not read for this file). 472 refuses no state, so this lists whose
--      answer changes (1, 2) and what needs the Owner (3 to 5). On the
--      production facts known (26 Oct 2026: two lots an Owner reversed and
--      one 328's repair replaced, none holding credit; no cancelled or
--      refunded invoice with a credit lot in its benefit rows; no reopening
--      waiting) 1 and 4 list nothing; 2, 3 and 5 may list invoices:
--     with
--     st as (
--       select i.id, i.status::text as status, i.cancel_refund_owed is not null as owed_stated,
--              i.status::text in ('cancelled', 'refunded')
--              or exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = i.id and q.applied_at is null) as held
--         from public.invoices i where i.deleted_at is null),
--     -- what 471 reads past: the locked lots of an invoice's credit released
--     -- before full payment that a Cancel's write-off closed, or a copy of one a
--     -- reissue made (no ledger row of an Owner's reversal or 328's repair)
--     wo as (
--       select pl.invoice_id, w.lot_id
--         from public.credit_package_progress_lots pl
--         cross join lateral unnest(public.credit_lot_chain(pl.lot_id)) w(lot_id)
--         join public.customer_credit_lots c on c.id = w.lot_id
--        where c.is_locked
--          and not exists (select 1 from public.customer_credit_ledger e
--                           where e.customer_id = c.customer_id and e.lot_id = c.id
--                             and e.source_type in ('reversal', 'credit_lot_provenance_repair'))),
--     -- lots 328's repair replaced (its ledger row)
--     rp as (
--       select distinct e.lot_id from public.customer_credit_ledger e
--        where e.source_type = 'credit_lot_provenance_repair' and e.lot_id is not null),
--     -- each lot a benefit row names and each lot it replaced (credit_lot_ancestry),
--     -- with whoever holds the benefits, and whether 472 reads where 471 passed it
--     -- over: a sale paid from the named lot, refunded, opens it; 471 passed it over
--     -- where it is locked (not 471's wo); a sale paid from a lot behind it: 471
--     -- passed it over where the named lot is closed or locked so, or that lot is
--     -- locked so; 472 passes over only a lot 328's repair replaced, and a named lot
--     -- that is closed and holds credit
--     x as (
--       select b.invoice_id, nl.id as named_id, p.id as lot_id, p.customer_id, p.status as lot_status, p.remaining_amount,
--              coalesce(public.invoice_credit_live_holder(b.invoice_id, nl.customer_id,
--                case when public.invoice_benefit_moved_to_other(b.id) then 'infinity'::timestamptz else nl.created_at end),
--                nl.customer_id) as holder,
--              case when p.id = nl.id
--                   then nl.is_locked and not exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = nl.id)
--                        and nl.id not in (select lot_id from rp)
--                   else not (nl.status <> 'active' and nl.remaining_amount > 0)
--                        and nl.id not in (select lot_id from rp) and p.id not in (select lot_id from rp)
--                        and (nl.status <> 'active'
--                             or nl.is_locked and not exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = nl.id)
--                             or p.is_locked and not exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = p.id))
--              end as reads_now
--         from public.invoice_benefit_values b
--         join public.customer_credit_lots nl on nl.id = b.lot_id
--         cross join lateral unnest(public.credit_lot_ancestry(nl.id)) a(lot_id)
--         join public.customer_credit_lots p on p.id = a.lot_id
--        where nl.is_locked or nl.status <> 'active' or p.is_locked or p.status <> 'active'),
--     sold as (
--       select x.*, st.held,
--              (select count(*) from public.invoice_line_credit_allocations a where a.lot_id = x.lot_id and a.amount > coalesce(a.reversed_amount, 0))
--              + (select count(*) from public.special_credit_allocations s where s.lot_id = x.lot_id and s.amount > coalesce(s.reversed_amount, 0)) as n
--         from x join st on st.id = x.invoice_id
--        where x.reads_now),
--     found(reason, invoice_id, n) as (
--       select '1 changes: cancelled, refunded or waiting for a reopening''s payment, with sales paid from a lot an Owner reversed that its records name, or from a lot behind such a lot or behind one they name that is closed, that can still be refunded or corrected (the credit they give back is now held back, its money added to what is owed back where that is stated; before, the customer could spend it, or it stayed with whoever it went back to) (the count is of sales)', s.invoice_id, sum(s.n)
--         from sold s where s.n > 0 and s.held
--        group by s.invoice_id
--       union all
--       select '2 changes: paid, with sales paid from such a lot that can still be refunded or corrected, where it is behind the lot the records name or held by someone other than whoever holds the benefits now (the credit they give back now goes to whoever holds the benefits; before, it stayed with whoever it went back to) (the count is of sales)', s.invoice_id, sum(s.n)
--         from sold s where s.n > 0 and not s.held and (s.lot_id <> s.named_id or s.customer_id <> s.holder)
--        group by s.invoice_id
--       union all
--       select '3 for the Owner (not changed by 472): credit spendable today on such a lot, given back before 472, while the invoice is cancelled, refunded or waiting, or behind the lot the records name, or held by someone other than whoever holds the benefits: a data fix, or left with the customer; until then the next refund or correction of a sale paid from that chain holds it back, or moves it, with the new credit (the count is of lots)', s.invoice_id, count(*)
--         from sold s where s.lot_status = 'active' and s.remaining_amount > 0 and (s.held or s.lot_id <> s.named_id or s.customer_id <> s.holder)
--        group by s.invoice_id
--       union all
--       select '4 for the Owner (not changed by 472: NOT COVERED 2): credit on a closed lot its records name, or one behind it (refund_special_credit gives credit back without opening the lot), which no one can spend (the count is of lots)', x.invoice_id, count(distinct x.lot_id)
--         from x where x.lot_status <> 'active' and x.remaining_amount > 0
--        group by x.invoice_id
--       union all
--       select '5 for the Owner (not changed by 472: NOT COVERED 1): a lot of its credit released before full payment that 328''s repair replaced, holding credit or with sales paid from it that can still be refunded or corrected (the count is of such sales, and of such lots holding credit)', pl.invoice_id,
--              sum((select count(*) from public.invoice_line_credit_allocations a where a.lot_id = l.id and a.amount > coalesce(a.reversed_amount, 0))
--                  + (select count(*) from public.special_credit_allocations s where s.lot_id = l.id and s.amount > coalesce(s.reversed_amount, 0))
--                  + case when l.remaining_amount > 0 then 1 else 0 end)
--         from rp join public.customer_credit_lots l on l.id = rp.lot_id
--         join public.credit_package_progress_lots pl on pl.lot_id = l.id
--        group by pl.invoice_id
--       having sum((select count(*) from public.invoice_line_credit_allocations a where a.lot_id = l.id and a.amount > coalesce(a.reversed_amount, 0))
--                  + (select count(*) from public.special_credit_allocations s where s.lot_id = l.id and s.amount > coalesce(s.reversed_amount, 0))
--                  + case when l.remaining_amount > 0 then 1 else 0 end) > 0)
--     select f.reason, i.invoice_no, f.n
--       from found f join public.invoices i on i.id = f.invoice_id
--      order by f.reason, i.invoice_no
--      (The suite runs this same text on its cases' states before 472 and
--      checks what it lists.)
--   2. Dry run on a copy of production as it is then: work out its
--      fingerprint and grant list first (they must be the BEFORE figures
--      below, or be worked out again on that copy); apply this file twice;
--      the first run ends at the AFTER fingerprint below, the second changes
--      nothing ("left alone"); and the suite, with the earlier suites below.
--   3. Apply (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself.
--   4. No page change goes with it (NOT CHANGED).
--   Afterwards (checked on copies of production at 471, 26 Oct 2026): a
--   re-run of 471 refuses (its forwarder is neither its BEFORE nor its
--   AFTER), changing nothing; 472's own leaves all alone. The suites that
--   check the forwarder where 472 is in (-v nomig=1):
--   plain-cancelled-package-credit-471 (S; PX, PXs, S8gb, S8gs and S2gb end
--   the 472 way; KNOWN K10 checked as 472 settles it),
--   cancelled-package-refund-470, move-merge-leftovers-462 and
--   change-store-moves-bundle-vouchers-463 (S), each by 472's AFTER md5.
--   function-grants is unchanged (nothing is added).
--
-- BEFORE (production at 471, 26 Oct 2026; md5 of pg_get_functiondef with
-- search_path public)
--   changed
--   credit_given_back_follows(uuid)                                    1417d83e7d7be49209f5cd1369d07ec7  (471's)
--   relied on, not changed (pinned; 471's list, as 471 left it)
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
--   allocate_invoice_wallet_credit(uuid,numeric,text,text)             da8aa986c92d765a8028741f33bf56b0
--   trg_legacy_refund_guard()                                          089965ef41a18fe3c54dd622e743075a
--   trg_lock_on_settle()                                               39c6478cdaec553c2ab8ceaf55058960
--   validate_invoice_business_metadata()                               c6e4436575e1c5ec8580d2b3d9d11d50
--   track_invoice_business_date_version()                              2c1e7ac8c5c2cfea8ddc5122adfc5d92
--   trg_create_therapy_on_paid()                                       012ae4e305b9870fa5596f740c0427b9
--   trg_fulfil_from_warehouse()                                        4abf4bf68e4f00658a8da66469e7059e
--   trg_issue_sold_vouchers_on_paid()                                  cf0b5610b77edfea2683751d5c25ca1d
--   writeoff_released_credit_on_close(uuid,text,text)                  284a89cfb965e8028136b5f8a4f2bf08
--   release_credit_package_paid_credit(uuid)                           530521c100163445e5a0b99799fbcccc
--   credit_package_released_paid_credit(uuid)                          6b27388462747e3c13f3da0b9ad165c0
--   capture_invoice_benefit_values(uuid)                               d5e061945c2921a1af86f8c99a349e98
--   credit_lot_chain(uuid)                                             556e725784154cbffc23d3ad900f9366
--   credit_lot_current(uuid)                                           d48fb24e6eb9733d7f867e42fa703e7b
--   trim_released_paid_credit(uuid,text,boolean)                       14ded4342c3e65eb98547d224263519f
--   reclaim_released_credit_of_removed_lines(uuid,jsonb,text)          823cd6a96c813b43bf2767dc1644e943
--   repair_credit_package_progress_lots()                              ebd2a1a9f8ce7a9c1c272168b30b5ce3
--   credit_package_money_toward_line(uuid)                             798c2d67d55bb1d140232ff06ffb1034
--   credit_line_paid_entitlement(uuid)                                 da2404a1db281b46a44231bd071a069a
--   credit_lot_source_group(uuid)                                      6b902cb426210eb10ee9a15344ff100b
--   customer_credit_balances(uuid)                                     c2287779ce0ec9c52eeec41952055f78
--   invoice_commission_benefit_source(uuid)                            f8d3d29fae79065a252a8c5231cc2d4b
--   update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean) 1f034561a461bdb46a1e6274e0d04606
--   reverse_credit_lot(uuid,text,text,text)                            10c1a3d8e3bb003fbaf01cf879f97c5e
--   (what makes 327's source unspendable: NOT COVERED 1)
--   credit_lot_line_allowed(uuid,uuid)                                 7d81252612104b1012b6d78513092091
--   credit_lot_allows_category(uuid,text)                              935acacb64f836a97f0a1b4458d70d96
--   credit_lot_policy(text,text,boolean)                               d9a97af64871c4ebcff8d1f6c15f68a6
--   credit_policy_allows(text,text)                                    504f3055b3f1c1a038c5cae217e37fd6
--   credit_lot_policy_for(uuid)                                        ccdd506e78c7cdca97194fde87cdcc42
--   the triggers on invoices (md5 of their definitions, by name)       92c94e3ebc6113a68d972330bbca8938 (19 triggers)
--   public function fingerprint, production now (471)                  fd61e1a11dce76dd9ad4348f6bb99180 (1387 functions; head 20261026142140)
--   grant list (string_agg(signature '=' proacl, '|'), sorted)          381ef69cb44f960ff981585ff8402fa1 (production lists the same
--                                                                      grants in another order: compare as sets)
-- AFTER (for later guards)
--   credit_given_back_follows(uuid)                                    f2a7a4d1ca28f0865b14e3f1e5e02bbb  (grants kept: the service role)
--   public function fingerprint, worked out on a copy of production at 471 (26 Oct 2026; a second run the same):
--     production now (471) -> 472                                      84308fd1c3570babf682c472bd6f95b2 (1387 functions: none added, none dropped)
--   grant list after 472                                               381ef69cb44f960ff981585ff8402fa1 (unchanged)
--   the triggers on invoices                                           92c94e3ebc6113a68d972330bbca8938 (19, unchanged)
--
-- Test: scripts/invoices/tests/reversed-lot-credit-held-back-472.sql (begin
-- ... rollback; it installs this file twice; -v nomig=1 where it is in). It
-- reproduces PX, PXs, S8gb, S8gs, S2gb, O1o and the closed named lot's cases
-- (RV1..., PXh, PXhc) first, then checks the header's query (1 to 5), the
-- refusals, the install, every case after 472 with 462's invariants and
-- Cancel, the held-back row in place on the lot an Owner reversed (its
-- reversal row as it was, the Audit Log, the statement), the amount owed
-- back by its money, the queue while a reopening waits and its payment, the
-- new lot replacing a closed one, cases begun before 472 and finished after,
-- the controls unchanged, and NOT COVERED 1 to 4 as KNOWN (a lot 328's
-- repair replaced, by a stand-in; 327's source spending nothing; credit on a
-- closed lot; credit given back before 472; a Move of such a lot refused).
-- Each app call is followed by what its commit does (462's trigger is
-- deferred). Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The function this changes: BEFORE (production, 26 Oct 2026: 471's
  -- AFTER) and AFTER md5s; who may call it, as read (kept) ══════════════════
  c_sig constant text := 'credit_given_back_follows(uuid)';
  c_before constant text := '1417d83e7d7be49209f5cd1369d07ec7';
  c_after constant text := 'f2a7a4d1ca28f0865b14e3f1e5e02bbb';
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
-- holder is the benefits' holder while the invoice is paid (as before; 471:
-- otherwise it is held back where it is, below), nor for a lot no invoice's
-- benefit row names or replaced (wallet credit of other kinds; 471: credit
-- released before the invoice was paid in full, below). The holder:
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
-- 471 (the Owner, 26 Oct 2026, answering 470's NOT COVERED 1: "Yes, fix it
-- after 470": the plain case works as the reissue case does; a cancel or
-- refund takes back what the invoice gave, the customer holds exactly what
-- the net payment buys, refunds paid back count as not used): where nothing
-- was reissued (the named lot alone holds it and its holder is whoever holds
-- the benefits, or no live record is left), credit given back while the
-- invoice is cancelled or refunded, or a reopening of it waits, stayed on
-- that lot and could be spent (after a guided Cancel that recorded the
-- refund, the customer kept S$20 and nothing more could be paid back; a
-- package refunded in full with an override left S$20). Now it is held back
-- for the cancellation where it is: what the named lot holds is taken back
-- on it with the cancellation's own ledger row (the same kind and reason as
-- above), added to cancelled_unused_value and, where an amount owed back is
-- stated on a cancelled invoice, its money added to that, by the same rule;
-- while a reopening waits it is queued for its payment (the latest waiting
-- request; the Owner, 26 Oct 2026, accepting 470's NOT COVERED 3), which
-- gives it back. Nothing is reissued, so nothing else is carried or closed.
-- Whether anything needs doing is read first without locks (a refund that
-- moves nothing takes no lock here); only then are the invoice, its benefit
-- row and the lots locked, in the order Cancel and Reopen take them (then
-- the reopening's queue rows on those lots), and everything read again.
-- 471 also (the same answer): paid credit released before the invoice was
-- paid in full (327, 356: no benefit row names its lot; the release record,
-- credit_package_progress_lots, does). Credit given back on such a lot while
-- its invoice is cancelled or refunded stayed there for the buyer to spend,
-- and the release record still counted it as spent, so a plain Cancel could
-- not record the money paid back. Now it is taken back as Cancel's write-off
-- takes it (writeoff_released_credit_on_close's kind of row:
-- 'adjust_decrease', 'invoice_cancel_released_credit', or
-- 'invoice_refund_released_credit' when refunded, the invoice), the release
-- record counts that much less as spent, and the lot is closed again
-- ('reversed', locked), as Cancel left it; where an amount owed back is
-- stated on a cancelled invoice, S$1 is added to it for each S$1 held back
-- (credit is released S$1 for each S$1 received). Nothing is held while the
-- invoice is open again: its reopening released again the credit its money
-- buys (356). Read first without locks, then the invoice, the lot and the
-- release record locked in Cancel's order, and read again.
-- 471 also: such a lot that Cancel's write-off closed ('reversed', locked)
-- and a benefit row names once the invoice was reopened and paid in full
-- (capture_invoice_benefit_values names it) is opened again by a refund or
-- a correction of a sale paid from it ('active', still locked); it was
-- passed over as locked, so the credit stayed there for its holder to
-- spend, cancelled or not, and did not follow a 'transfer' change. Such a
-- lock is no longer a reason to pass it over (an Owner's reversal and
-- 328's repair still are): it is held back, or follows the benefits'
-- holder, as above.
-- 472 (the Owner, 26 Oct 2026: "fix the leftover gaps too", 471's NOT
-- COVERED 10: an Owner's reversal stays reversed, what it took stays taken,
-- and credit a refund gives back after it is the session's credit and
-- follows the same rules as 471's): a lot an Owner reversed
-- (reverse_credit_lot: 'reversed', locked, its 'reversal' ledger row) that a
-- refund or a correction of a sale paid from it opened again ('active',
-- still locked) was passed over, so while its invoice was cancelled, refunded
-- or waiting that credit stayed there for its holder to spend (after a guided
-- Cancel nothing more could be paid back), and it did not follow the
-- benefits' holder; and where the lot the records name was closed at S$0 (an
-- Owner reversed it), credit given back on a lot behind it stayed there. Now
-- a lock is no reason to pass a lot over, but 328's repair's (its
-- 'credit_lot_provenance_repair' row: such a lot carries 327's source, which
-- no credit payment could draw on, and no lot an invoice's records name
-- continues it); a lot the records name that is closed and holds nothing is
-- read too, so what is behind it follows; a closed lot holding credit
-- (refund_special_credit puts credit back without opening the lot) is passed
-- over, as before. Only what a lot holds is drawn, and an Owner's reversal
-- left nothing on it: what the reversal took stays taken.
declare v_try int:=0; v_k int; v_cur uuid; v_prev uuid; v_inv uuid; v_locked boolean:=false; v_status text;
 b public.invoice_benefit_values%rowtype; n public.customer_credit_lots%rowtype; x record;
 v_chain uuid[]; v_h uuid; v_more boolean; v_total numeric:=0; v_new uuid; v_wallet uuid; v_cap numeric;
 v_from jsonb:='[]'::jsonb; v_parent uuid; v_up uuid; v_depth int; v_replace boolean;
 -- 470
 v_hold boolean:=false; v_wait uuid; v_carry numeric:=0; v_held jsonb:='[]'::jsonb; v_mark uuid; v_take uuid; hb record;
 v_owed numeric; v_owed_new numeric; v_owed_add numeric;
 -- 471
 v_plain boolean:=false; v_rel uuid; v_rel_amt numeric;
 -- 472
 v_rp uuid[]:='{}';
 c_reason constant text:='Credit given back goes to whoever holds the invoice''s benefits now';
 c_held constant text:='Held back by the invoice''s cancellation for whoever holds its benefits now';
 c_held_rel constant text:='Held back by the invoice''s cancellation: credit released before it was paid in full';
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
  if v_cur is null then exit; end if;
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
  -- 471: a lot of the invoice's credit released before full payment that a
  -- Cancel's write-off closed ('reversed', locked), and that a refund or a
  -- correction has opened again ('active', still locked), is read as any
  -- other lot here, also where a benefit row names it after the invoice was
  -- reopened and paid in full. 472: so is a lot an Owner reversed (opened
  -- again so, or closed at S$0 and named, with credit behind it); a lot
  -- 328's repair replaced is not, nor a closed lot holding credit (as before).
  if n.status<>'active' and n.remaining_amount>0 then return; end if;
  v_chain:=public.credit_lot_ancestry(n.id);
  v_rp:=array(select c.id from public.customer_credit_lots c
               where c.id=any(v_chain) and c.is_locked
                 and exists(select 1 from public.customer_credit_ledger e
                             where e.customer_id=c.customer_id and e.lot_id=c.id
                               and e.source_type='credit_lot_provenance_repair'));
  if n.id=any(v_rp) then return; end if;
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
                  where l.id=any(v_chain) and l.id<>n.id and l.remaining_amount>0 and l.status='active'
                    and not (l.id=any(v_rp)));
  -- 471: the named lot alone holds it and its holder is the benefits' (or no
  -- live record is left), while the cancellation holds back what the invoice
  -- gave: held back where it is.
  v_plain:=v_hold and not v_more and n.remaining_amount>0 and (v_h is null or n.customer_id=v_h);
  if not v_plain and not v_more and (n.remaining_amount<=0 or n.customer_id=v_h or v_h is null) then return; end if;
  if v_h is null and not v_plain then
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
 if v_cur is null then
  -- 471: no benefit row names it. The release record whose lots reach it:
  -- this lot or one it replaced (a merge's or customer change's reissue,
  -- or 328's replacement), as credit_lot_chain reads them forward.
  v_up:=p_lot_id; v_depth:=0; v_rel:=null;
  loop
   select pl.lot_id,pl.invoice_id into v_rel,v_inv from public.credit_package_progress_lots pl
    where pl.lot_id=v_up and pl.released_amount>0;
   exit when v_rel is not null;
   v_parent:=(select l.reassigned_from_lot_id from public.customer_credit_lots l where l.id=v_up);
   if v_parent is null then
    v_parent:=(select pl.replaces_lot_id from public.credit_package_progress_lots pl where pl.lot_id=v_up);
   end if;
   v_depth:=v_depth+1;
   exit when v_parent is null or v_depth>12;
   v_up:=v_parent;
  end loop;
  if v_rel is null or not (p_lot_id=any(public.credit_lot_chain(v_rel))) then return; end if;
  -- As Cancel's write-off: a settled line's benefit rows own its lots.
  if exists(select 1 from public.invoice_benefit_values bv where bv.lot_id=any(public.credit_lot_chain(v_rel))) then return; end if;
  if (select i.status::text from public.invoices i where i.id=v_inv) is distinct from 'cancelled'
     and (select i.status::text from public.invoices i where i.id=v_inv) is distinct from 'refunded' then return; end if;
  if coalesce((select l.remaining_amount from public.customer_credit_lots l where l.id=p_lot_id),0)<=0 then return; end if;
  perform 1 from public.invoices where id=v_inv for update;
  select * into n from public.customer_credit_lots where id=p_lot_id for update;
  select pl.released_amount into v_rel_amt from public.credit_package_progress_lots pl where pl.lot_id=v_rel for update;
  select i.status::text,i.cancel_refund_owed into v_status,v_owed from public.invoices i where i.id=v_inv;
  if coalesce(v_status,'') not in ('cancelled','refunded') or coalesce(n.remaining_amount,0)<=0 then return; end if;
  v_total:=n.remaining_amount;
  insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
   values(n.wallet_id,n.customer_id,'adjust_decrease',n.category,v_total,n.id,
          case when v_status='cancelled' then 'invoice_cancel_released_credit' else 'invoice_refund_released_credit' end,
          v_inv,n.store_id,c_held_rel,auth.uid(),auth.uid());
  update public.credit_package_progress_lots set released_amount=greatest(released_amount-v_total,0) where lot_id=v_rel;
  update public.customer_credit_lots set remaining_amount=0,status='reversed',is_locked=true,updated_at=now() where id=n.id;
  if v_status='cancelled' and v_owed is not null then
   v_owed_add:=v_total;
   v_owed_new:=v_owed+v_owed_add;
   update public.invoices set cancel_refund_owed=v_owed_new where id=v_inv;
  end if;
  perform public.write_audit_ex('invoices',v_inv,'credit_given_back_followed',null,
    jsonb_build_object('lot_id',n.id,'to_customer',n.customer_id,'amount',v_total,
      'from',jsonb_build_array(jsonb_build_object('lot_id',n.id,'customer_id',n.customer_id,'amount',v_total)),
      'benefit_id',null,'replaces_lot_id',null,'in_place_of_lot_id',null,'held_in_place',true,
      'released_credit',true,'release_lot_id',v_rel,'released_before',v_rel_amt,
      'released_after',greatest(coalesce(v_rel_amt,0)-v_total,0),
      'held_back',v_total,'queued_for_request',null,
      'refund_owed',v_owed,'refund_owed_added',v_owed_add,'refund_owed_now',v_owed_new),
    'invoices',c_held_rel,(select store_id from public.invoices where id=v_inv));
  return;
 end if;
 if v_plain then
  -- 471: held back where it is, for the cancellation: taken back on the
  -- named lot as the cancellation's own row (queued for a waiting
  -- reopening's payment), held back by the row and, where an amount owed
  -- back is stated on a cancelled invoice, owed back in money (as below).
  v_total:=n.remaining_amount;
  update public.customer_credit_lots set remaining_amount=0,updated_at=now() where id=n.id;
  insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
   values(n.wallet_id,n.customer_id,'adjust_decrease',n.category,v_total,n.id,'invoice_cancel_benefit',b.invoice_id,n.store_id,c_held,auth.uid(),auth.uid())
   returning id into v_take;
  if v_wait is not null then
   insert into public.invoice_reopen_benefits(invoice_id,source_ledger_id,request_id,amount,created_by)
    values(b.invoice_id,v_take,v_wait,v_total,auth.uid());
  end if;
  update public.invoice_benefit_values set cancelled_unused_value=cancelled_unused_value+v_total where id=b.id;
  select cancel_refund_owed into v_owed from public.invoices where id=b.invoice_id;
  if v_status='cancelled' and v_owed is not null then
   v_owed_add:=case when b.paid_value>0 and b.granted_value>0
                    then round(b.paid_value*(b.cancelled_unused_value+v_total)/b.granted_value,2)
                         -round(b.paid_value*b.cancelled_unused_value/b.granted_value,2)
                    else 0 end;
   v_owed_new:=v_owed+v_owed_add;
   update public.invoices set cancel_refund_owed=v_owed_new where id=b.invoice_id;
  end if;
  perform public.write_audit_ex('invoices',b.invoice_id,'credit_given_back_followed',null,
    jsonb_build_object('lot_id',n.id,'to_customer',n.customer_id,'amount',v_total,
      'from',jsonb_build_array(jsonb_build_object('lot_id',n.id,'customer_id',n.customer_id,'amount',v_total)),
      'benefit_id',b.id,'replaces_lot_id',null,'in_place_of_lot_id',null,'held_in_place',true,
      'held_back',v_total,'held_back_before',0,'held_back_rows','[]'::jsonb,'held_back_mark',null,'queued_for_request',v_wait,
      'refund_owed',v_owed,'refund_owed_added',v_owed_add,'refund_owed_now',v_owed_new),
    'invoices',c_held,(select store_id from public.invoices where id=b.invoice_id));
  return;
 end if;
 if exists(select 1 from public.customer_credit_lots l
            where l.id=any(v_chain) and l.remaining_amount>0 and l.status='active' and not (l.id=any(v_rp))
              and l.category is distinct from n.category) then
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
           where l.id=any(v_chain) and l.remaining_amount>0 and l.status='active' and not (l.id=any(v_rp))
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

  -- ══ Relied on, not changed (production at 471, 26 Oct 2026: 471's list,
  -- unchanged since, then what makes 327's source unspendable) ═══════════════
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
    'allocate_invoice_wallet_credit(uuid,numeric,text,text)',
    'trg_legacy_refund_guard()',
    'trg_lock_on_settle()',
    'validate_invoice_business_metadata()',
    'track_invoice_business_date_version()',
    'trg_create_therapy_on_paid()',
    'trg_fulfil_from_warehouse()',
    'trg_issue_sold_vouchers_on_paid()',
    'writeoff_released_credit_on_close(uuid,text,text)',
    'release_credit_package_paid_credit(uuid)',
    'credit_package_released_paid_credit(uuid)',
    'capture_invoice_benefit_values(uuid)',
    'credit_lot_chain(uuid)',
    'credit_lot_current(uuid)',
    'trim_released_paid_credit(uuid,text,boolean)',
    'reclaim_released_credit_of_removed_lines(uuid,jsonb,text)',
    'repair_credit_package_progress_lots()',
    'credit_package_money_toward_line(uuid)',
    'credit_line_paid_entitlement(uuid)',
    'credit_lot_source_group(uuid)',
    'customer_credit_balances(uuid)',
    'invoice_commission_benefit_source(uuid)',
    'update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)',
    'reverse_credit_lot(uuid,text,text,text)',
    'credit_lot_line_allowed(uuid,uuid)',
    'credit_lot_allows_category(uuid,text)',
    'credit_lot_policy(text,text,boolean)',
    'credit_policy_allows(text,text)',
    'credit_lot_policy_for(uuid)'];
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
    'da8aa986c92d765a8028741f33bf56b0',
    '089965ef41a18fe3c54dd622e743075a',
    '39c6478cdaec553c2ab8ceaf55058960',
    'c6e4436575e1c5ec8580d2b3d9d11d50',
    '2c1e7ac8c5c2cfea8ddc5122adfc5d92',
    '012ae4e305b9870fa5596f740c0427b9',
    '4abf4bf68e4f00658a8da66469e7059e',
    'cf0b5610b77edfea2683751d5c25ca1d',
    '284a89cfb965e8028136b5f8a4f2bf08',
    '530521c100163445e5a0b99799fbcccc',
    '6b27388462747e3c13f3da0b9ad165c0',
    'd5e061945c2921a1af86f8c99a349e98',
    '556e725784154cbffc23d3ad900f9366',
    'd48fb24e6eb9733d7f867e42fa703e7b',
    '14ded4342c3e65eb98547d224263519f',
    '823cd6a96c813b43bf2767dc1644e943',
    'ebd2a1a9f8ce7a9c1c272168b30b5ce3',
    '798c2d67d55bb1d140232ff06ffb1034',
    'da2404a1db281b46a44231bd071a069a',
    '6b902cb426210eb10ee9a15344ff100b',
    'c2287779ce0ec9c52eeec41952055f78',
    'f8d3d29fae79065a252a8c5231cc2d4b',
    '1f034561a461bdb46a1e6274e0d04606',
    '10c1a3d8e3bb003fbaf01cf879f97c5e',
    '7d81252612104b1012b6d78513092091',
    '935acacb64f836a97f0a1b4458d70d96',
    'd9a97af64871c4ebcff8d1f6c15f68a6',
    '504f3055b3f1c1a038c5cae217e37fd6',
    'ccdd506e78c7cdca97194fde87cdcc42'];
  -- Who calls the forwarder; who reads or writes a cancellation's ledger
  -- rows, the reopening queue and the amount owed back; what writes a
  -- 'reverse' ledger row and what raises a lot's balance; who reads or
  -- writes the release record and its write-off rows; what locks a lot (by
  -- name; a session's own temporary functions and the forwarder itself are
  -- not counted), as read on production at 471 (26 Oct 2026; as 471 read
  -- them, unchanged by it). And what writes 328's repair row, by which the
  -- forwarder tells the one lock it still passes over.
  c_callers constant text := 'trg_credit_given_back_follows()';
  c_cancel_rows constant text := 'cancel_invoice_recorded(uuid,text,uuid), credit_lot_policy(text,text,boolean), invoice_benefit_unused_elsewhere(uuid), invoice_reopen_preview_before_sessions(uuid), reopen_invoice(uuid,text,uuid)';
  c_queue_inserts constant text := 'reopen_invoice(uuid,text,uuid)';
  c_queue_updates constant text := 'apply_reopened_invoice_benefits(), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)';
  c_owed_writers constant text := 'cancel_invoice_recorded(uuid,text,uuid), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)';
  c_reverse_writers constant text := 'apply_reopened_invoice_benefits(), correct_invoice_payment(uuid,numeric,date,uuid,text,uuid), customer_credit_statement(uuid,date,date), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), refund_special_credit(text,uuid), repair_credit_package_progress_lots(), reverse_credit_lot(uuid,text,text,text), reverse_invoice_date_recovery(uuid,uuid,text)';
  c_raisers constant text := 'apply_reopened_invoice_benefits(), correct_invoice_payment(uuid,numeric,date,uuid,text,uuid), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), refund_special_credit(text,uuid)';
  c_release_rw constant text := 'cancelled_invoice_used_value(uuid), capture_invoice_benefit_values(uuid), credit_lot_chain(uuid), credit_lot_source_group(uuid), credit_package_money_toward_line(uuid), credit_package_released_paid_credit(uuid), customer_credit_balances(uuid), invoice_commission_benefit_source(uuid), invoice_credit_lot_ids(uuid), move_invoice_benefits_to_customer(uuid,uuid,uuid,text), reclaim_released_credit_of_removed_lines(uuid,jsonb,text), release_credit_package_paid_credit(uuid), repair_credit_package_progress_lots(), trg_create_therapy_on_paid(), trim_released_paid_credit(uuid,text,boolean), writeoff_released_credit_on_close(uuid,text,text)';
  c_release_kinds constant text := 'cancel_invoice_recorded(uuid,text,uuid), cancelled_invoice_used_value(uuid), reclaim_released_credit_of_removed_lines(uuid,jsonb,text), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), trim_released_paid_credit(uuid,text,boolean), update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean), writeoff_released_credit_on_close(uuid,text,text)';
  c_lockers constant text := 'repair_credit_package_progress_lots(), reverse_credit_lot(uuid,text,text,text), writeoff_released_credit_on_close(uuid,text,text)';
  c_repair_rows constant text := 'repair_credit_package_progress_lots()';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; n int; i int; v_first boolean; v_acl text;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_pk uuid; t_svc uuid; t_wallet uuid;
  t_case int; t_a uuid; t_b uuid; t_inv uuid; t_s1 uuid; t_s2 uuid; t_item uuid; t_ben uuid; t_rcpt uuid; t_lot0 uuid;
  t_lot1 uuid; t_lot uuid; t_rev uuid;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The text is the tested one.
  if md5(c_def_follows) <> c_after then
    raise exception '472: the text in this file is not the tested one'; end if;

  -- The functions relied on are as read on production (at 471, 26 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '472: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if to_regprocedure('auth.uid()') is null then raise exception '472: auth.uid() must be there'; end if;

  -- The columns read and written, with these types (471's list, and the
  -- lot's status and lock).
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('customer_credit_lots', 'id', 'uuid'), ('customer_credit_lots', 'customer_id', 'uuid'),
                 ('customer_credit_lots', 'wallet_id', 'uuid'), ('customer_credit_lots', 'store_id', 'uuid'),
                 ('customer_credit_lots', 'category', 'text'), ('customer_credit_lots', 'status', 'text'),
                 ('customer_credit_lots', 'is_locked', 'boolean'), ('customer_credit_lots', 'original_amount', 'numeric(12,2)'),
                 ('customer_credit_lots', 'remaining_amount', 'numeric(12,2)'), ('customer_credit_lots', 'reassigned_from_lot_id', 'uuid'),
                 ('customer_credit_lots', 'source_type', 'text'), ('customer_credit_lots', 'source_record_id', 'uuid'),
                 ('customer_credit_lots', 'created_at', 'timestamp with time zone'),
                 ('customer_credit_ledger', 'id', 'uuid'), ('customer_credit_ledger', 'lot_id', 'uuid'),
                 ('customer_credit_ledger', 'wallet_id', 'uuid'), ('customer_credit_ledger', 'customer_id', 'uuid'),
                 ('customer_credit_ledger', 'category', 'text'), ('customer_credit_ledger', 'store_id', 'uuid'),
                 ('customer_credit_ledger', 'entry_type', 'text'), ('customer_credit_ledger', 'source_type', 'text'),
                 ('customer_credit_ledger', 'source_record_id', 'uuid'), ('customer_credit_ledger', 'amount', 'numeric(12,2)'),
                 ('customer_credit_ledger', 'reason', 'text'), ('customer_credit_ledger', 'entry_seq', 'bigint'),
                 ('invoice_benefit_values', 'id', 'uuid'), ('invoice_benefit_values', 'invoice_id', 'uuid'),
                 ('invoice_benefit_values', 'lot_id', 'uuid'), ('invoice_benefit_values', 'cancelled_unused_value', 'numeric(12,2)'),
                 ('invoice_benefit_values', 'paid_value', 'numeric(12,2)'), ('invoice_benefit_values', 'granted_value', 'numeric(12,2)'),
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
                 ('special_credit_allocations', 'reversed_amount', 'numeric(14,2)'),
                 ('credit_package_progress_lots', 'lot_id', 'uuid'), ('credit_package_progress_lots', 'invoice_id', 'uuid'),
                 ('credit_package_progress_lots', 'released_amount', 'numeric(12,2)'), ('credit_package_progress_lots', 'replaces_lot_id', 'uuid')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '472: these columns are missing or not as read on 26 Oct 2026: %', v; end if;
  -- One queue row per ledger row; a lot never holds more than it was
  -- granted; a lot is 'active' or 'reversed'; lots and the ledger keep their
  -- history.
  if not exists (select 1 from pg_constraint where conrelid = 'public.invoice_reopen_benefits'::regclass and contype = 'u'
                  and pg_get_constraintdef(oid) = 'UNIQUE (source_ledger_id)')
     or not exists (select 1 from pg_constraint where conrelid = 'public.customer_credit_lots'::regclass
                     and conname = 'credit_lot_remaining_within_original' and pg_get_constraintdef(oid) = 'CHECK ((remaining_amount <= original_amount))')
     or not exists (select 1 from pg_constraint where conrelid = 'public.customer_credit_lots'::regclass and contype = 'c'
                     and pg_get_constraintdef(oid) = 'CHECK ((status = ANY (ARRAY[''active''::text, ''reversed''::text])))')
     or not exists (select 1 from pg_trigger where tgrelid = 'public.customer_credit_ledger'::regclass and tgname = 'credit_ledger_immutable'
                     and not tgisinternal and tgenabled = 'O')
     or not exists (select 1 from pg_trigger where tgrelid = 'public.customer_credit_lots'::regclass and tgname = 'credit_lot_immutable'
                     and not tgisinternal and tgenabled = 'O') then
    raise exception '472: the queue''s one row per ledger row, a lot''s ceiling or statuses, or the history guards are not as read on 26 Oct 2026'; end if;
  -- 462's ledger trigger, the reopening's settlement and the triggers on
  -- invoices, as they were read (the forwarder updates invoices).
  if (select pg_get_triggerdef(oid) from pg_trigger where tgrelid = 'public.customer_credit_ledger'::regclass
       and tgname = 'credit_given_back_follows') is distinct from c_ledger_trg_def
     or (select pg_get_triggerdef(oid) from pg_trigger where tgrelid = 'public.invoices'::regclass
          and tgname = 'invoice_reopen_benefits_settled') is distinct from c_settle_trg_def then
    raise exception '472: 462''s trigger credit_given_back_follows or the reopening''s settlement trigger is not as made; 472 goes in after 462, 463, 470 and 471'; end if;
  select md5(string_agg(pg_get_triggerdef(oid), E'\n' order by tgname)), count(*) into v, n
    from pg_trigger where tgrelid = 'public.invoices'::regclass and not tgisinternal;
  if v is distinct from c_inv_trg_md5 or n <> c_inv_trg_n then
    raise exception '472: the triggers on invoices are not as read on 26 Oct 2026 (% triggers, md5 %); check what an update of an invoice''s amount owed back runs, then re-test', n, v; end if;

  -- No other function takes the name (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'credit_given_back_follows'
     and p.oid::regprocedure::text <> c_sig;
  if v is not null then raise exception '472: another function takes the name of the one this changes: %', v; end if;

  -- Who calls the forwarder; who reads or writes a cancellation's rows, the
  -- queue and the amount owed back; what gives credit back on a lot; the
  -- release record; what locks a lot; what writes 328's repair row: as read
  -- (a new way would need the same care).
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'credit_given_back_follows\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  if v is distinct from c_callers then
    raise exception '472: the functions that call credit_given_back_follows are not as read on 26 Oct 2026 (%)', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ '''invoice_cancel_benefit''' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  if v is distinct from c_cancel_rows then
    raise exception '472: what reads or writes a cancellation''s ledger rows is not as read on 26 Oct 2026 (%)', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'insert\s+into\s+public\.invoice_reopen_benefits' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'update\s+public\.invoice_reopen_benefits' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  if v is distinct from c_queue_inserts or d is distinct from c_queue_updates then
    raise exception '472: what writes the reopening''s queue is not as read on 26 Oct 2026 (% / %)', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'cancel_refund_owed\s*=' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  if v is distinct from c_owed_writers then
    raise exception '472: what writes the amount owed back is not as read on 26 Oct 2026 (%)', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ '''reverse''' and ns.nspname not like 'pg\_temp\_%';
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'remaining_amount\s*=\s*(\w+\.)?remaining_amount\s*\+' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_reverse_writers or d is distinct from c_raisers then
    raise exception '472: what gives credit back on a lot is not as read on 26 Oct 2026 (% / %); check that 462''s trigger forwards each, and which opens the lot, then re-test', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'credit_package_progress_lots' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ '_released_credit' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  if v is distinct from c_release_rw or d is distinct from c_release_kinds then
    raise exception '472: what reads or writes the release record of credit released before full payment, or its write-off rows, is not as read on 26 Oct 2026 (% / %)', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'is_locked\s*=\s*true' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ '''credit_lot_provenance_repair''' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'credit_given_back_follows';
  if v is distinct from c_lockers or d is distinct from c_repair_rows then
    raise exception '472: what locks a credit lot, or writes 328''s repair row, is not as read on 26 Oct 2026 (% / %); check whether the forwarder may read past that lock, then re-test', v, d; end if;

  -- The function: its BEFORE (471's AFTER: replaced) or its AFTER (left alone).
  d := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  if md5(d) = c_after then
    raise notice '472: public.% is already this version; left alone', c_sig;
    v_first := false;
  elsif md5(d) = c_before then
    v_first := true;
  else
    raise exception '472: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig, md5(d);
  end if;

  -- ── On the first run: nothing is refused for the data (472 needs no
  -- decision before it goes in), but what needs the Owner's decision is
  -- named (the header's read-only query, 3 to 5): credit given back before
  -- 472 on a lot an Owner reversed (or behind a lot the records name that is
  -- closed) and spendable today where the cancellation holds back what the
  -- invoice gave, or held by someone other than whoever holds the benefits;
  -- credit on a closed lot (refund_special_credit); and sales paid from a
  -- lot 328's repair replaced, or credit on one. 472 does not change it; the
  -- next refund or correction of a sale paid from that chain holds back, or
  -- moves, the first with the new credit (NOT COVERED 3).
  if v_first then
    with wo as (
      select pl.invoice_id, w.lot_id
        from public.credit_package_progress_lots pl
        cross join lateral unnest(public.credit_lot_chain(pl.lot_id)) w(lot_id)
        join public.customer_credit_lots c on c.id = w.lot_id
       where c.is_locked
         and not exists (select 1 from public.customer_credit_ledger e
                          where e.customer_id = c.customer_id and e.lot_id = c.id
                            and e.source_type in ('reversal', 'credit_lot_provenance_repair'))),
    x as (
      select b.invoice_id, nl.id as named_id, p.id as lot_id, p.customer_id, p.status as lot_status, p.remaining_amount,
             coalesce(public.invoice_credit_live_holder(b.invoice_id, nl.customer_id,
               case when public.invoice_benefit_moved_to_other(b.id) then 'infinity'::timestamptz else nl.created_at end),
               nl.customer_id) as holder,
             case when p.id = nl.id
                  then nl.is_locked and not exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = nl.id)
                       and not exists (select 1 from public.customer_credit_ledger e where e.customer_id = nl.customer_id and e.lot_id = nl.id
                                        and e.source_type = 'credit_lot_provenance_repair')
                  else not (nl.status <> 'active' and nl.remaining_amount > 0)
                       and not exists (select 1 from public.customer_credit_ledger e where e.customer_id = nl.customer_id and e.lot_id = nl.id
                                        and e.source_type = 'credit_lot_provenance_repair')
                       and not exists (select 1 from public.customer_credit_ledger e where e.customer_id = p.customer_id and e.lot_id = p.id
                                        and e.source_type = 'credit_lot_provenance_repair')
                       and (nl.status <> 'active'
                            or nl.is_locked and not exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = nl.id)
                            or p.is_locked and not exists (select 1 from wo where wo.invoice_id = b.invoice_id and wo.lot_id = p.id))
             end as reads_now
        from public.invoice_benefit_values b
        join public.customer_credit_lots nl on nl.id = b.lot_id
        cross join lateral unnest(public.credit_lot_ancestry(nl.id)) a(lot_id)
        join public.customer_credit_lots p on p.id = a.lot_id
       where nl.is_locked or nl.status <> 'active' or p.is_locked or p.status <> 'active')
    select count(distinct x.invoice_id), string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into n, v
      from x join public.invoices iv on iv.id = x.invoice_id and iv.deleted_at is null
     where x.reads_now and x.lot_status = 'active' and x.remaining_amount > 0
       and (iv.status in ('cancelled', 'refunded')
            or exists (select 1 from public.invoice_reopen_benefits w where w.invoice_id = iv.id and w.applied_at is null)
            or x.lot_id <> x.named_id or x.customer_id <> x.holder);
    if n > 0 then
      raise notice '472: % invoice(s) hold credit spendable today on a lot an Owner reversed, or behind a closed lot their records name, given back before 472, while cancelled, refunded or waiting for a reopening''s payment, or held by someone other than whoever holds their benefits (%): for the Owner (a data fix, or left as it is); not changed by 472', n, v;
    end if;
    select count(distinct b.invoice_id), string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into n, v
      from public.invoice_benefit_values b
      join public.invoices iv on iv.id = b.invoice_id and iv.deleted_at is null
      join public.customer_credit_lots p on b.lot_id is not null and p.id = any (public.credit_lot_ancestry(b.lot_id))
     where p.status <> 'active' and p.remaining_amount > 0;
    if n > 0 then
      raise notice '472: % invoice(s) have credit on a closed lot their records name, or behind it (refund_special_credit gives credit back without opening the lot), which no one can spend (%): for the Owner; not changed by 472 (NOT COVERED 2)', n, v;
    end if;
    select count(distinct l.id), string_agg(distinct coalesce(iv.invoice_no, '(no invoice)'), ', ') into n, v
      from public.customer_credit_lots l
      left join public.credit_package_progress_lots pl on pl.lot_id = l.id
      left join public.invoices iv on iv.id = pl.invoice_id
     where exists (select 1 from public.customer_credit_ledger e where e.customer_id = l.customer_id and e.lot_id = l.id
                    and e.source_type = 'credit_lot_provenance_repair')
       and (l.remaining_amount > 0
            or exists (select 1 from public.invoice_line_credit_allocations a where a.lot_id = l.id and a.amount > coalesce(a.reversed_amount, 0))
            or exists (select 1 from public.special_credit_allocations s where s.lot_id = l.id and s.amount > coalesce(s.reversed_amount, 0)));
    if n > 0 then
      raise notice '472: % lot(s) that 328''s repair replaced hold credit or have sales paid from them that can still be refunded or corrected (%): for the Owner; 472 passes such a lot over, as before (NOT COVERED 1)', n, v;
    end if;
  end if;

  -- Who may call it, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig))
     is distinct from (select array_agg(x::text order by x::text) from unnest(c_acl::aclitem[]) x) then
    raise exception '472: who may call public.% is not as read on 26 Oct 2026 (%)', c_sig,
      (select proacl::text from pg_proc where oid = to_regprocedure('public.' || c_sig)); end if;
  v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig));

  -- ── Change ──────────────────────────────────────────────────────────────
  if v_first then
    execute c_def_follows;
  end if;

  -- ── Afterwards: installed exactly as tested, grants as before ───────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_after then
    raise exception '472: public.% is not at its AFTER md5 (%)', c_sig, md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))); end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig)) is distinct from v_acl then
    raise exception '472: the grants of public.% changed', c_sig; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("472 check", @example.invalid, fictional ACMA
  -- phones no customer uses); it ends by raising P0472, which undoes all it
  -- wrote. 462's trigger runs at commit; here at each step's end (SET
  -- CONSTRAINTS ... IMMEDIATE), as a commit would.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from generate_series(800, 899) g, lateral (select '+61491570' || g::text as p) x
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p desc limit 7);
    if coalesce(cardinality(t_phones), 0) < 7 then raise exception '472: the self-test found no seven unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '472-check-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '472 check', '472-check-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('472 check ' || t_sfx, '472-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('472 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy, grants_reward)
    values ('472 check ' || t_sfx, 100, 100, false, true, true, false) returning id into t_pk;
    insert into public.credit_package_stores (package_id, store_id) values (t_pk, t_store);
    insert into public.therapy_services (service_code, name, standard_price, duration_minutes, is_active)
    values ('472-' || t_sfx, '472 check ' || t_sfx, 20, 30, true) returning id into t_svc;
    insert into public.therapy_service_stores (service_id, store_id, is_available) values (t_svc, t_store, true);
    select pm.id into t_wallet from public.payment_methods pm
     where pm.name = 'Wallet — Credit Package Paid' and pm.is_wallet_credit and pm.deleted_at is null;
    if t_wallet is null then raise exception '472: the wallet method "Wallet — Credit Package Paid" (443) is not there'; end if;

    for t_case in 1 .. 5 loop
      -- The common part: the package sold to A and paid in full, a S$20
      -- session paid from it (two in (a), (b) and (c)).
      insert into public.customers (full_name, phone) values ('472 Check Buyer ' || t_case || ' ' || t_sfx, t_phones[t_case]) returning id into t_a;
      t_inv := public.create_invoice(t_store, t_a, null::uuid,
        jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
      perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
      select b.id, b.lot_id into t_ben, t_lot0 from public.invoice_benefit_values b where b.invoice_id = t_inv;
      select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv;
      select p.id into t_rcpt from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1;
      t_s1 := public.create_invoice(t_store, t_a, null::uuid,
        jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
      perform public.record_invoice_payment(t_s1, jsonb_build_array(jsonb_build_object('payment_method_id', t_wallet, 'amount', 20)), gen_random_uuid());
      if t_case in (1, 2, 3) then
        t_s2 := public.create_invoice(t_store, t_a, null::uuid,
          jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 1)),
          0::numeric, null::text, null::uuid, '[]'::jsonb);
        perform public.record_invoice_payment(t_s2, jsonb_build_array(jsonb_build_object('payment_method_id', t_wallet, 'amount', 20)), gen_random_uuid());
      end if;
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      if t_case in (1, 2, 3) then
        -- (a), (b), (c): an Owner reverses the S$60 left on the package's
        -- own lot ('reversed', locked, its 'reversal' row).
        t_rev := public.reverse_credit_lot(t_lot0, '472 check');
        if t_case in (1, 2) then
          perform public.cancel_invoice_recorded(t_inv, '472 check', gen_random_uuid());
        end if;
        if t_case = 2 then
          -- (b) a stand-in for a guided Cancel that kept it all (S$0 owed back).
          update public.invoices set cancel_refund_owed = 0 where id = t_inv;
        end if;
      else
        -- (d), (e): cancelled, the customer changed to B ('transfer'), reopened
        -- (paid at once: the reopening gives B a lot that replaces A's), and an
        -- Owner reverses B's S$80 (the lot the records name, closed at S$0);
        -- in (e) cancelled again.
        perform public.cancel_invoice_recorded(t_inv, '472 check', gen_random_uuid());
        insert into public.customers (full_name, phone) values ('472 Check Holder ' || t_case || ' ' || t_sfx, t_phones[t_case + 2]) returning id into t_b;
        perform public.correct_invoice(t_inv,
          (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
                    'credit_package_id', it.credit_package_id, 'quantity', it.quantity, 'unit_price', it.unit_price)) order by it.id)
             from public.invoice_items it where it.invoice_id = t_inv),
          jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = t_inv),
            'customer_id', t_b, 'store_id', t_store, 'benefit_action', 'transfer'),
          '472 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        perform public.reopen_invoice(t_inv, '472 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        select b.lot_id into t_lot1 from public.invoice_benefit_values b where b.id = t_ben;
        if (select status::text from public.invoices where id = t_inv) <> 'paid' or t_lot1 = t_lot0
           or (select customer_id from public.customer_credit_lots where id = t_lot1) <> t_b
           or (select remaining_amount from public.customer_credit_lots where id = t_lot1) <> 80 then
          raise exception '472: (%) the reopening did not give B the S$80 on a lot of B''s', chr(96 + t_case); end if;
        t_rev := public.reverse_credit_lot(t_lot1, '472 check');
        if t_case = 5 then
          perform public.cancel_invoice_recorded(t_inv, '472 check', gen_random_uuid());
        end if;
      end if;
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      -- S1 cancelled and refunded: S$20 back on A's lot (opened again).
      perform public.cancel_invoice_recorded(t_s1, '472 check', gen_random_uuid());
      perform public.refund_invoice_recorded(t_s1, jsonb_build_array(jsonb_build_object('amount', 20)),
        jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_s1 and p.entry_kind = 'receipt'
                                                             order by p.created_at limit 1), 'amount', 20)), '[]'::jsonb, '472 check', gen_random_uuid());
      if (select remaining_amount from public.customer_credit_lots where id = t_lot0) <> 20
         or (select status from public.customer_credit_lots where id = t_lot0) <> 'active' then
        raise exception '472: (%) the session''s refund did not go back where it was paid from before the commit point', chr(96 + t_case); end if;
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      if t_case = 3 then
        -- (c) paid (a control): the S$20 is A's to spend, nothing held back,
        -- the lot still locked with its reversal row.
        if (select remaining_amount from public.customer_credit_lots where id = t_lot0) <> 20
           or (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben) <> 0
           or exists (select 1 from public.customer_credit_ledger e where e.lot_id = t_lot0 and e.source_type in ('invoice_cancel_benefit', 'credit_given_back_reassignment_out')) then
          raise exception '472: (c) credit given back on a lot an Owner reversed while the package is paid did not stay with A'; end if;
        continue;
      end if;
      if t_case in (1, 2) then
        -- (a), (b) held back where it is, on the package's own lot (no lot
        -- made): A holds nothing, one held-back row of S$20, the row holds it
        -- back, the reversal's S$60 still taken (its row as it was).
        if (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> 0
           or (select remaining_amount from public.customer_credit_lots where id = t_lot0) <> 0
           or not (select is_locked from public.customer_credit_lots where id = t_lot0)
           or (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben) <> 20
           or (select lot_id from public.invoice_benefit_values where id = t_ben) <> t_lot0
           or (select count(*) from public.customer_credit_ledger e where e.lot_id = t_lot0 and e.entry_type = 'adjust_decrease'
                and e.source_type = 'invoice_cancel_benefit' and e.source_record_id = t_inv and e.amount = 20
                and e.reason = 'Held back by the invoice''s cancellation for whoever holds its benefits now') <> 1
           or (select amount from public.customer_credit_ledger e where e.id = t_rev) <> 60
           or exists (select 1 from public.customer_credit_ledger e where e.source_record_id = t_inv
                       and e.source_type in ('credit_given_back_reassignment_in', 'credit_given_back_reassignment_out')) then
          raise exception '472: (%) the credit given back on a lot an Owner reversed was not held back where it is (A %, held back %)', chr(96 + t_case),
            (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a),
            (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben); end if;
        if t_case = 2 then
          -- (b) owed back: the S$20 (what a refund by line pays back for it).
          if (select cancel_refund_owed from public.invoices where id = t_inv) <> 20
             or (public.invoice_financial_position(t_inv)->>'refund_due')::numeric <> 20 then
            raise exception '472: (b) the amount owed back is % (due %)', (select cancel_refund_owed from public.invoices where id = t_inv),
              public.invoice_financial_position(t_inv)->>'refund_due'; end if;
        end if;
        -- refunded by line: the S$20 paid back, nothing more held, the S$60
        -- the reversal took not paid back (net S$80).
        perform public.refund_invoice_recorded(t_inv,
          jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 20,
            'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_ben, 'amount', 20)))),
          jsonb_build_array(jsonb_build_object('payment_id', t_rcpt, 'amount', 20)), '[]'::jsonb, '472 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if public.invoice_net_received(t_inv) <> 80
           or (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben) <> 0
           or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> 0 then
          raise exception '472: (%) the refund by line did not pay the held-back credit back (net %)', chr(96 + t_case), public.invoice_net_received(t_inv); end if;
        continue;
      end if;
      -- (d), (e) the lot the records name is B's, closed at S$0: the S$20 on
      -- A's lot behind it goes to B as one new lot replacing it (the records
      -- name the new lot), paid: B's to spend; cancelled: held back there.
      select b.lot_id into t_lot from public.invoice_benefit_values b where b.id = t_ben;
      if t_lot = t_lot1
         or (select reassigned_from_lot_id from public.customer_credit_lots where id = t_lot) <> t_lot1
         or (select customer_id from public.customer_credit_lots where id = t_lot) <> t_b
         or (select remaining_amount from public.customer_credit_lots where id = t_lot) <> (case t_case when 4 then 20 else 0 end)
         or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> 0
         or (select status from public.customer_credit_lots where id = t_lot1) <> 'reversed'
         or (select amount from public.customer_credit_ledger e where e.id = t_rev) <> 80
         or (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben) <> (case t_case when 4 then 0 else 20 end) then
        raise exception '472: (%) the credit given back behind the closed lot did not go to B (B %, A %, held back %)', chr(96 + t_case),
          (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_b),
          (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a),
          (select cancelled_unused_value from public.invoice_benefit_values where id = t_ben); end if;
    end loop;
    raise exception using errcode = 'P0472', message = '472: self-test done, undone';
  exception when sqlstate 'P0472' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
