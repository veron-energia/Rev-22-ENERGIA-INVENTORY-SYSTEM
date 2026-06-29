-- =====================================================================
-- ENERGIA — PHASE 3: SALES FUNCTIONS
-- Invoice number generation, invoice creation with store-price lookup,
-- and the atomic pay_invoice (stock check + deduct + commission).
-- Run after 08_phase3_rls.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. NEXT INVOICE NUMBER  →  INV-YYYY-0001 (sequential per year)
-- ---------------------------------------------------------------------
create or replace function public.next_invoice_no()
returns text language plpgsql security definer set search_path = public as $$
declare
  v_year text := to_char(now(), 'YYYY');
  v_count integer;
  v_next text;
begin
  -- Count existing invoices for this year (including soft-deleted, to avoid number reuse).
  select count(*) into v_count from public.invoices
    where invoice_no like 'INV-' || v_year || '-%';
  v_next := 'INV-' || v_year || '-' || lpad((v_count + 1)::text, 4, '0');
  -- Guard against a rare collision by bumping until free.
  while exists (select 1 from public.invoices where invoice_no = v_next) loop
    v_count := v_count + 1;
    v_next := 'INV-' || v_year || '-' || lpad((v_count + 1)::text, 4, '0');
  end loop;
  return v_next;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. CREATE INVOICE (draft/unpaid) — prices pulled from the store list.
