begin;
do $$
declare o uuid:=gen_random_uuid(); st uuid; buyer uuid; ref uuid; method uuid; inv uuid; p uuid; bad uuid;
begin
 insert into auth.users(id,email) values(o,'legacy-payout@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Legacy Owner','legacy-payout@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Legacy Test','LPAY','SG') returning id into st;
 insert into customers(full_name,phone) values('Legacy Referrer','+6591118871') returning id into ref;
 insert into customers(full_name,phone) values('Legacy Buyer','+6591118872') returning id into buyer;
 insert into payment_methods(name,is_active) values('Legacy Cheque',false) returning id into method;
 insert into invoices(invoice_no,store_id,customer_id,created_by,status) values('LEGACY-PAYOUT',st,buyer,o,'paid') returning id into inv;
 insert into commission_payouts(payout_month,referrer_customer_id,total_tier1,total_tier2,total_amount,payment_method_id,paid_by,paid_at,reference)
 values('2020-01-01',ref,160,120,280,method,o,'2020-02-01 18:00:00+00','Verified legacy') returning id into p;
 insert into commissions(invoice_id,buyer_customer_id,referrer_customer_id,tier,product_type,line_amount,rate,commission_amount,invoice_paid_date,status,payout_id)
 values(inv,buyer,ref,'tier1','own',1200,15,180,'2020-01-02','paid',p),(inv,buyer,ref,'tier2','own',1200,5,120,'2020-01-03','paid',p),(inv,buyer,ref,'tier1','own',-100,15,-20,'2020-01-04','paid',p);
 insert into commission_payouts(payout_month,referrer_customer_id,total_tier1,total_amount,payment_method_id,paid_by,reference)
 values('2020-02-01',ref,200,200,method,o,'Ambiguous legacy') returning id into bad;
 insert into commissions(invoice_id,buyer_customer_id,referrer_customer_id,tier,product_type,line_amount,rate,commission_amount,invoice_paid_date,status,payout_id)
 values(inv,buyer,ref,'tier1','own',1200,15,180,'2020-02-02','paid',bad),
 (inv,buyer,ref,'tier1','own',1000,15,150,'2020-03-02','paid',null),
 (inv,buyer,ref,'tier1','own',1000,15,150,'2020-04-02','paid',bad);
end$$;
commit;
