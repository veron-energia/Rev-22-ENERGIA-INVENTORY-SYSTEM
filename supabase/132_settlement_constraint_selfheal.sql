-- =====================================================================
-- ENERGIA — THE txn_class CONSTRAINT KEPT REVERTING
--
-- Migration 131 widened the constraint to allow 'finance', and it worked. The
-- import still failed, because "66_phase17_tiktok_settlement.sql" sorts AFTER
-- "131_" as text:
--
--     131_allow_finance_txn_class.sql
--     66_phase17_tiktok_settlement.sql      <-- runs LAST
--
-- Migration 66 recreates three things unconditionally, all of which reverted
-- the fix:
--
--   * the txn_class CHECK, back to three values;
--   * tiktok_txn_class(), back to classing ad payments as orders;
--   * the settlement duplicate rule, back to rejecting a repeated order id.
--
-- This is the same trap that hid the customer-name fix earlier. File 66 has now
-- been corrected at source so it carries all three, and this migration repairs
-- whatever is in place at the time it runs — so the right result is reached
-- from any starting point, in any order.
--
-- Additive and idempotent. Safe to run at any time.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. The constraint, wherever it appears and whatever it currently says.
-- ---------------------------------------------------------------------
do $$
declare r record; v_n integer := 0;
begin
  for r in
    select c.conrelid::regclass as tbl, c.conname
      from pg_constraint c
     where c.contype = 'c'
       and pg_get_constraintdef(c.oid) like '%txn_class%'
       and pg_get_constraintdef(c.oid) not like '%finance%'
  loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
    execute format(
      'alter table %s add constraint %I check (txn_class = any (array[''order'',''adjustment'',''refund'',''finance'']))',
      r.tbl, r.conname);
    v_n := v_n + 1;
    raise notice 'Repaired % on %', r.conname, r.tbl;
  end loop;
  if v_n = 0 then raise notice 'The txn_class constraint already allows finance'; end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. The classifier.
-- ---------------------------------------------------------------------
create or replace function public.tiktok_txn_class(p_type text)
returns text language sql immutable as $function$
  select case
    when lower(coalesce(p_type,'')) like '%adjust%' then 'adjustment'
    when lower(coalesce(p_type,'')) like '%refund%'
      or lower(coalesce(p_type,'')) like '%return%' then 'refund'
    when lower(coalesce(p_type,'')) like '%tiktok ads%'
      or lower(coalesce(p_type,'')) like '%gmv payment%'
      or lower(coalesce(p_type,'')) like '%advertis%'
      or lower(coalesce(p_type,'')) like '%subscription%'
      or lower(coalesce(p_type,'')) like '%penalt%'
      or lower(coalesce(p_type,'')) like '%deposit%'
      or lower(coalesce(p_type,'')) like '%loan%'
      or lower(coalesce(p_type,'')) like '%payout%'
      or lower(coalesce(p_type,'')) like '%transfer%' then 'finance'
    else 'order'
  end
$function$;

-- ---------------------------------------------------------------------
-- 3. The matcher: a finance row has no customer order.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'tiktok_settlement_match';
  if v_def is null then raise notice 'matcher not present'; return; end if;
  if position('''finance''' in v_def) > 0 then
    raise notice 'the matcher already skips finance rows'; return;
  end if;

  v_new := replace(v_def,
    '  select case' || chr(10) || '    when p_class = ''order'' then',
    '  select case' || chr(10) ||
    '    when p_class = ''finance'' then null::text' || chr(10) ||
    '    when p_class = ''order'' then');

  if position('''finance''' in v_new) = 0 then
    raise exception 'Could not repair the settlement matcher';
  end if;
  execute v_new;
  raise notice 'the matcher now skips finance rows';
end $patch$;

-- ---------------------------------------------------------------------
-- 4. The duplicate rule: one order may settle across several lines.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'stage_tiktok_settlement';
  if v_def is null then raise notice 'staging function not present'; return; end if;
  if position('r.settlement_amount, 0) = coalesce(v_settle' in v_def) > 0 then
    raise notice 'the duplicate rule already allows legitimate repeats'; return;
  end if;

  v_new := replace(v_def,
    '    v_dup := v_status is null and exists (select 1 from public.tiktok_settlement_rows
              where batch_id = v_batch and order_id = v_oaid);',
    '    v_dup := v_status is null and exists (select 1 from public.tiktok_settlement_rows r
              where r.batch_id = v_batch
                and r.order_id = v_oaid
                and coalesce(r.transaction_type, '''') = coalesce(v_type, '''')
                and r.related_order_id is not distinct from v_related
                and coalesce(r.settlement_amount, 0) = coalesce(v_settle, 0));');

  if position('r.settlement_amount, 0) = coalesce(v_settle' in v_new) = 0 then
    raise notice 'the duplicate rule could not be repaired automatically — check migration 66';
    return;
  end if;
  execute v_new;
  raise notice 'the duplicate rule now allows legitimate repeats';
end $patch$;

-- ---------------------------------------------------------------------
-- 5. Prove all four are in place, so this fails here rather than during an
--    import. Two rounds of "fixed" reports have already been wrong.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_constraint where contype = 'c'
              and pg_get_constraintdef(oid) like '%txn_class%'
              and pg_get_constraintdef(oid) not like '%finance%') then
    raise exception 'A txn_class constraint still rejects finance';
  end if;
  if public.tiktok_txn_class('GMV payment for TikTok Ads') <> 'finance' then
    raise exception 'tiktok_txn_class still treats ad payments as orders';
  end if;
  if public.tiktok_txn_class('Order') <> 'order'
     or public.tiktok_txn_class('Customer refund') <> 'refund'
     or public.tiktok_txn_class('Adjustment') <> 'adjustment' then
    raise exception 'tiktok_txn_class broke an existing class';
  end if;
  raise notice 'Confirmed: constraint, classifier and matcher all accept finance rows';
end $$;

notify pgrst, 'reload schema';
