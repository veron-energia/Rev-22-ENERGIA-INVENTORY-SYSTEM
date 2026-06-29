-- =====================================================================
-- ENERGIA — PHASE 3: SALES RLS POLICIES
-- Customers, Affiliates, Store Price List, Invoices, Items, Payments,
-- Affiliate Commissions. Run after Phase 2 SQL.
-- Safe + idempotent (drop-if-exists then create).
-- =====================================================================

-- ========================= CUSTOMERS =========================
drop policy if exists "authenticated read customers" on public.customers;
create policy "authenticated read customers" on public.customers
  for select to authenticated using (deleted_at is null);

drop policy if exists "staff and above manage customers" on public.customers;
create policy "staff and above manage customers" on public.customers
  for all to authenticated
  using (true) with check (true);  -- any authenticated user can add/select customers for invoicing

-- ========================= AFFILIATES =========================
drop policy if exists "authenticated read affiliates" on public.affiliates;
create policy "authenticated read affiliates" on public.affiliates
  for select to authenticated using (deleted_at is null);

drop policy if exists "manager above manage affiliates" on public.affiliates;
create policy "manager above manage affiliates" on public.affiliates
  for all to authenticated
  using (public.is_manager_or_above()) with check (public.is_manager_or_above());

-- ========================= STORE PRICE LIST =========================
drop policy if exists "read accessible store prices" on public.store_product_prices;
create policy "read accessible store prices" on public.store_product_prices
  for select to authenticated using (true);  -- needed to build invoices + validate transfers

drop policy if exists "owner manager manage store prices" on public.store_product_prices;
create policy "owner manager manage store prices" on public.store_product_prices
  for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

-- ========================= INVOICES =========================
-- (Your DB already has invoice read/insert/update policies from earlier.
--  Re-assert them so behaviour is consistent.)
drop policy if exists "read accessible invoices" on public.invoices;
create policy "read accessible invoices" on public.invoices
  for select to authenticated using (public.user_has_store_access(store_id));

drop policy if exists "create invoices for accessible store" on public.invoices;
create policy "create invoices for accessible store" on public.invoices
  for insert to authenticated with check (public.user_has_store_access(store_id));

drop policy if exists "update accessible invoices" on public.invoices;
create policy "update accessible invoices" on public.invoices
  for update to authenticated
  using (public.user_has_store_access(store_id))
  with check (public.user_has_store_access(store_id));

-- ========================= INVOICE ITEMS =========================
drop policy if exists "read invoice items" on public.invoice_items;
create policy "read invoice items" on public.invoice_items
  for select to authenticated
  using (exists (select 1 from public.invoices i where i.id = invoice_id and public.user_has_store_access(i.store_id)));

drop policy if exists "write invoice items" on public.invoice_items;
create policy "write invoice items" on public.invoice_items
  for all to authenticated
  using (exists (select 1 from public.invoices i where i.id = invoice_id and public.user_has_store_access(i.store_id)))
  with check (exists (select 1 from public.invoices i where i.id = invoice_id and public.user_has_store_access(i.store_id)));

-- ========================= INVOICE PAYMENTS =========================
drop policy if exists "read invoice payments" on public.invoice_payments;
create policy "read invoice payments" on public.invoice_payments
  for select to authenticated
  using (exists (select 1 from public.invoices i where i.id = invoice_id and public.user_has_store_access(i.store_id)));
-- Inserts happen via the pay_invoice function (SECURITY DEFINER), so no insert policy needed.

-- ========================= AFFILIATE COMMISSIONS =========================
drop policy if exists "read affiliate commissions" on public.affiliate_commissions;
create policy "read affiliate commissions" on public.affiliate_commissions
  for select to authenticated using (public.is_manager_or_above());
-- Writes happen via pay_invoice / refund functions (SECURITY DEFINER).
