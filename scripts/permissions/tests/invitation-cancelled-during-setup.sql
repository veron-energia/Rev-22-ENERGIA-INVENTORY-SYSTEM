-- Inviting works again, and an invitation cancelled during set-up closes the
-- login it made (413).
--
-- The Owner's rule (9 Oct 2026, as for 412): when a staff invitation is
-- cancelled, that person's login is signed out and blocked. 413 makes
-- invite_user_begin read an affiliate's address from their login (the column
-- it read does not exist), and makes invite_user_provisioned close a login
-- whose invitation was cancelled before the two were tied.
--
--   1. invite_user_begin as the admin-invite-user Edge Function asks it (as
--      the signed-in administrator): a new address is recorded; an affiliate's
--      login address, a member of staff's address, a second click and a
--      second invitation for the same address are answered as before; Staff
--      may not invite.
--   2. invite_user_provisioned on a pending invitation: unchanged (a pending
--      profile, its stores, the login left alone).
--   3. Cancelled during set-up: the login is tied to the invitation, gets a
--      cancelled profile with no store, its session ends and it is banned
--      (412); auth-accept-invitation's look-up finds the cancelled invitation
--      and invite_user_accept refuses it; Users & Roles lists it as a
--      cancelled invitation. A second call changes nothing.
--   4. Cancelled during set-up, for a login that already has a profile, or is
--      an affiliate's: tied, but never given a profile; nothing else changes.
--   5. A cancelled invitation already tied to its login: nothing changes.
--   6. Grants and the catalogue.
--
-- It needs a database with production's schema and 406, 407, 412 and 413
-- applied, or given as preludes:
--   psql -v prelude412=supabase/412_....sql -v prelude=supabase/413_....sql -f this
--   npm run test:permissions:invitations -- -v prelude412=... -v prelude=...
-- Disposable database only; everything is rolled back. Fixture logins are
-- made-up addresses @sig.invalid; nothing real is read or printed.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude412}
\i :prelude412
\endif
\if :{?prelude}
\i :prelude
\endif
-- 429 changed these functions again (a cancelled invitee's profile is also
-- removed, so the address can be invited again). The test runs against 413's
-- versions or 429's; where 429 answers differently it says so, and
-- scripts/permissions/tests/invitations-start-again.sql tests 429 itself.
do $$
begin
  if to_regprocedure('public.staff_login_sync(uuid)') is null
     or md5(pg_get_functiondef(to_regprocedure('public.staff_login_sync(uuid)')))
        not in ('7648388b0b41caee3696694ae172377e', '9259111deccca8c66e95469acfdd250f') then
    raise exception '412 is not in this database: run with -v prelude412=supabase/412_deactivated_staff_signed_out_and_blocked.sql (see the header)'; end if;
  if md5(pg_get_functiondef(to_regprocedure('public.invite_user_provisioned(uuid,uuid)')))
        not in ('506816a8545148a24e9814d0bf2d5062', '7219cae03a5a758402e79762baf46f42',
                -- 437: a login the affiliate sign-up made is never an invitee's
                '6b895cc341bacbe9e115e28982d661e3')
     or md5(pg_get_functiondef(to_regprocedure('public.invite_user_begin(text,text,text,user_role,text,text,text,uuid[])')))
        not in ('8d2e1f3540a00dad9c1be25bd413e3c4', 'eda7f730fd83891146265adb06eca132') then
    raise exception '413 is not in this database: run with -v prelude=supabase/413_invitations_begin_again_and_cancel_during_setup.sql (see the header)'; end if;
end $$;
create function pg_temp.v429() returns boolean language sql as $f$
  select md5(pg_get_functiondef('public.invite_user_provisioned(uuid,uuid)'::regprocedure))
         in ('7219cae03a5a758402e79762baf46f42', '6b895cc341bacbe9e115e28982d661e3')
$f$;

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
  for r in select o.k, o.v from out o loop
    p_sql := replace(p_sql, format('pg_temp.out(%L)', r.k), format('%L::jsonb', r.v));
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
-- Everything this test watches, to prove a step changed nothing.
create function pg_temp.state() returns text language sql as $f$
  select md5(concat_ws('|',
    (select string_agg(u.id || ':' || coalesce(u.banned_until::text, '-'), ',' order by u.id) from auth.users u join fx on fx.id = u.id),
    (select count(*) from auth.sessions s join fx on fx.id = s.user_id),
    (select string_agg(p::text, ',' order by p.id) from public.profiles p join fx on fx.id = p.id),
    (select string_agg(i.id || ':' || i.status || ':' || coalesce(i.auth_user_id::text, '-') || ':' || coalesce(i.profile_id::text, '-'),
                       ',' order by i.id) from public.user_invitations i where i.request_id like '413t-%'),
    (select string_agg(b::text, ',' order by b.user_id) from public.staff_login_blocks b join fx on fx.id = b.user_id),
    (select count(*) from public.user_store_assignments s join fx on fx.id = s.user_id),
    (select count(*) from public.audit_logs a join fx on fx.id = a.record_id)))
