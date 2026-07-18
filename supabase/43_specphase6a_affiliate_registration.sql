-- =====================================================================
-- ENERGIA — NEW SPEC PHASE 6A: Affiliate registration + $5 fee + offset
--
-- You asked me to choose the best approach and to automate it.
--
-- WHAT THIS DOES
--   * Registers a customer as an affiliate (they can then earn referral
--     commission — gating lands in 6B with the rate engine).
--   * Charges a registration fee (default $5, configurable — not hardcoded).
--   * AUTOMATICALLY offsets that fee if they buy on the same Singapore day.
--     Automatic in BOTH directions:
--       - register first, buy later that day  -> a trigger offsets it
--       - buy first, register later that day  -> checked at registration
--     So staff never have to remember to waive it.
--
-- FEE STATES: payable -> offset | paid | waived
--   If the $5 was already COLLECTED and they then buy the same day, the fee
--   becomes 'offset' and a $5 credit is recorded as owed back, rather than
--   silently keeping their money.
--
-- Additive + idempotent. Run AFTER 42_specphase5d_consultant_permissions.sql.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Settings — the fee is data, not a magic number in code.
-- ---------------------------------------------------------------------
alter table public.app_settings add column if not exists affiliate_registration_fee numeric(12,2) not null default 5.00;
alter table public.app_settings add column if not exists affiliate_same_day_offset boolean not null default true;

create or replace function public.affiliate_fee() returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select affiliate_registration_fee from public.app_settings where id), 5.00)
$$;

create or replace function public.affiliate_offset_enabled() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select affiliate_same_day_offset from public.app_settings where id), true)
$$;

-- ---------------------------------------------------------------------
-- 2. Registrations. One per customer.
-- ---------------------------------------------------------------------
create table if not exists public.affiliate_registrations (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null unique references public.customers(id),
  store_id uuid not null references public.stores(id),

  fee_amount numeric(12,2) not null default 0,
  fee_status text not null default 'payable' check (fee_status in ('payable','paid','offset','waived')),
  fee_paid_at timestamptz,
  offset_invoice_id uuid references public.invoices(id),
  offset_at timestamptz,
  credit_due numeric(12,2) not null default 0,   -- fee collected then offset -> owed back

  status text not null default 'active' check (status in ('active','suspended')),
  registered_at timestamptz not null default now(),
  registered_by uuid references public.profiles(id),
  suspended_at timestamptz,
  suspend_reason text,
  notes text
);
create index if not exists idx_affreg_customer on public.affiliate_registrations(customer_id);
create index if not exists idx_affreg_store on public.affiliate_registrations(store_id);

alter table public.affiliate_registrations enable row level security;
drop policy if exists "read affiliate registrations" on public.affiliate_registrations;
create policy "read affiliate registrations" on public.affiliate_registrations for select to authenticated
  using (public.is_manager_or_above() or public.user_has_store_access(store_id));

-- ---------------------------------------------------------------------
-- 3. Is this customer a live affiliate? (6B will gate commission on this.)
-- ---------------------------------------------------------------------
create or replace function public.is_registered_affiliate(p_customer_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.affiliate_registrations r
    where r.customer_id = p_customer_id and r.status = 'active')
$$;

