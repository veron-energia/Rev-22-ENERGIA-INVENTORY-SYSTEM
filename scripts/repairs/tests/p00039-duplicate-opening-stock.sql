-- The one-off repair of P00039's opening stock entered twice at WH-0906 (420,
-- the Owner's answer of 9 Oct 2026): scripts/repairs/p00039-duplicate-opening-stock.sql.
--
--   * it refuses while a correction for P00039 at WH-0906 waits, after one was
--     made since 30 Jul, when the two Stock Ins are not as read, and when
--     fewer than 3 are there;
--   * it takes 3 off with one inventory_adjustment movement whose note says
--     why (Stock History), records the stock change and one audit row;
--   * stock that moved since 9 Oct is still corrected by 3, and said so;
--   * a second run changes nothing.
--
-- The repair names the product by SKU, the warehouse by code and the two
-- Stock Ins by id, so the fixture uses those with invented names. Disposable
-- database only; everything is rolled back. Needs 406 (write_audit); 420 is
-- not needed.
\set ON_ERROR_STOP on
begin;

create temp table repy(k text primary key, id uuid);

-- Fixture: the product, the warehouse, the three Opening stock entries of 30
-- Jul, 3 out since, and 77 left; a store and a staff login for a request.
do $$
declare p uuid := '07ad27ec-579b-4a4c-954d-2730dec80903'; wh uuid := '6f8fe10a-9385-4c11-971b-791b2332b5de';
        stf uuid := gen_random_uuid();
begin
  perform set_config('request.jwt.claims', '', true);
  insert into public.products (id, name, sku) values (p, 'REPY Pad', 'P00039');
  insert into public.warehouses (id, name, code) values (wh, 'REPY Warehouse', 'WH-0906');
  insert into public.stock_movements (id, product_id, movement_type, to_warehouse_id, quantity, notes, created_at) values
    ('a399b487-c2a0-4777-b407-43957de95db8', p, 'warehouse_stock_in', wh, 3, 'Opening stock', '2026-07-30 04:17:31.94692+00'),
    ('1f43e3c0-2cdb-4290-9ee0-794d3ad90f48', p, 'warehouse_stock_in', wh, 3, 'Opening stock', '2026-07-30 04:37:48.58599+00'),
    (gen_random_uuid(), p, 'warehouse_stock_in', wh, 74, 'Opening stock', '2026-07-30 04:49:26.010106+00');
  insert into public.warehouse_inventory (warehouse_id, product_id, current_qty) values (wh, p, 77);
  insert into auth.users (id, email) values (stf, 'repy-staff@sig.invalid');
  insert into public.profiles (id, full_name, email, role, is_active) values (stf, 'REPY staff', 'repy-staff@sig.invalid', 'staff', true);
  insert into repy values ('p', p), ('wh', wh), ('staff', stf);
end $$;

-- ── 1. Refusals: nothing changes ────────────────────────────────────────
-- A correction waits for approval.
insert into public.approval_requests (request_type, status, requested_by, related_record_id, reason, payload)
select 'adjustment', 'pending', (select id from repy where k = 'staff'), (select id from repy where k = 'p'), 'Count',
       jsonb_build_object('location_type', 'warehouse', 'location_id', (select id from repy where k = 'wh'),
                          'product_id', (select id from repy where k = 'p'), 'current_qty', 77, 'new_qty', 74, 'difference', -3);
\set ON_ERROR_STOP off
savepoint s1;
\echo 'R1: the ERROR below is expected (a correction waits for approval)'
\ir ../p00039-duplicate-opening-stock.sql
rollback to savepoint s1;
\set ON_ERROR_STOP on
select set_config('repy.last', :'LAST_ERROR_MESSAGE', true) is null as repy_unused \gset
do $$
begin
  if current_setting('repy.last') <> 'repair: a stock correction for P00039 at WH-0906 waits for approval; approve or reject it first; nothing was changed' then
    raise exception 'FAIL: R1 refused with %', current_setting('repy.last'); end if;
end $$;
delete from public.approval_requests where payload ->> 'product_id' = (select id from repy where k = 'p')::text;

-- A correction was made since 30 Jul: a count may already have taken the 3 off.
savepoint fx2;
insert into public.stock_movements (product_id, movement_type, from_warehouse_id, quantity, notes, created_at)
select (select id from repy where k = 'p'), 'inventory_adjustment', (select id from repy where k = 'wh'), 3, 'Adjustment: Count',
       '2026-08-31 02:00:00+00';
\set ON_ERROR_STOP off
savepoint s2;
\echo 'R2: the ERROR below is expected (a correction since 30 Jul)'
\ir ../p00039-duplicate-opening-stock.sql
rollback to savepoint s2;
\set ON_ERROR_STOP on
select set_config('repy.last', :'LAST_ERROR_MESSAGE', true) is null as repy_unused \gset
do $$
begin
  if current_setting('repy.last') not like 'repair: P00039 at WH-0906 was counted and corrected after 30 Jul 2026%' then
    raise exception 'FAIL: R2 refused with %', current_setting('repy.last'); end if;
end $$;
rollback to savepoint fx2;

