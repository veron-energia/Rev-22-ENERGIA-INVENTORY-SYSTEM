-- Isolated local database only. Fixtures roll back.
begin;
create function pg_temp.check(ok boolean, message text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception 'FAIL: %',message;end if;end$$;
do $$
declare owner_id uuid:=gen_random_uuid(); manager_id uuid:=gen_random_uuid(); staff_id uuid:=gen_random_uuid(); admin_id uuid:=gen_random_uuid();
 st uuid; ref uuid; buyer uuid; method uuid; method2 uuid; inv uuid; first_entry uuid; p1 uuid; p2 uuid; request uuid; r jsonb; snapshot jsonb; bad numeric; n integer;
 v_month date:='2020-02-01';
begin
 insert into auth.users(id,email) values(owner_id,'payout-owner@tests.invalid'),(manager_id,'payout-manager@tests.invalid'),(staff_id,'payout-staff@tests.invalid'),(admin_id,'payout-admin@tests.invalid');
 insert into profiles(id,full_name,email,role) values(owner_id,'Payout Owner','payout-owner@tests.invalid','owner'),(manager_id,'Payout Manager','payout-manager@tests.invalid','manager'),(staff_id,'Payout Staff','payout-staff@tests.invalid','staff'),(admin_id,'Payout Admin','payout-admin@tests.invalid','admin');
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 insert into stores(name,code,country_code) values('Payout tests','PAYT','SG') returning id into st;
 insert into customers(full_name,phone) values('Payout Referrer','+6591118841') returning id into ref;
 insert into customers(full_name,phone) values('Payout Buyer','+6591118842') returning id into buyer;
 insert into payment_methods(name) values('Payout Test Cash') returning id into method;
 insert into payment_methods(name) values('Payout Test Bank') returning id into method2;
 insert into invoices(invoice_no,store_id,customer_id,created_by,status) values('PAYOUT-TEST',st,buyer,owner_id,'paid') returning id into inv;
 insert into commissions(invoice_id,buyer_customer_id,referrer_customer_id,tier,product_type,line_amount,rate,commission_amount,invoice_paid_date)
 values(inv,buyer,ref,'tier1','own',2000,15,300,'2020-02-02') returning id into first_entry;
 request:=gen_random_uuid();
 r:=record_affiliate_payout(ref,v_month,150,method,'2020-03-01','First','First half',request);p1:=(r->>'id')::uuid;
 perform pg_temp.check(r=record_affiliate_payout(ref,v_month,150,method,'2020-03-01','First','First half',request),'same request returns same result');
 perform pg_temp.check((select balance=150 and paid=150 from affiliate_month_balances() where referrer=ref),'300 → 150 paid / 150 remaining');
 perform pg_temp.check((select count(*)=1 and sum(amount)=150 from commission_payout_allocations where payout_id=p1),'partial allocation of one entry');
 perform pg_temp.check((select commission_amount=300 and payout_id=p1 and status='paid' from commissions where id=first_entry),'original amount preserved and anchored');
 r:=record_affiliate_payout(ref,v_month,150,method,'2020-03-02',null,null,gen_random_uuid());p2:=(r->>'id')::uuid;
 perform pg_temp.check((select balance=0 and paid=300 from affiliate_month_balances() where referrer=ref),'two distinct 150 payments clear 300');
 perform pg_temp.check((select count(*)=2 from commission_payouts where referrer_customer_id=ref),'separate payouts retained');
 r:=correct_affiliate_payout(p1,1,100,method,'2020-03-01','First','Corrected half','Transcription error',gen_random_uuid());
 perform pg_temp.check((select balance=50 and paid=250 from affiliate_month_balances() where referrer=ref),'decrease only releases 50, later payout remains');
 perform correct_affiliate_payout(p2,1,100,method,'2020-03-02',null,null,'Second transcription error',gen_random_uuid());
 request:=gen_random_uuid();
 r:=correct_affiliate_payout(p1,2,150,method2,'2020-03-05','Bank 123','Verified receipt','Correction confirmed',request);
 perform pg_temp.check(r=correct_affiliate_payout(p1,2,150,method2,'2020-03-05','Bank 123','Verified receipt','Correction confirmed',request),'edit replay checked before stale version');
 perform pg_temp.check((select balance=50 from affiliate_month_balances() where referrer=ref),'increase consumes delta only');
 select jsonb_agg(to_jsonb(a) order by id) into snapshot from commission_payout_allocations a where payout_id=p1;
 update payment_methods set is_active=false where id=method2;
 perform correct_affiliate_payout(p1,3,150,method2,'2020-03-06','Updated reference','Updated notes','Metadata only',gen_random_uuid());
 perform pg_temp.check(snapshot=(select jsonb_agg(to_jsonb(a) order by id) from commission_payout_allocations a where payout_id=p1),'metadata correction and inactive method do not move allocation');
 perform pg_temp.check((select payment_date='2020-03-06' and payment_method_name='Payout Test Bank' and reference='Updated reference' and notes='Updated notes' from commission_payouts where id=p1),'effective metadata stored');
 perform pg_temp.check((select count(*)=4 from commission_payout_changes where payout_id=p1),'creation and each correction audited');
 perform pg_temp.check((affiliate_payout_history(p1)->'original'->>'total_amount')::numeric=150,'original record retained');
 foreach bad in array array[0,-1,50.001,51,'NaN'::numeric,'Infinity'::numeric] loop
  begin perform record_affiliate_payout(ref,v_month,bad,method,'2020-03-02',null,null,gen_random_uuid());raise exception 'Invalid payout accepted';
  exception when others then if sqlerrm='Invalid payout accepted' then raise;end if;end;
 end loop;
 begin perform correct_affiliate_payout(p1,1,150,method,'2020-03-01',null,null,'Stale',gen_random_uuid());raise exception 'Stale accepted';exception when serialization_failure then null;end;
 begin perform correct_affiliate_payout(p1,4,150,method,'2020-03-01',null,null,' ',gen_random_uuid());raise exception 'Blank reason accepted';exception when others then if sqlerrm not like '%reason is required%' then raise;end if;end;
 begin perform record_affiliate_payout(ref,v_month,1,null,'2020-03-02',null,null,gen_random_uuid());raise exception 'Missing method accepted';exception when others then if sqlerrm not like '%payment method%' then raise;end if;end;
 begin perform record_affiliate_payout(ref,v_month,1,method,sg_today()+1,null,null,gen_random_uuid());raise exception 'Future date accepted';exception when others then if sqlerrm not like '%after today%' then raise;end if;end;
 begin perform record_affiliate_payout(ref,v_month,1,method,'2020-03-02','Changed',null,request);raise exception 'Reused key accepted';exception when others then if sqlerrm not like '%identifier was already used%' then raise;end if;end;
 perform pg_temp.check((referrer_earnings(ref)->'lifetime'->>'total_paid')::numeric=250,'referrer paid matches cash');
 perform pg_temp.check((referrer_earnings(ref)->'lifetime'->>'total_earned')::numeric=50,'referrer unpaid matches balance');
 perform pg_temp.check((select unpaid_earned=50 from referrer_list() where customer_id=ref),'directory totals updated');
 perform pg_temp.check((select count(*)=1 from jsonb_array_elements(referrer_earnings(ref)->'lines')),'report keeps original single line');
 perform pg_temp.check((select paid=250 from report_affiliates() where customer_id=ref),'affiliate export paid means paid, not unpaid');
 perform affiliate_payout_overview();perform affiliate_admin_directory();

 -- All identity states remain visible only to permitted staff, never guessed.
 perform pg_temp.check((select count(*)=1 from commission_referrer_names(array[ref])),'active identity');
 update customers set is_active=false where id=ref;
 perform pg_temp.check((select count(*)=1 from commission_referrer_names(array[ref])),'inactive identity');
 update customers set deleted_at=now() where id=ref;
 perform pg_temp.check((select full_name='Payout Referrer' from commission_referrer_names(array[ref])),'deleted historical identity');
 perform pg_temp.check((select count(*)=0 from commission_referrer_names(array[gen_random_uuid()])),'unavailable identity is not invented');
 perform set_config('request.jwt.claim.sub',staff_id::text,true);
 begin perform record_affiliate_payout(ref,v_month,1,method,'2020-03-02',null,null,gen_random_uuid());raise exception 'Staff payout accepted';exception when insufficient_privilege then null;end;
 begin perform commission_referrer_names(array[ref]);raise exception 'Staff names accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 perform affiliate_payout_overview();
 begin perform correct_affiliate_payout(p1,4,150,method,'2020-03-01',null,null,'Admin',gen_random_uuid());raise exception 'Admin write accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',manager_id::text,true);
 perform record_affiliate_payout(ref,v_month,50,method,'2020-03-02',null,null,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 update profiles set is_active=false where id=manager_id;
 perform set_config('request.jwt.claim.sub',manager_id::text,true);
 begin perform affiliate_payout_overview();raise exception 'Inactive manager accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 begin perform create_commission_payout(ref,v_month,method,null,null);raise exception 'Legacy writer bypass accepted';exception when others then if sqlerrm not like '%screen needs an update%' then raise;end if;end;
 perform pg_temp.check(not has_function_privilege('anon','public.record_affiliate_payout(uuid,date,numeric,uuid,date,text,text,uuid)','execute'),'anonymous RPC denied');
 execute 'set local role authenticated';
 begin update public.commission_payouts set total_amount=1 where id=p1;raise exception 'Direct write accepted';exception when insufficient_privilege then null;end;
 begin insert into public.commission_payout_allocations(payout_id,commission_id,amount,operation_id) values(p1,first_entry,1,gen_random_uuid());raise exception 'Direct allocation accepted';exception when insufficient_privilege then null;end;
 execute 'reset role';
 raise notice 'PASS: partials, later payouts, corrections, replay, precision/caps, metadata, audit, totals, names and access';

 -- Deterministic oldest-first across both tiers; a negative adjustment lowers
 -- the cap but is never allocated as a new payable entry.
 insert into commissions(id,invoice_id,buyer_customer_id,referrer_customer_id,tier,product_type,line_amount,rate,commission_amount,invoice_paid_date,created_at)
 values('28000000-0000-4000-8000-000000000001',inv,buyer,ref,'tier1','own',100,15,100,'2020-04-01','2020-04-01'),
 ('28000000-0000-4000-8000-000000000002',inv,buyer,ref,'tier2','own',100,5,100,'2020-04-01','2020-04-01'),
 ('28000000-0000-4000-8000-000000000003',inv,buyer,ref,'tier1','own',100,15,100,'2020-04-02','2020-04-01'),
 ('28000000-0000-4000-8000-000000000004',inv,buyer,ref,'tier1','own',100,15,-20,'2020-04-02','2020-04-01');
 r:=record_affiliate_payout(ref,'2020-04-01',150,method,'2020-05-01',null,null,gen_random_uuid());p1:=(r->>'id')::uuid;
 perform pg_temp.check((select total_tier1=100 and total_tier2=50 from commission_payouts where id=p1),'oldest first / UUID tiebreak / both tiers');
 perform correct_affiliate_payout(p1,1,100,method,'2020-05-01',null,null,'Reduce',gen_random_uuid());
 perform pg_temp.check((select balance=180 from affiliate_month_balances() where referrer=ref and month='2020-04-01'),'adjustments count with released capacity');
 perform record_affiliate_payout(ref,'2020-04-01',180,method,'2020-05-02',null,null,gen_random_uuid());
 perform pg_temp.check(not exists(select 1 from commission_payout_allocations where commission_id='28000000-0000-4000-8000-000000000004'),'negative adjustment never allocated as payable');
 perform pg_temp.check((select balance=0 from affiliate_month_balances() where referrer=ref and month='2020-04-01'),'adjustment cap exact');
 -- Exact requested correction example, independent commission month.
 insert into commissions(invoice_id,buyer_customer_id,referrer_customer_id,tier,product_type,line_amount,rate,commission_amount,invoice_paid_date)
 values(inv,buyer,ref,'tier1','own',2000,15,300,'2020-06-02');
 r:=record_affiliate_payout(ref,'2020-06-01',150,method,'2020-07-01',null,null,gen_random_uuid());p1:=(r->>'id')::uuid;
 perform correct_affiliate_payout(p1,1,100,method,'2020-07-01',null,null,'Correction example',gen_random_uuid());
 perform pg_temp.check((select balance=200 from affiliate_month_balances() where referrer=ref and month='2020-06-01'),'150 corrected to 100 leaves 200');
 perform record_affiliate_payout(ref,'2020-06-01',200,method,'2020-07-02',null,null,gen_random_uuid());
 perform pg_temp.check((select balance=0 from affiliate_month_balances() where referrer=ref and month='2020-06-01'),'remaining 200 settles');
 raise notice 'PASS: deterministic cross-tier allocation, negative adjustments, 300 → 150 → 100 → +200';
end$$;
rollback;
