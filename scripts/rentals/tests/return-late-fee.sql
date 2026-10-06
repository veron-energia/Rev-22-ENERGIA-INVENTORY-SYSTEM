-- 395 + 396 + 397: a rental's Return, with an optional late fee invoiced and paid at once.
--
-- The Owner's rules of 6 Oct 2026: a late return offers "No late fee" (the
-- default, no reason) or "Charge late fee"; the days start at the days late and
-- may only be fewer; the daily rate is typed and more than S$0; an optional
-- discount, S$ or %, needs a reason; the fee after it is more than S$0; it is
-- paid at the return by one method that is not wallet credit; one transaction
-- records the return and an invoice of its own (normal INV number, the
-- rental's store or one staff choose for an old-style rental, the rental's
-- customer, dated the return date, one late-fee line with the discount as its
-- Discount), paid at once and linked to the rental; no commission of any kind;
-- Return is Owner/Manager only; ticked, the unit goes back into real stock
-- where it came from, once, unticked nowhere, a lost unit never; an old-style
-- rental goes back into the old special stock pay_rental took it from (never
-- warehouse stock), and one with no warehouse product moves nothing without
-- failing; "Returned on" counts the days; the late-fee line takes no stock,
-- cannot be added, changed or removed through the invoice, gets no affiliate,
-- its payment is corrected on the payment, and its invoice refunds and
-- cancels as any other; it is revenue in "Sales by Service Staff" credited to
-- no one, and no item on the Dashboard. 397 revokes the old Return.
--
-- Disposable local database only; everything is rolled back. The migrations
-- are applied inside this transaction, so run the file on its own:
--   psql -v ON_ERROR_STOP=1 -f scripts/rentals/tests/return-late-fee.sql
-- On a local database that has drifted from production, pass a file that
-- installs production's functions, run right after the begin below:
--   psql -v ON_ERROR_STOP=1 -v prelude=/path/to/prod_prelude.sql -f ...
-- Where 395 is not committed yet, its value cannot be used in the same
-- transaction; the block after the prelude moves invoice_items.line_kind onto
-- a copy of the enum made in this transaction, so 395 adds the value to the
-- copy, and the rollback puts everything back. Where 395 is committed it does
-- nothing.
-- Every name, phone, number and amount here is invented.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif

do $swap$
declare v_labels text; c record; v_cons text[] := '{}'; v_names text[] := '{}'; k int;
begin
  if exists (select 1 from pg_enum e where e.enumtypid = 'public.invoice_line_kind'::regtype and e.enumlabel = 'late_fee') then
    return;
  end if;
  select string_agg(quote_literal(e.enumlabel), ',' order by e.enumsortorder) into v_labels
    from pg_enum e where e.enumtypid = 'public.invoice_line_kind'::regtype;
  for c in select conname, pg_get_constraintdef(oid) as def from pg_constraint
            where conrelid = 'public.invoice_items'::regclass and pg_get_constraintdef(oid) like '%invoice_line_kind%'
  loop
    v_names := v_names || c.conname::text; v_cons := v_cons || c.def;
    execute format('alter table public.invoice_items drop constraint %I', c.conname);
  end loop;
  alter table public.invoice_items alter column line_kind drop default;
  alter type public.invoice_line_kind rename to invoice_line_kind_committed;
  execute 'create type public.invoice_line_kind as enum (' || v_labels || ')';
  alter table public.invoice_items alter column line_kind type public.invoice_line_kind
    using line_kind::text::public.invoice_line_kind;
  alter table public.invoice_items alter column line_kind set default 'product'::public.invoice_line_kind;
  for k in 1 .. coalesce(array_length(v_names, 1), 0) loop
    execute format('alter table public.invoice_items add constraint %I %s', v_names[k], v_cons[k]);
  end loop;
end $swap$;

\ir ../../../supabase/395_late_fee_line_kind.sql
\ir ../../../supabase/396_rental_return_late_fee.sql

-- ===== 1. The migrations re-run as no-ops =====
create temp table t396_before as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5,
         coalesce(array_to_string(p.proacl, ','), '') as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace;
create temp table t396_cols_before as
  select column_name, data_type from information_schema.columns
   where table_schema = 'public' and table_name = 'rentals';
\ir ../../../supabase/395_late_fee_line_kind.sql
\ir ../../../supabase/396_rental_return_late_fee.sql
do $$
begin
  if exists (select 1 from pg_proc p left join t396_before b on b.fn = p.oid::regprocedure::text
              where p.pronamespace = 'public'::regnamespace
                and (b.fn is null or b.md5 <> md5(pg_get_functiondef(p.oid))
                     or b.acl <> coalesce(array_to_string(p.proacl, ','), ''))) then
    raise exception 'FAIL 1: a second run of 395 and 396 changed a function or a grant'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'rentals')
     <> (select count(*) from t396_cols_before) then
    raise exception 'FAIL 1: a second run changed the rentals columns'; end if;
  if (select count(*) from pg_enum where enumtypid = 'public.invoice_line_kind'::regtype and enumlabel = 'late_fee') <> 1 then
    raise exception 'FAIL 1: late_fee is not one value of invoice_line_kind'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.invoice_items'::regclass
        and tgname = 'invoice_item_late_fee_guard' and not tgisinternal) <> 1 then
    raise exception 'FAIL 1: the late-fee guard is not on invoice_items once'; end if;
  raise notice 'PASS 1: a second run of 395 and 396 changes no function, grant, column, value or trigger';
end $$;

-- ===== 2. Grants, and 397 =====
do $$
declare sig text := 'public.return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text)';
begin
  if not has_function_privilege('authenticated', sig, 'execute') or has_function_privilege('anon', sig, 'execute') then
    raise exception 'FAIL 2: the Return is not staff-only'; end if;
  if exists (select 1 from unnest(array['public.invoice_is_late_fee(uuid)', 'public.rental_put_back_stock(uuid)',
               'public.trg_invoice_item_late_fee_guard()', 'public.return_rental_to_warehouse(uuid)']) f
              where has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute')) then
    raise exception 'FAIL 2: an internal helper is callable by a client role'; end if;
  -- Until 397 the page live before the deploy keeps its Return.
  if not has_function_privilege('authenticated', 'public.return_rental(uuid,return_condition,boolean,uuid,text,text)', 'execute') then
    raise exception 'FAIL 2: 396 took the old Return away before the new page is deployed'; end if;
end $$;
create temp table t397_before as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5
    from pg_proc p where p.pronamespace = 'public'::regnamespace;
\ir ../../../supabase/397_old_rental_return_revoked.sql
create temp table t397_acl as
  select p.oid::regprocedure::text as fn, coalesce(array_to_string(p.proacl, ','), '') as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace;
\ir ../../../supabase/397_old_rental_return_revoked.sql
do $$
declare sig text := 'public.return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text)';
begin
  if has_function_privilege('authenticated', 'public.return_rental(uuid,return_condition,boolean,uuid,text,text)', 'execute')
     or has_function_privilege('anon', 'public.return_rental(uuid,return_condition,boolean,uuid,text,text)', 'execute') then
    raise exception 'FAIL 2: after 397 the old Return is still callable by a client role'; end if;
  if not has_function_privilege('authenticated', sig, 'execute') then
    raise exception 'FAIL 2: 397 took the new Return away'; end if;
  if exists (select 1 from pg_proc p left join t397_before b on b.fn = p.oid::regprocedure::text
              where p.pronamespace = 'public'::regnamespace and (b.fn is null or b.md5 <> md5(pg_get_functiondef(p.oid)))) then
    raise exception 'FAIL 2: 397 changed a function''s text'; end if;
  if exists (select 1 from pg_proc p join t397_acl a on a.fn = p.oid::regprocedure::text
              where p.pronamespace = 'public'::regnamespace and a.acl <> coalesce(array_to_string(p.proacl, ','), '')) then
    raise exception 'FAIL 2: a second run of 397 changed a grant'; end if;
  raise notice 'PASS 2: the Return is granted to staff (it checks the role) and to no one signed out; the helpers to no client role; the old Return stays callable after 396 and is revoked by 397, which changes no text and re-runs as a no-op';
end $$;

-- ===== Fixtures =====
create temp table t396(k text primary key, id uuid);

create function pg_temp.t396_id(p_k text) returns uuid language sql as $f$
  select id from t396 where k = p_k
$f$;

create function pg_temp.t396_as(p_k text) returns void language sql as $f$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.t396_id(p_k)::text, 'role', 'authenticated')::text, true);
  select set_config('request.jwt.claim.sub', pg_temp.t396_id(p_k)::text, true);
