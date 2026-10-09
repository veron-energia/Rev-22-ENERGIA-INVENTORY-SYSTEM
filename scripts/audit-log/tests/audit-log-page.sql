-- The Audit Log, read a page at a time on the server (428, REPORTS-10).
--
-- audit_log_page must answer the roles the Audit Log page is for (active
-- Owners, Admins and Managers) and refuse everyone else with 42501; reach
-- every entry, newest first, a page at a time, entries of one time by id so
-- no page repeats or drops one; filter by Singapore day, module, table, person
-- and text (the role and the module included); take a missing module from the
-- entry's table without changing the entry; find an invoice's entries by its
-- number; keep one search's pages steady with its as-of time; and offer the
-- filters' choices only when asked.
--
-- Needs a database with production's schema and 406 and 428 applied. Run it
-- after 428 in the same transaction on a disposable copy, for example:
--   begin; \i supabase/428_audit_log_paging.sql
--   \i scripts/audit-log/tests/audit-log-page.sql      (its rollback ends both)
-- Everything is rolled back. Fixture names carry AUDX, emails @sig.invalid;
-- nothing real is read or printed.
\set ON_ERROR_STOP on
begin;

create temp table audx(k text primary key, id uuid not null);
create temp table audx_fail(n serial, msg text);

create function pg_temp.audx_id(p text) returns uuid language sql stable as
  $f$ select id from audx where k = p $f$;

