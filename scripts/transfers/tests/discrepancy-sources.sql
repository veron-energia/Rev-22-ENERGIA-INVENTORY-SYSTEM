-- 421: a transfer discrepancy is resolved where the line came from.
--
-- Before 421, "Correct source stock" and "Return excess to source" moved
-- stock at the transfer's header source, though an approver may send a line
-- from somewhere else (STOCK-M2); taking extra units off a place that had
-- sold them failed with a stock-rule or check-constraint error (STOCK-11);
-- "Create linked inventory adjustment" on extra units wrote a movement of
-- units that never arrived; an edit could not clear a transfer's note
-- (STOCK-14 item 2); and a staff request with no store went to the first
-- store a two-store person was assigned to (STOCK-1). Section 1 reproduces
-- these on the functions as they are; each part runs only while its function
-- is still at the BEFORE md5 (a database without 421). Section 2 applies 421
-- (twice), and checks it refuses a changed function, another overload of one,
-- and a relied-on function at another version; it runs only while one of
-- 421's functions is still at BEFORE. Section 3 checks the rules, so a
-- database that already has 421 (or 430 after it) goes straight there.
--
-- Disposable local database only; everything is rolled back. The migration
-- is applied inside this transaction, so run the file on its own:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/transfers/tests/discrepancy-sources.sql
-- On a local database that has drifted from production, pass a file that
-- installs production's functions, run right after the begin below:
--   psql -X -v ON_ERROR_STOP=1 -v prelude=/path/to/prod_prelude.sql -f ...
-- Every name and number is invented (DSX fixtures, @sig.invalid).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
-- The error a call raises, or null when it succeeds; rolled back either way.
create function pg_temp.refused(q text) returns text language plpgsql as $$
begin
  begin
    execute q;
    raise exception 'T421: accepted';
  exception when others then
    if sqlerrm = 'T421: accepted' then return null; end if;
    return sqlerrm;
  end;
end $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true) $$;
create function pg_temp.wh(w text) returns int language sql as
$$ select coalesce((select current_qty from public.warehouse_inventory where warehouse_id = pg_temp.fx(w) and product_id = pg_temp.fx('p')), 0) $$;
create function pg_temp.st(s text) returns int language sql as
$$ select coalesce((select current_qty from public.store_inventory where store_id = pg_temp.fx(s) and product_id = pg_temp.fx('p')), 0) $$;
-- A transfer into dest, one product line, sent from the sources given
-- ([{type,key,qty}]), then received as rcv. Returns the line id; the request
-- id is kept as fx('<name>').
create function pg_temp.sent(name text, src_type text, src_key text, dest_type text, dest_key text, qty int,
                             sources jsonb, rcv int, kind text default 'product') returns uuid language plpgsql as $$
declare r uuid; l uuid; s jsonb := '[]'::jsonb; e jsonb;
begin
  perform pg_temp.as_user('owner');
  r := (public.create_transfer_request(src_type || '_to_' || dest_type, src_type, pg_temp.fx(src_key), dest_type, pg_temp.fx(dest_key),
         case when kind = 'manual'
              then jsonb_build_array(jsonb_build_object('line_kind', 'manual', 'manual_item_name', 'DSX Box', 'manual_uom', 'pc', 'quantity', qty))
              else jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'quantity', qty)) end,
         'DSX ' || name) ->> 'id')::uuid;
  select id into l from public.transfer_request_lines where transfer_request_id = r;
  for e in select * from jsonb_array_elements(sources) loop
    s := s || jsonb_build_array(jsonb_build_object('source_type', e->>'type', 'source_id', pg_temp.fx(e->>'key'), 'quantity', (e->>'qty')::int));
  end loop;
  perform public.review_and_dispatch_transfer(r, jsonb_build_array(jsonb_build_object('line_id', l, 'approved_quantity', qty,
    'sources', case when kind = 'manual' then '[]'::jsonb else s end)), 'DSX dispatch');
  perform public.receive_transfer(r, jsonb_build_array(jsonb_build_object('line_id', l, 'received_quantity', rcv)),
    case when rcv <> qty then 'DSX count differs' end, false);
  insert into fx values (name, r) on conflict (k) do update set v = excluded.v;
  return l;
end $$;
create function pg_temp.resolve(name text, line uuid, res text, reason text default null) returns jsonb language sql as
$$ select public.resolve_transfer_discrepancy(pg_temp.fx(name),
     jsonb_build_array(jsonb_build_object('line_id', line, 'resolution', res, 'reason', reason)), null) $$;

