-- =====================================================================
-- ENERGIA — PHASE 25 FIX: WHY AN AFFILIATE EARNED NO LEGACY THERAPY
--
-- Three invoices on one day for three different customers, all crediting the
-- same Affiliate (S$564 + S$470 + S$564 = S$1,598), produced no Affiliate
-- Legacy entitlement. Two defects in the Phase 25 work caused it.
--
--   1. NO AFFILIATE RULE COULD EVER BE CREATED. upsert_legacy_rule() — the
--      only path the Qualification tab uses — never set applies_to, so every
--      rule made in the app defaulted to 'customer'. affiliate_legacy_rule()
--      therefore found nothing and awarded 0 units, silently. (The "10
--      Vouchers" rule is a CUSTOMER rule, which is why LEG-0000001 is a
--      customer entitlement with a voucher reward.) upsert_legacy_rule now
--      takes p_applies_to.
--
--   2. NO AFFILIATE SNAPSHOT WAS STORED FOR DIRECT REFERRALS. Since Phase 23
--      the invoice screen *displays* the customer's direct referrer as the
--      affiliate who will be credited, but invoices.affiliate_id is only
--      written when someone actively changes the dropdown. With affiliate_id
--      null, snapshot_invoice_affiliate() stored no snapshot, so the residual
--      had nowhere to go. The specification is headed "Direct Referrals Only"
--      and excludes Tier 2 downline sales, so a DIRECT (Tier 1) referrer now
--      counts: the snapshot is the explicitly chosen Affiliate when there is
--      one, otherwise the customer's direct referrer if that person is an
--      active Affiliate. Tier 2 still never qualifies.
--
--   3. It was impossible to see why nothing was awarded.
--      affiliate_legacy_diagnose() now explains it.
--
-- Additive and idempotent. Run AFTER 74.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Rules can be created for either earner from the app.
--    The 10-argument form is dropped first: adding an optional parameter
--    would otherwise make every existing call ambiguous.
-- ---------------------------------------------------------------------
drop function if exists public.upsert_legacy_rule(uuid, uuid, text, numeric, text, integer, integer, integer, boolean, date);

create or replace function public.upsert_legacy_rule(
  p_id uuid, p_store_id uuid, p_name text, p_qualifying_amount numeric,
  p_entitlement_kind text, p_duration_months integer, p_voucher_qty integer,
  p_activation_deadline_days integer, p_is_active boolean,
  p_effective_date date default null, p_applies_to text default 'customer')
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_id uuid; v_scope text := coalesce(nullif(trim(p_applies_to),''),'customer');
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can edit qualification rules'; end if;
  if coalesce(p_qualifying_amount,0) <= 0 then raise exception 'Qualifying amount must be greater than zero'; end if;
  if v_scope not in ('customer','affiliate') then raise exception 'Rule scope must be customer or affiliate'; end if;
  if p_entitlement_kind not in ('unlimited','voucher') then raise exception 'Entitlement kind must be unlimited or voucher'; end if;
  if v_scope = 'affiliate' and p_entitlement_kind <> 'voucher' then
    raise exception 'An Affiliate reward can only be vouchers'; end if;
  if p_entitlement_kind = 'voucher' and coalesce(p_voucher_qty,0) <= 0 then
    raise exception 'Voucher reward needs a voucher quantity'; end if;

  if p_id is null then
    insert into public.therapy_package_rules (store_id, name, qualifying_amount, entitlement_kind,
      duration_months, voucher_qty, activation_deadline_days, is_active, effective_date, applies_to)
    values (p_store_id, coalesce(nullif(trim(p_name),''),'Legacy Qualification'), p_qualifying_amount,
      p_entitlement_kind, p_duration_months, p_voucher_qty, coalesce(p_activation_deadline_days,365),
      coalesce(p_is_active,true), coalesce(p_effective_date, public.sg_today()), v_scope)
    returning id into v_id;
  else
    update public.therapy_package_rules
       set store_id = p_store_id, name = coalesce(nullif(trim(p_name),''),'Legacy Qualification'),
           qualifying_amount = p_qualifying_amount, entitlement_kind = p_entitlement_kind,
           duration_months = p_duration_months, voucher_qty = p_voucher_qty,
           activation_deadline_days = coalesce(p_activation_deadline_days,365),
           is_active = coalesce(p_is_active,true),
           effective_date = coalesce(p_effective_date, effective_date),
           applies_to = v_scope, updated_at = now()
     where id = p_id
    returning id into v_id;
  end if;

  perform public.write_audit_ex('therapy_package_rules', v_id, 'legacy_rule_upserted',
    null, jsonb_build_object('name', p_name, 'qualifying_amount', p_qualifying_amount,
      'kind', p_entitlement_kind, 'store', p_store_id, 'applies_to', v_scope,
      'effective_date', p_effective_date), 'therapy', null, p_store_id);
  return v_id;
