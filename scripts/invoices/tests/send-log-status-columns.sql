-- The send log gains its status and error_text columns (389).
--
--   C1 On a table built from 93 as it stands (this database's), 389 changes
--      nothing: not the table, not any public function.
--   C2 Rebuilt below as production's (read 3 Oct 2026, after 388):
--      document_sends without status, error_text and their check, beside the
--      one record_document_send, byte for byte, with its grants.
--   C3 There a staff member's nine-argument call, the one logSend makes,
--      reaches the 9-argument function and fails with 42703: production's
--      failure.
--   C4 389 refuses a status column of another shape, and changes nothing then.
--   C5 389 refuses a status check of another definition, and changes nothing
--      then.
--   C6 389 gives production's table 93's columns, defaults and check, and
--      touches no public function.
--   C7 The staff member's call now records a send, as 'sent' or as 'failed'
--      with its reason, sent by them, and readable by them; a status other
--      than 'sent' or 'failed' is refused.
--   C8 Running 389 again changes nothing.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. The staff member and the documents are invented.
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
-- document_sends as columns (by name, so column order does not count) and checks.
create function pg_temp.shape() returns text language sql as
$$ select (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
                             || case when a.attnotnull then ' not null' else '' end
                             || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), ''), ', ' order by a.attname)
             from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
            where a.attrelid = 'public.document_sends'::regclass and a.attnum > 0 and not a.attisdropped)
     || ' | ' ||
     (select string_agg(conname || ' ' || pg_get_constraintdef(oid), ', ' order by conname)
        from pg_constraint where conrelid = 'public.document_sends'::regclass) $$;
-- The SQLSTATE and message a call ends with ('' when it returns).
create function pg_temp.outcome(sql text) returns text language plpgsql as
$$begin execute sql; return '';
exception when others then return sqlstate || ' ' || sqlerrm; end$$;
grant execute on function pg_temp.outcome(text) to authenticated;

