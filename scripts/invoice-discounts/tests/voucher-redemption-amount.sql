-- The redemption row of an invoice-level Discount Voucher records what the
-- voucher gave, as the Discounts report reads it (387).
--
--   R1 Paid in full: S$200 of goods, a S$5 line voucher, a S$20 manual
--      discount and a 10% invoice voucher. The voucher gave S$17.50 (10% of
--      200 - 20 - 5); before 387 its row said S$37.50. The line voucher's row
--      is its S$5, as before.
--   R2 A voucher alone: S$100 and a S$10 voucher record S$10, as before.
--   R3 A manual discount that leaves the voucher little: S$100, a S$95 manual
--      discount and a 10% voucher give S$0.50 (before: S$95.50).
--   R4 Save Earth on an invoice from before it was removed is not the
--      voucher's either: S$100, a S$10 voucher and S$2 Save Earth record S$10
--      (before: S$12).
--   R5 Confirmed as FOC: one line free, the other S$100 brought to nothing by a
--      S$90 manual discount and a 100% voucher on the S$10 left. The voucher
--      gave S$10 (before: S$100).
--   R6 Every invoice-level row written here equals report_discounts' Voucher
--      column for its invoice.
--   R7 Running 387 again changes nothing.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Installs 387 after "begin;" (a database that has
-- it already leaves it alone). Fixtures are invented.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;

\ir ../../../supabase/387_voucher_redemption_records_the_voucher_alone.sql

create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;
create function pg_temp.mk(items jsonb, hdr jsonb default '{}'::jsonb) returns uuid language sql as
$$ select public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('c'), items,
     jsonb_build_object('business_date', public.sg_today()::text) || hdr) $$;
create function pg_temp.pay(inv uuid) returns void language sql as
$$ select public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'),
     'amount', (select total_amount from public.invoices where id = inv)))) $$;
-- The invoice-level voucher's redemption row (exactly one is expected).
create function pg_temp.redeemed(inv uuid) returns numeric language sql as
$$ select case when count(*) = 1 then max(r.discount_applied) end
     from public.voucher_redemptions r join public.invoices i on i.id = r.invoice_id
    where r.invoice_id = inv and r.voucher_id = i.discount_voucher_id $$;
create function pg_temp.reported(inv uuid) returns numeric language sql as
$$ select voucher_discount from public.report_discounts() where invoice_id = inv $$;
create function pg_temp.own(n int default 1) returns jsonb language sql as
$$ select jsonb_build_object('kind','product','product_id',pg_temp.fx('own'),'quantity',n) $$;

-- ═════ Fixtures (invented) ═════
do $$
declare o uuid:=gen_random_uuid(); sfx text:=lower(substr(md5(random()::text||clock_timestamp()::text),1,6));
 st uuid; v uuid;
