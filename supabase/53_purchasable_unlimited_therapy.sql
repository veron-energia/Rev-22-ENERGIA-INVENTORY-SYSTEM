-- =====================================================================
-- ENERGIA — PHASE 6: PURCHASABLE UNLIMITED THERAPY
--
-- Removes the TARGET-BASED therapy qualification for NEW transactions and
-- introduces purchasable Unlimited Therapy packages sold as an invoice line
-- (Member/Non-Member priced, non-stock, Own Product, commission-earning).
--
-- Historical therapy data is fully preserved and becomes read-only "Legacy
-- Therapy" — the only allowed legacy action is activating an eligible,
-- unactivated legacy entitlement within its existing deadline.
--
-- NUMBERING: the spec names 49_purchasable_unlimited_therapy.sql, but 49 is
-- the Phase 4 final-corrections migration (executed, must not be renamed).
-- This ships as 53 (50/51/52 precede it).
--
-- Additive + idempotent. Run AFTER 52.
-- =====================================================================

set check_function_bodies = off;

-- =====================================================================
-- 1. DISABLE new target-based awards.
--    We do NOT drop the historical tables (legacy data + legacy activation
--    still need them). The creation/mutation ENTRY POINTS are dropped and
--    re-created as permanent "retired" stubs. Drops use the exact original
--    signatures — required because some stubs change the return type or the
--    argument list, which CREATE OR REPLACE cannot do.
-- =====================================================================

