-- =====================================================================
-- ENERGIA — STAFF COMMISSION SHARED ACROSS THE STORE'S ACTIVE STAFF
--
-- Before: each paid invoice was split among the people named in "Served by",
-- whatever their role — so an Owner or Manager who served a customer took a
-- share of the staff commission pool.
--
-- After: each paid invoice is divided among the ACTIVE STAFF ASSIGNED TO THAT
-- STORE. Role 'staff' only: Owners, Admins and Managers are excluded, as are
-- inactive accounts and staff assigned elsewhere. "Served by" no longer affects
-- staff commission at all — it remains on the invoice as a record of who served
-- the customer, and still drives affiliate/referral commission, which is
-- untouched.
--
--     each staff member earns:  invoice_total / staff_at_store * rate%
--
-- THE RATE IS RETAINED, deliberately. Dividing sales by headcount with no rate
-- would pay out the ENTIRE revenue as commission — a $7,094 invoice with two
-- staff would owe $3,547 each. If a rate of 100% is genuinely intended it can
-- be set in Settings; the formula does not need changing.
--
-- Historical rows are untouched: staff_commissions is append-only and previously
-- earned commission keeps the basis it was calculated on.
--
-- Additive and idempotent. Run AFTER 100.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- The active staff a store's commission is shared between.
-- Exposed as a function so the UI can show the divisor and the same rule is
-- used everywhere.
-- ---------------------------------------------------------------------
create or replace function public.store_commission_staff(p_store_id uuid)
returns table(staff_id uuid, staff_name text)
language sql stable security definer set search_path to 'public' as $function$
  select p.id, p.full_name
    from public.profiles p
    join public.user_store_assignments usa on usa.user_id = p.id
   where usa.store_id = p_store_id
     and p.role = 'staff'          -- staff only: no owner, admin or manager
     and coalesce(p.is_active, true)
   order by p.full_name
$function$;

create or replace function public.store_commission_staff_count(p_store_id uuid)
returns integer language sql stable security definer set search_path to 'public' as $function$
  select count(*)::integer from public.store_commission_staff(p_store_id)
$function$;

-- ---------------------------------------------------------------------
-- Earn staff commission for a paid invoice.
-- ---------------------------------------------------------------------
create or replace function public.earn_staff_commission(p_invoice_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare
  v_inv public.invoices%rowtype; v_rate numeric; v_n integer;
  v_share numeric; v_paid_date date; v_amt numeric; v_staff record;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return; end if;

  -- Divided among the store's active staff, regardless of who served.
  v_n := public.store_commission_staff_count(v_inv.store_id);
  if v_n = 0 then
    -- Nobody to pay. Recorded rather than silently skipped, so an unassigned
    -- store is visible instead of quietly producing no commission.
    perform public.write_audit('staff_commissions', p_invoice_id,
      'staff_commission_skipped_no_staff', null,
      jsonb_build_object('invoice_no', v_inv.invoice_no, 'store_id', v_inv.store_id));
    return;
  end if;

  select staff_commission_rate into v_rate from public.app_settings where id = true;
  v_rate := coalesce(v_rate, 0);
  if v_rate <= 0 then return; end if;

  v_share := round(1.0 / v_n, 6);
  v_paid_date := coalesce(v_inv.paid_at, now())::date;

  for v_staff in select s.staff_id from public.store_commission_staff(v_inv.store_id) s
  loop
    v_amt := round(v_inv.total_amount * v_share * v_rate / 100.0, 2);
    if v_amt <= 0 then continue; end if;
    insert into public.staff_commissions
      (invoice_id, staff_id, store_id, invoice_total, share_ratio, rate,
       commission_amount, status, invoice_paid_date)
    values (p_invoice_id, v_staff.staff_id, v_inv.store_id, v_inv.total_amount,
       v_share, v_rate, v_amt, 'earned', v_paid_date);
  end loop;

  perform public.write_audit('staff_commissions', p_invoice_id, 'staff_commission_earned', null,
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'staff_count', v_n,
      'rate', v_rate, 'basis', 'store active staff'));
end $function$;

notify pgrst, 'reload schema';
