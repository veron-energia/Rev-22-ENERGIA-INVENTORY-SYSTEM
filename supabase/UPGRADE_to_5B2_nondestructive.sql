-- =====================================================================
-- ENERGIA — BRING DATABASE TO CURRENT (ADDITIVE, NON-DESTRUCTIVE)
-- =====================================================================
-- Run this whole file ONCE in the Supabase SQL Editor.
--
-- SAFE TO RUN ON AN EXISTING DATABASE:
--   * Tables use CREATE TABLE IF NOT EXISTS  → existing tables/data untouched
--   * Columns use ADD COLUMN IF NOT EXISTS   → existing columns/data untouched
--   * Functions use CREATE OR REPLACE        → logic updated, no data touched
--   * Policies are dropped + recreated by name → permissions only, no data
--   * Enums use ADD VALUE IF NOT EXISTS      → only adds missing values
--   * NO drop table / truncate / delete / data update anywhere
--
-- It upgrades a database to include everything through Phase 5B.2:
--   core schema, inventory, sales, controls, customer referrals,
--   two-tier commission, monthly payouts, and the referrer views.
--
-- check_function_bodies is turned OFF so that functions referencing the
-- newly-added 'paid' enum value create cleanly in the same run; the value
-- is committed at the end and validated when the functions first execute.
-- =====================================================================

set check_function_bodies = off;

-- Ensure the commission_status enum has 'paid' (older DBs lack it).
alter type public.commission_status add value if not exists 'paid';




-- =====================================================================
-- CORE SCHEMA + INVENTORY + SALES + CONTROLS (Phases 1-4)
--   (source: 00_complete_setup.sql)
-- =====================================================================

-- =====================================================================
-- ENERGIA INVENTORY & SALES — COMPLETE SETUP (FROM SCRATCH)
-- Run this ONCE on a brand-new Supabase project, in the SQL Editor.
-- It creates every type, table, helper, RLS policy, and business
-- function the app needs — consistent and in the correct order.
--
-- AFTER running this:
--   1. Supabase Dashboard → Authentication → Users → Add user
--      (create your Owner login with email + password).
--   2. Copy that user's UUID.
--   3. Run the STARTER DATA block at the very bottom (uncomment it and
--      paste your UUID + email), to create your Owner profile + seed data.
-- =====================================================================

-- ========================= EXTENSIONS =========================
create extension if not exists "pgcrypto";

-- ========================= 1. ENUM TYPES =========================
do $$ begin
  create type user_role as enum ('owner','admin','manager','inventory_manager','staff');
exception when duplicate_object then null; end $$;

do $$ begin
  create type product_type as enum ('own','third_party');
exception when duplicate_object then null; end $$;

do $$ begin
  create type location_type as enum ('warehouse','store');
exception when duplicate_object then null; end $$;

do $$ begin
  create type invoice_status as enum (
    'draft','unpaid','partially_paid','paid',
    'cancellation_requested','cancelled','refund_requested','refunded');
exception when duplicate_object then null; end $$;

do $$ begin
  create type approval_status as enum ('pending','approved','partially_approved','rejected','cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type stock_movement_type as enum (
    'warehouse_stock_in','warehouse_to_store','warehouse_to_warehouse',
    'store_to_store','store_sale','invoice_cancel_return',
    'invoice_refund_return','inventory_adjustment');
exception when duplicate_object then null; end $$;

do $$ begin
  create type commission_status as enum ('earned','paid','reversed','cancelled');
exception when duplicate_object then null; end $$;

-- ========================= 2. PROFILES =========================
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null unique,
  role user_role not null default 'staff',
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ========================= 3. LOCATIONS =========================
create table if not exists public.warehouses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  address text,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.stores (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  address text,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.user_store_assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(user_id, store_id)
);

-- ========================= 4. PRODUCTS =========================
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sku text not null unique,
  product_type product_type not null,
  category text,
  brand text,
  uom text not null default 'pcs',
  barcode text,
  description text,
  image_url text,
  supplier_name text,
  default_cost_price numeric(12,2) not null default 0,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ========================= 5. INVENTORY BALANCES =========================
create table if not exists public.warehouse_inventory (
  id uuid primary key default gen_random_uuid(),
  warehouse_id uuid not null references public.warehouses(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  current_qty integer not null default 0 check (current_qty >= 0),
  low_stock_threshold integer not null default 0,
  updated_at timestamptz not null default now(),
  unique(warehouse_id, product_id)
);

create table if not exists public.store_inventory (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  current_qty integer not null default 0 check (current_qty >= 0),
  low_stock_threshold integer not null default 0,
  updated_at timestamptz not null default now(),
  unique(store_id, product_id)
);

-- ========================= 6. CUSTOMERS =========================
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text not null unique,
  email text,
  address text,
  notes text,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

-- ========================= 7. AFFILIATES =========================
create table if not exists public.affiliates (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  email text,
  customer_id uuid references public.customers(id) on delete set null,
  commission_type text not null default 'percentage',
  commission_value numeric(12,2) not null default 0,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

-- ========================= 8. STORE PRICE LIST =========================
create table if not exists public.store_product_prices (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  selling_price numeric(12,2) not null check (selling_price >= 0),
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  unique(store_id, product_id)
);

-- ========================= 9. PAYMENT METHODS =========================
create table if not exists public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

-- ========================= 10. INVOICES =========================
create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_no text not null unique,
  store_id uuid not null references public.stores(id),
  customer_id uuid not null references public.customers(id),
  affiliate_id uuid references public.affiliates(id),
  created_by uuid not null references public.profiles(id),
  status invoice_status not null default 'unpaid',
  subtotal numeric(12,2) not null default 0,
  discount_total numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  paid_amount numeric(12,2) not null default 0,
  notes text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  locked_at timestamptz
);

create table if not exists public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  product_id uuid not null references public.products(id),
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  line_total numeric(12,2) not null check (line_total >= 0)
);

create table if not exists public.invoice_payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  payment_method_id uuid not null references public.payment_methods(id),
  amount numeric(12,2) not null check (amount > 0),
  payment_reference text,
  received_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  locked_at timestamptz not null default now()
);

-- ========================= 11. AFFILIATE COMMISSION =========================
create table if not exists public.affiliate_commissions (
  id uuid primary key default gen_random_uuid(),
  affiliate_id uuid not null references public.affiliates(id),
  invoice_id uuid not null references public.invoices(id),
  commission_amount numeric(12,2) not null default 0,
  status commission_status not null default 'earned',
  created_at timestamptz not null default now(),
  reversed_at timestamptz,
  unique(affiliate_id, invoice_id)
);

-- ========================= 12. STOCK MOVEMENT LOG =========================
create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id),
  movement_type stock_movement_type not null,
  from_warehouse_id uuid references public.warehouses(id),
  to_warehouse_id uuid references public.warehouses(id),
  from_store_id uuid references public.stores(id),
  to_store_id uuid references public.stores(id),
  invoice_id uuid references public.invoices(id),
  quantity integer not null check (quantity > 0),
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

-- ========================= 13. TRANSFER REQUESTS =========================
-- Dedicated tables (what the app uses) — header + line items.
create table if not exists public.transfer_requests (
  id uuid primary key default gen_random_uuid(),
  transfer_type text not null,                 -- warehouse_to_warehouse | warehouse_to_store | store_to_store
  source_type location_type not null,
  source_id uuid not null,
  dest_type location_type not null,
  dest_id uuid not null,
  status approval_status not null default 'pending',
  note text,
  rejection_reason text,
  requested_by uuid references public.profiles(id),
  approved_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  completed_at timestamptz
);

create table if not exists public.transfer_request_lines (
  id uuid primary key default gen_random_uuid(),
  transfer_request_id uuid not null references public.transfer_requests(id) on delete cascade,
  product_id uuid not null references public.products(id),
  quantity integer not null check (quantity > 0),
  approved_quantity integer,
  created_at timestamptz not null default now()
);

-- ========================= 14. APPROVAL REQUESTS =========================
-- Covers inventory adjustments + invoice cancel/refund (JSON payload).
create table if not exists public.approval_requests (
  id uuid primary key default gen_random_uuid(),
  request_type text not null,                  -- adjustment | invoice_cancel | invoice_refund
  status approval_status not null default 'pending',
  requested_by uuid not null references public.profiles(id),
  approved_by uuid references public.profiles(id),
  related_record_id uuid,
  payload jsonb,
  reason text,
  response_note text,
  rejection_reason text,
  created_at timestamptz not null default now(),
  approved_at timestamptz
);

-- ========================= 15. AUDIT LOG =========================
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  table_name text not null,
  record_id uuid,
  action text not null,
  old_data jsonb,
  new_data jsonb,
  changed_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

