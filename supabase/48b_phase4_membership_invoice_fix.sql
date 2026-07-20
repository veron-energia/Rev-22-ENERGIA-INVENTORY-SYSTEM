-- =====================================================================
-- ENERGIA — 48b: PHASE 4 CORRECTION & COMPLETION (part 1 of 1 file)
--
-- Migrations 47 and 48 are treated as EXECUTED (you tested Phase 4), so per
-- the migration-history rule this is an additive correction; 47/48 are not
-- renamed or rewritten. NUMBERING CONFLICT RECORDED: the plan reserved 48 for
-- Phase 5 affiliates; 48 was used by Phase 4B payment. Phase 5 will use 49.
--
-- Defects fixed here (from the Phase 4 fix command):
--   A1 renewal storage + overlap (exclusion constraint, not one-live index)
--   A2 renewal Member ID reuse (+ helper column bug: member_id was read from
--      override_reason in invoice_membership_line — fixed)
--   A3 Member ID required before ANY payment (was: full payment only)
--   A4 double-discount (line_total is GROSS; discounts only in discount_total)
--   A5 missing prices BLOCK (was: silently kept stale/member price)
--   A6 eligibility enforced at DB level
--   A7 one membership line per invoice (DB unique index + validation)
--   B  authoritative resolvers for product/voucher/promotion/membership
--   C  permanent line snapshots (mode, source, ids, member/non-member, store)
--   E  reprice covers vouchers+promotions; review_required payment flow
--   F  override supports voucher/promotion; blocked after any payment
--   G  pay_invoice exact ordering
--   H  reservation release wiring + permission checks
--   I  calendar-month expiry warnings (not months×30)
--
-- Additive + idempotent. Run AFTER 48. Enum values from 47 already committed.
-- =====================================================================

set check_function_bodies = off;

-- =====================================================================
-- A1. Overlap-safe renewal storage
-- =====================================================================
create extension if not exists btree_gist;

drop index if exists uq_cmemb_one_live;

-- Real periods (dated, not cancelled, not deleted) must never overlap for a
-- customer. Allows current + future renewal side by side; blocks overlap.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'excl_cmemb_no_overlap') then
    alter table public.customer_memberships
      add constraint excl_cmemb_no_overlap
      exclude using gist (
        customer_id with =,
        daterange(start_date, expiry_date, '[]') with &&
      ) where (deleted_at is null and status <> 'cancelled'
               and start_date is not null and expiry_date is not null);
  end if;
end $$;

-- A2/H. Reservation hygiene: one active reservation per customer and per invoice.
create unique index if not exists uq_midres_customer on public.member_id_reservations(customer_id);
create unique index if not exists uq_midres_invoice on public.member_id_reservations(invoice_id)
  where invoice_id is not null;

-- A7. One membership line per invoice — database-enforced.
create unique index if not exists uq_invoice_one_membership
  on public.invoice_items(invoice_id) where (line_kind = 'membership');

-- =====================================================================
-- C. Permanent snapshot columns
-- =====================================================================
alter table public.invoice_items add column if not exists price_source_id uuid;
alter table public.invoice_items add column if not exists store_id_snapshot uuid;
alter table public.invoice_items add column if not exists member_price_snapshot numeric(12,2);
alter table public.invoice_items add column if not exists non_member_price_snapshot numeric(12,2);
alter table public.invoice_items add column if not exists plan_name_snapshot text;
alter table public.invoice_items add column if not exists plan_months_snapshot integer;
alter table public.invoice_items add column if not exists member_id_snapshot text;