$f$;
create temp table st(k text primary key, v text);
create function pg_temp.keep(p_k text, p_v text) returns void language sql as
  $f$ insert into st values (p_k, p_v) on conflict (k) do update set v = excluded.v $f$;
create function pg_temp.kept(p_k text) returns text language sql as $f$ select v from st where k = p_k $f$;

-- ── Fixture (written as the server would) ────────────────────────────────────
do $$
declare k text; v uuid; v_cust uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  foreach k in array array['owner','manager','staff','affiliate','pending_login','race_login','old_login',
                           'aff_race_login','tied_login'] loop
    insert into auth.users (id, email) values (gen_random_uuid(), '413t-' || k || '@sig.invalid') returning id into v;
    insert into fx values (k, v);
  end loop;
  insert into public.profiles (id, full_name, email, role, is_active, invitation_status)
  select fx.id, '413T ' || fx.k, '413t-' || fx.k || '@sig.invalid', x.role::public.user_role, x.active, x.inv
    from fx join (values ('owner','owner',true,null), ('manager','manager',true,'accepted'),
                         ('staff','staff',true,'accepted')) x(k, role, active, inv) on x.k = fx.k;
  -- A login whose old profile was removed (a deleted date) before 412.
  alter table public.profiles disable trigger staff_login_follows_profile;
  insert into public.profiles (id, full_name, email, role, is_active, deleted_at)
  values (pg_temp.fx('old_login'), '413T old', '413t-old_login@sig.invalid', 'staff', false, now() - interval '1 year');
  alter table public.profiles enable trigger staff_login_follows_profile;
  -- The affiliate: a login with an affiliate account and no profile.
  -- Its login address as Supabase Auth might hold it, in other letters.
  update auth.users set email = '413T-Affiliate@sig.invalid' where id = pg_temp.fx('affiliate');
  insert into public.customers (full_name, phone) values ('413T Affiliate', '+61491576398') returning id into v_cust;
  insert into public.affiliate_accounts (auth_user_id, customer_id, status) values (pg_temp.fx('affiliate'), v_cust, 'claimed');
  insert into public.customers (full_name, phone) values ('413T Affiliate 2', '+61491576801') returning id into v_cust;
  insert into public.affiliate_accounts (auth_user_id, customer_id, status) values (pg_temp.fx('aff_race_login'), v_cust, 'claimed');
  insert into auth.sessions (id, user_id, created_at, updated_at)
  select gen_random_uuid(), pg_temp.fx(x.w), now(), now()
    from unnest(array['affiliate','race_login','aff_race_login','old_login']) x(w);
end $$;

-- ── 1. invite_user_begin ─────────────────────────────────────────────────────
select pg_temp.run('owner', $q$select public.invite_user_begin('413t-req-pending', '413t-pending_login@sig.invalid', '413T pending',
    'staff', '+61491577426', '+61491577644', '413t-personal@sig.invalid', '{}')$q$, 'ok',
  'begin: an Owner invites a new address (as admin-invite-user asks it)', 'pending');
select pg_temp.check(pg_temp.out('pending')->>'outcome' = 'created'
                     and exists (select 1 from public.user_invitations i where i.id = pg_temp.inv('413t-req-pending')
                                  and i.status = 'pending' and i.auth_user_id is null and i.last_email_status = 'not_attempted'),
  'begin: it is answered "created" and recorded pending (it failed on production: no affiliate_accounts.email)');
select pg_temp.run('owner', $q$select public.invite_user_begin('413t-req-aff', '413T-Affiliate@SIG.invalid', '413T aff',
    'staff', '+61491577426', '+61491577644', '413t-personal@sig.invalid', '{}')$q$, 'ok',
  'begin: an Owner invites an affiliate''s login address, in other letters', 'aff');
select pg_temp.check(pg_temp.out('aff')->>'outcome' = 'email_in_use' and pg_temp.out('aff')->>'scope' = 'affiliate'
                     and pg_temp.inv('413t-req-aff') is null,
  'begin: an affiliate''s address is refused as before (read from their login), and nothing is recorded');
