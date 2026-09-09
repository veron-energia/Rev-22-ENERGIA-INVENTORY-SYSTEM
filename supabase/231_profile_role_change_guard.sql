-- =====================================================================
-- ENERGIA — A ROLE CANNOT BE RAISED THROUGH THE EDIT FORM
--
-- The invitation workflow enforces who may create which role. That is worth
-- nothing on its own, because the existing Users & Roles edit form writes the
-- role with a direct table update:
--
--     supabase.from('profiles').update({ role, is_active, ... })
--
-- so the only thing standing between a Manager and an Owner account is row-level
-- security. Both policy sets in this repository leave a way through:
--
--   02_rls_policies.sql   "owner manager manage profiles" — for all, using
--                         is_owner_or_manager(). A Manager may update ANY
--                         profile, including setting role = 'owner', and
--                         including their own.
--   00_complete_setup.sql "update profiles" — using (id = auth.uid() or
--                         is_owner_or_admin()). The first branch lets ANY
--                         signed-in user update their own row, role included.
--
-- Either way, "Managers must not grant Owner, Admin, or Manager privileges" is
-- not true today. A Manager can invite a Staff member and then promote them —
-- or themselves — from the same screen.
--
-- This is fixed with a trigger rather than another policy, because a trigger
-- runs on every path into the table: the edit form, a direct PostgREST call,
-- a future function, an ad-hoc SQL editor session under a user's JWT. Which
-- policy happens to be installed stops mattering.
--
-- Only role and is_active are guarded. Editing a name, a phone or an email is
-- untouched, so nothing that works today stops working.
--
-- Additive. Run AFTER 230.
-- =====================================================================

set check_function_bodies = off;

-- Our own SECURITY DEFINER functions need to set role and is_active — that is
-- their whole job. They announce it for the duration of their transaction, and
-- the trigger honours only that flag, which no client can set through PostgREST.
create or replace function public.profile_privilege_change_allowed()
returns boolean language sql stable as $function$
  select coalesce(current_setting('energia.profile_privilege_change', true), '') = 'on'
$function$;

create or replace function public.trg_guard_profile_privileges()
returns trigger language plpgsql security definer set search_path = public as $function$
declare
  v_actor uuid := auth.uid();
  v_actor_role user_role;
  v_role_changed boolean := new.role is distinct from old.role;
  v_active_changed boolean := new.is_active is distinct from old.is_active;
begin
  if not v_role_changed and not v_active_changed then
    return new;                                  -- ordinary profile edit
  end if;

  -- A server-side function that has declared its intent, or a service-role
  -- connection with no end user at all (migrations, the Edge Functions).
  if public.profile_privilege_change_allowed() then return new; end if;
  if v_actor is null then return new; end if;

  select p.role into v_actor_role from public.profiles p
   where p.id = v_actor and p.is_active = true and p.deleted_at is null;

  if v_actor_role is null then
    raise exception 'Your account is not permitted to change roles or activation.'
      using errcode = '42501';
  end if;

  -- Nobody edits their own privileges, whatever their role. An Owner who needs
  -- to step down asks another Owner; that is a smaller inconvenience than a
  -- self-service route to Owner existing at all.
  if new.id = v_actor and v_role_changed then
    raise exception 'You cannot change your own role.' using errcode = '42501';
  end if;
  if new.id = v_actor and v_active_changed then
    raise exception 'You cannot change your own activation.' using errcode = '42501';
  end if;

  if v_actor_role in ('owner','admin') then
    return new;                                  -- may set any role
  end if;

  if v_actor_role = 'manager' then
    -- A Manager may only ever touch Inventory Managers and Staff, and may only
    -- move somebody between those two. Both the old and the new role are
    -- checked: without the first test a Manager could demote an Owner.
    if v_role_changed and (old.role not in ('inventory_manager','staff')
                           or new.role not in ('inventory_manager','staff')) then
      raise exception 'A Manager may only assign the Inventory Manager or Staff role.'
        using errcode = '42501';
    end if;
    if v_active_changed and old.role not in ('inventory_manager','staff') then
      raise exception 'A Manager may only activate or deactivate Inventory Managers and Staff.'
        using errcode = '42501';
    end if;
    return new;
  end if;

  raise exception 'Your role may not change roles or activation.' using errcode = '42501';
end $function$;

drop trigger if exists guard_profile_privileges on public.profiles;
create trigger guard_profile_privileges
  before update on public.profiles
  for each row execute function public.trg_guard_profile_privileges();

