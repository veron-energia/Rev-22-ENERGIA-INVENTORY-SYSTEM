-- =====================================================================
-- ENERGIA — CREDIT PACKAGES AND PREMIUM BUNDLES NO LONGER GRANT A
--           QUALIFICATION REWARD
--
-- Buying a Credit Package produced qualification reward units — Legacy
-- therapy entitlements derived from floor(credit / qualifying amount) — and a
-- Premium Bundle issued free reward vouchers derived from the same threshold.
-- Neither should happen any more.
--
-- Rather than deleting the behaviour outright it becomes a per-item switch,
-- `grants_reward`, so a package or bundle can grant a reward again later
-- without another migration. Every existing and new row is set to FALSE,
-- which is the requested behaviour.
--
-- Already-issued rewards are NOT touched: entitlements and vouchers a customer
-- has already received stay exactly as they are. This only changes what
-- future sales grant.
--
-- Additive and idempotent. Run AFTER 86.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. The switch, off by default and off for everything that exists.
-- ---------------------------------------------------------------------
alter table public.credit_packages  add column if not exists grants_reward boolean not null default false;
alter table public.premium_bundles  add column if not exists grants_reward boolean not null default false;

-- Anything created before this migration also stops granting a reward.
update public.credit_packages set grants_reward = false where grants_reward is distinct from false;
update public.premium_bundles set grants_reward = false where grants_reward is distinct from false;