-- 406 made record_document_send refuse anyone but active staff, as its first
-- statement. This file tests 389, so it runs against the body 389 met
-- (production's from 389 to 406), put back here inside the transaction; on a
-- database before 406 this changes nothing.
CREATE OR REPLACE FUNCTION public.record_document_send(p_doc_kind text, p_doc_no text, p_channel text, p_doc_id uuid DEFAULT NULL::uuid, p_customer_id uuid DEFAULT NULL::uuid, p_sent_to text DEFAULT NULL::text, p_pdf_path text DEFAULT NULL::text, p_status text DEFAULT 'sent'::text, p_error text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;
begin
  insert into public.document_sends (doc_kind, doc_id, doc_no, customer_id, channel,
    sent_to, pdf_path, status, error_text, sent_by)
  values (p_doc_kind, p_doc_id, p_doc_no, p_customer_id, p_channel,
    p_sent_to, p_pdf_path, coalesce(p_status,'sent'), p_error, auth.uid())
  returning id into v_id;
  return v_id;
end $function$;

-- ── C1: on 93's table, 389 is a no-op ──────────────────────────────────────
create temp table shape93 as select pg_temp.shape() s;
create temp table fns93 as select * from pg_temp.fns();
set client_min_messages = warning;
\ir ../../../supabase/389_send_log_status_columns.sql
reset client_min_messages;
select pg_temp.check(
  (select s from shape93) like '%error_text text, %status text not null default ''sent''::text%document_sends_status_check CHECK ((status = ANY (ARRAY[''sent''::text, ''failed''::text])))%'
  and pg_temp.shape() = (select s from shape93)
  and not exists ((select * from fns93 except select * from pg_temp.fns())
                  union all (select * from pg_temp.fns() except select * from fns93)),
  'C1 on a table built from 93 as it stands, 389 changes nothing');

-- ── C2: production's table and functions ───────────────────────────────────
alter table public.document_sends drop constraint document_sends_status_check,
  drop column status, drop column error_text;

-- 388 (applied to production 3 Oct 2026) dropped the 7-argument form; a
-- database without 388 is brought to the same state.
drop function if exists public.record_document_send(text,text,text,uuid,uuid,text,text);

select pg_temp.check(
  (select string_agg(attname, ',' order by attnum) from pg_attribute
    where attrelid = 'public.document_sends'::regclass and attnum > 0 and not attisdropped)
    = 'id,doc_kind,doc_id,doc_no,customer_id,channel,sent_to,pdf_path,sent_by,created_at'
  and not exists (select 1 from pg_constraint where conrelid = 'public.document_sends'::regclass and conname = 'document_sends_status_check')
  and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'record_document_send') = 1
  and (select md5(prosrc) from pg_proc where oid = 'public.record_document_send(text,text,text,uuid,uuid,text,text,text,text)'::regprocedure)
      = '0a7b7f0068f4dd59a76ffdece443bcb9'
  and has_function_privilege('authenticated', 'public.record_document_send(text,text,text,uuid,uuid,text,text,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.record_document_send(text,text,text,uuid,uuid,text,text,text,text)', 'execute'),
  'C2 document_sends and record_document_send are production''s, granted to staff and not to anon');

-- An invented staff member, signed in.
insert into auth.users(id, email, email_confirmed_at)
  values ('00000000-0000-4000-8000-000000000389', 'staff.sendlog@tests.invalid', now());
insert into public.profiles(id, full_name, email, role)
  values ('00000000-0000-4000-8000-000000000389', 'Send Log Staff', 'staff.sendlog@tests.invalid', 'staff');
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000389","role":"authenticated"}', true);

-- What logSend sends: all nine arguments, by name.
create temp table calls(k text primary key, sql text);
insert into calls values
  ('sent', $c$select public.record_document_send(p_doc_kind => 'invoice', p_doc_no => 'INV-TEST-0389', p_channel => 'whatsapp',
     p_doc_id => null, p_customer_id => null, p_sent_to => '6591234567',
     p_pdf_path => 'store-test/invoice/INV-TEST-0389.pdf', p_status => 'sent', p_error => null)$c$),
  ('failed', $c$select public.record_document_send(p_doc_kind => 'invoice', p_doc_no => 'INV-TEST-0390', p_channel => 'email',
     p_doc_id => null, p_customer_id => null, p_sent_to => 'ana.test@tests.invalid',
     p_pdf_path => null, p_status => 'failed', p_error => 'Could not upload the PDF: test')$c$),
  ('bounced', $c$select public.record_document_send(p_doc_kind => 'invoice', p_doc_no => 'INV-TEST-0391', p_channel => 'email',
     p_doc_id => null, p_customer_id => null, p_sent_to => 'ana.test@tests.invalid',
     p_pdf_path => null, p_status => 'bounced', p_error => null)$c$);
grant select on calls to authenticated;

-- ── C3: production's failure ───────────────────────────────────────────────
set local role authenticated;
select pg_temp.outcome((select sql from calls where k = 'sent')) as c3_outcome \gset
reset role;
select pg_temp.check(:'c3_outcome' = '42703 column "status" of relation "document_sends" does not exist'
    and not exists (select 1 from public.document_sends where doc_no like 'INV-TEST-03__'),
  'C3 before 389, the nine-argument call reaches the 9-argument function and fails with 42703, as in production');

create temp table before389 as select * from pg_temp.fns();
create temp table shapeprod as select pg_temp.shape() s;

-- ── C4: a status column of another shape ───────────────────────────────────
\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on
savepoint c4;
alter table public.document_sends add column status text;
\echo 'C4: the ERROR below is expected (389 refusing a status column of another shape)'
\ir ../../../supabase/389_send_log_status_columns.sql
\set c4_error :LAST_ERROR_MESSAGE
select pg_temp.shape() as c4_shape \gset
rollback to savepoint c4;
release savepoint c4;
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP on
select pg_temp.check(:'c4_error' = '389: document_sends.status is "text", not 93''s "text not null default ''sent''::text"'
    and :'c4_shape' not like '%error_text%' and :'c4_shape' not like '%status_check%',
  'C4 389 refuses a status column of another shape, and adds nothing then');

-- ── C5: a status check of another definition ───────────────────────────────
\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on
savepoint c5;
alter table public.document_sends add column status text not null default 'sent',
  add constraint document_sends_status_check check (status in ('sent', 'failed', 'queued'));
\echo 'C5: the ERROR below is expected (389 refusing a status check of another definition)'
\ir ../../../supabase/389_send_log_status_columns.sql
\set c5_error :LAST_ERROR_MESSAGE
select pg_temp.shape() as c5_shape \gset
rollback to savepoint c5;
release savepoint c5;
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP on
select pg_temp.check(:'c5_error' like '389: document_sends_status_check is "CHECK (%queued%)", not 93''s check on status'
    and :'c5_shape' not like '%error_text%',
  'C5 389 refuses a status check of another definition, and adds nothing then');

select pg_temp.check(pg_temp.shape() = (select s from shapeprod),
  'C4/C5 left production''s table as it was');

-- ── C6: the real thing ─────────────────────────────────────────────────────
set client_min_messages = warning;
\ir ../../../supabase/389_send_log_status_columns.sql
reset client_min_messages;
select pg_temp.check(
  pg_temp.shape() = (select s from shape93)
  and not exists ((select * from before389 except select * from pg_temp.fns())
                  union all (select * from pg_temp.fns() except select * from before389)),
  'C6 389 gives production''s table 93''s columns, defaults and check, and no public function changes');

-- ── C7: the staff member's calls ───────────────────────────────────────────
set local role authenticated;
select pg_temp.outcome((select sql from calls where k = 'sent'))    as c7_sent,
       pg_temp.outcome((select sql from calls where k = 'failed'))  as c7_failed,
       pg_temp.outcome((select sql from calls where k = 'bounced')) as c7_bounced \gset
select coalesce(string_agg(doc_no || ' ' || channel || ' ' || status || ' ' || coalesce(error_text, '-') || ' '
                           || coalesce(pdf_path, '-') || ' ' || (sent_by = auth.uid())::text, ' | ' order by doc_no), '')
         as c7_seen
  from public.document_sends where doc_no like 'INV-TEST-03__' \gset
reset role;
select pg_temp.check(:'c7_sent' = '' and :'c7_failed' = ''
    and :'c7_seen' = 'INV-TEST-0389 whatsapp sent - store-test/invoice/INV-TEST-0389.pdf true'
                  || ' | INV-TEST-0390 email failed Could not upload the PDF: test - true',
  'C7 the staff member''s call records the send, as sent or as failed with its reason, sent by them, and they can read it back');
select pg_temp.check(:'c7_bounced' like '23514 new row for relation "document_sends" violates check constraint "document_sends_status_check"%',
  'C7 a status other than sent or failed is refused');

-- ── C8: again ──────────────────────────────────────────────────────────────
create temp table after389 as select * from pg_temp.fns();
create temp table shape389 as select pg_temp.shape() s;
set client_min_messages = warning;
\ir ../../../supabase/389_send_log_status_columns.sql
reset client_min_messages;
select pg_temp.check(
  pg_temp.shape() = (select s from shape389)
  and not exists ((select * from after389 except select * from pg_temp.fns())
                  union all (select * from pg_temp.fns() except select * from after389)),
  'C8 running 389 again changes nothing');

do $$ begin
  if exists (select 1 from failed) then
    raise exception 'FAIL: % check(s) failed: %', (select count(*) from failed), (select string_agg(msg, ' | ' order by n) from failed); end if;
  raise notice 'ALL PASS: the send log gains its status and error_text columns (389)';
end $$;
rollback;