-- ===== Fixture =====
do $$
declare tag text := substr(md5(random()::text), 1, 6); v uuid;
begin
  foreach v in array array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid()] loop
    insert into auth.users(id, email) values (v, 'dsx-' || v || '@sig.invalid');
  end loop;
  insert into fx select x.k, u.id from (select id, row_number() over (order by email) n from auth.users where email like 'dsx-%@sig.invalid') u
    join (values (1, 'owner'), (2, 'manager'), (3, 'staff2'), (4, 'staff1'), (5, 'staff0')) x(n, k) on x.n = u.n;
  insert into public.profiles(id, full_name, email, role)
  select fx.v, 'DSX ' || fx.k, 'dsx-' || fx.v || '@sig.invalid',
         (case fx.k when 'owner' then 'owner' when 'manager' then 'manager' else 'staff' end)::public.user_role
    from fx;
  insert into public.stores(name, code, country_code) values ('DSX Store A ' || tag, 'DSXA' || tag, 'SG') returning id into v; insert into fx values ('sa', v);
  insert into public.stores(name, code, country_code) values ('DSX Store B ' || tag, 'DSXB' || tag, 'SG') returning id into v; insert into fx values ('sb', v);
  insert into public.stores(name, code, country_code, deleted_at) values ('DSX Store Gone ' || tag, 'DSXG' || tag, 'SG', now()) returning id into v; insert into fx values ('sgone', v);
  insert into public.warehouses(name, code) values ('DSX WH 1 ' || tag, 'DSX1' || tag) returning id into v; insert into fx values ('w1', v);
  insert into public.warehouses(name, code) values ('DSX WH 2 ' || tag, 'DSX2' || tag) returning id into v; insert into fx values ('w2', v);
  insert into public.warehouses(name, code) values ('DSX WH 3 ' || tag, 'DSX3' || tag) returning id into v; insert into fx values ('w3', v);
  insert into public.products(name, sku, product_type) values ('DSX Pillow', 'DSX-P-' || tag, 'own') returning id into v; insert into fx values ('p', v);
  insert into public.store_product_prices(store_id, product_id, selling_price)
  values (pg_temp.fx('sa'), pg_temp.fx('p'), 10), (pg_temp.fx('sb'), pg_temp.fx('p'), 10);
  -- staff2 works at A and B; staff1 at A only, and at a store since deleted
  -- (assigned to it first); staff0 nowhere.
  insert into public.user_store_assignments(user_id, store_id, created_at)
  values (pg_temp.fx('staff2'), pg_temp.fx('sa'), now() - interval '2 days'), (pg_temp.fx('staff2'), pg_temp.fx('sb'), now() - interval '1 day'),
         (pg_temp.fx('staff1'), pg_temp.fx('sgone'), now() - interval '3 days'), (pg_temp.fx('staff1'), pg_temp.fx('sa'), now());
  insert into public.warehouse_inventory(warehouse_id, product_id, current_qty)
  values (pg_temp.fx('w1'), pg_temp.fx('p'), 100), (pg_temp.fx('w2'), pg_temp.fx('p'), 100), (pg_temp.fx('w3'), pg_temp.fx('p'), 100);
  insert into public.store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('sb'), pg_temp.fx('p'), 50);
end $$;

-- ===== 1. Before 421: the defects (only on a database without 421) =====
savepoint before421;
do $$
declare l uuid; r uuid; msg text;
  v_res boolean := md5(pg_get_functiondef('public.resolve_transfer_discrepancy(uuid,jsonb,text)'::regprocedure))
                   = '8b387cbec43f41fc64406ed3a901c7cb';
  v_edit boolean := md5(pg_get_functiondef('public.edit_transfer_request(uuid,integer,text,location_type,uuid,location_type,uuid,jsonb,text)'::regprocedure))
                    = 'b150a0ce6de9584ef344e6ee1730a66b';
  v_staff boolean := md5(pg_get_functiondef('public.create_staff_transfer_request(jsonb,text,uuid)'::regprocedure))
                     = '1dd8c2ee3e45c340c0378d4f61338b07';
