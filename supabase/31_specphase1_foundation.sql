-- =====================================================================
-- ENERGIA — NEW SPEC PHASE 1: Foundation (audit, dropdowns, permissions)
--
-- Scope (agreed): extend audit_logs in place; add brands / categories /
-- suppliers dropdown tables + product link tables; add the important-
-- product flag; tighten a couple of permissions. Later phases add their
-- own tables (exchanges, therapy, surveys, affiliate registration).
--
-- Non-destructive & idempotent. All timestamps use Singapore time via the
-- sg_now() helper. Run AFTER 30_phase6e2_store_invoice_fields.sql.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 0. Singapore-time helper (used across all new phases).
-- ---------------------------------------------------------------------
create or replace function public.sg_now() returns timestamptz
  language sql stable as $$ select now() $$;   -- stored as UTC; display in SGT
create or replace function public.sg_today() returns date
  language sql stable as $$ select (now() at time zone 'Asia/Singapore')::date $$;

-- ---------------------------------------------------------------------
-- 1. Audit log extension (add columns; keep existing rows/values).
--    role / module / reason / store / ip / device — all nullable so the
--    176 existing write_audit() calls keep working unchanged.
-- ---------------------------------------------------------------------
alter table public.audit_logs add column if not exists actor_role text;
alter table public.audit_logs add column if not exists module text;
alter table public.audit_logs add column if not exists reason text;
alter table public.audit_logs add column if not exists store_id uuid references public.stores(id);
alter table public.audit_logs add column if not exists ip_address text;
alter table public.audit_logs add column if not exists device_info text;

-- Backward-compatible 5-arg version: fills actor_role automatically.
create or replace function public.write_audit(
  p_table text, p_record uuid, p_action text, p_old jsonb, p_new jsonb
) returns void language sql security definer set search_path = public as $$
  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by, actor_role)
  values (p_table, p_record, p_action, p_old, p_new, auth.uid(), public.current_user_role()::text);
$$;

-- Rich version for new phases: adds module / reason / store / ip / device.
create or replace function public.write_audit_ex(
  p_table text, p_record uuid, p_action text, p_old jsonb, p_new jsonb,
  p_module text default null, p_reason text default null, p_store uuid default null,
  p_ip text default null, p_device text default null
) returns void language sql security definer set search_path = public as $$
  insert into public.audit_logs
    (table_name, record_id, action, old_data, new_data, changed_by, actor_role, module, reason, store_id, ip_address, device_info)
  values (p_table, p_record, p_action, p_old, p_new, auth.uid(), public.current_user_role()::text,
          p_module, p_reason, p_store, p_ip, p_device);
$$;

-- ---------------------------------------------------------------------
-- 2. Important-product flag (Phase 2 UI uses it; column lives here).
-- ---------------------------------------------------------------------
alter table public.products add column if not exists is_important boolean not null default false;

-- ---------------------------------------------------------------------
-- 3. Dropdown/config tables: brands, categories, suppliers.
--    One brand per product; many categories/suppliers per product.
-- ---------------------------------------------------------------------
create table if not exists public.brands (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact_person text,
  phone text,
  email text,
  address text,
  notes text,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Product links. brand is one-per-product (FK on products); categories and
-- suppliers are many-per-product (join tables).
alter table public.products add column if not exists brand_id uuid references public.brands(id);

create table if not exists public.product_categories (
  product_id uuid not null references public.products(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete restrict,
  primary key (product_id, category_id)
);

create table if not exists public.product_suppliers (
  product_id uuid not null references public.products(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  primary key (product_id, supplier_id)
);

-- ---------------------------------------------------------------------
-- 4. RLS: everyone authenticated can READ dropdowns; only Owner/Manager
--    may write (add/edit/deactivate/soft-delete/restore).
-- ---------------------------------------------------------------------
do $$ declare t text;
begin
  foreach t in array array['brands','categories','suppliers','product_categories','product_suppliers']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "%s read" on public.%I', t, t);
    execute format('create policy "%s read" on public.%I for select to authenticated using (true)', t, t);
    execute format('drop policy if exists "%s write" on public.%I', t, t);
    execute format('create policy "%s write" on public.%I for all to authenticated using (public.is_owner_or_manager()) with check (public.is_owner_or_manager())', t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 5. Guard: block deleting a brand/category/supplier still used by a
--    product (spec 2.3). Soft-delete (is_active=false / deleted_at) is
--    always allowed; hard delete is blocked while referenced.
-- ---------------------------------------------------------------------
create or replace function public.guard_brand_delete() returns trigger
  language plpgsql as $$
begin
  if exists (select 1 from public.products where brand_id = old.id and deleted_at is null) then
    raise exception 'Cannot delete brand "%": it is still used by one or more products. Deactivate it instead.', old.name;
  end if;
  return old;
end $$;
drop trigger if exists trg_guard_brand_delete on public.brands;
create trigger trg_guard_brand_delete before delete on public.brands
  for each row execute function public.guard_brand_delete();

create or replace function public.guard_category_delete() returns trigger
  language plpgsql as $$
begin
  if exists (select 1 from public.product_categories where category_id = old.id) then
    raise exception 'Cannot delete category "%": it is still used by one or more products. Deactivate it instead.', old.name;
  end if;
  return old;
end $$;
drop trigger if exists trg_guard_category_delete on public.categories;
create trigger trg_guard_category_delete before delete on public.categories
  for each row execute function public.guard_category_delete();

create or replace function public.guard_supplier_delete() returns trigger
  language plpgsql as $$
begin
  if exists (select 1 from public.product_suppliers where supplier_id = old.id) then
    raise exception 'Cannot delete supplier "%": it is still used by one or more products. Deactivate it instead.', old.name;
  end if;
  return old;
end $$;
drop trigger if exists trg_guard_supplier_delete on public.suppliers;
create trigger trg_guard_supplier_delete before delete on public.suppliers
  for each row execute function public.guard_supplier_delete();

-- ---------------------------------------------------------------------
-- 6. Toggle important-product (Owner/Manager only, audited). Phase 2 UI
--    calls this rather than updating the column directly.
-- ---------------------------------------------------------------------
create or replace function public.set_product_important(p_product_id uuid, p_important boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only Owner or Manager can mark products as important'; end if;
  update public.products set is_important = p_important, updated_at = now() where id = p_product_id;
  perform public.write_audit_ex('products', p_product_id,
    case when p_important then 'product_marked_important' else 'product_unmarked_important' end,
    null, jsonb_build_object('is_important', p_important), 'products');
end $$;

notify pgrst, 'reload schema';
