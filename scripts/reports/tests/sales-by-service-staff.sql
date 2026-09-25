-- Sales by Service Staff adds up to revenue, to the cent (358).
--
-- Before 358 the report was assembled in the browser: invoices with no "Served
-- by" were dropped (S$957 on 24 Sep 2026), each person's equal share was a float
-- rounded on its own, and part payments from last month could never be credited
-- to this month. Everything here goes through the real invoice functions.
--
-- Round 2 (a second store, SSR2): last month's money that changes around the
-- registration of earlier part payments.
--   (a) a moved (last-month) receipt removed, or corrected down, after
--       registering: the reversal is credited in the current month with the
--       receipts, no month holds a negative person, and the current month holds
--       exactly what the invoice still holds;
--   (b) a receipt and a refund both last month move NET: the review lists
--       payments minus the refund, and both months reconcile afterwards;
--   (c) the staff sales moved and the commission registered land in the same
--       month, for the same invoices, on the same money.
--
-- Disposable database only; everything is rolled back. Fixtures carry a random
-- suffix so the file can run beside other suites on a shared database.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;
create temp table d(k text primary key, v date);
create function pg_temp.d(key text) returns date language sql as $$ select v from d where k=key $$;
-- A random, valid Singapore mobile (+659 then 0-8: numbers beginning 99 are not issued).
create function pg_temp.phone() returns text language sql volatile as
$$ select '+659' || floor(random() * 9)::int::text || lpad(floor(random() * 1000000)::int::text, 6, '0') $$;
-- The report for the fixture store only.
create function pg_temp.rep(p_from date, p_to date) returns jsonb language sql as
$$ select report_sales_by_service_staff(p_from, p_to, pg_temp.fx('st')) $$;
create function pg_temp.person(r jsonb, who uuid, field text) returns numeric language sql as
$$ select coalesce((select (x->>field)::numeric from jsonb_array_elements(r->'rows') x where (x->>'staff_id')::uuid = who), 0) $$;
create function pg_temp.ledger_revenue(p_from date, p_to date) returns numeric language sql as
$$ select coalesce(sum(l.amount),0) from invoice_sales_ledger() l join invoices i on i.id=l.invoice_id
    where i.store_id=pg_temp.fx('st') and (p_from is null or l.sales_date>=p_from) and (p_to is null or l.sales_date<=p_to) $$;
-- Round 2: the report for the second fixture store.
create function pg_temp.rep2(p_from date, p_to date) returns jsonb language sql as
$$ select report_sales_by_service_staff(p_from, p_to, pg_temp.fx('st2')) $$;
-- Staff sales on one invoice credited in a period (null bounds: all time).
create function pg_temp.inv_sales(inv uuid, p_from date, p_to date) returns numeric language sql as
$$ select coalesce(sum(s.amount),0) from invoice_staff_sales_ledger() s
    where s.invoice_id=inv and (p_from is null or s.credited_on>=p_from) and (p_to is null or s.credited_on<=p_to) $$;
-- (c) Same month, same invoices, same money. For every fixture invoice that
-- holds part-payment staff commission: its rows are dated in the current month,
-- every dollar of its staff sales is credited in the current month, and the
-- commission it holds is the staff rate on exactly those staff sales. And every
-- fixture invoice whose earlier money was moved holds commission dated the day
-- it was credited. Returns the offending invoices, so a failure names them.
create function pg_temp.same_month_problems() returns text language sql as
$$ with fixture as (select i.id, i.invoice_no from invoices i where i.store_id in (pg_temp.fx('st'), pg_temp.fx('st2'))),
        held as (select sc.invoice_id, sum(sc.commission_amount) as held,
                        min(sc.invoice_paid_date) as first_day, max(sc.invoice_paid_date) as last_day
                   from staff_commissions sc join fixture f on f.id=sc.invoice_id
                  where sc.earning_basis='instalment' and sc.status in ('earned','paid')
                  group by sc.invoice_id),
        rate as (select coalesce(a.staff_commission_rate,0) as r from app_settings a where a.id=true),
        bad as (
          select f.invoice_no||': commission '||h.held||' dated '||h.first_day||'..'||h.last_day
                 ||', staff sales this month '||pg_temp.inv_sales(f.id, pg_temp.d('cur_from'), pg_temp.d('cur_to'))
                 ||' of '||pg_temp.inv_sales(f.id, null, null) as msg
            from held h join fixture f on f.id=h.invoice_id cross join rate
           where h.first_day < pg_temp.d('cur_from') or h.last_day > pg_temp.d('cur_to')
              or pg_temp.inv_sales(f.id, pg_temp.d('cur_from'), pg_temp.d('cur_to')) <> pg_temp.inv_sales(f.id, null, null)
              or h.held <> round(pg_temp.inv_sales(f.id, null, null) * rate.r / 100.0, 2)
          union all
          select f.invoice_no||': staff sales moved to '||b.credited_on||' but no part-payment commission dated that day'
            from sales_credit_backfill b join fixture f on f.id=b.invoice_id
           where not exists (select 1 from staff_commissions sc where sc.invoice_id=b.invoice_id
                              and sc.earning_basis='instalment' and sc.invoice_paid_date=b.credited_on))
   select string_agg(msg, '; ' order by msg) from bad $$;
