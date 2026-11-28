-- 547: special, consignment and rental items on an invoice's Goods collected (the Owner's answers of
-- 27 Nov 2026), through the app's own calls.
--
--   I  547 installs, a second run changes nothing; grants; the new functions are internal; every
--      changed or new owner-rights function searches pg_temp last (546's rule).
--   O  Ordinary products: invoice_goods_status's products, totals and flags, the hand-over's answer
--      and the list badge are as before 547 (captured before installing).
--   L  Listed (answers 1, 5, 6): special, consignment and rental lines with their units, still to
--      collect before and after full payment; nothing to collect on a cancelled invoice.
--   W  Who (answer 9): staff of the invoice's store record Collected / Delivered; staff of another
--      store, a former member of staff and an Inventory Manager are refused.
--   C  Before full payment (answers 2, 4, 7): with a part payment or the button; the item waits for
--      a warehouse at once, no stock moves; Delivered only for a consignment sale; a rental whole;
--      not more than still to collect; retries; the Owner releases it while the invoice owes (an
--      item not collected still waits for the payment); full payment raises the rest, never twice.
--   A  After full payment (answers 3, 6): release, then Collected, as separate steps, in either
--      order; a paid invoice lists To collect; products are not handed over after payment.
--   B  Blocked until returned (answer 8): cancel, delete, correction (remove, lower, swap), refund
--      (whole line, a unit the customer has, closing the invoice, a rental's line); what stays
--      allowed.
--   R  Returns (answer 9's rights): Owner / Manager of the store only; not yet released, released
--      from a warehouse or a store, sent by a supplier, before and after full payment; a released
--      rental comes back by its own Return; then the blocked step goes through; retries.
--   F  Corrections and payments keep the sales in step: a lowered line takes an uncollected unit; a
--      raised line before full payment waits for the payment; the full payment after returns raises
--      what is missing.
--   K  Items released before 547 (made before installing it): a sale from a warehouse recorded
--      Collected, one a supplier sent Delivered, a rental out and one returned Collected, a waiting
--      sale left to collect; by the migration (source 'migration', no person, dated at the release,
--      its note); no stock, sale or rental changes; a re-run adds nothing; UNDO takes them away.
--   M  The waiting list's marks: what the customer has, to Owners and Managers of the store only.
--
-- Run on a copy of production after 546 (createdb -T of a template equal to it; never the template):
--   psql -X -d <copy> -v ON_ERROR_STOP=1 -f scripts/special/tests/goods-collected-547.sql
-- (with -v skip_install=1 where 547 is in: I1-I3 and O are then skipped). Every check runs, then the
-- file fails if any did. Everything is rolled back. Every name, phone and email is invented
-- (+61 2 5550 ...., @example.invalid); the repository is public.
-- Note: a check that calls a function and reads what it changed in ONE expression reads the snapshot
-- from before the call; call first, then check.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
-- 548 (the Class page): where it is in, its UNDO goes first of all, before 547's (it calls 540's
-- inventory_manager_guard, which 540's UNDO refuses while any other function uses it).
select to_regprocedure('public.class_page_data()') is not null as t548_in \gset
\if :t548_in
select set_config('energia.undo548_test_only', 'on', true) \g /dev/null
\ir ../../classes/undo-548.sql
\endif
-- 549 (the referral page's booking lookup): where it is in, its UNDO goes next, before 547's (production's
-- order was 547, 549, then 548; this file's last checks pin the function fingerprint of production after 546).
select to_regprocedure('public.referral_booking_lookup(text,text,text)') is not null as t549_in \gset
\if :t549_in
\ir ../../affiliate-signup/undo-549.sql
\endif
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise warning 'FAIL %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlerrm; end$$;
create function pg_temp.fp() returns text language sql set search_path = public as
$$ select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || '/' || count(*)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' $$;

create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true),
          set_config('request.jwt.claim.role', case when key is null then 'anon' else 'authenticated' end, true),
          set_config('request.jwt.claims', '', true) $$;

-- ═════ Fixtures (invented) ═════
do $$
declare u uuid; k text; st uuid; st2 uuid; wh uuid; v uuid; ph text;
  sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
begin
  foreach k in array array['owner', 'manager', 'staff', 'other', 'other_mgr', 'former', 'im'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'g547-' || k || '-' || sfx || '@example.invalid');
    insert into public.profiles(id, full_name, email, role, is_active)
      values (u, 'G547 ' || k, 'g547-' || k || '-' || sfx || '@example.invalid',
              (case k when 'other' then 'staff' when 'other_mgr' then 'manager' when 'former' then 'staff'
                      when 'im' then 'inventory_manager' else k end)::public.user_role, k <> 'former');
    insert into fx values (k, u);
  end loop;
  perform pg_temp.as_user('owner');
  insert into public.stores(name, code, country_code) values ('G547 Store ' || sfx, 'G547' || sfx, 'SG') returning id into st; insert into fx values ('store', st);
  insert into public.stores(name, code, country_code) values ('G547 Store B ' || sfx, 'G547B' || sfx, 'SG') returning id into st2; insert into fx values ('store2', st2);
  insert into public.warehouses(name, code) values ('G547 Warehouse ' || sfx, 'G547W' || sfx) returning id into wh; insert into fx values ('wh', wh);
  insert into public.payment_methods(name, is_active) values ('G547 Cash ' || sfx, true) returning id into v; insert into fx values ('cash', v);
  insert into public.user_store_assignments(user_id, store_id) values
    (pg_temp.fx('manager'), st), (pg_temp.fx('staff'), st), (pg_temp.fx('former'), st), (pg_temp.fx('im'), st),
    (pg_temp.fx('other'), st2), (pg_temp.fx('other_mgr'), st2);
  select '+6125550' || lpad(n::text, 4, '0') into ph from generate_series(1000, 9999) n
   where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = '+6125550' || lpad(n::text, 4, '0'))
   order by n limit 1;
  insert into public.customers(full_name, phone) values ('G547 Buyer', ph) returning id into v; insert into fx values ('buyer', v);
end $$;

-- A special product (S$1,000, S$100 a month to rent) over a third-party product holding 10 at the
-- warehouse and 10 at the store.
create function pg_temp.mkspecial(tag text) returns void language plpgsql as
$$declare p uuid; sp uuid;
begin
  perform pg_temp.as_user('owner');
  insert into public.products(name, sku, product_type) values ('G547 ' || tag, 'G547-' || tag || '-' || substr(md5(random()::text), 1, 5), 'third_party') returning id into p;
  insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (pg_temp.fx('wh'), p, 10);
  insert into public.store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('store'), p, 10);
  sp := public.upsert_special_product_from_product(null, p, 1000, 0, 0, 100, 0, 0);
  insert into fx values ('p_' || tag, p), ('sp_' || tag, sp);
end$$;
-- A consignment one: a supplier linked, ticked (494).
create function pg_temp.mkconsign(tag text) returns void language plpgsql as
$$declare sup uuid;
begin
  perform pg_temp.mkspecial(tag);
  insert into public.suppliers(name, phone) values ('G547 Supplier ' || tag, '+6125550' || lpad((9000 + (select count(*) from fx))::text, 4, '0')) returning id into sup;
  insert into public.product_suppliers(product_id, supplier_id) values (pg_temp.fx('p_' || tag), sup);
  perform public.set_special_product_consignment(pg_temp.fx('sp_' || tag), true);
  insert into fx values ('sup_' || tag, sup);
end$$;
create function pg_temp.mkplain(tag text) returns void language plpgsql as
$$declare p uuid;
begin
  insert into public.products(name, sku, product_type) values ('G547 ' || tag, 'G547-' || tag || '-' || substr(md5(random()::text), 1, 5), 'own') returning id into p;
  insert into public.store_product_prices(store_id, product_id, selling_price) values (pg_temp.fx('store'), p, 100);
  insert into public.store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('store'), p, 10);
  insert into fx values ('p_' || tag, p);
end$$;
create function pg_temp.sale_line(tag text, qty int default 1) returns jsonb language sql as
$$ select jsonb_build_object('kind', 'special_product', 'special_product_id', pg_temp.fx('sp_' || tag), 'quantity', qty) $$;
create function pg_temp.rent_line(tag text, qty int default 1) returns jsonb language sql as
$$ select jsonb_build_object('kind', 'rental', 'special_product_id', pg_temp.fx('sp_' || tag), 'quantity', qty,
     'rental_rate_type', 'month', 'rental_periods', 1, 'rental_start_date', public.sg_today()::text) $$;
create function pg_temp.prod_line(tag text, qty int default 1) returns jsonb language sql as
$$ select jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('p_' || tag), 'quantity', qty) $$;
create function pg_temp.mk(items jsonb) returns uuid language plpgsql as
$$begin perform pg_temp.as_user('owner');
  return public.create_invoice_with_details(pg_temp.fx('store'), pg_temp.fx('buyer'), items,
            jsonb_build_object('business_date', public.sg_today()::text)); end$$;
-- Full payment of what is owed (Record Payment's full path).
create function pg_temp.pay(inv uuid) returns void language plpgsql as
$$begin perform pg_temp.as_user('owner');
  perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'),
     'amount', public.invoice_charge_total(inv) - public.invoice_net_received(inv)))); end$$;
-- A part payment as the Invoices page records it, with its hand-over answer.
create function pg_temp.settle(inv uuid, amount numeric, handover jsonb, req uuid default gen_random_uuid(), who text default 'staff')
returns jsonb language plpgsql as
$$begin perform pg_temp.as_user(who);
  return public.record_invoice_settlement(inv,
     jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object('key', 'line-0',
       'payment_method_id', pg_temp.fx('cash'), 'amount', amount)), 'arrangements', '[]'::jsonb)
     || case when handover is not null then jsonb_build_object('handover', handover) else '{}'::jsonb end, req); end$$;
