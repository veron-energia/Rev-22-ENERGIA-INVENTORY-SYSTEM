-- Several items in one exchange: plain product lines and items of bundles, in any mix (455).
--
-- The Owner, 22 Oct 2026, item 2: "Both kinds, any mix". One 'Items to return' list where plain product
-- lines (returned whole) and items from a bundle (a quantity up to what is held, not already exchanged)
-- are ticked together, giving ONE exchange number and ONE replacement invoice; the value of everything
-- returned is pooled; one product type per exchange, enforced on the server; part-quantity rules as they
-- are; the whole-bundle exchange stays its own mode. Item 6 (exchange half): exchange_invoice_details
-- returns the exchange's notes.
--
--   G  The md5s and the grants: create_items_exchange is the server's alone; create_exchange_with_details
--      and exchange_invoice_details keep theirs; every function 455 relies on is unchanged.
--   B  Two items of one bundle: one EXC- exchange (kind bundle_component), a returned row each with its
--      credit (adding up to the exchange's), stock back for each and out for each replacement, both marked
--      on the bundle line, ONE replacement invoice (line discounts = the credit), commission on the
--      top-up only, the served staff, one audit row; the page's preview gives the same figures.
--   X  A plain line and items of two bundles: kind items, the credit pooled (a non-refundable remainder,
--      no payment taken, a payment refused), the plain line marked exchanged, each bundle line its item;
--      the note comes back through exchange_invoice_details exactly, and none for an exchange without one.
--   P  Plain lines only, through 'items': the same exchange as the old 'product' kind gives (EX-).
--   R  Refused, nothing written: the same item twice, more than the bundle holds, none, part of a plain
--      line, a bundle line with no item named, a product line named as a bundle, a product not in the
--      bundle, own and third-party mixed (returned, or returned and replacement), a line of another
--      invoice, a wallet payment, more than is due, two replacement rows of one product beyond its stock,
--      no reason, nothing returned, no replacement, staff of another store, a login that is not staff.
--   A  Already exchanged: an item of a bundle again, a plain line again, a bundle exchanged whole; the
--      whole-bundle exchange after its items; cancelling the original invoice.
--   K  The old kinds still work (bundle_component, product, bundle); an instalment on an 'items' top-up
--      is recorded on the replacement invoice; nothing is refused at commit.
--   M  455 twice changes nothing; its first run changes create_exchange_with_details and
--      exchange_invoice_details and adds create_items_exchange; its self-test leaves no row (when this
--      file installs it).
--
-- Disposable local database only; everything is rolled back. Every name is invented ('X455 ...'), emails
-- are @example.com and phones are ACMA's fictional mobile range (+61 491 570 ...). It installs 455 twice
-- (run with -v skip_install=1 where 455 is already installed). Every check runs, then the file fails if
-- any did.
\set ON_ERROR_STOP on
begin;
create function pg_temp.row_counts() returns jsonb language plpgsql as
$$declare r record; n bigint; v jsonb := '{}'::jsonb;
begin
  for r in select c.oid::regclass::text as t from pg_class c join pg_namespace s on s.oid = c.relnamespace
            where s.nspname in ('public', 'auth') and c.relkind = 'r' order by 1 loop
    execute format('select count(*) from %s', r.t) into n;
    v := v || jsonb_build_object(r.t, n);
  end loop;
  return v;
end$$;
create function pg_temp.fn_md5s() returns table(fn text, md5 text) language plpgsql as
$$begin
  perform set_config('search_path', 'public', true);
  return query select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))
                 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
end$$;
\if :{?skip_install}
\else
create temp table b455 as select * from pg_temp.fn_md5s();
create temp table r455 as select pg_temp.row_counts() as before;
\ir ../../../supabase/455_exchange_several_items.sql
create temp table m455 as select * from pg_temp.fn_md5s();
alter table r455 add column after1 jsonb;
update r455 set after1 = pg_temp.row_counts();
\ir ../../../supabase/455_exchange_several_items.sql
\endif
set local search_path = public;
set local lock_timeout = '10s';
set local statement_timeout = '300s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.putx(key text, val uuid) returns uuid language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v returning v $$;
-- Acting as a signed-in person (null: the server, keeping auth.uid() for created_by).
create function pg_temp.as_user(p uuid, keep uuid default null) returns void language plpgsql as $$
begin
  if p is null then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', coalesce(keep::text, ''), true);
  else
    perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', p::text, true);
  end if;
end $$;
-- What a commit does to the replacement invoice: create it now, then go back to waiting.
create function pg_temp.settle() returns void language plpgsql as $$
begin
  set constraints public.exchange_creates_invoice immediate;
  set constraints public.exchange_creates_invoice deferred;
end $$;
-- What a commit does to 408's stock check: run every pending check now.
create function pg_temp.commit_checks() returns void language plpgsql as $$
begin
  if exists (select 1 from pg_constraint where conrelid = 'public.stock_movements'::regclass
              and conname = 'stock_return_exchange_hold' and condeferrable) then
    set constraints public.stock_return_exchange_hold immediate;
    set constraints public.stock_return_exchange_hold deferred;
  end if;
