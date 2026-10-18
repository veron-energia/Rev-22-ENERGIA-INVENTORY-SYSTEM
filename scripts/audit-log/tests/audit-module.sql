-- Audit entries record their module (431, owner's answer of 9 Oct 2026).
--
-- 431 must:
--   * file every new entry under a module. write_audit() saves its table's.
--     write_audit_ex() saves the one its caller passes, as passed
--     ("commission" too), and the table's when none is passed. An entry
--     written straight into audit_logs with none (as seven server functions
--     and the service role do) is given its table's by a trigger, which sets
--     nothing else and does not fire on an update;
--   * take the module from the table with 428's list, plus the tables audit
--     writers use that 428 did not name; any other table is its own module;
--     no table gives "affiliate", which the affiliate claim checks trust;
--   * (owner, 18 Oct 2026) file the therapy voucher-rights routine's entries
--     (apply_therapy_voucher_rights_retrospectively, table
--     customer_reward_vouchers, no module) under "therapy" and FOC-reason
--     changes (upsert_foc_reason, set_foc_reason_active: table foc_reasons)
--     under "invoices", while voucher entries saved as "refunds" or
--     "invoices" keep them, old and new, and FOC invoices saved as "foc"
--     stay under "foc", apart from the FOC reasons; any voucher entry with
--     no module, whoever writes it, goes under "therapy";
--   * show "commission" and "commissions" as one module in the Audit Log: in
--     its rows, in its filter's choices (one name, the counts added up), in a
--     filter by either name, and in its text search. Other names that differ
--     by a letter stay apart. An entry saved with no module is still marked
--     as taken from its table;
--   * leave every entry already saved exactly as it was, when it is applied
--     and when it is re-run, and change no function but its own four;
--   * refuse, and change nothing, on a database it was not tested against:
--     write_audit or audit_log_page neither production's version nor its
--     own, 406 not in, current_user_role() another version, audit_logs
--     shaped another way, audit_module another version, another function
--     with one of its names, or another trigger with its trigger's name;
--   * keep write_audit, write_audit_ex and the new helpers for the server
--     alone, and audit_log_page for the staff it lets in (Staff, an affiliate
--     and the anon key refused as before).
--
-- Run it on a disposable copy with production's schema and 406 and 428
-- applied, from any folder:
--   psql -X -v ON_ERROR_STOP=1 -d <copy> -f scripts/audit-log/tests/audit-module.sql
-- It saves entries as they were before 431, then applies 431 inside its own
-- transaction (a re-run, which changes nothing, when 431 is in already), runs
-- it a second time, then runs it eight more times, each after one change
-- that is undone, and checks that each run refuses. psql prints those eight
-- refusals as ERROR lines; they are expected. Then it rolls everything back.
-- Fixture names carry AUDM, emails @sig.invalid; nothing real is read or
-- printed.
\set ON_ERROR_STOP on
begin;

create temp table audm(k text primary key, id uuid not null);
create temp table audm_fail(n serial, msg text);

create function pg_temp.audm_id(p text) returns uuid language sql stable as
  $f$ select id from audm where k = p $f$;

create function pg_temp.audm_fail(p text) returns void language sql as
  $f$ insert into audm_fail(msg) values (p) $f$;

-- Run p_sql as one of the fixture's logins and say what happened:
--   'ok' and the result as text, or the SQLSTATE and the message.
-- p_who is a login key, 'anon' (the public key, signed out), 'service' (the
-- service role) or 'server' (no request at all).
create function pg_temp.audm_try(p_who text, p_sql text) returns text language plpgsql as $f$
declare v_out text; v_state text; v_msg text;
begin
  begin
    if p_who = 'server' then
      perform set_config('request.jwt.claims', '', true);
    elsif p_who = 'anon' then
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
      execute 'set local role anon';
    elsif p_who = 'service' then
      perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
      execute 'set local role service_role';
    else
      perform set_config('request.jwt.claims',
        json_build_object('sub', pg_temp.audm_id(p_who), 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    execute p_sql into v_out;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    return 'ok' || chr(9) || coalesce(v_out, '');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    perform set_config('request.jwt.claims', '', true);
    return v_state || chr(9) || v_msg;
  end;
end $f$;

-- One Audit Log page as the Owner; the answer as jsonb (a failure fails the test).
create function pg_temp.audm_page(p_args text) returns jsonb language plpgsql as $f$
declare v_out text;
begin
  v_out := pg_temp.audm_try('owner', 'select public.audit_log_page(' || p_args || ')::text');
  if split_part(v_out, chr(9), 1) <> 'ok' then
    perform pg_temp.audm_fail('audit_log_page(' || p_args || ') failed for the Owner: ' || v_out);
    return null;
  end if;
  return substr(v_out, 4)::jsonb;
end $f$;

-- The page's rows as "action:module:recorded", by action.
create function pg_temp.audm_shown(j jsonb) returns text language sql immutable as
  $f$ select coalesce(string_agg(concat_ws(':', r ->> 'action', r ->> 'module', r ->> 'module_recorded'), ',' order by r ->> 'action' collate "C"), '')
        from jsonb_array_elements(coalesce(j -> 'rows', '[]')) r $f$;

-- Every public function's md5, as the migrations compare them.
create function pg_temp.audm_fn_md5s() returns table(fn text, md5 text) language sql stable as
  $f$ select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))
        from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' $f$;

-- ── Fixture, and entries as saved before 431 ────────────────────────────────
do $$
declare k text; v uuid; st uuid; o uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  foreach k in array array['owner', 'manager', 'staff', 'affiliate'] loop
    insert into auth.users(id, email) values (gen_random_uuid(), 'audm-' || k || '@sig.invalid') returning id into v;
    insert into audm values (k, v);
  end loop;
  -- The affiliate login has no staff profile.
  insert into public.profiles(id, full_name, email, role, is_active, created_at, updated_at)
  select s.id, 'AUDM ' || s.k, 'audm-' || s.k || '@sig.invalid', x.role::public.user_role, true, now(), now()
    from audm s join (values ('owner', 'owner'), ('manager', 'manager'), ('staff', 'staff')) x(k, role) on x.k = s.k;
  insert into public.stores(name, code, country_code) values ('AUDM Store', 'AUDMA', 'SG') returning id into st;
  insert into public.user_store_assignments(user_id, store_id)
  select pg_temp.audm_id(x), st from unnest(array['manager', 'staff']) x;
  insert into audm values ('store', st);
  o := pg_temp.audm_id('owner');

  -- Entries saved before 431, every one with "audmold" in its reason. When
  -- the database has 431's trigger already, it is off while they are saved.
  if exists (select 1 from pg_trigger t where t.tgrelid = 'public.audit_logs'::regclass
              and t.tgname = 'audit_logs_fill_module') then
    alter table public.audit_logs disable trigger audit_logs_fill_module;
  end if;
  insert into public.audit_logs (table_name, action, module, changed_by, actor_role, reason, created_at)
  values ('invoices',            'audm_old_commission',     'commission',  o,    'owner', 'audmold', timestamptz '2026-09-01 02:00:00+00'),
         ('staff_commissions',   'audm_old_staff_comm',     null,          null, null,    'audmold', timestamptz '2026-09-01 02:01:00+00'),
         ('commissions',         'audm_old_commissions',    'commissions', o,    'owner', 'audmold', timestamptz '2026-09-01 02:02:00+00'),
         ('invoices',            'audm_old_invoice',        'invoice',     o,    'owner', 'audmold', timestamptz '2026-09-01 02:03:00+00'),
         ('invoices',            'audm_old_invoices',       'invoices',    o,    'owner', 'audmold', timestamptz '2026-09-01 02:04:00+00'),
         ('voucher_store_stock', 'audm_old_voucher_stock',  null,          o,    'owner', 'audmold', timestamptz '2026-09-01 02:05:00+00'),
         ('affiliate_accounts',  'audm_old_affiliate_acct', null,          o,    'owner', 'audmold', timestamptz '2026-09-01 02:06:00+00'),
         ('profiles',            'audm_old_profile',        null,          o,    'owner', 'audmold', timestamptz '2026-09-01 02:07:00+00'),
         ('customer_reward_vouchers', 'audm_old_voucher_refund',  'refunds',  o, 'owner', 'audmold', timestamptz '2026-09-01 02:08:00+00'),
         ('customer_reward_vouchers', 'audm_old_voucher_carried', 'invoices', o, 'owner', 'audmold', timestamptz '2026-09-01 02:09:00+00'),
         ('customer_reward_vouchers', 'audm_old_voucher_rights',  null,       o, 'owner', 'audmold', timestamptz '2026-09-01 02:10:00+00'),
         ('foc_reasons',              'audm_old_foc_reason',      null,       o, 'owner', 'audmold', timestamptz '2026-09-01 02:11:00+00');
  if exists (select 1 from pg_trigger t where t.tgrelid = 'public.audit_logs'::regclass
              and t.tgname = 'audit_logs_fill_module') then
    alter table public.audit_logs enable trigger audit_logs_fill_module;
  end if;
end $$;

-- Every entry and every function, as they are before 431 is applied (or re-run).
create temp table audm_rows_before as select a.id, to_jsonb(a) as row from public.audit_logs a;
create temp table audm_fns_before as select * from pg_temp.audm_fn_md5s();

-- ── 431, applied (or re-run when it is in already) ───────────────────────────
\ir ../../../supabase/431_audit_entries_record_their_module.sql

create temp table audm_fns_once as select * from pg_temp.audm_fn_md5s();
create temp table audm_rows_once as select a.id, to_jsonb(a) as row from public.audit_logs a;

-- ── and run again: it must change nothing ───────────────────────────────────
\ir ../../../supabase/431_audit_entries_record_their_module.sql

-- ── 431 refuses on a database it was not tested against ─────────────────────
-- Each case changes one thing inside a savepoint, runs 431 again, undoes the
-- change and keeps 431's error message. psql prints each refusal as an ERROR
-- line; they are expected and checked in section 6. Each case has its own
-- savepoint, released before the message is kept: with one savepoint reused,
-- the next "rollback to savepoint" would undo the kept message too.
-- Section 1 then compares every function with the first run, so it also
-- shows the refusals left nothing behind.
\set ON_ERROR_STOP off

-- write_audit is neither production's version nor 431's.
\set LAST_ERROR_MESSAGE ''
savepoint audm_g;
do $$ begin execute regexp_replace(pg_get_functiondef('public.write_audit(text,uuid,text,jsonb,jsonb)'::regprocedure),
  '\$function\$', E'$function$\n-- AUDM another version\n'); end $$;
\ir ../../../supabase/431_audit_entries_record_their_module.sql
rollback to savepoint audm_g;
release savepoint audm_g;
select set_config('audm.g_write_audit', :'LAST_ERROR_MESSAGE', true) as audm_kept \gset

-- audit_log_page is neither production's version nor 431's.
\set LAST_ERROR_MESSAGE ''
savepoint audm_g;
do $$ begin execute regexp_replace(pg_get_functiondef('public.audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean)'::regprocedure),
  '\$function\$', E'$function$\n-- AUDM another version\n'); end $$;
\ir ../../../supabase/431_audit_entries_record_their_module.sql
rollback to savepoint audm_g;
release savepoint audm_g;
select set_config('audm.g_page', :'LAST_ERROR_MESSAGE', true) as audm_kept \gset

-- 406 is not in: require_active_staff is another version.
\set LAST_ERROR_MESSAGE ''
savepoint audm_g;
do $$ begin execute regexp_replace(pg_get_functiondef('public.require_active_staff(text[])'::regprocedure),
  '\$function\$', E'$function$\n-- AUDM another version\n'); end $$;
\ir ../../../supabase/431_audit_entries_record_their_module.sql
rollback to savepoint audm_g;
release savepoint audm_g;
select set_config('audm.g_406', :'LAST_ERROR_MESSAGE', true) as audm_kept \gset

-- current_user_role() is another version.
\set LAST_ERROR_MESSAGE ''
savepoint audm_g;
do $$ begin execute regexp_replace(pg_get_functiondef('public.current_user_role()'::regprocedure),
  '\$function\$', E'$function$\n-- AUDM another version\n'); end $$;
\ir ../../../supabase/431_audit_entries_record_their_module.sql
rollback to savepoint audm_g;
release savepoint audm_g;
select set_config('audm.g_role', :'LAST_ERROR_MESSAGE', true) as audm_kept \gset

-- audit_logs is shaped another way. A rename: with 431 in, the trigger's
-- WHEN clause blocks changing the module column.
\set LAST_ERROR_MESSAGE ''
savepoint audm_g;
alter table public.audit_logs rename column old_data to audm_old_data;
\ir ../../../supabase/431_audit_entries_record_their_module.sql
rollback to savepoint audm_g;
release savepoint audm_g;
select set_config('audm.g_cols', :'LAST_ERROR_MESSAGE', true) as audm_kept \gset

-- audit_module exists and is another version.
\set LAST_ERROR_MESSAGE ''
savepoint audm_g;
create or replace function public.audit_module(p_module text, p_table text) returns text language sql immutable
  as $f$ select coalesce(p_module, p_table) $f$;
\ir ../../../supabase/431_audit_entries_record_their_module.sql
rollback to savepoint audm_g;
release savepoint audm_g;
select set_config('audm.g_new_fn', :'LAST_ERROR_MESSAGE', true) as audm_kept \gset

-- Another function takes one of its names (an overload).
\set LAST_ERROR_MESSAGE ''
savepoint audm_g;
create function public.audit_module(p text) returns text language sql immutable as $f$ select p $f$;
\ir ../../../supabase/431_audit_entries_record_their_module.sql
rollback to savepoint audm_g;
release savepoint audm_g;
select set_config('audm.g_overload', :'LAST_ERROR_MESSAGE', true) as audm_kept \gset

-- A trigger of the same name that is not 431's (it also fires on update).
\set LAST_ERROR_MESSAGE ''
savepoint audm_g;
drop trigger audit_logs_fill_module on public.audit_logs;
create trigger audit_logs_fill_module before insert or update on public.audit_logs
  for each row when (new.module is null) execute function public.trg_audit_logs_fill_module();
\ir ../../../supabase/431_audit_entries_record_their_module.sql
rollback to savepoint audm_g;
release savepoint audm_g;
select set_config('audm.g_trigger', :'LAST_ERROR_MESSAGE', true) as audm_kept \gset

\set ON_ERROR_STOP on

-- ── 1. What 431 changed, and what it left alone ─────────────────────────────
do $$
declare v_changed text; v_bad text;
begin
  -- No entry saved before it was written, changed or removed: they are evidence.
  if (select count(*) from audm_rows_once) <> (select count(*) from audm_rows_before)
     or exists (select 1 from audm_rows_before b left join audm_rows_once a on a.id = b.id
                 where a.id is null or a.row <> b.row) then
    perform pg_temp.audm_fail('1: applying 431 added, changed or removed an audit entry');
  end if;
  if (select count(*) from public.audit_logs) <> (select count(*) from audm_rows_before)
     or exists (select 1 from audm_rows_before b left join public.audit_logs a on a.id = b.id
                 where a.id is null or to_jsonb(a) <> b.row) then
    perform pg_temp.audm_fail('1: re-running 431 added, changed or removed an audit entry');
  end if;
  -- The old entries kept their modules, the empty ones empty.
  if (select string_agg(a.action || ':' || coalesce(a.module, '-'), ',' order by a.action collate "C")
        from public.audit_logs a where a.reason = 'audmold')
     <> 'audm_old_affiliate_acct:-,audm_old_commission:commission,audm_old_commissions:commissions,audm_old_foc_reason:-,'
        'audm_old_invoice:invoice,audm_old_invoices:invoices,audm_old_profile:-,audm_old_staff_comm:-,'
        'audm_old_voucher_carried:invoices,audm_old_voucher_refund:refunds,audm_old_voucher_rights:-,audm_old_voucher_stock:-' then
    perform pg_temp.audm_fail('1: an entry saved before 431 does not keep its module as saved');
  end if;

  -- Only its own four functions changed (none when it was in already), and the
  -- re-run changed none.
  select string_agg(coalesce(a.fn, b.fn), ', ' order by coalesce(a.fn, b.fn) collate "C") into v_changed
    from audm_fns_once a full join audm_fns_before b on b.fn = a.fn
   where a.md5 is distinct from b.md5;
  if coalesce(v_changed, '') not in ('',
       'audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean), audit_module(text,text), '
       'trg_audit_logs_fill_module(), write_audit(text,uuid,text,jsonb,jsonb)') then
    perform pg_temp.audm_fail('1: 431 changed functions other than its own four: ' || v_changed);
  end if;
  select string_agg(coalesce(a.fn, b.fn), ', ') into v_bad
    from pg_temp.audm_fn_md5s() a full join audm_fns_once b on b.fn = a.fn
   where a.md5 is distinct from b.md5;
  if v_bad is not null then
    perform pg_temp.audm_fail('1: re-running 431 changed functions: ' || v_bad);
  end if;
  -- write_audit_ex is left exactly as it was (415, 417 and 418 check it).
  if (select md5 from pg_temp.audm_fn_md5s() where fn = 'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)')
     is distinct from (select md5 from audm_fns_before where fn = 'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)') then
    perform pg_temp.audm_fail('1: 431 changed write_audit_ex');
  end if;

  -- The new helpers are the tested texts.
  if (select md5 from pg_temp.audm_fn_md5s() where fn = 'audit_module(text,text)') is distinct from 'daf0c43e9e9578e78048b2f6d7cba57e'
     or (select md5 from pg_temp.audm_fn_md5s() where fn = 'trg_audit_logs_fill_module()') is distinct from '417a84925a3e465bcc9f11f7c13bb673' then
    perform pg_temp.audm_fail('1: audit_module or trg_audit_logs_fill_module is not the tested text');
  end if;

  -- The trigger: before insert, each row, only when the module is empty, on.
  if (select pg_get_triggerdef(t.oid) || ' ' || t.tgenabled::text || ' ' || t.tgtype::text
        from pg_trigger t where t.tgrelid = 'public.audit_logs'::regclass and t.tgname = 'audit_logs_fill_module')
     is distinct from 'CREATE TRIGGER audit_logs_fill_module BEFORE INSERT ON public.audit_logs FOR EACH ROW '
                      'WHEN ((new.module IS NULL)) EXECUTE FUNCTION trg_audit_logs_fill_module() O 7' then
    perform pg_temp.audm_fail('1: the trigger is not before insert, for each row with no module, and on');
  end if;
  -- The other trigger on audit_logs is still there and on.
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'public.audit_logs'::regclass
                  and t.tgname = 'invoice_date_audit_lock' and t.tgenabled = 'O') then
    perform pg_temp.audm_fail('1: the invoice date lock trigger on audit_logs is missing or off');
  end if;

  -- One function of each name: the API picks an overload by name.
  select string_agg(x.proname || ' x' || x.n, ', ') into v_bad
    from (select p.proname, count(*) as n from pg_proc p where p.pronamespace = 'public'::regnamespace
            and p.proname in ('audit_module', 'trg_audit_logs_fill_module', 'write_audit', 'write_audit_ex', 'audit_log_page')
           group by p.proname) x
   where x.n <> 1;
  if (select count(distinct p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.proname in ('audit_module', 'trg_audit_logs_fill_module', 'write_audit', 'write_audit_ex', 'audit_log_page')) <> 5 then
    v_bad := concat_ws(', ', v_bad, 'one of the five is missing');
  end if;
  if v_bad is not null then
    perform pg_temp.audm_fail('1: a function of these names has an overload: ' || v_bad);
  end if;
end $$;

-- ── 2. Who may call what ─────────────────────────────────────────────────────
do $$
declare v text; v_out text; v_who text;
begin
  -- The writers and the new helpers are the server's alone.
  foreach v in array array['audit_module(text,text)', 'trg_audit_logs_fill_module()',
                           'write_audit(text,uuid,text,jsonb,jsonb)',
                           'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)'] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or has_function_privilege('authenticated', 'public.' || v, 'execute')
       or has_function_privilege('public', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute') then
      perform pg_temp.audm_fail('2: public.' || v || ' is not the service role''s alone');
    end if;
  end loop;
  foreach v_who in array array['owner', 'staff', 'affiliate', 'anon'] loop
    v_out := pg_temp.audm_try(v_who, 'select public.audit_module(null, ''invoices'')');
    if split_part(v_out, chr(9), 1) <> '42501' then
      perform pg_temp.audm_fail('2: ' || v_who || ' called audit_module: ' || v_out);
    end if;
    v_out := pg_temp.audm_try(v_who, 'select public.write_audit(''invoices'', null, ''audm_client'', null, null)::text');
    if split_part(v_out, chr(9), 1) <> '42501' then
      perform pg_temp.audm_fail('2: ' || v_who || ' called write_audit: ' || v_out);
    end if;
  end loop;
  if pg_temp.audm_try('service', 'select public.audit_module(''commission'', null)') <> 'ok' || chr(9) || 'commissions' then
    perform pg_temp.audm_fail('2: the service role cannot call audit_module, or it does not read "commission" as "commissions"');
  end if;
  -- The Audit Log: active Owners, Admins and Managers, as before.
  if has_function_privilege('anon', 'public.audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean)', 'execute') then
    perform pg_temp.audm_fail('2: audit_log_page is not callable by signed-in logins alone');
  end if;
  foreach v_who in array array['staff', 'affiliate', 'anon'] loop
    v_out := pg_temp.audm_try(v_who, 'select public.audit_log_page(p_text => ''audmold'')::text');
    if split_part(v_out, chr(9), 1) <> '42501' or v_out ~ 'audm' then
      perform pg_temp.audm_fail('2: ' || v_who || ' was not refused the Audit Log: ' || left(v_out, 120));
    end if;
  end loop;
  if split_part(pg_temp.audm_try('manager', 'select (public.audit_log_page(p_text => ''audmold'') ->> ''total'')'), chr(9), 2) <> '12' then
    perform pg_temp.audm_fail('2: a Manager does not see the Audit Log');
  end if;
end $$;

-- ── 3. The module a table gives, and a module given ─────────────────────────
do $$
declare r record; v_got text;
begin
  for r in select * from (values
    -- 428's list, unchanged
    (null, 'invoices', 'invoices'),
    (null, 'commissions', 'commissions'), (null, 'commission_payouts', 'commissions'), (null, 'staff_commissions', 'commissions'),
    (null, 'inventory_adjustment', 'inventory'), (null, 'warehouse_inventory', 'inventory'), (null, 'special_product_stock', 'inventory'),
    (null, 'vouchers', 'catalogue'), (null, 'credit_packages', 'catalogue'), (null, 'promotion_items', 'catalogue'),
    (null, 'unlimited_therapy_packages', 'catalogue'),
    (null, 'therapy_services', 'therapy'),
    (null, 'customers', 'customers'), (null, 'customer_source_options', 'customers'),
    (null, 'transfer_requests', 'transfers'), (null, 'product_exchanges', 'exchanges'), (null, 'rentals', 'rentals'),
    (null, 'app_settings', 'settings'), (null, 'profiles', 'users'),
    -- the tables audit writers use that 428 did not name
    (null, 'staff_commission_payouts', 'commissions'), (null, 'affiliate_deduction_settlements', 'commissions'),
    (null, 'voucher_store_stock', 'inventory'),
    (null, 'products', 'catalogue'), (null, 'credit_package_spending_rules', 'catalogue'),
    (null, 'therapy_entitlements', 'therapy'), (null, 'special_sales', 'special'),
    (null, 'tiktok_status_mappings', 'tiktok_import'),
    (null, 'user_invitations', 'users'), (null, 'user_store_assignments', 'users'),
    -- the owner's answer of 18 Oct 2026
    (null, 'foc_reasons', 'invoices'), (null, 'customer_reward_vouchers', 'therapy'),
    -- any other table is its own module; nothing at all is nothing
    (null, 'affiliate_accounts', 'affiliate_accounts'), (null, 'affiliate_account_claims', 'affiliate_account_claims'),
    (null, 'stores', 'stores'), (null, 'warehouses', 'warehouses'), (null, 'audm_side_table', 'audm_side_table'),
    (null, null, null),
    -- a module given is kept; "commission" is read as "commissions", whatever the table
    ('commission', 'invoices', 'commissions'), ('commission', null, 'commissions'), ('commission', 'staff_commissions', 'commissions'),
    ('commissions', 'invoices', 'commissions'), ('Commission', 'invoices', 'Commission'), ('commission ', null, 'commission '),
    ('invoice', 'invoices', 'invoice'), ('invoice_edit', 'invoices', 'invoice_edit'), ('affiliate', 'affiliate_accounts', 'affiliate'),
    ('affiliates', 'customer_affiliates', 'affiliates'), ('foc', 'invoices', 'foc'), ('', 'invoices', ''),
    ('refunds', 'customer_reward_vouchers', 'refunds'), ('invoices', 'customer_reward_vouchers', 'invoices'),
    ('foc', 'foc_reasons', 'foc')
  ) x(module, tbl, want) loop
    v_got := public.audit_module(r.module, r.tbl);
    if v_got is distinct from r.want then
      perform pg_temp.audm_fail(format('3: audit_module(%L, %L) is %L, not %L', r.module, r.tbl, v_got, r.want));
    end if;
  end loop;
  -- No table gives "affiliate": the affiliate claim checks count only rows
  -- saved with it, which only write_audit_ex writes when asked to.
  if exists (select 1 from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'v')
              and public.audit_module(null, c.relname::text) = 'affiliate') then
    perform pg_temp.audm_fail('3: a table gives the module "affiliate"');
  end if;
end $$;

-- ── 4. Every kind of writer files the entry ─────────────────────────────────
do $$
declare v_out text; v_svc uuid; v_id uuid := gen_random_uuid(); v_rec uuid := gen_random_uuid();
  v_got text; v_want text; v_row jsonb; v_cust uuid; v_voucher uuid; v_rv uuid; v_foc uuid;
  o uuid := pg_temp.audm_id('owner'); s uuid := pg_temp.audm_id('staff'); st uuid := pg_temp.audm_id('store');
begin
  -- write_audit, as server functions call it, for the Owner, for Staff and
  -- for nobody (the role and person saved as before).
  perform set_config('request.jwt.claims', json_build_object('sub', o, 'role', 'authenticated')::text, true);
  perform public.write_audit('staff_commission_payouts', null, 'audm_new_wa_owner', null, '{"m": "audmnew"}');
  perform public.write_audit('affiliate_accounts', null, 'audm_new_wa_affiliate', null, '{"m": "audmnew"}');
  perform set_config('request.jwt.claims', json_build_object('sub', s, 'role', 'authenticated')::text, true);
  perform public.write_audit('inventory_adjustment', null, 'audm_new_wa_staff', null, '{"m": "audmnew"}');
  perform set_config('request.jwt.claims', '', true);
  perform public.write_audit('foc_reasons', null, 'audm_new_wa_system', null, '{"m": "audmnew"}');
  -- write_audit_ex: the module passed, as passed; none passed, the table's.
  perform set_config('request.jwt.claims', json_build_object('sub', o, 'role', 'authenticated')::text, true);
  perform public.write_audit_ex('invoices', null, 'audm_new_wax_commission', null, '{"m": "audmnew"}', 'commission',
                                'a reason', st, '10.0.0.1', 'a device');
  perform public.write_audit_ex('invoices', null, 'audm_new_wax_none', null, '{"m": "audmnew"}');
  perform public.write_audit_ex('affiliate_account_claims', null, 'audm_new_wax_affiliate', null, '{"m": "audmnew"}', 'affiliate');
  -- Customer reward vouchers: none passed, therapy (the owner's answer of
  -- 18 Oct 2026); "refunds" and "invoices" passed, kept.
  perform public.write_audit('customer_reward_vouchers', null, 'audm_new_wa_voucher_rights', null, '{"m": "audmnew"}');
  perform public.write_audit_ex('customer_reward_vouchers', null, 'audm_new_wax_voucher_refund', null, '{"m": "audmnew"}', 'refunds');
  perform public.write_audit_ex('customer_reward_vouchers', null, 'audm_new_wax_voucher_carried', null, '{"m": "audmnew"}', 'invoices');
  perform set_config('request.jwt.claims', '', true);

  v_got := (select string_agg(concat_ws(':', a.action, coalesce(a.module, '-'), coalesce(a.actor_role, '-'),
                                        case a.changed_by when o then 'owner' when s then 'staff' else '-' end), ',' order by a.action collate "C")
              from public.audit_logs a where a.new_data ->> 'm' = 'audmnew');
  v_want := 'audm_new_wa_affiliate:affiliate_accounts:owner:owner,audm_new_wa_owner:commissions:owner:owner,'
            'audm_new_wa_staff:inventory:staff:staff,audm_new_wa_system:invoices:-:-,'
            'audm_new_wa_voucher_rights:therapy:owner:owner,'
            'audm_new_wax_affiliate:affiliate:owner:owner,audm_new_wax_commission:commission:owner:owner,'
            'audm_new_wax_none:invoices:owner:owner,audm_new_wax_voucher_carried:invoices:owner:owner,'
            'audm_new_wax_voucher_refund:refunds:owner:owner';
  if v_got is distinct from v_want then
    perform pg_temp.audm_fail('4: write_audit and write_audit_ex saved ' || coalesce(v_got, 'nothing') || ', not ' || v_want);
  end if;
  if not exists (select 1 from public.audit_logs a where a.action = 'audm_new_wax_commission' and a.reason = 'a reason'
                  and a.store_id = st and a.ip_address = '10.0.0.1' and a.device_info = 'a device') then
    perform pg_temp.audm_fail('4: write_audit_ex no longer saves the reason, store, address and device');
  end if;
  -- write_audit sets the module itself (the owner's rule), not only through
  -- the trigger: with the trigger off it still saves its table's.
  alter table public.audit_logs disable trigger audit_logs_fill_module;
  perform public.write_audit('special_sales', null, 'audm_wa_trigger_off', null, '{"m": "audmoff"}');
  alter table public.audit_logs enable trigger audit_logs_fill_module;
  if (select a.module from public.audit_logs a where a.action = 'audm_wa_trigger_off') is distinct from 'special' then
    perform pg_temp.audm_fail('4: write_audit does not set the module itself');
  end if;

  -- Real server functions, as the page calls them, signed in as the Owner:
  -- one through write_audit, one that writes audit_logs itself with no module.
  v_out := pg_temp.audm_try('owner', 'select public.set_staff_commission_rate(3)::text');
  if split_part(v_out, chr(9), 1) <> 'ok' then
    perform pg_temp.audm_fail('4: set_staff_commission_rate failed for the Owner: ' || v_out);
  end if;
  if (select string_agg(concat_ws(':', a.table_name, a.module, a.actor_role), ',') from public.audit_logs a
       where a.action = 'staff_commission_rate_set' and a.changed_by = o) is distinct from 'app_settings:settings:owner' then
    perform pg_temp.audm_fail('4: set_staff_commission_rate''s entry is not filed under settings');
  end if;
  v_out := pg_temp.audm_try('owner', 'select public.upsert_therapy_service(null, ''AUDM-SVC-1'', ''AUDM service'', 10, null, ''unrestricted'')::text');
  if split_part(v_out, chr(9), 1) <> 'ok' then
    perform pg_temp.audm_fail('4: upsert_therapy_service failed for the Owner: ' || v_out);
  else
    v_svc := (substr(v_out, 4)::jsonb ->> 'id')::uuid;
    -- It saves no role, as before: only the module is added.
    if (select string_agg(concat_ws(':', a.action, a.module, coalesce(a.actor_role, '-')), ',') from public.audit_logs a
         where a.table_name = 'therapy_services' and a.record_id = v_svc and a.changed_by = o)
       is distinct from 'therapy_service_created:therapy:-' then
      perform pg_temp.audm_fail('4: upsert_therapy_service''s entry is not filed under therapy');
    end if;
  end if;

  -- The owner's answer of 18 Oct 2026, through the real routines, as server
  -- functions call them for the Owner (none of the three is a client's).
  -- A voucher issued before it was described, then given therapy rights
  -- afterwards: filed under therapy.
  insert into public.customers(full_name, phone) values ('AUDM Voucher Holder', '+61491570737') returning id into v_cust;
  insert into public.vouchers(name, code, voucher_kind, selling_price)
  values ('AUDM voucher', 'AUDM-V1', 'normal', 120) returning id into v_voucher;
  insert into public.customer_reward_vouchers(customer_id, voucher_id, store_id, quantity)
  values (v_cust, v_voucher, st, 1) returning id into v_rv;
  v_out := pg_temp.audm_try('owner', format('select public.upsert_therapy_voucher_definition(%L, %L::jsonb)::text', v_voucher,
             jsonb_build_array(jsonb_build_object('kind', 'fixed', 'service_id', v_svc, 'quantity', 1))));
  if split_part(v_out, chr(9), 1) <> 'ok' then
    perform pg_temp.audm_fail('4: upsert_therapy_voucher_definition failed for the Owner: ' || v_out);
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', o, 'role', 'authenticated')::text, true);
  perform public.apply_therapy_voucher_rights_retrospectively(v_rv);
  -- A FOC reason saved, then switched off: filed under invoices.
  v_foc := public.upsert_foc_reason('AUDM_FOC', 'AUDM reason');
  perform public.set_foc_reason_active(v_foc, false);
  perform set_config('request.jwt.claims', '', true);
  if (select string_agg(concat_ws(':', a.table_name, a.action, a.module, a.actor_role), ',' order by a.table_name collate "C", a.action collate "C")
        from public.audit_logs a where a.changed_by = o and a.record_id in (v_rv, v_foc))
     is distinct from 'customer_reward_vouchers:therapy_rights_applied_retrospectively:therapy:owner,'
                      'foc_reasons:foc_reason_active_changed:invoices:owner,foc_reasons:foc_reason_saved:invoices:owner' then
    perform pg_temp.audm_fail('4: the therapy voucher-rights or FOC-reason entries are not filed under therapy and invoices: '
      || coalesce((select string_agg(concat_ws(':', a.table_name, a.action, a.module, a.actor_role), ',' order by a.table_name collate "C", a.action collate "C")
                     from public.audit_logs a where a.record_id in (v_rv, v_foc)), 'none'));
  end if;

  -- The service role writing the table straight (as an Edge Function could).
  v_out := pg_temp.audm_try('service', 'insert into public.audit_logs (table_name, action, new_data) values '
                                       || '(''user_invitations'', ''audm_new_service'', ''{"m": "audmlater"}'') returning module');
  if v_out <> 'ok' || chr(9) || 'users' then
    perform pg_temp.audm_fail('4: an entry the service role wrote with no module is not filed under its table''s: ' || v_out);
  end if;

  -- Written straight into the table with every column but the module: only
  -- the module is set.
  insert into public.audit_logs (id, table_name, record_id, action, old_data, new_data, changed_by, created_at,
                                 actor_role, module, reason, store_id, ip_address, device_info)
  values (v_id, 'customers', v_rec, 'audm_new_direct', '{"a": 1}', '{"m": "audmlater"}', o,
          timestamptz '2026-08-15 01:02:03+00', 'manager', null, 'a direct reason', st, '10.0.0.2', 'a device 2');
  select to_jsonb(a) into v_row from public.audit_logs a where a.id = v_id;
  if v_row ->> 'module' is distinct from 'customers'
     or (v_row - 'module') <> jsonb_build_object('id', v_id, 'table_name', 'customers', 'record_id', v_rec,
          'action', 'audm_new_direct', 'old_data', '{"a": 1}'::jsonb, 'new_data', '{"m": "audmlater"}'::jsonb, 'changed_by', o,
          'created_at', v_row -> 'created_at', 'actor_role', 'manager', 'reason', 'a direct reason', 'store_id', st,
          'ip_address', '10.0.0.2', 'device_info', 'a device 2')
     or (v_row ->> 'created_at')::timestamptz <> timestamptz '2026-08-15 01:02:03+00' then
    perform pg_temp.audm_fail('4: the trigger changed more than the empty module: ' || v_row::text);
  end if;
  -- A module given is kept, whatever the table.
  insert into public.audit_logs (table_name, action, module, new_data)
  values ('customers', 'audm_new_given', 'audm_given', '{"m": "audmlater"}'),
         ('invoices', 'audm_new_given_commission', 'commission', '{"m": "audmlater"}');
  if (select string_agg(a.action || ':' || a.module, ',' order by a.action collate "C") from public.audit_logs a
       where a.action in ('audm_new_given', 'audm_new_given_commission'))
     is distinct from 'audm_new_given:audm_given,audm_new_given_commission:commission' then
    perform pg_temp.audm_fail('4: a module given with the entry was not kept as given');
  end if;

  -- An update does not fill a module: the trigger is for new entries only.
  update public.audit_logs set reason = 'audmold' where action = 'audm_old_profile';
  if (select a.module from public.audit_logs a where a.action = 'audm_old_profile') is not null then
    perform pg_temp.audm_fail('4: updating an entry saved with no module gave it one');
  end if;
end $$;

-- ── 5. The Audit Log: one name for commissions ──────────────────────────────
do $$
declare j jsonb; j2 jsonb; c jsonb; v_before text; v_after text; v_want_total int;
begin
  select md5(string_agg(to_jsonb(a)::text, '' order by a.id)) into v_before from public.audit_logs a;

  -- The rows: "commission" shown as "commissions"; an entry with no module
  -- still marked as taken from its table, also for a table 428 did not name.
  j := pg_temp.audm_page('p_text => ''audmold'', p_limit => 100');
  if pg_temp.audm_shown(j) is distinct from
       'audm_old_affiliate_acct:affiliate_accounts:false,audm_old_commission:commissions:true,'
       'audm_old_commissions:commissions:true,audm_old_foc_reason:invoices:false,audm_old_invoice:invoice:true,'
       'audm_old_invoices:invoices:true,audm_old_profile:users:false,audm_old_staff_comm:commissions:false,'
       'audm_old_voucher_carried:invoices:true,audm_old_voucher_refund:refunds:true,audm_old_voucher_rights:therapy:false,'
       'audm_old_voucher_stock:inventory:false' then
    perform pg_temp.audm_fail('5: the old entries are not shown as tested: ' || pg_temp.audm_shown(j));
  end if;
  j := pg_temp.audm_page('p_text => ''audmnew'', p_limit => 100');
  if pg_temp.audm_shown(j) is distinct from
       'audm_new_wa_affiliate:affiliate_accounts:true,audm_new_wa_owner:commissions:true,audm_new_wa_staff:inventory:true,'
       'audm_new_wa_system:invoices:true,audm_new_wa_voucher_rights:therapy:true,audm_new_wax_affiliate:affiliate:true,'
       'audm_new_wax_commission:commissions:true,audm_new_wax_none:invoices:true,audm_new_wax_voucher_carried:invoices:true,'
       'audm_new_wax_voucher_refund:refunds:true' then
    perform pg_temp.audm_fail('5: the new entries are not shown as tested: ' || pg_temp.audm_shown(j));
  end if;

  -- A filter by either name finds the same entries: stored either way, or
  -- taken from the table.
  j := pg_temp.audm_page('p_module => ''commission'', p_text => ''audmold''');
  j2 := pg_temp.audm_page('p_module => ''commissions'', p_text => ''audmold''');
  if (j ->> 'total')::int <> 3 or j -> 'rows' <> j2 -> 'rows' or (j2 ->> 'total')::int <> 3
     or pg_temp.audm_shown(j) <> 'audm_old_commission:commissions:true,audm_old_commissions:commissions:true,audm_old_staff_comm:commissions:false' then
    perform pg_temp.audm_fail('5: the commission filters differ or miss an entry: ' || pg_temp.audm_shown(j) || ' / ' || pg_temp.audm_shown(j2));
  end if;
  j := pg_temp.audm_page('p_module => ''commission'', p_text => ''audm'', p_limit => 100');
  if (j ->> 'total')::int <> 6 then
    perform pg_temp.audm_fail('5: the commission filter does not find every commission entry, old and new: ' || pg_temp.audm_shown(j));
  end if;
  -- Other names that differ by a letter stay apart.
  -- ("invoices" also holds the FOC reason taken from its table and the
  -- voucher entry saved as "invoices".)
  if (pg_temp.audm_page('p_module => ''invoice'', p_text => ''audmold''') ->> 'total')::int <> 1
     or (pg_temp.audm_page('p_module => ''invoices'', p_text => ''audmold''') ->> 'total')::int <> 3 then
    perform pg_temp.audm_fail('5: "invoice" and "invoices" are no longer apart');
  end if;
  -- The owner's answer of 18 Oct 2026: the voucher entry with no module is
  -- found under therapy, the one saved as "refunds" under refunds, and the
  -- three voucher entries stay one table.
  j := pg_temp.audm_page('p_module => ''therapy'', p_text => ''audmold''');
  j2 := pg_temp.audm_page('p_module => ''refunds'', p_text => ''audmold''');
  if pg_temp.audm_shown(j) is distinct from 'audm_old_voucher_rights:therapy:false'
     or pg_temp.audm_shown(j2) is distinct from 'audm_old_voucher_refund:refunds:true'
     or (pg_temp.audm_page('p_table => ''customer_reward_vouchers'', p_text => ''audmold''') ->> 'total')::int <> 3
     or (pg_temp.audm_page('p_table => ''foc_reasons'', p_module => ''invoices'', p_text => ''audmold''') ->> 'total')::int <> 1 then
    perform pg_temp.audm_fail('5: the voucher and FOC-reason entries are not found as filed: ' || pg_temp.audm_shown(j) || ' / ' || pg_temp.audm_shown(j2));
  end if;
  -- A module taken from a table 428 did not name filters as shown.
  if (pg_temp.audm_page('p_module => ''inventory'', p_text => ''audmold''') ->> 'total')::int <> 1 then
    perform pg_temp.audm_fail('5: voucher store stock with no module is not found under inventory');
  end if;
  -- Text matches the module as shown: "commissions" finds the entry saved as "commission".
  j := pg_temp.audm_page('p_text => ''commissions'', p_table => ''invoices'', p_from => date ''2026-09-01'', p_to => date ''2026-09-01''');
  if not exists (select 1 from jsonb_array_elements(j -> 'rows') r where r ->> 'action' = 'audm_old_commission') then
    perform pg_temp.audm_fail('5: searching "commissions" does not find the entry saved as "commission"');
  end if;
  -- The table filter is unchanged.
  if (pg_temp.audm_page('p_table => ''invoices'', p_text => ''audmold''') ->> 'total')::int <> 3 then
    perform pg_temp.audm_fail('5: the table filter changed');
  end if;

  -- The choices: one "commissions", with every commission entry counted; no
  -- "commission"; "invoice" and "invoices" both; sorted.
  c := pg_temp.audm_page('p_with_choices => true, p_limit => 1') -> 'choices';
  select count(*) into v_want_total from public.audit_logs a where public.audit_module(a.module, a.table_name) = 'commissions';
  if c is null
     or exists (select 1 from jsonb_array_elements(c -> 'modules') x where x ->> 'value' = 'commission')
     or (select count(*) from jsonb_array_elements(c -> 'modules') x where x ->> 'value' = 'commissions') <> 1
     or (select (x ->> 'count')::int from jsonb_array_elements(c -> 'modules') x where x ->> 'value' = 'commissions') <> v_want_total
     or not exists (select 1 from jsonb_array_elements(c -> 'modules') x where x ->> 'value' = 'invoice')
     or not exists (select 1 from jsonb_array_elements(c -> 'modules') x where x ->> 'value' = 'invoices')
     or (select array_agg(x ->> 'value' order by o) from jsonb_array_elements(c -> 'modules') with ordinality t(x, o))
        <> (select array_agg(x ->> 'value' order by x ->> 'value') from jsonb_array_elements(c -> 'modules') x) then
    perform pg_temp.audm_fail('5: the module choices are not one sorted list with one commissions: ' || coalesce((c -> 'modules')::text, 'none'));
  end if;
  if v_want_total < 6 then
    perform pg_temp.audm_fail('5: fewer commission entries than the fixture holds: ' || v_want_total);
  end if;

  -- Reading changed nothing.
  select md5(string_agg(to_jsonb(a)::text, '' order by a.id)) into v_after from public.audit_logs a;
  if v_after <> v_before then
    perform pg_temp.audm_fail('5: reading the Audit Log changed an entry');
  end if;
end $$;

-- ── 5b. What rule 4 leaves as it was (review of 18 Oct 2026) ────────────────
-- FOC invoices saved as "foc" stay under "foc", apart from the FOC-reason
-- changes now under "invoices" (module names already in use are kept). And
-- any entry for customer_reward_vouchers that comes with no module, whoever
-- writes it, is filed under "therapy"; a writer whose entry is not about
-- therapy passes its own module, which is kept.
do $$
declare j jsonb; c jsonb; o uuid := pg_temp.audm_id('owner');
begin
  perform set_config('request.jwt.claims', json_build_object('sub', o, 'role', 'authenticated')::text, true);
  perform public.write_audit_ex('invoices', null, 'audm_foc_invoice', null, '{"m": "audmfoc"}', 'foc');
  perform public.write_audit('foc_reasons', null, 'audm_foc_reason', null, '{"m": "audmfoc"}');
  perform public.write_audit_ex('customer_reward_vouchers', null, 'audm_foc_voucher_other', null, '{"m": "audmfoc"}', 'audm_other');
  perform set_config('request.jwt.claims', '', true);
  insert into public.audit_logs (table_name, action, module, new_data)
  values ('customer_reward_vouchers', 'audm_foc_voucher_direct', null, '{"m": "audmfoc"}');

  j := pg_temp.audm_page('p_text => ''audmfoc'', p_limit => 100');
  if pg_temp.audm_shown(j) is distinct from
       'audm_foc_invoice:foc:true,audm_foc_reason:invoices:true,audm_foc_voucher_direct:therapy:true,audm_foc_voucher_other:audm_other:true' then
    perform pg_temp.audm_fail('5b: FOC invoices, FOC reasons and voucher entries are not shown as tested: ' || pg_temp.audm_shown(j));
  end if;
  if pg_temp.audm_shown(pg_temp.audm_page('p_module => ''foc'', p_text => ''audmfoc'''))
       is distinct from 'audm_foc_invoice:foc:true'
     or pg_temp.audm_shown(pg_temp.audm_page('p_module => ''invoices'', p_text => ''audmfoc'''))
       is distinct from 'audm_foc_reason:invoices:true'
     or pg_temp.audm_shown(pg_temp.audm_page('p_module => ''therapy'', p_text => ''audmfoc'''))
       is distinct from 'audm_foc_voucher_direct:therapy:true' then
    perform pg_temp.audm_fail('5b: filtering by foc, invoices or therapy does not keep them apart');
  end if;
  c := pg_temp.audm_page('p_with_choices => true, p_limit => 1') -> 'choices';
  if not exists (select 1 from jsonb_array_elements(c -> 'modules') x where x ->> 'value' = 'foc')
     or not exists (select 1 from jsonb_array_elements(c -> 'modules') x where x ->> 'value' = 'invoices') then
    perform pg_temp.audm_fail('5b: the module choices do not offer both foc and invoices');
  end if;
end $$;

-- ── 6. 431 refused each database it was not tested against ──────────────────
-- The messages were kept above, one per case; an empty one means 431 ran.
do $$
declare r record;
begin
  for r in select * from (values
    ('g_write_audit', '431: public.write_audit(text,uuid,text,jsonb,jsonb) is not the version this was tested against%'),
    ('g_page', '431: public.audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean) is not the version this was tested against%'),
    ('g_406', '431: 406 is not in%'),
    ('g_role', '431: public.current_user_role() is missing or not the version read on 9 Oct 2026%'),
    ('g_cols', '431: public.audit_logs is not shaped as read on 9 Oct 2026%'),
    ('g_new_fn', '431: public.audit_module(text,text) exists and is not this migration''s version%'),
    ('g_overload', '431: another function takes one of these names: audit_module(text)%'),
    ('g_trigger', '431: a trigger audit_logs_fill_module exists on public.audit_logs and is not this migration''s%')
  ) x(k, want) loop
    if coalesce(current_setting('audm.' || r.k, true), '') not like r.want then
      perform pg_temp.audm_fail('6: 431 did not refuse (' || r.k || '): '
                                || coalesce(nullif(current_setting('audm.' || r.k, true), ''), 'it ran'));
    end if;
  end loop;
end $$;

-- ── Result ──────────────────────────────────────────────────────────────────
do $$
declare v_fail text;
begin
  select string_agg(msg, E'\n  ' order by n) into v_fail from audm_fail;
  if v_fail is not null then
    raise exception E'FAIL (%):\n  %', (select count(*) from audm_fail), v_fail;
  end if;
  raise notice 'PASS: 431 files every new audit entry under a module (write_audit its table''s; write_audit_ex the one passed, or its table''s; an entry written straight with none, its table''s, and nothing else changed); takes the module from the table with 428''s list and the added tables, never "affiliate"; files the therapy voucher-rights routine under therapy and FOC-reason changes under invoices while voucher entries saved as refunds or invoices keep them and FOC invoices stay under foc; shows, filters, searches and offers "commission" and "commissions" as one module while other names stay apart; leaves every saved entry and every other function as it was, applied and re-run; refuses, changing nothing, on each of 8 databases it was not tested against; and keeps the writers and helpers for the server, and the Audit Log for Owners, Admins and Managers.';
end $$;
rollback;
