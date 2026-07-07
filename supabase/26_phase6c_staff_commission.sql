-- =====================================================================
-- ENERGIA — PHASE 6C (part 1): Service staff + staff commission engine
--
-- A second, parallel commission system alongside the customer-referrer
-- one. When an invoice is created, one or more SERVICE STAFF (Owner /
-- Manager / Staff only) can be attached. When the invoice is fully paid,
-- each service staff earns an EQUAL SHARE of a configurable commission
-- rate on the invoice's paid (after-discount) total. Reversed on refund/
-- cancel. Paid out monthly per staff, mirroring the referrer payout flow.
--
-- Equal sharing is the default and is implemented so the split can be
-- changed later (share_ratio column per row; today always equal).
--
-- Additive + idempotent. Run AFTER 25_phase6b_customer_fields.sql.
-- =====================================================================

set check_function_bodies = off;

-- Reuse the commission_status enum from 5B ('earned','reversed','paid').

-- ---------------------------------------------------------------------
-- 0. Config: the staff commission rate (percent of the invoice's paid
--    after-discount total, split equally among service staff).
--    A one-row settings table so it is changeable without code.
-- ---------------------------------------------------------------------
create table if not exists public.app_settings (
  id boolean primary key default true check (id),   -- single row
  staff_commission_rate numeric(6,3) not null default 3.0,
  updated_at timestamptz not null default now()
);
insert into public.app_settings (id) values (true) on conflict (id) do nothing;

alter table public.app_settings enable row level security;
drop policy if exists "read settings" on public.app_settings;
create policy "read settings" on public.app_settings for select to authenticated using (true);
drop policy if exists "write settings" on public.app_settings;
create policy "write settings" on public.app_settings for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

-- ---------------------------------------------------------------------
-- 1. Service-staff attached to an invoice (many per invoice).
-- ---------------------------------------------------------------------
create table if not exists public.invoice_service_staff (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  staff_id uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(invoice_id, staff_id)
);
create index if not exists idx_iss_invoice on public.invoice_service_staff(invoice_id);
create index if not exists idx_iss_staff on public.invoice_service_staff(staff_id);

alter table public.invoice_service_staff enable row level security;
drop policy if exists "read invoice service staff" on public.invoice_service_staff;
create policy "read invoice service staff" on public.invoice_service_staff for select to authenticated
  using (exists (select 1 from public.invoices i where i.id = invoice_id and public.user_has_store_access(i.store_id)));

-- ---------------------------------------------------------------------
-- 2. Staff commission ledger (mirrors `commissions`, but per staff).
-- ---------------------------------------------------------------------
create table if not exists public.staff_commissions (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id),
  staff_id uuid not null references public.profiles(id),
  store_id uuid references public.stores(id),
  invoice_total numeric(12,2) not null default 0,   -- paid after-discount total
  share_ratio numeric(8,6) not null default 0,      -- this staff's share (equal today)
  rate numeric(6,3) not null default 0,             -- % applied
  commission_amount numeric(12,2) not null default 0,
  status commission_status not null default 'earned',
  invoice_paid_date date,
  payout_id uuid,
  reversed_at timestamptz,
  reversal_reason text,
  created_at timestamptz not null default now()
);
create index if not exists idx_sc_staff on public.staff_commissions(staff_id);
create index if not exists idx_sc_invoice on public.staff_commissions(invoice_id);
create index if not exists idx_sc_status on public.staff_commissions(status);

alter table public.staff_commissions enable row level security;
drop policy if exists "read staff commissions" on public.staff_commissions;
create policy "read staff commissions" on public.staff_commissions for select to authenticated
  using (public.is_manager_or_above() or staff_id = auth.uid());

