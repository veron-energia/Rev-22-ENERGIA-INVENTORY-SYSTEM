-- 429_users_invitations_and_payment_methods.sql
--
-- WHAT WAS WRONG (audit of 9 Oct 2026, section 11: ADMIN-AUTH-7, -10, -11,
-- -15, -17)
--
--   1. Invitations could reach dead ends (ADMIN-AUTH-7).
--      a. An invitation whose login or profile was never made (the link could
--         not be generated, or the set-up failed) was invisible: Users & Roles
--         lists people from their profiles, and user_admin_orphan_invitations()
--         was not callable by a page. Inviting the address again was answered
--         "Resend or cancel it instead", with nothing to click.
--      b. A cancelled person could never be invited again. invite_user_cancel
--         switched the profile off and marked it cancelled but left it in
--         place, so invite_user_begin refused the address as "already belongs
--         to a user", and 412 had blocked the login. The resend refusal said
--         "Create a new one", which was impossible.
--      c. Had an orphan invitation been resent, its login would have been made
--         without a profile, and invite_user_accept, matching by address,
--         would have marked the invitation accepted with no profile behind it.
--      d. Accepting picked one of a login's invitations at random; a login
--         invited again after a cancelled invitation has two.
--      e. A member of staff who was removed could not be invited again.
--         Their address was accepted and saved, but their login was never
--         offered for reuse, invite_user_provisioned would not take it, and
--         Supabase Auth refuses a new 'invite' link for it. The invitation
--         then sat unfinished, and Resend failed every time (none on
--         production, 10 Oct 2026).
--   2. The Admin role (ADMIN-AUTH-15). Nobody has it, and the Owner decided
--      on 9 Oct 2026 (Q13, answer A) that it is no longer given to new staff.
--      assignable_roles() still offered it, and an Owner could still give it.
--   3. Payment methods (ADMIN-AUTH-10, -11). A system wallet method (the five
--      Wallet credit types) could be renamed or switched off; once one was
--      off, customers holding that kind of credit could not spend it at the
--      till. The name was unique among deleted methods too, so a deleted
--      method's name could never be used again (9 such names on production,
--      9 Oct 2026). The page could not tell which methods the website order
--      channels use (that table is closed to pages), so it could not warn
--      before one was switched off.
--
-- THE RULES
--
--   * The Owner, 9 Oct 2026, Q13 (A): Admin is no longer offered for new
--     staff. Managers keep inviting and managing Inventory Managers and Staff
--     only; Owners manage everyone.
--   * 412 (the Owner, 9 Oct 2026): a cancelled invitee's login is signed out
--     and blocked; a pending invitee is not blocked (rule 5).
--   * The Owner, 10 Oct 2026: the five Wallet credit types (Paid,
--     Promotional/FOC, Bonus, Legacy, Exchange) can never be switched off.
--     The Payment Methods page does not offer it and the database refuses it.
--   * The Owner, 10 Oct 2026: a member of staff who was removed may be
--     invited again with their old email. The invitation reuses their login,
--     so their history stays linked to it. When the new invitation is set up
--     their profile is pending again and 412 lifts the block it placed (a
--     pending invitee is not blocked, rule 5), so the link works; on
--     accepting, the profile is active again. It is still their profile, so
--     whoever invites them must be allowed to manage the role they had, as on
--     Users & Roles (a Manager: Inventory Managers and Staff). That stays
--     true after an Owner's invitation of theirs is cancelled: the profile
--     keeps its role.
--   * The Owner, 10 Oct 2026: after opening an emailed link (reset, sign-in
--     link, invitation) a new password can be set without the current one for
--     30 minutes; after that the current password is needed and the page
--     offers a new link. That is the Edge Functions' rule, not this file's:
--     auth-change-password, and since 18 Oct 2026 auth-accept-invitation,
--     enforce the 30 minutes. Someone at a signed-in device who uses the
--     browser's developer tools can still set a password through Supabase
--     Auth directly from a session opened by an email link. No Supabase
--     setting enforces 30 minutes. Supabase's
--     "Require current password when updating" closes that route for
--     password sign-ins only (whether production has it on was not checked);
--     "Secure password change" must stay off, as it refuses a session over
--     24 hours old even with the current password. USER_INVITATIONS.md says
--     the rest. Accepting an invitation cannot be done that way:
--     invite_user_accept is the service role's alone.
--
-- WHAT THIS DOES
--
--   * invite_user_cancel: a never-accepted invitee's profile is also removed
--     (a deleted date). Users & Roles stops listing it, invite_user_begin no
--     longer sees the address as in use, and the login stays blocked (412).
--     Only a profile that is an invitee's (pending or cancelled) is touched.
--   * invite_user_provisioned: a login that is already someone's (a live
--     staff profile that is not an invitee's, or an affiliate account) is
--     never made an invitee; it answers "login_in_use" and ties nothing. A
--     cancelled invitee's login, or a removed member of staff's, is used
--     again: their profile is put back as the new invitation's, pending, with
--     that invitation's stores only, and an audit row keeps what it was
--     before (name, role, state, removed date, stores). A login made for an
--     invitation cancelled during set-up (413) gets a removed profile, as a
--     cancel now gives.
--   * staff_login_sync: a pending invitee whose login this blocked when an
--     earlier invitation was cancelled, or when they were removed, has the
--     block lifted, so the new invitation link works (412 rule 5: pending
--     invitees are not blocked).
--     A cancelled invitation's block is still recorded as
--     "invitation_cancelled", although the profile is now removed too.
--   * invite_user_accept: the pending invitation of the login is the one
--     accepted; an invitation never tied to the login, or a profile that is
--     not the pending one it made, is refused as "not finished".
--   * invite_user_prepare_resend: the cancelled and too-many-resends answers
--     say what to do now that re-inviting works.
--   * invite_user_reusable_login(uuid) (new; internal, the service role's
--     alone): the login a pending invitation may use again, so
--     admin-invite-user can invite a cancelled person or a removed member of
--     staff again and finish an orphan invitation's set-up.
--   * user_admin_orphan_invitations(): starts with require_active_staff
--     (Owners, Admins, Managers), lists only invitations the caller may
--     manage, and is granted to signed-in staff so Users & Roles lists them.
--   * invite_user_begin: a member of staff who was removed may be invited
--     again (their login is then reused), but only by someone allowed to
--     manage the role their profile has; anyone else is refused
--     ("forbidden", scope "removed_staff") and nothing is saved. This holds
--     whatever the removed profile's invitation state, so a cancelled
--     re-invitation does not open the way: a Manager may not invite back a
--     removed Manager after an Owner's invitation of them is cancelled, nor
--     a cancelled invitee an Owner had invited as a Manager.
--   * Admin (Q13): assignable_roles() no longer lists it; invite_user_begin
--     refuses it; the profile rule refuses giving it. can_assign_role() keeps
--     what it meant (who may manage someone with that role) but no longer
--     reads assignable_roles(), so an existing Admin can still be managed.
--   * trg_protect_system_payment_methods: a system wallet method cannot be
--     renamed or switched off either (it already could not be deleted or
--     reconfigured). Switching one back on stays possible.
--   * payment_methods: the name is unique among live methods only, ignoring
--     case and outer spaces (payment_methods_live_name_key replaces
--     payment_methods_name_key), so a deleted method's name can be added or
--     the old method restored.
--   * payment_method_web_uses() (new; Owners and Managers, the Payment
--     Methods page): which methods the website order channels use, read as
--     web_order_payment_method() reads them.
--
-- NOT CHANGED
--
--   * Who may invite or manage whom (beyond Admin no longer being given), the
--     contact and store rules of invite_user_begin, the request id and pending
--     checks, the rate limits, invite_user_record_delivery.
--   * user_admin_role(), user_admin_list() and assignable_store_ids(); the
--     store-assignment rule is B06's (assign_user_store, 420).
--   * A system method still cannot be deleted or reconfigured (as before).
--     Ordinary payment methods can still be switched off and deleted.
--   * 412's closing paths (deactivated, removed, cancelled): unchanged. Only a
--     pending invitee's block is lifted, and only a block 412 placed. A
--     member of staff who is deactivated but not removed is switched on again
--     on Users & Roles, not invited (their address stays "in use").
--   * The table rules and grants on payment_methods and profiles (the anon
--     and authenticated table grants the audit noted; row level security
--     refuses them): left to the policy sweep (B17, 430).
--   * No row is changed: on 10 Oct 2026 production had no invitation, no
--     invitee profile, no removed profile, no Admin, no two live payment
--     methods with the same name ignoring case and spaces, and all five
--     system wallet methods on.
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. It
--   refuses unless 406, 412 and 413 are in (require_active_staff,
--   staff_login_sync, its trigger and the two functions 413 changed at their
--   AFTER md5s); every function it changes is the version read on 9 Oct 2026
--   (or already this one), with no overload, and the two new names are
--   missing or already this version; the tables and columns read have the
--   shape read that day; payment_methods has the one name constraint read that
--   day (or already the new index), no two live names that clash, and every
--   system wallet method on and not deleted; and the role running this may
--   read auth.users. Each anchor occurs exactly once and every text built has
--   its AFTER md5 before anything is installed. CREATE OR REPLACE keeps the
--   grants; the grants are then set for the two new functions and the orphan
--   list, and all are checked. Then, inside a block that is always undone, as
--   made-up logins (@sig.invalid): an Owner invites, cancels and invites again
--   the same address, which reuses the login, lifts its block and is
--   accepted; a removed member of staff is invited again, which reuses their
--   login, keeps what their profile was in the audit log, lifts their block
--   and is accepted; Admin is refused; the orphan list answers an Owner; a
--   system wallet method cannot be renamed or switched off; a deleted
--   method's name is added again. Nothing is printed and no row remains.
--
-- BEFORE (production, 9 Oct 2026, re-read 10 Oct 2026; md5 of
-- pg_get_functiondef, search_path public):
--   invite_user_begin(text,text,text,user_role,text,text,text,uuid[])
--                                           8d2e1f3540a00dad9c1be25bd413e3c4  (413's AFTER)
--   invite_user_provisioned(uuid,uuid)      506816a8545148a24e9814d0bf2d5062  (413's AFTER)
--   invite_user_cancel(uuid,text)           03693443bf396a94cff6f99850ff0bc4
--   invite_user_prepare_resend(uuid)        78d04c138c7f3ebc62b4cb53623e1485
--   invite_user_accept(uuid,text)           f5ba4fd5053eb308c5e3e59ff99a3dfe
--   staff_login_sync(uuid)                  7648388b0b41caee3696694ae172377e  (412's AFTER)
--   user_admin_orphan_invitations()         b39a4cfa6b3d2684b2fe2b5b01216711
--   assignable_roles()                      90bd806d630ef44845edd94d83b3d851
--   can_assign_role(user_role)              c7c9b29b1be64baa32aa2005f7d7cb12
--   trg_guard_profile_privileges()          903ce9d75b2d0314428fb298a185d781  (407's AFTER)
--   trg_protect_system_payment_methods()    9d8bc45f96b46bae93453d87d62a5c18
--   relied on, not changed
--   require_active_staff(text[])            877b3aa74cea559881979bb161c450e2  (406's AFTER)
--   trg_staff_login_follows_profile()       a3a60fef98d7755b7104a5d96c4e38f8  (412's AFTER)
--   user_admin_role()                       6fe6c3202163ce80babdcf04fc28f76b
--   user_admin_list()                       4d770ec592c3e96644602f196b4f7ce2
--   new: invite_user_reusable_login(uuid), payment_method_web_uses() (missing)
--   public function fingerprint             675ac22c631079b58f06813d0d463fa3 (a copy of production
--                                           after 413; production also has 414, 415, 421 and 428,
--                                           which touch none of these functions: every md5 above
--                                           re-read on production 10 Oct 2026 after 415, and all
--                                           match; production's fingerprint then was
--                                           566e76f702c89c9846968e6fdd89cc45)
-- AFTER (for later guards):
--   invite_user_begin(...)                  eda7f730fd83891146265adb06eca132
--   invite_user_provisioned(uuid,uuid)      7219cae03a5a758402e79762baf46f42
--   invite_user_cancel(uuid,text)           e9e97c330ed7189415e2f67cef9716c5
--   invite_user_prepare_resend(uuid)        0ef0ebb3836bcdac6d6ee4a76e213753
--   invite_user_accept(uuid,text)           04eb29a50699f8f9f41d7ba591af3480
--   staff_login_sync(uuid)                  9259111deccca8c66e95469acfdd250f
--   user_admin_orphan_invitations()         8856ea1bba6dbbf1f250e279686b1eef
--   assignable_roles()                      792bd103eaf31a84c43d1dd2ca5d5574
--   can_assign_role(user_role)              1d7194e92d758bc01928f9115ec9f3af
--   trg_guard_profile_privileges()          b4e69e15ec0edaebde1448f1f15d89dd
--   trg_protect_system_payment_methods()    9c1af002437091b7ef61b04221b254eb
--   invite_user_reusable_login(uuid)        340580cff28c74eb1b1b8bde967dc8fc
--   payment_method_web_uses()               766591ae7f9ddb163715e21deb812a0a
--   public function fingerprint             d8c14d25a33000b3430a490ad597122e (the same copy after 429)
--                                           79b59fa189681fc01ed94b830f584e2f (that copy with 414, 415,
--                                           421 and 428 applied first, which matches production's
--                                           566e76f7 of 10 Oct 2026, then 429)
--   index payment_methods_live_name_key     UNIQUE (lower(btrim(name))) WHERE deleted_at IS NULL
--
-- DEPLOY ORDER: this, then the Edge Functions auth-accept-invitation (carries
-- supabase/functions/_shared/auth-email/accept.ts, password.ts and
-- validate.ts), admin-invite-user (carries invitations.ts, password.ts and
-- validate.ts) and auth-change-password (carries change.ts, password.ts and
-- validate.ts), then the front end. Deploy each function by its name; never a
-- bare "supabase functions deploy", which would also deploy folders that are
-- not part of this. auth-accept-invitation now accepts only a session opened
-- from an emailed link (an invitation or recovery link) in the last 30
-- minutes, the window of auth-change-password (the Owner, 18 Oct 2026: "30
-- minutes, like reset links"); a link opened longer ago is told to ask for a
-- new invitation, and Resend on Users & Roles sends one. A removed member of
-- staff invited again still has their old password, and the block on their
-- login is lifted when
-- the invitation is set up, so without this check that password alone could
-- switch them back on without the email. A new invitee has no password, so
-- their session always comes from the link. Deploy it no later than
-- admin-invite-user. auth-change-password asks for the current password
-- unless the session came from an email link in the last 30 minutes, and
-- tells a link opened longer ago to give it or request a new link. The
-- current password, when given, also goes to Supabase Auth with the change,
-- so it keeps working once "Require current password when updating" is on.
-- The live admin-invite-user against this: unchanged, except that a
-- re-invited address whose old login is unconfirmed now succeeds, a removed
-- member of staff's invitation is still saved but not sent (it does not ask
-- for a login to reuse, as before this), a Manager re-inviting a removed
-- Manager or Owner (or a cancelled invitee whose profile has such a role) is
-- refused (it passes the answer on), and an orphan's resend still makes a
-- login with no profile (refused at acceptance as "not finished" instead of
-- accepted with no profile). The live Accept page against the new
-- admin-invite-user: a removed member of staff invited again gets a recovery
-- link, whose login has no invited_to mark, and the live page shows them "You
-- are signed in as ..." with no form. The new Accept page first asks
-- auth-accept-invitation { check: true }. The live function answers that 400,
-- so the page would say it could not check. Deploy the function before the
-- front end. The page shows the form only to a login with a pending
-- invitation, so ship the front end soon after admin-invite-user. The new
-- admin-invite-user against a database without this: it asks
-- invite_user_reusable_login, which does not exist, so a new invitation is
-- saved but not sent ("could not be set up") and a resend fails; this goes
-- first. The new pages against a database without this: the orphan list and
-- the website check say they could not be loaded; nothing else changes.
--
-- Test: scripts/permissions/tests/invitations-start-again.sql (new: every
-- path above), scripts/permissions/tests/invitation-cancelled-during-setup.sql,
-- scripts/permissions/tests/deactivated-login-blocked.sql,
-- scripts/payment-methods/tests/payment-methods.sql (new),
-- scripts/permissions/tests/function-grants.sql,
-- scripts/permissions/tests/staff-only-functions.sql,
-- scripts/permissions/tests/reinvite-gotrue.mjs (new: the same against a real
-- Supabase Auth), supabase/functions/_shared/auth-email/tests/
-- invitations.test.ts, password.test.ts, accept.test.ts and change.test.ts
-- (npm run test:auth-email:edge),
-- the pages: scripts/ui/tests/users-page, payment-methods-page,
-- password-pages, accept-invitation-page and app-shell .test.mjs (npm run
-- test:password-ui), and scripts/web-orders/tests/door-orders.sql (its
-- fixture no longer needs two live methods with one name, which this
-- refuses. On a copy of production it stops at 380's own md5 guard, with or
-- without this, so its fixture was checked on its own).

set lock_timeout = '5s';

do $mig$
declare
  -- ── invite_user_cancel ─────────────────────────────────────────────────────
  c_cancel_sig    constant text := 'invite_user_cancel(uuid,text)';
  c_cancel_before constant text := '03693443bf396a94cff6f99850ff0bc4';
  c_cancel_after  constant text := 'e9e97c330ed7189415e2f67cef9716c5';
  c_cancel_anchor constant text := $a$  if inv.auth_user_id is not null then
    update public.profiles
       set is_active = false, invitation_status = 'cancelled', updated_at = now()
     where id = inv.auth_user_id and coalesce(invitation_status,'') <> 'accepted';
  end if;
$a$;
  c_cancel_repl   constant text := $r$  if inv.auth_user_id is not null then
    -- 429: the profile of someone who never accepted is also removed (a
    -- deleted date), so Users & Roles no longer lists them and the address
    -- can be invited again. Their login stays, blocked (412); a new
    -- invitation uses it again. A profile that is not an invitee's is left
    -- alone.
    update public.profiles
       set is_active = false, invitation_status = 'cancelled',
           deleted_at = coalesce(deleted_at, now()), updated_at = now()
     where id = inv.auth_user_id and invitation_status in ('pending', 'cancelled');
  end if;
$r$;

  -- ── invite_user_prepare_resend ─────────────────────────────────────────────
  c_resend_sig     constant text := 'invite_user_prepare_resend(uuid)';
  c_resend_before  constant text := '78d04c138c7f3ebc62b4cb53623e1485';
  c_resend_after   constant text := '0ef0ebb3836bcdac6d6ee4a76e213753';
  c_resend_anchor1 constant text := $a$        when 'cancelled' then 'This invitation was cancelled. Create a new one if they still need access.'
$a$;
  c_resend_repl1   constant text := $r$        when 'cancelled' then 'This invitation was cancelled. Use Invite User to invite them again if they still need access.'
$r$;
  c_resend_anchor2 constant text := $a$      'message','This invitation has been resent too many times. Cancel it and start again.');
$a$;
  c_resend_repl2   constant text := $r$      'message','This invitation has been resent too many times. Cancel it, then use Invite User to invite them again.');
$r$;

  -- ── invite_user_provisioned ────────────────────────────────────────────────
  c_prov_sig     constant text := 'invite_user_provisioned(uuid,uuid)';
  c_prov_before  constant text := '506816a8545148a24e9814d0bf2d5062';
  c_prov_after   constant text := '7219cae03a5a758402e79762baf46f42';
  c_prov_anchor1 constant text := $a$        insert into public.profiles (id, full_name, email, role, is_active,
                                     work_phone, personal_phone, personal_email, invitation_status)
        values (p_auth_user_id, inv.full_name, inv.email, inv.role, false,
                inv.work_phone, inv.personal_phone, inv.personal_email, 'cancelled')
        on conflict do nothing;
$a$;
  c_prov_repl1   constant text := $r$        -- 429: removed too (a deleted date), as invite_user_cancel now does,
        -- so the address can be invited again.
        insert into public.profiles (id, full_name, email, role, is_active,
                                     work_phone, personal_phone, personal_email, invitation_status, deleted_at)
        values (p_auth_user_id, inv.full_name, inv.email, inv.role, false,
                inv.work_phone, inv.personal_phone, inv.personal_email, 'cancelled', now())
        on conflict do nothing;
$r$;
  c_prov_anchor2 constant text := $a$  insert into public.profiles (id, full_name, email, role, is_active,
                               work_phone, personal_phone, personal_email, invitation_status)
  values (p_auth_user_id, inv.full_name, inv.email, inv.role, false,
          inv.work_phone, inv.personal_phone, inv.personal_email, 'pending')
  on conflict (id) do update
    set full_name = excluded.full_name, role = excluded.role,
        work_phone = excluded.work_phone, personal_phone = excluded.personal_phone,
        personal_email = excluded.personal_email,
        is_active = public.profiles.is_active,
        invitation_status = coalesce(public.profiles.invitation_status, 'pending');

$a$;
  c_prov_repl2   constant text := $r$  -- 429: a login that is already someone's (a live member of staff's
  -- profile, or an affiliate account) is never made an invitee. Nothing is
  -- tied and no email is sent.
  if exists (select 1 from public.affiliate_accounts a where a.auth_user_id = p_auth_user_id)
     or exists (select 1 from public.profiles p where p.id = p_auth_user_id and p.deleted_at is null
                 and coalesce(p.invitation_status, 'accepted') not in ('pending', 'cancelled')) then
    return jsonb_build_object('outcome','login_in_use',
      'message','That login already belongs to someone in this system. No email was sent.');
  end if;

  -- 429: the login of someone invited before who never accepted (their
  -- invitation was cancelled), or of a member of staff who was removed (the
  -- Owner, 10 Oct 2026), is used again, so their history stays linked to it.
  -- What their profile was is kept in the audit log first. Then it is put
  -- back as this invitation's: pending, switched off, not removed, with this
  -- invitation's stores only. 412 then lifts the block it placed when they
  -- were cancelled or removed, so the new link works.
  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by)
  select 'profiles', p.id, 'user_invitation_login_reused',
         jsonb_build_object('full_name', p.full_name, 'role', p.role, 'is_active', p.is_active,
                            'invitation_status', p.invitation_status, 'deleted_at', p.deleted_at,
                            'store_ids', (select coalesce(jsonb_agg(s.store_id order by s.store_id), '[]')
                                            from public.user_store_assignments s where s.user_id = p.id)),
         jsonb_build_object('invitation_id', inv.id, 'role', inv.role, 'invitation_status', 'pending',
                            'store_ids', to_jsonb(coalesce(inv.store_ids, '{}'))),
         inv.invited_by
    from public.profiles p
   where p.id = p_auth_user_id and (p.deleted_at is not null or p.invitation_status = 'cancelled');

  insert into public.profiles (id, full_name, email, role, is_active,
                               work_phone, personal_phone, personal_email, invitation_status)
  values (p_auth_user_id, inv.full_name, inv.email, inv.role, false,
          inv.work_phone, inv.personal_phone, inv.personal_email, 'pending')
  on conflict (id) do update
    set full_name = excluded.full_name, role = excluded.role,
        work_phone = excluded.work_phone, personal_phone = excluded.personal_phone,
        personal_email = excluded.personal_email,
        is_active = false, invitation_status = 'pending', deleted_at = null,
        updated_at = now();

  delete from public.user_store_assignments s
   where s.user_id = p_auth_user_id and not (s.store_id = any (coalesce(inv.store_ids, '{}')));

$r$;

  -- ── invite_user_accept ─────────────────────────────────────────────────────
  c_accept_sig     constant text := 'invite_user_accept(uuid,text)';
  c_accept_before  constant text := 'f5ba4fd5053eb308c5e3e59ff99a3dfe';
  c_accept_after   constant text := '04eb29a50699f8f9f41d7ba591af3480';
  c_accept_anchor1 constant text := $a$  select * into inv from public.user_invitations where auth_user_id = p_auth_user_id for update;
$a$;
  c_accept_repl1   constant text := $r$  -- 429: a login invited again after a cancelled invitation has two; the
  -- pending one is the one being accepted.
  select * into inv from public.user_invitations where auth_user_id = p_auth_user_id
   order by (status = 'pending') desc, invited_at desc limit 1 for update;
$r$;
  c_accept_anchor2 constant text := $a$  update public.profiles
     set is_active = true, invitation_status = 'accepted', updated_at = now()
   where id = p_auth_user_id;
$a$;
  c_accept_repl2   constant text := $r$  -- 429: only the pending profile the invitation made is switched on. An
  -- invitation never tied to this login (its set-up did not finish) is not
  -- marked accepted with no profile behind it.
  if inv.auth_user_id is distinct from p_auth_user_id then
    return jsonb_build_object('activated', false, 'reason','not_set_up',
      'message','This invitation was not finished. Ask whoever invited you to send it again.');
  end if;
  update public.profiles
     set is_active = true, invitation_status = 'accepted', updated_at = now()
   where id = p_auth_user_id and invitation_status = 'pending' and deleted_at is null;
  if not found then
    return jsonb_build_object('activated', false, 'reason','not_set_up',
      'message','This invitation was not finished. Ask whoever invited you to send it again.');
  end if;
$r$;

  -- ── invite_user_begin ──────────────────────────────────────────────────────
  c_begin_sig    constant text := 'invite_user_begin(text,text,text,user_role,text,text,text,uuid[])';
  c_begin_before constant text := '8d2e1f3540a00dad9c1be25bd413e3c4';
  c_begin_after  constant text := 'eda7f730fd83891146265adb06eca132';
  c_begin_anchor constant text := $a$  if not public.can_assign_role(p_role) then
    return jsonb_build_object('outcome','forbidden',
      'message', format('Your role may not create %s accounts.', p_role));
  end if;
$a$;
  c_begin_repl   constant text := $r$  -- 429: the Admin role is no longer given to new staff (the Owner, 9 Oct
  -- 2026, Q13).
  if p_role = 'admin' then
    return jsonb_build_object('outcome','forbidden','field','role',
      'message','The Admin role is no longer given to new staff. Choose another role.');
  end if;
  if not public.can_assign_role(p_role) then
    return jsonb_build_object('outcome','forbidden',
      'message', format('Your role may not create %s accounts.', p_role));
  end if;
$r$;
  c_begin_anchor2 constant text := $a$  if exists (select 1 from public.profiles p where lower(p.email) = v_email and p.deleted_at is null) then
    return jsonb_build_object('outcome','email_in_use', 'scope','staff',
      'message','That login email already belongs to a user in this system. Nothing has been changed.');
  end if;
$a$;
  c_begin_repl2   constant text := $r$  if exists (select 1 from public.profiles p where lower(p.email) = v_email and p.deleted_at is null) then
    return jsonb_build_object('outcome','email_in_use', 'scope','staff',
      'message','That login email already belongs to a user in this system. Nothing has been changed.');
  end if;
  -- 429: a member of staff who was removed may be invited again (the Owner,
  -- 10 Oct 2026). The invitation reuses their login, so their history stays
  -- linked to it, and their profile is set up again as this invitation's.
  -- It is still their profile, so whoever invites them must be allowed to
  -- manage the role it has, as on Users & Roles. This holds whatever the
  -- profile's invitation state: when an Owner invites back a removed Manager
  -- and then cancels, the profile is a cancelled Manager's, and a Manager
  -- still may not invite them.
  if exists (select 1 from auth.users u join public.profiles p on p.id = u.id
              where lower(u.email) = v_email and p.deleted_at is not null
                and not public.can_assign_role(p.role)) then
    return jsonb_build_object('outcome','forbidden', 'scope','removed_staff',
      'message','This person was removed from Users & Roles, or their invitation was cancelled. '
                || 'Your role may not manage the role they have. '
                || 'Ask an Owner to invite them again. Nothing has been changed.');
  end if;
$r$;

  -- ── staff_login_sync ───────────────────────────────────────────────────────
  c_sync_sig     constant text := 'staff_login_sync(uuid)';
  c_sync_before  constant text := '7648388b0b41caee3696694ae172377e';
  c_sync_after   constant text := '9259111deccca8c66e95469acfdd250f';
  c_sync_anchor0 constant text := $a$  v_state := case
    when v_deleted is not null then 'removed'
    when coalesce(v_inv, 'accepted') = 'pending' then 'pending'
    when coalesce(v_inv, 'accepted') <> 'accepted' then 'invitation_cancelled'
$a$;
  c_sync_repl0   constant text := $r$  -- 429: a cancelled invitation is still named as such, now that
  -- invite_user_cancel also removes the profile. Closed either way.
  v_state := case
    when coalesce(v_inv, 'accepted') not in ('accepted', 'pending') then 'invitation_cancelled'
    when v_deleted is not null then 'removed'
    when coalesce(v_inv, 'accepted') = 'pending' then 'pending'
$r$;
  c_sync_anchor1 constant text := $a$  if v_state = 'pending' then
    return 'pending';
  end if;
$a$;
  c_sync_repl1   constant text := $r$  -- 429: a pending invitee is not blocked (412, rule 5). One whose login
  -- this blocked when an earlier invitation of theirs was cancelled, or who
  -- was removed and is invited again, has the block this placed lifted
  -- below, so the new link works.
  if v_state = 'pending' and not exists (select 1 from public.staff_login_blocks b where b.user_id = p_user_id) then
    return 'pending';
  end if;
$r$;
  c_sync_anchor2 constant text := $a$  if v_state = 'open' then
    if v_blk.user_id is null then
      return 'open';
    end if;
$a$;
  c_sync_repl2   constant text := $r$  if v_state in ('open', 'pending') then
    if v_blk.user_id is null then
      return v_state;
    end if;
$r$;

  -- ── trg_guard_profile_privileges ───────────────────────────────────────────
  c_guard_sig    constant text := 'trg_guard_profile_privileges()';
  c_guard_before constant text := '903ce9d75b2d0314428fb298a185d781';
  c_guard_after  constant text := 'b4e69e15ec0edaebde1448f1f15d89dd';
  c_guard_anchor constant text := $a$  if v_actor_role in ('owner','admin') then
    return new;                                  -- may set any role
  end if;
$a$;
  c_guard_repl   constant text := $r$  -- 429: the Admin role is no longer given to anyone (the Owner, 9 Oct
  -- 2026, Q13). Someone who has it keeps it until their role is changed.
  if v_role_changed and new.role = 'admin' then
    raise exception 'The Admin role is no longer given to anyone. Choose another role.'
      using errcode = '42501';
  end if;
  if v_actor_role in ('owner','admin') then
    return new;                                  -- may set any role but Admin
  end if;
$r$;

  -- ── trg_protect_system_payment_methods ─────────────────────────────────────
  c_protect_sig    constant text := 'trg_protect_system_payment_methods()';
  c_protect_before constant text := '9d8bc45f96b46bae93453d87d62a5c18';
  c_protect_after  constant text := '9c1af002437091b7ef61b04221b254eb';
  c_protect_anchor constant text := $a$      raise exception 'A system wallet payment method cannot be reconfigured';
    end if;
$a$;
  c_protect_repl   constant text := $r$      raise exception 'A system wallet payment method cannot be reconfigured';
    end if;
    -- 429: nor renamed. Staff and the reports know the five wallet credit
    -- types by these names.
    if new.name is distinct from old.name then
      raise exception 'A system wallet payment method cannot be renamed';
    end if;
    -- 429: nor switched off (the Owner, 10 Oct 2026). Customers spend their
    -- credit through these five methods, so they are always on.
    if old.is_active and not new.is_active then
      raise exception 'A system wallet payment method cannot be switched off';
    end if;
$r$;

  -- ── Whole new texts ────────────────────────────────────────────────────────
  c_roles_sig    constant text := 'assignable_roles()';
  c_roles_before constant text := '90bd806d630ef44845edd94d83b3d851';
  c_roles_after  constant text := '792bd103eaf31a84c43d1dd2ca5d5574';
  c_roles_def    constant text := $def$CREATE OR REPLACE FUNCTION public.assignable_roles()
 RETURNS user_role[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- The roles this administrator may give someone. 429: Admin is no longer
  -- given to anyone (the Owner, 9 Oct 2026, Q13); can_assign_role() says who
  -- may manage someone who already has a role.
  select case public.user_admin_role()
    when 'owner'   then array['owner','manager','inventory_manager','staff']::user_role[]
    when 'admin'   then array['owner','manager','inventory_manager','staff']::user_role[]
    when 'manager' then array['inventory_manager','staff']::user_role[]
    else '{}'::user_role[]
  end
$function$
$def$;

  c_canassign_sig    constant text := 'can_assign_role(user_role)';
  c_canassign_before constant text := 'c7c9b29b1be64baa32aa2005f7d7cb12';
  c_canassign_after  constant text := '1d7194e92d758bc01928f9115ec9f3af';
  c_canassign_def    constant text := $def$CREATE OR REPLACE FUNCTION public.can_assign_role(p_role user_role)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- Whether this administrator may manage someone with this role: their
  -- invitation, their profile and their stores. Owners and Admins: every
  -- role; Managers: Inventory Managers and Staff. 429: the same answers as
  -- before, no longer read from assignable_roles(), which stopped listing
  -- Admin (Q13): an Owner can still manage someone who has the Admin role.
  select case public.user_admin_role()
    when 'owner'   then p_role is not null
    when 'admin'   then p_role is not null
    when 'manager' then coalesce(p_role in ('inventory_manager','staff'), false)
    else false
  end
$function$
$def$;

  c_orphans_sig    constant text := 'user_admin_orphan_invitations()';
  c_orphans_before constant text := 'b39a4cfa6b3d2684b2fe2b5b01216711';
  c_orphans_after  constant text := '8856ea1bba6dbbf1f250e279686b1eef';
  c_orphans_def    constant text := $def$CREATE OR REPLACE FUNCTION public.user_admin_orphan_invitations()
 RETURNS TABLE(invitation_id uuid, email text, full_name text, role user_role, invited_at timestamp with time zone, last_email_status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.require_active_staff('{owner,admin,manager}');  -- 429: Users & Roles (Owners, Admins, Managers)
  -- Pending invitations whose login or profile was never made (the link
  -- could not be generated, or the set-up failed). Users & Roles lists people
  -- from their profiles, so it shows these beside them, with Resend and
  -- Cancel. Only the ones this administrator may manage.
  select i.id, i.email, i.full_name, i.role, i.invited_at, i.last_email_status
    from public.user_invitations i
   where i.status = 'pending' and i.auth_user_id is null
     and public.user_admin_role() is not null
     and public.can_assign_role(i.role)
   order by i.invited_at desc
$function$
$def$;

  c_reuse_sig   constant text := 'invite_user_reusable_login(uuid)';
  c_reuse_after constant text := '340580cff28c74eb1b1b8bde967dc8fc';
  c_reuse_def   constant text := $def$CREATE OR REPLACE FUNCTION public.invite_user_reusable_login(p_invitation_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 429: the login a pending invitation may use, if there is one already:
  -- the login tied to it, else the login with its address when that login is
  -- an invitee's who never accepted (a pending or cancelled invitation's
  -- profile), a removed member of staff's (the Owner, 10 Oct 2026), or was
  -- made by an invitation and never given a profile. Never an affiliate's
  -- login or a live member of staff's. admin-invite-user (the service role)
  -- asks this before it makes a link, so a cancelled person or a removed
  -- member of staff can be invited again and an unfinished invitation can be
  -- finished.
  select coalesce(i.auth_user_id, (
           select u.id from auth.users u
            where lower(u.email) = i.email_normalized
              and not exists (select 1 from public.affiliate_accounts a where a.auth_user_id = u.id)
              and (exists (select 1 from public.profiles p where p.id = u.id
                            and (p.invitation_status in ('pending', 'cancelled') or p.deleted_at is not null))
                   or (not exists (select 1 from public.profiles p where p.id = u.id)
                       and u.raw_user_meta_data ->> 'invited_to' = 'energia_internal'))
            order by u.created_at limit 1))
    from public.user_invitations i
   where i.id = p_invitation_id and i.status = 'pending'
$function$
$def$;

  c_webuses_sig   constant text := 'payment_method_web_uses()';
  c_webuses_after constant text := '766591ae7f9ddb163715e21deb812a0a';
  c_webuses_def   constant text := $def$CREATE OR REPLACE FUNCTION public.payment_method_web_uses()
 RETURNS TABLE(payment_method_id uuid, channel_key text, channel_mode text, used_for text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.require_active_staff('{owner,manager}');  -- 429: the Payment Methods page (Owners and Managers)
  -- Which payment methods the website order channels use, so the page can
  -- warn before one is switched off or renamed: a channel cannot turn its
  -- orders into invoices with a method that is off. Read as
  -- web_order_payment_method() reads them: the channel's method, its HitPay
  -- method (or, when it names none, the active method called
  -- 'HitPay (online)'), and the methods its door payments use.
  select u.method_id, c.key, c.mode, u.used_for
    from public.web_order_channels c
   cross join lateral (
     select c.payment_method_id as method_id, 'website orders'::text as used_for
     union all
     select coalesce(c.hitpay_payment_method_id,
                     (select m.id from public.payment_methods m
                       where lower(m.name) = lower('HitPay (online)') and m.is_active and m.deleted_at is null
                       order by m.created_at limit 1)),
            'website orders paid by HitPay'
     union all
     select (d.value #>> '{}')::uuid, 'payments at the door (' || d.key || ')'
       from jsonb_each(c.door_methods) d
      where jsonb_typeof(d.value) = 'string'
        and (d.value #>> '{}') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   ) u
   where u.method_id is not null
   order by c.key, u.used_for
$function$
$def$;

  -- ── Relied on ──────────────────────────────────────────────────────────────
  c_staff_406   constant text := '877b3aa74cea559881979bb161c450e2';  -- require_active_staff(text[])
  c_trg_412     constant text := 'a3a60fef98d7755b7104a5d96c4e38f8';  -- trg_staff_login_follows_profile()
  c_trigger_412 constant text := 'CREATE TRIGGER staff_login_follows_profile AFTER INSERT OR UPDATE OF is_active, deleted_at, invitation_status ON public.profiles FOR EACH ROW EXECUTE FUNCTION trg_staff_login_follows_profile()';
  c_protect_trigger constant text := 'CREATE TRIGGER protect_system_payment_methods BEFORE DELETE OR UPDATE ON public.payment_methods FOR EACH ROW EXECUTE FUNCTION trg_protect_system_payment_methods()';
  c_name_index  constant text := 'CREATE UNIQUE INDEX payment_methods_live_name_key ON public.payment_methods USING btree (lower(btrim(name))) WHERE (deleted_at IS NULL)';

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v text; n int; r record;
  v_texts jsonb := '{}';          -- signature -> text to install (only those still to do)
  v_bad text := '';
  v_owner uuid; v_login uuid; v_inv1 uuid; v_inv2 uuid; v_store_a uuid; v_store_b uuid;
  v_wallet uuid; v_old uuid; j jsonb; v_ban timestamptz; v_ok boolean;
begin
  perform set_config('search_path', 'public', true);

  -- ── Guards: nothing changes unless all pass ──────────────────────────────
  -- 406, 412 and 413 are in.
  if to_regprocedure('public.require_active_staff(text[])') is null
     or md5(pg_get_functiondef('public.require_active_staff(text[])'::regprocedure)) <> c_staff_406 then
    raise exception '429: 406 is not in (require_active_staff is missing or not 406''s version)'; end if;
  if to_regprocedure('public.trg_staff_login_follows_profile()') is null
     or md5(pg_get_functiondef('public.trg_staff_login_follows_profile()'::regprocedure)) <> c_trg_412 then
    raise exception '429: 412 is not in (trg_staff_login_follows_profile is missing or not 412''s version)'; end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'public.profiles'::regclass and not t.tgisinternal
                  and t.tgenabled = 'O' and pg_get_triggerdef(t.oid) = c_trigger_412) then
    raise exception '429: the trigger staff_login_follows_profile (412) is not on public.profiles, enabled'; end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'public.payment_methods'::regclass and not t.tgisinternal
                  and t.tgenabled = 'O' and pg_get_triggerdef(t.oid) = c_protect_trigger) then
    raise exception '429: the trigger protect_system_payment_methods is not on public.payment_methods, enabled'; end if;

  -- One function of each name; the two new names missing or exactly this.
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('invite_user_cancel', 'invite_user_prepare_resend', 'invite_user_provisioned',
                       'invite_user_accept', 'invite_user_begin', 'staff_login_sync', 'trg_guard_profile_privileges',
                       'trg_protect_system_payment_methods', 'assignable_roles', 'can_assign_role',
                       'user_admin_orphan_invitations', 'invite_user_reusable_login', 'payment_method_web_uses')
     and p.oid::regprocedure::text not in (c_cancel_sig, c_resend_sig, c_prov_sig, c_accept_sig, c_begin_sig,
                       c_sync_sig, c_guard_sig, c_protect_sig, c_roles_sig, c_canassign_sig, c_orphans_sig,
                       c_reuse_sig, c_webuses_sig);
  if v is not null then
    raise exception '429: another function takes one of the names: %', v; end if;

  -- The tables and columns the new texts read, as read on 9 Oct 2026.
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by a.attname) into v
    from pg_attribute a where a.attrelid = 'public.profiles'::regclass and not a.attisdropped
     and a.attname in ('deleted_at', 'invitation_status', 'is_active', 'updated_at');
  if v is distinct from 'deleted_at timestamp with time zone|invitation_status text|is_active boolean|updated_at timestamp with time zone' then
    raise exception '429: public.profiles is not shaped as read on 9 Oct 2026 (%)', v; end if;
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by a.attname) into v
    from pg_attribute a where a.attrelid = 'public.user_invitations'::regclass and not a.attisdropped
     and a.attname in ('auth_user_id', 'email_normalized', 'invited_at', 'role', 'status', 'store_ids');
  if v is distinct from 'auth_user_id uuid|email_normalized text|invited_at timestamp with time zone|role user_role|status text|store_ids uuid[]' then
    raise exception '429: public.user_invitations is not shaped as read on 9 Oct 2026 (%)', v; end if;
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by a.attname) into v
    from pg_attribute a where a.attrelid = 'auth.users'::regclass and not a.attisdropped
     and a.attname in ('created_at', 'email', 'id', 'raw_user_meta_data');
  if v is distinct from 'created_at timestamp with time zone|email character varying(255)|id uuid|raw_user_meta_data jsonb' then
    raise exception '429: auth.users is not shaped as read on 9 Oct 2026 (%)', v; end if;
  if (select format_type(a.atttypid, a.atttypmod) from pg_attribute a
       where a.attrelid = 'public.affiliate_accounts'::regclass and a.attname = 'auth_user_id' and not a.attisdropped) is distinct from 'uuid'
     or (select format_type(a.atttypid, a.atttypmod) from pg_attribute a
          where a.attrelid = 'public.staff_login_blocks'::regclass and a.attname = 'user_id' and not a.attisdropped) is distinct from 'uuid'
     or (select format_type(a.atttypid, a.atttypmod) from pg_attribute a
          where a.attrelid = 'public.user_store_assignments'::regclass and a.attname = 'store_id' and not a.attisdropped) is distinct from 'uuid' then
    raise exception '429: affiliate_accounts, staff_login_blocks or user_store_assignments is not shaped as read on 9 Oct 2026'; end if;
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by a.attname) into v
    from pg_attribute a where a.attrelid = 'public.web_order_channels'::regclass and not a.attisdropped
     and a.attname in ('door_methods', 'hitpay_payment_method_id', 'key', 'mode', 'payment_method_id');
  if v is distinct from 'door_methods jsonb|hitpay_payment_method_id uuid|key text|mode text|payment_method_id uuid' then
    raise exception '429: public.web_order_channels is not shaped as read on 9 Oct 2026 (%)', v; end if;
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by a.attname) into v
    from pg_attribute a where a.attrelid = 'public.payment_methods'::regclass and not a.attisdropped
     and a.attname in ('created_at', 'deleted_at', 'is_active', 'is_system', 'name');
  if v is distinct from 'created_at timestamp with time zone|deleted_at timestamp with time zone|is_active boolean|is_system boolean|name text' then
    raise exception '429: public.payment_methods is not shaped as read on 9 Oct 2026 (%)', v; end if;
  if not has_table_privilege(current_user, 'auth.users', 'select') then
    raise exception '429: % may not read auth.users, which invite_user_reusable_login reads with its rights', current_user; end if;

  -- payment_methods: the one name constraint read on 9 Oct 2026, or already
  -- the new index; and no two live names that the new index would refuse.
  select string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), '|' order by c.conname) into v
    from pg_constraint c where c.conrelid = 'public.payment_methods'::regclass and c.contype = 'u';
  if v is not null and v <> 'payment_methods_name_key UNIQUE (name)' then
    raise exception '429: payment_methods has unique constraints other than the one read on 9 Oct 2026 (%)', v; end if;
  if v is null and not exists (select 1 from pg_indexes i where i.schemaname = 'public' and i.tablename = 'payment_methods'
                                  and i.indexname = 'payment_methods_live_name_key' and i.indexdef = c_name_index) then
    raise exception '429: payment_methods has neither its name constraint nor the new index'; end if;
  if exists (select 1 from pg_constraint k where k.contype = 'f' and k.confrelid = 'public.payment_methods'::regclass
              and k.confkey <> array[(select a.attnum from pg_attribute a where a.attrelid = 'public.payment_methods'::regclass
                                       and a.attname = 'id')]) then
    raise exception '429: a foreign key refers to payment_methods by something other than its id'; end if;
  select string_agg(x.k, ', ') into v from (
    select lower(btrim(m.name)) k from public.payment_methods m where m.deleted_at is null
     group by 1 having count(*) > 1) x;
  if v is not null then
    raise exception '429: live payment methods share a name ignoring case and spaces (%); rename one first', v; end if;
  -- The five wallet credit types are always on from now on: none may be off
  -- or deleted when the rule starts (all five were on, 10 Oct 2026).
  select string_agg(m.name, ', ' order by m.name) into v from public.payment_methods m
   where m.is_system and (not m.is_active or m.deleted_at is not null);
  if v is not null then
    raise exception '429: a system wallet payment method is off or deleted (%); switch it on first', v; end if;

  -- The texts: BEFORE (patched here) or already AFTER (nothing to do).
  for r in select * from (values
      (c_cancel_sig,  c_cancel_before,  c_cancel_after,  array[c_cancel_anchor],                   array[c_cancel_repl]),
      (c_resend_sig,  c_resend_before,  c_resend_after,  array[c_resend_anchor1, c_resend_anchor2], array[c_resend_repl1, c_resend_repl2]),
      (c_prov_sig,    c_prov_before,    c_prov_after,    array[c_prov_anchor1, c_prov_anchor2],     array[c_prov_repl1, c_prov_repl2]),
      (c_accept_sig,  c_accept_before,  c_accept_after,  array[c_accept_anchor1, c_accept_anchor2], array[c_accept_repl1, c_accept_repl2]),
      (c_begin_sig,   c_begin_before,   c_begin_after,   array[c_begin_anchor, c_begin_anchor2],   array[c_begin_repl, c_begin_repl2]),
      (c_sync_sig,    c_sync_before,    c_sync_after,    array[c_sync_anchor0, c_sync_anchor1, c_sync_anchor2], array[c_sync_repl0, c_sync_repl1, c_sync_repl2]),
      (c_guard_sig,   c_guard_before,   c_guard_after,   array[c_guard_anchor],                    array[c_guard_repl]),
      (c_protect_sig, c_protect_before, c_protect_after, array[c_protect_anchor],                  array[c_protect_repl])
    ) x(sig, before_md5, after_md5, anchors, repls)
  loop
    if to_regprocedure('public.' || r.sig) is null then
      raise exception '429: public.% is missing', r.sig; end if;
    v := pg_get_functiondef(('public.' || r.sig)::regprocedure);
    if md5(v) = r.after_md5 then
      continue;
    elsif md5(v) <> r.before_md5 then
      raise exception '429: public.% is not the version read on 9 Oct 2026 (md5 %)', r.sig, md5(v);
    end if;
    for n in 1 .. cardinality(r.anchors) loop
      if (length(v) - length(replace(v, r.anchors[n], ''))) / length(r.anchors[n]) <> 1 then
        raise exception '429: anchor % of % occurs % times', n, r.sig,
          (length(v) - length(replace(v, r.anchors[n], ''))) / length(r.anchors[n]); end if;
      v := replace(v, r.anchors[n], r.repls[n]);
    end loop;
    if md5(v) <> r.after_md5 then
      v_bad := v_bad || format(' %s=%s', r.sig, md5(v));
    end if;
    v_texts := v_texts || jsonb_build_object(r.sig, v);
  end loop;
  for r in select * from (values
      (c_roles_sig,     c_roles_before,     c_roles_after,     c_roles_def),
      (c_canassign_sig, c_canassign_before, c_canassign_after, c_canassign_def),
      (c_orphans_sig,   c_orphans_before,   c_orphans_after,   c_orphans_def),
      (c_reuse_sig,     null,               c_reuse_after,     c_reuse_def),
      (c_webuses_sig,   null,               c_webuses_after,   c_webuses_def)
    ) x(sig, before_md5, after_md5, def)
  loop
    if md5(r.def) <> r.after_md5 then
      v_bad := v_bad || format(' %s=%s', r.sig, md5(r.def));
    end if;
    if to_regprocedure('public.' || r.sig) is null then
      if r.before_md5 is not null then
        raise exception '429: public.% is missing', r.sig; end if;
      v_texts := v_texts || jsonb_build_object(r.sig, r.def);
    elsif md5(pg_get_functiondef(('public.' || r.sig)::regprocedure)) = r.after_md5 then
      continue;
    elsif r.before_md5 is null
          or md5(pg_get_functiondef(('public.' || r.sig)::regprocedure)) <> r.before_md5 then
      raise exception '429: public.% is not the version read on 9 Oct 2026 (md5 %)', r.sig,
        md5(pg_get_functiondef(('public.' || r.sig)::regprocedure));
    else
      v_texts := v_texts || jsonb_build_object(r.sig, r.def);
    end if;
  end loop;
  if v_bad <> '' then
    raise exception '429: the texts built are not the ones tested:%', v_bad; end if;

  -- ── Change ───────────────────────────────────────────────────────────────
  for r in select key, value from jsonb_each_text(v_texts) loop
    execute r.value;
  end loop;

  if exists (select 1 from pg_constraint c where c.conrelid = 'public.payment_methods'::regclass
              and c.conname = 'payment_methods_name_key') then
    alter table public.payment_methods drop constraint payment_methods_name_key;
  end if;
  if not exists (select 1 from pg_indexes i where i.schemaname = 'public' and i.tablename = 'payment_methods'
                  and i.indexname = 'payment_methods_live_name_key') then
    create unique index payment_methods_live_name_key on public.payment_methods (lower(btrim(name)))
      where deleted_at is null;
  end if;
  comment on index public.payment_methods_live_name_key is
    '429: a payment method''s name is unique among live methods, ignoring case and outer spaces. A deleted method''s name can be used again.';

  -- The new internal helper is the service role's alone (339); the two
  -- functions the pages call are signed-in staff's, and refuse anyone else
  -- (require_active_staff).
  revoke all on function public.invite_user_reusable_login(uuid) from public, anon, authenticated;
  grant execute on function public.invite_user_reusable_login(uuid) to service_role;
  revoke all on function public.payment_method_web_uses() from public, anon;
  grant execute on function public.payment_method_web_uses() to authenticated, service_role;
  revoke all on function public.user_admin_orphan_invitations() from public, anon;
  grant execute on function public.user_admin_orphan_invitations() to authenticated, service_role;

  -- ── As tested ────────────────────────────────────────────────────────────
  for r in select * from (values
      (c_cancel_sig, c_cancel_after), (c_resend_sig, c_resend_after), (c_prov_sig, c_prov_after),
      (c_accept_sig, c_accept_after), (c_begin_sig, c_begin_after), (c_sync_sig, c_sync_after),
      (c_guard_sig, c_guard_after), (c_protect_sig, c_protect_after), (c_roles_sig, c_roles_after),
      (c_canassign_sig, c_canassign_after), (c_orphans_sig, c_orphans_after), (c_reuse_sig, c_reuse_after),
      (c_webuses_sig, c_webuses_after)) x(sig, after_md5)
  loop
    if md5(pg_get_functiondef(('public.' || r.sig)::regprocedure)) <> r.after_md5 then
      raise exception '429: public.% was installed with an md5 other than the tested one', r.sig; end if;
  end loop;
  if not exists (select 1 from pg_indexes i where i.schemaname = 'public' and i.tablename = 'payment_methods'
                  and i.indexname = 'payment_methods_live_name_key' and i.indexdef = c_name_index)
     or exists (select 1 from pg_constraint c where c.conrelid = 'public.payment_methods'::regclass and c.contype = 'u') then
    raise exception '429: the payment method name rule is not as tested'; end if;
  -- Grants: the pages' functions are staff's (and refuse others themselves);
  -- the server-only ones are the service role's alone.
  for r in select * from (values
      (c_begin_sig, true), (c_cancel_sig, true), (c_resend_sig, true), (c_roles_sig, true),
      (c_orphans_sig, true), (c_webuses_sig, true),
      (c_prov_sig, false), (c_accept_sig, false), (c_sync_sig, false), (c_guard_sig, false),
      (c_protect_sig, false), (c_canassign_sig, false), (c_reuse_sig, false)) x(sig, staff)
  loop
    if has_function_privilege('anon', 'public.' || r.sig, 'execute')
       or has_function_privilege('authenticated', 'public.' || r.sig, 'execute') <> r.staff
       or not has_function_privilege('service_role', 'public.' || r.sig, 'execute') then
      raise exception '429: the grants on public.% are not as tested', r.sig; end if;
  end loop;

  -- ── Behaviour, inside a block that is always undone ──────────────────────
  -- Made-up logins (@sig.invalid). Nothing is printed and no row remains.
  begin
    perform set_config('request.jwt.claims', '', true);
    insert into auth.users (id, email) values (gen_random_uuid(), '429-check-owner-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '429 check', u.email, 'owner', true from auth.users u where u.id = v_owner;
    insert into public.stores (name, code) values ('429 check A ' || gen_random_uuid(), '429A-' || gen_random_uuid())
      returning id into v_store_a;
    insert into public.stores (name, code) values ('429 check B ' || gen_random_uuid(), '429B-' || gen_random_uuid())
      returning id into v_store_b;

    -- An Owner invites a new address; the login Supabase Auth makes is tied.
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.invite_user_begin('429-check-1-' || replace(gen_random_uuid()::text, '-', ''),
           '429-check-new@sig.invalid', '429 check', 'staff',
           '+61491574632', '+61491575254', '429-check-personal@sig.invalid', array[v_store_a]);
    execute 'reset role';
    if j->>'outcome' is distinct from 'created' then
      raise exception '429: an Owner inviting a new address was not answered "created" (%)', j->>'outcome'; end if;
    v_inv1 := (j->>'invitation_id')::uuid;
    perform set_config('request.jwt.claims', '', true);
    insert into auth.users (id, email, raw_user_meta_data)
    values (gen_random_uuid(), '429-check-new@sig.invalid', '{"invited_to":"energia_internal"}') returning id into v_login;
    if public.invite_user_reusable_login(v_inv1) is distinct from v_login then
      raise exception '429: an invitation''s own unfinished login was not offered for reuse'; end if;
    j := public.invite_user_provisioned(v_inv1, v_login);
    if j->>'outcome' is distinct from 'provisioned' then
      raise exception '429: the first invitation''s login was not provisioned (%)', j->>'outcome'; end if;

    -- The Owner cancels: the profile is removed, the login blocked.
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.invite_user_cancel(v_inv1, '429 check');
    execute 'reset role';
    select u.banned_until into v_ban from auth.users u where u.id = v_login;
    if j->>'outcome' is distinct from 'cancelled'
       or not exists (select 1 from public.profiles p where p.id = v_login and p.deleted_at is not null
                       and p.invitation_status = 'cancelled' and not p.is_active)
       or v_ban is null or v_ban < now() + interval '99 years' then
      raise exception '429: cancelling did not remove the invitee''s profile and block the login'; end if;

    -- The Owner invites the same address again (other stores, another role).
    execute 'set local role authenticated';
    select count(*) into n from public.user_admin_list() x where x.user_id = v_login;
    j := public.invite_user_begin('429-check-2-' || replace(gen_random_uuid()::text, '-', ''),
           '429-Check-New@sig.invalid', '429 check again', 'inventory_manager',
           null, null, null, array[v_store_b]);
    execute 'reset role';
    if n <> 0 then
      raise exception '429: a cancelled invitee is still listed in Users & Roles'; end if;
    if j->>'outcome' is distinct from 'created' then
      raise exception '429: a cancelled person could not be invited again (%)', j->>'outcome'; end if;
    v_inv2 := (j->>'invitation_id')::uuid;
    perform set_config('request.jwt.claims', '', true);
    if public.invite_user_reusable_login(v_inv2) is distinct from v_login then
      raise exception '429: the cancelled invitee''s login was not offered for reuse'; end if;
    j := public.invite_user_provisioned(v_inv2, v_login);
    select u.banned_until into v_ban from auth.users u where u.id = v_login;
    if j->>'outcome' is distinct from 'provisioned'
       or not exists (select 1 from public.profiles p where p.id = v_login and p.deleted_at is null
                       and p.invitation_status = 'pending' and not p.is_active and p.role = 'inventory_manager'
                       and p.full_name = '429 check again')
       or v_ban is not null
       or exists (select 1 from public.staff_login_blocks b where b.user_id = v_login)
       or (select array_agg(s.store_id) from public.user_store_assignments s where s.user_id = v_login)
          is distinct from array[v_store_b] then
      raise exception '429: inviting again did not put the profile back as pending, unblocked, with the new stores'; end if;
    j := public.invite_user_accept(v_login, '429-check-new@sig.invalid');
    if (j->>'activated')::boolean is distinct from true
       or (select i.status from public.user_invitations i where i.id = v_inv2) <> 'accepted'
       or (select i.status from public.user_invitations i where i.id = v_inv1) <> 'cancelled'
       or not exists (select 1 from public.profiles p where p.id = v_login and p.is_active
                       and p.invitation_status = 'accepted') then
      raise exception '429: the second invitation was not the one accepted (%)', j; end if;

    -- A login that is a member of staff's is never made an invitee.
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.invite_user_begin('429-check-3-' || replace(gen_random_uuid()::text, '-', ''),
           '429-check-other@sig.invalid', '429 check other', 'staff',
           '+61491574632', '+61491575254', '429-check-personal@sig.invalid', '{}');
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    if j->>'outcome' is distinct from 'created' then
      raise exception '429: an Owner inviting another new address was not answered "created" (%)', j->>'outcome'; end if;
    j := public.invite_user_provisioned((j->>'invitation_id')::uuid, v_owner);
    if j->>'outcome' is distinct from 'login_in_use'
       or not exists (select 1 from public.profiles p where p.id = v_owner and p.role = 'owner' and p.is_active) then
      raise exception '429: a member of staff''s login was made an invitee (%)', j->>'outcome'; end if;

    -- A removed member of staff is invited again: their login is reused,
    -- what their profile was is kept in the audit log, the block 412 placed
    -- when they were removed is lifted, and accepting switches them on.
    insert into auth.users (id, email) values (gen_random_uuid(), '429-check-removed@sig.invalid') returning id into v_old;
    insert into public.profiles (id, full_name, email, role, is_active, deleted_at)
    values (v_old, '429 check removed', '429-check-removed@sig.invalid', 'staff', false, now());
    select u.banned_until into v_ban from auth.users u where u.id = v_old;
    if v_ban is null then
      raise exception '429: a removed member of staff''s login was not blocked to start with'; end if;
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.invite_user_begin('429-check-5-' || replace(gen_random_uuid()::text, '-', ''),
           '429-Check-Removed@sig.invalid', '429 check back', 'staff',
           '+61491574632', '+61491575254', '429-check-personal@sig.invalid', array[v_store_a]);
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    if j->>'outcome' is distinct from 'created' then
      raise exception '429: a removed member of staff could not be invited again (%)', j->>'outcome'; end if;
    v_inv1 := (j->>'invitation_id')::uuid;
    if public.invite_user_reusable_login(v_inv1) is distinct from v_old then
      raise exception '429: a removed member of staff''s login was not offered for reuse'; end if;
    j := public.invite_user_provisioned(v_inv1, v_old);
    select u.banned_until into v_ban from auth.users u where u.id = v_old;
    if j->>'outcome' is distinct from 'provisioned'
       or not exists (select 1 from public.profiles p where p.id = v_old and p.deleted_at is null
                       and p.invitation_status = 'pending' and not p.is_active and p.full_name = '429 check back')
       or v_ban is not null
       or exists (select 1 from public.staff_login_blocks b where b.user_id = v_old)
       or not exists (select 1 from public.audit_logs a where a.record_id = v_old and a.action = 'user_invitation_login_reused'
                       and a.old_data->>'full_name' = '429 check removed' and a.old_data->>'deleted_at' is not null) then
      raise exception '429: inviting a removed member of staff again did not reuse their login, keep what it was and lift the block'; end if;
    j := public.invite_user_accept(v_old, '429-check-removed@sig.invalid');
    if (j->>'activated')::boolean is distinct from true
       or not exists (select 1 from public.profiles p where p.id = v_old and p.is_active
                       and p.invitation_status = 'accepted' and p.deleted_at is null) then
      raise exception '429: a removed member of staff invited again was not switched on when they accepted (%)', j; end if;

    -- Admin is no longer given; an existing role can still be managed.
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.invite_user_begin('429-check-4-' || replace(gen_random_uuid()::text, '-', ''),
           '429-check-admin@sig.invalid', '429 check admin', 'admin', null, null, null, '{}');
    v_ok := 'admin' = any (public.assignable_roles());
    select count(*) into n from public.user_admin_orphan_invitations() x where x.email = '429-check-other@sig.invalid';
    execute 'reset role';
    if j->>'outcome' is distinct from 'forbidden' or v_ok then
      raise exception '429: the Admin role is still offered (%)', j->>'outcome'; end if;
    if n <> 1 then
      raise exception '429: an Owner does not see an unfinished invitation in the orphan list'; end if;
    -- The invitation functions above declared their intent for this whole
    -- transaction; a page's update has not.
    perform set_config('energia.profile_privilege_change', '', true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    begin
      execute 'set local role authenticated';
      update public.profiles set role = 'admin' where id = v_login;
      execute 'reset role';
      raise exception using errcode = 'P0429', message = '429: an Owner gave the Admin role';
    exception when sqlstate '42501' then execute 'reset role';
    end;

    -- Payment methods: a system wallet method keeps its name and stays on; a
    -- deleted method's name can be used again.
    perform set_config('request.jwt.claims', '', true);
    insert into public.payment_methods (name, is_wallet_credit, wallet_category, is_system)
    values ('429 check wallet ' || gen_random_uuid(), true, 'paid', true) returning id into v_wallet;
    begin
      update public.payment_methods set name = name || ' renamed' where id = v_wallet;
      raise exception using errcode = 'P0429', message = '429: a system wallet method was renamed';
    exception when raise_exception then
      if sqlerrm <> 'A system wallet payment method cannot be renamed' then raise; end if;
    end;
    begin
      update public.payment_methods set is_active = false where id = v_wallet;
      raise exception using errcode = 'P0429', message = '429: a system wallet method was switched off';
    exception when raise_exception then
      if sqlerrm <> 'A system wallet payment method cannot be switched off' then raise; end if;
    end;
    insert into public.payment_methods (name) values ('429 Check Method') returning id into v_old;
    update public.payment_methods set deleted_at = now(), is_active = false where id = v_old;
    insert into public.payment_methods (name) values (' 429 check method ');
    begin
      insert into public.payment_methods (name) values ('429 CHECK METHOD');
      raise exception using errcode = 'P0429', message = '429: two live methods share a name';
    exception when unique_violation then null;
    end;

    raise exception using errcode = 'P0430', message = '429: check done, undone';
  exception when sqlstate 'P0430' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