begin
  if not (v_res or v_edit or v_staff) then
    raise notice 'SKIP  section 1: this database already has 421'; return; end if;
  if not v_res then
    raise notice 'SKIP  section 1, resolving: resolve_transfer_discrepancy is past its BEFORE version';
  else
    -- header W1, the line sent from W2, two short: "Correct source" credits W1
    l := pg_temp.sent('t1', 'warehouse', 'w1', 'store', 'sa', 5, '[{"type":"warehouse","key":"w2","qty":5}]', 3);
    perform pg_temp.resolve('t1', l, 'correct_source');
    perform pg_temp.check(pg_temp.wh('w1') = 102 and pg_temp.wh('w2') = 95,
      'before 421: Correct source gave the header warehouse units it never sent (W1 102, W2 95)');
    -- two extra at store A, all but one sold: a stock-rule error
    l := pg_temp.sent('t2', 'warehouse', 'w1', 'store', 'sa', 2, '[{"type":"warehouse","key":"w2","qty":2}]', 4);
    update public.store_inventory set current_qty = 1 where store_id = pg_temp.fx('sa') and product_id = pg_temp.fx('p');
    msg := pg_temp.refused(format('select pg_temp.resolve(%L, %L, %L)', 't2', l, 'return_excess'));
    perform pg_temp.check(msg like 'Stock cannot go negative%', 'before 421: Return excess on sold units fails with the stock rule: ' || msg);
    -- the adjustment on extra units writes a movement of units that never came
    update public.store_inventory set current_qty = 7 where store_id = pg_temp.fx('sa') and product_id = pg_temp.fx('p');
    perform pg_temp.resolve('t2', l, 'inventory_adjustment', 'counted');
    perform pg_temp.check(pg_temp.st('sa') = 7 and exists (select 1 from public.stock_movements x where x.transfer_request_line_id = l
        and x.movement_type = 'inventory_adjustment' and x.quantity = 2),
      'before 421: the adjustment on extra units changed no stock but wrote 2 units arriving');
  end if;
  if not v_edit then
    raise notice 'SKIP  section 1, the note: edit_transfer_request is past its BEFORE version';
  else
    -- a note of spaces is kept as spaces (the page sent null for an empty note,
    -- so the old note stayed)
    perform pg_temp.as_user('owner');
    insert into fx values ('t3', (public.create_transfer_request('warehouse_to_store', 'warehouse', pg_temp.fx('w1'), 'store', pg_temp.fx('sa'),
      jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'quantity', 1)), 'DSX old note') ->> 'id')::uuid);
    perform public.edit_transfer_request(pg_temp.fx('t3'), null, 'clear it', null, null, null, null, null, '   ');
    perform pg_temp.check((select note from public.transfer_requests where id = pg_temp.fx('t3')) = '   ',
      'before 421: a note of spaces is stored as it is, not cleared');
  end if;
  if not v_staff then
    raise notice 'SKIP  section 1, the store: create_staff_transfer_request is past its BEFORE version';
  else
    -- a two-store member of staff with no store: the first store they were given
    perform pg_temp.as_user('staff2');
    r := (public.create_staff_transfer_request(jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'quantity', 1)), null, null) ->> 'id')::uuid;
    perform pg_temp.check((select dest_id from public.transfer_requests where id = r) = pg_temp.fx('sa'),
      'before 421: a two-store request with no store went to the first store');
  end if;
end $$;
rollback to savepoint before421;
release savepoint before421;

-- ===== 2. Apply 421; a re-run changes nothing; the guards refuse =====
-- Only while one of 421's functions is still at its BEFORE md5. After 421 (or
-- 430, which changes is_owner_or_manager() and so makes 421 refuse), the
-- rules are checked on the database as it is.
select md5(pg_get_functiondef('public.resolve_transfer_discrepancy(uuid,jsonb,text)'::regprocedure)) = '8b387cbec43f41fc64406ed3a901c7cb'
    or md5(pg_get_functiondef('public.edit_transfer_request(uuid,integer,text,location_type,uuid,location_type,uuid,jsonb,text)'::regprocedure)) = 'b150a0ce6de9584ef344e6ee1730a66b'
    or md5(pg_get_functiondef('public.create_staff_transfer_request(jsonb,text,uuid)'::regprocedure)) = '1dd8c2ee3e45c340c0378d4f61338b07'
    or md5(pg_get_functiondef('public.stock_history_table(jsonb,integer,integer,timestamp with time zone)'::regprocedure)) = '52c71fac2ccaa5b6e580476871555fae'
    or md5(pg_get_functiondef('public.stock_private_report_transfer_stock_integrity()'::regprocedure)) = 'b9980473a9722b64094ddfd5413fea23'
    as t421_needed \gset
