-- 510: units received above what was sent wait for an Owner or Manager.
--
--   1 A receipt of exactly what was sent adds it all; nothing waits.
--   2 A shortfall adds what was typed, as before; nothing waits; accepting the
--     loss changes nothing.
--   3 Staff type 500 for a line of 2: the store gets 2. The line records 500
--     and +498, and 498 wait. The integrity report does not call it a receipt
--     mismatch. Staff cannot resolve it. A Manager accepts the surplus: the
--     498 are added then, with a receipt movement, and nothing waits.
--   4 Every other resolution of extra units ends with the stock it gave before
--     510: return excess, correct destination, correct source.
--   5 Resolving again adds nothing again; a second line resolved later gets its
--     own waiting units only.
--   6 Into a warehouse: the extra waits there too.
--   7 A manual line typed above what was sent changes no stock and never waits;
--     "Fill approved" (confirm all) is unchanged.
--
-- 510 is installed here when it is not in yet. Disposable local database only;
-- everything is rolled back. Every name and number is invented (X510, @example.invalid).
--   psql -X -v ON_ERROR_STOP=1 -f scripts/transfers/tests/extra-waits-510.sql
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
select position('510:' in pg_get_functiondef('public.receive_transfer(uuid,jsonb,text,boolean)'::regprocedure)) > 0 as m510_in \gset
\if :m510_in
\else
\ir ../../../supabase/510_received_extra_waits_for_a_manager.sql
\endif

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true) $$;
create function pg_temp.try(q text) returns text language plpgsql as $$
begin execute q; return 'ok'; exception when others then return sqlerrm; end $$;
create function pg_temp.wh(w text) returns int language sql as
$$ select coalesce((select current_qty from public.warehouse_inventory where warehouse_id = pg_temp.fx(w) and product_id = pg_temp.fx('p')), 0) $$;
create function pg_temp.st(s text) returns int language sql as
$$ select coalesce((select current_qty from public.store_inventory where store_id = pg_temp.fx(s) and product_id = pg_temp.fx('p')), 0) $$;
create function pg_temp.ln(line uuid) returns public.transfer_request_lines language sql as
$$ select * from public.transfer_request_lines where id = line $$;
create function pg_temp.receipts(line uuid) returns int language sql as
$$ select coalesce(sum(quantity), 0)::int from public.stock_movements where transfer_request_line_id = line and movement_type = 'transfer_receipt' $$;
create function pg_temp.mismatch(line uuid) returns boolean language sql as
$$ select exists (select 1 from public.stock_private_report_transfer_stock_integrity() i where i.line_id = line and i.issue_type = 'receipt_movement_mismatch') $$;
create function pg_temp.status(name text) returns text language sql as
$$ select status::text from public.transfer_requests where id = pg_temp.fx(name) $$;
-- A transfer of one line (product, or manual), approved and sent as qty from
-- src, kept as fx('<name>'); returns the line id. Not received yet.
create function pg_temp.sent(name text, src_type text, src_key text, dest_type text, dest_key text, qty int,
                             kind text default 'product') returns uuid language plpgsql as $$
declare r uuid; l uuid;
begin
  perform pg_temp.as_user('owner');
  r := (public.create_transfer_request(src_type || '_to_' || dest_type, src_type, pg_temp.fx(src_key), dest_type, pg_temp.fx(dest_key),
         case when kind = 'manual'
              then jsonb_build_array(jsonb_build_object('line_kind', 'manual', 'manual_item_name', 'X510 Box', 'manual_uom', 'pc', 'quantity', qty))
              else jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'quantity', qty)) end,
         'X510 ' || name) ->> 'id')::uuid;
  select id into l from public.transfer_request_lines where transfer_request_id = r;
  perform public.review_and_dispatch_transfer(r, jsonb_build_array(jsonb_build_object('line_id', l, 'approved_quantity', qty,
    'sources', case when kind = 'manual' then '[]'::jsonb
                    else jsonb_build_array(jsonb_build_object('source_type', src_type, 'source_id', pg_temp.fx(src_key), 'quantity', qty)) end)),
    'X510 dispatch');
  insert into fx values (name, r) on conflict (k) do update set v = excluded.v;
  return l;
end $$;
create function pg_temp.receive(who text, name text, line uuid, rcv int) returns jsonb language plpgsql as $$
begin
  perform pg_temp.as_user(who);
  return public.receive_transfer(pg_temp.fx(name), jsonb_build_array(jsonb_build_object('line_id', line, 'received_quantity', rcv)),
    'X510 count', false);
end $$;
create function pg_temp.resolve(who text, name text, line uuid, res text) returns jsonb language plpgsql as $$
begin
  perform pg_temp.as_user(who);
  return public.resolve_transfer_discrepancy(pg_temp.fx(name),
    jsonb_build_array(jsonb_build_object('line_id', line, 'resolution', res, 'reason', 'X510 ' || res)), null);
