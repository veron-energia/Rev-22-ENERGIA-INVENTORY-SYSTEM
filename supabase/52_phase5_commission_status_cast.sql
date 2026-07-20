-- =====================================================================
-- ENERGIA — 52: PHASE 5 FIX — cast commission status to enum
--
-- Bug: in migration 51, earn_invoice_commission inserts the per-tier status
-- from text variables (v_t1_status / v_t2_status = 'earned' | 'blocked') into
-- commissions.status, which is the commission_status ENUM. Postgres does not
-- implicitly cast text -> enum in an INSERT, so pay_invoice failed at payment
-- time with: column "status" is of type commission_status but expression is of
-- type text.
--
-- Fix: re-create earn_invoice_commission with explicit ::commission_status
-- casts. Nothing else changes — rates, allocation, and the per-tier blocking
-- logic (Tier 1 blocked does NOT block Tier 2) are identical to 51.
--
-- Additive + idempotent. Run AFTER 51.
-- =====================================================================

set check_function_bodies = off;

create or replace function public.earn_invoice_commission(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
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
end; $$;

notify pgrst, 'reload schema';
