-- 457_correct_foc_and_settled_invoices.sql
--
-- EVERY INVOICE HAS A WAY TO BE CORRECTED: A COMPLETED FOC INVOICE, AND ONE
-- THAT WAS ONCE SETTLED AND IS UNPAID AGAIN (the Owner, 22 Oct 2026, item 9)
--
-- WHAT WAS WRONG / WHY
--
--   * A completed FOC invoice had no Edit or Correct button on the Invoices
--     page (a page regression of 10 Sep 2026, kept by 417's page check): only
--     Refund / Cancel and a new invoice. correct_invoice already corrects one
--     (172, 416 rules 6, 7 and 14: what Confirm FOC took is recorded, a save
--     that stays FOC gives nothing more, taking the FOC off takes back the
--     unused vouchers it gave), so the page alone was missing it.
--   * Settling an invoice (paid, or completed FOC) sets invoices.locked_at
--     (lock_settled_invoice, 82), and nothing clears it. A correction that
--     takes the FOC off leaves the invoice unpaid, with no payment, still
--     locked. correct_invoice treated an unpaid invoice with no payment as an
--     ordinary edit (no reason, no Owner or Manager) and then asked
--     can_edit_invoice, which needs locked_at null, so every save on it was
--     refused, the Owner's too: "You cannot edit this invoice" (Make FOC and
--     Remove FOC refuse it too: "Invoice is locked"). The page offered "Edit
--     Invoice" there, and it always failed. The same dead end held for an
--     exchange's replacement invoice with its top-up not paid yet (made
--     locked, by create_exchange_invoice) and for a refund top-up invoice
--     (is_topup), unpaid with no payment: the page offers Owners and Managers
--     "Correct Invoice" on both, and the server answered "You cannot edit
--     this invoice".
--   * A correction that removes a line still on record elsewhere stopped
--     with the database's own words, for example 'update or delete on table
--     "invoice_items" violates foreign key constraint
--     "invoice_line_credit_allocations_invoice_item_id_fkey" on table
--     "invoice_line_credit_allocations"'. Reproduced on a copy of production
--     (made-up records, 23 Oct 2026): a line paid with the customer's credit,
--     on a paid invoice and again once it was cancelled; a line of a refunded
--     invoice named by a refund row, as the older line refund (55) wrote them
--     (today's refunds name the payment, not the line; production keeps the
--     older rows).
--   * A correction that changes the lines of an invoice settled once and
--     left unpaid or part-paid (its FOC taken off in that save or before)
--     took the voucher lines' units from stock at once, as for a settled
--     invoice, though no voucher is given until it is paid in full. A cancel
--     before then gave back one unit too few for each voucher the FOC removal
--     had taken back (cancel_invoice_recorded counts it as given), and
--     lowering the line gave none back. Reproduced on a copy of production
--     (made-up records, 24 Oct 2026): socks and one voucher, FOC confirmed,
--     the FOC taken off and the voucher raised to two in one save, then
--     cancelled: voucher stock 10 -> 9; the same when it was part paid
--     first. (The first draft of this file, letting such an invoice be
--     corrected again, opened three more such paths: cancelled before
--     payment; deleted by staff after its product line was removed, a unit
--     lost for good; raised then lowered before payment. An independent
--     review found them, 24 Oct 2026.)
--
-- THE RULES (binding; the Owner's answers, 22 Oct 2026, the recommendations
-- accepted)
--
--   * Owners and Managers (not staff) get "Correct Invoice" on completed FOC
--     invoices, with a reason and revision history, exactly like paid
--     invoices. The instalment fields are not shown when the invoice being
--     corrected was FOC.
--   * After a correction takes the FOC off (the invoice becomes unpaid but
--     was once settled, locked_at set), it can be corrected again through
--     Correct Invoice (Owners and Managers) instead of the page offering an
--     "Edit Invoice" that always fails.
--   * Today's rule stays: a corrected FOC invoice that stays FOC issues no
--     extra vouchers (416).
--   * Cancelled and refunded invoices stay correctable by Owners and
--     Managers as today, but the raw database error some of those paths show
--     is replaced by a plain message.
--   * Exchange (replacement) invoices: header-only correction for Owners and
--     Managers, as today. Rental late-fee invoices stay uneditable.
--   * "All invoices editable" means: every status has its correct path and
--     no dead end.
--   How it reads (this file, 23-24 Oct 2026):
--   * An invoice is corrected as a settled one (an Owner or Manager, or staff
--     staff_may_correct_invoice allows; a reason; update_invoice_internal
--     told it is settled) when it is not a draft or unpaid, OR it has a
--     payment recorded (as before), OR it was ever settled (locked_at set),
--     OR it is a refund top-up or an exchange's replacement invoice (which
--     can_edit_invoice never lets anyone edit). Only the rest, a draft or
--     unpaid invoice never settled, with no payment, is an ordinary edit
--     (can_edit_invoice, no reason), as before.
--   * staff_may_correct_invoice is unchanged (paid and part-paid only), so
--     staff are refused on a completed FOC invoice, on one unpaid again after
--     its FOC came off, and on a top-up or exchange invoice, with 377's
--     words.
--   * A removed line still on record elsewhere stays: the save is refused in
--     words ("A line you removed has a refund recorded against it, so it
--     stays on the invoice ... Keep the line.", the same for a line paid
--     with the customer's credit, and a general one naming the record for
--     anything else) instead of the database's.
--   * Vouchers are given when an invoice is paid in full (or completed FOC),
--     and their stock is taken then: a correction that leaves an invoice
--     settled once unpaid or part-paid keeps no voucher stock for its lines
--     (what it takes for them it gives back in the same save, as 416 does for
--     a save that stays FOC); its products are put back and taken again, as
--     for any settled invoice (as before). So a cancel, a delete or a lower
--     quantity before payment leaves the voucher stock whole.
--
-- WHAT THIS DOES
--
--   1. correct_invoice(uuid,jsonb,jsonb,text,uuid) (456's text): works out
--      once, in a new variable, whether the invoice is corrected as a settled
--      one (above), and uses it in the three places that asked "not draft or
--      unpaid, or a payment recorded": the Owner / Manager / staff and reason
--      check, the can_edit_invoice check (now only for an ordinary edit), and
--      the p_allow_settled it passes update_invoice_internal. Four anchors
--      (the variable, those three). And where 416 gives back what
--      deduct_invoice_stock took for voucher lines on a save that stays FOC,
--      it does the same on a save that leaves the invoice unpaid or part-paid
--      (only an invoice settled once gets there so: 399), its row reading
--      "Not paid in full, nothing given yet (taken at payment): <reason>"
--      (416's wording kept for a save that stays FOC). Two anchors (that
--      condition and that row's reason).
--   2. update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,
--      text,boolean): the delete of the lines a save removes runs in its own
--      block; a foreign-key refusal there is raised again in words (a refund
--      recorded against the line, the customer's credit paid against it, or
--      the record that holds it), the constraint in the detail. One anchor.
--   The Invoices page (src/pages/InvoicesPage.tsx, not this file): Correct
--   Invoice in the completed FOC footer (behind canCorrectInvoice: Owners and
--   Managers; staff and Inventory Managers never); a once-settled (locked)
--   unpaid invoice gets Correct Invoice (Owners and Managers), not Edit
--   Invoice, and the form asks for the reason (also on a top-up or exchange
--   invoice); Make FOC / Remove FOC are not offered on a locked invoice; the
--   instalment fields are hidden, and not sent, when correcting a completed
--   FOC invoice.
--
-- NOT CHANGED
--
--   * Everything else correct_invoice does: the FOC rules of 416 (what Confirm
--     FOC took recorded as rows, a save that stays FOC keeps no extra voucher
--     stock and gives no voucher, taking the FOC off takes back the unused
--     vouchers and returns their stock, audited), product stock (a
--     once-settled invoice puts back and takes again what it holds, as
--     invoice_before_full_payment already counts it settled), voucher stock
--     on a save that settles the invoice or keeps it settled, commission
--     (reconcile_invoice_commissions), therapy (correct_invoice_therapy_
--     sessions, 362), credit (355, 356), the 456 printed note, the status it
--     works out, the revision, the 'invoice_corrected' audit row, the
--     correction summary (preview_invoice_correction calls it).
--   * Everything else update_invoice_internal does, including its refusals
--     of any line change on a refund top-up or exchange invoice (so those
--     stay header-only), and 416's refusal of removing a line that gave
--     vouchers (checked before the delete, as before).
--   * can_edit_invoice, staff_may_correct_invoice, lock_settled_invoice and
--     its trigger, apply_line_foc, remove_line_foc, confirm_foc_invoice,
--     record_invoice_payment (its full payment still takes what the invoice
--     lacks, net, and the vouchers are given then), deduct_invoice_stock,
--     cancel_invoice_recorded, delete_invoice, update_invoice (the old path:
--     it asks can_edit_invoice before it calls correct_invoice, so a locked, top-up
--     or exchange invoice is still refused there, "Use the Owner/Manager
--     correction workflow for this invoice"; correct_invoice is
--     update_invoice_internal's only caller), the late-fee guards (396:
--     correct_invoice still refuses a late fee's line and affiliate; the page
--     still offers no correction on a late fee), the exchange holds (408),
--     451's functions,
--     invoice_transferable_benefits and move_invoice_benefits_to_customer
--     (correct_invoice calls them; not pinned), every table, column, policy
--     and grant.
--
-- NOT COVERED (to tell the owner)
--
--   * locked_at is still never cleared: an invoice once settled is corrected
--     as a settled one from then on (an Owner or Manager, a reason). An
--     invoice whose FOC came off still cannot take Make FOC / Remove FOC
--     ("Invoice is locked"; the page no longer offers them there): give or
--     take FOC through Correct Invoice on it.
--   * A corrected completed FOC invoice that stays FOC still gives no extra
--     vouchers for a voucher line raised or added (416's rule, kept): make a
--     new FOC invoice for the extra.
--   * A line with a refund recorded against it, or paid with the customer's
--     credit, can never be removed (the record stays with the line); the
--     save now says so. Reopening the invoice does not change that.
--   * A once-settled invoice is corrected as settled in product stock (as
--     invoice_before_full_payment already counted it, 399): a correction that
--     changes its lines puts back and takes again the stock of all its
--     products, though it is unpaid (a removed product goes back on the
--     shelf; an added one is recorded as out). Its voucher lines' units are
--     taken and given back in the same save, so the store must still hold
--     them: short, the correction is refused ("Not enough voucher stock"), as
--     the payment would be. Tested: two vouchers, none kept at the
--     correction (still 10), two taken at the payment (8), two given.
--   * Not new, unchanged here (to tell the owner): on an invoice already
--     paid, a voucher line raised by a correction takes the extra unit (at
--     the correction, or now at the payment that settles it again) but gives
--     no extra voucher (the issuers skip a line that gave vouchers before):
--     tested, paid S$180 for two, one voucher held, two units out. A cancel
--     gives both back. Raise it with the owner separately.
--   * Staff may still delete an invoice settled once and unpaid again when
--     it has no payment and no goods out (417's rule: unpaid, no payment);
--     its voucher stock is whole by then, so nothing is lost.
--   * On a paid invoice with a line refunded the way refunds are recorded
--     today (they name the payment, not the line), removing that line is
--     still refused by 253's commission check ("Commission
--     review required: a refunded original invoice line is unavailable on
--     invoice ..."); on a fully refunded invoice it saves, as before.
--   * Read, not run on production: an invoice that never took product stock
--     (for example a therapy-only FOC) takes none when a correction adds a
--     product (172's rule for paid invoices too); unchanged here.
--   * Staff still cannot correct a completed FOC invoice; they raise a
--     refund / cancel request (377, the Owner's choice A of 22 Oct 2026).
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (451-455, 460 and 461 in: 037095a507480dafd8381a6d3d8add90,
--   1374 functions) -> 456 -> 457 (this file) -> 458 (this round of 22 Oct 2026).
--   * 456 must be in first: this file's BEFORE for correct_invoice is 456's
--     AFTER (e174a2fd...), and 456 pins update_invoice_internal (8e674fe0...)
--     as relied on: run after this file, 456 refuses (as it should: it is in
--     already). 456's suite (print-note-456.sql) runs with -v skip_install=1
--     once this file is in; its G2 and G4 take either 456's or this file's
--     AFTERs. 458, if it changes correct_invoice or update_invoice_internal,
--     takes this file's AFTERs as its BEFOREs.
--   * Another session's 460 and 461 went live first (24 Oct 2026:
--     20261024003624 and 20261024003655). They changed no function this file
--     changes or pins (re-read on production after them), so nothing was
--     re-pinned; 460's 'transfer' customer change now always writes its
--     'invoice_benefits_followed_reassignment' row (in move_invoice_benefits_
--     to_customer, not changed here). What was planned for either order:
--     - 461 (invoice_transferable_benefits, maybe move_invoice_benefits_to_
--       customer) changes no function this file changes or pins: either
--       order, nothing to re-pin.
--     - 460 (credit and vouchers a reopened invoice gives back follow a
--       customer change) may change apply_reopened_invoice_benefits,
--       apply_reopened_invoice_vouchers and reopen_invoice (not pinned here),
--       and possibly correct_invoice's transfer path or move_invoice_benefits_
--       to_customer. correct_invoice is SHARED. If 460 goes first and changes
--       it, this file refuses, naming it, and changes nothing: re-read
--       correct_invoice after 460, re-check the six anchors (in the declare
--       section, the access, can_edit and update_invoice_internal calls, and
--       416's voucher give-back after deduct_invoice_stock; not the transfer
--       path), re-pin the BEFORE (460's AFTER) and the AFTER here, in the
--       suite (G1), in print-note-456.sql (G2) and in 458, and re-test. The
--       same if 460 changes a function pinned as relied on below
--       (cancel_invoice_recorded, deduct_invoice_stock and the rest; 460 is
--       not expected to). If this file goes first, 460 must take this
--       file's AFTER for correct_invoice as its BEFORE (and
--       update_invoice_internal's, if it changes that). The same holds for
--       any other file that changes a function pinned below.
--   1. Dry run on a copy of production as it is then (456 in): apply this
--      file twice; the first run ends at the fingerprint below, the second
--      changes nothing ("already this version; left alone" for both
--      functions).
--   2. Apply (the CLI, or the MCP's apply_migration with this text verbatim).
--      It checks itself. The first draft of this file (correct_invoice
--      918dd5e5...) was never applied anywhere but local copies; a copy that
--      has it is refused (neither BEFORE nor AFTER): make the copy again.
--   3. Then deploy the page (InvoicesPage.tsx). The new page before 457
--      would offer Correct Invoice on a once-settled unpaid invoice, which
--      the server would still refuse ("You cannot edit this invoice"): the
--      migration first. An open page from before 457 keeps offering Edit
--      Invoice there; the server now answers it "A correction reason is
--      required" (it asks for none): reload the page.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the functions it relies on are as read on production now with 456 in
--     (23-24 Oct 2026, on a copy of it), and the triggers lock_on_settle and
--     issue_sold_vouchers_on_paid with them; the invoices columns it reads
--     are there with these types; the two
--     foreign keys its messages name are there (NO ACTION);
--   * each patched function is its BEFORE (patched; each anchor found once;
--     the text built has the tested AFTER md5) or its AFTER (left alone), so
--     a second run changes nothing; no other function takes their names;
--   * afterwards: both md5s are the AFTER ones; both keep their grants
--     (compared as sets); correct_invoice stays callable by signed-in staff
--     and the service role, never anon, and still reads the invoice for
--     update and checks store access before anything else;
--     update_invoice_internal stays the service role's (and the owner's),
--     never anon's or signed-in staff's;
--   * then a self-test, in a block that is always undone (it ends by raising
--     P0457, so it leaves no row): a made-up Owner, store, payment method,
--     buyer (an ACMA fictional phone no customer has), S$20 product and S$30
--     limited voucher, five of each in stock. An invoice for one of each,
--     made FOC and confirmed (completed FOC, locked, 4 and 4 left); a
--     correction takes the FOC off (unpaid, still locked, no payment, the
--     voucher back: 5); a second correction without a reason is refused ("A
--     correction reason is required"; before this file: "You cannot edit this
--     invoice"); with one, two vouchers: saved (unpaid, S$80, two revisions;
--     the product still out, 4; no voucher stock kept, 5, rows net 0); paid
--     in full: paid, two vouchers given, 3 left.
--   It reads only, apart from the two functions and the self-test's rows
--   (undone). Locks: the two functions' catalogue rows, to the end of the
--   apply, and the self-test's own rows. The whole apply took under 0.3 s on
--   a copy of production with no business rows (0.19 s, 24 Oct 2026). A
--   correction running at that moment finishes on the text it started with.
--
-- BEFORE (production now with 456 in, read on a copy of it, 23-24 Oct 2026; md5
-- of pg_get_functiondef with search_path public)
--   changed
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                    e174a2fde4ad5bb158e6f306b0b944e5  (456's AFTER)
--   update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean) 8e674fe0d5e35ed5c2e93d417f14c05a  (as at 416; 456 pins it)
--   relied on, not changed
--   can_edit_invoice(uuid)                                         22f496c486ee4f0dfd45c68da6240ac2
--   staff_may_correct_invoice(uuid)                                60cbe4859f1f1f43da02115c019fc4bf
--   lock_settled_invoice(uuid)                                     ccc7016ac73d9a13142980386a5929dc
--   trg_lock_on_settle()                                           39c6478cdaec553c2ab8ceaf55058960
--   invoice_before_full_payment(uuid)                              532d7690367fc674737b20420e7fb16c
--   preview_invoice_correction(uuid,jsonb)                         2bb7c0a5769050d5b2f9247a3aa05ecd
--   invoice_revision_retry(uuid,uuid,jsonb)                        5c33c50a8f6870d8a66f74b63b782f24
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   create_invoice_with_details(uuid,uuid,jsonb,jsonb)             770ee0129b0e9fe909259ad7ea95b8d0  (456's AFTER; the self-test)
--   apply_line_foc(uuid,integer,uuid,text)                         5fbd0b6feb36e11dea6be231ffa0e952  (the self-test)
--   confirm_foc_invoice(uuid,text)                                 ba8b1ce2a5671989b927891f0cb7b1a2  (the self-test)
--   record_invoice_payment(uuid,jsonb,uuid)                        9c70097ed4da614fb9dcc66fdfcdb7d6  (the self-test)
--   deduct_invoice_stock(uuid,text)                                32183fe9e7c15ed0b11307c48289831a
--   invoice_stock_to_deduct(uuid)                                  6356494ccb8545d46c56b788f8f85f54
--   invoice_record_payments_internal(uuid,jsonb)                   21890d84bcb0b9c00a2bc98aff313d0b
--   trg_issue_sold_vouchers_on_paid()                              c840d0d2754e7a8e889848ea8269a293
--   cancel_invoice_recorded(uuid,text,uuid)                        de52d9dbaef8ab15163bef35cb9d733d
--   delete_invoice(uuid,text)                                      530b8217e94c9bbb0765c47da2d8d40e
--   set_product_prices(uuid,uuid,numeric,numeric,text)             aef4792013bc3a56f8ee62bc1a7d686a  (the self-test)
--   public function fingerprint, 451-455 in (before 460 and 461)   b43a0781217fd1b4027749deafbddca7 (1372 functions)
--   public function fingerprint, production now (460 and 461 in)   037095a507480dafd8381a6d3d8add90 (1374 functions)
--   public function fingerprint, production now -> 456             09e03ea7e0e87b22e900b06ffa497347 (1374 functions)
-- AFTER (for later guards: 458, 460)
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                    45e7f523e50a6b423b6e1d9f8836ebb6
--   update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean) 1f034561a461bdb46a1e6274e0d04606
--   public function fingerprint, worked out on a copy of production (24 Oct 2026):
--     production now -> 456 -> 457 (a second run the same)         11840d5ac3aa7f5fc4a26020a7b2d0ce (1374 functions: none added or dropped)
--     (on 451-455 alone: be4cbd87a8393e40264832eb0e9ebd89, 1372)
--
-- Test: scripts/invoices/tests/foc-correct-again-457.sql (begin ... rollback;
-- it installs this file twice, or -v skip_install=1 where it is installed).
-- scripts/invoices/tests/page-checks-416.test.mjs checks the page's footer
-- branches; staff-correct-browser.mjs drives them in Chrome. Fixtures only
-- (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The two functions: BEFORE (production now, 456 in) and AFTER md5s ══
  c_sigs constant text[] := array[
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)'];
  c_before constant text[] := array[
    'e174a2fde4ad5bb158e6f306b0b944e5',
    '8e674fe0d5e35ed5c2e93d417f14c05a'];
  c_after constant text[] := array[
    '45e7f523e50a6b423b6e1d9f8836ebb6',
    '1f034561a461bdb46a1e6274e0d04606'];
  -- each anchor (found once in its function's BEFORE text), the function it
  -- is in (an index into c_sigs) and its patch, in order
  c_fn constant int[] := array[1, 1, 1, 1, 1, 1, 2];
  c_anchor constant text[] := array[
$a1$ v377_staff boolean := false;
$a1$,
$a2$ if i.status not in ('draft','unpaid') or exists(select 1 from public.invoice_payments where invoice_id=i.id) then
   -- 377: staff correct a paid or part-paid invoice of their own store
$a2$,
$a3$ if i.status in ('draft','unpaid') and not exists(select 1 from public.invoice_payments where invoice_id=i.id) and not public.can_edit_invoice(i.id) then raise exception 'You cannot edit this invoice'; end if;
$a3$,
$a4$    i.status not in ('draft','unpaid') or exists(select 1 from public.invoice_payments where invoice_id=i.id));
$a4$,
$a5$   if i.status = 'completed_foc' and v_status = 'completed_foc' then
     for v416_v in select mv.voucher_id, mv.store_id, mv.quantity from public.invoice_voucher_movements mv
$a5$,
$a6$               'Still FOC, nothing given for the change: ' || p_reason, auth.uid());
$a6$,
$a7$  delete from public.invoice_items ii where invoice_id = p_invoice_id
    and not exists(select 1 from jsonb_array_elements(p_items) x where nullif(x->>'invoice_item_id','')::uuid=ii.id);
$a7$];
  c_patch constant text[] := array[
$p1$ v377_staff boolean := false;
 v457_settled boolean;  -- 457: corrected as a settled invoice (an Owner or Manager, a reason)
$p1$,
$p2$ -- 457 (the Owner, 22 Oct 2026): every invoice has its correct path. A
 -- settled one is corrected by an Owner or Manager (or staff where 377
 -- allows), with a reason: not a draft or unpaid invoice, or one with a
 -- payment (as before), or one ever settled (locked_at: a completed FOC
 -- whose FOC a correction took off is unpaid again but locked, and
 -- can_edit_invoice refused it to everyone), or a refund top-up or an
 -- exchange's replacement invoice (can_edit_invoice never lets anyone edit
 -- them; update_invoice_internal keeps their lines). The rest, a draft or
 -- unpaid invoice never settled with no payment, is an ordinary edit.
 v457_settled := i.status not in ('draft','unpaid') or i.locked_at is not null
   or coalesce(i.is_topup,false) or coalesce(i.is_exchange,false)
   or exists(select 1 from public.invoice_payments where invoice_id=i.id);
 if v457_settled then
   -- 377: staff correct a paid or part-paid invoice of their own store
$p2$,
$p3$ if not v457_settled and not public.can_edit_invoice(i.id) then raise exception 'You cannot edit this invoice'; end if;  -- 457: an ordinary edit only
$p3$,
$p4$    v457_settled);  -- 457: settled as worked out above
$p4$,
$p5$   -- 457 (the Owner, 22 Oct 2026): a save that leaves the invoice unpaid or
   -- part-paid gives no voucher either (vouchers are given when it is paid in
   -- full), so it keeps no voucher stock for its lines: what
   -- deduct_invoice_stock just took for a voucher line goes back, with a row
   -- that cancels its row, and the payment that settles the invoice takes it
   -- then, net. Only an invoice settled once (paid or completed FOC since it
   -- was last reopened) gets here unsettled. Kept, those units were out with
   -- no voucher given: a cancel gave back one unit too few for a voucher the
   -- FOC removal had taken back (it counts that voucher as given), a delete
   -- gave back none, and lowering the line before payment gave none back.
   if (i.status = 'completed_foc' and v_status = 'completed_foc') or v_status in ('unpaid','partially_paid') then
     for v416_v in select mv.voucher_id, mv.store_id, mv.quantity from public.invoice_voucher_movements mv
$p5$,
$p6$               case when v_status = 'completed_foc' then 'Still FOC, nothing given for the change: '
                    else 'Not paid in full, nothing given yet (taken at payment): ' end || p_reason, auth.uid());  -- 457
$p6$,
$p7$  -- 457 (the Owner, 22 Oct 2026): a removed line still on record elsewhere
  -- (a refund recorded against it, the customer's credit paid against it)
  -- stays, and the save says so in words, not the database's.
  declare v457_tab text; v457_con text;
  begin
    delete from public.invoice_items ii where invoice_id = p_invoice_id
      and not exists(select 1 from jsonb_array_elements(p_items) x where nullif(x->>'invoice_item_id','')::uuid=ii.id);
  exception when foreign_key_violation then
    get stacked diagnostics v457_tab = table_name, v457_con = constraint_name;
    raise exception '%', case v457_tab
        when 'invoice_refunds' then 'A line you removed has a refund recorded against it, so it stays on the invoice. Keep the line.'
        when 'invoice_line_credit_allocations' then 'A line you removed was paid with the customer''s credit, which is recorded against it, so it stays on the invoice. Keep the line; to give the credit back, refund it.'
        else format('A line you removed is still on record in %s, so it stays on the invoice. Keep the line.', replace(v457_tab, '_', ' ')) end
      using detail = format('%s on %s', v457_con, v457_tab);
  end;
$p7$];

  -- ══ Relied on, not changed (production now, 456 in) ════════════════════
  c_relied constant text[] := array[
    'can_edit_invoice(uuid)',
    'staff_may_correct_invoice(uuid)',
    'lock_settled_invoice(uuid)',
    'trg_lock_on_settle()',
    'invoice_before_full_payment(uuid)',
    'preview_invoice_correction(uuid,jsonb)',
    'invoice_revision_retry(uuid,uuid,jsonb)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'create_invoice_with_details(uuid,uuid,jsonb,jsonb)',
    'apply_line_foc(uuid,integer,uuid,text)',
    'confirm_foc_invoice(uuid,text)',
    'record_invoice_payment(uuid,jsonb,uuid)',
    'deduct_invoice_stock(uuid,text)',
    'invoice_stock_to_deduct(uuid)',
    'invoice_record_payments_internal(uuid,jsonb)',
    'trg_issue_sold_vouchers_on_paid()',
    'cancel_invoice_recorded(uuid,text,uuid)',
    'delete_invoice(uuid,text)',
    'set_product_prices(uuid,uuid,numeric,numeric,text)'];
  c_relied_md5 constant text[] := array[
    '22f496c486ee4f0dfd45c68da6240ac2',
    '60cbe4859f1f1f43da02115c019fc4bf',
    'ccc7016ac73d9a13142980386a5929dc',
    '39c6478cdaec553c2ab8ceaf55058960',
    '532d7690367fc674737b20420e7fb16c',
    '2bb7c0a5769050d5b2f9247a3aa05ecd',
    '5c33c50a8f6870d8a66f74b63b782f24',
    'c705c733e213a27f0dc32d54322cc855',
    '770ee0129b0e9fe909259ad7ea95b8d0',
    '5fbd0b6feb36e11dea6be231ffa0e952',
    'ba8b1ce2a5671989b927891f0cb7b1a2',
    '9c70097ed4da614fb9dcc66fdfcdb7d6',
    '32183fe9e7c15ed0b11307c48289831a',
    '6356494ccb8545d46c56b788f8f85f54',
    '21890d84bcb0b9c00a2bc98aff313d0b',
    'c840d0d2754e7a8e889848ea8269a293',
    'de52d9dbaef8ab15163bef35cb9d733d',
    '530b8217e94c9bbb0765c47da2d8d40e',
    'aef4792013bc3a56f8ee62bc1a7d686a'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; n int; i int; k int;
  v_texts text[] := array[null, null]::text[]; v_acls text[] := array[null, null]::text[];
  -- the self-test's made-up records
  t_sfx text; t_phone text; t_owner uuid; t_store uuid; t_cash uuid; t_vch uuid; t_buyer uuid; t_prod uuid; t_item uuid;
  t_inv uuid; t_lines jsonb; t_msg text; t_edits int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── 1. Checks: nothing is changed before all of them pass ──────────────
  -- What it relies on and does not change: as read on production with 456
  -- in, 23-24 Oct 2026.
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '457: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'lock_on_settle'
                   and t.tgfoid = 'public.trg_lock_on_settle()'::regprocedure and t.tgenabled = 'O') then
    raise exception '457: the trigger lock_on_settle on invoices is missing or not as read on 23 Oct 2026'; end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoices'::regclass and t.tgname = 'issue_sold_vouchers_on_paid'
                   and t.tgfoid = 'public.trg_issue_sold_vouchers_on_paid()'::regprocedure and t.tgenabled = 'O') then
    raise exception '457: the trigger issue_sold_vouchers_on_paid on invoices is missing or not as read on 24 Oct 2026'; end if;

  -- The columns it reads, with these types.
  select string_agg(x.c || ' ' || x.ty, ', ') into v
    from (values ('id', 'uuid'), ('status', 'invoice_status'), ('locked_at', 'timestamp with time zone'),
                 ('is_topup', 'boolean'), ('is_exchange', 'boolean'), ('total_amount', 'numeric(12,2)'),
                 ('paid_amount', 'numeric(12,2)'), ('edit_count', 'integer'), ('deleted_at', 'timestamp with time zone')) x(c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = 'public.invoices'::regclass and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '457: these invoices columns are missing or not as read on 23 Oct 2026: %', v; end if;
  -- The two foreign keys the plain messages name, as read (NO ACTION).
  select string_agg(x.t, ', ') into v
    from (values ('invoice_refunds'), ('invoice_line_credit_allocations')) x(t)
   where not exists (select 1 from pg_constraint c where c.contype = 'f' and c.confrelid = 'public.invoice_items'::regclass
                      and c.conrelid = to_regclass('public.' || x.t) and c.confdeltype = 'a');
  if v is not null then raise exception '457: no NO ACTION foreign key to invoice_items on: %', v; end if;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('correct_invoice', 'update_invoice_internal')
     and p.oid::regprocedure::text <> all (c_sigs);
  if v is not null then raise exception '457: another function takes the name of one this changes: %', v; end if;

  -- Each patched function: its BEFORE (patched; each anchor found once; the
  -- text built has its AFTER md5) or its AFTER (left alone).
  for k in 1 .. cardinality(c_sigs) loop
    if to_regprocedure('public.' || c_sigs[k]) is null then raise exception '457: public.% is missing', c_sigs[k]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sigs[k]));
    -- its grants, to compare after (as sets: production lists them in
    -- another order than a local copy does)
    v_acls[k] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                    from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[k]));
    if md5(d) = c_after[k] then
      raise notice '457: public.% is already this version; left alone', c_sigs[k];
      continue;
    end if;
    if md5(d) <> c_before[k] then
      raise exception '457: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sigs[k], md5(d); end if;
    for i in 1 .. cardinality(c_anchor) loop
      continue when c_fn[i] <> k;
      n := (length(d) - length(replace(d, c_anchor[i], ''))) / length(c_anchor[i]);
      if n <> 1 then raise exception '457: anchor % of public.% was found % times, not once', i, c_sigs[k], n; end if;
      d := replace(d, c_anchor[i], c_patch[i]);
    end loop;
    if md5(d) <> c_after[k] then
      raise exception '457: the text built for public.% is not the tested one (md5 %)', c_sigs[k], md5(d); end if;
    v_texts[k] := d;
  end loop;

  -- ── 2. Install ──────────────────────────────────────────────────────────
  for k in 1 .. cardinality(c_sigs) loop
    if v_texts[k] is not null then execute v_texts[k]; end if;
  end loop;

  -- ── 3. Checks after installing ──────────────────────────────────────────
  for k in 1 .. cardinality(c_sigs) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[k]))) <> c_after[k] then
      raise exception '457: public.% was installed with an md5 other than the tested one', c_sigs[k]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[k])) is distinct from v_acls[k]
       or has_function_privilege('anon', 'public.' || c_sigs[k], 'execute')
       or not has_function_privilege('service_role', 'public.' || c_sigs[k], 'execute') then
      raise exception '457: the grants of public.% changed', c_sigs[k]; end if;
  end loop;
  -- correct_invoice: signed-in staff may call it; update_invoice_internal:
  -- never (only the functions that call it, as the definer).
  if not has_function_privilege('authenticated', 'public.' || c_sigs[1], 'execute')
     or has_function_privilege('authenticated', 'public.' || c_sigs[2], 'execute') then
    raise exception '457: correct_invoice must be callable by signed-in staff and update_invoice_internal must not be'; end if;
  -- correct_invoice still reads the invoice for update and checks store
  -- access before anything else.
  d := pg_get_functiondef(to_regprocedure('public.' || c_sigs[1]));
  if position(E'\nbegin\n select * into i from public.invoices where id=p_invoice_id for update;\n'
              || E' if not found or i.deleted_at is not null then raise exception ''Invoice not found''; end if;\n'
              || E' if not public.user_has_store_access(i.store_id) then raise exception ''No access to this invoice''; end if;\n' in d) = 0 then
    raise exception '457: public.% no longer checks store access first', c_sigs[1]; end if;

  -- ── 4. Self-test, in a block that is always undone ─────────────────────
  -- Made-up records only ("457 check", @example.com, a fictional ACMA
  -- phone no customer uses); it ends by raising P0457, which undoes all it
  -- wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    select x into t_phone
      from (select '+6125550' || lpad(g::text, 4, '0') as x from generate_series(4570, 4609) g) y
     where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = y.x)
     order by x limit 1;
    if t_phone is null then raise exception '457: the self-test found no unused fictional phone'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '457-check-' || t_sfx || '@example.com') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '457 check', '457-check-' || t_sfx || '@example.com', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('457 check ' || t_sfx, '457-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('457 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.customers (full_name, phone) values ('457 Check Customer ' || t_sfx, t_phone) returning id into t_buyer;
    insert into public.vouchers (name, code, voucher_kind, selling_price, qty_type, is_active)
    values ('457 check ' || t_sfx, '457-' || t_sfx, 'normal', 30, 'limited', true) returning id into t_vch;
    insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store) values (t_vch, t_store, 30, true);
    insert into public.voucher_store_stock (voucher_id, store_id, current_qty) values (t_vch, t_store, 5);
    insert into public.products (name, sku, product_type) values ('457 check ' || t_sfx, '457-' || t_sfx, 'own') returning id into t_prod;
    insert into public.store_inventory (store_id, product_id, current_qty) values (t_store, t_prod, 5);
    perform public.set_product_prices(t_store, t_prod, 20, 20, 'available');

    -- A product and a voucher (5 of each in stock), made FOC and confirmed:
    -- completed FOC, locked, one of each taken.
    t_inv := public.create_invoice_with_details(t_store, t_buyer,
      jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', t_prod, 'quantity', 1),
                        jsonb_build_object('kind', 'voucher', 'voucher_id', t_vch, 'quantity', 1)),
      jsonb_build_object('business_date', public.sg_today()));
    for t_item in select it.id from public.invoice_items it where it.invoice_id = t_inv order by it.id loop
      perform public.apply_line_foc(t_item, null, null, '457 check'); end loop;
    perform public.confirm_foc_invoice(t_inv, null);
    if (select (status::text, locked_at is not null) is distinct from ('completed_foc'::text, true) from public.invoices where id = t_inv)
       or (select current_qty from public.store_inventory where store_id = t_store and product_id = t_prod) <> 4
       or (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch) <> 4 then
      raise exception '457: the self-test''s invoice is not completed FOC and locked with one of each taken'; end if;

    -- A correction takes the FOC off: unpaid, still locked, no payment; the
    -- product stays out, the voucher is taken back and its stock returned.
    select coalesce(edit_count, 0) into t_edits from public.invoices where id = t_inv;
    select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind::text, 'product_id', it.product_id,
                                        'voucher_id', it.voucher_id, 'quantity', it.quantity, 'unit_price', it.unit_price,
                                        'foc_quantity', 0) order by it.id)
      into t_lines from public.invoice_items it where it.invoice_id = t_inv;
    perform public.correct_invoice(t_inv, t_lines, jsonb_build_object('expected_edit_count', t_edits), '457 check: FOC off', gen_random_uuid());
    if (select (status::text, locked_at is not null, total_amount) is distinct from ('unpaid'::text, true, 50::numeric)
          from public.invoices where id = t_inv)
       or exists (select 1 from public.invoice_payments where invoice_id = t_inv)
       or (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch) <> 5 then
      raise exception '457: taking the FOC off did not leave the invoice unpaid and locked, its voucher back in stock (%)',
        (select jsonb_build_object('status', status, 'locked', locked_at is not null, 'total', total_amount) from public.invoices where id = t_inv); end if;

    -- Corrected again: as a settled invoice, so a reason is asked for.
    select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind::text, 'product_id', it.product_id,
                                        'voucher_id', it.voucher_id, 'quantity', case when it.voucher_id is not null then 2 else it.quantity end,
                                        'unit_price', it.unit_price, 'foc_quantity', 0) order by it.id)
      into t_lines from public.invoice_items it where it.invoice_id = t_inv;
    begin
      perform public.correct_invoice(t_inv, t_lines, '{}'::jsonb, ' ', gen_random_uuid());
      t_msg := null;
    exception when others then t_msg := sqlerrm;
    end;
    if t_msg is distinct from 'A correction reason is required' then
      raise exception '457: correcting the once-settled unpaid invoice again without a reason was not asked for one (%)', coalesce(t_msg, 'saved'); end if;
    -- With one, two vouchers: saved, still unpaid; the product still out (put
    -- back and taken again), and no voucher stock kept before the payment.
    perform public.correct_invoice(t_inv, t_lines, jsonb_build_object('expected_edit_count', t_edits + 1), '457 check: two', gen_random_uuid());
    if (select (status::text, total_amount, paid_amount, coalesce(edit_count, 0)) is distinct from ('unpaid'::text, 80::numeric, 0::numeric, t_edits + 2)
          from public.invoices where id = t_inv)
       or (select count(*) from public.invoice_revisions where invoice_id = t_inv) <> 2
       or (select count(*) from public.invoice_revisions where invoice_id = t_inv and edit_reason = '457 check: two'
             and after_snapshot->'invoice'->>'total_amount' = '80.00') <> 1
       or (select current_qty from public.store_inventory where store_id = t_store and product_id = t_prod) <> 4
       or (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch) <> 5
       or (select coalesce(sum(quantity), 0) from public.invoice_voucher_movements where invoice_id = t_inv) <> 0 then
      raise exception '457: the second correction is not as tested (%)',
        (select jsonb_build_object('status', status, 'total', total_amount, 'paid', paid_amount, 'edits', edit_count,
                  'voucher_stock', (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch))
           from public.invoices where id = t_inv); end if;

    -- Paid in full: paid; the two vouchers given and their stock taken then.
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 80)), gen_random_uuid());
    if (select status::text from public.invoices where id = t_inv) <> 'paid'
       or (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch) <> 3
       or (select coalesce(sum(v.quantity), 0) from public.customer_reward_vouchers v
             join public.invoice_benefit_values b on b.reward_voucher_id = v.id
            where b.invoice_id = t_inv and v.status = 'held') <> 2 then
      raise exception '457: the corrected invoice did not become paid with its two vouchers given from stock'; end if;

    raise exception using errcode = 'P0457', message = '457: self-test done, undone';
  exception when sqlstate 'P0457' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