-- Run p_sql as one of the fixture's logins and say what happened:
--   'ok' and the result as text, or the SQLSTATE and the message.
-- p_who is a login key, 'anon' (the public key, signed out), 'service' (the
-- service role) or 'server' (no request at all).
create function pg_temp.audx_try(p_who text, p_sql text) returns text language plpgsql as $f$
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
        json_build_object('sub', pg_temp.audx_id(p_who), 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    execute p_sql into v_out;
    execute 'reset role';
    return 'ok' || chr(9) || coalesce(v_out, '');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return v_state || chr(9) || v_msg;
  end;
end $f$;

create function pg_temp.audx_fail(p text) returns void language sql as
  $f$ insert into audx_fail(msg) values (p) $f$;

-- One call as the Owner; the answer as jsonb (a failure fails the test).
create function pg_temp.audx_page(p_args text) returns jsonb language plpgsql as $f$
declare v_out text;
begin
  v_out := pg_temp.audx_try('owner', 'select public.audit_log_page(' || p_args || ')::text');
  if split_part(v_out, chr(9), 1) <> 'ok' then
    perform pg_temp.audx_fail('audit_log_page(' || p_args || ') failed for the Owner: ' || v_out);
    return null;
  end if;
  return substr(v_out, 4)::jsonb;
end $f$;

-- The entries' actions, in the order returned.
create function pg_temp.audx_actions(j jsonb) returns text language sql immutable as
  $f$ select coalesce(string_agg(r ->> 'action', ',' order by o), '')
        from jsonb_array_elements(coalesce(j -> 'rows', '[]')) with ordinality t(r, o) $f$;

-- ── Fixture ──────────────────────────────────────────────────────────────────
do $$
declare k text; v uuid; st uuid; c1 uuid; ca uuid; aff uuid; inv uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  foreach k in array array['owner','admin','manager','invman','staff','inactive','pending','cancelled',
                           'nostaff','affiliate'] loop
    insert into auth.users(id, email) values (gen_random_uuid(), 'audx-' || k || '@sig.invalid') returning id into v;
    insert into audx values (k, v);
  end loop;
  insert into public.profiles(id, full_name, email, role, is_active, invitation_status, created_at, updated_at)
  select s.id, 'AUDX ' || s.k, 'audx-' || s.k || '@sig.invalid', x.role::public.user_role, x.active, x.inv, now(), now()
    from audx s join (values ('owner','owner',true,null), ('admin','admin',true,null), ('manager','manager',true,null),
                             ('invman','inventory_manager',true,null), ('staff','staff',true,null),
                             ('inactive','manager',false,null), ('pending','manager',false,'pending'),
                             ('cancelled','manager',false,'cancelled'))
                     x(k, role, active, inv) on x.k = s.k;
  insert into public.stores(name, code, country_code) values ('AUDX Store', 'AUDXA', 'SG') returning id into st;
  insert into public.user_store_assignments(user_id, store_id)
  select pg_temp.audx_id(x.who), st from unnest(array['manager','invman','staff','inactive']) x(who);
  insert into public.customers(full_name, phone, email) values ('AUDX Customer', '+6591400301', 'audx-c1@sig.invalid') returning id into c1;
  insert into public.customers(full_name, phone, email) values ('AUDX Affiliate', '+6591400302', 'audx-ca@sig.invalid') returning id into ca;
  insert into public.customer_affiliates(customer_id, status, store_id, activated_at)
    values (ca, 'active', st, now()) returning id into aff;
  insert into public.affiliate_accounts(auth_user_id, customer_id, affiliate_id, status)
    values (pg_temp.audx_id('affiliate'), ca, aff, 'claimed');
  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, business_date)
    values ('AUDX-INV-1', st, c1, pg_temp.audx_id('owner'), 'unpaid', 100, 100, public.sg_today()) returning id into inv;
  insert into audx values ('store', st), ('c1', c1), ('inv', inv);

  -- Six entries, all carrying "audxmark" somewhere the search reads, around
  -- the Singapore midnights of 9 and 11 Sep 2026 (16:00 UTC the day before),
  -- all in the past, as the as-of time leaves out anything later than now:
  --   e1 8 Sep 23:59:59 SGT  profiles, no module (taken: users), by the Owner, a reason with % and _
  --   e2 9 Sep 00:00:00 SGT  transfer_requests, module transfers, by Staff, the mark in new_data
  --   e3 9 Sep 00:30 SGT     invoices, no module (taken: invoices), nobody (System), the invoice's
  --                           record id, the mark in old_data
  --   e4 9 Sep 00:30 SGT     invoices, module invoice_edit, by the Manager, same time as e3
  --   e5 10 Sep 23:59 SGT    a table no module is known for, the mark in the action
  --   e6 11 Sep 00:00 SGT    app_settings, no module (taken: settings), a backslash in the reason
  insert into public.audit_logs (table_name, action, module, changed_by, actor_role, reason, record_id, old_data, new_data, created_at)
  values ('profiles', 'audx_one', null, pg_temp.audx_id('owner'), 'owner', 'audxmark checked 100%_done', null, null, null,
          timestamptz '2026-09-08 15:59:59+00'),
         ('transfer_requests', 'audx_two', 'transfers', pg_temp.audx_id('staff'), 'staff', null, null, null,
          '{"note": "audxmark in new"}', timestamptz '2026-09-08 16:00:00+00'),
         ('invoices', 'audx_three', null, null, null, null, inv, '{"note": "audxmark in old"}', null,
          timestamptz '2026-09-08 16:30:00+00'),
         ('invoices', 'audx_four', 'invoice_edit', pg_temp.audx_id('manager'), 'manager', 'audxmark edit', inv, null, null,
          timestamptz '2026-09-08 16:30:00+00'),
         ('audx_side_table', 'audxmark_five', null, pg_temp.audx_id('owner'), 'owner', null, null, null, null,
          timestamptz '2026-09-10 15:59:00+00'),
         ('app_settings', 'audx_six', null, pg_temp.audx_id('owner'), 'owner', 'audxmark C:\temp', null, null, null,
          timestamptz '2026-09-10 16:00:00+00');
end $$;

