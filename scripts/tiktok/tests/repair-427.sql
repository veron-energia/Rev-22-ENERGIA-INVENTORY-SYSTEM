-- The two 427 repairs (scripts/tiktok/repair/427-*.sql), run against
-- invented fixtures (an Owner login, an Adelphi store, the seven settlement
-- lines, with ids made here and given to the repairs as the hand-off's
-- production ids are given at deploy), with 427 applied inside this
-- transaction.
--
--   1. 427-july-orders-reviewed.sql: refuses without the ids, with lines
--      that are not the six read (a wrong amount), with an actor who is not
--      an Owner, and when a line is not as read (superseded, or matched
--      since); records the six July lines as needing no stock taken off, as
--      the Owner, audited; a second run changes nothing.
--   2. 427-take-off-27-aug-order.sql: refuses without the ids, without the order's lines, with
--      a line the Import page could not deduct, and when Adelphi is short;
--      with the lines and no "checked" it only reports; checked, it imports
--      the order through the Import page's functions (stock off at Adelphi,
--      Stock History, the line matched, the alert gone); a second run changes
--      nothing; a line reviewed as needing no stock is refused.
--
-- Disposable database only (it needs no production rows: it makes them);
-- everything is rolled back. Run the file on its own:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/tiktok/tests/repair-427.sql
-- Every name, id, order and SKU is invented (T427). The repairs print ERROR
-- lines for the refusals; they are expected and checked below.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;

\ir ../../../supabase/427_dashboard_reports_and_takings.sql
create function pg_temp.settled_without_order() returns int language sql as $$
  select count(distinct (r.store_id, coalesce(r.order_id, r.related_order_id, r.adjustment_id, r.id::text)))::int
    from public.tiktok_settlement_rows r
   where r.confirmed and r.is_current and r.match_status = 'pending'
     and not exists (select 1 from public.tiktok_settlement_reviews v where v.settlement_row_id = r.id) $$;

-- ═════ Fixtures (ids made here) ═════
do $$
declare v uuid; b uuid; st constant uuid := gen_random_uuid(); o constant uuid := gen_random_uuid();
  mg constant uuid := gen_random_uuid();
begin
  insert into auth.users(id, email) values (o, 't427-repair-owner@sig.invalid'), (mg, 't427-repair-manager@sig.invalid');
  insert into public.profiles(id, full_name, email, role, is_active)
  values (o, 'T427 Owner', 't427-repair-owner@sig.invalid', 'owner', true),
         (mg, 'T427 Manager', 't427-repair-manager@sig.invalid', 'manager', true);
  insert into public.stores(id, name, code, country_code) values (st, 'T427 Adelphi', 'T427ADL', 'SG');
  insert into fx values ('owner', o), ('manager', mg), ('store', st);
  insert into public.tiktok_status_mappings(status_label, status_norm, action, marks_shipped)
  select x.l, public.tiktok_norm_status(x.l), 'deduct', true from (values ('T427 Shipped'), ('T427 Completed')) x(l)
  on conflict (status_norm) do nothing;
  insert into public.tiktok_import_batches(store_id, file_kind, file_name, status, uploaded_by)
  values (st, 'settlement', 'T427 settlement', 'confirmed', o) returning id into b;
  insert into public.tiktok_settlement_rows(id, batch_id, store_id, row_no, order_id, transaction_type, txn_class, settlement_amount,
                                            revenue_amount, fee_amount, order_created_time, settled_time, match_status, confirmed, is_current)
  select x.id, b, st, x.n, x.ord, 'Order', 'order', x.amt, x.amt + 1, -1, x.created::timestamptz, x.created::timestamptz + interval '5 days',
         'pending', true, true
    from (values (1, gen_random_uuid(), 'T427-JUL-1', 340.99, '2026-07-24 16:00+00'),
                 (2, gen_random_uuid(), 'T427-JUL-2', 7.22, '2026-07-26 16:00+00'),
                 (3, gen_random_uuid(), 'T427-JUL-3', 65.26, '2026-07-27 16:00+00'),
                 (4, gen_random_uuid(), 'T427-JUL-4', 117.80, '2026-07-27 16:00+00'),
                 (5, gen_random_uuid(), 'T427-JUL-4', 259.54, '2026-07-27 16:00+00'),
                 (6, gen_random_uuid(), 'T427-JUL-5', 7.65, '2026-07-29 16:00+00'),
                 (7, gen_random_uuid(), 'T427-AUG-1', 256.51, '2026-08-27 16:00+00')) x(n, id, ord, amt, created);
  insert into fx select 'line' || r.row_no, r.id from public.tiktok_settlement_rows r where r.batch_id = b;
  insert into public.products(name, sku) values ('T427 Soap', 'T427-SOAP') returning id into v; insert into fx values ('soap', v);
  insert into public.products(name, sku) values ('T427 Corset', 'T427-CORSET') returning id into v; insert into fx values ('corset', v);
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, pg_temp.fx('soap'), 5), (st, pg_temp.fx('corset'), 1);
  insert into public.tiktok_sku_aliases(store_id, seller_sku, target_kind, target_id, created_by)
  values (st, 'T427-SKU-SOAP', 'product', pg_temp.fx('soap'), o), (st, 'T427-SKU-CORSET', 'product', pg_temp.fx('corset'), o);
  -- A count on 1 Oct took one soap off at Adelphi (the repair reports it).
  insert into public.stock_movements(product_id, movement_type, from_store_id, quantity, notes, created_by, created_at)
  values (pg_temp.fx('soap'), 'inventory_adjustment', st, 1, 'T427 September closing', o, timestamptz '2026-10-01 07:57+00');
  -- The ids, given as at deploy (for the rest of this transaction).
  perform set_config('repair427.actor', o::text, true), set_config('repair427.store', st::text, true),
          set_config('repair427.july_rows', (select jsonb_agg(jsonb_build_object('id', r.id, 'order_id', r.order_id, 'amount', r.settlement_amount) order by r.row_no)
                                               from public.tiktok_settlement_rows r where r.batch_id = b and r.row_no <= 6)::text, true),
          set_config('repair427.aug_row', pg_temp.fx('line7')::text, true), set_config('repair427.aug_order', 'T427-AUG-1', true);
