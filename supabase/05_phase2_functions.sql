-- =====================================================================
-- ENERGIA — PHASE 2: STOCK FUNCTIONS (RPCs)
-- All stock mutations happen here, server-side and atomic, so balances
-- can never go negative and approvals are the only way stock moves.
-- Run AFTER 04_phase2_rls.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helper: write an audit log row
-- ---------------------------------------------------------------------
create or replace function public.write_audit(
  p_table text, p_record uuid, p_action text, p_old jsonb, p_new jsonb
) returns void language sql security definer set search_path = public as $$
  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by)
  values (p_table, p_record, p_action, p_old, p_new, auth.uid());
$$;

-- =====================================================================
-- 1. MANUAL WAREHOUSE STOCK-IN
--    Roles: owner, manager, inventory_manager
--    Requires a reason. Increases warehouse balance, logs movement + audit.
-- =====================================================================
create or replace function public.warehouse_stock_in(
  p_warehouse_id uuid,
  p_product_id uuid,
  p_quantity integer,
  p_reason text,
  p_note text default null,
  p_reference text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_new_qty integer;
  v_movement_id uuid;
begin
  if not public.can_manage_warehouse_stock() then
    raise exception 'Not authorized to add warehouse stock';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason for stock-in is required';
  end if;

  -- Upsert the warehouse balance.
  insert into public.warehouse_inventory (warehouse_id, product_id, current_qty)
  values (p_warehouse_id, p_product_id, p_quantity)
  on conflict (warehouse_id, product_id)
  do update set current_qty = public.warehouse_inventory.current_qty + excluded.current_qty,
                updated_at = now()
  returning current_qty into v_new_qty;

  -- Record the movement.
  insert into public.stock_movements
    (product_id, movement_type, to_warehouse_id, quantity, notes, created_by)
  values
    (p_product_id, 'warehouse_stock_in', p_warehouse_id, p_quantity,
     trim(coalesce(p_reason,'') || case when p_note is not null then ' — ' || p_note else '' end
       || case when p_reference is not null then ' (ref: ' || p_reference || ')' else '' end),
     auth.uid())
  returning id into v_movement_id;

  perform public.write_audit(
    'warehouse_inventory', p_product_id, 'stock_in',
    null,
    jsonb_build_object('warehouse_id', p_warehouse_id, 'product_id', p_product_id,
                       'quantity', p_quantity, 'new_qty', v_new_qty, 'reason', p_reason,
                       'reference', p_reference)
  );

  return v_movement_id;
end;
$$;

-- =====================================================================
-- 2. SET LOW STOCK THRESHOLD (warehouse or store)
--    Roles: owner, manager
-- =====================================================================
create or replace function public.set_low_stock_threshold(
  p_location_type location_type,
  p_location_id uuid,
  p_product_id uuid,
  p_threshold integer
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only Owner or Manager can set low stock thresholds';
  end if;
  if p_threshold < 0 then
    raise exception 'Threshold cannot be negative';
  end if;

  if p_location_type = 'warehouse' then
    insert into public.warehouse_inventory (warehouse_id, product_id, current_qty, low_stock_threshold)
    values (p_location_id, p_product_id, 0, p_threshold)
    on conflict (warehouse_id, product_id)
    do update set low_stock_threshold = p_threshold, updated_at = now();
  else
    insert into public.store_inventory (store_id, product_id, current_qty, low_stock_threshold)
    values (p_location_id, p_product_id, 0, p_threshold)
    on conflict (store_id, product_id)
    do update set low_stock_threshold = p_threshold, updated_at = now();
  end if;

  perform public.write_audit('low_stock_threshold', p_product_id, 'set_threshold', null,
    jsonb_build_object('location_type', p_location_type, 'location_id', p_location_id,
                       'product_id', p_product_id, 'threshold', p_threshold));
end;
$$;

-- =====================================================================
-- 3. CREATE STOCK TRANSFER REQUEST
--    Any authenticated user (staff limited to their store as source/dest).
--    Validates: source stock available, destination store has prices set.
--    Saves as a pending approval_request with a JSON payload of lines.
-- =====================================================================
create or replace function public.create_transfer_request(
  p_transfer_type text,        -- 'warehouse_to_warehouse' | 'warehouse_to_store' | 'store_to_store'
  p_source_type location_type,
  p_source_id uuid,
  p_dest_type location_type,
  p_dest_id uuid,
  p_lines jsonb,               -- [{ "product_id": "...", "quantity": 10 }, ...]
  p_note text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_line jsonb;
  v_product_id uuid;
  v_qty integer;
  v_available integer;
  v_has_price boolean;
  v_request_id uuid;
  v_role user_role;
begin
  v_role := public.current_user_role();

  -- Staff may only request transfers involving their assigned store.
  if v_role = 'staff' then
    if p_source_type = 'store' and not public.user_has_store_access(p_source_id) then
      raise exception 'Staff can only transfer from their assigned store';
    end if;
    if p_dest_type = 'store' and not public.user_has_store_access(p_dest_id) then
      raise exception 'Staff can only transfer to their assigned store';
    end if;
    -- Staff cannot move warehouse->warehouse.
    if p_source_type = 'warehouse' and p_dest_type = 'warehouse' then
      raise exception 'Staff cannot request warehouse-to-warehouse transfers';
    end if;
  end if;

  if p_source_type = p_dest_type and p_source_id = p_dest_id then
    raise exception 'Source and destination must be different';
  end if;
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'At least one product line is required';
  end if;

  -- Validate every line: stock availability + destination price (if dest is a store).
  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_product_id := (v_line->>'product_id')::uuid;
    v_qty := (v_line->>'quantity')::integer;

    if v_qty is null or v_qty <= 0 then
      raise exception 'Each line quantity must be greater than zero';
    end if;

    -- Source availability
    if p_source_type = 'warehouse' then
      select current_qty into v_available from public.warehouse_inventory
        where warehouse_id = p_source_id and product_id = v_product_id;
    else
      select current_qty into v_available from public.store_inventory
        where store_id = p_source_id and product_id = v_product_id;
    end if;
    v_available := coalesce(v_available, 0);
    if v_available < v_qty then
      raise exception 'Insufficient stock at source for product % (have %, need %)',
        v_product_id, v_available, v_qty;
    end if;

    -- Destination store must have a price for the product.
    if p_dest_type = 'store' then
      select exists (
        select 1 from public.store_product_prices
        where store_id = p_dest_id and product_id = v_product_id
          and is_active = true and deleted_at is null
      ) into v_has_price;
      if not v_has_price then
        raise exception 'Destination store has no price set for product %', v_product_id;
      end if;
    end if;
  end loop;

  -- Save the request.
  insert into public.approval_requests
    (request_type, status, requested_by, reason, payload)
  values
    ('transfer', 'pending', auth.uid(), p_note,
     jsonb_build_object(
       'transfer_type', p_transfer_type,
       'source_type', p_source_type, 'source_id', p_source_id,
       'dest_type', p_dest_type, 'dest_id', p_dest_id,
       'lines', p_lines, 'note', p_note))
  returning id into v_request_id;

  perform public.write_audit('approval_requests', v_request_id, 'transfer_requested', null,
    jsonb_build_object('transfer_type', p_transfer_type, 'lines', p_lines));

  return v_request_id;
end;
$$;

-- =====================================================================
-- 4. APPROVE / PARTIALLY APPROVE TRANSFER
--    Roles: owner, manager only.
--    p_approved_lines lets the approver change quantities (partial approval).
--    Moves stock atomically: source decreases, destination increases.
-- =====================================================================
create or replace function public.approve_transfer(
  p_request_id uuid,
  p_approved_lines jsonb,      -- [{ "product_id": "...", "quantity": 60 }, ...]
  p_note text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_req public.approval_requests%rowtype;
  v_payload jsonb;
  v_source_type location_type;
  v_source_id uuid;
  v_dest_type location_type;
  v_dest_id uuid;
  v_transfer_type text;
  v_movement_type stock_movement_type;
  v_line jsonb;
  v_product_id uuid;
  v_qty integer;
  v_requested_qty integer;
  v_available integer;
  v_is_partial boolean := false;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only Owner or Manager can approve transfers';
  end if;

  select * into v_req from public.approval_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request is not pending'; end if;
  if v_req.request_type <> 'transfer' then raise exception 'Not a transfer request'; end if;

  v_payload := v_req.payload;
  v_transfer_type := v_payload->>'transfer_type';
  v_source_type := (v_payload->>'source_type')::location_type;
  v_source_id := (v_payload->>'source_id')::uuid;
  v_dest_type := (v_payload->>'dest_type')::location_type;
  v_dest_id := (v_payload->>'dest_id')::uuid;

  v_movement_type := case v_transfer_type
    when 'warehouse_to_warehouse' then 'warehouse_to_warehouse'::stock_movement_type
    when 'warehouse_to_store' then 'warehouse_to_store'::stock_movement_type
    when 'store_to_store' then 'store_to_store'::stock_movement_type
    else 'warehouse_to_store'::stock_movement_type end;

  -- Move each approved line.
  for v_line in select * from jsonb_array_elements(p_approved_lines)
  loop
    v_product_id := (v_line->>'product_id')::uuid;
    v_qty := (v_line->>'quantity')::integer;

    if v_qty is null or v_qty < 0 then
      raise exception 'Approved quantity cannot be negative';
    end if;
    if v_qty = 0 then continue; end if;  -- skip zero-approved lines

    -- Compare against requested qty to detect partial approval.
    select (l->>'quantity')::integer into v_requested_qty
      from jsonb_array_elements(v_payload->'lines') l
      where (l->>'product_id')::uuid = v_product_id
      limit 1;
    if v_requested_qty is null then
      raise exception 'Approved product % was not in the original request', v_product_id;
    end if;
    if v_qty < v_requested_qty then v_is_partial := true; end if;
    if v_qty > v_requested_qty then
      raise exception 'Approved qty cannot exceed requested qty for product %', v_product_id;
    end if;

    -- Re-check source availability at approval time (stock may have changed).
    if v_source_type = 'warehouse' then
      select current_qty into v_available from public.warehouse_inventory
        where warehouse_id = v_source_id and product_id = v_product_id for update;
    else
      select current_qty into v_available from public.store_inventory
        where store_id = v_source_id and product_id = v_product_id for update;
    end if;
    v_available := coalesce(v_available, 0);
    if v_available < v_qty then
      raise exception 'Insufficient source stock for product % at approval (have %, approving %)',
        v_product_id, v_available, v_qty;
    end if;

    -- Decrease source.
    if v_source_type = 'warehouse' then
      update public.warehouse_inventory set current_qty = current_qty - v_qty, updated_at = now()
        where warehouse_id = v_source_id and product_id = v_product_id;
    else
      update public.store_inventory set current_qty = current_qty - v_qty, updated_at = now()
        where store_id = v_source_id and product_id = v_product_id;
    end if;

    -- Increase destination (upsert).
    if v_dest_type = 'warehouse' then
      insert into public.warehouse_inventory (warehouse_id, product_id, current_qty)
      values (v_dest_id, v_product_id, v_qty)
      on conflict (warehouse_id, product_id)
      do update set current_qty = public.warehouse_inventory.current_qty + v_qty, updated_at = now();
    else
      insert into public.store_inventory (store_id, product_id, current_qty)
      values (v_dest_id, v_product_id, v_qty)
      on conflict (store_id, product_id)
      do update set current_qty = public.store_inventory.current_qty + v_qty, updated_at = now();
    end if;

    -- Record the movement.
    insert into public.stock_movements
      (product_id, movement_type, from_warehouse_id, to_warehouse_id, from_store_id, to_store_id, quantity, notes, created_by)
    values (
      v_product_id, v_movement_type,
      case when v_source_type = 'warehouse' then v_source_id end,
      case when v_dest_type = 'warehouse' then v_dest_id end,
      case when v_source_type = 'store' then v_source_id end,
      case when v_dest_type = 'store' then v_dest_id end,
      v_qty,
      coalesce(p_note, 'Transfer approved'),
      auth.uid()
    );
  end loop;

  -- Update the request status.
  update public.approval_requests set
    status = case when v_is_partial then 'partially_approved'::approval_status else 'approved'::approval_status end,
    approved_by = auth.uid(),
    approved_at = now(),
    response_note = p_note,
    payload = v_payload || jsonb_build_object('approved_lines', p_approved_lines)
  where id = p_request_id;

  perform public.write_audit('approval_requests', p_request_id,
    case when v_is_partial then 'transfer_partially_approved' else 'transfer_approved' end,
    to_jsonb(v_req), jsonb_build_object('approved_lines', p_approved_lines));
end;
$$;

-- =====================================================================
-- 5. REJECT TRANSFER (requires a reason)
-- =====================================================================
create or replace function public.reject_transfer(
  p_request_id uuid,
  p_rejection_reason text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_req public.approval_requests%rowtype;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only Owner or Manager can reject transfers';
  end if;
  if p_rejection_reason is null or length(trim(p_rejection_reason)) = 0 then
    raise exception 'A rejection reason is required';
  end if;

  select * into v_req from public.approval_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request is not pending'; end if;

  update public.approval_requests set
    status = 'rejected', approved_by = auth.uid(), approved_at = now(),
    rejection_reason = p_rejection_reason
  where id = p_request_id;

  perform public.write_audit('approval_requests', p_request_id, 'transfer_rejected',
    to_jsonb(v_req), jsonb_build_object('rejection_reason', p_rejection_reason));
end;
$$;

-- =====================================================================
-- 6. CANCEL OWN PENDING TRANSFER REQUEST
-- =====================================================================
create or replace function public.cancel_transfer_request(p_request_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_req public.approval_requests%rowtype;
begin
  select * into v_req from public.approval_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if v_req.requested_by <> auth.uid() and not public.is_owner_or_manager() then
    raise exception 'You can only cancel your own request';
  end if;
  if v_req.status <> 'pending' then raise exception 'Only pending requests can be cancelled'; end if;

  update public.approval_requests set status = 'cancelled' where id = p_request_id;
  perform public.write_audit('approval_requests', p_request_id, 'transfer_cancelled', to_jsonb(v_req), null);
end;
$$;
