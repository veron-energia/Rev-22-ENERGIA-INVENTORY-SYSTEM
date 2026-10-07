-- 400 + 401: Record use in one transaction on both stock pages, and stock lent
-- out and taken back.
--
-- The Owner's rules of 6 Oct 2026: Record use records all its lines or none,
-- and a retry records nothing twice (a retry of the same form is answered
-- with what was saved; the same form changed after a lost answer is refused,
-- naming what was saved, for uses, loans and take-backs alike), at a store (staff with access to it) and
-- at a warehouse (the warehouse stock permission). Lend, at a store for staff
-- with access to it and at a warehouse for Owner/Manager, to a customer or a
-- typed name, with a required expected return date not in the past; the stock
-- leaves on-hand at once with a loan_out movement, and a line short of stock
-- refuses the loan. Take back in part, into any store (into a warehouse only
-- with the warehouse permission), and close the rest as used / given away or
-- lost / damaged; a damaged return goes back to stock or is recorded as used;
-- nothing accounts for more than is out; the loan closes when every line is
-- accounted for. "On loan" lists with overdue loans; the customer's loans;
-- Stock History's "Lent out" and "Loan returned" with the loan number, and
-- inventory changes that match the movements. Grants, row-level security, and
-- the migrations re-running as no-ops.
--
-- Disposable local database only; everything is rolled back. The migrations
-- are applied inside this transaction, so run the file on its own:
--   psql -v ON_ERROR_STOP=1 -f scripts/stock-loans/tests/loans.sql
-- On a local database that has drifted from production, pass a file that
-- installs production's functions, run right after the begin below:
--   psql -v ON_ERROR_STOP=1 -v prelude=/path/to/prod_prelude.sql -f ...
-- Where 400 is not committed yet, its values cannot be used in the same
-- transaction; the block after the prelude moves every stock_movement_type
-- column onto a copy of the enum made in this transaction, so 400 adds the
-- values to the copy, and the rollback puts everything back. Where 400 is
-- committed it does nothing.
-- Every name, phone, number and amount here is invented.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif

do $swap$
declare v_labels text; c record;
begin
  if exists (select 1 from pg_enum e where e.enumtypid = 'public.stock_movement_type'::regtype and e.enumlabel = 'loan_out') then
    return;
  end if;
  select string_agg(quote_literal(e.enumlabel), ',' order by e.enumsortorder) into v_labels
    from pg_enum e where e.enumtypid = 'public.stock_movement_type'::regtype;
  alter type public.stock_movement_type rename to stock_movement_type_committed;
  execute 'create type public.stock_movement_type as enum (' || v_labels || ')';
  for c in select a.attrelid::regclass as tbl, a.attname from pg_attribute a
            where a.atttypid = 'public.stock_movement_type_committed'::regtype and not a.attisdropped and a.attnum > 0
  loop
    execute format('alter table %s alter column %I type public.stock_movement_type using %I::text::public.stock_movement_type',
                   c.tbl, c.attname, c.attname);
  end loop;
end $swap$;

\ir ../../../supabase/400_stock_loan_movement_types.sql
\ir ../../../supabase/401_record_use_and_stock_loans.sql

-- ===== 1. The migrations re-run as no-ops =====
create temp table t401_fns as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5,
         coalesce(array_to_string(p.proacl, ','), '') as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace;
create temp table t401_shape as
  select 'col ' || table_name || '.' || column_name || ' ' || data_type as k from information_schema.columns
   where table_schema = 'public' and table_name in ('stock_loans', 'stock_loan_lines', 'stock_loan_events', 'stock_uses')
  union all select 'pol ' || tablename || '.' || policyname || ' ' || coalesce(qual, '') from pg_policies
   where schemaname = 'public' and tablename like 'stock_loan%'
  union all select 'idx ' || indexdef from pg_indexes
   where schemaname = 'public' and (tablename like 'stock_loan%' or tablename = 'stock_uses')
  union all select 'con ' || conrelid::regclass::text || '.' || conname || ' ' || pg_get_constraintdef(oid) from pg_constraint
   where conrelid in ('public.stock_loans'::regclass, 'public.stock_loan_lines'::regclass, 'public.stock_loan_events'::regclass)
  union all select 'acl ' || c.relname || ' ' || coalesce(array_to_string(c.relacl, ','), '') from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relname in ('stock_loans', 'stock_loan_lines', 'stock_loan_events', 'stock_loan_no_seq')
  union all select 'enum ' || e.enumlabel from pg_enum e where e.enumtypid = 'public.stock_movement_type'::regtype;
\ir ../../../supabase/400_stock_loan_movement_types.sql
\ir ../../../supabase/401_record_use_and_stock_loans.sql
do $$
declare v_shape text[];
begin
  if exists (select 1 from pg_proc p left join t401_fns b on b.fn = p.oid::regprocedure::text
              where p.pronamespace = 'public'::regnamespace
                and (b.fn is null or b.md5 <> md5(pg_get_functiondef(p.oid))
                     or b.acl <> coalesce(array_to_string(p.proacl, ','), ''))) then
    raise exception 'FAIL 1: a second run of 400 and 401 changed a function or a grant'; end if;
  select array_agg(k order by k) into v_shape from (
    select 'col ' || table_name || '.' || column_name || ' ' || data_type as k from information_schema.columns
     where table_schema = 'public' and table_name in ('stock_loans', 'stock_loan_lines', 'stock_loan_events', 'stock_uses')
    union all select 'pol ' || tablename || '.' || policyname || ' ' || coalesce(qual, '') from pg_policies
     where schemaname = 'public' and tablename like 'stock_loan%'
    union all select 'idx ' || indexdef from pg_indexes
     where schemaname = 'public' and (tablename like 'stock_loan%' or tablename = 'stock_uses')
    union all select 'con ' || conrelid::regclass::text || '.' || conname || ' ' || pg_get_constraintdef(oid) from pg_constraint
     where conrelid in ('public.stock_loans'::regclass, 'public.stock_loan_lines'::regclass, 'public.stock_loan_events'::regclass)
    union all select 'acl ' || c.relname || ' ' || coalesce(array_to_string(c.relacl, ','), '') from pg_class c
     where c.relnamespace = 'public'::regnamespace and c.relname in ('stock_loans', 'stock_loan_lines', 'stock_loan_events', 'stock_loan_no_seq')
    union all select 'enum ' || e.enumlabel from pg_enum e where e.enumtypid = 'public.stock_movement_type'::regtype) x;
  if v_shape is distinct from (select array_agg(k order by k) from t401_shape) then
    raise exception 'FAIL 1: a second run changed a table, policy, index, constraint, grant or enum value'; end if;
  if (select count(*) from pg_enum where enumtypid = 'public.stock_movement_type'::regtype
        and enumlabel in ('loan_out', 'loan_return')) <> 2 then
    raise exception 'FAIL 1: loan_out and loan_return are not values of stock_movement_type'; end if;
  if (select count(*) from t401_shape where k like 'pol %') <> 3 then
    raise exception 'FAIL 1: the three read policies are not there once each'; end if;
  raise notice 'PASS 1: a second run of 400 and 401 changes no function, grant, column, policy, index, constraint or enum value';
end $$;

-- ===== 2. Grants (339) =====
do $$
declare f text;
begin
  foreach f in array array['public.record_stock_uses(text,uuid,jsonb,text,text,uuid)',
                           'public.lend_stock(text,uuid,jsonb,date,uuid,text,text,uuid)',
                           'public.return_stock_loan(uuid,jsonb,text,uuid)',
                           'public.stock_loans_at(text,uuid,boolean)', 'public.customer_stock_loans(uuid)',
                           'public.record_stock_use(text,uuid,uuid,integer,text,text)'] loop
    if not has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute') then
      raise exception 'FAIL 2: % is not staff-only', f; end if;
  end loop;
  foreach f in array array['public.stock_loan_access(text,uuid,boolean)', 'public.stock_loan_json(uuid)'] loop
    if has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute') then
      raise exception 'FAIL 2: the helper % is callable by a client role', f; end if;
  end loop;
  foreach f in array array['public.stock_loans', 'public.stock_loan_lines', 'public.stock_loan_events'] loop
    if not has_table_privilege('authenticated', f, 'select')
       or has_table_privilege('authenticated', f, 'insert') or has_table_privilege('authenticated', f, 'update')
       or has_table_privilege('authenticated', f, 'delete') or has_table_privilege('anon', f, 'select') then
      raise exception 'FAIL 2: % is not read-only for staff and closed signed out', f; end if;
  end loop;
  if has_sequence_privilege('authenticated', 'public.stock_loan_no_seq', 'usage')
     or has_sequence_privilege('anon', 'public.stock_loan_no_seq', 'usage') then
    raise exception 'FAIL 2: a client role can draw loan numbers'; end if;
  -- No two functions of one name take the same parameter names (386/388/390).
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
               and p.proname in ('record_stock_uses', 'record_stock_use', 'lend_stock', 'return_stock_loan',
                                 'stock_loans_at', 'customer_stock_loans', 'stock_loan_access', 'stock_loan_json')
             group by p.proname having count(*) > 1) then
    raise exception 'FAIL 2: a loan or use function has a second overload'; end if;
  raise notice 'PASS 2: the five functions the pages call are staff-only, record_stock_use is still granted, the helpers are endpoints for nobody, the tables are read-only for staff, the sequence is closed, one function per name';
