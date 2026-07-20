-- =====================================================================
-- ENERGIA — PHASE 5: MEMBERSHIP-BASED AFFILIATE SYSTEM
--
-- Replaces the (already rolled-back) fee-based affiliate model with one where
-- an ACTIVE PAID MEMBERSHIP + a valid physical Member ID makes a customer an
-- eligible affiliate. No fee. Existing referral tree (customers.referred_by)
-- and existing earned commissions are preserved.
--
-- NUMBERING: the spec names 48_membership_affiliates.sql, but 48 is already the
-- payment migration. This is delivered as 51 (48/48b/48c/49/50 precede it).
--
-- Additive + idempotent. Run AFTER 50_membership_management.sql.
-- =====================================================================

set check_function_bodies = off;

-- =====================================================================
-- 1. Commission 'blocked' status + block reason.
--    Payouts already sum only status='earned', so 'blocked' is automatically
--    excluded from every payout total — permanently, never released.
-- =====================================================================
do $$
begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid=e.enumtypid
                 where t.typname='commission_status' and e.enumlabel='blocked') then
    alter type commission_status add value 'blocked';
  end if;
end $$;

alter table public.commissions add column if not exists block_reason text;

-- =====================================================================
-- 2. Affiliate profiles.
-- =====================================================================
create table if not exists public.customer_affiliates (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null unique references public.customers(id),

  -- Live status is DERIVED (see customer_affiliate_state); this stored status
  -- holds the manual dimension (active vs manually suspended) + last computed.
  status text not null default 'active'
    check (status in ('active','suspended_manual',
                      'inactive_membership_expired','inactive_missing_member_id','inactive_no_membership')),
  manually_suspended boolean not null default false,

  activated_at timestamptz, activated_by uuid references public.profiles(id),
  suspended_at timestamptz, suspended_by uuid references public.profiles(id), suspend_reason text,
  reactivated_at timestamptz, reactivated_by uuid references public.profiles(id),
  membership_expired_at timestamptz,

  store_id uuid references public.stores(id),
  notes text,

  deleted_at timestamptz,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_caff_customer on public.customer_affiliates(customer_id);
create index if not exists idx_caff_status on public.customer_affiliates(status) where deleted_at is null;

alter table public.customer_affiliates enable row level security;
drop policy if exists "read affiliates" on public.customer_affiliates;
create policy "read affiliates" on public.customer_affiliates for select to authenticated using (true);
-- Writes go through SECURITY DEFINER functions only.

-- =====================================================================
-- 3. Eligibility resolver — the single source of truth.
--    A customer is an ELIGIBLE affiliate iff:
--      * they have an affiliate profile that is not manually suspended and not
--        soft-deleted, AND
--      * they hold a CURRENT active membership (covers today), AND
--      * they own a valid physical Member ID, AND
--      * their customer record is active.
--    Returns the derived state + the block reason when not eligible.
-- =====================================================================
create or replace function public.customer_affiliate_state(p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_a public.customer_affiliates%rowtype; v_c public.customers%rowtype;
  v_ms jsonb; v_has_id boolean; v_state text; v_eligible boolean := false; v_reason text := null;
begin
  select * into v_c from public.customers where id = p_customer_id;
  select * into v_a from public.customer_affiliates where customer_id = p_customer_id and deleted_at is null;
  v_ms := public.customer_membership_status(p_customer_id);
  v_has_id := exists (select 1 from public.member_ids where customer_id = p_customer_id);

  if v_a.id is null then
    -- No affiliate profile at all -> not activated.
    v_state := 'not_activated'; v_reason := 'Affiliate Not Activated';
  elsif v_a.manually_suspended then
    v_state := 'suspended_manual'; v_reason := 'Affiliate Suspended';
  elsif v_c.id is null or v_c.deleted_at is not null then
    v_state := 'inactive_no_membership'; v_reason := 'No Active Membership';
  elsif not v_has_id then
    v_state := 'inactive_missing_member_id'; v_reason := 'Missing Member ID';
  elsif not coalesce((v_ms->>'is_member')::boolean,false) then
    -- Distinguish expired from never-had.
    if (v_ms->>'status') = 'expired' or v_ms ? 'expiry_date' then
      v_state := 'inactive_membership_expired'; v_reason := 'Membership Expired';
    else
      v_state := 'inactive_no_membership'; v_reason := 'No Active Membership';
    end if;
  else
    v_state := 'active'; v_eligible := true;
  end if;

  return jsonb_build_object(
    'eligible', v_eligible, 'state', v_state, 'block_reason', v_reason,
    'has_profile', v_a.id is not null, 'manually_suspended', coalesce(v_a.manually_suspended,false),
    'has_member_id', v_has_id, 'member_id', v_ms->>'member_id',
    'membership_status', v_ms->>'status', 'membership_expiry', v_ms->>'expiry_date',
    'store_id', v_a.store_id);
end $$;

-- Convenience boolean for the commission engine.
create or replace function public.is_eligible_affiliate(p_customer_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((public.customer_affiliate_state(p_customer_id)->>'eligible')::boolean, false)
$$;

create or replace function public.affiliate_block_reason(p_customer_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select public.customer_affiliate_state(p_customer_id)->>'block_reason'
$$;

-- =====================================================================
-- 4. Activate / suspend / reactivate / assign store (Owner/Manager).
-- =====================================================================
create or replace function public.activate_affiliate(p_customer_id uuid, p_store_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_ms jsonb; v_c public.customers%rowtype;
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can activate affiliates'; end if;
  select * into v_c from public.customers where id = p_customer_id and deleted_at is null;
  if not found then raise exception 'Customer not found or inactive'; end if;

  -- Requirements: active paid membership + valid Member ID.
  v_ms := public.customer_membership_status(p_customer_id);
  if not coalesce((v_ms->>'is_member')::boolean,false) then
    raise exception 'Customer needs an active paid membership before becoming an affiliate'; end if;
  if not exists (select 1 from public.member_ids where customer_id = p_customer_id) then
    raise exception 'Customer needs a valid Member ID before becoming an affiliate'; end if;

  insert into public.customer_affiliates (customer_id, status, manually_suspended, store_id, activated_at, activated_by, created_by, updated_by)
  values (p_customer_id, 'active', false, p_store_id, now(), auth.uid(), auth.uid(), auth.uid())
  on conflict (customer_id) do update
    set manually_suspended = false, status = 'active', deleted_at = null,
        store_id = coalesce(excluded.store_id, public.customer_affiliates.store_id),
        reactivated_at = now(), reactivated_by = auth.uid(), updated_by = auth.uid(), updated_at = now()
  returning id into v_id;

  perform public.write_audit_ex('customer_affiliates', v_id, 'affiliate_activated',
    null, jsonb_build_object('customer', v_c.full_name, 'store', p_store_id), 'affiliates', null, p_store_id);
  return v_id;
end $$;

create or replace function public.suspend_affiliate(p_customer_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_a public.customer_affiliates%rowtype;
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can suspend affiliates'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'A reason is required to suspend an affiliate'; end if;
  select * into v_a from public.customer_affiliates where customer_id = p_customer_id and deleted_at is null;
  if not found then raise exception 'Affiliate not found'; end if;

  update public.customer_affiliates
     set manually_suspended = true, status = 'suspended_manual',
         suspended_at = now(), suspended_by = auth.uid(), suspend_reason = trim(p_reason),
         updated_by = auth.uid(), updated_at = now()
   where id = v_a.id;
  perform public.write_audit_ex('customer_affiliates', v_a.id, 'affiliate_suspended',
    jsonb_build_object('status', v_a.status), jsonb_build_object('status','suspended_manual'),
    'affiliates', p_reason, v_a.store_id);
end $$;

create or replace function public.reactivate_affiliate(p_customer_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_a public.customer_affiliates%rowtype; v_ms jsonb;
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can reactivate affiliates'; end if;
  select * into v_a from public.customer_affiliates where customer_id = p_customer_id and deleted_at is null;
  if not found then raise exception 'Affiliate not found'; end if;

  -- Reactivation clears the MANUAL suspension. Eligibility is then re-derived
  -- (still needs a live membership + Member ID to actually earn).
  update public.customer_affiliates
     set manually_suspended = false, status = 'active',
         reactivated_at = now(), reactivated_by = auth.uid(),
         suspended_at = null, suspend_reason = null, updated_by = auth.uid(), updated_at = now()
   where id = v_a.id;
  perform public.write_audit_ex('customer_affiliates', v_a.id, 'affiliate_reactivated',
    jsonb_build_object('status', v_a.status), jsonb_build_object('status','active'),
    'affiliates', null, v_a.store_id);
end $$;

create or replace function public.set_affiliate_store(p_customer_id uuid, p_store_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_a public.customer_affiliates%rowtype;
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can assign an affiliate store'; end if;
  select * into v_a from public.customer_affiliates where customer_id = p_customer_id and deleted_at is null;
  if not found then raise exception 'Affiliate not found'; end if;
  update public.customer_affiliates set store_id = p_store_id, updated_by = auth.uid(), updated_at = now() where id = v_a.id;
  perform public.write_audit_ex('customer_affiliates', v_a.id, 'affiliate_store_set',
    jsonb_build_object('store', v_a.store_id), jsonb_build_object('store', p_store_id), 'affiliates', null, p_store_id);
end $$;

-- Refresh stored status from derived state (safe to call anytime / nightly).
-- Manually-suspended affiliates stay suspended; expiry-only inactives flip back
-- to active automatically when a membership becomes current again.
create or replace function public.refresh_affiliate_statuses()
returns integer language plpgsql security definer set search_path = public as $$
declare v_n integer := 0; v_a record; v_state jsonb; v_new text;
begin
  for v_a in select * from public.customer_affiliates where deleted_at is null loop
    v_state := public.customer_affiliate_state(v_a.customer_id);
    v_new := case
      when v_a.manually_suspended then 'suspended_manual'
      when coalesce((v_state->>'eligible')::boolean,false) then 'active'
      else v_state->>'state' end;
    if v_new is distinct from v_a.status then
      update public.customer_affiliates
         set status = v_new,
             membership_expired_at = case when v_new = 'inactive_membership_expired' and v_a.membership_expired_at is null then now() else membership_expired_at end,
             updated_at = now()
       where id = v_a.id;
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end $$;

notify pgrst, 'reload schema';

-- =====================================================================

-- =====================================================================
-- 5. earn_invoice_commission — per-tier affiliate eligibility gating.
--    Preserves all rates (T1 15%/4.5%, T2 5%), allocation and own/third
--    split from 48c. Only change: each tier row is 'earned' when that tier
--    is an eligible affiliate, else 'blocked' + reason. Blocked rows are
--    excluded from payouts automatically (payout sums status='earned').
-- =====================================================================
create or replace function public.earn_invoice_commission(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_tier1 uuid; v_tier2 uuid; v_item record;
  v_ptype text; v_line_after numeric; v_t1_rate numeric; v_t1_amt numeric; v_t2_amt numeric;
  v_paid_date date; v_own_orig numeric; v_third_orig numeric; v_tot_orig numeric; v_portion numeric;
  v_line_disc_sum numeric; v_invoice_level numeric; v_base_total numeric; v_line_net numeric;
  v_sel_own numeric; v_sel_third numeric; v_is_third boolean;
  v_t1_status text; v_t1_block text; v_t2_status text := 'earned'; v_t2_block text;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return; end if;

  select tier1, tier2 into v_tier1, v_tier2 from public.customer_referrers(v_inv.customer_id);
  if v_tier1 is null then return; end if;

  -- Phase 5: resolve each tier's affiliate eligibility INDEPENDENTLY. A tier
  -- that is not an eligible affiliate still gets its commission row, but with
  -- status='blocked' + reason, so it is visible for reports yet never paid and
  -- never released. Tier 1 blocked does not block Tier 2 and vice-versa.
  v_t1_status := case when public.is_eligible_affiliate(v_tier1) then 'earned' else 'blocked' end;
  v_t1_block := case when v_t1_status='blocked' then public.affiliate_block_reason(v_tier1) else null end;
  if v_tier2 is not null then
    v_t2_status := case when public.is_eligible_affiliate(v_tier2) then 'earned' else 'blocked' end;
    v_t2_block := case when v_t2_status='blocked' then public.affiliate_block_reason(v_tier2) else null end;
  end if;

  v_paid_date := coalesce(v_inv.paid_at, now())::date;
  select coalesce(sum(line_discount),0) into v_line_disc_sum from public.invoice_items where invoice_id = p_invoice_id;
  v_invoice_level := coalesce(v_inv.discount_total,0) - v_line_disc_sum;

  -- Allocation base excludes 3rd-party product lines (they are discount-proof).
  select coalesce(sum(ii.line_total - coalesce(ii.line_discount,0)),0) into v_base_total
  from public.invoice_items ii
  left join public.products p on p.id = ii.product_id
  where ii.invoice_id = p_invoice_id
    and not (ii.line_kind = 'product' and p.product_type::text = 'third_party');

  for v_item in
    select ii.id, ii.line_kind, ii.voucher_id, ii.promotion_id, ii.quantity, ii.line_total, ii.line_discount, ii.price_mode,
           coalesce(p.product_type::text, 'own') as ptype
    from public.invoice_items ii
    left join public.products p on p.id = ii.product_id
    where ii.invoice_id = p_invoice_id
  loop
    v_is_third := (v_item.line_kind = 'product' and v_item.ptype = 'third_party');
    v_line_net := v_item.line_total - coalesce(v_item.line_discount,0);
    if v_is_third then
      v_line_after := v_line_net;   -- never reduced by invoice-level discounts
    elsif v_base_total > 0 then
      v_line_after := v_line_net - (v_invoice_level * (v_line_net / v_base_total));
    else
      v_line_after := v_line_net;
    end if;
    if v_line_after < 0 then v_line_after := 0; end if;
    if v_line_after = 0 then continue; end if;

    if v_item.line_kind = 'promotion' then
      select
        coalesce(sum(case when ptype = 'third_party' then 0 else original_value end),0),
        coalesce(sum(case when ptype = 'third_party' then original_value else 0 end),0)
        into v_own_orig, v_third_orig
      from public.promotion_commission_items(v_item.promotion_id, v_inv.store_id, v_item.quantity, v_item.price_mode);

      select
        coalesce(sum(case
          when s.product_id is not null and coalesce(pp.product_type::text,'own') <> 'third_party'
            then (case v_item.price_mode
                    when 'member' then coalesce(spp.member_price, spp.selling_price, 0)
                    when 'non_member' then coalesce(spp.non_member_price, spp.selling_price, 0)
                    else coalesce(spp.selling_price, 0) end) * s.quantity
          when s.voucher_id is not null
            then (case v_item.price_mode
                    when 'member' then coalesce(vsp.member_price, vv.selling_price, 0)
                    when 'non_member' then coalesce(vsp.non_member_price, vv.selling_price, 0)
                    else coalesce(vv.selling_price, 0) end) * s.quantity
          else 0 end),0),
        coalesce(sum(case
          when s.product_id is not null and coalesce(pp.product_type::text,'own') = 'third_party'
            then (case v_item.price_mode
                    when 'member' then coalesce(spp.member_price, spp.selling_price, 0)
                    when 'non_member' then coalesce(spp.non_member_price, spp.selling_price, 0)
                    else coalesce(spp.selling_price, 0) end) * s.quantity
          else 0 end),0)
        into v_sel_own, v_sel_third
      from public.invoice_promotion_selections s
      left join public.products pp on pp.id = s.product_id
      left join public.store_product_prices spp on spp.store_id = v_inv.store_id and spp.product_id = s.product_id
        and spp.is_active = true and spp.deleted_at is null
      left join public.vouchers vv on vv.id = s.voucher_id
      left join public.voucher_store_prices vsp on vsp.store_id = v_inv.store_id and vsp.voucher_id = s.voucher_id
        and vsp.deleted_at is null
      where s.invoice_item_id = v_item.id;

      v_own_orig := v_own_orig + v_sel_own;
      v_third_orig := v_third_orig + v_sel_third;
      v_tot_orig := v_own_orig + v_third_orig;
      if v_tot_orig <= 0 then v_own_orig := 1; v_third_orig := 0; v_tot_orig := 1; end if;

      if v_own_orig > 0 then
        v_portion := round(v_line_after * v_own_orig / v_tot_orig, 2);
        v_t1_amt := round(v_portion * 15 / 100.0, 2);
        if v_t1_amt > 0 then
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', 'own', v_portion, 15, v_t1_amt, v_t1_status::commission_status, v_t1_block, v_paid_date);
          if v_tier2 is not null then
            v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
            if v_t2_amt > 0 then
              insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
              values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', 'own', v_t1_amt, 5.0, v_t2_amt, v_t2_status::commission_status, v_t2_block, v_paid_date);
            end if;
          end if;
        end if;
      end if;

      if v_third_orig > 0 then
        v_portion := round(v_line_after * v_third_orig / v_tot_orig, 2);
        v_t1_amt := round(v_portion * 4.5 / 100.0, 2);
        if v_t1_amt > 0 then
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', 'third_party', v_portion, 4.5, v_t1_amt, v_t1_status::commission_status, v_t1_block, v_paid_date);
          if v_tier2 is not null then
            v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
            if v_t2_amt > 0 then
              insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
              values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', 'third_party', v_t1_amt, 5.0, v_t2_amt, v_t2_status::commission_status, v_t2_block, v_paid_date);
            end if;
          end if;
        end if;
      end if;

    else
      if v_item.line_kind = 'voucher' then v_ptype := 'own'; else v_ptype := v_item.ptype; end if;
      v_t1_rate := case when v_ptype = 'third_party' then 4.5 else 15 end;
      v_t1_amt := round(v_line_after * v_t1_rate / 100.0, 2);
      if v_t1_amt <= 0 then continue; end if;

      insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
      values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', v_ptype, v_line_after, v_t1_rate, v_t1_amt, v_t1_status::commission_status, v_t1_block, v_paid_date);

      if v_tier2 is not null then
        v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
        if v_t2_amt > 0 then
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, block_reason, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', v_ptype, v_t1_amt, 5.0, v_t2_amt, v_t2_status::commission_status, v_t2_block, v_paid_date);
        end if;
      end if;
    end if;
  end loop;

  perform public.write_audit('commissions', p_invoice_id, 'commission_calculated', null,
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'tier1', v_tier1, 'tier2', v_tier2));
end; $$;

notify pgrst, 'reload schema';

-- =====================================================================
-- 6. Affiliate directory view — one row per customer who is either an
--    affiliate OR a referrer OR owns referrals, with all page columns.
-- =====================================================================
create or replace function public.affiliate_directory()
returns table (
  customer_id uuid, full_name text, phone text, member_id text,
  membership_status text, membership_plan text, membership_expiry date,
  affiliate_state text, block_reason text, store_id uuid, store_name text,
  direct_referrals integer, downline integer,
  lifetime_earned numeric, unpaid_payable numeric, blocked_commission numeric,
  last_commission_date date, has_profile boolean, manually_suspended boolean
) language sql stable security definer set search_path = public as $$
  with affs as (
    select distinct c.id as customer_id
    from public.customers c
    where c.deleted_at is null and (
      exists (select 1 from public.customer_affiliates a where a.customer_id = c.id and a.deleted_at is null)
      or exists (select 1 from public.customers r where r.referred_by = c.id)
      or exists (select 1 from public.commissions cm where cm.referrer_customer_id = c.id)
    )
  )
  select
    c.id, c.full_name, c.phone,
    mi.member_id,
    ms->>'status', ms->>'plan_name', (ms->>'expiry_date')::date,
    st->>'state', st->>'block_reason',
    a.store_id, s.name,
    (select count(*)::int from public.customers r where r.referred_by = c.id),
    (select count(*)::int from public.customers r1
      where r1.referred_by = c.id
         or r1.referred_by in (select id from public.customers r2 where r2.referred_by = c.id)),
    coalesce((select sum(commission_amount) from public.commissions cm where cm.referrer_customer_id = c.id and cm.status in ('earned','paid')),0),
    coalesce((select sum(commission_amount) from public.commissions cm where cm.referrer_customer_id = c.id and cm.status = 'earned' and cm.payout_id is null),0),
    coalesce((select sum(commission_amount) from public.commissions cm where cm.referrer_customer_id = c.id and cm.status = 'blocked'),0),
    (select max(invoice_paid_date) from public.commissions cm where cm.referrer_customer_id = c.id),
    a.id is not null, coalesce(a.manually_suspended,false)
  from affs
  join public.customers c on c.id = affs.customer_id
  left join public.customer_affiliates a on a.customer_id = c.id and a.deleted_at is null
  left join public.member_ids mi on mi.customer_id = c.id
  left join public.stores s on s.id = a.store_id
  cross join lateral public.customer_membership_status(c.id) ms
  cross join lateral public.customer_affiliate_state(c.id) st
  order by c.full_name;
$$;

notify pgrst, 'reload schema';
