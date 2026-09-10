-- READ ONLY. Export with psql -X -f scripts/invoices/diagnose-local-definition.sql
-- Keep the output private: function definitions can reveal internal business rules.
select p.oid::regprocedure as signature, md5(pg_get_functiondef(p.oid)) as definition_hash,
       pg_get_functiondef(p.oid) as definition
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in ('update_invoice','edit_paid_invoice','create_invoice');
select c.relname as table_name,t.tgname,pg_get_triggerdef(t.oid),p.oid::regprocedure,
       pg_get_functiondef(p.oid)
from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_proc p on p.oid=t.tgfoid
where c.relnamespace='public'::regnamespace and c.relname in ('invoices','invoice_items') and not t.tgisinternal;
