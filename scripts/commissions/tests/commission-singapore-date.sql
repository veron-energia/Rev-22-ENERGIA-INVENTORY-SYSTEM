-- Invoice-line and staff commission are dated the Singapore day the invoice was
-- paid (384).
--
-- Before 384, earn_invoice_commission, earn_staff_commission and
-- reearn_invoice_staff_commission dated their rows paid_at::date: the UTC day,
-- which for a payment made before 08:00 in Singapore is the day before. On the
-- 1st of a month that is the previous month, while package and bundle
-- commission (383) and the part-payment close (357) carry the Singapore day.
-- One invoice ended up split across two months.
--
-- Earning happens now, so "paid at 07:30 on the 1st" is set up the way the
-- other commission suites do it: once settled, the invoice's paid_at and the
-- rows written that day move to that moment. The rows earned again afterwards
-- (Correct Invoice, the staff rebase) are what is checked.
--
-- Run after migration 384. Fixtures only. Disposable database; everything is
-- rolled back.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;

-- As if the invoice had been settled at p_at rather than now: paid_at, and the
-- rows written today, move to the Singapore day of p_at.
create function pg_temp.settled_at(inv uuid, p_at timestamptz) returns void language plpgsql as $$
declare d date := (p_at at time zone 'Asia/Singapore')::date;
        today date := least(sg_today(), (now() at time zone 'UTC')::date);
begin
  update invoices set paid_at = p_at where id = inv;
  update commissions set invoice_paid_date = d where invoice_id = inv and invoice_paid_date >= today;
  update staff_commissions set invoice_paid_date = d where invoice_id = inv and invoice_paid_date >= today;
end $$;

-- As if a part payment had been registered on day d (no settlement yet).
create function pg_temp.part_paid_on(inv uuid, d date) returns void language plpgsql as $$
declare today date := least(sg_today(), (now() at time zone 'UTC')::date);
begin
  update commissions set invoice_paid_date = d where invoice_id = inv and invoice_paid_date >= today;
  update staff_commissions set invoice_paid_date = d where invoice_id = inv and invoice_paid_date >= today;
end $$;

-- The invoice's lines exactly as they are, for a correction that changes only
-- the header (invoice_all_lines_match is checked before each correction).
create function pg_temp.same_lines(inv uuid) returns jsonb language sql as $$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'invoice_item_id', it.id, 'kind', it.line_kind::text, 'quantity', it.quantity,
           'product_id', it.product_id, 'credit_package_id', it.credit_package_id,
           'premium_bundle_id', it.premium_bundle_id, 'unit_price', it.unit_price,
           'voucher_selection', case when it.line_kind = 'premium_bundle'
                                     then coalesce(it.bundle_voucher_selection, '[]'::jsonb) end)) order by it.id)
    from invoice_items it where it.invoice_id = inv $$;

-- Correct Invoice, as the owner, with a new affiliate and the lines unchanged.
create function pg_temp.switch_affiliate(inv uuid, aff uuid, why text) returns jsonb language plpgsql as $$
begin
  perform pg_temp.check(invoice_all_lines_match(inv, pg_temp.same_lines(inv)),
    format('%s: the correction keeps every line as it is', why));
  return correct_invoice(inv, pg_temp.same_lines(inv),
    jsonb_build_object('affiliate_id', aff, 'expected_edit_count', (select coalesce(edit_count,0) from invoices where id = inv)),
    why, md5('commission-singapore-date/' || why || '/' || inv)::uuid);
end $$;

-- Live (earned or paid) commission of an invoice for one beneficiary.
create function pg_temp.live(inv uuid, who uuid) returns numeric language sql as $$
  select coalesce(sum(commission_amount), 0) from commissions
   where invoice_id = inv and referrer_customer_id = who and status in ('earned','paid') $$;

-- The dates of an invoice's live settlement rows: affiliate rows of some
-- beneficiaries, or (who = null) its staff rows.
create function pg_temp.dates(inv uuid, who uuid[]) returns date[] language sql as $$
  select array_agg(distinct invoice_paid_date order by invoice_paid_date) from commissions
   where invoice_id = inv and referrer_customer_id = any(who) and status in ('earned','paid')
     and earning_basis = 'settlement' and adjusts_commission_id is null $$;
create function pg_temp.staff_dates(inv uuid) returns date[] language sql as $$
  select array_agg(distinct invoice_paid_date order by invoice_paid_date) from staff_commissions
   where invoice_id = inv and status in ('earned','paid') and earning_basis = 'settlement' $$;

