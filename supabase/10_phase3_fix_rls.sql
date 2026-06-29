-- =====================================================================
-- ENERGIA — PHASE 3 FIX: customers & affiliates insert RLS
-- Symptom: "new row violates row-level security policy" when adding a
-- customer or affiliate from the app.
--
-- IMPORTANT: `select auth.uid()` is null in the SQL Editor — that's normal
-- (the editor runs as admin, not as a logged-in user). It is NOT the bug.
-- The bug is the INSERT policies. This file rebuilds them cleanly.
--
-- Run this whole file in the Supabase SQL Editor. Safe + idempotent.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Make sure the role helper functions exist and are correct.
--    (If 08_phase3_rls.sql errored because one of these was missing,
--     the policies never got created — which causes the deny.)
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- 1. CUSTOMERS — allow any authenticated user to read/insert/update.
--    Customers are shared reference data used when invoicing, so every
--    signed-in user can add or pick one.
-- ---------------------------------------------------------------------
alter table public.customers enable row level security;

drop policy if exists "authenticated read customers" on public.customers;
drop policy if exists "staff and above manage customers" on public.customers;
drop policy if exists "authenticated insert customers" on public.customers;
drop policy if exists "authenticated update customers" on public.customers;

create policy "authenticated read customers" on public.customers
  for select to authenticated using (deleted_at is null);

create policy "authenticated insert customers" on public.customers
  for insert to authenticated with check (true);

create policy "authenticated update customers" on public.customers
  for update to authenticated using (true) with check (true);

-- ---------------------------------------------------------------------
-- 2. AFFILIATES — Manager and above manage; everyone can read.
--    Uses is_manager_or_above(); the function above guarantees it exists.
-- ---------------------------------------------------------------------
alter table public.affiliates enable row level security;

drop policy if exists "authenticated read affiliates" on public.affiliates;
drop policy if exists "manager above manage affiliates" on public.affiliates;
drop policy if exists "manager insert affiliates" on public.affiliates;
drop policy if exists "manager update affiliates" on public.affiliates;
drop policy if exists "manager delete affiliates" on public.affiliates;

create policy "authenticated read affiliates" on public.affiliates
  for select to authenticated using (deleted_at is null);

create policy "manager insert affiliates" on public.affiliates
  for insert to authenticated with check (public.is_manager_or_above());

create policy "manager update affiliates" on public.affiliates
  for update to authenticated
  using (public.is_manager_or_above()) with check (public.is_manager_or_above());

create policy "manager delete affiliates" on public.affiliates
  for delete to authenticated using (public.is_manager_or_above());

-- =====================================================================
-- 3. DIAGNOSTIC — confirm YOUR profile is set up correctly.
--    Replace the email with your login email and run just this SELECT.
--    role must be one of owner/admin/manager for affiliate inserts,
--    and is_active must be true.
-- =====================================================================
-- select id, full_name, email, role, is_active
-- from public.profiles
-- where email = 'your-email@example.com';

-- If that row shows the wrong role, fix it:
-- update public.profiles set role = 'owner', is_active = true
-- where email = 'your-email@example.com';
