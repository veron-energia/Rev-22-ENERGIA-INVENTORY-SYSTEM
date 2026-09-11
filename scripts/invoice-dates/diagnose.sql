-- PRE-MIGRATION, read-only. Use an approved read-only connection/snapshot.
-- No auth impersonation, date updates or inference from payments/invoice numbers.
begin isolation level repeatable read read only;
select jsonb_build_object('database',current_database(),'observed_at',clock_timestamp(),
 'business_date_column',exists(select 1 from information_schema.columns where table_schema='public' and table_name='invoices' and column_name='business_date'),
 'invoices',count(*),'missing_business_date',count(*) filter(where to_jsonb(i)->>'business_date' is null),
 'non_deleted_missing',count(*) filter(where i.deleted_at is null and to_jsonb(i)->>'business_date' is null)) as overview from public.invoices i;
select i.id invoice_id,i.invoice_no,i.status,s.name store,to_jsonb(i)->>'business_date' business_date,
 i.created_at original_created_at,case when isfinite(i.created_at) then (i.created_at at time zone 'Asia/Singapore')::date end creation_date_suggestion,
 i.notes,(select count(*) from public.invoice_revisions r where r.invoice_id=i.id) revision_count,
 (select count(*) from public.audit_logs a where a.table_name='invoices' and a.record_id=i.id) audit_count,
 (select count(*) from public.invoice_payments p where p.invoice_id=i.id) payment_count
from public.invoices i left join public.stores s on s.id=i.store_id
where to_jsonb(i)->>'business_date' is null order by i.id;
-- Compare these effective definitions against the tested repository BEFORE
-- recovery. Unexpected custom triggers/functions require review on staging.
select t.tgname,pg_get_triggerdef(t.oid) definition,pg_get_functiondef(t.tgfoid) function_definition
from pg_trigger t where t.tgrelid='public.invoices'::regclass and not t.tgisinternal order by t.tgname;
select p.proname,pg_get_function_identity_arguments(p.oid) arguments,pg_get_functiondef(p.oid) definition
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in
 ('create_invoice','create_exchange_invoice','correct_invoice','invoice_sales_ledger','daily_payments_by_method','sales_between','dashboard_sales','report_sales_reconciliation') order by p.proname;
commit;
