-- Cancelling an invitation keeps the role guard on (505).
--
-- invite_user_cancel used to switch the profile role guard off at its first
-- step and never back on, for the rest of the transaction. Here a Manager calls
-- it and then tries to make themself Owner in the same transaction; and an
-- Owner really cancels an invitation, which must still work, and then tries to
-- change their own role.
--
--   sh scripts/invoices/local-sql.sh -f scripts/permissions/tests/role-guard-flag-505.sql
-- 505 is installed here when it is not in yet. Disposable local database only;
-- everything is rolled back. Made-up records only (G505, @example.invalid).
\set ON_ERROR_STOP on
begin;
select position('505:' in pg_get_functiondef('public.invite_user_cancel(uuid,text)'::regprocedure)) > 0 as m505_in \gset
\if :m505_in
\else
\ir ../../../supabase/505_cancelling_an_invitation_keeps_the_role_guard_on.sql
\endif
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;

do $$
declare own uuid := gen_random_uuid(); mgr uuid := gen_random_uuid(); inv_login uuid := gen_random_uuid();
        v_inv uuid; v_out jsonb; v_msg text;
begin
  insert into auth.users(id, email, email_confirmed_at) values
    (own, 'g505-owner@example.invalid', now()), (mgr, 'g505-manager@example.invalid', now()), (inv_login, 'g505-invitee@example.invalid', null);
  insert into public.profiles(id, full_name, email, role, is_active) values
    (own, 'G505 Owner', 'g505-owner@example.invalid', 'owner', true),
    (mgr, 'G505 Manager', 'g505-manager@example.invalid', 'manager', true);
  insert into public.profiles(id, full_name, email, role, is_active, invitation_status)
    values (inv_login, 'G505 Invitee', 'g505-invitee@example.invalid', 'staff', false, 'pending');
  insert into public.user_invitations(request_id, email, email_normalized, full_name, role, status, auth_user_id, invited_by)
    values (gen_random_uuid(), 'g505-invitee@example.invalid', 'g505-invitee@example.invalid', 'G505 Invitee', 'staff', 'pending', inv_login, own)
    returning id into v_inv;

  -- 1. a Manager: cancel something that is not there, then promote themself
  perform set_config('request.jwt.claim.sub', mgr::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', mgr, 'role', 'authenticated')::text, true);
  v_out := public.invite_user_cancel(gen_random_uuid(), 'G505 check');
  perform pg_temp.check(v_out->>'outcome' = 'not_found', '1 a Manager cancelling an unknown invitation is told not_found');
  perform pg_temp.check(coalesce(current_setting('energia.profile_privilege_change', true), '') <> 'on',
    '1 the guard''s flag is not left on after that call');
  begin
    update public.profiles set role = 'owner' where id = mgr;
    v_msg := 'accepted';
  exception when others then v_msg := sqlerrm; end;
  perform pg_temp.check(v_msg = 'You cannot change your own role.',
    '1 the Manager cannot then make themself Owner in the same transaction: ' || v_msg);
  perform pg_temp.check((select role::text from public.profiles where id = mgr) = 'manager', '1 and is still a Manager');

  -- 2. an Owner really cancels an invitation: the invitee's profile is still written
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  v_out := public.invite_user_cancel(v_inv, 'G505 check');
  perform pg_temp.check(v_out->>'outcome' = 'cancelled', '2 an Owner cancels a pending invitation: ' || v_out::text);
  perform pg_temp.check((select invitation_status = 'cancelled' and deleted_at is not null and not is_active from public.profiles where id = inv_login),
    '2 the invitee''s profile is cancelled and removed, as before (the guard let the server write through)');
  perform pg_temp.check(coalesce(current_setting('energia.profile_privilege_change', true), '') <> 'on',
    '2 the flag is off again after a cancellation that went through');
  begin
    update public.profiles set role = 'manager' where id = own;
    v_msg := 'accepted';
  exception when others then v_msg := sqlerrm; end;
  perform pg_temp.check(v_msg = 'You cannot change your own role.',
    '2 the Owner cannot then change their own role in the same transaction: ' || v_msg);
end $$;
rollback;
