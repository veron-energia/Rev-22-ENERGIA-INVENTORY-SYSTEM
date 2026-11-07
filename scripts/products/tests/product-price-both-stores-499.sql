-- 499: saving a product sets its price at every store (the user, 7 Nov 2026).
-- supabase/499_product_page_price_sets_both_stores.sql.
--
-- Every step goes through the app's own calls, as the person named, with their grants: the
-- Products page's Save (save_product), the Price List page's Save (set_product_prices), the
-- Products page's Delete and Restore, the invoice form (create_invoice_with_details).
--
--   R. Without 499 (skipped with -v skip_install=1): what was wrong.
--   I. Install: as tested, twice; a function not as tested stops it, changing nothing.
--   A. An Owner adds a product: every active store gets its price, with the Audit Log's entries.
--   B. A Manager changes the price: every store follows.
--   C. A save that leaves the price as it is writes nothing to the Price List.
--   D. The Price List page still sets one store; the next save sets it back, that store alone.
--   E. A blank price sets nothing, and leaves prices already there.
--   F. A machine on the Special page that only rents stays off; one that sells follows.
--   G. Who: an Inventory Manager's save leaves selling prices; the rest as before.
--   J. A price row deleted is brought back, as the Price List page does.
--   K. A refused save changes no price; a price that fails undoes the save.
--   L. Invoices already raised keep their price; the next takes the new one, at either store.
--   M. Inactive, deleted, restored.
--   N. Grants and the other functions are unchanged.
--   U. The UNDO (scripts/products/undo-499.sql).
--
-- Run from the repository's root, on a copy of production at 498 (or with -v skip_install=1
-- where 499 is in):
--   psql -X -v ON_ERROR_STOP=1 -d <copy> -f scripts/products/tests/product-price-both-stores-499.sql
-- Disposable database only; everything is rolled back. Every name and code is invented
-- (@example.invalid); the phones are fictional (+61 2 5550 nnnn).
\set ON_ERROR_STOP on
\set t499_mig `cat supabase/499_product_page_price_sets_both_stores.sql`
\set t499_undo `cat scripts/products/undo-499.sql`
begin;
set local lock_timeout = '10s';
set local statement_timeout = '600s';
select set_config('t499.mig', :'t499_mig', true), set_config('t499.undo', :'t499_undo', true) \g /dev/null
set local client_min_messages = warning;

