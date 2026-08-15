-- =====================================================================
-- ENERGIA — "That warehouse does not exist" WHEN RELEASING FROM A STORE
--
-- Migration 117 added a four-argument fulfil_special_doc() whose last
-- parameter is the ENUM public.location_type, plus a three-argument overload
-- for backward compatibility.
--
-- The cause was the OVERLOAD, not the enum. An enum parameter on its own is
-- fine: PostgREST passes arguments as unknown-typed literals, which coerce to
-- an enum happily — create_deferred_transfer_request(p_dest_type location_type)
-- has always worked this way.
--
-- The problem was having TWO candidates. With both a three-argument and a
-- four-argument form present, a call carrying an unresolvable fourth argument
-- fell through to the three-argument overload, which forwards 'warehouse'.
-- Releasing from a store then looked up a store id in the warehouses table:
--
--     That warehouse does not exist
--
-- The fix removes the overload entirely, leaving ONE function with a defaulted
-- final parameter. The parameter is taken as text and validated, so an unknown
-- value is rejected clearly instead of silently becoming a warehouse — and a
-- three-argument call still works, defaulting to warehouse.
--
-- Additive and idempotent. Run AFTER 119.
-- =====================================================================

set check_function_bodies = off;

-- Both previous versions go, leaving exactly one function so no call can ever
-- resolve to an unintended overload again.
drop function if exists public.fulfil_special_doc(text, uuid, uuid, public.location_type);
drop function if exists public.fulfil_special_doc(text, uuid, uuid);

create or replace function public.fulfil_special_doc(
  p_doc_kind text, p_doc_id uuid, p_warehouse_id uuid,
  p_location_type text default 'warehouse')
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_sp uuid; v_qty integer; v_no text; v_prod uuid; v_name text;
  v_avail record; v_loc_name text; v_type public.location_type;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can choose where stock is released from'; end if;
  if p_warehouse_id is null then raise exception 'Choose where the stock comes from'; end if;

  -- Validate rather than defaulting silently: a typo must not quietly become a
  -- warehouse and produce a confusing "does not exist" further down.
  if coalesce(nullif(trim(p_location_type), ''), 'warehouse') not in ('warehouse', 'store') then
    raise exception 'Unknown location type "%" — expected warehouse or store', p_location_type;
  end if;
  v_type := coalesce(nullif(trim(p_location_type), ''), 'warehouse')::public.location_type;

  if v_type = 'warehouse' then
    select name into v_loc_name from public.warehouses
     where id = p_warehouse_id and deleted_at is null;
    if v_loc_name is null then raise exception 'That warehouse does not exist'; end if;
  else
    select name into v_loc_name from public.stores
     where id = p_warehouse_id and deleted_at is null;
    if v_loc_name is null then raise exception 'That store does not exist'; end if;
  end if;

  if p_doc_kind = 'special_sale' then
    select special_product_id, quantity, sale_no into v_sp, v_qty, v_no
      from public.special_sales where id = p_doc_id
        and warehouse_id is null and source_store_id is null
        and status <> 'cancelled' for update;
    if v_sp is null then raise exception 'That sale is not awaiting a location'; end if;
  elsif p_doc_kind = 'rental' then
    select special_product_id, quantity, rental_no into v_sp, v_qty, v_no
      from public.rentals where id = p_doc_id
        and warehouse_id is null and source_store_id is null
        and status <> 'cancelled' for update;
    if v_sp is null then raise exception 'That rental is not awaiting a location'; end if;
  else
    raise exception 'Unknown document kind "%"', p_doc_kind;
  end if;

  select product_id into v_prod from public.special_products where id = v_sp;
  if v_prod is null then
    raise exception 'This special product is not linked to a warehouse product yet'; end if;
  v_name := public.special_product_name(v_sp);

  select * into v_avail from public.location_available_qty(v_type, p_warehouse_id, v_prod);

  if v_avail.available < v_qty then
    if v_avail.on_hand >= v_qty then
      raise exception
        'Only % of "%" free at % (% on hand, % already claimed by pending transfer requests). Approve or reject those first.',
        v_avail.available, v_name, v_loc_name, v_avail.on_hand, v_avail.reserved;
    end if;
    raise exception 'Not enough "%" at %: % needed, % on hand',
      v_name, v_loc_name, v_qty, v_avail.on_hand;
  end if;

  if v_type = 'warehouse' then
    update public.warehouse_inventory
       set current_qty = current_qty - v_qty, updated_at = now()
     where warehouse_id = p_warehouse_id and product_id = v_prod;
    insert into public.stock_movements
      (product_id, movement_type, from_warehouse_id, quantity, notes, created_by)
    values (v_prod, 'store_sale'::stock_movement_type, p_warehouse_id, v_qty,
      case when p_doc_kind = 'rental' then 'Rental released — ' else 'Special sale released — ' end || v_no,
      auth.uid());
  else
    update public.store_inventory
       set current_qty = current_qty - v_qty, updated_at = now()
     where store_id = p_warehouse_id and product_id = v_prod;
    insert into public.stock_movements
      (product_id, movement_type, from_store_id, quantity, notes, created_by)
    values (v_prod, 'store_sale'::stock_movement_type, p_warehouse_id, v_qty,
      case when p_doc_kind = 'rental' then 'Rental released — ' else 'Special sale released — ' end || v_no
        || ' (from store)',
      auth.uid());
  end if;

  if p_doc_kind = 'special_sale' then
    update public.special_sales
       set warehouse_id = case when v_type = 'warehouse' then p_warehouse_id end,
           source_store_id = case when v_type = 'store' then p_warehouse_id end,
           source_type = v_type,
           status = 'completed', fulfilled_at = now(), fulfilled_by = auth.uid()
     where id = p_doc_id;
  else
    update public.rentals
       set warehouse_id = case when v_type = 'warehouse' then p_warehouse_id end,
           source_store_id = case when v_type = 'store' then p_warehouse_id end,
           source_type = v_type,
           status = 'active', activated_at = now(),
           fulfilled_at = now(), fulfilled_by = auth.uid()
     where id = p_doc_id;
  end if;

  perform public.write_audit_ex(p_doc_kind, p_doc_id, 'special_doc_fulfilled', null,
    jsonb_build_object('location_type', v_type, 'location', p_warehouse_id,
      'location_name', v_loc_name, 'product', v_name, 'quantity', v_qty, 'doc_no', v_no),
    'special', null, null);

  return jsonb_build_object('success', true, 'doc_no', v_no,
    'location_type', v_type, 'location_name', v_loc_name,
    'quantity', v_qty, 'product', v_name);
end $function$;

notify pgrst, 'reload schema';
