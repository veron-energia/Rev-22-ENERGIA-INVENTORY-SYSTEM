-- 494: a consignment product's sale can go to a supplier, who sends it directly
-- to the customer (the user's design, 6 Nov 2026), through the app's own calls.
--
--   I  494 installs (two functions added, two replaced), a second run changes
--      nothing, its self-test leaves no row, and the new columns start empty.
--   T  The tick: a new product is not in consignment; an Owner and a Manager
--      set it, with an Audit Log entry; staff, an Admin, signed-out and a deleted
--      product are refused.
--   S  A sale with no stock anywhere is paid and waits, as it always could, and
--      only once the invoice is paid in full.
--   R  Release to a supplier: the sale is completed and names the supplier and
--      the note (a blank note is no note); it leaves the waiting list; no stock
--      moves and no movement is written; the Audit Log says so; commission is
--      what it was.
--   N  Refused: a product not in consignment, a supplier not linked, not active
--      or deleted, staff, an Admin, signed out, a rental, an unknown sale, no
--      supplier, a note over 500 characters, a sale whose invoice no longer
--      sells it, a second release, a warehouse release after a supplier, and a
--      location added by hand after one.
--   W  A consignment product that is in stock can still be released from a
--      warehouse, as any sale, and then cannot go to a supplier; sent by a
--      supplier instead, its warehouse and store stock stay as they were, and a
--      refund brings none back; an ordinary product's sale goes as before and is
--      offered no supplier.
--   B  After release, a full refund moves no stock and asks about none, the sale
--      stays as it was; reopened and paid again it raises no second sale. So
--      does a cancellation. Still waiting, a refund cancels it as before (393).
--   U  Unticked: a waiting sale can no longer go to a supplier, and one already
--      sent keeps its supplier.
--   G  Grants: signed-in logins and the service role alone.
--
-- Run on a copy of production at 493 or later (createdb -T of a template equal
-- to it; never the template itself):
--   psql -d <copy> -v ON_ERROR_STOP=1 -f scripts/special/tests/consignment-494.sql
-- (with -v skip_install=1 where 494 is in). Every check runs, then the file fails
-- if any did. Everything is rolled back. Every name, phone and email is invented
-- (+61 2 5550 ...., @example.invalid); the repository is public.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlerrm; end$$;
create function pg_temp.fp() returns text language sql set search_path = public as
$$ select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || ' ' || count(*)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') $$;

create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
-- Signed in as a login of the fixtures, or signed out (null).
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true),
          set_config('request.jwt.claim.role', case when key is null then 'anon' else 'authenticated' end, true),
          set_config('request.jwt.claims', '', true) $$;

-- ═════ I Installs ═════
create temp table before_install as select pg_temp.fp() f;
\if :{?skip_install}
do $$ begin raise notice 'NOTE  I1-I2 are skipped: 494 is in already'; end $$;
\else
\ir ../../../supabase/494_consignment_sale_released_to_supplier.sql
create temp table after_first as select pg_temp.fp() f;
\ir ../../../supabase/494_consignment_sale_released_to_supplier.sql
select pg_temp.check((select f from after_first) = pg_temp.fp()
    and split_part(pg_temp.fp(), ' ', 2)::int = split_part((select f from before_install), ' ', 2)::int + 2,
  'I1 494 adds two functions, and a second run changes nothing: ' || pg_temp.fp());
select pg_temp.check(not exists (select 1 from public.suppliers where name like '494 Check%')
    and not exists (select 1 from public.special_sales where sale_no like '494-CHECK%')
    and not exists (select 1 from auth.users where email like '494chk-%'),
  'I2 its self-tests left no supplier, no sale and no login');
\endif
select pg_temp.check(not exists (select 1 from public.special_products where is_consignment)
    and not exists (select 1 from public.special_sales where supplier_id is not null or deliver_to is not null),
  'I3 on a copy of production no product is in consignment and no sale has a supplier');