end $$;

-- ===== Fixture =====
do $$
declare v uuid; k text;
begin
  foreach k in array array['owner', 'manager', 'staff'] loop
    v := gen_random_uuid();
    insert into auth.users(id, email) values (v, 'x510-' || k || '@example.invalid');
    insert into public.profiles(id, full_name, email, role)
      values (v, 'X510 ' || k, 'x510-' || k || '@example.invalid', k::public.user_role);
    insert into fx values (k, v);
  end loop;
  perform pg_temp.as_user('owner');
  insert into public.stores(name, code, country_code) values ('X510 Store A', 'X510A', 'SG') returning id into v; insert into fx values ('sa', v);
  insert into public.warehouses(name, code) values ('X510 WH 1', 'X5101') returning id into v; insert into fx values ('w1', v);
  insert into public.warehouses(name, code) values ('X510 WH 2', 'X5102') returning id into v; insert into fx values ('w2', v);
  insert into public.products(name, sku, product_type) values ('X510 Pillow', 'X510-P', 'own') returning id into v; insert into fx values ('p', v);
  insert into public.store_product_prices(store_id, product_id, selling_price) values (pg_temp.fx('sa'), pg_temp.fx('p'), 10);
  insert into public.user_store_assignments(user_id, store_id) values (pg_temp.fx('staff'), pg_temp.fx('sa'));
  -- The Manager works at store A: since 533 (security audit of 17 Nov 2026, M9) a Manager resolves
  -- only for the stores they work at.
  insert into public.user_store_assignments(user_id, store_id) values (pg_temp.fx('manager'), pg_temp.fx('sa'));
  insert into public.warehouse_inventory(warehouse_id, product_id, current_qty)
  values (pg_temp.fx('w1'), pg_temp.fx('p'), 100), (pg_temp.fx('w2'), pg_temp.fx('p'), 100);
end $$;

-- ===== 1. Exact receipt =====
do $$
declare l uuid; a int := pg_temp.st('sa'); out jsonb;
begin
  l := pg_temp.sent('t1', 'warehouse', 'w1', 'store', 'sa', 5);
  out := pg_temp.receive('staff', 't1', l, 5);
  perform pg_temp.check(pg_temp.st('sa') = a + 5 and pg_temp.status('t1') = 'received'
                        and (pg_temp.ln(l)).extra_waiting_quantity = 0 and pg_temp.receipts(l) = 5
                        and (out->>'extra_waiting')::int = 0,
    '1 exactly what was sent: all 5 added, received, nothing waits');
end $$;

-- ===== 2. Shortfall =====
do $$
declare l uuid; a int := pg_temp.st('sa');
begin
  l := pg_temp.sent('t2', 'warehouse', 'w1', 'store', 'sa', 5);
  perform pg_temp.receive('staff', 't2', l, 3);
  perform pg_temp.check(pg_temp.st('sa') = a + 3 and pg_temp.status('t2') = 'received_with_discrepancy'
                        and (pg_temp.ln(l)).received_quantity = 3 and (pg_temp.ln(l)).discrepancy_quantity = -2
                        and (pg_temp.ln(l)).extra_waiting_quantity = 0 and pg_temp.receipts(l) = 3,
    '2 a shortfall: the 3 typed are added, -2 recorded, nothing waits (as before)');
  perform pg_temp.resolve('manager', 't2', l, 'accept_loss');
  perform pg_temp.check(pg_temp.st('sa') = a + 3 and pg_temp.status('t2') = 'completed',
    '2 accepting the loss changes no stock (as before)');
end $$;