-- "Hand over items" (the button) as someone.
create function pg_temp.collect(inv uuid, answer jsonb, who text default 'staff', req uuid default gen_random_uuid()) returns jsonb language plpgsql as
$$begin perform pg_temp.as_user(who); return public.record_invoice_handover(inv, answer, req); end$$;
create function pg_temp.sp(line uuid, qty int default 1, how text default 'collected') returns jsonb language sql as
$$ select jsonb_build_object('specials', jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'qty', qty, 'how', how))) $$;
create function pg_temp.ret(inv uuid, items jsonb, who text default 'owner', req uuid default gen_random_uuid()) returns jsonb language plpgsql as
$$begin perform pg_temp.as_user(who); return public.record_invoice_goods_return(inv, items, 'Brought back', req); end$$;
create function pg_temp.rsp(line uuid, n int default 1) returns jsonb language sql as
$$ select jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'returned', n)) $$;
create function pg_temp.status(inv uuid, who text default 'staff') returns jsonb language plpgsql as
$$begin perform pg_temp.as_user(who); return public.invoice_goods_status(inv); end$$;
create function pg_temp.spl(inv uuid, line uuid) returns jsonb language sql as
$$ select e from jsonb_array_elements(pg_temp.status(inv)->'specials') e where e->>'invoice_item_id' = line::text $$;
create function pg_temp.line_of(inv uuid, kind text, tag text) returns uuid language sql as
$$ select id from public.invoice_items where invoice_id = inv and line_kind::text = kind
      and coalesce(special_product_id, product_id) = coalesce(pg_temp.fx('sp_' || tag), pg_temp.fx('p_' || tag)) limit 1 $$;
create function pg_temp.sales(inv uuid, st text default null) returns uuid[] language sql as
$$ select coalesce(array_agg(id order by sale_no), '{}') from public.special_sales where invoice_id = inv and (st is null or status = st) $$;
create function pg_temp.rentals(inv uuid) returns uuid[] language sql as
$$ select coalesce(array_agg(id order by rental_no), '{}') from public.rentals where invoice_id = inv $$;
create function pg_temp.waiting(inv uuid) returns int language plpgsql as
$$begin perform pg_temp.as_user('owner');
  return (select count(*) from public.special_docs_awaiting_fulfilment() w where w.invoice_no = (select invoice_no from public.invoices where id = inv)); end$$;
create function pg_temp.release(kind text, doc uuid, loc text default 'wh') returns text language plpgsql as
$$begin perform pg_temp.as_user('owner');
  return pg_temp.err(format('select public.fulfil_special_doc(%L, %L, %L, %L)', kind, doc, pg_temp.fx(loc),
                            case when loc like 'store%' then 'store' else 'warehouse' end)); end$$;
create function pg_temp.to_supplier(sale uuid, tag text) returns text language plpgsql as
$$begin perform pg_temp.as_user('owner');
  return pg_temp.err(format('select public.release_special_sale_to_supplier(%L, %L, %L)', sale, pg_temp.fx('sup_' || tag), 'Deliver to the buyer''s flat')); end$$;
create function pg_temp.at_wh(tag text) returns int language sql as
$$ select coalesce((select current_qty from public.warehouse_inventory where product_id = pg_temp.fx('p_' || tag) and warehouse_id = pg_temp.fx('wh')), 0) $$;
create function pg_temp.at_store(tag text) returns int language sql as
$$ select coalesce((select current_qty from public.store_inventory where product_id = pg_temp.fx('p_' || tag) and store_id = pg_temp.fx('store')), 0) $$;
create function pg_temp.lines(inv uuid) returns jsonb language sql as
$$ select jsonb_agg(jsonb_build_object('invoice_item_id', id, 'kind', line_kind::text, 'product_id', product_id,
     'special_product_id', special_product_id, 'quantity', quantity, 'unit_price', unit_price,
     'rental_rate_type', rental_rate_type, 'rental_periods', rental_periods, 'rental_start_date', rental_start_date) order by id)
     from public.invoice_items where invoice_id = inv $$;
-- The lines with one line's quantity changed (0 removes it), or its machine swapped.
create function pg_temp.lines_with(inv uuid, line uuid, q int, swap text default null) returns jsonb language sql as
$$ select coalesce(jsonb_agg(case when (l->>'invoice_item_id')::uuid = line
                                  then l || jsonb_build_object('quantity', q)
                                         || case when swap is null then '{}'::jsonb else jsonb_build_object('special_product_id', pg_temp.fx('sp_' || swap)) end
                                  else l end)
                     filter (where not ((l->>'invoice_item_id')::uuid = line and q = 0)), '[]'::jsonb)
     from jsonb_array_elements(pg_temp.lines(inv)) l $$;
create function pg_temp.correct(inv uuid, items jsonb, who text default 'owner') returns text language plpgsql as
$$begin perform pg_temp.as_user(who);
  return pg_temp.err(format('select public.correct_invoice(%L, %L::jsonb, %L::jsonb, %L, %L)', inv, items, '{}', 'Keyed wrongly', gen_random_uuid())); end$$;
create function pg_temp.cancel(inv uuid) returns text language plpgsql as
$$begin perform pg_temp.as_user('owner');
  return pg_temp.err(format('select public.cancel_invoice_recorded(%L, %L, %L)', inv, 'Customer changed mind', gen_random_uuid())); end$$;
create function pg_temp.current_payment(inv uuid) returns uuid language sql as
$$ select p.id from public.invoice_payments p where p.invoice_id = inv and p.entry_kind <> 'correction_reversal'
      and not exists (select 1 from public.invoice_payments v where v.corrects_payment_id = p.id and v.entry_kind = 'correction_reversal')
    order by public.invoice_payment_remaining(p.id) desc limit 1 $$;
-- A refund of one line; amount null = the line's whole value left.
create function pg_temp.refund(inv uuid, line uuid, amt numeric, stock jsonb default '[]', waiting jsonb default null) returns text language plpgsql as
$$declare pay uuid; a numeric;
begin
  perform pg_temp.as_user('owner');
  pay := pg_temp.current_payment(inv);
  a := coalesce(amt, public.invoice_discounted_line_value(line));
  return pg_temp.err(format('select public.refund_invoice_recorded(%L, %L::jsonb, %L::jsonb, %L::jsonb, %L, %L)', inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'amount', a)
                      || case when waiting is null then '{}'::jsonb else jsonb_build_object('waiting', waiting) end),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', a)), stock, 'Refund check', gen_random_uuid()));
end$$;
create function pg_temp.answer(sale uuid, s int, d int, n int) returns jsonb language sql as
$$ select jsonb_build_array(jsonb_build_object('movement_id', (select release_movement_id from public.special_sales where id = sale),
     'sellable_quantity', s, 'damaged_quantity', d, 'not_returned_quantity', n)) $$;
create function pg_temp.st(sale uuid) returns text language sql as $$ select status from public.special_sales where id = sale $$;
create function pg_temp.rst(r uuid) returns text language sql as $$ select status::text from public.rentals where id = r $$;
create function pg_temp.ok(t text) returns boolean language sql as $$ select t = 'ok' $$;
create function pg_temp.refused(t text, pat text) returns boolean language sql as $$ select t <> 'ok' and t ~* pat $$;

-- ═════ O (before) Ordinary products as 399 has them, captured before 547 ═════
select pg_temp.mkplain('pillow'), pg_temp.mkplain('socks');
create temp table o_before(k text primary key, v jsonb);
do $$
declare inv uuid; res jsonb;
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.prod_line('pillow', 3), pg_temp.prod_line('socks', 1)));
  insert into fx values ('o_inv', inv);
  res := pg_temp.settle(inv, 50, jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p_pillow'), 'qty', 2))));
  insert into o_before values ('answer', (res->'handover') - 'handover_id' - 'created_at');
  insert into o_before values ('status', pg_temp.status(inv) - 'history');
  perform pg_temp.as_user('staff');
  insert into o_before values ('badge', (select to_jsonb(array_agg(to_jsonb(g) order by g.invoice_id)) from public.invoice_list_goods_out(array[inv]) g));
end $$;

-- ═════ K (before) Items released before 547 ═════
select pg_temp.mkspecial('k_wh'), pg_temp.mkconsign('k_sup'), pg_temp.mkspecial('k_pend'), pg_temp.mkspecial('k_rent'),
       pg_temp.mkspecial('k_set'), pg_temp.mkplain('k_plain');
do $$
declare inv uuid; r uuid; m text;
begin
  -- Released, then its line refunded with the unit answered "not returned": settled by the refund.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('k_set', 1), pg_temp.prod_line('k_plain', 1))); perform pg_temp.pay(inv);
  perform pg_temp.release('special_sale', (pg_temp.sales(inv))[1]);
  m := pg_temp.refund(inv, pg_temp.line_of(inv, 'special_product', 'k_set'), null, pg_temp.answer((pg_temp.sales(inv))[1], 0, 0, 1));
  if m <> 'ok' then raise exception 'fixture k6: %', m; end if;
  insert into fx values ('k6', inv);
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('k_wh', 1))); perform pg_temp.pay(inv);
  perform pg_temp.release('special_sale', (pg_temp.sales(inv))[1]); insert into fx values ('k1', inv);
  -- Released ten days ago (a test shortcut: everything here happens in one transaction).
  update public.special_sales set fulfilled_at = fulfilled_at - interval '10 days' where invoice_id = inv;
  -- A rental returned on an invoice since cancelled: not a live invoice.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.rent_line('k_rent', 1))); perform pg_temp.pay(inv);
  r := (pg_temp.rentals(inv))[1];
  perform pg_temp.release('rental', r);
  perform pg_temp.as_user('owner');
  perform public.return_rental_with_fee(r, 'good', true);
  m := pg_temp.cancel(inv);
  if m <> 'ok' then raise exception 'fixture k7: %', m; end if;
  insert into fx values ('k7', inv);
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('k_sup', 1))); perform pg_temp.pay(inv);
  perform pg_temp.to_supplier((pg_temp.sales(inv))[1], 'k_sup'); insert into fx values ('k2', inv);
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('k_pend', 1))); perform pg_temp.pay(inv); insert into fx values ('k3', inv);
  inv := pg_temp.mk(jsonb_build_array(pg_temp.rent_line('k_rent', 1))); perform pg_temp.pay(inv);
  perform pg_temp.release('rental', (pg_temp.rentals(inv))[1], 'store'); insert into fx values ('k4', inv);
  inv := pg_temp.mk(jsonb_build_array(pg_temp.rent_line('k_rent', 1))); perform pg_temp.pay(inv);
  r := (pg_temp.rentals(inv))[1];
  perform pg_temp.release('rental', r);
  perform pg_temp.as_user('owner');
  perform public.return_rental_with_fee(r, 'good', true); insert into fx values ('k5', inv);