-- ═════ Fixtures (invented) ═════
do $$
declare sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  k text; u uuid; st uuid; wh uuid; v uuid; aff uuid; ph text[];
begin
  foreach k in array array['owner', 'manager', 'staff', 'admin'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'c494-' || k || '-' || sfx || '@example.invalid');
    insert into public.profiles(id, full_name, email, role, is_active)
      values (u, 'C494 ' || k, 'c494-' || k || '-' || sfx || '@example.invalid', k::public.user_role, true);
    insert into fx values (k, u);
  end loop;
  perform pg_temp.as_user('owner');
  insert into public.stores(name, code, country_code) values ('C494 Store ' || sfx, 'C494' || sfx, 'SG') returning id into st; insert into fx values ('store', st);
  insert into public.warehouses(name, code) values ('C494 Warehouse', 'C494W' || sfx) returning id into wh; insert into fx values ('wh', wh);
  insert into public.payment_methods(name, is_active) values ('C494 Cash ' || sfx, true) returning id into v; insert into fx values ('cash', v);
  -- Fictional phones no customer holds: an affiliate, and a buyer they referred.
  ph := array(select '+6125550' || lpad(n::text, 4, '0') from generate_series(1000, 9999) n
               where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = '+6125550' || lpad(n::text, 4, '0'))
               order by n limit 2);
  insert into public.customers(full_name, phone) values ('C494 Affiliate', ph[1]) returning id into aff;
  insert into public.customer_affiliates(customer_id, status, activated_at, referral_code) values (aff, 'active', now(), 'C494A' || upper(sfx));
  insert into public.customers(full_name, phone, referred_by) values ('C494 Buyer', ph[2], aff) returning id into v; insert into fx values ('buyer', v);
  -- Three machines: no stock anywhere, in stock, and not in consignment at all.
  insert into public.products(name, sku, product_type) values ('C494 Nowhere', 'C494-N-' || sfx, 'third_party') returning id into v; insert into fx values ('p_none', v);
  insert into public.products(name, sku, product_type) values ('C494 Held', 'C494-H-' || sfx, 'third_party') returning id into v; insert into fx values ('p_held', v);
  insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (wh, v, 5);
  insert into public.products(name, sku, product_type) values ('C494 Plain', 'C494-P-' || sfx, 'third_party') returning id into v; insert into fx values ('p_plain', v);
  insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (wh, v, 5);
  insert into public.products(name, sku, product_type) values ('C494 Gone', 'C494-G-' || sfx, 'third_party') returning id into v; insert into fx values ('p_gone', v);
  -- Suppliers: one linked, one linked but switched off, one linked but deleted, one not linked.
  insert into public.suppliers(name, phone) values ('C494 Supplier ' || sfx, '+61255509901') returning id into v; insert into fx values ('sup', v);
  insert into public.product_suppliers(product_id, supplier_id) select pg_temp.fx(p), v from unnest(array['p_none', 'p_held', 'p_plain']) p;
  insert into public.suppliers(name, is_active) values ('C494 Off ' || sfx, false) returning id into v; insert into fx values ('sup_off', v);
  insert into public.product_suppliers(product_id, supplier_id) values (pg_temp.fx('p_none'), v);
  insert into public.suppliers(name, deleted_at) values ('C494 Gone ' || sfx, now()) returning id into v; insert into fx values ('sup_gone', v);
  insert into public.product_suppliers(product_id, supplier_id) values (pg_temp.fx('p_none'), v);
  insert into public.suppliers(name) values ('C494 Other ' || sfx) returning id into v; insert into fx values ('sup_other', v);
  -- Special products: sold at S$1,000, the first two also rented.
  insert into fx values ('sp_none', public.upsert_special_product_from_product(null, pg_temp.fx('p_none'), 1000, 0, 0, 100, 0, 0));
  insert into fx values ('sp_held', public.upsert_special_product_from_product(null, pg_temp.fx('p_held'), 1000, 0, 0, 100, 0, 0));
  insert into fx values ('sp_plain', public.upsert_special_product_from_product(null, pg_temp.fx('p_plain'), 1000));
end $$;