end $$;
create function pg_temp.q(p_product text) returns integer language sql as
$$ select coalesce((select current_qty from public.store_inventory where store_id = pg_temp.fx('st') and product_id = pg_temp.fx(p_product)), 0) $$;
-- A sale at the store, paid in full by cash.
create function pg_temp.sale(p_items jsonb, p_amount numeric) returns uuid language plpgsql as $$
declare v uuid;
begin
  perform pg_temp.as_user(null, pg_temp.fx('own'));
  v := public.create_invoice(pg_temp.fx('st'), pg_temp.fx('cust'), null, p_items, 0, null, null, null);
  perform public.record_invoice_payment(v, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', p_amount)), gen_random_uuid());
  return v;
end $$;
create function pg_temp.pl(p text) returns jsonb language sql as
$$ select jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx(p), 'quantity', 1) $$;
create function pg_temp.bu(p text, n int default 1) returns jsonb language sql as
$$ select jsonb_build_object('kind', 'promotion', 'promotion_id', pg_temp.fx(p), 'quantity', n) $$;
-- The invoice's line of a product, or of a bundle.
create function pg_temp.line(p_inv uuid, p text) returns uuid language sql as
$$ select id from public.invoice_items where invoice_id = p_inv and (product_id = pg_temp.fx(p) or promotion_id = pg_temp.fx(p)) order by id limit 1 $$;
-- A returned entry: a plain line whole, or an item of a bundle line.
create function pg_temp.r_line(p_inv uuid, p text) returns jsonb language sql as
$$ select jsonb_build_object('invoice_item_id', pg_temp.line(p_inv, p), 'quantity', (select quantity from public.invoice_items where id = pg_temp.line(p_inv, p))) $$;
create function pg_temp.r_item(p_inv uuid, p_bundle text, p text, n int) returns jsonb language sql as
$$ select jsonb_build_object('invoice_item_id', pg_temp.line(p_inv, p_bundle), 'product_id', pg_temp.fx(p), 'quantity', n) $$;
create function pg_temp.repl(p text, n int) returns jsonb language sql as
$$ select jsonb_build_object('product_id', pg_temp.fx(p), 'quantity', n) $$;
create function pg_temp.cashpay(n numeric) returns jsonb language sql as
$$ select jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', n)) $$;
-- The page's payload for an 'items' exchange of p_inv at the store, served by Staff One.
create function pg_temp.payload(p_inv uuid, p_returned jsonb, p_replacement jsonb, p_extra jsonb default '{}'::jsonb) returns jsonb language sql as
$$ select jsonb_build_object('original_invoice_id', p_inv, 'processing_store_id', pg_temp.fx('st'),
            'returned', p_returned, 'replacement', p_replacement, 'payments', '[]'::jsonb,
            'reason', 'X455 test reason', 'served_by', jsonb_build_array(pg_temp.fx('s1')::text)) || p_extra $$;
-- An exchange made as Staff One, as the page makes it; its replacement invoice made as a commit would.
create function pg_temp.exchange(p_kind text, p jsonb) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.as_user(pg_temp.fx('s1'));
  v := public.create_exchange_with_details(p_kind, p);
  perform pg_temp.settle();
  perform pg_temp.as_user(null, pg_temp.fx('own'));
  return v;
end $$;
-- What a refused exchange says (an accepted one is undone and says 'accepted').
create function pg_temp.refusal(p_kind text, p jsonb, p_as uuid default null) returns text language plpgsql as $$
begin
  perform pg_temp.as_user(coalesce(p_as, pg_temp.fx('s1')));
  perform public.create_exchange_with_details(p_kind, p);
  raise exception using errcode = 'P0455', message = 'accepted';
exception when sqlstate 'P0455' then perform pg_temp.as_user(null, pg_temp.fx('own')); return 'accepted';
          when others then perform pg_temp.as_user(null, pg_temp.fx('own')); return sqlerrm;
end $$;
create function pg_temp.exinv(p_ex uuid) returns uuid language sql as
$$ select id from public.invoices where exchange_id = p_ex and is_exchange $$;
create function pg_temp.moves(p_no text, p_type text) returns text language sql as
$$ select coalesce(string_agg(p.name || ' ' || m.quantity, ', ' order by p.name), '')
     from public.stock_movements m join public.products p on p.id = m.product_id
    where m.notes like '%' || p_no || '%' and m.movement_type::text = p_type $$;

-- ═════ Fixtures ═════
do $$
declare own uuid := gen_random_uuid(); s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid();
  st uuid; st2 uuid; ref uuid; v uuid; x record;
