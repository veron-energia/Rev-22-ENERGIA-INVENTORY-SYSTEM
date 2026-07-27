-- =====================================================================
-- ENERGIA — PHASE 25: AFFILIATE SAME-DAY RESIDUAL QUALIFICATION
--
-- After a customer's own Legacy units are reserved, whatever spend is left
-- over on that Singapore day flows to the Affiliate that was snapshotted on
-- each paid invoice. An Affiliate earns one unit per full qualifying amount
-- of residual, aggregated across all of their direct customers and all
-- stores for that date. The Affiliate reward is vouchers only.
--
-- Order of calculation, per customer and Singapore date:
--   1. total eligible spend for the customer that day
--   2. customer units = floor(spend / customer qualifying amount)
--   3. consumed = units * qualifying amount
--   4. customer residual = spend - consumed
--   5. each invoice's residual share = paid_i * (residual / spend)
--   6. residual shares are attributed to that invoice's Affiliate snapshot
--   7. per Affiliate per date, units = floor(total residual / amount)
--   8. the remainder is forfeited at the end of the day
--
-- The outcome never depends on the order anything is claimed: it is always
-- recomputed from the invoices themselves.
--
-- Additive and idempotent. Run AFTER 73.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Rules are now scoped to who they reward.
-- ---------------------------------------------------------------------
alter table public.therapy_package_rules
  add column if not exists applies_to text not null default 'customer';
-- Affiliate residual aggregates across every store, so a rule must be able to
-- apply globally (store_id null) rather than to one store.
alter table public.therapy_package_rules alter column store_id drop not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'therapy_package_rules_applies_to_check') then
    alter table public.therapy_package_rules
      add constraint therapy_package_rules_applies_to_check check (applies_to in ('customer','affiliate'));
  end if;
end $$;

-- Which entitlements were earned as an Affiliate rather than as a customer.
alter table public.therapy_entitlements
  add column if not exists earner_kind text not null default 'customer';
alter table public.therapy_entitlements
  add column if not exists residual_value numeric;

-- ---------------------------------------------------------------------
-- 2. Affiliate eligibility is snapshotted when the invoice is paid.
--    A later suspension never changes an already-qualified historical sale.
-- ---------------------------------------------------------------------
alter table public.invoices
  add column if not exists affiliate_snapshot_customer_id uuid references public.customers(id);
alter table public.invoices
  add column if not exists affiliate_active_on_paid boolean;

