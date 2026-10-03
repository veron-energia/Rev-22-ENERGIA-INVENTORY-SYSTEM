-- 385_invoice_line_discount_types.sql
--
-- (Written as 384 and renumbered: 384 went to the Singapore-date commission
-- migration, applied first. The labels inside this file, its "384:" messages
-- and markers, keep the number it was written under; they are not renamed so
-- the function bodies and their md5s stay exactly as tested.)
--
-- ONE DISCOUNT PER INVOICE LINE (the owner's decisions of 3 Oct 2026)
--
--   Until now an invoice line had two separate controls: "FOC:" (some or all
--   units free, with a reason) and "Line voucher:" (a discount voucher, own
--   products only). Birthday and Staff discounts were ordinary discount
--   vouchers told apart only by their names, so nothing checked the birthday,
--   nothing stopped a second birthday discount, a line could be part FOC and
--   carry a voucher, and there was no discount by amount or percentage on a
--   line. The invoice's own Manual discount (with its internal reason) and its
--   Discount Voucher stay exactly as they are and may still stack on top.
--
--   1. One "Discount" per line: FOC, Vouchers, Birthday discount, Staff
--      discount, Manual discount (S$, reason) or Percentage discount (%,
--      reason). A line is FOC or has one discount, never both. A line saved
--      before 384 with FOC and a voucher keeps both until that line is
--      changed; changing it means picking one.
--   2. Vouchers, Birthday and Staff are discount vouchers, told apart by a new
--      category the Owner sets on the Vouchers page (vouchers.discount_category:
--      voucher, birthday or staff). A Birthday voucher says whether it is for
--      the birthday itself or the whole birth month (vouchers.birthday_rule:
--      actual_date or whole_month). Existing discount vouchers are filled in
--      once from their names (a name starting "Birthday" with "Actual Date" or
--      "Whole Month" in it is a Birthday voucher with that rule; a name
--      starting "Staff" is a Staff voucher; every other discount voucher,
--      a "Birthday ..." one with neither phrase included, is a Voucher). No
--      voucher is renamed or switched off.
--   3. Who: FOC and the three voucher options, every role that may invoice
--      except an Inventory Manager (refused FOC already; now refused the
--      voucher options too, which nothing checked before). Manual and
--      Percentage: anyone who may invoice, with a reason (free text, required,
--      internal: never printed).
--   4. Which lines: FOC where it is today (not on a credit package or premium
--      bundle when the invoice is made). Vouchers, Birthday and Staff on our
--      own products only (not third-party, not other kinds), as the line
--      voucher was. Manual and Percentage on every line that can be
--      discounted: products (third-party too), promotions, sold vouchers,
--      therapy, special products, rentals and event tickets. Not on a credit
--      package or premium bundle: a discount there scales its credit down.
--   5. Birthday: the customer's date of birth against the invoice's business
--      date (Singapore). "On the birthday": that day only (29 Feb is 28 Feb in
--      a year without one). "In the birth month": any day of that month. No
--      customer or no date of birth: refused ("Add the customer's date of
--      birth ..."). One birthday-discount invoice per customer per calendar
--      year of the business date ("Birthday discount already used this year on
--      INV-..."); any number of birthday lines on that one invoice. Cancelled,
--      refunded and deleted invoices do not count, nor the invoice being
--      edited. A line saved before 384 with a Birthday voucher counts, and so
--      does an invoice whose own Discount Voucher is a Birthday voucher.
--      That invoice-level Birthday voucher is itself a Birthday discount: it
--      is checked the same way when it is picked (made, or picked in an edit)
--      or the customer changes; one kept as saved before 384 is not. A
--      correction that moves the invoice to another customer or date checks
--      every Birthday discount on it again: its birthday lines (those saved
--      before 384 too) and its own Birthday voucher.
--   6. Staff: no check that the customer is staff.
--   7. Percentage: more than 0 and at most 100, of the line's value before the
--      discount (unit price x quantity, plus a promotion's top-up: what the
--      line charges), amount = round(value x % / 100, 2). Manual: rounded to
--      the cent, then more than S$0 and at most the line's value. Every option
--      keeps its money in invoice_items.line_discount, as the line voucher
--      did, so commission, refunds, the wallet-credit cap and every other
--      reader of line_discount carry on unchanged.
--   8. Reports: the Discounts report gains a column per option, and exchange
--      credit (a line discount with neither voucher nor option, written by
--      exchanges) on its own. A line saved before 384 with a voucher counts
--      under that voucher's category. FOC keeps its own report.
--   9. Corrections. A saved line whose Discount alone changes (given, taken
--      off, another option, amount, percentage or reason) is not sold again:
--      its price, FOC, item, promotion picks, therapy and ticket people stay
--      as saved and only its Discount is worked out, on its saved value. So a
--      discount can be given on a paid therapy package or a promotion that
--      has since ended (before, the line was checked as a new sale and
--      refused). An Owner or Manager correcting only the price of a therapy
--      session (or credit line) moves its Discount with the price: a
--      percentage follows it, a manual amount above it is refused.
--
--   And three faults this change runs into:
--   a) refresh_invoice_discount_total, which every edit and FOC change ends
--      with, worked the invoice voucher out on another base than
--      create_invoice did (third-party value in, the manual discount not
--      taken off), so an edit quietly changed what the voucher gave (subtotal
--      100, manual 20, a 10% invoice voucher: 8 off when made, 10 off after
--      any edit). It now adds up exactly as create_invoice does. An invoice
--      already edited before 384 holds the old amount; its next correction
--      that changes a line, a discount, Save Earth or the service staff works
--      the voucher out the new way, and the total moves (list them first:
--      BEFORE APPLYING). A correction of anything else (notes, dates, the
--      customer, payments) no longer goes through the money at all:
--      correct_invoice re-ran it whenever the screen sent the service staff,
--      which it always does, changed or not.
--   b) (screen only) a saved voucher no longer listed showed "None" on edit.
--   c) Special product and rental lines lost their FOC: update_invoice_internal
--      (and create_invoice) wrote them without it, while the subtotal had
--      already been reduced by it. Both now write it. Invoices already saved
--      that way are not repaired here (list them first: BEFORE APPLYING): a
--      correction of one that would charge that FOC again is refused until
--      the line is given its FOC again in the correction.
--
-- WHAT THIS CHANGES
--
--   * vouchers: discount_category, birthday_rule, their checks, and a trigger
--     that keeps them in step with the voucher's kind (a sold voucher has
--     neither; a discount voucher without a category is a Voucher; only a
--     Birthday voucher has a rule, and it must have one).
--   * invoice_items: line_discount_type (voucher, birthday, staff, manual,
--     percentage), line_discount_percent, line_discount_reason,
--     line_discount_by, line_discount_at, with checks (a voucher option has
--     its voucher, manual and percentage none; a percentage line has its
--     percentage; an option means no FOC) and a reason trigger.
--   * New, internal (service role only; called from the functions below):
--     invoice_line_discount_kind, invoice_line_discount_for,
--     invoice_birthday_check, invoice_birthday_lines_check,
--     invoice_line_discount_take, invoice_line_discount_write,
--     invoice_line_discount_rebase, invoice_line_discount_only, and the two
--     trigger functions.
--   * create_invoice (8 arguments): every line's Discount through
--     invoice_line_discount_for in pass 1; pass 2 writes it on the line; the
--     invoice voucher's base leaves out discounts on third-party lines (there
--     were none before); special and rental lines keep their FOC; an
--     invoice-level Birthday voucher is checked as a Birthday discount.
--   * update_invoice_internal: the same in both passes, for every changed
--     line; a line kept as it is keeps its Discount; a line whose Discount
--     alone changed keeps everything else (9 above); a price-only correction
--     moves the Discount with the price; special and rental lines keep their
--     FOC; an invoice-level Birthday voucher is checked when picked or the
--     customer changes; a correction that would charge again FOC lost by (c)
--     is refused.
--   * correct_invoice: checks every Birthday discount again when the
--     customer or the business date changes; re-runs the money only when the
--     service staff change, not whenever they are sent.
--   * invoice_line_matches: a line whose Discount changed is a changed line.
--     invoice_operational_lines_match: a change of Discount alone moves no
--     stock.
--   * apply_line_foc (Make FOC): refused on a line that has a discount.
--   * reprice_invoice_lines (Confirm FOC): a percentage follows the new
--     value, a manual amount is capped by it.
--   * refresh_invoice_discount_total: (a) above.
--   * report_discounts: the new columns line_voucher_discount,
--     birthday_discount, staff_discount, line_manual_discount,
--     line_percentage_discount and exchange_credit, after the existing ones,
--     which keep their meaning (line_discount is still every line discount).
--
--   Each item of create_invoice_with_details, create_invoice, update_invoice,
--   correct_invoice may carry: line_discount_type; line_voucher_id (Vouchers,
--   Birthday, Staff); line_discount_amount (Manual); line_discount_percent
--   (Percentage); line_discount_reason (Manual, Percentage); and the FOC keys
--   as before. An item with line_voucher_id and no line_discount_type is that
--   voucher's category (website and seminar orders, and screens from before
--   384). An item with neither has no discount, so website and seminar orders
--   (web_order_make_invoice -> create_invoice_with_details) are made exactly
--   as before.
--
-- NOT CHANGED
--
--   * The invoice's Manual discount and reason, and its Discount Voucher
--     (apart from a Birthday voucher being checked as one, 5 above). The
--     manual discount is still kept as typed and capped with the rest at the
--     subtotal, so with line discounts beside it the parts can add up to
--     more than the invoice's discount total (as a manual discount above the
--     subtotal always could).
--   * FOC maths, FOC reasons, Undo FOC (remove_line_foc: a line with an
--     option never has FOC, so nothing there changes), confirm_foc_invoice,
--     the voucher redemptions recorded at payment, commission, refunds.
--   * create_invoice_with_details passes items through untouched, and
--     preview_invoice_correction reads no items: neither needed a change.
--   * The 7-argument create_invoice overload (writes no line discount at all)
--     and override_invoice_line_price (no grant to staff, no caller).
--
-- SAFETY
--
-- Apart from the lock timeout, the migration is ONE statement (a DO block), so
-- it is atomic however it is run. It checks first and changes nothing unless
-- every check passes: md5(prosrc) of production (3 Oct 2026) for the
-- functions it relies on unchanged, and for each function it patches (BEFORE
-- below) or already this migration's version (AFTER, left alone, so a second
-- run changes nothing), with every anchor found the expected number of times.
-- Then: the columns, the new functions, the patched functions, the report,
-- the one-off fill of the voucher categories (only where none is set), the
-- checks, and the triggers. Finally every patched and new function must have
-- its AFTER md5. New functions: SECURITY DEFINER where they read tables, for
-- the service role only (339); report_discounts keeps its grants (signed-in
-- users). No invoice data is changed.
--
-- NUMBER: another migration applied to production on 3 Oct 2026 also carries
-- 384 (384_invoice_and_staff_commission_use_the_singapore_date, earn_* only).
-- They touch no function in common; this one may be applied before or after
-- it, and may be renumbered without any other change.
--
-- DEPLOY ORDER: apply this, then the screens. Screens from before 384 keep
-- working (a line voucher without an option is read as its category), but they
-- cannot give the new options and drop a Manual or Percentage discount from a
-- line they save again.
--
-- BEFORE APPLYING (read-only; for the Owner to look at, nothing to change):
--   -- (a) Settled invoices whose percentage invoice voucher gave another
--   -- amount than (a)'s fix works out: their next money correction moves
--   -- the total by the difference.
--   select * from (
--     select i.invoice_no, i.status, i.total_amount, i.paid_amount,
--            round(coalesce(i.discount_total,0) - coalesce(i.manual_discount,0) - l.disc
--                  - case when i.save_earth_applied then coalesce(i.save_earth_amount,0) else 0 end, 2) as voucher_now,
--            least(case when v.max_discount_cap is not null then least(x.amt, v.max_discount_cap) else x.amt end, x.base) as voucher_after_384
--       from public.invoices i
--       join public.vouchers v on v.id = i.discount_voucher_id and v.voucher_kind = 'percentage_discount'
--       cross join lateral (
--         select coalesce(sum(ii.line_total) filter (where t.third), 0) as third,
--                coalesce(sum(coalesce(ii.line_discount,0)), 0) as disc,
--                coalesce(sum(coalesce(ii.line_discount,0)) filter (where not t.third), 0) as own_disc
--           from public.invoice_items ii
--           cross join lateral (select ii.line_kind = 'product' and exists (select 1 from public.products p
--                                where p.id = ii.product_id and p.product_type = 'third_party') as third) t
--          where ii.invoice_id = i.id) l
--       cross join lateral (select greatest(0, (i.subtotal - l.third) - least(coalesce(i.manual_discount,0), i.subtotal - l.third) - l.own_disc) as base) b
--       cross join lateral (select b.base, round(b.base * coalesce(v.discount_percent,0) / 100.0, 2) as amt) x
--      where i.deleted_at is null and i.status in ('paid','partially_paid','completed_foc')) q
--    where voucher_now <> voucher_after_384
--    order by invoice_no;
--   -- (c) Invoices whose special product or rental FOC is in their totals but
--   -- not on the line.
--   select i.invoice_no, i.status, i.subtotal, i.foc_total, sum(ii.foc_amount) as lines_foc, sum(ii.line_total) as lines_total
--     from public.invoices i join public.invoice_items ii on ii.invoice_id = i.id
--    where i.deleted_at is null
--    group by i.id
--   having bool_or(ii.line_kind in ('special_product','rental'))
--      and (i.foc_total <> sum(ii.foc_amount) or i.subtotal <> sum(ii.line_total))
--    order by i.invoice_no;
--
-- BEFORE (production, md5(prosrc), 3 Oct 2026):
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)   dc89089ab43b718ce20148d6b4175887
--   update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)
--                                                                  e4cfc6432345d996cf4b25392d0d1887
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                    83a2d4d1445683b628daab8b0236fc4c
--   invoice_line_matches(uuid,jsonb)                               856cf4dd899ff7f67f682dc5e3e6a850
--   invoice_operational_lines_match(uuid,jsonb)                    5f394f5839b7728d9fe1216e1de83412
--   apply_line_foc(uuid,integer,uuid,text)                         8f0dd45852e137f85559139aa5368e37
--   reprice_invoice_lines(uuid,boolean)                            454e726d19cae93e8336b1bb89d7da4f
--   refresh_invoice_discount_total(uuid)                           b22e4c68caac029313b62bb5d4ad4596
--   report_discounts()                                             80d1a845ccebeb6c245c1897f4515fe1
--
-- AFTER (md5(prosrc) once applied, for later guards; energia_events with
-- production's versions installed, 3 Oct 2026):
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)   bf0f627b032aa11d680e1a09738c2edf
--   update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)
--                                                                  42be5f307a680d1828798845da06e0e6
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                    b3f99df8a82012b140a99bd96cb2cf91
--   invoice_line_matches(uuid,jsonb)                               3b24939e07962d6ac3de82813bc3a83a
--   invoice_operational_lines_match(uuid,jsonb)                    dc1c5430914fd0b0f4cc646b2d0badb9
--   apply_line_foc(uuid,integer,uuid,text)                         813831f58318f02c3d92d59b69cf8a7b
--   reprice_invoice_lines(uuid,boolean)                            1e30330eae2f8387d0d9622a69a1e103
--   refresh_invoice_discount_total(uuid)                           3b983d77df1c81146b7fd56f02d8ca7f
--   report_discounts()                                             7534e742656c0dd5cb818a6d468f6a7e
--   invoice_line_discount_kind(text,uuid)                          9314ad644e0a027c4649b140bf714ff0
--   invoice_line_discount_for(jsonb,text,boolean,numeric,uuid,date,uuid)
--                                                                  72f51bc774e6a033c41b814768c50fc3
--   invoice_birthday_check(uuid,date,uuid,uuid)                    a93b421ecdbfbcdc71696edd55866893
--   invoice_birthday_lines_check(uuid)                             259a17712fc4162e036911be958fbe59
--   invoice_line_discount_take(uuid,uuid)                          fcbe90339168f294ed86fc8189bb5c82
--   invoice_line_discount_write(uuid,jsonb,jsonb)                  d933fa2a9da99f4df8305e07cef38bd3
--   invoice_line_discount_rebase(text,uuid,numeric,numeric,numeric)
--                                                                  c8aba1474be0a2690d246eba016999b8
--   invoice_line_discount_only(uuid,jsonb)                         aebdcb4bf20b2ac7ee4ccd1cc4ebbfc5
--   trg_voucher_discount_category()                                327ab6341b467f149a82b684fdb46d07
--   trg_invoice_item_line_discount_reason()                        bbc6164e972434d025b2e9b08bb0da27
--
-- Tests: scripts/invoice-discounts/tests/line-discount-types.sql.

