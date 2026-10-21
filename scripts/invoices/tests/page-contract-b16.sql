-- B16: what the Invoices page sends, and what it reads back, checked against
-- the database it runs on (416, live 16 Oct 2026) and 417, which ships with
-- this page. The page itself is checked in page-checks-416.test.mjs and the
-- browser harnesses; this checks it calls each function as the function
-- expects and says the server's own words first.
--
--   1. A request id per New Invoice form (416 rule 5, CREATE-15): the header
--      the page sends, sent twice, makes one invoice.
--   2. The correction summary sent the corrected lines (416 rule 11,
--      CREATE-M1) returns the outcome keys the page shows (total, status,
--      owing, refund due, the lines) and a 'total' entry; without lines, no
--      outcome, as before.
--   3. The page's own sentences are the server's: 2 decimal places, a date
--      after today, a date cleared.
--   4. delete_invoice(p_invoice_id, p_reason) (417, Q4 = A): a reason is
--      required, a completed FOC is refused, a draft or unpaid invoice is
--      deleted with the reason kept; the one-argument version is gone.
--   5. invoice_request_status (417, AFTER-14): what the banner reads, for
--      staff of the store only.
--   6. remove_line_foc takes the optional reason (CREATE-19 f), and
--      invoice_financial_position carries the figures the copies print
--      (AFTER-10).
--
-- Run on a copy of production's schema with 417 installed first in the same
-- transaction (psql -v mig=supabase/417_refund_cancel_requests_and_rental_returns.sql),
-- or on a copy that has it. Disposable database only; everything is rolled
-- back. Every name, phone and amount is invented (@tests.invalid).
\set ON_ERROR_STOP on
begin;
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
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.as_user(key text) returns void language plpgsql as
$$begin
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(key), 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', pg_temp.fx(key)::text, true);
end$$;
-- Runs p_sql; the refusal's message, or null when it went through.
create function pg_temp.refusal(p_sql text) returns text language plpgsql as
$$begin
  execute p_sql;
  return null;
exception when others then return sqlstate || ' ' || sqlerrm;
end$$;
-- The header the page sends (handleCreate), less what a test sets itself.
create function pg_temp.page_header(extra jsonb default '{}') returns jsonb language sql as
$$ select jsonb_build_object('customer_id', pg_temp.fx('c'), 'store_id', pg_temp.fx('A'), 'notes', null,
     'preserve_issued_recipients', false, 'manual_discount', 0, 'discount_voucher_id', null,
     'service_staff', '[]'::jsonb, 'business_date', public.sg_today()::text,
     'instalment_category', null, 'instalment_method_id', null, 'instalment_months', null,
     'manual_discount_reason', null, 'payment_methods', '[]'::jsonb, 'payment_corrections', '[]'::jsonb,
     'payment_removals', '[]'::jsonb) || extra $$;
create function pg_temp.line(qty int, extra jsonb default '{}') returns jsonb language sql as
$$ select jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('socks'), 'quantity', qty) || extra) $$;

do $$
declare o uuid := gen_random_uuid(); sa uuid := gen_random_uuid(); sb uuid := gen_random_uuid(); sfx text := left(md5(random()::text), 6);
  st_a uuid; st_b uuid; c uuid; p uuid; pm uuid;
begin
  insert into auth.users(id, email) values (o, 'b16-o-'||sfx||'@tests.invalid'), (sa, 'b16-sa-'||sfx||'@tests.invalid'),
    (sb, 'b16-sb-'||sfx||'@tests.invalid');
  insert into profiles(id, full_name, email, role, is_active) values (o, 'B16 Owner', 'b16-o-'||sfx||'@tests.invalid', 'owner', true),
    (sa, 'B16 Staff A', 'b16-sa-'||sfx||'@tests.invalid', 'staff', true), (sb, 'B16 Staff B', 'b16-sb-'||sfx||'@tests.invalid', 'staff', true);
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into stores(name, code, country_code) values ('B16 Store A', 'B16A'||sfx, 'SG') returning id into st_a;
  insert into stores(name, code, country_code) values ('B16 Store B', 'B16B'||sfx, 'SG') returning id into st_b;
  insert into user_store_assignments(user_id, store_id) values (sa, st_a), (sb, st_b);
  insert into customers(full_name, phone) values ('B16 Buyer', '+61491576398') returning id into c;
  insert into products(name, sku, product_type) values ('B16 Socks', 'B16S-'||sfx, 'own') returning id into p;
  insert into store_inventory(store_id, product_id, current_qty) values (st_a, p, 100);
  perform set_product_prices(st_a, p, 100, 100, 'available');
  insert into payment_methods(name, is_active) values ('B16 Cash '||sfx, true) returning id into pm;
  if not exists (select 1 from app_settings) then insert into app_settings(id) values (true); end if;
  insert into fx values ('o', o), ('sa', sa), ('sb', sb), ('A', st_a), ('B', st_b), ('c', c), ('socks', p), ('cash', pm),
    ('rid', gen_random_uuid());
end $$;

