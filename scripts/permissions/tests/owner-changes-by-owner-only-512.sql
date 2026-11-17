-- Only an Owner changes an Owner, and the last active Owner stays (512).
--
-- Someone who still has the retired Admin role tries to make an Owner, step one
-- down, switch one off or on, and invite one; an Owner and a Manager do what they
-- did before; and the last active Owner is stepped down, switched off, removed
-- and cancelled by the server itself, which must all be refused.
--
--   sh scripts/invoices/local-sql.sh -f scripts/permissions/tests/owner-changes-by-owner-only-512.sql
-- 512 is installed here when it is not in yet. Disposable local database only;
-- everything is rolled back. Made-up records only (L512, @example.invalid).
\set ON_ERROR_STOP on
begin;
select position('512:' in pg_get_functiondef('public.trg_guard_profile_privileges()'::regprocedure)) > 0 as m512_in \gset
\if :m512_in
\else
\ir ../../../supabase/512_only_an_owner_changes_an_owner.sql
\endif
-- A second run changes nothing.
\ir ../../../supabase/512_only_an_owner_changes_an_owner.sql

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;
-- Runs one statement; 'ok' or the error's text. Nothing it did is kept on an error.
create function pg_temp.try(q text) returns text language plpgsql as
$f$ begin execute q; return 'ok'; exception when others then return sqlerrm; end $f$;
-- The same as a signed-in login (the authenticated role, row rules on).
create function pg_temp.try_login(q text) returns text language plpgsql as
$f$ begin execute 'set local role authenticated'; execute q; execute 'reset role'; return 'ok';
exception when others then return sqlerrm; end $f$;
create function pg_temp.as_user(u uuid) returns void language plpgsql as
$f$ begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
end $f$;
-- The service role or the database itself: no signed-in user.
create function pg_temp.as_server() returns void language plpgsql as
$f$ begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end $f$;

do $$
declare
  own  uuid := gen_random_uuid(); own2 uuid := gen_random_uuid(); was_own uuid := gen_random_uuid();
  adm  uuid := gen_random_uuid(); mgr  uuid := gen_random_uuid();
  stf  uuid := gen_random_uuid(); stf2 uuid := gen_random_uuid();
  c_admin constant text := 'Only an Owner may change an Owner''s role or switch an Owner on or off.';
  c_last  constant text := 'This is the last active Owner. Make someone else an Owner first.';
  v text; v_out jsonb; v_roles jsonb;
