-- 525_the_sign_up_makes_no_email_hint.sql
--
-- THE AFFILIATE SIGN-UP MAKES NO HINT OF ANYONE'S LOGIN EMAIL
--
--   From the security audit of 17 Nov 2026 (finding L9, part 1).
--   The BEFORE md5 below was compared with production on 18 Nov 2026 (head 523) and
--   matches. If production differs when this is applied, it refuses and changes nothing.
--   (The number 525 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone, and in the suite's name.)
--
-- WHAT WAS WRONG
--
--   A sign-up whose phone belongs to an existing affiliate was answered with a masked hint
--   of that affiliate's login email (the first letter, then ***@ and the domain). Anyone who
--   knew a phone number could read part of its owner's email (466, the Owner's choice of
--   24 Oct 2026).
--
-- THE RULE (the user, 18 Nov 2026)
--
--   Drop the hint. The sign-up still says that the phone or the email already has an
--   affiliate account and sends the person to Sign in, or Reset password.
--
-- WHAT THIS DOES
--
--   affiliate_signup_existing() makes no hint any more: its email_hint is always null, and
--   the Audit Log row it writes for each try says email_hint_shown false. The sign-up
--   function (auth-signup-request) and the pages no longer read or show one either (the same
--   change, in supabase/functions/_shared/auth-email and src/lib/auth-email/client.mjs), so
--   even an older copy of the function would find none to show.
--
-- WHAT THIS LEAVES ALONE
--
--   Everything else the function answers and logs (which kind matched, the login-email
--   flag, the Audit Log rows), its grants (the service role only), and the earlier Audit
--   Log rows, which keep what they said.
--
-- UNDO
--
--   Run this block with c_before and c_after swapped and c_anchor and c_new swapped. A later
--   migration changing affiliate_signup_existing must pin 525's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/affiliate-signup/tests/no-email-hint-525.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  c_sig constant text[] := array[
    'affiliate_signup_existing(text,text,text,uuid)'];
  c_before constant text[] := array[
    '27e3b1ad5a583bc6421d783b5a7db45a'];
  c_after constant text[] := array[
    '6df6e72e2942db0ea39818666a68bf57'];
  c_fn constant int[] := array[1];
  c_anchor constant text[] := array[
$a$  -- A hint of the one login's email, when the email typed is not it: the
  -- first character of the part before the @, then ••• and the whole domain.
  if cardinality(v_logins) = 1 and not v_login_email then
    select h ->> 'login_email' into v_login from jsonb_array_elements(v_hits) h
     where (h ->> 'auth_user_id')::uuid = v_logins[1] limit 1;
    v_local := substring(v_login from '^(.*)@[^@]*$');
    v_domain := substring(v_login from '@([^@]*)$');
    if v_local is not null and coalesce(v_domain, '') <> '' then
      v_hint := case when char_length(v_local) > 1 then left(v_local, 1) else '' end || '•••@' || v_domain;
    end if;
  end if;
  -- Only a hint of the shape the sign-up function shows (its EMAIL_HINT_RE,
  -- in ASCII here) is given, so the Audit Log says a hint was shown only
  -- when it was.
  if v_hint is not null
     and not (char_length(v_hint) <= 256
              and v_hint ~ '^[!-~]?•••@[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$'
              and v_hint !~ '^[@<>"''`\\]') then
    v_hint := null;
  end if;
$a$];
  c_new constant text[] := array[
$n$  -- 525 (security audit of 17 Nov 2026, L9; the user, 18 Nov 2026): no hint of anyone's
  -- login email is made any more. The sign-up page shows none, and the Audit Log's
  -- email_hint_shown below is false.
  v_hint := null;
$n$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[1]);
  v_make boolean[] := array_fill(false, array[1]);
  v_acl text[] := array_fill(null::text, array[1]);
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '525: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '525: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '525: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '525: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '525: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '525: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '525: the grants of public.% changed', c_sig[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
