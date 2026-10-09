-- 405_pause_affiliate_signup.sql
--
-- WHY (the Owner, 9 Oct 2026)
--
--   The audit of 8-9 Oct 2026 found that many database functions treat any
--   signed-in login as staff, and anyone can create a login through the
--   affiliate sign-up page (/affiliate/join). Until the security fix (406
--   and after) is live, the Owner chose to pause public affiliate sign-up so
--   that no new outside accounts are created.
--
--   The sign-up page creates accounts through the edge function
--   auth-signup-request, which first reserves a rate-limit slot with
--   auth_email_reserve and only then has Supabase create the account and
--   mint the verification link. The resend (auth-resend-verification) does
--   the same before minting a fresh link for an account not yet verified.
--   (Supabase's own public sign-up endpoint is switched off separately, in
--   the project's Auth settings, by the Owner.)
--
-- WHAT THIS DOES
--
--   * auth_email_pauses (new): the email actions that are paused, one row
--     each, with when and why. Row level security on, no policies, no grants
--     to clients: only the database's own functions read it.
--   * auth_email_reserve (patched): a paused action is refused before any
--     slot is taken: it raises AUTH_EMAIL_PAUSED. The edge functions treat a
--     limiter that cannot answer as "fail closed" and answer the page with
--     503 "We could not process that request just now. Please try again
--     shortly." Nothing is created and no email is sent.
--   * Pauses 'signup' and 'resend'. 'recovery' (password reset for an
--     existing account) is not paused, so existing affiliates and staff can
--     still reset their passwords.
--
-- TO REOPEN SIGN-UP (with the Owner's go-ahead, once the security fix is
-- live): delete from public.auth_email_pauses where action in ('signup',
-- 'resend'); no migration is needed.
--
-- NOT CHANGED
--
--   * Existing logins, staff invitations (admin-invite-user uses Supabase's
--     admin invite, not this limiter), password recovery, the referral
--     sign-up page (/r/:code, which creates customers, not logins), the rate
--     limits themselves and every grant: auth_email_reserve keeps the grants
--     it has (the security fix deals with those).
--
-- SAFETY
--
--   One DO block, so atomic. auth_email_reserve must be the version read on
--   9 Oct 2026 (BEFORE) or already this one (AFTER, left alone); the anchor
--   must match exactly once. The table and its rows are added only if
--   missing, so a re-run changes nothing. After installing, the function has
--   its AFTER md5 and the grants it had.
--
-- BEFORE (production, 9 Oct 2026, md5 of pg_get_functiondef):
--   auth_email_reserve(text,text,text)  9ce9f2f3268c0a7bc52b70abaed29fbb
-- AFTER:
--   auth_email_reserve(text,text,text)  e391dd051d05f0661c7924f24e04a1b2
--
-- Test: scripts/permissions/tests/auth-email-pause.sql (begin ... rollback).

set lock_timeout = '5s';

do $mig$
declare
  c_fn constant text := 'public.auth_email_reserve(text,text,text)';
  c_before constant text := '9ce9f2f3268c0a7bc52b70abaed29fbb';
  c_after constant text := 'e391dd051d05f0661c7924f24e04a1b2';
  c_anchor constant text :=
       E'  if p_email_hash is null or length(btrim(p_email_hash)) = 0 then\n'
    || E'    raise exception ''AUTH_EMAIL_MISSING_EMAIL_KEY'';\n'
    || E'  end if;\n';
  c_patch constant text :=
       E'  if p_email_hash is null or length(btrim(p_email_hash)) = 0 then\n'
    || E'    raise exception ''AUTH_EMAIL_MISSING_EMAIL_KEY'';\n'
    || E'  end if;\n'
    || E'  -- 405: a paused action (the Owner, 9 Oct 2026: public affiliate sign-up\n'
    || E'  -- paused until the security fix is live) is refused before any slot is\n'
    || E'  -- taken. The edge functions fail closed on this: nothing is created or sent.\n'
    || E'  if exists (select 1 from public.auth_email_pauses ps where ps.action = p_action) then\n'
    || E'    raise exception ''AUTH_EMAIL_PAUSED: %'', p_action;\n'
    || E'  end if;\n';
  v_path text := current_setting('search_path');
  d text; v text; n int; v_acl text;
begin
  perform set_config('search_path', 'public', true);

  create table if not exists public.auth_email_pauses (
    action text primary key check (action in ('signup', 'resend', 'recovery')),
    paused_at timestamptz not null default now(),
    reason text not null
  );
  alter table public.auth_email_pauses enable row level security;
  revoke all on table public.auth_email_pauses from public, anon, authenticated;
  grant all on table public.auth_email_pauses to service_role;

  select p.proacl::text into v_acl from pg_proc p where p.oid = to_regprocedure(c_fn);
  d := pg_get_functiondef(to_regprocedure(c_fn));
  v := md5(d);
  if v = c_after then
    raise notice '405: % is already this version; left alone', c_fn;
  elsif v <> c_before then
    raise exception '405: % is not the version read on 9 Oct 2026 (md5 %). Re-read it and re-test before applying.', c_fn, v;
  else
    n := (length(d) - length(replace(d, c_anchor, ''))) / length(c_anchor);
    if n <> 1 then
      raise exception '405: the anchor of % was found % times, not once', c_fn, n; end if;
    execute replace(d, c_anchor, c_patch);
  end if;

  insert into public.auth_email_pauses (action, reason)
  values ('signup', 'Public affiliate sign-up paused until the security fix is live (the Owner, 9 Oct 2026)'),
         ('resend', 'Verification resends paused with sign-up (the Owner, 9 Oct 2026)')
  on conflict (action) do nothing;

  if md5(pg_get_functiondef(to_regprocedure(c_fn))) <> c_after then
    raise exception '405: % installed with md5 %, not the tested %', c_fn,
      md5(pg_get_functiondef(to_regprocedure(c_fn))), c_after; end if;
  if (select p.proacl::text from pg_proc p where p.oid = to_regprocedure(c_fn)) is distinct from v_acl then
    raise exception '405: the grants of % changed', c_fn; end if;
  if has_table_privilege('anon', 'public.auth_email_pauses', 'select')
     or has_table_privilege('authenticated', 'public.auth_email_pauses', 'select') then
    raise exception '405: public.auth_email_pauses is readable by a client role'; end if;

  perform set_config('search_path', v_path, true);
end $mig$;