end $$;
create temp table k_before as
  select (select md5(string_agg(to_jsonb(s)::text, '' order by s.id)) from public.special_sales s
           where s.invoice_id in (select v from fx where k in ('k1', 'k2', 'k3', 'k4', 'k5'))) as sales,
         (select md5(string_agg(to_jsonb(r)::text, '' order by r.id)) from public.rentals r
           where r.invoice_id in (select v from fx where k in ('k1', 'k2', 'k3', 'k4', 'k5'))) as rentals,
         (select count(*) from public.stock_movements) as moves,
         (select md5(string_agg(to_jsonb(w)::text, '' order by w.warehouse_id, w.product_id)) from public.warehouse_inventory w) as wh,
         (select md5(string_agg(to_jsonb(t)::text, '' order by t.store_id, t.product_id)) from public.store_inventory t) as st;

-- ═════ I Installs ═════
create temp table before_install as select pg_temp.fp() f;
create temp table acl_before as
  select p.oid::regprocedure::text as sig, coalesce(array_to_string(p.proacl, ','), '') as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace;
\if :{?skip_install}
do $$ begin raise notice 'NOTE  I1-I3 and O are skipped: 547 is in already'; end $$;
\else
\ir ../../../supabase/547_special_consignment_rental_goods_collected.sql
create temp table after_install as select pg_temp.fp() f;
create temp table k_after1 as
  select (select count(*) from public.invoice_handovers where source = 'migration') as headers,
         (select count(*) from public.invoice_special_handover_lines) as lines;
\ir ../../../supabase/547_special_consignment_rental_goods_collected.sql
do $$
begin
  perform pg_temp.check((select f from before_install) = 'f5f09a8bf80f379ccdf38b6edaad0dbc/1462',
    'I1 it was installed on production''s functions after 546 (f5f09a8b.../1462): ' || (select f from before_install));
  perform pg_temp.check((select f from after_install) = pg_temp.fp(), 'I2 a second run changes no function');
  perform pg_temp.check(not exists (select 1 from acl_before b join pg_proc p on p.oid::regprocedure::text = b.sig
                                     where coalesce(array_to_string(p.proacl, ','), '') <> b.acl),
    'I3 every function that was there keeps its grants');
end $$;
\endif
do $$
declare f text; t text;
begin
  foreach f in array array['invoice_special_goods_out(uuid)', 'invoice_special_lines(uuid)', 'special_doc_collected(text,uuid)',
      'invoice_special_kept_check(uuid)', 'invoice_special_goods_block(uuid,text)',
      'invoice_special_refund_check(uuid,uuid,boolean,jsonb,jsonb)', 'invoice_special_collect_internal(uuid,uuid,jsonb)'] loop
    perform pg_temp.check(to_regprocedure('public.' || f) is not null
        and not has_function_privilege('anon', 'public.' || f, 'execute')
        and not has_function_privilege('authenticated', 'public.' || f, 'execute')
        and has_function_privilege('service_role', 'public.' || f, 'execute'),
      'I4 ' || f || ' is internal (service_role only)');
  end loop;
  foreach f in array array['record_invoice_handover(uuid,jsonb,uuid)', 'record_invoice_goods_return(uuid,jsonb,text,uuid)',
      'invoice_goods_status(uuid)', 'invoice_list_goods_out(uuid[])'] loop
    perform pg_temp.check(has_function_privilege('authenticated', 'public.' || f, 'execute')
        and not has_function_privilege('anon', 'public.' || f, 'execute'), 'I5 ' || f || ' is for signed-in staff only');
  end loop;
  perform pg_temp.check(not exists (
      select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.proowner = 'postgres'::regrole
         and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
         and not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%' and c like '%pg\_temp')),
    'I6 every owner-rights function of the app searches pg_temp last (546''s rule), the new and changed ones too');
  foreach t in array array['public.invoice_special_handover_lines', 'public.invoice_special_handover_returns'] loop
    perform pg_temp.check(has_table_privilege('authenticated', t, 'select')
        and not has_table_privilege('authenticated', t, 'insert') and not has_table_privilege('authenticated', t, 'update')
        and not has_table_privilege('authenticated', t, 'delete') and not has_table_privilege('authenticated', t, 'truncate')
        and not has_table_privilege('anon', t, 'select')
        and (select relrowsecurity from pg_class where oid = t::regclass),
      'I7 ' || t || ': signed-in staff read it (row rules on), nobody writes it but the functions');
  end loop;
  perform pg_temp.check(pg_get_constraintdef((select oid from pg_constraint where conname = 'special_sale_returns_why_check'))
                        like '%item returned%', 'I8 a special sale''s return may say "item returned"');
end $$;

-- ═════ K Items released before 547 (only where this file installed 547) ═════
\if :{?skip_install}
\else
do $$
declare l record; h record; n int; gs jsonb;
begin
  select * into l from public.invoice_special_handover_lines where invoice_id = pg_temp.fx('k1');
  select * into h from public.invoice_handovers where id = l.handover_id;
  perform pg_temp.check(l.how = 'collected' and l.quantity = 1 and l.special_sale_id = (pg_temp.sales(pg_temp.fx('k1')))[1]
                        and h.source = 'migration' and h.kind = 'handover' and h.created_by is null and l.created_by is null
                        and h.reason = 'Released before 547 (27 Nov 2026): recorded as collected or delivered by the migration, not by staff'
                        and h.created_at = (select fulfilled_at from public.special_sales where id = l.special_sale_id)
                        and h.created_at < now() - interval '9 days'
                        and l.created_at = h.created_at,
    'K1 a sale released from a warehouse before 547: Collected, by the migration, no person, dated at its release, with its note');
  perform pg_temp.check((select how from public.invoice_special_handover_lines where invoice_id = pg_temp.fx('k2')) = 'delivered',
    'K2 one its supplier sent: Delivered');
  perform pg_temp.check(not exists (select 1 from public.invoice_special_handover_lines where invoice_id = pg_temp.fx('k3'))
                        and (pg_temp.spl(pg_temp.fx('k3'), pg_temp.line_of(pg_temp.fx('k3'), 'special_product', 'k_pend'))->>'to_collect')::int = 1,
    'K3 a waiting sale: no record, still 1 to collect');
  perform pg_temp.check((select how || quantity::text from public.invoice_special_handover_lines where invoice_id = pg_temp.fx('k4')) = 'collected1'
                        and (pg_temp.spl(pg_temp.fx('k4'), pg_temp.line_of(pg_temp.fx('k4'), 'rental', 'k_rent'))->>'out')::int = 1,
    'K4 a rental out: Collected, whole, with the customer');
  perform pg_temp.check((select how from public.invoice_special_handover_lines where invoice_id = pg_temp.fx('k5')) = 'collected'
                        and (pg_temp.spl(pg_temp.fx('k5'), pg_temp.line_of(pg_temp.fx('k5'), 'rental', 'k_rent'))->>'out')::int = 0,
    'K5 a rental returned: Collected, and back (out with nobody)');
  perform pg_temp.check((select headers from k_after1) = 4
                        and (select count(*) from public.invoice_handovers where source = 'migration') = 4
                        and (select count(*) from public.invoice_special_handover_lines) = (select lines from k_after1),
    'K6 one record each, and the second run added nothing');
  perform pg_temp.check((select sales from k_before) = (select md5(string_agg(to_jsonb(s)::text, '' order by s.id)) from public.special_sales s
                           where s.invoice_id in (select v from fx where k in ('k1', 'k2', 'k3', 'k4', 'k5')))
                        and (select rentals from k_before) = (select md5(string_agg(to_jsonb(r)::text, '' order by r.id)) from public.rentals r
                           where r.invoice_id in (select v from fx where k in ('k1', 'k2', 'k3', 'k4', 'k5')))
                        and (select moves from k_before) = (select count(*) from public.stock_movements)
                        and (select wh from k_before) = (select md5(string_agg(to_jsonb(w)::text, '' order by w.warehouse_id, w.product_id)) from public.warehouse_inventory w)
                        and (select st from k_before) = (select md5(string_agg(to_jsonb(t)::text, '' order by t.store_id, t.product_id)) from public.store_inventory t),
    'K7 no stock, movement, sale or rental changed');
  gs := pg_temp.status(pg_temp.fx('k1'));
  perform pg_temp.check((gs->>'special_to_collect_total')::int = 0 and (gs->>'special_collected_total')::int = 1
                        and gs->'history'->0->>'source' = 'migration' and gs->'history'->0->>'created_by_name' is null
                        and gs->'history'->0->'items'->0->>'how' = 'collected',
    'K8 the paid invoice no longer lists it To collect; its history says the migration recorded it');
  perform pg_temp.check((select status from public.invoices where id = pg_temp.fx('k6')) = 'paid'
                        and pg_temp.st((pg_temp.sales(pg_temp.fx('k6')))[1]) = 'completed'
                        and not exists (select 1 from public.invoice_special_handover_lines where invoice_id = pg_temp.fx('k6'))
                        and (pg_temp.spl(pg_temp.fx('k6'), pg_temp.line_of(pg_temp.fx('k6'), 'special_product', 'k_set'))->>'to_collect')::int = 0,
    'K11 a released sale a refund already settled (not returned): no record, and nothing to collect');
  perform pg_temp.check((select status::text from public.invoices where id = pg_temp.fx('k7')) = 'cancelled'
                        and pg_temp.rst((pg_temp.rentals(pg_temp.fx('k7')))[1]) = 'returned'
                        and not exists (select 1 from public.invoice_special_handover_lines where invoice_id = pg_temp.fx('k7')),
    'K12 a returned rental on a cancelled invoice: no record');
  perform pg_temp.check(pg_temp.cancel(pg_temp.fx('k4')) ~ '^The customer has', 'K9 the rental out blocks a cancellation, as any collected item');
  perform pg_temp.check(pg_temp.cancel(pg_temp.fx('k5')) = 'ok', 'K10 the returned one does not');
end $$;
\endif

-- ═════ O Ordinary products unchanged (only where this file installed 547) ═════
\if :{?skip_install}
\else
do $$
declare inv uuid := pg_temp.fx('o_inv'); res jsonb; b jsonb;
begin
  b := pg_temp.status(inv) - 'history';
  perform pg_temp.check((b - 'specials' - 'special_collected_total' - 'special_delivered_total' - 'special_out_total'
                           - 'special_to_collect_total' - 'can_collect_special' - 'can_record_special_return')
                        = (select v from o_before where k = 'status'),
    'O1 a products-only invoice''s goods (products, totals, can hand over, can record return) are as before 547');
  perform pg_temp.check(b->'specials' = '[]'::jsonb and (b->>'special_to_collect_total')::int = 0
                        and not (b->>'can_collect_special')::boolean and not (b->>'can_record_special_return')::boolean,
    'O2 and it lists no special item, nothing to collect, no special button');
  perform pg_temp.as_user('staff');
  perform pg_temp.check((select to_jsonb(array_agg(to_jsonb(g) order by g.invoice_id)) from public.invoice_list_goods_out(array[inv]) g)
                        = (select v from o_before where k = 'badge'), 'O3 its "Goods out" badge is as before');
  -- The same answer on a fresh invoice answers as before (but for its own ids and times).
  inv := pg_temp.mk(jsonb_build_array(pg_temp.prod_line('pillow', 3), pg_temp.prod_line('socks', 1)));
  res := pg_temp.settle(inv, 50, jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p_pillow'), 'qty', 2))));
  b := (select v from o_before where k = 'answer');
  perform pg_temp.check(((res->'handover') - 'handover_id' - 'created_at' - 'invoice_id' - 'invoice_no' - 'specials')
                        = (b - 'invoice_id' - 'invoice_no') and res->'handover'->'specials' = '[]'::jsonb,
    'O4 a part payment''s hand-over of products answers as before (and no special items)');
  perform pg_temp.check(pg_temp.err(format('select pg_temp.collect(%L, %L::jsonb)', inv, '{"none": true}')) ~ 'Choose at least one item',
    'O5 Hand over items still refuses "Nothing taken"');
end $$;
\endif

-- ═════ L Listed ═════
select pg_temp.mkspecial('chair'), pg_temp.mkspecial('bed'), pg_temp.mkconsign('purifier'), pg_temp.mkspecial('lamp');
do $$
declare inv uuid; s jsonb; c jsonb; r jsonb; p jsonb; st jsonb;
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.prod_line('pillow', 1), pg_temp.sale_line('chair', 2), pg_temp.sale_line('purifier', 1),
                                      pg_temp.rent_line('lamp', 1)));
  insert into fx values ('l_inv', inv);
  st := pg_temp.status(inv);
  s := pg_temp.spl(inv, pg_temp.line_of(inv, 'special_product', 'chair'));
  c := pg_temp.spl(inv, pg_temp.line_of(inv, 'special_product', 'purifier'));
  r := pg_temp.spl(inv, pg_temp.line_of(inv, 'rental', 'lamp'));
  perform pg_temp.check(jsonb_array_length(st->'specials') = 3, 'L1 an unpaid invoice lists its special, consignment and rental lines');
  perform pg_temp.check((s->>'quantity')::int = 2 and (s->>'to_collect')::int = 2 and (s->>'collected')::int = 0 and not (s->>'can_deliver')::boolean
                        and s->>'name' = 'G547 chair', 'L2 a special line: 2 on the invoice, 2 to collect, none collected, not deliverable');
  perform pg_temp.check((c->>'to_collect')::int = 1 and (c->>'is_consignment')::boolean and (c->>'can_deliver')::boolean,
    'L3 a consignment line: 1 to collect, may be Delivered');
  perform pg_temp.check((r->>'to_collect')::int = 1 and r->>'line_kind' = 'rental' and r->>'name' = 'G547 lamp (rental)'
                        and not (r->>'can_deliver')::boolean, 'L4 a rental line: 1 to collect, named as a rental, not deliverable');
  perform pg_temp.check((st->>'special_to_collect_total')::int = 4 and (st->>'can_collect_special')::boolean
                        and (st->>'to_collect_total')::int = 1, 'L5 4 special units to collect; the products'' figure stays 1');
  perform pg_temp.check(pg_temp.waiting(inv) = 0, 'L6 nothing waits for a warehouse before anything is collected or paid');
  perform pg_temp.pay(inv);
  st := pg_temp.status(inv);
  perform pg_temp.check(st->>'status' = 'paid' and (st->>'special_to_collect_total')::int = 4 and (st->>'can_collect_special')::boolean
                        and (st->>'to_collect_total')::int = 0 and not (st->>'can_hand_over')::boolean,
    'L7 paid in full: the 4 special units are still To collect (answer 6); products have nothing to collect');
  perform pg_temp.check(pg_temp.waiting(inv) = 4 - 1 + 1, 'L8 and they wait for a warehouse: 3 sales and 1 rental');
  perform pg_temp.as_user('staff');
  perform public.request_invoice_action(inv, 'invoice_cancel', true, 'Customer asked');
  st := pg_temp.status(inv);
  perform pg_temp.check((st->>'special_to_collect_total')::int = 0 and not (st->>'can_collect_special')::boolean,
    'L8b waiting on a cancellation request: nothing to collect');
  perform pg_temp.check(pg_temp.err(format('select pg_temp.collect(%L, %L::jsonb)', inv,
                          pg_temp.sp(pg_temp.line_of(inv, 'special_product', 'chair')))) ~ 'Only 0|only on an unpaid',
    'L8c and nothing can be recorded as collected');
  update public.invoices set status = 'paid' where id = inv;  -- the request set aside (a test shortcut)
  perform pg_temp.check(pg_temp.cancel(inv) = 'ok', 'L9 nothing collected: it may be cancelled');
  st := pg_temp.status(inv);
  perform pg_temp.check((st->>'special_to_collect_total')::int = 0 and not (st->>'can_collect_special')::boolean,
    'L10 a cancelled invoice has nothing to collect');
