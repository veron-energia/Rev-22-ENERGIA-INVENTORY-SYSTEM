-- Invoice corrections foundation. Run after 163; 164-169 reserved for survey work.
-- Explicit canonical update_invoice definition replaces the accumulated text patches.
-- Existing invoice and line primary keys are retained. No data cleanup/backfill.
begin;
set local check_function_bodies = on;

create or replace function public.invoice_line_matches(p_item_id uuid,p_line jsonb)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare i public.invoice_items%rowtype; k text; a jsonb; b jsonb;
begin
  select * into i from public.invoice_items where id=p_item_id;
  if not found then return false; end if;
  if i.line_kind::text<>coalesce(p_line->>'kind','product') or i.quantity<>coalesce((p_line->>'quantity')::integer,0) then return false; end if;
  foreach k in array array['product_id','voucher_id','promotion_id','therapy_package_id','special_product_id','credit_package_id','premium_bundle_id','line_voucher_id'] loop
    if nullif(to_jsonb(i)->>k,'') is distinct from nullif(p_line->>k,'') then return false; end if;
  end loop;
  if coalesce(i.foc_quantity,0)<>coalesce((p_line->>'foc_quantity')::integer,0)
    or nullif(i.foc_reason_id::text,'') is distinct from nullif(p_line->>'foc_reason_id','')
    or nullif(i.foc_reason,'') is distinct from nullif(p_line->>'foc_reason','') then return false; end if;
  if p_line ? 'unit_price' and (p_line->>'unit_price')::numeric is distinct from i.unit_price then return false; end if;
  if i.line_kind='rental' then
    foreach k in array array['rental_rate_type','rental_periods','rental_start_date','rental_return_date'] loop
      if nullif(to_jsonb(i)->>k,'') is distinct from nullif(p_line->>k,'') then return false; end if;
    end loop;
  end if;
  if i.line_kind='premium_bundle' then
    select coalesce(jsonb_agg(x order by x->>'voucher_id'),'[]') into a from jsonb_array_elements(coalesce(i.bundle_voucher_selection,'[]')) x;
    select coalesce(jsonb_agg(x order by x->>'voucher_id'),'[]') into b from jsonb_array_elements(coalesce(p_line->'voucher_selection','[]')) x;
    if a<>b then return false; end if;
  end if;
  if i.line_kind='promotion' then
    select coalesce(jsonb_agg(jsonb_build_array(group_id,product_id,voucher_id,quantity) order by group_id,product_id,voucher_id),'[]') into a
      from public.invoice_promotion_selections where invoice_item_id=i.id;
    select coalesce(jsonb_agg(jsonb_build_array((g->>'group_id')::uuid,nullif(o->>'product_id','')::uuid,nullif(o->>'voucher_id','')::uuid,(o->>'quantity')::int)
      order by (g->>'group_id')::uuid,nullif(o->>'product_id','')::uuid,nullif(o->>'voucher_id','')::uuid),'[]') into b
      from jsonb_array_elements(coalesce(p_line->'selections','[]')) g,
           jsonb_array_elements(coalesce(g->'options','[]')) o where coalesce((o->>'quantity')::int,0)>0;
    if a<>b then return false; end if;
  end if;
  return true;
end $$;
revoke all on function public.invoice_line_matches(uuid,jsonb) from public,anon,authenticated;

create or replace function public.invoice_operational_lines_match(p_invoice_id uuid,p_items jsonb)
returns boolean language sql stable security definer set search_path=public as $$
 select jsonb_array_length(p_items)=(select count(*) from public.invoice_items where invoice_id=p_invoice_id)
 and (select count(distinct x->>'invoice_item_id') from jsonb_array_elements(p_items) x)=jsonb_array_length(p_items)
 and not exists(select 1 from jsonb_array_elements(p_items) x left join public.invoice_items it on it.id=nullif(x->>'invoice_item_id','')::uuid
  where it.invoice_id is distinct from p_invoice_id or not public.invoice_line_matches(it.id,x||jsonb_build_object(
   'unit_price',it.unit_price,'foc_quantity',it.foc_quantity,'foc_reason_id',it.foc_reason_id,'foc_reason',it.foc_reason,'line_voucher_id',it.line_voucher_id)))
$$;
revoke all on function public.invoice_operational_lines_match(uuid,jsonb) from public,anon,authenticated;

-- Unchanged FOC allocations retain historical reasons, including inactive ones.
create or replace function public.invoice_foc_reason(p_invoice_id uuid,p_line jsonb)
returns text language plpgsql stable security definer set search_path=public as $$
declare it public.invoice_items%rowtype; rid uuid:=nullif(p_line->>'foc_reason_id','')::uuid;
 note text:=nullif(trim(p_line->>'foc_reason'),''); v_label text; qty int;
