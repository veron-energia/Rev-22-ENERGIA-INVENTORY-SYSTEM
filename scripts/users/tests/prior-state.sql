-- =====================================================================
-- The database as migrations 230 and 231 find it.
--
-- Reduced, and faithful where it matters: the profiles table, the role enum,
-- the store assignments and auth.uid() are the objects the permission matrix is
-- built on, so they are shaped as the installed schema has them rather than
-- restated loosely.
--
-- Deliberate deviations, none of which touch the permission rules:
--   * auth.uid() reads a session setting, so a test can BE a particular user
--     without minting a JWT. Production reads it from the token.
--   * no RLS: this harness connects as the database owner, who bypasses every
--     policy anyway. The guard under test is a trigger, precisely because a
--     trigger runs on paths a policy does not.
--
-- Safe to run repeatedly.
-- =====================================================================

set check_function_bodies = off;

create schema if not exists auth;
do $$ begin
  create type user_role as enum ('owner','admin','manager','inventory_manager','staff');
exception when duplicate_object then null; end $$;

create table if not exists public.stores (
  id uuid primary key default gen_random_uuid(),
  name text not null
);

-- profiles may already exist in this shared database, created by another
-- suite's fixture with fewer columns and a plain-text role. "create table if
-- not exists" would silently do nothing and leave the shape wrong, so the table
-- is RECONCILED to the installed schema instead of assumed.
create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  full_name text not null
);

alter table public.profiles
  add column if not exists email text,
  add column if not exists is_active boolean not null default true,
  add column if not exists work_phone text,
  add column if not exists personal_phone text,
  add column if not exists personal_email text,
  add column if not exists deleted_at timestamptz,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'profiles' and column_name = 'role') then
    alter table public.profiles add column role user_role not null default 'staff';
  elsif (select data_type from information_schema.columns
          where table_schema = 'public' and table_name = 'profiles' and column_name = 'role') <> 'USER-DEFINED' then
    -- Another fixture made it text. Production has the enum, and the permission
    -- matrix is written against the enum, so convert it.
    alter table public.profiles
      alter column role drop default,
      alter column role type user_role using coalesce(nullif(role, ''), 'staff')::user_role,
      alter column role set default 'staff';
    alter table public.profiles alter column role set not null;
  end if;
end $$;

-- Partial: rows another fixture created have no email at all.
create unique index if not exists uq_profiles_email
  on public.profiles (lower(email)) where email is not null;

create table if not exists public.user_store_assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, store_id)
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  table_name text not null, record_id uuid, action text not null,
  old_data jsonb, new_data jsonb, changed_by uuid,
  created_at timestamptz not null default now()
);

-- An affiliate account, so the "this address is already an affiliate" branch is
-- exercised rather than skipped by to_regclass().
create table if not exists public.affiliate_accounts (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  full_name text
);

do $$ begin
  execute format('alter database %I set test.role = %L', current_database(), 'owner');
end $$;

create or replace function auth.uid() returns uuid
language sql stable as $fn$
  select nullif(current_setting('test.user_id', true), '')::uuid
$fn$;

-- The two policy helpers the existing pages use. Shaped as installed.
create or replace function public.is_owner_or_admin() returns boolean
language sql stable security definer set search_path = public as $fn$
  select exists (select 1 from public.profiles
                  where id = auth.uid() and role in ('owner','admin') and is_active = true)
$fn$;

create or replace function public.is_owner_or_manager() returns boolean
language sql stable security definer set search_path = public as $fn$
  select exists (select 1 from public.profiles
                  where id = auth.uid() and role in ('owner','manager') and is_active = true)
$fn$;
