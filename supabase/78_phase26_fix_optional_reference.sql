-- =====================================================================
-- ENERGIA — PHASE 26 FIX: THE CREDIT REFERENCE NUMBER IS OPTIONAL
--
-- A reference number is no longer required when entering an opening balance
-- or an adjustment. When one IS supplied it must still be unique, so a
-- mistyped duplicate is caught. The unique indexes already ignore nulls.
--
-- Additive and idempotent. Run AFTER 77.
-- =====================================================================

set check_function_bodies = off;

alter table public.customer_credit_adjustments alter column reference_no drop not null;

create or replace function public.add_legacy_credit(
  p_customer_id uuid, p_category text, p_amount numeric,
  p_original_purchase_date date, p_store_id uuid, p_reference_no text,
  p_note text, p_effective_date date default null, p_approved_by uuid default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare v_lot uuid; v_approver uuid; v_ref text := nullif(trim(coalesce(p_reference_no,'')),'');
begin
  if not public.can_manage_customer_credit() then
    raise exception 'Only an Owner or Manager can enter old-client balances';
  end if;
  if p_category not in ('paid','bonus','legacy') then
    raise exception 'An opening balance may only be Paid, Bonus or Legacy credit';
  end if;
  if p_customer_id is null then raise exception 'A customer is required'; end if;
  if coalesce(p_amount,0) <= 0 then raise exception 'Amount must be greater than zero'; end if;
  if p_original_purchase_date is null then raise exception 'The original purchase date is required'; end if;
  if p_store_id is null then raise exception 'The store is required'; end if;
  if coalesce(trim(p_note),'') = '' then raise exception 'A supporting note is required'; end if;

  v_approver := coalesce(p_approved_by, auth.uid());

  -- A reference is optional, but must be unique when given.
  if v_ref is not null and exists (
        select 1 from public.customer_credit_lots
         where source_type = 'manual_legacy' and reference_no = v_ref) then
    raise exception 'Reference number "%" has already been used for a manual legacy entry', v_ref;
  end if;

  v_lot := public.grant_customer_credit(
    p_customer_id, p_category, p_amount, 'manual_legacy', null, p_store_id,
    coalesce(p_effective_date, p_original_purchase_date), v_ref,
    'Old-client opening balance', p_note, p_original_purchase_date, v_approver);
  return v_lot;
end $function$;

create or replace function public.adjust_customer_credit(
  p_customer_id uuid, p_category text, p_direction text, p_amount numeric,
  p_reason text, p_reference_no text, p_effective_date date default null,
  p_note text default null, p_store_id uuid default null, p_approved_by uuid default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare
  v_wallet uuid; v_lot uuid; v_entry uuid; v_adj uuid; v_eff date;
  v_left numeric; v_take numeric; v_l record; v_approver uuid;
  v_ref text := nullif(trim(coalesce(p_reference_no,'')),'');
begin
  if not public.can_manage_customer_credit() then
    raise exception 'Only an Owner or Manager can adjust customer credit';
  end if;
  if p_direction not in ('increase','decrease') then raise exception 'Direction must be increase or decrease'; end if;
  if coalesce(p_amount,0) <= 0 then raise exception 'Amount must be greater than zero'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'A reason is required'; end if;

  v_eff := coalesce(p_effective_date, public.sg_today());
  v_approver := coalesce(p_approved_by, auth.uid());
  v_wallet := public.ensure_customer_wallet(p_customer_id);

  if v_ref is not null and exists (
        select 1 from public.customer_credit_adjustments where reference_no = v_ref) then
    raise exception 'Reference number "%" has already been used for an adjustment', v_ref;
  end if;

  if p_direction = 'increase' then
    v_lot := public.grant_customer_credit(p_customer_id, p_category, p_amount,
      'manual_adjustment', null, p_store_id, v_eff, v_ref, p_reason, p_note, null, v_approver);
    select id into v_entry from public.customer_credit_ledger
     where lot_id = v_lot and entry_type = 'grant' limit 1;
  else
    select coalesce(sum(remaining_amount),0) into v_left
      from public.customer_credit_lots
     where customer_id = p_customer_id and category = p_category and status = 'active';
    if v_left < round(p_amount,2) then
      raise exception 'Cannot decrease % credit by % — only % is available', p_category, p_amount, v_left;
    end if;

    insert into public.customer_credit_ledger (
      wallet_id, customer_id, entry_type, category, amount, source_type,
      store_id, effective_date, reference_no, reason, note, created_by, approved_by)
    values (v_wallet, p_customer_id, 'adjust_decrease', p_category, round(p_amount,2),
      'manual_adjustment', p_store_id, v_eff, v_ref, p_reason, p_note, auth.uid(), v_approver)
    returning id into v_entry;

    v_take := round(p_amount,2);
    for v_l in
      select id, remaining_amount from public.customer_credit_lots
       where customer_id = p_customer_id and category = p_category
         and status = 'active' and remaining_amount > 0
       order by effective_date, created_at for update
    loop
      exit when v_take <= 0;
      if v_l.remaining_amount >= v_take then
        update public.customer_credit_lots
           set remaining_amount = remaining_amount - v_take, updated_at = now() where id = v_l.id;
        insert into public.customer_credit_allocations (ledger_entry_id, lot_id, customer_id, amount)
        values (v_entry, v_l.id, p_customer_id, v_take);
        v_take := 0;
      else
        update public.customer_credit_lots
           set remaining_amount = 0, updated_at = now() where id = v_l.id;
        insert into public.customer_credit_allocations (ledger_entry_id, lot_id, customer_id, amount)
        values (v_entry, v_l.id, p_customer_id, v_l.remaining_amount);
        v_take := v_take - v_l.remaining_amount;
      end if;
    end loop;
  end if;

  insert into public.customer_credit_adjustments (
    customer_id, category, direction, amount, reason, note, reference_no,
    effective_date, ledger_entry_id, lot_id, created_by, approved_by)
  values (p_customer_id, p_category, p_direction, round(p_amount,2), p_reason, p_note,
    v_ref, v_eff, v_entry, v_lot, auth.uid(), v_approver)
  returning id into v_adj;

  perform public.write_audit_ex('customer_credit_adjustments', v_adj, 'credit_adjusted', null,
    jsonb_build_object('customer', p_customer_id, 'category', p_category,
      'direction', p_direction, 'amount', p_amount, 'reference', v_ref),
    'credit', p_reason, p_store_id);
  return v_adj;
end $function$;

notify pgrst, 'reload schema';
