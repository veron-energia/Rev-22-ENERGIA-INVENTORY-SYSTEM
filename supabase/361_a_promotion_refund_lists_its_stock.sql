-- 361_a_promotion_refund_lists_its_stock.sql
--
-- WHAT WAS WRONG (reported 26 Sep 2026, INV-2026-0314)
--
-- Refunding or cancelling a promotion line through Approvals (the guided
-- Refund / Cancel flow) failed with "Record the returned-and-sellable, damaged,
-- or not-returned quantities for this product refund", and the window offered
-- nowhere to record them.
--
-- invoice_action_plan lists, for each line, the stock that line took, by
-- matching each store_sale movement's product to the line's product. A
-- promotion line names no product of its own — its products are the
-- promotion's contents — so nothing matched: the plan listed no stock, the
-- Approvals list said "No stock return", and the window showed no quantity
-- fields. The refund engine (refund_invoice_recorded) does see the movements,
-- and rightly refuses a product or promotion refund until what happened to the
-- goods is recorded. So no promotion that took stock could be refunded through
-- Approvals. (A cancellation went through, because the cancellation put every
-- unit back as sellable without asking.)
--
-- WHAT THIS CHANGES
--
--   1. invoice_line_stock_products: the products a promotion line holds — the
--      promotion's items, the items of promotions nested in it, and the products
--      the customer chose for that line.
--   2. invoice_action_plan: a promotion line lists the stock movements of those
--      products, each once. Refunding the whole line proposes all of it back as
--      sellable; refunding part of it proposes that share. The approver can
--      change each figure to damaged or not returned, as for a product line.
--
-- A request raised before this, like the one on INV-2026-0314, needs nothing
-- redone: on approval the plan is worked out again, the change is shown as
-- "What this would do has changed", now with the quantity fields, and the
-- approver confirms again.
--
-- NOT CHANGED
--
--   * Product lines keep their own matching.
--   * The refund engine's own check, and what it records.
--   * Cancelling through Approvals now asks for the goods' condition for a
--     promotion too, as it already did for a product (so damaged units are not
--     put back as sellable).
--
-- SAFETY
--
-- invoice_action_plan is guarded by the md5 of its production version (26 Sep
-- 2026, after 359) and an anchor that must occur once; a function already
-- carrying "361:" is left alone.

set lock_timeout = '5s';

-- ── 1. the products a promotion line holds ──────────────────────────────────
create or replace function public.invoice_line_stock_products(p_invoice_item_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path to 'public'
as $function$
  -- 361: the promotion on the line, promotions nested in it (fixed items or the
  -- customer's choices), then every product any of them holds.
  with recursive promos(promotion_id) as (
      select b.promotion_id from (
        select ii.promotion_id from public.invoice_items ii
         where ii.id = p_invoice_item_id and ii.promotion_id is not null
        union
        select s.child_promotion_id from public.invoice_promotion_selections s
         where s.invoice_item_id = p_invoice_item_id and s.child_promotion_id is not null
      ) b
    union
      select pi.child_promotion_id
        from public.promotion_items pi join promos p on p.promotion_id = pi.promotion_id
       where pi.child_promotion_id is not null)
  select pi.product_id
    from public.promotion_items pi join promos p on p.promotion_id = pi.promotion_id
   where pi.product_id is not null
  union
  select s.product_id from public.invoice_promotion_selections s
   where s.invoice_item_id = p_invoice_item_id and s.product_id is not null
$function$;

revoke all on function public.invoice_line_stock_products(uuid) from public, anon, authenticated;
grant execute on function public.invoice_line_stock_products(uuid) to service_role;

-- ── 2. the plan lists a promotion line's stock ──────────────────────────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.invoice_action_plan(uuid,text,jsonb)'::regprocedure);
  if position('361:' in d) > 0 then raise notice '361: invoice_action_plan already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '398c0d970cd43d2f0cce8a5252146d31' then
    raise exception '361: invoice_action_plan is not the version this was tested against (md5 %)', v_md5; end if;

  a := $a$   for s in select * from jsonb_array_elements(coalesce(o->'stock','[]')) loop
    continue when coalesce(s->>'product_id','')<>coalesce(it.product_id::text,'');
    v_returnable:=coalesce((s->>'quantity')::int,0)-coalesce((s->>'resolved_quantity')::int,0);
    if v_returnable<=0 then continue; end if;
    v_returnable:=least(v_returnable,v_qty);$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '361: invoice_action_plan stock anchor found % times', n; end if;
  d := replace(d, a, $r$   for s in select * from jsonb_array_elements(coalesce(o->'stock','[]')) loop
    -- 361: a product line's stock is its own product. A promotion line names no
    -- product; its stock is the products inside the promotion, listed once.
    if it.line_kind::text = 'promotion' then
     continue when s->>'product_id' is null
       or not ((s->>'product_id')::uuid in (select public.invoice_line_stock_products(it.id)))
       or v_stock @> jsonb_build_array(jsonb_build_object('movement_id', s->>'movement_id'));
    else
     continue when coalesce(s->>'product_id','')<>coalesce(it.product_id::text,'');
    end if;
    v_returnable:=coalesce((s->>'quantity')::int,0)-coalesce((s->>'resolved_quantity')::int,0);
    if v_returnable<=0 then continue; end if;
    -- A product line returns at most the units refunded. A promotion returns its
    -- share of each product: all of it when the whole line is refunded.
    v_returnable:=case when it.line_kind::text = 'promotion'
                       then least(v_returnable, ceil(v_returnable * v_qty::numeric / v_full_qty)::int)
                       else least(v_returnable,v_qty) end;$r$);
  execute d;
end $mig$;

notify pgrst, 'reload schema';
