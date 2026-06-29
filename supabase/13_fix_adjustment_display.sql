-- =====================================================================
-- ENERGIA — FIX: adjustment requests exist but don't show in the app
-- Symptom: Adjustments + Approvals pages are empty, but approval_requests
-- has rows (request_type = 'inventory_adjustment', status 'pending').
--
-- TWO causes, both fixed here:
--   (A) Your rows use request_type = 'inventory_adjustment', but the app
--       (and the resolve function) expect 'adjustment'. Name mismatch.
--   (B) The read policy on approval_requests may be blocking the owner.
--
-- Run this whole file in the Supabase SQL Editor. Safe + idempotent.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helpers (ensure correct definitions).
-- ---------------------------------------------------------------------
create or replace function public.is_manager_or_above()
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from public.profiles
    where id = auth.uid() and role in ('owner','admin','manager') and is_active = true)
$$;

-- ---------------------------------------------------------------------
-- (A) Normalize request_type: 'inventory_adjustment' -> 'adjustment'
--     so existing rows match what the app and resolve function use.
-- ---------------------------------------------------------------------
update public.approval_requests
  set request_type = 'adjustment'
  where request_type = 'inventory_adjustment';

-- ---------------------------------------------------------------------
-- (B) Fix the READ policy on approval_requests.
--     Owner/Admin/Manager can read ALL; a requester can read their own.
-- ---------------------------------------------------------------------
alter table public.approval_requests enable row level security;

drop policy if exists "read approval requests" on public.approval_requests;
drop policy if exists "Users can read approval requests" on public.approval_requests;
drop policy if exists "create approval requests" on public.approval_requests;

create policy "read approval requests" on public.approval_requests
  for select to authenticated
  using (requested_by = auth.uid() or public.is_manager_or_above());

create policy "create approval requests" on public.approval_requests
  for insert to authenticated
  with check (requested_by = auth.uid());

-- Approvals update happens via SECURITY DEFINER resolve_* functions, but
-- allow owner/manager direct update too (harmless, keeps things flexible).
drop policy if exists "manager update approval requests" on public.approval_requests;
create policy "manager update approval requests" on public.approval_requests
  for update to authenticated
  using (public.is_manager_or_above()) with check (public.is_manager_or_above());

-- ---------------------------------------------------------------------
-- Make sure request_inventory_adjustment writes 'adjustment' (not the
-- long name) and into approval_requests. Re-assert the correct version.
-- ---------------------------------------------------------------------
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
-- DIAGNOSTIC — run these after, to confirm.
-- 1) Your role (should be owner/admin/manager):
--    select role, is_active from public.profiles where id = auth.uid();
-- 2) Adjustment rows now normalized:
--    select request_type, count(*) from public.approval_requests group by request_type;
-- =====================================================================
