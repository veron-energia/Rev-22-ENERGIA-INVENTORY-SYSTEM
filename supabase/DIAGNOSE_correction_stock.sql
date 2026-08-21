-- =====================================================================
-- DIAGNOSTIC — WHICH LINE KINDS ACTUALLY CONSUME STOCK?
--
-- Read-only. Changes nothing. Run it in the Supabase SQL editor.
--
-- It answers the question directly: is this only promotions, or do other line
-- kinds fail the same way? Everything I can read in the code says the expansion
-- should work, so the answer is in your data, not in my reading of it.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. WHICH VERSION OF EACH FUNCTION IS ACTUALLY INSTALLED?
--
--    Migration ordering has bitten this project repeatedly. If the fix did not
--    take, this is the first thing to rule out.
-- ---------------------------------------------------------------------
select 'deduct_invoice_stock' as fn,
       case when prosrc like '%invoice_required_stock%'
            then 'FIXED — expands promotions'
            else 'OLD — walks product_id only  <-- migration 136 did not take' end as version
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and proname = 'deduct_invoice_stock'
union all
select 'restore_invoice_stock',
       case when prosrc like '%invoice_required_stock%'
            then 'FIXED — expands promotions'
            else 'OLD — walks product_id only  <-- migration 136 did not take' end
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and proname = 'restore_invoice_stock'
union all
select 'invoice_required_stock',
       case when prosrc like '%premium_bundle%' then 'handles promotion AND bundle'
            when prosrc like '%promotion%'      then 'handles promotion only'
            else 'DOES NOT EXPAND PROMOTIONS AT ALL  <-- this would explain it' end
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and proname = 'invoice_required_stock';

-- ---------------------------------------------------------------------
-- 2. FOR ONE OF YOUR CORRECTED INVOICES: what does the system think it needs?
--
--    Replace the invoice number below with the one you corrected.
-- ---------------------------------------------------------------------
\set inv_no 'INV-2026-0060'

with target as (
  select id, invoice_no, store_id from public.invoices
   where invoice_no = :'inv_no' limit 1
)
select
  ii.line_kind::text                         as line_kind,
  coalesce(p.name, v.name, pr.name, '—')     as line_shows,
  ii.quantity                                as line_qty,
  -- What the stock engine expands this invoice to. If a promotion line appears
  -- above but nothing appears here for its contents, that is the fault.
  (select count(*) from public.invoice_required_stock((select id from target))) as total_required_rows
  from public.invoice_items ii
  left join public.products p     on p.id = ii.product_id
  left join public.vouchers v     on v.id = ii.voucher_id
  left join public.promotions pr  on pr.id = ii.promotion_id
 where ii.invoice_id = (select id from target)
 order by ii.line_kind;

-- The expansion itself, item by item.
select r.kind,
       coalesce(p.name, v.name, '(unknown)') as item,
       r.quantity
  from public.invoice_required_stock(
        (select id from public.invoices where invoice_no = :'inv_no' limit 1)) r
  left join public.products p on p.id = r.item_id
  left join public.vouchers v on v.id = r.item_id;
-- EXPECTED: one row per product the promotion contains.
-- IF EMPTY for a promotion line -> the promotion's contents are not registered.

-- ---------------------------------------------------------------------
-- 3. IS THE PROMOTION'S CONTENT ACTUALLY RECORDED?
--
--    A promotion holds stock either as FIXED contents (promotion_items) or as
--    CHOICES the customer picks (invoice_promotion_selections). If a promotion
--    has neither, there is nothing for the engine to deduct — and that would
--    look exactly like the bug you are seeing, without being a code fault.
-- ---------------------------------------------------------------------
select pr.name                                   as promotion,
       count(pi.id) filter (where pi.item_type = 'product')  as fixed_products,
       count(pi.id) filter (where pi.item_type = 'voucher')  as fixed_vouchers,
       (select count(*) from public.promotion_choice_groups g
         where g.promotion_id = pr.id)           as choice_groups,
       case
         when count(pi.id) = 0
          and (select count(*) from public.promotion_choice_groups g
                where g.promotion_id = pr.id) = 0
         then '<-- HOLDS NO STOCK ITEMS: nothing to deduct, by design'
         else 'has contents' end                 as verdict
  from public.promotions pr
  left join public.promotion_items pi on pi.promotion_id = pr.id
 where pr.is_active
 group by pr.id, pr.name
 order by 5 desc, 1;

-- ---------------------------------------------------------------------
-- 4. DID THE CORRECTION WRITE THE SELECTIONS?
--
--    For a choice-based promotion the contents live here. If the correction
--    rewrote the line but not its selections, the engine has nothing to expand.
-- ---------------------------------------------------------------------
select ii.line_kind::text as line_kind,
       ii.id              as invoice_item_id,
       (select count(*) from public.invoice_promotion_selections s
         where s.invoice_item_id = ii.id) as selections_recorded
  from public.invoice_items ii
 where ii.invoice_id = (select id from public.invoices where invoice_no = :'inv_no' limit 1)
   and ii.line_kind::text in ('promotion', 'premium_bundle');
-- IF selections_recorded = 0 for a choice-based promotion -> that is the fault.

-- ---------------------------------------------------------------------
-- 5. THE ACTUAL MOVEMENTS WRITTEN FOR THAT CORRECTION.
--
--    Returns without matching deductions are the stock that leaked.
-- ---------------------------------------------------------------------
select sm.created_at,
       sm.movement_type::text,
       coalesce(p.name, '—') as product,
       sm.quantity,
       sm.notes
  from public.stock_movements sm
  left join public.products p on p.id = sm.product_id
 where sm.invoice_id = (select id from public.invoices where invoice_no = :'inv_no' limit 1)
 order by sm.created_at;
