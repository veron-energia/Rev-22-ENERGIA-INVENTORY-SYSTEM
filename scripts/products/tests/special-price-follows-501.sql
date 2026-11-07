-- 501: saving a product also sets its sale price on the Special page (the user, 7 Nov 2026).
-- supabase/501_product_page_price_sets_special_sale_price.sql.
--
-- Every step goes through the app's own calls, as the person named, with their grants: the
-- Products page's Save (save_product), the Special page's form (upsert_special_product_from_product,
-- set_special_product_consignment), the invoice form (create_invoice_with_details), the Pay dialog
-- (record_invoice_settlement).
--
--   R. Without 501 (skipped with -v skip_install=1): what was wrong.
--   I. Install: as tested, twice; a function not as tested stops it, changing nothing.
--   A. An Owner changes the price: the sale price follows, the Audit Log says what it was.
--   B. A Manager; a product on the Consignment tab; the rest of the entry stays.
--   C. A save that leaves the price as it is writes nothing.
--   D. The Special page's form still sets it alone; the next save sets it back.
--   E. A blank price leaves it.
--   F. A machine that only rents keeps no sale price; a deleted entry and another product's stay.
--   G. Who: an Inventory Manager's save leaves it; the rest as before.
--   H. An entry switched off follows, and stays off.
--   K. A refused save changes nothing; a sale price that fails undoes the save.
--   L. Invoices and sales already raised keep their price; the next invoice takes the new one.
--   N. Grants and the other functions are unchanged.
--   U. The UNDO (scripts/products/undo-501.sql).
--
-- Run from the repository's root, on a copy of production at 500 (or with -v skip_install=1
-- where 501 is in):
--   psql -X -v ON_ERROR_STOP=1 -d <copy> -f scripts/products/tests/special-price-follows-501.sql
-- Disposable database only; everything is rolled back. Every name and code is invented
-- (@example.invalid); the phones are fictional (+61 2 5550 nnnn).
\set ON_ERROR_STOP on
\set t501_mig `cat supabase/501_product_page_price_sets_special_sale_price.sql`
\set t501_undo `cat scripts/products/undo-501.sql`
begin;
set local lock_timeout = '10s';
set local statement_timeout = '600s';
select set_config('t501.mig', :'t501_mig', true), set_config('t501.undo', :'t501_undo', true) \g /dev/null
set local client_min_messages = warning;

create temp table t501(k text primary key, id uuid);
create temp table t501_res(n serial primary key, ok boolean, label text);
create temp sequence t501_phone;
create function pg_temp.id(p_k text) returns uuid language sql as $f$ select id from t501 where k = p_k $f$;
create function pg_temp.put(p_k text, p_id uuid) returns uuid language sql as $f$
  insert into t501 values (p_k, p_id) on conflict (k) do update set id = excluded.id returning id $f$;
create function pg_temp.ok(p_ok boolean, p_label text) returns void language plpgsql as $f$
begin
  insert into t501_res(ok, label) values (coalesce(p_ok, false), p_label);
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
-- The Special page's form: sale price, a day rate and whether it is on; returns its id.
create function pg_temp.entry(p_who uuid, p_id uuid, p_product uuid, p_sale numeric, p_day numeric default 0, p_on boolean default true) returns uuid language plpgsql as $f$
declare t text;
begin
  t := pg_temp.try_as(p_who, format('select public.upsert_special_product_from_product(%L::uuid, %L::uuid, %L::numeric, %L::numeric, 0, 0, 0, 0, %L, %L::boolean)::text',
    p_id, p_product, p_sale, p_day, '', p_on));
  if t not like 'ok:%' then raise exception 'the Special page''s form was refused: %', t; end if;
  return substr(t, 4)::uuid;
end $f$;
create function pg_temp.sale_price(p_sp uuid) returns numeric language sql as $f$
  select sale_price from public.special_products where id = p_sp $f$;
-- The Audit Log's entries for this entry's sale price.
create function pg_temp.audits(p_sp uuid) returns bigint language sql as $f$
  select count(*) from public.audit_logs where table_name = 'special_products' and record_id = p_sp and action = 'special_product_sale_price' $f$;
create function pg_temp.store_price(p_store uuid, p_product uuid) returns numeric language sql as $f$
  select selling_price from public.store_product_prices where store_id = p_store and product_id = p_product and deleted_at is null $f$;