end $$;

-- ===== Fixtures =====
create temp table t401(k text primary key, id uuid);

create function pg_temp.t401_id(p_k text) returns uuid language sql as $f$
  select id from t401 where k = p_k
$f$;

create function pg_temp.t401_as(p_k text) returns void language sql as $f$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.t401_id(p_k)::text, 'role', 'authenticated')::text, true);
  select set_config('request.jwt.claim.sub', pg_temp.t401_id(p_k)::text, true);
$f$;

create function pg_temp.t401_l(p_k text, p_q int) returns jsonb language sql as $f$
  select jsonb_build_object('product_id', pg_temp.t401_id(p_k), 'quantity', p_q)
$f$;

create function pg_temp.t401_st(p_store text, p_prod text) returns int language sql as $f$
  select coalesce((select current_qty from public.store_inventory
                    where store_id = pg_temp.t401_id(p_store) and product_id = pg_temp.t401_id(p_prod)), 0)
$f$;
create function pg_temp.t401_wh(p_prod text) returns int language sql as $f$
  select coalesce((select current_qty from public.warehouse_inventory
                    where warehouse_id = pg_temp.t401_id('wh') and product_id = pg_temp.t401_id(p_prod)), 0)
$f$;
-- The loan's line for a product.
create function pg_temp.t401_line(p_loan uuid, p_prod text) returns uuid language sql as $f$
  select id from public.stock_loan_lines where loan_id = p_loan and product_id = pg_temp.t401_id(p_prod)
$f$;

-- Runs p_sql and expects it to be refused with a message containing p_like.
create function pg_temp.t401_refused(p_label text, p_sql text, p_like text) returns void language plpgsql as $f$
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
declare o uuid := gen_random_uuid(); m uuid := gen_random_uuid(); ad uuid := gen_random_uuid();
  sa_u uuid := gen_random_uuid(); sb_u uuid := gen_random_uuid();
  sa uuid; sb uuid; sc uuid; wh uuid; p1 uuid; p2 uuid; p3 uuid; c uuid; aff uuid; gone uuid;
begin
  insert into auth.users(id, email) values (o, 'owner401@sig.invalid'), (m, 'manager401@sig.invalid'),
    (ad, 'admin401@sig.invalid'), (sa_u, 'staffa401@sig.invalid'), (sb_u, 'staffb401@sig.invalid');
  insert into public.profiles(id, full_name, email, role, is_active) values
    (o, 'Fixture Owner', 'owner401@sig.invalid', 'owner', true),
    (m, 'Fixture Manager', 'manager401@sig.invalid', 'manager', true),
    (ad, 'Fixture Admin', 'admin401@sig.invalid', 'admin', true),
    (sa_u, 'Fixture Staff A', 'staffa401@sig.invalid', 'staff', true),
    (sb_u, 'Fixture Staff B', 'staffb401@sig.invalid', 'staff', true);
  insert into t401 values ('owner', o), ('manager', m), ('admin', ad), ('staff_a', sa_u), ('staff_b', sb_u);
  perform pg_temp.t401_as('owner');
  insert into public.stores(name, code, country_code) values ('Fixture Store 401 A', 'T401A', 'SG') returning id into sa;
  insert into public.stores(name, code, country_code) values ('Fixture Store 401 B', 'T401B', 'SG') returning id into sb;
  insert into public.stores(name, code, country_code, is_active) values ('Fixture Store 401 Closed', 'T401C', 'SG', false) returning id into sc;
  insert into public.warehouses(name, code) values ('Fixture Warehouse 401', 'T401W') returning id into wh;
  insert into public.user_store_assignments(user_id, store_id) values (sa_u, sa), (sb_u, sb), (m, sa), (m, sb);
  insert into t401 values ('store_a', sa), ('store_b', sb), ('store_c', sc), ('wh', wh);
  insert into public.products(name, sku, product_type) values ('Fixture Mat 401', 'T401-1', 'own') returning id into p1;
  insert into public.products(name, sku, product_type) values ('Fixture Lamp 401', 'T401-2', 'own') returning id into p2;
  insert into public.products(name, sku, product_type) values ('Fixture Kit 401', 'T401-3', 'own') returning id into p3;
  insert into t401 values ('p1', p1), ('p2', p2), ('p3', p3);
  -- Opening stock, each with its movement, so Stock History's own check has
  -- evidence for every unit (section 12).
  insert into public.store_inventory(store_id, product_id, current_qty) values (sa, p1, 10), (sa, p2, 5);
  insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (wh, p1, 20), (wh, p3, 8);
  insert into public.stock_movements(product_id, movement_type, to_store_id, to_warehouse_id, quantity, notes, created_by) values
    (p1, 'inventory_adjustment', sa, null, 10, 'Fixture opening 401', o),
    (p2, 'inventory_adjustment', sa, null, 5, 'Fixture opening 401', o),
    (p1, 'inventory_adjustment', null, wh, 20, 'Fixture opening 401', o),
    (p3, 'inventory_adjustment', null, wh, 8, 'Fixture opening 401', o);
  insert into public.customers(full_name, phone) values ('Jane Tan', '+6591390401') returning id into c;
  insert into public.customers(full_name, phone) values ('Rex Teo', '+6591390402') returning id into aff;
  insert into public.customers(full_name, phone, deleted_at) values ('Jim Gone', '+6591390403', now()) returning id into gone;
  insert into public.customer_affiliates(customer_id, store_id, status, referral_code) values (aff, sa, 'active', 'T401AFF');
  insert into t401 values ('jane', c), ('john', aff), ('gone', gone);
end $$;

