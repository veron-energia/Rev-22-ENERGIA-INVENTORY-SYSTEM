-- The Dashboard's TikTok counts are each login's stores' (522).
--
-- Stores A and B, with something for each of the seven TikTok counts of the Operations alerts:
-- one at store A and two at store B (staged files, unmatched SKUs, imported orders awaiting
-- settlement, settlement mismatches, orders settled with no imported order, items awaiting a
-- physical return). Staff, an Inventory Manager and a Manager work at store A only. Each login
-- reads dashboard_alerts_summary() as the Dashboard does (the authenticated role): Staff and
-- the Inventory Manager count store A's, and the same as they can open on the TikTok Import
-- page; the Manager and the Owner count every store's, as before 522. 522's UNDO
-- (scripts/dashboard/undo-522.sql) gives the counts of every store back, and 522 again keeps
-- them to the stores.
--
--   sh scripts/invoices/local-sql.sh -f scripts/dashboard/tests/tiktok-counts-follow-the-store-522.sql
-- 522 is installed here when it is not in yet. Disposable local database only;
-- everything is rolled back. Made-up records only (L522, @example.invalid).
\set ON_ERROR_STOP on
begin;
-- 546 (security audit of 17 Nov 2026, L15): where it is in, its UNDO goes first, as this file pins
-- md5s of functions it changes (only their search path); this run only, rolled back with the rest.
select coalesce('search_path=public, pg_temp' = any (proconfig), false) as t546_in
  from pg_proc where oid = 'public.current_user_role()'::regprocedure \gset
\if :t546_in
select set_config('energia.undo546_skip_body_check', 'on', true) \g /dev/null
\ir ../../permissions/undo-546.sql
\endif
select md5(pg_get_functiondef('public.dashboard_alerts_summary()'::regprocedure)) = 'b614ad8c75f8012e069ec72a5be06aa9' as m522_in \gset
\if :m522_in
\else
\ir ../../../supabase/522_dashboard_tiktok_counts_follow_the_store.sql
\endif
-- A second run changes nothing.
\ir ../../../supabase/522_dashboard_tiktok_counts_follow_the_store.sql

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;
create temp table l522(k text primary key, v text not null);
create function pg_temp.fx(p_k text) returns text language sql as $f$ select v from l522 where k = p_k $f$;
-- One statement as a signed-in login: its first column as text, or 'ERR <sqlstate> <message>'.
create function pg_temp.as_login(p_who text, q text) returns text language plpgsql as $f$
declare v text; u uuid := pg_temp.fx(p_who)::uuid;
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute q into v;
  execute 'reset role';
  return coalesce(v, 'ok');
exception when others then return 'ERR ' || sqlstate || ' ' || sqlerrm;
end $f$;
-- The seven TikTok counts a login's Dashboard shows.
create function pg_temp.tiles(p_who text) returns jsonb language sql as
$f$ select (pg_temp.as_login(p_who, $q$select ((public.dashboard_alerts_summary() -> 'tiktok') - 'negative_stock')::text$q$))::jsonb $f$;
-- The same seven over every store, as they were counted before 522 (read here as the database owner).
create function pg_temp.every_store() returns jsonb language sql as $f$
  select jsonb_build_object(
    'imported_orders', (select count(distinct (store_id, order_id)) from public.tiktok_order_state),
    'unmatched_skus', (select count(distinct (o.store_id, o.seller_sku)) from public.tiktok_order_rows o
                        where o.staging_status = 'Unmatched SKU'
                          and not exists (select 1 from public.tiktok_sku_aliases a where a.store_id = o.store_id and a.seller_sku = o.seller_sku)),
    'staged_batches', (select count(*) from public.tiktok_import_batches b where b.status = 'staged' and b.deleted_at is null),
    'orders_awaiting_settlement', (select count(*) from public.tiktok_order_state st
                                    where st.deducted_qty > 0
                                      and not exists (select 1 from public.tiktok_settlement_rows r
                                                       where r.store_id = st.store_id and r.matched_order_id = st.order_id and r.is_current and r.confirmed)),
    'settlement_mismatches', (select count(*) from public.tiktok_settlement_rows r
                               where r.confirmed and r.is_current
                                 and public.tiktok_settlement_row_reconciled(r.reconciled, r.txn_class, r.match_status,
                                       r.settlement_amount, r.revenue_amount, r.fee_amount, r.adjustment_amount) is false),
    'settled_without_order', (select count(distinct (r.store_id, coalesce(r.order_id, r.related_order_id, r.adjustment_id, r.id::text)))
                                from public.tiktok_settlement_rows r
                               where r.confirmed and r.is_current and r.match_status = 'pending'
                                 and not exists (select 1 from public.tiktok_settlement_reviews v where v.settlement_row_id = r.id)),
    'awaiting_physical_return', (select count(*) from public.tiktok_physical_returns pr where pr.status = 'awaiting')) $f$;
