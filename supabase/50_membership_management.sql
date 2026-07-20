-- =====================================================================
-- ENERGIA — 50: MEMBERSHIP MANAGEMENT (edit member details)
--
-- Adds the ability to edit a customer membership after it exists: assign or
-- correct a missing Member ID, fix store/dates, and cancel/suspend/reactivate.
-- These are administrative corrections (Owner/Manager only), separate from the
-- sale flow (Phase 4). Every change is audited.
--
-- Phase 4 (47-49) is complete and untouched. Additive + idempotent.
-- NOTE: this is Phase 5's first migration slot per the running plan; it holds
-- membership management because the UI gap surfaced here. Membership-based
-- affiliates (the larger Phase 5 body) will follow in 51+.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Assign / correct a membership's Member ID.
--    Writes BOTH the membership row and the permanent member_ids ownership
--    table, enforcing global uniqueness. Owner/Manager only, reason required.
-- ---------------------------------------------------------------------
create or replace function public.set_membership_member_id(
  p_membership_id uuid, p_member_id text, p_reason text
) returns void language plpgsql security definer set search_path = public as $$
declare v_m public.customer_memberships%rowtype; v_id text; v_owner uuid;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can edit a Member ID'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'A reason is required'; end if;
  v_id := nullif(trim(p_member_id), '');
  if v_id is null then raise exception 'Member ID is required'; end if;

  select * into v_m from public.customer_memberships where id = p_membership_id and deleted_at is null;
  if not found then raise exception 'Membership not found'; end if;

  -- Global uniqueness: the ID must not be owned by (or reserved for) another customer.
  select customer_id into v_owner from public.member_ids where member_id = v_id;
  if v_owner is not null and v_owner <> v_m.customer_id then
    raise exception 'Member ID % is already assigned to another customer', v_id; end if;
  if exists (select 1 from public.member_id_reservations r
              where r.member_id = v_id and r.customer_id <> v_m.customer_id) then
    raise exception 'Member ID % is currently reserved for another customer', v_id; end if;

  -- If this customer already owns a DIFFERENT permanent ID, block (one per customer).
  if exists (select 1 from public.member_ids where customer_id = v_m.customer_id and member_id <> v_id) then
    raise exception 'This customer already owns a different Member ID; a customer keeps one permanent ID'; end if;

  -- Permanent ownership (insert or re-point).
  insert into public.member_ids (member_id, customer_id, assigned_by)
  values (v_id, v_m.customer_id, auth.uid())
  on conflict (member_id) do update set customer_id = excluded.customer_id,
    assigned_at = now(), assigned_by = auth.uid();

  -- Stamp every non-deleted membership of this customer that lacks an ID.
  update public.customer_memberships
     set member_id = v_id, updated_by = auth.uid(), updated_at = now()
   where customer_id = v_m.customer_id and deleted_at is null
     and (member_id is null or id = p_membership_id);

  perform public.write_audit_ex('customer_memberships', p_membership_id, 'membership_member_id_set',
    jsonb_build_object('old', v_m.member_id),
    jsonb_build_object('new', v_id, 'membership_no', v_m.membership_no),
    'membership', p_reason, v_m.store_id);
end $$;

-- ---------------------------------------------------------------------
-- 2. Edit membership details: store, start, expiry. Owner/Manager only.
--    Overlap is still guarded by the exclusion constraint from 48b.
-- ---------------------------------------------------------------------
create or replace function public.edit_membership(
  p_membership_id uuid, p_store_id uuid, p_start date, p_expiry date, p_reason text
) returns void language plpgsql security definer set search_path = public as $$
declare v_m public.customer_memberships%rowtype;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can edit a membership'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'A reason is required'; end if;

  select * into v_m from public.customer_memberships where id = p_membership_id and deleted_at is null;
  if not found then raise exception 'Membership not found'; end if;
  if p_start is not null and p_expiry is not null and p_expiry < p_start then
    raise exception 'Expiry cannot be before start'; end if;

  update public.customer_memberships
     set store_id = coalesce(p_store_id, store_id),
         start_date = coalesce(p_start, start_date),
         expiry_date = coalesce(p_expiry, expiry_date),
         updated_by = auth.uid(), updated_at = now()
   where id = p_membership_id;

  perform public.write_audit_ex('customer_memberships', p_membership_id, 'membership_edited',
    jsonb_build_object('store', v_m.store_id, 'start', v_m.start_date, 'expiry', v_m.expiry_date),
    jsonb_build_object('store', coalesce(p_store_id, v_m.store_id), 'start', coalesce(p_start, v_m.start_date), 'expiry', coalesce(p_expiry, v_m.expiry_date)),
    'membership', p_reason, coalesce(p_store_id, v_m.store_id));
end $$;

-- ---------------------------------------------------------------------
-- 3. Cancel / suspend / reactivate. Owner/Manager only, reason required for
--    cancel + suspend. Never touches invoices or payments.
-- ---------------------------------------------------------------------
create or replace function public.set_membership_status(
  p_membership_id uuid, p_status text, p_reason text
) returns void language plpgsql security definer set search_path = public as $$
declare v_m public.customer_memberships%rowtype;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can change a membership status'; end if;
  if p_status not in ('active','suspended','cancelled') then
    raise exception 'Status must be active, suspended or cancelled'; end if;
  if p_status in ('suspended','cancelled') and coalesce(trim(p_reason),'') = '' then
    raise exception 'A reason is required to % a membership', p_status; end if;

  select * into v_m from public.customer_memberships where id = p_membership_id and deleted_at is null;
  if not found then raise exception 'Membership not found'; end if;
  if v_m.status = 'cancelled' then raise exception 'A cancelled membership cannot be changed'; end if;

  update public.customer_memberships
     set status = p_status,
         cancelled_at = case when p_status = 'cancelled' then now() else cancelled_at end,
         cancel_reason = case when p_status = 'cancelled' then trim(p_reason) else cancel_reason end,
         suspended_at = case when p_status = 'suspended' then now()
                             when p_status = 'active' then null else suspended_at end,
         suspend_reason = case when p_status = 'suspended' then trim(p_reason)
                               when p_status = 'active' then null else suspend_reason end,
         updated_by = auth.uid(), updated_at = now()
   where id = p_membership_id;

  perform public.write_audit_ex('customer_memberships', p_membership_id, 'membership_status_changed',
    jsonb_build_object('status', v_m.status),
    jsonb_build_object('status', p_status, 'membership_no', v_m.membership_no),
    'membership', p_reason, v_m.store_id);
end $$;

notify pgrst, 'reload schema';