-- ===== 3. Record use at a store: all lines or none, and a retry records nothing twice =====
do $$
declare x jsonb; rq uuid := gen_random_uuid(); n0 int; m0 int; a0 int;
begin
  perform pg_temp.t401_as('staff_a');
  n0 := (select count(*) from public.stock_uses); m0 := (select count(*) from public.stock_movements);
  a0 := (select count(*) from public.audit_logs where action = 'stock_used');
  -- The second line is short: nothing at all is recorded, the first line included.
  perform pg_temp.t401_refused('3a', format($q$select public.record_stock_uses('store', %L, %L::jsonb, 'Demo units', null, %L)$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 3), pg_temp.t401_l('p2', 99)), rq),
    'Only 5 of "Fixture Lamp 401" in stock at this store');
  if pg_temp.t401_st('store_a', 'p1') <> 10 or pg_temp.t401_st('store_a', 'p2') <> 5
     or (select count(*) from public.stock_uses) <> n0 or (select count(*) from public.stock_movements) <> m0 then
    raise exception 'FAIL 3a: a refused batch left a line recorded'; end if;
  -- The same form again, corrected: both lines, once.
  x := public.record_stock_uses('store', pg_temp.t401_id('store_a'),
         jsonb_build_array(pg_temp.t401_l('p1', 3), pg_temp.t401_l('p2', 2)), '  Demo units ', ' opened for testers ', rq);
  if pg_temp.t401_st('store_a', 'p1') <> 7 or pg_temp.t401_st('store_a', 'p2') <> 3 then
    raise exception 'FAIL 3b: the batch did not take both lines off (% / %)', pg_temp.t401_st('store_a', 'p1'), pg_temp.t401_st('store_a', 'p2'); end if;
  if (x->>'replayed')::boolean or jsonb_array_length(x->'uses') <> 2 then
    raise exception 'FAIL 3b: the batch answered %', x; end if;
  if (select count(*) from public.stock_uses where request_id = rq and reason = 'Demo units'
        and note = 'opened for testers' and used_by = pg_temp.t401_id('staff_a') and location_type = 'store'
        and store_id = pg_temp.t401_id('store_a')) <> 2 then
    raise exception 'FAIL 3b: the two uses are not recorded under the request'; end if;
  if (select count(*) from public.stock_movements m join public.stock_uses u on m.notes like 'Stock use ' || u.use_no || ' — Demo units (opened for testers)'
        where u.request_id = rq and m.movement_type::text = 'inventory_adjustment' and m.from_store_id = pg_temp.t401_id('store_a')
          and m.quantity = u.quantity and m.product_id = u.product_id) <> 2
     or (select count(*) from public.audit_logs where action = 'stock_used') <> a0 + 2 then
    raise exception 'FAIL 3b: a batch line is not exactly a single use (movement and audit row)'; end if;
  -- Pressed again (the answer was lost on the way back): the same form, its
  -- lines in another order and its words spaced differently, records nothing more.
  x := public.record_stock_uses('store', pg_temp.t401_id('store_a'),
         jsonb_build_array(pg_temp.t401_l('p2', 2), pg_temp.t401_l('p1', 3)), 'Demo units', 'opened for testers', rq);
  if not (x->>'replayed')::boolean or jsonb_array_length(x->'uses') <> 2
     or pg_temp.t401_st('store_a', 'p1') <> 7 or pg_temp.t401_st('store_a', 'p2') <> 3
     or (select count(*) from public.stock_uses where request_id = rq) <> 2 then
    raise exception 'FAIL 3c: a retry recorded the use again: %', x; end if;
  -- The form changed after a save whose answer was lost (a quantity, a line,
  -- the reason or the note): refused, naming what was saved, and nothing more
  -- is recorded, rather than "already recorded" for changes that were not kept.
  perform pg_temp.t401_refused('3g', format($q$select public.record_stock_uses('store', %L, %L::jsonb, 'Demo units', 'opened for testers', %L)$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 4), pg_temp.t401_l('p2', 2)), rq),
    'This form was already saved as USE-');
  perform pg_temp.t401_refused('3g', format($q$select public.record_stock_uses('store', %L, %L::jsonb, 'Demo units', 'opened for testers', %L)$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 3)), rq), 'has been changed since');
  perform pg_temp.t401_refused('3g', format($q$select public.record_stock_uses('store', %L, %L::jsonb, 'Demo units', 'opened for testers', %L)$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 3), pg_temp.t401_l('p2', 2), pg_temp.t401_l('p3', 1)), rq),
    'Fixture Lamp 401 ×2');
  perform pg_temp.t401_refused('3g', format($q$select public.record_stock_uses('store', %L, %L::jsonb, 'Samples', 'opened for testers', %L)$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 3), pg_temp.t401_l('p2', 2)), rq), 'nothing more was recorded');
  perform pg_temp.t401_refused('3g', format($q$select public.record_stock_uses('store', %L, %L::jsonb, 'Demo units', null, %L)$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 3), pg_temp.t401_l('p2', 2)), rq), 'has been changed since');
  if pg_temp.t401_st('store_a', 'p1') <> 7 or pg_temp.t401_st('store_a', 'p2') <> 3
     or (select count(*) from public.stock_uses where request_id = rq) <> 2 then
    raise exception 'FAIL 3g: a changed retry recorded something'; end if;
  -- Someone else, or another place, with the same request: refused.
  perform pg_temp.t401_as('owner');
  perform pg_temp.t401_refused('3d', format($q$select public.record_stock_uses('store', %L, %L::jsonb, 'Demo units', null, %L)$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 1)), rq), 'already used for another record');
  perform pg_temp.t401_as('staff_a');
  perform pg_temp.t401_refused('3d', format($q$select public.record_stock_uses('store', %L, %L::jsonb, 'Demo units', 'opened for testers', %L)$q$,
    pg_temp.t401_id('store_b'), jsonb_build_array(pg_temp.t401_l('p1', 3), pg_temp.t401_l('p2', 2)), rq), 'already used for another record');
  -- The form's own rules.
  perform pg_temp.t401_refused('3e', format($q$select public.record_stock_uses('store', %L, %L::jsonb, 'x')$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 1), pg_temp.t401_l('p1', 1))), 'listed more than once');
  perform pg_temp.t401_refused('3e', format($q$select public.record_stock_uses('store', %L, '[]'::jsonb, 'x')$q$,
    pg_temp.t401_id('store_a')), 'at least one product');
  perform pg_temp.t401_refused('3e', format($q$select public.record_stock_uses('store', %L, %L::jsonb, '  ')$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 1))), 'A reason is required');
  perform pg_temp.t401_refused('3e', format($q$select public.record_stock_uses('store', %L, %L::jsonb, 'x')$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 0))), 'whole quantity greater than zero');
  perform pg_temp.t401_refused('3e', format($q$select public.record_stock_uses('store', %L, %L::jsonb, 'x')$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(jsonb_build_object('product_id', pg_temp.t401_id('p1'), 'quantity', 1.5))),
    'whole quantity greater than zero');
  -- Without a request id (another caller) it still works, once per call.
  perform public.record_stock_uses('store', pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 1)), 'Tester');
  if pg_temp.t401_st('store_a', 'p1') <> 6 then raise exception 'FAIL 3f: a use without a request id was not recorded'; end if;
  -- record_stock_use itself is unchanged for other callers.
  perform public.record_stock_use('store', pg_temp.t401_id('store_a'), pg_temp.t401_id('p1'), 1, 'Single use');
  if pg_temp.t401_st('store_a', 'p1') <> 5 then raise exception 'FAIL 3f: record_stock_use no longer records a use'; end if;
  raise notice 'PASS 3: at a store a short line refuses the whole Record use; the corrected form records every line once, each exactly a single use; a retry of the same form records nothing; the form changed after the save (quantity, lines, reason, note) is refused naming what was saved; another person or place cannot reuse it; duplicates, no lines, no reason and bad quantities are refused; record_stock_use still works alone';
end $$;

-- ===== 4. Record use at a warehouse, and who may record where =====
do $$
declare x jsonb; rq uuid := gen_random_uuid();
begin
  -- Staff: not at a warehouse, not at a store they have no access to.
  perform pg_temp.t401_as('staff_a');
  perform pg_temp.t401_refused('4a', format($q$select public.record_stock_uses('warehouse', %L, %L::jsonb, 'Event')$q$,
    pg_temp.t401_id('wh'), jsonb_build_array(pg_temp.t401_l('p1', 2))), 'permission to use stock from a warehouse');
  perform pg_temp.t401_as('staff_b');
  perform pg_temp.t401_refused('4b', format($q$select public.record_stock_uses('store', %L, %L::jsonb, 'Event')$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 1))), 'No access to this store');
  perform pg_temp.t401_as('admin');
  perform pg_temp.t401_refused('4c', format($q$select public.record_stock_uses('warehouse', %L, %L::jsonb, 'Event')$q$,
    pg_temp.t401_id('wh'), jsonb_build_array(pg_temp.t401_l('p1', 2))), 'permission to use stock from a warehouse');
  if pg_temp.t401_wh('p1') <> 20 or pg_temp.t401_st('store_a', 'p1') <> 5 then
    raise exception 'FAIL 4: a refused use moved stock'; end if;
  -- A manager: all lines or none, then once.
  perform pg_temp.t401_as('manager');
  perform pg_temp.t401_refused('4d', format($q$select public.record_stock_uses('warehouse', %L, %L::jsonb, 'Event', null, %L)$q$,
    pg_temp.t401_id('wh'), jsonb_build_array(pg_temp.t401_l('p1', 5), pg_temp.t401_l('p3', 9)), rq),
    'Only 8 of "Fixture Kit 401" in stock at this warehouse');
  if pg_temp.t401_wh('p1') <> 20 or pg_temp.t401_wh('p3') <> 8 then raise exception 'FAIL 4d: a refused warehouse batch left a line'; end if;
  x := public.record_stock_uses('warehouse', pg_temp.t401_id('wh'),
         jsonb_build_array(pg_temp.t401_l('p3', 1), pg_temp.t401_l('p1', 5)), 'Event', null, rq);
  x := public.record_stock_uses('warehouse', pg_temp.t401_id('wh'),
         jsonb_build_array(pg_temp.t401_l('p3', 1), pg_temp.t401_l('p1', 5)), 'Event', null, rq);
  if pg_temp.t401_wh('p1') <> 15 or pg_temp.t401_wh('p3') <> 7 or not (x->>'replayed')::boolean
     or (select count(*) from public.stock_uses where request_id = rq and location_type = 'warehouse'
           and warehouse_id = pg_temp.t401_id('wh')) <> 2
     or (select count(*) from public.stock_movements m join public.stock_uses u on m.notes like 'Stock use ' || u.use_no || ' — %'
           where u.request_id = rq and m.from_warehouse_id = pg_temp.t401_id('wh')) <> 2 then
    raise exception 'FAIL 4e: the warehouse batch was not recorded exactly once'; end if;
  raise notice 'PASS 4: at a warehouse staff and admin are refused and a manager records all lines or none, once; staff cannot record at a store they have no access to';
