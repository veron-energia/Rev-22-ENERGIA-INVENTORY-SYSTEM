-- 423: vouchers, therapy services, therapy store prices and holiday regions.
--
-- Before 423 (section 1, reproduced here): deleting a voucher left no trace
-- and did not say who still held it; nothing recorded a change to a voucher;
-- a voucher's price change at a store was logged only as a summary of what
-- was sent, with no before; "one price at every store" switched every store
-- back on; saving a therapy
-- service wiped its notes; a therapy package's store price could be saved
-- below zero; and a holiday region was stored as typed, spaces and all, even
-- for "All countries". Section 2 applies 423 and checks each rule, who may
-- call the new functions, and their grants.
--
-- Disposable database only; everything is rolled back. The migration is
-- applied inside this transaction, so run the file on its own:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/therapy/tests/vouchers-services-prices.sql
-- It needs a database with production's schema after 413 (no rows needed).
-- Every name, phone and email is invented (T423, +65 9123 45xx, @sig.invalid).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end$$;
create temp table fx(k text primary key, v uuid);
grant select on fx to public;  -- read while acting as a login
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
-- Act as one of the fixture's logins ('server' = no request at all).
create function pg_temp.as_login(k text) returns void language plpgsql as $$
begin
  execute 'reset role';
  if k = 'server' then
    perform set_config('request.jwt.claims', '', true);
  elsif k = 'anon' then
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    execute 'set local role anon';
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', coalesce(pg_temp.fx(k), gen_random_uuid()), 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
  end if;
end $$;
-- The SQLSTATE and message a statement raises, or null when it succeeds.
-- Either way what it did is undone.
create function pg_temp.refused(q text) returns text language plpgsql as $$
declare v_state text; v_msg text;
begin
  begin
    execute q;
    raise exception 'T423: accepted';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    if v_msg = 'T423: accepted' then return null; end if;
    return v_state || ': ' || v_msg;
  end;
end $$;

-- ── Fixture (as the server) ─────────────────────────────────────────────────
do $$
declare k text; v uuid; st_a uuid; st_b uuid; st_c uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  foreach k in array array['owner', 'admin', 'manager', 'invman', 'staff'] loop
    insert into auth.users(id, email) values (gen_random_uuid(), 't423-' || k || '@sig.invalid') returning id into v;
    insert into fx values (k, v);
    insert into public.profiles(id, full_name, email, role, is_active)
    values (v, 'T423 ' || k, 't423-' || k || '@sig.invalid',
            (case k when 'invman' then 'inventory_manager' else k end)::public.user_role, true);
  end loop;
  insert into public.stores(name, code) values ('T423 Store A', 'T423A') returning id into st_a;
  insert into public.stores(name, code) values ('T423 Store B', 'T423B') returning id into st_b;
  insert into public.stores(name, code, is_active) values ('T423 Store C (closed)', 'T423C', false) returning id into st_c;
  insert into fx values ('store_a', st_a), ('store_b', st_b), ('store_c', st_c);
  insert into public.user_store_assignments(user_id, store_id)
  values (pg_temp.fx('manager'), st_a), (pg_temp.fx('manager'), st_b), (pg_temp.fx('staff'), st_a),
         (pg_temp.fx('invman'), st_a);
  insert into public.customers(full_name, phone, email) values ('T423 Customer One', '+6591234501', 't423-c1@sig.invalid') returning id into v;
  insert into fx values ('c1', v);
  insert into public.customers(full_name, phone, email) values ('T423 Customer Two', '+6591234502', 't423-c2@sig.invalid') returning id into v;
  insert into fx values ('c2', v);
  insert into public.therapy_holiday_countries(code, name, is_active, requires_region)
  values ('SG', 'Singapore', true, false), ('MY', 'Malaysia', true, true)
  on conflict (code) do nothing;
  -- A "voucher prices set" summary row written before 423: evidence, kept as it is.
  insert into public.audit_logs(table_name, record_id, action, old_data, new_data, module, store_id)
  values ('voucher_store_prices', gen_random_uuid(), 'voucher_prices_set', null,
          jsonb_build_object('store', st_a, 'price', 9), 'pricing', st_a)
  returning id into v;
  insert into fx values ('old_summary', v);
end $$;

