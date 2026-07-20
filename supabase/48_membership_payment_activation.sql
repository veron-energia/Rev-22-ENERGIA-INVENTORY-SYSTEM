-- =====================================================================
-- ENERGIA — PHASE 4B: Atomic payment + membership activation
--
-- Rewrites pay_invoice CAREFULLY: every existing behaviour is preserved
-- verbatim (stock lock/check/deduct, multi-payment, voucher redemptions,
-- affiliate + staff commission, partial payment, locking). The following
-- membership steps are ADDED, all inside the same single transaction the
-- function already runs in:
--
--   * Member ID required before a membership line can be paid.
--   * Reprice non-overridden lines by membership status at payment time
--     (membership + products on one invoice => member prices apply).
--   * On full payment, create/renew the membership (renewal starts the day
--     after current expiry; no overlap).
--   * Commit the reserved Member ID to permanent ownership.
--   * Membership line earns Staff + Tier1/Tier2 affiliate commission
--     (handled by the existing earn_* functions, which read invoice lines).
--   * Promotion member-gating: a non-member may only buy a promotion if the
--     invoice also contains a membership line or the line was overridden.
--
-- Idempotent (create or replace). Run AFTER 47_membership_invoice_wiring.sql.
-- Depends on enum values 'membership'/'therapy' added in 47 (separate txn).
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- Helper: does this invoice contain a membership line? Returns the plan.
-- ---------------------------------------------------------------------
create or replace function public.invoice_membership_line(p_invoice_id uuid)
returns table (item_id uuid, plan_id uuid, member_id text, unit_price numeric)
language sql stable security definer set search_path = public as $$
  select ii.id, ii.membership_plan_id, ii.override_reason, ii.unit_price
  from public.invoice_items ii
  where ii.invoice_id = p_invoice_id and ii.line_kind = 'membership'
  limit 1
$$;

