-- =====================================================================
-- ENERGIA — PHASE 24: TIERED LEGACY QUALIFICATION, INVOICE LINKING,
--                      BACKFILL AND DIAGNOSTICS
--
-- Fixes why a paid invoice earned no claimable Legacy therapy.
--
--   1. TIERED RULES. therapy_package_rules holds several tiers (e.g. 794 ->
--      1 month, 3994 -> 12 months). Phase 22 picked ONE rule ("limit 1", the
--      newest) and divided by it, so a S$1034 day measured against the 3994
--      tier earned floor(1034/3994) = 0 units. Qualification now picks the
--      BEST tier the day's total actually reaches (the highest qualifying
--      amount <= the day total) and divides by that.
--
--   2. INVOICE LINKING. Phase 22 never wrote therapy_entitlement_invoices,
--      so invoice_therapy_summary always reported "hasn't been used for
--      therapy qualification yet — it's still eligible", even after the day
--      had earned an entitlement. Qualifying invoices are now linked to the
--      entitlements they produced, with the amount each contributed.
--
--   3. BACKFILL. Phase 22 only ran from the payment trigger, so invoices
--      that were already paid before the migration were never evaluated.
--      backfill_legacy_qualification() re-evaluates historical paid days.
--
--   4. RULE EFFECTIVE DATE. A rule created today did not apply to earlier
--      days, so backfilling found no rule. upsert_legacy_rule() now accepts
--      an effective date so a rule can be backdated.
--
--   5. DIAGNOSTICS. legacy_qualification_diagnose() explains exactly why a
--      given customer/store/day did or did not earn anything.
--
-- Additive and idempotent. Run AFTER 72.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Tier lookup: the best rule the day's total actually reaches.
-- ---------------------------------------------------------------------
create or replace function public.legacy_rule_for_amount(
  p_store_id uuid, p_day date, p_amount numeric)
returns public.therapy_package_rules
language sql stable security definer set search_path to 'public' as $function$
  select r.* from public.therapy_package_rules r
   where r.is_active = true and r.deleted_at is null
     and coalesce(r.qualifying_amount, 0) > 0
     and (r.store_id = p_store_id or r.store_id is null)
     and r.effective_date <= p_day
     and r.qualifying_amount <= coalesce(p_amount, 0)
   order by r.qualifying_amount desc,
            (r.store_id = p_store_id) desc,
            r.effective_date desc, r.created_at desc
   limit 1
$function$;

-- The cheapest tier available (used to tell staff how far off a customer is).
create or replace function public.legacy_lowest_rule(p_store_id uuid, p_day date)
returns public.therapy_package_rules
language sql stable security definer set search_path to 'public' as $function$
  select r.* from public.therapy_package_rules r
   where r.is_active = true and r.deleted_at is null
     and coalesce(r.qualifying_amount, 0) > 0
     and (r.store_id = p_store_id or r.store_id is null)
     and r.effective_date <= p_day
   order by r.qualifying_amount asc,
            (r.store_id = p_store_id) desc,
            r.effective_date desc, r.created_at desc
   limit 1
$function$;

-- ---------------------------------------------------------------------
-- 2. Recompute, now tier-aware and linking the invoices that qualified.
-- ---------------------------------------------------------------------
create or replace function public.recompute_legacy_qualification(
  p_customer_id uuid, p_store_id uuid, p_day date)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_rule public.therapy_package_rules;
  v_group uuid;
  v_day_charged numeric;
  v_units_target integer;
  v_units_locked integer;
  v_pending_needed integer;
  v_pending_have integer;
  v_deadline date;
  v_e record; v_first uuid;
  v_created integer := 0; v_cancelled integer := 0;
