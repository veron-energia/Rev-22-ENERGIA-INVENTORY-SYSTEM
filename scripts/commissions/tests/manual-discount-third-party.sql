-- An invoice's manual discount comes off every line's commission, third-party
-- lines included (391). Rates as on 3 Oct 2026: tier 1 15% own, 4.5%
-- third-party; tier 2 35% of tier 1.
--
--   M0 Before 391 the three invoices below earned S$12.00, S$4.50 and
--      S$22.50 at tier 1 (the third-party line kept its full value).
--   M1 own S$100 + third S$100, manual S$50: own on S$75 (S$11.25), third on
--      S$75 (S$3.38); tier 2 follows each.
--   M2 third S$100 alone, manual S$30: third on S$70 (S$3.15).
--   M3 own S$100 + third S$500, manual S$150: own on S$75 (S$11.25), third on
--      S$375 (S$16.88).
--   M4 the voucher stays off third-party goods: own S$100 + third S$100,
--      manual S$20, a 10% voucher (S$8): own on S$82, third on S$90.
--   M5 in M1-M4 the tier-1 bases add up to what the customer paid.
--   M6 the part-payment preview (357) answers what settlement earns.
--   M7 no change where there is no manual discount or no third-party line:
--      a manual discount and a voucher on our own lines only; a voucher beside
--      a third-party line; no discount at all.
--   M8 paid in two halves (part payments earning): half is registered at the
--      first payment; settlement reverses it and earns the same S$28.13.
--   M9 running 391 again changes nothing.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Installs 384 first when the database still has
-- the version before it (the shared local one), then 391. Fixtures are
-- invented.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;

-- Production's earn_invoice_commission (384's) where the database is behind.
select md5(pg_get_functiondef('public.earn_invoice_commission(uuid)'::regprocedure)) = '2e4942e9ff859b0469fdcd99faf325fd' as need384 \gset
\if :need384
set client_min_messages = warning;
\ir ../../../supabase/384_invoice_and_staff_commission_use_the_singapore_date.sql
reset client_min_messages;
\endif

-- The preview as it is before 391, kept beside it to compare with.
select md5(pg_get_functiondef('public.invoice_affiliate_commission_preview(uuid)'::regprocedure)) = '79e093f22f226f1a72ca059f1da1234b' as before391 \gset
\if :before391
do $$ begin
  execute replace(pg_get_functiondef('public.invoice_affiliate_commission_preview(uuid)'::regprocedure),
    'FUNCTION public.invoice_affiliate_commission_preview(', 'FUNCTION pg_temp.preview_before_391(');
end $$;
\endif

\ir ../../../supabase/391_manual_discount_reaches_third_party_commission.sql

create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;
create function pg_temp.line(kind text, n int default 1) returns jsonb language sql as
$$ select jsonb_build_object('kind','product','product_id',pg_temp.fx(kind),'quantity',n) $$;
-- A new buyer referred by the tier-1 affiliate, and an invoice for them.
create function pg_temp.mk(items jsonb, hdr jsonb default '{}'::jsonb) returns uuid language plpgsql as
$$declare c uuid;
begin
  insert into public.customers(full_name, phone, referred_by)
  values ('M391 Buyer',
          (select '+659123' || lpad(n::text, 4, '0') from generate_series(0, 9999) n
            where not exists (select 1 from public.customers x
                               where regexp_replace(coalesce(x.phone, ''), '\D', '', 'g') = '659123' || lpad(n::text, 4, '0'))
            order by random() limit 1), pg_temp.fx('t1')) returning id into c;
  return public.create_invoice_with_details(pg_temp.fx('A'), c, items,
           jsonb_build_object('business_date', public.sg_today()::text) || hdr);
end$$;
create function pg_temp.pay(inv uuid, amount numeric default null) returns void language sql as
$$ select public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'),
     'amount', coalesce(amount, (select total_amount - paid_amount from public.invoices where id = inv))))) $$;