-- ===== 1. One invoice for one New Invoice form (CREATE-15) =====
do $$
declare first uuid; again uuid;
begin
  perform pg_temp.as_user('sa');
  first := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c'), pg_temp.line(1),
    pg_temp.page_header(jsonb_build_object('request_id', pg_temp.fx('rid'))));
  again := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c'), pg_temp.line(1),
    pg_temp.page_header(jsonb_build_object('request_id', pg_temp.fx('rid'))));
  perform pg_temp.check(first = again and (select count(*) from invoices where create_request_id = pg_temp.fx('rid')) = 1,
    '1 the header the page sends, with its request id, sent twice makes one invoice');
  insert into fx values ('unpaid', first);
end $$;

-- ===== 2. The correction summary with the corrected lines (CREATE-M1) =====
do $$
declare inv uuid; line uuid; pv jsonb; o jsonb;
begin
  perform pg_temp.as_user('o');
  inv := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c'), pg_temp.line(1), pg_temp.page_header());
  perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 100)));
  select id into line from invoice_items where invoice_id = inv;
  insert into fx values ('paid', inv), ('paid_line', line);
  -- Quantity 1 -> 2 on a paid invoice: part paid, S$100 owing.
  pv := public.preview_invoice_correction(inv, pg_temp.page_header(jsonb_build_object('expected_edit_count', 0,
    'items', pg_temp.line(2, jsonb_build_object('invoice_item_id', line, 'unit_price', 100)))));
  o := pv->'outcome';
  perform pg_temp.check((o->>'checked')::boolean is true, '2 the corrected lines were checked: ' || coalesce(o::text, 'no outcome'));
  perform pg_temp.check((o->>'total_before')::numeric = 100 and (o->>'total_after')::numeric = 200
    and o->>'status_before' = 'paid' and o->>'status_after' = 'partially_paid'
    and (o->>'outstanding_after')::numeric = 100 and (o->>'refund_due_after')::numeric = 0,
    '2 the outcome keys the page shows: total, status, owing, refund due: ' || coalesce(o::text, ''));
  perform pg_temp.check(jsonb_typeof(o->'lines') = 'array' and o->'lines'->0->>'change' = 'changed'
    and (o->'lines'->0->>'quantity_before')::int = 1 and (o->'lines'->0->>'quantity_after')::int = 2
    and o->'lines'->0 ? 'label' and o->'lines'->0 ? 'charged_before' and o->'lines'->0 ? 'charged_after',
    '2 and the lines that change, with the keys the page reads');
  perform pg_temp.check(exists (select 1 from jsonb_array_elements(pv->'effects') e where e->>'area' = 'total'),
    '2 a "total" entry, which the page shows as Total and status');
  -- The price lowered to S$50: still paid, S$50 refund due.
  pv := public.preview_invoice_correction(inv, pg_temp.page_header(jsonb_build_object('expected_edit_count', 0,
    'items', pg_temp.line(1, jsonb_build_object('invoice_item_id', line, 'unit_price', 50)))));
  perform pg_temp.check(pv->'outcome'->>'status_after' = 'paid' and (pv->'outcome'->>'refund_due_after')::numeric = 50,
    '2 a lower price shows the refund due: ' || coalesce((pv->'outcome')::text, ''));
  -- Without the lines, as before: no outcome.
  pv := public.preview_invoice_correction(inv, pg_temp.page_header(jsonb_build_object('expected_edit_count', 0)));
  perform pg_temp.check(not (pv ? 'outcome'), '2 without the lines the summary is as before, with no outcome');
  -- Nothing was saved by any of it.
  perform pg_temp.check((select quantity from invoice_items where id = line) = 1
    and (select total_amount from invoices where id = inv) = 100, '2 the summary saves nothing');
end $$;

-- ===== 3. The page's sentences are the server's (CREATE-9, CREATE-11) =====
do $$
declare r text;
begin
  perform pg_temp.as_user('sa');
  r := pg_temp.refusal(format($q$select public.record_invoice_settlement(%L, %L::jsonb, %L)$q$, pg_temp.fx('unpaid'),
    jsonb_build_object('receipts', jsonb_build_array(jsonb_build_object('key', 'line-0', 'payment_method_id', pg_temp.fx('cash'),
      'amount', 99.995, 'payment_date', public.sg_today()::text)), 'arrangements', '[]'::jsonb), gen_random_uuid()));
  perform pg_temp.check(r like '%Payment amounts can have at most 2 decimal places.', '3 99.995 is refused in the words the page uses: ' || coalesce(r, 'went through'));
  r := pg_temp.refusal(format($q$select public.create_invoice_with_details(%L, %L, %L::jsonb, %L::jsonb)$q$,
    pg_temp.fx('A'), pg_temp.fx('c'), pg_temp.line(1), pg_temp.page_header(jsonb_build_object('business_date', (public.sg_today() + 1)::text))));
  perform pg_temp.check(r like '%The invoice date cannot be after today.', '3 tomorrow is refused in the words the page uses: ' || coalesce(r, 'went through'));
  perform pg_temp.as_user('o');
  r := pg_temp.refusal(format($q$select public.correct_invoice(%L, %L::jsonb, %L::jsonb, 'Clear the date', %L)$q$,
    pg_temp.fx('paid'), pg_temp.line(1, jsonb_build_object('invoice_item_id', pg_temp.fx('paid_line'), 'unit_price', 100)),
    pg_temp.page_header(jsonb_build_object('business_date', null, 'expected_edit_count', 0)), gen_random_uuid()));
  perform pg_temp.check(r like '%Keep the invoice date; it cannot be cleared.', '3 a cleared date is refused in the words the page uses: ' || coalesce(r, 'went through'));
