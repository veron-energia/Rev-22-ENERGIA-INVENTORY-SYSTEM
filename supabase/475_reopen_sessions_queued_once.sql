-- 475_reopen_sessions_queued_once.sql
--
-- A THERAPY SESSION AN EARLIER REOPENING QUEUED, STILL WAITING BECAUSE THE
-- INVOICE WAS CANCELLED AGAIN BEFORE IT WAS SETTLED, IS NOT QUEUED AGAIN BY
-- THE NEXT REOPENING, SO THE PAYMENT THAT SETTLES THE INVOICE REINSTATES IT
-- ONCE INSTEAD OF BEING REFUSED (474's NOT COVERED 1; the Owner, 27 Oct 2026:
-- "Yes, fix it next")
--
-- (The number 475 is this file's name, its errors' prefix, its self-test's
-- error code P0475 and its suite's; if it changes at commit, change it in
-- these places alone: the file name, the "475:" messages, P0475, the suite,
-- and the "-- 475 (the Owner" line the suites find reopen_invoice's version
-- by.)
--
-- WHO FOUND IT
--
--   474's builders (its NOT COVERED 1 and its suite's KNOWN K1, THq, 27 Oct
--   2026), put to the Owner with 472 to 474's questions. Reproduced for this
--   file on copies of production at 474 (c1940191, 1387 functions, 27 Oct
--   2026) with THq and its siblings (this file's suite): made-up records,
--   the app's own calls (the invoice form and the Pay dialog, Record
--   Payment, Correct payment, Cancel, Reopen, the Finance panel's refund by
--   line of a therapy line by money and "Record refund paid", the guided
--   Cancel and Refund in full, the invoice form's customer change, a
--   customer merge), each followed by what its commit does, the Reopen
--   dialog read before each reopening (invoice_reopen_preview, as
--   InvoiceFinancePanel.tsx shows it) and compared with what the reopening
--   queued and what the payment that settles it reinstated.
--
-- WHAT WAS WRONG
--
--   A reopening queues, for each current therapy session of the invoice, all
--   it shows as refunded and cancelled (reopen_invoice: one
--   invoice_reopen_sessions row of quantity_refunded+quantity_cancelled),
--   and the payment that settles the invoice reinstates each waiting row
--   after checking that its quantity is what the session shows now
--   (trg_create_therapy_sessions_on_paid: "Therapy session reopening
--   changed; reload its original evidence" otherwise), then sets the
--   session's refunded and cancelled to 0. Where the invoice was cancelled
--   again before that payment, the first reopening's row stays waiting and
--   the session is unchanged (a cancellation finds none of it unused), so
--   the next reopening queued it again: two rows of the same quantity. The
--   payment reinstated the session at the first row and was refused at the
--   second (the session now shows 0), so the invoice could never be settled,
--   and with it neither its credit nor its voucher units waiting for that
--   payment were given. On copies, a 3-session line at S$20, paid S$60:
--   * cancelled, S$20 refunded by line, reopened (S$20 to pay, the session
--     queued: 3), cancelled again, reopened (queued again: 6), paid: refused
--     (THq, 474's K1); a third reopening the same (THq3: 9); S$40 or the
--     whole S$60 refunded by line first (TH2c, THall);
--   * refunded in full first (the guided Refund in full: the sessions
--     refunded, not cancelled), reopened, cancelled, reopened, paid: refused
--     (THr);
--   * cancelled again and "Record refund paid" (no line) of what it owes
--     back, or the guided Cancel with "Record refund paid" not ticked, the
--     second time: refused (THrp, THgk);
--   * the buyer merged into K while it waited, or once cancelled again
--     (the session follows to K): refused (THmg, THmgc);
--   * beside a S$100 Credit Package (its credit refunded by line, the
--     sessions only cancelled), the S$140 Premium Bundle (2 vouchers), a
--     package with a session paid from it and a voucher line, or a voucher
--     line with one unit refunded: refused, and the S$100, S$140 + 2
--     vouchers, S$80 + 2 vouchers, 2 vouchers waiting for that payment were
--     never given (THcpw, THpb, THmix, THvs);
--   * the same cycle run twice (cancelled, S$20 refunded by line, reopened,
--     cancelled, reopened, paid; then all of it again): refused at its
--     first payment already (THq2p; from 475 both payments settle it, each
--     reinstating the 3 sessions once);
--   * settled by the Pay dialog, or by Correct payment (a S$5 payment
--     corrected to S$20), instead of Record Payment: refused the same way
--     (THpd, THfix; the same trigger).
--   The Reopen dialog said "Unused therapy sessions to reinstate after
--   settlement: 3" each time; the reopening queued 6 (or 9).
--   Right both before 475 and after it (controls): a first reopening paid
--   (TH0, THcp0), reopened straight to paid (THc), twice (THcc), refunded in
--   full or the guided Cancel then reopened and paid (THr1, THgc1), and
--   474's credit and voucher controls (K5, VQ).
--   Production, 27 Oct 2026 (read-only, as given to this builder): no
--   reopening waits and no invoice has therapy sessions queued twice; so it
--   has not happened there; nothing to repair.
--
-- THE OWNER'S ANSWERS
--
--   9 Oct 2026 (417): voucher units an earlier reopening queued, still
--   waiting, are given with the next one; only what is more is queued, so
--   each is given once. 22 Oct 2026 (451): after any sequence of line
--   refunds, cancels, reopenings and settlements the customer holds exactly
--   what the net payment buys. 27 Oct 2026, answering 474's NOT COVERED 1:
--   "Yes, fix it next": a reopening queues only what is not already waiting,
--   as 417 does for voucher units; the payment then reinstates each session
--   once; the dialog's session count is right. No other business rule is
--   changed by guessing.
--
-- WHAT THIS DOES (one function changed, whole text; nothing added; no table,
-- column, trigger or grant changes)
--
--   reopen_invoice(uuid,text,uuid) (458's text, as 462, 463 and 470 to 474
--   pinned it). Its sessions step now queues, for each current session of
--   the invoice, what it shows as refunded and cancelled LESS what still
--   waits for it from an earlier reopening of the same invoice (its
--   invoice_reopen_sessions rows not applied), where that is more than 0, as
--   417 queues voucher units. While a session waits nothing changes what it
--   shows (refund_invoice_therapy_sessions and
--   correct_invoice_therapy_sessions refuse to touch it, and a cancellation
--   finds none of it unused: the cancellation before the reopening took
--   it), so on every path the pages offer the next reopening queues nothing
--   for it: one row waits, of what the session shows, and the payment that
--   settles the invoice reinstates it once and records one 'reopen' event,
--   whichever way it is paid (Record Payment, the Pay dialog, Correct
--   payment: THpd, THfix; an instalment payment is Record Payment,
--   record_invoice_payment_with_instalment calls it). THq: 3 queued once;
--   paid S$20, the 3 sessions available again; THcpw, THpb, THmix, THvs:
--   the credit and vouchers waiting for that payment given with it (S$100;
--   S$140 + 2; S$80 + 2; 2), as 474's dialog said.
--   Everything else is 458's text unchanged: the blockers (through the
--   preview), the revision and its snapshot of the preview, the credit queue
--   (by ledger row, unchanged), the voucher queue (417 and 451), the stock,
--   the status, the special items and rentals, the commissions, the Audit
--   Log row.
--   The Reopen dialog (invoice_reopen_preview: "Unused therapy sessions to
--   reinstate after settlement", the sum over current sessions of what they
--   show as refunded and cancelled) is unchanged: with one row waiting per
--   session, of that quantity, it is what the payment now reinstates (THq: 3
--   shown, 3 reinstated; before 475: 3 shown, 6 queued, refused).
--
-- WHY THIS WAY
--
--   In the reopening, as 417 for voucher units: the payment already
--   reinstates what waits, and its check (what waits for a session is what
--   the session shows) is the evidence guard 252 put there; the fault was
--   only that the second reopening queued what already waited. By the
--   difference (what the session shows less what waits), not by "skip a
--   session with a row waiting": in every state the pages can reach the two
--   are the same (the difference is 0); the difference is 417's "only what
--   is more". The other ways:
--   * changing trg_create_therapy_sessions_on_paid to sum a session's
--     waiting rows (or to skip rows once the session shows 0): it loosens the
--     evidence check the Owner did not ask to change, and an invoice queued
--     twice before 475 would then settle with no decision (NOT COVERED 3);
--   * the reopening refusing while a session waits: the Owner asked for the
--     reopening to go through and be settled.
--
-- NOT CHANGED
--
--   * Pinned (below), unchanged: the Reopen dialog's preview
--     (invoice_reopen_preview e09ebf9c, invoice_reopen_preview_before_
--     sessions 7e1ef2d2: 474's AFTER), what reinstates and what refuses to
--     touch a waiting session (trg_create_therapy_sessions_on_paid,
--     refund_invoice_therapy_sessions, correct_invoice_therapy_sessions),
--     create_therapy_sessions_for_invoice, refund_invoice_recorded,
--     cancel_invoice_recorded, the credit and voucher queues' givers
--     (apply_reopened_invoice_benefits, apply_reopened_invoice_vouchers) and
--     472's forwarder, and the rest reopen_invoice's text calls.
--   * Edge Functions, settings, pages: no change. Read from src: the Reopen
--     dialog shows "Unused therapy sessions to reinstate after settlement"
--     (InvoiceFinancePanel.tsx) from the preview, unchanged and now right.
--
-- NOT COVERED (for the Owner; the suite checks 1 to 4 as they are and prints
-- them as KNOWN)
--
--   1. While a session's reopening waits (the invoice reopened and not yet
--      paid), and once that invoice is cancelled again before it is paid, a
--      refund by line of its therapy line is refused ("Settle the reopened
--      invoice before changing its queued sessions", 252), and so are the
--      guided Cancel with "Record refund paid" ticked and the guided Refund
--      in full while it waits (their plans refund the sessions by line)
--      (THw, THb, THgc, THrf). The plain Cancel, the guided Cancel with
--      "Record refund paid" not ticked, and "Record refund paid" with no line
--      work. The same before 475 and after it (252's rule, not this fault).
--      Whether such a refund should go through, taking the sessions off the
--      queue as 446 does for voucher units, is for the Owner.
--   2. A customer change ('transfer' or 'keep') of an invoice whose session
--      waits, or once it is cancelled again, is refused ("Settle the pending
--      session reopening before changing its allocation", 252) (THchw, THchc,
--      THchk). The same before 475 and after it. Whether it should go
--      through (the sessions following to the new customer) is for the
--      Owner.
--   3. An invoice whose session was queued twice before 475 goes in (the
--      header's query, 2) stays one whose settling payment is refused: 475
--      queues nothing more for it (what waits is already more than the
--      session shows) and repairs no row already there (no data repair in
--      this file). Production, 27 Oct 2026: none. If one is there when 475
--      goes in, it needs an Owner's go-ahead for a one-off repair (taking
--      the later reopenings' duplicate rows off the queue, as applied with
--      nothing reinstated) before it can be settled.
--   4. If what a session shows as refunded and cancelled ever grew while its
--      row waited (no function does that today: each writer refuses or finds
--      nothing unused), 475 queues the difference and the payment's evidence
--      check refuses it ("reload its original evidence"), as before 475 (the
--      header's query, 3; the suite makes such a state by hand and checks
--      it).
--   5. Therapy bought through therapy packages and promotions
--      (purchased_therapy_entitlements, 359) is not queued by a reopening at
--      all (another record); not examined.
--   6. A reopening still open when 475 commits finishes on the text it
--      started with (it may queue a session a second time only if it is the
--      next reopening of an invoice cancelled again while a session waits,
--      at that same moment: then NOT COVERED 3).
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the text is the tested one (its AFTER md5); the function is its BEFORE
--     (458's AFTER, as 462, 463 and 470 to 474 pinned it: replaced) or its
--     AFTER (left alone), anything else refused; no other function takes its
--     name; nothing calls it (the Finance panel's Reopen calls it); so a
--     second run changes nothing;
--   * the functions it relies on are as read on production at 474 (pinned,
--     below); the trigger that reinstates sessions at settlement as read;
--     the columns read have these types; the queue holds one row per
--     session and reopening, of a quantity above 0; what reads or writes the
--     session queue and what updates the sessions, as read (a new way would
--     need the same care);
--   * on the first run nothing is refused for the data (475 needs no
--     decision before it goes in); the invoices of the header's query are
--     named in a notice (invoice numbers only): 1 (the next reopening now
--     queues the session once), 2 and 3 (for the Owner, NOT COVERED 3, 4);
--   * who may call the function is as read (signed-in staff and the service
--     role), compared as sets, and kept;
--   * afterwards: the AFTER md5 and the grants as tested.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0475, so it leaves no row): a made-up Owner, store, cash method, S$20
--   session and three customers (fictional ACMA phones no customer has),
--   three times: a 3-session line sold to A and paid S$60, cancelled; (a)
--   S$20 refunded by line, reopened (S$20 to pay), cancelled again,
--   reopened: one row waits for the session, of 3 (6 before 475); the
--   dialog says 3; paid: the invoice is paid, the 3 sessions available, one
--   'reopen' event, nothing waits; (b) the same with a third reopening; (c)
--   a control: reopened straight to paid (the money held), cancelled,
--   reopened straight to paid again: 3 available, two 'reopen' events.
--   Locks: the function's catalogue row to the end of the apply, and the
--   rows the self-test writes and undoes; no table is locked against
--   ordinary writes. The self-test takes the commission advisory locks
--   (through its cancels and refunds) and new invoice numbers, so it waits
--   for any app cancel, refund, commission-writing payment or invoice
--   creation still open, and those wait for it, for under a second. If one
--   stays open longer than the 5 s lock timeout, or an invoice created at the
--   same moment takes the self-test's invoice number, the apply stops,
--   changing nothing, and can be run again. Apply at a quiet time.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (474 in, 27 Oct 2026: c1940191, 1387 functions; the grant
--   list 381ef69c; head 20261027012311) -> 475. 476 to 478 (built after this
--   file in the same batch) pin what they find, 475's AFTER among it; if
--   anything else goes in first, work the fingerprints out again and check
--   that it changes none of the functions pinned below.
--   It changes reopen_invoice, which 462, 463 and 470 to 474 pin (and 458
--   wrote): after 475 a re-run of 462, 463 or 470 to 474 refuses (that pin),
--   changing nothing. Most refuse already at 474 on another pin, which 475
--   does not change: 458 (correct_invoice, 464's), 462, 470, 471 and 472
--   (the preview, 474's), 463 (invoice_transferable_benefits, 473's); 473's
--   and 474's re-runs leave all alone at 474 and refuse after 475 (checked
--   on copies, below). All are applied, so nothing is lost.
--   1. Before it, read only (invoice numbers and counts only; production was
--      not read for this file). 475 refuses no state; this lists whose next
--      reopening changes (1) and what needs the Owner (2, 3). On the
--      production facts known (27 Oct 2026: no reopening waits, no session
--      queued twice) it lists nothing:
--     with
--     -- therapy sessions waiting for a reopening's payment: per session,
--     -- its waiting rows, what they hold and what the session shows as
--     -- refunded and cancelled
--     w as (
--       select q.invoice_id, q.session_id, count(*) as n_rows, sum(q.quantity) as queued,
--              max(s.quantity_refunded + s.quantity_cancelled) as shows
--         from public.invoice_reopen_sessions q
--         join public.customer_therapy_sessions s on s.id = q.session_id
--        where q.applied_at is null
--        group by q.invoice_id, q.session_id),
--     found(reason, invoice_id, n) as (
--       select '1 changes: cancelled or refunded with a therapy session an earlier reopening queued still waiting; reopened again, before 475 the session was queued again and the payment that settles it refused, from 475 it is not queued again and that payment reinstates it once (the count is of sessions)', i.id, count(*)
--         from public.invoices i join w on w.invoice_id = i.id
--        where i.deleted_at is null and i.status::text in ('cancelled', 'refunded') and w.n_rows = 1
--        group by i.id
--       union all
--       select '2 for the Owner (not changed by 475: NOT COVERED 3): a therapy session queued by two or more reopenings still waiting; the payment that settles the invoice is refused ("Therapy session reopening changed; reload its original evidence"), before 475 and after it (the count is of sessions)', i.id, count(*)
--         from public.invoices i join w on w.invoice_id = i.id
--        where i.deleted_at is null and w.n_rows > 1
--        group by i.id
--       union all
--       select '3 for the Owner (not changed by 475: NOT COVERED 4): a therapy session waiting once whose refunded and cancelled count is no longer what its row holds; the payment that settles the invoice is refused, before 475 and after it (the count is of sessions)', i.id, count(*)
--         from public.invoices i join w on w.invoice_id = i.id
--        where i.deleted_at is null and w.n_rows = 1 and w.queued <> w.shows
--        group by i.id)
--     select f.reason, i.invoice_no, f.n
--       from found f join public.invoices i on i.id = f.invoice_id
--      order by f.reason, i.invoice_no
--      (The suite runs this same text on its cases' states before 475 and
--      checks what it lists.)
--   2. Dry run on a copy of production as it is then: work out its
--      fingerprint and grant list first (they must be the BEFORE figures
--      below, or be worked out again on that copy); apply this file twice;
--      the first run ends at the AFTER fingerprint below, the second changes
--      nothing ("left alone"); and the suite, with the earlier suites below.
--   3. Apply (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself.
--   4. No page change goes with it (NOT CHANGED).
--   Afterwards (checked on copies of production at 474, 27 Oct 2026): a
--   re-run of 462, 463 or 470 to 474 refuses on its pin of reopen_invoice
--   (475's AFTER is not its md5), 458's on its pin of correct_invoice (as
--   at 474, 464's), each changing nothing; 475's own leaves all alone. The
--   suites that read reopen_invoice's version, where 475 is in:
--   reopen-dialog-waiting-credit-474 (-v nomig=1: its THq, KNOWN K1, checked
--   as 475 settles it), reopen-refund-cycles-451 (10: reopen_invoice at
--   475's AFTER), rentals/invoice-follows-458 (-v skip_install=1: G1 reads
--   475's reopen_invoice as 458's); refunded-units-not-used-448 and
--   sold-voucher-issuance read it too and are not affected (451's comment
--   is kept; an older md5). function-grants is unchanged (nothing is
--   added). The other suites of the stack (91 in all, and print-note-456
--   with -v skip_install=1) end the same with 475 in as without it; those
--   whose own install refuses on today's stack refuse the same.
--
-- BEFORE (production at 474, 27 Oct 2026; md5 of pg_get_functiondef with
-- search_path public)
--   changed
--   reopen_invoice(uuid,text,uuid)                                     0ff61e4ead121c198ea7f90a7fc78274  (458's)
--   relied on, not changed (pinned)
--   invoice_reopen_preview(uuid)                                       e09ebf9c0841ef5463f96b26f4933541
--   invoice_reopen_preview_before_sessions(uuid)                       7e1ef2d25415e69b3f770fe2efd45190  (474's AFTER)
--   trg_create_therapy_sessions_on_paid()                              af85d6800c7d980565ef8d68898b6a38
--   refund_invoice_therapy_sessions(uuid,numeric,text,uuid)            93739f00ada43b1c3f4177b32c9bdc52
--   correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid)   12e1cf25bb069521adfe18809bcef68d
--   create_therapy_sessions_for_invoice(uuid)                          c0a45b7ce309cb9b4ceea53b212bd4aa
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)          804ecd829cfecf713783a09a05d93c7e
--   cancel_invoice_recorded(uuid,text,uuid)                            de52d9dbaef8ab15163bef35cb9d733d
--   apply_reopened_invoice_benefits()                                  36eaa7224e514d3e7e42e3eeb51acfb5
--   apply_reopened_invoice_vouchers()                                  6684840544d1ad8a28e2415934300054
--   credit_given_back_follows(uuid)                                    f2a7a4d1ca28f0865b14e3f1e5e02bbb  (472's AFTER)
--   invoice_voucher_reopen_candidates(uuid)                            20405a96c8780eac6425a5dae59c29e1
--   invoice_voucher_stock_unrecorded(uuid,boolean)                     91c8f0fa69ef6337f323b7ac467a8c2b
--   deduct_invoice_stock(uuid,text)                                    32183fe9e7c15ed0b11307c48289831a
--   create_special_docs_for_invoice(uuid)                              429f4ac315cb5d0557c2005807bad115
--   reconcile_invoice_commissions(uuid,text)                           3c267728e215d17ebeb9cfe9cb7db47c
--   invoice_revision_retry(uuid,uuid,jsonb)                            5c33c50a8f6870d8a66f74b63b782f24
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   invoice_net_received(uuid)                                         f256bea69b7defa38a950753bbc248da
--   invoice_financial_position(uuid)                                   ba7eccbfeff217c8b1969b0e55a010ca
--   is_owner_or_manager()                                              a98e50f1b6d3fa1e6c62cf52a8073cc8
--   user_has_store_access(uuid)                                        708992afaa6c3951f6329239b742987c
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)       80c80d386a5241e63b353e35e13ef250  (the self-test)
--   record_invoice_payment(uuid,jsonb,uuid)                            9c70097ed4da614fb9dcc66fdfcdb7d6  (the self-test)
--   public function fingerprint, production now (474)                 c19401919a0a8b67746e18b8f7a78639 (1387 functions; head 20261027012311)
--   grant list (string_agg(signature '=' proacl, '|'), sorted)          381ef69cb44f960ff981585ff8402fa1 (production lists the same
--                                                                      grants in another order: compare as sets)
-- AFTER (for later guards)
--   reopen_invoice(uuid,text,uuid)                                     30066e137b9b75b5789a050c14debc04  (grants kept: signed-in staff, postgres, the service role)
--   public function fingerprint, worked out on a copy of production at 474 (27 Oct 2026; a second run the same):
--     production now (474) -> 475                                      e948504da4c17c1c15ff871fcb1e5631 (1387 functions: none added, none dropped)
--   grant list after 475                                               381ef69cb44f960ff981585ff8402fa1 (unchanged)
--
-- Test: scripts/invoices/tests/reopen-sessions-queued-once-475.sql
-- (begin ... rollback; it installs this file twice; -v nomig=1 where it is
-- in). It reproduces THq and its siblings first (two and three reopening
-- cycles, sessions refunded by line before them, cancelled only or refunded
-- in full, "Record refund paid" and the guided Cancel the second time, a
-- merge while it waited or once cancelled again, beside credit, Premium
-- Bundle and voucher lines, settled once then again), with the Reopen
-- dialog read before each reopening and compared with what it queued and
-- what the payment reinstated (Record Payment, the Pay dialog, Correct
-- payment); then checks the header's query (1 to 3), the refusals, the
-- install, every case after 475 (paid; each session reinstated once; the
-- dialog's count what was queued and reinstated; everything before the
-- payment exactly as before 475), the controls unchanged, cases begun
-- before 475 and finished after it, the text of reopen_invoice beside the
-- sessions step exactly 458's, and NOT COVERED 1 to 4 as KNOWN. Each app
-- call is followed by what its commit does (462's trigger is deferred).
-- Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The function this changes: BEFORE (production, 27 Oct 2026: 458's
  -- AFTER, as 462, 463 and 470 to 474 pinned it) and AFTER md5s; who may call it,
  -- as read (kept) ═══════════════════════════════════════════════════════
  c_sig constant text := 'reopen_invoice(uuid,text,uuid)';
  c_before constant text := '0ff61e4ead121c198ea7f90a7fc78274';
  c_after constant text := '30066e137b9b75b5789a050c14debc04';
  c_acl constant text := '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}';

  -- ══ The whole text (exactly as the database prints it back) ═════════════
  c_def constant text := $d1$CREATE OR REPLACE FUNCTION public.reopen_invoice(p_invoice_id uuid, p_reason text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare i public.invoices%rowtype; p jsonb; n numeric; v_rev int; v_status invoice_status; v417 record;
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can reopen invoices'; end if;
 if nullif(trim(p_reason),'') is null or p_request_id is null then raise exception 'Reopening reason and request ID are required'; end if;
 select * into i from public.invoices where id=p_invoice_id for update;
 if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 if public.invoice_revision_retry(i.id,p_request_id,jsonb_build_object('operation','reopen','reason',p_reason)) then
  return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'replayed',true); end if;
 p:=public.invoice_reopen_preview(i.id);
 if not (p->>'can_reopen')::boolean then raise exception 'Reopening requires resolution: %',p->'blockers'; end if;
 select coalesce(max(revision_no),0)+1 into v_rev from public.invoice_revisions where invoice_id=i.id;
 insert into public.invoice_revisions(invoice_id,revision_no,snapshot,edited_by,edit_reason,request_id)
  values(i.id,v_rev,jsonb_build_object('invoice',to_jsonb(i),'reopen_preview',p),auth.uid(),p_reason,p_request_id);
 insert into public.invoice_reopen_benefits(invoice_id,source_ledger_id,request_id,amount,created_by)
  select i.id,l.id,p_request_id,l.amount,auth.uid() from public.customer_credit_ledger l
  where (l.source_type='invoice_cancel_benefit' and l.source_record_id=i.id
    or l.source_type='invoice_benefit_refund' and exists(select 1 from public.invoice_refunds r where r.invoice_id=i.id and r.request_id=l.source_record_id))
    and not exists(select 1 from public.invoice_reopen_benefits b where b.source_ledger_id=l.id);
 -- 417 (the Owner, 9 Oct 2026): units an earlier reopening queued, and still
 -- waiting because the invoice was cancelled again before it was settled,
 -- are given with this one. Only what is more is queued, so each unit is
 -- given, and its stock taken, once. Before, both were given.
 -- 451 (the Owner, 22 Oct 2026: "fix the rare 446 voucher case too"): only
 -- the cancellation's part of what waits is counted again here. The
 -- candidates are what a cancellation took back (cancelled_unused_value,
 -- where its units stay while they wait) and the units refunded by line
 -- since the last reopening. What waits may also be units an earlier line
 -- refund took, which an earlier reopening queued to give back and the
 -- candidates no longer count; and units refunded while they waited come
 -- off the queue and off cancelled_unused_value alike (446). So the waiting
 -- units come off only up to cancelled_unused_value. Before, all of them
 -- did, and a unit refunded on each side of a reopening was given back for
 -- one side only (a line of two: 1 voucher for S$60).
 insert into public.invoice_reopen_vouchers(invoice_id,benefit_id,request_id,quantity)
 select i.id,c.benefit_id,p_request_id,c.quantity-least(coalesce(w.quantity,0),b.cancelled_unused_value::int)
   from public.invoice_voucher_reopen_candidates(i.id) c
   join public.invoice_benefit_values b on b.id=c.benefit_id
   left join (select q.benefit_id,sum(q.quantity)::int as quantity from public.invoice_reopen_vouchers q
               where q.invoice_id=i.id and q.applied_at is null group by q.benefit_id) w on w.benefit_id=c.benefit_id
  where c.quantity-least(coalesce(w.quantity,0),b.cancelled_unused_value::int)>0;
 -- 475 (the Owner, 27 Oct 2026: "Yes, fix it next"; 474's NOT COVERED 1):
 -- sessions an earlier reopening queued, and still waiting because the
 -- invoice was cancelled again before it was settled, are reinstated with
 -- this one. Only what is more is queued, as 417 does for voucher units, so
 -- the payment that settles the invoice finds one row per session, what it
 -- shows as refunded and cancelled, and reinstates it once
 -- (trg_create_therapy_sessions_on_paid). While a session waits nothing
 -- changes that (its refund by line and its customer change are refused, and
 -- a cancellation finds none of it unused), so nothing more is queued for it.
 -- Before, each reopening queued it again, and that payment was refused at
 -- the second row ("Therapy session reopening changed; reload its original
 -- evidence"): the invoice could never be settled.
 insert into public.invoice_reopen_sessions(invoice_id,session_id,request_id,quantity)
 select i.id,s.id,p_request_id,s.quantity_refunded+s.quantity_cancelled-coalesce(w.quantity,0) from public.customer_therapy_sessions s
   left join (select q.session_id,sum(q.quantity)::int as quantity from public.invoice_reopen_sessions q
               where q.invoice_id=i.id and q.applied_at is null group by q.session_id) w on w.session_id=s.id
 where s.invoice_id=i.id and s.is_current and s.quantity_refunded+s.quantity_cancelled-coalesce(w.quantity,0)>0;
 n:=public.invoice_net_received(i.id);
 v_status:=case when i.total_amount=0 and i.has_foc then 'completed_foc'::invoice_status
  when n>=i.total_amount then 'paid'::invoice_status when n>0 then 'partially_paid'::invoice_status else 'unpaid'::invoice_status end;
 -- 417 (the Owner, 9 Oct 2026): a reopening takes voucher stock once. The
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
 if v_status in ('paid','completed_foc') then perform public.deduct_invoice_stock(i.id,'Explicit invoice reopening: '||p_reason); end if;
 update public.invoices set status=v_status,paid_amount=n,reopened_at=clock_timestamp(),edit_count=coalesce(edit_count,0)+1,edited_at=now(),edited_by=auth.uid() where id=i.id;
 -- 393: reopened straight to paid (its money was still held), its special
 -- items and rentals wait for a warehouse again. Otherwise the payment
 -- that settles it raises them.
 -- 458 (the Owner, 22 Oct 2026, rule 6): and reopened as completed FOC, as
 -- Confirm FOC raises them; create_special_docs_for_invoice also sets a
 -- rental ended while out running again, or raises a new one for a unit
 -- received back.
 if v_status in ('paid','completed_foc') then perform public.create_special_docs_for_invoice(i.id); end if;
 perform public.reconcile_invoice_commissions(i.id,'Reopening: '||p_reason);
 update public.invoice_revisions set request_hash=md5((jsonb_build_object('operation','reopen','reason',p_reason))::text),after_snapshot=(select to_jsonb(v) from public.invoices v where v.id=i.id) where invoice_id=i.id and revision_no=v_rev;
 perform public.write_audit_ex('invoices',i.id,'invoice_reopened',to_jsonb(i),p,'invoices',p_reason,i.store_id);
 return public.invoice_financial_position(i.id)||jsonb_build_object('success',true);
end $function$
$d1$;

  -- ══ Relied on, not changed (production at 474, 27 Oct 2026): the Reopen
  -- dialog's preview (reopen_invoice calls it; its session count is what
  -- the payment now reinstates); what reinstates a waiting session and what
  -- refuses to touch one (what keeps a waiting row equal to what its session
  -- shows); the other queues' givers; what the rest of its text calls; the
  -- self-test's calls ═══════════════════════════════════════════════════
  c_relied constant text[] := array[
    'invoice_reopen_preview(uuid)',
    'invoice_reopen_preview_before_sessions(uuid)',
    'trg_create_therapy_sessions_on_paid()',
    'refund_invoice_therapy_sessions(uuid,numeric,text,uuid)',
    'correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid)',
    'create_therapy_sessions_for_invoice(uuid)',
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'apply_reopened_invoice_benefits()',
    'apply_reopened_invoice_vouchers()',
    'credit_given_back_follows(uuid)',
    'invoice_voucher_reopen_candidates(uuid)',
    'invoice_voucher_stock_unrecorded(uuid,boolean)',
    'deduct_invoice_stock(uuid,text)',
    'create_special_docs_for_invoice(uuid)',
    'reconcile_invoice_commissions(uuid,text)',
    'invoice_revision_retry(uuid,uuid,jsonb)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'invoice_net_received(uuid)',
    'invoice_financial_position(uuid)',
    'is_owner_or_manager()',
    'user_has_store_access(uuid)',
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    'record_invoice_payment(uuid,jsonb,uuid)'];
  c_relied_md5 constant text[] := array[
    'e09ebf9c0841ef5463f96b26f4933541',
    '7e1ef2d25415e69b3f770fe2efd45190',
    'af85d6800c7d980565ef8d68898b6a38',
    '93739f00ada43b1c3f4177b32c9bdc52',
    '12e1cf25bb069521adfe18809bcef68d',
    'c0a45b7ce309cb9b4ceea53b212bd4aa',
    '804ecd829cfecf713783a09a05d93c7e',
    'de52d9dbaef8ab15163bef35cb9d733d',
    '36eaa7224e514d3e7e42e3eeb51acfb5',
    '6684840544d1ad8a28e2415934300054',
    'f2a7a4d1ca28f0865b14e3f1e5e02bbb',
    '20405a96c8780eac6425a5dae59c29e1',
    '91c8f0fa69ef6337f323b7ac467a8c2b',
    '32183fe9e7c15ed0b11307c48289831a',
    '429f4ac315cb5d0557c2005807bad115',
    '3c267728e215d17ebeb9cfe9cb7db47c',
    '5c33c50a8f6870d8a66f74b63b782f24',
    'c705c733e213a27f0dc32d54322cc855',
    'f256bea69b7defa38a950753bbc248da',
    'ba7eccbfeff217c8b1969b0e55a010ca',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    '708992afaa6c3951f6329239b742987c',
    '80c80d386a5241e63b353e35e13ef250',
    '9c70097ed4da614fb9dcc66fdfcdb7d6'];
  -- The trigger that reinstates a waiting session at settlement, as read.
  c_trigger constant text := 'CREATE TRIGGER create_therapy_sessions_on_paid AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_create_therapy_sessions_on_paid()';
  -- What reads or writes the session queue, and what updates the sessions
  -- (by name; a session's own temporary functions are not counted), as read
  -- on production at 474; nothing calls reopen_invoice.
  c_queue_users constant text := 'correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid), refund_invoice_therapy_sessions(uuid,numeric,text,uuid), reopen_invoice(uuid,text,uuid), trg_create_therapy_sessions_on_paid()';
  c_queue_writers constant text := 'reopen_invoice(uuid,text,uuid), trg_create_therapy_sessions_on_paid()';
  c_session_writers constant text := 'correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid), refund_invoice_therapy_sessions(uuid,numeric,text,uuid), trg_create_therapy_sessions_on_paid()';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; i int; v_first boolean; v_acl text;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_svc uuid;
  t_case int; t_a uuid; t_inv uuid; t_item uuid; t_pay uuid; t_s uuid; t_k int; t_shown int; t_ev0 int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The text is the tested one.
  if md5(c_def) <> c_after then
    raise exception '475: the text in this file is not the tested one'; end if;

  -- The functions relied on are as read on production (at 474, 27 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '475: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying (475 goes in after 474).',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if (select string_agg(pg_get_triggerdef(t.oid), E'\n' order by t.tgname) from pg_trigger t
       where t.tgrelid = 'public.invoices'::regclass and t.tgfoid = 'public.trg_create_therapy_sessions_on_paid()'::regprocedure)
     is distinct from c_trigger then
    raise exception '475: the trigger that reinstates a reopening''s therapy sessions at settlement is not as read on 27 Oct 2026'; end if;

  -- The columns read, with these types; one queue row per session and
  -- reopening, of a quantity above 0.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('invoice_reopen_sessions', 'invoice_id', 'uuid'), ('invoice_reopen_sessions', 'session_id', 'uuid'),
                 ('invoice_reopen_sessions', 'request_id', 'uuid'), ('invoice_reopen_sessions', 'quantity', 'integer'),
                 ('invoice_reopen_sessions', 'applied_at', 'timestamp with time zone'),
                 ('customer_therapy_sessions', 'id', 'uuid'), ('customer_therapy_sessions', 'invoice_id', 'uuid'),
                 ('customer_therapy_sessions', 'is_current', 'boolean'), ('customer_therapy_sessions', 'quantity_refunded', 'integer'),
                 ('customer_therapy_sessions', 'quantity_cancelled', 'integer')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '475: these columns are missing or not as read on 27 Oct 2026: %', v; end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.invoice_reopen_sessions'::regclass and contype = 'u'
                  and pg_get_constraintdef(oid) = 'UNIQUE (session_id, request_id)')
     or not exists (select 1 from pg_constraint where conrelid = 'public.invoice_reopen_sessions'::regclass and contype = 'c'
                  and pg_get_constraintdef(oid) = 'CHECK ((quantity > 0))') then
    raise exception '475: the session queue''s keys are not as read on 27 Oct 2026 (one row per session and reopening, of a quantity above 0)'; end if;

  -- No other function takes the name (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'reopen_invoice'
     and p.oid::regprocedure::text <> c_sig;
  if v is not null then raise exception '475: another function takes the name of the one this changes: %', v; end if;

  -- Nothing calls reopen_invoice; what reads or writes the session queue
  -- and what updates the sessions: as read (a new way would need the same
  -- care).
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'reopen_invoice\s*\(' and ns.nspname not like 'pg\_temp\_%' and p.proname <> 'reopen_invoice';
  if v is not null then
    raise exception '475: functions call reopen_invoice (%), not as read on 27 Oct 2026; check how each reopens, then re-test', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'invoice_reopen_sessions' and ns.nspname not like 'pg\_temp\_%';
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+public\.invoice_reopen_sessions' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_queue_users or d is distinct from c_queue_writers then
    raise exception '475: what reads or writes the session queue (invoice_reopen_sessions) is not as read on 27 Oct 2026 (% / %); check what it queues and reinstates, then re-test', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'update\s+(public\.)?customer_therapy_sessions' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_session_writers then
    raise exception '475: what updates the therapy sessions (customer_therapy_sessions) is not as read on 27 Oct 2026 (%); check that a waiting session cannot change, then re-test', v; end if;

  -- The function: its BEFORE (replaced) or its AFTER (left alone).
  d := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  if md5(d) = c_after then
    raise notice '475: public.% is already this version; left alone', c_sig;
    v_first := false;
  elsif md5(d) = c_before then
    v_first := true;
  else
    raise exception '475: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig, md5(d);
  end if;

  -- ── On the first run: nothing is refused for the data (475 needs no
  -- decision before it goes in), but whose next reopening changes and what
  -- needs the Owner is named (the header's read-only query: 1, the next
  -- reopening queues the session once; 2 and 3, for the Owner).
  if v_first then
    with
    w as (
      select q.invoice_id, q.session_id, count(*) as n_rows, sum(q.quantity) as queued,
             max(s.quantity_refunded + s.quantity_cancelled) as shows
        from public.invoice_reopen_sessions q
        join public.customer_therapy_sessions s on s.id = q.session_id
       where q.applied_at is null
       group by q.invoice_id, q.session_id),
    found(reason, invoice_id) as (
      select 1, i.id from public.invoices i join w on w.invoice_id = i.id
       where i.deleted_at is null and i.status::text in ('cancelled', 'refunded') and w.n_rows = 1
      union
      select 2, i.id from public.invoices i join w on w.invoice_id = i.id
       where i.deleted_at is null and w.n_rows > 1
      union
      select 3, i.id from public.invoices i join w on w.invoice_id = i.id
       where i.deleted_at is null and w.n_rows = 1 and w.queued <> w.shows)
    select string_agg(format('%s: %s invoice(s) (%s)', f.reason, f.n, f.nos), '; ' order by f.reason) into v
      from (select f.reason, count(*) as n, string_agg(i.invoice_no, ', ' order by i.invoice_no) as nos
              from found f join public.invoices i on i.id = f.invoice_id group by f.reason) f;
    if v is not null then
      raise notice '475: the header''s query lists %: 1, the next reopening now queues the waiting session once and its payment reinstates it; 2 and 3 are for the Owner (NOT COVERED 3, 4), not changed by 475', v;
    end if;
  end if;

  -- Who may call it, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig))
     is distinct from (select array_agg(x::text order by x::text) from unnest(c_acl::aclitem[]) x) then
    raise exception '475: who may call public.% is not as read on 27 Oct 2026 (%)', c_sig,
      (select proacl::text from pg_proc where oid = to_regprocedure('public.' || c_sig)); end if;
  v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig));

  -- ── Change ──────────────────────────────────────────────────────────────
  if v_first then
    execute c_def;
  end if;

  -- ── Afterwards: installed exactly as tested, grants as before ───────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_after then
    raise exception '475: public.% is not at its AFTER md5 (%)', c_sig, md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))); end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig)) is distinct from v_acl then
    raise exception '475: the grants of public.% changed', c_sig; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("475 check", @example.com, fictional ACMA
  -- phones no customer uses); it ends by raising P0475, which undoes all it
  -- wrote. 462's trigger runs at commit; here at each step's end (SET
  -- CONSTRAINTS ... IMMEDIATE), as a commit would.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from generate_series(700, 799) g, lateral (select '+61491570' || g::text as p) x
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p desc limit 3);
    if coalesce(cardinality(t_phones), 0) < 3 then raise exception '475: the self-test found no three unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '475-check-' || t_sfx || '@example.com') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '475 check', '475-check-' || t_sfx || '@example.com', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('475 check ' || t_sfx, '475-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('475 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.therapy_services (service_code, name, standard_price, duration_minutes, is_active)
    values ('475-' || t_sfx, '475 check ' || t_sfx, 20, 30, true) returning id into t_svc;
    insert into public.therapy_service_stores (service_id, store_id, is_available) values (t_svc, t_store, true);

    for t_case in 1 .. 3 loop
      -- A 3-session line sold to A and paid S$60 (its sessions are made at
      -- payment); cancelled (the 3 sessions cancelled).
      insert into public.customers (full_name, phone) values ('475 Check Buyer ' || t_case || ' ' || t_sfx, t_phones[t_case]) returning id into t_a;
      t_inv := public.create_invoice(t_store, t_a, null::uuid,
        jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 3)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
      perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)), gen_random_uuid());
      select s.id into t_s from public.customer_therapy_sessions s where s.invoice_id = t_inv and s.is_current;
      if t_s is null then raise exception '475: the self-test''s sessions were not made at payment'; end if;
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      perform public.cancel_invoice_recorded(t_inv, '475 check', gen_random_uuid());
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      t_ev0 := (select count(*) from public.invoice_therapy_session_events e where e.session_id = t_s and e.event_kind = 'reopen');
      if t_case in (1, 2) then
        -- (a), (b) S$20 refunded by line (the Finance panel: one session),
        -- reopened (S$20 to pay, the session queued), cancelled again,
        -- reopened again (and in (b) once more).
        select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv;
        select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt';
        perform public.refund_invoice_recorded(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 20)),
          jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 20)), '[]'::jsonb, '475 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        for t_k in 1 .. t_case loop
          perform public.reopen_invoice(t_inv, '475 check', gen_random_uuid());
          set constraints public.credit_given_back_follows immediate;
          set constraints public.credit_given_back_follows deferred;
          perform public.cancel_invoice_recorded(t_inv, '475 check', gen_random_uuid());
          set constraints public.credit_given_back_follows immediate;
          set constraints public.credit_given_back_follows deferred;
        end loop;
        -- The Reopen dialog's "Unused therapy sessions to reinstate after
        -- settlement", then the last reopening.
        t_shown := (public.invoice_reopen_preview(t_inv)->>'sessions_to_reinstate_after_settlement')::int;
        perform public.reopen_invoice(t_inv, '475 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if t_shown is distinct from 3
           or (select count(*) from public.invoice_reopen_sessions q where q.session_id = t_s and q.applied_at is null) <> 1
           or (select sum(q.quantity) from public.invoice_reopen_sessions q where q.session_id = t_s and q.applied_at is null) <> 3 then
          raise exception '475: (%) the session waits % time(s) for % (wanted once for 3; the dialog said %)', chr(96 + t_case),
            (select count(*) from public.invoice_reopen_sessions q where q.session_id = t_s and q.applied_at is null),
            (select sum(q.quantity) from public.invoice_reopen_sessions q where q.session_id = t_s and q.applied_at is null), t_shown; end if;
        -- What is outstanding paid (Record Payment): the payment settles it.
        perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
          'amount', (public.invoice_financial_position(t_inv)->>'outstanding')::numeric)), gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        t_k := 1;
      else
        -- (c) a control: reopened straight to paid (the money held), cancelled,
        -- reopened straight to paid again: reinstated at once each time.
        for t_k in 1 .. 2 loop
          if t_k = 2 then
            perform public.cancel_invoice_recorded(t_inv, '475 check', gen_random_uuid());
            set constraints public.credit_given_back_follows immediate;
            set constraints public.credit_given_back_follows deferred;
          end if;
          perform public.reopen_invoice(t_inv, '475 check', gen_random_uuid());
          set constraints public.credit_given_back_follows immediate;
          set constraints public.credit_given_back_follows deferred;
        end loop;
        t_k := 2;
      end if;
      if (select status::text from public.invoices where id = t_inv) <> 'paid'
         or (select s.quantity_purchased - s.quantity_used - s.quantity_refunded - s.quantity_cancelled
               from public.customer_therapy_sessions s where s.id = t_s and s.is_current and s.status = 'available') is distinct from 3
         or exists (select 1 from public.invoice_reopen_sessions q where q.invoice_id = t_inv and q.applied_at is null)
         or (select count(*) from public.invoice_therapy_session_events e where e.session_id = t_s and e.event_kind = 'reopen') - t_ev0 <> t_k then
        raise exception '475: (%) the payment did not reinstate the sessions once (status %, available %, waiting %, reinstated % time(s))', chr(96 + t_case),
          (select status::text from public.invoices where id = t_inv),
          (select s.quantity_purchased - s.quantity_used - s.quantity_refunded - s.quantity_cancelled from public.customer_therapy_sessions s where s.id = t_s),
          (select count(*) from public.invoice_reopen_sessions q where q.invoice_id = t_inv and q.applied_at is null),
          (select count(*) from public.invoice_therapy_session_events e where e.session_id = t_s and e.event_kind = 'reopen') - t_ev0; end if;
    end loop;
    raise exception using errcode = 'P0475', message = '475: self-test done, undone';
  exception when sqlstate 'P0475' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
