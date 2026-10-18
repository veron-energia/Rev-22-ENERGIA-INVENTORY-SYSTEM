-- Invitations can start again; Admin is no longer given (429).
--
-- ADMIN-AUTH-7: a cancelled person could never be invited again, an
-- invitation whose set-up never finished was invisible and, resent, would have
-- been accepted with no profile behind it. ADMIN-AUTH-15 (the Owner, 9 Oct
-- 2026, Q13 A): the Admin role is no longer given to new staff.
--
--   1. Cancelling removes a never-accepted invitee's profile (a deleted date):
--      Users & Roles stops listing it and its login stays blocked (412).
--   2. The same address can be invited again. The old login is offered for
--      reuse (invite_user_reusable_login); setting it up puts the profile back
--      as the new invitation's (pending, its stores only) and lifts the block
--      412 placed, so the new link works; accepting picks the pending
--      invitation, not the cancelled one.
--   3. An invitation whose set-up never finished: listed for its
--      administrator (user_admin_orphan_invitations); a login made for it is
--      offered for reuse; accepting it before it is set up is refused ("not
--      finished") and leaves it pending; once set up it is accepted.
--   4. A login that is someone else's (a member of staff's, an affiliate's, a
--      login with no invitation behind it) is never offered and never made an
--      invitee.
--   5. The resend answers say what to do now.
--   6. Admin: not offered, refused when invited or given, and an existing
--      Admin can still be managed by an Owner.
--   7. Grants and the catalogue.
--   8. Cancelling leaves alone a profile that is not an invitee's (an older
--      member of staff's, or an accepted one). Accepting needs the invitation
--      tied to the login and its pending profile in place: an orphan whose
--      login has a pending profile, or a tie to a removed profile, is "not
--      finished".
--   9. A member of staff who was removed is invited again (the Owner, 10 Oct
--      2026): their login is reused, what their profile was is kept in the
--      audit log, the block 412 placed is lifted when the invitation is set
--      up, accepting switches them on, and their history stays with the same
--      login. A Manager may invite a removed member of Staff again but not a
--      removed Manager; an Owner may. Cancelling such an invitation removes
--      and blocks them again, and they can be invited once more; a cancelled
--      invitation of a removed Manager does not let a Manager invite them,
--      and a Manager may invite again a cancelled invitee who was invited as
--      Staff but not one invited as a Manager. A live member of staff's
--      address is still "in use".
--
-- It needs a database with production's schema, 406, 407 and 412 to 429
-- applied, or 429 given as the prelude:
--   psql -v prelude=supabase/429_users_invitations_and_payment_methods.sql -f this
-- Disposable database only; everything is rolled back. Fixture logins are
-- made-up addresses @sig.invalid, names "429T ...", phones ACMA fictional
-- numbers (+61 491 57x xxx); nothing real is read or printed.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif
do $$
begin
  if to_regprocedure('public.invite_user_reusable_login(uuid)') is null
     or md5(pg_get_functiondef('public.invite_user_provisioned(uuid,uuid)'::regprocedure)) <> '7219cae03a5a758402e79762baf46f42' then
    raise exception '429 is not in this database: run with -v prelude=supabase/429_users_invitations_and_payment_methods.sql (see the header)'; end if;
end $$;

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end$$;

create temp table fx(k text primary key, id uuid not null);
create function pg_temp.fx(p text) returns uuid language sql as $f$ select id from fx where k = p $f$;
create temp table out(k text primary key, v jsonb);
create function pg_temp.out(p text) returns jsonb language sql as $f$ select v from out where k = p $f$;