end $function$;

-- ---------------------------------------------------------------------
-- 2. The snapshot honours direct referrals.
--    Explicit choice wins; otherwise the customer's DIRECT referrer counts
--    when they are an active Affiliate. Tier 2 never qualifies.
-- ---------------------------------------------------------------------
create or replace function public.snapshot_invoice_affiliate(p_invoice_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare
  v_inv public.invoices%rowtype; v_person uuid; v_active boolean := false;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return; end if;

  if v_inv.affiliate_id is not null then
    -- Explicitly selected on the invoice.
    select a.customer_id,
           (a.status = 'active' and not coalesce(a.manually_suspended,false) and a.deleted_at is null)
      into v_person, v_active
      from public.customer_affiliates a where a.id = v_inv.affiliate_id;
  else
    -- The customer's DIRECT referrer (Tier 1). Their own referrer (Tier 2) is
    -- deliberately never considered.
    select c.referred_by into v_person from public.customers c where c.id = v_inv.customer_id;
    if v_person is not null then
      select (a.status = 'active' and not coalesce(a.manually_suspended,false) and a.deleted_at is null)
        into v_active
        from public.customer_affiliates a where a.customer_id = v_person;
      -- A referrer who is not a registered affiliate earns no Legacy residual.
      if v_active is null then v_active := false; end if;
    end if;
  end if;

  -- A customer never generates Legacy residual for themselves.
  if v_person is not null and v_person = v_inv.customer_id then
    v_person := null; v_active := false;
  end if;

  update public.invoices
     set affiliate_snapshot_customer_id = case when coalesce(v_active,false) then v_person else null end,
         affiliate_active_on_paid = coalesce(v_active,false)
   where id = p_invoice_id;
end $function$;

-- ---------------------------------------------------------------------
-- 3. Fill in snapshots that were never stored, without disturbing genuine
--    historical ones (a later suspension must not rewrite history).
-- ---------------------------------------------------------------------
create or replace function public.backfill_affiliate_snapshots(p_store_id uuid default null)
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare v_r record; v_n integer := 0;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can backfill affiliate snapshots'; end if;
  for v_r in
    select id from public.invoices
     where status in ('paid','partially_paid') and coalesce(paid_amount,0) > 0
       and paid_at is not null
       and affiliate_snapshot_customer_id is null
       and (p_store_id is null or store_id = p_store_id)
  loop
    perform public.snapshot_invoice_affiliate(v_r.id);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;

-- The overall backfill now repairs missing snapshots before it recomputes.
create or replace function public.backfill_legacy_qualification(
  p_from date default null, p_to date default null, p_store_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_r record; v_res jsonb;
  v_days integer := 0; v_created integer := 0; v_cancelled integer := 0; v_aff integer := 0;
  v_snap integer := 0;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can run the qualification backfill';
  end if;

  v_snap := public.backfill_affiliate_snapshots(p_store_id);

  for v_r in
    select i.customer_id, i.store_id, (i.paid_at at time zone 'Asia/Singapore')::date as day
      from public.invoices i
     where i.customer_id is not null and i.store_id is not null
       and i.status in ('paid','partially_paid') and coalesce(i.paid_amount,0) > 0
       and i.paid_at is not null
       and (p_store_id is null or i.store_id = p_store_id)
       and (p_from is null or (i.paid_at at time zone 'Asia/Singapore')::date >= p_from)
       and (p_to   is null or (i.paid_at at time zone 'Asia/Singapore')::date <= p_to)
     group by 1,2,3 order by 3
  loop
    v_res := public.recompute_legacy_qualification(v_r.customer_id, v_r.store_id, v_r.day);
    v_days := v_days + 1;
    v_created := v_created + coalesce((v_res->>'created')::integer, 0);
    v_cancelled := v_cancelled + coalesce((v_res->>'cancelled')::integer, 0);
  end loop;

  for v_r in
    select distinct i.affiliate_snapshot_customer_id as aff,
           (i.paid_at at time zone 'Asia/Singapore')::date as day
      from public.invoices i
     where i.affiliate_snapshot_customer_id is not null
       and coalesce(i.affiliate_active_on_paid,false)
       and i.status in ('paid','partially_paid') and coalesce(i.paid_amount,0) > 0
       and i.paid_at is not null
       and (p_from is null or (i.paid_at at time zone 'Asia/Singapore')::date >= p_from)
       and (p_to   is null or (i.paid_at at time zone 'Asia/Singapore')::date <= p_to)
  loop
    v_res := public.recompute_affiliate_legacy_qualification(v_r.aff, v_r.day);
    v_aff := v_aff + coalesce((v_res->>'created')::integer, 0);
  end loop;

  return jsonb_build_object('days_evaluated', v_days, 'created', v_created + v_aff,
    'customer_created', v_created, 'affiliate_created', v_aff,
    'cancelled', v_cancelled, 'snapshots_filled', v_snap);
end $function$;

-- ---------------------------------------------------------------------
-- 4. Why did this Affiliate earn nothing on this date?
-- ---------------------------------------------------------------------
create or replace function public.affiliate_legacy_diagnose(
  p_affiliate_customer_id uuid, p_day date default null)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare
  v_day date := coalesce(p_day, public.sg_today());
  v_residual numeric; v_invoices integer; v_gross numeric;
  v_rules integer; v_rule public.therapy_package_rules; v_store uuid;
  v_units integer; v_have integer; v_group uuid; v_reason text;
  v_is_aff boolean;
begin
  select exists (select 1 from public.customer_affiliates a
                  where a.customer_id = p_affiliate_customer_id and a.deleted_at is null)
    into v_is_aff;

  select count(*), coalesce(sum(i.paid_amount),0) into v_invoices, v_gross
    from public.invoices i
   where i.affiliate_snapshot_customer_id = p_affiliate_customer_id
     and coalesce(i.affiliate_active_on_paid,false)
     and i.status in ('paid','partially_paid') and coalesce(i.paid_amount,0) > 0
     and (i.paid_at at time zone 'Asia/Singapore')::date = v_day;

  v_residual := public.affiliate_residual_for_day(p_affiliate_customer_id, v_day);

  select i.store_id into v_store
    from public.invoices i
   where i.affiliate_snapshot_customer_id = p_affiliate_customer_id
     and coalesce(i.affiliate_active_on_paid,false)
     and i.status in ('paid','partially_paid') and coalesce(i.paid_amount,0) > 0
     and (i.paid_at at time zone 'Asia/Singapore')::date = v_day
   group by i.store_id order by sum(i.paid_amount) desc limit 1;

  select count(*) into v_rules from public.therapy_package_rules
   where is_active = true and deleted_at is null
     and coalesce(applies_to,'customer') = 'affiliate' and coalesce(qualifying_amount,0) > 0;
  v_rule := public.affiliate_legacy_rule(v_store, v_day);

  v_units := case when v_rule.id is null then 0
                  else floor(v_residual / v_rule.qualifying_amount)::integer end;
  v_group := md5('legacy_aff:' || p_affiliate_customer_id::text || ':' || v_day::text)::uuid;
  select count(*) into v_have from public.therapy_entitlements
   where qualification_group_id = v_group and status <> 'cancelled';

  if not coalesce(v_is_aff,false) then
    v_reason := 'This customer is not a registered Affiliate.';
  elsif v_invoices = 0 then
    v_reason := 'No paid invoices on ' || v_day || ' carry this Affiliate as an eligible snapshot. '
      || 'Either the Affiliate was not selected on the invoice and the customer has no direct referrer, '
      || 'or the Affiliate was not active when the invoice was paid.';
  elsif v_rules = 0 then
    v_reason := 'No active AFFILIATE qualification rule exists. Add one under Therapy → Qualification '
      || 'with Rewards set to "Affiliate" (vouchers only).';
  elsif v_rule.id is null then
    v_reason := 'An Affiliate rule exists but none is effective on ' || v_day
      || ' for this store. Backdate its effective date.';
  elsif v_residual <= 0 then
    v_reason := 'Contributing sales totalled ' || v_gross
      || ' but the customers consumed all of it on their own Legacy units, leaving no residual.';
  elsif v_units = 0 then
    v_reason := 'Residual of ' || v_residual || ' has not reached the Affiliate threshold of '
      || v_rule.qualifying_amount || ' (short by ' || round(v_rule.qualifying_amount - v_residual, 2) || ').';
  elsif v_have = 0 then
    v_reason := 'This date qualifies but has not been computed yet — run Re-check paid days.';
  else
    v_reason := 'Qualified.';
  end if;

  return jsonb_build_object(
    'day', v_day, 'is_affiliate', coalesce(v_is_aff,false),
    'contributing_invoices', v_invoices, 'contributing_gross', v_gross,
    'affiliate_residual', v_residual,
    'affiliate_rules_configured', v_rules,
    'qualifying_amount', v_rule.qualifying_amount,
    'units_target', v_units, 'entitlements_existing', v_have,
    'reason', v_reason);
end $function$;

notify pgrst, 'reload schema';