-- ── 1. Before 423 ───────────────────────────────────────────────────────────
savepoint before423;
do $$
declare v_v uuid; v_svc uuid; v_pkg uuid; v_cl uuid;
begin
  -- A voucher made, changed and deleted through the table leaves no audit row.
  perform pg_temp.as_login('owner');
  insert into public.vouchers(name, code, selling_price) values ('T423 Before', 'T423-BEFORE', 10) returning id into v_v;
  update public.vouchers set name = 'T423 Before 2' where id = v_v;
  update public.vouchers set deleted_at = now(), is_active = false where id = v_v;
  perform pg_temp.as_login('server');
  perform pg_temp.check(not exists (select 1 from public.audit_logs where record_id = v_v),
    'before 423: a voucher made, changed and deleted leaves no audit row');

  -- One price at every store switches a store back on.
  insert into public.vouchers(name, code, selling_price) values ('T423 Before price', 'T423-BEFORE-P', 10) returning id into v_v;
  insert into public.voucher_store_prices(voucher_id, store_id, selling_price, available_at_store)
  values (v_v, pg_temp.fx('store_a'), 10, false);
  perform pg_temp.as_login('owner');
  perform public.set_voucher_price_all_stores(v_v, 12, true);
  perform pg_temp.as_login('server');
  perform pg_temp.check((select available_at_store from public.voucher_store_prices
                          where voucher_id = v_v and store_id = pg_temp.fx('store_a')),
    'before 423: one price at every store switches a store back on');
  perform pg_temp.check((select count(*) from public.audit_logs where record_id = v_v and store_id = pg_temp.fx('store_a')) = 1
                        and exists (select 1 from public.audit_logs where record_id = v_v and store_id = pg_temp.fx('store_a')
                                      and action = 'voucher_prices_set' and old_data is null),
    'before 423: a price change at a store is logged only as a summary of what was sent, with no before');

  -- Saving a service without notes wipes them.
  insert into public.therapy_services(service_code, name, standard_price, duration_minutes, is_active, notes)
  values ('t423-before', 'T423 Before service', 50, 30, true, 'A note') returning id into v_svc;
  perform pg_temp.as_login('owner');
  perform public.upsert_therapy_service(v_svc, 't423-before', 'T423 Before service', 50, 30, 'unrestricted', 1, null, null, true, null);
  perform pg_temp.as_login('server');
  perform pg_temp.check((select notes from public.therapy_services where id = v_svc) is null,
    'before 423: saving a service without notes wipes them');

  -- A negative therapy store price is saved.
  insert into public.unlimited_therapy_packages(name, duration_months) values ('T423 Before package', 12) returning id into v_pkg;
  perform pg_temp.as_login('owner');
  perform public.set_unlimited_therapy_price(v_pkg, pg_temp.fx('store_a'), -5, -5, true);
  perform pg_temp.as_login('server');
  perform pg_temp.check((select selling_price from public.unlimited_therapy_store_prices where package_id = v_pkg) = -5,
    'before 423: a therapy store price of -5 is saved');

  -- A region is stored with its spaces, and for all countries.
  perform pg_temp.as_login('owner');
  v_cl := public.upsert_therapy_closure_date(null, date '2099-03-01', 'company_closure', 'T423 Before', null, '  North ', null, null, null, null);
  perform pg_temp.as_login('server');
  perform pg_temp.check((select region from public.therapy_closure_dates where id = v_cl) = '  North ',
    'before 423: a region is stored as typed, for all countries');
end $$;
rollback to savepoint before423;

-- ── 2. 423 ──────────────────────────────────────────────────────────────────
\ir ../../../supabase/423_vouchers_services_prices_and_splits.sql
reset role;
select set_config('request.jwt.claims', '', true);

