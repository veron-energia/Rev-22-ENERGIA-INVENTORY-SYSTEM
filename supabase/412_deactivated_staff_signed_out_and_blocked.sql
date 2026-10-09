-- 412_deactivated_staff_signed_out_and_blocked.sql
--
-- WHAT WAS WRONG (follow-up to the security fix of 9 Oct 2026)
--
--   Since 406 and 407 the database treats a staff profile that is
--   deactivated, removed (a deleted date) or whose invitation was cancelled
--   as nobody: no staff function, table or PDF answers it. The login itself
--   was never touched. Such a person could still sign in with their password,
--   and a device already signed in kept its session, renewing it every hour.
--   Nothing told them they were out, and the login stayed usable wherever
--   Supabase Auth itself answers (changing the password, reading the account,
--   the invitation page). On 9 Oct 2026 production had 8 staff profiles, one
--   of them deactivated (no open session, not banned), and no invitations.
--
-- THE RULES (the Owner, 9 Oct 2026)
--
--   1. When a staff profile is deactivated (Active off), removed (a deleted
--      date) or its invitation is cancelled, that person's login is signed
--      out on every device and blocked from signing in.
--   2. When the profile is active, accepted and not removed again (an Owner
--      or Manager ticks Active), the login is unblocked by itself.
--   3. Staff only. An affiliate has no profile; suspending an affiliate on
--      the Affiliates page is unchanged.
--   4. The profile already closed is blocked once at go-live by
--      scripts/permissions/repair/412-block-existing-closed.sql, not here.
--   5. A pending invitee is not treated as closed (the Owner, 9 Oct 2026,
--      after the review). They sign in from the invitation link to accept it,
--      and Supabase Auth refuses that link for a banned login, so blocking
--      them would break every invitation. Their login is left alone until
--      they accept (open) or the invitation is cancelled (closed).
--   6. Supabase Auth may tell anyone who types a blocked staff member's email
--      that the login is switched off (the Owner accepted this, 9 Oct 2026;
--      see NOT CHANGED). The staff sign-in page says "This login has been
--      switched off. Ask an Owner or Manager if you need access."
--
-- WHAT THIS DOES
--
--   * staff_login_blocks (new table): one row for each login this blocked,
--     with why (deactivated, removed, invitation_cancelled), when, the ban
--     time it wrote and the ban there before. Row level security on, no
--     rules; no client role may touch it; the service role may read it.
--   * staff_login_sync(p_user_id) (new; internal, the service role's alone,
--     339): reads the profile and makes the login match it.
--       Closed: deletes every auth.sessions row of the login (the database
--       deletes their refresh tokens with them) and any refresh token left
--       with no session, and sets auth.users.banned_until a hundred years
--       ahead, the way Supabase Auth's own ban does, never 'infinity' (which
--       Supabase Auth cannot read). A login already banned for longer is left
--       as it is.
--       Open again: if this placed the ban and the ban is still that one, puts
--       back what was there before (nothing, normally); a ban placed or
--       changed in any other way stays. The row goes either way.
--       Pending, no profile, no login: nothing.
--     It writes an audit row (staff_login_blocked, staff_login_unblocked) when
--     something changed, and a second run changes nothing.
--   * trg_staff_login_follows_profile() (new; internal) and the trigger
--     staff_login_follows_profile on profiles, after insert or update of
--     is_active, deleted_at or invitation_status: calls staff_login_sync when
--     one of the three really changed. Every path that closes or reopens a
--     profile goes through it: the Users & Roles page (its direct update),
--     invite_user_cancel (the admin-invite-user Edge Function's Cancel),
--     invite_user_accept (auth-accept-invitation), invite_user_provisioned
--     (an invitation's profile), the service role and the SQL editor. No
--     other function writes those columns (production, 9 Oct 2026).
--
-- NOT CHANGED
--
--   * trg_guard_profile_privileges and "update profiles" (407): who may
--     deactivate whom is unchanged; this only follows what they allow.
--   * current_user_role(), require_active_staff() and the rest of 406.
--   * The invitation functions and the Edge Functions. Each one that acts for
--     a signed-in caller already refuses a closed one: admin-invite-user asks
--     invite_user_* as the caller (user_admin_role() is null for them);
--     auth-accept-invitation refuses an invitation that is not pending;
--     auth-change-password uses the caller's own session. Once this has run,
--     Supabase Auth refuses all three at once (the session is gone, the login
--     is banned).
--   * Affiliate logins and the Affiliates page. No profile is an affiliate's
--     login on production (9 Oct 2026).
--   * A profile deleted outright (no page or function does it; the service
--     role could) leaves the login as it was; it has no profile, so the
--     database treats it as nobody (406).
--   * An access token already issued keeps naming the login at the API until
--     it runs out (an hour at most; the database refuses it since 406).
--   * No row: the profile already closed is left to the repair script.
--   * What Supabase Auth tells a stranger. It answers "User is banned" before
--     it checks the password, so anyone who types a blocked staff member's
--     email, with any password, learns that the login is switched off.
--     Whether a login exists already shows today (a magic-link request is
--     answered differently), so only "switched off" is new. A blocked login
--     that never had a password (an invitee) still answers "Invalid login
--     credentials". This cannot be hidden while the ban is used, and the ban
--     is what stops the password, magic links and recovery links. Accepted by
--     the Owner on 9 Oct 2026 (rule 6).
--   * Inviting a new person fails on production today (invite_user_begin
--     reads a column affiliate_accounts does not have), and an invitation
--     cancelled while its login is being made leaves that login open: both
--     are 413, which goes after this.
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. It
--   refuses unless 406 and 407 are in (current_user_role() and
--   trg_guard_profile_privileges() at their AFTER md5s); profiles has the
--   columns read on 9 Oct 2026 and only the trigger guard_profile_privileges
--   (or this one, already); auth.users has banned_until, auth.sessions and
--   auth.refresh_tokens are shaped as read that day (a session's refresh
--   tokens are deleted with it) and none of the three has a trigger; and the
--   role running this (the owner of the new functions) may read and change
--   them past their row level security. The new functions and the table are
--   missing or already exactly this version; no other function takes their
--   names; each function text has its AFTER md5 before it is installed.
--   Afterwards the md5s, the trigger, the table and the grants are as tested,
--   and, switching role: a signed-in login with no profile and the anon key
--   can neither call staff_login_sync nor read the table. Then, inside a
--   block that is always undone, a made-up Owner deactivates a made-up member
--   of staff with two open sessions through the profile rules, as the page
--   does: both sessions go, the login is banned about a hundred years (a
--   finite time) and the block is recorded; ticking Active again lifts it.
--   Nothing is printed and no row remains.
--
-- BEFORE (production, 9 Oct 2026; md5 of pg_get_functiondef, search_path public):
--   relied on, not changed
--   current_user_role()                     519b0a33a3548f970c5d585b6e76a389  (406's AFTER)
--   trg_guard_profile_privileges()          903ce9d75b2d0314428fb298a185d781  (407's AFTER)
--   read for the paths, not relied on
--   invite_user_cancel(uuid,text)           03693443bf396a94cff6f99850ff0bc4
--   invite_user_accept(uuid,text)           f5ba4fd5053eb308c5e3e59ff99a3dfe
--   invite_user_provisioned(uuid,uuid)      868148e6c252f2c95de3bda6925b41a0
--   new: staff_login_sync(uuid), trg_staff_login_follows_profile() (missing)
--   public function fingerprint             40c96afb27ff263f7608100f5d683bac
-- AFTER (for later guards):
--   staff_login_sync(uuid)                  7648388b0b41caee3696694ae172377e
--   trg_staff_login_follows_profile()       a3a60fef98d7755b7104a5d96c4e38f8
--
-- DEPLOY ORDER: this, then the repair script once
-- (scripts/permissions/repair/412-block-existing-closed.sql), then 413, then
-- the front end (the Users & Roles page sends Active only when it changed and
-- says what happened to the login; the sign-in page words a blocked login
-- plainly). The pages live now keep working against this: a save that
-- deactivates someone signs them out as it saves (the live page sends Active
-- with every save, so a save from a copy of the page opened before someone
-- else switched that person on or off puts the older value back).
-- The new pages against a database without this would say a login was
-- signed out when it was not, so this goes first.
--
-- Test: scripts/permissions/tests/deactivated-login-blocked.sql (every path,
-- the bans, a re-run, the grants), scripts/permissions/tests/
-- deactivated-login-gotrue.mjs (Supabase Auth itself refuses and accepts the
-- login), scripts/permissions/tests/staff-only-functions.sql,
-- scripts/permissions/tests/function-grants.sql.

set lock_timeout = '5s';

do $mig$
declare
  c_sync_def constant text := $def$CREATE OR REPLACE FUNCTION public.staff_login_sync(p_user_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_active boolean; v_deleted timestamptz; v_inv text; v_state text;
  v_ban timestamptz; v_until timestamptz; v_actor uuid;
  v_blk public.staff_login_blocks%rowtype;
  v_sessions int := 0; v_tokens int := 0;
begin
  -- 412: a member of staff's login follows their profile (the Owner, 9 Oct
  -- 2026). A profile that is deactivated, removed (a deleted date) or whose
  -- invitation was cancelled is closed: its login is signed out on every
  -- device and cannot sign in. Once the profile is active, accepted and not
  -- removed again, the block this placed is lifted. A pending invitee is left
  -- alone: they sign in from the invitation link to accept it.
  --
  -- Signed out: every Supabase Auth session of the login is deleted, and its
  -- refresh tokens with it (the database cascades them; an old token with no
  -- session is deleted by its user id). An access token already issued still
  -- names the login until it expires, within the hour; the database has
  -- treated a closed profile as nobody since 406, and Supabase Auth refuses
  -- that token at once, its session being gone.
  --
  -- Blocked: auth.users.banned_until, as Supabase Auth's own ban. A time a
  -- hundred years ahead, never 'infinity', which Supabase Auth cannot read
  -- (every read of that login would fail). staff_login_blocks keeps the time
  -- written and what was there before, so a lift puts back only a ban this
  -- placed, and only while it is still the one in place. A ban placed in any
  -- other way is never lifted here.
  --
  -- Affiliates have no profile, so no affiliate login is ever reached. A
  -- missing profile or login is not an error. Running it again changes
  -- nothing.
  select p.is_active, p.deleted_at, p.invitation_status into v_active, v_deleted, v_inv
    from public.profiles p where p.id = p_user_id for update;
  if not found then
    return 'no_profile';
  end if;
  v_state := case
    when v_deleted is not null then 'removed'
    when coalesce(v_inv, 'accepted') = 'pending' then 'pending'
    when coalesce(v_inv, 'accepted') <> 'accepted' then 'invitation_cancelled'
    when not v_active then 'deactivated'
    else 'open' end;
  if v_state = 'pending' then
    return 'pending';
  end if;

  -- The login's row first, then the record: one order for every caller.
  select u.banned_until into v_ban from auth.users u where u.id = p_user_id for update;
  if not found then
    return 'no_login';
  end if;
  select * into v_blk from public.staff_login_blocks b where b.user_id = p_user_id for update;
  select p.id into v_actor from public.profiles p where p.id = auth.uid();

  if v_state = 'open' then
    if v_blk.user_id is null then
      return 'open';
    end if;
    if v_blk.banned_until_set is not null and v_ban is not distinct from v_blk.banned_until_set then
      update auth.users u set banned_until = v_blk.banned_until_before where u.id = p_user_id;
    end if;
    delete from public.staff_login_blocks b where b.user_id = p_user_id;
    insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by)
    values ('profiles', p_user_id, 'staff_login_unblocked',
            jsonb_build_object('reason', v_blk.reason, 'blocked_at', v_blk.blocked_at),
            jsonb_build_object('ban_lifted', v_blk.banned_until_set is not null
                                             and v_ban is not distinct from v_blk.banned_until_set),
            v_actor);
    return 'unblocked';
  end if;

  delete from auth.sessions s where s.user_id = p_user_id;
  get diagnostics v_sessions = row_count;
  delete from auth.refresh_tokens r where r.user_id = p_user_id::text;
  get diagnostics v_tokens = row_count;

  if v_blk.user_id is not null
     and v_ban is not distinct from coalesce(v_blk.banned_until_set, v_blk.banned_until_before) then
    -- Already blocked by this, and the ban is still the one it found or placed.
    update public.staff_login_blocks b set reason = v_state
     where b.user_id = p_user_id and b.reason is distinct from v_state;
    if v_sessions = 0 and v_tokens = 0 then
      return 'already_blocked';
    end if;
  else
    v_until := now() + interval '100 years';
    if v_ban is not null and v_ban >= v_until then
      v_until := null;  -- a longer ban placed some other way stands as it is
    else
      update auth.users u set banned_until = v_until where u.id = p_user_id;
    end if;
    insert into public.staff_login_blocks (user_id, reason, blocked_at, banned_until_set, banned_until_before)
    values (p_user_id, v_state, now(), v_until, v_ban)
    on conflict (user_id) do update
      set reason = excluded.reason, blocked_at = excluded.blocked_at,
          banned_until_set = excluded.banned_until_set, banned_until_before = excluded.banned_until_before;
  end if;
  insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by)
  values ('profiles', p_user_id, 'staff_login_blocked', null,
          jsonb_build_object('reason', v_state, 'sessions_ended', v_sessions,
                             'refresh_tokens_without_session', v_tokens,
                             'ban_placed', v_until is not null),
          v_actor);
  return 'blocked';
end
$function$
$def$;
  c_trg_def constant text := $def$CREATE OR REPLACE FUNCTION public.trg_staff_login_follows_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- 412: when a profile is made, or its active flag, deleted date or
  -- invitation state changes, its login follows (staff_login_sync): a closed
  -- profile's login is signed out everywhere and blocked, and an open one's
  -- block, if 412 placed it, is lifted. Every path passes here: the Users &
  -- Roles page, cancelling or accepting an invitation, the service role and
  -- the SQL editor. Other edits (a name, a phone) leave the login alone.
  if tg_op = 'UPDATE'
     and new.is_active is not distinct from old.is_active
     and new.deleted_at is not distinct from old.deleted_at
     and new.invitation_status is not distinct from old.invitation_status then
    return null;
  end if;
  perform public.staff_login_sync(new.id);
  return null;
end
$function$
$def$;
  c_sync_after constant text := '7648388b0b41caee3696694ae172377e';
  c_trg_after  constant text := 'a3a60fef98d7755b7104a5d96c4e38f8';
  c_role_406   constant text := '519b0a33a3548f970c5d585b6e76a389';
  c_guard_407  constant text := '903ce9d75b2d0314428fb298a185d781';
  c_trigger    constant text := 'CREATE TRIGGER staff_login_follows_profile AFTER INSERT OR UPDATE OF is_active, deleted_at, invitation_status ON public.profiles FOR EACH ROW EXECUTE FUNCTION trg_staff_login_follows_profile()';
  c_guard_trg  constant text := 'CREATE TRIGGER guard_profile_privileges BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION trg_guard_profile_privileges()';
  -- staff_login_blocks as this makes it: columns, then constraints.
  c_cols constant text := 'user_id uuid not null|reason text not null|blocked_at timestamp with time zone not null default now()|banned_until_set timestamp with time zone|banned_until_before timestamp with time zone';
  c_cons constant text := 'CHECK ((reason = ANY (ARRAY[''deactivated''::text, ''removed''::text, ''invitation_cancelled''::text])))|FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE|PRIMARY KEY (user_id)';
  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v text; v_bad text; n int;
  v_sync_new boolean; v_trg_new boolean; v_table_new boolean; v_trigger_new boolean;
  v_owner uuid; v_staff uuid; v_ban timestamptz;
begin
  perform set_config('search_path', 'public', true);

  -- ── Guards: nothing changes unless all pass ──────────────────────────────
  -- 406 and 407 are in.
  if to_regprocedure('public.current_user_role()') is null
     or md5(pg_get_functiondef('public.current_user_role()'::regprocedure)) <> c_role_406 then
    raise exception '412: 406 is not in (current_user_role() is not 406''s version); apply 406 and 407 first'; end if;
  if to_regprocedure('public.trg_guard_profile_privileges()') is null
     or md5(pg_get_functiondef('public.trg_guard_profile_privileges()'::regprocedure)) <> c_guard_407 then
    raise exception '412: 407 is not in (trg_guard_profile_privileges() is not 407''s version); apply 407 first'; end if;

  -- profiles, as read on 9 Oct 2026.
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end,
                    '|' order by a.attname) into v
    from pg_attribute a
   where a.attrelid = 'public.profiles'::regclass and a.attnum > 0 and not a.attisdropped
     and a.attname in ('id', 'is_active', 'deleted_at', 'invitation_status');
  if v is distinct from 'deleted_at timestamp with time zone|id uuid not null|invitation_status text|is_active boolean not null' then
    raise exception '412: public.profiles is not shaped as read on 9 Oct 2026 (%)', v; end if;
  if not exists (select 1 from pg_constraint k where k.conrelid = 'public.profiles'::regclass and k.contype = 'f'
                  and pg_get_constraintdef(k.oid) = 'FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE') then
    raise exception '412: a profile is no longer keyed by its login (profiles.id -> auth.users)'; end if;
  select string_agg(pg_get_triggerdef(t.oid), '|' order by t.tgname) into v
    from pg_trigger t where t.tgrelid = 'public.profiles'::regclass and not t.tgisinternal;
  if v is distinct from c_guard_trg and v is distinct from c_guard_trg || '|' || c_trigger then
    raise exception '412: the triggers on public.profiles are not the ones read on 9 Oct 2026 (%)', v; end if;
  v_trigger_new := v = c_guard_trg;
  if exists (select 1 from pg_trigger t where t.tgrelid = 'public.profiles'::regclass and not t.tgisinternal
              and t.tgenabled <> 'O') then
    raise exception '412: a trigger on public.profiles is disabled'; end if;

  -- Supabase Auth's tables, as read on 9 Oct 2026.
  if (select format_type(a.atttypid, a.atttypmod) from pg_attribute a
       where a.attrelid = 'auth.users'::regclass and a.attname = 'banned_until' and not a.attisdropped)
     is distinct from 'timestamp with time zone' then
    raise exception '412: auth.users.banned_until is missing or not a timestamp with time zone'; end if;
  if (select format_type(a.atttypid, a.atttypmod) from pg_attribute a
       where a.attrelid = 'auth.sessions'::regclass and a.attname = 'user_id' and not a.attisdropped)
     is distinct from 'uuid'
     or (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by a.attname)
           from pg_attribute a where a.attrelid = 'auth.refresh_tokens'::regclass
            and a.attname in ('user_id', 'session_id') and not a.attisdropped)
        is distinct from 'session_id uuid|user_id character varying(255)' then
    raise exception '412: auth.sessions or auth.refresh_tokens is not shaped as read on 9 Oct 2026'; end if;
  if not exists (select 1 from pg_constraint k where k.conrelid = 'auth.refresh_tokens'::regclass and k.contype = 'f'
                  and pg_get_constraintdef(k.oid) = 'FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE') then
    raise exception '412: a session''s refresh tokens are no longer deleted with it'; end if;
  if exists (select 1 from pg_trigger t where t.tgrelid in ('auth.users'::regclass, 'auth.sessions'::regclass,
                                                             'auth.refresh_tokens'::regclass) and not t.tgisinternal) then
    raise exception '412: auth.users, auth.sessions or auth.refresh_tokens has a trigger; none had on 9 Oct 2026. Re-read and re-test'; end if;
  -- The role running this owns the new functions, which act with its rights.
  if not (has_table_privilege(current_user, 'auth.users', 'select')
          and has_column_privilege(current_user, 'auth.users', 'banned_until', 'update')
          and has_table_privilege(current_user, 'auth.users', 'references')
          and has_table_privilege(current_user, 'auth.sessions', 'select,delete')
          and has_table_privilege(current_user, 'auth.refresh_tokens', 'select,delete')) then
    raise exception '412: % may not read and change auth.users, auth.sessions and auth.refresh_tokens', current_user; end if;
  if not exists (select 1 from pg_roles r where r.rolname = current_user and (r.rolbypassrls or r.rolsuper)) then
    raise exception '412: % does not pass row level security, which is on for Supabase Auth''s tables', current_user; end if;

  -- The new functions: missing, or already this version; no other takes their names.
  v_sync_new := to_regprocedure('public.staff_login_sync(uuid)') is null;
  if not v_sync_new and md5(pg_get_functiondef(to_regprocedure('public.staff_login_sync(uuid)'))) <> c_sync_after then
    raise exception '412: public.staff_login_sync(uuid) exists and is not this migration''s version'; end if;
  v_trg_new := to_regprocedure('public.trg_staff_login_follows_profile()') is null;
  if not v_trg_new and md5(pg_get_functiondef(to_regprocedure('public.trg_staff_login_follows_profile()'))) <> c_trg_after then
    raise exception '412: public.trg_staff_login_follows_profile() exists and is not this migration''s version'; end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('staff_login_sync', 'trg_staff_login_follows_profile')
     and p.oid::regprocedure::text not in ('staff_login_sync(uuid)', 'trg_staff_login_follows_profile()');
  if v_bad is not null then
    raise exception '412: another function takes one of the new names: %', v_bad; end if;
  if v_sync_new <> v_trg_new or v_trg_new <> v_trigger_new then
    raise exception '412: only part of this migration is installed; re-read and re-test'; end if;

  -- The table: missing, or already exactly this.
  v_table_new := to_regclass('public.staff_login_blocks') is null;
  if not v_table_new then
    select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
                      || case when a.attnotnull then ' not null' else '' end
                      || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), ''), '|' order by a.attnum) into v
      from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
     where a.attrelid = 'public.staff_login_blocks'::regclass and a.attnum > 0 and not a.attisdropped;
    if v is distinct from c_cols then
      raise exception '412: public.staff_login_blocks exists and is not this migration''s (%)', v; end if;
    select string_agg(pg_get_constraintdef(k.oid), '|' order by pg_get_constraintdef(k.oid)) into v
      from pg_constraint k where k.conrelid = 'public.staff_login_blocks'::regclass;
    if v is distinct from c_cons then
      raise exception '412: public.staff_login_blocks has other constraints (%)', v; end if;
  elsif not v_sync_new then
    raise exception '412: the functions are in but public.staff_login_blocks is missing';
  end if;

  -- The texts are the tested ones.
  if md5(c_sync_def) <> c_sync_after or md5(c_trg_def) <> c_trg_after then
    raise exception '412: a function text is not the tested one'; end if;

  -- ── Change ───────────────────────────────────────────────────────────────
  if v_table_new then
    create table public.staff_login_blocks (
      user_id uuid primary key references auth.users(id) on delete cascade,
      reason text not null check (reason in ('deactivated', 'removed', 'invitation_cancelled')),
      blocked_at timestamptz not null default now(),
      banned_until_set timestamptz,
      banned_until_before timestamptz);
    comment on table public.staff_login_blocks is
      '412: staff logins blocked because their profile was closed; the ban time written and the one before. Written by staff_login_sync() only.';
  end if;
  alter table public.staff_login_blocks enable row level security;
  revoke all on table public.staff_login_blocks from public, anon, authenticated, service_role;
  grant select on table public.staff_login_blocks to service_role;

  if v_sync_new then
    execute c_sync_def;
    revoke all on function public.staff_login_sync(uuid) from public, anon, authenticated;
    grant execute on function public.staff_login_sync(uuid) to service_role;
  end if;
  if v_trg_new then
    execute c_trg_def;
    revoke all on function public.trg_staff_login_follows_profile() from public, anon, authenticated;
    grant execute on function public.trg_staff_login_follows_profile() to service_role;
  end if;
  if v_trigger_new then
    create trigger staff_login_follows_profile
      after insert or update of is_active, deleted_at, invitation_status on public.profiles
      for each row execute function public.trg_staff_login_follows_profile();
  end if;

  -- ── As tested ────────────────────────────────────────────────────────────
  if md5(pg_get_functiondef('public.staff_login_sync(uuid)'::regprocedure)) <> c_sync_after
     or md5(pg_get_functiondef('public.trg_staff_login_follows_profile()'::regprocedure)) <> c_trg_after then
    raise exception '412: installed with md5s other than the tested ones'; end if;
  select string_agg(pg_get_triggerdef(t.oid), '|' order by t.tgname) into v
    from pg_trigger t where t.tgrelid = 'public.profiles'::regclass and not t.tgisinternal and t.tgenabled = 'O';
  if v is distinct from c_guard_trg || '|' || c_trigger then
    raise exception '412: the triggers on public.profiles are not as tested (%)', v; end if;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.staff_login_blocks'::regclass) then
    raise exception '412: row level security is off on public.staff_login_blocks'; end if;
  if exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'staff_login_blocks') then
    raise exception '412: public.staff_login_blocks has a rule; it should have none'; end if;
  if (select pg_get_userbyid(p.proowner) from pg_proc p where p.oid = 'public.staff_login_sync(uuid)'::regprocedure)
     is distinct from current_user then
    raise exception '412: staff_login_sync is not owned by the role that was checked'; end if;

  -- ── Grants, by the catalogue ─────────────────────────────────────────────
  foreach v in array array['staff_login_sync(uuid)', 'trg_staff_login_follows_profile()'] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '412: public.% is not the service role''s alone', v; end if;
  end loop;
  if has_table_privilege('anon', 'public.staff_login_blocks', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'public.staff_login_blocks', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('service_role', 'public.staff_login_blocks', 'insert,update,delete,truncate,references,trigger')
     or not has_table_privilege('service_role', 'public.staff_login_blocks', 'select') then
    raise exception '412: the grants on public.staff_login_blocks are not as tested'; end if;

  -- ── Behaviour, switching role (nothing is printed, no row remains) ───────
  -- A signed-in login with no profile, and the anon key.
  foreach v in array array['authenticated', 'anon'] loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', gen_random_uuid(), 'role', v)::text, true);
    execute format('set local role %I', v);
    begin
      perform public.staff_login_sync(gen_random_uuid());
      raise exception '412: % may call staff_login_sync', v;
    exception when insufficient_privilege then null;
    end;
    begin
      perform count(*) from public.staff_login_blocks;
      raise exception '412: % may read staff_login_blocks', v;
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';
  end loop;
  perform set_config('request.jwt.claims', '', true);

  -- The page's deactivation and reactivation, inside a block that is always
  -- undone: a made-up Owner and member of staff (@sig.invalid), two open
  -- sessions.
  begin
    insert into auth.users (id, email) values (gen_random_uuid(), '412-check-owner-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_owner;
    insert into auth.users (id, email) values (gen_random_uuid(), '412-check-staff-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_staff;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '412 check', u.email, x.role::public.user_role, true
      from auth.users u join (values (v_owner, 'owner'), (v_staff, 'staff')) x(id, role) on x.id = u.id;
    insert into auth.sessions (id, user_id, created_at, updated_at)
    values (gen_random_uuid(), v_staff, now(), now()), (gen_random_uuid(), v_staff, now(), now());

    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    update public.profiles set is_active = false where id = v_staff;
    execute 'reset role';
    select u.banned_until into v_ban from auth.users u where u.id = v_staff;
    if exists (select 1 from auth.sessions s where s.user_id = v_staff)
       or v_ban is null or not isfinite(v_ban)
       or v_ban < now() + interval '99 years' or v_ban > now() + interval '101 years'
       or not exists (select 1 from public.staff_login_blocks b where b.user_id = v_staff
                       and b.reason = 'deactivated' and b.banned_until_set = v_ban and b.banned_until_before is null) then
      raise exception '412: deactivating a member of staff did not sign them out and block them'; end if;
    if (select u.banned_until from auth.users u where u.id = v_owner) is not null then
      raise exception '412: the Owner''s own login was touched'; end if;

    execute 'set local role authenticated';
    update public.profiles set is_active = true where id = v_staff;
    execute 'reset role';
    if (select u.banned_until from auth.users u where u.id = v_staff) is not null
       or exists (select 1 from public.staff_login_blocks b where b.user_id = v_staff) then
      raise exception '412: ticking Active again did not lift the block'; end if;
    raise exception using errcode = 'P0412', message = '412: check done, undone';
  exception when sqlstate 'P0412' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
