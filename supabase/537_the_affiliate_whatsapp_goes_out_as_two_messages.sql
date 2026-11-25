-- 537_the_affiliate_whatsapp_goes_out_as_two_messages.sql
--
-- THE AFFILIATE WHATSAPP GOES OUT AS TWO MESSAGES: FIRST THE LOGIN LINKS, THEN A MESSAGE THE
-- AFFILIATE FORWARDS TO FRIENDS AND FAMILY, WITH THEIR REFERRAL LINK
--
--   The BEFORE md5s and the relied-on md5s below are those of production after 529 plus the
--   530-533 batch (531's affiliate_whatsapp_enqueue in), as rehearsed on a local copy on
--   24 Nov 2026. It refuses, changing nothing, unless 531 is in. If production differs when this
--   is applied, it refuses and changes nothing.
--   (The number 537 is this file's name and its errors' prefix; if it changes at commit, change
--   it there, in the 537 comments it writes into the two functions (and so their md5s, also in
--   scripts/affiliate-whatsapp/undo-537.sql and in the suite that knows them), and in the name
--   and path of its suite.)
--
-- WHAT THE OWNER ASKED (24 Nov 2026; the words and the plan approved)
--
--   The welcome WhatsApp (394: a self sign-up going live, staff resolving a claim) and the
--   "active again" one (an Owner reactivating a suspended affiliate) go out as TWO messages:
--
--   1. The first, to the affiliate: their login and forgot-password links, one line about the
--      portal, and a line saying that the next message is for their friends and family. It no
--      longer carries the referral link:
--
--        Hi {first}, welcome to the Energia affiliate programme! Your account is now active.
--
--        Log in: {app}/affiliate/login
--
--        Forgot your password? {app}/affiliate/forgot-password
--
--        In your portal you can see your referrals, earnings and payouts.
--
--        The next message is for your friends and family: copy it and send it to them. It has
--        your own referral link, so everyone who registers through it counts as your referral.
--
--        Rev 22 Global Energia
--
--      (the "active again" one: the first line is "Hi {first}, your Energia affiliate account is
--      active again."; one line in the function, wrapped here.)
--
--   2. The second (kind 'share'), for them to copy and send on, with no name in it:
--
--        Hi! I know the boss of Rev22 Global Energia, so I can bring 3 people to try their
--        therapies for FREE: an Acugraph Energy Analysis, Power Recharge Therapy and Power Foot
--        Detox Therapy, worth S$216. It's for first-timers only. Would you like to try?
--
--        Register here: {app}/r/{code}
--
--      (one paragraph in the function, wrapped here.) "3 people" is a sales line only: no rule
--      counts or limits who registers through the link.
--
--   {first} is the first name as 531's rules give it ("there" when none), {app} the settings'
--   app_url, {code} the affiliate's referral code. Only NEW affiliates get two messages: no
--   backfill, and a first message composed before this (with the referral link in it) gets no
--   second one.
--
-- WHAT THIS DOES
--
--   * affiliate_whatsapp_message (same arguments, answers null as before for an unknown kind,
--     or without the app's address or a referral code; same grants): the words above, for
--     'welcome', 'reactivated' and the new 'share'.
--   * The outbox's kind check (affiliate_whatsapp_outbox_kind) also allows 'share'.
--   * affiliate_whatsapp_settle (same arguments and answers, same grants): when a 'welcome' or
--     'reactivated' row becomes 'sent' (a 2xx answer from Pabbly), it queues that row's 'share'
--     row: the same customer, login, affiliate, phone (E.164, WhatsApp country code and number)
--     and first name; the parent's referral code; the message composed then, with the settings'
--     app_url; idempotency_key 'share:' || the parent's key (ON CONFLICT DO NOTHING, so a
--     repeated settle adds nothing); status 'queued'. Rules:
--       - a 'share' row never queues another;
--       - a first message whose text already holds its own referral link ('/r/' || its code: the
--         one-message words composed before 537, e.g. a row queued or being posted when this is
--         applied) gets no share;
--       - a 'failed' (non-2xx, timeout, no answer) or a 'skipped'/'expired' row gets none: only
--         the change to 'sent' queues it, so the share goes only after Pabbly took the first;
--       - a share whose message cannot be composed (no referral code) is kept as 'skipped'
--         (no_referral_code); any error while queueing it is caught: kept as a 'failed' row
--         (skip_reason enqueue_error, never posted), or, when even that cannot be written, only
--         warned about. The parent's 'sent' always stands, and reconcile and dispatch go on.
--     The dispatcher is not changed: its reconcile settles the first message, and the same run's
--     affiliate_whatsapp_take then hands the queued share to the post, so it goes about one
--     minute after the first, and only after Pabbly answered 2xx for the first.
--   * The outbox table's comment names the new kind.
--
-- WHAT THIS LEAVES ALONE
--
--   * affiliate_whatsapp_enqueue (531's: the name rule, the 30 welcomes a day, which count
--     kind 'welcome' only, so the shares are neither counted nor limited), take, payload,
--     mark_sending, reconcile, dispatch, the two triggers that queue the first messages, the
--     pg_cron job, the settings and the rows already in the outbox (no backfill).
--   * take with a waiting share: it expires after 48 hours like any row; it is skipped
--     (no_longer_active) when the login is no longer linked or the affiliate or customer no
--     longer active; the earlier_message_pending rule looks at 'reactivated' rows only, so a
--     share is never skipped by it. A 'reactivated' row queued while a share for the same login
--     still waits (suspended and reactivated within the minute after the welcome went) is
--     skipped by it, as with a waiting welcome: the person has just had the welcome, with the
--     same links.
--   * Pabbly and WbizTool: the body posted is the same keys, kind 'share' is a new value of the
--     'kind' key; the workflow's filter checks 'secret' only and WbizTool sends 'message'
--     (scripts/affiliate-whatsapp/PABBLY_SETUP.md). No workflow change.
--   * No trigger is on the outbox (532's audit trigger is on its 13 tables only); every write
--     here runs inside the dispatcher's SECURITY DEFINER functions.
--
-- UNDO
--
--   scripts/affiliate-whatsapp/undo-537.sql (it refuses unless the two functions are 537's
--   versions and the outbox is as 537 left it): puts 394's affiliate_whatsapp_message and
--   affiliate_whatsapp_settle back exactly, and the table comment; 'share' rows still waiting
--   ('queued', or 'failed' to be retried) become 'skipped' (undo_537), so nothing more is posted;
--   the 'share' rows stay as the record of what went out, so the kind check keeps 'share' while
--   any are there, and goes back to welcome/reactivated only when none is. A later migration
--   changing either function must pin 537's AFTER md5. 537 relies on 531 and replaces the
--   message 531 pins: to undo 531, run undo-537.sql first (it refuses once 531's enqueue is gone).
--
-- SAFETY
--
--   One statement (a DO block), atomic however it is run; lock_timeout 5s inside it (the ALTER
--   TABLE waits at most that for a dispatcher run, then this refuses whole). Every check comes
--   first; nothing is changed unless all pass:
--   * the relied-on functions are as tested, 531's affiliate_whatsapp_enqueue among them (else:
--     apply the 530-533 batch first);
--   * the settings table's shape is 394's;
--   * the two functions are both 394's (BEFORE: replaced) or both 537's (AFTER: left alone),
--     with the tested grants;
--   * the kind check and the outbox's shape are 394's (widened) or 537's (left alone; e.g. after
--     undo-537 kept 'share' rows); 537's functions with 394's check are refused.
--   After installing: every md5, grant, the kind check and the table's shape are the tested
--   ones, no client role reaches the table or the functions, and the relied-on functions are
--   unchanged. No row is written or changed.
--
-- BEFORE (production after 529, and with the 530-533 batch; md5 of pg_get_functiondef):
--   affiliate_whatsapp_message(text,text,text,text)          6cab1d437121fb0942f90dd7ec7c5310
--   affiliate_whatsapp_settle(bigint,integer,boolean,text)   950a44ad565eada10199a3ccfc0e20bb
--   constraint affiliate_whatsapp_outbox_kind                CHECK ((kind = ANY (ARRAY['welcome'::text, 'reactivated'::text])))
--   table affiliate_whatsapp_outbox (394's shape)            93b1b08d815a1aa2985f20d7b792b15a
-- Relied on, not changed:
--   affiliate_whatsapp_enqueue(text,uuid,uuid,uuid,text)     1b52d84e2842ef7709b86e2cbd03718d  (531's AFTER)
--   affiliate_whatsapp_take(integer)                         f3a07d2367e23dff74164dbe755e321f
--   affiliate_whatsapp_payload(bigint,text)                  63b8112911fe477a718ab63083afd840
--   affiliate_whatsapp_mark_sending(bigint,bigint)           c8e6a1aa0e486279f9ee86c801af4808
--   affiliate_whatsapp_reconcile()                           ca72f063b7eee883ba577fa679a2f3e6
--   affiliate_whatsapp_dispatch(integer)                     bfeefed42b32c7b68cf8f39a82a4b59a
--   trg_affiliate_whatsapp_welcome()                         248067d2763aff9e825d7d42eebb833e
--   trg_affiliate_whatsapp_reactivated()                     b44622c610e11e90fff0ffe078d2bf75
--   table affiliate_whatsapp_settings (394's shape)          52a462e9f7ab6f6b91f55b05eaf153f5
-- AFTER (for later guards):
--   affiliate_whatsapp_message(text,text,text,text)          9b7caba24a3cec3e7dc66becfae7ed4b
--   affiliate_whatsapp_settle(bigint,integer,boolean,text)   b19c07bc3735a291e29de393ca1a57f8
--   constraint affiliate_whatsapp_outbox_kind                CHECK ((kind = ANY (ARRAY['welcome'::text, 'reactivated'::text, 'share'::text])))
--   table affiliate_whatsapp_outbox (shape)                  17e02f51d286cdfefb1be873d199a8b7
--
-- NO SELF-TEST INSIDE; the suite is scripts/affiliate-whatsapp/tests/two-messages-537.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  c_app constant text := 'https://rev-22-energia-inventory-system.vercel.app';

  c_message_def constant text := $def$
create or replace function public.affiliate_whatsapp_message(p_kind text, p_first_name text, p_app_url text, p_referral_code text)
returns text
language sql
immutable
set search_path = public
as $fn$
  -- 394: the words of the affiliate WhatsApps, all in this one place, so a
  -- later migration changes them by replacing this function alone. Null for
  -- any other kind, or without the app's address or a referral code.
  -- 537 (the Owner, 24 Nov 2026): two messages. 'welcome' (a login becomes an
  -- affiliate's) and 'reactivated' (a suspended affiliate with a login is
  -- reactivated): the login links, and a line saying the next message is for
  -- friends and family; no referral link. 'share' (queued by
  -- affiliate_whatsapp_settle once the first was sent): the message the
  -- affiliate copies and sends on, with their referral link and no name.
  select case
           when p_app_url is null or p_referral_code is null then null
           when p_kind in ('welcome', 'reactivated') then
             'Hi ' || coalesce(nullif(btrim(p_first_name), ''), 'there')
             || case p_kind
                  when 'welcome' then ', welcome to the Energia affiliate programme! Your account is now active.'
                  else ', your Energia affiliate account is active again.'
                end
             || E'\n\n' || 'Log in: ' || p_app_url || '/affiliate/login'
             || E'\n\n' || 'Forgot your password? ' || p_app_url || '/affiliate/forgot-password'
             || E'\n\n' || 'In your portal you can see your referrals, earnings and payouts.'
             || E'\n\n' || 'The next message is for your friends and family: copy it and send it to them. '
                        || 'It has your own referral link, so everyone who registers through it counts as your referral.'
             || E'\n\n' || 'Rev 22 Global Energia'
           when p_kind = 'share' then
             'Hi! I know the boss of Rev22 Global Energia, so I can bring 3 people to try their therapies for FREE: '
             || 'an Acugraph Energy Analysis, Power Recharge Therapy and Power Foot Detox Therapy, worth S$216. '
             || 'It''s for first-timers only. Would you like to try?'
             || E'\n\n' || 'Register here: ' || p_app_url || '/r/' || p_referral_code
         end
$fn$
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
-- 537 (the Owner, 24 Nov 2026): a 'welcome' or 'reactivated' row that becomes
-- 'sent' queues its 'share' row (the message for friends and family, with the
-- referral link): same customer, login, affiliate, phone and first name, the
-- row's referral code, composed now with the settings' app_url, key 'share:'
-- and the row's key, once only. The same dispatcher run posts it, about a
-- minute after the first. None for a 'share' row, and none for a first
-- message that already holds its own referral link (the one-message words
-- from before 537). It never undoes the 'sent': a share that cannot be
-- composed is kept 'skipped' (no_referral_code), an error 'failed'
-- (enqueue_error, never posted), or only warned about.
declare
  v_row public.affiliate_whatsapp_outbox%rowtype; v_key text; v_app text; v_msg text;
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
  returning o.* into v_row;

  if v_row.status = 'sent' and v_row.kind in ('welcome', 'reactivated')
     and strpos(coalesce(v_row.message, ''), '/r/' || coalesce(v_row.referral_code, chr(1))) = 0 then
    v_key := 'share:' || v_row.idempotency_key;
    begin
      select s.app_url into v_app from public.affiliate_whatsapp_settings s where s.id;
      v_app := coalesce(v_app, 'https://rev-22-energia-inventory-system.vercel.app');
      v_msg := public.affiliate_whatsapp_message('share', v_row.first_name, v_app, v_row.referral_code);
      insert into public.affiliate_whatsapp_outbox (kind, idempotency_key, customer_id, auth_user_id, affiliate_id,
          phone_e164, wa_country_code, wa_number, first_name, referral_code, message, status, skip_reason)
      values ('share', v_key, v_row.customer_id, v_row.auth_user_id, v_row.affiliate_id,
          v_row.phone_e164, v_row.wa_country_code, v_row.wa_number, v_row.first_name, v_row.referral_code, v_msg,
          case when v_msg is null then 'skipped' else 'queued' end,
          case when v_msg is null then 'no_referral_code' end)
      on conflict (idempotency_key) do nothing;
    exception when others then
      begin
        insert into public.affiliate_whatsapp_outbox (kind, idempotency_key, customer_id, auth_user_id, affiliate_id,
            first_name, referral_code, status, skip_reason, last_error)
        values ('share', v_key, v_row.customer_id, v_row.auth_user_id, v_row.affiliate_id,
            v_row.first_name, v_row.referral_code, 'failed', 'enqueue_error', left(sqlerrm, 500))
        on conflict (idempotency_key) do nothing;
      exception when others then
        raise warning '537: the share WhatsApp after outbox row % was not queued: %', v_row.id, sqlerrm;
      end;
    end;
  end if;
  return v_row.status;
end $fn$
$def$;

  c_outbox_comment_before constant text :=
    '394: one row per affiliate login WhatsApp (welcome, reactivated) and what became of it.';
  c_outbox_comment_after constant text :=
    '394, 537: one row per affiliate WhatsApp (welcome, reactivated, and the share message for friends and family queued once either is sent) and what became of it.';

  -- Relied on, not changed: [signature, md5].
  c_relied constant text[] := array[
    'public.affiliate_whatsapp_enqueue(text,uuid,uuid,uuid,text)',
    'public.affiliate_whatsapp_take(integer)',
    'public.affiliate_whatsapp_payload(bigint,text)',
    'public.affiliate_whatsapp_mark_sending(bigint,bigint)',
    'public.affiliate_whatsapp_reconcile()',
    'public.affiliate_whatsapp_dispatch(integer)',
    'public.trg_affiliate_whatsapp_welcome()',
    'public.trg_affiliate_whatsapp_reactivated()'];
  c_relied_md5 constant text[] := array[
    '1b52d84e2842ef7709b86e2cbd03718d',   -- 531's AFTER: the 530-533 batch is in
    'f3a07d2367e23dff74164dbe755e321f',
    '63b8112911fe477a718ab63083afd840',
    'c8e6a1aa0e486279f9ee86c801af4808',
    'ca72f063b7eee883ba577fa679a2f3e6',
    'bfeefed42b32c7b68cf8f39a82a4b59a',
    '248067d2763aff9e825d7d42eebb833e',
    'b44622c610e11e90fff0ffe078d2bf75'];
  -- Replaced: [signature, BEFORE, AFTER]; the grants before and after.
  c_sig constant text[] := array[
    'public.affiliate_whatsapp_message(text,text,text,text)',
    'public.affiliate_whatsapp_settle(bigint,integer,boolean,text)'];
  c_before constant text[] := array[
    '6cab1d437121fb0942f90dd7ec7c5310',
    '950a44ad565eada10199a3ccfc0e20bb'];
  c_after constant text[] := array[
    '9b7caba24a3cec3e7dc66becfae7ed4b',
    'b19c07bc3735a291e29de393ca1a57f8'];
  c_acl constant text := 'postgres=X/postgres,service_role=X/postgres';
  -- The kind check and the tables' shapes.
  c_kind_before constant text := 'CHECK ((kind = ANY (ARRAY[''welcome''::text, ''reactivated''::text])))';
  c_kind_after  constant text := 'CHECK ((kind = ANY (ARRAY[''welcome''::text, ''reactivated''::text, ''share''::text])))';
  c_outbox_before constant text := '93b1b08d815a1aa2985f20d7b792b15a';
  c_outbox_after  constant text := '17e02f51d286cdfefb1be873d199a8b7';
  c_settings_shape constant text := '52a462e9f7ab6f6b91f55b05eaf153f5';

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_defs text[];
  v_state text[] := array_fill(null::text, array[2]);
  v_kind text; v_widen boolean; v_shape text; v text; i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy table or function waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);
  v_defs := array[c_message_def, c_settle_def];

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure(c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure(c_relied[i]))) <> c_relied_md5[i] then
      raise exception '537: % is missing or not the version this was tested against (md5 %).%', c_relied[i],
        coalesce(md5(pg_get_functiondef(to_regprocedure(c_relied[i]))), 'none'),
        case when i = 1 then ' 531 must be in first (the 530-533 batch).' else ' Re-read it and re-test before applying.' end;
    end if;
  end loop;

  if to_regclass('public.affiliate_whatsapp_settings') is null or to_regclass('public.affiliate_whatsapp_outbox') is null then
    raise exception '537: the affiliate WhatsApp tables (394) are missing'; end if;
  select md5(string_agg(x, E'\n' order by x)) into v from (
    select 'col ' || lpad(a.attnum::text, 3, '0') || ' ' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
           || case when a.attnotnull then ' not null' else '' end
           || case when a.attidentity <> '' then ' identity ' || a.attidentity::text else '' end
           || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), '') x
      from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
     where a.attrelid = 'public.affiliate_whatsapp_settings'::regclass and a.attnum > 0 and not a.attisdropped
    union all
    select 'con ' || c.conname || ' ' || pg_get_constraintdef(c.oid)
      from pg_constraint c where c.conrelid = 'public.affiliate_whatsapp_settings'::regclass
    union all
    select 'idx ' || pg_get_indexdef(x.indexrelid) from pg_index x where x.indrelid = 'public.affiliate_whatsapp_settings'::regclass
    union all
    select 'rls ' || c.relrowsecurity from pg_class c where c.oid = 'public.affiliate_whatsapp_settings'::regclass) s;
  if v <> c_settings_shape then
    raise exception '537: public.affiliate_whatsapp_settings is not 394''s shape (md5 %). Re-read it before applying.', v; end if;

  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure(c_sig[i]) is null then raise exception '537: % is missing', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure(c_sig[i])) is distinct from c_acl then
      raise exception '537: the grants of % are not the tested ones. Re-read them before applying.', c_sig[i]; end if;
    v := md5(pg_get_functiondef(to_regprocedure(c_sig[i])));
    if v = c_before[i] then v_state[i] := 'before';
    elsif v = c_after[i] then v_state[i] := 'after';
    else
      raise exception '537: % is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], v;
    end if;
  end loop;
  if v_state[1] <> v_state[2] then
    raise exception '537: affiliate_whatsapp_message is % 537 and affiliate_whatsapp_settle is % it. Re-read them before applying.',
      v_state[1], v_state[2]; end if;

  select pg_get_constraintdef(c.oid) into v_kind from pg_constraint c
   where c.conrelid = 'public.affiliate_whatsapp_outbox'::regclass and c.conname = 'affiliate_whatsapp_outbox_kind';
  select md5(string_agg(x, E'\n' order by x)) into v_shape from (
    select 'col ' || lpad(a.attnum::text, 3, '0') || ' ' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
           || case when a.attnotnull then ' not null' else '' end
           || case when a.attidentity <> '' then ' identity ' || a.attidentity::text else '' end
           || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), '') x
      from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
     where a.attrelid = 'public.affiliate_whatsapp_outbox'::regclass and a.attnum > 0 and not a.attisdropped
    union all
    select 'con ' || c.conname || ' ' || pg_get_constraintdef(c.oid)
      from pg_constraint c where c.conrelid = 'public.affiliate_whatsapp_outbox'::regclass
    union all
    select 'idx ' || pg_get_indexdef(x.indexrelid) from pg_index x where x.indrelid = 'public.affiliate_whatsapp_outbox'::regclass
    union all
    select 'rls ' || c.relrowsecurity from pg_class c where c.oid = 'public.affiliate_whatsapp_outbox'::regclass) s;
  if v_kind is not distinct from c_kind_before and v_shape = c_outbox_before then
    v_widen := true;
  elsif v_kind is not distinct from c_kind_after and v_shape = c_outbox_after then
    v_widen := false;
    raise notice '537: the outbox''s kind check already allows ''share''; left alone';
  else
    raise exception '537: public.affiliate_whatsapp_outbox is not as tested (kind check %, shape md5 %). Re-read it before applying.',
      coalesce(v_kind, 'missing'), v_shape;
  end if;
  if v_state[1] = 'after' and v_widen then
    raise exception '537: the functions are 537''s but the outbox''s kind check does not allow ''share''. Re-read them before applying.'; end if;

  -- 2. Install: the check first (the new settle writes 'share'), then the functions
  if v_widen then
    alter table public.affiliate_whatsapp_outbox drop constraint affiliate_whatsapp_outbox_kind;
    alter table public.affiliate_whatsapp_outbox add constraint affiliate_whatsapp_outbox_kind
      check (kind in ('welcome', 'reactivated', 'share'));
  end if;
  if v_state[1] = 'before' then
    for i in 1 .. cardinality(c_sig) loop
      execute v_defs[i];
    end loop;
  else
    raise notice '537: affiliate_whatsapp_message and affiliate_whatsapp_settle are already 537''s; left alone';
  end if;
  if obj_description('public.affiliate_whatsapp_outbox'::regclass, 'pg_class') is distinct from c_outbox_comment_after then
    execute format('comment on table public.affiliate_whatsapp_outbox is %L', c_outbox_comment_after);
  end if;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    v := md5(pg_get_functiondef(to_regprocedure(c_sig[i])));
    if v <> c_after[i] then
      raise exception '537: % was installed with md5 %, not the tested %', c_sig[i], v, c_after[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure(c_sig[i])) is distinct from c_acl
       or has_function_privilege('anon', c_sig[i], 'execute')
       or has_function_privilege('authenticated', c_sig[i], 'execute') then
      raise exception '537: the grants of % changed', c_sig[i]; end if;
  end loop;
  select md5(string_agg(x, E'\n' order by x)) into v_shape from (
    select 'col ' || lpad(a.attnum::text, 3, '0') || ' ' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
           || case when a.attnotnull then ' not null' else '' end
           || case when a.attidentity <> '' then ' identity ' || a.attidentity::text else '' end
           || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), '') x
      from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
     where a.attrelid = 'public.affiliate_whatsapp_outbox'::regclass and a.attnum > 0 and not a.attisdropped
    union all
    select 'con ' || c.conname || ' ' || pg_get_constraintdef(c.oid)
      from pg_constraint c where c.conrelid = 'public.affiliate_whatsapp_outbox'::regclass
    union all
    select 'idx ' || pg_get_indexdef(x.indexrelid) from pg_index x where x.indrelid = 'public.affiliate_whatsapp_outbox'::regclass
    union all
    select 'rls ' || c.relrowsecurity from pg_class c where c.oid = 'public.affiliate_whatsapp_outbox'::regclass) s;
  if v_shape <> c_outbox_after then
    raise exception '537: public.affiliate_whatsapp_outbox has shape md5 %, not the tested %', v_shape, c_outbox_after; end if;
  if has_table_privilege('anon', 'public.affiliate_whatsapp_outbox', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'public.affiliate_whatsapp_outbox', 'select,insert,update,delete,truncate,references,trigger') then
    raise exception '537: public.affiliate_whatsapp_outbox is reachable by a client role'; end if;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure(c_relied[i]))) <> c_relied_md5[i] then
      raise exception '537: % changed', c_relied[i]; end if;
  end loop;
  if public.affiliate_whatsapp_message('share', null, c_app, 'X') is null
     or public.affiliate_whatsapp_message('other', null, c_app, 'X') is not null then
    raise exception '537: affiliate_whatsapp_message does not answer as tested'; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