create temp table t499(k text primary key, id uuid);
create temp table t499_res(n serial primary key, ok boolean, label text);
create temp sequence t499_phone;
create function pg_temp.id(p_k text) returns uuid language sql as $f$ select id from t499 where k = p_k $f$;
create function pg_temp.put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t499 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.ok(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  insert into t499_res(ok, label) values (coalesce(p_ok, false), p_label);
  if not coalesce(p_ok, false) then raise warning 'FAIL %', p_label; end if;
end $f$;
-- Runs p_sql as this person, with their grants. 'ok:<answer>', or 'sqlstate:words' when refused.
create function pg_temp.try_as(p_who uuid, p_sql text) returns text language plpgsql as $f$
declare v text; s text; m text;
begin
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
    perform set_config('request.jwt.claims', '', true);
    if p_who is not null then
      perform set_config('request.jwt.claims', json_build_object('sub', p_who, 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    execute p_sql into v;
    execute 'reset role';
    return 'ok:' || coalesce(v, '');
  exception when others then
    get stacked diagnostics s = returned_sqlstate, m = message_text;
    return s || ':' || m;
  end;
end $f$;
-- The Products page's Save; a refusal stops the suite.
create function pg_temp.save(p_who uuid, p_id uuid, p_fields jsonb) returns jsonb language plpgsql as $f$
declare t text;
begin
  t := pg_temp.try_as(p_who, format('select public.save_product(%L::uuid, %L::jsonb)::text', p_id, p_fields));
  if t not like 'ok:%' then raise exception 'save refused: %', t; end if;
  return substr(t, 4)::jsonb;
end $f$;
-- The Products page's Save when a refusal is the point: its words.
create function pg_temp.save_says(p_who uuid, p_id uuid, p_fields jsonb) returns text language sql as $f$
  select pg_temp.try_as(p_who, format('select public.save_product(%L::uuid, %L::jsonb)::text', p_id, p_fields)) $f$;
-- The Price List page's Save for one store.
create function pg_temp.price_list(p_who uuid, p_store uuid, p_product uuid, p_price numeric) returns text language sql as $f$
  select pg_temp.try_as(p_who, format('select public.set_product_prices(%L::uuid, %L::uuid, %L::numeric, %L::numeric, %L)::text',
    p_store, p_product, p_price, p_price, 'both')) $f$;
-- What the Price List shows: the open row's price, or null where it has none.
create function pg_temp.price(p_store uuid, p_product uuid) returns numeric language sql as $f$
  select selling_price from public.store_product_prices where store_id = p_store and product_id = p_product and deleted_at is null $f$;
-- The Audit Log's entries for this product's prices.
create function pg_temp.audits(p_product uuid) returns bigint language sql as $f$
  select count(*) from public.audit_logs where table_name = 'store_product_prices' and record_id = p_product and action = 'product_prices_set' $f$;
create function pg_temp.cust() returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into public.customers(full_name, phone) values ('T499 Buyer ' || nextval('t499_phone'), '+6125550' || lpad((6000 + currval('t499_phone'))::text, 4, '0'))
    returning id into c;
  return c;
end $f$;
-- The invoice form: one line of this product at this store. Its line's unit price comes from the Price List.
create function pg_temp.invoice(p_who uuid, p_store uuid, p_product uuid) returns uuid language plpgsql as $f$
declare t text;
begin
  t := pg_temp.try_as(p_who, format('select public.create_invoice_with_details(%L::uuid, %L::uuid, %L::jsonb, %L::jsonb)::text',
    p_store, pg_temp.cust(), jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', p_product, 'quantity', 1)),
    jsonb_build_object('business_date', public.sg_today()::text)));
  if t not like 'ok:%' then raise exception 'invoice refused: %', t; end if;
  return substr(t, 4)::uuid;
end $f$;
create function pg_temp.line_price(p_inv uuid) returns numeric language sql as $f$
  select unit_price from public.invoice_items where invoice_id = p_inv $f$;
create function pg_temp.fp() returns text language sql as $f$
  select md5(string_agg(md5(pg_get_functiondef(oid)), '' order by oid::regprocedure::text)) || '/' || count(*)
    from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f' $f$;
create function pg_temp.md5_of(p_sig text) returns text language sql as $f$
  select md5(pg_get_functiondef(to_regprocedure('public.' || p_sig))) $f$;
create function pg_temp.acl_of(p_sig text) returns text language sql as $f$
  select coalesce(string_agg(x::text, ',' order by x::text), '') from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || p_sig) $f$;

-- ═════ Fixtures (invented) ═════
do $fx$
declare
  r record; u uuid;
begin
  perform set_config('search_path', 'public', true);
  for r in select * from (values ('own', 'owner', true), ('mgr', 'manager', true), ('inv', 'inventory_manager', true),
                                 ('adm', 'admin', true), ('stf', 'staff', true), ('gone', 'owner', false)) as t(k, role, active) loop
    insert into auth.users (id, email) values (gen_random_uuid(), 't499-' || r.k || '@example.invalid') returning id into u;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (u, 'T499 ' || r.k, 't499-' || r.k || '@example.invalid', r.role::public.user_role, r.active);
    perform pg_temp.put(r.k, u);
  end loop;
  insert into public.stores (name, code, country_code) values ('T499 Store A', 'T499-A', 'SG') returning id into u; perform pg_temp.put('sa', u);
  insert into public.stores (name, code, country_code) values ('T499 Store B', 'T499-B', 'SG') returning id into u; perform pg_temp.put('sb', u);
  insert into public.stores (name, code, country_code, is_active) values ('T499 Store Shut', 'T499-S', 'SG', false) returning id into u; perform pg_temp.put('shut', u);
  insert into public.stores (name, code, country_code, deleted_at) values ('T499 Store Gone', 'T499-G', 'SG', now()) returning id into u; perform pg_temp.put('del', u);
end $fx$;

-- ═════ R Without 499: a save never touches the Price List ═════
\if :{?skip_install}
do $$ begin raise notice 'NOTE  R1 and I1-I5 are skipped: 499 is in already'; end $$;
create temp table before_install as
  select pg_temp.acl_of('save_product(uuid,jsonb,uuid[],uuid[])') a, pg_temp.acl_of('set_product_prices(uuid,uuid,numeric,numeric,text)') b;
\else
do $r$
declare r jsonb; p uuid;
begin
  r := pg_temp.save(pg_temp.id('own'), null, jsonb_build_object('name', 'T499 Before', 'sku', 'T499-BEFORE', 'default_cost_price', '50'));
  p := (r->>'product_id')::uuid;
  perform pg_temp.ok(not r ? 'prices_set' and pg_temp.price(pg_temp.id('sa'), p) is null and pg_temp.price(pg_temp.id('sb'), p) is null,
    'R1 without 499 a product saved at S$50 has no price at either store');
end $r$;

-- ═════ I Install ═════
create temp table before_install as
  select pg_temp.acl_of('save_product(uuid,jsonb,uuid[],uuid[])') a, pg_temp.acl_of('set_product_prices(uuid,uuid,numeric,numeric,text)') b, pg_temp.fp() f;
create temp table before_md5 as
  select p.oid::regprocedure::text sig, md5(pg_get_functiondef(p.oid)) m from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';

-- A function not as tested stops it, changing nothing.
do $i$
declare e text; f text := pg_temp.fp(); d text;
begin
  d := pg_get_functiondef('public.save_product(uuid,jsonb,uuid[],uuid[])'::regprocedure);
  begin
    execute replace(d, '-- 420: the Products page''s Add and Edit', '-- changed since: the Products page''s Add and Edit');
    begin
      execute current_setting('t499.mig');
      e := null;
    exception when others then e := sqlerrm; end;
    raise exception using errcode = 'T4999';
  exception when sqlstate 'T4999' then null;
  end;
  perform pg_temp.ok(e like '499: public.save_product(uuid,jsonb,uuid[],uuid[]) is not the version this was tested against%',
    'I1 a save_product other than the tested one stops it: ' || coalesce(e, 'it ran'));
  perform pg_temp.ok(pg_temp.fp() = f, 'I2 and nothing changed');
end $i$;

do $i$
declare f text;
begin
  execute current_setting('t499.mig');
  perform pg_temp.ok(pg_temp.md5_of('save_product(uuid,jsonb,uuid[],uuid[])') = '151ad4be5fe4742573ef6ec1b2cbe78a', 'I3 installed as tested');
  f := pg_temp.fp();
  execute current_setting('t499.mig');
  perform pg_temp.ok(pg_temp.fp() = f, 'I4 a second run changes nothing');
  perform pg_temp.ok(not exists (select 1 from public.products where sku like '499-%')
      and not exists (select 1 from public.stores where code like '499-%')
      and not exists (select 1 from public.profiles where email like '499chk-%')
      and not exists (select 1 from auth.users where email like '499chk-%')
      and not exists (select 1 from public.special_products where sku like '499-%')
      and not exists (select 1 from public.store_product_prices s join public.products p on p.id = s.product_id where p.name like '499 Check%')
      and not exists (select 1 from public.audit_logs where new_data->>'sku' like '499-%'),
    'I5 its self-test left no product, store, login, machine, price or Audit Log entry');
end $i$;
\endif

-- ═════ A-M ═════
do $t$
declare
  own uuid := pg_temp.id('own'); mgr uuid := pg_temp.id('mgr'); inv uuid := pg_temp.id('inv');
  adm uuid := pg_temp.id('adm'); stf uuid := pg_temp.id('stf'); gone uuid := pg_temp.id('gone');
  a uuid := pg_temp.id('sa'); b uuid := pg_temp.id('sb'); shut uuid := pg_temp.id('shut'); del uuid := pg_temp.id('del');
  n int := (select count(*) from public.stores where deleted_at is null and is_active);
  p uuid; q uuid; s uuid; rent uuid; sp uuid; r jsonb; t text; x bigint; ida uuid; i1 uuid; i2 uuid;
begin
  -- ── A An Owner adds a product ──
  r := pg_temp.save(own, null, jsonb_build_object('name', 'T499 Mat', 'sku', 'T499-MAT', 'default_cost_price', '12.50'));
  p := (r->>'product_id')::uuid;
  perform pg_temp.ok((r->>'success')::boolean and (r->>'created')::boolean, 'A1 the product is added');
  perform pg_temp.ok((r->>'prices_set')::int = n, 'A2 the answer says every active store changed: ' || r::text);
  perform pg_temp.ok(pg_temp.price(a, p) = 12.50 and pg_temp.price(b, p) = 12.50, 'A3 S$12.50 at both stores');
  perform pg_temp.ok(pg_temp.price(shut, p) is null, 'A4 no price at a store switched off');
  perform pg_temp.ok(pg_temp.price(del, p) is null, 'A5 no price at a deleted store');
  perform pg_temp.ok((select bool_and(s.is_active and s.eligibility = 'available') from public.store_product_prices s where s.product_id = p),
    'A6 the rows are as the Price List page writes them');
  perform pg_temp.ok(pg_temp.audits(p) = n, 'A7 one Audit Log entry per store');
  perform pg_temp.ok((select bool_and(l.changed_by = own and l.module = 'pricing' and (l.new_data->>'price')::numeric = 12.50)
                        from public.audit_logs l where l.table_name = 'store_product_prices' and l.record_id = p),
    'A8 they name the Owner, the Pricing module and the price');
  perform pg_temp.ok((select count(*) from public.audit_logs l where l.table_name = 'store_product_prices' and l.record_id = p and l.store_id = a) = 1,
    'A9 and the store');
  perform pg_temp.ok((select count(*) from public.audit_logs l where l.table_name = 'products' and l.record_id = p and l.action = 'product_created') = 1,
    'A10 the product''s own entry is there too');

  -- ── B A Manager changes the price ──
  r := pg_temp.save(mgr, p, jsonb_build_object('default_cost_price', '20'));
  perform pg_temp.ok((r->>'prices_set')::int = n and not (r->>'created')::boolean, 'B1 every store changes: ' || r::text);
  perform pg_temp.ok(pg_temp.price(a, p) = 20 and pg_temp.price(b, p) = 20, 'B2 S$20 at both stores');
  perform pg_temp.ok((select count(*) from public.store_product_prices s where s.product_id = p) = n, 'B3 no second row');
  perform pg_temp.ok(pg_temp.audits(p) = 2 * n, 'B4 the Audit Log gains one entry per store');
  perform pg_temp.ok((select count(*) from public.audit_logs l where l.table_name = 'store_product_prices' and l.record_id = p and l.changed_by = mgr) = n,
    'B5 naming the Manager');

  -- ── C The price as it is ──
  ida := (select s.id from public.store_product_prices s where s.product_id = p and s.store_id = a);
  x := pg_temp.audits(p);
  r := pg_temp.save(mgr, p, jsonb_build_object('barcode', 'T499-BAR'));
  perform pg_temp.ok((r->>'prices_set')::int = 0, 'C1 a save with no price sent, the same price saved: nothing changes');
  r := pg_temp.save(mgr, p, jsonb_build_object('default_cost_price', '20.00'));
  perform pg_temp.ok((r->>'prices_set')::int = 0, 'C2 the same price written otherwise: nothing changes');
  perform pg_temp.ok(pg_temp.audits(p) = x, 'C3 no Audit Log entry');
  perform pg_temp.ok((select s.id from public.store_product_prices s where s.product_id = p and s.store_id = a) = ida, 'C4 the row is the same one');
  perform pg_temp.ok((select barcode from public.products where id = p) = 'T499-BAR', 'C5 the edit itself is saved');

  -- ── D The Price List page sets one store; the next save sets it back ──
  t := pg_temp.price_list(mgr, b, p, 5);
  perform pg_temp.ok(t like 'ok:%' and pg_temp.price(b, p) = 5 and pg_temp.price(a, p) = 20, 'D1 the Price List page changes that store alone: ' || t);
  perform pg_temp.ok((select default_cost_price from public.products where id = p) = 20, 'D2 and not the Product page');
  x := pg_temp.audits(p);
  r := pg_temp.save(mgr, p, jsonb_build_object('barcode', 'T499-BAR2'));
  perform pg_temp.ok((r->>'prices_set')::int = 1, 'D3 a small edit on the Product page changes that store back: ' || r::text);
  perform pg_temp.ok(pg_temp.price(b, p) = 20 and pg_temp.price(a, p) = 20, 'D4 S$20 at both again');
  perform pg_temp.ok(pg_temp.audits(p) = x + 1, 'D5 one Audit Log entry');

  -- ── E A blank price ──
  r := pg_temp.save(own, null, jsonb_build_object('name', 'T499 No Key', 'sku', 'T499-NOKEY'));
  q := (r->>'product_id')::uuid;
  perform pg_temp.ok((r->>'prices_set')::int = 0 and pg_temp.price(a, q) is null and pg_temp.price(b, q) is null, 'E1 a new product with no price sent has none');
  r := pg_temp.save(own, null, jsonb_build_object('name', 'T499 Zero', 'sku', 'T499-ZERO', 'default_cost_price', '0'));
  q := (r->>'product_id')::uuid;
  perform pg_temp.ok((r->>'prices_set')::int = 0 and pg_temp.price(a, q) is null and pg_temp.price(b, q) is null, 'E2 a new product saved blank has none, not S$0');
  r := pg_temp.save(own, p, jsonb_build_object('default_cost_price', '0'));
  perform pg_temp.ok((r->>'prices_set')::int = 0, 'E3 a price made blank changes nothing');
  perform pg_temp.ok(pg_temp.price(a, p) = 20 and pg_temp.price(b, p) = 20, 'E4 the Price List keeps S$20');
  perform pg_temp.ok((select default_cost_price from public.products where id = p) = 0, 'E5 the Product page shows it blank');
  r := pg_temp.save(own, p, jsonb_build_object('default_cost_price', '33'));
  perform pg_temp.ok((r->>'prices_set')::int = n and pg_temp.price(a, p) = 33 and pg_temp.price(b, p) = 33, 'E6 a price again follows');

  -- ── F A machine on the Special page ──
  r := pg_temp.save(own, null, jsonb_build_object('name', 'T499 Van', 'sku', 'T499-VAN'));
  rent := (r->>'product_id')::uuid;
  insert into public.special_products (name, sku, sale_price, rate_day, product_id)
  values ('T499 Van', 'T499-VAN', 0, 100, rent) returning id into sp;
  r := pg_temp.save(own, rent, jsonb_build_object('default_cost_price', '100'));
  perform pg_temp.ok((r->>'prices_set')::int = 0, 'F1 a machine that only rents: no store changes');
  perform pg_temp.ok(not exists (select 1 from public.store_product_prices s where s.product_id = rent), 'F2 it stays off the Price List');
  perform pg_temp.ok((select default_cost_price from public.products where id = rent) = 100, 'F3 its figure is saved');
  t := pg_temp.price_list(own, a, rent, 90);
  r := pg_temp.save(own, rent, jsonb_build_object('default_cost_price', '110'));
  perform pg_temp.ok(t like 'ok:%' and (r->>'prices_set')::int = 0 and pg_temp.price(a, rent) = 90,
    'F4 priced by hand on the Price List it keeps that price: the save leaves it');
  update public.special_products set sale_price = 500 where id = sp;
  r := pg_temp.save(own, rent, '{}'::jsonb);
  perform pg_temp.ok((r->>'prices_set')::int = n and pg_temp.price(a, rent) = 110 and pg_temp.price(b, rent) = 110, 'F5 given a sale price, it follows');
  update public.special_products set sale_price = 0, deleted_at = now() where id = sp;
  r := pg_temp.save(own, rent, jsonb_build_object('default_cost_price', '120'));
  perform pg_temp.ok((r->>'prices_set')::int = n and pg_temp.price(b, rent) = 120, 'F6 a deleted Special entry does not hold it off');
  r := pg_temp.save(own, null, jsonb_build_object('name', 'T499 Machine', 'sku', 'T499-MACH'));
  q := (r->>'product_id')::uuid;
  insert into public.special_products (name, sku, sale_price, product_id) values ('T499 Machine', 'T499-MACH', 999, q);
  r := pg_temp.save(own, q, jsonb_build_object('default_cost_price', '994'));
  perform pg_temp.ok((r->>'prices_set')::int = n and pg_temp.price(a, q) = 994 and pg_temp.price(b, q) = 994, 'F7 a machine that sells follows the Product page');
  perform pg_temp.ok((select sale_price from public.special_products where product_id = q) = 999, 'F8 and its Special page price is left');

  -- ── G Who ──
  x := pg_temp.audits(p);
  r := pg_temp.save(inv, p, jsonb_build_object('default_cost_price', '44'));
  perform pg_temp.ok((r->>'prices_set')::int = 0, 'G1 an Inventory Manager''s save changes no store');
  perform pg_temp.ok((select default_cost_price from public.products where id = p) = 44, 'G2 the figure is saved, as the Owner agreed on 9 Oct');
  perform pg_temp.ok(pg_temp.price(a, p) = 33 and pg_temp.price(b, p) = 33 and pg_temp.audits(p) = x, 'G3 the selling prices stay, no Audit Log entry');
  r := pg_temp.save(inv, null, jsonb_build_object('name', 'T499 By Inv', 'sku', 'T499-INV', 'default_cost_price', '60'));
  q := (r->>'product_id')::uuid;
  perform pg_temp.ok((r->>'prices_set')::int = 0 and pg_temp.price(a, q) is null, 'G4 a product they add has no selling price yet');
  t := pg_temp.price_list(inv, a, p, 1);
  perform pg_temp.ok(t like '%Only an Owner or Manager can edit prices%', 'G5 and the Price List page refuses them, as before: ' || t);
  r := pg_temp.save(own, p, '{}'::jsonb);
  perform pg_temp.ok((r->>'prices_set')::int = n and pg_temp.price(a, p) = 44 and pg_temp.price(b, p) = 44, 'G6 an Owner''s next save puts their figure on the Price List');
  r := pg_temp.save(mgr, q, '{}'::jsonb);
  perform pg_temp.ok((r->>'prices_set')::int = n and pg_temp.price(b, q) = 60, 'G7 so does a Manager''s');
  t := pg_temp.save_says(adm, p, jsonb_build_object('default_cost_price', '1'));
  perform pg_temp.ok(t = '42501:Only an Owner, Manager or Inventory Manager can add or change products.', 'G8 an Admin is refused, as before: ' || t);
  t := pg_temp.save_says(stf, p, jsonb_build_object('default_cost_price', '1'));
  perform pg_temp.ok(t like '42501:%', 'G9 Staff are refused, as before: ' || t);
  t := pg_temp.save_says(gone, p, jsonb_build_object('default_cost_price', '1'));
  perform pg_temp.ok(t not like 'ok:%', 'G10 an Owner switched off is refused: ' || t);
  perform pg_temp.ok(pg_temp.price(a, p) = 44 and (select default_cost_price from public.products where id = p) = 44, 'G11 none of them changed a price');
  r := pg_temp.save(null, p, jsonb_build_object('default_cost_price', '45'));
  perform pg_temp.ok((r->>'prices_set')::int = 0 and pg_temp.price(a, p) = 44, 'G12 a script with nobody signed in sets no selling price');
  r := pg_temp.save(own, p, jsonb_build_object('default_cost_price', '44'));

  -- ── J A price row deleted ──
  update public.store_product_prices set deleted_at = now() where product_id = p and store_id = a;
  perform pg_temp.ok(pg_temp.price(a, p) is null, 'J0 the row is deleted');
  r := pg_temp.save(own, p, '{}'::jsonb);
  perform pg_temp.ok((r->>'prices_set')::int = 1 and pg_temp.price(a, p) = 44, 'J1 the save brings it back');
  perform pg_temp.ok((select count(*) from public.store_product_prices s where s.product_id = p and s.store_id = a) = 1, 'J2 the same row, not a second one');

  -- ── K Refused ──
  x := pg_temp.audits(p);
  t := pg_temp.save_says(own, p, jsonb_build_object('default_cost_price', '1.234'));
  perform pg_temp.ok(t = 'P0001:Price must be 0 or more, with at most 2 decimal places.', 'K1 three decimals, in the page''s word: ' || t);
  t := pg_temp.save_says(own, p, jsonb_build_object('default_cost_price', '-1'));
  perform pg_temp.ok(t like 'P0001:Price must be 0 or more%', 'K2 below zero: ' || t);
  t := pg_temp.save_says(own, p, jsonb_build_object('sku', 'T499-ZERO', 'default_cost_price', '9'));
  perform pg_temp.ok(t like 'P0001:That SKU already exists (T499 Zero)%', 'K3 a SKU in use: ' || t);
  perform pg_temp.ok(pg_temp.price(a, p) = 44 and pg_temp.price(b, p) = 44 and pg_temp.audits(p) = x, 'K4 none of them touched a price');
  -- A price that fails undoes the whole save.
  create function pg_temp.refuse_price() returns trigger language plpgsql as $f$
  begin
    if new.store_id = pg_temp.id('sb') then raise exception 'T499 this store refuses'; end if;
    return new;
  end $f$;
  create trigger t499_refuse before insert or update on public.store_product_prices
    for each row execute function pg_temp.refuse_price();
  t := pg_temp.save_says(own, p, jsonb_build_object('name', 'T499 Mat Renamed', 'default_cost_price', '55'));
  drop trigger t499_refuse on public.store_product_prices;
  perform pg_temp.ok(t like '%T499 this store refuses%', 'K5 a store''s price refused refuses the save: ' || t);
  perform pg_temp.ok((select name from public.products where id = p) = 'T499 Mat' and (select default_cost_price from public.products where id = p) = 44,
    'K6 the product is as it was');
  perform pg_temp.ok(pg_temp.price(a, p) = 44 and pg_temp.price(b, p) = 44, 'K7 and so is the other store');
  perform pg_temp.ok(pg_temp.audits(p) = x, 'K8 no Audit Log entry');
  r := pg_temp.save(own, p, jsonb_build_object('name', 'T499 Mat Renamed', 'default_cost_price', '55'));
  perform pg_temp.ok((r->>'prices_set')::int = n and pg_temp.price(a, p) = 55, 'K9 once it can, the same save goes through');

  -- ── L Invoices ──
  r := pg_temp.save(own, null, jsonb_build_object('name', 'T499 Fee', 'sku', 'T499-FEE', 'product_type', 'no_commission', 'default_cost_price', '40'));
  s := (r->>'product_id')::uuid;
  perform pg_temp.ok((r->>'prices_set')::int = n, 'L1 a new service gets its price at every store');
  i1 := pg_temp.invoice(own, a, s);
  perform pg_temp.ok(pg_temp.line_price(i1) = 40, 'L2 it can go on an invoice at once, at that price');
  perform pg_temp.ok(pg_temp.line_price(pg_temp.invoice(own, b, s)) = 40, 'L3 at the other store too');
  r := pg_temp.save(own, s, jsonb_build_object('default_cost_price', '55'));
  perform pg_temp.ok(pg_temp.line_price(i1) = 40 and (select total_amount from public.invoices where id = i1) = 40, 'L4 an invoice already raised keeps its price');
  i2 := pg_temp.invoice(own, a, s);
  perform pg_temp.ok(pg_temp.line_price(i2) = 55, 'L5 the next invoice takes the new one');
  perform pg_temp.ok(pg_temp.line_price(pg_temp.invoice(own, b, s)) = 55, 'L6 at the other store too');
  t := pg_temp.price_list(mgr, a, s, 70);
  perform pg_temp.ok(pg_temp.line_price(pg_temp.invoice(own, a, s)) = 70 and pg_temp.line_price(pg_temp.invoice(own, b, s)) = 55,
    'L7 a price set on the Price List page for one store sells at that store alone');
  r := pg_temp.save(own, s, jsonb_build_object('description', 'T499'));

  -- ── M Inactive, deleted, restored ──
  r := pg_temp.save(own, null, jsonb_build_object('name', 'T499 Off', 'sku', 'T499-OFF', 'default_cost_price', '10', 'is_active', false));
  q := (r->>'product_id')::uuid;
  perform pg_temp.ok((r->>'prices_set')::int = n and pg_temp.price(a, q) = 10, 'M1 a product saved inactive has its price ready for when it is on');
  t := pg_temp.try_as(own, format('select public.soft_delete_product(%L::uuid)::text', q));
  perform pg_temp.ok(t like 'ok:%', 'M2 it can be deleted: ' || t);
  t := pg_temp.save_says(own, q, jsonb_build_object('default_cost_price', '11'));
  perform pg_temp.ok(t = 'P0001:This product is deleted. Restore it first.' and pg_temp.price(a, q) = 10, 'M3 a deleted one cannot be saved; its price stays: ' || t);
  x := pg_temp.audits(q);
  t := pg_temp.try_as(own, format('select public.restore_product(%L::uuid)::text', q));
  perform pg_temp.ok(t like 'ok:%' and pg_temp.price(a, q) = 10 and pg_temp.price(b, q) = 10 and pg_temp.audits(q) = x, 'M4 restored, with its prices as they were: ' || t);
end $t$;

-- ═════ N Grants and the other functions ═════
do $n$
begin
  perform pg_temp.ok(pg_temp.acl_of('save_product(uuid,jsonb,uuid[],uuid[])') = (select a from before_install), 'N1 save_product''s grants are unchanged');
  perform pg_temp.ok(pg_temp.acl_of('set_product_prices(uuid,uuid,numeric,numeric,text)') = (select b from before_install), 'N2 set_product_prices'' grants are unchanged');
  perform pg_temp.ok(not has_function_privilege('anon', 'public.save_product(uuid,jsonb,uuid[],uuid[])', 'execute'), 'N3 not open to anon');
  perform pg_temp.ok(pg_temp.md5_of('save_product(uuid,jsonb,uuid[],uuid[])') = '151ad4be5fe4742573ef6ec1b2cbe78a', 'N4 save_product is the tested text');
end $n$;
\if :{?skip_install}
\else
select pg_temp.ok(not exists (select 1 from before_md5 b where b.sig <> 'save_product(uuid,jsonb,uuid[],uuid[])'
                                 and b.m is distinct from pg_temp.md5_of(b.sig))
    and split_part(pg_temp.fp(), '/', 2) = split_part((select f from before_install), '/', 2),
  'N5 no other function changed, and none was added') \g /dev/null
\endif

-- ═════ U The UNDO ═════
do $u$
declare own uuid := pg_temp.id('own'); r jsonb; p uuid; t text; e text;
begin
  -- It refuses anything but 499's version.
  execute replace(pg_get_functiondef('public.save_product(uuid,jsonb,uuid[],uuid[])'::regprocedure), '-- 420: the Products page''s Add and Edit', '-- changed since: the Products page''s Add and Edit');
  begin
    execute current_setting('t499.undo');
  exception when others then e := sqlerrm; end;
  perform pg_temp.ok(e like 'UNDO 499: public.save_product(uuid,jsonb,uuid[],uuid[]) is not 499''s version%', 'U1 UNDO refuses another version: ' || coalesce(e, 'it ran'));
  execute replace(pg_get_functiondef('public.save_product(uuid,jsonb,uuid[],uuid[])'::regprocedure), '-- changed since: the Products page''s Add and Edit', '-- 420: the Products page''s Add and Edit');

  execute current_setting('t499.undo');
  perform pg_temp.ok(pg_temp.md5_of('save_product(uuid,jsonb,uuid[],uuid[])') = '905cdc6ded1a0f3cda513a1884ee238a', 'U2 UNDO puts back production''s text');
  r := pg_temp.save(own, null, jsonb_build_object('name', 'T499 After Undo', 'sku', 'T499-UNDO', 'default_cost_price', '10'));
  p := (r->>'product_id')::uuid;
  perform pg_temp.ok(not r ? 'prices_set' and pg_temp.price(pg_temp.id('sa'), p) is null, 'U3 a save no longer sets a price');
  perform pg_temp.ok((select count(*) from public.store_product_prices s join public.products x on x.id = s.product_id where x.sku = 'T499-MAT') > 0, 'U4 prices already set stay set');
  t := pg_temp.save_says(own, p, jsonb_build_object('default_cost_price', '1.234'));
  perform pg_temp.ok(t like 'P0001:Cost price must be%', 'U5 and the refusal has its old words: ' || t);
  execute current_setting('t499.mig');
  perform pg_temp.ok(pg_temp.md5_of('save_product(uuid,jsonb,uuid[],uuid[])') = '151ad4be5fe4742573ef6ec1b2cbe78a', 'U6 499 again puts it in');
end $u$;

-- ═════ Result ═════
do $res$
declare f int; n int;
begin
  select count(*) filter (where not ok), count(*) into f, n from t499_res;
  if f > 0 then raise exception '% of % checks failed: %', f, n, (select string_agg(label, ' | ' order by t499_res.n) from t499_res where not ok); end if;
  raise warning 'PASS all % checks', n;
end $res$;
rollback;
