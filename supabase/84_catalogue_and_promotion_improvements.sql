-- =====================================================================
-- ENERGIA — CATALOGUE AND PROMOTION IMPROVEMENTS
--
--   1. A third product type, "no_commission", for genuinely third-party
--      pass-through lines such as delivery and external services. It earns
--      neither affiliate nor staff commission.
--   2. Promotions can include Therapy packages and Credit Packages, both as
--      fixed items and as choice-group options.
--   3. A choice group's base price can be the CHEAPEST or the HIGHEST option.
--   4. SKUs for therapy packages, credit packages and premium bundles.
--   5. Helpers to set one price across every store, so a price is entered once.
--
-- Additive and idempotent. Run AFTER 83.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. The no-commission product type.
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                  where t.typname = 'product_type' and e.enumlabel = 'no_commission') then
    alter type public.product_type rename to product_type_pre84;
    create type public.product_type as enum ('own','third_party','no_commission');
    alter table public.products alter column product_type drop default;
    alter table public.products
      alter column product_type type public.product_type
      using product_type::text::public.product_type;
    alter table public.products alter column product_type set default 'own';
    drop type public.product_type_pre84;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Promotions may contain therapy packages and credit packages.
-- ---------------------------------------------------------------------
alter table public.promotion_items
  add column if not exists therapy_package_id uuid references public.unlimited_therapy_packages(id);
alter table public.promotion_items
  add column if not exists credit_package_id uuid references public.credit_packages(id);

alter table public.promotion_choice_options
  add column if not exists therapy_package_id uuid references public.unlimited_therapy_packages(id);
alter table public.promotion_choice_options
  add column if not exists credit_package_id uuid references public.credit_packages(id);

-- A choice group can now offer therapy or credit packages as well.
alter table public.promotion_choice_groups drop constraint if exists promotion_choice_groups_item_kind_check;
alter table public.promotion_choice_groups
  add constraint promotion_choice_groups_item_kind_check
  check (item_kind in ('product','voucher','therapy','credit_package'));

-- ---------------------------------------------------------------------
-- 3. The base of a choice group: cheapest option (default) or highest.
-- ---------------------------------------------------------------------
alter table public.promotion_choice_groups
  add column if not exists base_mode text not null default 'cheapest';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'promotion_choice_groups_base_mode_check') then
    alter table public.promotion_choice_groups
      add constraint promotion_choice_groups_base_mode_check check (base_mode in ('cheapest','highest'));
  end if;
end $$;

-- The bundle top-up baseline follows the group's chosen base.
create or replace function public.promotion_selections_topup(
  p_promotion_id uuid, p_store_id uuid, p_selections jsonb, p_is_member boolean default true)
returns numeric language plpgsql stable security definer set search_path to 'public' as $function$
declare
  v_grp record; v_sel jsonb; v_opt jsonb; v_baseline numeric; v_price numeric;
  v_topup numeric := 0; v_qty integer; v_pj jsonb;
begin
  for v_grp in select * from public.promotion_choice_groups
    where promotion_id = p_promotion_id and item_kind = 'product'
  loop
    -- Baseline is the cheapest listed option, or the dearest when the group
    -- is configured that way. Anything above the baseline is a top-up.
    if coalesce(v_grp.base_mode,'cheapest') = 'highest' then
      select max(spp.selling_price) into v_baseline
        from public.promotion_choice_options o
        join public.store_product_prices spp
          on spp.product_id = o.product_id and spp.store_id = p_store_id
         and spp.is_active = true and spp.deleted_at is null
       where o.group_id = v_grp.id and o.product_id is not null;
    else
      select min(spp.selling_price) into v_baseline
        from public.promotion_choice_options o
        join public.store_product_prices spp
          on spp.product_id = o.product_id and spp.store_id = p_store_id
         and spp.is_active = true and spp.deleted_at is null
       where o.group_id = v_grp.id and o.product_id is not null;
    end if;
    if v_baseline is null then continue; end if;

    for v_sel in select * from jsonb_array_elements(coalesce(p_selections,'[]'::jsonb))
    loop
      if (v_sel->>'group_id')::uuid <> v_grp.id then continue; end if;
      for v_opt in select * from jsonb_array_elements(coalesce(v_sel->'options','[]'::jsonb))
      loop
        v_qty := coalesce((v_opt->>'quantity')::integer, 0);
        if v_qty <= 0 or (v_opt->>'product_id') is null then continue; end if;
        if exists (select 1 from public.promotion_choice_options o
                    where o.group_id = v_grp.id and o.product_id = (v_opt->>'product_id')::uuid)
        then continue; end if;
        v_pj := public.product_price_for(p_store_id, (v_opt->>'product_id')::uuid, true);
        if not coalesce((v_pj->>'has_price')::boolean, false) then
          raise exception 'Product "%" is missing its price at this store (needed for the bundle top-up)',
            (select name from public.products where id = (v_opt->>'product_id')::uuid);
        end if;
        v_price := (v_pj->>'price')::numeric;
        if v_price > v_baseline then v_topup := v_topup + (v_price - v_baseline) * v_qty; end if;
      end loop;
    end loop;
  end loop;
  return round(v_topup, 2);
end $function$;

-- ---------------------------------------------------------------------
-- 4. SKUs for therapy packages, credit packages and premium bundles.
-- ---------------------------------------------------------------------
alter table public.unlimited_therapy_packages add column if not exists sku text;
alter table public.credit_packages add column if not exists sku text;
alter table public.premium_bundles add column if not exists sku text;
create unique index if not exists uq_therapy_pkg_sku
  on public.unlimited_therapy_packages (sku) where sku is not null and deleted_at is null;