select pg_temp.run('manager', $q$select public.invite_user_begin('413t-req-staff', '413t-staff@sig.invalid', '413T staff',
    'staff', '+61491577426', '+61491577644', '413t-personal@sig.invalid', '{}')$q$, 'ok',
  'begin: a Manager invites a member of staff''s address', 'staffmail');
select pg_temp.check(pg_temp.out('staffmail')->>'outcome' = 'email_in_use' and pg_temp.out('staffmail')->>'scope' = 'staff',
  'begin: a member of staff''s address is refused as before');
select pg_temp.run('owner', $q$select public.invite_user_begin('413t-req-pending', '413t-other@sig.invalid', '413T other',
    'staff', '+61491577426', '+61491577644', '413t-personal@sig.invalid', '{}')$q$, 'ok',
  'begin: a second click with the same request id', 'again');
select pg_temp.run('owner', $q$select public.invite_user_begin('413t-req-dup', '413t-pending_login@sig.invalid', '413T dup',
    'staff', '+61491577426', '+61491577644', '413t-personal@sig.invalid', '{}')$q$, 'ok',
  'begin: a second invitation for a pending address', 'dup');
select pg_temp.check(pg_temp.out('again')->>'outcome' = 'existing_request' and pg_temp.out('dup')->>'outcome' = 'existing_pending'
                     and (select count(*) from public.user_invitations where request_id like '413t-%') = 1,
  'begin: are answered as before, with one invitation recorded');
select pg_temp.run('staff', $q$select public.invite_user_begin('413t-req-bystaff', '413t-x@sig.invalid', '413T x',
    'staff', '+61491577426', '+61491577644', '413t-personal@sig.invalid', '{}')$q$, 'ok',
  'begin: Staff try to invite', 'bystaff');
select pg_temp.check(pg_temp.out('bystaff')->>'outcome' = 'forbidden' and pg_temp.inv('413t-req-bystaff') is null,
  'begin: Staff may not, as before');

-- ── 2. A pending invitation's profile: unchanged ─────────────────────────────
select pg_temp.run('service', $q$select public.invite_user_provisioned(
    (select id from public.user_invitations where request_id = '413t-req-pending'), pg_temp.fx('pending_login'))$q$, 'ok',
  'pending: the Edge Function ties the login to a pending invitation', 'prov_pending');
select pg_temp.check(pg_temp.out('prov_pending')->>'outcome' = 'provisioned'
                     and exists (select 1 from public.profiles p where p.id = pg_temp.fx('pending_login')
                                  and p.invitation_status = 'pending' and not p.is_active)
                     and exists (select 1 from public.user_invitations i where i.id = pg_temp.inv('413t-req-pending')
                                  and i.auth_user_id = pg_temp.fx('pending_login') and i.profile_id = pg_temp.fx('pending_login'))
                     and pg_temp.ban('pending_login') is null,
  'pending: a pending profile, tied, the login left alone (they sign in from the link)');

-- ── 3. Cancelled during set-up ───────────────────────────────────────────────
select pg_temp.run('owner', $q$select public.invite_user_begin('413t-req-race', '413t-race_login@sig.invalid', '413T race',
    'staff', '+61491577426', '+61491577644', '413t-personal@sig.invalid', '{}')$q$, 'ok',
  'race: an Owner invites a new address', 'race');
-- A store on the invitation, as one the Owner chose: it must not be assigned.
update public.user_invitations set store_ids = array[gen_random_uuid()] where id = pg_temp.inv('413t-req-race');
select pg_temp.run('owner', $q$select public.invite_user_cancel(
    (select id from public.user_invitations where request_id = '413t-req-race'), '413 test')$q$, 'ok',
  'race: an Owner cancels it before Supabase Auth has made the login', 'race_cancel');
select pg_temp.check(pg_temp.out('race_cancel')->>'outcome' = 'cancelled'
                     and not exists (select 1 from public.profiles where id = pg_temp.fx('race_login')),
  'race: the cancel finds no login to close yet');
select pg_temp.run('service', $q$select public.invite_user_provisioned(
    (select id from public.user_invitations where request_id = '413t-req-race'), pg_temp.fx('race_login'))$q$, 'ok',
  'race: then the Edge Function ties the login Supabase Auth made', 'race_prov');
select pg_temp.check(pg_temp.out('race_prov')->>'outcome' = 'cancelled',
  'race: it is answered "cancelled" (the Edge Function sends no email for that)');
select pg_temp.check(exists (select 1 from public.user_invitations i where i.id = pg_temp.inv('413t-req-race')
                              and i.status = 'cancelled' and i.auth_user_id = pg_temp.fx('race_login')
                              and i.profile_id = pg_temp.fx('race_login')),
  'race: the login is tied to the cancelled invitation');
