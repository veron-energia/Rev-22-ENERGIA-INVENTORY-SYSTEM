begin;
do $$
declare own uuid:=gen_random_uuid(); c uuid; c2 uuid; st uuid; svc uuid; prod uuid; pm uuid; inv uuid; line uuid; pline uuid; session_id uuid; pay uuid;
 payload jsonb; reply jsonb; saved jsonb; request uuid; failed boolean;
begin
 insert into auth.users(id,email) values(own,'sessions@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Session Owner','sessions@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('Sessions','SES','SG') returning id into st;
 insert into customers(full_name,phone) values('Session Buyer','+6591238722') returning id into c;
 insert into customers(full_name,phone) values('Session Recipient','+6591238723') returning id into c2;
 insert into therapy_services(service_code,name,standard_price,duration_minutes,is_active) values('SES','Original Session',60,30,true) returning id into svc;
 insert into therapy_service_stores(service_id,store_id) values(svc,st);
 insert into payment_methods(name) values('Session Cash') returning id into pm;
 insert into products(name,sku,product_type) values('Session Test Product','SES-P','own') returning id into prod;
 insert into store_inventory(store_id,product_id,current_qty) values(st,prod,20);
 perform set_product_prices(st,prod,100,100,'available');
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',3),jsonb_build_object('kind','product','product_id',prod,'quantity',1)),jsonb_build_object('business_date',sg_today()));
 if exists(select 1 from customer_therapy_sessions where invoice_id=inv) then raise exception 'Unpaid session grant'; end if;
 if has_function_privilege('authenticated','public.create_therapy_sessions_for_invoice(uuid)','execute') then raise exception 'Unaudited session granting is callable'; end if;
 if create_therapy_sessions_for_invoice(inv)<>0 then raise exception 'Helper granted unpaid sessions'; end if;
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',280)),gen_random_uuid());
 select id into line from invoice_items where invoice_id=inv and therapy_service_id=svc;
 select id into pline from invoice_items where invoice_id=inv and product_id=prod;
 select id into session_id from customer_therapy_sessions where invoice_item_id=line and is_current;
 select id into pay from invoice_payments where invoice_id=inv;
 if session_id is null or (select remaining from customer_therapy_session_balance(c) where service_id=svc)<>3 then raise exception 'Paid sessions not issued'; end if;
 payload:=jsonb_build_array(jsonb_build_object('invoice_item_id',line,'kind','therapy','therapy_service_id',svc,'quantity',3,'unit_price',60),jsonb_build_object('invoice_item_id',pline,'kind','product','product_id',prod,'quantity',1,'unit_price',100));
 select to_jsonb(s) into saved from customer_therapy_sessions s where id=session_id;
 update therapy_services set standard_price=999,name='Changed catalogue',is_active=false where id=svc;
 perform correct_invoice(inv,payload,'{}','Unrelated saved invoice',gen_random_uuid());
 if (select to_jsonb(s) from customer_therapy_sessions s where id=session_id)<>saved then raise exception 'No-op changed saved session'; end if;
 if (select therapy_service_name_snapshot from invoice_items where id=line)<>'Original Session' then raise exception 'Saved session name replaced'; end if;
 -- Simulate an attendance recorded by the owning operational system.
 update customer_therapy_sessions set quantity_used=1 where id=session_id;
 failed:=false;
 begin
  perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',line,'amount',180)),jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',180)),'[]','Attempt consumed refund',gen_random_uuid());
 exception when others then if sqlerrm not like '%whole unused therapy sessions%' then raise; end if; failed:=true; end;
 if not failed then raise exception 'Consumed session refunded'; end if;
 request:=gen_random_uuid();
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',line,'amount',60)),jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',60)),'[]','One unused session',request);
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',line,'amount',60)),jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',60)),'[]','One unused session',request);
 if (select quantity_refunded from customer_therapy_sessions where id=session_id)<>1 or (select remaining from customer_therapy_session_balance(c) where service_id=svc)<>1 then raise exception 'Partial session refund/retry left incorrect rights'; end if;
 if (select remaining from therapy_customer_entitlements(c) where source_kind='sessions')<>1 then raise exception 'Combined rights reader ignored session refund'; end if;
 if (select status from invoices where id=inv)<>'paid' then raise exception 'Mixed invoice incorrectly terminal'; end if;
 perform cancel_invoice_recorded(inv,'Cancel remaining unused session',gen_random_uuid());
 if exists(select 1 from customer_therapy_session_balance(c) where service_id=svc) then raise exception 'Cancellation retained unused rights'; end if;
 reply:=invoice_reopen_preview(inv);
 if (reply->>'sessions_to_reinstate_after_settlement')::int<>2 then raise exception 'Incorrect reopen session preview: %',reply; end if;
 perform reopen_invoice(inv,'Reopen while preserving used session',gen_random_uuid());
 if exists(select 1 from customer_therapy_session_balance(c) where service_id=svc) then raise exception 'Unsettled reopened session became usable'; end if;
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',60)),gen_random_uuid());
 if (select remaining from customer_therapy_session_balance(c) where service_id=svc)<>2 or (select quantity_used from customer_therapy_sessions where id=session_id)<>1 then raise exception 'Reopening lost used history or duplicated sessions'; end if;
 failed:=false;
 begin perform correct_invoice(inv,payload,jsonb_build_object('customer_id',c2),'Change used recipient',gen_random_uuid());
 exception when others then if sqlerrm not like '%Used therapy sessions%' then raise; end if; failed:=true; end;
 if not failed then raise exception 'Moved consumed session history'; end if;
 -- A separate wholly unused purchase may change quantity and recipient atomically.
 update therapy_services set is_active=true,standard_price=60 where id=svc;
 inv:=create_invoice_with_details(st,c,jsonb_build_array(jsonb_build_object('kind','therapy','therapy_service_id',svc,'quantity',2)),jsonb_build_object('business_date',sg_today()));
 perform record_invoice_payment(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',120)),gen_random_uuid());
 select id into line from invoice_items where invoice_id=inv;
 payload:=jsonb_build_array(jsonb_build_object('invoice_item_id',line,'kind','therapy','therapy_service_id',svc,'quantity',1,'unit_price',60));
 perform correct_invoice(inv,payload,jsonb_build_object('customer_id',c2),'Correct unused purchase recipient and quantity',gen_random_uuid());
 if (select count(*) from customer_therapy_sessions where invoice_id=inv)<>2
  or (select quantity_purchased from customer_therapy_sessions where invoice_id=inv and is_current)<>1
  or (select customer_id from customer_therapy_sessions where invoice_id=inv and is_current)<>c2 then raise exception 'Unused correction failed to preserve old grant and issue corrected one'; end if;
 if (invoice_financial_position(inv)->>'refund_due')::numeric<>60 then raise exception 'Correction did not retain refund due'; end if;
 raise notice 'PASS: session creation security, snapshot/no-op, used-only limit, partial refund, retry, cancel/reopen, rights read models and unused recipient/quantity correction';
end $$;
rollback;
