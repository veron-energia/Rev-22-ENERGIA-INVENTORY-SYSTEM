-- 447_customer_change_invoice_follows_credit.sql
--
-- AN INVOICE WHOSE CUSTOMER WAS CHANGED WITH ITS BENEFITS TAKEN ALONG STILL
-- FINDS ITS CREDIT: A CANCELLATION TAKES IT BACK FROM THE NEW CUSTOMER, A
-- REFUND IS CAPPED BY THE NEW CUSTOMER'S LOT, AND THE REFUND DUE CAN BE
-- RECORDED (the Owner, 22 Oct 2026: "Fix it"; 438's NOT COVERED 5)
--
-- WHO FOUND IT
--
--   The reviews of 438 (21 Oct 2026; 438's header, NOT COVERED 5, "there
--   before 438, not caused by it"), and seen again while 445 was checked
--   (445's header, NOT COVERED, last point). Reproduced on 22 Oct 2026 on a
--   copy of production as it is (fingerprint 83a90dbf, 1370 functions), with
--   made-up records, through the app's own calls: the invoice form's
--   customer change (correct_invoice with benefit_action 'transfer'), the
--   guided Refund in full and Cancel (invoice_action_plan,
--   request_invoice_action_v2, resolve_invoice_action_v2), the Finance
--   panel's "Record refund paid" and its line-by-line refund
--   (refund_invoice_recorded).
--
-- WHAT WAS WRONG
--
--   A customer change that takes the invoice's benefits along calls
--   move_invoice_benefits_to_customer (321; last 417, md5 2c01c460). A
--   voucher moves in place (the same row, now the new customer's, still
--   held). Credit cannot change customer (a posted lot is immutable,
--   trg_credit_lot_immutable, 77), so each unused lot of the invoice is drawn
--   down to 0 and the new customer is granted the same credit as a new lot
--   (reassigned_from_lot_id names the lot it replaces). But the invoice's own
--   records still named the emptied lot: its benefit values
--   (invoice_benefit_values.lot_id: what a cancellation, a refund and its
--   cap, a Move and the "credit spent" checks read), its sale's lots
--   (credit_package_sales.credit_lot_id / bonus_credit_lot_id,
--   premium_bundle_sales.paid_credit_lot_id / bonus_credit_lot_id: what a
--   refund's commission is traced back through and what the refund blockers
--   and the Dashboard read) and a shared package's issued lot
--   (invoice_credit_splits.issued_lot_id). So, for a paid S$1,000 Credit
--   Package (S$1,000 Paid, S$100 Bonus) changed from one customer to another
--   (on the copy):
--   * the guided Refund in full and Cancel asked a credit_used override for
--     both lots ("credit spent"), though nothing had been spent, and the
--     refund options showed both benefits held by the first customer with
--     S$0 refundable; the refund blockers said "Credit from this purchase
--     has already been used";
--   * the guided Refund in full, its overrides given, was refused ("There
--     is nothing left to refund on this invoice");
--   * the guided Cancel also asked "State how much is owed back" ("Part of
--     what this invoice sold has been used ..."); confirmed with the false
--     overrides and no amount stated, it kept all S$1,000 "for used credit"
--     (refund due S$0), while the new customer kept all S$1,100 (the
--     cancellation follows each benefit row's own lot, now 0);
--   * a direct cancellation left the new customer the S$1,100 too and read
--     credit_used (cancelled_invoice_used_value), and its S$1,000 refund due
--     could not be recorded: "Record refund paid" is refused for any credit
--     invoice by design ("Allocate a correction refund to the original
--     unused purchased benefits ..."), and the line-by-line refund the panel
--     then offers had nothing to allocate (the cancel plan's line was S$0,
--     with credit_used asked), or was refused as over its cap ("Refund
--     exceeds the unused paid value of this benefit": the cap reads the
--     emptied lot);
--   * a refund of part of the credit, before any cancellation, was refused
--     the same way, and the Finance panel's Move of it was refused ("No
--     unused value remains to move").
--   The same for a Premium Bundle, for an invoice changed twice (A to B to
--   C), for credit partly spent at the new customer (both lots read spent),
--   and for paid credit released before settlement (credit_package_progress
--   _lots, 356) once the invoice is settled: 356 listed this last one under
--   NOT CHANGED, and scripts/credit-policy/tests/released-credit-paths.sql
--   has printed it as KNOWN GAP 6b since. (Changed before settlement, there
--   is no benefit value or sale yet: the released credit is followed along
--   already, credit_lot_current, and the payment that settles the invoice
--   records it on the new customer's lot. That case worked and still does.)
--   Production, read 22 Oct 2026 (counts only): no lot has a
--   reassigned_from_lot_id (0); the three customer changes that took
--   benefits along (17 Sep, 25 Sep, 20 Oct) each moved 1 voucher and 0
--   credit lots. So it has not happened: there is nothing to repair.
--
-- THE OWNER'S ANSWER (22 Oct 2026, GAP 5)
--
--   "Fix it": after a customer change that takes the invoice's benefits
--   along, the invoice's own records follow the credit to the new customer's
--   lot, the way 445 did for merges, so a cancellation takes the credit back
--   from the new customer, the refund cap reads the new lot, and the refund
--   due can be recorded. Vouchers already move in place and stay as they
--   are.
--
-- WHAT THIS DOES (move_invoice_benefits_to_customer(uuid,uuid,uuid,text);
-- one block added in its credit loop, nothing else in it changes)
--
--   For each of the invoice's lots it moves, as before: the lot is drawn
--   down to 0 (ledger 'invoice_reassignment_out'), the new customer is
--   granted the same credit as a new lot (ledger 'invoice_reassignment_in';
--   source, category, restrictions, store and dates carried; the link
--   reassigned_from_lot_id). Then, as 445's merge does:
--   1. The records that name the lot holding the purchase's credit name the
--      new customer's lot: the invoice's benefit values
--      (invoice_benefit_values.lot_id), the sale's lots
--      (credit_package_sales.credit_lot_id / bonus_credit_lot_id,
--      premium_bundle_sales.paid_credit_lot_id / bonus_credit_lot_id) and a
--      shared package's issued lot (invoice_credit_splits.issued_lot_id). So
--      a cancellation takes the credit back from the new customer
--      (cancel_invoice_recorded), a refund is capped by, and takes back from,
--      the new customer's lot (invoice_refund_options, refund_invoice_
--      recorded), the guided plans ask no false credit_used, 438's used-value
--      test (cancelled_invoice_used_value) reads it as unused, the refund
--      due can be recorded, a Move of it works, and the commission and
--      refund-basis readers still find the sale (invoice_commission_benefit_
--      source: the benefit and the sale name the same lot, as before). The
--      lot it replaced is no longer named by the sale, so it no longer shows
--      among the invoice's lots as "Fully spent" (invoice_credit_lot_ids
--      walks on from the sale's lot); credit_lot_chain still walks from it.
--   2. Not a lot whose benefit value was moved on to someone else (the
--      Finance panel's Move, 186: their credit is traced back through it):
--      its records stay where they are, as in a merge (rare: a Move takes
--      all of the lot's credit, so such a lot moves with the invoice only if
--      all of it was put back on it later).
--   3. A second customer change does the same again (A to B to C: the
--      records name C's lot); a part-paid invoice's released credit stays
--      named by credit_package_progress_lots, followed along as before.
--   Its signature, grants (the server's alone), answer ('vouchers',
--   'credit_lots', 'allowances'), audit row ('invoice_benefits_followed_
--   reassignment'), checks, locks, voucher, voucher stock, therapy and
--   ledger steps, and the lots it writes are as they were, byte for byte.
--
-- NOT CHANGED
--
--   * No lot, ledger row, benefit value, sale, split, voucher or invoice
--     (checked before anything changes: no invoice record names a lot a
--     customer change emptied; 0 lots have the link on production).
--   * Vouchers: moved in place, as before (the same row; its benefit value
--     names the same voucher).
--   * credit_package_progress_lots keeps naming the lot it released (it is
--     followed along by credit_lot_current, 356); invoice_line_credit_
--     allocations, customer_credit_allocations, customer_credit_adjustments
--     and special_credit_allocations record what happened to a lot and keep
--     naming it; the ledger rows a customer change writes, their amounts,
--     reasons and sources.
--   * Its caller, correct_invoice (the invoice form's save), and every
--     reader of these records: they read the records, which now name the
--     credit where it is. merge_customer_records and transfer_invoice_
--     unused_benefit stay 445's (2e0c9852, 7aebd712). refund_invoice_
--     recorded, invoice_voucher_reopen_candidates and apply_reopened_
--     invoice_vouchers (446's, 438's NOT COVERED 4) are neither changed nor
--     pinned here, so 446 and 447 go in either order.
--   * The pages: the invoice form's "Move the unused benefits to the new
--     customer" now holds for refunds and cancellations too; the guided
--     Refund / Cancel, the Finance panel and the Invoices page read the
--     server's plan, options and used value (InvoicesPage.tsx,
--     InvoiceFinancePanel.tsx). No page change.
--
-- NOT COVERED (told to the Owner)
--
--   * A lot whose benefit value was moved on (2. above): its records stay on
--     the first customer's emptied lot, as before this file and as in a
--     merge; a cancellation does not reach the new customer's part of it.
--   * A shared package's split (invoice_credit_splits, 141, older invoices
--     only) keeps naming its share's customer (customer_id); its issued lot
--     is now the new customer's (1.), so invoice_credit_split reads that
--     customer's name with the new customer's balance. A customer change
--     that takes the benefits along still takes every share of the invoice
--     to the new customer, as since 321. Neither is changed here.
--   * The sale rows keep naming the buyer at the time of sale
--     (credit_package_sales.customer_id, premium_bundle_sales.customer_id),
--     as before; nothing that takes credit back reads them.
--   * A reopened invoice whose cancelled credit is still waiting to be put
--     back (invoice_reopen_benefits not yet applied): the credit goes back,
--     when it is settled, on the lot the cancellation took it from, as
--     before (such a lot is empty, so a customer change does not move it).
--   * Seen while checking, not changed here: a 141 split issues each share
--     a whole package's credit (issue_credit_package with no line, 355: on
--     a copy, a S$1,000 package split 400 / 600 gave each share S$1,000 Paid
--     and S$100 Bonus). Older invoices only: set_invoice_credit_split is the
--     server's alone and no page calls it.
--   * Found when 446 and 447 were checked together (22 Oct 2026; there
--     before both, caused by neither): a customer change made while a
--     reopened invoice still waits (vouchers or credit not yet given back)
--     moves nothing that waits, so when the invoice is settled the waiting
--     vouchers and credit go to the OLD customer; a customer change does not
--     take a reopening's replacement vouchers along (only 'invoice_voucher_
--     sale' and 'invoice_promotion_voucher' rows move); and a line refunded
--     before a customer change, then cancelled, reopened and settled, puts
--     that line's credit back on the old customer's emptied lot (446's NOT
--     COVERED 5). Production has never had a waiting reopening with a
--     customer change. Each needs its own change.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the text built is the tested one (its AFTER md5);
--   * move_invoice_benefits_to_customer is its BEFORE (production, 22 Oct
--     2026: 417's text) or this file's AFTER (left alone); no other function
--     takes its name; only correct_invoice calls it;
--   * the functions it relies on and does not change are as read on
--     production (22 Oct 2026), below; auth.uid() is there. None of them is
--     refund_invoice_recorded, invoice_voucher_reopen_candidates or
--     apply_reopened_invoice_vouchers, the ones 446 may change (446's draft
--     of 22 Oct 2026 changes refund_invoice_recorded alone);
--   * the columns that name a lot are the fifteen 445 read (a new one would
--     need a decision: repointed or kept), the columns it repoints and reads
--     are there with their types, customer_credit_lots has its one trigger
--     as read, and the five tables it repoints or reads have none;
--   * no invoice record (benefit value, sale lot, split issued lot) names a
--     lot that a customer change emptied and replaced (ledger grant
--     'invoice_reassignment_in'), other than a lot whose benefit value was
--     moved on (0 on production: no lot has the link). One would need a
--     repair decision first, so the file stops and changes nothing;
--   * who may call it is as read (the server alone: postgres, service_role;
--     compared as sets, since production lists grants in another order than
--     a local copy), and is kept.
--   Afterwards: the md5 is the AFTER one; the grants are as before. Then a
--   self-test, in a block that is always undone (it ends by raising P0447,
--   so it leaves no row): a made-up Owner, store, payment method, Credit
--   Package (S$100 Paid, S$10 Bonus) and two customers (fictional ACMA
--   phones no customer has); the first buys the package (cash), the invoice's
--   customer is changed to the second with the benefits taken along
--   (correct_invoice, benefit_action 'transfer'); the benefit values and the
--   sale name the second customer's two new lots, the refund options show
--   them as the second customer's with their paid value refundable, and the
--   guided Refund in full asks no credit_used; then it is cancelled: the
--   second customer's two lots are emptied, nothing reads as used, and the
--   S$100 refund due is recorded through the line's benefits (refund due 0).
--   Its invoice number is counted, not drawn from a sequence; its credit
--   ledger rows draw entry numbers (a sequence, which an undone transaction
--   does not give back: a gap, which nothing counts). Each run, a second run
--   too, leaves these gaps. A second run changes nothing else.
--   Locks: the function's catalogue row, held to the end of the apply; the
--   rows the self-test writes and undoes. An invoice save running at that
--   moment finishes on the text it started with.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (... 443, 444, 445, 449) -> 447. No page, Edge Function
--   or setting changes. 449 (the event website, another session; live 22
--   Oct 2026 05:25 UTC, file md5 33508eab, fingerprint 6e368a7e) changes and
--   pins none of the functions here; 448 is unused.
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below, the second changes
--      nothing ("left alone").
--   2. Apply (the CLI, or the MCP's apply_migration with this text verbatim).
--      It checks itself.
--   446 (438's NOT COVERED 4, another session) changes refund_invoice_
--   recorded, which this file neither changes nor pins; this file changes
--   move_invoice_benefits_to_customer alone, which 446 neither changes nor
--   pins. So either order: on copies, the final 446 (vouchers and credit,
--   refund_invoice_recorded AFTER 804ecd82) then 447, and 447 then 446, both
--   end at the same fingerprint (below). If 446 changes again before it goes
--   live, re-check that it still changes none of the functions pinned here.
--   Afterwards the re-run of 445 (it pins move_invoice_benefits_to_customer
--   at 2c01c460) refuses, where today it leaves all alone; those of 434, 438
--   and 441 refuse already; 443's and 444's still leave all alone (checked
--   on a copy, 22 Oct 2026). All are applied, so nothing is lost.
--
-- BEFORE (production, 22 Oct 2026, after 445; md5 of pg_get_functiondef
-- with search_path public)
--   changed
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)        2c01c460d3af8edd3ad86332aa286ed8  (417's text)
--   relied on, not changed
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                    422682d6e1ada0e5d98053e74ab9f007  (its one caller)
--   invoice_credit_lot_ids(uuid)                                   50346a2e9aea50b31d4207c43b2f197c  (the lots it moves)
--   invoice_transferable_benefits(uuid)                            e3a4b753d87546a1a73342baf02bee70
--   credit_lot_chain(uuid)                                         556e725784154cbffc23d3ad900f9366
--   credit_lot_current(uuid)                                       d48fb24e6eb9733d7f867e42fa703e7b
--   capture_invoice_benefit_values(uuid)                           d5e061945c2921a1af86f8c99a349e98
--   cancel_invoice_recorded(uuid,text,uuid)                        de52d9dbaef8ab15163bef35cb9d733d
--   writeoff_released_credit_on_close(uuid,text,text)              284a89cfb965e8028136b5f8a4f2bf08
--   invoice_refund_options_before_sessions(uuid)                   bd3afcc79cd2f06f983607d54fed167c
--   cancelled_invoice_used_value(uuid)                             8caf1ea07bb021d91a5396b40fb7cda1  (438's AFTER)
--   invoice_action_plan(uuid,text,jsonb)                           3e5fe6ccd93548c13b6ed62800595838  (438's AFTER, 436 in)
--   invoice_commission_benefit_source(uuid)                        f8d3d29fae79065a252a8c5231cc2d4b
--   credit_purchase_refund_blockers(uuid)                          aa1afae71965fa31f8d0db616505edc8
--   customer_credit_balances(uuid)                                 c2287779ce0ec9c52eeec41952055f78
--   invoice_credit_transfer_origin(uuid)                           e778a9e4ff81567a493b8ca479d8222b
--   merge_customer_records(uuid,uuid,text,uuid)                    2e0c9852099ab88d8f27827b5f9a3846  (445's AFTER)
--   transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)      7aebd7120bc3928db46df0941cb20889  (445's AFTER)
--   trg_credit_lot_immutable()                                     0fc74da0dcc9b436dfd26c4582542f6c
--   ensure_customer_wallet(uuid)                                   8ef18daebbbe3c12f2024290ea8416e8
--   entitlement_claimed_qty(uuid)                                  89b08265d5303e890569e953d83d2440
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)   80c80d386a5241e63b353e35e13ef250  (the self-test)
--   record_invoice_payment(uuid,jsonb,uuid)                        9c70097ed4da614fb9dcc66fdfcdb7d6  (the self-test)
--   public function fingerprint, after 445                         83a90dbfc238c7f6048c8dc9e435d876 (1370 functions)
--   public function fingerprint, production now (449 in too)       6e368a7e6c22d186edc59798d1d31210 (1370 functions)
-- AFTER (for later guards)
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)        e313e87b4ab4c0063d924430996ffbd3
--   public function fingerprint, worked out on a copy of production (22 Oct 2026):
--     after 445 -> 447 (a second run the same)                     d2c798fa36896de2ddd1e9d05757c54c (1370 functions: none new, none dropped)
--     after 445 -> 446 -> 447, or 447 -> 446                       fcd9ec302339119c8191aa1940b2e14b (1370 functions)
--     production now (449 in) -> 447 (a second run the same)     e2fc58439246052d5ee15941c5d4ea64 (1370 functions)
--     production now (449 in) -> 446 -> 447, or 447 -> 446         9d2e2fdd5c26b214e5d1a0f867273aff (1370 functions)
--
-- Test: scripts/invoices/tests/customer-change-credit-447.sql (begin ...
-- rollback; it installs this file twice; -v nomig=1 where it is in). It
-- runs every case with 417's text first (rebuilt from this file's and
-- checked by its md5; undone) and then with this file's, and compares:
-- Credit Package and Premium Bundle Paid and Bonus, a part-paid package
-- changed before and after settling, credit partly spent at the new
-- customer, a second change, a Move after the change and a change after a
-- Move, 445's V path without a merge, a lot whose benefit value was moved
-- on, vouchers alone, an invoice with both, a shared package, and the
-- records the change itself writes (the same with both texts).
-- Where this file is in, scripts/invoices/tests/reopen-recancel-438.sql
-- checks its KNOWN 5 as fixed (as before where it is not), and
-- scripts/credit-policy/tests/released-credit-paths.sql makes its KNOWN GAP
-- 6b a hard check and finds case 9's released-lot benefits along the chain
-- (on the replacement lots now).

set lock_timeout = '5s';

do $mig$
declare
  -- ── The function this changes: signature, BEFORE md5 (production, 22 Oct
  -- 2026: 417's text), AFTER md5, and the text (as pg_get_functiondef gives
  -- it back with search_path public). ───────────────────────────────────────
  c_sig constant text := 'move_invoice_benefits_to_customer(uuid,uuid,uuid,text)';
  c_before constant text := '2c01c460d3af8edd3ad86332aa286ed8';
  c_after constant text := 'e313e87b4ab4c0063d924430996ffbd3';
  c_def constant text :=
$def$CREATE OR REPLACE FUNCTION public.move_invoice_benefits_to_customer(p_invoice_id uuid, p_customer_id uuid, p_store_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_blocked text; v_v int := 0; v_c int := 0; v_a int := 0; v_wallet uuid; v417 record;
        r_lot public.customer_credit_lots%rowtype; v_new_lot uuid;
begin
  select string_agg(description || ' (' || blocked_reason || ')', '; ')
    into v_blocked
    from public.invoice_transferable_benefits(p_invoice_id)
   where blocking;
  if v_blocked is not null then
    raise exception 'These benefits have already been used and cannot move with the invoice: %. Resolve each one through the benefit transfer review before reassigning.', v_blocked
      using errcode='P0001'; end if;

  -- 417: the stock of a limited voucher moves with it to the new store, as
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
     set customer_id = p_customer_id, store_id = p_store_id
   where source_type in ('invoice_voucher_sale','invoice_promotion_voucher')
     and source_id in (select id from public.invoice_items where invoice_id = p_invoice_id)
     and status = 'held' and redeemed_at is null;
  get diagnostics v_v = row_count;

  v_wallet := public.ensure_customer_wallet(p_customer_id);
  for r_lot in
    select l.* from public.customer_credit_lots l
     where l.id in (select lot_id from public.invoice_credit_lot_ids(p_invoice_id))
       and l.remaining_amount = l.original_amount
       and l.remaining_amount > 0
       and l.status = 'active'
       -- Already the new owner's (a repeated request, or a no-op move).
       and l.customer_id is distinct from p_customer_id
     for update
  loop
    v_new_lot := gen_random_uuid();

    update public.customer_credit_lots
       set remaining_amount = 0, updated_at = now() where id = r_lot.id;
    insert into public.customer_credit_ledger
      (wallet_id, customer_id, entry_type, category, amount, lot_id,
       source_type, source_record_id, store_id, reason, created_by, approved_by)
    values (r_lot.wallet_id, r_lot.customer_id, 'adjust_decrease', r_lot.category,
            r_lot.remaining_amount, r_lot.id, 'invoice_reassignment_out', p_invoice_id,
            r_lot.store_id, p_reason, auth.uid(), auth.uid());

    insert into public.customer_credit_lots
    select (jsonb_populate_record(null::public.customer_credit_lots, to_jsonb(r_lot) || jsonb_build_object(
      'id', v_new_lot, 'wallet_id', v_wallet, 'customer_id', p_customer_id,
      'original_amount', r_lot.remaining_amount, 'remaining_amount', r_lot.remaining_amount,
      -- source_type, source_record_id, usage_restrictions, category, store_id,
      -- effective_date and original_purchase_date are carried unchanged.
      'reassigned_from_lot_id', r_lot.id,
      'reference_no', null, 'reason', p_reason, 'reversal_of_lot_id', null,
      'created_by', auth.uid(), 'approved_by', auth.uid(),
      'created_at', now(), 'updated_at', now()))).*;
    insert into public.customer_credit_ledger
      (wallet_id, customer_id, entry_type, category, amount, lot_id,
       source_type, source_record_id, store_id, reason, created_by, approved_by)
    values (v_wallet, p_customer_id, 'grant', r_lot.category, r_lot.remaining_amount,
            v_new_lot, 'invoice_reassignment_in', p_invoice_id, r_lot.store_id,
            p_reason, auth.uid(), auth.uid());

    -- 447 (the Owner, 22 Oct 2026): the invoice's own records follow the
    -- credit to the new customer's lot, as a merge's do (445): its benefit
    -- value (what a cancellation, a refund and its cap, a Move and the
    -- "credit spent" checks read), its sale's lots (what a refund's
    -- commission is traced back through) and a shared package's issued lot.
    -- So a cancellation takes the credit back from the new customer and the
    -- refund due can be recorded. Credit released before settlement is
    -- followed along as before (credit_package_progress_lots keeps its lot).
    -- A lot whose benefit value was moved on to someone else (Move: their
    -- credit is traced back through it) keeps all of these, as in a merge.
    if not exists (select 1 from public.invoice_benefit_values b
                     join public.invoice_benefit_transfers t on t.source_benefit_id = b.id
                    where b.lot_id = r_lot.id) then
      update public.invoice_benefit_values set lot_id = v_new_lot where lot_id = r_lot.id;
      update public.credit_package_sales set credit_lot_id = v_new_lot where credit_lot_id = r_lot.id;
      update public.credit_package_sales set bonus_credit_lot_id = v_new_lot where bonus_credit_lot_id = r_lot.id;
      update public.premium_bundle_sales set paid_credit_lot_id = v_new_lot where paid_credit_lot_id = r_lot.id;
      update public.premium_bundle_sales set bonus_credit_lot_id = v_new_lot where bonus_credit_lot_id = r_lot.id;
      update public.invoice_credit_splits set issued_lot_id = v_new_lot where issued_lot_id = r_lot.id;
    end if;

    v_c := v_c + 1;
  end loop;

  update public.therapy_entitlements
     set customer_id = p_customer_id, store_id = p_store_id
   where claim_source_invoice_id = p_invoice_id
     and status <> 'cancelled'
     and public.entitlement_claimed_qty(id) = 0;
  get diagnostics v_a = row_count;

  if v_v + v_c + v_a > 0 then
    perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_benefits_followed_reassignment',
      null, jsonb_build_object('vouchers', v_v, 'credit_lots', v_c, 'allowances', v_a,
                               'to_customer', p_customer_id, 'reason', p_reason),
      'invoices', p_reason, p_store_id);
  end if;

  return jsonb_build_object('vouchers', v_v, 'credit_lots', v_c, 'allowances', v_a);
end $function$
$def$;
  -- Who may call it: the server alone (as read; kept).
  c_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';
  -- The functions whose text calls it, as read: correct_invoice (321).
  c_callers constant text[] := array['correct_invoice(uuid,jsonb,jsonb,text,uuid)'];

  -- ── Relied on, not changed (production, 22 Oct 2026, after 445). None of
  -- 446's (refund_invoice_recorded, invoice_voucher_reopen_candidates,
  -- apply_reopened_invoice_vouchers) is here. ──────────────────────────────
  c_relied constant text[] := array[
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'invoice_credit_lot_ids(uuid)', 'invoice_transferable_benefits(uuid)',
    'credit_lot_chain(uuid)', 'credit_lot_current(uuid)', 'capture_invoice_benefit_values(uuid)',
    'cancel_invoice_recorded(uuid,text,uuid)', 'writeoff_released_credit_on_close(uuid,text,text)',
    'invoice_refund_options_before_sessions(uuid)', 'cancelled_invoice_used_value(uuid)', 'invoice_action_plan(uuid,text,jsonb)',
    'invoice_commission_benefit_source(uuid)', 'credit_purchase_refund_blockers(uuid)', 'customer_credit_balances(uuid)',
    'invoice_credit_transfer_origin(uuid)', 'merge_customer_records(uuid,uuid,text,uuid)',
    'transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)', 'trg_credit_lot_immutable()', 'ensure_customer_wallet(uuid)',
    'entitlement_claimed_qty(uuid)', 'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)', 'record_invoice_payment(uuid,jsonb,uuid)'];
  c_relied_md5 constant text[] := array[
    '422682d6e1ada0e5d98053e74ab9f007', '50346a2e9aea50b31d4207c43b2f197c', 'e3a4b753d87546a1a73342baf02bee70',
    '556e725784154cbffc23d3ad900f9366', 'd48fb24e6eb9733d7f867e42fa703e7b', 'd5e061945c2921a1af86f8c99a349e98',
    'de52d9dbaef8ab15163bef35cb9d733d', '284a89cfb965e8028136b5f8a4f2bf08',
    'bd3afcc79cd2f06f983607d54fed167c', '8caf1ea07bb021d91a5396b40fb7cda1', '3e5fe6ccd93548c13b6ed62800595838',
    'f8d3d29fae79065a252a8c5231cc2d4b', 'aa1afae71965fa31f8d0db616505edc8', 'c2287779ce0ec9c52eeec41952055f78',
    'e778a9e4ff81567a493b8ca479d8222b', '2e0c9852099ab88d8f27827b5f9a3846',
    '7aebd7120bc3928db46df0941cb20889', '0fc74da0dcc9b436dfd26c4582542f6c', '8ef18daebbbe3c12f2024290ea8416e8',
    '89b08265d5303e890569e953d83d2440', 'c705c733e213a27f0dc32d54322cc855',
    '80c80d386a5241e63b353e35e13ef250', '9c70097ed4da614fb9dcc66fdfcdb7d6'];

  -- ── Tables and columns, as read on 22 Oct 2026 (as 445 read them) ───────
  -- Every column that names a lot (a foreign key to customer_credit_lots):
  -- the five this repoints, and the ten that record what happened to a lot
  -- or are followed along (kept).
  c_lot_refs constant text :=
    'credit_package_progress_lots.lot_id, credit_package_progress_lots.replaces_lot_id, '
    'credit_package_sales.bonus_credit_lot_id, credit_package_sales.credit_lot_id, customer_credit_adjustments.lot_id, '
    'customer_credit_allocations.lot_id, customer_credit_ledger.lot_id, customer_credit_lots.reassigned_from_lot_id, '
    'customer_credit_lots.reversal_of_lot_id, invoice_benefit_values.lot_id, invoice_credit_splits.issued_lot_id, '
    'invoice_line_credit_allocations.lot_id, premium_bundle_sales.bonus_credit_lot_id, '
    'premium_bundle_sales.paid_credit_lot_id, special_credit_allocations.lot_id';
  c_lot_trigger constant text := 'CREATE TRIGGER credit_lot_immutable BEFORE DELETE OR UPDATE ON public.customer_credit_lots FOR EACH ROW EXECUTE FUNCTION trg_credit_lot_immutable()';
  -- The tables it repoints, and the one it reads for a Move: no trigger.
  c_plain constant text[] := array['invoice_benefit_values', 'credit_package_sales', 'premium_bundle_sales',
                                   'invoice_credit_splits', 'invoice_benefit_transfers'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; i int; v_acl text;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_pk uuid; t_a uuid; t_b uuid;
  t_inv uuid; t_item uuid; t_paid uuid; t_bonus uuid; t_ans jsonb; t_plan jsonb; t_lines jsonb;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The text is the tested one.
  if md5(c_def) <> c_after then
    raise exception '447: the text of public.% is not the tested one (md5 %)', c_sig, md5(c_def); end if;

  -- move_invoice_benefits_to_customer is its BEFORE or this file's AFTER; no
  -- other function takes its name.
  if to_regprocedure('public.' || c_sig) is null then
    raise exception '447: public.% is missing', c_sig; end if;
  d := md5(pg_get_functiondef(to_regprocedure('public.' || c_sig)));
  if d <> c_after and d <> c_before then
    raise exception '447: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', c_sig, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'move_invoice_benefits_to_customer'
     and p.oid::regprocedure::text <> c_sig;
  if v is not null then raise exception '447: another function takes the name move_invoice_benefits_to_customer: %', v; end if;

  -- The functions relied on are as read on production (22 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '447: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if to_regprocedure('auth.uid()') is null then raise exception '447: auth.uid() must be there'; end if;

  -- Only correct_invoice calls it, so its answer needs no other caller
  -- checked. (A session's own temporary functions, a test suite's helpers,
  -- are not counted.)
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'move_invoice_benefits_to_customer\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and not (p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = c_sig);
  if v is distinct from array_to_string(c_callers, ', ') then
    raise exception '447: the functions that call move_invoice_benefits_to_customer are not as read on 22 Oct 2026 (%); check each, then re-test', v; end if;

  -- The tables and columns, as read on 22 Oct 2026.
  select string_agg(c.relname || '.' || a.attname, ', ' order by c.relname || '.' || a.attname) into v
    from pg_constraint k
    join pg_class c on c.oid = k.conrelid
    join pg_attribute a on a.attrelid = k.conrelid and a.attnum = any (k.conkey)
   where k.contype = 'f' and k.confrelid = 'public.customer_credit_lots'::regclass;
  if v is distinct from c_lot_refs then
    raise exception '447: the columns that name a credit lot are not as read on 22 Oct 2026 (%); decide for each new one whether a customer change repoints it, then re-test', v; end if;
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('invoice_benefit_values', 'id', 'uuid'), ('invoice_benefit_values', 'lot_id', 'uuid'),
                 ('invoice_benefit_transfers', 'source_benefit_id', 'uuid'),
                 ('credit_package_sales', 'credit_lot_id', 'uuid'), ('credit_package_sales', 'bonus_credit_lot_id', 'uuid'),
                 ('premium_bundle_sales', 'paid_credit_lot_id', 'uuid'), ('premium_bundle_sales', 'bonus_credit_lot_id', 'uuid'),
                 ('invoice_credit_splits', 'issued_lot_id', 'uuid'),
                 ('customer_credit_lots', 'reassigned_from_lot_id', 'uuid'),
                 ('customer_credit_ledger', 'lot_id', 'uuid'), ('customer_credit_ledger', 'entry_type', 'text'),
                 ('customer_credit_ledger', 'source_type', 'text')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '447: these columns are missing or not as read on 22 Oct 2026: %', v; end if;
  if (select string_agg(pg_get_triggerdef(t.oid), ' | ') from pg_trigger t
       where t.tgrelid = 'public.customer_credit_lots'::regclass and not t.tgisinternal) is distinct from c_lot_trigger then
    raise exception '447: the triggers on customer_credit_lots are not as read on 22 Oct 2026'; end if;
  select string_agg(t.tgrelid::regclass::text || ' ' || t.tgname, ', ') into v
    from pg_trigger t
   where t.tgrelid in (select to_regclass('public.' || x) from unnest(c_plain) x) and not t.tgisinternal;
  if v is not null then raise exception '447: these tables have triggers they did not have on 22 Oct 2026: %', v; end if;

  -- No invoice record names a lot that a customer change emptied and
  -- replaced (its new lot's grant is 'invoice_reassignment_in'), other than a
  -- lot whose benefit value was moved on (kept there on purpose, 2. in the
  -- header). None did on 22 Oct 2026 (no lot had the link). One that does is
  -- the state this file prevents, already there: it needs its own repair
  -- decision, so nothing is changed.
  select count(*) into i
    from public.customer_credit_lots o
   where exists (select 1 from public.customer_credit_lots n
                   join public.customer_credit_ledger e on e.lot_id = n.id
                  where n.reassigned_from_lot_id = o.id
                    and e.entry_type = 'grant' and e.source_type = 'invoice_reassignment_in')
     and not exists (select 1 from public.invoice_benefit_values b
                       join public.invoice_benefit_transfers t on t.source_benefit_id = b.id
                      where b.lot_id = o.id)
     and (exists (select 1 from public.invoice_benefit_values b where b.lot_id = o.id)
          or exists (select 1 from public.credit_package_sales s where o.id in (s.credit_lot_id, s.bonus_credit_lot_id))
          or exists (select 1 from public.premium_bundle_sales s where o.id in (s.paid_credit_lot_id, s.bonus_credit_lot_id))
          or exists (select 1 from public.invoice_credit_splits s where s.issued_lot_id = o.id));
  if i > 0 then
    raise exception '447: % lot(s) emptied by a customer change are still named by their invoice''s records (benefit values, sale or split); none were on 22 Oct 2026. Decide how to repair each, then re-test', i; end if;

  -- Who may call it, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does.
  select coalesce(proacl::text, '') into v_acl from pg_proc where oid = to_regprocedure('public.' || c_sig);
  if (select array_agg(x::text order by x::text) from unnest(nullif(v_acl, '')::aclitem[]) x)
     is distinct from (select array_agg(x::text order by x::text) from unnest(c_acl::aclitem[]) x) then
    raise exception '447: who may call public.% is not as read on 22 Oct 2026 (%)', c_sig, v_acl; end if;

  -- ── Change ──────────────────────────────────────────────────────────────
  if d <> c_after then
    execute c_def;
  else
    raise notice '447: move_invoice_benefits_to_customer already this version; left alone';
  end if;

  -- ── Afterwards ──────────────────────────────────────────────────────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_after then
    raise exception '447: public.% was installed with an md5 other than the tested one', c_sig; end if;
  if (select coalesce(proacl::text, '') from pg_proc where oid = to_regprocedure('public.' || c_sig)) is distinct from v_acl
     or has_function_privilege('anon', to_regprocedure('public.' || c_sig), 'execute')
     or has_function_privilege('authenticated', to_regprocedure('public.' || c_sig), 'execute') then
    raise exception '447: the grants of public.% changed', c_sig; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("447 check", @example.invalid, fictional ACMA
  -- phones no customer uses); it ends by raising P0447, which undoes all it
  -- wrote. No therapy, stock or voucher is sold.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from unnest(array['+61491570890', '+61491570891', '+61491570892', '+61491570893',
                                                 '+61491570894', '+61491570895']) p
                       where not exists (select 1 from public.customers c where c.phone = p)
                       order by p limit 2);
    if cardinality(t_phones) < 2 then raise exception '447: the self-test found no two unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '447-check-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '447 check', '447-check-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('447 check ' || t_sfx, '447-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name) values ('447 check cash ' || t_sfx) returning id into t_cash;
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, bonus_value,
                                        allow_product, allow_therapy, allow_voucher, grants_reward)
    values ('447 check ' || t_sfx, 100, 100, true, 10, true, true, true, false) returning id into t_pk;
    insert into public.credit_package_stores (package_id, store_id) values (t_pk, t_store);
    insert into public.customers (full_name, phone) values ('447 Check First ' || t_sfx, t_phones[1]) returning id into t_a;
    insert into public.customers (full_name, phone) values ('447 Check Second ' || t_sfx, t_phones[2]) returning id into t_b;
    -- The first customer buys the package (Paid 100, Bonus 10), cash.
    t_inv := public.create_invoice(t_store, t_a, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)),
      gen_random_uuid());
    select s.credit_lot_id, s.bonus_credit_lot_id into t_paid, t_bonus from public.credit_package_sales s where s.invoice_id = t_inv;
    select it.id into t_item from public.invoice_items it where it.invoice_id = t_inv;
    if t_paid is null or t_bonus is null
       or (select count(*) from public.customer_credit_lots l where l.id in (t_paid, t_bonus) and l.customer_id = t_a) <> 2 then
      raise exception '447: the self-test''s package did not give its buyer two lots'; end if;
    -- The invoice form's customer change, the benefits taken along.
    t_ans := public.correct_invoice(t_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', t_item, 'kind', 'credit_package', 'credit_package_id', t_pk,
                                           'quantity', 1, 'unit_price', 100)),
      jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = t_inv),
                         'customer_id', t_b, 'benefit_action', 'transfer'),
      '447 check', gen_random_uuid());
    if (select customer_id from public.invoices where id = t_inv) is distinct from t_b
       or (select count(*) from public.customer_credit_lots l
            where l.customer_id = t_b and l.reassigned_from_lot_id in (t_paid, t_bonus)
              and l.remaining_amount = l.original_amount and l.remaining_amount > 0) <> 2 then
      raise exception '447: the self-test''s customer change did not move the credit as tested: %', t_ans; end if;
    -- The invoice's records name the second customer's lots.
    if (select (s.credit_lot_id, s.bonus_credit_lot_id) from public.credit_package_sales s where s.invoice_id = t_inv)
       is distinct from (select (p.id, b.id) from public.customer_credit_lots p, public.customer_credit_lots b
                          where p.reassigned_from_lot_id = t_paid and b.reassigned_from_lot_id = t_bonus)
       or exists (select 1 from public.invoice_benefit_values b
                    left join public.customer_credit_lots l on l.id = b.lot_id
                   where b.invoice_id = t_inv and l.customer_id is distinct from t_b)
       or (select count(*) from public.invoice_benefit_values b where b.invoice_id = t_inv) <> 2 then
      raise exception '447: the self-test''s sale or benefit values do not name the second customer''s lots'; end if;
    if (select count(*) from jsonb_array_elements(public.invoice_refund_options_before_sessions(t_inv) -> 'benefits') x
         where x ->> 'customer_id' = t_b::text and (x ->> 'max_refund')::numeric = (x ->> 'paid_value')::numeric
           and (x ->> 'max_refund')::numeric > 0) <> 2 then
      raise exception '447: the self-test''s refund options do not read the second customer''s lots: %',
        public.invoice_refund_options_before_sessions(t_inv) -> 'benefits'; end if;
    t_plan := public.invoice_action_plan(t_inv, 'refund_full', '[]'::jsonb);
    if exists (select 1 from jsonb_array_elements(coalesce(t_plan -> 'overrides_required', '[]'::jsonb)) o
                where o ->> 'code' = 'credit_used') then
      raise exception '447: the self-test''s Refund in full still asks credit_used: %', t_plan -> 'overrides_required'; end if;
    -- Cancelled: the credit comes back from the second customer, nothing
    -- reads as used, and the refund due is recorded through the line's
    -- benefits, as the Finance panel's line-by-line refund sends it.
    perform public.cancel_invoice_recorded(t_inv, '447 check', gen_random_uuid());
    if exists (select 1 from public.customer_credit_lots l where l.customer_id in (t_a, t_b) and l.remaining_amount <> 0)
       or cardinality(public.cancelled_invoice_used_value(t_inv)) <> 0
       or (public.invoice_financial_position(t_inv) ->> 'refund_due')::numeric <> 100 then
      raise exception '447: the self-test''s cancellation did not take the credit back from the second customer: %',
        public.invoice_financial_position(t_inv); end if;
    t_plan := public.invoice_action_plan(t_inv, 'cancel', '[]'::jsonb);
    select jsonb_agg(jsonb_build_object('invoice_item_id', l ->> 'invoice_item_id', 'amount', (l ->> 'amount')::numeric,
             'benefits', (select jsonb_agg(jsonb_build_object('benefit_id', b ->> 'benefit_id', 'amount', (b ->> 'amount')::numeric))
                            from jsonb_array_elements(l -> 'benefits') b)))
      into t_lines from jsonb_array_elements(t_plan -> 'lines') l where (l ->> 'amount')::numeric > 0;
    perform public.refund_invoice_recorded(t_inv, t_lines,
      jsonb_build_array(jsonb_build_object('payment_id',
        (select p.id from public.invoice_payments p where p.invoice_id = t_inv and p.entry_kind = 'receipt' order by p.created_at limit 1),
        'amount', 100)), '[]'::jsonb, '447 check', gen_random_uuid());
    if (public.invoice_financial_position(t_inv) ->> 'refund_due')::numeric <> 0 then
      raise exception '447: the self-test''s refund due was not recorded: %', public.invoice_financial_position(t_inv); end if;
    raise exception using errcode = 'P0447', message = '447: self-test done, undone';
  exception when sqlstate 'P0447' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