create or replace function public.snapshot_invoice_affiliate(p_invoice_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare v_inv public.invoices%rowtype; v_person uuid; v_active boolean := false;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return; end if;
  -- Only the Affiliate directly selected on the invoice counts. A customer's
  -- referrer is NOT an affiliate snapshot for Legacy purposes.
  if v_inv.affiliate_id is null then
    update public.invoices
       set affiliate_snapshot_customer_id = null, affiliate_active_on_paid = false
     where id = p_invoice_id;
    return;
  end if;
  select a.customer_id,
         (a.status = 'active' and not coalesce(a.manually_suspended,false) and a.deleted_at is null)
    into v_person, v_active
    from public.customer_affiliates a where a.id = v_inv.affiliate_id;
  update public.invoices
     set affiliate_snapshot_customer_id = v_person,
         affiliate_active_on_paid = coalesce(v_active,false)
   where id = p_invoice_id;
end $function$;

-- ---------------------------------------------------------------------
-- 3. Rule lookups become scope-aware.
-- ---------------------------------------------------------------------
create or replace function public.legacy_rule_for_amount(
  p_store_id uuid, p_day date, p_amount numeric)
returns public.therapy_package_rules
language sql stable security definer set search_path to 'public' as $function$
  select r.* from public.therapy_package_rules r
   where r.is_active = true and r.deleted_at is null
     and coalesce(r.applies_to,'customer') = 'customer'
     and coalesce(r.qualifying_amount, 0) > 0
     and (r.store_id = p_store_id or r.store_id is null)
     and r.effective_date <= p_day
     and r.qualifying_amount <= coalesce(p_amount, 0)
   order by r.qualifying_amount desc, (r.store_id = p_store_id) desc,
            r.effective_date desc, r.created_at desc
   limit 1
$function$;

create or replace function public.legacy_lowest_rule(p_store_id uuid, p_day date)
returns public.therapy_package_rules
language sql stable security definer set search_path to 'public' as $function$
  select r.* from public.therapy_package_rules r
   where r.is_active = true and r.deleted_at is null
     and coalesce(r.applies_to,'customer') = 'customer'
     and coalesce(r.qualifying_amount, 0) > 0
     and (r.store_id = p_store_id or r.store_id is null)
     and r.effective_date <= p_day
   order by r.qualifying_amount asc, (r.store_id = p_store_id) desc,
            r.effective_date desc, r.created_at desc
   limit 1
$function$;

-- The Affiliate rule (vouchers only). Store-specific preferred, else global.
create or replace function public.affiliate_legacy_rule(p_store_id uuid, p_day date)
returns public.therapy_package_rules
language sql stable security definer set search_path to 'public' as $function$
  select r.* from public.therapy_package_rules r
   where r.is_active = true and r.deleted_at is null
     and coalesce(r.applies_to,'customer') = 'affiliate'
     and coalesce(r.qualifying_amount, 0) > 0
     and (r.store_id = p_store_id or r.store_id is null)
     and r.effective_date <= p_day
   order by (r.store_id = p_store_id) desc, r.effective_date desc, r.created_at desc
   limit 1
$function$;

-- ---------------------------------------------------------------------
-- 4. Residual attributable to each Affiliate for a Singapore date.
--    Customer units are reserved FIRST; only what is left flows onward.
-- ---------------------------------------------------------------------
create or replace function public.affiliate_residual_for_day(p_affiliate_customer_id uuid, p_day date)
returns numeric language plpgsql stable security definer set search_path to 'public' as $function$
declare
  v_c record; v_rule public.therapy_package_rules;
  v_spend numeric; v_units integer; v_consumed numeric; v_residual numeric;
  v_share numeric; v_total numeric := 0;
begin
  -- Every (customer, store) whose paid invoices that day name this affiliate.
  for v_c in
    select distinct i.customer_id, i.store_id
      from public.invoices i
     where i.affiliate_snapshot_customer_id = p_affiliate_customer_id
       and coalesce(i.affiliate_active_on_paid,false)
       and i.status in ('paid','partially_paid') and coalesce(i.paid_amount,0) > 0
       and (i.paid_at at time zone 'Asia/Singapore')::date = p_day
  loop
    -- The customer's whole day at that store decides how much they consume.
    select coalesce(sum(i.paid_amount),0) into v_spend
      from public.invoices i
     where i.customer_id = v_c.customer_id and i.store_id = v_c.store_id
       and i.status in ('paid','partially_paid') and coalesce(i.paid_amount,0) > 0
       and (i.paid_at at time zone 'Asia/Singapore')::date = p_day;
    if v_spend <= 0 then continue; end if;

    v_rule := public.legacy_rule_for_amount(v_c.store_id, p_day, v_spend);
    v_units := case when v_rule.id is null then 0
                    else floor(v_spend / v_rule.qualifying_amount)::integer end;
    v_consumed := case when v_rule.id is null then 0
                       else v_units * v_rule.qualifying_amount end;
    v_residual := v_spend - v_consumed;
    if v_residual <= 0 then continue; end if;

    -- Proportional share of that residual for the invoices naming THIS affiliate.
    select coalesce(sum(i.paid_amount),0) into v_share
      from public.invoices i
     where i.customer_id = v_c.customer_id and i.store_id = v_c.store_id
       and i.status in ('paid','partially_paid') and coalesce(i.paid_amount,0) > 0
       and (i.paid_at at time zone 'Asia/Singapore')::date = p_day
       and i.affiliate_snapshot_customer_id = p_affiliate_customer_id
       and coalesce(i.affiliate_active_on_paid,false);

    v_total := v_total + round(v_share * (v_residual / v_spend), 2);
  end loop;

  return round(coalesce(v_total,0), 2);
end $function$;

-- ---------------------------------------------------------------------
-- 5. Recompute an Affiliate's Legacy units for a Singapore date.
--    Aggregated across every direct customer and every store.
-- ---------------------------------------------------------------------
create or replace function public.recompute_affiliate_legacy_qualification(
  p_affiliate_customer_id uuid, p_day date)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_group uuid; v_residual numeric; v_rule public.therapy_package_rules;
  v_store uuid; v_units integer; v_locked integer; v_needed integer; v_have integer;
  v_e record; v_created integer := 0; v_cancelled integer := 0; v_deadline date;
begin
  if p_affiliate_customer_id is null or p_day is null then
    return jsonb_build_object('skipped', true);
  end if;

  v_group := md5('legacy_aff:' || p_affiliate_customer_id::text || ':' || p_day::text)::uuid;
  v_residual := public.affiliate_residual_for_day(p_affiliate_customer_id, p_day);

  -- The store that contributed most of the residual carries the entitlement.
  select i.store_id into v_store
    from public.invoices i
   where i.affiliate_snapshot_customer_id = p_affiliate_customer_id
     and coalesce(i.affiliate_active_on_paid,false)
     and i.status in ('paid','partially_paid') and coalesce(i.paid_amount,0) > 0
     and (i.paid_at at time zone 'Asia/Singapore')::date = p_day
   group by i.store_id order by sum(i.paid_amount) desc limit 1;

  v_rule := public.affiliate_legacy_rule(v_store, p_day);

  v_units := case when v_rule.id is null or coalesce(v_rule.qualifying_amount,0) <= 0 then 0
                  else floor(v_residual / v_rule.qualifying_amount)::integer end;

  select count(*) into v_locked from public.therapy_entitlements
   where qualification_group_id = v_group and status not in ('pending_activation','cancelled');
  v_needed := greatest(v_units - v_locked, 0);

  select count(*) into v_have from public.therapy_entitlements
   where qualification_group_id = v_group and status = 'pending_activation';

  if v_have < v_needed then
    v_deadline := p_day + coalesce(v_rule.activation_deadline_days, 365);
    for i in 1 .. (v_needed - v_have) loop
      insert into public.therapy_entitlements (
        entitlement_no, customer_id, store_id, rule_id, package_name,
        entitlement_kind, duration_months, voucher_qty, qualifying_amount,
        qualified_value, forfeited_value, residual_value, activation_deadline,
        status, created_by, qualification_group_id, earner_kind)
      values (
        public.next_legacy_entitlement_no(), p_affiliate_customer_id, v_store, v_rule.id,
        coalesce(v_rule.name, 'Affiliate Legacy Reward'),
        'voucher', null, coalesce(v_rule.voucher_qty, 10), v_rule.qualifying_amount,
        v_rule.qualifying_amount, 0, v_residual, v_deadline,
        'pending_activation', auth.uid(), v_group, 'affiliate');
      v_created := v_created + 1;
    end loop;
  elsif v_have > v_needed then
    for v_e in
      select id from public.therapy_entitlements
       where qualification_group_id = v_group and status = 'pending_activation'
       order by created_at desc limit (v_have - v_needed)
    loop
      -- Withdrawing an unclaimed affiliate unit also returns any reward stock.
      perform public.revoke_affiliate_reward_vouchers(v_e.id);
      update public.therapy_entitlements set status = 'cancelled' where id = v_e.id;
      v_cancelled := v_cancelled + 1;
    end loop;
  end if;

  update public.therapy_entitlements
     set residual_value = v_residual,
         forfeited_value = case when v_rule.id is null then v_residual
                                else round(v_residual - (v_units * v_rule.qualifying_amount), 2) end
   where qualification_group_id = v_group and status = 'pending_activation';

  return jsonb_build_object('affiliate_residual', v_residual,
    'qualifying_amount', coalesce(v_rule.qualifying_amount,0),
    'units_target', v_units, 'created', v_created, 'cancelled', v_cancelled,
    'forfeited', case when v_rule.id is null then v_residual
                      else round(v_residual - (v_units * v_rule.qualifying_amount), 2) end);
end $function$;

-- Recompute every Affiliate touched by a customer/day.
create or replace function public.recompute_affiliates_for_customer_day(
  p_customer_id uuid, p_day date)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare v_a record;
begin
  for v_a in
    select distinct i.affiliate_snapshot_customer_id as aff
      from public.invoices i
     where i.customer_id = p_customer_id
       and i.affiliate_snapshot_customer_id is not null
       and (i.paid_at at time zone 'Asia/Singapore')::date = p_day
  loop
    perform public.recompute_affiliate_legacy_qualification(v_a.aff, p_day);
  end loop;
end $function$;

-- ---------------------------------------------------------------------
-- 6. Affiliate reward vouchers held against the Affiliate's customer record.
--    They never expire and cannot be transferred.
-- ---------------------------------------------------------------------
create table if not exists public.customer_reward_vouchers (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  voucher_id uuid not null references public.vouchers(id),
  entitlement_id uuid references public.therapy_entitlements(id),
  store_id uuid references public.stores(id),
  quantity integer not null check (quantity > 0),
  status text not null default 'held' check (status in ('held','redeemed','revoked')),
  issued_at timestamptz not null default now(),
  issued_by uuid references public.profiles(id),
  redeemed_at timestamptz,
  notes text
);
create index if not exists idx_crv_customer on public.customer_reward_vouchers (customer_id);
create index if not exists idx_crv_entitlement on public.customer_reward_vouchers (entitlement_id);
alter table public.customer_reward_vouchers enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='customer_reward_vouchers' and policyname='read reward vouchers') then
    create policy "read reward vouchers" on public.customer_reward_vouchers for select to authenticated using (true);
  end if;
