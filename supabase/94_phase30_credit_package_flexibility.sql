-- =====================================================================
-- ENERGIA — PHASE 30: FLEXIBLE CREDIT PACKAGES AND BONUS CREDIT
--
-- A Credit Package now declares WHICH CATEGORIES its Paid Credit may buy, and
-- may issue Bonus Credit as a fixed amount or a percentage of the package
-- price.
--
-- Extends the existing wallet machinery rather than duplicating it:
--   * usage_restrictions.allowed_purposes already drives credit_lot_allows(),
--     so a category set is expressed in that same shape;
--   * grant_customer_credit / allocate_invoice_wallet_credit are unchanged in
--     signature.
--
-- Existing packages migrate as VOUCHER-ONLY with a $0 fixed bonus, which is
-- exactly what they do today — so no live package changes behaviour.
--
-- Additive and idempotent. Run AFTER 93.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. The seven purchasable categories.
--    Kept as explicit booleans rather than an array so a check constraint,
--    an index or a report can reference one directly.
-- ---------------------------------------------------------------------
alter table public.credit_packages add column if not exists allow_product          boolean not null default false;
alter table public.credit_packages add column if not exists allow_voucher          boolean not null default false;
alter table public.credit_packages add column if not exists allow_promotion        boolean not null default false;
alter table public.credit_packages add column if not exists allow_therapy          boolean not null default false;
alter table public.credit_packages add column if not exists allow_rental           boolean not null default false;
alter table public.credit_packages add column if not exists allow_event            boolean not null default false;
alter table public.credit_packages add column if not exists allow_special_product  boolean not null default false;

