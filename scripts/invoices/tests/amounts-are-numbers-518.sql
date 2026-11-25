-- An amount is always a number (518).
--
-- "NaN" and "Infinity", sent as text by a crafted request, are refused: as New
-- Invoice's manual discount (a Staff login), as Edit Invoice's (by the check on
-- invoices), as a corrected payment amount (an Owner login) and as a part of a
-- split; nothing is saved. Real numbers work as before. The seven tables'
-- checks refuse such an amount whatever writes it.
--
--   sh scripts/invoices/local-sql.sh -f scripts/invoices/tests/amounts-are-numbers-518.sql
-- 518 is installed here when it is not in yet. Disposable local database only;
-- everything is rolled back. Made-up records only (L518, @example.invalid).
\set ON_ERROR_STOP on
begin;
-- 540 (security audit of 17 Nov 2026, M13: "Stock only") changed functions this file pins; it
-- changes nothing an Owner, a Manager or Staff are answered. Where it is in, its UNDO goes first
-- (this run only, rolled back with everything here).
select to_regprocedure('public.inventory_manager_guard(text)') is not null as t540_in \gset
\if :t540_in
\ir ../../customers/undo-540.sql
\endif
select position('518:' in pg_get_functiondef('public.correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)'::regprocedure)) > 0 as m518_in \gset
\if :m518_in
\else
\ir ../../../supabase/518_an_amount_is_always_a_number.sql
\endif
-- A second run changes nothing. (528, security audit of 17 Nov 2026, M11, changes
-- correct_invoice, which 518 pins as relied on: where 528 is in, 518 rightly refuses to run
-- again, so it is not run again there.)
select position('-- 528 (security audit' in pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure)) > 0 as m518_528_in \gset
\if :m518_528_in
\else
\ir ../../../supabase/518_an_amount_is_always_a_number.sql
\endif

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;
create temp table l518(k text primary key, id uuid not null);
create function pg_temp.fx(p_k text) returns uuid language sql as $f$ select id from l518 where k = p_k $f$;
-- One statement as a signed-in login: its first column as text, or 'ERR <sqlstate> <message>'.
create function pg_temp.as_login(p_who text, q text) returns text language plpgsql as $f$
declare v text; u uuid := pg_temp.fx(p_who);
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute q into v;
  execute 'reset role';
  return coalesce(v, 'ok');
exception when others then return 'ERR ' || sqlstate || ' ' || sqlerrm;
end $f$;
-- Runs one statement as the database itself; 'ok' or 'ERR <sqlstate> <message>'.
create function pg_temp.try(q text) returns text language plpgsql as
$f$ begin execute q; return 'ok'; exception when others then return 'ERR ' || sqlstate || ' ' || sqlerrm; end $f$;
create function pg_temp.new_invoice(p_discount text) returns text language sql as
$f$ select format($q$select public.create_invoice_with_details(%L, %L,
     jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', %L, 'quantity', 1)),
     jsonb_build_object('business_date', public.sg_today(), 'manual_discount', %L, 'manual_discount_reason', 'L518 tried',
                        'request_id', gen_random_uuid()))::text$q$,
     pg_temp.fx('store'), pg_temp.fx('cust'), pg_temp.fx('prod'), p_discount) $f$;
create function pg_temp.state(p_inv text) returns text language sql as
$f$ select coalesce(manual_discount::text, '-') || ' ' || total_amount || ' ' || paid_amount || ' ' || status
     from public.invoices where id = pg_temp.fx(p_inv) $f$;
create function pg_temp.pays(p_inv text) returns text language sql as
$f$ select string_agg(entry_kind || ' ' || amount, ', ' order by created_at, id) from public.invoice_payments where invoice_id = pg_temp.fx(p_inv) $f$;

