-- Make FOC, Remove FOC, the affiliate and Fulfil from warehouse (416:
-- INVOICES-CREATE-8, INVOICES-CREATE-M2, INVOICES-CREATE-16).
--
--   F1 Make FOC and Remove FOC on an unpaid invoice work as before; each
--      raises edit_count, and the invoice stays unpaid (no payment, so its
--      status cannot go stale).
--   F2 An Edit Invoice opened before Make FOC is told the invoice changed
--      (expected_edit_count), and saves nothing.
--   F3 On a part-paid invoice both are refused and the lines are untouched.
--   F4 On a deleted invoice both are refused; on a locked one Remove FOC is
--      too.
--   F5 The affiliate: a change raises edit_count, the same affiliate again
--      does not, and a deleted invoice is not found.
--   F6 Fulfil from warehouse: a Manager of another store is refused; an
--      Owner's change raises edit_count, the same warehouse again does not,
--      clearing it does, and a deleted invoice is not found.
--
-- Needs 416 (psql -v mig=supabase/416_invoice_editing_foc_and_payment_guards.sql
-- installs it after "begin;"). Disposable database only; everything is rolled
-- back. Fixtures are invented.
\set ON_ERROR_STOP on
begin;
\if :{?prelude}
\i :prelude
\endif
\if :{?mig}
\i :mig
\endif
set local lock_timeout = '10s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', pg_temp.fx(key)::text, true) $$;
-- An unpaid invoice of two pairs of socks (two lines) at a store, by the Owner.
create function pg_temp.sale(st text) returns uuid language plpgsql as
$$begin
  perform pg_temp.as_user('o');
  return public.create_invoice(pg_temp.fx(st), pg_temp.fx('c'), null, jsonb_build_array(
    jsonb_build_object('kind','product','product_id',pg_temp.fx('socks'),'quantity',1),
    jsonb_build_object('kind','product','product_id',pg_temp.fx('socks'),'quantity',1)));
end$$;
create function pg_temp.line(inv uuid, n int) returns uuid language sql as
$$ select id from public.invoice_items where invoice_id = inv order by id offset n - 1 limit 1 $$;
create function pg_temp.edits(inv uuid) returns int language sql as
$$ select coalesce(edit_count, 0) from public.invoices where id = inv $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlerrm; end$$;
create function pg_temp.foc(item uuid) returns text language sql as
$$ select pg_temp.err(format('select public.apply_line_foc(%L, null, null, %L)', item, 'Event giveaway')) $$;
create function pg_temp.unfoc(item uuid) returns text language sql as
$$ select pg_temp.err(format('select public.remove_line_foc(%L, null)', item)) $$;

do $$
declare o uuid := gen_random_uuid(); m uuid := gen_random_uuid(); sfx text := left(md5(random()::text), 6);
  st_a uuid; st_b uuid; c uuid; p uuid; pm uuid; wh uuid; r uuid; aff uuid;
begin
  insert into auth.users(id,email) values (o,'fg416-o-'||sfx||'@tests.invalid'),(m,'fg416-m-'||sfx||'@tests.invalid');
  insert into profiles(id,full_name,email,role) values (o,'FG Owner','fg416-o-'||sfx||'@tests.invalid','owner'),
                                                       (m,'FG Manager','fg416-m-'||sfx||'@tests.invalid','manager');
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into stores(name,code,country_code) values ('FG Store A','FGA'||sfx,'SG') returning id into st_a;
  insert into stores(name,code,country_code) values ('FG Store B','FGB'||sfx,'SG') returning id into st_b;
  -- The Manager works at A only.
  insert into user_store_assignments(user_id,store_id) values (m, st_a);
  insert into customers(full_name,phone) values ('FG Buyer','+61491570157') returning id into c;
  insert into customers(full_name,phone) values ('FG Referrer','+61491570157') returning id into r;
  insert into customer_affiliates(customer_id,status,store_id,activated_at) values (r,'active',st_a,now()) returning id into aff;
  insert into payment_methods(name,is_active) values ('FG Cash '||sfx,true) returning id into pm;
  insert into products(name,sku,product_type) values ('FG Socks','FGS-'||sfx,'own') returning id into p;
  insert into store_inventory(store_id,product_id,current_qty) values (st_a,p,100),(st_b,p,100);
  perform set_product_prices(st_a,p,100,100,'available');
  perform set_product_prices(st_b,p,100,100,'available');
  insert into warehouses(name,code) values ('FG Warehouse','FGW'||sfx) returning id into wh;
  insert into warehouse_inventory(warehouse_id,product_id,current_qty) values (wh,p,100);
  insert into fx values ('o',o),('m',m),('A',st_a),('B',st_b),('c',c),('socks',p),('cash',pm),('wh',wh),('aff',aff);
