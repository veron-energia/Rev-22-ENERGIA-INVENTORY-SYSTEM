begin;
-- =====================================================================
-- THE COMMISSION FUNCTIONS, INSTALLED AS THE REPOSITORY DEFINES THEM
--
-- Production was found running the 5D2-era earn_invoice_commission (the body
-- in file 19) while every function around it was current. That build credits
-- only the buyer's profile referrer, so an affiliate selected on the invoice
-- earns nothing (INV-2026-0222); a referrer who is not an activated affiliate
-- is paid instead of blocked; the rates are the fixed 15 / 4.5 / 5 rather than
-- app_settings; wallet-funded value, no-commission products and package lines
-- are not excluded.
--
-- 182 patches this function by anchored replace. Its guard refused the body it
-- did not recognise, so none of 182 landed there either: set_invoice_affiliate
-- does not record that a choice was explicit, invoice_effective_affiliate does
-- not honour an explicit "None", and the two package commission functions
-- ignore it. Everything after 182 that touches these five is present.
--
-- The chain (52 -> 69 -> 70 -> 72, then 102, 128, 151, 182, 243, 253) cannot
-- be replayed onto a body it does not expect, so this file installs the five
-- functions in full, exactly as a clean build of every migration produces
-- them (verified against three independent local builds). On a database that
-- already has them it changes nothing. It ends by checking the marker each
-- patch left behind, so a partial apply is loud rather than silent.
--
-- Commission already recorded is not touched here. That is the job of
-- scripts/commissions/reearn-affiliate-commissions.sql, which rehearses by
-- default.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. earn_invoice_commission: 72 + 102 + 128 + 151 + 182 + 243 + 253.
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
  v_rate_t1_own numeric; v_rate_t1_third numeric; v_rate_t2_own numeric; v_rate_t2_third numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return; end if;

  -- Tier 1 is the affiliate explicitly chosen on the invoice, when there is one;
  -- otherwise it falls back to the customer's own referrer. Tier 2 is always the
  -- person who referred Tier 1.
  if v_inv.affiliate_selection_explicit and v_inv.affiliate_id is null then return; end if;
  if v_inv.affiliate_id is not null then
    select a.customer_id into v_tier1
      from public.customer_affiliates a where a.id = v_inv.affiliate_id;
    select c.referred_by into v_tier2
      from public.customers c where c.id = v_tier1;
  else
    select tier1, tier2 into v_tier1, v_tier2 from public.customer_referrers(v_inv.customer_id);
  end if;
  if v_tier1 is null then return; end if;
  -- A customer never earns commission on their own purchase.
  if v_tier1 = v_inv.customer_id then return; end if;

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
           coalesce(p.product_type::text, 'own') as ptype,
           coalesce((select sum(a.amount - a.reversed_amount)
                       from public.invoice_line_credit_allocations a
                      where a.invoice_item_id = ii.id), 0) as wallet_funded
    from public.invoice_items ii
    left join public.products p on p.id = ii.product_id
    where ii.invoice_id = p_invoice_id
      and ii.line_kind not in ('credit_package','premium_bundle')
      and coalesce(p.product_type::text, 'own') <> 'no_commission'
  loop
    v_is_third := (v_item.line_kind = 'product' and v_item.ptype = 'third_party');
    -- Wallet-funded value never earns commission.
    v_line_net := greatest(v_item.line_total - coalesce(v_item.line_discount,0)
                           - coalesce(v_item.wallet_funded,0), 0);
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
end; $function$

;