-- People with a negative staff-sales total in any calendar month (by the date
-- credited), on the second store's invoices.
create function pg_temp.negative_months() returns text language sql as
$$ select string_agg(p.full_name||' '||x.m||' '||x.total, '; ' order by p.full_name, x.m)
     from (select s.staff_id, to_char(s.credited_on,'YYYY-MM') as m, sum(s.amount) as total
             from invoice_staff_sales_ledger() s join invoices i on i.id=s.invoice_id
            where i.store_id=pg_temp.fx('st2') group by 1, 2 having sum(s.amount) < 0) x
     left join profiles p on p.id=x.staff_id $$;

insert into d values
  ('prev_from', (date_trunc('month', sg_today()::timestamp) - interval '1 month')::date),
  ('prev_to',   (date_trunc('month', sg_today()::timestamp) - interval '1 day')::date),
  ('prev_paid', (date_trunc('month', sg_today()::timestamp) - interval '1 month')::date + 17),
  ('cur_from',  date_trunc('month', sg_today()::timestamp)::date),
  ('cur_to',    sg_today());

-- ═════ Fixtures ═════
do $$
declare own uuid:=gen_random_uuid(); mgr uuid:=gen_random_uuid(); a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid();
 st uuid; cust uuid; cash uuid; wpm uuid; p10 uuid; p1001 uuid; p1000 uuid; p5000 uuid;
 i1 uuid; i2 uuid; i3 uuid; i4 uuid; i5 uuid; i6 uuid; i7 uuid; i8 uuid; pay uuid; staff3 jsonb;
 sfx text := lpad(floor(random()*10000000)::bigint::text, 7, '0');
