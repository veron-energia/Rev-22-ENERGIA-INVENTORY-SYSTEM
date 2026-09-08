-- =====================================================================
-- 200_auth_email_delivery.sql
--
-- Server-side support for Auth email delivery through Pabbly Connect.
--
-- Supabase Auth keeps doing everything that matters: users, password hashing,
-- verification and recovery tokens, sessions and token validation. This
-- migration only adds what an Edge Function needs in front of it:
--
--   1. auth_email_limits      — every rate-limit threshold, in one adjustable table.
--   2. auth_email_rate_events — the sliding-window counters.
--   3. auth_email_deliveries  — what happened to each send, for troubleshooting.
--   4. auth_email_reserve()   — atomically admit-or-refuse one request.
--   5. auth_email_record_outcome() — record delivery outcome, separately from admission.
--   6. auth_email_user_state()     — 'none' | 'unconfirmed' | 'confirmed', so a
--      resend never creates an account and never re-mails a verified one.
--   7. auth_email_cleanup()   — retention, ~14 days.
--
-- Everything here is service-role only. RLS is on with no policies, so anon and
-- authenticated cannot read a single row even if a grant were added by mistake.
--
-- Nothing in this migration alters an existing table, function, view, policy or
-- trigger, and nothing existing depends on it. Numbered 200 to leave 180–199
-- free for the in-flight invoice series (170–179).
--
-- Email addresses and IPs are stored only as keyed hashes (HMAC computed in the
-- Edge Function). No passwords, action links, tokens or provider secrets are
-- stored anywhere in this schema.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Thresholds — the single source of truth.
--
-- To adjust a limit, UPDATE this table. No redeploy of any Edge Function is
-- needed; auth_email_reserve() reads it on every call.
--
-- Defaults sized so that up to ~10 people sharing one roadshow Wi-Fi IP are
-- never the ones who get blocked: the per-IP ceilings are far above 10 people
-- doing one signup and one resend each, while the per-email ceilings stay tight.
-- ---------------------------------------------------------------------
create table if not exists public.auth_email_limits (
  action          text        not null check (action in ('signup','resend','recovery','combined')),
  scope           text        not null check (scope in ('email','ip')),
  max_attempts    integer     not null check (max_attempts > 0),
  window_seconds  integer     not null check (window_seconds > 0),
  updated_at      timestamptz not null default now(),
  primary key (action, scope)
);

comment on table public.auth_email_limits is
  'Rate-limit thresholds for public Auth-email endpoints. UPDATE to adjust; no redeploy needed.';

insert into public.auth_email_limits (action, scope, max_attempts, window_seconds) values
  ('signup',   'email',  3,  900),      -- 3 per normalized email per 15 minutes
  ('signup',   'ip',    30, 3600),      -- 30 per reliable client IP per hour
  ('resend',   'email',  3,  900),
  ('resend',   'ip',    30, 3600),
  ('recovery', 'email',  5, 3600),      -- 5 per normalized email per hour
  ('recovery', 'ip',    60, 3600),
  ('combined', 'ip',    60, 3600)       -- all public Auth-email requests per IP per hour
on conflict (action, scope) do nothing;

-- ---------------------------------------------------------------------
-- 2. Sliding-window counters.
--
-- key_hash is an HMAC of the normalized email or of the platform-supplied client
-- IP, keyed with a secret the database never sees. Plaintext never lands here.
-- ---------------------------------------------------------------------
create table if not exists public.auth_email_rate_events (
  id           bigserial   primary key,
  action       text        not null,
  scope        text        not null,
  key_hash     text        not null,
  occurred_at  timestamptz not null default now()
);

create index if not exists auth_email_rate_events_bucket_idx
  on public.auth_email_rate_events (action, scope, key_hash, occurred_at desc);
create index if not exists auth_email_rate_events_cleanup_idx
  on public.auth_email_rate_events (occurred_at);