select pg_temp.check(exists (select 1 from public.profiles p where p.id = pg_temp.fx('race_login') and not p.is_active
                              and p.invitation_status = 'cancelled' and p.role = 'staff' and p.full_name = '413T race'
                              -- 429: removed too (a deleted date), so the address can be invited again
                              and (p.deleted_at is not null) = pg_temp.v429())
                     and not exists (select 1 from public.user_store_assignments s where s.user_id = pg_temp.fx('race_login')),
  'race: it gets a cancelled profile, switched off, with no store (429: and removed)');
select pg_temp.check(pg_temp.sessions('race_login') = 0 and pg_temp.blocked_100y('race_login')
                     and (select reason from public.staff_login_blocks where user_id = pg_temp.fx('race_login')) = 'invitation_cancelled',
  'race: so 412 signs it out and blocks it (about a hundred years, a finite time)');
select pg_temp.check((select i.status from public.user_invitations i where i.auth_user_id = pg_temp.fx('race_login')
                       order by i.invited_at desc limit 1) = 'cancelled',
  'race: auth-accept-invitation''s look-up by login finds the cancelled invitation, so it sets no password');
select pg_temp.run('service', $q$select public.invite_user_accept(pg_temp.fx('race_login'), '413t-race_login@sig.invalid')$q$, 'ok',
  'race: and invite_user_accept is asked anyway', 'race_accept');
select pg_temp.check(pg_temp.out('race_accept')->>'reason' = 'cancelled' and (pg_temp.out('race_accept')->>'activated')::boolean = false
                     and pg_temp.blocked_100y('race_login'),
  'race: it refuses: the invitation was cancelled (before 413: not_invited)');
select pg_temp.run('owner', $q$select to_jsonb(x) from public.user_admin_list() x where x.user_id = pg_temp.fx('race_login')$q$, 'ok',
  'race: an Owner opens Users & Roles', 'race_list');
select pg_temp.check(case when pg_temp.v429() then pg_temp.out('race_list') is null
                          else pg_temp.out('race_list')->>'state' = 'cancelled_invitation' end,
  'race: the login is listed as a cancelled invitation (429: not listed, as any cancelled invitee)');
select pg_temp.keep('state', pg_temp.state());
select pg_temp.run('service', $q$select public.invite_user_provisioned(
    (select id from public.user_invitations where request_id = '413t-req-race'), pg_temp.fx('race_login'))$q$, 'ok',
  'race: the Edge Function retries', 'race_prov2');
select pg_temp.check(pg_temp.out('race_prov2')->>'outcome' = 'cancelled' and pg_temp.kept('state') = pg_temp.state(),
  'race: a second call changes nothing');

-- ── 4. Cancelled during set-up, for a login that is already someone's ───────
-- A login with an old, removed profile (invite_user_begin only refuses a live
-- one; 429 lets an Owner invite a removed member of staff again, the Owner's
-- decision of 10 Oct 2026).
select pg_temp.run('owner', $q$select public.invite_user_begin('413t-req-old', '413t-old_login@sig.invalid', '413T old again',
    'manager', '+61491577426', '+61491577644', '413t-personal@sig.invalid', '{}')$q$, 'ok',
  'existing: an Owner invites the address of a removed profile''s login', 'old');
select pg_temp.check(pg_temp.out('old')->>'outcome' = 'created',
  'existing: it is recorded (413 and 429 alike)');
select pg_temp.run('owner', $q$select public.invite_user_cancel(
    (select id from public.user_invitations where request_id = '413t-req-old'), '413 test')$q$, 'ok',
  'existing: and cancels it during set-up');
select pg_temp.keep('old', (select p::text from public.profiles p where p.id = pg_temp.fx('old_login')));
select pg_temp.run('service', $q$select public.invite_user_provisioned(
    (select id from public.user_invitations where request_id = '413t-req-old'), pg_temp.fx('old_login'))$q$, 'ok',
  'existing: the Edge Function ties the login', 'old_prov');
select pg_temp.check(pg_temp.out('old_prov')->>'outcome' = 'cancelled'
                     and (select p::text from public.profiles p where p.id = pg_temp.fx('old_login')) = pg_temp.kept('old')
                     and exists (select 1 from public.user_invitations i where i.id = pg_temp.inv('413t-req-old')
                                  and i.auth_user_id = pg_temp.fx('old_login') and i.profile_id is null),
  'existing: tied, and its own profile is left exactly as it was (no role, name or state from the invitation)');
