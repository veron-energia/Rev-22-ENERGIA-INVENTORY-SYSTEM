-- UNDO of 526 (with the user's go-ahead). It puts event_web_guest_extras back to its text before
-- 526 (md5 03358fda…, as 449 left it): the Guests tab's list carries each website person's VIP
-- upgrade token again, for any staff login that can run the event, with no Audit Log row. It
-- drops event_web_key_check and event_web_vip_link. The grants of event_web_guest_extras stay as
-- they are; the Audit Log rows 526's function wrote stay.
--
-- FIRST put back the event-website function and the page of before 526: the function of 526
-- calls event_web_key_check before every message (without it, it answers 503 retry to all of
-- them), and the page's "Copy VIP link" calls event_web_vip_link.
--
-- It refuses, with nothing changed, unless the three functions are exactly 526's versions (so a
-- later version is never overwritten). One transaction, all or nothing; it waits at most 5
-- seconds for a lock. The 526 row in supabase_migrations.schema_migrations stays; with the
-- user's OK, remove that one row (found by its name, 526_a_vip_link_is_read_one_at_a_time) or
-- record this UNDO beside it.
--
-- The patch texts below are 526's, the other way round: each 526 text is found exactly once and
-- put back as it was.
do $undo$
declare
  c_sig constant text := 'event_web_guest_extras(uuid)';
  c_526 constant text := '1e1af232acf928680d5f630c63541002';
  c_before_526 constant text := '03358fda2da1b4fda082e3f29b512a38';
  c_new_sig constant text[] := array['event_web_key_check(text)', 'event_web_vip_link(uuid,uuid)'];
  c_new_md5 constant text[] := array['d86522bca42a63007dde3b93d8d84758', 'aa91b87f6b11549a9c216e58e03eb414'];
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

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_acl text;
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  if to_regprocedure('public.' || c_sig) is null then raise exception 'UNDO 526: public.% is missing', c_sig; end if;
  d := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  if md5(d) <> c_526 then
    raise exception 'UNDO 526: public.% is not 526''s version (md5 %). Nothing changed.', c_sig, md5(d); end if;
  v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig));
  for i in 1 .. cardinality(c_new) loop
    if (length(d) - length(replace(d, c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'UNDO 526: patch % does not find 526''s text exactly once in public.%', i, c_sig; end if;
    d := replace(d, c_new[i], c_anchor[i]);
  end loop;
  if md5(d) <> c_before_526 then
    raise exception 'UNDO 526: the text put back is not the one before 526 (md5 %). Nothing changed.', md5(d); end if;
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception 'UNDO 526: public.% is missing or not 526''s version. Nothing changed.', c_new_sig[i]; end if;
  end loop;

  -- 2. Put back
  execute d;
  for i in 1 .. cardinality(c_new_sig) loop
    execute format('drop function public.%s', c_new_sig[i]);
  end loop;

  -- 3. Checks after
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_before_526 then
    raise exception 'UNDO 526: public.% was put back with an md5 other than the one before 526', c_sig; end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig)) is distinct from v_acl then
    raise exception 'UNDO 526: the grants of public.% changed', c_sig; end if;
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is not null then
      raise exception 'UNDO 526: public.% is still there', c_new_sig[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
