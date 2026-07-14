-- =====================================================================
-- ENERGIA — NEW SPEC PHASE 3B: Bundle exchanges
--
-- Two flows on top of 3A's tables:
--   A) Bundle-to-bundle (3.8): a WHOLE bundle A -> a WHOLE bundle B.
--      No partial. Credit = current regular total of bundle A at the
--      processing store; replacement = current regular total of bundle B.
--      Each A component returned to stock individually; each B component
--      deducted individually. Top-up / non-refundable like 3A.
--   B) Bundle-component (3.9): ONE component of bundle A -> a normal
--      product. Credit = that component's current store price. Original
--      bundle stays recorded; the component can't be exchanged twice.
--      Own<->own / third<->third enforced.
--
-- Reuses: promotion_stock_items(), invoice_promotion_selections,
-- store_product_prices, product_exchanges/items/payments (3A). Direct
-- completion, atomic, reason mandatory, locked on completion.
--
-- Additive + idempotent. Run AFTER 33_specphase3a_product_exchange.sql.
-- =====================================================================

set check_function_bodies = off;

-- Tag the exchange kind + which invoice line / component was exchanged.
alter table public.product_exchanges add column if not exists exchange_kind text not null default 'product';
alter table public.invoice_items add column if not exists component_exchanged jsonb default '[]'::jsonb;

-- ---------------------------------------------------------------------
-- Helper: full component list (product, qty) of ONE bundle invoice line
-- = fixed promotion_stock_items + chosen invoice_promotion_selections.
-- ---------------------------------------------------------------------
create or replace function public.bundle_line_components(p_invoice_item_id uuid)
returns table(product_id uuid, quantity bigint)
language sql stable security definer set search_path = public as $$
  with fixed as (
    select s.item_id as product_id, s.quantity::bigint as quantity
    from public.invoice_items ii
    cross join lateral public.promotion_stock_items(ii.promotion_id, ii.quantity) s
    where ii.id = p_invoice_item_id and ii.line_kind = 'promotion' and s.kind = 'product'
  ),
  chosen as (
    select ips.product_id, ips.quantity::bigint as quantity
    from public.invoice_promotion_selections ips
    where ips.invoice_item_id = p_invoice_item_id and ips.product_id is not null
  )
  select product_id, sum(quantity) as quantity from (select * from fixed union all select * from chosen) u
  group by product_id
$$;