end $$;

-- ===== 5. Lend to a customer, from a store =====
do $$
declare x jsonb; y jsonb; rq uuid := gen_random_uuid(); l uuid; a0 int;
begin
  perform pg_temp.t401_as('staff_a');
  a0 := (select count(*) from public.audit_logs where action = 'stock_lent');
  x := public.lend_stock('store', pg_temp.t401_id('store_a'),
         jsonb_build_array(pg_temp.t401_l('p2', 1), pg_temp.t401_l('p1', 2)), public.sg_today() + 7,
         pg_temp.t401_id('jane'), null, ' Home trial ', rq);
  l := (x->>'loan_id')::uuid;
  insert into t401 values ('loan_jane', l);
  if pg_temp.t401_st('store_a', 'p1') <> 3 or pg_temp.t401_st('store_a', 'p2') <> 2 then
    raise exception 'FAIL 5a: lent stock did not leave the shelf (% / %)', pg_temp.t401_st('store_a', 'p1'), pg_temp.t401_st('store_a', 'p2'); end if;
  if x->>'loan_no' !~ '^LOAN-[0-9]{6}$' or (x->>'replayed')::boolean then raise exception 'FAIL 5a: the loan answered %', x; end if;
  if (select (status, location_type, store_id, warehouse_id, customer_id, borrower_name, purpose, expected_return_date, lent_by)
        from public.stock_loans where id = l) is distinct from
     ('open'::text, 'store'::text, pg_temp.t401_id('store_a'), null::uuid, pg_temp.t401_id('jane'), null::text, 'Home trial'::text,
      public.sg_today() + 7, pg_temp.t401_id('staff_a')) then
    raise exception 'FAIL 5a: the loan was recorded as %', (select to_jsonb(s) from public.stock_loans s where id = l); end if;
  if (select count(*) from public.stock_loan_lines where loan_id = l) <> 2
     or (select qty_out from public.stock_loan_lines where id = pg_temp.t401_line(l, 'p1')) <> 2 then
    raise exception 'FAIL 5a: the loan lines are wrong'; end if;
  if (select count(*) from public.stock_movements where movement_type::text = 'loan_out'
        and from_store_id = pg_temp.t401_id('store_a') and to_store_id is null and to_warehouse_id is null
        and invoice_id is null and created_by = pg_temp.t401_id('staff_a')
        and notes = (x->>'loan_no') || ' — lent to Jane Tan (Home trial), due back ' || to_char(public.sg_today() + 7, 'DD Mon YYYY')) <> 2 then
    raise exception 'FAIL 5a: there is not one loan_out movement per line, from the store, naming the loan'; end if;
  if (select count(*) from public.audit_logs where action = 'stock_lent' and record_id = l) <> 1
     or (select count(*) from public.audit_logs where action = 'stock_lent') <> a0 + 1 then
    raise exception 'FAIL 5a: no single audit row'; end if;
  -- Pressed again: the same loan, nothing more off the shelf.
  y := public.lend_stock('store', pg_temp.t401_id('store_a'),
         jsonb_build_array(pg_temp.t401_l('p2', 1), pg_temp.t401_l('p1', 2)), public.sg_today() + 7,
         pg_temp.t401_id('jane'), null, 'Home trial', rq);
  if not (y->>'replayed')::boolean or y->>'loan_id' <> x->>'loan_id' or pg_temp.t401_st('store_a', 'p1') <> 3
     or (select count(*) from public.stock_loans where request_id = rq) <> 1 then
    raise exception 'FAIL 5b: a retry lent the stock twice: %', y; end if;
  -- The form changed after the save (borrower, date, purpose, lines, place):
  -- refused, naming the loan made; nothing more is lent.
  perform pg_temp.t401_refused('5d', format($q$select public.lend_stock('store', %L, %L::jsonb, %L::date, null, 'Fixture roadshow', 'Home trial', %L)$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p2', 1), pg_temp.t401_l('p1', 2)), public.sg_today() + 7, rq),
    'This form was already saved as ' || (x->>'loan_no') || ' (Fixture Lamp 401 ×1, Fixture Mat 401 ×2)');
  perform pg_temp.t401_refused('5d', format($q$select public.lend_stock('store', %L, %L::jsonb, %L::date, %L, null, 'Home trial', %L)$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p2', 1), pg_temp.t401_l('p1', 2)), public.sg_today() + 10,
    pg_temp.t401_id('jane'), rq), 'nothing more was lent');
  perform pg_temp.t401_refused('5d', format($q$select public.lend_stock('store', %L, %L::jsonb, %L::date, %L, null, 'Event', %L)$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p2', 1), pg_temp.t401_l('p1', 2)), public.sg_today() + 7,
    pg_temp.t401_id('jane'), rq), 'has been changed since');
  perform pg_temp.t401_refused('5d', format($q$select public.lend_stock('store', %L, %L::jsonb, %L::date, %L, null, 'Home trial', %L)$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p2', 1), pg_temp.t401_l('p1', 1)), public.sg_today() + 7,
    pg_temp.t401_id('jane'), rq), 'has been changed since');
  perform pg_temp.t401_refused('5d', format($q$select public.lend_stock('store', %L, %L::jsonb, %L::date, %L, null, 'Home trial', %L)$q$,
    pg_temp.t401_id('store_b'), jsonb_build_array(pg_temp.t401_l('p2', 1), pg_temp.t401_l('p1', 2)), public.sg_today() + 7,
    pg_temp.t401_id('jane'), rq), 'has been changed since');
  if pg_temp.t401_st('store_a', 'p1') <> 3 or pg_temp.t401_st('store_a', 'p2') <> 2
     or (select count(*) from public.stock_loans where request_id = rq) <> 1
     or (select count(*) from public.stock_loan_lines where loan_id = l) <> 2 then
    raise exception 'FAIL 5d: a changed retry lent something'; end if;
  perform pg_temp.t401_as('manager');
  perform pg_temp.t401_refused('5d', format($q$select public.lend_stock('store', %L, %L::jsonb, %L::date, %L, null, 'Home trial', %L)$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p2', 1), pg_temp.t401_l('p1', 2)), public.sg_today() + 7,
    pg_temp.t401_id('jane'), rq), 'already used for another loan');
  perform pg_temp.t401_as('staff_a');
  -- An affiliate is a customer with an affiliate row; the loan says so.
  x := public.lend_stock('store', pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p2', 1)),
         public.sg_today(), pg_temp.t401_id('john'));
  insert into t401 values ('loan_john', (x->>'loan_id')::uuid);
  if not (x->'loan'->>'is_affiliate')::boolean or x->'loan'->>'borrower' <> 'Rex Teo' or (x->'loan'->>'overdue')::boolean then
    raise exception 'FAIL 5c: the affiliate''s loan reads %', x->'loan'; end if;
  if (y->'loan'->>'is_affiliate')::boolean then raise exception 'FAIL 5c: Jane Tan is shown as an affiliate'; end if;
  raise notice 'PASS 5: a loan to a customer takes every line off the store at once, with one loan_out movement per line naming the loan, the borrower, the purpose and the due date, and an audit row; a retry of the same form lends nothing twice; the form changed after the save (borrower, date, purpose, quantity, place) or sent by someone else is refused naming the loan; an affiliate''s loan says so';
end $$;

-- ===== 6. Lend to a typed name, from a warehouse; who may lend where =====
do $$
declare x jsonb; l uuid;
begin
  perform pg_temp.t401_as('staff_a');
  perform pg_temp.t401_refused('6a', format($q$select public.lend_stock('warehouse', %L, %L::jsonb, %L::date, null, 'Roadshow')$q$,
    pg_temp.t401_id('wh'), jsonb_build_array(pg_temp.t401_l('p3', 1)), public.sg_today() + 1),
    'permission to lend stock from a warehouse');
  perform pg_temp.t401_as('admin');
  perform pg_temp.t401_refused('6a', format($q$select public.lend_stock('warehouse', %L, %L::jsonb, %L::date, null, 'Roadshow')$q$,
    pg_temp.t401_id('wh'), jsonb_build_array(pg_temp.t401_l('p3', 1)), public.sg_today() + 1),
    'permission to lend stock from a warehouse');
  perform pg_temp.t401_as('staff_b');
  perform pg_temp.t401_refused('6b', format($q$select public.lend_stock('store', %L, %L::jsonb, %L::date, null, 'Roadshow')$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 1)), public.sg_today() + 1), 'No access to this store');
  perform pg_temp.t401_as('manager');
  x := public.lend_stock('warehouse', pg_temp.t401_id('wh'),
         jsonb_build_array(pg_temp.t401_l('p3', 4), pg_temp.t401_l('p1', 3)), public.sg_today() + 2,
         null, '  Roadshow   Fixture  401 ');
  l := (x->>'loan_id')::uuid;
  insert into t401 values ('loan_road', l);
  if pg_temp.t401_wh('p3') <> 3 or pg_temp.t401_wh('p1') <> 12 then
    raise exception 'FAIL 6c: the warehouse loan did not leave warehouse stock'; end if;
  if (select (borrower_name, customer_id, warehouse_id, store_id, purpose) from public.stock_loans where id = l)
       is distinct from ('Roadshow Fixture 401'::text, null::uuid, pg_temp.t401_id('wh'), null::uuid, null::text) then
    raise exception 'FAIL 6c: the typed-name loan was recorded as %', (select to_jsonb(s) from public.stock_loans s where id = l); end if;
  if (select count(*) from public.stock_movements where movement_type::text = 'loan_out'
        and from_warehouse_id = pg_temp.t401_id('wh') and notes like (x->>'loan_no') || ' — lent to Roadshow Fixture 401, due back %') <> 2 then
    raise exception 'FAIL 6c: the warehouse loan_out movements are wrong'; end if;
  if x->'loan'->>'borrower' <> 'Roadshow Fixture 401' or (x->'loan'->>'is_affiliate')::boolean then
    raise exception 'FAIL 6c: the loan reads %', x->'loan'; end if;
  raise notice 'PASS 6: a manager lends warehouse stock to a typed name (spaces tidied), out of the warehouse at once; staff and admin cannot lend from a warehouse, and staff cannot lend from a store they have no access to';
