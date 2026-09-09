-- =====================================================================
-- The database as migrations 240-243 find it.
--
-- Reduced, and faithful where it decides something: the commission functions
-- below are copied VERBATIM from migrations 79 and 80, because the whole point
-- of the commission test is what the installed code actually does with a
-- classification. Paraphrasing them would test my paraphrase.
--
-- Deliberate deviations, none of which touch the rules under test:
--   * no RLS — this harness connects as the database owner, who bypasses it;
--   * auth.uid() and the role helpers read session settings, so a test can be
--     an owner or a cashier without minting a JWT;
--   * tables carry the columns these migrations read and nothing else.
--
-- Shared database: other suites own their own tables here, so this file only
-- creates and reconciles what it needs.
--
-- Safe to run repeatedly.
-- =====================================================================

set check_function_bodies = off;

create schema if not exists auth;
do $$ begin create type user_role as enum ('owner','admin','manager','inventory_manager','staff');
exception when duplicate_object then null; end $$;
do $$ begin create type product_type as enum ('own','third_party','no_commission');
exception when duplicate_object then null; end $$;
do $$ begin create type commission_tier as enum ('tier1','tier2');
exception when duplicate_object then null; end $$;
do $$ begin create type commission_status as enum ('earned','pending','blocked','reversed','paid');
exception when duplicate_object then null; end $$;
do $$ begin create type voucher_kind as enum ('normal','fixed_discount','percentage_discount');
exception when duplicate_object then null; end $$;
do $$ begin create type voucher_qty_type as enum ('unlimited','limited');
exception when duplicate_object then null; end $$;

create table if not exists public.stores (
  id uuid primary key default gen_random_uuid(), name text not null);

-- customers and invoices already exist in this shared database, created by
-- another suite's fixture with fewer columns. "create table if not exists"
-- would silently do nothing and leave the shape wrong, so they are RECONCILED.
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null, phone text not null);
alter table public.customers
  add column if not exists referred_by uuid references public.customers(id),
  add column if not exists email text,
  add column if not exists is_active boolean not null default true,
  add column if not exists deleted_at timestamptz,
  add column if not exists created_at timestamptz not null default now();

create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(), full_name text not null);
alter table public.profiles
  add column if not exists role user_role not null default 'staff',
  add column if not exists is_active boolean not null default true,
  add column if not exists email text,
  add column if not exists deleted_at timestamptz;

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_no text, customer_id uuid references public.customers(id));
alter table public.invoices
  add column if not exists store_id uuid references public.stores(id),
  add column if not exists affiliate_id uuid,
  add column if not exists affiliate_selection_explicit boolean not null default false,
  add column if not exists status text,
  add column if not exists paid_at timestamptz,
  add column if not exists deleted_at timestamptz;

create table if not exists public.customer_affiliates (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id));

-- The customer columns carry no foreign key here, and production does.
--
-- This database is shared with other suites, and one of them clears customers
-- as part of its own setup. A real FK from commissions would make that delete
-- fail and break a neighbouring suite that has nothing to do with commission.
-- The columns and every value are the same; only the constraint is absent, and
-- nothing under test depends on it.
create table if not exists public.commissions (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  invoice_item_id uuid,
  buyer_customer_id uuid not null,
  referrer_customer_id uuid not null,
  tier commission_tier not null,
  product_type text,
  line_amount numeric(12,2) not null default 0,
  rate numeric(6,3) not null default 0,
  commission_amount numeric(12,2) not null default 0,
  status commission_status not null default 'earned',
  payout_id uuid, invoice_paid_date date, block_reason text,
  created_at timestamptz not null default now());

-- app_settings is a single-row table keyed by a boolean primary key.
create table if not exists public.app_settings (id boolean primary key default true check (id));
alter table public.app_settings
  add column if not exists commission_tier1_own_rate   numeric not null default 15,
  add column if not exists commission_tier1_third_rate numeric not null default 4.5,
  add column if not exists commission_tier2_own_rate   numeric not null default 5,
  add column if not exists commission_tier2_third_rate numeric not null default 5;
insert into public.app_settings (id) values (true) on conflict do nothing;

