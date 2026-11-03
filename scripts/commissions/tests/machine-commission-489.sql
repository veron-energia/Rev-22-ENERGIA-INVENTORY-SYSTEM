-- A special product or a rental earns commission like the machine it is
-- (489; the user, 3 Nov 2026), from the moment 489 is applied; what was
-- already earned stays. Rates as on 3 Nov 2026: tier 1 15% own, 4.5%
-- third-party; tier 2 35% of tier 1.
--
--   M0 Before 489: a third-party machine sold as a special product earns as
--      ours (S$1,000 -> S$150.00 at tier 1).
--   M1 That sale, recalculated after 489 is in (a reconcile, as a refund,
--      cancellation, reopening, correction or payment change runs), still
--      earns S$150.00: the rule follows the invoice's creation time.
--   M2 After 489: the same machine sold as a special product earns the
--      third-party rate (S$45.00, tier 2 S$15.75).
--   M3 A month's rental of it (S$100): third-party too (S$4.50 / S$1.58).
--   M4 A special product of our own machine: our rate, as before.
--   M5 One of a no-commission machine: nothing.
--   M6 One linked to no machine: ours, as before.
--   M7 With an invoice Discount Voucher, the machine line takes no share of
--      it, exactly as the same machine sold as a product line: both invoices
--      earn the same.
--   M8 Part-paid: the first half earns its third-party share; settlement
--      comes to what paying at once earns.
--   M9 The preview (357) shows what earn_invoice_commission writes, on every
--      invoice above.
--   M10 With no cut-off (489's UNDO) a new sale earns as before.
--   M11 Running 489 again changes nothing.
--
-- Run on a copy of production at 481 or later (createdb -T of a template
-- equal to it; never the template itself):
--   psql -d <copy> -v ON_ERROR_STOP=1 -f scripts/commissions/tests/machine-commission-489.sql
-- Every check runs, then the file fails if any did. Everything is rolled
-- back. Fixtures are invented (the repository is public).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;

-- A settings row as production has one (a local copy may have none), at the
-- rates of 3 Nov 2026.
insert into public.app_settings (id, staff_commission_rate, save_earth_label, save_earth_amount,
  commission_tier1_own_rate, commission_tier1_third_rate, commission_tier2_own_rate, commission_tier2_third_rate,
  instalment_commission_from)
values (true, 3, 'No Discount', 0, 15, 4.5, 35, 35, date '2026-09-25')
on conflict (id) do update set commission_tier1_own_rate = 15, commission_tier1_third_rate = 4.5,
  commission_tier2_own_rate = 35, commission_tier2_third_rate = 35, instalment_commission_from = date '2026-09-25';

create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;
create function pg_temp.sp(key text) returns jsonb language sql as
$$ select jsonb_build_object('kind','special_product','special_product_id',pg_temp.fx(key),'quantity',1) $$;
create function pg_temp.rent(key text) returns jsonb language sql as
$$ select jsonb_build_object('kind','rental','special_product_id',pg_temp.fx(key),'quantity',1,
            'rental_rate_type','month','rental_periods',1,'rental_start_date',public.sg_today()::text) $$;
create function pg_temp.prod(key text) returns jsonb language sql as
$$ select jsonb_build_object('kind','product','product_id',pg_temp.fx(key),'quantity',1) $$;
create function pg_temp.mk(items jsonb, hdr jsonb default '{}'::jsonb) returns uuid language sql as
$$ select public.create_invoice_with_details(pg_temp.fx('A'), pg_temp.fx('buyer'), items,
            jsonb_build_object('business_date', public.sg_today()::text) || hdr) $$;
create function pg_temp.pay(inv uuid, amount numeric default null) returns void language sql as
$$ select public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'),
     'amount', coalesce(amount, (select total_amount - paid_amount from public.invoices where id = inv))))) $$;
-- What the invoice earns now at a tier (its rows that are not reversed), as
-- "type base/amount" per product type.
create function pg_temp.earned(inv uuid, t text default 'tier1') returns text language sql as
$$ select coalesce(string_agg(product_type || ' ' || line_amount || '/' || commission_amount, ', ' order by product_type), '-')
     from (select product_type::text, sum(line_amount) line_amount, sum(commission_amount) commission_amount
             from public.commissions where invoice_id = inv and tier::text = t and status::text <> 'reversed'
            group by product_type) x $$;
-- The preview, rounded as it is stored, in the same shape.
create function pg_temp.previewed(inv uuid, t text default 'tier1') returns text language sql as
$$ select coalesce(string_agg(o_product_type || ' ' || b || '/' || a, ', ' order by o_product_type), '-')
     from (select o_product_type, sum(round(o_line_amount, 2)) b, sum(o_amount) a
             from public.invoice_affiliate_commission_preview(inv) where o_tier = t group by o_product_type) x $$;