end $$;

-- ═════ W Who ═════
do $$
declare inv uuid; line uuid; m text;
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('chair', 1)));
  line := pg_temp.line_of(inv, 'special_product', 'chair');
  insert into fx values ('w_inv', inv);
  m := pg_temp.err(format('select pg_temp.collect(%L, %L::jsonb, %L)', inv, pg_temp.sp(line), 'other'));
  perform pg_temp.check(m ~* 'No access', 'W1 staff of another store cannot record it collected: ' || m);
  m := pg_temp.err(format('select pg_temp.collect(%L, %L::jsonb, %L)', inv, pg_temp.sp(line), 'former'));
  perform pg_temp.check(m <> 'ok', 'W2 a former member of staff cannot: ' || m);
  m := pg_temp.err(format('select pg_temp.collect(%L, %L::jsonb, %L)', inv, pg_temp.sp(line), 'im'));
  perform pg_temp.check(m <> 'ok', 'W3 an Inventory Manager cannot: ' || m);
  m := pg_temp.err(format('select pg_temp.collect(%L, %L::jsonb, %L)', inv, pg_temp.sp(line), null));
  perform pg_temp.check(m <> 'ok', 'W4 nobody signed in cannot: ' || m);
  perform pg_temp.check(pg_temp.sales(inv) = '{}' and not exists (select 1 from public.invoice_special_handover_lines where invoice_id = inv),
    'W5 and none of them left anything');
  m := pg_temp.err(format('select pg_temp.collect(%L, %L::jsonb, %L)', inv, pg_temp.sp(line), 'staff'));
  perform pg_temp.check(m = 'ok', 'W6 staff of the invoice''s store can: ' || m);
  perform pg_temp.as_user('other');
  perform pg_temp.check(pg_temp.err(format('select public.invoice_goods_status(%L)', inv)) ~* 'No access',
    'W7 staff of another store cannot read its goods');
  perform pg_temp.as_user('other');
end $$;
-- The row rule, as a signed-in staff member of the store (not as postgres).
select pg_temp.fx('w_inv') as w_inv \gset
select pg_temp.as_user('staff') \g /dev/null
set local role authenticated;
select count(*) as w9 from public.invoice_special_handover_lines where invoice_id = :'w_inv' \gset
reset role;
select pg_temp.as_user('other') \g /dev/null
set local role authenticated;
select count(*) as w10 from public.invoice_special_handover_lines where invoice_id = :'w_inv' \gset
reset role;
select pg_temp.as_user('im') \g /dev/null
set local role authenticated;
select count(*) as w11 from public.invoice_special_handover_lines where invoice_id = :'w_inv' \gset
reset role;
select pg_temp.check(:w9 = 1, 'W9 staff of the store read its record'),
       pg_temp.check(:w10 = 0, 'W10 staff of another store read none'),
       pg_temp.check(:w11 = 0, 'W11 nor does an Inventory Manager') \g /dev/null

