-- =====================================================================
-- ENERGIA — STAFF MAY FLAG A PRODUCT AS IMPORTANT
--
-- products.is_important already exists, but every write policy on the table is
-- manager-level (can_manage_warehouse_stock / is_manager_or_above). Staff are
-- the people watching what actually moves in a store, so they are the right
-- people to mark it — but that must not turn into general product-edit rights.
--
-- A narrow SECURITY DEFINER function is the way: it can set THIS ONE FLAG and
-- nothing else. Prices, names, SKUs and everything else stay protected exactly
-- as they are.
--
-- Additive and idempotent. Run AFTER 109.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- Set or clear the flag.
--
-- This function already existed, restricted to an Owner or Manager. Staff are
-- the people who see what actually moves in a store, so the restriction is
-- lifted to any signed-in, active user. It remains narrow: THIS ONE FLAG and
-- nothing else — prices, names and SKUs stay protected as they are.
--
-- The return type is unchanged (void), so existing callers keep working.
-- ---------------------------------------------------------------------
create or replace function public.set_product_important(
  p_product_id uuid, p_important boolean)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare v_name text; v_role text;
begin
  select role into v_role from public.profiles
   where id = auth.uid() and coalesce(is_active, true);
  if v_role is null then raise exception 'No active profile for the current user'; end if;

  select name into v_name from public.products
   where id = p_product_id and deleted_at is null;
  if v_name is null then raise exception 'Product not found'; end if;

  update public.products
     set is_important = coalesce(p_important, false), updated_at = now()
   where id = p_product_id;

  perform public.write_audit_ex('products', p_product_id,
    case when p_important then 'product_marked_important' else 'product_unmarked_important' end,
    null, jsonb_build_object('product', v_name, 'by_role', v_role),
    'catalogue', null, null);
end $function$;

-- ---------------------------------------------------------------------
-- Store stock with the flag included, so the list can colour and filter by it
-- without a second round trip.
-- ---------------------------------------------------------------------
create or replace function public.store_stock_with_flags(p_store_id uuid)
returns table(product_id uuid, name text, sku text, is_important boolean,
              current_qty integer, low_stock_threshold integer)
language sql stable security definer set search_path to 'public' as $function$
  select p.id, p.name, p.sku, coalesce(p.is_important, false),
         coalesce(si.current_qty, 0)::integer,
         coalesce(si.low_stock_threshold, 0)::integer
    from public.products p
    left join public.store_inventory si
      on si.store_id = p_store_id and si.product_id = p.id
   where p.deleted_at is null and coalesce(p.is_active, true)
   order by coalesce(p.is_important, false) desc, p.name
$function$;

notify pgrst, 'reload schema';
