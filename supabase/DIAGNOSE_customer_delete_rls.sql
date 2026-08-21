-- =====================================================================
-- DIAGNOSTIC — "new row violates row-level security policy for customers"
--
-- Read-only until section 4, which is clearly marked and optional.
-- Run in the Supabase SQL editor.
--
-- WHY THIS IS A DIAGNOSTIC RATHER THAN A FIX
--
-- Deleting a customer is a plain soft delete from the browser:
--
--     update customers set deleted_at = now(), is_active = false where id = ...
--
-- Every policy on public.customers in your migration files is permissive —
-- using (true) with check (true). None of them can produce that error. So the
-- policy rejecting it was almost certainly added directly in Supabase (the
-- dashboard's RLS editor, or an AI-generated policy), and I cannot see it from
-- the code. These queries will show it in one step.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. EVERY POLICY CURRENTLY ON customers.
--
--    Look for: permissive = 'RESTRICTIVE', or a with_check that is not "true".
--    A RESTRICTIVE policy is ANDed with the others, so one of them can block
--    an update that every permissive policy allows.
-- ---------------------------------------------------------------------
select policyname,
       permissive,                 -- RESTRICTIVE here is the usual culprit
       cmd,
       roles::text,
       qual        as using_expression,
       with_check  as with_check_expression
  from pg_policies
 where schemaname = 'public' and tablename = 'customers'
 order by permissive desc, cmd, policyname;

-- ---------------------------------------------------------------------
-- 2. IS RLS FORCED?
--
--    force_row_level_security makes policies apply even to the table owner,
--    which can make a SECURITY DEFINER function fail unexpectedly.
-- ---------------------------------------------------------------------
select relname          as table_name,
       relrowsecurity   as rls_enabled,
       relforcerowsecurity as rls_forced
  from pg_class
 where oid = 'public.customers'::regclass;

-- ---------------------------------------------------------------------
-- 3. WHICH POLICY WOULD REJECT THE SOFT DELETE?
--
--    Evaluates each policy's WITH CHECK against a row as it would look AFTER
--    the delete. Any row returning false is the one blocking you.
-- ---------------------------------------------------------------------
select p.policyname,
       p.permissive,
       p.with_check,
       case
         when p.with_check is null then 'no with_check — cannot block'
         when p.with_check = 'true' then 'allows anything'
         else 'CHECK THIS ONE — it constrains the updated row'
       end as verdict
  from pg_policies p
 where p.schemaname = 'public' and p.tablename = 'customers'
   and p.cmd in ('UPDATE', 'ALL')
 order by p.permissive desc;

-- Also worth seeing: triggers on customers. A trigger that writes back to the
-- table runs under the caller's rights unless it is SECURITY DEFINER, and can
-- raise this same error from a statement you did not write.
select t.tgname as trigger_name,
       p.proname as function_name,
       p.prosecdef as security_definer,
       pg_get_triggerdef(t.oid) as definition
  from pg_trigger t
  join pg_proc p on p.oid = t.tgfoid
 where t.tgrelid = 'public.customers'::regclass
   and not t.tgisinternal;

-- ---------------------------------------------------------------------
-- 4. OPTIONAL FIX — only run this once section 1 has shown you the culprit.
--
--    If section 1 shows a RESTRICTIVE policy you did not intend, drop it by
--    name. Read the policy first and be sure it is not doing something you
--    want; dropping a policy weakens access control.
--
--    Replace the name before running. Left commented deliberately.
-- ---------------------------------------------------------------------
-- drop policy "the name shown in section 1" on public.customers;

-- If instead the intent is simply that any signed-in user may soft-delete a
-- customer, this restores the documented behaviour without removing anything
-- else. Again, only after reading section 1.
--
-- drop policy if exists "update customers" on public.customers;
-- create policy "update customers" on public.customers
--   for update to authenticated using (true) with check (true);