create function pg_temp.manual(amount numeric) returns jsonb language sql as
$$ select jsonb_build_object('manual_discount', amount, 'manual_discount_reason', 'Test reason') $$;
-- Tier-1 (or tier-2) commission by product type, as "own base/amount, third base/amount".
create function pg_temp.earned(inv uuid, t text default 'tier1') returns text language sql as
$$ select coalesce(string_agg(product_type || ' ' || line_amount || '/' || commission_amount, ', ' order by product_type), '-')
     from (select product_type, sum(line_amount) line_amount, sum(commission_amount) commission_amount
             from public.commissions where invoice_id = inv and tier::text = t group by product_type) x $$;
-- What the invoice earns now: its rows that are not reversed.
create function pg_temp.total(inv uuid, t text default 'tier1') returns numeric language sql as
$$ select coalesce(sum(commission_amount), 0) from public.commissions
    where invoice_id = inv and tier::text = t and status::text <> 'reversed' $$;
-- The preview, rounded as it is stored, in the same shape.
create function pg_temp.previewed(inv uuid, t text default 'tier1') returns text language sql as
$$ select coalesce(string_agg(o_product_type || ' ' || b || '/' || a, ', ' order by o_product_type), '-')
     from (select o_product_type, sum(round(o_line_amount, 2)) b, sum(o_amount) a
             from public.invoice_affiliate_commission_preview(inv) where o_tier = t group by o_product_type) x $$;

-- ═════ Fixtures (invented) ═════
do $$
declare o uuid:=gen_random_uuid(); sfx text:=lower(substr(md5(random()::text||clock_timestamp()::text),1,6));
 st uuid; v uuid; t2 uuid;