-- ── 1. Who may read it ──────────────────────────────────────────────────────
do $$
declare v_who text; v_out text; v_state text;
begin
  foreach v_who in array array['owner', 'admin', 'manager', 'service', 'server'] loop
    v_out := pg_temp.audx_try(v_who, 'select (public.audit_log_page(p_text => ''audxmark'') ->> ''total'')');
    if v_out <> 'ok' || chr(9) || '6' then
      perform pg_temp.audx_fail(format('1: %s, who may, got %s', v_who, v_out));
    end if;
  end loop;
  -- The page's isManagerOrAbove leaves the Inventory Manager and Staff out;
  -- closed profiles, a login with no profile and an affiliate are not staff.
  foreach v_who in array array['invman', 'staff', 'inactive', 'pending', 'cancelled', 'nostaff', 'affiliate', 'anon'] loop
    v_out := pg_temp.audx_try(v_who, 'select public.audit_log_page(p_text => ''audxmark'')::text');
    v_state := split_part(v_out, chr(9), 1);
    if v_state <> '42501' then
      perform pg_temp.audx_fail(format('1: %s was answered with %s, not 42501', v_who, v_state));
    end if;
    if v_out ~ 'audxmark|AUDX' then
      perform pg_temp.audx_fail(format('1: %s got the log''s rows', v_who));
    end if;
  end loop;
  if position('perform public.require_active_staff(array[''owner'', ''admin'', ''manager'']);' in
              pg_get_functiondef('public.audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean)'::regprocedure))
     = 0 then
    perform pg_temp.audx_fail('1: audit_log_page does not start with the staff check');
  end if;
  -- Grants: signed-in logins and the service role; not anon; one function of the name.
  if has_function_privilege('anon', 'public.audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean)', 'execute')
     or not has_function_privilege('service_role', 'public.audit_log_page(date,date,text,text,uuid,text,integer,integer,timestamp with time zone,boolean)', 'execute') then
    perform pg_temp.audx_fail('1: the grants on audit_log_page are not signed-in logins and the service role only');
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'audit_log_page') <> 1 then
    perform pg_temp.audx_fail('1: audit_log_page has an overload');
  end if;
  if (select pg_get_indexdef(to_regclass('public.idx_audit_logs_created_at')))
     is distinct from 'CREATE INDEX idx_audit_logs_created_at ON public.audit_logs USING btree (created_at DESC, id DESC)' then
    perform pg_temp.audx_fail('1: the created_at index is missing or different');
  end if;
end $$;

-- ── 2. The rows: newest first, every field the page shows ───────────────────
do $$
declare j jsonb; r jsonb; v_before text; v_after text;
begin
  select md5(string_agg(to_jsonb(a)::text, '' order by a.id)) into v_before from public.audit_logs a;
  j := pg_temp.audx_page('p_text => ''audxmark''');
  if (j ->> 'total')::int <> 6 or jsonb_array_length(j -> 'rows') <> 6 then
    perform pg_temp.audx_fail('2: the search did not find the six entries: ' || coalesce(j ->> 'total', 'null'));
  end if;
  -- e3 and e4 share a time: the later id comes first, as the page pages.
  if pg_temp.audx_actions(j) not in ('audx_six,audxmark_five,audx_four,audx_three,audx_two,audx_one',
                                     'audx_six,audxmark_five,audx_three,audx_four,audx_two,audx_one') then
    perform pg_temp.audx_fail('2: not newest first: ' || pg_temp.audx_actions(j));
  end if;
  if (select string_agg(x ->> 'id', ',' order by o) from jsonb_array_elements(j -> 'rows') with ordinality t(x, o)
       where x ->> 'action' in ('audx_three', 'audx_four'))
     <> (select string_agg(a.id::text, ',' order by a.id desc) from public.audit_logs a where a.action in ('audx_three', 'audx_four')) then
    perform pg_temp.audx_fail('2: entries of one time are not ordered by id, newest first');
  end if;
  select x into r from jsonb_array_elements(j -> 'rows') x where x ->> 'action' = 'audx_three';
  if r ->> 'module' <> 'invoices' or (r ->> 'module_recorded')::boolean or r ->> 'actor_name' <> 'System'
     or r ->> 'record_label' <> 'AUDX-INV-1' or r ->> 'record_id' <> pg_temp.audx_id('inv')::text
     or r -> 'old_data' ->> 'note' <> 'audxmark in old' or r -> 'new_data' <> 'null'
     or r ->> 'table_name' <> 'invoices' or r ? 'store_id' then
    perform pg_temp.audx_fail('2: an invoice entry with no module and nobody is not as shown: ' || r::text);
  end if;
  select x into r from jsonb_array_elements(j -> 'rows') x where x ->> 'action' = 'audx_two';
  if r ->> 'module' <> 'transfers' or not (r ->> 'module_recorded')::boolean or r ->> 'actor_name' <> 'AUDX staff'
     or r ->> 'actor_role' <> 'staff' or r ->> 'changed_by' <> pg_temp.audx_id('staff')::text
     or r ->> 'record_label' is not null or r -> 'new_data' ->> 'note' <> 'audxmark in new' then
    perform pg_temp.audx_fail('2: a recorded module or its person is not as shown: ' || r::text);
  end if;
  select x into r from jsonb_array_elements(j -> 'rows') x where x ->> 'action' = 'audx_one';
  if r ->> 'module' <> 'users' or (r ->> 'module_recorded')::boolean or r ->> 'reason' <> 'audxmark checked 100%_done' then
    perform pg_temp.audx_fail('2: a profile entry''s module is not taken from its table: ' || r::text);
  end if;
  select x into r from jsonb_array_elements(j -> 'rows') x where x ->> 'action' = 'audxmark_five';
  if r ->> 'module' <> 'audx_side_table' or (r ->> 'module_recorded')::boolean then
    perform pg_temp.audx_fail('2: a table with no known module does not show its own name: ' || r::text);
  end if;
  select x into r from jsonb_array_elements(j -> 'rows') x where x ->> 'action' = 'audx_six';
  if r ->> 'module' <> 'settings' then
    perform pg_temp.audx_fail('2: app_settings is not shown as settings: ' || r::text);
  end if;
  if coalesce(j -> 'choices', 'null') <> 'null' then
    perform pg_temp.audx_fail('2: the choices were sent unasked');
  end if;
  -- Reading changed nothing: the entries are evidence.
  select md5(string_agg(to_jsonb(a)::text, '' order by a.id)) into v_after from public.audit_logs a;
  if v_after <> v_before then
    perform pg_temp.audx_fail('2: reading the log changed an entry');
  end if;
