-- 412 repair: block the logins of the staff profiles that were already closed
-- when 412 went live.
--
-- 412's trigger makes a login follow its profile from the moment 412 is in;
-- it does not look back. On 9 Oct 2026 production had one such profile: a
-- deactivated member of staff (no open session, not banned). This calls
-- staff_login_sync, the helper the trigger calls, for every profile that is
-- closed now: deactivated, removed (a deleted date) or whose invitation was
-- cancelled. Their sessions are ended and their logins banned, and each block
-- is recorded and audited as the trigger would. A pending invitee, an open
-- profile and every affiliate login are left alone.
--
-- Run it once, after 412, as the database owner (the SQL editor, the MCP
-- execute_sql tool, or psql as postgres). It is one statement, so it is
-- atomic. A second run changes nothing. It prints counts only (a notice),
-- never a name or an address. Expected on production (9 Oct 2026): 1 closed
-- profile, 1 blocked now, 0 already blocked.
--
-- To check afterwards (counts only):
--   select count(*) filter (where u.banned_until > now() + interval '99 years') as banned,
--          count(*) filter (where exists (select 1 from auth.sessions s where s.user_id = p.id)) as with_sessions,
--          count(*) filter (where b.user_id is not null) as recorded
--     from public.profiles p join auth.users u on u.id = p.id
--     left join public.staff_login_blocks b on b.user_id = p.id
--    where p.deleted_at is not null
--       or coalesce(p.invitation_status, 'accepted') not in ('accepted', 'pending')
--       or (not p.is_active and coalesce(p.invitation_status, 'accepted') = 'accepted');
--   -- expected: banned = recorded = the number of closed profiles, with_sessions = 0

do $repair$
declare
  c_sync_after constant text := '7648388b0b41caee3696694ae172377e';  -- staff_login_sync(uuid), 412's AFTER
  v_path text := current_setting('search_path');
  r record; v text; n_closed int := 0; n_blocked int := 0; n_already int := 0; n_bad int;
begin
  perform set_config('search_path', 'public', true);
  if to_regprocedure('public.staff_login_sync(uuid)') is null
     or md5(pg_get_functiondef(to_regprocedure('public.staff_login_sync(uuid)'))) <> c_sync_after then
    raise exception '412 repair: 412 is not in (staff_login_sync is missing or not 412''s version); apply 412 first'; end if;

  -- Closed, as staff_login_sync reads it: removed; an invitation neither
  -- accepted nor pending; or switched off with the invitation accepted (or
  -- from before invitations).
  for r in select p.id from public.profiles p
            where p.deleted_at is not null
               or coalesce(p.invitation_status, 'accepted') not in ('accepted', 'pending')
               or (not p.is_active and coalesce(p.invitation_status, 'accepted') = 'accepted')
            order by p.created_at, p.id
  loop
    n_closed := n_closed + 1;
    v := public.staff_login_sync(r.id);
    if v = 'blocked' then n_blocked := n_blocked + 1;
    elsif v = 'already_blocked' then n_already := n_already + 1;
    else raise exception '412 repair: a closed profile answered "%"; nothing was changed', v;
    end if;
  end loop;

  -- Every closed profile's login now has no session and is banned.
  select count(*) into n_bad
    from public.profiles p join auth.users u on u.id = p.id
   where (p.deleted_at is not null
          or coalesce(p.invitation_status, 'accepted') not in ('accepted', 'pending')
          or (not p.is_active and coalesce(p.invitation_status, 'accepted') = 'accepted'))
     and (u.banned_until is null or u.banned_until <= now()
          or exists (select 1 from auth.sessions s where s.user_id = p.id)
          or not exists (select 1 from public.staff_login_blocks b where b.user_id = p.id));
  if n_bad > 0 then
    raise exception '412 repair: % closed profile(s) still not blocked; nothing was changed', n_bad; end if;

  raise notice '412 repair: % closed profile(s); % blocked now, % already blocked', n_closed, n_blocked, n_already;
  perform set_config('search_path', v_path, true);
end $repair$;
