-- 512_only_an_owner_changes_an_owner.sql
--
-- ONLY AN OWNER CHANGES AN OWNER, AND THE LAST ACTIVE OWNER STAYS
--
--   From the security audit of 17 Nov 2026 (finding L1).
--   The BEFORE md5s below were compared with production on 17 Nov 2026 (head 510) and match.
--   If production's text differs when this is applied, it refuses and changes nothing.
--   (The number 512 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- WHAT WAS WRONG
--
--   The Admin role is no longer given to anyone (the Owner, 9 Oct 2026, Q13; 429), and
--   Users & Roles is closed to it. The database still let someone who has it do everything
--   an Owner does with users: make someone an Owner (on their profile, or by inviting them
--   as one), take the Owner role away from every Owner, and switch every Owner's login off.
--   Nothing kept the last active Owner either. Had the last one been stepped down, by an
--   Admin or by a server function, nobody would be left who can make an Owner. And two
--   Owners stepping each other down at the same moment could both go through, as each
--   change saw the other Owner still active. On 17 Nov 2026 production had no Admin and
--   two active Owners.
--
-- WHAT THIS DOES
--
--   * trg_guard_profile_privileges (the trigger guard_profile_privileges on profiles):
--     - Only an Owner gives someone the Owner role, takes it away, or switches an Owner's
--       login on or off. Someone with the Admin role is refused ("Only an Owner may change
--       an Owner's role or switch an Owner on or off.") and still manages every other role
--       as before. Owners and Managers are not changed; a Manager gets the same answers as
--       before.
--     - A change that would leave no active Owner is refused, whoever makes it, the service
--       role and the server's own functions included ("This is the last active Owner. Make
--       someone else an Owner first."). Active means what it means everywhere else: the
--       login is on, the profile is not removed, and its invitation, if any, is accepted.
--       Such changes take a lock first, so two at the same moment wait for each other and
--       the second one sees the first.
--   * assignable_roles(): an Admin's list no longer offers Owner.
--   * can_assign_role(user_role): an Admin no longer manages someone who has the Owner
--     role. That covers inviting one (invite_user_begin), inviting a removed Owner again,
--     resending or cancelling an Owner's invitation (invite_user_prepare_resend,
--     invite_user_cancel), an Owner's stores (assign_user_store), and Users & Roles marking
--     an Owner's row as not theirs to manage (user_admin_list,
--     user_admin_orphan_invitations).
--
-- WHAT THIS LEAVES ALONE
--
--   * Owners still give and take every role but Admin, and switch anyone but themselves on
--     or off. Nobody changes their own role or activation, as before.
--   * Managers: unchanged (Inventory Managers and Staff only).
--   * Someone with the Admin role can still edit an Owner's name and phone numbers (an
--     ordinary profile edit, under the rule "update profiles"). The audit asked only for
--     roles and activation, and nobody has the role.
--   * Deleting a profile row. Only the service role and the database itself can, and nothing
--     in the app does.
--   * The lock relies on each statement seeing what was committed before it, which is how
--     the API runs (read committed).
--
-- UNDO
--
--   Run this block with c_before and c_after swapped and c_anchor and c_new swapped; it then
--   refuses unless the functions are 512's version. A later migration changing any of the
--   three must pin 512's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/permissions/tests/owner-changes-by-owner-only-512.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- The function(s) this patches: BEFORE (production, 17 Nov 2026) and AFTER md5s
  c_sig constant text[] := array[
    'trg_guard_profile_privileges()',
    'assignable_roles()',
    'can_assign_role(user_role)'];
  c_before constant text[] := array[
    'b4e69e15ec0edaebde1448f1f15d89dd',
    '792bd103eaf31a84c43d1dd2ca5d5574',
    '1d7194e92d758bc01928f9115ec9f3af'];
  c_after constant text[] := array[
    '7a45127fc3f23b627285a6c5f90dbb6d',
    '3cf14cf4e4b06a7aa9f09c3f809eb12d',
    'b97c2bf355c585bb7c246c2678c253d2'];
  -- Each patch: which function (its place in c_sig), the text found exactly once
  -- in it, and the text put in its place. The UNDO swaps them back.
  c_fn constant int[] := array[1, 1, 2, 3];
  c_anchor constant text[] := array[
$a$  if not v_role_changed and not v_active_changed then
    return new;                                  -- ordinary profile edit
  end if;$a$,
$a$  if v_actor_role in ('owner','admin') then
    return new;                                  -- may set any role but Admin
  end if;$a$,
$a$    when 'admin'   then array['owner','manager','inventory_manager','staff']::user_role[]$a$,
$a$    when 'admin'   then p_role is not null$a$];
  c_new constant text[] := array[
$n$  -- 512: there is always an active Owner (security audit of 17 Nov 2026,
  -- L1). Nobody, the service role and the server's own functions included,
  -- takes the role away from the last one, switches their login off, removes
  -- them or moves their invitation on. Such changes wait for each other here,
  -- so two Owners stepping each other down at the same moment cannot both go
  -- through: the second one sees the first.
  if old.role = 'owner' and old.is_active and old.deleted_at is null
     and coalesce(old.invitation_status, 'accepted') = 'accepted'
     and not (new.role = 'owner' and new.is_active and new.deleted_at is null
              and coalesce(new.invitation_status, 'accepted') = 'accepted') then
    perform pg_advisory_xact_lock(hashtextextended('profile-last-active-owner', 0));
    if not exists (select 1 from public.profiles p
                    where p.id <> old.id and p.role = 'owner' and p.is_active
                      and p.deleted_at is null
                      and coalesce(p.invitation_status, 'accepted') = 'accepted') then
      raise exception 'This is the last active Owner. Make someone else an Owner first.'
        using errcode = '42501';
    end if;
  end if;
  if not v_role_changed and not v_active_changed then
    return new;                                  -- ordinary profile edit
  end if;$n$,
$n$  if v_actor_role = 'owner' then
    return new;                                  -- may set any role but Admin
  end if;
  if v_actor_role = 'admin' then
    -- 512: only an Owner gives the Owner role, takes it away, or switches an
    -- Owner's login on or off (security audit of 17 Nov 2026, L1). Admin is
    -- no longer given (429); someone who still has it manages every other
    -- role as before.
    if (v_role_changed and (old.role = 'owner' or new.role = 'owner'))
       or (v_active_changed and old.role = 'owner') then
      raise exception 'Only an Owner may change an Owner''s role or switch an Owner on or off.'
        using errcode = '42501';
    end if;
    return new;                                  -- may set any role but Admin and Owner
  end if;$n$,
$n$    -- 512: an Admin no longer gives the Owner role (security audit of
    -- 17 Nov 2026, L1).
    when 'admin'   then array['manager','inventory_manager','staff']::user_role[]$n$,
$n$    -- 512: an Admin no longer manages someone who has the Owner role
    -- (security audit of 17 Nov 2026, L1).
    when 'admin'   then coalesce(p_role <> 'owner', false)$n$];
  -- Relied on, not changed: who an administrator is, the server functions' flag, and
  -- every function that asks can_assign_role() whether this administrator may act.
  c_relied constant text[] := array[
    'user_admin_role()',
    'profile_privilege_change_allowed()',
    'invite_user_begin(text,text,text,user_role,text,text,text,uuid[])',
    'invite_user_prepare_resend(uuid)',
    'invite_user_cancel(uuid,text)',
    'assign_user_store(uuid,uuid,boolean)',
    'user_admin_list()',
    'user_admin_orphan_invitations()'];
  c_relied_md5 constant text[] := array[
    '6fe6c3202163ce80babdcf04fc28f76b',
    '5fa0c10e9eb0c7007e87a2baf5d36264',
    'eda7f730fd83891146265adb06eca132',
    '0ef0ebb3836bcdac6d6ee4a76e213753',
    '957be434e8753a2c0151ee718e63c3b7',
    'd52aee001ec2343f1fe3699843c3df71',
    '4d770ec592c3e96644602f196b4f7ce2',
    '8856ea1bba6dbbf1f250e279686b1eef'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[3]);
  v_make boolean[] := array_fill(false, array[3]);
  v_acl text[] := array_fill(null::text, array[3]);
  d text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy function waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '512: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  -- The guard is only worth patching while it runs on every update of a profile.
  if not exists (select 1 from pg_trigger t
                  where t.tgrelid = 'public.profiles'::regclass and t.tgname = 'guard_profile_privileges'
                    and t.tgenabled = 'O' and not t.tgisinternal
                    and t.tgfoid = 'public.trg_guard_profile_privileges()'::regprocedure) then
    raise exception '512: the trigger guard_profile_privileges on public.profiles is missing or switched off';
  end if;

  -- The function(s) it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '512: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '512: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '512: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '512: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '512: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '512: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    -- compared as sets: production lists them in another order than a local copy
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '512: the grants of public.% changed', c_sig[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