-- =====================================================================
-- I + A1. Membership detection: current must COVER today; future renewals
-- are reported separately, never selected as current. Calendar-month warnings.
-- =====================================================================
create or replace function public.customer_membership_status(p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_m public.customer_memberships%rowtype; v_f public.customer_memberships%rowtype;
  v_plan public.membership_plans%rowtype;
  v_w1 integer; v_w2 integer; v_days_left integer; v_warn text := null; v_today date := public.sg_today();
begin
  select coalesce(membership_warn_months_1,3), coalesce(membership_warn_months_2,1)
    into v_w1, v_w2 from public.app_settings where id;

  -- CURRENT: dated, covering today, effectively live.
  select * into v_m from public.customer_memberships
   where customer_id = p_customer_id and deleted_at is null
     and status in ('active','expiring_soon')
     and start_date is not null and expiry_date is not null
     and start_date <= v_today and expiry_date >= v_today
   order by expiry_date desc limit 1;

  -- FUTURE renewal (starts after today), reported but never "current".
  select * into v_f from public.customer_memberships
   where customer_id = p_customer_id and deleted_at is null
     and status in ('active','expiring_soon')
     and start_date is not null and start_date > v_today
   order by start_date asc limit 1;

  if v_m.id is null then
    return jsonb_build_object('is_member', false, 'status', 'none',
      'has_future_renewal', v_f.id is not null,
      'future_start', v_f.start_date, 'future_expiry', v_f.expiry_date);
  end if;

  select * into v_plan from public.membership_plans where id = v_m.plan_id;
  v_days_left := v_m.expiry_date - v_today;

  -- TRUE calendar months, not months*30: warn when today has entered the
  -- window [expiry - N months, expiry].
  if v_today > v_m.expiry_date then v_warn := 'expired';
  elsif v_today >= (v_m.expiry_date - (v_w2 || ' months')::interval)::date then v_warn := 'one_month';
  elsif v_today >= (v_m.expiry_date - (v_w1 || ' months')::interval)::date then v_warn := 'three_month';
  end if;

  return jsonb_build_object(
    'is_member', true,
    'membership_id', v_m.id, 'membership_no', v_m.membership_no,
    'member_id', v_m.member_id, 'plan_id', v_m.plan_id, 'plan_name', v_plan.name,
    'store_id', v_m.store_id, 'start_date', v_m.start_date, 'expiry_date', v_m.expiry_date,
    'days_left', v_days_left,
    'status', case when v_warn in ('one_month','three_month') then 'expiring_soon' else 'active' end,
    'raw_status', v_m.status, 'warning', v_warn, 'is_complimentary', v_m.is_complimentary,
    'has_future_renewal', v_f.id is not null,
    'future_start', v_f.start_date, 'future_expiry', v_f.expiry_date);
end $$;

create or replace function public.set_membership_warn_thresholds(p_months_1 integer, p_months_2 integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit thresholds'; end if;
  if coalesce(p_months_2,0) <= 0 or coalesce(p_months_1,0) <= p_months_2 then
    raise exception 'Thresholds must satisfy: first > second > 0'; end if;
  update public.app_settings set membership_warn_months_1 = p_months_1, membership_warn_months_2 = p_months_2 where id;
  perform public.write_audit_ex('app_settings', null, 'membership_thresholds_set',
    null, jsonb_build_object('months_1', p_months_1, 'months_2', p_months_2), 'membership', null, null);
end $$;

-- =====================================================================
-- B. Authoritative price resolvers (strict; legacy fields not used)
-- =====================================================================
create or replace function public.product_price_for(
  p_store_id uuid, p_product_id uuid, p_is_member boolean
) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_spp public.store_product_prices%rowtype; v_price numeric; v_mode text; v_eligible boolean;
begin
  select * into v_spp from public.store_product_prices
   where store_id = p_store_id and product_id = p_product_id
     and is_active = true and deleted_at is null;
  if not found then return jsonb_build_object('found', false); end if;

  v_mode := case when p_is_member then 'member' else 'non_member' end;
  v_price := case when p_is_member then v_spp.member_price else v_spp.non_member_price end;
  v_eligible := case coalesce(v_spp.eligibility,'both')
    when 'both' then true when 'member_only' then p_is_member
    when 'non_member_only' then not p_is_member else false end;

  return jsonb_build_object('found', true, 'source_id', v_spp.id, 'store_id', p_store_id,
    'eligibility', coalesce(v_spp.eligibility,'both'), 'price_mode', v_mode, 'price', v_price,
    'member_price', v_spp.member_price, 'non_member_price', v_spp.non_member_price,
    'eligible', v_eligible, 'has_price', v_price is not null);
end $$;

create or replace function public.voucher_price_for(
  p_store_id uuid, p_voucher_id uuid, p_is_member boolean
) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_r public.voucher_store_prices%rowtype; v_price numeric; v_mode text;
begin
  select * into v_r from public.voucher_store_prices
   where store_id = p_store_id and voucher_id = p_voucher_id and deleted_at is null;
  if not found or not v_r.available_at_store then
    return jsonb_build_object('found', found, 'available', false); end if;
  v_mode := case when p_is_member then 'member' else 'non_member' end;
  v_price := case when p_is_member then v_r.member_price else v_r.non_member_price end;
  return jsonb_build_object('found', true, 'available', true, 'source_id', v_r.id, 'store_id', p_store_id,
    'price_mode', v_mode, 'price', v_price,
    'member_price', v_r.member_price, 'non_member_price', v_r.non_member_price,
    'eligible', true, 'has_price', v_price is not null);
end $$;

create or replace function public.promotion_price_for(
  p_store_id uuid, p_promotion_id uuid, p_is_member boolean
) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_r public.promotion_store_prices%rowtype; v_price numeric; v_mode text;
begin
  select * into v_r from public.promotion_store_prices
   where store_id = p_store_id and promotion_id = p_promotion_id and deleted_at is null;
  if not found or not v_r.available_at_store then
    return jsonb_build_object('found', found, 'available', false); end if;
  v_mode := case when p_is_member then 'member' else 'non_member' end;
  v_price := case when p_is_member then v_r.member_price else v_r.non_member_price end;
  return jsonb_build_object('found', true, 'available', true, 'source_id', v_r.id, 'store_id', p_store_id,
    'price_mode', v_mode, 'price', v_price,
    'member_price', v_r.member_price, 'non_member_price', v_r.non_member_price,
    'eligible', true, 'has_price', v_price is not null);
end $$;

create or replace function public.membership_price_for(p_store_id uuid, p_plan_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_p public.membership_plans%rowtype; v_r public.membership_plan_store_prices%rowtype;
begin
  select * into v_p from public.membership_plans where id = p_plan_id and deleted_at is null;
  if not found then return jsonb_build_object('found', false); end if;
  select * into v_r from public.membership_plan_store_prices
   where plan_id = p_plan_id and store_id = p_store_id and deleted_at is null;
  return jsonb_build_object('found', true,
    'plan_name', v_p.name, 'duration_months', v_p.duration_months,
    'is_active', v_p.is_active, 'is_system', v_p.is_system, 'is_complimentary', v_p.is_complimentary,
    'store_price_found', v_r.id is not null,
    'available', coalesce(v_r.available_at_store, false) and coalesce(v_r.is_active, false),
    'source_id', v_r.id, 'store_id', p_store_id, 'fee', v_r.membership_fee);
end $$;

-- Mode-aware promotion top-up (strict). The 3-arg legacy version is kept
-- untouched for exchange/history functions that predate member pricing.
create or replace function public.promotion_selections_topup(
  p_promotion_id uuid, p_store_id uuid, p_selections jsonb, p_is_member boolean
) returns numeric language plpgsql stable security definer set search_path = public as $$
declare
  v_grp record; v_sel jsonb; v_opt jsonb; v_baseline numeric; v_price numeric;
  v_topup numeric := 0; v_qty integer; v_pj jsonb;
begin
  for v_grp in select * from public.promotion_choice_groups
    where promotion_id = p_promotion_id and item_kind = 'product'
  loop
    -- Baseline = cheapest option at this store IN THE APPLICABLE MODE.
    select min(case when p_is_member then spp.member_price else spp.non_member_price end)
      into v_baseline
    from public.promotion_choice_options o
    join public.store_product_prices spp
      on spp.product_id = o.product_id and spp.store_id = p_store_id
     and spp.is_active = true and spp.deleted_at is null
    where o.group_id = v_grp.id and o.product_id is not null;
    if v_baseline is null then continue; end if;

    for v_sel in select * from jsonb_array_elements(coalesce(p_selections,'[]'::jsonb))
    loop
      if (v_sel->>'group_id')::uuid <> v_grp.id then continue; end if;
      for v_opt in select * from jsonb_array_elements(coalesce(v_sel->'options','[]'::jsonb))
      loop
        v_qty := coalesce((v_opt->>'quantity')::integer, 0);
        if v_qty <= 0 or (v_opt->>'product_id') is null then continue; end if;
        v_pj := public.product_price_for(p_store_id, (v_opt->>'product_id')::uuid, p_is_member);
        if not coalesce((v_pj->>'has_price')::boolean,false) then
          raise exception 'Product "%" is missing its % price at this store (needed for the bundle top-up)',
            (select name from public.products where id = (v_opt->>'product_id')::uuid),
            case when p_is_member then 'Member' else 'Non-Member' end;
        end if;
        v_price := (v_pj->>'price')::numeric;
        if v_price > v_baseline then v_topup := v_topup + (v_price - v_baseline) * v_qty; end if;
      end loop;
    end loop;
  end loop;
  return round(v_topup, 2);
end $$;

-- A2 fix: correct column mapping (member_id no longer read from override_reason).
-- The return row gains plan_months vs migration 48, and Postgres cannot
-- CREATE OR REPLACE across a return-type change — drop the old one first.
drop function if exists public.invoice_membership_line(uuid);
create function public.invoice_membership_line(p_invoice_id uuid)
returns table (item_id uuid, plan_id uuid, member_id text, unit_price numeric, plan_months integer)
language sql stable security definer set search_path = public as $$
  select ii.id, ii.membership_plan_id, ii.member_id_snapshot, ii.unit_price, ii.plan_months_snapshot
  from public.invoice_items ii
  where ii.invoice_id = p_invoice_id and ii.line_kind = 'membership'
  limit 1
$$;

-- =====================================================================
-- E + A4 + A5 + A6. Repricing: all applicable kinds, GROSS line_total,
-- strict prices, eligibility enforced. Returns the list of changed lines.
-- =====================================================================
-- Return type changes from void (migration 48) to jsonb (the list of changed
-- lines, needed for the payment review flow) — drop the old version first.
drop function if exists public.reprice_invoice_lines(uuid, boolean);
create function public.reprice_invoice_lines(p_invoice_id uuid, p_is_member boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_li record; v_pj jsonb; v_new numeric;
  v_changes jsonb := '[]'::jsonb; v_subtotal numeric; v_mode text;
  v_old_line_disc numeric; v_new_line_disc numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  v_mode := case when p_is_member then 'member' else 'non_member' end;
  select coalesce(sum(coalesce(line_discount,0)),0) into v_old_line_disc
    from public.invoice_items where invoice_id = p_invoice_id;

  for v_li in
    select ii.*, p.name as pname, pr.name as prname, vo.name as voname
      from public.invoice_items ii
      left join public.products p on p.id = ii.product_id
      left join public.promotions pr on pr.id = ii.promotion_id
      left join public.vouchers vo on vo.id = ii.voucher_id
     where ii.invoice_id = p_invoice_id
       and ii.line_kind in ('product','voucher','promotion')
       and coalesce(ii.price_overridden,false) = false
  loop
    if v_li.line_kind = 'product' then
      v_pj := public.product_price_for(v_inv.store_id, v_li.product_id, p_is_member);
      if not coalesce((v_pj->>'found')::boolean,false) then
        raise exception 'Product "%" has no price row at this store', v_li.pname; end if;
      -- A6: eligibility for non-overridden lines.
      if not coalesce((v_pj->>'eligible')::boolean,false) then
        raise exception 'Product "%" is % — not sellable to this customer without a manual override',
          v_li.pname, replace(v_pj->>'eligibility','_',' ');
      end if;
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Product "%" is missing its % price at this store', v_li.pname,
          case when p_is_member then 'Member' else 'Non-Member' end;
      end if;
      v_new := (v_pj->>'price')::numeric;

    elsif v_li.line_kind = 'voucher' then
      v_pj := public.voucher_price_for(v_inv.store_id, v_li.voucher_id, p_is_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Voucher "%" is missing its % price at this store', v_li.voname,
          case when p_is_member then 'Member' else 'Non-Member' end;
      end if;
      v_new := (v_pj->>'price')::numeric;

    else -- promotion
      v_pj := public.promotion_price_for(v_inv.store_id, v_li.promotion_id, p_is_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Promotion "%" is missing its % price at this store', v_li.prname,
          case when p_is_member then 'Member' else 'Non-Member' end;
      end if;
      v_new := (v_pj->>'price')::numeric;
    end if;

    if v_new is distinct from v_li.unit_price or v_li.price_mode is distinct from v_mode then
      v_changes := v_changes || jsonb_build_object(
        'item_id', v_li.id, 'kind', v_li.line_kind,
        'name', coalesce(v_li.pname, v_li.prname, v_li.voname),
        'old_price', v_li.unit_price, 'new_price', v_new);

      -- A4: line_total is GROSS. Promotions keep their top-up added on.
      update public.invoice_items
         set unit_price = v_new,
             line_total = (v_new * quantity) + coalesce(topup_amount, 0),
             line_discount = case
               when line_voucher_id is not null
                 then public.voucher_discount_amount(line_voucher_id, v_new * quantity)
               else line_discount end,
             price_mode = v_mode, price_source = line_kind::text,
             price_source_id = (v_pj->>'source_id')::uuid,
             store_id_snapshot = v_inv.store_id,
             member_price_snapshot = (v_pj->>'member_price')::numeric,
             non_member_price_snapshot = (v_pj->>'non_member_price')::numeric,
             original_price = coalesce(original_price, v_li.unit_price)
       where id = v_li.id;
    end if;
  end loop;

  -- Rebuild invoice money from lines. subtotal = GROSS sum of line_totals
  -- (which include promotion top-ups). discount_total is then rebuilt
  -- deterministically from its parts (manual + line vouchers + whole-invoice
  -- voucher) so every discount is counted exactly once — A4.
  select coalesce(sum(line_total),0) into v_subtotal
    from public.invoice_items where invoice_id = p_invoice_id;

  select coalesce(sum(coalesce(line_discount,0)),0) into v_new_line_disc
    from public.invoice_items where invoice_id = p_invoice_id;

  update public.invoices set subtotal = v_subtotal where id = p_invoice_id;
  if v_inv.manual_discount is not null then
    -- Full deterministic rebuild (manual + line + whole voucher, once each).
    perform public.refresh_invoice_discount_total(p_invoice_id);
  else
    -- Pre-fix invoice whose manual component can't be reconstructed:
    -- keep its structure and apply only the precise line-discount delta.
    update public.invoices
       set discount_total = greatest(0, coalesce(discount_total,0) + (v_new_line_disc - v_old_line_disc))
     where id = p_invoice_id;
  end if;
  update public.invoices i
     set total_amount = greatest(0, i.subtotal - coalesce(i.discount_total,0))
   where i.id = p_invoice_id;

  -- A partially paid invoice must never drop below what was already paid.
  if exists (select 1 from public.invoices
              where id = p_invoice_id and total_amount + 0.001 < paid_amount) then
    raise exception 'Repricing would reduce the total below the amount already paid';
  end if;

  return v_changes;
end $$;

-- Deterministic discount refresh: discount_total = manual + line vouchers +
-- whole-invoice voucher, each computed once from current line amounts.
alter table public.invoices add column if not exists manual_discount numeric(12,2);
-- Backfill only where it is EXACT: without a whole-invoice voucher,
-- manual = discount_total - line discounts. With one, the split can't be
-- reconstructed; those keep manual_discount NULL and reprice applies the
-- line-discount delta instead (see reprice_invoice_lines).
update public.invoices i
   set manual_discount = greatest(0, coalesce(i.discount_total,0)
        - coalesce((select sum(coalesce(ii.line_discount,0))
                      from public.invoice_items ii where ii.invoice_id = i.id),0))
 where i.manual_discount is null
   and i.discount_voucher_id is null
   and i.status in ('unpaid','partially_paid');

create or replace function public.refresh_invoice_discount_total(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_i public.invoices%rowtype; v_line numeric; v_third numeric; v_whole numeric := 0; v_base numeric;
begin
  select * into v_i from public.invoices where id = p_invoice_id;
  if v_i.status not in ('unpaid','partially_paid') then return; end if;  -- never touch paid history

  select coalesce(sum(coalesce(line_discount,0)),0) into v_line
    from public.invoice_items where invoice_id = p_invoice_id;
  select coalesce(sum(ii.line_total),0) into v_third
    from public.invoice_items ii join public.products p on p.id = ii.product_id
   where ii.invoice_id = p_invoice_id and p.product_type = 'third_party';

  if v_i.discount_voucher_id is not null then
    v_base := greatest(0, (v_i.subtotal - v_third) - coalesce(v_i.manual_discount,0) - v_line);
    v_whole := coalesce(public.voucher_discount_amount(v_i.discount_voucher_id, v_base),0);
  end if;

  update public.invoices
     set discount_total = least(greatest(0, coalesce(manual_discount,0) + v_line + v_whole),
                                greatest(0, subtotal - v_third))
   where id = p_invoice_id;
end $$;

-- =====================================================================
-- D. create_invoice — extended, all existing behaviour preserved.
-- New item kinds/fields: {kind:'membership', plan_id, member_id?} and on
-- product/voucher/promotion items optional {price_mode_override, override_reason}.
-- =====================================================================
create or replace function public.create_invoice(
  p_store_id uuid, p_customer_id uuid, p_affiliate_id uuid,
  p_items jsonb, p_discount_total numeric default 0, p_notes text default null,
  p_discount_voucher_id uuid default null, p_service_staff jsonb default '[]'::jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_item jsonb; v_kind text; v_product_id uuid; v_voucher_id uuid; v_promo_id uuid;
  v_qty integer; v_price numeric; v_subtotal numeric := 0; v_line_total numeric;
  v_invoice_id uuid; v_invoice_no text; v_manual numeric := coalesce(p_discount_total,0);
  v_has_promo boolean := false; v_promo public.promotions%rowtype;
  v_line_voucher uuid; v_line_disc numeric; v_line_disc_sum numeric := 0;
  v_lv public.vouchers%rowtype; v_discount numeric;
  v_grp record; v_sel jsonb; v_opt jsonb; v_provided integer; v_required integer;
  v_item_id uuid; v_sel_group uuid; v_ok boolean; v_topup numeric;
  v_ptype text; v_third_sum numeric := 0; v_discountable numeric; v_wbase numeric;
  v_ss jsonb; v_ss_id uuid; v_ss_role user_role;
  -- membership / mode additions
  v_ms jsonb; v_is_member boolean; v_membership_count integer := 0;
  v_plan_id uuid; v_mp jsonb; v_member_id text; v_owned_id text; v_is_renewal boolean := false;
  v_mode_ovr text; v_ovr_reason text; v_pj jsonb; v_use_member boolean; v_mode text;
begin
  if public.current_user_role() is null then raise exception 'No profile for current user'; end if;
  if not public.user_has_store_access(p_store_id) then raise exception 'You do not have access to this store'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'At least one item is required'; end if;
  if p_customer_id is null then raise exception 'A customer is required'; end if;

  -- Membership context: current (covers today) + whether this invoice sells one.
  v_ms := public.customer_membership_status(p_customer_id);
  select count(*) into v_membership_count
    from jsonb_array_elements(p_items) x where coalesce(x->>'kind','product') = 'membership';
  if v_membership_count > 1 then raise exception 'Only one membership line is allowed per invoice'; end if;
  v_is_member := coalesce((v_ms->>'is_member')::boolean, false) or v_membership_count = 1;

  if v_membership_count = 1 then
    if coalesce((v_ms->>'has_future_renewal')::boolean, false) then
      raise exception 'This customer already has a scheduled renewal'; end if;
    v_is_renewal := coalesce((v_ms->>'is_member')::boolean, false);
    select member_id into v_owned_id from public.member_ids where customer_id = p_customer_id;
  end if;

  -- PASS 1: validate + price (mode-aware, strict) + accumulate.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantity must be greater than zero'; end if;
    v_mode_ovr := nullif(v_item->>'price_mode_override','');
    v_ovr_reason := nullif(trim(coalesce(v_item->>'override_reason','')),'');
    if v_mode_ovr is not null and v_mode_ovr not in ('member','non_member') then
      raise exception 'Invalid price mode override'; end if;
    if v_mode_ovr is not null and v_ovr_reason is null then
      raise exception 'An override reason is required when overriding a line price mode'; end if;
    v_use_member := coalesce(v_mode_ovr = 'member', v_is_member);

    if v_kind = 'membership' then
      if v_qty <> 1 then raise exception 'A membership line must have quantity 1'; end if;
      if v_mode_ovr is not null then raise exception 'Member/Non-Member override does not apply to a membership line'; end if;
      v_plan_id := (v_item->>'plan_id')::uuid;
      v_mp := public.membership_price_for(p_store_id, v_plan_id);
      if not coalesce((v_mp->>'found')::boolean,false) then raise exception 'Membership plan not found'; end if;
      if coalesce((v_mp->>'is_system')::boolean,false) or coalesce((v_mp->>'is_complimentary')::boolean,false) then
        raise exception 'Plan "%" is protected and cannot be sold', v_mp->>'plan_name'; end if;
      if not coalesce((v_mp->>'is_active')::boolean,false) then
        raise exception 'Plan "%" is not active', v_mp->>'plan_name'; end if;
      if not coalesce((v_mp->>'available')::boolean,false) or (v_mp->>'fee') is null then
        raise exception 'Plan "%" has no active price at this store', v_mp->>'plan_name'; end if;

      v_member_id := nullif(trim(coalesce(v_item->>'member_id','')),'');
      if v_is_renewal then
        -- Renewal reuses the customer's permanent Member ID automatically.
        if v_member_id is not null and v_owned_id is not null and v_member_id <> v_owned_id then
          raise exception 'Renewal must keep the existing Member ID (%)', v_owned_id; end if;
      elsif v_member_id is not null then
        if not public.member_id_available(v_member_id, p_customer_id) then
          raise exception 'Member ID % is already taken', v_member_id; end if;
      end if;
      v_subtotal := v_subtotal + (v_mp->>'fee')::numeric;

    elsif v_kind = 'promotion' then
      v_has_promo := true;
      v_promo_id := (v_item->>'promotion_id')::uuid;
      select * into v_promo from public.promotions where id = v_promo_id and deleted_at is null;
      if not found then raise exception 'Promotion not found'; end if;
      if not v_promo.is_active then raise exception 'Promotion "%" is not active', v_promo.name; end if;
      if v_promo.start_date is not null and now()::date < v_promo.start_date then raise exception 'Promotion "%" has not started yet', v_promo.name; end if;
      if v_promo.end_date is not null and now()::date > v_promo.end_date then raise exception 'Promotion "%" has ended', v_promo.name; end if;
      -- Members-only rule (override or same-invoice membership lifts it).
      if not v_is_member and v_mode_ovr is null then
        raise exception 'Promotions are for members only. Add a membership to this invoice or apply a manual override.'; end if;

      for v_grp in select * from public.promotion_choice_groups where promotion_id = v_promo_id
      loop
        v_required := v_grp.choose_qty * v_qty;
        v_provided := 0;
        for v_sel in select * from jsonb_array_elements(coalesce(v_item->'selections','[]'::jsonb))
        loop
          if (v_sel->>'group_id')::uuid = v_grp.id then
            for v_opt in select * from jsonb_array_elements(coalesce(v_sel->'options','[]'::jsonb))
            loop
              if coalesce((v_opt->>'quantity')::integer,0) <= 0 then continue; end if;
              if v_grp.item_kind = 'voucher' then
                select exists (
                  select 1 from public.promotion_choice_options o
                  where o.group_id = v_grp.id
                    and (v_opt->>'voucher_id') is not null and o.voucher_id = (v_opt->>'voucher_id')::uuid
                ) into v_ok;
                if not v_ok then raise exception 'A selected voucher does not belong to choice group "%"', v_grp.label; end if;
              else
                if (v_opt->>'product_id') is null then raise exception 'Choice group "%" expects product selections', v_grp.label; end if;
                select exists (
                  select 1 from public.store_product_prices
                  where store_id = p_store_id and product_id = (v_opt->>'product_id')::uuid
                    and is_active = true and deleted_at is null
                ) into v_ok;
                if not v_ok then
                  raise exception 'Product "%" has no price at this store, so it cannot be chosen in "%"',
                    (select name from public.products where id = (v_opt->>'product_id')::uuid), v_grp.label;
                end if;
              end if;
              v_provided := v_provided + (v_opt->>'quantity')::integer;
            end loop;
          end if;
        end loop;
        if v_provided <> v_required then
          raise exception 'Choice group "%" requires % selection(s), got %', v_grp.label, v_required, v_provided;
        end if;
      end loop;

      v_pj := public.promotion_price_for(p_store_id, v_promo_id, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Promotion "%" is missing its % price at this store', v_promo.name,
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_topup := public.promotion_selections_topup(v_promo_id, p_store_id, v_item->'selections', v_use_member);
      v_subtotal := v_subtotal + ((v_pj->>'price')::numeric * v_qty) + v_topup;

    elsif v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      perform 1 from public.vouchers where id = v_voucher_id and is_active = true and deleted_at is null;
      if not found then raise exception 'Voucher not found or inactive'; end if;
      v_pj := public.voucher_price_for(p_store_id, v_voucher_id, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Voucher "%" is missing its % price at this store',
          (select name from public.vouchers where id = v_voucher_id),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_subtotal := v_subtotal + ((v_pj->>'price')::numeric * v_qty);

    else
      v_product_id := (v_item->>'product_id')::uuid;
      select p.product_type::text into v_ptype from public.products p where p.id = v_product_id;
      v_pj := public.product_price_for(p_store_id, v_product_id, v_use_member);
      if not coalesce((v_pj->>'found')::boolean,false) then
        raise exception 'No price set for "%" in this store',
          (select name from public.products where id = v_product_id); end if;
      if v_mode_ovr is null and not coalesce((v_pj->>'eligible')::boolean,false) then
        raise exception 'Product "%" is % — not sellable to this customer without a manual override',
          (select name from public.products where id = v_product_id),
          replace(v_pj->>'eligibility','_',' '); end if;
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Product "%" is missing its % price at this store',
          (select name from public.products where id = v_product_id),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_price := (v_pj->>'price')::numeric;
      v_line_total := v_price * v_qty;
      v_subtotal := v_subtotal + v_line_total;
      if v_ptype = 'third_party' then v_third_sum := v_third_sum + v_line_total; end if;

      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      if v_line_voucher is not null then
        if v_ptype = 'third_party' then
          raise exception 'Discounts cannot be applied to third-party products ("%")',
            (select name from public.products where id = v_product_id);
        end if;
        select * into v_lv from public.vouchers where id = v_line_voucher and deleted_at is null;
        if not found then raise exception 'Line voucher not found'; end if;
        if v_lv.voucher_kind = 'normal' then raise exception 'Voucher "%" is not a discount voucher', v_lv.name; end if;
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
        v_line_disc_sum := v_line_disc_sum + v_line_disc;
      end if;
    end if;
  end loop;

  if p_discount_voucher_id is not null and v_has_promo then
    raise exception 'A whole-invoice discount voucher cannot be used when the invoice contains a promotion/bundle. Use per-product vouchers instead.';
  end if;

  v_discountable := v_subtotal - v_third_sum;
  v_discount := v_manual + v_line_disc_sum;
  if p_discount_voucher_id is not null then
    v_wbase := v_discountable - v_manual - v_line_disc_sum;
    if v_wbase < 0 then v_wbase := 0; end if;
    v_discount := v_discount + public.voucher_discount_amount(p_discount_voucher_id, v_wbase);
  end if;
  if v_discount > v_discountable then v_discount := v_discountable; end if;

  v_invoice_no := public.next_invoice_no();
  insert into public.invoices
    (invoice_no, store_id, customer_id, affiliate_id, created_by, status,
     subtotal, discount_total, manual_discount, total_amount, paid_amount, notes, discount_voucher_id)
  values (v_invoice_no, p_store_id, p_customer_id, p_affiliate_id, auth.uid(), 'unpaid',
          v_subtotal, v_discount, v_manual, v_subtotal - v_discount, 0, p_notes, p_discount_voucher_id)
  returning id into v_invoice_id;

  for v_ss in select * from jsonb_array_elements(coalesce(p_service_staff, '[]'::jsonb))
  loop
    v_ss_id := (v_ss#>>'{}')::uuid;
    if v_ss_id is null then continue; end if;
    select role into v_ss_role from public.profiles where id = v_ss_id and is_active = true and deleted_at is null;
    if v_ss_role is null then raise exception 'A selected service staff was not found or is inactive'; end if;
    if v_ss_role not in ('owner','manager','staff') then
      raise exception 'Service staff must be Owner, Manager, or Staff (got %)', v_ss_role;
    end if;
    insert into public.invoice_service_staff (invoice_id, staff_id)
    values (v_invoice_id, v_ss_id) on conflict (invoice_id, staff_id) do nothing;
  end loop;

  -- PASS 2: insert lines with permanent snapshots.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    v_mode_ovr := nullif(v_item->>'price_mode_override','');
    v_ovr_reason := nullif(trim(coalesce(v_item->>'override_reason','')),'');
    v_use_member := coalesce(v_mode_ovr = 'member', v_is_member);
    v_mode := case when v_use_member then 'member' else 'non_member' end;

    if v_kind = 'membership' then
      v_plan_id := (v_item->>'plan_id')::uuid;
      v_mp := public.membership_price_for(p_store_id, v_plan_id);
      v_member_id := case when v_is_renewal then v_owned_id
                          else nullif(trim(coalesce(v_item->>'member_id','')),'') end;
      insert into public.invoice_items
        (invoice_id, line_kind, product_id, quantity, unit_price, line_total,
         membership_plan_id, price_source, price_source_id, store_id_snapshot,
         plan_name_snapshot, plan_months_snapshot, member_id_snapshot, original_price)
      values (v_invoice_id, 'membership', null, 1, (v_mp->>'fee')::numeric, (v_mp->>'fee')::numeric,
              v_plan_id, 'membership', (v_mp->>'source_id')::uuid, p_store_id,
              v_mp->>'plan_name', (v_mp->>'duration_months')::integer, v_member_id, (v_mp->>'fee')::numeric);
      -- Reserve a NEW member's ID now the invoice exists; renewals reuse theirs.
      if not v_is_renewal and v_member_id is not null then
        perform public.reserve_member_id(v_member_id, p_customer_id, v_invoice_id);
      end if;

    elsif v_kind = 'promotion' then
      v_promo_id := (v_item->>'promotion_id')::uuid;
      v_pj := public.promotion_price_for(p_store_id, v_promo_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_topup := public.promotion_selections_topup(v_promo_id, p_store_id, v_item->'selections', v_use_member);
      insert into public.invoice_items
        (invoice_id, line_kind, promotion_id, product_id, quantity, unit_price, line_total, topup_amount,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         price_overridden, override_reason, override_by, override_at)
      values (v_invoice_id, 'promotion', v_promo_id, null, v_qty, v_price, (v_price * v_qty) + v_topup, v_topup,
              v_mode, case when v_mode_ovr is null then 'promotion' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, p_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end)
      returning id into v_item_id;

      for v_sel in select * from jsonb_array_elements(coalesce(v_item->'selections','[]'::jsonb))
      loop
        v_sel_group := (v_sel->>'group_id')::uuid;
        for v_opt in select * from jsonb_array_elements(coalesce(v_sel->'options','[]'::jsonb))
        loop
          if coalesce((v_opt->>'quantity')::integer,0) <= 0 then continue; end if;
          insert into public.invoice_promotion_selections (invoice_item_id, group_id, product_id, voucher_id, quantity)
          values (v_item_id, v_sel_group,
                  nullif(v_opt->>'product_id','')::uuid, nullif(v_opt->>'voucher_id','')::uuid,
                  (v_opt->>'quantity')::integer);
        end loop;
      end loop;

    elsif v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      v_pj := public.voucher_price_for(p_store_id, v_voucher_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      insert into public.invoice_items
        (invoice_id, line_kind, voucher_id, product_id, quantity, unit_price, line_total,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         price_overridden, override_reason, override_by, override_at)
      values (v_invoice_id, 'voucher', v_voucher_id, null, v_qty, v_price, v_price * v_qty,
              v_mode, case when v_mode_ovr is null then 'voucher' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, p_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end);
    else
      v_product_id := (v_item->>'product_id')::uuid;
      v_pj := public.product_price_for(p_store_id, v_product_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_line_total := v_price * v_qty;
      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      v_line_disc := 0;
      if v_line_voucher is not null then
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
      end if;
      insert into public.invoice_items
        (invoice_id, line_kind, product_id, quantity, unit_price, line_total, line_voucher_id, line_discount,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         price_overridden, override_reason, override_by, override_at)
      values (v_invoice_id, 'product', v_product_id, v_qty, v_price, v_line_total, v_line_voucher, v_line_disc,
              v_mode, case when v_mode_ovr is null then 'product' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, p_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end);
    end if;
  end loop;

  perform public.write_audit('invoices', v_invoice_id, 'invoice_created', null,
    jsonb_build_object('invoice_no', v_invoice_no, 'total', v_subtotal - v_discount,
                       'has_promotion', v_has_promo, 'third_party_total', v_third_sum,
                       'is_member_pricing', v_is_member, 'has_membership_line', v_membership_count = 1,
                       'is_renewal', v_is_renewal));
  return v_invoice_id;
end; $$;

-- =====================================================================
-- F. Line override — product/voucher/promotion; never membership;
-- blocked once ANY payment exists.
-- =====================================================================
create or replace function public.override_invoice_line_price(
  p_item_id uuid, p_mode text, p_reason text
) returns void language plpgsql security definer set search_path = public as $$
declare v_li public.invoice_items%rowtype; v_inv public.invoices%rowtype; v_pj jsonb;
        v_new numeric; v_role user_role; v_member boolean;
begin
  v_role := public.current_user_role();
  if v_role is null or v_role = 'inventory_manager' then raise exception 'Not permitted'; end if;
  if p_mode not in ('member','non_member') then raise exception 'Invalid price mode'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'An override reason is required'; end if;

  select * into v_li from public.invoice_items where id = p_item_id;
  if not found then raise exception 'Line not found'; end if;
  if v_li.line_kind = 'membership' then
    raise exception 'Member/Non-Member override does not apply to a membership line'; end if;
  if v_li.line_kind not in ('product','voucher','promotion') then
    raise exception 'This line kind cannot be overridden'; end if;
  select * into v_inv from public.invoices where id = v_li.invoice_id;
  if v_inv.status in ('paid','cancelled','refunded') or v_inv.locked_at is not null then
    raise exception 'Invoice is locked'; end if;
  if coalesce(v_inv.paid_amount,0) > 0 then
    raise exception 'Lines cannot be changed after a payment has been recorded'; end if;
  if not (public.is_manager_or_above() or public.user_has_store_access(v_inv.store_id)) then
    raise exception 'No access to this invoice''s store'; end if;

  v_member := (p_mode = 'member');
  if v_li.line_kind = 'product' then
    v_pj := public.product_price_for(v_inv.store_id, v_li.product_id, v_member);
  elsif v_li.line_kind = 'voucher' then
    v_pj := public.voucher_price_for(v_inv.store_id, v_li.voucher_id, v_member);
  else
    v_pj := public.promotion_price_for(v_inv.store_id, v_li.promotion_id, v_member);
  end if;
  if not coalesce((v_pj->>'has_price')::boolean,false) then
    raise exception 'No % price is set for this line at this store', p_mode; end if;
  v_new := (v_pj->>'price')::numeric;

  update public.invoice_items
     set unit_price = v_new,
         line_total = (v_new * quantity) + coalesce(topup_amount,0),
         line_discount = case when line_voucher_id is not null
           then public.voucher_discount_amount(line_voucher_id, v_new * quantity)
           else line_discount end,
         price_mode = p_mode, price_source = 'manual_override',
         price_source_id = (v_pj->>'source_id')::uuid,
         member_price_snapshot = (v_pj->>'member_price')::numeric,
         non_member_price_snapshot = (v_pj->>'non_member_price')::numeric,
         original_price = coalesce(original_price, v_li.unit_price),
         price_overridden = true, override_reason = trim(p_reason),
         override_by = auth.uid(), override_at = now()
   where id = p_item_id;

  update public.invoices set subtotal =
    coalesce((select sum(line_total) from public.invoice_items where invoice_id = v_inv.id),0)
   where id = v_inv.id;
  perform public.refresh_invoice_discount_total(v_inv.id);
  update public.invoices i set total_amount = greatest(0, i.subtotal - coalesce(i.discount_total,0))
   where i.id = v_inv.id;

  perform public.write_audit_ex('invoice_items', p_item_id, 'line_price_overridden',
    jsonb_build_object('old_mode', v_li.price_mode, 'old_price', v_li.unit_price),
    jsonb_build_object('new_mode', p_mode, 'new_price', v_new), 'pricing', p_reason, v_inv.store_id);
end $$;

-- Membership line removal — blocked once any payment exists; releases the
-- reservation; reprices remaining lines by the customer's REAL membership.
create or replace function public.remove_membership_line(p_item_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_li public.invoice_items%rowtype; v_inv public.invoices%rowtype;
begin
  select * into v_li from public.invoice_items where id = p_item_id and line_kind = 'membership';
  if not found then raise exception 'Membership line not found'; end if;
  select * into v_inv from public.invoices where id = v_li.invoice_id;
  if v_inv.status in ('paid','cancelled','refunded') or v_inv.locked_at is not null then
    raise exception 'Invoice is locked'; end if;
  if coalesce(v_inv.paid_amount,0) > 0 then
    raise exception 'Lines cannot be changed after a payment has been recorded'; end if;
  if not (public.is_manager_or_above() or public.user_has_store_access(v_inv.store_id)) then
    raise exception 'No access'; end if;

  perform public.release_member_id_reservations_for_invoice(v_inv.id);
  delete from public.invoice_items where id = p_item_id;

  perform public.reprice_invoice_lines(v_inv.id,
    coalesce((public.customer_membership_status(v_inv.customer_id)->>'is_member')::boolean, false));

  perform public.write_audit_ex('invoice_items', p_item_id, 'membership_line_removed',
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'plan', v_li.plan_name_snapshot), null,
    'membership', null, v_inv.store_id);
end $$;

-- =====================================================================
-- G. pay_invoice — exact ordered atomic flow. Existing stock, voucher
-- redemption, multi-payment, commission, audit and locking behaviour is
-- preserved verbatim; membership steps are inserted in the required order.
-- =====================================================================
create or replace function public.pay_invoice(p_invoice_id uuid, p_payments jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_pay jsonb; v_method uuid; v_amount numeric;
  v_total_paying numeric := 0; v_already_paid numeric; v_new_paid numeric;
  v_req record; v_available integer; v_li record;
  v_ms jsonb; v_is_member boolean; v_memline record; v_will_be_full boolean;
  v_old_total numeric; v_changes jsonb;
  v_owned_id text; v_resv public.member_id_reservations%rowtype;
  v_start date; v_expiry date; v_months integer;
  v_prev_id uuid; v_prev_expiry date; v_is_renewal boolean := false;
  v_new_membership uuid; v_use_member_id text;
begin
  -- 1. Lock invoice.
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  -- 2. Role/store access.
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access to this invoice''s store'; end if;
  -- 3. Editable/payable + customer present.
  if v_inv.status in ('paid','cancelled','refunded') then raise exception 'Invoice is already %', v_inv.status; end if;
  if v_inv.customer_id is null then raise exception 'Invoice has no customer'; end if;
  if p_payments is null or jsonb_array_length(p_payments) = 0 then raise exception 'At least one payment is required'; end if;

  -- 4. Lock the customer's membership rows (renewal decisions are made on them).
  perform 1 from public.customer_memberships
    where customer_id = v_inv.customer_id and deleted_at is null for update;

  -- 5. Recheck membership + same-invoice membership line.
  select * into v_memline from public.invoice_membership_line(p_invoice_id) limit 1;
  v_ms := public.customer_membership_status(v_inv.customer_id);
  v_is_member := coalesce((v_ms->>'is_member')::boolean, false) or (v_memline.plan_id is not null);

  -- 6. Reprice all applicable non-overridden lines (strict prices + eligibility
  --    enforced inside; raises with the line name if anything is missing).
  v_old_total := v_inv.total_amount;
  v_changes := public.reprice_invoice_lines(p_invoice_id, v_is_member);
  select * into v_inv from public.invoices where id = p_invoice_id;   -- fresh totals

  -- 7. If anything changed, persist the repriced invoice, record NO payment,
  --    and return a structured review request.
  if jsonb_array_length(v_changes) > 0 then
    perform public.write_audit('invoices', p_invoice_id, 'payment_price_review', null,
      jsonb_build_object('invoice_no', v_inv.invoice_no, 'old_total', v_old_total,
                         'new_total', v_inv.total_amount, 'changes', v_changes));
    return jsonb_build_object(
      'success', false, 'review_required', true,
      'old_total', v_old_total, 'new_total', v_inv.total_amount, 'changes', v_changes);
  end if;

  -- 8. Validate the membership line + its snapshots.
  if v_memline.plan_id is not null then
    if v_memline.plan_months is null or v_memline.unit_price is null then
      raise exception 'Membership line is missing its plan snapshot — remove and re-add the membership line'; end if;
    select member_id into v_owned_id from public.member_ids where customer_id = v_inv.customer_id;
    v_is_renewal := v_owned_id is not null;

    -- 9. Member ID before ANY payment (partial included).
    if v_is_renewal then
      -- Renewal reuses the permanent ID; a conflicting reservation is an error.
      select * into v_resv from public.member_id_reservations
        where customer_id = v_inv.customer_id limit 1;
      if v_resv.member_id is not null and v_resv.member_id <> v_owned_id then
        raise exception 'This customer already owns Member ID % — the reservation for % conflicts',
          v_owned_id, v_resv.member_id; end if;
      v_use_member_id := v_owned_id;
    else
      select * into v_resv from public.member_id_reservations
        where invoice_id = p_invoice_id and customer_id = v_inv.customer_id limit 1;
      if v_resv.member_id is null then
        raise exception 'A Member ID must be assigned before any payment can be taken on a membership invoice'; end if;
      v_use_member_id := v_resv.member_id;
    end if;
  end if;

  -- 10./11. Prices + eligibility were enforced during reprice; promotion gate:
  if not coalesce((v_ms->>'is_member')::boolean,false) and v_memline.plan_id is null then
    if exists (select 1 from public.invoice_items ii
                where ii.invoice_id = p_invoice_id and ii.line_kind = 'promotion'
                  and coalesce(ii.price_overridden,false) = false) then
      raise exception 'Promotions are for members only. Add a membership to this invoice or apply a manual override.';
    end if;
  end if;

  -- 13. Validate payment amounts.
  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_amount := (v_pay->>'amount')::numeric;
    if v_amount is null or v_amount <= 0 then raise exception 'Payment amount must be positive'; end if;
    v_total_paying := v_total_paying + v_amount;
  end loop;
  v_already_paid := v_inv.paid_amount;
  v_new_paid := v_already_paid + v_total_paying;
  if v_new_paid > v_inv.total_amount + 0.001 then raise exception 'Payment exceeds remaining balance'; end if;
  v_will_be_full := v_new_paid >= v_inv.total_amount - 0.001;

  -- 12. Stock check (only matters when this payment completes the invoice).
  if v_will_be_full then
    for v_req in select * from public.invoice_required_stock(p_invoice_id)
    loop
      if v_req.kind = 'product' then
        select current_qty into v_available from public.store_inventory
          where store_id = v_inv.store_id and product_id = v_req.item_id for update;
        if coalesce(v_available,0) < v_req.quantity then
          raise exception 'Insufficient store stock for % (have %, need % incl. bundles). Payment blocked.',
            (select name from public.products where id = v_req.item_id), coalesce(v_available,0), v_req.quantity;
        end if;
      else
        select current_qty into v_available from public.voucher_store_stock
          where store_id = v_inv.store_id and voucher_id = v_req.item_id for update;
        if coalesce(v_available,0) < v_req.quantity then
          raise exception 'Insufficient voucher stock for % (have %, need % incl. bundles). Payment blocked.',
            (select name from public.vouchers where id = v_req.item_id), coalesce(v_available,0), v_req.quantity;
        end if;
      end if;
    end loop;
  end if;

  -- 14. Record payments.
  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_method := (v_pay->>'payment_method_id')::uuid;
    v_amount := (v_pay->>'amount')::numeric;
    insert into public.invoice_payments (invoice_id, payment_method_id, amount, payment_reference, received_by)
    values (p_invoice_id, v_method, v_amount, v_pay->>'reference', auth.uid());
  end loop;

  if v_will_be_full then
    -- 15. Deduct stock.
    for v_req in select * from public.invoice_required_stock(p_invoice_id)
    loop
      if v_req.kind = 'product' then
        update public.store_inventory set current_qty = current_qty - v_req.quantity, updated_at = now()
          where store_id = v_inv.store_id and product_id = v_req.item_id;
        insert into public.stock_movements (product_id, movement_type, from_store_id, invoice_id, quantity, notes, created_by)
        values (v_req.item_id, 'store_sale', v_inv.store_id, p_invoice_id, v_req.quantity, 'Sale — '||v_inv.invoice_no, auth.uid());
      else
        update public.voucher_store_stock set current_qty = current_qty - v_req.quantity, updated_at = now()
          where store_id = v_inv.store_id and voucher_id = v_req.item_id;
        perform public.write_audit('vouchers', v_req.item_id, 'voucher_sold', null,
          jsonb_build_object('invoice_no', v_inv.invoice_no, 'qty', v_req.quantity));
      end if;
    end loop;

    -- 16. Mark paid + lock.
    update public.invoices set status = 'paid', paid_amount = v_new_paid, paid_at = now(), locked_at = now()
      where id = p_invoice_id;

    -- Voucher redemptions (preserved).
    if v_inv.discount_voucher_id is not null then
      insert into public.voucher_redemptions (voucher_id, invoice_id, customer_id, discount_applied, redeemed_by)
      values (v_inv.discount_voucher_id, p_invoice_id, v_inv.customer_id,
              v_inv.discount_total - coalesce((select sum(line_discount) from public.invoice_items where invoice_id = p_invoice_id),0),
              auth.uid());
      perform public.write_audit('vouchers', v_inv.discount_voucher_id, 'voucher_redeemed', null,
        jsonb_build_object('invoice_no', v_inv.invoice_no));
    end if;
    for v_li in select line_voucher_id, line_discount from public.invoice_items
      where invoice_id = p_invoice_id and line_voucher_id is not null
    loop
      insert into public.voucher_redemptions (voucher_id, invoice_id, customer_id, discount_applied, redeemed_by)
      values (v_li.line_voucher_id, p_invoice_id, v_inv.customer_id, v_li.line_discount, auth.uid());
      perform public.write_audit('vouchers', v_li.line_voucher_id, 'voucher_redeemed', null,
        jsonb_build_object('invoice_no', v_inv.invoice_no, 'line_discount', v_li.line_discount));
    end loop;

    -- 17. Create the membership / future renewal FROM SNAPSHOTS.
    if v_memline.plan_id is not null then
      v_months := v_memline.plan_months;
      -- Renewal starts the day after the LATEST applicable expiry (rows locked
      -- in step 4). Applicable = dated, not cancelled, not deleted, not ended.
      select id, expiry_date into v_prev_id, v_prev_expiry
        from public.customer_memberships
        where customer_id = v_inv.customer_id and deleted_at is null
          and status <> 'cancelled' and start_date is not null and expiry_date is not null
          and expiry_date >= public.sg_today()
        order by expiry_date desc limit 1;

      if v_prev_id is not null then
        v_start := public.membership_renewal_start(v_prev_expiry);
        v_is_renewal := true;
      else
        v_start := public.sg_today();
      end if;
      v_expiry := public.membership_expiry(v_start, v_months);

      insert into public.customer_memberships (
        customer_id, plan_id, store_id, member_id, source, invoice_id, invoice_item_id,
        fee_snapshot, start_date, expiry_date, status, is_renewal, previous_membership_id,
        activated_at, created_by)
      values (
        v_inv.customer_id, v_memline.plan_id, v_inv.store_id, v_use_member_id,
        case when v_is_renewal then 'renewal' else 'sale' end,
        p_invoice_id, v_memline.item_id,
        v_memline.unit_price, v_start, v_expiry, 'active',
        v_is_renewal, v_prev_id, now(), auth.uid())
      returning id into v_new_membership;

      -- Keep the line snapshot complete for printing.
      update public.invoice_items set member_id_snapshot = v_use_member_id
        where id = v_memline.item_id and member_id_snapshot is null;

      -- 18. Commit a NEW reservation to permanent ownership; renewals already own.
      if not (v_owned_id is not null) then
        perform public.commit_member_id(v_use_member_id, v_inv.customer_id);
      end if;

      perform public.write_audit_ex('customer_memberships', v_new_membership, 'membership_activated',
        null, jsonb_build_object('plan', v_memline.plan_id, 'start', v_start, 'expiry', v_expiry,
                                 'renewal', v_is_renewal, 'member_id', v_use_member_id,
                                 'invoice_no', v_inv.invoice_no),
        'membership', null, v_inv.store_id);
    end if;

    -- 19. Commissions (membership line = Own Product, earns normally).
    perform public.earn_invoice_commission(p_invoice_id);
    perform public.earn_staff_commission(p_invoice_id);

    -- 20. Audit.
    perform public.write_audit('invoices', p_invoice_id, 'invoice_paid', null,
      jsonb_build_object('paid_amount', v_new_paid, 'invoice_no', v_inv.invoice_no,
                         'membership_created', (v_new_membership is not null)));
    return jsonb_build_object('success', true, 'status', 'paid', 'paid_amount', v_new_paid,
                              'membership_id', v_new_membership);
  else
    -- Partial payment: money recorded, NOTHING activates, no stock moves.
    update public.invoices set paid_amount = v_new_paid, status = 'partially_paid' where id = p_invoice_id;
    perform public.write_audit('invoices', p_invoice_id, 'invoice_partial_payment', null,
      jsonb_build_object('paid_amount', v_new_paid));
    return jsonb_build_object('success', true, 'status', 'partially_paid', 'paid_amount', v_new_paid,
                              'remaining', v_inv.total_amount - v_new_paid);
  end if;
end; $$;

-- =====================================================================
-- H. Reservation permission hardening + automatic release
-- =====================================================================
create or replace function public.reserve_member_id(
  p_member_id text, p_customer_id uuid, p_invoice_id uuid default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_id text; v_inv public.invoices%rowtype;
begin
  if public.current_user_role() is null then raise exception 'No profile'; end if;
  if public.current_user_role() = 'inventory_manager' then
    raise exception 'Inventory Manager cannot manage Member IDs'; end if;
  v_id := nullif(trim(p_member_id), '');
  if v_id is null then raise exception 'Member ID is required'; end if;

  if p_invoice_id is not null then
    select * into v_inv from public.invoices where id = p_invoice_id;
    if not found then raise exception 'Invoice not found'; end if;
    if not public.user_has_store_access(v_inv.store_id) then
      raise exception 'No access to this invoice''s store'; end if;
    if v_inv.customer_id <> p_customer_id then
      raise exception 'The reservation customer does not match the invoice customer'; end if;
    if v_inv.status in ('paid','cancelled','refunded') then
      raise exception 'Invoice is %', v_inv.status; end if;
  elsif not public.is_manager_or_above() then
    raise exception 'Only a Manager or above can reserve a Member ID without an invoice';
  end if;

  if exists (select 1 from public.member_ids where member_id = v_id and customer_id <> p_customer_id) then
    raise exception 'Member ID % is already assigned to another customer', v_id; end if;
  if exists (select 1 from public.member_id_reservations where member_id = v_id and customer_id <> p_customer_id) then
    raise exception 'Member ID % is currently reserved for another customer', v_id; end if;
  if exists (select 1 from public.member_ids where member_id = v_id and customer_id = p_customer_id) then
    return; end if;

  -- One active reservation per customer (uq_midres_customer backs this up).
  delete from public.member_id_reservations where customer_id = p_customer_id and member_id <> v_id;
  insert into public.member_id_reservations (member_id, customer_id, invoice_id, reserved_by)
  values (v_id, p_customer_id, p_invoice_id, auth.uid())
  on conflict (member_id) do update
    set invoice_id = excluded.invoice_id, reserved_at = now(), reserved_by = auth.uid()
    where public.member_id_reservations.customer_id = excluded.customer_id;
end $$;

create or replace function public.release_member_id_reservation(p_member_id text)
returns void language plpgsql security definer set search_path = public as $$
declare v_r public.member_id_reservations%rowtype; v_inv public.invoices%rowtype;
begin
  select * into v_r from public.member_id_reservations where member_id = nullif(trim(p_member_id),'');
  if not found then return; end if;
  if v_r.invoice_id is not null then
    select * into v_inv from public.invoices where id = v_r.invoice_id;
    if not (public.is_manager_or_above() or public.user_has_store_access(v_inv.store_id)) then
      raise exception 'No access to release this reservation'; end if;
  elsif not public.is_manager_or_above() then
    raise exception 'Only a Manager or above can release this reservation';
  end if;
  delete from public.member_id_reservations where member_id = v_r.member_id;
end $$;

-- Automatic release when an invoice that can no longer be paid dies:
-- soft-deleted, or cancelled after approval — in both cases only when no
-- payment was ever completed. A cancellation REQUEST does not fire this
-- (status 'cancellation_requested' is not 'cancelled'), and a rejected
-- request returns to 'unpaid', so the reservation is kept — as specified.
create or replace function public.trg_release_reservations_dead_invoice() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.deleted_at is not null and old.deleted_at is null and old.paid_at is null)
     or (new.status = 'cancelled' and old.status is distinct from 'cancelled' and old.paid_at is null) then
    delete from public.member_id_reservations where invoice_id = new.id;
  end if;
  return null;
end $$;

drop trigger if exists release_reservations_dead_invoice on public.invoices;
create trigger release_reservations_dead_invoice
  after update on public.invoices
  for each row execute function public.trg_release_reservations_dead_invoice();


-- =====================================================================
-- Seed voucher store prices (Phase 3 seeded promotions but NOT vouchers).
-- Without this, strict pricing would block every voucher sale on day one.
-- Member price = legacy selling_price; Non-Member left blank for staff.
-- =====================================================================
insert into public.voucher_store_prices (voucher_id, store_id, member_price)
select v.id, s.id, v.selling_price
from public.vouchers v
cross join public.stores s
where v.deleted_at is null and s.deleted_at is null
  and not exists (select 1 from public.voucher_store_prices x
                   where x.voucher_id = v.id and x.store_id = s.id)
on conflict (voucher_id, store_id) do nothing;

notify pgrst, 'reload schema';
