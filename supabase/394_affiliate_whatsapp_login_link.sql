-- 394_affiliate_whatsapp_login_link.sql
--
-- WHAT THE OWNER ASKED (6 Oct 2026, final)
--
-- An affiliate should get a WhatsApp with their login link when their portal
-- account goes live, so they do not have to come back to us to find it:
--
--   1. when a self sign-up goes live (complete_affiliate_onboarding links the
--      login to a customer),
--   2. when staff Resolve an account claim (resolve_affiliate_account_claim),
--   3. when an Owner reactivates a suspended affiliate that has a login.
--
-- 1 and 2 are both a new row in affiliate_accounts. 3 is reactivate_affiliate
-- setting customer_affiliates.manually_suspended back to false. Nobody who
-- already has a login gets anything: there is no backfill.
--
-- The message (draft wording, to be approved by the Owner; it lives in one
-- function, affiliate_whatsapp_message, so it can be changed in one place):
--
--   Hi Jane, welcome to the Energia affiliate programme! Your account is now active.
--
--   Log in: <app>/affiliate/login
--   Forgot your password? <app>/affiliate/forgot-password
--
--   Your referral link to share with friends and family: <app>/r/<code>
--
--   In your portal you can see your referrals, earnings and payouts.
--
--   Rev 22 Global Energia
--
-- The reactivation message starts "Hi Jane, your Energia affiliate account is
-- active again." and has the same links. <app> is
-- https://rev-22-energia-inventory-system.vercel.app (a setting).
--
-- HOW IT IS SENT
--
-- The database does not talk to WhatsApp. It keeps an outbox, and every
-- minute pg_cron posts what is waiting to a Pabbly Connect "Catch Webhook".
-- The Pabbly workflow checks the shared secret and sends the message through
-- WbizTool from +65 8572 9186, as the TikTok lead messages are sent. The
-- workflow is not built yet: scripts/affiliate-whatsapp/PABBLY_SETUP.md says
-- how, and how to fill in the settings below.
--
-- WHAT THIS DOES
--
--   * affiliate_whatsapp_settings: one row. enabled (false), webhook_url
--     (null), secret (null) and app_url. Nothing is posted until an Owner sets
--     the Pabbly webhook address and a secret and turns it on. This file never
--     holds the real address or secret (the repository is public); they are
--     typed into the SQL editor by hand. No client role can read the table.
--   * affiliate_whatsapp_outbox: one row per message, with the message
--     composed when it is queued, the phone (E.164, and split into WhatsApp
--     country code and number for WbizTool), the first name and what became
--     of it: queued, sending, sent, failed, skipped (with the reason) or
--     expired. idempotency_key makes each message once only: one 'welcome'
--     per login, one 'reactivated' per reactivation. No client role can read
--     the table.
--   * Two triggers queue the messages:
--       - AFTER INSERT on affiliate_accounts: 'welcome'. If the affiliate is
--         suspended or not active at that moment, the customer is deleted,
--         or no phone is usable, the row is kept as 'skipped' with the
--         reason, and nothing is sent.
--       - AFTER UPDATE OF manually_suspended on customer_affiliates, from true
--         to false, when the affiliate has a login: 'reactivated'.
--     They never stop the sign-up, the Resolve or the reactivation: anything
--     that goes wrong is kept as a 'failed' row (skip_reason enqueue_error)
--     or, if even that cannot be written, raised as a warning only.
--   * The phone: the customer's phone, else the phone the person gave at
--     sign-up (auth.users metadata), each through normalize_customer_phone,
--     so a legacy 8-digit phone becomes +65.... One the phone policy finds
--     ambiguous (a few 8-digit numbers could be Singapore or Malaysia) is not
--     guessed: the sign-up phone is used, else nothing is sent (no_phone).
--     The WhatsApp country code is ads_wa_country_code's (the TikTok
--     messages use it); the number is the rest.
--   * The first name: the one given at sign-up, else the customer's first
--     name, else the first word of the full name, each without the notes
--     staff keep in brackets (affiliate_calendar_label, 392). The sign-up name
--     is whatever the person typed (nobody checks it, nor the phone), and the
--     message goes out from the business number, so a name is used only if it
--     looks like one: letters, spaces, an apostrophe or a hyphen, at most 30
--     characters. One with digits, dots, slashes, colons or anything else (a
--     link, a phone number, a sentence too long) is passed over for the next.
--     With none, the greeting is "Hi there".
--   * The message is composed when it is queued, with the referral code and
--     app_url of that moment.
--   * affiliate_whatsapp_dispatch(): what pg_cron runs every minute (job
--     'affiliate-whatsapp-dispatch'). It does nothing unless the settings are
--     enabled with a webhook address and a secret. Then it:
--       1. settles the posts pg_net has answered (net._http_response): a 2xx
--          answer is 'sent'. Any other status code is 'failed', and is posted
--          again 5 minutes later while fewer than 3 posts were made, since
--          Pabbly did not take it. A timeout, an error or no answer within 15
--          minutes is 'failed' for good: the message may have gone out, and
--          posting it again could send it twice.
--       2. expires what has waited more than 48 hours, and skips a message
--          whose login is no longer linked or whose affiliate is no longer
--          active. It also skips a 'reactivated' message while the same login
--          still has an earlier one waiting or being posted
--          (earlier_message_pending): someone suspended and reactivated
--          before their welcome went out (sending off, or within the minute)
--          gets the welcome alone, which has the same links;
--       3. posts up to 10 waiting messages, oldest first, through
--          net.http_post (10 second timeout) with the body
--          {secret, idempotency_key, kind, first_name, phone_e164,
--           wa_country_code, wa_number, message}, and marks them 'sending'
--          with pg_net's request id.
--     The steps are separate functions (affiliate_whatsapp_reconcile,
--     _settle, _take, _payload, _mark_sending), so everything but the post
--     itself can be tested without pg_net.
--   * pg_cron runs it every minute, only where pg_cron is installed
--     (production has it since 381). Elsewhere the migration still runs and
--     says so; nothing runs the dispatcher there.
--   * ads_wa_country_code is created, exactly as production has it, on a
--     database that does not have it (it is not in this repository).
--     Production's is left alone.
--
-- NOT CHANGED
--
--   * complete_affiliate_onboarding, resolve_affiliate_account_claim,
--     reactivate_affiliate and every other function: no function is patched.
--   * Who is linked or reactivated, and what they are told on screen.
--   * Affiliates who already have a login (44 in production on 6 Oct 2026):
--     no message.
--   * A login linked again after an Owner's Unlink: no second welcome (one
--     per login). A different login linked to the customer gets its own.
--   * Messages queued while the sending is off are posted once it is on, if
--     they are less than 48 hours old; older ones expire unsent.
--   * The Pabbly workflow, WbizTool and the webhook address: built by hand
--     later (PABBLY_SETUP.md). Until then, and until an Owner turns it on,
--     the outbox only fills.
--   * No staff page shows the outbox; it is read in the SQL editor
--     (PABBLY_SETUP.md has the queries).
--   * pg_cron keeps a row per run in cron.job_run_details: one a minute more
--     from now on, as for any every-minute job.
--
-- SAFETY
--
-- Apart from the lock timeout, the migration is one statement (a DO block), so
-- it is atomic however it is run. Every check comes first; nothing is created
-- unless all of them pass:
--   * the functions it relies on must be the production versions read on
--     6 Oct 2026 (BEFORE): normalize_customer_phone and the parser under it,
--     affiliate_calendar_label (392), and ads_wa_country_code (or missing);
--   * the columns it reads must exist;
--   * every table, function, trigger and cron job it creates must be missing,
--     or already exactly this migration's (AFTER), which is left alone, so a
--     re-run changes nothing and keeps the settings an Owner has filled in.
-- After installing, every function must have its AFTER md5 and each table its
-- AFTER shape, the triggers must be in place, both tables must have row level
-- security and no grant to anon or authenticated, and no new function may be
-- callable by a client role (339: service_role only). No row is written
-- except the one settings row (sending off).
--
-- BEFORE (production, 6 Oct 2026, md5 of pg_get_functiondef), relied on:
--   normalize_customer_phone(text)                          b2bfac910e0c9eff402ba44e19750bee
--   inspect_customer_phone(text,text)                       6672c4d1963996f3b601896f4a55916e
--   affiliate_calendar_label(text)                          af4eecdcf978c19b3effb6af3a897165
--   ads_wa_country_code(text)                               51abbed9eb0f93a58da238d3ec155b68
-- Not changed, and tested with (they insert affiliate_accounts / reactivate):
--   complete_affiliate_onboarding(text,text,text,boolean)   9ff0fd280f4a46eddb2446523d500233
--   resolve_affiliate_account_claim(uuid,uuid,text)         29a68a4d2282995f367b715089736c6c
--   reactivate_affiliate(uuid)                              733943ad9c802d0566cee9939c846580
-- AFTER (for later guards):
--   affiliate_whatsapp_message(text,text,text,text)         6cab1d437121fb0942f90dd7ec7c5310
--   affiliate_whatsapp_enqueue(text,uuid,uuid,uuid,text)    c88ad74525019c20254a6927f4a802a3
--   trg_affiliate_whatsapp_welcome()                        248067d2763aff9e825d7d42eebb833e
--   trg_affiliate_whatsapp_reactivated()                    b44622c610e11e90fff0ffe078d2bf75
--   affiliate_whatsapp_take(integer)                        f3a07d2367e23dff74164dbe755e321f
--   affiliate_whatsapp_payload(bigint,text)                 63b8112911fe477a718ab63083afd840
--   affiliate_whatsapp_mark_sending(bigint,bigint)          c8e6a1aa0e486279f9ee86c801af4808
--   affiliate_whatsapp_settle(bigint,integer,boolean,text)  950a44ad565eada10199a3ccfc0e20bb
--   affiliate_whatsapp_reconcile()                          ca72f063b7eee883ba577fa679a2f3e6
--   affiliate_whatsapp_dispatch(integer)                    bfeefed42b32c7b68cf8f39a82a4b59a
--   table affiliate_whatsapp_settings (shape)               52a462e9f7ab6f6b91f55b05eaf153f5
--   table affiliate_whatsapp_outbox (shape)                 93b1b08d815a1aa2985f20d7b792b15a
--
-- Test: scripts/affiliate-whatsapp/tests/outbox.sql.

