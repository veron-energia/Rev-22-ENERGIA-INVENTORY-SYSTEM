-- 526_a_vip_link_is_read_one_at_a_time.sql
--
-- A PERSON'S VIP LINK IS READ ONE AT A TIME, AND EACH READ IS IN THE AUDIT LOG;
-- THE WEBSITE'S KEY IS CHECKED BEFORE ITS MESSAGE IS READ
--
--   From the security audit of 17 Nov 2026 (finding L11).
--   The BEFORE md5 and the relied-on md5s below are those of production after 525 (the local
--   copy of 18 Nov 2026). If production differs when this is applied, it refuses and changes
--   nothing.
--   (The number 526 is this file's name and its errors' prefix; if it changes at commit,
--   change it there, in the 526 comments it writes into the three functions (and so their
--   md5s, also in scripts/event-website/undo-526.sql), in the name and path of its suite, and
--   in the suites that look for '526:' in event_web_guest_extras.)
--
-- WHAT WAS WRONG
--
--   1. event_web_guest_extras, which the Event page's Guests tab reads, gave every website
--      person's VIP upgrade token (their link to buy VIP, change their answers and read their
--      registration) to any staff login that can run the event: the whole list at once, with
--      no record of who read it.
--   2. The event-website function read and parsed a message's body before the database had
--      checked its key: anyone could make it parse 16 KiB of JSON with a key of the right
--      shape. (Its timestamp is bound to nothing, so a captured request can be sent again for
--      five minutes; signing requests waits until after the Christmas event of 20 Dec 2026,
--      because the live website would have to change. Not part of this.)
--
-- THE RULES (the user, 18 Nov 2026)
--
--   * "Copy VIP link" fetches ONE guest's link per click, and each fetch writes an Audit Log
--     row (who, which guest and person, when). The guest list stops carrying tokens. The
--     button works as before otherwise.
--   * The event-website function checks the key BEFORE it reads or parses the body. No
--     change to the website.
--
-- WHAT THIS DOES
--
--   * event_web_guest_extras: a website person's rows say 'upgrade_token' null always, and
--     'vip_link_ready': true when "Copy VIP link" may be offered (the rule the token was given
--     by: not closed, VIP none or refunded, and a token). A VIP sold at the counter has
--     'vip_link_ready' false. 'upgrade_token' stays in the rows, null, so an older page simply
--     hides its button.
--   * event_web_vip_link(event, person), for signed-in staff who can run the event (the same
--     check and 42501 as the list's): for a person of that event for whom vip_link_ready
--     holds, one Audit Log row (event_web_vip_link_copied, on event_registration_people, the
--     person; the event, the person's free and VIP guest records, never the token; the
--     website's store) and {ok: true, upgrade_token}. Anyone else (closed, VIP paid or
--     pending, another event's person, no one) gets {ok: false, reason: 'not_available'} and
--     nothing is written.
--   * event_web_key_check(key hash), for the service role only: the same three refusals as
--     event_web_call (a key unknown or revoked, an event with no website settings, a deleted
--     event: {ok: false, error: 'bad_key'}), else {ok: true}. It only reads. The event-website
--     function (supabase/functions/event-website/handler.ts) calls it before reading the body.
--
-- WHAT THIS LEAVES ALONE
--
--   * event_web_call (it still checks the key itself, and keeps last_used_at), the website and
--     its contract, the tokens themselves (no token changes; links already sent work).
--   * Everything else event_web_guest_extras answers, and its grants (signed-in staff, the
--     service role). The website's own person read, VIP checkout and answers.
--   * The Audit Log rows already written.
--
-- ORDER OF GOING LIVE
--
--   This first; then the event-website function (it calls event_web_key_check: before this it
--   would answer 503 retry to every request); then the page (it calls event_web_vip_link).
--   Between this and the page, the page in use shows no "Copy VIP link" (no token comes).
--
-- UNDO
--
--   First put back the event-website function and the page of before 526 (they call the two
--   functions this makes). Then scripts/event-website/undo-526.sql (it refuses unless the
--   three functions are 526's versions): event_web_guest_extras is put back as it was, and
--   event_web_key_check and event_web_vip_link are dropped. The Audit Log rows stay. A later
--   migration changing event_web_guest_extras must pin 526's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/event-website/tests/vip-link-one-at-a-time-526.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Functions the new ones rely on, as tested.
  c_relied constant text[] := array[
    'require_active_staff(text[])',
    'event_can_run(uuid)',
    'event_web_person_vip_state(uuid)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'event_web_call(text,uuid,text,jsonb)'];
  c_relied_md5 constant text[] := array[
    '877b3aa74cea559881979bb161c450e2',
    'dac12d0086533bb528e847eb828809df',
    'fc0a3c9ce094fe72e69cff7f420837b6',
    'c705c733e213a27f0dc32d54322cc855',
    'e114ba39de4923cc52ed426e27d9bfde'];
  -- The function patched.
  c_sig constant text[] := array[
    'event_web_guest_extras(uuid)'];
  c_before constant text[] := array[
    '03358fda2da1b4fda082e3f29b512a38'];
  c_after constant text[] := array[
    '1e1af232acf928680d5f630c63541002'];
  -- Two patches of the one function, each found exactly once.
  c_fn constant int[] := array[1, 1];
  c_anchor constant text[] := array[
$a$                 'upgrade_token', case when p.match <> 'closed' and public.event_web_person_vip_state(p.id) in ('none', 'refunded')
                                       then p.upgrade_token end,
$a$,
$a$                 'hold', null, 'closed', false, 'match', null, 'typed_email', null, 'referral', null, 'upgrade_token', null,
$a$];
  c_new constant text[] := array[
$n$                 -- 526 (security audit of 17 Nov 2026, L11; the user, 18 Nov 2026): the list carries no
                 -- one's VIP link token any more (every staff login that can run the event could read
                 -- them all). vip_link_ready says "Copy VIP link" may be offered (not closed, not VIP, a
                 -- token); the page asks event_web_vip_link for one person's token per click, which
                 -- writes an Audit Log row. upgrade_token stays, always null, so an older page simply
                 -- hides its button.
                 'upgrade_token', null,
                 'vip_link_ready', coalesce(p.match <> 'closed' and public.event_web_person_vip_state(p.id) in ('none', 'refunded')
                                            and p.upgrade_token is not null, false),
$n$,
$n$                 'hold', null, 'closed', false, 'match', null, 'typed_email', null, 'referral', null, 'upgrade_token', null,
                 'vip_link_ready', false, -- 526: a VIP sold at the counter has no VIP link
$n$];
  -- The new functions.
  c_new_sig constant text[] := array[
    'event_web_key_check(text)',
    'event_web_vip_link(uuid,uuid)'];
  c_new_md5 constant text[] := array[
    'd86522bca42a63007dde3b93d8d84758',
    'aa91b87f6b11549a9c216e58e03eb414'];
  c_new_grantees constant text[] := array[
    'service_role',
    'authenticated, service_role'];
  c_new_acl constant text[] := array[
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'];
  c_new_def constant text[] := array[
$def$CREATE OR REPLACE FUNCTION public.event_web_key_check(p_key_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_event uuid;
begin
  -- 526 (security audit of 17 Nov 2026, L11; the user, 18 Nov 2026): the event-website
  -- function asks this before it reads the body, so a request without a working key is
  -- refused before any of it is parsed. The same three refusals as event_web_call, with
  -- the same one answer (bad_key) for each: a key unknown or revoked, a key whose event
  -- has no website settings, a key of a deleted event. It only reads (last_used_at is
  -- event_web_call's), and event_web_call still checks the key itself.
  select k.event_id into v_event from public.event_web_keys k where k.key_hash = p_key_hash and k.revoked_at is null;
  if not found then return jsonb_build_object('ok', false, 'error', 'bad_key'); end if;
  if not exists (select 1 from public.event_web_settings s where s.event_id = v_event) then
    return jsonb_build_object('ok', false, 'error', 'bad_key'); end if;
  if exists (select 1 from public.events e where e.id = v_event and e.deleted_at is not null) then
    return jsonb_build_object('ok', false, 'error', 'bad_key'); end if;
  return jsonb_build_object('ok', true);
end $function$
$def$,
$def$CREATE OR REPLACE FUNCTION public.event_web_vip_link(p_event_id uuid, p_person_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.event_registration_people%rowtype;
begin
  -- 526 (security audit of 17 Nov 2026, L11; the user, 18 Nov 2026): "Copy VIP link" on the
  -- Guests tab asks for one person's VIP link token here, one click at a time, and each
  -- answer that gives a token writes an Audit Log row (who, which person and guest records,
  -- when). The guest list (event_web_guest_extras) no longer carries any token.
  perform public.require_active_staff();
  if not public.event_can_run(p_event_id) then
    raise exception 'You do not have access to this event' using errcode = '42501'; end if;
  select * into p from public.event_registration_people x where x.id = p_person_id and x.event_id = p_event_id;
  -- The same rule as the list's vip_link_ready: not closed, not VIP (none or refunded), a
  -- token. Someone of another event, or no one, gets the same answer, and nothing is written.
  if not found or p.match = 'closed' or p.upgrade_token is null
     or coalesce(public.event_web_person_vip_state(p.id) not in ('none', 'refunded'), true) then
    return jsonb_build_object('ok', false, 'reason', 'not_available');
  end if;
  -- The Audit Log row names the person and their guest records, never the token.
  perform public.write_audit_ex('event_registration_people', p.id, 'event_web_vip_link_copied', null,
    jsonb_build_object('event_id', p_event_id, 'person_id', p.id, 'free_guest_id', p.free_guest_id,
                       'vip_guest_id', p.vip_guest_id, 'position', p.position, 'is_test', p.is_test),
    'events', null, (select s.store_id from public.event_web_settings s where s.event_id = p_event_id));
  return jsonb_build_object('ok', true, 'upgrade_token', p.upgrade_token);
end $function$
$def$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[1]);
  v_make boolean[] := array_fill(false, array[1]);
  v_acl text[] := array_fill(null::text, array[1]);
  v_make_new boolean[] := array_fill(false, array[2]);
  d text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy table or function waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '526: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '526: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '526: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '526: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '526: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '526: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;
  -- The new functions: missing (made), or 526's already with its rights (left alone).
  for i in 1 .. cardinality(c_new_sig) loop
    if md5(c_new_def[i]) <> c_new_md5[i] then
      raise exception '526: the text of public.% in this file is not the tested one (md5 %)', c_new_sig[i], md5(c_new_def[i]); end if;
    if to_regprocedure('public.' || c_new_sig[i]) is null then
      v_make_new[i] := true;
    elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) = c_new_md5[i]
          and (select coalesce(string_agg(x::text, ',' order by x::text), '')
                 from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new_sig[i])) = c_new_acl[i] then
      raise notice '526: public.% is already there; left alone', c_new_sig[i];
    else
      raise exception '526: a function public.% is there, but not 526''s. Re-read it before applying.', c_new_sig[i];
    end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_new_sig) loop
    if v_make_new[i] then
      execute c_new_def[i];
      execute format('revoke all on function public.%s from public, anon, authenticated, service_role', c_new_sig[i]);
      execute format('grant execute on function public.%s to %s', c_new_sig[i], c_new_grantees[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '526: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '526: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception '526: public.% was installed with an md5 other than the tested one (md5 %)', c_new_sig[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new_sig[i])) is distinct from c_new_acl[i] then
      raise exception '526: the rights on public.% are not the tested ones', c_new_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '526: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
