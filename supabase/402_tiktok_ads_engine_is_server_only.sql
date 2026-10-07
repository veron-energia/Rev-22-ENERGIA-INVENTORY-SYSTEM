-- 402_tiktok_ads_engine_is_server_only.sql
--
-- WHAT WAS WRONG (found 6–7 Oct 2026)
--
--   The TikTok ads engine (the ads_* tables, views and functions that own
--   the TikTok leads Google Sheet) is not in this repository. Its own
--   migrations, applied to production from 19 Sep 2026 on, never said who may
--   use what they created, so everything kept the defaults: PostgreSQL's
--   EXECUTE for PUBLIC on a function, and Supabase's grants to anon and
--   authenticated on every table and view.
--
--   1. Eighteen functions are callable with the anon key, outside the five
--      signed-out endpoints of 339; check 1 of
--      scripts/permissions/tests/function-grants.sql fails on production.
--      They were created after 339 (20 Sep), so 339 never revoked them.
--      They are SECURITY INVOKER and every ads_* table has row-level
--      security with no policy, so for anon they reach nothing: tried as
--      anon on production (read-only), each one either fails on a helper
--      anon cannot call (ads_row_state, ads_sheet_deltas,
--      ads_normalize_phone, ads_ingest_calendar_event) or finds no rows.
--      The three pure formatters (ads_cell_literal, ads_items_key,
--      ads_money_text) touch no data. So these are endpoints nobody should
--      have, not a leak.
--
--   2. The leak is the four views. A view reads its tables with its owner's
--      rights unless it is marked security_invoker, and these are not, so
--      they read past row-level security. anon and authenticated hold every
--      privilege on all four:
--        * ads_lead_purchase_totals: a signed-out visitor reads every lead's
--          id, purchase total and invoice count (335 rows on 7 Oct, 15 with
--          an amount).
--        * ads_desired_sheet: any signed-in session reads every lead's
--          WhatsApp number (334 of 335), booking date and time, status,
--          purchases and row colour. An affiliate login is a signed-in
--          session, and anyone can create one from the public sign-up
--          (auth-signup-request). anon is stopped here only because the view
--          calls helpers anon cannot execute.
--        * ads_colour_diff: lead names and appointment history, to any
--          signed-in session (86 rows on 7 Oct).
--        * ads_sheet_write_queue: ads_desired_sheet's rows with changes
--          pending, to any signed-in session.
--      The ads_* functions staff can call (ads_sheet_deltas among them) read
--      these views too, so the same data reaches a signed-in session through
--      them. Supabase's security advisor reports all four views as
--      "Security Definer View" (ERROR).
--
--   3. The sixteen ads_* tables grant anon and authenticated every privilege.
--      Row-level security with no policy is what keeps their rows out today;
--      TRUNCATE, REFERENCES and TRIGGER are not governed by it.
--
-- WHO USES THE ENGINE
--
--   Pabbly Connect only, with the project's secret key, which PostgREST runs
--   as service_role. Every request to an ads_* path in the API logs from
--   28 Sep to 7 Oct 2026 was Pabbly's, with that key:
--     09:00 reconcile    ads_rpc_sheet_sync, ads_rpc_calendar_bulk (one per
--                        calendar), ads_rpc_reconcile, ads_rpc_sheet_write,
--                        ads_rpc_sheet_written, ads_rpc_alert_email,
--                        ads_rpc_alert_sent
--     10:30              ads_rpc_after_visit_run
--     11:00              ads_rpc_followup_run
--     20:45              ads_rpc_sheet_sync, ads_rpc_no_show_run
--   ads_rpc_no_show_run, ads_rpc_after_visit_run and ads_rpc_followup_run are
--   already granted to service_role alone and answer Pabbly every day, which
--   shows its key acts as service_role.
--   No pg_cron job, edge function or page of the application uses the
--   engine. Of the application's own functions only affiliate_whatsapp_enqueue
--   (394) calls into it (ads_wa_country_code), and it is SECURITY DEFINER, so
--   it runs as the owner. The daily checks made through the database
--   connection run as postgres. Neither needs a client role's grant.
--
--   Of the eighteen, Pabbly calls four (ads_rpc_calendar_bulk,
--   ads_rpc_sheet_write, ads_rpc_sheet_written, ads_rpc_alert_email). Nine are
--   reached from inside other engine functions or ads_desired_sheet, which
--   run as service_role when Pabbly calls them. Four (ads_rpc_mark_all_written,
--   ads_rpc_sheet_blocks, ads_rpc_sheet_columns, ads_rpc_row_state_column) are
--   earlier versions of the sheet write that nothing calls any more.
--   ads_flag_wa_phone_conflicts has no caller either.
--
-- WHAT THIS DOES
--
--   1. The eighteen functions are revoked from public, anon and authenticated
--      and granted to service_role.
--   2. The four views are revoked from public, anon and authenticated.
--   3. The sixteen tables are revoked from public, anon and authenticated.
--   service_role keeps everything it has, and postgres owns it all. Nothing
--   is created, replaced or dropped: no function or view text changes, and
--   no row.
--
-- NOT CHANGED
--
--   * The engine's other 46 functions. 13 are already service_role only. 33
--     are callable by staff, because 339 left every SECURITY INVOKER function
--     callable by staff. With the views and tables closed they reach no row
--     for a client role. One of them must stay that way:
--     ads_normalize_phone is in indexes on customers and health_surveys,
--     which are evaluated as whoever writes those tables.
--   * Making the views security_invoker. No client role can read them once
--     their grants are gone, and the engine reads them as service_role,
--     which bypasses row-level security anyway.
--   * The engine's mutable search_path (advisor WARN on all 64 functions).
--     They are SECURITY INVOKER, so it raises nobody's rights.
--
-- SAFETY
--
--   Apart from the lock timeout, this is one DO block, so it is atomic. It
--   refuses unless:
--     * each of the eighteen functions and four views is the version read
--       from production on 7 Oct 2026 (md5 below);
--     * the ads_* tables are exactly the sixteen named in c_tables, each with
--       row-level security on and no policy. A policy would mean some client
--       role is meant to read it.
--   Revoking twice changes nothing, so a re-run is a no-op.
--   Afterwards it checks:
--     * no client role holds any privilege on any of the thirty-eight;
--     * service_role can still execute every ads_* function and use the
--       views and tables;
--     * switching role, anon is refused ads_lead_purchase_totals and a
--       signed-in session is refused ads_desired_sheet and ads_sheet_deltas;
--     * service_role still reads ads_desired_sheet and builds what the 9am
--       run writes to the sheet (ads_rpc_sheet_write) and emails
--       (ads_rpc_alert_email). Both are read-only.
--
-- md5 of pg_get_functiondef, unchanged by this migration:
--   ads_cell_literal(text,text)             8105afad87982c418e673629e8474228
--   ads_flag_wa_phone_conflicts()           82857c50decce18587345b5e762518be
--   ads_items_key(text)                     1a45b48e894667bb47d5b9366ca37df1
--   ads_link_all_lead_customers()           1c6f02e350d4b6d282ddf38dbf525f4a
--   ads_may_contact(text,text)              e4f33b483583a0a338eaabe22e3eb348
--   ads_money_text(numeric)                 7d5c2e425b86513ff0819fa19659d50b
--   ads_resolve_all_attendance()            d4e46a0b2661b07b71c71d2b1cc034ef
--   ads_row_j_value(integer)                04b6537ea6bd5ae511bfa7bd1b307cc3
--   ads_row_p_value(integer)                a9674f1e9436c04b238b02ca8c26949c
--   ads_row_r_value(integer)                66eae1a944faaaf7c0084e8e3d4a20c8
--   ads_rpc_alert_email()                   8bf9eba2fd2b0c615a6d57394e0ed23c
--   ads_rpc_calendar_bulk(text,text)        fdf9c31c46ff0860ea9e96203ce9409d
--   ads_rpc_mark_all_written()              a4d787d049f22d41194529acbecce0e1
--   ads_rpc_row_state_column()              ee4270c3422cfb09788fc31dbd2188a7
--   ads_rpc_sheet_blocks()                  5c19bddbd6f92ae1471c9c7e770c175a
--   ads_rpc_sheet_columns()                 7235af95999420817b4e0c51484eead9
--   ads_rpc_sheet_write()                   55470c2e36868795128bff597721a13a
--   ads_rpc_sheet_written()                 6fa9edf4b9dff08f2b05a010e7e7f612
-- md5 of pg_get_viewdef with search_path = public, unchanged:
--   ads_colour_diff                         0681f35956dc93016a8235d98a353991
--   ads_desired_sheet                       d7d2c1b9131748efdf1046a143af153a
--   ads_lead_purchase_totals                f6e1a5cc0684bacb438f6190e05f4054
--   ads_sheet_write_queue                   06123b5ab6d14f458eea6cf2c29e5d68
--
-- Test: scripts/permissions/tests/function-grants.sql (checks 1, 3, 10 and
-- 11). It is read-only and can run on production.