end $$;

-- ── 3. The filters ───────────────────────────────────────────────────────────
do $$
declare r record; j jsonb;
begin
  for r in select * from (values
    -- Singapore days: 23:59:59 on 8 Sep is the 8th, midnight is the 9th.
    ('one day',          'p_from => date ''2026-09-09'', p_to => date ''2026-09-09''', 'audx_four,audx_three,audx_two'),
    ('to only',          'p_to => date ''2026-09-08''',                               'audx_one'),
    ('from only',        'p_from => date ''2026-09-10''',                             'audx_six,audxmark_five'),
    ('last minute',      'p_from => date ''2026-09-10'', p_to => date ''2026-09-10''', 'audxmark_five'),
    -- The module shown, stored or taken from the table.
    ('taken module',     'p_module => ''users''',                                     'audx_one'),
    ('stored module',    'p_module => ''transfers''',                                 'audx_two'),
    ('taken invoices',   'p_module => ''invoices''',                                  'audx_three'),
    ('table',            'p_table => ''invoices''',                                   'audx_four,audx_three'),
    ('person',           'p_actor => ' || quote_literal(pg_temp.audx_id('manager')) || '::uuid', 'audx_four'),
    ('all together',     'p_from => date ''2026-09-09'', p_to => date ''2026-09-09'', p_table => ''invoices'', p_actor => '
                           || quote_literal(pg_temp.audx_id('manager')) || '::uuid', 'audx_four')
  ) x(label, args, want) loop
    j := pg_temp.audx_page(r.args || ', p_text => ''audxmark''');
    -- e3 and e4 share a time, so either may come first.
    if pg_temp.audx_actions(j) not in (r.want, coalesce(case r.want when 'audx_four,audx_three,audx_two' then 'audx_three,audx_four,audx_two'
                                                                     when 'audx_four,audx_three' then 'audx_three,audx_four' end, r.want))
       or (j ->> 'total')::int <> array_length(string_to_array(r.want, ','), 1) then
      perform pg_temp.audx_fail(format('3: %s gave %s (total %s), not %s', r.label, pg_temp.audx_actions(j), j ->> 'total', r.want));
    end if;
  end loop;

  -- Text: everything the page shows, and what was changed.
  for r in select * from (values
    ('the action, as shown',     'audx four',                  'audx_four'),
    ('the action, as stored',    'audx_four',                  'audx_four'),
    ('the reason',               'checked 100%_done',          'audx_one'),
    ('the table',                'audx_side_table',            'audxmark_five'),
    ('the person',               'AUDX manager',               'audx_four'),
    ('nobody',                   'system',                     null),
    ('the invoice number',       'audx-inv-1',                 'audx_three,audx_four'),
    ('new details',              'audxmark in new',            'audx_two'),
    ('old details',              'AUDXMARK IN OLD',            'audx_three'),
    ('a backslash',              'C:\temp',                    'audx_six'),
    -- % and _ are letters: "100_" and "%done" match nothing.
    ('a literal _',              'checked 100_',               ''),
    ('a literal %',              'audxmark%in',                ''),
    ('spaces around',            '   audx four   ',            'audx_four')
  ) x(label, txt, want) loop
    j := pg_temp.audx_page('p_text => ' || quote_literal(r.txt) || ', p_limit => 1000');
    if r.want is null then
      -- 'System' names every entry with nobody, so only that one of ours.
      if not exists (select 1 from jsonb_array_elements(j -> 'rows') x where x ->> 'action' = 'audx_three')
         or exists (select 1 from jsonb_array_elements(j -> 'rows') x where x ->> 'action' in ('audx_one', 'audx_two', 'audx_four')) then
        perform pg_temp.audx_fail('3: searching "system" did not find the entry made by nobody, alone');
      end if;
    elsif (select coalesce(string_agg(x ->> 'action', ',' order by x ->> 'action' desc), '')
             from jsonb_array_elements(j -> 'rows') x where x ->> 'action' like 'audx%') <> r.want then
      perform pg_temp.audx_fail(format('3: text "%s" (%s) gave %s, not %s', r.txt, r.label, pg_temp.audx_actions(j), r.want));
    end if;
  end loop;
  -- The record id itself.
  j := pg_temp.audx_page('p_text => ' || quote_literal(left(pg_temp.audx_id('inv')::text, 13)) || ', p_table => ''invoices''');
  if (j ->> 'total')::int <> 2 then
    perform pg_temp.audx_fail('3: the record id is not searched: ' || coalesce(j ->> 'total', 'null'));
  end if;
  -- Blank text is no filter.
  if (pg_temp.audx_page('p_text => ''   '', p_table => ''audx_side_table''') ->> 'total')::int <> 1 then
    perform pg_temp.audx_fail('3: blank text filtered something out');
  end if;