create table if not exists public.credit_packages (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  customer_price numeric(12,2) not null default 0,
  paid_credit_amount numeric(12,2) not null default 0,
  is_active boolean not null default true,
  commission_classification text not null default 'own'
    check (commission_classification in ('own','third_party')),
  tier1_rate numeric(6,3), tier2_rate numeric(6,3),
  staff_commission_rate numeric(6,3),
  deleted_at timestamptz);

create table if not exists public.premium_bundles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  customer_price numeric(12,2) not null default 0,
  paid_credit_amount numeric(12,2) not null default 0,
  bonus_credit_amount numeric(12,2) not null default 0,
  is_active boolean not null default true,
  commission_classification text not null default 'third_party'
    check (commission_classification in ('own','third_party')),
  tier1_rate numeric(6,3), tier2_rate numeric(6,3),
  staff_commission_rate numeric(6,3),
  deleted_at timestamptz);

create table if not exists public.credit_package_sales (
  id uuid primary key default gen_random_uuid(),
  package_id uuid references public.credit_packages(id),
  customer_id uuid not null,
  store_id uuid references public.stores(id),
  invoice_id uuid references public.invoices(id),
  plan_name_snapshot text, price_snapshot numeric(12,2),
  paid_credit_snapshot numeric(12,2),
  classification_snapshot text,
  tier1_rate_snapshot numeric(6,3), tier2_rate_snapshot numeric(6,3),
  staff_rate_snapshot numeric(6,3),
  external_paid numeric(12,2) not null default 0,
  created_at timestamptz not null default now());

create table if not exists public.premium_bundle_sales (
  id uuid primary key default gen_random_uuid(),
  bundle_id uuid references public.premium_bundles(id),
  customer_id uuid not null,
  store_id uuid references public.stores(id),
  invoice_id uuid references public.invoices(id),
  bundle_name_snapshot text, price_snapshot numeric(12,2),
  classification_snapshot text,
  tier1_rate_snapshot numeric(6,3), tier2_rate_snapshot numeric(6,3),
  external_paid numeric(12,2) not null default 0,
  created_at timestamptz not null default now());

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  table_name text not null, record_id uuid, action text not null,
  old_data jsonb, new_data jsonb, changed_by uuid,
  created_at timestamptz not null default now());
-- Reconciled, like the other shared tables: another suite creates audit_logs
-- too, and "create table if not exists" would leave its shape in place.
alter table public.audit_logs
  add column if not exists old_data jsonb,
  add column if not exists new_data jsonb,
  add column if not exists changed_by uuid,
  add column if not exists created_at timestamptz not null default now();

do $$ begin
  execute format('alter database %I set test.role = %L', current_database(), 'owner');
end $$;

create or replace function auth.uid() returns uuid language sql stable as $fn$
  select nullif(current_setting('test.user_id', true), '')::uuid $fn$;

create or replace function public.is_manager_or_above() returns boolean
language sql stable as $fn$
  select coalesce(nullif(current_setting('test.role', true), ''), '') in ('owner','admin','manager') $fn$;

create or replace function public.sg_today() returns date
  language sql stable as $fn$ select (now() at time zone 'Asia/Singapore')::date $fn$;

create or replace function public.write_audit(p_table text, p_record uuid, p_action text,
  p_old jsonb default null, p_new jsonb default null)
returns void language sql as $fn$
  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by)
  values (p_table, p_record, p_action, p_old, p_new, auth.uid()) $fn$;

