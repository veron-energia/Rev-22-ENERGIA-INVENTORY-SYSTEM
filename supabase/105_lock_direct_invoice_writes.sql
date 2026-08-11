-- =====================================================================
-- ENERGIA — SECURITY: INVOICES MUST BE WRITTEN THROUGH THE FUNCTIONS
--
-- Migration 08 gave `authenticated` direct INSERT and UPDATE on public.invoices:
--
--     create policy "create invoices for accessible store" on public.invoices
--       for insert to authenticated with check (user_has_store_access(store_id));
--     create policy "update accessible invoices" on public.invoices
--       for update to authenticated using (user_has_store_access(store_id));
--
-- The phase 9 security suite asserts these should NOT exist — sensitive tables
-- are meant to be written only through SECURITY DEFINER functions. That
-- lockdown was never written, so the assertion has been failing and the gap has
-- been open.
--
-- It is not theoretical. Verified against a live database with RLS enforced,
-- acting as the `authenticated` role: a STAFF member could run
--
--     update public.invoices set total_amount = 1 where id = <a paid invoice>;
--
-- and it succeeded. That bypasses create_invoice/update_invoice validation, the
-- settled-invoice lock, edit_paid_invoice()'s Owner/Manager check, its revision
-- snapshot, and the stock and commission reversal that a correction performs.
--
-- The policies are removed here. Nothing in the application writes invoices
-- directly — every path goes through an RPC — so this closes the hole without
-- removing any working behaviour.
--
-- Additive and idempotent. Run AFTER 104.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- Remove the direct write policies. SELECT is untouched: staff still read the
-- invoices for their stores exactly as before.
-- ---------------------------------------------------------------------
drop policy if exists "create invoices for accessible store" on public.invoices;
drop policy if exists "update accessible invoices" on public.invoices;

-- The same check applied to every table the security suite names, in case any
-- other direct write policy was added along the way.
do $$
declare r record;
begin
  for r in
    select tablename, policyname
      from pg_policies
     where schemaname = 'public'
       and tablename in ('commissions','staff_commissions','invoice_refunds',
                         'purchased_therapy_entitlements','customer_affiliates',
                         'consultant_notes','invoices','invoice_items','app_settings')
       and cmd in ('INSERT','UPDATE','DELETE','ALL')
       and 'authenticated' = any(roles)
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
    raise notice 'Removed direct write policy %.%', r.tablename, r.policyname;
  end loop;
end $$;

notify pgrst, 'reload schema';
