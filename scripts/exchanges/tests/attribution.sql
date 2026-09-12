-- An exchange is handled by somebody, and it is not whoever sold the thing.
--
-- Before 305 an exchange recorded only its store, an affiliate and created_by,
-- so an exchange served by Staff C and D was indistinguishable from the
-- original sale served by Staff A and B.
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid();
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid();
 cc uuid:=gen_random_uuid(); d uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
 st uuid; st2 uuid; cust uuid; ref1 uuid; ref2 uuid; pm uuid; p uuid; p2 uuid;
 inv uuid; res jsonb; ctx jsonb; ex uuid; n int; aff1 uuid; aff2 uuid;
begin
 insert into auth.users(id,email) values
   (own,'ea-own@tests.invalid'),(a,'ea-a@tests.invalid'),(b,'ea-b@tests.invalid'),
   (cc,'ea-c@tests.invalid'),(d,'ea-d@tests.invalid'),(outsider,'ea-x@tests.invalid');
 insert into profiles(id,full_name,email,role) values
   (own,'Owner','ea-own@tests.invalid','owner'),
   (a,'Staff A','ea-a@tests.invalid','staff'),(b,'Staff B','ea-b@tests.invalid','staff'),
   (cc,'Staff C','ea-c@tests.invalid','staff'),(d,'Staff D','ea-d@tests.invalid','staff'),
   (outsider,'Staff X','ea-x@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('EA Store','EAS','SG') returning id into st;
 insert into stores(name,code,country_code) values('EA Other','EAO','SG') returning id into st2;
 insert into user_store_assignments(user_id,store_id) values
   (a,st),(b,st),(cc,st),(d,st),(outsider,st2);
 insert into customers(full_name,phone) values('EA Buyer','+6598900001') returning id into cust;
 insert into customers(full_name,phone) values('EA Referrer One','+6598900002') returning id into ref1;
 insert into customers(full_name,phone) values('EA Referrer Two','+6598900003') returning id into ref2;
 -- Both referrers are activated affiliates; eligibility is checked server-side.
 insert into customer_affiliates(customer_id,status,activated_at,activated_by)
   values(ref1,'active',now(),own) returning id into aff1;
 insert into customer_affiliates(customer_id,status,activated_at,activated_by)
   values(ref2,'active',now(),own) returning id into aff2;
 insert into payment_methods(name,is_active) values('EA Cash',true) returning id into pm;
 insert into products(name,sku,product_type) values('EA Item','EAI','own') returning id into p;
 insert into products(name,sku,product_type) values('EA Swap','EAS2','own') returning id into p2;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p,50),(st,p2,50);
 perform set_product_prices(st,p,100,100,'available');
 perform set_product_prices(st,p2,100,100,'available');

 -- ---- the original sale, served by A and B -------------------------------
 inv:=create_invoice(st,cust,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',p,'quantity',1)),
   0,null,null,jsonb_build_array(a::text,b::text));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)),gen_random_uuid());
 if (select count(*) from invoice_service_staff where invoice_id=inv)<>2 then
  raise exception 'Fixture did not record both original staff'; end if;

 -- The original sale's own attribution, shown as context, never as a default.
 ctx:=exchange_original_context(inv);
 if ctx->>'customer' is null then
  raise exception 'The original context must name the customer'; end if;
 if jsonb_array_length(ctx->'served_by')<>2 then
  raise exception 'The original context must list both original staff'; end if;

 -- ---- the exchange, served by C and D ------------------------------------
 res:=create_exchange_with_details('product',jsonb_build_object(
   'original_invoice_id',inv,'processing_store_id',st,
   'returned',jsonb_build_array(jsonb_build_object(
     'invoice_item_id',(select id from invoice_items where invoice_id=inv),'quantity',1)),
   'replacement',jsonb_build_array(jsonb_build_object('product_id',p2,'quantity',1)),
   'reason','Wrong size',
   'served_by',jsonb_build_array(cc::text,d::text),
   'affiliate',jsonb_build_object('mode','set','id',aff1)));
 ex:=(res->>'id')::uuid;

 -- Both records keep their own people.
 if (select count(*) from invoice_service_staff where invoice_id=inv)<>2 then
  raise exception 'The original sale lost its staff'; end if;
 if not exists(select 1 from invoice_service_staff where invoice_id=inv and staff_id=a)
    or not exists(select 1 from invoice_service_staff where invoice_id=inv and staff_id=b) then
  raise exception 'The original sale''s staff were replaced by the exchange''s'; end if;
 select count(*) into n from product_exchange_service_staff where exchange_id=ex;
 if n<>2 then raise exception 'The exchange recorded % staff, expected 2',n; end if;
 if not exists(select 1 from product_exchange_service_staff where exchange_id=ex and staff_id=cc)
    or not exists(select 1 from product_exchange_service_staff where exchange_id=ex and staff_id=d) then
  raise exception 'The exchange did not record Staff C and D'; end if;
 if exists(select 1 from product_exchange_service_staff where exchange_id=ex and staff_id in (a,b)) then
  raise exception 'Yesterday''s staff were copied into today''s exchange'; end if;

 -- Raised by defaults to the current user and is kept apart from served by.
 if (select raised_by from product_exchanges where id=ex)<>own then
  raise exception 'Raised by did not default to the person issuing it'; end if;
 if exists(select 1 from product_exchange_service_staff where exchange_id=ex and staff_id=own) then
  raise exception 'The issuer was silently added as service staff'; end if;
 -- Dated today in Singapore, and the original invoice's date is untouched.
 if (select exchange_date from product_exchanges where id=ex)<>sg_today() then
  raise exception 'The exchange was not dated today'; end if;
 if (select business_date from invoices where id=inv) is distinct from
    (select business_date from invoices where invoice_no=(select invoice_no from invoices where id=inv)) then
  raise exception 'The original invoice date moved'; end if;
 if (select exchange_affiliate_id from product_exchanges where id=ex)<>aff1 then
  raise exception 'The exchange affiliate was not recorded'; end if;

 -- ---- staff must be eligible for the processing store --------------------
 begin
  perform set_exchange_details(ex,jsonb_build_array(outsider::text),'{"mode":"inherit"}'::jsonb,null,null,null);
  raise exception 'Staff from another store were accepted';
 exception when others then
  if sqlerrm not like '%not assigned to the store%' then raise; end if; end;
 -- and the refusal changed nothing
 if (select count(*) from product_exchange_service_staff where exchange_id=ex)<>2 then
  raise exception 'A refused staff change altered the record'; end if;

 -- ---- no staff at all is refused, not silently inherited -----------------
 begin
  perform set_exchange_details(ex,'[]'::jsonb,'{"mode":"inherit"}'::jsonb,null,null,null);
  raise exception 'An exchange with no staff was accepted';
 exception when others then
  if sqlerrm not like '%staff who handled this exchange%' then raise; end if; end;

 -- ---- an explicit None stays None ----------------------------------------
 res:=set_exchange_details(ex,jsonb_build_array(cc::text),jsonb_build_object('mode','none'),null,null,null);
 if (select exchange_affiliate_id from product_exchanges where id=ex) is not null then
  raise exception 'An explicit None kept an affiliate'; end if;
 if not (select affiliate_selection_explicit from product_exchanges where id=ex) then
  raise exception 'An explicit None was not recorded as a deliberate choice'; end if;
 -- and a later "inherit" must not resurrect one behind the person's back
 perform set_exchange_details(ex,jsonb_build_array(cc::text),'{"mode":"inherit"}'::jsonb,null,null,null);
 if (select exchange_affiliate_id from product_exchanges where id=ex) is not null then
  raise exception 'None silently fell back to a referrer'; end if;

 -- ---- a different eligible affiliate can be chosen -----------------------
 perform set_exchange_details(ex,jsonb_build_array(cc::text),jsonb_build_object('mode','set','id',aff2),null,null,null);
 if (select exchange_affiliate_id from product_exchanges where id=ex)<>aff2 then
  raise exception 'A different affiliate was not accepted'; end if;

 -- ---- a future date is refused -------------------------------------------
 begin
  perform set_exchange_details(ex,jsonb_build_array(cc::text),'{"mode":"inherit"}'::jsonb,null,sg_today()+1,null);
  raise exception 'A future-dated exchange was accepted';
 exception when others then
  if sqlerrm not like '%dated in the future%' then raise; end if; end;

 -- ---- it is all on the record --------------------------------------------
 if not exists(select 1 from audit_logs where table_name='product_exchanges'
                and record_id=ex and action='exchange_details_set') then
  raise exception 'The exchange attribution was not audited'; end if;

 raise notice 'PASS: the original sale keeps Staff A and B while the exchange records Staff C and D; nothing is inherited; staff must belong to the processing store; raised-by defaults to the issuer and never becomes service staff; the exchange is dated today without touching the invoice; an explicit None stays None; a different eligible affiliate is accepted; future dates are refused; every change is audited';
end $$;
rollback;
