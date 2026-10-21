-- 423: a split sale sent again with the same request id is not made twice.
--
-- Before 423 (section 1, reproduced here): create_split_credit_package_invoices
-- took no request id, so when the answer to "Create invoices" was lost and
-- staff pressed it again, a second group of unpaid invoices was made for the
-- same sale. Section 2 applies 423 and makes real split invoices: a credit
-- package and a premium bundle, each sent twice with one request id (the
-- second answer is the first sale, and no invoice is added), a request id used
-- for another package, bundle or store, or for other customers, amounts or
-- vouchers (refused, never answered as the first sale; the same allocations
-- in another order are the same sale), a failed first try then a good retry
-- with the same id, a call with no id (as before), and who may call.
-- scripts/therapy/tests/split-replay-concurrency.mjs sends two calls at once.
--
-- Disposable database only; everything is rolled back. The migration is
-- applied inside this transaction, so run the file on its own:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/therapy/tests/split-replay.sql
-- It needs a database with production's schema after 413 (no rows needed).
-- Every name, phone and email is invented (T423S, +65 9123 46xx, @sig.invalid).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end$$;
create temp table fx(k text primary key, v uuid);
grant select on fx to public;  -- read while acting as a login
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
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
create function pg_temp.refused(q text) returns text language plpgsql as $$
declare v_state text; v_msg text;
begin
  begin
    execute q;
    raise exception 'T423S: accepted';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    if v_msg = 'T423S: accepted' then return null; end if;
    return v_state || ': ' || v_msg;
  end;
end $$;
-- The allocations the panels send: two customers, 60 / 40.
create function pg_temp.cp_alloc() returns jsonb language sql as $$
  select jsonb_build_array(
    jsonb_build_object('customer_id', pg_temp.fx('c1'), 'payment_amount', 600, 'reward_voucher_qty', 0),
    jsonb_build_object('customer_id', pg_temp.fx('c2'), 'payment_amount', 400, 'reward_voucher_qty', 0)) $$;
