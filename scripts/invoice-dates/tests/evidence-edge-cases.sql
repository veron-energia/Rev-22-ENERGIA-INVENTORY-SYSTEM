begin;
create function pg_temp.check(ok boolean,msg text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception 'FAIL: %',msg;end if;raise notice 'PASS: %',msg;end$$;
do $$
declare e jsonb:='{"invoice":{"id":"29000000-0000-4000-8000-000000000099","created_at":"2020-01-01T16:00:00Z","business_date":null},"history":[],"payments":[]}';
 h jsonb; r jsonb; v jsonb;
begin
 foreach v in array array['{"imported_at":"2026-01-01T00:00:00Z"}'::jsonb,'{"original_invoice_date":"31/12/2019"}'::jsonb,'{"source":"migration"}'::jsonb] loop
  r:=plan_invoice_date_recovery(jsonb_set(e,'{invoice}',(e->'invoice')||v));
  perform pg_temp.check(r->>'classification'='manual_review','unsupported import/original-date metadata cannot authorize a creation-date guess');
 end loop;
 h:='[{"key":"original","at":"2020-01-01T16:00:00Z","kind":"invoice_created","after":{"business_date":"2019-12-01"}},
 {"key":"later","at":"2020-01-02T00:00:00Z","kind":"revision","before":{"business_date":"2019-12-01"}}]';
 r:=plan_invoice_date_recovery(jsonb_set(e,'{history}',h));
 perform pg_temp.check(r->>'classification'='manual_review','later before-only revision cannot authorize an old date');
 h:=jsonb_set(h,'{1,after}','{"business_date":null}') #- '{1,before}';
 r:=plan_invoice_date_recovery(jsonb_set(e,'{history}',h));
 perform pg_temp.check(r->>'classification'='manual_review','later NULL after-snapshot without before evidence cannot resurrect old date');
 h:='[{"key":"r1","at":"2020-01-02T00:00:00Z","kind":"revision","sequence":1,"before":{"business_date":"2019-12-01"},"after":{"business_date":"2019-12-02"}},
 {"key":"a1","at":"2020-01-02T00:00:00Z","kind":"invoice_corrected","sequence":1,"before":{"business_date":"2019-12-01"},"after":{"business_date":"2019-12-02"}},
 {"key":"r2","at":"2020-01-02T00:00:00Z","kind":"revision","sequence":2,"before":{"business_date":"2019-12-02"},"after":{"business_date":"2019-11-30"}},
 {"key":"a2","at":"2020-01-02T00:00:00Z","kind":"invoice_corrected","sequence":2,"before":{"business_date":"2019-12-02"},"after":{"business_date":"2019-11-30"}}]';
 r:=plan_invoice_date_recovery(jsonb_set(e,'{history}',h));
 perform pg_temp.check(r->>'classification'='eligible' and r->>'proposed_date'='2019-11-30','ordered same-time corrections and their exact audit copies retain the latest intentional date');
 h:=jsonb_set(h,'{1,sequence}','0');
 r:=plan_invoice_date_recovery(jsonb_set(e,'{history}',h));
 perform pg_temp.check(r->>'classification'='manual_review','unmatched conflicting same-time evidence remains manual');
end$$;
-- Verify collector attaches sequence ONLY for an exact full-header audit copy.
do $$
declare o uuid:=gen_random_uuid(); st uuid; c uuid; inv uuid; h jsonb; j jsonb; old_header jsonb; new_header jsonb;
begin
 insert into auth.users(id,email) values(o,'edge-date@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Edge Date Owner','edge-date@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Date edge tests','EDGDATE','SG') returning id into st;
 insert into customers(full_name,phone) values('Date edge buyer','+6591188889') returning id into c;
 insert into invoices(invoice_no,store_id,customer_id,created_by,business_date,created_at) values('DATE-EDGE',st,c,o,null,'2020-01-01T00:00Z') returning id into inv;
 old_header:=jsonb_build_object('id',inv,'business_date','2019-01-01','edit_count',0);
 new_header:=jsonb_build_object('id',inv,'business_date','2019-02-01','edit_count',1);
 insert into invoice_revisions(invoice_id,revision_no,snapshot,after_snapshot,edited_by,edited_at)
 values(inv,1,jsonb_build_object('invoice',old_header),jsonb_build_object('invoice',new_header),o,'2020-01-02T00:00Z');
 insert into audit_logs(table_name,record_id,action,old_data,new_data,created_at,changed_by)
 values('invoices',inv,'invoice_corrected',jsonb_build_object('invoice',old_header),jsonb_build_object('invoice',new_header),'2020-01-02T00:00Z',o);
 h:=invoice_date_evidence(inv);
 perform pg_temp.check((select bool_and((x->>'sequence')::int=1) from jsonb_array_elements(h->'history') x),'collector pairs exact audit header copies with their unique revision');
 j:=plan_invoice_date_recovery(h);
 perform pg_temp.check(j->>'proposed_date'='2019-02-01','paired collector evidence produces correct proposal');
 -- Each historical status has the same date-only path, including soft deletion.
 for h in select to_jsonb(v) from unnest(array['paid','unpaid','partially_paid','refunded','cancelled','completed_foc']) v loop
  insert into invoices(invoice_no,store_id,customer_id,created_by,business_date,created_at,status)
   values('DATE-STATUS-'||(h#>>'{}'),st,c,o,null,'2020-01-31T16:00:00Z',(h#>>'{}')::invoice_status) returning id into inv;
  select jsonb_agg(x) into j from preview_invoice_date_recovery(array[inv]) x;
  perform apply_invoice_date_recovery(gen_random_uuid(),j,'Historical status date recovery');
  perform pg_temp.check((select business_date='2020-02-01' and status::text=(h#>>'{}') and total_amount=0 from invoices where id=inv),'date recovery preserves status and totals: '||(h#>>'{}'));
 end loop;
 -- Database default is Singapore today even if the connection is elsewhere.
 perform set_config('TimeZone','America/Los_Angeles',true);
 insert into invoices(invoice_no,store_id,customer_id,created_by) values('DATE-DEFAULT',st,c,o) returning id into inv;
 perform pg_temp.check((select business_date=(now() at time zone 'Asia/Singapore')::date from invoices where id=inv),'new database date default remains Singapore today');
end$$;
rollback;
