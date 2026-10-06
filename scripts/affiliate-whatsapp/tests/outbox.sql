-- An affiliate whose login goes live is sent their login link on WhatsApp (394).
--
--   M  The migration: nothing is queued for logins that already exist; a
--      second run changes nothing; a table, a function or a relied-on
--      function that is not the tested one makes it refuse.
--   W  A self sign-up that goes live queues exactly one 'welcome', with the
--      phone (E.164, WhatsApp country code and number), the first name, the
--      app's login, forgot-password and referral links, and the affiliate's
--      code. Asking again, or linking the same login again, queues nothing.
--   R  Staff resolving a claim queues the welcome too; the first name comes
--      from the customer's name without the notes in brackets.
--   S  A suspended affiliate at that moment: kept as 'skipped'
--      (affiliate_suspended), nothing to send.
--   P  No usable phone: 'skipped' (no_phone). A legacy 8-digit phone becomes
--      +65; one the phone policy finds ambiguous (Singapore or Malaysia) is
--      not guessed, and like an unusable one falls back to the sign-up phone.
--   A  Reactivating a suspended affiliate with a login queues one
--      'reactivated'; reactivating again, or one without a login, does not.
--   F  A failure while queueing never stops the sign-up: it is kept as
--      'failed' (enqueue_error), or, when even that cannot be written, only
--      warned about.
--   D  The dispatcher does nothing while off. What it posts and how answers
--      settle: 2xx sent; another status code retried after 5 minutes, at
--      most 3 posts; a timeout or no answer failed for good; waiting over 48
--      hours expired; a login no longer linked skipped. Tested through the
--      functions it is made of, and end to end against a stand-in for pg_net
--      where pg_net is not installed. A reactivation while the welcome (or an
--      earlier reactivation) still waits or is being posted is skipped
--      (earlier_message_pending); after the welcome expired it goes out.
--   N  The greeting uses a name only if it looks like one (letters, spaces,
--      an apostrophe or a hyphen, at most 30 characters): a sign-up name with
--      a link, a phone number or 5,000 characters is passed over for the
--      customer's, else "Hi there".
--   G  No client role reaches the tables or the functions.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. It installs 378, 379 and 392 first (each leaves
-- itself alone where it is already applied), then 394 twice. Every name,
-- phone, email and link below is invented; the phones are +65 9139 21xx, one
-- +65 8139 2105 and one +60 12-345 6789.
--
-- Three refusals are provoked on purpose (G1-G3 under M): psql prints their
-- "ERROR:  394: ..." lines, and the checks right after them say whether each
-- refusal was the expected one.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';

\ir ../../../supabase/378_staff_affiliate_claims.sql
\ir ../../../supabase/379_reject_protects_the_customer.sql
\ir ../../../supabase/392_referral_booking_names_the_affiliate.sql

create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;

-- The bodies this was run against: production's on 6 Oct 2026 (394's header).
do $$
begin
  raise notice 'NOTE  complete_affiliate_onboarding %, resolve_affiliate_account_claim %, reactivate_affiliate % (production 6 Oct 2026: 9ff0fd28…, 29a68a4d…, 733943ad…)',
    md5(pg_get_functiondef('public.complete_affiliate_onboarding(text,text,text,boolean)'::regprocedure)),
    md5(pg_get_functiondef('public.resolve_affiliate_account_claim(uuid,uuid,text)'::regprocedure)),
    md5(pg_get_functiondef('public.reactivate_affiliate(uuid)'::regprocedure));
end $$;
select pg_temp.check(not exists (select 1 from public.customers
                                  where public.normalize_customer_phone(phone) like '+65913921__'
                                     or public.normalize_customer_phone(phone) = '+6581392105'
                                     or phone in ('91392111', '81392105')),
  'M0 no customer uses the test phones +65 9139 21xx or 8139 2105 (the checks below assume so)');
-- An affiliate who already has a login before 394.
do $$
declare u uuid := gen_random_uuid(); c uuid; a uuid;
begin
  insert into fx values ('uPre', u);
  insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
    values (u, 'wa394-pre@sig.invalid', now(), jsonb_build_object('first_name', 'Pat', 'phone', '+6591392100'));
  insert into customers(full_name, phone) values ('Pat Early', '+6591392100') returning id into c;
  insert into customer_affiliates(customer_id, status, activated_at, referral_code)
    values (c, 'active', now(), generate_affiliate_referral_code()) returning id into a;
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status) values (u, c, a, 'claimed');
end $$;

-- ═════ M: the migration ═════
\ir ../../../supabase/394_affiliate_whatsapp_login_link.sql

select pg_temp.check((select count(*) from public.affiliate_whatsapp_outbox) = 0,
  'M1 nothing is queued for the ' || (select count(*) from public.affiliate_accounts) || ' logins that already exist (no backfill)');
select pg_temp.check((select count(*) = 1 and bool_and(not enabled and webhook_url is null and secret is null
                             and app_url = 'https://rev-22-energia-inventory-system.vercel.app')
                        from public.affiliate_whatsapp_settings),
  'M1 one settings row, off, with no webhook address or secret');

-- Everything 394 makes, as one text.
create function pg_temp.snapshot() returns text language plpgsql as
$$declare v text; v_cron text;
begin
  select string_agg(x, E'\n' order by x) into v from (
    select 'fn ' || p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) || ' ' || coalesce(p.proacl::text, '') as x
      from pg_proc p where p.pronamespace = 'public'::regnamespace
       and (p.proname like 'affiliate_whatsapp%' or p.proname like 'trg_affiliate_whatsapp%' or p.proname = 'ads_wa_country_code')
    union all
    select 'rel ' || c.oid::regclass::text || ' ' || coalesce(c.relacl::text, '') || ' ' || c.relrowsecurity
           || ' ' || coalesce(obj_description(c.oid, 'pg_class'), '')
      from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname like 'affiliate_whatsapp%'
    union all
    select 'col ' || a.attrelid::regclass::text || ' ' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
      from pg_attribute a where a.attrelid in ('public.affiliate_whatsapp_settings'::regclass, 'public.affiliate_whatsapp_outbox'::regclass)
       and a.attnum > 0 and not a.attisdropped
    union all
    select 'con ' || c.conname || ' ' || pg_get_constraintdef(c.oid)
      from pg_constraint c where c.conrelid in ('public.affiliate_whatsapp_settings'::regclass, 'public.affiliate_whatsapp_outbox'::regclass)
    union all
    select 'trg ' || pg_get_triggerdef(t.oid) || ' ' || t.tgenabled::text from pg_trigger t where t.tgname like 'trg_affiliate_whatsapp%'
    union all
    select 'set ' || s::text from public.affiliate_whatsapp_settings s
    union all
    select 'rows ' || count(*) from public.affiliate_whatsapp_outbox) s;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$select string_agg(jobname || ' ' || schedule || ' ' || command || ' ' || active, ';')
                 from cron.job where jobname = 'affiliate-whatsapp-dispatch'$q$ into strict v_cron;
    v := v || E'\ncron ' || coalesce(v_cron, 'none');
  end if;
  return v;
