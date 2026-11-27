-- A manual discount is never negative (516).
--
-- New Invoice, called as a real signed-in Staff login (the authenticated role,
-- row rules on) as the page calls it, refuses a negative manual discount and
-- saves nothing; zero and a positive discount with its reason work as before.
-- Edit Invoice still refuses a negative discount and still saves an invoice
-- made this way. The check on invoices stops any other route from writing one.
--
--   sh scripts/invoices/local-sql.sh -f scripts/invoices/tests/manual-discount-not-negative-516.sql
-- 516 is installed here when it is not in yet. Disposable local database only;
-- everything is rolled back. Made-up records only (L516, @example.invalid).
\set ON_ERROR_STOP on
begin;
-- 540 (security audit of 17 Nov 2026, M13: "Stock only") changed functions this file pins; it
-- changes nothing an Owner, a Manager or Staff are answered. Where it is in, its UNDO goes first
-- (this run only, rolled back with everything here).
select to_regprocedure('public.inventory_manager_guard(text)') is not null as t540_in \gset
\if :t540_in
-- 546 (security audit of 17 Nov 2026, L15): where it is in, its UNDO goes first of all.
select coalesce('search_path=public, pg_temp' = any (proconfig), false) as t546_in
  from pg_proc where oid = 'public.current_user_role()'::regprocedure \gset
\if :t546_in
select set_config('energia.undo546_skip_body_check', 'on', true) \g /dev/null
\ir ../../permissions/undo-546.sql
\endif
-- 541, 542 (security audit of 17 Nov 2026, Lows): where they are in, their UNDOs go first, as 540's needs.
select to_regprocedure('public.invoice_line_holds_stock(uuid,uuid)') is not null as t542_in,
       position('541 (security audit' in pg_get_functiondef('public.record_document_send(text,text,text,uuid,uuid,text,text,text,text)'::regprocedure)) > 0 as t541_in \gset
\if :t542_in
\ir ../../invoice-actions/undo-542.sql
\endif
\if :t541_in
\ir ../../permissions/undo-541.sql
\endif
\ir ../../customers/undo-540.sql
\endif
select position('516:' in pg_get_functiondef('public.create_invoice_with_details(uuid,uuid,jsonb,jsonb)'::regprocedure)) > 0 as m516_in \gset
\if :m516_in
\else
\ir ../../../supabase/516_a_manual_discount_is_never_negative.sql
\endif
-- A second run changes nothing, while New Invoice's function is as 516 left it. 518 (18 Nov
-- 2026) changes it again, and 516 then rightly refuses to run again.
select md5(pg_get_functiondef('public.create_invoice_with_details(uuid,uuid,jsonb,jsonb)'::regprocedure))
       = '7c37ac1d841d2c0c2a9cf9b54c563ead' as m516_rerun \gset
\if :m516_rerun
\ir ../../../supabase/516_a_manual_discount_is_never_negative.sql
\endif

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;
create temp table l516(k text primary key, id uuid not null);
create temp table l516t(k text primary key, v text);
create function pg_temp.fx(p_k text) returns uuid language sql as $f$ select id from l516 where k = p_k $f$;
create function pg_temp.tx(p_k text) returns text language sql as $f$ select v from l516t where k = p_k $f$;
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
-- New Invoice as the page sends it: one item, today, the given manual discount and reason.
create function pg_temp.new_invoice(p_discount numeric, p_reason text) returns text language sql as
$f$ select format($q$select public.create_invoice_with_details(%L, %L,
     jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', %L, 'quantity', 1)),
     jsonb_build_object('business_date', public.sg_today(), 'manual_discount', %s, 'manual_discount_reason', %L,
                        'request_id', gen_random_uuid()))::text$q$,
     pg_temp.fx('store'), pg_temp.fx('cust'), pg_temp.fx('prod'), p_discount, p_reason) $f$;
-- Edit Invoice as the page sends it: the one line, the given quantity and manual discount.
create function pg_temp.edit_invoice(p_inv uuid, p_qty int, p_discount numeric) returns text language sql as
$f$ select format($q$select null::text from public.correct_invoice(%L,
     jsonb_build_array(jsonb_build_object('invoice_item_id', %L, 'kind', 'product', 'product_id', %L, 'quantity', %s)),
     jsonb_build_object('manual_discount', %s, 'manual_discount_reason', 'L516 loyal customer'), null, gen_random_uuid())$q$,
     p_inv, (select id from public.invoice_items where invoice_id = p_inv), pg_temp.fx('prod'), p_qty, p_discount) $f$;

