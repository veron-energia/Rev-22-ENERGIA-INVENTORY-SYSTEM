-- =====================================================================
-- ENERGIA — PHASE 21: EDITABLE COMMISSION RATES
--
--   * Adds four editable affiliate-commission rate settings to the
--     app_settings singleton: Tier 1 / Tier 2 × Own / Third-party.
--   * A set_commission_rates() setter (Owner/Manager only, audited).
--   * earn_invoice_commission now reads these rates instead of the
--     previously hard-coded 15 / 4.5 / 5 / 5, defaulting to the same
--     values so existing behaviour is unchanged until the rates are set.
--
-- Already-earned commissions keep the rate they were calculated at;
-- new rates apply to invoices paid from the change onward.
--
-- Additive and idempotent. Run AFTER 69.
-- =====================================================================

set check_function_bodies = off;

-- 1. Rate columns on the settings singleton (defaults = historical rates).
alter table public.app_settings add column if not exists commission_tier1_own_rate   numeric not null default 15;
alter table public.app_settings add column if not exists commission_tier1_third_rate numeric not null default 4.5;
alter table public.app_settings add column if not exists commission_tier2_own_rate   numeric not null default 5;
alter table public.app_settings add column if not exists commission_tier2_third_rate numeric not null default 5;

-- 2. Owner/Manager setter, audited.
create or replace function public.set_commission_rates(
  p_tier1_own numeric, p_tier1_third numeric, p_tier2_own numeric, p_tier2_third numeric)
returns void language plpgsql security definer set search_path to 'public' as $function$
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit commission rates'; end if;
  if p_tier1_own   is null or p_tier1_own   < 0 or p_tier1_own   > 100 then raise exception 'Tier 1 Own rate must be between 0 and 100'; end if;
  if p_tier1_third is null or p_tier1_third < 0 or p_tier1_third > 100 then raise exception 'Tier 1 Third-party rate must be between 0 and 100'; end if;
  if p_tier2_own   is null or p_tier2_own   < 0 or p_tier2_own   > 100 then raise exception 'Tier 2 Own rate must be between 0 and 100'; end if;
  if p_tier2_third is null or p_tier2_third < 0 or p_tier2_third > 100 then raise exception 'Tier 2 Third-party rate must be between 0 and 100'; end if;
  update public.app_settings
     set commission_tier1_own_rate = p_tier1_own,
         commission_tier1_third_rate = p_tier1_third,
         commission_tier2_own_rate = p_tier2_own,
         commission_tier2_third_rate = p_tier2_third,
         updated_at = now()
   where id = true;
  perform public.write_audit('app_settings', null, 'commission_rates_set', null,
    jsonb_build_object('tier1_own', p_tier1_own, 'tier1_third', p_tier1_third,
                       'tier2_own', p_tier2_own, 'tier2_third', p_tier2_third));
end $function$;

-- 3. earn_invoice_commission re-issued to read the editable rates.
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
  v_rate_t1_own numeric; v_rate_t1_third numeric; v_rate_t2_own numeric; v_rate_t2_third numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return; end if;

  select tier1, tier2 into v_tier1, v_tier2 from public.customer_referrers(v_inv.customer_id);
  if v_tier1 is null then return; end if;

  -- Editable commission rates (fall back to the historical defaults).
  select coalesce(commission_tier1_own_rate, 15), coalesce(commission_tier1_third_rate, 4.5),
         coalesce(commission_tier2_own_rate, 5), coalesce(commission_tier2_third_rate, 5)
    into v_rate_t1_own, v_rate_t1_third, v_rate_t2_own, v_rate_t2_third
    from public.app_settings where id = true;

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
        v_t1_amt := round(v_portion * v_rate_t1_own / 100.0, 2);
        if v_t1_amt > 0 then
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', 'own', v_portion, v_rate_t1_own, v_t1_amt, v_t1_status::commission_status, v_t1_block, v_paid_date);
          if v_tier2 is not null then
            v_t2_amt := round(v_t1_amt * v_rate_t2_own / 100.0, 2);
            if v_t2_amt > 0 then
              insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
              values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', 'own', v_t1_amt, v_rate_t2_own, v_t2_amt, v_t2_status::commission_status, v_t2_block, v_paid_date);
            end if;
          end if;
        end if;
      end if;

      if v_third_orig > 0 then
        v_portion := round(v_line_after * v_third_orig / v_tot_orig, 2);
        v_t1_amt := round(v_portion * v_rate_t1_third / 100.0, 2);
        if v_t1_amt > 0 then
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', 'third_party', v_portion, v_rate_t1_third, v_t1_amt, v_t1_status::commission_status, v_t1_block, v_paid_date);
          if v_tier2 is not null then
            v_t2_amt := round(v_t1_amt * v_rate_t2_third / 100.0, 2);
            if v_t2_amt > 0 then
              insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
              values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', 'third_party', v_t1_amt, v_rate_t2_third, v_t2_amt, v_t2_status::commission_status, v_t2_block, v_paid_date);
            end if;
          end if;
        end if;
      end if;

    else
      if v_item.line_kind = 'voucher' then v_ptype := 'own'; else v_ptype := v_item.ptype; end if;
      v_t1_rate := case when v_ptype = 'third_party' then v_rate_t1_third else v_rate_t1_own end;
      v_t1_amt := round(v_line_after * v_t1_rate / 100.0, 2);
      if v_t1_amt <= 0 then continue; end if;

      insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
      values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', v_ptype, v_line_after, v_t1_rate, v_t1_amt, v_t1_status::commission_status, v_t1_block, v_paid_date);

      if v_tier2 is not null then
        v_t2_amt := round(v_t1_amt * (case when v_ptype = 'third_party' then v_rate_t2_third else v_rate_t2_own end) / 100.0, 2);
        if v_t2_amt > 0 then
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', v_ptype, v_t1_amt, (case when v_ptype = 'third_party' then v_rate_t2_third else v_rate_t2_own end), v_t2_amt, v_t2_status::commission_status, v_t2_block, v_paid_date);
        end if;
      end if;
    end if;
  end loop;

  perform public.write_audit('commissions', p_invoice_id, 'commission_calculated', null,
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'tier1', v_tier1, 'tier2', v_tier2));
end; $function$;

notify pgrst, 'reload schema';