end $$;

-- ===== 4. Delete with a reason (417, CREATE-14) =====
do $$
declare r text; foc uuid; line uuid;
begin
  perform pg_temp.check(to_regprocedure('public.delete_invoice(uuid)') is null
    and to_regprocedure('public.delete_invoice(uuid,text)') is not null
    and (select array_agg(n order by n) from unnest((select proargnames from pg_proc where oid = 'public.delete_invoice(uuid,text)'::regprocedure)) n)
        = array['p_invoice_id', 'p_reason'],
    '4 delete_invoice takes the two named arguments the page sends; the one-argument version is gone');
  perform pg_temp.as_user('sa');
  r := pg_temp.refusal(format($q$select public.delete_invoice(p_invoice_id => %L)$q$, pg_temp.fx('unpaid')));
  perform pg_temp.check(r like '%Give a short reason for deleting this invoice.%', '4 no reason, no delete: ' || coalesce(r, 'deleted'));
  -- A completed FOC is refused, naming it; the page offers no bin there.
  perform pg_temp.as_user('o');
  foc := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c'), pg_temp.line(1), pg_temp.page_header());
  select id into line from invoice_items where invoice_id = foc;
  perform public.apply_line_foc(line, 1, null, 'B16 fixture gift');
  perform public.confirm_foc_invoice(foc, null);
  perform pg_temp.as_user('sa');
  r := pg_temp.refusal(format($q$select public.delete_invoice(p_invoice_id => %L, p_reason => 'Made by mistake')$q$, foc));
  perform pg_temp.check(r like '%a completed FOC invoice%', '4 a completed FOC invoice is refused, by name: ' || coalesce(r, 'deleted'));
  r := pg_temp.refusal(format($q$select public.delete_invoice(p_invoice_id => %L, p_reason => 'Made twice by mistake')$q$, pg_temp.fx('unpaid')));
  perform pg_temp.check(r is null and (select deleted_at is not null from invoices where id = pg_temp.fx('unpaid')),
    '4 an unpaid invoice is deleted with the reason given: ' || coalesce(r, 'deleted'));
  perform pg_temp.check(exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('unpaid') and a.action = 'invoice_deleted'
      and a.reason = 'Made twice by mistake'), '4 and the reason is kept in the history');
  insert into fx values ('foc', foc);
end $$;

-- ===== 5. The request on an invoice, as the banner reads it (417, AFTER-14) =====
do $$
declare s jsonb; r text;
begin
  perform pg_temp.as_user('sa');
  s := public.invoice_request_status(pg_temp.fx('paid'));
  perform pg_temp.check(s->>'invoice_id' = pg_temp.fx('paid')::text and (s->>'pending')::boolean is false and s->'request' = 'null'::jsonb,
    '5 no request: the banner has nothing to say: ' || coalesce(s::text, ''));
  perform pg_temp.as_user('sb');
  r := pg_temp.refusal(format($q$select public.invoice_request_status(%L)$q$, pg_temp.fx('paid')));
  perform pg_temp.check(r like '42501%', '5 staff of another store are refused: ' || coalesce(r, 'answered'));
end $$;

-- ===== 6. Remove FOC with a reason; the copies' figures (CREATE-19, AFTER-10) =====
do $$
declare inv uuid; line uuid; f jsonb; r text;
begin
  perform pg_temp.as_user('sa');
  inv := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c'), pg_temp.line(2), pg_temp.page_header());
  select id into line from invoice_items where invoice_id = inv;
  perform public.apply_line_foc(line, 1, null, 'B16 fixture gift');
  r := pg_temp.refusal(format($q$select public.remove_line_foc(p_invoice_item_id => %L, p_reason => 'Charged after all')$q$, line));
  perform pg_temp.check(r is null and (select coalesce(foc_quantity, 0) from invoice_items where id = line) = 0,
    '6 Remove FOC takes the optional reason the page sends: ' || coalesce(r, 'removed'));
  f := public.invoice_financial_position(pg_temp.fx('paid'));
  perform pg_temp.check(f ? 'refunded' and f ? 'net_received' and f ? 'refund_due' and f ? 'outstanding'
    and (f->>'net_received')::numeric = 100, '6 the financial position carries what the copies print: ' || f::text);
end $$;

do $$
declare n int;
begin
  select count(*) into n from failed;
  if n > 0 then raise exception 'page-contract-b16: % check(s) failed: %', n, (select string_agg(msg, ' | ' order by n) from failed); end if;
  raise notice 'page-contract-b16: all checks passed';
end $$;
rollback;