-- --- verbatim from migrations 79 and 80 -------------------------------
create or replace function public.earn_credit_package_commission(p_sale_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  s public.credit_package_sales%rowtype;
  v_inv public.invoices%rowtype;
  v_t1 uuid; v_t2 uuid; v_base numeric;
  v_r1 numeric; v_r2 numeric; v_a1 numeric; v_a2 numeric;
  v_ptype text;
begin
  select * into s from public.credit_package_sales where id = p_sale_id;
  if not found then raise exception 'Package sale not found'; end if;

  -- Basis: the money actually received, never the credit or free reward.
  v_base := round(coalesce(s.external_paid,0), 2);
  if v_base <= 0 then
    return jsonb_build_object('skipped', true, 'reason', 'no external payment');
  end if;
  -- Commission is always recorded against an invoice, so a sale booked without
  -- one earns nothing until it is invoiced.
  if s.invoice_id is null then
    return jsonb_build_object('skipped', true, 'reason', 'no invoice');
  end if;

  if s.invoice_id is not null then
    select * into v_inv from public.invoices where id = s.invoice_id;
  end if;

  if v_inv.affiliate_id is not null then
    select a.customer_id into v_t1 from public.customer_affiliates a where a.id = v_inv.affiliate_id;
  else
    select c.referred_by into v_t1 from public.customers c where c.id = s.customer_id;
  end if;
  if v_t1 is null or v_t1 = s.customer_id then
    return jsonb_build_object('skipped', true, 'reason', 'no eligible referrer');
  end if;
  select c.referred_by into v_t2 from public.customers c where c.id = v_t1;

  v_ptype := coalesce(s.classification_snapshot, 'own');
  select coalesce(s.tier1_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier1_third_rate
                else commission_tier1_own_rate end),
         coalesce(s.tier2_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier2_third_rate
                else commission_tier2_own_rate end)
    into v_r1, v_r2 from public.app_settings where id = true;

  v_a1 := round(v_base * v_r1 / 100.0, 2);
  if v_a1 > 0 then
    insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
      tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      'earned', public.sg_today());
    if v_t2 is not null then
      v_a2 := round(v_a1 * v_r2 / 100.0, 2);
      if v_a2 > 0 then
        insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
          tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
        values (s.invoice_id, s.customer_id, v_t2, 'tier2', v_ptype, v_a1, v_r2, v_a2,
          'earned', public.sg_today());
      end if;
    end if;
  end if;

  return jsonb_build_object('basis', v_base, 'tier1', v_a1, 'tier2', coalesce(v_a2,0),
    'tier1_rate', v_r1, 'tier2_rate', v_r2);
end $function$;

create or replace function public.earn_premium_bundle_commission(p_sale_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  s public.premium_bundle_sales%rowtype;
  v_inv public.invoices%rowtype;
  v_t1 uuid; v_t2 uuid; v_base numeric; v_ptype text;
  v_r1 numeric; v_r2 numeric; v_a1 numeric; v_a2 numeric;
begin
  select * into s from public.premium_bundle_sales where id = p_sale_id;
  if not found then raise exception 'Bundle sale not found'; end if;

  -- Only external money after discount and FOC. Never bonus credit, free
  -- voucher value, or any later redemption.
  v_base := round(coalesce(s.external_paid,0), 2);
  if v_base <= 0 then return jsonb_build_object('skipped', true, 'reason', 'no external payment'); end if;
  if s.invoice_id is null then return jsonb_build_object('skipped', true, 'reason', 'no invoice'); end if;

  select * into v_inv from public.invoices where id = s.invoice_id;
  if v_inv.affiliate_id is not null then
    select a.customer_id into v_t1 from public.customer_affiliates a where a.id = v_inv.affiliate_id;
  else
    select c.referred_by into v_t1 from public.customers c where c.id = s.customer_id;
  end if;
  if v_t1 is null or v_t1 = s.customer_id then
    return jsonb_build_object('skipped', true, 'reason', 'no eligible referrer'); end if;
  select c.referred_by into v_t2 from public.customers c where c.id = v_t1;

  v_ptype := coalesce(s.classification_snapshot, 'third_party');
  select coalesce(s.tier1_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier1_third_rate
                else commission_tier1_own_rate end),
         coalesce(s.tier2_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier2_third_rate
                else commission_tier2_own_rate end)
    into v_r1, v_r2 from public.app_settings where id = true;

  v_a1 := round(v_base * v_r1 / 100.0, 2);
  if v_a1 > 0 then
    insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
      tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      'earned', public.sg_today());
    if v_t2 is not null then
      v_a2 := round(v_a1 * v_r2 / 100.0, 2);
      if v_a2 > 0 then
        insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
          tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
        values (s.invoice_id, s.customer_id, v_t2, 'tier2', v_ptype, v_a1, v_r2, v_a2,
          'earned', public.sg_today());
      end if;
    end if;
  end if;

  return jsonb_build_object('basis', v_base, 'classification', v_ptype,
    'tier1_rate', v_r1, 'tier2_rate', v_r2, 'tier1', v_a1, 'tier2', coalesce(v_a2,0));
end $function$;