set lock_timeout = '5s';

do $mig$
declare
  c_fns constant text[][] := array[
    ['public.ads_cell_literal(text,text)',          '8105afad87982c418e673629e8474228'],
    ['public.ads_flag_wa_phone_conflicts()',        '82857c50decce18587345b5e762518be'],
    ['public.ads_items_key(text)',                  '1a45b48e894667bb47d5b9366ca37df1'],
    ['public.ads_link_all_lead_customers()',        '1c6f02e350d4b6d282ddf38dbf525f4a'],
    ['public.ads_may_contact(text,text)',           'e4f33b483583a0a338eaabe22e3eb348'],
    ['public.ads_money_text(numeric)',              '7d5c2e425b86513ff0819fa19659d50b'],
    ['public.ads_resolve_all_attendance()',         'd4e46a0b2661b07b71c71d2b1cc034ef'],
    ['public.ads_row_j_value(integer)',             '04b6537ea6bd5ae511bfa7bd1b307cc3'],
    ['public.ads_row_p_value(integer)',             'a9674f1e9436c04b238b02ca8c26949c'],
    ['public.ads_row_r_value(integer)',             '66eae1a944faaaf7c0084e8e3d4a20c8'],
    ['public.ads_rpc_alert_email()',                '8bf9eba2fd2b0c615a6d57394e0ed23c'],
    ['public.ads_rpc_calendar_bulk(text,text)',     'fdf9c31c46ff0860ea9e96203ce9409d'],
    ['public.ads_rpc_mark_all_written()',           'a4d787d049f22d41194529acbecce0e1'],
    ['public.ads_rpc_row_state_column()',           'ee4270c3422cfb09788fc31dbd2188a7'],
    ['public.ads_rpc_sheet_blocks()',               '5c19bddbd6f92ae1471c9c7e770c175a'],
    ['public.ads_rpc_sheet_columns()',              '7235af95999420817b4e0c51484eead9'],
    ['public.ads_rpc_sheet_write()',                '55470c2e36868795128bff597721a13a'],
    ['public.ads_rpc_sheet_written()',              '6fa9edf4b9dff08f2b05a010e7e7f612']];
  c_views constant text[][] := array[
    ['ads_colour_diff',          '0681f35956dc93016a8235d98a353991'],
    ['ads_desired_sheet',        'd7d2c1b9131748efdf1046a143af153a'],
    ['ads_lead_purchase_totals', 'f6e1a5cc0684bacb438f6190e05f4054'],
    ['ads_sheet_write_queue',    '06123b5ab6d14f458eea6cf2c29e5d68']];
  c_tables constant text[] := array[
    'ads_appointments', 'ads_attendance_matches', 'ads_automation_exceptions', 'ads_automation_runs',
    'ads_excluded_phones', 'ads_lead_customers', 'ads_lead_submissions', 'ads_leads', 'ads_messages',
    'ads_optout_phones', 'ads_purchase_attributions', 'ads_sheet_colour_observed', 'ads_sheet_j',
    'ads_sheet_manual_colour', 'ads_sheet_state', 'ads_sync_inbox'];
  c_all_privs constant text := 'select,insert,update,delete,truncate,references,trigger';
  v_path text := current_setting('search_path');
  v_rels text[] := c_tables;
  v text; i int; n int; r jsonb; rel regclass; t text;