set lock_timeout = '5s';

do $mig$
declare
  c_app constant text := 'https://rev-22-energia-inventory-system.vercel.app';
  c_job constant text := 'affiliate-whatsapp-dispatch';
  c_job_schedule constant text := '* * * * *';
  c_job_command constant text := 'select public.affiliate_whatsapp_dispatch()';

  -- ── The tables ─────────────────────────────────────────────────────────────
  c_settings_def constant text := $def$
create table public.affiliate_whatsapp_settings (
  id boolean primary key default true
    constraint affiliate_whatsapp_settings_one_row check (id),
  enabled boolean not null default false,
  webhook_url text
    constraint affiliate_whatsapp_settings_webhook_url check (webhook_url ~ '^https://[^[:space:]]+$'),
  secret text
    constraint affiliate_whatsapp_settings_secret check (length(secret) >= 16),
  app_url text not null default 'https://rev-22-energia-inventory-system.vercel.app'
    constraint affiliate_whatsapp_settings_app_url check (app_url ~ '^https://[^[:space:]]*[^/[:space:]]$'),
  updated_at timestamptz not null default now(),
  constraint affiliate_whatsapp_settings_ready
    check (not enabled or (webhook_url is not null and secret is not null))
)
$def$;
  c_outbox_def constant text := $def$
