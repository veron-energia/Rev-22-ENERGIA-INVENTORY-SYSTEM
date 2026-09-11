-- Synthetic fixtures only. All data is rolled back.
begin;
create function pg_temp.check(ok boolean,msg text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception 'FAIL: %',msg;end if;raise notice 'PASS: %',msg;end$$;
create function pg_temp.operational_snapshot() returns jsonb language plpgsql as $$
declare r record; result jsonb:='{}'; v jsonb;
begin
 for r in select tablename from pg_tables where schemaname='public' and tablename not in
 ('invoices','audit_logs','invoice_revisions','invoice_date_recovery_events','invoice_date_recovery_batches') order by tablename loop
  execute format('select jsonb_build_object(''count'',count(*),''hash'',md5(coalesce(string_agg(md5(to_jsonb(t)::text),'''' order by md5(to_jsonb(t)::text)),''''))) from public.%I t',r.tablename) into v;
  result:=result||jsonb_build_object(r.tablename,v);
 end loop;
 select coalesce(jsonb_agg(to_jsonb(i)-array['business_date','business_date_version','edit_count','edited_at','edited_by'] order by id),'[]') into v from invoices i;
 return result||jsonb_build_object('invoice_operational_fields',v);
end$$;
do $$
declare o uuid:=gen_random_uuid(); m uuid:=gen_random_uuid(); staff uuid:=gen_random_uuid(); st uuid; buyer uuid; method uuid;
 ids uuid[]:=array[]::uuid[]; id uuid; n int; r jsonb; rows jsonb; snap jsonb; batch uuid:=gen_random_uuid(); reverse_batch uuid:=gen_random_uuid();
 payment uuid; audit_id uuid; view_before jsonb; orig jsonb; plan jsonb; saved_result jsonb; d date; ref uuid;
begin
 insert into auth.users(id,email) values(o,'date-owner@tests.invalid'),(m,'date-manager@tests.invalid'),(staff,'date-staff@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Date Owner','date-owner@tests.invalid','owner'),(m,'Date Manager','date-manager@tests.invalid','manager'),(staff,'Date Staff','date-staff@tests.invalid','staff');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Date Tests','DATET','SG') returning stores.id into st;
 insert into customers(full_name,phone) values('Date Customer','+6591188840') returning customers.id into buyer;
 insert into payment_methods(name) values('Date Cash') returning payment_methods.id into method;
 for n in 1..14 loop
  insert into invoices(invoice_no,store_id,customer_id,created_by,status,total_amount,paid_amount,business_date,created_at,notes)
  values('DATE-TEST-'||n,st,buyer,o,case n when 1 then 'partially_paid' when 2 then 'paid' when 3 then 'unpaid' when 4 then 'refunded' when 5 then 'cancelled' when 6 then 'draft' when 7 then 'completed_foc' else 'unpaid' end::invoice_status,
   300,case when n=1 then 150 else 0 end,case when n=3 then '2020-01-01'::date else null end,
   case when n=6 then '2020-01-31T15:59:59Z'::timestamptz else '2020-01-31T16:00:00Z'::timestamptz end,
   case when n=5 then 'Imported invoice; source date missing' end) returning invoices.id into id;
  ids:=array_append(ids,id);
 end loop;
 -- Delayed receipt date is not an invoice-date conflict. Two receipts, one invoice.
 insert into invoice_payments(invoice_id,payment_method_id,amount,received_by,created_at) values(ids[1],method,100,o,'2020-03-01T01:00Z') returning invoice_payments.id into payment;
 insert into invoice_payments(invoice_id,payment_method_id,amount,received_by,created_at) values(ids[1],method,50,o,'2020-03-02T01:00Z');
 insert into invoice_refunds(invoice_id,payment_id,amount,created_at,refunded_by,reason) values(ids[1],payment,10,'2020-04-01T01:00Z',o,'Historical refund');
 -- A reliable original date-only record.
 insert into audit_logs(table_name,record_id,action,new_data,created_at,changed_by) values
 ('invoices',ids[2],'invoice_created','{"business_date":"2019-12-31"}','2020-02-01',o);
 -- Disagreement without an ordered correction must stay pending.
 insert into audit_logs(table_name,record_id,action,new_data,created_at,changed_by) values
 ('invoices',ids[4],'invoice_created','{"business_date":"2019-11-01"}','2020-02-01',o),
 ('invoices',ids[4],'invoice_created','{"business_date":"2019-11-02"}','2020-02-02',o);
 -- Invalid timestamp available in DB ('infinity'), invalid date in JSON.
 update invoices set created_at='infinity' where invoices.id=ids[7];
 insert into audit_logs(table_name,record_id,action,new_data,created_at,changed_by) values
 ('invoices',ids[8],'invoice_created','{"business_date":"2020-02-30"}','2020-02-01',o);
 -- Intentional later correction overrides an older original, even backdated.
 insert into audit_logs(table_name,record_id,action,new_data,created_at,changed_by) values
 ('invoices',ids[9],'invoice_created','{"business_date":"2020-01-01"}','2020-02-01',o);
 insert into invoice_revisions(invoice_id,revision_no,snapshot,after_snapshot,edited_by,edited_at,edit_reason) values
 (ids[9],1,'{"invoice":{"business_date":"2020-01-01"}}','{"invoice":{"business_date":"2019-12-15"}}',o,'2020-02-02','Verified date correction'),
 (ids[9],2,'{"invoice":{"business_date":"2019-12-15"}}','{"invoice":{"business_date":"2019-12-15"}}',o,'2020-02-03','Unrelated notes');
 -- A later explicit clear must not resurrect an older date.
 insert into invoice_revisions(invoice_id,revision_no,snapshot,after_snapshot,edited_by,edited_at,edit_reason) values
 (ids[10],1,'{"invoice":{"business_date":"2020-01-01"}}','{"invoice":{"business_date":null}}',o,'2020-02-02','Date disputed');
 -- Original created_at was replaced by a later import timestamp.
 insert into audit_logs(table_name,record_id,action,old_data,new_data,created_at,changed_by) values
 ('invoices',ids[11],'invoice_updated','{"created_at":"2019-01-01T00:00:00Z"}','{"created_at":"2020-01-31T16:00:00Z"}','2020-02-02',o);
 select jsonb_agg(x) into view_before from preview_invoice_date_recovery(ids) x;
 perform pg_temp.check(jsonb_array_length(view_before)=14,'exactly one preview row per invoice across multiple payments/revisions');
 select x into r from jsonb_array_elements(view_before) x where x->>'invoice_id'=ids[1]::text;
 perform pg_temp.check(r->>'proposed_date'='2020-02-01' and (r->>'sales_to_add')::numeric=150,'SG midnight + delayed payments + 300 total / 150 received');
 select x into r from jsonb_array_elements(view_before) x where x->>'invoice_id'=ids[2]::text;
 perform pg_temp.check(r->>'proposed_date'='2019-12-31','explicit date-only evidence is preserved without timezone conversion');
 select x into r from jsonb_array_elements(view_before) x where x->>'invoice_id'=ids[3]::text;
 perform pg_temp.check(r->>'classification'='already_valid' and r->>'existing_business_date'='2020-01-01','existing intentionally backdated date preserved');
 select x into r from jsonb_array_elements(view_before) x where x->>'invoice_id'=ids[6]::text;
 perform pg_temp.check(r->>'proposed_date'='2020-01-31','instant before Singapore midnight stays on prior day');
 select x into r from jsonb_array_elements(view_before) x where x->>'invoice_id'=ids[9]::text;
 perform pg_temp.check(r->>'proposed_date'='2019-12-15' and r->>'classification'='eligible','later intentional correction wins over old date and unrelated revision');
 foreach id in array array[ids[4],ids[5],ids[7],ids[8],ids[10],ids[11]] loop
  select x into r from jsonb_array_elements(view_before) x where x->>'invoice_id'=id::text;
  perform pg_temp.check(r->>'classification'='manual_review','uncertain history remains pending: '||(r->>'invoice_no'));
 end loop;
 -- Pure planner covers sources impossible under today's NOT NULL/type constraints.
 orig:=invoice_date_evidence(ids[1]);
 foreach r in array array['null'::jsonb,'"2020-02-01T00:00:00"'::jsonb,'"nonsense"'::jsonb] loop
  plan:=plan_invoice_date_recovery(jsonb_set(orig,'{invoice,created_at}',r));
  perform pg_temp.check(plan->>'classification'='manual_review','missing/zone-less/invalid original timestamps require review');
 end loop;
 -- Preserve a manual date entered since preview; changed evidence skips too.
 update invoices set business_date='2018-07-01' where invoices.id=ids[12];
 insert into audit_logs(table_name,record_id,action,new_data,created_at,changed_by) values('invoices',ids[13],'invoice_imported','{}',clock_timestamp(),o);
 -- Harmless source metadata changes also require a fresh preview.
 update invoices set notes='Another user changed delivery details' where invoices.id=ids[14];
 select jsonb_agg(x) into rows from jsonb_array_elements(view_before) x where x->>'classification'='eligible';
 snap:=pg_temp.operational_snapshot();
 saved_result:=apply_invoice_date_recovery(batch,rows,'Verified historical date recovery');
 perform pg_temp.check(snap=pg_temp.operational_snapshot(),'all non-audit tables and every operational invoice field unchanged');
 perform pg_temp.check((select count(*)=4 from invoice_date_recovery_events where batch_id=batch),'exactly four eligible, unchanged invoices recovered');
 perform pg_temp.check((select business_date='2018-07-01' from invoices where invoices.id=ids[12]),'new manual date after preview preserved');
 perform pg_temp.check(exists(select 1 from jsonb_array_elements(saved_result) x where x->>'invoice_id'=ids[13]::text and x->>'outcome'='evidence_changed'),'new import evidence skipped');
 perform pg_temp.check(exists(select 1 from jsonb_array_elements(saved_result) x where x->>'invoice_id'=ids[14]::text and x->>'outcome'='evidence_changed'),'unrelated source change skipped for fresh review');
 perform pg_temp.check(invoice_net_sales_between(ids[1],'2020-02-01','2020-02-01')=150,'recovery attributes received 150, not invoice total 300');
 perform pg_temp.check(invoice_net_sales_between(ids[1],'2020-04-01','2020-04-01')=-10,'refund stays on refund date');
 perform pg_temp.check((select sum(amount)=150 from daily_payments_by_method('2020-03-01','2020-03-31',st)),'collections remain on actual March payment dates');
 perform pg_temp.check((select count(*)=3 from invoice_sales_ledger() where invoice_id=ids[1]),'two existing receipts and one refund appear once each');
 perform pg_temp.check(saved_result=apply_invoice_date_recovery(batch,rows,'Verified historical date recovery'),'same batch rerun returns same results');
 perform apply_invoice_date_recovery(gen_random_uuid(),rows,'Repeated reviewed set');
 perform pg_temp.check((select count(*)=4 from invoice_date_recovery_events where batch_id=batch),'rerun does not duplicate audit events');
 -- Genuine date change A→B→A prevents reversal, while unrelated metadata is safe.
 update invoices set business_date='2010-01-01' where invoices.id=ids[2];
 update invoices set business_date='2019-12-31' where invoices.id=ids[2];
 update invoices set notes='Later delivery note' where invoices.id=ids[1];
 r:=reverse_invoice_date_recovery(batch,reverse_batch,'Reverse reviewed recovery');
 perform pg_temp.check(exists(select 1 from jsonb_array_elements(r) x where x->>'invoice_id'=ids[2]::text and x->>'outcome'='date_changed_since_recovery'),'reversal cannot overwrite subsequent A→B→A date corrections');
 perform pg_temp.check((select business_date is null and notes='Later delivery note' from invoices where invoices.id=ids[1]),'reversal restores audited NULL while preserving unrelated edits');
 perform pg_temp.check(r=reverse_invoice_date_recovery(batch,reverse_batch,'Reverse reviewed recovery'),'reversal retry is idempotent');
 select x into r from preview_invoice_date_recovery(array[ids[1]]) x;
 perform pg_temp.check(r->>'classification'='manual_review','reversal is not automatically undone by another recovery');
 perform set_config('request.jwt.claim.sub',staff::text,true);
 begin perform preview_invoice_date_recovery(ids);raise exception 'Staff accepted';exception when insufficient_privilege then null;end;
 begin perform apply_invoice_date_recovery(gen_random_uuid(),rows,'Staff');raise exception 'Staff write accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',m::text,true);
 perform pg_temp.check((select count(*)=14 from preview_invoice_date_recovery(ids)),'active Manager can preview');
 perform set_config('request.jwt.claim.sub',o::text,true);
 update profiles set is_active=false where profiles.id=m;
 perform set_config('request.jwt.claim.sub',m::text,true);
 begin perform preview_invoice_date_recovery(ids);raise exception 'Inactive Manager accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',o::text,true);
 execute 'set local role authenticated';
 perform pg_temp.check((select count(*)=14 from public.preview_invoice_date_recovery(ids)),'Owner RPC works under authenticated database role');
 begin perform public.invoice_date_evidence(ids[1]);raise exception 'Private helper exposed';exception when insufficient_privilege then null;end;
 begin update public.invoice_date_recovery_events set reason='changed';raise exception 'Audit write exposed';exception when insufficient_privilege then null;end;
 execute 'reset role';
 raise notice 'PASS: roles and private-helper/audit restrictions';
end $$;
rollback;