-- ---------------------------------------------------------------------
-- 3. Staff commission payouts (monthly, per staff).
-- ---------------------------------------------------------------------
create table if not exists public.staff_commission_payouts (
  id uuid primary key default gen_random_uuid(),
  payout_month date not null,
  staff_id uuid not null references public.profiles(id),
  total_amount numeric(12,2) not null default 0,
  payment_method_id uuid references public.payment_methods(id),
  reference text,
  notes text,
  status text not null default 'paid',
  paid_by uuid references public.profiles(id),
  paid_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists idx_scp_staff on public.staff_commission_payouts(staff_id);

alter table public.staff_commission_payouts enable row level security;
drop policy if exists "read staff payouts" on public.staff_commission_payouts;
create policy "read staff payouts" on public.staff_commission_payouts for select to authenticated
  using (public.is_manager_or_above() or staff_id = auth.uid());

-- ---------------------------------------------------------------------
-- 4. Earn staff commission for a fully-paid invoice (equal split).
--    Called from pay_invoice right after referrer commission.
-- ---------------------------------------------------------------------
create or replace function public.earn_staff_commission(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_rate numeric; v_n integer;
  v_share numeric; v_paid_date date; v_amt numeric; v_staff record;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return; end if;

  select count(*) into v_n from public.invoice_service_staff where invoice_id = p_invoice_id;
  if v_n = 0 then return; end if;

  select staff_commission_rate into v_rate from public.app_settings where id = true;
  v_rate := coalesce(v_rate, 0);
  if v_rate <= 0 then return; end if;

  v_share := round(1.0 / v_n, 6);
  v_paid_date := coalesce(v_inv.paid_at, now())::date;

  for v_staff in select staff_id from public.invoice_service_staff where invoice_id = p_invoice_id
  loop
    v_amt := round(v_inv.total_amount * v_share * v_rate / 100.0, 2);
    if v_amt <= 0 then continue; end if;
    insert into public.staff_commissions
      (invoice_id, staff_id, store_id, invoice_total, share_ratio, rate, commission_amount, status, invoice_paid_date)
    values (p_invoice_id, v_staff.staff_id, v_inv.store_id, v_inv.total_amount, v_share, v_rate, v_amt, 'earned', v_paid_date);
  end loop;

  perform public.write_audit('staff_commissions', p_invoice_id, 'staff_commission_earned', null,
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'staff_count', v_n, 'rate', v_rate));
end; $$;

-- ---------------------------------------------------------------------
-- 5. Reverse staff commission (refund / cancel). Called alongside the
--    referrer reverse_invoice_commission.
-- ---------------------------------------------------------------------
create or replace function public.reverse_staff_commission(p_invoice_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.staff_commissions
    set status = 'reversed', reversed_at = now(), reversal_reason = coalesce(p_reason, 'invoice reversed')
    where invoice_id = p_invoice_id and status = 'earned';
  perform public.write_audit('staff_commissions', p_invoice_id, 'staff_commission_reversed', null,
    jsonb_build_object('reason', p_reason));
end; $$;

-- ---------------------------------------------------------------------
-- 6. Monthly staff payout (mirrors create_commission_payout).
-- ---------------------------------------------------------------------
create or replace function public.create_staff_commission_payout(
  p_staff_id uuid, p_month date, p_payment_method_id uuid,
  p_reference text default null, p_notes text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_month_start date := date_trunc('month', p_month)::date;
  v_month_end date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  v_total numeric := 0; v_payout_id uuid;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can mark staff commission paid'; end if;

  select coalesce(sum(commission_amount), 0) into v_total
    from public.staff_commissions
    where staff_id = p_staff_id and status = 'earned' and payout_id is null
      and invoice_paid_date between v_month_start and v_month_end;

  if v_total <= 0 then raise exception 'No unpaid staff commission for that staff in that month'; end if;

  insert into public.staff_commission_payouts
    (payout_month, staff_id, total_amount, payment_method_id, reference, notes, status, paid_by)
  values (v_month_start, p_staff_id, v_total, p_payment_method_id, p_reference, p_notes, 'paid', auth.uid())
  returning id into v_payout_id;

  update public.staff_commissions
    set status = 'paid', payout_id = v_payout_id
    where staff_id = p_staff_id and status = 'earned' and payout_id is null
      and invoice_paid_date between v_month_start and v_month_end;

  perform public.write_audit('staff_commission_payouts', v_payout_id, 'staff_commission_paid', null,
    jsonb_build_object('staff_id', p_staff_id, 'month', v_month_start, 'total', v_total));
  return v_payout_id;
end; $$;

notify pgrst, 'reload schema';