create table public.affiliate_whatsapp_outbox (
  id bigint generated always as identity primary key,
  kind text not null
    constraint affiliate_whatsapp_outbox_kind check (kind in ('welcome', 'reactivated')),
  idempotency_key text not null
    constraint affiliate_whatsapp_outbox_once unique,
  customer_id uuid,
  auth_user_id uuid,
  affiliate_id uuid,
  phone_e164 text,
  wa_country_code text,
  wa_number text,
  first_name text,
  referral_code text,
  message text,
  status text not null default 'queued'
    constraint affiliate_whatsapp_outbox_status
    check (status in ('queued', 'sending', 'sent', 'failed', 'skipped', 'expired')),
  skip_reason text,
  attempts integer not null default 0,
  request_id bigint,
  last_status_code integer,
  last_error text,
  retry_after timestamptz,
  created_at timestamptz not null default now(),
  sending_at timestamptz,
  sent_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint affiliate_whatsapp_outbox_sendable
    check (status not in ('queued', 'sending', 'sent')
           or (phone_e164 is not null and wa_country_code is not null
               and wa_number is not null and message is not null))
)
$def$;
  c_outbox_index constant text := $def$
create index affiliate_whatsapp_outbox_waiting on public.affiliate_whatsapp_outbox (created_at, id)
  where status in ('queued', 'sending', 'failed')
$def$;

  -- ── ads_wa_country_code, exactly as production has it ─────────────────────
  c_cc_def constant text := $def$CREATE OR REPLACE FUNCTION public.ads_wa_country_code(p_e164 text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when p_e164 is null or p_e164 !~ '^[0-9]{8,15}$' then null
    when p_e164 ~ '^65[0-9]{8}$' then '65'
    when p_e164 ~ '^1[0-9]{10}$' then '1'
    else coalesce(substring(p_e164 from
           '^(852|853|855|856|880|886|966|971|60|61|62|63|64|66|81|82|84|86|91|92|94|95|44|49|33|39|34|7)'),
         left(p_e164, 2))
  end;
$function$
$def$;

  -- ── The functions ──────────────────────────────────────────────────────────
  c_message_def constant text := $def$
create or replace function public.affiliate_whatsapp_message(p_kind text, p_first_name text, p_app_url text, p_referral_code text)
returns text
language sql
immutable
set search_path = public
as $fn$
  -- 394: the words of the affiliate WhatsApps, all in this one place, so a
  -- later migration changes them by replacing this function alone. 'welcome'
  -- when a login becomes an affiliate's, 'reactivated' when a suspended
  -- affiliate with a login is reactivated. Null for any other kind, or
  -- without the app's address or a referral code.
  select case p_kind
           when 'welcome' then
             'Hi ' || coalesce(nullif(btrim(p_first_name), ''), 'there')
             || ', welcome to the Energia affiliate programme! Your account is now active.'
           when 'reactivated' then
             'Hi ' || coalesce(nullif(btrim(p_first_name), ''), 'there')
             || ', your Energia affiliate account is active again.'
         end
         || E'\n\n'
         || 'Log in: ' || p_app_url || '/affiliate/login' || E'\n'
         || 'Forgot your password? ' || p_app_url || '/affiliate/forgot-password' || E'\n\n'
         || 'Your referral link to share with friends and family: ' || p_app_url || '/r/' || p_referral_code || E'\n\n'
         || 'In your portal you can see your referrals, earnings and payouts.' || E'\n\n'
         || 'Rev 22 Global Energia'
$fn$
$def$;

  c_enqueue_def constant text := $def$
create or replace function public.affiliate_whatsapp_enqueue(p_kind text, p_auth_user_id uuid, p_customer_id uuid,
                                                             p_affiliate_id uuid, p_key text)
returns bigint
language plpgsql
security definer
set search_path = public
as $fn$
-- 394: queues one affiliate WhatsApp, composed now. One that must not go out
-- is kept as 'skipped' with the reason. p_key makes it once only: a second
-- call with the same key adds nothing and returns null.
declare
  v_c public.customers%rowtype; v_a public.customer_affiliates%rowtype; v_acct public.affiliate_accounts%rowtype;
  v_meta jsonb; v_app text; v_name text; v_first text; v_phone text; v_digits text; v_cc text; v_skip text; v_id bigint;
begin
  select * into v_c from public.customers where id = p_customer_id;
  if p_affiliate_id is not null then
    select * into v_a from public.customer_affiliates where id = p_affiliate_id;
  else
    select * into v_a from public.customer_affiliates where customer_id = p_customer_id;
  end if;
  select * into v_acct from public.affiliate_accounts where auth_user_id = p_auth_user_id;
  select raw_user_meta_data into v_meta from auth.users where id = p_auth_user_id;
  select s.app_url into v_app from public.affiliate_whatsapp_settings s where s.id;
  v_app := coalesce(v_app, 'https://rev-22-energia-inventory-system.vercel.app');

  -- The name they gave at sign-up, else the customer's first name, else the
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

  -- The customer's phone, else the one given at sign-up. WbizTool takes the
  -- WhatsApp country code and the number apart.
  v_phone := coalesce(public.normalize_customer_phone(v_c.phone),
                      public.normalize_customer_phone(v_meta->>'phone'));
  v_digits := ltrim(v_phone, '+');
  v_cc := public.ads_wa_country_code(v_digits);

  v_skip := case
    when v_a.id is null or v_a.deleted_at is not null then 'affiliate_missing'
    when v_a.manually_suspended then 'affiliate_suspended'
    when v_a.status is distinct from 'active' then 'affiliate_' || v_a.status
    when v_c.id is null or v_c.deleted_at is not null then 'customer_deleted'
    when v_acct.id is null or v_acct.status is distinct from 'claimed' then 'login_not_linked'
    when v_a.referral_code is null then 'no_referral_code'
    when v_phone is null or v_cc is null then 'no_phone'
  end;

  insert into public.affiliate_whatsapp_outbox (kind, idempotency_key, customer_id, auth_user_id, affiliate_id,
      phone_e164, wa_country_code, wa_number, first_name, referral_code, message, status, skip_reason)
  values (p_kind, p_key, p_customer_id, p_auth_user_id, v_a.id,
      v_phone, v_cc, case when v_cc is not null then substr(v_digits, length(v_cc) + 1) end,
      v_first, v_a.referral_code, public.affiliate_whatsapp_message(p_kind, v_first, v_app, v_a.referral_code),
      case when v_skip is null then 'queued' else 'skipped' end, v_skip)
  on conflict (idempotency_key) do nothing
  returning id into v_id;
  return v_id;
end $fn$
$def$;

  c_welcome_def constant text := $def$
create or replace function public.trg_affiliate_whatsapp_welcome()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
-- 394: a login that becomes an affiliate's (a self sign-up going live, or
-- staff resolving a claim) is sent the welcome WhatsApp, once per login. It
-- never stops the link: a failure is kept in the outbox, or only warned about.
declare v_key text := 'welcome:' || new.auth_user_id::text;
begin
  begin
    perform public.affiliate_whatsapp_enqueue('welcome', new.auth_user_id, new.customer_id, new.affiliate_id, v_key);
  exception when others then
    begin
      insert into public.affiliate_whatsapp_outbox (kind, idempotency_key, customer_id, auth_user_id, affiliate_id,
          status, skip_reason, last_error)
      values ('welcome', v_key, new.customer_id, new.auth_user_id, new.affiliate_id,
          'failed', 'enqueue_error', left(sqlerrm, 500))
      on conflict (idempotency_key) do nothing;
    exception when others then
      raise warning '394: the welcome WhatsApp for login % was not queued: %', new.auth_user_id, sqlerrm;
    end;
  end;
  return null;
