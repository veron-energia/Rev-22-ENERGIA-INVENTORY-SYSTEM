-- =====================================================================
-- IS ANY create_invoice / update_invoice OVERLOAD MISSING ITS BRANCHES?
-- Supabase SQL editor. READ ONLY: one SELECT, changes nothing.
--
-- Successive migrations added arguments to create_invoice, and "create or
-- replace" with a new argument list makes a NEW function rather than replacing
-- the old one. A migration that then patches "the" function by name alone can
-- patch an overload nothing calls, report success, and leave the live one
-- untouched. That is how single-customer credit packages and premium bundles
-- came to fail with: No price set for "<NULL>" in this store.
--
-- "called_by_app = yes" is the overload create_invoice_with_details resolves
-- to, which is what the invoice screen uses. If that row says NO for either
-- branch, selling a package or bundle to a single customer is broken and
-- migration 302 is the fix.
-- =====================================================================
select p.oid::regprocedure::text                       as overload,
       case when p.proname = 'create_invoice'
                 and pg_get_function_arguments(p.oid) like '%p_service_staff%'
            then 'yes' else '' end                     as called_by_app,
       case when position('v_kind = ''credit_package''' in pg_get_functiondef(p.oid)) > 0
            then 'yes' else 'NO' end                   as credit_package_branch,
       case when position('v_kind = ''premium_bundle''' in pg_get_functiondef(p.oid)) > 0
            then 'yes' else 'NO' end                   as premium_bundle_branch,
       case when position('therapy_service_id' in pg_get_functiondef(p.oid)) > 0
            then 'yes' else '' end                     as session_branch,
       length(pg_get_functiondef(p.oid))               as definition_length
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.prokind = 'f'
   and p.proname in ('create_invoice', 'update_invoice', 'update_invoice_internal')
 order by p.proname, p.oid;
