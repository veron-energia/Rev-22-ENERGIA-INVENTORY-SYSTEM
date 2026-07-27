-- =====================================================================
-- ENERGIA — PHASE 23: LEGACY THERAPY CLAIM + INVOICE AFFILIATE CREDIT
--
--   1. BUG FIX: activate_purchased_therapy still called membership_expiry(),
--      which Phase 19 dropped — activating a purchased therapy failed with
--      "function public.membership_expiry(date, integer) does not exist".
--      Replaced with a neutral therapy_expiry() helper.
--
--   2. The affiliate chosen on an invoice is now actually CREDITED:
--      earn_invoice_commission takes Tier 1 from invoices.affiliate_id when
--      one is set, falling back to the customer's own referrer. Tier 2 is
--      whoever referred Tier 1. Previously the selector had no effect on
--      commission at all.
--      invoice_effective_affiliate() exposes the affiliate that WILL be
--      credited so the UI can show it before anyone selects anything.
--
--   3. Legacy entitlements can now be CLAIMED properly: claiming records an
--      activation date and (for an unlimited reward) a calendar-month expiry,
--      so a claimed Legacy therapy has a real start and end. Previously
--      activation only flipped a status with no dates at all.
--
-- Additive and idempotent. Run AFTER 71.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Neutral calendar-month expiry helper (replaces membership_expiry).
--    Start + N months, minus one day, matching the old behaviour.
-- ---------------------------------------------------------------------
create or replace function public.therapy_expiry(p_start date, p_months integer)
returns date language sql immutable as $function$
  select case when p_start is null or coalesce(p_months,0) <= 0 then null
              else (p_start + make_interval(months => p_months) - interval '1 day')::date end
$function$;

-- ---------------------------------------------------------------------
-- 2. Legacy entitlements gain real activation dates.
-- ---------------------------------------------------------------------
alter table public.therapy_entitlements add column if not exists activation_date date;
alter table public.therapy_entitlements add column if not exists expiry_date date;
alter table public.therapy_entitlements add column if not exists claimed_by uuid references public.profiles(id);
alter table public.therapy_entitlements add column if not exists claimed_at timestamptz;