begin
 insert into auth.users(id,email) values (o,'v387-o-'||sfx||'@tests.invalid');
 insert into profiles(id,full_name,email,role) values (o,'V387 Owner','v387-o-'||sfx||'@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('V387 Store '||sfx,'V387'||sfx,'SG') returning id into st;
 insert into fx values ('A',st);
 insert into payment_methods(name) values('V387 Cash '||sfx) returning id into v; insert into fx values ('cash',v);
 insert into customers(full_name,phone) values('V387 Buyer',
   (select '+659123' || lpad(n::text, 4, '0') from generate_series(0, 9999) n
     where not exists (select 1 from public.customers x
                        where regexp_replace(coalesce(x.phone, ''), '\D', '', 'g') = '659123' || lpad(n::text, 4, '0'))
     order by random() limit 1)) returning id into v;
 insert into fx values ('c',v);
 insert into products(name,sku,product_type) values('V387 Lamp','V387L-'||sfx,'own') returning id into v; insert into fx values ('own',v);
 insert into store_inventory(store_id,product_id,current_qty) values(st,v,100);
 perform set_product_prices(st,v,100,100,'available');
 insert into products(name,sku,product_type) values('V387 Kettle','V387K-'||sfx,'own') returning id into v; insert into fx values ('own2',v);
 insert into store_inventory(store_id,product_id,current_qty) values(st,v,100);
 perform set_product_prices(st,v,40,40,'available');
 insert into vouchers(name,code,voucher_kind,discount_amount,qty_type,is_active)
   values ('V387 10 off','V387F-'||sfx,'fixed_discount',10,'unlimited',true) returning id into v; insert into fx values ('v10',v);
 insert into vouchers(name,code,voucher_kind,discount_amount,qty_type,is_active)
   values ('V387 line 5 off','V387L5-'||sfx,'fixed_discount',5,'unlimited',true) returning id into v; insert into fx values ('v5',v);
 insert into vouchers(name,code,voucher_kind,discount_percent,qty_type,is_active)
   values ('V387 10 pct','V387P-'||sfx,'percentage_discount',10,'unlimited',true) returning id into v; insert into fx values ('pct',v);
 insert into vouchers(name,code,voucher_kind,discount_percent,qty_type,is_active)
   values ('V387 the rest free','V387X-'||sfx,'percentage_discount',100,'unlimited',true) returning id into v; insert into fx values ('all',v);
end $$;

-- ═════ R1 Paid in full, with a line voucher and a manual discount ═════
do $$
declare inv uuid; i public.invoices;
begin
 inv := pg_temp.mk(jsonb_build_array(pg_temp.own(2) || jsonb_build_object('line_voucher_id', pg_temp.fx('v5'))),
   jsonb_build_object('discount_voucher_id', pg_temp.fx('pct'), 'manual_discount', 20, 'manual_discount_reason', 'Loyal customer'));
 insert into fx values ('r1', inv);
 select * into i from public.invoices where id = inv;
 perform pg_temp.check(i.subtotal = 200 and i.manual_discount = 20 and i.discount_total = 42.50 and i.total_amount = 157.50,
   format('R1 fixture: subtotal 200, manual 20, discount 42.50, total 157.50 (got %s, %s, %s, %s)',
          i.subtotal, i.manual_discount, i.discount_total, i.total_amount));
 perform pg_temp.pay(inv);
 perform pg_temp.check(pg_temp.redeemed(inv) = 17.50,
   format('R1 the invoice voucher records the S$17.50 it gave, not the manual discount beside it (got %s)', pg_temp.redeemed(inv)));
 perform pg_temp.check((select discount_applied from public.voucher_redemptions
                         where invoice_id = inv and voucher_id = pg_temp.fx('v5')) = 5,
   'R1 the line voucher records its S$5, as before');
end $$;

-- ═════ R2 A voucher alone ═════
do $$
declare inv uuid;
begin
 inv := pg_temp.mk(jsonb_build_array(pg_temp.own()), jsonb_build_object('discount_voucher_id', pg_temp.fx('v10')));
 insert into fx values ('r2', inv);
 perform pg_temp.pay(inv);
 perform pg_temp.check(pg_temp.redeemed(inv) = 10,
   format('R2 a voucher with nothing beside it records its S$10, as before (got %s)', pg_temp.redeemed(inv)));
end $$;

-- ═════ R3 A manual discount that leaves the voucher little ═════
do $$
declare inv uuid; i public.invoices;
begin
 inv := pg_temp.mk(jsonb_build_array(pg_temp.own()),
   jsonb_build_object('discount_voucher_id', pg_temp.fx('pct'), 'manual_discount', 95, 'manual_discount_reason', 'Display unit'));
 insert into fx values ('r3', inv);
 select * into i from public.invoices where id = inv;
 perform pg_temp.check(i.discount_total = 95.50 and i.total_amount = 4.50,
   format('R3 fixture: 10%% of the S$5 left after the manual discount, total 4.50 (got %s, %s)', i.discount_total, i.total_amount));
 perform pg_temp.pay(inv);
 perform pg_temp.check(pg_temp.redeemed(inv) = 0.50,
   format('R3 the voucher records S$0.50, not S$95.50 (got %s)', pg_temp.redeemed(inv)));
end $$;

-- ═════ R4 Save Earth from before it was removed ═════
do $$
declare inv uuid; e text;
begin
 inv := pg_temp.mk(jsonb_build_array(pg_temp.own()), jsonb_build_object('discount_voucher_id', pg_temp.fx('v10')));
 insert into fx values ('r4', inv);
 -- As an invoice made while Save Earth was offered carries it: in the
 -- discount total, out of the total.
 update public.invoices set save_earth_applied = true, save_earth_amount = 2,
        discount_total = discount_total + 2, total_amount = total_amount - 2 where id = inv;
 perform pg_temp.pay(inv);
 perform pg_temp.check(pg_temp.redeemed(inv) = 10,
   format('R4 Save Earth is not the voucher''s: S$10 recorded, not S$12 (got %s)', pg_temp.redeemed(inv)));
end $$;

-- ═════ R5 Confirmed as FOC ═════
do $$
declare inv uuid; i public.invoices; r jsonb;
begin
 inv := pg_temp.mk(jsonb_build_array(
          jsonb_build_object('kind','product','product_id',pg_temp.fx('own2'),'quantity',1,'foc_quantity',1,'foc_reason','Test goodwill'),
          pg_temp.own()),
   jsonb_build_object('discount_voucher_id', pg_temp.fx('all'), 'manual_discount', 90, 'manual_discount_reason', 'Event price'));
 insert into fx values ('r5', inv);
 select * into i from public.invoices where id = inv;
 perform pg_temp.check(i.has_foc and i.discount_total = 100 and i.total_amount = 0,
   format('R5 fixture: has FOC, discount 100, total 0 (got %s, %s, %s)', i.has_foc, i.discount_total, i.total_amount));
 r := public.confirm_foc_invoice(inv, 'Test confirm');
 perform pg_temp.check((select status from public.invoices where id = inv) = 'completed_foc',
   format('R5 the invoice is confirmed as FOC (%s)', r));
 perform pg_temp.check(pg_temp.redeemed(inv) = 10,
   format('R5 the voucher records its S$10, not the S$100 discount total (got %s)', pg_temp.redeemed(inv)));
end $$;

-- ═════ R6 The rows agree with the Discounts report ═════
do $$
declare k text; inv uuid;
begin
 foreach k in array array['r1','r2','r3','r4','r5'] loop
   inv := pg_temp.fx(k);
   perform pg_temp.check(pg_temp.redeemed(inv) is not distinct from pg_temp.reported(inv),
     format('R6 %s: the redemption row (%s) equals the Discounts report''s Voucher column (%s)',
            upper(k), pg_temp.redeemed(inv), pg_temp.reported(inv)));
 end loop;
end $$;

-- ═════ R7 Running 387 again changes nothing ═════
create temp table before_rerun as
  select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) m from pg_proc p
   where p.oid in ('public.invoice_record_payments_internal(uuid,jsonb)'::regprocedure,
                   'public.confirm_foc_invoice(uuid,text)'::regprocedure);
\ir ../../../supabase/387_voucher_redemption_records_the_voucher_alone.sql
do $$
begin
 perform pg_temp.check(not exists (
   select 1 from before_rerun b
    where b.m is distinct from md5(pg_get_functiondef(to_regprocedure('public.' || b.fn)))),
   'R7 running 387 again leaves both functions as they were');
end $$;

do $$
declare n int; msgs text;
begin
 select count(*), string_agg(msg, E'\n') into n, msgs from failed;
 if n > 0 then raise exception '% check(s) failed:%', n, E'\n' || msgs; end if;
 raise notice 'ALL PASSED: the invoice voucher''s redemption row is the voucher alone (paid and FOC-confirmed), equal to the Discounts report; line vouchers and a voucher alone are unchanged; 387 re-runs as a no-op';
end $$;
rollback;
