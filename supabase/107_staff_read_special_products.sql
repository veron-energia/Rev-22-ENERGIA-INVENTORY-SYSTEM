-- =====================================================================
-- ENERGIA — FIX: STAFF COULD NOT SEE THE SPECIAL PRODUCT CATALOGUE
--
-- Migration 106 let anyone put a Special Product or Rental on an invoice, but
-- the only policy on special_products was:
--
--     create policy "manage special products" on public.special_products
--       for all to authenticated using (public.is_owner_or_manager());
--
-- That was correct while the Special & Rentals page was Owner/Manager-only. Now
-- that staff sell these from the Invoices page, it left their picker EMPTY —
-- the dropdown returned no rows, so there was nothing to choose.
--
-- Read access is opened to any signed-in user; MANAGING the catalogue (adding,
-- editing, pricing, deleting) stays Owner/Manager-only. Stock levels are
-- likewise readable, so a staff member can see what exists, while every write
-- still goes through the vetted functions.
--
-- Additive and idempotent. Run AFTER 106.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. The catch-all ALL policy is split: read for everyone signed in, write
--    for an Owner or Manager only.
-- ---------------------------------------------------------------------
drop policy if exists "manage special products" on public.special_products;

do $$ begin
  drop policy if exists "read special products" on public.special_products;
  create policy "read special products" on public.special_products
    for select to authenticated using (true);

  -- Writes remain restricted. Split by command rather than left as ALL, so a
  -- future reader can see at a glance that only reading was widened.
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='special_products' and policyname='insert special products') then
    create policy "insert special products" on public.special_products
      for insert to authenticated with check (public.is_owner_or_manager());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='special_products' and policyname='update special products') then
    create policy "update special products" on public.special_products
      for update to authenticated
      using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='special_products' and policyname='delete special products') then
    create policy "delete special products" on public.special_products
      for delete to authenticated using (public.is_owner_or_manager());
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Stock levels: readable, so staff can see what exists. Every movement
--    still happens through fulfil_special_doc() and the other functions.
-- ---------------------------------------------------------------------
-- A read policy of this name may already exist with an Owner/Manager
-- condition, so it is DROPPED and recreated rather than skipped by an
-- "if not exists" that would silently leave staff unable to see stock.
drop policy if exists "manage special stock" on public.special_product_stock;
drop policy if exists "read special stock" on public.special_product_stock;
create policy "read special stock" on public.special_product_stock
  for select to authenticated using (true);

-- ---------------------------------------------------------------------
-- 3. Staff must be able to see their own store's sales and rentals, since they
--    now raise them. Reading only — no direct writes, in keeping with
--    migration 105.
-- ---------------------------------------------------------------------
drop policy if exists "read special sales" on public.special_sales;
create policy "read special sales" on public.special_sales
  for select to authenticated using (true);

drop policy if exists "read rentals" on public.rentals;
create policy "read rentals" on public.rentals
  for select to authenticated using (true);

notify pgrst, 'reload schema';
