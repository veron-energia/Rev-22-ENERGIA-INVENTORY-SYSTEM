-- =====================================================================
-- ENERGIA — PHASE 2: INVENTORY RLS POLICIES
-- Run AFTER Phase 1 SQL (01_schema, 02_rls_policies, 03_starter_data).
-- Covers: warehouse_inventory, store_inventory, stock_movements,
--         approval_requests (transfer subset).
-- =====================================================================

-- ========================= WAREHOUSE INVENTORY =========================
-- Anyone authenticated can read warehouse inventory (needed to build transfers).
create policy "authenticated read warehouse inventory" on public.warehouse_inventory
  for select to authenticated using (true);

-- Direct writes are blocked for everyone — all changes go through SECURITY DEFINER
-- functions (stock-in, transfer approval, adjustments). No insert/update/delete policy
-- means RLS denies direct table writes by default.

-- ========================= STORE INVENTORY =========================
-- Users can read store inventory only for stores they can access.
create policy "read accessible store inventory" on public.store_inventory
  for select to authenticated
  using (public.user_has_store_access(store_id));

-- Direct writes blocked — handled by functions.

-- ========================= STOCK MOVEMENTS =========================
-- Read: owner/admin/manager see everything; store-scoped users see movements
-- touching one of their accessible stores.
create policy "read stock movements" on public.stock_movements
  for select to authenticated
  using (
    public.is_manager_or_above()
    or (from_store_id is not null and public.user_has_store_access(from_store_id))
    or (to_store_id is not null and public.user_has_store_access(to_store_id))
  );

-- Inserts happen inside SECURITY DEFINER functions only.

-- ========================= APPROVAL REQUESTS =========================
-- Read: requester sees own; owner/manager see all; store-scoped users see
-- requests that reference a store they can access (via payload).
create policy "read approval requests" on public.approval_requests
  for select to authenticated
  using (
    requested_by = auth.uid()
    or public.is_owner_or_manager()
    or public.is_owner_or_admin()
  );

-- Insert: any authenticated user can create a request (the RPC validates store access).
create policy "create approval requests" on public.approval_requests
  for insert to authenticated
  with check (requested_by = auth.uid());

-- Update (cancel own pending request): requester may cancel; approval is via RPC.
create policy "requester cancels own pending" on public.approval_requests
  for update to authenticated
  using (requested_by = auth.uid() and status = 'pending')
  with check (requested_by = auth.uid());