end$$;
create temp table snap as select pg_temp.snapshot() s;
-- An Owner fills in the settings; a re-run must keep them.
update public.affiliate_whatsapp_settings set webhook_url = 'https://hooks.example.invalid/wa', secret = 'wa-test-secret-0123456789';
create temp table snap2 as select pg_temp.snapshot() s;

\ir ../../../supabase/394_affiliate_whatsapp_login_link.sql

select pg_temp.check(pg_temp.snapshot() = (select s from snap2),
  'M2 a second run changes nothing (functions, grants, tables, triggers, cron, and the settings an Owner filled in)');
update public.affiliate_whatsapp_settings set webhook_url = null, secret = null;
select pg_temp.check(pg_temp.snapshot() = (select s from snap), 'M2 (the settings put back for the rest of the file)');

-- G1-G3: refusals, each undone by its savepoint.
savepoint g1;
alter table public.affiliate_whatsapp_outbox add column note text;
\set ON_ERROR_STOP off
\ir ../../../supabase/394_affiliate_whatsapp_login_link.sql
\set g1_err :ERROR
\set ON_ERROR_STOP on
rollback to savepoint g1;
select pg_temp.check(:'g1_err' = 'true' and :'LAST_ERROR_MESSAGE' like '394: a different public.affiliate_whatsapp_outbox already exists%',
  'M3 a re-run refuses an outbox of another shape: ' || :'LAST_ERROR_MESSAGE');

savepoint g2;
create or replace function public.affiliate_whatsapp_message(p_kind text, p_first_name text, p_app_url text, p_referral_code text)
returns text language sql immutable set search_path = public as $fn$ select 'other words' $fn$;
\set ON_ERROR_STOP off
\ir ../../../supabase/394_affiliate_whatsapp_login_link.sql
\set g2_err :ERROR
\set ON_ERROR_STOP on
rollback to savepoint g2;
select pg_temp.check(:'g2_err' = 'true' and :'LAST_ERROR_MESSAGE' like '394: a different public.affiliate_whatsapp_message(text,text,text,text) already exists%',
  'M3 a re-run refuses a message function it did not write: ' || :'LAST_ERROR_MESSAGE');

savepoint g3;
create or replace function public.affiliate_calendar_label(p_full_name text) returns text
language sql immutable set search_path = public as $fn$ select p_full_name $fn$;
\set ON_ERROR_STOP off
\ir ../../../supabase/394_affiliate_whatsapp_login_link.sql
\set g3_err :ERROR
\set ON_ERROR_STOP on
rollback to savepoint g3;
select pg_temp.check(:'g3_err' = 'true' and :'LAST_ERROR_MESSAGE' like '394: public.affiliate_calendar_label(text) is not the version this was tested against%',
  'M3 it refuses when a function it relies on is not the tested one: ' || :'LAST_ERROR_MESSAGE');
select pg_temp.check(pg_temp.snapshot() = (select s from snap), 'M3 the refused runs left everything as it was');

select pg_temp.check(md5(pg_get_functiondef(to_regprocedure(f))) = m, 'M4 ' || f || ' is the version 394 records')
  from (values
    ('public.affiliate_whatsapp_message(text,text,text,text)',        '6cab1d437121fb0942f90dd7ec7c5310'),
    ('public.affiliate_whatsapp_enqueue(text,uuid,uuid,uuid,text)',   'c88ad74525019c20254a6927f4a802a3'),
    ('public.trg_affiliate_whatsapp_welcome()',                       '248067d2763aff9e825d7d42eebb833e'),
    ('public.trg_affiliate_whatsapp_reactivated()',                   'b44622c610e11e90fff0ffe078d2bf75'),
    ('public.affiliate_whatsapp_take(integer)',                       'f3a07d2367e23dff74164dbe755e321f'),
    ('public.affiliate_whatsapp_payload(bigint,text)',                '63b8112911fe477a718ab63083afd840'),
    ('public.affiliate_whatsapp_mark_sending(bigint,bigint)',         'c8e6a1aa0e486279f9ee86c801af4808'),
    ('public.affiliate_whatsapp_settle(bigint,integer,boolean,text)', '950a44ad565eada10199a3ccfc0e20bb'),
    ('public.affiliate_whatsapp_reconcile()',                         'ca72f063b7eee883ba577fa679a2f3e6'),
    ('public.affiliate_whatsapp_dispatch(integer)',                   'bfeefed42b32c7b68cf8f39a82a4b59a'),
    ('public.ads_wa_country_code(text)',                              '51abbed9eb0f93a58da238d3ec155b68')) x(f, m);

-- ═════ Helpers ═════
-- The message as the Owner's draft words it, written out here on its own.
create function pg_temp.expected(kind text, first text, code text) returns text language sql as
$$ select case kind
     when 'welcome' then 'Hi ' || first || ', welcome to the Energia affiliate programme! Your account is now active.'
     else 'Hi ' || first || ', your Energia affiliate account is active again.' end
   || E'\n\nLog in: https://rev-22-energia-inventory-system.vercel.app/affiliate/login'
   || E'\nForgot your password? https://rev-22-energia-inventory-system.vercel.app/affiliate/forgot-password'
   || E'\n\nYour referral link to share with friends and family: https://rev-22-energia-inventory-system.vercel.app/r/' || code
   || E'\n\nIn your portal you can see your referrals, earnings and payouts.'
   || E'\n\nRev 22 Global Energia' $$;
create function pg_temp.code(cust text) returns text language sql as
$$ select referral_code from public.customer_affiliates where customer_id = pg_temp.fx(cust) $$;
create function pg_temp.rows_for(login text) returns bigint language sql as
$$ select count(*) from public.affiliate_whatsapp_outbox where auth_user_id = pg_temp.fx(login) $$;
create function pg_temp.row_of(login text, k text default 'welcome') returns public.affiliate_whatsapp_outbox language sql as
$$ select o from public.affiliate_whatsapp_outbox o where o.auth_user_id = pg_temp.fx(login) and o.kind = k order by o.id desc limit 1 $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true) $$;
create function pg_temp.signup(login text) returns text language plpgsql as
$$declare r jsonb; begin
  perform pg_temp.as_user(login);
  execute 'set local role authenticated';
  r := public.complete_affiliate_onboarding('', '', '', true);
  execute 'reset role';
  return coalesce(r->>'status', '?');