end $fn$
$def$;

  c_reactivated_def constant text := $def$
create or replace function public.trg_affiliate_whatsapp_reactivated()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
-- 394: a suspended affiliate who is reactivated, and has a login, is sent the
-- "active again" WhatsApp, once per reactivation (one per transaction). Never
-- stops the reactivation: a failure is kept in the outbox, or only warned
-- about.
declare
  v_key text := 'reactivated:' || new.id::text || ':' || (extract(epoch from now()) * 1000000)::bigint::text;
  v_uid uuid;
begin
  begin
    select a.auth_user_id into v_uid from public.affiliate_accounts a
     where a.affiliate_id = new.id or (a.affiliate_id is null and a.customer_id = new.customer_id)
     order by (a.affiliate_id = new.id) desc nulls last
     limit 1;
    if v_uid is not null then
      perform public.affiliate_whatsapp_enqueue('reactivated', v_uid, new.customer_id, new.id, v_key);
    end if;
  exception when others then
    begin
      insert into public.affiliate_whatsapp_outbox (kind, idempotency_key, customer_id, auth_user_id, affiliate_id,
          status, skip_reason, last_error)
      values ('reactivated', v_key, new.customer_id, v_uid, new.id, 'failed', 'enqueue_error', left(sqlerrm, 500))
      on conflict (idempotency_key) do nothing;
    exception when others then
      raise warning '394: the reactivation WhatsApp for affiliate % was not queued: %', new.id, sqlerrm;
    end;
  end;
  return null;
end $fn$
$def$;

  c_take_def constant text := $def$