-- ═════ C Before full payment ═════
do $$
declare inv uuid; chair uuid; pur uuid; lamp uuid; res jsonb; req uuid := gen_random_uuid(); ans jsonb; m text;
  n_lines int; st jsonb; s jsonb; v_pillow int; v_wh int; v_store int; sale uuid; r uuid;
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.prod_line('pillow', 2), pg_temp.sale_line('chair', 2),
                                      pg_temp.sale_line('purifier', 1), pg_temp.rent_line('lamp', 1)));
  insert into fx values ('c_inv', inv);
  chair := pg_temp.line_of(inv, 'special_product', 'chair'); pur := pg_temp.line_of(inv, 'special_product', 'purifier');
  lamp := pg_temp.line_of(inv, 'rental', 'lamp');
  v_pillow := pg_temp.at_store('pillow'); v_wh := pg_temp.at_wh('chair'); v_store := pg_temp.at_store('chair');
  ans := jsonb_build_object('items', jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p_pillow'), 'qty', 1)),
           'specials', jsonb_build_array(jsonb_build_object('invoice_item_id', chair, 'qty', 1, 'how', 'collected'),
                                         jsonb_build_object('invoice_item_id', pur, 'qty', 1, 'how', 'delivered'),
                                         jsonb_build_object('invoice_item_id', lamp, 'qty', 1)));
  res := pg_temp.settle(inv, 500, ans, req);
  perform pg_temp.check(jsonb_array_length(res->'handover'->'specials') = 3 and jsonb_array_length(res->'handover'->'items') = 1,
    'C1 a part payment saves the products and the special, consignment and rental items taken (answer 1)');
  perform pg_temp.check(pg_temp.at_store('pillow') = v_pillow - 1, 'C2 the product left the store, as 399');
  perform pg_temp.check(pg_temp.at_wh('chair') = v_wh and pg_temp.at_store('chair') = v_store
                        and pg_temp.at_wh('purifier') = 10 and pg_temp.at_wh('lamp') = 10 and pg_temp.at_store('lamp') = 10,
    'C3 no special stock moved: no warehouse or store was chosen (answer 7)');
  perform pg_temp.check(cardinality(pg_temp.sales(inv, 'pending')) = 2 and cardinality(pg_temp.rentals(inv)) = 1
                        and pg_temp.rst((pg_temp.rentals(inv))[1]) = 'awaiting_fulfilment',
    'C4 one sale for the chair, one for the purifier and the rental were raised now, waiting');
  perform pg_temp.check(pg_temp.waiting(inv) = 3, 'C5 all three wait for a warehouse (answer 7)');
  perform pg_temp.check((select count(*) from public.special_sales where invoice_id = inv and notes like '%collected before full payment%') = 1
                        and (select count(*) from public.special_sales where invoice_id = inv and notes like '%delivered before full payment%') = 1,
    'C6 each sale says it was collected or delivered before full payment');
  s := pg_temp.spl(inv, chair);
  perform pg_temp.check((s->>'collected')::int = 1 and (s->>'to_collect')::int = 1 and (s->>'out')::int = 1, 'C7 the chair: 1 collected, 1 to collect');
  s := pg_temp.spl(inv, pur);
  perform pg_temp.check((s->>'delivered')::int = 1 and (s->>'collected')::int = 0 and (s->>'to_collect')::int = 0, 'C8 the purifier: 1 delivered (answer 4)');
  s := pg_temp.spl(inv, lamp);
  perform pg_temp.check((s->>'collected')::int = 1 and (s->>'to_collect')::int = 0, 'C9 the rental: collected (answer 5)');
  st := pg_temp.status(inv);
  perform pg_temp.check((select count(*) from jsonb_array_elements(st->'history'->-1->'items') e where (e->>'special')::boolean) = 3
                        and st->'history'->-1->>'source' = 'payment', 'C10 the history lists them, with the payment');
  perform pg_temp.check(exists (select 1 from public.audit_logs a where a.record_id = inv and a.action = 'invoice_goods_handed_over'
                                   and jsonb_array_length(a.new_data->'specials') = 3), 'C11 the audit row names them');
  perform pg_temp.as_user('staff');
  perform pg_temp.check((select quantity from public.invoice_list_goods_out(array[inv])) = 1 + 3,
    'C11b the list''s "Goods out" counts the product and the 3 special items with the customer');
  perform pg_temp.check((select count(*) from public.invoice_special_handover_lines h join public.invoice_handovers v on v.id = h.handover_id
                          where h.invoice_id = inv and v.kind = 'handover' and v.source = 'payment'
                            and v.settlement_request_id = req and h.created_by = pg_temp.fx('staff')) = 3,
    'C11c recorded under the payment''s hand-over, by the staff member');
  -- A retry, and a different answer under the same request.
  n_lines := (select count(*) from public.invoice_special_handover_lines where invoice_id = inv);
  perform pg_temp.as_user('staff');
  res := public.invoice_handover_internal(inv, ans, md5(req::text || ':handover')::uuid, 'payment', req);
  perform pg_temp.check((res->>'replayed')::boolean and (select count(*) from public.invoice_special_handover_lines where invoice_id = inv) = n_lines
                        and cardinality(pg_temp.sales(inv)) = 2, 'C12 a retry writes nothing again');
  m := pg_temp.err(format('select public.invoice_handover_internal(%L, %L::jsonb, %L, %L, %L)', inv,
         jsonb_set(ans, '{specials}', jsonb_build_array(jsonb_build_object('invoice_item_id', chair, 'qty', 1))),
         md5(req::text || ':handover')::uuid, 'payment', req));
  perform pg_temp.check(m ~ 'already used', 'C13 the same products with other special items under the same request is refused');
  -- Refusals.
  m := pg_temp.err(format('select pg_temp.collect(%L, %L::jsonb)', inv, pg_temp.sp(chair, 1, 'delivered')));
  perform pg_temp.check(m ~ 'only a consignment product', 'C14 Delivered is refused for a special product that is not consignment: ' || m);
  m := pg_temp.err(format('select pg_temp.collect(%L, %L::jsonb)', inv, pg_temp.sp(chair, 2)));
  perform pg_temp.check(m ~ 'Only 1 of "G547 chair" is still to collect', 'C15 not more than still to collect: ' || m);
  m := pg_temp.err(format('select pg_temp.collect(%L, %L::jsonb)', inv, pg_temp.sp(pur, 1, 'delivered')));
  perform pg_temp.check(m ~ 'Only 0', 'C16 not twice: ' || m);
  m := pg_temp.err(format('select pg_temp.settle(%L, 10, %L::jsonb)', inv, '{"none": true, "specials": [{"invoice_item_id": "' || chair || '", "qty": 1}]}'));
  perform pg_temp.check(m ~ 'not both', 'C17 "Nothing taken" and items together are refused');
  m := pg_temp.err(format('select pg_temp.collect(%L, %L::jsonb)', inv, pg_temp.sp(pg_temp.line_of(inv, 'product', 'pillow'))));
  perform pg_temp.check(m ~ 'not on', 'C18 a product line is not a special line: ' || m);
  m := pg_temp.err(format('select pg_temp.collect(%L, %L::jsonb)', inv, '{"specials": [{"invoice_item_id": "' || chair || '", "qty": 1, "how": "posted"}]}'));
  perform pg_temp.check(m ~ 'Collected or Delivered', 'C19 an unknown "how" is refused');
  perform pg_temp.check(cardinality(pg_temp.sales(inv)) = 2 and (select count(*) from public.invoice_special_handover_lines where invoice_id = inv) = n_lines,
    'C20 the refusals left nothing');
  -- The Owner releases what the customer has while the invoice still owes (answer 7).
  sale := (select id from public.special_sales where invoice_id = inv and invoice_item_id = chair);
  m := pg_temp.release('special_sale', sale);
  perform pg_temp.check(m = 'ok' and pg_temp.at_wh('chair') = v_wh - 1 and pg_temp.st(sale) = 'completed',
    'C21 the collected chair is released from the warehouse though the invoice owes: ' || m);
  m := pg_temp.to_supplier((select id from public.special_sales where invoice_id = inv and invoice_item_id = pur), 'purifier');
  perform pg_temp.check(m = 'ok' and pg_temp.at_wh('purifier') = 10, 'C22 the delivered purifier is released to its supplier, no stock: ' || m);
  r := (pg_temp.rentals(inv))[1];
  m := pg_temp.release('rental', r, 'store');
  perform pg_temp.check(m = 'ok' and pg_temp.at_store('lamp') = 9 and pg_temp.rst(r) = 'active', 'C23 the collected rental is released from the store: ' || m);
  -- Full payment: no second sale or rental, the chair's other unit raised.
  perform pg_temp.pay(inv);
  perform pg_temp.check((select count(*) from public.special_sales where invoice_item_id = chair and status <> 'cancelled') = 2
                        and (select count(*) from public.special_sales where invoice_item_id = pur) = 1
                        and (select count(*) from public.rentals where invoice_item_id = lamp) = 1,
    'C24 full payment raises the chair''s second unit only: no duplicate sale or rental');
  perform pg_temp.check((select paid_at from public.rentals where id = r) is not null, 'C25 the rental raised early is paid now');
  perform pg_temp.check(pg_temp.waiting(inv) = 1, 'C26 only the chair''s second unit waits');
  s := pg_temp.spl(inv, chair);
  perform pg_temp.check((s->>'collected')::int = 1 and (s->>'to_collect')::int = 1, 'C27 paid: the chair still shows 1 to collect');
  perform pg_temp.check(pg_temp.at_store('pillow') = v_pillow - 2, 'C28 the product''s rest left with the payment, once');
end $$;

-- A rental is collected whole; a waiting item not collected still waits for the payment.
do $$
declare inv uuid; lamp uuid; m text;
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.rent_line('lamp', 2)));
  insert into fx values ('c2_inv', inv);
  lamp := pg_temp.line_of(inv, 'rental', 'lamp');
  m := pg_temp.err(format('select pg_temp.collect(%L, %L::jsonb)', inv, pg_temp.sp(lamp, 1)));
  perform pg_temp.check(m ~ 'collected whole', 'C29 a rental of 2 is collected whole, not 1: ' || m);
  m := pg_temp.err(format('select pg_temp.collect(%L, %L::jsonb)', inv, pg_temp.sp(lamp, 2)));
  perform pg_temp.check(m = 'ok' and (select quantity from public.rentals where invoice_id = inv) = 2, 'C30 all 2 together: one rental of 2: ' || m);
  m := pg_temp.err(format('select pg_temp.collect(%L, %L::jsonb)', inv, pg_temp.sp(lamp, 1, 'delivered')));
  perform pg_temp.check(m ~ 'only a consignment product', 'C31 a rental cannot be Delivered');
end $$;