$f$;

-- A paid invoice in Store A renting the machine for p_days days; the rental
-- it raises (waiting for a warehouse).
create function pg_temp.t396_rental(p_qty int default 1, p_days int default 2) returns uuid language plpgsql as $f$
declare v_inv uuid; v_r uuid;
begin
  v_inv := public.create_invoice(pg_temp.t396_id('store_a'), pg_temp.t396_id('customer'), null,
    jsonb_build_array(jsonb_build_object('kind', 'rental', 'special_product_id', pg_temp.t396_id('special'),
      'quantity', p_qty, 'rental_rate_type', 'day', 'rental_periods', p_days)));
  perform public.pay_invoice(v_inv, jsonb_build_array(jsonb_build_object(
    'payment_method_id', pg_temp.t396_id('cash'), 'amount', public.invoice_charge_total(v_inv))));
  select id into v_r from public.rentals where invoice_id = v_inv;
  if v_r is null then raise exception 'FIXTURE: the paid rental invoice raised no rental'; end if;
  return v_r;
end $f$;

-- Released from a store or the warehouse, and its dates moved so it started
-- p_started days ago and was due back p_due days from today (negative: past).
create function pg_temp.t396_out(p_rental uuid, p_where text, p_started int, p_due int) returns uuid language plpgsql as $f$
begin
  perform public.fulfil_special_doc('rental', p_rental,
    pg_temp.t396_id(case when p_where = 'store' then 'store_b' else 'warehouse' end), p_where);
  update public.rentals set start_date = public.sg_today() - p_started,
                            expected_return_date = public.sg_today() + p_due
   where id = p_rental;
  return p_rental;
end $f$;

create function pg_temp.t396_wh() returns int language sql as $f$
  select coalesce((select current_qty from public.warehouse_inventory
                    where warehouse_id = pg_temp.t396_id('warehouse') and product_id = pg_temp.t396_id('product')), 0)
$f$;
create function pg_temp.t396_st() returns int language sql as $f$
  select coalesce((select current_qty from public.store_inventory
                    where store_id = pg_temp.t396_id('store_b') and product_id = pg_temp.t396_id('product')), 0)
$f$;
create function pg_temp.t396_moves(p_rental uuid) returns int language sql as $f$
  select count(*)::int from public.stock_movements
   where notes like 'Rental returned — ' || (select rental_no from public.rentals where id = p_rental) || '%'
$f$;

-- Runs p_sql and expects it to be refused with a message containing p_like.
create function pg_temp.t396_refused(p_label text, p_sql text, p_like text) returns void language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm not like '%' || p_like || '%' then
      raise exception 'FAIL %: refused, but with "%" (expected "%")', p_label, sqlerrm, p_like; end if;
    return;
  end;
  raise exception 'FAIL %: was not refused', p_label;
end $f$;

do $$
declare o uuid := gen_random_uuid(); s uuid := gen_random_uuid(); m uuid := gen_random_uuid();
  sa uuid; sb uuid; wh uuid; c uuid; ref uuid; p uuid; sp uuid; spx uuid;
begin
  insert into auth.users(id, email) values (o, 'owner396@sig.invalid'), (s, 'staff396@sig.invalid'), (m, 'manager396@sig.invalid');
  insert into public.profiles(id, full_name, email, role, is_active) values
    (o, 'Fixture Owner', 'owner396@sig.invalid', 'owner', true),
    (s, 'Fixture Staff', 'staff396@sig.invalid', 'staff', true),
    (m, 'Fixture Manager', 'manager396@sig.invalid', 'manager', true);
  insert into t396 values ('owner', o), ('staff', s), ('manager', m);
  perform pg_temp.t396_as('owner');
  insert into public.stores(name, code, country_code) values ('Fixture Store 396 A', 'T396A', 'SG') returning id into sa;
  insert into public.stores(name, code, country_code) values ('Fixture Store 396 B', 'T396B', 'SG') returning id into sb;
  insert into public.warehouses(name, code) values ('Fixture Warehouse 396', 'T396W') returning id into wh;
  -- Store A's staff share its staff commission (the control below).
  insert into public.user_store_assignments(user_id, store_id) values (s, sa), (m, sa), (m, sb);
  insert into t396 values ('store_a', sa), ('store_b', sb), ('warehouse', wh);
  with x as (insert into public.payment_methods(name, is_active) values ('Fixture Cash 396', true) returning id)
    insert into t396 select 'cash', id from x;
  with x as (insert into public.payment_methods(name, is_active, is_wallet_credit, wallet_category)
               values ('Fixture Wallet 396', true, true, 'paid') returning id)
    insert into t396 select 'wallet', id from x;
  with x as (insert into public.payment_methods(name, is_active) values ('Fixture Old Card 396', false) returning id)
    insert into t396 select 'old_card', id from x;
  with x as (insert into public.payment_methods(name, is_active) values ('Fixture Card 396', true) returning id)
    insert into t396 select 'card', id from x;
  -- John Lim referred Jane Tan, so an ordinary invoice of hers earns him
  -- commission (blocked: he is no affiliate), the control for "none".
  insert into public.customers(full_name, phone) values ('John Lim', '+6591395002') returning id into ref;
  insert into public.customers(full_name, phone, referred_by) values ('Jane Tan', '+6591395001', ref) returning id into c;
  insert into t396 values ('customer', c), ('referrer', ref);
  -- An active affiliate, for the correction that must not name one.
  with x as (insert into public.customer_affiliates(customer_id, store_id, status, referral_code)
               values (ref, sa, 'active', 'T396AFF') returning id)
    insert into t396 select 'affiliate', id from x;
  insert into public.products(name, sku, product_type) values ('Fixture Machine 396', 'T396-M', 'own') returning id into p;
  insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (wh, p, 10);
  insert into public.store_inventory(store_id, product_id, current_qty) values (sb, p, 4);
  -- No late fee of its own, as every active special product in production.
  sp := public.upsert_special_product_from_product(null, p, 300, 30, null, null, null, 0);
  -- An old special product, deleted, never a warehouse product.
  insert into public.special_products(name, sku, rate_day, is_active, deleted_at)
    values ('Fixture Old Machine 396', 'T396-OLD', 20, false, now()) returning id into spx;
  insert into t396 values ('product', p), ('special', sp), ('old_special', spx);
end $$;