-- The Stock Ins are not as read (the second is 4, not 3).
savepoint fx3;
update public.stock_movements set quantity = 4 where id = '1f43e3c0-2cdb-4290-9ee0-794d3ad90f48';
\set ON_ERROR_STOP off
savepoint s3;
\echo 'R3: the ERROR below is expected (the Stock Ins are not as read)'
\ir ../p00039-duplicate-opening-stock.sql
rollback to savepoint s3;
\set ON_ERROR_STOP on
select set_config('repy.last', :'LAST_ERROR_MESSAGE', true) is null as repy_unused \gset
do $$
begin
  if current_setting('repy.last') not like 'repair: the two Opening stock entries of 30 Jul 2026 for P00039 at WH-0906 are not as read%' then
    raise exception 'FAIL: R3 refused with %', current_setting('repy.last'); end if;
end $$;
rollback to savepoint fx3;

-- Fewer than 3 there now.
savepoint fx4;
update public.warehouse_inventory set current_qty = 2 where product_id = (select id from repy where k = 'p');
\set ON_ERROR_STOP off
savepoint s4;
\echo 'R4: the ERROR below is expected (only 2 there)'
\ir ../p00039-duplicate-opening-stock.sql
rollback to savepoint s4;
\set ON_ERROR_STOP on
select set_config('repy.last', :'LAST_ERROR_MESSAGE', true) is null as repy_unused \gset
do $$
begin
  if current_setting('repy.last') <> 'repair: WH-0906 holds 2 of P00039 now, fewer than the 3 to take off; count the shelf first; nothing was changed' then
    raise exception 'FAIL: R4 refused with %', current_setting('repy.last'); end if;
end $$;
rollback to savepoint fx4;
do $$
begin
  if (select current_qty from public.warehouse_inventory where product_id = (select id from repy where k = 'p')) <> 77
     or exists (select 1 from public.stock_movements where movement_type = 'inventory_adjustment'
                 and product_id = (select id from repy where k = 'p'))
     or exists (select 1 from public.audit_logs where action = 'duplicate_stock_in_removed') then
    raise exception 'FAIL: a refused run changed something'; end if;
end $$;

-- ── 2. Stock that moved since 9 Oct is still corrected by 3 ─────────────
savepoint fx5;
update public.warehouse_inventory set current_qty = 50 where product_id = (select id from repy where k = 'p');
\ir ../p00039-duplicate-opening-stock.sql
do $$
begin
  if (select current_qty from public.warehouse_inventory where product_id = (select id from repy where k = 'p')) <> 47 then
    raise exception 'FAIL: 50 did not become 47'; end if;
end $$;
rollback to savepoint fx5;

-- ── 3. The run as it would go today: 77 -> 74 ───────────────────────────
\ir ../p00039-duplicate-opening-stock.sql
do $$
declare p uuid := (select id from repy where k = 'p'); wh uuid := (select id from repy where k = 'wh'); n int;
begin
  if (select current_qty from public.warehouse_inventory where product_id = p and warehouse_id = wh) <> 74 then
    raise exception 'FAIL: the stock is not 74'; end if;
  select count(*) into n from public.stock_movements m
   where m.product_id = p and m.movement_type = 'inventory_adjustment' and m.from_warehouse_id = wh and m.to_warehouse_id is null
     and m.quantity = 3 and m.notes = 'Adjustment: Opening stock of 30 Jul 2026 was entered twice (3 at 12:17, the same 3 again at 12:37). The second 3 is taken off, as the Owner decided on 9 Oct 2026.';
  if n <> 1 then raise exception 'FAIL: % correction movements, not 1', n; end if;
  if not exists (select 1 from public.stock_history_inventory_changes c
                  where c.product_id = p and c.location_key = 'warehouse:' || wh and c.delta = -3
                    and c.before_quantity = 77 and c.after_quantity = 74) then
    raise exception 'FAIL: Stock History has no -3 change from 77 to 74'; end if;
  if (select count(*) from public.audit_logs a where a.record_id = p and a.action = 'duplicate_stock_in_removed'
        and (a.old_data ->> 'qty')::int = 77 and (a.new_data ->> 'qty')::int = 74) <> 1 then
    raise exception 'FAIL: no single audit row for the correction'; end if;
  -- The Stock Ins themselves stay as they were (history is not rewritten).
  if (select count(*) from public.stock_movements where product_id = p and movement_type = 'warehouse_stock_in') <> 3 then
    raise exception 'FAIL: a Stock In was changed or removed'; end if;
end $$;

-- ── 4. A second run changes nothing ─────────────────────────────────────
create temp table repy_before as
  select (select count(*) from public.stock_movements) m, (select count(*) from public.audit_logs) a,
         (select current_qty from public.warehouse_inventory where product_id = (select id from repy where k = 'p')) q;
\ir ../p00039-duplicate-opening-stock.sql
do $$
begin
  if (select count(*) from public.stock_movements) <> (select m from repy_before)
     or (select count(*) from public.audit_logs) <> (select a from repy_before)
     or (select current_qty from public.warehouse_inventory where product_id = (select id from repy where k = 'p')) <> (select q from repy_before) then
    raise exception 'FAIL: a second run changed something'; end if;
  raise notice 'PASS: the P00039 repair refuses while a correction waits, after one since 30 Jul, when the Stock Ins are not as read and when fewer than 3 are there; takes 3 off with one movement that says why, a Stock History change and one audit row, also when the stock moved since; leaves the Stock Ins; a second run changes nothing';
end $$;
rollback;