-- ═════ A After full payment ═════
do $$
declare inv uuid; bed uuid; sale uuid; m text; s jsonb; res jsonb; v_wh int;
begin
  -- Release first, then Collected.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('bed', 1), pg_temp.prod_line('socks', 1)));
  bed := pg_temp.line_of(inv, 'special_product', 'bed');
  perform pg_temp.pay(inv);
  sale := (pg_temp.sales(inv))[1];
  v_wh := pg_temp.at_wh('bed');
  perform pg_temp.check(pg_temp.release('special_sale', sale) = 'ok' and pg_temp.at_wh('bed') = v_wh - 1, 'A1 paid: the Owner releases it from the warehouse');
  s := pg_temp.spl(inv, bed);
  perform pg_temp.check((s->>'to_collect')::int = 1 and (s->>'collected')::int = 0,
    'A2 released is not collected: still 1 to collect (answer 3)');
  m := pg_temp.err(format('select pg_temp.collect(%L, %L::jsonb)', inv, jsonb_build_object('items',
         jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p_socks'), 'qty', 1)))));
  perform pg_temp.check(m ~ 'only on an unpaid or part-paid', 'A3 a paid invoice''s products are not handed over (as 399)');
  res := pg_temp.collect(inv, pg_temp.sp(bed));
  s := pg_temp.spl(inv, bed);
  perform pg_temp.check((s->>'collected')::int = 1 and (s->>'to_collect')::int = 0
                        and (select special_sale_id from public.invoice_special_handover_lines where invoice_id = inv) = sale,
    'A4 then Collected, days later or not: the released unit is the one collected');
  perform pg_temp.check(pg_temp.at_wh('bed') = v_wh - 1 and cardinality(pg_temp.sales(inv)) = 1, 'A5 no stock moved again, no other sale');
  perform pg_temp.check(res->'specials'->0->>'how' = 'collected' and (res->'specials'->0->>'quantity')::int = 1, 'A6 the answer names it');
  -- Collected first, then the release.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('bed', 1)));
  bed := pg_temp.line_of(inv, 'special_product', 'bed');
  perform pg_temp.pay(inv);
  sale := (pg_temp.sales(inv))[1];
  perform pg_temp.collect(inv, pg_temp.sp(bed));
  perform pg_temp.check(pg_temp.st(sale) = 'pending' and pg_temp.waiting(inv) = 1, 'A7 collected first: the sale still waits for a warehouse');
  perform pg_temp.check(pg_temp.release('special_sale', sale) = 'ok' and pg_temp.st(sale) = 'completed', 'A8 then the Owner releases it');
  -- Of two, one released: the released one is the one collected.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('bed', 2)));
  bed := pg_temp.line_of(inv, 'special_product', 'bed');
  perform pg_temp.pay(inv);
  sale := (pg_temp.sales(inv))[2];
  perform pg_temp.release('special_sale', sale);
  perform pg_temp.collect(inv, pg_temp.sp(bed, 1));
  perform pg_temp.check((select special_sale_id from public.invoice_special_handover_lines where invoice_item_id = bed) = sale,
    'A12 of two, one released: the released one is recorded as collected');
  -- A consignment: to the supplier, then Delivered.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('purifier', 1)));
  perform pg_temp.pay(inv);
  sale := (pg_temp.sales(inv))[1];
  perform pg_temp.check(pg_temp.to_supplier(sale, 'purifier') = 'ok', 'A9 a paid consignment sale goes to its supplier');
  perform pg_temp.collect(inv, pg_temp.sp(pg_temp.line_of(inv, 'special_product', 'purifier'), 1, 'delivered'));
  s := pg_temp.spl(inv, pg_temp.line_of(inv, 'special_product', 'purifier'));
  perform pg_temp.check((s->>'delivered')::int = 1 and (s->>'to_collect')::int = 0, 'A10 then Delivered');
  -- A settlement that pays in full, with the items in its answer, records them.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('bed', 1)));
  res := pg_temp.settle(inv, 1000, pg_temp.sp(pg_temp.line_of(inv, 'special_product', 'bed')));
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'paid'
                        and jsonb_array_length(res->'handover'->'specials') = 1
                        and (pg_temp.spl(inv, pg_temp.line_of(inv, 'special_product', 'bed'))->>'collected')::int = 1
                        and cardinality(pg_temp.sales(inv)) = 1,
    'A11 a payment in full with the item in its answer: paid, the item collected, one sale');
end $$;

-- ═════ B Blocked until returned (the paid invoice of C: the chair collected and released, the
-- purifier delivered by its supplier, the rental collected and out; the chair's 2nd unit waiting) ═════
do $$
declare inv uuid := pg_temp.fx('c_inv'); chair uuid; pur uuid; lamp uuid; m text; collected_sale uuid; other_sale uuid;
begin
  chair := pg_temp.line_of(inv, 'special_product', 'chair'); pur := pg_temp.line_of(inv, 'special_product', 'purifier');
  lamp := pg_temp.line_of(inv, 'rental', 'lamp');
  collected_sale := (select special_sale_id from public.invoice_special_handover_lines where invoice_item_id = chair);
  other_sale := (select id from public.special_sales where invoice_item_id = chair and id <> collected_sale);
  m := pg_temp.cancel(inv);
  perform pg_temp.check(m ~ '^The customer has' and m ~ 'G547 chair' and m ~ 'G547 purifier' and m ~ 'lamp \(rental\)',
    'B1 cancelling is refused while the customer has the items, naming them: ' || m);
  perform pg_temp.check((select status::text from public.invoices where id = inv) = 'paid', 'B2 and nothing changed');
  m := pg_temp.correct(inv, pg_temp.lines_with(inv, pur, 0));
  perform pg_temp.check(m ~ '^GOODS_HANDED_OVER' and m ~ 'purifier', 'B3 a correction removing the delivered line is refused: ' || m);
  m := pg_temp.correct(inv, pg_temp.lines_with(inv, chair, 0));
  perform pg_temp.check(m ~ '^GOODS_HANDED_OVER' and m ~ 'chair', 'B4 removing the collected chair''s line is refused');
  m := pg_temp.correct(inv, pg_temp.lines_with(inv, chair, 2, 'bed'));
  perform pg_temp.check(m ~ '^GOODS_HANDED_OVER', 'B5 putting another machine on the chair''s line is refused');
  m := pg_temp.correct(inv, pg_temp.lines_with(inv, lamp, 0));
  perform pg_temp.check(m ~ '^GOODS_HANDED_OVER' and m ~ 'lamp' or m ~ 'is out with the customer: Return it first',
    'B6 removing the rental''s line is refused (458 refuses it first, the rental being out): ' || m);
  perform pg_temp.check(pg_temp.st(collected_sale) = 'completed' and pg_temp.st(other_sale) = 'pending', 'B7 and nothing changed');
  -- Lowering the chair to the 1 the customer has is allowed, and takes the unit not collected (F1).
  m := pg_temp.correct(inv, pg_temp.lines_with(inv, chair, 1));
  perform pg_temp.check(m = 'ok', 'B8 lowering the chair to the 1 the customer has is allowed: ' || m);
  perform pg_temp.check(pg_temp.st(collected_sale) = 'completed' and pg_temp.st(other_sale) = 'cancelled',
    'F1 and it takes the waiting unit nobody collected, not the one the customer has');
  -- Refunds.
  m := pg_temp.refund(inv, chair, null);
  perform pg_temp.check(m ~ '^The customer has' and m ~ 'chair', 'B9 refunding the chair''s whole line is refused: ' || m);
  m := pg_temp.refund(inv, chair, 10, pg_temp.answer(collected_sale, 0, 0, 1));
  perform pg_temp.check(m ~ '^The customer has', 'B10 a part refund answering for the chair the customer has is refused');
  m := pg_temp.refund(inv, lamp, 10);
  perform pg_temp.check(m ~ '^The customer has' and m ~ 'rental', 'B11 any refund on the rental''s line is refused while it is out');
  m := pg_temp.refund(inv, pur, null);
  perform pg_temp.check(m ~ '^The customer has' and m ~ 'purifier', 'B12 refunding the delivered purifier''s line is refused');
  perform pg_temp.check(not exists (select 1 from public.invoice_refunds where invoice_id = inv), 'B13 and no refund was recorded');
end $$;
do $$
declare inv uuid; m text; line uuid;
begin
  -- Unpaid, collected: delete and cancel are refused.
  inv := pg_temp.fx('c2_inv');
  perform pg_temp.as_user('staff');
  m := pg_temp.err(format('select public.delete_invoice(%L, %L)', inv, 'Made by mistake'));
  perform pg_temp.check(m ~ '^The customer has' and m ~ 'delete the invoice', 'B14 an unpaid invoice with a collected rental is not deleted: ' || m);
  m := pg_temp.cancel(inv);
  perform pg_temp.check(m ~ '^The customer has', 'B15 nor cancelled');
  -- Lowered below the units the customer has.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('chair', 2)));
  line := pg_temp.line_of(inv, 'special_product', 'chair');
  perform pg_temp.collect(inv, pg_temp.sp(line, 2));
  m := pg_temp.correct(inv, pg_temp.lines_with(inv, line, 1));
  perform pg_temp.check(m ~ '^GOODS_HANDED_OVER' and m ~ '2 collected, the corrected invoice keeps 1', 'B18 lowering 2 collected to 1 is refused: ' || m);
  -- A part refund on a line whose other unit the customer does not have still goes through.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('chair', 2)));
  line := pg_temp.line_of(inv, 'special_product', 'chair');
  perform pg_temp.pay(inv);
  perform pg_temp.collect(inv, pg_temp.sp(line, 1));
  m := pg_temp.refund(inv, line, 1000, '[]', jsonb_build_array(jsonb_build_object('doc_id',
         (select id from public.special_sales s where s.invoice_item_id = line
             and not exists (select 1 from public.invoice_special_handover_lines h where h.special_sale_id = s.id)), 'still_taking', false)));
  perform pg_temp.check(m = 'ok', 'B16 a part refund of the unit not collected (customer not taking it) goes through: ' || m);
  m := pg_temp.refund(inv, line, 10, '[]', jsonb_build_array(jsonb_build_object('doc_id',
         (select special_sale_id from public.invoice_special_handover_lines h where h.invoice_item_id = line), 'still_taking', false)));
  perform pg_temp.check(m ~ '^The customer has', 'B17 saying the customer is not taking the unit they have is refused');
  -- A refund of another line that closes the invoice (the special line corrected to S$0).
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('chair', 1), pg_temp.prod_line('socks', 1)));
  line := pg_temp.line_of(inv, 'special_product', 'chair');
  perform pg_temp.pay(inv);
  perform pg_temp.collect(inv, pg_temp.sp(line));
  m := pg_temp.correct(inv, (select jsonb_agg(case when (l->>'invoice_item_id')::uuid = line then l || '{"unit_price": 0}'::jsonb else l end)
                               from jsonb_array_elements(pg_temp.lines(inv)) l));
  perform pg_temp.check(m = 'ok', 'B19a the chair''s line corrected to S$0: ' || m);
  m := pg_temp.refund(inv, pg_temp.line_of(inv, 'product', 'socks'), null,
         jsonb_build_array(jsonb_build_object('movement_id', (select id from public.stock_movements where invoice_id = inv
                                                                and product_id = pg_temp.fx('p_socks') and movement_type::text = 'store_sale'),
                                              'sellable_quantity', 0, 'damaged_quantity', 0, 'not_returned_quantity', 1)));
  perform pg_temp.check(m ~ '^The customer has' and m ~ 'refund it', 'B19 a refund of another line that would close the invoice is refused while the customer has the chair: ' || m);
end $$;