-- ===== 3. No late fee, ticked: back where it came from, once =====
do $$
declare r uuid; st0 int; wh0 int; x jsonb;
begin
  perform pg_temp.t396_as('owner');
  -- Released from Store B, on time.
  r := pg_temp.t396_out(pg_temp.t396_rental(), 'store', 1, 1);
  st0 := pg_temp.t396_st(); wh0 := pg_temp.t396_wh();
  x := public.return_rental_with_fee(p_rental_id => r, p_condition => 'good', p_return_stock => true);
  if pg_temp.t396_st() <> st0 + 1 or pg_temp.t396_wh() <> wh0 then
    raise exception 'FAIL 3a: a store release did not go back to its store (store % -> %, warehouse % -> %)',
      st0, pg_temp.t396_st(), wh0, pg_temp.t396_wh(); end if;
  if pg_temp.t396_moves(r) <> 1 or not exists (select 1 from public.stock_movements
        where notes like 'Rental returned — %' and to_store_id = pg_temp.t396_id('store_b')
          and product_id = pg_temp.t396_id('product') and quantity = 1
          and movement_type::text = 'invoice_cancel_return' and invoice_id is null) then
    raise exception 'FAIL 3a: the store return has no single stock movement into the store'; end if;
  if (select (status::text, stock_returned, late_days, late_fee_total, late_fee_invoice_id, late_fee_waived, return_condition::text)
        from public.rentals where id = r) is distinct from ('returned'::text, true, 0, 0::numeric, null::uuid, null::boolean, 'good'::text) then
    raise exception 'FAIL 3a: the store return was recorded as %', (select to_jsonb(x2) from public.rentals x2 where id = r); end if;
  if (x->>'restocked_quantity')::int <> 1 or x->>'stock_location_type' <> 'store' or x->>'invoice_id' is not null then
    raise exception 'FAIL 3a: the Return answered %', x; end if;
  if exists (select 1 from public.special_product_stock where special_product_id = pg_temp.t396_id('special')) then
    raise exception 'FAIL 3a: the retired special_product_stock was written'; end if;
  if not exists (select 1 from public.audit_logs where record_id = r and action = 'rental_returned') then
    raise exception 'FAIL 3a: no audit row'; end if;

  -- Released from the warehouse.
  r := pg_temp.t396_out(pg_temp.t396_rental(), 'warehouse', 1, 1);
  st0 := pg_temp.t396_st(); wh0 := pg_temp.t396_wh();
  perform public.return_rental_with_fee(p_rental_id => r, p_condition => 'good', p_return_stock => true);
  if pg_temp.t396_wh() <> wh0 + 1 or pg_temp.t396_st() <> st0 or pg_temp.t396_moves(r) <> 1 then
    raise exception 'FAIL 3b: a warehouse release did not go back to its warehouse once'; end if;

  -- Unticked (lost): nothing moves, and the trigger does not put it back.
  r := pg_temp.t396_out(pg_temp.t396_rental(), 'warehouse', 1, 1);
  wh0 := pg_temp.t396_wh(); st0 := pg_temp.t396_st();
  perform public.return_rental_with_fee(p_rental_id => r, p_condition => 'lost', p_return_stock => false);
  if pg_temp.t396_wh() <> wh0 or pg_temp.t396_st() <> st0 or pg_temp.t396_moves(r) <> 0
     or (select stock_returned from public.rentals where id = r) is distinct from false then
    raise exception 'FAIL 3c: an unticked return moved stock'; end if;

  -- Lost and ticked: refused, nothing moves.
  r := pg_temp.t396_out(pg_temp.t396_rental(), 'warehouse', 1, 1);
  wh0 := pg_temp.t396_wh();
  perform pg_temp.t396_refused('3d', format(
    'select public.return_rental_with_fee(p_rental_id => %L, p_condition => ''lost'', p_return_stock => true)', r),
    'A lost unit cannot go back into stock');
  if pg_temp.t396_wh() <> wh0 or (select status::text from public.rentals where id = r) <> 'active' then
    raise exception 'FAIL 3d: a refused lost-and-ticked return left something behind'; end if;

  -- Unticked, from a store.
  r := pg_temp.t396_out(pg_temp.t396_rental(), 'store', 1, 1);
  st0 := pg_temp.t396_st();
  perform public.return_rental_with_fee(p_rental_id => r, p_condition => 'damaged', p_return_stock => false);
  if pg_temp.t396_st() <> st0 or pg_temp.t396_moves(r) <> 0 then
    raise exception 'FAIL 3c: an unticked store return moved stock'; end if;
  raise notice 'PASS 3: ticked, a store release goes back to its store and a warehouse release to its warehouse, once, with one movement and never the retired table; unticked nothing moves; lost and ticked is refused';
end $$;

-- ===== 4. An old-style rental of a deleted special product: no stock, no error =====
do $$
declare r uuid; wh0 int; x jsonb;
begin
  perform pg_temp.t396_as('owner');
  insert into public.rentals(rental_no, special_product_id, warehouse_id, customer_id, quantity, rate_type,
    rate_amount, periods, rental_fee, start_date, expected_return_date, status, paid_at, payment_method_id)
  values ('RENT-2026-9001', pg_temp.t396_id('old_special'), pg_temp.t396_id('warehouse'), pg_temp.t396_id('customer'),
    1, 'day', 20, 3, 60, public.sg_today() - 3, public.sg_today(), 'active', now(), pg_temp.t396_id('cash'))
  returning id into r;
  insert into t396 values ('legacy_unlinked', r);
  wh0 := pg_temp.t396_wh();
  x := public.return_rental_with_fee(p_rental_id => r, p_condition => 'good', p_return_stock => true);
  if pg_temp.t396_wh() <> wh0 or pg_temp.t396_moves(r) <> 0
     or (select (status::text, stock_returned) from public.rentals where id = r) is distinct from ('returned'::text, false) then
    raise exception 'FAIL 4: the old-style return moved stock or was not recorded: %', x; end if;
  if (x->>'restocked_quantity')::int <> 0 or coalesce(x->>'stock_note', '') not like '%not a warehouse product%' then
    raise exception 'FAIL 4: the Return did not say there is no stock to put it back into: %', x; end if;
  raise notice 'PASS 4: an old-style rental of a deleted special product is returned without a stock change, saying why';
end $$;

-- ===== 5. "Returned on" =====
do $$
declare r uuid; d date;
begin
  perform pg_temp.t396_as('owner');
  -- Started 20 days ago, due back 12 days ago, returned 13 days ago: on time.
  r := pg_temp.t396_out(pg_temp.t396_rental(), 'warehouse', 20, -12);
  d := public.sg_today() - 13;
  perform pg_temp.t396_refused('5a', format(
    'select public.return_rental_with_fee(p_rental_id => %L, p_condition => ''good'', p_return_stock => true, p_returned_on => %L)',
    r, public.sg_today() + 1), 'cannot be in the future');
  perform pg_temp.t396_refused('5b', format(
    'select public.return_rental_with_fee(p_rental_id => %L, p_condition => ''good'', p_return_stock => true, p_returned_on => %L)',
    r, public.sg_today() - 21), 'before the rental started');
  perform public.return_rental_with_fee(p_rental_id => r, p_condition => 'good', p_return_stock => true, p_returned_on => d);
  if (select (late_days, late_fee_waived, (returned_at at time zone 'Asia/Singapore')::date, (returned_at at time zone 'UTC')::date)
        from public.rentals where id = r) is distinct from (0, null::boolean, d, d) then
    raise exception 'FAIL 5: a past on-time return was recorded as %',
      (select jsonb_build_object('late_days', late_days, 'returned_at', returned_at) from public.rentals where id = r); end if;
  -- Due back 5 days ago, returned 2 days ago: 3 days late, "No late fee".
  r := pg_temp.t396_out(pg_temp.t396_rental(), 'warehouse', 10, -5);
  perform public.return_rental_with_fee(p_rental_id => r, p_condition => 'good', p_return_stock => true,
    p_returned_on => public.sg_today() - 2);
  if (select (late_days, late_fee_waived, late_fee_total, late_fee_invoice_id) from public.rentals where id = r)
     is distinct from (3, true, 0::numeric, null::uuid) then
    raise exception 'FAIL 5: a late return with "No late fee" was not recorded as waived'; end if;
  raise notice 'PASS 5: the return date may not be in the future or before the start; the late days count to it; a late return with no fee is recorded as waived, needing no reason';
