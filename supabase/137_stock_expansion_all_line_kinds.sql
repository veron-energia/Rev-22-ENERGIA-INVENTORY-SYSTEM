-- =====================================================================
-- ENERGIA — WHICH LINE KINDS ACTUALLY DEDUCT STOCK, AND A WAY TO SEE IT
--
-- You asked whether the fault is promotions specifically or something broader.
-- It is broader, and there is a real gap I can prove:
--
--   invoice_required_stock() — the one function that decides what an invoice
--   consumes — handles exactly three line kinds:
--
--       line_kind = 'product'
--       line_kind = 'voucher'
--       line_kind = 'promotion'   (fixed items + the customer's choices)
--
--   The enum also contains 'premium_bundle', which carries a promotion_id and
--   whose contents live in promotion_items exactly like a promotion's. It is
--   NOT handled. A premium bundle therefore consumes no stock AT ALL — not on
--   correction, and not on an ordinary sale either.
--
-- 'therapy' and 'credit_package' correctly consume nothing. 'special_product'
-- and 'rental' correctly consume nothing here, because they are released from a
-- warehouse separately at fulfilment.
--
-- This migration:
--   1. adds premium_bundle to the expansion;
--   2. adds a diagnostic you can run on a specific invoice, so what the system
--      believes it requires can be read directly instead of inferred.
--
-- Additive and idempotent. Run AFTER 136.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Expansion covering every line kind that holds stock.
-- ---------------------------------------------------------------------
create or replace function public.invoice_required_stock(p_invoice_id uuid)
returns table (kind text, item_id uuid, quantity bigint)
language sql stable security definer set search_path = public as $function$
  with expanded as (
    -- A plain product line.
    select 'product'::text as kind, ii.product_id as item_id, ii.quantity::bigint as quantity
    from public.invoice_items ii
    where ii.invoice_id = p_invoice_id and ii.line_kind::text = 'product'
      and ii.product_id is not null
    union all
    -- A voucher line; only limited vouchers carry stock.
    select 'voucher', ii.voucher_id, ii.quantity::bigint
    from public.invoice_items ii
    join public.vouchers v on v.id = ii.voucher_id and v.qty_type = 'limited'
    where ii.invoice_id = p_invoice_id and ii.line_kind::text = 'voucher'
    union all
    -- Fixed contents of a promotion OR a premium bundle. Both carry a
    -- promotion_id and both keep their contents in promotion_items; only the
    -- former was ever expanded, so a bundle consumed nothing.
    select s.kind, s.item_id, (s.quantity)::bigint
    from public.invoice_items ii
    cross join lateral public.promotion_stock_items(ii.promotion_id, ii.quantity) s
    where ii.invoice_id = p_invoice_id
      and ii.line_kind::text in ('promotion', 'premium_bundle')
      and ii.promotion_id is not null
    union all
    -- Products the customer chose from a promotion's option groups.
    select 'product', ips.product_id, ips.quantity::bigint
    from public.invoice_promotion_selections ips
    join public.invoice_items ii on ii.id = ips.invoice_item_id
    where ii.invoice_id = p_invoice_id and ips.product_id is not null
    union all
    -- Vouchers chosen the same way.
    select 'voucher', ips.voucher_id, ips.quantity::bigint
    from public.invoice_promotion_selections ips
    join public.invoice_items ii on ii.id = ips.invoice_item_id
    join public.vouchers v on v.id = ips.voucher_id and v.qty_type = 'limited'
    where ii.invoice_id = p_invoice_id and ips.voucher_id is not null
  )
  select kind, item_id, sum(quantity) as quantity
  from expanded
  where item_id is not null
  group by kind, item_id
$function$;

-- ---------------------------------------------------------------------
-- 2. A diagnostic: what does the system think this invoice consumes?
--
--    Run it on the invoice you corrected. It lists every line, whether that
--    line was expanded into stock, and what came out. A line showing
--    "not expanded" is one whose goods are leaving without being counted.
-- ---------------------------------------------------------------------
create or replace function public.diagnose_invoice_stock(p_invoice_no text)
returns table (
  line_kind text,
  line_describes text,
  line_qty integer,
  expands_to text,
  expanded_qty bigint,
  verdict text)
language sql stable security definer set search_path = public as $function$
  with inv as (
    select id, store_id from public.invoices where invoice_no = p_invoice_no limit 1
  ),
  req as (
    select * from public.invoice_required_stock((select id from inv))
  ),
  lines as (
    select ii.id, ii.line_kind::text as lk, ii.quantity,
           coalesce(p.name, v.name, pr.name, '-') as describes,
           ii.promotion_id, ii.product_id, ii.voucher_id
      from public.invoice_items ii
      left join public.products p on p.id = ii.product_id
      left join public.vouchers v on v.id = ii.voucher_id
      left join public.promotions pr on pr.id = ii.promotion_id
     where ii.invoice_id = (select id from inv)
  )
  select
    l.lk,
    l.describes,
    l.quantity,
    coalesce((
      select string_agg(coalesce(pp.name, vv.name, r.item_id::text), ', ')
        from req r
        left join public.products pp on pp.id = r.item_id
        left join public.vouchers vv on vv.id = r.item_id
       where (l.lk = 'product'  and r.item_id = l.product_id)
          or (l.lk = 'voucher'  and r.item_id = l.voucher_id)
          or (l.lk in ('promotion','premium_bundle') and exists (
                select 1 from public.promotion_stock_items(l.promotion_id, l.quantity) s
                 where s.item_id = r.item_id))
    ), 'nothing') as expands_to,
    coalesce((
      select sum(r.quantity) from req r
       where (l.lk = 'product'  and r.item_id = l.product_id)
          or (l.lk = 'voucher'  and r.item_id = l.voucher_id)
          or (l.lk in ('promotion','premium_bundle') and exists (
                select 1 from public.promotion_stock_items(l.promotion_id, l.quantity) s
                 where s.item_id = r.item_id))
    ), 0) as expanded_qty,
    case
      when l.lk in ('therapy','credit_package') then 'no stock expected'
      when l.lk in ('special_product','rental') then 'released from a warehouse separately'
      when coalesce((select sum(r.quantity) from req r
                      where (l.lk = 'product' and r.item_id = l.product_id)
                         or (l.lk = 'voucher' and r.item_id = l.voucher_id)
                         or (l.lk in ('promotion','premium_bundle') and exists (
                               select 1 from public.promotion_stock_items(l.promotion_id, l.quantity) s
                                where s.item_id = r.item_id))), 0) > 0
        then 'OK — deducts stock'
      else 'NOT EXPANDED — goods leave without being counted'
    end as verdict
  from lines l
$function$;

-- ---------------------------------------------------------------------
-- 3. Confirm the expansion now covers bundles.
-- ---------------------------------------------------------------------
do $$
declare v_src text;
begin
  select prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'invoice_required_stock';
  if v_src is null or position('premium_bundle' in v_src) = 0 then
    raise exception 'invoice_required_stock still ignores premium bundles';
  end if;
  raise notice 'Confirmed: promotions AND premium bundles now expand into stock';
  raise notice 'To see what an invoice consumes, run:';
  raise notice '    select * from public.diagnose_invoice_stock(''INV-2026-0060'');';
end $$;

notify pgrst, 'reload schema';
