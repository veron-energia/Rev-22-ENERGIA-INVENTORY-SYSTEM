-- =====================================================================
-- ENERGIA — PHASE 28: ENERGIA PRODUCT PREMIUM BUNDLES
--
-- A Premium Bundle is its own catalogue, separate from ordinary Promotions.
-- The customer pays once and receives Paid Credit, Bonus Credit and a large
-- quantity of free reward vouchers issued immediately at payment.
--
-- Bundle A: pays $15,000 -> $15,000 Paid Credit + $2,000 Bonus Credit
--           + floor(15000 / 994) x 10 = 150 free vouchers (remainder $90 forfeited)
--
-- Key rules implemented here:
--   * Reward is vouchers ONLY — no Therapy-month choice, unlike a Legacy unit.
--   * The customer picks any mixture of eligible vouchers up to the required
--     quantity; stock is validated before payment and the payment is blocked
--     if it is short. Issued vouchers never expire.
--   * Bundle Paid and Bonus Credit may buy products, vouchers, promotions,
--     purchasable therapy and rentals — but never another Credit Package or
--     Premium Bundle.
--   * Commission uses the THIRD-PARTY percentage by default, is editable per
--     bundle, and is calculated only on external money paid after discount and
--     FOC — never on Bonus Credit, free vouchers or later redemption.
--   * A bundle never enters Legacy daily qualification.
--
-- Additive and idempotent. Run AFTER 79.
-- (Numbered 80 to stay sequential — 75 is already the Phase 25 fix.)
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Reward vouchers gain a source, so bundle-issued vouchers are traceable.
-- ---------------------------------------------------------------------
alter table public.customer_reward_vouchers add column if not exists source_type text;
alter table public.customer_reward_vouchers add column if not exists source_id uuid;
create index if not exists idx_crv_source on public.customer_reward_vouchers (source_type, source_id);

-- ---------------------------------------------------------------------
-- 2. Catalogue — deliberately separate from promotions.
-- ---------------------------------------------------------------------
create table if not exists public.premium_bundles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  customer_payment_amount numeric(12,2) not null check (customer_payment_amount >= 0),
  paid_credit_amount numeric(12,2) not null default 0 check (paid_credit_amount >= 0),
  bonus_credit_amount numeric(12,2) not null default 0 check (bonus_credit_amount >= 0),
  free_voucher_qty integer not null default 0 check (free_voucher_qty >= 0),
  reward_qualifying_amount numeric(12,2),
  is_active boolean not null default true,
  effective_from date not null default (now() at time zone 'Asia/Singapore')::date,
  effective_to date,
  -- Premium bundles commission at the third-party rate by default.
  commission_classification text not null default 'third_party'
    check (commission_classification in ('own','third_party')),
  staff_commission_enabled boolean not null default true,
  staff_commission_rate numeric(6,3),
  tier1_rate numeric(6,3),
  tier2_rate numeric(6,3),
  notes text,
  deleted_at timestamptz,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.premium_bundle_stores (
  bundle_id uuid not null references public.premium_bundles(id) on delete cascade,
  store_id uuid not null references public.stores(id),
  primary key (bundle_id, store_id)
);

create table if not exists public.premium_bundle_vouchers (
  bundle_id uuid not null references public.premium_bundles(id) on delete cascade,
  voucher_id uuid not null references public.vouchers(id),
  primary key (bundle_id, voucher_id)
);

