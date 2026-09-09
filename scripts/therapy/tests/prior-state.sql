-- =====================================================================
-- The database as migration 220 finds it.
--
-- Reduced, but faithful where it matters: therapy_expiry() and the entitlement
-- tables are copied from migrations 53, 72 and 74 so the calendar-month
-- convention under test is the real one, not a restatement of it.
--
-- Deliberate deviations from production, none of which touch the expiry rules:
--   * no RLS, no invoice/store foreign keys beyond what the functions read;
--   * current_user_role() and is_manager_or_above() read session settings, so a
--     test can be an owner or a cashier without inventing a JWT;
--   * auth.uid() returns a session setting rather than a real token subject.
--
-- Safe to run repeatedly.
-- =====================================================================

set check_function_bodies = off;

create schema if not exists auth;

create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  full_name text,
  role text,
  is_active boolean not null default true
);

create table if not exists public.stores (
  id uuid primary key default gen_random_uuid(),
  name text not null
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text not null,
  email text,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

-- From migration 17. voucher_kind is what separates a service voucher from a
-- money-off one, and migration 222 reads it, so it has to exist here or the
-- migration cannot even be applied.
do $$ begin create type voucher_kind as enum ('normal','fixed_discount','percentage_discount');
exception when duplicate_object then null; end $$;
do $$ begin create type voucher_qty_type as enum ('unlimited','limited');
exception when duplicate_object then null; end $$;

create table if not exists public.vouchers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text,
  voucher_kind voucher_kind not null default 'normal',
  discount_type text,
  discount_value numeric(12,2),
  valid_from date,
  valid_until date,
  is_active boolean not null default true,
  deleted_at timestamptz
);
-- Idempotent for a database that already has the older shape.
alter table public.vouchers
  add column if not exists code text,
  add column if not exists voucher_kind voucher_kind not null default 'normal',
  add column if not exists valid_from date,
  add column if not exists valid_until date;

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_no text,
  customer_id uuid references public.customers(id),
  status text,
  deleted_at timestamptz
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  table_name text not null,
  record_id uuid,
  action text not null,
  old_data jsonb,
  new_data jsonb,
  changed_by uuid,
  created_at timestamptz not null default now()
);

-- Session-driven identity. Owner by default, so a query written without a role
-- reads everything and a permission test has to opt in to being restricted.
do $$ begin
  execute format('alter database %I set test.role = %L', current_database(), 'owner');
  execute format('alter database %I set test.store_access = %L', current_database(), 'all');
end $$;

create or replace function auth.uid() returns uuid
language sql stable as $fn$
  select nullif(current_setting('test.user_id', true), '')::uuid
$fn$;

create or replace function public.current_user_role() returns text
language sql stable as $fn$
  select nullif(current_setting('test.role', true), '')
$fn$;

create or replace function public.is_manager_or_above() returns boolean
language sql stable as $fn$
  select coalesce(nullif(current_setting('test.role', true), ''), '') in ('owner','admin','manager')
$fn$;

create or replace function public.user_has_store_access(p_store_id uuid) returns boolean
language sql stable as $fn$
  select coalesce(
    current_setting('test.store_access', true) = 'all'
    or p_store_id::text = any (string_to_array(coalesce(current_setting('test.store_access', true), ''), ',')),
    false)
$fn$;

-- --- verbatim from migrations 31 and 72 -------------------------------
create or replace function public.sg_today() returns date
  language sql stable as $$ select (now() at time zone 'Asia/Singapore')::date $$;

create or replace function public.therapy_expiry(p_start date, p_months integer)
returns date language sql immutable as $function$
  select case when p_start is null or coalesce(p_months,0) <= 0 then null
              else (p_start + make_interval(months => p_months) - interval '1 day')::date end
$function$;

-- --- entitlement tables, shaped as migrations 35, 53, 72 and 74 leave them ---
create table if not exists public.unlimited_therapy_packages (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  duration_months integer not null,
  entitlement_kind text default 'unlimited',
  voucher_qty integer,
  voucher_id uuid references public.vouchers(id),
  is_active boolean not null default true
);