-- ---------------------------------------------------------------------
-- 3. Delivery outcomes — deliberately separate from admission.
--
-- A request can be admitted, generate a link, and still fail to reach Gmail.
-- Those are different facts and are recorded as different rows/columns so that
-- "we accepted the request" is never mistaken for "the email arrived".
--
-- outcome values:
--   requested          — admitted; link generated; not yet handed to Pabbly
--   suppressed         — deliberately not sent (no such account / already verified)
--   accepted           — Pabbly returned 2xx. NOT proof the email was sent.
--   provider_rejected  — Pabbly returned a non-2xx status
--   timeout            — no response within the bounded timeout; may or may not have sent
--   failed             — could not reach Pabbly at all
-- ---------------------------------------------------------------------
create table if not exists public.auth_email_deliveries (
  request_id      uuid        primary key,
  action          text        not null,
  recipient_hash  text,
  outcome         text        not null check (outcome in
                    ('requested','suppressed','accepted','provider_rejected','timeout','failed')),
  http_status     integer,
  detail          text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists auth_email_deliveries_created_idx
  on public.auth_email_deliveries (created_at);
create index if not exists auth_email_deliveries_outcome_idx
  on public.auth_email_deliveries (outcome, created_at desc);

comment on column public.auth_email_deliveries.detail is
  'Short, truncated provider message for troubleshooting. Never a link, token or secret.';

-- ---------------------------------------------------------------------
-- 4. Atomic reservation.
--
-- Called BEFORE a link is generated and BEFORE Pabbly is contacted, so a
-- refused request costs nothing downstream and an admitted one is already paid
-- for. A reservation is never refunded: a failed signup, an unknown email and a
-- provider error all consume their slot, which is what stops unlimited retries.
--
-- Atomicity: one transaction-scoped advisory lock serializes the whole
-- check-then-insert across every concurrent caller, so N parallel requests can
-- never all read "count = max - 1" and all insert. The lock is global to this
-- limiter rather than per-bucket because a single request touches three buckets
-- (email, IP, combined) and per-bucket locks would need a deadlock-safe
-- ordering. At the volumes these endpoints see (tens per hour) the serialization
-- is free, and being transaction-scoped it is released on commit or rollback —
-- a crashed caller cannot wedge the limiter.
--
-- The per-email limit is mandatory. If the platform cannot give a trustworthy
-- client IP the caller passes NULL and only the email buckets apply; the request
-- is still limited, never waved through.
--
-- Returns: { allowed, retry_after_seconds, scope, action }
-- ---------------------------------------------------------------------
create or replace function public.auth_email_reserve(
  p_action     text,
  p_email_hash text,
  p_ip_hash    text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_bucket        record;
  v_limit         record;
  v_used          integer;
  v_oldest        timestamptz;
  v_retry         integer;
  v_buckets       jsonb := '[]'::jsonb;
begin
  if p_action is null or p_action not in ('signup','resend','recovery') then
    raise exception 'AUTH_EMAIL_UNKNOWN_ACTION';
  end if;
  if p_email_hash is null or length(btrim(p_email_hash)) = 0 then
    raise exception 'AUTH_EMAIL_MISSING_EMAIL_KEY';
  end if;

  perform pg_advisory_xact_lock(hashtext('public.auth_email_reserve'));

  -- The buckets this request must fit inside.
  v_buckets := jsonb_build_array(jsonb_build_object('action', p_action, 'scope', 'email', 'key', p_email_hash));
  if p_ip_hash is not null and length(btrim(p_ip_hash)) > 0 then
    v_buckets := v_buckets
      || jsonb_build_array(jsonb_build_object('action', p_action,   'scope', 'ip', 'key', p_ip_hash))
      || jsonb_build_array(jsonb_build_object('action', 'combined', 'scope', 'ip', 'key', p_ip_hash));
  end if;

  -- Check every bucket first; only insert once all of them pass.
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
      v_retry := greatest(1, ceil(extract(epoch from
                   (v_oldest + make_interval(secs => v_limit.window_seconds)) - now()))::integer);
      return jsonb_build_object(
        'allowed', false,
        'retry_after_seconds', v_retry,
        'scope', v_bucket.scope,
        'action', v_bucket.action);
    end if;
  end loop;

  insert into public.auth_email_rate_events (action, scope, key_hash)
  select x.action, x.scope, x.key
    from jsonb_to_recordset(v_buckets) as x(action text, scope text, key text);

  return jsonb_build_object('allowed', true, 'retry_after_seconds', 0);
end
$function$;

-- ---------------------------------------------------------------------
-- 5. Delivery outcome, recorded separately from admission.
-- ---------------------------------------------------------------------
create or replace function public.auth_email_record_outcome(
  p_request_id     uuid,
  p_action         text,
  p_outcome        text,
  p_recipient_hash text default null,
  p_http_status    integer default null,
  p_detail         text default null)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  insert into public.auth_email_deliveries
    (request_id, action, recipient_hash, outcome, http_status, detail)
  values
    (p_request_id, p_action, p_recipient_hash, p_outcome, p_http_status, left(p_detail, 500))
  on conflict (request_id) do update
    set outcome     = excluded.outcome,
        http_status = excluded.http_status,
        detail      = excluded.detail,
        updated_at  = now();
end
$function$;

-- ---------------------------------------------------------------------
-- 6. Account state, without leaking it.
--
-- The Edge Function needs to know whether an address has no account, an
-- unconfirmed one, or a verified one — so that a resend can never create an
-- account and never re-mail somebody who is already verified. The answer stays
-- server-side: the public HTTP responses are identical in all three cases.
-- ---------------------------------------------------------------------
create or replace function public.auth_email_user_state(p_email text)
returns text
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_confirmed timestamptz; v_found boolean := false;
begin
  select u.email_confirmed_at, true into v_confirmed, v_found
    from auth.users u
   where lower(btrim(u.email)) = lower(btrim(p_email))
     and u.deleted_at is null
   order by u.created_at
   limit 1;

  if not coalesce(v_found, false) then return 'none'; end if;
  return case when v_confirmed is null then 'unconfirmed' else 'confirmed' end;
end
$function$;

-- ---------------------------------------------------------------------
-- 7. Retention. Nothing here is needed beyond a fortnight of troubleshooting,
--    and the rate windows are hours at most.
--
--    Run from the Supabase dashboard (Integrations → Cron) as:
--      select public.auth_email_cleanup();
--    daily. Until that schedule exists the tables simply grow slowly; the
--    indexes above keep reserve() fast regardless, because every count is
--    bounded by the window, not by table size.
-- ---------------------------------------------------------------------
create or replace function public.auth_email_cleanup(p_retention interval default interval '14 days')
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_events bigint; v_deliveries bigint;
begin
  delete from public.auth_email_rate_events where occurred_at < now() - p_retention;
  get diagnostics v_events = row_count;
  delete from public.auth_email_deliveries where created_at < now() - p_retention;
  get diagnostics v_deliveries = row_count;
  return jsonb_build_object('rate_events_deleted', v_events, 'deliveries_deleted', v_deliveries);
end
$function$;

-- ---------------------------------------------------------------------
-- 8. Lock everything down to the service role.
-- ---------------------------------------------------------------------
alter table public.auth_email_limits       enable row level security;
alter table public.auth_email_rate_events  enable row level security;
alter table public.auth_email_deliveries   enable row level security;

-- No policies are created on purpose: with RLS on and no policy, every role that
-- respects RLS (anon, authenticated) reads nothing. service_role bypasses RLS.
revoke all on table public.auth_email_limits      from public, anon, authenticated;
revoke all on table public.auth_email_rate_events from public, anon, authenticated;
revoke all on table public.auth_email_deliveries  from public, anon, authenticated;
grant select, insert, update, delete on table public.auth_email_limits      to service_role;
grant select, insert, update, delete on table public.auth_email_rate_events to service_role;
grant select, insert, update, delete on table public.auth_email_deliveries  to service_role;
grant usage, select on sequence public.auth_email_rate_events_id_seq to service_role;

revoke all on function public.auth_email_reserve(text,text,text)                       from public, anon, authenticated;
revoke all on function public.auth_email_record_outcome(uuid,text,text,text,integer,text) from public, anon, authenticated;
revoke all on function public.auth_email_user_state(text)                              from public, anon, authenticated;
revoke all on function public.auth_email_cleanup(interval)                             from public, anon, authenticated;

grant execute on function public.auth_email_reserve(text,text,text)                       to service_role;
grant execute on function public.auth_email_record_outcome(uuid,text,text,text,integer,text) to service_role;
grant execute on function public.auth_email_user_state(text)                              to service_role;
grant execute on function public.auth_email_cleanup(interval)                             to service_role;

-- ---------------------------------------------------------------------
-- 9. Verification — fail loudly if any piece is missing or reachable.
-- ---------------------------------------------------------------------
do $$
declare v_missing text;
begin
  foreach v_missing in array array['auth_email_reserve','auth_email_record_outcome',
                                   'auth_email_user_state','auth_email_cleanup'] loop
    if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname = v_missing) then
      raise exception 'migration 200: % missing', v_missing;
    end if;
  end loop;

  foreach v_missing in array array['auth_email_limits','auth_email_rate_events','auth_email_deliveries'] loop
    if not exists (select 1 from pg_tables where schemaname = 'public' and tablename = v_missing) then
      raise exception 'migration 200: table % missing', v_missing;
    end if;
    if not (select relrowsecurity from pg_class where oid = ('public.' || v_missing)::regclass) then
      raise exception 'migration 200: RLS not enabled on %', v_missing;
    end if;
    if has_table_privilege('anon', 'public.' || v_missing, 'select')
       or has_table_privilege('authenticated', 'public.' || v_missing, 'select') then
      raise exception 'migration 200: % is readable by anon/authenticated', v_missing;
    end if;
  end loop;

  if (select count(*) from public.auth_email_limits) < 7 then
    raise exception 'migration 200: rate-limit thresholds not seeded';
  end if;
end $$;
