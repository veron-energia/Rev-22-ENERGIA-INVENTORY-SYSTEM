-- =====================================================================
-- ENERGIA INVENTORY SYSTEM — RLS, HELPER FUNCTIONS, POLICIES
-- Run this SECOND, after 01_schema.sql.
-- =====================================================================

-- ========================= ENABLE ROW LEVEL SECURITY =========================
alter table public.profiles enable row level security;
alter table public.warehouses enable row level security;
alter table public.stores enable row level security;
alter table public.user_store_assignments enable row level security;
alter table public.products enable row level security;
alter table public.warehouse_inventory enable row level security;
alter table public.store_inventory enable row level security;
alter table public.customers enable row level security;
alter table public.affiliates enable row level security;
alter table public.store_product_prices enable row level security;
alter table public.payment_methods enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_items enable row level security;
alter table public.invoice_payments enable row level security;
alter table public.affiliate_commissions enable row level security;
alter table public.stock_movements enable row level security;
alter table public.approval_requests enable row level security;
alter table public.audit_logs enable row level security;

-- ========================= ROLE HELPER FUNCTIONS =========================
create or replace function public.current_user_role()
returns user_role language sql security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.is_owner_or_admin()
returns boolean language sql security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('owner', 'admin') and is_active = true
  )
$$;

create or replace function public.is_manager_or_above()
returns boolean language sql security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('owner', 'admin', 'manager') and is_active = true
  )
$$;

-- Owner/Manager only — for approvals, thresholds, store prices (NOT admin)
create or replace function public.is_owner_or_manager()
returns boolean language sql security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('owner', 'manager') and is_active = true
  )
$$;

-- Can manually add warehouse stock: owner, manager, inventory_manager
create or replace function public.can_manage_warehouse_stock()
returns boolean language sql security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
    and role in ('owner', 'manager', 'inventory_manager') and is_active = true
  )
$$;

create or replace function public.user_has_store_access(target_store_id uuid)
returns boolean language sql security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active = true and p.role in ('owner', 'admin')
  )
  or exists (
    select 1 from public.user_store_assignments usa
    join public.profiles p on p.id = usa.user_id
    where usa.user_id = auth.uid() and usa.store_id = target_store_id and p.is_active = true
  )
$$;

-- ========================= PROFILES POLICIES =========================
create policy "read own or admin reads all" on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_owner_or_admin());

create policy "owner manager manage profiles" on public.profiles
  for all to authenticated
  using (public.is_owner_or_manager())
  with check (public.is_owner_or_manager());

-- ========================= WAREHOUSES =========================
create policy "authenticated read warehouses" on public.warehouses
  for select to authenticated using (true);

create policy "owner manager manage warehouses" on public.warehouses
  for all to authenticated
  using (public.is_owner_or_manager())
  with check (public.is_owner_or_manager());

-- ========================= STORES =========================
create policy "read accessible stores" on public.stores
  for select to authenticated
  using (
    public.is_owner_or_admin()
    or exists (
      select 1 from public.user_store_assignments usa
      where usa.store_id = stores.id and usa.user_id = auth.uid()
    )
  );

create policy "owner manager manage stores" on public.stores
  for all to authenticated
  using (public.is_owner_or_manager())
  with check (public.is_owner_or_manager());

-- ========================= USER STORE ASSIGNMENTS =========================
create policy "read assignments" on public.user_store_assignments
  for select to authenticated
  using (user_id = auth.uid() or public.is_owner_or_admin());

create policy "owner manager manage assignments" on public.user_store_assignments
  for all to authenticated
  using (public.is_owner_or_manager())
  with check (public.is_owner_or_manager());

-- ========================= PRODUCTS =========================
create policy "authenticated read products" on public.products
  for select to authenticated using (true);

create policy "admin and above manage products" on public.products
  for all to authenticated
  using (public.is_manager_or_above())
  with check (public.is_manager_or_above());

-- ========================= PAYMENT METHODS =========================
create policy "authenticated read payment methods" on public.payment_methods
  for select to authenticated using (true);

create policy "owner manager manage payment methods" on public.payment_methods
  for all to authenticated
  using (public.is_owner_or_manager())
  with check (public.is_owner_or_manager());

-- NOTE: Inventory, invoices, transfers, customers, affiliates, and the rest
-- get their full policy sets in later phases as those modules are built.
-- Phase 1 ships profiles, warehouses, stores, assignments, products,
-- and payment methods — enough to validate auth + roles end to end.