set lock_timeout = '5s';

do $mig$
declare
  r record; v text; d text; k int; n int; p jsonb; e jsonb;
  v_patches jsonb; v_install text[] := '{}'; v_report boolean := false;
  v_after jsonb := '{}'::jsonb;
begin
  -- ── 0. Guards: nothing below is created unless all of these pass ─────────
  for r in select * from (values
    -- Relied on unchanged: how a voucher discount is worked out, the FOC
    -- reasons, the role and store checks, a ticket line's own check (it
    -- refuses a voucher on a ticket), the way items reach create_invoice and
    -- update_invoice_internal, the website orders that make invoices, and the
    -- FOC paths that end in refresh_invoice_discount_total.
    ('public.voucher_discount_amount(uuid,numeric)', '80f8f77afdafd8dcfe8df2547483cbc3'),
    ('public.foc_reason_resolve(uuid,text)', '00c2b5b44959e63b7c46447d5f70bcae'),
    ('public.invoice_foc_reason(uuid,jsonb)', '529d119ca7e9d854e69cc4a4be930af7'),
    ('public.current_user_role()', '38683d3be39913aba404fa202d77f1c8'),
    ('public.user_has_store_access(uuid)', '1a7f0aa1ec24e2712e96dc791d673778'),
    ('public.is_owner_or_manager()', '7f888d6df058283917622c3ad03ddd91'),
    ('public.staff_may_correct_invoice(uuid)', '1241e859686c3690bc3c9bec570ac611'),
    ('public.event_ticket_line_check(jsonb,date,uuid,integer)', '013ee5f48a3371dcb28c9a9aad9530aa'),
    ('public.create_invoice_with_details(uuid,uuid,jsonb,jsonb)', '39a0a106b4429eaa8a871ce4ac69c37b'),
    ('public.update_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text)', '15625dabc8b702f2634f37b90e440d84'),
    ('public.web_order_make_invoice(uuid,uuid,boolean,boolean)', 'ab59ad85375ac6ce0de559f8f8d42027'),
    ('public.invoice_all_lines_match(uuid,jsonb)', '1ea6cfb26d6a895c4cec3ae422bb1c94'),
    ('public.invoice_benefit_price_only(uuid,jsonb)', '799a5b7891dcf2acbe1faddb9c0fa537'),
    ('public.recalc_invoice_foc(uuid)', '08fd6dfb1f168974ff5728a93ecb5266'),
    ('public.remove_line_foc(uuid,text)', 'a80e06e9dbab8867ff7ed2e38033a75c'),
    ('public.confirm_foc_invoice(uuid,text)', '50104e9fca42a618270c0d37ff05084f'),
    ('public.preview_invoice_correction(uuid,jsonb)', '7ba54a8649b53dcbd58ef5e689c22e74')) x(fn, want)
  loop
    if to_regprocedure(r.fn) is null then raise exception '384: % is missing', r.fn; end if;
    select md5(prosrc) into v from pg_proc where oid = to_regprocedure(r.fn);
    if v <> r.want then
      raise exception '384: % is not the version this was tested against (md5 %)', r.fn, v; end if;
  end loop;

  -- report_discounts gains columns, so it is dropped and created again (below).
  select md5(prosrc) into v from pg_proc where oid = to_regprocedure('public.report_discounts()');
  if v is null then raise exception '384: public.report_discounts() is missing'; end if;
  if v = '80d1a845ccebeb6c245c1897f4515fe1' then v_report := true;
  elsif v <> '7534e742656c0dd5cb818a6d468f6a7e' then
    raise exception '384: public.report_discounts() is not the version this was tested against (md5 %)', v; end if;

  -- The patches, by exact text: each edit is [anchor, replacement, times the
  -- anchor must be found (1 if left out)], applied in order.
  v_patches := jsonb_build_array(

  -- ── 1. create_invoice ─────────────────────────────────────────────────────
  jsonb_build_object('fn', 'public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
  'md5', 'dc89089ab43b718ce20148d6b4175887', 'after', 'bf0f627b032aa11d680e1a09738c2edf',
  'edits', jsonb_build_array(
    jsonb_build_array($a$  v_ev jsonb; v_bdate date;
begin$a$, $r$  v_ev jsonb; v_bdate date;
  -- 384: each line's Discount as pass 1 works it out (one entry per item, in
  -- order), the line discounts given on value that is not third-party (the
  -- invoice voucher's base), and pass 2's place in the items.
  v384_ld jsonb; v384_lds jsonb := '[]'::jsonb; v384_own_disc numeric := 0;
  v384_n integer := 0; v384_third boolean;
begin$r$),
    jsonb_build_array($a$    -- Third-party + per-line voucher rules operate on the CHARGED value.
    -- 370: an event ticket is not a product either.
    if v_kind not in ('promotion','voucher','therapy','special_product','rental','credit_package','premium_bundle','event_ticket') then
      if v_ptype = 'third_party' then v_third_sum := v_third_sum + v_line_total; end if;
      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      if v_line_voucher is not null then
        if v_ptype = 'third_party' then
          raise exception 'Discounts cannot be applied to third-party products ("%")',
            (select name from public.products where id = v_product_id);
        end if;
        select * into v_lv from public.vouchers where id = v_line_voucher and deleted_at is null;
        if not found then raise exception 'Line voucher not found'; end if;
        if v_lv.voucher_kind = 'normal' then raise exception 'Voucher "%" is not a discount voucher', v_lv.name; end if;
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
        v_line_disc_sum := v_line_disc_sum + v_line_disc;
      end if;
    end if;
  end loop;$a$, $r$    -- Third-party value stays out of the invoice voucher's base.
    -- 370: an event ticket is not a product either.
    v384_third := v_kind not in ('promotion','voucher','therapy','special_product','rental','credit_package','premium_bundle','event_ticket')
                  and v_ptype is not distinct from 'third_party';
    if v384_third then v_third_sum := v_third_sum + v_line_total; end if;
    -- 384: the line's one Discount on its CHARGED value: which lines take
    -- which option, FOC or a discount, the birthday, the bounds and the
    -- reason are invoice_line_discount_for's.
    v384_ld := public.invoice_line_discount_for(v_item, v_kind, v384_third, v_line_total,
                                                p_customer_id, v_bdate, null);
    v_line_disc := (v384_ld->>'amount')::numeric;
    v_line_disc_sum := v_line_disc_sum + v_line_disc;
    if not v384_third then v384_own_disc := v384_own_disc + v_line_disc; end if;
    v384_lds := v384_lds || jsonb_build_array(v384_ld);
  end loop;$r$),
    jsonb_build_array($a$  if p_discount_voucher_id is not null and v_has_promo then
    raise exception 'A whole-invoice discount voucher cannot be used when the invoice contains a promotion/bundle. Use per-product vouchers instead.';
  end if;$a$, $r$  if p_discount_voucher_id is not null and v_has_promo then
    raise exception 'A whole-invoice discount voucher cannot be used when the invoice contains a promotion/bundle. Use per-product vouchers instead.';
  end if;
  -- 384: a Birthday voucher as the invoice's own discount voucher is a
  -- Birthday discount too: the customer's birthday or birth month, once a year.
  if p_discount_voucher_id is not null
     and exists (select 1 from public.vouchers where id = p_discount_voucher_id and discount_category = 'birthday') then
    perform public.invoice_birthday_check(p_customer_id, v_bdate, null, p_discount_voucher_id);
  end if;$r$),
    jsonb_build_array($a$    v_wbase := v_discountable - least(v_manual, v_discountable) - v_line_disc_sum;$a$,
                      $r$    -- 384: less the line discounts on that value (not those on third-party lines).
    v_wbase := v_discountable - least(v_manual, v_discountable) - v384_own_disc;$r$),
    jsonb_build_array($a$  -- PASS 2: insert lines with permanent snapshots (incl. FOC snapshots).
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');$a$, $r$  -- PASS 2: insert lines with permanent snapshots (incl. FOC snapshots).
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    -- 384: this line's Discount from pass 1; v_item_id becomes its row.
    v384_n := v384_n + 1;
    v384_ld := v384_lds->(v384_n - 1);
    v_item_id := null;$r$),
    jsonb_build_array($a$              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);

    elsif v_kind = 'therapy' and nullif(v_item->>'therapy_service_id', '') is not null then$a$,
                      $r$              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end)
      returning id into v_item_id;  -- 384

    elsif v_kind = 'therapy' and nullif(v_item->>'therapy_service_id', '') is not null then$r$),
    jsonb_build_array($a$        case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);

    elsif v_kind = 'therapy' then$a$, $r$        case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end)
      returning id into v_item_id;  -- 384

    elsif v_kind = 'therapy' then$r$),
    jsonb_build_array($a$              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);
    elsif v_kind in ('special_product','rental') then$a$, $r$              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end)
      returning id into v_item_id;  -- 384
    elsif v_kind in ('special_product','rental') then$r$),
    jsonb_build_array($a$      v_line_total := round(v_price * v_qty, 2);
      insert into public.invoice_items
        (invoice_id, line_kind, product_id, quantity, unit_price, line_total,
         store_id_snapshot, original_price, special_product_id,
         rental_rate_type, rental_periods, rental_start_date, rental_return_date)
      values (v_invoice_id, v_kind::public.invoice_line_kind, null, v_qty, v_price, v_line_total,
         p_store_id, v_price,
         (v_item->>'special_product_id')::uuid,
         nullif(v_item->>'rental_rate_type', '')::public.special_rate_type,
         coalesce((v_item->>'rental_periods')::integer, 1),
         nullif(v_item->>'rental_start_date', '')::date,
         nullif(v_item->>'rental_return_date', '')::date);$a$, $r$      -- 384: with its FOC, which pass 1 has already taken off the subtotal
      -- (it was left off the line here).
      v_gross := v_price * v_qty;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      insert into public.invoice_items
        (invoice_id, line_kind, product_id, quantity, unit_price, line_total,
         store_id_snapshot, original_price, special_product_id,
         rental_rate_type, rental_periods, rental_start_date, rental_return_date,
         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (v_invoice_id, v_kind::public.invoice_line_kind, null, v_qty, v_price, v_line_total,
         p_store_id, v_price,
         (v_item->>'special_product_id')::uuid,
         nullif(v_item->>'rental_rate_type', '')::public.special_rate_type,
         coalesce((v_item->>'rental_periods')::integer, 1),
         nullif(v_item->>'rental_start_date', '')::date,
         nullif(v_item->>'rental_return_date', '')::date,
         v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
         case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
         case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end)
      returning id into v_item_id;$r$),
    jsonb_build_array($a$      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      v_line_disc := 0;
      if v_line_voucher is not null then
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
      end if;$a$, $r$      -- 384: the voucher and amount of the line's Discount, from pass 1.
      v_line_voucher := nullif(v384_ld->>'voucher_id','')::uuid;
      v_line_disc := coalesce((v384_ld->>'amount')::numeric, 0);$r$),
    jsonb_build_array($a$              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);
    end if;
  end loop;

  perform public.write_audit('invoices', v_invoice_id, 'invoice_created', null,$a$,
                      $r$              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end)
      returning id into v_item_id;  -- 384
    end if;
    -- 384: the line's Discount: its option, percentage, reason, and who gave it.
    perform public.invoice_line_discount_write(v_item_id, v384_ld, null);
  end loop;

  perform public.write_audit('invoices', v_invoice_id, 'invoice_created', null,$r$)
  )),

  -- ── 2. update_invoice_internal ────────────────────────────────────────────
  jsonb_build_object('fn', 'public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)',
  'md5', 'e4cfc6432345d996cf4b25392d0d1887', 'after', '42be5f307a680d1828798845da06e0e6',
  'edits', jsonb_build_array(
    jsonb_build_array($a$  v_ev jsonb; v_kept_opt uuid; v_kept_qty integer;  -- 370
begin$a$, $r$  v_ev jsonb; v_kept_opt uuid; v_kept_qty integer;  -- 370
  -- 384: as in create_invoice, and the row each changed line is written to
  -- with the Discount it had before.
  v384_ld jsonb; v384_lds jsonb := '[]'::jsonb; v384_own_disc numeric := 0;
  v384_n integer := 0; v384_third boolean; v384_id uuid; v384_old jsonb; v384_missing numeric;
begin$r$),
    -- A therapy session whose price alone an Owner or Manager corrects: its
    -- Discount follows the corrected value (pass 1 here, pass 2 below).
    jsonb_build_array($a$      v_original_line.line_total:=round((v_item->>'unit_price')::numeric*v_original_line.quantity,2)-v_original_line.foc_amount;
    end if;$a$, $r$      v_original_line.line_total:=round((v_item->>'unit_price')::numeric*v_original_line.quantity,2)-v_original_line.foc_amount;
      -- 384: and its Discount on the corrected value: a percentage follows it;
      -- a manual amount above it is refused, as when it is given.
      if v_original_line.line_discount_type = 'manual' and v_original_line.line_discount > v_original_line.line_total then
        raise exception 'The discount on "%" (S$%) cannot be more than the line''s value (S$%).',
          coalesce(v_original_line.therapy_service_name_snapshot, v_original_line.plan_name_snapshot, 'this line'),
          to_char(v_original_line.line_discount, 'FM999999990.00'), to_char(v_original_line.line_total, 'FM999999990.00'); end if;
      v_original_line.line_discount := public.invoice_line_discount_rebase(v_original_line.line_discount_type,
        v_original_line.line_voucher_id, v_original_line.line_discount_percent, v_original_line.line_discount, v_original_line.line_total);
    end if;$r$),
    jsonb_build_array($a$      if exists(select 1 from public.products where id=v_original_line.product_id and product_type='third_party') then
        v_third_sum := v_third_sum + v_original_line.line_total;
      end if;
      continue;$a$, $r$      if exists(select 1 from public.products where id=v_original_line.product_id and product_type='third_party') then
        v_third_sum := v_third_sum + v_original_line.line_total;
      else
        v384_own_disc := v384_own_disc + coalesce(v_original_line.line_discount,0);  -- 384
      end if;
      -- 384: a line kept as it is keeps its Discount; pass 2 leaves it alone.
      v384_lds := v384_lds || jsonb_build_array(null::jsonb);
      continue;
    end if;
    -- 384: a saved line whose Discount alone changed is not sold again: its
    -- price, FOC, item, promotion picks and therapy stay as saved (so an ended
    -- promotion or the line's own therapy does not refuse it), and only its
    -- Discount is worked out, on its saved value; pass 2 writes just that.
    if v_original_line.id is not null and public.invoice_line_discount_only(v_original_line.id, v_item) then
      v_subtotal := v_subtotal + v_original_line.line_total;
      v_foc_total := v_foc_total + coalesce(v_original_line.foc_amount,0);
      v_has_promo := v_has_promo or v_original_line.line_kind='promotion';
      v384_third := v_original_line.line_kind = 'product'
                    and exists(select 1 from public.products where id=v_original_line.product_id and product_type='third_party');
      if v384_third then v_third_sum := v_third_sum + v_original_line.line_total; end if;
      v384_ld := public.invoice_line_discount_for(v_item, v_kind, v384_third, v_original_line.line_total, p_customer_id,
                   coalesce(v_old.business_date, (v_old.created_at at time zone 'Asia/Singapore')::date), p_invoice_id)
                 || jsonb_build_object('line_kept', true);
      v_line_disc := (v384_ld->>'amount')::numeric;
      v_line_disc_sum := v_line_disc_sum + v_line_disc;
      if not v384_third then v384_own_disc := v384_own_disc + v_line_disc; end if;
      v384_lds := v384_lds || jsonb_build_array(v384_ld);
      continue;$r$),
    jsonb_build_array($a$    -- Third-party + per-line voucher rules operate on the CHARGED value.
    -- 370: an event ticket is not a product either.
    if v_kind not in ('promotion','voucher','therapy','special_product','rental','credit_package','premium_bundle','event_ticket') then
      if v_ptype = 'third_party' then v_third_sum := v_third_sum + v_line_total; end if;
      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      if v_line_voucher is not null then
        if v_ptype = 'third_party' then
          raise exception 'Discounts cannot be applied to third-party products ("%")',
            (select name from public.products where id = v_product_id);
        end if;
        select * into v_lv from public.vouchers where id = v_line_voucher and deleted_at is null;
        if not found then raise exception 'Line voucher not found'; end if;
        if v_lv.voucher_kind = 'normal' then raise exception 'Voucher "%" is not a discount voucher', v_lv.name; end if;
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
        v_line_disc_sum := v_line_disc_sum + v_line_disc;
      end if;
    end if;
  end loop;$a$, $r$    -- Third-party value stays out of the invoice voucher's base.
    -- 370: an event ticket is not a product either.
    v384_third := v_kind not in ('promotion','voucher','therapy','special_product','rental','credit_package','premium_bundle','event_ticket')
                  and v_ptype is not distinct from 'third_party';
    if v384_third then v_third_sum := v_third_sum + v_line_total; end if;
    -- 384: the line's one Discount on its CHARGED value (as create_invoice),
    -- on the invoice's business date; this invoice's own birthday lines do
    -- not count against it.
    v384_ld := public.invoice_line_discount_for(v_item, v_kind, v384_third, v_line_total, p_customer_id,
                 coalesce(v_old.business_date, (v_old.created_at at time zone 'Asia/Singapore')::date), p_invoice_id);
    v_line_disc := (v384_ld->>'amount')::numeric;
    v_line_disc_sum := v_line_disc_sum + v_line_disc;
    if not v384_third then v384_own_disc := v384_own_disc + v_line_disc; end if;
    v384_lds := v384_lds || jsonb_build_array(v384_ld);
  end loop;$r$),
    jsonb_build_array($a$  if p_discount_voucher_id is not null and v_has_promo then
    raise exception 'A whole-invoice discount voucher cannot be used when the invoice contains a promotion/bundle. Use per-product vouchers instead.';
  end if;$a$, $r$  if p_discount_voucher_id is not null and v_has_promo then
    raise exception 'A whole-invoice discount voucher cannot be used when the invoice contains a promotion/bundle. Use per-product vouchers instead.';
  end if;
  -- 384: a Birthday voucher as the invoice's own discount voucher is a
  -- Birthday discount too, checked when it is chosen or the customer changes
  -- (correct_invoice checks it again when the customer or the date moves).
  if p_discount_voucher_id is not null
     and (p_discount_voucher_id is distinct from v_old.discount_voucher_id or p_customer_id is distinct from v_old.customer_id)
     and exists (select 1 from public.vouchers where id = p_discount_voucher_id and discount_category = 'birthday') then
    perform public.invoice_birthday_check(p_customer_id,
      coalesce(v_old.business_date, (v_old.created_at at time zone 'Asia/Singapore')::date), p_invoice_id, p_discount_voucher_id);
  end if;
  -- 384: an invoice saved before 384 with FOC on a special product or rental
  -- line has that FOC in its totals but not on the line (fault c), so its
  -- lines add up to more than it charges. A correction that does not give
  -- the FOC back would charge it again: refused.
  select coalesce(v_old.foc_total, 0) - coalesce(sum(ii.foc_amount), 0) into v384_missing
    from public.invoice_items ii where ii.invoice_id = p_invoice_id;
  if v384_missing > 0 and v_foc_total < coalesce(v_old.foc_total, 0)
     and exists (select 1 from public.invoice_items ii
                  where ii.invoice_id = p_invoice_id and ii.line_kind in ('special_product','rental')) then
    raise exception 'S$% of this invoice''s FOC was not saved on its special product or rental line, so this correction would charge it again. Give that line its FOC again in this correction, or ask the Owner to repair the invoice.',
      to_char(v384_missing, 'FM999999990.00'); end if;$r$),
    jsonb_build_array($a$    v_wbase := v_discountable - least(v_manual, v_discountable) - v_line_disc_sum;$a$,
                      $r$    -- 384: less the line discounts on that value (not those on third-party lines).
    v_wbase := v_discountable - least(v_manual, v_discountable) - v384_own_disc;$r$),
    -- A saved line whose Discount alone changed keeps its promotion picks.
    jsonb_build_array($a$       where nullif(x->>'invoice_item_id','')::uuid=ii.id and public.invoice_line_matches(ii.id,x));$a$,
                      $r$       where nullif(x->>'invoice_item_id','')::uuid=ii.id
         and (public.invoice_line_matches(ii.id,x) or public.invoice_line_discount_only(ii.id,x)));  -- 384$r$),
    -- 11c: the special and rental line, with its FOC.
    jsonb_build_array($a$      v_line_total := round(v_price * v_qty, 2);
      insert into public.invoice_items (id, invoice_id, line_kind, product_id, quantity, unit_price, line_total, store_id_snapshot, original_price, special_product_id, rental_rate_type, rental_periods, rental_start_date, rental_return_date)
      values (coalesce(nullif(v_item->>'invoice_item_id','')::uuid,gen_random_uuid()), p_invoice_id, v_kind::public.invoice_line_kind, null, v_qty, v_price, v_line_total,
         v_old.store_id, v_price,
         (v_item->>'special_product_id')::uuid,
         nullif(v_item->>'rental_rate_type', '')::public.special_rate_type,
         coalesce((v_item->>'rental_periods')::integer, 1),
         nullif(v_item->>'rental_start_date', '')::date,
         nullif(v_item->>'rental_return_date', '')::date)
      on conflict (id) do update set line_kind=excluded.line_kind, product_id=excluded.product_id, quantity=excluded.quantity, unit_price=excluded.unit_price, line_total=excluded.line_total, store_id_snapshot=excluded.store_id_snapshot, original_price=excluded.original_price, special_product_id=excluded.special_product_id, rental_rate_type=excluded.rental_rate_type, rental_periods=excluded.rental_periods, rental_start_date=excluded.rental_start_date, rental_return_date=excluded.rental_return_date;$a$,
                      $r$      -- 384: with its FOC, which pass 1 has already taken off the subtotal
      -- (it was dropped here, so an edit lost it).
      v_gross := v_price * v_qty;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      insert into public.invoice_items (id, invoice_id, line_kind, product_id, quantity, unit_price, line_total, store_id_snapshot, original_price, special_product_id, rental_rate_type, rental_periods, rental_start_date, rental_return_date,
         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (v384_id, p_invoice_id, v_kind::public.invoice_line_kind, null, v_qty, v_price, v_line_total,
         v_old.store_id, v_price,
         (v_item->>'special_product_id')::uuid,
         nullif(v_item->>'rental_rate_type', '')::public.special_rate_type,
         coalesce((v_item->>'rental_periods')::integer, 1),
         nullif(v_item->>'rental_start_date', '')::date,
         nullif(v_item->>'rental_return_date', '')::date,
         v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
         case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
         case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end)
      on conflict (id) do update set line_kind=excluded.line_kind, product_id=excluded.product_id, quantity=excluded.quantity, unit_price=excluded.unit_price, line_total=excluded.line_total, store_id_snapshot=excluded.store_id_snapshot, original_price=excluded.original_price, special_product_id=excluded.special_product_id, rental_rate_type=excluded.rental_rate_type, rental_periods=excluded.rental_periods, rental_start_date=excluded.rental_start_date, rental_return_date=excluded.rental_return_date,
        foc_quantity=excluded.foc_quantity, is_foc=excluded.is_foc, foc_amount=excluded.foc_amount, foc_original_unit_price=excluded.foc_original_unit_price, foc_reason_id=excluded.foc_reason_id, foc_reason=excluded.foc_reason, foc_by=excluded.foc_by, foc_at=excluded.foc_at;$r$),
    -- Every other changed line is written to v384_id, its saved id or a new one.
    jsonb_build_array($a$coalesce(nullif(v_item->>'invoice_item_id','')::uuid,gen_random_uuid())$a$, $r$v384_id$r$, 7),
    jsonb_build_array($a$coalesce(nullif(v_item->>'invoice_item_id','')::uuid, gen_random_uuid())$a$, $r$v384_id$r$, 1),
    jsonb_build_array($a$  -- PASS 2: insert lines with permanent snapshots (incl. FOC snapshots).
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');$a$, $r$  -- PASS 2: insert lines with permanent snapshots (incl. FOC snapshots).
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    -- 384: this line's Discount from pass 1, and the row it is written to.
    v384_n := v384_n + 1;
    v384_ld := v384_lds->(v384_n - 1);
    v384_id := coalesce(nullif(v_item->>'invoice_item_id', '')::uuid, gen_random_uuid());$r$),
    jsonb_build_array($a$      continue;
    end if;
    if public.invoice_benefit_price_only(nullif(v_item->>'invoice_item_id','')::uuid,v_item) then
      update public.invoice_items set unit_price=(v_item->>'unit_price')::numeric,
        line_total=round((v_item->>'unit_price')::numeric*quantity,2)-public.invoice_benefit_corrected_foc(id,(v_item->>'unit_price')::numeric),
        foc_amount=public.invoice_benefit_corrected_foc(id,(v_item->>'unit_price')::numeric),$a$, $r$      continue;
    end if;
    -- 384: a saved line whose Discount alone changed (pass 1): only its
    -- Discount is written; a ticket line's people stay with it.
    if v384_ld ? 'line_kept' then
      v384_old := public.invoice_line_discount_take(v384_id, p_invoice_id);
      perform public.invoice_line_discount_write(v384_id, v384_ld, v384_old);
      if v_kind = 'event_ticket' then perform public.event_sync_ticket_line(v384_id, v_item); end if;
      continue;
    end if;
    if public.invoice_benefit_price_only(nullif(v_item->>'invoice_item_id','')::uuid,v_item) then
      update public.invoice_items set unit_price=(v_item->>'unit_price')::numeric,
        line_total=round((v_item->>'unit_price')::numeric*quantity,2)-public.invoice_benefit_corrected_foc(id,(v_item->>'unit_price')::numeric),
        foc_amount=public.invoice_benefit_corrected_foc(id,(v_item->>'unit_price')::numeric),
        -- 384: its Discount on the corrected value, as pass 1 worked it out.
        line_discount=public.invoice_line_discount_rebase(line_discount_type,line_voucher_id,line_discount_percent,line_discount,
          round((v_item->>'unit_price')::numeric*quantity,2)-public.invoice_benefit_corrected_foc(id,(v_item->>'unit_price')::numeric)),$r$),
    jsonb_build_array($a$      where id=(v_item->>'invoice_item_id')::uuid and invoice_id=p_invoice_id;
      continue;
    end if;

    v_qty := (v_item->>'quantity')::integer;$a$, $r$      where id=(v_item->>'invoice_item_id')::uuid and invoice_id=p_invoice_id;
      continue;
    end if;
    -- 384: the Discount the saved line had, taken off while the line is
    -- written again (a line is never FOC and discounted at once), and put
    -- back, or replaced, below.
    v384_old := public.invoice_line_discount_take(v384_id, p_invoice_id);

    v_qty := (v_item->>'quantity')::integer;$r$),
    jsonb_build_array($a$      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      v_line_disc := 0;
      if v_line_voucher is not null then
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
      end if;$a$, $r$      -- 384: the voucher and amount of the line's Discount, from pass 1.
      v_line_voucher := nullif(v384_ld->>'voucher_id','')::uuid;
      v_line_disc := coalesce((v384_ld->>'amount')::numeric, 0);$r$),
    jsonb_build_array($a$    end if;
  end loop;

  -- Save Earth (columns preserved on the header) re-enters through the$a$, $r$    end if;
    -- 384: the line's Discount: its option, percentage, reason, and who gave
    -- it (kept when the Discount is the one it had).
    perform public.invoice_line_discount_write(v384_id, v384_ld, v384_old);
  end loop;

  -- Save Earth (columns preserved on the header) re-enters through the$r$)
  )),

  -- ── 3. correct_invoice: the birthday follows the customer and the date ────
  jsonb_build_object('fn', 'public.correct_invoice(uuid,jsonb,jsonb,text,uuid)',
  'md5', '83a2d4d1445683b628daab8b0236fc4c', 'after', 'b3f99df8a82012b140a99bd96cb2cf91',
  'edits', jsonb_build_array(
    jsonb_build_array($a$ select * into n from public.invoices where id=i.id;
 v_paid:=public.invoice_net_received(i.id);$a$, $r$ select * into n from public.invoices where id=i.id;
 -- 384: a Birthday discount is for this customer on this date, so a
 -- correction that moves either checks the invoice's birthday lines again.
 if (n.customer_id, n.business_date) is distinct from (i.customer_id, i.business_date) then
   perform public.invoice_birthday_lines_check(i.id); end if;
 v_paid:=public.invoice_net_received(i.id);$r$),
    -- The screen sends the service staff with every correction, unchanged or
    -- not; only a change of them re-runs the money path.
    jsonb_build_array($a$   (i.manual_discount,i.discount_voucher_id,i.save_earth_applied,i.save_earth_amount) or p_header ? 'service_staff' then$a$,
                      $r$   (i.manual_discount,i.discount_voucher_id,i.save_earth_applied,i.save_earth_amount)
   -- 384: when they change, not whenever the screen sends them, so a note,
   -- date, customer or payment correction leaves the invoice's money alone.
   or (p_header ? 'service_staff' and v_staff is distinct from
       (select coalesce(jsonb_agg(x order by x),'[]') from jsonb_array_elements(p_header->'service_staff') x)) then$r$)
  )),

  -- ── 4. invoice_line_matches: a changed Discount is a changed line ─────────
  jsonb_build_object('fn', 'public.invoice_line_matches(uuid,jsonb)',
  'md5', '856cf4dd899ff7f67f682dc5e3e6a850', 'after', '3b24939e07962d6ac3de82813bc3a83a',
  'edits', jsonb_build_array(
    jsonb_build_array($a$  if p_line ? 'unit_price' and (p_line->>'unit_price')::numeric is distinct from i.unit_price then return false; end if;$a$,
                      $r$  -- 384: and its Discount: the option (a line saved before 384 with a
  -- voucher is that voucher's category), a manual amount, a percentage and
  -- the reason. Exchange credit (no voucher, no option) is not compared.
  if public.invoice_line_discount_kind(i.line_discount_type, i.line_voucher_id)
       is distinct from public.invoice_line_discount_kind(nullif(p_line->>'line_discount_type',''), nullif(p_line->>'line_voucher_id','')::uuid)
     or (i.line_discount_type = 'manual'
         and round(nullif(p_line->>'line_discount_amount','')::numeric, 2) is distinct from i.line_discount)
     or (i.line_discount_type = 'percentage'
         and round(nullif(p_line->>'line_discount_percent','')::numeric, 3) is distinct from i.line_discount_percent)
     or (i.line_discount_type in ('manual','percentage')
         and nullif(btrim(p_line->>'line_discount_reason'),'') is distinct from i.line_discount_reason) then
    return false; end if;
  if p_line ? 'unit_price' and (p_line->>'unit_price')::numeric is distinct from i.unit_price then return false; end if;$r$)
  )),

  -- ── 5. invoice_operational_lines_match: a Discount moves no stock ─────────
  jsonb_build_object('fn', 'public.invoice_operational_lines_match(uuid,jsonb)',
  'md5', '5f394f5839b7728d9fe1216e1de83412', 'after', 'dc1c5430914fd0b0f4cc646b2d0badb9',
  'edits', jsonb_build_array(
    jsonb_build_array($a$'line_voucher_id',it.line_voucher_id)))$a$,
                      $r$'line_voucher_id',it.line_voucher_id,
   -- 384: nor does a change of Discount alone.
   'line_discount_type',it.line_discount_type,'line_discount_amount',it.line_discount,
   'line_discount_percent',it.line_discount_percent,'line_discount_reason',it.line_discount_reason)))$r$)
  )),

  -- ── 6. apply_line_foc (Make FOC): FOC or a discount, never both ───────────
  jsonb_build_object('fn', 'public.apply_line_foc(uuid,integer,uuid,text)',
  'md5', '8f0dd45852e137f85559139aa5368e37', 'after', '813831f58318f02c3d92d59b69cf8a7b',
  'edits', jsonb_build_array(
    jsonb_build_array($a$  -- Mandatory reason (validated before anything is written).$a$,
                      $r$  -- 384: one Discount per line. A line with a discount (a voucher saved
  -- before 384 included) is not made FOC on top of it.
  if v_li.line_discount_type is not null or v_li.line_voucher_id is not null then
    raise exception 'This line already has a discount. A line can be FOC or have a discount, not both: edit the invoice to take the discount off first.'; end if;

  -- Mandatory reason (validated before anything is written).$r$)
  )),

  -- ── 7. reprice_invoice_lines (Confirm FOC): the discount follows the price ─
  jsonb_build_object('fn', 'public.reprice_invoice_lines(uuid,boolean)',
  'md5', '454e726d19cae93e8336b1bb89d7da4f', 'after', '1e30330eae2f8387d0d9622a69a1e103',
  'edits', jsonb_build_array(
    jsonb_build_array($a$        line_discount = case when line_voucher_id is not null then public.voucher_discount_amount(line_voucher_id, v_charged) else line_discount end,$a$,
                      $r$        -- 384: a percentage follows the new value, a manual amount is capped by it.
        line_discount = public.invoice_line_discount_rebase(line_discount_type, line_voucher_id, line_discount_percent, line_discount, v_charged),$r$),
    jsonb_build_array($a$      update public.invoice_items set unit_price=v_new, line_total=v_charged, foc_amount=v_foc,
        price_mode=null, price_source='voucher',$a$, $r$      update public.invoice_items set unit_price=v_new, line_total=v_charged, foc_amount=v_foc,
        line_discount = public.invoice_line_discount_rebase(line_discount_type, line_voucher_id, line_discount_percent, line_discount, v_charged),  -- 384
        price_mode=null, price_source='voucher',$r$),
    jsonb_build_array($a$        line_total=v_charged, foc_amount=v_foc,
        price_mode=null, price_source='promotion',$a$, $r$        line_total=v_charged, foc_amount=v_foc,
        line_discount = public.invoice_line_discount_rebase(line_discount_type, line_voucher_id, line_discount_percent, line_discount, v_charged),  -- 384
        price_mode=null, price_source='promotion',$r$)
  )),

  -- ── 8. refresh_invoice_discount_total: the same sum as create_invoice ─────
  jsonb_build_object('fn', 'public.refresh_invoice_discount_total(uuid)',
  'md5', 'b22e4c68caac029313b62bb5d4ad4596', 'after', '3b983d77df1c81146b7fd56f02d8ca7f',
  'edits', jsonb_build_array(
    jsonb_build_array($a$declare v_inv public.invoices%rowtype; v_line_disc numeric; v_voucher_disc numeric := 0; v_total numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  select coalesce(sum(coalesce(line_discount,0)),0) into v_line_disc
    from public.invoice_items where invoice_id = p_invoice_id;
  if v_inv.discount_voucher_id is not null then
    v_voucher_disc := public.voucher_discount_amount(v_inv.discount_voucher_id,
      greatest(0, v_inv.subtotal - v_line_disc));
  end if;
  v_total := coalesce(v_inv.manual_discount,0) + v_line_disc + v_voucher_disc
             + case when v_inv.save_earth_applied then coalesce(v_inv.save_earth_amount,0) else 0 end;$a$,
                      $r$-- 384: the same sum create_invoice makes (99), so an edit or an FOC change
-- never changes what the invoice's discount voucher gives: the manual
-- discount, capped by the subtotal; the line discounts; and the voucher, on
-- the value that is not third-party, less the manual discount (up to that
-- value) and the line discounts given on it. Then Save Earth, as before.
-- Third-party: a product line whose product is third-party, as pass 1 of
-- update_invoice_internal reads it.
declare v_inv public.invoices%rowtype; v_line_disc numeric; v_voucher_disc numeric := 0; v_total numeric;
        v_sub numeric; v_manual numeric; v_third numeric; v_own_disc numeric; v_wbase numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  v_sub := coalesce(v_inv.subtotal, 0);
  v_manual := coalesce(v_inv.manual_discount, 0);
  select coalesce(sum(ii.line_total) filter (where t.third), 0),
         coalesce(sum(coalesce(ii.line_discount,0)), 0),
         coalesce(sum(coalesce(ii.line_discount,0)) filter (where not t.third), 0)
    into v_third, v_line_disc, v_own_disc
    from public.invoice_items ii
    cross join lateral (select ii.line_kind = 'product'
                               and exists (select 1 from public.products p
                                            where p.id = ii.product_id and p.product_type = 'third_party') as third) t
   where ii.invoice_id = p_invoice_id;
  if v_inv.discount_voucher_id is not null then
    v_wbase := (v_sub - v_third) - least(v_manual, v_sub - v_third) - v_own_disc;
    if v_wbase < 0 then v_wbase := 0; end if;
    v_voucher_disc := public.voucher_discount_amount(v_inv.discount_voucher_id, v_wbase);
  end if;
  v_total := least(least(v_manual, v_sub) + v_line_disc + v_voucher_disc, v_sub)
             + case when v_inv.save_earth_applied then coalesce(v_inv.save_earth_amount,0) else 0 end;$r$)
  )));

  -- Each patched function: present; left alone when it already has this
  -- migration's version; else the tested version, with every anchor found
  -- the expected number of times. The patched text is only built here.
  for p in select x from jsonb_array_elements(v_patches) x
  loop
    if to_regprocedure(p->>'fn') is null then raise exception '384: % is missing', p->>'fn'; end if;
    v_after := v_after || jsonb_build_object(p->>'fn', p->>'after');
    select md5(prosrc) into v from pg_proc where oid = to_regprocedure(p->>'fn');
    if v = p->>'after' then raise notice '384: % already patched; left alone.', p->>'fn'; continue; end if;
    if v <> p->>'md5' then
      raise exception '384: % is not the version this was tested against (md5 %)', p->>'fn', v; end if;
    d := pg_get_functiondef(to_regprocedure(p->>'fn'));
    k := 0;
    for e in select x from jsonb_array_elements(p->'edits') x
    loop
      k := k + 1;
      n := (length(d) - length(replace(d, e->>0, ''))) / length(e->>0);
      if n <> coalesce((e->>2)::int, 1) then
        raise exception '384: % anchor % found % times', p->>'fn', k, n; end if;
      d := replace(d, e->>0, e->>1);
    end loop;
    v_install := v_install || d;
  end loop;

  -- ── 9. Every check passed: the columns ───────────────────────────────────
  alter table public.vouchers
    add column if not exists discount_category text,
    add column if not exists birthday_rule text;
  alter table public.invoice_items
    add column if not exists line_discount_type text,
    add column if not exists line_discount_percent numeric(6,3),
    add column if not exists line_discount_reason text,
    add column if not exists line_discount_by uuid references public.profiles(id),
    add column if not exists line_discount_at timestamptz;

  -- ── 10. The rules, in one place each ─────────────────────────────────────
  execute $ddl$