-- Bonus Credit configuration.
alter table public.credit_packages add column if not exists bonus_enabled boolean not null default false;
alter table public.credit_packages add column if not exists bonus_mode text not null default 'fixed';
alter table public.credit_packages add column if not exists bonus_value numeric(14,2) not null default 0;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'credit_packages_bonus_mode_check') then
    alter table public.credit_packages
      add constraint credit_packages_bonus_mode_check check (bonus_mode in ('fixed','percentage'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'credit_packages_bonus_value_check') then
    alter table public.credit_packages
      add constraint credit_packages_bonus_value_check check (bonus_value >= 0);
  end if;
end $$;

-- Existing packages behave exactly as before: vouchers only, no bonus. The
-- guard means a re-run cannot undo an Owner's later edits.
update public.credit_packages
   set allow_voucher = true
 where allow_product = false and allow_voucher = false and allow_promotion = false
   and allow_therapy = false and allow_rental = false and allow_event = false
   and allow_special_product = false;

-- ---------------------------------------------------------------------
-- 2. Category set -> the allowed_purposes shape credit_lot_allows() reads.
-- ---------------------------------------------------------------------
create or replace function public.credit_package_purposes(p_package_id uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $function$
  select coalesce(jsonb_agg(x.purpose), '[]'::jsonb)
    from public.credit_packages pk,
    lateral (values
      ('product',         pk.allow_product),
      ('voucher',         pk.allow_voucher),
      ('promotion',       pk.allow_promotion),
      ('therapy',         pk.allow_therapy),
      ('rental',          pk.allow_rental),
      ('event',           pk.allow_event),
      ('special_product', pk.allow_special_product)
    ) as x(purpose, enabled)
   where pk.id = p_package_id and x.enabled
$function$;

-- What Bonus Credit may buy: everything ordinary, but never another credit
-- product — that would let a bundle mint further credit from itself.
create or replace function public.bonus_credit_purposes()
returns jsonb language sql immutable as $function$
  select '["product","voucher","promotion","therapy","rental","event","special_product"]'::jsonb
$function$;

-- ---------------------------------------------------------------------
-- 3. The bonus a package issues, from its own configuration.
--    Percentage is taken from the CUSTOMER PRICE, not the paid credit.
-- ---------------------------------------------------------------------
create or replace function public.credit_package_bonus_amount(p_package_id uuid)
returns numeric language sql stable security definer set search_path to 'public' as $function$
  select case
    when not coalesce(pk.bonus_enabled, false) then 0::numeric
    when pk.bonus_mode = 'percentage'
      then round(coalesce(pk.customer_price,0) * coalesce(pk.bonus_value,0) / 100.0, 2)
    else round(coalesce(pk.bonus_value,0), 2)
  end
  from public.credit_packages pk where pk.id = p_package_id
$function$;

-- ---------------------------------------------------------------------
-- 4. Rentals and events become spendable purposes.
-- ---------------------------------------------------------------------
create or replace function public.invoice_line_credit_purpose(p_line_kind text)
returns text language sql immutable as $function$
  select case p_line_kind
    when 'product' then 'product'
    when 'voucher' then 'voucher'
    when 'promotion' then 'promotion'
    when 'therapy' then 'therapy'
    when 'rental' then 'rental'
    when 'event' then 'event'
    when 'special_product' then 'special_product'
    when 'credit_package' then 'credit_package'
    when 'premium_bundle' then 'premium_bundle'
    else p_line_kind end
$function$;

-- ---------------------------------------------------------------------
-- 5. Issuing a package: paid credit restricted to its categories, bonus
--    credit alongside it, reward units from the CUSTOMER PRICE.
-- ---------------------------------------------------------------------
create or replace function public.issue_credit_package(
  p_package_id uuid, p_customer_id uuid, p_store_id uuid,
  p_external_paid numeric, p_invoice_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  pk public.credit_packages%rowtype;
  v_vouchers uuid[]; v_lot uuid; v_bonus_lot uuid; v_sale uuid;
  v_qual numeric; v_units integer; v_group uuid; v_deadline date;
  v_restrict jsonb; v_rule public.therapy_package_rules; i integer;
  v_bonus numeric;
begin
  select * into pk from public.credit_packages where id = p_package_id and deleted_at is null;
  if not found then raise exception 'Credit package not found'; end if;
  if p_customer_id is null then raise exception 'A customer is required to issue package credit'; end if;

  select coalesce(array_agg(voucher_id), '{}') into v_vouchers
    from public.credit_package_vouchers where package_id = p_package_id;

  -- The category set is SNAPSHOTTED here. Editing the package later cannot
  -- change what already-issued credit is allowed to buy.
  v_restrict := jsonb_build_object(
    'allowed_purposes', public.credit_package_purposes(p_package_id),
    'source', 'credit_package');

  -- Enabling the voucher category allows every active sellable voucher, so no
  -- voucher id list is attached; an explicit list is only kept when the
  -- package was configured with one.
  if array_length(v_vouchers, 1) is not null and not pk.allow_voucher then
    v_restrict := v_restrict || jsonb_build_object(
      'allowed_voucher_ids', (select jsonb_agg(v::text) from unnest(v_vouchers) v));
  end if;

  v_lot := public.grant_customer_credit(
    p_customer_id, 'paid', pk.paid_credit_amount, 'credit_package', p_package_id, p_store_id,
    public.sg_today(), null, 'Credit package: ' || pk.name, null, null, auth.uid(), v_restrict);

  -- Bonus Credit, spendable on everything ordinary.
  v_bonus := public.credit_package_bonus_amount(p_package_id);
  if v_bonus > 0 then
    v_bonus_lot := public.grant_customer_credit(
      p_customer_id, 'bonus', v_bonus, 'credit_package', p_package_id, p_store_id,
      public.sg_today(), null, 'Credit package bonus: ' || pk.name, null, null, auth.uid(),
      jsonb_build_object('allowed_purposes', public.bonus_credit_purposes(),
                         'source', 'credit_package_bonus'));
  end if;

  v_rule := public.legacy_lowest_rule(p_store_id, public.sg_today());
  v_qual := coalesce(pk.reward_qualifying_amount, v_rule.qualifying_amount, 994);

  -- Reward units come from the CUSTOMER PRICE, not the credit issued: the
  -- customer is rewarded for what they spent, not for the credit they hold.
  v_units := case
    when not coalesce(pk.grants_reward, false) then 0
    when v_qual > 0 then floor(coalesce(pk.customer_price,0) / v_qual)::integer
    else 0 end;

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
        v_qual, round(coalesce(pk.customer_price,0) - (v_units * v_qual), 2), v_deadline,
        'pending_activation', auth.uid(), v_group, 'credit_package');
    end loop;
  end if;

  perform public.write_audit_ex('credit_package_sales', v_sale, 'credit_package_issued', null,
    jsonb_build_object('package', pk.name, 'credit', pk.paid_credit_amount,
      'bonus', v_bonus, 'external_paid', p_external_paid, 'reward_units', v_units,
      'purposes', public.credit_package_purposes(p_package_id)), 'credit', null, p_store_id);

  return jsonb_build_object('sale_id', v_sale, 'credit_lot_id', v_lot,
    'bonus_lot_id', v_bonus_lot, 'credit_issued', pk.paid_credit_amount,
    'bonus_issued', v_bonus, 'reward_units', v_units,
    'grants_reward', coalesce(pk.grants_reward,false),
    'qualifying_amount', v_qual,
    'remainder', case when v_units > 0
                 then round(coalesce(pk.customer_price,0) - (v_units * v_qual), 2) else 0 end);
end $function$;

-- ---------------------------------------------------------------------
-- 6. Managing a package. The old signature is dropped first, or existing
--    calls become ambiguous.
-- ---------------------------------------------------------------------
drop function if exists public.upsert_credit_package(
  uuid, text, numeric, numeric, boolean, date, date, text, boolean, numeric,
  numeric, numeric, numeric, text, uuid[], uuid[]);

create or replace function public.upsert_credit_package(
  p_id uuid, p_name text, p_customer_price numeric, p_paid_credit_amount numeric,
  p_is_active boolean default true, p_effective_from date default null,
  p_effective_to date default null, p_commission_classification text default 'own',
  p_staff_commission_enabled boolean default true, p_staff_commission_rate numeric default null,
  p_tier1_rate numeric default null, p_tier2_rate numeric default null,
  p_reward_qualifying_amount numeric default null, p_notes text default null,
  p_store_ids uuid[] default null, p_voucher_ids uuid[] default null,
  p_allow_product boolean default null, p_allow_voucher boolean default null,
  p_allow_promotion boolean default null, p_allow_therapy boolean default null,
  p_allow_rental boolean default null, p_allow_event boolean default null,
  p_allow_special_product boolean default null,
  p_bonus_enabled boolean default null, p_bonus_mode text default null,
  p_bonus_value numeric default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid; v_s uuid; v_v uuid;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can manage credit packages'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'A package name is required'; end if;
  if coalesce(p_customer_price,0) <= 0 then raise exception 'The customer price must be greater than zero'; end if;
  if coalesce(p_paid_credit_amount,0) <= 0 then raise exception 'The paid credit must be greater than zero'; end if;
  if p_bonus_mode is not null and p_bonus_mode not in ('fixed','percentage') then
    raise exception 'The bonus mode must be fixed or percentage'; end if;
  if coalesce(p_bonus_value, 0) < 0 then raise exception 'The bonus value cannot be negative'; end if;

  if p_id is null then
    insert into public.credit_packages (
      name, customer_price, paid_credit_amount, is_active, effective_from, effective_to,
      commission_classification, staff_commission_enabled, staff_commission_rate,
      tier1_rate, tier2_rate, reward_qualifying_amount, notes, created_by,
      allow_product, allow_voucher, allow_promotion, allow_therapy,
      allow_rental, allow_event, allow_special_product,
      bonus_enabled, bonus_mode, bonus_value)
    values (trim(p_name), p_customer_price, p_paid_credit_amount, coalesce(p_is_active,true),
      p_effective_from, p_effective_to, coalesce(p_commission_classification,'own'),
      coalesce(p_staff_commission_enabled,true), p_staff_commission_rate,
      p_tier1_rate, p_tier2_rate, p_reward_qualifying_amount, p_notes, auth.uid(),
      -- A brand-new package with no categories chosen defaults to vouchers,
      -- matching how every package behaved before this phase.
      coalesce(p_allow_product,false),
      coalesce(p_allow_voucher, not coalesce(p_allow_product or p_allow_promotion
        or p_allow_therapy or p_allow_rental or p_allow_event or p_allow_special_product, false)),
      coalesce(p_allow_promotion,false), coalesce(p_allow_therapy,false),
      coalesce(p_allow_rental,false), coalesce(p_allow_event,false),
      coalesce(p_allow_special_product,false),
      coalesce(p_bonus_enabled,false), coalesce(p_bonus_mode,'fixed'), coalesce(p_bonus_value,0))
    returning id into v_id;
  else
    update public.credit_packages set
      name = trim(p_name), customer_price = p_customer_price,
      paid_credit_amount = p_paid_credit_amount, is_active = coalesce(p_is_active, is_active),
      effective_from = p_effective_from, effective_to = p_effective_to,
      commission_classification = coalesce(p_commission_classification, commission_classification),
      staff_commission_enabled = coalesce(p_staff_commission_enabled, staff_commission_enabled),
      staff_commission_rate = p_staff_commission_rate,
      tier1_rate = p_tier1_rate, tier2_rate = p_tier2_rate,
      reward_qualifying_amount = p_reward_qualifying_amount, notes = p_notes,
      allow_product         = coalesce(p_allow_product, allow_product),
      allow_voucher         = coalesce(p_allow_voucher, allow_voucher),
      allow_promotion       = coalesce(p_allow_promotion, allow_promotion),
      allow_therapy         = coalesce(p_allow_therapy, allow_therapy),
      allow_rental          = coalesce(p_allow_rental, allow_rental),
      allow_event           = coalesce(p_allow_event, allow_event),
      allow_special_product = coalesce(p_allow_special_product, allow_special_product),
      bonus_enabled = coalesce(p_bonus_enabled, bonus_enabled),
      bonus_mode    = coalesce(p_bonus_mode, bonus_mode),
      bonus_value   = coalesce(p_bonus_value, bonus_value),
      updated_by = auth.uid(), updated_at = now()
    where id = p_id returning id into v_id;
    if v_id is null then raise exception 'Credit package not found'; end if;
  end if;

  if p_store_ids is not null then
    delete from public.credit_package_stores where package_id = v_id;
    foreach v_s in array p_store_ids loop
      insert into public.credit_package_stores (package_id, store_id) values (v_id, v_s)
      on conflict do nothing;
    end loop;
  end if;
  if p_voucher_ids is not null then
    delete from public.credit_package_vouchers where package_id = v_id;
    foreach v_v in array p_voucher_ids loop
      insert into public.credit_package_vouchers (package_id, voucher_id) values (v_id, v_v)
      on conflict do nothing;
    end loop;
  end if;

  perform public.write_audit_ex('credit_packages', v_id,
    case when p_id is null then 'credit_package_created' else 'credit_package_updated' end,
    null, jsonb_build_object('name', trim(p_name)), 'catalogue', null, null);
  return v_id;
end $function$;

-- ---------------------------------------------------------------------
-- 7. Legacy qualification counts EXTERNAL payment only.
--    Wallet credit of every category is excluded, as are the credit products
--    themselves. The external share is worked out per line from the recorded
--    allocations, so a mixed payment qualifies only for the cash portion.
-- ---------------------------------------------------------------------
create or replace function public.invoice_qualifying_paid(p_invoice_id uuid)
returns numeric language sql stable security definer set search_path to 'public' as $function$
  with inv as (
    select i.paid_amount, i.subtotal from public.invoices i where i.id = p_invoice_id
  ),
  -- Lines that can never qualify: buying credit is not spending.
  excluded_lines as (
    select coalesce(sum(ii.line_total), 0) as amt
      from public.invoice_items ii
     where ii.invoice_id = p_invoice_id
       and ii.line_kind in ('credit_package','premium_bundle')
  ),
  -- Every wallet category funds nothing qualifying.
  wallet_funded as (
    select coalesce(sum(a.amount - coalesce(a.reversed_amount,0)), 0) as amt
      from public.invoice_line_credit_allocations a
     where a.invoice_id = p_invoice_id
  ),
  eligible as (
    select greatest(coalesce(inv.subtotal,0) - excluded_lines.amt, 0) as gross
      from inv, excluded_lines
  )
  select greatest(round(
           least(
             -- The paid amount attributable to eligible lines...
             coalesce(inv.paid_amount, 0)
               * case when coalesce(inv.subtotal,0) > 0
                      then eligible.gross / inv.subtotal else 1 end,
             -- ...less anything the wallet paid for.
             greatest(eligible.gross - wallet_funded.amt, 0)
           ), 2), 0)
    from inv, eligible, wallet_funded
$function$;

notify pgrst, 'reload schema';
