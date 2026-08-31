-- =====================================================================
-- WHY A PROMOTION'S PRODUCTS DO NOT COME OFF THE SHELF
--
-- ONE QUERY. Paste into the Supabase SQL editor. Read-only.
-- No psql commands, no temp tables, no functions created.
--
-- Put the invoice number on the TWO marked lines below, then run.
-- =====================================================================

with target as (
  -- >>> THE ONLY LINE YOU NEED TO EDIT <<<
  select 'INVOICE-NUMBER-HERE'::text as invoice_no
)
select 'A. WHICH FUNCTIONS ARE INSTALLED' as check_name,
       p.proname as detail,
       case when p.prosrc like '%invoice_required_stock%'
              or p.prosrc like '%promotion_stock_items%'
            then 'expands promotions'
            else 'DOES NOT EXPAND PROMOTIONS' end as value
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('pay_invoice', 'invoice_required_stock',
                     'deduct_invoice_stock', 'restore_invoice_stock')

union all

-- What the stock engine says this invoice needs. THIS IS THE KEY SECTION.
-- A promotion line should produce one row per product it contains.
-- NO ROWS for a promotion line means the promotion has no stock items
-- registered — and then nothing can be deducted, by design.
select 'B. STOCK THE INVOICE REQUIRES',
       coalesce(pr.name, v.name, '(unknown item)'),
       r.kind || ' x ' || r.quantity
  from public.invoices i
  cross join lateral public.invoice_required_stock(i.id) r
  left join public.products pr on pr.id = r.item_id
  left join public.vouchers v on v.id = r.item_id
 where i.invoice_no = (select invoice_no from target)

union all

-- The lines on the invoice, so you can see which are promotions.
select 'C. INVOICE LINES',
       ii.line_kind::text,
       coalesce(pr2.name, pm.name, vo.name, '(no name)') || '  x' || ii.quantity
  from public.invoices i
  join public.invoice_items ii on ii.invoice_id = i.id
  left join public.products pr2 on pr2.id = ii.product_id
  left join public.promotions pm on pm.id = ii.promotion_id
  left join public.vouchers vo on vo.id = ii.voucher_id
 where i.invoice_no = (select invoice_no from target)

union all

-- What each promotion on that invoice actually holds.
-- "HOLDS NOTHING" is the usual answer: a promotion with no product rows in
-- promotion_items and no choice groups has nothing to take off the shelf.
select 'D. WHAT THE PROMOTION CONTAINS',
       pm.name,
       'fixed products: ' ||
         (select count(*) from public.promotion_items pi
           where pi.promotion_id = pm.id and pi.item_type = 'product')
       || '   fixed vouchers: ' ||
         (select count(*) from public.promotion_items pi
           where pi.promotion_id = pm.id and pi.item_type = 'voucher')
       || '   choice groups: ' ||
         (select count(*) from public.promotion_choice_groups g
           where g.promotion_id = pm.id)
       || case when (select count(*) from public.promotion_items pi
                      where pi.promotion_id = pm.id) = 0
                and (select count(*) from public.promotion_choice_groups g
                      where g.promotion_id = pm.id) = 0
               then '   <-- HOLDS NOTHING: nothing to deduct'
               else '' end
  from public.promotions pm
 where pm.id in (select ii.promotion_id from public.invoices i
                   join public.invoice_items ii on ii.invoice_id = i.id
                  where i.invoice_no = (select invoice_no from target)
                    and ii.promotion_id is not null)

union all

-- The movements actually written for that invoice.
select 'E. STOCK MOVEMENTS WRITTEN',
       coalesce(p3.name, '(no product)'),
       sm.movement_type::text || ' x ' || sm.quantity
  from public.invoices i
  join public.stock_movements sm on sm.invoice_id = i.id
  left join public.products p3 on p3.id = sm.product_id
 where i.invoice_no = (select invoice_no from target)

order by 1, 2, 3;
