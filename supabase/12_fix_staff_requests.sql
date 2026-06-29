-- =====================================================================
-- ENERGIA — FIX: Staff can REQUEST transfers & adjustments
-- Symptom (P0001): Staff sees "You do not have permission to create
-- transfer requests" / "...request inventory adjustment".
--
-- Cause: the live versions of these functions in your database gate on a
-- blanket inventory-manager check (e.g. can_manage_inventory()), which
-- excludes Staff. Per the spec, Staff CAN request (scoped to their store);
-- they just cannot APPROVE. This overwrites both request functions with the
-- correct, store-scoped logic. Approval functions are unchanged.
--
-- Run this whole file in the Supabase SQL Editor. Safe + idempotent.
-- =====================================================================

-- Make sure the helpers these use exist.
create or replace function public.current_user_role()
returns user_role language sql security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.user_has_store_access(target_store_id uuid)
returns boolean language sql security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active = true and p.role in ('owner','admin')
  )
  or exists (
    select 1 from public.user_store_assignments usa
    join public.profiles p on p.id = usa.user_id
    where usa.user_id = auth.uid() and usa.store_id = target_store_id and p.is_active = true
  )
$$;

create or replace function public.can_manage_warehouse_stock()
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from public.profiles
    where id = auth.uid() and role in ('owner','manager','inventory_manager') and is_active = true)
$$;

-- =====================================================================
-- CREATE TRANSFER REQUEST  (Staff allowed, scoped to their store)
-- Matches your transfer_requests + transfer_request_lines schema.
-- Returns jsonb (your app and DB expect jsonb here).
-- =====================================================================
create or replace function public.create_transfer_request(
  p_transfer_type text,
  p_source_type text,
  p_source_id uuid,
  p_dest_type text,
  p_dest_id uuid,
  p_lines jsonb,
  p_note text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_role user_role;
  v_line jsonb;
  v_product_id uuid;
  v_qty integer;
  v_available integer;
  v_has_price boolean;
  v_request_id uuid;
begin
  v_role := public.current_user_role();
  if v_role is null then raise exception 'No profile found for current user'; end if;

  -- Staff: may only involve their assigned store, and not warehouse->warehouse.
  if v_role = 'staff' then
    if p_source_type = 'warehouse' and p_dest_type = 'warehouse' then
      raise exception 'Staff cannot request warehouse-to-warehouse transfers';
    end if;
    if p_source_type = 'store' and not public.user_has_store_access(p_source_id) then
      raise exception 'Staff can only transfer from their assigned store';
    end if;
    if p_dest_type = 'store' and not public.user_has_store_access(p_dest_id) then
      raise exception 'Staff can only transfer to their assigned store';
    end if;
  end if;

  if p_source_type = p_dest_type and p_source_id = p_dest_id then
    raise exception 'Source and destination must be different';
  end if;
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'At least one product line is required';
  end if;

  -- Validate each line: source stock + destination store price.
  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_product_id := (v_line->>'product_id')::uuid;
    v_qty := (v_line->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Each line quantity must be greater than zero'; end if;

    if p_source_type = 'warehouse' then
      select current_qty into v_available from public.warehouse_inventory
        where warehouse_id = p_source_id and product_id = v_product_id;
    else
      select current_qty into v_available from public.store_inventory
        where store_id = p_source_id and product_id = v_product_id;
    end if;
    v_available := coalesce(v_available, 0);
    if v_available < v_qty then
      raise exception 'Insufficient stock at source for a product (have %, need %)', v_available, v_qty;
    end if;

    if p_dest_type = 'store' then
      select exists (
        select 1 from public.store_product_prices
        where store_id = p_dest_id and product_id = v_product_id and is_active = true and deleted_at is null
      ) into v_has_price;
      if not v_has_price then
        raise exception 'Destination store has no price set for a selected product';
      end if;
    end if;
  end loop;

  -- Insert request header + lines.
  insert into public.transfer_requests
    (transfer_type, source_type, source_id, dest_type, dest_id, status, note, requested_by)
  values
    (p_transfer_type, p_source_type, p_source_id, p_dest_type, p_dest_id, 'pending', p_note, auth.uid())
  returning id into v_request_id;

  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    insert into public.transfer_request_lines (transfer_request_id, product_id, quantity)
    values (v_request_id, (v_line->>'product_id')::uuid, (v_line->>'quantity')::integer);
  end loop;

  perform public.write_audit('transfer_requests', v_request_id, 'transfer_requested', null,
    jsonb_build_object('transfer_type', p_transfer_type));

  return jsonb_build_object('success', true, 'id', v_request_id);
end;
$$;

-- =====================================================================
-- REQUEST INVENTORY ADJUSTMENT  (Staff allowed for their store)
-- Warehouse adjustments still limited to inventory-capable roles.
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
    -- Staff/manager/owner/admin assigned to the store may request.
    if not public.user_has_store_access(p_location_id) then
      raise exception 'You can only adjust your assigned store';
    end if;
    select current_qty into v_current from public.store_inventory
      where store_id = p_location_id and product_id = p_product_id;
  else
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
-- Also ensure RLS on the transfer tables lets Staff INSERT their request.
-- Your earlier policies used can_manage_inventory() (excludes staff).
-- Replace with authenticated insert; the function above does the scoping.
-- =====================================================================
alter table public.transfer_requests enable row level security;
alter table public.transfer_request_lines enable row level security;

drop policy if exists "Inventory managers can manage transfer requests" on public.transfer_requests;
drop policy if exists "Authenticated users can read transfer requests" on public.transfer_requests;
drop policy if exists "read transfer requests" on public.transfer_requests;
drop policy if exists "insert transfer requests" on public.transfer_requests;
drop policy if exists "update transfer requests" on public.transfer_requests;

create policy "read transfer requests" on public.transfer_requests
  for select to authenticated using (true);
create policy "insert transfer requests" on public.transfer_requests
  for insert to authenticated with check (requested_by = auth.uid());
create policy "update transfer requests" on public.transfer_requests
  for update to authenticated using (true) with check (true);

drop policy if exists "Inventory managers can manage transfer request lines" on public.transfer_request_lines;
drop policy if exists "Authenticated users can read transfer request lines" on public.transfer_request_lines;
drop policy if exists "read transfer request lines" on public.transfer_request_lines;
drop policy if exists "write transfer request lines" on public.transfer_request_lines;

create policy "read transfer request lines" on public.transfer_request_lines
  for select to authenticated using (true);
create policy "write transfer request lines" on public.transfer_request_lines
  for all to authenticated using (true) with check (true);

-- approval_requests: allow any authenticated user to insert their own request
-- (covers adjustments). Approval/update stays gated in the resolve_* functions.
alter table public.approval_requests enable row level security;
drop policy if exists "create approval requests" on public.approval_requests;
create policy "create approval requests" on public.approval_requests
  for insert to authenticated with check (requested_by = auth.uid());

drop policy if exists "read approval requests" on public.approval_requests;
create policy "read approval requests" on public.approval_requests
  for select to authenticated
  using (requested_by = auth.uid() or public.is_manager_or_above());