begin
  -- ── Guards: nothing is revoked unless all pass ─────────────────────────────
  for i in 1 .. array_length(c_fns, 1) loop
    if to_regprocedure(c_fns[i][1]) is null then
      raise exception '402: % is missing', c_fns[i][1]; end if;
    v := md5(pg_get_functiondef(to_regprocedure(c_fns[i][1])));
    if v <> c_fns[i][2] then
      raise exception '402: % is not the version read from production on 7 Oct 2026 (md5 %). Re-read it and re-test before applying.', c_fns[i][1], v; end if;
  end loop;

  -- pg_get_viewdef qualifies any name the search_path does not show, so the
  -- views are read with public alone, as they were on 7 Oct.
  perform set_config('search_path', 'public', true);
  for i in 1 .. array_length(c_views, 1) loop
    rel := to_regclass('public.' || c_views[i][1]);
    if rel is null or (select relkind from pg_class where oid = rel) <> 'v' then
      raise exception '402: the view public.% is missing', c_views[i][1]; end if;
    v := md5(pg_get_viewdef(rel));
    if v <> c_views[i][2] then
      raise exception '402: the view public.% is not the version read from production on 7 Oct 2026 (md5 %). Re-read it and re-test before applying.', c_views[i][1], v; end if;
  end loop;
  perform set_config('search_path', v_path, true);

  foreach t in array c_tables loop
    rel := to_regclass('public.' || t);
    if rel is null or (select relkind from pg_class where oid = rel) <> 'r' then
      raise exception '402: the table public.% is missing', t; end if;
    if not (select relrowsecurity from pg_class where oid = rel) then
      raise exception '402: public.% does not have row-level security on', t; end if;
    if exists (select 1 from pg_policy where polrelid = rel) then
      raise exception '402: public.% has a policy, so some client role is meant to read it; this migration assumed none', t; end if;
  end loop;
  select count(*) into n from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public' and c.relname like 'ads\_%' and c.relkind in ('r', 'p');
  if n <> array_length(c_tables, 1) then
    raise exception '402: there are % ads_* tables, not the 16 read on 7 Oct 2026; re-read them before applying', n; end if;

  -- ── Revoke ─────────────────────────────────────────────────────────────────
  for i in 1 .. array_length(c_fns, 1) loop
    execute format('revoke all on function %s from public, anon, authenticated', c_fns[i][1]);
    execute format('grant execute on function %s to service_role', c_fns[i][1]);
  end loop;
  for i in 1 .. array_length(c_views, 1) loop
    execute format('revoke all on table public.%I from public, anon, authenticated', c_views[i][1]);
  end loop;
  foreach t in array c_tables loop
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
  end loop;

  -- ── Verify: by the catalogue ───────────────────────────────────────────────
  for i in 1 .. array_length(c_fns, 1) loop
    if has_function_privilege('anon', c_fns[i][1], 'execute')
       or has_function_privilege('authenticated', c_fns[i][1], 'execute') then
      raise exception '402: % is still callable by a client role', c_fns[i][1]; end if;
  end loop;
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname like 'ads\_%'
     and not has_function_privilege('service_role', p.oid, 'execute');
  if v is not null then
    raise exception '402: service_role cannot execute %, which the engine needs', v; end if;
  for i in 1 .. array_length(c_views, 1) loop
    v_rels := v_rels || c_views[i][1];
  end loop;
  foreach t in array v_rels loop
    rel := to_regclass('public.' || t);
    if has_table_privilege('anon', rel, c_all_privs) or has_table_privilege('authenticated', rel, c_all_privs) then
      raise exception '402: public.% is still open to a client role', t; end if;
    if not has_table_privilege('service_role', rel, 'select') then
      raise exception '402: service_role cannot read public.%', t; end if;
  end loop;
  foreach t in array c_tables loop
    if not (has_table_privilege('service_role', 'public.' || t, 'insert')
            and has_table_privilege('service_role', 'public.' || t, 'update')
            and has_table_privilege('service_role', 'public.' || t, 'delete')) then
      raise exception '402: service_role cannot write public.%', t; end if;
  end loop;

  -- ── Verify: as each role ───────────────────────────────────────────────────
  execute 'set local role anon';
  begin
    perform 1 from public.ads_lead_purchase_totals limit 1;
    raise exception '402: anon still reads ads_lead_purchase_totals';
  exception when insufficient_privilege then null;
  end;
  execute 'set local role authenticated';
  begin
    perform 1 from public.ads_desired_sheet limit 1;
    raise exception '402: a signed-in session still reads ads_desired_sheet';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.ads_sheet_deltas() limit 1;
    raise exception '402: a signed-in session still reads the sheet through ads_sheet_deltas';
  exception when insufficient_privilege then null;
  end;
  execute 'set local role service_role';
  perform count(*) from public.ads_desired_sheet;
  r := public.ads_rpc_sheet_write();
  if (r ->> 'ok') is distinct from 'true' then
    raise exception '402: ads_rpc_sheet_write as service_role answered %', left(r::text, 200); end if;
  r := public.ads_rpc_alert_email();
  if (r ->> 'ok') is distinct from 'true' then
    raise exception '402: ads_rpc_alert_email as service_role answered %', left(r::text, 200); end if;
  execute 'reset role';

  perform pg_notify('pgrst', 'reload schema');
end $mig$;
