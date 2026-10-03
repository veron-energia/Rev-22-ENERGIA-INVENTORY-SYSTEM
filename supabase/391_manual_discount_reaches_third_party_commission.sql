-- 391_manual_discount_reaches_third_party_commission.sql
--
-- WHAT WAS WRONG
--
-- Since 99 an invoice's manual discount may be given against every line,
-- third-party products included, and 99 noted that commission follows "the
-- discounted, externally-paid value per line". earn_invoice_commission never
-- caught up: it spread the whole invoice-level discount (manual, Discount
-- Voucher, Save Earth) over our own lines only, as it had when that discount
-- could not reach third-party goods, and paid third-party lines on their full
-- value. With the rates of 3 Oct 2026 (tier 1: 15% own, 4.5% third-party):
--
--   own S$100 + third S$100, manual S$50, paid S$150:
--       own on S$50 (S$7.50) + third on S$100 (S$4.50)          = S$12.00
--   third S$100 alone, manual S$30, paid S$70:
--       third on S$100                                           = S$4.50
--   own S$100 + third S$500, manual S$150, paid S$450:
--       own on S$0 + third on S$500                              = S$22.50
--
-- In the last two, commission was earned on more money than was paid.
--
-- THE RULE (the Owner's choice, 3 Oct 2026)
--
-- The manual discount comes off every line in proportion to its value,
-- third-party lines included. The rest of the invoice-level discount (the
-- Discount Voucher and Save Earth) still comes off our own lines only, as a
-- voucher is never given against third-party goods. The manual part is read
-- as the Discounts report reads it: the manual amount, no more than the
-- invoice-level discount. The three invoices above now earn on what was paid:
--
--       own on S$75 (S$11.25) + third on S$75 (S$3.38)           = S$14.63
--       third on S$70                                            = S$3.15
--       own on S$75 (S$11.25) + third on S$375 (S$16.88)         = S$28.13
--
-- An invoice with no manual discount, or with no third-party line, earns
-- exactly what it earned before, to the last digit: without a manual discount
-- there is no manual share, and without a third-party line the manual share
-- and the voucher share add up to the old single share.
--
-- WHAT THIS DOES
--
-- Patches earn_invoice_commission and invoice_affiliate_commission_preview
-- (357, derived from it, which part payments earn by) alike, with the same
-- three anchors in each: the declarations, the allocation bases, and each
-- line's share. Every anchor must match exactly once.
--
-- NOT CHANGED
--
--   * Commission already recorded. One production invoice was affected
--     (third-party S$2,786, manual discount S$6): S$0.36 too much across both
--     tiers, already paid out. The Owner chose to leave it. A later
--     correction or re-earning of that invoice earns it by this rule, and the
--     difference becomes a payout deduction.
--   * Line discounts (each line's own Discount, 385): already on the line.
--   * Package and bundle commission, staff commission (the invoice total).
--   * The preview's "357: derived" marker, so re-running 357 leaves it alone.
--     384's re-run refuses after this (earn_invoice_commission is no longer
--     its version): 384 is applied and is not meant to re-run.
--
-- SAFETY
--
-- Apart from the lock timeout, the migration is one statement (a DO block), so
-- it is atomic however it is run. Every guard and anchor is checked, and every
-- patched text built, before anything is installed. md5(pg_get_functiondef)
-- must be the production version read on 3 Oct 2026 (BEFORE), or already this
-- migration's version (AFTER), which is left alone so a re-run changes
-- nothing. Anything else refuses. After installing, each function must have
-- its AFTER md5. The patched texts are executed as CREATE OR REPLACE, which
-- keeps owner and grants. Functions only; no data changes.
--
-- BEFORE (production, 3 Oct 2026, md5 of pg_get_functiondef):
--   earn_invoice_commission(uuid)                 96199e3a2779c4392e936e9e3d0be66b
--   invoice_affiliate_commission_preview(uuid)    79e093f22f226f1a72ca059f1da1234b
-- AFTER (for later guards):
--   earn_invoice_commission(uuid)                 669ed0046d5783a63f82c1308222d45f
--   invoice_affiliate_commission_preview(uuid)    d66b3d40daff42712e17cd21e1d7ff88
--
-- Test: scripts/commissions/tests/manual-discount-third-party.sql.

set lock_timeout = '5s';

do $mig$
declare
  r record; d text; v text; n int; k int;
  v_fns text[] := '{}'; v_defs text[] := '{}'; i int;
  -- The same three edits in both functions: [anchor, replacement].
  v_edits text[][] := array[
    [E'  v_line_disc_sum numeric; v_invoice_level numeric; v_base_total numeric; v_line_net numeric;\n',
     E'  v_line_disc_sum numeric; v_invoice_level numeric; v_base_total numeric; v_line_net numeric;\n'
     || E'  v_manual_part numeric; v_rest numeric; v_all_base numeric;  -- 391\n'],
    [E'  -- Allocation base excludes 3rd-party product lines (they are discount-proof).\n',
     E'  -- 391: the manual discount reaches every line (99), so each line gives up\n'
     || E'  -- its share of it, third-party lines included. The rest (the Discount\n'
     || E'  -- Voucher, Save Earth) is still given on our own lines only. The manual\n'
     || E'  -- part is read as the Discounts report reads it.\n'
     || E'  v_manual_part := least(coalesce(v_inv.manual_discount,0), greatest(v_invoice_level,0));\n'
     || E'  v_rest := v_invoice_level - v_manual_part;\n'
     || E'  select coalesce(sum(ii.line_total - coalesce(ii.line_discount,0)),0) into v_all_base\n'
     || E'  from public.invoice_items ii where ii.invoice_id = p_invoice_id;\n'
     || E'\n'
     || E'  -- The rest''s base excludes 3rd-party product lines.\n'],
    [E'    if v_is_third then\n'
     || E'      v_line_after := v_line_net;   -- never reduced by invoice-level discounts\n'
     || E'    elsif v_base_total > 0 then\n'
     || E'      v_line_after := v_line_net - (v_invoice_level * (v_line_net / v_base_total));\n'
     || E'    else\n'
     || E'      v_line_after := v_line_net;\n'
     || E'    end if;\n',
     E'    -- 391: every line its share of the manual discount; our own lines\n'
     || E'    -- also their share of the rest.\n'
     || E'    v_line_after := v_line_net\n'
     || E'      - case when v_manual_part <> 0 and v_all_base > 0 then v_manual_part * (v_line_net / v_all_base) else 0 end\n'
     || E'      - case when not v_is_third and v_base_total > 0 then v_rest * (v_line_net / v_base_total) else 0 end;\n']];
begin
  -- ── Guards, anchors and patched texts: nothing is installed unless all pass ──
  for r in select * from (values
    ('earn_invoice_commission(uuid)',
     '96199e3a2779c4392e936e9e3d0be66b', '669ed0046d5783a63f82c1308222d45f'),
    ('invoice_affiliate_commission_preview(uuid)',
     '79e093f22f226f1a72ca059f1da1234b', 'd66b3d40daff42712e17cd21e1d7ff88')
  ) x(fn, before_md5, after_md5)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '391: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '391: public.% already takes the manual discount off every line; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '391: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    for k in 1 .. array_length(v_edits, 1) loop
      n := (length(d) - length(replace(d, v_edits[k][1], ''))) / length(v_edits[k][1]);
      if n <> 1 then
        raise exception '391: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
      d := replace(d, v_edits[k][1], v_edits[k][2]);
    end loop;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;

  -- ── Install ───────────────────────────────────────────────────────────────
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
  end loop;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  for r in select * from (values
    ('earn_invoice_commission(uuid)', '669ed0046d5783a63f82c1308222d45f'),
    ('invoice_affiliate_commission_preview(uuid)', 'd66b3d40daff42712e17cd21e1d7ff88')) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      raise exception '391: public.% was installed with md5 %, not the tested %', r.fn, v, r.after_md5; end if;
  end loop;
end $mig$;