create or replace function public.invoice_line_discount_kind(p_type text, p_voucher_id uuid)
returns text
language sql
stable
security definer
set search_path to 'public'
as $f$
  -- 384: which Discount a line carries: its option, or for a line saved
  -- before 384 with a voucher, that voucher's category. None for a line
  -- with neither (no discount, or exchange credit).
  select coalesce(p_type, case when p_voucher_id is not null then
           coalesce((select v.discount_category from public.vouchers v where v.id = p_voucher_id), 'voucher') end)
$f$
$ddl$;

  execute $ddl$
create or replace function public.invoice_birthday_check(p_customer_id uuid, p_business_date date, p_invoice_id uuid, p_voucher_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $f$
-- 384: a Birthday discount is for the customer's birthday or birth month (the
-- voucher's rule) on the invoice's business date, and for one invoice a
-- calendar year per customer (any number of its lines). Cancelled, refunded
-- and deleted invoices do not count, nor p_invoice_id (the invoice being
-- edited). A line saved before 384 with a Birthday voucher counts, and so
-- does an invoice whose own discount voucher is a Birthday voucher.
declare v public.vouchers%rowtype; v_dob date; v_first date; v_day date; v_used text;
begin
  select * into v from public.vouchers where id = p_voucher_id;
  if p_customer_id is null then
    raise exception 'Choose the customer and add their date of birth to give a Birthday discount.'; end if;
  select c.date_of_birth into v_dob from public.customers c where c.id = p_customer_id;
  if v_dob is null then
    raise exception 'Add the customer''s date of birth to give a Birthday discount.'; end if;
  if v.birthday_rule = 'actual_date' then
    -- The birthday in the invoice's year; 29 Feb is 28 Feb in a year without one.
    v_first := make_date(extract(year from p_business_date)::int, extract(month from v_dob)::int, 1);
    v_day := v_first + (least(extract(day from v_dob)::int,
                              extract(day from (v_first + interval '1 month' - interval '1 day'))::int) - 1);
    if p_business_date <> v_day then
      raise exception '"%" is for the customer''s birthday only (%). This invoice is dated %.',
        v.name, to_char(v_day, 'FMDD Mon'), to_char(p_business_date, 'FMDD Mon YYYY'); end if;
  elsif v.birthday_rule = 'whole_month' then
    if extract(month from p_business_date) <> extract(month from v_dob) then
      raise exception '"%" is for the customer''s birth month only (%). This invoice is dated %.',
        v.name, to_char(v_dob, 'FMMonth'), to_char(p_business_date, 'FMDD Mon YYYY'); end if;
  else
    raise exception 'Set whether "%" is for the birthday itself or the whole birth month on the Vouchers page first.', v.name;
  end if;
  -- Two invoices saved at once for one customer cannot both pass.
  perform pg_advisory_xact_lock(hashtext('384 birthday ' || p_customer_id::text));
  select i.invoice_no into v_used
    from public.invoices i
   where i.customer_id = p_customer_id
     and i.id is distinct from p_invoice_id
     and i.deleted_at is null
     and i.status not in ('cancelled','refunded')
     and extract(year from coalesce(i.business_date, (i.created_at at time zone 'Asia/Singapore')::date))
         = extract(year from p_business_date)
     and (exists (select 1 from public.invoice_items ii
                   where ii.invoice_id = i.id
                     and public.invoice_line_discount_kind(ii.line_discount_type, ii.line_voucher_id) = 'birthday')
          or exists (select 1 from public.vouchers dv
                      where dv.id = i.discount_voucher_id and dv.discount_category = 'birthday'))
   order by coalesce(i.business_date, (i.created_at at time zone 'Asia/Singapore')::date), i.invoice_no
   limit 1;
  if v_used is not null then
    raise exception 'Birthday discount already used this year on %.', v_used; end if;
end $f$
$ddl$;

  execute $ddl$
create or replace function public.invoice_birthday_lines_check(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $f$
-- 384: every Birthday discount on the invoice, checked again for its
-- customer and date as they are now (a correction moved one of them): its
-- Birthday lines, those saved before 384 too (as invoice_birthday_check
-- counts them), and a Birthday voucher as its own discount voucher.
declare i public.invoices%rowtype; r record;
begin
  select * into i from public.invoices where id = p_invoice_id;
  for r in select ii.line_voucher_id as voucher_id from public.invoice_items ii
            where ii.invoice_id = p_invoice_id
              and public.invoice_line_discount_kind(ii.line_discount_type, ii.line_voucher_id) = 'birthday'
           union
           select v.id from public.vouchers v where v.id = i.discount_voucher_id and v.discount_category = 'birthday'
  loop
    perform public.invoice_birthday_check(i.customer_id,
      coalesce(i.business_date, (i.created_at at time zone 'Asia/Singapore')::date), i.id, r.voucher_id);
  end loop;
end $f$
$ddl$;

  execute $ddl$
create or replace function public.invoice_line_discount_for(
  p_item jsonb, p_kind text, p_third_party boolean, p_value numeric,
  p_customer_id uuid, p_business_date date, p_invoice_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $f$
-- 384: the one Discount an invoice line may carry, checked and worked out on
-- p_value, the line's value before the discount (what it charges). Returns
-- {type, voucher_id, percent, reason, amount}; type null and amount 0 when the
-- line has no discount (FOC is the line's own keys, as before). The amount is
-- what invoice_items.line_discount holds. The messages are shown to staff.
declare
  v_type text := nullif(btrim(coalesce(p_item->>'line_discount_type', '')), '');
  v_voucher uuid := nullif(p_item->>'line_voucher_id', '')::uuid;
  v_reason text := nullif(btrim(coalesce(p_item->>'line_discount_reason', '')), '');
  v_name text; v_option text; v_v public.vouchers%rowtype; v_amount numeric; v_pct numeric;
begin
  -- A voucher with no option (website and seminar orders, screens from before
  -- 384) is that voucher's own category.
  if v_type is null and v_voucher is not null then
    v_type := public.invoice_line_discount_kind(null, v_voucher); end if;
  if v_type is null then
    return jsonb_build_object('type', null, 'voucher_id', null, 'percent', null, 'reason', null, 'amount', 0); end if;
  if v_type not in ('voucher','birthday','staff','manual','percentage') then
    raise exception 'Choose the line''s discount from the list.'; end if;

  v_name := coalesce(case p_kind
      when 'promotion' then (select x.name from public.promotions x where x.id = nullif(p_item->>'promotion_id','')::uuid)
      when 'voucher' then (select x.name from public.vouchers x where x.id = nullif(p_item->>'voucher_id','')::uuid)
      when 'therapy' then coalesce(
        (select x.name from public.therapy_services x where x.id = nullif(p_item->>'therapy_service_id','')::uuid),
        (select x.name from public.unlimited_therapy_packages x where x.id = nullif(p_item->>'therapy_package_id','')::uuid))
      when 'special_product' then (select x.name from public.special_products x where x.id = nullif(p_item->>'special_product_id','')::uuid)
      when 'rental' then (select x.name from public.special_products x where x.id = nullif(p_item->>'special_product_id','')::uuid)
      when 'event_ticket' then (select x.name from public.event_ticket_options x where x.id = nullif(p_item->>'event_ticket_option_id','')::uuid)
      when 'credit_package' then (select x.name from public.credit_packages x where x.id = nullif(p_item->>'credit_package_id','')::uuid)
      when 'premium_bundle' then (select x.name from public.premium_bundles x where x.id = nullif(p_item->>'premium_bundle_id','')::uuid)
      else (select x.name from public.products x where x.id = nullif(p_item->>'product_id','')::uuid) end, 'this line');
  v_option := case v_type when 'voucher' then 'A voucher' when 'birthday' then 'A Birthday discount'
                          when 'staff' then 'A Staff discount' when 'manual' then 'A manual discount'
                          else 'A percentage discount' end;

  -- One per line: FOC, or one discount.
  if coalesce(nullif(p_item->>'foc_quantity','')::integer, 0) > 0
     or coalesce(nullif(p_item->>'is_foc','')::boolean, false) then
    raise exception 'A line can be FOC or have a discount, not both. Choose one for "%".', v_name; end if;
  -- A discount would scale a credit package's or premium bundle's credit down.
  if p_kind in ('credit_package','premium_bundle') then
    raise exception '"%" cannot take a line discount. Use the invoice''s manual discount or discount voucher instead.', v_name; end if;

  if v_type in ('voucher','birthday','staff') then
    -- As the line voucher and FOC: not an Inventory Manager; our own products only.
    if public.current_user_role() = 'inventory_manager' then
      raise exception 'Inventory Manager cannot give a voucher, Birthday or Staff discount'; end if;
    if p_kind <> 'product' then
      raise exception '% is for our own products only. Use a manual or percentage discount on "%".', v_option, v_name; end if;
    if p_third_party then
      raise exception '% cannot be used on a third-party product ("%"). Use a manual or percentage discount.', v_option, v_name; end if;
    if v_voucher is null then
      raise exception 'Choose which % to use on "%".',
        case v_type when 'voucher' then 'voucher' when 'birthday' then 'Birthday discount' else 'Staff discount' end, v_name; end if;
    select * into v_v from public.vouchers where id = v_voucher and deleted_at is null;
    if not found then raise exception 'Line voucher not found'; end if;
    if v_v.voucher_kind = 'normal' then raise exception 'Voucher "%" is not a discount voucher', v_v.name; end if;
    if coalesce(v_v.discount_category, 'voucher') <> v_type then
      raise exception '"%" is not on the % list. Choose one from that list.', v_v.name,
        case v_type when 'voucher' then 'Vouchers' when 'birthday' then 'Birthday discount' else 'Staff discount' end; end if;
    if v_type = 'birthday' then
      perform public.invoice_birthday_check(p_customer_id, p_business_date, p_invoice_id, v_voucher); end if;
    v_amount := public.voucher_discount_amount(v_voucher, p_value);
    return jsonb_build_object('type', v_type, 'voucher_id', v_voucher, 'percent', null, 'reason', null, 'amount', v_amount);
  end if;

  -- Manual and Percentage: anyone who may invoice, with an internal reason.
  -- An amount is kept to the cent, and its bounds hold for what is kept. A
  -- percentage is kept to 3 decimals; its bounds hold for what was typed and
  -- for what is kept.
  if v_type = 'manual' then
    v_amount := round(nullif(p_item->>'line_discount_amount', '')::numeric, 2);
    if v_amount is null or v_amount <= 0 then
      raise exception 'Enter the discount on "%" in S$ (more than 0).', v_name; end if;
    if v_amount > p_value then
      raise exception 'The discount on "%" (S$%) cannot be more than the line''s value (S$%).', v_name,
        to_char(v_amount, 'FM999999990.00'), to_char(p_value, 'FM999999990.00'); end if;
  else
    v_pct := nullif(p_item->>'line_discount_percent', '')::numeric;
    if v_pct is null or round(v_pct, 3) <= 0 or v_pct > 100 then
      raise exception 'The percentage discount on "%" must be more than 0%% and at most 100%%.', v_name; end if;
    v_pct := round(v_pct, 3);
    v_amount := round(p_value * v_pct / 100, 2);
  end if;
  if v_reason is null then
    raise exception 'Give the reason for the discount on "%". It stays on the invoice for staff and is never printed.', v_name; end if;
  return jsonb_build_object('type', v_type, 'voucher_id', null, 'percent', v_pct, 'reason', v_reason, 'amount', v_amount);
end $f$
$ddl$;

  execute $ddl$
create or replace function public.invoice_line_discount_take(p_item_id uuid, p_invoice_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $f$
-- 384: a saved line about to be written again: the Discount it has (for
-- invoice_line_discount_write to keep who gave it, when it stays), with its
-- option taken off so the line can become FOC in the same save.
declare v jsonb;
begin
  select jsonb_build_object('kind', public.invoice_line_discount_kind(x.line_discount_type, x.line_voucher_id),
           'voucher_id', x.line_voucher_id, 'percent', x.line_discount_percent, 'reason', x.line_discount_reason,
           'amount', x.line_discount, 'by', x.line_discount_by, 'at', x.line_discount_at)
    into v from public.invoice_items x where x.id = p_item_id and x.invoice_id = p_invoice_id;
  update public.invoice_items set line_discount_type = null, line_discount_percent = null, line_discount_reason = null
   where id = p_item_id and invoice_id = p_invoice_id and line_discount_type is not null;
  return v;
end $f$
$ddl$;

  execute $ddl$
create or replace function public.invoice_line_discount_write(p_item_id uuid, p_ld jsonb, p_old jsonb)
returns void
language plpgsql
security definer
set search_path to 'public'
as $f$
-- 384: writes a line's Discount (p_ld, from invoice_line_discount_for) on the
-- line. The same Discount it had before (p_old) keeps who gave it and when.
declare v_type text := p_ld->>'type'; v_same boolean; v_by uuid; v_at timestamptz;
begin
  if p_item_id is null then return; end if;
  v_same := p_old is not null and v_type is not null
    and (p_old->>'kind', p_old->>'voucher_id', (p_old->>'percent')::numeric, p_old->>'reason',
         case when p_old->>'kind' = 'manual' then (p_old->>'amount')::numeric end)
        is not distinct from
        (v_type, p_ld->>'voucher_id', (p_ld->>'percent')::numeric, p_ld->>'reason',
         case when v_type = 'manual' then (p_ld->>'amount')::numeric end);
  v_by := case when v_type is null then null when v_same then nullif(p_old->>'by', '')::uuid else auth.uid() end;
  v_at := case when v_type is null then null when v_same then (p_old->>'at')::timestamptz else now() end;
  update public.invoice_items
     set line_discount_type = v_type,
         line_voucher_id = nullif(p_ld->>'voucher_id', '')::uuid,
         line_discount = coalesce((p_ld->>'amount')::numeric, 0),
         line_discount_percent = (p_ld->>'percent')::numeric,
         line_discount_reason = p_ld->>'reason',
         line_discount_by = v_by,
         line_discount_at = v_at
   where id = p_item_id
     and (line_discount_type, line_voucher_id, line_discount, line_discount_percent, line_discount_reason,
          line_discount_by, line_discount_at)
         is distinct from (v_type, nullif(p_ld->>'voucher_id', '')::uuid, coalesce((p_ld->>'amount')::numeric, 0),
                           (p_ld->>'percent')::numeric, p_ld->>'reason', v_by, v_at);
end $f$
$ddl$;

  execute $ddl$
create or replace function public.invoice_line_discount_rebase(p_type text, p_voucher_id uuid, p_percent numeric, p_amount numeric, p_value numeric)
returns numeric
language sql
stable
security definer
set search_path to 'public'
as $f$
  -- 384: a line's discount when its value changes (a reprice): a percentage
  -- follows the value, a manual amount is capped by it, a voucher is worked
  -- out again (as before 384), exchange credit stays.
  select case when p_type = 'percentage' then round(p_value * p_percent / 100, 2)
              when p_type = 'manual' then least(p_amount, p_value)
              when p_voucher_id is not null then public.voucher_discount_amount(p_voucher_id, p_value)
              else p_amount end
$f$
$ddl$;

  execute $ddl$
create or replace function public.invoice_line_discount_only(p_item_id uuid, p_line jsonb)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $f$
  -- 384: a saved line sent back with only its Discount changed: it is not the
  -- line as saved, but would be with the saved Discount put back.
  select coalesce((select not public.invoice_line_matches(it.id, p_line)
                          and public.invoice_line_matches(it.id, p_line || jsonb_build_object(
                                'line_voucher_id', it.line_voucher_id, 'line_discount_type', it.line_discount_type,
                                'line_discount_amount', it.line_discount, 'line_discount_percent', it.line_discount_percent,
                                'line_discount_reason', it.line_discount_reason))
                     from public.invoice_items it where it.id = p_item_id), false)
$f$
$ddl$;

  execute $ddl$
create or replace function public.trg_voucher_discount_category()
returns trigger
language plpgsql
set search_path to 'public'
as $f$
-- 384: a discount voucher is on one list of the line's Discount (Vouchers,
-- Birthday or Staff; Vouchers when none is given); a voucher that is sold is
-- on none. Only a Birthday voucher has a rule, and it must have one.
begin
  if new.voucher_kind = 'normal' then
    new.discount_category := null; new.birthday_rule := null;
    return new;
  end if;
  new.discount_category := coalesce(nullif(btrim(coalesce(new.discount_category, '')), ''), 'voucher');
  if new.discount_category <> 'birthday' then
    new.birthday_rule := null;
  elsif new.birthday_rule is null then
    raise exception 'Choose whether "%" is for the birthday itself or the whole birth month.', new.name;
  end if;
  return new;
end $f$
$ddl$;

  execute $ddl$
create or replace function public.trg_invoice_item_line_discount_reason()
returns trigger
language plpgsql
set search_path to 'public'
as $f$
-- 384: a manual or percentage line discount carries its internal reason
-- (whitespace is not a reason); no other line keeps one.
begin
  new.line_discount_reason := nullif(btrim(coalesce(new.line_discount_reason, '')), '');
  if new.line_discount_type in ('manual','percentage') then
    if new.line_discount_reason is null then
      raise exception 'Give the reason for the line discount. It stays on the invoice for staff and is never printed.'; end if;
  else
    new.line_discount_reason := null;
  end if;
  return new;
end $f$
$ddl$;

  foreach v in array array['public.invoice_line_discount_kind(text,uuid)',
                           'public.invoice_birthday_check(uuid,date,uuid,uuid)',
                           'public.invoice_birthday_lines_check(uuid)',
                           'public.invoice_line_discount_for(jsonb,text,boolean,numeric,uuid,date,uuid)',
                           'public.invoice_line_discount_take(uuid,uuid)',
                           'public.invoice_line_discount_write(uuid,jsonb,jsonb)',
                           'public.invoice_line_discount_rebase(text,uuid,numeric,numeric,numeric)',
                           'public.invoice_line_discount_only(uuid,jsonb)',
                           'public.trg_voucher_discount_category()',
                           'public.trg_invoice_item_line_discount_reason()']
  loop
    execute format('revoke all on function %s from public, anon, authenticated', v);
    execute format('grant execute on function %s to service_role', v);
  end loop;

  -- ── 11. And the patched functions ────────────────────────────────────────
  foreach d in array v_install loop
    execute d;
  end loop;

  -- ── 12. report_discounts: a column per option ────────────────────────────
  if v_report then
    drop function public.report_discounts();
    execute $ddl$
create function public.report_discounts()
returns table(invoice_id uuid, invoice_no text, paid_date date, store_name text, staff_names text, customer_name text,
              save_earth numeric, voucher_discount numeric, promotion_discount numeric, line_discount numeric,
              manual_discount numeric, total_discount numeric,
              line_voucher_discount numeric, birthday_discount numeric, staff_discount numeric,
              line_manual_discount numeric, line_percentage_discount numeric, exchange_credit numeric)
language sql
stable
security definer
set search_path to 'public'
as $f$
  select
    i.id, i.invoice_no, public.invoice_effective_date(i.id), s.name,
    (select string_agg(pr.full_name, ', ') from public.invoice_service_staff iss
      join public.profiles pr on pr.id = iss.staff_id where iss.invoice_id = i.id),
    c.full_name,
    case when i.save_earth_applied then coalesce(i.save_earth_amount,0) else 0 end,
    -- 366: what the invoice was actually given, read from the invoice itself:
    -- its discount total less the manual, Save Earth and line discounts. Not
    -- recalculated through voucher_discount_amount, which refuses a voucher
    -- that has since been retired and would fail the whole report.
    case when i.discount_voucher_id is not null then
      greatest(round(coalesce(i.discount_total,0) - coalesce(i.manual_discount,0)
        - case when i.save_earth_applied then coalesce(i.save_earth_amount,0) else 0 end
        - l.all_lines, 2), 0)
    else 0 end,
    l.promotion,
    l.all_lines,
    coalesce(i.manual_discount,0),
    coalesce(i.discount_total,0),
    -- 384: the line discounts by the option given (a line saved before 384
    -- with a voucher counts under that voucher's category), and exchange
    -- credit (a line discount with neither) on its own.
    l.voucher, l.birthday, l.staff, l.manual, l.percentage, l.exchange
  from public.invoices i
  left join public.customers c on c.id = i.customer_id
  left join public.stores s on s.id = i.store_id
  cross join lateral (
    select coalesce(sum(coalesce(ii.line_discount,0)), 0) as all_lines,
           coalesce(sum(ii.line_discount) filter (where ii.promotion_id is not null), 0) as promotion,
           coalesce(sum(ii.line_discount) filter (where k.kind = 'voucher'), 0) as voucher,
           coalesce(sum(ii.line_discount) filter (where k.kind = 'birthday'), 0) as birthday,
           coalesce(sum(ii.line_discount) filter (where k.kind = 'staff'), 0) as staff,
           coalesce(sum(ii.line_discount) filter (where k.kind = 'manual'), 0) as manual,
           coalesce(sum(ii.line_discount) filter (where k.kind = 'percentage'), 0) as percentage,
           coalesce(sum(ii.line_discount) filter (where k.kind is null), 0) as exchange
      from public.invoice_items ii
      cross join lateral (select public.invoice_line_discount_kind(ii.line_discount_type, ii.line_voucher_id) as kind) k
     where ii.invoice_id = i.id) l
  where i.deleted_at is null and public.user_has_store_access(i.store_id) and i.status in ('paid','partially_paid','completed_foc') and coalesce(i.discount_total,0) > 0
  order by public.invoice_effective_date(i.id) desc,i.id;
$f$
$ddl$;
    revoke all on function public.report_discounts() from public, anon;
    grant execute on function public.report_discounts() to authenticated, service_role;
  end if;

  -- ── 13. The voucher lists, filled in once from the names ─────────────────
  drop trigger if exists voucher_discount_category on public.vouchers;
  create trigger voucher_discount_category before insert or update on public.vouchers
    for each row execute function public.trg_voucher_discount_category();
  update public.vouchers
     set birthday_rule = case when name ilike 'birthday%' and name ilike '%actual date%' then 'actual_date'
                              when name ilike 'birthday%' and name ilike '%whole month%' then 'whole_month' end,
         discount_category = case when name ilike 'birthday%' and (name ilike '%actual date%' or name ilike '%whole month%') then 'birthday'
                                  when name ilike 'staff%' then 'staff'
                                  else 'voucher' end
   where voucher_kind <> 'normal' and discount_category is null;
  get diagnostics n = row_count;
  raise notice '384: % discount voucher(s) given a list', n;

  alter table public.vouchers drop constraint if exists vouchers_discount_category_check;
  alter table public.vouchers add constraint vouchers_discount_category_check
    check ((voucher_kind = 'normal' and discount_category is null)
           or (voucher_kind <> 'normal' and discount_category in ('voucher','birthday','staff')));
  alter table public.vouchers drop constraint if exists vouchers_birthday_rule_check;
  alter table public.vouchers add constraint vouchers_birthday_rule_check
    check (case when discount_category = 'birthday' then birthday_rule in ('actual_date','whole_month')
                else birthday_rule is null end);

  -- ── 14. The line's Discount: its shape, and its reason ───────────────────
  alter table public.invoice_items drop constraint if exists invoice_items_line_discount_type_check;
  alter table public.invoice_items add constraint invoice_items_line_discount_type_check
    check (line_discount_type is null or line_discount_type in ('voucher','birthday','staff','manual','percentage'));
  alter table public.invoice_items drop constraint if exists invoice_items_line_discount_percent_check;
  alter table public.invoice_items add constraint invoice_items_line_discount_percent_check
    check (line_discount_percent is null or (line_discount_percent > 0 and line_discount_percent <= 100));
  alter table public.invoice_items drop constraint if exists invoice_items_line_discount_shape;
  alter table public.invoice_items add constraint invoice_items_line_discount_shape
    check (coalesce(line_discount_type = 'percentage', false) = (line_discount_percent is not null)
           and (line_discount_type is null or line_discount_type not in ('voucher','birthday','staff') or line_voucher_id is not null)
           and (line_discount_type is null or line_discount_type not in ('manual','percentage') or line_voucher_id is null));
  -- One per line. A line saved before 384 (no option) may still have both.
  alter table public.invoice_items drop constraint if exists invoice_items_line_discount_or_foc;
  alter table public.invoice_items add constraint invoice_items_line_discount_or_foc
    check (line_discount_type is null or coalesce(foc_quantity, 0) = 0);
  drop trigger if exists invoice_item_line_discount_reason on public.invoice_items;
  create trigger invoice_item_line_discount_reason before insert or update on public.invoice_items
    for each row execute function public.trg_invoice_item_line_discount_reason();

  -- ── 15. Installed as tested ──────────────────────────────────────────────
  v_after := v_after || jsonb_build_object(
    'public.report_discounts()', '7534e742656c0dd5cb818a6d468f6a7e',
    'public.invoice_line_discount_kind(text,uuid)', '9314ad644e0a027c4649b140bf714ff0',
    'public.invoice_birthday_check(uuid,date,uuid,uuid)', 'a93b421ecdbfbcdc71696edd55866893',
    'public.invoice_birthday_lines_check(uuid)', '259a17712fc4162e036911be958fbe59',
    'public.invoice_line_discount_for(jsonb,text,boolean,numeric,uuid,date,uuid)', '72f51bc774e6a033c41b814768c50fc3',
    'public.invoice_line_discount_take(uuid,uuid)', 'fcbe90339168f294ed86fc8189bb5c82',
    'public.invoice_line_discount_write(uuid,jsonb,jsonb)', 'd933fa2a9da99f4df8305e07cef38bd3',
    'public.invoice_line_discount_rebase(text,uuid,numeric,numeric,numeric)', 'c8aba1474be0a2690d246eba016999b8',
    'public.invoice_line_discount_only(uuid,jsonb)', 'aebdcb4bf20b2ac7ee4ccd1cc4ebbfc5',
    'public.trg_voucher_discount_category()', '327ab6341b467f149a82b684fdb46d07',
    'public.trg_invoice_item_line_discount_reason()', 'bbc6164e972434d025b2e9b08bb0da27');
  for r in select key as fn, value as want from jsonb_each_text(v_after)
  loop
    select md5(prosrc) into v from pg_proc where oid = to_regprocedure(r.fn);
    if v is distinct from r.want then
      raise exception '384: % was installed with md5 %, not the tested %', r.fn, v, r.want; end if;
  end loop;

  perform pg_notify('pgrst', 'reload schema');
end $mig$;