exception when others then execute 'reset role'; return 'ERROR: ' || sqlerrm;
end$$;
create function pg_temp.resolve(staff text, login text, cust text) returns text language plpgsql as
$$declare r jsonb; v_claim uuid; v_cust uuid := pg_temp.fx(cust); begin
  insert into public.affiliate_account_claims (auth_user_id, entered_phone, verified_email, candidate_customer_id, entered_name)
  select pg_temp.fx(login), c.phone, u.email, c.id, c.full_name
    from public.customers c, auth.users u where c.id = v_cust and u.id = pg_temp.fx(login)
  returning id into v_claim;
  perform pg_temp.as_user(staff);
  execute 'set local role authenticated';
  r := public.resolve_affiliate_account_claim(v_claim, v_cust, 'Checked the phone with the person');
  execute 'reset role';
  return coalesce(r->>'ok', '?') || coalesce(' suspended=' || (r->>'suspended'), '');
exception when others then execute 'reset role'; return 'ERROR: ' || sqlerrm;
end$$;
create function pg_temp.as_owner(q text) returns text language plpgsql as
$$begin
  perform pg_temp.as_user('own');
  execute 'set local role authenticated';
  execute q;
  execute 'reset role';
  return 'ok';
exception when others then execute 'reset role'; return 'ERROR: ' || sqlerrm;
end$$;