-- ---------------------------------------------------------------------
-- 3. Claim a Legacy entitlement. This is the "how do I claim it" action:
--    it activates the entitlement, records who claimed it and when, sets the
--    activation date (today or a chosen future date) and, for an unlimited
--    reward, computes the calendar-month expiry from duration_months.
-- ---------------------------------------------------------------------
create or replace function public.claim_legacy_therapy(
  p_entitlement_id uuid, p_activation_date date default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  e public.therapy_entitlements%rowtype;
  v_today date := public.sg_today();
  v_act date; v_exp date; v_status text;
begin
  select * into e from public.therapy_entitlements where id = p_entitlement_id for update;
  if not found then raise exception 'Legacy entitlement not found'; end if;
  if not public.user_has_store_access(e.store_id) then raise exception 'No access to this store'; end if;
  if e.status <> 'pending_activation' then
    raise exception 'Only an unclaimed entitlement can be claimed (currently %)', e.status; end if;

  v_act := coalesce(p_activation_date, v_today);
  if v_act < v_today then raise exception 'The claim date cannot be in the past'; end if;
  if e.activation_deadline is not null and v_act > e.activation_deadline then
    raise exception 'The claim deadline (%) has passed', e.activation_deadline; end if;

  -- An unlimited reward runs for duration_months from its start date; a voucher
  -- reward has no running period, so it is simply claimed.
  if coalesce(e.entitlement_kind,'unlimited') = 'unlimited' then
    v_exp := public.therapy_expiry(v_act, e.duration_months);
    v_status := case when v_act > v_today then 'scheduled' else 'active' end;
  else
    v_exp := null;
    v_status := 'active';
  end if;

  update public.therapy_entitlements
     set status = v_status, activation_date = v_act, expiry_date = v_exp,
         claimed_by = auth.uid(), claimed_at = now()
   where id = p_entitlement_id;

  perform public.write_audit_ex('therapy_entitlements', p_entitlement_id, 'legacy_therapy_claimed',
    jsonb_build_object('status', e.status),
    jsonb_build_object('status', v_status, 'activation_date', v_act, 'expiry_date', v_exp,
                       'kind', e.entitlement_kind, 'voucher_qty', e.voucher_qty),
    'therapy', 'legacy claim', e.store_id);

  return jsonb_build_object('success', true, 'status', v_status,
    'activation_date', v_act, 'expiry_date', v_exp,
    'entitlement_no', e.entitlement_no,
    'voucher_qty', case when coalesce(e.entitlement_kind,'unlimited') = 'voucher' then e.voucher_qty else null end);
end $function$;

-- Keep the original activation entry point working, now with real dates.
create or replace function public.activate_legacy_therapy(p_entitlement_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $function$
begin
  perform public.claim_legacy_therapy(p_entitlement_id, null);
end $function$;

-- ---------------------------------------------------------------------
-- 4. Expire claimed Legacy therapy whose period has ended (mirrors the
--    purchased-therapy refresh).
-- ---------------------------------------------------------------------
create or replace function public.refresh_legacy_therapy_statuses()
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare v_n integer := 0; v_today date := public.sg_today();
begin
  update public.therapy_entitlements
     set status = 'active'
   where status = 'scheduled' and activation_date is not null and activation_date <= v_today;

  update public.therapy_entitlements
     set status = 'expired'
   where status in ('active','scheduled') and expiry_date is not null and expiry_date < v_today;
  get diagnostics v_n = row_count;
  return v_n;
end $function$;

-- ---------------------------------------------------------------------
-- 5. The affiliate that WILL be credited for an invoice. Explicit choice
--    wins; otherwise the customer's own referrer is used. Returns the
--    customer_affiliates row id when that person is a registered affiliate,
--    so the UI can preselect it in the picker.
-- ---------------------------------------------------------------------
create or replace function public.invoice_effective_affiliate(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare
  v_inv public.invoices%rowtype;
  v_person uuid; v_source text; v_aff_id uuid; v_name text; v_phone text;
  v_is_active boolean := false; v_tier2 uuid; v_tier2_name text;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return jsonb_build_object('found', false); end if;

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
end $function$;

-- ---------------------------------------------------------------------
-- 6. Legacy entitlements earned by a given invoice's same-day qualification
--    (so a paid invoice can show what the customer earned).
-- ---------------------------------------------------------------------
create or replace function public.invoice_legacy_entitlements(p_invoice_id uuid)
returns table(id uuid, entitlement_no text, package_name text, entitlement_kind text,
              duration_months integer, voucher_qty integer, qualified_value numeric,
              activation_deadline date, status text, activation_date date, expiry_date date)
language plpgsql stable security definer set search_path to 'public' as $function$
#variable_conflict use_column
declare v_inv public.invoices%rowtype; v_group uuid; v_day date;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found or v_inv.customer_id is null or v_inv.store_id is null then return; end if;
  v_day := (coalesce(v_inv.paid_at, now()) at time zone 'Asia/Singapore')::date;
  v_group := public.legacy_qualification_group(v_inv.customer_id, v_inv.store_id, v_day);
  return query
    select e.id, e.entitlement_no, e.package_name, e.entitlement_kind,
           e.duration_months, e.voucher_qty, e.qualified_value,
           e.activation_deadline, e.status, e.activation_date, e.expiry_date
      from public.therapy_entitlements e
     where e.qualification_group_id = v_group and e.status <> 'cancelled'
     order by e.created_at;
end $function$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- 7. Re-issue activate_purchased_therapy (membership_expiry -> therapy_expiry).
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.activate_purchased_therapy(p_entitlement_id uuid, p_activation_date date DEFAULT NULL::date, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e public.purchased_therapy_entitlements%rowtype; v_today date := public.sg_today(); v_act date; v_exp date;
begin
  select * into e from public.purchased_therapy_entitlements where id = p_entitlement_id for update;
  if not found then raise exception 'Entitlement not found'; end if;
  if not public.user_has_store_access(e.store_id) then raise exception 'No access to this store'; end if;
  if e.status in ('active','expired','cancelled','refunded') then raise exception 'Entitlement is already %', e.status; end if;

  v_act := coalesce(p_activation_date, v_today);
  if v_act > e.activation_deadline then
    raise exception 'Activation must occur within one year of purchase (deadline %)', e.activation_deadline; end if;
  if v_act < v_today then raise exception 'Activation date cannot be in the past'; end if;

  v_exp := public.therapy_expiry(v_act, e.duration_months);   -- calendar-month expiry

  update public.purchased_therapy_entitlements
     set activation_date = v_act, expiry_date = v_exp,
         status = case when v_act > v_today then 'scheduled' else 'active' end,
         scheduled_date = case when v_act > v_today then v_act else scheduled_date end,
         updated_by = auth.uid(), updated_at = now()
   where id = p_entitlement_id;

  perform public.write_audit_ex('purchased_therapy_entitlements', p_entitlement_id,
    case when v_act > v_today then 'therapy_scheduled' else 'therapy_activated' end,
    jsonb_build_object('status', e.status),
    jsonb_build_object('activation', v_act, 'expiry', v_exp), 'therapy', p_reason, e.store_id);
end $function$;

-- ---------------------------------------------------------------------
-- 8. Re-issue earn_invoice_commission so the invoice affiliate is credited.
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