do $$
declare own uuid := gen_random_uuid(); stf uuid := gen_random_uuid(); st uuid; prod uuid; cust uuid;
begin
  insert into auth.users(id, email, email_confirmed_at) values
    (own, 'l516-owner@example.invalid', now()), (stf, 'l516-staff@example.invalid', now());
  insert into public.profiles(id, full_name, email, role, is_active) values
    (own, 'L516 Owner', 'l516-owner@example.invalid', 'owner', true),
    (stf, 'L516 Staff', 'l516-staff@example.invalid', 'staff', true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  insert into public.stores(name, code, country_code) values ('L516 Store', 'L516', 'SG') returning id into st;
  insert into public.user_store_assignments(user_id, store_id) values (stf, st);
  insert into public.products(name, sku) values ('L516 Item', 'L516-1') returning id into prod;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, prod, 10);
  perform public.set_product_prices(st, prod, 50, 50, 'available');
  insert into public.customers(full_name, phone) values ('L516 Customer', '+61491570516') returning id into cust;
  insert into l516 values ('owner', own), ('staff', stf), ('store', st), ('prod', prod), ('cust', cust);
end $$;

-- 1. New Invoice
select pg_temp.check(v = 'ERR 22023 The manual discount cannot be negative.', '1a a negative manual discount is refused: ' || v)
  from pg_temp.as_login('staff', pg_temp.new_invoice(-30, 'L516 trying')) v;
select pg_temp.check(not exists (select 1 from public.invoices where customer_id = pg_temp.fx('cust')), '1b and nothing was saved');
insert into l516t select 'zero', pg_temp.as_login('staff', pg_temp.new_invoice(0, null));
select pg_temp.check(pg_temp.tx('zero') ~ '^[0-9a-f-]{36}$'
                     and (select coalesce(manual_discount, 0) from public.invoices where id = pg_temp.tx('zero')::uuid) = 0,
  '1c no manual discount is saved as before: ' || pg_temp.tx('zero'));
select pg_temp.check(v like 'ERR % MANUAL_DISCOUNT_REASON_REQUIRED%', '1d a discount with no reason is still refused: ' || v)
  from pg_temp.as_login('staff', pg_temp.new_invoice(10, null)) v;
insert into l516t select 'ten', pg_temp.as_login('staff', pg_temp.new_invoice(10, 'L516 loyal customer'));
select pg_temp.check(pg_temp.tx('ten') ~ '^[0-9a-f-]{36}$'
                     and (select manual_discount from public.invoices where id = pg_temp.tx('ten')::uuid) = 10,
  '1e a discount of 10 with its reason is saved as before: ' || pg_temp.tx('ten'));

-- 2. Edit Invoice
select pg_temp.check(v like 'ERR % Discount cannot be negative%'
                     and (select manual_discount from public.invoices where id = pg_temp.tx('ten')::uuid) = 10,
  '2a Edit Invoice still refuses a negative discount: ' || v)
  from pg_temp.as_login('staff', pg_temp.edit_invoice(pg_temp.tx('ten')::uuid, 1, -5)) v;
insert into l516t select 'edit', pg_temp.as_login('staff', pg_temp.edit_invoice(pg_temp.tx('ten')::uuid, 2, 10));
select pg_temp.check(pg_temp.tx('edit') = 'ok'
                     and (select quantity from public.invoice_items where invoice_id = pg_temp.tx('ten')::uuid) = 2,
  '2b and saves the invoice''s other changes: ' || pg_temp.tx('edit'));

-- 3. The check on invoices: no route writes a negative manual discount
do $$
declare v text;
begin
  begin
    update public.invoices set manual_discount = -5 where id = pg_temp.tx('zero')::uuid;
    v := 'accepted';
  exception when check_violation then v := sqlerrm; end;
  perform pg_temp.check(v like '%invoices_manual_discount_not_negative%', '3a the database itself refuses a negative manual discount: ' || v);
end $$;
select pg_temp.check((select convalidated and pg_get_constraintdef(oid) = 'CHECK ((manual_discount >= (0)::numeric))'
                        from pg_constraint where conrelid = 'public.invoices'::regclass and conname = 'invoices_manual_discount_not_negative'),
  '3b the check is on invoices and holds for every invoice there');

-- 4. The functions
-- (or 518's, 18 Nov 2026: it also refuses a manual discount that is not a number; correct_invoice
-- unchanged by 516, or 528's, 19 Nov 2026: only an Owner or Manager changes the affiliate)
select pg_temp.check(md5(pg_get_functiondef('public.create_invoice_with_details(uuid,uuid,jsonb,jsonb)'::regprocedure)) in ('7c37ac1d841d2c0c2a9cf9b54c563ead', '0d60261bf337a1716dab9307b2f52fea')
                     and md5(pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure)) in ('cea93a5dd73d429f6437f4c9a8fcaa52', 'aaf592490eb5d13ca2ccb0544f48f647')
                     and has_function_privilege('authenticated', 'public.create_invoice_with_details(uuid,uuid,jsonb,jsonb)', 'execute')
                     and not has_function_privilege('anon', 'public.create_invoice_with_details(uuid,uuid,jsonb,jsonb)', 'execute'),
  '4a New Invoice''s function is 516''s, Edit Invoice''s is unchanged, the rights as before');
rollback;
