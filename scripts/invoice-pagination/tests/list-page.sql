-- One page of the invoice list, over a set larger than the API row limit.
--
-- The list used to page through every accessible invoice and then filter,
-- search and sort the whole set in the browser. These assertions cover what
-- that did, now that the database does it: the same filters and search fields,
-- the same sort options, a count and a summary over the WHOLE filtered set
-- rather than the visible page, and an ordering total enough that no row can
-- appear on two pages or on none.
--
-- The second block (416, INVOICES-CREATE-12): search finds the day the list
-- shows, the business date or an undated invoice's Singapore creation day, as
-- DD/MM/YYYY, YYYY-MM-DD and "5 Mar 2025", including an invoice made between
-- midnight and 8 am in Singapore (still the day before in UTC); "5 Mar 2025"
-- finds that day only, not 15 or 25 Mar, and "Mar 2025" finds the month; a
-- month name counts as a date only with a number ("5 Mar" is that day in any
-- year; "Jun" or "Mar" alone is a name search, the Owner, 9 Oct 2026); the
-- Singapore creation day still finds a dated invoice, also one made before
-- 8 am; and a page's rows come in the page's order. Needs 416 (psql -v
-- mig=supabase/416_invoice_editing_foc_and_payment_guards.sql installs it
-- after "begin;").
--
-- Disposable database only; everything is rolled back.
begin;
\if :{?mig}
\i :mig
\endif
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

-- ═════ 416: the day the list shows, and the order of a page ═════
do $$
declare own uuid; st uuid; c uuid; late uuid; early uuid; dated uuid; mid uuid; last uuid; dawn uuid; r jsonb; q text; n int;
 june uuid; jun uuid; named uuid;
