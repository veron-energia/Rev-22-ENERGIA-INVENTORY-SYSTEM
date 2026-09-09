-- =====================================================================
-- ENERGIA — INTERNAL USER INVITATIONS
--
-- Replaces the manual "create an Auth user in the dashboard, then paste SQL"
-- procedure with an invitation an authorized administrator can send from the
-- application. The administrator never sets or sees the new user's password.
--
-- The parts of this that matter:
--
--   * Authority is read from the CALLER'S OWN profile row, server-side, every
--     time. Nothing in a request body, a JWT claim or a browser can nominate a
--     role. is_active is checked too: a disabled administrator is not an
--     administrator.
--   * A pending invitation grants nothing. The profile is created inactive with
--     invitation_status = 'pending', and it stays that way until the recipient
--     completes a real Supabase password set. Two separate conditions guard
--     access rather than one overloaded flag.
--   * Account creation, profile setup, store assignment and email delivery span
--     two systems and are NOT one transaction. The invitation row is the
--     durable record that makes the sequence resumable, and the request id
--     makes a retry idempotent rather than duplicating a person.
--
-- Additive. Creates no users. Run AFTER 00/01/02 and independently of the
-- invoice (170-184) and therapy (220-226) work.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Invitation state, kept apart from Active/Inactive.
--
-- Overloading is_active would mean a single mistaken update could turn an
-- un-accepted invitation into a working account. They are separate columns so
-- that access requires BOTH an accepted invitation and an active profile.
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists invitation_status text
    check (invitation_status is null or invitation_status in ('pending','accepted','cancelled'));

comment on column public.profiles.invitation_status is
  'null = created before invitations existed, or by another path. pending = invited, no access. '
  'accepted = the recipient set their own password. cancelled = withdrawn, never grants access.';

