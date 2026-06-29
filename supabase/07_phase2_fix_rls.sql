-- =====================================================================
-- ENERGIA — PHASE 2 FIX #2: missing READ policies
-- Symptom: warehouse_inventory + stock_movements return [] even though
-- rows exist, because RLS is ENABLED on those tables but no SELECT policy
-- exists. With RLS on and no policy, reads return nothing.
-- This adds the missing read (and necessary write) policies.
-- Safe + idempotent: drops policy if exists, then recreates.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helper used by some policies (safe create-or-replace).
-- ---------------------------------------------------------------------
create or replace function public.is_manager_or_above()
returns boolean language sql security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('owner','admin','manager') and is_active = true
  )
$$;

-- =====================================================================
-- WAREHOUSE INVENTORY — add read policy (this is the main bug)
-- =====================================================================
drop policy if exists "authenticated read warehouse inventory" on public.warehouse_inventory;
create policy "authenticated read warehouse inventory" on public.warehouse_inventory
  for select to authenticated using (true);

-- Allow the threshold/stock-in functions' callers to upsert. The functions are
-- SECURITY DEFINER so they bypass RLS, but adding explicit write policies for
-- owner/manager keeps direct admin edits possible and avoids surprises.
drop policy if exists "managers write warehouse inventory" on public.warehouse_inventory;
create policy "managers write warehouse inventory" on public.warehouse_inventory
  for all to authenticated
  using (public.is_manager_or_above())
  with check (public.is_manager_or_above());

-- =====================================================================
-- STORE INVENTORY — ensure read policy exists (yours may already have one)
-- =====================================================================
drop policy if exists "read accessible store inventory" on public.store_inventory;
create policy "read accessible store inventory" on public.store_inventory
  for select to authenticated
  using (public.user_has_store_access(store_id));

drop policy if exists "managers write store inventory" on public.store_inventory;
create policy "managers write store inventory" on public.store_inventory
  for all to authenticated
  using (public.is_manager_or_above())
  with check (public.is_manager_or_above());

-- =====================================================================
-- STOCK MOVEMENTS — add read policy (this is why Stock History is empty)
-- =====================================================================
drop policy if exists "read stock movements" on public.stock_movements;
create policy "read stock movements" on public.stock_movements
  for select to authenticated
  using (
    public.is_manager_or_above()
    or (from_store_id is not null and public.user_has_store_access(from_store_id))
    or (to_store_id is not null and public.user_has_store_access(to_store_id))
  );

-- =====================================================================
-- QUICK DIAGNOSTIC (optional) — run these SELECTs after applying to confirm.
-- They should now return your actual rows:
--   select * from public.warehouse_inventory;
--   select * from public.stock_movements order by created_at desc;
-- =====================================================================