end $$;

-- ═════ F1–F2 Unpaid: works, raises edit_count, a stale edit is told ═════
do $$
declare inv uuid := pg_temp.sale('A'); it uuid; e text; n0 int;
begin
  it := pg_temp.line(inv, 1);
  n0 := pg_temp.edits(inv);
  e := pg_temp.foc(it);
  perform pg_temp.check(e is null and pg_temp.edits(inv) = n0 + 1
      and (select (status, total_amount) = ('unpaid'::invoice_status, 100.00::numeric) from public.invoices where id = inv),
    'F1 Make FOC on an unpaid invoice works, raises edit_count and leaves it unpaid at S$100.00: ' || coalesce(e, 'done'));
  e := pg_temp.err(format('select public.correct_invoice(%L, (select jsonb_agg(jsonb_build_object(''invoice_item_id'', id, ''kind'', ''product'', ''product_id'', product_id, ''quantity'', 2)) from public.invoice_items where invoice_id = %L), %L, %L, null)',
         inv, inv, jsonb_build_object('expected_edit_count', n0), 'Edit opened before Make FOC'));
  perform pg_temp.check(e = 'This invoice was changed by another user. Reload it before saving.'
      and (select foc_quantity from public.invoice_items where id = it) = 1,
    'F2 an Edit Invoice opened before Make FOC is told the invoice changed, and its FOC stands: ' || coalesce(e, 'saved'));
  e := pg_temp.unfoc(it);
  perform pg_temp.check(e is null and pg_temp.edits(inv) = n0 + 2
      and (select (status, total_amount) = ('unpaid'::invoice_status, 200.00::numeric) from public.invoices where id = inv),
    'F1 Remove FOC works, raises edit_count and leaves it unpaid at S$200.00: ' || coalesce(e, 'done'));
end $$;

-- ═════ F3 Part paid ═════
do $$
declare inv uuid := pg_temp.sale('A'); a uuid; b uuid; e text; n0 int;
  msg text := 'FOC can only be changed before any payment is recorded on the invoice.';
begin
  a := pg_temp.line(inv, 1); b := pg_temp.line(inv, 2);
  perform pg_temp.foc(a);
  perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 40)));
  n0 := pg_temp.edits(inv);
  perform pg_temp.check((select status from public.invoices where id = inv) = 'partially_paid', 'F3 fixture: part paid, S$40.00 of S$100.00');
  e := pg_temp.foc(b);
  perform pg_temp.check(e = msg and (select coalesce(foc_quantity, 0) from public.invoice_items where id = b) = 0 and pg_temp.edits(inv) = n0,
    'F3 Make FOC on a part-paid invoice is refused, and the line is untouched: ' || coalesce(e, 'done'));
  e := pg_temp.unfoc(a);
  perform pg_temp.check(e = msg and (select foc_quantity from public.invoice_items where id = a) = 1
      and (select total_amount from public.invoices where id = inv) = 100,
    'F3 Remove FOC on a part-paid invoice is refused, and the line keeps its FOC: ' || coalesce(e, 'done'));
end $$;

-- ═════ F4 Deleted, locked ═════
do $$
declare inv uuid := pg_temp.sale('A'); a uuid; b uuid; e text;
begin
  a := pg_temp.line(inv, 1); b := pg_temp.line(inv, 2);
  perform pg_temp.foc(a);
  update public.invoices set deleted_at = now() where id = inv;
  e := pg_temp.unfoc(a);
  perform pg_temp.check(e = 'Invoice has been deleted' and (select foc_quantity from public.invoice_items where id = a) = 1,
    'F4 Remove FOC on a deleted invoice is refused: ' || coalesce(e, 'done'));
  e := pg_temp.foc(b);
  perform pg_temp.check(e = 'Invoice has been deleted', 'F4 and Make FOC, as before: ' || coalesce(e, 'done'));
  update public.invoices set deleted_at = null, locked_at = now() where id = inv;
  e := pg_temp.unfoc(a);
  perform pg_temp.check(e = 'Invoice is locked' and (select foc_quantity from public.invoice_items where id = a) = 1,
    'F4 Remove FOC on a locked invoice is refused: ' || coalesce(e, 'done'));
