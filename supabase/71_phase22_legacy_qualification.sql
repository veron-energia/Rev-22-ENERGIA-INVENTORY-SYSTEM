-- =====================================================================
-- ENERGIA — PHASE 22: CUSTOMER SAME-DAY LEGACY QUALIFICATION
--
-- When a customer's PAID invoices at a store, on the same Asia/Singapore
-- calendar day, total at least the store's qualifying amount, the customer
-- earns floor(day_total / qualifying_amount) Legacy therapy entitlements.
--
--   * The qualifying total is the sum of the ACTUAL CHARGED value
--     (paid_amount) of that customer's invoices whose SG paid-date is that
--     day, at that store. Therapy purchases count; FOC value does not.
--   * The threshold and the reward (kind / duration / voucher qty /
--     activation window) are a CONFIGURABLE rule in therapy_package_rules.
--   * The remainder (day_total mod qualifying_amount) carries within the
--     same day — a later same-day invoice adds to the running total and can
--     push the unit count up — but never rolls over to another day.
--   * Recomputes automatically whenever an invoice is paid, and re-evaluates
--     on later same-day payments, refunds or edits: still-pending
--     entitlements are added or cancelled to match the day's unit count.
--     Already-activated entitlements are never revoked.
--   * Earned units are PENDING entitlements in therapy_entitlements with an
--     activation_deadline; claiming/activating them is a later phase.
--
-- Additive and idempotent. Run AFTER 70.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Numbering for Legacy entitlements (distinct from purchased UTP-).
-- ---------------------------------------------------------------------
create sequence if not exists public.legacy_entitlement_no_seq;

create or replace function public.next_legacy_entitlement_no()
returns text language sql security definer set search_path to 'public' as $function$
  select 'LEG-' || lpad(nextval('legacy_entitlement_no_seq')::text, 7, '0')
$function$;

-- A stable per-(customer, store, day) group id so recomputes are idempotent.
create or replace function public.legacy_qualification_group(p_customer_id uuid, p_store_id uuid, p_day date)
returns uuid language sql immutable as $function$
  select md5('legacy:' || p_customer_id::text || ':' || p_store_id::text || ':' || p_day::text)::uuid
$function$;

-- ---------------------------------------------------------------------
-- 2. The active qualification rule for a store on a given day.
--    Prefer a store-specific rule; fall back to a global (store_id null)
--    rule. Newest effective rule on/at the day wins.
-- ---------------------------------------------------------------------
create or replace function public.legacy_rule_for(p_store_id uuid, p_day date)
returns public.therapy_package_rules language sql stable security definer set search_path to 'public' as $function$
  select r.* from public.therapy_package_rules r
   where r.is_active = true and r.deleted_at is null
     and coalesce(r.qualifying_amount, 0) > 0
     and (r.store_id = p_store_id or r.store_id is null)
     and r.effective_date <= p_day
   order by (r.store_id = p_store_id) desc, r.effective_date desc, r.created_at desc
   limit 1
$function$;

-- ---------------------------------------------------------------------
-- 3. Recompute a customer's same-day Legacy qualification at a store.
--    Idempotent: brings the number of PENDING entitlements for that
--    (customer, store, day) into line with the day's earned unit count.
-- ---------------------------------------------------------------------
create or replace function public.recompute_legacy_qualification(
  p_customer_id uuid, p_store_id uuid, p_day date)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_rule public.therapy_package_rules;
  v_group uuid;
  v_day_charged numeric;
  v_units_target integer;
  v_units_activated integer;
  v_pending_needed integer;
  v_pending_have integer;
  v_deadline date;
  v_e record;
  v_created integer := 0; v_cancelled integer := 0;