create table if not exists public.user_invitations (
  id uuid primary key default gen_random_uuid(),

  -- Supplied by the caller and unique: a double-clicked form, a retried fetch
  -- and a resumed request all carry the same one, so they cannot create two
  -- people. This is the concurrency control, not a UI nicety.
  request_id text not null unique,

  -- Normalized once, stored beside the address as typed. Every existence check
  -- uses the normalized form so Bob@x.com and bob@x.com are the same person.
  email text not null,
  email_normalized text not null,

  full_name text not null,
  role user_role not null,
  work_phone text,
  personal_phone text,
  personal_email text,
  store_ids uuid[] not null default '{}',

  status text not null default 'pending'
    check (status in ('pending','accepted','cancelled','expired')),

  auth_user_id uuid,                 -- filled in once the Auth account exists
  profile_id uuid references public.profiles(id) on delete set null,

  invited_by uuid references public.profiles(id),
  invited_at timestamptz not null default now(),

  -- Delivery outcome as the provider reported it. A webhook acknowledgement is
  -- not proof the message reached an inbox, and the wording here says so.
  last_email_attempt_at timestamptz,
  last_email_status text check (last_email_status is null
    or last_email_status in ('accepted_by_provider','failed','not_attempted')),
  last_email_detail text,
  resend_count integer not null default 0,
  last_resend_at timestamptz,

  accepted_at timestamptz,
  cancelled_by uuid references public.profiles(id),
  cancelled_at timestamptz,
  cancel_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- One live invitation per address. A second attempt finds the first rather than
-- creating a parallel person with the same login.
create unique index if not exists uq_user_invitation_pending
  on public.user_invitations (email_normalized) where status = 'pending';

create index if not exists idx_user_invitation_status
  on public.user_invitations (status, invited_at desc);

-- ---------------------------------------------------------------------
-- 2. The permission matrix, in one place.
--
-- Owners may create every role. Managers may create Inventory Manager and
-- Staff only. Nobody else may invite at all. Admins are included with Owners
-- for user administration, matching is_owner_or_admin() elsewhere.
-- ---------------------------------------------------------------------
create or replace function public.user_admin_role()
returns user_role language sql stable security definer set search_path = public as $function$
  -- The caller's CURRENT role, from their own row, and only when that role may
  -- administer users at all. Returning any role would make "is not null" mean
  -- "is signed in", which is how a Staff member ends up reading the user list.
  --
  -- A stale client profile or a role in a token is not consulted, and an
  -- account that is inactive or itself still pending is nobody.
  select p.role from public.profiles p
   where p.id = auth.uid() and p.is_active = true and p.deleted_at is null
     and coalesce(p.invitation_status, 'accepted') = 'accepted'
     and p.role in ('owner','admin','manager')
$function$;

create or replace function public.assignable_roles()
returns user_role[] language sql stable security definer set search_path = public as $function$
  select case public.user_admin_role()
    when 'owner'   then array['owner','admin','manager','inventory_manager','staff']::user_role[]
    when 'admin'   then array['owner','admin','manager','inventory_manager','staff']::user_role[]
    when 'manager' then array['inventory_manager','staff']::user_role[]
    else '{}'::user_role[]
  end
$function$;

create or replace function public.can_assign_role(p_role user_role)
returns boolean language sql stable security definer set search_path = public as $function$
  select p_role = any (public.assignable_roles())
$function$;

-- The stores this administrator may hand out. An Owner or Admin may assign any
-- store; anyone else may assign only stores they are themselves assigned to, so
-- inviting somebody can never widen the inviter's own reach.
create or replace function public.assignable_store_ids()
returns uuid[] language sql stable security definer set search_path = public as $function$
  select case
    when public.user_admin_role() in ('owner','admin')
      then coalesce((select array_agg(s.id) from public.stores s), '{}')
    when public.user_admin_role() = 'manager'
      then coalesce((select array_agg(usa.store_id) from public.user_store_assignments usa
                      where usa.user_id = auth.uid()), '{}')
    else '{}'::uuid[]
  end
$function$;

-- ---------------------------------------------------------------------
-- 3. Creating an invitation.
--
-- Everything is checked before any account exists anywhere: permissions,
-- required fields, the role, the stores, and whether the address is already in
-- use. Only then is a row written for the Edge Function to act on.
-- ---------------------------------------------------------------------
create or replace function public.invite_user_begin(
  p_request_id text,
  p_email text,
  p_full_name text,
  p_role user_role,
  p_work_phone text default null,
  p_personal_phone text default null,
  p_personal_email text default null,
  p_store_ids uuid[] default '{}')
returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  v_admin user_role := public.user_admin_role();
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_name  text := btrim(coalesce(p_full_name, ''));
  v_stores uuid[] := coalesce(p_store_ids, '{}');
  v_allowed uuid[] := public.assignable_store_ids();
  v_existing public.user_invitations%rowtype;
  v_id uuid;
  v_bad uuid[];
begin
  if v_admin is null then
    return jsonb_build_object('outcome','forbidden',
      'message','Your account is not permitted to invite users.');
  end if;
  if not public.can_assign_role(p_role) then
    return jsonb_build_object('outcome','forbidden',
      'message', format('Your role may not create %s accounts.', p_role));
  end if;

  if v_name = '' then
    return jsonb_build_object('outcome','invalid','field','full_name','message','A full name is required.');
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    return jsonb_build_object('outcome','invalid','field','email','message','Enter a valid login email address.');
  end if;

  -- The role-dependent contact rules that already govern the edit form, copied
  -- from it rather than invented: UsersPage requires the three contact fields
  -- for staff, owner and manager, and not for admin or inventory_manager. A
  -- server rule that differed from the form would reject invitations the same
  -- page would accept as edits.
  if p_role in ('staff','owner','manager') then
    if coalesce(btrim(p_work_phone), '') = '' then
      return jsonb_build_object('outcome','invalid','field','work_phone','message','Work phone is required for this role.');
    end if;
    if coalesce(btrim(p_personal_phone), '') = '' then
      return jsonb_build_object('outcome','invalid','field','personal_phone','message','Personal phone is required for this role.');
    end if;
    if coalesce(btrim(p_personal_email), '') = '' then
      return jsonb_build_object('outcome','invalid','field','personal_email','message','Personal email is required for this role.');
    end if;
  end if;

  -- Stores must be ones this administrator actually holds.
  select coalesce(array_agg(s), '{}') into v_bad
    from unnest(v_stores) s where not (s = any (v_allowed));
  if coalesce(cardinality(v_bad), 0) > 0 then
    return jsonb_build_object('outcome','forbidden','field','store_ids',
      'message','You can only assign stores you manage.');
  end if;

  -- Same request id, same answer. This is what makes a double click, a retry
  -- and a resumed request harmless.
  select * into v_existing from public.user_invitations where request_id = p_request_id;
  if found then
    return jsonb_build_object('outcome','existing_request', 'invitation_id', v_existing.id,
      'status', v_existing.status, 'email', v_existing.email,
      'auth_user_id', v_existing.auth_user_id,
      'message','This invitation has already been recorded.');
  end if;

  -- Already a live invitation for this address: point at it, do not duplicate.
  select * into v_existing from public.user_invitations
   where email_normalized = v_email and status = 'pending';
  if found then
    return jsonb_build_object('outcome','existing_pending', 'invitation_id', v_existing.id,
      'email', v_existing.email, 'invited_at', v_existing.invited_at,
      'message','An invitation is already pending for this address. Resend or cancel it instead.');
  end if;

  -- Already a real account: say so and change nothing about it. No password is
  -- reset, no role is altered, no metadata is replaced.
  if exists (select 1 from public.profiles p where lower(p.email) = v_email and p.deleted_at is null) then
    return jsonb_build_object('outcome','email_in_use', 'scope','staff',
      'message','That login email already belongs to a user in this system. Nothing has been changed.');
  end if;
  if to_regclass('public.affiliate_accounts') is not null then
    if exists (select 1 from public.affiliate_accounts a where lower(a.email) = v_email) then
      return jsonb_build_object('outcome','email_in_use', 'scope','affiliate',
        'message','That address already belongs to an affiliate account. Adding internal access to an '
                || 'existing affiliate is a separate action and is not done here.');
    end if;
  end if;

  insert into public.user_invitations
    (request_id, email, email_normalized, full_name, role,
     work_phone, personal_phone, personal_email, store_ids, invited_by, last_email_status)
  values (p_request_id, btrim(p_email), v_email, v_name, p_role,
          nullif(btrim(p_work_phone), ''), nullif(btrim(p_personal_phone), ''),
          nullif(btrim(p_personal_email), ''), v_stores, auth.uid(), 'not_attempted')
  returning id into v_id;

  insert into public.audit_logs (table_name, record_id, action, new_data, changed_by)
  values ('user_invitations', v_id, 'user_invitation_created',
          jsonb_build_object('email', v_email, 'role', p_role, 'stores', to_jsonb(v_stores)),
          auth.uid());

  return jsonb_build_object('outcome','created','invitation_id', v_id, 'email', btrim(p_email));
end $function$;

-- ---------------------------------------------------------------------
-- 4. Provisioning, recorded step by step.
--
-- The Edge Function creates the Auth account, then calls this to attach it and
-- write the inaccessible profile. Split from step 3 on purpose: if the email
-- later fails, the record already exists and a resend picks it up instead of
-- creating a second person.
-- ---------------------------------------------------------------------
create or replace function public.invite_user_provisioned(
  p_invitation_id uuid, p_auth_user_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare inv public.user_invitations%rowtype; v_store uuid;
begin
  select * into inv from public.user_invitations where id = p_invitation_id for update;
  if not found then raise exception 'Invitation not found'; end if;
  if inv.status <> 'pending' then
    return jsonb_build_object('outcome', inv.status, 'message','This invitation is no longer pending.');
  end if;

  -- The profile is created INACTIVE and pending. It carries the role and the
  -- stores so activation has nothing left to decide, but it grants nothing:
  -- is_active is false and invitation_status is 'pending'.
  insert into public.profiles (id, full_name, email, role, is_active,
                               work_phone, personal_phone, personal_email, invitation_status)
  values (p_auth_user_id, inv.full_name, inv.email, inv.role, false,
          inv.work_phone, inv.personal_phone, inv.personal_email, 'pending')
  on conflict (id) do update
    set full_name = excluded.full_name, role = excluded.role,
        work_phone = excluded.work_phone, personal_phone = excluded.personal_phone,
        personal_email = excluded.personal_email,
        -- never re-disable or re-pend an account that is already live
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

-- Delivery outcome. Deliberately not called "sent": the provider accepting a
-- webhook is not the same as an inbox receiving a message, and the wording the
-- page shows comes from here.
create or replace function public.invite_user_record_delivery(
  p_invitation_id uuid, p_status text, p_detail text default null, p_is_resend boolean default false)
returns void language plpgsql security definer set search_path = public as $function$
begin
  update public.user_invitations
     set last_email_attempt_at = now(),
         last_email_status = p_status,
         last_email_detail = left(coalesce(p_detail, ''), 500),
         resend_count = resend_count + case when p_is_resend then 1 else 0 end,
         last_resend_at = case when p_is_resend then now() else last_resend_at end,
         updated_at = now()
   where id = p_invitation_id;
end $function$;

-- ---------------------------------------------------------------------
-- 5. Acceptance.
--
-- Called only from the server, and only after Supabase itself has confirmed a
-- password change for this account. The recipient's browser never gets to say
-- that setup succeeded; the caller passes the auth user id it read from the
-- verified session, and this checks it against the invitation.
-- ---------------------------------------------------------------------
create or replace function public.invite_user_accept(
  p_auth_user_id uuid, p_email text)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare inv public.user_invitations%rowtype; v_email text := lower(btrim(coalesce(p_email,'')));
begin
  select * into inv from public.user_invitations
   where auth_user_id = p_auth_user_id for update;

  if not found then
    -- Fall back to the address, for an invitation whose provisioning step did
    -- not complete. Both must agree before anything is activated.
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

  -- The role and stores activated are the ones an authorized administrator
  -- recorded, never anything the recipient supplied.
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

-- ---------------------------------------------------------------------
-- 6. Resend and cancel.
-- ---------------------------------------------------------------------
create or replace function public.invite_user_prepare_resend(p_invitation_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare inv public.user_invitations%rowtype;
begin
  if public.user_admin_role() is null then
    return jsonb_build_object('outcome','forbidden','message','Your account is not permitted to manage invitations.');
  end if;

  select * into inv from public.user_invitations where id = p_invitation_id for update;
  if not found then return jsonb_build_object('outcome','not_found','message','Invitation not found.'); end if;

  if not public.can_assign_role(inv.role) then
    return jsonb_build_object('outcome','forbidden',
      'message', format('Your role may not manage %s invitations.', inv.role));
  end if;
  if inv.status <> 'pending' then
    return jsonb_build_object('outcome','not_pending','status', inv.status,
      'message', case inv.status
        when 'accepted' then 'This person has already set their password. Resending an invitation is not a way to reset a password — ask them to use Forgot Password.'
        when 'cancelled' then 'This invitation was cancelled. Create a new one if they still need access.'
        else 'This invitation is no longer pending.' end);
  end if;

  -- A resend is an email, and an email is rate limited. Two minutes between
  -- attempts, ten in total, so a stuck administrator cannot become a mail sender.
  if inv.last_resend_at is not null and inv.last_resend_at > now() - interval '2 minutes' then
    return jsonb_build_object('outcome','rate_limited',
      'retry_after_seconds', ceil(extract(epoch from (inv.last_resend_at + interval '2 minutes' - now())))::int,
      'message','An invitation was just sent. Wait a couple of minutes before sending another.');
  end if;
  if inv.resend_count >= 10 then
    return jsonb_build_object('outcome','rate_limited',
      'message','This invitation has been resent too many times. Cancel it and start again.');
  end if;

  return jsonb_build_object('outcome','ok','invitation_id', inv.id, 'email', inv.email,
    'full_name', inv.full_name, 'auth_user_id', inv.auth_user_id);
end $function$;

create or replace function public.invite_user_cancel(p_invitation_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare inv public.user_invitations%rowtype;
begin
  if public.user_admin_role() is null then
    return jsonb_build_object('outcome','forbidden','message','Your account is not permitted to manage invitations.');
  end if;

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

  -- The profile is marked cancelled and left inactive. A link issued earlier
  -- may still produce an Auth session — provider tokens cannot be revoked
  -- individually — so access is refused here instead: invite_user_accept()
  -- rejects a cancelled invitation, and the profile grants nothing while
  -- is_active is false and invitation_status is not 'accepted'.
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

-- ---------------------------------------------------------------------
-- 7. The list the Users & Roles page reads.
--
-- One row per internal user, invited or not, with the invitation state beside
-- the account state so "invited three days ago, never accepted" reads
-- differently from "deactivated last year". No link and no token is ever
-- returned by this or any other function here.
-- ---------------------------------------------------------------------
create or replace function public.user_admin_list()
returns table (
  user_id uuid, full_name text, email text, role user_role,
  is_active boolean, invitation_status text,
  state text,                      -- active | inactive | pending_invitation | cancelled_invitation
  work_phone text, personal_phone text, personal_email text,
  store_ids uuid[], store_names text[],
  invitation_id uuid, invited_at timestamptz, invited_by_name text,
  last_email_attempt_at timestamptz, last_email_status text, last_email_detail text,
  resend_count integer, cancelled_at timestamptz, accepted_at timestamptz,
  can_manage boolean)
language sql stable security definer set search_path = public as $function$
  select p.id, p.full_name, p.email, p.role, p.is_active, p.invitation_status,
         case
           when coalesce(p.invitation_status,'accepted') = 'pending'   then 'pending_invitation'
           when coalesce(p.invitation_status,'accepted') = 'cancelled' then 'cancelled_invitation'
           when p.is_active then 'active' else 'inactive' end,
         p.work_phone, p.personal_phone, p.personal_email,
         coalesce((select array_agg(usa.store_id) from public.user_store_assignments usa where usa.user_id = p.id), '{}'),
         coalesce((select array_agg(s.name order by s.name) from public.user_store_assignments usa
                     join public.stores s on s.id = usa.store_id where usa.user_id = p.id), '{}'),
         inv.id, inv.invited_at, ib.full_name,
         inv.last_email_attempt_at, inv.last_email_status, inv.last_email_detail,
         coalesce(inv.resend_count, 0), inv.cancelled_at, inv.accepted_at,
         -- Whether THIS administrator may act on THIS user, so the page can
         -- hide what it must and the server still refuses what it must.
         public.can_assign_role(p.role)
    from public.profiles p
    left join lateral (
      select i.* from public.user_invitations i
       where i.profile_id = p.id or lower(i.email_normalized) = lower(p.email)
       order by i.invited_at desc limit 1) inv on true
    left join public.profiles ib on ib.id = inv.invited_by
   where p.deleted_at is null
     and public.user_admin_role() is not null
   order by p.full_name
$function$;

-- Pending invitations that never became a profile — a creation that failed
-- after the record was written. Shown so they can be resent rather than lost.
create or replace function public.user_admin_orphan_invitations()
returns table (invitation_id uuid, email text, full_name text, role user_role,
               invited_at timestamptz, last_email_status text)
language sql stable security definer set search_path = public as $function$
  select i.id, i.email, i.full_name, i.role, i.invited_at, i.last_email_status
    from public.user_invitations i
   where i.status = 'pending' and i.auth_user_id is null
     and public.user_admin_role() is not null
   order by i.invited_at desc
$function$;

-- ---------------------------------------------------------------------
-- 8. Access.
--
-- The invitations table holds account-conflict information and is readable
-- only by user administrators. There is no public lookup: an unauthenticated
-- caller cannot use this to discover whether an address has an account.
-- ---------------------------------------------------------------------
alter table public.user_invitations enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies
                  where tablename = 'user_invitations' and policyname = 'user admins read invitations') then
    create policy "user admins read invitations" on public.user_invitations
      for select to authenticated
      using (public.user_admin_role() is not null);
  end if;
end $$;

-- No insert, update or delete policy: every write goes through the functions
-- above, which check the caller's role first.

grant select on public.user_invitations to authenticated;
grant execute on function public.user_admin_role() to authenticated;
grant execute on function public.assignable_roles() to authenticated;
grant execute on function public.can_assign_role(user_role) to authenticated;
grant execute on function public.assignable_store_ids() to authenticated;
grant execute on function public.invite_user_begin(text,text,text,user_role,text,text,text,uuid[]) to authenticated;
grant execute on function public.invite_user_prepare_resend(uuid) to authenticated;
grant execute on function public.invite_user_cancel(uuid,text) to authenticated;
grant execute on function public.user_admin_list() to authenticated;
grant execute on function public.user_admin_orphan_invitations() to authenticated;

-- Provisioning and acceptance are server-only: they are called by the Edge
-- Functions with the service role, never from a browser.
revoke all on function public.invite_user_provisioned(uuid,uuid) from public, anon, authenticated;
revoke all on function public.invite_user_record_delivery(uuid,text,text,boolean) from public, anon, authenticated;
revoke all on function public.invite_user_accept(uuid,text) from public, anon, authenticated;
