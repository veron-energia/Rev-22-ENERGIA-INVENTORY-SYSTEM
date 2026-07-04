-- =====================================================================
-- ENERGIA — PHASE 5A: Foundations
--   (1) Customer-based referral graph (referred_by on customers)
--   (2) Customer profile stats helper (purchases, spend, referrals, commission)
--   (3) Address enforcement is done in the app layer; columns already exist.
--
-- Additive + idempotent. Run AFTER 00_complete_setup.sql. Does not touch
-- existing objects except adding columns/policies.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Referral graph: a customer may be referred by another customer.
--    Tier 1 referrer = customers.referred_by.
--    Tier 2 referrer = referred_by of the Tier 1 referrer (derived, not stored).
-- ---------------------------------------------------------------------
alter table public.customers add column if not exists referred_by uuid references public.customers(id);
alter table public.customers add column if not exists is_referrer boolean not null default false;

create index if not exists idx_customers_referred_by on public.customers(referred_by);

-- Guard: a customer cannot refer themselves.
create or replace function public.tg_customers_no_self_referral()
returns trigger language plpgsql as $$
begin
  if new.referred_by is not null and new.referred_by = new.id then
    raise exception 'A customer cannot be their own referrer';
  end if;
  return new;
end; $$;

drop trigger if exists trg_customers_no_self_referral on public.customers;
create trigger trg_customers_no_self_referral
  before insert or update on public.customers
  for each row execute function public.tg_customers_no_self_referral();

-- ---------------------------------------------------------------------
-- 2. Resolve a customer's Tier 1 and Tier 2 referrer ids in one call.
--    Used by the commission engine (5B) and the customer profile view.
-- ---------------------------------------------------------------------
create or replace function public.customer_referrers(p_customer_id uuid)
returns table (tier1 uuid, tier2 uuid)
language sql stable security definer set search_path = public as $$
  select
    c.referred_by as tier1,
    t1.referred_by as tier2
  from public.customers c
  left join public.customers t1 on t1.id = c.referred_by
  where c.id = p_customer_id
$$;

-- ---------------------------------------------------------------------
-- 3. Customer profile stats (one row of aggregates for the profile page).
--    Spend + purchase counts come from paid invoices.
--    Commission figures come from affiliate_commissions (rewritten in 5B);
--    until 5B runs, those columns simply read 0.
-- ---------------------------------------------------------------------
create or replace function public.customer_profile_stats(p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_purchases integer := 0;
  v_total_spend numeric := 0;
  v_referred_count integer := 0;
  v_referrer_name text;
begin
  select count(*), coalesce(sum(total_amount),0)
    into v_purchases, v_total_spend
    from public.invoices
    where customer_id = p_customer_id and status = 'paid' and deleted_at is null;

  select count(*) into v_referred_count
    from public.customers where referred_by = p_customer_id and deleted_at is null;

  select c2.full_name into v_referrer_name
    from public.customers c1
    join public.customers c2 on c2.id = c1.referred_by
    where c1.id = p_customer_id;

  return jsonb_build_object(
    'purchases', v_purchases,
    'total_spend', v_total_spend,
    'referred_count', v_referred_count,
    'referrer_name', v_referrer_name
  );
end; $$;

notify pgrst, 'reload schema';