\if :t421_needed
select set_config('request.jwt.claim.sub', '', true) as t421_cleared \gset
\ir ../../../supabase/421_transfer_discrepancies_and_stock_history.sql
create temp table t421_after as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5,
         coalesce(array_to_string(p.proacl, ','), '') as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace;
\ir ../../../supabase/421_transfer_discrepancies_and_stock_history.sql
do $$
begin
  perform pg_temp.check(not exists (
      select fn, md5, acl from t421_after
      except select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)), coalesce(array_to_string(p.proacl, ','), '')
               from pg_proc p where p.pronamespace = 'public'::regnamespace)
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace) = (select count(*) from t421_after),
    '2: a second run of 421 changes no function or grant');
  perform pg_temp.check(
    (select md5 from t421_after where fn = 'resolve_transfer_discrepancy(uuid,jsonb,text)') = '9b526acc4fbf00839c9ef4acd5af7856'
    and (select md5 from t421_after where fn = 'edit_transfer_request(uuid,integer,text,location_type,uuid,location_type,uuid,jsonb,text)') = 'd9cec0b343afaea0171952cbcda80b61'
    and (select md5 from t421_after where fn = 'stock_private_report_transfer_stock_integrity()') = '7e7d4acdae67439d64079dbe357ad971'
    and not has_function_privilege('authenticated', 'public.stock_private_report_transfer_stock_integrity()', 'execute')
    and has_function_privilege('authenticated', 'public.resolve_transfer_discrepancy(uuid,jsonb,text)', 'execute')
    and not has_function_privilege('anon', 'public.resolve_transfer_discrepancy(uuid,jsonb,text)', 'execute'),
    '2: installed at the AFTER md5s, grants as they were');
  perform pg_temp.check(not exists (select 1 from auth.users where email like '421-check-%')
    and not exists (select 1 from public.stores where name like '421 check %'),
    '2: the migration''s own check left no row');
end $$;
-- A function 421 changes, at a version it was not tested against (another
-- batch changed it): refused, not overwritten.
\set LAST_ERROR_MESSAGE ''
savepoint t421_guard0;
do $$
begin
  execute regexp_replace(pg_get_functiondef('public.resolve_transfer_discrepancy(uuid,jsonb,text)'::regprocedure),
    '\$function\$', E'$function$\n-- T421 another version\n');
end $$;
\set ON_ERROR_STOP off
\ir ../../../supabase/421_transfer_discrepancies_and_stock_history.sql
\set ON_ERROR_STOP on
rollback to savepoint t421_guard0;
release savepoint t421_guard0;
select set_config('t421.refused_changed', :'LAST_ERROR_MESSAGE', true) as t421_kept0 \gset
-- Another overload of a function 421 changes: refused.
\set LAST_ERROR_MESSAGE ''
savepoint t421_guard1;
create function public.resolve_transfer_discrepancy(p uuid) returns void language plpgsql as $f$ begin end $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/421_transfer_discrepancies_and_stock_history.sql
\set ON_ERROR_STOP on
rollback to savepoint t421_guard1;
release savepoint t421_guard1;
select set_config('t421.refused_overload', :'LAST_ERROR_MESSAGE', true) as t421_kept1 \gset
-- A function 421 relies on, at another version: refused.
\set LAST_ERROR_MESSAGE ''
savepoint t421_guard;
create or replace function public.stock_history_location_name(p_kind text, p_id uuid) returns text language sql stable
  security definer set search_path = public as $f$ select 'x'::text $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/421_transfer_discrepancies_and_stock_history.sql
\set ON_ERROR_STOP on
rollback to savepoint t421_guard;
release savepoint t421_guard;
select set_config('t421.refused_relied', :'LAST_ERROR_MESSAGE', true) as t421_kept \gset
do $$
begin
  perform pg_temp.check(current_setting('t421.refused_changed')
      like '421: public.resolve_transfer_discrepancy(uuid,jsonb,text) is not the version this was tested against%',
    '2: a changed function at another version refuses: ' || current_setting('t421.refused_changed'));
  perform pg_temp.check(current_setting('t421.refused_overload') = '421: another overload of a function this changes exists',
    '2: another overload of a changed function refuses: ' || current_setting('t421.refused_overload'));
  perform pg_temp.check(current_setting('t421.refused_relied') like '%stock_history_location_name(text,uuid) is missing or not the version%',
    '2: a relied-on function at another version refuses: ' || current_setting('t421.refused_relied'));
end $$;
\else
do $$ begin raise notice 'SKIP  section 2: this database already has 421'; end $$;
\endif

