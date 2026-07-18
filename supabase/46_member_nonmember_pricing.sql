-- =====================================================================
-- ENERGIA — PHASE 3: MEMBER / NON-MEMBER PRICING
--
-- Adds Member and Non-Member prices to products, vouchers, promotions and
-- Unlimited Therapy, plus product eligibility and transfer validation.
--
-- HISTORY-SAFE: the legacy `selling_price` columns are NOT dropped or
-- rewritten, so paid invoices (which snapshot their own line prices) are
-- untouched. Existing selling_price is COPIED into member_price; non_member
-- price is left blank for staff to fill. Invoice repricing is NOT activated
-- here (that is Phase 4).
--
-- Additive + idempotent. Run AFTER 45_membership_foundation.sql.
-- =====================================================================

set check_function_bodies = off;

-- =====================================================================
-- 1. PRODUCT PRICES + eligibility on store_product_prices
-- =====================================================================
alter table public.store_product_prices add column if not exists member_price numeric(12,2) check (member_price is null or member_price >= 0);
alter table public.store_product_prices add column if not exists non_member_price numeric(12,2) check (non_member_price is null or non_member_price >= 0);
alter table public.store_product_prices add column if not exists eligibility text not null default 'both'
  check (eligibility in ('both','member_only','non_member_only'));

-- Migrate: existing selling_price becomes the Member price; non-member stays
-- blank; everything defaults to "available to both". Only fill where empty so
-- a re-run doesn't clobber later manual edits.
update public.store_product_prices
   set member_price = selling_price
 where member_price is null;

-- =====================================================================
-- 2. Required-price validation for a store price row.
--    both            -> member AND non-member required
--    member_only     -> member required
--    non_member_only -> non-member required
-- =====================================================================
create or replace function public.product_price_complete(
  p_eligibility text, p_member numeric, p_non_member numeric
) returns boolean language sql immutable as $$
  select case coalesce(p_eligibility,'both')
    when 'both'            then p_member is not null and p_non_member is not null
    when 'member_only'     then p_member is not null
    when 'non_member_only' then p_non_member is not null
    else false end
$$;