begin
 insert into auth.users(id,email) values (o,'m391-o-'||sfx||'@tests.invalid');
 insert into profiles(id,full_name,email,role) values (o,'M391 Owner','m391-o-'||sfx||'@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 update public.app_settings set commission_tier1_own_rate = 15, commission_tier1_third_rate = 4.5,
        commission_tier2_own_rate = 35, commission_tier2_third_rate = 35 where id = true;
 insert into stores(name,code,country_code) values('M391 Store '||sfx,'M391'||sfx,'SG') returning id into st;
 insert into fx values ('A',st);
 insert into payment_methods(name) values('M391 Cash '||sfx) returning id into v; insert into fx values ('cash',v);
 insert into customers(full_name,phone) values('M391 Upline','+6591239'||lpad((floor(random()*1000))::int::text,3,'0')) returning id into t2;
 insert into customers(full_name,phone,referred_by) values('M391 Affiliate','+6591238'||lpad((floor(random()*1000))::int::text,3,'0'),t2) returning id into v;
 insert into fx values ('t1',v),('t2',t2);
 insert into products(name,sku,product_type) values('M391 Lamp','M391L-'||sfx,'own') returning id into v; insert into fx values ('own',v);
 insert into store_inventory(store_id,product_id,current_qty) values(st,v,100);
 perform set_product_prices(st,v,100,100,'available');
 insert into products(name,sku,product_type) values('M391 Massager','M391M-'||sfx,'third_party') returning id into v; insert into fx values ('third',v);
 insert into store_inventory(store_id,product_id,current_qty) values(st,v,100);
 perform set_product_prices(st,v,100,100,'available');
 insert into vouchers(name,code,voucher_kind,discount_amount,qty_type,is_active)
   values ('M391 10 off','M391F-'||sfx,'fixed_discount',10,'unlimited',true) returning id into v; insert into fx values ('v10',v);
 insert into vouchers(name,code,voucher_kind,discount_percent,qty_type,is_active)
   values ('M391 10 pct','M391P-'||sfx,'percentage_discount',10,'unlimited',true) returning id into v; insert into fx values ('pct',v);
end $$;

-- ═════ M1-M4 ═════
do $$
declare inv uuid;
begin
 inv := pg_temp.mk(jsonb_build_array(pg_temp.line('own'), pg_temp.line('third')), pg_temp.manual(50));
 insert into fx values ('m1', inv); perform pg_temp.pay(inv);
 perform pg_temp.check(pg_temp.earned(inv) = 'own 75.00/11.25, third_party 75.00/3.38',
   'M1 own S$100 + third S$100, manual S$50: each line on S$75 (got ' || pg_temp.earned(inv) || ')');
 perform pg_temp.check(pg_temp.earned(inv, 'tier2') = 'own 11.25/3.94, third_party 3.38/1.18',
   'M1 tier 2 is 35% of each tier-1 row (got ' || pg_temp.earned(inv, 'tier2') || ')');

 inv := pg_temp.mk(jsonb_build_array(pg_temp.line('third')), pg_temp.manual(30));
 insert into fx values ('m2', inv); perform pg_temp.pay(inv);
 perform pg_temp.check(pg_temp.earned(inv) = 'third_party 70.00/3.15',
   'M2 third S$100 alone, manual S$30: on the S$70 paid (got ' || pg_temp.earned(inv) || ')');

 inv := pg_temp.mk(jsonb_build_array(pg_temp.line('own'), pg_temp.line('third', 5)), pg_temp.manual(150));
 insert into fx values ('m3', inv); perform pg_temp.pay(inv);
 perform pg_temp.check(pg_temp.earned(inv) = 'own 75.00/11.25, third_party 375.00/16.88',
   'M3 own S$100 + third S$500, manual S$150: own on S$75, third on S$375 (got ' || pg_temp.earned(inv) || ')');

 inv := pg_temp.mk(jsonb_build_array(pg_temp.line('own'), pg_temp.line('third')),
                   pg_temp.manual(20) || jsonb_build_object('discount_voucher_id', pg_temp.fx('pct')));
 insert into fx values ('m4', inv);
 perform pg_temp.check((select discount_total from public.invoices where id = inv) = 28,
   'M4 fixture: manual S$20 + 10% of the S$80 own value left = S$28');
 perform pg_temp.pay(inv);
 perform pg_temp.check(pg_temp.earned(inv) = 'own 82.00/12.30, third_party 90.00/4.05',
   'M4 the manual discount on every line, the voucher on our own only: own on S$82, third on S$90 (got ' || pg_temp.earned(inv) || ')');
end $$;

-- ═════ M0 What they earned before 391 ═════
\if :before391
do $$
declare k text; want numeric[] := array[12.00, 4.50, 22.50]; got numeric; i int := 0;
begin
 foreach k in array array['m1','m2','m3'] loop
   i := i + 1;
   select coalesce(sum(o_amount), 0) into got from pg_temp.preview_before_391(pg_temp.fx(k)) where o_tier = 'tier1';
   perform pg_temp.check(got = want[i], format('M0 %s earned S$%s at tier 1 before 391 (got %s)', upper(k), want[i], got));
 end loop;
end $$;
\else
select pg_temp.check(true, 'M0 skipped: the database already has 391');
\endif

-- ═════ M5 The bases add up to what was paid ═════
do $$
declare k text; inv uuid; paid numeric; base numeric;
begin
 foreach k in array array['m1','m2','m3','m4'] loop
   inv := pg_temp.fx(k);
   select total_amount into paid from public.invoices where id = inv;
   select sum(line_amount) into base from public.commissions where invoice_id = inv and tier = 'tier1';
   perform pg_temp.check(base = paid, format('M5 %s: tier-1 bases S$%s = paid S$%s', upper(k), base, paid));
 end loop;
end $$;

-- ═════ M6 The preview answers what settlement earns ═════
do $$
declare k text; inv uuid;
begin
 foreach k in array array['m1','m2','m3','m4'] loop
   inv := pg_temp.fx(k);
   perform pg_temp.check(pg_temp.previewed(inv) = pg_temp.earned(inv) and pg_temp.previewed(inv, 'tier2') = pg_temp.earned(inv, 'tier2'),
     format('M6 %s: the preview (%s) equals what was earned (%s)', upper(k), pg_temp.previewed(inv), pg_temp.earned(inv)));
 end loop;
end $$;

-- ═════ M7 No change without a manual discount or a third-party line ═════
\if :before391
do $$
declare inv uuid; k text; before_ text; after_ text; i int := 0;
  cases jsonb[] := array[
    jsonb_build_object('items', jsonb_build_array(pg_temp.line('own', 2)),
                       'hdr', pg_temp.manual(20) || jsonb_build_object('discount_voucher_id', pg_temp.fx('pct')),
                       'what', 'a manual discount and a voucher, our own lines only'),
    jsonb_build_object('items', jsonb_build_array(pg_temp.line('own'), pg_temp.line('third', 2)),
                       'hdr', jsonb_build_object('discount_voucher_id', pg_temp.fx('v10')),
                       'what', 'a voucher beside third-party lines, no manual discount'),
    jsonb_build_object('items', jsonb_build_array(pg_temp.line('own'), pg_temp.line('third')),
                       'hdr', '{}'::jsonb, 'what', 'no discount')];
  c jsonb;
begin
 foreach c in array cases loop
   i := i + 1;
   inv := pg_temp.mk(c->'items', c->'hdr');
   select string_agg(o_tier || ' ' || o_product_type || ' ' || o_line_amount || '/' || o_amount, ', '
                     order by o_tier, o_product_type, o_invoice_item_id) into before_
     from pg_temp.preview_before_391(inv);
   select string_agg(o_tier || ' ' || o_product_type || ' ' || o_line_amount || '/' || o_amount, ', '
                     order by o_tier, o_product_type, o_invoice_item_id) into after_
     from public.invoice_affiliate_commission_preview(inv);
   perform pg_temp.check(before_ is not distinct from after_ and before_ is not null,
     format('M7.%s %s: the same to the last digit (before %s; after %s)', i, c->>'what', before_, after_));
 end loop;
end $$;
\else
select pg_temp.check(true, 'M7 skipped: the database already has 391');
\endif

-- ═════ M8 Paid in two halves, with part payments earning ═════
do $$
declare inv uuid; first_half numeric;
begin
 update public.app_settings set instalment_commission_from = public.sg_today() - 30 where id = true;
 inv := pg_temp.mk(jsonb_build_array(pg_temp.line('own'), pg_temp.line('third', 5)), pg_temp.manual(150));
 insert into fx values ('m8', inv);
 perform pg_temp.pay(inv, 225);
 select coalesce(sum(commission_amount), 0) into first_half
   from public.commissions where invoice_id = inv and tier = 'tier1' and earning_basis = 'instalment';
 perform pg_temp.check(first_half = 14.07,
   format('M8 half paid: half of S$11.25 + S$16.88 registered at tier 1, S$14.07 (got %s)', first_half));
 perform pg_temp.pay(inv);
 perform pg_temp.check((select status from public.invoices where id = inv) = 'paid', 'M8 the second half settles the invoice');
 perform pg_temp.check(pg_temp.total(inv) = 28.13
     and not exists (select 1 from public.commissions where invoice_id = inv and earning_basis = 'instalment' and status::text <> 'reversed'),
   format('M8 settled: the part-payment rows reversed, tier 1 comes to S$28.13, as paid at once (got %s: %s)', pg_temp.total(inv),
     (select string_agg(earning_basis || ' ' || product_type || ' ' || commission_amount || ' ' || status, '; ')
        from public.commissions where invoice_id = inv and tier = 'tier1')));
end $$;

-- ═════ M9 Running 391 again changes nothing ═════
create temp table before_rerun as
  select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) m from pg_proc p
   where p.oid in ('public.earn_invoice_commission(uuid)'::regprocedure,
                   'public.invoice_affiliate_commission_preview(uuid)'::regprocedure);
\ir ../../../supabase/391_manual_discount_reaches_third_party_commission.sql
do $$
begin
 perform pg_temp.check(not exists (
   select 1 from before_rerun b
    where b.m is distinct from md5(pg_get_functiondef(to_regprocedure('public.' || b.fn)))),
   'M9 running 391 again leaves both functions as they were');
end $$;

do $$
declare n int; msgs text;
begin
 select count(*), string_agg(msg, E'\n') into n, msgs from failed;
 if n > 0 then raise exception '% check(s) failed:%', n, E'\n' || msgs; end if;
 raise notice 'ALL PASSED: the manual discount comes off every line''s commission, third-party included; the voucher stays on our own lines; bases add up to what was paid; the preview agrees; nothing else moves; part payments settle to the same; 391 re-runs as a no-op';
end $$;
rollback;
