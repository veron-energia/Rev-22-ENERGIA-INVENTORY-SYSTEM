-- The guided refund/cancellation workflow.
--
-- These assertions state the rules the workflow exists to enforce, so that a
-- later change cannot quietly drop one: a request changes nothing, only an
-- Owner/Manager approves, goods are not assumed returned, the five-day window
-- runs from the invoice's own creation date and cannot be restarted, and an
-- approver is never allowed to approve something other than what was asked.
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); stf uuid:=gen_random_uuid(); other uuid:=gen_random_uuid();
 st uuid; st2 uuid; c uuid; pm uuid; p uuid; inv uuid; inv2 uuid;
 req jsonb; res jsonb; plan jsonb; w jsonb; it uuid; pay uuid; mv jsonb; n numeric; s text; q int;
begin
 insert into auth.users(id,email) values(own,'ga-own@tests.invalid'),(stf,'ga-stf@tests.invalid'),(other,'ga-oth@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (own,'Owner','ga-own@tests.invalid','owner'),
   (stf,'Store Staff','ga-stf@tests.invalid','staff'),
   (other,'Other Staff','ga-oth@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('GA Adelphi','GAA','SG') returning id into st;
 insert into stores(name,code,country_code) values('GA Van','GAV','SG') returning id into st2;
 insert into user_store_assignments(user_id,store_id) values(stf,st),(other,st2);
 insert into customers(full_name,phone) values('GA Buyer','+6598880001') returning id into c;
 insert into payment_methods(name,is_active) values('GA PayNow',true) returning id into pm;
 insert into products(name,sku,product_type) values('GA Corset','GAC','own') returning id into p;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,100);
 perform set_product_prices(st,p,100,100,'available');

 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',3)),
   jsonb_build_object('business_date',sg_today()::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',300)),gen_random_uuid());

 -- ---- the five-day window -----------------------------------------------
 w:=invoice_action_window(inv);
 if (w->>'deadline')::date<>(w->>'created_on')::date+4 then
  raise exception 'The window must be five days counting the creation day, got % from %',w->>'deadline',w->>'created_on'; end if;
 if not (w->>'within')::boolean then raise exception 'A new invoice must be inside the window'; end if;

 update invoices set created_at=now()-interval '4 days' where id=inv;
 if not (invoice_action_window(inv)->>'within')::boolean then
  raise exception 'Day five must still be inside the window'; end if;
 update invoices set created_at=now()-interval '5 days' where id=inv;
 if (invoice_action_window(inv)->>'within')::boolean then
  raise exception 'Day six must be outside the window'; end if;

 -- 301: the column the window is measured from is protected, so the rule does
 -- not rest on nobody happening to write it. Application roles reach invoices
 -- only through security-definer functions, none of which touch created_at,
 -- and a direct write is refused for any non-superuser.
 if not exists(select 1 from pg_trigger where tgname='invoice_created_at_immutable' and not tgisinternal) then
  raise exception 'The invoice creation time is unprotected; the five-day window rests on it'; end if;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='public' and p.prokind='f'
              and pg_get_functiondef(p.oid) ~* 'update[[:space:]]+public\.invoices[[:space:]]+set[^;]*created_at[[:space:]]*=') then
  raise exception 'Some function now writes invoices.created_at, which would move the refund window'; end if;

 -- Backdating, correcting and reopening must not restart it.
 w:=invoice_action_window(inv);
 update invoices set business_date=sg_today() where id=inv;
 if (invoice_action_window(inv)->>'deadline')<>(w->>'deadline') then
  raise exception 'Changing the business date restarted the window'; end if;
 update invoices set business_date=sg_today()-20 where id=inv;
 if (invoice_action_window(inv)->>'deadline')<>(w->>'deadline') then
  raise exception 'Backdating the business date restarted the window'; end if;
 update invoices set created_at=now() where id=inv;   -- back inside for the rest

 -- ---- a request changes nothing -----------------------------------------
 perform set_config('request.jwt.claim.sub',stf::text,true);
 req:=request_invoice_action_v2(inv,'refund_full','[]'::jsonb,'Customer changed their mind','All three coming back',gen_random_uuid());
 select status into s from invoices where id=inv;
 if s<>'paid' then raise exception 'Submitting a request changed the invoice status to %',s; end if;
 if exists(select 1 from invoice_refunds where invoice_id=inv) then
  raise exception 'Submitting a request recorded a refund'; end if;
 if (select current_qty from store_inventory where store_id=st and product_id=p)<>97 then
  raise exception 'Submitting a request returned stock'; end if;
 if (req#>>'{plan,refund_amount}')::numeric<>300 then
  raise exception 'The request must carry the amount the system calculated, got %',req#>>'{plan,refund_amount}'; end if;

 -- One pending request at a time.
 begin
  perform request_invoice_action_v2(inv,'cancel','[]'::jsonb,'second thoughts',null,gen_random_uuid());
  raise exception 'A second pending request was allowed';
 exception when others then
  if sqlerrm not like '%already waiting for approval%' then raise; end if;
 end;
 -- Resubmitting the same request id returns the same request, not a new one.
 if (select count(*) from approval_requests where related_record_id=inv)<>1 then
  raise exception 'Duplicate request rows'; end if;

 -- ---- only an Owner/Manager approves ------------------------------------
 begin
  perform resolve_invoice_action_v2((req->>'request_id')::uuid,true,'approving my own');
  raise exception 'Staff approved their own request';
 exception when others then
  if sqlerrm not like '%Only an Owner or Manager%' then raise; end if;
 end;

 -- ---- staff cannot reach another store's invoice -------------------------
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into store_inventory(store_id,product_id,current_qty) values(st2,p,10);
 perform set_product_prices(st2,p,100,100,'available');
 inv2:=create_invoice_with_details(st2,c,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 perform set_config('request.jwt.claim.sub',stf::text,true);
 begin
  perform invoice_action_plan(inv2,'refund_full');
  raise exception 'Staff saw an invoice outside their assigned stores';
 exception when others then
  if sqlerrm not like '%not accessible%' then raise; end if;
 end;
 begin
  perform request_invoice_action_v2(inv2,'refund_full','[]'::jsonb,'not mine',null,gen_random_uuid());
  raise exception 'Staff raised a request outside their assigned stores';
 exception when others then
  if sqlerrm not like '%not accessible%' then raise; end if;
 end;

 -- ---- goods are not assumed returned ------------------------------------
 perform set_config('request.jwt.claim.sub',own::text,true);
 begin
  perform resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Approved');
  raise exception 'Approved without confirming the returned goods';
 exception when others then
  if sqlerrm not like '%Confirm the returned, damaged and not-returned%' then raise; end if;
 end;

 -- ---- approval re-derives, and refuses a changed plan --------------------
 select id into it from invoice_items where invoice_id=inv;
 select id into pay from invoice_payments where invoice_id=inv;
 select jsonb_build_array(jsonb_build_object('movement_id',id,'sellable_quantity',1)) into mv
   from stock_movements where invoice_id=inv and movement_type='store_sale' limit 1;
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'amount',100)),
   jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',100)),mv,'One returned early',gen_random_uuid());
 -- An unrelated refund must NOT close somebody else's pending request.
 if (select status from approval_requests where id=(req->>'request_id')::uuid)<>'pending' then
  raise exception 'An unrelated refund closed the pending request'; end if;

 plan:=invoice_action_plan(inv,'refund_full');
 if (plan->>'refund_amount')::numeric<>200 then
  raise exception 'The re-derived plan must account for the refund that already happened, got %',plan->>'refund_amount'; end if;
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Approve',null,'[]'::jsonb,
   jsonb_build_array(jsonb_build_object('movement_id',plan#>>'{stock,0,movement_id}',
     'sellable_quantity',2,'damaged_quantity',0,'not_returned_quantity',0)),false);
 if not coalesce((res->>'confirmation_required')::boolean,false) then
  raise exception 'A materially changed plan was approved without confirmation'; end if;
 if (select count(*) from invoice_refunds where invoice_id=inv)<>1 then
  raise exception 'A refund was recorded while asking for confirmation'; end if;

 -- Confirming the revised plan by its own hash proceeds, and damaged goods
 -- do not become sellable again.
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'Approve revised',plan->>'plan_hash','[]'::jsonb,
   jsonb_build_array(jsonb_build_object('movement_id',plan#>>'{stock,0,movement_id}',
     'sellable_quantity',1,'damaged_quantity',1,'not_returned_quantity',0)),false);
 if res->>'status'<>'approved' then raise exception 'Confirming the revised plan did not approve it'; end if;
 if (res#>>'{outcome,refunded_amount}')::numeric<>200 then
  raise exception 'The revised amount was not the amount refunded, got %',res#>>'{outcome,refunded_amount}'; end if;
 select current_qty into q from store_inventory where store_id=st and product_id=p;
 if q<>99 then raise exception 'Expected 97 + 1 early + 1 sellable = 99 in stock, got % (a damaged unit must not return to sale)',q; end if;

 -- ---- a repeat click reports, it does not repeat -------------------------
 res:=resolve_invoice_action_v2((req->>'request_id')::uuid,true,'clicked again');
 if not coalesce((res->>'already_resolved')::boolean,false) then
  raise exception 'A repeated approval was not recognised as already resolved'; end if;
 if (select count(*) from invoice_refunds where invoice_id=inv and request_id=(req->>'request_id')::uuid)<>1 then
  raise exception 'A repeated approval refunded twice'; end if;

 raise notice 'PASS: window boundaries, a protected creation time, immunity to backdating, request changes nothing, staff cannot approve or reach other stores, goods must be confirmed, changed plans need explicit confirmation, damaged goods stay out of stock, repeat clicks do not repeat';
end $$;
rollback;