-- ---------------------------------------------------------------------
-- 2. A credit package only creates reward units when it is switched on.
-- ---------------------------------------------------------------------
create or replace function public.issue_credit_package(
  p_package_id uuid, p_customer_id uuid, p_store_id uuid,
  p_external_paid numeric, p_invoice_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  pk public.credit_packages%rowtype;
  v_vouchers uuid[]; v_lot uuid; v_sale uuid;
  v_qual numeric; v_units integer; v_group uuid; v_deadline date;
  v_restrict jsonb; v_rule public.therapy_package_rules; i integer;
begin
  select * into pk from public.credit_packages where id = p_package_id and deleted_at is null;
  if not found then raise exception 'Credit package not found'; end if;
  if p_customer_id is null then raise exception 'A customer is required to issue package credit'; end if;

  select coalesce(array_agg(voucher_id), '{}') into v_vouchers
    from public.credit_package_vouchers where package_id = p_package_id;

  v_restrict := jsonb_build_object(
    'allowed_purposes', jsonb_build_array('voucher'),
    'allowed_voucher_ids', coalesce((select jsonb_agg(v::text) from unnest(v_vouchers) v), '[]'::jsonb),
    'source', 'credit_package');

  v_lot := public.grant_customer_credit(
    p_customer_id, 'paid', pk.paid_credit_amount, 'credit_package', p_package_id, p_store_id,
    public.sg_today(), null, 'Credit package: ' || pk.name, null, null, auth.uid(), v_restrict);

  v_rule := public.legacy_lowest_rule(p_store_id, public.sg_today());
  v_qual := coalesce(pk.reward_qualifying_amount, v_rule.qualifying_amount, 994);

  -- The qualification reward is only granted when the package is configured
  -- to grant one. By default a credit package gives credit and nothing else.
  v_units := case
    when not coalesce(pk.grants_reward, false) then 0
    when v_qual > 0 then floor(pk.paid_credit_amount / v_qual)::integer
    else 0 end;

  insert into public.credit_package_sales (
    package_id, customer_id, store_id, invoice_id, package_name_snapshot,
    price_snapshot, credit_snapshot, classification_snapshot,
    tier1_rate_snapshot, tier2_rate_snapshot, staff_rate_snapshot,
    reward_qualifying_snapshot, eligible_voucher_ids, external_paid,
    credit_lot_id, reward_units, created_by)
  values (p_package_id, p_customer_id, p_store_id, p_invoice_id, pk.name,
    pk.customer_price, pk.paid_credit_amount, pk.commission_classification,
    pk.tier1_rate, pk.tier2_rate, pk.staff_commission_rate,
    v_qual, v_vouchers, coalesce(p_external_paid,0), v_lot, v_units, auth.uid())
  returning id into v_sale;

  if v_units > 0 then
    v_group := md5('credit_pkg:' || v_sale::text)::uuid;
    v_deadline := public.sg_today() + coalesce(v_rule.activation_deadline_days, 365);
    for i in 1 .. v_units loop
      insert into public.therapy_entitlements (
        entitlement_no, customer_id, store_id, rule_id, package_name,
        entitlement_kind, duration_months, voucher_qty, qualifying_amount,
        qualified_value, forfeited_value, activation_deadline, status,
        created_by, qualification_group_id, earner_kind)
      values (public.next_legacy_entitlement_no(), p_customer_id, p_store_id, null,
        'Credit package reward — ' || pk.name,
        'voucher', coalesce(v_rule.duration_months, 1), 10, v_qual,
        v_qual, round(pk.paid_credit_amount - (v_units * v_qual), 2), v_deadline,
        'pending_activation', auth.uid(), v_group, 'credit_package');
    end loop;
  end if;

  perform public.write_audit_ex('credit_package_sales', v_sale, 'credit_package_issued', null,
    jsonb_build_object('package', pk.name, 'credit', pk.paid_credit_amount,
      'external_paid', p_external_paid, 'reward_units', v_units,
      'grants_reward', coalesce(pk.grants_reward,false)), 'credit', null, p_store_id);

  return jsonb_build_object('sale_id', v_sale, 'credit_lot_id', v_lot,
    'credit_issued', pk.paid_credit_amount, 'reward_units', v_units,
    'grants_reward', coalesce(pk.grants_reward,false),
    'qualifying_amount', v_qual,
    'remainder', case when v_units > 0 then round(pk.paid_credit_amount - (v_units * v_qual), 2) else 0 end);
end $function$;

-- ---------------------------------------------------------------------
-- 3. A premium bundle only issues reward vouchers when switched on, and
--    stops asking for a voucher selection when it does not.
-- ---------------------------------------------------------------------
create or replace function public.validate_bundle_voucher_selection(
  p_bundle_id uuid, p_store_id uuid, p_selections jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare
  b public.premium_bundles%rowtype; v_sel jsonb; v_vid uuid; v_qty integer;
  v_sum integer := 0; v_stock integer; v_short text[] := '{}'; v_required integer;
begin
  select * into b from public.premium_bundles where id = p_bundle_id and deleted_at is null;
  if not found then raise exception 'Premium bundle not found'; end if;

  -- A bundle that grants no reward needs no vouchers chosen.
  v_required := case when coalesce(b.grants_reward,false) then b.free_voucher_qty else 0 end;

  for v_sel in select * from jsonb_array_elements(coalesce(p_selections,'[]'::jsonb)) loop
    v_vid := (v_sel->>'voucher_id')::uuid;
    v_qty := coalesce((v_sel->>'quantity')::integer, 0);
    if v_qty <= 0 then continue; end if;
    if not exists (select 1 from public.premium_bundle_vouchers
                    where bundle_id = p_bundle_id and voucher_id = v_vid) then
      raise exception 'Voucher "%" is not an eligible choice for this bundle',
        (select name from public.vouchers where id = v_vid);
    end if;
    v_sum := v_sum + v_qty;
    if exists (select 1 from public.vouchers where id = v_vid and qty_type <> 'unlimited') then
      select coalesce(current_qty,0) into v_stock from public.voucher_store_stock
       where voucher_id = v_vid and store_id = p_store_id;
      if coalesce(v_stock,0) < v_qty then
        v_short := array_append(v_short,
          (select name from public.vouchers where id = v_vid) || ' (need ' || v_qty
          || ', have ' || coalesce(v_stock,0) || ')');
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'required_qty', v_required, 'selected_qty', v_sum,
    'grants_reward', coalesce(b.grants_reward,false),
    'complete', v_sum = v_required,
    'stock_ok', array_length(v_short,1) is null,
    'shortages', to_jsonb(v_short));
end $function$;

-- ---------------------------------------------------------------------
-- 4. One setter for the switch, mirroring set_catalogue_sku.
-- ---------------------------------------------------------------------
create or replace function public.set_catalogue_reward(
  p_kind text, p_id uuid, p_grants boolean)
returns void language plpgsql security definer set search_path to 'public' as $function$
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can change the reward setting'; end if;
  if p_kind = 'credit_package' then
    update public.credit_packages set grants_reward = coalesce(p_grants,false), updated_at = now() where id = p_id;
  elsif p_kind = 'premium_bundle' then
    update public.premium_bundles set grants_reward = coalesce(p_grants,false), updated_at = now() where id = p_id;
  else
    raise exception 'Unknown catalogue kind "%"', p_kind;
  end if;
end $function$;

notify pgrst, 'reload schema';