-- --- the credit and invoice-line tables the spending rules act on -----
do $$ begin create type invoice_line_kind as enum
  ('product','voucher','promotion','therapy','credit_package','premium_bundle');
exception when duplicate_object then null; end $$;

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null, product_type product_type not null default 'own',
  deleted_at timestamptz);

create table if not exists public.vouchers (
  id uuid primary key default gen_random_uuid(), name text not null);
alter table public.vouchers
  add column if not exists voucher_kind voucher_kind not null default 'normal',
  add column if not exists selling_price numeric(12,2) default 0,
  add column if not exists deleted_at timestamptz;
alter table public.vouchers
  add column if not exists code text not null default '',
  add column if not exists is_active boolean not null default true,
  -- Used by the sibling therapy suite. Present here so that whichever fixture
  -- runs first, the shape is the same: "create table if not exists" does
  -- nothing against a table that already exists, so a reduced shape created
  -- here would silently deprive that suite of its columns.
  add column if not exists discount_type text,
  add column if not exists discount_value numeric(12,2);

-- Issued reward vouchers, verbatim in shape from migrations 74 and 80. The
-- customer FK is omitted for the same reason as the credit tables above: a
-- sibling suite sharing this database clears public.customers.
create table if not exists public.customer_reward_vouchers (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null,
  voucher_id uuid not null references public.vouchers(id),
  entitlement_id uuid,
  store_id uuid references public.stores(id),
  quantity integer not null check (quantity > 0),
  status text not null default 'held' check (status in ('held','redeemed','revoked')),
  issued_at timestamptz not null default now(),
  issued_by uuid references public.profiles(id),
  redeemed_at timestamptz,
  source_type text,
  source_id uuid,
  notes text);
alter table public.customer_reward_vouchers
  add column if not exists entitlement_id uuid,
  add column if not exists source_type text,
  add column if not exists source_id uuid,
  add column if not exists redeemed_at timestamptz,
  add column if not exists notes text;

create table if not exists public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  line_kind invoice_line_kind not null default 'product',
  product_id uuid references public.products(id),
  voucher_id uuid references public.vouchers(id),
  promotion_id uuid,
  quantity integer not null default 1,
  unit_price numeric(12,2) not null default 0,
  line_total numeric(12,2) not null default 0,
  line_discount numeric(12,2) not null default 0,
  price_mode text);

-- --- what create_invoice needs to write a line -----------------------
alter table public.invoice_items
  add column if not exists therapy_package_id uuid,
  add column if not exists price_source text,
  add column if not exists price_source_id uuid,
  add column if not exists store_id_snapshot uuid,
  add column if not exists original_price numeric(12,2),
  add column if not exists plan_name_snapshot text,
  add column if not exists plan_months_snapshot integer,
  add column if not exists price_overridden boolean not null default false,
  add column if not exists override_reason text,
  add column if not exists override_by uuid,
  add column if not exists override_at timestamptz,
  add column if not exists foc_quantity integer not null default 0,
  add column if not exists is_foc boolean not null default false,
  add column if not exists foc_amount numeric(12,2) not null default 0,
  add column if not exists foc_original_unit_price numeric(12,2),
  add column if not exists foc_reason_id uuid,
  add column if not exists foc_reason text,
  add column if not exists foc_by uuid,
  add column if not exists foc_at timestamptz;

-- These two are shared with the therapy suite, whichever runs first. Creating
-- them with a REDUCED shape is what broke that suite: its own fixture uses
-- "create table if not exists", which does nothing against a table that already
-- exists, so its columns never appeared. The full shape is reproduced here, and
-- the alters reconcile the other direction.
create table if not exists public.unlimited_therapy_packages (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  duration_months integer not null default 6,
  entitlement_kind text default 'unlimited',
  voucher_qty integer,
  voucher_id uuid references public.vouchers(id),
  is_active boolean not null default true
);
alter table public.unlimited_therapy_packages
  add column if not exists duration_months integer not null default 6,
  add column if not exists entitlement_kind text default 'unlimited',
  add column if not exists voucher_qty integer,
  add column if not exists is_active boolean not null default true,
  add column if not exists deleted_at timestamptz;

