-- The one-off repair of the stock under deleted products (420, STOCK-7, Q12):
-- scripts/repairs/deleted-products-stock.sql.
--
--   * it refuses while a choice is still '?', for a write-off with no note,
--     and when a product's stock is not what was read on 9 Oct 2026;
--   * 'restore' brings the product back, active, its store price on;
--   * 'write_off' sets every place to 0 with an inventory_adjustment movement
--     whose note says why, and leaves the product deleted;
--   * 'leave' changes nothing; a second run changes nothing; audit rows.
--
-- The repair names the three products by SKU and their places by code, so the
-- fixture uses those codes with invented names. Disposable database only;
-- everything is rolled back. Needs 406 (write_audit); 420 is not needed.
\set ON_ERROR_STOP on
begin;

create temp table repx(k text primary key, id uuid);

-- Fixture: the three products, deleted, with their stock; a store price.
do $$
declare st uuid; wh uuid; p1 uuid; p2 uuid; p3 uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  insert into public.stores (name, code, country_code) values ('REPX Store', 'RETAIL-ADELPHI', 'SG') returning id into st;
  insert into public.warehouses (name, code) values ('REPX Warehouse', 'WH-0906') returning id into wh;
  insert into public.products (name, sku) values ('REPX Set', 'PK00031') returning id into p1;
  insert into public.products (name, sku) values ('REPX Salt', 'Zhimalaya') returning id into p2;
  insert into public.products (name, sku) values ('REPX Pillow', 'ZPILLOWCASEFLORAL') returning id into p3;
  insert into public.store_inventory (store_id, product_id, current_qty) values (st, p1, 3), (st, p2, 13);
  insert into public.warehouse_inventory (warehouse_id, product_id, current_qty) values (wh, p3, 5);
  insert into public.store_product_prices (store_id, product_id, selling_price, is_active) values (st, p1, 50, false);
  -- Deleted as the old page did it (before 420, with stock).
  alter table public.products disable trigger user;
  update public.products set deleted_at = '2026-09-14 05:54:00+00', is_active = false where id in (p1, p2, p3);
  alter table public.products enable trigger user;
  insert into repx values ('store', st), ('warehouse', wh), ('p1', p1), ('p2', p2), ('p3', p3);
end $$;

-- ── 1. The file as it is in the repository: every choice '?' ─────────────
\set ON_ERROR_STOP off
savepoint s1;
\echo 'R1: the ERROR below is expected (every choice is still ''?'')'
\ir ../deleted-products-stock.sql
rollback to savepoint s1;
\set ON_ERROR_STOP on
select set_config('repx.last', :'LAST_ERROR_MESSAGE', true) is null as repx_unused \gset
do $$
begin
  if current_setting('repx.last') not like 'repair: fill in a choice for every product%' then
    raise exception 'FAIL: R1 refused with %', current_setting('repx.last'); end if;
  if exists (select 1 from public.products where sku in ('PK00031', 'Zhimalaya', 'ZPILLOWCASEFLORAL') and deleted_at is null)
     or (select sum(current_qty) from public.store_inventory where product_id in (select id from repx where k in ('p1','p2'))) <> 16 then
    raise exception 'FAIL: the repair changed something while a choice was ''?'''; end if;
end $$;

-- A write-off with no note is refused too.
create temp table if not exists repair_420_choices (
  sku text primary key, action text not null, note text, store_price numeric(12,2));
delete from repair_420_choices;
insert into repair_420_choices values ('PK00031', 'leave', null, null), ('Zhimalaya', 'write_off', '  ', null),
                                      ('ZPILLOWCASEFLORAL', 'leave', null, null);
\set ON_ERROR_STOP off
savepoint s2;
\echo 'R2: the ERROR below is expected (a write-off with no note)'
\ir ../deleted-products-stock.sql
rollback to savepoint s2;
\set ON_ERROR_STOP on
select set_config('repx.last', :'LAST_ERROR_MESSAGE', true) is null as repx_unused \gset
do $$
begin
  if current_setting('repx.last') not like 'repair: a write-off needs a note%' then
    raise exception 'FAIL: R2 refused with %', current_setting('repx.last'); end if;
  if (select current_qty from public.store_inventory where product_id = (select id from repx where k = 'p2')) <> 13 then
    raise exception 'FAIL: a write-off with no note went through'; end if;
end $$;