create function pg_temp.cust() returns uuid language plpgsql as $f$
declare c uuid;
begin
  insert into public.customers(full_name, phone) values ('T501 Buyer ' || nextval('t501_phone'), '+6125550' || lpad((7000 + currval('t501_phone'))::text, 4, '0'))
    returning id into c;
  return c;
end $f$;
-- The invoice form: one Special Product line at this store. Its price comes from the Special page.
create function pg_temp.invoice(p_who uuid, p_store uuid, p_sp uuid) returns uuid language plpgsql as $f$
declare t text;
begin
  t := pg_temp.try_as(p_who, format('select public.create_invoice_with_details(%L::uuid, %L::uuid, %L::jsonb, %L::jsonb)::text',
    p_store, pg_temp.cust(), jsonb_build_array(jsonb_build_object('kind', 'special_product', 'special_product_id', p_sp, 'quantity', 1)),
    jsonb_build_object('business_date', public.sg_today()::text)));
  if t not like 'ok:%' then raise exception 'invoice refused: %', t; end if;
  return substr(t, 4)::uuid;
end $f$;
create function pg_temp.line_price(p_inv uuid) returns numeric language sql as $f$
  select unit_price from public.invoice_items where invoice_id = p_inv $f$;
-- The Pay dialog, all of it.
create function pg_temp.pay(p_who uuid, p_inv uuid) returns void language plpgsql as $f$
declare t text;
begin
  t := pg_temp.try_as(p_who, format('select public.record_invoice_settlement(%L::uuid, %L::jsonb, %L::uuid)::text', p_inv,
    jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object('key', 'line-0', 'payment_method_id', pg_temp.id('pm'),
      'amount', (select total_amount from public.invoices where id = p_inv), 'payment_date', public.sg_today()::text)), 'arrangements', '[]'::jsonb),
    gen_random_uuid()));
  if t not like 'ok:%' then raise exception 'payment refused: %', t; end if;
end $f$;
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
    insert into auth.users (id, email) values (gen_random_uuid(), 't501-' || r.k || '@example.invalid') returning id into u;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (u, 'T501 ' || r.k, 't501-' || r.k || '@example.invalid', r.role::public.user_role, r.active);
    perform pg_temp.put(r.k, u);
  end loop;
  insert into public.stores (name, code, country_code) values ('T501 Store A', 'T501-A', 'SG') returning id into u; perform pg_temp.put('sa', u);
  insert into public.stores (name, code, country_code) values ('T501 Store B', 'T501-B', 'SG') returning id into u; perform pg_temp.put('sb', u);
  insert into public.payment_methods (name, is_active) values ('T501 Cash', true) returning id into u; perform pg_temp.put('pm', u);
end $fx$;

-- ═════ R Without 501: a save leaves the sale price ═════
\if :{?skip_install}
do $$ begin raise notice 'NOTE  R1 and I1-I5 are skipped: 501 is in already'; end $$;
create temp table before_install as
  select pg_temp.acl_of('save_product(uuid,jsonb,uuid[],uuid[])') a;
\else
do $r$
declare own uuid := pg_temp.id('own'); r jsonb; p uuid; sp uuid;
begin
  p := (pg_temp.save(own, null, jsonb_build_object('name', 'T501 Before', 'sku', 'T501-BEFORE', 'default_cost_price', '50'))->>'product_id')::uuid;
  sp := pg_temp.entry(own, null, p, 50);
  r := pg_temp.save(own, p, jsonb_build_object('default_cost_price', '60'));
  perform pg_temp.ok(not r ? 'special_price_set' and pg_temp.sale_price(sp) = 50 and pg_temp.store_price(pg_temp.id('sa'), p) = 60,
    'R1 without 501 the stores go to S$60 and the Special page stays at S$50');
end $r$;

-- ═════ I Install ═════
create temp table before_install as
  select pg_temp.acl_of('save_product(uuid,jsonb,uuid[],uuid[])') a, pg_temp.fp() f;
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
      execute current_setting('t501.mig');
      e := null;
    exception when others then e := sqlerrm; end;
    raise exception using errcode = 'T5019';
  exception when sqlstate 'T5019' then null;
  end;
  perform pg_temp.ok(e like '501: public.save_product(uuid,jsonb,uuid[],uuid[]) is not the version this was tested against%',
    'I1 a save_product other than the tested one stops it: ' || coalesce(e, 'it ran'));
  perform pg_temp.ok(pg_temp.fp() = f, 'I2 and nothing changed');
end $i$;