-- ---------------------------------------------------------------------
-- 2. The package commission functions: 81 ... 253 including 182's explicit
--    "None".
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.earn_credit_package_commission(p_sale_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s public.credit_package_sales%rowtype;
  v_inv public.invoices%rowtype;
  v_t1 uuid; v_t2 uuid; v_base numeric;
  v_r1 numeric; v_r2 numeric; v_a1 numeric; v_a2 numeric;
  v_ptype text;
begin
  select * into s from public.credit_package_sales where id = p_sale_id;
  if not found then raise exception 'Package sale not found'; end if;

  -- Basis: the money actually received, never the credit or free reward.
  v_base := round(coalesce(s.external_paid,0), 2);
  v_base := public.invoice_package_retained_commission_basis('credit_package',s.id,v_base);
  if v_base <= 0 then
    return jsonb_build_object('skipped', true, 'reason', 'no external payment');
  end if;
  -- Commission is always recorded against an invoice, so a sale booked without
  -- one earns nothing until it is invoiced.
  if s.invoice_id is null then
    return jsonb_build_object('skipped', true, 'reason', 'no invoice');
  end if;

  if s.invoice_id is not null then
    select * into v_inv from public.invoices where id = s.invoice_id;
  end if;

  if v_inv.affiliate_selection_explicit and v_inv.affiliate_id is null then return jsonb_build_object('skipped',true,'reason','Affiliate explicitly cleared'); end if;
  if v_inv.affiliate_id is not null then
    select a.customer_id into v_t1 from public.customer_affiliates a where a.id = v_inv.affiliate_id;
  else
    select c.referred_by into v_t1 from public.customers c where c.id = s.customer_id;
  end if;
  if v_t1 is null or v_t1 = s.customer_id then
    return jsonb_build_object('skipped', true, 'reason', 'no eligible referrer');
  end if;
  select c.referred_by into v_t2 from public.customers c where c.id = v_t1;

  v_ptype := public.package_commission_classification();
  select coalesce(s.tier1_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier1_third_rate
                else commission_tier1_own_rate end),
         coalesce(s.tier2_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier2_third_rate
                else commission_tier2_own_rate end)
    into v_r1, v_r2 from public.app_settings where id = true;

  v_a1 := round(v_base * v_r1 / 100.0, 2);
  if v_a1 > 0 then
    insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
      tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      'earned', public.sg_today());
    if v_t2 is not null then
      v_a2 := round(v_a1 * v_r2 / 100.0, 2);
      if v_a2 > 0 then
        insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
          tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
        values (s.invoice_id, s.customer_id, v_t2, 'tier2', v_ptype, v_a1, v_r2, v_a2,
          'earned', public.sg_today());
      end if;
    end if;
  end if;

  return jsonb_build_object('basis', v_base, 'tier1', v_a1, 'tier2', coalesce(v_a2,0),
    'tier1_rate', v_r1, 'tier2_rate', v_r2);
end $function$

;

CREATE OR REPLACE FUNCTION public.earn_premium_bundle_commission(p_sale_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s public.premium_bundle_sales%rowtype;
  v_inv public.invoices%rowtype;
  v_t1 uuid; v_t2 uuid; v_base numeric; v_ptype text;
  v_r1 numeric; v_r2 numeric; v_a1 numeric; v_a2 numeric;
begin
  select * into s from public.premium_bundle_sales where id = p_sale_id;
  if not found then raise exception 'Bundle sale not found'; end if;

  -- Only external money after discount and FOC. Never bonus credit, free
  -- voucher value, or any later redemption.
  v_base := round(coalesce(s.external_paid,0), 2);
  v_base := public.invoice_package_retained_commission_basis('premium_bundle',s.id,v_base);
  if v_base <= 0 then return jsonb_build_object('skipped', true, 'reason', 'no external payment'); end if;
  if s.invoice_id is null then return jsonb_build_object('skipped', true, 'reason', 'no invoice'); end if;

  select * into v_inv from public.invoices where id = s.invoice_id;
  if v_inv.affiliate_selection_explicit and v_inv.affiliate_id is null then return jsonb_build_object('skipped',true,'reason','Affiliate explicitly cleared'); end if;
  if v_inv.affiliate_id is not null then
    select a.customer_id into v_t1 from public.customer_affiliates a where a.id = v_inv.affiliate_id;
  else
    select c.referred_by into v_t1 from public.customers c where c.id = s.customer_id;
  end if;
  if v_t1 is null or v_t1 = s.customer_id then
    return jsonb_build_object('skipped', true, 'reason', 'no eligible referrer'); end if;
  select c.referred_by into v_t2 from public.customers c where c.id = v_t1;

  v_ptype := public.package_commission_classification();
  select coalesce(s.tier1_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier1_third_rate
                else commission_tier1_own_rate end),
         coalesce(s.tier2_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier2_third_rate
                else commission_tier2_own_rate end)
    into v_r1, v_r2 from public.app_settings where id = true;

  v_a1 := round(v_base * v_r1 / 100.0, 2);
  if v_a1 > 0 then
    insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
      tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      'earned', public.sg_today());
    if v_t2 is not null then
      v_a2 := round(v_a1 * v_r2 / 100.0, 2);
      if v_a2 > 0 then
        insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
          tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
        values (s.invoice_id, s.customer_id, v_t2, 'tier2', v_ptype, v_a1, v_r2, v_a2,
          'earned', public.sg_today());
      end if;
    end if;
  end if;

  return jsonb_build_object('basis', v_base, 'classification', v_ptype,
    'tier1_rate', v_r1, 'tier2_rate', v_r2, 'tier1', v_a1, 'tier2', coalesce(v_a2,0));