-- ---------------------------------------------------------------------
-- 4. The offset rule, in ONE place so both directions agree.
--    Offsets the fee when the customer has a paid invoice on the same
--    Singapore calendar day as their registration.
-- ---------------------------------------------------------------------
create or replace function public.apply_affiliate_fee_offset(p_customer_id uuid, p_invoice_id uuid default null)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_r public.affiliate_registrations%rowtype; v_inv public.invoices%rowtype; v_reg_date date;
begin
  if not public.affiliate_offset_enabled() then return false; end if;

  select * into v_r from public.affiliate_registrations
   where customer_id = p_customer_id and fee_status in ('payable','paid') for update;
  if not found then return false; end if;

  v_reg_date := (v_r.registered_at at time zone 'Asia/Singapore')::date;

  if p_invoice_id is not null then
    select * into v_inv from public.invoices where id = p_invoice_id;
  else
    -- Registration happened after the purchase: look for a same-day paid invoice.
    select * into v_inv from public.invoices i
     where i.customer_id = p_customer_id and i.status = 'paid' and i.paid_at is not null
       and i.deleted_at is null
       and (i.paid_at at time zone 'Asia/Singapore')::date = v_reg_date
     order by i.paid_at limit 1;
  end if;
  if v_inv.id is null then return false; end if;
  if v_inv.status <> 'paid' or v_inv.paid_at is null then return false; end if;
  if (v_inv.paid_at at time zone 'Asia/Singapore')::date <> v_reg_date then return false; end if;

  update public.affiliate_registrations
     set fee_status = 'offset',
         offset_invoice_id = v_inv.id,
         offset_at = now(),
         -- If we already took the $5, it is now owed back rather than kept.
         credit_due = case when v_r.fee_status = 'paid' then v_r.fee_amount else 0 end
   where id = v_r.id;

  perform public.write_audit_ex('affiliate_registrations', v_r.id, 'affiliate_fee_offset',
    jsonb_build_object('fee_status', v_r.fee_status),
    jsonb_build_object('fee_status', 'offset', 'invoice_no', v_inv.invoice_no,
                       'credit_due', case when v_r.fee_status = 'paid' then v_r.fee_amount else 0 end),
    'affiliates', 'Same-day purchase', v_r.store_id);
  return true;
end $$;

-- ---------------------------------------------------------------------
-- 5. Automation: when an invoice becomes paid, offset any same-day fee.
--    A trigger means no existing function had to be rewritten and no
--    code path can forget to do it.
-- ---------------------------------------------------------------------
create or replace function public.trg_affiliate_fee_offset() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'paid' and new.paid_at is not null
     and (tg_op = 'INSERT' or old.status is distinct from 'paid') then
    perform public.apply_affiliate_fee_offset(new.customer_id, new.id);
  end if;
  return null;
end $$;

drop trigger if exists affiliate_fee_offset_trg on public.invoices;
create trigger affiliate_fee_offset_trg
  after insert or update of status on public.invoices
  for each row execute function public.trg_affiliate_fee_offset();

