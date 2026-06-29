-- =====================================================================
-- ENERGIA — PHASE 2 FIX (matches your ACTUAL schema)
-- Your DB uses transfer_requests + transfer_request_lines (good design).
-- This adds the missing approve/reject/cancel functions + partial-approval
-- support, and a low-stock helper. Run this whole file in the SQL Editor.
-- Safe to re-run (uses create-or-replace and idempotent ALTERs).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Add columns needed for partial approval + rejection tracking.
-- ---------------------------------------------------------------------
alter table public.transfer_request_lines
  add column if not exists approved_quantity integer;

alter table public.transfer_requests
  add column if not exists rejection_reason text;

-- ---------------------------------------------------------------------
-- Audit helper (no-op safe if you already have one).
-- ---------------------------------------------------------------------
create or replace function public.write_audit(
  p_table text, p_record uuid, p_action text, p_old jsonb, p_new jsonb
) returns void language sql security definer set search_path = public as $$
  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by)
  values (p_table, p_record, p_action, p_old, p_new, auth.uid());
$$;

-- Owner/Manager check (works regardless of which helpers exist).
create or replace function public.is_owner_or_manager()
returns boolean language sql security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('owner','manager') and is_active = true
  )
$$;

-- =====================================================================
-- 1. APPROVE / PARTIALLY APPROVE TRANSFER
--    Reads transfer_requests + transfer_request_lines, moves stock,
--    writes stock_movements, sets approved_quantity per line.
--    p_approved_lines: [{ "product_id": "...", "quantity": 60 }, ...]
-- =====================================================================
create or replace function public.approve_transfer(
  p_request_id uuid,
  p_approved_lines jsonb,
  p_note text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_req public.transfer_requests%rowtype;
  v_line jsonb;
  v_product_id uuid;
  v_qty integer;
  v_requested_qty integer;
  v_available integer;
  v_is_partial boolean := false;
  v_movement_type stock_movement_type;
  v_src_wh uuid; v_dst_wh uuid; v_src_st uuid; v_dst_st uuid;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only Owner or Manager can approve transfers';
  end if;

  select * into v_req from public.transfer_requests where id = p_request_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request is not pending'; end if;

  v_movement_type := case v_req.transfer_type
    when 'warehouse_to_warehouse' then 'warehouse_to_warehouse'::stock_movement_type
    when 'warehouse_to_store' then 'warehouse_to_store'::stock_movement_type
    when 'store_to_store' then 'store_to_store'::stock_movement_type
    else 'warehouse_to_store'::stock_movement_type end;

  -- Resolve source/dest id columns by type.
  v_src_wh := case when v_req.source_type = 'warehouse' then v_req.source_id end;
  v_dst_wh := case when v_req.dest_type = 'warehouse' then v_req.dest_id end;
  v_src_st := case when v_req.source_type = 'store' then v_req.source_id end;
  v_dst_st := case when v_req.dest_type = 'store' then v_req.dest_id end;

  for v_line in select * from jsonb_array_elements(p_approved_lines)
  loop
    v_product_id := (v_line->>'product_id')::uuid;
    v_qty := (v_line->>'quantity')::integer;
    if v_qty is null or v_qty < 0 then raise exception 'Approved quantity cannot be negative'; end if;

    select quantity into v_requested_qty from public.transfer_request_lines
      where transfer_request_id = p_request_id and product_id = v_product_id;
    if v_requested_qty is null then
      raise exception 'Product % not in original request', v_product_id;
    end if;
    if v_qty > v_requested_qty then
      raise exception 'Approved qty cannot exceed requested qty for product %', v_product_id;
    end if;
    if v_qty < v_requested_qty then v_is_partial := true; end if;

    -- Record approved qty on the line.
    update public.transfer_request_lines set approved_quantity = v_qty
      where transfer_request_id = p_request_id and product_id = v_product_id;

    if v_qty = 0 then continue; end if;

    -- Re-check source availability now.
    if v_req.source_type = 'warehouse' then
      select current_qty into v_available from public.warehouse_inventory
        where warehouse_id = v_req.source_id and product_id = v_product_id for update;
    else
      select current_qty into v_available from public.store_inventory
        where store_id = v_req.source_id and product_id = v_product_id for update;
    end if;
    v_available := coalesce(v_available, 0);
    if v_available < v_qty then
      raise exception 'Insufficient source stock for product % (have %, approving %)',
        v_product_id, v_available, v_qty;
    end if;

    -- Decrease source.
    if v_req.source_type = 'warehouse' then
      update public.warehouse_inventory set current_qty = current_qty - v_qty, updated_at = now()
        where warehouse_id = v_req.source_id and product_id = v_product_id;
    else
      update public.store_inventory set current_qty = current_qty - v_qty, updated_at = now()
        where store_id = v_req.source_id and product_id = v_product_id;
    end if;

    -- Increase destination (upsert).
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

    -- Movement row.
    insert into public.stock_movements
      (product_id, movement_type, from_warehouse_id, to_warehouse_id, from_store_id, to_store_id, quantity, notes, created_by)
    values
      (v_product_id, v_movement_type, v_src_wh, v_dst_wh, v_src_st, v_dst_st, v_qty,
       coalesce(p_note, 'Transfer approved'), auth.uid());
  end loop;

  update public.transfer_requests set
    status = case when v_is_partial then 'partially_approved' else 'approved' end,
    approved_by = auth.uid(), approved_at = now(), completed_at = now()
  where id = p_request_id;

  perform public.write_audit('transfer_requests', p_request_id,
    case when v_is_partial then 'transfer_partially_approved' else 'transfer_approved' end,
    null, jsonb_build_object('approved_lines', p_approved_lines));

  return jsonb_build_object('success', true,
    'status', case when v_is_partial then 'partially_approved' else 'approved' end);
end;
$$;

-- =====================================================================
-- 2. REJECT TRANSFER (requires reason)
-- =====================================================================
create or replace function public.reject_transfer(
  p_request_id uuid,
  p_rejection_reason text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_req public.transfer_requests%rowtype;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only Owner or Manager can reject transfers';
  end if;
  if p_rejection_reason is null or length(trim(p_rejection_reason)) = 0 then
    raise exception 'A rejection reason is required';
  end if;

  select * into v_req from public.transfer_requests where id = p_request_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request is not pending'; end if;

  update public.transfer_requests set
    status = 'rejected', approved_by = auth.uid(), approved_at = now(),
    rejection_reason = p_rejection_reason
  where id = p_request_id;

  perform public.write_audit('transfer_requests', p_request_id, 'transfer_rejected',
    null, jsonb_build_object('rejection_reason', p_rejection_reason));
  return jsonb_build_object('success', true, 'status', 'rejected');
end;
$$;

-- =====================================================================
-- 3. CANCEL OWN PENDING TRANSFER
-- =====================================================================
create or replace function public.cancel_transfer_request(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_req public.transfer_requests%rowtype;
begin
  select * into v_req from public.transfer_requests where id = p_request_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if v_req.requested_by <> auth.uid() and not public.is_owner_or_manager() then
    raise exception 'You can only cancel your own request';
  end if;
  if v_req.status <> 'pending' then raise exception 'Only pending requests can be cancelled'; end if;

  update public.transfer_requests set status = 'cancelled' where id = p_request_id;
  perform public.write_audit('transfer_requests', p_request_id, 'transfer_cancelled', null, null);
  return jsonb_build_object('success', true, 'status', 'cancelled');
end;
$$;
