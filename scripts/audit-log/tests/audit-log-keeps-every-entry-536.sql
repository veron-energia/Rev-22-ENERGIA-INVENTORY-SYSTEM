-- The Audit Log keeps every entry: no login or key changes, deletes or empties it, and the secret
-- key no longer adds entries of its own (536; security audit of 17 Nov 2026, M14; the user, 24 Nov
-- 2026: "Append-only").
--
-- Every attempt is made as the API makes it: the secret key (the service_role role), a signed-in
-- login (the authenticated role with its JWT: an Owner, a Staff member), or the database owner
-- (postgres). Each refused attempt is rolled back on its own, so nothing it might have done stays
-- (in control mode too).
--
--   S  The secret key: an insert, an update, a deletion and emptying the table are refused
--      (permission denied), and so are /rpc/write_audit and /rpc/write_audit_ex; it still reads
--      the log.
--   A  A signed-in Owner and a Staff member: the same refusals; the Owner still reads the log.
--   W  Entries are still written: an Owner's Delete and Restore on the Stores page
--      (soft_delete_store, restore_store) give their own entry each, and so do the same two
--      called with the secret key (no login, as an Edge Function calls a server function); 532's trigger still records a change made straight
--      on a store by the secret key (actor_role service_role) and by an Owner, and a Staff
--      member's own phone (staff_profile_updated).
--   O  The database owner: an entry written before this transaction (committed) cannot be changed
--      or deleted, and neither can one written in this very transaction (there is no exception
--      for it); the log cannot be emptied, nor through emptying profiles or stores with cascade;
--      with session_replication_role = replica (the triggers are enabled ALWAYS) still not.
--   D  A suite that back-dates its own entries switches the row trigger off inside its own
--      transaction, as the older suites do: the update then goes through, and the trigger is
--      ALWAYS again after the rollback to before it.
--   G  536's fixed parts: the grants on audit_logs exactly
--      {postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=r/postgres} and no
--      column grant; write_audit and write_audit_ex callable by their owner alone; the function's
--      md5 and grants; the four triggers on audit_logs (both new ones enabled ALWAYS, before
--      invoice_date_audit_lock by name); installed here, only the new function and the two
--      helpers' grants differ from before among the functions.
--   U  scripts/audit-log/undo-536.sql puts back exactly what was there (every function's text and
--      grants, the table's grants, the triggers), after which the secret key deletes an entry
--      again; the undo a second time refuses; 536 again makes exactly what it made.
--   M  536 a second time refuses ("536 is already in") and changes nothing.
--
-- Disposable local database only. Everything is rolled back except one made-up entry (table_name
-- 'm536_suite', action 'm536_older_entry') written and committed before the transaction, so that
-- an entry older than it exists; the file removes it again at the end (switching the row trigger
-- off for that one statement when 536 is in, in one transaction). Every name is invented
-- (M536-…, @example.invalid); phones are the fictional +61 491 570 nnn range.
-- Run it on a copy of production without 536 (it applies 536, then again); with
-- -v skip_install=1 where 536 is already in (U is skipped); with -v control=1 on a copy WITHOUT
-- 536 (it does not install it, skips G, U and M, and fails on exactly the checks 536 makes pass).
-- Every check runs, then the file fails if any did.
--   psql -X -v ON_ERROR_STOP=1 -f scripts/audit-log/tests/audit-log-keeps-every-entry-536.sql
\set ON_ERROR_STOP on
-- Which mode, checked before anything is written.
select to_regprocedure('public.audit_logs_keep_every_entry()') is not null as had536 \gset
\if :{?control}
\if :had536
\echo control: 536 is in on this copy; run -v control=1 on a copy without it
select 1/0;
\endif
\set mode control
\elif :{?skip_install}
\if :had536
\else
\echo 536 is not in: run without -v skip_install
select 1/0;
\endif
\set mode skip
\elif :had536
\echo 536 is already in: run with -v skip_install=1
select 1/0;
\else
\set mode install
\endif
-- An entry committed before the test, unless a failed earlier run left one.
insert into public.audit_logs(table_name, record_id, action, new_data, actor_role, module)
select 'm536_suite', gen_random_uuid(), 'm536_older_entry', '{"m536": "older"}'::jsonb, 'owner', 'm536'
 where not exists (select 1 from public.audit_logs where table_name = 'm536_suite' and action = 'm536_older_entry');
begin;
set local lock_timeout = '10s';
set local statement_timeout = '300s';
-- Before: every function's text and rights, the table's grants and its triggers.
create temp table fn0 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
create function pg_temp.trg_set() returns text language sql as $f$
  select string_agg(t.tgname || '|' || t.tgenabled::text || '|' || pg_get_triggerdef(t.oid), ';' order by t.tgname)
    from pg_trigger t where t.tgrelid = 'public.audit_logs'::regclass and not t.tgisinternal $f$;
create temp table tbl0 as select (select relacl::text from pg_class where oid = 'public.audit_logs'::regclass) as acl, pg_temp.trg_set() as trg;
select :'mode' = 'install' as by_us_now \gset
\if :by_us_now
\ir ../../../supabase/536_the_audit_log_keeps_every_entry.sql
\endif
create temp table fn1 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
create temp table tbl1 as select (select relacl::text from pg_class where oid = 'public.audit_logs'::regclass) as acl, pg_temp.trg_set() as trg;
select :'mode' = 'install' as by_us, :'mode' = 'control' as is_control \gset

create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.put(key text, val uuid) returns uuid language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v returning v $$;
create temp table sfx as select lower(substr(md5(gen_random_uuid()::text), 1, 6)) as s;
create function pg_temp.sfx() returns text language sql as $$ select s from sfx $$;

-- Sets who is asking: 'svc' (the secret key), 'pg' (the database owner), or a login's key.
create function pg_temp.become(who text) returns void language plpgsql as $f$
begin
  if who = 'svc' then
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'service_role', true);
    perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
    execute 'set local role service_role';
  elsif who = 'pg' then
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
    perform set_config('request.jwt.claims', '', true);
  else
    perform set_config('request.jwt.claim.sub', pg_temp.fx(who)::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(who), 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
  end if;
end $f$;
-- One statement as someone, KEPT: 'ok:<first column>', or 'ERR <sqlstate> <message>'.
create function pg_temp.as_(who text, q text) returns text language plpgsql as $f$
declare v text; s text; m text;
begin
  begin
    perform pg_temp.become(who);
    execute q into v;
    execute 'reset role';
    return 'ok:' || coalesce(v, '');
  exception when others then
    get stacked diagnostics s = returned_sqlstate, m = message_text;
    execute 'reset role';
    return 'ERR ' || s || ' ' || m;
  end;
end $f$;
-- One statement as someone, ALWAYS ROLLED BACK (what it did, if it went through, does not stay):
-- 'ok:<first column>', or 'ERR <sqlstate> <message>'.
create function pg_temp.try_(who text, q text) returns text language plpgsql as $f$
declare v text; s text; m text;
begin
  begin
    perform pg_temp.become(who);
    if q ~* '^\s*(select|with)\M' then execute q into v; else execute q; v := 'done'; end if;
    raise exception 'm536 roll back' using errcode = 'ZZ536';
  exception when others then
    get stacked diagnostics s = returned_sqlstate, m = message_text;
    execute 'reset role';
    if s = 'ZZ536' then return 'ok:' || coalesce(v, ''); end if;
    return 'ERR ' || s || ' ' || m;
  end;
end $f$;
-- A write as someone, rolled back: how many rows it changed ('ok:<n>'), or the error.
create function pg_temp.n(who text, dml text) returns text language sql as
$$ select pg_temp.try_(who, format('with x as (%s returning 1) select count(*)::text from x', dml)) $$;
-- Refused with "permission denied" (42501, the privilege; not the trigger's sentence).
create function pg_temp.denied(t text) returns boolean language sql as
$$ select t like 'ERR 42501 permission denied%' $$;

-- The audit entries written since the last mark.
create temp table seen(id uuid primary key);
create function pg_temp.mark() returns void language sql as
$$ insert into seen select id from public.audit_logs on conflict do nothing $$;
create function pg_temp.acts() returns text language sql as
$$ select coalesce(string_agg(a.table_name || '/' || a.action || '/' || coalesce(a.actor_role, '-'), ' ; ' order by a.table_name, a.action), '')
     from public.audit_logs a where not exists (select 1 from seen s where s.id = a.id) $$;

-- ═════ Fixtures (invented), as the database owner ═════
do $fx$
declare r record; u uuid; s text := pg_temp.sfx();
begin
  for r in select * from (values ('own', 'owner'), ('stf', 'staff')) t(k, role) loop
    insert into auth.users(id, email, email_confirmed_at)
    values (gen_random_uuid(), 'm536-' || r.k || '-' || s || '@example.invalid', now()) returning id into u;
    insert into public.profiles(id, full_name, email, role, is_active, personal_phone)
    values (u, 'M536 ' || r.k, 'm536-' || r.k || '-' || s || '@example.invalid', r.role::public.user_role, true,
            '+6149157053' || case r.k when 'own' then '1' else '2' end);
    perform pg_temp.put(r.k, u);
  end loop;
  insert into public.stores(name, code, paynow_uen) values ('M536 Store A', 'M536-A-' || s, 'UEN-536-A') returning id into u; perform pg_temp.put('sa', u);
  insert into public.user_store_assignments(user_id, store_id) values (pg_temp.fx('stf'), pg_temp.fx('sa'));
  perform pg_temp.put('old', (select id from public.audit_logs where table_name = 'm536_suite' and action = 'm536_older_entry' limit 1));
  -- An entry written in this very transaction.
  insert into public.audit_logs(table_name, record_id, action, new_data, actor_role, module)
  values ('m536_suite', gen_random_uuid(), 'm536_new_entry', '{"m536": "new"}'::jsonb, 'owner', 'm536') returning id into u;
  perform pg_temp.put('new', u);
end $fx$;
select pg_temp.check(pg_temp.fx('old') is not null and pg_temp.fx('new') is not null, 'setup: an entry committed before this transaction and one written in it');

-- ═════ S  The secret key ═════
do $s$
declare t text;
begin
  t := pg_temp.n('svc', 'insert into public.audit_logs(table_name, action) values (''invoices'', ''invoice_cancelled'')');
  perform pg_temp.check(pg_temp.denied(t), 'S1 the secret key cannot add an entry straight to the table: ' || t);
  t := pg_temp.n('svc', format('update public.audit_logs set action = ''forged'' where id = %L', pg_temp.fx('old')));
  perform pg_temp.check(pg_temp.denied(t), 'S2 the secret key cannot change an entry: ' || t);
  t := pg_temp.n('svc', format('delete from public.audit_logs where id = %L', pg_temp.fx('old')));
  perform pg_temp.check(pg_temp.denied(t), 'S3 the secret key cannot delete an entry (the report''s local check): ' || t);
  t := pg_temp.try_('svc', 'truncate public.audit_logs');
  perform pg_temp.check(pg_temp.denied(t), 'S4 the secret key cannot empty the log: ' || t);
  t := pg_temp.try_('svc', 'select public.write_audit(''invoices'', null, ''invoice_cancelled'', null, ''{"forged": true}''::jsonb)::text');
  perform pg_temp.check(pg_temp.denied(t), 'S5 the secret key cannot call /rpc/write_audit: ' || t);
  t := pg_temp.try_('svc', 'select public.write_audit_ex(''invoices'', null, ''invoice_cancelled'', null, ''{"forged": true}''::jsonb, ''invoices'', ''forged'')::text');
  perform pg_temp.check(pg_temp.denied(t), 'S6 the secret key cannot call /rpc/write_audit_ex: ' || t);
  t := pg_temp.try_('svc', format('select count(*)::text from public.audit_logs where id in (%L, %L)', pg_temp.fx('old'), pg_temp.fx('new')));
  perform pg_temp.check(t = 'ok:2', 'S7 the secret key still reads the log: ' || t);
  t := pg_temp.try_('svc', 'merge into public.audit_logs a using (select 1) x on false when not matched then insert (table_name, action) values (''invoices'', ''forged'')');
  perform pg_temp.check(pg_temp.denied(t), 'S8 the secret key cannot add an entry by MERGE either: ' || t);
end $s$;

-- ═════ A  Signed-in logins ═════
do $a$
declare t text; w text;
begin
  foreach w in array array['own', 'stf'] loop
    t := pg_temp.n(w, 'insert into public.audit_logs(table_name, action) values (''invoices'', ''invoice_cancelled'')');
    perform pg_temp.check(pg_temp.denied(t), 'A1 ' || w || ' cannot add an entry straight to the table: ' || t);
    t := pg_temp.n(w, format('update public.audit_logs set action = ''forged'' where id = %L', pg_temp.fx('old')));
    perform pg_temp.check(pg_temp.denied(t), 'A2 ' || w || ' cannot change an entry: ' || t);
    t := pg_temp.n(w, format('delete from public.audit_logs where id = %L', pg_temp.fx('old')));
    perform pg_temp.check(pg_temp.denied(t), 'A3 ' || w || ' cannot delete an entry: ' || t);
    t := pg_temp.try_(w, 'truncate public.audit_logs');
    perform pg_temp.check(pg_temp.denied(t), 'A4 ' || w || ' cannot empty the log: ' || t);
    t := pg_temp.try_(w, 'select public.write_audit(''invoices'', null, ''invoice_cancelled'', null, null)::text');
    perform pg_temp.check(pg_temp.denied(t), 'A5 ' || w || ' cannot call write_audit: ' || t);
    t := pg_temp.try_(w, 'select public.write_audit_ex(''invoices'', null, ''invoice_cancelled'', null, null)::text');
    perform pg_temp.check(pg_temp.denied(t), 'A6 ' || w || ' cannot call write_audit_ex: ' || t);
  end loop;
  t := pg_temp.try_('own', format('select count(*)::text from public.audit_logs where id in (%L, %L)', pg_temp.fx('old'), pg_temp.fx('new')));
  perform pg_temp.check(t = 'ok:2', 'A7 an Owner still reads the log (its rule "read audit logs"): ' || t);
end $a$;

-- ═════ W  Entries are still written ═════
do $w$
declare t text;
begin
  perform pg_temp.mark();
  t := pg_temp.as_('own', format('select public.soft_delete_store(%L)::text', pg_temp.fx('sa')));
  perform pg_temp.check(t like 'ok:%' and pg_temp.acts() = 'stores/store_deleted/owner',
    'W1 an Owner''s Delete on the Stores page writes its own entry: ' || t || ' / ' || pg_temp.acts());
  perform pg_temp.mark();
  t := pg_temp.as_('own', format('select public.restore_store(%L)::text', pg_temp.fx('sa')));
  perform pg_temp.check(t like 'ok:%' and pg_temp.acts() = 'stores/store_restored/owner',
    'W2 an Owner''s Restore writes its own entry: ' || t || ' / ' || pg_temp.acts());
  perform pg_temp.mark();
  t := pg_temp.as_('svc', format('select public.soft_delete_store(%L)::text', pg_temp.fx('sa')))
       || ' ' || pg_temp.as_('svc', format('select public.restore_store(%L)::text', pg_temp.fx('sa')));
  perform pg_temp.check(t like 'ok:% ok:%' and pg_temp.acts() = 'stores/store_deleted/- ; stores/store_restored/-',
    'W3 a server function the secret key calls (soft_delete_store, restore_store) writes its entries: ' || t || ' / ' || pg_temp.acts());
  perform pg_temp.mark();
  t := pg_temp.as_('svc', format('update public.stores set paynow_uen = ''UEN-536-SVC'' where id = %L returning 1', pg_temp.fx('sa')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.acts() = 'stores/store_updated/service_role',
    'W4 532: the secret key''s change made straight on a store is recorded: ' || t || ' / ' || pg_temp.acts());
  perform pg_temp.mark();
  t := pg_temp.as_('own', format('update public.stores set paynow_uen = ''UEN-536-OWN'' where id = %L returning 1', pg_temp.fx('sa')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.acts() = 'stores/store_updated/owner',
    'W5 532: an Owner''s change made straight on a store is recorded: ' || t || ' / ' || pg_temp.acts());
  perform pg_temp.mark();
  t := pg_temp.as_('stf', format('update public.profiles set personal_phone = ''+61491570539'' where id = %L returning 1', pg_temp.fx('stf')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.acts() = 'profiles/staff_profile_updated/staff',
    'W6 532: a Staff member''s own phone, changed straight on the table, is recorded: ' || t || ' / ' || pg_temp.acts());
  perform pg_temp.mark();
  t := pg_temp.as_('pg', 'select public.write_audit(''m536_suite'', null, ''m536_owner_call'', null, null)::text');
  perform pg_temp.check(t like 'ok:%' and pg_temp.acts() = 'm536_suite/m536_owner_call/-',
    'W7 a function running as the owner still writes through write_audit: ' || t || ' / ' || pg_temp.acts());
end $w$;

-- ═════ O  The database owner ═════
do $o$
declare t text;
begin
  t := pg_temp.n('pg', format('update public.audit_logs set created_at = created_at - interval ''1 day'' where id = %L', pg_temp.fx('old')));
  perform pg_temp.check(t = 'ERR 42501 The Audit Log keeps every entry: it cannot be changed.',
    'O1 the owner cannot change an entry written before this transaction: ' || t);
  t := pg_temp.n('pg', format('delete from public.audit_logs where id = %L', pg_temp.fx('old')));
  perform pg_temp.check(t = 'ERR 42501 The Audit Log keeps every entry: it cannot be deleted.',
    'O2 the owner cannot delete an entry written before this transaction: ' || t);
  t := pg_temp.n('pg', format('update public.audit_logs set created_at = created_at - interval ''1 day'' where id = %L', pg_temp.fx('new')));
  perform pg_temp.check(t = 'ERR 42501 The Audit Log keeps every entry: it cannot be changed.',
    'O3 no exception for an entry written in this same transaction (changed): ' || t);
  t := pg_temp.n('pg', format('delete from public.audit_logs where id = %L', pg_temp.fx('new')));
  perform pg_temp.check(t = 'ERR 42501 The Audit Log keeps every entry: it cannot be deleted.',
    'O4 no exception for an entry written in this same transaction (deleted): ' || t);
  t := pg_temp.try_('pg', 'truncate public.audit_logs');
  perform pg_temp.check(t = 'ERR 42501 The Audit Log keeps every entry: it cannot be emptied.',
    'O5 the owner cannot empty the log: ' || t);
  t := pg_temp.try_('pg', 'truncate public.profiles cascade');
  perform pg_temp.check(t = 'ERR 42501 The Audit Log keeps every entry: it cannot be emptied.',
    'O6 emptying profiles with cascade does not empty the log (it is refused): ' || t);
  t := pg_temp.try_('pg', 'truncate public.stores cascade');
  perform pg_temp.check(t = 'ERR 42501 The Audit Log keeps every entry: it cannot be emptied.',
    'O7 emptying stores with cascade does not empty the log (it is refused): ' || t);
  t := pg_temp.try_('pg', format('merge into public.audit_logs a using (select %L::uuid as id) x on a.id = x.id when matched then delete', pg_temp.fx('old')));
  perform pg_temp.check(t = 'ERR 42501 The Audit Log keeps every entry: it cannot be deleted.',
    'O8 nor by MERGE: ' || t);
end $o$;
-- With session_replication_role = replica (ordinary triggers are skipped), the two still fire.
savepoint r1;
set local session_replication_role = replica;
select pg_temp.n('pg', format('delete from public.audit_logs where id = %L', pg_temp.fx('old'))) as r_del \gset
select pg_temp.try_('pg', 'truncate public.audit_logs') as r_trunc \gset
rollback to savepoint r1;
select pg_temp.check(:'r_del' = 'ERR 42501 The Audit Log keeps every entry: it cannot be deleted.'
  and :'r_trunc' = 'ERR 42501 The Audit Log keeps every entry: it cannot be emptied.',
  'O9 with session_replication_role = replica the owner still cannot delete or empty: ' || :'r_del' || ' / ' || :'r_trunc');
select pg_temp.check(current_setting('session_replication_role') = 'origin', 'O9b session_replication_role is back to origin');
select pg_temp.check((select count(*) from public.audit_logs where id in (pg_temp.fx('old'), pg_temp.fx('new'))) = 2,
  'O10 both entries are still there, as written');

-- ═════ D  A suite back-dating its own entries switches the row trigger off in its own transaction ═════
savepoint d1;
do $m536$ begin if exists (select 1 from pg_trigger where tgrelid = to_regclass('public.audit_logs') and tgname = 'audit_logs_keep_every_entry') then alter table public.audit_logs disable trigger audit_logs_keep_every_entry; end if; end $m536$;  -- 536: this suite back-dates or removes its own Audit Log rows; the trigger comes back with the rollback
select pg_temp.n('pg', format('update public.audit_logs set created_at = created_at - interval ''2 minutes'' where id = %L', pg_temp.fx('new'))) as d_upd \gset
select pg_temp.try_('pg', 'truncate public.audit_logs') as d_trunc \gset
rollback to savepoint d1;
select pg_temp.check(:'d_upd' = 'ok:1', 'D1 with the row trigger switched off in the suite''s own transaction, it back-dates its own entry: ' || :'d_upd');
select pg_temp.check(:'d_trunc' = 'ERR 42501 The Audit Log keeps every entry: it cannot be emptied.',
  'D2 the log still cannot be emptied meanwhile (that trigger is not switched off): ' || :'d_trunc');
select pg_temp.check((select tgenabled from pg_trigger where tgrelid = 'public.audit_logs'::regclass and tgname = 'audit_logs_keep_every_entry') = 'A',
  'D3 after the rollback to before it, the row trigger is enabled ALWAYS again');

-- ═════ G  536's fixed parts ═════
\if :is_control
\echo NOTE  G, U and M are skipped (control: 536 is not in)
\else
select pg_temp.check((select relacl::text from pg_class where oid = 'public.audit_logs'::regclass)
    = '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=r/postgres}'
  and not exists (select 1 from pg_attribute where attrelid = 'public.audit_logs'::regclass and attnum > 0 and attacl is not null),
  'G1 the grants on audit_logs are exactly 536''s, and no column has a grant of its own');
select pg_temp.check(not has_table_privilege('anon', 'public.audit_logs', 'select,insert,update,delete,truncate,references,trigger,maintain')
  and not has_table_privilege('authenticated', 'public.audit_logs', 'insert,update,delete,truncate,references,trigger,maintain')
  and not has_table_privilege('service_role', 'public.audit_logs', 'insert,update,delete,truncate,references,trigger,maintain')
  and not has_table_privilege('public', 'public.audit_logs', 'select,insert,update,delete,truncate,references,trigger,maintain')
  and has_table_privilege('authenticated', 'public.audit_logs', 'select') and has_table_privilege('service_role', 'public.audit_logs', 'select'),
  'G2 only SELECT is left, for authenticated and the service role');
select pg_temp.check((select string_agg(fn || '=' || acl, ';' order by fn collate "C") from fn1
                       where fn in ('write_audit(text,uuid,text,jsonb,jsonb)', 'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'audit_logs_keep_every_entry()'))
  = 'audit_logs_keep_every_entry()={postgres=X/postgres};write_audit(text,uuid,text,jsonb,jsonb)={postgres=X/postgres};write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)={postgres=X/postgres}',
  'G3 write_audit, write_audit_ex and the trigger function are callable by their owner alone');
select pg_temp.check((select md5 from fn1 where fn = 'audit_logs_keep_every_entry()') = 'a4fdc5a8c602e0edf2420f99b9f06584'
  and (select p.prosecdef from pg_proc p where p.oid = 'public.audit_logs_keep_every_entry()'::regprocedure) = false,
  'G4 the trigger function is 536''s (md5 a4fdc5a8…), SECURITY INVOKER');
select pg_temp.check((select string_agg(tgname || '|' || tgenabled::text, ';' order by tgname) from pg_trigger
                       where tgrelid = 'public.audit_logs'::regclass and not tgisinternal)
  = 'audit_logs_fill_module|O;audit_logs_keep_every_entry|A;audit_logs_never_emptied|A;invoice_date_audit_lock|O',
  'G5 the four triggers on audit_logs; both of 536''s enabled ALWAYS, and named before invoice_date_audit_lock');
\if :by_us
select pg_temp.check((select string_agg(coalesce(a.fn, b.fn), ', ' order by coalesce(a.fn, b.fn) collate "C")
                        from fn0 a full join fn1 b using (fn) where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl)
  = 'audit_logs_keep_every_entry(), write_audit(text,uuid,text,jsonb,jsonb), write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
  'G6 installed here, only the new function and the two helpers'' grants differ among the functions');

-- ═════ U  The undo ═════
\ir ../undo-536.sql
select pg_temp.check(not exists (select 1 from (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) a
                                  full join fn0 b using (fn) where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl)
  and (select relacl::text from pg_class where oid = 'public.audit_logs'::regclass) = (select acl from tbl0)
  and pg_temp.trg_set() = (select trg from tbl0),
  'U1 the undo puts back exactly what was there: every function and its grants, the table''s grants, the triggers');
select pg_temp.n('svc', format('delete from public.audit_logs where id = %L', pg_temp.fx('old'))) as u_del \gset
select pg_temp.check(:'u_del' = 'ok:1', 'U2 after the undo the secret key deletes an entry again (rolled back): ' || :'u_del');
savepoint u3;
\set ON_ERROR_STOP off
\ir ../undo-536.sql
\set ON_ERROR_STOP on
rollback to savepoint u3;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'undo 536: public.audit_logs_keep_every_entry() is not there%', 'U3 the undo a second time refuses: ' || :'LAST_ERROR_MESSAGE');
\ir ../../../supabase/536_the_audit_log_keeps_every_entry.sql
select pg_temp.check(not exists (select 1 from (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) a
                                  full join fn1 b using (fn) where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl)
  and (select relacl::text from pg_class where oid = 'public.audit_logs'::regclass) = (select acl from tbl1)
  and pg_temp.trg_set() = (select trg from tbl1),
  'U4 536 after the undo makes exactly what it made the first time');
\else
\echo NOTE  U is skipped (536 was not installed by this file)
\endif
-- ═════ M  536 a second time ═════
savepoint m1;
\set ON_ERROR_STOP off
\ir ../../../supabase/536_the_audit_log_keeps_every_entry.sql
\set ON_ERROR_STOP on
rollback to savepoint m1;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '536 is already in on this database%', 'M1 536 a second time refuses: ' || :'LAST_ERROR_MESSAGE');
select pg_temp.check((select relacl::text from pg_class where oid = 'public.audit_logs'::regclass) = (select acl from tbl1)
  and pg_temp.trg_set() = (select trg from tbl1), 'M2 and changes nothing');
\endif

select count(*) as n_failed, coalesce(string_agg(msg, E'\n' order by n), '') as failed_list from failed \gset
rollback;
-- The entry committed for the test is removed again (536's row trigger switched off for this one
-- statement, and ALWAYS again before the commit).
begin;
do $clean$
declare v_on boolean := exists (select 1 from pg_trigger where tgrelid = 'public.audit_logs'::regclass and tgname = 'audit_logs_keep_every_entry');
begin
  if v_on then alter table public.audit_logs disable trigger audit_logs_keep_every_entry; end if;
  delete from public.audit_logs where table_name = 'm536_suite' and action = 'm536_older_entry';
  if v_on then alter table public.audit_logs enable always trigger audit_logs_keep_every_entry; end if;
end $clean$;
commit;
\if :is_control
\echo control: :n_failed checks failed without 536 (each is one 536 makes pass)
\echo :failed_list
\else
select :n_failed > 0 as any_failed \gset
\if :any_failed
\echo :n_failed check(s) failed:
\echo :failed_list
select 1/0 as failed;
\else
\echo ALL PASSED
\endif
\endif