begin
  -- The one settings row production has (the commission rates' defaults).
  insert into app_settings default values on conflict do nothing;
  insert into auth.users(id, email) values (own, 'x455-own@example.com'), (s1, 'x455-s1@example.com'), (s2, 'x455-s2@example.com');
  insert into profiles(id, full_name, email, role) values
    (own, 'X455 Owner', 'x455-own@example.com', 'owner'),
    (s1, 'X455 Staff One', 'x455-s1@example.com', 'staff'),
    (s2, 'X455 Staff Two', 'x455-s2@example.com', 'staff');
  perform pg_temp.putx('own', own); perform pg_temp.putx('s1', s1); perform pg_temp.putx('s2', s2);
  perform pg_temp.as_user(null, own);
  insert into stores(name, code, country_code) values ('X455 Retail', 'X455R', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('X455 Van', 'X455V', 'SG') returning id into st2;
  perform pg_temp.putx('st', st); perform pg_temp.putx('st2', st2);
  insert into user_store_assignments(user_id, store_id) values (s1, st), (s2, st2);
  insert into customers(full_name, phone) values ('X455 Test Customer', '+61491570737') returning id into v;
  perform pg_temp.putx('cust', v);
  insert into customers(full_name, phone) values ('X455 Test Referrer', '+61491572983') returning id into ref;
  insert into customer_affiliates(customer_id, status, activated_at, activated_by) values (ref, 'active', now(), own) returning id into v;
  perform pg_temp.putx('aff', v);
  insert into payment_methods(name, is_active) values ('X455 Cash', true) returning id into v;
  perform pg_temp.putx('cash', v);
  insert into payment_methods(name, is_active) values ('X455 Card', true) returning id into v;
  perform pg_temp.putx('card', v);
  insert into payment_methods(name, is_active, is_wallet_credit) values ('X455 Wallet', true, true) returning id into v;
  perform pg_temp.putx('wallet', v);
  -- own A 100, B 100, C 120, D 50, E 60 (one in stock), F 1000; third-party T 80, U 90
  for x in select * from (values ('A', 'own', 100::numeric), ('B', 'own', 100), ('C', 'own', 120), ('D', 'own', 50), ('E', 'own', 60),
                                 ('F', 'own', 1000), ('T', 'third_party', 80), ('U', 'third_party', 90)) y(k, t, p) loop
    insert into products(name, sku, product_type) values ('X455 ' || x.k, 'X455' || x.k, x.t::product_type) returning id into v;
    perform pg_temp.putx(x.k, v);
    insert into store_inventory(store_id, product_id, current_qty)
      select s, v, case when x.k = 'E' then 1 else 50 end from unnest(array[st, st2]) s;
    perform set_product_prices(s, v, x.p, x.p, 'available') from unnest(array[st, st2]) s;
  end loop;
  -- bundles: AB (A+B, S$200 today) sold for S$150; DD (D x2, S$100 today) for S$80; XC (C) for S$110
  for x in select * from (values ('AB', 150::numeric), ('DD', 80), ('XC', 110)) y(k, p) loop
    insert into promotions(name, code, fixed_price) values ('X455 Bundle ' || x.k, 'X455' || x.k, x.p) returning id into v;
    perform pg_temp.putx(x.k, v);
  end loop;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values
    (pg_temp.fx('AB'), 'product', pg_temp.fx('A'), 1), (pg_temp.fx('AB'), 'product', pg_temp.fx('B'), 1),
    (pg_temp.fx('DD'), 'product', pg_temp.fx('D'), 2), (pg_temp.fx('XC'), 'product', pg_temp.fx('C'), 1);
  perform set_promotion_prices(pg_temp.fx(b.k), s, b.p, b.p, true)
     from (values ('AB', 150::numeric), ('DD', 80), ('XC', 110)) b(k, p), unnest(array[st, st2]) s;
end $$;

-- ═════ G The md5s and the grants ═════
select pg_temp.check(md5(pg_get_functiondef('public.create_items_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text)'::regprocedure)) = '39d3bf8e11dcf34425cb7bce4ea51a6d'
    and md5(pg_get_functiondef('public.create_exchange_with_details(text,jsonb)'::regprocedure)) = '82cdd84bf325a4ea5a49ea665f2d3404'
    and md5(pg_get_functiondef('public.exchange_invoice_details(uuid)'::regprocedure)) = '45791e627e1616ab7edad181139a2d83',
  'G1 create_items_exchange, create_exchange_with_details and exchange_invoice_details have 455''s AFTER md5s');
select pg_temp.check(not has_function_privilege('anon', 'public.create_items_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.create_items_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text)', 'execute')
    and has_function_privilege('service_role', 'public.create_items_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text)', 'execute')
    and not has_function_privilege('anon', 'public.create_exchange_with_details(text,jsonb)', 'execute')
    and has_function_privilege('authenticated', 'public.create_exchange_with_details(text,jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.exchange_invoice_details(uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.exchange_invoice_details(uuid)', 'execute'),
  'G2 create_items_exchange is the server''s alone; the page''s two keep staff''s grant and not anon''s');
select pg_temp.check(not exists (
    select 1 from (values
      ('create_product_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text,boolean,uuid,text)', '48679d09a214c9dcf8850be51110d8bc'),
      ('create_bundle_component_exchange(uuid,uuid,uuid,uuid,integer,jsonb,jsonb,text,text)', '8d588d7f856fca85356e293a8af3ecef'),
      ('create_bundle_exchange(uuid,uuid,uuid,uuid,jsonb,text,text)', 'c552d1734cd4e8052b113a6026d8a6b2'),
      ('create_exchange_invoice(uuid)', '6392abd80baad4b1a2a5069654c994c1'),
      ('exchange_credit_value(uuid,uuid,uuid,integer)', '8998ee93a6fce8ce3a82e2a8c49aa95a'),
      ('exchange_credit_preview(uuid,uuid)', '263bb91b1ed38c6b53767c4d0182595c'),
      ('bundle_line_components(uuid)', '794ad28556de3e53d945e9ff742697a0'),
      ('exchange_ineligibility_reason(uuid)', '869985df7601d401df40f44c40dd2d6e'),
      ('exchange_assert_payments(jsonb,numeric,boolean)', 'd6fd63cf456a5f1557405e70a1e81440'),
      ('set_exchange_details(uuid,jsonb,jsonb,uuid,date,text)', 'f317e42aae09809c46625f47eb884298'),
      ('exchange_invoice_hold(uuid,uuid[])', 'd55f4696593447039aa45eeeae9b66d7'),
      ('trg_stock_return_exchange_hold()', '6f9af8dd208b7203565ed1f5f90d781a'),
      ('exchange_bundle_quote(uuid,uuid,uuid,uuid)', '447b48555da3e278bf2adb4cde3c155b')) x(fn, m)
     where md5(pg_get_functiondef(to_regprocedure('public.' || x.fn))) is distinct from x.m),
  'G3 the creators, the replacement invoice, the credit, the holds and the whole-bundle quote are as on production (s450)');

-- ═════ B Two items of one bundle ═════
do $$
declare inv uuid; res jsonb; ex uuid; ei uuid; q0 int[]; prev jsonb; li uuid; c0 text;
begin
  inv := pg_temp.sale(jsonb_build_array(pg_temp.bu('AB')), 150);
  c0 := (select count(*) || '/' || coalesce(sum(commission_amount), 0) from commissions where invoice_id = inv);
  li := pg_temp.line(inv, 'AB');
  perform pg_temp.putx('inv_b', inv);
  q0 := array[pg_temp.q('A'), pg_temp.q('B'), pg_temp.q('C'), pg_temp.q('D')];
  -- what the page shows first, for the two items
  perform pg_temp.as_user(pg_temp.fx('s1'));
  prev := public.exchange_credit_preview(inv, pg_temp.fx('st'));
  perform pg_temp.as_user(null, pg_temp.fx('own'));
  res := pg_temp.exchange('items', pg_temp.payload(inv,
    jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 1), pg_temp.r_item(inv, 'AB', 'B', 1)),
    jsonb_build_array(pg_temp.repl('C', 1), pg_temp.repl('D', 1)),
    jsonb_build_object('payments', pg_temp.cashpay(20), 'affiliate', jsonb_build_object('mode', 'set', 'id', pg_temp.fx('aff')))));
  ex := (res->>'id')::uuid; ei := pg_temp.exinv(ex);
  perform pg_temp.putx('ex_b', ex);
  perform pg_temp.check((select count(*) from product_exchanges where original_invoice_id = inv) = 1
      and res->>'exchange_no' like 'EXC-%' and res->>'kind' = 'bundle_component'
      and (select exchange_kind from product_exchanges where id = ex) = 'bundle_component',
    'B1 two items of one bundle make ONE exchange, EXC- numbered, kind bundle_component: ' || coalesce(res::text, 'none'));
  perform pg_temp.check((select string_agg(p.name || '=' || i.line_total, ',' order by p.name) from product_exchange_items i join products p on p.id = i.product_id
                          where i.exchange_id = ex and i.direction = 'returned') = 'X455 A=75.00,X455 B=75.00'
      and (select bool_and(original_invoice_item_id = li) from product_exchange_items where exchange_id = ex and direction = 'returned')
      and (select sum(line_total) from product_exchange_items where exchange_id = ex and direction = 'returned')
          = (select returned_credit_total from product_exchanges where id = ex)
      and (select returned_credit_total::text || '/' || replacement_total::text || '/' || topup_amount::text || '/' || nonrefundable_amount::text
             from product_exchanges where id = ex) = '150.00/170.00/20.00/0.00',
    'B2 a returned row each, at its share of the S$150 bundle (75 + 75), adding up to the exchange''s credit; S$170 replaced, S$20 paid');
  perform pg_temp.check(
      (select (o->>'credit')::numeric from jsonb_array_elements(prev->'lines') l, jsonb_array_elements(l->'components') c, jsonb_array_elements(c->'options') o
        where l->>'invoice_item_id' = li::text and c->>'product_id' = pg_temp.fx('A')::text and (o->>'quantity')::int = 1)
    + (select (o->>'credit')::numeric from jsonb_array_elements(prev->'lines') l, jsonb_array_elements(l->'components') c, jsonb_array_elements(c->'options') o
        where l->>'invoice_item_id' = li::text and c->>'product_id' = pg_temp.fx('B')::text and (o->>'quantity')::int = 1) = 150,
    'B3 the page''s preview (exchange_credit_preview) of the two items adds up to the credit given');
  perform pg_temp.check(array[pg_temp.q('A'), pg_temp.q('B'), pg_temp.q('C'), pg_temp.q('D')] = array[q0[1] + 1, q0[2] + 1, q0[3] - 1, q0[4] - 1]
      and pg_temp.moves(res->>'exchange_no', 'exchange_return_in') = 'X455 A 1, X455 B 1'
      and pg_temp.moves(res->>'exchange_no', 'exchange_replacement_out') = 'X455 C 1, X455 D 1',
    'B4 stock: A and B back on the shelf, C and D out, a movement each: ' || pg_temp.moves(res->>'exchange_no', 'exchange_return_in'));
  perform pg_temp.check((select exchanged_at is null from invoice_items where id = li)
      and (select string_agg(e->>'product_id' || ':' || (e->>'qty') || ':' || (e->>'exchange_id'), ',' order by e->>'product_id')
             from invoice_items it, jsonb_array_elements(it.component_exchanged) e where it.id = li)
          = (select string_agg(x || ':1:' || ex::text, ',' order by x) from unnest(array[pg_temp.fx('A')::text, pg_temp.fx('B')::text]) x),
    'B5 the bundle line stays, both its items marked exchanged by this exchange');
  perform pg_temp.check((select count(*) from invoices where exchange_id = ex and is_exchange) = 1
      and (select total_amount::text || '/' || paid_amount::text || '/' || status::text || '/' || exchange_credit_total::text from invoices where id = ei) = '20.00/20.00/paid/150.00'
      and (select count(*) || '/' || sum(line_discount)::text || '/' || sum(line_total)::text from invoice_items where invoice_id = ei) = '2/150.00/170.00'
      and exists (select 1 from invoice_service_staff where invoice_id = ei and staff_id = pg_temp.fx('s1'))
      and (select affiliate_id from invoices where id = ei) = pg_temp.fx('aff'),
    'B6 ONE replacement invoice: S$20, paid, its two lines at full value less the S$150 credit, served by Staff One, the chosen affiliate');
  perform pg_temp.check((select sum(line_amount)::text || '/' || sum(commission_amount)::text from commissions where invoice_id = ei and tier::text = 'tier1') = '20.00/3.00'
      and (select count(*) || '/' || coalesce(sum(commission_amount), 0) from commissions where invoice_id = inv) = c0,
    'B7 commission on the S$20 top-up only (S$3.00 at the tier-1 own rate), the original sale''s as it was');
  perform pg_temp.check((select count(*) from audit_logs where record_id = ex and action = 'exchange_completed') = 1
      and (select jsonb_array_length(new_data->'returned') = 2 and (new_data->>'credit_todays_price')::numeric = 200 and (new_data->>'credit_paid')::numeric = 150
             from audit_logs where record_id = ex and action = 'exchange_completed'),
    'B8 one audit row, listing both items, today''s price (S$200) and what was paid (S$150) behind the credit');
