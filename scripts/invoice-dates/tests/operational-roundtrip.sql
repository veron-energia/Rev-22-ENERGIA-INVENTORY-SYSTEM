-- Appended inside the existing rich operational fixture's transaction by
-- run-local.sh. Fixture setup/real operational actions precede this snapshot.
create function pg_temp.date_integrity_snapshot() returns jsonb language plpgsql as $$
declare r record; out jsonb:='{}'; v jsonb;
begin
 for r in select tablename from pg_tables where schemaname='public' and tablename not in
 ('invoices','audit_logs','invoice_revisions','invoice_date_recovery_events','invoice_date_recovery_batches') order by tablename loop
  execute format('select jsonb_build_object(''count'',count(*),''hash'',md5(coalesce(string_agg(md5(to_jsonb(t)::text),'''' order by md5(to_jsonb(t)::text)),''''))) from public.%I t',r.tablename) into v;
  out:=out||jsonb_build_object(r.tablename,v);
 end loop;
 select coalesce(jsonb_agg(to_jsonb(i)-array['business_date','business_date_version','edit_count','edited_at','edited_by'] order by id),'[]') into v from invoices i;
 return out||jsonb_build_object('invoice_operational_fields',v);
end $$;
do $$
declare ids uuid[]; i record; o uuid; before jsonb; rows jsonb; result jsonb; batch uuid:=gen_random_uuid(); applied int;
begin
 select id into o from profiles where role='owner' and is_active and deleted_at is null limit 1;
 perform set_config('request.jwt.claim.sub',o::text,true);
 -- Simulate migration-171 legacy NULL dates in these disposable historical
 -- fixtures only. This is not part of the recovery/deployment procedure.
 select array_agg(id) into ids from invoices;
 -- Fixture-only source evidence: retain the exact selected date before making
 -- it NULL, so this integrity test can exercise every historical status even
 -- when its older operational audit snapshots are incomplete.
 insert into audit_logs(table_name,record_id,action,old_data,new_data,changed_by,created_at)
 select 'invoices',id,'invoice_date_verified','{"business_date":null}'::jsonb,
  jsonb_build_object('business_date',business_date),o,clock_timestamp() from invoices where business_date is not null;
 update invoices set business_date=null where id=any(ids);
 before:=pg_temp.date_integrity_snapshot();
 select jsonb_agg(x) into rows from preview_invoice_date_recovery(ids) x where x->>'classification'='eligible';
 if rows is null then raise exception 'Rich fixture produced no eligible invoices';end if;
 result:=apply_invoice_date_recovery(batch,rows,'Historical date verified in operational fixture');
 select count(*) into applied from jsonb_array_elements(result) x where x->>'outcome'='recovered';
 if applied<1 then raise exception 'No invoices recovered in rich fixture';end if;
 if before<>pg_temp.date_integrity_snapshot() then raise exception 'Date recovery altered operational tables';end if;
 perform reverse_invoice_date_recovery(batch,gen_random_uuid(),'Reverse isolated date fixture');
 if before<>pg_temp.date_integrity_snapshot() then raise exception 'Date reversal altered operational tables';end if;
 raise notice 'PASS: % rich historical invoices recovered/reversed; stock, payments/refunds, credit lots, vouchers, sessions, qualifications, commissions, payout corrections/allocations, TikTok and all other operational tables unchanged',applied;
end $$;
