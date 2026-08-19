-- =====================================================================
-- ENERGIA — PLATFORM FINANCE ROWS SHOULD NOT SIT IN "PENDING" FOREVER
--
-- match_status is set to 'matched' when a settlement row finds its customer
-- order, and 'pending' otherwise:
--
--     case when v_match is not null then 'matched' else 'pending' end
--
-- "Pending" means "we expect to match this once the order appears". For a
-- platform money movement — a TikTok ad payment, a subscription fee, a payout —
-- there is no customer order and there never will be. Those rows sat in the
-- pending queue permanently, inflating the count of things needing attention
-- and hiding the rows that genuinely do.
--
-- A third status, 'no_match_needed', is added for them. They are settled,
-- complete, and require nothing further.
--
-- Existing finance rows already imported are moved across, so the pending queue
-- is correct immediately rather than only for future imports.
--
-- Additive and idempotent. Safe to run at any time after 66.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Allow the new status, wherever the constraint lives.
-- ---------------------------------------------------------------------
do $$
declare r record; v_n integer := 0;
begin
  for r in
    select c.conrelid::regclass as tbl, c.conname
      from pg_constraint c
     where c.contype = 'c'
       and pg_get_constraintdef(c.oid) like '%match_status%'
       and pg_get_constraintdef(c.oid) not like '%no_match_needed%'
  loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
    execute format(
      'alter table %s add constraint %I check (match_status = any (array[''matched'',''pending'',''no_match_needed'']))',
      r.tbl, r.conname);
    v_n := v_n + 1;
    raise notice 'Widened % on %', r.conname, r.tbl;
  end loop;
  if v_n = 0 then raise notice 'match_status already allows no_match_needed'; end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. New imports: a finance row is complete, not pending.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'stage_tiktok_settlement';
  if v_def is null then raise exception 'stage_tiktok_settlement not found'; end if;
  if position('no_match_needed' in v_def) > 0 then
    raise notice 'staging already marks finance rows as needing no match'; return;
  end if;

  v_new := replace(v_def,
    '      case when v_match is not null then ''matched'' else ''pending'' end,',
    '      -- A platform money movement has no customer order to wait for, so it' || chr(10) ||
    '      -- is complete rather than pending.' || chr(10) ||
    '      case when v_match is not null then ''matched''' || chr(10) ||
    '           when v_class = ''finance'' then ''no_match_needed''' || chr(10) ||
    '           else ''pending'' end,');

  if position('no_match_needed' in v_new) = 0 then
    raise exception 'Could not mark finance rows as needing no match';
  end if;
  execute v_new;
  raise notice 'new finance rows will import as "no match needed"';
end $patch$;

-- ---------------------------------------------------------------------
-- 3. Move rows already imported, so the pending queue is right now.
-- ---------------------------------------------------------------------
do $$
declare v_n integer;
begin
  update public.tiktok_settlement_rows
     set match_status = 'no_match_needed'
   where txn_class = 'finance'
     and match_status = 'pending'
     and matched_order_id is null;
  get diagnostics v_n = row_count;
  if v_n > 0 then
    raise notice 'Moved % platform finance row(s) out of the pending queue', v_n;
  else
    raise notice 'No finance rows were sitting in pending';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. Rematching must not pull a finance row back into pending.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rematch_tiktok_settlements';
  if v_def is null then raise notice 'rematch function not present'; return; end if;
  if position('no_match_needed' in v_def) > 0 then
    raise notice 'rematch already leaves finance rows alone'; return;
  end if;

  -- It only touches rows where match_status = 'pending', and a finance row is
  -- no longer pending, so it is already excluded. The guard is made explicit so
  -- a later change to that filter cannot quietly re-include them.
  v_new := replace(v_def,
    'r.match_status = ''pending''',
    'r.match_status = ''pending'' and coalesce(r.txn_class, '''') <> ''finance''');

  if position('no_match_needed' in v_new) = 0
     and position('<> ''finance''' in v_new) = 0 then
    raise notice 'rematch left unchanged — it filters on pending only';
    return;
  end if;
  execute v_new;
  raise notice 'rematch now skips platform finance rows explicitly';
end $patch$;

-- ---------------------------------------------------------------------
-- 5. Prove it, so this fails here rather than during an import.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_constraint where contype = 'c'
              and pg_get_constraintdef(oid) like '%match_status%'
              and pg_get_constraintdef(oid) not like '%no_match_needed%') then
    raise exception 'A match_status constraint still rejects no_match_needed';
  end if;
  if exists (select 1 from public.tiktok_settlement_rows
              where txn_class = 'finance' and match_status = 'pending') then
    raise exception 'Finance rows are still sitting in the pending queue';
  end if;
  raise notice 'Confirmed: platform finance rows are complete, not pending';
end $$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- 6. The STAGING status and the pending COUNT say the same thing.
--
--    Two more places call a finance row "pending":
--
--      staging_status := case when v_match is not null
--                             then 'New — Matched' else 'New — Pending Order' end;
--
--      if v_row.match_status = 'pending' then v_pending := v_pending + 1; end if;
--
--    Left alone, the row would read "no match needed" in one column and
--    "New — Pending Order" in the next, and would still be counted in the
--    import summary's pending tally.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'stage_tiktok_settlement';
  if v_def is null then raise exception 'stage_tiktok_settlement not found'; end if;
  if position('New — No Match Needed' in v_def) > 0 then
    raise notice 'the staging status already covers finance rows'; return;
  end if;

  v_new := replace(v_def,
    '        v_status := case when v_match is not null then ''New — Matched'' else ''New — Pending Order'' end;',
    '        v_status := case when v_match is not null then ''New — Matched''' || chr(10) ||
    '                         when v_class = ''finance'' then ''New — No Match Needed''' || chr(10) ||
    '                         else ''New — Pending Order'' end;');

  if position('New — No Match Needed' in v_new) = 0 then
    raise notice 'the staging status could not be updated — check migration 66 line 278';
  else
    execute v_new;
    raise notice 'finance rows now stage as "New — No Match Needed"';
  end if;
end $patch$;

-- The import summary must not count them as awaiting anything.
do $patch$
declare v_def text; v_new text; v_name text;
begin
  foreach v_name in array array['commit_tiktok_settlement','tiktok_settlement_batch_summary'] loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_name;
    if v_def is null then continue; end if;
    if position('<> ''finance''' in v_def) > 0 then
      raise notice '% already excludes finance from the pending count', v_name; continue;
    end if;

    v_new := replace(v_def,
      'if v_row.match_status = ''pending'' then v_pending := v_pending + 1; end if;',
      'if v_row.match_status = ''pending'' and coalesce(v_row.txn_class, '''') <> ''finance''' || chr(10) ||
      '      then v_pending := v_pending + 1; end if;');

    if v_new <> v_def then
      execute v_new;
      raise notice '% no longer counts finance rows as pending', v_name;
    end if;
  end loop;
end $patch$;

notify pgrst, 'reload schema';