end $$;

-- ═════ X A plain line and items of two bundles ═════
do $$
declare inv uuid; res jsonb; ex uuid; ei uuid; q0 int[]; v text; d jsonb;
  note text := E'X455 note line one\nCustomer said "keep the box" <ok> & more';
begin
  inv := pg_temp.sale(jsonb_build_array(pg_temp.pl('A'), pg_temp.bu('AB'), pg_temp.bu('DD')), 330);
  perform pg_temp.putx('inv_x', inv);
  q0 := array[pg_temp.q('A'), pg_temp.q('B'), pg_temp.q('C'), pg_temp.q('D')];
  -- Nothing is due, so a payment is refused.
  v := pg_temp.refusal('items', pg_temp.payload(inv,
    jsonb_build_array(pg_temp.r_line(inv, 'A'), pg_temp.r_item(inv, 'AB', 'B', 1), pg_temp.r_item(inv, 'DD', 'D', 2)),
    jsonb_build_array(pg_temp.repl('C', 2)), jsonb_build_object('payments', pg_temp.cashpay(10))));
  perform pg_temp.check(v like 'Nothing is due on this exchange, so no payment can be taken (S$10.00 was entered).%'
      and not exists (select 1 from product_exchanges where original_invoice_id = inv),
    'X1 a payment when the pooled credit covers the replacement is refused: ' || v);
  res := pg_temp.exchange('items', pg_temp.payload(inv,
    jsonb_build_array(pg_temp.r_line(inv, 'A'), pg_temp.r_item(inv, 'AB', 'B', 1), pg_temp.r_item(inv, 'DD', 'D', 2)),
    jsonb_build_array(pg_temp.repl('C', 2)), jsonb_build_object('notes', note)));
  ex := (res->>'id')::uuid; ei := pg_temp.exinv(ex);
  perform pg_temp.putx('ex_x', ex);
  perform pg_temp.check(res->>'exchange_no' like 'EXC-%' and res->>'kind' = 'items'
      and (select count(*) from product_exchanges where original_invoice_id = inv) = 1,
    'X2 a plain line with items of two bundles: ONE exchange, kind items: ' || coalesce(res->>'exchange_no', 'none'));
  perform pg_temp.check((select string_agg(p.name || '=' || i.quantity || '@' || i.line_total, ',' order by p.name) from product_exchange_items i join products p on p.id = i.product_id
                          where i.exchange_id = ex and i.direction = 'returned') = 'X455 A=1@100.00,X455 B=1@75.00,X455 D=2@80.00'
      and (select returned_credit_total::text || '/' || replacement_total::text || '/' || topup_amount::text || '/' || nonrefundable_amount::text
             from product_exchanges where id = ex) = '255.00/240.00/0.00/15.00',
    'X3 the credit is pooled: A S$100 + B S$75 + D x2 S$80 = S$255 against S$240, S$15 non-refundable, nothing to pay');
  perform pg_temp.check((select exchanged_at is not null and exchange_id = ex from invoice_items where id = pg_temp.line(inv, 'A'))
      and (select jsonb_array_length(component_exchanged) = 1 and component_exchanged->0->>'product_id' = pg_temp.fx('B')::text and exchanged_at is null
             from invoice_items where id = pg_temp.line(inv, 'AB'))
      and (select jsonb_array_length(component_exchanged) = 1 and (component_exchanged->0->>'qty')::int = 2 and exchanged_at is null
             from invoice_items where id = pg_temp.line(inv, 'DD')),
    'X4 the plain line is marked exchanged; each bundle line its item (B; D x2)');
  perform pg_temp.check(array[pg_temp.q('A'), pg_temp.q('B'), pg_temp.q('C'), pg_temp.q('D')] = array[q0[1] + 1, q0[2] + 1, q0[3] - 2, q0[4] + 2],
    'X5 stock: A, B and two D back, two C out');
  perform pg_temp.check((select count(*) from invoices where exchange_id = ex and is_exchange) = 1
      and (select total_amount::text || '/' || status::text || '/' || discount_total::text || '/' || exchange_credit_total::text from invoices where id = ei) = '0.00/paid/240.00/240.00'
      and (select sum(line_discount) from invoice_items where invoice_id = ei) = 240
      and (select coalesce(sum(line_amount), 0) from commissions where invoice_id = ei) = 0,
    'X6 ONE replacement invoice: nothing to pay, paid, the S$240 covered by the credit, no commission');
  perform pg_temp.as_user(pg_temp.fx('s1'));
  d := public.exchange_invoice_details(ei);
  perform pg_temp.check(d->>'notes' = note and jsonb_array_length(d->'returned_items') = 3 and (d->>'returned_total')::numeric = 255
      and d->>'exchange_no' = res->>'exchange_no',
    'X7 exchange_invoice_details returns the exchange''s note exactly (line break, quotes, < and &), and its three returned items');
  d := public.exchange_invoice_details(pg_temp.exinv(pg_temp.fx('ex_b')));
  perform pg_temp.check(d ? 'notes' and jsonb_typeof(d->'notes') = 'null',
    'X8 an exchange without a note returns notes null');
  perform pg_temp.as_user(null, pg_temp.fx('own'));
  perform pg_temp.check((select notes from product_exchanges where id = ex) = note,
    'X9 the note is stored as typed');
