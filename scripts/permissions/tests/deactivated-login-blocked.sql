-- A closed staff profile's login is signed out and blocked (412).
--
-- The Owner's rule (9 Oct 2026): when a staff profile is deactivated,
-- removed (a deleted date) or its invitation is cancelled, that person's
-- login is signed out on every device and blocked from signing in; when the
-- profile is active, accepted and not removed again, the login is unblocked
-- by itself. Staff only: affiliates have no profile and are never touched.
--
-- Every path that closes or reopens a profile, as the pages and the Edge
-- Functions reach it:
--   1. the Users & Roles page, an Owner deactivating (its direct update, as a
--      signed-in login under the profile rules), and a Manager deactivating
--      Staff; the page's save as it now sends it (Active only when the dialog
--      changed it, and only onto the state it was opened with), so a dialog
--      opened before someone else switched a person on or off neither puts
--      the old value back nor blocks or unblocks them;
--   2. a second run, and an edit of something else, change nothing; a
--      session that slips in later is ended;
--   3. ticking Active again lifts the block;
--   4. cancelling an invitation (invite_user_cancel, as the admin-invite-user
--      Edge Function calls it) closes a pending invitee who had opened the
--      link;
--   5. an invitation's profile (invite_user_provisioned) and accepting it
--      (invite_user_accept), which leave a pending invitee alone and open
--      them;
--   6. the server removing a profile (a deleted date) and restoring it;
--   7. the server inserting a closed profile;
--   8. a ban placed some other way: shorter (put back when the profile
--      reopens), changed or lifted while the profile was closed (left as it
--      is, or placed again at the next closing change), longer (never
--      touched, and never put back once lifted by hand);
--   9. an affiliate login, and a login with no profile: never touched;
--  10. a browser, the anon key and the service role cannot write the record
--      or call the helper as a login; 407's rules still refuse what they
--      refused;
--  11. the repair script blocks profiles closed before 412, once;
--  12. the grants, the trigger and the table, by the catalogue; a deleted
--      login takes its record with it.
--
-- It needs a database with production's schema and 406, 407 and 412 applied,
-- or 412 given as the prelude:
--   psql -v prelude=supabase/412_deactivated_staff_signed_out_and_blocked.sql -f this
--   npm run test:permissions:login-blocked -- -v prelude=supabase/412_deactivated_staff_signed_out_and_blocked.sql
-- Disposable database only; everything is rolled back. Fixture logins are
-- made-up addresses @sig.invalid; nothing real is read or printed.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif
do $$
begin
  if to_regprocedure('public.staff_login_sync(uuid)') is null
     or md5(pg_get_functiondef(to_regprocedure('public.staff_login_sync(uuid)'))) <> '7648388b0b41caee3696694ae172377e' then
    raise exception '412 is not in this database: run with -v prelude=supabase/412_deactivated_staff_signed_out_and_blocked.sql (npm run test:permissions:login-blocked -- -v prelude=...; see the header)'; end if;
end $$;

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end$$;

create temp table fx(k text primary key, id uuid not null);
create function pg_temp.fx(p text) returns uuid language sql as $f$ select id from fx where k = p $f$;

-- Run p_sql as one of the fixture's logins (a signed-in browser), the anon
-- key ('anon'), the service role ('service') or the server ('server': no
-- request at all), and require the answer p_expect: 'ok' or a SQLSTATE.
-- Each action is a statement of its own; what it did is checked in the
-- next statement, which sees it.
create function pg_temp.run(p_who text, p_sql text, p_expect text, p_label text) returns void language plpgsql as $f$
declare v_state text := 'ok'; v_msg text; r record;
begin
  -- The fixture's ids go into the statement as text first: the logins
  -- switched to below may not read the test's own temporary tables.
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
    execute p_sql;
    execute 'reset role';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    execute 'reset role';
  end;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('energia.profile_privilege_change', '', true);
  if v_state is distinct from p_expect then
    raise exception 'FAIL: % (expected %, got % %)', p_label, p_expect, v_state, coalesce(v_msg, ''); end if;
  raise notice 'PASS  %', p_label;
end $f$;

-- staff_login_sync as the server, requiring its answer.
create function pg_temp.sync(p text, p_expect text, p_label text) returns void language plpgsql as $f$
declare v text := public.staff_login_sync(coalesce(pg_temp.fx(p), '00000000-0000-4000-8000-000000000412'));
begin
  if v is distinct from p_expect then
    raise exception 'FAIL: % (staff_login_sync answered %, expected %)', p_label, v, p_expect; end if;
  raise notice 'PASS  %', p_label;
end $f$;

-- A login's open sessions and refresh tokens; its ban; its block record.
create function pg_temp.sessions(p text) returns int language sql as
  $f$ select count(*)::int from auth.sessions where user_id = pg_temp.fx(p) $f$;
