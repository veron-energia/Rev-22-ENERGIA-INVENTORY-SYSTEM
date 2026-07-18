-- =====================================================================
-- ENERGIA — PHASE 2: MEMBERSHIP FOUNDATION
--
-- Core membership structure. NO invoice-pricing changes in this phase
-- (that is Phase 4). Additive + idempotent. Run AFTER 44_rollback_specphase6a.sql.
--
-- Design decisions (confirmed / stated):
--   * Physical Member ID: entered manually, GLOBALLY unique across all
--     customers, permanently owned by one customer, never reusable.
--   * Internal membership number MEM-000NNNN auto-generated, distinct from
--     the physical Member ID.
--   * Singapore calendar dates. 1-year paid 18 Jul 2026 -> expiry 17 Jul 2027
--     (start + duration - 1 day).
--   * Early renewal starts the day AFTER current expiry (no overlap, no grace).
--   * No membership transfer.
--   * Legacy affiliates migrated to a protected complimentary 1-year plan.
-- =====================================================================

set check_function_bodies = off;

-- =====================================================================
-- 1. MEMBERSHIP PLANS (global)
-- =====================================================================
create table if not exists public.membership_plans (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  duration_months integer not null check (duration_months > 0),
  description text,
  is_active boolean not null default true,
  is_complimentary boolean not null default false,   -- system/legacy plan flag
  is_system boolean not null default false,          -- protected: cannot be sold/deleted via UI
  deleted_at timestamptz,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_mplans_active on public.membership_plans(is_active) where deleted_at is null;

-- =====================================================================
-- 2. STORE-SPECIFIC MEMBERSHIP PRICES
-- =====================================================================
create table if not exists public.membership_plan_store_prices (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.membership_plans(id) on delete cascade,
  store_id uuid not null references public.stores(id),
  membership_fee numeric(12,2) not null default 0 check (membership_fee >= 0),
  available_at_store boolean not null default true,
  is_active boolean not null default true,
  effective_from date,
  deleted_at timestamptz,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (plan_id, store_id)
);
create index if not exists idx_mpsp_plan on public.membership_plan_store_prices(plan_id);
create index if not exists idx_mpsp_store on public.membership_plan_store_prices(store_id);

-- =====================================================================
-- 3. INTERNAL MEMBERSHIP NUMBER SEQUENCE  (MEM-0000125)
-- =====================================================================
create sequence if not exists public.membership_number_seq start 1;

create or replace function public.next_membership_number()
returns text language sql volatile as $$
  select 'MEM-' || lpad(nextval('public.membership_number_seq')::text, 7, '0')
$$;

-- =====================================================================
-- 4. PHYSICAL MEMBER ID — reservations + permanent ownership
--    Two tables so "reserved on an unpaid invoice" and "permanently owned
--    after payment" are distinct, and both enforce global uniqueness.
-- =====================================================================

-- Permanent ownership: one Member ID -> one customer, forever.
create table if not exists public.member_ids (
  member_id text primary key,                       -- the physical card id (manual)
  customer_id uuid not null unique references public.customers(id),
  assigned_at timestamptz not null default now(),
  assigned_by uuid references public.profiles(id)
);

-- Reservation: holds a Member ID against an unpaid membership invoice so no
-- one else can claim it, released if the invoice is cancelled/deleted/line removed.
create table if not exists public.member_id_reservations (
  member_id text primary key,
  customer_id uuid not null references public.customers(id),
  invoice_id uuid references public.invoices(id),
  reserved_at timestamptz not null default now(),
  reserved_by uuid references public.profiles(id)
);
create index if not exists idx_midres_invoice on public.member_id_reservations(invoice_id);
create index if not exists idx_midres_customer on public.member_id_reservations(customer_id);

-- Is a Member ID free to claim? (not permanently owned by someone else,
-- not reserved by someone else)
create or replace function public.member_id_available(p_member_id text, p_customer_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (
    select 1 from public.member_ids m
     where m.member_id = p_member_id and m.customer_id <> p_customer_id
  ) and not exists (
    select 1 from public.member_id_reservations r
     where r.member_id = p_member_id and r.customer_id <> p_customer_id
  )
$$;

-- Reserve a Member ID for a customer (optionally against an invoice).
create or replace function public.reserve_member_id(
  p_member_id text, p_customer_id uuid, p_invoice_id uuid default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_id text;
begin
  if public.current_user_role() is null then raise exception 'No profile'; end if;
  v_id := nullif(trim(p_member_id), '');
  if v_id is null then raise exception 'Member ID is required'; end if;

  -- Owned by someone else?
  if exists (select 1 from public.member_ids where member_id = v_id and customer_id <> p_customer_id) then
    raise exception 'Member ID % is already assigned to another customer', v_id; end if;
  -- Reserved by someone else?
  if exists (select 1 from public.member_id_reservations where member_id = v_id and customer_id <> p_customer_id) then
    raise exception 'Member ID % is currently reserved for another customer', v_id; end if;
  -- Already permanently owned by THIS customer -> nothing to reserve.
  if exists (select 1 from public.member_ids where member_id = v_id and customer_id = p_customer_id) then
    return; end if;

  insert into public.member_id_reservations (member_id, customer_id, invoice_id, reserved_by)
  values (v_id, p_customer_id, p_invoice_id, auth.uid())
  on conflict (member_id) do update
    set customer_id = excluded.customer_id, invoice_id = excluded.invoice_id,
        reserved_at = now(), reserved_by = auth.uid()
    where public.member_id_reservations.customer_id = excluded.customer_id;
end $$;

-- Release a reservation (line removed / invoice cancelled or deleted).
create or replace function public.release_member_id_reservation(p_member_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.member_id_reservations where member_id = nullif(trim(p_member_id),'');
end $$;

create or replace function public.release_member_id_reservations_for_invoice(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.member_id_reservations where invoice_id = p_invoice_id;
end $$;

-- Convert a reservation into permanent ownership (called at payment, Phase 4).
create or replace function public.commit_member_id(p_member_id text, p_customer_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_id text;
begin
  v_id := nullif(trim(p_member_id), '');
  if v_id is null then raise exception 'Member ID is required'; end if;
  if exists (select 1 from public.member_ids where member_id = v_id and customer_id <> p_customer_id) then
    raise exception 'Member ID % belongs to another customer', v_id; end if;

  insert into public.member_ids (member_id, customer_id, assigned_by)
  values (v_id, p_customer_id, auth.uid())
  on conflict (member_id) do nothing;

  -- Clear any reservation now that it is permanent.
  delete from public.member_id_reservations where member_id = v_id;
end $$;

-- Owner/Manager may re-point a Member ID after assignment (correction).
create or replace function public.reassign_member_id(p_member_id text, p_customer_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_id text; v_old uuid;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can edit an assigned Member ID'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'A reason is required'; end if;
  v_id := nullif(trim(p_member_id), '');

  select customer_id into v_old from public.member_ids where member_id = v_id;
  update public.member_ids set customer_id = p_customer_id, assigned_at = now(), assigned_by = auth.uid()
   where member_id = v_id;
  if not found then
    insert into public.member_ids (member_id, customer_id, assigned_by) values (v_id, p_customer_id, auth.uid()); end if;

  perform public.write_audit_ex('member_ids', null, 'member_id_reassigned',
    jsonb_build_object('member_id', v_id, 'old_customer', v_old),
    jsonb_build_object('member_id', v_id, 'new_customer', p_customer_id),
    'membership', p_reason, null);
end $$;

-- =====================================================================
-- 5. DATE MATH (Singapore calendar)
-- =====================================================================
-- Expiry = the day BEFORE the same calendar date N months later (inclusive
-- period). 18 Jul 2026 +12mo -> anchor 18 Jul 2027 -> expiry 17 Jul 2027.
--
-- IMPORTANT (leap-day rule, your decision): compute the anniversary anchor
-- and subtract one day, rather than "start + interval - 1 day". Postgres
-- clamps 29 Feb + 12 months to 28 Feb; the naive form would then subtract
-- again to 27 Feb and shorten a leap-day membership. Anchoring first means a
-- 29 Feb start runs a full year to 28 Feb — the day before its (clamped)
-- anniversary — so no membership is ever short-changed.
create or replace function public.membership_anniversary(p_start date, p_months integer)
returns date language sql immutable as $$
  select (p_start + (p_months || ' months')::interval)::date
$$;

create or replace function public.membership_expiry(p_start date, p_months integer)
returns date language sql immutable as $$
  -- day before the anniversary; for a 29 Feb start the anniversary clamps to
  -- 28 Feb, and we DO NOT subtract below it (that day is the full-period end).
  select case
    when extract(day from p_start) = 29 and extract(month from p_start) = 2
     and extract(day from public.membership_anniversary(p_start, p_months)) = 28
     and extract(month from public.membership_anniversary(p_start, p_months)) = 2
    then public.membership_anniversary(p_start, p_months)          -- 28 Feb, full period
    else public.membership_anniversary(p_start, p_months) - 1       -- normal: day before
  end
$$;

-- Renewal start = day after current expiry (no overlap, no grace).
create or replace function public.membership_renewal_start(p_current_expiry date)
returns date language sql immutable as $$
  select p_current_expiry + 1
$$;

-- =====================================================================
-- 6. CUSTOMER MEMBERSHIPS
-- =====================================================================
create table if not exists public.customer_memberships (
  id uuid primary key default gen_random_uuid(),
  membership_no text not null unique default public.next_membership_number(),
  customer_id uuid not null references public.customers(id),
  plan_id uuid not null references public.membership_plans(id),
  store_id uuid references public.stores(id),               -- nullable (legacy w/o store)
  member_id text,                                            -- physical id (once assigned)

  source text not null default 'sale' check (source in ('sale','complimentary','migration','renewal')),
  invoice_id uuid references public.invoices(id),
  invoice_item_id uuid,
  fee_snapshot numeric(12,2) not null default 0,

  start_date date,
  expiry_date date,
  status text not null default 'pending_payment'
    check (status in ('pending_payment','active','expiring_soon','expired','cancelled','suspended')),

  is_complimentary boolean not null default false,
  is_renewal boolean not null default false,
  previous_membership_id uuid references public.customer_memberships(id),

  activated_at timestamptz,
  cancelled_at timestamptz, cancel_reason text,
  suspended_at timestamptz, suspend_reason text,

  deleted_at timestamptz,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_cmemb_customer on public.customer_memberships(customer_id);
create index if not exists idx_cmemb_status on public.customer_memberships(status) where deleted_at is null;
create index if not exists idx_cmemb_member_id on public.customer_memberships(member_id);
-- At most ONE non-terminal membership per customer (no overlapping active/pending).
create unique index if not exists uq_cmemb_one_live
  on public.customer_memberships(customer_id)
  where deleted_at is null and status in ('pending_payment','active','expiring_soon','suspended');

-- Effective status from dates (Active / Expiring Soon / Expired), given the
-- stored status. Cancelled/suspended/pending are returned unchanged.
create or replace function public.membership_effective_status(
  p_status text, p_start date, p_expiry date, p_soon_days integer default 90
) returns text language sql immutable as $$
  select case
    when p_status in ('cancelled','suspended','pending_payment') then p_status
    when p_expiry is null or p_start is null then p_status
    when public.sg_today() > p_expiry then 'expired'
    when public.sg_today() >= (p_expiry - p_soon_days) then 'expiring_soon'
    else 'active'
  end
$$;

-- =====================================================================
-- 7. RLS
-- =====================================================================
alter table public.membership_plans enable row level security;
alter table public.membership_plan_store_prices enable row level security;
alter table public.customer_memberships enable row level security;
alter table public.member_ids enable row level security;
alter table public.member_id_reservations enable row level security;

-- Plans + prices: everyone authenticated reads; only Owner/Manager writes.
drop policy if exists "read plans" on public.membership_plans;
create policy "read plans" on public.membership_plans for select to authenticated using (true);
drop policy if exists "write plans" on public.membership_plans;
create policy "write plans" on public.membership_plans for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

drop policy if exists "read plan prices" on public.membership_plan_store_prices;
create policy "read plan prices" on public.membership_plan_store_prices for select to authenticated using (true);
drop policy if exists "write plan prices" on public.membership_plan_store_prices;
create policy "write plan prices" on public.membership_plan_store_prices for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

-- Memberships: store-scoped read; write via SECURITY DEFINER functions only
-- (so no broad table-write policy here — matches the survey pattern).
drop policy if exists "read memberships" on public.customer_memberships;
create policy "read memberships" on public.customer_memberships for select to authenticated
  using (public.is_manager_or_above() or store_id is null or public.user_has_store_access(store_id));

-- Member IDs + reservations: readable by staff (needed to validate uniqueness
-- in the UI); writes happen through the functions above.
drop policy if exists "read member ids" on public.member_ids;
create policy "read member ids" on public.member_ids for select to authenticated using (true);
drop policy if exists "read member id reservations" on public.member_id_reservations;
create policy "read member id reservations" on public.member_id_reservations for select to authenticated using (true);

-- =====================================================================
-- 8. PLAN MANAGEMENT (Owner/Manager) — create / edit / soft-delete / price
-- =====================================================================
create or replace function public.upsert_membership_plan(
  p_id uuid, p_name text, p_duration_months integer, p_description text, p_is_active boolean
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can manage plans'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'Plan name is required'; end if;
  if coalesce(p_duration_months,0) <= 0 then raise exception 'Duration must be at least 1 month'; end if;

  if p_id is null then
    insert into public.membership_plans (name, duration_months, description, is_active, created_by, updated_by)
    values (trim(p_name), p_duration_months, nullif(trim(coalesce(p_description,'')),''), coalesce(p_is_active,true), auth.uid(), auth.uid())
    returning id into v_id;
  else
    -- Protected system plans (e.g. the legacy complimentary plan) can't be edited here.
    if exists (select 1 from public.membership_plans where id = p_id and is_system) then
      raise exception 'This is a protected system plan and cannot be edited'; end if;
    update public.membership_plans
       set name = trim(p_name), duration_months = p_duration_months,
           description = nullif(trim(coalesce(p_description,'')),''),
           is_active = coalesce(p_is_active,true), updated_by = auth.uid(), updated_at = now()
     where id = p_id returning id into v_id;
  end if;

  perform public.write_audit_ex('membership_plans', v_id,
    case when p_id is null then 'membership_plan_created' else 'membership_plan_updated' end,
    null, jsonb_build_object('name', p_name, 'months', p_duration_months), 'membership', null, null);
  return v_id;
end $$;

create or replace function public.set_membership_plan_price(
  p_plan_id uuid, p_store_id uuid, p_fee numeric, p_available boolean
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can set plan prices'; end if;
  if coalesce(p_fee,0) < 0 then raise exception 'Fee cannot be negative'; end if;

  insert into public.membership_plan_store_prices (plan_id, store_id, membership_fee, available_at_store, created_by, updated_by)
  values (p_plan_id, p_store_id, p_fee, coalesce(p_available,true), auth.uid(), auth.uid())
  on conflict (plan_id, store_id) do update
    set membership_fee = excluded.membership_fee, available_at_store = excluded.available_at_store,
        updated_by = auth.uid(), updated_at = now(), deleted_at = null;

  perform public.write_audit_ex('membership_plan_store_prices', p_plan_id, 'membership_price_set',
    null, jsonb_build_object('store', p_store_id, 'fee', p_fee, 'available', p_available), 'membership', null, p_store_id);
end $$;

create or replace function public.soft_delete_membership_plan(p_id uuid, p_restore boolean default false)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can delete plans'; end if;
  if exists (select 1 from public.membership_plans where id = p_id and is_system) then
    raise exception 'Protected system plans cannot be deleted'; end if;
  update public.membership_plans
     set deleted_at = case when p_restore then null else now() end, updated_by = auth.uid(), updated_at = now()
   where id = p_id;
  perform public.write_audit_ex('membership_plans', p_id,
    case when p_restore then 'membership_plan_restored' else 'membership_plan_deleted' end,
    null, null, 'membership', null, null);
end $$;

-- =====================================================================
-- 9. PROTECTED LEGACY COMPLIMENTARY PLAN + affiliate migration
-- =====================================================================
insert into public.membership_plans (name, duration_months, description, is_active, is_complimentary, is_system)
select 'Legacy Affiliate Complimentary Membership – 1 Year', 12,
       'Protected system plan. One year, zero price, no invoice, no commission. Used only to migrate pre-existing affiliates.',
       true, true, true
where not exists (
  select 1 from public.membership_plans
   where is_system and name = 'Legacy Affiliate Complimentary Membership – 1 Year');

-- Idempotent migration: one complimentary 1-year membership per distinct
-- existing affiliate (customers referenced by customers.referred_by).
do $$
declare v_plan uuid; v_today date := public.sg_today();
begin
  select id into v_plan from public.membership_plans
    where is_system and name = 'Legacy Affiliate Complimentary Membership – 1 Year' limit 1;
  if v_plan is null then return; end if;

  insert into public.customer_memberships (
    customer_id, plan_id, store_id, source, is_complimentary, fee_snapshot,
    start_date, expiry_date, status, activated_at, created_by)
  select aff.customer_id, v_plan,
         -- store from their most recent referred PAID invoice, else null
         (select i.store_id from public.invoices i
           join public.customers c2 on c2.id = i.customer_id
           where c2.referred_by = aff.customer_id and i.status = 'paid' and i.deleted_at is null
           order by i.paid_at desc nulls last limit 1),
         'migration', true, 0,
         v_today, public.membership_expiry(v_today, 12), 'active', now(), null
  from (select distinct referred_by as customer_id
          from public.customers where referred_by is not null) aff
  where not exists (
    -- skip if this affiliate already has a complimentary/migration membership
    select 1 from public.customer_memberships m
     where m.customer_id = aff.customer_id and m.plan_id = v_plan and m.deleted_at is null)
    and exists (select 1 from public.customers c where c.id = aff.customer_id and c.deleted_at is null);
end $$;

notify pgrst, 'reload schema';