-- ========================= INDEXES =========================
create index if not exists idx_warehouse_inventory_product on public.warehouse_inventory(product_id);
create index if not exists idx_store_inventory_product on public.store_inventory(product_id);
create index if not exists idx_invoices_store on public.invoices(store_id);
create index if not exists idx_invoices_customer on public.invoices(customer_id);
create index if not exists idx_invoices_status on public.invoices(status);
create index if not exists idx_invoice_items_invoice on public.invoice_items(invoice_id);
create index if not exists idx_invoice_payments_invoice on public.invoice_payments(invoice_id);
create index if not exists idx_stock_movements_product on public.stock_movements(product_id);
create index if not exists idx_transfer_lines_req on public.transfer_request_lines(transfer_request_id);
create index if not exists idx_approval_requests_status on public.approval_requests(status);
create index if not exists idx_approval_requests_type on public.approval_requests(request_type);
create index if not exists idx_audit_logs_record on public.audit_logs(record_id);

-- =====================================================================
-- HELPER FUNCTIONS (role checks + audit)
-- =====================================================================
create or replace function public.write_audit(
  p_table text, p_record uuid, p_action text, p_old jsonb, p_new jsonb
) returns void language sql security definer set search_path = public as $$
  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by)
  values (p_table, p_record, p_action, p_old, p_new, auth.uid());
$$;

create or replace function public.current_user_role()
returns user_role language sql security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.is_owner_or_admin()
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from public.profiles
    where id = auth.uid() and role in ('owner','admin') and is_active = true)
$$;

create or replace function public.is_manager_or_above()
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from public.profiles
    where id = auth.uid() and role in ('owner','admin','manager') and is_active = true)
$$;

create or replace function public.is_owner_or_manager()
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from public.profiles
    where id = auth.uid() and role in ('owner','manager') and is_active = true)
$$;

create or replace function public.can_manage_warehouse_stock()
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from public.profiles
    where id = auth.uid() and role in ('owner','manager','inventory_manager') and is_active = true)
$$;

create or replace function public.user_has_store_access(target_store_id uuid)
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active = true and p.role in ('owner','admin'))
  or exists (select 1 from public.user_store_assignments usa
    join public.profiles p on p.id = usa.user_id
    where usa.user_id = auth.uid() and usa.store_id = target_store_id and p.is_active = true)
$$;

-- =====================================================================
-- ENABLE RLS ON EVERY TABLE
-- =====================================================================
alter table public.profiles               enable row level security;
alter table public.warehouses             enable row level security;
alter table public.stores                 enable row level security;
alter table public.user_store_assignments enable row level security;
alter table public.products               enable row level security;
alter table public.warehouse_inventory    enable row level security;
alter table public.store_inventory        enable row level security;
alter table public.customers              enable row level security;
alter table public.affiliates             enable row level security;
alter table public.store_product_prices   enable row level security;
alter table public.payment_methods        enable row level security;
alter table public.invoices               enable row level security;
alter table public.invoice_items          enable row level security;
alter table public.invoice_payments       enable row level security;
alter table public.affiliate_commissions  enable row level security;
alter table public.stock_movements        enable row level security;
alter table public.transfer_requests      enable row level security;
alter table public.transfer_request_lines enable row level security;
alter table public.approval_requests      enable row level security;
alter table public.audit_logs             enable row level security;

-- =====================================================================
-- RLS POLICIES
-- =====================================================================

-- PROFILES: everyone authenticated can read; user can update self;
-- owner/admin manage all.
drop policy if exists "read profiles" on public.profiles;
create policy "read profiles" on public.profiles for select to authenticated using (true);
drop policy if exists "insert profiles" on public.profiles;
create policy "insert profiles" on public.profiles for insert to authenticated with check (true);
drop policy if exists "update profiles" on public.profiles;
create policy "update profiles" on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_owner_or_admin())
  with check (id = auth.uid() or public.is_owner_or_admin());

-- WAREHOUSES / STORES: read all; manage owner/manager.
drop policy if exists "read warehouses" on public.warehouses;
create policy "read warehouses" on public.warehouses for select to authenticated using (true);
drop policy if exists "manage warehouses" on public.warehouses;
create policy "manage warehouses" on public.warehouses for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

drop policy if exists "read stores" on public.stores;
create policy "read stores" on public.stores for select to authenticated using (true);
drop policy if exists "manage stores" on public.stores;
create policy "manage stores" on public.stores for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

-- USER STORE ASSIGNMENTS: read all; manage owner/admin/manager.
drop policy if exists "read assignments" on public.user_store_assignments;
create policy "read assignments" on public.user_store_assignments for select to authenticated using (true);
drop policy if exists "manage assignments" on public.user_store_assignments;
create policy "manage assignments" on public.user_store_assignments for all to authenticated
  using (public.is_manager_or_above()) with check (public.is_manager_or_above());

-- PRODUCTS: read all; manage owner/manager/inventory_manager.
drop policy if exists "read products" on public.products;
create policy "read products" on public.products for select to authenticated using (true);
drop policy if exists "manage products" on public.products;
create policy "manage products" on public.products for all to authenticated
  using (public.can_manage_warehouse_stock()) with check (public.can_manage_warehouse_stock());

-- WAREHOUSE INVENTORY: read all; writes happen via functions, but allow
-- owner/manager direct writes too.
drop policy if exists "read warehouse inventory" on public.warehouse_inventory;
create policy "read warehouse inventory" on public.warehouse_inventory for select to authenticated using (true);
drop policy if exists "write warehouse inventory" on public.warehouse_inventory;
create policy "write warehouse inventory" on public.warehouse_inventory for all to authenticated
  using (public.can_manage_warehouse_stock()) with check (public.can_manage_warehouse_stock());

-- STORE INVENTORY: read by store access; writes via functions / managers.
drop policy if exists "read store inventory" on public.store_inventory;
create policy "read store inventory" on public.store_inventory for select to authenticated
  using (public.user_has_store_access(store_id));
drop policy if exists "write store inventory" on public.store_inventory;
create policy "write store inventory" on public.store_inventory for all to authenticated
  using (public.is_manager_or_above()) with check (public.is_manager_or_above());

-- CUSTOMERS: any authenticated read/insert/update.
drop policy if exists "read customers" on public.customers;
create policy "read customers" on public.customers for select to authenticated using (deleted_at is null);
drop policy if exists "insert customers" on public.customers;
create policy "insert customers" on public.customers for insert to authenticated with check (true);
drop policy if exists "update customers" on public.customers;
create policy "update customers" on public.customers for update to authenticated using (true) with check (true);

-- AFFILIATES: read all; manage manager+.
drop policy if exists "read affiliates" on public.affiliates;
create policy "read affiliates" on public.affiliates for select to authenticated using (deleted_at is null);
drop policy if exists "manage affiliates" on public.affiliates;
create policy "manage affiliates" on public.affiliates for all to authenticated
  using (public.is_manager_or_above()) with check (public.is_manager_or_above());

-- STORE PRICES: read all; manage owner/manager.
drop policy if exists "read store prices" on public.store_product_prices;
create policy "read store prices" on public.store_product_prices for select to authenticated using (true);
drop policy if exists "manage store prices" on public.store_product_prices;
create policy "manage store prices" on public.store_product_prices for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

-- PAYMENT METHODS: read all; manage owner/manager.
drop policy if exists "read payment methods" on public.payment_methods;
create policy "read payment methods" on public.payment_methods for select to authenticated using (true);
drop policy if exists "manage payment methods" on public.payment_methods;
create policy "manage payment methods" on public.payment_methods for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

-- INVOICES: read/create/update by store access.
drop policy if exists "read invoices" on public.invoices;
create policy "read invoices" on public.invoices for select to authenticated
  using (public.user_has_store_access(store_id));
drop policy if exists "create invoices" on public.invoices;
create policy "create invoices" on public.invoices for insert to authenticated
  with check (public.user_has_store_access(store_id));
drop policy if exists "update invoices" on public.invoices;
create policy "update invoices" on public.invoices for update to authenticated
  using (public.user_has_store_access(store_id)) with check (public.user_has_store_access(store_id));

-- INVOICE ITEMS: tied to invoice store access.
drop policy if exists "read invoice items" on public.invoice_items;
create policy "read invoice items" on public.invoice_items for select to authenticated
  using (exists (select 1 from public.invoices i where i.id = invoice_id and public.user_has_store_access(i.store_id)));
drop policy if exists "write invoice items" on public.invoice_items;
create policy "write invoice items" on public.invoice_items for all to authenticated
  using (exists (select 1 from public.invoices i where i.id = invoice_id and public.user_has_store_access(i.store_id)))
  with check (exists (select 1 from public.invoices i where i.id = invoice_id and public.user_has_store_access(i.store_id)));

-- INVOICE PAYMENTS: read by store access (writes via pay_invoice).
drop policy if exists "read invoice payments" on public.invoice_payments;
create policy "read invoice payments" on public.invoice_payments for select to authenticated
  using (exists (select 1 from public.invoices i where i.id = invoice_id and public.user_has_store_access(i.store_id)));

