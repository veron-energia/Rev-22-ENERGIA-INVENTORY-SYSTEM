-- =====================================================================
-- ENERGIA — PHASE 4A: Invoice membership detection & pricing (schema + reads)
--
-- This is the FIRST half of Phase 4. It adds the schema and the read-only
-- detection/pricing functions the UI needs, but DOES NOT modify pay_invoice
-- or create memberships. The atomic payment rewrite is Phase 4B, kept
-- separate so the working payment path is never in a half-changed state.
--
-- Additive + idempotent. Run AFTER 46_member_nonmember_pricing.sql.
-- =====================================================================

set check_function_bodies = off;

-- =====================================================================
-- 1. Invoice line: membership kind + price snapshot + override trail
-- =====================================================================
-- line_kind is an enum ('product','voucher','promotion'); add 'membership'
-- and 'therapy' so a membership can be a first-class non-stock line.
do $$
begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                 where t.typname = 'invoice_line_kind' and e.enumlabel = 'membership') then
    alter type invoice_line_kind add value 'membership';
  end if;
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                 where t.typname = 'invoice_line_kind' and e.enumlabel = 'therapy') then
    alter type invoice_line_kind add value 'therapy';
  end if;
end $$;

-- Price snapshot + membership references on the line.
alter table public.invoice_items add column if not exists price_mode text
  check (price_mode is null or price_mode in ('member','non_member'));
alter table public.invoice_items add column if not exists price_source text;   -- 'product'/'promotion'/'voucher'/'membership'/'manual_override'
alter table public.invoice_items add column if not exists original_price numeric(12,2);
alter table public.invoice_items add column if not exists price_overridden boolean not null default false;
alter table public.invoice_items add column if not exists override_reason text;
alter table public.invoice_items add column if not exists override_by uuid references public.profiles(id);
alter table public.invoice_items add column if not exists override_at timestamptz;
alter table public.invoice_items add column if not exists membership_plan_id uuid references public.membership_plans(id);

-- =====================================================================
-- 2. Expiry-warning thresholds (Owner/Manager editable, global)
-- =====================================================================
alter table public.app_settings add column if not exists membership_warn_months_1 integer not null default 3;
alter table public.app_settings add column if not exists membership_warn_months_2 integer not null default 1;

-- =====================================================================
-- 3. Membership detection for a customer (used on invoice + at payment)
-- =====================================================================
-- Returns the customer's current live membership with an effective status
-- recomputed from today's Singapore date, plus a warning level.
create or replace function public.customer_membership_status(p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_m public.customer_memberships%rowtype;
  v_eff text; v_plan public.membership_plans%rowtype;
  v_w1 integer; v_w2 integer; v_days_left integer; v_warn text := null;
begin
  select membership_warn_months_1, membership_warn_months_2 into v_w1, v_w2 from public.app_settings where id;

  select * into v_m from public.customer_memberships
   where customer_id = p_customer_id and deleted_at is null
     and status in ('active','expiring_soon','pending_payment','suspended')
   order by case status when 'active' then 0 when 'expiring_soon' then 1 else 2 end, expiry_date desc nulls last
   limit 1;

  if not found then
    return jsonb_build_object('is_member', false, 'status', 'none');
  end if;

  select * into v_plan from public.membership_plans where id = v_m.plan_id;
  v_eff := public.membership_effective_status(v_m.status, v_m.start_date, v_m.expiry_date, greatest(v_w1,3) * 30);

  if v_m.expiry_date is not null then
    v_days_left := v_m.expiry_date - public.sg_today();
    if v_days_left < 0 then v_warn := 'expired';
    elsif v_days_left <= v_w2 * 30 then v_warn := 'one_month';
    elsif v_days_left <= v_w1 * 30 then v_warn := 'three_month';
    end if;
  end if;

  return jsonb_build_object(
    'is_member', v_eff in ('active','expiring_soon'),
    'membership_id', v_m.id,
    'membership_no', v_m.membership_no,
    'member_id', v_m.member_id,
    'plan_id', v_m.plan_id,
    'plan_name', v_plan.name,
    'store_id', v_m.store_id,
    'start_date', v_m.start_date,
    'expiry_date', v_m.expiry_date,
    'days_left', v_days_left,
    'status', v_eff,
    'raw_status', v_m.status,
    'warning', v_warn,
    'is_complimentary', v_m.is_complimentary
  );
end $$;

-- =====================================================================
-- 4. Resolve the price for a product at a store, given member/non-member.
--    Returns member/non-member/eligibility so the UI can price a line and
--    flag when a product isn't sellable to that customer type.
-- =====================================================================
create or replace function public.product_price_for(
  p_store_id uuid, p_product_id uuid, p_is_member boolean
) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_spp public.store_product_prices%rowtype; v_price numeric; v_mode text; v_eligible boolean;
begin
  select * into v_spp from public.store_product_prices where store_id = p_store_id and product_id = p_product_id;
  if not found then
    return jsonb_build_object('found', false);
  end if;

  v_mode := case when p_is_member then 'member' else 'non_member' end;
  v_price := case when p_is_member then v_spp.member_price else v_spp.non_member_price end;

  -- Eligibility: is this customer type allowed to buy without an override?
  v_eligible := case coalesce(v_spp.eligibility,'both')
    when 'both' then true
    when 'member_only' then p_is_member
    when 'non_member_only' then not p_is_member
    else false end;

  return jsonb_build_object(
    'found', true,
    'eligibility', coalesce(v_spp.eligibility,'both'),
    'price_mode', v_mode,
    'price', v_price,
    'member_price', v_spp.member_price,
    'non_member_price', v_spp.non_member_price,
    'eligible', v_eligible,
    'has_price', v_price is not null
  );
end $$;

-- =====================================================================
-- 5. Expiry-threshold setter (Owner/Manager)
-- =====================================================================
create or replace function public.set_membership_warn_thresholds(p_months_1 integer, p_months_2 integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit thresholds'; end if;
  if coalesce(p_months_1,0) <= 0 or coalesce(p_months_2,0) <= 0 then raise exception 'Thresholds must be positive'; end if;
  update public.app_settings set membership_warn_months_1 = p_months_1, membership_warn_months_2 = p_months_2 where id;
  perform public.write_audit_ex('app_settings', null, 'membership_thresholds_set',
    null, jsonb_build_object('months_1', p_months_1, 'months_2', p_months_2), 'membership', null, null);
end $$;

-- =====================================================================
-- 6. Nightly-safe status refresh (callable; also used before reads).
--    Moves memberships to expiring_soon / expired based on today's date.
--    Does NOT touch cancelled/suspended/pending.
-- =====================================================================
create or replace function public.refresh_membership_statuses()
returns integer language plpgsql security definer set search_path = public as $$
declare v_w1 integer; v_n integer := 0;
begin
  select membership_warn_months_1 into v_w1 from public.app_settings where id;
  with upd as (
    update public.customer_memberships m
       set status = public.membership_effective_status(m.status, m.start_date, m.expiry_date, greatest(v_w1,3)*30),
           updated_at = now()
     where m.deleted_at is null
       and m.status in ('active','expiring_soon')
       and public.membership_effective_status(m.status, m.start_date, m.expiry_date, greatest(v_w1,3)*30) <> m.status
     returning 1)
  select count(*) into v_n from upd;
  return v_n;
end $$;

notify pgrst, 'reload schema';
