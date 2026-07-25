-- =====================================================================
-- ENERGIA — PHASE 20: SINGLE PRICING, AFFILIATE SIMPLIFICATION,
--                      INVOICE AFFILIATE RESELECTION
--
--   * Collapses Member Price / Non-Member Price to a single selling_price
--     on every store price row (products, vouchers, promotions, therapy).
--     The former Member Price is the price. Blocks migration if any active
--     product row has no Member Price to copy.
--   * Product eligibility becomes "available" (Available for Sale).
--   * Re-issues the pricing helpers, setters, repricer, transfer/stock
--     guards and promotion top-up to read selling_price only, ignoring the
--     price mode. Historical invoice snapshots are left intact.
--   * Reactivates affiliates that Phase 19 marked inactive ONLY because of
--     Membership (recorded in data_removal_reconciliation); leaves manually
--     suspended affiliates suspended. New affiliates still need Owner/Manager.
--   * Adds set_invoice_affiliate() so a Draft/Unpaid invoice's affiliate can
--     be selected or reselected (store-scoped for staff), recorded in the
--     revision history and audit log, without touching customers.referred_by.
--     Payment already snapshots invoices.affiliate_id and locks the invoice.
--
-- Additive/idempotent where possible; the column drops are one-way. Run
-- AFTER 68.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. GUARD: every active product price row must have a Member Price to
--    copy into selling_price. If any are missing, abort and list them.
-- ---------------------------------------------------------------------
do $$
declare v_missing integer; v_list text;
begin
  if not exists (select 1 from information_schema.columns
                  where table_name = 'store_product_prices' and column_name = 'member_price') then
    raise notice 'Phase 20: single-pricing already applied — skipping guard.';
    return;
  end if;
  select count(*), string_agg(distinct p.name || ' @ ' || s.name, ', ')
    into v_missing, v_list
    from public.store_product_prices spp
    join public.products p on p.id = spp.product_id
    join public.stores s on s.id = spp.store_id
   where spp.deleted_at is null and coalesce(spp.is_active, true)
     and spp.member_price is null;
  if coalesce(v_missing,0) > 0 then
    raise exception 'Phase 20 blocked: % active product price row(s) have no Member Price to become the selling price: %',
      v_missing, v_list;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Copy Member Price -> selling_price everywhere, then drop the M/NM
--    columns and the eligibility modes. Guarded so it only runs once.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from information_schema.columns
              where table_name = 'store_product_prices' and column_name = 'member_price') then

    -- Products: selling_price already mirrors member_price (Phase 19 kept it
    -- in sync); make it authoritative, then drop the M/NM + eligibility trio.
    update public.store_product_prices
       set selling_price = coalesce(member_price, non_member_price, selling_price, 0);
    alter table public.store_product_prices drop constraint if exists store_product_prices_eligibility_check;
    alter table public.store_product_prices drop constraint if exists store_product_prices_member_price_check;
    alter table public.store_product_prices drop constraint if exists store_product_prices_non_member_price_check;
    alter table public.store_product_prices drop column if exists member_price;
    alter table public.store_product_prices drop column if exists non_member_price;
    -- Eligibility collapses to a single value.
    update public.store_product_prices set eligibility = 'available';
    alter table public.store_product_prices
      add constraint store_product_prices_eligibility_check check (eligibility = 'available');
    alter table public.store_product_prices alter column eligibility set default 'available';
  end if;
end $$;

-- Voucher / Promotion / Therapy store prices: member_price becomes the
-- single selling_price column; drop non_member_price.
do $$
begin
  if exists (select 1 from information_schema.columns
              where table_name = 'voucher_store_prices' and column_name = 'non_member_price') then
    alter table public.voucher_store_prices rename column member_price to selling_price;
    update public.voucher_store_prices set selling_price = coalesce(selling_price, non_member_price);
    alter table public.voucher_store_prices drop column non_member_price;
  end if;
  if exists (select 1 from information_schema.columns
              where table_name = 'promotion_store_prices' and column_name = 'non_member_price') then
    alter table public.promotion_store_prices rename column member_price to selling_price;
    update public.promotion_store_prices set selling_price = coalesce(selling_price, non_member_price);
    alter table public.promotion_store_prices drop column non_member_price;
  end if;
  if exists (select 1 from information_schema.columns
              where table_name = 'unlimited_therapy_store_prices' and column_name = 'non_member_price') then
    alter table public.unlimited_therapy_store_prices rename column member_price to selling_price;
    update public.unlimited_therapy_store_prices set selling_price = coalesce(selling_price, non_member_price);
    alter table public.unlimited_therapy_store_prices drop column non_member_price;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 3. Re-issue the pricing helpers to read selling_price only. The
