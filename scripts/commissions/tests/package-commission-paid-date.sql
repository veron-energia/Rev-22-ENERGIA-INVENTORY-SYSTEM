-- Package and bundle commission stays in the month the invoice was paid (383).
--
-- Before 383, earn_credit_package_commission and earn_premium_bundle_commission
-- dated their rows sg_today(). Correcting an invoice paid in an earlier month
-- re-earned its package and bundle commission dated the day of the correction
-- (here: Correct Invoice with a new affiliate, which runs
-- reconcile_invoice_commissions), so it jumped into the next month's
-- commission and payouts. The invoice's own lines and staff commission stayed.
--
-- Payments can only happen now, so "paid in an earlier month" is set up the
-- way the other commission suites do it: once settled, the invoice's paid_at
-- and the rows written that day are moved back to the chosen day.
--
-- Run after migration 383. Fixtures only. Disposable database; everything is
-- rolled back.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;

-- As if the invoice had been settled at p_at rather than now: paid_at, and the
-- rows written today, move to the Singapore day of p_at, which is what every
-- earn function writes (383, 384).
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
    why, md5('package-commission-paid-date/' || why || '/' || inv)::uuid);
end $$;

-- Live (earned or paid) commission of an invoice for one beneficiary.
create function pg_temp.live(inv uuid, who uuid) returns numeric language sql as $$
  select coalesce(sum(commission_amount), 0) from commissions
   where invoice_id = inv and referrer_customer_id = who and status in ('earned','paid') $$;

-- The dates of an invoice's live settlement rows for some beneficiaries.
create function pg_temp.dates(inv uuid, who uuid[]) returns date[] language sql as $$
  select array_agg(distinct invoice_paid_date order by invoice_paid_date) from commissions
   where invoice_id = inv and referrer_customer_id = any(who) and status in ('earned','paid')
     and earning_basis = 'settlement' and adjusts_commission_id is null $$;

-- What the invoice holds from the start of this month on, on either ledger.
create function pg_temp.this_month(inv uuid) returns numeric language sql as $$
  select coalesce((select sum(abs(commission_amount)) from commissions where invoice_id = inv and status in ('earned','paid')
                     and invoice_paid_date >= date_trunc('month', sg_today()::timestamp)::date), 0)
       + coalesce((select sum(abs(commission_amount)) from staff_commissions where invoice_id = inv and status in ('earned','paid')
                     and invoice_paid_date >= date_trunc('month', sg_today()::timestamp)::date), 0) $$;

create function pg_temp.balance(who uuid, mon date) returns numeric language sql as $$
  select coalesce((select balance from affiliate_month_balances() where referrer = who and month = mon), 0) $$;