begin
  if p_customer_id is null or p_store_id is null or p_day is null then
    return jsonb_build_object('skipped', true, 'reason', 'missing customer, store or day');
  end if;

  v_group := public.legacy_qualification_group(p_customer_id, p_store_id, p_day);

  -- The day's actual charged value at this store.
  select coalesce(sum(i.paid_amount), 0) into v_day_charged
    from public.invoices i
   where i.customer_id = p_customer_id
     and i.store_id = p_store_id
     and i.status in ('paid','partially_paid')
     and coalesce(i.paid_amount,0) > 0
     and (i.paid_at at time zone 'Asia/Singapore')::date = p_day;

  -- Best tier the day's total reaches.
  v_rule := public.legacy_rule_for_amount(p_store_id, p_day, v_day_charged);

  -- Entitlements already locked in (claimed/activated) can never be revoked.
  select count(*) into v_units_locked
    from public.therapy_entitlements
   where qualification_group_id = v_group
     and status not in ('pending_activation','cancelled');

  if v_rule.id is null or coalesce(v_rule.qualifying_amount,0) <= 0 then
    v_units_target := 0;
  else
    v_units_target := floor(v_day_charged / v_rule.qualifying_amount)::integer;
  end if;

  v_pending_needed := greatest(v_units_target - v_units_locked, 0);

  -- A pending entitlement from a different tier is no longer right: cancel it
  -- so the correct tier can be granted instead.
  if v_rule.id is not null then
    for v_e in
      select id from public.therapy_entitlements
       where qualification_group_id = v_group and status = 'pending_activation'
         and rule_id is distinct from v_rule.id
    loop
      update public.therapy_entitlements set status = 'cancelled' where id = v_e.id;
      v_cancelled := v_cancelled + 1;
    end loop;
  end if;

  select count(*) into v_pending_have
    from public.therapy_entitlements
   where qualification_group_id = v_group and status = 'pending_activation';

  if v_pending_have < v_pending_needed then
    v_deadline := p_day + coalesce(v_rule.activation_deadline_days, 365);
    for i in 1 .. (v_pending_needed - v_pending_have) loop
      insert into public.therapy_entitlements (
        entitlement_no, customer_id, store_id, rule_id, package_name,
        entitlement_kind, duration_months, voucher_qty, qualifying_amount,
        qualified_value, forfeited_value, activation_deadline, status,
        created_by, qualification_group_id)
      values (
        public.next_legacy_entitlement_no(), p_customer_id, p_store_id, v_rule.id,
        coalesce(v_rule.name, 'Legacy Therapy'),
        coalesce(v_rule.entitlement_kind, 'unlimited'), v_rule.duration_months,
        v_rule.voucher_qty, v_rule.qualifying_amount,
        v_rule.qualifying_amount, 0, v_deadline, 'pending_activation',
        auth.uid(), v_group);
      v_created := v_created + 1;
    end loop;
  elsif v_pending_have > v_pending_needed then
    for v_e in
      select id from public.therapy_entitlements
       where qualification_group_id = v_group and status = 'pending_activation'
       order by created_at desc
       limit (v_pending_have - v_pending_needed)
    loop
      update public.therapy_entitlements set status = 'cancelled' where id = v_e.id;
      v_cancelled := v_cancelled + 1;
    end loop;
  end if;

  -- Record the day's leftover on the surviving pending rows.
  if v_rule.id is not null and coalesce(v_rule.qualifying_amount,0) > 0 then
    update public.therapy_entitlements
       set forfeited_value = round(v_day_charged - (v_units_target * v_rule.qualifying_amount), 2)
     where qualification_group_id = v_group and status = 'pending_activation';
  end if;

  -- Link the invoices that produced this qualification, so the invoice stops
  -- reporting itself as unused and the therapy summary can explain it.
  select id into v_first from public.therapy_entitlements
   where qualification_group_id = v_group and status <> 'cancelled'
   order by created_at limit 1;

  delete from public.therapy_entitlement_invoices tei
   using public.therapy_entitlements e
   where tei.entitlement_id = e.id and e.qualification_group_id = v_group;

  if v_first is not null then
    insert into public.therapy_entitlement_invoices (entitlement_id, invoice_id, contributed_amount)
    select v_first, i.id, i.paid_amount
      from public.invoices i
     where i.customer_id = p_customer_id
       and i.store_id = p_store_id
       and i.status in ('paid','partially_paid')
       and coalesce(i.paid_amount,0) > 0
       and (i.paid_at at time zone 'Asia/Singapore')::date = p_day;
  end if;

  if v_created > 0 or v_cancelled > 0 then
    perform public.write_audit_ex('therapy_entitlements', null, 'legacy_qualification_recomputed',
      null,
      jsonb_build_object('customer', p_customer_id, 'day', p_day, 'day_charged', v_day_charged,
        'tier', v_rule.name, 'qualifying_amount', v_rule.qualifying_amount,
        'units_target', v_units_target, 'created', v_created, 'cancelled', v_cancelled),
      'therapy', null, p_store_id);
  end if;

  return jsonb_build_object(
    'day_charged', v_day_charged,
    'tier_name', v_rule.name,
    'qualifying_amount', coalesce(v_rule.qualifying_amount, 0),
    'units_target', v_units_target,
    'units_locked', v_units_locked,
    'pending', greatest(v_pending_needed, 0),
    'created', v_created, 'cancelled', v_cancelled,
    'remainder', case when v_rule.id is null then v_day_charged
                      else round(v_day_charged - (v_units_target * v_rule.qualifying_amount), 2) end);
end $function$;

-- ---------------------------------------------------------------------
-- 3. Progress read model, tier-aware.
-- ---------------------------------------------------------------------
create or replace function public.legacy_qualification_progress(
  p_customer_id uuid, p_store_id uuid, p_day date default null)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare
  v_day date := coalesce(p_day, public.sg_today());
  v_best public.therapy_package_rules; v_low public.therapy_package_rules;
  v_charged numeric;
