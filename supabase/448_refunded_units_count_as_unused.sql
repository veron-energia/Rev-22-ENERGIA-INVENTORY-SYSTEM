-- 448_refunded_units_count_as_unused.sql
--
-- A VOUCHER UNIT OR CREDIT THAT A LINE REFUND ALREADY PAID BACK IS NOT "USED":
-- REFUND IN FULL AND CANCEL ASK NO FALSE OVERRIDE, AND WHAT A CANCELLED
-- INVOICE STILL OWES BACK CAN BE RECORDED (the Owner, 22 Oct 2026: "build the
-- warning fix"; 438's NOT COVERED 2, 446's NOT COVERED 1)
--
-- WHO FOUND IT
--
--   The reviews of 438 (21 Oct 2026; 438's header, NOT COVERED 2), checked as
--   KNOWN by 438's suite (scripts/invoices/tests/reopen-recancel-438.sql,
--   case 9 (2)) and again by 446's (446's NOT COVERED 1, the same for credit;
--   scripts/invoices/tests/reopen-refund-waiting-446.sql, case 8).
--   Reproduced for this file on 22 Oct 2026 on a copy of production as it
--   was before 450 went in (9d2e2fdd, 1370 functions: 447 in; the suite
--   reproduces it the same with 450 in), with made-up records, through the
--   app's own calls only: the invoice form and the Pay dialog, the guided
--   "Refund some items", Refund in full and Cancel, Cancel, the Finance
--   panel's "Record refund paid" and its refund by line, Reopen, Record
--   Payment, Move, the invoice form's customer change and a customer merge.
--
-- WHAT WAS WRONG
--
--   409's cancelled_invoice_used_value(uuid) says what the customer of a
--   cancelled invoice already had from it, and invoice_action_plan asks an
--   Owner or Manager override for each, by one test per benefit row of the
--   invoice (invoice_benefit_values): what is still on the row (its voucher
--   while held, or what its lot holds, plus what a cancellation took back:
--   cancelled_unused_value), plus what 438 counts elsewhere (units a
--   reopening or a payment gave again, units or credit an Owner moved), less
--   than what the row granted reads as "vouchers redeemed" or "credit
--   spent". A line refund (refund_invoice_recorded: the guided "Refund some
--   items", Refund in full, the Finance panel's refund by line) takes the
--   units or credit it pays back off the row (the voucher revoked or
--   lowered, the lot drawn down, cancelled_unused_value lowered) and records
--   them only in invoice_refunds.outcome (and, for credit, in its ledger
--   rows). So everything a line refund paid back read as used. On the copy:
--   * a line of two S$30 vouchers, paid, one unit refunded: Refund in full
--     and Cancel asked voucher_redeemed, and the guided Cancel also asked
--     "State how much is owed back"; cancelled directly, it read "vouchers
--     redeemed", "Record refund paid" for the S$30 still held was refused
--     ("Part of what INV-... sold has been used (vouchers redeemed), and no
--     amount owed back was stated when it was cancelled ... Nothing was
--     recorded."), and the Finance panel said so instead of offering it;
--   * two lines of one, line A refunded: Cancel asked voucher_redeemed, and
--     cancelled directly the same refusal;
--   * credit: two S$100 Credit Packages with a S$10 Bonus, line A refunded:
--     Cancel asked credit_used for its Paid and its Bonus credit and the
--     amount owed; cancelled directly, "credit spent". S$40 of one package
--     refunded: Refund in full and Cancel asked credit_used;
--   * the same for Premium Bundles (their credit and their vouchers), a
--     part-paid package's released credit once settled, a line refunded and
--     then the invoice cancelled and reopened (the refunded part waiting to
--     be given back), a line refunded while a reopening waited (446), and
--     after a Move, a customer change, a merge or an FOC taken off.
--   Nothing was given or kept wrongly: the money and the benefits were
--   right; the overrides and the refusal were false.
--   Production: not read here (no access). The query under DEPLOY ORDER
--   lists, read only, every invoice whose answer this changes.
--
-- THE OWNER'S ANSWER (22 Oct 2026)
--
--   "Build the warning fix": units and credit a line refund already paid
--   back count as not used, so no false override is asked and the refund
--   due can be recorded. Everything else behaves as today: real redemption
--   and spending still ask, amounts owed never count again what was already
--   refunded, therapy sessions and stock are unchanged.
--
-- THE RULE
--
--   "Used" stays what 409 says: vouchers redeemed, credit spent (and
--   sessions delivered, therapy started, released credit spent, unchanged).
--   A unit or credit a line refund paid back was not used. A reopening gives
--   refunded units and credit back (reopen_invoice): from then on they are
--   the reopening's, a replacement voucher (438 counts it) or credit back on
--   the lot, and the refund before the reopening no longer counts (the
--   reopening charges the line again). A redemption or a spend on the same
--   row as a refund still reads as used, once per row as before, and what
--   the refund paid back is not offered again (the refund options and the
--   plans' money are as before, to the cent).
--
-- WHAT THIS DOES (one function added; cancelled_invoice_used_value patched at
-- two anchors, its voucher test and its credit test, and invoice_action_plan
-- at one; no table, row or other function changes; grants kept)
--
--   * invoice_benefit_unused_elsewhere(uuid) (new; the server's alone, like
--     cancelled_invoice_used_value): what a benefit row granted that was not
--     used although it is no longer on the row, in the row's own terms. It
--     holds 438's two terms, moved here unchanged (units a reopening or a
--     payment gave again; units or credit an Owner moved), and adds:
--     - vouchers: the units refunded by line since the invoice was last
--       reopened, counted as the next reopening counts them to give back
--       (invoice_voucher_reopen_candidates, less what a cancellation took
--       back: whole units at the row's paid value, as the refund took them);
--       and the units a reopening queued to give back after an earlier line
--       refund that still wait (invoice_reopen_vouchers not applied, beyond
--       what a cancellation took back; a refund made while they wait takes
--       its units off both, 446, and is counted with the first);
--     - credit: read from the ledger rows a reopening puts back
--       (reopen_invoice, apply_reopened_invoice_benefits): the invoice's own
--       cancellation rows ('invoice_cancel_benefit') and its refunds' rows
--       ('invoice_benefit_refund') on the row's lot, or a lot it replaced (a
--       merge, 445; a customer change, 447), not queued yet or queued and
--       still waiting, beyond what cancelled_unused_value holds (a
--       cancellation's credit is in both). That is exactly what the refunds
--       took, to the cent, with no conversion from the money refunded. Where
--       a row has no such rows (a cancellation or a refund recorded before
--       these ledger rows were written), it adds nothing: as before.
--   * cancelled_invoice_used_value(uuid): its voucher test and its credit
--     test call the helper in place of 438's two expressions (one comment
--     each).
--   * invoice_action_plan(uuid,text,jsonb): its per-benefit test calls the
--     helper in place of 438's expression (one comment). So Refund in full
--     and Cancel ask no voucher_redeemed or credit_used for what a refund
--     paid back; with nothing else used, Cancel asks no amount owed (417's
--     refund_owed), the approval states none (resolve_invoice_action_v2 reads
--     the plan and cancelled_invoice_used_value), and once cancelled "Record
--     refund paid" records what the invoice still holds, up to the refund
--     due (refund_invoice_recorded reads cancelled_invoice_used_value).
--   Why counted from the queues and the ledger, not converted from the money
--   refunded: a refund of all of a row's credit takes what was left exactly,
--   which no conversion from the amount gets back to the cent; the units
--   are whole, and the queues are what a reopening gives back.
--
-- NOT CHANGED
--
--   * The money: invoice_refund_options (each row's remaining_value and
--     max_refund), the plans' lines, amounts, benefits, sources and refund
--     due (the suite compares them whole before and after), refund_
--     invoice_recorded and its caps (the refund due, cancel_refund_owed),
--     invoice_financial_position. A unit or credit refunded is never offered
--     again.
--   * cancel_invoice_recorded, reopen_invoice, apply_reopened_invoice_
--     vouchers and _benefits, trg_issue_sold_vouchers_on_paid (416),
--     transfer_invoice_unused_benefit (445), move_invoice_benefits_to_
--     customer (447), merge_customer_records (445), invoice_voucher_reopen_
--     candidates: what they record is what this counts; pinned below.
--   * Sessions delivered, therapy started, released credit spent before
--     settlement: their tests are unchanged.
--   * The pages: the Invoices page, the Finance panel and the guided Refund /
--     Cancel read the plan's codes, refund_owed and the financial position
--     (InvoicesPage.tsx, InvoiceFinancePanel.tsx, InvoiceGuidedAction.tsx,
--     src/lib/invoices/business.ts); none says that a refunded unit counts
--     as used. No page change.
--
-- NOT COVERED (found or noted while building this; each there before it; the
-- suite checks 1 to 3 as they are and prints them as KNOWN, and 5 as its
-- case 4; 438's suite checks 6)
--
--   1. (446's, found here; on a copy with 417's refund_invoice_recorded
--      rebuilt, there before 446 it was right) One unit of a line of two
--      refunded, the invoice cancelled, reopened (both units wait), cancelled
--      again before it was settled, the other unit refunded by line while
--      waiting (446 takes it off the queue), reopened again: 417's "only what
--      is more" finds one unit still waiting (the first refund's) and queues
--      nothing for the second, so one unit waits for the S$60 the line now
--      charges again; settled, the customer holds 1 voucher for S$60 (before
--      446: 2). 448 reads the unit never given as redeemed (the plan asks
--      voucher_redeemed). Only a line of two or more, refunded on both sides
--      of a reopening that was cancelled again unsettled. The fix belongs in
--      reopen_invoice (count waiting units by where they came from) or in
--      446's queue step: the Owner's decision, a migration of its own.
--   2. S$40 of a package refunded, the buyer then merged into another record
--      (445 reissues the lot), cancelled, reopened and settled: the
--      reopening reinstates the S$40 on the lot the refund came from, the
--      merged-away record's, so the kept record's lot holds S$60 and it reads
--      credit_used (as before 448). The same family as 446's NOT COVERED 5
--      (a customer change): the reopening, or the payment that settles it,
--      would follow the lot to its current holder. Before the reopening it
--      reads right (448 follows the lot back through the merge).
--   3. A partly refunded credit lot still blocks a customer change as "Partly
--      spent" (invoice_transferable_benefits, unchanged: its words and its
--      rule), and a wholly refunded one is listed as "Fully spent; it stays
--      with the original customer". Not the override this file is about.
--   4. A cancellation or refund of credit recorded before 'invoice_cancel_
--      benefit' / 'invoice_benefit_refund' ledger rows were written (older
--      engines, if any such invoice exists) is read as before: what it took
--      can't be told from what was spent. The query below would list it only
--      if it changes; it does not.
--   5. A guided request raised before 448 on an invoice whose plan changes
--      carries the old plan; approving it asks to confirm the revised one
--      ("What this request would do has changed since it was submitted ...":
--      the plan hash differs), as after 438. Other requests are unchanged.
--   6. 438's NOT COVERED 1 (the FOC taken off with the quantity lowered or the
--      voucher swapped) is not a refund and still reads as redeemed.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the helper's text is the tested one (its AFTER md5); the helper is
--     absent (created) or this version (left alone);
--   * each patched function is its BEFORE (production, 22 Oct 2026: 438's
--     AFTERs, 436 in; patched, each anchor found once, the text built has the
--     tested AFTER md5) or its AFTER (left alone), so a second run changes
--     nothing; no other function takes the three names;
--   * the functions it relies on are as read on production (below); the
--     columns it reads are there with these types;
--   * afterwards: the three md5s are the AFTER ones; the two patched keep
--     their grants (compared as sets: production lists them in another
--     order than a local copy), cancelled_invoice_used_value the service
--     role's alone, invoice_action_plan signed-in staff's and the service
--     role's; the helper is the service role's alone (revoked from public,
--     anon and signed-in staff; granted to the service role);
--   * then a self-test, in a block that is always undone (it ends by raising
--     P0448, so it leaves no row): a made-up Owner, store, buyer (a fictional
--     ACMA phone no customer has), S$30 voucher and S$100 Credit Package
--     (S$10 Bonus). (a) A line of two vouchers, paid, one unit refunded by
--     line: Refund in full and Cancel ask nothing, Cancel no amount owed and
--     a refund due of S$30; cancelled, nothing used, "Record refund paid"
--     records the S$30. (b) The same with the other unit redeemed:
--     voucher_redeemed asked once, the amount owed asked, refund due S$0;
--     cancelled, "vouchers redeemed", the S$30 refused. (c) Two packages,
--     line A refunded: Cancel asks nothing, refund due S$100; cancelled,
--     nothing used, the S$100 recorded by line. (d) The same with S$10 of
--     line B's Paid credit spent: credit_used asked once.
--   It reads only, apart from the three functions and the self-test's rows
--   (undone). Its credit ledger rows draw entry numbers (a sequence, which an
--   undone transaction does not give back: a gap, which nothing counts), as
--   443's to 447's self-tests do. Locks: the three functions' catalogue
--   rows, to the end of the apply. A refund or plan running at that moment
--   finishes on the text it started with.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (... 445, 449, 446, 447, 450: 46683a93, 1370 functions,
--   head 20261022064218) -> 448. No page, Edge Function or setting changes.
--   450 (applied 22 Oct 2026 06:42 UTC, file md5 a479fb92) changed
--   event_vip_person_problems and event_registration_close only and pins
--   none of the functions this file changes or relies on; this file pins
--   neither of its two. On a base without 450 (447's head, 9d2e2fdd) it
--   applies the same (fingerprints below).
--   1. Before it, read only, to know which invoices change (an invoice is
--      listed when one of its benefit rows reads redeemed or spent today and
--      not after 448; rows_still_used > 0: something else on it is really
--      used; owed_stated: an amount owed was stated when it was cancelled,
--      which stays; pending_requests: guided requests that will ask to
--      confirm their revised plan, NOT COVERED 5):
--        with recursive b as (
--          select bv.id, bv.invoice_id, bv.lot_id, bv.reward_voucher_id, bv.granted_value, bv.cancelled_unused_value,
--                 case when bv.reward_voucher_id is not null
--                      then coalesce((select case when v.status = 'held' then v.quantity else 0 end
--                                       from public.customer_reward_vouchers v where v.id = bv.reward_voucher_id), 0)
--                      else coalesce((select l.remaining_amount from public.customer_credit_lots l where l.id = bv.lot_id), 0) end
--                 + bv.cancelled_unused_value
--                 + coalesce((select sum(t.transferred_value) from public.invoice_benefit_transfers t
--                              where t.source_benefit_id = bv.id and t.replacement_benefit_id is not null), 0)
--                 + coalesce((select sum(q.quantity) from public.invoice_reopen_vouchers q
--                              where q.benefit_id = bv.id and q.applied_at is not null), 0) as unused_now
--            from public.invoice_benefit_values bv
--        ), chain(benefit_id, lot_id, n) as (
--          select b.id, b.lot_id, 0 from b where b.lot_id is not null
--          union all
--          select c.benefit_id, l.reassigned_from_lot_id, c.n + 1
--            from chain c join public.customer_credit_lots l on l.id = c.lot_id
--           where l.reassigned_from_lot_id is not null and c.n < 12
--        ), x as (
--          select b.*, case
--            when b.reward_voucher_id is not null then
--              greatest(coalesce((select c.quantity from public.invoice_voucher_reopen_candidates(b.invoice_id) c
--                                  where c.benefit_id = b.id), 0) - b.cancelled_unused_value, 0)
--            + greatest(coalesce((select sum(q.quantity) from public.invoice_reopen_vouchers q
--                                  where q.benefit_id = b.id and q.applied_at is null), 0) - b.cancelled_unused_value, 0)
--            when b.lot_id is not null then
--              greatest(coalesce((select sum(e.amount) from public.customer_credit_ledger e
--                                  where e.lot_id in (select c.lot_id from chain c where c.benefit_id = b.id)
--                                    and (e.source_type = 'invoice_cancel_benefit' and e.source_record_id = b.invoice_id
--                                         or e.source_type = 'invoice_benefit_refund'
--                                            and exists (select 1 from public.invoice_refunds r
--                                                         where r.invoice_id = b.invoice_id and r.request_id = e.source_record_id))
--                                    and not exists (select 1 from public.invoice_reopen_benefits q where q.source_ledger_id = e.id)), 0)
--                     + coalesce((select sum(q.amount) from public.invoice_reopen_benefits q
--                                   join public.customer_credit_ledger e on e.id = q.source_ledger_id
--                                  where q.invoice_id = b.invoice_id and q.applied_at is null
--                                    and e.lot_id in (select c.lot_id from chain c where c.benefit_id = b.id)), 0)
--                     - b.cancelled_unused_value, 0)
--            else 0 end as refunded
--            from b
--        )
--        select i.invoice_no, i.status::text as status,
--               count(*) filter (where x.unused_now < x.granted_value and x.unused_now + x.refunded >= x.granted_value) as rows_no_longer_used,
--               count(*) filter (where x.unused_now + x.refunded < x.granted_value) as rows_still_used,
--               i.cancel_refund_owed is not null as owed_stated,
--               (select count(*) from public.approval_requests r
--                 where r.related_record_id = i.id and r.status = 'pending'
--                   and r.request_type in ('invoice_cancel', 'invoice_refund')) as pending_requests
--          from x join public.invoices i on i.id = x.invoice_id
--         group by i.id, i.invoice_no, i.status, i.cancel_refund_owed
--        having count(*) filter (where x.unused_now < x.granted_value and x.unused_now + x.refunded >= x.granted_value) > 0
--         order by i.invoice_no;
--      (Invoice numbers and counts only. The suite runs this same text
--      before installing 448 and checks it lists exactly the invoices whose
--      answer changes.)
--   2. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below, the second changes
--      nothing ("left alone" three times).
--   3. Apply (the CLI, or the MCP's apply_migration with this text verbatim).
--      It checks itself.
--   Afterwards the re-run of 447 (it pins cancelled_invoice_used_value at
--   8caf1ea0 and invoice_action_plan at 3e5fe6cc) refuses, changing nothing,
--   where today it leaves all alone. 438's pins them too; its re-run, like
--   those of 436, 437, 439, 440, 441, 444, 445 and (since 450 changed
--   event_registration_close) 449, refuses already today on other pins.
--   442's, 443's, 446's and 450's still leave all alone (each checked on a
--   copy with 450 in, 22 Oct 2026). All are applied, so nothing is lost.
--   No test suite pins either md5.
--
-- BEFORE (production, 22 Oct 2026, at 450: 447's functions, which 450 did not
-- change; md5 of pg_get_functiondef with search_path public)
--   changed
--   cancelled_invoice_used_value(uuid)                             8caf1ea07bb021d91a5396b40fb7cda1  (438's AFTER)
--   invoice_action_plan(uuid,text,jsonb)                           3e5fe6ccd93548c13b6ed62800595838  (438's AFTER, 436 in)
--   invoice_benefit_unused_elsewhere(uuid)                         (not there)
--   relied on, not changed
--   invoice_voucher_reopen_candidates(uuid)                        20405a96c8780eac6425a5dae59c29e1  (the helper calls it)
--   invoice_refund_options(uuid)                                   689a71c246260d2c10ec44dd94eb7139  (the plan reads it)
--   invoice_refund_options_before_sessions(uuid)                   bd3afcc79cd2f06f983607d54fed167c
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)      804ecd829cfecf713783a09a05d93c7e  (446's AFTER)
--   reopen_invoice(uuid,text,uuid)                                 c9fcab7adfccdaeba1eb8dee4134ba47
--   apply_reopened_invoice_vouchers()                              71d50be41b73decceb0b20f8597dd4fa
--   apply_reopened_invoice_benefits()                              75489db2b12e60a3104fff9ef76c2d20
--   cancel_invoice_recorded(uuid,text,uuid)                        de52d9dbaef8ab15163bef35cb9d733d
--   trg_issue_sold_vouchers_on_paid()                              c840d0d2754e7a8e889848ea8269a293  (416)
--   transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)      7aebd7120bc3928db46df0941cb20889  (445's AFTER)
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)         e313e87b4ab4c0063d924430996ffbd3  (447's AFTER)
--   merge_customer_records(uuid,uuid,text,uuid)                    2e0c9852099ab88d8f27827b5f9a3846  (445's AFTER)
--   resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean) 201f08ebf14a64cd88d411a7cfb4c9c4
--   request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)      4360d74462ed1fc950b6bd8b5157b3ae
--   invoice_action_request_detail(uuid)                            df67842de673e4ec37890c027c52e0d9
--   invoice_financial_position(uuid)                               ba7eccbfeff217c8b1969b0e55a010ca
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)   80c80d386a5241e63b353e35e13ef250  (the self-test)
--   record_invoice_payment(uuid,jsonb,uuid)                        9c70097ed4da614fb9dcc66fdfcdb7d6  (the self-test)
--   public function fingerprint, production now (450 in)           46683a933775c18ee02261dafd3ffe47 (1370 functions)
--     before 450 (447's head)                                      9d2e2fdd5c26b214e5d1a0f867273aff (1370 functions)
-- AFTER (for later guards)
--   cancelled_invoice_used_value(uuid)                             055a3b07b1c15ffb1ac19039fa6cb650
--   invoice_action_plan(uuid,text,jsonb)                           383d618edb28c3c9a360242d038a022c
--   invoice_benefit_unused_elsewhere(uuid)                         d35d7c8ae7187985ea64f8a5c38a7d79  (new; service role alone)
--   public function fingerprint, worked out on a copy of production (22 Oct 2026):
--     production now (450 in) -> 448 (a second run the same)       63219badeea67a5d401d5af2aeb88f19 (1371 functions: one new, none dropped)
--     a base without 450 (447's head, 9d2e2fdd) -> 448             b2e3190d7c562705e1acc22487bbe869 (1371 functions)
--
-- Test: scripts/invoices/tests/refunded-units-not-used-448.sql (begin ...
-- rollback; it installs this file twice; -v nomig=1 where it is in). It
-- reproduces the false prompts first (where 448 is not in), on 29 cases
-- (vouchers and credit; a reopening, a wait, 446, a Move, a customer change,
-- a merge, an FOC taken off, a released lot, bundles, a session beside a
-- refund) and 15 controls, then checks: the controls read exactly as before
-- (codes, money, hash); each case asks only for real use, with its plans'
-- money exactly as before; the header's query lists exactly the invoices
-- that change; the money afterwards (Refund in full, the guided Cancel,
-- "Record refund paid" held to the refund due or to the amount owed
-- stated, the refund by line); settled and cancelled again; a request
-- raised before 448; the NOT COVERED cases as KNOWN. Where 448 is in,
-- reopen-recancel-438.sql checks its case 9 (2) and U4, and
-- reopen-refund-waiting-446.sql its cases 6, 7 and 8, the fixed way, and
-- scripts/permissions/tests/function-grants.sql lists the helper among the
-- internals no client role may call. Fixtures only (the repository is
-- public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The two functions this patches: BEFORE (production, 22 Oct 2026: 438's
  -- AFTER, 436 in) and AFTER md5s ═══════════════════════════════════════════
  c_uv constant text := 'cancelled_invoice_used_value(uuid)';
  c_pl constant text := 'invoice_action_plan(uuid,text,jsonb)';
  c_uv_before constant text := '8caf1ea07bb021d91a5396b40fb7cda1';
  c_uv_after  constant text := '055a3b07b1c15ffb1ac19039fa6cb650';
  c_pl_before constant text := '3e5fe6ccd93548c13b6ed62800595838';
  c_pl_after  constant text := '383d618edb28c3c9a360242d038a022c';

  -- ══ The helper this adds (the server's alone) ════════════════════════════
  c_h constant text := 'invoice_benefit_unused_elsewhere(uuid)';
  c_h_after constant text := 'd35d7c8ae7187985ea64f8a5c38a7d79';
  c_h_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';
  c_h_def constant text :=
$def$CREATE OR REPLACE FUNCTION public.invoice_benefit_unused_elsewhere(p_benefit_id uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 448 (the Owner, 22 Oct 2026: "build the warning fix"): what a benefit row of
-- an invoice granted that was not used although it is no longer on the row,
-- in the row's own terms (voucher units, or credit). On the row is its voucher
-- while held, or what its lot holds, and what a cancellation took back
-- (cancelled_unused_value). cancelled_invoice_used_value and
-- invoice_action_plan add this to that, and read the row as redeemed or spent
-- only when the sum is less than what the row granted. Only the two tests
-- read it: what can be refunded (invoice_refund_options) is the row's own and
-- is not changed, so nothing paid back is offered again.
declare b public.invoice_benefit_values%rowtype; v numeric; v_lots uuid[];
begin
  select * into b from public.invoice_benefit_values where id = p_benefit_id;
  if not found then return 0; end if;
  -- 438: moved by an Owner or Manager to another customer or store (the
  -- Finance panel's Move): its replacement is a benefit row of its own,
  -- tested on its own.
  v := coalesce((select sum(t.transferred_value) from public.invoice_benefit_transfers t
                  where t.source_benefit_id = b.id and t.replacement_benefit_id is not null), 0);
  if b.reward_voucher_id is not null then
    -- 438: given again by a reopening, or by the payment after an FOC came off
    -- (416), as a replacement row of its own.
    v := v + coalesce((select sum(q.quantity) from public.invoice_reopen_vouchers q
                        where q.benefit_id = b.id and q.applied_at is not null), 0);
    -- 448: paid back by a line refund since the invoice was last reopened, as
    -- the next reopening counts them to give back
    -- (invoice_voucher_reopen_candidates: what a cancellation took back plus
    -- the units refunded since the last reopening, whole units at the row's
    -- paid value, as the refund took them).
    v := v + greatest(coalesce((select c.quantity from public.invoice_voucher_reopen_candidates(b.invoice_id) c
                                 where c.benefit_id = b.id), 0) - b.cancelled_unused_value, 0);
    -- 448: paid back before the last reopening, which queued them to be given
    -- back when the invoice is settled, and still waiting: what waits beyond
    -- what a cancellation took back (a refund made while they wait takes its
    -- units off both, 446, and is counted above).
    v := v + greatest(coalesce((select sum(q.quantity) from public.invoice_reopen_vouchers q
                                 where q.benefit_id = b.id and q.applied_at is null), 0) - b.cancelled_unused_value, 0);
  elsif b.lot_id is not null then
    -- 448: credit paid back by a line refund and not put back by a reopening,
    -- read from the ledger rows a reopening puts back (reopen_invoice,
    -- apply_reopened_invoice_benefits): the invoice's own cancellation rows
    -- ('invoice_cancel_benefit') and its refunds' rows
    -- ('invoice_benefit_refund') on this row's lot, or on a lot it replaced
    -- (a merge, 445; a customer change, 447), not queued yet or queued and
    -- still waiting. What a cancellation took back is in those rows and in
    -- cancelled_unused_value alike, so what they hold beyond it was paid back:
    -- exactly what the refunds took, with no conversion from money.
    with recursive c(id, n) as (
      select b.lot_id, 0
      union all
      select l.reassigned_from_lot_id, c.n + 1
        from c join public.customer_credit_lots l on l.id = c.id
       where l.reassigned_from_lot_id is not null and c.n < 12)
    select array_agg(distinct c.id) into v_lots from c;
    v := v + greatest(
           coalesce((select sum(e.amount) from public.customer_credit_ledger e
                      where e.lot_id = any (v_lots)
                        and (e.source_type = 'invoice_cancel_benefit' and e.source_record_id = b.invoice_id
                             or e.source_type = 'invoice_benefit_refund'
                                and exists (select 1 from public.invoice_refunds r
                                             where r.invoice_id = b.invoice_id and r.request_id = e.source_record_id))
                        and not exists (select 1 from public.invoice_reopen_benefits q where q.source_ledger_id = e.id)), 0)
         + coalesce((select sum(q.amount) from public.invoice_reopen_benefits q
                       join public.customer_credit_ledger e on e.id = q.source_ledger_id
                      where q.invoice_id = b.invoice_id and q.applied_at is null and e.lot_id = any (v_lots)), 0)
         - b.cancelled_unused_value, 0);
  end if;
  return v;
end $function$
$def$;

  -- ══ cancelled_invoice_used_value: the voucher test and the credit test ══
  c_uv_a1 constant text := $a$                         -- 438: a unit a reopening or a payment gave again
                         -- (invoice_reopen_vouchers, applied) or an Owner moved
                         -- (invoice_benefit_transfers) was not used: its
                         -- replacement is a row of its own, tested here.
                         and coalesce(case when v.status = 'held' then v.quantity else 0 end, 0)
                             + b.cancelled_unused_value
                             + coalesce((select sum(q.quantity) from public.invoice_reopen_vouchers q
                                          where q.benefit_id = b.id and q.applied_at is not null), 0)
                             + coalesce((select sum(t.transferred_value) from public.invoice_benefit_transfers t
                                          where t.source_benefit_id = b.id and t.replacement_benefit_id is not null), 0)
                             < b.granted_value)
$a$;
  c_uv_r1 constant text := $r$                         -- 438: a unit a reopening or a payment gave again
                         -- (invoice_reopen_vouchers, applied) or an Owner moved
                         -- (invoice_benefit_transfers) was not used: its
                         -- replacement is a row of its own, tested here.
                         -- 448: nor was a unit a line refund paid back. Both
                         -- are counted in invoice_benefit_unused_elsewhere.
                         and coalesce(case when v.status = 'held' then v.quantity else 0 end, 0)
                             + b.cancelled_unused_value
                             + public.invoice_benefit_unused_elsewhere(b.id)
                             < b.granted_value)
$r$;
  c_uv_a2 constant text := $a$                         -- 438: credit an Owner moved was not spent: its new lot
                         -- is a row of its own, tested here.
                         and coalesce(l.remaining_amount, 0) + b.cancelled_unused_value
                             + coalesce((select sum(t.transferred_value) from public.invoice_benefit_transfers t
                                          where t.source_benefit_id = b.id and t.replacement_benefit_id is not null), 0)
                             < b.granted_value)
$a$;
  c_uv_r2 constant text := $r$                         -- 438: credit an Owner moved was not spent: its new lot
                         -- is a row of its own, tested here.
                         -- 448: nor was credit a line refund paid back. Both
                         -- are counted in invoice_benefit_unused_elsewhere.
                         and coalesce(l.remaining_amount, 0) + b.cancelled_unused_value
                             + public.invoice_benefit_unused_elsewhere(b.id)
                             < b.granted_value)
$r$;

  -- ══ invoice_action_plan: the per-benefit test ═══════════════════════════
  c_pl_a constant text := $a$   -- 438: a unit a reopening or a payment gave again (invoice_reopen_vouchers,
   -- applied) or an Owner moved to another customer or store (the Finance
   -- panel's Move, invoice_benefit_transfers) was not used: its replacement
   -- is a benefit of its own here, tested on its own.
   if coalesce((b->>'remaining_value')::numeric,0)
      +coalesce((select sum(q.quantity) from public.invoice_reopen_vouchers q
                  where q.benefit_id=(b->>'id')::uuid and q.applied_at is not null),0)
      +coalesce((select sum(t.transferred_value) from public.invoice_benefit_transfers t
                  where t.source_benefit_id=(b->>'id')::uuid and t.replacement_benefit_id is not null),0)
      < coalesce((b->>'granted_value')::numeric,0) then
$a$;
  c_pl_r constant text := $r$   -- 438: a unit a reopening or a payment gave again (invoice_reopen_vouchers,
   -- applied) or an Owner moved to another customer or store (the Finance
   -- panel's Move, invoice_benefit_transfers) was not used: its replacement
   -- is a benefit of its own here, tested on its own.
   -- 448 (the Owner, 22 Oct 2026): nor was a unit, or credit, a line refund
   -- paid back. Both are counted in invoice_benefit_unused_elsewhere, as
   -- cancelled_invoice_used_value counts them. What was paid back is not in
   -- remaining_value or max_refund, so it is not offered again.
   if coalesce((b->>'remaining_value')::numeric,0)
      +public.invoice_benefit_unused_elsewhere((b->>'id')::uuid)
      < coalesce((b->>'granted_value')::numeric,0) then
$r$;

  -- ══ Relied on, not changed (production, 22 Oct 2026, at 447) ════════════
  c_relied constant text[] := array[
    'invoice_voucher_reopen_candidates(uuid)',
    'invoice_refund_options(uuid)',
    'invoice_refund_options_before_sessions(uuid)',
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'reopen_invoice(uuid,text,uuid)',
    'apply_reopened_invoice_vouchers()',
    'apply_reopened_invoice_benefits()',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'trg_issue_sold_vouchers_on_paid()',
    'transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)',
    'move_invoice_benefits_to_customer(uuid,uuid,uuid,text)',
    'merge_customer_records(uuid,uuid,text,uuid)',
    'resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)',
    'request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)',
    'invoice_action_request_detail(uuid)',
    'invoice_financial_position(uuid)',
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    'record_invoice_payment(uuid,jsonb,uuid)'];
  c_relied_md5 constant text[] := array[
    '20405a96c8780eac6425a5dae59c29e1',
    '689a71c246260d2c10ec44dd94eb7139',
    'bd3afcc79cd2f06f983607d54fed167c',
    '804ecd829cfecf713783a09a05d93c7e',
    'c9fcab7adfccdaeba1eb8dee4134ba47',
    '71d50be41b73decceb0b20f8597dd4fa',
    '75489db2b12e60a3104fff9ef76c2d20',
    'de52d9dbaef8ab15163bef35cb9d733d',
    'c840d0d2754e7a8e889848ea8269a293',
    '7aebd7120bc3928db46df0941cb20889',
    'e313e87b4ab4c0063d924430996ffbd3',
    '2e0c9852099ab88d8f27827b5f9a3846',
    '201f08ebf14a64cd88d411a7cfb4c9c4',
    '4360d74462ed1fc950b6bd8b5157b3ae',
    'df67842de673e4ec37890c027c52e0d9',
    'ba7eccbfeff217c8b1969b0e55a010ca',
    '80c80d386a5241e63b353e35e13ef250',
    '9c70097ed4da614fb9dcc66fdfcdb7d6'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  r record; v text; d text; d2 text; n int; k int; i int;
  v_anchors text[]; v_patches text[]; v_before text; v_after text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[] := '{}'; v_new boolean := false;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_vch uuid; t_buyer uuid; t_pk uuid;
  t_inv uuid; t_item uuid; t_b uuid; t_pay uuid; t_plan jsonb; t_lines jsonb; t_msg text;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The helper's text is the tested one.
  if md5(c_h_def) <> c_h_after then
    raise exception '448: the text of public.% is not the tested one (md5 %)', c_h, md5(c_h_def); end if;

  -- The functions relied on are as read on production (22 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '448: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;

  -- The columns the helper reads, with these types.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('invoice_benefit_values', 'id', 'uuid'), ('invoice_benefit_values', 'invoice_id', 'uuid'),
                 ('invoice_benefit_values', 'lot_id', 'uuid'), ('invoice_benefit_values', 'reward_voucher_id', 'uuid'),
                 ('invoice_benefit_values', 'cancelled_unused_value', 'numeric(12,2)'),
                 ('invoice_benefit_values', 'granted_value', 'numeric(12,2)'),
                 ('invoice_reopen_vouchers', 'benefit_id', 'uuid'), ('invoice_reopen_vouchers', 'quantity', 'integer'),
                 ('invoice_reopen_vouchers', 'applied_at', 'timestamp with time zone'),
                 ('invoice_reopen_benefits', 'invoice_id', 'uuid'), ('invoice_reopen_benefits', 'source_ledger_id', 'uuid'),
                 ('invoice_reopen_benefits', 'amount', 'numeric(12,2)'),
                 ('invoice_reopen_benefits', 'applied_at', 'timestamp with time zone'),
                 ('invoice_benefit_transfers', 'source_benefit_id', 'uuid'),
                 ('invoice_benefit_transfers', 'replacement_benefit_id', 'uuid'),
                 ('invoice_benefit_transfers', 'transferred_value', 'numeric(12,2)'),
                 ('customer_credit_ledger', 'id', 'uuid'), ('customer_credit_ledger', 'lot_id', 'uuid'),
                 ('customer_credit_ledger', 'amount', 'numeric(12,2)'), ('customer_credit_ledger', 'source_type', 'text'),
                 ('customer_credit_ledger', 'source_record_id', 'uuid'),
                 ('customer_credit_lots', 'id', 'uuid'), ('customer_credit_lots', 'reassigned_from_lot_id', 'uuid'),
                 ('invoice_refunds', 'invoice_id', 'uuid'), ('invoice_refunds', 'request_id', 'uuid')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '448: these columns are missing or not as read on 22 Oct 2026: %', v; end if;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('cancelled_invoice_used_value', 'invoice_action_plan', 'invoice_benefit_unused_elsewhere')
     and p.oid::regprocedure::text not in (c_uv, c_pl, c_h);
  if v is not null then raise exception '448: another function takes the name of one this changes: %', v; end if;

  -- The helper: not there yet (created), or this version (left alone).
  if to_regprocedure('public.' || c_h) is not null then
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_h))) <> c_h_after then
      raise exception '448: public.% is there but not this version (md5 %). Nothing was changed.',
        c_h, md5(pg_get_functiondef(to_regprocedure('public.' || c_h))); end if;
  else
    v_new := true;
  end if;

  -- Each patched function: its BEFORE (patched; each anchor found once; the
  -- text built has its AFTER md5) or its AFTER (left alone).
  foreach v in array array[c_uv, c_pl] loop
    if to_regprocedure('public.' || v) is null then raise exception '448: public.% is missing', v; end if;
    if v = c_uv then
      v_anchors := array[c_uv_a1, c_uv_a2]; v_patches := array[c_uv_r1, c_uv_r2]; v_before := c_uv_before; v_after := c_uv_after;
    else
      v_anchors := array[c_pl_a]; v_patches := array[c_pl_r]; v_before := c_pl_before; v_after := c_pl_after;
    end if;
    d := pg_get_functiondef(to_regprocedure('public.' || v));
    if md5(d) = v_after then
      raise notice '448: public.% is already this version; left alone', v;
      continue;
    end if;
    d2 := d;
    for k in 1 .. cardinality(v_anchors) loop
      n := (length(d) - length(replace(d, v_anchors[k], ''))) / length(v_anchors[k]);
      if n <> 1 then
        raise exception '448: the anchor % of public.% is found % times, not once (md5 %). Re-read it and re-test before applying.', k, v, n, md5(d); end if;
      d2 := replace(d2, v_anchors[k], v_patches[k]);
    end loop;
    if md5(d) <> v_before then
      raise exception '448: public.% is not the version this was tested against (md5 %; patched it would be md5 %). Re-read it and re-test before applying.', v, md5(d), md5(d2); end if;
    if md5(d2) <> v_after then
      raise exception '448: the text built for public.% is not the tested one (md5 %)', v, md5(d2); end if;
    v_fns := v_fns || v;
    v_defs := v_defs || d2;
  end loop;

  -- The grants of the two, to compare after (as sets: production lists them
  -- in another order than a local copy does).
  foreach v in array array[c_uv, c_pl] loop
    v_acl := v_acl || (select coalesce(string_agg(x::text, ',' order by x::text), '')
                         from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || v));
  end loop;

  -- ── Install ───────────────────────────────────────────────────────────────
  -- The helper first: the patched texts call it.
  if v_new then
    execute c_h_def;
    execute format('revoke all on function public.%s from public, anon, authenticated', c_h);
    execute format('grant execute on function public.%s to service_role', c_h);
  else
    raise notice '448: public.% is already this version; left alone', c_h;
  end if;
  for k in 1 .. coalesce(cardinality(v_fns), 0) loop
    execute v_defs[k];
  end loop;

  -- ── Afterwards: installed exactly as tested, grants as before ────────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_h))) <> c_h_after then
    raise exception '448: public.% was installed with an md5 other than the tested one', c_h; end if;
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_uv))) <> c_uv_after
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_pl))) <> c_pl_after then
    raise exception '448: public.% or public.% is not at its AFTER md5 (% / %)', c_uv, c_pl,
      md5(pg_get_functiondef(to_regprocedure('public.' || c_uv))), md5(pg_get_functiondef(to_regprocedure('public.' || c_pl))); end if;
  k := 0;
  foreach v in array array[c_uv, c_pl] loop
    k := k + 1;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || v)) is distinct from v_acl[k] then
      raise exception '448: the grants of public.% changed', v; end if;
  end loop;
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_h))
     is distinct from (select array_agg(x::text order by x::text) from unnest(c_h_acl::aclitem[]) x)
     or has_function_privilege('anon', 'public.' || c_h, 'execute')
     or has_function_privilege('authenticated', 'public.' || c_h, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_h, 'execute') then
    raise exception '448: public.% is not the server''s alone', c_h; end if;
  if has_function_privilege('anon', 'public.' || c_uv, 'execute')
     or has_function_privilege('authenticated', 'public.' || c_uv, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_uv, 'execute')
     or has_function_privilege('anon', 'public.' || c_pl, 'execute')
     or not has_function_privilege('authenticated', 'public.' || c_pl, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_pl, 'execute') then
    raise exception '448: who may call public.% or public.% is not as before', c_uv, c_pl; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("448 check", @example.invalid, fictional ACMA phones
  -- no customer uses); it ends by raising P0448, which undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from unnest(array['+61491570481', '+61491570482', '+61491570483', '+61491570484']) p
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p limit 1);
    if coalesce(cardinality(t_phones), 0) < 1 then raise exception '448: the self-test found no unused fictional phone'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '448-check-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '448 check', '448-check-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('448 check ' || t_sfx, '448-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('448 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.customers (full_name, phone) values ('448 Check Buyer ' || t_sfx, t_phones[1]) returning id into t_buyer;
    insert into public.vouchers (name, code, voucher_kind, selling_price, qty_type, is_active)
    values ('448 check ' || t_sfx, '448-' || t_sfx, 'normal', 30, 'unlimited', true) returning id into t_vch;
    insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store) values (t_vch, t_store, 30, true);
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, bonus_value,
                                        allow_product, allow_therapy, allow_voucher, grants_reward)
    values ('448 check ' || t_sfx, 100, 100, true, 10, true, true, true, false) returning id into t_pk;
    insert into public.credit_package_stores (package_id, store_id) values (t_pk, t_store);

    -- (a) A line of two S$30 vouchers, paid, one unit refunded by line.
    t_inv := public.create_invoice(t_store, t_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', t_vch, 'quantity', 2)));
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)), gen_random_uuid());
    select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv;
    select b.id into t_b from public.invoice_benefit_values b where b.invoice_id = t_inv;
    select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1;
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 30,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_b, 'amount', 30)))),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 30)), '[]'::jsonb, '448 check', gen_random_uuid());
    if exists (select 1 from jsonb_array_elements(coalesce(public.invoice_action_plan(t_inv, 'refund_full', '[]'::jsonb)->'overrides_required', '[]'::jsonb)) o
                where o->>'code' in ('voucher_redeemed', 'credit_used'))
       or exists (select 1 from jsonb_array_elements(coalesce(public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->'overrides_required', '[]'::jsonb)) o
                   where o->>'code' in ('voucher_redeemed', 'credit_used'))
       or jsonb_typeof(public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->'refund_owed') = 'object'
       or (public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->>'refund_due')::numeric <> 30 then
      raise exception '448: a unit refunded by line still reads as redeemed (%)', public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb); end if;
    perform public.cancel_invoice_recorded(t_inv, '448 check', gen_random_uuid());
    if cardinality(public.cancelled_invoice_used_value(t_inv)) <> 0 then
      raise exception '448: cancelled, the invoice reads %', public.cancelled_invoice_used_value(t_inv); end if;
    perform public.refund_invoice_recorded(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 30)),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 30)), '[]'::jsonb, '448 check', gen_random_uuid());
    if (public.invoice_financial_position(t_inv)->>'refund_due')::numeric <> 0 or public.invoice_net_received(t_inv) <> 0 then
      raise exception '448: the S$30 still due was not recorded as paid back (%)', public.invoice_financial_position(t_inv); end if;

    -- (b) The same, but the other unit redeemed: still used, asked once.
    t_inv := public.create_invoice(t_store, t_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', t_vch, 'quantity', 2)));
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)), gen_random_uuid());
    select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv;
    select b.id into t_b from public.invoice_benefit_values b where b.invoice_id = t_inv;
    select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1;
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 30,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_b, 'amount', 30)))),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 30)), '[]'::jsonb, '448 check', gen_random_uuid());
    update public.customer_reward_vouchers set status = 'redeemed', redeemed_at = now()
     where id = (select b.reward_voucher_id from public.invoice_benefit_values b where b.id = t_b) and status = 'held';
    if not found then raise exception '448: the self-test found no held unit to redeem'; end if;
    t_plan := public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb);
    if (select count(*) from jsonb_array_elements(coalesce(t_plan->'overrides_required', '[]'::jsonb)) o where o->>'code' = 'voucher_redeemed') <> 1
       or jsonb_typeof(t_plan->'refund_owed') is distinct from 'object' or (t_plan->>'refund_due')::numeric <> 0 then
      raise exception '448: a redeemed unit beside a refunded one is not asked once (%)', t_plan; end if;
    perform public.cancel_invoice_recorded(t_inv, '448 check', gen_random_uuid());
    if public.cancelled_invoice_used_value(t_inv) is distinct from array['voucher_redeemed'] then
      raise exception '448: a redeemed unit reads % after the cancel', public.cancelled_invoice_used_value(t_inv); end if;
    t_msg := null;
    begin
      perform public.refund_invoice_recorded(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 30)),
        jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 30)), '[]'::jsonb, '448 check', gen_random_uuid());
    exception when others then t_msg := sqlerrm;
    end;
    if t_msg is null or t_msg not like 'Part of what % (vouchers redeemed)%' then
      raise exception '448: the S$30 of an invoice with a redeemed unit was not refused as used (%)', coalesce(t_msg, 'recorded'); end if;

    -- (c) Two S$100 Credit Packages (S$10 Bonus each), paid, line A refunded
    -- by line: nothing reads as spent; cancelled, the S$100 still due is
    -- recorded through line B's benefits (the Finance panel goes by line for
    -- credit). (d) Then S$10 of a second invoice's line B spent: spent.
    t_inv := public.create_invoice(t_store, t_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1),
                        jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)));
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 200)), gen_random_uuid());
    select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv order by it.id limit 1;
    select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1;
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 100,
        'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', b.id, 'amount', b.paid_value))
                       from public.invoice_benefit_values b where b.invoice_item_id = t_item))),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 100)), '[]'::jsonb, '448 check', gen_random_uuid());
    t_plan := public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb);
    if exists (select 1 from jsonb_array_elements(coalesce(t_plan->'overrides_required', '[]'::jsonb)) o where o->>'code' = 'credit_used')
       or jsonb_typeof(t_plan->'refund_owed') = 'object' or (t_plan->>'refund_due')::numeric <> 100 then
      raise exception '448: credit refunded by line still reads as spent (%)', t_plan; end if;
    perform public.cancel_invoice_recorded(t_inv, '448 check', gen_random_uuid());
    if cardinality(public.cancelled_invoice_used_value(t_inv)) <> 0 then
      raise exception '448: cancelled, the credit invoice reads %', public.cancelled_invoice_used_value(t_inv); end if;
    t_plan := public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb);
    select jsonb_agg(jsonb_build_object('invoice_item_id', l->>'invoice_item_id', 'amount', (l->>'amount')::numeric,
             'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', x->>'benefit_id', 'amount', (x->>'amount')::numeric))
                            from jsonb_array_elements(l->'benefits') x)))
      into t_lines from jsonb_array_elements(t_plan->'lines') l where (l->>'amount')::numeric > 0;
    perform public.refund_invoice_recorded(t_inv, t_lines,
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 100)), '[]'::jsonb, '448 check', gen_random_uuid());
    if (public.invoice_financial_position(t_inv)->>'refund_due')::numeric <> 0 then
      raise exception '448: the credit invoice''s S$100 still due was not recorded (%)', public.invoice_financial_position(t_inv); end if;
    t_inv := public.create_invoice(t_store, t_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1),
                        jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)));
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 200)), gen_random_uuid());
    select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv order by it.id limit 1;
    select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1;
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 100,
        'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', b.id, 'amount', b.paid_value))
                       from public.invoice_benefit_values b where b.invoice_item_id = t_item))),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 100)), '[]'::jsonb, '448 check', gen_random_uuid());
    update public.customer_credit_lots set remaining_amount = remaining_amount - 10
     where id = (select b.lot_id from public.invoice_benefit_values b
                  where b.invoice_id = t_inv and b.invoice_item_id <> t_item and b.granted_value = 100);
    if not found then raise exception '448: the self-test found no lot to spend from'; end if;
    if (select count(*) from jsonb_array_elements(coalesce(public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->'overrides_required', '[]'::jsonb)) o
         where o->>'code' = 'credit_used') <> 1 then
      raise exception '448: credit spent beside credit refunded is not asked once (%)', public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->'overrides_required'; end if;

    raise exception using errcode = 'P0448', message = '448: self-test done, undone';
  exception when sqlstate 'P0448' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
