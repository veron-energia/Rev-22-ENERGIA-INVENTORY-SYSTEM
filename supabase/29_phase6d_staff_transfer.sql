-- =====================================================================
-- ENERGIA — PHASE 6D: Staff-simplified stock transfer flow
--
-- Staff create a transfer request with ONLY product + quantity + note.
-- The destination is auto-set to their assigned store; the SOURCE is left
-- empty and chosen by the Owner/Manager AT APPROVAL time.
--
--   Staff request  -> source = NULL, dest = assigned store, type =
--                     'warehouse_to_store', status = pending
--   Owner/Manager  -> picks the source warehouse, then approves / partially
--                     approves / rejects (existing rules otherwise).
--
-- Owner/Manager continue to use the full create flow (source + dest chosen
-- up front) unchanged.
--
-- Additive + idempotent. Run AFTER 27_phase6c_invoice_wiring.sql.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Allow a deferred source (Staff requests have none until approval).
-- ---------------------------------------------------------------------
alter table public.transfer_requests alter column source_type drop not null;
alter table public.transfer_requests alter column source_id drop not null;

-- ---------------------------------------------------------------------
-- 2. Staff request: product + quantity + note only. Everything else is
--    derived server-side (no source/destination input trusted from Staff).
-- ---------------------------------------------------------------------
create or replace function public.create_staff_transfer_request(
  p_lines jsonb, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role user_role; v_store_id uuid; v_line jsonb; v_product_id uuid; v_qty integer;
  v_has_price boolean; v_request_id uuid;
begin
  v_role := public.current_user_role();
  if v_role is null then raise exception 'No profile found for current user'; end if;
  if v_role <> 'staff' then raise exception 'This request type is for Staff only'; end if;

  v_store_id := public.my_assigned_store_id();
  if v_store_id is null then
    raise exception 'You are not assigned to a store, so you cannot request a transfer. Ask an Owner or Manager to assign you.';
  end if;

  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'At least one product line is required'; end if;

  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_product_id := (v_line->>'product_id')::uuid;
    v_qty := (v_line->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Each line quantity must be greater than zero'; end if;
    -- Destination store must have a price for the product (same rule as before).
    select exists (select 1 from public.store_product_prices
      where store_id = v_store_id and product_id = v_product_id and is_active = true and deleted_at is null) into v_has_price;
    if not v_has_price then
      raise exception 'Your store has no price set for "%". Ask an Owner/Manager to set it first.',
        (select name from public.products where id = v_product_id); end if;
  end loop;

  -- Source deferred (null) — Owner/Manager selects the warehouse at approval.
  insert into public.transfer_requests
    (transfer_type, source_type, source_id, dest_type, dest_id, status, note, requested_by)
  values ('warehouse_to_store', null, null, 'store', v_store_id, 'pending', p_note, auth.uid())
  returning id into v_request_id;

  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    insert into public.transfer_request_lines (transfer_request_id, product_id, quantity)
    values (v_request_id, (v_line->>'product_id')::uuid, (v_line->>'quantity')::integer);
  end loop;

  perform public.write_audit('transfer_requests', v_request_id, 'transfer_requested_by_staff', null,
    jsonb_build_object('dest_store', v_store_id, 'source', 'deferred'));
  return jsonb_build_object('success', true, 'id', v_request_id);
end; $$;

-- ---------------------------------------------------------------------
-- 3. approve_transfer: accepts an optional source warehouse. Required
--    when the request has no source yet (Staff request); ignored when the
--    request already has one (Owner/Manager full request).
-- ---------------------------------------------------------------------
create or replace function public.approve_transfer(
  p_request_id uuid, p_approved_lines jsonb, p_note text default null,
  p_source_warehouse_id uuid default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_req public.transfer_requests%rowtype; v_line jsonb; v_product_id uuid;
  v_qty integer; v_requested_qty integer; v_available integer; v_is_partial boolean := false;
  v_movement_type stock_movement_type;
  v_src_type location_type; v_src_id uuid;
  v_src_wh uuid; v_dst_wh uuid; v_src_st uuid; v_dst_st uuid;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can approve transfers'; end if;
  select * into v_req from public.transfer_requests where id = p_request_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request is not pending'; end if;

  -- Resolve the source: use the request's own, or the one chosen now.
  if v_req.source_id is not null then
    v_src_type := v_req.source_type; v_src_id := v_req.source_id;
  else
    if p_source_warehouse_id is null then
      raise exception 'This request has no source yet — choose a source warehouse to approve it.'; end if;
    v_src_type := 'warehouse'; v_src_id := p_source_warehouse_id;
    -- Persist the chosen source on the request for the record/print/audit.
    update public.transfer_requests set source_type = 'warehouse', source_id = p_source_warehouse_id
      where id = p_request_id;
    v_req.source_type := 'warehouse'; v_req.source_id := p_source_warehouse_id;
  end if;

  if v_src_type = v_req.dest_type and v_src_id = v_req.dest_id then
    raise exception 'Source and destination must be different'; end if;

  v_movement_type := case v_req.transfer_type
    when 'warehouse_to_warehouse' then 'warehouse_to_warehouse'::stock_movement_type
    when 'warehouse_to_store' then 'warehouse_to_store'::stock_movement_type
    when 'store_to_store' then 'store_to_store'::stock_movement_type
    else 'warehouse_to_store'::stock_movement_type end;

  v_src_wh := case when v_src_type = 'warehouse' then v_src_id end;
  v_dst_wh := case when v_req.dest_type = 'warehouse' then v_req.dest_id end;
  v_src_st := case when v_src_type = 'store' then v_src_id end;
  v_dst_st := case when v_req.dest_type = 'store' then v_req.dest_id end;

  for v_line in select * from jsonb_array_elements(p_approved_lines)
  loop
    v_product_id := (v_line->>'product_id')::uuid;
    v_qty := (v_line->>'quantity')::integer;
    if v_qty is null or v_qty < 0 then raise exception 'Approved quantity cannot be negative'; end if;
    select quantity into v_requested_qty from public.transfer_request_lines
      where transfer_request_id = p_request_id and product_id = v_product_id;
    if v_requested_qty is null then raise exception 'Product not in original request'; end if;
    if v_qty > v_requested_qty then raise exception 'Approved qty cannot exceed requested qty'; end if;
    if v_qty < v_requested_qty then v_is_partial := true; end if;

    update public.transfer_request_lines set approved_quantity = v_qty
      where transfer_request_id = p_request_id and product_id = v_product_id;
    if v_qty = 0 then continue; end if;

    if v_src_type = 'warehouse' then
      select current_qty into v_available from public.warehouse_inventory
        where warehouse_id = v_src_id and product_id = v_product_id for update;
    else
      select current_qty into v_available from public.store_inventory
        where store_id = v_src_id and product_id = v_product_id for update;
    end if;
    if coalesce(v_available,0) < v_qty then raise exception 'Insufficient source stock (have %, approving %)', coalesce(v_available,0), v_qty; end if;

    if v_src_type = 'warehouse' then
      update public.warehouse_inventory set current_qty = current_qty - v_qty, updated_at = now()
        where warehouse_id = v_src_id and product_id = v_product_id;
    else
      update public.store_inventory set current_qty = current_qty - v_qty, updated_at = now()
        where store_id = v_src_id and product_id = v_product_id;
    end if;

    if v_req.dest_type = 'warehouse' then
      insert into public.warehouse_inventory (warehouse_id, product_id, current_qty)
      values (v_req.dest_id, v_product_id, v_qty)
      on conflict (warehouse_id, product_id)
      do update set current_qty = public.warehouse_inventory.current_qty + v_qty, updated_at = now();
    else
      insert into public.store_inventory (store_id, product_id, current_qty)
      values (v_req.dest_id, v_product_id, v_qty)
      on conflict (store_id, product_id)
      do update set current_qty = public.store_inventory.current_qty + v_qty, updated_at = now();
    end if;

    insert into public.stock_movements
      (product_id, movement_type, from_warehouse_id, to_warehouse_id, from_store_id, to_store_id, quantity, notes, created_by)
    values (v_product_id, v_movement_type, v_src_wh, v_dst_wh, v_src_st, v_dst_st, v_qty, coalesce(p_note,'Transfer approved'), auth.uid());
  end loop;

  update public.transfer_requests set
    status = (case when v_is_partial then 'partially_approved' else 'approved' end)::approval_status,
    approved_by = auth.uid(), approved_at = now(), completed_at = now()
  where id = p_request_id;

  perform public.write_audit('transfer_requests', p_request_id,
    case when v_is_partial then 'transfer_partially_approved' else 'transfer_approved' end,
    null, jsonb_build_object('approved_lines', p_approved_lines, 'source_warehouse', v_src_id));
  return jsonb_build_object('success', true,
    'status', case when v_is_partial then 'partially_approved' else 'approved' end);
end; $$;

notify pgrst, 'reload schema';