create function pg_temp.sale_line(sp text, qty int default 1) returns jsonb language sql as
$$ select jsonb_build_object('kind', 'special_product', 'special_product_id', pg_temp.fx(sp), 'quantity', qty) $$;
create function pg_temp.mk(items jsonb) returns uuid language sql as
$$ select public.create_invoice_with_details(pg_temp.fx('store'), pg_temp.fx('buyer'), items,
            jsonb_build_object('business_date', public.sg_today()::text)) $$;
create function pg_temp.pay(inv uuid, amount numeric default null) returns void language sql as
$$ select public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'),
     'amount', coalesce(amount, public.invoice_charge_total(inv) - public.invoice_net_received(inv))))) $$;
-- A paid invoice of one machine, and its sale.
create function pg_temp.sold(sp text) returns uuid language plpgsql as
$$declare inv uuid; begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line(sp)));
  perform pg_temp.pay(inv);
  return (select s.id from public.special_sales s where s.invoice_id = inv);
end$$;
create function pg_temp.invoice_of(sale uuid) returns uuid language sql as
$$ select invoice_id from public.special_sales where id = sale $$;
create function pg_temp.listed(sale uuid) returns boolean language sql as
$$ select exists (select 1 from public.special_docs_awaiting_fulfilment() w where w.doc_id = sale) $$;
create function pg_temp.stock_of(p text) returns bigint language sql as
$$ select coalesce((select sum(current_qty) from public.warehouse_inventory where product_id = pg_temp.fx(p)), 0)
        + coalesce((select sum(current_qty) from public.store_inventory where product_id = pg_temp.fx(p)), 0) $$;
create function pg_temp.moves_of(p text) returns bigint language sql as
$$ select count(*) from public.stock_movements where product_id = pg_temp.fx(p) $$;
create function pg_temp.release_sql(sale uuid, sup text, note text default null) returns text language sql as
$$ select format('select public.release_special_sale_to_supplier(%L, %L, %L)', sale, pg_temp.fx(sup), note) $$;
create function pg_temp.earned(inv uuid) returns text language sql as
$$ select coalesce(string_agg(tier::text || ' ' || product_type::text || ' ' || commission_amount, ', ' order by tier::text), '-')
     from public.commissions where invoice_id = inv and status::text <> 'reversed' $$;

-- ═════ T The tick ═════
do $$
declare gone uuid;
begin
  perform pg_temp.as_user('owner');
  perform pg_temp.check(not (select is_consignment from public.special_products where id = pg_temp.fx('sp_none')),
    'T1 a new special product is not in consignment');
  perform public.set_special_product_consignment(pg_temp.fx('sp_none'), true);
  perform pg_temp.check((select is_consignment from public.special_products where id = pg_temp.fx('sp_none'))
      and exists (select 1 from public.audit_logs l where l.record_id = pg_temp.fx('sp_none')
                    and l.action = 'special_product_consignment' and l.changed_by = pg_temp.fx('owner')
                    and l.new_data->>'is_consignment' = 'true' and l.old_data->>'is_consignment' = 'false'),
    'T2 an Owner ticks it, with an Audit Log entry saying who and what changed');
  perform pg_temp.as_user('manager');
  perform public.set_special_product_consignment(pg_temp.fx('sp_held'), true);
  perform pg_temp.check((select is_consignment from public.special_products where id = pg_temp.fx('sp_held')),
    'T3 so does a Manager');
  perform public.set_special_product_consignment(pg_temp.fx('sp_held'), true);
  perform pg_temp.check((select count(*) from public.audit_logs l where l.record_id = pg_temp.fx('sp_held') and l.action = 'special_product_consignment') = 1,
    'T4 ticking it again changes nothing and writes no second entry');
  perform pg_temp.as_user('staff');
  perform pg_temp.check(pg_temp.err(format('select public.set_special_product_consignment(%L, true)', pg_temp.fx('sp_plain'))) = 'Your role cannot do this.',
    'T5 staff are refused');
  perform pg_temp.as_user('admin');
  perform pg_temp.check(pg_temp.err(format('select public.set_special_product_consignment(%L, true)', pg_temp.fx('sp_plain'))) = 'Your role cannot do this.',
    'T6 so is an Admin');
  perform pg_temp.as_user(null);
  perform pg_temp.check(pg_temp.err(format('select public.set_special_product_consignment(%L, true)', pg_temp.fx('sp_plain'))) = 'Only active Energia staff can do this.',
    'T7 and signed out');
  perform pg_temp.as_user('owner');
  perform pg_temp.check(pg_temp.err(format('select public.set_special_product_consignment(%L, true)', gen_random_uuid())) = 'That special product does not exist',
    'T8 an unknown product is refused');
  perform pg_temp.check(not (select is_consignment from public.special_products where id = pg_temp.fx('sp_plain')),
    'T9 none of those changed it');
  -- A deleted product, as the page deletes one.
  gone := public.upsert_special_product_from_product(null, pg_temp.fx('p_gone'), 1000);
  update public.special_products set deleted_at = now(), is_active = false where id = gone;
  perform pg_temp.check(pg_temp.err(format('select public.set_special_product_consignment(%L, true)', gone)) = 'That special product does not exist'
      and not (select is_consignment from public.special_products where id = gone),
    'T10 a deleted product is refused too');