-- Run p_sql as a fixture login (a signed-in browser), the anon key ('anon'),
-- the service role ('service') or the server ('server'), require the answer
-- p_expect ('ok' or a SQLSTATE), and keep the jsonb it returns under p_keep.
create function pg_temp.run(p_who text, p_sql text, p_expect text, p_label text, p_keep text default null)
returns void language plpgsql as $f$
declare v_state text := 'ok'; v_msg text; r record; v_ret jsonb;
begin
  for r in select k, id from fx loop
    p_sql := replace(p_sql, format('pg_temp.fx(%L)', r.k), format('%L::uuid', r.id));
  end loop;
  begin
    if p_who = 'server' then
      perform set_config('request.jwt.claims', '', true);
    elsif p_who = 'anon' then
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
      execute 'set local role anon';
    elsif p_who = 'service' then
      perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
      execute 'set local role service_role';
    else
      perform set_config('request.jwt.claims',
        json_build_object('sub', pg_temp.fx(p_who), 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    perform set_config('energia.profile_privilege_change', '', true);
    execute p_sql into v_ret;
    execute 'reset role';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    execute 'reset role';
  end;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('energia.profile_privilege_change', '', true);
  if v_state is distinct from p_expect then
    raise exception 'FAIL: % (expected %, got % %)', p_label, p_expect, v_state, coalesce(v_msg, ''); end if;
  if p_keep is not null then
    insert into out values (p_keep, v_ret) on conflict (k) do update set v = excluded.v;
  end if;
  raise notice 'PASS  %', p_label;
end $f$;

create function pg_temp.inv(p_request text) returns uuid language sql as
  $f$ select id from public.user_invitations where request_id = p_request $f$;
create function pg_temp.ban(p text) returns timestamptz language sql as
  $f$ select banned_until from auth.users where id = pg_temp.fx(p) $f$;
create function pg_temp.blocked_100y(p text) returns boolean language sql as
  $f$ select b is not null and isfinite(b) and b between now() + interval '99 years' and now() + interval '101 years'
        from (select pg_temp.ban(p) b) x $f$;
create function pg_temp.sessions(p text) returns int language sql as
  $f$ select count(*)::int from auth.sessions where user_id = pg_temp.fx(p) $f$;
create function pg_temp.stores(p text) returns text language sql as
  $f$ select coalesce(string_agg(s.name, ',' order by s.name), '') from public.user_store_assignments a
        join public.stores s on s.id = a.store_id where a.user_id = pg_temp.fx(p) $f$;
create function pg_temp.listed(p_who text, p text) returns void language plpgsql as $f$
begin
  perform pg_temp.run(p_who, format($q$select to_jsonb(x) from public.user_admin_list() x where x.user_id = %L$q$, pg_temp.fx(p)),
                      'ok', format('list: %s opens Users & Roles', p_who), 'list_' || p_who || '_' || p);
end $f$;
-- The invitation helpers as admin-invite-user asks them: begin as the
-- signed-in administrator, the rest with the service role.
create function pg_temp.begin_as(p_who text, p_request text, p_email text, p_role text, p_stores text default '{}',
                                 p_label text default null) returns void language plpgsql as $f$
begin
  perform pg_temp.run(p_who, format($q$select public.invite_user_begin(%L, %L, '429T ' || %L, %L,
      '+61491570737', '+61491572983', '429t-personal@sig.invalid', %L::uuid[])$q$, p_request, p_email, p_request, p_role, p_stores),
    'ok', coalesce(p_label, format('begin: %s invites %s as %s', p_who, p_email, p_role)), p_request);
end $f$;

-- ── Fixture (written as the server would) ────────────────────────────────────
do $$
declare k text; v uuid; v_cust uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  foreach k in array array['owner','manager','staff','admin','affiliate','again_login','orphan_login','plain_login',
                           'owner_orphan_login','legacy_login','accepted_login','removed_tie_login',
                           'pending_orphan_login','removed_legacy','removed_accepted','removed_manager'] loop
    insert into auth.users (id, email) values (gen_random_uuid(), '429t-' || k || '@sig.invalid') returning id into v;
    insert into fx values (k, v);
  end loop;
  -- A login the 'invite' link made for an invitation whose set-up never finished.
  update auth.users set raw_user_meta_data = '{"full_name":"429T orphan","invited_to":"energia_internal"}'
   where id in (pg_temp.fx('orphan_login'), pg_temp.fx('owner_orphan_login'));
  insert into public.profiles (id, full_name, email, role, is_active, invitation_status)
  select fx.id, '429T ' || fx.k, '429t-' || fx.k || '@sig.invalid', x.role::public.user_role, true, x.inv
    from fx join (values ('owner','owner',null), ('manager','manager','accepted'), ('staff','staff','accepted'),
                         ('admin','admin','accepted')) x(k, role, inv) on x.k = fx.k;
  insert into public.customers (full_name, phone) values ('429T Affiliate', '+61491573770') returning id into v_cust;
  insert into public.affiliate_accounts (auth_user_id, customer_id, status) values (pg_temp.fx('affiliate'), v_cust, 'claimed');
  insert into public.stores (name, code) values ('429T Store A', '429TA') returning id into v;
  insert into fx values ('store_a', v);
  insert into public.stores (name, code) values ('429T Store B', '429TB') returning id into v;
  insert into fx values ('store_b', v);
  insert into public.user_store_assignments (user_id, store_id)
  values (pg_temp.fx('manager'), pg_temp.fx('store_a')), (pg_temp.fx('manager'), pg_temp.fx('store_b'));
end $$;

-- ── 1. Cancelling removes the invitee's profile ──────────────────────────────
select pg_temp.begin_as('owner', '429t-req-1', '429t-again_login@sig.invalid', 'staff',
                        format('{%s}', pg_temp.fx('store_a')));
select pg_temp.check(pg_temp.out('429t-req-1')->>'outcome' = 'created', 'first: an Owner invites a new address');
-- A day earlier, as it would be: everything here runs at one transaction time.
update public.user_invitations set invited_at = invited_at - interval '1 day' where request_id = '429t-req-1';
select pg_temp.run('service', $q$select to_jsonb(public.invite_user_reusable_login(
    (select id from public.user_invitations where request_id = '429t-req-1')))$q$, 'ok',
  'first: the Edge Function asks for a login to reuse', 'reuse0');
select pg_temp.check(pg_temp.out('reuse0') is null,
  'first: a plain login with that address that no invitation made is not offered');
select pg_temp.run('service', $q$select public.invite_user_provisioned(
    (select id from public.user_invitations where request_id = '429t-req-1'), pg_temp.fx('again_login'))$q$, 'ok',
  'first: then ties the login Supabase Auth made', 'prov1');
insert into auth.sessions (id, user_id, created_at, updated_at) values (gen_random_uuid(), pg_temp.fx('again_login'), now(), now());
select pg_temp.check(pg_temp.out('prov1')->>'outcome' = 'provisioned' and pg_temp.ban('again_login') is null
                     and pg_temp.stores('again_login') = '429T Store A',
  'first: a pending profile with Store A; the login is left alone (they sign in from the link)');
select pg_temp.run('owner', $q$select public.invite_user_cancel(
    (select id from public.user_invitations where request_id = '429t-req-1'), '429 test')$q$, 'ok',
  'cancel: the Owner cancels it', 'cancel1');
select pg_temp.check(pg_temp.out('cancel1')->>'outcome' = 'cancelled'
                     and exists (select 1 from public.profiles p where p.id = pg_temp.fx('again_login')
                                  and p.deleted_at is not null and p.invitation_status = 'cancelled' and not p.is_active),
  'cancel: the profile is cancelled and removed (a deleted date)');
select pg_temp.check(pg_temp.sessions('again_login') = 0 and pg_temp.blocked_100y('again_login')
                     and (select reason from public.staff_login_blocks where user_id = pg_temp.fx('again_login')) = 'invitation_cancelled',
  'cancel: the login is signed out and blocked, recorded as a cancelled invitation (412)');
select pg_temp.listed('owner', 'again_login');
select pg_temp.check(pg_temp.out('list_owner_again_login') is null,
  'cancel: Users & Roles no longer lists the cancelled invitee');
select pg_temp.run('owner', $q$select public.invite_user_cancel(
    (select id from public.user_invitations where request_id = '429t-req-1'), 'again')$q$, 'ok',
  'cancel: a second cancel', 'cancel1b');
select pg_temp.check(pg_temp.out('cancel1b')->>'outcome' = 'already_cancelled', 'cancel: is answered as before');
select pg_temp.run('owner', $q$select public.invite_user_prepare_resend(
    (select id from public.user_invitations where request_id = '429t-req-1'))$q$, 'ok',
  'cancel: Resend on the cancelled invitation', 'resend_cancelled');
select pg_temp.check(pg_temp.out('resend_cancelled')->>'message'
                       = 'This invitation was cancelled. Use Invite User to invite them again if they still need access.',
  'cancel: the refusal says to invite them again (it said "Create a new one", which was impossible)');

-- ── 2. The same address is invited again ─────────────────────────────────────
select pg_temp.begin_as('owner', '429t-req-2', ' 429T-Again_Login@SIG.invalid ', 'inventory_manager',
                        format('{%s}', pg_temp.fx('store_b')), 'again: the Owner invites the same address again, in other letters');
select pg_temp.check(pg_temp.out('429t-req-2')->>'outcome' = 'created',
  'again: it is recorded (before 429: "already belongs to a user")');
select pg_temp.run('service', $q$select to_jsonb(public.invite_user_reusable_login(
    (select id from public.user_invitations where request_id = '429t-req-2')))$q$, 'ok',
  'again: the Edge Function asks for a login to reuse', 'reuse2');
select pg_temp.check(pg_temp.out('reuse2') = to_jsonb(pg_temp.fx('again_login')),
  'again: the cancelled invitee''s own login is offered');
select pg_temp.run('service', $q$select public.invite_user_provisioned(
    (select id from public.user_invitations where request_id = '429t-req-2'), pg_temp.fx('again_login'))$q$, 'ok',
  'again: the Edge Function sets that login up before making the link', 'prov2');
select pg_temp.check(pg_temp.out('prov2')->>'outcome' = 'provisioned'
                     and exists (select 1 from public.profiles p where p.id = pg_temp.fx('again_login') and p.deleted_at is null
                                  and p.invitation_status = 'pending' and not p.is_active and p.role = 'inventory_manager'
                                  and p.full_name = '429T 429t-req-2'),
  'again: the profile is put back as the new invitation''s: pending, off, not removed, its role and name');
select pg_temp.check(pg_temp.stores('again_login') = '429T Store B',
  'again: with the new invitation''s stores only (Store A from the cancelled one is gone)');
select pg_temp.check(pg_temp.ban('again_login') is null
                     and not exists (select 1 from public.staff_login_blocks where user_id = pg_temp.fx('again_login'))
                     and exists (select 1 from public.audit_logs a where a.record_id = pg_temp.fx('again_login')
                                  and a.action = 'staff_login_unblocked'),
  'again: the block 412 placed is lifted (pending invitees are not blocked), with an audit row');
select pg_temp.check((select public.staff_login_sync(pg_temp.fx('again_login'))) = 'pending',
  'again: a second sync changes nothing');
select pg_temp.listed('owner', 'again_login');
select pg_temp.check(pg_temp.out('list_owner_again_login')->>'state' = 'pending_invitation'
                     and pg_temp.out('list_owner_again_login')->>'invitation_id' = pg_temp.inv('429t-req-2')::text,
  'again: Users & Roles lists them as a pending invitation, the new one');
select pg_temp.run('owner', $q$select public.invite_user_prepare_resend(
    (select id from public.user_invitations where request_id = '429t-req-2'))$q$, 'ok',
  'again: Resend', 'resend2');
select pg_temp.check(pg_temp.out('resend2')->>'outcome' = 'ok'
                     and pg_temp.out('resend2')->>'auth_user_id' = pg_temp.fx('again_login')::text,
  'again: can be resent, with the login tied');
select pg_temp.run('service', $q$select public.invite_user_accept(pg_temp.fx('again_login'), '429t-again_login@sig.invalid')$q$, 'ok',
  'again: they accept from the new link', 'accept2');
select pg_temp.check((pg_temp.out('accept2')->>'activated')::boolean
                     and (select status from public.user_invitations where id = pg_temp.inv('429t-req-2')) = 'accepted'
                     and (select status from public.user_invitations where id = pg_temp.inv('429t-req-1')) = 'cancelled'
                     and exists (select 1 from public.profiles p where p.id = pg_temp.fx('again_login') and p.is_active
                                  and p.invitation_status = 'accepted' and p.deleted_at is null)
                     and pg_temp.ban('again_login') is null,
  'again: the pending invitation is the one accepted (the login has two), and they are in');

-- ── 3. An invitation whose set-up never finished ─────────────────────────────
select pg_temp.begin_as('manager', '429t-req-3', '429t-orphan_login@sig.invalid', 'staff',
                        format('{%s}', pg_temp.fx('store_a')), 'orphan: a Manager invites Staff');
select pg_temp.begin_as('owner', '429t-req-4', '429t-owner_orphan_login@sig.invalid', 'owner', '{}',
                        'orphan: an Owner invites another Owner');
select pg_temp.run('owner', $q$select coalesce(jsonb_agg(to_jsonb(x) order by x.email), '[]') from public.user_admin_orphan_invitations() x
    where x.email like '429t-%'$q$, 'ok', 'orphan: the Owner opens Users & Roles', 'orph_owner');
select pg_temp.run('manager', $q$select coalesce(jsonb_agg(to_jsonb(x) order by x.email), '[]') from public.user_admin_orphan_invitations() x
    where x.email like '429t-%'$q$, 'ok', 'orphan: the Manager opens Users & Roles', 'orph_manager');
select pg_temp.check(jsonb_array_length(pg_temp.out('orph_owner')) = 2
                     and pg_temp.out('orph_owner')->0->>'email' = '429t-orphan_login@sig.invalid'
                     and pg_temp.out('orph_owner')->0->>'role' = 'staff',
  'orphan: the Owner sees both unfinished invitations (they were invisible before 429)');
select pg_temp.check(jsonb_array_length(pg_temp.out('orph_manager')) = 1
                     and pg_temp.out('orph_manager')->0->>'email' = '429t-orphan_login@sig.invalid',
  'orphan: the Manager sees only the one they may manage');
select pg_temp.run(w, $q$select count(*) from public.user_admin_orphan_invitations()$q$, '42501',
                   'orphan: ' || w || ' cannot read the list')
  from unnest(array['staff', 'affiliate', 'anon']) w;
select pg_temp.run('service', $q$select to_jsonb(public.invite_user_reusable_login(
    (select id from public.user_invitations where request_id = '429t-req-3')))$q$, 'ok',
  'orphan: Resend asks for a login to reuse', 'reuse3');
select pg_temp.check(pg_temp.out('reuse3') = to_jsonb(pg_temp.fx('orphan_login')),
  'orphan: the login the earlier attempt made (no profile, made by an invitation) is offered');
select pg_temp.run('service', $q$select public.invite_user_accept(pg_temp.fx('orphan_login'), '429t-orphan_login@sig.invalid')$q$, 'ok',
  'orphan: its link is used before it is set up', 'accept3');
select pg_temp.check(pg_temp.out('accept3')->>'reason' = 'not_set_up'
                     and (pg_temp.out('accept3')->>'activated')::boolean = false
                     and (select status from public.user_invitations where id = pg_temp.inv('429t-req-3')) = 'pending'
                     and not exists (select 1 from public.profiles where id = pg_temp.fx('orphan_login')),
  'orphan: refused as not finished, and the invitation stays pending (before 429 it was marked accepted with no profile)');
select pg_temp.run('service', $q$select public.invite_user_provisioned(
    (select id from public.user_invitations where request_id = '429t-req-3'), pg_temp.fx('orphan_login'))$q$, 'ok',
  'orphan: Resend sets the login up first', 'prov3');
select pg_temp.run('service', $q$select public.invite_user_accept(pg_temp.fx('orphan_login'), '429t-orphan_login@sig.invalid')$q$, 'ok',
  'orphan: then they accept', 'accept3b');
select pg_temp.check(pg_temp.out('prov3')->>'outcome' = 'provisioned' and (pg_temp.out('accept3b')->>'activated')::boolean
                     and pg_temp.stores('orphan_login') = '429T Store A',
  'orphan: set up and accepted, with its store');

-- ── 4. A login that is someone else's ────────────────────────────────────────
-- The affiliate's login carries the mark an invitation's link leaves, so only
-- its affiliate account keeps it from being offered.
update auth.users set raw_user_meta_data = '{"invited_to":"energia_internal"}' where id = pg_temp.fx('affiliate');
insert into public.user_invitations (request_id, email, email_normalized, full_name, role, invited_by)
values ('429t-req-staff', '429t-staff@sig.invalid', '429t-staff@sig.invalid', '429T x', 'staff', pg_temp.fx('owner')),
       ('429t-req-aff', '429t-affiliate@sig.invalid', '429t-affiliate@sig.invalid', '429T y', 'staff', pg_temp.fx('owner')),
       ('429t-req-plain', '429t-plain_login@sig.invalid', '429t-plain_login@sig.invalid', '429T z', 'staff', pg_temp.fx('owner'));
select pg_temp.run('service', $q$select jsonb_build_array(
    public.invite_user_reusable_login((select id from public.user_invitations where request_id = '429t-req-staff')),
    public.invite_user_reusable_login((select id from public.user_invitations where request_id = '429t-req-aff')),
    public.invite_user_reusable_login((select id from public.user_invitations where request_id = '429t-req-plain')))$q$, 'ok',
  'other: the server asks for logins to reuse for a member of staff''s, an affiliate''s and a plain login''s address', 'reuse_other');
select pg_temp.check(pg_temp.out('reuse_other') = '[null, null, null]'::jsonb, 'other: none of them is offered');
create temp table before_state as select p::text t from public.profiles p where p.id in (pg_temp.fx('staff'), pg_temp.fx('affiliate'));
select pg_temp.run('service', $q$select jsonb_build_array(
    public.invite_user_provisioned((select id from public.user_invitations where request_id = '429t-req-staff'), pg_temp.fx('staff')),
    public.invite_user_provisioned((select id from public.user_invitations where request_id = '429t-req-aff'), pg_temp.fx('affiliate')))$q$,
  'ok', 'other: the server is asked to make them invitees anyway', 'prov_other');
select pg_temp.check(pg_temp.out('prov_other')->0->>'outcome' = 'login_in_use'
                     and pg_temp.out('prov_other')->1->>'outcome' = 'login_in_use'
                     and (select string_agg(p::text, '|' order by p.id) from public.profiles p
                           where p.id in (pg_temp.fx('staff'), pg_temp.fx('affiliate')))
                         = (select string_agg(t, '|' order by t) from before_state)
                     and not exists (select 1 from public.profiles where id = pg_temp.fx('affiliate'))
                     and not exists (select 1 from public.user_invitations where request_id in ('429t-req-staff', '429t-req-aff')
                                      and auth_user_id is not null),
  'other: answered "login in use": the member of staff''s profile is unchanged, the affiliate gets none, nothing is tied');

-- ── 5. Resend wording ────────────────────────────────────────────────────────
update public.user_invitations set resend_count = 10 where id = pg_temp.inv('429t-req-4');
select pg_temp.run('owner', $q$select public.invite_user_prepare_resend(
    (select id from public.user_invitations where request_id = '429t-req-4'))$q$, 'ok',
  'resend: an invitation resent ten times', 'resend_many');
select pg_temp.check(pg_temp.out('resend_many')->>'message'
                       = 'This invitation has been resent too many times. Cancel it, then use Invite User to invite them again.',
  'resend: says to cancel it and invite them again, which now works');

-- ── 6. Admin is no longer given ──────────────────────────────────────────────
select pg_temp.begin_as('owner', '429t-req-admin', '429t-new-admin@sig.invalid', 'admin');
select pg_temp.begin_as('manager', '429t-req-admin2', '429t-new-admin2@sig.invalid', 'admin');
select pg_temp.check(pg_temp.out('429t-req-admin')->>'outcome' = 'forbidden'
                     and pg_temp.out('429t-req-admin')->>'field' = 'role'
                     and pg_temp.out('429t-req-admin')->>'message' like 'The Admin role is no longer given%'
                     and pg_temp.out('429t-req-admin2')->>'outcome' = 'forbidden'
                     and pg_temp.inv('429t-req-admin') is null and pg_temp.inv('429t-req-admin2') is null,
  'admin: an Owner and a Manager are refused when inviting an Admin, and nothing is recorded');
select pg_temp.run('owner', $q$select to_jsonb(public.assignable_roles())$q$, 'ok', 'admin: the Owner''s role list', 'roles_owner');
select pg_temp.run('manager', $q$select to_jsonb(public.assignable_roles())$q$, 'ok', 'admin: the Manager''s role list', 'roles_manager');
select pg_temp.run('admin', $q$select to_jsonb(public.assignable_roles())$q$, 'ok', 'admin: an Admin''s role list', 'roles_admin');
select pg_temp.check(pg_temp.out('roles_owner') = '["owner","manager","inventory_manager","staff"]'::jsonb
                     and pg_temp.out('roles_admin') = '["owner","manager","inventory_manager","staff"]'::jsonb
                     and pg_temp.out('roles_manager') = '["inventory_manager","staff"]'::jsonb,
  'admin: no role list offers Admin; a Manager''s list is unchanged');
select pg_temp.listed('owner', 'admin');
select pg_temp.listed('manager', 'admin');
select pg_temp.listed('manager', 'staff');
select pg_temp.check((pg_temp.out('list_owner_admin')->>'can_manage')::boolean
                     and not (pg_temp.out('list_manager_admin')->>'can_manage')::boolean
                     and (pg_temp.out('list_manager_staff')->>'can_manage')::boolean,
  'admin: an Owner can still manage someone who has the Admin role; a Manager still cannot; a Manager still manages Staff');
select pg_temp.run('owner', $q$update public.profiles set role = 'admin' where id = pg_temp.fx('staff') returning to_jsonb(role)$q$, '42501',
  'admin: an Owner cannot give the Admin role on Users & Roles');
select pg_temp.run('owner', $q$update public.profiles set role = 'manager', updated_at = now() where id = pg_temp.fx('admin') returning to_jsonb(role)$q$, 'ok',
  'admin: an Owner can change an Admin''s role');
select pg_temp.check((select role from public.profiles where id = pg_temp.fx('admin')) = 'manager'
                     and (select role from public.profiles where id = pg_temp.fx('staff')) = 'staff',
  'admin: the Admin is now a Manager; the member of staff is unchanged');
select pg_temp.run('manager', $q$update public.profiles set role = 'inventory_manager' where id = pg_temp.fx('staff') returning to_jsonb(role)$q$, 'ok',
  'admin: a Manager still moves Staff to Inventory Manager');

-- ── 7. Grants and the catalogue ──────────────────────────────────────────────
select pg_temp.run(w, $q$select public.invite_user_reusable_login(gen_random_uuid())$q$, '42501',
                   'grants: ' || w || ' cannot call invite_user_reusable_login')
  from unnest(array['owner', 'affiliate', 'anon']) w;
select pg_temp.check(has_function_privilege('authenticated', 'public.user_admin_orphan_invitations()', 'execute')
                     and not has_function_privilege('anon', 'public.user_admin_orphan_invitations()', 'execute')
                     and not has_function_privilege('authenticated', 'public.can_assign_role(user_role)', 'execute')
                     and has_function_privilege('service_role', 'public.invite_user_reusable_login(uuid)', 'execute'),
  'grants: the orphan list is signed-in staff''s, the helpers the server''s');
select pg_temp.check((select string_agg(x.sig || '=' || md5(pg_get_functiondef(to_regprocedure('public.' || x.sig))), ' ' order by x.sig)
                        from unnest(array['invite_user_cancel(uuid,text)', 'invite_user_provisioned(uuid,uuid)',
                                          'invite_user_accept(uuid,text)', 'staff_login_sync(uuid)',
                                          'invite_user_reusable_login(uuid)',
                                          'invite_user_begin(text,text,text,user_role,text,text,text,uuid[])']) x(sig))
                     = 'invite_user_accept(uuid,text)=04eb29a50699f8f9f41d7ba591af3480 '
                       || 'invite_user_begin(text,text,text,user_role,text,text,text,uuid[])=eda7f730fd83891146265adb06eca132 '
                       || 'invite_user_cancel(uuid,text)=e9e97c330ed7189415e2f67cef9716c5 '
                       || 'invite_user_provisioned(uuid,uuid)=7219cae03a5a758402e79762baf46f42 '
                       || 'invite_user_reusable_login(uuid)=340580cff28c74eb1b1b8bde967dc8fc '
                       || 'staff_login_sync(uuid)=9259111deccca8c66e95469acfdd250f',
  'catalogue: the functions tested are 429''s');
select pg_temp.check(not exists (select 1 from auth.users u join fx on fx.id = u.id
                                  where u.banned_until is not null and not isfinite(u.banned_until)),
  'no login was ever given an infinite ban');

-- ── 8. Cancel, accept and begin at their edges ───────────────────────────────
-- Written as the server would: invitations tied to logins that are not an
-- invitee's (invite_user_provisioned refuses such a tie now; older rows or a
-- hand-made one may still have it), an orphan whose login has a pending
-- profile, a tie to a removed profile, and two removed members of staff.
insert into public.profiles (id, full_name, email, role, is_active, invitation_status, deleted_at)
select fx.id, '429T ' || fx.k, '429t-' || fx.k || '@sig.invalid', 'staff', x.active, x.inv, x.deleted
  from fx join (values ('legacy_login', true, null, null::timestamptz), ('accepted_login', true, 'accepted', null),
                       ('removed_tie_login', false, 'cancelled', now()), ('pending_orphan_login', false, 'pending', null),
                       ('removed_legacy', false, null, now()), ('removed_accepted', false, 'accepted', now())
               ) x(k, active, inv, deleted) on x.k = fx.k;
insert into public.user_invitations (request_id, email, email_normalized, full_name, role, invited_by, auth_user_id)
select '429t-req-' || x.k, '429t-' || x.k || '@sig.invalid', '429t-' || x.k || '@sig.invalid', '429T ' || x.k, 'staff',
       pg_temp.fx('owner'), case when x.tied then pg_temp.fx(x.k) end
  from (values ('legacy_login', true), ('accepted_login', true), ('removed_tie_login', true),
               ('pending_orphan_login', false)) x(k, tied);
create temp table before_cancel as
  select p.id, p::text t from public.profiles p where p.id in (pg_temp.fx('legacy_login'), pg_temp.fx('accepted_login'));
select pg_temp.run('owner', format($q$select jsonb_build_array(public.invite_user_cancel(%L, 'edge'), public.invite_user_cancel(%L, 'edge'))$q$,
    pg_temp.inv('429t-req-legacy_login'), pg_temp.inv('429t-req-accepted_login')), 'ok',
  'edge: the Owner cancels invitations tied to an older member of staff''s and an accepted login', 'cancel_edge');
select pg_temp.check(pg_temp.out('cancel_edge')->0->>'outcome' = 'cancelled'
                     and pg_temp.out('cancel_edge')->1->>'outcome' = 'cancelled'
                     and (select status from public.user_invitations where id = pg_temp.inv('429t-req-legacy_login')) = 'cancelled'
                     and (select status from public.user_invitations where id = pg_temp.inv('429t-req-accepted_login')) = 'cancelled',
  'edge: both invitations are cancelled');
select pg_temp.check((select string_agg(p::text, '|' order by p.id) from public.profiles p
                       where p.id in (pg_temp.fx('legacy_login'), pg_temp.fx('accepted_login')))
                     = (select string_agg(t, '|' order by id) from before_cancel)
                     and pg_temp.ban('legacy_login') is null and pg_temp.ban('accepted_login') is null,
  'edge: neither profile is touched (still on, not cancelled, not removed) and neither login is blocked');
select pg_temp.run('service', $q$select jsonb_build_array(
    public.invite_user_accept(pg_temp.fx('pending_orphan_login'), '429t-pending_orphan_login@sig.invalid'),
    public.invite_user_accept(pg_temp.fx('removed_tie_login'), '429t-removed_tie_login@sig.invalid'))$q$, 'ok',
  'edge: an orphan whose login has a pending profile, and a tie to a removed profile, are accepted from their links', 'accept_edge');
select pg_temp.check(pg_temp.out('accept_edge')->0->>'reason' = 'not_set_up'
                     and pg_temp.out('accept_edge')->1->>'reason' = 'not_set_up'
                     and (select status from public.user_invitations where id = pg_temp.inv('429t-req-pending_orphan_login')) = 'pending'
                     and (select status from public.user_invitations where id = pg_temp.inv('429t-req-removed_tie_login')) = 'pending'
                     and exists (select 1 from public.profiles p where p.id = pg_temp.fx('pending_orphan_login')
                                  and not p.is_active and p.invitation_status = 'pending')
                     and exists (select 1 from public.profiles p where p.id = pg_temp.fx('removed_tie_login')
                                  and not p.is_active and p.invitation_status = 'cancelled' and p.deleted_at is not null),
  'edge: both are refused as not finished; the invitations stay pending and neither profile is switched on');
-- ── 9. A removed member of staff is invited again ──────────────────────────
-- Their history: an audit entry one of them made, an invitation the other
-- accepted long ago, and a store the first worked at, all tied to their logins.
insert into public.profiles (id, full_name, email, role, is_active, invitation_status, deleted_at)
values (pg_temp.fx('removed_manager'), '429T removed_manager', '429t-removed_manager@sig.invalid', 'manager', false,
        'accepted', now());
insert into public.user_store_assignments (user_id, store_id) values (pg_temp.fx('removed_legacy'), pg_temp.fx('store_a'));
insert into public.audit_logs (table_name, record_id, action, new_data, changed_by)
values ('429t_history', gen_random_uuid(), '429t_their_work', '{}', pg_temp.fx('removed_legacy'));
insert into public.user_invitations (request_id, email, email_normalized, full_name, role, invited_by, auth_user_id,
                                     profile_id, status, invited_at, accepted_at)
values ('429t-req-long-ago', '429t-removed_accepted@sig.invalid', '429t-removed_accepted@sig.invalid', '429T long ago',
        'staff', pg_temp.fx('owner'), pg_temp.fx('removed_accepted'), pg_temp.fx('removed_accepted'), 'accepted',
        now() - interval '1 year', now() - interval '1 year');
select pg_temp.check(pg_temp.blocked_100y('removed_legacy') and pg_temp.blocked_100y('removed_accepted')
                     and pg_temp.blocked_100y('removed_manager')
                     and (select reason from public.staff_login_blocks where user_id = pg_temp.fx('removed_legacy')) = 'removed',
  'back: the removed members of staff''s logins are blocked (412, as removed)');

-- The Owner invites one back, in other letters, with another role and store.
select pg_temp.begin_as('owner', '429t-req-back1', ' 429T-Removed_Legacy@sig.invalid', 'inventory_manager',
                        format('{%s}', pg_temp.fx('store_b')),
                        'back: the Owner invites a removed member of staff again (from before invitations)');
select pg_temp.check(pg_temp.out('429t-req-back1')->>'outcome' = 'created',
  'back: it is recorded (before: refused, or saved and never sendable)');
select pg_temp.run('service', $q$select to_jsonb(public.invite_user_reusable_login(
    (select id from public.user_invitations where request_id = '429t-req-back1')))$q$, 'ok',
  'back: the Edge Function asks for a login to reuse', 'reuse_back1');
select pg_temp.check(pg_temp.out('reuse_back1') = to_jsonb(pg_temp.fx('removed_legacy')),
  'back: their own login is offered, so their history stays linked');
select pg_temp.run('service', $q$select public.invite_user_provisioned(
    (select id from public.user_invitations where request_id = '429t-req-back1'), pg_temp.fx('removed_legacy'))$q$, 'ok',
  'back: the Edge Function sets that login up before making the link', 'prov_back1');
select pg_temp.check(pg_temp.out('prov_back1')->>'outcome' = 'provisioned'
                     and exists (select 1 from public.profiles p where p.id = pg_temp.fx('removed_legacy') and p.deleted_at is null
                                  and p.invitation_status = 'pending' and not p.is_active and p.role = 'inventory_manager'
                                  and p.full_name = '429T 429t-req-back1')
                     and pg_temp.stores('removed_legacy') = '429T Store B',
  'back: their profile is the new invitation''s: pending, off, not removed, its role, name and store');
select pg_temp.check(pg_temp.ban('removed_legacy') is null
                     and not exists (select 1 from public.staff_login_blocks where user_id = pg_temp.fx('removed_legacy'))
                     and exists (select 1 from public.audit_logs a where a.record_id = pg_temp.fx('removed_legacy')
                                  and a.action = 'staff_login_unblocked' and a.old_data->>'reason' = 'removed'),
  'back: the block 412 placed when they were removed is lifted, so the link works, with an audit row');
select pg_temp.check(exists (select 1 from public.audit_logs a where a.record_id = pg_temp.fx('removed_legacy')
                              and a.table_name = 'profiles' and a.action = 'user_invitation_login_reused'
                              and a.changed_by = pg_temp.fx('owner')
                              and a.old_data->>'full_name' = '429T removed_legacy' and a.old_data->>'role' = 'staff'
                              and a.old_data->>'deleted_at' is not null and a.old_data->'invitation_status' = 'null'::jsonb
                              and a.old_data->'store_ids' = jsonb_build_array(pg_temp.fx('store_a'))
                              and a.new_data->>'invitation_id' = pg_temp.inv('429t-req-back1')::text
                              and a.new_data->>'role' = 'inventory_manager'),
  'back: what their profile was (name, role, removed date, store) is kept in the audit log, by whoever invited them');
select pg_temp.listed('owner', 'removed_legacy');
select pg_temp.check(pg_temp.out('list_owner_removed_legacy')->>'state' = 'pending_invitation',
  'back: Users & Roles lists them as a pending invitation');
select pg_temp.run('service', $q$select public.invite_user_accept(pg_temp.fx('removed_legacy'), '429t-removed_legacy@sig.invalid')$q$, 'ok',
  'back: they accept from the new link', 'accept_back1');
select pg_temp.check((pg_temp.out('accept_back1')->>'activated')::boolean
                     and exists (select 1 from public.profiles p where p.id = pg_temp.fx('removed_legacy') and p.is_active
                                  and p.invitation_status = 'accepted' and p.deleted_at is null)
                     and pg_temp.ban('removed_legacy') is null
                     and (select status from public.user_invitations where id = pg_temp.inv('429t-req-back1')) = 'accepted',
  'back: accepting switches them on, unblocked');
select pg_temp.check(exists (select 1 from public.audit_logs a where a.action = '429t_their_work'
                              and a.changed_by = pg_temp.fx('removed_legacy')),
  'back: what they did before is still theirs (the same login and profile)');

-- A Manager invites a removed member of Staff back, cancels, and the Owner
-- invites them once more.
select pg_temp.begin_as('manager', '429t-req-back2', '429t-removed_accepted@sig.invalid', 'staff', '{}',
                        'back: a Manager invites a removed member of Staff again');
select pg_temp.run('service', $q$select public.invite_user_provisioned(
    (select id from public.user_invitations where request_id = '429t-req-back2'),
    public.invite_user_reusable_login((select id from public.user_invitations where request_id = '429t-req-back2')))$q$, 'ok',
  'back: the Edge Function sets their login up', 'prov_back2');
select pg_temp.check(pg_temp.out('429t-req-back2')->>'outcome' = 'created'
                     and pg_temp.out('prov_back2')->>'outcome' = 'provisioned'
                     and (select auth_user_id from public.user_invitations where id = pg_temp.inv('429t-req-back2')) = pg_temp.fx('removed_accepted')
                     and pg_temp.ban('removed_accepted') is null,
  'back: a Manager may (Staff is a role they manage); their login is reused and unblocked');
select pg_temp.run('manager', $q$select public.invite_user_cancel(
    (select id from public.user_invitations where request_id = '429t-req-back2'), '429 test')$q$, 'ok',
  'back: the Manager cancels it', 'cancel_back2');
select pg_temp.check(pg_temp.out('cancel_back2')->>'outcome' = 'cancelled'
                     and exists (select 1 from public.profiles p where p.id = pg_temp.fx('removed_accepted')
                                  and p.deleted_at is not null and p.invitation_status = 'cancelled' and not p.is_active)
                     and pg_temp.blocked_100y('removed_accepted')
                     and (select status from public.user_invitations where id = pg_temp.inv('429t-req-long-ago')) = 'accepted',
  'back: they are removed and blocked again; the invitation they accepted long ago is untouched');
select pg_temp.begin_as('owner', '429t-req-back3', '429t-removed_accepted@sig.invalid', 'staff', '{}',
                        'back: the Owner invites them once more');
select pg_temp.run('service', $q$select public.invite_user_provisioned(
    (select id from public.user_invitations where request_id = '429t-req-back3'),
    public.invite_user_reusable_login((select id from public.user_invitations where request_id = '429t-req-back3')))$q$, 'ok',
  'back: set up again', 'prov_back3');
select pg_temp.run('service', $q$select public.invite_user_accept(pg_temp.fx('removed_accepted'), '429t-removed_accepted@sig.invalid')$q$, 'ok',
  'back: they accept', 'accept_back3');
select pg_temp.check(pg_temp.out('prov_back3')->>'outcome' = 'provisioned'
                     and (pg_temp.out('accept_back3')->>'activated')::boolean
                     and (select status from public.user_invitations where id = pg_temp.inv('429t-req-back3')) = 'accepted'
                     and (select status from public.user_invitations where id = pg_temp.inv('429t-req-back2')) = 'cancelled'
                     and (select status from public.user_invitations where id = pg_temp.inv('429t-req-long-ago')) = 'accepted'
                     and exists (select 1 from public.profiles p where p.id = pg_temp.fx('removed_accepted') and p.is_active
                                  and p.invitation_status = 'accepted' and p.deleted_at is null)
                     and pg_temp.ban('removed_accepted') is null
                     and (select count(*) from public.audit_logs a where a.record_id = pg_temp.fx('removed_accepted')
                           and a.action = 'user_invitation_login_reused') = 2,
  'back: the pending invitation is the one accepted (the login has three); each reuse is in the audit log');

-- A removed Manager: not a Manager's to invite back; an Owner's.
select pg_temp.begin_as('manager', '429t-req-back4', '429t-removed_manager@sig.invalid', 'staff', '{}',
                        'back: a Manager invites a removed Manager again, as Staff');
select pg_temp.check(pg_temp.out('429t-req-back4')->>'outcome' = 'forbidden'
                     and pg_temp.out('429t-req-back4')->>'scope' = 'removed_staff'
                     and pg_temp.out('429t-req-back4')->>'message' like 'This person was removed from Users & Roles, or their invitation was cancelled. Your role may not manage the role they have.%'
                     and pg_temp.inv('429t-req-back4') is null
                     and exists (select 1 from public.profiles p where p.id = pg_temp.fx('removed_manager')
                                  and p.role = 'manager' and p.deleted_at is not null)
                     and pg_temp.blocked_100y('removed_manager'),
  'back: refused, nothing saved, their profile and block untouched (a Manager cannot manage a Manager)');
select pg_temp.begin_as('owner', '429t-req-back5', '429t-removed_manager@sig.invalid', 'manager', '{}',
                        'back: the Owner invites the removed Manager again');
select pg_temp.check(pg_temp.out('429t-req-back5')->>'outcome' = 'created',
  'back: an Owner may');
-- The Owner's invitation is set up, then cancelled: the profile is a
-- cancelled Manager's. A Manager still may not invite them back.
select pg_temp.run('service', $q$select public.invite_user_provisioned(
    (select id from public.user_invitations where request_id = '429t-req-back5'),
    public.invite_user_reusable_login((select id from public.user_invitations where request_id = '429t-req-back5')))$q$, 'ok',
  'back: the Edge Function sets the removed Manager''s login up', 'prov_back5');
select pg_temp.run('owner', $q$select public.invite_user_cancel(
    (select id from public.user_invitations where request_id = '429t-req-back5'), '429 test')$q$, 'ok',
  'back: the Owner cancels that invitation', 'cancel_back5');
select pg_temp.check(pg_temp.out('prov_back5')->>'outcome' = 'provisioned'
                     and pg_temp.out('cancel_back5')->>'outcome' = 'cancelled'
                     and exists (select 1 from public.profiles p where p.id = pg_temp.fx('removed_manager')
                                  and p.role = 'manager' and p.invitation_status = 'cancelled'
                                  and p.deleted_at is not null and not p.is_active)
                     and pg_temp.blocked_100y('removed_manager'),
  'back: their profile is a cancelled, removed Manager''s, and the login is blocked again');
select pg_temp.begin_as('manager', '429t-req-back6', '429t-removed_manager@sig.invalid', 'staff', '{}',
                        'back: a Manager then invites them, as Staff');
select pg_temp.check(pg_temp.out('429t-req-back6')->>'outcome' = 'forbidden'
                     and pg_temp.out('429t-req-back6')->>'scope' = 'removed_staff'
                     and pg_temp.inv('429t-req-back6') is null
                     and exists (select 1 from public.profiles p where p.id = pg_temp.fx('removed_manager')
                                  and p.role = 'manager' and p.deleted_at is not null and not p.is_active)
                     and pg_temp.blocked_100y('removed_manager')
                     and (select count(*) from public.audit_logs a where a.record_id = pg_temp.fx('removed_manager')
                           and a.action = 'user_invitation_login_reused') = 1,
  'back: still refused (a cancelled invitation does not open the way); nothing saved, their profile and block untouched');

-- A cancelled invitee who never accepted is judged by the role they were
-- invited as: a Manager may invite again one invited as Staff, not one an
-- Owner invited as a Manager (a Manager cannot cancel or resend that
-- invitation either).
do $$
declare k text; v uuid;
begin
  foreach k in array array['cancelled_staff', 'cancelled_manager'] loop
    insert into auth.users (id, email, raw_user_meta_data)
    values (gen_random_uuid(), '429t-' || k || '@sig.invalid', '{"invited_to":"energia_internal"}') returning id into v;
    insert into fx values (k, v);
  end loop;
end $$;
select pg_temp.begin_as('owner', '429t-req-cs1', '429t-cancelled_staff@sig.invalid', 'staff', '{}',
                        'cancelled: the Owner invites a new address as Staff');
select pg_temp.begin_as('owner', '429t-req-cm1', '429t-cancelled_manager@sig.invalid', 'manager', '{}',
                        'cancelled: and another as a Manager');
select pg_temp.run('service', format($q$select jsonb_build_object('s', public.invite_user_provisioned(%L, %L),
                                                                  'm', public.invite_user_provisioned(%L, %L))$q$,
                                     pg_temp.inv('429t-req-cs1'), pg_temp.fx('cancelled_staff'),
                                     pg_temp.inv('429t-req-cm1'), pg_temp.fx('cancelled_manager')), 'ok',
  'cancelled: both are set up', 'prov_c');
select pg_temp.run('owner', format($q$select jsonb_build_object('s', public.invite_user_cancel(%L, '429 test'),
                                                                'm', public.invite_user_cancel(%L, '429 test'))$q$,
                                   pg_temp.inv('429t-req-cs1'), pg_temp.inv('429t-req-cm1')), 'ok',
  'cancelled: the Owner cancels both', 'cancel_c');
select pg_temp.check(pg_temp.out('prov_c')#>>'{s,outcome}' = 'provisioned' and pg_temp.out('prov_c')#>>'{m,outcome}' = 'provisioned'
                     and pg_temp.out('cancel_c')#>>'{s,outcome}' = 'cancelled' and pg_temp.out('cancel_c')#>>'{m,outcome}' = 'cancelled',
  'cancelled: both invitations are cancelled');
select pg_temp.begin_as('manager', '429t-req-cs2', '429t-cancelled_staff@sig.invalid', 'staff', '{}',
                        'cancelled: a Manager invites the Staff invitee again');
select pg_temp.begin_as('manager', '429t-req-cm2', '429t-cancelled_manager@sig.invalid', 'staff', '{}',
                        'cancelled: a Manager invites the Manager invitee again, as Staff');
select pg_temp.check(pg_temp.out('429t-req-cs2')->>'outcome' = 'created' and pg_temp.inv('429t-req-cs2') is not null,
  'cancelled: a Manager may invite again someone invited as Staff');
select pg_temp.check(pg_temp.out('429t-req-cm2')->>'outcome' = 'forbidden'
                     and pg_temp.out('429t-req-cm2')->>'scope' = 'removed_staff'
                     and pg_temp.inv('429t-req-cm2') is null
                     and exists (select 1 from public.profiles p where p.id = pg_temp.fx('cancelled_manager')
                                  and p.role = 'manager' and p.invitation_status = 'cancelled' and p.deleted_at is not null),
  'cancelled: but not someone an Owner invited as a Manager; nothing saved');
select pg_temp.begin_as('owner', '429t-req-cm3', '429t-cancelled_manager@sig.invalid', 'manager', '{}',
                        'cancelled: the Owner invites the Manager invitee again');
select pg_temp.check(pg_temp.out('429t-req-cm3')->>'outcome' = 'created',
  'cancelled: an Owner may');

-- A live member of staff's address is still in use.
select pg_temp.begin_as('owner', '429t-req-live', '429t-accepted_login@sig.invalid', 'staff', '{}',
                        'live: the Owner invites a live member of staff''s address');
select pg_temp.check(pg_temp.out('429t-req-live')->>'outcome' = 'email_in_use'
                     and pg_temp.out('429t-req-live')->>'scope' = 'staff' and pg_temp.inv('429t-req-live') is null,
  'live: refused as before (switch them on again on Users & Roles instead)');

select pg_temp.check(true, 'invitations-start-again: all passed');
rollback;
