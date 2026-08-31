-- =====================================================================
-- ENERGIA — TRACING PROMOTION STOCK BACK THROUGH HISTORY
--
-- Migration 148 relabels movements that EXIST. This adds the reporting to go
-- back over past promotion sales properly:
--
--   1. promotion_stock_history()   — every product that moved because of a
--                                    promotion, with the promotion named;
--   2. promotion_stock_summary()   — totals per promotion and product;
--   3. promotion_stock_gaps()      — promotion sales where a movement was
--                                    NEVER written, so the stock changed with
--                                    no record, or did not change at all.
--
-- The third is the important one. A relabel can only fix rows that are there;
-- if a past sale wrote no movement, nothing in Stock History will ever show it,
-- and only a comparison against what the invoice REQUIRED can reveal that.
--
-- All read-only. Nothing is created, changed or deducted.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Every movement that came from a promotion or bundle.
--
--    A movement is attributed to a promotion when its product is NOT a direct
--    product line on that invoice but the invoice does carry a promotion —
--    the same test migration 148 uses for the note, so the two agree.
-- ---------------------------------------------------------------------
create or replace function public.promotion_stock_history(
  p_from date default null,
  p_to date default null,
  p_store_id uuid default null)
returns table(
  moved_at timestamptz,
  invoice_no text,
  store_name text,
  promotion_name text,
  product_name text,
  product_sku text,
  quantity integer,
  movement_type text,
  note text)
language sql stable security definer set search_path to 'public' as $function$
  select sm.created_at,
         i.invoice_no,
         s.name,
         (select string_agg(distinct pm.name, ', ')
            from public.invoice_items ii
            join public.promotions pm on pm.id = ii.promotion_id
           where ii.invoice_id = i.id
             and ii.line_kind::text in ('promotion', 'premium_bundle')),
         coalesce(p.name, '(unknown product)'),
         coalesce(p.sku, ''),
         sm.quantity,
         sm.movement_type::text,
         sm.notes
    from public.stock_movements sm
    join public.invoices i on i.id = sm.invoice_id
    left join public.stores s on s.id = i.store_id
    left join public.products p on p.id = sm.product_id
   where i.deleted_at is null
     and (p_store_id is null or i.store_id = p_store_id)
     and (p_from is null or (sm.created_at at time zone 'Asia/Singapore')::date >= p_from)
     and (p_to   is null or (sm.created_at at time zone 'Asia/Singapore')::date <= p_to)
     -- came from a promotion, not sold directly
     and not exists (select 1 from public.invoice_items ii
                      where ii.invoice_id = i.id
                        and ii.line_kind::text = 'product'
                        and ii.product_id = sm.product_id)
     and exists (select 1 from public.invoice_items ii
                  where ii.invoice_id = i.id
                    and ii.line_kind::text in ('promotion', 'premium_bundle'))
   order by sm.created_at desc
$function$;

-- ---------------------------------------------------------------------
-- 2. Totals: how much of each product each promotion has consumed.
-- ---------------------------------------------------------------------
create or replace function public.promotion_stock_summary(
  p_from date default null,
  p_to date default null,
  p_store_id uuid default null)
returns table(
  promotion_name text,
  product_name text,
  product_sku text,
  times_sold integer,
  units_moved bigint)
language sql stable security definer set search_path to 'public' as $function$
  select h.promotion_name,
         h.product_name,
         h.product_sku,
         count(distinct h.invoice_no)::integer,
         sum(h.quantity)::bigint
    from public.promotion_stock_history(p_from, p_to, p_store_id) h
   group by h.promotion_name, h.product_name, h.product_sku
   order by 5 desc, 1, 2
$function$;

-- ---------------------------------------------------------------------
-- 3. THE GAPS — promotion sales with no movement recorded.
--
--    Compares what each settled invoice REQUIRED against what was actually
--    written. A shortfall means the stock moved with no record, or never moved
--    at all. Either way it will never appear in Stock History, and no relabel
--    can bring it back.
-- ---------------------------------------------------------------------
create or replace function public.promotion_stock_gaps(
  p_from date default null,
  p_to date default null,
  p_store_id uuid default null)
returns table(
  invoice_no text,
  paid_at timestamptz,
  store_name text,
  promotion_name text,
  product_name text,
  required integer,
  recorded integer,
  missing integer)
language sql stable security definer set search_path to 'public' as $function$
  with settled as (
    select i.id, i.invoice_no, i.paid_at, i.store_id
      from public.invoices i
     where i.status in ('paid', 'completed_foc')
       and i.deleted_at is null
       and (p_store_id is null or i.store_id = p_store_id)
       and (p_from is null or (coalesce(i.paid_at, i.created_at) at time zone 'Asia/Singapore')::date >= p_from)
       and (p_to   is null or (coalesce(i.paid_at, i.created_at) at time zone 'Asia/Singapore')::date <= p_to)
       -- only invoices that actually carry a promotion
       and exists (select 1 from public.invoice_items ii
                    where ii.invoice_id = i.id
                      and ii.line_kind::text in ('promotion', 'premium_bundle'))
  ),
  required as (
    select st.id, st.invoice_no, st.paid_at, st.store_id,
           r.item_id as product_id,
           sum(r.quantity)::integer as need
      from settled st
      cross join lateral public.invoice_required_stock(st.id) r
     where r.kind = 'product'
     group by st.id, st.invoice_no, st.paid_at, st.store_id, r.item_id
  ),
  recorded as (
    select sm.invoice_id, sm.product_id,
           sum(case when sm.movement_type::text = 'store_sale' then sm.quantity else 0 end)::integer as got
      from public.stock_movements sm
     where sm.invoice_id in (select id from settled)
     group by sm.invoice_id, sm.product_id
  )
  select rq.invoice_no,
         rq.paid_at,
         s.name,
         (select string_agg(distinct pm.name, ', ')
            from public.invoice_items ii
            join public.promotions pm on pm.id = ii.promotion_id
           where ii.invoice_id = rq.id
             and ii.line_kind::text in ('promotion', 'premium_bundle')),
         coalesce(p.name, '(unknown product)'),
         rq.need,
         coalesce(rc.got, 0),
         rq.need - coalesce(rc.got, 0)
    from required rq
    left join recorded rc on rc.invoice_id = rq.id and rc.product_id = rq.product_id
    left join public.products p on p.id = rq.product_id
    left join public.stores s on s.id = rq.store_id
   where rq.need - coalesce(rc.got, 0) <> 0
   order by rq.paid_at desc, 5
$function$;

do $$
declare v_n integer;
begin
  select count(*) into v_n from public.promotion_stock_gaps();
  if v_n > 0 then
    raise notice 'NOTE: % promotion sale(s) have no matching stock movement — see promotion_stock_gaps()', v_n;
  else
    raise notice 'Confirmed: every promotion sale has its stock movements recorded';
  end if;
end $$;

notify pgrst, 'reload schema';