-- What the invoice holds, on either ledger, dated in [p_from, p_to].
create function pg_temp.held_between(inv uuid, p_from date, p_to date) returns numeric language sql as $$
  select coalesce((select sum(abs(commission_amount)) from commissions where invoice_id = inv and status in ('earned','paid')
                     and invoice_paid_date between p_from and p_to), 0)
       + coalesce((select sum(abs(commission_amount)) from staff_commissions where invoice_id = inv and status in ('earned','paid')
                     and invoice_paid_date between p_from and p_to), 0) $$;
create function pg_temp.this_month(inv uuid) returns numeric language sql as $$
  select pg_temp.held_between(inv, date_trunc('month', sg_today()::timestamp)::date, 'infinity'::date) $$;

-- Per month: the invoice's tier 1 total and its staff total.
create function pg_temp.months(inv uuid) returns jsonb language sql as $$
  select jsonb_build_object(
    'tier1', (select jsonb_object_agg(mo, t) from (
               select date_trunc('month', invoice_paid_date::timestamp)::date as mo, sum(commission_amount) as t
                 from commissions where invoice_id = inv and status in ('earned','paid') and tier = 'tier1' group by 1) q),
    'staff', (select jsonb_object_agg(mo, t) from (
               select date_trunc('month', invoice_paid_date::timestamp)::date as mo, sum(commission_amount) as t
                 from staff_commissions where invoice_id = inv and status in ('earned','paid') group by 1) q)) $$;