-- ═════ Fixtures ═════
-- Each scenario n has its own buyer n, affiliate a n (first chosen), affiliate
-- b n (the correction's), whose referrer r n earns tier 2. All are active
-- affiliates. Scenarios never share a beneficiary, so month balances are
-- theirs alone.
do $$
declare own uuid := gen_random_uuid(); s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid();
 st uuid; m uuid; p uuid; cp uuid; pb uuid; n int; ca uuid; cb uuid; cr uuid; cu uuid; x uuid;
begin
 insert into auth.users(id,email) values (own,'pcd-own@tests.invalid'),(s1,'pcd-s1@tests.invalid'),(s2,'pcd-s2@tests.invalid');
 insert into profiles(id,full_name,email,role) values (own,'PCD Owner','pcd-own@tests.invalid','owner'),
   (s1,'PCD Staff A','pcd-s1@tests.invalid','staff'),(s2,'PCD Staff B','pcd-s2@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub', own::text, true);
 insert into stores(name,code,country_code) values ('PCD Store','PCDS','SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values (s1,st),(s2,st);
 for n in 1..5 loop
   insert into customers(full_name,phone) values ('PCD Affiliate A'||n, '+65989361'||n||'1') returning id into ca;
   insert into customers(full_name,phone) values ('PCD Referrer R'||n, '+65989361'||n||'2') returning id into cr;
   insert into customers(full_name,phone,referred_by) values ('PCD Affiliate B'||n, '+65989361'||n||'3', cr) returning id into cb;
   insert into customers(full_name,phone) values ('PCD Buyer '||n, '+65989361'||n||'4') returning id into cu;
   insert into fx values ('a'||n, ca), ('b'||n, cb), ('r'||n, cr), ('buyer'||n, cu);
   insert into customer_affiliates(customer_id,status,store_id,activated_at) values (ca,'active',st,now()) returning id into x;
   insert into fx values ('affa'||n, x);
   insert into customer_affiliates(customer_id,status,store_id,activated_at) values (cb,'active',st,now()) returning id into x;
   insert into fx values ('affb'||n, x);
   insert into customer_affiliates(customer_id,status,store_id,activated_at) values (cr,'active',st,now());
 end loop;
 insert into payment_methods(name,is_active) values ('PCD Cash',true) returning id into m;
 insert into products(name,sku,product_type) values ('PCD Item','PCDI','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values (st,p,50);
 perform set_product_prices(st,p,100,100,'available');
 insert into credit_packages(name,customer_price,paid_credit_amount,allow_product,allow_therapy)
   values ('PCD Package',1000,1000,true,true) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values (cp,st);
 insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,bonus_credit_amount,free_voucher_qty,grants_reward)
   values ('PCD Bundle',2000,2000,200,0,false) returning id into pb;
 insert into premium_bundle_stores(bundle_id,store_id) values (pb,st);
 -- Production's rates and switch (3 Oct 2026): part payments earn as they arrive.
 update app_settings set staff_commission_rate=3, commission_tier1_own_rate=15, commission_tier2_own_rate=35,
   commission_tier1_third_rate=4.5, commission_tier2_third_rate=35,
   instalment_commission_from=sg_today() - 100 where id=true;
 insert into fx values ('own',own),('st',st),('m',m),('p',p),('cp',cp),('pb',pb);
end $$;

-- ═════ 1. A package (with a product line) paid last month, its affiliate corrected now ═════
do $$
declare st uuid := pg_temp.fx('st'); m uuid := pg_temp.fx('m');
 a uuid := pg_temp.fx('a1'); b uuid := pg_temp.fx('b1'); r uuid := pg_temp.fx('r1');
 inv uuid; d date := sg_today() - 40; mon date; before_total numeric;
begin
 mon := date_trunc('month', d::timestamp)::date;
 inv := create_invoice(st, pg_temp.fx('buyer1'), pg_temp.fx('affa1'), jsonb_build_array(
          jsonb_build_object('kind','product','product_id',pg_temp.fx('p'),'quantity',1),
          jsonb_build_object('kind','credit_package','credit_package_id',pg_temp.fx('cp'),'quantity',1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
 perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',1100)), gen_random_uuid());
 perform pg_temp.check((select status from invoices where id = inv) = 'paid'
    and exists (select 1 from credit_package_sales where invoice_id = inv),
   '1: the invoice is paid in full and the package is sold');
 perform pg_temp.check(pg_temp.live(inv, a) = 60,
   format('1: A earns 45.00 on the package (4.5%%) and 15.00 on the product (15%%), got %s', pg_temp.live(inv, a)));
 perform pg_temp.settled_at(inv, (d + time '15:00') at time zone 'Asia/Singapore');
 select sum(commission_amount) into before_total from commissions where invoice_id = inv and status = 'earned' and tier = 'tier1';

 perform pg_temp.switch_affiliate(inv, pg_temp.fx('affb1'), 'Affiliate was B');

 perform pg_temp.check(pg_temp.live(inv, a) = 0, '1: A''s unpaid commission is reversed');
 perform pg_temp.check(pg_temp.live(inv, b) = 60 and pg_temp.live(inv, r) = 21,
   format('1: B earns the same 60.00 and R tier 2 15.75 + 5.25, got %s / %s', pg_temp.live(inv, b), pg_temp.live(inv, r)));
 perform pg_temp.check(pg_temp.dates(inv, array[b, r]) = array[d],
   format('1: B''s and R''s rows, package and product alike, keep the paid date %s, got %s', d, pg_temp.dates(inv, array[b, r])));
 perform pg_temp.check(pg_temp.this_month(inv) = 0,
   format('1: nothing of the invoice moved into this month (%s held here)', pg_temp.this_month(inv)));
 perform pg_temp.check(pg_temp.balance(b, mon) = 60
    and not exists (select 1 from affiliate_month_balances() where referrer in (b, r) and month > mon),
   '1: B''s 60.00 is in the paid month''s balance and in no later month');
 perform pg_temp.check((select sum(commission_amount) from commissions where invoice_id = inv and status = 'earned' and tier = 'tier1') = before_total,
   '1: tier 1 is the same total, moved from A to B within the month');
end $$;

-- ═════ 2. A bundle paid last month and already paid out, its affiliate corrected now ═════
do $$
declare st uuid := pg_temp.fx('st'); m uuid := pg_temp.fx('m');
 a uuid := pg_temp.fx('a2'); b uuid := pg_temp.fx('b2'); r uuid := pg_temp.fx('r2');
 inv uuid; d date := sg_today() - 45; mon date; v_paid uuid;
begin
 mon := date_trunc('month', d::timestamp)::date;
 inv := create_invoice(st, pg_temp.fx('buyer2'), pg_temp.fx('affa2'), jsonb_build_array(
          jsonb_build_object('kind','premium_bundle','premium_bundle_id',pg_temp.fx('pb'),'quantity',1,'voucher_selection','[]'::jsonb)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
 perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',2000)), gen_random_uuid());
 perform pg_temp.check(exists (select 1 from premium_bundle_sales where invoice_id = inv) and pg_temp.live(inv, a) = 90,
   format('2: the bundle is sold and A earns 90.00 (4.5%% of 2000), got %s', pg_temp.live(inv, a)));
 perform pg_temp.settled_at(inv, (d + time '15:00') at time zone 'Asia/Singapore');
 perform record_affiliate_payout(a, mon, pg_temp.balance(a, mon), m, sg_today(), 'PCD payout', null, gen_random_uuid());
 select id into v_paid from commissions where invoice_id = inv and referrer_customer_id = a and status = 'paid';
 perform pg_temp.check(v_paid is not null and pg_temp.balance(a, mon) = 0, '2: A is paid out the paid month''s 90.00');

 perform pg_temp.switch_affiliate(inv, pg_temp.fx('affb2'), 'Affiliate was B after payout');

 -- 410 (the Owner, 3 Oct 2026): commission already paid out and then taken
 -- back is recovered from A's later commission, so A's take-back is dated the
 -- day of the correction and the month already paid stays as it was paid.
 -- Before 410 it was dated in the paid month (A at -90.00 there).
 perform pg_temp.check((select status from commissions where id = v_paid) = 'paid'
    and (select invoice_paid_date from commissions where adjusts_commission_id = v_paid and commission_amount = -90
          and status = 'earned') = sg_today(),
   '2: A''s paid row stands and is taken back by a -90.00 adjustment dated today (410)');
 perform pg_temp.check(pg_temp.live(inv, b) = 90 and pg_temp.live(inv, r) = 31.50, '2: B earns 90.00 and R tier 2 31.50');
 perform pg_temp.check(pg_temp.dates(inv, array[b, r]) = array[d],
   format('2: the re-earned bundle rows keep the paid date %s, got %s', d, pg_temp.dates(inv, array[b, r])));
 perform pg_temp.check(pg_temp.this_month(inv) = 90,
   format('2: of the invoice, only A''s take-back is in this month (%s held here)', pg_temp.this_month(inv)));
 perform pg_temp.check(pg_temp.balance(b, mon) = 90 and pg_temp.balance(a, mon) = 0
    and pg_temp.balance(a, date_trunc('month', sg_today()::timestamp)::date) = -90,
   '2: the paid month: B is owed 90.00 and A''s stays as paid; A gives back the 90.00 from this month (410)');
end $$;

-- ═════ 3. A bundle paid in two parts over two months, its affiliate corrected now ═════
do $$
declare st uuid := pg_temp.fx('st'); m uuid := pg_temp.fx('m');
 a uuid := pg_temp.fx('a3'); b uuid := pg_temp.fx('b3'); r uuid := pg_temp.fx('r3');
 inv uuid; d1 date := sg_today() - 75; d2 date := sg_today() - 40; m1 date; m2 date; v_months jsonb;
begin
 m1 := date_trunc('month', d1::timestamp)::date; m2 := date_trunc('month', d2::timestamp)::date;
 inv := create_invoice(st, pg_temp.fx('buyer3'), pg_temp.fx('affa3'), jsonb_build_array(
          jsonb_build_object('kind','premium_bundle','premium_bundle_id',pg_temp.fx('pb'),'quantity',1,'voucher_selection','[]'::jsonb)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
 -- 500 in the first month: paid credit released, commission on the part payment
 perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',500)), gen_random_uuid());
 perform pg_temp.check((select status from invoices where id = inv) = 'partially_paid'
    and not exists (select 1 from premium_bundle_sales where invoice_id = inv)
    and (select coalesce(sum(commission_amount),0) from commissions where invoice_id = inv and referrer_customer_id = a
          and earning_basis = 'instalment' and status = 'earned') = 22.50,
   '3: 500 of 2000 earns A 22.50 on the part-payment layer; the bundle is not sold yet');
 perform pg_temp.part_paid_on(inv, d1);
 -- the other 1500 the next month: sold, settled, the part-payment layer closed
 perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',1500)), gen_random_uuid());
 perform pg_temp.check((select status from invoices where id = inv) = 'paid' and pg_temp.live(inv, a) = 90,
   format('3: paid in full, A holds the full 90.00, got %s', pg_temp.live(inv, a)));
 perform pg_temp.settled_at(inv, (d2 + time '15:00') at time zone 'Asia/Singapore');
 perform pg_temp.check(pg_temp.balance(a, m1) = 22.50 and pg_temp.balance(a, m2) = 67.50,
   '3: before the correction A has 22.50 in the part-payment month and 67.50 in the paid-off month');
 select jsonb_object_agg(mo, t) into v_months from (
   select date_trunc('month', invoice_paid_date::timestamp)::date as mo, sum(commission_amount) as t
     from commissions where invoice_id = inv and status in ('earned','paid') and tier = 'tier1' group by 1) q;

 perform pg_temp.switch_affiliate(inv, pg_temp.fx('affb3'), 'Affiliate was B for the bundle');

 perform pg_temp.check(pg_temp.dates(inv, array[b, r]) = array[d2],
   format('3: B''s and R''s rows keep the paid-off date %s, the day the part payments closed, got %s', d2, pg_temp.dates(inv, array[b, r])));
 perform pg_temp.check(pg_temp.live(inv, b) = 90 and pg_temp.live(inv, r) = 31.50 and pg_temp.live(inv, a) = 0,
   '3: B earns the full 90.00 and R 31.50; A keeps nothing overall');
 perform pg_temp.check(pg_temp.balance(a, m1) = 22.50 and pg_temp.balance(a, m2) = -22.50,
   '3: A''s part-payment row and its close stay where they were (22.50, then -22.50)');
 perform pg_temp.check(v_months = (select jsonb_object_agg(mo, t) from (
     select date_trunc('month', invoice_paid_date::timestamp)::date as mo, sum(commission_amount) as t
       from commissions where invoice_id = inv and status in ('earned','paid') and tier = 'tier1' group by 1) q),
   format('3: every month''s tier 1 total is what it was before the correction (%s)', v_months));
 perform pg_temp.check(pg_temp.this_month(inv) = 0,
   format('3: nothing of the invoice moved into this month (%s held here)', pg_temp.this_month(inv)));
end $$;

-- ═════ 4. Paid at 07:30 on the 1st (Singapore), still the month before in UTC ═════
do $$
declare st uuid := pg_temp.fx('st'); m uuid := pg_temp.fx('m');
 a uuid := pg_temp.fx('a4'); b uuid := pg_temp.fx('b4'); r uuid := pg_temp.fx('r4');
 inv uuid; d date := date_trunc('month', (sg_today() - 40)::timestamp)::date; v_at timestamptz;
begin
 v_at := (d + time '07:30') at time zone 'Asia/Singapore';
 perform pg_temp.check((v_at at time zone 'UTC')::date = d - 1,
   '4: 07:30 on the 1st in Singapore is the last day of the month before in UTC');
 inv := create_invoice(st, pg_temp.fx('buyer4'), pg_temp.fx('affa4'), jsonb_build_array(
          jsonb_build_object('kind','credit_package','credit_package_id',pg_temp.fx('cp'),'quantity',1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
 perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',1000)), gen_random_uuid());
 perform pg_temp.settled_at(inv, v_at);
 perform pg_temp.check(pg_temp.dates(inv, array[a]) = array[d],
   '4: as first earned, the package commission is dated the 1st (sg_today() at the time)');

 perform pg_temp.switch_affiliate(inv, pg_temp.fx('affb4'), 'Affiliate was B, paid early');

 perform pg_temp.check(pg_temp.live(inv, b) = 45 and pg_temp.dates(inv, array[b, r]) = array[d],
   format('4: re-earned it is still dated the 1st, the Singapore day it was paid (not the UTC day before, not today), got %s',
     pg_temp.dates(inv, array[b, r])));
end $$;

-- ═════ 5. What does not change ═════
do $$
declare st uuid := pg_temp.fx('st'); m uuid := pg_temp.fx('m');
 a uuid := pg_temp.fx('a5'); b uuid := pg_temp.fx('b5'); inv uuid; inv2 uuid;
begin
 -- Settled now: dated today, as before.
 inv := create_invoice(st, pg_temp.fx('buyer5'), pg_temp.fx('affa5'), jsonb_build_array(
          jsonb_build_object('kind','credit_package','credit_package_id',pg_temp.fx('cp'),'quantity',1)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
 perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',1000)), gen_random_uuid());
 inv2 := create_invoice(st, pg_temp.fx('buyer5'), pg_temp.fx('affa5'), jsonb_build_array(
          jsonb_build_object('kind','premium_bundle','premium_bundle_id',pg_temp.fx('pb'),'quantity',1,'voucher_selection','[]'::jsonb)),
        0::numeric, null::text, null::uuid, '[]'::jsonb);
 perform record_invoice_payment(inv2, jsonb_build_array(jsonb_build_object('payment_method_id',m,'amount',2000)), gen_random_uuid());
 perform pg_temp.check(pg_temp.dates(inv, array[a]) = array[sg_today()] and pg_temp.dates(inv2, array[a]) = array[sg_today()]
    and pg_temp.live(inv, a) = 45 and pg_temp.live(inv2, a) = 90,
   '5: a package and a bundle settled today earn 45.00 and 90.00 dated today, as before');
 -- No paid date at all (not reachable through the app): today, as before.
 update invoices set paid_at = null where id = inv;
 perform pg_temp.switch_affiliate(inv, pg_temp.fx('affb5'), 'Affiliate was B, no paid date');
 perform pg_temp.check(pg_temp.live(inv, b) = 45 and pg_temp.dates(inv, array[b]) = array[sg_today()],
   '5: an invoice without a paid date still earns on today''s date');
end $$;

rollback;