-- ═════ Fixtures (invented) ═════
do $$
declare o uuid := gen_random_uuid(); sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  st uuid; wh uuid; v uuid; t1 uuid; t2 uuid; b uuid; ph text[];
begin
  insert into auth.users(id, email) values (o, 'm489-o-' || sfx || '@example.invalid');
  insert into profiles(id, full_name, email, role) values (o, 'M489 Owner', 'm489-o-' || sfx || '@example.invalid', 'owner');
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into stores(name, code, country_code) values ('M489 Store ' || sfx, 'M489' || sfx, 'SG') returning id into st;
  insert into fx values ('A', st);
  insert into warehouses(name, code) values ('M489 Warehouse', 'M489W' || sfx) returning id into wh;
  insert into payment_methods(name, is_active) values ('M489 Cash ' || sfx, true) returning id into v; insert into fx values ('cash', v);
  -- Three fictional phones (+61 2 5550 nnnn) no customer holds.
  ph := array(select '+6125550' || lpad(n::text, 4, '0') from generate_series(1000, 9999) n
               where not exists (select 1 from customers c where public.normalize_customer_phone(c.phone) = '+6125550' || lpad(n::text, 4, '0'))
               order by n limit 3);
  -- An upline affiliate, an affiliate they referred, and a buyer that affiliate referred.
  insert into customers(full_name, phone) values ('M489 Upline', ph[1]) returning id into t2;
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (t2, 'active', now(), 'M489U' || upper(sfx));
  insert into customers(full_name, phone, referred_by) values ('M489 Affiliate', ph[2], t2) returning id into t1;
  insert into customer_affiliates(customer_id, status, activated_at, referral_code) values (t1, 'active', now(), 'M489A' || upper(sfx));
  insert into customers(full_name, phone, referred_by) values ('M489 Buyer', ph[3], t1) returning id into b;
  insert into fx values ('t1', t1), ('t2', t2), ('buyer', b);
  -- Machines of each type, and the same third-party machine as a product line.
  insert into products(name, sku, product_type) values ('M489 Own Machine', 'M489MO-' || sfx, 'own') returning id into v; insert into fx values ('m_own', v);
  insert into products(name, sku, product_type) values ('M489 Partner Machine', 'M489MT-' || sfx, 'third_party') returning id into v; insert into fx values ('m_third', v);
  insert into store_inventory(store_id, product_id, current_qty) values (st, v, 100);
  perform set_product_prices(st, v, 1000, 1000, 'available');
  insert into products(name, sku, product_type) values ('M489 Fee Machine', 'M489MN-' || sfx, 'no_commission') returning id into v; insert into fx values ('m_nc', v);
  insert into products(name, sku, product_type) values ('M489 Lamp', 'M489L-' || sfx, 'own') returning id into v; insert into fx values ('lamp', v);
  insert into store_inventory(store_id, product_id, current_qty) values (st, v, 100);
  perform set_product_prices(st, v, 100, 100, 'available');
  -- Special products: S$1,000 to buy, S$100 a month to rent; linked to each machine, and one to none.
  insert into special_products(name, sku, sale_price, rate_month, is_active, product_id) values ('M489 SP Own', 'M489SO' || sfx, 1000, 100, true, pg_temp.fx('m_own')) returning id into v; insert into fx values ('sp_own', v);
  insert into special_product_stock(special_product_id, warehouse_id, current_qty) values (v, wh, 10);
  insert into special_products(name, sku, sale_price, rate_month, is_active, product_id) values ('M489 SP Partner', 'M489ST' || sfx, 1000, 100, true, pg_temp.fx('m_third')) returning id into v; insert into fx values ('sp_third', v);
  insert into special_product_stock(special_product_id, warehouse_id, current_qty) values (v, wh, 10);
  insert into special_products(name, sku, sale_price, rate_month, is_active, product_id) values ('M489 SP Fee', 'M489SN' || sfx, 1000, 100, true, pg_temp.fx('m_nc')) returning id into v; insert into fx values ('sp_nc', v);
  insert into special_product_stock(special_product_id, warehouse_id, current_qty) values (v, wh, 10);
  insert into special_products(name, sku, sale_price, rate_month, is_active) values ('M489 SP Unlinked', 'M489SX' || sfx, 1000, 100, true) returning id into v; insert into fx values ('sp_none', v);
  insert into special_product_stock(special_product_id, warehouse_id, current_qty) values (v, wh, 10);
  insert into vouchers(name, code, voucher_kind, discount_amount, qty_type, is_active)
    values ('M489 10 off', 'M489F-' || sfx, 'fixed_discount', 10, 'unlimited', true) returning id into v; insert into fx values ('v10', v);