--    p_items: [{ "product_id": "...", "quantity": 2 }, ...]
--    Does NOT touch stock (stock only moves on full payment).
-- ---------------------------------------------------------------------
create or replace function public.create_invoice(
  p_store_id uuid,
  p_customer_id uuid,
  p_affiliate_id uuid,
  p_items jsonb,
  p_discount_total numeric default 0,
  p_notes text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_item jsonb;
  v_product_id uuid;
  v_qty integer;
  v_price numeric;
  v_subtotal numeric := 0;
  v_line_total numeric;
  v_invoice_id uuid;
  v_invoice_no text;
begin
  if not public.user_has_store_access(p_store_id) then
    raise exception 'You do not have access to this store';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'At least one product is required';
  end if;

  -- Validate every line has a store price; compute subtotal.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantity must be greater than zero'; end if;

    select selling_price into v_price from public.store_product_prices
      where store_id = p_store_id and product_id = v_product_id
        and is_active = true and deleted_at is null;
    if v_price is null then
      raise exception 'No price set for product % in this store', v_product_id;
    end if;
    v_subtotal := v_subtotal + (v_price * v_qty);
  end loop;

  v_invoice_no := public.next_invoice_no();

  insert into public.invoices
    (invoice_no, store_id, customer_id, affiliate_id, created_by, status,
     subtotal, discount_total, total_amount, paid_amount)
  values
    (v_invoice_no, p_store_id, p_customer_id, p_affiliate_id, auth.uid(), 'unpaid',
     v_subtotal, coalesce(p_discount_total,0), v_subtotal - coalesce(p_discount_total,0), 0)
  returning id into v_invoice_id;

  -- Insert line items with the resolved price.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::integer;
    select selling_price into v_price from public.store_product_prices
      where store_id = p_store_id and product_id = v_product_id and is_active = true and deleted_at is null;
    v_line_total := v_price * v_qty;
    insert into public.invoice_items (invoice_id, product_id, quantity, unit_price, line_total)
    values (v_invoice_id, v_product_id, v_qty, v_price, v_line_total);
  end loop;

  perform public.write_audit('invoices', v_invoice_id, 'invoice_created', null,
    jsonb_build_object('invoice_no', v_invoice_no, 'total', v_subtotal - coalesce(p_discount_total,0)));

  return v_invoice_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. PAY INVOICE (split payments) — the atomic core of sales.
--    p_payments: [{ "payment_method_id": "...", "amount": 40 }, ...]
--    Steps: lock invoice → validate not already paid → check store stock
--    for every line → record payments → if fully paid: deduct store stock,
--    write stock_movements, mark paid, calculate affiliate commission.
-- ---------------------------------------------------------------------
create or replace function public.pay_invoice(
  p_invoice_id uuid,
  p_payments jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype;
  v_pay jsonb;
  v_method uuid;
  v_amount numeric;
  v_total_paying numeric := 0;
  v_already_paid numeric;
  v_new_paid numeric;
  v_item record;
  v_available integer;
  v_affiliate public.affiliates%rowtype;
  v_commission numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then
    raise exception 'You do not have access to this invoice''s store';
  end if;
  if v_inv.status in ('paid','cancelled','refunded') then
    raise exception 'Invoice is already %', v_inv.status;
  end if;
  if p_payments is null or jsonb_array_length(p_payments) = 0 then
    raise exception 'At least one payment is required';
  end if;

  -- Sum the payments being recorded now.
  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_amount := (v_pay->>'amount')::numeric;
    if v_amount is null or v_amount <= 0 then raise exception 'Payment amount must be positive'; end if;
    v_total_paying := v_total_paying + v_amount;
  end loop;

  v_already_paid := v_inv.paid_amount;
  v_new_paid := v_already_paid + v_total_paying;

  -- Block overpayment beyond the invoice total (allow tiny rounding slack).
  if v_new_paid > v_inv.total_amount + 0.001 then
    raise exception 'Payment (%.2f) exceeds remaining balance (%.2f)',
      v_total_paying, v_inv.total_amount - v_already_paid;
  end if;

  -- If this payment completes the invoice, re-check store stock for every line FIRST.
  if v_new_paid >= v_inv.total_amount - 0.001 then
    for v_item in select product_id, quantity from public.invoice_items where invoice_id = p_invoice_id
    loop
      select current_qty into v_available from public.store_inventory
        where store_id = v_inv.store_id and product_id = v_item.product_id for update;
      v_available := coalesce(v_available, 0);
      if v_available < v_item.quantity then
        raise exception 'Insufficient store stock for a product (have %, need %). Payment blocked.',
          v_available, v_item.quantity;
      end if;
    end loop;
  end if;

  -- Record the payment rows (locked immediately).
  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_method := (v_pay->>'payment_method_id')::uuid;
    v_amount := (v_pay->>'amount')::numeric;
    insert into public.invoice_payments (invoice_id, payment_method_id, amount, payment_reference, received_by)
    values (p_invoice_id, v_method, v_amount, v_pay->>'reference', auth.uid());
  end loop;

  -- Fully paid?  Deduct stock, log movements, mark paid, commission.
  if v_new_paid >= v_inv.total_amount - 0.001 then
    for v_item in select product_id, quantity from public.invoice_items where invoice_id = p_invoice_id
    loop
      update public.store_inventory set current_qty = current_qty - v_item.quantity, updated_at = now()
        where store_id = v_inv.store_id and product_id = v_item.product_id;

      insert into public.stock_movements
        (product_id, movement_type, from_store_id, invoice_id, quantity, notes, created_by)
      values
        (v_item.product_id, 'store_sale', v_inv.store_id, p_invoice_id, v_item.quantity,
         'Sale — ' || v_inv.invoice_no, auth.uid());
    end loop;

    update public.invoices
      set status = 'paid', paid_amount = v_new_paid, paid_at = now(), locked_at = now()
      where id = p_invoice_id;

    -- Affiliate commission (percentage of invoice total).
    if v_inv.affiliate_id is not null then
      select * into v_affiliate from public.affiliates where id = v_inv.affiliate_id;
      if found and v_affiliate.is_active then
        if v_affiliate.commission_type = 'percentage' then
          v_commission := round(v_inv.total_amount * v_affiliate.commission_value / 100.0, 2);
        else
          v_commission := v_affiliate.commission_value;  -- fixed fallback
        end if;
        if v_commission > 0 then
          insert into public.affiliate_commissions (affiliate_id, invoice_id, commission_amount, status)
          values (v_inv.affiliate_id, p_invoice_id, v_commission, 'earned')
          on conflict (affiliate_id, invoice_id) do nothing;
        end if;
      end if;
    end if;

    perform public.write_audit('invoices', p_invoice_id, 'invoice_paid', null,
      jsonb_build_object('paid_amount', v_new_paid, 'invoice_no', v_inv.invoice_no));

    return jsonb_build_object('success', true, 'status', 'paid', 'paid_amount', v_new_paid);
  else
    -- Partial payment: update running total, mark partially_paid.
    update public.invoices set paid_amount = v_new_paid, status = 'partially_paid'
      where id = p_invoice_id;

    perform public.write_audit('invoices', p_invoice_id, 'invoice_partial_payment', null,
      jsonb_build_object('paid_amount', v_new_paid));

    return jsonb_build_object('success', true, 'status', 'partially_paid',
      'paid_amount', v_new_paid, 'remaining', v_inv.total_amount - v_new_paid);
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. DELETE (soft) an unpaid invoice. Paid invoices are locked.
-- ---------------------------------------------------------------------
create or replace function public.delete_invoice(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_inv public.invoices%rowtype;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access'; end if;
  if v_inv.status = 'paid' then raise exception 'Paid invoices cannot be deleted (use cancel/refund)'; end if;

  update public.invoices set deleted_at = now() where id = p_invoice_id;
  perform public.write_audit('invoices', p_invoice_id, 'invoice_deleted', to_jsonb(v_inv), null);
end;
$$;
