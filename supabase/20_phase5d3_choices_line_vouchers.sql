-- =====================================================================
-- ENERGIA — PHASE 5D-3: Promotion choice groups + per-line discount vouchers
--
-- 1) CHOICE GROUPS: a promotion can now contain, alongside its fixed items,
--    groups like "choose 1 product from {P1,P2,P3}" or "choose 6 vouchers
--    from {V1,V2,V3}". The cashier makes the picks at invoice time (repeats
--    allowed, e.g. 6×V1). Picks scale with line qty. Stock deduction and
--    commission follow the CHOSEN items. Promotions with choice groups
--    cannot be nested.
--
-- 2) PER-LINE DISCOUNT VOUCHERS: each PRODUCT line may carry one discount
--    voucher (applied to that line's total). The whole-invoice discount
--    voucher still exists and is still blocked when a promotion line is
--    present — but per-line vouchers work regardless, so products sold
--    alongside a bundle can be discounted while the bundle price stays fixed.
--
-- Additive + idempotent. Run AFTER 19_phase5d2_promotion_sales.sql.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Schema
-- ---------------------------------------------------------------------
create table if not exists public.promotion_choice_groups (
  id uuid primary key default gen_random_uuid(),
  promotion_id uuid not null references public.promotions(id) on delete cascade,
  label text not null,
  item_kind text not null check (item_kind in ('product','voucher')),
  choose_qty integer not null check (choose_qty > 0),
  created_at timestamptz not null default now()
);
create index if not exists idx_choice_groups_promo on public.promotion_choice_groups(promotion_id);

create table if not exists public.promotion_choice_options (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.promotion_choice_groups(id) on delete cascade,
  product_id uuid references public.products(id),
  voucher_id uuid references public.vouchers(id),
  created_at timestamptz not null default now(),
  check (product_id is not null or voucher_id is not null)
);
create index if not exists idx_choice_options_group on public.promotion_choice_options(group_id);

create table if not exists public.invoice_promotion_selections (
  id uuid primary key default gen_random_uuid(),
  invoice_item_id uuid not null references public.invoice_items(id) on delete cascade,
  group_id uuid references public.promotion_choice_groups(id),
  product_id uuid references public.products(id),
  voucher_id uuid references public.vouchers(id),
  quantity integer not null check (quantity > 0),
  created_at timestamptz not null default now()
);
create index if not exists idx_inv_promo_sel_item on public.invoice_promotion_selections(invoice_item_id);

alter table public.invoice_items add column if not exists line_voucher_id uuid references public.vouchers(id);
alter table public.invoice_items add column if not exists line_discount numeric(12,2) not null default 0;

alter table public.promotion_choice_groups enable row level security;
drop policy if exists "read choice groups" on public.promotion_choice_groups;
create policy "read choice groups" on public.promotion_choice_groups for select to authenticated using (true);
drop policy if exists "manage choice groups" on public.promotion_choice_groups;
create policy "manage choice groups" on public.promotion_choice_groups for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

alter table public.promotion_choice_options enable row level security;
drop policy if exists "read choice options" on public.promotion_choice_options;
create policy "read choice options" on public.promotion_choice_options for select to authenticated using (true);
drop policy if exists "manage choice options" on public.promotion_choice_options;
create policy "manage choice options" on public.promotion_choice_options for all to authenticated
  using (public.is_owner_or_manager()) with check (public.is_owner_or_manager());

alter table public.invoice_promotion_selections enable row level security;
drop policy if exists "read invoice selections" on public.invoice_promotion_selections;
create policy "read invoice selections" on public.invoice_promotion_selections for select to authenticated using (true);

-- ---------------------------------------------------------------------
-- 2. Nesting: promotions with choice groups cannot be nested.
-- ---------------------------------------------------------------------
create or replace function public.validate_promotion_child(p_parent_id uuid, p_child_id uuid)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if p_parent_id = p_child_id then
    raise exception 'A promotion cannot include itself';
  end if;
  if public.promotion_has_children(p_child_id) then
    raise exception 'Nesting limit: "%" already contains a promotion, so it cannot be nested inside another (max 2 levels).',
      (select name from public.promotions where id = p_child_id);
  end if;
  if exists (select 1 from public.promotion_items where child_promotion_id = p_parent_id) then
    raise exception 'This promotion is already used inside another promotion, so it cannot contain a nested promotion (max 2 levels).';
  end if;
  if exists (select 1 from public.promotion_choice_groups where promotion_id = p_child_id) then
    raise exception 'Promotions with choice groups cannot be nested inside another promotion.';
  end if;
end; $$;

-- ---------------------------------------------------------------------
-- 3. create_invoice — per-line vouchers + choice selections.
--    p_items entries:
--      {kind:'product',  product_id, quantity, line_voucher_id?}
--      {kind:'voucher',  voucher_id, quantity}
--      {kind:'promotion',promotion_id, quantity,
--        selections:[{group_id, options:[{product_id?|voucher_id?, quantity}]}]}
-- ---------------------------------------------------------------------
create or replace function public.create_invoice(
  p_store_id uuid, p_customer_id uuid, p_affiliate_id uuid,
  p_items jsonb, p_discount_total numeric default 0, p_notes text default null,
  p_discount_voucher_id uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_item jsonb; v_kind text; v_product_id uuid; v_voucher_id uuid; v_promo_id uuid;
  v_qty integer; v_price numeric; v_subtotal numeric := 0; v_line_total numeric;
  v_invoice_id uuid; v_invoice_no text; v_manual numeric := coalesce(p_discount_total,0);
  v_has_promo boolean := false; v_promo public.promotions%rowtype;
  v_line_voucher uuid; v_line_disc numeric; v_line_disc_sum numeric := 0;
  v_lv public.vouchers%rowtype; v_discount numeric;
  v_grp record; v_sel jsonb; v_opt jsonb; v_provided integer; v_required integer;
  v_item_id uuid; v_sel_group uuid; v_ok boolean;
begin
  if not public.user_has_store_access(p_store_id) then raise exception 'You do not have access to this store'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'At least one item is required'; end if;

  -- PASS 1: validate + price + accumulate subtotal and line discounts.
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
      v_subtotal := v_subtotal + (v_price * v_qty);

      -- Validate choice selections: every group satisfied exactly.
      for v_grp in select * from public.promotion_choice_groups where promotion_id = v_promo_id
      loop
        v_required := v_grp.choose_qty * v_qty;
        v_provided := 0;
        for v_sel in select * from jsonb_array_elements(coalesce(v_item->'selections','[]'::jsonb))
        loop
          if (v_sel->>'group_id')::uuid = v_grp.id then
            for v_opt in select * from jsonb_array_elements(coalesce(v_sel->'options','[]'::jsonb))
            loop
              if coalesce((v_opt->>'quantity')::integer,0) <= 0 then continue; end if;
              -- the option must exist in this group
              select exists (
                select 1 from public.promotion_choice_options o
                where o.group_id = v_grp.id
                  and ((v_opt->>'product_id') is not null and o.product_id = (v_opt->>'product_id')::uuid
                    or (v_opt->>'voucher_id') is not null and o.voucher_id = (v_opt->>'voucher_id')::uuid)
              ) into v_ok;
              if not v_ok then raise exception 'A selected option does not belong to choice group "%"', v_grp.label; end if;
              v_provided := v_provided + (v_opt->>'quantity')::integer;
            end loop;
          end if;
        end loop;
        if v_provided <> v_required then
          raise exception 'Choice group "%" requires % selection(s), got %', v_grp.label, v_required, v_provided;
        end if;
      end loop;

    elsif v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      select selling_price into v_price from public.vouchers
        where id = v_voucher_id and is_active = true and deleted_at is null;
      if v_price is null then raise exception 'Voucher not found or inactive'; end if;
      v_subtotal := v_subtotal + (v_price * v_qty);
    else
      v_product_id := (v_item->>'product_id')::uuid;
      select selling_price into v_price from public.store_product_prices
        where store_id = p_store_id and product_id = v_product_id and is_active = true and deleted_at is null;
      if v_price is null then raise exception 'No price set for a product in this store'; end if;
      v_line_total := v_price * v_qty;
      v_subtotal := v_subtotal + v_line_total;

      -- Per-line discount voucher (discount kinds only, one per line).
      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      if v_line_voucher is not null then
        select * into v_lv from public.vouchers where id = v_line_voucher and deleted_at is null;
        if not found then raise exception 'Line voucher not found'; end if;
        if v_lv.voucher_kind = 'normal' then raise exception 'Voucher "%" is not a discount voucher', v_lv.name; end if;
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
        v_line_disc_sum := v_line_disc_sum + v_line_disc;
      end if;
    end if;
  end loop;

  -- Whole-invoice discount voucher: still one per invoice, still blocked on bundles.
  if p_discount_voucher_id is not null and v_has_promo then
    raise exception 'A whole-invoice discount voucher cannot be used when the invoice contains a promotion/bundle. Use per-product vouchers instead.';
  end if;

  v_discount := v_manual + v_line_disc_sum;
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

  -- PASS 2: insert lines (+ selections).
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    if v_kind = 'promotion' then
      v_promo_id := (v_item->>'promotion_id')::uuid;
      select fixed_price into v_price from public.promotions where id = v_promo_id;
      insert into public.invoice_items (invoice_id, line_kind, promotion_id, product_id, quantity, unit_price, line_total)
      values (v_invoice_id, 'promotion', v_promo_id, null, v_qty, v_price, v_price * v_qty)
      returning id into v_item_id;

      for v_sel in select * from jsonb_array_elements(coalesce(v_item->'selections','[]'::jsonb))
      loop
        v_sel_group := (v_sel->>'group_id')::uuid;
        for v_opt in select * from jsonb_array_elements(coalesce(v_sel->'options','[]'::jsonb))
        loop
          if coalesce((v_opt->>'quantity')::integer,0) <= 0 then continue; end if;
          insert into public.invoice_promotion_selections (invoice_item_id, group_id, product_id, voucher_id, quantity)
          values (v_item_id, v_sel_group,
                  nullif(v_opt->>'product_id','')::uuid, nullif(v_opt->>'voucher_id','')::uuid,
                  (v_opt->>'quantity')::integer);
        end loop;
      end loop;

    elsif v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      select selling_price into v_price from public.vouchers where id = v_voucher_id;
      insert into public.invoice_items (invoice_id, line_kind, voucher_id, product_id, quantity, unit_price, line_total)
      values (v_invoice_id, 'voucher', v_voucher_id, null, v_qty, v_price, v_price * v_qty);
    else
      v_product_id := (v_item->>'product_id')::uuid;
      select selling_price into v_price from public.store_product_prices
        where store_id = p_store_id and product_id = v_product_id and is_active = true and deleted_at is null;
      v_line_total := v_price * v_qty;
      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      v_line_disc := 0;
      if v_line_voucher is not null then
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
      end if;
      insert into public.invoice_items (invoice_id, line_kind, product_id, quantity, unit_price, line_total, line_voucher_id, line_discount)
      values (v_invoice_id, 'product', v_product_id, v_qty, v_price, v_line_total, v_line_voucher, v_line_disc);
    end if;
  end loop;

  perform public.write_audit('invoices', v_invoice_id, 'invoice_created', null,
    jsonb_build_object('invoice_no', v_invoice_no, 'total', v_subtotal - v_discount,
                       'has_promotion', v_has_promo, 'line_voucher_discounts', v_line_disc_sum));
  return v_invoice_id;
end; $$;

-- ---------------------------------------------------------------------
-- 4. invoice_required_stock — include chosen selection items.
-- ---------------------------------------------------------------------
create or replace function public.invoice_required_stock(p_invoice_id uuid)
returns table (kind text, item_id uuid, quantity bigint)
language sql stable security definer set search_path = public as $$
  with expanded as (
    select 'product'::text as kind, ii.product_id as item_id, ii.quantity::bigint as quantity
    from public.invoice_items ii
    where ii.invoice_id = p_invoice_id and ii.line_kind = 'product'
    union all
    select 'voucher', ii.voucher_id, ii.quantity::bigint
    from public.invoice_items ii
    join public.vouchers v on v.id = ii.voucher_id and v.qty_type = 'limited'
    where ii.invoice_id = p_invoice_id and ii.line_kind = 'voucher'
    union all
    select s.kind, s.item_id, (s.quantity)::bigint
    from public.invoice_items ii
    cross join lateral public.promotion_stock_items(ii.promotion_id, ii.quantity) s
    where ii.invoice_id = p_invoice_id and ii.line_kind = 'promotion'
    union all
    -- chosen products from choice groups
    select 'product', ips.product_id, ips.quantity::bigint
    from public.invoice_promotion_selections ips
    join public.invoice_items ii on ii.id = ips.invoice_item_id
    where ii.invoice_id = p_invoice_id and ips.product_id is not null
    union all
    -- chosen limited vouchers from choice groups
    select 'voucher', ips.voucher_id, ips.quantity::bigint
    from public.invoice_promotion_selections ips
    join public.invoice_items ii on ii.id = ips.invoice_item_id
    join public.vouchers v on v.id = ips.voucher_id and v.qty_type = 'limited'
    where ii.invoice_id = p_invoice_id and ips.voucher_id is not null
  )
  select kind, item_id, sum(quantity) as quantity
  from expanded
  group by kind, item_id
$$;

-- ---------------------------------------------------------------------
-- 5. pay_invoice — record per-line voucher redemptions on full payment.
--    (Stock check/deduct/refund all flow through invoice_required_stock,
--     which now covers selections, so only the redemption block changes.)
-- ---------------------------------------------------------------------
create or replace function public.pay_invoice(p_invoice_id uuid, p_payments jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_pay jsonb; v_method uuid; v_amount numeric;
  v_total_paying numeric := 0; v_already_paid numeric; v_new_paid numeric;
  v_req record; v_available integer; v_li record;
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

    -- Whole-invoice discount voucher redemption.
    if v_inv.discount_voucher_id is not null then
      insert into public.voucher_redemptions (voucher_id, invoice_id, customer_id, discount_applied, redeemed_by)
      values (v_inv.discount_voucher_id, p_invoice_id, v_inv.customer_id,
              v_inv.discount_total - coalesce((select sum(line_discount) from public.invoice_items where invoice_id = p_invoice_id),0),
              auth.uid());
      perform public.write_audit('vouchers', v_inv.discount_voucher_id, 'voucher_redeemed', null,
        jsonb_build_object('invoice_no', v_inv.invoice_no));
    end if;

    -- Per-line voucher redemptions.
    for v_li in select line_voucher_id, line_discount from public.invoice_items
      where invoice_id = p_invoice_id and line_voucher_id is not null
    loop
      insert into public.voucher_redemptions (voucher_id, invoice_id, customer_id, discount_applied, redeemed_by)
      values (v_li.line_voucher_id, p_invoice_id, v_inv.customer_id, v_li.line_discount, auth.uid());
      perform public.write_audit('vouchers', v_li.line_voucher_id, 'voucher_redeemed', null,
        jsonb_build_object('invoice_no', v_inv.invoice_no, 'line_discount', v_li.line_discount));
    end loop;

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
-- 6. earn_invoice_commission — per-line vouchers reduce the line basis
--    directly; invoice-level discount (manual + whole-invoice voucher) is
--    allocated proportionally over the voucher-reduced line amounts.
--    Promotion lines include CHOSEN items in the own/3rd-party split.
-- ---------------------------------------------------------------------
create or replace function public.earn_invoice_commission(p_invoice_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invoices%rowtype; v_tier1 uuid; v_tier2 uuid; v_item record;
  v_ptype text; v_line_after numeric; v_t1_rate numeric; v_t1_amt numeric; v_t2_amt numeric;
  v_paid_date date; v_own_orig numeric; v_third_orig numeric; v_tot_orig numeric; v_portion numeric;
  v_line_disc_sum numeric; v_invoice_level numeric; v_base_total numeric; v_line_net numeric;
  v_sel_own numeric; v_sel_third numeric;
begin
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then return; end if;

  select tier1, tier2 into v_tier1, v_tier2 from public.customer_referrers(v_inv.customer_id);
  if v_tier1 is null then return; end if;

  v_paid_date := coalesce(v_inv.paid_at, now())::date;
  select coalesce(sum(line_discount),0) into v_line_disc_sum from public.invoice_items where invoice_id = p_invoice_id;
  v_invoice_level := coalesce(v_inv.discount_total,0) - v_line_disc_sum;   -- manual + whole-invoice voucher
  v_base_total := coalesce(v_inv.subtotal,0) - v_line_disc_sum;

  for v_item in
    select ii.id, ii.line_kind, ii.voucher_id, ii.promotion_id, ii.quantity, ii.line_total, ii.line_discount,
           coalesce(p.product_type::text, 'own') as ptype
    from public.invoice_items ii
    left join public.products p on p.id = ii.product_id
    where ii.invoice_id = p_invoice_id
  loop
    v_line_net := v_item.line_total - coalesce(v_item.line_discount,0);
    if v_base_total > 0 then
      v_line_after := v_line_net - (v_invoice_level * (v_line_net / v_base_total));
    else
      v_line_after := v_line_net;
    end if;
    if v_line_after < 0 then v_line_after := 0; end if;
    if v_line_after = 0 then continue; end if;

    if v_item.line_kind = 'promotion' then
      -- Fixed contents
      select
        coalesce(sum(case when ptype = 'third_party' then 0 else original_value end),0),
        coalesce(sum(case when ptype = 'third_party' then original_value else 0 end),0)
        into v_own_orig, v_third_orig
      from public.promotion_commission_items(v_item.promotion_id, v_inv.store_id, v_item.quantity);

      -- Chosen contents (selections): products by type at store price; vouchers = own.
      select
        coalesce(sum(case
          when s.product_id is not null and coalesce(pp.product_type::text,'own') <> 'third_party'
            then coalesce(spp.selling_price,0) * s.quantity
          when s.voucher_id is not null then coalesce(vv.selling_price,0) * s.quantity
          else 0 end),0),
        coalesce(sum(case
          when s.product_id is not null and coalesce(pp.product_type::text,'own') = 'third_party'
            then coalesce(spp.selling_price,0) * s.quantity
          else 0 end),0)
        into v_sel_own, v_sel_third
      from public.invoice_promotion_selections s
      left join public.products pp on pp.id = s.product_id
      left join public.store_product_prices spp on spp.store_id = v_inv.store_id and spp.product_id = s.product_id
        and spp.is_active = true and spp.deleted_at is null
      left join public.vouchers vv on vv.id = s.voucher_id
      where s.invoice_item_id = v_item.id;

      v_own_orig := v_own_orig + v_sel_own;
      v_third_orig := v_third_orig + v_sel_third;
      v_tot_orig := v_own_orig + v_third_orig;
      if v_tot_orig <= 0 then v_own_orig := 1; v_third_orig := 0; v_tot_orig := 1; end if;

      if v_own_orig > 0 then
        v_portion := round(v_line_after * v_own_orig / v_tot_orig, 2);
        v_t1_amt := round(v_portion * 15 / 100.0, 2);
        if v_t1_amt > 0 then
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', 'own', v_portion, 15, v_t1_amt, 'earned', v_paid_date);
          if v_tier2 is not null then
            v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
            if v_t2_amt > 0 then
              insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
              values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', 'own', v_t1_amt, 5.0, v_t2_amt, 'earned', v_paid_date);
            end if;
          end if;
        end if;
      end if;

      if v_third_orig > 0 then
        v_portion := round(v_line_after * v_third_orig / v_tot_orig, 2);
        v_t1_amt := round(v_portion * 4.5 / 100.0, 2);
        if v_t1_amt > 0 then
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', 'third_party', v_portion, 4.5, v_t1_amt, 'earned', v_paid_date);
          if v_tier2 is not null then
            v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
            if v_t2_amt > 0 then
              insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
              values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', 'third_party', v_t1_amt, 5.0, v_t2_amt, 'earned', v_paid_date);
            end if;
          end if;
        end if;
      end if;

    else
      if v_item.line_kind = 'voucher' then v_ptype := 'own'; else v_ptype := v_item.ptype; end if;
      v_t1_rate := case when v_ptype = 'third_party' then 4.5 else 15 end;
      v_t1_amt := round(v_line_after * v_t1_rate / 100.0, 2);
      if v_t1_amt <= 0 then continue; end if;

      insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
      values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier1, 'tier1', v_ptype, v_line_after, v_t1_rate, v_t1_amt, 'earned', v_paid_date);

      if v_tier2 is not null then
        v_t2_amt := round(v_t1_amt * 5.0 / 100.0, 2);
        if v_t2_amt > 0 then
          insert into public.commissions (invoice_id, invoice_item_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount, rate, commission_amount, status, invoice_paid_date)
          values (p_invoice_id, v_item.id, v_inv.customer_id, v_tier2, 'tier2', v_ptype, v_t1_amt, 5.0, v_t2_amt, 'earned', v_paid_date);
        end if;
      end if;
    end if;
  end loop;

  perform public.write_audit('commissions', p_invoice_id, 'commission_calculated', null,
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'tier1', v_tier1, 'tier2', v_tier2));
end; $$;

notify pgrst, 'reload schema';
