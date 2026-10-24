-- 467 repair: put right the TikTok order times stored day/month-swapped.
--
-- Before 467, tiktok_parse_time read TikTok's 'DD/MM/YYYY HH24:MI:SS' month
-- first whenever the day was 12 or less (467's header says why). The six
-- times on each tiktok_order_rows row (rts_time, created_time, paid_time,
-- shipped_time, delivered_time, cancelled_time) were stored that way. Read
-- only on production, 24 Oct 2026: 421 of 809 stored times on 111 of 181
-- rows (73 of them confirmed; 136 of the times on rows of deleted files).
-- Every one is exactly what the old function gives for the row's raw text,
-- and nothing in the app reads the six columns, so no figure moves. The
-- settlement rows and the withdrawal records were right and are not touched.
--
-- What it does: every row of tiktok_order_rows whose six times are not what
-- 467's tiktok_parse_time reads from its raw text gets the six set to that
-- reading, and nothing else of the row changes. It refuses (and changes
-- nothing) if a stored time is neither 467's reading nor the old one: that
-- time was not stored by the import as it was, and needs a look first.
-- One audit row per row put right ('tiktok_order_times_restored', the times
-- as they were and as they are now), under the Owner given, so it can be
-- read back and undone.
--
-- Confirmed rows: trg_tiktok_row_immutable (64) refuses any update of a
-- confirmed row ("Confirmed import rows are immutable"). That stays the rule
-- for everything else. Here, inside this one statement and nowhere else, the
-- trigger is switched off (alter table ... disable trigger), the six times
-- are written, and it is switched on again before the statement ends; the
-- statement then checks it is on, as it was, and fails (undoing all of it,
-- the switch-off included: it is one transaction) if it is not. The
-- switch-off takes a lock on the table (share row exclusive) that every
-- other writer waits for until the statement ends, so no other change to the
-- table can happen while the trigger is off. The lock timeout gives up after
-- 5 s (an import being confirmed at that moment) and changes nothing.
--
-- Before running, in the same session:
--   0. 467 must be in (it checks).
--   1. Preview: scripts/tiktok/repair/467-restore-tiktok-order-times-preview.sql
--      (a plain select, read only: what would change, counts only), or run
--      this file without repair467.go: it checks everything and prints the
--      same counts as notices, then changes nothing.
--   2. With the Owner's go-ahead:
--        select set_config('repair467.actor', '<an active Owner''s profile id>', false),
--               set_config('repair467.expect', '<the times the preview counted, e.g. 421>', false),
--               set_config('repair467.go', 'yes', false);
--      and run this again, as the database owner (the MCP execute_sql tool,
--      the SQL editor, or psql as postgres). It acts only if the count is
--      still what was approved.
--   The settings last for the session only: where each run is a session of
--   its own (the MCP execute_sql tool, the SQL editor), send the set_config
--   lines and this file's text together, in one run.
-- A second run, once done, finds nothing to put right and changes nothing.
-- It prints counts and row ids only, never an order's contents.
--
-- To check afterwards (counts only; 0 expected):
--   select count(*) from public.tiktok_order_rows r
--    where r.rts_time is distinct from public.tiktok_parse_time(r.raw->>'rts_time')
--       or r.created_time is distinct from public.tiktok_parse_time(r.raw->>'created_time')
--       or r.paid_time is distinct from public.tiktok_parse_time(r.raw->>'paid_time')
--       or r.shipped_time is distinct from public.tiktok_parse_time(r.raw->>'shipped_time')
--       or r.delivered_time is distinct from public.tiktok_parse_time(r.raw->>'delivered_time')
--       or r.cancelled_time is distinct from public.tiktok_parse_time(r.raw->>'cancelled_time');
--   select tgenabled from pg_trigger where tgname = 'tiktok_row_immutable';   -- O
-- To undo (only if the Owner asks): each audit row 'tiktok_order_times_restored'
-- holds the six times as they were (old_data), by row id (record_id).
--
-- Test: scripts/tiktok/tests/times-day-first-467.sql (begin ... rollback).

set lock_timeout = '5s';

do $repair$
declare
  c_cols constant text[] := array['rts_time', 'created_time', 'paid_time', 'shipped_time', 'delivered_time', 'cancelled_time'];
  -- 467's tiktok_parse_time, and the trigger as read on production (24 Oct 2026)
  c_parse constant text := 'tiktok_parse_time(text)';
  c_parse_md5 constant text := '9ab3b68b4fc30013d6bc75294d68bc66';
  c_trg_fn_md5 constant text := 'e4b60289ccbea8febc55bc09021dff29';
  c_trg_def constant text := 'CREATE TRIGGER tiktok_row_immutable BEFORE DELETE OR UPDATE ON public.tiktok_order_rows FOR EACH ROW EXECUTE FUNCTION trg_tiktok_row_immutable()';
  c_audit constant text := 'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)';
  c_audit_md5 constant text := 'c705c733e213a27f0dc32d54322cc855';
  v_path text := current_setting('search_path');
  v_style text := current_setting('DateStyle');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v_go boolean := coalesce(current_setting('repair467.go', true), '') = 'yes';
  v_expect text := nullif(btrim(coalesce(current_setting('repair467.expect', true), '')), '');
  v_actor uuid;
  r record; k text; v text; v_raw text; v_stored timestamptz; v_old timestamptz; v_new timestamptz;
  v_was jsonb; v_now jsonb;
  v_fix uuid[] := '{}'; v_odd text; n_values int := 0; n_rows int := 0; n_confirmed int := 0; n_deleted int := 0; n_future int := 0;
  v_per_col jsonb := '{}'::jsonb; v_others_before text; v_others_after text;
  v_trg_oid oid;
begin
  perform set_config('search_path', 'public', true);
  -- The old reading is reproduced under production's DateStyle (the one the
  -- imports ran under), whatever this session's is.
  perform set_config('DateStyle', 'ISO, MDY', true);

  -- ── Checks: nothing is changed before all of them pass ────────────────
  if to_regprocedure('public.' || c_parse) is null
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_parse))) <> c_parse_md5 then
    raise exception '467 repair: public.% is not 467''s (md5 %): apply 467 first; nothing was changed',
      c_parse, md5(pg_get_functiondef(to_regprocedure('public.' || c_parse))); end if;
  if md5(pg_get_functiondef('public.trg_tiktok_row_immutable()'::regprocedure)) <> c_trg_fn_md5
     or to_regprocedure('public.' || c_audit) is null
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_audit))) <> c_audit_md5 then
    raise exception '467 repair: trg_tiktok_row_immutable or write_audit_ex is not the version read on 24 Oct 2026; nothing was changed. Re-read it first.'; end if;
  -- The table's one trigger of its own is the immutability one, switched on.
  select t.oid into v_trg_oid from pg_trigger t
   where t.tgrelid = 'public.tiktok_order_rows'::regclass and not t.tgisinternal and t.tgname = 'tiktok_row_immutable'
     and t.tgenabled = 'O' and pg_get_triggerdef(t.oid) = c_trg_def;
  if v_trg_oid is null
     or (select count(*) from pg_trigger t where t.tgrelid = 'public.tiktok_order_rows'::regclass and not t.tgisinternal) <> 1 then
    raise exception '467 repair: tiktok_order_rows'' triggers are not as read on 24 Oct 2026 (tiktok_row_immutable alone, on); nothing was changed'; end if;
  -- The columns, with these types.
  select string_agg(x, ', ') into v from unnest(c_cols || array['raw']) x
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = 'public.tiktok_order_rows'::regclass and a.attname = x and not a.attisdropped
                        and format_type(a.atttypid, a.atttypmod) = case when x = 'raw' then 'jsonb' else 'timestamp with time zone' end);
  if v is not null then raise exception '467 repair: these columns of tiktok_order_rows are missing or not of the type read: %; nothing was changed', v; end if;
  if v_go then
    begin
      v_actor := nullif(btrim(coalesce(current_setting('repair467.actor', true), '')), '')::uuid;
    exception when others then
      raise exception '467 repair: repair467.actor must be a profile id; nothing was changed'; end;
    if v_actor is null or not exists (select 1 from public.profiles p where p.id = v_actor and p.role = 'owner' and p.is_active
                                         and p.deleted_at is null and coalesce(p.invitation_status, 'accepted') = 'accepted') then
      raise exception '467 repair: repair467.actor is not an active Owner; nothing was changed'; end if;
    if v_expect is null or v_expect !~ '^[0-9]+$' then
      raise exception '467 repair: give repair467.expect, the number of times the preview counted; nothing was changed'; end if;
    -- Nothing else writes the table from here to the end (the trigger's
    -- switch-off below takes the same lock).
    lock table public.tiktok_order_rows in share row exclusive mode;
  end if;

  -- ── What it would change: each row's six times, read again from raw ───
  for r in select o.id, o.confirmed, b.deleted_at is not null as deleted_file, o.raw, to_jsonb(o) as j
             from public.tiktok_order_rows o join public.tiktok_import_batches b on b.id = o.batch_id
            order by o.id loop
    v_was := '{}'::jsonb; v_now := '{}'::jsonb;
    foreach k in array c_cols loop
      v_raw := r.raw->>k;
      v_stored := (r.j->>k)::timestamptz;
      v_new := public.tiktok_parse_time(v_raw);
      continue when v_stored is not distinct from v_new;
      -- The old reading (64's body, word for word).
      v_old := null;
      v := nullif(trim(coalesce(v_raw, '')), '');
      if v is not null then
        begin v_old := (replace(v, '/', '-')::timestamp) at time zone 'Asia/Singapore';
        exception when others then
          begin v_old := (to_timestamp(v, 'DD/MM/YYYY HH24:MI:SS')::timestamp) at time zone 'Asia/Singapore';
          exception when others then
            begin v_old := (to_timestamp(v, 'DD/MM/YYYY HH24:MI')::timestamp) at time zone 'Asia/Singapore';
            exception when others then v_old := null; end;
          end;
        end;
      end if;
      if v_stored is distinct from v_old then
        v_odd := concat_ws(', ', v_odd, r.id || ' ' || k);
        continue;
      end if;
      v_was := v_was || jsonb_build_object(k, v_stored);
      v_now := v_now || jsonb_build_object(k, v_new);
      v_per_col := v_per_col || jsonb_build_object(k, coalesce((v_per_col->>k)::int, 0) + 1);
      n_values := n_values + 1;
      if v_stored > now() then n_future := n_future + 1; end if;
    end loop;
    if v_was <> '{}'::jsonb then
      v_fix := v_fix || r.id;
      n_rows := n_rows + 1;
      if r.confirmed then n_confirmed := n_confirmed + 1; end if;
      if r.deleted_file then n_deleted := n_deleted + 1; end if;
    end if;
  end loop;
  if v_odd is not null then
    raise exception '467 repair: these stored times are neither 467''s reading of the row''s raw text nor the old one, so the import did not store them as it was: %. Nothing was changed; look at them first.', v_odd; end if;

  raise notice '467 repair: % time(s) to put right on % row(s) (% confirmed, % of deleted files); % of them are in the future now; by column: %',
    n_values, n_rows, n_confirmed, n_deleted, n_future, v_per_col;
  if n_values = 0 then
    raise notice '467 repair: nothing to put right (already done, or nothing was swapped); nothing changed';
    perform set_config('DateStyle', v_style, true);
    perform set_config('search_path', v_path, true);
    return;
  end if;
  if not v_go then
    raise notice '467 repair: checked; nothing changed. With the Owner''s go-ahead: select set_config(''repair467.actor'', ''<an active Owner''''s profile id>'', false), set_config(''repair467.expect'', ''%'', false), set_config(''repair467.go'', ''yes'', false); and run this again', n_values;
    perform set_config('DateStyle', v_style, true);
    perform set_config('search_path', v_path, true);
    return;
  end if;
  if v_expect::int <> n_values then
    raise exception '467 repair: % time(s) to put right now, not the % approved (repair467.expect); nothing was changed. Preview again.', n_values, v_expect; end if;

  -- ── The repair ─────────────────────────────────────────────────────────
  -- Everything of every row but the six times, to compare after.
  select md5(string_agg((to_jsonb(o) - c_cols)::text, '|' order by o.id)) into v_others_before from public.tiktok_order_rows o;

  -- The audit rows first (the times as they were), as the Owner given.
  perform set_config('request.jwt.claims', json_build_object('sub', v_actor, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  for r in select o.id, o.store_id, to_jsonb(o) as j, o.raw from public.tiktok_order_rows o where o.id = any (v_fix) order by o.id loop
    v_was := '{}'::jsonb; v_now := '{}'::jsonb;
    foreach k in array c_cols loop
      v_new := public.tiktok_parse_time(r.raw->>k);
      continue when (r.j->>k)::timestamptz is not distinct from v_new;
      v_was := v_was || jsonb_build_object(k, r.j->k);
      v_now := v_now || jsonb_build_object(k, v_new);
    end loop;
    perform public.write_audit_ex('tiktok_order_rows', r.id, 'tiktok_order_times_restored', v_was, v_now, 'tiktok_import',
      'TikTok times read day first (467): a day of 12 or less had been stored as the month', r.store_id);
  end loop;

  -- The six times, with the immutability trigger off for this statement
  -- alone (see the header).
  execute 'alter table public.tiktok_order_rows disable trigger tiktok_row_immutable';
  update public.tiktok_order_rows o
     set rts_time       = public.tiktok_parse_time(o.raw->>'rts_time'),
         created_time   = public.tiktok_parse_time(o.raw->>'created_time'),
         paid_time      = public.tiktok_parse_time(o.raw->>'paid_time'),
         shipped_time   = public.tiktok_parse_time(o.raw->>'shipped_time'),
         delivered_time = public.tiktok_parse_time(o.raw->>'delivered_time'),
         cancelled_time = public.tiktok_parse_time(o.raw->>'cancelled_time')
   where o.id = any (v_fix);
  execute 'alter table public.tiktok_order_rows enable trigger tiktok_row_immutable';

  -- ── Checks after: or all of it is undone ──────────────────────────────
  if not exists (select 1 from pg_trigger t where t.oid = v_trg_oid and t.tgenabled = 'O' and pg_get_triggerdef(t.oid) = c_trg_def) then
    raise exception '467 repair: the immutability trigger is not on again as it was; nothing was changed'; end if;
  if exists (select 1 from public.tiktok_order_rows o
              where o.rts_time is distinct from public.tiktok_parse_time(o.raw->>'rts_time')
                 or o.created_time is distinct from public.tiktok_parse_time(o.raw->>'created_time')
                 or o.paid_time is distinct from public.tiktok_parse_time(o.raw->>'paid_time')
                 or o.shipped_time is distinct from public.tiktok_parse_time(o.raw->>'shipped_time')
                 or o.delivered_time is distinct from public.tiktok_parse_time(o.raw->>'delivered_time')
                 or o.cancelled_time is distinct from public.tiktok_parse_time(o.raw->>'cancelled_time')) then
    raise exception '467 repair: a row''s times are still not 467''s reading of its raw text; nothing was changed'; end if;
  select md5(string_agg((to_jsonb(o) - c_cols)::text, '|' order by o.id)) into v_others_after from public.tiktok_order_rows o;
  if v_others_after is distinct from v_others_before then
    raise exception '467 repair: something other than the six times changed; nothing was changed'; end if;
  if (select count(*) from public.audit_logs a where a.action = 'tiktok_order_times_restored' and a.record_id = any (v_fix)
         and a.changed_by = v_actor and a.created_at = now()) <> n_rows then
    raise exception '467 repair: the audit rows were not written as expected; nothing was changed'; end if;

  raise notice '467 repair: done: % time(s) put right on % row(s) (% confirmed); the immutability trigger is on again', n_values, n_rows, n_confirmed;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);
  perform set_config('DateStyle', v_style, true);
  perform set_config('search_path', v_path, true);
end $repair$;