create table if not exists public.therapy_package_rules (
  id uuid primary key default gen_random_uuid(),
  store_id uuid references public.stores(id),
  name text not null,
  qualifying_amount numeric(12,2) not null,
  entitlement_kind text not null default 'unlimited'
    check (entitlement_kind in ('unlimited','voucher')),
  duration_months integer,
  voucher_qty integer,
  activation_deadline_days integer not null default 365,
  applies_to text default 'customer',
  is_active boolean not null default true,
  effective_date date not null default (now() at time zone 'Asia/Singapore')::date,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.therapy_entitlements (
  id uuid primary key default gen_random_uuid(),
  entitlement_no text not null unique,
  customer_id uuid not null references public.customers(id),
  store_id uuid references public.stores(id),
  rule_id uuid references public.therapy_package_rules(id),
  package_name text not null,
  entitlement_kind text not null,
  duration_months integer,
  voucher_qty integer,
  qualifying_amount numeric(12,2) not null,
  qualified_value numeric(12,2) not null default 0,
  forfeited_value numeric(12,2) not null default 0,
  earner_kind text default 'customer',
  activation_deadline date,
  activation_date date,
  expiry_date date,
  status text not null default 'pending_activation',
  claimed_by uuid, claimed_at timestamptz,
  created_by uuid, created_at timestamptz not null default now()
);

create table if not exists public.purchased_therapy_entitlements (
  id uuid primary key default gen_random_uuid(),
  entitlement_no text not null unique,
  customer_id uuid not null references public.customers(id),
  store_id uuid references public.stores(id),
  package_id uuid references public.unlimited_therapy_packages(id),
  invoice_id uuid references public.invoices(id),
  package_name text not null,
  duration_months integer not null,
  price_snapshot numeric(12,2) not null default 0,
  purchase_date date not null default (now() at time zone 'Asia/Singapore')::date,
  activation_deadline date,
  scheduled_date date,
  activation_date date,
  expiry_date date,
  status text not null default 'pending_activation'
    check (status in ('pending_activation','scheduled','active','expired','cancelled','refunded')),
  created_by uuid, updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.customer_reward_vouchers (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  voucher_id uuid not null references public.vouchers(id),
  entitlement_id uuid references public.therapy_entitlements(id),
  store_id uuid references public.stores(id),
  quantity integer not null check (quantity > 0),
  status text not null default 'held' check (status in ('held','redeemed','revoked')),
  issued_at timestamptz not null default now(),
  issued_by uuid, redeemed_at timestamptz, notes text
);

create table if not exists public.voucher_redemptions (
  id uuid primary key default gen_random_uuid(),
  voucher_id uuid not null references public.vouchers(id),
  invoice_id uuid references public.invoices(id),
  customer_id uuid references public.customers(id),
  discount_applied numeric(12,2) not null default 0,
  redeemed_by uuid,
  created_at timestamptz not null default now()
);

-- Columns and helpers added by later migrations that the claim path reads.
alter table public.vouchers
  add column if not exists reward_eligible boolean default true,
  add column if not exists qty_type text default 'unlimited';

-- From migration 80: where an issued voucher came from.
alter table public.customer_reward_vouchers
  add column if not exists source_type text,
  add column if not exists source_id uuid;

-- membership_expiry() is deliberately NOT created here.
--
-- Phase 19 dropped it, and migration 72 exists because activate_purchased_therapy
-- was still calling it: "function public.membership_expiry(date, integer) does
-- not exist". That migration replaced the call with therapy_expiry(), so this
-- system has ONE calendar-month convention, not two.
--
-- An earlier version of this fixture created membership_expiry by copying it out
-- of migration 45 — a migration this database never ran. That made the fixture
-- richer than production, the tests passed, and the real database raised the
-- exact error migration 72 was written to fix. A fixture has to mirror what is
-- installed, not what some superseded file says.

create table if not exists public.voucher_store_stock (
  voucher_id uuid not null references public.vouchers(id),
  store_id uuid not null references public.stores(id),
  current_qty integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (voucher_id, store_id)
);

create or replace function public.write_audit_ex(
  p_table text, p_record uuid, p_action text, p_old jsonb, p_new jsonb,
  p_module text default null, p_reason text default null, p_store uuid default null)
returns void language sql as $fn$
  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by)
  values (p_table, p_record, p_action, p_old, p_new, auth.uid())
$fn$;