create table if not exists public.premium_bundle_sales (
  id uuid primary key default gen_random_uuid(),
  bundle_id uuid not null references public.premium_bundles(id),
  customer_id uuid not null references public.customers(id),
  store_id uuid references public.stores(id),
  invoice_id uuid references public.invoices(id),
  -- Permanent benefit snapshot.
  bundle_name_snapshot text not null,
  payment_snapshot numeric(12,2) not null,
  paid_credit_snapshot numeric(12,2) not null,
  bonus_credit_snapshot numeric(12,2) not null,
  voucher_qty_snapshot integer not null,
  classification_snapshot text not null,
  tier1_rate_snapshot numeric(6,3),
  tier2_rate_snapshot numeric(6,3),
  staff_rate_snapshot numeric(6,3),
  reward_qualifying_snapshot numeric(12,2),
  forfeited_remainder numeric(12,2) not null default 0,
  eligible_voucher_ids uuid[] not null default '{}',
  external_paid numeric(12,2) not null default 0,
  paid_credit_lot_id uuid references public.customer_credit_lots(id),
  bonus_credit_lot_id uuid references public.customer_credit_lots(id),
  vouchers_issued integer not null default 0,
  sold_at timestamptz not null default now(),
  created_by uuid references public.profiles(id)
);
create index if not exists idx_pbs_customer on public.premium_bundle_sales (customer_id);

do $$
declare t text;
begin
  foreach t in array array['premium_bundles','premium_bundle_stores',
                           'premium_bundle_vouchers','premium_bundle_sales'] loop
    execute format('alter table public.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname='public' and tablename=t
                    and policyname='read premium bundles') then
      execute format($f$create policy "read premium bundles" on public.%I
                        for select to authenticated using (true)$f$, t);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 3. The free voucher quantity a payment earns.
--    floor(payment / qualifying) x 10; the remainder is forfeited.
-- ---------------------------------------------------------------------
create or replace function public.premium_bundle_voucher_entitlement(
  p_payment numeric, p_qualifying numeric)
returns integer language sql immutable as $function$
  select case when coalesce(p_qualifying,0) <= 0 then 0
              else floor(coalesce(p_payment,0) / p_qualifying)::integer * 10 end
$function$;

