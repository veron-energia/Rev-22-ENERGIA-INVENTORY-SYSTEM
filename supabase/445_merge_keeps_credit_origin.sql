-- 445_merge_keeps_credit_origin.sql
--
-- CREDIT CARRIED OVER IN A CUSTOMER MERGE STAYS THE CREDIT IT WAS: ITS
-- PACKAGE OR BUNDLE, ITS RULES, AND ITS PURCHASE (the Owner, 21 Oct 2026,
-- CREDIT-SPLIT-14)
--
-- WHAT WAS WRONG
--
--   * merge_customer_records (318; last 425, md5 099ecf3a) carries the
--     duplicate's credit over by drawing each of its lots down to nothing and
--     granting the kept customer a new lot (a posted lot cannot change
--     customer: trg_credit_lot_immutable, 77). The new lot was written with
--     source_type 'customer_merge' and source_record_id = the duplicate's id,
--     in place of the lot's own source (the Credit Package or Premium Bundle,
--     an opening balance, Adjust, Move ...). So:
--       - credit_lot_policy (242/250) does not know 'customer_merge' and says
--         'needs_review': the kept customer could not spend it at all, with
--         any wallet method;
--       - 443's credit_lot_source_group put it under 'Other', so the customer
--         page, Record Payment and the printed balance showed Credit Package
--         and Premium Bundle credit as Other;
--       - nothing linked the new lot to the lot it replaced, so what follows a
--         purchase's credit from its sale and its invoice lines
--         (invoice_credit_lot_ids, credit_lot_chain / credit_lot_current, the
--         balances' list of purchases) lost it;
--       - and the purchase records still named the duplicate's emptied lot:
--         the invoice's benefit values (invoice_benefit_values.lot_id) and the
--         sale (credit_package_sales.credit_lot_id / bonus_credit_lot_id,
--         premium_bundle_sales.paid_credit_lot_id / bonus_credit_lot_id). A
--         refund of the invoice that sold the credit found nothing left
--         ("There is nothing left to refund on this invoice"; the plan asked
--         for a "credit spent" override), and a cancellation took nothing
--         back: the kept customer kept all of it (checked on a copy of
--         production with made-up records, 21 Oct 2026: S$1,100 kept after a
--         cancelled S$1,000 package; with this file, the same refund returns
--         the S$1,000 and takes the S$1,100 back from the kept customer). It
--         could not be spent, so no money moved; with the source put right
--         alone, it could have been.
--   * Found in review (21 Oct 2026), once the new lot carries that link (1.
--     below): a Move of it (transfer_invoice_unused_benefit, 186; the
--     Finance panel's Move) builds the recipient's lot as a copy of the
--     moved lot's row and clears only reversal_of_lot_id, so the
--     recipient's lot claimed the link too. For credit released before
--     settlement (named by credit_package_progress_lots), credit_lot_chain
--     and credit_lot_current follow the newest lot with the link, so they
--     went to the recipient's lot and skipped the kept customer's:
--     invoice_credit_lot_ids counted the recipient's credit as the
--     invoice's, and invoice_commission_benefit_source found no sale for the
--     released credit or the moved credit ("Commission review required
--     ..."). A refund of the moved credit was refused, and the invoice
--     reassigned with its credit (321) took the recipient's credit to its new
--     customer (on a copy: the recipient's S$300 gone). The same already
--     happens without a merge, when a part-paid invoice reassigned with its
--     credit (321) is settled, its released credit moved, and the invoice
--     reassigned again (checked on a copy of production as it is).
--   * Production, 21 Oct 2026: no 'customer_merge' lot exists (0), no lot has
--     been moved (0 'invoice_benefit_transfer' lots) and no lot has the link
--     (0 reassigned_from_lot_id). This is preventive; there is nothing to
--     repair.
--
-- THE OWNER'S ANSWER (21 Oct 2026, CREDIT-SPLIT-14)
--
--   Merged credit keeps its Package or Bundle origin and stays spendable: put
--   right as its own small change, once 441 is live (441 is live).
--   The Move part (3. below) was found in review the same day. It is put
--   right here so that merged credit stays ordinary credit when it is moved
--   on; it also puts right the same thing for credit an invoice
--   reassignment carried. It was not asked of the Owner separately: told to
--   the Owner with this file.
--
-- WHAT THIS DOES (merge_customer_records(uuid,uuid,text,uuid) and
-- transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid))
--
--   In merge_customer_records only the credit step changes. For each of the
--   duplicate's live lots with credit left, as before: the lot is drawn down
--   to 0 (ledger 'customer_merge_out') and the kept customer is granted the
--   same amount (ledger 'customer_merge_in'), as a new lot of their own. Now:
--   1. The new lot keeps the duplicate's lot's source_type and
--      source_record_id (with its category, usage_restrictions, store,
--      effective_date and original_purchase_date, as before), and its
--      reassigned_from_lot_id names the lot it replaces: what an invoice
--      reassignment's new lot does (321). So the spending rules, the source
--      groups and every wallet method per source (443), and what follows a
--      lot along (invoice_credit_lot_ids, credit_lot_chain / credit_lot_current
--      for credit released before settlement, 356; the balances' purchases)
--      read it as they read the original. Credit moved from another
--      customer's invoice (Move, 186) stays moved credit, traced to its origin
--      through its transfer.
--   2. The records that name the lot holding a purchase's credit then name
--      the kept customer's new lot: the invoice's benefit value
--      (invoice_benefit_values.lot_id: what a refund, a cancellation, a Move
--      and the "credit spent" checks read), the sale's lots
--      (credit_package_sales.credit_lot_id / bonus_credit_lot_id,
--      premium_bundle_sales.paid_credit_lot_id / bonus_credit_lot_id: what a
--      refund's commission is traced back through, 356) and a shared
--      package's issued lot (invoice_credit_splits.issued_lot_id). So a refund
--      or cancellation of the invoice that sold the credit takes it back from
--      the kept customer, as it would have from the duplicate. A lot whose
--      benefit value was moved on to someone else (Move, 186: their credit is
--      traced back through it) keeps all of these on the duplicate's lot, as
--      before (rare: a Move takes all of the lot's credit, so such a lot has
--      credit left only if some was put back on it later, by a refund or
--      correction of a payment it paid, which a merge refuses, or by a
--      reopened invoice's reinstated credit).
--   merge_customer_records' signature, grants (the server's alone), its
--   answer ('success', 'kept', 'retired', 'moved'; a replay's), its audit row
--   ('customers_merged') and everything else it does are as they were, byte
--   for byte: the checks, the locks, the referrals, the affiliate record, the
--   catalogue loop of every other column naming a customer, the retired
--   record.
--   3. Move (transfer_invoice_unused_benefit): the recipient's new lot no
--      longer copies the moved lot's reassigned_from_lot_id (null, as its
--      reversal_of_lot_id already was). Moved credit is traced through its
--      transfer (invoice_credit_transfer_origin), as every Move's is, and
--      the lot it came from stays the one credit_lot_chain,
--      credit_lot_current and invoice_credit_lot_ids follow. A Move of a lot
--      without the link (every Move so far) writes exactly what it wrote
--      before. Nothing else in it changes: its signature, checks, answer,
--      transfer record, ledger rows, benefit value, audit row and grants
--      (signed-in staff, as 339 left it; it lets only an Owner or Manager
--      through).
--
-- NOT CHANGED
--
--   * No lot, ledger row, allocation, sale, benefit value or invoice: no
--     merged credit exists (0 'customer_merge' lots), and no lot a Move
--     granted has the link 3. stops copying (0; checked before anything
--     changes).
--   * The ledger rows a merge writes ('customer_merge_out' / '_in', their
--     amounts, reasons and sources), so the statement reads as before.
--   * credit_package_progress_lots (credit released before settlement) keeps
--     naming the lot it released: it is followed along by credit_lot_current
--     (356), which now finds the new lot (and, with 3., never a Move's lot).
--     invoice_line_credit_allocations, customer_credit_allocations,
--     customer_credit_adjustments and special_credit_allocations record what
--     happened to a lot and keep naming it.
--   * Its callers: link_affiliate_signup (437) merges through it and gets the
--     same answer; 441's event_web_* read the 'customers_merged' rows, which
--     are unchanged. invoice reassignment (321), refunds and cancellations
--     are not changed; Move (186) only as in 3.
--
-- NOT COVERED (told to the Owner)
--
--   * A duplicate who has ever spent wallet credit still cannot be merged:
--     the catalogue loop tries to move customer_credit_allocations, which no
--     one may change (trg_credit_alloc_immutable, 77), and the merge stops
--     with "Credit allocations cannot be changed once recorded", changing
--     nothing (as since 318). Letting it through needs more than this: a
--     refund or correction of a payment the duplicate made would then give
--     the credit back to the duplicate's emptied lot, on the retired record,
--     where the kept customer cannot see it. Left for its own change.
--   * Credit put back later on one of the duplicate's lots (a reopened
--     invoice's reinstated credit, 362/417) goes to that lot, on the retired
--     record. Same reason.
--   * A lot whose benefit value was moved on (2. above, rare): what it had
--     left goes to the kept customer as the same credit, but its records stay
--     on the duplicate's lot (so the moved credit stays traced), and a refund
--     or cancellation of its invoice does not reach the kept customer's part.
--     As before this file.
--   * The new lot is granted what was left (original = remaining, as 321 and
--     186 grant it). A lot partly taken back before the merge (a part refund
--     of its purchase, credit trimmed) therefore reads as unused at the kept
--     customer: an invoice reassignment (321) would let its remaining credit
--     go with the invoice instead of stopping as "partly spent", and a moved
--     lot (Move) partly taken back no longer matches its transfer
--     (invoice_credit_transfer_origin) and is held for review. Refunds and
--     cancellations still take back the right amount (they reckon from the
--     benefit value's grant).
--   * Lots already 'customer_merge' (none on production) keep that source.
--   * Seen while checking, not changed here: an invoice reassigned with its
--     credit (321's move_invoice_benefits_to_customer) leaves its benefit
--     values and sale on the emptied lots, so a refund or cancellation of it
--     afterwards takes nothing back from the new holder (on a copy: S$1,100
--     kept after cancelling).
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the two texts built are the tested ones (their AFTER md5s);
--   * merge_customer_records is its BEFORE (production, 21 Oct 2026, after
--     441 and 443: 425's AFTER) or this file's AFTER (left alone); no other
--     function takes its name; only link_affiliate_signup calls it;
--   * transfer_invoice_unused_benefit is its BEFORE (production, 21 Oct
--     2026: 191's text) or this file's AFTER (left alone); no other function
--     takes its name, and no function calls it (the Finance panel calls it
--     through the API);
--   * the functions the merge calls and the ones that read what either
--     writes, relied on and not changed, are as read on production (21 Oct
--     2026), below; auth.uid() is there. (What Move itself calls, the store
--     access, credit evidence and audit helpers, is not pinned: 3. changes
--     one column of the lot it writes, which none of them reads; the
--     self-test goes through them);
--   * customer_credit_lots' columns (the new lot is the old one's row with
--     some columns set) and the columns it repoints are as read; the columns
--     that name a lot are the fifteen read (a new one would need a decision:
--     repointed or kept); customer_credit_lots has its one trigger as read,
--     and the four tables it repoints have none;
--   * no lot a Move granted (its ledger grant 'invoice_benefit_transfer_in')
--     has the link (0 as read on production; one would need its own
--     decision, so the file stops; a merged lot of moved credit has the
--     link rightly, and its grant is 'customer_merge_in');
--   * who may call each is as read (merge_customer_records: the server alone;
--     transfer_invoice_unused_benefit: signed-in staff and the server), and
--     is kept.
--   Afterwards: the md5s are the AFTER ones; the grants are as before. Then a
--   self-test, in a block that is always undone (it ends by raising P0445, so
--   it leaves no row): a made-up Owner, store, Credit Package and three
--   customers (fictional phones no customer has); one buys the package (cash)
--   and is merged into another; the kept customer's two new lots keep the
--   package, its rules, its group and the link; the sale, the benefit values
--   and the refund options name the kept customer's lots; then the kept
--   customer's Paid credit is moved to the third (Move): the third's lot has
--   no link, the package's Paid credit is still followed to the kept
--   customer's lot, not the third's, and the moved credit's sale is found.
--   Its invoice number is counted, not drawn from a sequence; its eight
--   credit ledger rows draw eight entry numbers (a sequence, which an undone
--   transaction does not give back: a gap, which nothing counts). Each run, a
--   dry run or a second run too, leaves these gaps. A second run changes
--   nothing else.
--   Locks: the two functions' catalogue rows, held to the end of the apply;
--   the rows the self-test writes and undoes. A merge or a Move running at
--   that moment finishes on the text it started with.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (... 441, 443, 444) -> 445. No page, Edge Function or
--   setting changes.
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below, the second changes
--      nothing ("left alone").
--   2. Apply (the CLI, or the MCP's apply_migration with this text verbatim).
--      It checks itself.
--   Afterwards the re-runs of 434 and 438 (they pin
--   transfer_invoice_unused_benefit at ea7e8ce0) and of 441 (it pins
--   merge_customer_records at 099ecf3a) refuse, where today they leave all
--   alone; those of 425, 436, 437, 439 and 440 refuse already (425, 436,
--   437 and 439 pin merge_customer_records too); 443's still leaves all
--   alone (checked on a copy, 22 Oct 2026). All are applied, so nothing is
--   lost.
--   444 (the event website's unpaid checkout, another session) changes and
--   pins none of the functions here, and this file none of its: either
--   order. 444 went live on 21 Oct 2026 at 16:14 UTC (20261021161439, file
--   md5 ed9c0c693d9ac265fbe2ea983bfec89f; production fingerprint 5fd44560),
--   so production is at 444 when this goes in; on a copy, 444 then 445 and
--   445 then 444 both end at the fingerprint below.
--
-- BEFORE (production, 21 Oct 2026, after 441 and 443; md5 of
-- pg_get_functiondef with search_path public)
--   changed
--   merge_customer_records(uuid,uuid,text,uuid)                    099ecf3aae30b5faaf8fb36bc15ce888  (425's AFTER)
--   transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)      ea7e8ce0612752c75ba75748c9275c42  (191's text)
--   relied on, not changed
--   preview_customer_merge(uuid,uuid)                              f66c9d63369ef3b831ca74906a99b587
--   ensure_customer_wallet(uuid)                                   8ef18daebbbe3c12f2024290ea8416e8
--   is_owner_or_manager()                                          a98e50f1b6d3fa1e6c62cf52a8073cc8
--   reassign_customer_referrer(uuid,uuid,text)                     9b32f3bef5b4f17897aae637e343c208
--   write_audit(text,uuid,text,jsonb,jsonb)                        b194f839993670c5b5dd28e934c2a829
--   link_affiliate_signup(uuid,uuid,text,uuid,boolean)             198780b31301695db55c4a39ba9618f8  (its one caller)
--   trg_credit_lot_immutable()                                     0fc74da0dcc9b436dfd26c4582542f6c
--   credit_lot_policy(text,text,boolean)                           d9a97af64871c4ebcff8d1f6c15f68a6
--   credit_lot_policy_for(uuid)                                    ccdd506e78c7cdca97194fde87cdcc42
--   invoice_credit_transfer_origin(uuid)                           e778a9e4ff81567a493b8ca479d8222b
--   credit_lot_source_group(uuid)                                  6b902cb426210eb10ee9a15344ff100b
--   credit_lot_chain(uuid)                                         556e725784154cbffc23d3ad900f9366
--   credit_lot_current(uuid)                                       d48fb24e6eb9733d7f867e42fa703e7b
--   invoice_credit_lot_ids(uuid)                                   50346a2e9aea50b31d4207c43b2f197c
--   customer_credit_balances(uuid)                                 c2287779ce0ec9c52eeec41952055f78
--   invoice_refund_options_before_sessions(uuid)                   bd3afcc79cd2f06f983607d54fed167c
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)      e6f6c3cbf1bda3574d748bde2db5a759
--   cancel_invoice_recorded(uuid,text,uuid)                        de52d9dbaef8ab15163bef35cb9d733d
--   writeoff_released_credit_on_close(uuid,text,text)              284a89cfb965e8028136b5f8a4f2bf08
--   invoice_commission_benefit_source(uuid)                        f8d3d29fae79065a252a8c5231cc2d4b
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)         2c01c460d3af8edd3ad86332aa286ed8  (reads a Move's lot, through invoice_credit_lot_ids)
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)   80c80d386a5241e63b353e35e13ef250  (the self-test)
--   record_invoice_payment(uuid,jsonb,uuid)                        9c70097ed4da614fb9dcc66fdfcdb7d6  (the self-test; 443's AFTER)
--   public function fingerprint, after 441 and 443                 d8bfc0b83af95d114f2d9f8f2489d3e0 (1370 functions)
--   public function fingerprint, production now (444 in too)      5fd445602b9c202c178e808ce6263098 (1370 functions)
-- AFTER (for later guards)
--   merge_customer_records(uuid,uuid,text,uuid)                    2e0c9852099ab88d8f27827b5f9a3846
--   transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)      7aebd7120bc3928db46df0941cb20889
--   public function fingerprint, worked out on a copy of production (22 Oct 2026):
--     after 441 and 443 -> 445 (a second run the same)           c5f5ee43da3e470ef04a4335896fd4c2 (1370 functions: none new, none dropped)
--     after 441 and 443 -> 444 alone (444 md5 ed9c0c69: its AFTER) 5fd445602b9c202c178e808ce6263098 (1370 functions)
--     production now (444 in) -> 445; 445 then 444 the same        83a90dbfc238c7f6048c8dc9e435d876 (1370 functions)
--
-- Test: scripts/customer-merge/tests/merge-credit-origin-445.sql (begin ...
-- rollback; it installs this file twice; -v nomig=1 where it is in). The
-- record merged away holds Credit Package Paid (partly taken back by a part
-- refund) and Bonus, Premium Bundle Paid and Bonus, a Legacy lot linked to
-- its bundle line and Paid credit released by a part-paid package (both
-- through credit_package_progress_lots), credit moved to it from another
-- customer's package (Move), opening balances and Adjust credit, and a
-- bundle whose Bonus was moved on. It merges the same records with 425's
-- text first (undone) and compares the answer, the audit rows and every
-- other record the merge touches; then checks each new lot's origin, rule
-- and group, the balances (nothing counted twice), the sale and benefit
-- records, the guided refund and cancellation plans (as before the merge,
-- with the kept customer as holder), Record Payment's methods paying each
-- kind, a refund of a payment made after the merge, a full refund and a
-- cancellation of the duplicate's invoices, and its part-paid package
-- settled by the kept customer. Then another duplicate's part-paid package:
-- merged, settled by the kept customer, its released credit moved to a
-- third customer (Move), then part of that refunded, and (instead) the
-- invoice reassigned with its credit: the third's lot has no link, the
-- chain stays on the kept customer's lot, the refund goes through, and the
-- third customer keeps their credit. With Move's old text (191's), the same
-- steps give the third's lot the link, so two lots claim the duplicate's
-- (the chain takes the newer; when it is the third's, the refund is
-- refused), the third's credit counts as the invoice's, and the
-- reassignment takes it. A duplicate who has spent wallet credit still
-- cannot be merged (NOT COVERED), by either text.
-- scripts/customer-merge/tests/merge-duplicates.sql finds the kept
-- customer's new lot by its link (reassigned_from_lot_id) as well as by
-- 'customer_merge', so it passes before and after this file.

set lock_timeout = '5s';

do $mig$
declare
  -- ── The function this changes: signature, BEFORE md5 (production, 21 Oct
  -- 2026: 425's AFTER), AFTER md5, and the text (as pg_get_functiondef gives
  -- it back with search_path public). ───────────────────────────────────────
  c_sig constant text := 'merge_customer_records(uuid,uuid,text,uuid)';
  c_before constant text := '099ecf3aae30b5faaf8fb36bc15ce888';
  c_after constant text := '2e0c9852099ab88d8f27827b5f9a3846';
  c_def constant text :=
$def$CREATE OR REPLACE FUNCTION public.merge_customer_records(p_keep uuid, p_merge uuid, p_reason text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_preview jsonb; k public.customers%rowtype; m public.customers%rowtype;
        r record; r_lot public.customer_credit_lots%rowtype; v_new_lot uuid;
        v_moved jsonb := '{}'::jsonb; n bigint; v_keep_wallet uuid;
        v_sql text;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can merge customer records' using errcode='42501'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then
    raise exception 'Give a reason; it is kept with the merge'; end if;
  if p_request_id is null then raise exception 'A request id is required'; end if;

  -- A retry returns the original outcome instead of merging a second time.
  if exists (select 1 from public.audit_logs
              where action = 'customers_merged'
                and record_id = p_keep
                and new_data->>'request_id' = p_request_id::text) then
    return jsonb_build_object('success', true, 'replayed', true,
      'detail','This merge was already applied.'); end if;

  -- Lock both, keeper first, so two merges cannot interleave.
  select * into k from public.customers where id = least(p_keep,p_merge) for update;
  select * into m from public.customers where id = greatest(p_keep,p_merge) for update;
  select * into k from public.customers where id = p_keep;
  select * into m from public.customers where id = p_merge;

  v_preview := public.preview_customer_merge(p_keep, p_merge);
  if not (v_preview->>'can_merge')::boolean then
    raise exception 'This merge needs review first: %',
      (select string_agg(x->>'detail',' ') from jsonb_array_elements(v_preview->'blocking') x); end if;

  -- ---- credit: drawn down and reissued, never repointed -------------------
  --
  -- A posted lot is immutable -- customer, category, original amount, source
  -- and store cannot be edited -- and the ledger behind it is append-only. So
  -- the surviving record is granted a replacement carrying the same category,
  -- restrictions and dates, and the duplicate's lot is drawn down to nothing,
  -- with both movements written to the ledger. The balance is carried; it is
  -- never recreated, and bonus credit cannot become paid credit on the way.
  --
  -- The duplicate's wallet and its ledger entries stay as they are. Those
  -- entries record that, at the time, this credit moved under that record, and
  -- that remains true; the retired customer row keeps them resolvable.
  --
  -- 445 (the Owner, 21 Oct 2026, CREDIT-SPLIT-14): the replacement is the same
  -- credit, as an invoice reassignment's is (321). It keeps the duplicate's
  -- lot's source_type and source_record_id, with its category, restrictions,
  -- store and dates, so the spending rules (credit_lot_policy), the source
  -- groups (443) and the balances read it as they read the original; and
  -- reassigned_from_lot_id names the lot it replaces, so what follows a lot
  -- along (invoice_credit_lot_ids, credit_lot_chain and credit_lot_current,
  -- the source groups, the balances) finds it. (Before, it was 'customer_merge'
  -- credit: held for review, Other, and cut off from its purchase.)
  -- The records that name the lot holding a purchase's credit then name the
  -- kept customer's: the invoice's benefit value (what a refund, a
  -- cancellation, a Move and the "credit spent" checks read), the package's or
  -- bundle's sale (what a refund's commission is traced back through) and a
  -- shared package's issued lot. So a refund or a cancellation of the invoice
  -- that sold it takes it back from the kept customer, as if it had always
  -- been theirs. A lot whose benefit value was moved on to someone (a Move,
  -- 186: their credit is traced back through it) keeps all of these, as
  -- before.
  v_keep_wallet := public.ensure_customer_wallet(p_keep);
  for r_lot in
    select l.* from public.customer_credit_lots l
     where l.customer_id = p_merge and l.status = 'active' and l.remaining_amount > 0
     for update
  loop
    v_new_lot := gen_random_uuid();
    update public.customer_credit_lots
       set remaining_amount = 0, updated_at = now() where id = r_lot.id;
    insert into public.customer_credit_ledger
      (wallet_id, customer_id, entry_type, category, amount, lot_id,
       source_type, source_record_id, store_id, reason, created_by, approved_by)
    values (r_lot.wallet_id, r_lot.customer_id, 'adjust_decrease', r_lot.category,
            r_lot.remaining_amount, r_lot.id, 'customer_merge_out', p_keep,
            r_lot.store_id, p_reason, auth.uid(), auth.uid());

    insert into public.customer_credit_lots
    select (jsonb_populate_record(null::public.customer_credit_lots, to_jsonb(r_lot) || jsonb_build_object(
      'id', v_new_lot, 'wallet_id', v_keep_wallet, 'customer_id', p_keep,
      'original_amount', r_lot.remaining_amount, 'remaining_amount', r_lot.remaining_amount,
      'reassigned_from_lot_id', r_lot.id,
      'reference_no', null, 'reason', p_reason, 'reversal_of_lot_id', null,
      'created_by', auth.uid(), 'approved_by', auth.uid(),
      'created_at', now(), 'updated_at', now()))).*;
    insert into public.customer_credit_ledger
      (wallet_id, customer_id, entry_type, category, amount, lot_id,
       source_type, source_record_id, store_id, reason, created_by, approved_by)
    values (v_keep_wallet, p_keep, 'grant', r_lot.category, r_lot.remaining_amount,
            v_new_lot, 'customer_merge_in', p_merge, r_lot.store_id,
            p_reason, auth.uid(), auth.uid());
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
  end loop;

  -- ---- referrals go through the path that owns them -----------------------
  --
  -- customers.referred_by is protected by enforce_referral_ownership and by a
  -- no-self-referral trigger, and reassign_customer_referrer is what may change
  -- it: it locks the row, walks the chain for cycles and records the reason.
  -- Repointing it directly would be going round all of that.
  if k.referred_by = p_merge then
    perform public.reassign_customer_referrer(p_keep, null,
      'Merged duplicate ' || p_merge::text || ': ' || trim(p_reason));
  end if;
  -- 398: the duplicate's friends are the same referrals, made when they
  -- were made: each keeps their referral date (tg_customers_referral_date).
  perform set_config('energia.keep_referral_date', '1', true);
  for r in select id from public.customers
            where referred_by = p_merge and id <> p_keep and deleted_at is null
  loop
    perform public.reassign_customer_referrer(r.id, p_keep,
      'Referrer merged from duplicate ' || p_merge::text || ': ' || trim(p_reason));
  end loop;
  perform set_config('energia.keep_referral_date', '0', true);

  -- ---- affiliate record, when only the duplicate has one ------------------
  update public.customer_affiliates set customer_id = p_keep
   where customer_id = p_merge
     and not exists (select 1 from public.customer_affiliates where customer_id = p_keep);

  -- ---- everything else, from the catalogue --------------------------------
  for r in
    select c.relname as tbl, a.attname as col
      from pg_constraint kk
      join pg_class c on c.oid = kk.conrelid and c.relkind = 'r'
      join pg_attribute a on a.attrelid = kk.conrelid and a.attnum = any(kk.conkey)
      join pg_class f on f.oid = kk.confrelid
      join pg_namespace ns on ns.oid = c.relnamespace
     where kk.contype = 'f' and f.relname = 'customers' and ns.nspname = 'public'
       -- Handled above, or deliberately not moved:
       and not (c.relname = 'customer_credit_wallets')            -- UNIQUE per customer
       and not (c.relname = 'customer_credit_ledger')             -- append-only by design
       and not (c.relname = 'customer_credit_lots')               -- immutable; reissued above
       and not (c.relname = 'customers' and a.attname = 'referred_by') -- reassigned above
       and not (c.relname = 'customer_affiliates' and a.attname = 'customer_id')
       -- 362: a phone-review capture describes its own record's phone (one row
       -- per customer); it stays with the retired record.
       and not (c.relname = 'customer_phone_migration_map')
       -- 425: a referral sign-up check stays with the sign-up it was made for.
       -- The retired record keeps it, so it no longer counts or waits; the kept
       -- customer keeps their own check, or none (one check per customer).
       and not (c.relname = 'referral_signup_checks' and a.attname = 'customer_id')
     order by c.relname, a.attname
  loop
    v_sql := format('update public.%I set %I = $1 where %I = $2', r.tbl, r.col, r.col);
    execute v_sql using p_keep, p_merge;
    get diagnostics n = row_count;
    if n > 0 then
      v_moved := v_moved || jsonb_build_object(r.tbl || '.' || r.col, n);
    end if;
  end loop;

  -- The duplicate is retired, not destroyed: it is the evidence that those
  -- older records were always this person.
  update public.customers
     set deleted_at = now(),
         notes = coalesce(notes || E'\n', '') ||
                 'Merged into ' || coalesce(k.full_name, p_keep::text) ||
                 ' (' || p_keep::text || ') — ' || trim(p_reason)
   where id = p_merge;

  perform public.write_audit('customers', p_keep, 'customers_merged',
    jsonb_build_object('kept', to_jsonb(k), 'merged', to_jsonb(m)),
    jsonb_build_object('merged_from', p_merge, 'moved', v_moved,
                       'reason', trim(p_reason), 'request_id', p_request_id));

  return jsonb_build_object('success', true, 'kept', p_keep, 'retired', p_merge,
    'moved', v_moved);
end $function$
$def$;
  -- Who may call it: the server alone (as read; kept).
  c_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';
  -- The functions whose text calls it, as read: link_affiliate_signup (437).
  c_callers constant text[] := array['link_affiliate_signup(uuid,uuid,text,uuid,boolean)'];

  -- ── The second function this changes (3. in the header): Move. Signature,
  -- BEFORE md5 (production, 21 Oct 2026: 191's text), AFTER md5, and the
  -- text (as pg_get_functiondef gives it back with search_path public). ────
  c_move_sig constant text := 'transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)';
  c_move_before constant text := 'ea7e8ce0612752c75ba75748c9275c42';
  c_move_after constant text := '7aebd7120bc3928db46df0941cb20889';
  c_move_def constant text :=
$mdef$CREATE OR REPLACE FUNCTION public.transfer_invoice_unused_benefit(p_benefit_id uuid, p_customer_id uuid, p_store_id uuid, p_reason text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b public.invoice_benefit_values%rowtype; i public.invoices%rowtype;
 l public.customer_credit_lots%rowtype; v public.customer_reward_vouchers%rowtype;
 t public.invoice_benefit_transfers%rowtype; moved numeric; wallet uuid; replacement uuid;
 new_benefit uuid; transfer_id uuid:=gen_random_uuid(); h text; old_snapshot jsonb; new_snapshot jsonb;
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can correct benefit recipients'; end if;
 if nullif(trim(p_reason),'') is null or p_request_id is null then raise exception 'A reason and request ID are required'; end if;
 select * into b from public.invoice_benefit_values where id=p_benefit_id;
 select * into i from public.invoices where id=b.invoice_id for update;
 if not found or i.deleted_at is not null or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 if not public.user_has_store_access(p_store_id) then raise exception 'No access to the destination store'; end if;
 h:=md5(jsonb_build_object('benefit',p_benefit_id,'customer',p_customer_id,'store',p_store_id,'reason',p_reason)::text);
 select * into t from public.invoice_benefit_transfers where invoice_id=i.id and request_id=p_request_id;
 if found then
  if t.request_hash<>h then raise exception 'This transfer request ID was already used for different details'; end if;
  return jsonb_build_object('success',true,'replayed',true,'transferred_value',t.transferred_value,'benefit_id',t.replacement_benefit_id);
 end if;
 if not exists(select 1 from public.customers where id=p_customer_id and deleted_at is null) then raise exception 'Choose a non-deleted recipient'; end if;
 if i.status in ('cancelled','refunded','cancellation_requested','refund_requested') then
  raise exception 'Resolve the invoice status and explicitly reopen it before moving spendable benefits'; end if;
 if exists(select 1 from public.invoice_reopen_benefits where invoice_id=i.id and applied_at is null)
  or exists(select 1 from public.invoice_reopen_vouchers where invoice_id=i.id and applied_at is null) then
  raise exception 'Settle the reopened invoice before moving its reinstated benefits'; end if;
 select * into b from public.invoice_benefit_values where id=p_benefit_id for update;
 perform public.assert_invoice_credit_source_evidence(i.id,b.invoice_item_id);
 if b.cancelled_unused_value>0 then raise exception 'Resolve reserved cancelled benefits before moving this allocation'; end if;
 if b.lot_id is not null then
  select * into l from public.customer_credit_lots where id=b.lot_id for update;
  if l.status<>'active' or l.is_locked then raise exception 'This credit lot is locked or reversed'; end if;
  if (l.customer_id,l.store_id) is not distinct from (p_customer_id,p_store_id) then raise exception 'Choose a different recipient or store'; end if;
  moved:=l.remaining_amount; old_snapshot:=to_jsonb(l);
 else
  select * into v from public.customer_reward_vouchers where id=b.reward_voucher_id for update;
  if v.status<>'held' then raise exception 'Only unused held vouchers can move; redeemed records remain with their original recipient'; end if;
  if (v.customer_id,v.store_id) is not distinct from (p_customer_id,p_store_id) then raise exception 'Choose a different recipient or store'; end if;
  moved:=v.quantity; old_snapshot:=to_jsonb(v);
 end if;
 if moved is null or moved<=0 then raise exception 'No unused value remains to move'; end if;
 insert into public.invoice_benefit_transfers(id,invoice_id,source_benefit_id,customer_id,store_id,transferred_value,request_id,request_hash,reason,before_snapshot,created_by)
  values(transfer_id,i.id,b.id,p_customer_id,p_store_id,moved,p_request_id,h,p_reason,old_snapshot,auth.uid());
 replacement:=gen_random_uuid();
 if b.lot_id is not null then
  insert into public.customer_credit_wallets(customer_id) values(p_customer_id) on conflict(customer_id) do nothing;
  select id into wallet from public.customer_credit_wallets where customer_id=p_customer_id;
  update public.customer_credit_lots set remaining_amount=0,updated_at=now() where id=l.id;
  insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
   values(l.wallet_id,l.customer_id,'adjust_decrease',l.category,moved,l.id,'invoice_benefit_transfer_out',transfer_id,l.store_id,p_reason,auth.uid(),auth.uid());
  -- Carry eligibility, expiry/restrictions and original purchase date, so a
  -- recipient correction cannot turn bonus credit into unrestricted paid credit.
  -- 445: but not its link to a lot it replaced (reassigned_from_lot_id: an
  -- invoice reassignment's, 321, or a merge's): moved credit is traced through
  -- its transfer (invoice_credit_transfer_origin). A copied link made the
  -- recipient's lot read as the invoice's own credit (credit_lot_chain,
  -- invoice_credit_lot_ids).
  insert into public.customer_credit_lots select (jsonb_populate_record(null::public.customer_credit_lots,to_jsonb(l)||jsonb_build_object(
   'id',replacement,'wallet_id',wallet,'customer_id',p_customer_id,'store_id',p_store_id,
   'original_amount',moved,'remaining_amount',moved,'source_type','invoice_benefit_transfer','source_record_id',transfer_id,
   'reference_no',null,'reason',p_reason,'reversal_of_lot_id',null,'reassigned_from_lot_id',null,'created_by',auth.uid(),'approved_by',auth.uid(),'created_at',now(),'updated_at',now()))).*;
  insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
   values(wallet,p_customer_id,'grant',l.category,moved,replacement,'invoice_benefit_transfer_in',transfer_id,p_store_id,p_reason,auth.uid(),auth.uid());
  select to_jsonb(q) into new_snapshot from public.customer_credit_lots q where id=replacement;
 else
  if v.store_id is distinct from p_store_id and exists(select 1 from public.vouchers where id=v.voucher_id and qty_type='limited') then
   update public.voucher_store_stock set current_qty=current_qty-v.quantity where voucher_id=v.voucher_id and store_id=p_store_id and current_qty>=v.quantity;
   if not found then raise exception 'Not enough voucher stock at the destination store'; end if;
   insert into public.voucher_store_stock(voucher_id,store_id,current_qty) values(v.voucher_id,v.store_id,v.quantity)
    on conflict(voucher_id,store_id) do update set current_qty=public.voucher_store_stock.current_qty+excluded.current_qty;
  end if;
  update public.customer_reward_vouchers set status='revoked',notes=concat_ws(E'\n',notes,'Unused units moved by invoice correction '||transfer_id) where id=v.id;
  insert into public.customer_reward_vouchers(id,customer_id,voucher_id,store_id,quantity,status,issued_by,source_type,source_id,notes)
   values(replacement,p_customer_id,v.voucher_id,p_store_id,v.quantity,'held',auth.uid(),'invoice_benefit_transfer',transfer_id,'Original voucher '||v.id||': '||p_reason);
  select to_jsonb(q) into new_snapshot from public.customer_reward_vouchers q where id=replacement;
 end if;
 insert into public.invoice_benefit_values(invoice_id,invoice_item_id,lot_id,reward_voucher_id,paid_value,granted_value,evidence,created_by)
  values(i.id,b.invoice_item_id,case when b.lot_id is not null then replacement end,case when b.reward_voucher_id is not null then replacement end,
   round(b.paid_value*moved/b.granted_value,2),moved,'Unused portion transferred from recorded allocation '||b.id||'; transfer '||transfer_id,auth.uid()) returning id into new_benefit;
 update public.invoice_benefit_transfers set replacement_benefit_id=new_benefit,after_snapshot=new_snapshot where id=transfer_id;
 update public.invoices set edit_count=coalesce(edit_count,0)+1,edited_at=now(),edited_by=auth.uid() where id=i.id;
 perform public.write_audit_ex('invoices',i.id,'unused_benefit_recipient_corrected',old_snapshot,new_snapshot,'invoices',p_reason,i.store_id);
 return jsonb_build_object('success',true,'transferred_value',moved,'benefit_id',new_benefit);
end $function$
$mdef$;
  -- Who may call it: signed-in staff and the server (as read, 339; kept). No
  -- function calls it (the Finance panel does, through the API).
  c_move_acl constant text := '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}';

  -- ── Relied on, not changed (production, 21 Oct 2026, after 441 and 443) ──
  c_relied constant text[] := array[
    'preview_customer_merge(uuid,uuid)', 'ensure_customer_wallet(uuid)', 'is_owner_or_manager()',
    'reassign_customer_referrer(uuid,uuid,text)', 'write_audit(text,uuid,text,jsonb,jsonb)',
    'link_affiliate_signup(uuid,uuid,text,uuid,boolean)', 'trg_credit_lot_immutable()',
    'credit_lot_policy(text,text,boolean)', 'credit_lot_policy_for(uuid)', 'invoice_credit_transfer_origin(uuid)',
    'credit_lot_source_group(uuid)', 'credit_lot_chain(uuid)', 'credit_lot_current(uuid)',
    'invoice_credit_lot_ids(uuid)', 'customer_credit_balances(uuid)', 'invoice_refund_options_before_sessions(uuid)',
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)', 'cancel_invoice_recorded(uuid,text,uuid)',
    'writeoff_released_credit_on_close(uuid,text,text)', 'invoice_commission_benefit_source(uuid)',
    'move_invoice_benefits_to_customer(uuid,uuid,uuid,text)',
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)', 'record_invoice_payment(uuid,jsonb,uuid)'];
  c_relied_md5 constant text[] := array[
    'f66c9d63369ef3b831ca74906a99b587', '8ef18daebbbe3c12f2024290ea8416e8', 'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    '9b32f3bef5b4f17897aae637e343c208', 'b194f839993670c5b5dd28e934c2a829',
    '198780b31301695db55c4a39ba9618f8', '0fc74da0dcc9b436dfd26c4582542f6c',
    'd9a97af64871c4ebcff8d1f6c15f68a6', 'ccdd506e78c7cdca97194fde87cdcc42', 'e778a9e4ff81567a493b8ca479d8222b',
    '6b902cb426210eb10ee9a15344ff100b', '556e725784154cbffc23d3ad900f9366', 'd48fb24e6eb9733d7f867e42fa703e7b',
    '50346a2e9aea50b31d4207c43b2f197c', 'c2287779ce0ec9c52eeec41952055f78', 'bd3afcc79cd2f06f983607d54fed167c',
    'e6f6c3cbf1bda3574d748bde2db5a759', 'de52d9dbaef8ab15163bef35cb9d733d',
    '284a89cfb965e8028136b5f8a4f2bf08', 'f8d3d29fae79065a252a8c5231cc2d4b',
    '2c01c460d3af8edd3ad86332aa286ed8',
    '80c80d386a5241e63b353e35e13ef250', '9c70097ed4da614fb9dcc66fdfcdb7d6'];

  -- ── Tables and columns, as read on 21 Oct 2026 ───────────────────────────
  -- customer_credit_lots, every column: the new lot is the old one's row with
  -- some of them set.
  c_lot_cols constant text :=
    'id uuid, wallet_id uuid, customer_id uuid, category text, original_amount numeric(12,2), '
    'remaining_amount numeric(12,2), source_type text, source_record_id uuid, store_id uuid, usage_restrictions jsonb, '
    'original_purchase_date date, effective_date date, reference_no text, reason text, note text, status text, '
    'reversal_of_lot_id uuid, is_locked boolean, created_by uuid, approved_by uuid, '
    'created_at timestamp with time zone, updated_at timestamp with time zone, reassigned_from_lot_id uuid';
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
  v text; d text; dm text; i int; v_acl text; v_move_acl text;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_pk uuid; t_m uuid; t_k uuid;
  t_inv uuid; t_paid uuid; t_bonus uuid; t_ans jsonb; t_old public.customer_credit_lots%rowtype;
  t_new public.customer_credit_lots%rowtype; t_lot uuid; t_z uuid; t_kp uuid; t_zb uuid; t_zl uuid;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The text is the tested one.
  if md5(c_def) <> c_after then
    raise exception '445: the text of public.% is not the tested one (md5 %)', c_sig, md5(c_def); end if;

  -- merge_customer_records is its BEFORE or this file's AFTER; no other
  -- function takes its name.
  if to_regprocedure('public.' || c_sig) is null then
    raise exception '445: public.% is missing', c_sig; end if;
  d := md5(pg_get_functiondef(to_regprocedure('public.' || c_sig)));
  if d <> c_after and d <> c_before then
    raise exception '445: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', c_sig, d; end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'merge_customer_records'
     and p.oid::regprocedure::text <> c_sig;
  if v is not null then raise exception '445: another function takes the name merge_customer_records: %', v; end if;

  -- transfer_invoice_unused_benefit (Move) is its BEFORE or this file's
  -- AFTER; no other function takes its name.
  if md5(c_move_def) <> c_move_after then
    raise exception '445: the text of public.% is not the tested one (md5 %)', c_move_sig, md5(c_move_def); end if;
  if to_regprocedure('public.' || c_move_sig) is null then
    raise exception '445: public.% is missing', c_move_sig; end if;
  dm := md5(pg_get_functiondef(to_regprocedure('public.' || c_move_sig)));
  if dm <> c_move_after and dm <> c_move_before then
    raise exception '445: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', c_move_sig, dm; end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'transfer_invoice_unused_benefit'
     and p.oid::regprocedure::text <> c_move_sig;
  if v is not null then raise exception '445: another function takes the name transfer_invoice_unused_benefit: %', v; end if;

  -- The functions relied on are as read on production (21 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '445: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if to_regprocedure('auth.uid()') is null then raise exception '445: auth.uid() must be there'; end if;

  -- Only link_affiliate_signup calls it, so its answer needs no other caller
  -- checked. (A session's own temporary functions, a test suite's helpers,
  -- are not counted.)
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'merge_customer_records\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and not (p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = c_sig);
  if v is distinct from array_to_string(c_callers, ', ') then
    raise exception '445: the functions that call merge_customer_records are not as read on 21 Oct 2026 (%); check each, then re-test', v; end if;
  -- No function calls Move (as read), so its answer needs none checked.
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where p.prosrc ~ 'transfer_invoice_unused_benefit\s*\(' and ns.nspname not like 'pg\_temp\_%'
     and not (p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = c_move_sig);
  if v is not null then
    raise exception '445: functions call transfer_invoice_unused_benefit (%), none did on 21 Oct 2026; check each, then re-test', v; end if;

  -- The tables and columns, as read on 21 Oct 2026.
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), ', ' order by a.attnum) into v
    from pg_attribute a
   where a.attrelid = 'public.customer_credit_lots'::regclass and a.attnum > 0 and not a.attisdropped;
  if v is distinct from c_lot_cols then
    raise exception '445: customer_credit_lots'' columns are not as read on 21 Oct 2026: %', v; end if;
  select string_agg(c.relname || '.' || a.attname, ', ' order by c.relname || '.' || a.attname) into v
    from pg_constraint k
    join pg_class c on c.oid = k.conrelid
    join pg_attribute a on a.attrelid = k.conrelid and a.attnum = any (k.conkey)
   where k.contype = 'f' and k.confrelid = 'public.customer_credit_lots'::regclass;
  if v is distinct from c_lot_refs then
    raise exception '445: the columns that name a credit lot are not as read on 21 Oct 2026 (%); decide for each new one whether a merge repoints it, then re-test', v; end if;
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('invoice_benefit_values', 'id', 'uuid'), ('invoice_benefit_values', 'lot_id', 'uuid'),
                 ('invoice_benefit_transfers', 'source_benefit_id', 'uuid'),
                 ('credit_package_sales', 'credit_lot_id', 'uuid'), ('credit_package_sales', 'bonus_credit_lot_id', 'uuid'),
                 ('premium_bundle_sales', 'paid_credit_lot_id', 'uuid'), ('premium_bundle_sales', 'bonus_credit_lot_id', 'uuid'),
                 ('invoice_credit_splits', 'issued_lot_id', 'uuid')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '445: these columns are missing or not as read on 21 Oct 2026: %', v; end if;
  if (select string_agg(pg_get_triggerdef(t.oid), ' | ') from pg_trigger t
       where t.tgrelid = 'public.customer_credit_lots'::regclass and not t.tgisinternal) is distinct from c_lot_trigger then
    raise exception '445: the triggers on customer_credit_lots are not as read on 21 Oct 2026'; end if;
  select string_agg(t.tgrelid::regclass::text || ' ' || t.tgname, ', ') into v
    from pg_trigger t
   where t.tgrelid in (select to_regclass('public.' || x) from unnest(c_plain) x) and not t.tgisinternal;
  if v is not null then raise exception '445: these tables have triggers they did not have on 21 Oct 2026: %', v; end if;

  -- No lot granted by a Move carries a link (3.: none did on 21 Oct 2026).
  -- One that does needs its own decision, so nothing is changed. (A lot a
  -- merge grants for moved credit keeps its source and has the link; its
  -- grant is 'customer_merge_in', so it is not counted.)
  select count(*) into i
    from public.customer_credit_lots l
   where l.reassigned_from_lot_id is not null
     and exists (select 1 from public.customer_credit_ledger e
                  where e.lot_id = l.id and e.entry_type = 'grant' and e.source_type = 'invoice_benefit_transfer_in');
  if i > 0 then
    raise exception '445: % lot(s) granted by a Move name a lot they did not replace (reassigned_from_lot_id); none did on 21 Oct 2026. Decide what each should name, then re-test', i; end if;

  -- Who may call each, as read. Compared as sets: production lists the same
  -- grants in another order than a local copy does (the first apply refused
  -- on that, 22 Oct 2026, changing nothing).
  select coalesce(proacl::text, '') into v_acl from pg_proc where oid = to_regprocedure('public.' || c_sig);
  if (select array_agg(x::text order by x::text) from unnest(nullif(v_acl, '')::aclitem[]) x)
     is distinct from (select array_agg(x::text order by x::text) from unnest(c_acl::aclitem[]) x) then
    raise exception '445: who may call public.% is not as read on 21 Oct 2026 (%)', c_sig, v_acl; end if;
  select coalesce(proacl::text, '') into v_move_acl from pg_proc where oid = to_regprocedure('public.' || c_move_sig);
  if (select array_agg(x::text order by x::text) from unnest(nullif(v_move_acl, '')::aclitem[]) x)
     is distinct from (select array_agg(x::text order by x::text) from unnest(c_move_acl::aclitem[]) x) then
    raise exception '445: who may call public.% is not as read on 21 Oct 2026 (%)', c_move_sig, v_move_acl; end if;

  -- ── Change ──────────────────────────────────────────────────────────────
  if d <> c_after then
    execute c_def;
  else
    raise notice '445: merge_customer_records already this version; left alone';
  end if;
  if dm <> c_move_after then
    execute c_move_def;
  else
    raise notice '445: transfer_invoice_unused_benefit already this version; left alone';
  end if;

  -- ── Afterwards ──────────────────────────────────────────────────────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_after then
    raise exception '445: public.% was installed with an md5 other than the tested one', c_sig; end if;
  if (select coalesce(proacl::text, '') from pg_proc where oid = to_regprocedure('public.' || c_sig)) is distinct from v_acl
     or has_function_privilege('anon', to_regprocedure('public.' || c_sig), 'execute')
     or has_function_privilege('authenticated', to_regprocedure('public.' || c_sig), 'execute') then
    raise exception '445: the grants of public.% changed', c_sig; end if;
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_move_sig))) <> c_move_after then
    raise exception '445: public.% was installed with an md5 other than the tested one', c_move_sig; end if;
  if (select coalesce(proacl::text, '') from pg_proc where oid = to_regprocedure('public.' || c_move_sig)) is distinct from v_move_acl
     or has_function_privilege('anon', to_regprocedure('public.' || c_move_sig), 'execute')
     or not has_function_privilege('authenticated', to_regprocedure('public.' || c_move_sig), 'execute') then
    raise exception '445: the grants of public.% changed', c_move_sig; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("445 check", @example.invalid, fictional phones no
  -- customer uses); it ends by raising P0445, which undoes all it wrote. No
  -- therapy or stock is sold.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from unnest(array['+61491570880', '+61491570881', '+61491570882', '+61491570883',
                                                 '+61491570884', '+61491570885']) p
                       where not exists (select 1 from public.customers c where c.phone = p)
                       order by p limit 3);
    if cardinality(t_phones) < 3 then raise exception '445: the self-test found no three unused fictional phones'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '445-check-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '445 check', '445-check-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('445 check ' || t_sfx, '445-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name) values ('445 check cash ' || t_sfx) returning id into t_cash;
    insert into public.credit_packages (name, customer_price, paid_credit_amount, bonus_enabled, bonus_value,
                                        allow_product, allow_therapy, allow_voucher, grants_reward)
    values ('445 check ' || t_sfx, 100, 100, true, 10, true, true, true, false) returning id into t_pk;
    insert into public.credit_package_stores (package_id, store_id) values (t_pk, t_store);
    insert into public.customers (full_name, phone) values ('445 Check Gone ' || t_sfx, t_phones[1]) returning id into t_m;
    insert into public.customers (full_name, phone) values ('445 Check Kept ' || t_sfx, t_phones[2]) returning id into t_k;
    insert into public.customers (full_name, phone) values ('445 Check Friend ' || t_sfx, t_phones[3]) returning id into t_z;
    -- The duplicate buys the package (Paid 100, Bonus 10), cash.
    t_inv := public.create_invoice(t_store, t_m, null::uuid,
      jsonb_build_array(jsonb_build_object('kind', 'credit_package', 'credit_package_id', t_pk, 'quantity', 1)),
      0::numeric, null::text, null::uuid, '[]'::jsonb);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 100)),
      gen_random_uuid());
    select s.credit_lot_id, s.bonus_credit_lot_id into t_paid, t_bonus from public.credit_package_sales s where s.invoice_id = t_inv;
    if t_paid is null or t_bonus is null
       or (select count(*) from public.customer_credit_lots l where l.id in (t_paid, t_bonus) and l.customer_id = t_m) <> 2 then
      raise exception '445: the self-test''s package did not give its buyer two lots'; end if;
    t_ans := public.merge_customer_records(t_k, t_m, '445 check', gen_random_uuid());
    if not coalesce((t_ans ->> 'success')::boolean, false) or (t_ans ->> 'kept') is distinct from t_k::text
       or (t_ans ->> 'retired') is distinct from t_m::text or (t_ans -> 'moved' ->> 'invoices.customer_id') is distinct from '1' then
      raise exception '445: the self-test''s merge did not answer as tested: %', t_ans; end if;
    -- Each of the two: drawn down, and the kept customer's new lot is the same
    -- credit, linked to it.
    foreach t_lot in array array[t_paid, t_bonus] loop
      select * into t_old from public.customer_credit_lots where id = t_lot;
      select * into t_new from public.customer_credit_lots where reassigned_from_lot_id = t_lot;
      if t_old.remaining_amount <> 0 or t_new.id is null or t_new.customer_id <> t_k
         or (select count(*) from public.customer_credit_lots where reassigned_from_lot_id = t_lot) <> 1
         or (t_new.category, t_new.source_type, t_new.source_record_id, t_new.usage_restrictions, t_new.store_id,
             t_new.effective_date, t_new.original_purchase_date)
            is distinct from (t_old.category, t_old.source_type, t_old.source_record_id, t_old.usage_restrictions, t_old.store_id,
                              t_old.effective_date, t_old.original_purchase_date)
         or t_new.source_type <> 'credit_package' or t_new.source_record_id <> t_pk
         or t_new.original_amount <> t_old.original_amount or t_new.remaining_amount <> t_old.original_amount
         or public.credit_lot_policy_for(t_new.id) <> (case t_new.category when 'paid' then 'package_paid' else 'package_bonus' end)
         or public.credit_lot_source_group(t_new.id) <> 'credit_package' then
        raise exception '445: the self-test''s % lot was not carried over as the same credit: % -> %', t_old.category, to_jsonb(t_old), to_jsonb(t_new); end if;
      if (select l.id from public.invoice_benefit_values b join public.customer_credit_lots l on l.id = b.lot_id
           where b.invoice_id = t_inv and l.category = t_old.category) is distinct from t_new.id then
        raise exception '445: the self-test''s % benefit value does not name the kept customer''s lot', t_old.category; end if;
    end loop;
    if (select (s.credit_lot_id, s.bonus_credit_lot_id) from public.credit_package_sales s where s.invoice_id = t_inv)
       is distinct from (select (p.id, b.id) from public.customer_credit_lots p, public.customer_credit_lots b
                          where p.reassigned_from_lot_id = t_paid and b.reassigned_from_lot_id = t_bonus) then
      raise exception '445: the self-test''s sale does not name the kept customer''s lots'; end if;
    if (select count(*) from jsonb_array_elements(public.invoice_refund_options_before_sessions(t_inv) -> 'benefits') x
         where x ->> 'customer_id' = t_k::text and (x ->> 'max_refund')::numeric > 0) <> 2
       or exists (select 1 from public.customer_credit_lots where customer_id = t_k and source_type = 'customer_merge') then
      raise exception '445: the self-test''s refund options do not take the credit back from the kept customer: %',
        public.invoice_refund_options_before_sessions(t_inv) -> 'benefits'; end if;
    -- 3. The kept customer's Paid credit moved on to a friend (Move): the
    -- friend's lot has no link, the package's Paid credit is still followed
    -- to the kept customer's lot (not the friend's), and the moved credit's
    -- sale is found.
    select l.id into t_kp from public.customer_credit_lots l where l.reassigned_from_lot_id = t_paid;
    t_ans := public.transfer_invoice_unused_benefit(
      (select b.id from public.invoice_benefit_values b where b.invoice_id = t_inv and b.lot_id = t_kp),
      t_z, t_store, '445 check', gen_random_uuid());
    t_zb := (t_ans ->> 'benefit_id')::uuid;
    select b.lot_id into t_zl from public.invoice_benefit_values b where b.id = t_zb;
    if t_zl is null
       or (select (l.customer_id, l.remaining_amount, l.source_type) from public.customer_credit_lots l where l.id = t_zl)
          is distinct from (t_z, 100::numeric, 'invoice_benefit_transfer'::text)
       or (select l.reassigned_from_lot_id from public.customer_credit_lots l where l.id = t_zl) is not null
       or public.credit_lot_current(t_paid) is distinct from t_kp
       or t_zl in (select x.lot_id from public.invoice_credit_lot_ids(t_inv) x)
       or (public.invoice_commission_benefit_source(t_zb) ->> 'sale_kind') is distinct from 'credit_package' then
      raise exception '445: the self-test''s moved credit is not traced as tested: %',
        (select to_jsonb(l) from public.customer_credit_lots l where l.id = t_zl); end if;
    raise exception using errcode = 'P0445', message = '445: self-test done, undone';
  exception when sqlstate 'P0445' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