end $$;

-- ═════ S A sale with no stock waits, once paid in full ═════
do $$
declare inv uuid; sale uuid;
begin
  perform pg_temp.as_user('owner');
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('sp_none')));
  perform pg_temp.check(not exists (select 1 from public.special_sales where invoice_id = inv),
    'S1 unpaid: no sale yet, so nothing on the waiting list');
  perform pg_temp.pay(inv, 400);
  perform pg_temp.check(not exists (select 1 from public.special_sales where invoice_id = inv),
    'S2 after a deposit: still none (a supplier can be phoned; Supplier is chosen once it is paid)');
  perform pg_temp.pay(inv);
  select id into sale from public.special_sales where invoice_id = inv;
  insert into fx values ('s_main', sale);
  perform pg_temp.check(sale is not null and pg_temp.listed(sale) and pg_temp.stock_of('p_none') = 0 and pg_temp.moves_of('p_none') = 0,
    'S3 paid in full with no stock anywhere: it goes through and waits, and no stock has moved');
end $$;

-- ═════ N Refused ═════
do $$
declare sale uuid := pg_temp.fx('s_main'); plain uuid; rental uuid; inv uuid; unsold uuid;
begin
  perform pg_temp.as_user('owner');
  plain := pg_temp.sold('sp_plain');
  insert into fx values ('s_plain', plain);
  perform pg_temp.check(pg_temp.err(pg_temp.release_sql(plain, 'sup')) like '"C494 Plain" is not a consignment product%',
    'N1 a product not in consignment, even with a supplier linked: ' || pg_temp.err(pg_temp.release_sql(plain, 'sup')));
  perform pg_temp.check(pg_temp.err(pg_temp.release_sql(sale, 'sup_other')) like 'That supplier is not linked to "C494 Nowhere"%',
    'N2 a supplier not linked to the product');
  perform pg_temp.check(pg_temp.err(pg_temp.release_sql(sale, 'sup_off')) like 'That supplier is not linked%',
    'N3 a linked supplier switched off');
  perform pg_temp.check(pg_temp.err(pg_temp.release_sql(sale, 'sup_gone')) like 'That supplier is not linked%',
    'N4 a linked supplier deleted');
  perform pg_temp.check(pg_temp.err(format('select public.release_special_sale_to_supplier(%L, null, null)', sale)) = 'Choose the supplier',
    'N5 no supplier');
  perform pg_temp.check(pg_temp.err(pg_temp.release_sql(sale, 'sup', repeat('x', 501))) = 'The delivery note is too long (500 characters at most)',
    'N6 a note over 500 characters');
  perform pg_temp.check(pg_temp.err(pg_temp.release_sql(gen_random_uuid(), 'sup')) = 'That sale is not awaiting a location',
    'N7 an unknown sale');
  -- A rental of a consignment product: not a sale, so it cannot go to a supplier.
  inv := pg_temp.mk(jsonb_build_array(jsonb_build_object('kind', 'rental', 'special_product_id', pg_temp.fx('sp_none'), 'quantity', 1,
           'rental_rate_type', 'month', 'rental_periods', 1, 'rental_start_date', public.sg_today()::text)));
  perform pg_temp.pay(inv);
  select id into rental from public.rentals where invoice_id = inv;
  perform pg_temp.check(rental is not null and pg_temp.listed(rental)
      and pg_temp.err(pg_temp.release_sql(rental, 'sup')) = 'That sale is not awaiting a location',
    'N8 a rental of a consignment product waits for a warehouse and cannot go to a supplier');
  perform pg_temp.as_user('staff');
  perform pg_temp.check(pg_temp.err(pg_temp.release_sql(sale, 'sup')) = 'Your role cannot do this.', 'N9 staff');
  perform pg_temp.as_user('admin');
  perform pg_temp.check(pg_temp.err(pg_temp.release_sql(sale, 'sup')) = 'Your role cannot do this.', 'N10 an Admin');
  perform pg_temp.as_user(null);
  perform pg_temp.check(pg_temp.err(pg_temp.release_sql(sale, 'sup')) = 'Only active Energia staff can do this.', 'N11 signed out');
  perform pg_temp.as_user('owner');
  perform pg_temp.check(pg_temp.listed(sale)
      and (select supplier_id from public.special_sales where id = sale) is null
      and (select status from public.special_sales where id = sale) = 'pending',
    'N12 after all of those the sale is still waiting, untouched');
  -- 393's rule: a sale left waiting on an invoice that no longer sells it (an
  -- older row: since 393 a refund or a cancellation cancels what is waiting).
  unsold := pg_temp.sold('sp_none');
  update public.invoices set status = 'refunded' where id = pg_temp.invoice_of(unsold);
  perform pg_temp.check(pg_temp.err(pg_temp.release_sql(unsold, 'sup')) like '% cannot be released: its invoice % was refunded. It is no longer waiting for a warehouse.'
      and (select supplier_id from public.special_sales where id = unsold) is null,
    'N13 a sale whose invoice no longer sells it: ' || pg_temp.err(pg_temp.release_sql(unsold, 'sup')));
