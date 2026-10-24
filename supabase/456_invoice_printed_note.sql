-- 456_invoice_printed_note.sql
--
-- A NOTE PRINTED ON THE INVOICE, APART FROM ITS INTERNAL NOTES (the Owner,
-- 22 Oct 2026, item 6, the invoice half)
--
-- WHAT WAS WRONG / WHY
--
--   The New / Edit / Correct Invoice form has a Notes box (invoices.notes),
--   but nothing ever showed it again: not the invoice screen, the printed
--   customer and office copies, the PDF or the image (and so not WhatsApp or
--   email). To the owner it looked as if an invoice could not carry a note.
--   Notes cannot simply be printed: the same column holds text the system
--   writes (website orders and their Stripe session ids, VIP orders, exchange
--   and top-up reasons, late-fee and voucher-claim references) and anything
--   staff typed while it never printed.
--
-- THE RULES (binding; the Owner's answers, 22 Oct 2026)
--
--   * A NEW field, "Note printed on the invoice", up to 500 characters,
--     separate from the existing Notes. Notes becomes "Internal notes (not
--     printed)" and never prints (it holds system text: website order and
--     Stripe ids, exchange/top-up reasons, late-fee and voucher-claim
--     references).
--   * The printed note shows on the invoice detail, prints on BOTH the
--     customer and office copies above the signatures under the heading
--     "Note", and is on the PDF and the WhatsApp/email image too.
--   * It is entered at create and at edit. On a paid invoice it changes
--     through Correct Invoice (a reason, the revision history, the audit log)
--     like any other change: no new shortcut.
--   * (Item 6, the exchange half, in the page only: an exchange's own note,
--     product_exchanges.notes, which 455's exchange_invoice_details returns
--     as 'notes', prints under "Exchange Details" on its replacement invoice's
--     print, PDF and image.)
--   How it reads (this file, 22 Oct 2026):
--   * Stored as typed, less the spaces, tabs and line breaks around it (the
--     line breaks inside it are kept and printed); blank is none (null).
--     More than 500 characters is refused, in words (PRINT_NOTE_TOO_LONG),
--     and by a check on the column.
--   * create_invoice_with_details (the New Invoice form) stores
--     header.print_note with the invoice it makes. A replayed request (416's
--     request_id) returns the invoice it made, as before; the note is part of
--     the request, so the same request id with another note is refused as any
--     other change to the form is (416, CREATE-15).
--   * correct_invoice (Edit Invoice and Correct Invoice, and the correction
--     summary through preview_invoice_correction) sets it when the header
--     names print_note (blank: none) and keeps it when it does not (an older
--     page, update_invoice). Its rules are unchanged: an unpaid invoice with
--     no payment, can_edit_invoice, no reason needed; a paid, part-paid,
--     cancelled or refunded one, an Owner or Manager, or staff allowed by
--     staff_may_correct_invoice (their own store, no refund or cancellation
--     request waiting), with a reason. A changed note is a change (the whole
--     row is compared), so it writes the revision (invoice_revisions, the
--     row before and after) and the 'invoice_corrected' audit row (the row
--     before and after), counts an edit, and, not being a change of lines,
--     discount, store or customer, moves no money, stock, commission, credit
--     or therapy (384's rule, as for Notes).
--
-- WHAT THIS DOES
--
--   1. invoices.print_note text, nullable, no default, with the check
--      invoices_print_note_length (null, or at most 500 characters).
--   2. create_invoice_with_details(uuid,uuid,jsonb,jsonb): reads
--      header.print_note (trimmed; refused past 500 characters) before the
--      invoice is made, and writes it in the update that already follows
--      create_invoice (business date, instalment, discount reason, request).
--      Three anchors: a variable, the check after the discount-reason check,
--      the column in that update.
--   3. correct_invoice(uuid,jsonb,jsonb,text,uuid): after "notes", the same
--      for print_note when the header names it; the column in the update
--      that already writes notes. Two anchors.
--
-- NOT CHANGED
--
--   * invoices.notes and every function that writes it: create_invoice,
--     update_invoice_internal (correct_invoice already writes print_note
--     before it calls it, and it never writes print_note: it sets named
--     columns), update_invoice (sends no print_note: kept), web_order_make_
--     invoice, event_vip_make_invoices, create_exchange_invoice,
--     create_topup_invoice, the late-fee and voucher-claim invoices: their
--     text stays in the internal notes and prints nowhere.
--   * preview_invoice_correction (it hands the header to correct_invoice and
--     so sees the note), invoice_revision_retry, write_audit_ex,
--     staff_may_correct_invoice, can_edit_invoice, record_invoice_payment,
--     exchange_invoice_details (455's) and every other function, table,
--     policy and grant. The invoices table keeps its grants and its one
--     policy ("read invoices"); clients still cannot update it directly.
--   * 451's functions (reopen_invoice, invoice_reopen_preview_before_
--     sessions, refund_invoice_recorded, invoice_voucher_reopen_candidates,
--     apply_reopened_invoice_vouchers, invoice_action_plan, cancelled_
--     invoice_used_value), apply_reopened_invoice_benefits, invoice_
--     transferable_benefits and move_invoice_benefits_to_customer: not
--     touched, not pinned (correct_invoice calls the last two; its text, which
--     is pinned, is what matters here).
--
-- NOT COVERED (to tell the owner)
--
--   * Invoices with no Edit or Correct button on the Invoices page (an unpaid
--     exchange or top-up invoice, a late fee, a completed FOC invoice: item 9)
--     can be given a printed note only once item 9 opens them to editing; the
--     server would take one through correct_invoice.
--   * Invoices the system makes (website orders, VIP orders, exchanges,
--     top-ups, late fees, voucher claims) are made with no printed note.
--   * The paper copy is still two fixed halves of one A4 sheet (item 5): the
--     note is never squeezed (only the credit balance gives way there), but a
--     very long invoice with a long note can still run the foot of a half
--     (terms, policy, store footer) past its bottom edge. The PDF never cuts
--     it (the tail of a long note goes on to the next page) and the image
--     grows taller; on both, nothing above the note (the payments, the goods,
--     the credit line) shortens or moves for it: they come out as on the
--     same invoice without a note.
--   * Old internal Notes stay internal: nothing moves from notes to
--     print_note.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (451-455, 460 and 461 in: 037095a507480dafd8381a6d3d8add90,
--   1374 functions) -> 456 -> 457 -> 458 (this round of 22 Oct 2026; 457 or 458,
--   if it changes correct_invoice or create_invoice_with_details too, takes
--   456's AFTER as its BEFORE). None of 451-455 changed a function this file
--   changes or pins (re-read on a copy of production, 23 Oct 2026: every
--   BEFORE below is as it was at 450). The page's exchange note under
--   Exchange Details needs 455 (exchange_invoice_details' 'notes'), live.
--   Another session's 460 and 461 went live first (24 Oct 2026: 20261024003624
--   and 20261024003655). They changed no function this file changes or pins
--   (re-read on production after them: every BEFORE below as it was), so
--   nothing was re-pinned. What was planned for either order:
--   * 461 (invoice_transferable_benefits, move_invoice_benefits_to_customer)
--     changes neither function this file changes nor any it pins, and pins
--     neither of them itself (it checks their callers by name): either order,
--     nothing to re-pin.
--   * 460 (credit and vouchers a reopened invoice gives back follow a
--     customer change) may change apply_reopened_invoice_benefits,
--     apply_reopened_invoice_vouchers and reopen_invoice (not pinned here) and
--     possibly correct_invoice's transfer path or move_invoice_benefits_to_
--     customer. correct_invoice is SHARED. If 460 goes first and changes it,
--     this file refuses, naming it, and changes nothing: re-read correct_
--     invoice after 460, re-check the two anchors (in the header reading and
--     the header update, not the transfer path), re-pin the BEFORE (460's
--     AFTER) and the AFTER here, in the suite (G2) and in 457/458, and re-test.
--     If this file goes first, 460 must take e174a2fde4ad5bb158e6f306b0b944e5
--     as correct_invoice's BEFORE. The same holds for any other file that
--     changes a function pinned below.
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below, the second changes
--      nothing ("already there; left alone" for the column, "already this
--      version; left alone" for the two functions).
--   2. Apply (the CLI, or the MCP's apply_migration with this text verbatim).
--      It checks itself.
--   3. Then deploy the page (InvoicesPage.tsx, src/lib/invoicePdf.ts,
--      src/lib/invoiceImage.ts, src/lib/invoices/customerCopy.ts,
--      src/types/index.ts). An open page from before 456 sends no print_note:
--      correct_invoice keeps the note, so an older tab never clears one. The
--      new page before 456 would be refused nothing (an unknown header key
--      is ignored) but its note would be lost: migration first.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the functions it relies on are as read on production now (451-455 in,
--     23 Oct 2026, on a copy of it); the columns it reads and
--     writes are there with these types; the column it adds is absent (added)
--     or exactly as this file adds it (left alone);
--   * each patched function is its BEFORE (patched; each anchor found once;
--     the text built has the tested AFTER md5) or its AFTER (left alone), so
--     a second run changes nothing; no other function takes their names;
--   * afterwards: both md5s are the AFTER ones; both keep their grants
--     (compared as sets) and stay callable by signed-in staff and the service
--     role, never anon; each still checks access before it writes
--     (correct_invoice reads the invoice for update and checks store access
--     first; create_invoice_with_details writes only after create_invoice,
--     which checks the caller and the store);
--   * then a self-test, in a block that is always undone (it ends by raising
--     P0456, so it leaves no row): a made-up Owner, store, payment method,
--     buyer (an ACMA fictional phone no customer has) and S$30 voucher. An
--     invoice made with a printed note (spaces and line breaks around it
--     dropped, the one inside kept) and an internal note: both stored apart;
--     a 501-character note refused; paid in full; a note-only correction
--     refused without a reason; with one: the note changed, the internal
--     note, total, paid amount and status unchanged, one revision and one
--     'invoice_corrected' row holding the old and new notes, one edit
--     counted; a correction that does not name print_note keeps it; a blank
--     one clears it; 501 characters refused there too.
--   It reads only, apart from the column, the two functions and the
--   self-test's rows (undone). Locks, each held to the end of the apply (the
--   one DO block commits as a whole): invoices, ACCESS EXCLUSIVE from the
--   column's addition on, through the self-test, so every invoice read and
--   save waits for the apply to finish (no rewrite: the column has no
--   default; the new check reads each invoice once to confirm it, under that
--   lock); and the two functions' catalogue rows. The whole apply took under
--   0.3 s on a copy of production with no business rows (24 Oct 2026); on
--   production the check's one read of the invoices table adds to that. An
--   open transaction holding invoices longer than the 5 s lock timeout stops
--   the apply there, with nothing changed. An invoice save that started
--   before the column was added finishes first, on the text it started with.
--
-- BEFORE (production now, 451-455 in, read on a copy of it, 23 Oct 2026; md5
-- of pg_get_functiondef with search_path public; each the same as at 450)
--   changed
--   create_invoice_with_details(uuid,uuid,jsonb,jsonb)             0f408a1a350b68fd86cd24109c85c05b  (416, 436)
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                    422682d6e1ada0e5d98053e74ab9f007  (447's guard)
--   relied on, not changed
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)   80c80d386a5241e63b353e35e13ef250
--   update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean) 8e674fe0d5e35ed5c2e93d417f14c05a
--   preview_invoice_correction(uuid,jsonb)                         2bb7c0a5769050d5b2f9247a3aa05ecd
--   record_invoice_payment(uuid,jsonb,uuid)                        9c70097ed4da614fb9dcc66fdfcdb7d6  (the self-test)
--   staff_may_correct_invoice(uuid)                                60cbe4859f1f1f43da02115c019fc4bf
--   can_edit_invoice(uuid)                                         22f496c486ee4f0dfd45c68da6240ac2
--   invoice_revision_retry(uuid,uuid,jsonb)                        5c33c50a8f6870d8a66f74b63b782f24
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   public function fingerprint, 451-455 in (before 460 and 461)   b43a0781217fd1b4027749deafbddca7 (1372 functions)
--   public function fingerprint, production now (460 and 461 in)   037095a507480dafd8381a6d3d8add90 (1374 functions)
-- AFTER (for later guards: 457, 458, 460)
--   create_invoice_with_details(uuid,uuid,jsonb,jsonb)             770ee0129b0e9fe909259ad7ea95b8d0
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                    e174a2fde4ad5bb158e6f306b0b944e5
--   public function fingerprint, worked out on a copy of production (23 Oct 2026):
--     production now (460 and 461 in) -> 456 (a second run the same) 09e03ea7e0e87b22e900b06ffa497347 (1374 functions: none added or dropped)
--     (on 451-455 alone, 23 Oct 2026: be1be52e07439432a0de08b2100dde27, 1372)
--
-- Test: scripts/invoices/tests/print-note-456.sql (begin ... rollback; it
-- installs this file twice, or -v skip_install=1 where it is installed).
-- scripts/invoices/tests/print-note.test.mjs checks the page, the print, the
-- PDF and the image; print-note-browser.mjs the real page, print, PDF and
-- image in Chrome. Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The column ═══════════════════════════════════════════════════════════
  c_con constant text := 'CHECK (((print_note IS NULL) OR (char_length(print_note) <= 500)))';

  -- ══ The two functions: BEFORE (production now, 451-455 in) and AFTER md5s
  c_sigs constant text[] := array[
    'create_invoice_with_details(uuid,uuid,jsonb,jsonb)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)'];
  c_before constant text[] := array[
    '0f408a1a350b68fd86cd24109c85c05b',
    '422682d6e1ada0e5d98053e74ab9f007'];
  c_after constant text[] := array[
    '770ee0129b0e9fe909259ad7ea95b8d0',
    'e174a2fde4ad5bb158e6f306b0b944e5'];
  -- each anchor (found once in its function's BEFORE text), the function it
  -- is in (an index into c_sigs) and its patch, in order
  c_fn constant int[] := array[1, 1, 1, 2, 2];
  c_anchor constant text[] := array[
$a1$ v_req uuid; v_hash text; v_prev public.invoices%rowtype;  -- 416: the form's request
$a1$,
$a2$   raise exception 'MANUAL_DISCOUNT_REASON_REQUIRED: Give the internal reason for the manual discount.'; end if;
 perform set_config('invoice.manual_discount_reason', coalesce(p_header->>'manual_discount_reason',''), true);
$a2$,
$a3$  create_request_id=v_req, create_request_hash=v_hash  -- 416
  where id=v_id;
$a3$,
$a4$ if p_header ? 'notes' then n.notes:=p_header->>'notes'; end if;
$a4$,
$a5$affiliate_selection_explicit=n.affiliate_selection_explicit,notes=n.notes,
$a5$];
  c_patch constant text[] := array[
$p1$ v_req uuid; v_hash text; v_prev public.invoices%rowtype;  -- 416: the form's request
 v456_note text;  -- 456: the note printed on the invoice
$p1$,
$p2$   raise exception 'MANUAL_DISCOUNT_REASON_REQUIRED: Give the internal reason for the manual discount.'; end if;
 -- 456 (the Owner, 22 Oct 2026): the note printed on the invoice, apart from
 -- its internal Notes, which never print. Up to 500 characters, kept without
 -- the spaces and line breaks around it; blank is none.
 v456_note := nullif(btrim(coalesce(p_header->>'print_note', ''), E' \t\r\n'), '');
 if char_length(v456_note) > 500 then
   raise exception 'PRINT_NOTE_TOO_LONG: The note printed on the invoice can be at most 500 characters.'; end if;
 perform set_config('invoice.manual_discount_reason', coalesce(p_header->>'manual_discount_reason',''), true);
$p2$,
$p3$  create_request_id=v_req, create_request_hash=v_hash,  -- 416
  print_note=v456_note  -- 456
  where id=v_id;
$p3$,
$p4$ if p_header ? 'notes' then n.notes:=p_header->>'notes'; end if;
 -- 456 (the Owner, 22 Oct 2026): the note printed on the invoice (Notes stay
 -- internal and never print). Named in the header: set (blank is none), up to
 -- 500 characters; not named: kept. A change is a change like any other: on
 -- a paid invoice it needs the reason, and the revision and the
 -- invoice_corrected audit row hold the whole row before and after.
 if p_header ? 'print_note' then
   n.print_note:=nullif(btrim(coalesce(p_header->>'print_note',''),E' \t\r\n'),'');
   if char_length(n.print_note)>500 then
     raise exception 'PRINT_NOTE_TOO_LONG: The note printed on the invoice can be at most 500 characters.'; end if;
 end if;
$p4$,
$p5$affiliate_selection_explicit=n.affiliate_selection_explicit,notes=n.notes,print_note=n.print_note,  -- 456
$p5$];

  -- ══ Relied on, not changed (production now, 451-455 in; as at 450) ══════
  c_relied constant text[] := array[
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    'update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)',
    'preview_invoice_correction(uuid,jsonb)',
    'record_invoice_payment(uuid,jsonb,uuid)',
    'staff_may_correct_invoice(uuid)',
    'can_edit_invoice(uuid)',
    'invoice_revision_retry(uuid,uuid,jsonb)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)'];
  c_relied_md5 constant text[] := array[
    '80c80d386a5241e63b353e35e13ef250',
    '8e674fe0d5e35ed5c2e93d417f14c05a',
    '2bb7c0a5769050d5b2f9247a3aa05ecd',
    '9c70097ed4da614fb9dcc66fdfcdb7d6',
    '60cbe4859f1f1f43da02115c019fc4bf',
    '22f496c486ee4f0dfd45c68da6240ac2',
    '5c33c50a8f6870d8a66f74b63b782f24',
    'c705c733e213a27f0dc32d54322cc855'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; n int; i int; k int; v_add boolean := false;
  v_texts text[] := array[null, null]::text[]; v_acls text[] := array[null, null]::text[];
  -- the self-test's made-up records
  t_sfx text; t_phone text; t_owner uuid; t_store uuid; t_cash uuid; t_vch uuid; t_buyer uuid;
  t_inv uuid; t_lines jsonb; t_msg text; t_rev int; t_aud int; t_edits int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── 1. Checks: nothing is changed before all of them pass ──────────────
  -- What it relies on and does not change: as read on production, 23 Oct 2026.
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '456: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;

  -- The columns it reads and writes, with these types.
  select string_agg(x.c || ' ' || x.ty, ', ') into v
    from (values ('id', 'uuid'), ('notes', 'text'), ('status', 'invoice_status'), ('total_amount', 'numeric(12,2)'),
                 ('paid_amount', 'numeric(12,2)'), ('edit_count', 'integer'), ('create_request_id', 'uuid'),
                 ('create_request_hash', 'text'), ('deleted_at', 'timestamp with time zone')) x(c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = 'public.invoices'::regclass and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '456: these invoices columns are missing or not as read on 22 Oct 2026: %', v; end if;
  if to_regclass('public.invoice_revisions') is null or to_regclass('public.audit_logs') is null then
    raise exception '456: invoice_revisions or audit_logs is missing'; end if;

  -- The column: absent (added), or exactly as this file adds it (left alone).
  if exists (select 1 from pg_attribute a where a.attrelid = 'public.invoices'::regclass
               and a.attname = 'print_note' and a.attnum > 0 and not a.attisdropped) then
    if not exists (select 1 from pg_attribute a where a.attrelid = 'public.invoices'::regclass
                     and a.attname = 'print_note' and a.attnum > 0 and not a.attisdropped
                     and format_type(a.atttypid, a.atttypmod) = 'text' and not a.attnotnull and not a.atthasdef)
       or (select pg_get_constraintdef(c.oid) from pg_constraint c
            where c.conrelid = 'public.invoices'::regclass and c.conname = 'invoices_print_note_length') is distinct from c_con then
      raise exception '456: invoices.print_note is there but not as this file adds it (text, nullable, no default, invoices_print_note_length): re-read it'; end if;
  elsif exists (select 1 from pg_constraint c where c.conrelid = 'public.invoices'::regclass
                  and c.conname = 'invoices_print_note_length') then
    raise exception '456: invoices has the check invoices_print_note_length but no print_note column: re-read it';
  else
    v_add := true;
  end if;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('create_invoice_with_details', 'correct_invoice')
     and p.oid::regprocedure::text <> all (c_sigs);
  if v is not null then raise exception '456: another function takes the name of one this changes: %', v; end if;

  -- Each patched function: its BEFORE (patched; each anchor found once; the
  -- text built has its AFTER md5) or its AFTER (left alone).
  for k in 1 .. cardinality(c_sigs) loop
    if to_regprocedure('public.' || c_sigs[k]) is null then raise exception '456: public.% is missing', c_sigs[k]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sigs[k]));
    -- its grants, to compare after (as sets: production lists them in
    -- another order than a local copy does)
    v_acls[k] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                    from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[k]));
    if md5(d) = c_after[k] then
      raise notice '456: public.% is already this version; left alone', c_sigs[k];
      continue;
    end if;
    if md5(d) <> c_before[k] then
      raise exception '456: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sigs[k], md5(d); end if;
    for i in 1 .. cardinality(c_anchor) loop
      continue when c_fn[i] <> k;
      n := (length(d) - length(replace(d, c_anchor[i], ''))) / length(c_anchor[i]);
      if n <> 1 then raise exception '456: anchor % of public.% was found % times, not once', i, c_sigs[k], n; end if;
      d := replace(d, c_anchor[i], c_patch[i]);
    end loop;
    if md5(d) <> c_after[k] then
      raise exception '456: the text built for public.% is not the tested one (md5 %)', c_sigs[k], md5(d); end if;
    v_texts[k] := d;
  end loop;

  -- ── 2. Install ──────────────────────────────────────────────────────────
  -- The column first: the patched texts read and write it.
  if v_add then
    alter table public.invoices
      add column print_note text,
      add constraint invoices_print_note_length check (print_note is null or char_length(print_note) <= 500);
    comment on column public.invoices.print_note is
      '456 (the Owner, 22 Oct 2026): the note printed on the invoice: shown on the invoice screen and printed on the '
      'customer and office copies, the PDF and the image, above the signatures under "Note". Up to 500 characters; '
      'null when none. notes stays internal and never prints.';
  else
    raise notice '456: invoices.print_note is already there; left alone';
  end if;
  for k in 1 .. cardinality(c_sigs) loop
    if v_texts[k] is not null then execute v_texts[k]; end if;
  end loop;

  -- ── 3. Checks after installing ──────────────────────────────────────────
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'public.invoices'::regclass and c.conname = 'invoices_print_note_length') is distinct from c_con
     or not exists (select 1 from pg_attribute a where a.attrelid = 'public.invoices'::regclass
                      and a.attname = 'print_note' and a.attnum > 0 and not a.attisdropped
                      and format_type(a.atttypid, a.atttypmod) = 'text' and not a.attnotnull and not a.atthasdef) then
    raise exception '456: invoices.print_note is not as this file adds it'; end if;
  -- Read like every other column of the table: signed-in staff through the
  -- one policy, as before.
  if not has_column_privilege('authenticated', 'public.invoices', 'print_note', 'select') then
    raise exception '456: signed-in staff cannot read invoices.print_note'; end if;
  for k in 1 .. cardinality(c_sigs) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[k]))) <> c_after[k] then
      raise exception '456: public.% was installed with an md5 other than the tested one', c_sigs[k]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[k])) is distinct from v_acls[k]
       or has_function_privilege('anon', 'public.' || c_sigs[k], 'execute')
       or not has_function_privilege('authenticated', 'public.' || c_sigs[k], 'execute')
       or not has_function_privilege('service_role', 'public.' || c_sigs[k], 'execute') then
      raise exception '456: the grants of public.% changed (signed-in staff and the service role, never anon)', c_sigs[k]; end if;
  end loop;
  -- Each still checks access before it writes.
  d := pg_get_functiondef(to_regprocedure('public.' || c_sigs[2]));
  if position(E'\nbegin\n select * into i from public.invoices where id=p_invoice_id for update;\n'
              || E' if not found or i.deleted_at is not null then raise exception ''Invoice not found''; end if;\n'
              || E' if not public.user_has_store_access(i.store_id) then raise exception ''No access to this invoice''; end if;\n' in d) = 0 then
    raise exception '456: public.% no longer checks store access first', c_sigs[2]; end if;
  d := pg_get_functiondef(to_regprocedure('public.' || c_sigs[1]));
  if position('v_id:=public.create_invoice(' in d) = 0
     or position('update public.invoices set' in d) < position('v_id:=public.create_invoice(' in d)
     or (length(d) - length(replace(d, 'update public.invoices', ''))) / length('update public.invoices') <> 1 then
    raise exception '456: public.% writes the invoice before create_invoice has checked the caller', c_sigs[1]; end if;

  -- ── 4. Self-test, in a block that is always undone ─────────────────────
  -- Made-up records only ("456 check", @example.com, a fictional ACMA
  -- phone no customer uses); it ends by raising P0456, which undoes all it
  -- wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    select x into t_phone
      from (select '+6125550' || lpad(g::text, 4, '0') as x from generate_series(4560, 4599) g) y
     where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = y.x)
     order by x limit 1;
    if t_phone is null then raise exception '456: the self-test found no unused fictional phone'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '456-check-' || t_sfx || '@example.com') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '456 check', '456-check-' || t_sfx || '@example.com', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('456 check ' || t_sfx, '456-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('456 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.customers (full_name, phone) values ('456 Check Customer ' || t_sfx, t_phone) returning id into t_buyer;
    insert into public.vouchers (name, code, voucher_kind, selling_price, qty_type, is_active)
    values ('456 check ' || t_sfx, '456-' || t_sfx, 'normal', 30, 'unlimited', true) returning id into t_vch;
    insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store) values (t_vch, t_store, 30, true);

    -- Made with a printed note and an internal note: kept apart, trimmed.
    t_inv := public.create_invoice_with_details(t_store, t_buyer,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', t_vch, 'quantity', 1)),
      jsonb_build_object('business_date', public.sg_today(), 'notes', '456 check internal',
                         'print_note', E'  \nThank you, Test Customer.\nSee you soon. \n'));
    if (select (print_note, notes) is distinct from (E'Thank you, Test Customer.\nSee you soon.'::text, '456 check internal'::text)
          from public.invoices where id = t_inv) then
      raise exception '456: the invoice was not made with its printed note apart from its internal note (%)',
        (select jsonb_build_object('print_note', print_note, 'notes', notes) from public.invoices where id = t_inv); end if;
    begin
      perform public.create_invoice_with_details(t_store, t_buyer,
        jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', t_vch, 'quantity', 1)),
        jsonb_build_object('business_date', public.sg_today(), 'print_note', repeat('x', 501)));
      t_msg := null;
    exception when others then t_msg := sqlerrm;
    end;
    if t_msg is distinct from 'PRINT_NOTE_TOO_LONG: The note printed on the invoice can be at most 500 characters.' then
      raise exception '456: a 501-character note was not refused in words (%)', coalesce(t_msg, 'made'); end if;

    -- Paid in full; a note-only correction needs a reason.
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 30)), gen_random_uuid());
    if (select status::text from public.invoices where id = t_inv) <> 'paid' then
      raise exception '456: the self-test''s invoice is not paid'; end if;
    select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind::text, 'voucher_id', it.voucher_id,
                                        'quantity', it.quantity, 'unit_price', it.unit_price) order by it.id)
      into t_lines from public.invoice_items it where it.invoice_id = t_inv;
    begin
      perform public.correct_invoice(t_inv, t_lines, jsonb_build_object('print_note', 'Changed note'), '', gen_random_uuid());
      t_msg := null;
    exception when others then t_msg := sqlerrm;
    end;
    if t_msg is distinct from 'A correction reason is required' then
      raise exception '456: a note change on a paid invoice was not refused without a reason (%)', coalesce(t_msg, 'saved'); end if;
    perform public.correct_invoice(t_inv, t_lines, jsonb_build_object('print_note', 'Changed note', 'expected_edit_count', 0),
                                   '456 check', gen_random_uuid());
    select count(*) into t_rev from public.invoice_revisions r
     where r.invoice_id = t_inv and r.edit_reason = '456 check'
       and r.snapshot->'invoice'->>'print_note' = E'Thank you, Test Customer.\nSee you soon.'
       and r.after_snapshot->'invoice'->>'print_note' = 'Changed note';
    select count(*) into t_aud from public.audit_logs a
     where a.table_name = 'invoices' and a.record_id = t_inv and a.action = 'invoice_corrected' and a.reason = '456 check'
       and a.old_data->'invoice'->>'print_note' = E'Thank you, Test Customer.\nSee you soon.'
       and a.new_data->'invoice'->>'print_note' = 'Changed note';
    if (select (print_note, notes, total_amount, paid_amount, status::text, coalesce(edit_count, 0))
               is distinct from ('Changed note'::text, '456 check internal'::text, 30::numeric, 30::numeric, 'paid'::text, 1)
          from public.invoices where id = t_inv)
       or t_rev <> 1 or t_aud <> 1
       or (select count(*) from public.invoice_revisions where invoice_id = t_inv) <> 1 then
      raise exception '456: the note-only correction is not as tested (% revision(s), % audit row(s): %)', t_rev, t_aud,
        (select jsonb_build_object('print_note', print_note, 'notes', notes, 'total', total_amount, 'paid', paid_amount,
                                   'status', status, 'edits', edit_count) from public.invoices where id = t_inv); end if;

    -- Not named: kept. Blank: cleared. Too long: refused.
    perform public.correct_invoice(t_inv, t_lines, jsonb_build_object('notes', '456 check internal, changed'),
                                   '456 check 2', gen_random_uuid());
    if (select (print_note, notes) is distinct from ('Changed note'::text, '456 check internal, changed'::text)
          from public.invoices where id = t_inv) then
      raise exception '456: a correction that does not name print_note did not keep it'; end if;
    perform public.correct_invoice(t_inv, t_lines, jsonb_build_object('print_note', E' \n '), '456 check 3', gen_random_uuid());
    select coalesce(edit_count, 0) into t_edits from public.invoices where id = t_inv;
    if (select print_note from public.invoices where id = t_inv) is not null or t_edits <> 3 then
      raise exception '456: a blank note did not clear it (edits %)', t_edits; end if;
    begin
      perform public.correct_invoice(t_inv, t_lines, jsonb_build_object('print_note', repeat('y', 501)), '456 check 4', gen_random_uuid());
      t_msg := null;
    exception when others then t_msg := sqlerrm;
    end;
    if t_msg is distinct from 'PRINT_NOTE_TOO_LONG: The note printed on the invoice can be at most 500 characters.' then
      raise exception '456: a 501-character note was not refused by the correction (%)', coalesce(t_msg, 'saved'); end if;

    raise exception using errcode = 'P0456', message = '456: self-test done, undone';
  exception when sqlstate 'P0456' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
