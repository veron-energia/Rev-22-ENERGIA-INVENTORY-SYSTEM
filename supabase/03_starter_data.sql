-- =====================================================================
-- ENERGIA INVENTORY SYSTEM — STARTER DATA
-- Run this THIRD, AFTER creating the first Owner user in
-- Supabase Dashboard → Authentication → Users → Add user.
-- Replace the placeholders before running.
-- =====================================================================

-- 1. Create the first Owner profile.
--    Paste the Auth user UUID from Authentication → Users.
insert into public.profiles (id, full_name, email, role)
values (
  'PASTE-YOUR-AUTH-USER-ID-HERE',
  'Shin Thant Aung',
  'your-email@example.com',
  'owner'
);

-- 2. First warehouse and store.
insert into public.warehouses (name, code, address)
values ('Main Warehouse', 'WH-MAIN', 'Singapore');

insert into public.stores (name, code, address)
values ('Energia Rev22 (Adelphi)', 'STORE-ADELPHI', '1 Coleman St, B1-37 The Adelphi, Singapore 179803');

-- 3. Payment methods.
insert into public.payment_methods (name) values
  ('Cash'), ('PayNow'), ('Bank Transfer'), ('Credit Card'), ('GrabPay');

-- 4. (Optional) A couple of sample products to verify the Products page.
insert into public.products (name, sku, product_type, category, brand, uom, default_cost_price)
values
  ('Energia Wellness Corset 3.0', 'EN-CORSET-3', 'own', 'Wellness', 'Energia', 'pcs', 40.00),
  ('Socks Black', 'TP-SOCKS-BLK', 'third_party', 'Apparel', 'Generic', 'pcs', 5.00);