create or replace function public.affiliate_whatsapp_take(p_limit integer)
returns setof bigint
language plpgsql
security definer
set search_path = public
as $fn$
-- 394: the outbox rows to post now, oldest first, at most p_limit (1 to 50),
-- locked. Waiting: 'queued', and 'failed' rows a non-2xx answer left to try
-- again (retry_after set and passed, fewer than 3 posts). First, a waiting
-- row older than 48 hours becomes 'expired', and one whose login is no
-- longer linked to the customer, or whose affiliate or customer is no longer
-- active, 'skipped' (no_longer_active). Then a 'reactivated' row whose login
-- still has an earlier message waiting or being posted (a welcome, or an
-- earlier reactivation) is 'skipped' (earlier_message_pending): that one has
-- the same links, and the person is not sent two at once.
begin
  update public.affiliate_whatsapp_outbox o
     set status = 'expired', retry_after = null, updated_at = now()
   where (o.status = 'queued' or (o.status = 'failed' and o.retry_after is not null))
     and o.created_at < now() - interval '48 hours';

  update public.affiliate_whatsapp_outbox o
     set status = 'skipped', skip_reason = 'no_longer_active', retry_after = null, updated_at = now()
   where (o.status = 'queued' or (o.status = 'failed' and o.retry_after is not null))
     and not exists (select 1 from public.affiliate_accounts a
                       join public.customer_affiliates ca on ca.customer_id = a.customer_id
                       join public.customers c on c.id = a.customer_id
                      where a.auth_user_id = o.auth_user_id and a.customer_id = o.customer_id
                        and a.status = 'claimed' and ca.deleted_at is null
                        and not ca.manually_suspended and ca.status = 'active'
                        and c.deleted_at is null);

  update public.affiliate_whatsapp_outbox o
     set status = 'skipped', skip_reason = 'earlier_message_pending', retry_after = null, updated_at = now()
   where o.kind = 'reactivated'
     and (o.status = 'queued' or (o.status = 'failed' and o.retry_after is not null))
     and exists (select 1 from public.affiliate_whatsapp_outbox e
                  where e.auth_user_id = o.auth_user_id and e.id < o.id
                    and (e.status in ('queued', 'sending') or (e.status = 'failed' and e.retry_after is not null)));

  return query
    select o.id from public.affiliate_whatsapp_outbox o
     where o.status = 'queued'
        or (o.status = 'failed' and o.retry_after <= now() and o.attempts < 3)
     order by o.created_at, o.id
     limit greatest(1, least(coalesce(p_limit, 10), 50))
     for update skip locked;
end $fn$
$def$;

  c_payload_def constant text := $def$
