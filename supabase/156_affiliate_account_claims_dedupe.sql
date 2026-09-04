-- =====================================================================
-- ENERGIA — AFFILIATE ACCOUNT CLAIMS: DUPLICATE-PENDING FIX
--
-- complete_affiliate_onboarding() (migration 155) parks ambiguous identity as
-- a row in affiliate_account_claims and used `on conflict do nothing` — but no
-- constraint existed to conflict on, so repeated onboarding attempts by the
-- same Auth user (before an Owner/Manager resolves the first) piled up multiple
-- 'pending' rows. This adds a partial unique index so a given Auth user can hold
-- at most ONE pending claim; resolved/rejected history is unaffected and the
-- existing `on conflict do nothing` becomes a genuine idempotency guard.
--
-- Additive and idempotent. Run AFTER 155.
-- =====================================================================

set check_function_bodies = off;

-- Collapse any pre-existing duplicate pendings first: keep the earliest per
-- Auth user, mark the rest 'rejected' so the unique index can be created.
with ranked as (
  select id, row_number() over (partition by auth_user_id order by created_at, id) as rn
  from public.affiliate_account_claims
  where status = 'pending'
)
update public.affiliate_account_claims c
   set status = 'rejected',
       resolution_note = coalesce(c.resolution_note, 'Superseded duplicate pending claim (auto-dedupe 156)')
  from ranked r
 where c.id = r.id and r.rn > 1;

create unique index if not exists uq_affiliate_claims_one_pending
  on public.affiliate_account_claims(auth_user_id)
  where status = 'pending';

do $$
begin
  if not exists (select 1 from pg_indexes where indexname = 'uq_affiliate_claims_one_pending') then
    raise exception 'pending-claim unique index missing';
  end if;
  raise notice 'Confirmed: at most one pending affiliate account claim per Auth user.';
end $$;

notify pgrst, 'reload schema';