end $$;

-- ═════ M0 Before 489 ═════
do $$
declare inv uuid;
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sp('sp_third')));
  insert into fx values ('m0', inv); perform pg_temp.pay(inv);
  perform pg_temp.check(pg_temp.earned(inv) = 'own 1000.00/150.00' and pg_temp.earned(inv, 'tier2') = 'own 150.00/52.50',
    'M0 before 489 a third-party machine sold as a special product earns as ours (got ' || pg_temp.earned(inv) || ' / ' || pg_temp.earned(inv, 'tier2') || ')');
end $$;

\ir ../../../supabase/489_machines_earn_like_the_machine.sql
-- M0's sale was made before the change: back-date it a day, as a real sale
-- of yesterday. Every invoice in this one transaction has the same creation
-- time, and invoice_created_at_immutable refuses the app a change, so the
-- triggers are off for this statement alone.
set local session_replication_role = replica;
update public.invoices set created_at = created_at - interval '1 day' where id = pg_temp.fx('m0');
set local session_replication_role = origin;

-- ═════ M1 The old sale recalculated after the change keeps its rule ═════
do $$
declare inv uuid := pg_temp.fx('m0');
begin
  perform public.reconcile_invoice_commissions(inv, 'M489 recalculation after the change');
  perform pg_temp.check(pg_temp.earned(inv) = 'own 1000.00/150.00' and pg_temp.earned(inv, 'tier2') = 'own 150.00/52.50',
    'M1 the old sale, recalculated after 489, still earns S$150.00 / S$52.50 (got ' || pg_temp.earned(inv) || ' / ' || pg_temp.earned(inv, 'tier2') || ')');
  perform pg_temp.check(pg_temp.previewed(inv) = 'own 1000.00/150.00', 'M1 and its preview says the same (got ' || pg_temp.previewed(inv) || ')');
end $$;

-- ═════ M2-M6 New sales ═════
do $$
declare inv uuid;
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sp('sp_third'))); insert into fx values ('m2', inv); perform pg_temp.pay(inv);
  perform pg_temp.check(pg_temp.earned(inv) = 'third_party 1000.00/45.00' and pg_temp.earned(inv, 'tier2') = 'third_party 45.00/15.75',
    'M2 a third-party machine sold as a special product now earns S$45.00 / S$15.75 (got ' || pg_temp.earned(inv) || ' / ' || pg_temp.earned(inv, 'tier2') || ')');

  inv := pg_temp.mk(jsonb_build_array(pg_temp.rent('sp_third'))); insert into fx values ('m3', inv); perform pg_temp.pay(inv);
  perform pg_temp.check(pg_temp.earned(inv) = 'third_party 100.00/4.50' and pg_temp.earned(inv, 'tier2') = 'third_party 4.50/1.58',
    'M3 a month''s rental of it earns S$4.50 / S$1.58 (got ' || pg_temp.earned(inv) || ' / ' || pg_temp.earned(inv, 'tier2') || ')');

  inv := pg_temp.mk(jsonb_build_array(pg_temp.sp('sp_own'))); insert into fx values ('m4', inv); perform pg_temp.pay(inv);
  perform pg_temp.check(pg_temp.earned(inv) = 'own 1000.00/150.00' and pg_temp.earned(inv, 'tier2') = 'own 150.00/52.50',
    'M4 our own machine as a special product: our rate, as before (got ' || pg_temp.earned(inv) || ')');

  inv := pg_temp.mk(jsonb_build_array(pg_temp.sp('sp_nc'))); insert into fx values ('m5', inv); perform pg_temp.pay(inv);
  perform pg_temp.check(pg_temp.earned(inv) = '-' and pg_temp.earned(inv, 'tier2') = '-',
    'M5 a no-commission machine earns nothing (got ' || pg_temp.earned(inv) || ')');

  inv := pg_temp.mk(jsonb_build_array(pg_temp.sp('sp_none'))); insert into fx values ('m6', inv); perform pg_temp.pay(inv);
  perform pg_temp.check(pg_temp.earned(inv) = 'own 1000.00/150.00',
    'M6 a special product linked to no machine stays ours (got ' || pg_temp.earned(inv) || ')');
end $$;