--    p_is_member parameter stays for signature compatibility but is
--    ignored (every customer gets the single price).
-- ---------------------------------------------------------------------
create or replace function public.product_price_for(p_store_id uuid, p_product_id uuid, p_is_member boolean default true)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_spp public.store_product_prices%rowtype;
begin
  select * into v_spp from public.store_product_prices
   where store_id = p_store_id and product_id = p_product_id
     and is_active = true and deleted_at is null;
  if not found then return jsonb_build_object('found', false); end if;
  return jsonb_build_object('found', true, 'source_id', v_spp.id, 'store_id', p_store_id,
    'eligibility', 'available', 'price_mode', null, 'price', v_spp.selling_price,
    'member_price', v_spp.selling_price, 'non_member_price', v_spp.selling_price,
    'eligible', true, 'has_price', v_spp.selling_price is not null);
end $function$;

create or replace function public.voucher_price_for(p_store_id uuid, p_voucher_id uuid, p_is_member boolean default true)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_r public.voucher_store_prices%rowtype;
begin
  select * into v_r from public.voucher_store_prices
   where store_id = p_store_id and voucher_id = p_voucher_id and deleted_at is null;
  if not found or not v_r.available_at_store then
    return jsonb_build_object('found', found, 'available', false); end if;
  return jsonb_build_object('found', true, 'available', true, 'source_id', v_r.id, 'store_id', p_store_id,
    'price_mode', null, 'price', v_r.selling_price,
    'member_price', v_r.selling_price, 'non_member_price', v_r.selling_price,
    'eligible', true, 'has_price', v_r.selling_price is not null);
end $function$;

create or replace function public.promotion_price_for(p_store_id uuid, p_promotion_id uuid, p_is_member boolean default true)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_r public.promotion_store_prices%rowtype;
begin
  select * into v_r from public.promotion_store_prices
   where store_id = p_store_id and promotion_id = p_promotion_id and deleted_at is null;
  if not found or not v_r.available_at_store then
    return jsonb_build_object('found', found, 'available', false); end if;
  return jsonb_build_object('found', true, 'available', true, 'source_id', v_r.id, 'store_id', p_store_id,
    'price_mode', null, 'price', v_r.selling_price,
    'member_price', v_r.selling_price, 'non_member_price', v_r.selling_price,
    'eligible', true, 'has_price', v_r.selling_price is not null);
end $function$;

create or replace function public.therapy_price_for(p_store_id uuid, p_package_id uuid, p_is_member boolean default true)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare r public.unlimited_therapy_store_prices%rowtype;
begin
  select * into r from public.unlimited_therapy_store_prices
   where package_id = p_package_id and store_id = p_store_id and deleted_at is null;
  if not found or not r.available_at_store then
    return jsonb_build_object('found', false, 'has_price', false, 'eligible', true); end if;
  return jsonb_build_object('found', true, 'eligible', true,
    'has_price', r.selling_price is not null, 'price', r.selling_price, 'price_mode', null,
    'member_price', r.selling_price, 'non_member_price', r.selling_price, 'source_id', p_package_id);
end $function$;

-- product_price_complete: a row is complete when it has a selling price.
create or replace function public.product_price_complete(p_eligibility text, p_member numeric, p_non_member numeric)
returns boolean language sql immutable as $function$
  select coalesce(p_member, p_non_member) is not null
$function$;

-- ---------------------------------------------------------------------
-- 4. Single-price setters. Old multi-arg signatures are dropped first so
--    the new ones don't collide, then a compatibility shim keeps the
--    5-arg product setter callable from the current frontend.
-- ---------------------------------------------------------------------
drop function if exists public.set_product_prices(uuid, uuid, numeric, numeric, text);
create or replace function public.set_product_prices(
  p_store_id uuid, p_product_id uuid, p_member numeric,
  p_non_member numeric default null, p_eligibility text default 'available')
returns void language plpgsql security definer set search_path to 'public' as $function$
declare v_price numeric := coalesce(p_member, p_non_member);
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit prices'; end if;
  if v_price is null then raise exception 'A selling price is required'; end if;
  if v_price < 0 then raise exception 'Price cannot be negative'; end if;
  insert into public.store_product_prices (store_id, product_id, selling_price, eligibility)
  values (p_store_id, p_product_id, v_price, 'available')
  on conflict (store_id, product_id) do update
    set selling_price = excluded.selling_price, eligibility = 'available', deleted_at = null;
  perform public.write_audit_ex('store_product_prices', p_product_id, 'product_prices_set',
    null, jsonb_build_object('store', p_store_id, 'price', v_price), 'pricing', null, p_store_id);
end $function$;

drop function if exists public.set_voucher_prices(uuid, uuid, numeric, numeric, boolean);
create or replace function public.set_voucher_prices(
  p_voucher_id uuid, p_store_id uuid, p_member numeric,
  p_non_member numeric default null, p_available boolean default true)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare v_price numeric := coalesce(p_member, p_non_member);
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit voucher prices'; end if;
  insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store, created_by, updated_by)
  values (p_voucher_id, p_store_id, v_price, coalesce(p_available,true), auth.uid(), auth.uid())
  on conflict (voucher_id, store_id) do update
    set selling_price = excluded.selling_price, available_at_store = excluded.available_at_store,
        updated_by = auth.uid(), updated_at = now(), deleted_at = null;
  perform public.write_audit_ex('voucher_store_prices', p_voucher_id, 'voucher_prices_set',
    null, jsonb_build_object('store', p_store_id, 'price', v_price), 'pricing', null, p_store_id);