do $i$
declare f text;
begin
  execute current_setting('t501.mig');
  perform pg_temp.ok(pg_temp.md5_of('save_product(uuid,jsonb,uuid[],uuid[])') = '2b16ba59e2024b024317a642fa50b62b', 'I3 installed as tested');
  f := pg_temp.fp();
  execute current_setting('t501.mig');
  perform pg_temp.ok(pg_temp.fp() = f, 'I4 a second run changes nothing');
  perform pg_temp.ok(not exists (select 1 from public.products where sku like '501-%')
      and not exists (select 1 from public.stores where code like '501-%')
      and not exists (select 1 from public.profiles where email like '501chk-%')
      and not exists (select 1 from auth.users where email like '501chk-%')
      and not exists (select 1 from public.special_products where sku like '501-%')
      and not exists (select 1 from public.store_product_prices s join public.products p on p.id = s.product_id where p.name like '501 Check%')
      and not exists (select 1 from public.audit_logs where new_data->>'sku' like '501-%'),
    'I5 its self-test left no product, store, login, machine, price or Audit Log entry');
end $i$;
\endif

-- ═════ A-L ═════
do $t$
declare
  own uuid := pg_temp.id('own'); mgr uuid := pg_temp.id('mgr'); inv uuid := pg_temp.id('inv');
  adm uuid := pg_temp.id('adm'); stf uuid := pg_temp.id('stf'); gone uuid := pg_temp.id('gone');
  a uuid := pg_temp.id('sa'); b uuid := pg_temp.id('sb');
  n int := (select count(*) from public.stores where deleted_at is null and is_active);
  p uuid; sp uuid; q uuid; sq uuid; rent uuid; srent uuid; r jsonb; t text; x bigint; before_row jsonb; i1 uuid; i2 uuid; sale record;