-- ===== 3. The rules =====
do $$
declare l uuid; msg text; mv uuid; n int;
begin
  perform set_config('request.jwt.claim.sub', '', true);

  -- Rule 1: header W1, the line sent from W2. Two short: W2 gets them back.
  l := pg_temp.sent('a1', 'warehouse', 'w1', 'store', 'sa', 5, '[{"type":"warehouse","key":"w2","qty":5}]', 3);
  perform pg_temp.check(pg_temp.wh('w2') = 95 and pg_temp.wh('w1') = 100 and pg_temp.st('sa') = 3, '1: sent from W2, three arrived');
  perform pg_temp.resolve('a1', l, 'correct_source');
  select id into mv from public.stock_movements where transfer_request_line_id = l and notes = 'Discrepancy: corrected source';
  perform pg_temp.check(pg_temp.wh('w2') = 97 and pg_temp.wh('w1') = 100,
    '1: Correct source puts the two missing units back at W2, where the line came from; W1 is untouched');
  perform pg_temp.check((select from_warehouse_id from public.stock_movements where id = mv) = pg_temp.fx('w2')
    and public.stock_history_effect(mv, 'warehouse:' || pg_temp.fx('w2')) = 2
    and public.stock_history_effect(mv, 'warehouse:' || pg_temp.fx('w1')) = 0,
    '1: its movement is from W2, and Stock History scores +2 at W2 and nothing at W1');
  perform pg_temp.check((select new_data->>'source_id' from public.audit_logs where record_id = l and action = 'transfer_discrepancy_resolved')
    = pg_temp.fx('w2')::text, '1: the audit row names the source used');
  perform pg_temp.check((select status::text from public.transfer_requests where id = pg_temp.fx('a1')) = 'completed', '1: the transfer completes');

  -- Rule 1: two extra; Return excess sends them back to W2.
  l := pg_temp.sent('a2', 'warehouse', 'w1', 'store', 'sa', 2, '[{"type":"warehouse","key":"w2","qty":2}]', 4);
  perform pg_temp.check(pg_temp.st('sa') = 7 and pg_temp.wh('w2') = 95, '1: two extra arrived at A');
  perform pg_temp.resolve('a2', l, 'return_excess');
  select id into mv from public.stock_movements where transfer_request_line_id = l and notes = 'Discrepancy: returned excess to source';
  perform pg_temp.check(pg_temp.st('sa') = 5 and pg_temp.wh('w2') = 97 and pg_temp.wh('w1') = 100,
    '1: Return excess takes the two off A and gives them back to W2, not W1');
  perform pg_temp.check((select (from_store_id, to_warehouse_id) from public.stock_movements where id = mv) = (pg_temp.fx('sa'), pg_temp.fx('w2'))
    and public.stock_history_effect(mv, 'store:' || pg_temp.fx('sa')) = -2
    and public.stock_history_effect(mv, 'warehouse:' || pg_temp.fx('w2')) = 2,
    '1: its movement is A to W2, scored -2 at A and +2 at W2');

  -- Rule 1: Correct source on extra units takes them off the line's source.
  l := pg_temp.sent('a3', 'warehouse', 'w1', 'store', 'sa', 2, '[{"type":"warehouse","key":"w2","qty":2}]', 3);
  perform pg_temp.resolve('a3', l, 'correct_source');
  perform pg_temp.check(pg_temp.wh('w2') = 94 and pg_temp.wh('w1') = 100 and pg_temp.st('sa') = 8,
    '1: Correct source on one extra unit takes it off W2 (the line''s source), the store keeps it');

  -- Rule 1: a line from two places: these two refused, the others work.
  l := pg_temp.sent('a4', 'warehouse', 'w1', 'store', 'sa', 2,
         '[{"type":"warehouse","key":"w1","qty":1},{"type":"warehouse","key":"w2","qty":1}]', 1);
  msg := pg_temp.refused(format('select pg_temp.resolve(%L, %L, %L)', 'a4', l, 'correct_source'));
  perform pg_temp.check(msg = 'This line came from several places; accept it, or record an adjustment at the right place',
    '1: Correct source on a line from two places is refused: ' || coalesce(msg, 'accepted'));
  perform pg_temp.resolve('a4', l, 'accept_loss', 'DSX lost on the way');
  perform pg_temp.check((select status::text from public.transfer_requests where id = pg_temp.fx('a4')) = 'completed',
    '1: it can still be accepted as a loss');
  l := pg_temp.sent('a5', 'warehouse', 'w1', 'store', 'sa', 2,
         '[{"type":"warehouse","key":"w1","qty":1},{"type":"warehouse","key":"w2","qty":1}]', 3);
  msg := pg_temp.refused(format('select pg_temp.resolve(%L, %L, %L)', 'a5', l, 'return_excess'));
  perform pg_temp.check(msg like 'This line came from several places%', '1: Return excess on a line from two places is refused');

  -- Rule 1: a line with no allocation (before allocations) uses the header.
  l := pg_temp.sent('a6', 'warehouse', 'w3', 'store', 'sa', 2, '[{"type":"warehouse","key":"w2","qty":2}]', 1);
  delete from public.transfer_line_sources where line_id = l;
  perform pg_temp.resolve('a6', l, 'correct_source');
  perform pg_temp.check(pg_temp.wh('w3') = 101, '1: a line with no allocation is corrected at the header source, as before');
  -- ... and with no header source either, both are refused.
  l := pg_temp.sent('a7', 'warehouse', 'w3', 'store', 'sa', 2, '[{"type":"warehouse","key":"w2","qty":2}]', 3);
  delete from public.transfer_line_sources where line_id = l;
  update public.transfer_requests set source_type = null, source_id = null where id = pg_temp.fx('a7');
  msg := pg_temp.refused(format('select pg_temp.resolve(%L, %L, %L)', 'a7', l, 'return_excess'));
  perform pg_temp.check(msg like 'This line has no recorded source%',
    '1: Return excess with no source anywhere is refused (it used to take the units off the store with no movement): ' || coalesce(msg, 'accepted'));

  -- Rule 2: extra units already sold at a store: a plain message.
  l := pg_temp.sent('b1', 'warehouse', 'w1', 'store', 'sa', 2, '[{"type":"warehouse","key":"w2","qty":2}]', 5);
  update public.store_inventory set current_qty = 1 where store_id = pg_temp.fx('sa') and product_id = pg_temp.fx('p');
  msg := pg_temp.refused(format('select pg_temp.resolve(%L, %L, %L)', 'b1', l, 'return_excess'));
  perform pg_temp.check(msg like 'Only 1 of the 3 extra units are still at DSX Store A %. Accept the extra as surplus, or record a stock adjustment there.',
    '2: Return excess on sold units says how many are left: ' || coalesce(msg, 'accepted'));
  msg := pg_temp.refused(format('select pg_temp.resolve(%L, %L, %L)', 'b1', l, 'correct_destination'));
  perform pg_temp.check(msg like 'Only 1 of the 3 extra units are still at DSX Store A %', '2: so does Correct destination');
  perform set_config('energia.tiktok_negative', 'allow', true);
  update public.store_inventory set current_qty = -2 where store_id = pg_temp.fx('sa') and product_id = pg_temp.fx('p');
  perform set_config('energia.tiktok_negative', '', true);
  msg := pg_temp.refused(format('select pg_temp.resolve(%L, %L, %L)', 'b1', l, 'return_excess'));
  perform pg_temp.check(msg like 'Only 0 of the 3 extra units are still at DSX Store A %', '2: below zero (TikTok) reads as 0 left');
  update public.store_inventory set current_qty = 10 where store_id = pg_temp.fx('sa') and product_id = pg_temp.fx('p');
  perform pg_temp.resolve('b1', l, 'accept_surplus');
  perform pg_temp.check(pg_temp.st('sa') = 10, '2: accepting them as surplus still works');
  -- at a warehouse: a plain message, not the check constraint
  l := pg_temp.sent('b2', 'warehouse', 'w1', 'warehouse', 'w3', 2, '[{"type":"warehouse","key":"w2","qty":2}]', 4);
  update public.warehouse_inventory set current_qty = 1 where warehouse_id = pg_temp.fx('w3') and product_id = pg_temp.fx('p');
  msg := pg_temp.refused(format('select pg_temp.resolve(%L, %L, %L)', 'b2', l, 'return_excess'));
  perform pg_temp.check(msg like 'Only 1 of the 2 extra units are still at DSX WH 3 %', '2: at a warehouse too: ' || coalesce(msg, 'accepted'));
  -- the line's source no longer holds the extra units Correct source would take
  update public.warehouse_inventory set current_qty = 1 where warehouse_id = pg_temp.fx('w2') and product_id = pg_temp.fx('p');
  msg := pg_temp.refused(format('select pg_temp.resolve(%L, %L, %L)', 'b2', l, 'correct_source'));
  perform pg_temp.check(msg like 'DSX WH 2 % holds only 1, so the 2 extra units cannot be taken off there.%',
    '2: Correct source names the source that holds too few: ' || coalesce(msg, 'accepted'));
  update public.warehouse_inventory set current_qty = 50 where warehouse_id = pg_temp.fx('w2') and product_id = pg_temp.fx('p');
  update public.warehouse_inventory set current_qty = 50 where warehouse_id = pg_temp.fx('w3') and product_id = pg_temp.fx('p');

  -- Rule 3: the adjustment adds missing units, and is refused on extra ones.
  msg := pg_temp.refused(format('select pg_temp.resolve(%L, %L, %L)', 'b2', l, 'inventory_adjustment'));
  perform pg_temp.check(msg like 'A linked inventory adjustment only adds missing units.%', '3: no adjustment on extra units');
  perform pg_temp.check(not exists (select 1 from public.stock_movements where transfer_request_line_id = l and movement_type = 'inventory_adjustment'),
    '3: and no movement was written');
  l := pg_temp.sent('b3', 'warehouse', 'w1', 'store', 'sa', 3, '[{"type":"warehouse","key":"w1","qty":3}]', 1);
  perform pg_temp.resolve('b3', l, 'inventory_adjustment', 'found in the back room');
  perform pg_temp.check(pg_temp.st('sa') = 13 and exists (select 1 from public.stock_movements where transfer_request_line_id = l
      and movement_type = 'inventory_adjustment' and quantity = 2 and notes like 'Discrepancy: linked inventory adjustment (found in the back room)'),
    '3: on two missing units it adds them at the store, as before');

  -- Manual lines stay acknowledgement-only.
  l := pg_temp.sent('c1', 'warehouse', 'w1', 'store', 'sa', 2, '[]', 3, 'manual');
  msg := pg_temp.refused(format('select pg_temp.resolve(%L, %L, %L)', 'c1', l, 'return_excess'));
  perform pg_temp.check(msg like 'Manual/non-inventory discrepancies are acknowledgement-only%', 'manual lines are acknowledgement-only, as before');

  -- Only an Owner or Manager resolves (unchanged).
  l := pg_temp.sent('c2', 'warehouse', 'w1', 'store', 'sa', 2, '[{"type":"warehouse","key":"w1","qty":2}]', 1);
  perform pg_temp.as_user('staff2');
  msg := pg_temp.refused(format('select pg_temp.resolve(%L, %L, %L)', 'c2', l, 'accept_loss'));
  perform pg_temp.check(msg = 'Only Owner or Manager can resolve transfer discrepancies', 'Staff still cannot resolve');
  perform pg_temp.as_user('manager');
  n := pg_temp.wh('w1');
  perform pg_temp.resolve('c2', l, 'correct_source');
  perform pg_temp.check(pg_temp.wh('w1') = n + 1, 'a Manager resolves (one unit back at W1)');