create function pg_temp.tokens(p text) returns int language sql as
  $f$ select count(*)::int from auth.refresh_tokens where user_id = pg_temp.fx(p)::text $f$;
create function pg_temp.ban(p text) returns timestamptz language sql as
  $f$ select banned_until from auth.users where id = pg_temp.fx(p) $f$;
create function pg_temp.blocked_100y(p text) returns boolean language sql as
  $f$ select b is not null and isfinite(b) and b between now() + interval '99 years' and now() + interval '101 years'
        from (select pg_temp.ban(p) b) x $f$;
create function pg_temp.reason(p text) returns text language sql as
  $f$ select reason from public.staff_login_blocks where user_id = pg_temp.fx(p) $f$;
create function pg_temp.audits(p text, p_action text) returns int language sql as
  $f$ select count(*)::int from public.audit_logs where record_id = pg_temp.fx(p) and action = p_action $f$;
create function pg_temp.active(p text) returns boolean language sql as
  $f$ select is_active from public.profiles where id = pg_temp.fx(p) $f$;
-- n sessions, each with a refresh token, as a signed-in phone and laptop.
create function pg_temp.open_sessions(p text, n int default 2) returns void language plpgsql as $f$
declare v uuid;
begin
  for i in 1 .. n loop
    insert into auth.sessions (id, user_id, created_at, updated_at) values (gen_random_uuid(), pg_temp.fx(p), now(), now())
      returning id into v;
    insert into auth.refresh_tokens (token, user_id, revoked, created_at, updated_at, session_id)
    values ('412-' || gen_random_uuid(), pg_temp.fx(p)::text, false, now(), now(), v);
  end loop;
end $f$;
-- Everything about logins this test watches, to prove a step changed nothing.
create function pg_temp.state() returns text language sql as $f$
  select md5(concat_ws('|',
    (select string_agg(u.id || ':' || coalesce(u.banned_until::text, '-'), ',' order by u.id)
       from auth.users u join fx on fx.id = u.id),
    (select count(*) from auth.sessions s join fx on fx.id = s.user_id),
    (select count(*) from auth.refresh_tokens r join fx on fx.id::text = r.user_id),
    (select string_agg(b::text, ',' order by b.user_id) from public.staff_login_blocks b),
    (select count(*) from public.audit_logs a join fx on fx.id = a.record_id),
    (select string_agg(p.id || ':' || p.is_active || ':' || coalesce(p.deleted_at::text, '-') || ':'
                       || coalesce(p.invitation_status, '-'), ',' order by p.id)
       from public.profiles p join fx on fx.id = p.id)))
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
  foreach k in array array['owner','manager','staff_a','staff_b','staff_c','staff_d','staff_e','removed','other_ban','changed_ban',
                           'lifted_ban','long_ban','lifted_long_ban','invitee_cancel','invitee_accept','invitee_new',
                           'inserted','affiliate','old_closed','old_pending'] loop
    insert into auth.users (id, email) values (gen_random_uuid(), '412t-' || k || '@sig.invalid') returning id into v;
    insert into fx values (k, v);
  end loop;
  insert into public.profiles (id, full_name, email, role, is_active, invitation_status)
  select fx.id, '412T ' || fx.k, '412t-' || fx.k || '@sig.invalid', x.role::public.user_role, x.active, x.inv
    from fx join (values ('owner','owner',true,null), ('manager','manager',true,'accepted'),
                         ('staff_a','staff',true,'accepted'), ('staff_b','staff',true,null),
                         ('staff_c','inventory_manager',true,null), ('removed','staff',true,null),
                         ('staff_d','staff',true,'accepted'), ('staff_e','staff',true,null),
                         ('other_ban','staff',true,null), ('changed_ban','staff',true,null),
                         ('lifted_ban','staff',true,null), ('long_ban','staff',true,null),
                         ('lifted_long_ban','staff',true,null),
                         ('invitee_cancel','staff',false,'pending'), ('invitee_accept','staff',false,'pending'))
                  x(k, role, active, inv) on x.k = fx.k;
  -- The affiliate: a login with an affiliate account and no profile.
  insert into public.customers (full_name, phone) values ('412T Affiliate', '+6591412001') returning id into v_cust;
  insert into public.affiliate_accounts (auth_user_id, customer_id) values (pg_temp.fx('affiliate'), v_cust);
  -- The invitations of the pending invitees.
  insert into public.user_invitations (request_id, email, email_normalized, full_name, role, status, auth_user_id, profile_id, invited_by)
  select '412t-req-' || fx.k, '412t-' || fx.k || '@sig.invalid', '412t-' || fx.k || '@sig.invalid', '412T ' || fx.k,
         'staff', 'pending', fx.id, fx.id, pg_temp.fx('owner')
    from fx where fx.k in ('invitee_cancel', 'invitee_accept');
  insert into public.user_invitations (request_id, email, email_normalized, full_name, role, status, invited_by)
  values ('412t-req-invitee_new', '412t-invitee_new@sig.invalid', '412t-invitee_new@sig.invalid', '412T invitee_new',
          'staff', 'pending', pg_temp.fx('owner'));
