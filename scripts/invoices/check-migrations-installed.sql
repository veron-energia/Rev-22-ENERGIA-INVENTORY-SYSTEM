-- =====================================================================
-- IS THE SALES FIX ACTUALLY IN THIS DATABASE?
-- Supabase SQL editor. READ ONLY: one SELECT, changes nothing.
--
-- "git push" ships files to GitHub. It does not run SQL against Supabase.
-- A migration only takes effect once it is run in the SQL editor, so this
-- reports what is really installed rather than what is in the repository.
-- =====================================================================
select '292 sales on payment date' as migration,
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                          where n.nspname='public' and p.proname='payment_sales_date')
            then 'INSTALLED' else 'NOT INSTALLED — run supabase/292_sales_on_payment_date.sql' end as state
union all
select '293 dashboard shares one basis',
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                          where n.nspname='public' and p.proname='invoice_sales_day')
            then 'INSTALLED' else 'NOT INSTALLED — run supabase/293_dashboard_sales_basis.sql' end
union all
select '294 cancelled/refunded leave Sales',
       case when position('invoice_counts_as_sale' in
                 pg_get_functiondef('public.invoice_sales_ledger()'::regprocedure)) > 0
            then 'INSTALLED'
            else 'NOT INSTALLED — run supabase/294_sales_exclude_voided_invoices.sql' end
union all
select '294 dashboard items/discount tiles',
       case when position('invoice_counts_as_sale' in
                 pg_get_functiondef('public.dashboard_sales(text,date,date,uuid)'::regprocedure)) > 0
            then 'INSTALLED' else 'NOT INSTALLED — run supabase/294_sales_exclude_voided_invoices.sql' end
order by 1;
