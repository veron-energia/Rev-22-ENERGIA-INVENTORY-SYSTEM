-- =====================================================================
-- ENERGIA — PHASE 5D-2: Selling promotions on invoices
--   * promotion invoice lines (sold at the promotion's fixed price)
--   * discount vouchers BLOCKED on bundle invoices (spec rule)
--   * unified stock resolver: expands product/voucher/promotion lines to
--     leaf stock items (aggregated) — used for payment check, deduction,
--     and refund/cancel return. ALSO FIXES: refunds of voucher-line
--     invoices previously assumed every line was a product.
--   * proportional commission: a promotion line's after-discount amount is
--     allocated across its commissionable contents by original value at the
--     store, each portion at its own (15%) / 3rd-party (4.5%) Tier-1 rate.
--     If contents have no catalogue value (all treatments), the whole line
--     earns at the Own rate.
--
-- Additive + idempotent. Run AFTER 18_phase5d1_promotions.sql.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. invoice_items: promotion reference
-- ---------------------------------------------------------------------
alter table public.invoice_items add column if not exists promotion_id uuid references public.promotions(id);

-- ---------------------------------------------------------------------
-- 2. Unified stock requirement resolver for an invoice.
--    Expands all lines to leaf items and AGGREGATES quantities (so two
--    lines sharing a product are checked against combined need).
-- ---------------------------------------------------------------------
create or replace function public.invoice_required_stock(p_invoice_id uuid)
returns table (kind text, item_id uuid, quantity bigint)
language sql stable security definer set search_path = public as $$
  with expanded as (
    -- direct product lines
    select 'product'::text as kind, ii.product_id as item_id, ii.quantity::bigint as quantity
    from public.invoice_items ii
    where ii.invoice_id = p_invoice_id and ii.line_kind = 'product'
    union all
    -- limited-voucher lines
    select 'voucher', ii.voucher_id, ii.quantity::bigint
    from public.invoice_items ii
    join public.vouchers v on v.id = ii.voucher_id and v.qty_type = 'limited'
    where ii.invoice_id = p_invoice_id and ii.line_kind = 'voucher'
    union all
    -- promotion lines expanded to leaf items (products + limited vouchers)
    select s.kind, s.item_id, (s.quantity)::bigint
    from public.invoice_items ii
    cross join lateral public.promotion_stock_items(ii.promotion_id, ii.quantity) s
    where ii.invoice_id = p_invoice_id and ii.line_kind::text in ('promotion', 'premium_bundle')  -- a bundle carries a
      -- promotion_id and keeps its contents in promotion_items exactly as a
      -- promotion does; expanding only 'promotion' meant a bundle consumed
      -- no stock at all, on corrections and on ordinary sales alike.
  )
  select kind, item_id, sum(quantity) as quantity
  from expanded
  group by kind, item_id
$$;

-- ---------------------------------------------------------------------
-- 3. create_invoice — adds promotion lines; blocks discount vouchers on
--    bundle invoices; validates promotion active + date window.
-- ---------------------------------------------------------------------
create or replace function public.create_invoice(
  p_store_id uuid, p_customer_id uuid, p_affiliate_id uuid,
  p_items jsonb, p_discount_total numeric default 0, p_notes text default null,
  p_discount_voucher_id uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_item jsonb; v_kind text; v_product_id uuid; v_voucher_id uuid; v_promo_id uuid;
  v_qty integer; v_price numeric; v_subtotal numeric := 0; v_line_total numeric;
  v_invoice_id uuid; v_invoice_no text; v_discount numeric := coalesce(p_discount_total,0);
  v_has_promo boolean := false; v_promo public.promotions%rowtype;
begin
  if not public.user_has_store_access(p_store_id) then raise exception 'You do not have access to this store'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'At least one item is required'; end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantity must be greater than zero'; end if;

    if v_kind = 'promotion' then
      v_has_promo := true;
      v_promo_id := (v_item->>'promotion_id')::uuid;
      select * into v_promo from public.promotions where id = v_promo_id and deleted_at is null;
      if not found then raise exception 'Promotion not found'; end if;
      if not v_promo.is_active then raise exception 'Promotion "%" is not active', v_promo.name; end if;
      if v_promo.start_date is not null and now()::date < v_promo.start_date then raise exception 'Promotion "%" has not started yet', v_promo.name; end if;
      if v_promo.end_date is not null and now()::date > v_promo.end_date then raise exception 'Promotion "%" has ended', v_promo.name; end if;
      v_price := v_promo.fixed_price;
    elsif v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      select selling_price into v_price from public.vouchers
        where id = v_voucher_id and is_active = true and deleted_at is null;
      if v_price is null then raise exception 'Voucher not found or inactive'; end if;
    else
      v_product_id := (v_item->>'product_id')::uuid;
      select selling_price into v_price from public.store_product_prices
        where store_id = p_store_id and product_id = v_product_id and is_active = true and deleted_at is null;
      if v_price is null then raise exception 'No price set for a product in this store'; end if;
    end if;
    v_subtotal := v_subtotal + (v_price * v_qty);
  end loop;

  -- Spec rule: discount vouchers can never be used on bundle invoices.
  if p_discount_voucher_id is not null and v_has_promo then
    raise exception 'Discount vouchers cannot be used on an invoice that contains a promotion/bundle';
  end if;

  if p_discount_voucher_id is not null then
    v_discount := v_discount + public.voucher_discount_amount(p_discount_voucher_id, v_subtotal - v_discount);
  end if;
  if v_discount > v_subtotal then v_discount := v_subtotal; end if;

  v_invoice_no := public.next_invoice_no();
  insert into public.invoices
    (invoice_no, store_id, customer_id, affiliate_id, created_by, status,
     subtotal, discount_total, total_amount, paid_amount, notes, discount_voucher_id)
  values (v_invoice_no, p_store_id, p_customer_id, p_affiliate_id, auth.uid(), 'unpaid',
          v_subtotal, v_discount, v_subtotal - v_discount, 0, p_notes, p_discount_voucher_id)
  returning id into v_invoice_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    if v_kind = 'promotion' then
      v_promo_id := (v_item->>'promotion_id')::uuid;
      select fixed_price into v_price from public.promotions where id = v_promo_id;
      v_line_total := v_price * v_qty;
      insert into public.invoice_items (invoice_id, line_kind, promotion_id, product_id, quantity, unit_price, line_total)
      values (v_invoice_id, 'promotion', v_promo_id, null, v_qty, v_price, v_line_total);
    elsif v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      select selling_price into v_price from public.vouchers where id = v_voucher_id;
      v_line_total := v_price * v_qty;
      insert into public.invoice_items (invoice_id, line_kind, voucher_id, product_id, quantity, unit_price, line_total)
      values (v_invoice_id, 'voucher', v_voucher_id, null, v_qty, v_price, v_line_total);
    else
      v_product_id := (v_item->>'product_id')::uuid;
      select selling_price into v_price from public.store_product_prices
        where store_id = p_store_id and product_id = v_product_id and is_active = true and deleted_at is null;
      v_line_total := v_price * v_qty;
      insert into public.invoice_items (invoice_id, line_kind, product_id, quantity, unit_price, line_total)
      values (v_invoice_id, 'product', v_product_id, v_qty, v_price, v_line_total);
    end if;
  end loop;

  perform public.write_audit('invoices', v_invoice_id, 'invoice_created', null,
    jsonb_build_object('invoice_no', v_invoice_no, 'total', v_subtotal - v_discount,
                       'has_promotion', v_has_promo, 'discount_voucher', p_discount_voucher_id));
  return v_invoice_id;
end; $$;

-- ---------------------------------------------------------------------
-- 4. pay_invoice — stock check + deduction now via invoice_required_stock
--    (covers products, limited vouchers, and full bundle expansion).
-- ---------------------------------------------------------------------
create or replace function public.pay_invoice(p_invoice_id uuid, p_payments jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_pay jsonb; v_method uuid; v_amount numeric;
  v_total_paying numeric := 0; v_already_paid numeric; v_new_paid numeric;
  v_req record; v_available integer; v_item record;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access to this invoice''s store'; end if;
  if v_inv.status in ('paid','cancelled','refunded') then raise exception 'Invoice is already %', v_inv.status; end if;
  if p_payments is null or jsonb_array_length(p_payments) = 0 then raise exception 'At least one payment is required'; end if;

  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_amount := (v_pay->>'amount')::numeric;
    if v_amount is null or v_amount <= 0 then raise exception 'Payment amount must be positive'; end if;
    v_total_paying := v_total_paying + v_amount;
  end loop;

  v_already_paid := v_inv.paid_amount;
  v_new_paid := v_already_paid + v_total_paying;
  if v_new_paid > v_inv.total_amount + 0.001 then raise exception 'Payment exceeds remaining balance'; end if;

  -- Full payment → check ALL required stock (aggregated, bundles expanded).
  if v_new_paid >= v_inv.total_amount - 0.001 then
    for v_req in select * from public.invoice_required_stock(p_invoice_id)
    loop
      if v_req.kind = 'product' then
        select current_qty into v_available from public.store_inventory
          where store_id = v_inv.store_id and product_id = v_req.item_id for update;
        if coalesce(v_available,0) < v_req.quantity then
          raise exception 'Insufficient store stock for % (have %, need % incl. bundles). Payment blocked.',
            (select name from public.products where id = v_req.item_id), coalesce(v_available,0), v_req.quantity;
        end if;
      else
        select current_qty into v_available from public.voucher_store_stock
          where store_id = v_inv.store_id and voucher_id = v_req.item_id for update;
        if coalesce(v_available,0) < v_req.quantity then
          raise exception 'Insufficient voucher stock for % (have %, need % incl. bundles). Payment blocked.',
            (select name from public.vouchers where id = v_req.item_id), coalesce(v_available,0), v_req.quantity;
        end if;
      end if;
    end loop;
  end if;

  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_method := (v_pay->>'payment_method_id')::uuid;
    v_amount := (v_pay->>'amount')::numeric;
    insert into public.invoice_payments (invoice_id, payment_method_id, amount, payment_reference, received_by)
    values (p_invoice_id, v_method, v_amount, v_pay->>'reference', auth.uid());
  end loop;

  if v_new_paid >= v_inv.total_amount - 0.001 then
    -- Deduct aggregated requirements (bundle contents included).
    for v_req in select * from public.invoice_required_stock(p_invoice_id)
    loop
      if v_req.kind = 'product' then
        update public.store_inventory set current_qty = current_qty - v_req.quantity, updated_at = now()
          where store_id = v_inv.store_id and product_id = v_req.item_id;
        insert into public.stock_movements (product_id, movement_type, from_store_id, invoice_id, quantity, notes, created_by)
        values (v_req.item_id, 'store_sale', v_inv.store_id, p_invoice_id, v_req.quantity, 'Sale — '||v_inv.invoice_no, auth.uid());
      else
        update public.voucher_store_stock set current_qty = current_qty - v_req.quantity, updated_at = now()
          where store_id = v_inv.store_id and voucher_id = v_req.item_id;
        perform public.write_audit('vouchers', v_req.item_id, 'voucher_sold', null,
          jsonb_build_object('invoice_no', v_inv.invoice_no, 'qty', v_req.quantity));
      end if;
    end loop;

    update public.invoices set status = 'paid', paid_amount = v_new_paid, paid_at = now(), locked_at = now()
      where id = p_invoice_id;

    if v_inv.discount_voucher_id is not null then
      insert into public.voucher_redemptions (voucher_id, invoice_id, customer_id, discount_applied, redeemed_by)
      values (v_inv.discount_voucher_id, p_invoice_id, v_inv.customer_id, v_inv.discount_total, auth.uid());
      perform public.write_audit('vouchers', v_inv.discount_voucher_id, 'voucher_redeemed', null,
        jsonb_build_object('invoice_no', v_inv.invoice_no, 'discount', v_inv.discount_total));
    end if;

    perform public.earn_invoice_commission(p_invoice_id);

    perform public.write_audit('invoices', p_invoice_id, 'invoice_paid', null,
      jsonb_build_object('paid_amount', v_new_paid, 'invoice_no', v_inv.invoice_no));
    return jsonb_build_object('success', true, 'status', 'paid', 'paid_amount', v_new_paid);
  else
    update public.invoices set paid_amount = v_new_paid, status = 'partially_paid' where id = p_invoice_id;
    perform public.write_audit('invoices', p_invoice_id, 'invoice_partial_payment', null,
      jsonb_build_object('paid_amount', v_new_paid));
    return jsonb_build_object('success', true, 'status', 'partially_paid', 'paid_amount', v_new_paid, 'remaining', v_inv.total_amount - v_new_paid);
  end if;
end; $$;

-- ---------------------------------------------------------------------
-- 5. resolve_invoice_action — return stock via the same resolver.
--    FIXES the latent bug where voucher/promotion lines broke refunds.
-- ---------------------------------------------------------------------
create or replace function public.resolve_invoice_action(
  p_request_id uuid, p_approve boolean, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_req public.approval_requests%rowtype; v_inv public.invoices%rowtype;
  v_return_stock boolean; v_req_item record; v_is_refund boolean; v_final_status invoice_status;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can approve'; end if;
  select * into v_req from public.approval_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request is not pending'; end if;

  select * into v_inv from public.invoices where id = v_req.related_record_id for update;
  v_is_refund := (v_req.request_type = 'invoice_refund');
  v_return_stock := coalesce((v_req.payload->>'return_stock')::boolean, false);

  if not p_approve then
    update public.invoices set status = (case when v_is_refund then 'paid' else 'unpaid' end)::invoice_status where id = v_inv.id;
    update public.approval_requests set status = 'rejected', approved_by = auth.uid(),
      approved_at = now(), response_note = p_note where id = p_request_id;
    perform public.write_audit('invoices', v_inv.id, 'invoice_action_rejected', null,
      jsonb_build_object('request_type', v_req.request_type));
    return jsonb_build_object('success', true, 'status', 'rejected');
  end if;

  v_final_status := case when v_is_refund then 'refunded'::invoice_status else 'cancelled'::invoice_status end;

  if v_return_stock then
    for v_req_item in select * from public.invoice_required_stock(v_inv.id)
    loop
      if v_req_item.kind = 'product' then
        insert into public.store_inventory (store_id, product_id, current_qty)
        values (v_inv.store_id, v_req_item.item_id, v_req_item.quantity)
        on conflict (store_id, product_id)
        do update set current_qty = public.store_inventory.current_qty + excluded.current_qty, updated_at = now();
        insert into public.stock_movements (product_id, movement_type, to_store_id, invoice_id, quantity, notes, created_by)
        values (v_req_item.item_id,
          (case when v_is_refund then 'invoice_refund_return' else 'invoice_cancel_return' end)::stock_movement_type,
          v_inv.store_id, v_inv.id, v_req_item.quantity, 'Stock returned — '||v_inv.invoice_no, auth.uid());
      else
        insert into public.voucher_store_stock (voucher_id, store_id, current_qty)
        values (v_req_item.item_id, v_inv.store_id, v_req_item.quantity)
        on conflict (voucher_id, store_id)
        do update set current_qty = public.voucher_store_stock.current_qty + excluded.current_qty, updated_at = now();
      end if;
    end loop;
  end if;

  perform public.reverse_invoice_commission(v_inv.id,
    case when v_is_refund then 'invoice refunded' else 'invoice cancelled' end);

  update public.invoices set status = v_final_status where id = v_inv.id;
  update public.approval_requests set status = 'approved', approved_by = auth.uid(),
    approved_at = now(), response_note = p_note where id = p_request_id;

  perform public.write_audit('invoices', v_inv.id,
    case when v_is_refund then 'invoice_refunded' else 'invoice_cancelled' end, null,
    jsonb_build_object('return_stock', v_return_stock, 'invoice_no', v_inv.invoice_no));
  return jsonb_build_object('success', true, 'status', v_final_status, 'stock_returned', v_return_stock);
end; $$;

-- ---------------------------------------------------------------------
-- 6. earn_invoice_commission — promotion lines allocate proportionally.
-- ---------------------------------------------------------------------
create or replace function public.earn_invoice_commission(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_tier1 uuid; v_tier2 uuid; v_item record;
  v_ptype text; v_subtotal numeric; v_discount numeric; v_line_after numeric;
  v_t1_rate numeric; v_t1_amt numeric; v_t2_amt numeric; v_paid_date date;
  v_own_orig numeric; v_third_orig numeric; v_tot_orig numeric; v_portion numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return; end if;

  select tier1, tier2 into v_tier1, v_tier2 from public.customer_referrers(v_inv.customer_id);
  if v_tier1 is null then return; end if;

  v_paid_date := coalesce(v_inv.paid_at, now())::date;
  v_subtotal := nullif(v_inv.subtotal, 0);
  v_discount := coalesce(v_inv.discount_total, 0);

  for v_item in
    select ii.id, ii.line_kind, ii.voucher_id, ii.promotion_id, ii.quantity, ii.line_total,
           coalesce(p.product_type::text, 'own') as ptype
    from public.invoice_items ii
    left join public.products p on p.id = ii.product_id
    where ii.invoice_id = p_invoice_id
  loop
    if v_subtotal is null then v_line_after := v_item.line_total;
    else v_line_after := v_item.line_total - (v_discount * (v_item.line_total / v_subtotal)); end if;
    if v_line_after < 0 then v_line_after := 0; end if;
    if v_line_after = 0 then continue; end if;

    if v_item.line_kind = 'promotion' then
      -- Proportional allocation: split after-discount amount by original values
      -- of the bundle's commissionable contents (own vs third-party).
      select
        coalesce(sum(case when ptype = 'third_party' then 0 else original_value end),0),
        coalesce(sum(case when ptype = 'third_party' then original_value else 0 end),0)
        into v_own_orig, v_third_orig
      from public.promotion_commission_items(v_item.promotion_id, v_inv.store_id, v_item.quantity);
      v_tot_orig := v_own_orig + v_third_orig;

      if v_tot_orig <= 0 then
        -- No catalogue value (e.g. all treatments): whole line at Own rate.
        v_own_orig := 1; v_third_orig := 0; v_tot_orig := 1;
      end if;

      -- Own portion
      if v_own_orig > 0 then
        v_portion := round(v_line_after * v_own_orig / v_tot_orig, 2);
        v_t1_amt := round(v_portion * 15 / 100.0, 2);
        if v_t1_amt > 0 then
          insert into public.commissions
            (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
             product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1',
             'own', v_portion, 15, v_t1_amt, 'earned', v_paid_date);
          if v_tier2 is not null then
            v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
            if v_t2_amt > 0 then
              insert into public.commissions
                (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
                 product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
              values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2',
                 'own', v_t1_amt, 5.0, v_t2_amt, 'earned', v_paid_date);
            end if;
          end if;
        end if;
      end if;

      -- Third-party portion
      if v_third_orig > 0 then
        v_portion := round(v_line_after * v_third_orig / v_tot_orig, 2);
        v_t1_amt := round(v_portion * 4.5 / 100.0, 2);
        if v_t1_amt > 0 then
          insert into public.commissions
            (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
             product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1',
             'third_party', v_portion, 4.5, v_t1_amt, 'earned', v_paid_date);
          if v_tier2 is not null then
            v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
            if v_t2_amt > 0 then
              insert into public.commissions
                (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
                 product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
              values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2',
                 'third_party', v_t1_amt, 5.0, v_t2_amt, 'earned', v_paid_date);
            end if;
          end if;
        end if;
      end if;

    else
      -- Product / voucher lines: unchanged from 5C.
      if v_item.line_kind = 'voucher' then v_ptype := 'own'; else v_ptype := v_item.ptype; end if;
      v_t1_rate := case when v_ptype = 'third_party' then 4.5 else 15 end;
      v_t1_amt := round(v_line_after * v_t1_rate / 100.0, 2);
      if v_t1_amt <= 0 then continue; end if;

      insert into public.commissions
        (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
         product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
      values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1',
         v_ptype, v_line_after, v_t1_rate, v_t1_amt, 'earned', v_paid_date);

      if v_tier2 is not null then
        v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
        if v_t2_amt > 0 then
          insert into public.commissions
            (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier,
             product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2',
             v_ptype, v_t1_amt, 5.0, v_t2_amt, 'earned', v_paid_date);
        end if;
      end if;
    end if;
  end loop;

  perform public.write_audit('commissions', p_invoice_id, 'commission_calculated', null,
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'tier1', v_tier1, 'tier2', v_tier2));
end; $$;

notify pgrst, 'reload schema';