create table if not exists public.purchased_therapy_entitlements (
  id uuid primary key default gen_random_uuid(),
  entitlement_no text not null unique,
  customer_id uuid not null,
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
-- Added nullable: a sibling may have created the table already and filled it,
-- and a NOT NULL column cannot be added to a table that has rows.
alter table public.purchased_therapy_entitlements
  add column if not exists entitlement_no text,
  add column if not exists store_id uuid,
  add column if not exists package_id uuid,
  add column if not exists invoice_id uuid,
  add column if not exists package_name text,
  add column if not exists duration_months integer,
  add column if not exists price_snapshot numeric(12,2) default 0,
  add column if not exists purchase_date date,
  add column if not exists activation_deadline date,
  add column if not exists scheduled_date date,
  add column if not exists activation_date date,
  add column if not exists expiry_date date,
  add column if not exists status text not null default 'pending_activation';

-- Store access, driven by a session setting so a test can be a user with
-- access to one store and not another. Production reads user_store_assignments;
-- the answer is what migration 245 depends on, not where it came from.
--
-- Created only if absent. A sibling suite in this shared database defines an
-- equivalent one with a different parameter name, and "create or replace"
-- cannot rename a parameter — nor should this file quietly take over a function
-- another suite depends on.
do $$ begin
  if to_regprocedure('public.user_has_store_access(uuid)') is null then
    execute $fn$
      create function public.user_has_store_access(p_store_id uuid)
      returns boolean language sql stable as $body$
        select coalesce(
          current_setting('test.store_access', true) = 'all'
          or p_store_id::text = any (string_to_array(
               coalesce(current_setting('test.store_access', true), ''), ',')),
          false)
      $body$;
    $fn$;
  end if;
end $$;

-- 222's detail, reduced to the envelope migration 245 composes with. The point
-- under test is that 245 adds to it without rewriting it, so only the shape
-- matters here. Created only if absent, for the same reason as above.
do $$ begin
  if to_regprocedure('public.therapy_customer_detail(uuid)') is null then
    execute $fn$
      create function public.therapy_customer_detail(p_customer_id uuid)
      returns jsonb language sql stable as $body$
        select jsonb_build_object(
          'customer', (select jsonb_build_object('id', c.id, 'name', c.full_name)
                         from public.customers c where c.id = p_customer_id),
          'as_of', public.sg_today(),
          'vouchers', '[]'::jsonb,
          'unlimited', '[]'::jsonb)
      $body$;
    $fn$;
  end if;
end $$;

create or replace function public.therapy_price_for(
  p_store_id uuid, p_package_id uuid, p_use_member boolean)
returns jsonb language sql stable as $fn$
  select jsonb_build_object('has_price', true, 'price', 1200,
                            'member_price', 1200, 'non_member_price', 1200) $fn$;

create or replace function public.write_audit_ex(p_table text, p_record uuid, p_action text,
  p_old jsonb, p_new jsonb, p_area text default null, p_extra jsonb default null,
  p_store uuid default null)
returns void language sql security definer set search_path to 'public' as $fn$
  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by)
  values (p_table, p_record, p_action, p_old, p_new, auth.uid()) $fn$;

