-- =====================================================================
-- ENERGIA — 54: create_invoice therapy support (direct therapy on invoice)
--
-- Adds a 'therapy' branch to create_invoice's validation and insert loops so
-- Unlimited Therapy can be sold directly in the New Invoice builder, including
-- therapy-only invoices. Identical function signature (returns uuid), so
-- CREATE OR REPLACE is safe — no DROP needed.
--
-- Preserves every existing branch (membership / promotion / voucher / product)
-- byte-for-byte; only the therapy branch and its declarations are new.
--
-- Additive + idempotent. Run AFTER 53.
-- =====================================================================

set check_function_bodies = off;

create or replace function public.create_invoice(
  p_store_id uuid, p_customer_id uuid, p_affiliate_id uuid,
  p_items jsonb, p_discount_total numeric default 0, p_notes text default null,
  p_discount_voucher_id uuid default null, p_service_staff jsonb default '[]'::jsonb
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
  v_ptype text; v_third_sum numeric := 0; v_discountable numeric; v_wbase numeric;
  v_ss jsonb; v_ss_id uuid; v_ss_role user_role;
  -- membership / mode additions
  v_ms jsonb; v_is_member boolean; v_membership_count integer := 0;
  v_plan_id uuid; v_mp jsonb; v_member_id text; v_owned_id text; v_is_renewal boolean := false;
  v_mode_ovr text; v_ovr_reason text; v_pj jsonb; v_use_member boolean; v_mode text;
  v_therapy_pkg uuid; v_therapy_name text; v_therapy_months integer;
begin
  if public.current_user_role() is null then raise exception 'No profile for current user'; end if;
  if not public.user_has_store_access(p_store_id) then raise exception 'You do not have access to this store'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'At least one item is required'; end if;
  if p_customer_id is null then raise exception 'A customer is required'; end if;

  -- Membership context: current (covers today) + whether this invoice sells one.
  v_ms := public.customer_membership_status(p_customer_id);
  select count(*) into v_membership_count
    from jsonb_array_elements(p_items) x where coalesce(x->>'kind','product') = 'membership';
  if v_membership_count > 1 then raise exception 'Only one membership line is allowed per invoice'; end if;
  v_is_member := coalesce((v_ms->>'is_member')::boolean, false) or v_membership_count = 1;

  if v_membership_count = 1 then
    if coalesce((v_ms->>'has_future_renewal')::boolean, false) then
      raise exception 'This customer already has a scheduled renewal'; end if;
    v_is_renewal := coalesce((v_ms->>'is_member')::boolean, false);
    select member_id into v_owned_id from public.member_ids where customer_id = p_customer_id;
  end if;

  -- PASS 1: validate + price (mode-aware, strict) + accumulate.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantity must be greater than zero'; end if;
    v_mode_ovr := nullif(v_item->>'price_mode_override','');
    v_ovr_reason := nullif(trim(coalesce(v_item->>'override_reason','')),'');
    if v_mode_ovr is not null and v_mode_ovr not in ('member','non_member') then
      raise exception 'Invalid price mode override'; end if;
    if v_mode_ovr is not null and v_ovr_reason is null then
      raise exception 'An override reason is required when overriding a line price mode'; end if;
    v_use_member := coalesce(v_mode_ovr = 'member', v_is_member);

    if v_kind = 'membership' then
      if v_qty <> 1 then raise exception 'A membership line must have quantity 1'; end if;
      if v_mode_ovr is not null then raise exception 'Member/Non-Member override does not apply to a membership line'; end if;
      v_plan_id := (v_item->>'plan_id')::uuid;
      v_mp := public.membership_price_for(p_store_id, v_plan_id);
      if not coalesce((v_mp->>'found')::boolean,false) then raise exception 'Membership plan not found'; end if;
      if coalesce((v_mp->>'is_system')::boolean,false) or coalesce((v_mp->>'is_complimentary')::boolean,false) then
        raise exception 'Plan "%" is protected and cannot be sold', v_mp->>'plan_name'; end if;
      if not coalesce((v_mp->>'is_active')::boolean,false) then
        raise exception 'Plan "%" is not active', v_mp->>'plan_name'; end if;
      if not coalesce((v_mp->>'available')::boolean,false) or (v_mp->>'fee') is null then
        raise exception 'Plan "%" has no active price at this store', v_mp->>'plan_name'; end if;

      v_member_id := nullif(trim(coalesce(v_item->>'member_id','')),'');
      if v_is_renewal then
        -- Renewal reuses the customer's permanent Member ID automatically.
        if v_member_id is not null and v_owned_id is not null and v_member_id <> v_owned_id then
          raise exception 'Renewal must keep the existing Member ID (%)', v_owned_id; end if;
      elsif v_member_id is not null then
        if not public.member_id_available(v_member_id, p_customer_id) then
          raise exception 'Member ID % is already taken', v_member_id; end if;
      end if;
      v_subtotal := v_subtotal + (v_mp->>'fee')::numeric;

    elsif v_kind = 'promotion' then
      v_has_promo := true;
      v_promo_id := (v_item->>'promotion_id')::uuid;
      select * into v_promo from public.promotions where id = v_promo_id and deleted_at is null;
      if not found then raise exception 'Promotion not found'; end if;
      if not v_promo.is_active then raise exception 'Promotion "%" is not active', v_promo.name; end if;
      if v_promo.start_date is not null and now()::date < v_promo.start_date then raise exception 'Promotion "%" has not started yet', v_promo.name; end if;
      if v_promo.end_date is not null and now()::date > v_promo.end_date then raise exception 'Promotion "%" has ended', v_promo.name; end if;
      -- Members-only rule (override or same-invoice membership lifts it).
      if not v_is_member and v_mode_ovr is null then
        raise exception 'Promotions are for members only. Add a membership to this invoice or apply a manual override.'; end if;

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
                select exists (
                  select 1 from public.promotion_choice_options o
                  where o.group_id = v_grp.id
                    and (v_opt->>'voucher_id') is not null and o.voucher_id = (v_opt->>'voucher_id')::uuid
                ) into v_ok;
                if not v_ok then raise exception 'A selected voucher does not belong to choice group "%"', v_grp.label; end if;
              else
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

      v_pj := public.promotion_price_for(p_store_id, v_promo_id, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Promotion "%" is missing its % price at this store', v_promo.name,
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_topup := public.promotion_selections_topup(v_promo_id, p_store_id, v_item->'selections', v_use_member);
      v_subtotal := v_subtotal + ((v_pj->>'price')::numeric * v_qty) + v_topup;

    elsif v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      perform 1 from public.vouchers where id = v_voucher_id and is_active = true and deleted_at is null;
      if not found then raise exception 'Voucher not found or inactive'; end if;
      v_pj := public.voucher_price_for(p_store_id, v_voucher_id, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Voucher "%" is missing its % price at this store',
          (select name from public.vouchers where id = v_voucher_id),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_subtotal := v_subtotal + ((v_pj->>'price')::numeric * v_qty);

    elsif v_kind = 'therapy' then
      if v_qty <> 1 then raise exception 'A therapy line must have quantity 1'; end if;
      v_therapy_pkg := (v_item->>'therapy_package_id')::uuid;
      perform 1 from public.unlimited_therapy_packages where id = v_therapy_pkg and is_active = true and deleted_at is null;
      if not found then raise exception 'Therapy package not found or inactive'; end if;
      -- One entitlement per package per live window.
      if exists (select 1 from public.purchased_therapy_entitlements
                  where customer_id = p_customer_id and package_id = v_therapy_pkg
                    and status in ('active','scheduled','pending_activation')) then
        raise exception 'This customer already has a current entitlement for this therapy package'; end if;
      v_pj := public.therapy_price_for(p_store_id, v_therapy_pkg, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Therapy package "%" is missing its % price at this store',
          (select name from public.unlimited_therapy_packages where id = v_therapy_pkg),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_subtotal := v_subtotal + ((v_pj->>'price')::numeric * v_qty);

    else
      v_product_id := (v_item->>'product_id')::uuid;
      select p.product_type::text into v_ptype from public.products p where p.id = v_product_id;
      v_pj := public.product_price_for(p_store_id, v_product_id, v_use_member);
      if not coalesce((v_pj->>'found')::boolean,false) then
        raise exception 'No price set for "%" in this store',
          (select name from public.products where id = v_product_id); end if;
      if v_mode_ovr is null and not coalesce((v_pj->>'eligible')::boolean,false) then
        raise exception 'Product "%" is % — not sellable to this customer without a manual override',
          (select name from public.products where id = v_product_id),
          replace(v_pj->>'eligibility','_',' '); end if;
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Product "%" is missing its % price at this store',
          (select name from public.products where id = v_product_id),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_price := (v_pj->>'price')::numeric;
      v_line_total := v_price * v_qty;
      v_subtotal := v_subtotal + v_line_total;
      if v_ptype = 'third_party' then v_third_sum := v_third_sum + v_line_total; end if;

      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      if v_line_voucher is not null then
        if v_ptype = 'third_party' then
          raise exception 'Discounts cannot be applied to third-party products ("%")',
            (select name from public.products where id = v_product_id);
        end if;
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

  v_discountable := v_subtotal - v_third_sum;
  v_discount := v_manual + v_line_disc_sum;
  if p_discount_voucher_id is not null then
    v_wbase := v_discountable - v_manual - v_line_disc_sum;
    if v_wbase < 0 then v_wbase := 0; end if;
    v_discount := v_discount + public.voucher_discount_amount(p_discount_voucher_id, v_wbase);
  end if;
  if v_discount > v_discountable then v_discount := v_discountable; end if;

  v_invoice_no := public.next_invoice_no();
  insert into public.invoices
    (invoice_no, store_id, customer_id, affiliate_id, created_by, status,
     subtotal, discount_total, manual_discount, total_amount, paid_amount, notes, discount_voucher_id)
  values (v_invoice_no, p_store_id, p_customer_id, p_affiliate_id, auth.uid(), 'unpaid',
          v_subtotal, v_discount, v_manual, v_subtotal - v_discount, 0, p_notes, p_discount_voucher_id)
  returning id into v_invoice_id;

  for v_ss in select * from jsonb_array_elements(coalesce(p_service_staff, '[]'::jsonb))
  loop
    v_ss_id := (v_ss#>>'{}')::uuid;
    if v_ss_id is null then continue; end if;
    select role into v_ss_role from public.profiles where id = v_ss_id and is_active = true and deleted_at is null;
    if v_ss_role is null then raise exception 'A selected service staff was not found or is inactive'; end if;
    if v_ss_role not in ('owner','manager','staff') then
      raise exception 'Service staff must be Owner, Manager, or Staff (got %)', v_ss_role;
    end if;
    insert into public.invoice_service_staff (invoice_id, staff_id)
    values (v_invoice_id, v_ss_id) on conflict (invoice_id, staff_id) do nothing;
  end loop;

  -- PASS 2: insert lines with permanent snapshots.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    v_mode_ovr := nullif(v_item->>'price_mode_override','');
    v_ovr_reason := nullif(trim(coalesce(v_item->>'override_reason','')),'');
    v_use_member := coalesce(v_mode_ovr = 'member', v_is_member);
    v_mode := case when v_use_member then 'member' else 'non_member' end;

    if v_kind = 'membership' then
      v_plan_id := (v_item->>'plan_id')::uuid;
      v_mp := public.membership_price_for(p_store_id, v_plan_id);
      v_member_id := case when v_is_renewal then v_owned_id
                          else nullif(trim(coalesce(v_item->>'member_id','')),'') end;
      insert into public.invoice_items
        (invoice_id, line_kind, product_id, quantity, unit_price, line_total,
         membership_plan_id, price_source, price_source_id, store_id_snapshot,
         plan_name_snapshot, plan_months_snapshot, member_id_snapshot, original_price)
      values (v_invoice_id, 'membership', null, 1, (v_mp->>'fee')::numeric, (v_mp->>'fee')::numeric,
              v_plan_id, 'membership', (v_mp->>'source_id')::uuid, p_store_id,
              v_mp->>'plan_name', (v_mp->>'duration_months')::integer, v_member_id, (v_mp->>'fee')::numeric);
      -- Reserve a NEW member's ID now the invoice exists; renewals reuse theirs.
      if not v_is_renewal and v_member_id is not null then
        perform public.reserve_member_id(v_member_id, p_customer_id, v_invoice_id);
      end if;

    elsif v_kind = 'promotion' then
      v_promo_id := (v_item->>'promotion_id')::uuid;
      v_pj := public.promotion_price_for(p_store_id, v_promo_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_topup := public.promotion_selections_topup(v_promo_id, p_store_id, v_item->'selections', v_use_member);
      insert into public.invoice_items
        (invoice_id, line_kind, promotion_id, product_id, quantity, unit_price, line_total, topup_amount,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         price_overridden, override_reason, override_by, override_at)
      values (v_invoice_id, 'promotion', v_promo_id, null, v_qty, v_price, (v_price * v_qty) + v_topup, v_topup,
              v_mode, case when v_mode_ovr is null then 'promotion' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, p_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end)
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
      v_pj := public.voucher_price_for(p_store_id, v_voucher_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      insert into public.invoice_items
        (invoice_id, line_kind, voucher_id, product_id, quantity, unit_price, line_total,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         price_overridden, override_reason, override_by, override_at)
      values (v_invoice_id, 'voucher', v_voucher_id, null, v_qty, v_price, v_price * v_qty,
              v_mode, case when v_mode_ovr is null then 'voucher' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, p_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end);
    elsif v_kind = 'therapy' then
      v_therapy_pkg := (v_item->>'therapy_package_id')::uuid;
      v_pj := public.therapy_price_for(p_store_id, v_therapy_pkg, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      select name, duration_months into v_therapy_name, v_therapy_months
        from public.unlimited_therapy_packages where id = v_therapy_pkg;
      insert into public.invoice_items
        (invoice_id, line_kind, product_id, therapy_package_id, quantity, unit_price, line_total,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         plan_name_snapshot, plan_months_snapshot,
         price_overridden, override_reason, override_by, override_at)
      values (v_invoice_id, 'therapy', null, v_therapy_pkg, 1, v_price, v_price,
              v_mode, case when v_mode_ovr is null then 'therapy' else 'manual_override' end,
              v_therapy_pkg, p_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_therapy_name, v_therapy_months,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end);
    else
      v_product_id := (v_item->>'product_id')::uuid;
      v_pj := public.product_price_for(p_store_id, v_product_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_line_total := v_price * v_qty;
      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      v_line_disc := 0;
      if v_line_voucher is not null then
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
      end if;
      insert into public.invoice_items
        (invoice_id, line_kind, product_id, quantity, unit_price, line_total, line_voucher_id, line_discount,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         price_overridden, override_reason, override_by, override_at)
      values (v_invoice_id, 'product', v_product_id, v_qty, v_price, v_line_total, v_line_voucher, v_line_disc,
              v_mode, case when v_mode_ovr is null then 'product' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, p_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end);
    end if;
  end loop;

  perform public.write_audit('invoices', v_invoice_id, 'invoice_created', null,
    jsonb_build_object('invoice_no', v_invoice_no, 'total', v_subtotal - v_discount,
                       'has_promotion', v_has_promo, 'third_party_total', v_third_sum,
                       'is_member_pricing', v_is_member, 'has_membership_line', v_membership_count = 1,
                       'is_renewal', v_is_renewal));
  return v_invoice_id;
end; $$;
notify pgrst, 'reload schema';
