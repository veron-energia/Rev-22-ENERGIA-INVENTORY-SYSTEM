-- =====================================================================
-- ENERGIA — FIX: rental late days computed in Singapore time
--
-- return_rental used now()::date, which is the database's UTC date. In
-- Singapore (UTC+8) a return processed before 8am local time would count
-- one late day too few. This recreates the function using the
-- Asia/Singapore calendar date. Run once; safe to re-run.
-- =====================================================================

create or replace function public.return_rental(
  p_rental_id uuid, p_condition return_condition, p_return_stock boolean,
  p_late_payment_method_id uuid default null, p_late_reference text default null, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_r public.rentals%rowtype; v_late_days integer; v_late_total numeric; v_today date;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can manage rentals'; end if;
  select * into v_r from public.rentals where id = p_rental_id for update;
  if not found then raise exception 'Rental not found'; end if;
  if v_r.status not in ('paid','active','overdue') then
    raise exception 'Only paid/active rentals can be returned (current: %)', v_r.status;
  end if;

  v_today := (now() at time zone 'Asia/Singapore')::date;
  v_late_days := greatest(0, (v_today - v_r.expected_return_date));
  v_late_total := round(v_late_days * v_r.late_fee_per_day * v_r.quantity, 2);
  if v_late_total > 0 and p_late_payment_method_id is null then
    raise exception 'Late fee of S$% is due — select a payment method for it', v_late_total;
  end if;

  if p_return_stock then
    insert into public.special_product_stock (special_product_id, warehouse_id, current_qty)
    values (v_r.special_product_id, v_r.warehouse_id, v_r.quantity)
    on conflict (special_product_id, warehouse_id)
    do update set current_qty = public.special_product_stock.current_qty + excluded.current_qty, updated_at = now();
  end if;

  update public.rentals set status = 'returned', returned_at = now(),
    return_condition = p_condition, stock_returned = p_return_stock,
    late_days = v_late_days, late_fee_total = v_late_total,
    late_payment_method_id = p_late_payment_method_id, late_payment_reference = p_late_reference,
    notes = coalesce(notes,'') || case when p_note is null then '' else ' | Return: '||p_note end
    where id = p_rental_id;

  perform public.write_audit('rentals', p_rental_id, 'rental_returned', null,
    jsonb_build_object('rental_no', v_r.rental_no, 'condition', p_condition,
      'stock_returned', p_return_stock, 'late_days', v_late_days, 'late_fee', v_late_total));
  return jsonb_build_object('success', true, 'late_days', v_late_days, 'late_fee_total', v_late_total);
end; $$;

notify pgrst, 'reload schema';