end $$;

-- ===== 7. What a loan refuses =====
do $$
declare n0 int; m0 int; s1 int; s2 int;
begin
  perform pg_temp.t401_as('staff_a');
  n0 := (select count(*) from public.stock_loans); m0 := (select count(*) from public.stock_movements);
  s1 := pg_temp.t401_st('store_a', 'p1'); s2 := pg_temp.t401_st('store_a', 'p2');
  -- Short on the second line (in product order): nothing is lent at all.
  perform pg_temp.t401_refused('7a', format($q$select public.lend_stock('store', %L, %L::jsonb, %L::date, %L)$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 1), pg_temp.t401_l('p2', 99)), public.sg_today() + 1,
    pg_temp.t401_id('jane')), 'so 99 cannot be lent');
  perform pg_temp.t401_refused('7b', format($q$select public.lend_stock('store', %L, %L::jsonb, null, %L)$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 1)), pg_temp.t401_id('jane')),
    'An expected return date is required');
  perform pg_temp.t401_refused('7c', format($q$select public.lend_stock('store', %L, %L::jsonb, %L::date, %L)$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 1)), public.sg_today() - 1, pg_temp.t401_id('jane')),
    'cannot be in the past');
  perform pg_temp.t401_refused('7d', format($q$select public.lend_stock('store', %L, %L::jsonb, %L::date, %L, 'Someone')$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 1)), public.sg_today(), pg_temp.t401_id('jane')),
    'not both');
  perform pg_temp.t401_refused('7e', format($q$select public.lend_stock('store', %L, %L::jsonb, %L::date, null, '   ')$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 1)), public.sg_today()), 'Who is borrowing it');
  perform pg_temp.t401_refused('7f', format($q$select public.lend_stock('store', %L, %L::jsonb, %L::date, %L)$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 1)), public.sg_today(), pg_temp.t401_id('gone')),
    'Customer not found');
  perform pg_temp.t401_refused('7g', format($q$select public.lend_stock('store', %L, %L::jsonb, %L::date, null, 'Someone')$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 1), pg_temp.t401_l('p1', 1)), public.sg_today()),
    'listed more than once');
  perform pg_temp.t401_refused('7h', format($q$select public.lend_stock('store', %L, '[]'::jsonb, %L::date, null, 'Someone')$q$,
    pg_temp.t401_id('store_a'), public.sg_today()), 'at least one product');
  -- A product the store has never held.
  perform pg_temp.t401_refused('7i', format($q$select public.lend_stock('store', %L, %L::jsonb, %L::date, null, 'Someone')$q$,
    pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p3', 1)), public.sg_today()), 'Only 0 of "Fixture Kit 401"');
  if (select count(*) from public.stock_loans) <> n0 or (select count(*) from public.stock_movements) <> m0
     or pg_temp.t401_st('store_a', 'p1') <> s1 or pg_temp.t401_st('store_a', 'p2') <> s2 then
    raise exception 'FAIL 7: a refused loan left a loan, a movement or a stock change behind'; end if;
  raise notice 'PASS 7: a loan short of stock on any line lends nothing; a missing or past return date, both or neither borrower, a deleted customer, duplicate or no lines are refused';
end $$;

-- ===== 8. Taking back in part, into another store, and closing as used and lost =====
do $$
declare l uuid := pg_temp.t401_id('loan_jane'); x jsonb; rq uuid := gen_random_uuid(); u0 int; b0 int; a0 int;
begin
  perform pg_temp.t401_as('staff_a');
  u0 := (select count(*) from public.stock_uses); b0 := pg_temp.t401_st('store_b', 'p1');
  a0 := (select count(*) from public.audit_logs where action = 'stock_loan_taken_back' and record_id = l);
  -- One of the two mats comes back to Store B, which staff A is not assigned
  -- to ("any store", the Owner).
  x := public.return_stock_loan(l, jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'),
         'outcome', 'returned', 'quantity', 1, 'location_type', 'store', 'location_id', pg_temp.t401_id('store_b'))),
         'Dropped off at B', rq);
  if pg_temp.t401_st('store_b', 'p1') <> b0 + 1 or pg_temp.t401_st('store_a', 'p1') <> 3 then
    raise exception 'FAIL 8a: the part return did not go into Store B'; end if;
  if (x->>'closed')::boolean or (select status from public.stock_loans where id = l) <> 'open'
     or (select (qty_returned, qty_used, qty_lost) from public.stock_loan_lines where id = pg_temp.t401_line(l, 'p1'))
        is distinct from (1, 0, 0) then
    raise exception 'FAIL 8a: the part return closed the loan or was not counted'; end if;
  if (select count(*) from public.stock_movements m join public.stock_loan_events e on e.movement_id = m.id
        where e.loan_id = l and e.outcome = 'returned' and e.condition = 'good' and e.request_id = rq
          and e.store_id = pg_temp.t401_id('store_b') and m.movement_type::text = 'loan_return'
          and m.to_store_id = pg_temp.t401_id('store_b') and m.from_store_id is null and m.quantity = 1
          and m.notes = (select loan_no from public.stock_loans where id = l) || ' — returned by Jane Tan: Dropped off at B') <> 1 then
    raise exception 'FAIL 8a: the return has no single loan_return movement into Store B naming the loan'; end if;
  -- Pressed again: nothing more.
  x := public.return_stock_loan(l, jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'),
         'outcome', 'returned', 'quantity', 1, 'location_type', 'store', 'location_id', pg_temp.t401_id('store_b'))),
         'Dropped off at B', rq);
  if not (x->>'replayed')::boolean or pg_temp.t401_st('store_b', 'p1') <> b0 + 1
     or (select count(*) from public.stock_loan_events where loan_id = l) <> 1 then
    raise exception 'FAIL 8b: a retried take-back was recorded twice'; end if;
  -- The form changed after the save (the outcome, the place, the quantity, the
  -- note): refused, naming what was recorded; nothing more is recorded.
  perform pg_temp.t401_refused('8i', format($q$select public.return_stock_loan(%L, %L::jsonb, 'Dropped off at B', %L)$q$, l,
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'lost', 'quantity', 1)), rq),
    'This form was already saved for ' || (select loan_no from public.stock_loans where id = l) || ' (Fixture Mat 401 ×1 returned)');
  perform pg_temp.t401_refused('8i', format($q$select public.return_stock_loan(%L, %L::jsonb, 'Dropped off at B', %L)$q$, l,
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'returned', 'quantity', 1,
      'location_type', 'store', 'location_id', pg_temp.t401_id('store_a'))), rq), 'has been changed since');
  perform pg_temp.t401_refused('8i', format($q$select public.return_stock_loan(%L, %L::jsonb, 'Dropped off at B', %L)$q$, l,
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'returned', 'quantity', 1,
      'condition', 'damaged', 'location_type', 'store', 'location_id', pg_temp.t401_id('store_b'))), rq), 'has been changed since');
  perform pg_temp.t401_refused('8i', format($q$select public.return_stock_loan(%L, %L::jsonb, 'Dropped off at B', %L)$q$, l,
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'returned', 'quantity', 1,
      'location_type', 'store', 'location_id', pg_temp.t401_id('store_b')),
      jsonb_build_object('line_id', pg_temp.t401_line(l, 'p2'), 'outcome', 'used', 'quantity', 1)), rq), 'nothing more was recorded');
  perform pg_temp.t401_refused('8i', format($q$select public.return_stock_loan(%L, %L::jsonb, 'Left at B', %L)$q$, l,
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'returned', 'quantity', 1,
      'location_type', 'store', 'location_id', pg_temp.t401_id('store_b'))), rq), 'has been changed since');
  -- The same entries spelled out (condition "good" given) are the same form.
  x := public.return_stock_loan(l, jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'),
         'outcome', 'returned', 'quantity', 1, 'condition', 'good', 'location_type', 'store', 'location_id', pg_temp.t401_id('store_b'))),
         ' Dropped off at B ', rq);
  if not (x->>'replayed')::boolean or pg_temp.t401_st('store_b', 'p1') <> b0 + 1 or pg_temp.t401_st('store_a', 'p1') <> 3
     or (select count(*) from public.stock_loan_events where loan_id = l) <> 1
     or (select (qty_returned, qty_used, qty_lost) from public.stock_loan_lines where id = pg_temp.t401_line(l, 'p1'))
        is distinct from (1, 0, 0) then
    raise exception 'FAIL 8i: a changed take-back retry recorded something, or the same one was not replayed'; end if;
  -- Into a warehouse: not for staff.
  perform pg_temp.t401_refused('8c', format($q$select public.return_stock_loan(%L, %L::jsonb)$q$, l,
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'returned', 'quantity', 1,
      'location_type', 'warehouse', 'location_id', pg_temp.t401_id('wh')))), 'permission to take stock back into a warehouse');
  -- More than is out: refused, nothing changes.
  perform pg_temp.t401_refused('8d', format($q$select public.return_stock_loan(%L, %L::jsonb)$q$, l,
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'returned', 'quantity', 1,
                        'location_type', 'store', 'location_id', pg_temp.t401_id('store_a')),
                      jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'lost', 'quantity', 1))),
    'Only 1 of "Fixture Mat 401" still out on');
  if pg_temp.t401_st('store_a', 'p1') <> 3 or (select count(*) from public.stock_loan_events where loan_id = l) <> 1 then
    raise exception 'FAIL 8d: a refused over-return changed something'; end if;
  -- A store no longer open, a line of another loan, and the outcomes' own rules.
  perform pg_temp.t401_refused('8e', format($q$select public.return_stock_loan(%L, %L::jsonb)$q$, l,
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'returned', 'quantity', 1,
      'location_type', 'store', 'location_id', pg_temp.t401_id('store_c')))), 'Store not found');
  perform pg_temp.t401_refused('8e', format($q$select public.return_stock_loan(%L, %L::jsonb)$q$, l,
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(pg_temp.t401_id('loan_john'), 'p2'), 'outcome', 'lost', 'quantity', 1))),
    'not on');
  perform pg_temp.t401_refused('8e', format($q$select public.return_stock_loan(%L, %L::jsonb)$q$, l,
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'returned', 'quantity', 1))),
    'Choose the store or warehouse it came back to');
  perform pg_temp.t401_refused('8e', format($q$select public.return_stock_loan(%L, %L::jsonb)$q$, l,
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'returned', 'quantity', 1,
      'condition', 'broken', 'location_type', 'store', 'location_id', pg_temp.t401_id('store_a')))), 'good or damaged');
  perform pg_temp.t401_refused('8e', format($q$select public.return_stock_loan(%L, %L::jsonb)$q$, l,
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'used', 'quantity', 1, 'condition', 'good'))),
    'Used / given away');
  perform pg_temp.t401_refused('8e', format($q$select public.return_stock_loan(%L, %L::jsonb)$q$, l,
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'lost', 'quantity', 1, 'condition', 'damaged'))),
    'takes no condition');
  perform pg_temp.t401_refused('8e', format($q$select public.return_stock_loan(%L, %L::jsonb)$q$, l,
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'sold', 'quantity', 1))),
    'Say whether it was returned');
  perform pg_temp.t401_refused('8e', format($q$select public.return_stock_loan(%L, '[]'::jsonb)$q$, l), 'at least one item');
  -- Someone without access to the loan's store.
  perform pg_temp.t401_as('staff_b');
  perform pg_temp.t401_refused('8f', format($q$select public.return_stock_loan(%L, %L::jsonb)$q$, l,
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'lost', 'quantity', 1))),
    'No access to this store');
  -- The lamp was given away and the last mat lost: no stock moves, no stock
  -- use is written, the loan closes.
  perform pg_temp.t401_as('staff_a');
  b0 := pg_temp.t401_st('store_a', 'p2');
  x := public.return_stock_loan(l, jsonb_build_array(
         jsonb_build_object('line_id', pg_temp.t401_line(l, 'p2'), 'outcome', 'used', 'quantity', 1),
         jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'lost', 'quantity', 1)), 'Customer kept the lamp');
  if not (x->>'closed')::boolean or (select (status, closed_at is not null) from public.stock_loans where id = l)
       is distinct from ('closed'::text, true) then
    raise exception 'FAIL 8g: the fully accounted loan did not close: %', x; end if;
  if pg_temp.t401_st('store_a', 'p2') <> b0 or pg_temp.t401_st('store_a', 'p1') <> 3
     or (select count(*) from public.stock_uses) <> u0
     or (select count(*) from public.stock_loan_events where loan_id = l and outcome in ('used', 'lost') and movement_id is null) <> 2 then
    raise exception 'FAIL 8g: used or lost moved stock or wrote a stock use'; end if;
  if (select count(*) from public.audit_logs where action = 'stock_loan_taken_back' and record_id = l) <> a0 + 2 then
    raise exception 'FAIL 8g: each take-back is not audited once'; end if;
  perform pg_temp.t401_refused('8h', format($q$select public.return_stock_loan(%L, %L::jsonb)$q$, l,
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'lost', 'quantity', 1))),
    'already closed');
  if (x->'loan'->>'outstanding')::int <> 0 or jsonb_array_length(x->'loan'->'events') <> 3 then
    raise exception 'FAIL 8g: the closed loan reads %', x->'loan'; end if;
  raise notice 'PASS 8: part of a loan comes back into another store with a loan_return movement naming the loan; a retry of the same form records nothing, and the form changed after the save (outcome, place, condition, items, note) is refused naming what was recorded; staff cannot return into a warehouse; nothing accounts for more than is out; used and lost move no stock and write no stock use; the loan closes when every line is accounted for and then refuses more';