begin
  if p_customer_id is null or p_store_id is null or p_day is null then
    return jsonb_build_object('skipped', true, 'reason', 'missing key');
  end if;

  v_rule := public.legacy_rule_for(p_store_id, p_day);
  v_group := public.legacy_qualification_group(p_customer_id, p_store_id, p_day);

  -- Sum the ACTUAL CHARGED value (paid_amount) of this customer's invoices
  -- whose SG paid-date is p_day, at this store. FOC value is excluded because
  -- it is never part of paid_amount; therapy purchases are included.
  select coalesce(sum(i.paid_amount), 0) into v_day_charged
    from public.invoices i
   where i.customer_id = p_customer_id
     and i.store_id = p_store_id
     and i.status in ('paid','partially_paid')
     and coalesce(i.paid_amount,0) > 0
     and (i.paid_at at time zone 'Asia/Singapore')::date = p_day;

  -- How many entitlements are already activated (or beyond pending) for this
  -- group — these are locked and can never be revoked.
  select count(*) into v_units_activated
    from public.therapy_entitlements
   where qualification_group_id = v_group
     and status not in ('pending_activation','cancelled');

  if v_rule.id is null or coalesce(v_rule.qualifying_amount,0) <= 0 then
    v_units_target := 0;
  else
    v_units_target := floor(v_day_charged / v_rule.qualifying_amount)::integer;
  end if;

  -- Never below what is already locked in.
  v_pending_needed := greatest(v_units_target - v_units_activated, 0);

  select count(*) into v_pending_have
    from public.therapy_entitlements
   where qualification_group_id = v_group and status = 'pending_activation';

  if v_pending_have < v_pending_needed then
    -- Create the missing pending entitlements.
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
    -- Day total dropped (refund / edit): cancel the newest still-pending
    -- entitlements down to the new target. Activated ones are untouched.
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

  -- Record the day's leftover as the forfeited remainder on the group's rows
  -- (informational: it is only "forfeited" in the sense that it never rolls to
  -- another day). Kept on each row for reporting parity with the old system.
  if v_rule.id is not null and coalesce(v_rule.qualifying_amount,0) > 0 then
    update public.therapy_entitlements
       set forfeited_value = round(v_day_charged - (v_units_target * v_rule.qualifying_amount), 2)
     where qualification_group_id = v_group and status = 'pending_activation';
  end if;

  if v_created > 0 or v_cancelled > 0 then
    perform public.write_audit_ex('therapy_entitlements', null, 'legacy_qualification_recomputed',
      null,
      jsonb_build_object('customer', p_customer_id, 'day', p_day, 'day_charged', v_day_charged,
        'qualifying_amount', v_rule.qualifying_amount, 'units_target', v_units_target,
        'created', v_created, 'cancelled', v_cancelled),
      'therapy', null, p_store_id);
  end if;

  return jsonb_build_object(
    'day_charged', v_day_charged,
    'qualifying_amount', coalesce(v_rule.qualifying_amount, 0),
    'units_target', v_units_target,
    'units_activated', v_units_activated,
    'pending', greatest(v_pending_needed, 0),
    'created', v_created, 'cancelled', v_cancelled,
    'remainder', case when v_rule.id is null or coalesce(v_rule.qualifying_amount,0) <= 0 then 0
                      else round(v_day_charged - (v_units_target * v_rule.qualifying_amount), 2) end);
end $function$;

