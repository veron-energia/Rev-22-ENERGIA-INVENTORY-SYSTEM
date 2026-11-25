-- Removes the reinstall + re-earn fixtures. Isolated local database only.
-- Safe to run when there is nothing to remove, so the runner uses it both to
-- clear a failed earlier run and to leave the fixture as it found it.
\set ON_ERROR_STOP on
begin;
do $m536$ begin if exists (select 1 from pg_trigger where tgrelid = to_regclass('public.audit_logs') and tgname = 'audit_logs_keep_every_entry') then alter table public.audit_logs disable trigger audit_logs_keep_every_entry; end if; end $m536$;  -- 536: this removes an earlier run's Audit Log rows; the row trigger is switched back on before the commit
delete from public.audit_logs where record_id in (select id from public.invoices where invoice_no like 'REEARN-%');
delete from public.commissions where invoice_id in (select id from public.invoices where invoice_no like 'REEARN-%');
delete from public.invoice_items where invoice_id in (select id from public.invoices where invoice_no like 'REEARN-%');
delete from public.invoices where invoice_no like 'REEARN-%';
delete from public.customer_affiliates where customer_id in (select id from public.customers where full_name like 'Reearn %');
delete from public.customers where full_name like 'Reearn %';
delete from public.promotions where code = 'REEARN-PROMO';
delete from public.products where sku = 'REEARN-OWN';
delete from public.stores where code = 'REEARN';
delete from public.profiles where email = 'reearn-owner@tests.invalid';
delete from auth.users where email = 'reearn-owner@tests.invalid';
update public.app_settings set commission_tier2_own_rate = 5, commission_tier2_third_rate = 5 where id = true;
do $m536$ begin if exists (select 1 from pg_trigger where tgrelid = to_regclass('public.audit_logs') and tgname = 'audit_logs_keep_every_entry') then alter table public.audit_logs enable always trigger audit_logs_keep_every_entry; end if; end $m536$;  -- 536: back on, as 536 made it
commit;
