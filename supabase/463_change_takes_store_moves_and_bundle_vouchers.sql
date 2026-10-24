-- 463_change_takes_store_moves_and_bundle_vouchers.sql
--
-- A CUSTOMER CHANGE THAT TAKES THE BENEFITS ALONG ALSO TAKES WHAT AN OWNER
-- MOVED TO THE SAME CUSTOMER AT ANOTHER STORE, AND A PREMIUM BUNDLE'S
-- VOUCHERS; ITS SUMMARY SAYS WHAT A WAITING REOPENING WILL GIVE BACK; NO
-- INVOICE IS MADE FOR A REMOVED CUSTOMER RECORD (the Owner, 24 Oct 2026,
-- decisions 2 and 3; 460's NOT COVERED 2 and 7; 462's NOT COVERED 1)
--
-- WHO FOUND IT
--
--   The builders of 460 and 462 (460's NOT COVERED 2 and 7; the catalogue of
--   Move and merge leftovers of 24 Oct 2026, its cases 13 (T1, T1r, T2, T2c),
--   14 (V3, V4, V7) and 15 (W1), and its side note K6s), put to the Owner by
--   462's judge as decisions 2 and 3. Then the critics of this file's first
--   build (24 Oct 2026), four findings, each reproduced on a copy before it
--   was fixed: (1) the read-only query, and the install's check, missed
--   invoices cancelled or refunded after a change and not reopened yet,
--   whose reopening 463 gives to the new customer (C2, C1, C3, C4, C2r);
--   (2) a voucher a reopening before 463 gave again to the old customer
--   after a change kept going back to that customer at every later
--   reopening, and the suite's one transaction hid it (V4, T2w, V3c, each
--   call committed on its own); (3) moving part of a package to the same
--   customer at another store let a change split a package already partly
--   spent, which 461 refuses without the Move (P1); (4) the query said such
--   partly spent credit "moves with a later change", which 463 refuses.
--   Built on 462 (its AFTERs are this file's BEFOREs where they share a
--   function) and tested on copies of production at 464 with 462 in
--   (055ad62e, 1383 functions), made-up records, the app's own calls, each
--   followed by what its commit does.
--
-- WHAT WAS WRONG
--
--   On the copies, each with a S$100 Credit Package (S$100 + S$10 where it
--   says so), a voucher line of two S$30 vouchers, or a S$140 Premium Bundle
--   (S$100 Paid, S$40 Bonus, two vouchers), sold to A at the first store:
--   * an Owner moved the package's S$100 to A at the second store (Move: a
--     store correction), then the invoice's customer was changed A to B with
--     'transfer' (the benefits go along): A kept the S$100, B got nothing
--     (T1); with S$40 refunded first, then the Move, the change, Cancel,
--     Reopen and the payment: A S$60, B S$40 (T1r; the same with the change
--     while the reopening waited, T1w); a second change, or a merge of A:
--     the S$100 stayed with A, or with the record the merge kept (T1c, T1m);
--     with the Bonus moved too: A S$110 (T1x); cancelled (or refunded in
--     full) after the change and reopened (paid): A got the S$100 back (C2,
--     C2r; the change made while a reopening waited, then paid: C2w). A
--     session paid from the package before the Move and refunded (or its
--     payment corrected to cash) before the change: B got the S$20, A kept
--     the S$80 (T1p, T1d). The two vouchers moved to A at the second store
--     stayed with A, and a reopening gave them again to A (T2, T2c, T2w,
--     T2m), and again at every later reopening (T2wc);
--   * a Premium Bundle's credit followed the change and its two vouchers
--     stayed with A, "not transferable" (V3; a second change, the store
--     changed too: the same, V3c, V3s); after a reopening that waited, or a
--     Cancel (or Refund in full) and Reopen after the change, its payment
--     gave them again to A (V4, V7, V3w, V3r, C4; then B merged into K: A
--     still held them, V4m), and so did every later reopening (V4c) and a
--     second change left them (V3rC);
--   * a session paid from the package, the S$80 left moved by an Owner to A
--     at the second store, then the change: it went through, the Move's row
--     reading as untouched (it was given only the S$80 left), though the
--     same package without the Move is refused, "Partly spent" (461's rule,
--     L5): a change that took the benefits along would have split a partly
--     spent package (P1, once 463 takes such credit along);
--   * the summary of a customer change made while a reopening waits for its
--     payment listed nothing of what that payment gives back, though it then
--     went to the new customer (W1: S$100 Paid and two vouchers);
--   * create_invoice_with_details took a customer record a merge had
--     retired, or Delete customer had removed (K6s: an invoice for the
--     retired record spent its credit, and its plans then asked a false
--     credit_used). The pages cannot pick such a record (the customers read
--     policy hides it); a form left open across a merge could send one.
--   Nothing was lost: Cancel took everything back from whoever held it. But
--   a change that takes the benefits along left part of them with the old
--   customer.
--
-- THE OWNER'S ANSWERS (24 Oct 2026)
--
--   Decision 2 (option (a)): a Move to the same customer at another store
--   (a store correction) is taken along by a later 'transfer' customer
--   change. Decision 3 (option (a)): a Premium Bundle's vouchers follow a
--   'transfer' customer change as the bundle's credit does. (Decision 1, "B,
--   the package's holder now", is 462's.) A Move to someone else stays with
--   its recipient, as before (434). A store correction changes nothing else:
--   a package partly spent before it still blocks the change, as without it
--   (461's rule; the critics' finding 3).
--
-- WHAT THIS DOES (two functions added, eight changed; no table or column
-- changes; grants of the eight kept)
--
--   * invoice_benefit_moved_to_other(uuid) (new, the server's alone):
--     whether a benefit row is what an Owner moved to someone else, or a
--     Move of such a row. A Move to the same customer (the Move's own
--     snapshots name the same customer before and after it; the Move refuses
--     the same customer at the same store) leaves the row the invoice's own.
--   * invoice_benefit_moved_from_spent(uuid) (new, the server's alone):
--     whether a row a Move made came from a row partly spent before the
--     Move: back along the Move's chain, a credit row whose lot holds, with
--     what a cancellation took back and what is not used although no longer
--     on it (invoice_benefit_unused_elsewhere: what a Move took, what a line
--     refund paid back), less than the row granted.
--   * Credit (decision 2): move_invoice_benefits_to_customer and
--     invoice_transferable_benefits also take, and list, the lot that a
--     store-moved row names now (as the invoice's own lots: unspent, it
--     moves with its records and keeps its store, origin and dates; with
--     real spending on it, or on the row it was moved from before the Move
--     (invoice_benefit_moved_from_spent), it blocks the change as "Partly
--     spent", 461's rule, and the change moves nothing; refunded first, it
--     moves). apply_reopened_invoice_benefits and credit_given_back_follows
--     (462's P4, P5) read such a row's holder as the invoice's own: whoever
--     holds the benefits now (a later change, a merge), not the Move's
--     recipient; a Move to someone else still follows merges alone.
--   * Vouchers (decisions 2 and 3): invoice_own_voucher_ids (460's) also
--     returns what a Premium Bundle sold on the invoice gave (source
--     'premium_bundle'), a voucher an Owner moved from one of the invoice's
--     own to the same customer at another store, and those given again in
--     place of either. So a change with 'transfer' moves them and lists them
--     (the invoice's own vouchers, 460), and a reopening gives them again to
--     whoever holds the benefits (apply_reopened_invoice_vouchers, 460's).
--     That holder is now read from when the first voucher of the chain was
--     given (the line's, the bundle's, or the store-moved one's source: back
--     along invoice_reopen_vouchers and the Move), not from when the one it
--     replaces was given: one given again to the old customer after a change
--     (before 463, a bundle's or a store-moved one's) goes to the holder at
--     the next reopening, instead of back to that customer every time (the
--     critics' finding 2; for every voucher given again after the latest
--     change, the two readings name the same holder). A store-moved voucher,
--     and a bundle's, keep their store when the customer changes (as credit
--     keeps its store: no stock moves for them; a store-only correction
--     leaves them where they are); a voucher line's and a promotion line's
--     go to the invoice's store with their limited stock, as before (417).
--   * The summary (W1): preview_invoice_correction (458's), for a customer
--     change that is not 'keep', adds what a reopening waiting to be settled
--     will give back when it is paid: by credit category (the amounts its
--     cancellation took, "Paid credit 100.00") and by voucher ("<voucher> ×
--     2"), not what was moved to someone else, under "Customer benefits",
--     'transferring': "The invoice's reopening waits for its payment. When
--     it is paid, these go back to the new customer, with their original
--     source, deadlines and restrictions unchanged." The page shows any such
--     entry as it shows the others (no page change). And where the same
--     save takes the FOC off (416's part of the summary), a voucher this
--     save moves to the new customer as one of the invoice's own (a
--     store-moved one now) is listed as taken back, as the save takes it back
--     (it moves the vouchers first); before, the summary said it stayed with
--     the customer an Owner moved it to, and the save took it back. Credit
--     the change now refuses for (above) is listed under the review's
--     "already been used" entry, "Paid credit 80.00 — Partly spent", as for
--     the invoice's own.
--   * K6s: create_invoice_with_details (456's) refuses a customer record
--     that is deleted (a merge retired it, or Delete customer removed it):
--     "This customer's record was merged into another or deleted. Choose the
--     customer again." A request already made is given back as before
--     (416). The website's and the
--     event's invoices are made by the same function: a website order whose
--     customer was removed goes to review with that message
--     (web_order_make_invoice catches it); the event's VIP invoices already
--     refuse a removed record.
--   Afterwards (the suite, each case): A holds nothing; B holds the S$100
--   (T1: at the second store), S$100 (T1r, T1w), C S$100 (T1c), B S$110
--   (T1x), B S$100 when the session was refunded before the change (T1p,
--   T1d), B S$100 after a Cancel or Refund in full and the reopening (C2,
--   C2r, C2w), and the two vouchers at the second store (T2, T2c, T2w, T2m,
--   T2wc); B the bundle's S$140 and its two vouchers (V3, V4, V7, V3w, V3r,
--   C4, V4c; C after a second change, V3c, V3rC; K after a merge); nothing
--   is asked, the refund due is what was received, and Cancel takes it all
--   back from whoever holds it. A session paid from the store-moved credit,
--   or from the package before the Move, blocks the change as "Partly
--   spent" (T1s, P1), as without the Move (L5).
--
-- NOT CHANGED
--
--   * transfer_invoice_unused_benefit (the Move), merge_customer_records
--     (462's), correct_invoice (464's), cancel_invoice_recorded,
--     reopen_invoice, refund_invoice_recorded, correct_invoice_payment,
--     invoice_benefits_holder, invoice_benefit_unused_elsewhere,
--     invoice_credit_lot_ids, 462's trace, ancestry, holder and trigger,
--     create_invoice, the website's and the event's invoice functions:
--     pinned, unchanged. apply_reopened_invoice_vouchers changes in one
--     place (the time its holder is read from); its stock, store, value and
--     issue are as 460 and 464 left them.
--   * A Move to someone else: its recipient keeps it (434), merges followed;
--     a Move to the same customer of what was moved to someone else stays
--     theirs. 'keep' leaves everything where it is.
--   * The pages: no wording a page matches on changes (the summary's new
--     entry is shown as the others are; the invoice form shows a server
--     refusal as it comes). No page, Edge Function or setting changes.
--
-- NOT COVERED (for the Owner; the suite checks 1 and 2 as they are)
--
--   1. 460's NOT COVERED 3 (W2): vouchers a reopening gives again stay at
--      the store of the voucher they replace, after a change that moved the
--      invoice to another store (an Owner decision).
--   2. 445's NOT COVERED 1: a merge of a record that spent wallet credit is
--      still refused (S1m).
--   3. A store-moved voucher, and a Premium Bundle's, keep their store when
--      the customer changes, also when the change moves the invoice to
--      another store (as built: as the credit keeps its store, the Owner's
--      correction of a voucher's store is kept, and no stock moves or is
--      refused). Ask the Owner if they should go to the invoice's store
--      instead, as a voucher line's do (417). Taking the FOC off in the same
--      save takes a store-moved voucher back too (it is unused and the
--      save's), and the payment gives it again at the invoice's store, as
--      the other vouchers the FOC gave (cancel-voucher-stock-once 13c-e).
--   4. Vouchers claimed later from a Premium Bundle's voucher allowance
--      (claim_entitlement_vouchers) stay with whoever claimed them; the
--      allowance itself moves with the change while nothing is claimed from
--      it (as before).
--   5. A therapy voucher with sessions used but still held moves with the
--      change (as a voucher line's does today): what is left of it goes to
--      the new customer. 461's rule for credit (partly spent blocks) is not
--      applied to vouchers.
--   6. 461's NOT COVERED 2: a lot an Owner moved, or a lot a Move emptied,
--      reads "Fully spent; it stays with the original customer" in the
--      change's list (no page shows it).
--   7. A summary or a form open on a screen when this goes in shows the old
--      answer until it is opened again; the server checks again on save.
--   8. Credit is still read by when its lot was made (462's rule), not from
--      the first lot of its chain as vouchers now are: credit an Owner moved
--      to the same customer at another store that a change with 'transfer'
--      before 463 left with the old customer, and that a merge then reissued
--      (a lot made after the change), is the merge's record's under 463, as
--      before; only a later change moves it (the query lists it under 2). A
--      data fix with the Owner's yes, if it should be the new customer's.
--      Credit given back after the latest change already goes to whoever
--      holds the benefits (460, 462), so nothing made since 462 is affected.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the texts are the tested ones (their AFTER md5s); each of the eight is
--     its BEFORE (changed; each anchor found once; the text built has its
--     AFTER md5) or its AFTER (left alone), all eight or none; each added
--     function is absent (added) or this version (left alone); no other
--     function takes the ten names; so a second run changes nothing;
--   * 462 is in (its functions and its trigger as 462 made them), and the
--     functions this relies on are as read (pinned, below); the columns read
--     have these types; the reopening's two settlement triggers are there;
--     who else calls the eight is as read; what gives a Premium Bundle's
--     vouchers is as read (a new way would need its source here);
--   * on the first run, nothing already in a state this reads differently
--     and that needs a decision first: credit an Owner moved to the same
--     customer at another store, held by someone other than whoever holds
--     the benefits now by this file's rule (a change with 'transfer' since
--     left it with the old customer; from 463 the next refund or reopening
--     would move it all at once). It stops, changing nothing, and names the
--     invoices (the read-only query below lists them, 1). A repair is a
--     separate data fix, with the Owner's yes;
--   * not refused, but listed by the query (3 and 5 to 8): what only a
--     later step reads differently, with nothing anyone holds changed by the
--     install: a change with 'transfer' of partly spent store-moved credit
--     (refused from 463, 3); a Cancel and Reopen of vouchers the old
--     customer still holds after a change (5); a waiting reopening's payment
--     (6); the reopening of an invoice cancelled or refunded after a change,
--     its credit and vouchers taken back and not given again yet (7, 8; the
--     critics' finding 1). Those steps then give what they give back to
--     whoever holds the benefits, by the Owner's decisions 2 and 3: the same
--     as for the same invoices not cancelled (refused, 1), whose credit is
--     still held and would otherwise sit with the wrong customer;
--   * who may call the eight is as read, compared as sets, and kept; each
--     added function is revoked from public, anon and signed-in staff and
--     granted to the service role;
--   * afterwards: the AFTER md5s and the grants as tested.
--   Then a self-test, in a block that is always undone (it ends by raising
--   P0463, so it leaves no row): a made-up Owner, two stores, a package, a
--   voucher, a bundle and eight customers (fictional ACMA phones no customer
--   has). (a) The package's S$100 moved to the buyer at the other store,
--   then the customer changed: the second customer holds the S$100 at the
--   other store, on a lot replacing the moved one that the moved benefit row
--   names, traced to the package (Credit Package Paid); nothing asked, due
--   S$100. (b) A voucher line of two sold to the third customer, both moved
--   to that customer at the other store, the customer changed to the fourth:
--   the fourth holds them there; cancelled and reopened: given again to the
--   fourth, there. (c) A bundle, the customer changed: the sixth holds its
--   S$140 and two vouchers; (g) cancelled and reopened: given again to the
--   sixth; then one given again left with the fifth, dated after the change
--   (a stand-in for a reopening's payment before 463), cancelled and
--   reopened again: given again to the sixth. (d) A second bundle,
--   cancelled, refunded by line, reopened (it waits): the summary of a change
--   lists "Bonus credit 40.00", "Paid credit 100.00" and the two vouchers;
--   with 'keep' nothing; changed and paid: the new customer holds all of it.
--   (e) A deleted customer: an invoice for it is refused, none made. (f) A
--   package for the eighth customer, S$20 of it spent (a stand-in 'use'
--   row), the S$80 left moved to that customer at the other store: listed
--   as blocking, "Partly spent", and the change refused, moving nothing.
--   Its credit ledger rows draw entry numbers (a sequence, 33 per run, which
--   an undone transaction does not give back: a gap, as 443 to 464's self-
--   tests). Locks: the ten functions' catalogue rows to the end of the
--   apply, and the rows the self-test writes and undoes. A change, a
--   reopening's payment or a new invoice running at that moment finishes on
--   the text it started with.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (467 in: 732a3805, 1380 functions; as 462's header reads
--   it) -> 462 -> 463. 463 needs 462 (it stops without it) and changes four
--   of 462's functions (their 462 AFTERs are its BEFOREs). 456 to 458, 464,
--   465 and 467 are in; 463 changes 458's preview_invoice_correction,
--   456's create_invoice_with_details (their AFTERs are its BEFOREs), and
--   460's invoice_own_voucher_ids and apply_reopened_invoice_vouchers
--   (pinned by 464: its suite takes 463's AFTERs). If anything else goes in
--   first, work the fingerprints out again (466, on main since: it changes
--   affiliate functions alone; with it in too, worked out below).
--   1. Before it, read only (invoice numbers and counts only; production
--      was not read for this file, so what it lists is not known yet), with
--      462 in: what would stop the install (1) and whose answer changes (2
--      to 12):
--     with recursive
--     mv(benefit_id, at_id, other, n) as (
--       select t.replacement_benefit_id, t.source_benefit_id,
--              (t.before_snapshot->>'customer_id') is distinct from coalesce(t.after_snapshot->>'customer_id', t.customer_id::text), 0
--         from public.invoice_benefit_transfers t where t.replacement_benefit_id is not null
--       union all
--       select mv.benefit_id, t.source_benefit_id,
--              (t.before_snapshot->>'customer_id') is distinct from coalesce(t.after_snapshot->>'customer_id', t.customer_id::text), mv.n + 1
--         from mv join public.invoice_benefit_transfers t on t.replacement_benefit_id = mv.at_id
--        where not mv.other and mv.n < 64),
--     -- benefit rows an Owner moved to the same customer at another store (463's
--     -- invoice_benefit_moved_to_other false for a row a Move made)
--     store_moved as (
--       select b.* from public.invoice_benefit_values b
--        where b.id in (select mv.benefit_id from mv group by mv.benefit_id having not bool_or(mv.other))),
--     -- their credit, with 463's test for a customer change (invoice_transferable_
--     -- benefits: it moves when untouched, or nothing on it spent and nothing
--     -- holds a claim on it, 461; and nothing spent on the rows it was moved from
--     -- before the Move, invoice_benefit_moved_from_spent)
--     sm_credit as (
--       select b.invoice_id, b.id, l.id as lot_id, l.customer_id, l.created_at, l.remaining_amount, l.status,
--              (l.remaining_amount = l.original_amount and l.reassigned_from_lot_id is null
--               or l.remaining_amount + b.cancelled_unused_value + public.invoice_benefit_unused_elsewhere(b.id) >= b.granted_value
--                  and b.cancelled_unused_value = 0
--                  and not exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = b.invoice_id and q.applied_at is null)
--                  and not exists (select 1 from public.invoices iv where iv.id = b.invoice_id and iv.status in ('cancelled', 'refunded')))
--              and not exists (
--                with recursive m(benefit_id, n) as (
--                  select t.source_benefit_id, 0 from public.invoice_benefit_transfers t where t.replacement_benefit_id = b.id
--                  union all
--                  select t.source_benefit_id, m.n + 1
--                    from m join public.invoice_benefit_transfers t on t.replacement_benefit_id = m.benefit_id where m.n < 64)
--                select 1 from m
--                  join public.invoice_benefit_values sb on sb.id = m.benefit_id and sb.lot_id is not null
--                  left join public.customer_credit_lots sl on sl.id = sb.lot_id
--                 where coalesce(sl.remaining_amount, 0) + sb.cancelled_unused_value
--                       + public.invoice_benefit_unused_elsewhere(sb.id) < sb.granted_value) as moves
--         from store_moved b join public.customer_credit_lots l on l.id = b.lot_id),
--     -- the invoice's own vouchers by 463's rule (invoice_own_voucher_ids): its
--     -- voucher and promotion lines', a Premium Bundle's, one an Owner moved from
--     -- one of them to the same customer at another store, and those given again
--     -- in place of any of them; with when the first of each chain was given (463
--     -- gives one again to whoever holds the benefits since then) and whether it
--     -- was the invoice's own before 463 (460's: a line's, and those given again
--     -- in its place)
--     own_v(invoice_id, id, kind, root_at, own_before, n) as (
--       select it.invoice_id, v.id, 'line', v.issued_at, true, 0
--         from public.customer_reward_vouchers v join public.invoice_items it on it.id = v.source_id
--        where v.source_type in ('invoice_voucher_sale', 'invoice_promotion_voucher')
--       union all
--       select s.invoice_id, v.id, 'bundle', v.issued_at, false, 0
--         from public.premium_bundle_sales s
--         join public.customer_reward_vouchers v on v.source_type = 'premium_bundle' and v.source_id = s.id
--        where s.invoice_id is not null
--       union all
--       select o.invoice_id, x.id, case when x.moved then 'moved' else o.kind end, o.root_at, o.own_before and not x.moved, o.n + 1
--         from own_v o
--         join public.invoice_benefit_values b on b.reward_voucher_id = o.id and b.invoice_id = o.invoice_id
--         cross join lateral (
--           select q.replacement_voucher_id as id, false as moved
--             from public.invoice_reopen_vouchers q
--            where q.benefit_id = b.id and q.invoice_id = o.invoice_id and q.replacement_voucher_id is not null
--           union all
--           select rb.reward_voucher_id, true
--             from public.invoice_benefit_transfers t
--             join store_moved rb on rb.id = t.replacement_benefit_id
--            where t.source_benefit_id = b.id and t.invoice_id = o.invoice_id and rb.reward_voucher_id is not null) x
--        where o.n < 64),
--     -- who a reopening gives each one again to: from 463 (apply_reopened_invoice_
--     -- vouchers), and before it
--     own_vh as (
--       select o.invoice_id, o.kind, v.id, v.customer_id, v.status, v.redeemed_at,
--              public.invoice_benefits_holder(o.invoice_id, v.customer_id, o.root_at) as holder_after,
--              case when o.own_before then public.invoice_benefits_holder(o.invoice_id, v.customer_id, v.issued_at)
--                   else v.customer_id end as holder_before
--         from own_v o join public.customer_reward_vouchers v on v.id = o.id),
--     found(reason, invoice_id, n) as (
--       -- 463 refuses to install (it needs a decision first; a data fix):
--       select '1 refuses: credit an Owner moved to the same customer at another store, held by someone other than whoever holds the benefits now (a customer change with "transfer" left it)', c.invoice_id, count(*)
--         from sm_credit c
--        where c.remaining_amount > 0 and c.status = 'active'
--          and c.customer_id is distinct from public.invoice_credit_live_holder(c.invoice_id, c.customer_id, c.created_at)
--        group by c.invoice_id
--       union all
--       -- 463 changes the answer (no refusal):
--       select '2 changes: credit an Owner moved to the same customer at another store, unspent (a later change with "transfer" takes it along)', c.invoice_id, count(*)
--         from sm_credit c
--        where c.remaining_amount > 0 and c.status = 'active' and c.moves
--        group by c.invoice_id
--       union all
--       select '3 changes: credit an Owner moved to the same customer at another store, partly spent (on it, or on the row it was moved from before the Move): a change with "transfer" is now refused as "Partly spent" until it is resolved', c.invoice_id, count(*)
--         from sm_credit c
--        where c.remaining_amount > 0 and c.status = 'active' and not c.moves
--        group by c.invoice_id
--       union all
--       select '4 changes: vouchers an Owner moved to the same customer at another store (or given again in their place), unused (a later change with "transfer" takes them along, at their store)', v.invoice_id, count(*)
--         from own_vh v
--        where v.kind = 'moved' and v.status = 'held' and v.redeemed_at is null
--        group by v.invoice_id
--       union all
--       select '5 changes: the invoice''s own vouchers (a voucher line''s, a Premium Bundle''s, a store-moved one, or given again in their place), unused, held by someone other than whoever holds the benefits now (a change with "transfer" before 463 left them, or a reopening before 463 gave them again to the old customer): a Cancel and Reopen now gives them again to the holder, and a later change takes them along', v.invoice_id, count(*)
--         from own_vh v
--        where v.status = 'held' and v.redeemed_at is null and v.holder_after is distinct from v.holder_before
--        group by v.invoice_id
--       union all
--       select '6 changes: a reopening waiting to be settled whose payment gives a Premium Bundle''s or a store-moved voucher, or store-moved credit, to someone else than before (the holder of the benefits after a change with "transfer")', x.invoice_id, count(*)
--         from (select q.invoice_id from public.invoice_reopen_vouchers q
--                 join public.invoice_benefit_values b on b.id = q.benefit_id
--                 join own_vh v on v.id = b.reward_voucher_id and v.invoice_id = q.invoice_id
--                where q.applied_at is null and v.holder_after is distinct from v.holder_before
--               union all
--               select q.invoice_id from public.invoice_reopen_benefits q
--                 join public.customer_credit_ledger e on e.id = q.source_ledger_id
--                 join sm_credit c on c.invoice_id = q.invoice_id and e.lot_id = any (public.credit_lot_ancestry(c.lot_id))
--                where q.applied_at is null
--                  and public.invoice_credit_live_holder(q.invoice_id, c.customer_id, c.created_at)
--                      is distinct from public.invoice_credit_live_holder(q.invoice_id, c.customer_id, 'infinity')) x
--        group by x.invoice_id
--       union all
--       select '7 changes: cancelled or refunded (or a line refunded), not reopened yet: credit an Owner moved to the same customer at another store that the next reopening gives back to someone else than before (the holder of the benefits after a change with "transfer")', c.invoice_id, count(*)
--         from sm_credit c
--        where exists (select 1 from public.customer_credit_ledger e
--                       where e.lot_id = any (public.credit_lot_ancestry(c.lot_id))
--                         and (e.source_type = 'invoice_cancel_benefit' and e.source_record_id = c.invoice_id
--                              or e.source_type = 'invoice_benefit_refund'
--                                 and exists (select 1 from public.invoice_refunds r where r.invoice_id = c.invoice_id and r.request_id = e.source_record_id))
--                         and not exists (select 1 from public.invoice_reopen_benefits q where q.source_ledger_id = e.id))
--          and public.invoice_credit_live_holder(c.invoice_id, c.customer_id, c.created_at)
--              is distinct from public.invoice_credit_live_holder(c.invoice_id, c.customer_id, 'infinity')
--        group by c.invoice_id
--       union all
--       select '8 changes: cancelled or refunded (or a line refunded), not reopened yet: the invoice''s own vouchers (a Premium Bundle''s, a store-moved one, or given again in their place) that the next reopening gives again to someone else than before (the holder of the benefits after a change with "transfer")', v.invoice_id, count(*)
--         from own_vh v
--         join public.invoice_benefit_values b on b.reward_voucher_id = v.id and b.invoice_id = v.invoice_id
--         cross join lateral public.invoice_voucher_reopen_candidates(v.invoice_id) k
--        where k.benefit_id = b.id
--          and k.quantity > coalesce((select sum(q.quantity) from public.invoice_reopen_vouchers q
--                                      where q.benefit_id = b.id and q.applied_at is null), 0)
--          and v.holder_after is distinct from v.holder_before
--        group by v.invoice_id
--       union all
--       select '9 changes: credit an Owner moved to the same customer at another store, held by someone other than whoever holds the benefits now, with sales paid from it that can still be refunded (their credit then goes to the holder)', c.invoice_id, count(*)
--         from sm_credit c
--        where c.customer_id is distinct from public.invoice_credit_live_holder(c.invoice_id, c.customer_id, c.created_at)
--          and (exists (select 1 from public.invoice_line_credit_allocations a where a.lot_id = c.lot_id and a.amount > coalesce(a.reversed_amount, 0))
--               or exists (select 1 from public.special_credit_allocations s where s.lot_id = c.lot_id and s.amount > coalesce(s.reversed_amount, 0)))
--        group by c.invoice_id
--       union all
--       select '10 changes: a reopening waiting to be settled (the summary of a customer change now lists what its payment gives the new customer)', x.invoice_id, count(*)
--         from (select invoice_id from public.invoice_reopen_benefits where applied_at is null
--               union all select invoice_id from public.invoice_reopen_vouchers where applied_at is null) x
--        group by x.invoice_id
--       union all
--       select '11 changes: invoices with a Premium Bundle''s unused vouchers (a later change with "transfer" moves them too; a count)', null::uuid, count(distinct v.invoice_id)
--         from own_vh v join public.invoices iv on iv.id = v.invoice_id
--        where v.kind = 'bundle' and v.status = 'held' and v.redeemed_at is null and iv.deleted_at is null
--       union all
--       select '12 changes: customer records a merge retired or Delete customer removed (a new invoice for one is refused; a count)', null::uuid, count(*)
--         from public.customers c where c.deleted_at is not null)
--     select f.reason, i.invoice_no, f.n
--       from found f left join public.invoices i on i.id = f.invoice_id
--      where f.n > 0
--      order by split_part(f.reason, ' ', 1)::int, i.invoice_no
--      (The suite runs this same text on its cases' states before 463, the
--      vouchers each step gives dated when the step ends, as in the app, and
--      checks what it lists.)
--   2. Dry run on a copy of production as it is then (462 in): work out its
--      fingerprint and grant list first (they must be the BEFORE figures
--      below, or be worked out again on that copy); apply this file twice;
--      the first run ends at the AFTER fingerprint below, the second changes
--      nothing ("left alone" eight times); the suite, with the earlier
--      suites below.
--   3. Apply (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself.
--   Afterwards (checked on a copy at 464 with 462 and 463 in, 24 Oct 2026,
--   each in a transaction undone): the re-runs of 446, 451, 462 and 464
--   refuse on 463's apply_reopened_invoice_vouchers (446 and 451 already
--   did on 460's), 457's on its preview_invoice_correction; those of 445,
--   447, 448, 456, 458, 460 and 461 refuse already on earlier changes
--   (462's, 458's, 464's); each changes nothing (the fingerprint stays
--   8f41d41b), and all are applied, so nothing is lost; 463's
--   own leaves all alone. Their suites check 463 where it is in:
--   move-merge-leftovers-462 (S; T1, T1r, T2, T2c, V3, V4 and its KNOWN 1 to
--   4 the 463 way), reopen-follows-customer-460 (10: the voucher list and
--   the move's text outside 461's part, the settlement of vouchers; X8 the
--   463 way), customer-change-refunded-461 (10), raised-voucher-lines-464
--   (the pins), invoice-follows-458 (G1), print-note-456 and
--   foc-correct-again-457 (the pins), customer-change-credit-447 (its
--   fixture takes 463's six changes to the move out), cancel-voucher-stock-
--   once (13c-e the 463 way: the FOC off with a change takes back the
--   store-moved voucher too, in the summary and the save); function-grants
--   lists the two helpers.
--
-- BEFORE (production at 464 with 462 in, as on the copies, 24 Oct 2026; md5
-- of pg_get_functiondef with search_path public)
--   changed
--   invoice_own_voucher_ids(uuid)                                      9340840f1ce4e031ec3613198688ba2e  (460's; pinned by 464)
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)             130c25c6ce3d91b7b421e6f4c3d02353  (462's)
--   invoice_transferable_benefits(uuid)                                d0d19b7c765337c3cd68096fdc6de7dd  (462's)
--   apply_reopened_invoice_benefits()                                  4efef2f1e97bed6a3f0eed0df4e2df51  (462's)
--   credit_given_back_follows(uuid)                                    9d75978de5b247a8de1aaee4e894a698  (462's)
--   preview_invoice_correction(uuid,jsonb)                             3047239c7418179e84927f6f00e7f2eb  (458's)
--   create_invoice_with_details(uuid,uuid,jsonb,jsonb)                 770ee0129b0e9fe909259ad7ea95b8d0  (456's)
--   apply_reopened_invoice_vouchers()                                  28d3b7a69b91ddebcdb200559d96a0ef  (460's; pinned by 464)
--   invoice_benefit_moved_to_other(uuid)                               (not there)
--   invoice_benefit_moved_from_spent(uuid)                             (not there)
--   relied on, not changed (pinned)
--   invoice_credit_lot_ids(uuid)                                       50346a2e9aea50b31d4207c43b2f197c
--   invoice_benefits_holder(uuid,uuid,timestamp with time zone)        55995ff6e1ffd4a1172cb930512a34b0  (460's)
--   invoice_credit_live_holder(uuid,uuid,timestamp with time zone)     a5692590ef3e8a7a7dd7e8ff7cfa9568  (462's)
--   credit_lot_ancestry(uuid)                                          52b3cae789b6b52a12bb2f798af40cbe  (462's)
--   trg_credit_given_back_follows()                                    84e2d978b74b56a9508e4f4f5b518c22  (462's)
--   invoice_credit_transfer_origin(uuid)                               1e8beeccfbf7e432edffc1598acddb53  (462's)
--   invoice_benefit_unused_elsewhere(uuid)                             d35d7c8ae7187985ea64f8a5c38a7d79
--   transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)          7aebd7120bc3928db46df0941cb20889
--   merge_customer_records(uuid,uuid,text,uuid)                        ba05c2b1fb4c0e14d369c01d06a635b0  (462's)
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                        04d647e13e9424a9375942e5812e91a2  (464's)
--   cancel_invoice_recorded(uuid,text,uuid)                            de52d9dbaef8ab15163bef35cb9d733d
--   reopen_invoice(uuid,text,uuid)                                     0ff61e4ead121c198ea7f90a7fc78274  (458's)
--   invoice_reopen_preview(uuid)                                       e09ebf9c0841ef5463f96b26f4933541  (462's)
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)          804ecd829cfecf713783a09a05d93c7e
--   issue_premium_bundle_invoice_item(uuid)                            9981515e45c3e79a41d36f96acbf000b
--   sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid) 3cee8de4ce6361744a9d57b172e84563
--   capture_invoice_benefit_values(uuid)                               d5e061945c2921a1af86f8c99a349e98
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)       80c80d386a5241e63b353e35e13ef250
--   event_vip_make_invoices(uuid,boolean)                              026c6f301e6040d9954757ba559839ba
--   web_order_make_invoice(uuid,uuid,boolean,boolean)                  9d4bd47df0bb803a5f7958249175979f
--   delete_customer(uuid,text,text)                                    5b407735574fc3cacd8067c4dc8213f4
--   ensure_customer_wallet(uuid)                                       8ef18daebbbe3c12f2024290ea8416e8
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   trigger credit_given_back_follows on customer_credit_ledger         as 462 made it (text pinned in the file)
--   public function fingerprint, production with 462 in               43aeae86af2c9a9c824182284fbdbbdd (1384 functions) (at 464 with 462 in: 055ad62ecb57d228932cb70900dcc077, 1383)
--   grant list (string_agg(signature '=' proacl, '|')), the same        95be5abc774a6fb5d9e998614c6eb5b5 (at 464 with 462: 6e250747df5caf63135469985f52a6da; production lists
--                                                                      the same grants in another order: compare as sets)
-- AFTER (for later guards)
--   invoice_own_voucher_ids(uuid)                                      ee0202627b9500dcbad103d3ade2401f
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)             c01606c84ee13ddcd88c15521d6d9aed
--   invoice_transferable_benefits(uuid)                                68736a39ed765ee787242bc62bbaeebb
--   apply_reopened_invoice_benefits()                                  36eaa7224e514d3e7e42e3eeb51acfb5
--   credit_given_back_follows(uuid)                                    844b73106bbf362768ed4a899ceb00d5
--   preview_invoice_correction(uuid,jsonb)                             f26752231c100461e11caddc03c98a33
--   create_invoice_with_details(uuid,uuid,jsonb,jsonb)                 0ac29c7aa909dd756ec572645ca86448
--   apply_reopened_invoice_vouchers()                                  6684840544d1ad8a28e2415934300054
--   invoice_benefit_moved_to_other(uuid)                               7016bed898e1bbe9d0ac4a05037d07c2  (new; service role alone)
--   invoice_benefit_moved_from_spent(uuid)                             901fde963b051cfd93fcd9f7dab7149e  (new; service role alone)
--   public function fingerprint, worked out on copies (24 Oct 2026; a second run the same):
--     production now (467 in) -> 462 -> 463                            dad8b7fc88a31f93c91771dd904367d4 (1386 functions: two new, none dropped)
--     with 466 in too (467, 466) -> 462 -> 463                         6d96407cdeb903712a2d7be7016aa9a6 (1387; 466 alone: 41a2fcab, 1381; with 462: cb35d3dc, 1385)
--     464 -> 462 -> 463 (the suites' copy)                             8f41d41b1af3cd07cd2de7453fa4ec11 (1385)
--   grant list after 463: at 467 e659be1b2560dfd42e0c6c951e5bd728, at 464 3195cc9fe9a848eac7e8e43123c41e80 (compare as sets)
--
-- Test: scripts/invoices/tests/change-store-moves-bundle-vouchers-463.sql
-- (begin ... rollback; it installs 462 first where it is not in, then this
-- file twice; -v nomig=1 where both are in). It reproduces each case first
-- (without 463), then checks the header's query, the refusals, the install,
-- every case after 463 with 462's invariants (463's holder rule), the stock
-- of a limited voucher, the summary while a reopening waits (W1), the
-- removed record (K6s), cases begun before 463 and finished after (also
-- cancelled, refunded or waiting when it goes in), and NOT COVERED 1 and 2
-- as KNOWN. Each step's vouchers are dated when the step ends, as each call
-- commits on its own in the app. Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The eight functions this changes: BEFORE (production at 464 with 462
  -- in, 24 Oct 2026: 462's, 458's, 456's and 460's AFTERs) and AFTER md5s;
  -- who may call each, as read (kept). 1 is replaced whole (its text below);
  -- 2 to 8 are patched at anchors (below) ═════════════════════════════════════
  c_sigs constant text[] := array[
    'invoice_own_voucher_ids(uuid)',
    'move_invoice_benefits_to_customer(uuid,uuid,uuid,text)',
    'invoice_transferable_benefits(uuid)',
    'apply_reopened_invoice_benefits()',
    'credit_given_back_follows(uuid)',
    'preview_invoice_correction(uuid,jsonb)',
    'create_invoice_with_details(uuid,uuid,jsonb,jsonb)',
    'apply_reopened_invoice_vouchers()'];
  c_before constant text[] := array[
    '9340840f1ce4e031ec3613198688ba2e',
    '130c25c6ce3d91b7b421e6f4c3d02353',
    'd0d19b7c765337c3cd68096fdc6de7dd',
    '4efef2f1e97bed6a3f0eed0df4e2df51',
    '9d75978de5b247a8de1aaee4e894a698',
    '3047239c7418179e84927f6f00e7f2eb',
    '770ee0129b0e9fe909259ad7ea95b8d0',
    '28d3b7a69b91ddebcdb200559d96a0ef'];
  c_after constant text[] := array[
    'ee0202627b9500dcbad103d3ade2401f',
    'c01606c84ee13ddcd88c15521d6d9aed',
    '68736a39ed765ee787242bc62bbaeebb',
    '36eaa7224e514d3e7e42e3eeb51acfb5',
    '844b73106bbf362768ed4a899ceb00d5',
    'f26752231c100461e11caddc03c98a33',
    '0ac29c7aa909dd756ec572645ca86448',
    '6684840544d1ad8a28e2415934300054'];
  c_acl constant text[] := array[
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',
    '{postgres=X/postgres,service_role=X/postgres}'];
  -- ══ The two functions this adds (the server's alone) ════════════════════
  c_new constant text[] := array['invoice_benefit_moved_to_other(uuid)', 'invoice_benefit_moved_from_spent(uuid)'];
  c_new_after constant text[] := array['7016bed898e1bbe9d0ac4a05037d07c2', '901fde963b051cfd93fcd9f7dab7149e'];
  c_new_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';

  -- ══ The whole texts (each exactly as the database prints it back) ═══════
  c_def_moved constant text := $d1$CREATE OR REPLACE FUNCTION public.invoice_benefit_moved_to_other(p_benefit_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 463 (the Owner, 24 Oct 2026, decision 2: a Move to the same customer at
  -- another store is a store correction, which a later customer change that
  -- takes the benefits along takes along): whether an invoice's benefit row
  -- is what an Owner moved to someone else (transfer_invoice_unused_benefit,
  -- 434: its recipient keeps it, following merges alone), or a Move of such
  -- a row. A Move to the same customer (the Move's own snapshots name the
  -- same customer before and after it; the Move refuses the same customer at
  -- the same store) leaves the row the invoice's own, as the row it was
  -- moved from is. False for a row no Move made.
  with recursive m(benefit_id, other, n) as (
    select t.source_benefit_id,
           (t.before_snapshot->>'customer_id') is distinct from coalesce(t.after_snapshot->>'customer_id', t.customer_id::text),
           0
      from public.invoice_benefit_transfers t
     where t.replacement_benefit_id = p_benefit_id
    union all
    select t.source_benefit_id,
           (t.before_snapshot->>'customer_id') is distinct from coalesce(t.after_snapshot->>'customer_id', t.customer_id::text),
           m.n + 1
      from m
      join public.invoice_benefit_transfers t on t.replacement_benefit_id = m.benefit_id
     where not m.other and m.n < 64)
  select coalesce(bool_or(m.other), false) from m
$function$
$d1$;
  c_def_spent constant text := $d3$CREATE OR REPLACE FUNCTION public.invoice_benefit_moved_from_spent(p_benefit_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 463 (the critics of 24 Oct 2026; 461's rule, kept for a store
  -- correction): whether an invoice's benefit row that an Owner's Move made
  -- (transfer_invoice_unused_benefit) came from a row partly spent before
  -- the Move: back along the Move's chain to the sale's row, a credit row
  -- whose lot holds, with what a cancellation took back and what is not used
  -- although it is no longer on the row (invoice_benefit_unused_elsewhere:
  -- what a Move took, what a line refund paid back), less than the row
  -- granted. A Move gives its row only what was left, so that row alone
  -- says nothing of what was spent before it (as 462 judges a reissued lot
  -- by its benefit row). Read for credit an Owner moved to the same customer
  -- at another store, which a customer change that takes the benefits along
  -- takes along (decision 2): spent before the Move, it blocks the change as
  -- "Partly spent", as the same credit without the Move does
  -- (invoice_transferable_benefits, move_invoice_benefits_to_customer).
  -- False for a row no Move made, or one whose rows show no spending.
  with recursive m(benefit_id, n) as (
    select t.source_benefit_id, 0
      from public.invoice_benefit_transfers t
     where t.replacement_benefit_id = p_benefit_id
    union all
    select t.source_benefit_id, m.n + 1
      from m
      join public.invoice_benefit_transfers t on t.replacement_benefit_id = m.benefit_id
     where m.n < 64)
  select coalesce(bool_or(coalesce(l.remaining_amount, 0) + b.cancelled_unused_value
                          + public.invoice_benefit_unused_elsewhere(b.id) < b.granted_value), false)
    from m
    join public.invoice_benefit_values b on b.id = m.benefit_id and b.lot_id is not null
    left join public.customer_credit_lots l on l.id = b.lot_id
$function$
$d3$;
  c_def_own constant text := $d2$CREATE OR REPLACE FUNCTION public.invoice_own_voucher_ids(p_invoice_id uuid)
 RETURNS TABLE(voucher_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 460 (the Owner, 22 Oct 2026: "fix the other two rare gaps too"): the
  -- invoice's own vouchers, which a customer change that takes the benefits
  -- along moves (move_invoice_benefits_to_customer) and lists
  -- (invoice_transferable_benefits), and which a reopening gives again to
  -- whoever holds the benefits (apply_reopened_invoice_vouchers): what its
  -- voucher and promotion lines gave (sources 'invoice_voucher_sale',
  -- 'invoice_promotion_voucher'), and every voucher given again in place of
  -- one of them, by a reopening or by the payment after an FOC was taken off
  -- (source 'invoice_reopen', named by invoice_reopen_vouchers.
  -- replacement_voucher_id), however many times.
  -- 463 (the Owner, 24 Oct 2026, decisions 2 and 3): also what a Premium
  -- Bundle sold on the invoice gave (source 'premium_bundle', its sale's id):
  -- they follow a customer change that takes the benefits along, as the
  -- bundle's credit does; and a voucher an Owner moved from one of them to
  -- the same customer at another store (a store correction: source
  -- 'invoice_benefit_transfer', invoice_benefit_moved_to_other), with those
  -- given again in its place. Not a voucher an Owner moved to someone else
  -- (it stays with them, 434) nor one given again in its place.
  with recursive own(id, n) as (
    select crv.id, 0
      from public.customer_reward_vouchers crv
     where crv.source_type in ('invoice_voucher_sale','invoice_promotion_voucher')
       and crv.source_id in (select it.id from public.invoice_items it where it.invoice_id = p_invoice_id)
    union all
    select crv.id, 0
      from public.customer_reward_vouchers crv
     where crv.source_type = 'premium_bundle'
       and crv.source_id in (select s.id from public.premium_bundle_sales s where s.invoice_id = p_invoice_id)
    union all
    select x.id, o.n + 1
      from own o
      join public.invoice_benefit_values b on b.reward_voucher_id = o.id and b.invoice_id = p_invoice_id
      cross join lateral (
        select q.replacement_voucher_id as id
          from public.invoice_reopen_vouchers q
         where q.benefit_id = b.id and q.invoice_id = p_invoice_id and q.replacement_voucher_id is not null
        union all
        select rb.reward_voucher_id
          from public.invoice_benefit_transfers t
          join public.invoice_benefit_values rb on rb.id = t.replacement_benefit_id
         where t.source_benefit_id = b.id and t.invoice_id = p_invoice_id and rb.reward_voucher_id is not null
           and not public.invoice_benefit_moved_to_other(rb.id)) x
     where o.n < 64)
  select distinct o.id from own o
$function$
$d2$;

  -- ══ The anchors: each is found exactly once in its function's BEFORE text
  -- and replaced by its patch; the text built must have the AFTER md5 ══════
  c_fn constant int[] := array[2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 4, 5, 6, 6, 6, 7, 8, 8];
  c_anchor constant text[] := array[
    $a1$        r_lot public.customer_credit_lots%rowtype; v_new_lot uuid;
$a1$,
    $a2$   order by id for update;
  for v417 in
$a2$,
    $a3$       and p_store_id is not null and rv.store_id is not null and rv.store_id <> p_store_id
$a3$,
    $a4$  update public.customer_reward_vouchers
     set customer_id = p_customer_id, store_id = p_store_id
$a4$,
    $a5$     where l.id in (select lot_id from public.invoice_credit_lot_ids(p_invoice_id))
$a5$,
    $a6$       and l.remaining_amount > 0
       and l.status = 'active'
$a6$,
    $a7$   where l.id in (select lot_id from public.invoice_credit_lot_ids(p_invoice_id))
$a7$,
    $a8$         l.status = 'active' and l.remaining_amount > 0
           and (w.untouched or coalesce(u.moves, false)),
         l.remaining_amount > 0 and not w.untouched and not coalesce(u.moves, false),
$a8$,
    $a9$              when not w.untouched and not coalesce(u.moves, false) then 'Partly spent'
$a9$,
    $a10$                               and (l.reassigned_from_lot_id is null or u.named is null) as untouched) w
$a10$,
    $a11$            case when exists(select 1 from public.invoice_benefit_values b
                               join public.invoice_benefit_transfers bt on bt.replacement_benefit_id=b.id
                              where b.invoice_id=new.id and b.lot_id=t.id) then 'infinity'::timestamptz
                 else t.created_at end),
$a11$,
    $a12$                  case when exists(select 1 from public.invoice_benefit_transfers t where t.replacement_benefit_id=b.id)
                       then 'infinity'::timestamptz else n.created_at end),
$a12$,
    $a13$        v416_back jsonb; v416_kept jsonb;  -- 416: the vouchers removing the FOC takes back or leaves
$a13$,
    $a14$        'detail','These have already been used and will not move. The correction is refused until each is resolved through the benefit transfer review.'));
    end if;
$a14$,
    $a15$                               and crv.customer_id is distinct from v_new_cust
$a15$,
    $a16$     return v_prev.id;
   end if;
 end if;
$a16$,
    $a17$  -- At that voucher's store, as before.
$a17$,
    $a18$               then public.invoice_benefits_holder(new.id,v.customer_id,v.issued_at) else v.customer_id end,
$a18$];
  c_patch constant text[] := array[
    $p1$        r_lot public.customer_credit_lots%rowtype; v_new_lot uuid;
        v463_kept uuid[];  -- 463: vouchers that keep their store
$p1$,
    $p2$   order by id for update;
  -- 463 (the Owner, 24 Oct 2026, decisions 2 and 3): a voucher an Owner
  -- moved to the same customer at another store (a store correction, which
  -- a customer change that takes the benefits along takes along), and a
  -- Premium Bundle's (they follow such a change as the bundle's credit
  -- does), and one given again in place of either, is one of the invoice's
  -- own now (invoice_own_voucher_ids): it moves to the new customer and
  -- keeps its store, as credit keeps its store: no stock moves for it. The
  -- voucher and promotion lines' go to the invoice's store, as before (417).
  v463_kept := array(
    with recursive k(id, n) as (
      select o.voucher_id, 0
        from public.invoice_own_voucher_ids(p_invoice_id) o
        join public.customer_reward_vouchers c on c.id = o.voucher_id
       where c.source_type in ('invoice_benefit_transfer', 'premium_bundle')
      union all
      select q.replacement_voucher_id, k.n + 1
        from k
        join public.invoice_benefit_values b on b.reward_voucher_id = k.id and b.invoice_id = p_invoice_id
        join public.invoice_reopen_vouchers q on q.benefit_id = b.id and q.invoice_id = p_invoice_id
       where q.replacement_voucher_id is not null and k.n < 64)
    select distinct k.id from k);
  for v417 in
$p2$,
    $p3$       and p_store_id is not null and rv.store_id is not null and rv.store_id <> p_store_id
       and rv.id <> all (v463_kept)   -- 463
$p3$,
    $p4$  update public.customer_reward_vouchers
     set customer_id = p_customer_id,
         store_id = case when id = any (v463_kept) then store_id else p_store_id end   -- 463
$p4$,
    $p5$     where (l.id in (select lot_id from public.invoice_credit_lot_ids(p_invoice_id))
            -- 463 (the Owner, 24 Oct 2026, decision 2): and credit an Owner
            -- moved to the same customer at another store (a store
            -- correction): the lot its benefit row names now, which stays
            -- the invoice's own (invoice_benefit_moved_to_other), so it
            -- moves with its records, keeping its store, as the invoice's
            -- own credit does. Not a Move to someone else (its recipient
            -- keeps it, 434).
            or l.id in (select b.lot_id from public.invoice_benefit_values b
                         where b.invoice_id = p_invoice_id and b.lot_id is not null
                           and exists (select 1 from public.invoice_benefit_transfers t
                                        where t.replacement_benefit_id = b.id)
                           and not public.invoice_benefit_moved_to_other(b.id)))
$p5$,
    $p6$       and l.remaining_amount > 0
       and l.status = 'active'
       -- 463: nor credit an Owner moved to the same customer at another
       -- store from a benefit row partly spent before the Move
       -- (invoice_benefit_moved_from_spent: the list blocks the change for
       -- it, "Partly spent", as for the invoice's own credit), read again
       -- once the lot is locked.
       and not exists (select 1 from public.invoice_benefit_values b
                        where b.lot_id = l.id and b.invoice_id = p_invoice_id
                          and public.invoice_benefit_moved_from_spent(b.id))
$p6$,
    $p7$   where (l.id in (select lot_id from public.invoice_credit_lot_ids(p_invoice_id))
          -- 463 (the Owner, 24 Oct 2026, decision 2): and credit an Owner
          -- moved to the same customer at another store, which stays the
          -- invoice's own (invoice_benefit_moved_to_other), as the change
          -- moves it (move_invoice_benefits_to_customer).
          or l.id in (select b.lot_id from public.invoice_benefit_values b
                       where b.invoice_id = p_invoice_id and b.lot_id is not null
                         and exists (select 1 from public.invoice_benefit_transfers t
                                      where t.replacement_benefit_id = b.id)
                         and not public.invoice_benefit_moved_to_other(b.id)))
$p7$,
    $p8$         l.status = 'active' and l.remaining_amount > 0
           and (w.untouched or coalesce(u.moves, false)) and not s.spent_before,
         l.remaining_amount > 0 and (not w.untouched and not coalesce(u.moves, false) or s.spent_before),
$p8$,
    $p9$              when not w.untouched and not coalesce(u.moves, false) or s.spent_before then 'Partly spent'
$p9$,
    $p10$                               and (l.reassigned_from_lot_id is null or u.named is null) as untouched) w
    -- 463: credit an Owner moved to the same customer at another store (a
    -- store correction) from a benefit row partly spent before the Move:
    -- the Move gave its row only what was left, so the row alone looks
    -- untouched; it is judged by the rows it was moved from too
    -- (invoice_benefit_moved_from_spent), so it blocks the change as
    -- "Partly spent", as the same credit without the Move does (461).
    cross join lateral (select exists (select 1 from public.invoice_benefit_values b
                                        where b.lot_id = l.id and b.invoice_id = p_invoice_id
                                          and public.invoice_benefit_moved_from_spent(b.id)) as spent_before) s
$p10$,
    $p11$            -- 463 (the Owner, 24 Oct 2026, decision 2): a lot an Owner moved
            -- to someone else follows merges alone; one moved to the same
            -- customer at another store is the invoice's own
            -- (invoice_benefit_moved_to_other), and follows a later change.
            case when exists(select 1 from public.invoice_benefit_values b
                              where b.invoice_id=new.id and b.lot_id=t.id
                                and public.invoice_benefit_moved_to_other(b.id)) then 'infinity'::timestamptz
                 else t.created_at end),
$p11$,
    $p12$                  -- 463 (the Owner, 24 Oct 2026, decision 2): only a Move to
                  -- someone else stays with its recipient (merges followed);
                  -- a Move to the same customer at another store is the
                  -- invoice's own (invoice_benefit_moved_to_other).
                  case when public.invoice_benefit_moved_to_other(b.id)
                       then 'infinity'::timestamptz else n.created_at end),
$p12$,
    $p13$        v416_back jsonb; v416_kept jsonb;  -- 416: the vouchers removing the FOC takes back or leaves
        v463_waiting jsonb;  -- 463: what a reopening that waits gives the new customer
$p13$,
    $p14$        'detail','These have already been used and will not move. The correction is refused until each is resolved through the benefit transfer review.'));
    end if;
    -- 463 (460's NOT COVERED 7, W1): a reopening that waits to be settled
    -- gives its credit and vouchers back when the invoice is paid, to whoever
    -- holds the benefits then (apply_reopened_invoice_benefits and _vouchers):
    -- after a change that takes them along, the new customer. So they are
    -- listed too: by credit category and by voucher, as the payment will
    -- give them. Not what an Owner moved to someone else (its recipient
    -- keeps it), nor with 'keep' (they stay with whoever holds them).
    if coalesce(p_header->>'benefit_action','') <> 'keep' then
      select coalesce(jsonb_agg(jsonb_build_object('kind', w.kind, 'what', w.what) order by w.ord, w.what), '[]'::jsonb)
        into v463_waiting
        from (select 'credit' as kind, 1 as ord,
                     initcap(l.category) || ' credit ' || sum(q.amount)::text as what
                from public.invoice_reopen_benefits q
                join public.customer_credit_ledger e on e.id = q.source_ledger_id
                join public.customer_credit_lots l on l.id = e.lot_id
               where q.invoice_id = i.id and q.applied_at is null
                 and not exists (select 1 from public.invoice_benefit_values b
                                  where b.invoice_id = i.id and b.lot_id is not null
                                    and e.lot_id = any (public.credit_lot_ancestry(b.lot_id))
                                    and public.invoice_benefit_moved_to_other(b.id))
               group by l.category
              union all
              select 'voucher', 2, vo.name || ' × ' || sum(q.quantity)::text
                from public.invoice_reopen_vouchers q
                join public.invoice_benefit_values b on b.id = q.benefit_id
                join public.customer_reward_vouchers crv on crv.id = b.reward_voucher_id
                join public.vouchers vo on vo.id = crv.voucher_id
               where q.invoice_id = i.id and q.applied_at is null
                 and crv.id in (select o.voucher_id from public.invoice_own_voucher_ids(i.id) o)
               group by vo.name) w;
      if jsonb_array_length(v463_waiting) > 0 then
        v_effects := v_effects || jsonb_build_array(jsonb_build_object(
          'area','benefits','change','transferring','items',v463_waiting,
          'detail','The invoice''s reopening waits for its payment. When it is paid, these go back to the new customer, with their original source, deadlines and restrictions unchanged.'));
      end if;
    end if;
$p14$,
    $p15$                               and crv.customer_id is distinct from v_new_cust
                               -- 463: not one this save moves to the invoice's customer (one of
                               -- the invoice's own, invoice_own_voucher_ids, with 'transfer':
                               -- a store-moved or a Premium Bundle's too now), as in the save,
                               -- which moves it before it takes the vouchers back
                               and not (coalesce(p_header->>'benefit_action','') = 'transfer'
                                        and (v_new_cust, v_new_store) is distinct from (i.customer_id, i.store_id)
                                        and crv.status = 'held' and crv.redeemed_at is null
                                        and crv.id in (select o.voucher_id from public.invoice_own_voucher_ids(i.id) o))
$p15$,
    $p16$     return v_prev.id;
   end if;
 end if;
 -- 463 (K6s): never for a customer record a merge retired or Delete
 -- customer removed. The pages cannot pick one (the customers read policy
 -- hides them), but a form left open across a merge could send one; such
 -- an invoice spent the retired record's credit, and its plans then asked a
 -- false credit_used. A request already made is given back above, as before.
 if p_customer_id is not null
    and exists (select 1 from public.customers c where c.id = p_customer_id and c.deleted_at is not null) then
   raise exception 'This customer''s record was merged into another or deleted. Choose the customer again.'; end if;
$p16$,
    $p17$  -- At that voucher's store, as before.
  -- 463 (the Owner, 24 Oct 2026, decisions 2 and 3): a Premium Bundle's,
  -- and one an Owner moved to the same customer at another store, are the
  -- invoice's own now (invoice_own_voucher_ids), so what is given again in
  -- their place goes to whoever holds the benefits too. And the holder is
  -- read from when the first voucher of the chain was given (the line's, the
  -- bundle's, or the store-moved one's source: back along the vouchers given
  -- again in place of each other, invoice_reopen_vouchers, and the Move,
  -- invoice_benefit_transfers), not from when the one it replaces was
  -- given: one given again to the old customer after a customer change
  -- that took the benefits along (before 463, a bundle's or a store-moved
  -- one) went back to that customer at every later reopening.
$p17$,
    $p18$               then public.invoice_benefits_holder(new.id,v.customer_id,
                      (with recursive r(id,ts,n) as (
                         select v.id,v.issued_at,0
                         union all
                         select p.id,p.issued_at,r.n+1
                           from r
                           cross join lateral (
                             select pb.reward_voucher_id as id
                               from public.invoice_reopen_vouchers q2
                               join public.invoice_benefit_values pb on pb.id=q2.benefit_id
                              where q2.replacement_voucher_id=r.id and q2.invoice_id=new.id
                             union all
                             select sb.reward_voucher_id
                               from public.invoice_benefit_values rb
                               join public.invoice_benefit_transfers t on t.replacement_benefit_id=rb.id
                               join public.invoice_benefit_values sb on sb.id=t.source_benefit_id
                              where rb.reward_voucher_id=r.id and t.invoice_id=new.id) x
                           join public.customer_reward_vouchers p on p.id=x.id
                          where r.n<64)
                       select min(r.ts) from r))
               else v.customer_id end,
$p18$];

  -- ══ Relied on, not changed (pinned): as read on a copy of production at
  -- 464 with 462 in (24 Oct 2026) ═══════════════════════════════════════════
  c_relied constant text[] := array[
    'invoice_credit_lot_ids(uuid)',
    'invoice_benefits_holder(uuid,uuid,timestamp with time zone)',
    'invoice_credit_live_holder(uuid,uuid,timestamp with time zone)',
    'credit_lot_ancestry(uuid)',
    'trg_credit_given_back_follows()',
    'invoice_credit_transfer_origin(uuid)',
    'invoice_benefit_unused_elsewhere(uuid)',
    'transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)',
    'merge_customer_records(uuid,uuid,text,uuid)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'reopen_invoice(uuid,text,uuid)',
    'invoice_reopen_preview(uuid)',
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'issue_premium_bundle_invoice_item(uuid)',
    'sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid)',
    'capture_invoice_benefit_values(uuid)',
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    'event_vip_make_invoices(uuid,boolean)',
    'web_order_make_invoice(uuid,uuid,boolean,boolean)',
    'delete_customer(uuid,text,text)',
    'ensure_customer_wallet(uuid)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)'];
  c_relied_md5 constant text[] := array[
    '50346a2e9aea50b31d4207c43b2f197c',
    '55995ff6e1ffd4a1172cb930512a34b0',
    'a5692590ef3e8a7a7dd7e8ff7cfa9568',
    '52b3cae789b6b52a12bb2f798af40cbe',
    '84e2d978b74b56a9508e4f4f5b518c22',
    '1e8beeccfbf7e432edffc1598acddb53',
    'd35d7c8ae7187985ea64f8a5c38a7d79',
    '7aebd7120bc3928db46df0941cb20889',
    'ba05c2b1fb4c0e14d369c01d06a635b0',
    '04d647e13e9424a9375942e5812e91a2',
    'de52d9dbaef8ab15163bef35cb9d733d',
    '0ff61e4ead121c198ea7f90a7fc78274',
    'e09ebf9c0841ef5463f96b26f4933541',
    '804ecd829cfecf713783a09a05d93c7e',
    '9981515e45c3e79a41d36f96acbf000b',
    '3cee8de4ce6361744a9d57b172e84563',
    'd5e061945c2921a1af86f8c99a349e98',
    '80c80d386a5241e63b353e35e13ef250',
    '026c6f301e6040d9954757ba559839ba',
    '9d4bd47df0bb803a5f7958249175979f',
    '5b407735574fc3cacd8067c4dc8213f4',
    '8ef18daebbbe3c12f2024290ea8416e8',
    'c705c733e213a27f0dc32d54322cc855'];
  -- Who else calls the changed functions, as read (by name; not counting the
  -- eight themselves and the two added, whose texts are pinned above, nor a
  -- session's own temporary functions).
  c_callers constant text[] := array[
    'invoice_own_voucher_ids=',
    'move_invoice_benefits_to_customer=correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'invoice_transferable_benefits=correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'apply_reopened_invoice_benefits=',
    'credit_given_back_follows=trg_credit_given_back_follows()',
    'preview_invoice_correction=',
    'create_invoice_with_details=event_vip_make_invoices(uuid,boolean), web_order_make_invoice(uuid,uuid,boolean,boolean)',
    'apply_reopened_invoice_vouchers='];
  -- What gives a Premium Bundle's vouchers (source 'premium_bundle'), as read.
  c_bundle_writers constant text := 'issue_premium_bundle_invoice_item(uuid), sell_premium_bundle(uuid,uuid,uuid,jsonb,jsonb,numeric,numeric,uuid,boolean,uuid)';
  -- 462's trigger, as 462 made it (463 builds on 462).
  c_trg_def constant text := 'CREATE CONSTRAINT TRIGGER credit_given_back_follows AFTER INSERT ON public.customer_credit_ledger DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (((new.entry_type = ''reverse''::text) AND (new.lot_id IS NOT NULL) AND (new.source_type = ANY (ARRAY[''invoice_payment_refund''::text, ''payment_correction''::text, ''special_sale''::text, ''rental''::text, ''rental_late_fee''::text])))) EXECUTE FUNCTION trg_credit_given_back_follows()';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; n int; k int; i int; v_first boolean; v_left int := 0;
  v_defs text[] := '{}'; v_acl text[] := '{}'; v_built text[];
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_store2 uuid; t_cash uuid; t_pk uuid; t_v uuid; t_pb uuid;
  t_a uuid; t_b uuid; t_c uuid; t_d uuid; t_e uuid; t_g uuid; t_h uuid; t_inv uuid; t_lot uuid; t_ben uuid; t_ben2 uuid;
  t_ans jsonb; t_msg text; t_k uuid;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The texts are the tested ones.
  if md5(c_def_own) <> c_after[1] or md5(c_def_moved) <> c_new_after[1] or md5(c_def_spent) <> c_new_after[2]
     or cardinality(c_anchor) <> cardinality(c_fn) or cardinality(c_patch) <> cardinality(c_fn) then
    raise exception '463: a text in this file is not the tested one'; end if;

  -- The functions relied on are as read (462 is in: its functions and its
  -- trigger are as 462 made them).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '463: public.% is missing or not the version this was tested against (md5 %). 463 goes in after 462; re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if (select pg_get_triggerdef(oid) from pg_trigger where tgrelid = 'public.customer_credit_ledger'::regclass
       and tgname = 'credit_given_back_follows') is distinct from c_trg_def then
    raise exception '463: 462''s trigger credit_given_back_follows is not there as 462 made it; 463 goes in after 462'; end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.invoices'::regclass and tgname = 'invoice_reopen_benefits_settled'
                  and tgfoid = 'public.apply_reopened_invoice_benefits()'::regprocedure and not tgisinternal)
     or not exists (select 1 from pg_trigger where tgrelid = 'public.invoices'::regclass and tgname = 'invoice_reopen_vouchers_settled'
                     and tgfoid = 'public.apply_reopened_invoice_vouchers()'::regprocedure and not tgisinternal) then
    raise exception '463: the reopening''s settlement is no longer run by invoice_reopen_benefits_settled and invoice_reopen_vouchers_settled'; end if;

  -- The columns read, with these types.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('invoice_benefit_transfers', 'id', 'uuid'), ('invoice_benefit_transfers', 'invoice_id', 'uuid'),
                 ('invoice_benefit_transfers', 'source_benefit_id', 'uuid'), ('invoice_benefit_transfers', 'replacement_benefit_id', 'uuid'),
                 ('invoice_benefit_transfers', 'customer_id', 'uuid'), ('invoice_benefit_transfers', 'before_snapshot', 'jsonb'),
                 ('invoice_benefit_transfers', 'after_snapshot', 'jsonb'),
                 ('invoice_benefit_values', 'id', 'uuid'), ('invoice_benefit_values', 'invoice_id', 'uuid'),
                 ('invoice_benefit_values', 'lot_id', 'uuid'), ('invoice_benefit_values', 'reward_voucher_id', 'uuid'),
                 ('invoice_benefit_values', 'granted_value', 'numeric(12,2)'), ('invoice_benefit_values', 'cancelled_unused_value', 'numeric(12,2)'),
                 ('customer_reward_vouchers', 'id', 'uuid'), ('customer_reward_vouchers', 'customer_id', 'uuid'),
                 ('customer_reward_vouchers', 'store_id', 'uuid'), ('customer_reward_vouchers', 'source_type', 'text'),
                 ('customer_reward_vouchers', 'source_id', 'uuid'), ('customer_reward_vouchers', 'status', 'text'),
                 ('customer_reward_vouchers', 'redeemed_at', 'timestamp with time zone'), ('customer_reward_vouchers', 'voucher_id', 'uuid'),
                 ('customer_reward_vouchers', 'issued_at', 'timestamp with time zone'),
                 ('premium_bundle_sales', 'id', 'uuid'), ('premium_bundle_sales', 'invoice_id', 'uuid'),
                 ('invoice_reopen_vouchers', 'invoice_id', 'uuid'), ('invoice_reopen_vouchers', 'benefit_id', 'uuid'),
                 ('invoice_reopen_vouchers', 'quantity', 'integer'), ('invoice_reopen_vouchers', 'replacement_voucher_id', 'uuid'),
                 ('invoice_reopen_vouchers', 'applied_at', 'timestamp with time zone'),
                 ('invoice_reopen_benefits', 'invoice_id', 'uuid'), ('invoice_reopen_benefits', 'source_ledger_id', 'uuid'),
                 ('invoice_reopen_benefits', 'amount', 'numeric(12,2)'), ('invoice_reopen_benefits', 'applied_at', 'timestamp with time zone'),
                 ('customer_credit_ledger', 'id', 'uuid'), ('customer_credit_ledger', 'lot_id', 'uuid'),
                 ('customer_credit_lots', 'id', 'uuid'), ('customer_credit_lots', 'customer_id', 'uuid'),
                 ('customer_credit_lots', 'category', 'text'), ('customer_credit_lots', 'remaining_amount', 'numeric(12,2)'),
                 ('customer_credit_lots', 'status', 'text'), ('customer_credit_lots', 'created_at', 'timestamp with time zone'),
                 ('vouchers', 'id', 'uuid'), ('vouchers', 'name', 'text'),
                 ('customers', 'id', 'uuid'), ('customers', 'deleted_at', 'timestamp with time zone'),
                 ('invoices', 'id', 'uuid'), ('invoices', 'customer_id', 'uuid'), ('invoices', 'invoice_no', 'text')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '463: these columns are missing or not as read on 24 Oct 2026: %', v; end if;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('invoice_own_voucher_ids', 'move_invoice_benefits_to_customer', 'invoice_transferable_benefits',
                       'apply_reopened_invoice_benefits', 'credit_given_back_follows', 'preview_invoice_correction',
                       'create_invoice_with_details', 'apply_reopened_invoice_vouchers',
                       'invoice_benefit_moved_to_other', 'invoice_benefit_moved_from_spent')
     and p.oid::regprocedure::text <> all (c_sigs || c_new);
  if v is not null then raise exception '463: another function takes the name of one this changes or adds: %', v; end if;

  -- Who else calls them, as read.
  foreach v in array c_callers loop
    select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into d
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where p.prosrc ~ (split_part(v, '=', 1) || '\s*\(') and ns.nspname not like 'pg\_temp\_%'
       and p.proname <> split_part(v, '=', 1)
       and not (ns.nspname = 'public' and p.oid::regprocedure::text = any (c_sigs || c_new));
    if coalesce(d, '') is distinct from split_part(v, '=', 2) then
      raise exception '463: the functions that call % are not as read on 24 Oct 2026 (%); check each, then re-test', split_part(v, '=', 1), d; end if;
  end loop;

  -- What gives a Premium Bundle's vouchers, as read (a new way would need its
  -- source in invoice_own_voucher_ids).
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~* 'insert\s+into\s+(public\.)?customer_reward_vouchers' and p.prosrc ~ '''premium_bundle'''
     and ns.nspname not like 'pg\_temp\_%';
  if v is distinct from c_bundle_writers then
    raise exception '463: what gives a Premium Bundle''s vouchers is not as read on 24 Oct 2026 (%); check each, then re-test', v; end if;

  -- The added functions: each absent (added) or this version (left alone).
  for i in 1 .. cardinality(c_new) loop
    if to_regprocedure('public.' || c_new[i]) is not null
       and md5(pg_get_functiondef(to_regprocedure('public.' || c_new[i]))) <> c_new_after[i] then
      raise exception '463: public.% is there but not this version (md5 %)', c_new[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_new[i]))); end if;
  end loop;

  -- Each changed function: its BEFORE (changed; each anchor found once; the
  -- text built has its AFTER md5) or its AFTER (left alone).
  v_built := array[c_def_own, null, null, null, null, null, null, null];
  for i in 1 .. cardinality(c_sigs) loop
    if to_regprocedure('public.' || c_sigs[i]) is null then raise exception '463: public.% is missing', c_sigs[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sigs[i]));
    if md5(d) = c_after[i] then
      raise notice '463: public.% is already this version; left alone', c_sigs[i]; v_left := v_left + 1;
      continue;
    end if;
    if md5(d) <> c_before[i] then
      raise exception '463: public.% is not the version this was tested against (md5 %). 463 goes in after 462; re-read it and re-test before applying.', c_sigs[i], md5(d); end if;
    if i >= 2 then
      for k in 1 .. cardinality(c_fn) loop
        continue when c_fn[k] <> i;
        n := (length(d) - length(replace(d, c_anchor[k], ''))) / length(c_anchor[k]);
        if n <> 1 then
          raise exception '463: anchor % of public.% is found % times, not once (md5 %)', k, c_sigs[i], n, md5(d); end if;
        d := replace(d, c_anchor[k], c_patch[k]);
      end loop;
      if md5(d) <> c_after[i] then
        raise exception '463: the text built for public.% is not the tested one (md5 %)', c_sigs[i], md5(d); end if;
      v_built[i] := d;
    end if;
    v_defs := v_defs || v_built[i];
  end loop;
  -- All eight, or none: a part-way state is not one this was tested in.
  if v_left not in (0, cardinality(c_sigs)) then
    raise exception '463: only % of the eight functions are already this version; not a state this was tested in', v_left; end if;
  v_first := v_left = 0;
  if not v_first and (to_regprocedure('public.' || c_new[1]) is null or to_regprocedure('public.' || c_new[2]) is null) then
    raise exception '463: the functions are this version but public.% or public.% is missing; not a state this was tested in', c_new[1], c_new[2]; end if;

  -- ── On the first run: nothing already in a state 463 reads differently
  -- and that needs a decision first (the header's read-only query lists it;
  -- a repair is a separate data fix, with the Owner's yes).
  if v_first then
    -- (1) No credit an Owner moved to the same customer at another store,
    -- from the invoice's own, held by someone other than whoever holds the
    -- benefits now by 463's rule (a 'transfer' change made since: it left
    -- this credit with the old customer, and from 463 the next refund or
    -- reopening of it would move it all to the new one at once).
    with recursive mv(benefit_id, at_id, other, n) as (
      select t.replacement_benefit_id, t.source_benefit_id,
             (t.before_snapshot->>'customer_id') is distinct from coalesce(t.after_snapshot->>'customer_id', t.customer_id::text), 0
        from public.invoice_benefit_transfers t where t.replacement_benefit_id is not null
      union all
      select mv.benefit_id, t.source_benefit_id,
             (t.before_snapshot->>'customer_id') is distinct from coalesce(t.after_snapshot->>'customer_id', t.customer_id::text), mv.n + 1
        from mv join public.invoice_benefit_transfers t on t.replacement_benefit_id = mv.at_id
       where not mv.other and mv.n < 64)
    select count(distinct b.invoice_id), string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into n, v
      from public.invoice_benefit_values b
      join public.customer_credit_lots l on l.id = b.lot_id
      join public.invoices iv on iv.id = b.invoice_id
     where b.id in (select mv.benefit_id from mv group by mv.benefit_id having not bool_or(mv.other))
       and l.remaining_amount > 0 and l.status = 'active'
       and l.customer_id is distinct from public.invoice_credit_live_holder(b.invoice_id, l.customer_id, l.created_at);
    if n > 0 then
      raise exception '463: % invoice(s) have credit an Owner moved to the same customer at another store, held by someone other than whoever holds their benefits now (%): a customer change with "transfer" left it. Decide where it belongs (a data fix), then apply. Nothing was changed.', n, v; end if;
    -- Not refused (the read-only query lists them, 3 and 5 to 8): what only a
    -- later step reads differently, with nothing anyone holds changed by the
    -- install: a 'transfer' change of partly spent credit (refused from
    -- 463), a Cancel and Reopen of vouchers the old customer still holds, a
    -- reopening of an invoice cancelled or refunded after a change, a
    -- waiting reopening's payment. Those steps then give what they give
    -- back to whoever holds the benefits (decisions 2 and 3).
  end if;

  -- Who may call each, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  for i in 1 .. cardinality(c_sigs) loop
    if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i]))
       is distinct from (select array_agg(x::text order by x::text) from unnest(c_acl[i]::aclitem[]) x) then
      raise exception '463: who may call public.% is not as read on 24 Oct 2026 (%)', c_sigs[i],
        (select proacl::text from pg_proc where oid = to_regprocedure('public.' || c_sigs[i])); end if;
    v_acl := v_acl || (select coalesce(string_agg(x::text, ',' order by x::text), '')
                         from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i]));
  end loop;

  -- ── Change ──────────────────────────────────────────────────────────────
  -- The helpers first: the list functions (SQL) read them.
  for i in 1 .. cardinality(c_new) loop
    if to_regprocedure('public.' || c_new[i]) is null then
      execute case i when 1 then c_def_moved else c_def_spent end;
      execute format('revoke all on function public.%s from public, anon, authenticated', c_new[i]);
      execute format('grant execute on function public.%s to service_role', c_new[i]);
    end if;
  end loop;
  for k in 1 .. coalesce(cardinality(v_defs), 0) loop
    execute v_defs[k];
  end loop;

  -- ── Afterwards: installed exactly as tested, grants as before ───────────
  for i in 1 .. cardinality(c_sigs) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[i]))) <> c_after[i] then
      raise exception '463: public.% is not at its AFTER md5 (%)', c_sigs[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[i]))); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[i])) is distinct from v_acl[i] then
      raise exception '463: the grants of public.% changed', c_sigs[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_new) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_new[i]))) <> c_new_after[i]
       or (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new[i]))
          is distinct from (select array_agg(x::text order by x::text) from unnest(c_new_acl::aclitem[]) x)
       or has_function_privilege('anon', 'public.' || c_new[i], 'execute')
       or has_function_privilege('authenticated', 'public.' || c_new[i], 'execute') then
      raise exception '463: public.% is not as tested, or not the server''s alone', c_new[i]; end if;
  end loop;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("463 check", @example.invalid, fictional ACMA
  -- phones no customer uses); it ends by raising P0463, which undoes all it
  -- wrote. 462's trigger runs at commit; here it is run at each step's end
  -- (SET CONSTRAINTS ... IMMEDIATE), as a commit would.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from unnest(array['+61491570961', '+61491570962', '+61491570963', '+61491570964', '+61491570965',
                                                 '+61491570966', '+61491570967', '+61491570968', '+61491570969', '+61491570970',
                                                 '+61491570971', '+61491570972']) p
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p limit 8);
    if coalesce(cardinality(t_phones), 0) < 8 then raise exception '463: the self-test found no eight unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '463-check-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '463 check', '463-check-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('463 check ' || t_sfx, '463-' || t_sfx, 'SG') returning id into t_store;
    insert into public.stores (name, code, country_code) values ('463 check other ' || t_sfx, '463o-' || t_sfx, 'SG') returning id into t_store2;
    insert into public.payment_methods (name, is_active) values ('463 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, allow_product, allow_therapy, grants_reward)
    values ('463 check ' || t_sfx, 100, 100, false, true, true, false) returning id into t_pk;
    insert into public.credit_package_stores (package_id, store_id) values (t_pk, t_store), (t_pk, t_store2);
    insert into public.vouchers (name, code, voucher_kind, qty_type, selling_price, is_active)
    values ('463 check ' || t_sfx, '463-' || t_sfx, 'normal', 'unlimited', 30, true) returning id into t_v;
    insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store)
    values (t_v, t_store, 30, true), (t_v, t_store2, 30, true);
    insert into public.premium_bundles (name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('463 check ' || t_sfx, 140, 100, 40, 2, true) returning id into t_pb;
    insert into public.premium_bundle_stores (bundle_id, store_id) values (t_pb, t_store), (t_pb, t_store2);
    insert into public.premium_bundle_vouchers (bundle_id, voucher_id) values (t_pb, t_v);
    insert into public.customers (full_name, phone) values ('463 Check Buyer ' || t_sfx, t_phones[1]) returning id into t_a;
    insert into public.customers (full_name, phone) values ('463 Check Second ' || t_sfx, t_phones[2]) returning id into t_b;
    insert into public.customers (full_name, phone) values ('463 Check Third ' || t_sfx, t_phones[3]) returning id into t_c;
    insert into public.customers (full_name, phone) values ('463 Check Fourth ' || t_sfx, t_phones[4]) returning id into t_d;
    insert into public.customers (full_name, phone) values ('463 Check Fifth ' || t_sfx, t_phones[5]) returning id into t_e;
    insert into public.customers (full_name, phone) values ('463 Check Sixth ' || t_sfx, t_phones[6]) returning id into t_g;
    insert into public.customers (full_name, phone) values ('463 Check Removed ' || t_sfx, t_phones[7]) returning id into t_h;

    -- (a) Decision 2, credit: a package, the S$100 moved by an Owner to the
    -- same customer at the other store, then the invoice's customer changed
    -- with the benefits (the change's step): the second customer holds the
    -- S$100, at the other store, on a lot replacing the moved one that the
    -- moved benefit row names; it still traces to the package (Credit
    -- Package Paid); the buyer holds nothing; nothing asked, due S$100.
    t_inv := public.create_invoice(t_store, t_a, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
    select b.id, b.lot_id into t_ben, t_lot from public.invoice_benefit_values b where b.invoice_id = t_inv;
    perform public.transfer_invoice_unused_benefit(t_ben, t_a, t_store2, '463 check', gen_random_uuid());
    select t.replacement_benefit_id into t_ben2 from public.invoice_benefit_transfers t where t.source_benefit_id = t_ben;
    if public.invoice_benefit_moved_to_other(t_ben2) or not exists (select 1 from public.invoice_transferable_benefits(t_inv) x
                                                                     where x.kind = 'credit' and x.movable and x.units = 100) then
      raise exception '463: (a) the store-moved credit is not listed as moving with the change (%)',
        (select jsonb_agg(to_jsonb(x)) from public.invoice_transferable_benefits(t_inv) x); end if;
    perform public.move_invoice_benefits_to_customer(t_inv, t_b, t_store, '463 check');
    set constraints public.credit_given_back_follows immediate;
    set constraints public.credit_given_back_follows deferred;
    if (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_a) <> 0
       or not exists (select 1 from public.customer_credit_lots n2
                        join public.invoice_benefit_values b on b.lot_id = n2.id and b.id = t_ben2
                        join public.customer_credit_lots o on o.id = n2.reassigned_from_lot_id
                       where n2.customer_id = t_b and n2.remaining_amount = 100 and n2.store_id = t_store2
                         and o.source_type = 'invoice_benefit_transfer' and o.customer_id = t_a
                         and (n2.source_type, n2.source_record_id, n2.category, n2.usage_restrictions)
                             is not distinct from (o.source_type, o.source_record_id, o.category, o.usage_restrictions))
       or (select public.invoice_credit_transfer_origin(b.lot_id) from public.invoice_benefit_values b where b.id = t_ben2) is distinct from t_lot
       or (select public.credit_lot_policy_for(b.lot_id) from public.invoice_benefit_values b where b.id = t_ben2) <> 'package_paid'
       or exists (select 1 from jsonb_array_elements(coalesce(public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->'overrides_required', '[]'::jsonb)) o)
       or (public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->>'refund_due')::numeric <> 100 then
      raise exception '463: (a) the store-moved credit did not follow the change with its records (%)',
        (select jsonb_agg(jsonb_build_object('customer', l.customer_id, 'remaining', l.remaining_amount, 'store', l.store_id))
           from public.customer_credit_lots l where l.customer_id in (t_a, t_b)); end if;

    -- (b) Decision 2, vouchers: a voucher line of two, the two moved by an
    -- Owner to the same customer at the other store, the customer changed:
    -- the fourth customer holds the two at the other store (no stock moves);
    -- cancelled and reopened: given again to the fourth, at that store.
    t_inv := public.create_invoice(t_store, t_c, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', t_v, 'quantity', 2)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)), gen_random_uuid());
    select b.id into t_ben from public.invoice_benefit_values b where b.invoice_id = t_inv and b.reward_voucher_id is not null;
    perform public.transfer_invoice_unused_benefit(t_ben, t_c, t_store2, '463 check', gen_random_uuid());
    perform public.move_invoice_benefits_to_customer(t_inv, t_d, t_store, '463 check');
    if (select coalesce(sum(quantity), 0) from public.customer_reward_vouchers where customer_id = t_d and status = 'held' and store_id = t_store2) <> 2
       or exists (select 1 from public.customer_reward_vouchers where customer_id = t_c and status = 'held') then
      raise exception '463: (b) the store-moved vouchers did not follow the change at their store'; end if;
    perform public.cancel_invoice_recorded(t_inv, '463 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '463 check', gen_random_uuid());
    if (select coalesce(sum(quantity), 0) from public.customer_reward_vouchers where customer_id = t_d and status = 'held' and store_id = t_store2) <> 2
       or exists (select 1 from public.customer_reward_vouchers where customer_id = t_c and status = 'held') then
      raise exception '463: (b) the reopening did not give the vouchers again to the fourth customer'; end if;

    -- (c) Decision 3: a Premium Bundle (S$100 Paid, S$40 Bonus, two
    -- vouchers), the customer changed: the sixth customer holds the S$140
    -- and the two vouchers.
    t_inv := public.create_invoice(t_store, t_e, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', t_pb, 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', t_v, 'quantity', 2)))),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 140)), gen_random_uuid());
    if (select coalesce(sum(quantity), 0) from public.customer_reward_vouchers where customer_id = t_e and status = 'held') <> 2 then
      raise exception '463: (c) the bundle did not give its two vouchers'; end if;
    perform public.move_invoice_benefits_to_customer(t_inv, t_g, t_store, '463 check');
    if (select coalesce(sum(quantity), 0) from public.customer_reward_vouchers where customer_id = t_g and status = 'held') <> 2
       or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_g) <> 140
       or exists (select 1 from public.customer_reward_vouchers where customer_id = t_e and status = 'held')
       or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_e) <> 0 then
      raise exception '463: (c) the bundle''s vouchers did not follow the change with its credit'; end if;

    -- (g) A voucher given again goes to whoever holds the benefits, read
    -- from when the first voucher of its chain was given (the critics of 24
    -- Oct 2026): the bundle cancelled and reopened, its vouchers given again
    -- to the sixth customer; then left as a reopening's payment before 463
    -- left them after a change (a stand-in): back with the fifth customer,
    -- dated after the change. Cancelled and reopened again: given again to
    -- the sixth, who holds the benefits (before, to the fifth, at every
    -- reopening).
    perform public.cancel_invoice_recorded(t_inv, '463 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '463 check', gen_random_uuid());
    set constraints public.credit_given_back_follows immediate;
    set constraints public.credit_given_back_follows deferred;
    if (select coalesce(sum(quantity), 0) from public.customer_reward_vouchers
         where customer_id = t_g and status = 'held' and source_type = 'invoice_reopen') <> 2 then
      raise exception '463: (g) the reopening did not give the bundle''s vouchers again to the sixth customer'; end if;
    update public.customer_reward_vouchers set customer_id = t_e, issued_at = now() + interval '1 hour'
     where customer_id = t_g and status = 'held' and source_type = 'invoice_reopen'
       and id in (select o.voucher_id from public.invoice_own_voucher_ids(t_inv) o);
    perform public.cancel_invoice_recorded(t_inv, '463 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '463 check', gen_random_uuid());
    set constraints public.credit_given_back_follows immediate;
    set constraints public.credit_given_back_follows deferred;
    if (select coalesce(sum(quantity), 0) from public.customer_reward_vouchers where customer_id = t_g and status = 'held') <> 2
       or exists (select 1 from public.customer_reward_vouchers where customer_id = t_e and status = 'held')
       or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_g) <> 140 then
      raise exception '463: (g) a voucher given again to the old customer after the change went back to that customer'; end if;

    -- (d) W1: a second bundle for the fifth customer, cancelled, its refund
    -- recorded, reopened (it waits): the summary of a change to the second
    -- customer lists what the payment will give back (S$40 Bonus, S$100
    -- Paid, the two vouchers); with 'keep' it does not. Changed and paid:
    -- the second customer holds all of it.
    t_inv := public.create_invoice(t_store, t_e, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', t_pb, 'quantity', 1,
        'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', t_v, 'quantity', 2)))),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 140)), gen_random_uuid());
    perform public.cancel_invoice_recorded(t_inv, '463 check', gen_random_uuid());
    -- The Finance panel's refund of the line: every unused benefit it held.
    t_ans := public.invoice_refund_options_before_sessions(t_inv);
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', (select it.id from public.invoice_items it where it.invoice_id = t_inv), 'amount', 140,
        'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', b->>'id', 'amount', (b->>'max_refund')::numeric))
                       from jsonb_array_elements(t_ans->'benefits') b where (b->>'max_refund')::numeric > 0))),
      jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt'
                                                           order by p.created_at limit 1), 'amount', 140)), '[]'::jsonb, '463 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '463 check', gen_random_uuid());
    if not exists (select 1 from public.invoice_reopen_vouchers q where q.invoice_id = t_inv and q.applied_at is null)
       or not exists (select 1 from public.invoice_reopen_benefits q where q.invoice_id = t_inv and q.applied_at is null) then
      raise exception '463: (d) the reopening does not wait for its payment'; end if;
    t_ans := public.preview_invoice_correction(t_inv, jsonb_build_object('customer_id', t_b, 'benefit_action', 'transfer'));
    if not (t_ans->'effects' @> jsonb_build_array(jsonb_build_object('area', 'benefits', 'change', 'transferring',
              'items', jsonb_build_array(jsonb_build_object('kind', 'credit', 'what', 'Bonus credit 40.00'),
                                         jsonb_build_object('kind', 'credit', 'what', 'Paid credit 100.00'),
                                         jsonb_build_object('kind', 'voucher', 'what', '463 check ' || t_sfx || ' × 2'))))) then
      raise exception '463: (d) the summary does not list what the waiting reopening gives the new customer (%)', t_ans->'effects'; end if;
    t_ans := public.preview_invoice_correction(t_inv, jsonb_build_object('customer_id', t_b, 'benefit_action', 'keep'));
    if t_ans->'effects' @> '[{"area": "benefits", "change": "transferring"}]'::jsonb then
      raise exception '463: (d) with keep, the summary still lists benefits moving (%)', t_ans->'effects'; end if;
    perform public.move_invoice_benefits_to_customer(t_inv, t_b, t_store, '463 check');
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 140)), gen_random_uuid());
    set constraints public.credit_given_back_follows immediate;
    set constraints public.credit_given_back_follows deferred;
    if (select coalesce(sum(quantity), 0) from public.customer_reward_vouchers where customer_id = t_b and status = 'held') <> 2
       or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots l
            where l.customer_id = t_b and l.id in (select x.lot_id from public.invoice_credit_lot_ids(t_inv) x)) <> 140
       or exists (select 1 from public.customer_reward_vouchers where customer_id = t_e and status = 'held')
       or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_e) <> 0 then
      raise exception '463: (d) the reopening''s payment did not give the bundle''s credit and vouchers to the new customer'; end if;

    -- (e) K6s: no invoice for a removed customer record.
    perform public.delete_customer(t_h, (select full_name from public.customers where id = t_h), '463 check');
    begin
      perform public.create_invoice_with_details(t_store, t_h,
        jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', t_v, 'quantity', 1)),
        jsonb_build_object('business_date', public.sg_today()::text));
      t_msg := 'accepted';
    exception when others then t_msg := sqlerrm;
    end;
    if t_msg is distinct from 'This customer''s record was merged into another or deleted. Choose the customer again.'
       or exists (select 1 from public.invoices where customer_id = t_h) then
      raise exception '463: (e) an invoice for a removed customer record was not refused (%)', t_msg; end if;

    -- (f) 461's rule kept for a store correction (the critics of 24 Oct
    -- 2026): a package for the eighth customer, S$20 of it spent (a stand-in
    -- for a session paid from it: a 'use' row), the S$80 left moved by an
    -- Owner to that customer at the other store: the change's list shows the
    -- moved credit as blocking, "Partly spent", and the change is refused,
    -- moving nothing, as without the Move.
    insert into public.customers (full_name, phone) values ('463 Check Eighth ' || t_sfx, t_phones[8]) returning id into t_k;
    t_inv := public.create_invoice(t_store, t_k, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)), gen_random_uuid());
    select b.id, b.lot_id into t_ben, t_lot from public.invoice_benefit_values b where b.invoice_id = t_inv;
    insert into public.customer_credit_ledger (wallet_id, customer_id, entry_type, category, amount, lot_id, source_type, source_record_id, store_id, note, created_by)
    select l.wallet_id, l.customer_id, 'use', l.category, 20, l.id, 'special_sale', gen_random_uuid(), l.store_id, '463 check', t_owner
      from public.customer_credit_lots l where l.id = t_lot;
    update public.customer_credit_lots set remaining_amount = remaining_amount - 20, updated_at = now() where id = t_lot;
    perform public.transfer_invoice_unused_benefit(t_ben, t_k, t_store2, '463 check', gen_random_uuid());
    if not exists (select 1 from public.invoice_transferable_benefits(t_inv) x
                    where x.kind = 'credit' and x.units = 80 and x.blocking and not x.movable and x.blocked_reason = 'Partly spent') then
      raise exception '463: (f) credit moved to the same customer from a partly spent package is not listed as blocking (%)',
        (select jsonb_agg(to_jsonb(x)) from public.invoice_transferable_benefits(t_inv) x); end if;
    begin
      perform public.move_invoice_benefits_to_customer(t_inv, t_b, t_store, '463 check');
      t_msg := 'accepted';
    exception when others then t_msg := sqlerrm;
    end;
    if t_msg not like 'These benefits have already been used and cannot move with the invoice: Paid credit 80.00 (Partly spent).%'
       or (select coalesce(sum(remaining_amount), 0) from public.customer_credit_lots where customer_id = t_k and store_id = t_store2) <> 80 then
      raise exception '463: (f) the change of a partly spent package moved to another store was not refused (%)', t_msg; end if;
    raise exception using errcode = 'P0463', message = '463: self-test done, undone';
  exception when sqlstate 'P0463' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
