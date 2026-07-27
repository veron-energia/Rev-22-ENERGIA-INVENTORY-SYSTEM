-- =====================================================================
-- ENERGIA — PHASE 25 FIX (2): MAKE AFFILIATE QUALIFICATION VISIBLE
--
-- INV-2026-0060 and INV-2026-0062 (S$504 + S$504 = S$1,008, two customers,
-- one Affiliate, same Singapore day) produced no Affiliate Legacy reward.
--
-- The engine is correct: paying those two invoices through the normal trigger
-- path yields a residual of 1,008 and one Affiliate unit — PROVIDED an
-- Affiliate-scoped rule exists. What actually happens without one is that
-- affiliate_legacy_rule() finds nothing and awards zero units SILENTLY, with
-- nothing on screen to say so. Rules created before the Rewards selector
-- existed (or from an older build of the app) are all scoped to 'customer',
-- so that is the state the system is in.
--
-- This migration adds the read models needed to see the problem:
--   * legacy_setup_status()          — is qualification actually configured?
--   * affiliate_legacy_day_summary() — every Affiliate's residual for a date,
--                                      the units it earns, and why.
--
-- Read-only and idempotent. Run AFTER 75.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Is Legacy qualification configured at all?
-- ---------------------------------------------------------------------
create or replace function public.legacy_setup_status()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare
  v_cust integer; v_aff integer; v_aff_nonvoucher integer; v_warn text[] := '{}';
begin
  select count(*) into v_cust from public.therapy_package_rules
   where is_active = true and deleted_at is null
     and coalesce(applies_to,'customer') = 'customer' and coalesce(qualifying_amount,0) > 0;
  select count(*) into v_aff from public.therapy_package_rules
   where is_active = true and deleted_at is null
     and coalesce(applies_to,'customer') = 'affiliate' and coalesce(qualifying_amount,0) > 0;
  select count(*) into v_aff_nonvoucher from public.therapy_package_rules
   where is_active = true and deleted_at is null
     and coalesce(applies_to,'customer') = 'affiliate' and entitlement_kind <> 'voucher';

  if v_cust = 0 then
    v_warn := array_append(v_warn, 'No active Customer rule — customers cannot earn Legacy therapy.');
  end if;
  if v_aff = 0 then
    v_warn := array_append(v_warn, 'No active Affiliate rule — Affiliates will never earn a Legacy reward, however much their customers spend. Add a rule with Rewards set to Affiliate.');
  end if;
  if v_aff_nonvoucher > 0 then
    v_warn := array_append(v_warn, 'An Affiliate rule is not set to vouchers; Affiliate rewards must be vouchers.');
  end if;

  return jsonb_build_object(
    'customer_rules', v_cust, 'affiliate_rules', v_aff,
    'configured', (v_cust > 0 and v_aff > 0),
    'warnings', to_jsonb(v_warn));
end $function$;

-- ---------------------------------------------------------------------
-- 2. Every Affiliate's residual position for a Singapore date, with the
--    reason no reward was granted where that is the case.
-- ---------------------------------------------------------------------
create or replace function public.affiliate_legacy_day_summary(p_day date default null)
returns table(
  affiliate_customer_id uuid, full_name text, contributing_invoices integer,
  contributing_gross numeric, residual numeric, qualifying_amount numeric,
  units_target integer, units_existing integer, reason text)
language plpgsql stable security definer set search_path to 'public' as $function$
#variable_conflict use_column
declare v_day date := coalesce(p_day, public.sg_today()); v_a record; v_d jsonb;
begin
  for v_a in
    select distinct i.affiliate_snapshot_customer_id as aff
      from public.invoices i
     where i.affiliate_snapshot_customer_id is not null
       and coalesce(i.affiliate_active_on_paid,false)
       and i.status in ('paid','partially_paid') and coalesce(i.paid_amount,0) > 0
       and (i.paid_at at time zone 'Asia/Singapore')::date = v_day
  loop
    v_d := public.affiliate_legacy_diagnose(v_a.aff, v_day);
    return query select
      v_a.aff,
      (select c.full_name from public.customers c where c.id = v_a.aff),
      (v_d->>'contributing_invoices')::integer,
      (v_d->>'contributing_gross')::numeric,
      (v_d->>'affiliate_residual')::numeric,
      (v_d->>'qualifying_amount')::numeric,
      (v_d->>'units_target')::integer,
      (v_d->>'entitlements_existing')::integer,
      (v_d->>'reason')::text;
  end loop;
end $function$;

notify pgrst, 'reload schema';
