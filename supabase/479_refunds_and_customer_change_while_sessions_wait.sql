-- 479_refunds_and_customer_change_while_sessions_wait.sql
--
-- A THERAPY SESSION WAITING FOR ITS INVOICE'S REOPENING TO BE PAID (OR ONCE
-- THE INVOICE IS CANCELLED AGAIN) CAN BE REFUNDED BY LINE, THE SESSIONS
-- REFUNDED COMING OFF WHAT WAITS, AND THE INVOICE'S CUSTOMER CAN BE
-- CHANGED, THE WAITING SESSIONS GOING TO WHOEVER HOLDS THE INVOICE'S
-- BENEFITS; THE GUIDED CANCEL WITH "RECORD REFUND PAID" AND THE GUIDED
-- REFUND IN FULL REFUND IT WHERE THEIR PLAN COMES OUT IN WHOLE SESSIONS AND
-- VOUCHER UNITS, BUT ARE REFUSED AS BEFORE WHERE THEIR PLAN WAS CUT TO THE
-- MONEY HELD AND ANOTHER OF ITS LINES HAD SOMETHING TO REFUND, OR WHERE IT
-- GIVES MONEY AGAIN TO A PRODUCT LINE A REFUND BY LINE PAID BACK BEFORE THE
-- REOPENING (NOT COVERED 17, OPEN FOR THE OWNER), AND, AS BEFORE, OFFER NO
-- SESSION WHOSE MONEY A REFUND BY LINE PAID BACK BEFORE THE REOPENING (475's
-- NOT COVERED 1 and 2; the Owner, 27 Oct 2026, answer F, and 29 Oct 2026,
-- "Keep today's result" and, ~18:45 SGT, "Keep today's refusal")
--
-- (The number 479 is this file's name, its errors' prefix, its self-test's
-- error code P0479 and its suite's; if it changes at commit, change it in
-- these places alone: the file name, the "479:" messages, P0479, the suite,
-- and the "-- 479 (the Owner" lines the suites find the three functions'
-- version by.)
--
-- WHO FOUND IT
--
--   475's builders (its NOT COVERED 1 and 2 and its suite's KNOWN K1 and K2:
--   THw, THb, THgc, THrf, THchw, THchc, THchk, 27 Oct 2026), put to the
--   Owner with 476 to 478's questions. Reproduced for this file on copies of
--   production at 475 with 476, 477 and 478 applied (eae7f82f, 1390
--   functions, 28 Oct 2026) and again on copies of production as it was then
--   (478 in, 29 Oct 2026: the same eae7f82f) with the cases of this file's
--   suite: made-up records, the app's own calls (the invoice form and the
--   Pay dialog, Record Payment in full or of an amount, Correct payment,
--   Cancel, Reopen, the Finance panel's refund by line of a therapy line by
--   money and of a credit or voucher line, "Record refund paid", the guided
--   Cancel and Refund in full as an Owner confirms them, the invoice form's
--   customer change with 'transfer' or 'keep' and a correction of the line,
--   its quantity, the store or the notes, a customer merge), each followed
--   by what its commit does. The review of 476 to 479 (28 Oct 2026): this
--   file's first build locked the waiting sessions on every status write,
--   so a part payment and a customer merge at the same moment could
--   deadlock (fixed here: SAFETY); and, not 479's, a release that counts
--   money that paid for lines already delivered (NOT COVERED 11). The review
--   of that fix and the final check of 476 to 479 (28 Oct 2026, each app
--   call committed): the first build also changed the refund options, so
--   that they offered again the sessions a refund by line had paid back
--   before the reopening; on an invoice with another line the guided Refund
--   in full and Cancel then refunded the session money with the other
--   line's, or took the other line's money for the sessions, or were
--   refused, by the order the lines happen to be listed in. Put to the
--   Owner (THE OWNER'S ANSWERS, 29 Oct 2026): this file no longer changes
--   the refund options. The review of that build (29 Oct 2026, each app
--   call committed) found the line order still deciding where a plan offers
--   more than the money held, which the refund options as they are already
--   do (sessions or vouchers paid back with no line, "Record refund paid",
--   or a product line paid back before the reopening, then part of the
--   money paid again: invoice_action_plan cuts such a plan in the order the
--   lines are listed): 478 refused the guided flow wherever the cut gave the
--   waiting sessions some of the money, the build let it go through where
--   the cut was whole units, so which line it refunded followed that order
--   (TVn60, TVn20, PRxr, PRx, PRnl, PRxc). Put to the Owner with three
--   findings not caused by 479 (a product taken from stock again by the
--   payment that settles a reopened invoice, NOT COVERED 1; money a Cancel
--   leaves due on an invoice that issued credit, NOT COVERED 15; half a
--   cent, NOT COVERED 14): the Owner's answers of 29 Oct 2026 (~18:45 SGT,
--   below). This build (30 Oct 2026) keeps 478's refusal there (the refund
--   reads the plan at the session's turn: WHAT THIS DOES). Reproduced first
--   on copies of production at 478 and with the previous build (c0ae37fa),
--   each app call committed, the shapes in both line orders (TVn60, TVn60c,
--   TVn20, KGn, KGnc, TVn, PRxr, PRx, PRnl, PRxc, KG45, KG45c, KGn40): at
--   478 every shape whose plan gave the waiting sessions some of the money
--   was refused ("Settle the reopened invoice before changing its queued
--   sessions", or 252's "Refund whole unused therapy sessions ..."); the
--   previous build refunded TVn60, TVn60c, TVn20 with the therapy line
--   first and PRxr, PRx, PRnl, PRxc in either order (the product refunded a
--   second time with the product line first: S$80 on its S$40 line); this
--   build ends every one of them exactly as 478 (in both orders: on the
--   copies the same steps listed the lines in either order). Checking that
--   second refund: 478 refunds a product line paid back before the reopening
--   a second time too, wherever the guided plan gives it money and no
--   waiting session any (NOT COVERED 17, open for the Owner; not 479's;
--   where the plan gives a waiting session money 478 refuses it, and so does
--   this file since 2 Nov 2026, below).
--   Re-based (2 Nov 2026) on production as it was then (485: other sessions
--   applied 480, 483, 482, 484 and 485 since 478, each with the Owner's
--   go-ahead): none of them changes a function this file changes or relies
--   on, or what its catalogue checks read; nothing in this file's text
--   changed but its header and the comments of its checks (DEPLOY ORDER,
--   BEFORE, AFTER).
--   The review of the re-based build (2 Nov 2026, each app call committed,
--   on copies of production at 478 with this file, made-up records): where
--   at least two other lines are listed, one holding credit, vouchers or
--   sessions, and the plan does not look cut at the session's turn, the
--   refund trusted the plan the request saved, comparing the money held,
--   the lines, the session line's and the other lines' offers but not what
--   a line holding credit, vouchers or sessions offered; credit given back
--   to a package line between the request and the approval (a session paid
--   from the package's credit, cancelled, its refund recorded) made the plan
--   carried out cut (the package's S$100, the sessions' S$60, the product
--   given S$20 of its S$40) while the saved plan was not (the package's
--   S$80), and with the package listed before the therapy line the waiting
--   sessions were refunded, where 478 refuses (A1; the guided Cancel with
--   "Record refund paid", AG; a reviewer's by-hand line order and the same
--   reached with the app's own calls); in the other orders, or with the
--   request raised after the credit came back, it was refused. Reproduced
--   for this build on copies of production at 485 with the previous build
--   (each app call committed: A1, AG approved; refused at 485). This build
--   (2 Nov 2026) checks such a plan again once every line is done (WHAT
--   THIS DOES): A1 and AG refused as at 485, every key; the other 145 cases
--   of the suite, each app call committed, exactly as with the previous
--   build.
--   The review of that build (the fix review, 2 Nov 2026, each app call
--   committed, made-up records, on copies of production at 485): two cases
--   its suite called answer F's result, AC and AGC, rest on a product line
--   refunded by line while the invoice was cancelled and offered again by
--   the guided plan after the reopening (the reopening charges the line
--   again and the refund options count only its refunds since), so that
--   build refunded the product's S$40 line a second time together with the
--   waiting sessions, where 485 refuses both: whether such a line may be
--   refunded again is NOT COVERED 17, open for the Owner, not 479's to
--   decide. In money: AC (a S$100 Credit Package, the sessions and a S$40
--   product added by a correction, S$20 of the credit spent on a session
--   S1, cancelled, the product's S$40 refunded by line, reopened, S$20
--   paid, the guided Refund in full) paid back all S$220 the customer had
--   paid (S$80 on the S$40 product line) while S1 stayed available, and
--   left the invoice part-paid with S$20 outstanding, though it was
--   refunded in full; AGC (the guided Cancel) cancelled it with all S$220
--   paid back and S1 kept: a S$20 session for S$0. With no sessions at all
--   (ACnC, AGCnC) 478 itself does the same (NOT COVERED 17). And a refusal
--   once every line was done could show another line's message instead of
--   478's (AXV: "Voucher refund must cover whole unused units ...", where
--   485 says "Settle the reopened invoice ..."; NOT COVERED 16 had said no
--   case reached it). Reproduced for this build, each app call committed,
--   on copies at 485 and with the previous build (479 082badac with 481
--   ff40ea0a), in the line order the copies gave and with hash and merge
--   joins off: AC and AGC in six line orders each (XN1R to XN6C), ACp (AC,
--   then the S$20 outstanding paid: S$20 net for S1; without 481 that
--   payment also took the product from stock again, its line refunded
--   twice), AXV
--   (its message 478's with the lines listed in one order, the vouchers'
--   in the other), and, checking it, AXVn, AVXn (a voucher line, no credit
--   given back) and TPr, PTr, TPrc, PTrc (only the sessions and the
--   product, S$40 paid again: not cut). This build (2 Nov 2026) refuses the
--   session as 478 refuses it, at its turn, wherever the plan gives money
--   to a line holding no credit, vouchers or sessions that a refund by line
--   paid back before the last reopening (WHAT THIS DOES): each case above
--   ends exactly as at 485, every key, in both orders (AXV and AVX with
--   478's message); A1, AG, A1p, AN and A1x are refused there too, A1 and
--   AG at the session's turn now rather than once every line is done, with
--   the same message; the other cases as with the previous build.
--   The review of that build (the second fix review, 3 Nov 2026, each app
--   call committed, made-up records, on copies of production at 485): with
--   at least two other lines listed, one holding credit or vouchers, the
--   refund took the plan as not cut wherever no other line offered anything
--   at the session's turn, without reading the plan the request saved. That
--   is so where the credit and voucher lines are listed before the sessions'
--   (the refund reaches them first, and they show nothing once it has) and
--   any other line has nothing left (a product line refunded by line since
--   the reopening, which the guided Cancel lists at S$0). So a request
--   approved after the invoice changed (an ordinary part payment between
--   the request and the approval) went through with those lines listed
--   first, and was refused with the sessions' line listed before any of
--   them, where 485 refuses it in every order: the order Postgres happens
--   to list the lines
--   in decided it, which the Owner's answer of 29 Oct 2026 forbids. Y1: a
--   S$100 Credit Package, then 2 vouchers at S$30 and the 3 sessions added
--   by a correction, paid (S$220), cancelled, 1 session refunded by line,
--   reopened (S$200 held), the guided Refund in full requested (its plan:
--   the package's S$100, the vouchers' S$60, the sessions' S$40), S$10
--   paid, approved as it reads then: with the lines listed package,
--   vouchers, sessions, S$200 paid back, S$10 kept, 1 session waiting; with
--   the sessions listed before the vouchers (Y2, the sessions added before
--   them) or first (Y1's steps with the refund options' lines planned by
--   hash joins), refused; the guided Cancel the same (Y3, Y4); V1, V2, V3:
--   a voucher line, the sessions and a S$40 product, 1 session refunded by
--   line while cancelled, reopened, the product's S$40 refunded by line, the
--   guided Cancel requested, S$10 paid, approved: through with the vouchers
--   listed first, refused otherwise. The plan carried out was not cut, so no money
--   went astray either way; the result followed the line order. Reproduced
--   for this build on copies at 485 and with the previous build (479
--   2018c80d with 481 0e805e1e), each app call committed, by default, with
--   hash and merge joins off and with the refund options' lines planned by
--   hash joins: at 485 Y1 to Y4 and V1 to V3 refused in every order; the
--   previous build approved Y1, Y3 and V1 where the package or the vouchers
--   were listed before the sessions. This build (3 Nov 2026) reads the plan
--   the request saved there too (WHAT THIS DOES): each of them is refused as
--   at 485, every key, in every order seen; the Refund in full of V1's
--   state (V4, V5: the product, with nothing left, is not listed, so one
--   other line) and the same approvals with nothing changed between (Y1s,
--   Y3s, V1s) go through as with the previous build (answer F).
--   The review of that build (the third fix review, 3 Nov 2026, each app
--   call committed, made-up records, on copies of production at 485): the
--   shortcut that build deleted had let two things through, not one: a
--   credit or voucher line the refund reached first, which shows nothing by
--   the session's turn (Y1, Y3, V1: these follow the line order), and every
--   other line offering S$0 from the start, where no line order is
--   involved. So that build refused the second wherever two or more other
--   lines were listed at S$0, one a credit or voucher line (a credit or
--   voucher line refunded by line before the reopening, which the reopening
--   charges again; a product line refunded by line since it, which the
--   guided Cancel keeps), and anything
--   changed between the request and the approval (a payment, Correct
--   payment): only the session's line had anything to refund and the plan
--   was not cut, yet it was refused as at 485, where the same with one S$0
--   line or none went through: against answer F and the Owner's Q1 (a case
--   with no other item to choose between stays as built). Z8: a S$100
--   Credit Package, then 2 vouchers at S$30 and the 3 sessions added by a
--   correction, paid (S$220), cancelled, the package's S$100, both vouchers
--   and 1 session refunded by line, reopened (S$40 held), the guided Refund
--   in full requested (its plan: the package S$0, the vouchers S$0, the
--   sessions S$40), S$10 paid, approved: refused, S$50 held, 3 waiting (the
--   build before it: S$40 paid back, S$10 kept, 1 waiting). Reproduced for
--   this build on copies at 485 and with the build of 2 Nov 2026 (late: 479
--   2018c80d with 481 0e805e1e), by default, with hash and merge joins off
--   and with nested loops off, and with that build (479 1aa18683 with 481
--   82815a2b) by default, each app call committed (Z8, Z8b, Z8c, Z8p, Z5r, Z5x, Z5,
--   Z5xc, Z1, Z2, Z3, Z6, Z6x, KZ, KZx, Z7, Z7x, ZB, ZBx: the sessions listed
--   first, between the S$0 lines and last; through with the build of 2 Nov
--   2026 (late), refused with that build; the controls Z9, Z4, Z0, Z1r,
--   Z00, Z8s, Z1s, KZs, ZTTs: through on both). Checking it: a credit line
--   given credit back between the request and the approval (ZG: the
--   package's S$100 all spent on a session invoice S1 before the cancel, so
--   the saved plan gives the package S$0; S1 cancelled and its refund
--   recorded after the request, S$10 paid, approved): the build of 2 Nov
--   2026 (late) let it through with the package listed first (its S$100 and
--   the sessions' S$40 paid back) and refused it with the sessions first,
--   where 485 refuses it in every order (ZG, ZGx; the guided Cancel, ZGc,
--   ZGxc). This build (3 Nov 2026) goes on where only the session's line has
--   anything to refund, at its turn and in the plan the request saved,
--   compared by item (WHAT THIS DOES), and leaves the check once every line
--   is done, which, where the saved plan is not the one carried out, allows
--   no money for any other line: Z8 and the others above end as with the
--   build of 2 Nov 2026 (late), every key, whichever line is listed first;
--   ZG, ZGx, ZGc and ZGxc as at 485, every key, in every order seen (ZG at
--   the refund's status write, with 478's message); Y1 to Y4 and V1 to V3
--   stay refused, their package or vouchers offering money in the saved
--   plan; with nothing changed between, ZGs and ZGsx go through.
--   Re-based again (3 Nov 2026) on production as it is now (486, since 2
--   Nov 2026: another session's, the customer merge preview alone, with
--   the Owner's go-ahead): 486 changes no function this file changes,
--   relies on or reads, and no grant; nothing in this file's function texts
--   or pins
--   changed for it, only its header and its suite's fingerprint pair
--   (DEPLOY ORDER, BEFORE, AFTER).
--
-- WHAT WAS WRONG
--
--   A reopening queues, for each current therapy session of the invoice,
--   what it shows as refunded and cancelled (invoice_reopen_sessions; 475:
--   less what still waits), and the payment that settles the invoice
--   reinstates it (trg_create_therapy_sessions_on_paid). While it waited, or
--   once the invoice was cancelled again before it was paid, nothing could
--   change the session (252):
--   * a refund by line of its therapy line was refused, "Settle the reopened
--     invoice before changing its queued sessions"
--     (refund_invoice_therapy_sessions); so were the guided Cancel with
--     "Record refund paid" ticked and the guided Refund in full wherever
--     their plan refunds some of the line (they refund it by line,
--     refund_invoice_recorded). A 3-session line at S$20, paid S$60,
--     cancelled, S$20 refunded by line, reopened (S$20 to pay): S$20 more
--     refunded by line, refused (RW, 475's THw); the same once cancelled
--     again (RB, THb); the guided Cancel (GC, THgc) and Refund in full (GR,
--     THrf), refused; beside a Credit Package, a Premium Bundle, a voucher
--     line, and a package with a session paid from it and a voucher line,
--     the same (CPw, CPr, CPg, CPs, PBw, PBs, TV, MXw). Where it had been
--     refunded in full before the reopening (the sessions refunded, not
--     cancelled) and S$20 paid towards it since, the refund by line was
--     refused as "0 of 3 sessions remain refundable" (RF): the refund
--     counted the session's refunds before the reopening, though the
--     reopening charges the line again. "Record refund paid" with no line,
--     the plain Cancel and the guided Cancel with "Record refund paid" not
--     ticked went through;
--   * a customer change ('transfer' or 'keep'), "Settle the pending session
--     reopening before changing its allocation"
--     (correct_invoice_therapy_sessions): while it waited (CTw, CKv, CTv,
--     475's THchw, THchk) and once cancelled again (CTc, THchc).
--   So staff could not pay a customer back for sessions, or put the invoice
--   on the right customer, until the reopened invoice was paid in full or
--   cancelled and left; the guided flows offered actions that then failed.
--   Not wrong, and kept (the Owner, 29 Oct 2026): the guided Refund in full
--   and Cancel do not offer a waiting session's sessions whose money a
--   refund by line paid back before the reopening, as they do not offer
--   credit or voucher units a refund paid back (448). Where all of a therapy
--   line's sessions were refunded by line while the invoice was cancelled
--   and another line is on it, they refund the other line and keep the
--   session money (OWa, OWb, OWpb and their siblings); with only the therapy
--   line, refunded in full, reopened and S$20 paid, they find nothing to
--   refund (GRF, GCF), as for a Credit Package or vouchers in that state
--   (CRF, VRF; NOT COVERED 13). And kept (the Owner, 29 Oct 2026, ~18:45
--   SGT, "Keep today's refusal"): 478's refusal of a guided flow whose plan,
--   cut to the money held, gives a waiting session some of the money while
--   another line has something to refund (sessions whose money "Record
--   refund paid" paid back with no line show as cancelled, so the options
--   offer them again, and so they do a product line paid back before the
--   reopening: NOT COVERED 10). And kept rather than decided here (open for
--   the Owner, NOT COVERED 17): 478's refusal where the plan, cut or not,
--   gives money again to a product line a refund by line paid back before
--   the reopening (the fix review of 2 Nov 2026: AC, AGC).
--   Production, 29 Oct 2026 (read-only, as given to this builder; 476 to
--   478 in): no reopening waits (no unapplied row in invoice_reopen_sessions
--   or invoice_reopen_benefits); so it has not happened there; nothing to
--   repair. (Not read again for the re-base of 2 Nov 2026; the header's
--   query, DEPLOY ORDER step 1, lists any such invoice when it goes in.)
--   Production, 3 Nov 2026 (read only, 486 in, no 479 or 481 row; counts
--   only): the header's query returned no rows; no guided Cancel or Refund
--   in full request was pending; no reopened invoice was still open
--   (unpaid or part-paid), so none is exposed to NOT COVERED 17. Its
--   fingerprint (987d9ea6, 1398 functions), grant list (e68aa1ab), head
--   (20261102143942) and the three BEFORE md5s were as stated below.
--
-- THE OWNER'S ANSWERS
--
--   9 Oct 2026 (417) and 22 Oct 2026 (446, 451): a refund made while a
--   reopened invoice's credit or vouchers wait takes what it refunds off the
--   queue, so the payment that settles the invoice gives only what is still
--   owed; after any sequence of line refunds, cancels, reopenings and
--   settlements the customer holds exactly what the net payment buys.
--   22 Oct 2026 (448, "build the warning fix"): a voucher unit or credit a
--   line refund already paid back is not "used" (and the refund options do
--   not offer it again). 22 Oct 2026 (460): what a reopened invoice gives
--   back goes to whoever holds its benefits now: the record a merge kept,
--   the new customer after a customer change that took the benefits along
--   ('transfer'), the holder after one that left them ('keep'). 24 Oct
--   2026 (462, 463): a cancel or refund takes back what the invoice gave
--   from whoever holds it now; refunds paid back count as not used. 27 Oct
--   2026, answer F (ticked, with 476 to 478's):
--   "475 NC1/NC2: allow refund by line / guided Cancel with refund recorded
--   / Refund in full / customer change while reopened therapy sessions wait
--   (sessions come off the queue / follow the new customer)": a refund
--   takes what it refunds off the queue, as 446 does for voucher units, so
--   the payment brings back only what is still owed; a customer change
--   makes the waiting sessions follow 460's rule (the new customer with
--   'transfer', the holder with 'keep').
--   29 Oct 2026 (~14:00 SGT), asked from the final check of 476 to 479 (a
--   reopened invoice whose therapy sessions were all refunded while it was
--   cancelled, with vouchers, a Premium Bundle or a Credit Package on it
--   too): "Keep today's result": there the guided Refund in full and the
--   guided Cancel with "Record refund paid" work as before 479 (as at 475
--   to 478): they refund the other item(s) and keep the session money; the
--   waiting sessions are not offered again. Everything else answer F asked
--   stays: a refund by line of a waiting therapy line takes what it refunds
--   off the queue (the payment then brings back only what is still owed);
--   the guided flows go through where their plan comes out in whole
--   sessions and voucher units; a 'transfer' or 'keep' customer change
--   while sessions wait makes them follow 460's rule. Also answered 29 Oct
--   2026: the follow-ups the reviews found stay documented, unchanged: a
--   package added to an invoice already paid in full (NOT COVERED 11; 476's
--   13), the dialogs not naming who receives voucher units and sessions
--   (NOT COVERED 6 and 12; 476's 14), a Refund in full leaving a reopened
--   invoice part-paid (NOT COVERED 1), sessions a 'keep' left with the
--   buyer (NOT COVERED 3); and 476's commission window after a 'keep'
--   change (its NOT COVERED 7) stays as built. No other business rule is
--   changed by guessing (NOT COVERED).
--   29 Oct 2026 (~18:45 SGT), asked from the review of this file's previous
--   build (its NOT COVERED 10, the line order; with 1's product stock, 15 and
--   14, not caused by 479):
--   Q1, "Keep today's refusal": a reopened invoice waits for payment with
--   therapy sessions waiting and another item (vouchers, a bundle, a package
--   or a product); earlier money was paid back without a line ("Record
--   refund paid") or a product line was refunded, then part of it was paid
--   again; the guided Refund in full or Cancel with "Record refund paid"
--   must cut the money held across lines (invoice_action_plan's money cap,
--   in the unfixed order of the refund options' lines). Whenever that cut
--   would give the waiting sessions part of the money, the guided flow is
--   refused exactly as 478 refuses it, and staff refund item by item; where
--   the cut reaches only the other items it behaves exactly as 478. So the
--   outcome never depends on line order in a way 478 did not. A case with
--   no other item to choose between (only the therapy line: KG45, KG45c,
--   KGn40, whole sessions back, the remainder kept, as answer F asked) is
--   not this question and stays as built; the rule of 29 Oct (~14:00) and
--   answer F's cases stay as built. (This file reads it so where the plan
--   lists other lines at S$0 too: nothing to choose between there either;
--   the third fix review, 3 Nov 2026: Z8, Z1, KZ.)
--   Q2, "Fix it separately": the payment that settles a reopened invoice
--   (and, by the same rule, a part-paid invoice settled later) takes from
--   stock only what was not refunded by line since the sale or the last
--   reopening: a new migration, 481, after this one (not in this file; NOT
--   COVERED 1).
--   Q3 (NOT COVERED 15, money left due after a guided Cancel on an invoice
--   that issued credit) and Q4 (NOT COVERED 14, half a cent): leave them
--   documented, unchanged.
--   Not yet put to the Owner (open, 30 Oct 2026): NOT COVERED 16 (where the
--   plan the request saved is not the plan carried out, 478's refusal is
--   kept; corrected 2 Nov 2026: a saved plan that is not cut no longer lets
--   a cut plan through, it is checked again once every line is done;
--   corrected 3 Nov 2026: the saved plan is read also where no other line
--   offers anything at the session's turn, so the line order does not
--   decide it, but not where only the session's line has anything to
--   refund, at its turn and in the saved plan: that goes through as answer F
--   asked, the check once every line is done then allowing no money for any
--   other line where the saved plan is not the one carried out (the third
--   fix review, 3 Nov 2026); the guided Cancel and the Refund in full of one
--   state can end differently there, for the Owner with it) and
--   17 (a product line refunded before the reopening refunded again by the
--   guided flows: 478's own wherever the plan gives no waiting session
--   money, kept; where it gives one money 478 refuses it, and from 2 Nov
--   2026 so does 479, rather than decide it, but where it was paid back
--   with no line and all of it paid again: neither of 479's refusals
--   reaches it, the plan not being cut and the other reading only refunds
--   by line, so 479 lets it through where 486 refuses it, NL1, 3 Nov 2026;
--   no answer decides that, so it is for the Owner to confirm with 17).
--
--   3 Nov 2026, with the go-ahead for this file and 481: the Owner kept
--   the readings the final checks put to them. Where only the waiting
--   sessions' line has anything to refund and the other lines show S$0, the
--   guided flows go through (Z8 and its family). Money paid back with no
--   line and then all paid again goes through (NL1, NL2, NL1c); where this
--   header says that is for the Owner to confirm, it is confirmed. The
--   guided part refund follows the same rules. NOT COVERED 17, "Only what
--   was paid since": a separate update, not this file, is to make the
--   guided Refund in full and Cancel offer a product line refunded before
--   the reopening only what was paid for it since the reopening. Where this
--   header (or a comment in the function text) says 17 is open for the
--   Owner, that is the answer; until that update is in, this file's result
--   stands. NOT COVERED 16 and the other open items keep this file's
--   result.
--
-- WHAT THIS DOES (three functions changed, whole texts; nothing added; no
-- table, column, trigger or grant changes)
--
--   * refund_invoice_therapy_sessions(uuid,numeric,text,uuid) (252's). With
--     nothing waiting for the session, word for word as before; so too, a
--     session waiting, in a guided flow whose plan was cut to the money held
--     while another of its lines had something to refund (below): refused as
--     478 refuses it. With something waiting otherwise: what the payment
--     would reinstate is what waits; what was refunded by line since the
--     invoice was last reopened (the
--     session's 'refund' events since reopened_at: the reopening charges the
--     line again, so refunds before it count no more, as invoice_charge_
--     total and the refund options' line amounts count the line's money)
--     stays refunded. The two must add up to what the session shows (252's
--     evidence), otherwise refused ("Therapy session reopening changed;
--     reload its original evidence"). Whole sessions are refunded at their
--     original paid value, counted from those refunded since the reopening,
--     up to all but those used and those refunded since, as far as the money
--     held allows (refund_invoice_recorded; RF: after a Refund in full and a
--     reopening, the S$20 paid since). The sessions refunded come off what
--     waits, the most recently queued first (by the reopening's revision): a
--     row is lowered, or removed when nothing is left of it; each change is
--     in the invoice's Audit Log ('reopen_session_refunded': the row as it
--     was, the units, what still waits, the refund's request). The session's
--     counts: a waiting session refunded is now refunded (a cancelled one
--     counted as refunded); its 'refund' event as before. RW: S$20 more
--     refunded by line, 2 wait; paid S$20, 2 of 3 available, 1 refunded, the
--     customer having paid S$40 net (RWp); RW2p: S$40 refunded, 1 of 3 for
--     S$20; RF: the S$20 paid since refunded by line, 1 session off the
--     queue, paid: 2 of 3 for S$40.
--     In a guided flow (resolve_invoice_action_v2 carrying out the approval
--     of request p_request_id, which it names in invoice.therapy_reviewed
--     before it calls the refund: the guided Refund in full, Cancel with
--     "Record refund paid" or part refund) the refund first reads the plan as
--     it stands at the session's turn (invoice_action_plan for the request's
--     action and lines: what each line offers before the money cap, worked
--     out as the plan works it out, and the money held). First, wherever
--     that plan gives money to a line holding no credit, vouchers or
--     sessions (a product) that a refund by line paid back before the
--     invoice was last reopened (a line of invoice_refunds' lines, the
--     refund's row with them made at or before reopened_at), the session is
--     refused as 478 refuses it (below): such a line is offered again for
--     all it holds since the reopening, so it would be refunded a second
--     time, which is the Owner's to decide (NOT COVERED 17: AC, AGC, ACp,
--     AXV, AVX, TPr, PTr; TP2c, charged and paid again since, too). What
--     that line offers and its refunds before the reopening do not change
--     while the approval runs, so this does not follow the line order. The
--     refund has paid
--     nothing back yet (its money is recorded once every line is done), so
--     the money held is the plan's; the session's line and every line the
--     refund reaches after it are as the plan read them; a line it reached
--     before gave all it offered (the cut, if any, came after it, as this
--     line is given something) and shows less now where it holds credit,
--     vouchers or sessions. It counts the plan as cut while another line had
--     something to refund in three cases: this line is given less than it
--     offers (the cut is here) and money was left for a line before it, or
--     another line still offers something; this line is given all it offers
--     and another line still offers something which, with this line's, is
--     more than the money held; or, at least two other lines being listed
--     and one of them holding credit, vouchers or sessions (what it offered
--     may no longer show), the plan the request saved says so (its lines'
--     offers against its money held), or that saved plan is not the one
--     carried out by what can be compared (its money held, its lines, this
--     line's amount and offer, or what a line holding no credit, vouchers or
--     sessions offers, differ from the plan as it reads now: NOT COVERED 16).
--     That last case holds whether or not another line still offers
--     anything at the session's turn: a line holding credit, vouchers or
--     sessions that the refund reached first offers nothing by then, and
--     which lines it reaches first follows the order the lines are listed
--     in. (The build of 2 Nov 2026, late, took the plan as not cut wherever
--     no other line offered anything, so a request approved after the
--     invoice changed went through or was refused by that order: Y1, Y3,
--     V1; the second fix review, 3 Nov 2026.) But not where only the
--     session's line has anything to refund: no other line offers anything
--     at its turn and none offered anything in the saved plan (compared by
--     item, not by line order; the other lines are listed at S$0: a credit
--     or voucher line refunded by line before the reopening, which the
--     reopening charges again, or a product line refunded by line since it,
--     which the guided Cancel keeps). There nothing is left to choose
--     between and the plan is not cut, so it goes on, as answer F asked and
--     the Owner's Q1 keeps, however many lines are listed at S$0 and
--     whichever is listed first (Z8, Z8c, Z5r, Z5x, Z6, KZ, Z1, Z2; the build
--     of 3 Nov 2026 refused them wherever two or more other lines were
--     listed at S$0, one a credit or voucher line, and anything changed
--     between the request and the approval: the third fix review, 3 Nov
--     2026).
--     Where it counts the plan as cut, the session is refused exactly as 478
--     refuses it (252's checks, word for word: "Refund whole unused therapy
--     sessions at their original paid value; % of % sessions remain
--     refundable", else "Settle the reopened invoice before changing its
--     queued sessions"), which undoes the whole approval (TVn60, TVn60c,
--     TVn20, PRxr, PRx, PRnl, PRxc, VTPc; Y1 to Y4, V1 to V3; whichever line
--     is listed first).
--     Otherwise it goes on as above: the plan not cut (TV, TV2, PBs, CPs,
--     TVP, VTP, STv, V4, V5, Y1s, Y3s, V1s; NL1, NL2, NL1c, NOT COVERED
--     17(a)), or only the session's line
--     having anything to refund (KG45, KG45c, KGn40, no other line listed;
--     Z8 and the others above, the other lines listed at S$0: no other item
--     to choose between, as answer F asked). Where the cut gives
--     the session nothing the refund is not reached, as before 479. Where it
--     went on on the word of the saved plan (the last case, the saved plan
--     not cut; or only the session's line having anything to refund, at its
--     turn and in the saved plan, with two or more other lines listed, one
--     holding credit, vouchers or sessions), that plan cannot show what a
--     line the refund reached before the session's (credit, vouchers or
--     sessions) offered in the plan carried out, which may be more (credit
--     given back to it between the request and the approval); so the refund
--     leaves a check for the end of the approval
--     (invoice.therapy_plan_check, the transaction's own setting: the
--     invoice, the request, this line, what it offers, the money the lines
--     may take, what every other line offers at its turn and whether it
--     holds credit, vouchers or sessions, and the message 478 refuses it
--     with here), which trg_create_therapy_sessions_on_paid carries out
--     (below, (d)). The money the lines may take is the money held; but
--     where it went on because only the session's line had anything to
--     refund and the saved plan is not the one carried out by what can be
--     compared, it is this line's own offer, so any money the plan carried
--     out gave another line refuses it: a line given credit between the
--     request and the approval and reached first (ZG), which the saved plan
--     refuses at the session's turn with that line listed after the
--     session's (ZGx). (The previous builds' A1 and AG were refused there;
--     from 2 Nov 2026 the first rule refuses them at the session's turn,
--     their product line, refunded by line before the reopening, being
--     offered again. Refused there now: ZG and ZGc with the package listed
--     first, the check allowing no money for another line; no plan found
--     carried out cut reaches it. TVP, VTP, CTP, CFR and BFC, Y1s, Y3s and
--     V1s, and from the third fix review Z8, Z8c, Z5r, Z5x, Z6, KZ, Z1, Z2,
--     ZGs and ZGsx, reach the check and pass it: NOT COVERED 16.)
--   * trg_create_therapy_sessions_on_paid() (252's). (a) Whenever the
--     invoice's status is written and a session of it waits, the session
--     belongs to whoever holds the invoice's benefits now: 460's rule with
--     462's fall-backs for a deleted record (invoice_credit_live_holder(the
--     invoice, its holder, when it was made)). Where that is someone else, it
--     follows: in place, its counts and waiting rows with it (an event
--     'reassign' of 0 and the invoice's Audit Log row
--     'reopen_sessions_follow_holder'). It looks first without locks; only
--     where a waiting session must follow someone else does it lock the
--     waiting rows and the sessions and read them again, so a status write
--     that moves nothing (a part payment, Correct payment) locks no session,
--     as before 479. A correction writes the invoice's
--     status last, after it moved the benefits, so after a 'transfer' change
--     the sessions are the new customer's at once (CTw, CTv); after a 'keep'
--     they stay with their holder (CKv). (b) The payment that settles the
--     invoice reinstates, per session, all that waits for it; what was
--     refunded since the reopening stays refunded and nothing stays
--     cancelled. The evidence check is 252's counting those refunds: what
--     waits and what was refunded since add up to what the session shows
--     (with nothing refunded since, what waits is what it shows, as before);
--     summed per session, as a session may wait on two rows now (refunded
--     while it waited, cancelled again, reopened: RWc, rows 2 and 1). Each
--     row still gives one 'reopen' event under its reopening's request. (c)
--     The cancellation branch: word for word as before. (d) First, at the
--     status write that ends a guided refund (refund_invoice_recorded's last
--     write of the invoice, its money and lines recorded), the check the
--     refund left (above), for this invoice and that request: the lines the
--     refund recorded it carried out, in its order (invoice_refunds, the
--     request's row with the lines), give what the lines before the
--     session's were given (each all it offered: at what it was given, one
--     holding no credit, vouchers or sessions at what it offered at the
--     session's turn); every other line offered what it offered at the
--     session's turn (the refund had not reached it). Where those offers and
--     the session's come to more than the money held, the plan carried out
--     was cut and gave the waiting session part of the money while another
--     line had something to refund (the Owner, 29 Oct 2026 ~18:45 SGT, "Keep
--     today's refusal"): refused with the message the refund kept, the one
--     478 refuses it with at the session's turn, changing nothing (the whole
--     approval is undone). Where they do not, nothing changes (TVP, VTP:
--     the saved plan the one carried out, not cut). (The money held here is
--     what the refund left in the check: where it went on because only the
--     session's line had anything to refund and the saved plan is not the
--     one carried out, the session's own offer, so any money given to
--     another line refuses it: ZG, ZGc. This trigger's text is unchanged
--     from the build of 2 Nov 2026 for it: the refund sets the figure.) The
--     check is read once and cleared; a status write of any other invoice,
--     or with no such check, does nothing new.
--   * correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid)
--     (252's). A session whose reopening waits (or once its invoice was
--     cancelled again) may change customer; its line, quantity and store
--     still not (refused as before: CSw, CQw). It is not closed and replaced
--     (as a paid invoice's sessions are): it waits as it is, and follows (a)
--     above at the correction's end. Where the correction asks no 'transfer'
--     or 'keep' (the invoice issued no credit or vouchers: correct_invoice's
--     own test, invoice_transferable_benefits) its sessions follow the
--     change, as they do on a paid invoice (PK): written as move_invoice_
--     benefits_to_customer writes a change that takes the benefits along
--     ('invoice_benefits_followed_reassignment', to_customer, listing the
--     sessions), which is what 460's rule reads (CTw, CNN, CNb). Its
--     evidence must add up as in the refund; otherwise refused. And the
--     session's customer counts as changed when the correction moves the
--     invoice to a customer other than the session's holder (before 479:
--     other than the session's holder, the invoice's customer then always
--     being the holder: the same test), so sessions a 'keep' left with their
--     holder are not taken by a later correction that keeps the invoice's
--     customer (KKn: the notes) or sets it back to them (KK2). Once the
--     invoice is settled (paid), one that would change their line, quantity
--     or store, or move the invoice to a third customer, is refused,
--     changing nothing: "These therapy sessions were left with … when the
--     invoice's customer was changed, so their line, quantity or store
--     cannot be changed, nor the invoice moved to another customer, from
--     this invoice: set the invoice's customer back to them first. Nothing
--     was changed." (KK1; NOT COVERED 3); removing their line closes them,
--     as before. While they still wait (the waiting branch above), a move
--     of the invoice to another customer goes through, the sessions
--     following 460's rule ('keep': they stay with their holder, CKK;
--     'transfer': the new customer, CKT), and a change of their line,
--     quantity or store is refused, "Settle the pending session reopening
--     before changing its allocation" (CKq).
--   The guided Cancel with "Record refund paid", the guided Refund in full
--   and the guided part refund (invoice_action_plan and
--   resolve_invoice_action_v2, not changed) refund a waiting session through
--   the refund above, for what the refund options offer; the refund options
--   are not changed (the Owner, 29 Oct 2026). A waiting session's "unused"
--   sessions and its "up to" there count as refunded all it shows as refunded
--   (before the reopening or since), so the plans offer the sessions it shows
--   as cancelled, at their value, and never again one a refund by line paid
--   back; where its sessions were refunded by line, money paid since the
--   reopening stays held for them (it is not offered). Sessions shown as
--   cancelled whose money "Record refund paid" paid back with no line,
--   vouchers paid back that way, and a product line paid back before the
--   reopening (by line or with no line) are offered again at their value;
--   where a plan then offers more than the money held, invoice_action_plan
--   cuts it in the order the lines are listed (not fixed). Where that cut
--   gives the waiting session some of the money while another line has
--   something to refund, the approval is refused as 478 refuses it (the
--   Owner, 29 Oct 2026 ~18:45 SGT, "Keep today's refusal"); where it gives
--   the session nothing, the refund above is not reached and the plan goes
--   through or is refused as before 479; where only the session's line has
--   something to refund, its whole sessions go through (KGn40; NOT COVERED
--   10). So, a 3-session line at S$20 paid S$60, cancelled, S$20 refunded by
--   line, reopened: the guided Cancel (GC): cancelled, the S$40 held paid
--   back, 2 sessions off the queue (1 waits, for a later reopening); reopened
--   and paid S$60 (GCp): 3 of 3; the guided Refund in full (GR): the S$40
--   paid back, 2 sessions off the queue, the invoice still part-paid for S$20
--   (NOT COVERED 1); paid (GRp): 1 of 3 for S$20; with S$5 paid while it
--   waits, S$45 held (KG45): the S$40 paid back (2 sessions), the S$5 kept;
--   the guided Cancel the same, the S$5 shown due (KG45c); beside a voucher
--   line (TV), the Premium Bundle (PBs) or a Credit Package (CPs), or a
--   voucher line and a product (TVP, VTP): the sessions' S$40 and the other
--   lines' value, with no cut, so whichever line is listed first; paid: 1 of
--   3 for S$20. And where the therapy line's sessions were all refunded by
--   line while the invoice was cancelled (the Owner's case, 29 Oct 2026), the
--   plans leave the line out, as before 479: therapy and a S$100 Credit
--   Package, S$60 refunded, reopened, S$30 paid: the guided Refund in full
--   pays back the S$100, the S$30 stays held and the 3 sessions wait (OWa);
--   paid S$30: 3 of 3 for S$60 (OWap); the guided Cancel: cancelled, the
--   S$100 paid back, S$30 shown due (OWac), which, the invoice having issued
--   credit, "Record refund paid" with no line cannot record (NOT COVERED 15);
--   with 2 vouchers or the Premium Bundle and S$20 paid: the S$60 (S$140)
--   paid back, the S$20 kept (OWb, OWpb; Cancel: OWbc, OWpbc); with nothing
--   paid since: the other line's value, then paid S$60: 3 of 3 (OWa0, OWb0);
--   after OWa's Refund in full, a refund by line of S$20 of the S$30 kept
--   takes 1 session off the queue (OWak: paid, 2 of 3 for S$40); the other
--   S$10 stays held, and S$30 by line is refused (1.5 sessions).
--   Everything else as before: the refund options (what the Finance panel
--   shows and the guided plans offer), the credit and voucher queues (446,
--   451), the reopening (475's reopen_invoice: it queues what a session shows
--   less what still waits, so a later reopening queues again what was
--   refunded while it waited), the Reopen dialog's "Unused therapy sessions
--   to reinstate after settlement" (what the sessions show: what the next
--   reopening leaves waiting), Cancel, the plans' codes, the money, stock
--   (NOT COVERED 1).
--   On the copies (made-up records, each app call its own commit), a
--   3-session line at S$20 paid S$60, cancelled, S$20 refunded by line,
--   reopened (S$20 to pay), then:
--   * refunded by line while it waits: RWp 2 of 3 for S$40 net; RW2p 1 of 3
--     for S$20; RWc (cancelled again, reopened, paid S$40) 3 of 3 for S$60;
--     RWw (refunded again while the second reopening waits) 2 of 3; the Pay
--     dialog and Correct payment the same (RWpd, RWfx); the buyer merged into
--     K (RWm, RWmc): K's; refunded in full before the reopening, S$20 paid,
--     S$20 refunded by line (RF): 2 of 3 for S$40;
--   * once cancelled again: RB, then reopened and paid (RBp): 3 of 3 for
--     S$60; RBw (refunded while waiting and once cancelled again): 3 of 3;
--   * the guided flows: GC, GCp, GR, GRp, KG45, KG45c (above); paid back
--     with no line, reopened, S$40 paid, the guided Refund in full (KGn40):
--     the S$40, 2 sessions; paid, 1 of 3 for S$20; beside a voucher line and
--     a product, 1 session refunded while cancelled (TVP, VTP): the S$140
--     paid back, 1 waits; requested, S$10 paid, then approved as its plan
--     reads then, beside a voucher line (STv): the S$100 paid back, S$10
--     kept, 1 waits; so too beside a voucher line and a product whose S$40
--     was refunded by line since the reopening (the Refund in full leaves
--     it out: V4, V5); requested and approved with nothing changed between,
--     a package and a voucher line beside the sessions (Y1s: S$200 paid
--     back, 1 waits; the guided Cancel, Y3s) or a voucher line and that
--     product with the guided Cancel (V1s: S$100 paid back, cancelled, 1
--     waits); a S$100 Credit Package with the sessions and a S$40
--     product added by a correction, S$20 of the credit spent on another
--     invoice, cancelled, 1 session refunded by line, reopened, the Refund
--     in full (ACt) or Cancel (AGCt) requested and approved: not cut, the
--     S$160 offered paid back, the S$20 kept for the credit spent, 1 session
--     waiting; the product's S$40 refunded by line instead and S$20 paid
--     (AC, AGC): refused, exactly as 478 (NOT COVERED 17); beside two other
--     lines, one holding vouchers or credit, not cut, whichever line is
--     listed first: an Owner's discount (VTPd, CTPd), a package or the
--     Premium Bundle and a product (CTP, CTPc, BTP), a credit line written
--     first (CFR, BFC, BFR2): through, then paid 1 of 3; approved after
--     S$10 was paid, the other lines listed at S$0 (a S$100 Credit Package,
--     2 vouchers at S$30 and the sessions, the package's S$100, the vouchers
--     and 1 session refunded by line while cancelled; or the vouchers so and
--     a S$40 product refunded by line since the reopening), only the
--     sessions' line having anything to refund: the Refund in full (Z8, Z5r,
--     Z5x; KZ, S$5 paid before the request and S$5 after it; Z6, Correct
--     payment of S$5 to S$15) pays back the S$40, the rest kept, 1 session
--     waiting; the guided Cancel (Z8c, Z1, Z2): cancelled, the S$40 paid
--     back, S$10 shown due; with one S$0 line (Z9, Z0) or nothing changed
--     between (Z8s) the same, whichever line is listed first; the package's
--     credit all spent on a session S1 before the cancel and given back
--     between the request and the approval (S1 cancelled, its refund
--     recorded), with nothing paid between: the package's S$100 and the
--     sessions' S$40 paid back (ZGs, ZGsx); beside a S$40 product, S$40
--     paid back with no line and 1 session refunded by line while
--     cancelled, reopened, the S$40 paid again: the Refund in full or the
--     guided Cancel pays back the S$80 held, not cut (NL1, NL2, NL1c); after
--     the Refund in full, paid S$20: 1 of 3 (NL1p; NOT COVERED 17(a), 3 Nov
--     2026: these four in one transaction, each app call followed by what
--     its commit does); with another line on the invoice and the plan cut
--     to the money held, exactly as 478 (below);
--   * beside a Credit Package refunded by line (CPw: 2 sessions refunded,
--     paid: 1 of 3, S$100 of credit, S$120 net; CPr, Refund in full then
--     paid: 0 of 3, S$100 of credit; CPg: cancelled, all back), the Premium
--     Bundle (PBw: 2 of 3, S$140 and 2 vouchers), a package with a session
--     paid from it and a voucher line (MXw: 2 of 3, S$80 and 2 vouchers;
--     MXc: 3 of 3 after a second cycle), and the guided Refund in full beside
--     a voucher line (TV, TV2), the bundle (PBs) or a package (CPs): above;
--   * a customer change while it waits: an invoice with only the therapy
--     line (no 'transfer' or 'keep' asked) to B: B's at once, paid: B holds
--     3 (CTpg, as the invoice form sends it; CTw with 'transfer' sent; CTc
--     once cancelled again; CKn, 'keep' sent anyway: B, no choice being
--     asked; CNN B then C: C; CNb B then back to A: A; CTr, then refunded by
--     line: B 2 of 3); with a voucher line, 'keep' to B:
--     A keeps the sessions and the vouchers, the invoice is B's (CKv; CKc
--     cancelled again first); 'transfer' to B: B's (CTv); 'keep' to B then
--     'transfer' to C: C (CKT); 'keep' to B then 'keep' to C: A, the invoice
--     C's (CKK); 'keep' to B then the line's quantity changed: refused
--     (CKq); 'transfer' to B then 'keep' to C: B (CTK);
--     the Owner's case changed while it waits, then the guided Refund in
--     full and paid: 'keep' to B, A's (OWbk); 'transfer' to B, B's (OWbt).
--   Right before 479 and after it (exactly the same: controls, and what the
--   Owner kept): TH0, THc, THcc (a reopening paid; reopened straight to
--   paid; twice), RSr (a refund by line after a reopening was settled), RF0
--   (nothing held: refused for the money), CSw, CQw (a store or quantity
--   change while it waits: refused), PK, PVK, PRT (a customer change of a
--   paid invoice), CNCr (of a cancelled one, then reopened), THq, THmg
--   (475's), VQ and K5 (474's credit and voucher cases); the Owner's case
--   and its siblings (OWa, OWap, OWa2, OWac, OWa0, OWb, OWbp, OWb2, OWbc,
--   OWb0, OWpb, OWpbc, OWbm); GRF, GCF, CRF, VRF (nothing to refund), GRFk
--   (there the guided Cancel without "Record refund paid", then "Record
--   refund paid" with no line); KGn, KGnc, TVn, and TVn60, TVn60c, TVn20,
--   PRxr, PRx, PRnl, PRxc and VTPc, each run with its lines written both ways
--   and listed in either order on the copies (NOT COVERED 10: the Owner, 29
--   Oct 2026 ~18:45 SGT); STvp, and A1, AG, A1p, AN, A1x (NOT COVERED 16:
--   AC's with S$20 of credit given back to the package between the request
--   and the approval, the plan carried out cut; from 2 Nov 2026 each is
--   refused at the session's turn, its product line being offered again);
--   Y1 to Y4, V1 to V3 (NOT COVERED 16: approved after S$10 was paid, no
--   other line offering anything at the session's turn where the package or
--   the vouchers come first; the build of 2 Nov 2026, late, let Y1, Y3 and
--   V1 through in that order; each written in two or three line orders); ZG,
--   ZGx (NOT COVERED 16: ZGs's steps with S$10 paid between, the package
--   given its S$100 back between the request and the approval; that build
--   let ZG through with the package listed first);
--   AC, AGC, ACp, AXV, AVX, TPr, PTr (NOT COVERED 17: a product line
--   refunded by line before the reopening offered again, the plan reaching
--   a waiting session; AXV, AVX with 478's message in either line order);
--   KRdk, KRdp (NOT COVERED 14); VPR, PRxk, PRpp (NOT COVERED 1, a product
--   line); OWacR, OWpbcR, OWbcR (NOT COVERED 15); P1, P3, P4, P5, ACnC,
--   AGCnC, TP2c, and NL0 and BL1 (3 Nov 2026: at 486 and with 479 and 481,
--   in one transaction, as NL1) (NOT COVERED 17).
--
-- WHY THIS WAY
--
--   * The refund takes the sessions off what waits, as 446 does for voucher
--     units (the Owner's words): the payment then reinstates what still
--     waits. A removed row does not come back whole: 475's reopening queues
--     what a session shows less what waits, so a later reopening queues
--     again exactly what was refunded while it waited, which the reopening
--     charges again (RWc). Left on the queue, the payment would have given
--     back what was paid back.
--   * What stays refunded at settlement is read from the session's own
--     'refund' events since the invoice was last reopened (their created_at,
--     clock_timestamp(), after reopened_at, clock_timestamp()): the same
--     line the money follows (invoice_charge_total and the line's refunds,
--     r.created_at > reopened_at), no new column. So the evidence stays
--     exact: what waits plus what was refunded since is what the session
--     shows; a session queued twice before 475 (475's NOT COVERED 3) is
--     still refused. Only refund_invoice_therapy_sessions writes 'refund'
--     events and only reopen_invoice writes reopened_at (SAFETY checks both).
--   * The refund options are left as they are (the Owner, 29 Oct 2026,
--     "Keep today's result"): a session a refund by line paid back before
--     the reopening is not offered again by the guided flows, as credit and
--     voucher units a refund paid back are not (448), and money paid since
--     the reopening stays held for the waiting sessions until the invoice is
--     settled (which reinstates them) or cancelled (it is then shown due; on
--     an invoice that issued credit only a refund by line can record it as
--     paid back: NOT COVERED 15). Offering them again (this file's first
--     build) let invoice_action_plan cut the money held line by line in an
--     order that is not fixed: the session money refunded with the other
--     line's, the other line's money taken for the sessions (its benefits
--     then given by the payment instead of the sessions), or the approval
--     refused. Left as they are, where the sessions' money was paid back by
--     line before the reopening the plans offer only what each line still
--     holds from before it, so no cut is needed there (KG45, TV, PBs, CPs
--     and the Owner's case). Where money was paid back with no line, or a
--     product line was paid back before the reopening, the options offer it
--     again at its value and the cut remains, in the order the lines are
--     listed, as before 479. The refund by line is the explicit way: it may
--     take a waiting session the options do not offer, as far as money is
--     held (RF, OWak), and it is how staff refund item by item where a guided
--     flow is refused.
--   * There 478's refusal is kept (the Owner, 29 Oct 2026 ~18:45 SGT, "Keep
--     today's refusal"), in the refund itself: what 478 refused was the
--     refund (252's checks, at the session's turn in the approval), so
--     running those checks word for word there leaves the approval refused
--     with 478's message and nothing changed, whichever lines came before;
--     and the refund is the one function 479 already changes that a guided
--     flow reaches for the session. The guided flows themselves
--     (resolve_invoice_action_v2, invoice_action_plan, the refund options)
--     stay as 476 to 478 left them and as other files pin them. The refund
--     is not handed the plan the approval carries out, so it reads the plan
--     again at its turn: the refund has paid nothing back yet and the lines
--     it has not reached are as they were, so that reading tells whether the
--     plan was cut while another line had something to refund in every case
--     but one (two or more other lines, one holding credit, vouchers or
--     sessions the refund may already have reached; so too where none of
--     them offers anything at its turn, as a line the refund reached first
--     offers nothing then, and whether it was reached first follows the line
--     order: the build of 2 Nov 2026, late, took that reading as not cut,
--     which let Y1, Y3 and V1 through in one order only, the second fix
--     review, 3 Nov 2026). There the plan the
--     request saved is read: where it is not the plan carried out by what
--     can be compared, or says the plan was cut, 478's refusal is kept at
--     the session's turn; where it says not cut, it cannot show what a line
--     the refund reached before offered in the plan carried out (the
--     review of 2 Nov 2026: credit given back to a package between the
--     request and the approval, A1), so the plan carried out is checked
--     again once every line is done. Where it says, as the reading at the
--     session's turn does, that no other line offers anything, only the
--     session's line has anything to refund: nothing to choose between, and
--     no line order plays a part, so it goes on (answer F; the Owner's Q1
--     keeps it); the one thing that reading cannot see is a line given
--     credit or vouchers between the request and the approval and reached
--     before the session's, so where the saved plan is not the one carried
--     out the check once every line is done then allows no money for any
--     other line, which is what the saved plan refuses with that line
--     listed after the session's (ZG, ZGx: refused in either order, as 485).
--     Only then is it on record:
--     refund_invoice_recorded writes the lines it carried out, in its order
--     and with what each was given, before its last write of the invoice's
--     status, and this file's trigger runs at that write (the lines before
--     the session's gave all they offered; the rest offered at the session's
--     turn what they offer in the plan carried out). It asks whether the
--     plan was cut and another line had something, not where the cut fell,
--     so its answer does not follow the line order. Where the saved plan
--     differs from the plan carried out (NOT COVERED 16) it keeps 478's
--     refusal rather than guessing. (Since the fix review of 2 Nov 2026 A1
--     is refused before that, at the session's turn, its product line being
--     offered again; the check at the status write stays for a plan cut
--     another way, which no case found reaches, and from the third fix
--     review refuses there ZG and ZGc, money given to another line where only
--     the session's line had anything to refund: NOT COVERED 16.)
--   * Other readings, not taken: refusing every guided flow whose plan is cut
--     while a session waits (it would refuse KGn40, where only the therapy
--     line can be given anything: answer F's case, kept by the Owner); a
--     fixed order of the cut (another business rule: the Owner chose 478's
--     refusal); handing the plan to the refund through the guided flow (a
--     change of resolve_invoice_action_v2, which 417, 436, 438, 446, 448,
--     458, 470 to 472 and 477 pin as it is); working out at the session's
--     turn what the approval took from a line it reached before, from the
--     ledger, voucher and Audit Log rows written under the request (credit
--     or voucher units a cancellation held back are taken off without a row
--     of their own where no reopening queue holds them, so those rows can
--     say less than was taken, the wrong way for this check); refusing
--     wherever such a line was reached before the session's (it would
--     refuse TVP or VTP in one line order and not in the other); reading
--     the saved plan where only the session's line has anything to refund
--     and refusing wherever it is not the one carried out (the build of 3
--     Nov 2026: it refused answer F's cases, Z8 and the others, wherever two
--     or more other lines were listed at S$0, one a credit or voucher line,
--     and a payment came between, though nothing could be cut and no line
--     order played a part, and let the same through with one S$0 line);
--     letting that case through with no check at
--     the end (the build of 2 Nov 2026, late: a line given credit between
--     the request and the approval went through when reached first and was
--     refused when listed after the session's, ZG and ZGx).
--   * A line holding no credit, vouchers or sessions (a product) that a
--     refund by line paid back before the last reopening and that the plan
--     gives money again (the fix review of 2 Nov 2026): refused at the
--     session's turn as 478 refuses it, rather than refunded again, because
--     whether such a line may be refunded a second time is the Owner's open
--     question (NOT COVERED 17), and 478 never refunds it again in a plan
--     that reaches a waiting session. The test reads what the plan offers
--     that line at the session's turn and the line's refunds before the
--     reopening, neither of which the approval changes before every line is
--     done, so it gives the same answer in every line order (AC and AGC in
--     six orders each, AXV and AVX, TPr and PTr). It also refuses, as 478
--     does, AC's shape where the plan is not cut (the money the plan pays
--     the product again is money held for the credit spent on S1), which the
--     cut rule above cannot see. Other readings, not taken: refusing only
--     where the line's money was not paid again since (TP2c: the product
--     refunded by line before an earlier reopening, then charged and paid
--     in full; refused here though nothing would be refunded twice: which
--     refunds a later payment covers is the Owner's rule to set); valuing
--     the line at what was paid towards it since the reopening (a money
--     rule, one of NOT COVERED 17's options for the Owner).
--   * The waiting session follows 460's rule (invoice_credit_live_holder,
--     as 462 reads it for credit), not the invoice's customer: 'keep' keeps
--     it, 'transfer' and a merge move it, the latest change wins. In place:
--     a session cannot be closed and given again while it waits (what waits
--     names it, and its refunds since the reopening are its events). At every
--     status write, so it is right the moment the correction ends, and again
--     at the payment (a merge since).
--   * An invoice that sold only therapy sessions asks no 'transfer' or
--     'keep' (the page asks only when invoice_transferable_benefits lists
--     something), and on a paid invoice its sessions follow a customer
--     change; the waiting ones do the same. Written as 460's row so the rule
--     has one input (and a later change wins).
--   * A 'keep' leaves the session with a holder who is not the invoice's
--     customer: a state no function made before. The correction's test
--     compared the session's customer with the correction's, so the next
--     correction of any kind (the notes) would have closed the session and
--     given the invoice's customer new sessions. Now it compares with the
--     invoice's customer; what would still give them away is refused rather
--     than decided here (NOT COVERED 3).
--   * Other ways, not taken: a column on the queue for what was refunded
--     while waiting (a table change; the events already say it); keeping
--     the rows and reinstating less at settlement (the queue would then not
--     say what the payment gives, and the Owner asked for the sessions to
--     come off it); closing and replacing a waiting session on a customer
--     change (its rows and its refunds since the reopening would have to
--     move to the new record; 252's evidence would no longer find them);
--     offering in the refund options the sessions refunded before the
--     reopening as far as money was paid towards them since (the Owner's
--     case would then refund S$20 of OWa's S$30, not keep it).
--
-- NOT CHANGED
--
--   * Pinned (below), unchanged: reopen_invoice (475's AFTER: what a
--     reopening queues), the Reopen dialog's preview (invoice_reopen_preview,
--     478's invoice_reopen_preview_before_sessions), refund_invoice_recorded
--     (446's; it calls the refund and checks the line's money),
--     correct_invoice (it calls the correction's step, asks 'transfer' or
--     'keep', moves the benefits, then writes the status),
--     invoice_refund_options (what the Finance panel shows and the guided
--     plans offer: as 438, 448 and 477 pinned it; kept, the Owner, 29 Oct
--     2026), invoice_action_plan, request_invoice_action_v2 and
--     resolve_invoice_action_v2 (the guided flows), cancel_invoice_recorded,
--     create_therapy_sessions_for_invoice, 460's and 462's holder rule,
--     476's invoice_transferable_benefits and
--     move_invoice_benefits_to_customer, merge_customer_records,
--     invoice_refund_options_before_sessions, invoice_charge_total,
--     invoice_discounted_line_value (a line's value: what it offers, as the
--     plan works it out; the refund reads it in a guided flow). Read, not
--     changed: the guided request (approval_requests: its status, invoice,
--     kind, action, lines and saved plan) and which lines hold credit or
--     vouchers (invoice_benefit_values).
--   * The money, the plans' codes and amounts (the refund options as they
--     are), the credit and voucher queues, the commissions, stock, Edge
--     Functions, settings.
--   * Pages: none. The Finance panel shows the refund options' "unused
--     session(s)" and "up to" as before (NOT COVERED 13); the guided flows
--     show the plans; the invoice form sends what it sent. The Audit Log page
--     shows the new actions as 'reopen session refunded' and 'reopen
--     sessions follow holder' (it has no label map).
--
-- NOT COVERED (for the Owner; the suite checks 1, 2, 3, 7, 10, 13, 14, 15,
-- 16 and 17 as they are and prints them as KNOWN; 4 is its cases CTpg, CTw
-- and CKn; no case reaches 5, 6, 8 or 9; 11 and 12 are 476's NOT COVERED 13
-- and 14; the Owner, 29 Oct 2026: 1, 3, 6, 11 and 12 stay documented,
-- unchanged; ~18:45 SGT: 10 answered and built here, 1's product stock to
-- be fixed separately (481), 14 and 15 stay documented, unchanged; 16 and 17
-- are new, 30 Oct 2026, not yet put to the Owner; 16 corrected 2 Nov 2026,
-- 16 and 17 again after the fix review of 2 Nov 2026, 16 again after the
-- second fix review, 3 Nov 2026)
--
--   1. A guided Refund in full of a reopened invoice still waiting (GR,
--      KG45, TV) pays back the money its plan offers and takes those
--      sessions off the queue, but the invoice stays part-paid for what the
--      reopening charges and no payment covers (GR: S$20 to pay, 1 session
--      waiting for it): the same as for credit and vouchers since 446
--      (Refund in full while a package's credit or a voucher waits:
--      part-paid, S$0 held). Paid, it gives what that payment buys (GRp: 1
--      of 3 for S$20); Cancel closes it. Whether a Refund in full of a
--      reopened invoice should also close it: the Owner, 29 Oct 2026, stays
--      as it is. Not so where a product line is on the invoice (not caused by
--      479; the review of 29 Oct 2026): the payment that settles the invoice
--      also takes the product from stock again (a second store_sale) though
--      its line was refunded. ensure_invoice_stock_deducted
--      (invoice_required_stock less invoice_product_net_deducted) deducts the
--      line's full quantity less what was sold and not returned; a Cancel
--      returns the stock, a refund by line after it records none (nothing is
--      left unresolved), and a refund changes neither figure. So the customer
--      holds the product without paying for it, and no stock report flags it
--      (invoice_stock_to_deduct and invoice_stock_gaps see nothing). Before
--      479 already, with no waiting session: a S$40 product and 2 vouchers,
--      cancelled, 1 voucher refunded by line, reopened, the guided Refund in
--      full (the product's S$40, the voucher's S$30), paid S$30: 1 voucher
--      and the product (VPR; a S$100 Credit Package instead, S$50 of it
--      refunded by line while cancelled: S$50 of credit and the product for
--      S$50, CPR on the copies); a product and 3 sessions, the product refunded
--      by line while cancelled and again after the reopening, paid S$40: 3
--      sessions and the product for S$60 (PRxk); a part-paid invoice never
--      reopened, the product refunded by line, the rest paid: 2 vouchers and
--      the product for S$60 (PRpp). 479 adds routes, its guided Refund in
--      full going through where 478 refused it: the product and 3 sessions,
--      cancelled, 1 session refunded by line, reopened, Refund in full (the
--      product's S$40 and 2 sessions, either line first), paid S$20: 1 of 3
--      and the product for S$20 (PRn1, PRn2; before 479 the Refund in full
--      was refused and the payment gave 3 of 3 for S$100). (The previous
--      build added NOT COVERED 10's product-first order too, PRx1 and PRnl1;
--      this build refuses those, as 478 does.) Beside a voucher line or a
--      credit line too, the plan not cut, whichever line is listed first
--      (VTPd, CTPd, CTP, BTP, CFR: 1 session refunded by line while
--      cancelled, reopened, the guided Refund in full, which refunds the
--      product's line, then paid: 1 of 3 and the product taken again). The
--      guided flows also refund again a product line refunded before the
--      reopening where their plan gives no waiting session money (NOT
--      COVERED 17; where it gives one money they are refused as 478, but
--      where it was paid back with no line and all of it paid again: NOT
--      COVERED 17(a)).
--      The Owner, 29 Oct 2026 ~18:45 SGT, "Fix it separately": a new
--      migration, 481, after this one (not in this file), makes the payment
--      that settles a reopened invoice, and by the same rule a part-paid
--      invoice settled later, take from stock only what was not refunded by
--      line since the sale or the last reopening (its cases from the review
--      of 29 Oct 2026: VPR, CPR, PRxk, PRpp, PRn1, PRn2, and PRpd,
--      invoice_stock_to_deduct reporting 1 unit for a product refunded by
--      line with its stock returned; NOT COVERED 17's P1a, P3, P4a, P5a).
--   2. On a paid invoice (nothing waiting) a customer change still closes
--      the sessions and gives the new customer the line's sessions as new,
--      whatever the choice ('keep' too: PK, PVK), and a session refunded by
--      line before comes back (PRT: S$20 of S$60 refunded, the change gave
--      B 3 of 3 for S$40 net). Before 479 and after it; not touched.
--   3. Sessions a 'keep' left with their holder while they waited: once the
--      invoice is settled (paid), a later correction that would change their
--      line, quantity or store, or move the invoice to a third customer, is
--      refused (KK1); the Owner may want such a correction to keep them with
--      their holder, or to move them (29 Oct 2026: stays documented,
--      unchanged). While they still wait, a move of the invoice to another
--      customer goes through and they follow 460's rule ('keep': they stay
--      with their holder, CKK; 'transfer', or no choice asked: the new
--      customer, CKT), and a change of their line, quantity or store is
--      refused, as for any waiting session, "Settle the pending session
--      reopening before changing its allocation" (CKq). Their refund by line
--      (KKs), a Cancel and a reopening (KK3) work, from whoever holds them.
--   4. An invoice that sold only therapy sessions asks no 'transfer' or
--      'keep'; its waiting sessions follow a customer change, as its paid
--      sessions do (CKn: 'keep' sent anyway). The page offers no choice
--      there; if the Owner wants one, the page and invoice_transferable_
--      benefits would list waiting sessions.
--   5. A customer change of an invoice whose waiting session has sessions
--      used is refused, 'keep' too ("Used therapy sessions must keep their
--      original customer, service and invoice allocation", as on a paid
--      invoice). No function records a session used today (nothing updates
--      quantity_used), so it is not reached.
--   6. The review summary (preview_invoice_correction), the Reopen dialog
--      and the Pay dialog do not name who receives the waiting sessions
--      (478's receiver note covers credit and vouchers; 476's Pay dialog
--      note credit: 12). 29 Oct 2026: stays documented, unchanged.
--   7. 475's NOT COVERED 3 (a session queued twice before 475): still
--      refused at payment; its refund by line and customer change are now
--      refused as "Therapy session reopening changed; reload its original
--      evidence" (Kdup, Kdupc; before: the refund's "Settle the reopened
--      invoice before changing its queued sessions", the change's "Settle
--      the pending session reopening before changing its allocation"). 475's
--      NOT COVERED 4 (a waiting row lowered by hand, no function does it): the
--      payment now sums the session's rows, so once a later reopening has
--      queued the difference the payment settles it (before: refused), and
--      without one it is still refused.
--   8. Therapy bought through therapy packages and promotions
--      (purchased_therapy_entitlements, 359) is not queued by a reopening
--      (475's NOT COVERED 5); not examined.
--   9. A refund, change or payment still open when 479 commits finishes on
--      the text it started with (the 252 refusals; the old settlement). A
--      guided Cancel or Refund in full requested before 479 keeps its plan:
--      479 changes no plan (the refund options as they are); its approval
--      then refunds the waiting session through 479's refund, where before
--      it was refused.
--   10. Line order (answered, the Owner, 29 Oct 2026 ~18:45 SGT, "Keep
--      today's refusal"; built here). Where a plan offers more than the money
--      held, invoice_action_plan (pinned, unchanged) cuts it to the money held
--      line by line, in the order the refund options list the lines (as the
--      table returns them: not fixed; on the copies the same steps listed
--      them in either order). That order follows the plan Postgres picks:
--      invoice_refund_options_before_sessions builds its 'lines' with
--      jsonb_agg and no ORDER BY over invoice_items joined to products,
--      promotions and vouchers; invoice_refund_options hands them on
--      unchanged; invoice_action_plan works through them in that order and
--      lists its plan in it (the plan's hash covers it, so a request whose
--      plan was saved in another order asks the approver to confirm the plan
--      again); request_invoice_action_v2 saves that plan;
--      resolve_invoice_action_v2 builds the refund's lines from the plan as
--      it reads at the approval, in its order; refund_invoice_recorded
--      carries them out in that order (calling this file's refund at the
--      therapy line's turn) and records them in it (invoice_refunds' lines,
--      which this file's check at the refund's status write reads). None of
--      these is changed here (476 to 478 and other files pin them as they
--      are), nor is their order: which line a cut plan pays first stays the
--      Owner's rule as 478 has it. With hash and merge joins off the copies
--      listed most invoices' lines in the order they were written; with
--      nested loops off, often in another; production may list them in
--      either, and a session keeps its plan until the tables' figures
--      change. This file decides nothing by that order that 478 did not: run
--      each app call committed on copies at 485 and with 479 and 481, in the
--      orders the copies gave by default, with hash and merge joins off and
--      over several runs, every case ends with one outcome for a given line
--      order, the same as at 485 wherever the case is not one 479 or 481
--      changes on purpose, and no invoice's outcome follows the line order
--      with them where it did not at 485 (2 Nov 2026; the second fix review,
--      3 Nov 2026, found three that did with the build of 2 Nov 2026 (late),
--      requests approved after the invoice changed where no other line
--      offered anything at the session's turn: Y1, Y3, V1, NOT COVERED 16,
--      and the third fix review, 3 Nov 2026, another with it: a credit line
--      given credit between the request and the approval, ZG, ZGc; this
--      build refuses them in every order, as 485, and lets the cases where
--      only the session's line has anything to refund through in every
--      order, Z8 and the others, NOT COVERED 16; its cases, re-run so, show
--      no other; that is as far as the cases run go). The plans offer
--      what each line holds from
--      before the reopening (the refund options, as they are), so this
--      happens where a line's money was paid back before the reopening
--      without a refund by line the options count, and part of it was paid
--      again: (a) "Record refund paid" with no line after a Cancel (the
--      sessions show as cancelled, so they are offered again at their value,
--      and so are the vouchers); (b) a product line paid back before the
--      reopening, by line or with no line (its 'remaining' counts only
--      refunds since the reopening; NOT COVERED 17). (The Owner's case is not
--      one: its sessions were refunded by line, so its plans give the therapy
--      line S$0 in either order, OWb, OWb2.) As 478, from this build: where
--      the cut gives the waiting sessions some of the money while another
--      line has something to refund, the approval is refused, changing
--      nothing, with 478's own message, whichever line is listed first ("Settle
--      the reopened invoice before changing its queued sessions", or, where
--      the sessions' share is not whole sessions, "Refund whole unused therapy
--      sessions at their original paid value; % of % sessions remain
--      refundable"): 3 sessions and 2 vouchers at S$30, cancelled, all S$120
--      paid back with no line, reopened, S$60 paid, the guided Refund in full
--      or Cancel with the therapy line first (TVn60, TVn60c); S$20 paid
--      (TVn20); a S$40 product and 3 sessions, the product's S$40 refunded by
--      line (or paid back with no line) while cancelled, reopened, either line
--      first (PRxr, PRx, PRnl, PRxc: so the product is not refunded a second
--      time there, as the previous build did with the product first); the
--      vouchers, the sessions and the product all paid back with no line,
--      S$130 of S$160 paid again (VTPc, in either order). The previous build
--      refunded TVn60, TVn60c and TVn20 with the therapy line first and PRxr,
--      PRx, PRnl and PRxc in either order (each app call committed, on the
--      copies). Where the cut gives the
--      sessions nothing (the voucher line first: TVn60b, TVn60cb, TVn20b; the
--      product first with its S$40 taking all the money held: P4a), the refund
--      is not reached and the plan goes through or is refused as before 479,
--      which line it refunds following the order as at 478 (as on an invoice
--      with no sessions: P1, P5; NOT COVERED 17). With only the therapy line
--      there is no other item to choose between and the plan's whole sessions
--      go through, as answer F asked (KGn40: S$40 paid again on 3 sessions at
--      S$20 paid back with no line, 2 sessions; kept as built, the Owner, 29
--      Oct 2026 ~18:45); where its cut is not whole sessions the approval
--      refuses, as before 479 (KGn, KGnc: S$30, "3 of 3 sessions remain
--      refundable"); with a S$60 voucher line and S$50 paid (TVn), refused by
--      the sessions' rule or the vouchers', by the line first, as before 479.
--      The same rule for every guided flow that reaches the refund (the
--      guided part refund too, its plan being cut the same way) and for a
--      second therapy line as for any other line (two waiting therapy lines
--      in one cut plan: refused, as 478). In the app the request made by
--      request_invoice_action_v2 stays pending after a refused approval, until
--      someone rejects it; staff then refund item by item (refunds by line in
--      whole units), or use the guided Cancel with "Record refund paid" not
--      ticked and then "Record refund paid" with no line (not on an invoice
--      that issued credit: NOT COVERED 15). Where the refund cannot tell from
--      the invoice whether the plan carried out was cut: NOT COVERED 16.
--   11. 476's NOT COVERED 13 (not caused by 479): a package line added by a
--      correction to an invoice paid in full releases credit for money that
--      paid for lines already delivered; while sessions wait, a refund by
--      line of the therapy line lowers the money held and does not trim
--      that credit (as on a paid invoice: trg_create_therapy_on_paid skips
--      the trim where a refund is recorded in the same transaction). 29 Oct
--      2026: stays documented, unchanged.
--   12. 476's NOT COVERED 14: the Pay dialog names who receives the credit
--      a reopened invoice gives back, not the waiting sessions or voucher
--      units its settling payment reinstates (after a 'keep' change while
--      they wait: the holder). 29 Oct 2026: stays documented, unchanged.
--   13. Sessions a refund by line paid back before the reopening, with money
--      paid towards them since, on an invoice that sells only them (GRF, GCF: 3
--      sessions refunded in full, reopened, S$20 paid): the guided Refund in
--      full finds nothing to refund ("There is nothing left to refund on
--      this invoice") and the guided Cancel with "Record refund paid" no
--      money to return ("There is no money held on this invoice to
--      return"), as before 479 and as for a Credit Package or vouchers in
--      that state (CRF, VRF). The S$20 stays held. The refund by line of it
--      goes through (RF: 1 session off the queue; paid, 2 of 3 for S$40), and
--      so do the guided Cancel with "Record refund paid" not ticked and then
--      "Record refund paid" with no line (GRFk: cancelled, S$20 shown due and
--      paid back; reopened and paid S$60: 3 of 3). There the Finance panel's
--      sessions note reads "0 unused session(s) ... up to S$0.00" (the refund
--      options), while the line's own "up to" is S$60 and the refund by line
--      goes through. This file's first build refunded the S$20 by the guided
--      flows (it changed the refund options for that); the Owner's answer of
--      29 Oct 2026 keeps today's result where another line is on the
--      invoice and was not asked about this case, where it is kept too.
--   14. Half a cent. 479's refund values the sessions refunded since the
--      reopening counting from those refunded since (the line is charged
--      again), while the money held for the waiting sessions is what the
--      refunds before the reopening left; where a session's paid value
--      splits on half a cent the two differ by S$0.01 (KRd: 4 sessions at
--      S$20 with an Owner's S$0.01 discount, S$79.99; 2 refunded by line
--      while cancelled, S$40.00; reopened, S$39.99 held for the other 2).
--      Then the guided Refund in full's S$39.99 is refused ("Refund whole
--      unused therapy sessions at their original paid value; 4 of 4 sessions
--      remain refundable") and so is the guided Cancel's (KRdc); by line, 1
--      session at S$20.00 goes through, and the last one, valued at S$20.00
--      while S$19.99 is held, does not: S$20.00 is refused as "Refund exceeds
--      net payments still held" (KRd1), S$19.99 as "Refund whole unused
--      therapy sessions at their original paid value; 3 of 4 sessions remain
--      refundable" (KRd2). Before 479 these refunds were refused too (252).
--      So here the guided flows are refused though the refund options count
--      the plan's S$39.99 as 2 whole sessions. Paid, the invoice settles
--      (KRdp: 4 of 4 for S$79.99); the guided Cancel with "Record refund
--      paid" not ticked, then "Record refund paid" with no line, pays the
--      S$39.99 back (KRdk). This file's first build the same. A fix (valuing
--      the sessions cancelled with their money held as the refunds before
--      the reopening left them) would be a money rule; the Owner, 29 Oct
--      2026 ~18:45 SGT (Q4): leave it documented, unchanged.
--   15. Money a Cancel leaves due on a reopened invoice that issued credit (a
--      Credit Package or Premium Bundle line) cannot be recorded as paid back
--      with no line (not caused by 479; the review of 29 Oct 2026). "Record
--      refund paid" with no line is refused once the invoice issued credit
--      ("Allocate a correction refund to the original unused purchased
--      benefits; it cannot be cashed out as an unallocated overpayment"), and
--      the package line has nothing left, so only the therapy line can take
--      it, by line, in whole sessions: before 479 none (its sessions count as
--      refunded, or it is refused while they wait). The Owner's case (OWac:
--      the guided Cancel pays back the S$100, S$30 shown due): before 479 the
--      S$30 stays due (OWacR); from 479 S$20 of it goes back by line and S$10
--      stays due (OWac20R; S$30 is refused, 1.5 sessions). 1 session refunded
--      while cancelled, reopened, S$5 paid: the guided Cancel with "Record
--      refund paid", refused before 479, now goes through and leaves S$5 due
--      that nothing records (CPs5); the plain Cancel and the package by line
--      left S$45 before 479, S$5 from 479 (CPs5k). The Premium Bundle the
--      same (OWpbcR, S$20 due), one session by line clearing it from 479
--      (OWpbc20). With vouchers instead "Record refund paid" with no line
--      records it (OWbcR), and with only the therapy line (KG45c, GRFk,
--      KRdk). Ways out: reopening and paying in full; or, from 479,
--      reopening, recording more money, refunding whole sessions by line,
--      then Cancel. A fix (letting "Record refund paid" return money no line
--      can take on a cancelled invoice that issued credit, or a part-session
--      refund) would be a money rule; the Owner, 29 Oct 2026 ~18:45 SGT (Q3):
--      leave it documented, unchanged.
--   16. A guided request approved after the invoice changed (a payment, a
--      refund or a correction between the request and the approval, the
--      approver confirming the plan as it reads then), where the plan lists
--      at least two lines besides the waiting session's, one of which holds
--      credit, vouchers or sessions, and is not cut as it reads at the
--      session's turn: there the refund cannot tell from the invoice alone
--      whether the plan carried out was cut (a line the refund reached before
--      the session's shows less than it offered). Where the plan the request
--      saved is not the one carried out by what can be compared (its money
--      held, its lines, the session line's amount and offer, or what a line
--      holding no credit, vouchers or sessions offers differ), or says the
--      plan was cut, the session is refused as 478 refuses it, whichever line
--      is listed first. STvp: a voucher line and a product beside the
--      sessions, 1 session refunded by line while cancelled, reopened, the
--      Refund in full requested (its plan S$140 of S$140 held), S$10 paid,
--      approved: "Settle the reopened invoice before changing its queued
--      sessions", S$150 held, the 3 sessions waiting, though the plan carried
--      out (S$140 of S$150) is not cut. With one other line, or none holding
--      credit, vouchers or sessions, the refund reads the plan carried out
--      exactly and goes through as answer F asked (STv: a voucher line, S$100
--      paid back, S$10 kept). The same holds where no other line offers
--      anything at the session's turn (the second fix review, 3 Nov 2026):
--      the build of 2 Nov 2026 (late) took the plan as not cut there without
--      reading the saved plan, and a line holding credit, vouchers or
--      sessions that the refund reached first offers nothing by then, so the
--      approval went
--      through with such lines listed before the sessions' and was refused
--      otherwise (Y1: a S$100 Credit Package, then 2 vouchers at S$30 and the
--      sessions added by a correction, paid S$220, cancelled, 1 session
--      refunded by line, reopened, S$200 held, the Refund in full requested,
--      S$10 paid, approved: with the package and the vouchers listed first
--      S$200 paid back, S$10 kept, 1 waiting; with the sessions listed
--      first, refused; Y3 the guided Cancel; V1: a voucher line, the sessions
--      and a S$40 product refunded by line since the reopening, the guided
--      Cancel, S$110 held). The builds since read the saved plan there too,
--      so each is refused as 485 refuses it, every key, whichever line is
--      listed first (Y1 to Y4, V1 to V3: S$210 or S$110 held, 3 waiting).
--      This item does not hold where only the session's line has anything to
--      refund: no other line offers anything at its turn and none offered
--      anything in the saved plan (compared by item; the other lines listed
--      at S$0: a credit or voucher line refunded by line before the
--      reopening, a product line refunded by line since it in a guided
--      Cancel). Nothing is left to choose between and nothing can be cut, so
--      it goes through as answer F asked, whichever line is listed first (the
--      third fix review, 3 Nov 2026; the build of 3 Nov 2026 read the saved
--      plan there and refused it wherever two or more other lines were listed
--      at S$0, one a credit or voucher line, and anything changed between the
--      request and the approval, though the same with one S$0 line went
--      through: Z9, Z0). Z8: a S$100 Credit
--      Package, then 2 vouchers at S$30 and the sessions added by a
--      correction, paid, cancelled, the package's S$100, the vouchers and 1
--      session refunded by line, reopened (S$40 held), the Refund in full
--      requested, S$10 paid, approved: S$40 paid back, S$10 kept, 1 waiting
--      (Z8c, the guided Cancel: cancelled, S$10 shown due; Z5r, Z5x sold
--      together; KZ, Z6; Z1, Z2: vouchers refunded by line while cancelled
--      and a S$40 product since the reopening, the guided Cancel). There the
--      refund cannot see a line given credit or vouchers between the request
--      and the approval and reached before the session's (it shows nothing by
--      then), so the check once every line is done allows, where the saved
--      plan is not the one carried out by what can be compared, no money for
--      any other line: ZG (the package's S$100 spent on a session S1 before
--      the cancel, so the saved plan gives it S$0; S1 cancelled and its refund
--      recorded after the request; S$10 paid; the package listed first) is
--      refused there with 478's message, and ZGx (the sessions listed first)
--      at the session's turn by the saved plan: both as at 485, every key
--      (the build of 2 Nov 2026, late, let ZG through, the package's S$100 and
--      the sessions' S$40 paid back, and refused ZGx); with nothing paid
--      between (ZGs, ZGsx)
--      the saved plan is the one carried out by what can be compared and both
--      go through. For the Owner, with this item: on one state the guided
--      Cancel and the guided Refund in full can end differently here. A
--      product line refunded by line since the reopening has nothing left
--      ('remaining' S$0): invoice_action_plan keeps it, at S$0, for a Cancel
--      and leaves it out of a Refund in full (a credit or voucher line
--      refunded by line before the reopening is charged again by the
--      reopening, so both list it at S$0). So with V1's state (the vouchers
--      offering S$60 in the saved plan) the guided Cancel lists two other
--      lines and the saved plan is read: the guided Cancel requested, S$10
--      paid, approved: refused, S$110 held, 3 waiting. The guided Refund in
--      full of the same state lists one other line, so the refund reads the
--      plan carried out exactly and it goes through as answer F asked (V4,
--      V5: S$100 paid back, S$10 kept, 1 waiting). Neither result follows the
--      line order; which one applies follows the flow staff chose. (With the
--      vouchers refunded by line too, every other line S$0, both go through:
--      Z1, and Z1r on the copies.) With nothing changed between the request
--      and the approval both go through (V1s, the guided Cancel: S$100 paid
--      back, cancelled, 1 waiting; Y1s, Y3s). Where the saved plan says not
--      cut, the refund goes on and the plan carried out is checked again
--      once every line is
--      done (WHAT THIS DOES, the trigger's (d)), and refused there with 478's
--      message where it was cut. The review of 2 Nov 2026 found that case let
--      through by a build before (its saved plan never compared what a line
--      holding credit, vouchers or sessions offered): a S$100 Credit Package
--      written first, the sessions and a S$40 product added by a correction
--      (so the refund options list the package, the sessions, the product),
--      S$20 of the credit spent on another invoice, cancelled, the product's
--      S$40 refunded by line, reopened, S$20 paid (S$180 held), the Refund in
--      full requested (its plan: the package's S$80, the sessions' S$60, the
--      product's S$40, not cut), the other invoice cancelled and its refund
--      recorded (the S$20 of credit back, held for the package), then
--      approved as it reads then (the package's S$100: cut, the product given
--      S$20): that build refunded the 3 waiting sessions and S$20 of the
--      product (A1; the guided Cancel with "Record refund paid", AG:
--      cancelled, everything paid back); the next refused both as 478 does,
--      once every line was done; this build (the fix review, 2 Nov 2026)
--      refuses them at the session's turn, their product line, refunded by
--      line before the reopening, being offered again (NOT COVERED 17):
--      every key as at 485 ("Settle the reopened invoice ...", S$180 held, 3
--      waiting), each app call committed on copies of production at 485 and
--      in the suite. Refused as 478 already: the request raised after the
--      credit came back (AN: the saved plan cut), the product added before
--      the sessions (A1p: the sessions' line cut), the three lines sold
--      together (A1x: the package listed last). With no credit given back
--      (AC, AGC) the plan is not cut, but the product's line is offered
--      again: refused as 478 (NOT COVERED 17; the build before let them
--      through and its suite called that answer F's result: it was not).
--      Still open: where the saved plan is not the one carried out but the
--      plan carried out is not cut (STvp; Y1 to Y4, V1 to V3; ZG, ZGx), 478's
--      refusal is kept though answer F would let it through (not where only
--      the session's line has anything to refund and no other line was given
--      money: Z8 and the others above go through). And a refusal once every
--      line is done
--      shows the message of the line that refuses first, which may not be
--      478's: the fix review reached it with the app's own calls (AXV: AC's
--      steps with 2 vouchers at S$30 added after the product and the spent
--      credit given back between the request and the approval: the plan
--      carried out, the package's S$100, the sessions' S$60, the product's
--      S$40 and the vouchers' S$40, cut the vouchers to part of a unit, and
--      the build before refused it with "Voucher refund must cover whole
--      unused units at their allocated paid value" where 485 says "Settle
--      the reopened invoice ...", with the vouchers added before the product
--      (AVX) with 478's message, every other key the same: no money or stock
--      moved), where this item had said no case reaches it. This build
--      refuses both at the session's turn with 478's message, in either line
--      order (their product line being offered again: NOT COVERED 17). No
--      plan found carried out cut reaches a refusal once every line is done
--      now (what is refused there is ZG and ZGc, above, with 478's message:
--      money given to another line where only the session's line had
--      anything to refund and the saved plan is not the one carried out): a
--      plan carried out can be cut there only where a line is offered again for
--      money paid back before the reopening; on an invoice that issued
--      credit only a refund by line of a line holding no credit, vouchers or
--      sessions does that ("Record refund paid" with no line is refused
--      there), which the session's turn now refuses; on one with no credit
--      line it would take money paid back with no line and a voucher unit
--      given back to the customer between the request and the approval (not
--      built as a case). There the message may still be another line's
--      (changing nothing all the same): for the Owner with this item. What
--      works where the saved plan differs: rejecting the request and raising
--      it again (its plan saved as it reads then), or refunds by line. For
--      the Owner (open): keep 478's refusal where the saved plan differs; or
--      a change of the guided flow (resolve_invoice_action_v2) that hands the
--      refund the plan it carries out.
--   17. A product line refunded before the reopening is offered again by
--      the guided flows, and refunded a second time where the plan gives it
--      money (open for the Owner, not 479's to decide; found checking this
--      file's build of 30 Oct 2026, each app call committed on copies of
--      production at 478, with the build before and with that one, each
--      shape in both line orders; and in the fix review of 2 Nov 2026). The
--      reopening charges the line again and the refund options count only
--      the line's refunds since the reopening, so the guided Refund in full
--      and Cancel offer the product again at its value, whether it was paid
--      back before the reopening by line or with no line.
--      (a) Where the plan gives a waiting session money, 478 refuses the
--      approval at the session's turn. This file's earlier builds let some
--      of these through: plans cut to the money held (NOT COVERED 10: PRxr,
--      PRx, PRnl, PRxc with the product first: S$80 on its S$40 line) and,
--      until this build, plans not cut (the fix review's AC and AGC, their
--      money in WHO FOUND IT: all S$220 paid back with S1, a S$20 session,
--      kept; and, checking it, TPr, PTr: the sessions, 1 refunded by line
--      while cancelled, and the product refunded by line, reopened, S$40
--      paid again: the product's S$40 again and 2 sessions paid back, then
--      paid S$20: 1 of 3; AXVn, AVXn with a voucher line). From 2 Nov 2026
--      this file refuses the session as 478 does wherever the plan gives
--      money to a line holding no credit, vouchers or sessions that a refund
--      by line paid back before the last reopening, whichever line is listed
--      first: each of these ends exactly as at 485, every key. It refuses too
--      where the product was charged and paid again since that refund (TP2c:
--      the product refunded by line while cancelled, reopened and paid in
--      full, cancelled again, 1 session refunded by line, reopened again:
--      the guided Refund in full, the sessions' S$40 and the product's S$40,
--      is the S$80 held and would refund nothing twice; refused as at 485).
--      Paid back with no line instead ("Record refund paid"), the money is
--      not held until it is paid again. While less than all of it is paid
--      again since the reopening, the plan is cut and the cut rule
--      refuses it as 478 (PRnl; NL0, nothing paid again). With all of it
--      paid again, the plan is not cut and no refund by line paid the
--      product back before the reopening, so neither rule applies: the
--      guided Refund in full and Cancel go through where 486 refuses them
--      (found by the final checks, 3 Nov 2026, on copies at 486 and with
--      479 and 481, in the 481 suite's harness: one transaction, each app
--      call followed by what its commit does). A S$40 product and
--      3 sessions at S$20, paid S$100, cancelled, S$40 paid back with no line
--      and 1 session refunded by line, reopened, the S$40 paid again (S$80
--      held): the plan (the product's S$40, 2 sessions' S$40) is the S$80
--      held. The Refund in full pays it back: net S$0, 1 session waiting for
--      the S$20 the invoice is still part-paid for (NL1; the product written
--      first, the same: NL2); then paid S$20: 1 of 3 sessions for S$20, and
--      with 481 the product is not taken again (NL1p). The guided Cancel:
--      cancelled, net S$0 (NL1c). Nothing is paid back twice and the line
--      order plays no part. At 486 each is refused ("Settle the reopened
--      invoice before changing its queued sessions"). With the product's S$40
--      refunded by line instead it stays refused, as at 486 (BL1: the first
--      rule). No answer of the Owner's decides NL1, NL2 and NL1c: whether
--      such a product may be offered again is this item's open question, as
--      for TP2c (refused, though it refunds nothing twice). For the Owner to
--      confirm: keep them, or refuse them as TP2c is.
--      (b) Where the plan gives no waiting session money (478's own, kept:
--      the same before 479 and after it), its line is refunded again,
--      against its second charge. The sessions all refunded by line while
--      cancelled (they offer nothing), the product's S$40 refunded by line,
--      reopened, S$40 paid, the Refund in full pays back the product's S$40
--      again (S$80 in all on its S$40 line), then paid S$60: 3 of 3 and the
--      product (P3, either line first). With a voucher line, the product's
--      S$40 refunded by line while cancelled, reopened, S$10 paid, the plan
--      (the product's S$40, the vouchers' S$60) is cut to the S$70 held: the
--      product first, its S$40 again and 1 voucher, then paid S$30: the other
--      voucher and the product (P1a); the voucher line first, the 2 vouchers
--      and S$10 of the product (S$50 on its line), then paid S$30: the
--      product (P1b); the S$40 paid back with no line instead, the same (P5a,
--      P5b); the guided Cancel the same, cancelled with nothing held (P6a,
--      P6b on the copies). With the sessions, 1 refunded by line while
--      cancelled, nothing paid: the product first, its S$40 again and the
--      sessions nothing, then paid S$60: 3 of 3 and the product (P4a); the
--      therapy line first, refused (P4b). With no sessions at all, AC's steps
--      (a S$100 Credit Package, a S$40 product added by a correction and
--      paid, S$20 of the credit spent on a session S1, cancelled, the
--      product's S$40 refunded by line, reopened, S$20 paid): the guided
--      Refund in full pays back the package's S$80 and the product's S$40
--      again, so all S$160 the customer paid comes back while S1 stays
--      available, and leaves the invoice part-paid with S$20 outstanding
--      though it was refunded in full (ACnC; paid, the customer pays S$20
--      for S1 after all, ACnCp on the copies); the guided Cancel the same,
--      cancelled with nothing outstanding: a S$20 session for S$0 (AGCnC).
--      Where the plan was cut, the money paid back for the product came from
--      money held for other lines, and which line the cut reaches follows the
--      line order (478's); the payment that settles the invoice takes the
--      product from stock again (a second store_sale, NOT COVERED 1): the
--      customer holds the product its line's second refund paid back (P1a,
--      P3, P4a, P5a), or holds it for S$30 on its S$40 line (P1b, P5b). 481
--      (the Owner's Q2, after this file), as asked, changes the stock side
--      where the line was refunded by line since the last reopening (P1a, P3,
--      P4a, P5a: the product not taken again); where only part of its value
--      was refunded since (P1b, P5b: S$10 of S$40) the line still charges
--      S$30 and its unit was not refunded, so 481's rule as asked still takes
--      it.
--      For the Owner (a money rule; open): keep the second refund (the
--      reopening charges the line again, so it can be refunded again; 479
--      would then let (a)'s plans that are not cut through, as its build
--      before this did); offer a product line refunded before the reopening
--      only for what was paid towards it since; or leave such a line out of
--      the guided plans (staff refund it by line). Until the Owner decides,
--      (a) is refused as 478 refuses it (TP2c too, though it refunds nothing
--      twice), but where the money was paid back with no line and all of it
--      paid again (NL1, NL2, NL1c: through, neither of this file's rules
--      refusing them; for the Owner to confirm, or to refuse as TP2c), and
--      (b) is as 478 does it.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the texts are the tested ones (their AFTER md5s); each function is its
--     BEFORE (252's, as 475 pinned them: replaced) or all three their AFTER
--     (left alone), anything else refused; no other function takes their
--     names; who calls them is as read (refund_invoice_recorded,
--     correct_invoice, the trigger);
--   * the functions they rely on are as read on a copy of production at 478
--     (29 Oct 2026) and the same on copies of production at 485 (2 Nov
--     2026) and at 486 (3 Nov 2026; pinned, below), so 479 goes in after
--     476 to 478, and the refund options and the guided flows are as the
--     Owner kept them (what a plan offers and how it is cut, which the
--     refund reads again in a
--     guided flow: invoice_action_plan, invoice_discounted_line_value; that
--     resolve_invoice_action_v2 names the request it carries out in
--     invoice.therapy_reviewed before it calls the refund, and
--     refund_invoice_recorded passes that request on); the trigger as read;
--     the columns read, with these types (the approval request's, the
--     benefit rows' and the refund rows' among them: the check at the
--     refund's status write reads the lines refund_invoice_recorded records,
--     pinned with it, and the refund in a guided flow reads them, with when
--     they were made and the invoice's reopened_at, to find a line a refund
--     by line paid back before the reopening), the events' created_at stamped by
--     clock_timestamp(); the queue's keys; what reads
--     or writes the session queue, what updates the sessions, what writes
--     their events, what sets reopened_at, and what writes or reads 460's
--     row: as read (before, or after 479 on a second run); what reads or
--     writes invoice.therapy_plan_check (the check a guided flow's refund
--     leaves for its status write): nothing before 479, 479's refund and
--     trigger after it;
--   * on the first run nothing is refused for the data (479 needs no
--     decision before it goes in); the invoices of the header's query are
--     named in a notice (invoice numbers only);
--   * who may call each is as read (postgres and the service role), compared
--     as sets, and kept;
--   * afterwards: the AFTER md5s and the grants as tested.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0479, so it leaves no row): a made-up Owner, store, cash method, S$20
--   session, S$30 voucher and customers (fictional ACMA phones no customer
--   has): a 3-session line sold to A, paid S$60, cancelled, S$20 refunded by
--   line, reopened, then (a) S$20 more refunded by line while it waits: 2
--   wait, the refund options say 1 unused up to S$20 (the S$20 held), paid
--   S$20: 2 of 3 available, 1 refunded, one 'reopen' event; (b) cancelled
--   again, S$20 refunded by line, reopened (the dialog says 3; 2 and 1 wait),
--   paid S$40: 3 of 3, two 'reopen' events; (c) the customer changed to B (no
--   choice asked): the session B's at once, paid: B holds 3; (d) with a S$30
--   voucher line, the customer changed to B with 'keep': the session stays
--   A's, paid: A holds 3 and the voucher, the invoice is B's; a correction of
--   the notes leaves them with A; moving the invoice to C is refused; (e) the
--   Owner's case of 29 Oct 2026: with a S$30 voucher line, all S$60 of the
--   sessions refunded by line while cancelled, reopened, S$20 paid: the
--   guided Refund in full (requested, an Owner approving it) plans S$0 for
--   the sessions and S$30 for the voucher, pays back the S$30, keeps the S$20
--   and leaves the 3 sessions waiting; paid: 3 of 3, no voucher, S$60 net;
--   (f) the Owner's answer of 29 Oct 2026 (~18:45 SGT): with the S$30 voucher
--   line, all S$90 paid back with no line while cancelled, reopened, S$60
--   paid: the guided Refund in full's plan (the sessions S$60, the voucher
--   S$30) is cut to the S$60 held and gives the sessions some of it whichever
--   line it lists first: refused as 478 refuses it ("Settle the reopened
--   invoice before changing its queued sessions", or "Refund whole unused
--   therapy sessions at their original paid value; 3 of 3 sessions remain
--   refundable" where the voucher line comes first), changing nothing; paid
--   S$30: 3 of 3 and the voucher, S$90 net; (g) answer F with another line,
--   the plan not cut: with the voucher line, S$20 of the sessions refunded by
--   line while cancelled, reopened: the guided Refund in full pays back the
--   sessions' S$40 and the voucher's S$30 (the S$70 held), 1 session waits;
--   paid S$20: 1 of 3, no voucher.
--   Locks: the three functions' catalogue rows to the end of the apply, and
--   the rows the self-test writes and undoes; no table is locked against
--   ordinary writes. The self-test takes the commission advisory locks
--   (through its payments, cancels, refunds, corrections and the guided
--   refund's approval) and new invoice numbers, so it waits for any app
--   cancel, refund, correction, commission-writing payment or invoice
--   creation still open, and those wait for it, for under a second. If one
--   stays open longer than the 5 s lock timeout, or an invoice created at the
--   same moment takes the self-test's invoice number, the apply stops,
--   changing nothing, and can be run again. Apply at a quiet time.
--   In the app (each call its own transaction): a refund or correction of a
--   waiting session locks the invoice, then the session, then its waiting
--   rows (a guided flow's refund then reads the plan again, taking no lock,
--   and the check at the refund's status write reads the refund's own rows,
--   taking none);
--   the payment that settles it holds the invoice (its status) and locks the
--   rows, then the sessions: the two never run at once on one invoice (the
--   invoice's row lock comes first in both). Any other write of the invoice's
--   status while a session waits (a part payment, Correct payment, a
--   correction) first reads without locks whether a waiting session must
--   follow someone else, and locks the rows and the sessions (then reads them
--   again) only where one must (a customer change): so a part payment or
--   Correct payment takes no lock on the sessions, as before 479. A merge
--   locks the sessions it moves before the invoice (its loop over the tables
--   that name the customer, customer_therapy_sessions before invoices) and
--   without the invoice's lock, as before 479: a merge of a waiting session's
--   customer at the same moment as the payment that settles that invoice (as
--   before 479) or as a correction that moves the session can deadlock;
--   Postgres then stops one of the two, which changes nothing, and it can be
--   run again. (This file's first build locked the waiting sessions on every
--   status write, so a part payment and a merge could deadlock too: checked
--   on copies with two sessions and real commits, the part payment stopped
--   with 'deadlock detected'; now both go through.)
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   3 Nov 2026: the first apply on production, with the Owner's go-ahead,
--   stopped at self-test (f) and changed nothing (the whole apply was
--   undone; production still at 486, checked). A run that always rolled
--   back showed why. On production the guided plan for (f)'s made-up
--   invoice listed the voucher line first on one read and the session line
--   first a moment later, so the approval answered "What this request would
--   do has changed since it was submitted ..." and did nothing (S$60 held,
--   the 3 sessions waiting); the self-test took that for the approval going
--   through. 479's rule was not at fault: (f) is refused in both orders. The
--   self-test now confirms a revised plan with the same money and the same
--   lines and approves again, as staff would ((e), (f) and (g)). No function
--   text changed. For the Owner (478's own, not 479's; NOT COVERED 10): on
--   production an approval of a cut plan can ask staff to confirm a revised
--   plan although nothing changed, because which line it lists first is not
--   fixed.
--
--   production now (486, 2 Nov 2026: 987d9ea6, 1398 functions; the grant
--   list e68aa1ab, to be compared as sets (370ed899); head 20261102143942)
--   -> 479 (8928dd46) -> 481 (the Owner's Q2, 29 Oct 2026 ~18:45 SGT: the
--   settling payment's stock; a file of its own, built after this one,
--   pinning 479's AFTERs): 479, then 481, on top of 486. Applied since 478
--   (29 Oct 2026: eae7f82f, 1390 functions; the grant list c05bd82e; head
--   20261029060840) by other sessions, each with the Owner's go-ahead, in
--   version order: 480 (cal.com bookings: a table, six calcom_* functions,
--   customer_downline_visits and affiliate_portal_network), 483 (a
--   promotion picked in a choice group, a blind box's prize, takes its
--   stock: capture_invoice_stock_components), 482
--   (calcom_customer_bookings), 484 (affiliate_portal_network and two new
--   functions), 485 (attach_held_health_survey, event_web_fill_customer,
--   submit_health_survey) and 486 (2 Nov 2026, 22:39 SGT: the customer
--   merge preview, preview_customer_merge f66c9d63 -> b98004c9, one
--   function, no grant). None of them changes a function 479 changes,
--   relies on or reads, or what its catalogue checks read (checked 2 Nov
--   2026 on copies of production at 485 and again, 3 Nov 2026, at 486:
--   every pin as read; applied twice, the second run left alone; on a
--   copy at 486 with the merge preview put back to its text at 485 the
--   public function
--   fingerprint is 485's, d5bcc0ce, and the grant list is the same at
--   both). 479 pins merge_customer_records, which 486 left as it was; it
--   calls the merge preview, whose new refusal (the record holding a portal
--   login or an affiliate record retired into one holding neither) none of
--   the suite's merges meets (they hold neither, and pass at 486); 479 does
--   not pin the preview. It checks the functions it changes and relies
--   on, not the whole fingerprint, so a later file that changes none of
--   them does not stop it; the fingerprints below are then worked out again
--   on a copy of production as it is (step 2). 479 pins 476's AFTERs
--   (invoice_transferable_benefits, move_invoice_benefits_to_customer),
--   478's (the Reopen dialog's preview), the refund options and the guided
--   flows as they
--   are, so it refuses, changing nothing, if any of those changed first. It
--   changes the three functions 475 pinned (the trigger's, the refund's, the
--   correction's) and none that 438, 448 or 477 pinned (the refund options).
--   Checked on copies of production at 478 with and without the previous
--   build in (30 Oct 2026; for this build re-run at 485, 2 Nov 2026, below;
--   each run
--   inside begin ... rollback): re-runs of 438, 446 to 448, 451, 460 to 464
--   and 470 to 477 refuse, changing nothing, each on a pin a later file
--   already moved, the same with 479 in as without it (475's and 477's on
--   478's preview), but 461's, which with 479 in refuses on its list of the
--   functions that call invoice_transferable_benefits (479's correction step
--   joins it; without 479, on that function's anchor); 465 to 469 and 478 are
--   left alone; 479's own is left alone; the fingerprint stays the same.
--   0. The Owner answered NOT COVERED 10 (29 Oct 2026 ~18:45 SGT, "Keep
--      today's refusal": built here). 16 (where the plan the request saved
--      is not the plan carried out, 478's refusal is kept, also where no
--      other line offers anything at the session's turn, but not where only
--      the session's line has anything to refund, at its turn and in the
--      saved plan, which goes through as answer F asked unless another line
--      was given money; a saved plan not cut, or one where only the session's
--      line has anything to refund, is checked again once every line is
--      done; the guided Cancel and Refund in full of one state can end
--      differently there) and 17 (a
--      product line
--      refunded before the reopening refunded again by the guided flows:
--      refused as 478 where the plan reaches a waiting session, but not where
--      it was paid back with no line and all of it paid again (NL1: the plan
--      not cut and no refund by line before the reopening, so it goes
--      through; for the Owner to confirm); 478's own elsewhere) are
--      open for the Owner and do not hold 479 back: in both, 479 keeps 478's
--      result but where noted; nor do 1's stock (481, after it), 14 or 15
--      (left documented).
--   1. Before it, read only (invoice numbers and counts only; run on
--      production on 3 Nov 2026: no rows, WHAT WAS WRONG). 479 refuses no
--      state; this lists what changes (1, 3) and what needs the Owner (2).
--      On the production facts known (29 Oct 2026: no reopening waits) it
--      lists nothing under 1 and 2; 3 lists any session held by someone
--      other than its invoice's customer (none is known; no function made
--      one before 479):
--     with
--     -- therapy sessions waiting for their invoice's reopening to be paid (or once
--     -- it was cancelled or refunded again): per session, what waits, what was
--     -- refunded by line since the invoice was last reopened, what it shows as
--     -- refunded and cancelled
--     w as (
--       select q.invoice_id, q.session_id, q.waits,
--              s.quantity_refunded + s.quantity_cancelled as shows,
--              coalesce((select sum(-e.quantity) from public.invoice_therapy_session_events e
--                         where e.session_id = q.session_id and e.event_kind = 'refund'
--                           and e.created_at > i.reopened_at), 0) as since
--         from (select invoice_id, session_id, sum(quantity) as waits from public.invoice_reopen_sessions
--                where applied_at is null group by invoice_id, session_id) q
--         join public.customer_therapy_sessions s on s.id = q.session_id
--         join public.invoices i on i.id = q.invoice_id),
--     found(reason, invoice_id, n) as (
--       select '1 changes: a therapy session waiting for its invoice''s reopening to be paid, the invoice part-paid or unpaid, or cancelled or refunded again: its refund by line and a customer change keeping its line and store were refused before 479, and so were the guided Cancel with "Record refund paid" and the guided Refund in full where their plan refunded some of it; from 479 they go through, the refund taking its sessions off what waits, the change giving them to whoever holds the invoice''s benefits, the guided ones where their plan comes out in whole sessions and voucher units at the value 479 gives the sessions (NOT COVERED 14), offering as before no session a refund by line paid back before the reopening (the Owner, 29 Oct 2026), and refused as before 479 where their plan was cut to the money held and another of its lines had something to refund (the Owner, 29 Oct 2026, "Keep today''s refusal") (the count is of sessions)', i.id, count(*)
--         from public.invoices i join w on w.invoice_id = i.id
--        where i.deleted_at is null and w.waits + w.since = w.shows
--        group by i.id
--       union all
--       select '2 for the Owner (not changed by 479: 475''s NOT COVERED 3 and 4): a waiting therapy session whose waiting rows and refunds since the reopening do not add up to what it shows; the payment that settles the invoice is refused before 479 and after it, and from 479 its refund by line and customer change are too ("Therapy session reopening changed; reload its original evidence") (the count is of sessions)', i.id, count(*)
--         from public.invoices i join w on w.invoice_id = i.id
--        where i.deleted_at is null and w.waits + w.since <> w.shows
--        group by i.id
--       union all
--       select '3 changes: a current therapy session held by someone other than its invoice''s customer (no function made one before 479): not waiting, a correction of the invoice gave it to the invoice''s customer as new sessions before 479, and from 479 one that changes its line, quantity or store, or moves the invoice to a customer other than its holder, is refused, and one that changes none of them leaves it; still waiting for its reopening''s payment, every correction was refused before 479, and from 479 one that moves the invoice to another customer goes through, the session following 460''s rule, one that changes its line, quantity or store is refused, and one that changes none of them leaves it (the count is of sessions)', i.id, count(*)
--         from public.invoices i join public.customer_therapy_sessions s on s.invoice_id = i.id and s.is_current
--        where i.deleted_at is null and s.customer_id is distinct from i.customer_id
--        group by i.id)
--     select f.reason, i.invoice_no, f.n
--       from found f join public.invoices i on i.id = f.invoice_id
--      order by f.reason, i.invoice_no
--      (The suite runs this same text on its cases' states and checks what
--      it lists.)
--   2. Dry run on a copy of production as it is then: work out its
--      fingerprint and grant list first (they must be the BEFORE figures
--      below, or be worked out again on that copy); apply this file twice;
--      the first run ends at the AFTER fingerprint below, the second
--      changes nothing ("left alone"); and the suite, with the earlier
--      suites below.
--   3. Apply (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself.
--   4. No page change goes with it (NOT CHANGED).
--   Checked for the build of 30 Oct 2026 (the previous build), on copies of
--   production at 478, each dropped afterwards: applied twice (fbc67a29, 1390 functions; the
--   grant list unchanged, c05bd82e, as sets 5752c2df; the second run left
--   alone; the self-test's seven cases pass, (f) refused as 478 and (g)
--   through, leaving no row and moving no sequence); its suite in install
--   mode three times on this text (62 to 78 s, every section passing) and
--   once on the same logic before its comments were last edited (27 min, the
--   machine short of disk, every section passing), and with -v nomig=1 where
--   479 is in (in the sweep below: 7 PASS, 8 KNOWN); the re-runs above; the
--   app's calls one by one, each committed, on copies at 478 and with this
--   file: the shapes of the Owner's answer of 29 Oct 2026 ~18:45 in both line
--   orders, KG45, KG45c, KG45p, KGn40 and NOT COVERED 17's (34 cases: 30
--   exactly as at 478, every key; KG45, KG45c, KG45p and KGn40 as the
--   previous build), and all of this suite's cases (140: the cut plans
--   exactly as at 478, every key, wherever a copy at 478 listed their lines
--   in the same order, VTPc2's order, met only with 479, refused with 478's
--   message; the other 113 the previous build ran exactly as it, the plan's
--   lines in any order); the page tests (node --test, every
--   scripts/*/tests/*.test.mjs; 479 has no page change): 1314 of 1316 pass, 1
--   skipped, and the one failure needs a database of its own (voucher-claims'
--   migration-compilation), as before; and 224 suites (begin...rollback, -v
--   nomig=1 and skip_install=1) on a copy at 478 and on copies with this file
--   (a fresh one for the last 97), among them 476 to 478's, 475's, 474, 471,
--   470, 463, 462, 461, 460, 458, 451, 448, 447, 446, 438 and 417's, every
--   invoice-actions, credit-policy and customer-merge suite, the therapy,
--   stock, inventory, transfer and exchange suites and permissions'
--   staff-only-functions, role-guards and rls-policies, and function-grants
--   read-only (490 staff functions, the same with 479 in as without it): 181
--   end exactly the same; 39 differ only in random fixture values or the
--   order a few PASS lines print (the same outcome, the same PASS, KNOWN and
--   FAIL lines), and in 472's known R328c the used credit its refusal names
--   (S$60.00 on the copy at 478, S$20.00 with 479; S$20.00 on three fresh
--   copies at 478: 478's own order); 462's and 471's suites ran out of time
--   on the copy with 479 after some 120 suites (it had slowed: 476's suite
--   took 1,166 s there, 20 and 28 s alone), and alone on fresh copies end the
--   same with and without 479 (462: 45 and 37 s; 471: 37 and 45 s); and the
--   two meant to differ: this file's suite (refused at its start without 479;
--   with it, every section passing) and 475's (its K1 and K2 FIXED as far as
--   479 fixes them, as with the previous build). Some fail on both copies at
--   the same first error, as before: fixtures or seeds a schema-only copy
--   lacks, or their own install's pins of an earlier stack.
--   Re-checked for the re-base of that build (2 Nov 2026), on copies of
--   production at 485 (rc485_live: d5bcc0ce, 1398 functions), each dropped afterwards: every
--   function this file changes or relies on as pinned (none of them changed
--   by 480 or 482 to 485); applied twice (bda210db, 1398 functions; the
--   grant list unchanged, e68aa1ab, as sets 370ed899; the second run left
--   alone; the self-test's seven cases pass, every table's row count and
--   every sequence as before); 481 then applied on it (3d476df5, 1399
--   functions); its suite in install mode three times on this file (every
--   section passing: 12 PASS, 8 KNOWN) and with -v nomig=1 with 479 and 481
--   in (7 PASS, 8 KNOWN, its notes on 481 printed); the re-runs of 478 and
--   480 to 485 the same with 479 in as without it (481's DEPLOY ORDER); 47
--   suites (begin ... rollback, -v nomig=1 and skip_install=1) on a copy at
--   485 and on one with 479 and 481: 475's, 457's, 464's and 483's, every
--   exchange, promotion, transfer, stock history, stock-in, stock loan,
--   adjustment, product, rental and stock repair suite, the invoice-actions,
--   invoice-correction, invoices and therapy suites about promotions and
--   stock, TikTok's 465, invoices/regression.sql and permissions'
--   warehouse-stock-use, staff-only-functions, role-guards, rls-policies and
--   function-grants (read only: 491 staff functions at 485, with 479 and
--   with 479 and 481): 40 end exactly the same (exit code, PASS, KNOWN and
--   FIXED counts and lines, first error); 5 differ only in random fixture
--   values, a timestamp or the order an unordered list prints (455's, 458's,
--   465's and transfers' discrepancy-sources; 464's H2, voucher rows of one
--   moment listed by id); and the two meant to differ: this file's suite
--   (install mode at 485; -v nomig=1 with 479 and 481) and 475's (its K1 and
--   K2 FIXED as far as 479 fixes them); 8 of the 47 fail on both at the same
--   first error, as before (fixtures or seeds a schema-only copy lacks, or
--   their own install's pins of an earlier stack), and with an app settings
--   row added in the same rolled-back transaction exchanges' commission and
--   money-and-stock pass on both. Not re-run at 485: the page tests (479 has
--   no page change) and the full sweep.
--   Checked for this build at 486 (3 Nov 2026: the re-base onto production
--   at 486; nothing in 479's function texts or pins changed, only this
--   header and its suite's fingerprint pair, the pair at 485 still
--   accepted), on copies of production at 486 (rc486_live: 987d9ea6, 1398
--   functions; grants e68aa1ab, as sets 370ed899), each dropped afterwards:
--   every function this file changes, pins or reads as at 485 (with the
--   merge preview put back to its text at 485 the fingerprint is 485's,
--   d5bcc0ce, and the grant list the same); applied twice (8928dd46, 1398
--   functions; the grant list unchanged; the second run left alone; the
--   self-test's seven cases pass, every table's row count and every
--   sequence as before); 481 then applied on it twice (e15db582, 1399
--   functions; grants 0f4b7be6, as sets 80e531b7; the second run left
--   alone; row counts and sequences as before); its suite in install mode
--   three times (twice by default, once with hash and merge joins off: 12
--   PASS, 8 KNOWN each, the same notices word for word, 125 to 136 s) and
--   with -v nomig=1 on a copy with 479 and 481 (7 PASS, 8 KNOWN);
--   permissions' function-grants read only at 486, with 479 and with 479 and
--   481 (6 signed-out endpoints, 491 staff functions); the customer-merge
--   suites (486's merge-guard-486 among them, with -v skip_install=1; 445's
--   with -v nomig=1) and the other suites 486's commit edited (event-website
--   439 and 441 and affiliate-network-phone-484, with -v skip_install=1),
--   each on a copy at 486 and on one with 479 and 481: the same exit code
--   and the same PASS lines on both, but for random fixture values, the
--   order an unordered list prints (445's B3) and the number of functions
--   (1398 -> 1399, 481's); phone-capture-stays fails on both at the same
--   first error (a commission with no rate: a setting a schema-only copy
--   lacks). The final checks of this build (3 Nov 2026, on this file before
--   its header was last corrected, dcd24037: only comments changed since),
--   on fresh copies of production at 486, each dropped afterwards:
--   * applied twice, then 481 twice: 8928dd46, then e15db582 (1399); each
--     second run left alone; row counts and sequences as before (the
--     self-test made 7 invoices and 2 guided approvals each run); the same
--     with a settings row like production's (staff commission 3%);
--   * a schema diff (pg_dump -s of every schema; every function's md5 and
--     grants): only the three bodies changed; 486's merge preview stays
--     b98004c9, and 486's own file, run again, is left alone;
--   * the suite in install mode three more times (12 PASS, 8 KNOWN, the
--     same notices) and with -v nomig=1 (7 PASS, 8 KNOWN; also with a
--     settings row);
--   * 296 cases (the suite's 192 and 104 more), each app call committed,
--     in 14 runs: at 486 six (by default three times, with hash and merge
--     joins off twice, with nested loops off once), with 479 two, with 479
--     and 481 six. Every change from 486 falls under answer F, Q2 or a NOT
--     COVERED item 479 changes on purpose; each case's class matches its
--     Owner rule (0 mismatches); the same 28 cases follow the line order at
--     486 and with 479 and 481, with the same outcomes (NOT COVERED 10's and
--     17's cut plans, and some that differ only in their message); the
--     credit, queue and Cancel invariants hold in every run (Kdup and Kdupc
--     aside, the same in every build);
--   * the guided part refund (refund_partial), which the suite does not
--     run: through where its plan is not cut and comes out in whole units
--     (GPb, GPc, GPd, GPi, GPj); refused as at 486 where it is cut, with
--     the same message in each line order (GPe, GPe1, GPf);
--   * a customer merge while a guided request waits: the approval goes
--     through for the record kept (MG1: 1 session for S$20 net, nothing
--     left with the merged record; MG2, MG3); at 486 refused, the request
--     left pending;
--   * money paid back with no line, then all paid again: NOT COVERED 17(a);
--   * the repo's concurrency tests (invoice-actions, invoice-payments,
--     therapy-choices): every check the same at 486 and with 479 and 481;
--     a race test of 479's new paths (two sessions, both orders, 2 to 5
--     runs each): no deadlock; the approval first, S$40 refunded, then S$10
--     paid, 1 session waiting; the part payment first, the plan is stale
--     and the request stays pending; a refund by line of a waiting line
--     against the settling payment, 2 of 3 for S$40 net either way;
--   * a go-live rehearsal, twice: a copy at 486 holding 12 therapy and 12
--     stock cases begun there; the read-only queries; 479 and 481 applied
--     twice each; the cases finished. The notices named the invoices the
--     queries listed; requests raised before and approved after go through
--     where 479 allows (GL2, GL3, GL4) and stay refused and pending where
--     486 refuses (GL3p, GL8);
--   * the re-runs of migration files 399 to 486 and, in another check, 390
--     to 486, inside begin ... rollback, at 486 and with 479 and 481: the
--     same, but 461 (refused on both, on another check with 479 in), 478
--     (refused once 481 is in) and 479 and 481 (left alone once in);
--   * the full sweep: 231 suites (begin ... rollback, -v nomig=1 and
--     skip_install=1), each on a fresh copy at 486 and on one with 479 and
--     481: none fails only with them; 188 the same; 33 only in values (the
--     function count, random fixtures); 10 in lines (3 as meant, 7 random);
--     63 fail on both at the same first error (14 of them pass on both with
--     production's settings row). The 135 suites that reach the changed
--     paths, run with that row: no unexpected difference;
--   * the page tests (node --test, 134 files): 1359 of 1361 pass, 1
--     skipped; the one failure needs a database of its own (voucher-claims'
--     migration-compilation), as before.
--   Not shown: behaviour at production's data size; the apply itself (the
--   CLI or the MCP); anything past the first error of the suites that still
--   stop there on a schema-only copy; a voucher used elsewhere (no app call
--   marks one used); the merge-against-settle deadlock (SAFETY).
--   Checked for this build at 485 (3 Nov 2026, the third fix review: where
--   only the session's line has anything to refund, at its turn and in
--   the plan the request saved, the refund goes on again, and the check it
--   leaves for the end of the approval then allows no money for any other
--   line where the saved plan is not the one carried out; two variables
--   and one test added to the refund, its comments corrected; the
--   correction's step and the trigger unchanged), on copies of production
--   at 485 (rc485_live:
--   d5bcc0ce, 1398 functions; grants e68aa1ab, as sets 370ed899), each
--   dropped afterwards: reproduced first, each app call committed (46
--   cases: the review's Z8, Z8b, Z8c, Z8p, Z5r, Z5x, Z5, Z5xc, Z1, Z2, Z3,
--   Z6, Z6x, KZ, KZx and its controls Z9, Z4, Z0, Z1r, Z00, Z8s, Z1s, KZs;
--   found checking it ZG, ZGx, ZGc, ZGxc, ZGs, ZGsx, Z7, Z7x, ZB, ZBx, ZTT,
--   ZTTs; and Y1, Y2, Y3, V1, V2, V4, Y1s, STv, STvp, KG45, KGn40), at 485,
--   with the build of 2 Nov 2026 (late: 479 2018c80d, 481 0e805e1e) and with
--   this build and 481, by default, with hash and merge joins off and with
--   nested loops off (42 of the 46 seen in two or more line orders, the
--   sessions listed first, between the S$0 lines and last), and with the
--   build before (479 1aa18683, 481 82815a2b) by default: the build before
--   refused 19 of them (Z8 to KZx, Z7, Z7x, ZB, ZBx: only the session's line
--   having anything to refund, two or more other lines at S$0, a payment
--   or Correct payment between the request and the approval), which the
--   build of 2 Nov 2026 (late) let through in every order; that build had
--   two outcomes, by line order, for ZG, ZGx, ZGc, ZGxc, Y1, Y3 and V1; with
--   this build each case has one outcome in every line order seen, the same
--   as with the build of 2 Nov 2026 (late), every key, but where that build
--   let a case through in one line order only (Y1, Y3, V1, ZG and ZGc by
--   default and with hash and merge joins off, ZGx and ZGxc with nested
--   loops off), and the same as at 485, every key, wherever it
--   refuses (ZG, ZGx, ZGc, ZGxc, Y1, Y2, Y3, V1, V2, STvp, ZTT; ZG and ZGc
--   with the package listed first at the refund's status write, with 478's
--   message: the error's context, the trigger, on a copy with each app call
--   committed); applied twice (5695d246, 1398 functions; the grant list
--   unchanged, e68aa1ab, as sets 370ed899; the second run left alone; the
--   self-test's seven cases pass, every table's row count and every
--   sequence as before); 481 then applied on it twice (20ef063d, 1399
--   functions; grants 0f4b7be6, as sets 80e531b7; the second run left
--   alone; row counts and sequences as before); its suite (now 170 cases and
--   the 22 cut plans: the review's Z8, Z8c, Z5r, Z5x, Z6, KZ, Z1, Z2 with Z9,
--   Z0, Z8s, ZGs and ZGsx fixed, ZG and ZGx controls, K16 checking them; its
--   work-back of the refund and its AFTER md5 and fingerprint updated) in
--   install mode three times (twice by default, once with hash and merge
--   joins off: 12 PASS, 8 KNOWN each) and with -v nomig=1 on a copy with 479
--   and 481 (7 PASS, 8 KNOWN); all 192 cases of the suite (its 170 and the
--   22 cut plans), each app call committed, on copies at 485, with the build
--   before and 481 and with this build and 481, by default and with nested
--   loops off (97 of the 192 seen in two line orders with this build): one
--   outcome for each case, build and line order; this build the same as the
--   build before, every key, for each case and line order, but Z8, Z8c, Z5r,
--   Z5x, Z6, KZ, Z1 and Z2, which the build before refused; the same as at
--   485, every key, wherever both listed the lines in the same order, but
--   the cases 479 changes on purpose (refused before it) and 481's stock;
--   no case whose outcome follows the line order at 485 or with this build
--   but the cut plans of NOT COVERED 10 and 17 (TVn60b, TVn60cb, TVn20b and
--   P1, P4, P5: each as at 485 for the line it lists first, but 481's stock
--   with the product first); the suites the change can reach (56, each on a
--   fresh copy at 485 and on one with this build and 481, -v nomig=1 and
--   skip_install=1: 438's, 446's to 448's, 451's, 457's, 460's to 464's,
--   470's to 478's and 483's, the invoices therapy suites, every
--   invoice-actions, credit-policy, therapy, therapy-choices and
--   therapy-services suite, and permissions' function-grants read only): 45
--   end exactly the same (exit code, the PASS, KNOWN, FIXED and NOTE lines,
--   the first error; 9 of them fail on both at the same first error, as
--   before: fixtures or seeds a schema-only copy lacks, or their own
--   install's pins), 8 differ only in the number of functions they print
--   (1398 -> 1399, 481's), credit-policy's released-credit-paths and 464's
--   only in the order an unordered list prints, and 475's as meant (its K1
--   and K2 FIXED as far as 479 fixes them); function-grants the same (6
--   signed-out endpoints, 491 staff functions).
--   Not re-run for this build at 485 (the final checks ran them at 486,
--   above): the re-runs of the earlier files, the full sweep and the page
--   tests (479 has no page change).
--   Checked for the build before this one (3 Nov 2026: the plan the request
--   saved is read also where no other line offers anything at the session's
--   turn; one line of the refund deleted, its comment corrected), on copies of
--   production at 485 (rc485_live: d5bcc0ce, 1398 functions; grants
--   e68aa1ab, as sets 370ed899), each dropped afterwards: reproduced first,
--   each app call committed, at 485 and with the build before (479
--   2018c80d, 481 0e805e1e), by default, with hash and merge joins off and
--   with the refund options' lines planned by hash joins (Y1 to Y4, V1 to
--   V5, Y1s, Y3s, V1s, STv, STvp: at 485 every one refused, in every order
--   seen; the build before approved Y1, Y3 and V1 with the package or the
--   vouchers listed before the sessions and refused them with the sessions
--   or the product listed first; this build refuses Y1 to Y4 and V1 to V3
--   in every order, in refund_invoice_therapy_sessions at the session's
--   turn (the error's context), every key as at 485, and lets V4, V5, Y1s,
--   Y3s, V1s and STv through as the build before did); applied twice
--   (270aa323, 1398 functions; the grant list unchanged, e68aa1ab, as sets
--   370ed899; the second run left alone; the self-test's seven cases pass,
--   every table's row count and every sequence as before); 481 then applied
--   on it twice (41f202f2, 1399 functions; grants 0f4b7be6, as sets
--   80e531b7; the second run left alone; row counts and sequences as
--   before); its suite in install mode three times (twice by default, once
--   with hash and merge joins off: 12 PASS, 8 KNOWN each, the same notices
--   word for word, 96 to 102 s), with -v nomig=1 on a copy with 479 and 481
--   (7 PASS, 8 KNOWN) and again there with the refund options' lines planned
--   by hash joins (7 PASS, 8 KNOWN; Y1 to Y4 listing the sessions first, V1
--   to V3 the product); all 177 cases of the suite (its 155 and the 22 cut
--   plans), each app call committed, on copies at 485, with the build before
--   and 481 and with this build and 481, by default, with hash and merge
--   joins off and with the lines planned by hash joins (94 of the 177 seen
--   in two or more line orders): one outcome for each case, build and line
--   order; this build the same as the build before, every key, but Y1, Y3
--   and V1 where the build before let them through; the same as at 485,
--   every key, wherever both plans gave each line the same amount, but
--   481's stock (VPR, PRxk, PRpp, P3, P1, P4, P5) and the cases 479 changes
--   on purpose (refused before it); no case whose outcome follows the line
--   order at 485 or with this build but the cut plans of NOT COVERED 10 and
--   17, each as at 485 for the line it lists first (with the build before,
--   Y1, Y3 and V1 did);
--   the suites the change can reach (54, each on a fresh copy at 485 and on
--   one with this build and 481, -v nomig=1 and skip_install=1: 438's,
--   446's, 451's, 457's, 460's to 464's, 470's to 478's and 483's, the
--   invoices therapy suites, every invoice-actions, credit-policy, therapy,
--   therapy-choices and therapy-services suite, and permissions'
--   function-grants read only): 51 end exactly the same (exit code, the
--   PASS, KNOWN, FIXED and NOTE lines, the first error; 9 of them fail on
--   both at the same first error, as before: fixtures or seeds a
--   schema-only copy lacks, or their own install's pins or variables), the
--   number of functions aside (1398 -> 1399, 481's); credit-policy's
--   released-credit-paths and 464's differ only in the order an unordered
--   list prints or which of two lines a random id picks to print, and 475's
--   as meant (its K1 and K2 FIXED as far as 479 fixes them); function-grants
--   the same (6 signed-out endpoints, 491 staff functions).
--   Not re-run for that build: the 71 extra cases of the build before
--   (their scratch files were lost in a restart), the re-runs of the earlier
--   files, the full sweep and the page tests (479 has no page change).
--   Checked for the build before that (2 Nov 2026, late: a line holding
--   no credit, vouchers or sessions that a refund by line paid back before the last
--   reopening, offered again where the plan reaches a waiting session,
--   refused as 478 at the session's turn), on copies of production at 485
--   (rc485_live: d5bcc0ce, 1398 functions; grants e68aa1ab, as sets
--   370ed899), each dropped afterwards: reproduced first, each app call
--   committed, at 485 and with the build before (479 082badac, 481
--   ff40ea0a), in the line order the copies gave and with hash and merge
--   joins off (the fix review's AC, AGC, XN1R to XN6C, ACp, AXV, AVX, and
--   AXVn, AVXn, TPr, PTr, TPrc, PTrc, TP2c, TPk, ACt, AGCt, ACtp, ACtx
--   found checking it: the build before approved every one of the AC family
--   in every order, 485 refused it; AXV refused with the vouchers' message
--   in one order); applied twice (ca96dde5, 1398 functions; the grant list
--   unchanged; the second run left alone; the self-test's seven cases pass,
--   every table's row count and every sequence as before; the self-test has
--   no product line: selling one takes the store's stock, whose history
--   moves a sequence (stock_history_inventory_changes_id_seq) that the
--   self-test must leave as it was, so it does not reach the new rule: the
--   suite does); 481 then applied on it
--   twice (7987f0d2, 1399 functions; grants 0f4b7be6, as sets 80e531b7;
--   the second run left alone; row counts and sequences as before); its
--   suite in install mode (12 PASS, 8 KNOWN, 87 s) and again with hash and
--   merge joins off (the same notices word for word, 95 s), with -v nomig=1
--   on a copy with 479 and 481 (7 PASS, 8 KNOWN) and again there with the
--   refund options' lines planned by hash joins (an ALTER FUNCTION
--   invoice_refund_options_before_sessions SET enable_nestloop = off on
--   that copy only: 7 PASS, 8 KNOWN, many plans listing their lines in
--   another order, TVn60b, TVn60cb and TVn20b the therapy line first, PRxr2,
--   PRx2, PRnl2, PRxc2, P1b, P5b and P4b the product first, each case ending
--   as expected for the line its plan lists first); nested loops off for the
--   whole suite ran past half an hour in section A and was stopped. All 236
--   cases (the suite's 165 and 71 more), each app call committed, on copies
--   at 485, with this file and with this file and 481, in the order the
--   copies gave, with hash and merge joins off and with the lines planned
--   by hash joins (12 runs with the build before's, 126 of the 236 cases
--   listing their lines in another order in the last mode): one outcome for
--   each case, configuration and line order; for each case and line order
--   seen at 485 and with these files, the same outcome, every order-free key,
--   but where 479 or 481 change it on purpose (the fixed cases of answer F,
--   among them ACt, AGCt, VTPd, CTPd, CTP, CTPc, BTP, CFR, BFC, BFR2 and the
--   other orders TVPd, PVTd, TPCd, PCTd, TPC, PCT, PCTc, PTB, BFR, CFC, TPk,
--   ACtp, ACtx; the known cases refused before 479; 481's stock); no invoice
--   whose outcome follows the line order with them where it did not at 485
--   among those cases (the second fix review then found three that did:
--   Y1, Y3, V1, approved after the invoice changed; fixed by this build);
--   the AC family (AC, AGC, XN1R to XN6C, ACp, AXV, AVX, AXVn, AVXn, TPr,
--   PTr, TPrc, PTrc, TP2c) and the credit given back (A1, AG, A1p, AN, A1x,
--   XG1R to XG6C) exactly as at 485, every key, in every order seen, AC, AGC,
--   A1, AG, AXV, AVX and TPr refused in refund_invoice_therapy_sessions at
--   the session's turn (the error's context, a copy with each app call
--   committed); the suites of 475, 478, 457, 464 and 483, every
--   invoice-actions and credit-policy suite and the therapy suites (39, each
--   on a fresh copy at 485 and on one with 479 and 481, -v nomig=1 and
--   skip_install=1): 37 end exactly the same (6 of them fail on both at the
--   same first error, as before: fixtures a schema-only copy lacks, or their
--   own install's pins of an earlier stack), credit-policy's
--   released-credit-paths only in the order an unordered list prints, and
--   475's K1 and K2 FIXED as far as 479 fixes them; permissions'
--   function-grants read only (6 signed-out endpoints, 491 staff functions,
--   the same at 485 and with 479 and 481). Not re-run for that build: the
--   full sweep, the re-runs of the earlier files and the page tests (479
--   has no page change).
--   Checked for the build before those (2 Nov 2026: the check at the
--   refund's status write), on copies of production at 485 (rc485_live:
--   d5bcc0ce, 1398 functions), each dropped afterwards: applied twice (082badac, 1398
--   functions; the grant list unchanged, e68aa1ab, as sets 370ed899; the
--   second run left alone; the self-test's seven cases pass, every table's
--   row count and every sequence as before; the self-test does not reach the
--   check at the refund's status write, the suite does); 481 then applied on
--   it (ff40ea0a, 1399 functions); its suite in install mode five times
--   (every section passing: 12 PASS, 8 KNOWN; the last two with 9e6, the
--   refusal of a new reader of the check; A1 and AG listed the package
--   first each time, so were refused once every line was done, as the
--   error's context, the trigger, showed on a copy with each app call
--   committed) and with -v nomig=1 with 479 and 481 in (7 PASS, 8 KNOWN);
--   all 147 cases of the suite with each app call committed, on copies at
--   485, at 485 with the previous build (and 481's previous build) and with
--   this one: 145 exactly as with the previous build, every key, and A1 and
--   AG refused as at 485 where the previous build approved them (the A
--   cases against 485 differing only in the line order their plans listed
--   there); the re-runs of 399, 408, 416, 417, 434, 438, 446 to 448, 451 to
--   458 and 460 to 485, each inside begin ... rollback, on a copy at 485 and
--   on one with 479 and 481: the same outcome but 461's (refused on both: on
--   its list of the functions that call invoice_transferable_benefits,
--   which 479's correction step joins, without 479 on that function's
--   anchor), 478's (left alone at 485, refused once 481 is in, on its pin of
--   invoice_stock_to_deduct) and 479's and 481's own (left alone with them
--   in); the page tests (node --test, every scripts/*/tests/*.test.mjs; 479
--   has no page change): 1359 of 1361 pass, 1 skipped, and the one failure
--   needs a database of its own (voucher-claims' migration-compilation), as
--   before; permissions' function-grants read only (6 signed-out endpoints,
--   491 staff functions, the same with 479 and 481 in as without them); and
--   230 suites (every scripts/*/tests file that starts and rolls back a
--   transaction, and invoices/regression.sql; -v nomig=1 and skip_install=1)
--   on a copy at 485 and on one with 479 and 481 (the last 108 each on a
--   fresh copy on both sides: the shared copy with 479 and 481 had slowed
--   after some 120 suites, its planner figures for tables the rolled-back
--   suites had filled saying they were empty; 476's suite took 349 s there
--   and 17 s alone): 148 end exactly the same; 22 the same but for ids,
--   timestamps, md5s, test phones and document numbers; 57 differ only in
--   random fixture values (referral codes, tokens, name suffixes), the number
--   of functions (1398 -> 1399, 481's invoice_refunded_stock) or the order an
--   unordered list prints (471's PTRh and PTRhp name S$20.00 or S$60.00 of
--   used credit in their refusal, by run, on either copy); and the three
--   meant to differ: this file's and 481's suites (refused at their start
--   without them) and 475's (its K1 and K2 FIXED as far as 479 fixes them).
--   63 fail on both at the same first error, as before (fixtures or seeds a
--   schema-only copy lacks, or their own install's pins of an earlier stack;
--   none fails only with 479 and 481).
--
-- BEFORE (production at 478, 29 Oct 2026, as on its copy, and the same at
-- 485, 2 Nov 2026, as on its copy rc485_live, and at 486 (since 2 Nov 2026),
-- as on its copy rc486_live, 3 Nov 2026; md5 of pg_get_functiondef with
-- search_path public)
--   changed
--   refund_invoice_therapy_sessions(uuid,numeric,text,uuid)             93739f00ada43b1c3f4177b32c9bdc52  (252's)
--   correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid)    12e1cf25bb069521adfe18809bcef68d  (252's)
--   trg_create_therapy_sessions_on_paid()                               af85d6800c7d980565ef8d68898b6a38  (252's)
--   relied on, not changed (pinned)
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)           804ecd829cfecf713783a09a05d93c7e  (446's; calls the refund)
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                         04d647e13e9424a9375942e5812e91a2  (calls the correction's step)
--   invoice_action_plan(uuid,text,jsonb)                                383d618edb28c3c9a360242d038a022c  (reads the refund options; the refund reads it again in a guided flow)
--   resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean) 201f08ebf14a64cd88d411a7cfb4c9c4  (the guided flows; names its request in invoice.therapy_reviewed)
--   request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)           4360d74462ed1fc950b6bd8b5157b3ae  (the guided request; the self-test)
--   invoice_refund_options(uuid)                                        689a71c246260d2c10ec44dd94eb7139  (as 438, 448 and 477 pinned it; kept: the Owner, 29 Oct 2026)
--   reopen_invoice(uuid,text,uuid)                                      30066e137b9b75b5789a050c14debc04  (475's AFTER)
--   invoice_reopen_preview(uuid)                                        e09ebf9c0841ef5463f96b26f4933541
--   invoice_reopen_preview_before_sessions(uuid)                        acbfc38a20a000e1af0e78d26fc7fc4c  (478's AFTER)
--   cancel_invoice_recorded(uuid,text,uuid)                             de52d9dbaef8ab15163bef35cb9d733d
--   create_therapy_sessions_for_invoice(uuid)                           c0a45b7ce309cb9b4ceea53b212bd4aa
--   invoice_credit_live_holder(uuid,uuid,timestamp with time zone)      a5692590ef3e8a7a7dd7e8ff7cfa9568  (462's)
--   invoice_benefits_holder(uuid,uuid,timestamp with time zone)         55995ff6e1ffd4a1172cb930512a34b0  (460's)
--   invoice_transferable_benefits(uuid)                                 1546de1f83d970424d26e65941f4dcb8  (476's AFTER)
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)              142dd3252911480bd4a17e7c55b488d3  (476's AFTER)
--   merge_customer_records(uuid,uuid,text,uuid)                         ba05c2b1fb4c0e14d369c01d06a635b0
--   apply_reopened_invoice_vouchers()                                   6684840544d1ad8a28e2415934300054
--   invoice_refund_options_before_sessions(uuid)                        bd3afcc79cd2f06f983607d54fed167c
--   invoice_charge_total(uuid)                                          8297147511ba285db2279598f3d727fb
--   invoice_discounted_line_value(uuid)                                 ead4a430c3abd1e3f953912867ca4fe6  (a line's value, as the plan reads it; the refund in a guided flow)
--   invoice_financial_position(uuid)                                    ba7eccbfeff217c8b1969b0e55a010ca
--   invoice_net_received(uuid)                                          f256bea69b7defa38a950753bbc248da
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   is_owner_or_manager()                                               a98e50f1b6d3fa1e6c62cf52a8073cc8
--   user_has_store_access(uuid)                                         708992afaa6c3951f6329239b742987c
--   normalize_customer_phone(text)                                      b2bfac910e0c9eff402ba44e19750bee  (the self-test)
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)        80c80d386a5241e63b353e35e13ef250  (the self-test)
--   record_invoice_payment(uuid,jsonb,uuid)                             9c70097ed4da614fb9dcc66fdfcdb7d6  (the self-test)
--   public function fingerprint, production now (486, 2 Nov 2026)      987d9ea60beaec88fb6146d3db6f9441 (1398 functions)
--     (at 485, 2 Nov 2026                                              d5bcc0cef63fe73c19cf2c9a949b05d5 (1398 functions; 486 changed the merge preview alone))
--     (at 478, 29 Oct 2026                                             eae7f82fcf73b53d97945020e755721a (1390 functions))
--   grant list (string_agg(signature '=' proacl, '|'), sorted)          e68aa1abc012f3e4539dd315b96a1ea1 (production at 486, 2 Nov 2026, and its copy; the same at 485); as sets
--                                                                      (each proacl's items sorted) 370ed89994c39b2d544b3d39a26412d2
--                                                                      (at 478: c05bd82e, as sets 5752c2df)
--                                                                      (compare as sets: the same grants may be listed in another order)
-- AFTER (for later guards)
--   refund_invoice_therapy_sessions(uuid,numeric,text,uuid)             35d3f1ba4c906a66a8deb131c777dab8  (grants kept)
--   correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid)    32df6441a3f5e37e164b1279f8dc502b  (grants kept)
--   trg_create_therapy_sessions_on_paid()                               15f4bbc260e53ba538debc0947082f43  (grants kept)
--   invoice_refund_options(uuid)                                        689a71c246260d2c10ec44dd94eb7139  (not changed)
--   public function fingerprint, worked out on copies of production (a second run the same):
--     486 -> 479 (3 Nov 2026, on rc486_live copies)                    8928dd465d7bfd1125d42a983735e226 (1398 functions: none added, none dropped)
--     (485 -> 479, 3 Nov 2026, on rc485_live copies: 5695d246; not worked out at 478 for this build)
--     (this file's first build, which also changed invoice_refund_options, ended at 903bac73, its refund's AFTER 36499347;
--      its build of 29 Oct 2026, which let a cut plan's whole units go through, at c0ae37fa, its refund's AFTER fc004488;
--      its build of 30 Oct 2026, re-based 2 Nov 2026, which trusted a saved plan not cut without comparing what a line
--      holding credit, vouchers or sessions offered, at bda210db (fbc67a29 at 478), its refund's AFTER 26f011d1, the
--      trigger's 3a5ab817; its build of 2 Nov 2026, which refunded again a product line a refund by line paid back
--      before the reopening where the plan was not cut, at 082badac, its refund's AFTER 09a25bcb; its build of 2 Nov
--      2026 (late), which took a plan as not cut where no other line offered anything at the session's turn, so that a
--      request approved after the invoice changed followed the line order, at ca96dde5, its refund's AFTER b02dcb46;
--      its build of 3 Nov 2026, which read the plan the request saved there too, so that answer F's cases with two or more
--      other lines listed at S$0 were refused once anything changed between the request and the approval, at 270aa323,
--      its refund's AFTER 2c6ace5b; the trigger's and the correction's AFTERs the same since 2 Nov 2026)
--   grant list after 479                                               unchanged: e68aa1ab, as sets 370ed899, at 486 and at 485 (at 478: c05bd82e, as sets 5752c2df)
--
-- UNDO (with the Owner's go-ahead; 481 first if it is in: it was built and
-- checked only on top of 479, whose AFTERs it pins; see 481's UNDO)
--   Before the apply, save the three functions' texts from production
--   (pg_get_functiondef, search_path public); each md5 must be its BEFORE
--   one. To undo, in one transaction: stop unless the three are at their
--   AFTER md5s; put each BEFORE text back (the saved text, which is 252's:
--   refund_invoice_therapy_sessions 93739f00,
--   correct_invoice_therapy_sessions 12e1cf25 and
--   trg_create_therapy_sessions_on_paid af85d680; 252's statement for
--   each, run as CREATE OR REPLACE, gives that md5); CREATE OR REPLACE
--   keeps the grants and the trigger; then delete 479's row in
--   supabase_migrations.schema_migrations, guarded on
--   md5(array_to_string(statements, '')) being this file's md5 as applied
--   (a file cannot hold its own md5). Checked 3 Nov 2026 on a copy of
--   production at 486 with 479 and 481 in: 481 undone, the fingerprint is
--   8928dd46 (1398 functions); then this undo, 987d9ea6 (1398) again; the
--   grant list e68aa1ab both times.
--   Warning: a refund by line of a waiting session under 479 lowers its
--   waiting rows (WHAT THIS DOES). Undone, 252's check at the payment that
--   settles the invoice wants each waiting row to be all its session shows
--   as refunded and cancelled; where it is not, that payment is refused
--   ("Therapy session reopening changed; reload its original evidence"),
--   so the invoice cannot be paid off. Find such sessions before undoing
--   and repair their invoices by hand. And a session a 'keep' left with
--   its holder (the header's query, reason 3) would, once its invoice is
--   paid, go to the invoice's customer as new sessions at the next
--   correction of any kind (WHY THIS WAY).
--
-- Test: scripts/invoices/tests/refunds-while-sessions-wait-479.sql
-- (begin ... rollback; it installs this file twice; -v nomig=1 where it is
-- in). It reproduces the refusals first (each case before 479), then checks
-- the header's query, the refusals of this file, cases begun before 479 and
-- finished after it, the install, every case after 479 (what each customer
-- holds, the money, the queue, the sessions' own invariants and 462's,
-- Cancel taking all back, the stock movements of a product line), the
-- Owner's case of 29 Oct 2026 and its siblings exactly as before 479, the
-- controls unchanged, the three texts beside 479's parts exactly as before
-- (worked back, by md5), the refund options unchanged, and NOT COVERED 1, 2,
-- 3, 7, 10, 13, 14, 15, 16 and 17 as KNOWN (4 is its cases CTpg, CTw and
-- CKn; 5, 6, 8 and 9 no case reaches); the cut plans (NOT COVERED 10 and
-- 17) are each run with their lines written both ways and checked for the
-- line their plan lists first, before 479 and after it, and where both runs
-- listed the lines in the same order, after 479 exactly as before it; no
-- comparison depends on the order the lines are listed in; credit given
-- back to a package between the request and the approval (A1, AG, A1p, AN,
-- A1x, AXV, AVX: exactly as before 479, every key), a product line refunded
-- by line before the reopening offered again where the plan reaches a
-- waiting session (AC, AGC, ACp, AXV, AVX, TPr, PTr: exactly as before 479,
-- every key; TP2c, KNOWN) and where it does not (P3, ACnC, AGCnC: 478's,
-- KNOWN), the plans not cut beside two other lines in several orders (ACt,
-- AGCt, VTPd, CTPd, CTP, CTPc, BTP, CFR, BFC, BFR2: through), requests
-- approved after the invoice changed where no other line offers anything at
-- the session's turn (Y1 to Y4, V1 to V3, written in two or three line
-- orders: exactly as before 479, every key; V4, V5 and, with nothing changed
-- between, Y1s, Y3s, V1s: through), the line order each plan listed printed
-- (K16). Each app call
-- is followed by what its commit does (462's trigger is deferred); the
-- Owner's case, its siblings, the cases answer F asked for, the shapes of
-- the Owner's answer of 29 Oct 2026 ~18:45 SGT (in both line orders) and the
-- cases the reviews added were also run with a real COMMIT after every app
-- call, on copies of production at 478, with this file's previous build
-- and with the build of 30 Oct 2026; all 147 cases of the suite (2 Nov
-- 2026) on copies at 485, at 485 with that build and with the next; and
-- all 165 cases of the suite then, with 71 more (2 Nov 2026, late), on
-- copies at 485, with this file and with this file and 481, in the line
-- order the copies gave, with hash and merge joins off and with the refund
-- options' lines planned by hash joins; and all 192 cases of the suite now
-- (3 Nov 2026: its 170 and the 22 cut plans) on copies at 485, with the
-- build before and 481 and with this file and 481 (DEPLOY ORDER). Its own
-- runs for the re-base onto 486 are in DEPLOY ORDER.
-- Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The functions this changes: BEFORE (production at 478, 29 Oct 2026,
  -- and at 485, 2 Nov 2026, as on their copies: 252's three, as 475 pinned
  -- them) and AFTER md5s; who may call each, as read (kept).
  -- invoice_refund_options is not changed (the Owner, 29 Oct 2026): it is
  -- pinned with the functions relied on ═════════════════════════════════════
  c_sigs constant text[] := array[
    'refund_invoice_therapy_sessions(uuid,numeric,text,uuid)',
    'correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid)',
    'trg_create_therapy_sessions_on_paid()'];
  c_names constant text[] := array['refund_invoice_therapy_sessions', 'correct_invoice_therapy_sessions',
                                   'trg_create_therapy_sessions_on_paid'];
  c_before constant text[] := array[
    '93739f00ada43b1c3f4177b32c9bdc52',
    '12e1cf25bb069521adfe18809bcef68d',
    'af85d6800c7d980565ef8d68898b6a38'];
  c_after constant text[] := array[
    '35d3f1ba4c906a66a8deb131c777dab8',
    '32df6441a3f5e37e164b1279f8dc502b',
    '15f4bbc260e53ba538debc0947082f43'];
  c_acl constant text[] := array[
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}'];

  -- ══ The whole texts (each exactly as the database prints it back) ═══════
  c_def_refund constant text := $d1$CREATE OR REPLACE FUNCTION public.refund_invoice_therapy_sessions(p_item_id uuid, p_amount numeric, p_reason text, p_request_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.customer_therapy_sessions%rowtype; units integer; reserve integer;
 v479_wait integer; v479_since integer; v479_take integer; v479_left integer; v479_n integer; q479 record; v479_store uuid;
 v479_req public.approval_requests%rowtype; v479_plan jsonb; v479_offers jsonb; v479_held numeric; v479_pre numeric;
 v479_others numeric; v479_pos integer; v479_lines integer; v479_moving integer; v479_as478 boolean:=false; v479_chk jsonb;
 v479_again boolean; v479_same boolean; v479_only boolean;
begin
 select * into s from public.customer_therapy_sessions where invoice_item_id=p_item_id and is_current for update;
 if not found then raise exception 'Therapy session grant is missing; review the original payment and session evidence'; end if;
 if s.paid_value_snapshot is null or s.paid_value_snapshot<=0 then raise exception 'Original paid session value requires review before a refund'; end if;
 -- 479 (the Owner, 27 Oct 2026, answer F: "allow refund by line / guided
 -- Cancel with refund recorded / Refund in full ... while reopened therapy
 -- sessions wait (sessions come off the queue)"): a session whose invoice's
 -- reopening waits for its payment (invoice_reopen_sessions, not applied),
 -- or which was cancelled again before it was paid, is refunded by line
 -- here; before, refused ("Settle the reopened invoice before changing its
 -- queued sessions", 252, below). The guided Cancel and Refund in full call
 -- it for what the refund options offer, which still count the sessions
 -- refunded before the reopening as refunded (the Owner, 29 Oct 2026:
 -- "keep today's result", those are not offered again); a refund by line may
 -- take them. Its waiting rows are locked first, then read. With nothing
 -- waiting, as before 479 (below, word for word).
 perform 1 from public.invoice_reopen_sessions where session_id=s.id and applied_at is null order by id for update;
 select coalesce(sum(quantity),0)::int into v479_wait from public.invoice_reopen_sessions where session_id=s.id and applied_at is null;
 -- 479 (the Owner, 29 Oct 2026 ~18:45 SGT, "Keep today's refusal"): in the
 -- guided Refund in full, Cancel with "Record refund paid" or part refund
 -- (resolve_invoice_action_v2 carrying out the approval of request
 -- p_request_id: it names it in invoice.therapy_reviewed), where the plan
 -- was cut to the money held (invoice_action_plan's cap, line by line in an
 -- order that is not fixed) and another of its lines had something to
 -- refund, the waiting session is refused exactly as before 479 (252's
 -- checks, below), so that what the guided flow does never follows the
 -- line order where 478 refused; staff refund item by item. Where only the
 -- session's line had something to refund, or the plan was not cut, it goes
 -- on below, as answer F asked. The plan is read as it stands now: the
 -- refund has paid nothing back yet (its money is recorded once every line
 -- is done, so the money held is the plan's), and has not touched this
 -- session's line or any line it reaches after it; a line it reached before
 -- this one gave all it offered (the cut, if any, came after it, as this
 -- line is given something) and, where it holds credit, vouchers or
 -- sessions, shows less now. So: this line given less than it offers is the
 -- cut, and another line had something where money was left for the lines
 -- before it or another line still offers something; this line given all it
 -- offers, a cut is on a line after it, which still offers what it offered:
 -- with what this line and the others offer more than the money held, a
 -- cut; otherwise no cut where at most one other line is listed or none
 -- holds credit, vouchers or sessions (nothing hidden); else (a line before
 -- this one may have offered more than it shows now; so too where no other
 -- line offers anything now, as one holding credit, vouchers or sessions
 -- that the refund reached first shows nothing: which lines come first
 -- follows the order the lines are listed in, which is not fixed, so this
 -- test does not read that alone; the second fix review, 3 Nov 2026) the
 -- plan the request saved is read. Where it is the one being carried out by
 -- what can be compared (the money held, the lines, this line's amount and
 -- offer, what a line holding no credit, vouchers or sessions offers) and
 -- says not cut, the refund goes on. Where every other line offered nothing
 -- in it (by item, not by line order) and none offers anything now, only
 -- this line has anything to refund (no other item to choose between:
 -- answer F, kept by the Owner's Q1 of 29 Oct 2026, whichever line is
 -- listed first; the third fix review, 3 Nov 2026), so it goes on too.
 -- Otherwise the session is refused as before 479. Where it goes on, the
 -- plan carried out is checked again once every line is done (below, and
 -- trg_create_therapy_sessions_on_paid; NOT COVERED 16).
 if v479_wait>0 and coalesce(current_setting('invoice.therapy_reviewed',true),'')=p_request_id::text then
  select * into v479_req from public.approval_requests r
   where r.id=p_request_id and r.status='pending' and r.related_record_id=s.invoice_id and r.request_type in ('invoice_cancel','invoice_refund');
  if found then
   v479_plan:=public.invoice_action_plan(s.invoice_id,v479_req.payload->>'action',coalesce(v479_req.payload->'lines','[]'::jsonb));
   v479_held:=coalesce((v479_plan->>'net_held')::numeric,0);
   -- What each line offers before the cap, as invoice_action_plan works it
   -- out (its credit and voucher units, else its value up to what it still
   -- holds, a session line up to its sessions' "up to"), now and in the
   -- plan the request saved; whether the refund changes what it offers as it
   -- goes (credit, vouchers or sessions).
   select coalesce(jsonb_agg(jsonb_build_object('src',z.src,'item',z.item,'amount',z.amount,'offer',z.offer,'moving',z.moving)),'[]'::jsonb)
     into v479_offers
     from (select t.src,t.x->>'invoice_item_id' as item,coalesce((t.x->>'amount')::numeric,0) as amount,
                  case when b.ben then coalesce((t.x->>'benefit_backed')::numeric,0)
                       else least(greatest(least(round(coalesce(public.invoice_discounted_line_value((t.x->>'invoice_item_id')::uuid),0)
                                                       *coalesce((t.x->>'selected_quantity')::int,1)/greatest(coalesce((t.x->>'quantity')::int,1),1),2),
                                                 round(coalesce((t.x->>'remaining_value')::numeric,0),2)),0),
                                  case when jsonb_typeof(t.x->'sessions')='object' then round(coalesce((t.x->'sessions'->>'max_refund')::numeric,0),2) end) end as offer,
                  b.ben or jsonb_typeof(t.x->'sessions')='object' as moving
             from (select 'now' as src,x from jsonb_array_elements(coalesce(v479_plan->'lines','[]'::jsonb)) x
                   union all
                   select 'request',x from jsonb_array_elements(coalesce(v479_req.payload->'plan'->'lines','[]'::jsonb)) x) t
             cross join lateral (select coalesce((t.x->>'benefit_backed')::numeric,0)>0 or t.x->>'line_kind' in ('credit_package','premium_bundle')
                                        or exists(select 1 from public.invoice_benefit_values bv
                                                   where bv.invoice_id=s.invoice_id and bv.invoice_item_id::text=t.x->>'invoice_item_id') as ben) b) z;
   select (o->>'offer')::numeric into v479_pre from jsonb_array_elements(v479_offers) o where o->>'src'='now' and o->>'item'=p_item_id::text;
   select coalesce(sum((o->>'offer')::numeric),0),count(*) filter (where (o->>'offer')::numeric>0),count(*),count(*) filter (where (o->>'moving')::boolean)
     into v479_others,v479_pos,v479_lines,v479_moving
     from jsonb_array_elements(v479_offers) o where o->>'src'='now' and o->>'item'<>p_item_id::text;
   -- 479 (the review of 2 Nov 2026; NOT COVERED 17, open for the Owner): a
   -- line holding no credit, vouchers or sessions (a product) that a refund
   -- by line paid back before the invoice was last reopened is offered again
   -- by the plan, for all it holds since the reopening (the reopening charges
   -- the line again); where the plan gives it money its line is refunded a
   -- second time. 478 never does that in a plan that reaches a waiting
   -- session (it refuses the session), and whether it may is the Owner's to
   -- decide: so the session is refused as 478 refuses it, whichever line is
   -- listed first (such a line's offer and its refunds before the reopening
   -- do not change while the approval runs).
   v479_again:=exists(select 1 from jsonb_array_elements(v479_offers) o
                       where o->>'src'='now' and not (o->>'moving')::boolean and (o->>'offer')::numeric>0
                         and exists(select 1 from public.invoice_refunds r cross join lateral jsonb_array_elements(coalesce(r.outcome->'lines','[]'::jsonb)) e
                                     where r.invoice_id=s.invoice_id and e->>'invoice_item_id'=o->>'item'
                                       and r.created_at<=(select i.reopened_at from public.invoices i where i.id=s.invoice_id)));
   if v479_pre is null or v479_again then v479_as478:=true;
   elsif p_amount<v479_pre then v479_as478:=v479_held>p_amount or v479_pos>0;
   elsif v479_pre+v479_others>v479_held then v479_as478:=true;
   elsif v479_lines<2 or v479_moving=0 then v479_as478:=false;
   else
    v479_same:=v479_req.payload->'plan'->>'action' is not distinct from v479_req.payload->>'action'
      and (v479_req.payload->'plan'->>'net_held')::numeric is not distinct from v479_held
      and (select array_agg(o->>'item' order by o->>'item') from jsonb_array_elements(v479_offers) o where o->>'src'='request')
          is not distinct from (select array_agg(o->>'item' order by o->>'item') from jsonb_array_elements(v479_offers) o where o->>'src'='now')
      and exists(select 1 from jsonb_array_elements(v479_offers) o where o->>'src'='request' and o->>'item'=p_item_id::text
                  and (o->>'amount')::numeric=p_amount and (o->>'offer')::numeric=v479_pre)
      and not exists(select 1 from jsonb_array_elements(v479_offers) r join jsonb_array_elements(v479_offers) n on n->>'item'=r->>'item'
                      where r->>'src'='request' and n->>'src'='now' and not (n->>'moving')::boolean
                        and (n->>'offer')::numeric is distinct from (r->>'offer')::numeric)
      and (select sum((o->>'offer')::numeric) from jsonb_array_elements(v479_offers) o where o->>'src'='request')<=v479_held;
    -- 479 (the third fix review, 3 Nov 2026; answer F and the Owner's Q1 of
    -- 29 Oct 2026, a case with no other item to choose between stays as
    -- built): no other line offers anything at this line's turn, and none
    -- offered anything in the plan the request saved. The other lines are
    -- listed at S$0 (a credit or voucher line refunded by line before the
    -- reopening, which the reopening charges again; a product line refunded
    -- by line since, which the guided Cancel keeps), so the outcome does not
    -- follow how many of them there are, nor the line order.
    v479_only:=v479_pos=0 and not exists(select 1 from jsonb_array_elements(v479_offers) o
                                          where o->>'src'='request' and o->>'item'<>p_item_id::text and (o->>'offer')::numeric>0);
    v479_as478:=not (coalesce(v479_same,false) or v479_only);
    -- 479: the saved plan cannot show what a line the refund reached before
    -- this one (one holding credit, vouchers or sessions) offered in the plan
    -- carried out, which may be more than the request saved (credit given
    -- back to it between the request and the approval: the plan carried out
    -- then cut on a line after this one). So where it reads not cut, the
    -- refund goes on and this is checked again once every line is done, at
    -- the refund's own status write (trg_create_therapy_sessions_on_paid),
    -- from the lines the refund recorded it carried out: refused there with
    -- the message 478 refuses it with here (252's checks, as they read here)
    -- where the plan carried out was cut. Where it went on because only this
    -- line has anything to refund but the saved plan is not the one carried
    -- out (by what can be compared), the money that check allows is this
    -- line's own offer: so any money the plan carried out gave another line
    -- refuses it (one that gained credit or vouchers between the request and
    -- the approval and was reached before this one; listed after it, the
    -- saved plan above refuses it), and the line order cannot decide it.
    if not v479_as478 then
     units:=round(p_amount*s.quantity_purchased/s.paid_value_snapshot)::integer;
     v479_chk:=case when coalesce(current_setting('invoice.therapy_plan_check',true),'') like '{%}'
                    then current_setting('invoice.therapy_plan_check',true)::jsonb end;
     perform set_config('invoice.therapy_plan_check',jsonb_build_object('invoice',s.invoice_id,'request',p_request_id,
       'checks',case when v479_chk->>'invoice'=s.invoice_id::text and v479_chk->>'request'=p_request_id::text
                     then v479_chk->'checks' else '[]'::jsonb end
         ||jsonb_build_array(jsonb_build_object('item',p_item_id,'pre',v479_pre,'held',case when v479_same then v479_held else v479_pre end,
             'lines',(select coalesce(jsonb_object_agg(o->>'item',jsonb_build_object('offer',(o->>'offer')::numeric,'moving',(o->>'moving')::boolean)),'{}'::jsonb)
                        from jsonb_array_elements(v479_offers) o where o->>'src'='now' and o->>'item'<>p_item_id::text),
             'message',case when units<=0 or units>s.quantity_purchased-s.quantity_used-s.quantity_refunded
                              or round(s.paid_value_snapshot*(s.quantity_refunded+units)/s.quantity_purchased,2)-round(s.paid_value_snapshot*s.quantity_refunded/s.quantity_purchased,2)<>p_amount
                            then format('Refund whole unused therapy sessions at their original paid value; %s of %s sessions remain refundable',
                                        s.quantity_purchased-s.quantity_used-s.quantity_refunded,s.quantity_purchased)
                            else 'Settle the reopened invoice before changing its queued sessions' end)))::text,true);
    end if;
   end if;
  end if;
 end if;
 if v479_wait>0 and not v479_as478 then
  -- 479: what waits comes back when the invoice is settled: all of what the
  -- session shows as refunded and cancelled but the sessions refunded by
  -- line since the invoice was last reopened (its 'refund' events since
  -- reopened_at). The reopening charges the line again, so here a refund
  -- made before it counts no more (as invoice_charge_total and the refund
  -- options' line amounts count the line's money); one made since does.
  -- The two always add up to what the session shows (the evidence 252's
  -- payment checks); otherwise refused, changing nothing. Whole sessions
  -- are refunded at their original paid value counted from those refunded
  -- since the reopening, up to all but those used and those refunded since:
  -- what the payment would reinstate (and any still available).
  select coalesce(sum(-e.quantity),0)::int into v479_since from public.invoice_therapy_session_events e
   where e.session_id=s.id and e.event_kind='refund'
     and e.created_at>(select i.reopened_at from public.invoices i where i.id=s.invoice_id);
  if v479_wait+v479_since<>s.quantity_refunded+s.quantity_cancelled then
   raise exception 'Therapy session reopening changed; reload its original evidence'; end if;
  units:=round(p_amount*s.quantity_purchased/s.paid_value_snapshot)::integer;
  if units<=0 or units>s.quantity_purchased-s.quantity_used-v479_since
   or round(s.paid_value_snapshot*(v479_since+units)/s.quantity_purchased,2)-round(s.paid_value_snapshot*v479_since/s.quantity_purchased,2)<>p_amount then
   raise exception 'Refund whole unused therapy sessions at their original paid value; % of % sessions remain refundable',s.quantity_purchased-s.quantity_used-v479_since,s.quantity_purchased;
  end if;
  -- 479: the sessions refunded come off what waits, the most recently
  -- queued first (by the reopening's revision), as 446 takes refunded
  -- voucher units off theirs: a row is lowered, or removed when nothing is
  -- left of it (a later reopening queues again what the session shows less
  -- what still waits, 475, so a removed row does not come back whole). Each
  -- change is in the invoice's Audit Log ('reopen_session_refunded'). So the
  -- payment that settles the invoice reinstates only what is still owed.
  v479_take:=least(units,v479_wait);
  v479_left:=v479_take;
  select i.store_id into v479_store from public.invoices i where i.id=s.invoice_id;
  for q479 in select q.* from public.invoice_reopen_sessions q
                left join public.invoice_revisions r on r.invoice_id=q.invoice_id and r.request_id=q.request_id
               where q.session_id=s.id and q.applied_at is null
               order by r.revision_no desc nulls last,q.id desc loop
   exit when v479_left<=0;
   v479_n:=least(q479.quantity,v479_left);
   if v479_n=q479.quantity then
    delete from public.invoice_reopen_sessions where id=q479.id;
   else
    update public.invoice_reopen_sessions set quantity=quantity-v479_n where id=q479.id;
   end if;
   perform public.write_audit_ex('invoices',s.invoice_id,'reopen_session_refunded',to_jsonb(q479),
     jsonb_build_object('reopen_session_id',q479.id,'session_id',s.id,'refunded_units',v479_n,
       'still_waiting',q479.quantity-v479_n,'request_id',p_request_id),
     'refunds',p_reason,v479_store);
   v479_left:=v479_left-v479_n;
  end loop;
  -- 479: a waiting session refunded was cancelled or refunded already: it
  -- now shows as refunded (a cancelled one counted as refunded); one still
  -- available, if any, is refunded as before. The refund's event is written
  -- as before (the settling payment counts it).
  reserve:=least(s.quantity_cancelled,v479_take);
  insert into public.invoice_therapy_session_events(session_id,invoice_id,request_id,event_kind,quantity,before_snapshot,reason,created_by)
  values(s.id,s.invoice_id,p_request_id,'refund',-units,to_jsonb(s),p_reason,auth.uid());
  update public.customer_therapy_sessions set quantity_refunded=quantity_refunded+reserve+units-v479_take,quantity_cancelled=quantity_cancelled-reserve,
   status=case when quantity_purchased-quantity_used-quantity_refunded-quantity_cancelled-units+v479_take>0 then 'available'
     when quantity_used>0 then 'used' else 'refunded' end where id=s.id;
  return;
 end if;
 units:=round(p_amount*s.quantity_purchased/s.paid_value_snapshot)::integer;
 if units<=0 or units>s.quantity_purchased-s.quantity_used-s.quantity_refunded
  or round(s.paid_value_snapshot*(s.quantity_refunded+units)/s.quantity_purchased,2)-round(s.paid_value_snapshot*s.quantity_refunded/s.quantity_purchased,2)<>p_amount then
  raise exception 'Refund whole unused therapy sessions at their original paid value; % of % sessions remain refundable',s.quantity_purchased-s.quantity_used-s.quantity_refunded,s.quantity_purchased;
 end if;
 if exists(select 1 from public.invoice_reopen_sessions where session_id=s.id and applied_at is null) then raise exception 'Settle the reopened invoice before changing its queued sessions'; end if;
 reserve:=least(s.quantity_cancelled,units);
 insert into public.invoice_therapy_session_events(session_id,invoice_id,request_id,event_kind,quantity,before_snapshot,reason,created_by)
 values(s.id,s.invoice_id,p_request_id,'refund',-units,to_jsonb(s),p_reason,auth.uid());
 update public.customer_therapy_sessions set quantity_refunded=quantity_refunded+units,quantity_cancelled=quantity_cancelled-reserve,
  status=case when quantity_purchased-quantity_used-quantity_refunded-units-quantity_cancelled+reserve>0 then 'available'
    when quantity_used>0 then 'used' else 'refunded' end where id=s.id;
end $function$
$d1$;
  c_def_correct constant text := $d2$CREATE OR REPLACE FUNCTION public.correct_invoice_therapy_sessions(p_invoice_id uuid, p_items jsonb, p_customer uuid, p_store uuid, p_reason text, p_request uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.customer_therapy_sessions%rowtype; x jsonb; changed boolean; it public.invoice_items%rowtype;
 v479_from uuid; v479_since integer; v479_follow uuid[]:='{}';
begin
 -- 479 (the Owner, 27 Oct 2026, answer F: "allow ... customer change while
 -- reopened therapy sessions wait (sessions ... follow the new customer)"):
 -- the invoice's customer before this correction (correct_invoice saves the
 -- new one after this runs).
 select i.customer_id into v479_from from public.invoices i where i.id=p_invoice_id;
 for s in select * from public.customer_therapy_sessions where invoice_id=p_invoice_id and is_current order by id for update loop
  select value into x from jsonb_array_elements(p_items) where value->>'invoice_item_id'=s.invoice_item_id::text;
  select * into it from public.invoice_items where id=s.invoice_item_id;
  -- 479: the session's customer changes when the correction changes the
  -- invoice's customer to someone other than the session's holder (before
  -- 479, when it is not the session's holder: the invoice's customer was
  -- always the holder then, so it is the same test), so sessions a customer
  -- change left with their holder ('keep', below) are not taken by a later
  -- correction that keeps the invoice's customer, or sets it back to them.
  changed:=x is null or (nullif(x->>'therapy_service_id','')::uuid,(x->>'quantity')::integer,p_store)
    is distinct from (s.service_id,s.quantity_purchased,s.store_id)
    or p_customer is distinct from v479_from and p_customer is distinct from s.customer_id;
  if not changed then continue; end if;
  if s.quantity_used>0 then raise exception 'Used therapy sessions must keep their original customer, service and invoice allocation; correct only unused purchases'; end if;
  if exists(select 1 from public.invoice_reopen_sessions where session_id=s.id and applied_at is null) then
   -- 479: a session whose reopening waits (or once its invoice was cancelled
   -- again) keeps its line, quantity and store (refused as before 479); its
   -- customer may change. It is not closed and replaced: it waits as it is,
   -- and belongs to whoever holds the invoice's benefits now (460's rule):
   -- the new customer after a 'transfer', the holder after a 'keep', the new
   -- customer where no such choice is asked (below). It follows at this
   -- correction's end, when the invoice's status is written
   -- (trg_create_therapy_sessions_on_paid). What it shows and what waits for
   -- it must still add up (252's evidence, counting refunds since the
   -- reopening); otherwise refused.
   if x is null or (nullif(x->>'therapy_service_id','')::uuid,(x->>'quantity')::integer,p_store)
        is distinct from (s.service_id,s.quantity_purchased,s.store_id) then
    raise exception 'Settle the pending session reopening before changing its allocation'; end if;
   select coalesce(sum(-e.quantity),0)::int into v479_since from public.invoice_therapy_session_events e
    where e.session_id=s.id and e.event_kind='refund'
      and e.created_at>(select i.reopened_at from public.invoices i where i.id=p_invoice_id);
   if (select coalesce(sum(q.quantity),0) from public.invoice_reopen_sessions q where q.session_id=s.id and q.applied_at is null)
      +v479_since<>s.quantity_refunded+s.quantity_cancelled then
    raise exception 'Therapy session reopening changed; reload its original evidence'; end if;
   v479_follow:=v479_follow||s.id;
   continue;
  end if;
  -- 479: sessions a customer change left with their holder ('keep') while
  -- their reopening waited are not the invoice's customer's: changing their
  -- line, quantity or store, or the invoice's customer to someone else,
  -- would give them to the invoice's customer. Refused, changing nothing
  -- (for the Owner); removing their line closes them, as before.
  if s.customer_id is distinct from v479_from and x is not null then
   raise exception 'These therapy sessions were left with % when the invoice''s customer was changed, so their line, quantity or store cannot be changed, nor the invoice moved to another customer, from this invoice: set the invoice''s customer back to them first. Nothing was changed.',
     coalesce((select c.full_name from public.customers c where c.id=s.customer_id),'their holder'); end if;
  insert into public.invoice_therapy_session_events(session_id,invoice_id,request_id,event_kind,quantity,before_snapshot,reason,created_by)
   values(s.id,s.invoice_id,p_request,'correction',-(s.quantity_purchased-s.quantity_refunded-s.quantity_cancelled),to_jsonb(s),coalesce(p_reason,'Invoice correction'),auth.uid());
  update public.customer_therapy_sessions set is_current=false,status='cancelled',quantity_cancelled=quantity_purchased-quantity_refunded where id=s.id;
 end loop;
 -- 479: waiting sessions whose customer changed on an invoice that asks no
 -- 'transfer' or 'keep' (it issued no credit or vouchers: correct_invoice's
 -- own test, invoice_transferable_benefits, as it read before this ran)
 -- follow the change, as on a paid invoice. Recorded as move_invoice_
 -- benefits_to_customer records a change that takes the invoice's benefits
 -- along ('invoice_benefits_followed_reassignment', to_customer), which is
 -- what 460's rule reads.
 if cardinality(v479_follow)>0 and not exists(select 1 from public.invoice_transferable_benefits(p_invoice_id)) then
  perform public.write_audit_ex('invoices',p_invoice_id,'invoice_benefits_followed_reassignment',null,
    jsonb_build_object('vouchers','[]'::jsonb,'credit_lots','[]'::jsonb,'allowances','[]'::jsonb,
      'therapy_sessions',to_jsonb(v479_follow),'to_customer',p_customer,'reason',p_reason),
    'invoices',p_reason,p_store);
 end if;
end $function$
$d2$;
  c_def_trigger constant text := $d3$CREATE OR REPLACE FUNCTION public.trg_create_therapy_sessions_on_paid()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.customer_therapy_sessions%rowtype; q record; unused integer;
 v479_wait integer; v479_since integer; v479_to uuid;
 v479_raw text; v479_lines jsonb; v479_c jsonb; v479_items text[]; v479_before numeric; v479_after numeric;
begin
 -- 479 (the Owner, 29 Oct 2026 ~18:45 SGT, "Keep today's refusal"): a guided
 -- flow's refund of a waiting session that went on because the plan its
 -- request saved was not cut (refund_invoice_therapy_sessions, which leaves
 -- this check in invoice.therapy_plan_check) is checked again at the
 -- refund's own status write, once every line is done: refund_invoice_
 -- recorded has then recorded the lines it carried out, in the order it
 -- carried them out (invoice_refunds, the request's row with the lines). A
 -- line before the session's was given all it offered (at what it was given;
 -- one holding no credit, vouchers or sessions at what it offered at the
 -- session's turn, as the refund changes nothing it holds); a line after it
 -- offered what it offered at the session's turn (the refund had not reached
 -- it). Where those offers come to more than the money held, the plan
 -- carried out was cut and gave the waiting session part of the money while
 -- another line had something to refund: refused with the message 478
 -- refuses it with at the session's turn, changing nothing.
 v479_raw:=current_setting('invoice.therapy_plan_check',true);
 if v479_raw like '{%}' and (v479_raw::jsonb)->>'invoice'=new.id::text then
  select r.outcome->'lines' into v479_lines from public.invoice_refunds r
   where r.invoice_id=new.id and r.request_id=((v479_raw::jsonb)->>'request')::uuid and jsonb_typeof(r.outcome->'lines')='array'
   order by r.created_at limit 1;
  if v479_lines is not null then
   perform set_config('invoice.therapy_plan_check','',true);
   for v479_c in select c from jsonb_array_elements((v479_raw::jsonb)->'checks') c loop
    select coalesce(sum(case when not coalesce((v479_c->'lines'->(x.l->>'invoice_item_id')->>'moving')::boolean,true)
                             then (v479_c->'lines'->(x.l->>'invoice_item_id')->>'offer')::numeric
                             when jsonb_typeof(x.l->'benefits')='array' and jsonb_array_length(x.l->'benefits')>0
                             then (select sum((b->>'amount')::numeric) from jsonb_array_elements(x.l->'benefits') b)
                             else (x.l->>'amount')::numeric end),0),
           coalesce(array_agg(x.l->>'invoice_item_id'),'{}')
      into v479_before,v479_items
      from jsonb_array_elements(v479_lines) with ordinality x(l,o)
     where x.o<(select min(y.o) from jsonb_array_elements(v479_lines) with ordinality y(l,o) where y.l->>'invoice_item_id'=v479_c->>'item');
    select coalesce(sum((e.value->>'offer')::numeric),0) into v479_after
      from jsonb_each(v479_c->'lines') e where not (e.key=any(v479_items));
    if v479_before+(v479_c->>'pre')::numeric+v479_after>(v479_c->>'held')::numeric then
     raise exception '%',v479_c->>'message'; end if;
   end loop;
  end if;
 end if;
 -- 479 (the Owner, 27 Oct 2026, answer F: "customer change while reopened
 -- therapy sessions wait (sessions ... follow the new customer)"): a session
 -- waiting for a reopening's payment, or once its invoice was cancelled again
 -- before it was paid, belongs to whoever holds the invoice's benefits now,
 -- as what a reopening gives back does (460's rule, with 462's fall-backs
 -- for a deleted record: invoice_credit_live_holder): the new customer after
 -- a customer change that took the benefits along ('transfer', or one with
 -- no such choice, correct_invoice_therapy_sessions), its holder after a
 -- 'keep', the record a merge kept. It follows whenever the invoice's status
 -- is written (a correction writes it last, after it moved the benefits), in
 -- place, with its counts and its waiting rows; an event and the invoice's
 -- Audit Log ('reopen_sessions_follow_holder') record it. Read first without
 -- locks: only where a waiting session must follow someone else are its
 -- waiting rows and the sessions locked and read again, so a status write
 -- that moves nothing (a part payment, Correct payment) locks no session, as
 -- before 479 (a merge locks the sessions before the invoice).
 if exists(select 1 from public.invoice_reopen_sessions w
            join public.customer_therapy_sessions x on x.id=w.session_id and x.is_current
            cross join lateral (select public.invoice_credit_live_holder(new.id,x.customer_id,x.created_at) as h) l
            where w.invoice_id=new.id and w.applied_at is null and l.h is not null and l.h<>x.customer_id) then
  perform 1 from public.invoice_reopen_sessions where invoice_id=new.id and applied_at is null order by id for update;
  for s in select x.* from public.customer_therapy_sessions x
            where x.is_current and x.id in (select w.session_id from public.invoice_reopen_sessions w where w.invoice_id=new.id and w.applied_at is null)
            order by x.id for update loop
   v479_to:=public.invoice_credit_live_holder(new.id,s.customer_id,s.created_at);
   continue when v479_to is null or v479_to=s.customer_id;
   insert into public.invoice_therapy_session_events(session_id,invoice_id,event_kind,quantity,before_snapshot,reason,created_by)
    values(s.id,new.id,'reassign',0,to_jsonb(s),'Waiting for a reopening''s payment; follows whoever holds the invoice''s benefits now',auth.uid());
   update public.customer_therapy_sessions set customer_id=v479_to where id=s.id;
   perform public.write_audit_ex('invoices',new.id,'reopen_sessions_follow_holder',
     jsonb_build_object('session_id',s.id,'customer_id',s.customer_id),
     jsonb_build_object('session_id',s.id,'customer_id',v479_to,
       'waiting',(select sum(w.quantity) from public.invoice_reopen_sessions w where w.session_id=s.id and w.applied_at is null)),
     'invoices','Therapy sessions waiting for a reopening''s payment follow whoever holds the invoice''s benefits',new.store_id);
  end loop;
 end if;
 if new.status in ('paid','completed_foc') then
  -- Only an explicit reopening queues reinstatement. An ordinary terminal edit
  -- cannot cause this branch to restore refunded or cancelled rights.
  -- 479: per session, all that waits for it is reinstated but what was
  -- refunded by line since the invoice was last reopened (its 'refund' events
  -- since reopened_at; refund_invoice_therapy_sessions took it off the
  -- queue): those stay refunded, nothing stays cancelled. The evidence is
  -- 252's, counting those refunds: what waits and what was refunded since add
  -- up to what the session shows (with nothing refunded since, as before:
  -- what waits is what it shows); otherwise refused, changing nothing.
  perform 1 from public.invoice_reopen_sessions where invoice_id=new.id and applied_at is null order by id for update;
  for s in select x.* from public.customer_therapy_sessions x
            where x.id in (select w.session_id from public.invoice_reopen_sessions w where w.invoice_id=new.id and w.applied_at is null)
            order by x.id for update loop
   select coalesce(sum(w.quantity),0)::int into v479_wait from public.invoice_reopen_sessions w
    where w.session_id=s.id and w.invoice_id=new.id and w.applied_at is null;
   select coalesce(sum(-e.quantity),0)::int into v479_since from public.invoice_therapy_session_events e
    where e.session_id=s.id and e.event_kind='refund' and e.created_at>new.reopened_at;
   if not s.is_current or v479_wait+v479_since<>s.quantity_refunded+s.quantity_cancelled then raise exception 'Therapy session reopening changed; reload its original evidence'; end if;
   for q in select * from public.invoice_reopen_sessions w where w.session_id=s.id and w.invoice_id=new.id and w.applied_at is null order by w.id loop
    insert into public.invoice_therapy_session_events(session_id,invoice_id,request_id,event_kind,quantity,before_snapshot,reason,created_by)
     values(s.id,new.id,q.request_id,'reopen',q.quantity,to_jsonb(s),'Explicit reopening settled',auth.uid());
    update public.invoice_reopen_sessions set applied_at=clock_timestamp() where id=q.id;
   end loop;
   update public.customer_therapy_sessions set quantity_refunded=v479_since,quantity_cancelled=0,status='available' where id=s.id;
  end loop;
  perform public.create_therapy_sessions_for_invoice(new.id);
 end if;
 if new.status='cancelled' and old.status is distinct from new.status then
  for s in select * from public.customer_therapy_sessions where invoice_id=new.id and is_current order by id for update loop
   unused:=s.quantity_purchased-s.quantity_used-s.quantity_refunded-s.quantity_cancelled;
   if unused<=0 then continue; end if;
   insert into public.invoice_therapy_session_events(session_id,invoice_id,event_kind,quantity,before_snapshot,reason,created_by)
    values(s.id,new.id,'cancel',-unused,to_jsonb(s),'Invoice cancelled; payments remain separately recorded',auth.uid());
   update public.customer_therapy_sessions set quantity_cancelled=quantity_cancelled+unused,
    status=case when quantity_used>0 then 'used' else 'cancelled' end where id=s.id;
  end loop;
 end if;
 return null;
end $function$
$d3$;

  -- ══ Relied on, not changed (production at 478, 29 Oct 2026, as on its
  -- copy, and the same at 485, 2 Nov 2026): who calls the three; what a reopening queues and what the Reopen
  -- dialog says; the guided flows and what their plans offer (the refund
  -- options, kept as they are: the Owner, 29 Oct 2026); whom the benefits
  -- belong to (460, 462) and what a customer change asks and writes (476's);
  -- what moves a session's customer besides (a merge); the money the line
  -- follows; what the refund reads of a guided plan (invoice_action_plan,
  -- the line's value: the Owner, 29 Oct 2026, "Keep today's refusal"); the
  -- self-test's calls ═════════════════════════════════════════════════════
  c_relied constant text[] := array[
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'invoice_action_plan(uuid,text,jsonb)',
    'resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)',
    'request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)',
    'invoice_refund_options(uuid)',
    'reopen_invoice(uuid,text,uuid)',
    'invoice_reopen_preview(uuid)',
    'invoice_reopen_preview_before_sessions(uuid)',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'create_therapy_sessions_for_invoice(uuid)',
    'invoice_credit_live_holder(uuid,uuid,timestamp with time zone)',
    'invoice_benefits_holder(uuid,uuid,timestamp with time zone)',
    'invoice_transferable_benefits(uuid)',
    'move_invoice_benefits_to_customer(uuid,uuid,uuid,text)',
    'merge_customer_records(uuid,uuid,text,uuid)',
    'apply_reopened_invoice_vouchers()',
    'invoice_refund_options_before_sessions(uuid)',
    'invoice_charge_total(uuid)',
    'invoice_discounted_line_value(uuid)',
    'invoice_financial_position(uuid)',
    'invoice_net_received(uuid)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'is_owner_or_manager()',
    'user_has_store_access(uuid)',
    'normalize_customer_phone(text)',
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    'record_invoice_payment(uuid,jsonb,uuid)'];
  c_relied_md5 constant text[] := array[
    '804ecd829cfecf713783a09a05d93c7e',
    '04d647e13e9424a9375942e5812e91a2',
    '383d618edb28c3c9a360242d038a022c',
    '201f08ebf14a64cd88d411a7cfb4c9c4',
    '4360d74462ed1fc950b6bd8b5157b3ae',
    '689a71c246260d2c10ec44dd94eb7139',
    '30066e137b9b75b5789a050c14debc04',
    'e09ebf9c0841ef5463f96b26f4933541',
    'acbfc38a20a000e1af0e78d26fc7fc4c',
    'de52d9dbaef8ab15163bef35cb9d733d',
    'c0a45b7ce309cb9b4ceea53b212bd4aa',
    'a5692590ef3e8a7a7dd7e8ff7cfa9568',
    '55995ff6e1ffd4a1172cb930512a34b0',
    '1546de1f83d970424d26e65941f4dcb8',
    '142dd3252911480bd4a17e7c55b488d3',
    'ba05c2b1fb4c0e14d369c01d06a635b0',
    '6684840544d1ad8a28e2415934300054',
    'bd3afcc79cd2f06f983607d54fed167c',
    '8297147511ba285db2279598f3d727fb',
    'ead4a430c3abd1e3f953912867ca4fe6',
    'ba7eccbfeff217c8b1969b0e55a010ca',
    'f256bea69b7defa38a950753bbc248da',
    'c705c733e213a27f0dc32d54322cc855',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    '708992afaa6c3951f6329239b742987c',
    'b2bfac910e0c9eff402ba44e19750bee',
    '80c80d386a5241e63b353e35e13ef250',
    '9c70097ed4da614fb9dcc66fdfcdb7d6'];
  -- The trigger that runs the settlement's step, as read.
  c_trigger constant text := 'CREATE TRIGGER create_therapy_sessions_on_paid AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_create_therapy_sessions_on_paid()';
  -- What reads or writes the session queue, what updates the sessions, what
  -- reads or writes their events, what sets reopened_at, what writes or reads
  -- 460's row (by name; a session's own temporary functions are not
  -- counted): as read before 479, and as 479 leaves them.
  c_queue_users constant text := 'correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid), refund_invoice_therapy_sessions(uuid,numeric,text,uuid), reopen_invoice(uuid,text,uuid), trg_create_therapy_sessions_on_paid()';
  c_queue_writers_before constant text := 'reopen_invoice(uuid,text,uuid), trg_create_therapy_sessions_on_paid()';
  c_queue_writers_after constant text := 'refund_invoice_therapy_sessions(uuid,numeric,text,uuid), reopen_invoice(uuid,text,uuid), trg_create_therapy_sessions_on_paid()';
  c_session_writers constant text := 'correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid), refund_invoice_therapy_sessions(uuid,numeric,text,uuid), trg_create_therapy_sessions_on_paid()';
  c_event_users constant text := 'correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid), refund_invoice_therapy_sessions(uuid,numeric,text,uuid), trg_create_therapy_sessions_on_paid()';
  c_event_writers constant text := 'correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid), refund_invoice_therapy_sessions(uuid,numeric,text,uuid), trg_create_therapy_sessions_on_paid()';
  c_reopened_writers constant text := 'reopen_invoice(uuid,text,uuid)';
  c_follow_users_before constant text := 'invoice_benefits_holder(uuid,uuid,timestamp with time zone), move_invoice_benefits_to_customer(uuid,uuid,uuid,text)';
  c_follow_users_after constant text := 'correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid), invoice_benefits_holder(uuid,uuid,timestamp with time zone), move_invoice_benefits_to_customer(uuid,uuid,uuid,text)';
  -- What reads or writes the check a guided flow's refund leaves for the
  -- refund's status write (invoice.therapy_plan_check): 479's two alone.
  c_check_users_after constant text := 'refund_invoice_therapy_sessions(uuid,numeric,text,uuid), trg_create_therapy_sessions_on_paid()';
  -- Who calls the three (a function's callers by name; the trigger's by the
  -- trigger alone).
  c_callers constant text[] := array[
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    null];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; i int; n_before int := 0; n_after int := 0; v_first boolean; v_acl text[] := '{}';
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_svc uuid; t_vou uuid;
  t_case int; t_a uuid; t_b uuid; t_c uuid; t_inv uuid; t_item uuid; t_vitem uuid; t_pay uuid; t_s uuid; t_ev0 int;
  t_lines jsonb; t_msg text; t_opt jsonb; t_plan jsonb; t_req jsonb; t_res jsonb; t_try int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The texts are the tested ones.
  if md5(c_def_refund) <> c_after[1] or md5(c_def_correct) <> c_after[2]
     or md5(c_def_trigger) <> c_after[3] then
    raise exception '479: the texts in this file are not the tested ones'; end if;

  -- The functions relied on are as read (production at 478, 29 Oct 2026,
  -- and the same at 485, 2 Nov 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '479: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying (479 goes in after 476, 477 and 478).',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if (select string_agg(pg_get_triggerdef(t.oid), E'\n' order by t.tgname) from pg_trigger t
       where t.tgrelid = 'public.invoices'::regclass and t.tgfoid = 'public.trg_create_therapy_sessions_on_paid()'::regprocedure)
     is distinct from c_trigger then
    raise exception '479: the trigger that runs a reopening''s therapy sessions at settlement is not as read on 29 Oct 2026'; end if;

  -- The columns read, with these types (the approval request and the
  -- benefit rows: what the refund reads of a guided plan); the events
  -- stamped by clock_timestamp(); one queue row per session and reopening,
  -- of a quantity above 0.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('invoice_reopen_sessions', 'id', 'uuid'), ('invoice_reopen_sessions', 'invoice_id', 'uuid'),
                 ('invoice_reopen_sessions', 'session_id', 'uuid'), ('invoice_reopen_sessions', 'request_id', 'uuid'),
                 ('invoice_reopen_sessions', 'quantity', 'integer'), ('invoice_reopen_sessions', 'applied_at', 'timestamp with time zone'),
                 ('customer_therapy_sessions', 'id', 'uuid'), ('customer_therapy_sessions', 'customer_id', 'uuid'),
                 ('customer_therapy_sessions', 'invoice_id', 'uuid'), ('customer_therapy_sessions', 'invoice_item_id', 'uuid'),
                 ('customer_therapy_sessions', 'service_id', 'uuid'), ('customer_therapy_sessions', 'store_id', 'uuid'),
                 ('customer_therapy_sessions', 'quantity_purchased', 'integer'), ('customer_therapy_sessions', 'quantity_used', 'integer'),
                 ('customer_therapy_sessions', 'quantity_refunded', 'integer'), ('customer_therapy_sessions', 'quantity_cancelled', 'integer'),
                 ('customer_therapy_sessions', 'paid_value_snapshot', 'numeric(12,2)'), ('customer_therapy_sessions', 'status', 'text'),
                 ('customer_therapy_sessions', 'is_current', 'boolean'), ('customer_therapy_sessions', 'created_at', 'timestamp with time zone'),
                 ('invoice_therapy_session_events', 'session_id', 'uuid'), ('invoice_therapy_session_events', 'invoice_id', 'uuid'),
                 ('invoice_therapy_session_events', 'request_id', 'uuid'), ('invoice_therapy_session_events', 'event_kind', 'text'),
                 ('invoice_therapy_session_events', 'quantity', 'integer'), ('invoice_therapy_session_events', 'before_snapshot', 'jsonb'),
                 ('invoice_therapy_session_events', 'created_at', 'timestamp with time zone'),
                 ('invoices', 'reopened_at', 'timestamp with time zone'), ('invoices', 'customer_id', 'uuid'),
                 ('invoices', 'store_id', 'uuid'), ('invoice_revisions', 'request_id', 'uuid'),
                 ('invoice_revisions', 'revision_no', 'integer'),
                 ('approval_requests', 'id', 'uuid'), ('approval_requests', 'status', 'approval_status'),
                 ('approval_requests', 'related_record_id', 'uuid'), ('approval_requests', 'request_type', 'text'),
                 ('approval_requests', 'payload', 'jsonb'),
                 ('invoice_benefit_values', 'invoice_id', 'uuid'), ('invoice_benefit_values', 'invoice_item_id', 'uuid'),
                 ('invoice_refunds', 'invoice_id', 'uuid'), ('invoice_refunds', 'request_id', 'uuid'),
                 ('invoice_refunds', 'outcome', 'jsonb'), ('invoice_refunds', 'created_at', 'timestamp with time zone')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '479: these columns are missing or not as read on 29 Oct 2026: %', v; end if;
  if (select pg_get_expr(ad.adbin, ad.adrelid) from pg_attrdef ad
       join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum
      where ad.adrelid = 'public.invoice_therapy_session_events'::regclass and a.attname = 'created_at')
     is distinct from 'clock_timestamp()' then
    raise exception '479: the therapy session events are not stamped by clock_timestamp() as read on 29 Oct 2026 (what was refunded since a reopening is read by it)'; end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.invoice_reopen_sessions'::regclass and contype = 'u'
                  and pg_get_constraintdef(oid) = 'UNIQUE (session_id, request_id)')
     or not exists (select 1 from pg_constraint where conrelid = 'public.invoice_reopen_sessions'::regclass and contype = 'c'
                  and pg_get_constraintdef(oid) = 'CHECK ((quantity > 0))') then
    raise exception '479: the session queue''s keys are not as read on 29 Oct 2026 (one row per session and reopening, of a quantity above 0)'; end if;

  -- No other function takes their names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = any (c_names)
     and not (p.oid::regprocedure::text = any (c_sigs));
  if v is not null then raise exception '479: another function takes the name of one this changes: %', v; end if;

  -- Who calls them, as read.
  for i in 1 .. cardinality(c_sigs) loop
    select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where p.prosrc ~ (c_names[i] || '\s*\(') and ns.nspname not like 'pg\_temp\_%' and p.proname <> c_names[i];
    if v is distinct from c_callers[i] then
      raise exception '479: public.% is called by % (as read on 29 Oct 2026: %); check how each calls it, then re-test', c_sigs[i], coalesce(v, 'nothing'), coalesce(c_callers[i], 'nothing'); end if;
  end loop;
  if (select count(*) from pg_trigger t where t.tgfoid = 'public.trg_create_therapy_sessions_on_paid()'::regprocedure) <> 1 then
    raise exception '479: trg_create_therapy_sessions_on_paid runs from other triggers than the one read on 29 Oct 2026'; end if;

  -- The three: all at their BEFORE (replaced) or all at their AFTER (left
  -- alone); anything else refused.
  for i in 1 .. cardinality(c_sigs) loop
    d := pg_get_functiondef(to_regprocedure('public.' || c_sigs[i]));
    if md5(d) = c_before[i] then n_before := n_before + 1;
    elsif md5(d) = c_after[i] then n_after := n_after + 1;
    else
      raise exception '479: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sigs[i], md5(d);
    end if;
  end loop;
  if n_after = cardinality(c_sigs) then
    raise notice '479: the three functions are already this version; left alone';
    v_first := false;
  elsif n_before = cardinality(c_sigs) then
    v_first := true;
  else
    raise exception '479: some of the three functions are at their BEFORE and some at their AFTER (% and %); a partial install, not as tested', n_before, n_after;
  end if;

  -- What reads or writes the session queue, updates the sessions, reads or
  -- writes their events, sets reopened_at, writes or reads 460's row: as
  -- read (a new way would need the same care).
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'invoice_reopen_sessions' and ns.nspname not like 'pg\_temp\_%';
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+public\.invoice_reopen_sessions' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_queue_users
     or d is distinct from (case when v_first then c_queue_writers_before else c_queue_writers_after end) then
    raise exception '479: what reads or writes the session queue (invoice_reopen_sessions) is not as read on 29 Oct 2026 (% / %); check what it queues and reinstates, then re-test', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'update\s+(public\.)?customer_therapy_sessions' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_session_writers then
    raise exception '479: what updates the therapy sessions (customer_therapy_sessions) is not as read on 29 Oct 2026 (%); check what it changes, then re-test', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'invoice_therapy_session_events' and ns.nspname not like 'pg\_temp\_%';
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'insert\s+into\s+public\.invoice_therapy_session_events' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_event_users
     or d is distinct from c_event_writers then
    raise exception '479: what reads or writes the therapy session events is not as read on 29 Oct 2026 (% / %); what was refunded since a reopening is read from them, so check it, then re-test', v, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'reopened_at\s*=' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_reopened_writers then
    raise exception '479: what sets an invoice''s reopened_at is not as read on 29 Oct 2026 (%); what was refunded since a reopening is read by it, so check it, then re-test', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'invoice_benefits_followed_reassignment' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from (case when v_first then c_follow_users_before else c_follow_users_after end) then
    raise exception '479: what writes or reads the record of a customer change that takes the benefits along (invoice_benefits_followed_reassignment) is not as read on 29 Oct 2026 (%); check it, then re-test', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'invoice\.therapy_plan_check' and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from (case when v_first then null else c_check_users_after end) then
    raise exception '479: what reads or writes invoice.therapy_plan_check (the check a guided flow''s refund of a waiting session leaves for the refund''s status write) is not as 479 leaves it (%); check it, then re-test', v; end if;

  -- ── On the first run: nothing is refused for the data (479 needs no
  -- decision before it goes in), but what changes and what needs the Owner
  -- is named (the header's read-only query, the same text: 1 and 3 change,
  -- 2 is for the Owner).
  if v_first then
    select string_agg(format('%s: %s invoice(s) (%s)', f.reason, f.n, f.nos), '; ' order by f.reason) into v
      from (select left(q.reason, 1) as reason, count(*) as n, string_agg(q.invoice_no, ', ' order by q.invoice_no) as nos
              from (
with
-- therapy sessions waiting for their invoice's reopening to be paid (or once
-- it was cancelled or refunded again): per session, what waits, what was
-- refunded by line since the invoice was last reopened, what it shows as
-- refunded and cancelled
w as (
  select q.invoice_id, q.session_id, q.waits,
         s.quantity_refunded + s.quantity_cancelled as shows,
         coalesce((select sum(-e.quantity) from public.invoice_therapy_session_events e
                    where e.session_id = q.session_id and e.event_kind = 'refund'
                      and e.created_at > i.reopened_at), 0) as since
    from (select invoice_id, session_id, sum(quantity) as waits from public.invoice_reopen_sessions
           where applied_at is null group by invoice_id, session_id) q
    join public.customer_therapy_sessions s on s.id = q.session_id
    join public.invoices i on i.id = q.invoice_id),
found(reason, invoice_id, n) as (
  select '1 changes: a therapy session waiting for its invoice''s reopening to be paid, the invoice part-paid or unpaid, or cancelled or refunded again: its refund by line and a customer change keeping its line and store were refused before 479, and so were the guided Cancel with "Record refund paid" and the guided Refund in full where their plan refunded some of it; from 479 they go through, the refund taking its sessions off what waits, the change giving them to whoever holds the invoice''s benefits, the guided ones where their plan comes out in whole sessions and voucher units at the value 479 gives the sessions (NOT COVERED 14), offering as before no session a refund by line paid back before the reopening (the Owner, 29 Oct 2026), and refused as before 479 where their plan was cut to the money held and another of its lines had something to refund (the Owner, 29 Oct 2026, "Keep today''s refusal") (the count is of sessions)', i.id, count(*)
    from public.invoices i join w on w.invoice_id = i.id
   where i.deleted_at is null and w.waits + w.since = w.shows
   group by i.id
  union all
  select '2 for the Owner (not changed by 479: 475''s NOT COVERED 3 and 4): a waiting therapy session whose waiting rows and refunds since the reopening do not add up to what it shows; the payment that settles the invoice is refused before 479 and after it, and from 479 its refund by line and customer change are too ("Therapy session reopening changed; reload its original evidence") (the count is of sessions)', i.id, count(*)
    from public.invoices i join w on w.invoice_id = i.id
   where i.deleted_at is null and w.waits + w.since <> w.shows
   group by i.id
  union all
  select '3 changes: a current therapy session held by someone other than its invoice''s customer (no function made one before 479): not waiting, a correction of the invoice gave it to the invoice''s customer as new sessions before 479, and from 479 one that changes its line, quantity or store, or moves the invoice to a customer other than its holder, is refused, and one that changes none of them leaves it; still waiting for its reopening''s payment, every correction was refused before 479, and from 479 one that moves the invoice to another customer goes through, the session following 460''s rule, one that changes its line, quantity or store is refused, and one that changes none of them leaves it (the count is of sessions)', i.id, count(*)
    from public.invoices i join public.customer_therapy_sessions s on s.invoice_id = i.id and s.is_current
   where i.deleted_at is null and s.customer_id is distinct from i.customer_id
   group by i.id)
select f.reason, i.invoice_no, f.n
  from found f join public.invoices i on i.id = f.invoice_id
 order by f.reason, i.invoice_no
                   ) q
             group by left(q.reason, 1)) f;
    if v is not null then
      raise notice '479: the header''s query lists %: 1, a waiting session''s refund by line and a customer change now go through, and the guided Cancel and Refund in full where their plan refunds the session in whole sessions and voucher units at the value 479 gives them (NOT COVERED 14; sessions a refund by line paid back before the reopening are not offered again: the Owner, 29 Oct 2026; a plan cut to the money held with another line to refund is refused as before 479: the Owner, 29 Oct 2026, "Keep today''s refusal"); 3, a session held by someone other than its invoice''s customer is no longer given to the invoice''s customer by a correction (while it waits, a move to another customer gives it to whoever holds the invoice''s benefits); 2 is for the Owner (475''s NOT COVERED 3 and 4), not changed by 479', v;
    end if;
  end if;

  -- Who may call each, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  for i in 1 .. cardinality(c_sigs) loop
    if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i]))
       is distinct from (select array_agg(x::text order by x::text) from unnest(c_acl[i]::aclitem[]) x) then
      raise exception '479: who may call public.% is not as read on 29 Oct 2026 (%)', c_sigs[i],
        (select proacl::text from pg_proc where oid = to_regprocedure('public.' || c_sigs[i])); end if;
    v_acl := v_acl || (select coalesce(string_agg(x::text, ',' order by x::text), '')
                         from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i]));
  end loop;

  -- ── Change ──────────────────────────────────────────────────────────────
  if v_first then
    execute c_def_refund;
    execute c_def_correct;
    execute c_def_trigger;
  end if;

  -- ── Afterwards: installed exactly as tested, grants as before ───────────
  for i in 1 .. cardinality(c_sigs) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[i]))) <> c_after[i] then
      raise exception '479: public.% is not at its AFTER md5 (%)', c_sigs[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[i]))); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i])) is distinct from v_acl[i] then
      raise exception '479: the grants of public.% changed', c_sigs[i]; end if;
  end loop;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("479 check", @example.com, fictional ACMA phones
  -- no customer uses); it ends by raising P0479, which undoes all it wrote.
  -- 462's trigger runs at commit; here at each step's end (SET CONSTRAINTS
  -- ... IMMEDIATE), as a commit would.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from generate_series(700, 799) g, lateral (select '+61491570' || g::text as p) x
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p desc limit 10);
    if coalesce(cardinality(t_phones), 0) < 10 then raise exception '479: the self-test found no ten unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '479-check-' || t_sfx || '@example.com') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '479 check', '479-check-' || t_sfx || '@example.com', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('479 check ' || t_sfx, '479-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('479 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.therapy_services (service_code, name, standard_price, duration_minutes, is_active)
    values ('479-' || t_sfx, '479 check ' || t_sfx, 20, 30, true) returning id into t_svc;
    insert into public.therapy_service_stores (service_id, store_id, is_available) values (t_svc, t_store, true);
    insert into public.vouchers (name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('479 check ' || t_sfx, '479-' || t_sfx, 'normal', 'unlimited', 30, true) returning id into t_vou;
    insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store) values (t_vou, t_store, 30, true);

    for t_case in 1 .. 7 loop
      -- A 3-session line at S$20 (and, in (d) to (g), a S$30 voucher line)
      -- sold to A and paid; cancelled; S$20 of the therapy line refunded by
      -- line (in (e) all of it, S$60; in (f) all S$90 paid back with no line,
      -- "Record refund paid"); reopened (the sessions waiting).
      insert into public.customers (full_name, phone)
      values ('479 Check Buyer ' || t_case || ' ' || t_sfx,
              t_phones[case t_case when 1 then 1 when 2 then 2 when 3 then 3 when 4 then 5 when 5 then 8 when 6 then 9 else 10 end])
      returning id into t_a;
      t_inv := public.create_invoice(t_store, t_a, null::uuid,
        jsonb_build_array(jsonb_build_object('kind', 'therapy', 'therapy_service_id', t_svc, 'quantity', 3))
          || case when t_case >= 4 then jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', t_vou, 'quantity', 1))
                  else '[]'::jsonb end,
        0::numeric, null::text, null::uuid, '[]'::jsonb);
      perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
        'amount', (select total_amount from public.invoices where id = t_inv))), gen_random_uuid());
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      select s.id into t_s from public.customer_therapy_sessions s where s.invoice_id = t_inv and s.is_current;
      select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv and it.therapy_service_id is not null;
      select it.id into t_vitem from public.invoice_items it where it.invoice_id = t_inv and it.line_kind::text = 'voucher';
      select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt';
      if t_s is null then raise exception '479: the self-test''s sessions were not made at payment'; end if;
      perform public.cancel_invoice_recorded(t_inv, '479 check', gen_random_uuid());
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      perform public.refund_invoice_recorded(t_inv,
        case when t_case = 6 then jsonb_build_array(jsonb_build_object('amount', 90))
             else jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', case when t_case = 5 then 60 else 20 end)) end,
        jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', case t_case when 5 then 60 when 6 then 90 else 20 end)),
        '[]'::jsonb, '479 check', gen_random_uuid());
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      perform public.reopen_invoice(t_inv, '479 check', gen_random_uuid());
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      t_ev0 := (select count(*) from public.invoice_therapy_session_events e where e.session_id = t_s and e.event_kind = 'reopen');
      -- The invoice form's lines as saved (the therapy line with its service).
      t_lines := (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind,
                    'voucher_id', it.voucher_id, 'therapy_service_id', it.therapy_service_id,
                    'quantity', it.quantity, 'unit_price', it.unit_price)) order by it.id)
                    from public.invoice_items it where it.invoice_id = t_inv);
      if t_case = 1 then
        -- (a) S$20 more refunded by line while it waits: 2 wait; the refund
        -- options (not changed by 479) say 1 unused up to S$20, the S$20
        -- held; paid S$20: 2 of 3, 1 refunded.
        perform public.refund_invoice_recorded(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 20)),
          jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 20)), '[]'::jsonb, '479 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        t_opt := (select o from jsonb_array_elements(public.invoice_refund_options(t_inv)->'therapy_sessions') o limit 1);
        if (select sum(q.quantity) from public.invoice_reopen_sessions q where q.session_id = t_s and q.applied_at is null) is distinct from 2
           or (t_opt->>'unused')::int is distinct from 1 or (t_opt->>'max_refund')::numeric is distinct from 20 then
          raise exception '479: (a) after the refund while it waits, % wait, the options say % unused up to %',
            (select sum(q.quantity) from public.invoice_reopen_sessions q where q.session_id = t_s and q.applied_at is null),
            t_opt->>'unused', t_opt->>'max_refund'; end if;
      elsif t_case = 2 then
        -- (b) cancelled again, S$20 refunded by line, reopened: the dialog
        -- says 3, and 2 and 1 wait.
        perform public.cancel_invoice_recorded(t_inv, '479 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        perform public.refund_invoice_recorded(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 20)),
          jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 20)), '[]'::jsonb, '479 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if (public.invoice_reopen_preview(t_inv)->>'sessions_to_reinstate_after_settlement')::int is distinct from 3 then
          raise exception '479: (b) the Reopen dialog does not say 3 sessions'; end if;
        perform public.reopen_invoice(t_inv, '479 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if (select array_agg(q.quantity order by q.quantity desc) from public.invoice_reopen_sessions q
             where q.session_id = t_s and q.applied_at is null) is distinct from '{2,1}'::int[] then
          raise exception '479: (b) after the second reopening the rows waiting are not 2 and 1'; end if;
      elsif t_case = 3 then
        -- (c) the customer changed to B (only a therapy line: no 'transfer' or
        -- 'keep' asked): the session is B's at once.
        insert into public.customers (full_name, phone) values ('479 Check B ' || t_sfx, t_phones[4]) returning id into t_b;
        perform public.correct_invoice(t_inv, t_lines,
          jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = t_inv),
                             'customer_id', t_b, 'store_id', t_store), '479 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if (select customer_id from public.customer_therapy_sessions where id = t_s) is distinct from t_b then
          raise exception '479: (c) the waiting session did not follow the customer change'; end if;
      elsif t_case = 4 then
        -- (d) with the voucher line, the customer changed to B with 'keep':
        -- the session stays A's.
        insert into public.customers (full_name, phone) values ('479 Check B ' || t_sfx, t_phones[6]) returning id into t_b;
        insert into public.customers (full_name, phone) values ('479 Check C ' || t_sfx, t_phones[7]) returning id into t_c;
        perform public.correct_invoice(t_inv, t_lines,
          jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = t_inv),
                             'customer_id', t_b, 'store_id', t_store, 'benefit_action', 'keep'), '479 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if (select customer_id from public.customer_therapy_sessions where id = t_s) is distinct from t_a then
          raise exception '479: (d) the waiting session did not stay with its holder after ''keep'''; end if;
      elsif t_case = 5 then
        -- (e) the Owner's case (29 Oct 2026): all 3 sessions refunded by line
        -- while it was cancelled, a voucher line, reopened, S$20 paid: the
        -- guided Refund in full (requested, an Owner approving it) leaves the
        -- therapy line out, as before 479: it pays back the voucher's S$30,
        -- the S$20 stays held and the 3 sessions wait.
        perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
          'amount', 20)), gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        t_plan := public.invoice_action_plan(t_inv, 'refund_full', '[]'::jsonb);
        if (select (l->>'amount')::numeric from jsonb_array_elements(t_plan->'lines') l where l->>'invoice_item_id' = t_item::text) is distinct from 0
           or (select (l->>'amount')::numeric from jsonb_array_elements(t_plan->'lines') l where l->>'invoice_item_id' = t_vitem::text) is distinct from 30
           or (t_plan->>'refund_amount')::numeric is distinct from 30 then
          raise exception '479: (e) the guided Refund in full''s plan is not as tested (%)', t_plan->'lines'; end if;
        t_req := public.request_invoice_action_v2(t_inv, 'refund_full', '[]'::jsonb, '479 check', null::text, gen_random_uuid());
        -- 479 (3 Nov 2026, the first apply on production): which line a plan
        -- lists first is not fixed, and on production it changed between two
        -- reads a moment apart, so the approval answered "What this request would
        -- do has changed ..." and did nothing. As staff would, the self-test
        -- confirms the revised plan (the same money and the same lines) and
        -- approves again.
        for t_try in 1 .. 10 loop
          t_res := public.resolve_invoice_action_v2((t_req->>'request_id')::uuid, true, '479 check', t_plan->>'plan_hash',
            (select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
                      then jsonb_build_object('code', o->>'code', 'reason', '479 check', 'amount', (o->>'default_amount')::numeric)
                      else jsonb_build_object('code', o->>'code', 'reason', '479 check') end), '[]'::jsonb)
               from jsonb_array_elements(coalesce(t_plan->'overrides_required', '[]'::jsonb)) o),
            null::jsonb, true);
          exit when t_res->>'status' is distinct from 'pending' or t_res->'revised_plan' is null;
          if (t_res->'revised_plan'->>'refund_amount')::numeric is distinct from (t_plan->>'refund_amount')::numeric
             or (select array_agg(l->>'invoice_item_id' order by l->>'invoice_item_id') from jsonb_array_elements(t_res->'revised_plan'->'lines') l)
                is distinct from (select array_agg(l->>'invoice_item_id' order by l->>'invoice_item_id') from jsonb_array_elements(t_plan->'lines') l) then
            raise exception '479: the self-test''s approval was asked to confirm a different plan (%)', t_res->'revised_plan'->'lines'; end if;
          t_plan := t_res->'revised_plan';
        end loop;
        if t_res->>'status' = 'pending' then
          raise exception '479: the self-test''s approval was asked to confirm a revised plan on every try (%)', t_res->'revised_plan'->'lines'; end if;
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if public.invoice_net_received(t_inv) <> 20
           or (select sum(q.quantity) from public.invoice_reopen_sessions q where q.session_id = t_s and q.applied_at is null) is distinct from 3 then
          raise exception '479: (e) the guided Refund in full did not keep the session money and the 3 waiting sessions (net %)',
            public.invoice_net_received(t_inv); end if;
      elsif t_case = 6 then
        -- (f) the Owner's answer of 29 Oct 2026 (~18:45 SGT), "Keep today's
        -- refusal": all S$90 paid back with no line while cancelled, reopened,
        -- S$60 paid: the guided Refund in full's plan (the sessions S$60, the
        -- voucher S$30) is cut to the S$60 held and gives the sessions some of
        -- it, whichever line it lists first, while the voucher line has
        -- something to refund too: refused as before 479 (252's own refusal:
        -- "Settle the reopened invoice ..." with the therapy line first, its
        -- "Refund whole unused therapy sessions ..." with S$30 left for it),
        -- changing nothing: S$60 held, the 3 sessions waiting.
        perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
          'amount', 60)), gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        t_plan := public.invoice_action_plan(t_inv, 'refund_full', '[]'::jsonb);
        if (t_plan->>'refund_amount')::numeric is distinct from 60
           or coalesce((select (l->>'amount')::numeric from jsonb_array_elements(t_plan->'lines') l where l->>'invoice_item_id' = t_item::text), 0) <= 0 then
          raise exception '479: (f) the guided Refund in full''s plan is not as tested (%)', t_plan->'lines'; end if;
        t_req := public.request_invoice_action_v2(t_inv, 'refund_full', '[]'::jsonb, '479 check', null::text, gen_random_uuid());
        t_msg := null;
        begin
          -- 479 (3 Nov 2026, the first apply on production): which line a plan
          -- lists first is not fixed, and on production it changed between two
          -- reads a moment apart, so the approval answered "What this request would
          -- do has changed ..." and did nothing. As staff would, the self-test
          -- confirms the revised plan (the same money and the same lines) and
          -- approves again.
          for t_try in 1 .. 10 loop
            t_res := public.resolve_invoice_action_v2((t_req->>'request_id')::uuid, true, '479 check', t_plan->>'plan_hash',
              (select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
                        then jsonb_build_object('code', o->>'code', 'reason', '479 check', 'amount', (o->>'default_amount')::numeric)
                        else jsonb_build_object('code', o->>'code', 'reason', '479 check') end), '[]'::jsonb)
                 from jsonb_array_elements(coalesce(t_plan->'overrides_required', '[]'::jsonb)) o),
              null::jsonb, true);
            exit when t_res->>'status' is distinct from 'pending' or t_res->'revised_plan' is null;
            if (t_res->'revised_plan'->>'refund_amount')::numeric is distinct from (t_plan->>'refund_amount')::numeric
               or (select array_agg(l->>'invoice_item_id' order by l->>'invoice_item_id') from jsonb_array_elements(t_res->'revised_plan'->'lines') l)
                  is distinct from (select array_agg(l->>'invoice_item_id' order by l->>'invoice_item_id') from jsonb_array_elements(t_plan->'lines') l) then
              raise exception '479: the self-test''s approval was asked to confirm a different plan (%)', t_res->'revised_plan'->'lines'; end if;
            t_plan := t_res->'revised_plan';
          end loop;
          if t_res->>'status' = 'pending' then
            raise exception '479: the self-test''s approval was asked to confirm a revised plan on every try (%)', t_res->'revised_plan'->'lines'; end if;
        exception when others then t_msg := sqlerrm;
        end;
        if t_msg is null
           or t_msg not in ('Settle the reopened invoice before changing its queued sessions',
                            'Refund whole unused therapy sessions at their original paid value; 3 of 3 sessions remain refundable')
           or public.invoice_net_received(t_inv) <> 60
           or (select sum(q.quantity) from public.invoice_reopen_sessions q where q.session_id = t_s and q.applied_at is null) is distinct from 3 then
          raise exception '479: (f) the guided Refund in full of a plan cut to the money held, the voucher line to refund too, was not refused as before 479 (%)',
            coalesce(t_msg, 'it went through: ' || coalesce(t_res->>'status', 'no answer')); end if;
      else
        -- (g) answer F with another line, the plan not cut: S$20 of the
        -- sessions refunded by line while cancelled, reopened: the guided
        -- Refund in full pays back the sessions' S$40 and the voucher's S$30,
        -- the S$70 held, whichever line it lists first; 2 sessions off the
        -- queue, 1 waits.
        t_plan := public.invoice_action_plan(t_inv, 'refund_full', '[]'::jsonb);
        if (t_plan->>'refund_amount')::numeric is distinct from 70
           or (select (l->>'amount')::numeric from jsonb_array_elements(t_plan->'lines') l where l->>'invoice_item_id' = t_item::text) is distinct from 40 then
          raise exception '479: (g) the guided Refund in full''s plan is not as tested (%)', t_plan->'lines'; end if;
        t_req := public.request_invoice_action_v2(t_inv, 'refund_full', '[]'::jsonb, '479 check', null::text, gen_random_uuid());
        -- 479 (3 Nov 2026, the first apply on production): which line a plan
        -- lists first is not fixed, and on production it changed between two
        -- reads a moment apart, so the approval answered "What this request would
        -- do has changed ..." and did nothing. As staff would, the self-test
        -- confirms the revised plan (the same money and the same lines) and
        -- approves again.
        for t_try in 1 .. 10 loop
          t_res := public.resolve_invoice_action_v2((t_req->>'request_id')::uuid, true, '479 check', t_plan->>'plan_hash',
            (select coalesce(jsonb_agg(case when coalesce((o->>'amount_required')::boolean, false)
                      then jsonb_build_object('code', o->>'code', 'reason', '479 check', 'amount', (o->>'default_amount')::numeric)
                      else jsonb_build_object('code', o->>'code', 'reason', '479 check') end), '[]'::jsonb)
               from jsonb_array_elements(coalesce(t_plan->'overrides_required', '[]'::jsonb)) o),
            null::jsonb, true);
          exit when t_res->>'status' is distinct from 'pending' or t_res->'revised_plan' is null;
          if (t_res->'revised_plan'->>'refund_amount')::numeric is distinct from (t_plan->>'refund_amount')::numeric
             or (select array_agg(l->>'invoice_item_id' order by l->>'invoice_item_id') from jsonb_array_elements(t_res->'revised_plan'->'lines') l)
                is distinct from (select array_agg(l->>'invoice_item_id' order by l->>'invoice_item_id') from jsonb_array_elements(t_plan->'lines') l) then
            raise exception '479: the self-test''s approval was asked to confirm a different plan (%)', t_res->'revised_plan'->'lines'; end if;
          t_plan := t_res->'revised_plan';
        end loop;
        if t_res->>'status' = 'pending' then
          raise exception '479: the self-test''s approval was asked to confirm a revised plan on every try (%)', t_res->'revised_plan'->'lines'; end if;
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if public.invoice_net_received(t_inv) <> 0
           or (select sum(q.quantity) from public.invoice_reopen_sessions q where q.session_id = t_s and q.applied_at is null) is distinct from 1 then
          raise exception '479: (g) the guided Refund in full did not pay back the S$70 and leave 1 session waiting (net %)',
            public.invoice_net_received(t_inv); end if;
      end if;
      -- What is outstanding paid (Record Payment): the payment settles it.
      perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash,
        'amount', (public.invoice_financial_position(t_inv)->>'outstanding')::numeric)), gen_random_uuid());
      set constraints public.credit_given_back_follows immediate;
      set constraints public.credit_given_back_follows deferred;
      if (select status::text from public.invoices where id = t_inv) <> 'paid'
         or exists (select 1 from public.invoice_reopen_sessions q where q.invoice_id = t_inv and q.applied_at is null)
         or (select row(s.customer_id, s.quantity_purchased - s.quantity_used - s.quantity_refunded - s.quantity_cancelled,
                        s.quantity_refunded, s.quantity_cancelled, s.status)
               from public.customer_therapy_sessions s where s.id = t_s and s.is_current)
            is distinct from row(case when t_case = 3 then t_b else t_a end, case t_case when 1 then 2 when 7 then 1 else 3 end,
                                 case t_case when 1 then 1 when 7 then 2 else 0 end, 0, 'available'::text)
         or (select count(*) from public.invoice_therapy_session_events e where e.session_id = t_s and e.event_kind = 'reopen') - t_ev0
            <> (case when t_case = 2 then 2 else 1 end)
         or public.invoice_net_received(t_inv) <> (case t_case when 1 then 40 when 4 then 90 when 6 then 90 when 7 then 20 else 60 end)
         or t_case in (5, 7) and exists (select 1 from public.customer_reward_vouchers v where v.customer_id = t_a and v.status = 'held')
         or t_case = 6 and not exists (select 1 from public.customer_reward_vouchers v where v.customer_id = t_a and v.status = 'held') then
        raise exception '479: (%) the payment did not settle it as tested (status %, session %, net %)', chr(96 + t_case),
          (select status::text from public.invoices where id = t_inv),
          (select to_jsonb(s) from public.customer_therapy_sessions s where s.id = t_s), public.invoice_net_received(t_inv); end if;
      if t_case = 4 then
        -- (d) the invoice is B's, the sessions and the voucher A's; a
        -- correction of the notes leaves them; moving the invoice to C is
        -- refused.
        if (select customer_id from public.invoices where id = t_inv) is distinct from t_b
           or exists (select 1 from public.customer_reward_vouchers v where v.customer_id = t_b and v.status = 'held') then
          raise exception '479: (d) after ''keep'' the invoice is not B''s, or B holds a voucher'; end if;
        perform public.correct_invoice(t_inv, t_lines,
          jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = t_inv),
                             'customer_id', t_b, 'store_id', t_store, 'notes', '479 check note'), '479 check', gen_random_uuid());
        set constraints public.credit_given_back_follows immediate;
        set constraints public.credit_given_back_follows deferred;
        if (select customer_id from public.customer_therapy_sessions where id = t_s and is_current) is distinct from t_a then
          raise exception '479: (d) a correction of the notes took the sessions from their holder'; end if;
        t_msg := null;
        begin
          perform public.correct_invoice(t_inv, t_lines,
            jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = t_inv),
                               'customer_id', t_c, 'store_id', t_store, 'benefit_action', 'transfer'), '479 check', gen_random_uuid());
        exception when others then t_msg := sqlerrm;
        end;
        if t_msg is null or t_msg not like 'These therapy sessions were left with %' then
          raise exception '479: (d) moving the invoice to a third customer was not refused as tested (%)', coalesce(t_msg, 'it went through'); end if;
      end if;
    end loop;
    raise exception using errcode = 'P0479', message = '479: self-test done, undone';
  exception when sqlstate 'P0479' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
