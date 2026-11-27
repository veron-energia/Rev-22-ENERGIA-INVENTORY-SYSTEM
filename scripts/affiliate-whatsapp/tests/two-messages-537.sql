-- The affiliate WhatsApp goes out as two messages (537; the Owner, 24 Nov 2026).
--
--   M  The migration: only affiliate_whatsapp_message and affiliate_whatsapp_settle change (and
--      the outbox's kind check and comment); a second run changes nothing; it refuses, changing
--      nothing, without 531's enqueue, with a message function it did not write, with another
--      kind check, and with 537's functions on 394's kind check.
--   T  The words, as whole strings: 'welcome', 'reactivated' and 'share'; the greeting's name
--      as before ('there' when none or blank).
--   N  Null as before: an unknown kind, no app address, no referral code (each kind).
--   W  A login that goes live queues the new first message (no referral link) and nothing else.
--   S  settle: a 2xx answer on a 'welcome' or 'reactivated' row queues its 'share' row (same
--      customer, login, affiliate, phone, name; the parent's code; key 'share:' || parent key);
--      none after a non-2xx (until a retry is answered 2xx), a timeout, no answer, or for a
--      skipped, expired or still queued row; never a share of a share; a repeated settle gives
--      one share; a first message in the one-message words from before 537 gives none; a share
--      that cannot be composed is kept skipped (no_referral_code); an error while queueing it
--      is kept 'failed' (enqueue_error), or only warned about, and the 'sent' stands.
--   D  The dispatcher's steps without pg_net posting anything: take -> mark_sending -> a pg_net
--      answer row -> reconcile settles it -> take hands over the share, after the first.
--   A  take with a waiting share: no_longer_active skips it; it expires after 48 hours; it is
--      never skipped as earlier_message_pending, and a reactivation behind it is.
--   L  The 30 welcomes a day (531) count 'welcome' only: shares neither count nor are limited.
--   G  Grants of the two functions and the outbox unchanged; no client role reaches them.
--   U  scripts/affiliate-whatsapp/undo-537.sql: with share rows it puts 394's functions back,
--      skips the waiting shares and keeps the kind check; 537 again installs over that; with no
--      share rows it puts 394's check and shape back too; it refuses where 537 is not in.
--      undo-531 refuses while 537 is in; undo-537 first, then undo-531, works (U8, U9).
--      (Two refusals are provoked on purpose: psql prints their "ERROR:  undo-537: ..." and
--      "ERROR:  undo-531: ..." lines.)
--
-- Disposable local database only; everything is rolled back. Every name is a test name
-- ("Testing ..."); phones are the fictional +61 491 570 7nn range; links point at the code
-- ENTEST00 or at codes made here. Run it on a copy of production after the 530-533 batch: it
-- applies 537 twice; with -v skip_install=1 where 537 is already in. Where the settings row is
-- missing (the schema-only copies) it is made here, as production has it (sending off here).
-- Every check runs, then the file fails if any did.
-- (Several refusals are provoked on purpose under M: psql prints their "ERROR:  537: ..." lines.)
--   psql -X -v ON_ERROR_STOP=1 -f scripts/affiliate-whatsapp/tests/two-messages-537.sql
--   psql -X -v ON_ERROR_STOP=1 -v skip_install=1 -f scripts/affiliate-whatsapp/tests/two-messages-537.sql
\set ON_ERROR_STOP on
begin;
-- 546 (security audit of 17 Nov 2026, L15): where it is in, its UNDO goes first, as this file pins
-- md5s of functions it changes (only their search path); this run only, rolled back with the rest.
select coalesce('search_path=public, pg_temp' = any (proconfig), false) as t546_in
  from pg_proc where oid = 'public.current_user_role()'::regprocedure \gset
\if :t546_in
select set_config('energia.undo546_skip_body_check', 'on', true) \g /dev/null
\ir ../../permissions/undo-546.sql
\endif
set local lock_timeout = '10s';
set local statement_timeout = '300s';
create temp table failed(n serial, msg text);
create temp table ran(n serial);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  insert into ran default values;
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create function pg_temp.fp() returns table(fn text, md5 text, acl text) language sql as
$$ select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text, '')
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') $$;
create function pg_temp.shape() returns text language sql as
$$ select md5(string_agg(x, E'\n' order by x)) from (
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
      select 'rls ' || c.relrowsecurity from pg_class c where c.oid = 'public.affiliate_whatsapp_outbox'::regclass) s $$;
create function pg_temp.md5of(f text) returns text language sql as $$ select md5(pg_get_functiondef(to_regprocedure(f))) $$;
create function pg_temp.kindcheck() returns text language sql as
$$ select pg_get_constraintdef(c.oid) from pg_constraint c
    where c.conrelid = 'public.affiliate_whatsapp_outbox'::regclass and c.conname = 'affiliate_whatsapp_outbox_kind' $$;

-- ═════ M the migration ═════
create temp table fp0 as select * from pg_temp.fp();
create temp table shape0 as select pg_temp.shape() s, pg_temp.kindcheck() k,
                                   obj_description('public.affiliate_whatsapp_outbox'::regclass, 'pg_class') c;
select pg_temp.md5of('public.affiliate_whatsapp_message(text,text,text,text)') = '9b7caba24a3cec3e7dc66becfae7ed4b' as had537 \gset
\if :{?skip_install}
\elif :had537
\echo 537 is already in: run with -v skip_install=1
select 1/0;
\else
select pg_temp.check(pg_temp.md5of('public.affiliate_whatsapp_enqueue(text,uuid,uuid,uuid,text)') = '1b52d84e2842ef7709b86e2cbd03718d'
    and pg_temp.md5of('public.affiliate_whatsapp_message(text,text,text,text)') = '6cab1d437121fb0942f90dd7ec7c5310'
    and pg_temp.md5of('public.affiliate_whatsapp_settle(bigint,integer,boolean,text)') = '950a44ad565eada10199a3ccfc0e20bb'
    and (select s from shape0) = '93b1b08d815a1aa2985f20d7b792b15a',
  'M0 the database is as 537 expects it: 531''s enqueue in, 394''s message and settle, 394''s outbox');

-- Refusals first, each undone by its savepoint; then the real install.
savepoint r1;
create or replace function public.affiliate_whatsapp_message(p_kind text, p_first_name text, p_app_url text, p_referral_code text)
returns text language sql immutable set search_path = public as $fn$ select 'other words' $fn$;
\set ON_ERROR_STOP off
\ir ../../../supabase/537_the_affiliate_whatsapp_goes_out_as_two_messages.sql
\set r1_err :ERROR
\set ON_ERROR_STOP on
rollback to savepoint r1;
select pg_temp.check(:'r1_err' = 'true' and :'LAST_ERROR_MESSAGE' like '537: public.affiliate_whatsapp_message(text,text,text,text) is not the version this was tested against%',
  'M1 it refuses a message function it did not write: ' || :'LAST_ERROR_MESSAGE');

savepoint r2;
do $$ begin execute replace(pg_get_functiondef('public.affiliate_whatsapp_enqueue(text,uuid,uuid,uuid,text)'::regprocedure),
                            '-- 531: when the login was made', '-- 531: when the login was made (not 531''s text)'); end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/537_the_affiliate_whatsapp_goes_out_as_two_messages.sql
\set r2_err :ERROR
\set ON_ERROR_STOP on
rollback to savepoint r2;
select pg_temp.check(:'r2_err' = 'true' and :'LAST_ERROR_MESSAGE' like '537: public.affiliate_whatsapp_enqueue(text,uuid,uuid,uuid,text) is missing or not the version%531 must be in first%',
  'M1 it refuses unless 531''s enqueue is in: ' || :'LAST_ERROR_MESSAGE');

savepoint r3;
alter table public.affiliate_whatsapp_outbox drop constraint affiliate_whatsapp_outbox_kind;
alter table public.affiliate_whatsapp_outbox add constraint affiliate_whatsapp_outbox_kind check (kind in ('welcome', 'reactivated', 'promo'));
\set ON_ERROR_STOP off
\ir ../../../supabase/537_the_affiliate_whatsapp_goes_out_as_two_messages.sql
\set r3_err :ERROR
\set ON_ERROR_STOP on
rollback to savepoint r3;
select pg_temp.check(:'r3_err' = 'true' and :'LAST_ERROR_MESSAGE' like '537: public.affiliate_whatsapp_outbox is not as tested%',
  'M1 it refuses another kind check: ' || :'LAST_ERROR_MESSAGE');

savepoint r4;
\ir ../../../supabase/537_the_affiliate_whatsapp_goes_out_as_two_messages.sql
alter table public.affiliate_whatsapp_outbox drop constraint affiliate_whatsapp_outbox_kind;
alter table public.affiliate_whatsapp_outbox add constraint affiliate_whatsapp_outbox_kind check (kind in ('welcome', 'reactivated'));
\set ON_ERROR_STOP off
\ir ../../../supabase/537_the_affiliate_whatsapp_goes_out_as_two_messages.sql
\set r4_err :ERROR
\set ON_ERROR_STOP on
rollback to savepoint r4;
select pg_temp.check(:'r4_err' = 'true' and :'LAST_ERROR_MESSAGE' like '537: the functions are 537''s but the outbox''s kind check does not allow ''share''%',
  'M1 it refuses 537''s functions on 394''s kind check: ' || :'LAST_ERROR_MESSAGE');
select pg_temp.check(not exists (select * from pg_temp.fp() except select * from fp0)
    and not exists (select * from fp0 except select * from pg_temp.fp())
    and (select s from shape0) = pg_temp.shape(),
  'M1 the refused runs changed nothing');

\ir ../../../supabase/537_the_affiliate_whatsapp_goes_out_as_two_messages.sql
create temp table fp1 as select * from pg_temp.fp();
create temp table shape1 as select pg_temp.shape() s, obj_description('public.affiliate_whatsapp_outbox'::regclass, 'pg_class') c;
\ir ../../../supabase/537_the_affiliate_whatsapp_goes_out_as_two_messages.sql
select pg_temp.check((select string_agg(fn, ',' order by fn) from (select fn, md5 from pg_temp.fp() except select fn, md5 from fp0) x)
      = 'affiliate_whatsapp_message(text,text,text,text),affiliate_whatsapp_settle(bigint,integer,boolean,text)'
    and not exists (select fn from fp0 except select fn from pg_temp.fp())
    and not exists (select fn, acl from pg_temp.fp() except select fn, acl from fp0),
  'M2 only affiliate_whatsapp_message and affiliate_whatsapp_settle changed; no function added or removed; grants as before');
select pg_temp.check(not exists (select * from pg_temp.fp() except select * from fp1)
    and (select s from shape1) = pg_temp.shape()
    and (select c from shape1) = obj_description('public.affiliate_whatsapp_outbox'::regclass, 'pg_class'),
  'M2 a second run changes nothing');
\endif
select pg_temp.check(pg_temp.md5of('public.affiliate_whatsapp_message(text,text,text,text)') = '9b7caba24a3cec3e7dc66becfae7ed4b'
    and pg_temp.md5of('public.affiliate_whatsapp_settle(bigint,integer,boolean,text)') = 'b19c07bc3735a291e29de393ca1a57f8'
    and pg_temp.kindcheck() = 'CHECK ((kind = ANY (ARRAY[''welcome''::text, ''reactivated''::text, ''share''::text])))'
    and pg_temp.shape() = '17e02f51d286cdfefb1be873d199a8b7'
    and obj_description('public.affiliate_whatsapp_outbox'::regclass, 'pg_class') like '394, 537:%share%',
  'M3 the AFTER md5s, the kind check, the outbox''s shape and comment are 537''s');
select pg_temp.check(md5 = m, 'M4 ' || f || ' is unchanged (relied on)')
  from (values
    ('public.affiliate_whatsapp_enqueue(text,uuid,uuid,uuid,text)',   '1b52d84e2842ef7709b86e2cbd03718d'),
    ('public.affiliate_whatsapp_take(integer)',                       'f3a07d2367e23dff74164dbe755e321f'),
    ('public.affiliate_whatsapp_payload(bigint,text)',                '63b8112911fe477a718ab63083afd840'),
    ('public.affiliate_whatsapp_mark_sending(bigint,bigint)',         'c8e6a1aa0e486279f9ee86c801af4808'),
    ('public.affiliate_whatsapp_reconcile()',                         'ca72f063b7eee883ba577fa679a2f3e6'),
    ('public.affiliate_whatsapp_dispatch(integer)',                   'bfeefed42b32c7b68cf8f39a82a4b59a'),
    ('public.trg_affiliate_whatsapp_welcome()',                       '248067d2763aff9e825d7d42eebb833e'),
    ('public.trg_affiliate_whatsapp_reactivated()',                   'b44622c610e11e90fff0ffe078d2bf75')) x(f, m),
  lateral (select pg_temp.md5of(f) md5) y;
select pg_temp.check(not exists (select 1 from pg_trigger where tgrelid = 'public.affiliate_whatsapp_outbox'::regclass),
  'M5 no trigger is on the outbox (532''s audit trigger is not): the dispatcher''s inserts touch nothing else');

-- ═════ T the words ═════
-- Each written out here on its own, exactly as the Owner approved them.
create temp table fp1x(fn text);
insert into fp1x values ('affiliate_whatsapp_message(text,text,text,text)'), ('affiliate_whatsapp_settle(bigint,integer,boolean,text)');
create temp table words(kind text primary key, txt text);
insert into words values
('welcome', 'Hi John, welcome to the Energia affiliate programme! Your account is now active.

Log in: https://rev-22-energia-inventory-system.vercel.app/affiliate/login

Forgot your password? https://rev-22-energia-inventory-system.vercel.app/affiliate/forgot-password

In your portal you can see your referrals, earnings and payouts.

The next message is for your friends and family: copy it and send it to them. It has your own referral link, so everyone who registers through it counts as your referral.

Rev 22 Global Energia'),
('reactivated', 'Hi John, your Energia affiliate account is active again.

Log in: https://rev-22-energia-inventory-system.vercel.app/affiliate/login

Forgot your password? https://rev-22-energia-inventory-system.vercel.app/affiliate/forgot-password

In your portal you can see your referrals, earnings and payouts.

The next message is for your friends and family: copy it and send it to them. It has your own referral link, so everyone who registers through it counts as your referral.

Rev 22 Global Energia'),
('share', 'Hi! I know the boss of Rev22 Global Energia, so I can bring 3 people to try their therapies for FREE: an Acugraph Energy Analysis, Power Recharge Therapy and Power Foot Detox Therapy, worth S$216. It''s for first-timers only. Would you like to try?

Register here: https://rev-22-energia-inventory-system.vercel.app/r/ENTEST00');
create function pg_temp.msg(k text, f text, app text, code text) returns text language sql as
$$ select public.affiliate_whatsapp_message(k, f, app, code) $$;
\set app '''https://rev-22-energia-inventory-system.vercel.app'''
select pg_temp.check(pg_temp.msg(kind, 'John', :app, 'ENTEST00') = txt,
  'T1 ' || kind || ': the whole text is the approved words (' || length(txt) || ' characters)')
  from words order by kind;
select pg_temp.check(position(E'\r' in txt) = 0 and position(E'’' in txt) = 0 and txt !~ E'\\s$' and txt !~ E'^\\s',
  'T2 ' || kind || ': plain line breaks, straight apostrophes, no space or line break at either end') from words order by kind;
select pg_temp.check(pg_temp.msg('welcome', null, :app, 'ENTEST00') = replace((select txt from words where kind = 'welcome'), 'Hi John,', 'Hi there,')
    and pg_temp.msg('reactivated', '  ', :app, 'ENTEST00') = replace((select txt from words where kind = 'reactivated'), 'Hi John,', 'Hi there,')
    and pg_temp.msg('welcome', ' Mary Ann ', :app, 'ENTEST00') like 'Hi Mary Ann, welcome%',
  'T3 no name or a blank one: "Hi there"; a name is trimmed, as before');
select pg_temp.check(pg_temp.msg('share', 'John', :app, 'ENTEST00') = pg_temp.msg('share', null, :app, 'ENTEST00')
    and position('John' in pg_temp.msg('share', 'John', :app, 'ENTEST00')) = 0,
  'T4 the share message has no name in it');
select pg_temp.check(position('/r/' in pg_temp.msg('welcome', 'John', :app, 'ENTEST00')) = 0
    and position('/r/' in pg_temp.msg('reactivated', 'John', :app, 'ENTEST00')) = 0
    and position('ENTEST00' in pg_temp.msg('welcome', 'John', :app, 'ENTEST00')) = 0,
  'T5 the first messages no longer carry the referral link');

-- ═════ N null as before ═════
select pg_temp.check(pg_temp.msg('promo', 'John', :app, 'ENTEST00') is null and pg_temp.msg(null, 'John', :app, 'ENTEST00') is null
    and pg_temp.msg('Welcome', 'John', :app, 'ENTEST00') is null,
  'N1 an unknown kind (or null, or another spelling): null');
select pg_temp.check(bool_and(pg_temp.msg(k, 'John', null, 'ENTEST00') is null and pg_temp.msg(k, 'John', :app, null) is null
                              and pg_temp.msg(k, null, null, null) is null),
  'N2 no app address or no referral code: null, for welcome, reactivated and share')
  from unnest(array['welcome', 'reactivated', 'share']) k;

-- ═════ Fixtures ═════
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.ph(n int) returns text language sql as $$ select '+61491570' || (700 + n)::text $$;
select pg_temp.check(not exists (select 1 from public.customers where public.normalize_customer_phone(phone) like '+614915707__'),
  'F0 no customer uses the test phones +61 491 570 7nn (the checks below assume so)');
insert into public.affiliate_whatsapp_settings (id) values (true) on conflict (id) do nothing;
update public.affiliate_whatsapp_settings set app_url = 'https://rev-22-energia-inventory-system.vercel.app', enabled = false where id;
-- Only this file's rows in the outbox from here on (rolled back).
delete from public.affiliate_whatsapp_outbox;
-- An affiliate: a customer made 3 days before the login (531 greets by its name), an active
-- affiliate record, and the login's account (its insert queues the welcome).
create function pg_temp.affiliate(key text, first text, n int) returns uuid language plpgsql as
$$declare u uuid := gen_random_uuid(); c uuid; a uuid; begin
  insert into auth.users(id, email, email_confirmed_at, created_at, raw_user_meta_data)
    values (u, 'wa537-' || lower(key) || '@example.invalid', now(), now(), '{}'::jsonb);
  insert into public.customers(first_name, last_name, full_name, phone, created_at)
    values (first, 'Affiliate', first || ' Affiliate', pg_temp.ph(n), now() - interval '3 days') returning id into c;
  insert into public.customer_affiliates(customer_id, status, activated_at, referral_code)
    values (c, 'active', now(), public.generate_affiliate_referral_code()) returning id into a;
  insert into public.affiliate_accounts(auth_user_id, customer_id, affiliate_id, status) values (u, c, a, 'claimed');
  insert into fx values (key, u), ('c:' || key, c), ('a:' || key, a);
  return u;
end$$;
create function pg_temp.row_of(key text, k text default 'welcome') returns public.affiliate_whatsapp_outbox language sql as
$$ select o from public.affiliate_whatsapp_outbox o where o.auth_user_id = pg_temp.fx(key) and o.kind = k order by o.id desc limit 1 $$;
create function pg_temp.id_of(key text, k text default 'welcome') returns bigint language sql as $$ select (pg_temp.row_of(key, k)).id $$;
create function pg_temp.shares(key text) returns bigint language sql as
$$ select count(*) from public.affiliate_whatsapp_outbox where auth_user_id = pg_temp.fx(key) and kind = 'share' $$;
create function pg_temp.code(key text) returns text language sql as
$$ select referral_code from public.customer_affiliates where id = pg_temp.fx('a:' || key) $$;
-- Posted: what the dispatcher does to a row it takes (pg_net's request id made up).
create function pg_temp.post(id bigint) returns boolean language sql as
$$ select public.affiliate_whatsapp_mark_sending(id, 900000 + id) $$;
-- The share message as approved, for a code.
create function pg_temp.share_words(code text) returns text language sql as
$$ select replace((select txt from words where kind = 'share'), '/r/ENTEST00', '/r/' || code) $$;

-- ═════ W a login goes live ═════
select pg_temp.affiliate('wA', 'Testing', 1);
select pg_temp.check((select count(*) from public.affiliate_whatsapp_outbox where auth_user_id = pg_temp.fx('wA')) = 1
    and (pg_temp.row_of('wA')).status = 'queued'
    and (pg_temp.row_of('wA')).message = replace((select txt from words where kind = 'welcome'), 'Hi John,', 'Hi Testing,')
    and (pg_temp.row_of('wA')).referral_code = pg_temp.code('wA'),
  'W1 a login going live queues one welcome in the new words (no referral link), keeping the code on the row; no share yet');

-- ═════ S settle ═════
-- S1 a 2xx answer queues the share.
select pg_temp.check(pg_temp.post(pg_temp.id_of('wA')), 'S1 (the welcome is posted)');
select pg_temp.check(public.affiliate_whatsapp_settle(pg_temp.id_of('wA'), 200, false, null) = 'sent',
  'S1 a 2xx answer: the welcome is sent');
select pg_temp.check(s.kind = 'share' and s.status = 'queued' and s.skip_reason is null and s.attempts = 0
    and s.idempotency_key = 'share:' || w.idempotency_key and s.idempotency_key = 'share:welcome:' || pg_temp.fx('wA')
    and s.customer_id = w.customer_id and s.auth_user_id = w.auth_user_id and s.affiliate_id = w.affiliate_id
    and s.phone_e164 = w.phone_e164 and s.phone_e164 = pg_temp.ph(1) and s.wa_country_code = w.wa_country_code
    and s.wa_number = w.wa_number and s.first_name is not distinct from w.first_name and s.first_name = 'Testing'
    and s.referral_code = w.referral_code and s.message = pg_temp.share_words(w.referral_code)
    and s.id > w.id and s.created_at >= w.created_at and s.request_id is null and s.sent_at is null,
  'S1 its share is queued: same customer, login, affiliate, phone and name, the parent''s code, the approved words, key share:welcome:<login>: '
  || coalesce(row(s.kind, s.status, s.idempotency_key, s.phone_e164, s.first_name)::text, 'none'))
  from (select (pg_temp.row_of('wA', 'share')).*) s, (select (pg_temp.row_of('wA')).*) w;
-- S2 a non-2xx answer: none; the retry answered 2xx: one.
select pg_temp.affiliate('sB', 'Testing Two', 2);
select pg_temp.post(pg_temp.id_of('sB'));
select pg_temp.check(public.affiliate_whatsapp_settle(pg_temp.id_of('sB'), 500, false, 'Pabbly busy') = 'failed'
    and pg_temp.shares('sB') = 0 and (pg_temp.row_of('sB')).retry_after is not null,
  'S2 a non-2xx answer: failed, to be retried, and no share');
update public.affiliate_whatsapp_outbox set retry_after = now() - interval '1 second' where id = pg_temp.id_of('sB');
select pg_temp.check(pg_temp.id_of('sB') in (select t from public.affiliate_whatsapp_take(50) t), 'S2 (the retry is taken)');
select pg_temp.post(pg_temp.id_of('sB'));
select pg_temp.check(public.affiliate_whatsapp_settle(pg_temp.id_of('sB'), 202, false, null) = 'sent' and pg_temp.shares('sB') = 1,
  'S2 the retry answered 2xx (202): sent, and then one share');
-- S3 a timeout, no answer: none.
select pg_temp.affiliate('sC', 'Testing Three', 3);
select pg_temp.affiliate('sD', 'Testing Four', 4);
select pg_temp.post(pg_temp.id_of('sC')); select pg_temp.post(pg_temp.id_of('sD'));
select pg_temp.check(public.affiliate_whatsapp_settle(pg_temp.id_of('sC'), null, true, null) = 'failed'
    and public.affiliate_whatsapp_settle(pg_temp.id_of('sD'), null, null, 'no answer recorded by pg_net') = 'failed'
    and pg_temp.shares('sC') = 0 and pg_temp.shares('sD') = 0,
  'S3 a timeout, or no answer: failed for good, and no share');
-- S4 skipped, expired or still queued rows: settle changes nothing and queues none.
select pg_temp.affiliate('sE', 'Testing Five', 5);
select pg_temp.affiliate('sF', 'Testing Six', 6);
select pg_temp.affiliate('sG', 'Testing Seven', 7);
update public.affiliate_whatsapp_outbox set status = 'skipped', skip_reason = 'no_longer_active' where id = pg_temp.id_of('sE');
update public.affiliate_whatsapp_outbox set status = 'expired' where id = pg_temp.id_of('sF');
select pg_temp.check(public.affiliate_whatsapp_settle(pg_temp.id_of('sE'), 200, false, null) is null
    and public.affiliate_whatsapp_settle(pg_temp.id_of('sF'), 200, false, null) is null
    and public.affiliate_whatsapp_settle(pg_temp.id_of('sG'), 200, false, null) is null
    and pg_temp.shares('sE') + pg_temp.shares('sF') + pg_temp.shares('sG') = 0
    and (pg_temp.row_of('sE')).status = 'skipped' and (pg_temp.row_of('sF')).status = 'expired' and (pg_temp.row_of('sG')).status = 'queued',
  'S4 a skipped, an expired or a still queued welcome: settle changes nothing and queues no share');
-- S5 never a share of a share; a repeated settle gives one share.
select pg_temp.post(pg_temp.id_of('wA', 'share'));
select pg_temp.check(public.affiliate_whatsapp_settle(pg_temp.id_of('wA', 'share'), 200, false, null) = 'sent'
    and pg_temp.shares('wA') = 1
    and not exists (select 1 from public.affiliate_whatsapp_outbox where idempotency_key like 'share:share:%')
    and (select count(*) from public.affiliate_whatsapp_outbox where auth_user_id = pg_temp.fx('wA')) = 2,
  'S5 the share itself sent: no share of a share (two rows for the login in all)');
select pg_temp.check(public.affiliate_whatsapp_settle(pg_temp.id_of('wA'), 200, false, null) is null and pg_temp.shares('wA') = 1,
  'S6 the welcome settled again: nothing changes, still one share');
update public.affiliate_whatsapp_outbox set status = 'sending' where id = pg_temp.id_of('wA');
select pg_temp.check(public.affiliate_whatsapp_settle(pg_temp.id_of('wA'), 200, false, null) = 'sent' and pg_temp.shares('wA') = 1
    and (pg_temp.row_of('wA', 'share')).status = 'sent',
  'S6 even forced back to sending and settled 2xx again: the key holds, still one share, the sent one untouched');
-- S7 the one-message words from before 537: no share (welcome and reactivated).
select pg_temp.affiliate('sH', 'Testing Eight', 8);
create temp table old394 as select
  'Hi Testing, welcome to the Energia affiliate programme! Your account is now active.' || E'\n\n'
  || 'Log in: https://rev-22-energia-inventory-system.vercel.app/affiliate/login' || E'\n'
  || 'Forgot your password? https://rev-22-energia-inventory-system.vercel.app/affiliate/forgot-password' || E'\n\n'
  || 'Your referral link to share with friends and family: https://rev-22-energia-inventory-system.vercel.app/r/' || pg_temp.code('sH') || E'\n\n'
  || 'In your portal you can see your referrals, earnings and payouts.' || E'\n\n' || 'Rev 22 Global Energia' as w;
update public.affiliate_whatsapp_outbox set message = (select w from old394) where id = pg_temp.id_of('sH');
insert into public.affiliate_whatsapp_outbox (kind, idempotency_key, customer_id, auth_user_id, affiliate_id, phone_e164,
    wa_country_code, wa_number, first_name, referral_code, message, status)
select 'reactivated', 'reactivated:T537-old', customer_id, auth_user_id, affiliate_id, phone_e164, wa_country_code, wa_number,
       first_name, referral_code, replace((select w from old394), 'welcome to the Energia affiliate programme! Your account is now active.',
                                          'your Energia affiliate account is active again.'), 'queued'
  from public.affiliate_whatsapp_outbox where id = pg_temp.id_of('sH');
select pg_temp.post(pg_temp.id_of('sH')); select pg_temp.post(pg_temp.id_of('sH', 'reactivated'));
select pg_temp.check(public.affiliate_whatsapp_settle(pg_temp.id_of('sH'), 200, false, null) = 'sent'
    and public.affiliate_whatsapp_settle(pg_temp.id_of('sH', 'reactivated'), 200, false, null) = 'sent'
    and pg_temp.shares('sH') = 0,
  'S7 a welcome and a reactivation in the one-message words (the referral link in them, composed before 537): sent, and no share');
-- S8 a reactivation in the new words: its own share, keyed by it.
select public.affiliate_whatsapp_enqueue('reactivated', pg_temp.fx('sG'), pg_temp.fx('c:sG'), pg_temp.fx('a:sG'), 'reactivated:T537-new');
select pg_temp.post(pg_temp.id_of('sG', 'reactivated'));
select pg_temp.check((pg_temp.row_of('sG', 'reactivated')).message like 'Hi Testing Seven, your Energia affiliate account is active again.%'
    and public.affiliate_whatsapp_settle(pg_temp.id_of('sG', 'reactivated'), 200, false, null) = 'sent'
    and (pg_temp.row_of('sG', 'share')).idempotency_key = 'share:reactivated:T537-new'
    and (pg_temp.row_of('sG', 'share')).status = 'queued'
    and (pg_temp.row_of('sG', 'share')).message = pg_temp.share_words(pg_temp.code('sG')),
  'S8 a reactivation sent: its share is queued, key share:reactivated:<its key>');
-- S9 a share that cannot be composed: kept skipped.
select pg_temp.affiliate('sJ', 'Testing Nine', 9);
update public.affiliate_whatsapp_outbox set referral_code = null where id = pg_temp.id_of('sJ');
select pg_temp.post(pg_temp.id_of('sJ'));
select pg_temp.check(public.affiliate_whatsapp_settle(pg_temp.id_of('sJ'), 200, false, null) = 'sent'
    and (pg_temp.row_of('sJ', 'share')).status = 'skipped' and (pg_temp.row_of('sJ', 'share')).skip_reason = 'no_referral_code'
    and (pg_temp.row_of('sJ', 'share')).message is null,
  'S9 a parent with no referral code: sent, and its share kept skipped (no_referral_code), nothing to post');
-- S10 an error while queueing: kept failed (enqueue_error); the 'sent' stands.
create temp table saved_message as
  select pg_get_functiondef('public.affiliate_whatsapp_message(text,text,text,text)'::regprocedure) d;
create or replace function public.affiliate_whatsapp_message(p_kind text, p_first_name text, p_app_url text, p_referral_code text)
returns text language plpgsql immutable set search_path = public as
$fn$ begin if p_kind = 'share' then raise exception 'T537 the share words broke'; end if; return 'x'; end $fn$;
select pg_temp.affiliate('sK', 'Testing Ten', 10);
update public.affiliate_whatsapp_outbox set message = 'T537 first message' where id = pg_temp.id_of('sK');
select pg_temp.post(pg_temp.id_of('sK'));
select pg_temp.check(public.affiliate_whatsapp_settle(pg_temp.id_of('sK'), 200, false, null) = 'sent'
    and (pg_temp.row_of('sK')).status = 'sent'
    and (pg_temp.row_of('sK', 'share')).status = 'failed' and (pg_temp.row_of('sK', 'share')).skip_reason = 'enqueue_error'
    and (pg_temp.row_of('sK', 'share')).last_error like '%T537 the share words broke%'
    and (pg_temp.row_of('sK', 'share')).retry_after is null and (pg_temp.row_of('sK', 'share')).message is null,
  'S10 composing the share fails: the welcome stays sent; the share is kept failed (enqueue_error), never to be posted');
select pg_temp.check(pg_temp.id_of('sK', 'share') not in (select t from public.affiliate_whatsapp_take(50) t),
  'S10 take never hands that failed share over');
-- Even the failed row cannot be written (a stand-in trigger refuses every share): a warning only.
create function pg_temp.no_share() returns trigger language plpgsql as
$$ begin if new.kind = 'share' then raise exception 'T537 no share rows'; end if; return new; end $$;
create trigger t537_no_share before insert on public.affiliate_whatsapp_outbox for each row execute function pg_temp.no_share();
select pg_temp.affiliate('sL', 'Testing Eleven', 11);
update public.affiliate_whatsapp_outbox set message = 'T537 first message' where id = pg_temp.id_of('sL');
select pg_temp.post(pg_temp.id_of('sL'));
select pg_temp.check(public.affiliate_whatsapp_settle(pg_temp.id_of('sL'), 200, false, null) = 'sent'
    and (pg_temp.row_of('sL')).status = 'sent' and pg_temp.shares('sL') = 0,
  'S10 not even the failed row can be written: a warning only (printed above), and the welcome stays sent');
drop trigger t537_no_share on public.affiliate_whatsapp_outbox;
do $$ begin execute (select d from saved_message); end $$;
select pg_temp.check(pg_temp.md5of('public.affiliate_whatsapp_message(text,text,text,text)') = '9b7caba24a3cec3e7dc66becfae7ed4b',
  'S10 (the message function put back)');

-- ═════ D the dispatcher's steps, pg_net answering, nothing posted ═════
delete from public.affiliate_whatsapp_outbox;
select pg_temp.affiliate('dA', 'Testing Dee', 20);
create temp table took1 as select t id from public.affiliate_whatsapp_take(10) t;
select pg_temp.check((select array_agg(id) from took1) = array[pg_temp.id_of('dA')],
  'D1 the first run takes the welcome alone');
select pg_temp.post(id) from took1;
create temp table had_net as select to_regclass('net._http_response') is not null as y;
select y as has_net from had_net \gset
\if :has_net
insert into net._http_response (id, status_code, content_type, headers, content, timed_out, error_msg, created)
values (900000 + pg_temp.id_of('dA'), 200, 'text/plain', '{}'::jsonb, 'Response Accepted', false, null, now());
select pg_temp.check(public.affiliate_whatsapp_reconcile() = 1 and (pg_temp.row_of('dA')).status = 'sent',
  'D2 the next run: reconcile reads pg_net''s 200 and settles the welcome as sent');
\else
select pg_temp.check(public.affiliate_whatsapp_settle(pg_temp.id_of('dA'), 200, false, null) = 'sent',
  'D2 (no pg_net here) the welcome is settled 2xx as reconcile would');
\endif
create temp table took2 as select t id from public.affiliate_whatsapp_take(10) t;
select pg_temp.check((select array_agg(id) from took2) = array[pg_temp.id_of('dA', 'share')]
    and pg_temp.id_of('dA', 'share') > pg_temp.id_of('dA'),
  'D3 the same run''s take then hands over the share, and only it: it goes after the first was taken by Pabbly');
select pg_temp.check((public.affiliate_whatsapp_payload(pg_temp.id_of('dA', 'share'), 'T537-secret-0123456789')) - 'idempotency_key' - 'message'
      = jsonb_build_object('secret', 'T537-secret-0123456789', 'kind', 'share', 'first_name', 'Testing Dee',
                           'phone_e164', pg_temp.ph(20), 'wa_country_code', '61', 'wa_number', '491570720')
    and public.affiliate_whatsapp_payload(pg_temp.id_of('dA', 'share'), 'x')->>'message' = pg_temp.share_words(pg_temp.code('dA')),
  'D4 the share''s body: the same keys as before, kind ''share'', the message with the referral link');
select pg_temp.post(id) from took2;
\if :has_net
insert into net._http_response (id, status_code, content_type, headers, content, timed_out, error_msg, created)
values (900000 + pg_temp.id_of('dA', 'share'), 200, 'text/plain', '{}'::jsonb, 'Response Accepted', false, null, now());
select pg_temp.check(public.affiliate_whatsapp_reconcile() = 1 and (pg_temp.row_of('dA', 'share')).status = 'sent'
    and not exists (select 1 from public.affiliate_whatsapp_take(10)),
  'D5 the share answered 200: sent, and nothing more to take');
\else
select pg_temp.check(public.affiliate_whatsapp_settle(pg_temp.id_of('dA', 'share'), 200, false, null) = 'sent'
    and not exists (select 1 from public.affiliate_whatsapp_take(10)),
  'D5 the share settled 2xx: sent, and nothing more to take');
\endif

-- ═════ A take with a waiting share ═════
delete from public.affiliate_whatsapp_outbox;
select pg_temp.affiliate('aA', 'Testing Ay', 30);
select pg_temp.affiliate('aB', 'Testing Bee', 31);
select pg_temp.affiliate('aC', 'Testing Cee', 32);
select pg_temp.post(pg_temp.id_of(k)) from unnest(array['aA', 'aB', 'aC']) k;
select public.affiliate_whatsapp_settle(pg_temp.id_of(k), 200, false, null) from unnest(array['aA', 'aB', 'aC']) k;
update public.customer_affiliates set manually_suspended = true where id = pg_temp.fx('a:aA');
update public.affiliate_whatsapp_outbox set created_at = now() - interval '49 hours' where id = pg_temp.id_of('aB', 'share');
-- aC: suspended and reactivated within the minute after the welcome went (its share still waits).
update public.customer_affiliates set manually_suspended = true where id = pg_temp.fx('a:aC');
update public.customer_affiliates set manually_suspended = false where id = pg_temp.fx('a:aC');
create temp table took3 as select t id from public.affiliate_whatsapp_take(10) t;
select pg_temp.check((pg_temp.row_of('aA', 'share')).status = 'skipped' and (pg_temp.row_of('aA', 'share')).skip_reason = 'no_longer_active'
    and pg_temp.id_of('aA', 'share') not in (select id from took3),
  'A1 the affiliate suspended while the share waits: it is skipped (no_longer_active)');
select pg_temp.check((pg_temp.row_of('aB', 'share')).status = 'expired' and pg_temp.id_of('aB', 'share') not in (select id from took3),
  'A2 a share waiting more than 48 hours expires');
select pg_temp.check((pg_temp.row_of('aC', 'share')).status = 'queued' and pg_temp.id_of('aC', 'share') in (select id from took3)
    and (pg_temp.row_of('aC', 'reactivated')).status = 'skipped'
    and (pg_temp.row_of('aC', 'reactivated')).skip_reason = 'earlier_message_pending'
    and (select array_agg(id) from took3) = array[pg_temp.id_of('aC', 'share')],
  'A3 a share is never skipped as earlier_message_pending; a reactivation queued behind it is (the welcome with the links went a minute before)');

-- ═════ L the 30 welcomes a day count welcomes only ═════
delete from public.affiliate_whatsapp_outbox;
insert into public.affiliate_whatsapp_outbox (kind, idempotency_key, phone_e164, wa_country_code, wa_number, message, status, created_at)
select 'welcome', 'T537-fill-' || i, pg_temp.ph(99), '61', '491570799', 'T537', 'sent', now() - interval '1 hour' from generate_series(1, 29) i;
insert into public.affiliate_whatsapp_outbox (kind, idempotency_key, phone_e164, wa_country_code, wa_number, message, status, created_at)
select 'share', 'share:T537-fill-' || i, pg_temp.ph(99), '61', '491570799', 'T537',
       (array['queued', 'sending', 'sent', 'failed'])[1 + i % 4], now() - interval '1 hour' from generate_series(1, 40) i;
select pg_temp.affiliate('l30', 'Testing Thirty', 40);
select pg_temp.affiliate('l31', 'Testing Thirtyone', 41);
select pg_temp.check((pg_temp.row_of('l30')).status = 'queued' and (pg_temp.row_of('l31')).skip_reason = 'daily_limit',
  'L1 29 welcomes and 40 shares in 24 hours: the 30th welcome is queued, the 31st kept skipped (daily_limit): shares are not counted');
select pg_temp.post(pg_temp.id_of('l30'));
select pg_temp.check(public.affiliate_whatsapp_settle(pg_temp.id_of('l30'), 200, false, null) = 'sent'
    and (pg_temp.row_of('l30', 'share')).status = 'queued',
  'L2 and a share is not limited by it: queued after the 30th welcome was sent');

-- ═════ G grants ═════
create function pg_temp.acl(f text) returns text language sql as
$$ select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure(f) $$;
select pg_temp.check(pg_temp.acl('public.affiliate_whatsapp_message(text,text,text,text)') = 'postgres=X/postgres,service_role=X/postgres'
    and pg_temp.acl('public.affiliate_whatsapp_settle(bigint,integer,boolean,text)') = 'postgres=X/postgres,service_role=X/postgres'
    and not has_function_privilege('anon', 'public.affiliate_whatsapp_message(text,text,text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.affiliate_whatsapp_message(text,text,text,text)', 'execute')
    and not has_function_privilege('anon', 'public.affiliate_whatsapp_settle(bigint,integer,boolean,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.affiliate_whatsapp_settle(bigint,integer,boolean,text)', 'execute')
    and (select p.prosecdef and p.proconfig = '{search_path=public}' from pg_proc p
          where p.oid = 'public.affiliate_whatsapp_settle(bigint,integer,boolean,text)'::regprocedure)
    and (select not p.prosecdef and p.provolatile = 'i' and p.proconfig = '{search_path=public}' from pg_proc p
          where p.oid = 'public.affiliate_whatsapp_message(text,text,text,text)'::regprocedure),
  'G1 the two functions: the service role''s alone, as before; settle runs as the owner, message immutable, both with search_path public');
select pg_temp.check(not has_table_privilege('anon', 'public.affiliate_whatsapp_outbox', 'select,insert,update,delete,truncate,references,trigger')
    and not has_table_privilege('authenticated', 'public.affiliate_whatsapp_outbox', 'select,insert,update,delete,truncate,references,trigger')
    and (select relrowsecurity from pg_class where oid = 'public.affiliate_whatsapp_outbox'::regclass)
    and (select relacl::text from pg_class where oid = 'public.affiliate_whatsapp_outbox'::regclass)
        = (select relacl::text from pg_class where oid = 'public.affiliate_whatsapp_settings'::regclass),
  'G2 the outbox: no client role reaches it, row level security on, its grants as the settings table''s');

-- ═════ U undo-537 ═════
-- Rows now: welcomes and shares (some waiting). The undo with share rows there.
create temp table before_undo as select count(*) filter (where kind = 'share') n_share,
  count(*) filter (where kind = 'share' and (status = 'queued' or (status = 'failed' and retry_after is not null))) n_waiting
  from public.affiliate_whatsapp_outbox;
update public.affiliate_whatsapp_outbox set retry_after = now() + interval '5 minutes'
 where kind = 'share' and status = 'failed' and idempotency_key = 'share:T537-fill-3';
\ir ../undo-537.sql
select pg_temp.check(pg_temp.md5of('public.affiliate_whatsapp_message(text,text,text,text)') = '6cab1d437121fb0942f90dd7ec7c5310'
    and pg_temp.md5of('public.affiliate_whatsapp_settle(bigint,integer,boolean,text)') = '950a44ad565eada10199a3ccfc0e20bb'
    and pg_temp.acl('public.affiliate_whatsapp_message(text,text,text,text)') = 'postgres=X/postgres,service_role=X/postgres'
    and pg_temp.acl('public.affiliate_whatsapp_settle(bigint,integer,boolean,text)') = 'postgres=X/postgres,service_role=X/postgres'
    and obj_description('public.affiliate_whatsapp_outbox'::regclass, 'pg_class')
        = '394: one row per affiliate login WhatsApp (welcome, reactivated) and what became of it.',
  'U1 the undo puts 394''s message and settle back exactly (md5s, grants) and the table comment');
select pg_temp.check((select count(*) from public.affiliate_whatsapp_outbox where kind = 'share') = (select n_share from before_undo)
    and not exists (select 1 from public.affiliate_whatsapp_outbox where kind = 'share'
                     and (status = 'queued' or (status = 'failed' and retry_after is not null)))
    and (select count(*) from public.affiliate_whatsapp_outbox where skip_reason = 'undo_537') >= 1
    and pg_temp.kindcheck() like '%share%' and pg_temp.shape() = '17e02f51d286cdfefb1be873d199a8b7',
  'U2 with share rows there: kept as the record, the waiting ones skipped (undo_537), the kind check keeps ''share''');
-- (L's filler welcomes out of the way, so 531's 30 a day does not keep this one.)
delete from public.affiliate_whatsapp_outbox where kind = 'welcome' and idempotency_key like 'T537-fill-%';
select pg_temp.affiliate('uA', 'Testing Undo', 50);
select pg_temp.post(pg_temp.id_of('uA'));
select pg_temp.check((pg_temp.row_of('uA')).message like '%/r/' || pg_temp.code('uA') || '%'
    and public.affiliate_whatsapp_settle(pg_temp.id_of('uA'), 200, false, null) = 'sent' and pg_temp.shares('uA') = 0,
  'U3 after the undo: one message with the referral link, and no share');
savepoint u4;
\set ON_ERROR_STOP off
\ir ../undo-537.sql
\set u4_err :ERROR
\set ON_ERROR_STOP on
rollback to savepoint u4;
select pg_temp.check(:'u4_err' = 'true' and :'LAST_ERROR_MESSAGE' like 'undo-537: public.affiliate_whatsapp_message(text,text,text,text) is not 537''s version%',
  'U4 the undo refuses where 537 is not in: ' || :'LAST_ERROR_MESSAGE');
\ir ../../../supabase/537_the_affiliate_whatsapp_goes_out_as_two_messages.sql
select pg_temp.check(pg_temp.md5of('public.affiliate_whatsapp_message(text,text,text,text)') = '9b7caba24a3cec3e7dc66becfae7ed4b'
    and pg_temp.md5of('public.affiliate_whatsapp_settle(bigint,integer,boolean,text)') = 'b19c07bc3735a291e29de393ca1a57f8'
    and pg_temp.shape() = '17e02f51d286cdfefb1be873d199a8b7',
  'U5 537 again over that state (394''s functions, the check keeping ''share''): installs, leaving the check alone');
delete from public.affiliate_whatsapp_outbox where kind = 'share';
\ir ../undo-537.sql
select pg_temp.check(pg_temp.kindcheck() = 'CHECK ((kind = ANY (ARRAY[''welcome''::text, ''reactivated''::text])))'
    and pg_temp.shape() = '93b1b08d815a1aa2985f20d7b792b15a'
    and pg_temp.md5of('public.affiliate_whatsapp_message(text,text,text,text)') = '6cab1d437121fb0942f90dd7ec7c5310'
    and pg_temp.md5of('public.affiliate_whatsapp_settle(bigint,integer,boolean,text)') = '950a44ad565eada10199a3ccfc0e20bb'
    and not exists (select * from pg_temp.fp() where fn not in (select fn from fp1x) except select * from fp0)
    and not exists (select * from fp0 where fn not in (select fn from fp1x) except select * from pg_temp.fp()),
  'U6 with no share row: the undo also puts 394''s kind check and shape back; every public function as before 537');
\ir ../../../supabase/537_the_affiliate_whatsapp_goes_out_as_two_messages.sql
select pg_temp.check(pg_temp.shape() = '17e02f51d286cdfefb1be873d199a8b7'
    and pg_temp.md5of('public.affiliate_whatsapp_settle(bigint,integer,boolean,text)') = 'b19c07bc3735a291e29de393ca1a57f8',
  'U7 and 537 again from there is as the first time');
-- undo-531 refuses while 537 is in (it would leave 537's words and settle on 394's enqueue, which
-- no script gets out of; the security audit, 24 Nov 2026); undo-537 first, then undo-531, works.
savepoint u8;
\set ON_ERROR_STOP off
\ir ../../affiliate-signup/undo-531.sql
\set u8_err :ERROR
\set ON_ERROR_STOP on
rollback to savepoint u8;
select pg_temp.check(:'u8_err' = 'true' and :'LAST_ERROR_MESSAGE' like 'undo-531: affiliate_whatsapp_message or affiliate_whatsapp_settle is not 394''s version (537 is in, or one of them was changed by hand)%'
    and pg_temp.md5of('public.affiliate_whatsapp_enqueue(text,uuid,uuid,uuid,text)') = '1b52d84e2842ef7709b86e2cbd03718d'
    and pg_temp.md5of('public.affiliate_whatsapp_settle(bigint,integer,boolean,text)') = 'b19c07bc3735a291e29de393ca1a57f8',
  'U8 undo-531 refuses while 537 is in, changing nothing: ' || :'LAST_ERROR_MESSAGE');
delete from public.affiliate_whatsapp_outbox where kind = 'share';
\ir ../undo-537.sql
\ir ../../affiliate-signup/undo-531.sql
select pg_temp.check(pg_temp.md5of('public.affiliate_whatsapp_enqueue(text,uuid,uuid,uuid,text)') = 'c88ad74525019c20254a6927f4a802a3'
    and pg_temp.md5of('public.affiliate_whatsapp_message(text,text,text,text)') = '6cab1d437121fb0942f90dd7ec7c5310'
    and pg_temp.md5of('public.affiliate_whatsapp_settle(bigint,integer,boolean,text)') = '950a44ad565eada10199a3ccfc0e20bb',
  'U9 the right order works: undo-537, then undo-531, leaves 394''s three WhatsApp functions');

-- ═════ Result ═════
do $$
declare n int; t int; msgs text;
begin
  select count(*), string_agg(msg, E'\n') into n, msgs from failed;
  select count(*) into t from ran;
  if n > 0 then raise exception '% of % two-message check(s) failed:%', n, t, E'\n' || msgs; end if;
  raise notice 'ALL % two-message checks passed', t;
end $$;
rollback;
