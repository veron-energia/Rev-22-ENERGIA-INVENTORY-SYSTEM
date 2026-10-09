-- 413_invitations_begin_again_and_cancel_during_setup.sql
--
-- WHAT WAS WRONG (review of 412, 9 Oct 2026)
--
--   1. Inviting a new person fails on production. invite_user_begin checks
--      whether the address belongs to an affiliate by reading
--      affiliate_accounts.email, and affiliate_accounts has no email column
--      (production, 9 Oct 2026: id, auth_user_id, customer_id, affiliate_id,
--      status, created_at, updated_at, last_login_at). The check runs for every
--      address that is not already a profile or a pending invitation, so every
--      new invitation stops with "column a.email does not exist". The test
--      database of 230 still had that column, so nothing showed it. On 9 Oct
--      2026 production had no invitation at all.
--   2. An invitation cancelled while it is being set up leaves an open login.
--      admin-invite-user records the invitation (invite_user_begin), then has
--      Supabase Auth make the login, then ties the two (invite_user_provisioned).
--      If an Owner or Manager cancels in between (about a second, and only by
--      calling the API directly: the page lists no invitation before it has a
--      profile), invite_user_cancel finds no login to close, and
--      invite_user_provisioned answers "cancelled" without tying the login to
--      the invitation. The Edge Function did not look at that answer and sent
--      the invitation email anyway. The link then set a password on a login no
--      invitation knew, which 412 never blocks because it has no profile.
--
-- THE RULES (the Owner, 9 Oct 2026, as for 412)
--
--   1. When a staff invitation is cancelled, that person's login is signed out
--      on every device and blocked from signing in.
--   2. An address that already belongs to an affiliate is not invited here
--      (230's rule, unchanged).
--
-- WHAT THIS DOES
--
--   * invite_user_begin (patched): the affiliate check reads the affiliate's
--     login address from auth.users, joined by affiliate_accounts.auth_user_id.
--     Nothing else in it changes.
--   * invite_user_provisioned (patched): when the invitation was cancelled
--     before its login was tied to it, the login is tied to it now and, unless
--     it already has a profile or is an affiliate's login, gets a profile
--     closed as a cancelled invitee (Active off, invitation cancelled, no
--     store). 412's trigger then signs that login out and blocks it, and
--     auth-accept-invitation refuses its link before setting any password.
--     The answer is still "cancelled".
--   * The Edge Function (front end of this, same deploy): createInvitation
--     sends nothing unless invite_user_provisioned answers "provisioned", and
--     resendInvitation asks invite_user_prepare_resend again, as the caller,
--     just before it sends.
--
-- NOT CHANGED
--
--   * Who may invite whom, the contact rules, the store rule, the request id
--     and pending checks of invite_user_begin; the pending path of
--     invite_user_provisioned (the profile, the stores, the ids).
--   * invite_user_cancel, invite_user_accept, invite_user_prepare_resend,
--     invite_user_record_delivery, 412 and its rules.
--   * A login that already has a profile or an affiliate account is never
--     given a profile here; it stays as it is.
--   * No row: no invitation was cancelled during set-up on production
--     (there was no invitation on 9 Oct 2026).
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. It
--   refuses unless 412 is in (staff_login_sync() and its trigger function at
--   412's AFTER md5s, the trigger on profiles); both functions are the
--   versions read on 9 Oct 2026 (or already this one), with no overload;
--   affiliate_accounts.auth_user_id is a uuid tied to auth.users; profiles and
--   user_invitations have the columns read that day and a profile may be
--   'cancelled'; and the role running this may read auth.users. Each anchor
--   occurs exactly once and each text built has its AFTER md5 before it is
--   installed. CREATE OR REPLACE keeps the grants, which are checked
--   afterwards. Then, inside a block that is always undone: a made-up Owner
--   (@sig.invalid) invites a new address and is answered "created"; the Owner
--   cancels it; the login Supabase Auth would have made is tied to it as the
--   server would: it gets a cancelled profile, has no session and is banned
--   about a hundred years (412). Nothing is printed and no row remains.
--
-- BEFORE (production, 9 Oct 2026; md5 of pg_get_functiondef, search_path public):
--   invite_user_begin(text,text,text,user_role,text,text,text,uuid[])
--                                           2d2cc915c623b3d4d6d2a1227d3870b2
--   invite_user_provisioned(uuid,uuid)      868148e6c252f2c95de3bda6925b41a0
--   relied on, not changed
--   staff_login_sync(uuid)                  7648388b0b41caee3696694ae172377e  (412's AFTER)
--   trg_staff_login_follows_profile()       a3a60fef98d7755b7104a5d96c4e38f8  (412's AFTER)
--   invite_user_cancel(uuid,text)           03693443bf396a94cff6f99850ff0bc4
--   invite_user_prepare_resend(uuid)        78d04c138c7f3ebc62b4cb53623e1485
--   public function fingerprint             40c96afb27ff263f7608100f5d683bac (before 412)
-- AFTER (for later guards):
--   invite_user_begin(...)                  8d2e1f3540a00dad9c1be25bd413e3c4
--   invite_user_provisioned(uuid,uuid)      506816a8545148a24e9814d0bf2d5062
--
-- DEPLOY ORDER: 412 (and its repair script), then this, then the Edge Function
-- admin-invite-user (it carries supabase/functions/_shared/auth-email/
-- invitations.ts). The Edge Function live now against this: inviting works
-- again; a cancel during set-up still gets its email sent, but the login is
-- blocked, so the link is refused. The new Edge Function against a database
-- without this: unchanged, since invite_user_begin still fails.
--
-- Test: scripts/permissions/tests/invitation-cancelled-during-setup.sql
-- (begin, an affiliate's address, the cancel during set-up, a re-run),
-- supabase/functions/_shared/auth-email/tests/invitations.test.ts (npm run
-- test:auth-email:edge), scripts/permissions/tests/deactivated-login-blocked.sql,
-- scripts/permissions/tests/staff-only-functions.sql,
-- scripts/permissions/tests/function-grants.sql.

set lock_timeout = '5s';

do $mig$
declare
  c_begin_before constant text := '2d2cc915c623b3d4d6d2a1227d3870b2';
  c_begin_after  constant text := '8d2e1f3540a00dad9c1be25bd413e3c4';
  c_begin_anchor constant text := $a$    if exists (select 1 from public.affiliate_accounts a where lower(a.email) = v_email) then
$a$;
  c_begin_repl   constant text := $r$    -- 413: affiliate_accounts has no email column. An affiliate's address is
    -- their login's, in auth.users.
    if exists (select 1 from public.affiliate_accounts a join auth.users u on u.id = a.auth_user_id
                where lower(u.email) = v_email) then
$r$;
  c_prov_before  constant text := '868148e6c252f2c95de3bda6925b41a0';
  c_prov_after   constant text := '506816a8545148a24e9814d0bf2d5062';
  c_prov_anchor  constant text := $a$  if inv.status <> 'pending' then
    return jsonb_build_object('outcome', inv.status, 'message','This invitation is no longer pending.');
  end if;
$a$;
  c_prov_repl    constant text := $r$  if inv.status <> 'pending' then
    -- 413: cancelled while its login was being made. The login exists now:
    -- tie it to the invitation and, unless it is already someone's (a profile
    -- or an affiliate account), close it as a cancelled invitee. 412 then
    -- signs it out and blocks it, and its invitation link is refused. The
    -- Edge Function sends no email for this answer.
    if inv.status = 'cancelled' and inv.auth_user_id is null then
      update public.user_invitations
         set auth_user_id = p_auth_user_id, updated_at = now()
       where id = p_invitation_id;
      if not exists (select 1 from public.profiles p where p.id = p_auth_user_id)
         and not exists (select 1 from public.affiliate_accounts a where a.auth_user_id = p_auth_user_id) then
        insert into public.profiles (id, full_name, email, role, is_active,
                                     work_phone, personal_phone, personal_email, invitation_status)
        values (p_auth_user_id, inv.full_name, inv.email, inv.role, false,
                inv.work_phone, inv.personal_phone, inv.personal_email, 'cancelled')
        on conflict do nothing;
        if found then
          update public.user_invitations set profile_id = p_auth_user_id where id = p_invitation_id;
        end if;
      end if;
    end if;
    return jsonb_build_object('outcome', inv.status, 'message','This invitation is no longer pending.');
  end if;
$r$;
  c_sync_412     constant text := '7648388b0b41caee3696694ae172377e';
  c_trg_412      constant text := 'a3a60fef98d7755b7104a5d96c4e38f8';
  c_trigger_412  constant text := 'CREATE TRIGGER staff_login_follows_profile AFTER INSERT OR UPDATE OF is_active, deleted_at, invitation_status ON public.profiles FOR EACH ROW EXECUTE FUNCTION trg_staff_login_follows_profile()';
  c_begin_sig    constant text := 'invite_user_begin(text,text,text,user_role,text,text,text,uuid[])';
  c_prov_sig     constant text := 'invite_user_provisioned(uuid,uuid)';
  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v text; v_begin text; v_prov text; n int;
  v_begin_todo boolean; v_prov_todo boolean;
  v_owner uuid; v_login uuid; v_inv uuid; v_ban timestamptz; j jsonb;
begin
  perform set_config('search_path', 'public', true);

  -- ── Guards: nothing changes unless all pass ──────────────────────────────
  -- 412 is in: the login follows the profile.
  if to_regprocedure('public.staff_login_sync(uuid)') is null
     or md5(pg_get_functiondef(to_regprocedure('public.staff_login_sync(uuid)'))) <> c_sync_412
     or to_regprocedure('public.trg_staff_login_follows_profile()') is null
     or md5(pg_get_functiondef(to_regprocedure('public.trg_staff_login_follows_profile()'))) <> c_trg_412 then
    raise exception '413: 412 is not in (staff_login_sync or its trigger function is not 412''s version); apply 412 first'; end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'public.profiles'::regclass and not t.tgisinternal
                  and t.tgenabled = 'O' and pg_get_triggerdef(t.oid) = c_trigger_412) then
    raise exception '413: the trigger staff_login_follows_profile (412) is not on public.profiles, enabled'; end if;

  -- One function of each name, at the version read on 9 Oct 2026 (or this one).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname in ('invite_user_begin', 'invite_user_provisioned')
     and p.oid::regprocedure::text not in (c_begin_sig, c_prov_sig);
  if v is not null then
    raise exception '413: another function takes one of the names: %', v; end if;
  if to_regprocedure('public.' || c_begin_sig) is null or to_regprocedure('public.' || c_prov_sig) is null then
    raise exception '413: invite_user_begin or invite_user_provisioned is missing'; end if;

  -- The tables the new text reads, as read on 9 Oct 2026.
  if (select format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end
        from pg_attribute a where a.attrelid = 'public.affiliate_accounts'::regclass
         and a.attname = 'auth_user_id' and not a.attisdropped) is distinct from 'uuid not null'
     or not exists (select 1 from pg_constraint k where k.conrelid = 'public.affiliate_accounts'::regclass and k.contype = 'f'
                     and pg_get_constraintdef(k.oid) = 'FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE') then
    raise exception '413: affiliate_accounts.auth_user_id is not a login id as read on 9 Oct 2026'; end if;
  if exists (select 1 from pg_attribute a where a.attrelid = 'public.affiliate_accounts'::regclass
              and a.attname = 'email' and not a.attisdropped) then
    raise exception '413: affiliate_accounts has an email column again; re-read and re-test'; end if;
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by a.attname) into v
    from pg_attribute a where a.attrelid = 'public.user_invitations'::regclass and not a.attisdropped
     and a.attname in ('auth_user_id', 'profile_id', 'status', 'updated_at');
  if v is distinct from 'auth_user_id uuid|profile_id uuid|status text|updated_at timestamp with time zone' then
    raise exception '413: public.user_invitations is not shaped as read on 9 Oct 2026 (%)', v; end if;
  if not exists (select 1 from pg_constraint k where k.conrelid = 'public.profiles'::regclass and k.contype = 'c'
                  and pg_get_constraintdef(k.oid) = 'CHECK (((invitation_status IS NULL) OR (invitation_status = ANY (ARRAY[''pending''::text, ''accepted''::text, ''cancelled''::text]))))') then
    raise exception '413: a profile''s invitation state is not checked as read on 9 Oct 2026'; end if;
  if not has_table_privilege(current_user, 'auth.users', 'select') then
    raise exception '413: % may not read auth.users, which invite_user_begin now reads with its rights', current_user; end if;

  -- The texts: BEFORE (patched here) or already AFTER (nothing to do).
  v_begin := pg_get_functiondef(('public.' || c_begin_sig)::regprocedure);
  if md5(v_begin) = c_begin_after then
    v_begin_todo := false;
  elsif md5(v_begin) = c_begin_before then
    v_begin_todo := true;
    n := (length(v_begin) - length(replace(v_begin, c_begin_anchor, ''))) / length(c_begin_anchor);
    if n <> 1 then raise exception '413: invite_user_begin''s anchor occurs % times', n; end if;
    v_begin := replace(v_begin, c_begin_anchor, c_begin_repl);
    if md5(v_begin) <> c_begin_after then
      raise exception '413: the invite_user_begin built is not the one tested (md5 %)', md5(v_begin); end if;
  else
    raise exception '413: public.invite_user_begin is not the version read on 9 Oct 2026 (md5 %)', md5(v_begin);
  end if;
  v_prov := pg_get_functiondef(('public.' || c_prov_sig)::regprocedure);
  if md5(v_prov) = c_prov_after then
    v_prov_todo := false;
  elsif md5(v_prov) = c_prov_before then
    v_prov_todo := true;
    n := (length(v_prov) - length(replace(v_prov, c_prov_anchor, ''))) / length(c_prov_anchor);
    if n <> 1 then raise exception '413: invite_user_provisioned''s anchor occurs % times', n; end if;
    v_prov := replace(v_prov, c_prov_anchor, c_prov_repl);
    if md5(v_prov) <> c_prov_after then
      raise exception '413: the invite_user_provisioned built is not the one tested (md5 %)', md5(v_prov); end if;
  else
    raise exception '413: public.invite_user_provisioned is not the version read on 9 Oct 2026 (md5 %)', md5(v_prov);
  end if;

  -- ── Change ───────────────────────────────────────────────────────────────
  if v_begin_todo then execute v_begin; end if;
  if v_prov_todo then execute v_prov; end if;

  -- ── As tested ────────────────────────────────────────────────────────────
  if md5(pg_get_functiondef(('public.' || c_begin_sig)::regprocedure)) <> c_begin_after
     or md5(pg_get_functiondef(('public.' || c_prov_sig)::regprocedure)) <> c_prov_after then
    raise exception '413: installed with md5s other than the tested ones'; end if;
  -- The grants are kept: invite_user_begin is the caller's (admin-invite-user
  -- asks it as the signed-in administrator), invite_user_provisioned the
  -- service role's alone (339).
  if has_function_privilege('anon', 'public.' || c_begin_sig, 'execute')
     or not has_function_privilege('authenticated', 'public.' || c_begin_sig, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_begin_sig, 'execute')
     or has_function_privilege('anon', 'public.' || c_prov_sig, 'execute')
     or has_function_privilege('authenticated', 'public.' || c_prov_sig, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_prov_sig, 'execute') then
    raise exception '413: the grants on the two functions are not as tested'; end if;

  -- ── Behaviour, inside a block that is always undone ──────────────────────
  -- A made-up Owner (@sig.invalid) invites a new address, then cancels it
  -- before the login is tied to it; the server ties it as admin-invite-user
  -- does. Nothing is printed and no row remains.
  begin
    insert into auth.users (id, email) values (gen_random_uuid(), '413-check-owner-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '413 check', u.email, 'owner', true from auth.users u where u.id = v_owner;

    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.invite_user_begin('413-check-' || replace(gen_random_uuid()::text, '-', ''),
           '413-check-new-' || gen_random_uuid() || '@sig.invalid', '413 check', 'staff',
           '+6500000413', '+6500000414', '413-check-personal@sig.invalid', '{}');
    execute 'reset role';
    if j->>'outcome' is distinct from 'created' then
      raise exception '413: an Owner inviting a new address was not answered "created" (%)', j->>'outcome'; end if;
    v_inv := (j->>'invitation_id')::uuid;

    execute 'set local role authenticated';
    j := public.invite_user_cancel(v_inv, '413 check');
    execute 'reset role';
    if j->>'outcome' is distinct from 'cancelled' then
      raise exception '413: the Owner could not cancel the invitation (%)', j->>'outcome'; end if;

    perform set_config('request.jwt.claims', '', true);
    insert into auth.users (id, email)
    select gen_random_uuid(), i.email_normalized from public.user_invitations i where i.id = v_inv
    returning id into v_login;
    insert into auth.sessions (id, user_id, created_at, updated_at) values (gen_random_uuid(), v_login, now(), now());
    j := public.invite_user_provisioned(v_inv, v_login);
    select u.banned_until into v_ban from auth.users u where u.id = v_login;
    if j->>'outcome' is distinct from 'cancelled'
       or not exists (select 1 from public.user_invitations i where i.id = v_inv
                       and i.status = 'cancelled' and i.auth_user_id = v_login and i.profile_id = v_login)
       or not exists (select 1 from public.profiles p where p.id = v_login and not p.is_active
                       and p.invitation_status = 'cancelled' and p.deleted_at is null)
       or exists (select 1 from public.user_store_assignments s where s.user_id = v_login)
       or exists (select 1 from auth.sessions s where s.user_id = v_login)
       or v_ban is null or not isfinite(v_ban)
       or v_ban < now() + interval '99 years' or v_ban > now() + interval '101 years'
       or not exists (select 1 from public.staff_login_blocks b where b.user_id = v_login
                       and b.reason = 'invitation_cancelled') then
      raise exception '413: a login made for an invitation cancelled during set-up was not tied to it and blocked'; end if;
    if (select u.banned_until from auth.users u where u.id = v_owner) is not null then
      raise exception '413: the Owner''s own login was touched'; end if;
    raise exception using errcode = 'P0413', message = '413: check done, undone';
  exception when sqlstate 'P0413' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
