-- =====================================================================
-- ENERGIA — PHASE 5D-4: Top-up pricing for product choice groups
--
-- Product choice groups now work as: the listed options define the
-- BASELINE price (the cheapest option at the invoice's store), and the
-- customer may choose ANY product. If the chosen product's store price is
-- above the baseline, the difference is added to the invoice as a top-up.
-- Cheaper picks pay no extra and get no discount.
--   e.g. options {A:300, B:310}, bundle 399 → A: 399; B: 399;
--        C (500): 399 + (500−300) = 599; D (200): 399.
-- Voucher choice groups are unchanged: listed options only, no top-up.
--
-- Additive + idempotent. Run AFTER 20_phase5d3_choices_line_vouchers.sql.
-- =====================================================================

set check_function_bodies = off;

alter table public.invoice_items add column if not exists topup_amount numeric(12,2) not null default 0;

-- ---------------------------------------------------------------------
-- 1. Top-up for one promotion line's selections at a store.
--    Only product-kind groups contribute. Baseline per group = MIN store
--    price among that group's listed product options; no priced options →
--    no baseline → no top-up for that group.
-- ---------------------------------------------------------------------
create or replace function public.promotion_selections_topup(
  p_promotion_id uuid, p_store_id uuid, p_selections jsonb
) returns numeric language plpgsql stable security definer set search_path = public as $$
declare
  v_grp record; v_sel jsonb; v_opt jsonb; v_baseline numeric; v_price numeric;
  v_topup numeric := 0; v_qty integer;
begin
  for v_grp in select * from public.promotion_choice_groups
    where promotion_id = p_promotion_id and item_kind = 'product'
  loop
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
        v_qty := coalesce((v_opt->>'quantity')::integer,0);
        if v_qty <= 0 or (v_opt->>'product_id') is null then continue; end if;
        -- LISTED options never pay a top-up: they are all covered by the
        -- bundle price, whatever their individual prices. Only products
        -- OUTSIDE the group's options pay the difference above the baseline.
        if exists (
          select 1 from public.promotion_choice_options o
          where o.group_id = v_grp.id and o.product_id = (v_opt->>'product_id')::uuid
        ) then continue; end if;
        select selling_price into v_price from public.store_product_prices
          where store_id = p_store_id and product_id = (v_opt->>'product_id')::uuid
            and is_active = true and deleted_at is null;
        if v_price is not null and v_price > v_baseline then
          v_topup := v_topup + (v_price - v_baseline) * v_qty;
        end if;
      end loop;
    end loop;
  end loop;
  return round(v_topup, 2);
end; $$;

-- ---------------------------------------------------------------------
-- 2. create_invoice — product-group picks may be ANY product (must be
--    priced at the store); voucher-group picks must be listed options.
--    Promotion line total = fixed price × qty + top-up.
-- ---------------------------------------------------------------------
create or replace function public.create_invoice(
  p_store_id uuid, p_customer_id uuid, p_affiliate_id uuid,
  p_items jsonb, p_discount_total numeric default 0, p_notes text default null,
  p_discount_voucher_id uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_item jsonb; v_kind text; v_product_id uuid; v_voucher_id uuid; v_promo_id uuid;
  v_qty integer; v_price numeric; v_subtotal numeric := 0; v_line_total numeric;
  v_invoice_id uuid; v_invoice_no text; v_manual numeric := coalesce(p_discount_total,0);
  v_has_promo boolean := false; v_promo public.promotions%rowtype;
  v_line_voucher uuid; v_line_disc numeric; v_line_disc_sum numeric := 0;
  v_lv public.vouchers%rowtype; v_discount numeric;
  v_grp record; v_sel jsonb; v_opt jsonb; v_provided integer; v_required integer;
  v_item_id uuid; v_sel_group uuid; v_ok boolean; v_topup numeric;
begin
  if not public.user_has_store_access(p_store_id) then raise exception 'You do not have access to this store'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'At least one item is required'; end if;

  -- PASS 1: validate + price + accumulate subtotal and line discounts.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantity must be greater than zero'; end if;

    if v_kind = 'promotion' then
      v_has_promo := true;
      v_promo_id := (v_item->>'promotion_id')::uuid;
      select * into v_promo from public.promotions where id = v_promo_id and deleted_at is null;
      if not found then raise exception 'Promotion not found'; end if;
      if not v_promo.is_active then raise exception 'Promotion "%" is not active', v_promo.name; end if;
      if v_promo.start_date is not null and now()::date < v_promo.start_date then raise exception 'Promotion "%" has not started yet', v_promo.name; end if;
      if v_promo.end_date is not null and now()::date > v_promo.end_date then raise exception 'Promotion "%" has ended', v_promo.name; end if;

      -- Validate choice selections group by group.
      for v_grp in select * from public.promotion_choice_groups where promotion_id = v_promo_id
      loop
        v_required := v_grp.choose_qty * v_qty;
        v_provided := 0;
        for v_sel in select * from jsonb_array_elements(coalesce(v_item->'selections','[]'::jsonb))
        loop
          if (v_sel->>'group_id')::uuid = v_grp.id then
            for v_opt in select * from jsonb_array_elements(coalesce(v_sel->'options','[]'::jsonb))
            loop
              if coalesce((v_opt->>'quantity')::integer,0) <= 0 then continue; end if;
              if v_grp.item_kind = 'voucher' then
                -- voucher picks must be listed options
                select exists (
                  select 1 from public.promotion_choice_options o
                  where o.group_id = v_grp.id
                    and (v_opt->>'voucher_id') is not null and o.voucher_id = (v_opt->>'voucher_id')::uuid
                ) into v_ok;
                if not v_ok then raise exception 'A selected voucher does not belong to choice group "%"', v_grp.label; end if;
              else
                -- product picks: ANY product, but it must be priced at this store
                if (v_opt->>'product_id') is null then raise exception 'Choice group "%" expects product selections', v_grp.label; end if;
                select exists (
                  select 1 from public.store_product_prices
                  where store_id = p_store_id and product_id = (v_opt->>'product_id')::uuid
                    and is_active = true and deleted_at is null
                ) into v_ok;
                if not v_ok then
                  raise exception 'Product "%" has no price at this store, so it cannot be chosen in "%"',
                    (select name from public.products where id = (v_opt->>'product_id')::uuid), v_grp.label;
                end if;
              end if;
              v_provided := v_provided + (v_opt->>'quantity')::integer;
            end loop;
          end if;
        end loop;
        if v_provided <> v_required then
          raise exception 'Choice group "%" requires % selection(s), got %', v_grp.label, v_required, v_provided;
        end if;
      end loop;

      v_topup := public.promotion_selections_topup(v_promo_id, p_store_id, v_item->'selections');
      v_subtotal := v_subtotal + (v_promo.fixed_price * v_qty) + v_topup;

    elsif v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      select selling_price into v_price from public.vouchers
        where id = v_voucher_id and is_active = true and deleted_at is null;
      if v_price is null then raise exception 'Voucher not found or inactive'; end if;
      v_subtotal := v_subtotal + (v_price * v_qty);
    else
      v_product_id := (v_item->>'product_id')::uuid;
      select selling_price into v_price from public.store_product_prices
        where store_id = p_store_id and product_id = v_product_id and is_active = true and deleted_at is null;
      if v_price is null then raise exception 'No price set for a product in this store'; end if;
      v_line_total := v_price * v_qty;
      v_subtotal := v_subtotal + v_line_total;

      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      if v_line_voucher is not null then
        select * into v_lv from public.vouchers where id = v_line_voucher and deleted_at is null;
        if not found then raise exception 'Line voucher not found'; end if;
        if v_lv.voucher_kind = 'normal' then raise exception 'Voucher "%" is not a discount voucher', v_lv.name; end if;
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
        v_line_disc_sum := v_line_disc_sum + v_line_disc;
      end if;
    end if;
  end loop;

  if p_discount_voucher_id is not null and v_has_promo then
    raise exception 'A whole-invoice discount voucher cannot be used when the invoice contains a promotion/bundle. Use per-product vouchers instead.';
  end if;

  v_discount := v_manual + v_line_disc_sum;
  if p_discount_voucher_id is not null then
    v_discount := v_discount + public.voucher_discount_amount(p_discount_voucher_id, v_subtotal - v_discount);
  end if;
  if v_discount > v_subtotal then v_discount := v_subtotal; end if;

  v_invoice_no := public.next_invoice_no();
  insert into public.invoices
    (invoice_no, store_id, customer_id, affiliate_id, created_by, status,
     subtotal, discount_total, total_amount, paid_amount, notes, discount_voucher_id)
  values (v_invoice_no, p_store_id, p_customer_id, p_affiliate_id, auth.uid(), 'unpaid',
          v_subtotal, v_discount, v_subtotal - v_discount, 0, p_notes, p_discount_voucher_id)
  returning id into v_invoice_id;

  -- PASS 2: insert lines (+ selections).
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    if v_kind = 'promotion' then
      v_promo_id := (v_item->>'promotion_id')::uuid;
      select fixed_price into v_price from public.promotions where id = v_promo_id;
      v_topup := public.promotion_selections_topup(v_promo_id, p_store_id, v_item->'selections');
      insert into public.invoice_items (invoice_id, line_kind, promotion_id, product_id, quantity, unit_price, line_total, topup_amount)
      values (v_invoice_id, 'promotion', v_promo_id, null, v_qty, v_price, (v_price * v_qty) + v_topup, v_topup)
      returning id into v_item_id;

      for v_sel in select * from jsonb_array_elements(coalesce(v_item->'selections','[]'::jsonb))
      loop
        v_sel_group := (v_sel->>'group_id')::uuid;
        for v_opt in select * from jsonb_array_elements(coalesce(v_sel->'options','[]'::jsonb))
        loop
          if coalesce((v_opt->>'quantity')::integer,0) <= 0 then continue; end if;
          insert into public.invoice_promotion_selections (invoice_item_id, group_id, product_id, voucher_id, quantity)
          values (v_item_id, v_sel_group,
                  nullif(v_opt->>'product_id','')::uuid, nullif(v_opt->>'voucher_id','')::uuid,
                  (v_opt->>'quantity')::integer);
        end loop;
      end loop;

    elsif v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      select selling_price into v_price from public.vouchers where id = v_voucher_id;
      insert into public.invoice_items (invoice_id, line_kind, voucher_id, product_id, quantity, unit_price, line_total)
      values (v_invoice_id, 'voucher', v_voucher_id, null, v_qty, v_price, v_price * v_qty);
    else
      v_product_id := (v_item->>'product_id')::uuid;
      select selling_price into v_price from public.store_product_prices
        where store_id = p_store_id and product_id = v_product_id and is_active = true and deleted_at is null;
      v_line_total := v_price * v_qty;
      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      v_line_disc := 0;
      if v_line_voucher is not null then
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
      end if;
      insert into public.invoice_items (invoice_id, line_kind, product_id, quantity, unit_price, line_total, line_voucher_id, line_discount)
      values (v_invoice_id, 'product', v_product_id, v_qty, v_price, v_line_total, v_line_voucher, v_line_disc);
    end if;
  end loop;

  perform public.write_audit('invoices', v_invoice_id, 'invoice_created', null,
    jsonb_build_object('invoice_no', v_invoice_no, 'total', v_subtotal - v_discount,
                       'has_promotion', v_has_promo, 'line_voucher_discounts', v_line_disc_sum));
  return v_invoice_id;
end; $$;

notify pgrst, 'reload schema';