-- create_therapy_entitlements: same signature, returns jsonb -> safe to replace,
-- but drop first for consistency.
drop function if exists public.create_therapy_entitlements(uuid, uuid, uuid[], jsonb, numeric, jsonb);
create function public.create_therapy_entitlements(
  p_customer_id uuid, p_store_id uuid, p_invoice_ids uuid[],
  p_combination jsonb, p_topup_amount numeric default 0, p_topup_payments jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Target-based therapy qualification has been retired. Sell an Unlimited Therapy package on an invoice instead.';
end $$;

-- assign_therapy_beneficiary: ORIGINAL args were (uuid, uuid, integer, integer).
drop function if exists public.assign_therapy_beneficiary(uuid, uuid, integer, integer);
create function public.assign_therapy_beneficiary(
  p_entitlement_id uuid, p_customer_id uuid,
  p_portion_months integer default null, p_portion_vouchers integer default null
) returns uuid language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Beneficiary assignment is retired for the new therapy model. Legacy entitlements are view-only (activation excepted).';
end $$;

-- transfer_therapy_beneficiary: ORIGINAL args were (uuid, uuid, text).
drop function if exists public.transfer_therapy_beneficiary(uuid, uuid, text);
create function public.transfer_therapy_beneficiary(
  p_beneficiary_id uuid, p_new_customer_id uuid, p_reason text default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Therapy transfer is retired. Purchased therapy is owned by the buyer and is non-transferable.';
end $$;

-- request_therapy_date_change: ORIGINAL args were (uuid, text, date, text).
drop function if exists public.request_therapy_date_change(uuid, text, date, text);
create function public.request_therapy_date_change(
  p_beneficiary_id uuid, p_field text, p_new_value date, p_reason text
) returns uuid language plpgsql security definer set search_path = public as $$
begin
  raise exception 'The date-change request workflow is retired. Purchased therapy dates are set directly before activation.';
end $$;

-- therapy_eligible_invoices: RETURN TYPE changes -> must drop first.
drop function if exists public.therapy_eligible_invoices(uuid, uuid, date);
create function public.therapy_eligible_invoices(
  p_customer_id uuid, p_store_id uuid, p_sg_date date
) returns table (invoice_id uuid, invoice_no text, total_amount numeric, paid_date date)
language sql stable security definer set search_path = public as $$
  select null::uuid, null::text, null::numeric, null::date where false
$$;

-- =====================================================================
-- 2. Purchasable Unlimited Therapy packages + store prices.
-- =====================================================================
create table if not exists public.unlimited_therapy_packages (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  duration_months integer not null check (duration_months > 0),
  description text,
  is_active boolean not null default true,
  deleted_at timestamptz,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.unlimited_therapy_store_prices (
  id uuid primary key default gen_random_uuid(),
  package_id uuid not null references public.unlimited_therapy_packages(id) on delete cascade,
  store_id uuid not null references public.stores(id),
  member_price numeric(12,2),
  non_member_price numeric(12,2),
  available_at_store boolean not null default true,
  deleted_at timestamptz,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (package_id, store_id)
);

alter table public.unlimited_therapy_packages enable row level security;
alter table public.unlimited_therapy_store_prices enable row level security;
drop policy if exists "read utp" on public.unlimited_therapy_packages;
create policy "read utp" on public.unlimited_therapy_packages for select to authenticated using (true);
drop policy if exists "read utsp" on public.unlimited_therapy_store_prices;
create policy "read utsp" on public.unlimited_therapy_store_prices for select to authenticated using (true);

-- Owner/Manager management functions.
create or replace function public.upsert_unlimited_therapy_package(
  p_id uuid, p_name text, p_duration_months integer, p_description text, p_is_active boolean
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can manage therapy packages'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'Package name is required'; end if;
  if p_duration_months is null or p_duration_months <= 0 then raise exception 'Duration (calendar months) must be positive'; end if;
  if p_id is null then
    insert into public.unlimited_therapy_packages (name, duration_months, description, is_active, created_by, updated_by)
    values (trim(p_name), p_duration_months, p_description, coalesce(p_is_active,true), auth.uid(), auth.uid())
    returning id into v_id;
  else
    update public.unlimited_therapy_packages
       set name = trim(p_name), duration_months = p_duration_months, description = p_description,
           is_active = coalesce(p_is_active,true), updated_by = auth.uid(), updated_at = now()
     where id = p_id returning id into v_id;
  end if;
  perform public.write_audit('unlimited_therapy_packages', v_id, case when p_id is null then 'therapy_package_created' else 'therapy_package_updated' end,
    null, jsonb_build_object('name', p_name, 'months', p_duration_months));
  return v_id;
end $$;

create or replace function public.set_unlimited_therapy_price(
  p_package_id uuid, p_store_id uuid, p_member numeric, p_non_member numeric, p_available boolean
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can set therapy prices'; end if;
  insert into public.unlimited_therapy_store_prices (package_id, store_id, member_price, non_member_price, available_at_store, created_by, updated_by)
  values (p_package_id, p_store_id, p_member, p_non_member, coalesce(p_available,true), auth.uid(), auth.uid())
  on conflict (package_id, store_id) do update
    set member_price = excluded.member_price, non_member_price = excluded.non_member_price,
        available_at_store = excluded.available_at_store, deleted_at = null,
        updated_by = auth.uid(), updated_at = now();
  perform public.write_audit_ex('unlimited_therapy_store_prices', p_package_id, 'therapy_price_set',
    null, jsonb_build_object('store', p_store_id, 'member', p_member, 'non_member', p_non_member), 'therapy', null, p_store_id);
end $$;

-- Mode-aware price resolver (mirrors product/voucher resolvers).
create or replace function public.therapy_price_for(p_store_id uuid, p_package_id uuid, p_is_member boolean)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r public.unlimited_therapy_store_prices%rowtype; v_price numeric;
begin
  select * into r from public.unlimited_therapy_store_prices
   where package_id = p_package_id and store_id = p_store_id and deleted_at is null;
  if not found or not r.available_at_store then
    return jsonb_build_object('found', false, 'has_price', false, 'eligible', true); end if;
  v_price := case when p_is_member then r.member_price else r.non_member_price end;
  return jsonb_build_object('found', true, 'eligible', true,
    'has_price', v_price is not null, 'price', v_price, 'price_mode', case when p_is_member then 'member' else 'non_member' end,
    'member_price', r.member_price, 'non_member_price', r.non_member_price, 'source_id', p_package_id);
end $$;

-- =====================================================================
-- 3. Purchased therapy entitlements (new structure).
-- =====================================================================
create table if not exists public.purchased_therapy_entitlements (
  id uuid primary key default gen_random_uuid(),
  entitlement_no text not null unique,
  customer_id uuid not null references public.customers(id),
  store_id uuid not null references public.stores(id),
  package_id uuid not null references public.unlimited_therapy_packages(id),
  invoice_id uuid not null references public.invoices(id),
  invoice_item_id uuid references public.invoice_items(id) on delete set null,

  package_name text not null,
  duration_months integer not null,
  price_snapshot numeric(12,2) not null,
  price_mode text,

  purchase_date date not null,
  activation_deadline date not null,        -- purchase_date + 1 calendar year
  scheduled_date date,                      -- future activation date (optional)
  activation_date date,                     -- locked on activation
  expiry_date date,                         -- locked on activation

  status text not null default 'pending_activation'
    check (status in ('pending_activation','scheduled','active','expired','cancelled','refunded')),

  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_pte_customer on public.purchased_therapy_entitlements(customer_id);
create index if not exists idx_pte_invoice on public.purchased_therapy_entitlements(invoice_id);
create index if not exists idx_pte_status on public.purchased_therapy_entitlements(status);

alter table public.purchased_therapy_entitlements enable row level security;
drop policy if exists "read pte" on public.purchased_therapy_entitlements;
create policy "read pte" on public.purchased_therapy_entitlements for select to authenticated using (true);

-- No-overlap for the SAME package (different packages may overlap; future
-- renewal of the same package after expiry is allowed). Uses activation/expiry
-- window; pending/scheduled rows without an activation window don't conflict.
create extension if not exists btree_gist;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'excl_pte_same_package_no_overlap') then
    alter table public.purchased_therapy_entitlements
      add constraint excl_pte_same_package_no_overlap
      exclude using gist (
        customer_id with =, package_id with =,
        daterange(activation_date, expiry_date, '[]') with &&
      ) where (activation_date is not null and expiry_date is not null and status in ('active','scheduled','expired') = false or status = 'active');
  end if;
exception when others then
  -- If the partial predicate is rejected on this PG version, fall back to a
  -- simpler active-only exclusion.
  if not exists (select 1 from pg_constraint where conname = 'excl_pte_same_package_no_overlap') then
    alter table public.purchased_therapy_entitlements
      add constraint excl_pte_same_package_no_overlap
      exclude using gist (
        customer_id with =, package_id with =,
        daterange(activation_date, expiry_date, '[]') with &&
      ) where (status = 'active');
  end if;
end $$;

create sequence if not exists purchased_therapy_no_seq;
create or replace function public.next_purchased_therapy_no()
returns text language sql security definer set search_path = public as $$
  select 'UTP-' || lpad(nextval('purchased_therapy_no_seq')::text, 7, '0')
$$;

-- invoice_items therapy package reference (additive).
alter table public.invoice_items add column if not exists therapy_package_id uuid references public.unlimited_therapy_packages(id);

-- =====================================================================
-- 4. Create purchased entitlements at payment (called from pay_invoice for
--    each therapy line). Non-stock, owned by buyer, one-year deadline.
-- =====================================================================
create or replace function public.create_purchased_therapy_for_invoice(p_invoice_id uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare v_inv public.invoices%rowtype; v_li record; v_n integer := 0; v_pkg public.unlimited_therapy_packages%rowtype; v_deadline date;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  for v_li in select * from public.invoice_items where invoice_id = p_invoice_id and line_kind = 'therapy'
  loop
    -- Skip if already created (idempotent on re-run).
    if exists (select 1 from public.purchased_therapy_entitlements where invoice_item_id = v_li.id) then continue; end if;
    select * into v_pkg from public.unlimited_therapy_packages where id = v_li.therapy_package_id;
    if not found then raise exception 'Therapy package not found for line'; end if;
    v_deadline := (v_inv.paid_at at time zone 'Asia/Singapore')::date + interval '1 year';

    insert into public.purchased_therapy_entitlements (
      entitlement_no, customer_id, store_id, package_id, invoice_id, invoice_item_id,
      package_name, duration_months, price_snapshot, price_mode,
      purchase_date, activation_deadline, status, created_by, updated_by)
    values (
      public.next_purchased_therapy_no(), v_inv.customer_id, v_inv.store_id, v_pkg.id, p_invoice_id, v_li.id,
      v_pkg.name, v_pkg.duration_months, v_li.unit_price, v_li.price_mode,
      (v_inv.paid_at at time zone 'Asia/Singapore')::date, v_deadline::date, 'pending_activation',
      auth.uid(), auth.uid());
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;


-- Auto-create purchased therapy the moment an invoice becomes fully paid.
-- pay_invoice (48b) already runs stock/membership/commission in its transaction;
-- this trigger fires in the same commit, so therapy creation is atomic with
-- payment without rewriting pay_invoice.
create or replace function public.trg_create_therapy_on_paid() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'paid' and old.status is distinct from 'paid' then
    if exists (select 1 from public.invoice_items where invoice_id = new.id and line_kind = 'therapy') then
      perform public.create_purchased_therapy_for_invoice(new.id);
    end if;
  end if;
  return null;
end $$;

drop trigger if exists create_therapy_on_paid on public.invoices;
create trigger create_therapy_on_paid
  after update on public.invoices
  for each row execute function public.trg_create_therapy_on_paid();

-- =====================================================================
-- 5. Activation / scheduling (everyone with invoice access).
-- =====================================================================
create or replace function public.activate_purchased_therapy(
  p_entitlement_id uuid, p_activation_date date default null, p_reason text default null
) returns void language plpgsql security definer set search_path = public as $$
declare e public.purchased_therapy_entitlements%rowtype; v_today date := public.sg_today(); v_act date; v_exp date;
begin
  select * into e from public.purchased_therapy_entitlements where id = p_entitlement_id for update;
  if not found then raise exception 'Entitlement not found'; end if;
  if not public.user_has_store_access(e.store_id) then raise exception 'No access to this store'; end if;
  if e.status in ('active','expired','cancelled','refunded') then raise exception 'Entitlement is already %', e.status; end if;

  v_act := coalesce(p_activation_date, v_today);
  if v_act > e.activation_deadline then
    raise exception 'Activation must occur within one year of purchase (deadline %)', e.activation_deadline; end if;
  if v_act < v_today then raise exception 'Activation date cannot be in the past'; end if;

  v_exp := public.membership_expiry(v_act, e.duration_months);   -- calendar-month expiry

  update public.purchased_therapy_entitlements
     set activation_date = v_act, expiry_date = v_exp,
         status = case when v_act > v_today then 'scheduled' else 'active' end,
         scheduled_date = case when v_act > v_today then v_act else scheduled_date end,
         updated_by = auth.uid(), updated_at = now()
   where id = p_entitlement_id;

  perform public.write_audit_ex('purchased_therapy_entitlements', p_entitlement_id,
    case when v_act > v_today then 'therapy_scheduled' else 'therapy_activated' end,
    jsonb_build_object('status', e.status),
    jsonb_build_object('activation', v_act, 'expiry', v_exp), 'therapy', p_reason, e.store_id);
end $$;

create or replace function public.reschedule_purchased_therapy(
  p_entitlement_id uuid, p_new_date date, p_reason text
) returns void language plpgsql security definer set search_path = public as $$
declare e public.purchased_therapy_entitlements%rowtype; v_today date := public.sg_today();
begin
  if coalesce(trim(p_reason),'') = '' then raise exception 'A reason is required to change the scheduled date'; end if;
  select * into e from public.purchased_therapy_entitlements where id = p_entitlement_id for update;
  if not found then raise exception 'Entitlement not found'; end if;
  if not public.user_has_store_access(e.store_id) then raise exception 'No access to this store'; end if;
  -- Only BEFORE activation. Scheduled (future) or pending may be rescheduled;
  -- once active, dates are locked.
  if e.status not in ('pending_activation','scheduled') then
    raise exception 'Dates can only be changed before activation'; end if;
  if p_new_date < v_today then raise exception 'Scheduled date cannot be in the past'; end if;
  if p_new_date > e.activation_deadline then
    raise exception 'Scheduled date is past the activation deadline (%)', e.activation_deadline; end if;

  update public.purchased_therapy_entitlements
     set scheduled_date = p_new_date, status = 'scheduled', updated_by = auth.uid(), updated_at = now()
   where id = p_entitlement_id;
  perform public.write_audit_ex('purchased_therapy_entitlements', p_entitlement_id, 'therapy_rescheduled',
    jsonb_build_object('old', e.scheduled_date), jsonb_build_object('new', p_new_date), 'therapy', p_reason, e.store_id);
end $$;

-- Nightly/status refresh: scheduled -> active when the date arrives; active ->
-- expired when the window ends; pending -> expired past deadline.
create or replace function public.refresh_purchased_therapy_statuses()
returns integer language plpgsql security definer set search_path = public as $$
declare v_n integer := 0; v_today date := public.sg_today();
begin
  update public.purchased_therapy_entitlements
     set status = 'active', updated_at = now()
   where status = 'scheduled' and activation_date is not null and activation_date <= v_today;
  get diagnostics v_n = row_count;
  update public.purchased_therapy_entitlements
     set status = 'expired', updated_at = now()
   where status = 'active' and expiry_date is not null and expiry_date < v_today;
  update public.purchased_therapy_entitlements
     set status = 'expired', updated_at = now()
   where status = 'pending_activation' and activation_deadline < v_today;
  return v_n;
end $$;

-- =====================================================================
-- 6. Refund a therapy line — only BEFORE activation. Cancels entitlement +
--    reverses its commission; keeps invoice/payment history; no stock.
-- =====================================================================
create or replace function public.refund_purchased_therapy(p_entitlement_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare e public.purchased_therapy_entitlements%rowtype;
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can refund therapy'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'A refund reason is required'; end if;
  select * into e from public.purchased_therapy_entitlements where id = p_entitlement_id for update;
  if not found then raise exception 'Entitlement not found'; end if;
  if e.status in ('active','expired') then raise exception 'Therapy cannot be refunded after activation'; end if;
  if e.status in ('cancelled','refunded') then raise exception 'Entitlement is already %', e.status; end if;

  update public.purchased_therapy_entitlements
     set status = 'refunded', updated_by = auth.uid(), updated_at = now()
   where id = p_entitlement_id;

  -- Reverse the commission earned on this therapy line (preserve history: mark
  -- reversed, don't delete).
  update public.commissions
     set status = 'reversed', reversal_reason = 'Therapy refunded: ' || p_reason
   where invoice_item_id = e.invoice_item_id and status in ('earned');

  perform public.write_audit_ex('purchased_therapy_entitlements', p_entitlement_id, 'therapy_refunded',
    jsonb_build_object('status', e.status), jsonb_build_object('status','refunded'), 'therapy', p_reason, e.store_id);
end $$;

-- =====================================================================
-- 7. Legacy activation — the ONLY allowed action on legacy entitlements.
--    Everyone with invoice access; respects the existing deadline; no
--    transfer/division/reassignment/date-change/new-qualification.
-- =====================================================================
create or replace function public.activate_legacy_therapy(p_entitlement_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare e public.therapy_entitlements%rowtype; v_today date := public.sg_today();
begin
  select * into e from public.therapy_entitlements where id = p_entitlement_id for update;
  if not found then raise exception 'Legacy entitlement not found'; end if;
  if not public.user_has_store_access(e.store_id) then raise exception 'No access to this store'; end if;
  if e.status <> 'pending_activation' then raise exception 'Only an unactivated legacy entitlement can be activated (currently %)', e.status; end if;
  if v_today > e.activation_deadline then raise exception 'The activation deadline (%) has passed', e.activation_deadline; end if;

  update public.therapy_entitlements set status = 'active' where id = p_entitlement_id;
  perform public.write_audit_ex('therapy_entitlements', p_entitlement_id, 'legacy_therapy_activated',
    jsonb_build_object('status','pending_activation'), jsonb_build_object('status','active'),
    'therapy', 'legacy activation', e.store_id);
end $$;

notify pgrst, 'reload schema';

-- =====================================================================
-- 8. Add a therapy line to an existing UNPAID invoice (Owner/Manager/Admin/
--    Staff-own-store). Non-stock, Member/Non-Member priced, one per package.
--    Kept separate from create_invoice so that large function is untouched.
-- =====================================================================
create or replace function public.add_therapy_line(
  p_invoice_id uuid, p_package_id uuid, p_mode text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_inv public.invoices%rowtype; v_pkg public.unlimited_therapy_packages%rowtype;
        v_ms jsonb; v_member boolean; v_pj jsonb; v_price numeric; v_item_id uuid; v_mode text;
begin
  if public.current_user_role() = 'inventory_manager' then raise exception 'Inventory Manager cannot sell therapy'; end if;
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access to this store'; end if;
  if v_inv.status in ('paid','partially_paid','cancelled','refunded') or coalesce(v_inv.paid_amount,0) > 0 then
    raise exception 'Cannot change a paid or locked invoice'; end if;
  if v_inv.customer_id is null then raise exception 'Invoice has no customer'; end if;

  select * into v_pkg from public.unlimited_therapy_packages where id = p_package_id and deleted_at is null and is_active = true;
  if not found then raise exception 'Therapy package not found or inactive'; end if;

  -- One entitlement per package per active window: block if the customer already
  -- has an active/scheduled entitlement for this package (overlap rule).
  if exists (select 1 from public.purchased_therapy_entitlements
              where customer_id = v_inv.customer_id and package_id = p_package_id
                and status in ('active','scheduled','pending_activation')) then
    raise exception 'This customer already has a current entitlement for this package'; end if;

  -- Resolve applied mode: explicit override, else membership-derived.
  v_ms := public.customer_membership_status(v_inv.customer_id);
  v_member := coalesce((v_ms->>'is_member')::boolean, false)
              or exists (select 1 from public.invoice_items where invoice_id = p_invoice_id and line_kind = 'membership');
  if p_mode in ('member','non_member') then v_member := (p_mode = 'member'); end if;
  v_mode := case when v_member then 'member' else 'non_member' end;

  v_pj := public.therapy_price_for(v_inv.store_id, p_package_id, v_member);
  if not coalesce((v_pj->>'has_price')::boolean,false) then
    raise exception 'Therapy package "%" is missing its % price at this store', v_pkg.name,
      case when v_member then 'Member' else 'Non-Member' end; end if;
  v_price := (v_pj->>'price')::numeric;

  insert into public.invoice_items (
    invoice_id, line_kind, product_id, therapy_package_id, quantity, unit_price, line_total,
    price_mode, price_source, price_source_id, store_id_snapshot,
    member_price_snapshot, non_member_price_snapshot,
    plan_name_snapshot, plan_months_snapshot)
  values (
    p_invoice_id, 'therapy', null, p_package_id, 1, v_price, v_price,
    v_mode, 'therapy', p_package_id, v_inv.store_id,
    (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric,
    v_pkg.name, v_pkg.duration_months)
  returning id into v_item_id;

  update public.invoices set
    subtotal = coalesce((select sum(line_total) from public.invoice_items where invoice_id = p_invoice_id),0)
   where id = p_invoice_id;
  update public.invoices i set total_amount = greatest(0, i.subtotal - coalesce(i.discount_total,0)) where i.id = p_invoice_id;

  perform public.write_audit_ex('invoice_items', v_item_id, 'therapy_line_added',
    null, jsonb_build_object('package', v_pkg.name, 'price', v_price, 'mode', v_mode), 'therapy', null, v_inv.store_id);
  return v_item_id;
end $$;

notify pgrst, 'reload schema';