create unique index if not exists uq_credit_pkg_sku
  on public.credit_packages (sku) where sku is not null and deleted_at is null;
create unique index if not exists uq_premium_bundle_sku
  on public.premium_bundles (sku) where sku is not null and deleted_at is null;

-- ---------------------------------------------------------------------
-- 5. Commission ignores no-commission products entirely.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'earn_invoice_commission';
  if v_def is null then raise exception 'earn_invoice_commission is missing'; end if;

  if position('no_commission' in v_def) = 0 then
    -- A no-commission product never contributes to a commission basis.
    v_def := replace(v_def,
      '      and ii.line_kind not in (''credit_package'',''premium_bundle'')',
      '      and ii.line_kind not in (''credit_package'',''premium_bundle'')' || chr(10) ||
      '      and coalesce(p.product_type::text, ''own'') <> ''no_commission''');
    if position('no_commission' in v_def) = 0 then
      raise exception 'could not exclude no-commission products from earn_invoice_commission';
    end if;
    execute v_def;
  end if;
end $patch$;

-- Staff commission, wherever it is calculated, ignores them too.
do $patch2$
declare r record; v_def text;
begin
  for r in
    select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prosrc ~ 'insert into public\.staff_commissions'
  loop
    v_def := pg_get_functiondef(r.oid);
    if position('no_commission' in v_def) = 0
       and position('from public.invoice_items ii' in v_def) > 0 then
      v_def := replace(v_def,
        'from public.invoice_items ii',
        'from public.invoice_items ii' || chr(10) ||
        '      left join public.products np on np.id = ii.product_id');
      v_def := replace(v_def,
        'where ii.invoice_id = p_invoice_id',
        'where ii.invoice_id = p_invoice_id' || chr(10) ||
        '        and coalesce(np.product_type::text, ''own'') <> ''no_commission''');
      if position('no_commission' in v_def) > 0 then
        begin
          execute v_def;
        exception when others then
          raise notice 'Staff commission function % left unchanged: %', r.proname, sqlerrm;
        end;
      end if;
    end if;
  end loop;
end $patch2$;

-- ---------------------------------------------------------------------
-- 6. Enter a price once and apply it everywhere.
-- ---------------------------------------------------------------------
create or replace function public.set_voucher_price_all_stores(
  p_voucher_id uuid, p_price numeric, p_available boolean default true)
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare v_s record; v_n integer := 0;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can edit voucher prices'; end if;
  for v_s in select id from public.stores where deleted_at is null and coalesce(is_active,true) loop
    perform public.set_voucher_prices(p_voucher_id, v_s.id, p_price, p_price, coalesce(p_available,true));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;

create or replace function public.set_promotion_price_all_stores(
  p_promotion_id uuid, p_price numeric, p_available boolean default true)
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare v_s record; v_n integer := 0;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can edit promotion prices'; end if;
  for v_s in select id from public.stores where deleted_at is null and coalesce(is_active,true) loop
    perform public.set_promotion_prices(p_promotion_id, v_s.id, p_price, p_price, coalesce(p_available,true));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;

create or replace function public.set_therapy_price_all_stores(
  p_package_id uuid, p_price numeric, p_available boolean default true)
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare v_s record; v_n integer := 0;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can set therapy prices'; end if;
  for v_s in select id from public.stores where deleted_at is null and coalesce(is_active,true) loop
    perform public.set_unlimited_therapy_price(p_package_id, v_s.id, p_price, p_price, coalesce(p_available,true));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;

-- ---------------------------------------------------------------------
-- 7. Customers who are not yet referrers can be activated as affiliates.
--    activate_affiliate already enforces Owner/Manager; this lists the
--    candidates so the UI can offer them.
-- ---------------------------------------------------------------------
create or replace function public.affiliate_candidates(p_query text default null, p_limit integer default 50)
returns table(customer_id uuid, full_name text, phone text, email text, is_referrer boolean)
language sql stable security definer set search_path to 'public' as $function$
  select c.id, c.full_name, c.phone, c.email, coalesce(c.is_referrer,false)
    from public.customers c
   where c.deleted_at is null
     and not exists (select 1 from public.customer_affiliates a
                      where a.customer_id = c.id and a.deleted_at is null)
     and (nullif(trim(coalesce(p_query,'')),'') is null
          or c.full_name ilike '%' || trim(p_query) || '%'
          or c.phone     ilike '%' || trim(p_query) || '%'
          or c.email     ilike '%' || trim(p_query) || '%'
          or c.notes     ilike '%' || trim(p_query) || '%')
   order by c.full_name
   limit greatest(coalesce(p_limit, 50), 1)
$function$;

-- One setter for all three catalogue SKUs, so the upsert signatures (and their
-- many optional parameters) do not have to change again.
create or replace function public.set_catalogue_sku(
  p_kind text, p_id uuid, p_sku text)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare v_sku text := nullif(trim(coalesce(p_sku,'')),'');
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can set a SKU'; end if;
  if p_kind = 'therapy' then
    update public.unlimited_therapy_packages set sku = v_sku, updated_at = now() where id = p_id;
  elsif p_kind = 'credit_package' then
    update public.credit_packages set sku = v_sku, updated_at = now() where id = p_id;
  elsif p_kind = 'premium_bundle' then
    update public.premium_bundles set sku = v_sku, updated_at = now() where id = p_id;
  else
    raise exception 'Unknown catalogue kind "%"', p_kind;
  end if;
exception when unique_violation then
  raise exception 'SKU "%" is already used by another item', v_sku;
end $function$;

notify pgrst, 'reload schema';