end $$;

-- Which vouchers may be given as a Legacy reward.
alter table public.vouchers add column if not exists reward_eligible boolean not null default true;

create or replace function public.legacy_reward_voucher_options(p_store_id uuid)
returns table(voucher_id uuid, name text, code text, available_qty integer)
language sql stable security definer set search_path to 'public' as $function$
  select v.id, v.name, v.code,
         case when v.qty_type = 'unlimited' then null
              else coalesce(vs.current_qty, 0) end
    from public.vouchers v
    left join public.voucher_store_stock vs on vs.voucher_id = v.id and vs.store_id = p_store_id
   where v.is_active = true and v.deleted_at is null and coalesce(v.reward_eligible,true)
   order by v.name
$function$;

-- Return reward voucher stock when an unclaimed affiliate unit is withdrawn.
create or replace function public.revoke_affiliate_reward_vouchers(p_entitlement_id uuid)
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare v_r record; v_n integer := 0;
begin
  for v_r in
    select * from public.customer_reward_vouchers
     where entitlement_id = p_entitlement_id and status = 'held'
  loop
    if v_r.store_id is not null then
      update public.voucher_store_stock
         set current_qty = current_qty + v_r.quantity, updated_at = now()
       where voucher_id = v_r.voucher_id and store_id = v_r.store_id;
    end if;
    update public.customer_reward_vouchers set status = 'revoked' where id = v_r.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;