-- Stock that moved since 9 Oct 2026 is refused.
update public.store_inventory set current_qty = 12 where product_id = (select id from repx where k = 'p2');
delete from repair_420_choices;
insert into repair_420_choices values ('PK00031', 'leave', null, null),
  ('Zhimalaya', 'write_off', 'Not on the shelf at the fixture check', null), ('ZPILLOWCASEFLORAL', 'leave', null, null);
\set ON_ERROR_STOP off
savepoint s3;
\echo 'R3: the ERROR below is expected (the stock moved since 9 Oct 2026)'
\ir ../deleted-products-stock.sql
rollback to savepoint s3;
\set ON_ERROR_STOP on
select set_config('repx.last', :'LAST_ERROR_MESSAGE', true) is null as repx_unused \gset
do $$
begin
  if current_setting('repx.last') <> 'repair: the stock of Zhimalaya is Zhimalaya|store|RETAIL-ADELPHI|12 now, not Zhimalaya|store|RETAIL-ADELPHI|13 as read on 9 Oct 2026; re-read it; nothing was changed' then
    raise exception 'FAIL: R3 refused with %', current_setting('repx.last'); end if;
  if (select current_qty from public.store_inventory where product_id = (select id from repx where k = 'p2')) <> 12
     or exists (select 1 from public.stock_movements where product_id = (select id from repx where k = 'p2')) then
    raise exception 'FAIL: the repair wrote off stock that moved since it was read'; end if;
end $$;
update public.store_inventory set current_qty = 13 where product_id = (select id from repx where k = 'p2');

-- ── 2. Restore one, write off two ───────────────────────────────────────
delete from repair_420_choices;
insert into repair_420_choices values
  ('PK00031', 'restore', 'On the shelf and still sold', null),
  ('Zhimalaya', 'write_off', 'Not on the shelf at the fixture check', null),
  ('ZPILLOWCASEFLORAL', 'write_off', 'Damaged, thrown away', null);
\ir ../deleted-products-stock.sql
do $$
declare p1 uuid := (select id from repx where k = 'p1'); p2 uuid := (select id from repx where k = 'p2');
        p3 uuid := (select id from repx where k = 'p3'); n int;
begin
  if not exists (select 1 from public.products where id = p1 and deleted_at is null and is_active) then
    raise exception 'FAIL: the restored product is not back and active'; end if;
  if (select current_qty from public.store_inventory where product_id = p1) <> 3 then
    raise exception 'FAIL: restoring changed the stock'; end if;
  if not exists (select 1 from public.store_product_prices where product_id = p1 and is_active and deleted_at is null) then
    raise exception 'FAIL: the restored product has no live store price'; end if;
  if not exists (select 1 from public.products where id = p2 and deleted_at is not null)
     or (select current_qty from public.store_inventory where product_id = p2) <> 0
     or (select current_qty from public.warehouse_inventory where product_id = p3) <> 0 then
    raise exception 'FAIL: the written-off stock is not 0, or the product came back'; end if;
  if not exists (select 1 from public.stock_movements m where m.product_id = p2 and m.movement_type = 'inventory_adjustment'
                  and m.from_store_id = (select id from repx where k = 'store') and m.quantity = 13
                  and m.notes = 'Written off: product deleted 14 Sep 2026. Not on the shelf at the fixture check')
     or not exists (select 1 from public.stock_movements m where m.product_id = p3 and m.movement_type = 'inventory_adjustment'
                  and m.from_warehouse_id = (select id from repx where k = 'warehouse') and m.quantity = 5
                  and m.notes like 'Written off: product deleted 14 Sep 2026. Damaged%') then
    raise exception 'FAIL: the write-off movements are not there as expected'; end if;
  select count(*) into n from public.audit_logs where record_id in (p1, p2, p3)
     and action in ('deleted_product_restored', 'deleted_product_stock_written_off');
  if n <> 3 then raise exception 'FAIL: % audit rows, not 3', n; end if;
end $$;

-- ── 3. A second run changes nothing ─────────────────────────────────────
create temp table repx_before as
  select (select count(*) from public.stock_movements) m, (select count(*) from public.audit_logs) a;
\ir ../deleted-products-stock.sql
do $$
begin
  if (select count(*) from public.stock_movements) <> (select m from repx_before)
     or (select count(*) from public.audit_logs) <> (select a from repx_before) then
    raise exception 'FAIL: a second run changed something'; end if;
  raise notice 'PASS: the deleted-products repair refuses unfilled choices, a write-off with no note and stock that moved; restores with a live price, writes off to 0 with a movement that says why, leaves the rest, audits each, and a second run changes nothing';
end $$;
rollback;