end $$;

-- ===== 9. Damaged: back to stock or recorded as used; a warehouse loan back into a warehouse and a store =====
do $$
declare x jsonb; l uuid; st0 int;
begin
  perform pg_temp.t401_as('staff_a');
  x := public.lend_stock('store', pg_temp.t401_id('store_a'), jsonb_build_array(pg_temp.t401_l('p1', 3)),
         public.sg_today() + 3, null, 'Demo day');
  l := (x->>'loan_id')::uuid;
  st0 := pg_temp.t401_st('store_a', 'p1');
  x := public.return_stock_loan(l, jsonb_build_array(
         jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'returned', 'quantity', 1, 'condition', 'damaged',
                            'location_type', 'store', 'location_id', pg_temp.t401_id('store_a')),
         jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'used', 'quantity', 1, 'condition', 'damaged'),
         jsonb_build_object('line_id', pg_temp.t401_line(l, 'p1'), 'outcome', 'returned', 'quantity', 1,
                            'location_type', 'store', 'location_id', pg_temp.t401_id('store_a'))));
  if pg_temp.t401_st('store_a', 'p1') <> st0 + 2 or not (x->>'closed')::boolean then
    raise exception 'FAIL 9a: two returns (one damaged) did not go back to stock, or the loan did not close'; end if;
  if (select count(*) from public.stock_loan_events where loan_id = l and outcome = 'returned' and condition = 'damaged') <> 1
     or (select count(*) from public.stock_loan_events where loan_id = l and outcome = 'returned' and condition = 'good') <> 1
     or (select count(*) from public.stock_loan_events where loan_id = l and outcome = 'used' and condition = 'damaged' and movement_id is null) <> 1 then
    raise exception 'FAIL 9a: the damaged entries are recorded wrongly'; end if;
  if (select count(*) from public.stock_movements where movement_type::text = 'loan_return'
        and notes like (x->'loan'->>'loan_no') || ' — returned by Demo day%') <> 2
     or (select count(*) from public.stock_movements where movement_type::text = 'loan_return'
        and notes = (x->'loan'->>'loan_no') || ' — returned by Demo day (damaged)') <> 1 then
    raise exception 'FAIL 9a: the damaged return''s movement does not say so'; end if;

  -- The warehouse loan: staff cannot take it back; a manager returns some
  -- into the warehouse and some into Store A, and records one kit lost.
  l := pg_temp.t401_id('loan_road');
  perform pg_temp.t401_refused('9b', format($q$select public.return_stock_loan(%L, %L::jsonb)$q$, l,
    jsonb_build_array(jsonb_build_object('line_id', pg_temp.t401_line(l, 'p3'), 'outcome', 'returned', 'quantity', 1,
      'location_type', 'store', 'location_id', pg_temp.t401_id('store_a')))), 'take back a loan from a warehouse');
  perform pg_temp.t401_as('manager');
  st0 := pg_temp.t401_st('store_a', 'p3');
  x := public.return_stock_loan(l, jsonb_build_array(
         jsonb_build_object('line_id', pg_temp.t401_line(l, 'p3'), 'outcome', 'returned', 'quantity', 2,
                            'location_type', 'warehouse', 'location_id', pg_temp.t401_id('wh')),
         jsonb_build_object('line_id', pg_temp.t401_line(l, 'p3'), 'outcome', 'returned', 'quantity', 1,
                            'location_type', 'store', 'location_id', pg_temp.t401_id('store_a'))));
  if pg_temp.t401_wh('p3') <> 5 or pg_temp.t401_st('store_a', 'p3') <> st0 + 1 or (x->>'closed')::boolean then
    raise exception 'FAIL 9c: the warehouse loan did not come back where it was told (wh %, store %)', pg_temp.t401_wh('p3'), pg_temp.t401_st('store_a', 'p3'); end if;
  if (select count(*) from public.stock_movements where movement_type::text = 'loan_return'
        and to_warehouse_id = pg_temp.t401_id('wh') and product_id = pg_temp.t401_id('p3') and quantity = 2) <> 1 then
    raise exception 'FAIL 9c: no loan_return movement into the warehouse'; end if;
  raise notice 'PASS 9: a damaged item goes back to stock or is recorded as used, as staff choose, and the movement says "damaged"; a warehouse loan is taken back by a manager into the warehouse and into a store; staff cannot take back a warehouse loan';