-- ---------------------------------------------------------------------
-- 7. Claiming, with a choice of reward and (for vouchers) a basket.
-- ---------------------------------------------------------------------
-- The reward options available for an entitlement: every rule at the same
-- qualifying amount and scope. Affiliates only ever see voucher rewards.
create or replace function public.legacy_reward_options(p_entitlement_id uuid)
returns table(rule_id uuid, name text, entitlement_kind text,
              duration_months integer, voucher_qty integer)
language plpgsql stable security definer set search_path to 'public' as $function$
#variable_conflict use_column
declare e public.therapy_entitlements%rowtype;
begin
  select * into e from public.therapy_entitlements where id = p_entitlement_id;
  if not found then return; end if;
  return query
    select r.id, r.name, r.entitlement_kind, r.duration_months, r.voucher_qty
      from public.therapy_package_rules r
     where r.is_active = true and r.deleted_at is null
       and r.qualifying_amount = e.qualifying_amount
       and (r.store_id = e.store_id or r.store_id is null)
       and coalesce(r.applies_to,'customer') =
           (case when e.earner_kind = 'affiliate' then 'affiliate' else 'customer' end)
       and (e.earner_kind <> 'affiliate' or r.entitlement_kind = 'voucher')
     order by r.entitlement_kind, r.name;