end $$;

-- ═════ R Release to a supplier ═════
do $$
declare sale uuid := pg_temp.fx('s_main'); r public.special_sales%rowtype; was text; ans jsonb; blank uuid;
begin
  perform pg_temp.as_user('manager');
  was := pg_temp.earned(pg_temp.invoice_of(sale));
  ans := public.release_special_sale_to_supplier(sale, pg_temp.fx('sup'), '  12 Fixture Road  ');
  select * into r from public.special_sales where id = sale;
  perform pg_temp.check(r.status = 'completed' and r.supplier_id = pg_temp.fx('sup') and r.deliver_to = '12 Fixture Road'
      and r.warehouse_id is null and r.source_store_id is null and r.source_type is null
      and r.fulfilled_by = pg_temp.fx('manager') and r.fulfilled_at is not null,
    'R1 a Manager releases it: completed, naming the supplier and the note (trimmed), no warehouse or store');
  perform pg_temp.check(ans->>'location_type' = 'supplier' and ans->>'doc_no' = r.sale_no and ans->>'product' = 'C494 Nowhere',
    'R2 the answer says what happened: ' || ans::text);
  perform pg_temp.check(not pg_temp.listed(sale), 'R3 it has left the waiting list');
  perform pg_temp.check(pg_temp.stock_of('p_none') = 0 and pg_temp.moves_of('p_none') = 0,
    'R4 no stock moved and no movement was written');
  perform pg_temp.check(exists (select 1 from public.audit_logs l where l.record_id = sale and l.action = 'special_doc_fulfilled'
        and l.changed_by = pg_temp.fx('manager') and l.new_data->>'location_type' = 'supplier'
        and l.new_data->>'location' = pg_temp.fx('sup')::text and l.new_data->>'deliver_to' = '12 Fixture Road'),
    'R5 the Audit Log has it, as a release, saying who, which supplier and the note');
  perform pg_temp.check(pg_temp.earned(pg_temp.invoice_of(sale)) = was and was <> '-',
    'R6 commission is what the payment earned: ' || was);
  perform pg_temp.check(pg_temp.err(pg_temp.release_sql(sale, 'sup')) = 'That sale is not awaiting a location',
    'R7 it cannot go to a supplier twice');
  perform pg_temp.check(pg_temp.err(format('select public.fulfil_special_doc(''special_sale'', %L, %L, ''warehouse'')', sale, pg_temp.fx('wh'))) = 'That sale is not awaiting a location',
    'R8 nor be released from a warehouse afterwards');
  perform pg_temp.check(pg_temp.err(format('update public.special_sales set warehouse_id = %L where id = %L', pg_temp.fx('wh'), sale)) like '%special_sales_supplier_has_no_location%',
    'R9 and the table itself refuses a supplier with a warehouse');
  perform pg_temp.as_user('owner');
  blank := pg_temp.sold('sp_none');
  perform public.release_special_sale_to_supplier(blank, pg_temp.fx('sup'), '   ');
  perform pg_temp.check((select deliver_to from public.special_sales where id = blank) is null
      and (select supplier_id from public.special_sales where id = blank) = pg_temp.fx('sup'),
    'R10 a blank note is no note');
