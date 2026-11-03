-- 491_affiliate_changes_own_details.sql
--
-- AN AFFILIATE CHANGES THEIR OWN NAME, PHONE AND EMAIL FROM THE PORTAL
-- (the user's answers in chat, 3 Nov 2026)
--
-- (The number 491 is this file's name, its errors' prefix, its self-test's
-- error code P0491 and its suite's; if it changes at commit, change it in
-- these places alone.)
--
-- THE RULE
--
--   * A VERIFIED account (affiliate_accounts.email_verified_at) gets a
--     6-digit code by email to its CURRENT email before any change is made;
--     for a new email, a second code to the NEW email, so the login email
--     and the record's email change together and the account stays
--     Verified.
--   * An UNVERIFIED account changes freely only when its own sign-up made
--     the customer record (484's proof own_record). Any other unverified
--     account verifies its email first.
--   * A verified account that 484 does not prove to be the record's (a login
--     joined to an existing customer whose verified email is not the
--     record's) confirms the code and then waits for an Owner or Manager,
--     who approves or rejects it on the Affiliates page.
--   * A phone another customer holds, or another login signed up with, is
--     refused; so is an email another login, customer or sign-up has.
--   * Names: letters, spaces, hyphens, apostrophes, full stops, "/" and "@",
--     50 at most (no digits or other signs).
--   * A code lives 10 minutes and allows 5 tries; a step sends at most 5
--     codes, a minute apart; a login starts at most 5 requests a day.
--   * Every change writes an Audit Log row ("customer_details_changed_by_
--     affiliate"); the server emails the old address (the Edge Function
--     affiliate-details). A phone changed this way since the affiliate's last
--     payout is shown to staff before they pay (PayNow goes to it).
--
-- HOW
--
--   The portal calls the Edge Function affiliate-details, which checks the
--   caller's session and calls these functions as the service role (no user
--   JWT, so the phone history and the Audit Log need no staff profile):
--   start, verify, resend, cancel, then finish once the login's email (if
--   it changes) is changed through Supabase Auth's admin API; an Owner's or
--   Manager's decision goes the same way (decide). Codes are kept as
--   sha-256 hashes only. The portal reads affiliate_portal_details(); the
--   Affiliates page reads affiliate_detail_change_requests(); the payout
--   window reads affiliate_self_phone_change().
--
--   Closing the other ways round:
--   * A login email changed any other way (Supabase Auth's own email change
--     called from a browser, the dashboard) is no longer verified, and its
--     time is kept (the trigger affiliate_login_email_changed on auth.users;
--     the portal's own change is told apart by its request, in 'applying'
--     with that email).
--   * confirm_affiliate_email no longer accepts a session opened from an
--     email link sent before the login's email last changed.
--
-- NOT COVERED
--
--   * A phone number is not proven by a code (no SMS or WhatsApp code
--     service exists); it is checked for its form and for other holders.
--   * Answers such as phone_in_use or email_in_use say that a number or an
--     address is someone's, as sign-up already does (466); a login may
--     start only 5 requests a day.
--   * Past cal.com bookings, TikTok lead links, seminar registrations and
--     the 440 sign-up copy keep the details they were made with.
--
-- DEPLOY ORDER (each step with the user's go-ahead in chat)
--
--   489 -> 490 -> 491 -> the Edge Function affiliate-details -> the pages.
--   491 does not depend on 489 or 490. 487 and 488 (another session) do not
--   touch these functions.
--   1. Dry run on a copy of production: apply this file twice; the second
--      run changes nothing.
--   2. Apply. It checks itself and runs its self-test.
--   3. Deploy affiliate-details; one real test with a real inbox.
--
-- BEFORE (production now, 3 Nov 2026; md5 of pg_get_functiondef with
-- search_path public)
--   changed:
--   * confirm_affiliate_email(): 431ff39aa4fe42ec9b1442e65a044676
--   relied on, not changed:
--   * affiliate_login_link_proof(uuid,uuid): 2484fb464733c124213b96152837a660
--   * affiliate_session_from_email_link(): d0f5ab3b19eecc6211262821bcbee600
--   * customer_email_match_key(text): be468815c9626fff1728e2cfcd484b66
--   * inspect_customer_phone(text,text): 6672c4d1963996f3b601896f4a55916e
--   * is_owner_or_manager(): a98e50f1b6d3fa1e6c62cf52a8073cc8
--   * normalize_customer_phone(text): b2bfac910e0c9eff402ba44e19750bee
-- AFTER (for later guards)
--   * confirm_affiliate_email(): 8a0a7036312cf5dc22dd2beb82b3ce09
--   * public function fingerprint, production -> 489 -> 490 -> 491 (a second
--     run the same): 3b9d2f339b0338a1f8979471162bb6c9 (1414 functions: 14
--     added, one replaced). Worked out on a copy of production at 481.
--
-- UNDO
--
--   Re-install confirm_affiliate_email's BEFORE body; drop the trigger
--   affiliate_login_email_changed on auth.users and the functions this file
--   makes; keep the table (its rows are the record of what changed).
--
-- Test: scripts/affiliate-details/tests/details-491.sql (begin ... rollback).
-- Fixtures only (the repository is public).

set lock_timeout = '5s';

-- ══ 1. Checks: nothing is changed before all of them pass ══
do $chk$
declare v text; i int;
  c_relied constant text[] := array['affiliate_login_link_proof(uuid,uuid)', 'affiliate_session_from_email_link()',
    'customer_email_match_key(text)', 'inspect_customer_phone(text,text)', 'is_owner_or_manager()', 'normalize_customer_phone(text)'];
  c_relied_md5 constant text[] := array['2484fb464733c124213b96152837a660', 'd0f5ab3b19eecc6211262821bcbee600',
    'be468815c9626fff1728e2cfcd484b66', '6672c4d1963996f3b601896f4a55916e', 'a98e50f1b6d3fa1e6c62cf52a8073cc8', 'b2bfac910e0c9eff402ba44e19750bee'];
begin
  perform set_config('search_path', 'public', true);
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '491: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  if to_regprocedure('public.confirm_affiliate_email()') is null
     or md5(pg_get_functiondef('public.confirm_affiliate_email()'::regprocedure))
        not in ('431ff39aa4fe42ec9b1442e65a044676', '8a0a7036312cf5dc22dd2beb82b3ce09') then
    raise exception '491: public.confirm_affiliate_email() is not the version this was tested against. Re-read it and re-test before applying.';
  end if;
  if to_regprocedure('extensions.digest(text,text)') is null or to_regprocedure('extensions.gen_random_bytes(integer)') is null then
    raise exception '491: pgcrypto (extensions.digest, extensions.gen_random_bytes) is missing'; end if;
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('public', 'affiliate_accounts', 'email_verified_at'), ('public', 'affiliate_accounts', 'customer_id'),
                 ('public', 'customers', 'first_name'), ('public', 'customers', 'last_name'), ('public', 'customers', 'phone'),
                 ('public', 'customers', 'email'), ('public', 'affiliate_signup_identities', 'phone'),
                 ('public', 'affiliate_signup_identities', 'email'), ('public', 'commission_payouts', 'referrer_customer_id'),
                 ('public', 'audit_logs', 'module'), ('auth', 'users', 'raw_app_meta_data'), ('auth', 'users', 'raw_user_meta_data')) x(s, t, c)
   where not exists (select 1 from pg_attribute a where a.attrelid = (x.s || '.' || x.t)::regclass and a.attname = x.c and not a.attisdropped);
  if v is not null then raise exception '491: these columns are missing: %', v; end if;
