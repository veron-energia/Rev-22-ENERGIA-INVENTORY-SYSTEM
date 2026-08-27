-- =====================================================================
-- ONE QUERY. Paste into the Supabase SQL editor and run.
-- Read-only. No functions, no temp tables, no psql commands.
--
-- It answers, in one table, everything needed to explain why the names do not
-- sync in either direction.
-- =====================================================================

select 'A. COLUMNS' as check_name,
       table_name || '.' || column_name as detail,
       'exists' as value
  from information_schema.columns
 where table_schema = 'public'
   and table_name in ('customers', 'health_surveys')
   and column_name in ('first_name', 'last_name', 'full_name')

union all

-- The triggers that carry the names between the two tables.
-- EXPECTED, at minimum:
--   customers      -> sync_customer_name        (keeps parts and whole in step)
--   customers      -> sync_customer_to_surveys  (pushes customer -> surveys)
--   health_surveys -> sync_survey_name          (keeps parts and whole in step)
-- If sync_customer_to_surveys is MISSING, the customer -> survey direction
-- cannot work at all, and that is the answer.
select 'B. TRIGGERS',
       c.relname || ' -> ' || t.tgname,
       case when t.tgenabled = 'D' then 'DISABLED' else 'enabled' end
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
 where c.relname in ('customers', 'health_surveys')
   and not t.tgisinternal

union all

-- More than one version of the edit function means a call can land on an older
-- one that ignores the arguments it does not have.
select 'C. EDIT FUNCTION VERSIONS',
       case when pg_get_function_identity_arguments(p.oid) like '%p_has_medical_condition%'
            then 'FULL version' else 'OLD SHORT VERSION' end,
       left(pg_get_function_identity_arguments(p.oid), 90)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'update_survey_particulars'

union all

-- Does the customer -> survey trigger function actually carry the name parts?
select 'D. SYNC FUNCTION',
       'carries first_name',
       case when p.prosrc like '%first_name%' then 'yes' else 'NO — this is the fault' end
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'trg_sync_customer_to_surveys'

union all

-- Five real pairs, so you can see whether they actually differ.
-- Limited inside its own subquery, so it cannot crowd out the sections above.
select * from (
  select 'E. LIVE PAIRS' as check_name,
         coalesce(c.full_name, '(no customer)') as detail,
         'customer: ' || coalesce(c.first_name, '-') || ' / ' || coalesce(c.last_name, '-')
         || '   survey: ' || coalesce(hs.first_name, '-') || ' / ' || coalesce(hs.last_name, '-')
         || case when coalesce(c.first_name,'') is distinct from coalesce(hs.first_name,'')
                   or coalesce(c.last_name,'')  is distinct from coalesce(hs.last_name,'')
                 then '   <-- DIFFERENT' else '   (match)' end as value
    from public.health_surveys hs
    left join public.customers c on c.id = hs.customer_id
   where hs.customer_id is not null
   order by 2
   limit 25
) e

order by 1, 2;