-- ===== 3. Staff type 500 for 2 =====
do $$
declare l uuid; a int := pg_temp.st('sa'); out jsonb; au jsonb;
begin
  l := pg_temp.sent('t3', 'warehouse', 'w1', 'store', 'sa', 2);
  out := pg_temp.receive('staff', 't3', l, 500);
  perform pg_temp.check(pg_temp.st('sa') = a + 2, '3 Staff type 500 for a line of 2: the store gets 2');
  perform pg_temp.check((pg_temp.ln(l)).received_quantity = 500 and (pg_temp.ln(l)).discrepancy_quantity = 498
                        and (pg_temp.ln(l)).extra_waiting_quantity = 498 and pg_temp.status('t3') = 'received_with_discrepancy',
    '3 the line records 500 typed, +498, and 498 waiting');
  perform pg_temp.check(pg_temp.receipts(l) = 2 and (out->>'extra_waiting')::int = 498, '3 one receipt movement of 2; the answer says 498 wait');
  select new_data into au from public.audit_logs where record_id = pg_temp.fx('t3') and action = 'transfer_received_with_discrepancy' order by created_at desc limit 1;
  perform pg_temp.check((au->>'extra_waiting')::int = 498, '3 the receipt''s audit row says 498 wait');
  perform pg_temp.check(not pg_temp.mismatch(l), '3 the integrity report does not list a receipt mismatch while they wait');
  perform pg_temp.check(pg_temp.try(format('select pg_temp.resolve(%L, %L, %L, %L)', 'staff', 't3', l, 'accept_surplus'))
                        = 'Only Owner or Manager can resolve transfer discrepancies', '3 Staff cannot resolve it');
  perform pg_temp.check(pg_temp.st('sa') = a + 2, '3 and the store still has 2 of them');
  perform pg_temp.resolve('manager', 't3', l, 'accept_surplus');
  perform pg_temp.check(pg_temp.st('sa') = a + 500 and (pg_temp.ln(l)).extra_waiting_quantity = 0 and pg_temp.status('t3') = 'completed',
    '3 a Manager accepts the surplus: the 498 are added now and nothing waits');
  perform pg_temp.check(pg_temp.receipts(l) = 500 and not pg_temp.mismatch(l)
                        and exists (select 1 from public.stock_movements where transfer_request_line_id = l and movement_type = 'transfer_receipt'
                                      and quantity = 498 and notes like 'Transfer received: extra units added%'),
    '3 with a receipt movement of 498; receipts now match the 500 received');
  select new_data into au from public.audit_logs where record_id = l and action = 'transfer_discrepancy_resolved' order by created_at desc limit 1;
  perform pg_temp.check((au->>'extra_added')::int = 498, '3 the resolution''s audit row says 498 added');
end $$;

-- ===== 4. Other resolutions end as before 510 =====
do $$
declare l uuid; a int; w int;
begin
  -- Return excess: before 510 the destination kept what was sent and the source got the extra back.
  a := pg_temp.st('sa'); w := pg_temp.wh('w1');
  l := pg_temp.sent('t4r', 'warehouse', 'w1', 'store', 'sa', 4);
  perform pg_temp.receive('staff', 't4r', l, 6);
  perform pg_temp.check(pg_temp.st('sa') = a + 4 and pg_temp.wh('w1') = w - 4, '4 return excess: at receipt the store has 4, the source gave 4');
  perform pg_temp.resolve('manager', 't4r', l, 'return_excess');
  perform pg_temp.check(pg_temp.st('sa') = a + 4 and pg_temp.wh('w1') = w - 4 + 2 and (pg_temp.ln(l)).extra_waiting_quantity = 0,
    '4 return excess: the store ends with 4 and the source gets 2 back (as before)');
  -- Correct destination: before 510 the destination ended with what was sent.
  a := pg_temp.st('sa'); w := pg_temp.wh('w1');
  l := pg_temp.sent('t4d', 'warehouse', 'w1', 'store', 'sa', 3);
  perform pg_temp.receive('staff', 't4d', l, 5);
  perform pg_temp.resolve('manager', 't4d', l, 'correct_destination');
  perform pg_temp.check(pg_temp.st('sa') = a + 3 and pg_temp.wh('w1') = w - 3, '4 correct destination: the store ends with 3 (as before)');
  -- Correct source: before 510 the destination kept all 5 and the source gave 2 more.
  a := pg_temp.st('sa'); w := pg_temp.wh('w1');
  l := pg_temp.sent('t4s', 'warehouse', 'w1', 'store', 'sa', 3);
  perform pg_temp.receive('staff', 't4s', l, 5);
  perform pg_temp.resolve('manager', 't4s', l, 'correct_source');
  perform pg_temp.check(pg_temp.st('sa') = a + 5 and pg_temp.wh('w1') = w - 5, '4 correct source: the store ends with 5 and the source gave 5 (as before)');
end $$;