end $$;

-- ═════ P Plain lines only, through 'items' and through 'product' ═════
do $$
declare inv1 uuid; inv2 uuid; r1 jsonb; r2 jsonb; a text; b text;
begin
  inv1 := pg_temp.sale(jsonb_build_array(pg_temp.pl('A'), pg_temp.pl('D')), 150);
  inv2 := pg_temp.sale(jsonb_build_array(pg_temp.pl('A'), pg_temp.pl('D')), 150);
  r1 := pg_temp.exchange('items', pg_temp.payload(inv1, jsonb_build_array(pg_temp.r_line(inv1, 'A'), pg_temp.r_line(inv1, 'D')),
          jsonb_build_array(pg_temp.repl('C', 1), pg_temp.repl('D', 1)), jsonb_build_object('payments', pg_temp.cashpay(20))));
  r2 := pg_temp.exchange('product', pg_temp.payload(inv2, jsonb_build_array(pg_temp.r_line(inv2, 'A'), pg_temp.r_line(inv2, 'D')),
          jsonb_build_array(pg_temp.repl('C', 1), pg_temp.repl('D', 1)), jsonb_build_object('payments', pg_temp.cashpay(20))));
  select string_agg(x, '|') into a from (
    select returned_credit_total::text || '/' || replacement_total || '/' || topup_amount || '/' || nonrefundable_amount || '/' || exchange_kind as x
      from product_exchanges where id = (r1->>'id')::uuid
    union all select string_agg(p.name || '=' || i.line_total, ',' order by p.name) from product_exchange_items i join products p on p.id = i.product_id
      where i.exchange_id = (r1->>'id')::uuid and i.direction = 'returned'
    union all select total_amount || '/' || discount_total from invoices where exchange_id = (r1->>'id')::uuid and is_exchange) y;
  select string_agg(x, '|') into b from (
    select returned_credit_total::text || '/' || replacement_total || '/' || topup_amount || '/' || nonrefundable_amount || '/' || exchange_kind as x
      from product_exchanges where id = (r2->>'id')::uuid
    union all select string_agg(p.name || '=' || i.line_total, ',' order by p.name) from product_exchange_items i join products p on p.id = i.product_id
      where i.exchange_id = (r2->>'id')::uuid and i.direction = 'returned'
    union all select total_amount || '/' || discount_total from invoices where exchange_id = (r2->>'id')::uuid and is_exchange) y;
  perform pg_temp.check(a = b and r1->>'exchange_no' like 'EX-%' and r2->>'exchange_no' like 'EX-%'
      and a = '150.00/170.00/20.00/0.00/product|X455 A=100.00,X455 D=50.00|20.00/150.00',
    'P1 plain lines only through ''items'' are the exchange the ''product'' kind makes (EX-, kind product): ' || coalesce(a, 'none') || ' vs ' || coalesce(b, 'none'));
