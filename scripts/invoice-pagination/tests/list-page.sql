-- One page of the invoice list, over a set larger than the API row limit.
--
-- The list used to page through every accessible invoice and then filter,
-- search and sort the whole set in the browser. These assertions cover what
-- that did, now that the database does it: the same filters and search fields,
-- the same sort options, a count and a summary over the WHOLE filtered set
-- rather than the visible page, and an ordering total enough that no row can
-- appear on two pages or on none.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; st2 uuid; c1 uuid; c2 uuid; pm uuid; pm2 uuid;
 prod uuid; r jsonb; n int; ids uuid[]; seen uuid[]; page jsonb; i int;
 v_total bigint; first_no text; last_no text;
begin
 insert into auth.users(id,email) values(own,'ilp@t.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','ilp@t.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('ILP Main','ILP','SG') returning id into st;
 insert into stores(name,code,country_code) values('ILP Other','ILQ','SG') returning id into st2;
 insert into customers(full_name,phone) values('Alpha Buyer','+6591710001') returning id into c1;
 insert into customers(full_name,phone) values('Zulu Buyer','+6591710002') returning id into c2;
 insert into payment_methods(name) values('ILP Cash') returning id into pm;
 insert into payment_methods(name) values('ILP Atome') returning id into pm2;
 insert into products(name,sku,product_type) values('ILP Item','ILP-1','own') returning id into prod;
 insert into store_inventory(store_id,product_id,current_qty) values(st,prod,100000),(st2,prod,100000);
 perform set_product_prices(st,prod,10,10,'available');
 perform set_product_prices(st2,prod,10,10,'available');

 -- 1,205 invoices: past PostgREST's 1000-row ceiling, and past any one page.
 -- Written directly rather than through create_invoice, which would take far
 -- too long for a set this size; the columns the list reads are what matter.
 for i in 1..1205 loop
   insert into invoices(invoice_no,store_id,customer_id,created_by,status,
                        subtotal,discount_total,total_amount,paid_amount,business_date,created_at)
   values('INV-2026-'||lpad(i::text,4,'0'),
          case when i % 5 = 0 then st2 else st end,
          case when i % 2 = 0 then c1 else c2 end,
          own,
          case when i % 3 = 0 then 'paid'::invoice_status else 'unpaid'::invoice_status end,
          10, 0, 10, case when i % 3 = 0 then 10 else 0 end,
          case when i % 7 = 0 then null else (date '2026-01-01' + (i % 300)) end,
          now() - (i || ' minutes')::interval);
 end loop;

 -- ---- a page is a page -----------------------------------------------------
 r:=invoice_list_page(null,null,'all',null,null,null,'created_at','desc',25,0);
 if jsonb_array_length(r->'rows')<>25 then
  raise exception 'Asked for 25, got %', jsonb_array_length(r->'rows'); end if;
 if (r->>'total')::bigint<>1205 then
  raise exception 'The count is not the whole matching set: %', r->>'total'; end if;
 if (r->>'pages')::int<>49 then raise exception 'Wrong page count: %', r->>'pages'; end if;

 -- page sizes
 if jsonb_array_length(invoice_list_page(null,null,'all',null,null,null,'created_at','desc',50,0)->'rows')<>50 then
  raise exception '50 per page did not return 50'; end if;
 if jsonb_array_length(invoice_list_page(null,null,'all',null,null,null,'created_at','desc',100,0)->'rows')<>100 then
  raise exception '100 per page did not return 100'; end if;

 -- the last page is short, not empty
 r:=invoice_list_page(null,null,'all',null,null,null,'created_at','desc',100,1200);
 if jsonb_array_length(r->'rows')<>5 then
  raise exception 'The last page should hold the remaining 5, got %', jsonb_array_length(r->'rows'); end if;
 -- past the end is empty, not an error
 r:=invoice_list_page(null,null,'all',null,null,null,'created_at','desc',25,5000);
 if jsonb_array_length(r->'rows')<>0 then raise exception 'Past the end should be empty'; end if;
 if (r->>'total')::bigint<>1205 then raise exception 'Past the end lost the count'; end if;

 -- ---- every row appears exactly once across all pages ----------------------
 seen:='{}';
 for i in 0..12 loop
   page:=invoice_list_page(null,null,'all',null,null,null,'business_date','desc',100,i*100);
   select seen || coalesce(array_agg((x->>'id')::uuid),'{}') into seen
     from jsonb_array_elements(page->'rows') x;
 end loop;
 if array_length(seen,1)<>1205 then
  raise exception 'Walking the pages returned % rows, not 1205', array_length(seen,1); end if;
 if (select count(distinct u) from unnest(seen) u)<>1205 then
  raise exception 'A row appeared on more than one page'; end if;

 -- ---- filters run over everything, not the page ---------------------------
 r:=invoice_list_page(null,'paid','all',null,null,null,'created_at','desc',25,0);
 select count(*) into n from invoices where status='paid';
 if (r->>'total')::bigint<>n then
  raise exception 'Status filter counted %, expected %', r->>'total', n; end if;

 r:=invoice_list_page(null,null,'pending',null,null,null,'created_at','desc',25,0);
 select count(*) into n from invoices where business_date is null;
 if (r->>'total')::bigint<>n then raise exception 'Undated filter is wrong'; end if;

 r:=invoice_list_page(null,null,'all',null,null,st2,'created_at','desc',25,0);
 select count(*) into n from invoices where store_id=st2;
 if (r->>'total')::bigint<>n then raise exception 'Store filter is wrong'; end if;

 -- ---- search spans the joined fields --------------------------------------
 r:=invoice_list_page('Alpha',null,'all',null,null,null,'created_at','desc',25,0);
 select count(*) into n from invoices where customer_id=c1;
 if (r->>'total')::bigint<>n then
  raise exception 'Searching a customer name found %, expected %', r->>'total', n; end if;

 r:=invoice_list_page('ILP Other',null,'all',null,null,null,'created_at','desc',25,0);
 if (r->>'total')::bigint<>(select count(*) from invoices where store_id=st2) then
  raise exception 'Searching a store name is wrong'; end if;

 -- a match that lives well past the first page is still found
 r:=invoice_list_page('INV-2026-1200',null,'all',null,null,null,'created_at','desc',25,0);
 if (r->>'total')::bigint<>1 then
  raise exception 'A match beyond page one was not found'; end if;

 -- payment method search
 insert into invoice_payments(invoice_id,payment_method_id,amount,received_by)
  select id,pm2,10,own from invoices where invoice_no='INV-2026-0500';
 r:=invoice_list_page('Atome',null,'all',null,null,null,'created_at','desc',25,0);
 if (r->>'total')::bigint<>1 then
  raise exception 'Searching a payment method found %, expected 1', r->>'total'; end if;

 -- ---- sorting is over everything, and natural for invoice numbers ---------
 r:=invoice_list_page(null,null,'all',null,null,null,'invoice_no','asc',1,0);
 first_no:=r->'rows'->0->>'invoice_no';
 if first_no<>'INV-2026-0001' then
  raise exception 'Ascending invoice_no started at %, expected 0001', first_no; end if;
 r:=invoice_list_page(null,null,'all',null,null,null,'invoice_no','desc',1,0);
 last_no:=r->'rows'->0->>'invoice_no';
 if last_no<>'INV-2026-1205' then
  raise exception 'Descending invoice_no started at %, expected 1205', last_no; end if;

 -- undated invoices sit at the bottom whichever way business_date is sorted
 r:=invoice_list_page(null,null,'all',null,null,null,'business_date','asc',5,0);
 if exists(select 1 from jsonb_array_elements(r->'rows') x where x->>'business_date' is null) then
  raise exception 'An undated invoice sorted to the top'; end if;
 r:=invoice_list_page(null,null,'all',null,null,null,'business_date','desc',5,0);
 if exists(select 1 from jsonb_array_elements(r->'rows') x where x->>'business_date' is null) then
  raise exception 'An undated invoice sorted to the top descending'; end if;

 -- ---- the summary covers the filtered set, not the page -------------------
 r:=invoice_list_page(null,'paid','all',null,null,null,'created_at','desc',25,0);
 select count(*) into n from invoices where status='paid';
 if (r->'summary'->>'total_amount')::numeric <> (n*10)::numeric then
  raise exception 'Summary total covers the page, not the filter: %', r->'summary'->>'total_amount'; end if;
 if (r->'summary'->>'outstanding')::numeric <> 0 then
  raise exception 'Paid invoices should show no outstanding, got %', r->'summary'->>'outstanding'; end if;

 -- ---- an unsortable field is refused --------------------------------------
 begin
  perform invoice_list_page(null,null,'all',null,null,null,'total_amount; drop table invoices','desc',25,0);
  raise exception 'An arbitrary sort field was accepted';
 exception when others then
  if sqlerrm not like '%Not a sortable field%' then raise; end if; end;

 raise notice 'PASS: a page is one page over 1205 invoices, every row appears exactly once across the pages, filters search and sorting run over the whole set including customer store and payment method, invoice numbers sort naturally, undated rows stay last, and the count and summary describe the filter rather than the page';
end $$;
rollback;