-- Seven ones: what a login of store A alone should count.
create function pg_temp.ones() returns jsonb language sql as $f$
  select jsonb_build_object('imported_orders', 1, 'unmatched_skus', 1, 'staged_batches', 1, 'orders_awaiting_settlement', 1,
                            'settlement_mismatches', 1, 'settled_without_order', 1, 'awaiting_physical_return', 1) $f$;

do $$
declare own uuid := gen_random_uuid(); mgr uuid := gen_random_uuid(); im uuid := gen_random_uuid(); stf uuid := gen_random_uuid();
        sa uuid; sb uuid; s uuid; b uuid; k text; n int; j int; row_no int := 1000;
        sfx constant text := lower(substr(md5(gen_random_uuid()::text), 1, 6));
        status constant text := 'L522 To ship ' || sfx;
begin
  insert into auth.users(id, email, email_confirmed_at) values
    (own, 'l522-owner@example.invalid', now()), (mgr, 'l522-manager@example.invalid', now()),
    (im, 'l522-invman@example.invalid', now()), (stf, 'l522-staff@example.invalid', now());
  insert into public.profiles(id, full_name, email, role, is_active) values
    (own, 'L522 Owner', 'l522-owner@example.invalid', 'owner', true),
    (mgr, 'L522 Manager', 'l522-manager@example.invalid', 'manager', true),
    (im, 'L522 Inventory Manager', 'l522-invman@example.invalid', 'inventory_manager', true),
    (stf, 'L522 Staff', 'l522-staff@example.invalid', 'staff', true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  insert into public.stores(name, code, country_code) values ('L522 Store A ' || sfx, 'L522A' || sfx, 'SG') returning id into sa;
  insert into public.stores(name, code, country_code) values ('L522 Store B ' || sfx, 'L522B' || sfx, 'SG') returning id into sb;
  -- Staff, the Inventory Manager and the Manager all work at store A only.
  insert into public.user_store_assignments(user_id, store_id) values (stf, sa), (im, sa), (mgr, sa);
  insert into l522 values ('owner', own::text), ('manager', mgr::text), ('invman', im::text), ('staff', stf::text),
    ('sa', sa::text), ('sb', sb::text);
  -- A status of its own that takes no stock, so the staged rows are judged on their SKU.
  insert into public.tiktok_status_mappings(status_label, status_norm, action, marks_shipped)
    values (status, public.tiktok_norm_status(status), 'none', false);
  -- One of each at store A, two at store B.
  foreach k in array array['a', 'b'] loop
    s := case k when 'a' then sa else sb end;
    n := case k when 'a' then 1 else 2 end;
    for j in 1 .. n loop
      -- A staged order file with an SKU not mapped yet.
      b := public.stage_tiktok_orders(s, format('L522 %s%s.csv', k, j), null, jsonb_build_array(jsonb_build_object(
             'order_id', format('L522-%s%s-%s', k, j, sfx), 'seller_sku', format('L522-NEW-%s%s-%s', k, j, sfx),
             'quantity', '1', 'order_status', status, 'product_name', 'L522 soap')));
      -- An imported order whose stock was taken off, with no settlement yet.
      insert into public.tiktok_order_state(store_id, order_id, seller_sku, deducted_qty, last_status)
        values (s, format('L522-ORD-%s%s-%s', k, j, sfx), format('L522-SKU-%s%s', k, j), 1, status);
      -- A settled line that does not reconcile, and one settled with no imported order.
      row_no := row_no + 1;
      insert into public.tiktok_settlement_rows(batch_id, store_id, row_no, order_id, txn_class, match_status, reconciled, confirmed, is_current)
        values (b, s, row_no, format('L522-MIS-%s%s-%s', k, j, sfx), 'order', 'matched', false, true, true);
      row_no := row_no + 1;
      insert into public.tiktok_settlement_rows(batch_id, store_id, row_no, order_id, txn_class, match_status, reconciled, confirmed, is_current)
        values (b, s, row_no, format('L522-SWO-%s%s-%s', k, j, sfx), 'order', 'pending', true, true, true);
      -- An item awaiting its physical return.
      insert into public.tiktok_physical_returns(store_id, order_id, seller_sku, expected_qty, status)
        values (s, format('L522-RET-%s%s-%s', k, j, sfx), format('L522-SKU-%s%s', k, j), 1, 'awaiting');
    end loop;
  end loop;
end $$;

-- 1. Staff and the Inventory Manager of store A: store A's, one of each
select pg_temp.check(pg_temp.tiles(w) = pg_temp.ones(), '1a ' || w || ' of store A counts store A''s: ' || pg_temp.tiles(w)::text)
  from unnest(array['staff', 'invman']) w;
-- The same as they can open on the TikTok Import page (the tables' read rules, since 520).
select pg_temp.check(pg_temp.tiles('staff') ->> 'imported_orders' = pg_temp.as_login('staff', 'select count(distinct (store_id, order_id))::text from public.tiktok_order_state')
                     and pg_temp.tiles('staff') ->> 'staged_batches' = pg_temp.as_login('staff', $q$select count(*)::text from public.tiktok_import_batches where status = 'staged' and deleted_at is null$q$)
                     and pg_temp.tiles('staff') ->> 'awaiting_physical_return' = pg_temp.as_login('staff', $q$select count(*)::text from public.tiktok_physical_returns where status = 'awaiting'$q$),
  '1b Staff''s imported orders, staged files and awaiting returns are those the TikTok Import page shows them');

-- 2. The Manager of store A, and the Owner: every store's, as before 522
select pg_temp.check(pg_temp.tiles(w) = pg_temp.every_store(), '2a ' || w || ' counts every store''s: ' || pg_temp.tiles(w)::text)
  from unnest(array['manager', 'owner']) w;
select pg_temp.check((select bool_and((pg_temp.every_store() ->> key)::int >= 3) from jsonb_object_keys(pg_temp.ones()) key),
  '2b (every store''s holds at least store A''s one and store B''s two of each)');

-- 3. The function
select pg_temp.check(md5(pg_get_functiondef('public.dashboard_alerts_summary()'::regprocedure)) = 'b614ad8c75f8012e069ec72a5be06aa9'
                     and has_function_privilege('authenticated', 'public.dashboard_alerts_summary()', 'execute'),
  '3a dashboard_alerts_summary is 522''s, signed-in logins still call it');

-- 4. 522's UNDO gives every store's counts back; 522 again keeps them to the stores
\ir ../undo-522.sql
select pg_temp.check(md5(pg_get_functiondef('public.dashboard_alerts_summary()'::regprocedure)) = '71c01b0053937347a63b311b7eca5734'
                     and pg_temp.tiles('staff') = pg_temp.every_store(),
  '4a after the UNDO the function is as before 522, and Staff of store A count every store''s again');
\ir ../../../supabase/522_dashboard_tiktok_counts_follow_the_store.sql
select pg_temp.check(md5(pg_get_functiondef('public.dashboard_alerts_summary()'::regprocedure)) = 'b614ad8c75f8012e069ec72a5be06aa9'
                     and pg_temp.tiles('staff') = pg_temp.ones(),
  '4b 522 again: store A''s once more');
rollback;