end $$;

-- ═════ W From stock, as before ═════
do $$
declare sale uuid; plain uuid := pg_temp.fx('s_plain'); sent uuid; line uuid; pay uuid;
begin
  perform pg_temp.as_user('owner');
  sale := pg_temp.sold('sp_held');
  perform public.fulfil_special_doc('special_sale', sale, pg_temp.fx('wh'), 'warehouse');
  perform pg_temp.check((select status from public.special_sales where id = sale) = 'completed'
      and (select warehouse_id from public.special_sales where id = sale) = pg_temp.fx('wh')
      and (select supplier_id from public.special_sales where id = sale) is null
      and pg_temp.stock_of('p_held') = 4 and pg_temp.moves_of('p_held') = 1,
    'W1 a consignment product in stock can be released from a warehouse: stock goes down by one, as any sale');
  perform pg_temp.check(pg_temp.err(pg_temp.release_sql(sale, 'sup')) = 'That sale is not awaiting a location',
    'W2 and then cannot go to a supplier');
  -- In stock at a warehouse and a store, and sent by the supplier all the same.
  insert into public.store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('store'), pg_temp.fx('p_held'), 3);
  sent := pg_temp.sold('sp_held');
  perform public.release_special_sale_to_supplier(sent, pg_temp.fx('sup'), null);
  perform pg_temp.check((select current_qty from public.warehouse_inventory where warehouse_id = pg_temp.fx('wh') and product_id = pg_temp.fx('p_held')) = 4
      and (select current_qty from public.store_inventory where store_id = pg_temp.fx('store') and product_id = pg_temp.fx('p_held')) = 3
      and pg_temp.moves_of('p_held') = 1 and not pg_temp.listed(sent),
    'W4 the same product sent by a supplier: its warehouse and store stock stay as they were, and no movement is written');
  select invoice_item_id into line from public.special_sales where id = sent;
  select id into pay from public.invoice_payments where invoice_id = pg_temp.invoice_of(sent) limit 1;
  perform public.refund_invoice_recorded(pg_temp.invoice_of(sent),
    jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'amount', public.invoice_payment_remaining(pay))),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', public.invoice_payment_remaining(pay))),
    '[]', 'Fixture refund', gen_random_uuid());
  perform pg_temp.check((select status::text from public.invoices where id = pg_temp.invoice_of(sent)) = 'refunded'
      and pg_temp.stock_of('p_held') = 7 and pg_temp.moves_of('p_held') = 1,
    'W5 and its refund brings no stock back');
  perform public.fulfil_special_doc('special_sale', plain, pg_temp.fx('wh'), 'warehouse');
  perform pg_temp.check(not pg_temp.listed(plain) and pg_temp.stock_of('p_plain') = 4,
    'W3 an ordinary product goes as before');
end $$;