-- ---------------------------------------------------------------------
-- 6. Register an affiliate. Staff may register (they take the money at
--    the counter), scoped to their store.
-- ---------------------------------------------------------------------
create or replace function public.register_affiliate(
  p_customer_id uuid,
  p_store_id uuid,
  p_fee_collected boolean default false,
  p_waive boolean default false,
  p_notes text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_fee numeric; v_status text; v_offset boolean; v_c public.customers%rowtype;
begin
  if public.current_user_role() is null then raise exception 'No profile for current user'; end if;
  if public.current_user_role() = 'inventory_manager' then
    raise exception 'Inventory Manager cannot register affiliates'; end if;
  if not public.user_has_store_access(p_store_id) then raise exception 'No access to that store'; end if;

  select * into v_c from public.customers where id = p_customer_id and deleted_at is null;
  if not found then raise exception 'Customer not found'; end if;
  if exists (select 1 from public.affiliate_registrations where customer_id = p_customer_id) then
    raise exception 'This customer is already registered as an affiliate'; end if;
  if p_waive and not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can waive the registration fee'; end if;

  v_fee := public.affiliate_fee();
  v_status := case when p_waive then 'waived' when p_fee_collected then 'paid' else 'payable' end;

  insert into public.affiliate_registrations
    (customer_id, store_id, fee_amount, fee_status, fee_paid_at, registered_by, notes)
  values (p_customer_id, p_store_id, v_fee, v_status,
          case when p_fee_collected then now() else null end, auth.uid(), nullif(trim(coalesce(p_notes,'')),''))
  returning id into v_id;

  perform public.write_audit_ex('affiliate_registrations', v_id, 'affiliate_registered', null,
    jsonb_build_object('customer', v_c.full_name, 'fee', v_fee, 'fee_status', v_status),
    'affiliates', p_notes, p_store_id);

  -- Bought earlier today? Offset immediately.
  v_offset := public.apply_affiliate_fee_offset(p_customer_id, null);

  return jsonb_build_object('success', true, 'id', v_id, 'fee', v_fee,
    'fee_status', case when v_offset then 'offset' else v_status end, 'offset_applied', v_offset);
end $$;

-- ---------------------------------------------------------------------
-- 7. Mark the fee collected / settle the credit / suspend / reactivate.
-- ---------------------------------------------------------------------
create or replace function public.set_affiliate_fee_paid(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_r public.affiliate_registrations%rowtype;
begin
  select * into v_r from public.affiliate_registrations where id = p_id;
  if not found then raise exception 'Registration not found'; end if;
  if not (public.is_manager_or_above() or public.user_has_store_access(v_r.store_id)) then
    raise exception 'No access to that store'; end if;
  if v_r.fee_status <> 'payable' then raise exception 'That fee is not outstanding'; end if;

  update public.affiliate_registrations set fee_status = 'paid', fee_paid_at = now() where id = p_id;
  perform public.write_audit_ex('affiliate_registrations', p_id, 'affiliate_fee_paid',
    jsonb_build_object('fee_status','payable'), jsonb_build_object('fee_status','paid'),
    'affiliates', null, v_r.store_id);
end $$;

create or replace function public.settle_affiliate_credit(p_id uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_r public.affiliate_registrations%rowtype;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can settle a credit'; end if;
  select * into v_r from public.affiliate_registrations where id = p_id;
  if not found then raise exception 'Registration not found'; end if;
  if v_r.credit_due <= 0 then raise exception 'There is no credit outstanding'; end if;

  update public.affiliate_registrations set credit_due = 0 where id = p_id;
  perform public.write_audit_ex('affiliate_registrations', p_id, 'affiliate_credit_settled',
    jsonb_build_object('credit_due', v_r.credit_due), jsonb_build_object('credit_due', 0),
    'affiliates', p_note, v_r.store_id);
end $$;

create or replace function public.set_affiliate_status(p_id uuid, p_status text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_r public.affiliate_registrations%rowtype;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can suspend or reactivate an affiliate'; end if;
  if p_status not in ('active','suspended') then raise exception 'Invalid status'; end if;
  if p_status = 'suspended' and coalesce(trim(p_reason),'') = '' then
    raise exception 'A reason is required to suspend an affiliate'; end if;
  select * into v_r from public.affiliate_registrations where id = p_id;
  if not found then raise exception 'Registration not found'; end if;

  update public.affiliate_registrations
     set status = p_status,
         suspended_at = case when p_status = 'suspended' then now() else null end,
         suspend_reason = case when p_status = 'suspended' then trim(p_reason) else null end
   where id = p_id;
  perform public.write_audit_ex('affiliate_registrations', p_id, 'affiliate_status_changed',
    jsonb_build_object('status', v_r.status), jsonb_build_object('status', p_status),
    'affiliates', p_reason, v_r.store_id);
end $$;

-- ---------------------------------------------------------------------
-- 8. Grandfather existing referrers so nobody loses commission when 6B
--    starts requiring registration. Fee waived — they never owed one.
-- ---------------------------------------------------------------------
insert into public.affiliate_registrations (customer_id, store_id, fee_amount, fee_status, status, notes)
select distinct c.referred_by,
       (select id from public.stores where deleted_at is null order by created_at limit 1),
       0, 'waived', 'active', 'Grandfathered — referring before affiliate registration existed'
from public.customers c
where c.referred_by is not null
  and not exists (select 1 from public.affiliate_registrations r where r.customer_id = c.referred_by)
  and exists (select 1 from public.stores where deleted_at is null)
on conflict (customer_id) do nothing;

notify pgrst, 'reload schema';
