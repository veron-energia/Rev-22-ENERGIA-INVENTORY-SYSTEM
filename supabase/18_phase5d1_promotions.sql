-- =====================================================================
-- ENERGIA — PHASE 5D-1: Promotions & bundles (MANAGEMENT ONLY)
--   * promotions catalog + promotion_items (products/vouchers/promotions/treatments)
--   * 2-level nesting rule + circular-reference prevention
--   * original-total price (from a store's normal prices) + savings
--   * flat stock resolver (expands nested promotions to leaf stock items)
--
-- This phase does NOT touch invoices, payment, or commission — that's 5D-2.
-- Additive + idempotent. Run AFTER 17_phase5c_vouchers.sql.
-- =====================================================================

set check_function_bodies = off;

do $$ begin create type promotion_type as enum ('bundle','treatment','other');
exception when duplicate_object then null; end $$;
do $$ begin create type promotion_item_type as enum ('product','voucher','promotion','treatment');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- 1. Promotions catalog
-- ---------------------------------------------------------------------
create table if not exists public.promotions (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null,
  promo_type promotion_type not null default 'bundle',
  fixed_price numeric(12,2) not null default 0,   -- the bundle selling price
  start_date date,
  end_date date,
  is_active boolean not null default true,
  description text,
  terms text,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists idx_promotions_active on public.promotions(is_active) where deleted_at is null;

-- ---------------------------------------------------------------------
-- 2. Promotion items (what's included)
-- ---------------------------------------------------------------------
create table if not exists public.promotion_items (
  id uuid primary key default gen_random_uuid(),
  promotion_id uuid not null references public.promotions(id) on delete cascade,
  item_type promotion_item_type not null,
  product_id uuid references public.products(id),
  voucher_id uuid references public.vouchers(id),
  child_promotion_id uuid references public.promotions(id),
  treatment_name text,                       -- for 'treatment' items
  quantity integer not null default 1 check (quantity > 0),
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists idx_promotion_items_promo on public.promotion_items(promotion_id);
create index if not exists idx_promotion_items_child on public.promotion_items(child_promotion_id);

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
alter table public.promotions enable row level security;
drop policy if exists "read promotions" on public.promotions;
create policy "read promotions" on public.promotions for select to authenticated using (deleted_at is null);
drop policy if exists "manage promotions" on public.promotions;
create policy "manage promotions" on public.promotions for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

alter table public.promotion_items enable row level security;
drop policy if exists "read promotion items" on public.promotion_items;
create policy "read promotion items" on public.promotion_items for select to authenticated using (true);
drop policy if exists "manage promotion items" on public.promotion_items;
create policy "manage promotion items" on public.promotion_items for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

-- ---------------------------------------------------------------------
-- 3. Does a promotion contain any child promotions? (depth helper)
--    A "leaf" promotion (no child promotions) has depth 1.
-- ---------------------------------------------------------------------
create or replace function public.promotion_has_children(p_promotion_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.promotion_items
    where promotion_id = p_promotion_id and item_type = 'promotion' and child_promotion_id is not null
  )
$$;

-- ---------------------------------------------------------------------
-- 4. Validate adding a child promotion (enforces 2-level rule + no cycle).
--    Rule: a child promotion may be included only if it ITSELF contains no
--    child promotions. That caps total depth at 2 and makes cycles impossible
--    (a leaf references no promotion, so A->B->A can't form).
-- ---------------------------------------------------------------------
create or replace function public.validate_promotion_child(p_parent_id uuid, p_child_id uuid)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if p_parent_id = p_child_id then
    raise exception 'A promotion cannot include itself';
  end if;
  if public.promotion_has_children(p_child_id) then
    raise exception 'Nesting limit: "%" already contains a promotion, so it cannot be nested inside another (max 2 levels).',
      (select name from public.promotions where id = p_child_id);
  end if;
  -- Also block if the parent is itself already nested inside something (would push depth to 3).
  if exists (select 1 from public.promotion_items where child_promotion_id = p_parent_id) then
    raise exception 'This promotion is already used inside another promotion, so it cannot contain a nested promotion (max 2 levels).';
  end if;
end; $$;

-- ---------------------------------------------------------------------
-- 5. Add a promotion item (validates child promotions).
--    item: product | voucher | promotion | treatment
-- ---------------------------------------------------------------------
create or replace function public.add_promotion_item(
  p_promotion_id uuid, p_item_type promotion_item_type,
  p_product_id uuid, p_voucher_id uuid, p_child_promotion_id uuid,
  p_treatment_name text, p_quantity integer, p_notes text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can edit promotions'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be greater than zero'; end if;

  if p_item_type = 'promotion' then
    if p_child_promotion_id is null then raise exception 'Select a promotion to nest'; end if;
    perform public.validate_promotion_child(p_promotion_id, p_child_promotion_id);
  elsif p_item_type = 'product' then
    if p_product_id is null then raise exception 'Select a product'; end if;
  elsif p_item_type = 'voucher' then
    if p_voucher_id is null then raise exception 'Select a voucher'; end if;
  elsif p_item_type = 'treatment' then
    if p_treatment_name is null or length(trim(p_treatment_name)) = 0 then raise exception 'Enter a treatment name'; end if;
  end if;

  insert into public.promotion_items
    (promotion_id, item_type, product_id, voucher_id, child_promotion_id, treatment_name, quantity, notes)
  values
    (p_promotion_id, p_item_type, p_product_id, p_voucher_id, p_child_promotion_id, p_treatment_name, p_quantity, p_notes)
  returning id into v_id;

  perform public.write_audit('promotion_items', p_promotion_id, 'promotion_item_added', null,
    jsonb_build_object('item_type', p_item_type));
  return v_id;
end; $$;

-- ---------------------------------------------------------------------
-- 6. Original total price of a promotion at a given store.
--    Products → store price; vouchers → selling price; nested promotion →
--    its own original total (recursively, bounded by the 2-level rule);
--    treatments → 0 (no catalogue price).
-- ---------------------------------------------------------------------
create or replace function public.promotion_original_total(p_promotion_id uuid, p_store_id uuid)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare v_item record; v_total numeric := 0; v_price numeric;
begin
  for v_item in select * from public.promotion_items where promotion_id = p_promotion_id
  loop
    if v_item.item_type = 'product' then
      select selling_price into v_price from public.store_product_prices
        where store_id = p_store_id and product_id = v_item.product_id and is_active = true and deleted_at is null;
      v_total := v_total + coalesce(v_price,0) * v_item.quantity;
    elsif v_item.item_type = 'voucher' then
      select selling_price into v_price from public.vouchers where id = v_item.voucher_id;
      v_total := v_total + coalesce(v_price,0) * v_item.quantity;
    elsif v_item.item_type = 'promotion' then
      v_total := v_total + public.promotion_original_total(v_item.child_promotion_id, p_store_id) * v_item.quantity;
    end if;  -- treatment contributes 0
  end loop;
  return v_total;
end; $$;

-- ---------------------------------------------------------------------
-- 7. Flat stock resolver: expand a promotion (incl. nested) into the
--    leaf stock items and total quantities. Returns product lines and
--    limited-voucher lines (unlimited vouchers/treatments carry no stock).
--    p_multiplier lets callers scale by the invoice line quantity.
-- ---------------------------------------------------------------------
create or replace function public.promotion_stock_items(p_promotion_id uuid, p_multiplier integer default 1)
returns table (kind text, item_id uuid, quantity integer)
language plpgsql stable security definer set search_path = public as $$
declare v_item record;
begin
  for v_item in select * from public.promotion_items where promotion_id = p_promotion_id
  loop
    if v_item.item_type = 'product' then
      kind := 'product'; item_id := v_item.product_id; quantity := v_item.quantity * p_multiplier; return next;
    elsif v_item.item_type = 'voucher' then
      -- only limited vouchers carry stock
      if exists (select 1 from public.vouchers where id = v_item.voucher_id and qty_type = 'limited') then
        kind := 'voucher'; item_id := v_item.voucher_id; quantity := v_item.quantity * p_multiplier; return next;
      end if;
    elsif v_item.item_type = 'promotion' then
      return query select * from public.promotion_stock_items(v_item.child_promotion_id, v_item.quantity * p_multiplier);
    end if;
  end loop;
end; $$;

-- ---------------------------------------------------------------------
-- 8. Commissionable breakdown: flat list of commission-bearing items with
--    their original price share and product-type. Used by 5D-2 to allocate
--    the fixed bundle price proportionally. (Products/vouchers/treatments;
--    nested promotions expand.)
-- ---------------------------------------------------------------------
create or replace function public.promotion_commission_items(p_promotion_id uuid, p_store_id uuid, p_multiplier integer default 1)
returns table (ptype text, original_value numeric)
language plpgsql stable security definer set search_path = public as $$
declare v_item record; v_price numeric;
begin
  for v_item in select * from public.promotion_items where promotion_id = p_promotion_id
  loop
    if v_item.item_type = 'product' then
      select selling_price into v_price from public.store_product_prices
        where store_id = p_store_id and product_id = v_item.product_id and is_active = true and deleted_at is null;
      ptype := coalesce((select product_type::text from public.products where id = v_item.product_id), 'own');
      original_value := coalesce(v_price,0) * v_item.quantity * p_multiplier; return next;
    elsif v_item.item_type = 'voucher' then
      select selling_price into v_price from public.vouchers where id = v_item.voucher_id;
      ptype := 'own';  -- vouchers commission like own products
      original_value := coalesce(v_price,0) * v_item.quantity * p_multiplier; return next;
    elsif v_item.item_type = 'treatment' then
      ptype := 'own';  -- treatments commission like own products; value 0 (no catalogue price)
      original_value := 0; return next;
    elsif v_item.item_type = 'promotion' then
      return query select * from public.promotion_commission_items(v_item.child_promotion_id, p_store_id, v_item.quantity * p_multiplier);
    end if;
  end loop;
end; $$;

notify pgrst, 'reload schema';