end $$;

-- ═════ R Refused, nothing written ═════
do $$
declare inv uuid; inv_other uuid; v text; q0 int[]; c0 bigint; c1 bigint;
  t record;
begin
  inv := pg_temp.sale(jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('A'), 'quantity', 2),
                                        pg_temp.pl('T'), pg_temp.bu('AB')), 430);
  inv_other := pg_temp.fx('inv_b');
  q0 := array[pg_temp.q('A'), pg_temp.q('B'), pg_temp.q('C'), pg_temp.q('E'), pg_temp.q('T'), pg_temp.q('U')];
  c0 := (select count(*) from product_exchanges);
  for t in select * from (values
    ('R1 the same bundle item twice', jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 1), pg_temp.r_item(inv, 'AB', 'A', 1)), jsonb_build_array(pg_temp.repl('C', 1)), '{}'::jsonb,
       'The same item is listed twice in this exchange'),
    ('R2 the same plain line twice', jsonb_build_array(pg_temp.r_line(inv, 'A'), pg_temp.r_line(inv, 'A')), jsonb_build_array(pg_temp.repl('F', 1)), '{}'::jsonb,
       'The same item is listed twice in this exchange'),
    ('R3 more of an item than the bundle holds', jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 2)), jsonb_build_array(pg_temp.repl('C', 1)), '{}'::jsonb,
       'Invalid component quantity (bundle has 1 of that product)'),
    ('R4 none of an item', jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 0)), jsonb_build_array(pg_temp.repl('C', 1)), '{}'::jsonb,
       'Invalid component quantity (bundle has 1 of that product)'),
    ('R5 part of a plain line (1 of 2)', jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.line(inv, 'A'), 'quantity', 1)), jsonb_build_array(pg_temp.repl('C', 1)), '{}'::jsonb,
       'Return the full quantity of the purchased line in 3A'),
    ('R6 a bundle line with no item named', jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.line(inv, 'AB'))), jsonb_build_array(pg_temp.repl('C', 1)), '{}'::jsonb,
       'A bundle is returned item by item here (name the product of it being returned), or whole as a bundle exchange'),
    ('R7 a product line named as a bundle', jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.line(inv, 'A'), 'product_id', pg_temp.fx('A'), 'quantity', 1)), jsonb_build_array(pg_temp.repl('C', 1)), '{}'::jsonb,
       'That line is not a bundle'),
    ('R8 a product the bundle does not hold', jsonb_build_array(pg_temp.r_item(inv, 'AB', 'C', 1)), jsonb_build_array(pg_temp.repl('C', 1)), '{}'::jsonb,
       'That product is not a component of this bundle'),
    ('R9 own and third-party returned together', jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 1), pg_temp.r_line(inv, 'T')), jsonb_build_array(pg_temp.repl('C', 1)), '{}'::jsonb,
       'All returned items must be the same product type'),
    ('R10 an own item for a third-party replacement', jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 1)), jsonb_build_array(pg_temp.repl('U', 1)), '{}'::jsonb,
       'Own products may only be exchanged for own products, and third-party for third-party'),
    ('R11 a line of another invoice', jsonb_build_array(pg_temp.r_item(inv_other, 'AB', 'A', 1)), jsonb_build_array(pg_temp.repl('C', 1)), '{}'::jsonb,
       'A returned item is not part of the original invoice'),
    ('R12 a wallet payment', jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 1)), jsonb_build_array(pg_temp.repl('C', 1)),
       jsonb_build_object('payments', jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('wallet'), 'amount', 45))),
       '"X455 Wallet" is wallet credit, which cannot pay an exchange%'),
    ('R13 more than is due', jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 1)), jsonb_build_array(pg_temp.repl('C', 1)), jsonb_build_object('payments', pg_temp.cashpay(50)),
       'Top-up payment (S$50.00) is more than the amount due (S$45.00)'),
    ('R14 two rows of one replacement beyond its stock', jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 1)), jsonb_build_array(pg_temp.repl('E', 1), pg_temp.repl('E', 1)), '{}'::jsonb,
       'Insufficient replacement stock at the processing store: X455 E has 1, and 2 is asked for'),
    ('R15 no reason', jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 1)), jsonb_build_array(pg_temp.repl('C', 1)), jsonb_build_object('reason', '  '),
       'A reason is required for the exchange'),
    ('R16 nothing returned', '[]'::jsonb, jsonb_build_array(pg_temp.repl('C', 1)), '{}'::jsonb,
       'Select at least one item to return'),
    ('R17 no replacement', jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 1)), '[]'::jsonb, '{}'::jsonb,
       'Select at least one replacement product')) x(label, ret, rep, extra, says)
  loop
    v := pg_temp.refusal('items', pg_temp.payload(inv, t.ret, t.rep, t.extra));
    perform pg_temp.check(v like t.says, t.label || ' is refused: ' || v);
  end loop;
  v := pg_temp.refusal('items', pg_temp.payload(inv, jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 1)), jsonb_build_array(pg_temp.repl('C', 1)),
         jsonb_build_object('payments', pg_temp.cashpay(45))), pg_temp.fx('s2'));
  perform pg_temp.check(v = 'You do not have access to the processing store', 'R18 staff of another store are refused: ' || v);
  v := pg_temp.refusal('items', pg_temp.payload(inv, jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 1)), jsonb_build_array(pg_temp.repl('C', 1))), gen_random_uuid());
  perform pg_temp.check(v like 'Only active Energia staff%', 'R19 a login that is not staff is refused (406): ' || v);
  v := pg_temp.refusal('mystery', pg_temp.payload(inv, '[]'::jsonb, '[]'::jsonb));
  perform pg_temp.check(v = 'Unknown exchange kind mystery', 'R20 an unknown kind is still refused: ' || v);
  -- the same with the right money goes through, so each refusal above is for its own reason
  v := pg_temp.refusal('items', pg_temp.payload(inv, jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 1)), jsonb_build_array(pg_temp.repl('C', 1)),
         jsonb_build_object('payments', pg_temp.cashpay(45))));
  perform pg_temp.check(v = 'accepted', 'R21 control: one item of the bundle for C, S$45 paid, is accepted: ' || v);
  c1 := (select count(*) from product_exchanges);
  perform pg_temp.check(c1 = c0 and array[pg_temp.q('A'), pg_temp.q('B'), pg_temp.q('C'), pg_temp.q('E'), pg_temp.q('T'), pg_temp.q('U')] = q0
      and (select bool_and(exchanged_at is null and coalesce(jsonb_array_length(component_exchanged), 0) = 0) from invoice_items where invoice_id = inv),
    'R22 nothing refused (or undone) left an exchange, moved stock or marked a line');
