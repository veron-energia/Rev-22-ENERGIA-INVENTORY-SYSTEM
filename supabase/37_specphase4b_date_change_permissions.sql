-- =====================================================================
-- ENERGIA — SPEC PHASE 4B REVISION: date-change permissions
--
-- Your decision: Owner, Manager AND Staff may request an activation- or
-- ending-date change, and each self-approves immediately. Inventory
-- Manager still cannot.
--
-- Effect: every date-change request auto-approves, so the request/approve
-- pair now acts as an AUDIT TRAIL (who, when, old -> new, reason) rather
-- than a gate. The reason stays mandatory and overlap validation still
-- runs on every change.
--
-- Staff are restricted to entitlements sold by THEIR store (same rule as
-- activation).
--
-- Replaces the two functions from 36. Additive + idempotent.
-- Run AFTER 36_specphase4b_therapy_activation.sql.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- Who may change therapy dates: everyone who may activate.
-- ---------------------------------------------------------------------
create or replace function public.can_change_therapy_dates(p_store_id uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare v_role user_role;
begin
  v_role := public.current_user_role();
  if v_role is null then return false; end if;
  if v_role = 'inventory_manager' then return false; end if;
  if v_role = 'staff' then
    return public.my_assigned_store_id() is not distinct from p_store_id;
  end if;
  return true;   -- owner / admin / manager
end $$;

-- ---------------------------------------------------------------------
-- Request a date change. All permitted roles self-approve immediately.
-- ---------------------------------------------------------------------
create or replace function public.request_therapy_date_change(
  p_beneficiary_id uuid, p_field text, p_new_value date, p_reason text
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_b public.therapy_entitlement_beneficiaries%rowtype;
  v_ent public.therapy_entitlements%rowtype;
  v_role user_role; v_old date; v_id uuid;
begin
  v_role := public.current_user_role();
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason is required'; end if;
  if p_field not in ('activation_date','ending_date') then raise exception 'Invalid field'; end if;

  select * into v_b from public.therapy_entitlement_beneficiaries where id = p_beneficiary_id;
  if not found then raise exception 'Beneficiary not found'; end if;
  select * into v_ent from public.therapy_entitlements where id = v_b.entitlement_id;

  if not public.can_change_therapy_dates(v_ent.store_id) then
    raise exception 'You do not have permission to change therapy dates for this entitlement';
  end if;

  v_old := case p_field when 'activation_date' then v_b.activation_date else v_b.ending_date end;

  insert into public.therapy_date_change_requests
    (beneficiary_id, field, old_value, new_value, reason, status, requested_by, requested_role)
  values (p_beneficiary_id, p_field, v_old, p_new_value, trim(p_reason), 'pending', auth.uid(), v_role::text)
  returning id into v_id;

  perform public.write_audit_ex('therapy_date_change_requests', v_id, 'therapy_date_change_requested',
    jsonb_build_object('old', v_old), jsonb_build_object('new', p_new_value), 'therapy', p_reason, v_ent.store_id);

  -- Owner, Manager and Staff all self-approve immediately.
  perform public.approve_therapy_date_change(v_id);
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Approve (self-approval for all permitted roles).
-- ---------------------------------------------------------------------
create or replace function public.approve_therapy_date_change(p_request_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_r public.therapy_date_change_requests%rowtype;
  v_b public.therapy_entitlement_beneficiaries%rowtype;
  v_ent public.therapy_entitlements%rowtype;
  v_act date; v_end date; v_clash integer;
begin
  select * into v_r from public.therapy_date_change_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if v_r.status <> 'pending' then raise exception 'Request is not pending'; end if;

  select * into v_b from public.therapy_entitlement_beneficiaries where id = v_r.beneficiary_id for update;
  select * into v_ent from public.therapy_entitlements where id = v_b.entitlement_id;

  if not public.can_change_therapy_dates(v_ent.store_id) then
    raise exception 'You do not have permission to change therapy dates for this entitlement';
  end if;

  v_act := v_b.activation_date; v_end := v_b.ending_date;
  if v_r.field = 'activation_date' then
    v_act := v_r.new_value;
    -- Ending date recalculates automatically from the new activation date.
    if v_ent.entitlement_kind = 'unlimited' then
      v_end := public.therapy_ending_date(v_act, v_b.portion_months);
    end if;
  else
    v_end := v_r.new_value;   -- manual override of the ending date
  end if;

  -- Overlap validation still applies.
  if v_ent.entitlement_kind = 'unlimited' and v_act is not null then
    select count(*) into v_clash
    from public.therapy_entitlement_beneficiaries b2
    join public.therapy_entitlements e2 on e2.id = b2.entitlement_id
    where b2.beneficiary_customer_id = v_b.beneficiary_customer_id
      and b2.id <> v_b.id and b2.status <> 'cancelled'
      and b2.activation_date is not null and e2.entitlement_kind = 'unlimited'
      and daterange(b2.activation_date, b2.ending_date, '[]') && daterange(v_act, v_end, '[]');
    if v_clash > 0 then
      raise exception 'That change would overlap another therapy period for this beneficiary'; end if;
  end if;

  update public.therapy_entitlement_beneficiaries
    set activation_date = v_act, ending_date = v_end,
        status = public.therapy_effective_status(status, v_act, v_end, v_ent.activation_deadline),
        updated_at = now()
    where id = v_b.id;

  update public.therapy_date_change_requests
    set status = 'approved', approved_by = auth.uid(), approved_at = now()
    where id = p_request_id;

  perform public.write_audit_ex('therapy_date_change_requests', p_request_id, 'therapy_date_change_approved',
    jsonb_build_object('old', v_r.old_value), jsonb_build_object('new', v_r.new_value, 'ending_date', v_end),
    'therapy', v_r.reason, v_ent.store_id);
end $$;

-- ---------------------------------------------------------------------
-- Reject stays available (kept for completeness / future gating).
-- ---------------------------------------------------------------------
create or replace function public.reject_therapy_date_change(p_request_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_r public.therapy_date_change_requests%rowtype; v_b public.therapy_entitlement_beneficiaries%rowtype;
        v_ent public.therapy_entitlements%rowtype;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A rejection reason is required'; end if;
  select * into v_r from public.therapy_date_change_requests where id = p_request_id;
  if not found then raise exception 'Request not found'; end if;
  select * into v_b from public.therapy_entitlement_beneficiaries where id = v_r.beneficiary_id;
  select * into v_ent from public.therapy_entitlements where id = v_b.entitlement_id;
  if not public.can_change_therapy_dates(v_ent.store_id) then
    raise exception 'You do not have permission to reject this request'; end if;

  update public.therapy_date_change_requests
    set status = 'rejected', approved_by = auth.uid(), approved_at = now(), rejection_reason = trim(p_reason)
    where id = p_request_id and status = 'pending';
  perform public.write_audit_ex('therapy_date_change_requests', p_request_id, 'therapy_date_change_rejected',
    null, null, 'therapy', p_reason, v_ent.store_id);
end $$;

notify pgrst, 'reload schema';
