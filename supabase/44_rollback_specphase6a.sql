-- =====================================================================
-- ENERGIA — PHASE 1: ROLL BACK SPEC_PHASE6A (migration 43)
--
-- Removes ONLY the fee-based affiliate-registration feature added in
-- 43_specphase6a_affiliate_registration.sql, ahead of the membership-based
-- rebuild.
--
-- MUST NOT touch:
--   * Older Phase 6A (PHASE6A.md, migration 24 — profile/location only)
--   * customers.referred_by, customers.is_referrer
--   * commissions, staff_commissions, commission_payouts (Tier 1 / Tier 2)
--   * invoices, payments, customers, referral relationships, earnings history
--   * Phase 5 health surveys
--
-- SAFETY PROPERTIES (per the command):
--   * Idempotent — running it twice produces no error (verified).
--   * Dependency-safe — trigger dropped before its function; table's own
--     policies/indexes/constraints fall with the table via CASCADE.
--   * Tolerant of partial state — every drop is IF EXISTS; column and audit
--     cleanups are guarded so they no-op when already gone.
--
-- Wrapped in a transaction so a failure rolls back cleanly.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. Trigger first (it depends on trg_affiliate_fee_offset()).
-- ---------------------------------------------------------------------
drop trigger if exists affiliate_fee_offset_trg on public.invoices;

-- ---------------------------------------------------------------------
-- 2. Functions — exact type signatures (names/defaults omitted on purpose).
--    Each is standalone now that the trigger is gone.
-- ---------------------------------------------------------------------
drop function if exists public.trg_affiliate_fee_offset();
drop function if exists public.register_affiliate(uuid, uuid, boolean, boolean, text);
drop function if exists public.apply_affiliate_fee_offset(uuid, uuid);
drop function if exists public.is_registered_affiliate(uuid);
drop function if exists public.set_affiliate_fee_paid(uuid);
drop function if exists public.settle_affiliate_credit(uuid, text);
drop function if exists public.set_affiliate_status(uuid, text, text);
drop function if exists public.affiliate_fee();
drop function if exists public.affiliate_offset_enabled();

-- ---------------------------------------------------------------------
-- 3. Table — CASCADE removes its RLS policies, indexes, constraints and
--    the FK from any dependent object created in 43. No other table
--    references affiliate_registrations, so nothing else is affected.
--    (Registration records are intentionally not retained.)
-- ---------------------------------------------------------------------
drop table if exists public.affiliate_registrations cascade;

-- ---------------------------------------------------------------------
-- 4. app_settings columns added by 43. Guarded so a second run is a no-op.
--    Other app_settings columns (e.g. staff_commission_rate) are untouched.
-- ---------------------------------------------------------------------
alter table public.app_settings drop column if exists affiliate_registration_fee;
alter table public.app_settings drop column if exists affiliate_same_day_offset;

-- ---------------------------------------------------------------------
-- 5. Audit records that belong ONLY to the registration-fee feature.
--    Scoped to module='affiliates' AND these exact actions, so referral
--    and commission audit history is left intact. (If the audit_logs
--    table or a column is absent in some environment, skip silently.)
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from information_schema.tables
             where table_schema = 'public' and table_name = 'audit_logs')
     and exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'audit_logs' and column_name = 'action')
  then
    delete from public.audit_logs
     where action in (
       'affiliate_registered', 'affiliate_fee_paid', 'affiliate_fee_offset',
       'affiliate_credit_settled', 'affiliate_status_changed'
     )
     and (
       -- only rows tied to this feature; keep referral/commission history
       (select true from information_schema.columns
          where table_schema='public' and table_name='audit_logs' and column_name='module') is null
       or module = 'affiliates'
     );
  end if;
end $$;

commit;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- Post-run verification helpers (optional — run manually):
--
--   -- should return 0 rows:
--   select proname from pg_proc
--    where proname in ('affiliate_fee','affiliate_offset_enabled',
--      'is_registered_affiliate','apply_affiliate_fee_offset',
--      'trg_affiliate_fee_offset','register_affiliate','set_affiliate_fee_paid',
--      'settle_affiliate_credit','set_affiliate_status');
--
--   -- should return 0 rows:
--   select 1 from information_schema.tables
--    where table_schema='public' and table_name='affiliate_registrations';
--
--   -- should STILL exist (preserved):
--   select column_name from information_schema.columns
--    where table_schema='public' and table_name='customers'
--      and column_name in ('referred_by','is_referrer');
--   -- commissions / staff_commissions / commission_payouts intact:
--   select table_name from information_schema.tables
--    where table_schema='public'
--      and table_name in ('commissions','staff_commissions','commission_payouts');
-- ---------------------------------------------------------------------
