-- 531_the_affiliate_sign_up_limits_and_email_codes.sql
--
-- AFFILIATE SIGN-UP HAS LIMITS FOR EACH CONNECTION AND FOR ALL SIGN-UPS, THE SIGN-IN EMAILS HAVE
-- DAILY BUDGETS (STAFF THEIR OWN), AN EMAIL IS VERIFIED BY A CODE TYPED WHILE SIGNED IN, AND THE
-- WELCOME WHATSAPP NEVER GREETS BY A TYPED NAME AND GOES TO AT MOST 30 A DAY
--
--   From the security audit of 17 Nov 2026 (finding M6).
--   The BEFORE md5s and the relied-on md5s below are those of production after 529 (the local
--   copy of 20 Nov 2026). 530 is not needed and not touched: this applies before or after it.
--   If production differs when this is applied, it refuses and changes nothing.
--   (The number 531 is this file's name and its errors' prefix; if it changes at commit, change
--   it there, in the 531 comments it writes into the functions (and so their md5s, also in
--   scripts/affiliate-signup/undo-531.sql and in the suites that know them), and in the name and
--   path of its suite.)
--
-- WHAT WAS WRONG
--
--   The public affiliate sign-up and the sign-in emails (verify, resend, password reset) are
--   sent by Edge Functions that ask auth_email_reserve for a place first. Its limits were per
--   address and per connection only: 30 sign-ups an hour from one connection, and nothing across
--   all of them, so many connections together could make logins and send emails without end,
--   and use up the mail provider's daily allowance (after which no one gets a reset email).
--   An emailed link opened within 30 minutes marked the email verified
--   (confirm_affiliate_email): whoever held a sign-in link from that inbox, or a session made
--   from one, verified it; and the sign-up (complete_affiliate_onboarding) made a new account
--   verified when its session came from an emailed link, or when Supabase Auth had confirmed
--   the login itself, so a login made with someone's email and left without an account became
--   verified when that person opened a reset link. A verified email is one of the proofs that a
--   login is a customer record's (484's proof (d)). And the welcome WhatsApp greeted the person by the first name
--   typed at sign-up (auth.users metadata), or by a customer record's name that a public form
--   had just made from what the person typed: anyone could make Energia's WhatsApp number send
--   the words they chose to any phone, and nothing limited how many welcomes went out.
--
-- THE RULE (the user, 20 Nov 2026)
--
--   1. "10 per connection + 30 overall": a connection gets at most 10 sign-ups an hour (it was
--      30), and all sign-ups together get at most 30 new logins an hour.
--   2. "60 a day + 5 per address": the verify and reset emails together are at most 60 SENT a
--      day (a request for an address with no login sends nothing and is not counted), and any
--      one address gets at most 5 a day. "A day" is the last 24 hours (a sliding window, as
--      Gmail counts). An email a signed-in login asks for itself counts for that login's
--      address too, so one login cannot use up the 60.
--   3. "Staff get their own 20": the emails sent to an active staff login are counted in a
--      budget of their own, 20 a day, not in the 60 (a full 60 never stops a staff reset).
--   4. "Code on the Account page": the verify email carries a 6-digit code that the affiliate
--      types while signed in. No emailed link marks an email verified any more.
--   5. "No typed names": the welcome WhatsApp greets by the customer record's first name only
--      when the record was there at least 24 hours before the login; otherwise "Hi there" (a
--      customer added at the counter who signs up the same day is greeted "Hi there").
--   6. "30 welcomes a day": at most 30 welcome WhatsApps in 24 hours (every one not skipped or
--      expired counts); past that the welcome is kept as skipped ('daily_limit') and not sent,
--      then or later. The Owner's 'reactivated' messages are not counted or limited.
--
-- WHAT THIS DOES
--
--   * public.auth_email_limits: its checks allow the actions 'send' (the emails sent, all
--     together), 'send_staff' (the emails sent to staff logins) and 'email_day' (one address,
--     a day) and the scope 'all'. ('signup','ip') goes from 30 to 10 an hour (it refuses unless
--     it is 30, or already 10). Four rows are added (left alone when there): ('signup','all')
--     30 an hour, ('send','all') 60 in 24 hours, ('send_staff','all') 20 in 24 hours,
--     ('email_day','email') 5 in 24 hours.
--   * auth_email_reserve (the Edge Functions' first ask; same arguments, answers and grants):
--     a sign-up first looks at the limit for all sign-ups ('signup','all'), after the pause
--     (405) and under the same lock: full -> {allowed:false, retry_after_seconds, scope:'all',
--     action:'signup'}, and nothing is counted (a place is taken by auth_email_take once a login
--     is made). A resend or a reset also fits the address's day ('email_day', by the email's
--     key, counted like the others when it is allowed, whoever the address is); it does not
--     look at the emails' budgets here, so its answer never shows whether an address is a staff
--     login's (those are taken when the email is sent). A call with no connection key (the Edge
--     Functions before their redeploy) works as before, with the address's day added.
--   * public.auth_email_take(p_bucket, p_email_hash, p_user_id, p_recipient_hash, p_lookup_email;
--     the last four default null), new, the service role's alone: takes one place in a budget when it is used,
--     under the reserve's lock: 'signup' when a login is made (30 an hour); 'send' when an email
--     is sent: the staff budget ('send_staff', 20 a day) when p_user_id is an active staff login
--     (a profile that is active, not deleted and accepted, any role, as 406's
--     require_active_staff), else the 60. The caller names only 'signup' or 'send'; the staff
--     budget is chosen here. With the login's own address key and with a recipient's key (an
--     address the caller typed, such as a new email's code), 'send' only, each address's day
--     must have room too (the recipient's when it is another address); every place is taken only
--     when every budget has room. Full -> {allowed:false, retry_after_seconds, scope, action}
--     naming the budget that refused ('all' with 'signup', 'send' or 'send_staff'; 'email' with
--     'email_day'); else {allowed:true, retry_after_seconds:0}. With an address typed
--     (p_lookup_email, 'send' only, not with p_user_id; a reset takes its place before the link
--     is made), the login is found as auth_email_user_state finds it and chooses the budget;
--     none -> {allowed:false, retry_after_seconds:0, scope:'email', action:'no_login'}, nothing
--     counted; it adds no address's day (reserve counted it).
--   * public.affiliate_email_codes, new: one row per code sent: the login, the address it went
--     to, the sha256 of the login and the code (never the code), when it was made and ends (15
--     minutes), the wrong tries (at most 5), when it was used or retired. Row level security on,
--     no policy, every privilege revoked from public, anon, authenticated and the service role:
--     only the two functions below (running as the owner) read and write it.
--   * public.affiliate_email_code_issue(p_auth_user_id), new, the service role's alone (the
--     Edge Function passes the login from its verified token): for an affiliate's login (its
--     account 'claimed', not a staff login, its email not yet verified) it retires the login's
--     earlier codes and makes a new 6-digit code from pgcrypto's random bytes, and answers
--     {status:'issued', code, email (the login's address now), expires_in_seconds:900};
--     anything else {status:'none'}. The code is answered once, for the email, and kept only as
--     a hash.
--   * public.confirm_affiliate_email_code(p_code), new, for the signed-in login itself:
--     already verified -> {verified:true, already:true}; not six digits -> 'invalid'; no live
--     code (none, used, retired, 5 wrong tries), a code from before the login's email last
--     changed (491's login_email_changed_at), or the right code for another address than the
--     login's now -> 'no_code'; ended -> 'expired'; wrong -> 'wrong_code' with tries_left, and
--     the 5th wrong try ends it ('too_many_tries'); right -> the email is verified, with the
--     same login copy and audit entry as confirm_affiliate_email wrote -> {verified:true}. The
--     account and the code row are locked, so two tries at once are counted one after the other.
--   * confirm_affiliate_email() (same arguments, grants): no longer verifies. Already verified
--     and not an affiliate are answered as before; otherwise {verified:false,
--     reason:'use_code'}, changing nothing.
--   * complete_affiliate_onboarding (same arguments, grants), where it makes a new account only:
--     the account is verified only from the date the server keeps on the login (app_metadata
--     affiliate_email_verified_at: written when the login verified with a code, or kept from an
--     account an Owner unlinked, 378). Supabase Auth's own confirmation (email_confirmed_at) and
--     a session from an emailed link no longer verify it, and no longer write that date. Every
--     other new account starts unverified and verifies with the code. (email_confirmed_at is
--     still required before signing up, as before; an account already there is answered as
--     before.)
--   * affiliate_whatsapp_enqueue (same arguments, grants):
--       - the greeting's name never comes from the sign-up (auth.users metadata). The customer
--         record's first name, else the first word of its full name (as before: without notes
--         in brackets, only if it looks like a name), only when the record was there at least
--         24 hours before the login. Else "Hi there". For 'welcome' and 'reactivated' alike.
--         (customers keeps no column saying who made a record, so a record a public form made
--         shortly before, with what the caller typed, is told apart only by its age.)
--       - 'welcome' only: under one lock for all welcomes, the welcomes of the last 24 hours
--         are counted, every one but those 'skipped' or 'expired' (a 'failed' one may be retried
--         or may have gone before its answer timed out); at 30 a new one is kept as 'skipped'
--         ('daily_limit'), its key still taken, so it is never sent later.
--
-- WHAT THIS LEAVES ALONE
--
--   * The other limit rows and their numbers; the pauses (405); the rate events already there.
--   * affiliate_whatsapp_message (the words) and the phone rule (the customer's, else the
--     sign-up's); the triggers that queue the WhatsApps; the outbox table (skip_reason has no
--     check, so 'daily_limit' needs none); the outbox rows already there.
--   * affiliate_session_from_email_link and affiliate_email_verification_needed: still there;
--     once 531 is in, no function verifies an email from a link or from Supabase's confirmation
--     (confirm_affiliate_email and the onboarding above were the two that did). The writers left
--     verify only by a code or a server carry-over: affiliate_detail_change_finish (491's code to
--     the new address), confirm_affiliate_email_code (531's code); resolve_affiliate_account_claim
--     makes an account unverified; affiliate_login_email_changed clears it. The emails verified
--     before 531 stay verified.
--   * 529's and 530's objects.
--
-- UNDO
--
--   scripts/affiliate-signup/undo-531.sql (it refuses unless the four functions are 531's
--   versions and the new objects are as 531 made them): the four functions (auth_email_reserve,
--   confirm_affiliate_email, affiliate_whatsapp_enqueue, complete_affiliate_onboarding) are put
--   back exactly
--   as they were, the new functions and the codes table are dropped (codes not yet typed are
--   gone), the four limit rows are deleted, ('signup','ip') goes back to 30 and the checks to
--   their old values. The rate events written while 531 was in stay (the old reserve never
--   counts their actions). The Edge Functions and pages are undone with their own commit; until
--   then their calls to the new functions fail. A later migration changing any of the four
--   functions must pin 531's AFTER md5.
--
-- NO SELF-TEST INSIDE; the suite is scripts/affiliate-signup/tests/signup-limits-and-email-codes-531.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Functions relied on, as tested: the words of the WhatsApp and the trigger that queues the
  -- welcome (affiliate_whatsapp_message, trg_affiliate_whatsapp_welcome), the name as a booking
  -- prints it (affiliate_calendar_label), and the proof that reads email_verified_at
  -- (affiliate_login_link_proof).
  c_relied constant text[] := array[
    'affiliate_whatsapp_message(text,text,text,text)',
    'trg_affiliate_whatsapp_welcome()',
    'affiliate_login_link_proof(uuid,uuid)',
    'affiliate_calendar_label(text)'];
  c_relied_md5 constant text[] := array[
    '6cab1d437121fb0942f90dd7ec7c5310',
    '248067d2763aff9e825d7d42eebb833e',
    '2484fb464733c124213b96152837a660',
    'af4eecdcf978c19b3effb6af3a897165'];
  -- The functions patched.
  c_sig constant text[] := array[
    'auth_email_reserve(text,text,text)',
    'confirm_affiliate_email()',
    'affiliate_whatsapp_enqueue(text,uuid,uuid,uuid,text)',
    'complete_affiliate_onboarding(text,text,text,boolean)'];
  c_before constant text[] := array[
    'e391dd051d05f0661c7924f24e04a1b2',
    '8a0a7036312cf5dc22dd2beb82b3ce09',
    'c88ad74525019c20254a6927f4a802a3',
    '0dd12d4c9cef8b86bb1bcc02a5344927'];
  c_after constant text[] := array[
    'b5fdd6ba83a77beddb370c2a0e8114a1',
    '701c2626748dd8ab80aa4e36a3d2c036',
    '1b52d84e2842ef7709b86e2cbd03718d',
    '15f677725266f658f552051ae61e6d71'];
  -- Their grants, before and after (unchanged).
  c_acl constant text[] := array[
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'];
  -- The new functions: their text, md5 and grants.
  c_new_sig constant text[] := array[
    'auth_email_take(text,text,uuid,text,text)',
    'affiliate_email_code_issue(uuid)',
    'confirm_affiliate_email_code(text)'];
  c_new_def constant text[] := array[
-- 1 auth_email_take
$fn$CREATE OR REPLACE FUNCTION public.auth_email_take(p_bucket text, p_email_hash text DEFAULT NULL::text, p_user_id uuid DEFAULT NULL::uuid, p_recipient_hash text DEFAULT NULL::text, p_lookup_email text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_login   uuid := p_user_id;
  v_global  text;
  v_buckets jsonb;
  v_bucket  record;
  v_limit   record;
  v_used    integer;
  v_oldest  timestamptz;
begin
  -- 531 (security audit of 17 Nov 2026, M6; the user, 20 Nov 2026: "10 per connection + 30
  -- overall", "60 a day + 5 per address", "Staff get their own 20"): one place in a budget all
  -- requests share, taken when it is used, so a request that made or sent nothing takes none:
  --   'signup' when the sign-up has made a login: ('signup','all'), 30 an hour;
  --   'send' when an email has been sent: ('send','all'), 60 in 24 hours, or, when p_user_id
  --   is an active staff login, ('send_staff','all'), 20 in 24 hours. Active staff: a profile
  --   that is active, not deleted and accepted (any role), as require_active_staff (406). The
  --   caller names only 'signup' or 'send'; the staff budget is chosen here, never by it.
  -- With an address key (p_email_hash, 'send' only: an email a signed-in login asks for
  -- itself, which reserve did not count), that address's day (('email_day','email'), 5 in 24
  -- hours) must have room too. With a recipient's key (p_recipient_hash, 'send' only: an email
  -- to an address the caller typed, such as a new email's code), that address's day too, when
  -- it is another address than p_email_hash, so no number of logins can send one address more
  -- than 5 a day. Every place is taken only when every budget has room. A refusal names the
  -- budget that refused. The service role's alone (the Edge Functions). The reserve's lock, so two
  -- requests cannot both take the last place.
  -- With an address typed (p_lookup_email, 'send' only, in place of p_user_id: a password reset
  -- takes its place BEFORE the reset link is made, so a refusal leaves no new link that nobody
  -- receives), the login is found here as auth_email_user_state finds it (the address trimmed
  -- and in lower case, not deleted, the oldest first), and chooses the budget as p_user_id
  -- would. No such login: {allowed:false, retry_after_seconds:0, scope:'email',
  -- action:'no_login'}, nothing counted. It adds no address's day (reserve counted it).
  if p_bucket is null or p_bucket not in ('signup', 'send') then
    raise exception '531: auth_email_take takes ''signup'' or ''send'', not %', coalesce(p_bucket, 'null');
  end if;
  if p_email_hash is not null and (p_bucket <> 'send' or length(btrim(p_email_hash)) = 0) then
    raise exception '531: auth_email_take takes an address key with ''send'' only, and not a blank one';
  end if;
  if p_recipient_hash is not null and (p_bucket <> 'send' or length(btrim(p_recipient_hash)) = 0) then
    raise exception '531: auth_email_take takes a recipient''s key with ''send'' only, and not a blank one';
  end if;
  if p_user_id is not null and p_bucket <> 'send' then
    raise exception '531: auth_email_take takes a login with ''send'' only';
  end if;
  if p_lookup_email is not null and (p_bucket <> 'send' or p_user_id is not null) then
    raise exception '531: auth_email_take takes an address to look up with ''send'' only, and not with a login';
  end if;
  if p_lookup_email is not null then
    select u.id into v_login
      from auth.users u
     where lower(btrim(u.email)) = lower(btrim(p_lookup_email))
       and u.deleted_at is null
     order by u.created_at
     limit 1;
    if v_login is null then
      return jsonb_build_object('allowed', false, 'retry_after_seconds', 0, 'scope', 'email', 'action', 'no_login');
    end if;
  end if;

  perform pg_advisory_xact_lock(hashtext('public.auth_email_reserve'));

  v_global := case
    when p_bucket = 'send' and v_login is not null
         and exists (select 1 from public.profiles p
                      where p.id = v_login and p.is_active and p.deleted_at is null
                        and coalesce(p.invitation_status, 'accepted') = 'accepted') then 'send_staff'
    else p_bucket end;
  v_buckets := jsonb_build_array(jsonb_build_object('action', v_global, 'scope', 'all', 'key', 'all'));
  if p_email_hash is not null then
    v_buckets := v_buckets
      || jsonb_build_array(jsonb_build_object('action', 'email_day', 'scope', 'email', 'key', p_email_hash));
  end if;
  if p_recipient_hash is not null and p_recipient_hash is distinct from p_email_hash then
    v_buckets := v_buckets
      || jsonb_build_array(jsonb_build_object('action', 'email_day', 'scope', 'email', 'key', p_recipient_hash));
  end if;

  for v_bucket in select * from jsonb_to_recordset(v_buckets) as x(action text, scope text, key text) loop
    select * into v_limit from public.auth_email_limits l
     where l.action = v_bucket.action and l.scope = v_bucket.scope;
    if not found then
      raise exception 'AUTH_EMAIL_LIMIT_NOT_CONFIGURED: % / %', v_bucket.action, v_bucket.scope;
    end if;
    select count(*), min(e.occurred_at) into v_used, v_oldest
      from public.auth_email_rate_events e
     where e.action = v_bucket.action
       and e.scope  = v_bucket.scope
       and e.key_hash = v_bucket.key
       and e.occurred_at > now() - make_interval(secs => v_limit.window_seconds);
    if v_used >= v_limit.max_attempts then
      return jsonb_build_object(
        'allowed', false,
        'retry_after_seconds', greatest(1, ceil(extract(epoch from
                                 (v_oldest + make_interval(secs => v_limit.window_seconds)) - now()))::integer),
        'scope', v_bucket.scope,
        'action', v_bucket.action);
    end if;
  end loop;

  insert into public.auth_email_rate_events (action, scope, key_hash)
  select x.action, x.scope, x.key
    from jsonb_to_recordset(v_buckets) as x(action text, scope text, key text);

  return jsonb_build_object('allowed', true, 'retry_after_seconds', 0);
end
$function$
$fn$,
-- 2 affiliate_email_code_issue
$fn$CREATE OR REPLACE FUNCTION public.affiliate_email_code_issue(p_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_email text;
  v_bytes bytea;
  v_n     bigint;
  v_code  text;
  v_at    timestamptz;
begin
  -- 531 (security audit of 17 Nov 2026, M6; the user, 20 Nov 2026: "Code on the Account
  -- page"): a new 6-digit code for the verify email of this affiliate login. The Edge Function
  -- passes the login from its own verified token (the signed-in affiliate asks), and puts the
  -- code in the email it sends to the login's address; the affiliate types it on the Account
  -- page (confirm_affiliate_email_code). The service role's alone.
  --
  -- Only for a login with an affiliate account the portal accepts ('claimed'), that is not a
  -- staff login and whose email is not yet verified. Anything else (no such login, no
  -- address, a staff login, no account, already verified) gets the same answer:
  -- {status:'none'}. The login's earlier codes are retired; only the newest one counts.
  -- The code: pgcrypto's random bytes, 4 at a time, a draw over the last whole million thrown
  -- away (so every code is as likely). It is answered here, once, and kept only as the sha256
  -- of the login and the code; never stored or logged as it is. It lasts 15 minutes and 5
  -- wrong tries.
  if p_auth_user_id is null then
    return jsonb_build_object('status', 'none');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('affiliate-email-code:' || p_auth_user_id::text, 0));
  select u.email into v_email from auth.users u where u.id = p_auth_user_id and u.deleted_at is null;
  if nullif(btrim(coalesce(v_email, '')), '') is null
     or not exists (select 1 from public.affiliate_accounts a
                     where a.auth_user_id = p_auth_user_id and a.status = 'claimed'
                       and a.email_verified_at is null)
     or exists (select 1 from public.profiles p where p.id = p_auth_user_id) then
    return jsonb_build_object('status', 'none');
  end if;

  update public.affiliate_email_codes
     set retired_at = now()
   where auth_user_id = p_auth_user_id and used_at is null and retired_at is null;

  loop
    v_bytes := extensions.gen_random_bytes(4);
    v_n := (get_byte(v_bytes, 0)::bigint << 24) | (get_byte(v_bytes, 1)::bigint << 16)
         | (get_byte(v_bytes, 2)::bigint << 8) | get_byte(v_bytes, 3)::bigint;
    exit when v_n < 4294000000;
  end loop;
  v_code := lpad((v_n % 1000000)::text, 6, '0');
  -- The time it is made (the clock, so codes made in one transaction keep their order).
  v_at := clock_timestamp();

  insert into public.affiliate_email_codes (auth_user_id, email, code_hash, created_at, expires_at)
  values (p_auth_user_id, lower(btrim(v_email)),
          encode(sha256(convert_to(p_auth_user_id::text || ':' || v_code, 'UTF8')), 'hex'),
          v_at, v_at + interval '15 minutes');

  return jsonb_build_object('status', 'issued', 'code', v_code, 'email', v_email, 'expires_in_seconds', 900);
end
$function$
$fn$,
-- 3 confirm_affiliate_email_code
$fn$CREATE OR REPLACE FUNCTION public.confirm_affiliate_email_code(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid  uuid := auth.uid();
  v_acct public.affiliate_accounts%rowtype;
  v_row  public.affiliate_email_codes%rowtype;
  v_now_email text;
begin
  -- 531 (security audit of 17 Nov 2026, M6; the user, 20 Nov 2026: "Code on the Account
  -- page"): the signed-in affiliate types the 6-digit code of their verify email
  -- (affiliate_email_code_issue); the right code, in time, verifies the login's email. This
  -- replaces the emailed link (confirm_affiliate_email answers use_code now).
  --   already verified                           -> {verified:true, already:true}
  --   not six digits                             -> reason 'invalid'
  --   no live code (none, used, retired, ended by 5 wrong tries), a code from before the
  --   login's email last changed (491), or the right code for another address than the
  --   login's now                                -> reason 'no_code'
  --   the newest code ended (15 minutes)         -> reason 'expired'
  --   a wrong code                               -> reason 'wrong_code', tries_left
  --   the 5th wrong code (the code ends)         -> reason 'too_many_tries'
  --   the right code                             -> {verified:true}
  -- The account and the code are locked, so two tries at once are counted one after the
  -- other. Verified: the same login copy and audit entry as confirm_affiliate_email wrote.
  if v_uid is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  select * into v_acct from public.affiliate_accounts where auth_user_id = v_uid for update;
  if v_acct.id is not null and v_acct.email_verified_at is not null then
    return jsonb_build_object('verified', true, 'already', true);
  end if;
  if p_code is null or p_code !~ '^[0-9]{6}$' then
    return jsonb_build_object('verified', false, 'reason', 'invalid');
  end if;
  if v_acct.id is null or v_acct.status is distinct from 'claimed'
     or exists (select 1 from public.profiles p where p.id = v_uid) then
    return jsonb_build_object('verified', false, 'reason', 'no_code');
  end if;
  select * into v_row from public.affiliate_email_codes c
   where c.auth_user_id = v_uid
   order by c.created_at desc, c.id desc
   limit 1
   for update;
  if v_row.id is null or v_row.used_at is not null or v_row.retired_at is not null or v_row.tries >= 5
     or (v_acct.login_email_changed_at is not null and v_row.created_at < v_acct.login_email_changed_at) then
    return jsonb_build_object('verified', false, 'reason', 'no_code');
  end if;
  if v_row.expires_at <= clock_timestamp() then
    return jsonb_build_object('verified', false, 'reason', 'expired');
  end if;
  if v_row.code_hash is distinct from encode(sha256(convert_to(v_uid::text || ':' || p_code, 'UTF8')), 'hex') then
    update public.affiliate_email_codes set tries = tries + 1 where id = v_row.id
    returning tries into v_row.tries;
    if v_row.tries >= 5 then
      return jsonb_build_object('verified', false, 'reason', 'too_many_tries');
    end if;
    return jsonb_build_object('verified', false, 'reason', 'wrong_code', 'tries_left', 5 - v_row.tries);
  end if;
  select lower(btrim(u.email)) into v_now_email from auth.users u where u.id = v_uid;
  if v_now_email is distinct from v_row.email then
    return jsonb_build_object('verified', false, 'reason', 'no_code');
  end if;

  update public.affiliate_email_codes set used_at = now() where id = v_row.id;
  update public.affiliate_accounts set email_verified_at = now(), updated_at = now()
   where id = v_acct.id returning * into v_acct;
  -- Kept on the login too (app_metadata, which only the server writes), as
  -- confirm_affiliate_email did (437).
  update auth.users
     set raw_app_meta_data = (coalesce(raw_app_meta_data, '{}'::jsonb) - 'affiliate_email_unverified')
                             || jsonb_build_object('affiliate_email_verified_at', v_acct.email_verified_at)
   where id = v_uid;
  -- Written straight into audit_logs (an affiliate has no staff profile for write_audit_ex to
  -- record), the same entry as confirm_affiliate_email wrote.
  begin
    insert into public.audit_logs (table_name, record_id, action, old_data, new_data, module)
    values ('affiliate_accounts', v_acct.id, 'affiliate_email_verified',
      jsonb_build_object('email_verified_at', null),
      jsonb_build_object('auth_user_id', v_uid, 'customer_id', v_acct.customer_id,
                         'email_verified_at', v_acct.email_verified_at),
      'affiliate');
  exception when others then
    raise warning '531: the email verification audit row was not saved: %', sqlerrm;
  end;
  return jsonb_build_object('verified', true);
end
$function$
$fn$];
  c_new_md5 constant text[] := array[
    '17a3702da427e408526a184e06d4f662',
    '829da32b75af310c200fbbba20df03b7',
    'a56f471685007ee0dad071c9e98d633e'];
  c_new_acl constant text[] := array[
    'postgres=X/postgres,service_role=X/postgres',
    'postgres=X/postgres,service_role=X/postgres',
    'authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres'];
  -- The codes table, as 531 makes it: the owner's alone.
  c_codes_cols constant text :=
    'id uuid NO,auth_user_id uuid NO,email text NO,code_hash text NO,created_at timestamp with time zone NO,expires_at timestamp with time zone NO,tries integer NO,used_at timestamp with time zone YES,retired_at timestamp with time zone YES';
  c_codes_idx constant text[] := array[
    'CREATE INDEX idx_affiliate_email_codes_login_time ON public.affiliate_email_codes USING btree (auth_user_id, created_at DESC)',
    'CREATE UNIQUE INDEX affiliate_email_codes_pkey ON public.affiliate_email_codes USING btree (id)'];
  c_codes_con constant text[] := array[
    'affiliate_email_codes_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE',
    'affiliate_email_codes_code_hash_is_a_hash CHECK ((code_hash ~ ''^[0-9a-f]{64}$''::text))',
    'affiliate_email_codes_pkey PRIMARY KEY (id)',
    'affiliate_email_codes_tries_check CHECK (((tries >= 0) AND (tries <= 5)))'];
  c_codes_acl constant text := 'postgres=arwdDxtm/postgres';
  -- The limits table's checks, before 531 and after.
  c_lim_con_before constant text[] := array[
    'auth_email_limits_action_check CHECK ((action = ANY (ARRAY[''signup''::text, ''resend''::text, ''recovery''::text, ''combined''::text])))',
    'auth_email_limits_max_attempts_check CHECK ((max_attempts > 0))',
    'auth_email_limits_pkey PRIMARY KEY (action, scope)',
    'auth_email_limits_scope_check CHECK ((scope = ANY (ARRAY[''email''::text, ''ip''::text])))',
    'auth_email_limits_window_seconds_check CHECK ((window_seconds > 0))'];
  c_lim_con_after constant text[] := array[
    'auth_email_limits_action_check CHECK ((action = ANY (ARRAY[''signup''::text, ''resend''::text, ''recovery''::text, ''combined''::text, ''send''::text, ''send_staff''::text, ''email_day''::text])))',
    'auth_email_limits_max_attempts_check CHECK ((max_attempts > 0))',
    'auth_email_limits_pkey PRIMARY KEY (action, scope)',
    'auth_email_limits_scope_check CHECK ((scope = ANY (ARRAY[''email''::text, ''ip''::text, ''all''::text])))',
    'auth_email_limits_window_seconds_check CHECK ((window_seconds > 0))'];
  -- Seven patches, each found exactly once in its function:
  --   1. reserve: a sign-up looks at the limit for all first; a resend or reset fits the address's day
  --   2. confirm_affiliate_email: no longer verifies (use_code)
  --   3. enqueue: the declarations (when the login was made)
  --   4. enqueue: the login's time read with its metadata
  --   5. enqueue: the greeting's name (no typed name)
  --   6. enqueue: at most 30 welcomes a day
  --   7. onboarding: a new account is verified only by the date the server keeps on the login
  c_fn constant int[] := array[1, 2, 3, 3, 3, 3, 4];
  c_anchor constant text[] := array[
-- 1 reserve: a sign-up looks at the limit for all first; a resend or reset fits the address's day
$a$  perform pg_advisory_xact_lock(hashtext('public.auth_email_reserve'));

  -- The buckets this request must fit inside.
  v_buckets := jsonb_build_array(jsonb_build_object('action', p_action, 'scope', 'email', 'key', p_email_hash));
$a$,
-- 2 confirm_affiliate_email: no longer verifies (use_code)
$a$  if not public.affiliate_session_from_email_link() then
    return jsonb_build_object('verified', false, 'reason', 'not_from_email_link');
  end if;
  -- 491: a link sent before the login's email last changed proved the old
  -- inbox, not the one the login has now.
  if v_acct.login_email_changed_at is not null
     and coalesce((select max((e->>'timestamp')::numeric)
                     from jsonb_array_elements(case when jsonb_typeof(auth.jwt()->'amr') = 'array'
                                                    then auth.jwt()->'amr' else '[]'::jsonb end) e
                    where e->>'method' in ('magiclink', 'otp', 'recovery', 'invite', 'email/signup')), 0)
         < extract(epoch from v_acct.login_email_changed_at) then
    return jsonb_build_object('verified', false, 'reason', 'email_changed_since_link');
  end if;
  update public.affiliate_accounts set email_verified_at = now(), updated_at = now()
   where id = v_acct.id returning * into v_acct;
  -- Kept on the login too (app_metadata, which only the server writes), so
  -- the account made at its next sign-in after an Owner unlinks it (378)
  -- starts verified; and the login no longer counts as one the sign-up
  -- confirmed on an address nobody proved (invite_user_provisioned).
  update auth.users
     set raw_app_meta_data = (coalesce(raw_app_meta_data, '{}'::jsonb) - 'affiliate_email_unverified')
                             || jsonb_build_object('affiliate_email_verified_at', v_acct.email_verified_at)
   where id = v_uid;
  -- Written straight into audit_logs (an affiliate has no staff profile for
  -- write_audit_ex to record), as sign-up's own rows are (432).
  begin
    insert into public.audit_logs (table_name, record_id, action, old_data, new_data, module)
    values ('affiliate_accounts', v_acct.id, 'affiliate_email_verified',
      jsonb_build_object('email_verified_at', null),
      jsonb_build_object('auth_user_id', v_uid, 'customer_id', v_acct.customer_id,
                         'email_verified_at', v_acct.email_verified_at),
      'affiliate');
  exception when others then
    raise warning '437: the email verification audit row was not saved: %', sqlerrm;
  end;
  return jsonb_build_object('verified', true, 'already', false, 'verified_at', v_acct.email_verified_at);
end $function$
$a$,
-- 3 enqueue: the declarations (when the login was made)
$a$  v_meta jsonb; v_app text; v_name text; v_first text; v_phone text; v_digits text; v_cc text; v_skip text; v_id bigint;
begin
$a$,
-- 4 enqueue: the login's time read with its metadata
$a$  select raw_user_meta_data into v_meta from auth.users where id = p_auth_user_id;
$a$,
-- 5 enqueue: the greeting's name (no typed name)
$a$  -- The name they gave at sign-up, else the customer's first name, else the
  -- first word of the full name; never the notes staff keep in brackets. The
  -- sign-up name is whatever the person typed, so a name is used only if it
  -- looks like one: letters, spaces, an apostrophe or a hyphen, at most 30
  -- characters. No digits, dots, slashes or colons: no link or phone number
  -- goes out in the greeting. None that does: "Hi there".
  foreach v_name in array array[v_meta->>'first_name', v_c.first_name,
                                split_part(public.affiliate_calendar_label(v_c.full_name), ' ', 1)] loop
    v_name := public.affiliate_calendar_label(v_name);
    if v_name ~ E'^[[:alpha:]][[:alpha:]''\u2019 -]{0,29}$' then
      v_first := v_name;
      exit;
    end if;
  end loop;
$a$,
-- 6 enqueue: at most 30 welcomes a day
$a$    when v_phone is null or v_cc is null then 'no_phone'
  end;
$a$,
-- 7 onboarding: a new account is verified only by the date the server keeps on the login
$a$
  -- 437 (2): the app's own "email verified". Yes, from that day, when the
  -- login says it was verified before (app_metadata
  -- affiliate_email_verified_at: an account an Owner unlinked, 378); yes
  -- when Supabase Auth confirmed the login through its email link (every
  -- login before 437); no when the sign-up function or the 437 repair
  -- confirmed it (app_metadata.affiliate_email_unverified; the server alone
  -- sets either); yes now when this session was opened from an emailed link,
  -- which the login then keeps too.
  v_verified := case
    when coalesce(v_app->>'affiliate_email_verified_at', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}'
      then (v_app->>'affiliate_email_verified_at')::timestamptz
    when coalesce(v_app->>'affiliate_email_unverified', '') = 'true' then null
    else v_confirmed end;
  if v_verified is null and public.affiliate_session_from_email_link() then
    v_verified := now();
    update auth.users
       set raw_app_meta_data = (coalesce(raw_app_meta_data, '{}'::jsonb) - 'affiliate_email_unverified')
                               || jsonb_build_object('affiliate_email_verified_at', v_verified)
     where id = v_uid;
  end if;
$a$];
  c_new constant text[] := array[
-- 1 reserve: a sign-up looks at the limit for all first; a resend or reset fits the address's day
$n$  perform pg_advisory_xact_lock(hashtext('public.auth_email_reserve'));

  -- 531 (security audit of 17 Nov 2026, M6; the user, 20 Nov 2026: "10 per connection + 30
  -- overall"): a sign-up first looks at the limit all sign-ups share, ('signup','all'), 30 new
  -- logins an hour. Full: refused, and nothing is counted. A place in it is taken only when a
  -- login is made (auth_email_take), so a sign-up that makes none never counts there. A resend
  -- or a reset does not look at the emails' budgets here (they are taken when an email is
  -- sent, the staff budget apart), so this answer never shows whether an address is staff.
  if p_action = 'signup' then
    select * into v_limit from public.auth_email_limits l
     where l.action = 'signup' and l.scope = 'all';
    if not found then
      raise exception 'AUTH_EMAIL_LIMIT_NOT_CONFIGURED: % / %', 'signup', 'all';
    end if;
    select count(*), min(e.occurred_at) into v_used, v_oldest
      from public.auth_email_rate_events e
     where e.action = 'signup'
       and e.scope  = 'all'
       and e.key_hash = 'all'
       and e.occurred_at > now() - make_interval(secs => v_limit.window_seconds);
    if v_used >= v_limit.max_attempts then
      v_retry := greatest(1, ceil(extract(epoch from
                   (v_oldest + make_interval(secs => v_limit.window_seconds)) - now()))::integer);
      return jsonb_build_object(
        'allowed', false,
        'retry_after_seconds', v_retry,
        'scope', 'all',
        'action', 'signup');
    end if;
  end if;

  -- The buckets this request must fit inside.
  v_buckets := jsonb_build_array(jsonb_build_object('action', p_action, 'scope', 'email', 'key', p_email_hash));
  -- 531 ("60 a day + 5 per address"): a resend or a reset also fits the address's day, 5 in 24
  -- hours, the two together, counted for every request allowed (whoever the address is).
  if p_action in ('resend', 'recovery') then
    v_buckets := v_buckets
      || jsonb_build_array(jsonb_build_object('action', 'email_day', 'scope', 'email', 'key', p_email_hash));
  end if;
$n$,
-- 2 confirm_affiliate_email: no longer verifies (use_code)
$n$  -- 531 (security audit of 17 Nov 2026, M6; the user, 20 Nov 2026: "Code on the Account
  -- page"): an emailed link no longer marks an email verified. The verify email carries a
  -- 6-digit code that the affiliate types on the Account page while signed in
  -- (confirm_affiliate_email_code). Already verified and not an affiliate are answered as
  -- before; anything else is answered use_code, and nothing changes.
  return jsonb_build_object('verified', false, 'reason', 'use_code');
end $function$
$n$,
-- 3 enqueue: the declarations (when the login was made)
$n$  v_meta jsonb; v_app text; v_name text; v_first text; v_phone text; v_digits text; v_cc text; v_skip text; v_id bigint;
  v_login_at timestamptz;  -- 531: when the login was made
begin
$n$,
-- 4 enqueue: the login's time read with its metadata
$n$  select raw_user_meta_data, created_at into v_meta, v_login_at from auth.users where id = p_auth_user_id;
$n$,
-- 5 enqueue: the greeting's name (no typed name)
$n$  -- 531 (security audit of 17 Nov 2026, M6; the user, 20 Nov 2026: "No typed names"): the
  -- greeting never uses a name the person typed. Never the sign-up's name (auth.users
  -- metadata). The customer record's name only when the record was there at least 24 hours
  -- before the login: a record made shortly before by a public form (the referral page, the QR
  -- health form, the event website, a website order) or by the sign-up itself carries what the
  -- caller typed, and customers keeps no column saying who made a record. (A customer added at
  -- the counter who signs up the same day is greeted "Hi there".) Then, as before, the
  -- record's first name, else the first word of its full name, never the notes in brackets,
  -- only if it looks like a name: letters, spaces, an apostrophe or a hyphen, at most 30
  -- characters. None: "Hi there".
  if v_c.id is not null and v_login_at is not null and v_c.created_at <= v_login_at - interval '24 hours' then
    foreach v_name in array array[v_c.first_name,
                                  split_part(public.affiliate_calendar_label(v_c.full_name), ' ', 1)] loop
      v_name := public.affiliate_calendar_label(v_name);
      if v_name ~ E'^[[:alpha:]][[:alpha:]''\u2019 -]{0,29}$' then
        v_first := v_name;
        exit;
      end if;
    end loop;
  end if;
$n$,
-- 6 enqueue: at most 30 welcomes a day
$n$    when v_phone is null or v_cc is null then 'no_phone'
  end;
  -- 531 (security audit of 17 Nov 2026, M6; the user, 20 Nov 2026: "30 welcomes a day"): at
  -- most 30 welcome WhatsApps in 24 hours. Under one lock for all welcomes (held to the end of
  -- the transaction, so two at once are counted one after the other), the welcomes of the last
  -- 24 hours that may have gone or may still go are counted: every one but those 'skipped' or
  -- 'expired' (so a 'failed' one, which may be retried or may have gone before its answer timed
  -- out, counts too); at 30 this one is kept as 'skipped'
  -- ('daily_limit'), nothing is sent, and its key is taken, so it is never sent later. The
  -- Owner's 'reactivated' messages are neither counted nor limited.
  if p_kind = 'welcome' then
    perform pg_advisory_xact_lock(hashtextextended('affiliate-whatsapp-welcome-day', 0));
    if v_skip is null
       and (select count(*) from public.affiliate_whatsapp_outbox o
             where o.kind = 'welcome' and o.status not in ('skipped', 'expired')
               and o.created_at > now() - interval '24 hours') >= 30 then
      v_skip := 'daily_limit';
    end if;
  end if;
$n$,
-- 7 onboarding: a new account is verified only by the date the server keeps on the login
$n$  -- 531 (security audit of 17 Nov 2026, M6; the user, 20 Nov 2026: "Code on the Account
  -- page"): a new account's "email verified" comes only from the date the server keeps on the
  -- login (app_metadata affiliate_email_verified_at, which the server alone writes: when the
  -- login verified with a code, or kept from an account an Owner unlinked, 378). Neither
  -- Supabase Auth's own confirmation (email_confirmed_at) nor a session opened from an emailed
  -- link (a reset link, a magic link) verifies it any more; 437 (2) took both. A login the
  -- sign-up made with someone's email and left without an account would otherwise become
  -- verified when that person opened a reset link. Every other new account starts unverified
  -- and verifies with the code from the verify email (confirm_affiliate_email_code).
  v_verified := case
    when coalesce(v_app->>'affiliate_email_verified_at', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}'
      then (v_app->>'affiliate_email_verified_at')::timestamptz
  end;
$n$];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[4]);
  v_make boolean[] := array_fill(false, array[4]);
  v_acl text[] := array_fill(null::text, array[4]);
  v_new_make boolean[] := array_fill(false, array[3]);
  v_add_codes boolean := false;
  v_widen boolean := false;
  v_ip_max int;
  v_con text[];
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
      raise exception '531: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  -- pgcrypto (in the schema extensions) makes the codes; sha256 (built in) hashes them.
  if to_regprocedure('extensions.gen_random_bytes(integer)') is null then
    raise exception '531: pgcrypto''s extensions.gen_random_bytes(integer) is missing'; end if;
  if to_regprocedure('pg_catalog.sha256(bytea)') is null then
    raise exception '531: pg_catalog.sha256(bytea) is missing'; end if;
  -- The tables the functions read.
  if to_regclass('public.auth_email_rate_events') is null or to_regclass('public.auth_email_pauses') is null
     or to_regclass('public.affiliate_accounts') is null or to_regclass('public.profiles') is null
     or to_regclass('public.audit_logs') is null then
    raise exception '531: a table the functions read is missing (auth_email_rate_events, auth_email_pauses, affiliate_accounts, profiles, audit_logs)'; end if;
  if (select count(*) from information_schema.columns
       where table_schema = 'public' and table_name = 'affiliate_accounts'
         and column_name in ('email_verified_at', 'login_email_changed_at', 'status')) <> 3 then
    raise exception '531: affiliate_accounts has not the columns this reads (email_verified_at, login_email_changed_at, status)'; end if;

  -- The limits table: its checks as before 531 (widened) or as 531 left them (left alone);
  -- ('signup','ip') at 30 (made 10) or 10 (left alone).
  if to_regclass('public.auth_email_limits') is null then
    raise exception '531: public.auth_email_limits is missing'; end if;
  v_con := (select array_agg(c.conname || ' ' || pg_get_constraintdef(c.oid) order by c.conname)
              from pg_constraint c where c.conrelid = 'public.auth_email_limits'::regclass);
  if v_con = c_lim_con_before then
    v_widen := true;
  elsif v_con = c_lim_con_after then
    raise notice '531: the checks of public.auth_email_limits already allow send, email_day and all; left alone';
  else
    raise exception '531: the constraints of public.auth_email_limits are not as tested (%). Re-read them before applying.', v_con;
  end if;
  select l.max_attempts into v_ip_max from public.auth_email_limits l where l.action = 'signup' and l.scope = 'ip';
  if v_ip_max is null or v_ip_max not in (30, 10) then
    raise exception '531: the limit (signup, ip) is % (expected 30, or 10 after 531). Re-read public.auth_email_limits before applying.',
      coalesce(v_ip_max::text, 'missing');
  end if;

  -- The codes table: missing (made), or as 531 made it (left alone).
  if to_regclass('public.affiliate_email_codes') is null then
    v_add_codes := true;
  elsif (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
           from information_schema.columns where table_schema = 'public' and table_name = 'affiliate_email_codes') = c_codes_cols
        and (select array_agg(pg_get_indexdef(x.indexrelid) order by pg_get_indexdef(x.indexrelid))
               from pg_index x where x.indrelid = 'public.affiliate_email_codes'::regclass) = c_codes_idx
        and (select array_agg(c.conname || ' ' || pg_get_constraintdef(c.oid) order by c.conname)
               from pg_constraint c where c.conrelid = 'public.affiliate_email_codes'::regclass) = c_codes_con
        and (select c.relrowsecurity from pg_class c where c.oid = 'public.affiliate_email_codes'::regclass)
        and not exists (select 1 from pg_policy p where p.polrelid = 'public.affiliate_email_codes'::regclass)
        and (select coalesce(string_agg(x::text, ',' order by x::text), '')
               from pg_class c, unnest(c.relacl) x where c.oid = 'public.affiliate_email_codes'::regclass) = c_codes_acl then
    raise notice '531: public.affiliate_email_codes is already there as 531 made it; left alone';
  else
    raise exception '531: a table public.affiliate_email_codes is there, but not as 531 makes it. Re-read it before applying.';
  end if;

  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '531: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if v_acl[i] is distinct from c_acl[i] then
      raise exception '531: the grants of public.% are not the tested ones (%). Re-read them before applying.', c_sig[i], v_acl[i]; end if;
    if md5(d) = c_after[i] then
      raise notice '531: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '531: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if to_regprocedure('public.' || c_new_sig[i]) is null then
      -- No other function of that name (a different overload) may be there either.
      if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                  and p.proname = split_part(c_new_sig[i], '(', 1)) then
        raise exception '531: another public.% is there. Re-read it before applying.', split_part(c_new_sig[i], '(', 1); end if;
      v_new_make[i] := true;
    elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) = c_new_md5[i]
          and (select coalesce(string_agg(x::text, ',' order by x::text), '')
                 from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new_sig[i])) = c_new_acl[i] then
      raise notice '531: public.% is already this version with its grants; left alone', c_new_sig[i];
    else
      raise exception '531: a function public.% is there, but not as 531 makes it. Re-read it before applying.', c_new_sig[i];
    end if;
  end loop;
  -- All before 531 or all as 531 left them (the new functions read the table, reserve reads
  -- the new limit rows the widened checks allow).
  if exists (select 1 from unnest(v_make || v_new_make || array[v_add_codes, v_widen]) m where m is distinct from v_make[1]) then
    raise exception '531: the functions, public.affiliate_email_codes and the checks of public.auth_email_limits are not all before 531 or all after it. Re-read them before applying.';
  end if;
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '531: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '531: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install: the limits first (reserve reads the new rows), then the table (the new
  --    functions read it), then the functions
  if v_widen then
    alter table public.auth_email_limits drop constraint auth_email_limits_action_check;
    alter table public.auth_email_limits add constraint auth_email_limits_action_check
      check (action = any (array['signup', 'resend', 'recovery', 'combined', 'send', 'send_staff', 'email_day']));
    alter table public.auth_email_limits drop constraint auth_email_limits_scope_check;
    alter table public.auth_email_limits add constraint auth_email_limits_scope_check
      check (scope = any (array['email', 'ip', 'all']));
  end if;
  if v_ip_max = 30 then
    update public.auth_email_limits set max_attempts = 10, updated_at = now()
     where action = 'signup' and scope = 'ip' and max_attempts = 30;
  end if;
  insert into public.auth_email_limits (action, scope, max_attempts, window_seconds) values
    ('signup',    'all',   30,  3600),   -- 531: all sign-ups together, 30 new logins an hour
    ('send',      'all',   60, 86400),   -- 531: the verify and reset emails sent, 60 in 24 hours
    ('send_staff','all',   20, 86400),   -- 531: those sent to active staff logins, 20 in 24 hours
    ('email_day', 'email',  5, 86400)    -- 531: one address, 5 emails in 24 hours
  on conflict (action, scope) do nothing;

  if v_add_codes then
    create table public.affiliate_email_codes (
      id uuid primary key default gen_random_uuid(),
      auth_user_id uuid not null references auth.users(id) on delete cascade,
      email text not null,
      code_hash text not null constraint affiliate_email_codes_code_hash_is_a_hash check (code_hash ~ '^[0-9a-f]{64}$'),
      created_at timestamp with time zone not null default now(),
      expires_at timestamp with time zone not null,
      tries integer not null default 0 constraint affiliate_email_codes_tries_check check (tries >= 0 and tries <= 5),
      used_at timestamp with time zone,
      retired_at timestamp with time zone);
    create index idx_affiliate_email_codes_login_time on public.affiliate_email_codes (auth_user_id, created_at desc);
    alter table public.affiliate_email_codes enable row level security;
    revoke all on table public.affiliate_email_codes from public, anon, authenticated, service_role;
    comment on table public.affiliate_email_codes is
      '531: the 6-digit codes of the affiliate verify email (affiliate_email_code_issue), kept as the sha256 of the login and the code, never the code. 15 minutes, 5 wrong tries; only the newest code of a login counts (confirm_affiliate_email_code). No API role reads it (row level security on, no policy, no grant).';
  end if;

  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if v_new_make[i] then
      execute c_new_def[i];
      execute format('revoke all on function public.%s from public, anon, authenticated, service_role', c_new_sig[i]);
      execute format('grant execute on function public.%s to %s', c_new_sig[i],
                     case when c_new_sig[i] = 'confirm_affiliate_email_code(text)' then 'authenticated, service_role'
                          else 'service_role' end);
    end if;
  end loop;

  -- 3. Checks after installing
  if (select array_agg(c.conname || ' ' || pg_get_constraintdef(c.oid) order by c.conname)
        from pg_constraint c where c.conrelid = 'public.auth_email_limits'::regclass) is distinct from c_lim_con_after then
    raise exception '531: the checks of public.auth_email_limits are not as tested after widening them'; end if;
  if (select max_attempts from public.auth_email_limits where action = 'signup' and scope = 'ip') is distinct from 10
     or not exists (select 1 from public.auth_email_limits where action = 'signup' and scope = 'all')
     or not exists (select 1 from public.auth_email_limits where action = 'send' and scope = 'all')
     or not exists (select 1 from public.auth_email_limits where action = 'send_staff' and scope = 'all')
     or not exists (select 1 from public.auth_email_limits where action = 'email_day' and scope = 'email') then
    raise exception '531: the limit rows are not as tested after adding them'; end if;
  if (select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position)
        from information_schema.columns where table_schema = 'public' and table_name = 'affiliate_email_codes') is distinct from c_codes_cols
     or (select array_agg(pg_get_indexdef(x.indexrelid) order by pg_get_indexdef(x.indexrelid))
           from pg_index x where x.indrelid = 'public.affiliate_email_codes'::regclass) is distinct from c_codes_idx
     or (select array_agg(c.conname || ' ' || pg_get_constraintdef(c.oid) order by c.conname)
           from pg_constraint c where c.conrelid = 'public.affiliate_email_codes'::regclass) is distinct from c_codes_con
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.affiliate_email_codes'::regclass)
     or exists (select 1 from pg_policy p where p.polrelid = 'public.affiliate_email_codes'::regclass)
     or (select coalesce(string_agg(x::text, ',' order by x::text), '')
           from pg_class c, unnest(c.relacl) x where c.oid = 'public.affiliate_email_codes'::regclass) is distinct from c_codes_acl
     or has_table_privilege('anon', 'public.affiliate_email_codes', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.affiliate_email_codes', 'select,insert,update,delete')
     or has_table_privilege('service_role', 'public.affiliate_email_codes', 'select,insert,update,delete') then
    raise exception '531: public.affiliate_email_codes is not as tested after making it (the owner''s alone)'; end if;
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '531: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '531: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_new_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_md5[i] then
      raise exception '531: public.% was installed with an md5 other than the tested one (md5 %)', c_new_sig[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))); end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new_sig[i])) is distinct from c_new_acl[i] then
      raise exception '531: the grants of public.% are not the tested ones', c_new_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '531: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