-- Rule 1: the audit of a voucher and its store prices.
do $$
declare v_v uuid; n int;
begin
  perform pg_temp.as_login('manager');
  insert into public.vouchers(name, code, voucher_kind, selling_price) values ('T423 Audit', 'T423-AUDIT', 'normal', 20)
    returning id into v_v;
  update public.vouchers set selling_price = 25, description = 'T423 note' where id = v_v;
  update public.vouchers set selling_price = 25 where id = v_v;              -- no change: no row
  update public.vouchers set deleted_at = now(), is_active = false where id = v_v;  -- the old page's delete
  update public.vouchers set deleted_at = null where id = v_v;
  perform pg_temp.as_login('server');
  insert into fx values ('v_audit', v_v);
  perform pg_temp.check((select count(*) from public.audit_logs where record_id = v_v and table_name = 'vouchers') = 4,
    'four changes to a voucher, four audit rows (a change that changes nothing writes none)');
  perform pg_temp.check(exists (select 1 from public.audit_logs where record_id = v_v and action = 'voucher_created'
                                  and changed_by = pg_temp.fx('manager') and actor_role = 'manager' and module = 'catalogue'
                                  and new_data ->> 'code' = 'T423-AUDIT'),
    'a new voucher is logged as voucher_created, by the Manager, with the whole row');
  perform pg_temp.check(exists (select 1 from public.audit_logs where record_id = v_v and action = 'voucher_updated'
                                  and old_data = '{"selling_price": 20, "description": null}'::jsonb
                                  and new_data = '{"selling_price": 25, "description": "T423 note"}'::jsonb),
    'an edit is logged with only the columns that changed, before and after');
  perform pg_temp.check(exists (select 1 from public.audit_logs where record_id = v_v and action = 'voucher_deleted'
                                  and old_data ? 'deleted_at' and reason is null),
    'a delete through the table (the old page) is logged as voucher_deleted');
  perform pg_temp.check(exists (select 1 from public.audit_logs where record_id = v_v and action = 'voucher_restored'),
    'clearing deleted_at is logged as voucher_restored');

  -- Price rows, under the voucher, with the store.
  perform pg_temp.as_login('owner');
  perform public.set_voucher_prices(v_v, pg_temp.fx('store_a'), 30, 30, true);
  perform public.set_voucher_prices(v_v, pg_temp.fx('store_a'), 30, 30, true);  -- same again: no trigger row
  perform public.set_voucher_prices(v_v, pg_temp.fx('store_a'), 31, 31, false);
  perform pg_temp.as_login('server');
  perform pg_temp.check((select count(*) from public.audit_logs where record_id = v_v and table_name = 'voucher_store_prices'
                          and action like 'voucher_store_price_%') = 2,
    'a price row made, then changed: two trigger rows (the same price again writes none)');
  perform pg_temp.check(not exists (select 1 from public.audit_logs where record_id = v_v and action = 'voucher_prices_set'),
    'set_voucher_prices writes no "voucher prices set" summary any more: a price change has one row, its before and after');
  perform pg_temp.check(exists (select 1 from public.audit_logs where record_id = v_v and action = 'voucher_store_price_updated'
                                  and store_id = pg_temp.fx('store_a') and module = 'pricing'
                                  and old_data = '{"selling_price": 30, "available_at_store": true}'::jsonb
                                  and new_data ->> 'selling_price' = '31.00' and new_data ->> 'store_id' = pg_temp.fx('store_a')::text),
    'a price change is logged under the voucher, with the store, before and after');
  perform pg_temp.check((select new_data - 'price_row_id' from public.audit_logs
                          where record_id = v_v and action = 'voucher_store_price_updated')
                        = jsonb_build_object('selling_price', 31, 'available_at_store', false, 'store_id', pg_temp.fx('store_a')),
    'a changed price''s details are the store and the columns that changed (and the price row), nothing else');
  perform pg_temp.check(exists (select 1 from public.audit_logs where id = pg_temp.fx('old_summary') and action = 'voucher_prices_set'
                                      and old_data is null and new_data = jsonb_build_object('store', pg_temp.fx('store_a'), 'price', 9)),
    'a "voucher prices set" row written before 423 is kept as it was');
  -- A row deleted outright.
  delete from public.voucher_store_prices where voucher_id = v_v;
  delete from public.vouchers where id = v_v;
  perform pg_temp.check(exists (select 1 from public.audit_logs where record_id = v_v and action = 'voucher_store_price_removed')
                        and exists (select 1 from public.audit_logs where record_id = v_v and action = 'voucher_removed'
                                      and new_data is null and old_data ->> 'name' = 'T423 Audit'),
    'a price row and a voucher deleted outright are logged as removed, with the row');
  -- No profile behind the change (a login that is not staff cannot write, but
  -- a server function might run for one): the row still goes in, by nobody.
  perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  insert into public.vouchers(name, code, selling_price) values ('T423 No profile', 'T423-NOPROFILE', 5) returning id into v_v;
  perform set_config('request.jwt.claims', '', true);
  perform pg_temp.check(exists (select 1 from public.audit_logs where record_id = v_v and action = 'voucher_created'
                                  and changed_by is null),
    'a change with no staff profile behind it is logged with no author, not refused');
end $$;