-- ═════ B Refunds and reopening ═════
do $$
declare sale uuid := pg_temp.fx('s_main'); inv uuid := pg_temp.invoice_of(sale); line uuid; pay uuid; waiting uuid; inv2 uuid; other uuid; inv3 uuid;
begin
  perform pg_temp.as_user('owner');
  select invoice_item_id into line from public.special_sales where id = sale;
  select id into pay from public.invoice_payments where invoice_id = inv order by public.invoice_payment_remaining(id) desc limit 1;
  perform public.refund_invoice_recorded(inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'amount', public.invoice_payment_remaining(pay))),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', public.invoice_payment_remaining(pay))),
    '[]', 'Fixture refund', gen_random_uuid());
  -- The deposit's payment too, so the whole S$1,000 goes back.
  select id into pay from public.invoice_payments where invoice_id = inv and public.invoice_payment_remaining(id) > 0 limit 1;
  if pay is not null then
    perform public.refund_invoice_recorded(inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'amount', public.invoice_payment_remaining(pay))),
      jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', public.invoice_payment_remaining(pay))),
      '[]', 'Fixture refund', gen_random_uuid());
  end if;
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'refunded',
    'B1 a full refund goes through with no stock answer asked of it');
  perform pg_temp.check((select status from public.special_sales where id = sale) = 'completed'
      and (select supplier_id from public.special_sales where id = sale) = pg_temp.fx('sup')
      and pg_temp.stock_of('p_none') = 0 and pg_temp.moves_of('p_none') = 0,
    'B2 the sale keeps its supplier and no stock came back: it goes back to the supplier');
  perform public.reopen_invoice(inv, 'Customer came back for it', gen_random_uuid());
  perform pg_temp.pay(inv);
  perform pg_temp.check((select count(*) from public.special_sales where invoice_id = inv) = 1 and not pg_temp.listed(sale),
    'B3 reopened and paid again: no second sale, nothing waiting');

  other := pg_temp.sold('sp_none');
  inv2 := pg_temp.invoice_of(other);
  perform public.release_special_sale_to_supplier(other, pg_temp.fx('sup'), null);
  perform public.cancel_invoice_recorded(inv2, 'Fixture cancellation', gen_random_uuid());
  perform pg_temp.check((select status from public.special_sales where id = other) = 'completed' and pg_temp.stock_of('p_none') = 0,
    'B4 cancelled after release: the sale stays as it was, no stock came back');

  waiting := pg_temp.sold('sp_none');
  inv3 := pg_temp.invoice_of(waiting);
  perform public.cancel_invoice_recorded(inv3, 'Fixture cancellation', gen_random_uuid());
  perform pg_temp.check((select status from public.special_sales where id = waiting) = 'cancelled' and not pg_temp.listed(waiting)
      and pg_temp.err(pg_temp.release_sql(waiting, 'sup')) = 'That sale is not awaiting a location',
    'B5 cancelled while still waiting: cancelled as before (393), and cannot go to a supplier');
end $$;

-- ═════ U Unticked ═════
do $$
declare waiting uuid; sent uuid := pg_temp.fx('s_main');
begin
  perform pg_temp.as_user('owner');
  waiting := pg_temp.sold('sp_none');
  perform public.set_special_product_consignment(pg_temp.fx('sp_none'), false);
  perform pg_temp.check(pg_temp.err(pg_temp.release_sql(waiting, 'sup')) like '"C494 Nowhere" is not a consignment product%' and pg_temp.listed(waiting),
    'U1 unticked: a waiting sale can no longer go to a supplier, and still waits');
  perform pg_temp.check((select supplier_id from public.special_sales where id = sent) = pg_temp.fx('sup'),
    'U2 one already sent keeps its supplier');
end $$;

-- ═════ G Grants ═════
select pg_temp.check(not has_function_privilege('anon', f::regprocedure, 'execute')
    and has_function_privilege('authenticated', f::regprocedure, 'execute')
    and has_function_privilege('service_role', f::regprocedure, 'execute'),
  'G1 ' || f || ': signed-in logins and the service role alone')
  from unnest(array['public.release_special_sale_to_supplier(uuid,uuid,text)', 'public.set_special_product_consignment(uuid,boolean)']) f;

do $$
declare n int; msgs text;
begin
  select count(*), string_agg(msg, E'\n') into n, msgs from failed;
  if n > 0 then raise exception '% check(s) failed:%', n, E'\n' || msgs; end if;
  raise notice 'All 494 checks passed.';
end $$;
rollback;
