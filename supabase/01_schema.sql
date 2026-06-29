-- =====================================================================
-- ENERGIA INVENTORY SYSTEM — DATABASE SCHEMA
-- Refined from Shin's setup documentation (Appendix A)
-- Run this FIRST in the Supabase SQL Editor on a fresh project.
-- =====================================================================

-- ========================= 1. ENUM TYPES =========================
create type user_role as enum (
  'owner', 'admin', 'manager', 'inventory_manager', 'staff'
);

create type product_type as enum ('own', 'third_party');

create type location_type as enum ('warehouse', 'store');

-- Refined: added the intermediate workflow states the spec requires
create type invoice_status as enum (
  'draft',
  'unpaid',
  'partially_paid',
  'paid',
  'cancellation_requested',
  'cancelled',
  'refund_requested',
  'refunded'
);

create type approval_status as enum (
  'pending', 'approved', 'partially_approved', 'rejected', 'cancelled'
);

create type stock_movement_type as enum (
  'warehouse_stock_in',
  'warehouse_to_store',
  'warehouse_to_warehouse',
  'store_to_store',
  'store_sale',
  'invoice_cancel_return',
  'invoice_refund_return',
  'inventory_adjustment'
);

create type commission_status as enum ('earned', 'reversed', 'cancelled');

-- ========================= 2. PROFILES =========================
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null unique,
  role user_role not null default 'staff',
  is_active boolean not null default true,
  deleted_at timestamptz,                       -- soft delete
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ========================= 3. LOCATIONS =========================
create table public.warehouses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  address text,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.stores (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  address text,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.user_store_assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(user_id, store_id)
);

-- ========================= 4. PRODUCTS (master data only) =========================
create table public.products (
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
create table public.warehouse_inventory (
  id uuid primary key default gen_random_uuid(),
  warehouse_id uuid not null references public.warehouses(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  current_qty integer not null default 0 check (current_qty >= 0),
  low_stock_threshold integer not null default 0,
  updated_at timestamptz not null default now(),
  unique(warehouse_id, product_id)
);

create table public.store_inventory (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  current_qty integer not null default 0 check (current_qty >= 0),
  low_stock_threshold integer not null default 0,
  updated_at timestamptz not null default now(),
  unique(store_id, product_id)
);

-- ========================= 6. CUSTOMERS (globally unique phone) =========================
create table public.customers (
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

-- ========================= 7. AFFILIATES (standalone) =========================
create table public.affiliates (
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
create table public.store_product_prices (
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
create table public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

-- ========================= 10. INVOICES =========================
create table public.invoices (
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

create table public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  product_id uuid not null references public.products(id),
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  line_total numeric(12,2) not null check (line_total >= 0)
);

create table public.invoice_payments (
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
create table public.affiliate_commissions (
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
create table public.stock_movements (
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

-- ========================= 13. APPROVAL REQUESTS =========================
-- Covers: stock transfers, inventory adjustments, invoice cancel/refund
create table public.approval_requests (
  id uuid primary key default gen_random_uuid(),
  request_type text not null,          -- 'transfer' | 'adjustment' | 'invoice_cancel' | 'invoice_refund'
  status approval_status not null default 'pending',
  requested_by uuid not null references public.profiles(id),
  approved_by uuid references public.profiles(id),
  related_record_id uuid,
  payload jsonb,                        -- request-type-specific details
  reason text,
  response_note text,
  rejection_reason text,
  created_at timestamptz not null default now(),
  approved_at timestamptz
);

-- ========================= 14. AUDIT LOG =========================
create table public.audit_logs (
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
create index idx_warehouse_inventory_product on public.warehouse_inventory(product_id);
create index idx_store_inventory_product on public.store_inventory(product_id);
create index idx_invoices_store on public.invoices(store_id);
create index idx_invoices_customer on public.invoices(customer_id);
create index idx_invoices_status on public.invoices(status);
create index idx_invoice_items_invoice on public.invoice_items(invoice_id);
create index idx_invoice_payments_invoice on public.invoice_payments(invoice_id);
create index idx_stock_movements_product on public.stock_movements(product_id);
create index idx_approval_requests_status on public.approval_requests(status);
create index idx_audit_logs_record on public.audit_logs(record_id);
