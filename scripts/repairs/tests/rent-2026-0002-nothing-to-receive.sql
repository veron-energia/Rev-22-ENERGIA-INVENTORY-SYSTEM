-- The RENT-2026-0002 repair (scripts/repairs/rent-2026-0002-nothing-to-receive.sql)
-- against fixtures shaped as production was on 9 Oct 2026 (rental numbers
-- only; every name is invented): an old-style rental cancelled as a duplicate,
-- never released, on no invoice, that reads as still out; and its original,
-- returned. Refused while a stock movement names it; settled with no stock
-- moved and audited; a second run changes nothing. Disposable database only;
-- everything is rolled back.
\set ON_ERROR_STOP on
begin;

do $$
declare o uuid := gen_random_uuid(); wh uuid; sp uuid; c uuid;
begin
  insert into auth.users(id, email) values (o, 'trn-owner@tests.invalid');
  insert into profiles(id, full_name, email, role, is_active) values (o, 'TRN Owner', 'trn-owner@tests.invalid', 'owner', true);
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into warehouses(name, code) values ('TRN Warehouse', 'TRNW') returning id into wh;
  insert into customers(full_name, phone) values ('TRN Renter', '+61491572665') returning id into c;
  insert into special_products(name, sku, rate_day, is_active) values ('TRN Machine', 'TRN-M', 20, true) returning id into sp;
  insert into rentals(rental_no, customer_id, special_product_id, warehouse_id, quantity, rate_type, periods, start_date,
                      expected_return_date, status, activated_at, cancelled_at, stock_returned, notes)
    values ('RENT-2026-0002', c, sp, wh, 1, 'day', 1, '2026-08-09', '2026-08-10', 'cancelled', '2026-08-09 11:32+00',
            '2026-10-06 10:31+00', false, 'Duplicate of RNT-2026-0003');
  insert into rentals(rental_no, customer_id, special_product_id, quantity, rate_type, periods, start_date,
                      expected_return_date, status, activated_at, returned_at, stock_returned)
    values ('RNT-2026-0003', c, sp, 1, 'day', 1, '2026-08-15', '2026-09-09', 'returned', '2026-08-15 05:58+00',
            '2026-09-09 04:00+00', true);
  if not rental_awaiting_return((select id from rentals where rental_no = 'RENT-2026-0002')) then
    raise exception 'Fixture: RENT-2026-0002 should read as still out, as on production'; end if;
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- ===== 1. A movement names it: refused, nothing kept =====
savepoint trn_guard;
with p as (insert into products(name, sku, product_type) values ('TRN Part', 'TRN-P', 'own') returning id)
insert into stock_movements(product_id, movement_type, to_warehouse_id, quantity, notes)
  select p.id, 'invoice_cancel_return', (select id from warehouses where code = 'TRNW'), 1, 'Fixture: RENT-2026-0002 back' from p;
\set ON_ERROR_STOP off
\ir ../rent-2026-0002-nothing-to-receive.sql
\set ON_ERROR_STOP on
rollback to savepoint trn_guard;
release savepoint trn_guard;
select set_config('trn.refused', :'LAST_ERROR_MESSAGE', true) as trn_refused \gset
do $$
begin
  if current_setting('trn.refused') not like 'A stock movement names RENT-2026-0002, so it did take stock; nothing was changed%' then
    raise exception 'FAIL 1: not refused as expected: %', current_setting('trn.refused'); end if;
  raise notice 'PASS 1: refused while a stock movement names it';
end $$;

-- ===== 2. The repair =====
\ir ../rent-2026-0002-nothing-to-receive.sql
do $$
declare r rentals%rowtype;
begin
  select * into r from rentals where rental_no = 'RENT-2026-0002';
  if r.status::text <> 'cancelled' or not r.stock_returned or rental_awaiting_return(r.id)
     or r.notes not like '%Nothing to receive: a duplicate of RNT-2026-0003 that never took stock%' then
    raise exception 'FAIL 2: %', to_jsonb(r) - 'notes'; end if;
  if exists (select 1 from stock_movements) or exists (select 1 from warehouse_inventory) or exists (select 1 from special_product_stock) then
    raise exception 'FAIL 2: stock moved'; end if;
  if (select count(*) from audit_logs where record_id = r.id and action = 'rental_settled_no_stock') <> 1 then
    raise exception 'FAIL 2: not audited once'; end if;
  raise notice 'PASS 2: settled with no stock moved, still cancelled, no longer read as out, audited once';
end $$;

-- ===== 3. Run again =====
\ir ../rent-2026-0002-nothing-to-receive.sql
do $$
begin
  if (select count(*) from audit_logs where action = 'rental_settled_no_stock') <> 1 then
    raise exception 'FAIL 3: a second run wrote again'; end if;
  raise notice 'PASS 3: a second run changes nothing';
end $$;

rollback;