-- An affiliate's login (the address check stops this before; the server could still be asked).
insert into public.user_invitations (request_id, email, email_normalized, full_name, role, status, invited_by, cancelled_at)
values ('413t-req-affrace', '413t-aff_race_login@sig.invalid', '413t-aff_race_login@sig.invalid', '413T aff race', 'staff',
        'cancelled', pg_temp.fx('owner'), now());
select pg_temp.run('service', $q$select public.invite_user_provisioned(
    (select id from public.user_invitations where request_id = '413t-req-affrace'), pg_temp.fx('aff_race_login'))$q$, 'ok',
  'existing: a cancelled invitation is tied to an affiliate''s login', 'aff_prov');
select pg_temp.check(pg_temp.out('aff_prov')->>'outcome' = 'cancelled'
                     and not exists (select 1 from public.profiles where id = pg_temp.fx('aff_race_login'))
                     and pg_temp.ban('aff_race_login') is null and pg_temp.sessions('aff_race_login') = 1
                     and not exists (select 1 from public.staff_login_blocks where user_id = pg_temp.fx('aff_race_login')),
  'existing: the affiliate gets no profile, keeps their session and is not blocked');

-- ── 5. A cancelled invitation already tied to its login ──────────────────────
insert into public.user_invitations (request_id, email, email_normalized, full_name, role, status, invited_by, cancelled_at,
                                     auth_user_id)
values ('413t-req-tied', '413t-tied_login@sig.invalid', '413t-tied_login@sig.invalid', '413T tied', 'staff',
        'cancelled', pg_temp.fx('owner'), now(), pg_temp.fx('tied_login'));
select pg_temp.keep('state', pg_temp.state());
select pg_temp.run('service', $q$select public.invite_user_provisioned(
    (select id from public.user_invitations where request_id = '413t-req-tied'), pg_temp.fx('tied_login'))$q$, 'ok',
  'tied: the Edge Function ties a login to an invitation cancelled after it was tied', 'tied_prov');
select pg_temp.check(pg_temp.out('tied_prov')->>'outcome' = 'cancelled' and pg_temp.kept('state') = pg_temp.state(),
  'tied: nothing changes (invite_user_cancel closed that login when it cancelled)');
select pg_temp.check(pg_temp.sessions('affiliate') = 1 and pg_temp.ban('affiliate') is null
                     and pg_temp.ban('owner') is null and pg_temp.ban('manager') is null,
  'nobody else''s login was touched (the affiliate, the Owner, the Manager)');

-- ── 6. Grants and the catalogue ──────────────────────────────────────────────
select pg_temp.run(w, $q$select public.invite_user_provisioned(gen_random_uuid(), gen_random_uuid())$q$, '42501',
                   'grants: ' || w || ' cannot call invite_user_provisioned')
  from unnest(array['owner', 'affiliate', 'anon']) w;
select pg_temp.run('anon', $q$select public.invite_user_begin('413t-req-anon', '413t-anon@sig.invalid', 'x', 'staff')$q$, '42501',
  'grants: the anon key cannot call invite_user_begin');
select pg_temp.run('affiliate', $q$select public.invite_user_begin('413t-req-affcall', '413t-y@sig.invalid', '413T y',
    'staff', '+61491577426', '+61491577644', '413t-personal@sig.invalid', '{}')$q$, 'ok',
  'grants: an affiliate''s login calls invite_user_begin', 'affcall');
select pg_temp.check(pg_temp.out('affcall')->>'outcome' = 'forbidden' and pg_temp.inv('413t-req-affcall') is null,
  'grants: and is refused, as before');
select pg_temp.check(md5(pg_get_functiondef('public.invite_user_begin(text,text,text,user_role,text,text,text,uuid[])'::regprocedure))
                       = case when pg_temp.v429() then 'eda7f730fd83891146265adb06eca132' else '8d2e1f3540a00dad9c1be25bd413e3c4' end
                     and md5(pg_get_functiondef('public.invite_user_provisioned(uuid,uuid)'::regprocedure))
                       in (case when pg_temp.v429() then '7219cae03a5a758402e79762baf46f42' else '506816a8545148a24e9814d0bf2d5062' end,
                           '6b895cc341bacbe9e115e28982d661e3'),
  'catalogue: both functions are at 413''s AFTER md5s (or 429''s; invite_user_provisioned may be 437''s)');
select pg_temp.check(not exists (select 1 from auth.users u join fx on fx.id = u.id
                                  where u.banned_until is not null and not isfinite(u.banned_until)),
  'no login was ever given an infinite ban');

select pg_temp.check(true, 'invitation-cancelled-during-setup: all passed');
rollback;
