-- 387_voucher_redemption_records_the_voucher_alone.sql
--
-- WHAT WAS WRONG
--
-- When an invoice with an invoice-level Discount Voucher is paid in full
-- (invoice_record_payments_internal) or confirmed as FOC (confirm_foc_invoice),
-- a voucher_redemptions row records what the voucher gave, as
--   discount_total - sum(line_discount)
-- discount_total also holds the invoice's manual discount and Save Earth, so
-- those were recorded as the voucher's. S$200 of goods with a S$5 line
-- voucher, a S$20 manual discount and a 10% invoice voucher: the voucher gave
-- S$17.50 (10% of 200 - 20 - 5) and the row said S$37.50. On an FOC invoice
-- brought to nothing by a S$90 manual discount and a voucher for the S$10
-- left, it said S$100.
--
-- The Discounts report (366, 385) and the Reports page Vouchers tab already
-- read the voucher's amount from the invoice as
--   discount_total - manual_discount - Save Earth - sum(line_discount),
-- never below zero. The redemption row now records the same, so the customer's
-- redemption history (therapy_customer_detail) agrees with the reports.
--
-- In production on 3 Oct 2026 two invoices have an invoice-level voucher.
-- Neither has a manual discount or Save Earth, and both rows already equal
-- the report's amount, so no recorded row is wrong and none is changed.
--
-- WHAT THIS DOES
--
-- Patches that one expression in each of the two functions and nothing else:
-- one anchor per function, which must match exactly once. The line voucher
-- rows (each line's line_discount) are already right and are not touched.
--
-- NOT CHANGED
--
--   * Rows already written (see above), and the 30 missing / 3 duplicated
--     rows from August and September, which the Owner chose not to repair
--     (28 Sep 2026). The reports do not read this table for amounts.
--   * report_discounts and the Vouchers tab: they are the rule this follows.
--   * 385 lists confirm_foc_invoice among the functions it relies on
--     unchanged, so running 385 again after this refuses at its guard
--     (loudly, changing nothing). 385 is applied; it is not meant to re-run.
--
-- NUMBER: 386 is another migration of 3 Oct 2026 (the legacy create_invoice
-- overload dropped); this touches no function in common with it.
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
--   invoice_record_payments_internal(uuid,jsonb)  9faefe9b10e29f30b8f42140dea96530
--   confirm_foc_invoice(uuid,text)                d23a149f0c3eb22ed6fdfe88506300af
-- AFTER (for later guards):
--   invoice_record_payments_internal(uuid,jsonb)  5c2559f7cf4dbca5dec4fdd55d00ae34
--   confirm_foc_invoice(uuid,text)                0f1cb37a25666b0155553b127e05b208
--
-- Test: scripts/invoice-discounts/tests/voucher-redemption-amount.sql.

set lock_timeout = '5s';

do $mig$
declare
  r record; d text; v text; n int;
  v_fns text[] := '{}'; v_defs text[] := '{}'; i int;
begin
  -- ── Guards, anchors and patched texts: nothing is installed unless all pass ──
  for r in select * from (values
    ('invoice_record_payments_internal(uuid,jsonb)',
     '9faefe9b10e29f30b8f42140dea96530', '5c2559f7cf4dbca5dec4fdd55d00ae34',
     E'              v_inv.discount_total - coalesce((select sum(line_discount) from public.invoice_items where invoice_id = p_invoice_id),0),\n',
     E'              -- 387: the voucher alone, as the Discounts report reads it (366):\n'
     || E'              -- not the manual discount or Save Earth beside it.\n'
     || E'              greatest(round(coalesce(v_inv.discount_total,0) - coalesce(v_inv.manual_discount,0)\n'
     || E'                - case when v_inv.save_earth_applied then coalesce(v_inv.save_earth_amount,0) else 0 end\n'
     || E'                - coalesce((select sum(line_discount) from public.invoice_items where invoice_id = p_invoice_id),0), 2), 0),\n'),
    ('confirm_foc_invoice(uuid,text)',
     'd23a149f0c3eb22ed6fdfe88506300af', '0f1cb37a25666b0155553b127e05b208',
     E'            coalesce(v_inv.discount_total,0) - coalesce((select sum(line_discount) from public.invoice_items where invoice_id = p_invoice_id),0),\n',
     E'            -- 387: the voucher alone, as the Discounts report reads it (366):\n'
     || E'            -- not the manual discount or Save Earth beside it.\n'
     || E'            greatest(round(coalesce(v_inv.discount_total,0) - coalesce(v_inv.manual_discount,0)\n'
     || E'              - case when v_inv.save_earth_applied then coalesce(v_inv.save_earth_amount,0) else 0 end\n'
     || E'              - coalesce((select sum(line_discount) from public.invoice_items where invoice_id = p_invoice_id),0), 2), 0),\n')
  ) x(fn, before_md5, after_md5, anchor, replacement)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '387: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '387: public.% already records the voucher alone; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '387: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    n := (length(d) - length(replace(d, r.anchor, ''))) / length(r.anchor);
    if n <> 1 then
      raise exception '387: the redemption anchor of public.% was found % times, not once', r.fn, n; end if;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || replace(d, r.anchor, r.replacement);
  end loop;

  -- ── Install ───────────────────────────────────────────────────────────────
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
  end loop;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  for r in select * from (values
    ('invoice_record_payments_internal(uuid,jsonb)', '5c2559f7cf4dbca5dec4fdd55d00ae34'),
    ('confirm_foc_invoice(uuid,text)', '0f1cb37a25666b0155553b127e05b208')) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      raise exception '387: public.% was installed with md5 %, not the tested %', r.fn, v, r.after_md5; end if;
  end loop;
end $mig$;