-- AFFILIATE COMMISSIONS: read manager+ (writes via functions).
drop policy if exists "read commissions" on public.affiliate_commissions;
create policy "read commissions" on public.affiliate_commissions for select to authenticated
  using (public.is_manager_or_above());

-- STOCK MOVEMENTS: read manager+ or store access (writes via functions).
drop policy if exists "read stock movements" on public.stock_movements;
create policy "read stock movements" on public.stock_movements for select to authenticated
  using (public.is_manager_or_above()
     or (from_store_id is not null and public.user_has_store_access(from_store_id))
     or (to_store_id is not null and public.user_has_store_access(to_store_id)));

-- TRANSFER REQUESTS + LINES: read all; insert own; update via functions/managers.
drop policy if exists "read transfer requests" on public.transfer_requests;
create policy "read transfer requests" on public.transfer_requests for select to authenticated using (true);
drop policy if exists "insert transfer requests" on public.transfer_requests;
create policy "insert transfer requests" on public.transfer_requests for insert to authenticated
  with check (requested_by = auth.uid());
drop policy if exists "update transfer requests" on public.transfer_requests;
create policy "update transfer requests" on public.transfer_requests for update to authenticated
  using (true) with check (true);

drop policy if exists "read transfer lines" on public.transfer_request_lines;
create policy "read transfer lines" on public.transfer_request_lines for select to authenticated using (true);
drop policy if exists "write transfer lines" on public.transfer_request_lines;
create policy "write transfer lines" on public.transfer_request_lines for all to authenticated
  using (true) with check (true);

-- APPROVAL REQUESTS: read own or manager+; insert own; update manager+.
drop policy if exists "read approval requests" on public.approval_requests;
create policy "read approval requests" on public.approval_requests for select to authenticated
  using (requested_by = auth.uid() or public.is_manager_or_above());
drop policy if exists "insert approval requests" on public.approval_requests;
create policy "insert approval requests" on public.approval_requests for insert to authenticated
  with check (requested_by = auth.uid());
drop policy if exists "update approval requests" on public.approval_requests;
create policy "update approval requests" on public.approval_requests for update to authenticated
  using (public.is_manager_or_above()) with check (public.is_manager_or_above());

-- AUDIT LOGS: read manager+ (writes via write_audit, SECURITY DEFINER).
drop policy if exists "read audit logs" on public.audit_logs;
create policy "read audit logs" on public.audit_logs for select to authenticated
  using (public.is_manager_or_above());

-- =====================================================================
-- BUSINESS FUNCTIONS — INVENTORY (Phase 2)
-- =====================================================================