end $function$;

drop function if exists public.set_promotion_prices(uuid, uuid, numeric, numeric, boolean);
create or replace function public.set_promotion_prices(
  p_promotion_id uuid, p_store_id uuid, p_member numeric,
  p_non_member numeric default null, p_available boolean default true)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare v_price numeric := coalesce(p_member, p_non_member);
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit promotion prices'; end if;
  insert into public.promotion_store_prices (promotion_id, store_id, selling_price, available_at_store, created_by, updated_by)
  values (p_promotion_id, p_store_id, v_price, coalesce(p_available,true), auth.uid(), auth.uid())
  on conflict (promotion_id, store_id) do update
    set selling_price = excluded.selling_price, available_at_store = excluded.available_at_store,
        updated_by = auth.uid(), updated_at = now(), deleted_at = null;
  perform public.write_audit_ex('promotion_store_prices', p_promotion_id, 'promotion_prices_set',
    null, jsonb_build_object('store', p_store_id, 'price', v_price), 'pricing', null, p_store_id);
end $function$;

drop function if exists public.set_unlimited_therapy_price(uuid, uuid, numeric, numeric, boolean);
create or replace function public.set_unlimited_therapy_price(
  p_package_id uuid, p_store_id uuid, p_member numeric,
  p_non_member numeric default null, p_available boolean default true)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare v_price numeric := coalesce(p_member, p_non_member);
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can set therapy prices'; end if;
  insert into public.unlimited_therapy_store_prices (package_id, store_id, selling_price, available_at_store, created_by, updated_by)
  values (p_package_id, p_store_id, v_price, coalesce(p_available,true), auth.uid(), auth.uid())
  on conflict (package_id, store_id) do update
    set selling_price = excluded.selling_price, available_at_store = excluded.available_at_store,
        deleted_at = null, updated_by = auth.uid(), updated_at = now();
  perform public.write_audit_ex('unlimited_therapy_store_prices', p_package_id, 'therapy_price_set',
    null, jsonb_build_object('store', p_store_id, 'price', v_price), 'therapy', null, p_store_id);
end $function$;

-- ---------------------------------------------------------------------
-- 5. Transfer / stock guards read selling_price now.
-- ---------------------------------------------------------------------
create or replace function public.transfer_price_blockers(p_store_id uuid, p_product_ids uuid[])
returns table(product_id uuid, product_name text, eligibility text, missing text)
language sql stable security definer set search_path to 'public' as $function$
  select p.id, p.name, 'available',
         case when spp.product_id is null then 'no price row for this store'
              when spp.selling_price is null then 'Selling price' end
  from public.products p
  left join public.store_product_prices spp
    on spp.product_id = p.id and spp.store_id = p_store_id
  where p.id = any(p_product_ids)
    and (spp.product_id is null or spp.selling_price is null)
$function$;

create or replace function public.trg_block_unpriced_store_stock()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.store_id is not null and coalesce(new.quantity,0) > 0 then
    if not exists (
      select 1 from public.store_product_prices spp
       where spp.store_id = new.store_id and spp.product_id = new.product_id
         and spp.selling_price is not null
    ) then
      raise exception 'Product % has no selling price for this store — set a price before stocking it here', new.product_id;
    end if;
  end if;
  return new;
end $function$;
-- ---------------------------------------------------------------------
-- 6. Promotion bundle top-up: baseline uses selling_price now.
-- ---------------------------------------------------------------------
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
    -- Baseline = cheapest LISTED option at this store (single price now).
    select min(spp.selling_price) into v_baseline
    from public.promotion_choice_options o
    join public.store_product_prices spp
      on spp.product_id = o.product_id and spp.store_id = p_store_id
     and spp.is_active = true and spp.deleted_at is null
    where o.group_id = v_grp.id and o.product_id is not null;
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

-- Keep the old 4-arg promotion_selections_topup signature working (some
-- callers pass p_is_member explicitly); it now just ignores the mode.
-- (The 4-arg form already matches the definition above via defaults.)