-- Rule 2: Delete says what still depends on a voucher, and waits.
do $$
declare v_v uuid; v_free uuid; v_pr uuid; v_res jsonb; v_e text;
begin
  perform pg_temp.as_login('server');
  insert into public.vouchers(name, code, selling_price, qty_type) values ('T423 Held', 'T423-HELD', 10, 'limited') returning id into v_v;
  insert into public.vouchers(name, code, selling_price) values ('T423 Free', 'T423-FREE', 10) returning id into v_free;
  -- Two customers hold three units (one revoked row does not count), a store
  -- has four in stock, a live promotion and a live bundle offer it (an
  -- inactive promotion does not count).
  insert into public.customer_reward_vouchers(customer_id, voucher_id, quantity, status)
  values (pg_temp.fx('c1'), v_v, 2, 'held'), (pg_temp.fx('c2'), v_v, 1, 'held'), (pg_temp.fx('c2'), v_v, 5, 'revoked');
  insert into public.voucher_store_stock(voucher_id, store_id, current_qty) values (v_v, pg_temp.fx('store_a'), 4),
                                                                                  (v_v, pg_temp.fx('store_b'), 0);
  insert into public.promotions(name, code) values ('T423 Promo', 'T423-PROMO') returning id into v_pr;
  insert into public.promotion_items(promotion_id, item_type, voucher_id, quantity) values (v_pr, 'voucher', v_v, 1);
  insert into public.promotions(name, code, is_active) values ('T423 Old promo', 'T423-OLD', false) returning id into v_pr;
  insert into public.promotion_items(promotion_id, item_type, voucher_id, quantity) values (v_pr, 'voucher', v_v, 1);
  insert into public.premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty)
  values ('T423 Bundle', 100, 100, 0, 1) returning id into v_pr;
  insert into public.premium_bundle_vouchers(bundle_id, voucher_id) values (v_pr, v_v);

  -- Who may: Owner and Manager. Admin, Inventory Manager and Staff are refused.
  foreach v_e in array array['admin', 'invman', 'staff', 'nobody'] loop
    perform pg_temp.as_login(v_e);
    perform pg_temp.check(pg_temp.refused(format('select public.soft_delete_voucher(%L, null, true)', v_v)) like '42501:%',
      format('%s may not delete a voucher (42501)', v_e));
  end loop;
  perform pg_temp.as_login('anon');
  perform pg_temp.check(pg_temp.refused(format('select public.soft_delete_voucher(%L, null, true)', v_v)) like '42501:%',
    'the anon key may not call soft_delete_voucher');

  perform pg_temp.as_login('manager');
  v_res := public.soft_delete_voucher(v_v, 'Event over', false);
  perform pg_temp.as_login('server');
  perform pg_temp.check((v_res ->> 'needs_confirmation')::boolean and not (v_res ->> 'deleted')::boolean
                        and (v_res ->> 'holders_customers')::int = 2 and (v_res ->> 'holders_units')::int = 3
                        and (v_res ->> 'store_stock_total')::int = 4
                        and v_res -> 'store_stock' = jsonb_build_array(jsonb_build_object(
                              'store_id', pg_temp.fx('store_a'), 'store_name', 'T423 Store A', 'quantity', 4))
                        and v_res -> 'used_in' = '{"promotions": 1, "premium_bundles": 1, "credit_packages": 0, "therapy_packages": 0}'::jsonb
                        and (v_res ->> 'used_in_total')::int = 2,
    'unconfirmed: it says 2 customers hold 3, Store A has 4, 1 live promotion and 1 live bundle offer it');
  perform pg_temp.check((select deleted_at is null and is_active from public.vouchers where id = v_v)
                        and not exists (select 1 from public.audit_logs where record_id = v_v and action = 'voucher_deleted'),
    'unconfirmed: nothing changed and nothing was logged');

  perform pg_temp.as_login('manager');
  v_res := public.soft_delete_voucher(v_v, '  Event over  ', true);
  perform pg_temp.as_login('server');
  perform pg_temp.check((v_res ->> 'deleted')::boolean and not (v_res ->> 'needs_confirmation')::boolean
                        and (select deleted_at is not null and not is_active from public.vouchers where id = v_v),
    'confirmed: the voucher is marked deleted and switched off');
  perform pg_temp.check((select count(*) from public.customer_reward_vouchers where voucher_id = v_v and status = 'held') = 2,
    'customers keep the vouchers they hold');
  perform pg_temp.check((select count(*) from public.audit_logs where record_id = v_v and action = 'voucher_deleted') = 1
                        and exists (select 1 from public.audit_logs where record_id = v_v and action = 'voucher_deleted'
                                      and reason = 'Event over' and changed_by = pg_temp.fx('manager')
                                      and (new_data -> 'detail' ->> 'holders_units')::int = 3
                                      and (new_data -> 'detail' ->> 'store_stock_total')::int = 4
                                      and new_data ->> 'is_active' = 'false'),
    'one audit row: the reason, the Manager, and what depended on it');
  perform pg_temp.check(coalesce(current_setting('energia.voucher_change_reason', true), '') = ''
                        and coalesce(current_setting('energia.voucher_change_detail', true), '') = '',
    'the reason is not left set for later statements');

  perform pg_temp.as_login('owner');
  v_res := public.soft_delete_voucher(v_v, null, false);
  perform pg_temp.check((v_res ->> 'deleted')::boolean and (v_res ->> 'already_deleted')::boolean,
    'deleting it again answers "already deleted" (a retry is safe)');
  -- Nothing depends on it: deleted at once, no reason needed.
  v_res := public.soft_delete_voucher(v_free, null, false);
  perform pg_temp.as_login('server');
  perform pg_temp.check((v_res ->> 'deleted')::boolean and (select deleted_at is not null from public.vouchers where id = v_free)
                        and exists (select 1 from public.audit_logs where record_id = v_free and action = 'voucher_deleted'
                                      and reason is null and changed_by = pg_temp.fx('owner')),
    'a voucher nothing depends on is deleted at once, and logged');
  perform pg_temp.check(pg_temp.refused(format('select public.soft_delete_voucher(%L)', gen_random_uuid())) like '%That voucher no longer exists%',
    'an unknown voucher is refused plainly');
end $$;

