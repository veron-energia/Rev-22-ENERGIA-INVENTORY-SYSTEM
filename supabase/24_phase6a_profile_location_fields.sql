-- =====================================================================
-- ENERGIA — PHASE 6A: Profile fields, Manager store access, location phones
--
-- * Manager gets unconditional store access, same as Owner/Admin.
-- * profiles gains: personal_phone, work_phone, personal_email.
--   The EXISTING `email` column is repurposed in the UI as "Work Email"
--   (it already is the Supabase Auth login email — no schema change
--   needed for that; changing it in-app is DISPLAY ONLY per your
--   decision, and does not touch the Auth login credential).
-- * stores / warehouses gain a `phone` column.
-- * A helper to fetch a Staff user's single assigned store (Section 1),
--   enforced at the app layer: Staff should have exactly one row in
--   user_store_assignments. This does not restrict the underlying table
--   to one row (so existing setups aren't broken), it just gives the
--   app a clean "assigned store" concept to build on.
--
-- Additive + idempotent. Run AFTER 23b_fix_rental_late_timezone.sql.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Manager: unconditional store access (per your decision).
-- ---------------------------------------------------------------------
create or replace function public.user_has_store_access(target_store_id uuid)
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active = true and p.role in ('owner','admin','manager'))
  or exists (select 1 from public.user_store_assignments usa
    join public.profiles p on p.id = usa.user_id
    where usa.user_id = auth.uid() and usa.store_id = target_store_id and p.is_active = true)
$$;

-- ---------------------------------------------------------------------
-- 2. Profile contact fields.
-- ---------------------------------------------------------------------
alter table public.profiles add column if not exists personal_phone text;
alter table public.profiles add column if not exists work_phone text;
alter table public.profiles add column if not exists personal_email text;
-- `email` stays as-is: it is the Work Email (== the Auth login address).

-- ---------------------------------------------------------------------
-- 3. Store / Warehouse phone numbers.
-- ---------------------------------------------------------------------
alter table public.stores add column if not exists phone text;
alter table public.warehouses add column if not exists phone text;

-- ---------------------------------------------------------------------
-- 4. Staff's single assigned store (first/only row in
--    user_store_assignments for that user). Returns null if none or if
--    the user isn't Staff (Owner/Admin/Manager don't have a single
--    "assigned" store — they can use any).
-- ---------------------------------------------------------------------
create or replace function public.my_assigned_store_id()
returns uuid language sql stable security definer set search_path = public as $$
  select usa.store_id
  from public.user_store_assignments usa
  join public.profiles p on p.id = usa.user_id
  where usa.user_id = auth.uid() and p.role = 'staff'
  order by usa.created_at
  limit 1
$$;

notify pgrst, 'reload schema';
