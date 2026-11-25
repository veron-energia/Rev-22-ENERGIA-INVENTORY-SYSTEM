-- undo-537.sql: puts the affiliate WhatsApp back to ONE message (394's words), undoing
-- supabase/537_the_affiliate_whatsapp_goes_out_as_two_messages.sql.
--
-- WHAT IT DOES
--
--   * It refuses, changing nothing, unless affiliate_whatsapp_message and
--     affiliate_whatsapp_settle are 537's versions (AFTER md5s below) with their tested grants,
--     the outbox is as 537 left it (kind check with 'share', shape 17e02f51...), and the
--     functions 537 relied on are unchanged (531's affiliate_whatsapp_enqueue among them).
--   * 'share' rows still waiting ('queued', or 'failed' to be posted again) become 'skipped'
--     (skip_reason undo_537), so nothing more is posted after the undo. A 'share' row being posted
--     ('sending') is settled by 394's settle as any row; one 'sent' stays 'sent'.
--   * affiliate_whatsapp_message and affiliate_whatsapp_settle are put back exactly as 394 made
--     them (6cab1d43..., 950a44ad...), grants unchanged, and the outbox's comment as 394 wrote it.
--     From then on a new first message carries the referral link again, and no share is queued.
--   * The 'share' rows are KEPT: they are the record of what was sent. So the kind check goes back
--     to ('welcome', 'reactivated') only when no 'share' row is left (the shape is then 394's,
--     93b1b08d...); while any is there it keeps 'share' (a notice says so), and a later 537 run
--     accepts that state and leaves the check alone. To narrow it anyway, delete the share rows
--     by hand first (they are a log only; nothing reads them).
--   * The first messages composed under 537 (without the referral link) and still waiting are
--     posted with those words; they get no share. Run this when the outbox has nothing waiting
--     (PABBLY_SETUP.md, "Watching it"), or turn sending off first, to avoid that.
--
-- One statement (a DO block), lock_timeout 5s inside it. Run it like a migration, in one
-- transaction with nothing else:
--   psql -X -v ON_ERROR_STOP=1 -1 -f scripts/affiliate-whatsapp/undo-537.sql

do $undo$
declare
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
  c_outbox_comment_394 constant text :=
    '394: one row per affiliate login WhatsApp (welcome, reactivated) and what became of it.';

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
    '1b52d84e2842ef7709b86e2cbd03718d',
    'f3a07d2367e23dff74164dbe755e321f',
    '63b8112911fe477a718ab63083afd840',
    'c8e6a1aa0e486279f9ee86c801af4808',
    'ca72f063b7eee883ba577fa679a2f3e6',
    'bfeefed42b32c7b68cf8f39a82a4b59a',
    '248067d2763aff9e825d7d42eebb833e',
    'b44622c610e11e90fff0ffe078d2bf75'];
  c_sig constant text[] := array[
    'public.affiliate_whatsapp_message(text,text,text,text)',
    'public.affiliate_whatsapp_settle(bigint,integer,boolean,text)'];
  c_537 constant text[] := array[
    '9b7caba24a3cec3e7dc66becfae7ed4b',
    'b19c07bc3735a291e29de393ca1a57f8'];
  c_394 constant text[] := array[
    '6cab1d437121fb0942f90dd7ec7c5310',
    '950a44ad565eada10199a3ccfc0e20bb'];
  c_acl constant text := 'postgres=X/postgres,service_role=X/postgres';
  c_kind_537 constant text := 'CHECK ((kind = ANY (ARRAY[''welcome''::text, ''reactivated''::text, ''share''::text])))';
  c_shape_537 constant text := '17e02f51d286cdfefb1be873d199a8b7';
  c_shape_394 constant text := '93b1b08d815a1aa2985f20d7b792b15a';
  -- The outbox's shape, as 394 and 537 measure it.
  c_shape_sql constant text := $q$
    select md5(string_agg(x, E'\n' order by x)) from (
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
      select 'rls ' || c.relrowsecurity from pg_class c where c.oid = 'public.affiliate_whatsapp_outbox'::regclass) s
  $q$;

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_defs text[];
  v text; v_kind text; v_shape text; n_skipped int; n_share int; i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);
  v_defs := array[c_message_def, c_settle_def];

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure(c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure(c_relied[i]))) <> c_relied_md5[i] then
      raise exception 'undo-537: % is not the version 537 was tested with. Re-read it before undoing.', c_relied[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    v := md5(pg_get_functiondef(to_regprocedure(c_sig[i])));
    if v <> c_537[i] then
      raise exception 'undo-537: % is not 537''s version (md5 %), so there is nothing of 537 to undo, or something changed it since.', c_sig[i], v; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure(c_sig[i])) is distinct from c_acl then
      raise exception 'undo-537: the grants of % are not the tested ones', c_sig[i]; end if;
  end loop;
  select pg_get_constraintdef(c.oid) into v_kind from pg_constraint c
   where c.conrelid = 'public.affiliate_whatsapp_outbox'::regclass and c.conname = 'affiliate_whatsapp_outbox_kind';
  execute c_shape_sql into v_shape;
  if v_kind is distinct from c_kind_537 or v_shape is distinct from c_shape_537 then
    raise exception 'undo-537: public.affiliate_whatsapp_outbox is not as 537 left it. Re-read it before undoing.'; end if;

  -- 2. No share waits any more
  update public.affiliate_whatsapp_outbox
     set status = 'skipped', skip_reason = 'undo_537', retry_after = null, updated_at = now()
   where kind = 'share' and (status = 'queued' or (status = 'failed' and retry_after is not null));
  get diagnostics n_skipped = row_count;
  raise notice 'undo-537: % waiting share message(s) skipped (undo_537)', n_skipped;

  -- 3. 394's functions and comment back
  for i in 1 .. cardinality(c_sig) loop
    execute v_defs[i];
  end loop;
  execute format('comment on table public.affiliate_whatsapp_outbox is %L', c_outbox_comment_394);

  -- 4. The kind check: back to 394's only when no share row is left
  select count(*) into n_share from public.affiliate_whatsapp_outbox where kind = 'share';
  if n_share = 0 then
    alter table public.affiliate_whatsapp_outbox drop constraint affiliate_whatsapp_outbox_kind;
    alter table public.affiliate_whatsapp_outbox add constraint affiliate_whatsapp_outbox_kind
      check (kind in ('welcome', 'reactivated'));
    execute c_shape_sql into v_shape;
    if v_shape is distinct from c_shape_394 then
      raise exception 'undo-537: the outbox is not 394''s shape after narrowing its kind check'; end if;
  else
    raise notice 'undo-537: % share row(s) kept as the record, so the kind check keeps ''share''', n_share;
  end if;

  -- 5. Checks after
  for i in 1 .. cardinality(c_sig) loop
    v := md5(pg_get_functiondef(to_regprocedure(c_sig[i])));
    if v <> c_394[i] then
      raise exception 'undo-537: % was put back with md5 %, not 394''s %', c_sig[i], v, c_394[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure(c_sig[i])) is distinct from c_acl then
      raise exception 'undo-537: the grants of % changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure(c_relied[i]))) <> c_relied_md5[i] then
      raise exception 'undo-537: % changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
