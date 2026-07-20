-- =====================================================================
-- ENERGIA — 48c: PHASE 4 REMAINING FIXES (database part)
--
-- 47, 48 and 48b are executed and untouched. This is the next additive
-- correction in sequence. Three concerns:
--
--   L. CONCURRENCY — functions that mutate unpaid-invoice membership or
--      pricing state now take a FOR UPDATE lock on the invoice row and
--      RE-CHECK its status after acquiring the lock, so an override, a
--      membership-line removal or a Member-ID reservation can no longer
--      race a simultaneous payment and mutate an invoice that just became
--      paid. (pay_invoice already locks; these are the other writers.)
--
--   I. COMMISSION ALLOCATION — promotion component valuation now uses the
--      line's APPLIED price-mode snapshots (member/non-member store prices).
--      legacy `selling_price` is used ONLY when the line has no price_mode
--      (pre-Phase-4 invoices), which keeps every historical allocation
--      byte-identical. New 4-arg promotion_commission_items overload; the
--      3-arg original is kept for exchanges and older callers.
--
--   Plus: reserve_member_id gains the same lock + recheck.
--
-- Additive + idempotent + safe to re-run. Run AFTER 48b.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- I.1  Mode-aware promotion component valuation (4-arg overload).
--      p_mode null => exact legacy behaviour (selling_price).
-- ---------------------------------------------------------------------
create or replace function public.promotion_commission_items(
  p_promotion_id uuid, p_store_id uuid, p_multiplier integer, p_mode text
) returns table (ptype text, original_value numeric)
language plpgsql stable security definer set search_path = public as $$
declare v_item record; v_price numeric;
begin
  for v_item in select * from public.promotion_items where promotion_id = p_promotion_id
  loop
    if v_item.item_type = 'product' then
      select case p_mode
               when 'member' then coalesce(member_price, selling_price)
               when 'non_member' then coalesce(non_member_price, selling_price)
               else selling_price end
        into v_price
        from public.store_product_prices
        where store_id = p_store_id and product_id = v_item.product_id
          and is_active = true and deleted_at is null;
      ptype := coalesce((select product_type::text from public.products where id = v_item.product_id), 'own');
      original_value := coalesce(v_price,0) * v_item.quantity * p_multiplier; return next;
    elsif v_item.item_type = 'voucher' then
      select case p_mode
               when 'member' then coalesce(vsp.member_price, v.selling_price)
               when 'non_member' then coalesce(vsp.non_member_price, v.selling_price)
               else v.selling_price end
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
end; $$;