begin
 select id into own from profiles where email = 'ilp@t.invalid';
 perform set_config('request.jwt.claim.sub', own::text, true);
 insert into stores(name,code,country_code) values('ILP Dates','ILD','SG') returning id into st;
 insert into customers(full_name,phone) values('Dates Buyer','+61491571804') returning id into c;
 -- Undated, made at 23:30 on 4 Mar 2025 in Singapore (15:30 UTC that day).
 insert into invoices(invoice_no,store_id,customer_id,created_by,status,subtotal,discount_total,total_amount,paid_amount,business_date,created_at)
 values('ILD-0001',st,c,own,'unpaid',10,0,10,0,null,timestamptz '2025-03-04 23:30:00+08') returning id into late;
 -- Undated, made at 01:00 on 5 Mar 2025 in Singapore (still 4 Mar in UTC).
 insert into invoices(invoice_no,store_id,customer_id,created_by,status,subtotal,discount_total,total_amount,paid_amount,business_date,created_at)
 values('ILD-0002',st,c,own,'unpaid',10,0,10,0,null,timestamptz '2025-03-05 01:00:00+08') returning id into early;
 -- Dated 5 Mar 2025, made on 10 Mar 2025.
 insert into invoices(invoice_no,store_id,customer_id,created_by,status,subtotal,discount_total,total_amount,paid_amount,business_date,created_at)
 values('ILD-0003',st,c,own,'unpaid',10,0,10,0,date '2025-03-05',timestamptz '2025-03-10 12:00:00+08') returning id into dated;
 -- Dated 15 and 25 Mar 2025: "5 Mar 2025" is in their text, not their day.
 insert into invoices(invoice_no,store_id,customer_id,created_by,status,subtotal,discount_total,total_amount,paid_amount,business_date,created_at)
 values('ILD-0004',st,c,own,'unpaid',10,0,10,0,date '2025-03-15',timestamptz '2025-03-15 12:00:00+08') returning id into mid;
 insert into invoices(invoice_no,store_id,customer_id,created_by,status,subtotal,discount_total,total_amount,paid_amount,business_date,created_at)
 values('ILD-0005',st,c,own,'unpaid',10,0,10,0,date '2025-03-25',timestamptz '2025-03-25 12:00:00+08') returning id into last;
 -- Dated 20 Feb 2025, made at 01:00 on 12 Mar 2025 in Singapore (11 Mar in UTC).
 insert into invoices(invoice_no,store_id,customer_id,created_by,status,subtotal,discount_total,total_amount,paid_amount,business_date,created_at)
 values('ILD-0006',st,c,own,'unpaid',10,0,10,0,date '2025-02-20',timestamptz '2025-03-12 01:00:00+08') returning id into dawn;

 foreach q in array array['05/03/2025', '2025-03-05', '5 Mar 2025', '05 Mar 2025', '5 mar 2025'] loop
   r := invoice_list_page(q,null,'all',null,null,st,'invoice_no','asc',25,0);
   if (r->>'total')::int <> 2 or r->'rows'->0->>'id' <> early::text or r->'rows'->1->>'id' <> dated::text then
     raise exception '"%" should find the invoice made at 01:00 SGT and the one dated that day, found %', q, r->'rows'; end if;
 end loop;
 r := invoice_list_page('04/03/2025',null,'all',null,null,st,'invoice_no','asc',25,0);
 if (r->>'total')::int <> 1 or r->'rows'->0->>'id' <> late::text then
   raise exception '04/03/2025 should find only the invoice made at 23:30 SGT that day, found %', r->'rows'; end if;
 r := invoice_list_page('2025-03-10',null,'all',null,null,st,'invoice_no','asc',25,0);
 if (r->>'total')::int <> 1 or r->'rows'->0->>'id' <> dated::text then
   raise exception 'The day a dated invoice was made should still find it, found %', r->'rows'; end if;
 r := invoice_list_page('2025-03-12',null,'all',null,null,st,'invoice_no','asc',25,0);
 if (r->>'total')::int <> 1 or r->'rows'->0->>'id' <> dawn::text then
   raise exception 'The Singapore day a dated invoice was made before 8 am should find it, found %', r->'rows'; end if;
 r := invoice_list_page('2025-03-11',null,'all',null,null,st,'invoice_no','asc',25,0);
 if (r->>'total')::int <> 0 then
   raise exception 'The UTC day an invoice was made should not find it, found %', r->'rows'; end if;
 r := invoice_list_page('Mar 2025',null,'all',null,null,st,'invoice_no','asc',25,0);
 if (r->>'total')::int <> 5 then
   raise exception '"Mar 2025" should find the five invoices of March 2025, found %', r->'rows'; end if;
 r := invoice_list_page('15 Mar 2025',null,'all',null,null,st,'invoice_no','asc',25,0);
 if (r->>'total')::int <> 1 or r->'rows'->0->>'id' <> mid::text then
   raise exception '"15 Mar 2025" should find the invoice of that day only, found %', r->'rows'; end if;

 -- A month name counts as a date only with a number (the Owner, 9 Oct
 -- 2026): "5 Mar" is that day in any year, "Jun 2025" the month; "Mar" or
 -- "Jun" alone is a name search.
 foreach q in array array['5 Mar', '05 Mar', '5 mar'] loop
   r := invoice_list_page(q,null,'all',null,null,st,'invoice_no','asc',25,0);
   if (r->>'total')::int <> 2 or r->'rows'->0->>'id' <> early::text or r->'rows'->1->>'id' <> dated::text then
     raise exception '"%" should find the two invoices of 5 March only, not 15 or 25 March, found %', q, r->'rows'; end if;
 end loop;
 insert into invoices(invoice_no,store_id,customer_id,created_by,status,subtotal,discount_total,total_amount,paid_amount,business_date,created_at)
 values('ILD-0007',st,c,own,'unpaid',10,0,10,0,date '2025-06-03',timestamptz '2025-06-03 12:00:00+08') returning id into june;
 insert into customers(full_name,phone) values('Jun Lim','+61491574118') returning id into jun;
 insert into invoices(invoice_no,store_id,customer_id,created_by,status,subtotal,discount_total,total_amount,paid_amount,business_date,created_at)
 values('ILD-0008',st,jun,own,'unpaid',10,0,10,0,date '2025-04-02',timestamptz '2025-04-02 12:00:00+08') returning id into named;
 r := invoice_list_page('Jun',null,'all',null,null,st,'invoice_no','asc',25,0);
 if (r->>'total')::int <> 1 or r->'rows'->0->>'id' <> named::text then
   raise exception '"Jun" alone should find Jun Lim''s invoice by name only, not the one dated in June, found %', r->'rows'; end if;
 r := invoice_list_page('Mar',null,'all',null,null,st,'invoice_no','asc',25,0);
 if (r->>'total')::int <> 0 then
   raise exception '"Mar" alone should find no invoice by its date, found %', r->'rows'; end if;
 r := invoice_list_page('Jun 2025',null,'all',null,null,st,'invoice_no','asc',25,0);
 if (r->>'total')::int <> 1 or r->'rows'->0->>'id' <> june::text then
   raise exception '"Jun 2025" should find the invoice dated in June 2025, found %', r->'rows'; end if;

 -- A page's rows come in the page's order (every row, both directions).
 foreach q in array array['invoice_no', 'created_at', 'total', 'customer'] loop
   r := invoice_list_page(null,null,'all',null,null,null,q,'asc',200,0);
   select count(*) into n from jsonb_array_elements(r->'rows') with ordinality t(x, i)
    where i > 1 and (case q when 'invoice_no' then public.invoice_no_sortkey(x->>'invoice_no') < public.invoice_no_sortkey((r->'rows'->((i - 2)::int))->>'invoice_no')
                           when 'created_at' then (x->>'created_at')::timestamptz < ((r->'rows'->((i - 2)::int))->>'created_at')::timestamptz
                           when 'total' then (x->>'total_amount')::numeric < ((r->'rows'->((i - 2)::int))->>'total_amount')::numeric
                           else lower(x->>'customer_name') < lower((r->'rows'->((i - 2)::int))->>'customer_name') end);
   if n > 0 then raise exception 'Rows sorted by % ascending came out of order (% times)', q, n; end if;
   if exists (select 1 from jsonb_array_elements(r->'rows') x where x ? 'rn' or x ? 'sort_no') then
     raise exception 'A row carries the page''s own numbering'; end if;
 end loop;

 raise notice 'PASS: search finds the day the list shows (DD/MM/YYYY, YYYY-MM-DD, 5 Mar 2025, that day only), the Singapore day for an undated invoice made before 8 am, the month from Mar 2025, the day from 5 Mar, and the Singapore creation day of a dated one; Jun or Mar alone is a name search; a page''s rows come in its order';
end $$;
rollback;