-- ---------------------------------------------------------------------
-- Reprice non-overridden lines against the customer's member status.
-- Called at payment (after final membership state is known). Overridden
-- lines and voucher/promotion/membership lines are left as priced.
-- Returns the recomputed invoice total for the caller to re-validate.
-- ---------------------------------------------------------------------
create or replace function public.reprice_invoice_lines(p_invoice_id uuid, p_is_member boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_inv public.invoices%rowtype; v_li record; v_pj jsonb; v_new numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  for v_li in
    select * from public.invoice_items
     where invoice_id = p_invoice_id and line_kind = 'product'
       and price_overridden = false
  loop
    v_pj := public.product_price_for(v_inv.store_id, v_li.product_id, p_is_member);
    if (v_pj->>'found')::boolean and (v_pj->>'has_price')::boolean then
      v_new := (v_pj->>'price')::numeric;
      if v_new is distinct from v_li.unit_price then
        update public.invoice_items
           set unit_price = v_new,
               line_total = (v_new * quantity) - coalesce(line_discount,0),
               price_mode = v_pj->>'price_mode',
               price_source = 'product',
               original_price = coalesce(original_price, v_li.unit_price)
         where id = v_li.id;
      end if;
    end if;
  end loop;

  -- Recalculate the invoice total from its lines (+ existing discount_total).
  update public.invoices i
     set total_amount = coalesce((select sum(line_total) from public.invoice_items where invoice_id = p_invoice_id),0)
                        - coalesce(i.discount_total,0)
   where i.id = p_invoice_id;
end $$;

-- ---------------------------------------------------------------------
-- Manual per-line price override (Owner/Manager/Admin, or Staff for their
-- store). Records reason + old/new mode. May override product eligibility.
-- ---------------------------------------------------------------------
create or replace function public.override_invoice_line_price(
  p_item_id uuid, p_mode text, p_reason text
) returns void language plpgsql security definer set search_path = public as $$
declare v_li public.invoice_items%rowtype; v_inv public.invoices%rowtype; v_pj jsonb; v_new numeric; v_role user_role;
begin
  v_role := public.current_user_role();
  if v_role is null or v_role = 'inventory_manager' then raise exception 'Not permitted'; end if;
  if p_mode not in ('member','non_member') then raise exception 'Invalid price mode'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'An override reason is required'; end if;

  select * into v_li from public.invoice_items where id = p_item_id;
  if not found then raise exception 'Line not found'; end if;
  select * into v_inv from public.invoices where id = v_li.invoice_id;
  if v_inv.status in ('paid','cancelled','refunded') then raise exception 'Invoice is locked'; end if;
  if not (public.is_manager_or_above() or public.user_has_store_access(v_inv.store_id)) then
    raise exception 'No access to this invoice''s store'; end if;

  v_pj := public.product_price_for(v_inv.store_id, v_li.product_id, p_mode = 'member');
  if not (v_pj->>'found')::boolean or (v_pj->>'price') is null then
    raise exception 'No % price is set for this product', p_mode; end if;
  v_new := (v_pj->>'price')::numeric;

  update public.invoice_items
     set unit_price = v_new,
         line_total = (v_new * quantity) - coalesce(line_discount,0),
         price_mode = p_mode, price_source = 'manual_override',
         original_price = coalesce(original_price, v_li.unit_price),
         price_overridden = true, override_reason = trim(p_reason),
         override_by = auth.uid(), override_at = now()
   where id = p_item_id;

  update public.invoices i
     set total_amount = coalesce((select sum(line_total) from public.invoice_items where invoice_id = v_inv.id),0)
                        - coalesce(i.discount_total,0)
   where i.id = v_inv.id;

  perform public.write_audit_ex('invoice_items', p_item_id, 'line_price_overridden',
    jsonb_build_object('old_mode', v_li.price_mode, 'old_price', v_li.unit_price),
    jsonb_build_object('new_mode', p_mode, 'new_price', v_new), 'pricing', p_reason, v_inv.store_id);
end $$;

-- ---------------------------------------------------------------------
-- THE PAYMENT FUNCTION — existing behaviour preserved, membership added.
-- ---------------------------------------------------------------------
create or replace function public.pay_invoice(p_invoice_id uuid, p_payments jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_pay jsonb; v_method uuid; v_amount numeric;
  v_total_paying numeric := 0; v_already_paid numeric; v_new_paid numeric;
  v_req record; v_available integer; v_li record;
  -- membership additions
  v_ms jsonb; v_is_member boolean; v_memline record; v_will_be_full boolean;
  v_start date; v_expiry date; v_prev public.customer_memberships%rowtype; v_plan public.membership_plans%rowtype;
  v_new_membership uuid;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access to this invoice''s store'; end if;
  if v_inv.status in ('paid','cancelled','refunded') then raise exception 'Invoice is already %', v_inv.status; end if;
  if p_payments is null or jsonb_array_length(p_payments) = 0 then raise exception 'At least one payment is required'; end if;

  -- ---- membership pre-checks (before taking money) ----
  select * into v_memline from public.invoice_membership_line(p_invoice_id) limit 1;
  v_ms := public.customer_membership_status(v_inv.customer_id);
  -- Effective membership = already a member, OR this invoice sells a membership.
  v_is_member := coalesce((v_ms->>'is_member')::boolean, false) or (v_memline.plan_id is not null);

  -- Sum the payment (validation preserved).
  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_amount := (v_pay->>'amount')::numeric;
    if v_amount is null or v_amount <= 0 then raise exception 'Payment amount must be positive'; end if;
    v_total_paying := v_total_paying + v_amount;
  end loop;

  -- Reprice non-overridden lines by member status, THEN read the fresh total.
  perform public.reprice_invoice_lines(p_invoice_id, v_is_member);
  select * into v_inv from public.invoices where id = p_invoice_id for update;

  v_already_paid := v_inv.paid_amount;
  v_new_paid := v_already_paid + v_total_paying;
  if v_new_paid > v_inv.total_amount + 0.001 then raise exception 'Payment exceeds remaining balance'; end if;
  v_will_be_full := v_new_paid >= v_inv.total_amount - 0.001;

  -- Member ID required before a membership line can be fully paid.
  if v_memline.plan_id is not null and v_will_be_full then
    if not exists (
      select 1 from public.member_id_reservations r
       where r.invoice_id = p_invoice_id and r.customer_id = v_inv.customer_id)
       and not exists (
      select 1 from public.member_ids m where m.customer_id = v_inv.customer_id)
    then
      raise exception 'A Member ID must be assigned before this membership can be paid';
    end if;
  end if;

  -- Promotion member-gating: non-member may buy a promotion only if the
  -- invoice also sells a membership OR the promotion line was overridden.
  if not coalesce((v_ms->>'is_member')::boolean,false) and v_memline.plan_id is null then
    if exists (
      select 1 from public.invoice_items ii
       where ii.invoice_id = p_invoice_id and ii.line_kind = 'promotion'
         and ii.price_overridden = false)
    then
      raise exception 'Promotions are for members only. Add a membership to this invoice or apply a manual override.';
    end if;
  end if;

  -- ---- stock check (preserved verbatim) ----
  if v_will_be_full then
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

  -- ---- record payments (preserved) ----
  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_method := (v_pay->>'payment_method_id')::uuid;
    v_amount := (v_pay->>'amount')::numeric;
    insert into public.invoice_payments (invoice_id, payment_method_id, amount, payment_reference, received_by)
    values (p_invoice_id, v_method, v_amount, v_pay->>'reference', auth.uid());
  end loop;

  if v_will_be_full then
    -- ---- deduct stock (preserved) ----
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

    -- ---- voucher redemptions (preserved) ----
    if v_inv.discount_voucher_id is not null then
      insert into public.voucher_redemptions (voucher_id, invoice_id, customer_id, discount_applied, redeemed_by)
      values (v_inv.discount_voucher_id, p_invoice_id, v_inv.customer_id,
              v_inv.discount_total - coalesce((select sum(line_discount) from public.invoice_items where invoice_id = p_invoice_id),0),
              auth.uid());
      perform public.write_audit('vouchers', v_inv.discount_voucher_id, 'voucher_redeemed', null,
        jsonb_build_object('invoice_no', v_inv.invoice_no));
    end if;
    for v_li in select line_voucher_id, line_discount from public.invoice_items
      where invoice_id = p_invoice_id and line_voucher_id is not null
    loop
      insert into public.voucher_redemptions (voucher_id, invoice_id, customer_id, discount_applied, redeemed_by)
      values (v_li.line_voucher_id, p_invoice_id, v_inv.customer_id, v_li.line_discount, auth.uid());
      perform public.write_audit('vouchers', v_li.line_voucher_id, 'voucher_redeemed', null,
        jsonb_build_object('invoice_no', v_inv.invoice_no, 'line_discount', v_li.line_discount));
    end loop;

    -- ---- MEMBERSHIP ACTIVATION (new) ----
    if v_memline.plan_id is not null then
      select * into v_plan from public.membership_plans where id = v_memline.plan_id;

      -- Renewal? If an active/expiring membership exists, start day after its expiry.
      select * into v_prev from public.customer_memberships
        where customer_id = v_inv.customer_id and deleted_at is null
          and status in ('active','expiring_soon')
        order by expiry_date desc nulls last limit 1;

      if found and v_prev.expiry_date is not null and v_prev.expiry_date >= public.sg_today() then
        v_start := public.membership_renewal_start(v_prev.expiry_date);
      else
        v_start := public.sg_today();
      end if;
      v_expiry := public.membership_expiry(v_start, v_plan.duration_months);

      insert into public.customer_memberships (
        customer_id, plan_id, store_id, member_id, source, invoice_id, invoice_item_id,
        fee_snapshot, start_date, expiry_date, status, is_renewal, previous_membership_id, activated_at, created_by)
      values (
        v_inv.customer_id, v_memline.plan_id, v_inv.store_id,
        (select member_id from public.member_id_reservations where invoice_id = p_invoice_id and customer_id = v_inv.customer_id limit 1),
        'sale', p_invoice_id, v_memline.item_id,
        v_memline.unit_price, v_start, v_expiry, 'active',
        (v_prev.id is not null), v_prev.id, now(), auth.uid())
      returning id into v_new_membership;

      -- Commit the reserved Member ID to permanent ownership.
      update public.customer_memberships set member_id = r.member_id
        from public.member_id_reservations r
        where r.invoice_id = p_invoice_id and customer_memberships.id = v_new_membership
          and customer_memberships.member_id is null;
      perform public.commit_member_id(
        (select member_id from public.customer_memberships where id = v_new_membership), v_inv.customer_id);

      perform public.write_audit_ex('customer_memberships', v_new_membership, 'membership_activated',
        null, jsonb_build_object('plan', v_plan.name, 'start', v_start, 'expiry', v_expiry,
                                 'renewal', (v_prev.id is not null), 'invoice_no', v_inv.invoice_no),
        'membership', null, v_inv.store_id);
    end if;

    -- ---- commissions (preserved — membership line is Own Product, earns normally) ----
    perform public.earn_invoice_commission(p_invoice_id);
    perform public.earn_staff_commission(p_invoice_id);

    perform public.write_audit('invoices', p_invoice_id, 'invoice_paid', null,
      jsonb_build_object('paid_amount', v_new_paid, 'invoice_no', v_inv.invoice_no,
                         'membership_created', (v_new_membership is not null)));
    return jsonb_build_object('success', true, 'status', 'paid', 'paid_amount', v_new_paid,
                              'membership_id', v_new_membership);
  else
    update public.invoices set paid_amount = v_new_paid, status = 'partially_paid' where id = p_invoice_id;
    perform public.write_audit('invoices', p_invoice_id, 'invoice_partial_payment', null,
      jsonb_build_object('paid_amount', v_new_paid));
    return jsonb_build_object('success', true, 'status', 'partially_paid', 'paid_amount', v_new_paid,
                              'remaining', v_inv.total_amount - v_new_paid);
  end if;
end; $$;

-- ---------------------------------------------------------------------
-- Release Member ID reservations when a membership line is removed or the
-- unpaid invoice is cancelled/deleted. (Hook for the invoice-edit UI.)
-- ---------------------------------------------------------------------
create or replace function public.remove_membership_line(p_item_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_li public.invoice_items%rowtype; v_inv public.invoices%rowtype;
begin
  select * into v_li from public.invoice_items where id = p_item_id and line_kind = 'membership';
  if not found then raise exception 'Membership line not found'; end if;
  select * into v_inv from public.invoices where id = v_li.invoice_id;
  if v_inv.status in ('paid','cancelled','refunded') then raise exception 'Invoice is locked'; end if;
  if not (public.is_manager_or_above() or public.user_has_store_access(v_inv.store_id)) then
    raise exception 'No access'; end if;

  perform public.release_member_id_reservations_for_invoice(v_inv.id);
  delete from public.invoice_items where id = p_item_id;

  update public.invoices i
     set total_amount = coalesce((select sum(line_total) from public.invoice_items where invoice_id = i.id),0)
                        - coalesce(i.discount_total,0)
   where i.id = v_inv.id;

  -- Non-overridden lines return to non-member pricing if the customer isn't
  -- otherwise a member.
  perform public.reprice_invoice_lines(v_inv.id,
    coalesce((public.customer_membership_status(v_inv.customer_id)->>'is_member')::boolean, false));
end $$;

notify pgrst, 'reload schema';
