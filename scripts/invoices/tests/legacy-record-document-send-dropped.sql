-- The seven-argument record_document_send is dropped (388).
--
--   C1 The overload installed below is production's, byte for byte (the md5
--      388 guards on), granted to staff and not to anon, as it was.
--   C2 Beside the nine-argument record_document_send no call reaches it:
--      three or seven arguments, by position or by name, are refused as
--      ambiguous, while the application's call (nine named arguments) reaches
--      the nine-argument one.
--   C3 388 refuses a version of it that is not production's, and changes
--      nothing then.
--   C4 388 drops it, and only it: every other public function keeps its body
--      and its grants, and one record_document_send is left.
--   C5 A call with three or seven arguments now reaches the nine-argument
--      function, and the application's call still does.
--   C6 Running 388 again changes nothing.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Works whether or not the database already has
-- 388: the old overload is installed after "begin;" either way.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
-- Every public function as signature, body and grants.
create function pg_temp.fns() returns table(fn text, h text) language sql as
$$ select p.oid::regprocedure::text, md5(p.prosrc) || ':' || coalesce(p.proacl::text, '')
     from pg_proc p where p.pronamespace = 'public'::regnamespace $$;
-- The SQLSTATE and message a call ends with ('' when it returns).
create function pg_temp.outcome(sql text) returns text language plpgsql as
$$begin execute sql; return '';
exception when others then return sqlstate || ' ' || sqlerrm; end$$;

-- Production's record_document_send(text,text,text,uuid,uuid,text,text), read
-- 3 Oct 2026, with its grants.
create or replace function public.record_document_send(p_doc_kind text, p_doc_no text, p_channel text, p_doc_id uuid default null::uuid, p_customer_id uuid default null::uuid, p_sent_to text default null::text, p_pdf_path text default null::text)
returns uuid language plpgsql security definer set search_path to 'public' as $legacy$
declare v_id uuid;
begin
  insert into public.document_sends (doc_kind, doc_id, doc_no, customer_id, channel, sent_to, pdf_path, sent_by)
  values (p_doc_kind, p_doc_id, p_doc_no, p_customer_id, p_channel, p_sent_to, p_pdf_path, auth.uid())
  returning id into v_id;
  return v_id;
end $legacy$;
revoke all on function public.record_document_send(text,text,text,uuid,uuid,text,text) from public;
grant execute on function public.record_document_send(text,text,text,uuid,uuid,text,text) to authenticated, service_role;

select pg_temp.check(
  (select md5(prosrc) from pg_proc where oid = 'public.record_document_send(text,text,text,uuid,uuid,text,text)'::regprocedure)
    = 'f6807793ccb4f40fe53956bf1e95f36e'
  and has_function_privilege('authenticated', 'public.record_document_send(text,text,text,uuid,uuid,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.record_document_send(text,text,text,uuid,uuid,text,text)', 'execute'),
  'C1 the old record_document_send is production''s, callable by staff and not by anon');

create temp table calls(k text primary key, sql text);
insert into calls values
  ('three', $c$select public.record_document_send('invoice', 'TEST-0001', 'download')$c$),
  ('seven', $c$select public.record_document_send('invoice', 'TEST-0001', 'download', null::uuid, null::uuid, null::text, null::text)$c$),
  ('named', $c$select public.record_document_send(p_doc_kind => 'invoice', p_doc_no => 'TEST-0001', p_channel => 'download',
     p_doc_id => null, p_customer_id => null, p_sent_to => null, p_pdf_path => null)$c$);
-- What src/lib/sendDoc.ts (logSend) sends: all nine, by name.
create temp table app_call as select $c$select public.record_document_send(p_doc_kind => 'invoice', p_doc_no => 'TEST-0001',
  p_channel => 'download', p_doc_id => null, p_customer_id => null, p_sent_to => null, p_pdf_path => null,
  p_status => 'sent', p_error => null)$c$ as sql;

select pg_temp.check(
  (select bool_and(pg_temp.outcome(sql) like '42725 function public.record_document_send(%) is not unique') from calls)
  and to_regproc('public.record_document_send') is null
  and (select pg_temp.outcome(sql) not like '42725 %' and pg_temp.outcome(sql) not like '42883 %' from app_call),
  'C2 beside the nine-argument one, no call with three or seven arguments, by position or by name, reaches it; the application''s call reaches the nine-argument one');

create temp table before388 as select * from pg_temp.fns();

-- C3: a version that is not production's.
\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on
savepoint c3;
do $$begin execute regexp_replace(pg_get_functiondef('public.record_document_send(text,text,text,uuid,uuid,text,text)'::regprocedure),
  '\$function\$\s*$', E'-- changed\n$function$'); end$$;
\echo 'C3: the ERROR below is expected (388 refusing a changed record_document_send)'
\ir ../../../supabase/388_drop_legacy_record_document_send_overload.sql
\set c3_error :LAST_ERROR_MESSAGE
select count(*) = 2 as c3_both from pg_proc where pronamespace = 'public'::regnamespace and proname = 'record_document_send' \gset
rollback to savepoint c3;
release savepoint c3;
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP on
select pg_temp.check(:'c3_error' like '388: record_document_send(text,text,text,uuid,uuid,text,text) is not the version this was tested against (md5 %)'
    and :'c3_both',
  'C3 388 refuses a record_document_send that is not production''s, and leaves both');

-- C4: the real thing.
set client_min_messages = warning;
\ir ../../../supabase/388_drop_legacy_record_document_send_overload.sql
reset client_min_messages;
select pg_temp.check(
  to_regprocedure('public.record_document_send(text,text,text,uuid,uuid,text,text)') is null
  and (select array_agg(fn) from (select fn, h from before388 except select fn, h from pg_temp.fns()) gone)
      = array['record_document_send(text,text,text,uuid,uuid,text,text)']
  and not exists (select fn, h from pg_temp.fns() except select fn, h from before388)
  and to_regproc('public.record_document_send')::oid = 'public.record_document_send(text,text,text,uuid,uuid,text,text,text,text)'::regprocedure::oid,
  'C4 388 drops the old record_document_send and nothing else: every other public function keeps its body and grants, and one record_document_send is left');

select pg_temp.check(
  (select bool_and(pg_temp.outcome(sql) not like '42725 %' and pg_temp.outcome(sql) not like '42883 %')
     from (select sql from calls union all select sql from app_call) c),
  'C5 a call with three or seven arguments, by position or by name, now reaches the nine-argument record_document_send, and the application''s call still does');

create temp table after388 as select * from pg_temp.fns();
set client_min_messages = warning;
\ir ../../../supabase/388_drop_legacy_record_document_send_overload.sql
reset client_min_messages;
select pg_temp.check(
  not exists ((select * from after388 except select * from pg_temp.fns())
              union all (select * from pg_temp.fns() except select * from after388)),
  'C6 running 388 again changes nothing');

do $$ begin
  if exists (select 1 from failed) then
    raise exception 'FAIL: % check(s) failed: %', (select count(*) from failed), (select string_agg(msg, ' | ' order by n) from failed); end if;
  raise notice 'ALL PASS: the seven-argument record_document_send is dropped (388)';
end $$;
rollback;
