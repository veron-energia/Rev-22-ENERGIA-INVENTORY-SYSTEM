-- The dashboard must describe one set of sales.
--
-- After 292 the sales figure moved to the day money arrived while the tiles
-- beside it stayed on the invoice date, so one invoice appeared in two months.
-- Disposable database only; everything is rolled back.
begin;
do $$
declare o uuid:=gen_random_uuid(); st uuid; c uuid; pm uuid; p uuid;
 inv uuid; undated uuid; d jsonb; n numeric;
begin
 insert into auth.users(id,email) values(o,'db-owner@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Owner','db-owner@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('DB Store','DBS','SG') returning id into st;
 insert into customers(full_name,phone) values('DB Buyer','+6598009999') returning id into c;
 insert into payment_methods(name,is_active) values('DB Cash',true) returning id into pm;
 insert into products(name,sku,product_type) values('DB Item','DBI','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,100);
 perform set_product_prices(st,p,100,100,'available');

 -- Raised in August, paid in September: the whole invoice belongs to September.
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',3)),
   jsonb_build_object('business_date','2026-08-15','manual_discount',30));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object(
   'payment_method_id',pm,'amount',270,'payment_date','2026-09-04')),gen_random_uuid());

 d:=dashboard_sales('custom','2026-09-01','2026-09-30',st);
 if (d->>'sales')::numeric<>270 then raise exception 'September sales were % instead of 270', d->>'sales'; end if;
 if (d->>'items_sold')::numeric<>3 then raise exception 'September items were % instead of 3 — the tiles disagree with sales', d->>'items_sold'; end if;
 if (d->>'discount_total')::numeric<>30 then raise exception 'September discount was % instead of 30', d->>'discount_total'; end if;
 if (d->>'invoice_count')::numeric<>1 then raise exception 'September invoice count was %', d->>'invoice_count'; end if;

 -- August must show none of it, not the items and discount on their own.
 d:=dashboard_sales('custom','2026-08-01','2026-08-31',st);
 if (d->>'sales')::numeric<>0 or (d->>'items_sold')::numeric<>0 or (d->>'discount_total')::numeric<>0 then
  raise exception 'August still shows part of a September sale: %', d; end if;

 -- The stated basis must match what the numbers do.
 if (select d->>'basis') not like '%day they were received%' then
  raise exception 'The dashboard still describes itself as invoice-date based'; end if;

 -- ---------------------------------------------------------------
 -- An invoice whose date was never recorded is not invisible.
 -- ---------------------------------------------------------------
 undated:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',2)),
   jsonb_build_object('business_date','2026-09-10','manual_discount',10));
 perform record_invoice_payment(undated,jsonb_build_array(jsonb_build_object(
   'payment_method_id',pm,'amount',190,'payment_date','2026-09-10')),gen_random_uuid());
 update invoices set business_date=null where id=undated;   -- the historical shape

 d:=dashboard_sales('custom','2026-09-01','2026-09-30',st);
 if (d->>'sales')::numeric<>460 then raise exception 'An undated invoice was dropped from sales: %', d->>'sales'; end if;
 if (d->>'items_sold')::numeric<>5 then raise exception 'An undated invoice was dropped from items: %', d->>'items_sold'; end if;
 if (d->>'discount_total')::numeric<>40 then raise exception 'An undated invoice was dropped from discounts: %', d->>'discount_total'; end if;

 -- And it appears in the detail reports, dated by the day it was created.
 if not exists(select 1 from report_pricing() where invoice_id=undated) then
  raise exception 'An undated invoice is missing from the pricing report'; end if;
 if (select paid_date from report_pricing() where invoice_id=undated limit 1)
    <> (select (created_at at time zone 'Asia/Singapore')::date from invoices where id=undated) then
  raise exception 'The pricing report did not date it by its creation day'; end if;

 -- A recorded date still wins over the creation date.
 if (select invoice_effective_date(inv))<>'2026-08-15' then
  raise exception 'A recorded business date was overridden'; end if;
 if (select invoice_sales_day(inv))<>'2026-09-04' then
  raise exception 'The sales day is not the day the money arrived'; end if;

 raise notice 'PASS: sales, count, items and discounts describe one set of sales on the day money arrived; an invoice with no recorded date appears in the dashboard and the detail reports under its creation day; a recorded date still wins';
end $$;
rollback;
