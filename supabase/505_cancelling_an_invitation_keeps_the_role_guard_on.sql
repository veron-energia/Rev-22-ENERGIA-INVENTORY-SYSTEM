-- 505_cancelling_an_invitation_keeps_the_role_guard_on.sql
--
-- CANCELLING AN INVITATION KEEPS THE ROLE GUARD ON
--
--   From the security audit of 17 Nov 2026 (finding H3).
--   The BEFORE md5s below were compared with production on 17 Nov 2026 (head 502) and match.
--   If production's text differs when this is applied, it refuses and changes nothing.
--   (The number 505 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- WHAT WAS WRONG
--
--   The trigger guard_profile_privileges stops anyone changing their own role, and stops a
--   Manager giving any role but Inventory Manager or Staff. Server functions that must write
--   a profile say so by setting energia.profile_privilege_change to 'on' for the transaction
--   (231). invite_user_cancel set it as its first step after the caller test, before it had
--   even found the invitation, and never set it back. So for the rest of that transaction the
--   guard was off for whoever called it: an Owner, Admin or Manager.
--   The ordinary API runs one statement per request, so nothing follows. Supabase's GraphQL
--   endpoint (/graphql/v1) runs a whole request in one transaction. Shown on a local copy on
--   17 Nov 2026 as a Manager: "update profiles set role = 'owner'" on their own row is
--   refused; after "select invite_user_cancel(gen_random_uuid(), 'x')" (answer: not_found)
--   in the same transaction, the same update goes through.
--
-- WHAT THIS DOES
--
--   invite_user_cancel sets the flag only around its own update of the invitee's profile,
--   and clears it in the next statement. On every early answer (forbidden, not found,
--   already accepted, already cancelled) it is never set.
--
-- WHAT THIS LEAVES ALONE
--
--   * invite_user_accept and invite_user_provisioned set the same flag and do not clear it.
--     Only the service role can call them, and the service role is not subject to the guard.
--     On 17 Nov 2026 they were the only other functions on production that set it.
--   * The guard itself, and the design of a flag a transaction carries. A sturdier guard
--     would recognise a server write by the role running it.
--   * GraphQL. The app does not use it. Switching pg_graphql off (Dashboard, Database,
--     Extensions), or revoking usage on schema graphql_public from anon and authenticated,
--     closes the only known way to run two statements in one transaction as a login.
--
-- UNDO
--
--   Run this block with c_before and c_after swapped and c_anchor and c_new swapped; it then
--   refuses unless the function is 505's version. A later migration changing
--   invite_user_cancel must pin 505's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/permissions/tests/role-guard-flag-505.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- The function(s) this patches: BEFORE (the rebuilt copy of production) and AFTER md5s
  c_sig constant text[] := array[
    'invite_user_cancel(uuid,text)'];
  c_before constant text[] := array[
    'e9e97c330ed7189415e2f67cef9716c5'];
  c_after constant text[] := array[
    '957be434e8753a2c0151ee718e63c3b7'];
  -- Each patch: which function (its place in c_sig), the text found exactly once
  -- in it, and the text put in its place. The UNDO swaps them back.
  c_fn constant int[] := array[1, 1];
  c_anchor constant text[] := array[
$a$  end if;
  perform set_config('energia.profile_privilege_change', 'on', true);

  select * into inv from public.user_invitations where id = p_invitation_id for update;$a$,
$a$    update public.profiles
       set is_active = false, invitation_status = 'cancelled',
           deleted_at = coalesce(deleted_at, now()), updated_at = now()
     where id = inv.auth_user_id and invitation_status in ('pending', 'cancelled');$a$];
  c_new constant text[] := array[
$n$  end if;

  select * into inv from public.user_invitations where id = p_invitation_id for update;$n$,
$n$    -- 505: the role guard is told this is a server write for this one
    -- statement, and no longer so straight after it. It used to be told at the
    -- top of the function and never again, so whatever followed in the same
    -- transaction could change roles as it liked.
    perform set_config('energia.profile_privilege_change', 'on', true);
    update public.profiles
       set is_active = false, invitation_status = 'cancelled',
           deleted_at = coalesce(deleted_at, now()), updated_at = now()
     where id = inv.auth_user_id and invitation_status in ('pending', 'cancelled');
    perform set_config('energia.profile_privilege_change', '', true);$n$];
  -- Relied on, not changed
  c_relied constant text[] := array[
    'trg_guard_profile_privileges()',
    'profile_privilege_change_allowed()'];
  c_relied_md5 constant text[] := array[
    'b4e69e15ec0edaebde1448f1f15d89dd',
    '5fa0c10e9eb0c7007e87a2baf5d36264'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[1]);
  v_make boolean[] := array_fill(false, array[1]);
  v_acl text[] := array_fill(null::text, array[1]);
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
      raise exception '505: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The function(s) it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '505: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '505: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '505: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '505: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '505: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '505: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    -- compared as sets: production lists them in another order than a local copy
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '505: the grants of public.% changed', c_sig[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