end $$;

-- ── 4. Pages, the as-of time, the limits ─────────────────────────────────────
do $$
declare j jsonb; v_as_of timestamptz; v_seen text[] := '{}'; v_page text[]; v_out text; i int;
begin
  -- 2,500 more entries: the export reads them 1,000 at a time.
  insert into public.audit_logs (table_name, action, reason, created_at)
  select 'audx_bulk', 'audx_bulk', 'audxbulk ' || g, timestamptz '2026-09-01 00:00:00+00' + g * interval '1 minute'
    from generate_series(1, 2500) g;
  j := pg_temp.audx_page('p_text => ''audxbulk'', p_limit => 1000, p_offset => 0');
  v_as_of := (j ->> 'as_of')::timestamptz;
  if v_as_of is null or v_as_of <> now() or (j ->> 'total')::int <> 2500 then
    perform pg_temp.audx_fail('4: the first export page has no as-of time or the wrong total');
  end if;
  for i in 0 .. 2 loop
    j := pg_temp.audx_page(format('p_text => ''audxbulk'', p_limit => 1000, p_offset => %s, p_as_of => %L', i * 1000, v_as_of));
    select array_agg(x ->> 'id') into v_page from jsonb_array_elements(j -> 'rows') x;
    if cardinality(v_page) <> (case when i < 2 then 1000 else 500 end) then
      perform pg_temp.audx_fail(format('4: export page %s held %s entries', i + 1, cardinality(v_page)));
    end if;
    v_seen := v_seen || v_page;
  end loop;
  if cardinality(v_seen) <> 2500 or (select count(distinct x) from unnest(v_seen) x) <> 2500 then
    perform pg_temp.audx_fail('4: three pages of 1000 did not hold every entry once');
  end if;
  -- Newest first across pages: the first entry is minute 2500, the last minute 1.
  if (select a.reason from public.audit_logs a where a.id = v_seen[1]::uuid) <> 'audxbulk 2500'
     or (select a.reason from public.audit_logs a where a.id = v_seen[2500]::uuid) <> 'audxbulk 1' then
    perform pg_temp.audx_fail('4: the pages are not newest first');
  end if;

  -- The as-of time leaves out what came after it; in the future it is now.
  j := pg_temp.audx_page('p_text => ''audxmark'', p_as_of => timestamptz ''2026-09-08 16:15:00+00''');
  if pg_temp.audx_actions(j) <> 'audx_two,audx_one' then
    perform pg_temp.audx_fail('4: the as-of time did not leave out later entries: ' || pg_temp.audx_actions(j));
  end if;
  j := pg_temp.audx_page('p_text => ''audxmark'', p_as_of => now() + interval ''1 year''');
  if (j ->> 'as_of')::timestamptz <> now() or (j ->> 'total')::int <> 6 then
    perform pg_temp.audx_fail('4: an as-of time in the future was not taken as now');
  end if;

  -- A page of the default size, and the edges of the limits.
  j := pg_temp.audx_page('p_text => ''audxbulk''');
  if jsonb_array_length(j -> 'rows') <> 50 then
    perform pg_temp.audx_fail('4: the default page is not 50 entries');
  end if;
  j := pg_temp.audx_page('p_text => ''audxbulk'', p_limit => null, p_offset => null');
  if jsonb_array_length(j -> 'rows') <> 50 then
    perform pg_temp.audx_fail('4: a page with no size given is not 50 entries');
  end if;
  j := pg_temp.audx_page('p_text => ''audxbulk'', p_offset => 2500');
  if jsonb_array_length(j -> 'rows') <> 0 or (j ->> 'total')::int <> 2500 then
    perform pg_temp.audx_fail('4: a page past the end is not empty with the total');
  end if;
  foreach v_out in array array['p_limit => 0', 'p_limit => 1001', 'p_offset => -1',
                               'p_from => date ''2026-09-09'', p_to => date ''2026-09-08'''] loop
    if split_part(pg_temp.audx_try('owner', 'select public.audit_log_page(' || v_out || ')::text'), chr(9), 1) <> '22023' then
      perform pg_temp.audx_fail('4: ' || v_out || ' was not refused');
    end if;
  end loop;
  if split_part(pg_temp.audx_try('owner', 'select public.audit_log_page(p_from => date ''2026-09-09'', p_to => date ''2026-09-08'')::text'), chr(9), 2)
     <> 'The end date cannot be before the start date.' then
    perform pg_temp.audx_fail('4: a reversed date range is not explained');
  end if;