end $$;
select pg_temp.open_sessions(k) from unnest(array['owner','staff_a','staff_b','other_ban','changed_ban','lifted_ban',
                                                  'long_ban','invitee_cancel','invitee_accept','affiliate']) k;
-- An old refresh token with no session (Supabase Auth's earlier kind).
insert into auth.refresh_tokens (token, user_id, revoked, created_at, updated_at)
values ('412-old-' || gen_random_uuid(), pg_temp.fx('staff_a')::text, false, now(), now());
-- Bans placed some other way (the dashboard, Supabase Auth's admin API).
update auth.users set banned_until = now() + interval '1 day' where id = pg_temp.fx('other_ban');
update auth.users set banned_until = now() + interval '200 years' where id in (pg_temp.fx('long_ban'), pg_temp.fx('lifted_long_ban'));

select pg_temp.check(pg_temp.sessions('staff_a') = 2 and pg_temp.tokens('staff_a') = 3 and pg_temp.ban('staff_a') is null
                     and (select count(*) from public.staff_login_blocks b join fx on fx.id = b.user_id) = 0
                     and (select count(*) from public.audit_logs a join fx on fx.id = a.record_id) = 0,
  'fixture: making open profiles leaves their logins alone (sessions kept, no ban, no record, no audit row)');
select pg_temp.check(pg_temp.reason('invitee_cancel') is null and pg_temp.ban('invitee_cancel') is null
                     and pg_temp.sessions('invitee_cancel') = 2,
  'fixture: a pending invitee who opened the link keeps that session (pending is left alone)');

-- ── 1. The Users & Roles page ─────────────────────────────────────────────────
select pg_temp.run('owner', $q$update public.profiles set full_name = full_name, role = role, is_active = false,
    work_phone = work_phone, updated_at = now() where id = pg_temp.fx('staff_a')$q$, 'ok',
  'page: an Owner saves a member of staff with Active off (the page''s whole-row update)');
select pg_temp.check(pg_temp.active('staff_a') = false, 'page: the profile is switched off');
select pg_temp.check(pg_temp.sessions('staff_a') = 0 and pg_temp.tokens('staff_a') = 0,
  'page: every session ends, and every refresh token with it (the one with no session too)');
select pg_temp.check(pg_temp.blocked_100y('staff_a'),
  'page: the login is banned about a hundred years ahead, a finite time (never infinity)');
select pg_temp.check((select b.reason = 'deactivated' and b.banned_until_set = pg_temp.ban('staff_a') and b.banned_until_before is null
                        from public.staff_login_blocks b where b.user_id = pg_temp.fx('staff_a')),
  'page: the block is recorded with the time written and nothing before it');
select pg_temp.check((select a.changed_by = pg_temp.fx('owner') and a.table_name = 'profiles'
                             and a.new_data = jsonb_build_object('reason', 'deactivated', 'sessions_ended', 2,
                                                                 'refresh_tokens_without_session', 1, 'ban_placed', true)
                        from public.audit_logs a where a.record_id = pg_temp.fx('staff_a') and a.action = 'staff_login_blocked'),
  'page: one audit row names the Owner, two sessions and one loose token ended, the ban placed');
select pg_temp.check(pg_temp.sessions('owner') = 2 and pg_temp.ban('owner') is null
                     and pg_temp.sessions('affiliate') = 2 and pg_temp.ban('affiliate') is null
                     and pg_temp.sessions('staff_b') = 2 and pg_temp.ban('staff_b') is null,
  'page: nobody else''s login is touched (the Owner''s own, another member of staff, an affiliate)');

select pg_temp.run('manager', $q$update public.profiles set is_active = false where id = pg_temp.fx('staff_b')$q$, 'ok',
  'page: a Manager saves Staff with Active off');
select pg_temp.check(pg_temp.active('staff_b') = false and pg_temp.sessions('staff_b') = 0
                     and pg_temp.blocked_100y('staff_b') and pg_temp.reason('staff_b') = 'deactivated',
  'page: so they are signed out and blocked too');

-- The page's save as it now sends it. A Manager opens staff_d's dialog while
-- staff_d is on; an Owner switches staff_d off meanwhile.
select pg_temp.run('owner', $q$update public.profiles set is_active = false, updated_at = now()
    where id = pg_temp.fx('staff_d') and is_active = true$q$, 'ok',
  'page now: an Owner switches someone off while a Manager has their dialog open');
select pg_temp.run('manager', $q$update public.profiles set full_name = '412T staff_d', role = 'staff',
    work_phone = '+6591412077', personal_phone = null, personal_email = null, updated_at = now()
    where id = pg_temp.fx('staff_d')$q$, 'ok',
  'page now: the Manager saves a new phone with Active untouched, so Active is not sent');
select pg_temp.check(pg_temp.active('staff_d') = false and pg_temp.blocked_100y('staff_d') and pg_temp.reason('staff_d') = 'deactivated'
                     and (select work_phone from public.profiles where id = pg_temp.fx('staff_d')) = '+6591412077',
  'page now: the phone is saved and they stay switched off and blocked (the whole-row save switched them back on)');
select pg_temp.keep('state', pg_temp.state());
select pg_temp.run('manager', $q$update public.profiles set is_active = false, updated_at = now()
    where id = pg_temp.fx('staff_d') and is_active = true$q$, 'ok',
  'page now: the Manager unticks Active in the old dialog (sent onto "on", the state it opened with)');
select pg_temp.check(pg_temp.kept('state') = pg_temp.state() and pg_temp.audits('staff_d', 'staff_login_blocked') = 1,
  'page now: that save changes no row (the page then says someone else switched them)');
-- The other way: staff_e is off when the Manager opens the dialog; the Owner
-- switches staff_e on meanwhile.
select pg_temp.run('owner', $q$update public.profiles set is_active = false where id = pg_temp.fx('staff_e')$q$, 'ok',
  'page now: an Owner switches someone off');
select pg_temp.run('owner', $q$update public.profiles set is_active = true, updated_at = now()
    where id = pg_temp.fx('staff_e') and is_active = false$q$, 'ok',
  'page now: and, while a Manager has the dialog open, back on');
select pg_temp.keep('state', pg_temp.state());
select pg_temp.run('manager', $q$update public.profiles set is_active = true, updated_at = now()
    where id = pg_temp.fx('staff_e') and is_active = false$q$, 'ok',
  'page now: the Manager ticks Active in the old dialog (sent onto "off")');
select pg_temp.check(pg_temp.kept('state') = pg_temp.state(), 'page now: that save changes no row either');
select pg_temp.run('manager', $q$update public.profiles set full_name = '412T staff_e', role = 'staff',
    work_phone = '+6591412078', updated_at = now() where id = pg_temp.fx('staff_e')$q$, 'ok',
  'page now: the Manager saves a new phone in the old dialog, Active untouched');
select pg_temp.check(pg_temp.active('staff_e') and pg_temp.ban('staff_e') is null and pg_temp.reason('staff_e') is null
                     and pg_temp.audits('staff_e', 'staff_login_blocked') = 1 and pg_temp.audits('staff_e', 'staff_login_unblocked') = 1,
  'page now: they stay on and unblocked (the whole-row save switched them off and blocked them)');

-- ── 2. A second run, and other edits, change nothing ─────────────────────────
select pg_temp.keep('state', pg_temp.state());
select pg_temp.sync('staff_a', 'already_blocked', 're-run: the helper again answers already_blocked');
select pg_temp.sync('staff_a', 'already_blocked', 're-run: and again');
select pg_temp.check(pg_temp.kept('state') = pg_temp.state(), 're-run: twice more changed no row');
select pg_temp.run('owner', $q$update public.profiles set full_name = '412T staff_a renamed', work_phone = '+6591412099'
    where id = pg_temp.fx('staff_a')$q$, 'ok', 're-run: an Owner edits a closed profile''s name and phone');
select pg_temp.run('owner', $q$update public.profiles set is_active = false, updated_at = now()
    where id = pg_temp.fx('staff_a')$q$, 'ok', 're-run: and saves Active off again, unchanged');
select pg_temp.check(pg_temp.audits('staff_a', 'staff_login_blocked') = 1 and pg_temp.audits('staff_a', 'staff_login_unblocked') = 0
                     and (select string_agg(b::text, ',') from public.staff_login_blocks b where b.user_id = pg_temp.fx('staff_a'))
                         is not null and pg_temp.blocked_100y('staff_a'),
  're-run: those edits leave the login, the record and the audit log as they were');
-- A session that slips in (a sign-in already under way when the block landed).
select pg_temp.open_sessions('staff_a', 1);
select pg_temp.keep('ban', pg_temp.ban('staff_a')::text);
select pg_temp.sync('staff_a', 'blocked', 're-run: a session found later is ended');
select pg_temp.check(pg_temp.sessions('staff_a') = 0 and pg_temp.ban('staff_a')::text = pg_temp.kept('ban')
                     and (select count(*) from public.audit_logs a where a.record_id = pg_temp.fx('staff_a')
                           and a.action = 'staff_login_blocked' and a.new_data->>'ban_placed' = 'false'
                           and a.new_data->>'sessions_ended' = '1') = 1,
  're-run: the ban written first stays as it is, and the audit row says so');

-- ── 3. Ticking Active again ──────────────────────────────────────────────────
select pg_temp.run('owner', $q$update public.profiles set is_active = true where id = pg_temp.fx('staff_a')$q$, 'ok',
  'reactivate: an Owner ticks Active again');
select pg_temp.check(pg_temp.ban('staff_a') is null and pg_temp.reason('staff_a') is null,
  'reactivate: the ban this placed is lifted and the record goes');
select pg_temp.check((select a.changed_by = pg_temp.fx('owner') and (a.new_data->>'ban_lifted')::boolean
                        from public.audit_logs a where a.record_id = pg_temp.fx('staff_a') and a.action = 'staff_login_unblocked'),
  'reactivate: one audit row says the ban was lifted, by whom');
select pg_temp.sync('staff_a', 'open', 'reactivate: a second run answers open');
select pg_temp.check(pg_temp.audits('staff_a', 'staff_login_unblocked') = 1 and pg_temp.ban('staff_a') is null,
  'reactivate: and changes nothing');
select pg_temp.run('manager', $q$update public.profiles set is_active = true where id = pg_temp.fx('staff_b')$q$, 'ok',
  'reactivate: a Manager ticks Staff Active again');
select pg_temp.check(pg_temp.ban('staff_b') is null and pg_temp.reason('staff_b') is null, 'reactivate: lifted too');

-- ── 4. Cancelling an invitation ──────────────────────────────────────────────
select pg_temp.run('owner', $q$select public.invite_user_cancel(
    (select id from public.user_invitations where request_id = '412t-req-invitee_cancel'), 'test')$q$, 'ok',
  'cancel: an Owner cancels a pending invitation (as admin-invite-user does)');
select pg_temp.check((select invitation_status from public.profiles where id = pg_temp.fx('invitee_cancel')) = 'cancelled',
  'cancel: the profile is cancelled');
select pg_temp.check(pg_temp.sessions('invitee_cancel') = 0 and pg_temp.tokens('invitee_cancel') = 0
                     and pg_temp.blocked_100y('invitee_cancel') and pg_temp.reason('invitee_cancel') = 'invitation_cancelled',
  'cancel: the session they opened from the link ends and the login is blocked');

-- ── 5. An invitation's profile, and accepting it ─────────────────────────────
select pg_temp.run('service', $q$select public.invite_user_provisioned(
    (select id from public.user_invitations where request_id = '412t-req-invitee_new'), pg_temp.fx('invitee_new'))$q$, 'ok',
  'invite: the Edge Function makes an invitation''s profile');
select pg_temp.check((select invitation_status = 'pending' and not is_active from public.profiles where id = pg_temp.fx('invitee_new'))
                     and pg_temp.ban('invitee_new') is null and pg_temp.reason('invitee_new') is null,
  'invite: the pending profile leaves its login alone (they sign in from the link)');
select pg_temp.run('service', $q$select public.invite_user_accept(pg_temp.fx('invitee_accept'),
    '412t-invitee_accept@sig.invalid')$q$, 'ok', 'accept: the Edge Function accepts an invitation');
select pg_temp.check((select is_active and invitation_status = 'accepted' from public.profiles where id = pg_temp.fx('invitee_accept'))
                     and pg_temp.ban('invitee_accept') is null and pg_temp.sessions('invitee_accept') = 2
                     and pg_temp.reason('invitee_accept') is null,
  'accept: the profile opens and keeps the session they set the password from');

-- ── 6. The server removes a profile, and restores it ─────────────────────────
select pg_temp.run('service', $q$update public.profiles set deleted_at = now() where id = pg_temp.fx('removed')$q$, 'ok',
  'remove: the service role sets a deleted date');
select pg_temp.check(pg_temp.blocked_100y('removed') and pg_temp.reason('removed') = 'removed', 'remove: the login is blocked');
select pg_temp.run('server', $q$update public.profiles set deleted_at = null where id = pg_temp.fx('removed')$q$, 'ok',
  'remove: the SQL editor clears it on an active, accepted profile');
select pg_temp.check(pg_temp.ban('removed') is null and pg_temp.reason('removed') is null, 'remove: the block is lifted');
select pg_temp.run('owner', $q$update public.profiles set is_active = false where id = pg_temp.fx('staff_b')$q$, 'ok',
  'remove: an Owner switches a member of staff off');
select pg_temp.keep('ban', pg_temp.ban('staff_b')::text);
select pg_temp.run('service', $q$update public.profiles set deleted_at = now() where id = pg_temp.fx('staff_b')$q$, 'ok',
  'remove: then the service role removes the profile');
select pg_temp.check(pg_temp.reason('staff_b') = 'removed' and pg_temp.ban('staff_b')::text = pg_temp.kept('ban')
                     and pg_temp.audits('staff_b', 'staff_login_blocked') = 2,
  'remove: the ban stays as written and only the reason changes (one audit row for this block)');
select pg_temp.run('service', $q$update public.profiles set deleted_at = null where id = pg_temp.fx('staff_b')$q$, 'ok',
  'remove: the service role restores it while it is still switched off');
select pg_temp.check(pg_temp.reason('staff_b') = 'deactivated' and pg_temp.ban('staff_b')::text = pg_temp.kept('ban'),
  'remove: so it stays blocked');

-- ── 7. The server inserts a closed profile ───────────────────────────────────
insert into auth.sessions (id, user_id, created_at, updated_at) values (gen_random_uuid(), pg_temp.fx('inserted'), now(), now());
select pg_temp.run('service', $q$insert into public.profiles (id, full_name, email, role, is_active)
    values (pg_temp.fx('inserted'), '412T inserted', '412t-inserted@sig.invalid', 'staff', false)$q$, 'ok',
  'insert: the service role makes a profile that is switched off');
select pg_temp.check(pg_temp.sessions('inserted') = 0 and pg_temp.blocked_100y('inserted') and pg_temp.reason('inserted') = 'deactivated',
  'insert: its login is signed out and blocked at once');

-- ── 8. Bans placed some other way ────────────────────────────────────────────
select pg_temp.keep('ban', pg_temp.ban('other_ban')::text);
select pg_temp.run('owner', $q$update public.profiles set is_active = false where id = pg_temp.fx('other_ban')$q$, 'ok',
  'other ban: an Owner switches off someone banned for a day already');
select pg_temp.check(pg_temp.blocked_100y('other_ban')
                     and (select banned_until_before::text from public.staff_login_blocks
                           where user_id = pg_temp.fx('other_ban')) = pg_temp.kept('ban'),
  'other ban: the shorter ban is replaced while the profile is closed, and remembered');
select pg_temp.run('owner', $q$update public.profiles set is_active = true where id = pg_temp.fx('other_ban')$q$, 'ok',
  'other ban: and ticks Active again');
select pg_temp.check(pg_temp.ban('other_ban')::text = pg_temp.kept('ban') and pg_temp.ban('other_ban') > now(),
  'other ban: the earlier ban is put back, not lifted');

select pg_temp.run('owner', $q$update public.profiles set is_active = false where id = pg_temp.fx('changed_ban')$q$, 'ok',
  'changed ban: an Owner switches someone off');
update auth.users set banned_until = now() + interval '5 days' where id = pg_temp.fx('changed_ban');
select pg_temp.keep('ban', pg_temp.ban('changed_ban')::text);
select pg_temp.run('owner', $q$update public.profiles set is_active = true where id = pg_temp.fx('changed_ban')$q$, 'ok',
  'changed ban: their ban is changed by hand, then Active is ticked again');
select pg_temp.check(pg_temp.ban('changed_ban')::text = pg_temp.kept('ban') and pg_temp.reason('changed_ban') is null
                     and (select (a.new_data->>'ban_lifted')::boolean from public.audit_logs a
                           where a.record_id = pg_temp.fx('changed_ban') and a.action = 'staff_login_unblocked') = false,
  'changed ban: the ban changed by hand is left as it is (and the audit row says nothing was lifted)');

select pg_temp.run('owner', $q$update public.profiles set is_active = false where id = pg_temp.fx('lifted_ban')$q$, 'ok',
  'lifted ban: an Owner switches someone off');
update auth.users set banned_until = null where id = pg_temp.fx('lifted_ban');
select pg_temp.run('service', $q$update public.profiles set deleted_at = now() where id = pg_temp.fx('lifted_ban')$q$, 'ok',
  'lifted ban: their ban is lifted by hand, then the profile is removed');
select pg_temp.check(pg_temp.blocked_100y('lifted_ban') and pg_temp.reason('lifted_ban') = 'removed',
  'lifted ban: the next closing change bans the login again');
select pg_temp.run('server', $q$update public.profiles set deleted_at = null, is_active = true
    where id = pg_temp.fx('lifted_ban')$q$, 'ok', 'lifted ban: the SQL editor restores and reactivates it');
select pg_temp.check(pg_temp.ban('lifted_ban') is null and pg_temp.reason('lifted_ban') is null, 'lifted ban: and the ban goes');

select pg_temp.keep('ban', pg_temp.ban('long_ban')::text);
select pg_temp.run('owner', $q$update public.profiles set is_active = false where id = pg_temp.fx('long_ban')$q$, 'ok',
  'long ban: an Owner switches off someone banned for two hundred years');
select pg_temp.check(pg_temp.ban('long_ban')::text = pg_temp.kept('ban') and pg_temp.sessions('long_ban') = 0
                     and (select banned_until_set is null and banned_until_before::text = pg_temp.kept('ban')
                            from public.staff_login_blocks where user_id = pg_temp.fx('long_ban')),
  'long ban: the longer ban is left exactly as it is (the sessions still end)');
select pg_temp.sync('long_ban', 'already_blocked', 'long ban: a second run answers already_blocked');
select pg_temp.run('owner', $q$update public.profiles set is_active = true where id = pg_temp.fx('long_ban')$q$, 'ok',
  'long ban: Active is ticked again');
select pg_temp.check(pg_temp.ban('long_ban')::text = pg_temp.kept('ban') and pg_temp.reason('long_ban') is null,
  'long ban: a ban it did not place is not lifted');

-- The longer ban lifted by hand while the profile is closed: 412 placed no
-- ban (its record keeps none written, and the longer one as "before"), so
-- reopening must not put the lifted ban back.
select pg_temp.run('owner', $q$update public.profiles set is_active = false where id = pg_temp.fx('lifted_long_ban')$q$, 'ok',
  'lifted long ban: an Owner switches off someone banned for two hundred years');
select pg_temp.check((select banned_until_set is null and banned_until_before > now() + interval '199 years'
                        from public.staff_login_blocks where user_id = pg_temp.fx('lifted_long_ban')),
  'lifted long ban: the record says no ban was written, and keeps the longer one as before');
update auth.users set banned_until = null where id = pg_temp.fx('lifted_long_ban');
select pg_temp.run('owner', $q$update public.profiles set is_active = true where id = pg_temp.fx('lifted_long_ban')$q$, 'ok',
  'lifted long ban: the admin lifts that ban by hand, then Active is ticked again');
select pg_temp.check(pg_temp.ban('lifted_long_ban') is null and pg_temp.reason('lifted_long_ban') is null
                     and (select (a.new_data->>'ban_lifted')::boolean from public.audit_logs a
                           where a.record_id = pg_temp.fx('lifted_long_ban') and a.action = 'staff_login_unblocked') = false,
  'lifted long ban: the ban lifted by hand is not put back, and the record goes');

-- ── 9. Affiliates and logins with no profile ─────────────────────────────────
select pg_temp.sync('affiliate', 'no_profile', 'affiliate: an affiliate''s login has no profile, so nothing is done');
select pg_temp.sync('no such key', 'no_profile', 'affiliate: a login that does not exist is not an error');
select pg_temp.check(pg_temp.sessions('affiliate') = 2 and pg_temp.ban('affiliate') is null
                     and pg_temp.reason('affiliate') is null,
  'affiliate: after every step above, the affiliate''s sessions and login are untouched');

-- ── 10. Who may do what ──────────────────────────────────────────────────────
select pg_temp.run(w, $q$select public.staff_login_sync(pg_temp.fx('owner'))$q$, '42501', 'grants: ' || w || ' cannot call the helper'),
       pg_temp.run(w, $q$select count(*) from public.staff_login_blocks$q$, '42501', 'grants: ' || w || ' cannot read the record'),
       pg_temp.run(w, $q$delete from public.staff_login_blocks$q$, '42501', 'grants: ' || w || ' cannot delete a record'),
       pg_temp.run(w, $q$insert into public.staff_login_blocks (user_id, reason) values (pg_temp.fx('owner'), 'deactivated')$q$,
                   '42501', 'grants: ' || w || ' cannot write a record')
  from unnest(array['owner', 'staff_c', 'affiliate', 'anon']) w;
select pg_temp.run('service', $q$select count(*) from public.staff_login_blocks$q$, 'ok', 'grants: the service role reads the record');
select pg_temp.run('service', $q$delete from public.staff_login_blocks$q$, '42501', 'grants: the service role cannot delete a record');
select pg_temp.run('service', $q$select public.staff_login_sync(gen_random_uuid())$q$, 'ok', 'grants: the service role may run the helper (339)');
select pg_temp.run('owner', $q$update public.profiles set deleted_at = now() where id = pg_temp.fx('staff_c')$q$, '42501',
  '407: a browser still cannot set a deleted date');
select pg_temp.run('staff_c', $q$update public.profiles set is_active = false where id = pg_temp.fx('staff_c')$q$, '42501',
  '407: nobody switches themselves off');
select pg_temp.run('owner', $q$update public.profiles set is_active = true where id = pg_temp.fx('invitee_cancel')$q$, '42501',
  '407: ticking Active on a cancelled invitee is still refused');
select pg_temp.run('staff_a', $q$update public.profiles set is_active = false where id = pg_temp.fx('staff_c')$q$, 'ok',
  '407: Staff saving someone else changes no row');
select pg_temp.check(pg_temp.active('staff_c') and pg_temp.reason('staff_c') is null and pg_temp.ban('staff_c') is null
                     and pg_temp.reason('invitee_cancel') = 'invitation_cancelled',
  '407: so those refusals blocked nobody, and the cancelled invitee stays blocked');

-- ── 11. The repair script ────────────────────────────────────────────────────
-- Profiles closed before 412: made with the trigger off, as before 412.
alter table public.profiles disable trigger staff_login_follows_profile;
insert into public.profiles (id, full_name, email, role, is_active, invitation_status)
values (pg_temp.fx('old_closed'), '412T old_closed', '412t-old_closed@sig.invalid', 'staff', false, null),
       (pg_temp.fx('old_pending'), '412T old_pending', '412t-old_pending@sig.invalid', 'staff', false, 'pending');
alter table public.profiles enable trigger staff_login_follows_profile;
select pg_temp.open_sessions('old_closed'); select pg_temp.open_sessions('old_pending');
select pg_temp.check(pg_temp.ban('old_closed') is null and pg_temp.sessions('old_closed') = 2,
  'repair: setup (a profile closed before 412, with two sessions)');
\ir ../repair/412-block-existing-closed.sql
select pg_temp.check(pg_temp.sessions('old_closed') = 0 and pg_temp.blocked_100y('old_closed') and pg_temp.reason('old_closed') = 'deactivated'
                     and pg_temp.audits('old_closed', 'staff_login_blocked') = 1,
  'repair: a profile closed before 412 is signed out and blocked');
select pg_temp.check(pg_temp.sessions('old_pending') = 2 and pg_temp.ban('old_pending') is null
                     and pg_temp.sessions('affiliate') = 2 and pg_temp.ban('affiliate') is null
                     and pg_temp.sessions('owner') = 2 and pg_temp.ban('owner') is null,
  'repair: a pending invitee, an open profile and an affiliate are left alone');
select pg_temp.keep('state', pg_temp.state());
\ir ../repair/412-block-existing-closed.sql
select pg_temp.check(pg_temp.kept('state') = pg_temp.state(), 'repair: a second run changes nothing');

-- ── 12. The catalogue ────────────────────────────────────────────────────────
select pg_temp.check(not has_function_privilege(r, f, 'execute'), 'grants: ' || r || ' cannot execute ' || f)
  from unnest(array['anon', 'authenticated']) r,
       unnest(array['public.staff_login_sync(uuid)', 'public.trg_staff_login_follows_profile()']) f;
select pg_temp.check(has_function_privilege('service_role', 'public.staff_login_sync(uuid)', 'execute')
                     and has_function_privilege('service_role', 'public.trg_staff_login_follows_profile()', 'execute'),
  'grants: the service role executes both (339)');
select pg_temp.check(not has_table_privilege(r, 'public.staff_login_blocks', 'select,insert,update,delete,truncate,references,trigger'),
  'grants: ' || r || ' has no right on staff_login_blocks') from unnest(array['anon', 'authenticated']) r;
select pg_temp.check(has_table_privilege('service_role', 'public.staff_login_blocks', 'select')
                     and not has_table_privilege('service_role', 'public.staff_login_blocks', 'insert,update,delete,truncate,references,trigger'),
  'grants: the service role only reads staff_login_blocks');
select pg_temp.check((select p.prosecdef and p.proconfig = array['search_path=public']
                        and pg_get_userbyid(p.proowner) = (select pg_get_userbyid(q.proowner) from pg_proc q
                                                            where q.oid = 'public.current_user_role()'::regprocedure)
                        from pg_proc p where p.oid = f::regprocedure),
  'catalogue: ' || f || ' runs with its owner''s rights (the owner of 406''s functions), search_path public')
  from unnest(array['public.staff_login_sync(uuid)', 'public.trg_staff_login_follows_profile()']) f;
select pg_temp.check((select relrowsecurity from pg_class where oid = 'public.staff_login_blocks'::regclass)
                     and not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'staff_login_blocks'),
  'table: row level security on, no rule');
select pg_temp.check((select string_agg(pg_get_triggerdef(t.oid), '|' order by t.tgname) from pg_trigger t
                       where t.tgrelid = 'public.profiles'::regclass and not t.tgisinternal and t.tgenabled = 'O')
  = 'CREATE TRIGGER guard_profile_privileges BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION trg_guard_profile_privileges()|'
    || 'CREATE TRIGGER staff_login_follows_profile AFTER INSERT OR UPDATE OF is_active, deleted_at, invitation_status ON public.profiles FOR EACH ROW EXECUTE FUNCTION trg_staff_login_follows_profile()',
  'trigger: the guard before, this after; both enabled');
select pg_temp.check(not exists (select 1 from auth.users u join fx on fx.id = u.id
                                  where u.banned_until is not null and not isfinite(u.banned_until)),
  'no login was ever given an infinite ban');

-- A deleted login takes its record with it.
select pg_temp.check(pg_temp.reason('staff_b') is not null, 'cascade: setup');
delete from auth.users where id = pg_temp.fx('staff_b');
select pg_temp.check(not exists (select 1 from public.staff_login_blocks where user_id = pg_temp.fx('staff_b')),
  'cascade: deleting a login deletes its record');

select pg_temp.check(true, 'deactivated-login-blocked: all passed');
rollback;
