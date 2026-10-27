-- 474_reopen_dialog_counts_waiting_credit.sql
--
-- THE REOPEN DIALOG'S "REVOKED CREDIT TO REINSTATE AFTER SETTLEMENT" ALSO
-- COUNTS THE CREDIT AN EARLIER REOPENING QUEUED THAT STILL WAITS, SO IT SAYS
-- WHAT THE PAYMENT THAT SETTLES THE INVOICE GIVES BACK (471's NOT COVERED 7,
-- its suite's KNOWN K5; an older gap, 417 and 451; the Owner, 26 Oct 2026:
-- "fix the leftover gaps too")
--
-- (The number 474 is this file's name, its errors' prefix, its self-test's
-- error code P0474 and its suite's; if it changes at commit, change it in
-- these places alone: the file name, the "474:" messages, P0474, the suite,
-- and the "-- 474 (the Owner" line the suites find the preview by.)
--
-- WHO FOUND IT
--
--   471's builders (its NOT COVERED 7 and its suite's KNOWN K5, 26 Oct
--   2026), put to the Owner with 471 ("Fix it later, separately"), then (26
--   Oct 2026) "fix the leftover gaps too". Reproduced on copies of
--   production at 471 with 472 and 473 in (fd61e1a1, then 84308fd1, then
--   eb7399d1, 1387 functions, 27 Oct 2026) with K5's case and its siblings
--   (this file's suite): made-up records, the app's own calls (the invoice
--   form, the Pay dialog, Record Payment, Cancel, the Finance panel's refund
--   by line, "Record refund paid", Correct payment and Reopen, the guided
--   Cancel and Refund in full, the invoice form's customer change, a
--   customer merge), each followed by what its commit does, every figure of
--   the Reopen dialog (invoice_reopen_preview, as InvoiceFinancePanel.tsx
--   shows it) read before each reopening and compared with what the payment
--   that settles it gives. Six of them (K5, CQ, CHws, WB10, PBqs and the
--   control CTL2) were also run one app call per real transaction on copies
--   (real commits, so 462's deferred trigger at each COMMIT), with and
--   without 474: the same outcomes as the suite's, both ways. Building 474
--   found that every case where an earlier reopening's credit still waits
--   is short (not only K5's), that the voucher units and the money figures
--   are right in all of them, and two things outside the credit figure (NOT
--   COVERED 1 and 2).
--
-- WHAT WAS WRONG
--
--   A reopening queues what the cancellation took back and what refunds by
--   line took since the last reopening (reopen_invoice: every such ledger
--   row not queued yet, invoice_reopen_benefits), and the payment that
--   settles the invoice gives back every row still waiting, whichever
--   reopening queued it (apply_reopened_invoice_benefits). Where the invoice
--   is cancelled again before that payment, its rows stay waiting; credit a
--   refund gives back while it waits is held back and queued for it too
--   (470, 471, 472: credit_given_back_follows). The Reopen dialog's "Revoked
--   credit to reinstate after settlement" (invoice_reopen_preview_before_
--   sessions, credit_to_reinstate_after_settlement) counted only the rows
--   not queued yet, so the credit still waiting was left out, while its
--   "Voucher units to replace after settlement" counts the units still
--   waiting (417, 451). On copies, a S$100 package sold to A, two S$20
--   sessions paid from it (S$60 left), then:
--   * cancelled, S$60 refunded by line, reopened (it waits: S$60 to pay, the
--     S$60 Cancel took queued), S2 refunded (S$20 held back and queued),
--     cancelled again: the dialog said S$0.00; reopened and paid, A was given
--     S$80 (K5, 471's suite: RD; here K5);
--   * the same without S2's refund: S$0.00 shown, S$60 given (CQ, Cancel's
--     own row the earlier reopening queued: 417's and 451's older gap); a
--     third reopening the same (CQ3: S$0.00, S$60; CQ3s: S$0.00, S$80);
--   * a refund by line while it waited, or once cancelled again (446 takes
--     it off the queue and the next reopening counts the refund's own row):
--     S$20 or S$10 shown, S$80 given (WB, WB10, WBc, WBc10);
--   * a guided Cancel the second time ("Record refund paid" ticked, or not):
--     S$20 or S$0.00 shown, S$80 given (WG, WK); S2's wallet payment
--     corrected to S$5 less while it waited: S$0.00, S$65 (WFa); a refund in
--     full with an Owner's override after the second Cancel: S$20, S$80
--     (WX);
--   * a 'transfer' customer change to B while it waited: S$0.00 shown, B
--     given S$60, or S$80 with S2 refunded (CHw, CHws); the buyer merged
--     into K while it waited (nothing spent): S$0.00, K S$100 (MGw);
--   * one session (S1) only, refunded in full with an Owner's override
--     (refunded: S$80 paid back), reopened (it waits: S$100 to pay),
--     cancelled, reopened: S$0.00 shown, S$80 given; S1 refunded while it
--     waited: S$0.00, S$100 (RXq, RXqs); a guided Cancel first ("Record
--     refund paid": S$60), reopened, S2 refunded while it waited, cancelled,
--     reopened: S$0.00, S$80 (GCq);
--   * the S$140 Premium Bundle (S$100 paid credit, S$40 Bonus, 2 vouchers),
--     S$42 refunded by line: S$0.00 shown, S$100 given, or S$120 with S2
--     refunded while it waited (PBq, PBqs); one session, with a voucher line
--     beside it: S$0.00, S$120 (MIX); in each the voucher units shown (2; 4)
--     were the units given;
--   * paid in part (S$40 of S$100), S1 paid from it, cancelled, reopened and
--     paid in full, cancelled, S$40 refunded by line, reopened, cancelled,
--     reopened: S$0.00 shown, S$80 given; S1 refunded while it waited: S$0.00,
--     S$100 (PTF, PTF2).
--   Right before 474 and after it (controls): reopened straight to paid
--   (CTL0: S$60 shown, S$60 given), a first reopening (CTL1: S$60, S$60;
--   CTL2: S$60 shown, then S2 refunded while it waits adds S$20 to the queue
--   and S$80 is given: the dialog was right when it was shown), the voucher
--   units (VQ, VQ3: 2 shown, 2 given), the sessions of a first reopening
--   (TH0: 3, 3), and the invoice total, net payments and payment required to
--   settle again in every case. The money was right (the payment gave what
--   was waiting); what staff were told was short.
--
-- THE OWNER'S ANSWERS
--
--   22 Oct 2026: credit follows a merge and a 'transfer' customer change;
--   refunds paid back count as not used. 24 Oct 2026 (462, 463, 470): a
--   cancel or refund takes back what the invoice gave from whoever holds it
--   now; the customer holds exactly what the net payment buys; nothing
--   stranded on a lot no record names; nothing paid twice; Correct payment
--   keeps working. 26 Oct 2026 (471): credit given back while a reopening
--   waits is held for that reopening's payment (accepted); the deadlock
--   trade-off, S$1 owed back per S$1 held, RX0/RX1 owed to nobody
--   (accepted). 26 Oct 2026, after choosing "Fix it later, separately" for
--   471's NOT COVERED 7 and 10: "fix the leftover gaps too", with this rule
--   for this one: staff are told what the payment will actually give; no
--   business rule is changed beyond these by guessing.
--
-- WHAT THIS DOES (one function changed, whole text; nothing added; no table,
-- column, trigger or grant changes; nothing given, taken or queued changes)
--
--   invoice_reopen_preview_before_sessions(uuid) (451's text). Its
--   credit_to_reinstate_after_settlement is now the credit rows a reopening
--   queues (the cancellation's, 'invoice_cancel_benefit', and the refunds'
--   by line, 'invoice_benefit_refund', not queued yet: as before, the same
--   test reopen_invoice queues by) and, added to them, every row of the
--   invoice still waiting in the reopening queue (invoice_reopen_benefits
--   not applied), by its amount now (446 lowers a row a refund by line
--   took part of). So it is what the payment that settles the reopened
--   invoice gives back (apply_reopened_invoice_benefits gives every row
--   still waiting): K5 S$80, CQ S$60, WB S$80, CHw S$60 (to B), PBq S$100.
--   A row is counted once: one queue row per ledger row (its unique key),
--   and a row with a queue row is not counted as not queued.
--   Everything else is 451's text unchanged: who may open it, the blockers
--   and can_reopen, the voucher units (417 and 451 already count the units
--   still waiting), the stock to issue, the explanation, and the money
--   figures (invoice_financial_position). invoice_reopen_preview (the one
--   the page calls; it adds the sessions) is unchanged.
--   Who reads the figure (read from src and the database): the Finance
--   panel's Reopen dialog, "Revoked credit to reinstate after settlement:
--   S$80.00" (InvoiceFinancePanel.tsx: its words stay true, so no page
--   change); reopen_invoice, which records the preview in the revision's
--   snapshot ('reopen_preview') and in its Audit Log row ('invoice_reopened'):
--   those record the new figure from 474 on (what is recorded already stays
--   as it is). No other function, page or Edge Function reads it. The
--   preview of an invoice whose reopening waits for its payment (the dialog
--   is not offered for it: can_reopen false, "Only cancelled or refunded
--   invoices can be reopened") now also shows the credit that payment gives
--   (471's suite P3: S$80 where it showed S$0.00).
--
-- WHY THIS WAY
--
--   In the preview, because the money is right: the payment already gives
--   every row still waiting, and the next reopening already queues only the
--   rows not queued yet, so only the count was short. By the queue's own
--   amounts, every row still waiting whichever reopening queued it, because
--   that is what the payment gives (a row 446 lowered gives its amount now; a
--   row a refund by line closed, or 470's reissue closed and queued again on
--   the new lot, is applied and not counted, and its new row is). As 417
--   counts voucher units still waiting. The other ways:
--   * changing reopen_invoice to queue the waiting rows again under the new
--     request, or apply_reopened_invoice_benefits to give only the latest
--     request's rows: the money would change (or credit be given twice), and
--     both are pinned by 446 to 473;
--   * a second figure ("credit still waiting from an earlier reopening")
--     beside the first: the dialog would need a new line, and staff would
--     add the two; the payment gives one amount.
--
-- NOT CHANGED
--
--   * Pinned (below), unchanged: invoice_reopen_preview (e09ebf9c),
--     reopen_invoice (0ff61e4e), apply_reopened_invoice_benefits (36eaa722),
--     refund_invoice_recorded (804ecd82), cancel_invoice_recorded
--     (de52d9db), 472's forwarder credit_given_back_follows (f2a7a4d1),
--     apply_reopened_invoice_vouchers, invoice_voucher_reopen_candidates,
--     invoice_voucher_stock_unrecorded, invoice_stock_to_deduct,
--     invoice_financial_position and the rest the preview calls. Not read by
--     the preview, not pinned, unchanged: trg_create_therapy_sessions_on_paid
--     (NOT COVERED 1), 473's invoice_transferable_benefits, the triggers on
--     invoices (but the one that gives the queue back at settlement, read
--     as it is).
--   * Edge Functions, settings, pages: no change. Read from src: the Reopen
--     dialog shows the figure as "Revoked credit to reinstate after
--     settlement" and the explanation "Previously revoked credit is
--     reinstated once the reopened invoice is fully settled."; both hold for
--     the new figure (InvoiceFinancePanel.tsx). The page's other lines read
--     the voucher units, the sessions, the total, net payments, the payment
--     required to settle again (total less net), the blockers and the stock
--     to issue: unchanged.
--
-- NOT COVERED (for the Owner; the suite checks 1 to 4 as they are)
--
--   1. Therapy sessions of an invoice reopened, cancelled again before it was
--      settled, and reopened again: each reopening queues every session with
--      sessions refunded or cancelled (reopen_invoice, invoice_reopen_
--      sessions), so the session is queued twice; the payment that settles
--      it reinstates the first and refuses at the second ("Therapy session
--      reopening changed; reload its original evidence",
--      trg_create_therapy_sessions_on_paid), so the invoice cannot be
--      settled; the dialog says 3 sessions (THq: a 3-session line, cancelled,
--      S$20 refunded by line, reopened, cancelled, reopened, paid: refused).
--      Found building 474, the same before 474 and after it (an older gap;
--      417 and 451 fixed the voucher units' twin). A fix (a reopening
--      queues only what is not waiting, as 417 does for voucher units) changes
--      reopen_invoice, which 446 to 473 pin: its own migration, for the
--      Owner. The header's query lists such invoices (3, 4).
--   2. A package paid in part (credit released before full payment, 327 and
--      356) that is cancelled and reopened has its paid credit released again
--      at once by the reopening (what its money buys, less what is still
--      counted as spent), not after settlement: the dialog's "credit to
--      reinstate after settlement" does not count it, and its explanation
--      ("Previously revoked credit is reinstated once the reopened invoice is
--      fully settled") does not say so (PT0: S$40 paid, S1 paid from it,
--      cancelled: the dialog says S$0.00 and S$60 to pay; the reopening
--      gives A S$20 at once; paid, A holds S$80, the S$100 package less the
--      S$20 spent). The same
--      before 474 and after it; the money is right and the payment required
--      is shown. Whether the dialog should also show what the reopening
--      releases at once is for the Owner (a new figure and a page line).
--   3. The figure is the total the payment gives back, not to whom: after a
--      customer change or a merge while it waited it goes to whoever holds
--      the benefits (460, 462: CHw B S$60, MGw K S$100); the dialog never
--      named the holder, before 474 or after.
--   4. The dialog shows what waits when it is opened: credit a session's
--      refund holds back and queues after the reopening, while it waits,
--      raises what the payment gives, and a refund by line while it waits
--      lowers it (CTL2: S$60 shown, S$80 given), as before 474.
--   5. A Reopen dialog open on a screen when this goes in shows the old
--      figure until it is opened again; nothing depends on it (the server
--      queues and gives as before).
--   6. Not examined by 474's suite: the stock to issue of product lines (the
--      cases have none; the voucher lines' figure is checked).
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the text is the tested one (its AFTER md5); the function is its BEFORE
--     (451's AFTER, as 462 and 470 to 472 pinned it: replaced) or its AFTER
--     (left alone), anything else refused; no other function takes its
--     name; so a second run changes nothing;
--   * the functions it relies on are as read on production at 471 with 472
--     and 473 in (pinned, below): its caller (invoice_reopen_preview), what
--     queues and gives back (reopen_invoice, apply_reopened_invoice_benefits,
--     refund_invoice_recorded, cancel_invoice_recorded, 472's forwarder),
--     and what the rest of its text calls; the trigger that gives back at
--     settlement as read; the columns read have these types; one queue row
--     per ledger row; who calls the preview, who calls invoice_reopen_
--     preview and who writes the reopening queue, as read (a new way would
--     need the same care);
--   * on the first run nothing is refused for the data (474 needs no
--     decision before it goes in); the invoices of the header's query are
--     named in a notice (invoice numbers only): 1 and 2 (the figure
--     changes), 3 and 4 (for the Owner, NOT COVERED 1);
--   * who may call the function is as read, compared as sets, and kept;
--   * afterwards: the AFTER md5 and the grants as tested.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0474, so it leaves no row): a made-up Owner, store, S$100 package, S$20
--   session and three customers (fictional ACMA phones no customer has),
--   three times: the package sold to A and paid, two sessions paid from its
--   credit, cancelled; (a) S$60 refunded by line, reopened (it waits), S2
--   refunded (held back and queued at its commit), cancelled again: the
--   dialog's credit to reinstate is S$80 (S$0.00 before 474); reopened and
--   paid, A holds S$80, nothing waits; (b) the same without S2's refund:
--   S$60 shown (S$0.00 before), A S$60; (c) a control: S2 refunded while
--   cancelled: S$80 shown (as before), reopened straight to paid, A S$80.
--   Its credit ledger rows draw entry numbers (a sequence, which an undone
--   transaction does not give back: a gap, as 443 to 473's self-tests).
--   Locks: the function's catalogue row to the end of the apply, and the
--   rows the self-test writes and undoes; no table is locked against
--   ordinary writes. The self-test takes the commission advisory locks
--   (through its cancels and refunds) and new invoice numbers, so it waits
--   for any app cancel, refund, commission-writing payment or invoice
--   creation still open, and those wait for it, for under a second. If one
--   stays open longer than the 5 s lock timeout, or an invoice created at the
--   same moment takes the self-test's invoice number, the apply stops,
--   changing nothing, and can be run again. A reopening still open when 474
--   commits records the preview it read. Apply at a quiet time.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (471 in, 26 Oct 2026: fd61e1a1, 1387 functions; the grant
--   list 381ef69c; head 20261026142140) -> 472 (84308fd1) -> 473 (eb7399d1)
--   -> 474. 474 pins 472's forwarder (its AFTER); it does not read 473's
--   function, but its fingerprints are worked out with 473 in. It changes
--   the preview, which 471 and 472 pin: after 474 a re-run of 471 or 472
--   refuses (that pin), changing nothing; 473's re-run leaves all alone (it
--   does not pin the preview). If anything else goes in first, work the
--   fingerprints out again and check that it changes none of the functions
--   pinned below.
--   1. Before it, read only (invoice numbers and counts only; production was
--      not read for this file). 474 refuses no state, so this lists whose
--      figure changes (1, 2) and what needs the Owner (3, 4). On the
--      production facts known (26 Oct 2026: no reopening waits) 1 and 2 list
--      nothing; 3 and 4 were not read:
--     with
--     -- the reopening queue's rows still waiting, by invoice
--     q as (
--       select q.invoice_id, count(*) as n from public.invoice_reopen_benefits q
--        where q.applied_at is null group by q.invoice_id),
--     -- therapy sessions waiting for a reopening's payment, by invoice: all,
--     -- and those queued more than once
--     s as (
--       select s.invoice_id, count(distinct s.session_id) as n,
--              count(distinct s.session_id) filter (where s.k > 1) as twice
--         from (select s.invoice_id, s.session_id, count(*) over (partition by s.session_id) as k
--                 from public.invoice_reopen_sessions s where s.applied_at is null) s
--        group by s.invoice_id),
--     found(reason, invoice_id, n) as (
--       select '1 changes: cancelled or refunded (the Reopen dialog is offered), with credit an earlier reopening queued still waiting; from 474 the dialog''s "Revoked credit to reinstate after settlement" counts it, as the payment that settles it gives it (the count is of queue rows)', i.id, q.n
--         from public.invoices i join q on q.invoice_id = i.id
--        where i.deleted_at is null and i.status::text in ('cancelled', 'refunded')
--       union all
--       select '2 changes (not shown: the dialog is offered for a cancelled or refunded invoice alone): a reopening waiting for its payment; from 474 its preview counts the credit queued for it (the count is of queue rows)', i.id, q.n
--         from public.invoices i join q on q.invoice_id = i.id
--        where i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
--       union all
--       select '3 for the Owner (not changed by 474: NOT COVERED 1): cancelled or refunded with a therapy session''s reopening still waiting; reopened again, the session is queued again and the payment that settles it is refused (the count is of sessions)', i.id, s.n
--         from public.invoices i join s on s.invoice_id = i.id
--        where i.deleted_at is null and i.status::text in ('cancelled', 'refunded')
--       union all
--       select '4 for the Owner (not changed by 474: NOT COVERED 1): a therapy session queued by two reopenings still waiting; the payment that settles the invoice is refused ("Therapy session reopening changed; reload its original evidence") (the count is of sessions)', i.id, s.twice
--         from public.invoices i join s on s.invoice_id = i.id
--        where i.deleted_at is null and s.twice > 0)
--     select f.reason, i.invoice_no, f.n
--       from found f join public.invoices i on i.id = f.invoice_id
--      order by f.reason, i.invoice_no
--      (The suite runs this same text on its cases' states before 474 and
--      checks what it lists.)
--   2. Dry run on a copy of production as it is then (471, then 472 and 473
--      applied to it): work out its fingerprint and grant list first (they
--      must be the BEFORE figures below, or be worked out again on that
--      copy); apply this file twice; the first run ends at the AFTER
--      fingerprint below, the second changes nothing ("left alone"); and the
--      suite, with the earlier suites below.
--   3. Apply (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself.
--   4. No page change goes with it (NOT CHANGED).
--   Afterwards (checked on copies of production at 471 with 472 and 473 in,
--   27 Oct 2026): a re-run of 471 or 472 refuses (their pin of the preview),
--   changing nothing; 473's and 474's own leave all alone. The suites that
--   read the preview where 474 is in (-v nomig=1): plain-cancelled-package-
--   credit-471 (KNOWN K5 checked as 474 settles it: S$80 shown, S$80 given;
--   its P3 reads S$80 on the waiting invoice), reopen-refund-waiting-446 (13:
--   S$200 shown where it said "would add" S$40), reopen-refund-cycles-451
--   (10: the preview at 474's AFTER), by 474's AFTER md5 or its text.
--   function-grants is unchanged (nothing is added).
--
-- BEFORE (production at 471 with 472 and 473 in, 26 Oct 2026; md5 of
-- pg_get_functiondef with search_path public)
--   changed
--   invoice_reopen_preview_before_sessions(uuid)                       12206ed066495024421b3b44a6a9d8e2  (451's)
--   relied on, not changed (pinned)
--   invoice_reopen_preview(uuid)                                       e09ebf9c0841ef5463f96b26f4933541
--   reopen_invoice(uuid,text,uuid)                                     0ff61e4ead121c198ea7f90a7fc78274
--   apply_reopened_invoice_benefits()                                  36eaa7224e514d3e7e42e3eeb51acfb5
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)          804ecd829cfecf713783a09a05d93c7e
--   cancel_invoice_recorded(uuid,text,uuid)                            de52d9dbaef8ab15163bef35cb9d733d
--   credit_given_back_follows(uuid)                                    f2a7a4d1ca28f0865b14e3f1e5e02bbb  (472's AFTER)
--   apply_reopened_invoice_vouchers()                                  6684840544d1ad8a28e2415934300054
--   invoice_voucher_reopen_candidates(uuid)                            20405a96c8780eac6425a5dae59c29e1
--   invoice_voucher_stock_unrecorded(uuid,boolean)                     91c8f0fa69ef6337f323b7ac467a8c2b
--   invoice_stock_to_deduct(uuid)                                      6356494ccb8545d46c56b788f8f85f54
--   invoice_financial_position(uuid)                                   ba7eccbfeff217c8b1969b0e55a010ca
--   is_owner_or_manager()                                              a98e50f1b6d3fa1e6c62cf52a8073cc8
--   user_has_store_access(uuid)                                        708992afaa6c3951f6329239b742987c
--   rental_is_outstanding(text)                                        076549a44bc057cd529aac5542c4d06e
--   public function fingerprint, production now (471)                  fd61e1a11dce76dd9ad4348f6bb99180 (1387 functions; head 20261026142140)
--   public function fingerprint, 471 -> 472 (472's AFTER, on a copy)   84308fd1c3570babf682c472bd6f95b2 (1387 functions)
--   public function fingerprint, 472 -> 473 (473's AFTER, on a copy)   eb7399d17225fcc55142a773e35b12b6 (1387 functions)
--   grant list (string_agg(signature '=' proacl, '|'), sorted)          381ef69cb44f960ff981585ff8402fa1 (production lists the same
--                                                                      grants in another order: compare as sets)
-- AFTER (for later guards)
--   invoice_reopen_preview_before_sessions(uuid)                       7e1ef2d25415e69b3f770fe2efd45190  (grants kept: postgres, the service role)
--   public function fingerprint, worked out on a copy of production at 471 with 472 and 473 applied (27 Oct 2026; a second run the same):
--     production now (471) -> 472 -> 473 -> 474                        c19401919a0a8b67746e18b8f7a78639 (1387 functions: none added, none dropped)
--   grant list after 474                                               381ef69cb44f960ff981585ff8402fa1 (unchanged)
--
-- Test: scripts/invoices/tests/reopen-dialog-waiting-credit-474.sql
-- (begin ... rollback; it installs this file twice; -v nomig=1 where it is
-- in). It reproduces K5 and its siblings first (credit an earlier reopening
-- queued still waiting: Cancel's own rows, credit held back while it waited,
-- refunds by line while it waited or once cancelled again, a guided Cancel,
-- Correct payment, a refund in full, a customer change and a merge while it
-- waited, a refunded invoice, the Premium Bundle and a voucher line, a
-- package paid in part and paid in full since, a third reopening), with
-- every figure of the Reopen dialog read before each reopening and compared
-- with what the reopening queues and the payment that settles it gives;
-- then checks the header's query (1 to 4), the refusals, the install, every
-- case after 474 (the dialog's credit is what the payment gives; everything
-- else, the money and who holds what, exactly as before 474), the preview's
-- other figures unchanged, the revision snapshot and Audit Log row a
-- reopening records, cases begun before 474 and read after, and NOT COVERED
-- 1 and 2 as KNOWN. Each app call is followed by what its commit does (462's
-- trigger is deferred). Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The function this changes: BEFORE (production, 26 Oct 2026: 451's
  -- AFTER, as 462 and 470 to 472 pinned it) and AFTER md5s; who may call it,
  -- as read (kept) ═══════════════════════════════════════════════════════
  c_sig constant text := 'invoice_reopen_preview_before_sessions(uuid)';
  c_before constant text := '12206ed066495024421b3b44a6a9d8e2';
  c_after constant text := '7e1ef2d25415e69b3f770fe2efd45190';
  c_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';

  -- ══ The whole text (exactly as the database prints it back) ═════════════
  c_def constant text := $d1$CREATE OR REPLACE FUNCTION public.invoice_reopen_preview_before_sessions(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare i public.invoices%rowtype; blockers text[]:='{}'; credits numeric;
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can reopen invoices'; end if;
 select * into i from public.invoices where id=p_invoice_id;
 if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 if i.status not in ('cancelled','refunded') then blockers:=array_append(blockers,'Only cancelled or refunded invoices can be reopened'); end if;
 if i.status='refunded' and not exists(select 1 from public.invoice_refunds where invoice_id=i.id) then
  blockers:=array_append(blockers,'Historical refunded status has no payment-source refund evidence'); end if;
 if exists(select 1 from public.invoice_refunds where invoice_id=i.id and payment_id is null) then blockers:=array_append(blockers,'Resolve historical refund payment sources first'); end if;
 if i.stock_snapshot_version is null and exists(select 1 from public.invoice_items where invoice_id=i.id and line_kind in ('promotion','premium_bundle','voucher')) then
  blockers:=array_append(blockers,'Historical component/stock snapshots require review before reopening'); end if;
 if exists(select 1 from public.rentals where invoice_id=i.id and public.rental_is_outstanding(status::text)) then
  blockers:=array_append(blockers,'Resolve the outstanding rental in Rentals before reopening'); end if;
 select coalesce(sum(l.amount),0) into credits from public.customer_credit_ledger l
 where (l.source_type='invoice_cancel_benefit' and l.source_record_id=i.id
   or l.source_type='invoice_benefit_refund' and exists(select 1 from public.invoice_refunds r where r.invoice_id=i.id and r.request_id=l.source_record_id))
   and not exists(select 1 from public.invoice_reopen_benefits b where b.source_ledger_id=l.id);
 -- 474 (the Owner, 26 Oct 2026: "fix the leftover gaps too"; 471's NOT
 -- COVERED 7): with the credit an earlier reopening queued that still waits
 -- (invoice_reopen_benefits, not applied: the reopening was cancelled again
 -- before it was settled), as 417 counts such voucher units. The payment
 -- that settles the invoice gives every row still waiting, whichever
 -- reopening queued it (apply_reopened_invoice_benefits), and reopen_invoice
 -- queues only the rows not queued yet, so this is what that payment gives:
 -- the cancellation's rows the earlier reopening queued, credit held back
 -- and queued while it waited (credit_given_back_follows), less what a
 -- refund by line took off the queue since (446). Before, the dialog left
 -- them out (cancelled, S$60 refunded by line, reopened, a session refunded
 -- while it waited, cancelled again: S$0.00 shown, S$80 given).
 credits:=credits+coalesce((select sum(q.amount) from public.invoice_reopen_benefits q
   where q.invoice_id=i.id and q.applied_at is null),0);
 return public.invoice_financial_position(i.id)||jsonb_build_object('can_reopen',cardinality(blockers)=0,'blockers',to_jsonb(blockers),
   'credit_to_reinstate_after_settlement',credits,'voucher_units_to_reinstate_after_settlement',
   -- 417: with the units an earlier reopening queued that are still waiting
   -- (reopen_invoice gives those, or more if there are more to give).
   -- 451: and what reopen_invoice queues beside them, by its rule: the
   -- candidates less the cancellation's part of what waits (up to
   -- cancelled_unused_value).
   (select coalesce(sum(w.quantity+greatest(c.quantity-least(w.quantity,b.cancelled_unused_value::int),0)),0)
      from public.invoice_voucher_reopen_candidates(i.id) c
      join public.invoice_benefit_values b on b.id=c.benefit_id
      cross join lateral (select coalesce(sum(q.quantity),0)::int as quantity from public.invoice_reopen_vouchers q
                           where q.invoice_id=i.id and q.benefit_id=c.benefit_id and q.applied_at is null) w),'stock_to_issue',(select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('item_name',case when s.kind='product' then (select name from public.products where id=s.item_id) else (select name from public.vouchers where id=s.item_id) end)),'[]') from (select t.kind,t.item_id,(t.quantity-case when t.kind='product' then 0 else coalesce((select sum(u.quantity)
          -- 417: less the units reopen_invoice records as taken already, moving no
          -- stock (a completed FOC invoice's vouchers, or those kept to give again).
          from public.invoice_voucher_stock_unrecorded(i.id,true) u where u.voucher_id=t.item_id),0) end)::int as quantity
         from public.invoice_stock_to_deduct(i.id) t) s where s.quantity>0),
   'explanation','Existing refunds remain recorded. Only net unrefunded payments settle the reopened invoice. Previously revoked credit is reinstated once the reopened invoice is fully settled.');
end $function$
$d1$;

  -- ══ Relied on, not changed (production at 471 with 472 and 473 in, 26 Oct
  -- 2026): its caller; what queues credit for a reopening and gives it back
  -- at settlement (the figure is what they queue and give); what the rest of
  -- its text calls ══════════════════════════════════════════════════════
  c_relied constant text[] := array[
    'invoice_reopen_preview(uuid)',
    'reopen_invoice(uuid,text,uuid)',
    'apply_reopened_invoice_benefits()',
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'credit_given_back_follows(uuid)',
    'apply_reopened_invoice_vouchers()',
    'invoice_voucher_reopen_candidates(uuid)',
    'invoice_voucher_stock_unrecorded(uuid,boolean)',
    'invoice_stock_to_deduct(uuid)',
    'invoice_financial_position(uuid)',
    'is_owner_or_manager()',
    'user_has_store_access(uuid)',
    'rental_is_outstanding(text)'];
  c_relied_md5 constant text[] := array[
    'e09ebf9c0841ef5463f96b26f4933541',
    '0ff61e4ead121c198ea7f90a7fc78274',
    '36eaa7224e514d3e7e42e3eeb51acfb5',
    '804ecd829cfecf713783a09a05d93c7e',
    'de52d9dbaef8ab15163bef35cb9d733d',
    'f2a7a4d1ca28f0865b14e3f1e5e02bbb',
    '6684840544d1ad8a28e2415934300054',
    '20405a96c8780eac6425a5dae59c29e1',
    '91c8f0fa69ef6337f323b7ac467a8c2b',
    '6356494ccb8545d46c56b788f8f85f54',
    'ba7eccbfeff217c8b1969b0e55a010ca',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    '708992afaa6c3951f6329239b742987c',
    '076549a44bc057cd529aac5542c4d06e'];
  -- The trigger that gives the queue back at settlement, as read.
  c_trigger constant text := 'CREATE TRIGGER invoice_reopen_benefits_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_benefits()';
  -- Who calls the preview, who calls invoice_reopen_preview, and who writes
  -- the reopening queue (by name; a session's own temporary functions and the
  -- preview itself are not counted), as read on production at 471 with 472
  -- and 473 in.
  c_callers constant text := 'invoice_reopen_preview(uuid)';
  c_pv_callers constant text := 'reopen_invoice(uuid,text,uuid)';
  c_writers constant text := 'apply_reopened_invoice_benefits(), credit_given_back_follows(uuid), refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid), reopen_invoice(uuid,text,uuid)';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; i int; v_first boolean; v_acl text;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_pk uuid; t_svc uuid; t_wallet uuid;
  t_case int; t_a uuid; t_inv uuid; t_s2 uuid; t_k int; t_s uuid; t_ben uuid; t_pay uuid; t_due numeric; t_shown numeric;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The text is the tested one.
  if md5(c_def) <> c_after then
    raise exception '474: the text in this file is not the tested one'; end if;

  -- The functions relied on are as read on production (at 471 with 472 and
  -- 473 in, 26 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '474: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying (474 goes in after 472).',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if (select string_agg(pg_get_triggerdef(t.oid), E'\n' order by t.tgname) from pg_trigger t
       where t.tgrelid = 'public.invoices'::regclass and t.tgfoid = 'public.apply_reopened_invoice_benefits()'::regprocedure)
     is distinct from c_trigger then
    raise exception '474: the trigger that gives a reopening''s credit back at settlement is not as read on 26 Oct 2026'; end if;

  -- The columns read, with these types; one queue row per ledger row.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('invoice_reopen_benefits', 'invoice_id', 'uuid'), ('invoice_reopen_benefits', 'source_ledger_id', 'uuid'),
                 ('invoice_reopen_benefits', 'amount', 'numeric(12,2)'), ('invoice_reopen_benefits', 'applied_at', 'timestamp with time zone'),
                 ('customer_credit_ledger', 'id', 'uuid'), ('customer_credit_ledger', 'amount', 'numeric(12,2)'),
                 ('customer_credit_ledger', 'source_type', 'text'), ('customer_credit_ledger', 'source_record_id', 'uuid'),
                 ('invoice_refunds', 'invoice_id', 'uuid'), ('invoice_refunds', 'request_id', 'uuid')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '474: these columns are missing or not as read on 26 Oct 2026: %', v; end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.invoice_reopen_benefits'::regclass and contype = 'u'
                  and pg_get_constraintdef(oid) = 'UNIQUE (source_ledger_id)') then
    raise exception '474: the reopening queue no longer holds one row per ledger row (its unique key is not as read on 26 Oct 2026)'; end if;

  -- No other function takes the name (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'invoice_reopen_preview_before_sessions'
     and p.oid::regprocedure::text <> c_sig;
  if v is not null then raise exception '474: another function takes the name of the one this changes: %', v; end if;

  -- Who calls the preview and invoice_reopen_preview; who writes the
  -- reopening queue: as read (a new way would need the same care).
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'invoice_reopen_preview_before_sessions\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'invoice_reopen_preview_before_sessions';
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'invoice_reopen_preview\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and p.proname <> 'invoice_reopen_preview';
  if v is distinct from c_callers or d is distinct from c_pv_callers then
    raise exception '474: the functions that call the Reopen dialog''s preview are not as read on 26 Oct 2026 (% / %); check how each reads its credit figure, then re-test', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+public\.invoice_reopen_benefits' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_writers then
    raise exception '474: what writes the reopening queue (invoice_reopen_benefits) is not as read on 26 Oct 2026 (%); check what the payment that settles a reopened invoice gives back, then re-test', v; end if;

  -- The function: its BEFORE (replaced) or its AFTER (left alone).
  d := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  if md5(d) = c_after then
    raise notice '474: public.% is already this version; left alone', c_sig;
    v_first := false;
  elsif md5(d) = c_before then
    v_first := true;
  else
    raise exception '474: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig, md5(d);
  end if;

  -- ── On the first run: nothing is refused for the data (474 needs no
  -- decision before it goes in), but whose figure changes and what needs the
  -- Owner is named (the header's read-only query: 1 and 2, the credit to
  -- reinstate now counts what still waits; 3 and 4, for the Owner).
  if v_first then
    with
    q as (
      select q.invoice_id from public.invoice_reopen_benefits q where q.applied_at is null group by q.invoice_id),
    s as (
      select s.invoice_id, count(distinct s.session_id) filter (where s.k > 1) as twice
        from (select s.invoice_id, s.session_id, count(*) over (partition by s.session_id) as k
                from public.invoice_reopen_sessions s where s.applied_at is null) s
       group by s.invoice_id),
    found(reason, invoice_id) as (
      select 1, i.id from public.invoices i join q on q.invoice_id = i.id
       where i.deleted_at is null and i.status::text in ('cancelled', 'refunded')
      union
      select 2, i.id from public.invoices i join q on q.invoice_id = i.id
       where i.deleted_at is null and i.status::text not in ('cancelled', 'refunded')
      union
      select 3, i.id from public.invoices i join s on s.invoice_id = i.id
       where i.deleted_at is null and i.status::text in ('cancelled', 'refunded')
      union
      select 4, i.id from public.invoices i join s on s.invoice_id = i.id
       where i.deleted_at is null and s.twice > 0)
    select string_agg(format('%s: %s invoice(s) (%s)', f.reason, f.n, f.nos), '; ' order by f.reason) into v
      from (select f.reason, count(*) as n, string_agg(i.invoice_no, ', ' order by i.invoice_no) as nos
              from found f join public.invoices i on i.id = f.invoice_id group by f.reason) f;
    if v is not null then
      raise notice '474: the header''s query lists %: 1 and 2, the Reopen dialog''s credit to reinstate now counts the credit still waiting for a reopening''s payment; 3 and 4 are for the Owner (NOT COVERED 1), not changed by 474', v;
    end if;
  end if;

  -- Who may call it, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig))
     is distinct from (select array_agg(x::text order by x::text) from unnest(c_acl::aclitem[]) x) then
    raise exception '474: who may call public.% is not as read on 26 Oct 2026 (%)', c_sig,
      (select proacl::text from pg_proc where oid = to_regprocedure('public.' || c_sig)); end if;
  v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig));

  -- ── Change ──────────────────────────────────────────────────────────────
  if v_first then
    execute c_def;
  end if;

  -- ── Afterwards: installed exactly as tested, grants as before ───────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_after then
    raise exception '474: public.% is not at its AFTER md5 (%)', c_sig, md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))); end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig)) is distinct from v_acl then
    raise exception '474: the grants of public.% changed', c_sig; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("474 check", @example.com, fictional ACMA
  -- phones no customer uses); it ends by raising P0474, which undoes all it
  -- wrote. 462's trigger runs at commit; here at each step's end (SET
  -- CONSTRAINTS ... IMMEDIATE), as a commit would.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from generate_series(700, 799) g, lateral (select '+61491570' || g::text as p) x
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p desc limit 3);
    if coalesce(cardinality(t_phones), 0) < 3 then raise exception '474: the self-test found no three unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '474-check-' || t_sfx || '@example.com') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '474 check', '474-check-' || t_sfx || '@example.com', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('474 check ' || t_sfx, '474-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('474 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy, grants_reward)
    values ('474 check ' || t_sfx, 100, 100, false, true, true, false) returning id into t_pk;
    insert into public.credit_package_stores (package_id, store_id) values (t_pk, t_store);
    insert into public.therapy_services (service_code, name, standard_price, duration_minutes, is_active)
    values ('474-' || t_sfx, '474 check ' || t_sfx, 20, 30, true) returning id into t_svc;
    insert into public.therapy_service_stores (service_id, store_id, is_available) values (t_svc, t_store, true);
    select pm.id into t_wallet from public.payment_methods pm
     where pm.name = 'Wallet — Credit Package Paid' and pm.is_wallet_credit and pm.deleted_at is null;
    if t_wallet is null then raise exception '474: the wallet method "Wallet — Credit Package Paid" (443) is not there'; end if;

    for t_case in 1 .. 3 loop
      -- The package sold to A and paid in full; two S$20 sessions paid from
      -- its credit; cancelled (Cancel takes the S$60 left back).
      insert into public.customers (full_name, phone) values ('474 Check Buyer ' || t_case || ' ' || t_sfx, t_phones[t_case]) returning id into t_a;
      t_inv := public.create_invoice(t_store, t_a, null::uuid,
        jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
      perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
      for t_k in 1 .. 2 loop
        t_s := public.create_invoice(t_store, t_a, null::uuid,
          jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 1)),
          0::numeric, null::text, null::uuid, '[]'::jsonb);
        perform public.record_invoice_payment(t_s, jsonb_build_array(jsonb_build_object('payment_method_id', t_wallet, 'amount', 20)), gen_random_uuid());
      end loop;
      t_s2 := t_s;
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      perform public.cancel_invoice_recorded(t_inv, '474 check', gen_random_uuid());
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      if t_case in (1, 2) then
        -- (a), (b) S$60 refunded by line (the Finance panel), reopened: it
        -- waits for S$60, the S$60 Cancel took queued for that payment.
        select b.id into t_ben from public.invoice_benefit_values b where b.invoice_id = t_inv and b.lot_id is not null;
        select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt';
        perform public.refund_invoice_recorded(t_inv,
          jsonb_build_array(jsonb_build_object('invoice_item_id', (select it.id from public.invoice_items it where it.invoice_id = t_inv),
            'amount', 60, 'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_ben, 'amount', 60)))),
          jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 60)), '[]'::jsonb, '474 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        perform public.reopen_invoice(t_inv, '474 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
      end if;
      if t_case in (1, 3) then
        -- (a) while the reopening waits, (c) while cancelled: S2 cancelled and
        -- "Record refund paid"; its S$20 goes back and, at its commit, is held
        -- back (and, in (a), queued for the waiting reopening's payment).
        perform public.cancel_invoice_recorded(t_s2, '474 check', gen_random_uuid());
        t_due := (public.invoice_financial_position(t_s2)->>'refund_due')::numeric;
        select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_s2 and p.entry_kind = 'receipt';
        perform public.refund_invoice_recorded(t_s2, jsonb_build_array(jsonb_build_object('amount', t_due)),
          jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', t_due)), '[]'::jsonb, '474 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
      end if;
      if t_case in (1, 2) then
        -- (a), (b) cancelled again before the reopening was settled.
        perform public.cancel_invoice_recorded(t_inv, '474 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
      end if;
      -- The Reopen dialog's "Revoked credit to reinstate after settlement".
      t_shown := (public.invoice_reopen_preview(t_inv)->>'credit_to_reinstate_after_settlement')::numeric;
      if t_shown is distinct from (case t_case when 2 then 60 else 80 end)::numeric then
        raise exception '474: (%) the Reopen dialog''s credit to reinstate is % (wanted %)', chr(96 + t_case), t_shown,
          case t_case when 2 then 60 else 80 end; end if;
      -- Reopened, and what is outstanding paid (Record Payment): A is given
      -- what the dialog said, and nothing waits.
      perform public.reopen_invoice(t_inv, '474 check', gen_random_uuid());
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      if (public.invoice_financial_position(t_inv)->>'outstanding')::numeric > 0 then
        perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
          'amount', (public.invoice_financial_position(t_inv)->>'outstanding')::numeric)), gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
      end if;
      if (select status::text from public.invoices where id = t_inv) <> 'paid'
         or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> t_shown
         or exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = t_inv and q.applied_at is null) then
        raise exception '474: (%) the payment did not give A what the dialog said (status %, A holds %, the dialog said %)', chr(96 + t_case),
          (select status::text from public.invoices where id = t_inv),
          (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a), t_shown; end if;
    end loop;
    raise exception using errcode = 'P0474', message = '474: self-test done, undone';
  exception when sqlstate 'P0474' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