end $$;

-- ═════ F5 The affiliate ═════
do $$
declare inv uuid := pg_temp.sale('A'); e text; n0 int;
begin
  n0 := pg_temp.edits(inv);
  e := pg_temp.err(format('select public.set_invoice_affiliate(%L, %L)', inv, pg_temp.fx('aff')));
  perform pg_temp.check(e is null and pg_temp.edits(inv) = n0 + 1 and (select affiliate_id from public.invoices where id = inv) = pg_temp.fx('aff'),
    'F5 choosing the affiliate raises edit_count: ' || coalesce(e, 'done'));
  e := pg_temp.err(format('select public.set_invoice_affiliate(%L, %L)', inv, pg_temp.fx('aff')));
  perform pg_temp.check(e is null and pg_temp.edits(inv) = n0 + 1, 'F5 the same affiliate again does not: ' || coalesce(e, 'done'));
  update public.invoices set deleted_at = now() where id = inv;
  e := pg_temp.err(format('select public.set_invoice_affiliate(%L, null)', inv));
  perform pg_temp.check(e = 'Invoice not found' and (select affiliate_id from public.invoices where id = inv) = pg_temp.fx('aff'),
    'F5 a deleted invoice is not found: ' || coalesce(e, 'done'));
end $$;

-- ═════ F6 Fulfil from warehouse ═════
do $$
declare inv_b uuid := pg_temp.sale('B'); inv_a uuid := pg_temp.sale('A'); e text; n0 int;
  q text := 'select public.set_invoice_fulfilment_warehouse(%L, %L)';
begin
  perform pg_temp.as_user('m');
  e := pg_temp.err(format(q, inv_b, pg_temp.fx('wh')));
  perform pg_temp.check(e = 'You do not have access to this invoice''s store' and (select fulfil_warehouse_id from public.invoices where id = inv_b) is null,
    'F6 a Manager of store A is refused on a store B invoice: ' || coalesce(e, 'done'));
  n0 := pg_temp.edits(inv_a);
  e := pg_temp.err(format(q, inv_a, pg_temp.fx('wh')));
  perform pg_temp.check(e is null and pg_temp.edits(inv_a) = n0 + 1 and (select fulfil_warehouse_id from public.invoices where id = inv_a) = pg_temp.fx('wh'),
    'F6 the Manager sets it on a store A invoice, raising edit_count: ' || coalesce(e, 'done'));
  e := pg_temp.err(format(q, inv_a, pg_temp.fx('wh')));
  perform pg_temp.check(e is null and pg_temp.edits(inv_a) = n0 + 1, 'F6 the same warehouse again does not: ' || coalesce(e, 'done'));
  e := pg_temp.err(format(q, inv_a, null));
  perform pg_temp.check(e is null and pg_temp.edits(inv_a) = n0 + 2 and (select fulfil_warehouse_id from public.invoices where id = inv_a) is null,
    'F6 clearing it does: ' || coalesce(e, 'done'));
  e := pg_temp.err(format(q, inv_a, null));
  perform pg_temp.check(e is null and pg_temp.edits(inv_a) = n0 + 2, 'F6 clearing it again does not: ' || coalesce(e, 'done'));
  perform pg_temp.as_user('o');
  e := pg_temp.err(format(q, inv_b, pg_temp.fx('wh')));
  perform pg_temp.check(e is null, 'F6 the Owner sets it on the store B invoice: ' || coalesce(e, 'done'));
  update public.invoices set deleted_at = now() where id = inv_b;
  e := pg_temp.err(format(q, inv_b, null));
  perform pg_temp.check(e = 'Invoice not found' and (select fulfil_warehouse_id from public.invoices where id = inv_b) = pg_temp.fx('wh'),
    'F6 a deleted invoice is not found: ' || coalesce(e, 'done'));
end $$;

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All FOC, affiliate and fulfilment checks passed.';
end $$;
rollback;