-- ═════ Fixtures ═════
-- Each scenario n has its own buyer n, affiliate a n (first chosen) and
-- affiliate b n (the correction's), whose referrer r n earns tier 2. All are
-- active affiliates. Two staff share the store's staff commission.
do $$
declare own uuid := gen_random_uuid(); s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid();
 st uuid; m uuid; p uuid; cp uuid; n int; ca uuid; cb uuid; cr uuid; cu uuid; x uuid;
begin
 insert into auth.users(id,email) values (own,'csd-own@tests.invalid'),(s1,'csd-s1@tests.invalid'),(s2,'csd-s2@tests.invalid');
 insert into profiles(id,full_name,email,role) values (own,'CSD Owner','csd-own@tests.invalid','owner'),
   (s1,'CSD Staff A','csd-s1@tests.invalid','staff'),(s2,'CSD Staff B','csd-s2@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub', own::text, true);
 insert into stores(name,code,country_code) values ('CSD Store','CSDS','SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values (s1,st),(s2,st);
 for n in 1..5 loop
   insert into customers(full_name,phone) values ('CSD Affiliate A'||n, '+65989371'||n||'1') returning id into ca;
   insert into customers(full_name,phone) values ('CSD Referrer R'||n, '+65989371'||n||'2') returning id into cr;
   insert into customers(full_name,phone,referred_by) values ('CSD Affiliate B'||n, '+65989371'||n||'3', cr) returning id into cb;
   insert into customers(full_name,phone) values ('CSD Buyer '||n, '+65989371'||n||'4') returning id into cu;
   insert into fx values ('a'||n, ca), ('b'||n, cb), ('r'||n, cr), ('buyer'||n, cu);
   insert into customer_affiliates(customer_id,status,store_id,activated_at) values (ca,'active',st,now()) returning id into x;
   insert into fx values ('affa'||n, x);
   insert into customer_affiliates(customer_id,status,store_id,activated_at) values (cb,'active',st,now()) returning id into x;
   insert into fx values ('affb'||n, x);
   insert into customer_affiliates(customer_id,status,store_id,activated_at) values (cr,'active',st,now());
 end loop;
 insert into payment_methods(name,is_active) values ('CSD Cash',true) returning id into m;
 insert into products(name,sku,product_type) values ('CSD Item','CSDI','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values (st,p,50);
 perform set_product_prices(st,p,100,100,'available');
 insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy)
   values ('CSD Package',1000,1000,true,true) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values (cp,st);
 -- Production's rates and switch (3 Oct 2026): part payments earn as they arrive.
 update app_settings set staff_commission_rate=3, commission_tier1_own_rate=15, commission_tier2_own_rate=35,
   commission_tier1_third_rate=4.5, commission_tier2_third_rate=35,
   instalment_commission_from=sg_today() - 100 where id=true;
 insert into fx values ('own',own),('st',st),('m',m),('p',p),('cp',cp);
end $$;

-- ═════ 1. Paid at 07:30 on the 1st, corrected later ═════
do $$
declare st uuid := pg_temp.fx('st'); m uuid := pg_temp.fx('m');
 a uuid := pg_temp.fx('a1'); b uuid := pg_temp.fx('b1'); r uuid := pg_temp.fx('r1');
 inv uuid; d date := date_trunc('month', (sg_today() - 40)::timestamp)::date; v_at timestamptz;
begin
 v_at := (d + time '07:30') at time zone 'Asia/Singapore';
 perform pg_temp.check((v_at at time zone 'UTC')::date = d - 1,
   '1: 07:30 on the 1st in Singapore is the last day of the month before in UTC');
 inv := create_invoice(st, pg_temp.fx('buyer1'), pg_temp.fx('affa1'), jsonb_build_array(
          jsonb_build_object('kind','product','product_id',pg_temp.fx('p'),'quantity',1),
          jsonb_build_object('kind','credit_package','credit_package_id',pg_temp.fx('cp'),'quantity',1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
 perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',1100)), gen_random_uuid());
 perform pg_temp.check(pg_temp.live(inv, a) = 60 and pg_temp.staff_dates(inv) is not null,
   format('1: paid in full: A earns 15.00 on the product and 45.00 on the package, staff are paid, got %s', pg_temp.live(inv, a)));
 perform pg_temp.settled_at(inv, v_at);

 perform pg_temp.switch_affiliate(inv, pg_temp.fx('affb1'), 'Affiliate was B');

 perform pg_temp.check(pg_temp.live(inv, b) = 60 and pg_temp.live(inv, r) = 21,
   format('1: B earns 60.00 and R tier 2 21.00, got %s / %s', pg_temp.live(inv, b), pg_temp.live(inv, r)));
 perform pg_temp.check(pg_temp.dates(inv, array[b, r]) = array[d],
   format('1: B''s and R''s rows, product and package alike, are dated the 1st, the Singapore day it was paid, got %s',
     pg_temp.dates(inv, array[b, r])));
 perform pg_temp.check(pg_temp.staff_dates(inv) = array[d],
   format('1: the staff rows earned again are dated the 1st too, got %s', pg_temp.staff_dates(inv)));
 perform pg_temp.check(pg_temp.held_between(inv, '-infinity'::date, d - 1) = 0,
   format('1: nothing of the invoice is booked in the month before (%s there)', pg_temp.held_between(inv, '-infinity'::date, d - 1)));
 perform pg_temp.check(pg_temp.this_month(inv) = 0, '1: and nothing moved into this month');
end $$;

-- ═════ 2. Paid in two parts, the second at 07:30 on the 1st, corrected later ═════
do $$
declare st uuid := pg_temp.fx('st'); m uuid := pg_temp.fx('m');
 a uuid := pg_temp.fx('a2'); b uuid := pg_temp.fx('b2'); r uuid := pg_temp.fx('r2');
 inv uuid; d date := date_trunc('month', (sg_today() - 40)::timestamp)::date; d1 date; v_at timestamptz; v_months jsonb;
begin
 d1 := d - 45;
 v_at := (d + time '07:30') at time zone 'Asia/Singapore';
 inv := create_invoice(st, pg_temp.fx('buyer2'), pg_temp.fx('affa2'), jsonb_build_array(
          jsonb_build_object('kind','product','product_id',pg_temp.fx('p'),'quantity',10)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
 -- 400 of 1000 two months earlier: A 60.00 and staff 12.00 on the part payment
 perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',400)), gen_random_uuid());
 perform pg_temp.check((select status from invoices where id = inv) = 'partially_paid'
    and (select coalesce(sum(commission_amount),0) from commissions where invoice_id = inv and referrer_customer_id = a
          and earning_basis = 'instalment' and status = 'earned') = 60
    and (select coalesce(sum(commission_amount),0) from staff_commissions where invoice_id = inv
          and earning_basis = 'instalment' and status = 'earned') = 12,
   '2: 400 of 1000 earns A 60.00 and the staff 12.00 on the part-payment layer');
 perform pg_temp.part_paid_on(inv, d1);
 -- the other 600 at 07:30 on the 1st: settled, the part-payment layer closed that day
 perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',600)), gen_random_uuid());
 perform pg_temp.settled_at(inv, v_at);
 perform pg_temp.check(pg_temp.live(inv, a) = 150, format('2: paid in full, A holds 150.00, got %s', pg_temp.live(inv, a)));
 v_months := pg_temp.months(inv);

 perform pg_temp.switch_affiliate(inv, pg_temp.fx('affb2'), 'Affiliate was B, paid in parts');

 perform pg_temp.check(pg_temp.live(inv, b) = 150 and pg_temp.live(inv, r) = 52.50 and pg_temp.live(inv, a) = 0,
   '2: B earns the full 150.00 and R 52.50; A keeps nothing overall');
 perform pg_temp.check(pg_temp.dates(inv, array[b, r]) = array[d],
   format('2: B''s and R''s settlement rows are dated the 1st, the day the part payments closed, got %s', pg_temp.dates(inv, array[b, r])));
 perform pg_temp.check(pg_temp.staff_dates(inv) = array[d],
   format('2: the staff settlement rows are dated the 1st, got %s', pg_temp.staff_dates(inv)));
 perform pg_temp.check(pg_temp.held_between(inv, date_trunc('month', (d - 1)::timestamp)::date, d - 1) = 0,
   format('2: nothing of the invoice is booked in the month before the 1st (%s there)',
     pg_temp.held_between(inv, date_trunc('month', (d - 1)::timestamp)::date, d - 1)));
 perform pg_temp.check(pg_temp.months(inv) = v_months,
   format('2: every month keeps the tier 1 and staff totals it had before the correction (%s)', v_months));
 perform pg_temp.check(pg_temp.this_month(inv) = 0, '2: and nothing moved into this month');
end $$;

-- ═════ 3. The staff rebase of an invoice paid at 07:30 on the 1st ═════
do $$
declare st uuid := pg_temp.fx('st'); m uuid := pg_temp.fx('m');
 inv uuid; d date := date_trunc('month', (sg_today() - 40)::timestamp)::date; v_res jsonb;
begin
 inv := create_invoice(st, pg_temp.fx('buyer3'), null::uuid, jsonb_build_array(
          jsonb_build_object('kind','product','product_id',pg_temp.fx('p'),'quantity',1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
 perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',100)), gen_random_uuid());
 perform pg_temp.settled_at(inv, (d + time '07:30') at time zone 'Asia/Singapore');
 -- what rebase_staff_commissions runs for each invoice it picks by its Singapore paid date
 v_res := reearn_invoice_staff_commission(inv);
 perform pg_temp.check((v_res->>'reversed')::int = 2 and (v_res->>'earned')::int = 2,
   format('3: the rebase replaces both staff rows, got %s', v_res));
 perform pg_temp.check(pg_temp.staff_dates(inv) = array[d]
    and (select sum(commission_amount) from staff_commissions where invoice_id = inv and status = 'earned') = 3,
   format('3: the rebased staff rows (3.00) are dated the 1st, the Singapore day it was paid, got %s', pg_temp.staff_dates(inv)));
end $$;

-- ═════ 4. What does not change ═════
do $$
declare st uuid := pg_temp.fx('st'); m uuid := pg_temp.fx('m');
 a4 uuid := pg_temp.fx('a4'); b4 uuid := pg_temp.fx('b4'); b5 uuid := pg_temp.fx('b5'); r5 uuid := pg_temp.fx('r5');
 inv uuid; inv2 uuid; d date := sg_today() - 40;
begin
 -- Settled now: today, on every row.
 inv := create_invoice(st, pg_temp.fx('buyer4'), pg_temp.fx('affa4'), jsonb_build_array(
          jsonb_build_object('kind','product','product_id',pg_temp.fx('p'),'quantity',1),
          jsonb_build_object('kind','credit_package','credit_package_id',pg_temp.fx('cp'),'quantity',1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
 perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',1100)), gen_random_uuid());
 perform pg_temp.check(pg_temp.dates(inv, array[a4]) = array[sg_today()] and pg_temp.staff_dates(inv) = array[sg_today()],
   '4: an invoice settled now is dated today (Singapore), affiliate and staff rows alike');
 -- Paid in the afternoon: the same day as before (the UTC and Singapore days agree).
 inv2 := create_invoice(st, pg_temp.fx('buyer5'), pg_temp.fx('affa5'), jsonb_build_array(
          jsonb_build_object('kind','product','product_id',pg_temp.fx('p'),'quantity',1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
 perform record_invoice_payment(inv2, jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',100)), gen_random_uuid());
 perform pg_temp.settled_at(inv2, (d + time '15:00') at time zone 'Asia/Singapore');
 perform pg_temp.switch_affiliate(inv2, pg_temp.fx('affb5'), 'Affiliate was B, afternoon');
 perform pg_temp.check(pg_temp.dates(inv2, array[b5, r5]) = array[d] and pg_temp.staff_dates(inv2) = array[d],
   '4: an invoice paid at 15:00 keeps its day when earned again, as before');
 -- No paid date at all (not reachable through the app): today in Singapore.
 update invoices set paid_at = null where id = inv;
 perform pg_temp.switch_affiliate(inv, pg_temp.fx('affb4'), 'Affiliate was B, no paid date');
 perform pg_temp.check(pg_temp.dates(inv, array[b4]) = array[sg_today()] and pg_temp.staff_dates(inv) = array[sg_today()],
   '4: an invoice without a paid date earns on today''s Singapore date');
end $$;

rollback;