end $chk$;

-- ══ 2. Objects ══

alter table public.affiliate_accounts add column if not exists login_email_changed_at timestamptz;
comment on column public.affiliate_accounts.login_email_changed_at is
  '491: when the login''s email last changed (the portal''s own change, or any other). confirm_affiliate_email refuses a session opened from an email link before it.';

create table if not exists public.affiliate_detail_changes (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  -- free: an unverified login on the record its own sign-up made; code: a
  -- verified login proven to be the record's (484); staff: verified, not proven
  route text not null check (route in ('free', 'code', 'staff')),
  status text not null check (status in ('awaiting_code', 'pending_staff', 'applying', 'applied', 'rejected', 'cancelled', 'expired', 'failed')),
  old_first_name text, old_last_name text, old_phone text, old_email text, old_login_email text,
  -- null: unchanged
  new_first_name text, new_last_name text, new_phone text, new_email text,
  -- the code: its sha-256 (salted with the request and its purpose), never the code
  code_hash text, code_for text check (code_for in ('current', 'new')), code_expires_at timestamptz,
  code_attempts int not null default 0, code_sends int not null default 0, code_sent_at timestamptz,
  current_proven_at timestamptz, new_proven_at timestamptz,
  decided_by uuid references public.profiles(id), decided_at timestamptz, decision_note text,
  applied_at timestamptz, failure text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
comment on table public.affiliate_detail_changes is
  '491: an affiliate''s own change of name, phone or email from the portal (the user, 3 Nov 2026). Written only by the server.';
create unique index if not exists affiliate_detail_changes_one_open on public.affiliate_detail_changes (auth_user_id)
  where status in ('awaiting_code', 'pending_staff', 'applying');
create index if not exists affiliate_detail_changes_by_customer on public.affiliate_detail_changes (customer_id, created_at desc);
create index if not exists affiliate_detail_changes_by_login on public.affiliate_detail_changes (auth_user_id, created_at desc);
alter table public.affiliate_detail_changes enable row level security;
revoke all on public.affiliate_detail_changes from public, anon, authenticated;
grant select, insert, update on public.affiliate_detail_changes to service_role;

-- What a login may change, and how (the user's answers, 3 Nov 2026).
create or replace function public.affiliate_detail_state(p_uid uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare a public.affiliate_accounts%rowtype; c public.customers%rowtype; v_login text; v_proof text; v_route text;
begin
  select * into a from public.affiliate_accounts where auth_user_id = p_uid;
  if not found then return jsonb_build_object('route', 'not_affiliate'); end if;
  select * into c from public.customers where id = a.customer_id;
  select u.email into v_login from auth.users u where u.id = p_uid;
  v_proof := public.affiliate_login_link_proof(p_uid, a.customer_id);
  v_route := case
    -- a staff login, a switched-off account or a missing record changes nothing here
    when exists (select 1 from public.profiles p where p.id = p_uid) or a.status <> 'claimed'
         or c.id is null or c.deleted_at is not null then 'closed'
    -- not verified: free only on the record the login's own sign-up made
    when a.email_verified_at is null and v_proof = 'own_record' then 'free'
    when a.email_verified_at is null then 'verify_first'
    -- verified: a code to the email; staff approve when the login is not proven to be the record's
    when v_proof is not null then 'code'
    else 'staff' end;
  return jsonb_build_object('route', v_route, 'proof', v_proof, 'verified', a.email_verified_at is not null,
    'customer_id', a.customer_id, 'first_name', c.first_name, 'last_name', c.last_name,
    'phone', c.phone, 'email', c.email, 'login_email', v_login);
end $function$;

-- The new values, checked and tidied, or why not: {changes} or {error, field}.
create or replace function public.affiliate_detail_check(p_uid uuid, p_new jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare s jsonb := public.affiliate_detail_state(p_uid); v_cust uuid := (s->>'customer_id')::uuid;
  v_out jsonb := '{}'::jsonb; k text; v text; v_phone jsonb; v_key text; v_email text;
begin
  if jsonb_typeof(p_new) is distinct from 'object' then return jsonb_build_object('error', 'invalid_request'); end if;
  foreach k in array array['first_name', 'last_name'] loop
    if p_new ? k then
      v := regexp_replace(btrim(coalesce(p_new->>k, '')), '\s+', ' ', 'g');
      if v = '' then return jsonb_build_object('error', 'name_required', 'field', k); end if;
      if length(v) > 50 then return jsonb_build_object('error', 'name_too_long', 'field', k); end if;
      -- letters, spaces, hyphens, apostrophes, full stops, "/" (as in S/O, D/O) and "@"
      if v ~ '[0-9<>{}()\[\]$%^*_=+|\\~`#&;:!?,"]' or v ~ '[[:cntrl:]]' then
        return jsonb_build_object('error', 'name_characters', 'field', k); end if;
      if v is distinct from (s->>k) then v_out := v_out || jsonb_build_object(k, v); end if;
    end if;
  end loop;
  if p_new ? 'phone' then
    v_phone := public.inspect_customer_phone(btrim(coalesce(p_new->>'phone', '')));
    if v_phone->>'status' is distinct from 'ready' or nullif(v_phone->>'normalized', '') is null then
      return jsonb_build_object('error', 'phone_invalid', 'field', 'phone', 'reason', v_phone->>'reason'); end if;
    v := v_phone->>'normalized';
    if v is distinct from public.normalize_customer_phone(s->>'phone') then
      -- no other customer holds it, and no other login signed up with it
      if exists (select 1 from public.customers c where c.deleted_at is null and c.id <> v_cust
                    and public.normalize_customer_phone(c.phone) = v)
         or exists (select 1 from public.affiliate_signup_identities i where i.auth_user_id <> p_uid
                       and public.normalize_customer_phone(i.phone) = v) then
        return jsonb_build_object('error', 'phone_in_use', 'field', 'phone'); end if;
      v_out := v_out || jsonb_build_object('phone', v);
    end if;
  end if;
  if p_new ? 'email' then
    v_email := lower(btrim(coalesce(p_new->>'email', '')));
    if length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      return jsonb_build_object('error', 'email_invalid', 'field', 'email'); end if;
    if v_email is distinct from lower(coalesce(s->>'login_email', '')) or v_email is distinct from lower(coalesce(s->>'email', '')) then
      v_key := public.customer_email_match_key(v_email);
      -- no other login has it, no other customer holds it, no other login signed up with it
      if exists (select 1 from auth.users u where u.id <> p_uid and lower(u.email) = v_email)
         or exists (select 1 from public.customers c where c.deleted_at is null and c.id <> v_cust
                       and public.customer_email_match_key(c.email) = v_key)
         or exists (select 1 from public.affiliate_signup_identities i where i.auth_user_id <> p_uid
                       and public.customer_email_match_key(i.email) = v_key) then
        return jsonb_build_object('error', 'email_in_use', 'field', 'email'); end if;
      v_out := v_out || jsonb_build_object('email', v_email);
    end if;
  end if;
  if v_out = '{}'::jsonb then return jsonb_build_object('error', 'no_change'); end if;
  return jsonb_build_object('changes', v_out);
end $function$;

-- A new 6-digit code for a request (valid 10 minutes, 5 tries); the code is
-- returned once, to the server that emails it, and only its hash is kept.
create or replace function public.affiliate_detail_new_code(p_id uuid, p_for text)
returns text language plpgsql volatile security definer set search_path to 'public' as $function$
declare b bytea := extensions.gen_random_bytes(4); v_code text;
begin
  v_code := lpad(((get_byte(b, 0)::bigint << 24 | get_byte(b, 1)::bigint << 16 | get_byte(b, 2)::bigint << 8
                   | get_byte(b, 3)::bigint) % 1000000)::text, 6, '0');
  update public.affiliate_detail_changes
     set code_hash = encode(extensions.digest(p_id::text || ':' || p_for || ':' || v_code, 'sha256'), 'hex'),
         code_for = p_for, code_expires_at = now() + interval '10 minutes', code_attempts = 0,
         code_sends = code_sends + 1, code_sent_at = now(), updated_at = now()
   where id = p_id;
  return v_code;
end $function$;

-- What the server must do to the login once the record may change: the email
-- (through Supabase Auth's admin API) when the login's email changes.
create or replace function public.affiliate_detail_apply_plan(p_id uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $function$
  select jsonb_build_object('request_id', d.id, 'auth_user_id', d.auth_user_id,
    'login_email', case when d.new_email is not null and d.new_email is distinct from lower(coalesce(d.old_login_email, ''))
                        then d.new_email end,
    'old_login_email', d.old_login_email)
    from public.affiliate_detail_changes d where d.id = p_id
$function$;

-- 1. The affiliate asks for a change (the server, for the signed-in login).
create or replace function public.affiliate_detail_change_start(p_uid uuid, p_new jsonb)
returns jsonb language plpgsql volatile security definer set search_path to 'public' as $function$
declare s jsonb; chk jsonb; r public.affiliate_detail_changes%rowtype; v_route text; v_code text;
begin
  perform pg_advisory_xact_lock(hashtext('affiliate_detail_change:' || p_uid::text));
  update public.affiliate_detail_changes set status = 'expired', updated_at = now()
   where auth_user_id = p_uid and status = 'awaiting_code' and code_expires_at < now();
  -- a change the server never finished (it stopped between the login and the record)
  update public.affiliate_detail_changes set status = 'failed', failure = 'interrupted', updated_at = now()
   where auth_user_id = p_uid and status = 'applying' and updated_at < now() - interval '10 minutes';
  if exists (select 1 from public.affiliate_detail_changes where auth_user_id = p_uid
                and status in ('awaiting_code', 'pending_staff', 'applying')) then
    return jsonb_build_object('error', 'open_request'); end if;
  if (select count(*) from public.affiliate_detail_changes
       where auth_user_id = p_uid and created_at > now() - interval '24 hours') >= 5 then
    return jsonb_build_object('error', 'too_many_requests'); end if;
  s := public.affiliate_detail_state(p_uid);
  v_route := s->>'route';
  if v_route = 'verify_first' then return jsonb_build_object('error', 'verify_first'); end if;
  if v_route not in ('free', 'code', 'staff') then return jsonb_build_object('error', 'not_allowed'); end if;
  chk := public.affiliate_detail_check(p_uid, p_new);
  if chk ? 'error' then return chk; end if;
  insert into public.affiliate_detail_changes (auth_user_id, customer_id, route, status,
      old_first_name, old_last_name, old_phone, old_email, old_login_email,
      new_first_name, new_last_name, new_phone, new_email)
  values (p_uid, (s->>'customer_id')::uuid, v_route, case when v_route = 'free' then 'applying' else 'awaiting_code' end,
      s->>'first_name', s->>'last_name', s->>'phone', s->>'email', s->>'login_email',
      chk->'changes'->>'first_name', chk->'changes'->>'last_name', chk->'changes'->>'phone', chk->'changes'->>'email')
  returning * into r;
  if v_route = 'free' then
    return jsonb_build_object('request_id', r.id, 'route', 'free', 'next', 'apply', 'apply', public.affiliate_detail_apply_plan(r.id));
  end if;
  v_code := public.affiliate_detail_new_code(r.id, 'current');
  return jsonb_build_object('request_id', r.id, 'route', v_route, 'next', 'code',
    'send', jsonb_build_object('to', r.old_login_email, 'code', v_code, 'purpose', 'current'));
end $function$;

-- 2. A code typed in.
create or replace function public.affiliate_detail_change_verify(p_uid uuid, p_id uuid, p_code text)
returns jsonb language plpgsql volatile security definer set search_path to 'public' as $function$
declare r public.affiliate_detail_changes%rowtype; v_code text; v_tries int;
begin
  select * into r from public.affiliate_detail_changes where id = p_id and auth_user_id = p_uid for update;
  if not found or r.status <> 'awaiting_code' or r.code_hash is null then return jsonb_build_object('error', 'no_request'); end if;
  if r.code_expires_at < now() then
    update public.affiliate_detail_changes set status = 'expired', updated_at = now() where id = r.id;
    return jsonb_build_object('error', 'expired'); end if;
  if coalesce(btrim(p_code), '') !~ '^[0-9]{6}$'
     or encode(extensions.digest(r.id::text || ':' || r.code_for || ':' || btrim(p_code), 'sha256'), 'hex') <> r.code_hash then
    v_tries := r.code_attempts + 1;
    update public.affiliate_detail_changes
       set code_attempts = v_tries, updated_at = now(),
           status = case when v_tries >= 5 then 'expired' else status end,
           failure = case when v_tries >= 5 then 'too_many_tries' else failure end
     where id = r.id;
    if v_tries >= 5 then return jsonb_build_object('error', 'too_many_tries'); end if;
    return jsonb_build_object('error', 'wrong_code', 'tries_left', 5 - v_tries);
  end if;
  if r.code_for = 'current' then
    update public.affiliate_detail_changes set current_proven_at = now(), code_hash = null, updated_at = now() where id = r.id;
    -- a new login email: its inbox proves itself next
    if r.new_email is not null and r.new_email is distinct from lower(coalesce(r.old_login_email, '')) then
      update public.affiliate_detail_changes set code_sends = 0 where id = r.id;
      v_code := public.affiliate_detail_new_code(r.id, 'new');
      return jsonb_build_object('request_id', r.id, 'next', 'code',
        'send', jsonb_build_object('to', r.new_email, 'code', v_code, 'purpose', 'new'));
    end if;
  else
    update public.affiliate_detail_changes set new_proven_at = now(), code_hash = null, updated_at = now() where id = r.id;
  end if;
  if r.route = 'staff' then
    update public.affiliate_detail_changes set status = 'pending_staff', updated_at = now() where id = r.id;
    return jsonb_build_object('request_id', r.id, 'next', 'pending_staff');
  end if;
  update public.affiliate_detail_changes set status = 'applying', updated_at = now() where id = r.id;
  return jsonb_build_object('request_id', r.id, 'next', 'apply', 'apply', public.affiliate_detail_apply_plan(r.id));
end $function$;

-- Another code for the same step (a minute apart, 5 in all per step).
create or replace function public.affiliate_detail_change_resend(p_uid uuid, p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path to 'public' as $function$
declare r public.affiliate_detail_changes%rowtype; v_code text;
begin
  select * into r from public.affiliate_detail_changes where id = p_id and auth_user_id = p_uid for update;
  if not found or r.status <> 'awaiting_code' then return jsonb_build_object('error', 'no_request'); end if;
  if r.code_sent_at > now() - interval '60 seconds' then
    return jsonb_build_object('error', 'wait', 'seconds', ceil(extract(epoch from r.code_sent_at + interval '60 seconds' - now()))::int); end if;
  if r.code_sends >= 5 then return jsonb_build_object('error', 'too_many_sends'); end if;
  v_code := public.affiliate_detail_new_code(r.id, r.code_for);
  return jsonb_build_object('request_id', r.id, 'next', 'code',
    'send', jsonb_build_object('to', case r.code_for when 'new' then r.new_email else r.old_login_email end,
                               'code', v_code, 'purpose', r.code_for));
end $function$;

create or replace function public.affiliate_detail_change_cancel(p_uid uuid, p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path to 'public' as $function$
begin
  update public.affiliate_detail_changes set status = 'cancelled', code_hash = null, updated_at = now()
   where id = p_id and auth_user_id = p_uid and status in ('awaiting_code', 'pending_staff');
  if not found then return jsonb_build_object('error', 'no_request'); end if;
  return jsonb_build_object('request_id', p_id, 'status', 'cancelled');
end $function$;

-- 3. After the login's email changed (or did not need to): the record, the
-- account's verification, the login's metadata, the Audit Log.
create or replace function public.affiliate_detail_change_finish(p_id uuid, p_login_ok boolean, p_failure text default null)
returns jsonb language plpgsql volatile security definer set search_path to 'public' as $function$
declare r public.affiliate_detail_changes%rowtype; v_login_changed boolean; v_proven boolean; v_changes jsonb;
begin
  select * into r from public.affiliate_detail_changes where id = p_id for update;
  if not found or r.status <> 'applying' then return jsonb_build_object('error', 'not_applying'); end if;
  if not coalesce(p_login_ok, false) then
    update public.affiliate_detail_changes set status = 'failed', failure = left(coalesce(p_failure, 'login email not changed'), 300),
           updated_at = now() where id = r.id;
    return jsonb_build_object('request_id', r.id, 'status', 'failed');
  end if;
  v_login_changed := r.new_email is not null and r.new_email is distinct from lower(coalesce(r.old_login_email, ''));
  v_proven := r.new_proven_at is not null;
  perform set_config('energia.phone_change_reason', 'Changed by the affiliate in the portal', true);
  update public.customers
     set first_name = coalesce(r.new_first_name, first_name), last_name = coalesce(r.new_last_name, last_name),
         phone = coalesce(r.new_phone, phone), email = coalesce(r.new_email, email)
   where id = r.customer_id;
  if v_login_changed then
    update public.affiliate_accounts
       set login_email_changed_at = now(),
           email_verified_at = case when v_proven then now() end, updated_at = now()
     where auth_user_id = r.auth_user_id;
    update auth.users
       set raw_app_meta_data = case when v_proven
             then (coalesce(raw_app_meta_data, '{}'::jsonb) - 'affiliate_email_unverified') || jsonb_build_object('affiliate_email_verified_at', now())
             else (coalesce(raw_app_meta_data, '{}'::jsonb) - 'affiliate_email_verified_at') || jsonb_build_object('affiliate_email_unverified', true) end
     where id = r.auth_user_id;
  end if;
  -- the greeting and WhatsApp names and phone the login carries
  update auth.users
     set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
           || jsonb_strip_nulls(jsonb_build_object('first_name', r.new_first_name, 'last_name', r.new_last_name, 'phone', r.new_phone))
   where id = r.auth_user_id and (r.new_first_name is not null or r.new_last_name is not null or r.new_phone is not null);
  update public.affiliate_detail_changes set status = 'applied', applied_at = now(), code_hash = null, updated_at = now() where id = r.id;
  v_changes := jsonb_strip_nulls(jsonb_build_object('first_name', r.new_first_name, 'last_name', r.new_last_name,
                                                    'phone', r.new_phone, 'email', r.new_email));
  begin
    insert into public.audit_logs (table_name, record_id, action, old_data, new_data, changed_by, module, reason)
    values ('customers', r.customer_id, 'customer_details_changed_by_affiliate',
      jsonb_build_object('first_name', r.old_first_name, 'last_name', r.old_last_name, 'phone', r.old_phone,
                         'email', r.old_email, 'login_email', r.old_login_email),
      v_changes || jsonb_build_object('auth_user_id', r.auth_user_id, 'request_id', r.id, 'route', r.route),
      r.decided_by, 'affiliate', case r.route when 'staff' then 'Approved by staff' when 'code' then 'Confirmed by email code' else 'Unverified account, its own record' end);
  exception when others then
    raise warning '491: the audit row was not saved: %', sqlerrm;
  end;
  return jsonb_build_object('request_id', r.id, 'status', 'applied', 'changes', v_changes,
    'notify', jsonb_build_object('to', r.old_login_email, 'login_email_changed', v_login_changed));
end $function$;

-- Staff: an Owner or Manager decides a request that waits for them.
create or replace function public.affiliate_detail_change_decide(p_staff_uid uuid, p_id uuid, p_approve boolean, p_note text)
returns jsonb language plpgsql volatile security definer set search_path to 'public' as $function$
declare r public.affiliate_detail_changes%rowtype; v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if not exists (select 1 from public.profiles p where p.id = p_staff_uid and p.is_active and p.role::text in ('owner', 'manager')) then
    return jsonb_build_object('error', 'not_allowed'); end if;
  select * into r from public.affiliate_detail_changes where id = p_id for update;
  if not found or r.status <> 'pending_staff' then return jsonb_build_object('error', 'no_request'); end if;
  if not coalesce(p_approve, false) then
    if v_note is null then return jsonb_build_object('error', 'note_required'); end if;
    update public.affiliate_detail_changes set status = 'rejected', decided_by = p_staff_uid, decided_at = now(),
           decision_note = left(v_note, 500), updated_at = now() where id = r.id;
    return jsonb_build_object('request_id', r.id, 'status', 'rejected');
  end if;
  update public.affiliate_detail_changes set status = 'applying', decided_by = p_staff_uid, decided_at = now(),
         decision_note = left(v_note, 500), updated_at = now() where id = r.id;
  return jsonb_build_object('request_id', r.id, 'next', 'apply', 'apply', public.affiliate_detail_apply_plan(r.id));
end $function$;

-- The portal's Your details: the record's details, what the login may do,
-- and its latest request (never a code or its hash).
create or replace function public.affiliate_portal_details()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare v_uid uuid := auth.uid(); s jsonb; v_req jsonb;
begin
  if v_uid is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  s := public.affiliate_detail_state(v_uid);
  if s->>'route' = 'not_affiliate' then raise exception 'Not an affiliate account'; end if;
  select jsonb_build_object('id', d.id, 'route', d.route, 'status', d.status,
           'new_first_name', d.new_first_name, 'new_last_name', d.new_last_name, 'new_phone', d.new_phone, 'new_email', d.new_email,
           'code_for', case when d.status = 'awaiting_code' then d.code_for end,
           'code_to', case when d.status = 'awaiting_code' then case d.code_for when 'new' then d.new_email else d.old_login_email end end,
           'code_expires_at', case when d.status = 'awaiting_code' then d.code_expires_at end,
           'created_at', d.created_at, 'decided_at', d.decided_at, 'decision_note', d.decision_note, 'applied_at', d.applied_at)
    into v_req
    from public.affiliate_detail_changes d
   where d.auth_user_id = v_uid and d.created_at > now() - interval '30 days'
   order by d.created_at desc limit 1;
  return jsonb_build_object('route', s->'route', 'verified', s->'verified',
    'first_name', s->'first_name', 'last_name', s->'last_name', 'phone', s->'phone', 'email', s->'email',
    'login_email', s->'login_email', 'request', v_req);
end $function$;

-- Staff: the requests that wait for an Owner or Manager, with what the
-- affiliate signed up with to compare.
create or replace function public.affiliate_detail_change_requests()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can review detail changes' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'created_at', d.created_at, 'customer_id', d.customer_id,
            'customer_name', c.full_name,
            'old', jsonb_build_object('first_name', d.old_first_name, 'last_name', d.old_last_name, 'phone', d.old_phone,
                                      'email', d.old_email, 'login_email', d.old_login_email),
            'new', jsonb_strip_nulls(jsonb_build_object('first_name', d.new_first_name, 'last_name', d.new_last_name,
                                                        'phone', d.new_phone, 'email', d.new_email)),
            'signed_up_with', (select jsonb_build_object('name', coalesce(i.full_name, btrim(coalesce(i.first_name, '') || ' ' || coalesce(i.last_name, ''))),
                                                         'phone', i.phone, 'email', i.email)
                                 from public.affiliate_signup_identities i where i.auth_user_id = d.auth_user_id
                                order by i.created_at limit 1),
            'new_email_proven', d.new_proven_at is not null) order by d.created_at)
      from public.affiliate_detail_changes d join public.customers c on c.id = d.customer_id
     where d.status = 'pending_staff'), '[]'::jsonb);
end $function$;

-- Staff: a phone number the affiliate changed themselves since their last
-- payout (PayNow goes to the record's phone), or null.
create or replace function public.affiliate_self_phone_change(p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can see this' using errcode = '42501'; end if;
  return (select jsonb_build_object('changed_at', d.applied_at, 'old_phone', d.old_phone, 'new_phone', d.new_phone)
            from public.affiliate_detail_changes d
           where d.customer_id = p_customer_id and d.status = 'applied' and d.new_phone is not null
             and d.applied_at > coalesce((select max(p.created_at) from public.commission_payouts p
                                           where p.referrer_customer_id = p_customer_id and p.status <> 'void'), '-infinity')
           order by d.applied_at desc limit 1);
end $function$;

-- Any change of a login's email that is not the portal's own (Supabase
-- Auth's own email change from a browser, or an Owner in the dashboard):
-- the email is no longer verified, and a link sent before no longer counts.
create or replace function public.affiliate_login_email_changed()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  -- The portal's own change, or its putting the old email back when the
  -- record could not be saved: affiliate_detail_change_finish sets what follows.
  if exists (select 1 from public.affiliate_detail_changes d
              where d.auth_user_id = new.id and d.status = 'applying'
                and (d.new_email = lower(new.email) or lower(d.old_login_email) = lower(new.email))) then
    return new;
  end if;
  update public.affiliate_accounts set email_verified_at = null, login_email_changed_at = now(), updated_at = now()
   where auth_user_id = new.id;
  if found then
    update auth.users set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) - 'affiliate_email_verified_at'
     where id = new.id;
    begin
      insert into public.audit_logs (table_name, record_id, action, old_data, new_data, module)
      select 'affiliate_accounts', a.id, 'affiliate_login_email_changed_elsewhere',
             jsonb_build_object('login_email', old.email), jsonb_build_object('login_email', new.email, 'auth_user_id', new.id), 'affiliate'
        from public.affiliate_accounts a where a.auth_user_id = new.id;
    exception when others then
      raise warning '491: the audit row was not saved: %', sqlerrm;
    end;
  end if;
  return new;
end $function$;

do $trg$
begin
  if not exists (select 1 from pg_trigger where tgname = 'affiliate_login_email_changed' and tgrelid = 'auth.users'::regclass) then
    create trigger affiliate_login_email_changed after update of email on auth.users
      for each row when (old.email is distinct from new.email) execute function public.affiliate_login_email_changed();
  end if;
end $trg$;

revoke all on function public.affiliate_detail_state(uuid), public.affiliate_detail_check(uuid, jsonb),
  public.affiliate_detail_new_code(uuid, text), public.affiliate_detail_apply_plan(uuid),
  public.affiliate_detail_change_start(uuid, jsonb), public.affiliate_detail_change_verify(uuid, uuid, text),
  public.affiliate_detail_change_resend(uuid, uuid), public.affiliate_detail_change_cancel(uuid, uuid),
  public.affiliate_detail_change_finish(uuid, boolean, text), public.affiliate_detail_change_decide(uuid, uuid, boolean, text),
  public.affiliate_portal_details(), public.affiliate_detail_change_requests(), public.affiliate_self_phone_change(uuid),
  public.affiliate_login_email_changed()
  from public, anon, authenticated;
grant execute on function public.affiliate_detail_state(uuid), public.affiliate_detail_check(uuid, jsonb),
  public.affiliate_detail_new_code(uuid, text), public.affiliate_detail_apply_plan(uuid),
  public.affiliate_detail_change_start(uuid, jsonb), public.affiliate_detail_change_verify(uuid, uuid, text),
  public.affiliate_detail_change_resend(uuid, uuid), public.affiliate_detail_change_cancel(uuid, uuid),
  public.affiliate_detail_change_finish(uuid, boolean, text), public.affiliate_detail_change_decide(uuid, uuid, boolean, text)
  to service_role;
grant execute on function public.affiliate_portal_details(), public.affiliate_detail_change_requests(),
  public.affiliate_self_phone_change(uuid) to authenticated, service_role;

-- 491: confirm_affiliate_email refuses a link sent before the login's email last
-- changed (BEFORE 431ff39a, AFTER 8a0a7036; the pre-check refused anything else).
CREATE OR REPLACE FUNCTION public.confirm_affiliate_email()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid := auth.uid(); v_acct public.affiliate_accounts%rowtype;
begin
  -- 437 (the Owner, 20 Oct 2026): an affiliate verifies their email later,
  -- from the Account page. Its email holds a sign-in link to
  -- /affiliate/verify; a session opened from it in the last 30 minutes marks
  -- the email verified. Nothing waits on it: the portal, the referral link,
  -- commission and payouts work the same before.
  if v_uid is null then raise exception 'Not authenticated' using errcode = '42501'; end if;
  select * into v_acct from public.affiliate_accounts where auth_user_id = v_uid for update;
  if not found then return jsonb_build_object('verified', false, 'reason', 'not_affiliate'); end if;
  if v_acct.email_verified_at is not null then
    return jsonb_build_object('verified', true, 'already', true, 'verified_at', v_acct.email_verified_at);
  end if;
  if not public.affiliate_session_from_email_link() then
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
end $function$;

-- ══ 3. Checks after installing, and the self-test ══
do $test$
declare i int; f text;
  c_server constant text[] := array['affiliate_detail_state(uuid)', 'affiliate_detail_check(uuid,jsonb)',
    'affiliate_detail_new_code(uuid,text)', 'affiliate_detail_apply_plan(uuid)', 'affiliate_detail_change_start(uuid,jsonb)',
    'affiliate_detail_change_verify(uuid,uuid,text)', 'affiliate_detail_change_resend(uuid,uuid)', 'affiliate_detail_change_cancel(uuid,uuid)',
    'affiliate_detail_change_finish(uuid,boolean,text)', 'affiliate_detail_change_decide(uuid,uuid,boolean,text)'];
  c_portal constant text[] := array['affiliate_portal_details()', 'affiliate_detail_change_requests()', 'affiliate_self_phone_change(uuid)'];
  t_sfx text; t_base int; t_ph text[]; t_uid uuid; t_cust uuid; t_aff uuid; t_other uuid; t_srr text;
  r jsonb; t_id uuid; t_code text; t_mail text; t_new text;
begin
  perform set_config('search_path', 'public', true);
  if md5(pg_get_functiondef('public.confirm_affiliate_email()'::regprocedure)) <> '8a0a7036312cf5dc22dd2beb82b3ce09' then
    raise exception '491: confirm_affiliate_email was installed with an md5 other than the tested one'; end if;
  foreach f in array c_server loop
    if has_function_privilege('anon', 'public.' || f, 'execute') or has_function_privilege('authenticated', 'public.' || f, 'execute')
       or not has_function_privilege('service_role', 'public.' || f, 'execute') then
      raise exception '491: public.% must be runnable by the service role alone', f; end if;
  end loop;
  foreach f in array c_portal loop
    if has_function_privilege('anon', 'public.' || f, 'execute') or not has_function_privilege('authenticated', 'public.' || f, 'execute') then
      raise exception '491: public.% must be runnable when signed in, never signed out', f; end if;
  end loop;
  if has_function_privilege('anon', 'public.affiliate_login_email_changed()', 'execute')
     or has_function_privilege('authenticated', 'public.affiliate_login_email_changed()', 'execute') then
    raise exception '491: the trigger function must not be callable from a browser'; end if;
  if has_table_privilege('anon', 'public.affiliate_detail_changes', 'select') or has_table_privilege('authenticated', 'public.affiliate_detail_changes', 'select')
     or has_table_privilege('authenticated', 'public.affiliate_detail_changes', 'insert') or has_table_privilege('authenticated', 'public.affiliate_detail_changes', 'update')
     or not (select relrowsecurity from pg_class where oid = 'public.affiliate_detail_changes'::regclass) then
    raise exception '491: affiliate_detail_changes must be closed to browsers (no grants, row level security on)'; end if;
  if not exists (select 1 from pg_trigger t where t.tgname = 'affiliate_login_email_changed' and t.tgrelid = 'auth.users'::regclass and t.tgenabled = 'O') then
    raise exception '491: the trigger affiliate_login_email_changed on auth.users is missing or off'; end if;

  -- The self-test, in a block that is always undone (it ends by raising
  -- P0491). Made-up records only ("491 Check", @example.invalid, fictional
  -- +61 2 5550 phones).
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    -- (range scans of the two partial phone indexes, as 486's; the sign-up
    -- copies' phones normalised once: 0.7 s on production, 3 Nov 2026)
    with ids as materialized (select public.normalize_customer_phone(i.phone) as p from public.affiliate_signup_identities i)
    select min(g) into t_base from generate_series(2000, 9980, 10) g
     where not exists (select 1 from public.customers c
                        where c.deleted_at is null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'))
       and not exists (select 1 from public.customers c
                        where c.deleted_at is not null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'))
       and not exists (select 1 from ids
                        where ids.p between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'));
    if t_base is null then raise exception '491: the self-test found no free fictional phones'; end if;
    t_ph := array(select '+6125550' || lpad((t_base + n)::text, 4, '0') from generate_series(0, 2) n);
    t_mail := '491chk-' || t_sfx || '@example.invalid';
    t_new := '491chk-new-' || t_sfx || '@example.invalid';
    -- A login and the record its own sign-up made, in one transaction (484: own_record).
    insert into auth.users (id, email) values (gen_random_uuid(), t_mail) returning id into t_uid;
    insert into public.customers (first_name, last_name, full_name, phone, email)
    values ('Check', 'Affiliate', 'Check Affiliate', t_ph[1], t_mail) returning id into t_cust;
    insert into public.customer_affiliates (customer_id, status, activated_at, referral_code)
    values (t_cust, 'active', now(), '491CHK' || upper(t_sfx)) returning id into t_aff;
    -- the portal account with triggers off for this statement only (its welcome WhatsApp takes a sequence number)
    t_srr := current_setting('session_replication_role');
    set local session_replication_role = replica;
    insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status) values (t_uid, t_cust, t_aff, 'claimed');
    execute format('set local session_replication_role = %L', t_srr);
    insert into public.customers (full_name, phone) values ('491 Check Other', t_ph[3]) returning id into t_other;

    -- 1. Not verified, on its own record: free.
    if public.affiliate_detail_state(t_uid)->>'route' <> 'free' then
      raise exception '491: an unverified login on its own record should change freely, not %', public.affiliate_detail_state(t_uid)->>'route'; end if;
    r := public.affiliate_detail_change_start(t_uid, jsonb_build_object('phone', t_ph[2]));
    if r->>'next' is distinct from 'apply' then raise exception '491: the free change did not go straight to apply: %', r; end if;
    r := public.affiliate_detail_change_finish((r->>'request_id')::uuid, true, null);
    if r->>'status' is distinct from 'applied' or (select public.normalize_customer_phone(phone) from public.customers where id = t_cust) <> t_ph[2] then
      raise exception '491: the free phone change was not applied: %', r; end if;

    -- 2. Refusals: another customer's phone, digits in a name, nothing new.
    if public.affiliate_detail_check(t_uid, jsonb_build_object('phone', t_ph[3]))->>'error' is distinct from 'phone_in_use'
       or public.affiliate_detail_check(t_uid, jsonb_build_object('first_name', 'Ch3ck'))->>'error' is distinct from 'name_characters'
       or public.affiliate_detail_check(t_uid, jsonb_build_object('first_name', 'Check'))->>'error' is distinct from 'no_change' then
      raise exception '491: a change that must be refused was not'; end if;

    -- 3. Verified: a code to the current email first.
    update public.affiliate_accounts set email_verified_at = now() where auth_user_id = t_uid;
    r := public.affiliate_detail_change_start(t_uid, jsonb_build_object('first_name', 'Checked'));
    if r->>'next' is distinct from 'code' or r->'send'->>'to' is distinct from t_mail or r->'send'->>'code' !~ '^[0-9]{6}$' then
      raise exception '491: a verified change did not send a code to the current email: %', r - 'send'; end if;
    t_id := (r->>'request_id')::uuid; t_code := r->'send'->>'code';
    if public.affiliate_detail_change_verify(t_uid, t_id, case when t_code = '000000' then '111111' else '000000' end)->>'error' is distinct from 'wrong_code' then
      raise exception '491: a wrong code was not refused'; end if;
    r := public.affiliate_detail_change_verify(t_uid, t_id, t_code);
    if r->>'next' is distinct from 'apply' then raise exception '491: the right code did not lead to apply: %', r; end if;
    r := public.affiliate_detail_change_finish(t_id, true, null);
    if (select first_name from public.customers where id = t_cust) is distinct from 'Checked' then
      raise exception '491: the name was not changed'; end if;

    -- 4. A new email: the current inbox, then the new one; the account stays verified.
    r := public.affiliate_detail_change_start(t_uid, jsonb_build_object('email', t_new));
    t_id := (r->>'request_id')::uuid;
    r := public.affiliate_detail_change_verify(t_uid, t_id, r->'send'->>'code');
    if r->>'next' is distinct from 'code' or r->'send'->>'to' is distinct from t_new then
      raise exception '491: the new email did not get its own code: %', r - 'send'; end if;
    r := public.affiliate_detail_change_verify(t_uid, t_id, r->'send'->>'code');
    if r->'apply'->>'login_email' is distinct from t_new then raise exception '491: the plan does not change the login email: %', r; end if;
    -- as Supabase Auth's admin API changes it: the trigger knows it as the portal's own
    update auth.users set email = t_new where id = t_uid;
    if (select email_verified_at from public.affiliate_accounts where auth_user_id = t_uid) is null then
      raise exception '491: the portal''s own email change was taken for another'; end if;
    r := public.affiliate_detail_change_finish(t_id, true, null);
    if (select email from public.customers where id = t_cust) is distinct from t_new
       or (select email_verified_at is null or login_email_changed_at is null from public.affiliate_accounts where auth_user_id = t_uid) then
      raise exception '491: the new email was not applied as verified'; end if;

    -- 5. A link sent before the change no longer verifies.
    update public.affiliate_accounts set email_verified_at = null where auth_user_id = t_uid;
    perform set_config('request.jwt.claim.sub', t_uid::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', t_uid, 'role', 'authenticated',
      'amr', json_build_array(json_build_object('method', 'magiclink',
        'timestamp', floor(extract(epoch from (select login_email_changed_at from public.affiliate_accounts where auth_user_id = t_uid))) - 60)))::text, true);
    r := public.confirm_affiliate_email();
    if r->>'reason' is distinct from 'email_changed_since_link' then
      raise exception '491: a link from before the email change still verified: %', r; end if;
    update public.affiliate_accounts set email_verified_at = now() where auth_user_id = t_uid;

    -- 6. Any other change of the login's email: no longer verified.
    update auth.users set email = '491chk-else-' || t_sfx || '@example.invalid' where id = t_uid;
    if (select email_verified_at from public.affiliate_accounts where auth_user_id = t_uid) is not null then
      raise exception '491: a login email changed elsewhere stayed verified'; end if;

    raise exception using errcode = 'P0491', message = '491: self-test done, undone';
  exception when sqlstate 'P0491' then null;
  end;
  perform pg_notify('pgrst', 'reload schema');
end $test$;
