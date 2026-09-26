-- Several imported records of one person merge into one (362).
--
-- customer_phone_migration_map holds one row per customer. Before 362 the merge
-- moved the duplicate's row onto the kept record, so when both had one — two
-- legacy imports of the same person — the merge failed on the primary key. The
-- capture now stays with the record it describes.
--
-- Shaped like the four "Alaric Ong" records of 26 Sep 2026: the kept affiliate
-- and two others carry a capture; one duplicate is a referrer with commission
-- rows, a survey and a consultant note; one was referred by the kept record.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); au uuid:=gen_random_uuid(); tag text:=substr(md5(random()::text),1,6);
 st uuid; pm uuid; prod uuid; keep uuid; d1 uuid; d2 uuid; d3 uuid; buyer uuid; inv uuid; sv uuid; aff uuid; r jsonb; n int;
begin
 insert into auth.users(id,email) values(own,'pcs-'||tag||'@tests.invalid'),(au,'pcs-a-'||tag||'@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','pcs-'||tag||'@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('PCS '||tag,'PCS'||tag,'SG') returning id into st;
 insert into payment_methods(name) values('PCS Cash '||tag) returning id into pm;
 insert into products(name,sku,product_type) values('PCS Item','PCS-'||tag,'own') returning id into prod;
 insert into store_inventory(store_id,product_id,current_qty) values(st,prod,50);
 perform set_product_prices(st,prod,100,100,'available');

 -- the kept record: an affiliate (a legacy import in the real case)
 insert into customers(first_name,last_name,phone) values('Al','Ong','+6598737299') returning id into keep;
 insert into customer_affiliates(customer_id,status,store_id,activated_at) values(keep,'active',st,now()) returning id into aff;
 insert into affiliate_accounts(auth_user_id,customer_id,affiliate_id) values(au,keep,aff);
 insert into customer_phone_migration_map(customer_id,full_name,original_phone,inspection) values(keep,'Al Ong','LEGACY','{}');
 -- d1: a referrer with commission rows, a survey, a note and its own capture
 insert into customers(first_name,phone,email) values('Al','+6598737201','pcs-'||tag||'@tests.invalid') returning id into d1;
 insert into customer_phone_migration_map(customer_id,full_name,original_phone,inspection) values(d1,'Al','98737201','{}');
 insert into health_surveys(survey_no,customer_id,full_name,first_name,phone) values('PCS-SV-'||tag,d1,'Al','Al','+6598737201') returning id into sv;
 insert into consultant_notes(survey_id,customer_id,remarks_condition) values(sv,d1,'note');
 insert into customers(first_name,last_name,phone,referred_by) values('Buyer','One','+6598737202',d1) returning id into buyer;
 inv:=create_invoice(st,buyer,null,jsonb_build_array(jsonb_build_object('kind','product','product_id',prod,'quantity',1)));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)));
 select count(*) into n from commissions where referrer_customer_id=d1;
 -- d2: signed up through the kept record's own link; holds nothing
 insert into customers(first_name,last_name,phone,referred_by) values('Al','Ong','+6598737203',keep) returning id into d2;
 -- d3: a second legacy import with its own capture
 insert into customers(first_name,last_name,phone) values('Al','(walk in) Ong','+6598737298') returning id into d3;
 insert into customer_phone_migration_map(customer_id,full_name,original_phone,inspection) values(d3,'Al (walk in) Ong','LEGACY','{}');

 r:=merge_customer_records(keep,d1,'same person',gen_random_uuid());
 if r ? 'moved' and (r->'moved') ? 'customer_phone_migration_map.customer_id' then raise exception 'A capture was moved: %', r->'moved'; end if;
 perform merge_customer_records(keep,d2,'same person',gen_random_uuid());
 perform merge_customer_records(keep,d3,'same person',gen_random_uuid());

 if (select count(*) from customers where id in (d1,d2,d3) and deleted_at is not null)<>3 then raise exception 'Not every duplicate was retired'; end if;
 if (select count(*) from customer_phone_migration_map where customer_id in (keep,d1,d3))<>3
    or (select customer_id from customer_phone_migration_map where full_name='Al (walk in) Ong' and customer_id in (keep,d3))<>d3 then
  raise exception 'The captures did not stay with their own records'; end if;
 if (select count(*) from commissions where referrer_customer_id=keep)<>n then raise exception 'The referrer''s commission rows did not move'; end if;
 if (select customer_id from health_surveys where id=sv)<>keep then raise exception 'The survey did not move'; end if;
 if (select customer_id from consultant_notes where survey_id=sv)<>keep then raise exception 'The note did not move'; end if;
 if (select referred_by from customers where id=buyer)<>keep then raise exception 'The referred customer did not move'; end if;
 if (select customer_id from affiliate_accounts where auth_user_id=au)<>keep then raise exception 'The login moved away'; end if;
 -- the kept record can now take the real phone the duplicates carried
 update customers set phone='+6598737201', email='pcs-'||tag||'@tests.invalid' where id=keep;
 if (select phone from customers where id=keep)<>'+6598737201' then raise exception 'The phone could not be set'; end if;

 raise notice 'PASS: three records with phone captures and one referred by the keeper merge into one; captures stay with their own records; commission, survey, note, referrals and login end on the kept record; it then takes the real phone';
end $$;
rollback;