end $$;

-- Rule 4: the note.
do $$
declare r uuid; msg text;
begin
  perform pg_temp.as_user('owner');
  r := (public.create_transfer_request('warehouse_to_store', 'warehouse', pg_temp.fx('w1'), 'store', pg_temp.fx('sa'),
         jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'quantity', 1)), 'DSX keep me') ->> 'id')::uuid;
  perform public.edit_transfer_request(r, null, 'no note sent', null, null, null, null, null, null);
  perform pg_temp.check((select note from public.transfer_requests where id = r) = 'DSX keep me', '4: a note left out is kept');
  perform public.edit_transfer_request(r, null, 'same note, spaces', null, null, null, null, null, '  DSX keep me ');
  perform pg_temp.check((select note from public.transfer_requests where id = r) = 'DSX keep me'
    and not ((select changed_summary from public.transfer_request_revisions where transfer_request_id = r and reason = 'same note, spaces') ? 'note'),
    '4: the same note with spaces round it is not a change');
  perform public.edit_transfer_request(r, null, 'same note, tabs', null, null, null, null, null, E'\tDSX keep me \n');
  perform pg_temp.check((select note from public.transfer_requests where id = r) = 'DSX keep me'
    and not ((select changed_summary from public.transfer_request_revisions where transfer_request_id = r and reason = 'same note, tabs') ? 'note'),
    '4: the same note with tabs and a line break round it is not a change');
  perform public.edit_transfer_request(r, null, 'new note', null, null, null, null, null, '  DSX new  ');
  perform pg_temp.check((select note from public.transfer_requests where id = r) = 'DSX new', '4: a new note replaces it, trimmed');
  perform public.edit_transfer_request(r, null, 'newer note', null, null, null, null, null, E'\t DSX newer\r\n');
  perform pg_temp.check((select note from public.transfer_requests where id = r) = 'DSX newer'
    and (select changed_summary->'note' from public.transfer_request_revisions where transfer_request_id = r and reason = 'newer note')
        = jsonb_build_object('from', 'DSX new', 'to', 'DSX newer'),
    '4: a new note with tabs and line breaks round it is stored without them');
  perform public.edit_transfer_request(r, null, 'clear it', null, null, null, null, null, '');
  perform pg_temp.check((select note from public.transfer_requests where id = r) is null
    and (select changed_summary->'note' from public.transfer_request_revisions where transfer_request_id = r and reason = 'clear it')
        = jsonb_build_object('from', 'DSX newer', 'to', null),
    '4: an empty note clears it, and the edit history says so');
  perform public.edit_transfer_request(r, null, 'spaces only', null, null, null, null, null, 'x');
  perform public.edit_transfer_request(r, null, 'spaces only 2', null, null, null, null, null, E' \t\n ');
  perform pg_temp.check((select note from public.transfer_requests where id = r) is null, '4: a note of spaces, tabs and line breaks clears it');
  -- a return keeps its required reason
  r := (public.create_transfer_request('store_to_warehouse', 'store', pg_temp.fx('sb'), 'warehouse', pg_temp.fx('w1'),
         jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'quantity', 1)), 'DSX overstock') ->> 'id')::uuid;
  msg := pg_temp.refused(format('select public.edit_transfer_request(%L, null, %L, null, null, null, null, null, %L)', r, 'clear', ''));
  perform pg_temp.check(msg like '%reason for returning%', '4: a return''s reason still cannot be cleared');
  -- Staff can clear the note of their own request
  perform pg_temp.as_user('staff1');
  r := (public.create_staff_transfer_request(jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'quantity', 1)), 'DSX staff note', pg_temp.fx('sa')) ->> 'id')::uuid;
  perform public.edit_transfer_request(r, null, 'clear mine', null, null, null, null, null, '');
  perform pg_temp.check((select note from public.transfer_requests where id = r) is null, '4: staff clear the note of their own request');