begin
  insert into auth.users(id, email, email_confirmed_at) values
    (own, 'l512-owner@example.invalid', now()), (own2, 'l512-owner2@example.invalid', now()),
    (was_own, 'l512-former-owner@example.invalid', now()), (adm, 'l512-admin@example.invalid', now()),
    (mgr, 'l512-manager@example.invalid', now()), (stf, 'l512-staff@example.invalid', now()),
    (stf2, 'l512-staff2@example.invalid', now());
  insert into public.profiles(id, full_name, email, role, is_active) values
    (own,     'L512 Owner',        'l512-owner@example.invalid',        'owner',   true),
    (own2,    'L512 Owner Two',    'l512-owner2@example.invalid',       'owner',   true),
    (was_own, 'L512 Former Owner', 'l512-former-owner@example.invalid', 'owner',   false),
    (adm,     'L512 Admin',        'l512-admin@example.invalid',        'admin',   true),
    (mgr,     'L512 Manager',      'l512-manager@example.invalid',      'manager', true),
    (stf,     'L512 Staff',        'l512-staff@example.invalid',        'staff',   true),
    (stf2,    'L512 Staff Two',    'l512-staff2@example.invalid',       'staff',   true);

  -- 1. Someone with the Admin role (nobody has it on production)
  perform pg_temp.as_user(adm);
  v := pg_temp.try(format('update public.profiles set role = %L where id = %L', 'owner', stf));
  perform pg_temp.check(v = c_admin, '1a an Admin cannot make a member of staff an Owner: ' || v);
  v := pg_temp.try(format('update public.profiles set role = %L where id = %L', 'staff', own));
  perform pg_temp.check(v = c_admin, '1b an Admin cannot take the Owner role away: ' || v);
  v := pg_temp.try(format('update public.profiles set is_active = false where id = %L', own2));
  perform pg_temp.check(v = c_admin, '1c an Admin cannot switch an Owner off: ' || v);
  v := pg_temp.try(format('update public.profiles set is_active = true where id = %L', was_own));
  perform pg_temp.check(v = c_admin, '1d an Admin cannot switch a former Owner back on: ' || v);
  perform pg_temp.check((select count(*) from public.profiles where id in (own, own2) and role = 'owner' and is_active) = 2
                        and (select role from public.profiles where id = stf) = 'staff'
                        and not (select is_active from public.profiles where id = was_own),
    '1e nothing above changed');
  v := pg_temp.try(format('update public.profiles set role = %L where id = %L', 'manager', stf));
  perform pg_temp.check(v = 'ok' and (select role from public.profiles where id = stf) = 'manager',
    '1f an Admin still makes a member of staff a Manager: ' || v);
  v := pg_temp.try(format('update public.profiles set role = %L where id = %L', 'staff', stf));
  perform pg_temp.check(v = 'ok', '1g and back to Staff: ' || v);
  v := pg_temp.try(format('update public.profiles set is_active = false where id = %L', stf2));
  perform pg_temp.check(v = 'ok' and not (select is_active from public.profiles where id = stf2),
    '1h an Admin still switches a member of staff off: ' || v);
  v := pg_temp.try(format('update public.profiles set work_phone = %L where id = %L', '+61491570512', own));
  perform pg_temp.check(v = 'ok', '1i an Admin can still edit an Owner''s phone numbers (left alone by 512): ' || v);
  v_roles := to_jsonb(public.assignable_roles());
  perform pg_temp.check(v_roles = '["manager","inventory_manager","staff"]'::jsonb,
    '1j an Admin''s role list no longer offers Owner: ' || v_roles::text);
  perform pg_temp.check(not public.can_assign_role('owner') and public.can_assign_role('manager')
                        and public.can_assign_role('admin') and public.can_assign_role('staff')
                        and not coalesce(public.can_assign_role(null), false),
    '1k an Admin no longer manages an Owner, and still manages every other role');
  v_out := public.invite_user_begin('L512-req-owner', 'l512-new-owner@example.invalid', 'L512 New Owner', 'owner',
                                    '+61491570513', '+61491570514', 'l512-new-owner-p@example.invalid', '{}');
  perform pg_temp.check(v_out->>'outcome' = 'forbidden'
                        and v_out->>'message' = 'Your role may not create owner accounts.'
                        and not exists (select 1 from public.user_invitations where email_normalized = 'l512-new-owner@example.invalid'),
    '1l an Admin cannot invite an Owner, and nothing is saved: ' || v_out::text);
  v_out := public.invite_user_begin('L512-req-manager', 'l512-new-manager@example.invalid', 'L512 New Manager', 'manager',
                                    '+61491570515', '+61491570516', 'l512-new-manager-p@example.invalid', '{}');
  perform pg_temp.check(coalesce(v_out->>'outcome', '') <> 'forbidden',
    '1m an Admin may still invite a Manager: ' || v_out::text);
  perform pg_temp.check((select bool_and(not l.can_manage) filter (where l.user_id in (own, own2, was_own))
                            and bool_and(l.can_manage) filter (where l.user_id in (mgr, stf, stf2))
                           from public.user_admin_list() l),
    '1n Users & Roles marks Owners as not an Admin''s to manage, and the rest as theirs');

  -- 2. The same as a signed-in login, with the database's row rules on
  v := pg_temp.try_login(format('update public.profiles set role = %L where id = %L', 'staff', own));
  perform pg_temp.check(v = c_admin, '2a through the API an Admin still cannot step an Owner down: ' || v);
  v := pg_temp.try_login(format('update public.profiles set role = %L where id = %L', 'owner', stf));
  perform pg_temp.check(v = c_admin, '2b nor make anyone an Owner: ' || v);
  v := pg_temp.try_login(format('with u as (update public.profiles set role = %L where id = %L returning 1) select count(*) from u', 'manager', stf2));
  perform pg_temp.check(v = 'ok' and (select role from public.profiles where id = stf2) = 'manager',
    '2c and still gives other roles there: ' || v);

  -- 3. An Owner: as before
  perform pg_temp.as_user(own);
  v_roles := to_jsonb(public.assignable_roles());
  perform pg_temp.check(v_roles = '["owner","manager","inventory_manager","staff"]'::jsonb,
    '3a an Owner''s role list is unchanged: ' || v_roles::text);
  perform pg_temp.check(public.can_assign_role('owner') and public.can_assign_role('admin'),
    '3b an Owner still manages Owners and Admins');
  v := pg_temp.try(format('update public.profiles set role = %L where id = %L', 'owner', stf));
  perform pg_temp.check(v = 'ok' and (select role from public.profiles where id = stf) = 'owner',
    '3c an Owner makes a member of staff an Owner: ' || v);
  v := pg_temp.try(format('update public.profiles set role = %L where id = %L', 'staff', stf));
  perform pg_temp.check(v = 'ok', '3d and takes it away again: ' || v);
  v := pg_temp.try(format('update public.profiles set is_active = false where id = %L', own2));
  perform pg_temp.check(v = 'ok', '3e an Owner switches another Owner off: ' || v);
  v := pg_temp.try(format('update public.profiles set is_active = true where id = %L', own2));
  perform pg_temp.check(v = 'ok', '3f and on again: ' || v);
  v := pg_temp.try(format('update public.profiles set role = %L where id = %L', 'manager', own));
  perform pg_temp.check(v = 'You cannot change your own role.', '3g an Owner still cannot change their own role: ' || v);

  -- 4. A Manager: the same answers as before
  perform pg_temp.as_user(mgr);
  v := pg_temp.try(format('update public.profiles set role = %L where id = %L', 'owner', stf));
  perform pg_temp.check(v = 'A Manager may only assign the Inventory Manager or Staff role.',
    '4a a Manager still cannot make an Owner, with the same answer: ' || v);
  v := pg_temp.try(format('update public.profiles set is_active = false where id = %L', own));
  perform pg_temp.check(v = 'A Manager may only activate or deactivate Inventory Managers and Staff.',
    '4b a Manager still cannot switch an Owner off, with the same answer: ' || v);

  -- 5. The last active Owner. The server (no signed-in user) switches every other
  -- active Owner in this database off first, inside this rolled-back transaction.
  perform pg_temp.as_server();
  update public.profiles set is_active = false
   where role = 'owner' and is_active and deleted_at is null
     and coalesce(invitation_status, 'accepted') = 'accepted' and id <> own;
  perform pg_temp.check((select count(*) from public.profiles where role = 'owner' and is_active and deleted_at is null
                           and coalesce(invitation_status, 'accepted') = 'accepted') = 1,
    '5a one active Owner is left');
  v := pg_temp.try(format('update public.profiles set is_active = false where id = %L', own));
  perform pg_temp.check(v = c_last, '5b the server cannot switch the last Owner off: ' || v);
  v := pg_temp.try(format('update public.profiles set role = %L where id = %L', 'manager', own));
  perform pg_temp.check(v = c_last, '5c nor take the role away: ' || v);
  v := pg_temp.try(format('update public.profiles set deleted_at = now() where id = %L', own));
  perform pg_temp.check(v = c_last, '5d nor remove them: ' || v);
  v := pg_temp.try(format('update public.profiles set invitation_status = %L where id = %L', 'cancelled', own));
  perform pg_temp.check(v = c_last, '5e nor cancel their invitation: ' || v);
  perform set_config('energia.profile_privilege_change', 'on', true);
  perform pg_temp.as_user(own2);
  v := pg_temp.try(format('update public.profiles set is_active = false where id = %L', own));
  perform set_config('energia.profile_privilege_change', '', true);
  perform pg_temp.check(v = c_last, '5f nor a server function that declared its intent: ' || v);
  perform pg_temp.as_user(adm);
  v := pg_temp.try(format('update public.profiles set is_active = false where id = %L', own));
  perform pg_temp.check(v = c_last, '5g nor an Admin: ' || v);
  perform pg_temp.as_server();
  v := pg_temp.try(format('update public.profiles set full_name = %L where id = %L', 'L512 Owner (renamed)', own));
  perform pg_temp.check(v = 'ok', '5h the last Owner''s name can still be changed: ' || v);
  v := pg_temp.try(format('update public.profiles set role = %L where id = %L', 'staff', was_own));
  perform pg_temp.check(v = 'ok', '5i an Owner who is switched off is not the last active one: ' || v);
  perform pg_temp.check((select role = 'owner' and is_active and deleted_at is null from public.profiles where id = own),
    '5j the last Owner is still an active Owner');

  -- 6. Two at once: one statement switching both Owners off is refused whole,
  -- whichever row it reaches first.
  update public.profiles set is_active = true where id = own2;
  v := pg_temp.try(format('update public.profiles set is_active = false where id in (%L, %L)', own, own2));
  perform pg_temp.check(v = c_last, '6a switching the last two Owners off together is refused: ' || v);
  perform pg_temp.check((select count(*) from public.profiles where id in (own, own2) and is_active) = 2,
    '6b and both are still on');

  -- 7. Someone else first, then the last one may step down
  perform pg_temp.as_user(own);
  update public.profiles set is_active = false where id = own2;
  v := pg_temp.try(format('update public.profiles set role = %L where id = %L', 'owner', stf));
  perform pg_temp.check(v = 'ok', '7a the last Owner makes someone else an Owner: ' || v);
  perform pg_temp.as_user(stf);
  v := pg_temp.try(format('update public.profiles set role = %L where id = %L', 'manager', own));
  perform pg_temp.check(v = 'ok' and (select role from public.profiles where id = own) = 'manager',
    '7b who may then step the first one down: ' || v);
end $$;

-- 8. The three functions are 512's, with their grants as before
select pg_temp.check(md5(pg_get_functiondef('public.trg_guard_profile_privileges()'::regprocedure)) = '7a45127fc3f23b627285a6c5f90dbb6d'
                     and md5(pg_get_functiondef('public.assignable_roles()'::regprocedure)) = '3cf14cf4e4b06a7aa9f09c3f809eb12d'
                     and md5(pg_get_functiondef('public.can_assign_role(user_role)'::regprocedure)) = 'b97c2bf355c585bb7c246c2678c253d2',
  '8a the guard, assignable_roles() and can_assign_role() are 512''s');
select pg_temp.check(has_function_privilege('authenticated', 'public.assignable_roles()', 'execute')
                     and not has_function_privilege('authenticated', 'public.can_assign_role(user_role)', 'execute')
                     and not has_function_privilege('anon', 'public.trg_guard_profile_privileges()', 'execute'),
  '8b grants as before');
rollback;