-- ---------------------------------------------------------------------
-- The invitation functions change privileges legitimately, so they declare it.
-- set_config(..., true) is transaction-local: it is gone by the next statement
-- outside this transaction, and PostgREST offers no way for a client to set it.
-- ---------------------------------------------------------------------
create or replace function public.invite_user_provisioned(
  p_invitation_id uuid, p_auth_user_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare inv public.user_invitations%rowtype; v_store uuid;
begin
  perform set_config('energia.profile_privilege_change', 'on', true);

  select * into inv from public.user_invitations where id = p_invitation_id for update;
  if not found then raise exception 'Invitation not found'; end if;
  if inv.status <> 'pending' then
    return jsonb_build_object('outcome', inv.status, 'message','This invitation is no longer pending.');
  end if;

  insert into public.profiles (id, full_name, email, role, is_active,
                               work_phone, personal_phone, personal_email, invitation_status)
  values (p_auth_user_id, inv.full_name, inv.email, inv.role, false,
          inv.work_phone, inv.personal_phone, inv.personal_email, 'pending')
  on conflict (id) do update
    set full_name = excluded.full_name, role = excluded.role,
        work_phone = excluded.work_phone, personal_phone = excluded.personal_phone,
        personal_email = excluded.personal_email,
        is_active = public.profiles.is_active,
        invitation_status = coalesce(public.profiles.invitation_status, 'pending');

  foreach v_store in array coalesce(inv.store_ids, '{}') loop
    insert into public.user_store_assignments (user_id, store_id)
    values (p_auth_user_id, v_store) on conflict (user_id, store_id) do nothing;
  end loop;

  update public.user_invitations
     set auth_user_id = p_auth_user_id, profile_id = p_auth_user_id, updated_at = now()
   where id = p_invitation_id;

  return jsonb_build_object('outcome','provisioned','invitation_id', p_invitation_id);
end $function$;

create or replace function public.invite_user_accept(p_auth_user_id uuid, p_email text)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare inv public.user_invitations%rowtype; v_email text := lower(btrim(coalesce(p_email,'')));
begin
  perform set_config('energia.profile_privilege_change', 'on', true);

  select * into inv from public.user_invitations where auth_user_id = p_auth_user_id for update;
  if not found then
    select * into inv from public.user_invitations
     where email_normalized = v_email and status = 'pending' for update;
  end if;

  if not found then
    return jsonb_build_object('activated', false, 'reason','not_invited',
      'message','There is no invitation for this account.');
  end if;
  if inv.email_normalized is distinct from v_email then
    return jsonb_build_object('activated', false, 'reason','wrong_account',
      'message','This invitation was sent to a different address.');
  end if;
  if inv.status = 'cancelled' then
    return jsonb_build_object('activated', false, 'reason','cancelled',
      'message','This invitation was cancelled and can no longer be used.');
  end if;
  if inv.status = 'accepted' then
    return jsonb_build_object('activated', false, 'reason','already_accepted',
      'message','This invitation has already been used. Sign in with your password.');
  end if;
  if inv.status <> 'pending' then
    return jsonb_build_object('activated', false, 'reason', inv.status,
      'message','This invitation is no longer valid.');
  end if;

  update public.profiles
     set is_active = true, invitation_status = 'accepted', updated_at = now()
   where id = p_auth_user_id;

  update public.user_invitations
     set status = 'accepted', accepted_at = now(), updated_at = now()
   where id = inv.id;

  insert into public.audit_logs (table_name, record_id, action, new_data, changed_by)
  values ('user_invitations', inv.id, 'user_invitation_accepted',
          jsonb_build_object('email', inv.email_normalized, 'role', inv.role), p_auth_user_id);

  return jsonb_build_object('activated', true, 'role', inv.role,
    'stores', (select count(*) from public.user_store_assignments where user_id = p_auth_user_id));
end $function$;

create or replace function public.invite_user_cancel(p_invitation_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare inv public.user_invitations%rowtype;
begin
  if public.user_admin_role() is null then
    return jsonb_build_object('outcome','forbidden','message','Your account is not permitted to manage invitations.');
  end if;
  perform set_config('energia.profile_privilege_change', 'on', true);

  select * into inv from public.user_invitations where id = p_invitation_id for update;
  if not found then return jsonb_build_object('outcome','not_found','message','Invitation not found.'); end if;
  if not public.can_assign_role(inv.role) then
    return jsonb_build_object('outcome','forbidden',
      'message', format('Your role may not manage %s invitations.', inv.role));
  end if;
  if inv.status = 'accepted' then
    return jsonb_build_object('outcome','already_accepted',
      'message','This person has already accepted. Deactivate the account instead of cancelling the invitation.');
  end if;
  if inv.status = 'cancelled' then
    return jsonb_build_object('outcome','already_cancelled','message','This invitation is already cancelled.');
  end if;

  update public.user_invitations
     set status = 'cancelled', cancelled_by = auth.uid(), cancelled_at = now(),
         cancel_reason = nullif(btrim(p_reason), ''), updated_at = now()
   where id = p_invitation_id;

  if inv.auth_user_id is not null then
    update public.profiles
       set is_active = false, invitation_status = 'cancelled', updated_at = now()
     where id = inv.auth_user_id and coalesce(invitation_status,'') <> 'accepted';
  end if;

  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by)
  values ('user_invitations', inv.id, 'user_invitation_cancelled',
          jsonb_build_object('status', inv.status),
          jsonb_build_object('status','cancelled','reason', nullif(btrim(p_reason),'')), auth.uid());

  return jsonb_build_object('outcome','cancelled','invitation_id', inv.id);
end $function$;

revoke all on function public.invite_user_provisioned(uuid,uuid) from public, anon, authenticated;
revoke all on function public.invite_user_accept(uuid,text) from public, anon, authenticated;
grant execute on function public.invite_user_cancel(uuid,text) to authenticated;