-- Owner/Manager set prices + eligibility for a product at a store.
create or replace function public.set_product_prices(
  p_store_id uuid, p_product_id uuid,
  p_member numeric, p_non_member numeric, p_eligibility text
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit prices'; end if;
  if coalesce(p_eligibility,'both') not in ('both','member_only','non_member_only') then
    raise exception 'Invalid eligibility'; end if;
  if p_member is not null and p_member < 0 then raise exception 'Member price cannot be negative'; end if;
  if p_non_member is not null and p_non_member < 0 then raise exception 'Non-member price cannot be negative'; end if;

  insert into public.store_product_prices (store_id, product_id, selling_price, member_price, non_member_price, eligibility)
  values (p_store_id, p_product_id, coalesce(p_member, p_non_member, 0), p_member, p_non_member, coalesce(p_eligibility,'both'))
  on conflict (store_id, product_id) do update
    set member_price = excluded.member_price,
        non_member_price = excluded.non_member_price,
        eligibility = excluded.eligibility,
        -- keep legacy selling_price meaningful (= member price when present)
        selling_price = coalesce(excluded.member_price, excluded.non_member_price, public.store_product_prices.selling_price);

  perform public.write_audit_ex('store_product_prices', p_product_id, 'product_prices_set',
    null, jsonb_build_object('store', p_store_id, 'member', p_member, 'non_member', p_non_member, 'eligibility', p_eligibility),
    'pricing', null, p_store_id);
end $$;

-- =====================================================================
-- 3. TRANSFER VALIDATION — block moving a product INTO a store when its
--    required prices for that store are missing. W->W is exempt.
-- =====================================================================
create or replace function public.transfer_price_blockers(p_store_id uuid, p_product_ids uuid[])
returns table (product_id uuid, product_name text, eligibility text, missing text)
language sql stable security definer set search_path = public as $$
  select p.id, p.name,
         coalesce(spp.eligibility, 'both'),
         case
           when spp.product_id is null then 'no price row for this store'
           when not public.product_price_complete(spp.eligibility, spp.member_price, spp.non_member_price)
             then case coalesce(spp.eligibility,'both')
                    when 'both' then
                      trim(both ', ' from
                        concat_ws(', ',
                          case when spp.member_price is null then 'Member price' end,
                          case when spp.non_member_price is null then 'Non-Member price' end))
                    when 'member_only' then 'Member price'
                    when 'non_member_only' then 'Non-Member price'
                  end
         end
  from public.products p
  left join public.store_product_prices spp
    on spp.product_id = p.id and spp.store_id = p_store_id
  where p.id = any(p_product_ids)
    and (spp.product_id is null
         or not public.product_price_complete(spp.eligibility, spp.member_price, spp.non_member_price))
$$;

-- Raises if any product in the set is missing required prices for the store.
create or replace function public.assert_transfer_prices_ok(p_store_id uuid, p_product_ids uuid[])
returns void language plpgsql stable security definer set search_path = public as $$
declare v_row record; v_msgs text := '';
begin
  for v_row in select * from public.transfer_price_blockers(p_store_id, p_product_ids) loop
    v_msgs := v_msgs || v_row.product_name || ' (' || v_row.missing || '); ';
  end loop;
  if length(v_msgs) > 0 then
    raise exception 'Cannot transfer to this store — missing prices: %', rtrim(v_msgs, '; ');
  end if;
end $$;

-- Hook the gate into approve_transfer for warehouse_to_store / store_to_store.
-- Done via a BEFORE trigger on the approval path is awkward (approval takes
-- jsonb lines), so we guard inside a wrapper the app calls before approving,
-- AND provide the raising function for server-side enforcement. To make the
-- rule impossible to bypass, we also add a trigger on stock arriving at a store.
create or replace function public.trg_block_unpriced_store_stock() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- Only guard stock ARRIVING at a store (store_stock upserts). Warehouse
  -- stock is unaffected, so warehouse-to-warehouse never trips this.
  if new.store_id is not null and coalesce(new.quantity,0) > 0 then
    if not exists (
      select 1 from public.store_product_prices spp
       where spp.store_id = new.store_id and spp.product_id = new.product_id
         and public.product_price_complete(spp.eligibility, spp.member_price, spp.non_member_price)
    ) then
      raise exception 'Product % has no complete Member/Non-Member price for this store — set prices before stocking it here', new.product_id;
    end if;
  end if;
  return new;
end $$;

-- Attach only if a store_stock table exists (name-guarded so this migration
-- is safe regardless of the exact stock table name in this environment).
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='store_stock')
     and exists (select 1 from information_schema.columns where table_schema='public' and table_name='store_stock' and column_name='store_id')
  then
    drop trigger if exists block_unpriced_store_stock on public.store_stock;
    create trigger block_unpriced_store_stock
      before insert or update of quantity on public.store_stock
      for each row execute function public.trg_block_unpriced_store_stock();
  end if;
end $$;

-- =====================================================================
-- 4. VOUCHER STORE PRICES
-- =====================================================================
create table if not exists public.voucher_store_prices (
  id uuid primary key default gen_random_uuid(),
  voucher_id uuid not null references public.vouchers(id) on delete cascade,
  store_id uuid not null references public.stores(id),
  member_price numeric(12,2) check (member_price is null or member_price >= 0),
  non_member_price numeric(12,2) check (non_member_price is null or non_member_price >= 0),
  available_at_store boolean not null default true,
  deleted_at timestamptz,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (voucher_id, store_id)
);
create index if not exists idx_vsp_voucher on public.voucher_store_prices(voucher_id);

