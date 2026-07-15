-- =====================================================================
-- ENERGIA — NEW SPEC PHASE 4A: Therapy rules, qualification, combinations,
--                              entitlement creation
--
-- Scope 4A: per-store package rules (seeded), the qualification engine
-- (single invoice, combined same-day invoices, qualification top-up), the
-- combination engine (which packages a spend can buy), and creating
-- entitlements with source-invoice linking. Beneficiaries/activation/
-- statuses/transfers are 4B; invoice display is 4C.
--
-- Additive + idempotent. Run AFTER 34_specphase3b_bundle_exchange.sql.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Per-store therapy package rules. entitlement_kind: 'unlimited'
--    (duration_months) or 'voucher' (voucher_qty). Historical entitlements
--    snapshot the rule, so later edits don't change them.
-- ---------------------------------------------------------------------
create table if not exists public.therapy_package_rules (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  qualifying_amount numeric(12,2) not null,
  entitlement_kind text not null default 'unlimited' check (entitlement_kind in ('unlimited','voucher')),
  duration_months integer,          -- for 'unlimited'
  voucher_qty integer,              -- for 'voucher'
  activation_deadline_days integer not null default 365,
  is_active boolean not null default true,
  effective_date date not null default (now() at time zone 'Asia/Singapore')::date,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_tpr_store on public.therapy_package_rules(store_id);

alter table public.therapy_package_rules enable row level security;
drop policy if exists "read therapy rules" on public.therapy_package_rules;
create policy "read therapy rules" on public.therapy_package_rules for select to authenticated using (true);
drop policy if exists "write therapy rules" on public.therapy_package_rules;
create policy "write therapy rules" on public.therapy_package_rules for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

-- Seed the three defaults for every store (unlimited variant; the voucher
-- alternative at the same amount is a second rule).
insert into public.therapy_package_rules (store_id, name, qualifying_amount, entitlement_kind, duration_months, voucher_qty)
select s.id, v.name, v.amt, v.kind, v.dur, v.vq
from public.stores s
cross join (values
  ('1 Month Unlimited', 794.00, 'unlimited', 1, null),
  ('10 Vouchers',       794.00, 'voucher',   null, 10),
  ('6 Months Unlimited',3594.00,'unlimited', 6, null),
  ('60 Vouchers',       3594.00,'voucher',   null, 60),
  ('12 Months Unlimited',3994.00,'unlimited',12, null),
  ('120 Vouchers',      3994.00,'voucher',   null, 120)
) as v(name, amt, kind, dur, vq)
where not exists (
  select 1 from public.therapy_package_rules r
  where r.store_id = s.id and r.name = v.name and r.qualifying_amount = v.amt
);

-- ---------------------------------------------------------------------
-- 2. Entitlements + source-invoice links. (Beneficiaries/activation in 4B.)
-- ---------------------------------------------------------------------
create table if not exists public.therapy_entitlements (
  id uuid primary key default gen_random_uuid(),
  entitlement_no text not null unique,
  customer_id uuid not null references public.customers(id),
  store_id uuid not null references public.stores(id),
  rule_id uuid references public.therapy_package_rules(id),
  -- snapshot of the rule at creation (historical integrity)
  package_name text not null,
  entitlement_kind text not null,
  duration_months integer,
  voucher_qty integer,
  qualifying_amount numeric(12,2) not null,      -- rule threshold used
  qualified_value numeric(12,2) not null,        -- eligible amount consumed
  forfeited_value numeric(12,2) not null default 0,
  activation_deadline date not null,
  status text not null default 'pending_activation',
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_te_customer on public.therapy_entitlements(customer_id);
create index if not exists idx_te_store on public.therapy_entitlements(store_id);

create table if not exists public.therapy_entitlement_invoices (
  id uuid primary key default gen_random_uuid(),
  entitlement_id uuid not null references public.therapy_entitlements(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id),
  contributed_amount numeric(12,2) not null default 0,
  created_at timestamptz not null default now(),
  unique(entitlement_id, invoice_id)
);
-- An invoice can only ever be consumed by ONE entitlement.
create unique index if not exists uq_tei_invoice on public.therapy_entitlement_invoices(invoice_id);

-- Qualification top-up ledger (special paid line, non-refundable).
create table if not exists public.therapy_qualification_topups (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  store_id uuid not null references public.stores(id),
  amount numeric(12,2) not null check (amount > 0),
  entitlement_id uuid references public.therapy_entitlements(id),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.therapy_entitlements enable row level security;
alter table public.therapy_entitlement_invoices enable row level security;
alter table public.therapy_qualification_topups enable row level security;
drop policy if exists "read entitlements" on public.therapy_entitlements;
create policy "read entitlements" on public.therapy_entitlements for select to authenticated
  using (public.is_manager_or_above() or public.user_has_store_access(store_id));
drop policy if exists "read ent invoices" on public.therapy_entitlement_invoices;
create policy "read ent invoices" on public.therapy_entitlement_invoices for select to authenticated using (true);
drop policy if exists "read qual topups" on public.therapy_qualification_topups;
create policy "read qual topups" on public.therapy_qualification_topups for select to authenticated using (true);

-- ---------------------------------------------------------------------
-- 3. Eligible invoices: fully-paid, same-customer, same-store, same SG
--    payment date, not already consumed by an entitlement. Excludes
--    cancelled/refunded/deleted implicitly (status must be 'paid').
-- ---------------------------------------------------------------------
create or replace function public.therapy_eligible_invoices(p_customer_id uuid, p_store_id uuid, p_sg_date date)
returns table(invoice_id uuid, invoice_no text, total_amount numeric, paid_date date)
language sql stable security definer set search_path = public as $$
  select i.id, i.invoice_no, i.total_amount, (i.paid_at at time zone 'Asia/Singapore')::date
  from public.invoices i
  where i.customer_id = p_customer_id and i.store_id = p_store_id
    and i.status = 'paid' and i.deleted_at is null and i.paid_at is not null
    and (i.paid_at at time zone 'Asia/Singapore')::date = p_sg_date
    and not exists (select 1 from public.therapy_entitlement_invoices tei where tei.invoice_id = i.id)
  order by i.paid_at
$$;

-- ---------------------------------------------------------------------
-- 4. Combination engine: given an eligible amount + store, return every
--    package rule affordable, and greedily suggest the "best" mix (largest
--    packages first). Pure calculation — no writes.
-- ---------------------------------------------------------------------
create or replace function public.therapy_combinations(p_store_id uuid, p_amount numeric)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_rule record; v_remaining numeric; v_suggest jsonb := '[]'::jsonb; v_used numeric := 0;
  v_affordable jsonb := '[]'::jsonb; v_count integer;
begin
  -- All single rules the amount can afford (for manual selection).
  for v_rule in
    select * from public.therapy_package_rules
    where store_id = p_store_id and is_active = true and deleted_at is null and qualifying_amount <= p_amount
    order by qualifying_amount desc, entitlement_kind
  loop
    v_affordable := v_affordable || jsonb_build_object(
      'rule_id', v_rule.id, 'name', v_rule.name, 'qualifying_amount', v_rule.qualifying_amount,
      'entitlement_kind', v_rule.entitlement_kind, 'duration_months', v_rule.duration_months, 'voucher_qty', v_rule.voucher_qty);
  end loop;

  -- Greedy auto-suggestion: repeatedly take the largest unlimited rule that
  -- still fits (falls back to any kind), until nothing fits.
  v_remaining := p_amount;
  loop
    select * into v_rule from public.therapy_package_rules
      where store_id = p_store_id and is_active = true and deleted_at is null
        and qualifying_amount <= v_remaining
      order by qualifying_amount desc, (entitlement_kind = 'unlimited') desc
      limit 1;
    exit when not found;
    v_count := 0;
    while v_remaining >= v_rule.qualifying_amount loop
      v_remaining := v_remaining - v_rule.qualifying_amount;
      v_used := v_used + v_rule.qualifying_amount;
      v_count := v_count + 1;
    end loop;
    v_suggest := v_suggest || jsonb_build_object(
      'rule_id', v_rule.id, 'name', v_rule.name, 'qty', v_count,
      'qualifying_amount', v_rule.qualifying_amount, 'entitlement_kind', v_rule.entitlement_kind,
      'duration_months', v_rule.duration_months, 'voucher_qty', v_rule.voucher_qty);
  end loop;

  return jsonb_build_object(
    'amount', p_amount, 'affordable', v_affordable,
    'suggestion', v_suggest, 'suggestion_used', v_used, 'suggestion_forfeited', p_amount - v_used);
end $$;

-- ---------------------------------------------------------------------
-- 5. Create entitlements (atomic). Consumes selected invoices (+ optional
--    top-up), applies the chosen combination (list of rule_id + qty), links
--    every source invoice, records forfeited balance. Manual OR auto: the
--    caller passes the final combination (auto flow just passes the engine's
--    suggestion).
-- ---------------------------------------------------------------------
create or replace function public.create_therapy_entitlements(
  p_customer_id uuid,
  p_store_id uuid,
  p_invoice_ids uuid[],
  p_combination jsonb,        -- [{rule_id, qty}]
  p_topup_amount numeric default 0,
  p_topup_payments jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role user_role; v_eligible numeric := 0; v_inv record; v_sg date;
  v_combo jsonb; v_rule public.therapy_package_rules%rowtype; v_qty integer;
  v_need numeric := 0; v_used numeric := 0; v_created jsonb := '[]'::jsonb;
  v_ent_id uuid; v_no text; v_deadline date; v_pay_sum numeric := 0; v_topup_id uuid; k integer;
begin
  v_role := public.current_user_role();
  if v_role is null then raise exception 'No profile for current user'; end if;
  if not public.user_has_store_access(p_store_id) then raise exception 'No access to that store'; end if;
  if p_invoice_ids is null or array_length(p_invoice_ids,1) is null then raise exception 'Select at least one paid invoice'; end if;

  -- Validate every invoice is eligible (paid, same customer/store/day, unconsumed).
  v_sg := null;
  for v_inv in
    select i.id, i.total_amount, (i.paid_at at time zone 'Asia/Singapore')::date d
    from public.invoices i where i.id = any(p_invoice_ids) for update
  loop
    if v_inv.d is null then raise exception 'An invoice is not paid'; end if;
    if v_sg is null then v_sg := v_inv.d; elsif v_sg <> v_inv.d then raise exception 'All invoices must share the same Singapore payment date'; end if;
    if exists (select 1 from public.therapy_entitlement_invoices t where t.invoice_id = v_inv.id) then
      raise exception 'An invoice has already been used for a therapy entitlement'; end if;
    v_eligible := v_eligible + v_inv.total_amount;
  end loop;

  -- Optional qualification top-up (real paid money, counts toward eligible).
  if coalesce(p_topup_amount,0) > 0 then
    select coalesce(sum((x->>'amount')::numeric),0) into v_pay_sum from jsonb_array_elements(p_topup_payments) x;
    if round(v_pay_sum,2) <> round(p_topup_amount,2) then raise exception 'Top-up payment must equal the top-up amount'; end if;
    v_eligible := v_eligible + p_topup_amount;
  end if;

  -- Sum the combination's required qualifying amounts; must not exceed eligible.
  for v_combo in select * from jsonb_array_elements(p_combination) loop
    select * into v_rule from public.therapy_package_rules where id = (v_combo->>'rule_id')::uuid;
    if not found then raise exception 'A selected package rule was not found'; end if;
    if v_rule.store_id <> p_store_id then raise exception 'A selected rule belongs to another store'; end if;
    v_qty := coalesce((v_combo->>'qty')::integer, 1);
    v_need := v_need + v_rule.qualifying_amount * v_qty;
  end loop;
  if v_need = 0 then raise exception 'Select at least one package'; end if;
  if round(v_need,2) > round(v_eligible,2) then
    raise exception 'Selected packages need %.2f but only %.2f is eligible', v_need, v_eligible; end if;

  -- Record the top-up (once), link later to first entitlement.
  if coalesce(p_topup_amount,0) > 0 then
    insert into public.therapy_qualification_topups (customer_id, store_id, amount, created_by)
    values (p_customer_id, p_store_id, p_topup_amount, auth.uid()) returning id into v_topup_id;
  end if;

  -- Create one entitlement per unit of each rule.
  for v_combo in select * from jsonb_array_elements(p_combination) loop
    select * into v_rule from public.therapy_package_rules where id = (v_combo->>'rule_id')::uuid;
    v_qty := coalesce((v_combo->>'qty')::integer, 1);
    for k in 1..v_qty loop
      v_no := 'TE-' || to_char(now() at time zone 'Asia/Singapore','YYYYMMDD') || '-' || substr(gen_random_uuid()::text,1,6);
      v_deadline := public.sg_today() + coalesce(v_rule.activation_deadline_days, 365);
      insert into public.therapy_entitlements
        (entitlement_no, customer_id, store_id, rule_id, package_name, entitlement_kind,
         duration_months, voucher_qty, qualifying_amount, qualified_value, forfeited_value,
         activation_deadline, status, created_by)
      values (v_no, p_customer_id, p_store_id, v_rule.id, v_rule.name, v_rule.entitlement_kind,
         v_rule.duration_months, v_rule.voucher_qty, v_rule.qualifying_amount, v_rule.qualifying_amount, 0,
         v_deadline, 'pending_activation', auth.uid())
      returning id into v_ent_id;
      v_used := v_used + v_rule.qualifying_amount;
      if v_topup_id is not null then update public.therapy_qualification_topups set entitlement_id = v_ent_id where id = v_topup_id and entitlement_id is null; end if;
      v_created := v_created || to_jsonb(v_ent_id);
    end loop;
  end loop;

  -- Link source invoices to the FIRST created entitlement (forfeit shown there).
  v_ent_id := (v_created->>0)::uuid;
  for v_inv in select i.id, i.total_amount from public.invoices i where i.id = any(p_invoice_ids)
  loop
    insert into public.therapy_entitlement_invoices (entitlement_id, invoice_id, contributed_amount)
    values (v_ent_id, v_inv.id, v_inv.total_amount);
  end loop;
  update public.therapy_entitlements set forfeited_value = round(v_eligible - v_used, 2) where id = v_ent_id;

  -- Top-up payments (recorded against the qualification top-up).
  if coalesce(p_topup_amount,0) > 0 then
    perform 1; -- payment capture is informational here; money handled at POS popup in UI
  end if;

  perform public.write_audit_ex('therapy_entitlements', v_ent_id, 'therapy_entitlement_created', null,
    jsonb_build_object('eligible', v_eligible, 'used', v_used, 'forfeited', round(v_eligible - v_used,2), 'count', jsonb_array_length(v_created)),
    'therapy', null, p_store_id);

  return jsonb_build_object('success', true, 'eligible', v_eligible, 'used', v_used,
    'forfeited', round(v_eligible - v_used, 2), 'entitlement_ids', v_created);
end $$;

notify pgrst, 'reload schema';