create or replace function public.affiliate_whatsapp_payload(p_id bigint, p_secret text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn$
  -- 394: what is posted to the Pabbly webhook for one outbox row. The secret
  -- is what the workflow's filter checks.
  select jsonb_build_object('secret', p_secret, 'idempotency_key', o.idempotency_key, 'kind', o.kind,
           'first_name', coalesce(o.first_name, ''), 'phone_e164', o.phone_e164,
           'wa_country_code', o.wa_country_code, 'wa_number', o.wa_number, 'message', o.message)
    from public.affiliate_whatsapp_outbox o
   where o.id = p_id
$fn$
$def$;

  c_mark_def constant text := $def$
create or replace function public.affiliate_whatsapp_mark_sending(p_id bigint, p_request_id bigint)
returns boolean
language plpgsql
security definer
set search_path = public
as $fn$
-- 394: a row has been posted (pg_net's request p_request_id): 'sending' until
-- pg_net has the answer.
begin
  update public.affiliate_whatsapp_outbox
     set status = 'sending', request_id = p_request_id, attempts = attempts + 1,
         sending_at = now(), retry_after = null, updated_at = now()
   where id = p_id and status in ('queued', 'failed');
  return found;
end $fn$
$def$;

  c_settle_def constant text := $def$
create or replace function public.affiliate_whatsapp_settle(p_id bigint, p_status_code integer, p_timed_out boolean,
                                                            p_error text)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
-- 394: what became of a post. A 2xx answer: 'sent'. Any other status code:
-- 'failed', and posted again 5 minutes later while fewer than 3 posts were
-- made, since Pabbly did not take it. No status code (a timeout, an error,
-- no answer): 'failed' for good, since the message may have gone out and a
-- second post could send it twice. Only a 'sending' row changes; returns its
-- new status, or null.
declare v_status text;
begin
  update public.affiliate_whatsapp_outbox o
     set status = case when p_status_code between 200 and 299 then 'sent' else 'failed' end,
         sent_at = case when p_status_code between 200 and 299 then now() end,
         last_status_code = p_status_code,
         last_error = case when p_status_code between 200 and 299 then null
                           else left(coalesce(nullif(btrim(p_error), ''),
                                              case when p_status_code is not null then 'HTTP ' || p_status_code
                                                   when coalesce(p_timed_out, false) then 'timed out'
                                                   else 'no answer' end), 500) end,
         retry_after = case when p_status_code is not null and p_status_code not between 200 and 299
                             and not coalesce(p_timed_out, false) and o.attempts < 3
                            then now() + interval '5 minutes' end,
         updated_at = now()
   where o.id = p_id and o.status = 'sending'
  returning o.status into v_status;
  return v_status;
end $fn$
$def$;

  c_reconcile_def constant text := $def$
create or replace function public.affiliate_whatsapp_reconcile()
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
-- 394: settles the posts pg_net has answered (net._http_response keeps the
-- answers for 6 hours). A post with no answer 15 minutes after it was made
-- is settled as unanswered. Returns how many were settled.
declare r record; v_resp record; n integer := 0;
begin
  for r in select o.id, o.request_id, o.sending_at from public.affiliate_whatsapp_outbox o
            where o.status = 'sending' order by o.id for update loop
    select h.status_code, h.timed_out, h.error_msg, h.content into v_resp
      from net._http_response h where h.id = r.request_id;
    if found then
      perform public.affiliate_whatsapp_settle(r.id, v_resp.status_code, v_resp.timed_out,
        coalesce(v_resp.error_msg,
                 case when v_resp.status_code not between 200 and 299 then left(v_resp.content, 300) end));
      n := n + 1;
    elsif r.request_id is null or r.sending_at < now() - interval '15 minutes' then
      perform public.affiliate_whatsapp_settle(r.id, null, null, 'no answer recorded by pg_net');
      n := n + 1;
    end if;
  end loop;
  return n;
end $fn$
$def$;

  c_dispatch_def constant text := $def$
create or replace function public.affiliate_whatsapp_dispatch(p_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
-- 394: what pg_cron runs every minute. Nothing unless the settings are
-- enabled with a webhook address and a secret. Then: settle what pg_net has
-- answered, and post what is waiting (affiliate_whatsapp_take). pg_net sends
-- the posts once this transaction commits.
declare s public.affiliate_whatsapp_settings%rowtype; v_id bigint; v_req bigint; n_settled integer; n_posted integer := 0;
begin
  select * into s from public.affiliate_whatsapp_settings where id;
  if not found or not s.enabled or s.webhook_url is null or s.secret is null then
    return jsonb_build_object('enabled', false);
  end if;
  if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then
    return jsonb_build_object('enabled', true, 'error', 'pg_net is not installed');
  end if;
  -- One run at a time.
  if not pg_try_advisory_xact_lock(hashtextextended('affiliate-whatsapp-dispatch', 0)) then
    return jsonb_build_object('enabled', true, 'busy', true);
  end if;

  n_settled := public.affiliate_whatsapp_reconcile();
  for v_id in select t.id from public.affiliate_whatsapp_take(p_limit) t(id) loop
    v_req := net.http_post(url := s.webhook_url,
                           body := public.affiliate_whatsapp_payload(v_id, s.secret),
                           headers := jsonb_build_object('Content-Type', 'application/json'),
                           timeout_milliseconds := 10000);
    perform public.affiliate_whatsapp_mark_sending(v_id, v_req);
    n_posted := n_posted + 1;
  end loop;
  return jsonb_build_object('enabled', true, 'settled', n_settled, 'posted', n_posted);
end $fn$
$def$;

  -- Relied on, not changed: [signature, production md5 (6 Oct 2026)].
  v_relied text[][] := array[
    ['public.normalize_customer_phone(text)',      'b2bfac910e0c9eff402ba44e19750bee'],
    ['public.inspect_customer_phone(text,text)',   '6672c4d1963996f3b601896f4a55916e'],
    ['public.affiliate_calendar_label(text)',      'af4eecdcf978c19b3effb6af3a897165']];
  c_cc_md5 constant text := '51abbed9eb0f93a58da238d3ec155b68';
  -- Created: [signature, AFTER md5].
  v_fns text[][] := array[
    ['public.affiliate_whatsapp_message(text,text,text,text)',        '6cab1d437121fb0942f90dd7ec7c5310'],
    ['public.affiliate_whatsapp_enqueue(text,uuid,uuid,uuid,text)',   'c88ad74525019c20254a6927f4a802a3'],
    ['public.trg_affiliate_whatsapp_welcome()',                       '248067d2763aff9e825d7d42eebb833e'],
    ['public.trg_affiliate_whatsapp_reactivated()',                   'b44622c610e11e90fff0ffe078d2bf75'],
    ['public.affiliate_whatsapp_take(integer)',                       'f3a07d2367e23dff74164dbe755e321f'],
    ['public.affiliate_whatsapp_payload(bigint,text)',                '63b8112911fe477a718ab63083afd840'],
    ['public.affiliate_whatsapp_mark_sending(bigint,bigint)',         'c8e6a1aa0e486279f9ee86c801af4808'],
    ['public.affiliate_whatsapp_settle(bigint,integer,boolean,text)', '950a44ad565eada10199a3ccfc0e20bb'],
    ['public.affiliate_whatsapp_reconcile()',                         'ca72f063b7eee883ba577fa679a2f3e6'],
    ['public.affiliate_whatsapp_dispatch(integer)',                   'bfeefed42b32c7b68cf8f39a82a4b59a']];
  v_defs text[];
  -- The tables: [name, AFTER shape md5].
  v_tables text[][] := array[
    ['public.affiliate_whatsapp_settings', '52a462e9f7ab6f6b91f55b05eaf153f5'],
    ['public.affiliate_whatsapp_outbox',   '93b1b08d815a1aa2985f20d7b792b15a']];
  -- The triggers: [name, table, function, tgtype (1 row + 4 insert / 16 update, after)].
  v_trgs text[][] := array[
    ['trg_affiliate_whatsapp_welcome', 'public.affiliate_accounts',
     'public.trg_affiliate_whatsapp_welcome()', '5'],
    ['trg_affiliate_whatsapp_reactivated', 'public.customer_affiliates',
     'public.trg_affiliate_whatsapp_reactivated()', '17']];
  v_new_tables boolean[] := '{}'; v_new_fns boolean[] := '{}'; v_new_trgs boolean[] := '{}';
  v_new_cc boolean := false; v_cron boolean := false; v_new_job boolean := false;
  v text; i int; n int; t record;
begin
  v_defs := array[c_message_def, c_enqueue_def, c_welcome_def, c_reactivated_def, c_take_def,
                  c_payload_def, c_mark_def, c_settle_def, c_reconcile_def, c_dispatch_def];

  -- ── Guards: nothing is created unless all pass ─────────────────────────────
  for i in 1 .. array_length(v_relied, 1) loop
    if to_regprocedure(v_relied[i][1]) is null then
      raise exception '394: % is missing (apply 392 first for affiliate_calendar_label)', v_relied[i][1]; end if;
    v := md5(pg_get_functiondef(to_regprocedure(v_relied[i][1])));
    if v <> v_relied[i][2] then
      raise exception '394: % is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', v_relied[i][1], v; end if;
  end loop;
  if to_regprocedure('public.ads_wa_country_code(text)') is null then
    v_new_cc := true;
  elsif md5(pg_get_functiondef(to_regprocedure('public.ads_wa_country_code(text)'))) <> c_cc_md5 then
    raise exception '394: public.ads_wa_country_code(text) is not the version this was tested against (md5 %)',
      md5(pg_get_functiondef(to_regprocedure('public.ads_wa_country_code(text)'))); end if;

  for t in select * from (values
      ('public.affiliate_accounts', 'id'), ('public.affiliate_accounts', 'auth_user_id'),
      ('public.affiliate_accounts', 'customer_id'), ('public.affiliate_accounts', 'affiliate_id'),
      ('public.affiliate_accounts', 'status'),
      ('public.customer_affiliates', 'id'), ('public.customer_affiliates', 'customer_id'),
      ('public.customer_affiliates', 'status'), ('public.customer_affiliates', 'manually_suspended'),
      ('public.customer_affiliates', 'deleted_at'), ('public.customer_affiliates', 'referral_code'),
      ('public.customers', 'id'), ('public.customers', 'phone'), ('public.customers', 'first_name'),
      ('public.customers', 'full_name'), ('public.customers', 'deleted_at'),
      ('auth.users', 'id'), ('auth.users', 'raw_user_meta_data')) x(tbl, col)
  loop
    if to_regclass(t.tbl) is null
       or not exists (select 1 from pg_attribute where attrelid = to_regclass(t.tbl)
                         and attname = t.col and attnum > 0 and not attisdropped) then
      raise exception '394: %.% is missing', t.tbl, t.col; end if;
  end loop;

  for i in 1 .. array_length(v_tables, 1) loop
    if to_regclass(v_tables[i][1]) is null then
      v_new_tables := v_new_tables || true;
    else
      select md5(string_agg(x, E'\n' order by x)) into v from (
        select 'col ' || lpad(a.attnum::text, 3, '0') || ' ' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
               || case when a.attnotnull then ' not null' else '' end
               || case when a.attidentity <> '' then ' identity ' || a.attidentity::text else '' end
               || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), '') x
          from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
         where a.attrelid = to_regclass(v_tables[i][1]) and a.attnum > 0 and not a.attisdropped
        union all
        select 'con ' || c.conname || ' ' || pg_get_constraintdef(c.oid)
          from pg_constraint c where c.conrelid = to_regclass(v_tables[i][1])
        union all
        select 'idx ' || pg_get_indexdef(x.indexrelid)
          from pg_index x where x.indrelid = to_regclass(v_tables[i][1])
        union all
        select 'rls ' || c.relrowsecurity from pg_class c where c.oid = to_regclass(v_tables[i][1])) s;
      if v <> v_tables[i][2] then
        raise exception '394: a different % already exists (shape md5 %)', v_tables[i][1], v; end if;
      v_new_tables := v_new_tables || false;
    end if;
  end loop;

  for i in 1 .. array_length(v_fns, 1) loop
    if to_regprocedure(v_fns[i][1]) is null then
      v_new_fns := v_new_fns || true;
    else
      v := md5(pg_get_functiondef(to_regprocedure(v_fns[i][1])));
      if v <> v_fns[i][2] then
        raise exception '394: a different % already exists (md5 %)', v_fns[i][1], v; end if;
      v_new_fns := v_new_fns || false;
    end if;
  end loop;

  for i in 1 .. array_length(v_trgs, 1) loop
    select count(*) into n from pg_trigger where tgname = v_trgs[i][1] and not tgisinternal;
    if n = 0 then
      v_new_trgs := v_new_trgs || true;
    else
      if not exists (select 1 from pg_trigger
                      where tgname = v_trgs[i][1] and tgrelid = to_regclass(v_trgs[i][2])
                        and tgfoid = to_regprocedure(v_trgs[i][3]) and tgtype = v_trgs[i][4]::int2
                        and tgenabled = 'O') or n <> 1 then
        raise exception '394: a different trigger % already exists', v_trgs[i][1]; end if;
      v_new_trgs := v_new_trgs || false;
    end if;
  end loop;

  v_cron := exists (select 1 from pg_extension where extname = 'pg_cron');
  if v_cron then
    execute 'select count(*) from cron.job where jobname = $1' into n using c_job;
    if n = 0 then
      v_new_job := true;
    else
      execute 'select count(*) from cron.job where jobname = $1 and schedule = $2 and command = $3 and active'
        into n using c_job, c_job_schedule, c_job_command;
      if n <> 1 then raise exception '394: a different cron job % already exists', c_job; end if;
    end if;
  end if;

  -- ── Install ────────────────────────────────────────────────────────────────
  if v_new_cc then
    execute c_cc_def;
    execute 'revoke all on function public.ads_wa_country_code(text) from public, anon, authenticated';
    execute 'grant execute on function public.ads_wa_country_code(text) to service_role';
  end if;

  if v_new_tables[1] then
    execute c_settings_def;
    execute 'alter table public.affiliate_whatsapp_settings enable row level security';
    execute 'revoke all on table public.affiliate_whatsapp_settings from public, anon, authenticated';
    execute 'grant all on table public.affiliate_whatsapp_settings to service_role';
    execute $c$comment on table public.affiliate_whatsapp_settings is
      '394: sending the affiliate login WhatsApps through Pabbly. One row; off until an Owner sets webhook_url and secret and turns enabled on.'$c$;
  end if;
  if v_new_tables[2] then
    execute c_outbox_def;
    execute c_outbox_index;
    execute 'alter table public.affiliate_whatsapp_outbox enable row level security';
    execute 'revoke all on table public.affiliate_whatsapp_outbox from public, anon, authenticated';
    execute 'grant all on table public.affiliate_whatsapp_outbox to service_role';
    execute format('revoke all on sequence %s from public, anon, authenticated',
                   pg_get_serial_sequence('public.affiliate_whatsapp_outbox', 'id'));
    execute format('grant usage, select on sequence %s to service_role',
                   pg_get_serial_sequence('public.affiliate_whatsapp_outbox', 'id'));
    execute $c$comment on table public.affiliate_whatsapp_outbox is
      '394: one row per affiliate login WhatsApp (welcome, reactivated) and what became of it.'$c$;
  end if;
  -- The one settings row, off. A re-run keeps what an Owner filled in.
  insert into public.affiliate_whatsapp_settings (id) values (true) on conflict (id) do nothing;

  for i in 1 .. array_length(v_fns, 1) loop
    if v_new_fns[i] then
      execute v_defs[i];
      execute format('revoke all on function %s from public, anon, authenticated', v_fns[i][1]);
      execute format('grant execute on function %s to service_role', v_fns[i][1]);
    end if;
  end loop;

  if v_new_trgs[1] then
    execute 'create trigger trg_affiliate_whatsapp_welcome after insert on public.affiliate_accounts
               for each row execute function public.trg_affiliate_whatsapp_welcome()';
  end if;
  if v_new_trgs[2] then
    execute 'create trigger trg_affiliate_whatsapp_reactivated after update of manually_suspended on public.customer_affiliates
               for each row when (old.manually_suspended and not new.manually_suspended)
               execute function public.trg_affiliate_whatsapp_reactivated()';
  end if;

  if v_new_job then
    execute 'select cron.schedule($1, $2, $3)' using c_job, c_job_schedule, c_job_command;
  elsif not v_cron then
    raise notice '394: pg_cron is not installed here, so nothing runs affiliate_whatsapp_dispatch()';
  end if;

  -- ── Installed exactly as tested ────────────────────────────────────────────
  if md5(pg_get_functiondef(to_regprocedure('public.ads_wa_country_code(text)'))) <> c_cc_md5 then
    raise exception '394: ads_wa_country_code was installed with a different md5'; end if;
  for i in 1 .. array_length(v_fns, 1) loop
    v := md5(pg_get_functiondef(to_regprocedure(v_fns[i][1])));
    if v <> v_fns[i][2] then
      raise exception '394: % was installed with md5 %, not the tested %', v_fns[i][1], v, v_fns[i][2]; end if;
    if has_function_privilege('anon', v_fns[i][1], 'execute')
       or has_function_privilege('authenticated', v_fns[i][1], 'execute') then
      raise exception '394: % is callable by a client role', v_fns[i][1]; end if;
  end loop;
  if has_function_privilege('anon', 'public.ads_wa_country_code(text)', 'execute')
     or has_function_privilege('authenticated', 'public.ads_wa_country_code(text)', 'execute') then
    raise exception '394: ads_wa_country_code is callable by a client role'; end if;
  for i in 1 .. array_length(v_tables, 1) loop
    select md5(string_agg(x, E'\n' order by x)) into v from (
      select 'col ' || lpad(a.attnum::text, 3, '0') || ' ' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
             || case when a.attnotnull then ' not null' else '' end
             || case when a.attidentity <> '' then ' identity ' || a.attidentity::text else '' end
             || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), '') x
        from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
       where a.attrelid = to_regclass(v_tables[i][1]) and a.attnum > 0 and not a.attisdropped
      union all
      select 'con ' || c.conname || ' ' || pg_get_constraintdef(c.oid)
        from pg_constraint c where c.conrelid = to_regclass(v_tables[i][1])
      union all
      select 'idx ' || pg_get_indexdef(x.indexrelid)
        from pg_index x where x.indrelid = to_regclass(v_tables[i][1])
      union all
      select 'rls ' || c.relrowsecurity from pg_class c where c.oid = to_regclass(v_tables[i][1])) s;
    if v <> v_tables[i][2] then
      raise exception '394: % was created with shape md5 %, not the tested %', v_tables[i][1], v, v_tables[i][2]; end if;
    if has_table_privilege('anon', v_tables[i][1], 'select,insert,update,delete,truncate,references,trigger')
       or has_table_privilege('authenticated', v_tables[i][1], 'select,insert,update,delete,truncate,references,trigger') then
      raise exception '394: % is reachable by a client role', v_tables[i][1]; end if;
  end loop;
  for i in 1 .. array_length(v_trgs, 1) loop
    if not exists (select 1 from pg_trigger
                    where tgname = v_trgs[i][1] and tgrelid = to_regclass(v_trgs[i][2])
                      and tgfoid = to_regprocedure(v_trgs[i][3]) and tgtype = v_trgs[i][4]::int2
                      and tgenabled = 'O') then
      raise exception '394: trigger % is not in place', v_trgs[i][1]; end if;
  end loop;
  if not exists (select 1 from public.affiliate_whatsapp_settings where id) then
    raise exception '394: the settings row is missing'; end if;
  if v_cron then
    execute 'select count(*) from cron.job where jobname = $1 and schedule = $2 and command = $3 and active'
      into n using c_job, c_job_schedule, c_job_command;
    if n <> 1 then raise exception '394: cron job % is not in place', c_job; end if;
  end if;

  perform pg_notify('pgrst', 'reload schema');
end $mig$;