-- Rule 2, one thing at a time: a voucher no customer holds and no store
-- stocks still asks first when one live thing offers it, and names that
-- thing. Each kind is counted on its own: a promotion's choice option, a
-- credit package, a therapy package (as its own voucher, or in its list).
-- Only things that are not live: deleted at once.
do $$
declare v uuid; v_pr uuid; v_g uuid; v_cp uuid; v_tp uuid; v_res jsonb; r record;
begin
  perform pg_temp.as_login('server');
  -- (a) only a live promotion's choice option
  insert into public.vouchers(name, code, selling_price) values ('T423 Only choice', 'T423-ONLY-CHOICE', 10) returning id into v;
  insert into fx values ('only_choice', v);
  insert into public.promotions(name, code) values ('T423 Choice promo', 'T423-CHOICE') returning id into v_pr;
  insert into public.promotion_choice_groups(promotion_id, label, item_kind, choose_qty)
  values (v_pr, 'T423 pick one', 'voucher', 1) returning id into v_g;
  insert into public.promotion_choice_options(group_id, voucher_id) values (v_g, v);
  -- (b) only a live credit package
  insert into public.vouchers(name, code, selling_price) values ('T423 Only credit', 'T423-ONLY-CREDIT', 10) returning id into v;
  insert into fx values ('only_credit', v);
  insert into public.credit_packages(name, customer_price, paid_credit_amount) values ('T423 Credit', 100, 100) returning id into v_cp;
  insert into public.credit_package_vouchers(package_id, voucher_id) values (v_cp, v);
  -- (c) only a live therapy package: as the package's own voucher, or in its list
  insert into public.vouchers(name, code, selling_price) values ('T423 Only therapy own', 'T423-ONLY-TPOWN', 10) returning id into v;
  insert into fx values ('only_tp_own', v);
  insert into public.unlimited_therapy_packages(name, duration_months, entitlement_kind, voucher_id, voucher_qty)
  values ('T423 Voucher package', 1, 'voucher', v, 1);
  insert into public.vouchers(name, code, selling_price) values ('T423 Only therapy list', 'T423-ONLY-TPLIST', 10) returning id into v;
  insert into fx values ('only_tp_list', v);
  insert into public.unlimited_therapy_packages(name, duration_months) values ('T423 Unlimited package', 12) returning id into v_tp;
  insert into public.therapy_package_vouchers(package_id, voucher_id) values (v_tp, v);
  -- (d) only things that are not live: an inactive promotion (an item and a
  -- choice option), a deleted credit package, an inactive therapy package
  insert into public.vouchers(name, code, selling_price) values ('T423 Only old', 'T423-ONLY-OLD', 10) returning id into v;
  insert into fx values ('only_old', v);
  insert into public.promotions(name, code, is_active) values ('T423 Old choice promo', 'T423-OLD-CHOICE', false) returning id into v_pr;
  insert into public.promotion_items(promotion_id, item_type, voucher_id, quantity) values (v_pr, 'voucher', v, 1);
  insert into public.promotion_choice_groups(promotion_id, label, item_kind, choose_qty)
  values (v_pr, 'T423 old pick', 'voucher', 1) returning id into v_g;
  insert into public.promotion_choice_options(group_id, voucher_id) values (v_g, v);
  insert into public.credit_packages(name, customer_price, paid_credit_amount, deleted_at)
  values ('T423 Old credit', 100, 100, now()) returning id into v_cp;
  insert into public.credit_package_vouchers(package_id, voucher_id) values (v_cp, v);
  insert into public.unlimited_therapy_packages(name, duration_months, is_active) values ('T423 Old package', 12, false) returning id into v_tp;
  insert into public.therapy_package_vouchers(package_id, voucher_id) values (v_tp, v);

  for r in select * from (values
    ('only_choice', '{"promotions": 1, "premium_bundles": 0, "credit_packages": 0, "therapy_packages": 0}', 'a live promotion''s choice option'),
    ('only_credit', '{"promotions": 0, "premium_bundles": 0, "credit_packages": 1, "therapy_packages": 0}', 'a live credit package'),
    ('only_tp_own', '{"promotions": 0, "premium_bundles": 0, "credit_packages": 0, "therapy_packages": 1}', 'a live therapy package, as its own voucher'),
    ('only_tp_list', '{"promotions": 0, "premium_bundles": 0, "credit_packages": 0, "therapy_packages": 1}', 'a live therapy package, in its list')
  ) x(k, used_in, what)
  loop
    perform pg_temp.as_login('manager');
    v_res := public.soft_delete_voucher(pg_temp.fx(r.k), null, false);
    perform pg_temp.as_login('server');
    perform pg_temp.check((v_res ->> 'needs_confirmation')::boolean and not (v_res ->> 'deleted')::boolean
                          and (v_res ->> 'holders_units')::int = 0 and (v_res ->> 'store_stock_total')::int = 0
                          and v_res -> 'used_in' = r.used_in::jsonb and (v_res ->> 'used_in_total')::int = 1
                          and (select deleted_at is null and is_active from public.vouchers where id = pg_temp.fx(r.k)),
      format('offered only by %s, held by no one, in no store: it asks first, names it, and changes nothing', r.what));
  end loop;
  perform pg_temp.as_login('manager');
  v_res := public.soft_delete_voucher(pg_temp.fx('only_old'), null, false);
  perform pg_temp.as_login('server');
  perform pg_temp.check((v_res ->> 'deleted')::boolean and not (v_res ->> 'needs_confirmation')::boolean
                        and (v_res ->> 'used_in_total')::int = 0
                        and v_res -> 'used_in' = '{"promotions": 0, "premium_bundles": 0, "credit_packages": 0, "therapy_packages": 0}'::jsonb
                        and (select deleted_at is not null from public.vouchers where id = pg_temp.fx('only_old')),
    'offered only by an inactive promotion, a deleted credit package and an inactive therapy package: deleted at once');
