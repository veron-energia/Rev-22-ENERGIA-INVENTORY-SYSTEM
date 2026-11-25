-- A payment is read again once its invoice is locked (517).
--
-- Correct payment, remove and split each read the payment again, and lock it,
-- after locking its invoice. Here the three still do what they did, with the
-- takings by method right after each: Correct payment as a real signed-in
-- Owner (the authenticated role) as the page calls it, after a method changed
-- in place as Edit Invoice does it; remove and split as Edit Invoice calls
-- them. The race itself (a Correct payment waiting while Edit Invoice changes
-- the method) needs two sessions; it was run on throwaway copies: without 517
-- Cash -10.00 and NETS 50.00, with 517 Cash 40.00 and NETS 0.00.
--
--   sh scripts/invoices/local-sql.sh -f scripts/invoices/tests/payment-read-after-lock-517.sql
-- 517 is installed here when it is not in yet. Disposable local database only;
-- everything is rolled back. Made-up records only (L517, @example.invalid).
\set ON_ERROR_STOP on
begin;
-- 540 (security audit of 17 Nov 2026, M13: "Stock only") changed functions this file pins; it
-- changes nothing an Owner, a Manager or Staff are answered. Where it is in, its UNDO goes first
-- (this run only, rolled back with everything here).
select to_regprocedure('public.inventory_manager_guard(text)') is not null as t540_in \gset
\if :t540_in
\ir ../../customers/undo-540.sql
\endif
select position('517:' in pg_get_functiondef('public.correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)'::regprocedure)) > 0 as m517_in \gset
\if :m517_in
\else
\ir ../../../supabase/517_a_payment_is_read_again_once_its_invoice_is_locked.sql
\endif
-- A second run changes nothing, while the three are as 517 left them. 518 (18 Nov 2026)
-- changes two of them again, and 517 then rightly refuses to run again.
select md5(pg_get_functiondef('public.correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)'::regprocedure))
       = '29c319b8306a39f940ccb3bb240336b6' as m517_rerun \gset
\if :m517_rerun
\ir ../../../supabase/517_a_payment_is_read_again_once_its_invoice_is_locked.sql
\endif

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;
create temp table l517(k text primary key, id uuid not null);
create function pg_temp.fx(p_k text) returns uuid language sql as $f$ select id from l517 where k = p_k $f$;
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
-- What an invoice took, by method: a reversal takes its amount back.
create function pg_temp.takings(p_inv text) returns text language sql as
$f$ select coalesce(string_agg(m.name || ' ' || x.s, ', ' order by m.name), '')
      from (select payment_method_id, sum(case when entry_kind = 'correction_reversal' then -amount else amount end) s
              from public.invoice_payments where invoice_id = pg_temp.fx(p_inv) group by 1) x
      join public.payment_methods m on m.id = x.payment_method_id $f$;
-- The payment that stands on an invoice: not a reversal, and not reversed since.
create function pg_temp.standing(p_inv text) returns uuid language sql as
$f$ select ip.id from public.invoice_payments ip
     where ip.invoice_id = pg_temp.fx(p_inv) and ip.entry_kind <> 'correction_reversal'
       and not exists (select 1 from public.invoice_payments r where r.corrects_payment_id = ip.id and r.entry_kind = 'correction_reversal')
     order by ip.created_at desc, ip.id limit 1 $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; prod uuid; cust uuid; cash uuid; nets uuid; k text;
