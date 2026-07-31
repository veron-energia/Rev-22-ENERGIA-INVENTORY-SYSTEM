-- =====================================================================
-- ENERGIA — THERAPY AND CREDIT PACKAGES AS PROMOTION INCLUDED ITEMS
--
-- Migration 84 added therapy_package_id / credit_package_id columns and
-- allowed both as CHOICE-GROUP options. This finishes the job: they can now
-- also be fixed "Included items" in a bundle.
--
--   * promotion_item_type gains 'therapy' and 'credit_package'
--   * add_promotion_item accepts the two new references
--   * promotion_original_total prices them, so the savings preview is honest
--
-- Additive and idempotent. Run AFTER 85.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Two more kinds of included item.
-- ---------------------------------------------------------------------
-- Anything typed on the old enum must go first, or the rebuild cannot drop it.
drop function if exists public.add_promotion_item(uuid, public.promotion_item_type, uuid, uuid, uuid, text, integer, text);

do $$
declare r record;
begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                  where t.typname = 'promotion_item_type' and e.enumlabel = 'therapy') then
    -- Drop every function that takes or returns the enum; they are all
    -- re-created below or elsewhere in the migration chain.
    for r in
      select p.oid::regprocedure as sig
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and (p.proargtypes::oid[] @> array[(select oid from pg_type where typname = 'promotion_item_type')]
              or p.prorettype = (select oid from pg_type where typname = 'promotion_item_type'))
    loop
      execute 'drop function if exists ' || r.sig;
    end loop;

    alter type public.promotion_item_type rename to promotion_item_type_pre86;
    create type public.promotion_item_type as enum
      ('product','voucher','promotion','treatment','therapy','credit_package');
    alter table public.promotion_items alter column item_type drop default;
    alter table public.promotion_items
      alter column item_type type public.promotion_item_type
      using item_type::text::public.promotion_item_type;
    drop type public.promotion_item_type_pre86;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Adding an item, now including therapy and credit packages.
-- ---------------------------------------------------------------------
create or replace function public.add_promotion_item(
  p_promotion_id uuid,
  p_item_type public.promotion_item_type,
  p_product_id uuid default null,
  p_voucher_id uuid default null,
  p_child_promotion_id uuid default null,
  p_treatment_name text default null,
  p_quantity integer default 1,
  p_notes text default null,
  p_therapy_package_id uuid default null,
  p_credit_package_id uuid default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can edit a promotion'; end if;
  if coalesce(p_quantity,0) <= 0 then raise exception 'Quantity must be greater than zero'; end if;

  if p_item_type = 'product' and p_product_id is null then
    raise exception 'Select a product'; end if;
  if p_item_type = 'voucher' and p_voucher_id is null then
    raise exception 'Select a voucher'; end if;
  if p_item_type = 'promotion' then
    if p_child_promotion_id is null then raise exception 'Select a promotion'; end if;
    perform public.validate_promotion_child(p_promotion_id, p_child_promotion_id);
  end if;
  if p_item_type = 'treatment' and coalesce(trim(p_treatment_name),'') = '' then
    raise exception 'Enter a treatment name'; end if;
  if p_item_type = 'therapy' and p_therapy_package_id is null then
    raise exception 'Select a therapy package'; end if;
  if p_item_type = 'credit_package' and p_credit_package_id is null then
    raise exception 'Select a credit package'; end if;

  insert into public.promotion_items (
    promotion_id, item_type, product_id, voucher_id, child_promotion_id,
    treatment_name, quantity, notes, therapy_package_id, credit_package_id)
  values (p_promotion_id, p_item_type, p_product_id, p_voucher_id, p_child_promotion_id,
    nullif(trim(coalesce(p_treatment_name,'')),''), p_quantity, p_notes,
    p_therapy_package_id, p_credit_package_id)
  returning id into v_id;

  perform public.write_audit_ex('promotion_items', v_id, 'promotion_item_added', null,
    jsonb_build_object('promotion', p_promotion_id, 'type', p_item_type, 'quantity', p_quantity),
    'catalogue', null, null);
  return v_id;
end $function$;

-- ---------------------------------------------------------------------
-- 3. Price the new kinds so the "original total" and savings are honest.
-- ---------------------------------------------------------------------
create or replace function public.promotion_original_total(p_promotion_id uuid, p_store_id uuid)
returns numeric language plpgsql stable security definer set search_path to 'public' as $function$
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
    elsif v_item.item_type = 'therapy' then
      -- Priced per store, like everything else.
      select selling_price into v_price from public.unlimited_therapy_store_prices
        where store_id = p_store_id and package_id = v_item.therapy_package_id
          and coalesce(available_at_store, true) and deleted_at is null;
      v_total := v_total + coalesce(v_price,0) * v_item.quantity;
    elsif v_item.item_type = 'credit_package' then
      select customer_price into v_price from public.credit_packages
        where id = v_item.credit_package_id and deleted_at is null;
      v_total := v_total + coalesce(v_price,0) * v_item.quantity;
    end if;  -- treatment contributes 0
  end loop;
  return v_total;
end $function$;

notify pgrst, 'reload schema';