end $$;

-- ═════ 1. The July lines ═════
savepoint r0a;
select set_config('repair427.july_rows', '', true);
\set ON_ERROR_STOP off
\ir ../repair/427-july-orders-reviewed.sql
\set ON_ERROR_STOP on
rollback to savepoint r0a;
select set_config('t427r.no_ids', :'LAST_ERROR_MESSAGE', true) as kept \gset
savepoint r0b;
select set_config('repair427.july_rows', (select jsonb_agg(case when x->>'order_id' = 'T427-JUL-2' then jsonb_set(x, '{amount}', '7.23') else x end)
                                            from jsonb_array_elements(current_setting('repair427.july_rows')::jsonb) x)::text, true);
\set ON_ERROR_STOP off
\ir ../repair/427-july-orders-reviewed.sql
\set ON_ERROR_STOP on
rollback to savepoint r0b;
select set_config('t427r.wrong_rows', :'LAST_ERROR_MESSAGE', true) as kept \gset
savepoint r0c;
select set_config('repair427.actor', pg_temp.fx('manager')::text, true);
\set ON_ERROR_STOP off
\ir ../repair/427-july-orders-reviewed.sql
\set ON_ERROR_STOP on
rollback to savepoint r0c;
select set_config('t427r.not_owner', :'LAST_ERROR_MESSAGE', true) as kept \gset
savepoint r1;
update public.tiktok_settlement_rows set is_current = false where id = pg_temp.fx('line2');
\set ON_ERROR_STOP off
\ir ../repair/427-july-orders-reviewed.sql
\set ON_ERROR_STOP on
rollback to savepoint r1;
select set_config('t427r.superseded', :'LAST_ERROR_MESSAGE', true) as kept \gset
savepoint r2;
select public.rematch_tiktok_settlements(pg_temp.fx('store'), 'T427-JUL-5');
\set ON_ERROR_STOP off
\ir ../repair/427-july-orders-reviewed.sql
\set ON_ERROR_STOP on
rollback to savepoint r2;
select set_config('t427r.matched', :'LAST_ERROR_MESSAGE', true) as kept \gset
do $$
begin
  perform pg_temp.check(current_setting('t427r.no_ids') like '427 repair: give the ids first%',
    '1: without the ids it refuses: ' || current_setting('t427r.no_ids'));
  perform pg_temp.check(current_setting('t427r.wrong_rows') like '427 repair: repair427.july_rows is not the six lines read on 10 Oct 2026%',
    '1: lines that are not the six read (one amount wrong) refuse: ' || current_setting('t427r.wrong_rows'));
  perform pg_temp.check(current_setting('t427r.not_owner') like '427 repair: repair427.actor is not an active Owner%',
    '1: an actor who is not an Owner refuses: ' || current_setting('t427r.not_owner'));
  perform pg_temp.check(current_setting('t427r.superseded') like '427 repair: these lines are not as given or as read on 10 Oct 2026%' || pg_temp.fx('line2')::text || '%',
    '1: a superseded line refuses, naming it: ' || current_setting('t427r.superseded'));
  perform pg_temp.check(current_setting('t427r.matched') like '427 repair: 1 of the 6 lines are no longer waiting for their order%',
    '1: a line matched since refuses: ' || current_setting('t427r.matched'));
  perform pg_temp.check(not exists (select 1 from public.tiktok_settlement_reviews), '1: nothing refused was recorded');
  perform pg_temp.check(pg_temp.settled_without_order() = 6, '1: before the repair, six orders are settled with no imported order');