begin
 qty:=case when coalesce((p_line->>'is_foc')::boolean,false) then (p_line->>'quantity')::int else coalesce((p_line->>'foc_quantity')::int,0) end;
 select * into it from public.invoice_items where id=nullif(p_line->>'invoice_item_id','')::uuid and invoice_id=p_invoice_id;
 if found and qty=it.foc_quantity and rid is not distinct from it.foc_reason_id and note is not distinct from nullif(trim(it.foc_reason),'') then return it.foc_reason; end if;
 select r.label into v_label from public.foc_reasons r where id=rid;
 if note=v_label then note:=null;
 elsif left(note,length(v_label)+3)=v_label||' — ' then note:=substring(note from length(v_label)+4); end if;
 return public.foc_reason_resolve(rid,note);
end $$;
revoke all on function public.invoice_foc_reason(uuid,jsonb) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.update_invoice(p_invoice_id uuid, p_customer_id uuid, p_affiliate_id uuid, p_items jsonb, p_discount_total numeric DEFAULT 0, p_notes text DEFAULT NULL::text, p_discount_voucher_id uuid DEFAULT NULL::uuid, p_service_staff jsonb DEFAULT '[]'::jsonb, p_edit_reason text DEFAULT NULL::text, p_allow_settled boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_item jsonb; v_kind text; v_product_id uuid; v_voucher_id uuid; v_promo_id uuid;
  v_qty integer; v_price numeric; v_subtotal numeric := 0; v_line_total numeric;
  v_original_line public.invoice_items%rowtype; v_invoice_no text; v_manual numeric := coalesce(p_discount_total,0);
  v_has_promo boolean := false; v_promo public.promotions%rowtype;
  v_line_voucher uuid; v_line_disc numeric; v_line_disc_sum numeric := 0;
  v_lv public.vouchers%rowtype; v_discount numeric;
  v_grp record; v_sel jsonb; v_opt jsonb; v_provided integer; v_required integer;
  v_item_id uuid; v_sel_group uuid; v_ok boolean; v_topup numeric;
  v_ptype text; v_third_sum numeric := 0; v_discountable numeric; v_wbase numeric;
  v_manual_base numeric; v_manual_capped numeric;
  v_ss jsonb; v_ss_id uuid; v_ss_role user_role;
  v_is_member boolean := true;
  v_mode_ovr text; v_ovr_reason text; v_pj jsonb; v_use_member boolean; v_mode text;
  v_therapy_pkg uuid; v_therapy_name text; v_therapy_months integer;
  -- Phase 13 edit context
  v_store_id uuid; v_old public.invoices%rowtype; v_rev integer; v_snapshot jsonb;
  -- FOC additions
  v_foc_qty integer; v_foc_amt numeric; v_gross numeric;
  v_foc_rid uuid; v_foc_rtext text; v_foc_resolved text; v_foc_total numeric := 0;
begin
  -- A caller must never bypass settled-invoice authorization via the public flag.
  if p_invoice_id is null then raise exception 'An existing invoice ID is required'; end if;
  if p_allow_settled and not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can correct a settled invoice'; end if;
  if p_allow_settled and nullif(trim(p_edit_reason),'') is null then
    raise exception 'A correction reason is required'; end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)=0 then
    raise exception 'At least one invoice line is required'; end if;
  if exists (select 1 from jsonb_array_elements(p_items) x where nullif(x->>'invoice_item_id','') is not null
    and not exists(select 1 from public.invoice_items i where i.id=(x->>'invoice_item_id')::uuid and i.invoice_id=p_invoice_id)) then
    raise exception 'Invoice line ID does not belong to this invoice'; end if;
  if exists(select x->>'invoice_item_id' from jsonb_array_elements(p_items) x
    where nullif(x->>'invoice_item_id','') is not null group by 1 having count(*)>1) then
    raise exception 'An invoice line cannot be submitted twice'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) x join public.invoice_items i
    on i.id=nullif(x->>'invoice_item_id','')::uuid where i.line_kind::text<>coalesce(x->>'kind','product')) then
    raise exception 'Remove the old line and add a new line when changing its type'; end if;
  -- ============ PHASE 13 EDIT GUARDS ============
  select * into v_old from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if v_old.deleted_at is not null then raise exception 'Invoice has been deleted'; end if;
  if coalesce(v_old.is_topup,false) then raise exception 'A refund top-up invoice is system-generated and cannot be edited'; end if;
  if coalesce(v_old.is_exchange,false) then raise exception 'An exchange invoice is system-generated and cannot be edited'; end if;
  if not p_allow_settled and v_old.status not in ('draft','unpaid') then
    raise exception 'Only Draft or Unpaid invoices can be edited (this one is %)', v_old.status; end if;
  if not p_allow_settled and coalesce(v_old.paid_amount,0) > 0 then
    raise exception 'This invoice has payments recorded (S$%.2f) and is locked for editing', v_old.paid_amount; end if;
  if not p_allow_settled and exists (select 1 from public.invoice_payments where invoice_id = p_invoice_id) then
    raise exception 'This invoice has payment records and is locked for editing'; end if;
  if not p_allow_settled and v_old.locked_at is not null then raise exception 'Invoice is locked'; end if;
  v_store_id := v_old.store_id;             -- store is NOT editable
  v_invoice_no := v_old.invoice_no;         -- invoice number is NOT editable

  -- (Phase 19: no reservations to release.)
  -- ============ END EDIT GUARDS ============

  if public.current_user_role() is null then raise exception 'No profile for current user'; end if;
  if not public.user_has_store_access(v_store_id) then raise exception 'You do not have access to this store'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'At least one item is required'; end if;
  if p_customer_id is null then raise exception 'A customer is required'; end if;
  if public.current_user_role() = 'inventory_manager'
     and exists (select 1 from jsonb_array_elements(p_items) x
                  where coalesce((x->>'foc_quantity')::integer,0) > 0 or coalesce((x->>'is_foc')::boolean,false)) then
    raise exception 'Inventory Manager cannot apply FOC';
  end if;

  -- Phase 19: Membership has been removed. Every customer receives the single
  -- normal selling price, and promotions are open to all customers.
  if exists (select 1 from jsonb_array_elements(p_items) x
              where coalesce(x->>'kind','product') = 'membership') then
    raise exception 'Membership is no longer sold';
  end if;
  v_is_member := true;

  -- PASS 1: validate + price + accumulate CHARGED value.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    select * into v_original_line from public.invoice_items
      where id=nullif(v_item->>'invoice_item_id','')::uuid and invoice_id=p_invoice_id;
    if found and public.invoice_line_matches(v_original_line.id,v_item) then
      v_subtotal := v_subtotal + v_original_line.line_total;
      v_foc_total := v_foc_total + coalesce(v_original_line.foc_amount,0);
      v_line_disc_sum := v_line_disc_sum + coalesce(v_original_line.line_discount,0);
      v_has_promo := v_has_promo or v_original_line.line_kind='promotion';
      if exists(select 1 from public.products where id=v_original_line.product_id and product_type='third_party') then
        v_third_sum := v_third_sum + v_original_line.line_total;
      end if;
      continue;
    end if;

    v_qty := (v_item->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantity must be greater than zero'; end if;
    v_mode_ovr := null; v_ovr_reason := null;   -- Phase 19: no Member/Non-Member modes
    v_use_member := true;

    -- FOC parsing + mandatory reason.
    v_foc_qty := coalesce((v_item->>'foc_quantity')::integer, 0);
    if coalesce((v_item->>'is_foc')::boolean,false) then v_foc_qty := v_qty; end if;
    if v_foc_qty < 0 then raise exception 'FOC quantity cannot be negative'; end if;
    if v_foc_qty > v_qty then
      raise exception 'FOC quantity (%) cannot exceed the line quantity (%)', v_foc_qty, v_qty; end if;
    if v_foc_qty > 0 then
      v_foc_rid := nullif(v_item->>'foc_reason_id','')::uuid;
      v_foc_rtext := nullif(trim(coalesce(v_item->>'foc_reason','')),'');
      perform public.invoice_foc_reason(p_invoice_id,v_item);
    end if;

    if v_kind = 'promotion' then
      v_has_promo := true;
      v_promo_id := (v_item->>'promotion_id')::uuid;
      select * into v_promo from public.promotions where id = v_promo_id and deleted_at is null;
      if not found then raise exception 'Promotion not found'; end if;
      if not v_promo.is_active then raise exception 'Promotion "%" is not active', v_promo.name; end if;
      if v_promo.start_date is not null and now()::date < v_promo.start_date then raise exception 'Promotion "%" has not started yet', v_promo.name; end if;
      if v_promo.end_date is not null and now()::date > v_promo.end_date then raise exception 'Promotion "%" has ended', v_promo.name; end if;

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
                  where store_id = v_store_id and product_id = (v_opt->>'product_id')::uuid
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

      v_pj := public.promotion_price_for(v_store_id, v_promo_id, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Promotion "%" is missing its % price at this store', v_promo.name,
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_topup := public.promotion_selections_topup(v_promo_id, v_store_id, v_item->'selections', v_use_member);
      v_gross := ((v_pj->>'price')::numeric * v_qty) + v_topup;

    elsif v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      perform 1 from public.vouchers where id = v_voucher_id and is_active = true and deleted_at is null;
      if not found then raise exception 'Voucher not found or inactive'; end if;
      v_pj := public.voucher_price_for(v_store_id, v_voucher_id, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Voucher "%" is missing its % price at this store',
          (select name from public.vouchers where id = v_voucher_id),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_gross := (v_pj->>'price')::numeric * v_qty;

    elsif v_kind = 'therapy' then
      if v_qty <> 1 then raise exception 'A therapy line must have quantity 1'; end if;
      v_therapy_pkg := (v_item->>'therapy_package_id')::uuid;
      perform 1 from public.unlimited_therapy_packages where id = v_therapy_pkg and is_active = true and deleted_at is null;
      if not found then raise exception 'Therapy package not found or inactive'; end if;
      if exists (select 1 from public.purchased_therapy_entitlements
                  where customer_id = p_customer_id and package_id = v_therapy_pkg
                    and status in ('active','scheduled','pending_activation')) then
        raise exception 'This customer already has a current entitlement for this therapy package'; end if;
      v_pj := public.therapy_price_for(v_store_id, v_therapy_pkg, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Therapy package "%" is missing its % price at this store',
          (select name from public.unlimited_therapy_packages where id = v_therapy_pkg),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_gross := (v_pj->>'price')::numeric * v_qty;

    elsif v_kind in ('special_product','rental') then
      v_gross := public.special_line_price(
        (v_item->>'special_product_id')::uuid, v_kind,
        nullif(v_item->>'rental_rate_type', '')::public.special_rate_type,
        coalesce((v_item->>'rental_periods')::integer, 1)) * v_qty;

    elsif v_kind = 'credit_package' then
      if v_qty <> 1 then raise exception 'A credit package line must have quantity 1'; end if;
      v_product_id := (v_item->>'credit_package_id')::uuid;
      if not exists (select 1 from public.credit_packages where id = v_product_id and deleted_at is null) then
        raise exception 'Credit package not found'; end if;
      if not exists (select 1 from public.credit_packages_for_store(v_old.store_id) x where x.id = v_product_id) then
        raise exception 'Credit package "%" is not available at this store',
          (select name from public.credit_packages where id = v_product_id); end if;
      select customer_price into v_price from public.credit_packages where id = v_product_id;
      v_gross := v_price * v_qty;

    elsif v_kind = 'premium_bundle' then
      if v_qty <> 1 then raise exception 'A premium bundle line must have quantity 1'; end if;
      v_product_id := (v_item->>'premium_bundle_id')::uuid;
      if not exists (select 1 from public.premium_bundles where id = v_product_id and deleted_at is null) then
        raise exception 'Premium bundle not found'; end if;
      if not exists (select 1 from public.premium_bundles_for_store(v_old.store_id) x where x.id = v_product_id) then
        raise exception 'Premium bundle "%" is not available at this store',
          (select name from public.premium_bundles where id = v_product_id); end if;
      v_sel := coalesce(v_item->'voucher_selection', '[]'::jsonb);
      v_pj := public.validate_bundle_voucher_selection(v_product_id, v_old.store_id, v_sel);
      if not (v_pj->>'complete')::boolean then
        raise exception 'Select exactly % reward voucher(s) for "%" — % chosen',
          v_pj->>'required_qty',
          (select name from public.premium_bundles where id = v_product_id),
          v_pj->>'selected_qty'; end if;
      if not (v_pj->>'stock_ok')::boolean then
        raise exception 'Not enough voucher stock for "%": %',
          (select name from public.premium_bundles where id = v_product_id),
          array_to_string(array(select jsonb_array_elements_text(v_pj->'shortages')), '; '); end if;
      select customer_payment_amount into v_price from public.premium_bundles where id = v_product_id;
      v_gross := v_price * v_qty;

    else
      v_product_id := (v_item->>'product_id')::uuid;
      select p.product_type::text into v_ptype from public.products p where p.id = v_product_id;
      v_pj := public.product_price_for(v_store_id, v_product_id, v_use_member);
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
      v_gross := v_price * v_qty;
    end if;

    if v_item ? 'unit_price' then
      v_price:=(v_item->>'unit_price')::numeric;
      if v_price is null or v_price<0 then raise exception 'Unit price must be zero or greater'; end if;
      if (v_original_line.id is null or v_price is distinct from v_original_line.unit_price) and not public.is_owner_or_manager() then
        raise exception 'Only an Owner or Manager can override invoice prices'; end if;
      v_gross:=v_price*v_qty+case when v_kind='promotion' then coalesce(v_topup,0) else 0 end;
    end if;
    -- FOC split (uniform across every line kind).
    v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
    v_line_total := round(v_gross - v_foc_amt, 2);
    v_subtotal := v_subtotal + v_line_total;
    v_foc_total := v_foc_total + v_foc_amt;

    -- Third-party + per-line voucher rules operate on the CHARGED value.
    if v_kind not in ('promotion','voucher','therapy','special_product','rental','credit_package','premium_bundle') then
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

  -- Discounts apply to the paid value only (v_subtotal is already net of FOC).
  -- A manual discount is a deliberate decision by an Owner or Manager and
  -- may be given against anything on the invoice, third-party included.
  -- Voucher discounts keep the narrower base, since a voucher's terms
  -- should not fund third-party goods.
  v_manual_base := v_subtotal;
  v_discountable := v_subtotal - v_third_sum;
  v_discount := v_manual + v_line_disc_sum;
  if p_discount_voucher_id is not null then
    v_wbase := v_discountable - least(v_manual, v_discountable) - v_line_disc_sum;
    if v_wbase < 0 then v_wbase := 0; end if;
    v_discount := v_discount + public.voucher_discount_amount(p_discount_voucher_id, v_wbase);
  end if;
  -- The manual portion is capped by the WHOLE invoice; the rest by the
  -- voucher base. Together they can never exceed what was charged.
  v_manual_capped := least(v_manual, v_manual_base);
  v_discount := least(v_discount - v_manual + v_manual_capped, v_manual_base);
  if v_discount > v_manual_base then v_discount := v_manual_base; end if;
  if v_discount < 0 then v_discount := 0; end if;

  -- All validation passed — now replace the invoice's contents in place.
  -- (Store, invoice number, creation date and creator are untouched.)
  delete from public.invoice_promotion_selections s
   using public.invoice_items ii
   where s.invoice_item_id = ii.id and ii.invoice_id = p_invoice_id
     and not exists(select 1 from jsonb_array_elements(p_items) x
       where nullif(x->>'invoice_item_id','')::uuid=ii.id and public.invoice_line_matches(ii.id,x));
  delete from public.invoice_items ii where invoice_id = p_invoice_id
    and not exists(select 1 from jsonb_array_elements(p_items) x where nullif(x->>'invoice_item_id','')::uuid=ii.id);
  delete from public.invoice_service_staff where invoice_id = p_invoice_id;

  update public.invoices
     set customer_id = p_customer_id,
         affiliate_id = p_affiliate_id,
         notes = p_notes,
         discount_voucher_id = p_discount_voucher_id,
         subtotal = v_subtotal,
         manual_discount = v_manual,
         discount_total = v_discount,
         total_amount = v_subtotal - v_discount,
         foc_total = v_foc_total,
         has_foc = v_foc_total > 0,
         is_full_foc = (v_foc_total > 0 and v_subtotal <= 0)
   where id = p_invoice_id;


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
    values (p_invoice_id, v_ss_id) on conflict (invoice_id, staff_id) do nothing;
  end loop;

  -- PASS 2: insert lines with permanent snapshots (incl. FOC snapshots).
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    if public.invoice_line_matches(nullif(v_item->>'invoice_item_id','')::uuid,v_item) then continue; end if;

    v_qty := (v_item->>'quantity')::integer;
    v_mode_ovr := nullif(v_item->>'price_mode_override','');
    v_ovr_reason := nullif(trim(coalesce(v_item->>'override_reason','')),'');
    v_use_member := coalesce(v_mode_ovr = 'member', v_is_member);
    v_mode := case when v_use_member then 'member' else 'non_member' end;

    v_foc_qty := coalesce((v_item->>'foc_quantity')::integer, 0);
    if coalesce((v_item->>'is_foc')::boolean,false) then v_foc_qty := v_qty; end if;
    v_foc_rid := nullif(v_item->>'foc_reason_id','')::uuid;
    v_foc_rtext := nullif(trim(coalesce(v_item->>'foc_reason','')),'');
    v_foc_resolved := case when v_foc_qty > 0 then public.invoice_foc_reason(p_invoice_id,v_item) else null end;

    if v_kind = 'promotion' then
      v_promo_id := (v_item->>'promotion_id')::uuid;
      v_pj := public.promotion_price_for(v_store_id, v_promo_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_topup := public.promotion_selections_topup(v_promo_id, v_store_id, v_item->'selections', v_use_member);
      v_price:=coalesce((v_item->>'unit_price')::numeric,v_price);
      v_gross := (v_price * v_qty) + v_topup;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      insert into public.invoice_items (id, invoice_id, line_kind, promotion_id, product_id, quantity, unit_price, line_total, topup_amount, price_mode, price_source, price_source_id, store_id_snapshot, member_price_snapshot, non_member_price_snapshot, original_price, price_overridden, override_reason, override_by, override_at, foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (coalesce(nullif(v_item->>'invoice_item_id','')::uuid,gen_random_uuid()), p_invoice_id, 'promotion', v_promo_id, null, v_qty, v_price, v_line_total, v_topup,
              v_mode, case when v_mode_ovr is null then 'promotion' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, v_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end)
      
      on conflict (id) do update set line_kind=excluded.line_kind, promotion_id=excluded.promotion_id, product_id=excluded.product_id, quantity=excluded.quantity, unit_price=excluded.unit_price, line_total=excluded.line_total, topup_amount=excluded.topup_amount, price_mode=excluded.price_mode, price_source=excluded.price_source, price_source_id=excluded.price_source_id, store_id_snapshot=excluded.store_id_snapshot, member_price_snapshot=excluded.member_price_snapshot, non_member_price_snapshot=excluded.non_member_price_snapshot, original_price=excluded.original_price, price_overridden=excluded.price_overridden, override_reason=excluded.override_reason, override_by=excluded.override_by, override_at=excluded.override_at, foc_quantity=excluded.foc_quantity, is_foc=excluded.is_foc, foc_amount=excluded.foc_amount, foc_original_unit_price=excluded.foc_original_unit_price, foc_reason_id=excluded.foc_reason_id, foc_reason=excluded.foc_reason, foc_by=excluded.foc_by, foc_at=excluded.foc_at returning id into v_item_id;

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
      v_pj := public.voucher_price_for(v_store_id, v_voucher_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_price:=coalesce((v_item->>'unit_price')::numeric,v_price);
      v_gross := v_price * v_qty;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      insert into public.invoice_items (id, invoice_id, line_kind, voucher_id, product_id, quantity, unit_price, line_total, price_mode, price_source, price_source_id, store_id_snapshot, member_price_snapshot, non_member_price_snapshot, original_price, price_overridden, override_reason, override_by, override_at, foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (coalesce(nullif(v_item->>'invoice_item_id','')::uuid,gen_random_uuid()), p_invoice_id, 'voucher', v_voucher_id, null, v_qty, v_price, v_line_total,
              v_mode, case when v_mode_ovr is null then 'voucher' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, v_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end)
      on conflict (id) do update set line_kind=excluded.line_kind, voucher_id=excluded.voucher_id, product_id=excluded.product_id, quantity=excluded.quantity, unit_price=excluded.unit_price, line_total=excluded.line_total, price_mode=excluded.price_mode, price_source=excluded.price_source, price_source_id=excluded.price_source_id, store_id_snapshot=excluded.store_id_snapshot, member_price_snapshot=excluded.member_price_snapshot, non_member_price_snapshot=excluded.non_member_price_snapshot, original_price=excluded.original_price, price_overridden=excluded.price_overridden, override_reason=excluded.override_reason, override_by=excluded.override_by, override_at=excluded.override_at, foc_quantity=excluded.foc_quantity, is_foc=excluded.is_foc, foc_amount=excluded.foc_amount, foc_original_unit_price=excluded.foc_original_unit_price, foc_reason_id=excluded.foc_reason_id, foc_reason=excluded.foc_reason, foc_by=excluded.foc_by, foc_at=excluded.foc_at;

    elsif v_kind = 'therapy' then
      v_therapy_pkg := (v_item->>'therapy_package_id')::uuid;
      v_pj := public.therapy_price_for(v_store_id, v_therapy_pkg, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_price:=coalesce((v_item->>'unit_price')::numeric,v_price);
      v_gross := v_price;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      select name, duration_months into v_therapy_name, v_therapy_months
        from public.unlimited_therapy_packages where id = v_therapy_pkg;
      insert into public.invoice_items (id, invoice_id, line_kind, product_id, therapy_package_id, quantity, unit_price, line_total, price_mode, price_source, price_source_id, store_id_snapshot, member_price_snapshot, non_member_price_snapshot, original_price, plan_name_snapshot, plan_months_snapshot, price_overridden, override_reason, override_by, override_at, foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (coalesce(nullif(v_item->>'invoice_item_id','')::uuid,gen_random_uuid()), p_invoice_id, 'therapy', null, v_therapy_pkg, 1, v_price, v_line_total,
              v_mode, case when v_mode_ovr is null then 'therapy' else 'manual_override' end,
              v_therapy_pkg, v_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_therapy_name, v_therapy_months,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end)
      on conflict (id) do update set line_kind=excluded.line_kind, product_id=excluded.product_id, therapy_package_id=excluded.therapy_package_id, quantity=excluded.quantity, unit_price=excluded.unit_price, line_total=excluded.line_total, price_mode=excluded.price_mode, price_source=excluded.price_source, price_source_id=excluded.price_source_id, store_id_snapshot=excluded.store_id_snapshot, member_price_snapshot=excluded.member_price_snapshot, non_member_price_snapshot=excluded.non_member_price_snapshot, original_price=excluded.original_price, plan_name_snapshot=excluded.plan_name_snapshot, plan_months_snapshot=excluded.plan_months_snapshot, price_overridden=excluded.price_overridden, override_reason=excluded.override_reason, override_by=excluded.override_by, override_at=excluded.override_at, foc_quantity=excluded.foc_quantity, is_foc=excluded.is_foc, foc_amount=excluded.foc_amount, foc_original_unit_price=excluded.foc_original_unit_price, foc_reason_id=excluded.foc_reason_id, foc_reason=excluded.foc_reason, foc_by=excluded.foc_by, foc_at=excluded.foc_at;
    elsif v_kind in ('special_product','rental') then
      v_price := round(public.special_line_price(
        (v_item->>'special_product_id')::uuid, v_kind,
        nullif(v_item->>'rental_rate_type', '')::public.special_rate_type,
        coalesce((v_item->>'rental_periods')::integer, 1)), 2);
      v_price:=coalesce((v_item->>'unit_price')::numeric,v_price);
      v_line_total := round(v_price * v_qty, 2);
      insert into public.invoice_items (id, invoice_id, line_kind, product_id, quantity, unit_price, line_total, store_id_snapshot, original_price, special_product_id, rental_rate_type, rental_periods, rental_start_date, rental_return_date)
      values (coalesce(nullif(v_item->>'invoice_item_id','')::uuid,gen_random_uuid()), p_invoice_id, v_kind::public.invoice_line_kind, null, v_qty, v_price, v_line_total,
         v_old.store_id, v_price,
         (v_item->>'special_product_id')::uuid,
         nullif(v_item->>'rental_rate_type', '')::public.special_rate_type,
         coalesce((v_item->>'rental_periods')::integer, 1),
         nullif(v_item->>'rental_start_date', '')::date,
         nullif(v_item->>'rental_return_date', '')::date)
      on conflict (id) do update set line_kind=excluded.line_kind, product_id=excluded.product_id, quantity=excluded.quantity, unit_price=excluded.unit_price, line_total=excluded.line_total, store_id_snapshot=excluded.store_id_snapshot, original_price=excluded.original_price, special_product_id=excluded.special_product_id, rental_rate_type=excluded.rental_rate_type, rental_periods=excluded.rental_periods, rental_start_date=excluded.rental_start_date, rental_return_date=excluded.rental_return_date;

    elsif v_kind = 'credit_package' then
      v_product_id := (v_item->>'credit_package_id')::uuid;
      select customer_price into v_price from public.credit_packages where id = v_product_id;
      v_price:=coalesce((v_item->>'unit_price')::numeric,v_price);
      v_line_total := round(v_price * v_qty, 2);
      insert into public.invoice_items (id, invoice_id, line_kind, quantity, unit_price, line_total, price_source, price_source_id, store_id_snapshot, original_price, credit_package_id, credit_paid_snapshot, credit_voucher_qty_snapshot, plan_name_snapshot)
      select coalesce(nullif(v_item->>'invoice_item_id','')::uuid,gen_random_uuid()), p_invoice_id, 'credit_package'::public.invoice_line_kind, 1, v_price, v_line_total, 'credit_package', v_product_id,
             v_old.store_id, v_price, v_product_id, pk.paid_credit_amount, null, pk.name
        from public.credit_packages pk where pk.id = v_product_id
      on conflict (id) do update set line_kind=excluded.line_kind, quantity=excluded.quantity, unit_price=excluded.unit_price, line_total=excluded.line_total, price_source=excluded.price_source, price_source_id=excluded.price_source_id, store_id_snapshot=excluded.store_id_snapshot, original_price=excluded.original_price, credit_package_id=excluded.credit_package_id, credit_paid_snapshot=excluded.credit_paid_snapshot, credit_voucher_qty_snapshot=excluded.credit_voucher_qty_snapshot, plan_name_snapshot=excluded.plan_name_snapshot;

    elsif v_kind = 'premium_bundle' then
      v_product_id := (v_item->>'premium_bundle_id')::uuid;
      v_sel := coalesce(v_item->'voucher_selection', '[]'::jsonb);
      select customer_payment_amount into v_price from public.premium_bundles where id = v_product_id;
      v_price:=coalesce((v_item->>'unit_price')::numeric,v_price);
      v_line_total := round(v_price * v_qty, 2);
      insert into public.invoice_items (id, invoice_id, line_kind, quantity, unit_price, line_total, price_source, price_source_id, store_id_snapshot, original_price, premium_bundle_id, credit_paid_snapshot, credit_bonus_snapshot, credit_voucher_qty_snapshot, bundle_voucher_selection, plan_name_snapshot)
      select coalesce(nullif(v_item->>'invoice_item_id','')::uuid,gen_random_uuid()), p_invoice_id, 'premium_bundle'::public.invoice_line_kind, 1, v_price, v_line_total, 'premium_bundle', v_product_id,
             v_old.store_id, v_price, v_product_id, b.paid_credit_amount, b.bonus_credit_amount,
             b.free_voucher_qty, v_sel, b.name
        from public.premium_bundles b where b.id = v_product_id
      on conflict (id) do update set line_kind=excluded.line_kind, quantity=excluded.quantity, unit_price=excluded.unit_price, line_total=excluded.line_total, price_source=excluded.price_source, price_source_id=excluded.price_source_id, store_id_snapshot=excluded.store_id_snapshot, original_price=excluded.original_price, premium_bundle_id=excluded.premium_bundle_id, credit_paid_snapshot=excluded.credit_paid_snapshot, credit_bonus_snapshot=excluded.credit_bonus_snapshot, credit_voucher_qty_snapshot=excluded.credit_voucher_qty_snapshot, bundle_voucher_selection=excluded.bundle_voucher_selection, plan_name_snapshot=excluded.plan_name_snapshot;

    else
      v_product_id := (v_item->>'product_id')::uuid;
      v_pj := public.product_price_for(v_store_id, v_product_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_price:=coalesce((v_item->>'unit_price')::numeric,v_price);
      v_gross := v_price * v_qty;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      v_line_disc := 0;
      if v_line_voucher is not null then
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
      end if;
      insert into public.invoice_items (id, invoice_id, line_kind, product_id, quantity, unit_price, line_total, line_voucher_id, line_discount, price_mode, price_source, price_source_id, store_id_snapshot, member_price_snapshot, non_member_price_snapshot, original_price, price_overridden, override_reason, override_by, override_at, foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (coalesce(nullif(v_item->>'invoice_item_id','')::uuid,gen_random_uuid()), p_invoice_id, 'product', v_product_id, v_qty, v_price, v_line_total, v_line_voucher, v_line_disc,
              v_mode, case when v_mode_ovr is null then 'product' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, v_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end)
      on conflict (id) do update set line_kind=excluded.line_kind, product_id=excluded.product_id, quantity=excluded.quantity, unit_price=excluded.unit_price, line_total=excluded.line_total, line_voucher_id=excluded.line_voucher_id, line_discount=excluded.line_discount, price_mode=excluded.price_mode, price_source=excluded.price_source, price_source_id=excluded.price_source_id, store_id_snapshot=excluded.store_id_snapshot, member_price_snapshot=excluded.member_price_snapshot, non_member_price_snapshot=excluded.non_member_price_snapshot, original_price=excluded.original_price, price_overridden=excluded.price_overridden, override_reason=excluded.override_reason, override_by=excluded.override_by, override_at=excluded.override_at, foc_quantity=excluded.foc_quantity, is_foc=excluded.is_foc, foc_amount=excluded.foc_amount, foc_original_unit_price=excluded.foc_original_unit_price, foc_reason_id=excluded.foc_reason_id, foc_reason=excluded.foc_reason, foc_by=excluded.foc_by, foc_at=excluded.foc_at;
    end if;
  end loop;

  -- Save Earth (columns preserved on the header) re-enters through the
  -- canonical discount refresh, capped at the charged subtotal.
  perform public.refresh_invoice_discount_total(p_invoice_id);
  update public.invoices set discount_total = least(coalesce(discount_total,0), subtotal) where id = p_invoice_id;
  update public.invoices i set total_amount = greatest(0, i.subtotal - coalesce(i.discount_total,0)) where i.id = p_invoice_id;

  perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_edited',
    jsonb_build_object('subtotal', v_old.subtotal, 'discount_total', v_old.discount_total,
                       'total_amount', v_old.total_amount, 'customer_id', v_old.customer_id,
                       'affiliate_id', v_old.affiliate_id),
    jsonb_build_object('invoice_no', v_invoice_no, 'revision_no', v_rev,
                       'subtotal', v_subtotal, 'discount_total', v_discount,
                       'total', v_subtotal - v_discount,
                       'has_promotion', v_has_promo,
                       'foc_total', v_foc_total),
    'invoice_edit', p_edit_reason, v_store_id);
  if v_foc_total > 0 then
    perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_foc_created', null,
      jsonb_build_object('invoice_no', v_invoice_no, 'foc_total', v_foc_total,
                         'charged_total', v_subtotal - v_discount),
      'foc', null, v_store_id);
  end if;
  return p_invoice_id;
end; $function$;
revoke all on function public.update_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean) from public,anon;
grant execute on function public.update_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
