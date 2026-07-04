-- =====================================================================
-- ENERGIA — FIX: commission_status enum missing 'paid'
-- Error: invalid input value for enum commission_status: "paid"
--
-- The commission_status enum was created without 'paid'. The payout logic
-- (create_commission_payout) and the referrer views both need it.
--
-- IMPORTANT: run this file BY ITSELF, first. Postgres cannot add an enum
-- value and use it in the same transaction, so this must be its own run,
-- before 16_phase5b2_referrers.sql.
-- =====================================================================

alter type public.commission_status add value if not exists 'paid';