-- Convenience wrapper: recompute for a specific invoice (uses its SG paid-date).
create or replace function public.recompute_legacy_qualification_for_invoice(p_invoice_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_inv public.invoices%rowtype; v_day date;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found or v_inv.customer_id is null or v_inv.store_id is null then
    return jsonb_build_object('skipped', true);
  end if;
  v_day := (coalesce(v_inv.paid_at, now()) at time zone 'Asia/Singapore')::date;
  return public.recompute_legacy_qualification(v_inv.customer_id, v_inv.store_id, v_day);
end $function$;

-- ---------------------------------------------------------------------
-- 4. Hook into the payment lifecycle. The existing trigger already fires
--    when an invoice becomes paid / completed_foc; extend it to also
--    recompute same-day Legacy qualification. Also recompute when
--    paid_amount changes on an already-paid invoice (partial pay, refund).
-- ---------------------------------------------------------------------
create or replace function public.trg_create_therapy_on_paid()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.status in ('paid','completed_foc') and old.status is distinct from new.status then
    if exists (select 1 from public.invoice_items where invoice_id = new.id and line_kind = 'therapy') then
      perform public.create_purchased_therapy_for_invoice(new.id);
    end if;
  end if;

  -- Same-day Legacy qualification: recompute whenever the paid picture of
  -- this invoice changes (new payment, status change, or refund).
  if (new.status is distinct from old.status)
     or (coalesce(new.paid_amount,0) is distinct from coalesce(old.paid_amount,0)) then
    if new.customer_id is not null and new.store_id is not null then
      perform public.recompute_legacy_qualification(
        new.customer_id, new.store_id,
        (coalesce(new.paid_at, now()) at time zone 'Asia/Singapore')::date);
    end if;
  end if;

  return null;
end $function$;

-- ---------------------------------------------------------------------
-- 5. Read model for the UI / reports: a customer's same-day progress
--    toward the next Legacy unit at a store.
-- ---------------------------------------------------------------------
create or replace function public.legacy_qualification_progress(
  p_customer_id uuid, p_store_id uuid, p_day date default null)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare
  v_day date := coalesce(p_day, public.sg_today());
  v_rule public.therapy_package_rules;
  v_charged numeric;
begin
  v_rule := public.legacy_rule_for(p_store_id, v_day);
  select coalesce(sum(i.paid_amount),0) into v_charged
    from public.invoices i
   where i.customer_id = p_customer_id and i.store_id = p_store_id
     and i.status in ('paid','partially_paid') and coalesce(i.paid_amount,0) > 0
     and (i.paid_at at time zone 'Asia/Singapore')::date = v_day;

  if v_rule.id is null or coalesce(v_rule.qualifying_amount,0) <= 0 then
    return jsonb_build_object('has_rule', false, 'day', v_day, 'day_charged', v_charged);
  end if;

  return jsonb_build_object(
    'has_rule', true, 'day', v_day, 'day_charged', v_charged,
    'qualifying_amount', v_rule.qualifying_amount,
    'units_earned', floor(v_charged / v_rule.qualifying_amount)::integer,
    'remainder', round(v_charged - floor(v_charged / v_rule.qualifying_amount) * v_rule.qualifying_amount, 2),
    'to_next_unit', round((floor(v_charged / v_rule.qualifying_amount) + 1) * v_rule.qualifying_amount - v_charged, 2),
    'rule_name', v_rule.name);
end $function$;

-- ---------------------------------------------------------------------
-- 6. Owner/Manager management of qualification rules (make the threshold
--    and reward configurable from the app).
-- ---------------------------------------------------------------------
create or replace function public.upsert_legacy_rule(
  p_id uuid, p_store_id uuid, p_name text, p_qualifying_amount numeric,
  p_entitlement_kind text, p_duration_months integer, p_voucher_qty integer,
  p_activation_deadline_days integer, p_is_active boolean)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid;
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit qualification rules'; end if;
  if coalesce(p_qualifying_amount,0) <= 0 then raise exception 'Qualifying amount must be greater than zero'; end if;
  if p_entitlement_kind not in ('unlimited','voucher') then raise exception 'Entitlement kind must be unlimited or voucher'; end if;
  if p_entitlement_kind = 'voucher' and coalesce(p_voucher_qty,0) <= 0 then raise exception 'Voucher reward needs a voucher quantity'; end if;

  if p_id is null then
    insert into public.therapy_package_rules (store_id, name, qualifying_amount, entitlement_kind,
      duration_months, voucher_qty, activation_deadline_days, is_active)
    values (p_store_id, coalesce(nullif(trim(p_name),''),'Legacy Qualification'), p_qualifying_amount,
      p_entitlement_kind, p_duration_months, p_voucher_qty, coalesce(p_activation_deadline_days,365),
      coalesce(p_is_active,true))
    returning id into v_id;
  else
    update public.therapy_package_rules
       set store_id = p_store_id, name = coalesce(nullif(trim(p_name),''),'Legacy Qualification'),
           qualifying_amount = p_qualifying_amount, entitlement_kind = p_entitlement_kind,
           duration_months = p_duration_months, voucher_qty = p_voucher_qty,
           activation_deadline_days = coalesce(p_activation_deadline_days,365),
           is_active = coalesce(p_is_active,true), updated_at = now()
     where id = p_id
    returning id into v_id;
  end if;

  perform public.write_audit_ex('therapy_package_rules', v_id, 'legacy_rule_upserted',
    null, jsonb_build_object('name', p_name, 'qualifying_amount', p_qualifying_amount,
      'kind', p_entitlement_kind, 'store', p_store_id), 'therapy', null, p_store_id);
  return v_id;
end $function$;

notify pgrst, 'reload schema';