end $$;

-- ── 5. The filters' choices ─────────────────────────────────────────────────
do $$
declare j jsonb; c jsonb;
begin
  j := pg_temp.audx_page('p_with_choices => true, p_limit => 1');
  c := j -> 'choices';
  if c is null or jsonb_typeof(c -> 'modules') <> 'array' or jsonb_typeof(c -> 'tables') <> 'array'
     or jsonb_typeof(c -> 'actors') <> 'array' then
    perform pg_temp.audx_fail('5: the choices are missing');
    return;
  end if;
  if not exists (select 1 from jsonb_array_elements(c -> 'modules') x where x ->> 'value' = 'users' and (x ->> 'count')::int >= 1)
     or not exists (select 1 from jsonb_array_elements(c -> 'modules') x where x ->> 'value' = 'invoice_edit')
     or not exists (select 1 from jsonb_array_elements(c -> 'tables') x where x ->> 'value' = 'audx_bulk' and (x ->> 'count')::int = 2500) then
    perform pg_temp.audx_fail('5: a module or table is missing from the choices, or miscounted');
  end if;
  if (select (x ->> 'count')::int from jsonb_array_elements(c -> 'actors') x where x ->> 'id' = pg_temp.audx_id('owner')::text) <> 3
     or (select x ->> 'name' from jsonb_array_elements(c -> 'actors') x where x ->> 'id' = pg_temp.audx_id('staff')::text) <> 'AUDX staff'
     or exists (select 1 from jsonb_array_elements(c -> 'actors') x where x ->> 'id' is null) then
    perform pg_temp.audx_fail('5: the people in the choices are not as tested');
  end if;
  -- Each list sorted, as the page shows it.
  if (select array_agg(x ->> 'value' order by o) from jsonb_array_elements(c -> 'tables') with ordinality t(x, o))
     <> (select array_agg(x ->> 'value' order by x ->> 'value') from jsonb_array_elements(c -> 'tables') x) then
    perform pg_temp.audx_fail('5: the tables are not sorted');
  end if;
end $$;