do $$
declare own uuid := gen_random_uuid(); stf uuid := gen_random_uuid(); st uuid; prod uuid; cust uuid; cust2 uuid; cash uuid; nets uuid;
begin
  insert into auth.users(id, email, email_confirmed_at) values
    (own, 'l518-owner@example.invalid', now()), (stf, 'l518-staff@example.invalid', now());
  insert into public.profiles(id, full_name, email, role, is_active) values
    (own, 'L518 Owner', 'l518-owner@example.invalid', 'owner', true),
    (stf, 'L518 Staff', 'l518-staff@example.invalid', 'staff', true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  insert into public.stores(name, code, country_code) values ('L518 Store', 'L518', 'SG') returning id into st;
  insert into public.user_store_assignments(user_id, store_id) values (stf, st);
  insert into public.products(name, sku) values ('L518 Item', 'L518-1') returning id into prod;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, prod, 10);
  perform public.set_product_prices(st, prod, 50, 50, 'available');
  insert into public.customers(full_name, phone) values ('L518 Customer', '+61491570518') returning id into cust;
  insert into public.customers(full_name, phone) values ('L518 Other', '+61491570519') returning id into cust2;
  insert into public.payment_methods(name) values ('L518 Cash') returning id into cash;
  insert into public.payment_methods(name) values ('L518 NETS') returning id into nets;
  insert into l518 values ('owner', own), ('staff', stf), ('store', st), ('prod', prod), ('cust', cust), ('cash', cash), ('nets', nets);
  -- S$50 invoices for the corrections: one part paid (S$20), one paid in full, one not paid.
  insert into l518 values ('part', public.create_invoice(st, cust2, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', prod, 'quantity', 1))));
  perform public.pay_invoice(pg_temp.fx('part'), jsonb_build_array(jsonb_build_object('payment_method_id', cash, 'amount', 20)));
  insert into l518 values ('full', public.create_invoice(st, cust2, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', prod, 'quantity', 1))));
  perform public.pay_invoice(pg_temp.fx('full'), jsonb_build_array(jsonb_build_object('payment_method_id', cash, 'amount', 50)));
  insert into l518 values ('unpaid', public.create_invoice(st, cust2, null, jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', prod, 'quantity', 1))));
  insert into l518 select 'part_pay', id from public.invoice_payments where invoice_id = pg_temp.fx('part');
  insert into l518 select 'full_pay', id from public.invoice_payments where invoice_id = pg_temp.fx('full');
end $$;

-- 1. New Invoice (Staff)
select pg_temp.check(v = 'ERR 22023 The manual discount must be an amount in dollars and cents.', '1a "NaN" as the manual discount is refused: ' || v)
  from pg_temp.as_login('staff', pg_temp.new_invoice('NaN')) v;
select pg_temp.check(v = 'ERR 22023 The manual discount must be an amount in dollars and cents.', '1b and "Infinity": ' || v)
  from pg_temp.as_login('staff', pg_temp.new_invoice('Infinity')) v;
select pg_temp.check(not exists (select 1 from public.invoices where customer_id = pg_temp.fx('cust')), '1c and nothing was saved');
select pg_temp.check(v ~ '^[0-9a-f-]{36}$', '1d a discount of 10 with its reason is saved as before: ' || v)
  from pg_temp.as_login('staff', pg_temp.new_invoice('10')) v;

-- 2. Edit Invoice (Staff): the check on invoices refuses it, and nothing changes
select pg_temp.check(v like 'ERR 23514 %invoices_amounts_are_numbers%' and pg_temp.state('unpaid') = '0.00 50.00 0.00 unpaid',
  '2a "NaN" as the manual discount on Edit Invoice is refused, the invoice as it was: ' || v || ' / ' || pg_temp.state('unpaid'))
  from pg_temp.as_login('staff', format($q$select null::text from public.correct_invoice(%L,
         jsonb_build_array(jsonb_build_object('invoice_item_id', %L, 'kind', 'product', 'product_id', %L, 'quantity', 1)),
         jsonb_build_object('manual_discount', 'NaN', 'manual_discount_reason', 'L518 tried'), null, gen_random_uuid())$q$,
         pg_temp.fx('unpaid'), (select id from public.invoice_items where invoice_id = pg_temp.fx('unpaid')), pg_temp.fx('prod'))) v;

-- 3. Correct payment (Owner), on the part-paid invoice
select pg_temp.check(v = 'ERR 22023 The corrected amount must be an amount in dollars and cents.', '3a "NaN" as a corrected amount is refused: ' || v)
  from pg_temp.as_login('owner', format($q$select public.correct_invoice_payment(%L, 'NaN', public.sg_today(), %L, 'L518 tried', gen_random_uuid())::text$q$,
                                       pg_temp.fx('part_pay'), pg_temp.fx('cash'))) v;
select pg_temp.check(v = 'ERR 22023 The corrected amount must be an amount in dollars and cents.', '3b and "Infinity": ' || v)
  from pg_temp.as_login('owner', format($q$select public.correct_invoice_payment(%L, 'Infinity', public.sg_today(), %L, 'L518 tried', gen_random_uuid())::text$q$,
                                       pg_temp.fx('part_pay'), pg_temp.fx('cash'))) v;
select pg_temp.check(pg_temp.state('part') = '0.00 50.00 20.00 partially_paid' and pg_temp.pays('part') = 'receipt 20.00',
  '3c the invoice and its payment are as they were: ' || pg_temp.state('part') || ' / ' || pg_temp.pays('part'));
select pg_temp.check(v not like 'ERR%' and pg_temp.state('part') = '0.00 50.00 25.00 partially_paid',
  '3d a real correction (20 to 25) works as before: ' || pg_temp.state('part'))
  from pg_temp.as_login('owner', format($q$select public.correct_invoice_payment(%L, 25, public.sg_today(), %L, 'L518 miscounted', gen_random_uuid())::text$q$,
                                       pg_temp.fx('part_pay'), pg_temp.fx('cash'))) v;

-- 4. A split, as Edit Invoice calls it (the invoice locked)
create temp table l518t(k text primary key, v text);
do $$ begin
  perform 1 from public.invoices where id = pg_temp.fx('full') for update;
  insert into l518t values ('split', pg_temp.try(format($q$select public.split_invoice_payment(%L, %L::jsonb, 'L518 tried', gen_random_uuid())$q$,
    pg_temp.fx('full_pay'), jsonb_build_array(
      jsonb_build_object('amount', 'NaN', 'date', public.sg_today(), 'payment_method_id', pg_temp.fx('cash')),
      jsonb_build_object('amount', 50, 'date', public.sg_today(), 'payment_method_id', pg_temp.fx('nets'))))));
end $$;
select pg_temp.check((select v from l518t where k = 'split') = 'ERR 22023 Each part of a split needs an amount in dollars and cents'
                     and pg_temp.pays('full') = 'receipt 50.00',
  '4a a split with a "NaN" part is refused, the payment as it was: ' || (select v from l518t where k = 'split'));

-- 5. The checks refuse such an amount whatever writes it
-- (Infinity cannot be stored in these columns at all: they have a precision, and
-- PostgreSQL answers "numeric field overflow". NaN can, and the checks refuse it.)
select pg_temp.check((a like 'ERR 23514 %invoices_amounts_are_numbers%' or (x.val <> 'NaN' and a like 'ERR 22003 %'))
                     and (b like 'ERR 23514 %invoice_items_amounts_are_numbers%' or (x.val <> 'NaN' and b like 'ERR 22003 %')),
  '5a the database itself refuses ' || x.val || ' on an invoice and its lines: ' || a || ' / ' || b)
  from (values ('NaN'), ('Infinity'), ('-Infinity')) x(val),
       lateral pg_temp.try(format('update public.invoices set paid_amount = %L where id = %L', x.val, pg_temp.fx('unpaid'))) a,
       lateral pg_temp.try(format('update public.invoice_items set unit_price = %L where invoice_id = %L', x.val, pg_temp.fx('unpaid'))) b;
-- A payment row is locked once saved, so a new one: NaN passes the older amount > 0
-- check, and the new one refuses it.
select pg_temp.check(v like 'ERR 23514 %invoice_payments_amounts_are_numbers%'
                     or (x.val <> 'NaN' and v like 'ERR 22003 %'),
  '5b the database itself refuses a payment of ' || x.val || ': ' || v)
  from (values ('NaN'), ('Infinity'), ('-Infinity')) x(val),
       lateral pg_temp.try(format('insert into public.invoice_payments(invoice_id, payment_method_id, amount, received_by) values (%L, %L, %L, %L)',
                                  pg_temp.fx('unpaid'), pg_temp.fx('cash'), x.val, pg_temp.fx('owner'))) v;
select pg_temp.check(bool_and(c.convalidated
                              and (select bool_and(strpos(pg_get_constraintdef(c.oid), quote_ident(col) || ')::text') > 0
                                                    or strpos(pg_get_constraintdef(c.oid), '(' || quote_ident(col) || ')::text') > 0)
                                     from information_schema.columns ic, lateral (select ic.column_name::text col) z
                                    where ic.table_schema = 'public' and ic.table_name = c.conrelid::regclass::text and ic.data_type = 'numeric'))
                     and count(*) = 7,
  '5c seven checks, validated, each naming every amount in its table')
  from pg_constraint c where c.conname like '%\_amounts\_are\_numbers' and c.connamespace = 'public'::regnamespace
   -- 518's seven tables (519, 18 Nov 2026, adds the same check to sixteen others)
   and c.conrelid::regclass::text = any (array['invoices', 'invoice_items', 'invoice_payments', 'invoice_refunds',
                                              'invoice_line_credit_allocations', 'customer_credit_lots', 'commissions']);

-- 6. The functions
-- (correct_invoice: or 528's, which adds who may change the affiliate. correct_invoice_payment and
-- split_invoice_payment: or 533's, which add the S$1,000 limit for a Manager.)
select pg_temp.check(md5(pg_get_functiondef(to_regprocedure('public.' || x.f))) = any (x.m), '6a ' || x.f || ' is as tested')
  from (values ('create_invoice_with_details(uuid,uuid,jsonb,jsonb)', array['0d60261bf337a1716dab9307b2f52fea']),
               ('correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)', array['088e2130d62a1dc4af8cd9417465c0b6', '5ac4a3ac99f5e5cbda370fcd8c9f9cd0']),
               ('split_invoice_payment(uuid,jsonb,text,uuid)', array['236b86da67f77eb036592e1ce12ec366', 'f66d4ba00406e50171afcf6b4b79c969']),
               ('correct_invoice(uuid,jsonb,jsonb,text,uuid)', array['cea93a5dd73d429f6437f4c9a8fcaa52', 'aaf592490eb5d13ca2ccb0544f48f647'])) x(f, m);
rollback;