-- ---------------------------------------------------------------------
-- 7. reprice_invoice_lines: single price, no eligibility gate. Historical
--    snapshot columns keep being written (value = the single price) so the
--    print/detail views stay consistent.
-- ---------------------------------------------------------------------
create or replace function public.reprice_invoice_lines(p_invoice_id uuid, p_is_member boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_inv public.invoices%rowtype; v_li record; v_pj jsonb; v_new numeric;
  v_changes jsonb := '[]'::jsonb; v_subtotal numeric;
  v_old_line_disc numeric; v_new_line_disc numeric;
  v_old_sub numeric; v_old_disc numeric; v_old_total numeric;
  v_new_topup numeric; v_gross numeric; v_foc numeric; v_charged numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  v_old_sub := v_inv.subtotal; v_old_disc := v_inv.discount_total; v_old_total := v_inv.total_amount;
  select coalesce(sum(coalesce(line_discount,0)),0) into v_old_line_disc
    from public.invoice_items where invoice_id = p_invoice_id;

  for v_li in
    select ii.*, p.name as pname, pr.name as prname, vo.name as voname
      from public.invoice_items ii
      left join public.products p on p.id = ii.product_id
      left join public.promotions pr on pr.id = ii.promotion_id
      left join public.vouchers vo on vo.id = ii.voucher_id
     where ii.invoice_id = p_invoice_id
       and ii.line_kind in ('product','voucher','promotion')
       and coalesce(ii.price_overridden,false) = false
       and coalesce(ii.price_source,'') <> 'topup'
       and not (ii.line_kind = 'product' and ii.product_id is null)
       and not (ii.line_kind = 'voucher' and ii.voucher_id is null)
       and not (ii.line_kind = 'promotion' and ii.promotion_id is null)
  loop
    if v_li.line_kind = 'product' then
      v_pj := public.product_price_for(v_inv.store_id, v_li.product_id, true);
      if not coalesce((v_pj->>'found')::boolean,false) then raise exception 'Product "%" has no price row at this store', v_li.pname; end if;
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Product "%" is missing its price at this store', v_li.pname; end if;
      v_new := (v_pj->>'price')::numeric;
      if v_new is distinct from v_li.unit_price then
        v_changes := v_changes || jsonb_build_object('item_id', v_li.id, 'kind','product','name', v_li.pname,
          'old_price', v_li.unit_price, 'new_price', v_new, 'reason','price updated');
      end if;
      v_gross := v_new * v_li.quantity;
      v_foc := case when coalesce(v_li.foc_quantity,0) > 0
                    then round(v_gross * v_li.foc_quantity::numeric / v_li.quantity::numeric, 2) else 0 end;
      v_charged := round(v_gross - v_foc, 2);
      update public.invoice_items set unit_price = v_new,
        line_total = v_charged, foc_amount = v_foc,
        line_discount = case when line_voucher_id is not null then public.voucher_discount_amount(line_voucher_id, v_charged) else line_discount end,
        price_mode = null, price_source='product', price_source_id=(v_pj->>'source_id')::uuid,
        store_id_snapshot = v_inv.store_id,
        member_price_snapshot = v_new, non_member_price_snapshot = v_new,
        original_price = coalesce(original_price, v_li.unit_price)
       where id = v_li.id;

    elsif v_li.line_kind = 'voucher' then
      v_pj := public.voucher_price_for(v_inv.store_id, v_li.voucher_id, true);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Voucher "%" is missing its price at this store', v_li.voname; end if;
      v_new := (v_pj->>'price')::numeric;
      if v_new is distinct from v_li.unit_price then
        v_changes := v_changes || jsonb_build_object('item_id', v_li.id, 'kind','voucher','name', v_li.voname,
          'old_price', v_li.unit_price, 'new_price', v_new, 'reason','price updated'); end if;
      v_gross := v_new * v_li.quantity;
      v_foc := case when coalesce(v_li.foc_quantity,0) > 0
                    then round(v_gross * v_li.foc_quantity::numeric / v_li.quantity::numeric, 2) else 0 end;
      v_charged := round(v_gross - v_foc, 2);
      update public.invoice_items set unit_price=v_new, line_total=v_charged, foc_amount=v_foc,
        price_mode=null, price_source='voucher', price_source_id=(v_pj->>'source_id')::uuid,
        store_id_snapshot=v_inv.store_id,
        member_price_snapshot = v_new, non_member_price_snapshot = v_new,
        original_price=coalesce(original_price, v_li.unit_price)
       where id = v_li.id;

    else -- promotion
      v_pj := public.promotion_price_for(v_inv.store_id, v_li.promotion_id, true);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Promotion "%" is missing its price at this store', v_li.prname; end if;
      perform public.assert_promotion_choices_ok(v_li.id, v_inv.store_id, true, coalesce(v_li.price_overridden,false));
      v_new := (v_pj->>'price')::numeric;
      v_new_topup := public.promotion_selections_topup(
        v_li.promotion_id, v_inv.store_id,
        (select coalesce(jsonb_agg(jsonb_build_object('group_id', g.group_id, 'options', g.options)), '[]'::jsonb)
           from (select s.group_id,
                        jsonb_agg(jsonb_build_object('product_id', s.product_id,
                          'voucher_id', s.voucher_id, 'quantity', s.quantity)) as options
                   from public.invoice_promotion_selections s
                  where s.invoice_item_id = v_li.id
                  group by s.group_id) g),
        true);
      if v_new is distinct from v_li.unit_price or coalesce(v_new_topup,0) is distinct from coalesce(v_li.topup_amount,0) then
        v_changes := v_changes || jsonb_build_object('item_id', v_li.id, 'kind','promotion','name', v_li.prname,
          'old_price', v_li.unit_price, 'new_price', v_new,
          'old_topup', coalesce(v_li.topup_amount,0), 'new_topup', coalesce(v_new_topup,0),
          'reason', 'price updated');
      end if;
      v_gross := (v_new * v_li.quantity) + coalesce(v_new_topup,0);
      v_foc := case when coalesce(v_li.foc_quantity,0) > 0
                    then round(v_gross * v_li.foc_quantity::numeric / v_li.quantity::numeric, 2) else 0 end;
      v_charged := round(v_gross - v_foc, 2);
      update public.invoice_items set unit_price=v_new, topup_amount=v_new_topup,
        line_total=v_charged, foc_amount=v_foc,
        price_mode=null, price_source='promotion', price_source_id=(v_pj->>'source_id')::uuid,
        store_id_snapshot=v_inv.store_id,
        member_price_snapshot = v_new, non_member_price_snapshot = v_new,
        original_price=coalesce(original_price, v_li.unit_price)
       where id = v_li.id;
    end if;
  end loop;

  select coalesce(sum(line_total),0) into v_subtotal from public.invoice_items where invoice_id = p_invoice_id;
  select coalesce(sum(coalesce(line_discount,0)),0) into v_new_line_disc from public.invoice_items where invoice_id = p_invoice_id;
  update public.invoices set subtotal = v_subtotal where id = p_invoice_id;
  if v_inv.manual_discount is not null then
    perform public.refresh_invoice_discount_total(p_invoice_id);
  else
    update public.invoices set discount_total = greatest(0, coalesce(discount_total,0) + (v_new_line_disc - v_old_line_disc)) where id = p_invoice_id;
  end if;
  update public.invoices set discount_total = least(coalesce(discount_total,0), v_subtotal) where id = p_invoice_id;
  update public.invoices i set total_amount = greatest(0, i.subtotal - coalesce(i.discount_total,0)) where i.id = p_invoice_id;

  -- Refresh the FOC rollup from the repriced lines.
  update public.invoices i
     set foc_total = coalesce(f.foc,0),
         has_foc = coalesce(f.foc_lines,0) > 0,
         is_full_foc = (coalesce(f.foc_lines,0) > 0 and coalesce(f.charged_lines,0) = 0)
    from (select coalesce(sum(foc_amount),0) as foc,
                 count(*) filter (where foc_quantity > 0) as foc_lines,
                 count(*) filter (where coalesce(line_total,0) > 0) as charged_lines
            from public.invoice_items where invoice_id = p_invoice_id) f
   where i.id = p_invoice_id;

  if exists (select 1 from public.invoices where id = p_invoice_id and total_amount + 0.001 < paid_amount) then
    raise exception 'Repricing would reduce the total below the amount already paid'; end if;

  select * into v_inv from public.invoices where id = p_invoice_id;
  if v_inv.subtotal is distinct from v_old_sub or v_inv.discount_total is distinct from v_old_disc
     or v_inv.total_amount is distinct from v_old_total then
    if jsonb_array_length(v_changes) = 0 then
      v_changes := v_changes || jsonb_build_object('item_id', null, 'kind','invoice','name','Invoice totals',
        'old_total', v_old_total, 'new_total', v_inv.total_amount, 'reason','totals recalculated');
    end if;
  end if;
  return v_changes;
end $function$;

-- ---------------------------------------------------------------------
-- 8. AFFILIATE SIMPLIFICATION
--    Reactivate the affiliates Phase 19 recorded as inactive ONLY because
--    of Membership. Manually suspended affiliates are left alone.
-- ---------------------------------------------------------------------
do $$
declare v_n integer := 0;
begin
  update public.customer_affiliates a
     set status = 'active', deleted_at = null,
         reactivated_at = now(), updated_at = now()
   where a.deleted_at is null
     and coalesce(a.manually_suspended, false) = false
     and a.status = 'inactive'
     and exists (
       select 1 from public.data_removal_reconciliation d
        where d.category = 'affiliate_inactive_due_to_membership'
          and d.customer_id = a.customer_id);
  get diagnostics v_n = row_count;
  raise notice 'Phase 20: reactivated % affiliate(s) that were inactive only due to Membership', v_n;
end $$;

-- ---------------------------------------------------------------------
-- 9. INVOICE AFFILIATE SELECTION / RESELECTION
--    Allowed while the invoice is Draft/Unpaid (never once paid/locked).
--    Staff limited to their store. Recorded in revision history + audit.
--    customers.referred_by is deliberately NOT changed.
-- ---------------------------------------------------------------------
create or replace function public.set_invoice_affiliate(p_invoice_id uuid, p_affiliate_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_inv public.invoices%rowtype; v_old uuid; v_rev integer;
  v_aff_ok boolean; v_aff_name text;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if v_inv.locked_at is not null or v_inv.status not in ('draft','unpaid')
     or coalesce(v_inv.paid_amount,0) <> 0
     or exists (select 1 from public.invoice_payments p where p.invoice_id = p_invoice_id) then
    raise exception 'The affiliate can only be changed while the invoice is unpaid';
  end if;
  if not public.user_has_store_access(v_inv.store_id) then
    raise exception 'You do not have access to this store''s invoices';
  end if;

  -- Validate the affiliate: p_affiliate_id is a customer_affiliates.id and must
  -- reference an ACTIVE affiliate (or be null to clear it).
  if p_affiliate_id is not null then
    select (a.status = 'active' and not coalesce(a.manually_suspended,false) and a.deleted_at is null),
           c.full_name
      into v_aff_ok, v_aff_name
      from public.customer_affiliates a
      join public.customers c on c.id = a.customer_id
     where a.id = p_affiliate_id;
    if not coalesce(v_aff_ok, false) then
      raise exception 'That affiliate is not active and cannot be selected';
    end if;
  end if;

  v_old := v_inv.affiliate_id;
  if v_old is not distinct from p_affiliate_id then
    return jsonb_build_object('success', true, 'unchanged', true, 'affiliate_id', p_affiliate_id);
  end if;

  update public.invoices set affiliate_id = p_affiliate_id where id = p_invoice_id;

  -- Revision history entry.
  select coalesce(max(revision_no),0) + 1 into v_rev
    from public.invoice_revisions where invoice_id = p_invoice_id;
  insert into public.invoice_revisions (invoice_id, revision_no, snapshot, edited_by, edit_reason)
  values (p_invoice_id, v_rev,
          jsonb_build_object('affiliate_changed', true, 'old_affiliate_id', v_old, 'new_affiliate_id', p_affiliate_id),
          auth.uid(), 'Affiliate ' || case when p_affiliate_id is null then 'removed' else 'selected' end);

  perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_affiliate_set',
    jsonb_build_object('affiliate_id', v_old),
    jsonb_build_object('affiliate_id', p_affiliate_id, 'affiliate_name', v_aff_name),
    'invoice', null, v_inv.store_id);

  return jsonb_build_object('success', true, 'affiliate_id', p_affiliate_id, 'affiliate_name', v_aff_name);
end $function$;

-- List of ACTIVE affiliates for the invoice affiliate picker.
create or replace function public.active_affiliates_for_picker()
returns table(affiliate_id uuid, customer_id uuid, full_name text, phone text, store_id uuid)
language sql stable security definer set search_path to 'public' as $function$
  select a.id, a.customer_id, c.full_name, c.phone, a.store_id
    from public.customer_affiliates a
    join public.customers c on c.id = a.customer_id
   where a.status = 'active' and not coalesce(a.manually_suspended,false) and a.deleted_at is null
     and c.deleted_at is null
   order by c.full_name
$function$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- 10. Commission calculators: read selling_price (M/NM columns are gone).
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.earn_invoice_commission(p_invoice_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_inv public.invoices%rowtype; v_tier1 uuid; v_tier2 uuid; v_item record;
  v_ptype text; v_line_after numeric; v_t1_rate numeric; v_t1_amt numeric; v_t2_amt numeric;
  v_paid_date date; v_own_orig numeric; v_third_orig numeric; v_tot_orig numeric; v_portion numeric;
  v_line_disc_sum numeric; v_invoice_level numeric; v_base_total numeric; v_line_net numeric;
  v_sel_own numeric; v_sel_third numeric; v_is_third boolean;
  v_t1_status text; v_t1_block text; v_t2_status text := 'earned'; v_t2_block text;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return; end if;

  select tier1, tier2 into v_tier1, v_tier2 from public.customer_referrers(v_inv.customer_id);
  if v_tier1 is null then return; end if;

  -- Phase 5: resolve each tier's affiliate eligibility INDEPENDENTLY. A tier
  -- that is not an eligible affiliate still gets its commission row, but with
  -- status='blocked' + reason, so it is visible for reports yet never paid and
  -- never released. Tier 1 blocked does not block Tier 2 and vice-versa.
  v_t1_status := case when public.is_eligible_affiliate(v_tier1) then 'earned' else 'blocked' end;
  v_t1_block := case when v_t1_status='blocked' then public.affiliate_block_reason(v_tier1) else null end;
  if v_tier2 is not null then
    v_t2_status := case when public.is_eligible_affiliate(v_tier2) then 'earned' else 'blocked' end;
    v_t2_block := case when v_t2_status='blocked' then public.affiliate_block_reason(v_tier2) else null end;
  end if;

  v_paid_date := coalesce(v_inv.paid_at, now())::date;
  select coalesce(sum(line_discount),0) into v_line_disc_sum from public.invoice_items where invoice_id = p_invoice_id;
  v_invoice_level := coalesce(v_inv.discount_total,0) - v_line_disc_sum;

  -- Allocation base excludes 3rd-party product lines (they are discount-proof).
  select coalesce(sum(ii.line_total - coalesce(ii.line_discount,0)),0) into v_base_total
  from public.invoice_items ii
  left join public.products p on p.id = ii.product_id
  where ii.invoice_id = p_invoice_id
    and not (ii.line_kind = 'product' and p.product_type::text = 'third_party');

  for v_item in
    select ii.id, ii.line_kind, ii.voucher_id, ii.promotion_id, ii.quantity, ii.line_total, ii.line_discount, ii.price_mode,
           coalesce(p.product_type::text, 'own') as ptype
    from public.invoice_items ii
    left join public.products p on p.id = ii.product_id
    where ii.invoice_id = p_invoice_id
  loop
    v_is_third := (v_item.line_kind = 'product' and v_item.ptype = 'third_party');
    v_line_net := v_item.line_total - coalesce(v_item.line_discount,0);
    if v_is_third then
      v_line_after := v_line_net;   -- never reduced by invoice-level discounts
    elsif v_base_total > 0 then
      v_line_after := v_line_net - (v_invoice_level * (v_line_net / v_base_total));
    else
      v_line_after := v_line_net;
    end if;
    if v_line_after < 0 then v_line_after := 0; end if;
    if v_line_after = 0 then continue; end if;

    if v_item.line_kind = 'promotion' then
      select
        coalesce(sum(case when ptype = 'third_party' then 0 else original_value end),0),
        coalesce(sum(case when ptype = 'third_party' then original_value else 0 end),0)
        into v_own_orig, v_third_orig
      from public.promotion_commission_items(v_item.promotion_id, v_inv.store_id, v_item.quantity, v_item.price_mode);

      select
        coalesce(sum(case
          when s.product_id is not null and coalesce(pp.product_type::text,'own') <> 'third_party'
            then coalesce(spp.selling_price, 0) * s.quantity
          when s.voucher_id is not null
            then coalesce(vsp.selling_price, vv.selling_price, 0) * s.quantity
          else 0 end),0),
        coalesce(sum(case
          when s.product_id is not null and coalesce(pp.product_type::text,'own') = 'third_party'
            then coalesce(spp.selling_price, 0) * s.quantity
          else 0 end),0)
        into v_sel_own, v_sel_third
      from public.invoice_promotion_selections s
      left join public.products pp on pp.id = s.product_id
      left join public.store_product_prices spp on spp.store_id = v_inv.store_id and spp.product_id = s.product_id
        and spp.is_active = true and spp.deleted_at is null
      left join public.vouchers vv on vv.id = s.voucher_id
      left join public.voucher_store_prices vsp on vsp.store_id = v_inv.store_id and vsp.voucher_id = s.voucher_id
        and vsp.deleted_at is null
      where s.invoice_item_id = v_item.id;

      v_own_orig := v_own_orig + v_sel_own;
      v_third_orig := v_third_orig + v_sel_third;
      v_tot_orig := v_own_orig + v_third_orig;
      if v_tot_orig <= 0 then v_own_orig := 1; v_third_orig := 0; v_tot_orig := 1; end if;

      if v_own_orig > 0 then
        v_portion := round(v_line_after * v_own_orig / v_tot_orig, 2);
        v_t1_amt := round(v_portion * 15 / 100.0, 2);
        if v_t1_amt > 0 then
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', 'own', v_portion, 15, v_t1_amt, v_t1_status::commission_status, v_t1_block, v_paid_date);
          if v_tier2 is not null then
            v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
            if v_t2_amt > 0 then
              insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
              values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', 'own', v_t1_amt, 5.0, v_t2_amt, v_t2_status::commission_status, v_t2_block, v_paid_date);
            end if;
          end if;
        end if;
      end if;

      if v_third_orig > 0 then
        v_portion := round(v_line_after * v_third_orig / v_tot_orig, 2);
        v_t1_amt := round(v_portion * 4.5 / 100.0, 2);
        if v_t1_amt > 0 then
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', 'third_party', v_portion, 4.5, v_t1_amt, v_t1_status::commission_status, v_t1_block, v_paid_date);
          if v_tier2 is not null then
            v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
            if v_t2_amt > 0 then
              insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
              values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', 'third_party', v_t1_amt, 5.0, v_t2_amt, v_t2_status::commission_status, v_t2_block, v_paid_date);
            end if;
          end if;
        end if;
      end if;

    else
      if v_item.line_kind = 'voucher' then v_ptype := 'own'; else v_ptype := v_item.ptype; end if;
      v_t1_rate := case when v_ptype = 'third_party' then 4.5 else 15 end;
      v_t1_amt := round(v_line_after * v_t1_rate / 100.0, 2);
      if v_t1_amt <= 0 then continue; end if;

      insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
      values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', v_ptype, v_line_after, v_t1_rate, v_t1_amt, v_t1_status::commission_status, v_t1_block, v_paid_date);

      if v_tier2 is not null then
        v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
        if v_t2_amt > 0 then
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', v_ptype, v_t1_amt, 5.0, v_t2_amt, v_t2_status::commission_status, v_t2_block, v_paid_date);
        end if;
      end if;
    end if;
  end loop;

  perform public.write_audit('commissions', p_invoice_id, 'commission_calculated', null,
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'tier1', v_tier1, 'tier2', v_tier2));
end; $function$;


CREATE OR REPLACE FUNCTION public.promotion_commission_items(p_promotion_id uuid, p_store_id uuid, p_multiplier integer DEFAULT 1)
 RETURNS TABLE(ptype text, original_value numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end; $function$;


----

CREATE OR REPLACE FUNCTION public.promotion_commission_items(p_promotion_id uuid, p_store_id uuid, p_multiplier integer, p_mode text)
 RETURNS TABLE(ptype text, original_value numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_item record; v_price numeric;
begin
  for v_item in select * from public.promotion_items where promotion_id = p_promotion_id
  loop
    if v_item.item_type = 'product' then
      select selling_price into v_price
        from public.store_product_prices
        where store_id = p_store_id and product_id = v_item.product_id
          and is_active = true and deleted_at is null;
      ptype := coalesce((select product_type::text from public.products where id = v_item.product_id), 'own');
      original_value := coalesce(v_price,0) * v_item.quantity * p_multiplier; return next;
    elsif v_item.item_type = 'voucher' then
      select coalesce(vsp.selling_price, v.selling_price) into v_price
        from public.vouchers v
        left join public.voucher_store_prices vsp
          on vsp.voucher_id = v.id and vsp.store_id = p_store_id and vsp.deleted_at is null
        where v.id = v_item.voucher_id;
      ptype := 'own';
      original_value := coalesce(v_price,0) * v_item.quantity * p_multiplier; return next;
    elsif v_item.item_type = 'treatment' then
      ptype := 'own'; original_value := 0; return next;
    elsif v_item.item_type = 'promotion' then
      return query select * from public.promotion_commission_items(v_item.child_promotion_id, p_store_id, v_item.quantity * p_multiplier, p_mode);
    end if;
  end loop;
end; $function$;

CREATE OR REPLACE FUNCTION public.promotion_commission_items(p_promotion_id uuid, p_store_id uuid, p_multiplier integer, p_mode text)
 RETURNS TABLE(ptype text, original_value numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_item record; v_price numeric;
begin
  for v_item in select * from public.promotion_items where promotion_id = p_promotion_id
  loop
    if v_item.item_type = 'product' then
      select selling_price
        into v_price
        from public.store_product_prices
        where store_id = p_store_id and product_id = v_item.product_id
          and is_active = true and deleted_at is null;
      ptype := coalesce((select product_type::text from public.products where id = v_item.product_id), 'own');
      original_value := coalesce(v_price,0) * v_item.quantity * p_multiplier; return next;
    elsif v_item.item_type = 'voucher' then
      select coalesce(vsp.selling_price, v.selling_price)
        into v_price
        from public.vouchers v
        left join public.voucher_store_prices vsp
          on vsp.voucher_id = v.id and vsp.store_id = p_store_id and vsp.deleted_at is null
        where v.id = v_item.voucher_id;
      ptype := 'own';
      original_value := coalesce(v_price,0) * v_item.quantity * p_multiplier; return next;
    elsif v_item.item_type = 'treatment' then
      ptype := 'own'; original_value := 0; return next;
    elsif v_item.item_type = 'promotion' then
      return query select * from public.promotion_commission_items(v_item.child_promotion_id, p_store_id, v_item.quantity * p_multiplier, p_mode);
    end if;
  end loop;
end; $function$;


-- ---------------------------------------------------------------------
-- 9b. Repoint invoices.affiliate_id at the live affiliate registry.
--     The legacy public.affiliates table is unused (no invoice ever set
--     it, and commission is derived from customers.referred_by). Point the
--     column at customer_affiliates so a selected invoice affiliate is a
--     real, active affiliate. Guarded/idempotent.
-- ---------------------------------------------------------------------
do $fk$
begin
  if exists (select 1 from pg_constraint where conname = 'invoices_affiliate_id_fkey'
              and confrelid = 'public.affiliates'::regclass) then
    -- Any legacy non-null affiliate_id values cannot map to customer_affiliates;
    -- none exist in practice, but null them defensively to satisfy the new FK.
    update public.invoices i set affiliate_id = null
     where affiliate_id is not null
       and not exists (select 1 from public.customer_affiliates a where a.id = i.affiliate_id);
    alter table public.invoices drop constraint invoices_affiliate_id_fkey;
    alter table public.invoices
      add constraint invoices_affiliate_id_fkey
      foreign key (affiliate_id) references public.customer_affiliates(id) on delete set null;
  end if;
end $fk$;

notify pgrst, 'reload schema';