end $$;

-- ===== 10. The "On loan" lists, overdue, and the customer's loans =====
do $$
declare x jsonb; c jsonb; o jsonb;
begin
  -- Rex's loan was due today; make it three days overdue.
  update public.stock_loans set expected_return_date = public.sg_today() - 3 where id = pg_temp.t401_id('loan_john');
  perform pg_temp.t401_as('staff_a');
  x := public.stock_loans_at('store', pg_temp.t401_id('store_a'));
  if jsonb_array_length(x->'open') <> 1 or x->'open'->0->>'id' <> pg_temp.t401_id('loan_john')::text
     or not (x->'open'->0->>'overdue')::boolean or (x->'open'->0->>'days_overdue')::int <> 3
     or jsonb_array_length(x->'closed') <> 0 or (x->>'today')::date <> public.sg_today() then
    raise exception 'FAIL 10a: Store A''s On loan list reads %', x; end if;
  if (x->'open'->0->'lines'->0->>'outstanding')::int <> 1 or x->'open'->0->'lines'->0->>'product_name' <> 'Fixture Lamp 401' then
    raise exception 'FAIL 10a: the open loan''s lines read %', x->'open'->0->'lines'; end if;
  x := public.stock_loans_at('store', pg_temp.t401_id('store_a'), true);
  if jsonb_array_length(x->'closed') <> 2 then raise exception 'FAIL 10b: the closed loans are not listed when asked'; end if;
  -- Staff A sees neither Store B's list (no access) nor the warehouse's.
  perform pg_temp.t401_refused('10c', format($q$select public.stock_loans_at('store', %L)$q$, pg_temp.t401_id('store_b')), 'No access to this store');
  perform pg_temp.t401_refused('10c', format($q$select public.stock_loans_at('warehouse', %L)$q$, pg_temp.t401_id('wh')), 'No access to this warehouse');
  -- An admin sees the warehouse's (read only); a manager too, with the road show still out.
  perform pg_temp.t401_as('admin');
  o := public.stock_loans_at('warehouse', pg_temp.t401_id('wh'));
  if jsonb_array_length(o->'open') <> 1 or (o->'open'->0->>'outstanding')::int <> 4 or (o->'open'->0->>'overdue')::boolean then
    raise exception 'FAIL 10d: the warehouse''s On loan list reads %', o; end if;
  -- can_act: what lend_stock, return_stock_loan and Record use allow there,
  -- so the pages offer only buttons that will work. Staff at their store and
  -- a manager at the warehouse may; an admin at the warehouse, and a manager
  -- at a store they are not assigned to (whose list they can read), may not.
  if (o->>'can_act')::boolean is distinct from false then raise exception 'FAIL 10g: an admin may act at the warehouse: %', o->>'can_act'; end if;
  perform pg_temp.t401_as('staff_a');
  if (public.stock_loans_at('store', pg_temp.t401_id('store_a'))->>'can_act')::boolean is distinct from true then
    raise exception 'FAIL 10g: staff may not act at their own store'; end if;
  perform pg_temp.t401_as('owner');
  with s as (insert into public.stores(name, code, country_code) values ('Fixture Store 401 D', 'T401D', 'SG') returning id)
  insert into t401 select 'store_d', id from s;
  perform pg_temp.t401_as('manager');
  if (public.stock_loans_at('warehouse', pg_temp.t401_id('wh'))->>'can_act')::boolean is distinct from true then
    raise exception 'FAIL 10g: a manager may not act at the warehouse'; end if;
  o := public.stock_loans_at('store', pg_temp.t401_id('store_d'));
  if (o->>'can_act')::boolean is distinct from false or jsonb_typeof(o->'open') <> 'array' then
    raise exception 'FAIL 10g: a manager not assigned to a store reads it as %', o; end if;
  perform pg_temp.t401_refused('10g', format($q$select public.record_stock_uses('store', %L, %L::jsonb, 'x')$q$,
    pg_temp.t401_id('store_d'), jsonb_build_array(pg_temp.t401_l('p1', 1))), 'No access to this store');
  perform pg_temp.t401_as('owner');
  if (public.stock_loans_at('store', pg_temp.t401_id('store_d'))->>'can_act')::boolean is distinct from true then
    raise exception 'FAIL 10g: the owner may not act at every store'; end if;
  perform pg_temp.t401_as('admin');
  -- The customer's profile: everything of Jane's the caller may see.
  perform pg_temp.t401_as('owner');
  c := public.customer_stock_loans(pg_temp.t401_id('jane'));
  if jsonb_array_length(c) <> 1 or c->0->>'status' <> 'closed' then raise exception 'FAIL 10e: Jane''s loans read %', c; end if;
  c := public.customer_stock_loans(pg_temp.t401_id('john'));
  if jsonb_array_length(c) <> 1 or not (c->0->>'overdue')::boolean then raise exception 'FAIL 10e: Rex''s loans read %', c; end if;
  perform pg_temp.t401_as('staff_b');
  if jsonb_array_length(public.customer_stock_loans(pg_temp.t401_id('john'))) <> 0 then
    raise exception 'FAIL 10f: staff without access to Store A see its loans on the profile'; end if;
  raise notice 'PASS 10: the On loan list shows the open loans, overdue ones flagged with their days, and the closed ones when asked; staff see only their stores, admin and managers the warehouse; can_act is true only where the caller may lend, take back and Record use (not an admin at a warehouse, not a manager at a store they are not assigned to); the customer''s loans follow the same rule';
