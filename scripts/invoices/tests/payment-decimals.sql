-- Payments are in cents and never dated after today (416: INVOICES-CREATE-9,
-- INVOICES-AFTER-16).
--
--   D1 A payment of 99.995 on a S$100.00 invoice is refused by Record Payment
--      (record_invoice_settlement, as the page sends it), by
--      record_invoice_payment and by invoice_record_payments_internal; the
--      invoice is left unpaid with no payment row.
--   D2 99.99 and then 0.01 settle it.
--   D3 Correct amount / date: an amount with 3 decimal places and a date
--      after today are refused; today is accepted.
--   D4 Split: a part dated after today and a part with 3 decimal places are
--      refused; a split dated today is accepted.
--   D5 Correct Invoice's payment corrections reach the same rules: a
--      payment, or a split part, dated tomorrow is refused and nothing is
--      saved.
--   D6 The correction summary says so before the save.
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
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlerrm; end$$;
-- An unpaid S$100.00 invoice at the test store, by the Owner.
create function pg_temp.sale() returns uuid language sql as
$$ select public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c'),
     jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('socks'),'quantity',1)),
     jsonb_build_object('business_date', public.sg_today()::text)) $$;
create function pg_temp.pay(inv uuid, amount numeric) returns text language sql as
$$ select pg_temp.err(format('select public.record_invoice_payment(%L, %L, %L)', inv,
     jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', amount)), gen_random_uuid())) $$;
create function pg_temp.untouched(inv uuid) returns boolean language sql as
$$ select (select (status, paid_amount) = ('unpaid'::invoice_status, 0::numeric) from public.invoices where id = inv)
      and not exists (select 1 from public.invoice_payments where invoice_id = inv) $$;

do $$
declare o uuid := gen_random_uuid(); sfx text := left(md5(random()::text), 6); st uuid; c uuid; p uuid; v uuid;
begin
  insert into auth.users(id,email) values (o,'pd416-'||sfx||'@tests.invalid');
  insert into profiles(id,full_name,email,role) values (o,'PD Owner','pd416-'||sfx||'@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into stores(name,code,country_code) values ('PD Store','PD'||sfx,'SG') returning id into st;
  insert into customers(full_name,phone) values ('PD Buyer','+61491577426') returning id into c;
  insert into products(name,sku,product_type) values ('PD Socks','PDS-'||sfx,'own') returning id into p;
  insert into store_inventory(store_id,product_id,current_qty) values (st,p,100);
  perform set_product_prices(st,p,100,100,'available');
  insert into fx values ('o',o),('A',st),('c',c),('socks',p);
  insert into payment_methods(name,is_active) values ('PD Cash '||sfx,true) returning id into v; insert into fx values ('cash',v);
  insert into payment_methods(name,is_active) values ('PD Card '||sfx,true) returning id into v; insert into fx values ('card',v);
end $$;

-- ═════ D1–D2 Recording ═════
do $$
declare inv uuid := pg_temp.sale(); e text; msg text := 'Payment amounts can have at most 2 decimal places.';
begin
  e := pg_temp.err(format('select public.record_invoice_settlement(%L, %L, %L)', inv,
         jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object('key','line-0','payment_method_id',pg_temp.fx('cash'),
           'amount',99.995,'payment_date',public.sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid()));
  perform pg_temp.check(e = msg and pg_temp.untouched(inv), 'D1 Record Payment of 99.995 is refused, nothing recorded: ' || coalesce(e, 'recorded'));
  e := pg_temp.pay(inv, 99.995);
  perform pg_temp.check(e = msg and pg_temp.untouched(inv), 'D1 record_invoice_payment refuses it: ' || coalesce(e, 'recorded'));
  e := pg_temp.err(format('select public.invoice_record_payments_internal(%L, %L)', inv,
         jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 99.995))));
  perform pg_temp.check(e = msg and pg_temp.untouched(inv), 'D1 and invoice_record_payments_internal: ' || coalesce(e, 'recorded'));
  e := pg_temp.pay(inv, 99.99);
  perform pg_temp.check(e is null and (select status from public.invoices where id = inv) = 'partially_paid', 'D2 99.99 is recorded: ' || coalesce(e, 'recorded'));
  e := pg_temp.pay(inv, 0.01);
  perform pg_temp.check(e is null and (select (status, paid_amount) = ('paid'::invoice_status, 100.00::numeric) from public.invoices where id = inv),
    'D2 and 0.01 settles it: ' || coalesce(e, 'recorded'));
end $$;

-- ═════ D3–D4 Correct amount / date, Split ═════
do $$
declare inv uuid := pg_temp.sale(); p uuid; e text; q text := 'select public.correct_invoice_payment(%L, %s, %L, %L, %L, %L)';
  sq text := 'select public.split_invoice_payment(%L, %L, %L, %L)';
begin
  perform pg_temp.pay(inv, 100);
  select id into p from public.invoice_payments where invoice_id = inv;
  e := pg_temp.err(format(q, p, '99.995', public.sg_today(), pg_temp.fx('cash'), 'Keyed wrongly', gen_random_uuid()));
  perform pg_temp.check(e = 'Payment amounts can have at most 2 decimal places.' and (select count(*) from public.invoice_payments where invoice_id = inv) = 1,
    'D3 a corrected amount of 99.995 is refused: ' || coalesce(e, 'saved'));
  e := pg_temp.err(format(q, p, '100', public.sg_today() + 1, pg_temp.fx('cash'), 'Keyed wrongly', gen_random_uuid()));
  perform pg_temp.check(e = 'A payment cannot be dated in the future' and (select count(*) from public.invoice_payments where invoice_id = inv) = 1,
    'D3 a corrected date of tomorrow is refused: ' || coalesce(e, 'saved'));
  e := pg_temp.err(format(sq, p, jsonb_build_array(
         jsonb_build_object('amount', 60, 'payment_method_id', pg_temp.fx('cash'), 'date', public.sg_today()::text),
         jsonb_build_object('amount', 40, 'payment_method_id', pg_temp.fx('card'), 'date', (public.sg_today() + 1)::text)), 'Split', gen_random_uuid()));
  perform pg_temp.check(e = 'A payment cannot be dated in the future' and (select count(*) from public.invoice_payments where invoice_id = inv) = 1,
    'D4 a split with a part dated tomorrow is refused: ' || coalesce(e, 'saved'));
  e := pg_temp.err(format(sq, p, jsonb_build_array(
         jsonb_build_object('amount', 59.995, 'payment_method_id', pg_temp.fx('cash'), 'date', public.sg_today()::text),
         jsonb_build_object('amount', 40.005, 'payment_method_id', pg_temp.fx('card'), 'date', public.sg_today()::text)), 'Split', gen_random_uuid()));
  perform pg_temp.check(e = 'Payment amounts can have at most 2 decimal places.' and (select count(*) from public.invoice_payments where invoice_id = inv) = 1,
    'D4 a split with 3 decimal places is refused: ' || coalesce(e, 'saved'));
  e := pg_temp.err(format(sq, p, jsonb_build_array(
         jsonb_build_object('amount', 60, 'payment_method_id', pg_temp.fx('cash'), 'date', public.sg_today()::text),
         jsonb_build_object('amount', 40, 'payment_method_id', pg_temp.fx('card'), 'date', public.sg_today()::text)), 'Split', gen_random_uuid()));
  perform pg_temp.check(e is null and public.invoice_net_received(inv) = 100, 'D4 a split dated today is accepted: ' || coalesce(e, 'saved'));
  select id into p from public.invoice_payments where invoice_id = inv and entry_kind = 'correction_replacement' and amount = 60;
  e := pg_temp.err(format(q, p, '60', public.sg_today(), pg_temp.fx('card'), 'Was the card', gen_random_uuid()));
  perform pg_temp.check(e is null, 'D3 a correction dated today is accepted: ' || coalesce(e, 'saved'));
end $$;

-- ═════ D5–D6 Through Correct Invoice ═════
do $$
declare inv uuid := pg_temp.sale(); p uuid; e text; r jsonb; items jsonb; n int;
begin
  perform pg_temp.pay(inv, 100);
  select id into p from public.invoice_payments where invoice_id = inv;
  select jsonb_agg(jsonb_build_object('invoice_item_id', id, 'kind', 'product', 'product_id', product_id, 'quantity', quantity, 'unit_price', unit_price))
    into items from public.invoice_items where invoice_id = inv;
  select count(*) into n from public.invoice_payments where invoice_id = inv;
  e := pg_temp.err(format('select public.correct_invoice(%L, %L, %L, %L, %L)', inv, items,
         jsonb_build_object('payment_corrections', jsonb_build_array(jsonb_build_object('payment_id', p, 'amount', 100,
           'date', (public.sg_today() + 1)::text, 'payment_method_id', pg_temp.fx('cash')))), 'Date of the payment', gen_random_uuid()));
  perform pg_temp.check(e = 'A payment cannot be dated in the future'
      and (select count(*) from public.invoice_payments where invoice_id = inv) = n
      and not exists (select 1 from public.invoice_revisions where invoice_id = inv),
    'D5 Correct Invoice with a payment dated tomorrow is refused, nothing saved: ' || coalesce(e, 'saved'));
  e := pg_temp.err(format('select public.correct_invoice(%L, %L, %L, %L, %L)', inv, items,
         jsonb_build_object('payment_corrections', jsonb_build_array(jsonb_build_object('payment_id', p, 'parts', jsonb_build_array(
           jsonb_build_object('amount', 50, 'date', public.sg_today()::text, 'payment_method_id', pg_temp.fx('cash')),
           jsonb_build_object('amount', 50, 'date', (public.sg_today() + 1)::text, 'payment_method_id', pg_temp.fx('card')))))),
         'Split payment', gen_random_uuid()));
  perform pg_temp.check(e = 'A payment cannot be dated in the future' and (select count(*) from public.invoice_payments where invoice_id = inv) = n,
    'D5 and a split part dated tomorrow: ' || coalesce(e, 'saved'));
  r := public.preview_invoice_correction(inv, jsonb_build_object('payment_corrections', jsonb_build_array(jsonb_build_object(
         'payment_id', p, 'amount', 100, 'date', (public.sg_today() + 1)::text, 'payment_method_id', pg_temp.fx('cash')))));
  perform pg_temp.check((r->>'blocking')::boolean and r->'needs_review' @> '[{"area":"payments"}]'
      and exists (select 1 from jsonb_array_elements(r->'needs_review') x where x->>'detail' like '%cannot be dated in the future%'),
    'D6 the summary flags a payment dated tomorrow: ' || (r->'needs_review')::text);
  r := public.preview_invoice_correction(inv, jsonb_build_object('payment_corrections', jsonb_build_array(jsonb_build_object(
         'payment_id', p, 'amount', 99.995, 'date', public.sg_today()::text, 'payment_method_id', pg_temp.fx('cash')))));
  perform pg_temp.check((r->>'blocking')::boolean
      and exists (select 1 from jsonb_array_elements(r->'needs_review') x where x->>'detail' like '%at most 2 decimal places%'),
    'D6 and an amount of 99.995: ' || (r->'needs_review')::text);
  r := public.preview_invoice_correction(inv, jsonb_build_object('payment_corrections', jsonb_build_array(jsonb_build_object(
         'payment_id', p, 'parts', jsonb_build_array(
           jsonb_build_object('amount', 50, 'date', public.sg_today()::text, 'payment_method_id', pg_temp.fx('cash')),
           jsonb_build_object('amount', 50, 'date', (public.sg_today() + 1)::text, 'payment_method_id', pg_temp.fx('card')))))));
  perform pg_temp.check((r->>'blocking')::boolean
      and exists (select 1 from jsonb_array_elements(r->'needs_review') x where x->>'detail' like '%not in the future%'),
    'D6 and a split part dated tomorrow: ' || (r->'needs_review')::text);
end $$;

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All payment decimal and date checks passed.';
end $$;
rollback;