end $function$

;

-- ---------------------------------------------------------------------
-- 3. Reading and setting the invoice's affiliate: 72 + 182 and 69 + 182.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.invoice_effective_affiliate(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_inv public.invoices%rowtype;
  v_person uuid; v_source text; v_aff_id uuid; v_name text; v_phone text;
  v_is_active boolean := false; v_tier2 uuid; v_tier2_name text;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return jsonb_build_object('found', false); end if;

  if not public.user_has_store_access(v_inv.store_id) then raise exception 'Invoice not accessible'; end if;
  if v_inv.affiliate_selection_explicit and v_inv.affiliate_id is null then return jsonb_build_object('found',true,'has_affiliate',false,'source','none'); end if;
  if v_inv.affiliate_id is not null then
    select a.customer_id, a.id into v_person, v_aff_id
      from public.customer_affiliates a where a.id = v_inv.affiliate_id;
    v_source := 'invoice';
  else
    select c.referred_by into v_person from public.customers c where c.id = v_inv.customer_id;
    v_source := 'referrer';
    if v_person is not null then
      select a.id into v_aff_id from public.customer_affiliates a
       where a.customer_id = v_person and a.deleted_at is null;
    end if;
  end if;

  if v_person is null then
    return jsonb_build_object('found', true, 'has_affiliate', false, 'source', 'none');
  end if;

  select c.full_name, c.phone into v_name, v_phone from public.customers c where c.id = v_person;
  select (a.status = 'active' and not coalesce(a.manually_suspended,false) and a.deleted_at is null)
    into v_is_active from public.customer_affiliates a where a.id = v_aff_id;
  select c2.referred_by into v_tier2 from public.customers c2 where c2.id = v_person;
  if v_tier2 is not null then
    select full_name into v_tier2_name from public.customers where id = v_tier2;
  end if;

  return jsonb_build_object(
    'found', true, 'has_affiliate', true, 'source', v_source,
    'customer_id', v_person, 'affiliate_id', v_aff_id,
    'full_name', v_name, 'phone', v_phone,
    'is_registered_affiliate', v_aff_id is not null,
    'is_active_affiliate', coalesce(v_is_active,false),
    'tier2_name', v_tier2_name);
end $function$

;

CREATE OR REPLACE FUNCTION public.set_invoice_affiliate(p_invoice_id uuid, p_affiliate_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  update public.invoices set affiliate_selection_explicit=true, affiliate_id = p_affiliate_id where id = p_invoice_id;

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
end $function$

;

-- ---------------------------------------------------------------------
-- 4. Every patch leaves a mark. Refuse to commit without all of them.
-- ---------------------------------------------------------------------
do $$
declare f text; sig text; marks text[]; m text;
begin
  for sig, marks in
    select * from (values
      ('public.earn_invoice_commission(uuid)',
       array['affiliate_selection_explicit', 'app_settings', 'is_eligible_affiliate',
             'wallet_funded', 'no_commission', 'credit_package', 'price_mode']),
      ('public.earn_credit_package_commission(uuid)',
       array['affiliate_selection_explicit', 'package_commission_classification',
             'invoice_package_retained_commission_basis']),
      ('public.earn_premium_bundle_commission(uuid)',
       array['affiliate_selection_explicit', 'package_commission_classification',
             'invoice_package_retained_commission_basis']),
      ('public.invoice_effective_affiliate(uuid)',
       array['affiliate_selection_explicit', 'user_has_store_access']),
      ('public.set_invoice_affiliate(uuid,uuid)',
       array['affiliate_selection_explicit=true'])) v(sig, marks)
  loop
    f := pg_get_functiondef(sig::regprocedure);
    foreach m in array marks loop
      if position(m in f) = 0 then
        raise exception '334: % is missing the mark "%"; the reinstall did not take', sig, m;
      end if;
    end loop;
  end loop;
end $$;

notify pgrst, 'reload schema';
commit;
