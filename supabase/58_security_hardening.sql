-- =====================================================================
-- ENERGIA — 58: PHASE 9 SECURITY HARDENING
--
-- Defence-in-depth: several early tables were created with broad
-- "for all / for insert / for update to authenticated" write policies. All
-- writes to these tables now flow through SECURITY DEFINER functions that
-- enforce the role/store matrix, so the direct-write policies are redundant
-- AND dangerous (any authenticated user could bypass the gates via the REST
-- API). This migration removes the direct write access and keeps read access,
-- so the database — not just the frontend — enforces the permission model.
--
-- Verified before writing this: no frontend path writes these tables directly;
-- every mutation goes through create_invoice / pay_invoice / affiliate / therapy
-- functions. app_settings keeps a write path but only via a new gated RPC.
--
-- Additive + idempotent. Run AFTER 57.
-- =====================================================================

set check_function_bodies = off;

-- ── invoices: writes via create_invoice / pay_invoice / refund fns only ──
drop policy if exists "create invoices" on public.invoices;
drop policy if exists "update invoices" on public.invoices;
-- (read policy is left intact)

-- ── invoice_items: writes via the invoice functions only ──
drop policy if exists "write invoice items" on public.invoice_items;
drop policy if exists "read invoice items" on public.invoice_items;
create policy "read invoice items" on public.invoice_items for select to authenticated using (true);

-- ── affiliates (legacy table): superseded by customer_affiliates + functions ──
drop policy if exists "manage affiliates" on public.affiliates;
drop policy if exists "read affiliates" on public.affiliates;
create policy "read affiliates" on public.affiliates for select to authenticated using (true);

-- ── therapy_package_rules: retired (target-based); read-only now ──
drop policy if exists "write therapy rules" on public.therapy_package_rules;
drop policy if exists "read therapy rules" on public.therapy_package_rules;
create policy "read therapy rules" on public.therapy_package_rules for select to authenticated using (true);

-- ── app_settings: replace the blanket write policy with read-only + a gated RPC ──
drop policy if exists "write settings" on public.app_settings;
drop policy if exists "read settings" on public.app_settings;
create policy "read settings" on public.app_settings for select to authenticated using (true);

-- Owner/Manager-gated staff commission rate setter (replaces the direct
-- app_settings update the Staff Commissions page used to do).
create or replace function public.set_staff_commission_rate(p_rate numeric)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can change the staff commission rate'; end if;
  if p_rate is null or p_rate < 0 or p_rate > 100 then
    raise exception 'Rate must be between 0 and 100'; end if;
  update public.app_settings set staff_commission_rate = p_rate, updated_at = now() where id = true;
  perform public.write_audit('app_settings', null, 'staff_commission_rate_set',
    null, jsonb_build_object('rate', p_rate));
end $$;

notify pgrst, 'reload schema';