begin
 insert into auth.users(id,email) values(own,'ssr-own-'||sfx||'@tests.invalid'),(mgr,'ssr-mgr-'||sfx||'@tests.invalid'),
   (a,'ssr-a-'||sfx||'@tests.invalid'),(b,'ssr-b-'||sfx||'@tests.invalid'),(c,'ssr-c-'||sfx||'@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'SSR Owner','ssr-own-'||sfx||'@tests.invalid','owner'),
   (mgr,'SSR Manager','ssr-mgr-'||sfx||'@tests.invalid','manager'),
   (a,'SSR Staff A','ssr-a-'||sfx||'@tests.invalid','staff'),(b,'SSR Staff B','ssr-b-'||sfx||'@tests.invalid','staff'),
   (c,'SSR Staff C','ssr-c-'||sfx||'@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 -- Earlier part payments can only be registered while part-payment commission is off.
 update app_settings set instalment_commission_from = null where id = true;
 insert into stores(name,code,country_code) values('SSR Store '||sfx,'SSRS'||sfx,'SG') returning id into st;
 insert into user_store_assignments(user_id,store_id) values(mgr,st),(a,st),(b,st),(c,st);
 insert into customers(full_name,phone) values('SSR Buyer',pg_temp.phone()) returning id into cust;
 insert into payment_methods(name,is_active) values('SSR Cash '||sfx,true) returning id into cash;
 select id into wpm from payment_methods where wallet_category='paid' and is_system limit 1;
 insert into products(name,sku,product_type) values('SSR 10.00','SSR10-'||sfx,'own') returning id into p10;
 insert into products(name,sku,product_type) values('SSR 10.01','SSR1001-'||sfx,'own') returning id into p1001;
 insert into products(name,sku,product_type) values('SSR 1000','SSR1000-'||sfx,'own') returning id into p1000;
 insert into products(name,sku,product_type) values('SSR 5000','SSR5000-'||sfx,'own') returning id into p5000;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p10,50),(st,p1001,50),(st,p1000,50),(st,p5000,50);
 perform set_product_prices(st,p10,10,10,'available');
 perform set_product_prices(st,p1001,10.01,10.01,'available');
 perform set_product_prices(st,p1000,1000,1000,'available');
 perform set_product_prices(st,p5000,5000,5000,'available');
 staff3 := jsonb_build_array(a::text, b::text, c::text);

 -- This month. I1/I2: an even and an uneven cent split between three.
 i1:=create_invoice_with_details(st,cust,jsonb_build_array(jsonb_build_object('kind','product','product_id',p10,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text,'service_staff',staff3));
 perform record_invoice_payment(i1,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',10)),gen_random_uuid());
 i2:=create_invoice_with_details(st,cust,jsonb_build_array(jsonb_build_object('kind','product','product_id',p1001,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text,'service_staff',staff3));
 perform record_invoice_payment(i2,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',10.01)),gen_random_uuid());
 -- I6: 100 received, then corrected to 50 (reversal and replacement).
 i6:=create_invoice_with_details(st,cust,jsonb_build_array(jsonb_build_object('kind','product','product_id',p1000,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text,'service_staff',staff3));
 perform record_invoice_payment(i6,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',100)),gen_random_uuid());
 select id into pay from invoice_payments where invoice_id=i6;
 perform correct_invoice_payment(pay,50,sg_today(),cash,'wrong amount keyed',gen_random_uuid());
 -- I7: part paid then cancelled. I8: paid with wallet credit only.
 i7:=create_invoice_with_details(st,cust,jsonb_build_array(jsonb_build_object('kind','product','product_id',p1000,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text,'service_staff',jsonb_build_array(a::text)));
 perform record_invoice_payment(i7,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',200)),gen_random_uuid());
 perform cancel_invoice_recorded(i7,'customer withdrew',gen_random_uuid());
 perform grant_customer_credit(cust,'paid',400,'opening_balance',null,st,sg_today(),null,'test',null,null,own,null);
 i8:=create_invoice_with_details(st,cust,jsonb_build_array(jsonb_build_object('kind','product','product_id',p1000,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text,'service_staff',jsonb_build_array(b::text)));
 perform record_invoice_payment(i8,jsonb_build_array(jsonb_build_object('payment_method_id',wpm,'amount',400)),gen_random_uuid());

 -- Last month, part paid and still being paid. I4 has service staff.
 i4:=create_invoice_with_details(st,cust,jsonb_build_array(jsonb_build_object('kind','product','product_id',p5000,'quantity',1)),
   jsonb_build_object('business_date',pg_temp.d('prev_paid')::text,'service_staff',staff3));
 perform record_invoice_payment(i4,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',1000,'payment_date',pg_temp.d('prev_paid')::text)),gen_random_uuid());

 -- Created by the manager, nobody recorded as "Served by": I3 this month, I5 last month.
 perform set_config('request.jwt.claim.sub',mgr::text,true);
 i3:=create_invoice_with_details(st,cust,jsonb_build_array(jsonb_build_object('kind','product','product_id',p1000,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 i5:=create_invoice_with_details(st,cust,jsonb_build_array(jsonb_build_object('kind','product','product_id',p1000,'quantity',1)),
   jsonb_build_object('business_date',pg_temp.d('prev_paid')::text));
 perform set_config('request.jwt.claim.sub',own::text,true);
 perform record_invoice_payment(i3,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',457)),gen_random_uuid());
 perform record_invoice_payment(i5,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',500,'payment_date',pg_temp.d('prev_paid')::text)),gen_random_uuid());

 insert into fx values('own',own),('mgr',mgr),('a',a),('b',b),('c',c),('st',st),('cash',cash),
   ('i1',i1),('i2',i2),('i3',i3),('i4',i4),('i5',i5),('i6',i6),('i7',i7),('i8',i8);
end $$;

-- ═════ The report adds up ═════
do $$
declare r jsonb; per text; f date; t date; a uuid:=pg_temp.fx('a'); b uuid:=pg_temp.fx('b'); c uuid:=pg_temp.fx('c'); mgr uuid:=pg_temp.fx('mgr');
begin
 for per, f, t in values ('all time', null::date, null::date), ('last month', pg_temp.d('prev_from'), pg_temp.d('prev_to')),
                         ('this month', pg_temp.d('cur_from'), pg_temp.d('cur_to')) loop
   r := pg_temp.rep(f, t);
   perform pg_temp.check((r->>'difference')::numeric = 0 and (r->>'staff_total')::numeric = (r->>'revenue')::numeric
      and (r->>'revenue')::numeric = pg_temp.ledger_revenue(f, t),
     format('%s: staff total %s = revenue %s = the revenue ledger', per, r->>'staff_total', r->>'revenue'));
 end loop;
 perform pg_temp.check((pg_temp.rep(null,null)->>'revenue')::numeric = 2027.01,
   format('fixture revenue is 10.00 + 10.01 + 50 + 457 this month and 1000 + 500 last month = 2027.01, got %s', pg_temp.rep(null,null)->>'revenue'));

 r := pg_temp.rep(pg_temp.d('cur_from'), pg_temp.d('cur_to'));
 perform pg_temp.check(pg_temp.person(r, mgr, 'shared_sales') = 457 and pg_temp.person(r, mgr, 'credited_as_creator') = 457,
   'an invoice with no "Served by" is credited to the person who created it');
 perform pg_temp.check((r->>'credited_as_creator')::numeric = 457, 'the report says how much was credited to creators');
 perform pg_temp.check((r->>'wallet_credit_not_counted')::numeric = 400,
   'wallet-credit spend is shown as not counted (400), and credits nobody');
 perform pg_temp.check(pg_temp.person(r, b, 'invoices_served') = 3,
   format('staff B''s wallet-only invoice is not counted as served (3, not 4), got %s', pg_temp.person(r, b, 'invoices_served')));
 perform pg_temp.check(pg_temp.person(r, a, 'invoices_served') = 3,
   format('staff A served 3 invoices with money this month (the cancelled one does not count), got %s', pg_temp.person(r, a, 'invoices_served')));

 r := pg_temp.rep(pg_temp.d('prev_from'), pg_temp.d('prev_to'));
 perform pg_temp.check(pg_temp.person(r, a, 'shared_sales') + pg_temp.person(r, b, 'shared_sales') + pg_temp.person(r, c, 'shared_sales') = 1000
    and pg_temp.person(r, mgr, 'credited_as_creator') = 500,
   'last month''s part payments show in the month the money arrived: 1000 split three ways, 500 to its creator');
end $$;

-- ═════ Every event is split exactly, to the cent ═════
do $$
declare bad int;
begin
 select count(*) into bad from (
   select s.event_id, s.event_amount, sum(s.amount) as split, bool_and(s.amount = round(s.amount, 2)) as cents
     from invoice_staff_sales_ledger() s join invoices i on i.id = s.invoice_id
    where i.store_id = pg_temp.fx('st') group by s.event_id, s.event_amount) e
  where e.split <> e.event_amount or not e.cents;
 perform pg_temp.check(bad = 0, 'every event''s shares add up exactly to the event, in whole cents');
 perform pg_temp.check((select array_agg(s.amount order by s.amount) from invoice_staff_sales_ledger() s where s.invoice_id = pg_temp.fx('i1'))
    = array[3.33, 3.33, 3.34]::numeric[], '10.00 between three is 3.34 + 3.33 + 3.33');
 perform pg_temp.check((select array_agg(s.amount order by s.amount) from invoice_staff_sales_ledger() s where s.invoice_id = pg_temp.fx('i2'))
    = array[3.33, 3.34, 3.34]::numeric[], '10.01 between three is 3.34 + 3.34 + 3.33');
 perform pg_temp.check(not exists (
     select 1 from invoice_staff_sales_ledger() s where s.invoice_id = pg_temp.fx('i6')
      group by s.staff_id having sum(s.amount) <> (select x.share from invoice_sales_credit_split(pg_temp.fx('i6'), 50) x where x.staff_id = s.staff_id)),
   'a corrected payment: the reversal cancels the receipt person by person, leaving each their share of the 50');
 perform pg_temp.check(not exists (select 1 from invoice_staff_sales_ledger() s where s.invoice_id in (pg_temp.fx('i7'), pg_temp.fx('i8'))),
   'the cancelled invoice and the wallet-only invoice credit nobody');
end $$;

-- ═════ Round 2 fixtures: a second store whose last-month money changes ═════
-- Every invoice is 1000 a unit, still being paid, and served by staff D/E/F.
--   R  (3000, D+E):   600 and 400 last month, 250 this month. After registering,
--                     the 400 is removed.
--   DN (3000, D+E+F): 1000 last month. After registering, corrected down to
--                     400.01, keeping its last-month date.
--   D2 (2000, E):     700 last month. After registering, corrected down to 300,
--                     dated today.
--   B  (3000, D+F):   2000.01 last month, then 999.99 refunded (one unit back),
--                     also last month. Before registering.
do $$
declare d uuid:=gen_random_uuid(); e uuid:=gen_random_uuid(); f uuid:=gen_random_uuid();
 sfx text := lpad(floor(random()*10000000)::bigint::text, 7, '0');
 st2 uuid; cust2 uuid; cash uuid:=pg_temp.fx('cash'); p1000 uuid; prev date:=pg_temp.d('prev_paid');
 r uuid; dn uuid; d2 uuid; bi uuid; pay uuid; it uuid; mv jsonb;
begin
 perform set_config('request.jwt.claim.sub',pg_temp.fx('own')::text,true);
 insert into auth.users(id,email) values(d,'ssr2-d-'||sfx||'@tests.invalid'),(e,'ssr2-e-'||sfx||'@tests.invalid'),
   (f,'ssr2-f-'||sfx||'@tests.invalid');
 insert into profiles(id,full_name,email,role) values(d,'SSR2 Staff D','ssr2-d-'||sfx||'@tests.invalid','staff'),
   (e,'SSR2 Staff E','ssr2-e-'||sfx||'@tests.invalid','staff'),(f,'SSR2 Staff F','ssr2-f-'||sfx||'@tests.invalid','staff');
 insert into stores(name,code,country_code) values('SSR2 Store '||sfx,'SSR2'||sfx,'SG') returning id into st2;
 insert into user_store_assignments(user_id,store_id) values(d,st2),(e,st2),(f,st2);
 insert into customers(full_name,phone) values('SSR2 Buyer',pg_temp.phone()) returning id into cust2;
 insert into products(name,sku,product_type) values('SSR2 1000','SSR2K-'||sfx,'own') returning id into p1000;
 insert into store_inventory(store_id,product_id,current_qty) values(st2,p1000,50);
 perform set_product_prices(st2,p1000,1000,1000,'available');

 r:=create_invoice_with_details(st2,cust2,jsonb_build_array(jsonb_build_object('kind','product','product_id',p1000,'quantity',3)),
   jsonb_build_object('business_date',prev::text,'service_staff',jsonb_build_array(d::text,e::text)));
 perform record_invoice_payment(r,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',600,'payment_date',prev::text)),gen_random_uuid());
 perform record_invoice_payment(r,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',400,'payment_date',(prev+3)::text)),gen_random_uuid());
 perform record_invoice_payment(r,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',250)),gen_random_uuid());

 dn:=create_invoice_with_details(st2,cust2,jsonb_build_array(jsonb_build_object('kind','product','product_id',p1000,'quantity',3)),
   jsonb_build_object('business_date',prev::text,'service_staff',jsonb_build_array(d::text,e::text,f::text)));
 perform record_invoice_payment(dn,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',1000,'payment_date',prev::text)),gen_random_uuid());

 d2:=create_invoice_with_details(st2,cust2,jsonb_build_array(jsonb_build_object('kind','product','product_id',p1000,'quantity',2)),
   jsonb_build_object('business_date',prev::text,'service_staff',jsonb_build_array(e::text)));
 perform record_invoice_payment(d2,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',700,'payment_date',prev::text)),gen_random_uuid());

 bi:=create_invoice_with_details(st2,cust2,jsonb_build_array(jsonb_build_object('kind','product','product_id',p1000,'quantity',3)),
   jsonb_build_object('business_date',prev::text,'service_staff',jsonb_build_array(d::text,f::text)));
 perform record_invoice_payment(bi,jsonb_build_array(jsonb_build_object('payment_method_id',cash,'amount',2000.01,'payment_date',prev::text)),gen_random_uuid());
 select id into it from invoice_items where invoice_id=bi;
 select id into pay from invoice_payments where invoice_id=bi;
 select jsonb_build_array(jsonb_build_object('movement_id',id,'sellable_quantity',1)) into mv
   from stock_movements where invoice_id=bi and movement_type='store_sale' limit 1;
 perform refund_invoice_recorded(bi,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',999.99)),
   jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',999.99)),coalesce(mv,'[]'::jsonb),
   'One unit returned last month',gen_random_uuid());
 -- The refund was recorded last month (a refund is dated when it is recorded).
 update invoice_refunds set created_at=((prev+5)::timestamp + interval '12 hours') at time zone 'Asia/Singapore'
  where invoice_id=bi;

 insert into fx values('st2',st2),('d',d),('e',e),('f',f),('r',r),('dn',dn),('d2',d2),('bi',bi);
end $$;

-- ═════ Round 2 (b): the review moves an invoice's earlier money net of its earlier refund ═════
do $$
declare bi uuid:=pg_temp.fx('bi'); v numeric; v_paid numeric; v_refunded numeric;
begin
 perform set_config('request.jwt.claim.sub',pg_temp.fx('own')::text,true);
 perform pg_temp.check((select status::text from invoices where id=bi)='partially_paid'
    and invoice_instalment_commission_active(bi) and invoice_net_received(bi)=1000.02,
   'B after its refund: still being paid, holding 2000.01 - 999.99 = 1000.02');
 perform pg_temp.check((select array_agg(s.sales_date order by s.amount) from invoice_staff_sales_ledger() s
                         where s.invoice_id=bi and s.event_kind='refund') = array[pg_temp.d('prev_paid')+5, pg_temp.d('prev_paid')+5],
   'B''s refund is dated last month in the ledger, split between its two staff');

 select coalesce(sum(earned_amount),0) into v from commission_instalment_backfill(false) where ledger='sales' and invoice_id=bi;
 select sum(amount) into v_paid from invoice_payments where invoice_id=bi;
 select sum(amount-credit_returned) into v_refunded from invoice_refunds where invoice_id=bi;
 perform pg_temp.check(v = v_paid - v_refunded and v = 1000.02,
   format('the review''s ''sales'' rows for B are payments %s minus the refund %s = 1000.02, got %s', v_paid, v_refunded, v));
 perform pg_temp.check((select count(*) from commission_instalment_backfill(false) where ledger='sales' and invoice_id=bi)=2
    and not exists (select 1 from commission_instalment_backfill(false) x where x.ledger='sales' and x.invoice_id=bi
                     and x.earned_amount <> (select sum(sp.share) from invoice_sales_credit_split(bi, 2000.01) sp where sp.staff_id=x.beneficiary_id)
                                        + (select sum(sp.share) from invoice_sales_credit_split(bi, -999.99) sp where sp.staff_id=x.beneficiary_id)),
   'per person, B moves each person''s share of the receipt less their share of the refund (no bare negative row)');
 perform pg_temp.check(not exists (select 1 from commission_instalment_backfill(false) x where x.ledger='sales' and x.earned_amount < 0
                                     and x.invoice_id in (select id from invoices where store_id=pg_temp.fx('st2'))),
   'no one on the second store is moved a negative amount');
 perform pg_temp.check((select sum(earned_amount) from commission_instalment_backfill(false) where ledger='sales' and invoice_id=pg_temp.fx('r'))=1000
    and (select sum(earned_amount) from commission_instalment_backfill(false) where ledger='sales' and invoice_id=pg_temp.fx('dn'))=1000
    and (select sum(earned_amount) from commission_instalment_backfill(false) where ledger='sales' and invoice_id=pg_temp.fx('d2'))=700,
   'R moves its 600 + 400 from last month (not this month''s 250); DN moves 1000; D2 moves 700');
 -- (c) in the review: every invoice whose staff sales move also registers staff commission, on the same credit date.
 perform pg_temp.check(not exists (
     select 1 from commission_instalment_backfill(false) s
      where s.ledger='sales' and s.invoice_id in (select id from invoices where store_id in (pg_temp.fx('st'), pg_temp.fx('st2')))
        and not exists (select 1 from commission_instalment_backfill(false) c
                         where c.ledger='staff' and c.invoice_id=s.invoice_id and c.earned_amount > 0 and c.credit_date=s.credit_date)),
   'the review: every invoice whose staff sales move also registers its staff commission, on the same date');
end $$;

-- ═════ Registering earlier part payments moves their credit to this month ═════
do $$
declare v_comm numeric; v_sales numeric; n int; r jsonb; mgr uuid:=pg_temp.fx('mgr'); a uuid:=pg_temp.fx('a');
begin
 select count(*) into n from sales_credit_backfill;
 select coalesce(sum(earned_amount) filter (where ledger='sales' and invoice_id in (pg_temp.fx('i4'), pg_temp.fx('i5'))), 0)
   into v_sales from commission_instalment_backfill(false);
 perform pg_temp.check(v_sales = 1500, format('the review lists last month''s 1000 + 500 as receipts to credit this month, got %s', v_sales));
 perform pg_temp.check((select count(*) from commission_instalment_backfill(false) where ledger='sales' and invoice_id=pg_temp.fx('i4'))=3
    and (select earned_amount from commission_instalment_backfill(false) where ledger='sales' and invoice_id=pg_temp.fx('i5'))=500
    and (select beneficiary_id from commission_instalment_backfill(false) where ledger='sales' and invoice_id=pg_temp.fx('i5'))=mgr,
   'per person: I4 split between its three staff, I5 to its creator');
 perform pg_temp.check((select count(*) from sales_credit_backfill)=n, 'the review writes nothing');
 perform pg_temp.check(not exists (select 1 from commission_instalment_backfill(false) where ledger='sales'
                                     and invoice_id in (pg_temp.fx('i1'), pg_temp.fx('i3'), pg_temp.fx('i6'))),
   'this month''s receipts are not moved: they are already in this month');

 select coalesce(sum(earned_amount) filter (where ledger<>'sales'),0), coalesce(sum(earned_amount) filter (where ledger='sales'),0)
   into v_comm, v_sales from commission_instalment_backfill(false);
 begin
   perform * from commission_instalment_backfill(true, null, v_comm, v_sales - 1);
   raise exception 'FAIL: a receipts total that differs from the review was accepted';
 exception when others then
   if sqlerrm not like 'The earlier receipts to credit now total%' then raise; end if;
   raise notice 'PASS  registering refuses a receipts total that differs from the review';
 end;
 perform set_config('request.jwt.claim.sub', a::text, true);
 begin
   perform * from commission_instalment_backfill(true, null, v_comm, v_sales);
   raise exception 'FAIL: a staff member registered part payments';
 exception when others then
   if sqlerrm like 'FAIL:%' then raise; end if;
   raise notice 'PASS  a staff member cannot register it';
 end;
 perform set_config('request.jwt.claim.sub', pg_temp.fx('own')::text, true);

 perform * from commission_instalment_backfill(true, null, v_comm, v_sales);
 perform pg_temp.check((select count(*) from sales_credit_backfill where invoice_id in (pg_temp.fx('i4'), pg_temp.fx('i5')))=2,
   'the two receipts are recorded as credited today');
 perform pg_temp.check(not exists (select 1 from commission_instalment_backfill(false) where ledger='sales'),
   'a second review finds no receipts left to move');

 r := pg_temp.rep(pg_temp.d('prev_from'), pg_temp.d('prev_to'));
 perform pg_temp.check((r->>'revenue')::numeric = 1500 and (r->>'backfill_out')::numeric = 1500
    and (r->>'staff_total')::numeric = 0 and (r->>'difference')::numeric = 0,
   'last month: revenue still 1500, all of it credited to this month, staff total 0, difference 0');
 r := pg_temp.rep(pg_temp.d('cur_from'), pg_temp.d('cur_to'));
 perform pg_temp.check((r->>'revenue')::numeric = 527.01 and (r->>'backfill_in')::numeric = 1500
    and (r->>'staff_total')::numeric = 2027.01 and (r->>'difference')::numeric = 0,
   format('this month: revenue 527.01 + 1500 credited here = staff total 2027.01, got %s', r->>'staff_total'));
 perform pg_temp.check(pg_temp.person(r, mgr, 'credited_as_creator') = 957 and pg_temp.person(r, mgr, 'backfilled_in') = 500,
   'the creator now holds 457 + 500, of which 500 was moved here');
 r := pg_temp.rep(null, null);
 perform pg_temp.check((r->>'revenue')::numeric = 2027.01 and (r->>'staff_total')::numeric = 2027.01
    and (r->>'backfill_in')::numeric = 0 and (r->>'backfill_out')::numeric = 0, 'all time is unchanged by the move');
 perform pg_temp.check((select sum(l.amount) from invoice_sales_ledger() l join invoices i on i.id=l.invoice_id
                         where i.store_id=pg_temp.fx('st') and l.sales_date between pg_temp.d('prev_from') and pg_temp.d('prev_to')) = 1500,
   'the revenue ledger itself did not move: the headline for last month is unchanged');
end $$;

-- ═════ Round 2 (b, c): after registering, the second store reconciles in both months ═════
do $$
declare r jsonb; per text; f date; t date; bad text; bi uuid:=pg_temp.fx('bi');
begin
 perform set_config('request.jwt.claim.sub',pg_temp.fx('own')::text,true);
 perform pg_temp.check((select count(*) from sales_credit_backfill b where b.invoice_id in
                          (pg_temp.fx('r'), pg_temp.fx('dn'), pg_temp.fx('d2'), bi) and b.credited_on=sg_today()
                          and b.moved_before=pg_temp.d('cur_from'))=4,
   'R, DN, D2 and B are registered: their money before this month is credited today');
 perform pg_temp.check((select amount from sales_credit_backfill where invoice_id=bi)=1000.02,
   'B is recorded as moving 1000.02, net of its refund');
 for per, f, t in values ('all time', null::date, null::date), ('last month', pg_temp.d('prev_from'), pg_temp.d('prev_to')),
                         ('this month', pg_temp.d('cur_from'), pg_temp.d('cur_to')) loop
   r := pg_temp.rep2(f, t);
   perform pg_temp.check((r->>'difference')::numeric = 0
      and (r->>'staff_total')::numeric = (r->>'revenue')::numeric + (r->>'backfill_in')::numeric - (r->>'backfill_out')::numeric
      and not exists (select 1 from jsonb_array_elements(r->'rows') x where (x->>'shared_sales')::numeric < 0),
     format('store 2, %s: staff total %s = revenue %s + %s in - %s out, difference 0, no one negative',
            per, r->>'staff_total', r->>'revenue', r->>'backfill_in', r->>'backfill_out'));
 end loop;
 r := pg_temp.rep2(pg_temp.d('prev_from'), pg_temp.d('prev_to'));
 perform pg_temp.check((r->>'revenue')::numeric = 3700.02 and (r->>'backfill_out')::numeric = 3700.02
    and (r->>'staff_total')::numeric = 0 and jsonb_array_length(r->'rows') = 0,
   format('store 2 last month: revenue 1000 + 1000 + 700 + (2000.01 - 999.99) = 3700.02, all of it credited to this month, got %s / %s',
          r->>'revenue', r->>'backfill_out'));
 r := pg_temp.rep2(pg_temp.d('cur_from'), pg_temp.d('cur_to'));
 perform pg_temp.check((r->>'revenue')::numeric = 250 and (r->>'backfill_in')::numeric = 3700.02
    and (r->>'staff_total')::numeric = 3950.02,
   format('store 2 this month: 250 received + 3700.02 moved here = 3950.02, got %s', r->>'staff_total'));
 perform pg_temp.check(pg_temp.inv_sales(bi, pg_temp.d('cur_from'), pg_temp.d('cur_to')) = invoice_net_received(bi)
    and pg_temp.inv_sales(bi, pg_temp.d('prev_from'), pg_temp.d('prev_to')) = 0,
   'B: this month holds the 1000.02 it still holds; last month holds nothing (the refund moved with its receipt)');
 bad := pg_temp.negative_months();
 perform pg_temp.check(bad is null, format('no one on store 2 has a negative month (%s)', coalesce(bad, 'none')));

 -- (c) after registering.
 bad := pg_temp.same_month_problems();
 perform pg_temp.check(bad is null,
   format('staff sales moved and commission registered: same month, same invoices, same money (%s)', coalesce(bad, 'all agree')));
 perform pg_temp.check((select count(distinct sc.invoice_id) from staff_commissions sc
                         where sc.earning_basis='instalment' and sc.invoice_id in
                           (pg_temp.fx('i4'), pg_temp.fx('i5'), pg_temp.fx('r'), pg_temp.fx('dn'), pg_temp.fx('d2'), bi))=6,
   'every invoice whose earlier money moved (I4, I5, R, DN, D2, B) holds registered part-payment commission');
end $$;

-- ═════ Round 2 (a): a moved receipt removed, or corrected down, after registering ═════
do $$
declare r jsonb; per text; f date; t date; bad text; pay uuid; cash uuid:=pg_temp.fx('cash');
 ri uuid:=pg_temp.fx('r'); dn uuid:=pg_temp.fx('dn'); d2 uuid:=pg_temp.fx('d2'); bi uuid:=pg_temp.fx('bi');
begin
 perform set_config('request.jwt.claim.sub',pg_temp.fx('own')::text,true);
 perform pg_temp.check((select instalment_commission_from from app_settings where id=true) is not null,
   'part-payment commission is on: these changes happen after registering');
 -- R: the 400 received last month bounced.
 select id into pay from invoice_payments where invoice_id=ri and amount=400 and entry_kind is distinct from 'correction_reversal';
 perform remove_invoice_payment(pay,'Transfer bounced',gen_random_uuid());
 -- DN: 1000 was keyed; 400.01 arrived, on the same day last month.
 select id into pay from invoice_payments where invoice_id=dn;
 perform correct_invoice_payment(pay,400.01,pg_temp.d('prev_paid'),cash,'Wrong amount keyed',gen_random_uuid());
 -- D2: 700 was keyed; 300 arrived, and it arrived today.
 select id into pay from invoice_payments where invoice_id=d2;
 perform correct_invoice_payment(pay,300,sg_today(),cash,'Wrong amount and date keyed',gen_random_uuid());

 perform pg_temp.check(invoice_net_received(ri)=850 and invoice_net_received(dn)=400.01 and invoice_net_received(d2)=300
    and (select bool_and(status::text='partially_paid') from invoices where id in (ri, dn, d2)),
   'R holds 850, DN 400.01, D2 300, all still being paid');
 perform pg_temp.check(not exists (
     select 1 from invoice_staff_sales_ledger() s where s.invoice_id in (ri, dn, d2) and s.event_kind='correction_reversal'
        and not (s.sales_date < pg_temp.d('cur_from') and s.credited_on between pg_temp.d('cur_from') and pg_temp.d('cur_to')))
    and (select count(distinct s.event_id) from invoice_staff_sales_ledger() s
          where s.invoice_id in (ri, dn, d2) and s.event_kind='correction_reversal')=3,
   'the three reversals keep their last-month dates and are credited this month, with the receipts they reverse');

 for per, f, t in values ('all time', null::date, null::date), ('last month', pg_temp.d('prev_from'), pg_temp.d('prev_to')),
                         ('this month', pg_temp.d('cur_from'), pg_temp.d('cur_to')) loop
   r := pg_temp.rep2(f, t);
   perform pg_temp.check((r->>'difference')::numeric = 0
      and (r->>'staff_total')::numeric = (r->>'revenue')::numeric + (r->>'backfill_in')::numeric - (r->>'backfill_out')::numeric
      and not exists (select 1 from jsonb_array_elements(r->'rows') x where (x->>'shared_sales')::numeric < 0),
     format('after the changes, store 2, %s: staff total %s = revenue %s + %s in - %s out, difference 0, no one negative',
            per, r->>'staff_total', r->>'revenue', r->>'backfill_in', r->>'backfill_out'));
 end loop;
 r := pg_temp.rep2(pg_temp.d('prev_from'), pg_temp.d('prev_to'));
 perform pg_temp.check((r->>'revenue')::numeric = 2000.03 and (r->>'backfill_out')::numeric = 2000.03
    and (r->>'staff_total')::numeric = 0 and jsonb_array_length(r->'rows') = 0,
   format('last month: revenue 600 + 400.01 + 0 + 1000.02 = 2000.03, all credited to this month, staff total 0, got %s / %s / %s',
          r->>'revenue', r->>'backfill_out', r->>'staff_total'));
 r := pg_temp.rep2(pg_temp.d('cur_from'), pg_temp.d('cur_to'));
 perform pg_temp.check((r->>'revenue')::numeric = 550 and (r->>'backfill_in')::numeric = 2000.03
    and (r->>'staff_total')::numeric = 2550.03,
   format('this month: 250 + 300 received + 2000.03 moved here = 2550.03, got %s', r->>'staff_total'));
 perform pg_temp.check(not exists (
     select 1 from unnest(array[ri, dn, d2, bi]) inv
      where pg_temp.inv_sales(inv, pg_temp.d('cur_from'), pg_temp.d('cur_to')) <> invoice_net_received(inv)
         or pg_temp.inv_sales(inv, pg_temp.d('prev_from'), pg_temp.d('prev_to')) <> 0),
   'each invoice''s staff sales this month are exactly what it still holds (R 850, DN 400.01, D2 300, B 1000.02); last month none');
 perform pg_temp.check(pg_temp.person(r, pg_temp.fx('d'), 'shared_sales') in (425 + 133.34 + 500.01, 425 + 133.33 + 500.01),
   format('staff D this month: R half of 850 + DN a third of 400.01 + B 500.01, got %s', pg_temp.person(r, pg_temp.fx('d'), 'shared_sales')));
 bad := pg_temp.negative_months();
 perform pg_temp.check(bad is null, format('no one on store 2 has a negative month after the changes (%s)', coalesce(bad, 'none')));

 -- (c) after money left: the commission followed the money in the same month.
 bad := pg_temp.same_month_problems();
 perform pg_temp.check(bad is null,
   format('after the changes, commission and staff sales still agree on month, invoice and money (%s)', coalesce(bad, 'all agree')));
end $$;

-- ═════ Who may see it ═════
do $$
declare v_msg text;
begin
 perform set_config('request.jwt.claim.sub', pg_temp.fx('a')::text, true);
 begin
   perform report_sales_by_service_staff(null, null, null);
   raise exception 'FAIL: a staff member could read the report';
 exception when others then
   if sqlerrm like 'FAIL:%' then raise; end if;
   raise notice 'PASS  a staff member cannot read the report';
 end;
 perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
 begin
   perform report_sales_by_service_staff(null, null, null);
   raise exception 'FAIL: a user with no profile could read the report';
 exception when others then
   if sqlerrm like 'FAIL:%' then raise; end if;
   raise notice 'PASS  a user with no profile cannot read the report';
 end;
 perform pg_temp.check(not has_function_privilege('anon', 'public.report_sales_by_service_staff(date,date,uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.invoice_staff_sales_ledger()', 'execute')
    and not has_function_privilege('authenticated', 'public.invoice_sales_credit_split(uuid,numeric)', 'execute'),
   'the ledger and split are internal; the report is not open to anon');
end $$;
rollback;
