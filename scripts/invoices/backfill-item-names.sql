-- Fill item_name_snapshot on invoice lines written before migration 354.
--
-- Names only. No money, stock, credit or commission row changes: the only other
-- trigger on invoice_items (capture_invoice_stock_components) returns at once on
-- an update that changes neither the item nor the quantity, and 354's own name
-- trigger keeps the value this statement sets. Proven by
-- scripts/invoices/tests/every-line-has-a-name.sql (T6).
--
-- Existing invoices already DISPLAY correctly without this, because
-- invoice_display_names falls back to the catalogue name. What this adds is a
-- frozen copy: once filled, renaming a product later cannot change what an old
-- invoice says. The one trade-off, which the owner should know: a line whose
-- catalogue item was ALREADY renamed before today is filled with today's name,
-- because no rename history exists to recover the old one.
--
-- Run in two steps.

-- ── STEP 1: DRY RUN — changes nothing ───────────────────────────────────────
-- Shows how many lines would be named, per kind, and confirms none would stay
-- blank. On production when 354 was written: 471 lines, 0 unresolved.
select it.line_kind::text                                         as line_kind,
       count(*)                                                   as lines_to_name,
       count(*) filter (where public.invoice_item_catalogue_name(it) is null) as would_stay_blank
  from public.invoice_items it
 where it.item_name_snapshot is null
 group by 1
 order by 2 desc;

-- ── STEP 2: APPLY — only after the dry run looks right ──────────────────────
-- Idempotent: it only touches lines still without a name, so running it twice
-- does nothing the second time. Uncomment to run.
--
-- update public.invoice_items it
--    set item_name_snapshot = public.invoice_item_catalogue_name(it)
--  where it.item_name_snapshot is null
--    and public.invoice_item_catalogue_name(it) is not null;
