-- A date range means dated invoices inside it (329).
--
-- The reported case: From = To = 17/09/2026 still listed invoices dated 08/09
-- and 09/09. Those had no business date; the list showed their creation day
-- and 324 let undated rows through any range. Disposable database only.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; st2 uuid; c uuid; r jsonb; i int; n int; msg text;
begin
 insert into auth.users(id,email) values(own,'dr-own@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','dr-own@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('DR Main','DRM','SG') returning id into st;
 insert into stores(name,code,country_code) values('DR Other','DRO','SG') returning id into st2;
 insert into customers(full_name,phone) values('DR Buyer','+6598913101') returning id into c;

 -- Dated: 16th, 18th, and 30 on the 17th (more than one page), one at the
 -- other store; undated ones created on 08/09 and 09/09, plus one created at
 -- 00:30 Singapore on the 17th (still the 16th in UTC).
 insert into invoices(invoice_no,store_id,customer_id,created_by,status,subtotal,discount_total,total_amount,paid_amount,business_date,created_at)
 values ('DR-0016',st,c,own,'unpaid',100,0,100,0,'2026-09-16','2026-09-16 10:00+08'),
        ('DR-0018',st,c,own,'unpaid',100,0,100,0,'2026-09-18','2026-09-18 10:00+08'),
        ('DR-U008',st,c,own,'unpaid',100,0,100,0,null,'2026-09-08 10:00+08'),
        ('DR-U009',st,c,own,'unpaid',100,0,100,0,null,'2026-09-09 10:00+08'),
        ('DR-U017',st,c,own,'unpaid',100,0,100,0,null,'2026-09-17 00:30+08');
 for i in 1..30 loop
  insert into invoices(invoice_no,store_id,customer_id,created_by,status,subtotal,discount_total,total_amount,paid_amount,business_date,created_at)
  values ('DR-17'||lpad(i::text,2,'0'), case when i=30 then st2 else st end, c, own,
          (case when i%2=0 then 'paid' else 'unpaid' end)::invoice_status, 100,0,100, case when i%2=0 then 100 else 0 end,
          '2026-09-17','2026-09-17 12:00+08');
 end loop;

 -- The reported reproduction.
 r:=invoice_list_page(null,null,'all','2026-09-17','2026-09-17',null,'created_at','desc',25,0);
 if (r->>'total')::int<>30 then raise exception 'FAIL: 17/09 to 17/09 matched % (expected 30 dated on the 17th only)', r->>'total'; end if;
 if jsonb_array_length(r->'rows')<>25 then raise exception 'FAIL: expected one page of 25, got %', jsonb_array_length(r->'rows'); end if;
 if (r->'summary'->>'matching')::int<>30 then raise exception 'FAIL: summary counts % not 30', r->'summary'->>'matching'; end if;
 if exists (select 1 from jsonb_array_elements(r->'rows') x where x->>'invoice_no' like 'DR-U%') then
  raise exception 'FAIL: an undated invoice was listed inside a date range'; end if;
 r:=invoice_list_page(null,null,'all','2026-09-17','2026-09-17',null,'created_at','desc',25,25);
 if jsonb_array_length(r->'rows')<>5 then raise exception 'FAIL: page two should hold the remaining 5, got %', jsonb_array_length(r->'rows'); end if;

 -- Both ends inclusive.
 r:=invoice_list_page(null,null,'all','2026-09-16','2026-09-18',null,'created_at','desc',50,0);
 if (r->>'total')::int<>32 then raise exception 'FAIL: 16th to 18th inclusive should be 32, got %', r->>'total'; end if;
 -- One side only.
 r:=invoice_list_page(null,null,'all','2026-09-18',null,null,'created_at','desc',50,0);
 if (r->>'total')::int<>1 then raise exception 'FAIL: from the 18th alone should be 1, got %', r->>'total'; end if;
 r:=invoice_list_page(null,null,'all',null,'2026-09-16',null,'created_at','desc',50,0);
 if (r->>'total')::int<>1 then raise exception 'FAIL: up to the 16th alone should be 1 (undated excluded), got %', r->>'total'; end if;
 -- Combined with status and store.
 r:=invoice_list_page(null,'paid','all','2026-09-17','2026-09-17',null,'created_at','desc',50,0);
 if (r->>'total')::int<>15 then raise exception 'FAIL: paid on the 17th should be 15, got %', r->>'total'; end if;
 r:=invoice_list_page(null,null,'all','2026-09-17','2026-09-17',st2,'created_at','desc',50,0);
 if (r->>'total')::int<>1 then raise exception 'FAIL: the other store on the 17th should be 1, got %', r->>'total'; end if;
 -- Confirmed mode with a range says the same thing.
 r:=invoice_list_page(null,null,'confirmed','2026-09-17','2026-09-17',null,'created_at','desc',50,0);
 if (r->>'total')::int<>30 then raise exception 'FAIL: confirmed + range should be 30, got %', r->>'total'; end if;
 -- Undated invoices are what the pending mode is for, and only that mode.
 r:=invoice_list_page(null,null,'pending',null,null,null,'created_at','desc',50,0);
 if (r->>'total')::int<>3 then raise exception 'FAIL: pending should list the 3 undated, got %', r->>'total'; end if;
 begin
  r:=invoice_list_page(null,null,'pending','2026-09-17','2026-09-17',null,'created_at','desc',50,0);
  raise exception 'FAIL: pending combined with a range was accepted';
 exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm not like '%DATE_RANGE_INCOMPATIBLE%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if;
 end;
 -- Reversed range: refused, never swapped.
 begin
  r:=invoice_list_page(null,null,'all','2026-09-18','2026-09-16',null,'created_at','desc',50,0);
  raise exception 'FAIL: a reversed range was accepted';
 exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm not like '%DATE_RANGE_INVALID%' then raise exception 'FAIL: wrong refusal: %', sqlerrm; end if;
 end;
 -- A recorded business date is a date: no timezone arithmetic applies to it.
 -- The undated invoice created at 00:30 Singapore on the 17th is not "on the
 -- 17th" for a range, because it has no business date at all.
 r:=invoice_list_page(null,null,'all','2026-09-17','2026-09-17',null,'created_at','desc',50,0);
 if exists (select 1 from jsonb_array_elements(r->'rows') x where x->>'invoice_no'='DR-U017') then
  raise exception 'FAIL: an undated invoice slipped into the range by its creation time'; end if;

 raise notice 'PASS: 17/09 to 17/09 lists only the 30 invoices dated the 17th, undated 08/09 and 09/09 excluded; ends inclusive; one-sided ranges; combined status and store; count and summary over the whole set; pending is the only home for undated rows and cannot take a range; reversed ranges refused';
end $$;
rollback;