end $$;

-- Rule 3: one price at every store keeps each store's availability.
do $$
declare v_v uuid;
begin
  perform pg_temp.as_login('server');
  insert into public.vouchers(name, code, selling_price) values ('T423 Price', 'T423-PRICE', 10) returning id into v_v;
  insert into public.voucher_store_prices(voucher_id, store_id, selling_price, available_at_store)
  values (v_v, pg_temp.fx('store_a'), 10, false);
  perform pg_temp.as_login('manager');
  perform public.set_voucher_price_all_stores(v_v, 15, null);
  perform pg_temp.as_login('server');
  perform pg_temp.check((select selling_price = 15 and not available_at_store from public.voucher_store_prices
                          where voucher_id = v_v and store_id = pg_temp.fx('store_a')),
    'null: Store A gets the new price and stays switched off');
  perform pg_temp.check((select selling_price = 15 and available_at_store from public.voucher_store_prices
                          where voucher_id = v_v and store_id = pg_temp.fx('store_b')),
    'null: Store B, which had no price, gets it on sale');
  perform pg_temp.check(not exists (select 1 from public.voucher_store_prices
                                     where voucher_id = v_v and store_id = pg_temp.fx('store_c')),
    'a closed store is not given a price');
  perform pg_temp.as_login('manager');
  perform public.set_voucher_price_all_stores(v_v, 16, true);
  perform pg_temp.as_login('server');
  perform pg_temp.check((select bool_and(available_at_store and selling_price = 16) from public.voucher_store_prices
                          where voucher_id = v_v),
    'true: every store on sale at the new price, as before');
  perform pg_temp.as_login('manager');
  perform public.set_voucher_price_all_stores(v_v, 16, false);
  perform pg_temp.as_login('server');
  perform pg_temp.check((select bool_and(not available_at_store) from public.voucher_store_prices where voucher_id = v_v),
    'false: every store switched off, as before');
  perform pg_temp.as_login('staff');
  perform pg_temp.check(pg_temp.refused(format('select public.set_voucher_price_all_stores(%L, 1, null)', v_v))
                        like '%Only an Owner or Manager can edit voucher prices%',
    'Staff may still not set voucher prices');
end $$;

-- Rule 4: notes are kept when none are sent.
do $$
declare v_svc uuid;
begin
  perform pg_temp.as_login('server');
  insert into public.therapy_services(service_code, name, standard_price, duration_minutes, is_active, notes)
  values ('t423-notes', 'T423 Notes service', 50, 30, true, 'Keep me') returning id into v_svc;
  insert into fx values ('svc', v_svc);
  perform pg_temp.as_login('manager');
  perform public.upsert_therapy_service(v_svc, 't423-notes', 'T423 Notes service', 55, 30, 'unrestricted', 1, null, 'Desc', true, null);
  perform pg_temp.check((select notes = 'Keep me' and standard_price = 55 and description = 'Desc'
                          from public.therapy_services where id = v_svc),
    'a save with no notes (null) keeps them and saves the rest');
  perform public.upsert_therapy_service(v_svc, 't423-notes', 'T423 Notes service', 55, 30, 'unrestricted', 1, null, 'Desc', true, '  New note ');
  perform pg_temp.check((select notes from public.therapy_services where id = v_svc) = 'New note',
    'a save with notes writes them, trimmed');
  perform public.upsert_therapy_service(v_svc, 't423-notes', 'T423 Notes service', 55, 30, 'unrestricted', 1, null, 'Desc', true, '');
  perform pg_temp.check((select notes from public.therapy_services where id = v_svc) is null,
    'an empty text clears them');
  -- (two statements: a query does not see what a function it calls has written)
  perform pg_temp.check((public.upsert_therapy_service(null, 't423-new', 'T423 New service', 40, 30, 'unrestricted', 1, null, null, true, ' First ')
                          ->> 'code') = 't423-new', 'a new service is made');
  perform pg_temp.check((select notes from public.therapy_services where service_code = 't423-new') = 'First',
    'a new service still takes its notes');
end $$;