end $$;
\ir ../repair/427-july-orders-reviewed.sql
create temp table r1_after as select * from public.tiktok_settlement_reviews;
\ir ../repair/427-july-orders-reviewed.sql
do $$
begin
  perform pg_temp.check((select count(*) from public.tiktok_settlement_reviews r
                          where r.reviewed_by = pg_temp.fx('owner') and r.decision = 'no_stock_needed'
                            and r.reason like 'Sold before the app tracked TikTok stock%') = 6
                        and not exists (select 1 from public.tiktok_settlement_reviews where settlement_row_id = pg_temp.fx('line7')),
    '1: the six July lines are reviewed as the Owner, with the reason; the August line is not');
  perform pg_temp.check((select count(*) from public.audit_logs a where a.action = 'tiktok_settlement_reviewed_no_stock'
                          and a.changed_by = pg_temp.fx('owner') and a.module = 'tiktok_import') = 6,
    '1: one audit entry per line');
  perform pg_temp.check(not exists (select * from public.tiktok_settlement_reviews except select * from r1_after)
                        and (select count(*) from public.tiktok_settlement_reviews) = 6,
    '1: a second run changes nothing');
  perform pg_temp.check(pg_temp.settled_without_order() = 1, '1: only the 28 August order (the Owner''s "27 August" one) is still settled with no imported order');
  perform pg_temp.check((select count(*) from public.tiktok_settlement_rows where match_status = 'pending') = 7
                        and (select sum(current_qty) from public.store_inventory where store_id = pg_temp.fx('store')) = 6,
    '1: no settlement line or stock changed');
end $$;