end $$;

-- ===== 6. Charge late fee: refusals =====
do $$
declare r uuid; q text;
begin
  perform pg_temp.t396_as('owner');
  r := pg_temp.t396_out(pg_temp.t396_rental(), 'warehouse', 10, -5);   -- 5 days late
  insert into t396 values ('late5', r);
  q := 'select public.return_rental_with_fee(p_rental_id => ''' || r || ''', p_condition => ''good'', p_return_stock => true, p_charge_late_fee => true';
  perform pg_temp.t396_refused('6a', q || ', p_late_days => 6, p_daily_rate => 10, p_payment_method_id => ''' || pg_temp.t396_id('cash') || ''')', 'between 1 and 5');
  perform pg_temp.t396_refused('6b', q || ', p_late_days => 0, p_daily_rate => 10, p_payment_method_id => ''' || pg_temp.t396_id('cash') || ''')', 'between 1 and 5');
  perform pg_temp.t396_refused('6c', q || ', p_daily_rate => 0, p_payment_method_id => ''' || pg_temp.t396_id('cash') || ''')', 'Type the daily late fee');
  perform pg_temp.t396_refused('6d', q || ', p_daily_rate => -5, p_payment_method_id => ''' || pg_temp.t396_id('cash') || ''')', 'Type the daily late fee');
  perform pg_temp.t396_refused('6e', q || ', p_payment_method_id => ''' || pg_temp.t396_id('cash') || ''')', 'Type the daily late fee');
  perform pg_temp.t396_refused('6f', q || ', p_daily_rate => 10, p_discount_type => ''manual'', p_discount_amount => 5, p_payment_method_id => ''' || pg_temp.t396_id('cash') || ''')', 'Give the reason');
  perform pg_temp.t396_refused('6g', q || ', p_daily_rate => 10, p_discount_type => ''percentage'', p_discount_percent => 10, p_discount_reason => ''  '', p_payment_method_id => ''' || pg_temp.t396_id('cash') || ''')', 'Give the reason');
  perform pg_temp.t396_refused('6h', q || ', p_daily_rate => 10, p_discount_type => ''manual'', p_discount_amount => 50, p_discount_reason => ''Regular customer'', p_payment_method_id => ''' || pg_temp.t396_id('cash') || ''')', 'more than S$0');
  perform pg_temp.t396_refused('6i', q || ', p_daily_rate => 10, p_discount_type => ''percentage'', p_discount_percent => 100, p_discount_reason => ''Regular customer'', p_payment_method_id => ''' || pg_temp.t396_id('cash') || ''')', 'more than S$0');
  perform pg_temp.t396_refused('6j', q || ', p_daily_rate => 10, p_discount_type => ''percentage'', p_discount_percent => 120, p_discount_reason => ''Regular customer'', p_payment_method_id => ''' || pg_temp.t396_id('cash') || ''')', 'at most 100');
  perform pg_temp.t396_refused('6k', q || ', p_daily_rate => 10, p_discount_type => ''voucher'', p_discount_reason => ''x'', p_payment_method_id => ''' || pg_temp.t396_id('cash') || ''')', 'amount (S$) or a percentage');
  perform pg_temp.t396_refused('6l', q || ', p_daily_rate => 10)', 'Choose how the late fee is paid');
  perform pg_temp.t396_refused('6m', q || ', p_daily_rate => 10, p_payment_method_id => ''' || pg_temp.t396_id('wallet') || ''')', 'Wallet credit cannot pay');
  perform pg_temp.t396_refused('6n', q || ', p_daily_rate => 10, p_payment_method_id => ''' || pg_temp.t396_id('old_card') || ''')', 'active payment method');
  -- Not late: nothing to charge.
  perform pg_temp.t396_refused('6o', q || ', p_returned_on => ''' || (public.sg_today() - 5) || ''', p_daily_rate => 10, p_payment_method_id => ''' || pg_temp.t396_id('cash') || ''')', 'not late');
  -- Only an Owner or Manager.
  perform pg_temp.t396_as('staff');
  perform pg_temp.t396_refused('6p', 'select public.return_rental_with_fee(p_rental_id => ''' || r || ''', p_condition => ''good'', p_return_stock => true)', 'Only an Owner or Manager');
  perform pg_temp.t396_as('owner');
  if (select status::text from public.rentals where id = r) <> 'active'
     or exists (select 1 from public.invoice_items where line_kind::text = 'late_fee') then
    raise exception 'FAIL 6: a refused Return left something behind'; end if;
  raise notice 'PASS 6: more days than late, no days, no rate or one of S$0 or less, a discount without a reason, a fee of S$0 or less after it, a percentage over 100, another kind of discount, no method, wallet credit, an inactive method, charging a return that is not late, and staff are all refused, leaving nothing behind';
end $$;

-- ===== 7. Charge late fee: fewer days, invoiced and paid at once =====
do $$
declare r uuid := pg_temp.t396_id('late5'); x jsonb; inv record; li record; wh0 int; n_moves int; v_ctl uuid;
begin
  perform pg_temp.t396_as('owner');
  wh0 := pg_temp.t396_wh();
  n_moves := (select count(*) from public.stock_movements);
  x := public.return_rental_with_fee(p_rental_id => r, p_condition => 'good', p_return_stock => true,
    p_charge_late_fee => true, p_late_days => 3, p_daily_rate => 12,
    p_payment_method_id => pg_temp.t396_id('cash'), p_payment_reference => 'RCPT-9001');
  select * into inv from public.invoices where id = (x->>'invoice_id')::uuid;
  if inv.id is null or inv.invoice_no is distinct from x->>'invoice_no' or inv.invoice_no not like 'INV-____-%' then
    raise exception 'FAIL 7: no late-fee invoice with an INV number: %', x; end if;
  if (inv.status::text, inv.store_id, inv.customer_id, inv.business_date, inv.affiliate_id, inv.affiliate_selection_explicit,
      inv.subtotal, inv.discount_total, inv.total_amount, inv.paid_amount)
     is distinct from ('paid'::text, pg_temp.t396_id('store_a'), pg_temp.t396_id('customer'), public.sg_today(), null::uuid, true,
                       36::numeric, 0::numeric, 36::numeric, 36::numeric) then
    raise exception 'FAIL 7: the late-fee invoice is %', to_jsonb(inv); end if;
  if (select count(*) from public.invoice_items where invoice_id = inv.id) <> 1 then
    raise exception 'FAIL 7: the late-fee invoice has other lines'; end if;
  select * into li from public.invoice_items where invoice_id = inv.id;
  if (li.line_kind::text, li.quantity, li.unit_price, li.line_total, li.line_discount, li.product_id, li.line_discount_type)
     is distinct from ('late_fee'::text, 3, 12::numeric, 36::numeric, 0::numeric, null::uuid, null::text)
     or li.item_name_snapshot <> 'Late return fee — ' || (select rental_no from public.rentals where id = r)
                                 || ' (Fixture Machine 396): 3 days × S$12.00'
     or public.invoice_line_label(li.id) <> li.item_name_snapshot then
    raise exception 'FAIL 7: the late-fee line is %', to_jsonb(li); end if;
  if (select count(*) from public.invoice_payments where invoice_id = inv.id) <> 1
     or not exists (select 1 from public.invoice_payments where invoice_id = inv.id and amount = 36
                     and payment_method_id = pg_temp.t396_id('cash') and payment_reference = 'RCPT-9001'
                     and effective_at is null and entry_kind = 'receipt') then
    raise exception 'FAIL 7: the late fee was not paid by the chosen method with its reference'; end if;
  if (select (late_fee_invoice_id, late_days, late_fee_days, late_fee_rate, late_fee_total, late_fee_waived,
              late_payment_method_id, late_payment_reference, status::text, stock_returned)
        from public.rentals where id = r)
     is distinct from (inv.id, 5, 3, 12::numeric, 36::numeric, false, pg_temp.t396_id('cash'), 'RCPT-9001'::text, 'returned'::text, true) then
    raise exception 'FAIL 7: the rental was recorded as %', (select to_jsonb(x2) from public.rentals x2 where id = r); end if;
  if pg_temp.t396_wh() <> wh0 + 1
     or (select count(*) from public.stock_movements) <> n_moves + 1
     or exists (select 1 from public.stock_movements where invoice_id = inv.id)
     or exists (select 1 from public.invoice_stock_components where invoice_item_id = li.id) then
    raise exception 'FAIL 7: the late fee moved stock, or the return did not put the machine back once'; end if;

  -- No commission of any kind, while the rental's own invoice (the control)
  -- earned all three.
  v_ctl := (select invoice_id from public.rentals where id = r);
  if not exists (select 1 from public.commissions where invoice_id = v_ctl)
     or not exists (select 1 from public.staff_commissions where invoice_id = v_ctl)
     or not exists (select 1 from public.invoice_staff_sales_ledger() l where l.invoice_id = v_ctl)
     or public.invoice_qualifying_paid(v_ctl) <= 0 or public.invoice_commission_basis(v_ctl) <= 0 then
    raise exception 'FIXTURE 7: the rental invoice did not earn the commission the late fee must not'; end if;
  if exists (select 1 from public.commissions where invoice_id = inv.id)
     or exists (select 1 from public.staff_commissions where invoice_id = inv.id)
     or exists (select 1 from public.invoice_staff_sales_ledger() l where l.invoice_id = inv.id)
     or public.invoice_qualifying_paid(inv.id) <> 0 or public.invoice_commission_basis(inv.id) <> 0
     or exists (select 1 from public.invoice_instalment_commission_targets(inv.id)) then
    raise exception 'FAIL 7: the late fee earned a commission, staff credit or qualification'; end if;
  -- Revenue like any receipt.
  if not exists (select 1 from public.invoice_sales_ledger() l where l.invoice_id = inv.id and l.amount = 36
                  and l.sales_date = public.sg_today()) then
    raise exception 'FAIL 7: the late fee is not revenue on the sales ledger'; end if;
  -- Even with the referrer fallback (explicit affiliate off), the line earns nothing.
  update public.invoices set affiliate_selection_explicit = false where id = inv.id;
  perform public.earn_invoice_commission(inv.id);
  if exists (select 1 from public.commissions where invoice_id = inv.id) then
    raise exception 'FAIL 7: a late-fee line earned affiliate commission through the referrer'; end if;
  if (public.reearn_invoice_staff_commission(inv.id))->>'skipped' is null
     or exists (select 1 from public.staff_commissions where invoice_id = inv.id) then
    raise exception 'FAIL 7: the staff commission rebase reached the late fee'; end if;
  update public.invoices set affiliate_selection_explicit = true where id = inv.id;
  -- A second Return is refused.
  perform pg_temp.t396_refused('7b', 'select public.return_rental_with_fee(p_rental_id => ''' || r || ''', p_condition => ''good'', p_return_stock => true)', 'already returned');
  if pg_temp.t396_moves(r) <> 1 then raise exception 'FAIL 7: the machine went back more than once'; end if;
  insert into t396 values ('late_invoice', inv.id), ('late_line', li.id);
  raise notice 'PASS 7: 3 of 5 days at S$12 are invoiced (INV number, the rental''s store and customer, today, no affiliate, one late-fee line describing the rental) and paid at once by the chosen method, linked to the rental; no stock, no commission, staff credit or qualification (the rental''s own invoice earns all three); revenue on the ledger; a second Return is refused';
end $$;

-- ===== 8. Discounts, quantity, a past date, an old-style rental's store =====
do $$
declare r uuid; x jsonb; li record; inv record; legacy uuid; wh0 int;
begin
  perform pg_temp.t396_as('owner');
  -- Two machines, 3 days at S$10 each: S$60, less S$15 for a reason.
  r := pg_temp.t396_out(pg_temp.t396_rental(2), 'warehouse', 10, -4);
  x := public.return_rental_with_fee(p_rental_id => r, p_condition => 'good', p_return_stock => true,
    p_charge_late_fee => true, p_late_days => 3, p_daily_rate => 10, p_discount_type => 'manual',
    p_discount_amount => 15, p_discount_reason => '  Came back early on the last day  ',
    p_payment_method_id => pg_temp.t396_id('cash'));
  select * into li from public.invoice_items where invoice_id = (x->>'invoice_id')::uuid;
  select * into inv from public.invoices where id = li.invoice_id;
  if (li.quantity, li.unit_price, li.line_total, li.line_discount, li.line_discount_type, li.line_discount_percent,
      li.line_discount_reason, li.line_discount_by is not null, inv.subtotal, inv.discount_total, inv.total_amount, inv.status::text)
     is distinct from (3, 20::numeric, 60::numeric, 15::numeric, 'manual'::text, null::numeric,
                       'Came back early on the last day'::text, true, 60::numeric, 15::numeric, 45::numeric, 'paid'::text)
     or li.item_name_snapshot not like '%: 3 days × S$10.00 × 2 units' then
    raise exception 'FAIL 8a: the S$ discount came out as % / %', to_jsonb(li), to_jsonb(inv); end if;
  if (select late_fee_total from public.rentals where id = r) <> 45
     or public.invoice_discounted_line_value(li.id) <> 45 then
    raise exception 'FAIL 8a: the rental or the line value is not the fee after the discount'; end if;

  -- 4 days at S$7.50, 10% off: S$30 less S$3, returned (and paid) 2 days ago.
  r := pg_temp.t396_out(pg_temp.t396_rental(), 'store', 12, -6);
  x := public.return_rental_with_fee(p_rental_id => r, p_condition => 'damaged', p_return_stock => true,
    p_returned_on => public.sg_today() - 2, p_charge_late_fee => true, p_daily_rate => 7.5,
    p_discount_type => 'percentage', p_discount_percent => 10, p_discount_reason => 'Regular customer',
    p_payment_method_id => pg_temp.t396_id('cash'));
  select * into li from public.invoice_items where invoice_id = (x->>'invoice_id')::uuid;
  select * into inv from public.invoices where id = li.invoice_id;
  if (li.quantity, li.line_total, li.line_discount, li.line_discount_type, li.line_discount_percent,
      inv.total_amount, inv.business_date, inv.status::text)
     is distinct from (4, 30::numeric, 3::numeric, 'percentage'::text, 10::numeric, 27::numeric, public.sg_today() - 2, 'paid'::text)
     or (select (effective_at at time zone 'Asia/Singapore')::date from public.invoice_payments where invoice_id = inv.id)
        is distinct from public.sg_today() - 2
     or not exists (select 1 from public.invoice_sales_ledger() l where l.invoice_id = inv.id and l.sales_date = public.sg_today() - 2) then
    raise exception 'FAIL 8b: the percentage discount on a past return came out as % / %', to_jsonb(li), to_jsonb(inv); end if;

  -- An old-style rental with a warehouse product and no store: the store is chosen.
  insert into public.rentals(rental_no, special_product_id, warehouse_id, customer_id, quantity, rate_type,
    rate_amount, periods, rental_fee, start_date, expected_return_date, status, paid_at, payment_method_id)
  values ('RENT-2026-9002', pg_temp.t396_id('special'), pg_temp.t396_id('warehouse'), pg_temp.t396_id('customer'),
    1, 'day', 30, 3, 90, public.sg_today() - 6, public.sg_today() - 3, 'active', now(), pg_temp.t396_id('cash'))
  returning id into legacy;
  wh0 := pg_temp.t396_wh();
  perform pg_temp.t396_refused('8c', 'select public.return_rental_with_fee(p_rental_id => ''' || legacy
    || ''', p_condition => ''good'', p_return_stock => true, p_charge_late_fee => true, p_daily_rate => 5, p_payment_method_id => '''
    || pg_temp.t396_id('cash') || ''')', 'Choose the store to invoice this late fee in');
  x := public.return_rental_with_fee(p_rental_id => legacy, p_condition => 'good', p_return_stock => true,
    p_charge_late_fee => true, p_daily_rate => 5, p_payment_method_id => pg_temp.t396_id('cash'),
    p_store_id => pg_temp.t396_id('store_b'));
  if (select (store_id, total_amount, status::text) from public.invoices where id = (x->>'invoice_id')::uuid)
     is distinct from (pg_temp.t396_id('store_b'), 15::numeric, 'paid'::text)
     or (select stock_returned from public.rentals where id = legacy) is distinct from true then
    raise exception 'FAIL 8c: the old-style rental''s fee was not invoiced in the chosen store, or not put back: %', x; end if;
  -- Put back where pay_rental would have taken it from, the old special
  -- stock, never warehouse stock, with no movement.
  if x->>'stock_location_type' is distinct from 'special_stock' or pg_temp.t396_moves(legacy) <> 0
     or (select current_qty from public.special_product_stock
          where special_product_id = pg_temp.t396_id('special') and warehouse_id = pg_temp.t396_id('warehouse')) is distinct from 1 then
    raise exception 'FAIL 8c: the old-style rental did not go back into the old special stock alone: %', x; end if;
  if pg_temp.t396_wh() <> wh0 then
    raise exception 'FAIL 8c: the old-style rental added warehouse stock that never left (% -> %)', wh0, pg_temp.t396_wh(); end if;
  -- A manager without access to a store cannot invoice there.
  insert into public.rentals(rental_no, special_product_id, warehouse_id, customer_id, quantity, rate_type,
    rate_amount, periods, rental_fee, start_date, expected_return_date, status, paid_at, payment_method_id)
  values ('RENT-2026-9003', pg_temp.t396_id('special'), pg_temp.t396_id('warehouse'), pg_temp.t396_id('customer'),
    1, 'day', 30, 3, 90, public.sg_today() - 6, public.sg_today() - 3, 'active', now(), pg_temp.t396_id('cash'))
  returning id into legacy;
  delete from public.user_store_assignments where user_id = pg_temp.t396_id('manager') and store_id = pg_temp.t396_id('store_b');
  perform pg_temp.t396_as('manager');
  if public.user_has_store_access(pg_temp.t396_id('store_b')) then
    raise notice 'NOTE 8d: a manager reaches every store here; the store-access refusal is not exercised';
  else
    perform pg_temp.t396_refused('8d', 'select public.return_rental_with_fee(p_rental_id => ''' || legacy
      || ''', p_condition => ''good'', p_return_stock => true, p_charge_late_fee => true, p_daily_rate => 5, p_payment_method_id => '''
      || pg_temp.t396_id('cash') || ''', p_store_id => ''' || pg_temp.t396_id('store_b') || ''')', 'do not have access');
  end if;
  -- A manager may record a Return.
  perform public.return_rental_with_fee(p_rental_id => legacy, p_condition => 'good', p_return_stock => false);
  perform pg_temp.t396_as('owner');
  raise notice 'PASS 8: an S$ and a %% discount are the line''s Discount with their reason, the fee after it on the rental; a past return dates the invoice and its payment that day; an old-style rental''s fee is invoiced in the store chosen, and refused without one; a manager may return';
end $$;

-- ===== 9. The late-fee line through the invoice paths =====
do $$
declare inv uuid := pg_temp.t396_id('late_invoice'); li uuid := pg_temp.t396_id('late_line'); x jsonb; pay uuid; r uuid; inv2 uuid;
begin
  perform pg_temp.t396_as('owner');
  -- Cannot be added: not by create_invoice (an unknown kind is a product to it), not by hand.
  perform pg_temp.t396_refused('9a', format('select public.create_invoice(%L, %L, null, %L::jsonb)',
    pg_temp.t396_id('store_a'), pg_temp.t396_id('customer'),
    jsonb_build_array(jsonb_build_object('kind', 'late_fee', 'quantity', 1, 'unit_price', 5))), '');
  perform pg_temp.t396_refused('9b', format(
    'insert into public.invoice_items(invoice_id, line_kind, quantity, unit_price, line_total) values (%L, ''late_fee'', 1, 5, 5)',
    (select invoice_id from public.rentals where id = pg_temp.t396_id('late5'))), 'charged at the rental''s Return');
  perform pg_temp.t396_refused('9c', format(
    'insert into public.invoice_items(invoice_id, line_kind, product_id, quantity, unit_price, line_total) values (%L, ''product'', %L, 1, 5, 5)',
    inv, pg_temp.t396_id('product')), 'holds nothing else');
  -- Cannot be changed or removed.
  perform pg_temp.t396_refused('9d', format('update public.invoice_items set quantity = 2, line_total = 24 where id = %L', li), 'cannot be changed');
  perform pg_temp.t396_refused('9e', format('update public.invoice_items set foc_quantity = 3, is_foc = true where id = %L', li), 'cannot be changed');
  perform pg_temp.t396_refused('9f', format('delete from public.invoice_items where id = %L', li), 'cannot be removed');
  update public.invoice_items set quantity = quantity where id = li;   -- a no-op update is fine

  -- Correct Invoice: its lines no; its notes yes.
  perform pg_temp.t396_refused('9g', format('select public.correct_invoice(%L, %L::jsonb, ''{}''::jsonb, ''Fewer days'', gen_random_uuid())',
    inv, jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'kind', 'late_fee', 'quantity', 2, 'unit_price', 12))),
    'its line cannot be corrected');
  perform pg_temp.t396_refused('9h', format('select public.correct_invoice(%L, %L::jsonb, ''{}''::jsonb, ''As a product'', gen_random_uuid())',
    inv, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.t396_id('product'), 'quantity', 1))),
    'its line cannot be corrected');
  perform pg_temp.t396_refused('9i', format('select public.correct_invoice(%L, %L::jsonb, %L::jsonb, ''A discount'', gen_random_uuid())',
    inv, jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'kind', 'late_fee', 'quantity', 3, 'unit_price', 12)),
    jsonb_build_object('manual_discount', 5, 'manual_discount_reason', 'Goodwill')),
    'its line cannot be corrected');
  -- No affiliate, explicitly: a correction cannot name one.
  perform pg_temp.t396_refused('9j', format('select public.correct_invoice(%L, %L::jsonb, %L::jsonb, ''Affiliate'', gen_random_uuid())',
    inv, jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'kind', 'late_fee', 'quantity', 3, 'unit_price', 12)),
    jsonb_build_object('affiliate_id', pg_temp.t396_id('affiliate'))), 'it has no affiliate');
  if (select (affiliate_id, affiliate_selection_explicit) from public.invoices where id = inv) is distinct from (null::uuid, true) then
    raise exception 'FAIL 9j: the late-fee invoice was given an affiliate'; end if;
  -- Clearing it (as the form sends) is no change, and is accepted.
  x := public.correct_invoice(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'kind', 'late_fee', 'quantity', 3, 'unit_price', 12)),
    jsonb_build_object('notes', 'Customer paid at the counter', 'affiliate_id', ''), 'Note added', gen_random_uuid());
  if (select (notes, status::text, total_amount) from public.invoices where id = inv)
     is distinct from ('Customer paid at the counter'::text, 'paid'::text, 36::numeric)
     or (select (quantity, line_total, line_kind::text) from public.invoice_items where id = li) is distinct from (3, 36::numeric, 'late_fee'::text) then
    raise exception 'FAIL 9: a notes-only correction of the late-fee invoice did not save, or touched its line'; end if;

  -- The refund screen's plan offers the line's whole value, with no stock to return.
  x := public.invoice_action_plan(inv, 'refund_full', '[]'::jsonb);
  if coalesce((select sum((l->>'amount')::numeric) from jsonb_array_elements(x->'lines') l
                where l->>'invoice_item_id' = li::text), 0) <> 36
     or jsonb_array_length(coalesce(x->'stock', '[]'::jsonb)) <> 0 then
    raise exception 'FAIL 9: the refund plan of a late-fee invoice is %', x; end if;
  -- A full refund works like any other, and moves no stock.
  select id into pay from public.invoice_payments where invoice_id = inv;
  x := public.refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'amount', 36)),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 36)), '[]', 'Charged in error', gen_random_uuid());
  if (select status::text from public.invoices where id = inv) <> 'refunded' or public.invoice_net_received(inv) <> 0
     or exists (select 1 from public.stock_movements where invoice_id = inv)
     or (select late_fee_invoice_id from public.rentals where id = pg_temp.t396_id('late5')) is distinct from inv then
    raise exception 'FAIL 9: the refund of the late-fee invoice did not go through as any other: %', x; end if;
  if exists (select 1 from public.commissions where invoice_id = inv) or exists (select 1 from public.staff_commissions where invoice_id = inv) then
    raise exception 'FAIL 9: the refund''s reconciliation earned commission on the late fee'; end if;

  -- A wrong payment method is corrected on the payment (Correct amount /
  -- date on the Invoices page), not by Correct Invoice; never to wallet credit.
  r := pg_temp.t396_out(pg_temp.t396_rental(), 'warehouse', 10, -2);
  x := public.return_rental_with_fee(p_rental_id => r, p_condition => 'good', p_return_stock => true,
    p_charge_late_fee => true, p_daily_rate => 9, p_payment_method_id => pg_temp.t396_id('cash'));
  inv2 := (x->>'invoice_id')::uuid;
  select id into pay from public.invoice_payments where invoice_id = inv2;
  perform pg_temp.t396_refused('9k', format('select public.correct_invoice_payment(%L, 18, %L, %L, ''Paid from the wallet'', gen_random_uuid())',
    pay, public.sg_today(), pg_temp.t396_id('wallet')), '');
  x := public.correct_invoice_payment(pay, 18, public.sg_today(), pg_temp.t396_id('card'), 'Paid by card, not cash', gen_random_uuid());
  if (select status::text from public.invoices where id = inv2) <> 'paid' or public.invoice_net_received(inv2) <> 18
     or (select count(*) from public.invoice_payments where invoice_id = inv2 and entry_kind = 'correction_replacement'
          and payment_method_id = pg_temp.t396_id('card') and amount = 18) <> 1
     or exists (select 1 from public.commissions where invoice_id = inv2)
     or exists (select 1 from public.staff_commissions where invoice_id = inv2) then
    raise exception 'FAIL 9k: correcting the late fee''s payment method did not work as for any invoice: %', x; end if;
  -- A cancellation works too.
  perform public.cancel_invoice_recorded(inv2, 'Waived after all', gen_random_uuid());
  if (select status::text from public.invoices where id = inv2) <> 'cancelled'
     or (select status::text from public.rentals where id = r) <> 'returned' then
    raise exception 'FAIL 9: cancelling a late-fee invoice did not cancel it, or touched the rental'; end if;
  raise notice 'PASS 9: a late-fee line cannot be added (Invoices page or by hand), have anything added beside it, be changed, given FOC or removed; Correct Invoice refuses its lines, discounts and an affiliate and saves its notes; its payment method is corrected on the payment (never to wallet credit); the refund plan offers its whole value and no stock; a refund and a cancellation of its invoice work, with no stock and no commission';
end $$;

-- ===== 10. The rental trigger and the cancelled-while-out path =====
do $$
declare r uuid; st0 int; wh0 int; inv uuid;
begin
  perform pg_temp.t396_as('owner');
  -- A return that sets no stock decision is put back where it came from, once.
  r := pg_temp.t396_out(pg_temp.t396_rental(), 'store', 2, 1);
  st0 := pg_temp.t396_st();
  update public.rentals set status = 'returned', returned_at = now() where id = r;
  update public.rentals set notes = 'touched again' where id = r;
  if pg_temp.t396_st() <> st0 + 1 or pg_temp.t396_moves(r) <> 1
     or (select stock_returned from public.rentals where id = r) is distinct from true then
    raise exception 'FAIL 10a: the trigger did not put a store release back into its store once'; end if;
  -- One that says false (lost) is left alone: the old trigger put it back.
  r := pg_temp.t396_out(pg_temp.t396_rental(), 'warehouse', 2, 1);
  wh0 := pg_temp.t396_wh();
  update public.rentals set status = 'returned', returned_at = now(), stock_returned = false where id = r;
  if pg_temp.t396_wh() <> wh0 or pg_temp.t396_moves(r) <> 0 then
    raise exception 'FAIL 10b: the trigger put back a return marked not restocked'; end if;
  -- Cancelled with its invoice while out, then received (300): back once, and
  -- the Return refuses it.
  r := pg_temp.t396_out(pg_temp.t396_rental(), 'warehouse', 2, 1);
  inv := (select invoice_id from public.rentals where id = r);
  perform public.cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  if (select status::text from public.rentals where id = r) <> 'cancelled' then
    raise exception 'FIXTURE 10c: the rental was not cancelled with its invoice'; end if;
  perform pg_temp.t396_refused('10c', 'select public.return_rental_with_fee(p_rental_id => ''' || r || ''', p_condition => ''good'', p_return_stock => true)', 'out with the customer');
  wh0 := pg_temp.t396_wh();
  perform public.receive_returned_rental(r, pg_temp.t396_id('warehouse'), 'good', 'Back at the counter', null);
  if pg_temp.t396_wh() <> wh0 + 1
     or (select count(*) from public.stock_movements where notes like 'Rental returned in good condition — %'
          and notes like '%' || (select rental_no from public.rentals where id = r) || '%') <> 1
     or pg_temp.t396_moves(r) <> 0 then
    raise exception 'FAIL 10c: receiving a rental cancelled while out did not put it back once'; end if;
  raise notice 'PASS 10: the trigger puts back only a return with no stock decision, where it came from, once, and never one marked not restocked; a rental cancelled while out is still received once, and the Return refuses it';
end $$;

-- ===== 11. An old-style rental, rented and returned as the old screens did =====
do $$
declare r uuid; wh0 int; sps0 int; sps1 int; x jsonb; mv0 int;
begin
  perform pg_temp.t396_as('owner');
  insert into public.special_product_stock(special_product_id, warehouse_id, current_qty)
    values (pg_temp.t396_id('special'), pg_temp.t396_id('warehouse'), 3)
    on conflict (special_product_id, warehouse_id) do update set current_qty = 3;
  wh0 := pg_temp.t396_wh();
  sps0 := 3;
  mv0 := (select count(*) from public.stock_movements);
  -- create_rental, pay_rental and activate_rental take it from the old special
  -- stock and never from warehouse stock.
  r := public.create_rental(pg_temp.t396_id('special'), pg_temp.t396_id('warehouse'), pg_temp.t396_id('customer'), 1,
         'day', 3, public.sg_today() - 5, public.sg_today() - 2, null);
  perform public.pay_rental(r, pg_temp.t396_id('cash'), null);
  perform public.activate_rental(r);
  sps1 := (select current_qty from public.special_product_stock
            where special_product_id = pg_temp.t396_id('special') and warehouse_id = pg_temp.t396_id('warehouse'));
  if sps1 <> sps0 - 1 or pg_temp.t396_wh() <> wh0 then
    raise exception 'FIXTURE 11: renting did not take from the old special stock alone (% -> %, warehouse % -> %)', sps0, sps1, wh0, pg_temp.t396_wh(); end if;
  -- Ticked: back into the old special stock; warehouse stock as it was; no movement.
  x := public.return_rental_with_fee(p_rental_id => r, p_condition => 'good', p_return_stock => true);
  if (select current_qty from public.special_product_stock
       where special_product_id = pg_temp.t396_id('special') and warehouse_id = pg_temp.t396_id('warehouse')) <> sps0
     or pg_temp.t396_wh() <> wh0 or (select count(*) from public.stock_movements) <> mv0
     or (x->>'restocked_quantity')::int <> 1 or x->>'stock_location_type' <> 'special_stock'
     or (select stock_returned from public.rentals where id = r) is distinct from true then
    raise exception 'FAIL 11a: a ticked old-style return did not go back where it was taken from alone: %, warehouse % -> %', x, wh0, pg_temp.t396_wh(); end if;
  -- Unticked: nothing anywhere, and the trigger adds no warehouse unit.
  r := public.create_rental(pg_temp.t396_id('special'), pg_temp.t396_id('warehouse'), pg_temp.t396_id('customer'), 1,
         'day', 3, public.sg_today() - 5, public.sg_today() - 2, null);
  perform public.pay_rental(r, pg_temp.t396_id('cash'), null);
  perform public.activate_rental(r);
  sps1 := (select current_qty from public.special_product_stock
            where special_product_id = pg_temp.t396_id('special') and warehouse_id = pg_temp.t396_id('warehouse'));
  perform public.return_rental_with_fee(p_rental_id => r, p_condition => 'damaged', p_return_stock => false);
  if (select current_qty from public.special_product_stock
       where special_product_id = pg_temp.t396_id('special') and warehouse_id = pg_temp.t396_id('warehouse')) <> sps1
     or pg_temp.t396_wh() <> wh0 or (select count(*) from public.stock_movements) <> mv0 then
    raise exception 'FAIL 11b: an unticked old-style return changed stock'; end if;
  raise notice 'PASS 11: an old-style rental (create_rental, pay_rental) goes back, ticked, into the old special stock it was taken from, with no movement and no warehouse unit; unticked nothing changes';
end $$;

-- ===== 12. The Dashboard: a late fee is revenue, not items =====
do $$
declare r uuid; d0 jsonb; d1 jsonb; x jsonb;
begin
  perform pg_temp.t396_as('owner');
  r := pg_temp.t396_out(pg_temp.t396_rental(), 'warehouse', 10, -4);   -- 4 days late
  d0 := public.dashboard_sales('day', null, null, pg_temp.t396_id('store_a'));
  x := public.return_rental_with_fee(p_rental_id => r, p_condition => 'good', p_return_stock => true,
    p_charge_late_fee => true, p_daily_rate => 5, p_payment_method_id => pg_temp.t396_id('cash'));
  d1 := public.dashboard_sales('day', null, null, pg_temp.t396_id('store_a'));
  if (d1->>'items_sold')::numeric <> (d0->>'items_sold')::numeric then
    raise exception 'FAIL 12: the late fee''s 4 days counted as items sold (% -> %)', d0->>'items_sold', d1->>'items_sold'; end if;
  if (d1->>'sales')::numeric <> (d0->>'sales')::numeric + 20 then
    raise exception 'FAIL 12: the late fee is not in the Dashboard''s sales (% -> %)', d0->>'sales', d1->>'sales'; end if;
  raise notice 'PASS 12: a 4-day late fee adds S$20 to the Dashboard''s sales and nothing to its items sold';
end $$;

-- ===== 13. Sales by Service Staff: revenue like any receipt, credited to no one =====
do $$
declare r uuid; v jsonb; x jsonb; v_ledger numeric; v_late numeric;
begin
  perform pg_temp.t396_as('owner');
  r := pg_temp.t396_out(pg_temp.t396_rental(), 'store', 10, -3);   -- 3 days late
  x := public.return_rental_with_fee(p_rental_id => r, p_condition => 'good', p_return_stock => true,
    p_charge_late_fee => true, p_daily_rate => 7, p_payment_method_id => pg_temp.t396_id('cash'));
  v := public.report_sales_by_service_staff(public.sg_today(), public.sg_today(), pg_temp.t396_id('store_a'));
  select coalesce(sum(l.amount), 0) into v_ledger from public.invoice_sales_ledger() l
    join public.invoices i on i.id = l.invoice_id
   where i.store_id = pg_temp.t396_id('store_a') and l.sales_date = public.sg_today();
  select coalesce(sum(l.amount), 0) into v_late from public.invoice_sales_ledger() l
    join public.invoices i on i.id = l.invoice_id
   where i.store_id = pg_temp.t396_id('store_a') and l.sales_date = public.sg_today()
     and exists (select 1 from public.invoice_items ii where ii.invoice_id = i.id and ii.line_kind::text = 'late_fee');
  if v_late < 21 then raise exception 'FIXTURE 13: no late fee on the ledger today (%)', v_late; end if;
  if (v->>'revenue')::numeric <> v_ledger then
    raise exception 'FAIL 13: the report''s revenue % is not the headline % (the ledger)', v->>'revenue', v_ledger; end if;
  if (v->>'late_fees_not_credited')::numeric <> v_late then
    raise exception 'FAIL 13: late fees not credited % <> % on the ledger', v->>'late_fees_not_credited', v_late; end if;
  if (v->>'difference')::numeric <> 0
     or (v->>'staff_total')::numeric + (v->>'late_fees_not_credited')::numeric
        <> (v->>'revenue')::numeric + (v->>'backfill_in')::numeric - (v->>'backfill_out')::numeric then
    raise exception 'FAIL 13: staff total and late fees do not reconcile with revenue: %', v - 'rows'; end if;
  if exists (select 1 from jsonb_array_elements(v->'rows') e where e->>'staff_id' is null) then
    raise exception 'FAIL 13: a row credited to no one is listed as a member of staff'; end if;
  raise notice 'PASS 13: Sales by Service Staff counts late fees in revenue (= the headline), as late fees credited to no one, and still reconciles (difference 0)';
end $$;

rollback;