begin
  insert into auth.users(id, email, email_confirmed_at) values (own, 'l517-owner@example.invalid', now());
  insert into public.profiles(id, full_name, email, role, is_active) values (own, 'L517 Owner', 'l517-owner@example.invalid', 'owner', true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  insert into public.stores(name, code, country_code) values ('L517 Store', 'L517', 'SG') returning id into st;
  insert into public.products(name, sku) values ('L517 Item', 'L517-1') returning id into prod;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, prod, 10);
  perform public.set_product_prices(st, prod, 50, 50, 'available');
  insert into public.customers(full_name, phone) values ('L517 Customer', '+61491570517') returning id into cust;
  insert into public.payment_methods(name) values ('L517 Cash') returning id into cash;
  insert into public.payment_methods(name) values ('L517 NETS') returning id into nets;
  insert into l517 values ('owner', own), ('cash', cash), ('nets', nets);
  -- Three invoices of S$50, each paid in cash.
  foreach k in array array['i1', 'i2', 'i3'] loop
    insert into l517 values (k, public.create_invoice(st, cust, null,
      jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', prod, 'quantity', 1))));
    perform public.pay_invoice(pg_temp.fx(k), jsonb_build_array(jsonb_build_object('payment_method_id', cash, 'amount', 50)));
  end loop;
end $$;
select pg_temp.check(pg_temp.takings('i1') = 'L517 Cash 50.00', '0 each invoice took S$50 in cash: ' || pg_temp.takings('i1'));

-- 1. Correct payment, as the page calls it
select pg_temp.check(v not like 'ERR%' and pg_temp.takings('i1') = 'L517 Cash 40.00',
  '1a an Owner corrects 50 to 40 in cash: ' || pg_temp.takings('i1'))
  from pg_temp.as_login('owner', format($q$select public.correct_invoice_payment(%L, 40, public.sg_today(), %L, 'L517 miscounted', gen_random_uuid())::text$q$,
                                       pg_temp.standing('i1'), pg_temp.fx('cash'))) v;
-- Edit Invoice gives the payment that stands another method, in place, under the invoice lock.
do $$ begin
  perform 1 from public.invoices where id = pg_temp.fx('i1') for update;
  perform public.correct_invoice_payment_methods(pg_temp.fx('i1'),
    jsonb_build_array(jsonb_build_object('payment_id', pg_temp.standing('i1'), 'payment_method_id', pg_temp.fx('nets'))), 'L517 it was NETS');
end $$;
select pg_temp.check(pg_temp.takings('i1') = 'L517 Cash 0.00, L517 NETS 40.00', '1b Edit Invoice moved the 40 to NETS: ' || pg_temp.takings('i1'));
select pg_temp.check(v not like 'ERR%' and pg_temp.takings('i1') = 'L517 Cash 30.00, L517 NETS 0.00',
  '1c correcting it again (40 to 30, in cash) takes the 40 back from NETS, where it now is: ' || pg_temp.takings('i1'))
  from pg_temp.as_login('owner', format($q$select public.correct_invoice_payment(%L, 30, public.sg_today(), %L, 'L517 miscounted again', gen_random_uuid())::text$q$,
                                       pg_temp.standing('i1'), pg_temp.fx('cash'))) v;

-- 2. Remove and split, as Edit Invoice calls them (with the invoice locked)
do $$ begin
  perform 1 from public.invoices where id = pg_temp.fx('i2') for update;
  perform public.remove_invoice_payment(pg_temp.standing('i2'), 'L517 entered twice', gen_random_uuid());
  perform 1 from public.invoices where id = pg_temp.fx('i3') for update;
  perform public.split_invoice_payment(pg_temp.standing('i3'), jsonb_build_array(
    jsonb_build_object('amount', 20, 'date', public.sg_today(), 'payment_method_id', pg_temp.fx('cash')),
    jsonb_build_object('amount', 30, 'date', public.sg_today(), 'payment_method_id', pg_temp.fx('nets'))), 'L517 paid two ways', gen_random_uuid());
end $$;
select pg_temp.check(pg_temp.takings('i2') = 'L517 Cash 0.00', '2a a removed payment takes the cash back: ' || pg_temp.takings('i2'));
select pg_temp.check(pg_temp.takings('i3') = 'L517 Cash 20.00, L517 NETS 30.00', '2b a split payment is 20 in cash and 30 by NETS: ' || pg_temp.takings('i3'));

-- 3. The three read the payment again, and lock it, after the invoice's lock
select pg_temp.check(
    position('517: the payment again' in d) > 0
    and position('for update' in substr(d, position('from public.invoices where id' in d))) > 0
    and strpos(d, 'from public.invoice_payments where id' || x.s || 'p_payment_id for update')
        > strpos(d, 'from public.invoices where id' || x.s || 'p.invoice_id for update'),
  '3a ' || x.f || ' reads and locks the payment after its invoice')
  from (values ('correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)', '='),
               ('remove_invoice_payment(uuid,text,uuid)', ' = '),
               ('split_invoice_payment(uuid,jsonb,text,uuid)', ' = ')) x(f, s),
       lateral (select pg_get_functiondef(to_regprocedure('public.' || x.f)) d) y;
-- (correct_invoice_payment and split_invoice_payment: or 518's, 18 Nov 2026: they also refuse
-- an amount that is not a number; the three payment functions: or 533's, 20 Nov 2026: they add the
-- S$1,000 limit for a Manager)
select pg_temp.check(md5(pg_get_functiondef(to_regprocedure('public.' || x.f))) = any (string_to_array(x.m, '|')), '3b ' || x.f || ' is as tested')
  from (values ('correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)', '29c319b8306a39f940ccb3bb240336b6|088e2130d62a1dc4af8cd9417465c0b6|5ac4a3ac99f5e5cbda370fcd8c9f9cd0'),
               ('remove_invoice_payment(uuid,text,uuid)', '8eb341eb5383430f676940be1de37def|ab2940828dffdd7aff007d036e88820b'),
               ('split_invoice_payment(uuid,jsonb,text,uuid)', '07c1b8191e2802e0ca388ab181ae4886|236b86da67f77eb036592e1ce12ec366|f66d4ba00406e50171afcf6b4b79c969'),
               ('correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'cea93a5dd73d429f6437f4c9a8fcaa52|aaf592490eb5d13ca2ccb0544f48f647'),  -- or 528's (19 Nov 2026)
               ('correct_invoice_payment_methods(uuid,jsonb,text)', '898afdee6c3cf57893ac81654597dff0')) x(f, m);
select pg_temp.check(has_function_privilege('authenticated', 'public.correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)', 'execute')
                     and not has_function_privilege('authenticated', 'public.remove_invoice_payment(uuid,text,uuid)', 'execute')
                     and not has_function_privilege('authenticated', 'public.split_invoice_payment(uuid,jsonb,text,uuid)', 'execute'),
  '3c rights as before: Correct payment for signed-in logins, remove and split for the server');
rollback;