-- ===== 5. Resolving again; two lines resolved one at a time =====
do $$
declare r uuid; l1 uuid; l2 uuid; a int := pg_temp.st('sa'); p2 uuid;
begin
  perform pg_temp.as_user('owner');
  insert into public.products(name, sku, product_type) values ('X510 Towel', 'X510-T', 'own') returning id into p2;
  insert into public.store_product_prices(store_id, product_id, selling_price) values (pg_temp.fx('sa'), p2, 10);
  insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (pg_temp.fx('w1'), p2, 50);
  r := (public.create_transfer_request('warehouse_to_store', 'warehouse', pg_temp.fx('w1'), 'store', pg_temp.fx('sa'),
         jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'quantity', 2), jsonb_build_object('product_id', p2, 'quantity', 2)),
         'X510 two lines') ->> 'id')::uuid;
  select id into l1 from public.transfer_request_lines where transfer_request_id = r and product_id = pg_temp.fx('p');
  select id into l2 from public.transfer_request_lines where transfer_request_id = r and product_id = p2;
  perform public.review_and_dispatch_transfer(r, jsonb_build_array(
    jsonb_build_object('line_id', l1, 'approved_quantity', 2, 'sources', jsonb_build_array(jsonb_build_object('source_type', 'warehouse', 'source_id', pg_temp.fx('w1'), 'quantity', 2))),
    jsonb_build_object('line_id', l2, 'approved_quantity', 2, 'sources', jsonb_build_array(jsonb_build_object('source_type', 'warehouse', 'source_id', pg_temp.fx('w1'), 'quantity', 2)))),
    'X510 dispatch');
  insert into fx values ('t5', r);
  perform pg_temp.as_user('staff');
  perform public.receive_transfer(r, jsonb_build_array(jsonb_build_object('line_id', l1, 'received_quantity', 5),
                                                       jsonb_build_object('line_id', l2, 'received_quantity', 4)), 'X510 count', false);
  perform pg_temp.check(pg_temp.st('sa') = a + 2 and (select current_qty from public.store_inventory where store_id = pg_temp.fx('sa') and product_id = p2) = 2,
    '5 two lines with extra: each adds its 2 at receipt');
  perform pg_temp.resolve('manager', 't5', l1, 'accept_surplus');
  perform pg_temp.check(pg_temp.st('sa') = a + 5 and pg_temp.status('t5') = 'received_with_discrepancy'
                        and (pg_temp.ln(l2)).extra_waiting_quantity = 2,
    '5 the first line resolved: its 3 are added; the second still waits');
  perform pg_temp.as_user('manager');
  perform public.resolve_transfer_discrepancy(r, jsonb_build_array(
    jsonb_build_object('line_id', l1, 'resolution', 'accept_surplus'), jsonb_build_object('line_id', l2, 'resolution', 'accept_surplus')), null);
  perform pg_temp.check(pg_temp.st('sa') = a + 5 and (select current_qty from public.store_inventory where store_id = pg_temp.fx('sa') and product_id = p2) = 4
                        and pg_temp.status('t5') = 'completed',
    '5 resolving both: the first adds nothing again, the second adds its 2');
  perform pg_temp.check(pg_temp.try(format('select pg_temp.resolve(%L, %L, %L, %L)', 'manager', 't5', l1, 'accept_surplus'))
                        = 'This transfer has no unresolved receipt discrepancy' and pg_temp.st('sa') = a + 5,
    '5 a third call is refused and adds nothing');
end $$;

-- ===== 6. Into a warehouse =====
do $$
declare l uuid; w int := pg_temp.wh('w2');
begin
  l := pg_temp.sent('t6', 'warehouse', 'w1', 'warehouse', 'w2', 3);
  perform pg_temp.receive('owner', 't6', l, 7);
  perform pg_temp.check(pg_temp.wh('w2') = w + 3 and (pg_temp.ln(l)).extra_waiting_quantity = 4, '6 a warehouse gets the 3 sent; 4 wait');
  perform pg_temp.resolve('owner', 't6', l, 'accept_surplus');
  perform pg_temp.check(pg_temp.wh('w2') = w + 7 and (pg_temp.ln(l)).extra_waiting_quantity = 0, '6 accepted: the 4 are added');
end $$;

-- ===== 7. Manual lines; Fill approved =====
do $$
declare l uuid; a int := pg_temp.st('sa'); n int := (select count(*) from public.stock_movements);
begin
  l := pg_temp.sent('t7m', 'warehouse', 'w1', 'store', 'sa', 2, 'manual');
  perform pg_temp.receive('staff', 't7m', l, 9);
  perform pg_temp.check((pg_temp.ln(l)).received_quantity = 9 and (pg_temp.ln(l)).discrepancy_quantity = 7
                        and (pg_temp.ln(l)).extra_waiting_quantity = 0 and pg_temp.st('sa') = a
                        and (select count(*) from public.stock_movements) = n,
    '7 a manual line typed 9 for 2: recorded, no stock, nothing waits');
  perform pg_temp.resolve('manager', 't7m', l, 'accept_surplus');
  perform pg_temp.check(pg_temp.st('sa') = a and pg_temp.status('t7m') = 'completed', '7 and accepting it changes no stock');
  l := pg_temp.sent('t7a', 'warehouse', 'w1', 'store', 'sa', 6);
  perform pg_temp.as_user('staff');
  perform public.receive_transfer(pg_temp.fx('t7a'), null, null, true);
  perform pg_temp.check(pg_temp.st('sa') = a + 6 and pg_temp.status('t7a') = 'received' and (pg_temp.ln(l)).extra_waiting_quantity = 0,
    '7 Fill approved receives the 6 sent, as before');
end $$;

rollback;