end $$;

-- ═════ A Already exchanged ═════
do $$
declare inv uuid; v text; res jsonb; q0 int;
begin
  inv := pg_temp.fx('inv_b');
  v := pg_temp.refusal('items', pg_temp.payload(inv, jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 1)), jsonb_build_array(pg_temp.repl('C', 1)),
         jsonb_build_object('payments', pg_temp.cashpay(45))));
  perform pg_temp.check(v = 'That component has already been exchanged', 'A1 an item of a bundle already exchanged is refused: ' || v);
  inv := pg_temp.fx('inv_x');
  v := pg_temp.refusal('items', pg_temp.payload(inv, jsonb_build_array(pg_temp.r_line(inv, 'A')), jsonb_build_array(pg_temp.repl('C', 1)),
         jsonb_build_object('payments', pg_temp.cashpay(20))));
  perform pg_temp.check(v = 'An item on this invoice has already been exchanged', 'A2 a plain line already exchanged is refused: ' || v);
  -- the other item of a bundle line one item of which went is still exchangeable
  v := pg_temp.refusal('items', pg_temp.payload(inv, jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 1)), jsonb_build_array(pg_temp.repl('C', 1)),
         jsonb_build_object('payments', pg_temp.cashpay(45))));
  perform pg_temp.check(v = 'accepted', 'A3 the other item of that bundle line still can be: ' || v);
  -- whole bundle after its items: refused (408)
  inv := pg_temp.fx('inv_b');
  v := pg_temp.refusal('bundle', jsonb_build_object('original_invoice_id', inv, 'processing_store_id', pg_temp.fx('st'),
         'original_invoice_item_id', pg_temp.line(inv, 'AB'), 'new_promotion_id', pg_temp.fx('XC'),
         'reason', 'X455 swap all', 'served_by', jsonb_build_array(pg_temp.fx('s1')::text)));
  perform pg_temp.check(v like '%already exchanged on its own%', 'A4 the whole bundle after its items were exchanged is refused: ' || v);
  -- a bundle exchanged whole: its items are refused
  inv := pg_temp.sale(jsonb_build_array(pg_temp.bu('AB')), 150);
  res := pg_temp.exchange('bundle', jsonb_build_object('original_invoice_id', inv, 'processing_store_id', pg_temp.fx('st'),
         'original_invoice_item_id', pg_temp.line(inv, 'AB'), 'new_promotion_id', pg_temp.fx('XC'),
         'reason', 'X455 swap all', 'served_by', jsonb_build_array(pg_temp.fx('s1')::text)));
  v := pg_temp.refusal('items', pg_temp.payload(inv, jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 1)), jsonb_build_array(pg_temp.repl('C', 1)),
         jsonb_build_object('payments', pg_temp.cashpay(45))));
  perform pg_temp.check(res->>'exchange_no' is not null and v = 'This bundle has already been fully exchanged',
    'A5 an item of a bundle exchanged whole is refused: ' || v);
  -- the original invoice of an 'items' exchange cannot be cancelled (408's holds)
  inv := pg_temp.fx('inv_x');
  q0 := pg_temp.q('A');
  begin
    perform public.cancel_invoice_recorded(inv, 'X455 changed mind', gen_random_uuid());
    v := 'cancelled';
  exception when others then v := sqlerrm;
  end;
  perform pg_temp.check(v like '%EXC-%refused. Ask the Owner how to undo the exchange.' and pg_temp.q('A') = q0
      and (select status::text from invoices where id = inv) = 'paid',
    'A6 the original invoice of a several-item exchange cannot be cancelled: ' || v);
end $$;

-- ═════ K The old kinds; an instalment; nothing refused at commit ═════
do $$
declare inv uuid; res jsonb; ei uuid;
begin
  inv := pg_temp.sale(jsonb_build_array(pg_temp.bu('AB')), 150);
  res := pg_temp.exchange('bundle_component', jsonb_build_object('original_invoice_id', inv, 'processing_store_id', pg_temp.fx('st'),
         'original_invoice_item_id', pg_temp.line(inv, 'AB'), 'component_product_id', pg_temp.fx('A'), 'component_qty', 1,
         'replacement', jsonb_build_array(pg_temp.repl('C', 1)), 'payments', pg_temp.cashpay(45),
         'reason', 'X455 size', 'served_by', jsonb_build_array(pg_temp.fx('s1')::text)));
  perform pg_temp.check(res->>'exchange_no' like 'EXC-%' and (select returned_credit_total from product_exchanges where id = (res->>'id')::uuid) = 75
      and pg_temp.exinv((res->>'id')::uuid) is not null,
    'K1 the old bundle_component kind still works');
  -- an instalment label on an 'items' top-up
  inv := pg_temp.sale(jsonb_build_array(pg_temp.bu('AB')), 150);
  perform pg_temp.as_user(pg_temp.fx('s1'));
  res := public.create_exchange_with_details('items', pg_temp.payload(inv,
    jsonb_build_array(pg_temp.r_item(inv, 'AB', 'A', 1), pg_temp.r_item(inv, 'AB', 'B', 1)), jsonb_build_array(pg_temp.repl('F', 1)),
    jsonb_build_object('payments', jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('card'), 'amount', 850)),
                       'instalment', jsonb_build_object('method_id', pg_temp.fx('card'), 'months', 6))));
  set constraints public.exchange_creates_invoice deferred;
  perform pg_temp.as_user(null, pg_temp.fx('own'));
  ei := pg_temp.exinv((res->>'id')::uuid);
  perform pg_temp.check((select instalment_category || '/' || instalment_months || '/' || (instalment_method_id = pg_temp.fx('card')) || '/' || status::text || '/' || total_amount
                           from invoices where id = ei) = 'in_house/6/true/paid/850.00'
      and (res->>'exchange_invoice_id')::uuid = ei,
    'K2 an instalment on an ''items'' top-up is recorded on its replacement invoice (card, 6 months, S$850 paid)');
  perform pg_temp.commit_checks();
  perform pg_temp.check(true, 'K3 nothing above is refused at commit (408''s stock check)');
end $$;

-- ═════ M 455 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m455 m left join pg_temp.fn_md5s() f on f.fn = m.fn where f.fn is null or f.md5 <> m.md5)
    and (select count(*) from pg_temp.fn_md5s()) = (select count(*) from m455),
  'M1 running 455 a second time changed no function');
select pg_temp.check((select coalesce(array_agg(m.fn order by m.fn), '{}') from m455 m left join b455 b on b.fn = m.fn
                       where b.fn is null or b.md5 <> m.md5)
                     = array['create_exchange_with_details(text,jsonb)', 'create_items_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text)',
                             'exchange_invoice_details(uuid)']
    and (select count(*) from m455) = (select count(*) from b455) + 1
    and not exists (select 1 from b455 b left join m455 m on m.fn = b.fn where m.fn is null),
  'M2 its first run changed create_exchange_with_details and exchange_invoice_details and added create_items_exchange (none dropped)');
select pg_temp.check((select before = after1 from r455),
  'M3 455''s self-test left no row (every table of public and auth counts the same before and after it)');
\endif

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 455 checks passed.';
end $$;
rollback;