-- ═════ 2. The 28 August order (Singapore time; the Owner's "27 August" one) ═════
savepoint a0;
select set_config('repair427.aug_row', '', true);
\set ON_ERROR_STOP off
\ir ../repair/427-take-off-27-aug-order.sql
\set ON_ERROR_STOP on
rollback to savepoint a0;
select set_config('t427r.aug_no_ids', :'LAST_ERROR_MESSAGE', true) as kept \gset
savepoint a1;
\set ON_ERROR_STOP off
\ir ../repair/427-take-off-27-aug-order.sql
\set ON_ERROR_STOP on
rollback to savepoint a1;
select set_config('t427r.no_lines', :'LAST_ERROR_MESSAGE', true) as kept \gset
savepoint a2;
select set_config('repair427.order_lines', '[{"seller_sku": "T427-SKU-SOAP", "quantity": 2, "order_status": "T427 Completed"}, {"seller_sku": "T427-UNKNOWN", "quantity": 1, "order_status": "T427 Completed"}]', true);
\set ON_ERROR_STOP off
\ir ../repair/427-take-off-27-aug-order.sql
\set ON_ERROR_STOP on
rollback to savepoint a2;
select set_config('t427r.unmatched', :'LAST_ERROR_MESSAGE', true) as kept \gset
savepoint a3;
select set_config('repair427.order_lines', '[{"seller_sku": "T427-SKU-SOAP", "quantity": 0, "order_status": "T427 Completed"}]', true);
\set ON_ERROR_STOP off
\ir ../repair/427-take-off-27-aug-order.sql
\set ON_ERROR_STOP on
rollback to savepoint a3;
select set_config('t427r.zero', :'LAST_ERROR_MESSAGE', true) as kept \gset
select set_config('repair427.order_lines', '[{"seller_sku": "T427-SKU-SOAP", "quantity": 2, "order_status": "T427 Completed"}, {"seller_sku": "T427-SKU-CORSET", "quantity": 1, "order_status": "T427 Shipped"}]', true);
-- Not yet checked against the count: it reports and changes nothing.
\ir ../repair/427-take-off-27-aug-order.sql
do $$
begin
  perform pg_temp.check(current_setting('t427r.aug_no_ids') like '427 repair: give the ids first%',
    '2: without the ids it refuses: ' || current_setting('t427r.aug_no_ids'));
  perform pg_temp.check(current_setting('t427r.no_lines') like '427 repair: give the order''s lines from Seller Center first%',
    '2: without the order''s lines it refuses: ' || current_setting('t427r.no_lines'));
  perform pg_temp.check(current_setting('t427r.unmatched') like '427 repair: these lines would not take stock off as given (T427-UNKNOWN: Unmatched SKU)%',
    '2: an unmapped SKU refuses, naming it: ' || current_setting('t427r.unmatched'));
  perform pg_temp.check(current_setting('t427r.zero') like '427 repair: each line needs a seller_sku, a whole quantity of 1 or more, and an order_status%',
    '2: a quantity of 0 refuses: ' || current_setting('t427r.zero'));
  perform pg_temp.check(not exists (select 1 from public.tiktok_import_batches where file_kind = 'order')
                        and (select current_qty from public.store_inventory where product_id = pg_temp.fx('soap')) = 5,
    '2: the check run (not yet checked against the count) changed nothing');
end $$;
savepoint r3;
select set_config('repair427.checked_against_count', 'yes', true);
update public.store_inventory set current_qty = 0 where product_id = pg_temp.fx('corset');
\set ON_ERROR_STOP off
\ir ../repair/427-take-off-27-aug-order.sql
\set ON_ERROR_STOP on
rollback to savepoint r3;
select set_config('t427r.short', :'LAST_ERROR_MESSAGE', true) as kept \gset
savepoint r4;
select set_config('repair427.checked_against_count', 'yes', true);
select public.tiktok_settlement_review_record(array[pg_temp.fx('line7')], 'T427 covered by the count', pg_temp.fx('owner'));
\set ON_ERROR_STOP off
\ir ../repair/427-take-off-27-aug-order.sql
\set ON_ERROR_STOP on
rollback to savepoint r4;
select set_config('t427r.reviewed', :'LAST_ERROR_MESSAGE', true) as kept \gset
select set_config('repair427.checked_against_count', 'yes', true);
\ir ../repair/427-take-off-27-aug-order.sql
create temp table r2_after as
  select (select count(*) from public.tiktok_import_batches where file_kind = 'order') batches,
         (select count(*) from public.stock_movements) movements,
         (select sum(current_qty) from public.store_inventory) stock;
\ir ../repair/427-take-off-27-aug-order.sql
do $$
declare b record;
begin
  perform pg_temp.check(current_setting('t427r.short') like '427 repair: Adelphi does not hold enough of T427-SKU-CORSET%',
    '2: Adelphi short of an item refuses, naming it: ' || current_setting('t427r.short'));
  perform pg_temp.check(current_setting('t427r.reviewed') like '427 repair: the settlement line was reviewed as needing no stock taken off%',
    '2: a line reviewed as needing no stock refuses: ' || current_setting('t427r.reviewed'));
  select * into b from public.tiktok_import_batches where file_kind = 'order';
  perform pg_temp.check(b.status = 'confirmed' and b.uploaded_by = pg_temp.fx('owner') and b.confirmed_by = pg_temp.fx('owner')
                        and b.file_name = 'Seller Center order T427-AUG-1 (28 Aug 2026), imported by the 427 repair',
    '2: the order is imported as one confirmed file, as the Owner, named with TikTok''s date (28 Aug 2026)');
  perform pg_temp.check((select current_qty from public.store_inventory where product_id = pg_temp.fx('soap')) = 3
                        and (select current_qty from public.store_inventory where product_id = pg_temp.fx('corset')) = 0,
    '2: its stock is taken off at Adelphi (soap 5 -> 3, corset 1 -> 0)');
  perform pg_temp.check((select count(*) from public.stock_movements m where m.movement_type = 'store_sale'
                          and m.from_store_id = pg_temp.fx('store') and m.created_by = pg_temp.fx('owner')
                          and m.notes like 'TikTok import Seller Center order T427-AUG-1%— order T427-AUG-1') = 2,
    '2: Stock History shows each item taken off, naming the order');
  perform pg_temp.check((select match_status from public.tiktok_settlement_rows where id = pg_temp.fx('line7')) = 'matched'
                        and pg_temp.settled_without_order() = 0,
    '2: the settlement line is matched and nothing is left settled with no imported order');
  perform pg_temp.check((select count(*) from public.audit_logs a where a.record_id = b.id and a.changed_by = pg_temp.fx('owner')
                          and a.action in ('tiktok_orders_staged', 'tiktok_batch_confirmed')) = 2,
    '2: the import is audited as the Owner''s');
  perform pg_temp.check((select batches from r2_after) = 1 and (select batches from r2_after) = (select count(*) from public.tiktok_import_batches where file_kind = 'order')
                        and (select movements from r2_after) = (select count(*) from public.stock_movements)
                        and (select stock from r2_after) = (select sum(current_qty) from public.store_inventory),
    '2: a second run changes nothing');
end $$;

do $$
declare v_n int; v_m text;
begin
  select count(*), string_agg(f.msg, ' | ' order by f.n) into v_n, v_m from failed f;
  if v_n > 0 then raise exception '% check(s) failed: %', v_n, v_m; end if;
  raise notice 'ALL PASS';
end $$;
rollback;
