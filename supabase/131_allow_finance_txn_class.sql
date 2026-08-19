-- =====================================================================
-- ENERGIA — THE 'finance' TXN CLASS WAS REJECTED BY A CHECK CONSTRAINT
--
-- Migration 130 added a 'finance' class for platform money movements — TikTok
-- ad payments, subscriptions, penalties, deposits, payouts — so they stop being
-- treated as customer orders.
--
-- I did not check that txn_class is constrained:
--
--     CHECK (txn_class = ANY (ARRAY['order','adjustment','refund']))
--
-- So importing any settlement file containing an ad payment failed outright:
--
--     new row for relation "tiktok_settlement_rows" violates check constraint
--     "tiktok_settlement_rows_txn_class_check"
--
-- That is worse than the bug it was fixing: the whole import stopped rather than
-- one row being misclassified. The constraint is widened to include 'finance'.
--
-- What I checked before widening it, rather than after:
--
--   * report_tiktok_settlement_summary() — its overall total sums EVERY row, so
--     a finance row is included in the settlement total. The adjustment and
--     refund sub-totals filter by class explicitly, so a finance row is simply
--     not counted as either, which is right.
--   * rematch_tiktok_settlements() — matches on 'order' or ('adjustment',
--     'refund') explicitly, so a finance row is never rematched against a
--     customer order. Also right.
--   * the frontend renders txn_class as text, so a fourth value displays
--     correctly with no change.
--
-- Additive and idempotent. Run AFTER 130.
-- =====================================================================

set check_function_bodies = off;

do $$
begin
  if exists (
    select 1 from pg_constraint
     where conname = 'tiktok_settlement_rows_txn_class_check'
       and pg_get_constraintdef(oid) like '%finance%'
  ) then
    raise notice 'the txn_class constraint already allows finance';
    return;
  end if;

  alter table public.tiktok_settlement_rows
    drop constraint if exists tiktok_settlement_rows_txn_class_check;

  alter table public.tiktok_settlement_rows
    add constraint tiktok_settlement_rows_txn_class_check
    check (txn_class = any (array['order', 'adjustment', 'refund', 'finance']));

  raise notice 'txn_class now accepts finance as well';
end $$;

-- Any staging table carrying the same column needs the same allowance, or the
-- import fails one step earlier instead.
do $$
declare r record;
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
    raise notice 'Widened % on %', r.conname, r.tbl;
  end loop;
end $$;

-- Confirm a finance row can now be stored, so this migration fails here rather
-- than during someone's import.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'tiktok_settlement_rows_txn_class_check'
       and pg_get_constraintdef(oid) like '%finance%'
  ) then
    raise exception 'txn_class still rejects finance — the import would fail';
  end if;
  raise notice 'Confirmed: a platform finance row can be stored';
end $$;

notify pgrst, 'reload schema';