-- ---------------------------------------------------------------------
-- 4. Catalogue management (Owner/Manager only).
-- ---------------------------------------------------------------------
create or replace function public.upsert_premium_bundle(
  p_id uuid, p_name text, p_customer_payment_amount numeric,
  p_paid_credit_amount numeric, p_bonus_credit_amount numeric,
  p_free_voucher_qty integer default null, p_reward_qualifying_amount numeric default null,
  p_is_active boolean default true, p_effective_from date default null,
  p_effective_to date default null, p_commission_classification text default 'third_party',
  p_staff_commission_enabled boolean default true, p_staff_commission_rate numeric default null,
  p_tier1_rate numeric default null, p_tier2_rate numeric default null,
  p_notes text default null, p_store_ids uuid[] default null, p_voucher_ids uuid[] default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid; v_qual numeric; v_qty integer;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can manage premium bundles'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'A bundle name is required'; end if;
  if coalesce(p_customer_payment_amount,-1) < 0 then raise exception 'The customer payment amount is required'; end if;
  if p_commission_classification not in ('own','third_party') then
    raise exception 'Commission classification must be own or third_party'; end if;

  -- Default the free quantity from the payment when it is not given.
  v_qual := coalesce(p_reward_qualifying_amount,
                     (select qualifying_amount from public.therapy_package_rules
                       where is_active = true and deleted_at is null
                         and coalesce(applies_to,'customer') = 'customer'
                       order by qualifying_amount asc limit 1),
                     994);
  v_qty := coalesce(p_free_voucher_qty,
                    public.premium_bundle_voucher_entitlement(p_customer_payment_amount, v_qual));

  if p_id is null then
    insert into public.premium_bundles (name, customer_payment_amount, paid_credit_amount,
      bonus_credit_amount, free_voucher_qty, reward_qualifying_amount, is_active,
      effective_from, effective_to, commission_classification, staff_commission_enabled,
      staff_commission_rate, tier1_rate, tier2_rate, notes, created_by, updated_by)
    values (trim(p_name), p_customer_payment_amount, coalesce(p_paid_credit_amount,0),
      coalesce(p_bonus_credit_amount,0), v_qty, v_qual, coalesce(p_is_active,true),
      coalesce(p_effective_from, public.sg_today()), p_effective_to,
      p_commission_classification, coalesce(p_staff_commission_enabled,true),
      p_staff_commission_rate, p_tier1_rate, p_tier2_rate, p_notes, auth.uid(), auth.uid())
    returning id into v_id;
  else
    update public.premium_bundles
       set name = trim(p_name), customer_payment_amount = p_customer_payment_amount,
           paid_credit_amount = coalesce(p_paid_credit_amount,0),
           bonus_credit_amount = coalesce(p_bonus_credit_amount,0),
           free_voucher_qty = v_qty, reward_qualifying_amount = v_qual,
           is_active = coalesce(p_is_active,true),
           effective_from = coalesce(p_effective_from, effective_from), effective_to = p_effective_to,
           commission_classification = p_commission_classification,
           staff_commission_enabled = coalesce(p_staff_commission_enabled,true),
           staff_commission_rate = p_staff_commission_rate,
           tier1_rate = p_tier1_rate, tier2_rate = p_tier2_rate, notes = p_notes,
           updated_by = auth.uid(), updated_at = now()
     where id = p_id
    returning id into v_id;
    if v_id is null then raise exception 'Premium bundle not found'; end if;
  end if;

  if p_store_ids is not null then
    delete from public.premium_bundle_stores where bundle_id = v_id;
    insert into public.premium_bundle_stores (bundle_id, store_id)
    select v_id, unnest(p_store_ids) on conflict do nothing;
  end if;
  if p_voucher_ids is not null then
    delete from public.premium_bundle_vouchers where bundle_id = v_id;
    insert into public.premium_bundle_vouchers (bundle_id, voucher_id)
    select v_id, unnest(p_voucher_ids) on conflict do nothing;
  end if;

  perform public.write_audit_ex('premium_bundles', v_id, 'premium_bundle_upserted', null,
    jsonb_build_object('name', p_name, 'payment', p_customer_payment_amount,
      'paid_credit', p_paid_credit_amount, 'bonus_credit', p_bonus_credit_amount,
      'vouchers', v_qty, 'classification', p_commission_classification), 'credit', null, null);
  return v_id;
end $function$;

create or replace function public.soft_delete_premium_bundle(p_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $function$
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can remove premium bundles'; end if;
  update public.premium_bundles set deleted_at = now(), is_active = false,
         updated_by = auth.uid(), updated_at = now() where id = p_id;
  perform public.write_audit_ex('premium_bundles', p_id, 'premium_bundle_deleted', null, null, 'credit', null, null);
end $function$;

create or replace function public.premium_bundles_for_store(p_store_id uuid, p_day date default null)
returns setof public.premium_bundles
language sql stable security definer set search_path to 'public' as $function$
  select b.* from public.premium_bundles b
   where b.deleted_at is null and b.is_active = true
     and b.effective_from <= coalesce(p_day, public.sg_today())
     and (b.effective_to is null or b.effective_to >= coalesce(p_day, public.sg_today()))
     and (not exists (select 1 from public.premium_bundle_stores s where s.bundle_id = b.id)
          or exists (select 1 from public.premium_bundle_stores s
                      where s.bundle_id = b.id and s.store_id = p_store_id))
   order by b.customer_payment_amount desc
$function$;

-- ---------------------------------------------------------------------
-- 5. Stock validation for a chosen voucher mix, before any money moves.
-- ---------------------------------------------------------------------
create or replace function public.validate_bundle_voucher_selection(
  p_bundle_id uuid, p_store_id uuid, p_selections jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare
  b public.premium_bundles%rowtype; v_sel jsonb; v_vid uuid; v_qty integer;
  v_sum integer := 0; v_stock integer; v_short text[] := '{}';
begin
  select * into b from public.premium_bundles where id = p_bundle_id and deleted_at is null;
  if not found then raise exception 'Premium bundle not found'; end if;

  for v_sel in select * from jsonb_array_elements(coalesce(p_selections,'[]'::jsonb)) loop
    v_vid := (v_sel->>'voucher_id')::uuid;
    v_qty := coalesce((v_sel->>'quantity')::integer, 0);
    if v_qty <= 0 then continue; end if;
    if not exists (select 1 from public.premium_bundle_vouchers
                    where bundle_id = p_bundle_id and voucher_id = v_vid) then
      raise exception 'Voucher "%" is not an eligible choice for this bundle',
        (select name from public.vouchers where id = v_vid);
    end if;
    v_sum := v_sum + v_qty;
    if exists (select 1 from public.vouchers where id = v_vid and qty_type <> 'unlimited') then
      select coalesce(current_qty,0) into v_stock from public.voucher_store_stock
       where voucher_id = v_vid and store_id = p_store_id;
      if coalesce(v_stock,0) < v_qty then
        v_short := array_append(v_short,
          (select name from public.vouchers where id = v_vid) || ' (need ' || v_qty
          || ', have ' || coalesce(v_stock,0) || ')');
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'required_qty', b.free_voucher_qty, 'selected_qty', v_sum,
    'complete', v_sum = b.free_voucher_qty,
    'stock_ok', array_length(v_short,1) is null,
    'shortages', to_jsonb(v_short));
end $function$;

-- ---------------------------------------------------------------------
-- 6. Selling a bundle: validate, take the money, then create both credit
--    lots and issue every reward voucher — all in one transaction.
-- ---------------------------------------------------------------------
create or replace function public.sell_premium_bundle(
  p_bundle_id uuid, p_customer_id uuid, p_store_id uuid,
  p_payments jsonb, p_voucher_selections jsonb,
  p_discount numeric default 0, p_foc_amount numeric default 0,
  p_invoice_id uuid default null, p_is_completed_foc boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  b public.premium_bundles%rowtype;
  v_check jsonb; v_external numeric := 0; v_p jsonb; v_due numeric;
  v_paid_lot uuid; v_bonus_lot uuid; v_sale uuid; v_restrict jsonb;
  v_sel jsonb; v_vid uuid; v_qty integer; v_stock integer; v_issued integer := 0;
  v_vouchers uuid[]; v_qual numeric; v_units integer; v_remainder numeric;
  v_comm jsonb;
begin
  select * into b from public.premium_bundles where id = p_bundle_id and deleted_at is null;
  if not found then raise exception 'Premium bundle not found'; end if;
  if p_customer_id is null then raise exception 'A customer is required'; end if;
  if not exists (select 1 from public.premium_bundles_for_store(p_store_id) x where x.id = p_bundle_id) then
    raise exception 'That premium bundle is not available at this store'; end if;

  -- The bundle itself is a paid offer: wallet credit may not fund it.
  for v_p in select * from jsonb_array_elements(coalesce(p_payments,'[]'::jsonb)) loop
    if coalesce(v_p->>'method','') = 'wallet_credit' or (v_p->>'use_wallet_credit')::boolean is true then
      raise exception 'A premium bundle cannot be paid for with wallet credit';
    end if;
    v_external := v_external + coalesce((v_p->>'amount')::numeric, 0);
  end loop;

  -- Validate the chosen mixture and its stock BEFORE anything is committed.
  v_check := public.validate_bundle_voucher_selection(p_bundle_id, p_store_id, p_voucher_selections);
  if not (v_check->>'complete')::boolean then
    raise exception 'Select exactly % voucher(s) — % chosen',
      v_check->>'required_qty', v_check->>'selected_qty';
  end if;
  if not (v_check->>'stock_ok')::boolean then
    raise exception 'Payment blocked — not enough voucher stock: %',
      array_to_string(array(select jsonb_array_elements_text(v_check->'shortages')), '; ');
  end if;

  -- Money due after discount and any FOC portion.
  v_due := greatest(round(b.customer_payment_amount - coalesce(p_discount,0) - coalesce(p_foc_amount,0), 2), 0);
  if not coalesce(p_is_completed_foc,false) and round(v_external,2) < v_due then
    raise exception 'The bundle needs % but only % was paid externally', v_due, round(v_external,2);
  end if;

  select coalesce(array_agg(voucher_id),'{}') into v_vouchers
    from public.premium_bundle_vouchers where bundle_id = p_bundle_id;

  -- Bundle credit is broadly usable, but never on another credit product.
  v_restrict := jsonb_build_object(
    'allowed_purposes', jsonb_build_array('product','voucher','promotion','therapy','rental'),
    'allowed_voucher_ids', '[]'::jsonb, 'source', 'premium_bundle');

  if b.paid_credit_amount > 0 then
    v_paid_lot := public.grant_customer_credit(p_customer_id, 'paid', b.paid_credit_amount,
      'premium_bundle', p_bundle_id, p_store_id, public.sg_today(), null,
      'Premium bundle: ' || b.name, null, null, auth.uid(), v_restrict);
  end if;
  if b.bonus_credit_amount > 0 then
    v_bonus_lot := public.grant_customer_credit(p_customer_id, 'bonus', b.bonus_credit_amount,
      'premium_bundle', p_bundle_id, p_store_id, public.sg_today(), null,
      'Premium bundle bonus: ' || b.name, null, null, auth.uid(), v_restrict);
  end if;

  v_qual := coalesce(b.reward_qualifying_amount, 994);
  v_units := case when v_qual > 0 then floor(b.customer_payment_amount / v_qual)::integer else 0 end;
  v_remainder := round(b.customer_payment_amount - (v_units * v_qual), 2);

  insert into public.premium_bundle_sales (
    bundle_id, customer_id, store_id, invoice_id, bundle_name_snapshot,
    payment_snapshot, paid_credit_snapshot, bonus_credit_snapshot, voucher_qty_snapshot,
    classification_snapshot, tier1_rate_snapshot, tier2_rate_snapshot, staff_rate_snapshot,
    reward_qualifying_snapshot, forfeited_remainder, eligible_voucher_ids,
    external_paid, paid_credit_lot_id, bonus_credit_lot_id, created_by)
  values (p_bundle_id, p_customer_id, p_store_id, p_invoice_id, b.name,
    b.customer_payment_amount, b.paid_credit_amount, b.bonus_credit_amount, b.free_voucher_qty,
    b.commission_classification, b.tier1_rate, b.tier2_rate, b.staff_commission_rate,
    v_qual, v_remainder, v_vouchers, round(v_external,2), v_paid_lot, v_bonus_lot, auth.uid())
  returning id into v_sale;

  -- Issue the reward vouchers immediately and deduct stock. Vouchers never expire.
  for v_sel in select * from jsonb_array_elements(coalesce(p_voucher_selections,'[]'::jsonb)) loop
    v_vid := (v_sel->>'voucher_id')::uuid;
    v_qty := coalesce((v_sel->>'quantity')::integer, 0);
    if v_qty <= 0 then continue; end if;
    if exists (select 1 from public.vouchers where id = v_vid and qty_type <> 'unlimited') then
      select current_qty into v_stock from public.voucher_store_stock
       where voucher_id = v_vid and store_id = p_store_id for update;
      if coalesce(v_stock,0) < v_qty then
        raise exception 'Payment blocked — stock of "%" ran out',
          (select name from public.vouchers where id = v_vid); end if;
      update public.voucher_store_stock set current_qty = current_qty - v_qty, updated_at = now()
       where voucher_id = v_vid and store_id = p_store_id;
    end if;
    insert into public.customer_reward_vouchers
      (customer_id, voucher_id, entitlement_id, store_id, quantity, issued_by, notes,
       source_type, source_id)
    values (p_customer_id, v_vid, null, p_store_id, v_qty, auth.uid(),
      'Premium bundle reward — never expires, not transferable', 'premium_bundle', v_sale);
    v_issued := v_issued + v_qty;
  end loop;

  update public.premium_bundle_sales set vouchers_issued = v_issued where id = v_sale;

  v_comm := public.earn_premium_bundle_commission(v_sale);

  perform public.write_audit_ex('premium_bundle_sales', v_sale, 'premium_bundle_sold', null,
    jsonb_build_object('bundle', b.name, 'paid_credit', b.paid_credit_amount,
      'bonus_credit', b.bonus_credit_amount, 'vouchers', v_issued,
      'external_paid', round(v_external,2)), 'credit', null, p_store_id);

  return jsonb_build_object('sale_id', v_sale,
    'paid_credit', b.paid_credit_amount, 'bonus_credit', b.bonus_credit_amount,
    'vouchers_issued', v_issued, 'voucher_entitlement', b.free_voucher_qty,
    'qualifying_amount', v_qual, 'reward_units', v_units, 'forfeited_remainder', v_remainder,
    'external_paid', round(v_external,2), 'commission', v_comm);
end $function$;

-- ---------------------------------------------------------------------
-- 7. Commission: third-party rate by default, external money only.
-- ---------------------------------------------------------------------
create or replace function public.earn_premium_bundle_commission(p_sale_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  s public.premium_bundle_sales%rowtype;
  v_inv public.invoices%rowtype;
  v_t1 uuid; v_t2 uuid; v_base numeric; v_ptype text;
  v_r1 numeric; v_r2 numeric; v_a1 numeric; v_a2 numeric;
begin
  select * into s from public.premium_bundle_sales where id = p_sale_id;
  if not found then raise exception 'Bundle sale not found'; end if;

  -- Only external money after discount and FOC. Never bonus credit, free
  -- voucher value, or any later redemption.
  v_base := round(coalesce(s.external_paid,0), 2);
  if v_base <= 0 then return jsonb_build_object('skipped', true, 'reason', 'no external payment'); end if;
  if s.invoice_id is null then return jsonb_build_object('skipped', true, 'reason', 'no invoice'); end if;

  select * into v_inv from public.invoices where id = s.invoice_id;
  if v_inv.affiliate_id is not null then
    select a.customer_id into v_t1 from public.customer_affiliates a where a.id = v_inv.affiliate_id;
  else
    select c.referred_by into v_t1 from public.customers c where c.id = s.customer_id;
  end if;
  if v_t1 is null or v_t1 = s.customer_id then
    return jsonb_build_object('skipped', true, 'reason', 'no eligible referrer'); end if;
  select c.referred_by into v_t2 from public.customers c where c.id = v_t1;

  v_ptype := coalesce(s.classification_snapshot, 'third_party');
  select coalesce(s.tier1_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier1_third_rate
                else commission_tier1_own_rate end),
         coalesce(s.tier2_rate_snapshot,
           case when v_ptype = 'third_party' then commission_tier2_third_rate
                else commission_tier2_own_rate end)
    into v_r1, v_r2 from public.app_settings where id = true;

  v_a1 := round(v_base * v_r1 / 100.0, 2);
  if v_a1 > 0 then
    insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
      tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
    values (s.invoice_id, s.customer_id, v_t1, 'tier1', v_ptype, v_base, v_r1, v_a1,
      'earned', public.sg_today());
    if v_t2 is not null then
      v_a2 := round(v_a1 * v_r2 / 100.0, 2);
      if v_a2 > 0 then
        insert into public.commissions (invoice_id, buyer_customer_id, referrer_customer_id,
          tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
        values (s.invoice_id, s.customer_id, v_t2, 'tier2', v_ptype, v_a1, v_r2, v_a2,
          'earned', public.sg_today());
      end if;
    end if;
  end if;

  return jsonb_build_object('basis', v_base, 'classification', v_ptype,
    'tier1_rate', v_r1, 'tier2_rate', v_r2, 'tier1', v_a1, 'tier2', coalesce(v_a2,0));
end $function$;

notify pgrst, 'reload schema';
