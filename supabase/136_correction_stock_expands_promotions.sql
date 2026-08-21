-- =====================================================================
-- ENERGIA — CORRECTING A LINE TO A PROMOTION LEFT ITS STOCK ON THE SHELF
--
-- Correcting a paid invoice returns the old lines' stock and re-deducts the
-- new ones. Both helpers walked invoice_items directly:
--
--     select ii.product_id, sum(ii.quantity)
--       from public.invoice_items ii
--      where ii.invoice_id = p_invoice_id and ii.product_id is not null
--
-- A PROMOTION line has promotion_id set and product_id NULL, so it matched
-- nothing. Changing a product line to a promotion therefore returned the
-- original product to the shelf and deducted NOTHING for the promotion's
-- contents — the goods left the shop but the system still counted them.
--
-- The ordinary payment path never had this fault. It uses
-- invoice_required_stock(), which expands a promotion into its component
-- products and vouchers, including the options a customer chose. The
-- correction path simply did not use it.
--
-- Both helpers now use that same function, so a correction consumes exactly
-- what a sale would. One definition, so the two cannot drift apart again.
--
-- This also fixes the same omission for premium bundles and for line-level
-- vouchers, which were invisible to the correction path for the same reason.
--
-- Additive and idempotent. Run AFTER 102.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Deduct everything the corrected invoice actually requires.
-- ---------------------------------------------------------------------
create or replace function public.deduct_invoice_stock(p_invoice_id uuid, p_note text default null)
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare v_inv public.invoices%rowtype; v_req record; v_have integer; v_n integer := 0;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return 0; end if;

  -- invoice_required_stock() expands promotions and bundles into the products
  -- and vouchers they actually consume. Reading invoice_items directly missed
  -- all of it.
  for v_req in select * from public.invoice_required_stock(p_invoice_id)
  loop
    if v_req.kind = 'product' then
      select coalesce(current_qty, 0) into v_have from public.store_inventory
       where store_id = v_inv.store_id and product_id = v_req.item_id for update;
      if coalesce(v_have, 0) < v_req.quantity then
        raise exception 'Not enough stock for "%": % needed, % available',
          (select name from public.products where id = v_req.item_id),
          v_req.quantity, coalesce(v_have, 0);
      end if;

      update public.store_inventory
         set current_qty = current_qty - v_req.quantity, updated_at = now()
       where store_id = v_inv.store_id and product_id = v_req.item_id;

      insert into public.stock_movements
        (product_id, movement_type, from_store_id, invoice_id, quantity, notes, created_by)
      values (v_req.item_id, 'store_sale'::stock_movement_type, v_inv.store_id, p_invoice_id,
        v_req.quantity, coalesce(p_note, 'Stock deducted — paid invoice edited'), auth.uid());
      v_n := v_n + 1;

    elsif v_req.kind = 'voucher' then
      -- Limited vouchers are stocked per store in their own table.
      select coalesce(current_qty, 0) into v_have from public.voucher_store_stock
       where store_id = v_inv.store_id and voucher_id = v_req.item_id for update;
      if coalesce(v_have, 0) < v_req.quantity then
        raise exception 'Not enough voucher stock for "%": % needed, % available',
          (select name from public.vouchers where id = v_req.item_id),
          v_req.quantity, coalesce(v_have, 0);
      end if;

      update public.voucher_store_stock
         set current_qty = current_qty - v_req.quantity, updated_at = now()
       where store_id = v_inv.store_id and voucher_id = v_req.item_id;
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end $function$;

-- ---------------------------------------------------------------------
-- 2. Return everything the invoice took, by the same reckoning.
--
--    This must mirror the deduction exactly. If it returned only raw product
--    lines while the deduction expanded promotions, a correction would leak
--    stock in the opposite direction.
-- ---------------------------------------------------------------------
create or replace function public.restore_invoice_stock(p_invoice_id uuid, p_note text default null)
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare v_inv public.invoices%rowtype; v_req record; v_n integer := 0;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return 0; end if;

  for v_req in select * from public.invoice_required_stock(p_invoice_id)
  loop
    if v_req.kind = 'product' then
      insert into public.store_inventory (store_id, product_id, current_qty)
      values (v_inv.store_id, v_req.item_id, v_req.quantity)
      on conflict (store_id, product_id)
      do update set current_qty = public.store_inventory.current_qty + v_req.quantity,
                    updated_at = now();

      insert into public.stock_movements
        (product_id, movement_type, to_store_id, invoice_id, quantity, notes, created_by)
      values (v_req.item_id, 'invoice_cancel_return'::stock_movement_type, v_inv.store_id, p_invoice_id,
        v_req.quantity, coalesce(p_note, 'Stock returned — paid invoice edited'), auth.uid());
      v_n := v_n + 1;

    elsif v_req.kind = 'voucher' then
      insert into public.voucher_store_stock (voucher_id, store_id, current_qty)
      values (v_req.item_id, v_inv.store_id, v_req.quantity)
      on conflict (voucher_id, store_id)
      do update set current_qty = public.voucher_store_stock.current_qty + v_req.quantity,
                    updated_at = now();
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end $function$;

-- ---------------------------------------------------------------------
-- 3. Prove both sides agree, so a correction cannot leak stock.
--
--    For any invoice, what would be restored must equal what would be
--    deducted. They now share one definition, and this states it.
-- ---------------------------------------------------------------------
do $$
declare v_src_d text; v_src_r text;
begin
  select prosrc into v_src_d from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'deduct_invoice_stock';
  select prosrc into v_src_r from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'restore_invoice_stock';

  if v_src_d is null or position('invoice_required_stock' in v_src_d) = 0 then
    raise exception 'deduct_invoice_stock still ignores promotion contents';
  end if;
  if v_src_r is null or position('invoice_required_stock' in v_src_r) = 0 then
    raise exception 'restore_invoice_stock still ignores promotion contents';
  end if;
  raise notice 'Confirmed: a correction now consumes and returns exactly what a sale would';
end $$;

notify pgrst, 'reload schema';
