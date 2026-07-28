-- =====================================================================
-- ENERGIA — PHASE 27: CREDIT PACKAGES
--
-- A Credit Package is a non-stock invoice line: the customer pays money and
-- receives Paid Credit that may only be spent on the package's eligible
-- Therapy Vouchers. The package also yields a separate free reward unit for
-- every whole qualifying amount of credit, claimed later from the Legacy
-- Entitlement page as either 10 eligible vouchers or one free Legacy Therapy
-- month.
--
-- Key rules implemented here:
--   * The package line itself can never be funded by wallet credit.
--   * Package credit carries usage restrictions and cannot buy products,
--     promotions, paid therapy, rentals, another package or a bundle.
--   * Reward units = floor(paid-credit value / qualifying amount); the
--     remainder creates nothing.
--   * Package reward units are excluded from BOTH customer same-day
--     qualification and Affiliate residual qualification.
--   * Commission is calculated on the actual external payment after discount
--     and FOC — never on credit issued or free reward value.
--   * The price and commission rates are snapshotted onto the invoice line so
--     later catalogue edits never change a sold package.
--
-- Additive and idempotent. Run AFTER 78.
-- (Numbered 79 to stay sequential — 74 is already Phase 25.)
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Catalogue
-- ---------------------------------------------------------------------
create table if not exists public.credit_packages (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  customer_price numeric(12,2) not null check (customer_price >= 0),
  paid_credit_amount numeric(12,2) not null check (paid_credit_amount >= 0),
  is_active boolean not null default true,
  effective_from date not null default (now() at time zone 'Asia/Singapore')::date,
  effective_to date,
  commission_classification text not null default 'own'
    check (commission_classification in ('own','third_party')),
  staff_commission_enabled boolean not null default true,
  staff_commission_rate numeric(6,3),
  tier1_rate numeric(6,3),
  tier2_rate numeric(6,3),
  reward_qualifying_amount numeric(12,2),
  notes text,
  deleted_at timestamptz,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.credit_package_stores (
  package_id uuid not null references public.credit_packages(id) on delete cascade,
  store_id uuid not null references public.stores(id),
  primary key (package_id, store_id)
);

-- The vouchers this package's credit (and its reward) may be spent on.
create table if not exists public.credit_package_vouchers (
  package_id uuid not null references public.credit_packages(id) on delete cascade,
  voucher_id uuid not null references public.vouchers(id),
  primary key (package_id, voucher_id)
);

alter table public.credit_packages enable row level security;
alter table public.credit_package_stores enable row level security;
alter table public.credit_package_vouchers enable row level security;
do $$
declare t text;
begin
  foreach t in array array['credit_packages','credit_package_stores','credit_package_vouchers'] loop
    if not exists (select 1 from pg_policies where schemaname='public' and tablename=t
                    and policyname='read credit packages') then
      execute format($f$create policy "read credit packages" on public.%I
                        for select to authenticated using (true)$f$, t);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 2. Catalogue management (Owner/Manager only).
-- ---------------------------------------------------------------------
create or replace function public.upsert_credit_package(
  p_id uuid, p_name text, p_customer_price numeric, p_paid_credit_amount numeric,
  p_is_active boolean default true, p_effective_from date default null,
  p_effective_to date default null, p_commission_classification text default 'own',
  p_staff_commission_enabled boolean default true, p_staff_commission_rate numeric default null,
  p_tier1_rate numeric default null, p_tier2_rate numeric default null,
  p_reward_qualifying_amount numeric default null, p_notes text default null,
  p_store_ids uuid[] default null, p_voucher_ids uuid[] default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can manage credit packages'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'A package name is required'; end if;
  if coalesce(p_customer_price,-1) < 0 then raise exception 'The customer price is required'; end if;
  if coalesce(p_paid_credit_amount,-1) < 0 then raise exception 'The paid credit amount is required'; end if;
  if p_commission_classification not in ('own','third_party') then
    raise exception 'Commission classification must be own or third_party'; end if;

  if p_id is null then
    insert into public.credit_packages (name, customer_price, paid_credit_amount, is_active,
      effective_from, effective_to, commission_classification, staff_commission_enabled,
      staff_commission_rate, tier1_rate, tier2_rate, reward_qualifying_amount, notes,
      created_by, updated_by)
    values (trim(p_name), p_customer_price, p_paid_credit_amount, coalesce(p_is_active,true),
      coalesce(p_effective_from, public.sg_today()), p_effective_to,
      p_commission_classification, coalesce(p_staff_commission_enabled,true),
      p_staff_commission_rate, p_tier1_rate, p_tier2_rate, p_reward_qualifying_amount,
      p_notes, auth.uid(), auth.uid())
    returning id into v_id;
  else
    update public.credit_packages
       set name = trim(p_name), customer_price = p_customer_price,
           paid_credit_amount = p_paid_credit_amount, is_active = coalesce(p_is_active,true),
           effective_from = coalesce(p_effective_from, effective_from), effective_to = p_effective_to,
           commission_classification = p_commission_classification,
           staff_commission_enabled = coalesce(p_staff_commission_enabled,true),
           staff_commission_rate = p_staff_commission_rate,
           tier1_rate = p_tier1_rate, tier2_rate = p_tier2_rate,
           reward_qualifying_amount = p_reward_qualifying_amount, notes = p_notes,
           updated_by = auth.uid(), updated_at = now()
     where id = p_id
    returning id into v_id;
    if v_id is null then raise exception 'Credit package not found'; end if;
  end if;

  if p_store_ids is not null then
    delete from public.credit_package_stores where package_id = v_id;
    insert into public.credit_package_stores (package_id, store_id)
    select v_id, unnest(p_store_ids) on conflict do nothing;
  end if;
  if p_voucher_ids is not null then
    delete from public.credit_package_vouchers where package_id = v_id;
    insert into public.credit_package_vouchers (package_id, voucher_id)
    select v_id, unnest(p_voucher_ids) on conflict do nothing;
  end if;

  perform public.write_audit_ex('credit_packages', v_id, 'credit_package_upserted', null,
    jsonb_build_object('name', p_name, 'price', p_customer_price,
      'credit', p_paid_credit_amount, 'classification', p_commission_classification),
    'credit', null, null);
  return v_id;
end $function$;

create or replace function public.soft_delete_credit_package(p_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $function$
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can remove credit packages'; end if;
  update public.credit_packages set deleted_at = now(), is_active = false,
         updated_by = auth.uid(), updated_at = now() where id = p_id;
  perform public.write_audit_ex('credit_packages', p_id, 'credit_package_deleted', null, null, 'credit', null, null);
end $function$;

-- Packages sellable at a store on a date.
create or replace function public.credit_packages_for_store(p_store_id uuid, p_day date default null)
returns setof public.credit_packages
language sql stable security definer set search_path to 'public' as $function$
  select p.* from public.credit_packages p
   where p.deleted_at is null and p.is_active = true
     and p.effective_from <= coalesce(p_day, public.sg_today())
     and (p.effective_to is null or p.effective_to >= coalesce(p_day, public.sg_today()))
     and (not exists (select 1 from public.credit_package_stores s where s.package_id = p.id)
          or exists (select 1 from public.credit_package_stores s
                      where s.package_id = p.id and s.store_id = p_store_id))
   order by p.customer_price
$function$;

-- ---------------------------------------------------------------------
-- 3. Credit usage restrictions.
--    A lot with restrictions may only fund the listed purpose/vouchers.
-- ---------------------------------------------------------------------
create or replace function public.credit_lot_allows(
  p_restrictions jsonb, p_purpose text, p_voucher_id uuid default null)
returns boolean language sql immutable as $function$
  select case
    -- No restrictions: spendable on anything.
    when p_restrictions is null or p_restrictions = '{}'::jsonb then true
    -- Restricted lots only fund the listed purposes...
    when not (coalesce(p_restrictions->'allowed_purposes', '[]'::jsonb) ? p_purpose) then false
    -- ...and, when a voucher list is present, only those vouchers.
    when jsonb_array_length(coalesce(p_restrictions->'allowed_voucher_ids','[]'::jsonb)) = 0 then true
    when p_voucher_id is null then false
    else coalesce(p_restrictions->'allowed_voucher_ids', '[]'::jsonb) ? p_voucher_id::text
  end
$function$;

-- Consumption becomes purpose-aware. Unrestricted lots behave as before.
-- The previous 7-argument form must be dropped first: adding the optional
-- purpose parameters would otherwise make every existing call ambiguous.
drop function if exists public.consume_customer_credit(uuid, numeric, text, uuid, uuid, text, text);

create or replace function public.consume_customer_credit(
  p_customer_id uuid, p_amount numeric, p_source_type text default 'manual_use',
  p_source_record_id uuid default null, p_store_id uuid default null,
  p_category text default null, p_note text default null,
  p_purpose text default 'general', p_voucher_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_wallet uuid; v_entry uuid; v_take numeric; v_avail numeric; v_l record;
  v_used jsonb := '[]'::jsonb;
begin
  if coalesce(p_amount,0) <= 0 then raise exception 'Amount must be greater than zero'; end if;
  v_wallet := public.ensure_customer_wallet(p_customer_id);

  select coalesce(sum(remaining_amount),0) into v_avail
    from public.customer_credit_lots
   where customer_id = p_customer_id and status = 'active'
     and (p_category is null or category = p_category)
     and public.credit_lot_allows(usage_restrictions, p_purpose, p_voucher_id);
  if v_avail < round(p_amount,2) then
    raise exception 'Insufficient credit for this purchase: % usable, % required', v_avail, p_amount;
  end if;

  v_take := round(p_amount,2);
  for v_l in
    select id, category, remaining_amount from public.customer_credit_lots
     where customer_id = p_customer_id and status = 'active' and remaining_amount > 0
       and (p_category is null or category = p_category)
       and public.credit_lot_allows(usage_restrictions, p_purpose, p_voucher_id)
     order by effective_date, created_at for update
  loop
    exit when v_take <= 0;
    declare v_use numeric := least(v_l.remaining_amount, v_take);
    begin
      insert into public.customer_credit_ledger (
        wallet_id, customer_id, entry_type, category, amount, lot_id,
        source_type, source_record_id, store_id, note, created_by)
      values (v_wallet, p_customer_id, 'use', v_l.category, v_use, v_l.id,
        p_source_type, p_source_record_id, p_store_id, p_note, auth.uid())
      returning id into v_entry;
      update public.customer_credit_lots
         set remaining_amount = remaining_amount - v_use, updated_at = now() where id = v_l.id;
      insert into public.customer_credit_allocations (ledger_entry_id, lot_id, customer_id, amount)
      values (v_entry, v_l.id, p_customer_id, v_use);
      v_used := v_used || jsonb_build_object('lot_id', v_l.id, 'category', v_l.category, 'amount', v_use);
      v_take := v_take - v_use;
    end;
  end loop;

  return jsonb_build_object('success', true, 'amount', round(p_amount,2), 'allocations', v_used,
    'balance_after', (select coalesce(sum(remaining_amount),0) from public.customer_credit_lots
                       where customer_id = p_customer_id and status = 'active'));
end $function$;

-- ---------------------------------------------------------------------
-- 4. Selling a package: issue the credit, the reward unit and the
--    commission, all from one snapshot. Called when payment completes.
-- ---------------------------------------------------------------------
create table if not exists public.credit_package_sales (
  id uuid primary key default gen_random_uuid(),
  package_id uuid not null references public.credit_packages(id),
  customer_id uuid not null references public.customers(id),
  store_id uuid references public.stores(id),
  invoice_id uuid references public.invoices(id),
  -- Permanent snapshot: later catalogue edits never change a sold package.
  package_name_snapshot text not null,
  price_snapshot numeric(12,2) not null,
  credit_snapshot numeric(12,2) not null,
  classification_snapshot text not null,
  tier1_rate_snapshot numeric(6,3),
  tier2_rate_snapshot numeric(6,3),
  staff_rate_snapshot numeric(6,3),
  reward_qualifying_snapshot numeric(12,2),
  eligible_voucher_ids uuid[] not null default '{}',
  external_paid numeric(12,2) not null default 0,
  credit_lot_id uuid references public.customer_credit_lots(id),
  reward_units integer not null default 0,
  sold_at timestamptz not null default now(),
  created_by uuid references public.profiles(id)
);
create index if not exists idx_cps_customer on public.credit_package_sales (customer_id);
alter table public.credit_package_sales enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='credit_package_sales' and policyname='read package sales') then
    create policy "read package sales" on public.credit_package_sales for select to authenticated using (true);
  end if;
end $$;

create or replace function public.issue_credit_package(
  p_package_id uuid, p_customer_id uuid, p_store_id uuid,
  p_external_paid numeric, p_invoice_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  pk public.credit_packages%rowtype;
  v_vouchers uuid[]; v_lot uuid; v_sale uuid;
  v_qual numeric; v_units integer; v_group uuid; v_deadline date;
  v_restrict jsonb; v_rule public.therapy_package_rules; i integer;
begin
  select * into pk from public.credit_packages where id = p_package_id and deleted_at is null;
  if not found then raise exception 'Credit package not found'; end if;
  if p_customer_id is null then raise exception 'A customer is required to issue package credit'; end if;

  select coalesce(array_agg(voucher_id), '{}') into v_vouchers
    from public.credit_package_vouchers where package_id = p_package_id;

  -- Package credit may only buy the package's eligible vouchers.
  v_restrict := jsonb_build_object(
    'allowed_purposes', jsonb_build_array('voucher'),
    'allowed_voucher_ids', coalesce((select jsonb_agg(v::text) from unnest(v_vouchers) v), '[]'::jsonb),
    'source', 'credit_package');

  v_lot := public.grant_customer_credit(
    p_customer_id, 'paid', pk.paid_credit_amount, 'credit_package', p_package_id, p_store_id,
    public.sg_today(), null, 'Credit package: ' || pk.name, null, null, auth.uid(), v_restrict);

  -- Reward units come from the credit value, not the money paid.
  v_rule := public.legacy_lowest_rule(p_store_id, public.sg_today());
  v_qual := coalesce(pk.reward_qualifying_amount, v_rule.qualifying_amount, 994);
  v_units := case when v_qual > 0 then floor(pk.paid_credit_amount / v_qual)::integer else 0 end;

  insert into public.credit_package_sales (
    package_id, customer_id, store_id, invoice_id, package_name_snapshot,
    price_snapshot, credit_snapshot, classification_snapshot,
    tier1_rate_snapshot, tier2_rate_snapshot, staff_rate_snapshot,
    reward_qualifying_snapshot, eligible_voucher_ids, external_paid,
    credit_lot_id, reward_units, created_by)
  values (p_package_id, p_customer_id, p_store_id, p_invoice_id, pk.name,
    pk.customer_price, pk.paid_credit_amount, pk.commission_classification,
    pk.tier1_rate, pk.tier2_rate, pk.staff_commission_rate,
    v_qual, v_vouchers, coalesce(p_external_paid,0), v_lot, v_units, auth.uid())
  returning id into v_sale;

  -- Reward units belong only to this customer. They are recorded in their own
  -- qualification group so they never mix with same-day customer qualification
  -- or Affiliate residual qualification.
  if v_units > 0 then
    v_group := md5('credit_pkg:' || v_sale::text)::uuid;
    v_deadline := public.sg_today() + coalesce(v_rule.activation_deadline_days, 365);
    for i in 1 .. v_units loop
      insert into public.therapy_entitlements (
        entitlement_no, customer_id, store_id, rule_id, package_name,
        entitlement_kind, duration_months, voucher_qty, qualifying_amount,
        qualified_value, forfeited_value, activation_deadline, status,
        created_by, qualification_group_id, earner_kind)
      values (public.next_legacy_entitlement_no(), p_customer_id, p_store_id, null,
        'Credit package reward — ' || pk.name,
        'voucher', coalesce(v_rule.duration_months, 1), 10, v_qual,
        v_qual, round(pk.paid_credit_amount - (v_units * v_qual), 2), v_deadline,
        'pending_activation', auth.uid(), v_group, 'credit_package');
    end loop;
  end if;

  perform public.write_audit_ex('credit_package_sales', v_sale, 'credit_package_issued', null,
    jsonb_build_object('package', pk.name, 'credit', pk.paid_credit_amount,
      'external_paid', p_external_paid, 'reward_units', v_units), 'credit', null, p_store_id);

  return jsonb_build_object('sale_id', v_sale, 'credit_lot_id', v_lot,
    'credit_issued', pk.paid_credit_amount, 'reward_units', v_units,
    'qualifying_amount', v_qual,
    'remainder', round(pk.paid_credit_amount - (v_units * v_qual), 2));
end $function$;

-- ---------------------------------------------------------------------
-- 5. Package reward units are excluded from both qualification engines.
--    Their spend never counts toward customer same-day units, and the credit
--    they generate is not a paid invoice, so it cannot reach the affiliate
--    residual. The entitlements themselves live in their own group.
-- ---------------------------------------------------------------------
create or replace function public.credit_package_reward_units(p_customer_id uuid)
returns table(entitlement_id uuid, entitlement_no text, package_name text,
              status text, activation_deadline date)
language sql stable security definer set search_path to 'public' as $function$
  select e.id, e.entitlement_no, e.package_name, e.status, e.activation_deadline
    from public.therapy_entitlements e
   where e.customer_id = p_customer_id and e.earner_kind = 'credit_package'
     and e.status <> 'cancelled'
   order by e.created_at
$function$;

-- ---------------------------------------------------------------------
-- 6. Commission on a package: the external payment only.
-- ---------------------------------------------------------------------
create or replace function public.earn_credit_package_commission(p_sale_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  s public.credit_package_sales%rowtype;
  v_inv public.invoices%rowtype;
  v_t1 uuid; v_t2 uuid; v_base numeric;
  v_r1 numeric; v_r2 numeric; v_a1 numeric; v_a2 numeric;
  v_ptype text;
begin
  select * into s from public.credit_package_sales where id = p_sale_id;
  if not found then raise exception 'Package sale not found'; end if;

  -- Basis: the money actually received, never the credit or free reward.
  v_base := round(coalesce(s.external_paid,0), 2);
  if v_base <= 0 then
    return jsonb_build_object('skipped', true, 'reason', 'no external payment');
  end if;
  -- Commission is always recorded against an invoice, so a sale booked without
  -- one earns nothing until it is invoiced.
  if s.invoice_id is null then
    return jsonb_build_object('skipped', true, 'reason', 'no invoice');
  end if;

  if s.invoice_id is not null then
    select * into v_inv from public.invoices where id = s.invoice_id;
  end if;

  if v_inv.affiliate_id is not null then
    select a.customer_id into v_t1 from public.customer_affiliates a where a.id = v_inv.affiliate_id;
  else
    select c.referred_by into v_t1 from public.customers c where c.id = s.customer_id;
  end if;
  if v_t1 is null or v_t1 = s.customer_id then
    return jsonb_build_object('skipped', true, 'reason', 'no eligible referrer');
  end if;
  select c.referred_by into v_t2 from public.customers c where c.id = v_t1;

  v_ptype := coalesce(s.classification_snapshot, 'own');
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

  return jsonb_build_object('basis', v_base, 'tier1', v_a1, 'tier2', coalesce(v_a2,0),
    'tier1_rate', v_r1, 'tier2_rate', v_r2);
end $function$;

-- ---------------------------------------------------------------------
-- 7. The atomic same-invoice workflow: pay the package externally, issue the
--    credit, then immediately spend it on the eligible voucher lines and
--    deduct their stock — all in one transaction. The package line itself is
--    never funded by wallet credit.
-- ---------------------------------------------------------------------
create or replace function public.sell_credit_package_with_vouchers(
  p_package_id uuid, p_customer_id uuid, p_store_id uuid,
  p_payments jsonb, p_voucher_lines jsonb default '[]'::jsonb,
  p_discount numeric default 0, p_foc_amount numeric default 0,
  p_invoice_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  pk public.credit_packages%rowtype;
  v_external numeric := 0; v_p jsonb; v_issue jsonb; v_sale uuid;
  v_line jsonb; v_vid uuid; v_qty integer; v_price numeric; v_total numeric := 0;
  v_stock integer; v_comm jsonb;
begin
  select * into pk from public.credit_packages where id = p_package_id and deleted_at is null;
  if not found then raise exception 'Credit package not found'; end if;
  if not exists (select 1 from public.credit_packages_for_store(p_store_id) x where x.id = p_package_id) then
    raise exception 'That credit package is not available at this store'; end if;

  -- 1/2. The package line must be covered by non-credit payment methods.
  for v_p in select * from jsonb_array_elements(coalesce(p_payments,'[]'::jsonb)) loop
    if coalesce(v_p->>'method','') = 'wallet_credit' or (v_p->>'use_wallet_credit')::boolean is true then
      raise exception 'A credit package cannot be paid for with wallet credit';
    end if;
    v_external := v_external + coalesce((v_p->>'amount')::numeric, 0);
  end loop;

  -- 3. What must be covered after a discount and any FOC portion.
  v_total := greatest(round(pk.customer_price - coalesce(p_discount,0) - coalesce(p_foc_amount,0), 2), 0);
  if round(v_external,2) < v_total then
    raise exception 'The credit package line needs % but only % was paid externally', v_total, round(v_external,2);
  end if;

  -- 4. Payment confirmed: create the Paid Credit and the reward unit(s).
  v_issue := public.issue_credit_package(p_package_id, p_customer_id, p_store_id,
                                         round(v_external,2), p_invoice_id);
  v_sale := (v_issue->>'sale_id')::uuid;

  -- 5/6. Immediately spend the new credit on the eligible voucher lines and
  --      deduct their stock.
  for v_line in select * from jsonb_array_elements(coalesce(p_voucher_lines,'[]'::jsonb)) loop
    v_vid := (v_line->>'voucher_id')::uuid;
    v_qty := coalesce((v_line->>'quantity')::integer, 0);
    if v_qty <= 0 then continue; end if;
    if not exists (select 1 from public.credit_package_vouchers
                    where package_id = p_package_id and voucher_id = v_vid) then
      raise exception 'Voucher "%" is not eligible for this credit package',
        (select name from public.vouchers where id = v_vid);
    end if;

    v_price := coalesce((public.voucher_price_for(p_store_id, v_vid, true)->>'price')::numeric, 0);
    if v_price <= 0 then
      raise exception 'Voucher "%" has no price at this store',
        (select name from public.vouchers where id = v_vid); end if;

    perform public.consume_customer_credit(p_customer_id, round(v_price * v_qty, 2),
      'credit_package_voucher', v_sale, p_store_id, 'paid',
      'Redeemed against ' || pk.name, 'voucher', v_vid);

    if exists (select 1 from public.vouchers where id = v_vid and qty_type <> 'unlimited') then
      select current_qty into v_stock from public.voucher_store_stock
       where voucher_id = v_vid and store_id = p_store_id for update;
      if coalesce(v_stock,0) < v_qty then
        raise exception 'Not enough stock of "%" at this store (% available)',
          (select name from public.vouchers where id = v_vid), coalesce(v_stock,0); end if;
      update public.voucher_store_stock set current_qty = current_qty - v_qty, updated_at = now()
       where voucher_id = v_vid and store_id = p_store_id;
    end if;
  end loop;

  -- 7. Commission on the external payment only.
  v_comm := public.earn_credit_package_commission(v_sale);

  return v_issue || jsonb_build_object('external_paid', round(v_external,2), 'commission', v_comm);
end $function$;

notify pgrst, 'reload schema';