begin
  select coalesce(sum(i.paid_amount),0) into v_charged
    from public.invoices i
   where i.customer_id = p_customer_id and i.store_id = p_store_id
     and i.status in ('paid','partially_paid') and coalesce(i.paid_amount,0) > 0
     and (i.paid_at at time zone 'Asia/Singapore')::date = v_day;

  v_best := public.legacy_rule_for_amount(p_store_id, v_day, v_charged);
  v_low  := public.legacy_lowest_rule(p_store_id, v_day);

  if v_low.id is null then
    return jsonb_build_object('has_rule', false, 'day', v_day, 'day_charged', v_charged);
  end if;

  if v_best.id is null then
    -- Spend has not reached even the cheapest tier yet.
    return jsonb_build_object('has_rule', true, 'day', v_day, 'day_charged', v_charged,
      'units_earned', 0, 'qualifying_amount', v_low.qualifying_amount,
      'rule_name', v_low.name, 'remainder', v_charged,
      'to_next_unit', round(v_low.qualifying_amount - v_charged, 2));
  end if;

  return jsonb_build_object(
    'has_rule', true, 'day', v_day, 'day_charged', v_charged,
    'qualifying_amount', v_best.qualifying_amount, 'rule_name', v_best.name,
    'units_earned', floor(v_charged / v_best.qualifying_amount)::integer,
    'remainder', round(v_charged - floor(v_charged / v_best.qualifying_amount) * v_best.qualifying_amount, 2),
    'to_next_unit', round((floor(v_charged / v_best.qualifying_amount) + 1) * v_best.qualifying_amount - v_charged, 2));
end $function$;

-- ---------------------------------------------------------------------
-- 4. Diagnosis: why did this customer/store/day earn nothing?
-- ---------------------------------------------------------------------
create or replace function public.legacy_qualification_diagnose(
  p_customer_id uuid, p_store_id uuid, p_day date default null)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare
  v_day date := coalesce(p_day, public.sg_today());
  v_charged numeric; v_invoices integer;
  v_rules_any integer; v_rules_effective integer;
  v_best public.therapy_package_rules; v_low public.therapy_package_rules;
  v_group uuid; v_have integer; v_reason text;
begin
  if p_customer_id is null then
    return jsonb_build_object('qualifies', false, 'reason', 'This invoice has no customer, so nothing can be earned.');
  end if;

  select coalesce(sum(i.paid_amount),0), count(*) into v_charged, v_invoices
    from public.invoices i
   where i.customer_id = p_customer_id and i.store_id = p_store_id
     and i.status in ('paid','partially_paid') and coalesce(i.paid_amount,0) > 0
     and (i.paid_at at time zone 'Asia/Singapore')::date = v_day;

  select count(*) into v_rules_any from public.therapy_package_rules
   where is_active = true and deleted_at is null and coalesce(qualifying_amount,0) > 0
     and (store_id = p_store_id or store_id is null);
  select count(*) into v_rules_effective from public.therapy_package_rules
   where is_active = true and deleted_at is null and coalesce(qualifying_amount,0) > 0
     and (store_id = p_store_id or store_id is null) and effective_date <= v_day;

  v_best := public.legacy_rule_for_amount(p_store_id, v_day, v_charged);
  v_low  := public.legacy_lowest_rule(p_store_id, v_day);
  v_group := public.legacy_qualification_group(p_customer_id, p_store_id, v_day);
  select count(*) into v_have from public.therapy_entitlements
   where qualification_group_id = v_group and status <> 'cancelled';

  if v_invoices = 0 then
    v_reason := 'No paid invoices for this customer at this store on ' || v_day || '.';
  elsif v_rules_any = 0 then
    v_reason := 'No active qualification rule exists for this store. Add one under Therapy → Qualification.';
  elsif v_rules_effective = 0 then
    v_reason := 'A qualification rule exists but its effective date is after ' || v_day ||
                '. Backdate the rule to cover this day.';
  elsif v_best.id is null then
    v_reason := 'The day total of ' || v_charged || ' has not reached the lowest tier of ' ||
                v_low.qualifying_amount || ' (short by ' || round(v_low.qualifying_amount - v_charged, 2) || ').';
  elsif v_have = 0 then
    v_reason := 'This day qualifies but has not been computed yet — run the backfill.';
  else
    v_reason := 'Qualified.';
  end if;

  return jsonb_build_object(
    'qualifies', v_best.id is not null, 'day', v_day,
    'day_charged', v_charged, 'paid_invoices', v_invoices,
    'rules_for_store', v_rules_any, 'rules_effective_on_day', v_rules_effective,
    'best_tier', v_best.name, 'best_tier_amount', v_best.qualifying_amount,
    'lowest_tier_amount', v_low.qualifying_amount,
    'units_target', case when v_best.id is null then 0
                         else floor(v_charged / v_best.qualifying_amount)::integer end,
    'entitlements_existing', v_have, 'reason', v_reason);
