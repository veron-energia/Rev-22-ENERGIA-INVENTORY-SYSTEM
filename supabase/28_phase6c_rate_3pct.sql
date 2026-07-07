-- =====================================================================
-- ENERGIA — Set staff commission rate to 3% (was 5%).
-- Equal split among service staff is unchanged: each paid invoice pays
-- 3% of its after-discount total, divided equally among the service
-- staff on that invoice. Already-earned commissions keep their old rate.
-- Safe to re-run. You can also change this anytime via the Rate button.
-- =====================================================================
update public.app_settings set staff_commission_rate = 3.0, updated_at = now() where id = true;