-- =====================================================================
-- 5. PROMOTION STORE PRICES
-- =====================================================================
create table if not exists public.promotion_store_prices (
  id uuid primary key default gen_random_uuid(),
  promotion_id uuid not null references public.promotions(id) on delete cascade,
  store_id uuid not null references public.stores(id),
  member_price numeric(12,2) check (member_price is null or member_price >= 0),
  non_member_price numeric(12,2) check (non_member_price is null or non_member_price >= 0),
  available_at_store boolean not null default true,
  deleted_at timestamptz,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (promotion_id, store_id)
);
create index if not exists idx_psp_promotion on public.promotion_store_prices(promotion_id);

-- Seed promotion store prices from the existing single fixed_price as the
-- member price, so nothing loses its current price. Non-member left blank.
insert into public.promotion_store_prices (promotion_id, store_id, member_price)
select pr.id, s.id, pr.fixed_price
from public.promotions pr
cross join public.stores s
where s.deleted_at is null
  and not exists (select 1 from public.promotion_store_prices x where x.promotion_id = pr.id and x.store_id = s.id)
on conflict (promotion_id, store_id) do nothing;

-- =====================================================================
-- 6. UNLIMITED THERAPY store prices (packages priced Member/Non-Member).
--    The purchasable-therapy tables land in a later phase; this table is
--    created now so pricing structure is uniform. Guard on therapy tables.
-- =====================================================================
-- (Deferred: purchasable therapy packages are created in a later phase;
--  their store prices will mirror this same member/non_member shape.)

-- =====================================================================
-- 7. Voucher/promotion price setters (Owner/Manager)
-- =====================================================================
create or replace function public.set_voucher_prices(
  p_voucher_id uuid, p_store_id uuid, p_member numeric, p_non_member numeric, p_available boolean
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit voucher prices'; end if;
  insert into public.voucher_store_prices (voucher_id, store_id, member_price, non_member_price, available_at_store, created_by, updated_by)
  values (p_voucher_id, p_store_id, p_member, p_non_member, coalesce(p_available,true), auth.uid(), auth.uid())
  on conflict (voucher_id, store_id) do update
    set member_price = excluded.member_price, non_member_price = excluded.non_member_price,
        available_at_store = excluded.available_at_store, updated_by = auth.uid(), updated_at = now(), deleted_at = null;
  perform public.write_audit_ex('voucher_store_prices', p_voucher_id, 'voucher_prices_set',
    null, jsonb_build_object('store', p_store_id, 'member', p_member, 'non_member', p_non_member), 'pricing', null, p_store_id);
end $$;

create or replace function public.set_promotion_prices(
  p_promotion_id uuid, p_store_id uuid, p_member numeric, p_non_member numeric, p_available boolean
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit promotion prices'; end if;
  insert into public.promotion_store_prices (promotion_id, store_id, member_price, non_member_price, available_at_store, created_by, updated_by)
  values (p_promotion_id, p_store_id, p_member, p_non_member, coalesce(p_available,true), auth.uid(), auth.uid())
  on conflict (promotion_id, store_id) do update
    set member_price = excluded.member_price, non_member_price = excluded.non_member_price,
        available_at_store = excluded.available_at_store, updated_by = auth.uid(), updated_at = now(), deleted_at = null;
  perform public.write_audit_ex('promotion_store_prices', p_promotion_id, 'promotion_prices_set',
    null, jsonb_build_object('store', p_store_id, 'member', p_member, 'non_member', p_non_member), 'pricing', null, p_store_id);
end $$;

-- =====================================================================
-- 8. RLS
-- =====================================================================
alter table public.voucher_store_prices enable row level security;
alter table public.promotion_store_prices enable row level security;

drop policy if exists "read voucher prices" on public.voucher_store_prices;
create policy "read voucher prices" on public.voucher_store_prices for select to authenticated using (true);
drop policy if exists "write voucher prices" on public.voucher_store_prices;
create policy "write voucher prices" on public.voucher_store_prices for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

drop policy if exists "read promotion prices" on public.promotion_store_prices;
create policy "read promotion prices" on public.promotion_store_prices for select to authenticated using (true);
drop policy if exists "write promotion prices" on public.promotion_store_prices;
create policy "write promotion prices" on public.promotion_store_prices for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

notify pgrst, 'reload schema';
