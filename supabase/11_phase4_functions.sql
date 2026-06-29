-- =====================================================================
-- ENERGIA — PHASE 4: CONTROLS (refund/cancel, adjustments, audit, restore)
-- Run after Phase 3 SQL. Safe + idempotent.
-- =====================================================================

-- ========================= AUDIT LOG (read) =========================
alter table public.audit_logs enable row level security;
drop policy if exists "read audit logs" on public.audit_logs;
create policy "read audit logs" on public.audit_logs
  for select to authenticated using (public.is_manager_or_above());

-- =====================================================================
-- 1. REQUEST invoice cancellation or refund (Staff+ for their store)
--    p_type: 'invoice_cancel' | 'invoice_refund'
--    p_return_stock: whether approved action returns stock to the store
-- =====================================================================
create or replace function public.request_invoice_action(
  p_invoice_id uuid,
  p_type text,
  p_return_stock boolean,
  p_reason text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype;
  v_req_id uuid;
  v_new_status invoice_status;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access to this invoice'; end if;
  if p_type not in ('invoice_cancel','invoice_refund') then raise exception 'Invalid request type'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason is required'; end if;

  -- Only paid invoices can be refunded; unpaid can be cancelled.
  if p_type = 'invoice_refund' and v_inv.status <> 'paid' then
    raise exception 'Only paid invoices can be refunded';
  end if;
  if v_inv.status in ('cancelled','refunded') then
    raise exception 'Invoice is already %', v_inv.status;
  end if;

  v_new_status := case when p_type = 'invoice_cancel' then 'cancellation_requested'::invoice_status
                       else 'refund_requested'::invoice_status end;
  update public.invoices set status = v_new_status where id = p_invoice_id;

  insert into public.approval_requests
    (request_type, status, requested_by, related_record_id, reason, payload)
  values
    (p_type, 'pending', auth.uid(), p_invoice_id, p_reason,
     jsonb_build_object('invoice_id', p_invoice_id, 'return_stock', p_return_stock,
                        'invoice_no', v_inv.invoice_no))
  returning id into v_req_id;

  perform public.write_audit('invoices', p_invoice_id,
    case when p_type = 'invoice_cancel' then 'cancellation_requested' else 'refund_requested' end,
    null, jsonb_build_object('reason', p_reason, 'return_stock', p_return_stock));
  return v_req_id;
end;
$$;

-- =====================================================================
-- 2. APPROVE/REJECT invoice cancel/refund (Owner/Manager)
--    On approve: set final status, optionally return stock, reverse commission.
-- =====================================================================
create or replace function public.resolve_invoice_action(
  p_request_id uuid,
  p_approve boolean,
  p_note text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_req public.approval_requests%rowtype;
  v_inv public.invoices%rowtype;
  v_return_stock boolean;
  v_item record;
  v_is_refund boolean;
  v_final_status invoice_status;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can approve'; end if;

  select * into v_req from public.approval_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request is not pending'; end if;

  select * into v_inv from public.invoices where id = v_req.related_record_id for update;
  v_is_refund := (v_req.request_type = 'invoice_refund');
  v_return_stock := coalesce((v_req.payload->>'return_stock')::boolean, false);

  if not p_approve then
    -- Reject: revert invoice to its prior settled status.
    update public.invoices set status = case when v_is_refund then 'paid' else 'unpaid' end
      where id = v_inv.id;
    update public.approval_requests set status = 'rejected', approved_by = auth.uid(),
      approved_at = now(), response_note = p_note where id = p_request_id;
    perform public.write_audit('invoices', v_inv.id, 'invoice_action_rejected', null,
      jsonb_build_object('request_type', v_req.request_type));
    return jsonb_build_object('success', true, 'status', 'rejected');
  end if;

  -- Approve.
  v_final_status := case when v_is_refund then 'refunded'::invoice_status else 'cancelled'::invoice_status end;

  -- Return stock to the store if requested.
  if v_return_stock then
    for v_item in select product_id, quantity from public.invoice_items where invoice_id = v_inv.id
    loop
      insert into public.store_inventory (store_id, product_id, current_qty)
      values (v_inv.store_id, v_item.product_id, v_item.quantity)
      on conflict (store_id, product_id)
      do update set current_qty = public.store_inventory.current_qty + v_item.quantity, updated_at = now();

      insert into public.stock_movements
        (product_id, movement_type, to_store_id, invoice_id, quantity, notes, created_by)
      values
        (v_item.product_id,
         case when v_is_refund then 'invoice_refund_return' else 'invoice_cancel_return' end,
         v_inv.store_id, v_inv.id, v_item.quantity,
         'Stock returned — ' || v_inv.invoice_no, auth.uid());
    end loop;
  end if;

  -- Reverse affiliate commission if any.
  update public.affiliate_commissions
    set status = 'reversed', reversed_at = now()
    where invoice_id = v_inv.id and status = 'earned';

  update public.invoices set status = v_final_status where id = v_inv.id;
  update public.approval_requests set status = 'approved', approved_by = auth.uid(),
    approved_at = now(), response_note = p_note where id = p_request_id;

  perform public.write_audit('invoices', v_inv.id,
    case when v_is_refund then 'invoice_refunded' else 'invoice_cancelled' end, null,
    jsonb_build_object('return_stock', v_return_stock, 'invoice_no', v_inv.invoice_no));

  return jsonb_build_object('success', true, 'status', v_final_status, 'stock_returned', v_return_stock);
end;
$$;

-- =====================================================================
-- 3. REQUEST inventory adjustment (Staff+ for their store; inv mgr/owner/mgr for warehouse)
--    p_location_type: 'warehouse' | 'store'
--    p_new_qty: the corrected absolute quantity
-- =====================================================================
create or replace function public.request_inventory_adjustment(
  p_location_type location_type,
  p_location_id uuid,
  p_product_id uuid,
  p_new_qty integer,
  p_reason text,
  p_reference text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_current integer;
  v_req_id uuid;
begin
  if p_new_qty < 0 then raise exception 'Adjusted quantity cannot be negative'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason is required'; end if;

  if p_location_type = 'store' then
    if not public.user_has_store_access(p_location_id) then
      raise exception 'You can only adjust your assigned store';
    end if;
    select current_qty into v_current from public.store_inventory
      where store_id = p_location_id and product_id = p_product_id;
  else
    -- Warehouse adjustments limited to inventory-capable roles.
    if not public.can_manage_warehouse_stock() then
      raise exception 'Not authorized to adjust warehouse stock';
    end if;
    select current_qty into v_current from public.warehouse_inventory
      where warehouse_id = p_location_id and product_id = p_product_id;
  end if;
  v_current := coalesce(v_current, 0);

  insert into public.approval_requests
    (request_type, status, requested_by, related_record_id, reason, payload)
  values
    ('adjustment', 'pending', auth.uid(), p_product_id, p_reason,
     jsonb_build_object('location_type', p_location_type, 'location_id', p_location_id,
       'product_id', p_product_id, 'current_qty', v_current, 'new_qty', p_new_qty,
       'difference', p_new_qty - v_current, 'reference', p_reference))
  returning id into v_req_id;

  perform public.write_audit('inventory_adjustment', p_product_id, 'adjustment_requested', null,
    jsonb_build_object('from', v_current, 'to', p_new_qty));
  return v_req_id;
end;
$$;

-- =====================================================================
-- 4. APPROVE/REJECT inventory adjustment (Owner/Manager)
-- =====================================================================
create or replace function public.resolve_inventory_adjustment(
  p_request_id uuid,
  p_approve boolean,
  p_note text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_req public.approval_requests%rowtype;
  v_loc_type location_type;
  v_loc_id uuid;
  v_product_id uuid;
  v_new_qty integer;
  v_current integer;
  v_movement_type stock_movement_type := 'inventory_adjustment';
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can approve adjustments'; end if;

  select * into v_req from public.approval_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request is not pending'; end if;
  if v_req.request_type <> 'adjustment' then raise exception 'Not an adjustment request'; end if;

  if not p_approve then
    update public.approval_requests set status = 'rejected', approved_by = auth.uid(),
      approved_at = now(), response_note = p_note where id = p_request_id;
    return jsonb_build_object('success', true, 'status', 'rejected');
  end if;

  v_loc_type := (v_req.payload->>'location_type')::location_type;
  v_loc_id := (v_req.payload->>'location_id')::uuid;
  v_product_id := (v_req.payload->>'product_id')::uuid;
  v_new_qty := (v_req.payload->>'new_qty')::integer;

  if v_loc_type = 'store' then
    select current_qty into v_current from public.store_inventory
      where store_id = v_loc_id and product_id = v_product_id for update;
    v_current := coalesce(v_current, 0);
    insert into public.store_inventory (store_id, product_id, current_qty)
    values (v_loc_id, v_product_id, v_new_qty)
    on conflict (store_id, product_id) do update set current_qty = v_new_qty, updated_at = now();
    insert into public.stock_movements (product_id, movement_type, to_store_id, from_store_id, quantity, notes, created_by)
    values (v_product_id, v_movement_type,
            case when v_new_qty >= v_current then v_loc_id end,
            case when v_new_qty < v_current then v_loc_id end,
            abs(v_new_qty - v_current), 'Adjustment: ' || coalesce(v_req.reason,''), auth.uid());
  else
    select current_qty into v_current from public.warehouse_inventory
      where warehouse_id = v_loc_id and product_id = v_product_id for update;
    v_current := coalesce(v_current, 0);
    insert into public.warehouse_inventory (warehouse_id, product_id, current_qty)
    values (v_loc_id, v_product_id, v_new_qty)
    on conflict (warehouse_id, product_id) do update set current_qty = v_new_qty, updated_at = now();
    insert into public.stock_movements (product_id, movement_type, to_warehouse_id, from_warehouse_id, quantity, notes, created_by)
    values (v_product_id, v_movement_type,
            case when v_new_qty >= v_current then v_loc_id end,
            case when v_new_qty < v_current then v_loc_id end,
            abs(v_new_qty - v_current), 'Adjustment: ' || coalesce(v_req.reason,''), auth.uid());
  end if;

  update public.approval_requests set status = 'approved', approved_by = auth.uid(),
    approved_at = now(), response_note = p_note where id = p_request_id;
  perform public.write_audit('inventory_adjustment', v_product_id, 'adjustment_approved', null,
    jsonb_build_object('from', v_current, 'to', v_new_qty));
  return jsonb_build_object('success', true, 'status', 'approved', 'new_qty', v_new_qty);
end;
$$;

-- =====================================================================
-- 5. RESTORE a soft-deleted record (Owner/Manager)
-- =====================================================================
create or replace function public.restore_record(p_table text, p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can restore records'; end if;
  if p_table not in ('products','warehouses','stores','customers','affiliates','invoices','payment_methods') then
    raise exception 'Restore not supported for table %', p_table;
  end if;
  execute format('update public.%I set deleted_at = null where id = $1', p_table) using p_id;
  perform public.write_audit(p_table, p_id, 'restored', null, null);
end;
$$;