end $$;

-- Rule 5: staff with two stores choose one.
do $$
declare r uuid; msg text;
begin
  perform pg_temp.as_user('staff2');
  msg := pg_temp.refused($q$select public.create_staff_transfer_request(jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'quantity', 1)), null, null)$q$);
  perform pg_temp.check(msg = 'Choose which store this request is for.', '5: two stores and none chosen: asked to choose: ' || coalesce(msg, 'accepted'));
  r := (public.create_staff_transfer_request(jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'quantity', 1)), null, pg_temp.fx('sb')) ->> 'id')::uuid;
  perform pg_temp.check((select dest_id from public.transfer_requests where id = r) = pg_temp.fx('sb'), '5: the store chosen is used');
  perform pg_temp.as_user('staff1');
  r := (public.create_staff_transfer_request(jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'quantity', 1)), null, null) ->> 'id')::uuid;
  perform pg_temp.check((select dest_id from public.transfer_requests where id = r) = pg_temp.fx('sa'),
    '5: one live store and none chosen: that store (not the deleted store assigned first)');
  perform pg_temp.as_user('staff0');
  msg := pg_temp.refused($q$select public.create_staff_transfer_request(jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p'), 'quantity', 1)), null, null)$q$);
  perform pg_temp.check(msg like 'You are not assigned to a store%', '5: no store: told so, as before');
  perform pg_temp.as_user('staff2');
  msg := pg_temp.refused(format('select public.create_staff_transfer_request(jsonb_build_array(jsonb_build_object(%L, %L::uuid, %L, 1)), null, %L)',
    'product_id', pg_temp.fx('p'), 'quantity', pg_temp.fx('sgone')));
  perform pg_temp.check(msg = 'You are not assigned to that store.', '5: a store they do not work at is refused, as before');
end $$;

select set_config('request.jwt.claim.sub', '', true) as t421_done \gset
do $$ begin raise notice 'PASS: 421 resolves where each line came from, checks before taking stock off, refuses the adjustment on extra units, clears notes, and asks two-store staff to choose'; end $$;
rollback;