-- ── 6. Entries of one time across pages; the role and the module as text ────
do $$
declare j jsonb; v_as_of timestamptz; v_seen text[] := '{}'; v_page text[]; i int; v_invman text;
begin
  -- Five entries of one time, written in an order that is not their ids'
  -- order (5, 3, 1, 4, 2), so only the id tie-break pages them newest id first.
  insert into public.audit_logs (id, table_name, action, reason, created_at)
  select ('00000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid, 'audx_tie', 'audx_tie', 'audxtie ' || g,
         timestamptz '2026-08-01 00:00:00+00'
    from generate_series(1, 5) g order by (g * 2) % 5;
  -- Read with a sort, not the created_at index, which would hide a missing
  -- tie-break.
  perform set_config('enable_indexscan', 'off', true);
  perform set_config('enable_bitmapscan', 'off', true);
  j := pg_temp.audx_page('p_text => ''audxtie'', p_limit => 2');
  v_as_of := (j ->> 'as_of')::timestamptz;
  for i in 0 .. 2 loop
    j := pg_temp.audx_page(format('p_text => ''audxtie'', p_limit => 2, p_offset => %s, p_as_of => %L', i * 2, v_as_of));
    select array_agg(x ->> 'id' order by o) into v_page from jsonb_array_elements(j -> 'rows') with ordinality t(x, o);
    v_seen := v_seen || coalesce(v_page, '{}');
  end loop;
  if v_seen is distinct from (select array_agg(a.id::text order by a.id desc) from public.audit_logs a where a.action = 'audx_tie') then
    perform pg_temp.audx_fail('6: entries of one time are not paged by id, newest first: ' || coalesce(array_to_string(v_seen, ','), 'none'));
  end if;
  perform set_config('enable_indexscan', 'on', true);
  perform set_config('enable_bitmapscan', 'on', true);

  -- The role, as stored and as the page shows it. Nothing else in this entry
  -- holds it: not the table, the action, the name ("AUDX invman") or details.
  insert into public.audit_logs (table_name, action, changed_by, actor_role, created_at)
  values ('audx_role_table', 'audx_seven', pg_temp.audx_id('invman'), 'inventory_manager', timestamptz '2026-08-02 00:00:00+00');
  v_invman := quote_literal(pg_temp.audx_id('invman')) || '::uuid';
  if (pg_temp.audx_page('p_text => ''inventory_manager'', p_actor => ' || v_invman) ->> 'total')::int <> 1 then
    perform pg_temp.audx_fail('6: the role, as stored, is not searched');
  end if;
  if (pg_temp.audx_page('p_text => ''Inventory Manager'', p_actor => ' || v_invman) ->> 'total')::int <> 1 then
    perform pg_temp.audx_fail('6: the role, as the page shows it, is not searched');
  end if;
  if (pg_temp.audx_page('p_text => ''store keeper'', p_actor => ' || v_invman) ->> 'total')::int <> 0 then
    perform pg_temp.audx_fail('6: a role search found an entry with another role');
  end if;

  -- The module, as text: e1's "users" is only in the module taken from its
  -- table; e4's "invoice_edit" is only in its stored module.
  if (pg_temp.audx_page('p_text => ''users'', p_table => ''profiles'', p_from => date ''2026-09-08'', p_to => date ''2026-09-08''')
        ->> 'total')::int <> 1 then
    perform pg_temp.audx_fail('6: a module taken from the table is not searched');
  end if;
  if (pg_temp.audx_page('p_text => ''invoice_edit'', p_table => ''invoices'', p_from => date ''2026-09-09'', p_to => date ''2026-09-09''')
        ->> 'total')::int <> 1 then
    perform pg_temp.audx_fail('6: a stored module is not searched');
  end if;
end $$;

-- ── Result ──────────────────────────────────────────────────────────────────
do $$
declare v_fail text;
begin
  select string_agg(msg, E'\n  ' order by n) into v_fail from audx_fail;
  if v_fail is not null then
    raise exception E'FAIL (%):\n  %', (select count(*) from audx_fail), v_fail;
  end if;
  raise notice 'PASS: audit_log_page answers active Owners, Admins and Managers and refuses everyone else; it reaches every entry newest first, a page at a time, entries of one time by id, and steady under its as-of time; filters by Singapore day, module (stored or taken from the table), table, person and literal text over the action, role, module, reason, person, record, invoice number and details; reads without changing an entry; and offers the choices only when asked.';
end $$;
rollback;