end $$;

-- ===== 11. Row-level security on the tables =====
select pg_temp.t401_as('staff_b');
set local role authenticated;
select set_config('t401.b_loans', (select count(*) from public.stock_loans)::text, true),
       set_config('t401.b_lines', (select count(*) from public.stock_loan_lines)::text, true),
       set_config('t401.b_events', (select count(*) from public.stock_loan_events)::text, true);
reset role;
select pg_temp.t401_as('staff_a');
set local role authenticated;
select set_config('t401.a_loans', (select count(*) from public.stock_loans where store_id is not null)::text, true),
       set_config('t401.a_wh', (select count(*) from public.stock_loans where warehouse_id is not null)::text, true),
       set_config('t401.a_lines', (select count(*) from public.stock_loan_lines)::text, true);
reset role;
select pg_temp.t401_as('manager');
set local role authenticated;
select set_config('t401.m_loans', (select count(*) from public.stock_loans)::text, true);
reset role;
do $$
begin
  if current_setting('t401.b_loans')::int <> 0 or current_setting('t401.b_lines')::int <> 0
     or current_setting('t401.b_events')::int <> 0 then
    raise exception 'FAIL 11a: staff without access to Store A read its loans (% / % / %)',
      current_setting('t401.b_loans'), current_setting('t401.b_lines'), current_setting('t401.b_events'); end if;
  if current_setting('t401.a_loans')::int <> (select count(*) from public.stock_loans where store_id = pg_temp.t401_id('store_a'))
     or current_setting('t401.a_wh')::int <> 0
     or current_setting('t401.a_lines')::int <> (select count(*) from public.stock_loan_lines x join public.stock_loans l on l.id = x.loan_id
                                                  where l.store_id = pg_temp.t401_id('store_a')) then
    raise exception 'FAIL 11b: staff A does not read exactly Store A''s loans'; end if;
  if current_setting('t401.m_loans')::int < (select count(*) from public.stock_loans
                                             where store_id in (pg_temp.t401_id('store_a'), pg_temp.t401_id('store_b'))
                                                or warehouse_id = pg_temp.t401_id('wh')) then
    raise exception 'FAIL 11c: a manager does not read every loan'; end if;
end $$;
select pg_temp.t401_as('staff_a');
set local role authenticated;
do $$
begin
  begin
    insert into public.stock_loans(loan_no, location_type, store_id, borrower_name, expected_return_date)
    values ('LOAN-999999', 'store', '00000000-0000-0000-0000-000000000000', 'Nobody', current_date);
    raise exception 'FAIL 11d: staff wrote a loan straight into the table';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.stock_loan_lines set qty_returned = qty_out;
    raise exception 'FAIL 11d: staff changed a loan line straight in the table';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
do $$ begin
  raise notice 'PASS 11: staff read the loans, lines and events of their own stores only, managers every loan, and nobody writes the tables directly';
end $$;

-- ===== 12. Stock History: labels, the loan number, and inventory that matches the movements =====
do $$
declare x jsonb; r record; v_bad text; v_qty int;
begin
  if public.stock_history_type_label('loan_out') <> 'Lent out' or public.stock_history_type_label('loan_return') <> 'Loan returned' then
    raise exception 'FAIL 12a: the loan types are labelled % and %',
      public.stock_history_type_label('loan_out'), public.stock_history_type_label('loan_return'); end if;
  if public.stock_history_type_label('inventory_adjustment') <> 'Adjustment'
     or public.stock_history_type_label('transfer_discrepancy') <> 'Transfer Discrepancy'
     or public.stock_history_type_label('exchange_return_in') <> 'Exchange Return In' then
    raise exception 'FAIL 12a: an existing label changed'; end if;
  perform pg_temp.t401_as('owner');
  -- The History tab: the loan rows read "Lent out" / "Loan returned" with the loan number.
  if (select count(*) from public.stock_history_rows(jsonb_build_object('from', public.sg_today(), 'to', public.sg_today(),
        'products', jsonb_build_array(pg_temp.t401_id('p1'), pg_temp.t401_id('p2'), pg_temp.t401_id('p3'))), clock_timestamp()) h
        where (h.type_label = 'Lent out' and h.movement_type = 'loan_out' and h.notes ~ '^LOAN-[0-9]{6} — lent to ')
           or (h.type_label = 'Loan returned' and h.movement_type = 'loan_return' and h.notes ~ '^LOAN-[0-9]{6} — returned by ')) <>
     (select count(*) from public.stock_movements where movement_type::text in ('loan_out', 'loan_return')
        and product_id in (pg_temp.t401_id('p1'), pg_temp.t401_id('p2'), pg_temp.t401_id('p3'))) then
    raise exception 'FAIL 12b: a loan movement is not shown as Lent out / Loan returned with its loan number'; end if;
  if not exists (select 1 from jsonb_array_elements(public.stock_history_options('types', 'lent', 0)->'rows') o
                  where o->>'value' = 'loan_out' and o->>'label' = 'Lent out') then
    raise exception 'FAIL 12b: "Lent out" is not offered as a movement type filter'; end if;
  -- Every loan movement's effect is the inventory change it made.
  select string_agg(m.id::text || ' ' || m.movement_type::text, ', ') into v_bad
    from public.stock_movements m
   where m.movement_type::text in ('loan_out', 'loan_return')
     and public.stock_history_effect(m.id, coalesce('store:' || m.from_store_id, 'warehouse:' || m.from_warehouse_id,
                                                    'store:' || m.to_store_id, 'warehouse:' || m.to_warehouse_id))
         is distinct from case when m.movement_type::text = 'loan_out' then -m.quantity else m.quantity end;
  if v_bad is not null then raise exception 'FAIL 12c: loan movements with the wrong Stock History effect: %', v_bad; end if;
  -- The Table tab's own check: per product and location, the observed
  -- inventory changes equal the movements, so no reconciliation warning.
  for r in select * from (values ('p1', 'store:' || pg_temp.t401_id('store_a')), ('p2', 'store:' || pg_temp.t401_id('store_a')),
                                 ('p1', 'warehouse:' || pg_temp.t401_id('wh')), ('p3', 'warehouse:' || pg_temp.t401_id('wh'))) v(p, loc)
  loop
    x := public.stock_history_table(jsonb_build_object('from', public.sg_today(), 'to', public.sg_today(),
           'products', jsonb_build_array(pg_temp.t401_id(r.p)), 'locations', jsonb_build_array(r.loc)));
    v_qty := case when r.loc like 'store:%' then pg_temp.t401_st('store_a', r.p) else pg_temp.t401_wh(r.p) end;
    if jsonb_array_length(x->'rows') <> 1 or coalesce(x->'rows'->0->>'warning', '') <> ''
       or (x->'rows'->0->>'closing_balance')::int <> v_qty then
      raise exception 'FAIL 12d: Stock History for % at % reads %', r.p, r.loc, x->'rows'; end if;
  end loop;
  raise notice 'PASS 12: Stock History labels loan_out "Lent out" and loan_return "Loan returned", with the loan number in the note and as a type filter; the other labels are unchanged; each loan movement''s effect is its inventory change and the Table tab reconciles without a warning';
end $$;

-- ===== 13. Loan movements stay out of the invoice stock functions =====
do $$
begin
  if exists (select 1 from public.stock_movements where movement_type::text in ('loan_out', 'loan_return')
               and (invoice_id is not null or transfer_request_id is not null or reversed_sale_id is not null)) then
    raise exception 'FAIL 13: a loan movement names an invoice, a transfer or a sale'; end if;
  raise notice 'PASS 13: loan movements carry no invoice, transfer or sale, which is what every function that names movement types keys on';
end $$;

rollback;
