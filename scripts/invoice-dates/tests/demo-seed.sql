-- Synthetic example records. Run ONLY through the guarded local fixture tools.
begin;
do $$begin if current_database()<>'energia_invoice_date_test' or current_setting('port')<>'55445' then raise exception 'Local date fixture only';end if;end$$;
insert into auth.users(id,email) values('29000000-0000-4000-8000-000000000001','date-demo@tests.invalid');
insert into profiles(id,full_name,email,role) values('29000000-0000-4000-8000-000000000001','Date Preview Demo Owner','date-demo@tests.invalid','owner');
select set_config('request.jwt.claim.sub','29000000-0000-4000-8000-000000000001',true) as ignored \gset
insert into stores(id,name,code,country_code) values('29000000-0000-4000-8000-000000000002','Synthetic Date Demo','DATEDEM','SG');
insert into customers(id,full_name,phone) values('29000000-0000-4000-8000-000000000003','Synthetic Date Buyer','+6591188881');
insert into payment_methods(id,name) values('29000000-0000-4000-8000-000000000004','Synthetic Cash');
insert into invoices(id,invoice_no,store_id,customer_id,created_by,status,total_amount,paid_amount,business_date,created_at,notes)
select ('29000000-0000-4000-8000-00000000010'||n)::uuid,'DEMO-DATE-'||n,'29000000-0000-4000-8000-000000000002',
 '29000000-0000-4000-8000-000000000003','29000000-0000-4000-8000-000000000001',case when n=1 then 'partially_paid' else 'unpaid' end::invoice_status,
 300,case when n=1 then 150 else 0 end,case when n=2 then '2019-12-01'::date end,
 case when n=7 then 'infinity'::timestamptz else '2020-01-31T16:00:00Z'::timestamptz end,
 case when n=3 then 'Imported invoice without original date' end
from generate_series(1,7) n;
insert into invoice_payments(invoice_id,payment_method_id,amount,received_by,created_at)
values('29000000-0000-4000-8000-000000000101','29000000-0000-4000-8000-000000000004',150,'29000000-0000-4000-8000-000000000001','2020-03-01T00:00Z');
insert into audit_logs(table_name,record_id,action,new_data,created_at,changed_by) values
 ('invoices','29000000-0000-4000-8000-000000000104','invoice_created','{"business_date":"2019-11-01"}','2020-02-01','29000000-0000-4000-8000-000000000001'),
 ('invoices','29000000-0000-4000-8000-000000000104','invoice_created','{"business_date":"2019-11-02"}','2020-02-02','29000000-0000-4000-8000-000000000001'),
 ('invoices','29000000-0000-4000-8000-000000000105','invoice_created','{"business_date":"2019-10-01"}','2020-02-01','29000000-0000-4000-8000-000000000001');
insert into invoice_revisions(invoice_id,revision_no,snapshot,after_snapshot,edited_by,edited_at,edit_reason)
values('29000000-0000-4000-8000-000000000106',1,'{"invoice":{"business_date":"2020-01-01"}}','{"invoice":{"business_date":null}}',
 '29000000-0000-4000-8000-000000000001','2020-02-02','Date disputed');
commit;