-- Manual warehouse stock-in.
create or replace function public.warehouse_stock_in(
  p_warehouse_id uuid, p_product_id uuid, p_quantity integer,
  p_reason text, p_note text default null, p_reference text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_new_qty integer; v_movement_id uuid;
begin
  if not public.can_manage_warehouse_stock() then raise exception 'Not authorized to add warehouse stock'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be greater than zero'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason for stock-in is required'; end if;

  insert into public.warehouse_inventory (warehouse_id, product_id, current_qty)
  values (p_warehouse_id, p_product_id, p_quantity)
  on conflict (warehouse_id, product_id)
  do update set current_qty = public.warehouse_inventory.current_qty + excluded.current_qty, updated_at = now()
  returning current_qty into v_new_qty;

  insert into public.stock_movements (product_id, movement_type, to_warehouse_id, quantity, notes, created_by)
  values (p_product_id, 'warehouse_stock_in', p_warehouse_id, p_quantity,
    trim(coalesce(p_reason,'') || case when p_note is not null then ' — ' || p_note else '' end
      || case when p_reference is not null then ' (ref: ' || p_reference || ')' else '' end), auth.uid())
  returning id into v_movement_id;

  perform public.write_audit('warehouse_inventory', p_product_id, 'stock_in', null,
    jsonb_build_object('warehouse_id', p_warehouse_id, 'quantity', p_quantity, 'new_qty', v_new_qty, 'reason', p_reason));
  return v_movement_id;
end; $$;

-- Set low-stock threshold.
create or replace function public.set_low_stock_threshold(
  p_location_type location_type, p_location_id uuid, p_product_id uuid, p_threshold integer
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can set thresholds'; end if;
  if p_threshold < 0 then raise exception 'Threshold cannot be negative'; end if;
  if p_location_type = 'warehouse' then
    insert into public.warehouse_inventory (warehouse_id, product_id, current_qty, low_stock_threshold)
    values (p_location_id, p_product_id, 0, p_threshold)
    on conflict (warehouse_id, product_id) do update set low_stock_threshold = p_threshold, updated_at = now();
  else
    insert into public.store_inventory (store_id, product_id, current_qty, low_stock_threshold)
    values (p_location_id, p_product_id, 0, p_threshold)
    on conflict (store_id, product_id) do update set low_stock_threshold = p_threshold, updated_at = now();
  end if;
end; $$;

-- Create transfer request (staff allowed, store-scoped).
create or replace function public.create_transfer_request(
  p_transfer_type text, p_source_type location_type, p_source_id uuid,
  p_dest_type location_type, p_dest_id uuid, p_lines jsonb, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role user_role; v_line jsonb; v_product_id uuid; v_qty integer;
  v_available integer; v_has_price boolean; v_request_id uuid;
begin
  v_role := public.current_user_role();
  if v_role is null then raise exception 'No profile found for current user'; end if;

  if v_role = 'staff' then
    if p_source_type = 'warehouse' and p_dest_type = 'warehouse' then
      raise exception 'Staff cannot request warehouse-to-warehouse transfers'; end if;
    if p_source_type = 'store' and not public.user_has_store_access(p_source_id) then
      raise exception 'Staff can only transfer from their assigned store'; end if;
    if p_dest_type = 'store' and not public.user_has_store_access(p_dest_id) then
      raise exception 'Staff can only transfer to their assigned store'; end if;
  end if;

  if p_source_type = p_dest_type and p_source_id = p_dest_id then
    raise exception 'Source and destination must be different'; end if;
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'At least one product line is required'; end if;

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
    if coalesce(v_available,0) < v_qty then
      raise exception 'Insufficient stock at source for a product (have %, need %)', coalesce(v_available,0), v_qty; end if;

    if p_dest_type = 'store' then
      select exists (select 1 from public.store_product_prices
        where store_id = p_dest_id and product_id = v_product_id and is_active = true and deleted_at is null) into v_has_price;
      if not v_has_price then raise exception 'Destination store has no price set for a selected product'; end if;
    end if;
  end loop;

  insert into public.transfer_requests
    (transfer_type, source_type, source_id, dest_type, dest_id, status, note, requested_by)
  values (p_transfer_type, p_source_type, p_source_id, p_dest_type, p_dest_id, 'pending', p_note, auth.uid())
  returning id into v_request_id;

  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    insert into public.transfer_request_lines (transfer_request_id, product_id, quantity)
    values (v_request_id, (v_line->>'product_id')::uuid, (v_line->>'quantity')::integer);
  end loop;

  perform public.write_audit('transfer_requests', v_request_id, 'transfer_requested', null,
    jsonb_build_object('transfer_type', p_transfer_type));
  return jsonb_build_object('success', true, 'id', v_request_id);
end; $$;

-- Approve / partially approve transfer.
create or replace function public.approve_transfer(
  p_request_id uuid, p_approved_lines jsonb, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_req public.transfer_requests%rowtype; v_line jsonb; v_product_id uuid;
  v_qty integer; v_requested_qty integer; v_available integer; v_is_partial boolean := false;
  v_movement_type stock_movement_type;
  v_src_wh uuid; v_dst_wh uuid; v_src_st uuid; v_dst_st uuid;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can approve transfers'; end if;
  select * into v_req from public.transfer_requests where id = p_request_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request is not pending'; end if;

  v_movement_type := case v_req.transfer_type
    when 'warehouse_to_warehouse' then 'warehouse_to_warehouse'::stock_movement_type
    when 'warehouse_to_store' then 'warehouse_to_store'::stock_movement_type
    when 'store_to_store' then 'store_to_store'::stock_movement_type
    else 'warehouse_to_store'::stock_movement_type end;

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
    if v_requested_qty is null then raise exception 'Product not in original request'; end if;
    if v_qty > v_requested_qty then raise exception 'Approved qty cannot exceed requested qty'; end if;
    if v_qty < v_requested_qty then v_is_partial := true; end if;

    update public.transfer_request_lines set approved_quantity = v_qty
      where transfer_request_id = p_request_id and product_id = v_product_id;
    if v_qty = 0 then continue; end if;

    if v_req.source_type = 'warehouse' then
      select current_qty into v_available from public.warehouse_inventory
        where warehouse_id = v_req.source_id and product_id = v_product_id for update;
    else
      select current_qty into v_available from public.store_inventory
        where store_id = v_req.source_id and product_id = v_product_id for update;
    end if;
    if coalesce(v_available,0) < v_qty then raise exception 'Insufficient source stock (have %, approving %)', coalesce(v_available,0), v_qty; end if;

    if v_req.source_type = 'warehouse' then
      update public.warehouse_inventory set current_qty = current_qty - v_qty, updated_at = now()
        where warehouse_id = v_req.source_id and product_id = v_product_id;
    else
      update public.store_inventory set current_qty = current_qty - v_qty, updated_at = now()
        where store_id = v_req.source_id and product_id = v_product_id;
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
    null, jsonb_build_object('approved_lines', p_approved_lines));
  return jsonb_build_object('success', true,
    'status', case when v_is_partial then 'partially_approved' else 'approved' end);
end; $$;

-- Reject transfer.
create or replace function public.reject_transfer(
  p_request_id uuid, p_rejection_reason text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_req public.transfer_requests%rowtype;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can reject transfers'; end if;
  if p_rejection_reason is null or length(trim(p_rejection_reason)) = 0 then raise exception 'A rejection reason is required'; end if;
  select * into v_req from public.transfer_requests where id = p_request_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request is not pending'; end if;
  update public.transfer_requests set status = 'rejected', approved_by = auth.uid(),
    approved_at = now(), rejection_reason = p_rejection_reason where id = p_request_id;
  perform public.write_audit('transfer_requests', p_request_id, 'transfer_rejected', null,
    jsonb_build_object('rejection_reason', p_rejection_reason));
  return jsonb_build_object('success', true, 'status', 'rejected');
end; $$;

-- Cancel own pending transfer.
create or replace function public.cancel_transfer_request(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_req public.transfer_requests%rowtype;
begin
  select * into v_req from public.transfer_requests where id = p_request_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if v_req.requested_by <> auth.uid() and not public.is_owner_or_manager() then
    raise exception 'You can only cancel your own request'; end if;
  if v_req.status <> 'pending' then raise exception 'Only pending requests can be cancelled'; end if;
  update public.transfer_requests set status = 'cancelled' where id = p_request_id;
  perform public.write_audit('transfer_requests', p_request_id, 'transfer_cancelled', null, null);
  return jsonb_build_object('success', true, 'status', 'cancelled');
end; $$;

-- =====================================================================
-- BUSINESS FUNCTIONS — SALES (Phase 3)
-- =====================================================================

create or replace function public.next_invoice_no()
returns text language plpgsql security definer set search_path = public as $$
declare v_year text := to_char(now(),'YYYY'); v_count integer; v_next text;
begin
  select count(*) into v_count from public.invoices where invoice_no like 'INV-'||v_year||'-%';
  v_next := 'INV-'||v_year||'-'||lpad((v_count+1)::text,4,'0');
  while exists (select 1 from public.invoices where invoice_no = v_next) loop
    v_count := v_count + 1;
    v_next := 'INV-'||v_year||'-'||lpad((v_count+1)::text,4,'0');
  end loop;
  return v_next;
end; $$;

create or replace function public.create_invoice(
  p_store_id uuid, p_customer_id uuid, p_affiliate_id uuid,
  p_items jsonb, p_discount_total numeric default 0, p_notes text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_item jsonb; v_product_id uuid; v_qty integer; v_price numeric;
  v_subtotal numeric := 0; v_line_total numeric; v_invoice_id uuid; v_invoice_no text;
begin
  if not public.user_has_store_access(p_store_id) then raise exception 'You do not have access to this store'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'At least one product is required'; end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantity must be greater than zero'; end if;
    select selling_price into v_price from public.store_product_prices
      where store_id = p_store_id and product_id = v_product_id and is_active = true and deleted_at is null;
    if v_price is null then raise exception 'No price set for a product in this store'; end if;
    v_subtotal := v_subtotal + (v_price * v_qty);
  end loop;

  v_invoice_no := public.next_invoice_no();
  insert into public.invoices
    (invoice_no, store_id, customer_id, affiliate_id, created_by, status, subtotal, discount_total, total_amount, paid_amount, notes)
  values (v_invoice_no, p_store_id, p_customer_id, p_affiliate_id, auth.uid(), 'unpaid',
          v_subtotal, coalesce(p_discount_total,0), v_subtotal - coalesce(p_discount_total,0), 0, p_notes)
  returning id into v_invoice_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::integer;
    select selling_price into v_price from public.store_product_prices
      where store_id = p_store_id and product_id = v_product_id and is_active = true and deleted_at is null;
    v_line_total := v_price * v_qty;
    insert into public.invoice_items (invoice_id, product_id, quantity, unit_price, line_total)
    values (v_invoice_id, v_product_id, v_qty, v_price, v_line_total);
  end loop;

  perform public.write_audit('invoices', v_invoice_id, 'invoice_created', null,
    jsonb_build_object('invoice_no', v_invoice_no, 'total', v_subtotal - coalesce(p_discount_total,0)));
  return v_invoice_id;
end; $$;

create or replace function public.pay_invoice(p_invoice_id uuid, p_payments jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_pay jsonb; v_method uuid; v_amount numeric;
  v_total_paying numeric := 0; v_already_paid numeric; v_new_paid numeric;
  v_item record; v_available integer; v_affiliate public.affiliates%rowtype; v_commission numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access to this invoice''s store'; end if;
  if v_inv.status in ('paid','cancelled','refunded') then raise exception 'Invoice is already %', v_inv.status; end if;
  if p_payments is null or jsonb_array_length(p_payments) = 0 then raise exception 'At least one payment is required'; end if;

  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_amount := (v_pay->>'amount')::numeric;
    if v_amount is null or v_amount <= 0 then raise exception 'Payment amount must be positive'; end if;
    v_total_paying := v_total_paying + v_amount;
  end loop;

  v_already_paid := v_inv.paid_amount;
  v_new_paid := v_already_paid + v_total_paying;
  if v_new_paid > v_inv.total_amount + 0.001 then
    raise exception 'Payment exceeds remaining balance'; end if;

  if v_new_paid >= v_inv.total_amount - 0.001 then
    for v_item in select product_id, quantity from public.invoice_items where invoice_id = p_invoice_id
    loop
      select current_qty into v_available from public.store_inventory
        where store_id = v_inv.store_id and product_id = v_item.product_id for update;
      if coalesce(v_available,0) < v_item.quantity then
        raise exception 'Insufficient store stock for a product (have %, need %). Payment blocked.', coalesce(v_available,0), v_item.quantity;
      end if;
    end loop;
  end if;

  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_method := (v_pay->>'payment_method_id')::uuid;
    v_amount := (v_pay->>'amount')::numeric;
    insert into public.invoice_payments (invoice_id, payment_method_id, amount, payment_reference, received_by)
    values (p_invoice_id, v_method, v_amount, v_pay->>'reference', auth.uid());
  end loop;

  if v_new_paid >= v_inv.total_amount - 0.001 then
    for v_item in select product_id, quantity from public.invoice_items where invoice_id = p_invoice_id
    loop
      update public.store_inventory set current_qty = current_qty - v_item.quantity, updated_at = now()
        where store_id = v_inv.store_id and product_id = v_item.product_id;
      insert into public.stock_movements (product_id, movement_type, from_store_id, invoice_id, quantity, notes, created_by)
      values (v_item.product_id, 'store_sale', v_inv.store_id, p_invoice_id, v_item.quantity, 'Sale — '||v_inv.invoice_no, auth.uid());
    end loop;

    update public.invoices set status = 'paid', paid_amount = v_new_paid, paid_at = now(), locked_at = now()
      where id = p_invoice_id;

    if v_inv.affiliate_id is not null then
      select * into v_affiliate from public.affiliates where id = v_inv.affiliate_id;
      if found and v_affiliate.is_active then
        if v_affiliate.commission_type = 'percentage' then
          v_commission := round(v_inv.total_amount * v_affiliate.commission_value / 100.0, 2);
        else v_commission := v_affiliate.commission_value; end if;
        if v_commission > 0 then
          insert into public.affiliate_commissions (affiliate_id, invoice_id, commission_amount, status)
          values (v_inv.affiliate_id, p_invoice_id, v_commission, 'earned')
          on conflict (affiliate_id, invoice_id) do nothing;
        end if;
      end if;
    end if;

    perform public.write_audit('invoices', p_invoice_id, 'invoice_paid', null,
      jsonb_build_object('paid_amount', v_new_paid, 'invoice_no', v_inv.invoice_no));
    return jsonb_build_object('success', true, 'status', 'paid', 'paid_amount', v_new_paid);
  else
    update public.invoices set paid_amount = v_new_paid, status = 'partially_paid' where id = p_invoice_id;
    perform public.write_audit('invoices', p_invoice_id, 'invoice_partial_payment', null,
      jsonb_build_object('paid_amount', v_new_paid));
    return jsonb_build_object('success', true, 'status', 'partially_paid', 'paid_amount', v_new_paid, 'remaining', v_inv.total_amount - v_new_paid);
  end if;
end; $$;

create or replace function public.delete_invoice(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_inv public.invoices%rowtype;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access'; end if;
  if v_inv.status = 'paid' then raise exception 'Paid invoices cannot be deleted (use cancel/refund)'; end if;
  update public.invoices set deleted_at = now() where id = p_invoice_id;
  perform public.write_audit('invoices', p_invoice_id, 'invoice_deleted', to_jsonb(v_inv), null);
end; $$;

-- =====================================================================
-- BUSINESS FUNCTIONS — CONTROLS (Phase 4)
-- =====================================================================

create or replace function public.request_invoice_action(
  p_invoice_id uuid, p_type text, p_return_stock boolean, p_reason text
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_inv public.invoices%rowtype; v_req_id uuid; v_new_status invoice_status;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access to this invoice'; end if;
  if p_type not in ('invoice_cancel','invoice_refund') then raise exception 'Invalid request type'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason is required'; end if;
  if p_type = 'invoice_refund' and v_inv.status <> 'paid' then raise exception 'Only paid invoices can be refunded'; end if;
  if v_inv.status in ('cancelled','refunded') then raise exception 'Invoice is already %', v_inv.status; end if;

  v_new_status := case when p_type = 'invoice_cancel' then 'cancellation_requested'::invoice_status
                       else 'refund_requested'::invoice_status end;
  update public.invoices set status = v_new_status where id = p_invoice_id;

  insert into public.approval_requests (request_type, status, requested_by, related_record_id, reason, payload)
  values (p_type, 'pending', auth.uid(), p_invoice_id, p_reason,
    jsonb_build_object('invoice_id', p_invoice_id, 'return_stock', p_return_stock, 'invoice_no', v_inv.invoice_no))
  returning id into v_req_id;

  perform public.write_audit('invoices', p_invoice_id,
    case when p_type = 'invoice_cancel' then 'cancellation_requested' else 'refund_requested' end,
    null, jsonb_build_object('reason', p_reason, 'return_stock', p_return_stock));
  return v_req_id;
end; $$;

create or replace function public.resolve_invoice_action(
  p_request_id uuid, p_approve boolean, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_req public.approval_requests%rowtype; v_inv public.invoices%rowtype;
  v_return_stock boolean; v_item record; v_is_refund boolean; v_final_status invoice_status;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can approve'; end if;
  select * into v_req from public.approval_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request is not pending'; end if;

  select * into v_inv from public.invoices where id = v_req.related_record_id for update;
  v_is_refund := (v_req.request_type = 'invoice_refund');
  v_return_stock := coalesce((v_req.payload->>'return_stock')::boolean, false);

  if not p_approve then
    update public.invoices set status = (case when v_is_refund then 'paid' else 'unpaid' end)::invoice_status where id = v_inv.id;
    update public.approval_requests set status = 'rejected', approved_by = auth.uid(),
      approved_at = now(), response_note = p_note where id = p_request_id;
    perform public.write_audit('invoices', v_inv.id, 'invoice_action_rejected', null,
      jsonb_build_object('request_type', v_req.request_type));
    return jsonb_build_object('success', true, 'status', 'rejected');
  end if;

  v_final_status := case when v_is_refund then 'refunded'::invoice_status else 'cancelled'::invoice_status end;

  if v_return_stock then
    for v_item in select product_id, quantity from public.invoice_items where invoice_id = v_inv.id
    loop
      insert into public.store_inventory (store_id, product_id, current_qty)
      values (v_inv.store_id, v_item.product_id, v_item.quantity)
      on conflict (store_id, product_id)
      do update set current_qty = public.store_inventory.current_qty + v_item.quantity, updated_at = now();
      insert into public.stock_movements (product_id, movement_type, to_store_id, invoice_id, quantity, notes, created_by)
      values (v_item.product_id,
        (case when v_is_refund then 'invoice_refund_return' else 'invoice_cancel_return' end)::stock_movement_type,
        v_inv.store_id, v_inv.id, v_item.quantity, 'Stock returned — '||v_inv.invoice_no, auth.uid());
    end loop;
  end if;

  update public.affiliate_commissions set status = 'reversed', reversed_at = now()
    where invoice_id = v_inv.id and status = 'earned';
  update public.invoices set status = v_final_status where id = v_inv.id;
  update public.approval_requests set status = 'approved', approved_by = auth.uid(),
    approved_at = now(), response_note = p_note where id = p_request_id;

  perform public.write_audit('invoices', v_inv.id,
    case when v_is_refund then 'invoice_refunded' else 'invoice_cancelled' end, null,
    jsonb_build_object('return_stock', v_return_stock, 'invoice_no', v_inv.invoice_no));
  return jsonb_build_object('success', true, 'status', v_final_status, 'stock_returned', v_return_stock);
end; $$;

create or replace function public.request_inventory_adjustment(
  p_location_type location_type, p_location_id uuid, p_product_id uuid,
  p_new_qty integer, p_reason text, p_reference text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_current integer; v_req_id uuid;
begin
  if p_new_qty < 0 then raise exception 'Adjusted quantity cannot be negative'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason is required'; end if;

  if p_location_type = 'store' then
    if not public.user_has_store_access(p_location_id) then raise exception 'You can only adjust your assigned store'; end if;
    select current_qty into v_current from public.store_inventory where store_id = p_location_id and product_id = p_product_id;
  else
    if not public.can_manage_warehouse_stock() then raise exception 'Not authorized to adjust warehouse stock'; end if;
    select current_qty into v_current from public.warehouse_inventory where warehouse_id = p_location_id and product_id = p_product_id;
  end if;
  v_current := coalesce(v_current, 0);

  insert into public.approval_requests (request_type, status, requested_by, related_record_id, reason, payload)
  values ('adjustment', 'pending', auth.uid(), p_product_id, p_reason,
    jsonb_build_object('location_type', p_location_type, 'location_id', p_location_id,
      'product_id', p_product_id, 'current_qty', v_current, 'new_qty', p_new_qty,
      'difference', p_new_qty - v_current, 'reference', p_reference))
  returning id into v_req_id;

  perform public.write_audit('inventory_adjustment', p_product_id, 'adjustment_requested', null,
    jsonb_build_object('from', v_current, 'to', p_new_qty));
  return v_req_id;
end; $$;

create or replace function public.resolve_inventory_adjustment(
  p_request_id uuid, p_approve boolean, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_req public.approval_requests%rowtype; v_loc_type location_type; v_loc_id uuid;
  v_product_id uuid; v_new_qty integer; v_current integer;
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
      abs(v_new_qty - v_current), 'Adjustment: '||coalesce(v_req.reason,''), auth.uid());
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
      abs(v_new_qty - v_current), 'Adjustment: '||coalesce(v_req.reason,''), auth.uid());
  end if;

  update public.approval_requests set status = 'approved', approved_by = auth.uid(),
    approved_at = now(), response_note = p_note where id = p_request_id;
  perform public.write_audit('inventory_adjustment', v_product_id, 'adjustment_approved', null,
    jsonb_build_object('from', v_current, 'to', v_new_qty));
  return jsonb_build_object('success', true, 'status', 'approved', 'new_qty', v_new_qty);
end; $$;

create or replace function public.restore_record(p_table text, p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can restore records'; end if;
  if p_table not in ('products','warehouses','stores','customers','affiliates','invoices','payment_methods') then
    raise exception 'Restore not supported for table %', p_table; end if;
  execute format('update public.%I set deleted_at = null where id = $1', p_table) using p_id;
  perform public.write_audit(p_table, p_id, 'restored', null, null);
end; $$;

-- =====================================================================
-- RELOAD POSTGREST SCHEMA CACHE so all functions are visible immediately.
-- =====================================================================

-- =====================================================================
-- ✅ SCHEMA COMPLETE.
--
-- NEXT STEPS (do these now):
--   1. Supabase Dashboard → Authentication → Users → "Add user".
--      Create your Owner login (email + password). Copy its User UID.
--   2. Uncomment the block below, paste your UID + email, and run it.
-- =====================================================================

/*
-- ---- STARTER DATA (uncomment, edit, run after creating the Auth user) ----
insert into public.profiles (id, full_name, email, role)
values ('PASTE-YOUR-AUTH-USER-UID-HERE', 'Shin Thant Aung', 'your-email@example.com', 'owner');

insert into public.warehouses (name, code, address)
values ('Main Warehouse', 'WH-MAIN', 'Singapore');

insert into public.stores (name, code, address)
values ('Energia Rev22 (Adelphi)', 'STORE-ADELPHI', '1 Coleman St, B1-37 The Adelphi, Singapore 179803');

insert into public.payment_methods (name) values
  ('Cash'), ('PayNow'), ('Bank Transfer'), ('Credit Card'), ('GrabPay');

insert into public.products (name, sku, product_type, category, brand, uom, default_cost_price)
values
  ('Energia Wellness Corset 3.0', 'EN-CORSET-3', 'own', 'Wellness', 'Energia', 'pcs', 40.00),
  ('Socks Black', 'TP-SOCKS-BLK', 'third_party', 'Apparel', 'Generic', 'pcs', 5.00);
*/


-- =====================================================================
-- PHASE 5A — customer referral graph + profile stats
--   (source: 14_phase5a_foundations.sql)
-- =====================================================================

-- =====================================================================
-- ENERGIA — PHASE 5A: Foundations
--   (1) Customer-based referral graph (referred_by on customers)
--   (2) Customer profile stats helper (purchases, spend, referrals, commission)
--   (3) Address enforcement is done in the app layer; columns already exist.
--
-- Additive + idempotent. Run AFTER 00_complete_setup.sql. Does not touch
-- existing objects except adding columns/policies.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Referral graph: a customer may be referred by another customer.
--    Tier 1 referrer = customers.referred_by.
--    Tier 2 referrer = referred_by of the Tier 1 referrer (derived, not stored).
-- ---------------------------------------------------------------------
alter table public.customers add column if not exists referred_by uuid references public.customers(id);
alter table public.customers add column if not exists is_referrer boolean not null default false;

create index if not exists idx_customers_referred_by on public.customers(referred_by);

-- Guard: a customer cannot refer themselves.
create or replace function public.tg_customers_no_self_referral()
returns trigger language plpgsql as $$
begin
  if new.referred_by is not null and new.referred_by = new.id then
    raise exception 'A customer cannot be their own referrer';
  end if;
  return new;
end; $$;

drop trigger if exists trg_customers_no_self_referral on public.customers;
create trigger trg_customers_no_self_referral
  before insert or update on public.customers
  for each row execute function public.tg_customers_no_self_referral();

-- ---------------------------------------------------------------------
-- 2. Resolve a customer's Tier 1 and Tier 2 referrer ids in one call.
--    Used by the commission engine (5B) and the customer profile view.
-- ---------------------------------------------------------------------
create or replace function public.customer_referrers(p_customer_id uuid)
returns table (tier1 uuid, tier2 uuid)
language sql stable security definer set search_path = public as $$
  select
    c.referred_by as tier1,
    t1.referred_by as tier2
  from public.customers c
  left join public.customers t1 on t1.id = c.referred_by
  where c.id = p_customer_id
$$;

-- ---------------------------------------------------------------------
-- 3. Customer profile stats (one row of aggregates for the profile page).
--    Spend + purchase counts come from paid invoices.
--    Commission figures come from affiliate_commissions (rewritten in 5B);
--    until 5B runs, those columns simply read 0.
-- ---------------------------------------------------------------------
create or replace function public.customer_profile_stats(p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_purchases integer := 0;
  v_total_spend numeric := 0;
  v_referred_count integer := 0;
  v_referrer_name text;
begin
  select count(*), coalesce(sum(total_amount),0)
    into v_purchases, v_total_spend
    from public.invoices
    where customer_id = p_customer_id and status = 'paid' and deleted_at is null;

  select count(*) into v_referred_count
    from public.customers where referred_by = p_customer_id and deleted_at is null;

  select c2.full_name into v_referrer_name
    from public.customers c1
    join public.customers c2 on c2.id = c1.referred_by
    where c1.id = p_customer_id;

  return jsonb_build_object(
    'purchases', v_purchases,
    'total_spend', v_total_spend,
    'referred_count', v_referred_count,
    'referrer_name', v_referrer_name
  );
end; $$;



-- =====================================================================
-- PHASE 5B — two-tier commission + payouts + pay_invoice rewrite
--   (source: 15_phase5b_commission.sql)
-- =====================================================================

-- =====================================================================
-- ENERGIA — PHASE 5B: Two-tier customer-referral commission
--   * New commissions table (per invoice line, tier 1 + tier 2)
--   * Monthly commission payout grouping
--   * pay_invoice rewritten to compute referral commission
--   * resolve_invoice_action reverses commission on refund/cancel
--
-- Tier 1: Own 15% / 3rd-party 4.5% of the line amount AFTER discount.
-- Tier 2: 5% of the Tier-1 commission amount.
-- Referrers come from customers.referred_by (5A). Stops at Tier 2.
--
-- Additive + idempotent. Run AFTER 14_phase5a_foundations.sql.
-- =====================================================================

-- Ensure commission_status has 'paid' (older databases were created without it).
alter type public.commission_status add value if not exists 'paid';

-- ---------------------------------------------------------------------
-- Commission rate constants (kept in one place for clarity).
-- Own product Tier-1 = 15%, 3rd-party Tier-1 = 4.5%, Tier-2 = 5% of Tier-1.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- 1. New per-line commission table.
-- ---------------------------------------------------------------------
do $$ begin
  create type commission_tier as enum ('tier1','tier2');
exception when duplicate_object then null; end $$;

create table if not exists public.commissions (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  invoice_item_id uuid references public.invoice_items(id) on delete set null,
  buyer_customer_id uuid not null references public.customers(id),
  referrer_customer_id uuid not null references public.customers(id),
  tier commission_tier not null,
  product_type text,                       -- 'own' | 'third_party'
  line_amount numeric(12,2) not null default 0,   -- after-discount basis
  rate numeric(6,3) not null default 0,           -- percent applied
  commission_amount numeric(12,2) not null default 0,
  status commission_status not null default 'earned',
  payout_id uuid,                          -- set when grouped into a monthly payout
  invoice_paid_date date,
  reversal_reason text,
  created_at timestamptz not null default now(),
  reversed_at timestamptz
);
create index if not exists idx_commissions_invoice on public.commissions(invoice_id);
create index if not exists idx_commissions_referrer on public.commissions(referrer_customer_id);
create index if not exists idx_commissions_status on public.commissions(status);
create index if not exists idx_commissions_paid_date on public.commissions(invoice_paid_date);

alter table public.commissions enable row level security;
drop policy if exists "read commissions new" on public.commissions;
create policy "read commissions new" on public.commissions for select to authenticated
  using (public.is_manager_or_above());

-- ---------------------------------------------------------------------
-- 2. Monthly commission payouts.
-- ---------------------------------------------------------------------
create table if not exists public.commission_payouts (
  id uuid primary key default gen_random_uuid(),
  payout_month date not null,              -- first day of the month
  referrer_customer_id uuid not null references public.customers(id),
  total_tier1 numeric(12,2) not null default 0,
  total_tier2 numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  payment_method_id uuid references public.payment_methods(id),
  reference text,
  notes text,
  status text not null default 'paid',     -- 'paid' | 'cancelled'
  paid_by uuid references public.profiles(id),
  paid_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists idx_payouts_month on public.commission_payouts(payout_month);
create index if not exists idx_payouts_referrer on public.commission_payouts(referrer_customer_id);

alter table public.commission_payouts enable row level security;
drop policy if exists "read payouts" on public.commission_payouts;
create policy "read payouts" on public.commission_payouts for select to authenticated
  using (public.is_manager_or_above());

-- ---------------------------------------------------------------------
-- 3. Core engine: earn commission for a fully-paid invoice.
--    Called from pay_invoice once an invoice flips to paid.
--    Allocates invoice discount proportionally across lines so the
--    commission basis is "after discount" (voucher-ready for 5C).
-- ---------------------------------------------------------------------
create or replace function public.earn_invoice_commission(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype;
  v_tier1 uuid; v_tier2 uuid;
  v_item record;
  v_ptype text;
  v_subtotal numeric;
  v_discount numeric;
  v_line_after numeric;
  v_t1_rate numeric;
  v_t1_amt numeric;
  v_t2_amt numeric;
  v_paid_date date;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return; end if;

  -- Resolve the buyer's referral chain (Tier 1 + Tier 2).
  select tier1, tier2 into v_tier1, v_tier2 from public.customer_referrers(v_inv.customer_id);
  if v_tier1 is null then return; end if;  -- no referrer → no commission

  v_paid_date := coalesce(v_inv.paid_at, now())::date;
  v_subtotal := nullif(v_inv.subtotal, 0);
  v_discount := coalesce(v_inv.discount_total, 0);

  for v_item in
    select ii.id, ii.product_id, ii.quantity, ii.line_total, p.product_type::text as ptype
    from public.invoice_items ii
    join public.products p on p.id = ii.product_id
    where ii.invoice_id = p_invoice_id
  loop
    v_ptype := v_item.ptype;

    -- Line amount after proportional discount allocation.
    if v_subtotal is null then
      v_line_after := v_item.line_total;
    else
      v_line_after := v_item.line_total - (v_discount * (v_item.line_total / v_subtotal));
    end if;
    if v_line_after < 0 then v_line_after := 0; end if;

    -- Tier-1 rate by product type (own 15%, third_party 4.5%).
    v_t1_rate := case when v_ptype = 'third_party' then 4.5 else 15 end;
    v_t1_amt := round(v_line_after * v_t1_rate / 100.0, 2);
    if v_t1_amt <= 0 then continue; end if;

    insert into public.commissions
      (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
       product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
    values
      (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1',
       v_ptype, v_line_after, v_t1_rate, v_t1_amt, 'earned', v_paid_date);

    -- Tier-2 = 5% of the Tier-1 amount (only if a Tier-2 referrer exists).
    if v_tier2 is not null then
      v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
      if v_t2_amt > 0 then
        insert into public.commissions
          (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
           product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
        values
          (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2',
           v_ptype, v_t1_amt, 5.0, v_t2_amt, 'earned', v_paid_date);
      end if;
    end if;
  end loop;

  perform public.write_audit('commissions', p_invoice_id, 'commission_calculated', null,
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'tier1', v_tier1, 'tier2', v_tier2));
end; $$;

-- ---------------------------------------------------------------------
-- 4. Reverse commission for an invoice (on refund/cancel).
-- ---------------------------------------------------------------------
create or replace function public.reverse_invoice_commission(p_invoice_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.commissions
    set status = 'reversed', reversed_at = now(), reversal_reason = coalesce(p_reason,'invoice reversed')
    where invoice_id = p_invoice_id and status in ('earned');
  perform public.write_audit('commissions', p_invoice_id, 'commission_reversed', null,
    jsonb_build_object('reason', p_reason));
end; $$;

-- ---------------------------------------------------------------------
-- 5. pay_invoice — rewritten to use the new commission engine.
--    (Stock deduction + payment logic unchanged; only the commission
--    block at the end is replaced.)
-- ---------------------------------------------------------------------
create or replace function public.pay_invoice(p_invoice_id uuid, p_payments jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_pay jsonb; v_method uuid; v_amount numeric;
  v_total_paying numeric := 0; v_already_paid numeric; v_new_paid numeric;
  v_item record; v_available integer;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access to this invoice''s store'; end if;
  if v_inv.status in ('paid','cancelled','refunded') then raise exception 'Invoice is already %', v_inv.status; end if;
  if p_payments is null or jsonb_array_length(p_payments) = 0 then raise exception 'At least one payment is required'; end if;

  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_amount := (v_pay->>'amount')::numeric;
    if v_amount is null or v_amount <= 0 then raise exception 'Payment amount must be positive'; end if;
    v_total_paying := v_total_paying + v_amount;
  end loop;

  v_already_paid := v_inv.paid_amount;
  v_new_paid := v_already_paid + v_total_paying;
  if v_new_paid > v_inv.total_amount + 0.001 then raise exception 'Payment exceeds remaining balance'; end if;

  if v_new_paid >= v_inv.total_amount - 0.001 then
    for v_item in select product_id, quantity from public.invoice_items where invoice_id = p_invoice_id
    loop
      select current_qty into v_available from public.store_inventory
        where store_id = v_inv.store_id and product_id = v_item.product_id for update;
      if coalesce(v_available,0) < v_item.quantity then
        raise exception 'Insufficient store stock for a product (have %, need %). Payment blocked.', coalesce(v_available,0), v_item.quantity;
      end if;
    end loop;
  end if;

  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_method := (v_pay->>'payment_method_id')::uuid;
    v_amount := (v_pay->>'amount')::numeric;
    insert into public.invoice_payments (invoice_id, payment_method_id, amount, payment_reference, received_by)
    values (p_invoice_id, v_method, v_amount, v_pay->>'reference', auth.uid());
  end loop;

  if v_new_paid >= v_inv.total_amount - 0.001 then
    for v_item in select product_id, quantity from public.invoice_items where invoice_id = p_invoice_id
    loop
      update public.store_inventory set current_qty = current_qty - v_item.quantity, updated_at = now()
        where store_id = v_inv.store_id and product_id = v_item.product_id;
      insert into public.stock_movements (product_id, movement_type, from_store_id, invoice_id, quantity, notes, created_by)
      values (v_item.product_id, 'store_sale', v_inv.store_id, p_invoice_id, v_item.quantity, 'Sale — '||v_inv.invoice_no, auth.uid());
    end loop;

    update public.invoices set status = 'paid', paid_amount = v_new_paid, paid_at = now(), locked_at = now()
      where id = p_invoice_id;

    -- NEW: two-tier referral commission.
    perform public.earn_invoice_commission(p_invoice_id);

    perform public.write_audit('invoices', p_invoice_id, 'invoice_paid', null,
      jsonb_build_object('paid_amount', v_new_paid, 'invoice_no', v_inv.invoice_no));
    return jsonb_build_object('success', true, 'status', 'paid', 'paid_amount', v_new_paid);
  else
    update public.invoices set paid_amount = v_new_paid, status = 'partially_paid' where id = p_invoice_id;
    perform public.write_audit('invoices', p_invoice_id, 'invoice_partial_payment', null,
      jsonb_build_object('paid_amount', v_new_paid));
    return jsonb_build_object('success', true, 'status', 'partially_paid', 'paid_amount', v_new_paid, 'remaining', v_inv.total_amount - v_new_paid);
  end if;
end; $$;

-- ---------------------------------------------------------------------
-- 6. resolve_invoice_action — reverse NEW commissions on refund/cancel.
--    (Same logic as before; swaps the old affiliate_commissions update
--     for reverse_invoice_commission.)
-- ---------------------------------------------------------------------
create or replace function public.resolve_invoice_action(
  p_request_id uuid, p_approve boolean, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_req public.approval_requests%rowtype; v_inv public.invoices%rowtype;
  v_return_stock boolean; v_item record; v_is_refund boolean; v_final_status invoice_status;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can approve'; end if;
  select * into v_req from public.approval_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request is not pending'; end if;

  select * into v_inv from public.invoices where id = v_req.related_record_id for update;
  v_is_refund := (v_req.request_type = 'invoice_refund');
  v_return_stock := coalesce((v_req.payload->>'return_stock')::boolean, false);

  if not p_approve then
    update public.invoices set status = (case when v_is_refund then 'paid' else 'unpaid' end)::invoice_status where id = v_inv.id;
    update public.approval_requests set status = 'rejected', approved_by = auth.uid(),
      approved_at = now(), response_note = p_note where id = p_request_id;
    perform public.write_audit('invoices', v_inv.id, 'invoice_action_rejected', null,
      jsonb_build_object('request_type', v_req.request_type));
    return jsonb_build_object('success', true, 'status', 'rejected');
  end if;

  v_final_status := case when v_is_refund then 'refunded'::invoice_status else 'cancelled'::invoice_status end;

  if v_return_stock then
    for v_item in select product_id, quantity from public.invoice_items where invoice_id = v_inv.id
    loop
      insert into public.store_inventory (store_id, product_id, current_qty)
      values (v_inv.store_id, v_item.product_id, v_item.quantity)
      on conflict (store_id, product_id)
      do update set current_qty = public.store_inventory.current_qty + v_item.quantity, updated_at = now();
      insert into public.stock_movements (product_id, movement_type, to_store_id, invoice_id, quantity, notes, created_by)
      values (v_item.product_id,
        (case when v_is_refund then 'invoice_refund_return' else 'invoice_cancel_return' end)::stock_movement_type,
        v_inv.store_id, v_inv.id, v_item.quantity, 'Stock returned — '||v_inv.invoice_no, auth.uid());
    end loop;
  end if;

  -- NEW: reverse two-tier commission.
  perform public.reverse_invoice_commission(v_inv.id,
    case when v_is_refund then 'invoice refunded' else 'invoice cancelled' end);

  update public.invoices set status = v_final_status where id = v_inv.id;
  update public.approval_requests set status = 'approved', approved_by = auth.uid(),
    approved_at = now(), response_note = p_note where id = p_request_id;

  perform public.write_audit('invoices', v_inv.id,
    case when v_is_refund then 'invoice_refunded' else 'invoice_cancelled' end, null,
    jsonb_build_object('return_stock', v_return_stock, 'invoice_no', v_inv.invoice_no));
  return jsonb_build_object('success', true, 'status', v_final_status, 'stock_returned', v_return_stock);
end; $$;

-- ---------------------------------------------------------------------
-- 7. Create a monthly payout: groups all earned+unpaid commissions for a
--    referrer in a given month (by invoice_paid_date) into one payout.
-- ---------------------------------------------------------------------
create or replace function public.create_commission_payout(
  p_referrer_customer_id uuid, p_month date, p_payment_method_id uuid,
  p_reference text default null, p_notes text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_month_start date := date_trunc('month', p_month)::date;
  v_month_end date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  v_t1 numeric := 0; v_t2 numeric := 0; v_payout_id uuid;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can mark commission paid'; end if;

  select
    coalesce(sum(case when tier='tier1' then commission_amount else 0 end),0),
    coalesce(sum(case when tier='tier2' then commission_amount else 0 end),0)
    into v_t1, v_t2
    from public.commissions
    where referrer_customer_id = p_referrer_customer_id
      and status = 'earned' and payout_id is null
      and invoice_paid_date between v_month_start and v_month_end;

  if (v_t1 + v_t2) <= 0 then raise exception 'No unpaid commission for this referrer in that month'; end if;

  insert into public.commission_payouts
    (payout_month, referrer_customer_id, total_tier1, total_tier2, total_amount,
     payment_method_id, reference, notes, status, paid_by)
  values (v_month_start, p_referrer_customer_id, v_t1, v_t2, v_t1 + v_t2,
     p_payment_method_id, p_reference, p_notes, 'paid', auth.uid())
  returning id into v_payout_id;

  update public.commissions
    set status = 'paid', payout_id = v_payout_id
    where referrer_customer_id = p_referrer_customer_id
      and status = 'earned' and payout_id is null
      and invoice_paid_date between v_month_start and v_month_end;

  perform public.write_audit('commission_payouts', v_payout_id, 'commission_payout_created', null,
    jsonb_build_object('month', v_month_start, 'referrer', p_referrer_customer_id, 'total', v_t1 + v_t2));
  return v_payout_id;
end; $$;



-- =====================================================================
-- PHASE 5B.2 — referrer views (downline, list, earnings)
--   (source: 16_phase5b2_referrers.sql)
-- =====================================================================

-- =====================================================================
-- ENERGIA — PHASE 5B.2: Referrer relationship + earnings views
--   * referrer_downline(p_customer_id)  → full recursive downline tree
--   * referrer_list()                   → everyone who referred / earned
--   * referrer_earnings(p_customer_id)  → lifetime + per-month + paid/unpaid,
--                                          plus per-buyer (Tier 2 traceback)
--
-- Additive + idempotent. Run AFTER 15_phase5b_commission.sql.
--
-- PREREQUISITE: the commission_status enum must include 'paid'. If you get
-- "invalid input value for enum commission_status: paid", run
-- 15b_fix_commission_status_enum.sql by itself first, then re-run this file.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Full downline tree for a referrer, however deep the chain goes.
--    Returns each descendant with its depth (1 = directly referred).
-- ---------------------------------------------------------------------
create or replace function public.referrer_downline(p_customer_id uuid)
returns table (
  customer_id uuid,
  full_name text,
  phone text,
  referred_by uuid,
  depth integer,
  paid_purchases integer,
  total_spend numeric
)
language sql stable security definer set search_path = public as $$
  with recursive tree as (
    select c.id, c.full_name, c.phone, c.referred_by, 1 as depth
    from public.customers c
    where c.referred_by = p_customer_id and c.deleted_at is null
    union all
    select c.id, c.full_name, c.phone, c.referred_by, t.depth + 1
    from public.customers c
    join tree t on c.referred_by = t.id
    where c.deleted_at is null and t.depth < 50   -- safety bound
  )
  select
    t.id, t.full_name, t.phone, t.referred_by, t.depth,
    coalesce(inv.cnt, 0)::integer as paid_purchases,
    coalesce(inv.spend, 0) as total_spend
  from tree t
  left join lateral (
    select count(*) as cnt, sum(i.total_amount) as spend
    from public.invoices i
    where i.customer_id = t.id and i.status = 'paid' and i.deleted_at is null
  ) inv on true
  order by t.depth, t.full_name
$$;

-- ---------------------------------------------------------------------
-- 2. List of referrers: any customer who has referred someone OR earned
--    commission. Includes quick headline numbers for the list view.
-- ---------------------------------------------------------------------
create or replace function public.referrer_list()
returns table (
  customer_id uuid,
  full_name text,
  phone text,
  direct_referrals integer,
  total_downline integer,
  lifetime_earned numeric,
  unpaid_earned numeric
)
language sql stable security definer set search_path = public as $$
  with referrers as (
    -- customers who have referred at least one person
    select distinct referred_by as cid from public.customers
    where referred_by is not null
    union
    -- customers who have earned commission
    select distinct referrer_customer_id as cid from public.commissions
  )
  select
    c.id, c.full_name, c.phone,
    coalesce(d.direct_cnt, 0)::integer as direct_referrals,
    coalesce(dl.total_cnt, 0)::integer as total_downline,
    coalesce(e.lifetime, 0) as lifetime_earned,
    coalesce(e.unpaid, 0) as unpaid_earned
  from referrers r
  join public.customers c on c.id = r.cid and c.deleted_at is null
  left join lateral (
    select count(*) as direct_cnt from public.customers x
    where x.referred_by = c.id and x.deleted_at is null
  ) d on true
  left join lateral (
    select count(*) as total_cnt from public.referrer_downline(c.id)
  ) dl on true
  left join lateral (
    select
      coalesce(sum(case when status in ('earned','paid') then commission_amount else 0 end),0) as lifetime,
      coalesce(sum(case when status = 'earned' then commission_amount else 0 end),0) as unpaid
    from public.commissions cm where cm.referrer_customer_id = c.id
  ) e on true
  order by coalesce(e.lifetime, 0) desc, c.full_name
$$;

-- ---------------------------------------------------------------------
-- 3. Full earnings detail for one referrer.
--    Returns a JSON object with:
--      - lifetime totals (tier1/tier2, paid/unpaid)
--      - per-month breakdown
--      - per-buyer subtotals (the Tier 2 "from which Tier 1" trace)
--      - every commission line (for the expandable detail)
-- ---------------------------------------------------------------------
create or replace function public.referrer_earnings(p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_lifetime jsonb;
  v_monthly jsonb;
  v_by_buyer jsonb;
  v_lines jsonb;
begin
  -- Lifetime split by tier and paid/unpaid.
  select jsonb_build_object(
    'tier1_earned', coalesce(sum(case when tier='tier1' and status='earned' then commission_amount else 0 end),0),
    'tier1_paid',   coalesce(sum(case when tier='tier1' and status='paid'   then commission_amount else 0 end),0),
    'tier2_earned', coalesce(sum(case when tier='tier2' and status='earned' then commission_amount else 0 end),0),
    'tier2_paid',   coalesce(sum(case when tier='tier2' and status='paid'   then commission_amount else 0 end),0),
    'reversed',     coalesce(sum(case when status='reversed' then commission_amount else 0 end),0),
    'total_earned', coalesce(sum(case when status='earned' then commission_amount else 0 end),0),
    'total_paid',   coalesce(sum(case when status='paid'   then commission_amount else 0 end),0)
  ) into v_lifetime
  from public.commissions where referrer_customer_id = p_customer_id;

  -- Per-month breakdown (by invoice paid date), tier + paid/unpaid split.
  select coalesce(jsonb_agg(row_to_json(m)), '[]'::jsonb) into v_monthly
  from (
    select
      to_char(date_trunc('month', invoice_paid_date), 'YYYY-MM') as month,
      sum(case when tier='tier1' then commission_amount else 0 end) as tier1,
      sum(case when tier='tier2' then commission_amount else 0 end) as tier2,
      sum(case when status='earned' then commission_amount else 0 end) as unpaid,
      sum(case when status='paid' then commission_amount else 0 end) as paid,
      sum(commission_amount) as total
    from public.commissions
    where referrer_customer_id = p_customer_id and status in ('earned','paid')
    group by date_trunc('month', invoice_paid_date)
    order by date_trunc('month', invoice_paid_date) desc
  ) m;

  -- Per-buyer subtotals: how much this referrer earned from each buyer,
  -- split by tier. For Tier 2 rows the buyer is Customer 3, so this is the
  -- "from which downline" trace.
  select coalesce(jsonb_agg(row_to_json(b)), '[]'::jsonb) into v_by_buyer
  from (
    select
      cm.buyer_customer_id,
      cust.full_name as buyer_name,
      sum(case when cm.tier='tier1' then cm.commission_amount else 0 end) as tier1,
      sum(case when cm.tier='tier2' then cm.commission_amount else 0 end) as tier2,
      sum(cm.commission_amount) as total,
      count(*) as lines
    from public.commissions cm
    join public.customers cust on cust.id = cm.buyer_customer_id
    where cm.referrer_customer_id = p_customer_id and cm.status in ('earned','paid')
    group by cm.buyer_customer_id, cust.full_name
    order by total desc
  ) b;

  -- Every commission line (for expandable detail under each buyer).
  select coalesce(jsonb_agg(row_to_json(l)), '[]'::jsonb) into v_lines
  from (
    select
      cm.id, cm.buyer_customer_id, cm.tier, cm.product_type,
      cm.line_amount, cm.rate, cm.commission_amount, cm.status,
      cm.invoice_paid_date, inv.invoice_no, p.name as product_name
    from public.commissions cm
    join public.invoices inv on inv.id = cm.invoice_id
    left join public.invoice_items ii on ii.id = cm.invoice_item_id
    left join public.products p on p.id = ii.product_id
    where cm.referrer_customer_id = p_customer_id
    order by cm.invoice_paid_date desc, cm.tier
  ) l;

  return jsonb_build_object(
    'lifetime', v_lifetime,
    'monthly', v_monthly,
    'by_buyer', v_by_buyer,
    'lines', v_lines
  );
end; $$;



-- =====================================================================
-- Reload PostgREST schema cache so all functions are visible immediately.
-- =====================================================================
notify pgrst, 'reload schema';
