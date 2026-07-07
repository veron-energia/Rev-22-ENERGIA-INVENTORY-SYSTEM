-- =====================================================================
-- ENERGIA — PHASE 6B: Customer profile changes
--
-- * Adds date_of_birth (optional), gender + gender_other (Male/Female/
--   Other-with-free-text), and occupation (optional) to customers.
-- * The `address` column is NO LONGER collected in the app (removed from
--   the customer form). It is kept in the database (nullable) so existing
--   address data is preserved — nothing is deleted. If you later want it
--   permanently dropped, that's a separate explicit step.
-- * Phone stays unique (unchanged).
--
-- Additive + idempotent. Run AFTER 24_phase6a_profile_location_fields.sql.
-- =====================================================================

set check_function_bodies = off;

do $$ begin
  create type customer_gender as enum ('male','female','other');
exception when duplicate_object then null; end $$;

alter table public.customers add column if not exists date_of_birth date;
alter table public.customers add column if not exists gender customer_gender;
alter table public.customers add column if not exists gender_other text;
alter table public.customers add column if not exists occupation text;

notify pgrst, 'reload schema';
