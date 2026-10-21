-- 434_moved_voucher_stays_after_reopen.sql
--
-- A VOUCHER AN OWNER MOVED TO ANOTHER CUSTOMER STAYS WITH THEM, ALSO AFTER
-- THE INVOICE IS CANCELLED AND REOPENED AND ITS FOC IS TAKEN OFF (the
-- Owner, 18 Oct 2026, W4-B02-FRIEND-AFTER-REOPEN)
--
-- WHAT WAS WRONG (found 10 Oct 2026 in batch B03's checks of 417)
--
--   An Owner or Manager moves a completed FOC invoice's unused voucher to
--   another customer, a friend (transfer_invoice_unused_benefit: the
--   friend's voucher has source 'invoice_benefit_transfer'). The invoice is
--   cancelled and reopened: 417's reopening gives the voucher back to the
--   friend, at the friend's store, as any reopening gives a voucher again
--   (source 'invoice_reopen'). Then the FOC is taken off (Edit Invoice).
--   416's rule 14 in correct_invoice, and the list preview_invoice_correction
--   shows before the save, counted a voucher as "moved to another customer"
--   only while its source was 'invoice_benefit_transfer'. So the friend's
--   voucher was taken back (its stock returned at the friend's store), and
--   the payment that settled the invoice gave it to the buyer instead
--   (trg_issue_sold_vouchers_on_paid gives again what was taken back).
--   Stock stayed right (20, 18, 20 in the two stores of the test), but the
--   voucher changed hands, against the Owner's rule; without the cancel and
--   reopen the friend kept it.
--   Production, 18 Oct 2026: no voucher of any invoice is held by a
--   customer other than the invoice's, none has source
--   'invoice_benefit_transfer' or 'invoice_reopen', no completed FOC
--   invoice gave a voucher, no voucher is limited. Nothing to repair.
--
-- THE RULES (the Owner)
--
--   * 9 Oct 2026 (416, rule 14): taking the FOC off a completed FOC invoice
--     takes back the unused vouchers it gave and returns their stock; used
--     ones stay with the customer, and one moved to another customer stays
--     with them; all of it is reported and audited.
--   * 18 Oct 2026, W4-B02-MOVED-VOUCHER: keep "a voucher moved to another
--     customer stays with them when the FOC comes off".
--   * 18 Oct 2026, W4-B02-FRIEND-AFTER-REOPEN: "A voucher moved to another
--     customer stays with them even after the invoice is cancelled and
--     reopened and the FOC is taken off (follow-up migration 434, after
--     417)." This migration reads that as: the voucher an Owner moved to a
--     customer who is not the invoice's customer stays with them, and so
--     does the voucher a reopening gave that customer again in its place
--     (source 'invoice_reopen'); it is reported, counted as still out, and
--     not given again. The Owner's words name a voucher moved to another
--     customer, so a voucher another customer holds for any other reason is
--     not covered and is taken back as before 434: a sale's or a
--     promotion's voucher left with the old customer by a change of the
--     invoice's customer with benefit_action 'keep' (322: leave them with
--     whoever holds them now), in this save or an earlier one, or moved to
--     the new customer by 'transfer'; and the old customer's reopened
--     vouchers after a change with 'transfer' (417's move carries only sale
--     and promotion vouchers).
--   * 18 Oct 2026, W4-B02-OWN-OTHER-STORE: keep "a voucher moved to the
--     customer's own other store is taken back and given again at the
--     invoice's store" (the same customer, so not "another customer").
--   * 18 Oct 2026, W4-B02-FOC-OFF-SCOPE and W4-B02-BUNDLE-FOC-OFF: only
--     vouchers, from voucher and promotion lines, are taken back; a premium
--     bundle's stay. Unchanged here.
--
-- WHAT THIS DOES
--
--   * correct_invoice (patched; grants kept), 416's rule 14 only: a voucher
--     of the invoice still out counts as moved to another customer, and
--     stays with them, when all three hold: it is an Owner's move (source
--     'invoice_benefit_transfer') or a voucher a reopening gave again
--     (source 'invoice_reopen'); the customer holding it is neither the
--     invoice's customer before this save nor its customer after it; and an
--     Owner moved one of this invoice's vouchers to that customer (a row of
--     invoice_benefit_values of the invoice whose voucher has source
--     'invoice_benefit_transfer' and that customer, in any status: the
--     friend's moved voucher is revoked by the cancel, and the reopening
--     gives them a new one). It is reported as before
--     (foc_vouchers.kept_used: "... — moved to another customer; it stays
--     with them", and the audit row 'foc_removed_vouchers'); it is not
--     revoked and its stock stays out at its store. One expression changes,
--     with a comment.
--   * preview_invoice_correction (patched; grants kept): the same test, so
--     the list shown before the save says what the save does. The customer
--     after the save is the one the screen sends (customer_id), or the
--     invoice's. A sale's or a promotion's voucher never counts, so those
--     the save itself moves to the new customer (benefit_action 'transfer',
--     as move_invoice_benefits_to_customer moves them) are taken back in
--     the summary as in the save. One expression changes, with a comment.
--   * The third condition is by customer, not traced voucher by voucher: a
--     voucher a reopening gave again to a customer an Owner moved another
--     voucher of the invoice to counts as moved even if it replaces one
--     that was never moved. That needs an Owner's move to that customer's
--     other store, or a move followed by changes of the invoice's customer,
--     and then a cancel and reopen before the FOC comes off; production has
--     no such voucher. (A reopening's voucher is not traced back through
--     each reopening and payment: the payment's replacements are matched to
--     the line, not to one voucher.)
--   * One change follows from "nor its customer after it", and is for the
--     Owner to confirm (OPEN 1): a voucher an Owner moved to a customer whom
--     this save makes the invoice's customer (benefit_action 'keep' or
--     'transfer') is no longer another customer's. It is taken back at the
--     store it is at and given again at the invoice's store when the
--     invoice is paid, like W4-B02-OWN-OTHER-STORE. Before 434 that
--     customer kept it at the other store (cancel-voucher-stock-once.sql
--     13c-b checks both).
--   What follows from it, unchanged code: the payment that settles the
--   invoice gives again only what was taken back, and counts a voucher of
--   the line that is not revoked as still out, whoever holds it
--   (trg_issue_sold_vouchers_on_paid: what the line gives, less every
--   voucher of the line not revoked), so it gives nothing for the friend's.
--   The stock: 417's reopening recorded the friend's unit at the friend's
--   store, so the invoice's movement rows hold what is out, the payment
--   takes nothing more, and a later cancel gives it back once, at the
--   friend's store (cancel-voucher-stock-once.sql 12b: 10/8 when the FOC
--   comes off, 10/8 paid, 10/10 cancelled again).
--
-- NOT CHANGED
--
--   * trg_issue_sold_vouchers_on_paid (416): its count of what is still out
--     on a line already takes every voucher not revoked, whoever holds it
--     and whatever its source, and it gives again only vouchers taken back.
--     It needs no change; it is guarded, as this relies on it.
--   * A voucher another customer holds that no Owner moved to them: taken
--     back as before 434, and the payment gives it to the invoice's
--     customer. That is the old customer's after a change of the invoice's
--     customer with 'keep', in this save or an earlier one (13c-d), and the
--     old customer's reopened vouchers after a change with 'transfer'
--     (12e: 417's move carries only sale and promotion vouchers, so a
--     reopening's stay where they are until the FOC comes off). A sale's
--     voucher held by a customer an Owner moved another voucher of the
--     invoice to is taken back too (13c-f).
--   * A save that also changes the invoice's customer: a voucher still with
--     the old customer, or moved to the new one by this save ('transfer'),
--     is taken back as before 434 (13c-a, 13c-c), and the payment gives it
--     to the invoice's new customer. A voucher an Owner moved to a customer
--     who is neither stays with them (13c-e), as before 434.
--   * A voucher moved to another store of the same customer: taken back and
--     given again at the invoice's store, as before (W4-B02-OWN-OTHER-STORE).
--   * The friend's voucher after a payment and a second cancel: revoked and
--     its stock given back once, at the friend's store (417).
--   * A line refund of the paid line whose vouchers the friend kept is
--     refused, as on 416's path without a cancel and reopen: the friend's
--     voucher carries no paid value (refund_invoice_recorded). The money
--     goes back by Cancel, or by lowering the price in Edit Invoice and
--     recording a correction refund (OPEN 3; 12b and 12c check the refusal).
--   * transfer_invoice_unused_benefit, the reopening, the cancel and the
--     move of an invoice's benefits (417), the issuers, every grant, every
--     other line of the two functions. No row is changed.
--
-- OPEN (for the Owner; until answered this keeps the behaviour above)
--   1. An Owner moved the voucher to a friend; then one save takes the FOC
--      off and makes the friend the invoice's customer ('keep' or
--      'transfer'). With 434 the voucher is taken back and given to the
--      friend again at the invoice's store when paid; before 434 the friend
--      kept it at the other store. Which?
--   2. A correction that moves a reopened invoice to another customer with
--      'transfer' does not move the vouchers its reopening gave again (417's
--      move_invoice_benefits_to_customer moves sale and promotion vouchers
--      only); they stay with the old customer until the FOC comes off, and
--      are then taken back and given to the new customer (12e). Should the
--      correction move them too?
--   3. When a friend keeps the vouchers, should the payment that settles
--      the line carry its paid value onto the friend's voucher, or should
--      Refund allow a line refund (or show the line as not refundable)?
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic, and
--   every check comes before anything is installed:
--   * It refuses to run before 417: 417's reopen_invoice,
--     cancel_invoice_recorded, move_invoice_benefits_to_customer and its new
--     invoice_voucher_stock_unrecorded must be there at 417's AFTER md5s.
--   * correct_invoice and preview_invoice_correction must be 416's versions
--     live on 18 Oct 2026 (BEFORE), or already this migration's (AFTER, left
--     alone), so a second run changes nothing. Each anchor must be found
--     exactly once, and each text built must have its AFTER md5 before it is
--     installed. No other function may share their names.
--   * The functions and triggers it relies on and does not change must be
--     as read on production on 18 Oct 2026 (the payment trigger and the
--     reopening's, the Owner's move, the issuers, the stock functions).
--   * Afterwards both functions have their AFTER md5s and the grants they
--     had (signed-in staff and the service role, not anon).
--   * Then, inside a block that is always undone, a made-up Owner, two
--     made-up stores, a buyer and a friend (fictional ACMA phones), and a
--     made-up limited voucher. First a completed FOC invoice of 1 voucher,
--     moved to the friend at the second store, cancelled and reopened (the
--     friend holds it again, source 'invoice_reopen'): the preview lists it
--     as moved to another customer; taking the FOC off leaves it with the
--     friend, takes nothing back and gives no stock back (5 and 4 in the two
--     stores). Then a second completed FOC of 1 voucher, cancelled and
--     reopened (the buyer holds it again), its customer changed to the
--     friend with 'transfer' while it stays FOC (the buyer keeps the
--     reopening's voucher): taking the FOC off takes it back, in the preview
--     and the save, and its stock comes back (5 and 4), as no Owner moved a
--     voucher of it to the buyer. Nothing is printed and no row remains.
--
-- BEFORE (production, 18 Oct 2026, head 20261016064105; md5 of
-- pg_get_functiondef, search_path public; prodnow and stack12 read the same):
--   changed
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                  8a126ade5710d340378ac4e75931b05b  (416)
--   preview_invoice_correction(uuid,jsonb)                       be5d652d71df0499d41edeba1c395717  (416)
--   relied on, 417's (AFTER md5s of supabase/417_refund_cancel_requests_and_rental_returns.sql)
--   reopen_invoice(uuid,text,uuid)                               c9fcab7adfccdaeba1eb8dee4134ba47
--   cancel_invoice_recorded(uuid,text,uuid)                      de52d9dbaef8ab15163bef35cb9d733d
--   move_invoice_benefits_to_customer(uuid,uuid,uuid,text)       2c01c460d3af8edd3ad86332aa286ed8
--   invoice_voucher_stock_unrecorded(uuid,boolean)               91c8f0fa69ef6337f323b7ac467a8c2b  (new in 417)
--   relied on, production's
--   trg_issue_sold_vouchers_on_paid()                            c840d0d2754e7a8e889848ea8269a293  (416)
--   apply_reopened_invoice_vouchers()                            71d50be41b73decceb0b20f8597dd4fa
--   transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)    ea7e8ce0612752c75ba75748c9275c42
--   issue_sold_vouchers_for_invoice(uuid)                        0dbb4bc74411b6d4f0535f661a8c09ee
--   invoice_voucher_reopen_candidates(uuid)                      20405a96c8780eac6425a5dae59c29e1
--   invoice_promotion_voucher_components(uuid)                   88abd9576481edb759d6e433408c6275
--   deduct_invoice_stock(uuid,text)                              32183fe9e7c15ed0b11307c48289831a
--   invoice_stock_to_deduct(uuid)                                6356494ccb8545d46c56b788f8f85f54
--   triggers on public.invoices, enabled, as read that day:
--   invoice_reopen_vouchers_settled (apply_reopened_invoice_vouchers) and
--   issue_sold_vouchers_on_paid (trg_issue_sold_vouchers_on_paid), which
--   fires after it
--   public function fingerprint (reference only, not guarded):
--     production, 18 Oct 2026 (1244 functions; 434 refuses there: no 417)  ff637c8e7adc37a4892a6bf361290c4b
--     prodnow + 417 (1247)                                                 a7e2aed5a97673fa51b563143a47b94a
--     stack12, the test copy of prodnow + 418 420 431 429 417 422 423 424
--     427 419 425 426 as built into it (1279)                              5279ab5f824e7b8358212549b9765c54
--     stack13, the same + 430 (1280)                                       efffa3fda48a12ec2b7cb57df47e9ed7
-- AFTER (for later guards):
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                  422682d6e1ada0e5d98053e74ab9f007
--   preview_invoice_correction(uuid,jsonb)                       2bb7c0a5769050d5b2f9247a3aa05ecd
--   public function fingerprint (reference only, worked out on the test
--   copies, not read on production; the number of functions is unchanged):
--     prodnow + 417 + 434                                                  4a3d122c0641bfcdb5ce50443bf6634f
--     stack12 + 434                                                        fc93dcfcccc0ee3218022efcc3ec8d4c
--     stack13 + 434                                                        1f190ce47c6f2923986d884f2615d286
--
-- DEPLOY ORDER
--   After 417 (which goes in with the B16 page: 417's DEPLOY ORDER, step 0)
--   and before 422, as planned: 418, 420, 431, 429, 417, 434, 422, 423, 424,
--   427, 419, 425, 426, 430. Before 417 it refuses ("434: needs 417 first").
--   None of 418 to 431 changes or guards the two functions this changes, so
--   it may also go in after any of them. The database only: no page
--   changes (the Edit Invoice summary shows the list as before).
--
-- Test: scripts/invoice-actions/tests/cancel-voucher-stock-once.sql (case
-- 12b: with this in, a hard check that the friend keeps the voucher through
-- the preview, the save, the payment and a second cancel, store by store,
-- and that a line refund is refused; without it, the KNOWN FAULT notice as
-- before. 12c: the line refund refused on 416's path. 12e: the old
-- customer's reopened vouchers after a 'transfer' are taken back and given
-- to the new customer. 13c (a) to (f): the FOC taken off in a save that
-- also changes the customer, or after an earlier 'keep', summary and save;
-- (b) checks 434's figures with it and the old ones without), with
-- scripts/invoices/tests/sold-voucher-issuance.sql, correction-preview.sql
-- and foc-guards.sql (each takes -v mig=supabase/434_moved_voucher_stays_after_reopen.sql),
-- scripts/permissions/tests/function-grants.sql and staff-only-functions.sql,
-- on a copy of production with 417 in (and with 418 to 430 in). Amended
-- for this: scripts/invoices/tests/before-416-prelude.sql also puts back
-- 434's correct_invoice (422682d6...) for a test run, as it does 416's, so
-- scripts/xero/tests/sales-events.sql and the other suites it serves still
-- run once this is in. Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ correct_invoice: 416's rule 14 ════════════════════════════════════════
  c_ci constant text := 'correct_invoice(uuid,jsonb,jsonb,text,uuid)';
  c_ci_before constant text := '8a126ade5710d340378ac4e75931b05b';
  c_ci_after constant text := '422682d6e1ada0e5d98053e74ab9f007';
  c_ci_a constant text := $a$                        (crv.source_type = 'invoice_benefit_transfer'
                         and crv.customer_id is distinct from i.customer_id) as moved,
$a$;
  c_ci_r constant text := $r$                        -- 434: moved to another customer when it is the Owner's move
                        -- (transfer_invoice_unused_benefit) or the voucher a reopening gave
                        -- again in its place, its holder is neither the invoice's customer
                        -- before this save (i) nor after it (n), and an Owner moved one of
                        -- this invoice's vouchers to that holder (the Owner, 18 Oct 2026). It
                        -- stays with them, is reported, and its stock stays out. A voucher
                        -- held for any other reason (a sale's or a promotion's, left by
                        -- 'keep' or moved by 'transfer') is taken back, as before.
                        (crv.source_type in ('invoice_benefit_transfer','invoice_reopen')
                         and crv.customer_id is distinct from i.customer_id
                         and crv.customer_id is distinct from n.customer_id
                         and exists (select 1 from public.invoice_benefit_values tb434
                                       join public.customer_reward_vouchers tv434 on tv434.id = tb434.reward_voucher_id
                                      where tb434.invoice_id = i.id
                                        and tv434.source_type = 'invoice_benefit_transfer'
                                        and tv434.customer_id = crv.customer_id)) as moved,
$r$;

  -- ══ preview_invoice_correction: the same, before the save ═════════════════
  c_pv constant text := 'preview_invoice_correction(uuid,jsonb)';
  c_pv_before constant text := 'be5d652d71df0499d41edeba1c395717';
  c_pv_after constant text := '2bb7c0a5769050d5b2f9247a3aa05ecd';
  c_pv_a constant text := $a$                     case when crv.source_type = 'invoice_benefit_transfer'
                               and crv.customer_id is distinct from i.customer_id
                            then 'moved to another customer; it stays with them'
$a$;
  c_pv_r constant text := $r$                     -- 434: as in the save: the Owner's move or a reopening's voucher,
                     -- held by neither the invoice's customer nor the one this save gives
                     -- it, but by a customer an Owner moved one of this invoice's
                     -- vouchers to. A sale's or a promotion's voucher is never counted,
                     -- so those this save moves to the new customer (benefit_action
                     -- 'transfer') are taken back, as in the save.
                     case when crv.source_type in ('invoice_benefit_transfer','invoice_reopen')
                               and crv.customer_id is distinct from i.customer_id
                               and crv.customer_id is distinct from v_new_cust
                               and exists (select 1 from public.invoice_benefit_values tb434
                                             join public.customer_reward_vouchers tv434 on tv434.id = tb434.reward_voucher_id
                                            where tb434.invoice_id = i.id
                                              and tv434.source_type = 'invoice_benefit_transfer'
                                              and tv434.customer_id = crv.customer_id)
                            then 'moved to another customer; it stays with them'
$r$;

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  r record; d text; v text; n int; k int; v_bad text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[];
  -- the check
  v_owner uuid; v_st uuid; v_st2 uuid; v_buyer uuid; v_friend uuid; v_vch uuid; v_inv uuid;
  v_phones text[]; v_items jsonb; v_res jsonb;
begin
  -- Definitions are read and compared with public alone on the search path,
  -- as they were read on 18 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── 1. Not before 417 ────────────────────────────────────────────────────
  for r in select * from (values
      ('invoice_voucher_stock_unrecorded(uuid,boolean)',         '91c8f0fa69ef6337f323b7ac467a8c2b'),
      ('reopen_invoice(uuid,text,uuid)',                         'c9fcab7adfccdaeba1eb8dee4134ba47'),
      ('cancel_invoice_recorded(uuid,text,uuid)',                'de52d9dbaef8ab15163bef35cb9d733d'),
      ('move_invoice_benefits_to_customer(uuid,uuid,uuid,text)', '2c01c460d3af8edd3ad86332aa286ed8')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '434: needs 417 first: public.% is missing', r.fn; end if;
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.md5 then
      raise exception '434: needs 417 first: public.% is not 417''s version (md5 %). Re-read it and re-test before applying.', r.fn, v; end if;
  end loop;

  -- ── 2. Relied on, not changed: as read on 18 Oct 2026 ────────────────────
  for r in select * from (values
      ('trg_issue_sold_vouchers_on_paid()',                         'c840d0d2754e7a8e889848ea8269a293'),
      ('apply_reopened_invoice_vouchers()',                         '71d50be41b73decceb0b20f8597dd4fa'),
      ('transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid)', 'ea7e8ce0612752c75ba75748c9275c42'),
      ('issue_sold_vouchers_for_invoice(uuid)',                     '0dbb4bc74411b6d4f0535f661a8c09ee'),
      ('invoice_voucher_reopen_candidates(uuid)',                   '20405a96c8780eac6425a5dae59c29e1'),
      ('invoice_promotion_voucher_components(uuid)',                '88abd9576481edb759d6e433408c6275'),
      ('deduct_invoice_stock(uuid,text)',                           '32183fe9e7c15ed0b11307c48289831a'),
      ('invoice_stock_to_deduct(uuid)',                             '6356494ccb8545d46c56b788f8f85f54')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '434: public.% is missing or not the version read on 18 Oct 2026. Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;
  -- The reopening's trigger gives a reopened invoice's vouchers again; the
  -- payment's fires after it and gives again what removing the FOC took back.
  for r in select * from (values
      ('invoice_reopen_vouchers_settled', 'CREATE TRIGGER invoice_reopen_vouchers_settled AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION apply_reopened_invoice_vouchers()'),
      ('issue_sold_vouchers_on_paid',     'CREATE TRIGGER issue_sold_vouchers_on_paid AFTER UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_issue_sold_vouchers_on_paid()')) x(tg, def)
  loop
    if (select pg_get_triggerdef(t.oid) from pg_trigger t
         where t.tgrelid = 'public.invoices'::regclass and t.tgname = r.tg and t.tgenabled = 'O') is distinct from r.def then
      raise exception '434: the trigger % on public.invoices is not the one read on 18 Oct 2026', r.tg; end if;
  end loop;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('correct_invoice', 'preview_invoice_correction')
     and p.oid::regprocedure::text not in (c_ci, c_pv);
  if v_bad is not null then
    raise exception '434: another overload of a function this changes exists: %', v_bad; end if;

  -- ── 3. The two functions: BEFORE (patched) or AFTER (left alone) ─────────
  for r in select * from (values
      (1, c_ci, c_ci_before, c_ci_after, c_ci_a, c_ci_r),
      (2, c_pv, c_pv_before, c_pv_after, c_pv_a, c_pv_r)) x(i, fn, before_md5, after_md5, anchor, patch)
    order by x.i
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '434: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '434: public.% is already this version; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '434: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    n := (length(d) - length(replace(d, r.anchor, ''))) / length(r.anchor);
    if n <> 1 then
      raise exception '434: the anchor of public.% was found % times, not once', r.fn, n; end if;
    d := replace(d, r.anchor, r.patch);
    if md5(d) <> r.after_md5 then
      raise exception '434: the text built for public.% is not the tested one (md5 %)', r.fn, md5(d); end if;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;

  -- The grants of both, to compare after.
  select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
    into v_acl
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text in (c_ci, c_pv);

  -- ── 4. Install ───────────────────────────────────────────────────────────
  for k in 1 .. coalesce(cardinality(v_fns), 0) loop
    execute v_defs[k];
  end loop;

  -- ── 5. Installed exactly as tested, grants as before ─────────────────────
  for r in select * from (values (c_ci, c_ci_after), (c_pv, c_pv_after)) x(fn, after_md5) loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      raise exception '434: public.% was installed with md5 %, not the tested one', r.fn, v; end if;
  end loop;
  if (select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
        from pg_proc p
       where p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text in (c_ci, c_pv))
     is distinct from v_acl then
    raise exception '434: the grants of the changed functions changed'; end if;
  foreach v in array array[c_ci, c_pv] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or not has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '434: public.% is not for signed-in staff and the service role only', v; end if;
  end loop;

  -- ── 6. Behaviour, inside a block that is always undone ───────────────────
  -- Case 12b of cancel-voucher-stock-once.sql with 1 voucher. Nothing is
  -- printed and no row remains.
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    insert into auth.users (id, email) values (gen_random_uuid(), '434-check-owner-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '434 check', u.email, 'owner'::public.user_role, true from auth.users u where u.id = v_owner;
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_owner::text, true);
    insert into public.stores (name, code, country_code)
      values ('434 check', '434-' || substr(md5(gen_random_uuid()::text), 1, 8), 'SG') returning id into v_st;
    insert into public.stores (name, code, country_code)
      values ('434 check 2', '434-' || substr(md5(gen_random_uuid()::text), 1, 8), 'SG') returning id into v_st2;
    -- Two valid phones no customer has: numbers kept for fiction (ACMA),
    -- never a real person's.
    select array_agg(c.p order by c.p) into v_phones
      from (values ('+61491570737'), ('+61491572983'), ('+61491573770'), ('+61491573087'), ('+61491574118'),
                   ('+61491574632'), ('+61491575254'), ('+61491575789'), ('+61491576398'), ('+61491576801'),
                   ('+61491577426'), ('+61491577644')) c(p)
     where public.normalize_customer_phone(c.p) = c.p
       and not exists (select 1 from public.customers cu where cu.phone = c.p);
    if coalesce(cardinality(v_phones), 0) < 2 then
      raise exception '434: the check found no two free fictional phones'; end if;
    insert into public.customers (full_name, phone) values ('434 check buyer', v_phones[1]) returning id into v_buyer;
    insert into public.customers (full_name, phone) values ('434 check friend', v_phones[2]) returning id into v_friend;
    insert into public.vouchers (name, code, voucher_kind, selling_price, qty_type, is_active)
      values ('434 check', '434-' || substr(md5(gen_random_uuid()::text), 1, 8), 'normal', 40, 'limited', true)
      returning id into v_vch;
    insert into public.voucher_store_stock (voucher_id, store_id, current_qty) values (v_vch, v_st, 5), (v_vch, v_st2, 5);
    insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store) values (v_vch, v_st, 40, true);
    -- A completed FOC of 1 voucher, moved to the friend at the second store,
    -- cancelled and reopened: the friend holds it again ('invoice_reopen').
    v_inv := public.create_invoice(v_st, v_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', v_vch, 'quantity', 1,
        'foc_quantity', 1, 'foc_reason', '434 check')));
    perform public.confirm_foc_invoice(v_inv, '434 check');
    perform public.transfer_invoice_unused_benefit((select b.id from public.invoice_benefit_values b where b.invoice_id = v_inv),
      v_friend, v_st2, '434 check', gen_random_uuid());
    perform public.cancel_invoice_recorded(v_inv, '434 check', gen_random_uuid());
    perform public.reopen_invoice(v_inv, '434 check', gen_random_uuid());
    if not coalesce((select status::text from public.invoices where id = v_inv) = 'completed_foc'
       and (select sum(quantity) from public.customer_reward_vouchers
             where voucher_id = v_vch and customer_id = v_friend and store_id = v_st2
               and status = 'held' and source_type = 'invoice_reopen') = 1
       and (select current_qty from public.voucher_store_stock where voucher_id = v_vch and store_id = v_st) = 5
       and (select current_qty from public.voucher_store_stock where voucher_id = v_vch and store_id = v_st2) = 4, false) then
      raise exception '434: the check''s invoice is not as tested after its reopening'; end if;
    -- The FOC taken off: the summary lists the voucher as moved, and the save
    -- leaves it with the friend, takes nothing back and gives no stock back.
    select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id,
             'quantity', it.quantity, 'unit_price', 40, 'foc_quantity', 0)) into v_items
      from public.invoice_items it where it.invoice_id = v_inv;
    v_res := public.preview_invoice_correction(v_inv, jsonb_build_object('items', v_items,
               'expected_edit_count', (select edit_count from public.invoices where id = v_inv)));
    if not coalesce(v_res->'effects' @> '[{"area":"vouchers","items":[{"kind":"voucher","why":"moved to another customer; it stays with them"}]}]'::jsonb
       and v_res->'effects' @> '[{"area":"vouchers","detail":"Removing the FOC takes back no voucher: the vouchers it gave have been used or moved to another customer."}]'::jsonb, false) then
      raise exception '434: the summary does not list the friend''s voucher as moved to another customer'; end if;
    v_res := public.correct_invoice(v_inv, v_items,
               jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = v_inv)),
               '434 check', gen_random_uuid());
    if not coalesce((select status::text from public.invoices where id = v_inv) = 'unpaid'
       and v_res#>'{foc_vouchers,taken_back}' = '[]'::jsonb
       and jsonb_array_length(v_res#>'{foc_vouchers,kept_used}') = 1
       and v_res#>>'{foc_vouchers,kept_used,0}' like '% — moved to another customer; it stays with them'
       and (select sum(quantity) from public.customer_reward_vouchers
             where voucher_id = v_vch and customer_id = v_friend and store_id = v_st2
               and status = 'held' and source_type = 'invoice_reopen') = 1
       and not exists (select 1 from public.customer_reward_vouchers
                        where voucher_id = v_vch and customer_id = v_buyer and status <> 'revoked')
       and (select current_qty from public.voucher_store_stock where voucher_id = v_vch and store_id = v_st) = 5
       and (select current_qty from public.voucher_store_stock where voucher_id = v_vch and store_id = v_st2) = 4, false) then
      raise exception '434: taking the FOC off did not leave the friend''s voucher with them (%)', v_res->'foc_vouchers'; end if;
    -- A second completed FOC of 1 voucher, cancelled and reopened (the buyer
    -- holds it again, 'invoice_reopen'), then, still FOC, its customer
    -- changed to the friend with 'transfer' (417's move carries only sale
    -- and promotion vouchers, so the buyer keeps it), then the FOC taken
    -- off: no Owner moved a voucher of it to the buyer, so the summary and
    -- the save take it back and its stock comes back, as before 434.
    v_inv := public.create_invoice(v_st, v_buyer, null,
      jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', v_vch, 'quantity', 1,
        'foc_quantity', 1, 'foc_reason', '434 check')));
    perform public.confirm_foc_invoice(v_inv, '434 check');
    perform public.cancel_invoice_recorded(v_inv, '434 check', gen_random_uuid());
    perform public.reopen_invoice(v_inv, '434 check', gen_random_uuid());
    select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id,
             'quantity', it.quantity, 'unit_price', 40, 'foc_quantity', it.quantity, 'foc_reason', it.foc_reason)) into v_items
      from public.invoice_items it where it.invoice_id = v_inv;
    perform public.correct_invoice(v_inv, v_items,
      jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = v_inv),
                         'customer_id', v_friend, 'benefit_action', 'transfer'),
      '434 check', gen_random_uuid());
    if not coalesce((select status::text from public.invoices where id = v_inv) = 'completed_foc'
       and (select customer_id from public.invoices where id = v_inv) = v_friend
       and (select sum(crv.quantity) from public.invoice_benefit_values b
              join public.customer_reward_vouchers crv on crv.id = b.reward_voucher_id
             where b.invoice_id = v_inv and crv.customer_id = v_buyer and crv.status = 'held'
               and crv.source_type = 'invoice_reopen') = 1
       and (select current_qty from public.voucher_store_stock where voucher_id = v_vch and store_id = v_st) = 4, false) then
      raise exception '434: the check''s second invoice is not as tested after its reopening and change of customer'; end if;
    select jsonb_agg(jsonb_build_object('invoice_item_id', it.id, 'kind', 'voucher', 'voucher_id', it.voucher_id,
             'quantity', it.quantity, 'unit_price', 40, 'foc_quantity', 0)) into v_items
      from public.invoice_items it where it.invoice_id = v_inv;
    v_res := public.preview_invoice_correction(v_inv, jsonb_build_object('items', v_items,
               'expected_edit_count', (select edit_count from public.invoices where id = v_inv)));
    if not coalesce(exists (select 1 from jsonb_array_elements(v_res->'effects') e
                    where e->>'area' = 'vouchers' and jsonb_array_length(e->'items') = 0
                      and e->>'detail' like 'Removing the FOC takes back the unused vouchers it gave (434 check × 1).%'), false) then
      raise exception '434: the summary does not take back the voucher the old customer kept'; end if;
    v_res := public.correct_invoice(v_inv, v_items,
               jsonb_build_object('expected_edit_count', (select edit_count from public.invoices where id = v_inv)),
               '434 check', gen_random_uuid());
    if not coalesce((select status::text from public.invoices where id = v_inv) = 'unpaid'
       and v_res->'foc_vouchers' = '{"taken_back":["434 check × 1"],"kept_used":[]}'::jsonb
       and not exists (select 1 from public.invoice_benefit_values b
                         join public.customer_reward_vouchers crv on crv.id = b.reward_voucher_id
                        where b.invoice_id = v_inv and crv.status <> 'revoked')
       and (select current_qty from public.voucher_store_stock where voucher_id = v_vch and store_id = v_st) = 5
       and (select current_qty from public.voucher_store_stock where voucher_id = v_vch and store_id = v_st2) = 4, false) then
      raise exception '434: taking the FOC off did not take back the voucher the old customer kept (%)', v_res->'foc_vouchers'; end if;
    raise exception using errcode = 'P0434', message = '434: check done, undone';
  exception when sqlstate 'P0434' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
