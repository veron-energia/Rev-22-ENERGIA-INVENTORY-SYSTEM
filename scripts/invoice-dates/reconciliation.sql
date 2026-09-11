-- Run before and after recovery in a quiet/maintenance window using an approved
-- database operator connection. READ ONLY, hashes only, no customer data output.
-- Full-table hashes can be expensive; rehearse against the staging snapshot.
begin isolation level repeatable read read only;
set local timezone='UTC';
select format($q$select jsonb_build_object('table',%L,'rows',count(*),'hash',md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by md5(to_jsonb(t)::text)),''))) from public.%I t;$q$,tablename,tablename)
from pg_tables where schemaname='public' and tablename not in
 ('invoices','audit_logs','invoice_revisions','invoice_date_recovery_events','invoice_date_recovery_batches') order by tablename \gexec
-- Only the date, date-version and established edit-audit metadata may change.
select jsonb_build_object('table','invoices_operational_fields','rows',count(*),'hash',md5(coalesce(string_agg(
 md5((to_jsonb(i)-array['business_date','business_date_version','edit_count','edited_at','edited_by'])::text),'' order by i.id),''))) from public.invoices i;
select jsonb_build_object('table','invoices_date_counts','confirmed',count(*) filter(where business_date is not null),
 'pending',count(*) filter(where business_date is null),'deleted',count(*) filter(where deleted_at is not null)) from public.invoices;
select jsonb_build_object('table','recovery_events','rows',count(*)) from public.invoice_date_recovery_events;
commit;