-- Rule 5: a service's stores are saved together.
do $$
declare v_svc uuid := pg_temp.fx('svc'); v_e text; n int;
begin
  foreach v_e in array array['staff', 'invman', 'nobody'] loop
    perform pg_temp.as_login(v_e);
    perform pg_temp.check(pg_temp.refused(format('select public.set_therapy_service_stores(%L, %L)', v_svc, '[]')) like '42501:%',
      format('%s may not save a service''s stores (42501)', v_e));
  end loop;
  perform pg_temp.as_login('anon');
  perform pg_temp.check(pg_temp.refused(format('select public.set_therapy_service_stores(%L, %L)', v_svc, '[]')) like '42501:%',
    'the anon key may not call set_therapy_service_stores');

  perform pg_temp.as_login('manager');
  perform pg_temp.check(pg_temp.refused(format('select public.set_therapy_service_stores(%L, %L::jsonb)', v_svc,
          jsonb_build_array(jsonb_build_object('store_id', pg_temp.fx('store_a'), 'is_available', true, 'price_override', 60),
                            jsonb_build_object('store_id', pg_temp.fx('store_b'), 'is_available', true, 'price_override', -1))))
                        like '%The price at T423 Store B cannot be negative%',
    'a negative price at Store B is refused, naming the store');
  perform pg_temp.check(pg_temp.refused(format('select public.set_therapy_service_stores(%L, %L::jsonb)', v_svc,
          jsonb_build_array(jsonb_build_object('store_id', pg_temp.fx('store_a'), 'is_available', true, 'price_override', 60),
                            jsonb_build_object('store_id', gen_random_uuid(), 'is_available', true))))
                        like '%A store in this list no longer exists%',
    'a store that does not exist is refused');
  perform pg_temp.check(not exists (select 1 from public.therapy_service_stores where service_id = v_svc),
    'after a refusal no store was saved (all or nothing)');

  perform pg_temp.check(public.set_therapy_service_stores(v_svc,
          jsonb_build_array(jsonb_build_object('store_id', pg_temp.fx('store_a'), 'is_available', true, 'price_override', 60),
                            jsonb_build_object('store_id', pg_temp.fx('store_b'), 'is_available', false, 'price_override', ''),
                            jsonb_build_object('store_id', pg_temp.fx('store_c'), 'is_available', false))) = 3,
    'three rows saved (a closed store with a row is kept too)');
  perform pg_temp.check((select string_agg(st.code || ':' || s.is_available || ':' || coalesce(s.price_override::text, '-'), ',' order by st.code)
                          from public.therapy_service_stores s join public.stores st on st.id = s.store_id
                         where s.service_id = v_svc) = 'T423A:true:60.00,T423B:false:-,T423C:false:-',
    'each store as sent; a blank price is the standard price');
  perform public.set_therapy_service_stores(v_svc,
          jsonb_build_array(jsonb_build_object('store_id', pg_temp.fx('store_a'), 'is_available', false, 'price_override', null)));
  perform pg_temp.check((select not is_available and price_override is null from public.therapy_service_stores
                          where service_id = v_svc and store_id = pg_temp.fx('store_a')),
    'a second save updates the row');
  perform pg_temp.as_login('admin');
  perform pg_temp.check(public.set_therapy_service_stores(v_svc, '[]'::jsonb) = 0, 'an Admin may save (the page is for Owner, Admin and Manager)');
  perform pg_temp.as_login('server');
  perform pg_temp.check((select count(*) from public.audit_logs where record_id = v_svc and action = 'therapy_service_stores_saved') = 3,
    'each save leaves one audit row');
  update public.therapy_services set deleted_at = now() where id = v_svc;
  perform pg_temp.as_login('manager');
  perform pg_temp.check(pg_temp.refused(format('select public.set_therapy_service_stores(%L, %L)', v_svc, '[]'))
                        like '%That service no longer exists%',
    'an archived service''s stores cannot be saved');
  perform pg_temp.check(pg_temp.refused(format('select public.set_therapy_service_stores(%L, %L)', gen_random_uuid(), '{}'))
                        like '%That service no longer exists%'
                        and pg_temp.refused(format('select public.set_therapy_service_stores(%L, %L)', (select id from public.therapy_services where service_code = 't423-new'), '{}'))
                        like '%Send the stores as a list%',
    'an unknown service, or rows that are not a list, are refused');
end $$;

-- Rule 7: a holiday's region.
do $$
declare v_cl uuid; v_cl2 uuid;
begin
  perform pg_temp.as_login('manager');
  perform pg_temp.check(pg_temp.refused($q$select public.upsert_therapy_closure_date(null, date '2099-03-01', 'company_closure', 'T423 A', null, 'North', null, null, null, null)$q$)
                        like '%Choose the country this region belongs to%',
    'a region for "All countries" is refused');
  perform pg_temp.check(pg_temp.refused($q$select public.upsert_therapy_closure_date(null, date '2099-03-01', 'public_holiday', 'T423 A', 'MY', ' * ', null, null, null, null)$q$)
                        like '%Leave the region blank for the whole country%',
    'the region "*" is refused');
  v_cl := public.upsert_therapy_closure_date(null, date '2099-03-02', 'public_holiday', 'T423 State day', 'MY', '  Selangor ', null, null, null, null);
  v_cl2 := public.upsert_therapy_closure_date(null, date '2099-03-03', 'public_holiday', 'T423 National day', 'MY', '   ', null, null, null, null);
  perform pg_temp.check((select region from public.therapy_closure_dates where id = v_cl) = 'Selangor'
                        and (select region from public.therapy_closure_dates where id = v_cl2) is null,
    'a region is trimmed, and a blank one is none (the whole country)');
  perform public.upsert_therapy_closure_date(v_cl, date '2099-03-02', 'public_holiday', 'T423 State day', 'MY', 'Johor  ', null, null, null, null);
  perform pg_temp.check((select region from public.therapy_closure_dates where id = v_cl) = 'Johor',
    'an edit trims the region too');
  perform pg_temp.check((select count(*) from public.therapy_applicable_closures(date '2099-03-01', date '2099-03-31', 'MY', 'Johor')) = 2
                        and (select count(*) from public.therapy_applicable_closures(date '2099-03-01', date '2099-03-31', 'MY', 'Selangor')) = 1,
    'Johor gets its own day and the national one; Selangor only the national one');
  perform pg_temp.as_login('staff');
  perform pg_temp.check(pg_temp.refused($q$select public.upsert_therapy_closure_date(null, date '2099-03-04', 'company_closure', 'T423 B', 'SG', null, null, null, null, null)$q$)
                        like '%Only an Owner or Manager can edit the holiday calendar%',
    'Staff still may not edit the holiday calendar');