-- ═════ Fixtures ═════
do $$
declare k text; u uuid; c uuid;
begin
  foreach k in array array['own', 'stf', 'uA', 'uB', 'uC', 'uD', 'uE', 'uE2', 'uF', 'uG', 'uH', 'uJ', 'uK',
                            'uN', 'uO', 'uQ', 'uR', 'uL', 'uM'] loop
    u := gen_random_uuid(); insert into fx values (k, u);
    insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
      values (u, 'wa394-' || lower(k) || '@sig.invalid', now(), '{}'::jsonb);
  end loop;
  insert into profiles(id, full_name, email, role) values
    (pg_temp.fx('own'), 'WA Owner', 'wa394-own@sig.invalid', 'owner'),
    (pg_temp.fx('stf'), 'WA Staff', 'wa394-stf@sig.invalid', 'staff');
  -- What each person typed at sign-up (the account's own copy).
  update auth.users set raw_user_meta_data = jsonb_build_object('first_name', 'Mei', 'last_name', 'Tan', 'phone', '+6591392101')
   where id = pg_temp.fx('uA');
  update auth.users set raw_user_meta_data = jsonb_build_object('first_name', 'Sue', 'phone', '+6591392103')
   where id = pg_temp.fx('uC');
  update auth.users set raw_user_meta_data = jsonb_build_object('first_name', 'Lee', 'phone', '+6591392199')
   where id = pg_temp.fx('uE');
  update auth.users set raw_user_meta_data = jsonb_build_object('first_name', 'Ann', 'phone', '+6591392112')
   where id = pg_temp.fx('uE2');
  update auth.users set raw_user_meta_data = jsonb_build_object('first_name', 'Faye', 'phone', '+60 12-345 6789')
   where id = pg_temp.fx('uF');
  update auth.users set raw_user_meta_data = jsonb_build_object('first_name', 'Gil', 'last_name', 'Fail', 'phone', '+6591392107')
   where id = pg_temp.fx('uG');
  update auth.users set raw_user_meta_data = jsonb_build_object('first_name', 'Hana', 'last_name', 'Fail', 'phone', '+6591392108')
   where id = pg_temp.fx('uH');
  update auth.users set raw_user_meta_data = jsonb_build_object('first_name', 'Jun', 'last_name', 'Post', 'phone', '+6591392109')
   where id = pg_temp.fx('uJ');
  update auth.users set raw_user_meta_data = jsonb_build_object('first_name', 'Kai', 'last_name', 'Post', 'phone', '+6591392110')
   where id = pg_temp.fx('uK');
  -- N: names nobody checks, typed at sign-up.
  update auth.users set raw_user_meta_data = jsonb_build_object('first_name',
           'Claim your S$500 prize at https://x.invalid/p and reply YES', 'last_name', 'Tan', 'phone', '+6591392113')
   where id = pg_temp.fx('uN');
  update auth.users set raw_user_meta_data = jsonb_build_object('first_name', repeat('A', 5000), 'last_name', 'Long', 'phone', '+6591392114')
   where id = pg_temp.fx('uO');
  update auth.users set raw_user_meta_data = jsonb_build_object('first_name', 'Win at https://x.invalid/p', 'phone', '+6591392115')
   where id = pg_temp.fx('uQ');
  update auth.users set raw_user_meta_data = jsonb_build_object('first_name', '+6591392199', 'phone', '+6591392116')
   where id = pg_temp.fx('uR');
  -- D13, D14: sign-ups suspended and reactivated before their welcome went out.
  update auth.users set raw_user_meta_data = jsonb_build_object('first_name', 'Lin', 'last_name', 'Wait', 'phone', '+6591392117')
   where id = pg_temp.fx('uL');
  update auth.users set raw_user_meta_data = jsonb_build_object('first_name', 'Max', 'last_name', 'Wait', 'phone', '+6591392118')
   where id = pg_temp.fx('uM');

  -- R: a customer whose name carries a note in front.
  insert into customers(full_name, phone) values ('(intern) Ravi Kumar', '+6591392102') returning id into c;
  insert into fx values ('cB', c);
  -- S: an affiliate an Owner suspended before they had a login.
  insert into customers(full_name, phone) values ('Sue Pended', '+6591392103') returning id into c;
  insert into fx values ('cC', c);
  insert into customer_affiliates(customer_id, status, manually_suspended, activated_at, referral_code)
    values (c, 'suspended_manual', true, now(), generate_affiliate_referral_code());
  -- A: a suspended affiliate with no login.
  insert into customers(full_name, phone) values ('Ida Nologin', '+6591392106') returning id into c;
  insert into fx values ('cI', c);
  insert into customer_affiliates(customer_id, status, manually_suspended, activated_at, referral_code)
    values (c, 'suspended_manual', true, now(), generate_affiliate_referral_code());
  -- N: customers staff link those logins to; the second has no name to greet.
  insert into customers(full_name, phone) values ('Grace Lim', '+6591392115') returning id into c;
  insert into fx values ('cQ', c);
  insert into customers(full_name, phone) values ('J.B. 2', '+6591392116') returning id into c;
  insert into fx values ('cR', c);
end $$;
-- P: phones kept as typed, as rows from before the phone policy are.
set local session_replication_role = replica;
with c as (insert into customers(full_name, phone) values ('Nora Nophone', '') returning id) insert into fx select 'cD', id from c;
with c as (insert into customers(full_name, phone) values ('Lee Legacy', '81392105') returning id) insert into fx select 'cE', id from c;
with c as (insert into customers(full_name, phone) values ('Ann Ambiguous', '91392111') returning id) insert into fx select 'cE2', id from c;
with c as (insert into customers(full_name, phone) values ('Faye Fallback', '12345') returning id) insert into fx select 'cF', id from c;
set local session_replication_role = origin;

-- ═════ W: a self sign-up goes live ═════
select pg_temp.check(pg_temp.signup('uA') = 'active', 'W1 the self sign-up goes live');
select pg_temp.check(pg_temp.rows_for('uA') = 1, 'W1 exactly one message is queued for it');
select pg_temp.check(o.kind = 'welcome' and o.status = 'queued' and o.skip_reason is null and o.attempts = 0
       and o.idempotency_key = 'welcome:' || pg_temp.fx('uA')
       and o.customer_id = (select customer_id from affiliate_accounts where auth_user_id = pg_temp.fx('uA'))
       and o.affiliate_id = (select affiliate_id from affiliate_accounts where auth_user_id = pg_temp.fx('uA')),
       'W1 a queued welcome, keyed by the login: ' || row(o.kind, o.status, o.skip_reason)::text)
  from (select (pg_temp.row_of('uA')).*) o;
insert into fx select 'cA', customer_id from affiliate_accounts where auth_user_id = pg_temp.fx('uA');
select pg_temp.check(o.phone_e164 = '+6591392101' and o.wa_country_code = '65' and o.wa_number = '91392101'
       and o.first_name = 'Mei' and o.referral_code = pg_temp.code('cA') and o.referral_code ~ '^EN[0-9A-Z]{6}$',
       'W2 the phone, WhatsApp country code and number, first name and referral code: '
       || row(o.phone_e164, o.wa_country_code, o.wa_number, o.first_name, o.referral_code)::text)
  from (select (pg_temp.row_of('uA')).*) o;
select pg_temp.check(o.message = pg_temp.expected('welcome', 'Mei', pg_temp.code('cA')),
       'W3 the message greets them by first name and has the login, forgot-password and referral links: ' || o.message)
  from (select (pg_temp.row_of('uA')).*) o;
select pg_temp.check(pg_temp.signup('uA') = 'active' and pg_temp.rows_for('uA') = 1,
  'W4 asking again (already onboarded) queues nothing more');
-- The same login linked again (as after an Owner's Unlink and a new Resolve).
create temp table relink as select * from affiliate_accounts where auth_user_id = pg_temp.fx('uA');
delete from affiliate_accounts where auth_user_id = pg_temp.fx('uA');
insert into affiliate_accounts select * from relink;
select pg_temp.check(pg_temp.rows_for('uA') = 1, 'W4 the same login linked again gets no second welcome');

-- ═════ R: staff resolve a claim ═════
select pg_temp.check(r = 'true suspended=false', 'R1 a member of staff resolves a claim: ' || r)
  from (select pg_temp.resolve('stf', 'uB', 'cB') r) x;
select pg_temp.check(pg_temp.rows_for('uB') = 1, 'R1 exactly one message is queued for it');
select pg_temp.check(o.kind = 'welcome' and o.status = 'queued' and o.phone_e164 = '+6591392102'
       and o.wa_country_code = '65' and o.wa_number = '91392102' and o.first_name = 'Ravi'
       and o.message = pg_temp.expected('welcome', 'Ravi', pg_temp.code('cB')),
       'R2 the welcome uses the customer''s phone, and the first word of their name without the bracketed note: '
       || row(o.status, o.phone_e164, o.first_name)::text)
  from (select (pg_temp.row_of('uB')).*) o;

-- ═════ S: suspended at that moment ═════
select pg_temp.check(r = 'true suspended=true', 'S1 an Owner links a login to a suspended affiliate: ' || r)
  from (select pg_temp.resolve('own', 'uC', 'cC') r) x;
select pg_temp.check(pg_temp.rows_for('uC') = 1 and o.status = 'skipped' and o.skip_reason = 'affiliate_suspended'
       and o.message = pg_temp.expected('welcome', 'Sue', pg_temp.code('cC')),
       'S1 the welcome is kept as skipped (affiliate_suspended), not sent: ' || row(o.status, o.skip_reason)::text)
  from (select (pg_temp.row_of('uC')).*) o;

-- ═════ P: phones ═════
select pg_temp.check(r = 'true suspended=false', 'P1 an Owner links a customer with no phone: ' || r)
  from (select pg_temp.resolve('own', 'uD', 'cD') r) x;
select pg_temp.check(pg_temp.rows_for('uD') = 1 and o.status = 'skipped' and o.skip_reason = 'no_phone'
       and o.phone_e164 is null and o.first_name = 'Nora',
       'P1 no phone on the customer or the sign-up: skipped (no_phone): ' || row(o.status, o.skip_reason, o.first_name)::text)
  from (select (pg_temp.row_of('uD')).*) o;
select pg_temp.check(r = 'true suspended=false', 'P2 an Owner links a customer with a legacy 8-digit phone: ' || r)
  from (select pg_temp.resolve('own', 'uE', 'cE') r) x;
select pg_temp.check(o.status = 'queued' and o.phone_e164 = '+6581392105' and o.wa_country_code = '65' and o.wa_number = '81392105'
       and o.first_name = 'Lee',
       'P2 the legacy phone is read as +65 (and wins over the sign-up phone): ' || row(o.status, o.phone_e164, o.wa_number)::text)
  from (select (pg_temp.row_of('uE')).*) o;
-- 9139 2111 could be Singapore or Malaysia; the phone policy does not guess.
select pg_temp.check(public.normalize_customer_phone('91392111') is null, 'P2 (a legacy 8-digit phone the policy finds ambiguous)');
select pg_temp.check(r = 'true suspended=false', 'P2 an Owner links a customer with an ambiguous legacy phone: ' || r)
  from (select pg_temp.resolve('own', 'uE2', 'cE2') r) x;
select pg_temp.check(o.status = 'queued' and o.phone_e164 = '+6591392112' and o.wa_number = '91392112' and o.first_name = 'Ann',
       'P2 an ambiguous one is not guessed: the phone given at sign-up is used: ' || row(o.status, o.phone_e164)::text)
  from (select (pg_temp.row_of('uE2')).*) o;
select pg_temp.check(r = 'true suspended=false', 'P3 an Owner links a customer whose phone cannot be read: ' || r)
  from (select pg_temp.resolve('own', 'uF', 'cF') r) x;
select pg_temp.check(o.status = 'queued' and o.phone_e164 = '+60123456789' and o.wa_country_code = '60' and o.wa_number = '123456789'
       and o.first_name = 'Faye',
       'P3 the phone given at sign-up is used instead: ' || row(o.status, o.phone_e164, o.wa_country_code, o.wa_number)::text)
  from (select (pg_temp.row_of('uF')).*) o;

-- ═════ A: reactivation ═════
select pg_temp.check(pg_temp.as_owner(format('select public.reactivate_affiliate(%L)', pg_temp.fx('cC'))) = 'ok',
  'A1 an Owner reactivates the suspended affiliate');
select pg_temp.check(pg_temp.rows_for('uC') = 2 and o.status = 'queued' and o.phone_e164 = '+6591392103' and o.first_name = 'Sue'
       and o.idempotency_key like 'reactivated:' || (select id from customer_affiliates where customer_id = pg_temp.fx('cC')) || ':%'
       and o.message = pg_temp.expected('reactivated', 'Sue', pg_temp.code('cC')),
       'A1 one ''reactivated'' message is queued, saying the account is active again, with the same links: ' || coalesce(o.message, 'none'))
  from (select (pg_temp.row_of('uC', 'reactivated')).*) o;
select pg_temp.check(pg_temp.as_owner(format('select public.reactivate_affiliate(%L)', pg_temp.fx('cC'))) = 'ok',
  'A2 an Owner reactivates them again');
select pg_temp.check(pg_temp.rows_for('uC') = 2, 'A2 reactivating an affiliate who is already active queues nothing');
update customer_affiliates set notes = 'touched', updated_at = now() where customer_id = pg_temp.fx('cC');
update customer_affiliates set manually_suspended = false where customer_id = pg_temp.fx('cC');
select pg_temp.check(pg_temp.rows_for('uC') = 2, 'A2 other updates, and false to false, queue nothing');
select pg_temp.check(pg_temp.as_owner(format('select public.suspend_affiliate(%L, %L)', pg_temp.fx('cC'), 'Testing')) = 'ok',
  'A2 an Owner suspends them');
select pg_temp.check(pg_temp.as_owner(format('select public.reactivate_affiliate(%L)', pg_temp.fx('cC'))) = 'ok',
  'A2 and reactivates them, in the same transaction');
select pg_temp.check(pg_temp.rows_for('uC') = 2,
  'A2 that is the same reactivation (one per transaction): no second message');
select pg_temp.check(pg_temp.as_owner(format('select public.reactivate_affiliate(%L)', pg_temp.fx('cI'))) = 'ok',
  'A3 an Owner reactivates an affiliate with no login');
select pg_temp.check(not (select manually_suspended from customer_affiliates where customer_id = pg_temp.fx('cI'))
       and not exists (select 1 from public.affiliate_whatsapp_outbox where customer_id = pg_temp.fx('cI')),
  'A3 which queues nothing');

-- ═════ F: a failure while queueing never stops the sign-up ═════
create temp table saved_message as
  select pg_get_functiondef('public.affiliate_whatsapp_message(text,text,text,text)'::regprocedure) d;
create or replace function public.affiliate_whatsapp_message(p_kind text, p_first_name text, p_app_url text, p_referral_code text)
returns text language plpgsql immutable set search_path = public as $fn$ begin raise exception 'wording broke'; end $fn$;
select pg_temp.check(pg_temp.signup('uG') = 'active', 'F1 the sign-up goes live although the message cannot be composed');
select pg_temp.check(exists (select 1 from affiliate_accounts where auth_user_id = pg_temp.fx('uG')), 'F1 the login is linked');
select pg_temp.check(pg_temp.rows_for('uG') = 1 and o.status = 'failed' and o.skip_reason = 'enqueue_error'
       and o.last_error like '%wording broke%' and o.message is null,
       'F1 the failure is kept as failed (enqueue_error) with the error: ' || row(o.status, o.skip_reason, o.last_error)::text)
  from (select (pg_temp.row_of('uG')).*) o;
do $$ begin execute (select d from saved_message); end $$;
-- Even the outbox refusing every row does not stop it (a warning only).
alter table public.affiliate_whatsapp_outbox add constraint wa394_test_refuse_all check (false) not valid;
select pg_temp.check(pg_temp.signup('uH') = 'active', 'F2 the sign-up goes live although the outbox refuses the row');
alter table public.affiliate_whatsapp_outbox drop constraint wa394_test_refuse_all;
select pg_temp.check(exists (select 1 from affiliate_accounts where auth_user_id = pg_temp.fx('uH')), 'F2 the login is linked');
select pg_temp.check(pg_temp.rows_for('uH') = 0, 'F2 and nothing is kept for it');
select pg_temp.check(md5(pg_get_functiondef('public.affiliate_whatsapp_message(text,text,text,text)'::regprocedure))
                       = '6cab1d437121fb0942f90dd7ec7c5310', 'F3 (the message function put back)');

-- ═════ D: the dispatcher ═════
create temp table states as select id, status, attempts, request_id from public.affiliate_whatsapp_outbox;
select pg_temp.check(public.affiliate_whatsapp_dispatch() = '{"enabled": false}'::jsonb, 'D1 while off, the dispatcher answers {"enabled": false}');
select pg_temp.check(not exists (select id, status, attempts, request_id from public.affiliate_whatsapp_outbox
                                 except select * from states), 'D1 and changes nothing');
select pg_temp.check((select count(*) from public.affiliate_whatsapp_outbox where status = 'queued') = 6,
  'D1 six messages wait: Mei, Ravi, Lee, Ann, Faye and Sue''s reactivation');
do $$ begin
  begin
    update public.affiliate_whatsapp_settings set enabled = true;
    raise exception 'turned on with no webhook address';
  exception when check_violation then null;
  end;
end $$;
select pg_temp.check(not (select enabled from public.affiliate_whatsapp_settings), 'D2 it cannot be turned on without a webhook address and a secret');
do $$ begin
  begin
    update public.affiliate_whatsapp_settings set webhook_url = 'http://hooks.example.invalid/wa';
    raise exception 'took an http address';
  exception when check_violation then null;
  end;
  begin
    update public.affiliate_whatsapp_settings set secret = 'short';
    raise exception 'took a short secret';
  exception when check_violation then null;
  end;
end $$;
select pg_temp.check(true, 'D2 the webhook address must be https and the secret at least 16 characters');

-- The body posted for one row.
select pg_temp.check(public.affiliate_whatsapp_payload(o.id, 'wa-test-secret-0123456789')
       = jsonb_build_object('secret', 'wa-test-secret-0123456789', 'idempotency_key', 'welcome:' || pg_temp.fx('uA'),
           'kind', 'welcome', 'first_name', 'Mei', 'phone_e164', '+6591392101', 'wa_country_code', '65',
           'wa_number', '91392101', 'message', pg_temp.expected('welcome', 'Mei', pg_temp.code('cA'))),
       'D3 the body: secret, idempotency_key, kind, first_name, phone_e164, wa_country_code, wa_number, message')
  from (select (pg_temp.row_of('uA')).*) o;

-- What is taken, and how answers settle.
update public.affiliate_whatsapp_outbox set created_at = now() - interval '49 hours' where auth_user_id = pg_temp.fx('uE');
delete from affiliate_accounts where auth_user_id = pg_temp.fx('uF');
create temp table taken as select t.id from public.affiliate_whatsapp_take(50) t(id);
select pg_temp.check((pg_temp.row_of('uE')).status = 'expired', 'D4 a message waiting more than 48 hours expires');
select pg_temp.check((pg_temp.row_of('uF')).status = 'skipped' and (pg_temp.row_of('uF')).skip_reason = 'no_longer_active',
  'D4 a message whose login is no longer linked is skipped (no_longer_active)');
select pg_temp.check((select array_agg(id order by id) from taken)
       = array[(pg_temp.row_of('uA')).id, (pg_temp.row_of('uB')).id, (pg_temp.row_of('uE2')).id,
               (pg_temp.row_of('uC', 'reactivated')).id],
  'D4 the four still waiting are taken, oldest first, and nothing else');
select pg_temp.check((select array_agg(t.id) from public.affiliate_whatsapp_take(1) t(id)) = array[(pg_temp.row_of('uA')).id],
  'D4 at most p_limit are taken');

do $$
declare a bigint := (pg_temp.row_of('uA')).id; b bigint := (pg_temp.row_of('uB')).id;
        c bigint := (pg_temp.row_of('uC', 'reactivated')).id; e bigint := (pg_temp.row_of('uE2')).id;
        o public.affiliate_whatsapp_outbox;
begin
  perform pg_temp.check(public.affiliate_whatsapp_settle(a, 200, false, null) is null,
    'D5 an answer for a row that was not posted changes nothing');
  perform pg_temp.check(public.affiliate_whatsapp_mark_sending(a, 101), 'D5 a posted row is marked sending');
  select * into o from public.affiliate_whatsapp_outbox where id = a;
  perform pg_temp.check(o.status = 'sending' and o.request_id = 101 and o.attempts = 1 and o.sending_at = now(),
    'D5 with pg_net''s request id and one attempt');
  perform pg_temp.check(public.affiliate_whatsapp_settle(a, 200, false, null) = 'sent', 'D6 a 2xx answer: sent');
  select * into o from public.affiliate_whatsapp_outbox where id = a;
  perform pg_temp.check(o.sent_at = now() and o.last_status_code = 200 and o.last_error is null and o.retry_after is null,
    'D6 with the time it was sent');
  perform public.affiliate_whatsapp_mark_sending(e, 106);
  perform pg_temp.check(public.affiliate_whatsapp_settle(e, 204, false, null) = 'sent', 'D6 any 2xx (204): sent');

  perform public.affiliate_whatsapp_mark_sending(b, 102);
  perform pg_temp.check(public.affiliate_whatsapp_settle(b, 500, false, 'Internal Server Error') = 'failed',
    'D7 another status code: failed');
  select * into o from public.affiliate_whatsapp_outbox where id = b;
  perform pg_temp.check(o.retry_after = now() + interval '5 minutes' and o.last_status_code = 500
                          and o.last_error = 'Internal Server Error',
    'D7 and posted again 5 minutes later');
  perform pg_temp.check(not exists (select 1 from public.affiliate_whatsapp_take(50) t(id) where t.id = b),
    'D7 not before then');
  update public.affiliate_whatsapp_outbox set retry_after = now() - interval '1 second' where id = b;
  perform pg_temp.check(exists (select 1 from public.affiliate_whatsapp_take(50) t(id) where t.id = b),
    'D7 then it is taken again');
  perform public.affiliate_whatsapp_mark_sending(b, 103);
  perform public.affiliate_whatsapp_settle(b, 502, false, null);
  update public.affiliate_whatsapp_outbox set retry_after = now() - interval '1 second' where id = b;
  perform public.affiliate_whatsapp_mark_sending(b, 104);
  perform pg_temp.check(public.affiliate_whatsapp_settle(b, 503, false, null) = 'failed', 'D7 a third failed post');
  select * into o from public.affiliate_whatsapp_outbox where id = b;
  perform pg_temp.check(o.attempts = 3 and o.retry_after is null and o.last_error = 'HTTP 503'
                          and not exists (select 1 from public.affiliate_whatsapp_take(50) t(id) where t.id = b),
    'D7 after 3 posts it is not tried again');

  perform public.affiliate_whatsapp_mark_sending(c, 105);
  perform pg_temp.check(public.affiliate_whatsapp_settle(c, null, true, 'Timeout of 10000 ms reached') = 'failed',
    'D8 a timeout: failed');
  select * into o from public.affiliate_whatsapp_outbox where id = c;
  perform pg_temp.check(o.attempts = 1 and o.retry_after is null and o.last_error = 'Timeout of 10000 ms reached'
                          and not exists (select 1 from public.affiliate_whatsapp_take(50) t(id) where t.id = c),
    'D8 and never tried again (it may have gone out)');
end $$;

-- End to end, against a stand-in for pg_net, where pg_net is not installed.
do $$
declare r jsonb; j bigint; k bigint;
begin
  if to_regnamespace('net') is not null then
    raise notice 'NOTE  pg_net is installed here: the end-to-end part (D9) is left out; D3-D8 cover its steps';
    return;
  end if;
  execute $s$
    create schema net;
    create table net.http_request_queue (id bigserial primary key, method text, url text, headers jsonb,
                                         body bytea, timeout_milliseconds integer);
    create table net._http_response (id bigint, status_code integer, content_type text, headers jsonb,
                                     content text, timed_out boolean, error_msg text, created timestamptz default now());
    create function net.http_post(url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
                                  headers jsonb default '{"Content-Type": "application/json"}'::jsonb,
                                  timeout_milliseconds integer default 5000)
    returns bigint language sql as $f$
      insert into net.http_request_queue (method, url, headers, body, timeout_milliseconds)
      values ('POST', url, headers, convert_to(body::text, 'UTF8'), timeout_milliseconds) returning id
    $f$;
  $s$;
  -- Two new sign-ups wait; nothing else does.
  perform pg_temp.check(pg_temp.signup('uJ') = 'active', 'D9 two more sign-ups go live (1)');
  perform pg_temp.check(pg_temp.signup('uK') = 'active', 'D9 two more sign-ups go live (2)');
  j := (pg_temp.row_of('uJ')).id; k := (pg_temp.row_of('uK')).id;
  update public.affiliate_whatsapp_settings
     set webhook_url = 'https://hooks.example.invalid/wa', secret = 'wa-test-secret-0123456789', enabled = true;

  r := public.affiliate_whatsapp_dispatch();
  perform pg_temp.check(r = '{"enabled": true, "posted": 2, "settled": 0}'::jsonb, 'D9 turned on, it posts the two waiting: ' || r::text);
  perform pg_temp.check((select count(*) from net.http_request_queue) = 2
      and (select bool_and(q.url = 'https://hooks.example.invalid/wa' and q.timeout_milliseconds = 10000
                           and q.headers = '{"Content-Type": "application/json"}'::jsonb)
             from net.http_request_queue q)
      and (select convert_from(q.body, 'UTF8')::jsonb from net.http_request_queue q
            where q.id = (select request_id from public.affiliate_whatsapp_outbox where id = j))
          = public.affiliate_whatsapp_payload(j, 'wa-test-secret-0123456789'),
    'D9 to the webhook address, with the body, a JSON header and a 10 second timeout');
  perform pg_temp.check((select bool_and(status = 'sending' and attempts = 1 and request_id is not null)
                           from public.affiliate_whatsapp_outbox where id in (j, k)),
    'D9 both are marked sending with pg_net''s request ids');

  insert into net._http_response (id, status_code, content)
    select request_id, 200, '{"status":"success"}' from public.affiliate_whatsapp_outbox where id = j;
  insert into net._http_response (id, status_code, content)
    select request_id, 500, 'nope' from public.affiliate_whatsapp_outbox where id = k;
  r := public.affiliate_whatsapp_dispatch();
  perform pg_temp.check(r = '{"enabled": true, "posted": 0, "settled": 2}'::jsonb
      and (pg_temp.row_of('uJ')).status = 'sent'
      and (pg_temp.row_of('uK')).status = 'failed' and (pg_temp.row_of('uK')).last_error = 'nope',
    'D10 the answers settle them: sent, and failed with what Pabbly said, not posted again at once: ' || r::text);

  update public.affiliate_whatsapp_outbox set retry_after = now() - interval '1 second' where id = k;
  r := public.affiliate_whatsapp_dispatch();
  perform pg_temp.check(r = '{"enabled": true, "posted": 1, "settled": 0}'::jsonb and (pg_temp.row_of('uK')).attempts = 2,
    'D11 after 5 minutes it is posted again: ' || r::text);
  update public.affiliate_whatsapp_outbox set sending_at = now() - interval '16 minutes' where id = k;
  r := public.affiliate_whatsapp_dispatch();
  perform pg_temp.check(r = '{"enabled": true, "posted": 0, "settled": 1}'::jsonb
      and (pg_temp.row_of('uK')).status = 'failed' and (pg_temp.row_of('uK')).retry_after is null
      and (pg_temp.row_of('uK')).last_error = 'no answer recorded by pg_net',
    'D11 no answer after 15 minutes: failed for good: ' || r::text);

  update public.affiliate_whatsapp_settings set enabled = false;
  update public.affiliate_whatsapp_outbox set retry_after = now() - interval '1 second', status = 'failed' where id = k;
  r := public.affiliate_whatsapp_dispatch();
  perform pg_temp.check(r = '{"enabled": false}'::jsonb and (select count(*) from net.http_request_queue) = 3,
    'D12 turned off again, nothing more is posted');
end $$;

-- ═════ D13, D14: a reactivation while an earlier message still waits ═════
select pg_temp.check(pg_temp.signup('uL') = 'active', 'D13 a sign-up goes live (its welcome waits)');
insert into fx select 'cL', customer_id from affiliate_accounts where auth_user_id = pg_temp.fx('uL');
select pg_temp.check(pg_temp.as_owner(format('select public.suspend_affiliate(%L, %L)', pg_temp.fx('cL'), 'Testing')) = 'ok',
  'D13 an Owner suspends them before it went out');
select pg_temp.check(pg_temp.as_owner(format('select public.reactivate_affiliate(%L)', pg_temp.fx('cL'))) = 'ok',
  'D13 and reactivates them');
select pg_temp.check(pg_temp.rows_for('uL') = 2 and (pg_temp.row_of('uL', 'reactivated')).status = 'queued',
  'D13 a welcome and a reactivation wait');
create temp table taken13 as select t.id from public.affiliate_whatsapp_take(50) t(id);
select pg_temp.check((pg_temp.row_of('uL')).id in (select id from taken13)
       and (pg_temp.row_of('uL', 'reactivated')).id not in (select id from taken13)
       and (pg_temp.row_of('uL', 'reactivated')).status = 'skipped'
       and (pg_temp.row_of('uL', 'reactivated')).skip_reason = 'earlier_message_pending',
  'D13 only the welcome is posted (same links); the reactivation is skipped (earlier_message_pending): '
  || row((pg_temp.row_of('uL', 'reactivated')).status, (pg_temp.row_of('uL', 'reactivated')).skip_reason)::text);
do $$
declare w bigint := (pg_temp.row_of('uL')).id; r2 bigint; r3 bigint; r4 bigint; v_taken bigint[];
begin
  -- Later reactivations of the same login (one per transaction, so queued here directly).
  perform public.affiliate_whatsapp_mark_sending(w, 301);
  r2 := public.affiliate_whatsapp_enqueue('reactivated', pg_temp.fx('uL'), pg_temp.fx('cL'), null, 'reactivated:wa394-test-2');
  select array_agg(t.id) into v_taken from public.affiliate_whatsapp_take(50) t(id);
  perform pg_temp.check(not (r2 = any (coalesce(v_taken, '{}')))
      and (select status || ' ' || skip_reason from public.affiliate_whatsapp_outbox where id = r2) = 'skipped earlier_message_pending',
    'D13 nor while the welcome is being posted');
  perform pg_temp.check(public.affiliate_whatsapp_settle(w, 200, false, null) = 'sent', 'D13 (the welcome is sent)');
  r3 := public.affiliate_whatsapp_enqueue('reactivated', pg_temp.fx('uL'), pg_temp.fx('cL'), null, 'reactivated:wa394-test-3');
  r4 := public.affiliate_whatsapp_enqueue('reactivated', pg_temp.fx('uL'), pg_temp.fx('cL'), null, 'reactivated:wa394-test-4');
  select array_agg(t.id) into v_taken from public.affiliate_whatsapp_take(50) t(id);
  perform pg_temp.check(r3 = any (v_taken) and not (r4 = any (v_taken))
      and (select status from public.affiliate_whatsapp_outbox where id = r3) = 'queued'
      and (select status || ' ' || skip_reason from public.affiliate_whatsapp_outbox where id = r4) = 'skipped earlier_message_pending',
    'D13 once the welcome was sent, a later reactivation is posted; of two waiting, only the first');
end $$;

select pg_temp.check(pg_temp.signup('uM') = 'active', 'D14 another sign-up goes live');
insert into fx select 'cM', customer_id from affiliate_accounts where auth_user_id = pg_temp.fx('uM');
update public.affiliate_whatsapp_outbox set created_at = now() - interval '49 hours' where auth_user_id = pg_temp.fx('uM');
select pg_temp.check(pg_temp.as_owner(format('select public.suspend_affiliate(%L, %L)', pg_temp.fx('cM'), 'Testing')) = 'ok',
  'D14 an Owner suspends them');
select pg_temp.check(pg_temp.as_owner(format('select public.reactivate_affiliate(%L)', pg_temp.fx('cM'))) = 'ok',
  'D14 and reactivates them');
create temp table taken14 as select t.id from public.affiliate_whatsapp_take(50) t(id);
select pg_temp.check((pg_temp.row_of('uM')).status = 'expired'
       and (pg_temp.row_of('uM', 'reactivated')).id in (select id from taken14)
       and (pg_temp.row_of('uM', 'reactivated')).status = 'queued',
  'D14 a welcome that waited over 48 hours expires, and the reactivation is posted instead');

-- ═════ N: the name in the greeting ═════
-- The sign-up name is whatever the person typed; only one that looks like a
-- name is used, else the customer's, else "there".
select pg_temp.check(pg_temp.signup('uN') = 'active', 'N1 a sign-up whose first name carries a link and a price goes live');
insert into fx select 'cN', customer_id from affiliate_accounts where auth_user_id = pg_temp.fx('uN');
select pg_temp.check(pg_temp.rows_for('uN') = 1 and o.status = 'queued'
       and (o.first_name is null or o.first_name ~ '^[[:alpha:]]+$')
       and o.message = pg_temp.expected('welcome', coalesce(o.first_name, 'there'), pg_temp.code('cN'))
       and strpos(o.message, 'x.invalid') = 0 and strpos(o.message, '500') = 0 and strpos(o.message, 'YES') = 0,
       'N1 the link, the price and the rest of it are not sent: greeted as ' || coalesce(o.first_name, 'there'))
  from (select (pg_temp.row_of('uN')).*) o;
select pg_temp.check(pg_temp.signup('uO') = 'active', 'N2 a sign-up with a 5,000-character first name goes live');
insert into fx select 'cO', customer_id from affiliate_accounts where auth_user_id = pg_temp.fx('uO');
select pg_temp.check(o.status = 'queued' and o.first_name is null
       and o.message = pg_temp.expected('welcome', 'there', pg_temp.code('cO')) and length(o.message) < 600
       and public.affiliate_whatsapp_payload(o.id, 'wa-test-secret-0123456789')->>'first_name' = '',
       'N2 greeted as "there" (no usable name), and the message stays short: ' || length(o.message) || ' characters')
  from (select (pg_temp.row_of('uO')).*) o;
select pg_temp.check(r = 'true suspended=false', 'N3 a member of staff links a login whose sign-up name carries a link: ' || r)
  from (select pg_temp.resolve('stf', 'uQ', 'cQ') r) x;
select pg_temp.check(o.status = 'queued' and o.first_name = 'Grace'
       and o.message = pg_temp.expected('welcome', 'Grace', pg_temp.code('cQ')),
       'N3 the customer''s first name is used instead: ' || coalesce(o.first_name, 'none'))
  from (select (pg_temp.row_of('uQ')).*) o;
select pg_temp.check(r = 'true suspended=false', 'N4 a member of staff links a login named with a phone number to a customer named J.B. 2: ' || r)
  from (select pg_temp.resolve('stf', 'uR', 'cR') r) x;
select pg_temp.check(o.status = 'queued' and o.first_name is null and o.phone_e164 = '+6591392116'
       and o.message = pg_temp.expected('welcome', 'there', pg_temp.code('cR')),
       'N4 no name looks like one: "Hi there": ' || coalesce(o.first_name, 'none'))
  from (select (pg_temp.row_of('uR')).*) o;
-- What is used of each typed name (Grace is the customer's own first name).
create temp table names(n serial, typed text, used text);
insert into names(typed, used) values
  ('Anne-Marie', 'Anne-Marie'), (E'D’Arcy', E'D’Arcy'), ('O''Neil', 'O''Neil'), (E'José', E'José'),
  ('Mei Ling', 'Mei Ling'), ('(VIP) Wen', 'Wen'), (E'  Siti \n Nur  ', 'Siti Nur'), (repeat('A', 30), repeat('A', 30)),
  ('bit.ly', 'Grace'), ('Jun2', 'Grace'), ('https://x.invalid', 'Grace'), ('+6591392199', 'Grace'), ('Ann@x', 'Grace'),
  ('Ann: hi', 'Grace'), ('a/b', 'Grace'), (E'Ann．x', 'Grace'), (repeat('A', 31), 'Grace'), ('', 'Grace'), (null, 'Grace');
do $$
declare r record; v text;
begin
  for r in select * from names order by n loop
    update auth.users set raw_user_meta_data = jsonb_build_object('first_name', r.typed) where id = pg_temp.fx('uQ');
    perform public.affiliate_whatsapp_enqueue('welcome', pg_temp.fx('uQ'), pg_temp.fx('cQ'), null, 'wa394-test-name:' || r.n);
    select first_name into v from public.affiliate_whatsapp_outbox where idempotency_key = 'wa394-test-name:' || r.n;
    perform pg_temp.check(v is not distinct from r.used, format('N5 typed %s: greeted as %s', coalesce(quote_literal(left(r.typed, 40)), 'nothing'), v));
  end loop;
  delete from public.affiliate_whatsapp_outbox where idempotency_key like 'wa394-test-name:%';
end $$;

-- ═════ G: who may call what ═════
select pg_temp.check(c.relrowsecurity
       and not has_table_privilege('anon', c.oid, 'select,insert,update,delete,truncate,references,trigger')
       and not has_table_privilege('authenticated', c.oid, 'select,insert,update,delete,truncate,references,trigger'),
       'G1 ' || c.relname || ': row level security on, nothing granted to anon or authenticated')
  from pg_class c where c.oid in ('public.affiliate_whatsapp_settings'::regclass, 'public.affiliate_whatsapp_outbox'::regclass);
select pg_temp.check(not has_sequence_privilege('anon', pg_get_serial_sequence('public.affiliate_whatsapp_outbox', 'id'), 'usage,select,update')
       and not has_sequence_privilege('authenticated', pg_get_serial_sequence('public.affiliate_whatsapp_outbox', 'id'), 'usage,select,update'),
  'G1 nor the outbox''s id sequence');
select pg_temp.check(not has_function_privilege('anon', p.oid, 'execute')
       and not has_function_privilege('authenticated', p.oid, 'execute')
       and has_function_privilege('service_role', p.oid, 'execute'),
       'G2 ' || p.oid::regprocedure::text || ': service_role only')
  from pg_proc p where p.pronamespace = 'public'::regnamespace
   and (p.proname like 'affiliate_whatsapp%' or p.proname like 'trg_affiliate_whatsapp%' or p.proname = 'ads_wa_country_code');
do $$
declare v_read text := 'read'; v_ran text := 'ran';
begin
  execute 'set local role authenticated';
  begin
    perform 1 from public.affiliate_whatsapp_settings;
  exception when insufficient_privilege then v_read := 'refused';
  end;
  begin
    perform public.affiliate_whatsapp_dispatch();
  exception when insufficient_privilege then v_ran := 'refused';
  end;
  execute 'reset role';
  perform pg_temp.check(v_read = 'refused', 'G3 a signed-in user cannot read the settings (the secret)');
  perform pg_temp.check(v_ran = 'refused', 'G3 nor run the dispatcher');
end $$;

do $$
declare n int; msgs text;
begin
  select count(*), string_agg(msg, E'\n') into n, msgs from failed;
  if n > 0 then raise exception E'% affiliate WhatsApp check(s) failed:\n%', n, msgs; end if;
  raise notice 'All affiliate WhatsApp outbox checks passed.';
end $$;

rollback;
