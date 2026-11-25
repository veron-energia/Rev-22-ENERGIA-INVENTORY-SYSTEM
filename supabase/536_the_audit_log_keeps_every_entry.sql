-- 536_the_audit_log_keeps_every_entry.sql
--
-- THE AUDIT LOG KEEPS EVERY ENTRY: NO LOGIN OR KEY CHANGES, DELETES OR EMPTIES IT, AND THE SECRET
-- KEY NO LONGER ADDS ENTRIES OF ITS OWN
--
--   From the security audit of 17 Nov 2026 (finding M14).
--   The BEFORE state and the relied-on md5s below are those of production at 533 (head
--   20261124091324, function fingerprint dee55c68b5a31c3ccf59eed226725984/1447, PostgreSQL 17.6;
--   the local copy of 529 with 530 to 533 applied gives the same). They are the same with 534,
--   535 and 537 in. If production differs when this is applied, it refuses and changes nothing.
--   (The number 536 is this file's name and its errors' prefix; if it changes at commit, change
--   it there, in the 536 comment it writes into audit_logs_keep_every_entry() (and so its md5,
--   also in scripts/audit-log/undo-536.sql, in scripts/permissions/tests/function-grants.sql and
--   in the suite), and in the name and path of its suite.)
--
-- WHAT WAS WRONG
--
--   No app role can write, change or delete an Audit Log entry, but nothing made the log
--   append-only. public.audit_logs gave the service role (the secret key, which the Edge
--   Functions and Pabbly Connect hold) INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER and
--   MAINTAIN, so anything holding that key could change, delete or empty entries through the
--   table API, with no trace. It could also add entries of its choosing: straight on the table,
--   or through /rpc/write_audit and /rpc/write_audit_ex, which save any entry they are given and
--   which the service role could call. And the database owner, by mistake or in the SQL editor,
--   could change or delete entries, or empty the log, also by emptying profiles or stores with
--   cascade. The one trigger that fired on a change or a deletion (invoice_date_audit_lock)
--   refuses nothing.
--
-- THE RULE (the user, 24 Nov 2026): "Append-only"
--
--   * No login or key can change, delete or empty an Audit Log entry.
--   * The secret key (service_role) cannot add entries straight to the table either.
--   * Entries still come from the app's own functions, as today, and every entry is kept: there is
--     no retention clean-up.
--   * Only the database owner (postgres, in the Supabase dashboard) could deliberately switch this
--     off.
--
-- WHAT THIS DOES (no data changes)
--
--   * Grants on public.audit_logs: INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER and
--     MAINTAIN are revoked from PUBLIC, anon, authenticated and service_role. SELECT stays with
--     authenticated (through its rule "read audit logs", Owners, Admins and Managers) and with the
--     service role. The grants are then exactly
--     {postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=r/postgres}, and no
--     column holds a grant of its own.
--   * EXECUTE on write_audit(text,uuid,text,jsonb,jsonb) and
--     write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) is revoked from PUBLIC,
--     anon, authenticated and service_role: only their owner, postgres, may call them, which every
--     function that calls them is (step 1 checks it). Their text is unchanged.
--   * audit_logs_keep_every_entry(), new, a trigger function (no grant but its owner's; SECURITY
--     INVOKER, search_path ''), raises, errcode 42501:
--       a change:   "The Audit Log keeps every entry: it cannot be changed."
--       a deletion: "The Audit Log keeps every entry: it cannot be deleted."
--       emptying:   "The Audit Log keeps every entry: it cannot be emptied."
--     It is the function of two triggers on public.audit_logs, both enabled ALWAYS, so that
--     session_replication_role = replica does not skip them:
--       audit_logs_keep_every_entry  BEFORE UPDATE OR DELETE, FOR EACH ROW;
--       audit_logs_never_emptied     BEFORE TRUNCATE, FOR EACH STATEMENT (it also fires when
--                                    profiles or stores are emptied with cascade, which before
--                                    this emptied the log).
--     Their names start "audit_logs_", so they fire before invoice_date_audit_lock and no invoice
--     row is locked before the refusal. There is no exception for an entry written in the same
--     transaction: an entry is kept from the moment it is written. A local test suite that
--     back-dates or removes its own entries switches the row trigger off inside its own
--     transaction (it comes back with the rollback).
--   * Step 1 refuses, with nothing changed, unless (read from the catalogue, every schema but the
--     temporary ones): every function that calls write_audit( or write_audit_ex(, or inserts into
--     audit_logs, is SECURITY DEFINER and owned by postgres; and no function at all updates,
--     deletes from, merges into or empties audit_logs (read from each function's text). With
--     those true, nothing in the app needed the service role's rights on the table or on the two
--     helpers, and nothing in the app is refused by the triggers.
--
-- WHAT STAYS
--
--   * Entries are written as before, by the app's own functions (each SECURITY DEFINER, owned by
--     postgres): the pages', the Edge Functions' and Pabbly's calls, the public forms, and 532's
--     trigger trg_audit_direct_change() (a change made straight on a store, a payment method, a
--     staff profile and the rest). audit_logs_fill_module still files an entry saved with no
--     module; invoice_date_audit_lock is not changed (its UPDATE and DELETE branches now never
--     run).
--   * The log becomes unchangeable, not complete: a change made with a secret key straight on a
--     table outside 532's list still leaves no entry, and every secret key still reads and writes
--     everything else.
--   * Entries written by the two public forms (submit_health_survey, affiliate_referral_signup)
--     cannot be removed either; how many there can be is held by 529's and 530's limits.
--   * Personal details inside entries are kept for good: a request to delete a person's data
--     cannot reach the log unless the database owner switches the trigger off.
--   * The database owner (postgres, in the Supabase dashboard) can still deliberately switch this
--     off: disable or drop a trigger, replace the trigger function, or drop or rewrite the table.
--     Those are changes to the catalogue, which a later read sees (the triggers' enabled state,
--     the function's md5, the grants). scripts/audit-log/undo-536.sql is that switch.
--   * The report's local check for M14 now answers, as service_role: "permission denied for table
--     audit_logs"; as the owner: the trigger's message.
--   * Reading the log, its rule "read audit logs" and the Audit Log page: unchanged.
--
-- UNDO
--
--   scripts/audit-log/undo-536.sql (it refuses unless every part of 536 is exactly 536's): the
--   two triggers and the function are dropped, the service role's grants on audit_logs and its
--   EXECUTE on the two helpers are put back exactly. A later migration changing any of these must
--   pin 536's state.
--
-- NO SELF-TEST INSIDE; the suite is scripts/audit-log/tests/audit-log-keeps-every-entry-536.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- Functions this relies on, as tested: the two helpers (their text stays; only their grants
  -- change) and the two triggers already on the table.
  c_relied constant text[] := array[
    'write_audit(text,uuid,text,jsonb,jsonb)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'trg_audit_logs_fill_module()',
    'lock_invoice_date_history()'];
  c_relied_md5 constant text[] := array[
    'b194f839993670c5b5dd28e934c2a829',
    'c705c733e213a27f0dc32d54322cc855',
    '417a84925a3e465bcc9f11f7c13bb673',
    'aeb1a3b86377f511af6b9a7d6d364a2e'];
  -- The two helpers whose EXECUTE is closed: their grants before and after.
  c_closed constant text[] := array[
    'write_audit(text,uuid,text,jsonb,jsonb)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)'];
  c_closed_acl_before constant text := 'postgres=X/postgres,service_role=X/postgres';
  c_closed_acl_after constant text := 'postgres=X/postgres';
  -- The table's grants before and after.
  c_tbl_acl_before constant text := '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=arwdDxtm/postgres}';
  c_tbl_acl_after constant text := '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=r/postgres}';
  -- Its triggers before (name, enabled, definition), and the two this adds.
  c_trg_before constant text :=
    'audit_logs_fill_module|O|CREATE TRIGGER audit_logs_fill_module BEFORE INSERT ON public.audit_logs FOR EACH ROW WHEN ((new.module IS NULL)) EXECUTE FUNCTION trg_audit_logs_fill_module()'
    || ';invoice_date_audit_lock|O|CREATE TRIGGER invoice_date_audit_lock BEFORE INSERT OR DELETE OR UPDATE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION lock_invoice_date_history()';
  c_trg_after constant text :=
    'audit_logs_fill_module|O|CREATE TRIGGER audit_logs_fill_module BEFORE INSERT ON public.audit_logs FOR EACH ROW WHEN ((new.module IS NULL)) EXECUTE FUNCTION trg_audit_logs_fill_module()'
    || ';audit_logs_keep_every_entry|A|CREATE TRIGGER audit_logs_keep_every_entry BEFORE DELETE OR UPDATE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION audit_logs_keep_every_entry()'
    || ';audit_logs_never_emptied|A|CREATE TRIGGER audit_logs_never_emptied BEFORE TRUNCATE ON public.audit_logs FOR EACH STATEMENT EXECUTE FUNCTION audit_logs_keep_every_entry()'
    || ';invoice_date_audit_lock|O|CREATE TRIGGER invoice_date_audit_lock BEFORE INSERT OR DELETE OR UPDATE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION lock_invoice_date_history()';
  -- Its foreign keys (both NO ACTION: no change to a profile or a store ever changes an entry).
  c_fk constant text := 'audit_logs_changed_by_fkey|aa|profiles;audit_logs_store_id_fkey|aa|stores';
  -- The new trigger function.
  c_new_sig constant text := 'audit_logs_keep_every_entry()';
  c_new_def constant text :=
$d$CREATE OR REPLACE FUNCTION public.audit_logs_keep_every_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  -- 536 (security audit of 17 Nov 2026, M14; the user, 24 Nov 2026: "Append-only"): an entry of
  -- the Audit Log is never changed, deleted or emptied, whoever asks and however. It runs as the
  -- triggers audit_logs_keep_every_entry (before a change or a deletion, each row) and
  -- audit_logs_never_emptied (before the table is emptied, also as part of emptying another table
  -- with cascade), both enabled ALWAYS. Entries are still added as before.
  if tg_op = 'UPDATE' then
    raise exception 'The Audit Log keeps every entry: it cannot be changed.' using errcode = '42501';
  elsif tg_op = 'DELETE' then
    raise exception 'The Audit Log keeps every entry: it cannot be deleted.' using errcode = '42501';
  end if;
  raise exception 'The Audit Log keeps every entry: it cannot be emptied.' using errcode = '42501';
end
$function$
$d$;
  c_new_md5 constant text := 'a4fdc5a8c602e0edf2420f99b9f06584';
  c_new_acl constant text := 'postgres=X/postgres';
  -- What a function's text must not do to the log (step 1), and what makes it a writer.
  c_rx_change constant text := '(update\s+(only\s+)?|delete\s+from\s+(only\s+)?|merge\s+into\s+(only\s+)?|truncate\s+(table\s+)?(only\s+)?)("?public"?\s*\.\s*)?"?audit_logs\M';
  c_rx_write constant text := '(write_audit(_ex)?\s*\(|insert\s+into\s+("?public"?\s*\.\s*)?"?audit_logs\M)';

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_acl text; v_trg text; v_bad text;
  v_fn_done boolean; v_trg_done boolean; v_tbl_done boolean; v_closed_done int := 0;
  i int;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);
  -- A busy table waits 5 seconds at most, then this refuses whole.
  perform set_config('lock_timeout', '5s', true);

  -- 1. Checks: nothing is changed before all of them pass
  if current_setting('server_version_num')::int < 170000 then
    raise exception '536: this was tested on PostgreSQL 17 (MAINTAIN); this server is %', current_setting('server_version'); end if;
  if to_regclass('public.audit_logs') is null then
    raise exception '536: public.audit_logs is missing'; end if;
  -- No entry is written while this reads and changes the table's rules.
  lock table public.audit_logs in share row exclusive mode;
  if (select c.relowner::regrole::text from pg_class c where c.oid = 'public.audit_logs'::regclass) <> 'postgres'
     or (select c.relkind from pg_class c where c.oid = 'public.audit_logs'::regclass) <> 'r'
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.audit_logs'::regclass)
     or exists (select 1 from pg_inherits h where h.inhparent = 'public.audit_logs'::regclass or h.inhrelid = 'public.audit_logs'::regclass)
     or exists (select 1 from pg_rewrite r where r.ev_class = 'public.audit_logs'::regclass) then
    raise exception '536: public.audit_logs is not as tested (owner postgres, a plain table, row-level security on, no inheritance, no rule). Re-read it before applying.'; end if;
  if exists (select 1 from pg_attribute a where a.attrelid = 'public.audit_logs'::regclass and a.attnum > 0 and a.attacl is not null) then
    raise exception '536: a column of public.audit_logs holds a grant of its own. Re-read them before applying.'; end if;
  if (select coalesce(string_agg(c.conname || '|' || c.confdeltype::text || c.confupdtype::text || '|' || c.confrelid::regclass::text, ';' order by c.conname), '')
        from pg_constraint c where c.conrelid = 'public.audit_logs'::regclass and c.contype = 'f') is distinct from c_fk then
    raise exception '536: the foreign keys of public.audit_logs are not the tested ones (both NO ACTION). Re-read them before applying.'; end if;
  if exists (select 1 from pg_constraint c where c.confrelid = 'public.audit_logs'::regclass) then
    raise exception '536: a foreign key refers to public.audit_logs. Re-read it before applying.'; end if;
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '536: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;
  -- Every writer of the log runs as postgres; nothing changes, deletes or empties it.
  select string_agg(p.oid::regprocedure::text || ' (' || n.nspname || ')', ', ' order by p.oid::regprocedure::text) into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname !~ '^pg_(toast_)?temp_'
     and p.prosrc ~* c_rx_write
     and not (p.prosecdef and p.proowner = 'postgres'::regrole);
  if v_bad is not null then
    raise exception '536: these functions write the Audit Log without running as postgres: %. They would be refused; re-read them before applying.', v_bad; end if;
  select string_agg(p.oid::regprocedure::text || ' (' || n.nspname || ')', ', ' order by p.oid::regprocedure::text) into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname !~ '^pg_(toast_)?temp_'
     and p.prosrc ~* c_rx_change;
  if v_bad is not null then
    raise exception '536: these functions change, delete or empty Audit Log entries: %. They would be refused; re-read them before applying.', v_bad; end if;

  -- Before, after, or in part.
  v_acl := (select c.relacl::text from pg_class c where c.oid = 'public.audit_logs'::regclass);
  if v_acl = c_tbl_acl_after then v_tbl_done := true;
  elsif v_acl = c_tbl_acl_before then v_tbl_done := false;
  else raise exception '536: the grants on public.audit_logs are not the tested ones (%). Re-read them before applying.', v_acl; end if;
  for i in 1 .. cardinality(c_closed) loop
    v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_closed[i]));
    if v_acl = c_closed_acl_after then v_closed_done := v_closed_done + 1;
    elsif v_acl is distinct from c_closed_acl_before then
      raise exception '536: the grants of public.% are not the tested ones (%). Re-read them before applying.', c_closed[i], v_acl; end if;
  end loop;
  if to_regprocedure('public.' || c_new_sig) is null then v_fn_done := false;
  elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig))) = c_new_md5 then v_fn_done := true;
  else raise exception '536: a function public.% is there, but not 536''s. Re-read it before applying.', c_new_sig; end if;
  v_trg := (select string_agg(t.tgname || '|' || t.tgenabled::text || '|' || pg_get_triggerdef(t.oid), ';' order by t.tgname)
              from pg_trigger t where t.tgrelid = 'public.audit_logs'::regclass and not t.tgisinternal);
  if v_trg = c_trg_after then v_trg_done := true;
  elsif v_trg = c_trg_before then v_trg_done := false;
  else raise exception '536: the triggers on public.audit_logs are not the tested ones (%). Re-read them before applying.', v_trg; end if;
  if v_tbl_done and v_fn_done and v_trg_done and v_closed_done = cardinality(c_closed) then
    raise exception '536 is already in on this database; nothing was changed.'; end if;
  if v_tbl_done or v_fn_done or v_trg_done or v_closed_done > 0 then
    raise exception '536: only part of it is in on this database (table grants %, function %, triggers %, % of % helpers closed). Re-read them before applying; nothing was changed.',
      case when v_tbl_done then 'closed' else 'open' end, case when v_fn_done then 'there' else 'missing' end,
      case when v_trg_done then 'there' else 'missing' end, v_closed_done, cardinality(c_closed); end if;

  -- 2. Install
  revoke insert, update, delete, truncate, references, trigger, maintain on table public.audit_logs
    from public, anon, authenticated, service_role;
  for i in 1 .. cardinality(c_closed) loop
    execute format('revoke execute on function public.%s from public, anon, authenticated, service_role', c_closed[i]);
  end loop;
  execute c_new_def;
  revoke all on function public.audit_logs_keep_every_entry() from public, anon, authenticated, service_role;
  create trigger audit_logs_keep_every_entry before update or delete on public.audit_logs
    for each row execute function public.audit_logs_keep_every_entry();
  create trigger audit_logs_never_emptied before truncate on public.audit_logs
    for each statement execute function public.audit_logs_keep_every_entry();
  alter table public.audit_logs enable always trigger audit_logs_keep_every_entry;
  alter table public.audit_logs enable always trigger audit_logs_never_emptied;

  -- 3. Checks after installing
  if (select c.relacl::text from pg_class c where c.oid = 'public.audit_logs'::regclass) is distinct from c_tbl_acl_after
     or exists (select 1 from pg_attribute a where a.attrelid = 'public.audit_logs'::regclass and a.attnum > 0 and a.attacl is not null)
     or has_table_privilege('anon', 'public.audit_logs', 'select,insert,update,delete,truncate,references,trigger,maintain')
     or has_table_privilege('authenticated', 'public.audit_logs', 'insert,update,delete,truncate,references,trigger,maintain')
     or has_table_privilege('service_role', 'public.audit_logs', 'insert,update,delete,truncate,references,trigger,maintain')
     or not has_table_privilege('authenticated', 'public.audit_logs', 'select')
     or not has_table_privilege('service_role', 'public.audit_logs', 'select') then
    raise exception '536: the grants on public.audit_logs are not 536''s after installing'; end if;
  for i in 1 .. cardinality(c_closed) loop
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_closed[i])) is distinct from c_closed_acl_after
       or has_function_privilege('anon', to_regprocedure('public.' || c_closed[i]), 'execute')
       or has_function_privilege('authenticated', to_regprocedure('public.' || c_closed[i]), 'execute')
       or has_function_privilege('service_role', to_regprocedure('public.' || c_closed[i]), 'execute') then
      raise exception '536: public.% can still be called by a key or a login', c_closed[i]; end if;
  end loop;
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig))) <> c_new_md5 then
    raise exception '536: public.% was made with an md5 other than the tested one (md5 %)', c_new_sig,
      md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig))); end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_new_sig)) is distinct from c_new_acl then
    raise exception '536: public.% has grants other than its owner''s', c_new_sig; end if;
  if (select string_agg(t.tgname || '|' || t.tgenabled::text || '|' || pg_get_triggerdef(t.oid), ';' order by t.tgname)
        from pg_trigger t where t.tgrelid = 'public.audit_logs'::regclass and not t.tgisinternal) is distinct from c_trg_after then
    raise exception '536: the triggers on public.audit_logs are not 536''s after installing'; end if;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '536: public.% changed', c_relied[i]; end if;
  end loop;

  perform set_config('lock_timeout', v_lock, true);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
