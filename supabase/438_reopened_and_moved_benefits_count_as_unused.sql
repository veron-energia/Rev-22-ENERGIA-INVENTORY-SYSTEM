-- 438_reopened_and_moved_benefits_count_as_unused.sql
--
-- A VOUCHER A REOPENING GAVE AGAIN, OR A UNIT AN OWNER MOVED, IS NOT "USED":
-- THE MONEY OF AN INVOICE CANCELLED, REOPENED AND CANCELLED AGAIN CAN BE
-- RECORDED AS PAID BACK, AND THE GUIDED CANCEL ASKS FOR NO FALSE OVERRIDE
--
-- WHO FOUND IT
--
--   The Health Seminar session (436), round 6 of its checks, 20-21 Oct 2026,
--   and passed to 417's and 434's owners. Reproduced on copies only, through
--   the app's own calls (the invoice form, the Pay dialog, the guided Cancel,
--   the Finance panel's Reopen, Move and "Record refund paid"): on production
--   now (78e592e1, 1269 functions) and on the stack after 430 (be589a20,
--   1280). The verifier and the scout of 21 Oct 2026 found the second case
--   (Move) and the FOC-off case below. The reviews of 21 Oct 2026 found what
--   NOT COVERED 1 now adds (a voucher swapped in the save that took the FOC
--   off) and NOT COVERED 4 and 5 (both there before 438); none of them
--   changes 438's code.
--
-- WHAT WAS WRONG
--
--   409's cancelled_invoice_used_value(uuid) says what the customer of a
--   cancelled invoice already had from it (sessions delivered, therapy
--   started, vouchers redeemed, credit spent). invoice_action_plan asks an
--   Owner or Manager override for each, by the same test: a benefit row of
--   the invoice (invoice_benefit_values) whose unused part - the voucher
--   still held, or what is left on the credit lot, plus what a cancellation
--   took back unused (cancelled_unused_value) - is less than what the row
--   granted counts as redeemed or spent. Three things take units off a row
--   without anyone using them, and the test counted none of them:
--   * A reopening (reopen_invoice, then apply_reopened_invoice_vouchers when
--     the invoice is settled again): the cancellation took the voucher back
--     (cancelled_unused_value 1); the reopening gives it again as a new
--     voucher on a new benefit row of the same invoice (source
--     'invoice_reopen'), records the unit in invoice_reopen_vouchers
--     (applied_at set) and sets the old row's cancelled_unused_value to 0.
--   * The payment that settles an invoice whose FOC was taken off (416's
--     trg_issue_sold_vouchers_on_paid) gives the vouchers taken back again in
--     the same way (an applied invoice_reopen_vouchers row each), as far as
--     the corrected line still gives them: the same voucher, up to its new
--     quantity. Units the correction dropped or swapped away get no such row
--     (NOT COVERED 1).
--   * The Finance panel's Move (transfer_invoice_unused_benefit): an Owner or
--     Manager moves the unused units to another customer or store; the old
--     voucher is revoked, or the old credit lot set to 0, and the units go on
--     a new benefit row of the same invoice (invoice_benefit_transfers, with
--     replacement_benefit_id).
--   (A customer change on the invoice that takes its benefits along also
--   moves credit off its row; 438 leaves that alone: NOT COVERED 5.)
--   So a plain S$30 voucher sale, paid, cancelled, reopened (paid again: the
--   money was still held) and cancelled again read "vouchers redeemed" though
--   nothing was used. "Record refund paid" for the S$30 still held was
--   refused ("Part of what INV-... sold has been used (vouchers redeemed),
--   and no amount owed back was stated when it was cancelled ... Nothing was
--   recorded."), the Invoices page hid that button, and the guided Cancel of
--   the reopened invoice asked for a voucher_redeemed override that was not
--   true; since 417 it also asked "State how much is owed back", and the
--   audit row 'cancel_refund_owed_stated' named voucher_redeemed. 417's
--   guided path lets the refund through on the amount stated, but a direct
--   cancel_invoice_recorded, and every invoice cancelled before 417, stayed
--   refused. The same after a Move: Refund in full of a paid invoice whose
--   voucher had been moved already asked for the override, and once cancelled
--   its refund was refused; moved credit read "credit spent". And after the
--   FOC came off with the same voucher and a quantity not lowered, and the
--   invoice was paid: the override on Refund in full and Cancel, and the
--   refusal after a cancel (lowered or swapped: NOT COVERED 1).
--   Production, 18 Oct 2026 (434's header): no voucher had source
--   'invoice_reopen' or 'invoice_benefit_transfer'. Whether any invoice is in
--   this state today is not known here (this was built on copies only): the
--   query under DEPLOY ORDER lists any, read only.
--
-- THE RULE
--
--   "Used" stays what 409 says: vouchers redeemed, credit spent (and
--   sessions delivered, therapy started, released credit spent, unchanged).
--   A unit that a reopening or a payment gave again, or that an Owner moved,
--   was not used: its replacement is a benefit row of the same invoice and is
--   tested on its own, so a replacement that is redeemed or spent still counts
--   as used. This is how 417's cancel_invoice_recorded already follows each
--   unit (it subtracts the applied invoice_reopen_vouchers rows and the
--   transferred_value when it gives voucher stock back, and it takes the
--   moved unit back from whoever holds it), and how 436's event_vip_take_back
--   counts them (436's item 8, built on the Owner's decision of 20 Oct 2026
--   for a VIP refunded in full: one moved to another customer is not used;
--   its replacement is taken back, or named once used). That a Move is not a
--   use is read from those two, and the Owner confirmed it on 21 Oct 2026.
--
-- WHAT THIS DOES (two functions, each patched at its anchors; grants kept)
--
--   * cancelled_invoice_used_value(uuid) (409's, the service role's alone):
--     the voucher test adds the units of each row a reopening or a payment
--     gave again (invoice_reopen_vouchers, applied_at set) and the units an
--     Owner moved (invoice_benefit_transfers with a replacement); the credit
--     test adds the credit an Owner moved. Two expressions change, with a
--     comment each. refund_invoice_recorded, resolve_invoice_action_v2 and
--     its audit row read it, unchanged.
--   * invoice_action_plan(uuid,text,jsonb) (417's, or 436's when 436 is in):
--     the same test where it asks voucher_redeemed or credit_used for a
--     benefit row; the same test also feeds 417's refund_owed ("State how
--     much is owed back") and the 'used' of its audit row. One expression
--     changes, with a comment. It is patched at one anchor inside whatever
--     version is installed (417's, or 436's, which patches two other places of
--     it), never replaced by a whole text, so 436's patch stays.
--   Nothing else changes: no table, no row, no other function, no grant.
--   The two sums are read per benefit row of one invoice, from two tables
--   that stay small (on 18 Oct 2026 no voucher on production came from a
--   reopening or a Move: 434's header), so no index is added.
--
-- NOT CHANGED
--
--   * invoice_refund_options and invoice_refund_options_before_sessions: each
--     row's remaining_value and max_refund are that row's own ceiling, and the
--     replacement is a row of its own with its own paid_value; adding the
--     replacement there would count its value twice. The fix is in the two
--     comparisons only.
--   * refund_invoice_recorded, resolve_invoice_action_v2,
--     request_invoice_action_v2, invoice_action_request_detail: they read the
--     two functions and need no change; pinned below.
--   * cancel_invoice_recorded, reopen_invoice, apply_reopened_invoice_vouchers,
--     apply_reopened_invoice_benefits, trg_issue_sold_vouchers_on_paid,
--     transfer_invoice_unused_benefit, invoice_voucher_reopen_candidates:
--     what they record is what this counts; pinned below. Credit needs no
--     reopening term: a reopening puts the credit back on the same lot
--     (apply_reopened_invoice_benefits), so the lot's remaining already
--     counts it.
--   * The pages: the Invoices page and the Finance panel read the plan's
--     codes (InvoicesPage.tsx, InvoiceFinancePanel.tsx); no page change.
--
-- NOT COVERED (found while building and reviewing this; unchanged by it, for
-- the Owner; the suite checks 1, 2, 4 and 5 as they are and prints them as
-- KNOWN)
--
--   1. The FOC taken off with the quantity lowered (2 given, 1 charged), or
--      with the line's voucher swapped for another in the same save (the
--      invoice form keeps the line when its catalogue item is changed): the
--      payment gives fewer again, or gives the new voucher as a sale (as "a
--      voucher this line did not give before", with no invoice_reopen_vouchers
--      row), and sets the taken-back row's cancelled_unused_value to 0. So the
--      units no longer given read as redeemed, before and after 438: Refund
--      in full and Cancel ask voucher_redeemed, and once cancelled "Record
--      refund paid" is refused unless the guided Cancel stated an amount
--      owed. Counting them needs a record of the units the correction dropped
--      or swapped away (416's trigger keeps none): a change of its own.
--   2. A voucher unit refunded by a line refund (Refund, part) leaves its row
--      short of what it granted, so a later Refund in full or Cancel asks a
--      voucher_redeemed override, before and after 438. The units refunded are
--      recorded only in invoice_refunds.outcome; counting them is a separate
--      change.
--   3. A guided request made before 438 on an invoice of this kind (reopened
--      and settled again, or with a Move) carries a plan that asked for the
--      false override; approving it after 438 is answered, unchanged, "What
--      this request would do has changed since it was submitted. Review the
--      revised effects and confirm them explicitly." (the plan hash differs).
--      Requests on other invoices keep their plan and hash (the suite's case
--      0 compares the plans whole).
--   4. (There before 438, not caused by it.) A reopening that leaves the
--      invoice part-paid queues the vouchers it takes back
--      (invoice_reopen_vouchers, not yet applied). A line refund made while
--      they wait (the guided "Refund some items") takes the unit's money out
--      of cancelled_unused_value but leaves its queued row, so the payment
--      that settles the invoice gives the unit again anyway
--      (apply_reopened_invoice_vouchers), and a later reopening counts the
--      same line refund again (invoice_voucher_reopen_candidates). On copies
--      of production now and of the stack: two S$30 vouchers sold and paid,
--      cancelled, S$30 recorded as paid back, reopened, line A refunded, the
--      S$30 outstanding paid: the customer holds 2 vouchers for S$30 net (a
--      second cancel, reopen and payment: 3 for two lines of 1). 438 counts
--      every applied row, these too, so there Refund in full and Cancel no
--      longer ask the voucher_redeemed override they asked before (wrongly,
--      as a redemption); what happens to the vouchers and the money is the
--      same either way (Refund in full pays back the S$30 and leaves line A's
--      voucher held). The fix is in refund_invoice_recorded (take the units
--      off the queued rows too) and invoice_voucher_reopen_candidates: the
--      Owner's decision, and a migration and test of its own.
--   5. (There before 438, not caused by it.) A customer change on the
--      invoice that takes its benefits along (correct_invoice with
--      benefit_action 'transfer': move_invoice_benefits_to_customer) moves a
--      voucher in place (the same row, still held: nothing changes for it),
--      but moves credit to a new lot of the new customer
--      (reassigned_from_lot_id), sets the invoice's own lot to 0 and writes no
--      invoice_benefit_transfers row. 438 does not count that as moved, on
--      purpose: the cancellation does not take the new customer's lot back
--      (cancel_invoice_recorded follows the benefit row's own lot only). So,
--      before and after 438, the invoice reads credit_used (Refund in full and
--      Cancel ask it); once cancelled, the new customer keeps the credit and
--      the refund due cannot be recorded: "Record refund paid" with no item is
--      refused for any credit invoice ("Allocate a correction refund to the
--      original unused purchased benefits ..."), and a line refund of the
--      benefit is over its cap ("Refund exceeds the unused paid value of this
--      benefit": the cap reads the invoice's own lot, now 0), also after a
--      guided Cancel that stated the amount owed. The fix is for the
--      cancellation and the refund's cap to follow the new lot, or for the
--      customer change to record a transfer with a replacement row as the
--      Move does (438's credit term would then count it): a migration of its
--      own.
--
-- ANSWERED (the Owner, 21 Oct 2026: "Yes, not used")
--
--   1. A voucher or credit moved with the Finance panel's Move to another
--      customer or store counts as not used, as 417's cancellation and 436
--      already treat it: Refund in full and Cancel ask no override for it,
--      and the money of the invoice can be recorded as paid back once it is
--      cancelled (the moved unit is taken back from whoever holds it). Once
--      the other customer redeems or spends it, it is used, as before. Yes.
--
-- ORDER (the rule agreed with the 436 session, 21 Oct 2026 02:45)
--
--   After 430 (Wednesday 21 Oct's run sheet: production's head, then 417,
--   434, 422, 423, 419, 425, 426, 430). If 436 goes live, 436 FIRST, then
--   438: 436 text-patches invoice_action_plan by its own anchors and accepts
--   only 417's version of it, and it pins cancelled_invoice_used_value at
--   409's 70f684f1; so 436 after 438 refuses as a whole ("436: public.
--   cancelled_invoice_used_value(uuid) is missing or not the version this was
--   tested against") and installs nothing, and 438 stays in. That is the
--   order rule, not a fault: 436 will not take a second version. 438 works on
--   either base: without 436 (417's plan) or with it (436's plan); the md5
--   table below holds both. 437 neither touches nor pins these functions, so
--   it goes before or after 438.
--
-- THE MD5 TABLE (one place to re-pin)
--
--   Every BEFORE and AFTER md5 this accepts is in c_md5, at the top of the
--   DO block, one line per installed version. 436's line is for 436 as
--   drafted when this was built (below); the final 436 may change its AFTER
--   of invoice_action_plan. Re-pinning to the final 436 is a ONE-LINE change:
--   that line's BEFORE becomes the final 436's AFTER of invoice_action_plan,
--   and its AFTER what 438 makes of it. Applied to a version not in the table,
--   438 refuses, installs nothing and prints both md5s (the installed one, and
--   what the patch would give when its anchor is found once), so the line can
--   be filled from that message and then re-tested on stack + final 436.
--   Update this header's copy too.
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic, and
--   every check comes before anything is installed:
--   * the functions it relies on and does not change must be as read on the
--     stack after 430 (the same with and without 436); the columns it reads
--     must be there with these types; the reopening's and the payment's
--     triggers on invoices as read;
--   * each of the two functions must be a BEFORE of the table (patched; each
--     anchor found exactly once; the text built must have the line's AFTER
--     md5 before it is installed) or an AFTER (left alone), so a second run
--     changes nothing; no other function may take their names;
--   * afterwards both have an AFTER md5 of the table and the grants they had
--     (cancelled_invoice_used_value: the service role alone;
--     invoice_action_plan: signed-in staff and the service role; anon
--     neither);
--   * then, inside a block that is always undone (it ends by raising P0438,
--     so it leaves no row): a made-up Owner, store, buyer, friend (fictional
--     ACMA phones) and S$30 voucher. (a) Paid, cancelled, reopened: the
--     guided Cancel's plan asks no used-override and no amount owed; cancelled
--     again: nothing reads as used, and "Record refund paid" for the S$30
--     records it. (b) The same, but the reopening's voucher redeemed: the plan
--     asks voucher_redeemed, the second cancel reads voucher_redeemed, and the
--     S$30 is refused. (c) Paid, its voucher moved to the friend: Refund in
--     full asks no override; cancelled, nothing reads as used.
--
-- BEFORE (the stack after 430, 21 Oct 2026; md5 of pg_get_functiondef with
-- search_path public; the same on the stack + 436 except invoice_action_plan):
--   changed
--   cancelled_invoice_used_value(uuid)                               70f684f1a8f0a4f42774394062e4df19  (409; 436 pins it)
--   invoice_action_plan(uuid,text,jsonb), 436 not in                 e117890fac11ea11435b691ca4787dec  (417's AFTER)
--   invoice_action_plan(uuid,text,jsonb), 436 in                     4af305c7b91bcbd8c36db21130307e0f  (436's AFTER, draft below)
--   relied on, not changed
--   invoice_refund_options_before_sessions(uuid)                     bd3afcc79cd2f06f983607d54fed167c
--   invoice_refund_options(uuid)                                     689a71c246260d2c10ec44dd94eb7139
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)        e6f6c3cbf1bda3574d748bde2db5a759
--   resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean) 201f08ebf14a64cd88d411a7cfb4c9c4
--   request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)        4360d74462ed1fc950b6bd8b5157b3ae
--   invoice_action_request_detail(uuid)                              df67842de673e4ec37890c027c52e0d9
--   cancel_invoice_recorded(uuid,text,uuid)                          de52d9dbaef8ab15163bef35cb9d733d  (417)
--   reopen_invoice(uuid,text,uuid)                                   c9fcab7adfccdaeba1eb8dee4134ba47  (417)
--   invoice_voucher_reopen_candidates(uuid)                          20405a96c8780eac6425a5dae59c29e1
--   apply_reopened_invoice_vouchers()                                71d50be41b73decceb0b20f8597dd4fa
--   apply_reopened_invoice_benefits()                                75489db2b12e60a3104fff9ef76c2d20
--   trg_issue_sold_vouchers_on_paid()                                c840d0d2754e7a8e889848ea8269a293  (416)
--   transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)        ea7e8ce0612752c75ba75748c9275c42
--   public function fingerprint (reference only, not guarded)
--     the stack after 430 (production now + 417, 434, 422, 423, 419,
--     425, 426, 430)                                                 be589a20fca0f181f648e6e93c45cb4d (1280)
--     ... + 436 (the draft below)                                    ba646923fea80bd850cdddb29b54418f (1352)
-- AFTER (for later guards):
--   cancelled_invoice_used_value(uuid)                               8caf1ea07bb021d91a5396b40fb7cda1  (with or without 436)
--   invoice_action_plan(uuid,text,jsonb), 436 not in                 d47bc403a52196092582ad8dc46f7b97
--   invoice_action_plan(uuid,text,jsonb), 436 in                     3e5fe6ccd93548c13b6ed62800595838  (re-pin with the final 436)
--   public function fingerprint (worked out on copies, not on production;
--   the number of functions is unchanged)
--     after 430 + 438                                                5dab2dce6f2665297dc387a2e106fb54 (1280)
--     after 430 + 436 + 438                                          aa3f804deae6685f41b3e6c63c001c60 (1352)
--   436 as tested: the draft of supabase/436_event_website_registrations_and_vip.sql
--   with file md5 58f6647bac6a0b97247f2e3a5cca23f5 (21 Oct 2026, 03:31),
--   whose AFTER of invoice_action_plan is 4af305c7... (its own header's
--   fingerprint ba646923 matches); the draft of 03:14 (file md5
--   4487de988ebf653cc8b9032f8806aee8; fingerprints ec4a9ffa..., then
--   6e6bba5c... with 438) had the same AFTER and gave the same two AFTERs
--   here. A later draft with the same AFTER needs no re-pin (only the
--   fingerprints above move).
--
-- RE-RUNNING EARLIER FILES AFTER 438 (checked on the copies)
--
--   434 re-runs as a no-op. 417 refuses (its invoice_action_plan is no
--   longer 417's: as after 436 already), and so does 436 (its pins on
--   cancelled_invoice_used_value and invoice_action_plan); each changes
--   nothing. 436's own suite (scripts/event-website/tests/event-website.sql)
--   therefore runs on a copy with 438 only with -v skip_install=1: run so on
--   the stack + 436 + 438, its 254 checks pass, as without 438.
--
-- DEPLOY ORDER (the database only; no page, no Edge Function)
--
--   1. After 430, and after 436 when 436 goes live (ORDER above).
--   2. Before it, read only, to know which invoices change (the refund of a
--      cancelled one becomes recordable; a guided request's plan changes):
--        select i.invoice_no, i.status, i.cancel_refund_owed,
--               public.cancelled_invoice_used_value(i.id) as used_now
--          from public.invoices i
--         where exists (select 1 from public.invoice_benefit_values b
--                        where b.invoice_id = i.id
--                          and (exists (select 1 from public.invoice_reopen_vouchers q
--                                        where q.benefit_id = b.id and q.applied_at is not null)
--                               or exists (select 1 from public.invoice_benefit_transfers t
--                                           where t.source_benefit_id = b.id
--                                             and t.replacement_benefit_id is not null)))
--         order by i.invoice_no;
--
-- Test: scripts/invoices/tests/reopen-recancel-438.sql (begin ... rollback;
-- run it with -v mig=supabase/438_reopened_and_moved_benefits_count_as_unused.sql
-- on a copy of the stack after 430, with or without 436; it installs this
-- file twice). Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ THE MD5 TABLE: every version this accepts (re-pin the "436" line) ═══
  --   function                                installed base              BEFORE                              AFTER
  c_md5 constant text[] := array[
    ['cancelled_invoice_used_value(uuid)',    '409 (436 in or not)',      '70f684f1a8f0a4f42774394062e4df19', '8caf1ea07bb021d91a5396b40fb7cda1'],
    ['invoice_action_plan(uuid,text,jsonb)',  '417 (436 not in)',         'e117890fac11ea11435b691ca4787dec', 'd47bc403a52196092582ad8dc46f7b97'],
    ['invoice_action_plan(uuid,text,jsonb)',  '436 (draft of 21 Oct)',    '4af305c7b91bcbd8c36db21130307e0f', '3e5fe6ccd93548c13b6ed62800595838']];

  c_uv constant text := 'cancelled_invoice_used_value(uuid)';
  c_pl constant text := 'invoice_action_plan(uuid,text,jsonb)';

  -- ══ cancelled_invoice_used_value: the voucher test and the credit test ══
  c_uv_a1 constant text := $a$                         and coalesce(case when v.status = 'held' then v.quantity else 0 end, 0)
                             + b.cancelled_unused_value < b.granted_value)
$a$;
  c_uv_r1 constant text := $r$                         -- 438: a unit a reopening or a payment gave again
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
$r$;
  c_uv_a2 constant text := $a$                         and coalesce(l.remaining_amount, 0) + b.cancelled_unused_value < b.granted_value)
$a$;
  c_uv_r2 constant text := $r$                         -- 438: credit an Owner moved was not spent: its new lot
                         -- is a row of its own, tested here.
                         and coalesce(l.remaining_amount, 0) + b.cancelled_unused_value
                             + coalesce((select sum(t.transferred_value) from public.invoice_benefit_transfers t
                                          where t.source_benefit_id = b.id and t.replacement_benefit_id is not null), 0)
                             < b.granted_value)
$r$;

  -- ══ invoice_action_plan: the per-benefit test (417's line; 436 keeps it) ══
  c_pl_a constant text := $a$   -- Anything already spent or redeemed is an override, not a silent reduction.
   if coalesce((b->>'remaining_value')::numeric,0) < coalesce((b->>'granted_value')::numeric,0) then
$a$;
  c_pl_r constant text := $r$   -- Anything already spent or redeemed is an override, not a silent reduction.
   -- 438: a unit a reopening or a payment gave again (invoice_reopen_vouchers,
   -- applied) or an Owner moved to another customer or store (the Finance
   -- panel's Move, invoice_benefit_transfers) was not used: its replacement
   -- is a benefit of its own here, tested on its own.
   if coalesce((b->>'remaining_value')::numeric,0)
      +coalesce((select sum(q.quantity) from public.invoice_reopen_vouchers q
                  where q.benefit_id=(b->>'id')::uuid and q.applied_at is not null),0)
      +coalesce((select sum(t.transferred_value) from public.invoice_benefit_transfers t
                  where t.source_benefit_id=(b->>'id')::uuid and t.replacement_benefit_id is not null),0)
      < coalesce((b->>'granted_value')::numeric,0) then
$r$;

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  r record; d text; d2 text; v text; n int; k int; v_bad text; v_row int;
  v_anchors text[]; v_patches text[];
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[];
  -- the check
  v_owner uuid; v_st uuid; v_buyer uuid; v_friend uuid; v_pm uuid; v_vch uuid; v_inv uuid;
  v_phones text[]; v_plan jsonb; v_msg text;
begin
  -- Definitions are read and compared with public alone on the search path,
  -- as they were read on 21 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── 1. Relied on, not changed: as read on the stack after 430 ───────────
  -- (the same with 436 in: 436 pins or leaves each of them)
  for r in select * from (values
      ('invoice_refund_options_before_sessions(uuid)',                         'bd3afcc79cd2f06f983607d54fed167c'),
      ('invoice_refund_options(uuid)',                                         '689a71c246260d2c10ec44dd94eb7139'),
      ('refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',            'e6f6c3cbf1bda3574d748bde2db5a759'),
      ('resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)', '201f08ebf14a64cd88d411a7cfb4c9c4'),
      ('request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)',            '4360d74462ed1fc950b6bd8b5157b3ae'),
      ('invoice_action_request_detail(uuid)',                                  'df67842de673e4ec37890c027c52e0d9'),
      ('cancel_invoice_recorded(uuid,text,uuid)',                              'de52d9dbaef8ab15163bef35cb9d733d'),
      ('reopen_invoice(uuid,text,uuid)',                                       'c9fcab7adfccdaeba1eb8dee4134ba47'),
      ('invoice_voucher_reopen_candidates(uuid)',                              '20405a96c8780eac6425a5dae59c29e1'),
      ('apply_reopened_invoice_vouchers()',                                    '71d50be41b73decceb0b20f8597dd4fa'),
      ('apply_reopened_invoice_benefits()',                                    '75489db2b12e60a3104fff9ef76c2d20'),
      ('trg_issue_sold_vouchers_on_paid()',                                    'c840d0d2754e7a8e889848ea8269a293'),
      ('transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)',            'ea7e8ce0612752c75ba75748c9275c42')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '438: public.% is missing or not the version read on the stack after 430 (21 Oct 2026). 438 goes after 430 (417 to 430 first); otherwise re-read it and re-test before applying.', r.fn; end if;
  end loop;
  -- The columns the two tests read.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('invoice_reopen_vouchers', 'benefit_id', 'uuid'),
                 ('invoice_reopen_vouchers', 'quantity', 'integer'),
                 ('invoice_reopen_vouchers', 'applied_at', 'timestamp with time zone'),
                 ('invoice_benefit_transfers', 'source_benefit_id', 'uuid'),
                 ('invoice_benefit_transfers', 'replacement_benefit_id', 'uuid'),
                 ('invoice_benefit_transfers', 'transferred_value', 'numeric(12,2)')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then
    raise exception '438: these columns are missing or not of the type read on 21 Oct 2026: %', v; end if;
  -- The reopening's trigger gives the vouchers again; the payment's fires
  -- after it and gives again what removing the FOC took back; credit goes
  -- back onto its own lot.
  for r in select * from (values
      ('invoice_reopen_vouchers_settled', 'CREATE TRIGGER invoice_reopen_vouchers_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_vouchers()'),
      ('invoice_reopen_benefits_settled', 'CREATE TRIGGER invoice_reopen_benefits_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_benefits()'),
      ('issue_sold_vouchers_on_paid',     'CREATE TRIGGER issue_sold_vouchers_on_paid AFTER UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_issue_sold_vouchers_on_paid()')) x(tg, def)
  loop
    if (select pg_get_triggerdef(t.oid) from pg_trigger t
         where t.tgrelid = 'public.invoices'::regclass and t.tgname = r.tg and t.tgenabled = 'O') is distinct from r.def then
      raise exception '438: the trigger % on public.invoices is not the one read on 21 Oct 2026', r.tg; end if;
  end loop;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('cancelled_invoice_used_value', 'invoice_action_plan')
     and p.oid::regprocedure::text not in (c_uv, c_pl);
  if v_bad is not null then
    raise exception '438: another overload of a function this changes exists: %', v_bad; end if;

  -- ── 2. Each function: a BEFORE of the table (patched) or an AFTER (left) ─
  foreach v in array array[c_uv, c_pl] loop
    if to_regprocedure('public.' || v) is null then
      raise exception '438: public.% is missing', v; end if;
    if v = c_uv then v_anchors := array[c_uv_a1, c_uv_a2]; v_patches := array[c_uv_r1, c_uv_r2];
    else v_anchors := array[c_pl_a]; v_patches := array[c_pl_r]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || v));
    if exists (select 1 from generate_subscripts(c_md5, 1) i where c_md5[i][1] = v and c_md5[i][4] = md5(d)) then
      raise notice '438: public.% is already this version; left alone', v;
      continue;
    end if;
    select min(i) into v_row from generate_subscripts(c_md5, 1) i where c_md5[i][1] = v and c_md5[i][3] = md5(d);
    -- What the patch would make of the installed text, for the messages.
    d2 := d;
    for k in 1 .. cardinality(v_anchors) loop
      n := (length(d) - length(replace(d, v_anchors[k], ''))) / length(v_anchors[k]);
      if n <> 1 then
        if v_row is null then
          raise exception '438: public.% is not a version this was tested against (md5 %), and its anchor % is found % times, not once. Re-read it and re-test before applying.', v, md5(d), k, n; end if;
        raise exception '438: the anchor % of public.% was found % times, not once', k, v, n;
      end if;
      d2 := replace(d2, v_anchors[k], v_patches[k]);
    end loop;
    if v_row is null then
      raise exception '438: public.% is not a version this was tested against (md5 %; patched it would be md5 %). If it is the final 436''s, re-pin the "436" line of the md5 table to these two md5s, re-test on the stack with the final 436, then apply.', v, md5(d), md5(d2);
    end if;
    if md5(d2) <> c_md5[v_row][4] then
      raise exception '438: the text built for public.% (base: %) is not the tested one (md5 %)', v, c_md5[v_row][2], md5(d2); end if;
    v_fns := v_fns || v;
    v_defs := v_defs || d2;
  end loop;

  -- The grants of both, to compare after.
  select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
    into v_acl
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text in (c_uv, c_pl);

  -- ── 3. Install ───────────────────────────────────────────────────────────
  for k in 1 .. coalesce(cardinality(v_fns), 0) loop
    execute v_defs[k];
  end loop;

  -- ── 4. Installed exactly as tested, grants as before ─────────────────────
  foreach v in array array[c_uv, c_pl] loop
    if not exists (select 1 from generate_subscripts(c_md5, 1) i
                    where c_md5[i][1] = v and c_md5[i][4] = md5(pg_get_functiondef(to_regprocedure('public.' || v)))) then
      raise exception '438: public.% is not at an AFTER md5 of the table (md5 %)', v, md5(pg_get_functiondef(to_regprocedure('public.' || v))); end if;
  end loop;
  if (select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
        from pg_proc p
       where p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text in (c_uv, c_pl))
     is distinct from v_acl then
    raise exception '438: the grants of the changed functions changed'; end if;
  if has_function_privilege('anon', 'public.' || c_uv, 'execute')
     or has_function_privilege('authenticated', 'public.' || c_uv, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_uv, 'execute') then
    raise exception '438: public.% is not the service role''s alone', c_uv; end if;
  if has_function_privilege('anon', 'public.' || c_pl, 'execute')
     or not has_function_privilege('authenticated', 'public.' || c_pl, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_pl, 'execute') then
    raise exception '438: public.% is not for signed-in staff and the service role only', c_pl; end if;

  -- ── 5. Behaviour, inside a block that is always undone ───────────────────
  -- Nothing is printed and no row remains.
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    insert into auth.users (id, email) values (gen_random_uuid(), '438-check-owner-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '438 check', u.email, 'owner'::public.user_role, true from auth.users u where u.id = v_owner;
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_owner::text, true);
    insert into public.stores (name, code, country_code)
      values ('438 check', '438-' || substr(md5(gen_random_uuid()::text), 1, 8), 'SG') returning id into v_st;
    insert into public.payment_methods (name, is_active) values ('438 check', true) returning id into v_pm;
    -- Two valid phones no customer has: numbers kept for fiction (ACMA),
    -- never a real person's.
    select array_agg(c.p order by c.p) into v_phones
      from (values ('+61491571266'), ('+61491571491'), ('+61491571804'), ('+61491572549'), ('+61491572665'),
                   ('+61491578957'), ('+61491578148'), ('+61491578888'), ('+61491579212'), ('+61491579760')) c(p)
     where public.normalize_customer_phone(c.p) = c.p
       and not exists (select 1 from public.customers cu where cu.phone = c.p);
    if coalesce(cardinality(v_phones), 0) < 2 then
      raise exception '438: the check found no two free fictional phones'; end if;
    insert into public.customers (full_name, phone) values ('438 check buyer', v_phones[1]) returning id into v_buyer;
    insert into public.customers (full_name, phone) values ('438 check friend', v_phones[2]) returning id into v_friend;
    insert into public.vouchers (name, code, voucher_kind, selling_price, qty_type, is_active)
      values ('438 check', '438-' || substr(md5(gen_random_uuid()::text), 1, 8), 'normal', 30, 'unlimited', true)
      returning id into v_vch;
    insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store) values (v_vch, v_st, 30, true);

    -- (a) The claim: paid S$30, cancelled, reopened (paid again: the money
    -- was still held), cancelled again.
    v_inv := public.create_invoice(v_st, v_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', v_vch, 'quantity', 1)));
    perform public.record_invoice_payment(v_inv, jsonb_build_array(jsonb_build_object('payment_method_id', v_pm, 'amount', 30)), gen_random_uuid());
    perform public.cancel_invoice_recorded(v_inv, '438 check', gen_random_uuid());
    perform public.reopen_invoice(v_inv, '438 check', gen_random_uuid());
    if not coalesce((select status::text from public.invoices where id = v_inv) = 'paid'
       and exists (select 1 from public.invoice_reopen_vouchers q where q.invoice_id = v_inv and q.applied_at is not null), false) then
      raise exception '438: the check''s invoice is not as tested after its reopening'; end if;
    v_plan := public.invoice_action_plan(v_inv, 'cancel', '[]'::jsonb);
    if exists (select 1 from jsonb_array_elements(coalesce(v_plan->'overrides_required', '[]'::jsonb)) o
                where o->>'code' in ('voucher_redeemed', 'credit_used'))
       or jsonb_typeof(v_plan->'refund_owed') = 'object' then
      raise exception '438: the guided Cancel of the reopened invoice still asks for a used override (%)', v_plan->'overrides_required'; end if;
    perform public.cancel_invoice_recorded(v_inv, '438 check', gen_random_uuid());
    if cardinality(public.cancelled_invoice_used_value(v_inv)) <> 0 then
      raise exception '438: the invoice cancelled again still reads %', public.cancelled_invoice_used_value(v_inv); end if;
    perform public.refund_invoice_recorded(v_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 30)),
      jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = v_inv
                                                            and p.entry_kind = 'receipt' order by p.created_at limit 1), 'amount', 30)),
      '[]'::jsonb, '438 check', gen_random_uuid());
    if (public.invoice_financial_position(v_inv)->>'refund_due')::numeric <> 0 then
      raise exception '438: the S$30 was not recorded as paid back (%)', public.invoice_financial_position(v_inv); end if;

    -- (b) The same, but the reopening's voucher was redeemed: still used.
    v_inv := public.create_invoice(v_st, v_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', v_vch, 'quantity', 1)));
    perform public.record_invoice_payment(v_inv, jsonb_build_array(jsonb_build_object('payment_method_id', v_pm, 'amount', 30)), gen_random_uuid());
    perform public.cancel_invoice_recorded(v_inv, '438 check', gen_random_uuid());
    perform public.reopen_invoice(v_inv, '438 check', gen_random_uuid());
    update public.customer_reward_vouchers set status = 'redeemed'
     where id in (select b.reward_voucher_id from public.invoice_benefit_values b
                    join public.customer_reward_vouchers cv on cv.id = b.reward_voucher_id
                   where b.invoice_id = v_inv and cv.status = 'held' and cv.source_type = 'invoice_reopen');
    if not found then raise exception '438: the check found no reopened voucher to redeem'; end if;
    v_plan := public.invoice_action_plan(v_inv, 'cancel', '[]'::jsonb);
    if not exists (select 1 from jsonb_array_elements(coalesce(v_plan->'overrides_required', '[]'::jsonb)) o
                    where o->>'code' = 'voucher_redeemed') then
      raise exception '438: the guided Cancel does not ask voucher_redeemed for a redeemed replacement'; end if;
    perform public.cancel_invoice_recorded(v_inv, '438 check', gen_random_uuid());
    if public.cancelled_invoice_used_value(v_inv) is distinct from array['voucher_redeemed'] then
      raise exception '438: a redeemed replacement reads % after the cancel', public.cancelled_invoice_used_value(v_inv); end if;
    v_msg := null;
    begin
      perform public.refund_invoice_recorded(v_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 30)),
        jsonb_build_array(jsonb_build_object('payment_id', (select p.id from public.invoice_payments p where p.invoice_id = v_inv
                                                              and p.entry_kind = 'receipt' order by p.created_at limit 1), 'amount', 30)),
        '[]'::jsonb, '438 check', gen_random_uuid());
    exception when others then v_msg := sqlerrm;
    end;
    if v_msg is null or v_msg not like 'Part of what % (vouchers redeemed)%' then
      raise exception '438: the refund of an invoice whose replacement was redeemed was not refused as used (%)', coalesce(v_msg, 'recorded'); end if;

    -- (c) Paid, its voucher moved to the friend (the Finance panel's Move).
    v_inv := public.create_invoice(v_st, v_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', v_vch, 'quantity', 1)));
    perform public.record_invoice_payment(v_inv, jsonb_build_array(jsonb_build_object('payment_method_id', v_pm, 'amount', 30)), gen_random_uuid());
    perform public.transfer_invoice_unused_benefit((select b.id from public.invoice_benefit_values b where b.invoice_id = v_inv),
      v_friend, v_st, '438 check', gen_random_uuid());
    v_plan := public.invoice_action_plan(v_inv, 'refund_full', '[]'::jsonb);
    if exists (select 1 from jsonb_array_elements(coalesce(v_plan->'overrides_required', '[]'::jsonb)) o
                where o->>'code' in ('voucher_redeemed', 'credit_used')) then
      raise exception '438: Refund in full of a moved voucher still asks for a used override'; end if;
    perform public.cancel_invoice_recorded(v_inv, '438 check', gen_random_uuid());
    if cardinality(public.cancelled_invoice_used_value(v_inv)) <> 0 then
      raise exception '438: the moved voucher''s invoice reads % after the cancel', public.cancelled_invoice_used_value(v_inv); end if;

    raise exception using errcode = 'P0438', message = '438: check done, undone';
  exception when sqlstate 'P0438' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