create function pg_temp.pb_alloc() returns jsonb language sql as $$
  select jsonb_build_array(
    jsonb_build_object('customer_id', pg_temp.fx('c1'), 'payment_amount', 300,
                       'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.fx('voucher'), 'quantity', 1))),
    jsonb_build_object('customer_id', pg_temp.fx('c2'), 'payment_amount', 200,
                       'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.fx('voucher'), 'quantity', 1)))) $$;
create function pg_temp.n_invoices() returns bigint language sql as $$
  select count(*) from public.invoices where store_id in (pg_temp.fx('store_a'), pg_temp.fx('store_b')) $$;

-- ── Fixture (as the server) ─────────────────────────────────────────────────
do $$
declare k text; v uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  foreach k in array array['manager', 'staff', 'staff_b', 'no_profile'] loop
    insert into auth.users(id, email) values (gen_random_uuid(), 't423s-' || k || '@sig.invalid') returning id into v;
    insert into fx values (k, v);
  end loop;
  insert into public.profiles(id, full_name, email, role, is_active)
  select x.id, 'T423S ' || x.k, 't423s-' || x.k || '@sig.invalid', x.role::public.user_role, true
    from (values (pg_temp.fx('manager'), 'manager', 'manager'), (pg_temp.fx('staff'), 'staff', 'staff'),
                 (pg_temp.fx('staff_b'), 'staff_b', 'staff')) x(id, k, role);
  insert into public.stores(name, code) values ('T423S Store A', 'T423SA') returning id into v;
  insert into fx values ('store_a', v);
  insert into public.stores(name, code) values ('T423S Store B', 'T423SB') returning id into v;
  insert into fx values ('store_b', v);
  insert into public.user_store_assignments(user_id, store_id)
  values (pg_temp.fx('manager'), pg_temp.fx('store_a')), (pg_temp.fx('manager'), pg_temp.fx('store_b')),
         (pg_temp.fx('staff'), pg_temp.fx('store_a')), (pg_temp.fx('staff_b'), pg_temp.fx('store_b'));
  insert into public.customers(full_name, phone, email) values ('T423S Customer One', '+6591234601', 't423s-c1@sig.invalid') returning id into v;
  insert into fx values ('c1', v);
  insert into public.customers(full_name, phone, email) values ('T423S Customer Two', '+6591234602', 't423s-c2@sig.invalid') returning id into v;
  insert into fx values ('c2', v);
  insert into public.customers(full_name, phone, email) values ('T423S Customer Three', '+6591234603', 't423s-c3@sig.invalid') returning id into v;
  insert into fx values ('c3', v);
  insert into public.credit_packages(name, customer_price, paid_credit_amount, is_active, grants_reward)
  values ('T423S Credit 1000', 1000, 1000, true, false) returning id into v;
  insert into fx values ('cp', v);
  insert into public.credit_packages(name, customer_price, paid_credit_amount, is_active, grants_reward)
  values ('T423S Credit 1000 other', 1000, 1000, true, false) returning id into v;
  insert into fx values ('cp2', v);
  insert into public.vouchers(name, code, voucher_kind, selling_price) values ('T423S Free session', 'T423S-FREE', 'normal', 50)
    returning id into v;
  insert into fx values ('voucher', v);
  insert into public.premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, is_active)
  values ('T423S Bundle 500', 500, 500, 100, 2, true) returning id into v;
  insert into fx values ('pb', v);
  insert into public.premium_bundle_vouchers(bundle_id, voucher_id) values (pg_temp.fx('pb'), pg_temp.fx('voucher'));
  insert into public.premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, is_active)
  values ('T423S Bundle 500 other', 500, 500, 100, 2, true) returning id into v;
  insert into fx values ('pb2', v);
  insert into public.premium_bundle_vouchers(bundle_id, voucher_id) values (pg_temp.fx('pb2'), pg_temp.fx('voucher'));
end $$;

-- ── 1. Before 423 ───────────────────────────────────────────────────────────
savepoint before423;
do $$
declare a jsonb; b jsonb;
begin
  perform pg_temp.as_login('staff');
  a := public.create_split_credit_package_invoices(pg_temp.fx('store_a'), pg_temp.fx('cp'), pg_temp.cp_alloc(), null, null, null);
  b := public.create_split_credit_package_invoices(pg_temp.fx('store_a'), pg_temp.fx('cp'), pg_temp.cp_alloc(), null, null, null);
  perform pg_temp.as_login('server');
  perform pg_temp.check(a ->> 'split_group_id' <> b ->> 'split_group_id' and pg_temp.n_invoices() = 4,
    'before 423: pressing "Create invoices" again makes a second group, 4 unpaid invoices for one sale');
end $$;
rollback to savepoint before423;

-- ── 2. 423 ──────────────────────────────────────────────────────────────────
\ir ../../../supabase/423_vouchers_services_prices_and_splits.sql
reset role;
select set_config('request.jwt.claims', '', true);

-- Credit package: the answer is lost, the same request is sent again.
do $$
declare r uuid := gen_random_uuid(); a jsonb; b jsonb;
begin
  perform pg_temp.as_login('staff');
  a := public.create_split_credit_package_invoices(pg_temp.fx('store_a'), pg_temp.fx('cp'), pg_temp.cp_alloc(), null, null, 'T423S note', r);
  b := public.create_split_credit_package_invoices(pg_temp.fx('store_a'), pg_temp.fx('cp'), pg_temp.cp_alloc(), null, null, 'T423S note', r);
  perform pg_temp.as_login('server');
  perform pg_temp.check(jsonb_array_length(a -> 'invoices') = 2 and not (a ? 'replayed') and pg_temp.n_invoices() = 2,
    'credit package: the first call makes the sale (2 invoices)');
  perform pg_temp.check((b ->> 'replayed')::boolean and b ->> 'split_group_id' = a ->> 'split_group_id',
    'credit package: the same request again answers with the same sale, marked replayed');
  perform pg_temp.check(b - 'replayed' = a,
    'credit package: the replayed answer is the first answer exactly (same keys, invoices, numbers and amounts)');
  perform pg_temp.check(pg_temp.n_invoices() = 2
                        and (select count(*) from public.credit_package_split_groups where store_id = pg_temp.fx('store_a')) = 1
                        and (select count(*) from public.credit_package_split_allocations x
                               join public.credit_package_split_groups g on g.id = x.split_group_id
                              where g.store_id = pg_temp.fx('store_a')) = 2,
    'credit package: still one group, two allocations and two invoices');
  perform pg_temp.check((select request_id from public.credit_package_split_groups where id = (a ->> 'split_group_id')::uuid) = r,
    'credit package: the group keeps the request id');
  insert into fx values ('cp_req', r), ('cp_group', (a ->> 'split_group_id')::uuid);

  -- The same id for another package, or at another store, is refused.
  perform pg_temp.as_login('manager');
  perform pg_temp.check(pg_temp.refused(format('select public.create_split_credit_package_invoices(%L, %L, %L::jsonb, null, null, null, %L)',
                          pg_temp.fx('store_a'), pg_temp.fx('cp2'), pg_temp.cp_alloc(), r))
                        like '%This request was already used for another sale%',
    'credit package: the id cannot be used for another package');
  perform pg_temp.check(pg_temp.refused(format('select public.create_split_credit_package_invoices(%L, %L, %L::jsonb, null, null, null, %L)',
                          pg_temp.fx('store_b'), pg_temp.fx('cp'), pg_temp.cp_alloc(), r))
                        like '%This request was already used for another sale%',
    'credit package: the id cannot be used at another store');
  -- The same id, package and store, but another sale: other customers, other
  -- amounts, other reward vouchers. Refused; the first sale is not shown.
  perform pg_temp.check(pg_temp.refused(format('select public.create_split_credit_package_invoices(%L, %L, %L::jsonb, null, null, null, %L)',
                          pg_temp.fx('store_a'), pg_temp.fx('cp'),
                          jsonb_set(pg_temp.cp_alloc(), '{1,customer_id}', to_jsonb(pg_temp.fx('c3'))), r))
                        like 'P0001: This request was already used for another sale%',
    'credit package: the id cannot be used for other customers');
  perform pg_temp.check(pg_temp.refused(format('select public.create_split_credit_package_invoices(%L, %L, %L::jsonb, null, null, null, %L)',
                          pg_temp.fx('store_a'), pg_temp.fx('cp'),
                          jsonb_set(jsonb_set(pg_temp.cp_alloc(), '{0,payment_amount}', '500'), '{1,payment_amount}', '500'), r))
                        like 'P0001: This request was already used for another sale%',
    'credit package: the id cannot be used for other amounts');
  perform pg_temp.check(pg_temp.refused(format('select public.create_split_credit_package_invoices(%L, %L, %L::jsonb, null, null, null, %L)',
                          pg_temp.fx('store_a'), pg_temp.fx('cp'),
                          jsonb_set(pg_temp.cp_alloc(), '{0,reward_voucher_qty}', '1'), r))
                        like 'P0001: This request was already used for another sale%',
    'credit package: the id cannot be used for other reward vouchers');
  b := public.create_split_credit_package_invoices(pg_temp.fx('store_a'), pg_temp.fx('cp'),
         jsonb_build_array(pg_temp.cp_alloc() -> 1, jsonb_set(pg_temp.cp_alloc() -> 0, '{payment_amount}', '"600.00"')),
         null, null, null, r);
  perform pg_temp.check((b ->> 'replayed')::boolean and b - 'replayed' = a,
    'credit package: the same customers and amounts in another order (600 sent as "600.00") are the same sale, replayed');
  perform pg_temp.as_login('server');
  perform pg_temp.check(pg_temp.n_invoices() = 2, 'credit package: the refusals made nothing');
end $$;

-- A failed first try leaves nothing behind, so the retry with the same id
-- makes the sale.
do $$
declare r uuid := gen_random_uuid(); b jsonb; v_bad jsonb;
begin
  v_bad := jsonb_set(pg_temp.cp_alloc(), '{1,payment_amount}', '300');   -- totals 900, not 1000
  perform pg_temp.as_login('staff');
  perform pg_temp.check(pg_temp.refused(format('select public.create_split_credit_package_invoices(%L, %L, %L::jsonb, null, null, null, %L)',
                          pg_temp.fx('store_a'), pg_temp.fx('cp'), v_bad, r))
                        like '%They must match exactly%',
    'a split whose payments do not add up is refused');
  b := public.create_split_credit_package_invoices(pg_temp.fx('store_a'), pg_temp.fx('cp'), pg_temp.cp_alloc(), null, null, null, r);
  perform pg_temp.as_login('server');
  perform pg_temp.check(not (b ? 'replayed') and pg_temp.n_invoices() = 4,
    'the corrected retry with the same id makes the sale (it was not made before)');
end $$;

-- No request id: as before, each call is a new sale (the live page until the
-- new one is deployed sends none).
do $$
declare a jsonb; b jsonb;
begin
  perform pg_temp.as_login('staff');
  a := public.create_split_credit_package_invoices(pg_temp.fx('store_a'), pg_temp.fx('cp'), pg_temp.cp_alloc(), null, null, null);
  b := public.create_split_credit_package_invoices(p_store_id => pg_temp.fx('store_a'), p_credit_package_id => pg_temp.fx('cp'),
         p_allocations => pg_temp.cp_alloc(), p_service_staff => null, p_affiliate_id => null, p_notes => null);
  perform pg_temp.as_login('server');
  perform pg_temp.check(a ->> 'split_group_id' <> b ->> 'split_group_id' and pg_temp.n_invoices() = 8
                        and (select count(*) from public.credit_package_split_groups where request_id is null) = 2,
    'no request id (six arguments, by position or by name): each call is a sale, as before');
end $$;

-- The table itself holds one group per request id.
do $$
begin
  perform pg_temp.check(pg_temp.refused(format(
      'insert into public.credit_package_split_groups (store_id, credit_package_id, package_name_snapshot, package_price_snapshot, '
      'paid_credit_total_snapshot, bonus_credit_total_snapshot, reward_voucher_total_snapshot, customer_count, request_id) '
      'values (%L, %L, %L, 1000, 1000, 0, 0, 2, %L)', pg_temp.fx('store_a'), pg_temp.fx('cp'), 'T423S dup', pg_temp.fx('cp_req')))
                        like '23505:%credit_package_split_groups_request_id_key%',
    'a second group with the same request id breaks the unique index');
end $$;

-- Premium bundle: the same, with the free vouchers chosen per customer.
do $$
declare r uuid := gen_random_uuid(); a jsonb; b jsonb; n0 bigint := pg_temp.n_invoices();
begin
  perform pg_temp.as_login('staff');
  a := public.create_split_premium_bundle_invoices(pg_temp.fx('store_a'), pg_temp.fx('pb'), pg_temp.pb_alloc(), null, null, null, r);
  b := public.create_split_premium_bundle_invoices(pg_temp.fx('store_a'), pg_temp.fx('pb'), pg_temp.pb_alloc(), null, null, null, r);
  perform pg_temp.as_login('server');
  perform pg_temp.check(jsonb_array_length(a -> 'invoices') = 2 and pg_temp.n_invoices() = n0 + 2,
    'premium bundle: the first call makes the sale (2 invoices)');
  perform pg_temp.check((b ->> 'replayed')::boolean and b - 'replayed' = a,
    'premium bundle: the same request again answers with the first answer exactly, marked replayed');
  perform pg_temp.check((select count(*) from public.premium_bundle_split_groups where request_id = r) = 1
                        and (select sum(voucher_qty) from public.premium_bundle_split_allocations x
                              where x.split_group_id = (a ->> 'split_group_id')::uuid) = 2,
    'premium bundle: one group, the two free vouchers allocated once');
  perform pg_temp.as_login('staff');
  perform pg_temp.check(pg_temp.refused(format('select public.create_split_premium_bundle_invoices(%L, %L, %L::jsonb, null, null, null, %L)',
                          pg_temp.fx('store_a'), pg_temp.fx('pb2'), pg_temp.pb_alloc(), r))
                        like '%This request was already used for another sale%',
    'premium bundle: the id cannot be used for another bundle');
  perform pg_temp.check(pg_temp.refused(format('select public.create_split_premium_bundle_invoices(%L, %L, %L::jsonb, null, null, null, %L)',
                          pg_temp.fx('store_a'), pg_temp.fx('pb'),
                          jsonb_set(pg_temp.pb_alloc(), '{0,customer_id}', to_jsonb(pg_temp.fx('c3'))), r))
                        like 'P0001: This request was already used for another sale%',
    'premium bundle: the id cannot be used for other customers');
  perform pg_temp.check(pg_temp.refused(format('select public.create_split_premium_bundle_invoices(%L, %L, %L::jsonb, null, null, null, %L)',
                          pg_temp.fx('store_a'), pg_temp.fx('pb'),
                          jsonb_set(jsonb_set(pg_temp.pb_alloc(), '{0,payment_amount}', '250'), '{1,payment_amount}', '250'), r))
                        like 'P0001: This request was already used for another sale%',
    'premium bundle: the id cannot be used for other amounts');
  perform pg_temp.check(pg_temp.refused(format('select public.create_split_premium_bundle_invoices(%L, %L, %L::jsonb, null, null, null, %L)',
                          pg_temp.fx('store_a'), pg_temp.fx('pb'),
                          jsonb_set(jsonb_set(pg_temp.pb_alloc(), '{0,voucher_selection,0,quantity}', '2'),
                                    '{1,voucher_selection}', '[]'), r))
                        like 'P0001: This request was already used for another sale%',
    'premium bundle: the id cannot be used for another share of the free vouchers');
  b := public.create_split_premium_bundle_invoices(pg_temp.fx('store_a'), pg_temp.fx('pb'),
         jsonb_build_array(pg_temp.pb_alloc() -> 1, pg_temp.pb_alloc() -> 0), null, null, null, r);
  perform pg_temp.check((b ->> 'replayed')::boolean and b - 'replayed' = a,
    'premium bundle: the same customers, amounts and vouchers in another order are the same sale, replayed');
  perform pg_temp.check(pg_temp.refused(format('select public.create_split_premium_bundle_invoices(%L, %L, %L::jsonb, null, null, null, %L)',
                          pg_temp.fx('store_b'), pg_temp.fx('pb'), pg_temp.pb_alloc(), r)) like '42501:%',
    'premium bundle: Staff of Store A cannot use Store B (42501)');
  perform pg_temp.as_login('staff_b');
  perform pg_temp.check(pg_temp.refused(format('select public.create_split_premium_bundle_invoices(%L, %L, %L::jsonb, null, null, null, %L)',
                          pg_temp.fx('store_b'), pg_temp.fx('pb'), pg_temp.pb_alloc(), r))
                        like '%This request was already used for another sale%',
    'premium bundle: the id cannot be used at another store');
  perform pg_temp.as_login('server');
  perform pg_temp.check(pg_temp.refused(format(
      'insert into public.premium_bundle_split_groups (store_id, premium_bundle_id, bundle_name_snapshot, payment_snapshot, '
      'paid_credit_total_snapshot, bonus_credit_total_snapshot, free_voucher_total_snapshot, customer_count, request_id) '
      'values (%L, %L, %L, 500, 500, 100, 2, 2, %L)', pg_temp.fx('store_a'), pg_temp.fx('pb'), 'T423S dup', r))
                        like '23505:%premium_bundle_split_groups_request_id_key%',
    'premium bundle: a second group with the same request id breaks the unique index');
  perform pg_temp.check(pg_temp.n_invoices() = n0 + 2, 'premium bundle: the refusals made nothing');
end $$;

-- Who may call: active staff of the store. A replay is refused to anyone else.
do $$
declare k text;
begin
  foreach k in array array['staff_b', 'no_profile', 'nobody'] loop
    perform pg_temp.as_login(k);
    perform pg_temp.check(pg_temp.refused(format('select public.create_split_credit_package_invoices(%L, %L, %L::jsonb, null, null, null, %L)',
                            pg_temp.fx('store_a'), pg_temp.fx('cp'), pg_temp.cp_alloc(), pg_temp.fx('cp_req'))) like '42501:%',
      format('%s cannot make or replay a split at Store A (42501)', k));
  end loop;
  perform pg_temp.as_login('anon');
  perform pg_temp.check(pg_temp.refused(format('select public.create_split_credit_package_invoices(%L, %L, %L::jsonb, null, null, null, %L)',
                          pg_temp.fx('store_a'), pg_temp.fx('cp'), pg_temp.cp_alloc(), pg_temp.fx('cp_req'))) like '42501:%',
    'the anon key cannot call the split (42501)');
  perform pg_temp.as_login('server');
  perform pg_temp.check(
    (select string_agg(p.oid::regprocedure::text, ', ' order by 1) from pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname in ('create_split_credit_package_invoices', 'create_split_premium_bundle_invoices'))
    = 'create_split_credit_package_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid), create_split_premium_bundle_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)',
    'one function of each name: the six-argument versions are gone');
  perform pg_temp.check(has_function_privilege('authenticated', 'public.create_split_credit_package_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)', 'execute')
                        and has_function_privilege('service_role', 'public.create_split_premium_bundle_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)', 'execute')
                        and not has_function_privilege('anon', 'public.create_split_premium_bundle_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)', 'execute'),
    'granted as before: signed-in logins and the service role, not anon');
end $$;

rollback;
