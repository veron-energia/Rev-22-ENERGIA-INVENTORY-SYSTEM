-- =====================================================================
-- ENERGIA — ADDING SPECIAL PRODUCT STOCK GOES TO WAREHOUSE INVENTORY
--
-- Migration 108 made a special product a warehouse product with one shared
-- stock pool, but special_stock_in() still wrote the retired
-- special_product_stock table. Stock added through the "Stock" button
-- therefore went into a table nothing reads any more: the figure stayed at
-- zero and the units could not be released.
--
-- It now writes warehouse_inventory, the same pool a transfer draws on, and
-- records a stock movement so the addition is visible in Stock History.
--
-- Additive and idempotent. Run AFTER 108.
-- =====================================================================

set check_function_bodies = off;

-- The original returns void; the signature is unchanged, so it is dropped
-- first rather than left to fail on the return type.
drop function if exists public.special_stock_in(uuid, uuid, integer, text);

create or replace function public.special_stock_in(
  p_special_product_id uuid, p_warehouse_id uuid, p_quantity integer,
  p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_prod uuid; v_name text; v_after integer;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can add stock'; end if;
  if coalesce(p_quantity,0) <= 0 then
    raise exception 'The quantity must be greater than zero'; end if;
  if p_warehouse_id is null then raise exception 'Choose a warehouse'; end if;

  select product_id into v_prod from public.special_products
   where id = p_special_product_id and deleted_at is null;
  if v_prod is null then
    raise exception 'This special product is not linked to a warehouse product. Re-add it by choosing the product it is.';
  end if;
  v_name := public.special_product_name(p_special_product_id);

  -- The shared pool: the same figure a transfer would draw on.
  insert into public.warehouse_inventory (warehouse_id, product_id, current_qty)
  values (p_warehouse_id, v_prod, p_quantity)
  on conflict (warehouse_id, product_id)
    do update set current_qty = public.warehouse_inventory.current_qty + excluded.current_qty,
                  updated_at = now()
  returning current_qty into v_after;

  insert into public.stock_movements
    (product_id, movement_type, to_warehouse_id, quantity, notes, created_by)
  values (v_prod, 'warehouse_stock_in'::stock_movement_type, p_warehouse_id, p_quantity,
    coalesce(p_note, 'Stock added — ' || v_name), auth.uid());

  perform public.write_audit_ex('special_products', p_special_product_id, 'special_stock_added', null,
    jsonb_build_object('warehouse', p_warehouse_id, 'quantity', p_quantity,
      'product', v_name, 'qty_after', v_after), 'inventory', p_note, null);

  return jsonb_build_object('success', true, 'quantity_added', p_quantity,
    'quantity_after', v_after, 'product', v_name);
end $function$;

notify pgrst, 'reload schema';