begin
  -- ── A An Owner changes the price ──
  p := (pg_temp.save(own, null, jsonb_build_object('name', 'T501 Machine', 'sku', 'T501-MACH', 'default_cost_price', '100'))->>'product_id')::uuid;
  sp := pg_temp.entry(own, null, p, 100, 7);
  r := pg_temp.save(own, p, jsonb_build_object('default_cost_price', '120'));
  perform pg_temp.ok((r->>'special_price_set')::int = 1, 'A1 the answer says the sale price changed: ' || r::text);
  perform pg_temp.ok((r->>'prices_set')::int = n, 'A2 and every store: ' || r::text);
  perform pg_temp.ok(pg_temp.sale_price(sp) = 120, 'A3 the Special page says S$120');
  perform pg_temp.ok(pg_temp.store_price(a, p) = 120 and pg_temp.store_price(b, p) = 120, 'A4 so do both stores');
  perform pg_temp.ok(pg_temp.audits(sp) = 1, 'A5 one Audit Log entry');
  perform pg_temp.ok((select (l.old_data->>'sale_price')::numeric = 100 and (l.new_data->>'sale_price')::numeric = 120 and l.new_data->>'sku' = 'T501-MACH'
                             and l.new_data->>'product' = 'T501 Machine' and l.changed_by = own and l.module = 'catalogue'
                        from public.audit_logs l where l.table_name = 'special_products' and l.record_id = sp and l.action = 'special_product_sale_price'),
    'A6 it says what it was and what it is now, who, and the product');
  perform pg_temp.ok((select rate_day from public.special_products where id = sp) = 7, 'A7 its rental rate stays');

  -- ── B A Manager; Consignment; the rest of the entry stays ──
  t := pg_temp.try_as(own, format('select public.set_special_product_consignment(%L::uuid, true)::text', sp));
  perform pg_temp.ok(t like 'ok:%', 'B0 it goes on the Consignment tab: ' || t);
  before_row := (select to_jsonb(s) - 'sale_price' from public.special_products s where s.id = sp);
  r := pg_temp.save(mgr, p, jsonb_build_object('default_cost_price', '130'));
  perform pg_temp.ok((r->>'special_price_set')::int = 1 and pg_temp.sale_price(sp) = 130, 'B1 a Manager''s save: a product on Consignment follows');
  perform pg_temp.ok((select to_jsonb(s) - 'sale_price' from public.special_products s where s.id = sp) = before_row,
    'B2 rates, late fee, name, SKU, description and tab are as they were');
  perform pg_temp.ok((select l.changed_by = mgr from public.audit_logs l where l.table_name = 'special_products' and l.record_id = sp and l.action = 'special_product_sale_price'
                       and (l.new_data->>'sale_price')::numeric = 130), 'B3 the Audit Log names the Manager');

  -- ── C The price as it is ──
  x := pg_temp.audits(sp);
  r := pg_temp.save(mgr, p, jsonb_build_object('barcode', 'T501-BAR'));
  perform pg_temp.ok((r->>'special_price_set')::int = 0, 'C1 no price sent, the same price saved: nothing changes');
  r := pg_temp.save(mgr, p, jsonb_build_object('default_cost_price', '130.00'));
  perform pg_temp.ok((r->>'special_price_set')::int = 0, 'C2 the same price written otherwise: nothing changes');
  perform pg_temp.ok(pg_temp.audits(sp) = x, 'C3 no Audit Log entry');

  -- ── D The Special page's form sets it alone; the next save sets it back ──
  perform pg_temp.entry(mgr, sp, p, 99, 7);
  perform pg_temp.ok(pg_temp.sale_price(sp) = 99, 'D1 the Special page''s form changes it');
  perform pg_temp.ok((select default_cost_price from public.products where id = p) = 130 and pg_temp.store_price(a, p) = 130,
    'D2 and not the Product page or the stores');
  r := pg_temp.save(mgr, p, jsonb_build_object('barcode', 'T501-BAR2'));
  perform pg_temp.ok((r->>'special_price_set')::int = 1 and (r->>'prices_set')::int = 0, 'D3 a small edit on the Product page sets it back, and no store: ' || r::text);
  perform pg_temp.ok(pg_temp.sale_price(sp) = 130, 'D4 S$130 again');

  -- ── E A blank price ──
  r := pg_temp.save(own, p, jsonb_build_object('default_cost_price', '0'));
  perform pg_temp.ok((r->>'special_price_set')::int = 0 and pg_temp.sale_price(sp) = 130, 'E1 a price made blank leaves S$130');
  r := pg_temp.save(own, p, jsonb_build_object('default_cost_price', '140'));
  perform pg_temp.ok((r->>'special_price_set')::int = 1 and pg_temp.sale_price(sp) = 140, 'E2 a price again follows');

  -- ── F What stays ──
  rent := (pg_temp.save(own, null, jsonb_build_object('name', 'T501 Van', 'sku', 'T501-VAN'))->>'product_id')::uuid;
  srent := pg_temp.entry(own, null, rent, 0, 100);
  r := pg_temp.save(own, rent, jsonb_build_object('default_cost_price', '100'));
  perform pg_temp.ok((r->>'special_price_set')::int = 0 and pg_temp.sale_price(srent) = 0, 'F1 a machine that only rents keeps no sale price');
  perform pg_temp.ok((select rate_day from public.special_products where id = srent) = 100 and pg_temp.audits(srent) = 0, 'F2 its day rate stays; no Audit Log entry');
  q := (pg_temp.save(own, null, jsonb_build_object('name', 'T501 Gone', 'sku', 'T501-GONE', 'default_cost_price', '10'))->>'product_id')::uuid;
  sq := pg_temp.entry(own, null, q, 10);
  update public.special_products set deleted_at = now() where id = sq;
  r := pg_temp.save(own, q, jsonb_build_object('default_cost_price', '20'));
  perform pg_temp.ok((r->>'special_price_set')::int = 0 and pg_temp.sale_price(sq) = 10, 'F3 a deleted entry is left');
  x := pg_temp.audits(sp);
  r := pg_temp.save(own, q, jsonb_build_object('default_cost_price', '25'));
  perform pg_temp.ok(pg_temp.sale_price(sp) = 140 and pg_temp.audits(sp) = x, 'F4 another product''s entry is left');
  r := pg_temp.save(own, null, jsonb_build_object('name', 'T501 Plain', 'sku', 'T501-PLAIN', 'default_cost_price', '30'));
  perform pg_temp.ok((r->>'special_price_set')::int = 0 and (r->>'prices_set')::int = n, 'F5 a product with no entry: stores only');

  -- ── G Who ──
  x := pg_temp.audits(sp);
  r := pg_temp.save(inv, p, jsonb_build_object('default_cost_price', '150'));
  perform pg_temp.ok((r->>'special_price_set')::int = 0 and pg_temp.sale_price(sp) = 140 and pg_temp.audits(sp) = x, 'G1 an Inventory Manager''s save leaves the sale price');
  perform pg_temp.ok((select default_cost_price from public.products where id = p) = 150, 'G2 their figure is saved');
  t := pg_temp.try_as(inv, format('select public.upsert_special_product_from_product(%L::uuid, %L::uuid, 1)::text', sp, p));
  perform pg_temp.ok(t like '%Owner or Manager%' or t like '42501%' or t like '%not allowed%', 'G3 and the Special page''s form refuses them, as before: ' || t);
  r := pg_temp.save(own, p, '{}'::jsonb);
  perform pg_temp.ok((r->>'special_price_set')::int = 1 and pg_temp.sale_price(sp) = 150, 'G4 an Owner''s next save puts their figure on the Special page');
  t := pg_temp.save_says(adm, p, jsonb_build_object('default_cost_price', '1'));
  perform pg_temp.ok(t like '42501:%', 'G5 an Admin is refused, as before: ' || t);
  t := pg_temp.save_says(stf, p, jsonb_build_object('default_cost_price', '1'));
  perform pg_temp.ok(t like '42501:%', 'G6 Staff are refused, as before: ' || t);
  t := pg_temp.save_says(gone, p, jsonb_build_object('default_cost_price', '1'));
  perform pg_temp.ok(t not like 'ok:%', 'G7 an Owner switched off is refused: ' || t);
  perform pg_temp.ok(pg_temp.sale_price(sp) = 150, 'G8 none of them changed it');
  r := pg_temp.save(null, p, jsonb_build_object('default_cost_price', '151'));
  perform pg_temp.ok((r->>'special_price_set')::int = 0 and pg_temp.sale_price(sp) = 150, 'G9 a script with nobody signed in leaves it');
  r := pg_temp.save(own, p, jsonb_build_object('default_cost_price', '150'));

  -- ── H An entry switched off ──
  q := (pg_temp.save(own, null, jsonb_build_object('name', 'T501 Off', 'sku', 'T501-OFF', 'default_cost_price', '10'))->>'product_id')::uuid;
  sq := pg_temp.entry(own, null, q, 10, 0, false);
  r := pg_temp.save(own, q, jsonb_build_object('default_cost_price', '15'));
  perform pg_temp.ok((r->>'special_price_set')::int = 1 and pg_temp.sale_price(sq) = 15, 'H1 an entry switched off follows, ready for when it is on');
  perform pg_temp.ok(not (select is_active from public.special_products where id = sq), 'H2 and stays off');

  -- ── K Refused ──
  x := pg_temp.audits(sp);
  t := pg_temp.save_says(own, p, jsonb_build_object('default_cost_price', '1.234'));
  perform pg_temp.ok(t = 'P0001:Price must be 0 or more, with at most 2 decimal places.', 'K1 three decimals: ' || t);
  t := pg_temp.save_says(own, p, jsonb_build_object('sku', 'T501-VAN', 'default_cost_price', '9'));
  perform pg_temp.ok(t like 'P0001:That SKU already exists (T501 Van)%', 'K2 a SKU in use: ' || t);
  perform pg_temp.ok(pg_temp.sale_price(sp) = 150 and pg_temp.audits(sp) = x, 'K3 neither touched the sale price');
  -- A sale price that fails undoes the whole save.
  create function pg_temp.refuse_sale_price() returns trigger language plpgsql as $f$
  begin
    if new.sale_price is distinct from old.sale_price then raise exception 'T501 this sale price is refused'; end if;
    return new;
  end $f$;
  create trigger t501_refuse before update on public.special_products
    for each row execute function pg_temp.refuse_sale_price();
  t := pg_temp.save_says(own, p, jsonb_build_object('name', 'T501 Machine Renamed', 'default_cost_price', '155'));
  drop trigger t501_refuse on public.special_products;
  perform pg_temp.ok(t like '%T501 this sale price is refused%', 'K4 a sale price refused refuses the save: ' || t);
  perform pg_temp.ok((select name from public.products where id = p) = 'T501 Machine' and (select default_cost_price from public.products where id = p) = 150,
    'K5 the product is as it was');
  perform pg_temp.ok(pg_temp.store_price(a, p) = 150 and pg_temp.store_price(b, p) = 150, 'K6 so are the store prices');
  perform pg_temp.ok(pg_temp.sale_price(sp) = 150 and pg_temp.audits(sp) = x, 'K7 and the sale price; no Audit Log entry');

  -- ── L Invoices and sales ──
  i1 := pg_temp.invoice(own, a, sp);
  perform pg_temp.ok(pg_temp.line_price(i1) = 150, 'L1 a Special Product line takes the sale price');
  r := pg_temp.save(own, p, jsonb_build_object('default_cost_price', '200'));
  perform pg_temp.ok(pg_temp.line_price(i1) = 150 and (select total_amount from public.invoices where id = i1) = 150, 'L2 an invoice already raised keeps its price');
  perform pg_temp.pay(own, i1);
  select * into sale from public.special_sales s where s.invoice_id = i1;
  perform pg_temp.ok(sale.status::text = 'pending' and sale.unit_price = 150, 'L3 paid afterwards, its sale waits at the price it was sold for');
  i2 := pg_temp.invoice(own, b, sp);
  perform pg_temp.ok(pg_temp.line_price(i2) = 200, 'L4 the next invoice takes the new price, at either store');
  r := pg_temp.save(own, p, jsonb_build_object('default_cost_price', '210'));
  perform pg_temp.ok((select unit_price from public.special_sales s where s.id = sale.id) = 150, 'L5 a sale already waiting keeps its price');