-- ---------------------------------------------------------------------
-- I.2  earn_invoice_commission — full body preserved from migration 22,
--      with exactly three changes: price_mode carried per line, the pci
--      call passes it, and chosen-selection valuation uses the applied
--      mode with selling_price only as the legacy (null-mode) fallback.
-- ---------------------------------------------------------------------
create or replace function public.earn_invoice_commission(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_tier1 uuid; v_tier2 uuid; v_item record;
  v_ptype text; v_line_after numeric; v_t1_rate numeric; v_t1_amt numeric; v_t2_amt numeric;
  v_paid_date date; v_own_orig numeric; v_third_orig numeric; v_tot_orig numeric; v_portion numeric;
  v_line_disc_sum numeric; v_invoice_level numeric; v_base_total numeric; v_line_net numeric;
  v_sel_own numeric; v_sel_third numeric; v_is_third boolean;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return; end if;

  select tier1, tier2 into v_tier1, v_tier2 from public.customer_referrers(v_inv.customer_id);
  if v_tier1 is null then return; end if;

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
            then (case v_item.price_mode
                    when 'member' then coalesce(spp.member_price, spp.selling_price, 0)
                    when 'non_member' then coalesce(spp.non_member_price, spp.selling_price, 0)
                    else coalesce(spp.selling_price, 0) end) * s.quantity
          when s.voucher_id is not null
            then (case v_item.price_mode
                    when 'member' then coalesce(vsp.member_price, vv.selling_price, 0)
                    when 'non_member' then coalesce(vsp.non_member_price, vv.selling_price, 0)
                    else coalesce(vv.selling_price, 0) end) * s.quantity
          else 0 end),0),
        coalesce(sum(case
          when s.product_id is not null and coalesce(pp.product_type::text,'own') = 'third_party'
            then (case v_item.price_mode
                    when 'member' then coalesce(spp.member_price, spp.selling_price, 0)
                    when 'non_member' then coalesce(spp.non_member_price, spp.selling_price, 0)
                    else coalesce(spp.selling_price, 0) end) * s.quantity
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
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', 'own', v_portion, 15, v_t1_amt, 'earned', v_paid_date);
          if v_tier2 is not null then
            v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
            if v_t2_amt > 0 then
              insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
              values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', 'own', v_t1_amt, 5.0, v_t2_amt, 'earned', v_paid_date);
            end if;
          end if;
        end if;
      end if;

      if v_third_orig > 0 then
        v_portion := round(v_line_after * v_third_orig / v_tot_orig, 2);
        v_t1_amt := round(v_portion * 4.5 / 100.0, 2);
        if v_t1_amt > 0 then
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', 'third_party', v_portion, 4.5, v_t1_amt, 'earned', v_paid_date);
          if v_tier2 is not null then
            v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
            if v_t2_amt > 0 then
              insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
              values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', 'third_party', v_t1_amt, 5.0, v_t2_amt, 'earned', v_paid_date);
            end if;
          end if;
        end if;
      end if;

    else
      if v_item.line_kind = 'voucher' then v_ptype := 'own'; else v_ptype := v_item.ptype; end if;
      v_t1_rate := case when v_ptype = 'third_party' then 4.5 else 15 end;
      v_t1_amt := round(v_line_after * v_t1_rate / 100.0, 2);
      if v_t1_amt <= 0 then continue; end if;

      insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
      values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', v_ptype, v_line_after, v_t1_rate, v_t1_amt, 'earned', v_paid_date);

      if v_tier2 is not null then
        v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
        if v_t2_amt > 0 then
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', v_ptype, v_t1_amt, 5.0, v_t2_amt, 'earned', v_paid_date);
        end if;
      end if;
    end if;
  end loop;

  perform public.write_audit('commissions', p_invoice_id, 'commission_calculated', null,
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'tier1', v_tier1, 'tier2', v_tier2));
end; $$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- L.1  override_invoice_line_price — invoice locked, status re-checked.
-- ---------------------------------------------------------------------
create or replace function public.override_invoice_line_price(
  p_item_id uuid, p_mode text, p_reason text
) returns void language plpgsql security definer set search_path = public as $$
declare v_li public.invoice_items%rowtype; v_inv public.invoices%rowtype; v_pj jsonb;
        v_new numeric; v_role user_role; v_member boolean;
begin
  v_role := public.current_user_role();
  if v_role is null or v_role = 'inventory_manager' then raise exception 'Not permitted'; end if;
  if p_mode not in ('member','non_member') then raise exception 'Invalid price mode'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'An override reason is required'; end if;

  select * into v_li from public.invoice_items where id = p_item_id;
  if not found then raise exception 'Line not found'; end if;
  if v_li.line_kind = 'membership' then
    raise exception 'Member/Non-Member override does not apply to a membership line'; end if;
  if v_li.line_kind not in ('product','voucher','promotion') then
    raise exception 'This line kind cannot be overridden'; end if;

  -- LOCK the invoice, then re-check everything that a concurrent payment
  -- could have changed while we waited for the lock.
  select * into v_inv from public.invoices where id = v_li.invoice_id for update;
  if v_inv.status in ('paid','cancelled','refunded') or v_inv.locked_at is not null then
    raise exception 'Invoice is locked'; end if;
  if coalesce(v_inv.paid_amount,0) > 0 then
    raise exception 'Lines cannot be changed after a payment has been recorded'; end if;
  if not (public.is_manager_or_above() or public.user_has_store_access(v_inv.store_id)) then
    raise exception 'No access to this invoice''s store'; end if;
  -- Re-read the line under the invoice lock (it may have been repriced).
  select * into v_li from public.invoice_items where id = p_item_id;
  if not found then raise exception 'Line not found'; end if;

  v_member := (p_mode = 'member');
  if v_li.line_kind = 'product' then
    v_pj := public.product_price_for(v_inv.store_id, v_li.product_id, v_member);
  elsif v_li.line_kind = 'voucher' then
    v_pj := public.voucher_price_for(v_inv.store_id, v_li.voucher_id, v_member);
  else
    v_pj := public.promotion_price_for(v_inv.store_id, v_li.promotion_id, v_member);
  end if;
  if not coalesce((v_pj->>'has_price')::boolean,false) then
    raise exception 'No % price is set for this line at this store', p_mode; end if;
  v_new := (v_pj->>'price')::numeric;

  update public.invoice_items
     set unit_price = v_new,
         line_total = (v_new * quantity) + coalesce(topup_amount,0),
         line_discount = case when line_voucher_id is not null
           then public.voucher_discount_amount(line_voucher_id, v_new * quantity)
           else line_discount end,
         price_mode = p_mode, price_source = 'manual_override',
         price_source_id = (v_pj->>'source_id')::uuid,
         member_price_snapshot = (v_pj->>'member_price')::numeric,
         non_member_price_snapshot = (v_pj->>'non_member_price')::numeric,
         original_price = coalesce(original_price, v_li.unit_price),
         price_overridden = true, override_reason = trim(p_reason),
         override_by = auth.uid(), override_at = now()
   where id = p_item_id;

  update public.invoices set subtotal =
    coalesce((select sum(line_total) from public.invoice_items where invoice_id = v_inv.id),0)
   where id = v_inv.id;
  perform public.refresh_invoice_discount_total(v_inv.id);
  update public.invoices i set total_amount = greatest(0, i.subtotal - coalesce(i.discount_total,0))
   where i.id = v_inv.id;

  perform public.write_audit_ex('invoice_items', p_item_id, 'line_price_overridden',
    jsonb_build_object('old_mode', v_li.price_mode, 'old_price', v_li.unit_price),
    jsonb_build_object('new_mode', p_mode, 'new_price', v_new), 'pricing', p_reason, v_inv.store_id);
end $$;

-- ---------------------------------------------------------------------
-- L.2  remove_membership_line — invoice locked, status re-checked.
-- ---------------------------------------------------------------------
create or replace function public.remove_membership_line(p_item_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_li public.invoice_items%rowtype; v_inv public.invoices%rowtype;
begin
  select * into v_li from public.invoice_items where id = p_item_id and line_kind = 'membership';
  if not found then raise exception 'Membership line not found'; end if;

  select * into v_inv from public.invoices where id = v_li.invoice_id for update;
  if v_inv.status in ('paid','cancelled','refunded') or v_inv.locked_at is not null then
    raise exception 'Invoice is locked'; end if;
  if coalesce(v_inv.paid_amount,0) > 0 then
    raise exception 'Lines cannot be changed after a payment has been recorded'; end if;
  if not (public.is_manager_or_above() or public.user_has_store_access(v_inv.store_id)) then
    raise exception 'No access'; end if;
  -- Re-verify the line still exists under the lock.
  perform 1 from public.invoice_items where id = p_item_id and line_kind = 'membership';
  if not found then raise exception 'Membership line not found'; end if;

  perform public.release_member_id_reservations_for_invoice(v_inv.id);
  delete from public.invoice_items where id = p_item_id;

  perform public.reprice_invoice_lines(v_inv.id,
    coalesce((public.customer_membership_status(v_inv.customer_id)->>'is_member')::boolean, false));

  perform public.write_audit_ex('invoice_items', p_item_id, 'membership_line_removed',
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'plan', v_li.plan_name_snapshot), null,
    'membership', null, v_inv.store_id);
end $$;

-- ---------------------------------------------------------------------
-- L.3  reserve_member_id — invoice locked + status re-checked when tied
--      to an invoice. Reservation on unpaid AND partially-paid invoices is
--      allowed (the ID must exist before payment completes); paid/dead
--      invoices refuse.
-- ---------------------------------------------------------------------
create or replace function public.reserve_member_id(
  p_member_id text, p_customer_id uuid, p_invoice_id uuid default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_id text; v_inv public.invoices%rowtype;
begin
  if public.current_user_role() is null then raise exception 'No profile'; end if;
  if public.current_user_role() = 'inventory_manager' then
    raise exception 'Inventory Manager cannot manage Member IDs'; end if;
  v_id := nullif(trim(p_member_id), '');
  if v_id is null then raise exception 'Member ID is required'; end if;

  if p_invoice_id is not null then
    select * into v_inv from public.invoices where id = p_invoice_id for update;
    if not found then raise exception 'Invoice not found'; end if;
    if not public.user_has_store_access(v_inv.store_id) then
      raise exception 'No access to this invoice''s store'; end if;
    if v_inv.customer_id <> p_customer_id then
      raise exception 'The reservation customer does not match the invoice customer'; end if;
    if v_inv.status in ('paid','cancelled','refunded') or v_inv.locked_at is not null then
      raise exception 'Invoice is %', v_inv.status; end if;
  elsif not public.is_manager_or_above() then
    raise exception 'Only a Manager or above can reserve a Member ID without an invoice';
  end if;

  if exists (select 1 from public.member_ids where member_id = v_id and customer_id <> p_customer_id) then
    raise exception 'Member ID % is already assigned to another customer', v_id; end if;
  if exists (select 1 from public.member_id_reservations where member_id = v_id and customer_id <> p_customer_id) then
    raise exception 'Member ID % is currently reserved for another customer', v_id; end if;
  if exists (select 1 from public.member_ids where member_id = v_id and customer_id = p_customer_id) then
    return; end if;

  delete from public.member_id_reservations where customer_id = p_customer_id and member_id <> v_id;
  insert into public.member_id_reservations (member_id, customer_id, invoice_id, reserved_by)
  values (v_id, p_customer_id, p_invoice_id, auth.uid())
  on conflict (member_id) do update
    set invoice_id = excluded.invoice_id, reserved_at = now(), reserved_by = auth.uid()
    where public.member_id_reservations.customer_id = excluded.customer_id;
end $$;

notify pgrst, 'reload schema';