end $function$;

-- Drop the previous 2-argument form, otherwise the new optional parameters
-- create an ambiguous overload for existing 2-argument callers.
drop function if exists public.claim_legacy_therapy(uuid, date);

create or replace function public.claim_legacy_therapy(
  p_entitlement_id uuid, p_activation_date date default null,
  p_rule_id uuid default null, p_voucher_selections jsonb default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  e public.therapy_entitlements%rowtype;
  r public.therapy_package_rules;
  v_today date := public.sg_today();
  v_act date; v_exp date; v_status text;
  v_kind text; v_months integer; v_qty integer; v_name text;
  v_sel jsonb; v_sum integer := 0; v_vid uuid; v_q integer; v_stock integer;
begin
  select * into e from public.therapy_entitlements where id = p_entitlement_id for update;
  if not found then raise exception 'Legacy entitlement not found'; end if;
  if e.store_id is not null and not public.user_has_store_access(e.store_id) then
    raise exception 'No access to this store'; end if;
  if e.status <> 'pending_activation' then
    raise exception 'Only an unclaimed entitlement can be claimed (currently %)', e.status; end if;

  v_act := coalesce(p_activation_date, v_today);
  if v_act < v_today then raise exception 'The claim date cannot be in the past'; end if;
  if e.activation_deadline is not null and v_act > e.activation_deadline then
    raise exception 'The claim deadline (%) has passed', e.activation_deadline; end if;

  -- Choice of reward, when the tier offers more than one.
  v_kind := coalesce(e.entitlement_kind,'unlimited');
  v_months := e.duration_months; v_qty := e.voucher_qty; v_name := e.package_name;
  if p_rule_id is not null then
    select * into r from public.therapy_package_rules where id = p_rule_id;
    if not found then raise exception 'That reward option no longer exists'; end if;
    if r.qualifying_amount is distinct from e.qualifying_amount then
      raise exception 'That reward belongs to a different qualifying tier'; end if;
    if e.earner_kind = 'affiliate' and r.entitlement_kind <> 'voucher' then
      raise exception 'An Affiliate reward can only be vouchers'; end if;
    v_kind := r.entitlement_kind; v_months := r.duration_months;
    v_qty := r.voucher_qty; v_name := r.name;
  end if;

  if v_kind = 'unlimited' then
    v_exp := public.therapy_expiry(v_act, v_months);
    v_status := case when v_act > v_today then 'scheduled' else 'active' end;
  else
    -- Voucher reward: the basket must add up to the entitled quantity.
    if p_voucher_selections is null or jsonb_array_length(p_voucher_selections) = 0 then
      raise exception 'Choose % voucher(s) to claim this reward', coalesce(v_qty,0); end if;
    for v_sel in select * from jsonb_array_elements(p_voucher_selections) loop
      v_sum := v_sum + coalesce((v_sel->>'quantity')::integer, 0);
    end loop;
    if v_sum <> coalesce(v_qty,0) then
      raise exception 'Select exactly % voucher(s) — % chosen', coalesce(v_qty,0), v_sum; end if;

    for v_sel in select * from jsonb_array_elements(p_voucher_selections) loop
      v_vid := (v_sel->>'voucher_id')::uuid;
      v_q := coalesce((v_sel->>'quantity')::integer, 0);
      if v_q <= 0 then continue; end if;
      if not exists (select 1 from public.vouchers v
                      where v.id = v_vid and v.is_active = true and v.deleted_at is null
                        and coalesce(v.reward_eligible,true)) then
        raise exception 'That voucher cannot be given as a reward'; end if;

      -- Limited vouchers draw down store stock.
      if exists (select 1 from public.vouchers where id = v_vid and qty_type <> 'unlimited') then
        select current_qty into v_stock from public.voucher_store_stock
         where voucher_id = v_vid and store_id = e.store_id for update;
        if coalesce(v_stock,0) < v_q then
          raise exception 'Not enough stock of "%" at this store (% available)',
            (select name from public.vouchers where id = v_vid), coalesce(v_stock,0); end if;
        update public.voucher_store_stock set current_qty = current_qty - v_q, updated_at = now()
         where voucher_id = v_vid and store_id = e.store_id;
      end if;

      insert into public.customer_reward_vouchers
        (customer_id, voucher_id, entitlement_id, store_id, quantity, issued_by, notes)
      values (e.customer_id, v_vid, e.id, e.store_id, v_q, auth.uid(),
              'Legacy reward — never expires, not transferable');
    end loop;
    v_exp := null; v_status := 'active';
  end if;

  update public.therapy_entitlements
     set status = v_status, activation_date = v_act, expiry_date = v_exp,
         entitlement_kind = v_kind, duration_months = v_months,
         voucher_qty = v_qty, package_name = v_name,
         rule_id = coalesce(p_rule_id, rule_id),
         claimed_by = auth.uid(), claimed_at = now()
   where id = p_entitlement_id;

  perform public.write_audit_ex('therapy_entitlements', p_entitlement_id, 'legacy_therapy_claimed',
    jsonb_build_object('status', e.status),
    jsonb_build_object('status', v_status, 'activation_date', v_act, 'expiry_date', v_exp,
                       'kind', v_kind, 'voucher_qty', v_qty, 'earner', e.earner_kind),
    'therapy', 'legacy claim', e.store_id);

  return jsonb_build_object('success', true, 'status', v_status, 'kind', v_kind,
    'activation_date', v_act, 'expiry_date', v_exp,
    'entitlement_no', e.entitlement_no,
    'voucher_qty', case when v_kind = 'voucher' then v_qty else null end);
end $function$;

-- ---------------------------------------------------------------------
-- 8. Refunds: recalculate both sides, and block where a reward is already
--    consumed or a therapy period already started.
-- ---------------------------------------------------------------------
create or replace function public.assert_legacy_refund_allowed(p_invoice_id uuid)
returns void language plpgsql stable security definer set search_path to 'public' as $function$
declare
  v_inv public.invoices%rowtype; v_day date; v_group uuid; v_n integer;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found or v_inv.paid_at is null then return; end if;
  v_day := (v_inv.paid_at at time zone 'Asia/Singapore')::date;

  -- The customer's own Legacy therapy for that day.
  if v_inv.customer_id is not null and v_inv.store_id is not null then
    v_group := public.legacy_qualification_group(v_inv.customer_id, v_inv.store_id, v_day);
    select count(*) into v_n from public.therapy_entitlements
     where qualification_group_id = v_group
       and status in ('active','scheduled','expired')
       and coalesce(entitlement_kind,'unlimited') = 'unlimited';
    if v_n > 0 then
      raise exception 'This invoice cannot be refunded: the customer''s Legacy therapy from that day has already been activated. Cancel or complete the therapy first.';
    end if;
  end if;

  -- Any affiliate reward voucher from that day that has already been redeemed.
  if v_inv.affiliate_snapshot_customer_id is not null then
    select count(*) into v_n
      from public.customer_reward_vouchers crv
      join public.therapy_entitlements e on e.id = crv.entitlement_id
     where e.earner_kind = 'affiliate'
       and e.customer_id = v_inv.affiliate_snapshot_customer_id
       and e.qualification_group_id =
           md5('legacy_aff:' || v_inv.affiliate_snapshot_customer_id::text || ':' || v_day::text)::uuid
       and crv.status = 'redeemed';
    if v_n > 0 then
      raise exception 'This invoice cannot be refunded: an Affiliate reward voucher earned from that day has already been redeemed.';
    end if;
  end if;
end $function$;

create or replace function public.trg_legacy_refund_guard()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  -- Only when money is being taken back or the invoice is being voided.
  if (coalesce(new.paid_amount,0) < coalesce(old.paid_amount,0))
     or (new.status in ('refunded','cancelled') and old.status not in ('refunded','cancelled')) then
    perform public.assert_legacy_refund_allowed(new.id);
  end if;
  return new;
end $function$;

drop trigger if exists legacy_refund_guard on public.invoices;
create trigger legacy_refund_guard before update on public.invoices
  for each row execute function public.trg_legacy_refund_guard();

-- ---------------------------------------------------------------------
-- 9. Payment hook: snapshot the affiliate, then recompute both sides.
-- ---------------------------------------------------------------------
create or replace function public.trg_create_therapy_on_paid()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare v_day date;
begin
  if new.status in ('paid','completed_foc') and old.status is distinct from new.status then
    if exists (select 1 from public.invoice_items where invoice_id = new.id and line_kind = 'therapy') then
      perform public.create_purchased_therapy_for_invoice(new.id);
    end if;
  end if;

  if (new.status is distinct from old.status)
     or (coalesce(new.paid_amount,0) is distinct from coalesce(old.paid_amount,0)) then
    v_day := (coalesce(new.paid_at, now()) at time zone 'Asia/Singapore')::date;

    -- Freeze who the affiliate was, and whether they were active, at payment.
    if new.status in ('paid','partially_paid') and coalesce(new.paid_amount,0) > 0
       and new.affiliate_active_on_paid is null then
      perform public.snapshot_invoice_affiliate(new.id);
    end if;

    if new.customer_id is not null and new.store_id is not null then
      perform public.recompute_legacy_qualification(new.customer_id, new.store_id, v_day);
      perform public.recompute_affiliates_for_customer_day(new.customer_id, v_day);
    end if;
  end if;

  return null;
end $function$;

-- ---------------------------------------------------------------------
-- 10. Backfill covers Affiliates too.
-- ---------------------------------------------------------------------
create or replace function public.backfill_legacy_qualification(
  p_from date default null, p_to date default null, p_store_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_r record; v_res jsonb;
  v_days integer := 0; v_created integer := 0; v_cancelled integer := 0; v_aff integer := 0;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can run the qualification backfill';
  end if;

  -- Make sure every paid invoice carries its affiliate snapshot.
  for v_r in
    select id from public.invoices
     where status in ('paid','partially_paid') and coalesce(paid_amount,0) > 0
       and paid_at is not null and affiliate_active_on_paid is null
       and (p_store_id is null or store_id = p_store_id)
  loop
    perform public.snapshot_invoice_affiliate(v_r.id);
  end loop;

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

  -- Affiliates are aggregated per date across every store, so they are done
  -- after all customer units for that date have been reserved.
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
    'customer_created', v_created, 'affiliate_created', v_aff, 'cancelled', v_cancelled);
end $function$;

notify pgrst, 'reload schema';
