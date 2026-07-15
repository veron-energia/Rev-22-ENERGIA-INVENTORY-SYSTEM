-- =====================================================================
-- ENERGIA — NEW SPEC PHASE 4B: Beneficiaries, activation, statuses,
--                              transfers, date-change requests
--
-- Builds on 4A's therapy_entitlements. Adds:
--   * therapy_entitlement_beneficiaries — who the entitlement is for, the
--     portion they get, activation/ending dates, and per-beneficiary status.
--   * Exact calendar-month ending dates (inclusive):
--       1 Aug + 1 month -> 31 Aug     15 Aug + 1 month -> 14 Sep
--     i.e. end = activation + N months - 1 day.
--   * No overlapping therapy periods for the same beneficiary.
--   * Statuses: pending_activation / scheduled / active / ended /
--     expired_before_activation / cancelled / suspended (auto by date).
--   * Transfer before activation (Staff, no approval); blocked after.
--   * Date-change requests: reason mandatory, old+new stored, audited.
--     Owner may approve their own; Manager requests need Owner approval.
--
-- Additive + idempotent. Run AFTER 35_specphase4a_therapy_qualification.sql.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Beneficiaries.
-- ---------------------------------------------------------------------
create table if not exists public.therapy_entitlement_beneficiaries (
  id uuid primary key default gen_random_uuid(),
  entitlement_id uuid not null references public.therapy_entitlements(id) on delete cascade,
  beneficiary_customer_id uuid not null references public.customers(id),
  portion_months integer,      -- for 'unlimited' entitlements
  portion_vouchers integer,    -- for 'voucher' entitlements
  activation_date date,
  ending_date date,
  status text not null default 'pending_activation',
  activated_by uuid references public.profiles(id),
  activated_at timestamptz,
  transferred_from uuid references public.customers(id),
  transferred_at timestamptz,
  cancelled_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_teb_ent on public.therapy_entitlement_beneficiaries(entitlement_id);
create index if not exists idx_teb_cust on public.therapy_entitlement_beneficiaries(beneficiary_customer_id);

alter table public.therapy_entitlement_beneficiaries enable row level security;
drop policy if exists "read beneficiaries" on public.therapy_entitlement_beneficiaries;
create policy "read beneficiaries" on public.therapy_entitlement_beneficiaries for select to authenticated
  using (exists (select 1 from public.therapy_entitlements e where e.id = entitlement_id
    and (public.is_manager_or_above() or public.user_has_store_access(e.store_id))));

-- ---------------------------------------------------------------------
-- 2. Date-change requests.
-- ---------------------------------------------------------------------
create table if not exists public.therapy_date_change_requests (
  id uuid primary key default gen_random_uuid(),
  beneficiary_id uuid not null references public.therapy_entitlement_beneficiaries(id) on delete cascade,
  field text not null check (field in ('activation_date','ending_date')),
  old_value date,
  new_value date not null,
  reason text not null,
  status approval_status not null default 'pending',
  requested_by uuid references public.profiles(id),
  requested_role text,
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now()
);
create index if not exists idx_tdcr_ben on public.therapy_date_change_requests(beneficiary_id);

alter table public.therapy_date_change_requests enable row level security;
drop policy if exists "read date changes" on public.therapy_date_change_requests;
create policy "read date changes" on public.therapy_date_change_requests for select to authenticated using (true);

-- ---------------------------------------------------------------------
-- 3. Calendar-month ending date (inclusive).
--    1 Aug + 1 month -> 31 Aug ; 15 Aug + 1 month -> 14 Sep
-- ---------------------------------------------------------------------
create or replace function public.therapy_ending_date(p_start date, p_months integer)
returns date language sql immutable as $$
  select (p_start + (p_months || ' months')::interval - interval '1 day')::date
$$;

-- ---------------------------------------------------------------------
-- 4. Effective status of a beneficiary row, derived from dates unless it
--    was explicitly cancelled/suspended.
-- ---------------------------------------------------------------------
create or replace function public.therapy_effective_status(
  p_status text, p_activation date, p_ending date, p_deadline date
) returns text language sql immutable as $$
  select case
    when p_status in ('cancelled','suspended') then p_status
    when p_activation is null and p_deadline < (now() at time zone 'Asia/Singapore')::date then 'expired_before_activation'
    when p_activation is null then 'pending_activation'
    when p_activation > (now() at time zone 'Asia/Singapore')::date then 'scheduled'
    when p_ending is not null and p_ending < (now() at time zone 'Asia/Singapore')::date then 'ended'
    else 'active'
  end
$$;

-- Refresh stored statuses (safe to run repeatedly; e.g. nightly or on load).
create or replace function public.refresh_therapy_statuses()
returns integer language plpgsql security definer set search_path = public as $$
declare v_count integer := 0;
begin
  update public.therapy_entitlement_beneficiaries b
    set status = public.therapy_effective_status(b.status, b.activation_date, b.ending_date, e.activation_deadline),
        updated_at = now()
  from public.therapy_entitlements e
  where e.id = b.entitlement_id
    and b.status <> public.therapy_effective_status(b.status, b.activation_date, b.ending_date, e.activation_deadline);
  get diagnostics v_count = row_count;

  -- Entitlement-level: expired if never activated past the deadline.
  update public.therapy_entitlements e
    set status = 'expired_before_activation'
  where e.status = 'pending_activation'
    and e.activation_deadline < public.sg_today()
    and not exists (select 1 from public.therapy_entitlement_beneficiaries b
                    where b.entitlement_id = e.id and b.activation_date is not null);
  return v_count;
end $$;

-- ---------------------------------------------------------------------
-- 5. Assign a beneficiary (portion of the entitlement).
-- ---------------------------------------------------------------------
create or replace function public.assign_therapy_beneficiary(
  p_entitlement_id uuid, p_customer_id uuid,
  p_portion_months integer default null, p_portion_vouchers integer default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_ent public.therapy_entitlements%rowtype; v_used integer; v_id uuid;
begin
  select * into v_ent from public.therapy_entitlements where id = p_entitlement_id for update;
  if not found then raise exception 'Entitlement not found'; end if;
  if not public.user_has_store_access(v_ent.store_id) then raise exception 'No access to that store'; end if;
  if v_ent.status in ('cancelled') then raise exception 'Entitlement is cancelled'; end if;

  -- Beneficiary must already exist as a customer.
  if not exists (select 1 from public.customers where id = p_customer_id and deleted_at is null) then
    raise exception 'Beneficiary must be an existing customer'; end if;

  if v_ent.entitlement_kind = 'unlimited' then
    if coalesce(p_portion_months,0) <= 0 then raise exception 'Portion (months) is required'; end if;
    select coalesce(sum(portion_months),0) into v_used from public.therapy_entitlement_beneficiaries
      where entitlement_id = p_entitlement_id and status <> 'cancelled';
    if v_used + p_portion_months > v_ent.duration_months then
      raise exception 'Only % month(s) remain on this entitlement', v_ent.duration_months - v_used; end if;
  else
    if coalesce(p_portion_vouchers,0) <= 0 then raise exception 'Portion (vouchers) is required'; end if;
    select coalesce(sum(portion_vouchers),0) into v_used from public.therapy_entitlement_beneficiaries
      where entitlement_id = p_entitlement_id and status <> 'cancelled';
    if v_used + p_portion_vouchers > v_ent.voucher_qty then
      raise exception 'Only % voucher(s) remain on this entitlement', v_ent.voucher_qty - v_used; end if;
  end if;

  insert into public.therapy_entitlement_beneficiaries
    (entitlement_id, beneficiary_customer_id, portion_months, portion_vouchers, status)
  values (p_entitlement_id, p_customer_id,
    case when v_ent.entitlement_kind = 'unlimited' then p_portion_months end,
    case when v_ent.entitlement_kind = 'voucher' then p_portion_vouchers end,
    'pending_activation')
  returning id into v_id;

  perform public.write_audit_ex('therapy_entitlement_beneficiaries', v_id, 'therapy_beneficiary_assigned', null,
    jsonb_build_object('entitlement', v_ent.entitlement_no, 'customer_id', p_customer_id,
      'portion_months', p_portion_months, 'portion_vouchers', p_portion_vouchers),
    'therapy', null, v_ent.store_id);
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 6. Activate a beneficiary's portion.
--    Owner / Manager / Admin, or Staff from the SELLING store.
--    Ending date = activation + portion months - 1 day (unlimited kind).
--    No overlapping periods for the same beneficiary.
-- ---------------------------------------------------------------------
create or replace function public.activate_therapy_beneficiary(
  p_beneficiary_id uuid, p_activation_date date, p_ending_override date default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_b public.therapy_entitlement_beneficiaries%rowtype;
  v_ent public.therapy_entitlements%rowtype; v_role user_role; v_end date; v_clash integer;
begin
  v_role := public.current_user_role();
  select * into v_b from public.therapy_entitlement_beneficiaries where id = p_beneficiary_id for update;
  if not found then raise exception 'Beneficiary not found'; end if;
  select * into v_ent from public.therapy_entitlements where id = v_b.entitlement_id;

  -- Permission: Owner/Manager/Admin anywhere; Staff only for the selling store.
  if v_role = 'staff' then
    if public.my_assigned_store_id() is distinct from v_ent.store_id then
      raise exception 'Only staff from the selling store can activate this entitlement'; end if;
  elsif v_role = 'inventory_manager' then
    raise exception 'Your role cannot activate therapy entitlements';
  end if;

  if v_b.activation_date is not null then raise exception 'This portion is already activated'; end if;
  if v_b.status = 'cancelled' then raise exception 'This portion is cancelled'; end if;
  if p_activation_date is null then raise exception 'Activation date is required'; end if;
  if v_ent.activation_deadline < public.sg_today() then
    raise exception 'The activation deadline (%) has passed', to_char(v_ent.activation_deadline,'DD Mon YYYY'); end if;

  if v_ent.entitlement_kind = 'unlimited' then
    v_end := coalesce(p_ending_override, public.therapy_ending_date(p_activation_date, v_b.portion_months));
    -- Overlap check for this beneficiary (ignore cancelled).
    select count(*) into v_clash
    from public.therapy_entitlement_beneficiaries b2
    join public.therapy_entitlements e2 on e2.id = b2.entitlement_id
    where b2.beneficiary_customer_id = v_b.beneficiary_customer_id
      and b2.id <> v_b.id and b2.status <> 'cancelled'
      and b2.activation_date is not null and e2.entitlement_kind = 'unlimited'
      and daterange(b2.activation_date, b2.ending_date, '[]') && daterange(p_activation_date, v_end, '[]');
    if v_clash > 0 then
      raise exception 'This beneficiary already has an unlimited therapy period overlapping % to %',
        to_char(p_activation_date,'DD Mon YYYY'), to_char(v_end,'DD Mon YYYY'); end if;
  else
    v_end := p_ending_override;   -- vouchers have no expiry (spec 4.7)
  end if;

  update public.therapy_entitlement_beneficiaries
    set activation_date = p_activation_date, ending_date = v_end,
        status = public.therapy_effective_status('active', p_activation_date, v_end, v_ent.activation_deadline),
        activated_by = auth.uid(), activated_at = now(), updated_at = now()
    where id = p_beneficiary_id;

  update public.therapy_entitlements set status = 'activated' where id = v_ent.id and status = 'pending_activation';

  perform public.write_audit_ex('therapy_entitlement_beneficiaries', p_beneficiary_id, 'therapy_activated', null,
    jsonb_build_object('activation_date', p_activation_date, 'ending_date', v_end), 'therapy', null, v_ent.store_id);
  return jsonb_build_object('success', true, 'activation_date', p_activation_date, 'ending_date', v_end);
end $$;

-- ---------------------------------------------------------------------
-- 7. Transfer a beneficiary's portion to another existing customer.
--    Allowed only BEFORE activation. Staff may do it without approval.
-- ---------------------------------------------------------------------
create or replace function public.transfer_therapy_beneficiary(
  p_beneficiary_id uuid, p_new_customer_id uuid, p_reason text default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_b public.therapy_entitlement_beneficiaries%rowtype; v_ent public.therapy_entitlements%rowtype;
begin
  select * into v_b from public.therapy_entitlement_beneficiaries where id = p_beneficiary_id for update;
  if not found then raise exception 'Beneficiary not found'; end if;
  select * into v_ent from public.therapy_entitlements where id = v_b.entitlement_id;
  if not public.user_has_store_access(v_ent.store_id) then raise exception 'No access to that store'; end if;
  if v_b.activation_date is not null then raise exception 'Transfer is blocked after activation'; end if;
  if not exists (select 1 from public.customers where id = p_new_customer_id and deleted_at is null) then
    raise exception 'The new beneficiary must be an existing customer'; end if;

  update public.therapy_entitlement_beneficiaries
    set transferred_from = v_b.beneficiary_customer_id, beneficiary_customer_id = p_new_customer_id,
        transferred_at = now(), updated_at = now()
    where id = p_beneficiary_id;

  perform public.write_audit_ex('therapy_entitlement_beneficiaries', p_beneficiary_id, 'therapy_entitlement_transferred',
    jsonb_build_object('from_customer', v_b.beneficiary_customer_id),
    jsonb_build_object('to_customer', p_new_customer_id), 'therapy', p_reason, v_ent.store_id);
end $$;

-- ---------------------------------------------------------------------
-- 8. Status changes (cancel / suspend / resume).
-- ---------------------------------------------------------------------
create or replace function public.set_therapy_beneficiary_status(
  p_beneficiary_id uuid, p_status text, p_reason text
) returns void language plpgsql security definer set search_path = public as $$
declare v_b public.therapy_entitlement_beneficiaries%rowtype; v_ent public.therapy_entitlements%rowtype; v_new text;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can change therapy status'; end if;
  if p_status not in ('cancelled','suspended','resume') then raise exception 'Invalid status'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason is required'; end if;

  select * into v_b from public.therapy_entitlement_beneficiaries where id = p_beneficiary_id for update;
  if not found then raise exception 'Beneficiary not found'; end if;
  select * into v_ent from public.therapy_entitlements where id = v_b.entitlement_id;

  if p_status = 'resume' then
    v_new := public.therapy_effective_status('active', v_b.activation_date, v_b.ending_date, v_ent.activation_deadline);
  else
    v_new := p_status;
  end if;

  update public.therapy_entitlement_beneficiaries
    set status = v_new, cancelled_reason = case when p_status = 'cancelled' then p_reason else cancelled_reason end,
        updated_at = now()
    where id = p_beneficiary_id;

  perform public.write_audit_ex('therapy_entitlement_beneficiaries', p_beneficiary_id,
    case p_status when 'cancelled' then 'therapy_cancelled' when 'suspended' then 'therapy_suspended' else 'therapy_resumed' end,
    jsonb_build_object('status', v_b.status), jsonb_build_object('status', v_new), 'therapy', p_reason, v_ent.store_id);
end $$;

-- ---------------------------------------------------------------------
-- 9. Date-change request + approval.
--    Owner may approve their own; Manager requests need Owner approval.
-- ---------------------------------------------------------------------
create or replace function public.request_therapy_date_change(
  p_beneficiary_id uuid, p_field text, p_new_value date, p_reason text
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_b public.therapy_entitlement_beneficiaries%rowtype; v_role user_role; v_old date; v_id uuid;
begin
  v_role := public.current_user_role();
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can request a therapy date change'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason is required'; end if;
  if p_field not in ('activation_date','ending_date') then raise exception 'Invalid field'; end if;

  select * into v_b from public.therapy_entitlement_beneficiaries where id = p_beneficiary_id;
  if not found then raise exception 'Beneficiary not found'; end if;
  v_old := case p_field when 'activation_date' then v_b.activation_date else v_b.ending_date end;

  insert into public.therapy_date_change_requests
    (beneficiary_id, field, old_value, new_value, reason, status, requested_by, requested_role)
  values (p_beneficiary_id, p_field, v_old, p_new_value, trim(p_reason), 'pending', auth.uid(), v_role::text)
  returning id into v_id;

  perform public.write_audit_ex('therapy_date_change_requests', v_id, 'therapy_date_change_requested',
    jsonb_build_object('old', v_old), jsonb_build_object('new', p_new_value), 'therapy', p_reason);

  -- Owner may approve their own request immediately.
  if v_role = 'owner' then perform public.approve_therapy_date_change(v_id); end if;
  return v_id;
end $$;

create or replace function public.approve_therapy_date_change(p_request_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_r public.therapy_date_change_requests%rowtype; v_b public.therapy_entitlement_beneficiaries%rowtype;
  v_ent public.therapy_entitlements%rowtype; v_act date; v_end date; v_clash integer; v_role user_role;
begin
  v_role := public.current_user_role();
  select * into v_r from public.therapy_date_change_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if v_r.status <> 'pending' then raise exception 'Request is not pending'; end if;

  -- Manager-raised requests need an Owner. Owner-raised may self-approve.
  if v_r.requested_role = 'manager' and v_role <> 'owner' then
    raise exception 'A Manager''s date-change request must be approved by an Owner'; end if;
  if v_role not in ('owner','manager') then raise exception 'Only Owner or Manager can approve'; end if;

  select * into v_b from public.therapy_entitlement_beneficiaries where id = v_r.beneficiary_id for update;
  select * into v_ent from public.therapy_entitlements where id = v_b.entitlement_id;

  v_act := v_b.activation_date; v_end := v_b.ending_date;
  if v_r.field = 'activation_date' then
    v_act := v_r.new_value;
    -- Ending date recalculates automatically from the new activation date.
    if v_ent.entitlement_kind = 'unlimited' then v_end := public.therapy_ending_date(v_act, v_b.portion_months); end if;
  else
    v_end := v_r.new_value;   -- manual override of the ending date
  end if;

  -- Re-run overlap validation after the change.
  if v_ent.entitlement_kind = 'unlimited' and v_act is not null then
    select count(*) into v_clash
    from public.therapy_entitlement_beneficiaries b2
    join public.therapy_entitlements e2 on e2.id = b2.entitlement_id
    where b2.beneficiary_customer_id = v_b.beneficiary_customer_id
      and b2.id <> v_b.id and b2.status <> 'cancelled'
      and b2.activation_date is not null and e2.entitlement_kind = 'unlimited'
      and daterange(b2.activation_date, b2.ending_date, '[]') && daterange(v_act, v_end, '[]');
    if v_clash > 0 then raise exception 'That change would overlap another therapy period for this beneficiary'; end if;
  end if;

  update public.therapy_entitlement_beneficiaries
    set activation_date = v_act, ending_date = v_end,
        status = public.therapy_effective_status(status, v_act, v_end, v_ent.activation_deadline), updated_at = now()
    where id = v_b.id;

  update public.therapy_date_change_requests
    set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_request_id;

  perform public.write_audit_ex('therapy_date_change_requests', p_request_id, 'therapy_date_change_approved',
    jsonb_build_object('old', v_r.old_value), jsonb_build_object('new', v_r.new_value, 'ending_date', v_end),
    'therapy', v_r.reason, v_ent.store_id);
end $$;

create or replace function public.reject_therapy_date_change(p_request_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can reject'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A rejection reason is required'; end if;
  update public.therapy_date_change_requests
    set status = 'rejected', approved_by = auth.uid(), approved_at = now(), rejection_reason = trim(p_reason)
    where id = p_request_id and status = 'pending';
  perform public.write_audit_ex('therapy_date_change_requests', p_request_id, 'therapy_date_change_rejected',
    null, null, 'therapy', p_reason);
end $$;

notify pgrst, 'reload schema';
