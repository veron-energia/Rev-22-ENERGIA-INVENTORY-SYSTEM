-- Creating an invoice with a request id, and the New Invoice date (416:
-- INVOICES-CREATE-15, INVOICES-CREATE-11).
--
--   R1 The same request sent again returns the invoice it made: one invoice.
--      Its request id and the request's md5 are kept on the invoice.
--   R2 The same request id with other contents (the form changed after its
--      first save went through) is refused, naming the invoice it made, and
--      nothing is made.
--   R3 With no request id, two creates make two invoices, as before (website
--      orders and event tickets send none).
--   R4 A new request id makes a new invoice (a deliberate second sale).
--   R5 Once the invoice is deleted, its request is refused, naming it, with
--      the same contents or others.
--   R6 Staff of another store sending the request get no invoice of it.
--   R7 A date after today in Singapore is refused; today and a past date are
--      not.
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
-- create_invoice_with_details as the page calls it: the invoice id, or the refusal.
create function pg_temp.create(qty int, hdr jsonb) returns jsonb language plpgsql as
$$declare v uuid;
begin
  v := public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c'),
    jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('socks'),'quantity',qty)),
    jsonb_build_object('business_date', public.sg_today()::text, 'notes', null, 'manual_discount', 0,
                       'discount_voucher_id', null, 'service_staff', '[]'::jsonb) || hdr);
  return jsonb_build_object('id', v);
exception when others then return jsonb_build_object('error', sqlerrm);
end$$;
create function pg_temp.made() returns int language sql as
$$ select count(*)::int from public.invoices where customer_id = pg_temp.fx('c') $$;

do $$
declare o uuid := gen_random_uuid(); s2 uuid := gen_random_uuid(); sfx text := left(md5(random()::text), 6);
  st_a uuid; st_b uuid; c uuid; p uuid;
begin
  insert into auth.users(id,email) values (o,'rq416-o-'||sfx||'@tests.invalid'),(s2,'rq416-s2-'||sfx||'@tests.invalid');
  insert into profiles(id,full_name,email,role) values (o,'RQ Owner','rq416-o-'||sfx||'@tests.invalid','owner'),
    (s2,'RQ Other Staff','rq416-s2-'||sfx||'@tests.invalid','staff');
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into stores(name,code,country_code) values ('RQ Store A','RQA'||sfx,'SG') returning id into st_a;
  insert into stores(name,code,country_code) values ('RQ Store B','RQB'||sfx,'SG') returning id into st_b;
  insert into user_store_assignments(user_id,store_id) values (s2,st_b);
  insert into customers(full_name,phone) values ('RQ Buyer','+61491575789') returning id into c;
  insert into products(name,sku,product_type) values ('RQ Socks','RQS-'||sfx,'own') returning id into p;
  insert into store_inventory(store_id,product_id,current_qty) values (st_a,p,100);
  perform set_product_prices(st_a,p,100,100,'available');
  insert into fx values ('o',o),('s2',s2),('A',st_a),('c',c),('socks',p),('rid',gen_random_uuid()),('rid2',gen_random_uuid());
end $$;

