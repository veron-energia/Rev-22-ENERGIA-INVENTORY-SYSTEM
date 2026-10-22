-- 451_reopen_refund_cycles_give_what_was_paid.sql
--
-- A VOUCHER UNIT REFUNDED ON BOTH SIDES OF A REOPENING IS GIVEN BACK ONCE THE
-- INVOICE IS PAID AGAIN: AFTER ANY LINE REFUNDS, CANCELS AND REOPENINGS, THE
-- CUSTOMER HOLDS WHAT THE INVOICE'S NET PAYMENT BUYS (the Owner, 22 Oct 2026:
-- "fix the rare 446 voucher case too"; 448's NOT COVERED 1)
--
-- WHO FOUND IT
--
--   Found while 448 was built (22 Oct 2026), written up as 448's NOT COVERED
--   1 and checked as KNOWN by its suite
--   (scripts/invoices/tests/refunded-units-not-used-448.sql, case 8 (1)).
--   Reproduced for this file on a copy of production as it is now (63219bad,
--   1371 functions: 448, 449 and 450 in), with made-up records, through the
--   app's own calls only (the invoice form and the Pay dialog, the guided
--   "Refund some items", Refund in full and Cancel, Cancel, Reopen, the
--   Finance panel's refund by line and "Record refund paid", Record Payment,
--   Move, the invoice form's customer change, the FOC taken off). With 417's
--   refund_invoice_recorded rebuilt (e6f6c3cb, 446's two blocks taken out)
--   the same steps give the right count. Then every sibling was looked for
--   by trying every sequence of those calls, up to six to eight steps, on a
--   line of two, of three, two lines of one, a line of two beside a line of
--   one, a limited voucher (with its stock), an FOC taken off (paid and not),
--   Premium Bundles with vouchers, and for credit one and two S$100 Credit
--   Packages (with and without a S$10 Bonus, S$40 refunds), Premium Bundles,
--   and Move and the customer change on both; after every step it checked
--   what the customer holds and what waits against what each line charges,
--   the stock, the Reopen dialog's figures, and 448's counting.
--
-- WHAT WAS WRONG
--
--   A reopening queues, for each voucher benefit row of the invoice, the units
--   its candidates count (invoice_voucher_reopen_candidates: what a
--   cancellation took back, cancelled_unused_value, plus the units refunded
--   by line since the last reopening), less what still waits from an earlier
--   reopening that was not settled (417: "only what is more", so units
--   cancelled again before they were settled are queued once). That took
--   every waiting unit for one the candidates count again. Two kinds are
--   not: units an earlier line refund took, which the earlier reopening
--   queued to give back (the candidates count only refunds since the last
--   reopening, so no longer these); and units refunded while they waited,
--   which since 446 come off the queue and off cancelled_unused_value alike,
--   so they no longer wait at all. Before 446 the second kind stayed in the
--   queue, and that hid the first. So on a voucher row of two or more units,
--   with units refunded by line before a reopening and others refunded after
--   it out of what the cancellation took back, the next reopening queued too
--   few, by the smaller of the two counts:
--   * a line of two S$30 vouchers, paid, one unit refunded (the guided
--     "Refund some items"), cancelled, reopened (both wait), cancelled again,
--     the other unit refunded by line (the Finance panel), reopened: 1 unit
--     waits for the S$60 the line charges again; paid, the customer held 1
--     voucher for S$60 (before 446: 2); the Reopen dialog said 1 unit to
--     replace, and 448 read the unit never given as redeemed (Cancel and
--     Refund in full asked voucher_redeemed, and once cancelled "Record
--     refund paid" was refused);
--   * the same with the second refund made while the reopened invoice waited
--     (not cancelled first), then cancelled and reopened; or the first one
--     made on the cancelled invoice before the first reopening;
--   * by every route that refunds by line: the guided "Refund some items",
--     the Finance panel's refund by line, the guided Refund in full, and the
--     guided Cancel with the money recorded (its plan refunds the waiting
--     units by line);
--   * a line of three, one or two units each side (short by the smaller);
--     each further cycle could lose more;
--   * the row that holds the units after a Move to another customer, or
--     after a customer change that took the vouchers along; a voucher given
--     again after its FOC was taken off and the invoice paid (416); a Premium
--     Bundle's vouchers; a limited voucher, whose stock followed the short
--     count (stock out equalled the units held, one too few).
--   Not: two lines of one (a row of one unit is refunded on one side only: a
--   unit queued because a refund took it cannot be refunded while it waits,
--   446's NOT COVERED 2), a row refunded on one side of the reopenings only,
--   and any row of an invoice with nothing refunded by line.
--   Credit: no such shortfall (below, CREDIT); searched the same way, nothing
--   found.
--   Production, 22 Oct 2026 (counts only): invoice_reopen_vouchers has never
--   had a row; invoice_reopen_benefits has 4 rows, on one invoice (11 Sep
--   2026), none waiting. So it has never happened; nothing to repair. The
--   file refuses, changing nothing, if an invoice where it can have happened
--   exists when it is applied (SAFETY).
--
-- THE OWNER'S ANSWER (22 Oct 2026)
--
--   "Fix the rare 446 voucher case too": after any sequence of line refunds,
--   cancels, reopenings and settlements, the customer holds exactly the
--   vouchers the invoice's net payment buys: units refunded stay refunded,
--   units paid for are given once. 438's and 448's counting keep reading
--   right (no false voucher_redeemed, no real redemption missed). And the
--   same for credit, with 446's credit part, if the credit analogue exists
--   (it does not: CREDIT below).
--
-- WHAT THIS DOES (two functions patched at one anchor each; grants kept)
--
--   * reopen_invoice(uuid,text,uuid): 417's "only what is more" takes off
--     only the cancellation's part of what waits: the waiting units up to
--     the row's cancelled_unused_value. The units a cancellation took back
--     stay in cancelled_unused_value while they wait (a refund made while
--     they wait takes its units off both, 446), so that is the part the
--     candidates count again; the rest of what waits is units earlier line
--     refunds took, which the candidates no longer count. So the reopening
--     queues the units refunded since the last reopening, and what a
--     cancellation took back that does not wait yet, on top of what waits.
--     On the copy: the line of two above, 2 wait (1 + 1 queued now); paid,
--     2 vouchers for S$60, nothing asked by Cancel or Refund in full.
--   * invoice_reopen_preview_before_sessions(uuid) (the Reopen dialog's
--     "Voucher units to replace after settlement", through
--     invoice_reopen_preview): what waits plus what reopen_invoice now
--     queues, by the same rule (before: the larger of the two counts).
--     reopen_invoice also stores this preview in the reopening's revision
--     and Audit Log entry, so those read right too.
--   Where nothing waits, or what waits is all the cancellation's (417's own
--   case: cancelled again before settling, with no line refund before the
--   earlier reopening), the subtraction is the same as before, to the unit:
--   the waiting units are then no more than cancelled_unused_value.
--   Otherwise it queues what 417's rule queued plus the units it left out,
--   and no more: what waits afterwards is every unit taken back from the
--   customer (by a cancellation or a line refund) and not given back since,
--   each once; its stock is taken once (when the invoice is settled,
--   apply_reopened_invoice_vouchers, unchanged).
--
-- WHY IN THE REOPENING, NOT IN 446's QUEUE STEP
--
--   A refund made while units wait cannot know whether a reopening follows:
--   if the invoice is settled next, the refunded unit must not be given
--   (446's fix); if it is reopened again, the reopening gives it back
--   (charging the line again), and only the reopening can tell. Leaving the
--   refunded unit in the queue (as before 446) gives it at settlement;
--   marking it given would give its stock back twice at a later
--   cancellation (446's header, VOUCHERS). The reopening already knows both
--   counts; it only subtracted the wrong part.
--
-- CREDIT: NO SHORTFALL (why; the suite proves it)
--
--   Credit is queued by ledger row, not by count: a reopening queues each
--   'invoice_cancel_benefit' row of the invoice and each refund's
--   'invoice_benefit_refund' row not queued before, whole (reopen_invoice;
--   invoice_reopen_benefits.source_ledger_id is unique), and subtracts
--   nothing. A cancellation of an invoice whose credit waits finds its lots
--   empty and writes no new row, so nothing is queued twice. A refund made
--   while credit waits (446) gives the refunded part from the waiting rows
--   (a 'reverse' row) and takes it back in its own 'invoice_benefit_refund'
--   row, which the next reopening queues, once. So every amount taken back
--   is queued once and given once, however the refunds fall around the
--   reopenings. On the copy, every sequence searched (above) left the
--   customer exactly the credit each line charges; the suite runs the
--   voucher sequences above on credit, whole and S$40 at a time, with and
--   without 451 (the same, and right), and a bounded search of every
--   sequence.
--
-- NOT CHANGED
--
--   * invoice_voucher_reopen_candidates, apply_reopened_invoice_vouchers,
--     refund_invoice_recorded (446's queue step), cancel_invoice_recorded,
--     trg_issue_sold_vouchers_on_paid (416), transfer_invoice_unused_benefit
--     (a Move is still refused while units wait), the credit queue and its
--     functions: pinned below.
--   * 448's counting (invoice_benefit_unused_elsewhere, read by
--     cancelled_invoice_used_value and invoice_action_plan) counts what waits
--     beyond cancelled_unused_value as units refunded before the last
--     reopening, and units refunded since then by the candidates: with the
--     missing unit now queued it reads right with no change (the suite: no
--     voucher_redeemed asked, waiting or settled, and cancelled nothing
--     "used"; a real redemption still asked).
--   * invoice_voucher_stock_unrecorded's count before a reopening (it caps
--     the Reopen dialog's "Stock to issue" for a limited voucher) still takes
--     the larger of what waits and the candidates. It differs from what the
--     reopening now queues only where units were refunded by line before an
--     earlier reopening and since it, and there the voucher's own stock
--     movement rows already record the units the paid invoice gave, so the
--     figure it caps comes out the same: in every sequence searched (a
--     limited voucher, after a Move or a customer change, an FOC taken off
--     and paid) the dialog's "Stock to issue" equalled what the reopening and
--     its payment took besides what waits, with or without changing it. Left
--     as it is, to change as little as possible. Its other count (after the
--     queue is written: reopen_invoice's own) was always what waits.
--   * The pages: the Finance panel reads the preview's figure as before
--     (InvoiceFinancePanel.tsx); no message or button changes. No table, row,
--     index, grant or other function changes.
--
-- NOT COVERED (for the Owner; the suite checks 1 as it is and prints it as
-- KNOWN; 446's and 448's suites check 2)
--
--   1. A voucher row that still holds units when its invoice is reopened:
--      only after a line refund that pays back more than the units it takes
--      (the 'larger_refund' override, which refund_invoice_recorded accepts
--      but no page sends; the Finance panel sends none and the guided plans
--      never ask it), then reopened, cancelled (the held units taken back)
--      and reopened again: the units that cancellation took back are taken
--      for ones already waiting, so one unit too few waits (a line of two,
--      S$60 back with one unit taken: 1 voucher for S$60). The same before
--      451 (417's rule) and before 446; not caused by either. Telling the
--      two apart needs when a cancellation took its units relative to the
--      last reopening, which no table keeps. Production: no reopening has
--      ever queued a voucher. Through the pages it cannot happen: a
--      reopening needs the invoice cancelled (which takes back every held
--      unit) or refunded in full (which takes back every unit it pays for).
--   2. 446's NOT COVERED 5 and 448's NOT COVERED 2 (after a customer change
--      or a merge, a reopening gives a refunded unit or credit back to the
--      old holder): unchanged, there before; not this.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * each function is its BEFORE (production, 22 Oct 2026: 417's AFTERs;
--     patched, its anchor found once, the text built has the tested AFTER
--     md5) or its AFTER (left alone), so a second run changes nothing; no
--     other function takes the two names; invoice_reopen_preview is the only
--     function that calls invoice_reopen_preview_before_sessions, and none
--     calls reopen_invoice (the Finance panel's Reopen calls it);
--   * the functions it relies on are as read on production (below);
--     invoice_reopen_vouchers' columns and constraints, the columns read, the
--     candidates' result columns and the triggers on invoices that give what
--     waits are as read;
--   * on the first run only (reopen_invoice its BEFORE): no invoice carries
--     the fault's footprint: a waiting voucher row 446 lowered or removed
--     for a refund ('reopen_voucher_refunded' in the invoice's Audit Log),
--     the invoice reopened again after that refund, and a line refund naming
--     the same benefit row recorded before the reopening that queued the row
--     (its revision's reopened_at). Where those three meet, the reopening
--     after the refund may have queued too few (it did when the earlier
--     refund's units still waited then; the file does not try to tell), so
--     what the customer holds needs a decision first: the file stops,
--     changing nothing, and names the invoices. Each condition is needed:
--     446's own case (no line refund before the first reopening), a refund
--     while waiting not yet followed by a reopening, and a refund with no
--     line before it are not listed (the suite, case 9). None on production
--     (the queue has never had a row). A second run skips this (reopenings
--     since are right);
--   * who may call each is as read (reopen_invoice: signed-in staff and the
--     service role; the preview: the service role alone), compared as sets
--     (production lists them in another order than a local copy), and kept.
--   Afterwards: both md5s are the AFTER ones; the grants are as before. Then a
--   self-test, in a block that is always undone (it ends by raising P0451, so
--   it leaves no row): a made-up Owner, store, buyer (a fictional ACMA phone
--   no customer has) and S$30 voucher. (a) A line of two, paid, one unit
--   refunded by line, cancelled, reopened (2 wait), cancelled again, the other
--   unit refunded by line (1 waits), the Reopen dialog says 2, reopened: 2
--   wait (one queued now); paid S$60: 2 held, Cancel asks no override.
--   (b) 417's own case: a line of two, paid, cancelled, S$30 paid back,
--   reopened (2 wait), cancelled again, reopened: still 2 wait (none queued),
--   the dialog said 2; paid: 2 held. (c) A unit refunded while waiting, then
--   cancelled again and reopened (446's case, unchanged): 2 wait; paid: 2.
--   Its invoice numbers are counted, not drawn from a sequence. Locks: the
--   two functions' catalogue rows, to the end of the apply; the rows the
--   self-test writes and undoes. A reopening running at that moment finishes
--   on the text it started with.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (... 447, 448, 449, 450: 63219bad, 1371 functions, head
--   20261022083155) -> 451. No page, Edge Function or setting changes.
--   449 and 450 (the event website, another session) change none of the
--   functions this file changes or relies on, and pin neither of its two.
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below, the second changes
--      nothing ("left alone" twice).
--   2. Apply (the CLI, or the MCP's apply_migration with this text verbatim).
--      It checks itself.
--   Afterwards the re-runs of 446 (it pins reopen_invoice at c9fcab7a and
--   invoice_reopen_preview_before_sessions at 4723b49b) and 448 (it pins
--   reopen_invoice) refuse, changing nothing, where today they leave all
--   alone. 417, 434, 436 and 438 pin reopen_invoice too, and their re-runs
--   refuse already today on other pins (each checked on a copy, 22 Oct
--   2026). All are applied, so nothing is lost.
--   scripts/invoices/tests/sold-voucher-issuance.sql reads reopen_invoice's
--   md5 only to print a known fault it no longer meets: its case prints
--   PASS (10 both times) with and without 451 (checked).
--
-- BEFORE (production, 22 Oct 2026, at 450; md5 of pg_get_functiondef with
-- search_path public)
--   changed
--   reopen_invoice(uuid,text,uuid)                                     c9fcab7adfccdaeba1eb8dee4134ba47  (417's AFTER)
--   invoice_reopen_preview_before_sessions(uuid)                       4723b49b3f27c17254c2987c4bebc17b  (417's AFTER)
--   relied on, not changed
--   invoice_voucher_reopen_candidates(uuid)                            20405a96c8780eac6425a5dae59c29e1  (the candidates)
--   apply_reopened_invoice_vouchers()                                  71d50be41b73decceb0b20f8597dd4fa  (gives what waits)
--   apply_reopened_invoice_benefits()                                  75489db2b12e60a3104fff9ef76c2d20  (credit; reinstates what waits)
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)          804ecd829cfecf713783a09a05d93c7e  (446's AFTER: its queue step)
--   cancel_invoice_recorded(uuid,text,uuid)                            de52d9dbaef8ab15163bef35cb9d733d  (cancelled_unused_value; stock)
--   invoice_voucher_stock_unrecorded(uuid,boolean)                     91c8f0fa69ef6337f323b7ac467a8c2b  (stock recorded at a reopening)
--   deduct_invoice_stock(uuid,text)                                    32183fe9e7c15ed0b11307c48289831a
--   invoice_stock_to_deduct(uuid)                                      6356494ccb8545d46c56b788f8f85f54
--   trg_issue_sold_vouchers_on_paid()                                  c840d0d2754e7a8e889848ea8269a293  (416; runs after the reopening's trigger)
--   invoice_reopen_preview(uuid)                                       7cb2805a10d92c41626e85a3542cc1f8  (the dialog; its one caller)
--   invoice_benefit_unused_elsewhere(uuid)                             d35d7c8ae7187985ea64f8a5c38a7d79  (448's counting)
--   cancelled_invoice_used_value(uuid)                                 055a3b07b1c15ffb1ac19039fa6cb650  (448's AFTER)
--   invoice_action_plan(uuid,text,jsonb)                               383d618edb28c3c9a360242d038a022c  (448's AFTER)
--   transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)          7aebd7120bc3928db46df0941cb20889  (445's AFTER; no Move while units wait)
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)       80c80d386a5241e63b353e35e13ef250  (the self-test)
--   record_invoice_payment(uuid,jsonb,uuid)                            9c70097ed4da614fb9dcc66fdfcdb7d6  (the self-test)
--   public function fingerprint, production now (450 in)           63219badeea67a5d401d5af2aeb88f19 (1371 functions)
-- AFTER (for later guards)
--   reopen_invoice(uuid,text,uuid)                                     cb647331300b0a476c1da7b2cb599889
--   invoice_reopen_preview_before_sessions(uuid)                       12206ed066495024421b3b44a6a9d8e2
--   public function fingerprint, worked out on a copy of production (22 Oct 2026):
--     production now (450 in) -> 451 (a second run the same)       893b4cdfee1b7ae8dde1a3fa9a86221a (1371 functions: none new, none dropped)
--
-- Test: scripts/invoices/tests/reopen-refund-cycles-451.sql (begin ...
-- rollback; it installs this file twice; -v nomig=1 where it is in). It
-- reproduces the shortfall first (where 451 is not in), on every sibling
-- found, then checks the refusal, the install, each case fixed (vouchers
-- held, net received, stock, the Reopen dialog, 448's counting, and further
-- cycles), the controls unchanged (compared whole with and without 451),
-- the credit analogue absent (the same sequences on credit, with and
-- without 451), a bounded search of every sequence after 451 (vouchers and
-- credit), and NOT COVERED 1 as KNOWN. Where 451 is in,
-- refunded-units-not-used-448.sql checks its case 8 (1) the fixed way.
-- Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The two functions this patches: BEFORE (production, 22 Oct 2026:
  -- 417's AFTERs) and AFTER md5s ═══════════════════════════════════════════
  c_ro constant text := 'reopen_invoice(uuid,text,uuid)';
  c_pv constant text := 'invoice_reopen_preview_before_sessions(uuid)';
  c_ro_before constant text := 'c9fcab7adfccdaeba1eb8dee4134ba47';
  c_ro_after  constant text := 'cb647331300b0a476c1da7b2cb599889';
  c_pv_before constant text := '4723b49b3f27c17254c2987c4bebc17b';
  c_pv_after  constant text := '12206ed066495024421b3b44a6a9d8e2';
  -- Who may call each, as read (kept).
  c_ro_acl constant text := '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}';
  c_pv_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';

  -- ══ reopen_invoice: the queue of voucher units ═══════════════════════════
  c_ro_a constant text := $a$ -- 417 (the Owner, 9 Oct 2026): units an earlier reopening queued, and still
 -- waiting because the invoice was cancelled again before it was settled,
 -- are given with this one. Only what is more is queued, so each unit is
 -- given, and its stock taken, once. Before, both were given.
 insert into public.invoice_reopen_vouchers(invoice_id,benefit_id,request_id,quantity)
 select i.id,c.benefit_id,p_request_id,c.quantity-coalesce(w.quantity,0)
   from public.invoice_voucher_reopen_candidates(i.id) c
   left join (select q.benefit_id,sum(q.quantity)::int as quantity from public.invoice_reopen_vouchers q
               where q.invoice_id=i.id and q.applied_at is null group by q.benefit_id) w on w.benefit_id=c.benefit_id
  where c.quantity-coalesce(w.quantity,0)>0;
$a$;
  c_ro_r constant text := $r$ -- 417 (the Owner, 9 Oct 2026): units an earlier reopening queued, and still
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
$r$;

  -- ══ invoice_reopen_preview_before_sessions: the Reopen dialog's count ═══
  c_pv_a constant text := $a$   -- 417: with the units an earlier reopening queued that are still waiting
   -- (reopen_invoice gives those, or more if there are more to give).
   (select coalesce(sum(greatest(c.quantity,coalesce((select sum(q.quantity) from public.invoice_reopen_vouchers q
      where q.invoice_id=i.id and q.benefit_id=c.benefit_id and q.applied_at is null),0))),0)
      from public.invoice_voucher_reopen_candidates(i.id) c),'stock_to_issue',$a$;
  c_pv_r constant text := $r$   -- 417: with the units an earlier reopening queued that are still waiting
   -- (reopen_invoice gives those, or more if there are more to give).
   -- 451: and what reopen_invoice queues beside them, by its rule: the
   -- candidates less the cancellation's part of what waits (up to
   -- cancelled_unused_value).
   (select coalesce(sum(w.quantity+greatest(c.quantity-least(w.quantity,b.cancelled_unused_value::int),0)),0)
      from public.invoice_voucher_reopen_candidates(i.id) c
      join public.invoice_benefit_values b on b.id=c.benefit_id
      cross join lateral (select coalesce(sum(q.quantity),0)::int as quantity from public.invoice_reopen_vouchers q
                           where q.invoice_id=i.id and q.benefit_id=c.benefit_id and q.applied_at is null) w),'stock_to_issue',$r$;

  -- ══ Relied on, not changed (production, 22 Oct 2026, at 450) ════════════
  c_relied constant text[] := array[
    'invoice_voucher_reopen_candidates(uuid)',
    'apply_reopened_invoice_vouchers()',
    'apply_reopened_invoice_benefits()',
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'invoice_voucher_stock_unrecorded(uuid,boolean)',
    'deduct_invoice_stock(uuid,text)',
    'invoice_stock_to_deduct(uuid)',
    'trg_issue_sold_vouchers_on_paid()',
    'invoice_reopen_preview(uuid)',
    'invoice_benefit_unused_elsewhere(uuid)',
    'cancelled_invoice_used_value(uuid)',
    'invoice_action_plan(uuid,text,jsonb)',
    'transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)',
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    'record_invoice_payment(uuid,jsonb,uuid)'];
  c_relied_md5 constant text[] := array[
    '20405a96c8780eac6425a5dae59c29e1',
    '71d50be41b73decceb0b20f8597dd4fa',
    '75489db2b12e60a3104fff9ef76c2d20',
    '804ecd829cfecf713783a09a05d93c7e',
    'de52d9dbaef8ab15163bef35cb9d733d',
    '91c8f0fa69ef6337f323b7ac467a8c2b',
    '32183fe9e7c15ed0b11307c48289831a',
    '6356494ccb8545d46c56b788f8f85f54',
    'c840d0d2754e7a8e889848ea8269a293',
    '7cb2805a10d92c41626e85a3542cc1f8',
    'd35d7c8ae7187985ea64f8a5c38a7d79',
    '055a3b07b1c15ffb1ac19039fa6cb650',
    '383d618edb28c3c9a360242d038a022c',
    '7aebd7120bc3928db46df0941cb20889',
    '80c80d386a5241e63b353e35e13ef250',
    '9c70097ed4da614fb9dcc66fdfcdb7d6'];

  -- ══ The voucher queue, as read on 22 Oct 2026 (446 read the same) ═══════
  c_q_cols constant text :=
    'id uuid, invoice_id uuid, benefit_id uuid, request_id uuid, quantity integer, replacement_voucher_id uuid, '
    'created_at timestamp with time zone, applied_at timestamp with time zone';
  c_q_cons constant text :=
    'invoice_reopen_vouchers_benefit_id_fkey FOREIGN KEY (benefit_id) REFERENCES invoice_benefit_values(id) | '
    'invoice_reopen_vouchers_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES invoices(id) | '
    'invoice_reopen_vouchers_invoice_id_request_id_benefit_id_key UNIQUE (invoice_id, request_id, benefit_id) | '
    'invoice_reopen_vouchers_pkey PRIMARY KEY (id) | '
    'invoice_reopen_vouchers_quantity_check CHECK ((quantity > 0)) | '
    'invoice_reopen_vouchers_replacement_voucher_id_fkey FOREIGN KEY (replacement_voucher_id) REFERENCES customer_reward_vouchers(id)';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  r record; v text; d text; d2 text; n int; k int; i int; v_first boolean;
  v_anchor text; v_patch text; v_before text; v_after text; v_want text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[] := '{}';
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_vch uuid; t_buyer uuid;
  t_inv uuid; t_item uuid; t_b uuid; t_pay uuid;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The functions relied on are as read on production (22 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '451: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if to_regprocedure('auth.uid()') is null then raise exception '451: auth.uid() must be there'; end if;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('reopen_invoice', 'invoice_reopen_preview_before_sessions')
     and p.oid::regprocedure::text not in (c_ro, c_pv);
  if v is not null then raise exception '451: another function takes the name of one this changes: %', v; end if;

  -- Who calls them, as read: the preview only through invoice_reopen_preview
  -- (the Reopen dialog); reopen_invoice by no function (the Finance panel
  -- calls it). (A session's own temporary functions are not counted.)
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'invoice_reopen_preview_before_sessions\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and not (p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = c_pv);
  if v is distinct from 'invoice_reopen_preview(uuid)' then
    raise exception '451: the functions that call invoice_reopen_preview_before_sessions are not as read on 22 Oct 2026 (%); check each, then re-test', v; end if;
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'reopen_invoice\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and not (p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = c_ro);
  if v is not null then
    raise exception '451: a function now calls reopen_invoice (%; none did on 22 Oct 2026); check it, then re-test', v; end if;

  -- The voucher queue: its columns and constraints as read.
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), ', ' order by a.attnum) into v
    from pg_attribute a
   where a.attrelid = to_regclass('public.invoice_reopen_vouchers') and a.attnum > 0 and not a.attisdropped;
  if v is distinct from c_q_cols then
    raise exception '451: invoice_reopen_vouchers'' columns are not as read on 22 Oct 2026: %', v; end if;
  select string_agg(k2.conname || ' ' || pg_get_constraintdef(k2.oid), ' | ' order by k2.conname) into v
    from pg_constraint k2 where k2.conrelid = 'public.invoice_reopen_vouchers'::regclass;
  if v is distinct from c_q_cons then
    raise exception '451: invoice_reopen_vouchers'' constraints are not as read on 22 Oct 2026: %', v; end if;
  -- The other columns read, with these types; the candidates' result.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('invoice_benefit_values', 'id', 'uuid'), ('invoice_benefit_values', 'invoice_id', 'uuid'),
                 ('invoice_benefit_values', 'cancelled_unused_value', 'numeric(12,2)'),
                 ('invoice_refunds', 'invoice_id', 'uuid'), ('invoice_refunds', 'request_id', 'uuid'),
                 ('invoice_refunds', 'outcome', 'jsonb'), ('invoice_refunds', 'created_at', 'timestamp with time zone'),
                 ('invoice_revisions', 'invoice_id', 'uuid'), ('invoice_revisions', 'request_id', 'uuid'),
                 ('invoice_revisions', 'after_snapshot', 'jsonb'),
                 ('invoices', 'reopened_at', 'timestamp with time zone'),
                 ('audit_logs', 'table_name', 'text'), ('audit_logs', 'record_id', 'uuid'), ('audit_logs', 'action', 'text'),
                 ('audit_logs', 'old_data', 'jsonb'), ('audit_logs', 'new_data', 'jsonb')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '451: these columns are missing or not as read on 22 Oct 2026: %', v; end if;
  if pg_get_function_result('public.invoice_voucher_reopen_candidates(uuid)'::regprocedure)
     is distinct from 'TABLE(benefit_id uuid, quantity integer)' then
    raise exception '451: invoice_voucher_reopen_candidates no longer returns (benefit_id uuid, quantity integer)'; end if;
  -- The settling payment gives what waits (the reopening's triggers), then
  -- 416's runs after them.
  for r in select * from (values
      ('invoice_reopen_benefits_settled', 'CREATE TRIGGER invoice_reopen_benefits_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_benefits()'),
      ('invoice_reopen_vouchers_settled', 'CREATE TRIGGER invoice_reopen_vouchers_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_vouchers()'),
      ('issue_sold_vouchers_on_paid',     'CREATE TRIGGER issue_sold_vouchers_on_paid AFTER UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_issue_sold_vouchers_on_paid()')) x(tg, def)
  loop
    if (select pg_get_triggerdef(t.oid) from pg_trigger t
         where t.tgrelid = 'public.invoices'::regclass and t.tgname = r.tg and t.tgenabled = 'O') is distinct from r.def then
      raise exception '451: the trigger % on public.invoices is not the one read on 22 Oct 2026', r.tg; end if;
  end loop;

  -- Each patched function: its BEFORE (patched; its anchor found once; the
  -- text built has its AFTER md5) or its AFTER (left alone).
  foreach v in array array[c_ro, c_pv] loop
    if to_regprocedure('public.' || v) is null then raise exception '451: public.% is missing', v; end if;
    if v = c_ro then
      v_anchor := c_ro_a; v_patch := c_ro_r; v_before := c_ro_before; v_after := c_ro_after;
    else
      v_anchor := c_pv_a; v_patch := c_pv_r; v_before := c_pv_before; v_after := c_pv_after;
    end if;
    d := pg_get_functiondef(to_regprocedure('public.' || v));
    if md5(d) = v_after then
      if v = c_ro then v_first := false; end if;
      raise notice '451: public.% is already this version; left alone', v;
      continue;
    end if;
    if v = c_ro then v_first := true; end if;
    n := (length(d) - length(replace(d, v_anchor, ''))) / length(v_anchor);
    if n <> 1 then
      raise exception '451: the anchor of public.% is found % times, not once (md5 %). Re-read it and re-test before applying.', v, n, md5(d); end if;
    d2 := replace(d, v_anchor, v_patch);
    if md5(d) <> v_before then
      raise exception '451: public.% is not the version this was tested against (md5 %; patched it would be md5 %). Re-read it and re-test before applying.', v, md5(d), md5(d2); end if;
    if md5(d2) <> v_after then
      raise exception '451: the text built for public.% is not the tested one (md5 %)', v, md5(d2); end if;
    v_fns := v_fns || v;
    v_defs := v_defs || d2;
  end loop;

  -- On the first run (reopen_invoice its BEFORE): no invoice carries the
  -- fault's footprint. A waiting voucher row 446 lowered or removed for a
  -- refund (its Audit Log entry keeps the row as it was, and the refund's
  -- request id); the invoice reopened again after that refund; and a line
  -- refund naming the same benefit row recorded before the reopening that
  -- queued the row (the reopening's revision keeps its reopened_at). Where
  -- the three meet, the reopening after the refund may have queued too few;
  -- what the customer holds then needs a decision first. None on 22 Oct
  -- 2026 (the queue has never had a row). A second run skips this: the
  -- reopenings since are right.
  if v_first then
    select count(distinct iv.id), string_agg(distinct iv.invoice_no, ', ' order by iv.invoice_no) into i, v
      from public.audit_logs a
      join public.invoices iv on iv.id = a.record_id
      join public.invoice_refunds rw on rw.invoice_id = iv.id and rw.request_id::text = a.new_data->>'request_id'
      join public.invoice_revisions rq on rq.invoice_id = iv.id and rq.request_id::text = a.old_data->>'request_id'
     where a.table_name = 'invoices' and a.action = 'reopen_voucher_refunded'
       and iv.reopened_at > rw.created_at
       and exists (select 1 from public.invoice_refunds rb
                    cross join lateral jsonb_array_elements(case when jsonb_typeof(rb.outcome->'lines') = 'array'
                                                                 then rb.outcome->'lines' else '[]'::jsonb end) x
                    cross join lateral jsonb_array_elements(case when jsonb_typeof(x->'benefits') = 'array'
                                                                 then x->'benefits' else '[]'::jsonb end) z
                    where rb.invoice_id = iv.id and z->>'benefit_id' = a.new_data->>'benefit_id'
                      and rb.created_at < (rq.after_snapshot->>'reopened_at')::timestamptz);
    if i > 0 then
      raise exception '451: % invoice(s) had a voucher unit refunded by line before a reopening and another while it waited, and were reopened again (%): that reopening may have queued too few. Decide what each customer should hold, then apply. Nothing was changed.', i, v; end if;
  end if;

  -- Who may call each, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  foreach v in array array[c_ro, c_pv] loop
    v_want := c_pv_acl;
    if v = c_ro then v_want := c_ro_acl; end if;
    if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || v))
       is distinct from (select array_agg(x::text order by x::text) from unnest(v_want::aclitem[]) x) then
      raise exception '451: who may call public.% is not as read on 22 Oct 2026 (%)', v,
        (select proacl::text from pg_proc where oid = to_regprocedure('public.' || v)); end if;
    v_acl := v_acl || (select coalesce(string_agg(x::text, ',' order by x::text), '')
                         from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || v));
  end loop;

  -- ── Change ──────────────────────────────────────────────────────────────
  for k in 1 .. coalesce(cardinality(v_fns), 0) loop
    execute v_defs[k];
  end loop;

  -- ── Afterwards: installed exactly as tested, grants as before ────────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_ro))) <> c_ro_after
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_pv))) <> c_pv_after then
    raise exception '451: public.% or public.% is not at its AFTER md5 (% / %)', c_ro, c_pv,
      md5(pg_get_functiondef(to_regprocedure('public.' || c_ro))), md5(pg_get_functiondef(to_regprocedure('public.' || c_pv))); end if;
  k := 0;
  foreach v in array array[c_ro, c_pv] loop
    k := k + 1;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || v)) is distinct from v_acl[k] then
      raise exception '451: the grants of public.% changed', v; end if;
  end loop;
  if has_function_privilege('anon', 'public.' || c_ro, 'execute')
     or not has_function_privilege('authenticated', 'public.' || c_ro, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_ro, 'execute')
     or has_function_privilege('anon', 'public.' || c_pv, 'execute')
     or has_function_privilege('authenticated', 'public.' || c_pv, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_pv, 'execute') then
    raise exception '451: who may call public.% or public.% is not as before', c_ro, c_pv; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("451 check", @example.invalid, fictional ACMA phones
  -- no customer uses); it ends by raising P0451, which undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from unnest(array['+61491570951', '+61491570952', '+61491570953', '+61491570954']) p
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p limit 1);
    if coalesce(cardinality(t_phones), 0) < 1 then raise exception '451: the self-test found no unused fictional phone'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '451-check-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '451 check', '451-check-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('451 check ' || t_sfx, '451-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('451 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.customers (full_name, phone) values ('451 Check Buyer ' || t_sfx, t_phones[1]) returning id into t_buyer;
    insert into public.vouchers (name, code, voucher_kind, selling_price, qty_type, is_active)
    values ('451 check ' || t_sfx, '451-' || t_sfx, 'normal', 30, 'unlimited', true) returning id into t_vch;
    insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store) values (t_vch, t_store, 30, true);

    -- (a) A line of two S$30 vouchers, paid; one unit refunded by line;
    -- cancelled; reopened (2 wait); cancelled again; the other unit refunded
    -- by line (446 takes it off the queue: 1 waits); reopened: 2 wait.
    t_inv := public.create_invoice(t_store, t_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', t_vch, 'quantity', 2)));
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)), gen_random_uuid());
    select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv;
    select b.id into t_b from public.invoice_benefit_values b where b.invoice_id = t_inv;
    select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1;
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 30,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_b, 'amount', 30)))),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 30)), '[]'::jsonb, '451 check', gen_random_uuid());
    perform public.cancel_invoice_recorded(t_inv, '451 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '451 check', gen_random_uuid());
    if (select coalesce(sum(q.quantity), 0) from public.invoice_reopen_vouchers q where q.invoice_id = t_inv and q.applied_at is null) <> 2 then
      raise exception '451: the self-test''s line of two does not wait with both units after its first reopening'; end if;
    perform public.cancel_invoice_recorded(t_inv, '451 check again', gen_random_uuid());
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 30,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_b, 'amount', 30)))),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 30)), '[]'::jsonb, '451 check', gen_random_uuid());
    if (select coalesce(sum(q.quantity), 0) from public.invoice_reopen_vouchers q where q.invoice_id = t_inv and q.applied_at is null) <> 1
       or (public.invoice_reopen_preview_before_sessions(t_inv)->>'voucher_units_to_reinstate_after_settlement')::int <> 2 then
      raise exception '451: after the second refund the self-test''s line does not wait with 1 unit, or the Reopen dialog would not replace 2 (%)',
        public.invoice_reopen_preview_before_sessions(t_inv)->>'voucher_units_to_reinstate_after_settlement'; end if;
    perform public.reopen_invoice(t_inv, '451 check', gen_random_uuid());
    if (select coalesce(sum(q.quantity), 0) from public.invoice_reopen_vouchers q where q.invoice_id = t_inv and q.applied_at is null) <> 2
       or public.invoice_charge_total(t_inv) <> 60 then
      raise exception '451: reopened again, the self-test''s line does not wait with 2 units for S$60 (% wait)',
        (select coalesce(sum(q.quantity), 0) from public.invoice_reopen_vouchers q where q.invoice_id = t_inv and q.applied_at is null); end if;
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)), gen_random_uuid());
    if (select status::text from public.invoices where id = t_inv) is distinct from 'paid'
       or public.invoice_net_received(t_inv) <> 60
       or (select coalesce(sum(v.quantity), 0) from public.invoice_benefit_values b
             join public.customer_reward_vouchers v on v.id = b.reward_voucher_id
            where b.invoice_id = t_inv and v.status = 'held') <> 2
       or exists (select 1 from jsonb_array_elements(coalesce(public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb)->'overrides_required', '[]'::jsonb)) o
                   where o->>'code' = 'voucher_redeemed') then
      raise exception '451: settled, the self-test''s buyer does not hold 2 vouchers for S$60 with nothing read as redeemed'; end if;

    -- (b) 417's own case: cancelled again before it was settled, no line
    -- refund: still 2 wait, none queued twice.
    t_inv := public.create_invoice(t_store, t_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', t_vch, 'quantity', 2)));
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)), gen_random_uuid());
    select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1;
    perform public.cancel_invoice_recorded(t_inv, '451 check', gen_random_uuid());
    perform public.refund_invoice_recorded(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 30)),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 30)), '[]'::jsonb, '451 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '451 check', gen_random_uuid());
    perform public.cancel_invoice_recorded(t_inv, '451 check again', gen_random_uuid());
    if (public.invoice_reopen_preview_before_sessions(t_inv)->>'voucher_units_to_reinstate_after_settlement')::int <> 2 then
      raise exception '451: 417''s case: the Reopen dialog would not replace 2'; end if;
    perform public.reopen_invoice(t_inv, '451 check', gen_random_uuid());
    if (select coalesce(sum(q.quantity), 0) from public.invoice_reopen_vouchers q where q.invoice_id = t_inv and q.applied_at is null) <> 2
       or (select count(*) from public.invoice_reopen_vouchers q where q.invoice_id = t_inv) <> 1 then
      raise exception '451: 417''s case: cancelled again and reopened, the units were queued again'; end if;
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 30)), gen_random_uuid());
    if (select coalesce(sum(v.quantity), 0) from public.invoice_benefit_values b
          join public.customer_reward_vouchers v on v.id = b.reward_voucher_id
         where b.invoice_id = t_inv and v.status = 'held') <> 2 then
      raise exception '451: 417''s case: settled, the buyer does not hold 2 vouchers'; end if;

    -- (c) 446's case: a unit refunded while waiting, cancelled again and
    -- reopened: the refund is given back once (2 wait), as before.
    t_inv := public.create_invoice(t_store, t_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', t_vch, 'quantity', 2)));
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)), gen_random_uuid());
    select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv;
    select b.id into t_b from public.invoice_benefit_values b where b.invoice_id = t_inv;
    select p.id into t_pay from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1;
    perform public.cancel_invoice_recorded(t_inv, '451 check', gen_random_uuid());
    perform public.refund_invoice_recorded(t_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 30)),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 30)), '[]'::jsonb, '451 check', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '451 check', gen_random_uuid());
    perform public.refund_invoice_recorded(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'amount', 30,
        'benefits', jsonb_build_array(jsonb_build_object('benefit_id', t_b, 'amount', 30)))),
      jsonb_build_array(jsonb_build_object('payment_id', t_pay, 'amount', 30)), '[]'::jsonb, '451 check', gen_random_uuid());
    perform public.cancel_invoice_recorded(t_inv, '451 check again', gen_random_uuid());
    perform public.reopen_invoice(t_inv, '451 check', gen_random_uuid());
    if (select coalesce(sum(q.quantity), 0) from public.invoice_reopen_vouchers q where q.invoice_id = t_inv and q.applied_at is null) <> 2 then
      raise exception '451: 446''s case: refunded while waiting, cancelled again and reopened, 2 do not wait'; end if;
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 60)), gen_random_uuid());
    if (select coalesce(sum(v.quantity), 0) from public.invoice_benefit_values b
          join public.customer_reward_vouchers v on v.id = b.reward_voucher_id
         where b.invoice_id = t_inv and v.status = 'held') <> 2 or public.invoice_net_received(t_inv) <> 60 then
      raise exception '451: 446''s case: settled, the buyer does not hold 2 vouchers for S$60'; end if;

    raise exception using errcode = 'P0451', message = '451: self-test done, undone';
  exception when sqlstate 'P0451' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