-- ═════ R Returns ═════
do $$
declare inv uuid := pg_temp.fx('c_inv'); chair uuid; pur uuid; lamp uuid; m text; sale uuid; res jsonb; req uuid := gen_random_uuid();
  v_wh int; fresh uuid; r uuid;
begin
  chair := pg_temp.line_of(inv, 'special_product', 'chair'); pur := pg_temp.line_of(inv, 'special_product', 'purifier');
  lamp := pg_temp.line_of(inv, 'rental', 'lamp');
  m := pg_temp.err(format('select pg_temp.ret(%L, %L::jsonb, %L)', inv, pg_temp.rsp(chair), 'staff'));
  perform pg_temp.check(m ~ 'Only an Owner or Manager', 'R1 staff cannot record items returned (399''s rights)');
  m := pg_temp.err(format('select pg_temp.ret(%L, %L::jsonb, %L)', inv, pg_temp.rsp(chair), 'other_mgr'));
  perform pg_temp.check(m ~ 'No access', 'R2 nor a Manager of another store');
  m := pg_temp.err(format('select pg_temp.ret(%L, %L::jsonb)', inv, pg_temp.rsp(chair, 2)));
  perform pg_temp.check(m ~ 'Only 1 of "G547 chair" is out', 'R3 not more than is out: ' || m);
  -- Paid, released from the warehouse: back on that shelf; the line waits for a warehouse again.
  sale := (select special_sale_id from public.invoice_special_handover_lines where invoice_item_id = chair);
  v_wh := pg_temp.at_wh('chair');
  res := pg_temp.ret(inv, pg_temp.rsp(chair), 'manager', req);
  perform pg_temp.check(pg_temp.at_wh('chair') = v_wh + 1 and pg_temp.st(sale) = 'cancelled'
                        and (select stock_returned from public.special_sales where id = sale),
    'R4 the Manager records the chair returned: it goes back to the warehouse it left, its sale ends');
  fresh := (select raised_sale_id from public.invoice_special_handover_returns where ended_sale_id = sale);
  perform pg_temp.check(pg_temp.st(fresh) = 'pending' and (pg_temp.spl(inv, chair)->>'to_collect')::int = 1
                        and (pg_temp.spl(inv, chair)->>'out')::int = 0,
    'R5 the paid line still holds it: a sale waits in its place, 1 to collect, none out (answer 6)');
  perform pg_temp.check(exists (select 1 from public.special_sale_returns where special_sale_id = sale and why = 'item returned'),
    'R6 the stock''s return is recorded as 496 records it, "item returned"');
  res := pg_temp.ret(inv, pg_temp.rsp(chair), 'manager', req);
  perform pg_temp.check((res->>'replayed')::boolean and pg_temp.at_wh('chair') = v_wh + 1, 'R7 a retry writes nothing again');
  m := pg_temp.err(format('select pg_temp.ret(%L, %L::jsonb, %L, %L)', inv, pg_temp.rsp(pur), 'owner', req));
  perform pg_temp.check(m ~ 'already used', 'R8 another answer under the same request is refused');
  -- The supplier's: back to the supplier, no stock.
  sale := (select special_sale_id from public.invoice_special_handover_lines where invoice_item_id = pur);
  perform pg_temp.ret(inv, pg_temp.rsp(pur));
  perform pg_temp.check(pg_temp.st(sale) = 'cancelled' and pg_temp.at_wh('purifier') = 10 and pg_temp.at_store('purifier') = 10
                        and (select notes from public.special_sales where id = sale) ~ 'Returned to G547 Supplier purifier, no stock moves',
    'R9 the purifier goes back to its supplier: no stock moves');
  -- A rental out from the store comes back by its own Return.
  r := (select rental_id from public.invoice_special_handover_lines where invoice_item_id = lamp);
  m := pg_temp.err(format('select pg_temp.ret(%L, %L::jsonb)', inv, pg_temp.rsp(lamp)));
  perform pg_temp.check(m ~ 'its own Return on Special & Rentals', 'R10 a released rental is not returned here: ' || m);
  m := pg_temp.cancel(inv);
  perform pg_temp.check(m ~ '^The customer has' and m ~ 'lamp' and m !~ 'chair', 'R11 cancelling is still refused, for the rental alone: ' || m);
  perform pg_temp.as_user('owner');
  perform public.return_rental_with_fee(r, 'good', true);
  perform pg_temp.check((pg_temp.spl(inv, lamp)->>'out')::int = 0 and (pg_temp.spl(inv, lamp)->>'collected')::int = 1,
    'R12 after its Return the rental is out no more (and still shows as collected)');
  m := pg_temp.cancel(inv);
  perform pg_temp.check(m = 'ok', 'R13 now the invoice is cancelled: ' || m);
  perform pg_temp.check(pg_temp.st(fresh) = 'cancelled', 'R14 and the sale waiting in the chair''s place is cancelled with it (393)');
end $$;
do $$
declare inv uuid; line uuid; sale uuid; m text; v_wh int; r uuid;
begin
  -- Before full payment, not released: off the waiting list; the full payment raises it again.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('chair', 1)));
  line := pg_temp.line_of(inv, 'special_product', 'chair');
  perform pg_temp.settle(inv, 100, pg_temp.sp(line));
  sale := (pg_temp.sales(inv))[1];
  perform pg_temp.ret(inv, pg_temp.rsp(line));
  perform pg_temp.check(pg_temp.st(sale) = 'cancelled' and pg_temp.waiting(inv) = 0 and (pg_temp.spl(inv, line)->>'to_collect')::int = 1,
    'R15 unpaid, not released: off the waiting list, 1 to collect again');
  perform pg_temp.pay(inv);
  perform pg_temp.check((select count(*) from public.special_sales where invoice_item_id = line and status = 'pending') = 1,
    'R16 and the full payment raises it again, once');
  -- Before full payment, released from the warehouse: back there; then the line may go.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('bed', 1), pg_temp.prod_line('socks', 1)));
  line := pg_temp.line_of(inv, 'special_product', 'bed');
  perform pg_temp.settle(inv, 100, pg_temp.sp(line));
  sale := (pg_temp.sales(inv))[1];
  v_wh := pg_temp.at_wh('bed');
  perform pg_temp.check(pg_temp.release('special_sale', sale) = 'ok' and pg_temp.at_wh('bed') = v_wh - 1, 'R17 part paid: released while owing');
  m := pg_temp.correct(inv, pg_temp.lines_with(inv, line, 0));
  perform pg_temp.check(m ~ '^GOODS_HANDED_OVER', 'R18 removing its line is refused');
  perform pg_temp.ret(inv, pg_temp.rsp(line), 'manager');
  perform pg_temp.check(pg_temp.at_wh('bed') = v_wh and pg_temp.st(sale) = 'cancelled'
                        and not exists (select 1 from public.special_sales where invoice_id = inv and status <> 'cancelled'),
    'R19 returned: back in the warehouse, the sale ended, nothing raised in its place before full payment');
  m := pg_temp.correct(inv, pg_temp.lines_with(inv, line, 0));
  perform pg_temp.check(m = 'ok' and pg_temp.at_wh('bed') = v_wh, 'R20 now the correction takes the line off; no stock moves again: ' || m);
  -- Before full payment, a rental not released comes back whole.
  inv := pg_temp.fx('c2_inv');
  line := pg_temp.line_of(inv, 'rental', 'lamp');
  r := (pg_temp.rentals(inv))[1];
  m := pg_temp.err(format('select pg_temp.ret(%L, %L::jsonb)', inv, pg_temp.rsp(line, 1)));
  perform pg_temp.check(m ~ 'comes back whole', 'R21 a rental of 2 comes back whole: ' || m);
  perform pg_temp.ret(inv, pg_temp.rsp(line, 2));
  perform pg_temp.check(pg_temp.rst(r) = 'cancelled' and pg_temp.waiting(inv) = 0, 'R22 returned whole: off the waiting list');
  perform pg_temp.as_user('staff');
  m := pg_temp.err(format('select public.delete_invoice(%L, %L)', inv, 'Made by mistake'));
  perform pg_temp.check(m = 'ok', 'R23 now the unpaid invoice may be deleted: ' || m);
  -- Before full payment, the rental returned, then paid: raised again.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.rent_line('lamp', 1)));
  line := pg_temp.line_of(inv, 'rental', 'lamp');
  perform pg_temp.collect(inv, pg_temp.sp(line));
  perform pg_temp.ret(inv, pg_temp.rsp(line));
  perform pg_temp.pay(inv);
  perform pg_temp.check((select count(*) from public.rentals where invoice_item_id = line and status::text = 'awaiting_fulfilment') = 1
                        and (select count(*) from public.rentals where invoice_item_id = line) = 2,
    'R24 a rental returned before payment is raised again by the full payment, once');
  -- Paid, not released: it just waits again.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('bed', 1)));
  line := pg_temp.line_of(inv, 'special_product', 'bed');
  perform pg_temp.pay(inv);
  perform pg_temp.collect(inv, pg_temp.sp(line));
  sale := (pg_temp.sales(inv))[1];
  perform pg_temp.ret(inv, pg_temp.rsp(line));
  perform pg_temp.check(pg_temp.st(sale) = 'pending' and cardinality(pg_temp.sales(inv)) = 1 and (pg_temp.spl(inv, line)->>'to_collect')::int = 1,
    'R25 paid, not released: the same sale waits again, 1 to collect');
  -- Products keep 399's rule: on a paid invoice they come back through Refund / Cancel.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.prod_line('socks', 1)));
  perform pg_temp.pay(inv);
  m := pg_temp.err(format('select pg_temp.ret(%L, %L::jsonb)', inv,
         jsonb_build_array(jsonb_build_object('product_id', pg_temp.fx('p_socks'), 'good', 1))));
  perform pg_temp.check(m ~ 'use Refund / Cancel', 'R26 a paid invoice''s products are still not returned here (399)');
end $$;

