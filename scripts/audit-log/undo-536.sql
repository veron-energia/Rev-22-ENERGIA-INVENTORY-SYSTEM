-- UNDO of 536 (with the user's go-ahead). THIS IS THE DATABASE OWNER'S BYPASS of the append-only
-- Audit Log: run as postgres, it switches the rule off. It drops the triggers
-- audit_logs_keep_every_entry and audit_logs_never_emptied from public.audit_logs and the
-- function audit_logs_keep_every_entry() (md5 a4fdc5a8…), gives the service role back INSERT,
-- UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER and MAINTAIN on public.audit_logs (the grants are
-- then exactly {postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres},
-- as before 536), and gives it back EXECUTE on write_audit(text,uuid,text,jsonb,jsonb) and
-- write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text). Afterwards anything holding
-- the secret key can again change, delete, empty and add Audit Log entries, and the database owner
-- can change, delete or empty them (the security audit's M14 open again). Every entry written
-- while 536 was in stays.
--
-- It refuses, with nothing changed, unless the function, the two triggers (enabled ALWAYS) and
-- the grants are exactly 536's and no other trigger uses the function (so a later version is never
-- overwritten and nothing that now uses it is broken). One transaction, all or nothing; it waits
-- at most 5 seconds for a lock. The 536 row in supabase_migrations.schema_migrations stays; with
-- the user's OK, remove that one row (found by its name, 536_the_audit_log_keeps_every_entry) or
-- record this UNDO beside it.
do $undo$
declare
  c_fn_sig constant text := 'audit_logs_keep_every_entry()';
  c_fn_md5 constant text := 'a4fdc5a8c602e0edf2420f99b9f06584';
  c_fn_acl constant text := 'postgres=X/postgres';
  c_closed constant text[] := array[
    'write_audit(text,uuid,text,jsonb,jsonb)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)'];
  c_closed_acl_536 constant text := 'postgres=X/postgres';
  c_closed_acl_before constant text := 'postgres=X/postgres,service_role=X/postgres';
  c_tbl_acl_536 constant text := '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=r/postgres}';
  c_tbl_acl_before constant text := '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}';
  c_trg_536 constant text :=
    'audit_logs_keep_every_entry|A|CREATE TRIGGER audit_logs_keep_every_entry BEFORE DELETE OR UPDATE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION audit_logs_keep_every_entry()'
    || ';audit_logs_never_emptied|A|CREATE TRIGGER audit_logs_never_emptied BEFORE TRUNCATE ON public.audit_logs FOR EACH STATEMENT EXECUTE FUNCTION audit_logs_keep_every_entry()';
  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regclass('public.audit_logs') is null then
    raise exception 'undo 536: public.audit_logs is missing. Nothing was changed.'; end if;
  lock table public.audit_logs in share row exclusive mode;

  -- 1. Checks
  if to_regprocedure('public.' || c_fn_sig) is null then
    raise exception 'undo 536: public.% is not there; 536 is not in. Nothing was changed.', c_fn_sig; end if;
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_fn_sig))) <> c_fn_md5 then
    raise exception 'undo 536: public.% is not 536''s version (md5 %). Nothing was changed.', c_fn_sig,
      md5(pg_get_functiondef(to_regprocedure('public.' || c_fn_sig))); end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_fn_sig)) is distinct from c_fn_acl then
    raise exception 'undo 536: the grants of public.% are not 536''s. Nothing was changed.', c_fn_sig; end if;
  select string_agg(t.tgrelid::regclass::text || '.' || t.tgname, ', ') into d
    from pg_trigger t where t.tgfoid = to_regprocedure('public.' || c_fn_sig)
     and not (t.tgrelid = 'public.audit_logs'::regclass and t.tgname in ('audit_logs_keep_every_entry', 'audit_logs_never_emptied'));
  if d is not null then
    raise exception 'undo 536: 536''s function is also used by %. Nothing was changed.', d; end if;
  if (select string_agg(t.tgname || '|' || t.tgenabled::text || '|' || pg_get_triggerdef(t.oid), ';' order by t.tgname)
        from pg_trigger t where t.tgrelid = 'public.audit_logs'::regclass and not t.tgisinternal
         and t.tgname in ('audit_logs_keep_every_entry', 'audit_logs_never_emptied')) is distinct from c_trg_536 then
    raise exception 'undo 536: the triggers on public.audit_logs are not 536''s (both there and enabled ALWAYS). Nothing was changed.'; end if;
  if (select c.relacl::text from pg_class c where c.oid = 'public.audit_logs'::regclass) is distinct from c_tbl_acl_536 then
    raise exception 'undo 536: the grants on public.audit_logs are not 536''s (%). Nothing was changed.',
      (select c.relacl::text from pg_class c where c.oid = 'public.audit_logs'::regclass); end if;
  for i in 1 .. cardinality(c_closed) loop
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_closed[i])) is distinct from c_closed_acl_536 then
      raise exception 'undo 536: the grants of public.% are not 536''s. Nothing was changed.', c_closed[i]; end if;
  end loop;

  -- 2. Undo
  drop trigger audit_logs_keep_every_entry on public.audit_logs;
  drop trigger audit_logs_never_emptied on public.audit_logs;
  drop function public.audit_logs_keep_every_entry();
  grant insert, update, delete, truncate, references, trigger, maintain on table public.audit_logs to service_role;
  for i in 1 .. cardinality(c_closed) loop
    execute format('grant execute on function public.%s to service_role', c_closed[i]);
  end loop;

  -- 3. Checks after
  if (select c.relacl::text from pg_class c where c.oid = 'public.audit_logs'::regclass) is distinct from c_tbl_acl_before then
    raise exception 'undo 536: the grants on public.audit_logs were not put back exactly'; end if;
  for i in 1 .. cardinality(c_closed) loop
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_closed[i])) is distinct from c_closed_acl_before then
      raise exception 'undo 536: the grants of public.% were not put back exactly', c_closed[i]; end if;
  end loop;
  if exists (select 1 from pg_trigger t where t.tgrelid = 'public.audit_logs'::regclass
              and t.tgname in ('audit_logs_keep_every_entry', 'audit_logs_never_emptied'))
     or to_regprocedure('public.' || c_fn_sig) is not null then
    raise exception 'undo 536: a part of 536 is still there'; end if;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