end $$;

-- Rule 8: a therapy store price is 0 or more, or blank.
do $$
declare v_pkg uuid;
begin
  perform pg_temp.as_login('server');
  insert into public.unlimited_therapy_packages(name, duration_months) values ('T423 Package', 12) returning id into v_pkg;
  perform pg_temp.as_login('owner');
  perform pg_temp.check(pg_temp.refused(format('select public.set_unlimited_therapy_price(%L, %L, -0.01, null, true)', v_pkg, pg_temp.fx('store_a')))
                        like '%Price cannot be negative%',
    'a price of -0.01 is refused');
  perform pg_temp.check(pg_temp.refused(format('select public.set_unlimited_therapy_price(%L, %L, %L::numeric, null, true)', v_pkg, pg_temp.fx('store_a'), 'NaN'))
                        like '%Price cannot be negative%',
    'NaN is refused');
  -- set_therapy_price_all_stores is the service role's alone (no page calls
  -- it): tried as the server, on the Owner's behalf.
  execute 'reset role';
  perform pg_temp.check(pg_temp.refused(format('select public.set_therapy_price_all_stores(%L, -10, true)', v_pkg))
                        like '%Price cannot be negative%',
    'set_therapy_price_all_stores refuses a negative price too');
  perform pg_temp.as_login('owner');
  perform public.set_unlimited_therapy_price(v_pkg, pg_temp.fx('store_a'), 0, 0, true);
  perform public.set_unlimited_therapy_price(v_pkg, pg_temp.fx('store_b'), null, null, true);
  perform pg_temp.as_login('server');
  perform pg_temp.check((select string_agg(st.code || ':' || coalesce(p.selling_price::text, 'blank'), ',' order by st.code)
                          from public.unlimited_therapy_store_prices p join public.stores st on st.id = p.store_id
                         where p.package_id = v_pkg) = 'T423A:0.00,T423B:blank',
    '0 and blank (blocked at that store) are still saved');
  perform pg_temp.check(pg_temp.refused(format('insert into public.unlimited_therapy_store_prices(package_id, store_id, selling_price) values (%L, %L, -1)', v_pkg, pg_temp.fx('store_c')))
                        like '23514:%unlimited_therapy_store_prices_selling_price_check%',
    'the table itself refuses a negative price (CHECK, validated)');
  perform pg_temp.check(pg_temp.refused(format('insert into public.unlimited_therapy_store_prices(package_id, store_id, selling_price) values (%L, %L, %L::numeric)', v_pkg, pg_temp.fx('store_c'), 'NaN'))
                        like '23514:%unlimited_therapy_store_prices_selling_price_check%',
    'the table itself refuses NaN as a price');
  perform pg_temp.check((select convalidated from pg_constraint where conname = 'unlimited_therapy_store_prices_selling_price_check'),
    'the check is validated');
end $$;

-- Grants of the new functions, and the old split signatures are gone.
do $$
begin
  perform pg_temp.as_login('server');
  perform pg_temp.check(has_function_privilege('authenticated', 'public.soft_delete_voucher(uuid,text,boolean)', 'execute')
                        and has_function_privilege('authenticated', 'public.set_therapy_service_stores(uuid,jsonb)', 'execute')
                        and not has_function_privilege('anon', 'public.soft_delete_voucher(uuid,text,boolean)', 'execute')
                        and not has_function_privilege('anon', 'public.set_therapy_service_stores(uuid,jsonb)', 'execute'),
    'the two new page functions: signed-in logins yes, anon no');
  perform pg_temp.check(not has_function_privilege('authenticated', 'public.trg_audit_voucher_change()', 'execute')
                        and not has_function_privilege('anon', 'public.trg_audit_voucher_change()', 'execute'),
    'the trigger function is no client''s');
  perform pg_temp.check(to_regprocedure('public.create_split_credit_package_invoices(uuid,uuid,jsonb,uuid[],uuid,text)') is null
                        and to_regprocedure('public.create_split_premium_bundle_invoices(uuid,uuid,jsonb,uuid[],uuid,text)') is null,
    'the six-argument split functions are gone');
end $$;

rollback;