do $$
declare r1 jsonb; r jsonb; n int;
begin
  -- R1
  r1 := pg_temp.create(1, jsonb_build_object('request_id', pg_temp.fx('rid')));
  r := pg_temp.create(1, jsonb_build_object('request_id', pg_temp.fx('rid')));
  perform pg_temp.check(r1->>'id' is not null and r->>'id' = r1->>'id' and pg_temp.made() = 1,
    'R1 the same request again returns the invoice it made, and only one is made: ' || coalesce(r->>'error', r1->>'error', 'one'));
  perform pg_temp.check((select create_request_id = pg_temp.fx('rid') and create_request_hash ~ '^[0-9a-f]{32}$'
                           from public.invoices where id = (r1->>'id')::uuid),
    'R1 the invoice keeps the request id and the md5 of what it asked for');
  -- The same request with its header keys in another order is the same request.
  r := pg_temp.create(1, jsonb_build_object('service_staff', '[]'::jsonb, 'request_id', pg_temp.fx('rid')));
  perform pg_temp.check(r->>'id' = r1->>'id' and pg_temp.made() = 1, 'R1 key order does not matter: ' || coalesce(r->>'error', 'one'));
  -- R2
  r := pg_temp.create(2, jsonb_build_object('request_id', pg_temp.fx('rid')));
  perform pg_temp.check(r->>'error' = format('This form already made %s. Open that invoice to change it, instead of creating another.',
                                             (select invoice_no from public.invoices where id = (r1->>'id')::uuid))
      and pg_temp.made() = 1, 'R2 the same request id with two pairs instead of one is refused, naming the invoice: ' || coalesce(r->>'error', 'made'));
  r := pg_temp.create(1, jsonb_build_object('request_id', pg_temp.fx('rid'), 'notes', 'Gift'));
  perform pg_temp.check(r->>'error' like 'This form already made %. Open that invoice to change it, instead of creating another.' and pg_temp.made() = 1,
    'R2 and with another note: ' || coalesce(r->>'error', 'made'));
  -- R3
  n := pg_temp.made();
  perform pg_temp.create(1, '{}'::jsonb);
  perform pg_temp.create(1, '{}'::jsonb);
  perform pg_temp.check(pg_temp.made() = n + 2, 'R3 with no request id, two creates make two invoices');
  -- R4
  r := pg_temp.create(1, jsonb_build_object('request_id', pg_temp.fx('rid2')));
  perform pg_temp.check(r->>'id' is not null and r->>'id' <> r1->>'id' and pg_temp.made() = n + 3,
    'R4 a new request id makes a new invoice: ' || coalesce(r->>'error', 'made'));
  -- R6
  perform pg_temp.as_user('s2');
  r := pg_temp.create(1, jsonb_build_object('request_id', pg_temp.fx('rid')));
  perform pg_temp.check(r->>'error' = 'You do not have access to this store', 'R6 staff of another store get no invoice of it: ' || coalesce(r->>'error', r->>'id'));
  perform pg_temp.as_user('o');
  -- R5
  update public.invoices set deleted_at = now() where id = (r1->>'id')::uuid;
  r := pg_temp.create(1, jsonb_build_object('request_id', pg_temp.fx('rid')));
  perform pg_temp.check(r->>'error' = format('The invoice this request made (%s) has been deleted. Open New Invoice again to make another.',
                                             (select invoice_no from public.invoices where id = (r1->>'id')::uuid)),
    'R5 a deleted invoice''s request is refused, naming it: ' || coalesce(r->>'error', 'made'));
  r := pg_temp.create(2, jsonb_build_object('request_id', pg_temp.fx('rid')));
  perform pg_temp.check(r->>'error' = format('The invoice this request made (%s) has been deleted. Open New Invoice again to make another.',
                                             (select invoice_no from public.invoices where id = (r1->>'id')::uuid)),
    'R5 and with other contents: ' || coalesce(r->>'error', 'made'));
  -- R7
  n := pg_temp.made();
  r := pg_temp.create(1, jsonb_build_object('business_date', (public.sg_today() + 1)::text));
  perform pg_temp.check(r->>'error' = 'The invoice date cannot be after today.' and pg_temp.made() = n,
    'R7 a New Invoice dated tomorrow is refused: ' || coalesce(r->>'error', 'made'));
  r := pg_temp.create(1, jsonb_build_object('business_date', public.sg_today()::text));
  perform pg_temp.check(r->>'id' is not null and (select business_date from public.invoices where id = (r->>'id')::uuid) = public.sg_today(),
    'R7 today is accepted: ' || coalesce(r->>'error', 'made'));
  r := pg_temp.create(1, jsonb_build_object('business_date', (public.sg_today() - 3)::text));
  perform pg_temp.check(r->>'id' is not null, 'R7 and a past date: ' || coalesce(r->>'error', 'made'));
end $$;

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All request id and date checks passed.';
end $$;
rollback;
