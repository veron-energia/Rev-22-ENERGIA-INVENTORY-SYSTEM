-- =====================================================================
-- ENERGIA — PHASE 6E-2: Per-store invoice fields, GST, image storage
--
-- Adds per-store fields shown on the printed invoice:
--   email, website, co_reg_no, paynow_uen, bank_account,
--   gst_enabled (default false) + gst_rate (percent, default 9),
--   and image URLs: company_logo_url, store_logo_url,
--   qr_paynow_url, qr_grabpay_url, qr_atome_url.
-- Images are uploaded to a public Storage bucket 'store-assets'; only the
-- resulting public URL is stored on the store row.
--
-- Additive + idempotent. Run AFTER 29_phase6d_staff_transfer.sql.
-- =====================================================================

set check_function_bodies = off;

alter table public.stores add column if not exists email text;
alter table public.stores add column if not exists website text;
alter table public.stores add column if not exists co_reg_no text;
alter table public.stores add column if not exists paynow_uen text;
alter table public.stores add column if not exists bank_account text;
alter table public.stores add column if not exists gst_enabled boolean not null default false;
alter table public.stores add column if not exists gst_rate numeric(6,3) not null default 9.0;
alter table public.stores add column if not exists company_logo_url text;
alter table public.stores add column if not exists store_logo_url text;
alter table public.stores add column if not exists qr_paynow_url text;
alter table public.stores add column if not exists qr_grabpay_url text;
alter table public.stores add column if not exists qr_atome_url text;

-- ---------------------------------------------------------------------
-- Public storage bucket for store logos + QR images.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('store-assets', 'store-assets', true)
on conflict (id) do update set public = true;

-- Anyone can READ (bucket is public, needed so <img> works on the printout).
drop policy if exists "store-assets read" on storage.objects;
create policy "store-assets read" on storage.objects for select
  using (bucket_id = 'store-assets');

-- Only Owner/Manager can upload / change / remove store assets.
drop policy if exists "store-assets write" on storage.objects;
create policy "store-assets write" on storage.objects for insert to authenticated
  with check (bucket_id = 'store-assets' and public.is_owner_or_manager());
drop policy if exists "store-assets update" on storage.objects;
create policy "store-assets update" on storage.objects for update to authenticated
  using (bucket_id = 'store-assets' and public.is_owner_or_manager());
drop policy if exists "store-assets delete" on storage.objects;
create policy "store-assets delete" on storage.objects for delete to authenticated
  using (bucket_id = 'store-assets' and public.is_owner_or_manager());

notify pgrst, 'reload schema';