-- --- create_invoice, in TWO overloads ---------------------------------
--
-- Production has more than one. Successive migrations added arguments, and
-- "create or replace" with a new argument list creates a NEW function rather
-- than replacing the old one, so the six-argument version from migration 09
-- still exists beside the current one.
--
-- Both are reproduced because migration 244 has to choose between them. The
-- older one has no therapy branch at all and must be left alone; picking by
-- position instead of by content patches it and leaves the live one untouched,
-- which looks like success and changes nothing.
create or replace function public.create_invoice(
  p_store_id uuid, p_customer_id uuid, p_affiliate_id uuid,
  p_items jsonb, p_discount_total numeric default 0, p_notes text default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_invoice_id uuid;
begin
  -- The pre-therapy shape, kept only so something exists to be left alone.
  insert into public.invoices (invoice_no, customer_id, store_id, status)
  values ('OLD-' || substr(gen_random_uuid()::text, 1, 8), p_customer_id, p_store_id, 'unpaid')
  returning id into v_invoice_id;
  return v_invoice_id;
end $function$;

-- --- create_invoice ---------------------------------------------------
--
-- NOT the production function. Production's is some 800 lines and belongs to
-- the invoice work being done in parallel; copying it here would create a second
-- copy to keep in step with, which is the failure this fixture exists to avoid.
--
-- What matters for migration 244 is reproduced EXACTLY: the two therapy branches
-- it anchors on, character for character from migration 61, and the surrounding
-- variables and per-line arithmetic they depend on. A companion assertion in
-- database.mjs checks those same two anchors still appear verbatim in
-- supabase/61_phase12_foc.sql, so this stub drifting from production is caught
-- rather than assumed away.
create or replace function public.create_invoice(
  p_store_id uuid, p_customer_id uuid, p_items jsonb)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare
  v_invoice_id uuid; v_item jsonb; v_kind text; v_qty integer;
  v_price numeric; v_gross numeric; v_line_total numeric; v_subtotal numeric := 0;
  v_foc_qty integer := 0; v_foc_amt numeric := 0; v_foc_rid uuid; v_foc_resolved text;
  v_mode text := 'non_member'; v_mode_ovr text; v_ovr_reason text;
  v_use_member boolean := false; v_pj jsonb; v_therapy_pkg uuid;
  v_therapy_name text; v_therapy_months integer; v_product_id uuid;
begin
  insert into public.invoices (invoice_no, customer_id, store_id, status)
  values ('INV-' || substr(gen_random_uuid()::text, 1, 8), p_customer_id, p_store_id, 'unpaid')
  returning id into v_invoice_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_kind := coalesce(v_item->>'line_kind', 'product');
    v_qty := greatest(coalesce((v_item->>'quantity')::integer, 1), 1);
    v_foc_qty := coalesce((v_item->>'foc_quantity')::integer, 0);

    if v_kind = 'nothing' then
      null;

    elsif v_kind = 'therapy' then
      if v_qty <> 1 then raise exception 'A therapy line must have quantity 1'; end if;
      v_therapy_pkg := (v_item->>'therapy_package_id')::uuid;
      perform 1 from public.unlimited_therapy_packages where id = v_therapy_pkg and is_active = true and deleted_at is null;
      if not found then raise exception 'Therapy package not found or inactive'; end if;
      if exists (select 1 from public.purchased_therapy_entitlements
                  where customer_id = p_customer_id and package_id = v_therapy_pkg
                    and status in ('active','scheduled','pending_activation')) then
        raise exception 'This customer already has a current entitlement for this therapy package'; end if;
      v_pj := public.therapy_price_for(p_store_id, v_therapy_pkg, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Therapy package "%" is missing its % price at this store',
          (select name from public.unlimited_therapy_packages where id = v_therapy_pkg),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_gross := (v_pj->>'price')::numeric * v_qty;

    else
      v_product_id := (v_item->>'product_id')::uuid;
      v_price := coalesce((v_item->>'unit_price')::numeric, 0);
      v_gross := v_price * v_qty;
    end if;

    v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
    v_line_total := round(v_gross - v_foc_amt, 2);
    v_subtotal := v_subtotal + v_line_total;
  end loop;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_kind := coalesce(v_item->>'line_kind', 'product');
    v_qty := greatest(coalesce((v_item->>'quantity')::integer, 1), 1);
    v_foc_qty := coalesce((v_item->>'foc_quantity')::integer, 0);

    if v_kind = 'nothing' then
      null;

    elsif v_kind = 'therapy' then
      v_therapy_pkg := (v_item->>'therapy_package_id')::uuid;
      v_pj := public.therapy_price_for(p_store_id, v_therapy_pkg, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_gross := v_price;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      select name, duration_months into v_therapy_name, v_therapy_months
        from public.unlimited_therapy_packages where id = v_therapy_pkg;
      insert into public.invoice_items
        (invoice_id, line_kind, product_id, therapy_package_id, quantity, unit_price, line_total,
         price_mode, price_source, price_source_id, store_id_snapshot, original_price,
         plan_name_snapshot, plan_months_snapshot, foc_quantity, is_foc, foc_amount)
      values (v_invoice_id, 'therapy', null, v_therapy_pkg, 1, v_price, v_line_total,
              v_mode, case when v_mode_ovr is null then 'therapy' else 'manual_override' end,
              v_therapy_pkg, p_store_id, v_price, v_therapy_name, v_therapy_months,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt);
    else
      v_product_id := (v_item->>'product_id')::uuid;
      v_price := coalesce((v_item->>'unit_price')::numeric, 0);
      v_gross := v_price * v_qty;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      insert into public.invoice_items
        (invoice_id, line_kind, product_id, quantity, unit_price, line_total, price_mode)
      values (v_invoice_id, 'product', v_product_id, v_qty, v_price, v_line_total, v_mode);
    end if;
  end loop;

  return v_invoice_id;
end $function$;

create table if not exists public.invoice_promotion_selections (
  id uuid primary key default gen_random_uuid(),
  invoice_item_id uuid references public.invoice_items(id) on delete cascade,
  product_id uuid references public.products(id),
  voucher_id uuid references public.vouchers(id),
  quantity integer not null default 1);

create table if not exists public.customer_credit_wallets (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null unique);   -- no FK: see the note above

create table if not exists public.customer_credit_lots (
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null references public.customer_credit_wallets(id),
  customer_id uuid not null,
  category text not null check (category in ('paid','bonus','legacy','promotional','exchange')),
  original_amount numeric(12,2) not null,
  remaining_amount numeric(12,2) not null,
  source_type text not null,
  source_record_id uuid,
  store_id uuid references public.stores(id),
  usage_restrictions jsonb not null default '{}'::jsonb,
  effective_date date not null default (now() at time zone 'Asia/Singapore')::date,
  reference_no text, reason text, note text,
  status text not null default 'active',
  is_locked boolean not null default false,
  created_by uuid, created_at timestamptz not null default now(),
  updated_at timestamptz not null default now());

create table if not exists public.customer_credit_ledger (
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null references public.customer_credit_wallets(id),
  customer_id uuid not null,
  entry_type text not null, category text not null,
  amount numeric(12,2) not null, lot_id uuid references public.customer_credit_lots(id),
  source_type text not null, source_record_id uuid,
  store_id uuid references public.stores(id),
  effective_date date not null default (now() at time zone 'Asia/Singapore')::date,
  reference_no text, reason text, note text, created_by uuid,
  created_at timestamptz not null default now());

create table if not exists public.customer_credit_allocations (
  id uuid primary key default gen_random_uuid(),
  ledger_entry_id uuid not null references public.customer_credit_ledger(id),
  lot_id uuid not null references public.customer_credit_lots(id),
  customer_id uuid not null,
  amount numeric(12,2) not null);

create table if not exists public.invoice_line_credit_allocations (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  invoice_item_id uuid references public.invoice_items(id) on delete cascade,
  lot_id uuid references public.customer_credit_lots(id),
  ledger_entry_id uuid references public.customer_credit_ledger(id),
  customer_id uuid,
  category text, amount numeric(12,2) not null,
  created_by uuid, created_at timestamptz not null default now());

-- --- verbatim from migrations 79 and 82 -------------------------------
create or replace function public.invoice_line_credit_purpose(p_line_kind text)
returns text language sql immutable as $function$
  select case p_line_kind
    when 'product' then 'product'
    when 'voucher' then 'voucher'
    when 'promotion' then 'promotion'
    when 'therapy' then 'therapy'
    when 'credit_package' then 'credit_package'
    when 'premium_bundle' then 'premium_bundle'
    else p_line_kind end
$function$;

create or replace function public.allocate_invoice_wallet_credit(
  p_invoice_id uuid, p_amount numeric, p_category text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_inv public.invoices%rowtype; v_it record; v_lot record;
  v_remaining numeric; v_line_open numeric; v_take numeric;
  v_wallet uuid; v_entry uuid; v_alloc jsonb := '[]'::jsonb; v_total numeric := 0;
  v_purpose text; v_vid uuid;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if v_inv.customer_id is null then
    raise exception 'Wallet credit needs a customer on the invoice'; end if;
  if v_inv.status not in ('draft','unpaid','partially_paid') then
    raise exception 'Wallet credit can only be applied to an unsettled invoice'; end if;
  if coalesce(p_amount,0) <= 0 then raise exception 'The wallet amount must be positive'; end if;

  v_wallet := public.ensure_customer_wallet(v_inv.customer_id);
  v_remaining := round(p_amount, 2);

  for v_it in
    select ii.*, public.invoice_line_credit_purpose(ii.line_kind::text) as purpose
      from public.invoice_items ii
     where ii.invoice_id = p_invoice_id
       and coalesce(ii.line_total,0) > 0
     order by ii.id
  loop
    exit when v_remaining <= 0;

    -- A credit product can never be funded by wallet credit.
    if v_it.purpose in ('credit_package','premium_bundle') then continue; end if;

    -- How much of this line is still unfunded by credit.
    select round(coalesce(v_it.line_total,0) - coalesce(v_it.line_discount,0)
                 - coalesce(sum(a.amount),0), 2)
      into v_line_open
      from public.invoice_line_credit_allocations a
     where a.invoice_item_id = v_it.id;
    if coalesce(v_line_open,0) <= 0 then continue; end if;

    v_purpose := v_it.purpose;
    v_vid := v_it.voucher_id;

    -- Bonus Credit first, then the oldest eligible lot.
    for v_lot in
      select l.* from public.customer_credit_lots l
       where l.customer_id = v_inv.customer_id and l.status = 'active'
         and l.remaining_amount > 0
         and (p_category is null or l.category = p_category)
         and public.credit_lot_allows(l.usage_restrictions, v_purpose, v_vid)
       order by (l.category = 'bonus') desc, l.effective_date, l.created_at
       for update
    loop
      exit when v_remaining <= 0 or v_line_open <= 0;
      v_take := least(v_lot.remaining_amount, v_line_open, v_remaining);
      if v_take <= 0 then continue; end if;

      insert into public.customer_credit_ledger (
        wallet_id, customer_id, entry_type, category, amount, lot_id,
        source_type, source_record_id, store_id, note, created_by)
      values (v_wallet, v_inv.customer_id, 'use', v_lot.category, v_take, v_lot.id,
        'invoice_payment', p_invoice_id, v_inv.store_id,
        'Invoice ' || v_inv.invoice_no, auth.uid())
      returning id into v_entry;

      update public.customer_credit_lots
         set remaining_amount = remaining_amount - v_take, updated_at = now()
       where id = v_lot.id;

      insert into public.customer_credit_allocations (ledger_entry_id, lot_id, customer_id, amount)
      values (v_entry, v_lot.id, v_inv.customer_id, v_take);

      insert into public.invoice_line_credit_allocations (
        invoice_id, invoice_item_id, lot_id, ledger_entry_id, customer_id,
        category, amount, created_by)
      values (p_invoice_id, v_it.id, v_lot.id, v_entry, v_inv.customer_id,
        v_lot.category, v_take, auth.uid());

      v_alloc := v_alloc || jsonb_build_object('invoice_item_id', v_it.id,
        'lot_id', v_lot.id, 'category', v_lot.category, 'amount', v_take);
      v_line_open := v_line_open - v_take;
      v_remaining := v_remaining - v_take;
      v_total := v_total + v_take;
    end loop;
  end loop;

  if v_remaining > 0.001 then
    raise exception 'Only % of the requested % could be funded by eligible credit', v_total, round(p_amount,2);
  end if;

  return jsonb_build_object('allocated', round(v_total,2), 'allocations', v_alloc);
end $function$;

create or replace function public.credit_lot_allows(
  p_restrictions jsonb, p_purpose text, p_voucher_id uuid default null)
returns boolean language sql immutable as $function$
  select case
    -- No restrictions: spendable on anything.
    when p_restrictions is null or p_restrictions = '{}'::jsonb then true
    -- Restricted lots only fund the listed purposes...
    when not (coalesce(p_restrictions->'allowed_purposes', '[]'::jsonb) ? p_purpose) then false
    -- ...and, when a voucher list is present, only those vouchers.
    when jsonb_array_length(coalesce(p_restrictions->'allowed_voucher_ids','[]'::jsonb)) = 0 then true
    when p_voucher_id is null then false
    else coalesce(p_restrictions->'allowed_voucher_ids', '[]'::jsonb) ? p_voucher_id::text
  end
$function$;

-- From migration 77: the wallet is created on demand.
create or replace function public.ensure_customer_wallet(p_customer_id uuid)
returns uuid language plpgsql set search_path = public as $fn$
declare v_id uuid;
begin
  select id into v_id from public.customer_credit_wallets where customer_id = p_customer_id;
  if v_id is null then
    insert into public.customer_credit_wallets (customer_id) values (p_customer_id) returning id into v_id;
  end if;
  return v_id;
end $fn$;