-- ---------------------------------------------------------------------
-- A) Bundle-to-bundle exchange.
-- ---------------------------------------------------------------------
create or replace function public.create_bundle_exchange(
  p_original_invoice_id uuid,
  p_processing_store_id uuid,
  p_original_invoice_item_id uuid,   -- the bundle A line on the original invoice
  p_new_promotion_id uuid,           -- bundle B
  p_payments jsonb default '[]'::jsonb,
  p_reason text default null,
  p_notes text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_item public.invoice_items%rowtype;
  v_reason text; v_role user_role; v_ex_id uuid; v_no text;
  v_credit numeric := 0; v_repl numeric := 0; v_topup numeric; v_nonref numeric := 0; v_pay_sum numeric := 0;
  v_comp record; v_price numeric; v_avail integer; v_line jsonb;
begin
  v_role := public.current_user_role();
  if v_role is null then raise exception 'No profile for current user'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason is required for the exchange'; end if;

  v_reason := public.exchange_ineligibility_reason(p_original_invoice_id);
  if v_reason <> '' then raise exception '%', v_reason; end if;

  select * into v_inv from public.invoices where id = p_original_invoice_id for update;
  if v_role = 'staff' and public.my_assigned_store_id() is distinct from p_processing_store_id then
    raise exception 'You can only process exchanges for your assigned store'; end if;
  if not public.user_has_store_access(p_processing_store_id) then
    raise exception 'You do not have access to the processing store'; end if;

  select * into v_item from public.invoice_items where id = p_original_invoice_item_id and invoice_id = p_original_invoice_id for update;
  if not found then raise exception 'Bundle line not found on the original invoice'; end if;
  if v_item.line_kind <> 'promotion' then raise exception 'That line is not a bundle'; end if;
  if v_item.exchanged_at is not null then raise exception 'This bundle has already been exchanged'; end if;

  -- Credit = current regular total of bundle A; replacement = bundle B.
  v_credit := public.promotion_original_total(v_item.promotion_id, p_processing_store_id);
  v_repl := public.promotion_original_total(p_new_promotion_id, p_processing_store_id);
  if v_credit is null or v_repl is null then raise exception 'Bundle price unavailable at the processing store'; end if;

  -- Stock check: bundle B fixed components must be available at the store.
  for v_comp in select s.item_id as product_id, s.quantity from public.promotion_stock_items(p_new_promotion_id, 1) s where s.kind = 'product'
  loop
    select current_qty into v_avail from public.store_inventory where store_id = p_processing_store_id and product_id = v_comp.product_id for update;
    if coalesce(v_avail,0) < v_comp.quantity then
      raise exception 'Insufficient stock for a component of the replacement bundle'; end if;
  end loop;

  v_topup := round(v_repl - v_credit, 2);
  if v_topup > 0 then
    select coalesce(sum((x->>'amount')::numeric),0) into v_pay_sum from jsonb_array_elements(p_payments) x;
    if round(v_pay_sum,2) <> v_topup then raise exception 'Top-up payment (%.2f) must equal the amount due (%.2f)', v_pay_sum, v_topup; end if;
  elsif v_topup < 0 then v_nonref := -v_topup; v_topup := 0; else v_topup := 0; end if;

  v_no := 'EXB-' || to_char(now() at time zone 'Asia/Singapore','YYYYMMDD') || '-' || substr(gen_random_uuid()::text,1,6);
  insert into public.product_exchanges
    (exchange_no, original_invoice_id, customer_id, processing_store_id, affiliate_id,
     returned_credit_total, replacement_total, topup_amount, nonrefundable_amount, status, exchange_kind, reason, notes, created_by, locked_at)
  values (v_no, p_original_invoice_id, v_inv.customer_id, p_processing_store_id, v_inv.affiliate_id,
     v_credit, v_repl, v_topup, v_nonref, 'completed', 'bundle', p_reason, p_notes, auth.uid(), now())
  returning id into v_ex_id;

  -- Return each bundle A component individually.
  for v_comp in select product_id, quantity from public.bundle_line_components(p_original_invoice_item_id)
  loop
    select selling_price into v_price from public.store_product_prices where store_id = p_processing_store_id and product_id = v_comp.product_id and is_active = true;
    insert into public.product_exchange_items (exchange_id, direction, original_invoice_item_id, product_id, quantity, unit_price, line_total)
    values (v_ex_id, 'returned', p_original_invoice_item_id, v_comp.product_id, v_comp.quantity, coalesce(v_price,0), coalesce(v_price,0)*v_comp.quantity);
    insert into public.store_inventory (store_id, product_id, current_qty) values (p_processing_store_id, v_comp.product_id, v_comp.quantity)
      on conflict (store_id, product_id) do update set current_qty = public.store_inventory.current_qty + excluded.current_qty, updated_at = now();
    insert into public.stock_movements (product_id, movement_type, to_store_id, quantity, notes, created_by)
      values (v_comp.product_id, 'exchange_return_in', p_processing_store_id, v_comp.quantity, 'Bundle exchange ' || v_no || ' — returned component', auth.uid());
  end loop;

  -- Deduct each bundle B fixed component individually.
  for v_comp in select s.item_id as product_id, s.quantity from public.promotion_stock_items(p_new_promotion_id, 1) s where s.kind = 'product'
  loop
    select selling_price into v_price from public.store_product_prices where store_id = p_processing_store_id and product_id = v_comp.product_id and is_active = true;
    insert into public.product_exchange_items (exchange_id, direction, product_id, quantity, unit_price, line_total)
    values (v_ex_id, 'replacement', v_comp.product_id, v_comp.quantity, coalesce(v_price,0), coalesce(v_price,0)*v_comp.quantity);
    update public.store_inventory set current_qty = current_qty - v_comp.quantity, updated_at = now()
      where store_id = p_processing_store_id and product_id = v_comp.product_id;
    insert into public.stock_movements (product_id, movement_type, from_store_id, quantity, notes, created_by)
      values (v_comp.product_id, 'exchange_replacement_out', p_processing_store_id, v_comp.quantity, 'Bundle exchange ' || v_no || ' — replacement component', auth.uid());
  end loop;

  update public.invoice_items set exchanged_at = now(), exchange_id = v_ex_id where id = p_original_invoice_item_id;

  if v_topup > 0 then
    for v_line in select * from jsonb_array_elements(p_payments) loop
      insert into public.product_exchange_payments (exchange_id, payment_method_id, amount, reference)
      values (v_ex_id, nullif(v_line->>'payment_method_id','')::uuid, (v_line->>'amount')::numeric, nullif(v_line->>'reference',''));
    end loop;
  end if;

  perform public.write_audit_ex('product_exchanges', v_ex_id, 'bundle_exchange_completed', null,
    jsonb_build_object('exchange_no', v_no, 'credit', v_credit, 'replacement', v_repl, 'topup', v_topup, 'nonrefundable', v_nonref),
    'exchanges', p_reason, p_processing_store_id);
  return jsonb_build_object('success', true, 'id', v_ex_id, 'exchange_no', v_no, 'topup', v_topup, 'nonrefundable', v_nonref);
end $$;

-- ---------------------------------------------------------------------
-- B) Bundle-component exchange: one component -> a normal product.
-- ---------------------------------------------------------------------
create or replace function public.create_bundle_component_exchange(
  p_original_invoice_id uuid,
  p_processing_store_id uuid,
  p_original_invoice_item_id uuid,   -- the bundle line
  p_component_product_id uuid,       -- which component of the bundle
  p_component_qty integer,
  p_replacement jsonb,               -- [{product_id, quantity}]
  p_payments jsonb default '[]'::jsonb,
  p_reason text default null,
  p_notes text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_item public.invoice_items%rowtype;
  v_reason text; v_role user_role; v_ex_id uuid; v_no text;
  v_credit numeric := 0; v_repl numeric := 0; v_topup numeric; v_nonref numeric := 0; v_pay_sum numeric := 0;
  v_price numeric; v_avail integer; v_line jsonb; v_prod_id uuid; v_qty integer;
  v_comp_type product_type; v_repl_type product_type; v_have bigint; v_done jsonb; v_already boolean;
begin
  v_role := public.current_user_role();
  if v_role is null then raise exception 'No profile for current user'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason is required for the exchange'; end if;

  v_reason := public.exchange_ineligibility_reason(p_original_invoice_id);
  if v_reason <> '' then raise exception '%', v_reason; end if;

  select * into v_inv from public.invoices where id = p_original_invoice_id for update;
  if v_role = 'staff' and public.my_assigned_store_id() is distinct from p_processing_store_id then
    raise exception 'You can only process exchanges for your assigned store'; end if;
  if not public.user_has_store_access(p_processing_store_id) then
    raise exception 'You do not have access to the processing store'; end if;

  select * into v_item from public.invoice_items where id = p_original_invoice_item_id and invoice_id = p_original_invoice_id for update;
  if not found then raise exception 'Bundle line not found on the original invoice'; end if;
  if v_item.line_kind <> 'promotion' then raise exception 'That line is not a bundle'; end if;
  if v_item.exchanged_at is not null then raise exception 'This bundle has already been fully exchanged'; end if;

  -- Component must exist in the bundle with enough quantity.
  select quantity into v_have from public.bundle_line_components(p_original_invoice_item_id) where product_id = p_component_product_id;
  if v_have is null then raise exception 'That product is not a component of this bundle'; end if;
  if p_component_qty is null or p_component_qty <= 0 or p_component_qty > v_have then
    raise exception 'Invalid component quantity (bundle has % of that product)', v_have; end if;

  -- Not already component-exchanged.
  select coalesce(component_exchanged, '[]'::jsonb) into v_done from public.invoice_items where id = p_original_invoice_item_id;
  select exists (select 1 from jsonb_array_elements(v_done) e where (e->>'product_id')::uuid = p_component_product_id) into v_already;
  if v_already then raise exception 'That component has already been exchanged'; end if;

  select product_type into v_comp_type from public.products where id = p_component_product_id;

  -- Credit = component current store price * qty.
  select selling_price into v_price from public.store_product_prices where store_id = p_processing_store_id and product_id = p_component_product_id and is_active = true;
  if v_price is null then raise exception 'Component has no active price at the processing store'; end if;
  v_credit := v_price * p_component_qty;

  -- Replacement: same product type, stock, total.
  if p_replacement is null or jsonb_array_length(p_replacement) = 0 then raise exception 'Select at least one replacement product'; end if;
  for v_line in select * from jsonb_array_elements(p_replacement) loop
    v_prod_id := (v_line->>'product_id')::uuid; v_qty := (v_line->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Replacement quantity must be greater than zero'; end if;
    select product_type into v_repl_type from public.products where id = v_prod_id;
    if v_repl_type is null then raise exception 'Replacement product not found'; end if;
    if v_repl_type <> v_comp_type then raise exception 'Own products may only be exchanged for own products, and third-party for third-party'; end if;
    select selling_price into v_price from public.store_product_prices where store_id = p_processing_store_id and product_id = v_prod_id and is_active = true;
    if v_price is null then raise exception 'A replacement product has no active price at the processing store'; end if;
    v_repl := v_repl + v_price * v_qty;
    select current_qty into v_avail from public.store_inventory where store_id = p_processing_store_id and product_id = v_prod_id for update;
    if coalesce(v_avail,0) < v_qty then raise exception 'Insufficient replacement stock at the processing store'; end if;
  end loop;

  v_topup := round(v_repl - v_credit, 2);
  if v_topup > 0 then
    select coalesce(sum((x->>'amount')::numeric),0) into v_pay_sum from jsonb_array_elements(p_payments) x;
    if round(v_pay_sum,2) <> v_topup then raise exception 'Top-up payment (%.2f) must equal the amount due (%.2f)', v_pay_sum, v_topup; end if;
  elsif v_topup < 0 then v_nonref := -v_topup; v_topup := 0; else v_topup := 0; end if;

  v_no := 'EXC-' || to_char(now() at time zone 'Asia/Singapore','YYYYMMDD') || '-' || substr(gen_random_uuid()::text,1,6);
  insert into public.product_exchanges
    (exchange_no, original_invoice_id, customer_id, processing_store_id, affiliate_id,
     returned_credit_total, replacement_total, topup_amount, nonrefundable_amount, status, exchange_kind, reason, notes, created_by, locked_at)
  values (v_no, p_original_invoice_id, v_inv.customer_id, p_processing_store_id, v_inv.affiliate_id,
     v_credit, v_repl, v_topup, v_nonref, 'completed', 'bundle_component', p_reason, p_notes, auth.uid(), now())
  returning id into v_ex_id;

  -- Return the component individually.
  insert into public.product_exchange_items (exchange_id, direction, original_invoice_item_id, product_id, quantity, unit_price, line_total)
  values (v_ex_id, 'returned', p_original_invoice_item_id, p_component_product_id, p_component_qty, v_credit / p_component_qty, v_credit);
  insert into public.store_inventory (store_id, product_id, current_qty) values (p_processing_store_id, p_component_product_id, p_component_qty)
    on conflict (store_id, product_id) do update set current_qty = public.store_inventory.current_qty + excluded.current_qty, updated_at = now();
  insert into public.stock_movements (product_id, movement_type, to_store_id, quantity, notes, created_by)
    values (p_component_product_id, 'exchange_return_in', p_processing_store_id, p_component_qty, 'Component exchange ' || v_no, auth.uid());

  -- Deduct replacements.
  for v_line in select * from jsonb_array_elements(p_replacement) loop
    v_prod_id := (v_line->>'product_id')::uuid; v_qty := (v_line->>'quantity')::integer;
    select selling_price into v_price from public.store_product_prices where store_id = p_processing_store_id and product_id = v_prod_id and is_active = true;
    insert into public.product_exchange_items (exchange_id, direction, product_id, quantity, unit_price, line_total)
    values (v_ex_id, 'replacement', v_prod_id, v_qty, v_price, v_price * v_qty);
    update public.store_inventory set current_qty = current_qty - v_qty, updated_at = now() where store_id = p_processing_store_id and product_id = v_prod_id;
    insert into public.stock_movements (product_id, movement_type, from_store_id, quantity, notes, created_by)
      values (v_prod_id, 'exchange_replacement_out', p_processing_store_id, v_qty, 'Component exchange ' || v_no || ' — replacement', auth.uid());
  end loop;

  -- Mark this component exchanged (bundle line stays; not fully exchanged).
  update public.invoice_items
    set component_exchanged = coalesce(component_exchanged,'[]'::jsonb) || jsonb_build_object('product_id', p_component_product_id, 'qty', p_component_qty, 'exchange_id', v_ex_id)
    where id = p_original_invoice_item_id;

  if v_topup > 0 then
    for v_line in select * from jsonb_array_elements(p_payments) loop
      insert into public.product_exchange_payments (exchange_id, payment_method_id, amount, reference)
      values (v_ex_id, nullif(v_line->>'payment_method_id','')::uuid, (v_line->>'amount')::numeric, nullif(v_line->>'reference',''));
    end loop;
  end if;

  perform public.write_audit_ex('product_exchanges', v_ex_id, 'bundle_component_exchange_completed', null,
    jsonb_build_object('exchange_no', v_no, 'component', p_component_product_id, 'credit', v_credit, 'replacement', v_repl, 'topup', v_topup),
    'exchanges', p_reason, p_processing_store_id);
  return jsonb_build_object('success', true, 'id', v_ex_id, 'exchange_no', v_no, 'topup', v_topup, 'nonrefundable', v_nonref);
end $$;

notify pgrst, 'reload schema';