-- ═════ F Kept in step ═════
do $$
declare inv uuid; line uuid; m text; s uuid;
begin
  -- Before full payment, a raised line waits for the payment.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('chair', 1)));
  line := pg_temp.line_of(inv, 'special_product', 'chair');
  perform pg_temp.settle(inv, 100, pg_temp.sp(line));
  m := pg_temp.correct(inv, pg_temp.lines_with(inv, line, 3));
  perform pg_temp.check(m = 'ok' and cardinality(pg_temp.sales(inv)) = 1 and (pg_temp.spl(inv, line)->>'to_collect')::int = 2,
    'F2 part paid, the line raised to 3: no sale raised yet, 2 to collect: ' || m);
  perform pg_temp.pay(inv);
  perform pg_temp.check((select count(*) from public.special_sales where invoice_item_id = line and status <> 'cancelled') = 3,
    'F3 the full payment raises the other 2');
  -- 2 collected and both returned before payment, the line lowered and raised again, then paid.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('chair', 2)));
  line := pg_temp.line_of(inv, 'special_product', 'chair');
  perform pg_temp.collect(inv, pg_temp.sp(line, 2));
  perform pg_temp.ret(inv, pg_temp.rsp(line, 2));
  perform pg_temp.check(pg_temp.correct(inv, pg_temp.lines_with(inv, line, 1)) = 'ok'
                        and pg_temp.correct(inv, pg_temp.lines_with(inv, line, 2)) = 'ok', 'F4 lowered and raised again');
  perform pg_temp.pay(inv);
  perform pg_temp.check((select count(*) from public.special_sales where invoice_item_id = line and status = 'pending') = 2,
    'F5 then paid: exactly 2 wait for a warehouse');
  -- The customer moves with a correction: the early sale follows (498, 500).
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('chair', 1)));
  line := pg_temp.line_of(inv, 'special_product', 'chair');
  perform pg_temp.collect(inv, pg_temp.sp(line));
  s := (pg_temp.sales(inv))[1];
  m := pg_temp.correct(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'kind', 'special_product',
                          'special_product_id', pg_temp.fx('sp_chair'), 'quantity', 1, 'unit_price', 900)));
  perform pg_temp.check(m = 'ok' and (select unit_price from public.special_sales where id = s) = 900,
    'F6 the early sale takes its line''s corrected price (500): ' || m);
  -- Lowered: the collected unit still waiting stays; the released one nobody collected goes back.
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('lamp', 2)));
  line := pg_temp.line_of(inv, 'special_product', 'lamp');
  perform pg_temp.pay(inv);
  perform pg_temp.collect(inv, pg_temp.sp(line, 1));
  s := (select x.id from public.special_sales x where x.invoice_item_id = line
          and not exists (select 1 from public.invoice_special_handover_lines h where h.special_sale_id = x.id));
  perform pg_temp.release('special_sale', s);
  m := pg_temp.correct(inv, pg_temp.lines_with(inv, line, 1));
  perform pg_temp.check(m = 'ok' and pg_temp.st(s) = 'cancelled'
                        and pg_temp.st((select special_sale_id from public.invoice_special_handover_lines where invoice_item_id = line)) = 'pending',
    'F10 lowered to 1: the released unit nobody collected goes back, the collected one (still waiting) stays: ' || m);
  -- A paid invoice corrected up so it owes: an item nobody collected still waits for the payment (498).
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('bed', 1)));
  line := pg_temp.line_of(inv, 'special_product', 'bed');
  perform pg_temp.pay(inv);
  perform pg_temp.collect(inv, pg_temp.sp(line));
  perform pg_temp.check(pg_temp.correct(inv, pg_temp.lines_with(inv, line, 2)) = 'ok', 'F7 a paid invoice raised to 2, owing');
  s := (select x.id from public.special_sales x where x.invoice_item_id = line
          and not exists (select 1 from public.invoice_special_handover_lines h where h.special_sale_id = x.id));
  m := pg_temp.release('special_sale', s);
  perform pg_temp.check(m ~ 'owing', 'F8 the unit nobody collected waits for the payment (498): ' || m);
  m := pg_temp.release('special_sale', (select special_sale_id from public.invoice_special_handover_lines where invoice_item_id = line));
  perform pg_temp.check(m = 'ok', 'F9 the one the customer has is released: ' || m);
end $$;

-- ═════ M The waiting list's marks ═════
do $$
declare inv uuid; line uuid; a uuid; b uuid; c uuid; inv2 uuid; m jsonb; e text;
begin
  -- A part-paid invoice: one chair collected (waiting), one not; a consignment bed delivered (waiting).
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('chair', 2), pg_temp.sale_line('purifier', 1)));
  perform pg_temp.settle(inv, 100, jsonb_build_object('specials', jsonb_build_array(
    jsonb_build_object('invoice_item_id', pg_temp.line_of(inv, 'special_product', 'chair'), 'qty', 1),
    jsonb_build_object('invoice_item_id', pg_temp.line_of(inv, 'special_product', 'purifier'), 'qty', 1, 'how', 'delivered'))));
  a := (select special_sale_id from public.invoice_special_handover_lines where invoice_item_id = pg_temp.line_of(inv, 'special_product', 'chair'));
  b := (select special_sale_id from public.invoice_special_handover_lines where invoice_item_id = pg_temp.line_of(inv, 'special_product', 'purifier'));
  -- A paid one with a chair nobody collected.
  inv2 := pg_temp.mk(jsonb_build_array(pg_temp.sale_line('chair', 1)));
  perform pg_temp.pay(inv2);
  c := (pg_temp.sales(inv2))[1];
  perform pg_temp.as_user('owner');
  select coalesce(jsonb_object_agg(w.doc_id, w.doc_kind || ':' || w.how), '{}') into m from public.special_waiting_collected(array[a, b, c]) w;
  perform pg_temp.check(m = jsonb_build_object(a, 'special_sale:collected', b, 'special_sale:delivered'),
    'M1 the Owner sees "customer has it" for the collected chair, "supplier delivered" for the bed, nothing for the one not collected: ' || m::text);
  perform pg_temp.as_user('manager');
  perform pg_temp.check((select count(*) from public.special_waiting_collected(array[a, b, c])) = 2, 'M2 so does the store''s Manager');
  perform pg_temp.as_user('other_mgr');
  perform pg_temp.check((select count(*) from public.special_waiting_collected(array[a, b, c])) = 0, 'M3 a Manager of another store sees none');
  perform pg_temp.as_user('staff');
  e := pg_temp.err(format('select * from public.special_waiting_collected(%L::uuid[])', array[a]));
  perform pg_temp.check(e <> 'ok', 'M4 staff are refused, as for the waiting list: ' || e);
  perform pg_temp.check(has_function_privilege('authenticated', 'public.special_waiting_collected(uuid[])', 'execute')
                        and not has_function_privilege('anon', 'public.special_waiting_collected(uuid[])', 'execute'),
    'M5 signed-in staff may call it (it checks who), the public key not');
  perform pg_temp.ret(inv, pg_temp.rsp(pg_temp.line_of(inv, 'special_product', 'chair')));
  perform pg_temp.as_user('owner');
  perform pg_temp.check(not exists (select 1 from public.special_waiting_collected(array[a]) w where w.doc_id = a),
    'M6 once recorded as returned, no mark');
end $$;

-- ═════ U UNDO and again (left out with -v no_undo=1) ═════
\if :{?no_undo}
\else
-- UNDO refuses while staff recorded anything; this file's own staff records go first (rolled back);
-- the migration's records of K stay, for the UNDO to remove.
select pg_temp.fp() as fp_with \gset
savepoint u1;
\set ON_ERROR_STOP off
\ir ../undo-547.sql
\set ON_ERROR_STOP on
rollback to savepoint u1;
select pg_temp.check(to_regclass('public.invoice_special_handover_lines') is not null and pg_temp.fp() = :'fp_with',
    'U1 UNDO refuses while items are recorded as collected (the error above), and changes nothing') \g /dev/null
-- An older suite's own rolled-back run sets the test-only flag first: then it goes through, staff
-- records and all, and the flag does not outlive it.
savepoint u0;
select set_config('energia.undo547_test_only', 'on', true) \g /dev/null
\ir ../undo-547.sql
select pg_temp.check(to_regclass('public.invoice_special_handover_lines') is null
                     and pg_temp.fp() = 'f5f09a8bf80f379ccdf38b6edaad0dbc/1462'
                     and coalesce(current_setting('energia.undo547_test_only', true), '') = ''
                     and not exists (select 1 from public.special_sale_returns where why = 'item returned'),
    'U0 with the test-only flag UNDO goes through though staff recorded items (rolled back here), and clears the flag') \g /dev/null
rollback to savepoint u0;
delete from public.invoice_special_handover_returns;
delete from public.invoice_special_handover_lines l using public.invoice_handovers h where h.id = l.handover_id and h.source <> 'migration';
delete from public.special_sale_returns where why = 'item returned';
select count(*) as k_migration from public.invoice_handovers where source = 'migration' \gset
\ir ../undo-547.sql
select pg_temp.check(not exists (select 1 from public.invoice_handovers where source = 'migration')
                     and pg_get_constraintdef((select oid from pg_constraint where conname = 'invoice_handovers_source_check')) not like '%migration%',
    'U3b UNDO removed the migration''s own records (' || :k_migration || ') and gave the hand-overs their three sources again') \g /dev/null
do $$ begin
  perform pg_temp.check(pg_temp.fp() = 'f5f09a8bf80f379ccdf38b6edaad0dbc/1462', 'U2 UNDO puts every function back as after 546: ' || pg_temp.fp());
  perform pg_temp.check(to_regclass('public.invoice_special_handover_lines') is null and to_regclass('public.invoice_special_handover_returns') is null
                        and pg_get_constraintdef((select oid from pg_constraint where conname = 'special_sale_returns_why_check')) not like '%item returned%',
    'U3 and drops its tables and its "item returned"');
end $$;
\ir ../../../supabase/547_special_consignment_rental_goods_collected.sql
select pg_temp.check(pg_temp.fp() = :'fp_with', 'U4 547 goes in again as it was') \g /dev/null
select pg_temp.check((select count(*) from public.invoice_handovers h join public.invoice_special_handover_lines l on l.handover_id = h.id
                       where h.source = 'migration' and l.invoice_id in (select v from fx where k in ('k1', 'k2', 'k4'))) = 3,
    'U5 and records the items released before it again (k5 was cancelled in K10: not on a live invoice)') \g /dev/null

\endif

-- ═════ Result ═════
do $$
declare n int; list text;
begin
  select count(*), string_agg(f.msg, E'\n' order by f.n) into n, list from failed f;
  if n > 0 then raise exception '% check(s) failed:%', n, E'\n' || list; end if;
  raise notice 'ALL PASSED';
end $$;
rollback;