end $function$;

-- ---------------------------------------------------------------------
-- 5. Backfill historical paid days (Owner/Manager).
-- ---------------------------------------------------------------------
create or replace function public.backfill_legacy_qualification(
  p_from date default null, p_to date default null, p_store_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_r record; v_res jsonb;
  v_days integer := 0; v_created integer := 0; v_cancelled integer := 0;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can run the qualification backfill';
  end if;

  for v_r in
    select i.customer_id, i.store_id,
           (i.paid_at at time zone 'Asia/Singapore')::date as day
      from public.invoices i
     where i.customer_id is not null and i.store_id is not null
       and i.status in ('paid','partially_paid') and coalesce(i.paid_amount,0) > 0
       and i.paid_at is not null
       and (p_store_id is null or i.store_id = p_store_id)
       and (p_from is null or (i.paid_at at time zone 'Asia/Singapore')::date >= p_from)
       and (p_to   is null or (i.paid_at at time zone 'Asia/Singapore')::date <= p_to)
     group by 1,2,3
     order by 3
  loop
    v_res := public.recompute_legacy_qualification(v_r.customer_id, v_r.store_id, v_r.day);
    v_days := v_days + 1;
    v_created := v_created + coalesce((v_res->>'created')::integer, 0);
    v_cancelled := v_cancelled + coalesce((v_res->>'cancelled')::integer, 0);
  end loop;

  perform public.write_audit_ex('therapy_entitlements', null, 'legacy_qualification_backfilled',
    null, jsonb_build_object('days', v_days, 'created', v_created, 'cancelled', v_cancelled,
      'from', p_from, 'to', p_to, 'store', p_store_id), 'therapy', null, p_store_id);

  return jsonb_build_object('days_evaluated', v_days, 'created', v_created, 'cancelled', v_cancelled);
end $function$;

-- ---------------------------------------------------------------------
-- 6. Rules can now be backdated so a backfill can find them.
-- ---------------------------------------------------------------------
-- Drop the previous 9-argument form first, otherwise adding the optional
-- effective-date parameter creates an ambiguous overload.
drop function if exists public.upsert_legacy_rule(uuid, uuid, text, numeric, text, integer, integer, integer, boolean);

create or replace function public.upsert_legacy_rule(
  p_id uuid, p_store_id uuid, p_name text, p_qualifying_amount numeric,
  p_entitlement_kind text, p_duration_months integer, p_voucher_qty integer,
  p_activation_deadline_days integer, p_is_active boolean,
  p_effective_date date default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid;
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit qualification rules'; end if;
  if coalesce(p_qualifying_amount,0) <= 0 then raise exception 'Qualifying amount must be greater than zero'; end if;
  if p_entitlement_kind not in ('unlimited','voucher') then raise exception 'Entitlement kind must be unlimited or voucher'; end if;
  if p_entitlement_kind = 'voucher' and coalesce(p_voucher_qty,0) <= 0 then raise exception 'Voucher reward needs a voucher quantity'; end if;

  if p_id is null then
    insert into public.therapy_package_rules (store_id, name, qualifying_amount, entitlement_kind,
      duration_months, voucher_qty, activation_deadline_days, is_active, effective_date)
    values (p_store_id, coalesce(nullif(trim(p_name),''),'Legacy Qualification'), p_qualifying_amount,
      p_entitlement_kind, p_duration_months, p_voucher_qty, coalesce(p_activation_deadline_days,365),
      coalesce(p_is_active,true), coalesce(p_effective_date, public.sg_today()))
    returning id into v_id;
  else
    update public.therapy_package_rules
       set store_id = p_store_id, name = coalesce(nullif(trim(p_name),''),'Legacy Qualification'),
           qualifying_amount = p_qualifying_amount, entitlement_kind = p_entitlement_kind,
           duration_months = p_duration_months, voucher_qty = p_voucher_qty,
           activation_deadline_days = coalesce(p_activation_deadline_days,365),
           is_active = coalesce(p_is_active,true),
           effective_date = coalesce(p_effective_date, effective_date), updated_at = now()
     where id = p_id
    returning id into v_id;
  end if;

  perform public.write_audit_ex('therapy_package_rules', v_id, 'legacy_rule_upserted',
    null, jsonb_build_object('name', p_name, 'qualifying_amount', p_qualifying_amount,
      'kind', p_entitlement_kind, 'store', p_store_id, 'effective_date', p_effective_date),
    'therapy', null, p_store_id);
  return v_id;
end $function$;

notify pgrst, 'reload schema';