-- ═════ M7 The Discount Voucher, as for the same machine sold as a product ═════
do $$
declare a uuid; b uuid;
begin
  a := pg_temp.mk(jsonb_build_array(pg_temp.prod('lamp'), pg_temp.sp('sp_third')), jsonb_build_object('discount_voucher_id', pg_temp.fx('v10')));
  insert into fx values ('m7a', a); perform pg_temp.pay(a);
  b := pg_temp.mk(jsonb_build_array(pg_temp.prod('lamp'), pg_temp.prod('m_third')), jsonb_build_object('discount_voucher_id', pg_temp.fx('v10')));
  insert into fx values ('m7b', b); perform pg_temp.pay(b);
  perform pg_temp.check(pg_temp.earned(a) = 'own 90.00/13.50, third_party 1000.00/45.00',
    'M7 the S$10 voucher falls on the lamp alone, as beside a third-party product (got ' || pg_temp.earned(a) || ')');
  perform pg_temp.check(pg_temp.earned(a) = pg_temp.earned(b) and pg_temp.earned(a, 'tier2') = pg_temp.earned(b, 'tier2'),
    'M7 the machine as a special product earns what it earns as a product line (' || pg_temp.earned(a) || ' vs ' || pg_temp.earned(b) || ')');
end $$;

-- ═════ M8 Part-paid ═════
do $$
declare inv uuid;
begin
  inv := pg_temp.mk(jsonb_build_array(pg_temp.sp('sp_third'))); insert into fx values ('m8', inv);
  perform pg_temp.pay(inv, 500);
  perform pg_temp.check(pg_temp.earned(inv) = 'third_party 500.00/22.50',
    'M8 half paid: half the third-party commission (got ' || pg_temp.earned(inv) || ')');
  perform pg_temp.pay(inv);
  perform pg_temp.check(pg_temp.earned(inv) = 'third_party 1000.00/45.00' and pg_temp.earned(inv, 'tier2') = 'third_party 45.00/15.75',
    'M8 settled: S$45.00 / S$15.75, as paying at once (got ' || pg_temp.earned(inv) || ' / ' || pg_temp.earned(inv, 'tier2') || ')');
end $$;

-- ═════ M9 The preview agrees ═════
do $$
declare k text;
begin
  foreach k in array array['m2','m3','m4','m5','m6','m7a','m7b','m8'] loop
    perform pg_temp.check(pg_temp.previewed(pg_temp.fx(k)) = pg_temp.earned(pg_temp.fx(k))
        and pg_temp.previewed(pg_temp.fx(k), 'tier2') = pg_temp.earned(pg_temp.fx(k), 'tier2'),
      'M9 ' || k || ': the preview shows what was earned (' || pg_temp.previewed(pg_temp.fx(k)) || ' vs ' || pg_temp.earned(pg_temp.fx(k)) || ')');
  end loop;
end $$;

-- ═════ M10 489's UNDO: no cut-off, the old rule for every invoice ═════
do $$
declare v timestamptz;
begin
  select machine_commission_from into v from public.app_settings where id = true;
  update public.app_settings set machine_commission_from = null where id = true;
  perform pg_temp.check(pg_temp.previewed(pg_temp.fx('m2')) = 'own 1000.00/150.00' and pg_temp.previewed(pg_temp.fx('m5')) = 'own 1000.00/150.00',
    'M10 with no cut-off a machine earns as ours again (got ' || pg_temp.previewed(pg_temp.fx('m2')) || ' and ' || pg_temp.previewed(pg_temp.fx('m5')) || ')');
  update public.app_settings set machine_commission_from = v where id = true;
end $$;

-- ═════ M11 Running 489 again changes nothing ═════
create temp table before_rerun as
  select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) m from pg_proc p
   where p.oid in ('public.earn_invoice_commission(uuid)'::regprocedure,
                   'public.invoice_affiliate_commission_preview(uuid)'::regprocedure);
create temp table cutoff_before as select machine_commission_from v from public.app_settings where id = true;
\ir ../../../supabase/489_machines_earn_like_the_machine.sql
do $$
begin
  perform pg_temp.check(not exists (select 1 from before_rerun b
                                     where b.m is distinct from md5(pg_get_functiondef(to_regprocedure('public.' || b.fn))))
      and (select v from cutoff_before) = (select machine_commission_from from public.app_settings where id = true),
    'M11 running 489 again leaves both functions and the cut-off as they were');
end $$;

do $$
declare n int; msgs text;
begin
  select count(*), string_agg(msg, E'\n') into n, msgs from failed;
  if n > 0 then raise exception '% check(s) failed:%', n, E'\n' || msgs; end if;
  raise notice 'ALL PASSED: machines earn like the machine from the cut-off; older sales keep their rule, also when recalculated; part payments and the preview agree; no cut-off is the old rule; 489 re-runs as a no-op';
end $$;
rollback;
