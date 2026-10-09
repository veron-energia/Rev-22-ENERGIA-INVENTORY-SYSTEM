-- 428_audit_log_paging.sql
--
-- WHAT WAS WRONG (the audit of 9 Oct 2026: REPORTS-10, with REPORTS-5)
--
--   The Audit Log page read the newest 500 entries straight from the table and
--   filtered them in the browser. On 9 Oct 2026 production held 5,045 entries;
--   the newest 500 went back only to 30 Sep, so nothing older could be found
--   at all. Search looked at the action, the table and the person only: not
--   the reason, the record or invoice number, or what was changed. The Excel
--   export had no By or Role column and an always-empty Category column (the
--   table has no such column), so it could not serve as evidence. Times were
--   in the device's time zone. A failed read showed "No audit entries".
--   2,380 entries have no module, and new ones keep arriving: everything
--   written through write_audit(), which 42 functions still call (invoices,
--   commissions, inventory adjustments, vouchers and more), is saved without
--   one. 156 have no role. The table has no index on its time (only the
--   primary key and record_id).
--
-- THE RULES
--
--   1. Who may read the Audit Log is unchanged: active Owners, Admins and
--      Managers (the page's isManagerOrAbove, and the table's read rule
--      is_manager_or_above()).
--   2. Every entry can be reached: the server pages and filters, newest first.
--   3. Entries are evidence: they are read, never changed. An entry saved
--      without a module has one taken from its table when it is read, and it
--      is marked as taken from the table.
--   4. Dates are Singapore days.
--
-- WHAT THIS DOES
--
--   * audit_log_page(p_from, p_to, p_module, p_table, p_actor, p_text,
--     p_limit, p_offset, p_as_of, p_with_choices) (new; the Audit Log page
--     calls it). Its first statement is require_active_staff(Owner, Admin,
--     Manager) (406). It returns one page as jsonb:
--       rows: id, created_at, action, table_name, module (stored, or taken
--         from the table), module_recorded (false when taken from the table),
--         changed_by, actor_name ('System' when nobody), actor_role, reason,
--         record_id, record_label (the invoice number when the entry is an
--         invoice's), old_data, new_data; newest first;
--       total: how many entries match;
--       as_of: the time the search was made; the page passes it back.
--         Entries made after the search started are left out of its next
--         pages and of an export read a page at a time. An entry is dated
--         when its write began, so one from a write still in progress when
--         the search started can still appear later and move the rest down a
--         place; the page's export skips an entry it already has;
--       choices (only when p_with_choices): every module, table and person in
--         the log, with how many entries each has, for the page's filters.
--     Filters, each optional: from and to (Singapore days, both included), a
--     module (the shown one), a table, a person, and text. Text is matched as
--     typed (% and _ are not wildcards) against the action and the person's
--     role (each also with its underscores as spaces, as the page shows it),
--     the table, the module, the person's name, the reason, the record id,
--     the invoice number and the old and new details. A page is 1 to 1000
--     entries (default 50); an end date before the start date is refused.
--     Granted to signed-in logins (the check refuses all but active Owners,
--     Admins and Managers) and the service role; not to anon.
--   * idx_audit_logs_created_at (new index): audit_logs (created_at desc, id
--     desc), the order every page reads.
--
-- NOT CHANGED
--
--   * public.audit_logs: no row is written, changed or removed; its columns,
--     its read rule, its grants and its trigger stay as they are.
--   * Who writes entries, and how (write_audit, write_audit_ex and the
--     triggers).
--   * is_manager_or_above(), require_active_staff() and the rest of 406.
--   * The modules stored with entries. Their names are not made consistent
--     (both "commission" and "commissions" are in use); the filter lists
--     each as it is.
--   * write_audit() still saves entries without a module. Having it record
--     one (the same table-to-module mapping, or a module from its callers)
--     is a follow-up, not part of this.
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. It
--   refuses unless 406 is in (require_active_staff at its AFTER md5);
--   audit_logs, profiles and invoices have the columns read on 9 Oct 2026;
--   the new function is missing or already exactly this version and no other
--   function takes its name; the index is missing or already exactly this
--   one; and the function text has its AFTER md5 before it is installed.
--   Creating the index holds new audit entries back for as long as it takes
--   (about 5,000 rows on 9 Oct 2026, well under a second); the lock timeout
--   stops it waiting behind a long write. Afterwards the md5, the index and
--   the grants are as tested, and, switching role: the anon key cannot call
--   it, and a signed-in login with no profile is refused. Then, inside a
--   block that is always undone, a made-up Owner and member of staff and
--   three made-up entries: Staff is refused; the Owner finds the three by
--   text, newest first, pages them, filters them by Singapore day, module,
--   table and person, sees the module taken from the table and "System",
--   and gets the choices; % and _ are not wildcards; a page of 0 and a
--   reversed date range are refused. Nothing is printed and no row remains.
--
-- BEFORE (production, 9 Oct 2026, read again after 414; md5 of pg_get_functiondef,
-- search_path public):
--   relied on, not changed
--   require_active_staff(text[])            877b3aa74cea559881979bb161c450e2  (406's AFTER)
--   read for the rule, not relied on
--   is_manager_or_above()                   f12b9ed342070fa4defa30e4da2ba655
--   new: audit_log_page(date,date,text,text,uuid,text,integer,integer,
--        timestamp with time zone,boolean) (missing); idx_audit_logs_created_at (missing)
--   public function fingerprint, after 414  af220b17c3d38e0ac75375c31ed12f2b
--   (this was written against 675ac22c631079b58f06813d0d463fa3, after 413; 414
--   changed other functions, none read here. The fingerprint is not guarded:
--   only the md5s above and the columns below are.)
-- AFTER (for later guards):
--   audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean)
--                                           1b9054e6e243a81e640f0a2a4b18202e
--   public function fingerprint, if this is the only change after 414
--                                           42369847c7cf009c7ce090f767c5f844
--   (worked out from production after 414, not yet seen; other migrations of
--   this round change it too; the md5 above is the guard)
--
-- DEPLOY ORDER: this, then the front end (the Audit Log page calls
-- audit_log_page). The page live now reads the table directly and keeps
-- working against this. The new page against a database without this shows
-- "The audit log could not be loaded" with the API's message, so this goes
-- first.
--
-- Test: scripts/audit-log/tests/audit-log-page.sql (every role, the filters,
-- the text search, the paging and its tie-break, the as-of time, the choices,
-- the grants),
-- scripts/audit-log/tests/audit-log-page.test.mjs (the page),
-- scripts/permissions/tests/staff-only-functions.sql,
-- scripts/permissions/tests/function-grants.sql.

set lock_timeout = '5s';

do $mig$
declare
  c_def constant text := $def$CREATE OR REPLACE FUNCTION public.audit_log_page(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_module text DEFAULT NULL::text, p_table text DEFAULT NULL::text, p_actor uuid DEFAULT NULL::uuid, p_text text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_as_of timestamp with time zone DEFAULT NULL::timestamp with time zone, p_with_choices boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_as_of timestamptz := least(coalesce(p_as_of, now()), now());
  v_limit integer := coalesce(p_limit, 50);
  v_offset integer := coalesce(p_offset, 0);
  v_like text;
  v_result jsonb;
begin
  -- 428: one page of the Audit Log, newest first, with its filters, read on
  -- the server so every entry can be reached (the page used to read only the
  -- newest 500). Owners, Admins and Managers, as the page and the table's
  -- read rule (is_manager_or_above) allow.
  perform public.require_active_staff(array['owner', 'admin', 'manager']);
  if v_limit < 1 or v_limit > 1000 then
    raise exception 'A page holds 1 to 1000 entries.' using errcode = '22023';
  end if;
  if v_offset < 0 then
    raise exception 'A page cannot start before the first entry.' using errcode = '22023';
  end if;
  if p_from is not null and p_to is not null and p_to < p_from then
    raise exception 'The end date cannot be before the start date.' using errcode = '22023';
  end if;
  -- Searched as typed: % and _ are letters here, not wildcards.
  if nullif(btrim(p_text), '') is not null then
    v_like := '%' || replace(replace(replace(btrim(p_text), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end if;

  -- Entries up to the as-of time only, so the pages of one search (and an
  -- export read page by page) leave out entries made after it started. An
  -- entry is dated when its write began, so one still being written then can
  -- appear later.
  -- Module: the one stored with the entry. Entries saved without one (all of
  -- write_audit()'s) have it taken from the table here, at read time, and
  -- marked so. The entries themselves are never changed: they are the evidence.
  -- Dates are Singapore days.
  with entries as not materialized (
    select a.id, a.created_at, a.action, a.table_name,
           coalesce(a.module, case
             when a.table_name = 'invoices' then 'invoices'
             when a.table_name in ('commissions', 'commission_payouts', 'staff_commissions') then 'commissions'
             when a.table_name in ('inventory_adjustment', 'warehouse_inventory', 'special_product_stock') then 'inventory'
             when a.table_name in ('vouchers', 'credit_packages', 'promotion_items', 'unlimited_therapy_packages') then 'catalogue'
             when a.table_name = 'therapy_services' then 'therapy'
             when a.table_name in ('customers', 'customer_source_options') then 'customers'
             when a.table_name = 'transfer_requests' then 'transfers'
             when a.table_name = 'product_exchanges' then 'exchanges'
             when a.table_name = 'rentals' then 'rentals'
             when a.table_name = 'app_settings' then 'settings'
             when a.table_name = 'profiles' then 'users'
             else a.table_name end) as module,
           a.module is not null as module_recorded,
           a.changed_by,
           case when a.changed_by is null then 'System'
                else coalesce(nullif(btrim(p.full_name), ''), 'Unknown login') end as actor_name,
           a.actor_role, a.reason, a.record_id,
           i.invoice_no as record_label,
           a.old_data, a.new_data
      from public.audit_logs a
      left join public.profiles p on p.id = a.changed_by
      left join public.invoices i on a.table_name = 'invoices' and i.id = a.record_id
     where a.created_at <= v_as_of
  ),
  matches as not materialized (
    select e.*
      from entries e
     where (p_from is null or e.created_at >= (p_from::timestamp at time zone 'Asia/Singapore'))
       and (p_to is null or e.created_at < ((p_to + 1)::timestamp at time zone 'Asia/Singapore'))
       and (p_module is null or e.module = p_module)
       and (p_table is null or e.table_name = p_table)
       and (p_actor is null or e.changed_by = p_actor)
       and (v_like is null
            or e.action ilike v_like or replace(e.action, '_', ' ') ilike v_like
            or e.table_name ilike v_like or e.module ilike v_like
            or e.actor_name ilike v_like
            or e.actor_role ilike v_like or replace(e.actor_role, '_', ' ') ilike v_like
            or e.reason ilike v_like or e.record_label ilike v_like
            or e.record_id::text ilike v_like
            or e.new_data::text ilike v_like or e.old_data::text ilike v_like)
  )
  select jsonb_build_object(
           'as_of', v_as_of,
           'total', (select count(*) from matches),
           'rows', coalesce((select jsonb_agg(to_jsonb(pg) order by pg.created_at desc, pg.id desc)
                               from (select m.* from matches m
                                      order by m.created_at desc, m.id desc
                                      limit v_limit offset v_offset) pg), '[]'::jsonb),
           -- What the filters can offer: every module, table and person in the
           -- log, with how many entries each has. Asked for by the page only.
           'choices', case when p_with_choices then jsonb_build_object(
             'modules', (select coalesce(jsonb_agg(jsonb_build_object('value', x.module, 'count', x.n) order by x.module), '[]'::jsonb)
                           from (select e.module, count(*) as n from entries e group by e.module) x),
             'tables', (select coalesce(jsonb_agg(jsonb_build_object('value', x.table_name, 'count', x.n) order by x.table_name), '[]'::jsonb)
                          from (select e.table_name, count(*) as n from entries e group by e.table_name) x),
             'actors', (select coalesce(jsonb_agg(jsonb_build_object('id', x.changed_by, 'name', x.actor_name, 'count', x.n)
                                                  order by lower(x.actor_name), x.changed_by), '[]'::jsonb)
                          from (select e.changed_by, e.actor_name, count(*) as n from entries e
                                 where e.changed_by is not null group by e.changed_by, e.actor_name) x)) end)
    into v_result;
  return v_result;
end
$function$
$def$;
  c_after     constant text := '1b9054e6e243a81e640f0a2a4b18202e';
  c_staff_406 constant text := '877b3aa74cea559881979bb161c450e2';
  c_sig       constant text := 'public.audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean)';
  c_index     constant text := 'CREATE INDEX idx_audit_logs_created_at ON public.audit_logs USING btree (created_at DESC, id DESC)';
  -- The columns of audit_logs this reads, as read on 9 Oct 2026.
  c_cols      constant text := 'action text not null|actor_role text|changed_by uuid|created_at timestamp with time zone not null|id uuid not null|module text|new_data jsonb|old_data jsonb|reason text|record_id uuid|table_name text not null';
  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v text; v_bad text; v_fn_new boolean; v_index_new boolean;
  v_owner uuid; v_staff uuid; v_mark text; j jsonb; v_state text;
begin
  perform set_config('search_path', 'public', true);

  -- ── Guards: nothing changes unless all pass ──────────────────────────────
  -- 406 is in.
  if to_regprocedure('public.require_active_staff(text[])') is null
     or md5(pg_get_functiondef('public.require_active_staff(text[])'::regprocedure)) <> c_staff_406 then
    raise exception '428: 406 is not in (require_active_staff(text[]) is not 406''s version); apply 406 first'; end if;

  -- The tables, as read on 9 Oct 2026.
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' not null' else '' end,
                    '|' order by a.attname) into v
    from pg_attribute a
   where a.attrelid = 'public.audit_logs'::regclass and a.attnum > 0 and not a.attisdropped
     and a.attname in ('id', 'created_at', 'action', 'table_name', 'module', 'changed_by', 'actor_role',
                       'reason', 'record_id', 'old_data', 'new_data');
  if v is distinct from c_cols then
    raise exception '428: public.audit_logs is not shaped as read on 9 Oct 2026 (%)', v; end if;
  select string_agg(a.attrelid::regclass::text || '.' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|'
                    order by a.attrelid::regclass::text, a.attname) into v
    from pg_attribute a
   where not a.attisdropped
     and ((a.attrelid = 'public.profiles'::regclass and a.attname in ('id', 'full_name'))
          or (a.attrelid = 'public.invoices'::regclass and a.attname in ('id', 'invoice_no')));
  if v is distinct from 'invoices.id uuid|invoices.invoice_no text|profiles.full_name text|profiles.id uuid' then
    raise exception '428: public.profiles or public.invoices is not shaped as read on 9 Oct 2026 (%)', v; end if;

  -- The new function: missing, or already this version; no other takes its name.
  v_fn_new := to_regprocedure(c_sig) is null;
  if not v_fn_new and md5(pg_get_functiondef(to_regprocedure(c_sig))) <> c_after then
    raise exception '428: % exists and is not this migration''s version', c_sig; end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'audit_log_page'
     and p.oid::regprocedure::text <> 'audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean)';
  if v_bad is not null then
    raise exception '428: another function takes the name audit_log_page: %', v_bad; end if;

  -- The index: missing, or already exactly this; nothing else takes its name.
  v_index_new := to_regclass('public.idx_audit_logs_created_at') is null;
  if not v_index_new
     and (select pg_get_indexdef(i.indexrelid) from pg_index i
           where i.indexrelid = to_regclass('public.idx_audit_logs_created_at')) is distinct from c_index then
    raise exception '428: public.idx_audit_logs_created_at exists and is not this migration''s index'; end if;

  -- The text is the tested one.
  if md5(c_def) <> c_after then
    raise exception '428: the function text is not the tested one'; end if;

  -- ── Change ───────────────────────────────────────────────────────────────
  if v_fn_new then
    execute c_def;
  end if;
  revoke all on function public.audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean)
    from public, anon;
  grant execute on function public.audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean)
    to authenticated, service_role;
  if v_index_new then
    create index idx_audit_logs_created_at on public.audit_logs (created_at desc, id desc);
  end if;

  -- ── As tested ────────────────────────────────────────────────────────────
  if md5(pg_get_functiondef(c_sig::regprocedure)) <> c_after then
    raise exception '428: installed with an md5 other than the tested one'; end if;
  if (select pg_get_indexdef(i.indexrelid) from pg_index i
       where i.indexrelid = to_regclass('public.idx_audit_logs_created_at') and i.indisvalid) is distinct from c_index then
    raise exception '428: the index is not as tested'; end if;
  if has_function_privilege('anon', c_sig, 'execute')
     or not has_function_privilege('authenticated', c_sig, 'execute')
     or not has_function_privilege('service_role', c_sig, 'execute') then
    raise exception '428: the grants on audit_log_page are not as tested'; end if;

  -- ── Behaviour, switching role (nothing is printed, no row remains) ───────
  -- The anon key, and a signed-in login with no profile (an affiliate's, say).
  foreach v in array array['anon', 'authenticated'] loop
    perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', v)::text, true);
    execute format('set local role %I', v);
    begin
      perform public.audit_log_page();
      raise exception '428: % read the audit log', v;
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';
  end loop;
  perform set_config('request.jwt.claims', '', true);

  -- The page's searches, inside a block that is always undone: a made-up
  -- Owner and member of staff (@sig.invalid) and three made-up entries.
  -- 8 Oct 23:30, 9 Oct 00:30 and 9 Oct 01:00, Singapore time.
  begin
    v_mark := '428chk' || replace(gen_random_uuid()::text, '-', '');
    insert into auth.users (id, email) values (gen_random_uuid(), '428-check-owner-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_owner;
    insert into auth.users (id, email) values (gen_random_uuid(), '428-check-staff-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_staff;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '428 check ' || x.role, u.email, x.role::public.user_role, true
      from auth.users u join (values (v_owner, 'owner'), (v_staff, 'staff')) x(id, role) on x.id = u.id;
    insert into public.audit_logs (table_name, action, module, changed_by, actor_role, reason, old_data, new_data, created_at)
    values ('profiles', 'check_428_one', null, v_owner, 'owner', 'checked 100% ' || v_mark, null, null,
            timestamptz '2026-10-08 15:30:00+00'),
           ('transfer_requests', 'check_428_two', 'transfers', v_staff, 'staff', null, null,
            jsonb_build_object('note', v_mark), timestamptz '2026-10-08 16:30:00+00'),
           ('invoices', 'check_428_three', null, null, null, null, jsonb_build_object('note', v_mark), null,
            timestamptz '2026-10-08 17:00:00+00');

    perform set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      perform public.audit_log_page(p_text => v_mark);
      raise exception '428: Staff read the audit log';
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';

    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.audit_log_page(p_text => v_mark, p_with_choices => true);
    if (j ->> 'total')::int <> 3
       or (select string_agg(r ->> 'action', ',' order by o) from jsonb_array_elements(j -> 'rows') with ordinality t(r, o))
          is distinct from 'check_428_three,check_428_two,check_428_one' then
      raise exception '428: the text search did not find the three entries, newest first'; end if;
    if (select string_agg(concat_ws(':', r ->> 'module', r ->> 'module_recorded', r ->> 'actor_name'), ','
                          order by o) from jsonb_array_elements(j -> 'rows') with ordinality t(r, o))
       is distinct from 'invoices:false:System,transfers:true:428 check staff,users:false:428 check owner' then
      raise exception '428: the module, its mark or the person is not as tested'; end if;
    if not exists (select 1 from jsonb_array_elements(j -> 'choices' -> 'actors') x
                    where x ->> 'id' = v_staff::text and (x ->> 'count')::int = 1)
       or not exists (select 1 from jsonb_array_elements(j -> 'choices' -> 'modules') x where x ->> 'value' = 'users')
       or not exists (select 1 from jsonb_array_elements(j -> 'choices' -> 'tables') x where x ->> 'value' = 'transfer_requests') then
      raise exception '428: the choices are not as tested'; end if;
    j := public.audit_log_page(p_text => v_mark, p_limit => 2, p_offset => 2);
    if (j ->> 'total')::int <> 3 or jsonb_array_length(j -> 'rows') <> 1
       or j -> 'rows' -> 0 ->> 'action' <> 'check_428_one' or coalesce(j -> 'choices', 'null') <> 'null' then
      raise exception '428: the second page is not as tested'; end if;
    if (public.audit_log_page(p_from => date '2026-10-09', p_to => date '2026-10-09', p_text => v_mark) ->> 'total')::int <> 2
       or (public.audit_log_page(p_to => date '2026-10-08', p_text => v_mark) ->> 'total')::int <> 1
       or (public.audit_log_page(p_module => 'users', p_text => v_mark) ->> 'total')::int <> 1
       or (public.audit_log_page(p_table => 'invoices', p_text => v_mark) ->> 'total')::int <> 1
       or (public.audit_log_page(p_actor => v_staff, p_text => v_mark) ->> 'total')::int <> 1
       or (public.audit_log_page(p_text => 'check 428 two') ->> 'total')::int <> 1
       or (public.audit_log_page(p_text => '100% ' || v_mark) ->> 'total')::int <> 1
       or (public.audit_log_page(p_text => v_mark || '_') ->> 'total')::int <> 0
       or (public.audit_log_page(p_text => v_mark, p_as_of => timestamptz '2026-10-08 16:00:00+00') ->> 'total')::int <> 1 then
      raise exception '428: a filter is not as tested'; end if;
    foreach v in array array['select public.audit_log_page(p_limit => 0)',
                             'select public.audit_log_page(p_from => date ''2026-10-09'', p_to => date ''2026-10-08'')'] loop
      begin
        execute v;
        raise exception '428: % was not refused', v;
      exception when invalid_parameter_value then null;
      end;
    end loop;
    execute 'reset role';
    raise exception using errcode = 'P0428', message = '428: check done, undone';
  exception when sqlstate 'P0428' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