end $t$;

-- ═════ N Grants and the other functions ═════
do $n$
begin
  perform pg_temp.ok(pg_temp.acl_of('save_product(uuid,jsonb,uuid[],uuid[])') = (select a from before_install), 'N1 save_product''s grants are unchanged');
  perform pg_temp.ok(not has_function_privilege('anon', 'public.save_product(uuid,jsonb,uuid[],uuid[])', 'execute'), 'N2 not open to anon');
  perform pg_temp.ok(pg_temp.md5_of('save_product(uuid,jsonb,uuid[],uuid[])') = '2b16ba59e2024b024317a642fa50b62b', 'N3 save_product is the tested text');
end $n$;
\if :{?skip_install}
\else
select pg_temp.ok(not exists (select 1 from before_md5 b where b.sig <> 'save_product(uuid,jsonb,uuid[],uuid[])'
                                 and b.m is distinct from pg_temp.md5_of(b.sig))
    and split_part(pg_temp.fp(), '/', 2) = split_part((select f from before_install), '/', 2),
  'N4 no other function changed, and none was added') \g /dev/null
\endif

-- ═════ U The UNDO ═════
do $u$
declare own uuid := pg_temp.id('own'); r jsonb; p uuid; sp uuid; e text;
begin
  -- It refuses anything but 501's version.
  execute replace(pg_get_functiondef('public.save_product(uuid,jsonb,uuid[],uuid[])'::regprocedure), '-- 420: the Products page''s Add and Edit', '-- changed since: the Products page''s Add and Edit');
  begin
    execute current_setting('t501.undo');
  exception when others then e := sqlerrm; end;
  perform pg_temp.ok(e like 'UNDO 501: public.save_product(uuid,jsonb,uuid[],uuid[]) is not 501''s version%', 'U1 UNDO refuses another version: ' || coalesce(e, 'it ran'));
  execute replace(pg_get_functiondef('public.save_product(uuid,jsonb,uuid[],uuid[])'::regprocedure), '-- changed since: the Products page''s Add and Edit', '-- 420: the Products page''s Add and Edit');

  execute current_setting('t501.undo');
  perform pg_temp.ok(pg_temp.md5_of('save_product(uuid,jsonb,uuid[],uuid[])') = '151ad4be5fe4742573ef6ec1b2cbe78a', 'U2 UNDO puts back 499''s text');
  p := (pg_temp.save(own, null, jsonb_build_object('name', 'T501 After Undo', 'sku', 'T501-UNDO', 'default_cost_price', '10'))->>'product_id')::uuid;
  sp := pg_temp.entry(own, null, p, 10);
  r := pg_temp.save(own, p, jsonb_build_object('default_cost_price', '20'));
  perform pg_temp.ok(not r ? 'special_price_set' and pg_temp.sale_price(sp) = 10, 'U3 a save no longer sets the sale price');
  perform pg_temp.ok(pg_temp.store_price(pg_temp.id('sa'), p) = 20, 'U4 it still sets the stores');
  perform pg_temp.ok((select sale_price from public.special_products where sku = 'T501-MACH') = 210, 'U5 sale prices already set stay set');
  execute current_setting('t501.mig');
  perform pg_temp.ok(pg_temp.md5_of('save_product(uuid,jsonb,uuid[],uuid[])') = '2b16ba59e2024b024317a642fa50b62b', 'U6 501 again puts it in');
end $u$;

-- ═════ Result ═════
do $res$
declare f int; n int;
begin
  select count(*) filter (where not ok), count(*) into f, n from t501_res;
  if f > 0 then raise exception '% of % checks failed: %', f, n, (select string_agg(label, ' | ' order by t501_res.n) from t501_res where not ok); end if;
  raise warning 'PASS all % checks', n;
end $res$;
rollback;
