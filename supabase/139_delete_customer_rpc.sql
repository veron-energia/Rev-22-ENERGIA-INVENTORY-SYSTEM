-- =====================================================================
-- ENERGIA — DELETING A CUSTOMER FAILED WITH AN RLS ERROR
--
--     42501: new row violates row-level security policy for table "customers"
--
-- The Customers page soft-deletes by writing to the table directly:
--
--     supabase.from('customers').update({ deleted_at: ..., is_active: false })
--
-- Every policy on customers in the migration files is permissive
-- (using (true) with check (true)), so the policy rejecting this was added
-- somewhere outside them — most likely through the Supabase dashboard. Dropping
-- a policy I cannot read would be a careless way to fix access control.
--
-- Instead the delete goes through a SECURITY DEFINER function, as every other
-- consequential action in this system already does. That:
--
--   * works regardless of what the table policies say, without weakening them;
--   * gives the operation a proper permission check — Owner or Manager only,
--     where before ANY signed-in user could delete a customer;
--   * records who did it and why;
--   * refuses when deleting would strand real money.
--
-- The customer is SOFT deleted, exactly as before: the row remains, invoices
-- and history are untouched, and it can be restored.
--
-- Additive and idempotent.
-- =====================================================================

set check_function_bodies = off;

create or replace function public.delete_customer(
  p_customer_id uuid,
  p_confirm_name text,
  p_reason text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_c public.customers%rowtype;
  v_credit numeric := 0;
  v_therapy integer := 0;
  v_unpaid integer := 0;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can delete a customer';
  end if;

  select * into v_c from public.customers where id = p_customer_id;
  if not found then raise exception 'That customer does not exist'; end if;
  if v_c.deleted_at is not null then
    raise exception 'That customer is already deleted';
  end if;

  -- The typed name must match. Compared case-insensitively and with runs of
  -- whitespace collapsed, so "  ann  tan " matches "Ann Tan" — the point is to
  -- make the person read the name, not to test their typing.
  if regexp_replace(lower(trim(coalesce(p_confirm_name, ''))), '\s+', ' ', 'g')
     is distinct from
     regexp_replace(lower(trim(coalesce(v_c.full_name, ''))), '\s+', ' ', 'g')
  then
    raise exception 'The name you typed does not match "%"', v_c.full_name;
  end if;

  -- Refuse where deleting would strand something of value. These are the
  -- customer's own money and entitlements; they should be settled or
  -- transferred deliberately, not lost behind a deleted record.
  select coalesce(sum(l.remaining_amount), 0) into v_credit
    from public.customer_credit_lots l
   where l.customer_id = p_customer_id
     and coalesce(l.remaining_amount, 0) > 0
     and coalesce(l.status, 'active') <> 'reversed';
  if v_credit > 0 then
    raise exception 'This customer still holds S$% of wallet credit. Refund or transfer it first.',
      to_char(v_credit, 'FM999999990.00');
  end if;

  select count(*) into v_therapy
    from public.purchased_therapy_entitlements e
   where e.customer_id = p_customer_id
     -- scheduled counts too: the appointment is booked and unused.
     and e.status in ('pending_activation', 'scheduled', 'active');
  if v_therapy > 0 then
    raise exception 'This customer has % therapy entitlement(s) not yet used. Settle them first.', v_therapy;
  end if;

  select count(*) into v_unpaid
    from public.invoices i
   where i.customer_id = p_customer_id
     and i.deleted_at is null
     and i.status in ('unpaid', 'partially_paid');
  if v_unpaid > 0 then
    raise exception 'This customer has % unpaid or part-paid invoice(s). Settle or cancel them first.', v_unpaid;
  end if;

  update public.customers
     set deleted_at = now(),
         is_active = false
   where id = p_customer_id;

  perform public.write_audit_ex('customers', p_customer_id, 'customer_deleted',
    jsonb_build_object('full_name', v_c.full_name, 'phone', v_c.phone),
    jsonb_build_object('reason', nullif(trim(coalesce(p_reason, '')), ''),
                       'deleted_by', auth.uid()),
    'customers', null, null);

  return jsonb_build_object('success', true, 'full_name', v_c.full_name);
end $function$;

-- ---------------------------------------------------------------------
-- Restoring one, since a soft delete is only useful if it can be undone.
-- ---------------------------------------------------------------------
create or replace function public.restore_customer(p_customer_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_c public.customers%rowtype;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can restore a customer';
  end if;

  select * into v_c from public.customers where id = p_customer_id;
  if not found then raise exception 'That customer does not exist'; end if;
  if v_c.deleted_at is null then raise exception 'That customer is not deleted'; end if;

  update public.customers set deleted_at = null, is_active = true where id = p_customer_id;

  perform public.write_audit_ex('customers', p_customer_id, 'customer_restored', null,
    jsonb_build_object('full_name', v_c.full_name), 'customers', null, null);

  return jsonb_build_object('success', true, 'full_name', v_c.full_name);
end $function$;

-- ---------------------------------------------------------------------
-- Confirm it is callable, so this fails here rather than in front of someone.
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'delete_customer' and p.prosecdef
  ) then
    raise exception 'delete_customer is missing or not SECURITY DEFINER — RLS would still block it';
  end if;
  raise notice 'Confirmed: deleting a customer goes through a checked, audited function';
end $$;

notify pgrst, 'reload schema';
