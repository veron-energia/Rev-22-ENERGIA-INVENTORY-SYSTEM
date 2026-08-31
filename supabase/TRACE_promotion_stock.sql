-- =====================================================================
-- TRACING PROMOTION STOCK BACK THROUGH HISTORY
--
-- Paste any ONE of these into the Supabase SQL editor and run it.
-- All read-only. Requires migration 149.
--
-- No psql commands, no temp tables — run any block on its own.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. EVERY PRODUCT THAT MOVED BECAUSE OF A PROMOTION — all time.
--    Newest first. This is the main trace-back.
-- ---------------------------------------------------------------------
select * from public.promotion_stock_history();


-- ---------------------------------------------------------------------
-- 2. THE SAME, FOR A DATE RANGE.
--    Edit the two dates.
-- ---------------------------------------------------------------------
-- select * from public.promotion_stock_history('2026-01-01', '2026-08-31');


-- ---------------------------------------------------------------------
-- 3. TOTALS — how much of each product each promotion has consumed.
--    The quickest way to see what a promotion has actually cost you in stock.
-- ---------------------------------------------------------------------
-- select * from public.promotion_stock_summary();


-- ---------------------------------------------------------------------
-- 4. THE GAPS — promotion sales with NO stock movement recorded.
--
--    THIS IS THE ONE THAT MATTERS FOR HISTORY. It compares what each settled
--    invoice REQUIRED against what was actually written. Anything listed here
--    will never appear in Stock History, however the notes are relabelled —
--    the record was never created.
--
--    A positive "missing" means stock left the shop with no record of it.
--    A negative one means more was recorded than the invoice called for.
-- ---------------------------------------------------------------------
-- select * from public.promotion_stock_gaps();


-- ---------------------------------------------------------------------
-- 5. GAPS SUMMARISED BY PRODUCT — how far out each product's count may be.
--    Run this before doing a physical count.
-- ---------------------------------------------------------------------
-- select product_name,
--        count(*)          as affected_invoices,
--        sum(missing)      as units_unrecorded
--   from public.promotion_stock_gaps()
--  group by product_name
--  order by 3 desc;


-- ---------------------------------------------------------------------
-- 6. ONE PROMOTION'S WHOLE HISTORY.
--    Edit the name.
-- ---------------------------------------------------------------------
-- select * from public.promotion_stock_history()
--  where promotion_name ilike '%Weekend Bundle%'
--  order by moved_at desc;


-- ---------------------------------------------------------------------
-- 7. ONE PRODUCT — which promotions have been consuming it.
--    Edit the name.
-- ---------------------------------------------------------------------
-- select promotion_name, count(*) as sales, sum(quantity) as units
--   from public.promotion_stock_history()
--  where product_name ilike '%Pillow%'
--  group by promotion_name
--  order by 3 desc;
