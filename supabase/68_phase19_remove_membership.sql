-- =====================================================================
-- ENERGIA — PHASE 19: DESTRUCTIVE MEMBERSHIP REMOVAL
--
-- Removes Membership, Member ID and Member/Non-Member gating completely.
--   * Every Membership Invoice (including MIXED invoices and every
--     dependent invoice) is deleted and its whole effect graph reversed.
--   * Product and voucher stock are restored ONCE, netting anything that
--     was already returned by a refund, cancellation or exchange.
--   * Commissions are deleted; payout batches are recalculated, and any
--     commission already PAID becomes a generic correction entry.
--   * Membership tables, columns, functions, triggers, policies, indexes,
--     settings and audit history are dropped.
--   * Shared invoice functions are re-issued without Membership: the
--     former "member price" becomes the single normal selling price and
--     promotions are open to every customer.
--
-- ⚠ DESTRUCTIVE AND ONE-WAY. Take a full database backup and run
--   scripts/phase19_membership_removal_preview.sql first.
--   Money already collected and commission already paid CANNOT be undone
--   by a migration — see public.data_removal_reconciliation after the run.
--
-- Additive-safe to re-run: the reversal only executes while the
-- Membership tables still exist. Run AFTER 67.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Permanent record of what was removed (feeds the manual financial
--    reconciliation report). Deliberately NOT a Membership table.
-- ---------------------------------------------------------------------
create table if not exists public.data_removal_reconciliation (
  id           uuid primary key default gen_random_uuid(),
  run_at       timestamptz not null default now(),
  category     text not null,
  reference    text,
  party        text,
  customer_id  uuid,
  store_id     uuid,
  quantity     integer,
  amount       numeric(12,2),
  detail       jsonb,
  note         text
);
create index if not exists idx_drr_category on public.data_removal_reconciliation (category);
alter table public.data_removal_reconciliation enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='data_removal_reconciliation' and policyname='read data removal log') then
    create policy "read data removal log" on public.data_removal_reconciliation for select to authenticated using (true);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. THE REVERSAL. Runs only while the Membership tables still exist.
-- ---------------------------------------------------------------------
do $$
declare
  v_r record; v_n integer; v_amt numeric;
begin
  if to_regclass('public.customer_memberships') is null then
    raise notice 'Phase 19: Membership tables already removed — reversal skipped.';
    return;
  end if;

  -- 2a. Build the Membership Invoice graph.
  create temp table mm_inv (id uuid primary key) on commit drop;
  insert into mm_inv (id)
  with recursive
  seed as (
    select distinct i.id
      from public.invoices i
     where exists (select 1 from public.invoice_items ii
                    where ii.invoice_id = i.id and ii.line_kind = 'membership')
        or exists (select 1 from public.customer_memberships m where m.invoice_id = i.id)
  ),
  edges as (
    select i.topup_of_invoice_id as parent, i.id as child
      from public.invoices i where i.topup_of_invoice_id is not null
    union all
    select r.invoice_id, r.topup_invoice_id
      from public.invoice_refunds r where r.topup_invoice_id is not null
    union all
    select e.original_invoice_id, e.exchange_invoice_id
      from public.product_exchanges e where e.exchange_invoice_id is not null
  ),
  graph as (
    select id from seed
    union
    select e.child from edges e join graph g on e.parent = g.id
  )
  select distinct id from graph where id is not null;

  -- Lock every affected invoice for the whole reversal.
  perform 1 from public.invoices i join mm_inv m on m.id = i.id for update;

  select count(*) into v_n from mm_inv;
  raise notice 'Phase 19: % membership invoice(s) in scope', v_n;

  -- 2b. Log the invoices (and their payments) before anything is deleted.
  insert into public.data_removal_reconciliation (category, reference, party, customer_id, store_id, amount, detail, note)
  select 'invoice_deleted', i.invoice_no, c.full_name, i.customer_id, i.store_id, i.total_amount,
         jsonb_build_object('status', i.status, 'paid_amount', i.paid_amount,
                            'mixed', exists (select 1 from public.invoice_items x
                                              where x.invoice_id = i.id and x.line_kind <> 'membership')
                                     and exists (select 1 from public.invoice_items x
                                                  where x.invoice_id = i.id and x.line_kind = 'membership')),
         'Membership invoice deleted by Phase 19'
    from public.invoices i join mm_inv m on m.id = i.id
    left join public.customers c on c.id = i.customer_id;

  insert into public.data_removal_reconciliation (category, reference, party, customer_id, store_id, amount, note)
  select 'customer_payment_manual_reconciliation', i.invoice_no, c.full_name, i.customer_id, i.store_id,
         sum(p.amount), 'Money already collected from the customer — refund/settle manually'
    from public.invoice_payments p
    join public.invoices i on i.id = p.invoice_id
    join mm_inv m on m.id = i.id
    left join public.customers c on c.id = i.customer_id
   group by i.invoice_no, c.full_name, i.customer_id, i.store_id;

  -- 2c. PRODUCT STOCK — restore only what is still deducted.
  for v_r in
    select m.product_id,
           coalesce(m.from_store_id, m.to_store_id) as store_id,
           sum(case when m.movement_type in ('store_sale','exchange_replacement_out') then m.quantity
                    when m.movement_type in ('invoice_cancel_return','invoice_refund_return','exchange_return_in') then -m.quantity
                    else 0 end) as net_out
      from public.stock_movements m
      join mm_inv mi on mi.id = m.invoice_id
     where m.product_id is not null
     group by 1,2
    having sum(case when m.movement_type in ('store_sale','exchange_replacement_out') then m.quantity
                    when m.movement_type in ('invoice_cancel_return','invoice_refund_return','exchange_return_in') then -m.quantity
                    else 0 end) > 0
  loop
    if v_r.store_id is null then continue; end if;
    -- Lock the balance row, then restore exactly the net outstanding qty.
    perform 1 from public.store_inventory
      where store_id = v_r.store_id and product_id = v_r.product_id for update;
    insert into public.store_inventory (store_id, product_id, current_qty)
    values (v_r.store_id, v_r.product_id, v_r.net_out)
    on conflict (store_id, product_id) do update
      set current_qty = public.store_inventory.current_qty + excluded.current_qty;

    insert into public.data_removal_reconciliation (category, reference, store_id, quantity, note)
    values ('product_stock_restored',
            (select sku from public.products where id = v_r.product_id),
            v_r.store_id, v_r.net_out, 'Net quantity still deducted by deleted membership invoices');
  end loop;

  -- 2d. VOUCHER STOCK — restore what these invoices consumed, net of
  --     quantities already returned by a refund that returned stock.
  for v_r in
    with used as (
      select ii.voucher_id, i.store_id, sum(ii.quantity)::integer as qty
        from public.invoice_items ii
        join public.invoices i on i.id = ii.invoice_id
        join mm_inv m on m.id = i.id
       where ii.line_kind = 'voucher' and ii.voucher_id is not null
         and i.status in ('paid','partially_paid','completed_foc')
       group by 1,2
      union all
      select ps.voucher_id, i.store_id, sum(ps.quantity)::integer
        from public.invoice_promotion_selections ps
        join public.invoice_items ii on ii.id = ps.invoice_item_id
        join public.invoices i on i.id = ii.invoice_id
        join mm_inv m on m.id = i.id
       where ps.voucher_id is not null
         and i.status in ('paid','partially_paid','completed_foc')
       group by 1,2
    ),
    returned as (
      select ii.voucher_id, i.store_id, count(*)::integer as qty
        from public.invoice_refunds r
        join public.invoice_items ii on ii.id = r.invoice_item_id
        join public.invoices i on i.id = ii.invoice_id
        join mm_inv m on m.id = i.id
       where ii.line_kind = 'voucher' and ii.voucher_id is not null and coalesce(r.return_stock,false)
       group by 1,2
    )
    select u.voucher_id, u.store_id, sum(u.qty) - coalesce(max(rt.qty),0) as net_qty
      from used u left join returned rt on rt.voucher_id = u.voucher_id and rt.store_id = u.store_id
     group by u.voucher_id, u.store_id
    having sum(u.qty) - coalesce(max(rt.qty),0) > 0
  loop
    if v_r.store_id is null then continue; end if;
    perform 1 from public.voucher_store_stock
      where store_id = v_r.store_id and voucher_id = v_r.voucher_id for update;
    insert into public.voucher_store_stock (voucher_id, store_id, current_qty)
    values (v_r.voucher_id, v_r.store_id, v_r.net_qty)
    on conflict (voucher_id, store_id) do update
      set current_qty = public.voucher_store_stock.current_qty + excluded.current_qty;

    insert into public.data_removal_reconciliation (category, reference, store_id, quantity, note)
    values ('voucher_stock_restored',
            (select code from public.vouchers where id = v_r.voucher_id),
            v_r.store_id, v_r.net_qty, 'Voucher stock consumed by deleted membership invoices');
  end loop;

  -- Redeemed vouchers cannot be un-used: flag them for manual review.
  insert into public.data_removal_reconciliation (category, reference, party, customer_id, amount, note)
  select 'voucher_already_redeemed_manual_reconciliation', i.invoice_no, c.full_name, vr.customer_id,
         vr.discount_applied, 'Voucher from a deleted invoice had already been redeemed'
    from public.voucher_redemptions vr
    join public.invoices i on i.id = vr.invoice_id
    join mm_inv m on m.id = i.id
    left join public.customers c on c.id = vr.customer_id;

  -- 2e. THERAPY — record activated entitlements, then remove them all.
  insert into public.data_removal_reconciliation (category, reference, party, customer_id, note)
  select 'therapy_already_activated_manual_reconciliation', e.entitlement_no, c.full_name, e.customer_id,
         'Purchased therapy from a deleted invoice was already activated'
    from public.purchased_therapy_entitlements e
    join mm_inv m on m.id = e.invoice_id
    left join public.customers c on c.id = e.customer_id
   where e.status not in ('pending_activation','cancelled');

  -- 2f. COMMISSIONS — log paid-out amounts, unhook payouts, recalculate.
  create table if not exists public.commission_corrections (
    id uuid primary key default gen_random_uuid(),
    kind text not null check (kind in ('affiliate','staff')),
    customer_id uuid references public.customers(id),
    staff_id uuid references public.profiles(id),
    payout_id uuid,
    amount numeric(12,2) not null,
    reason text not null,
    status text not null default 'open' check (status in ('open','settled','waived')),
    created_at timestamptz not null default now(),
    created_by uuid references public.profiles(id)
  );

  insert into public.commission_corrections (kind, customer_id, payout_id, amount, reason)
  select 'affiliate', c.referrer_customer_id, c.payout_id, sum(c.commission_amount),
         'Historical data removal correction'
    from public.commissions c
    join mm_inv m on m.id = c.invoice_id
    join public.commission_payouts po on po.id = c.payout_id and po.status = 'paid'
   group by c.referrer_customer_id, c.payout_id;

  insert into public.commission_corrections (kind, staff_id, payout_id, amount, reason)
  select 'staff', sc.staff_id, sc.payout_id, sum(sc.commission_amount),
         'Historical data removal correction'
    from public.staff_commissions sc
    join mm_inv m on m.id = sc.invoice_id
    join public.staff_commission_payouts po on po.id = sc.payout_id and po.status = 'paid'
   group by sc.staff_id, sc.payout_id;

  insert into public.data_removal_reconciliation (category, reference, party, amount, note)
  select 'affiliate_commission_paid_manual_reconciliation', po.reference, c.full_name,
         sum(cm.commission_amount), 'Tier commission already paid out — correction entry created'
    from public.commissions cm
    join mm_inv m on m.id = cm.invoice_id
    join public.commission_payouts po on po.id = cm.payout_id and po.status = 'paid'
    left join public.customers c on c.id = cm.referrer_customer_id
   group by po.reference, c.full_name;

  insert into public.data_removal_reconciliation (category, reference, party, amount, note)
  select 'staff_commission_paid_manual_reconciliation', po.reference, pr.full_name,
         sum(sc.commission_amount), 'Staff commission already paid out — correction entry created'
    from public.staff_commissions sc
    join mm_inv m on m.id = sc.invoice_id
    join public.staff_commission_payouts po on po.id = sc.payout_id and po.status = 'paid'
    left join public.profiles pr on pr.id = sc.staff_id
   group by po.reference, pr.full_name;

  -- Remember which payout batches must be recalculated after deletion.
  create temp table mm_payout (id uuid primary key) on commit drop;
  insert into mm_payout (id)
    select distinct c.payout_id from public.commissions c
      join mm_inv m on m.id = c.invoice_id where c.payout_id is not null;
  create temp table mm_spayout (id uuid primary key) on commit drop;
  insert into mm_spayout (id)
    select distinct sc.payout_id from public.staff_commissions sc
      join mm_inv m on m.id = sc.invoice_id where sc.payout_id is not null;

  -- 2g. EXCHANGES tied to these invoices (their invoices are already in scope).
  create temp table mm_exch (id uuid primary key) on commit drop;
  insert into mm_exch (id)
    select distinct e.id from public.product_exchanges e
     where e.original_invoice_id in (select id from mm_inv)
        or e.exchange_invoice_id in (select id from mm_inv);
  -- Release the invoice -> exchange link before the exchanges are removed.
  update public.invoices set exchange_id = null where exchange_id in (select id from mm_exch);
  delete from public.product_exchange_payments where exchange_id in (select id from mm_exch);
  delete from public.product_exchange_items where exchange_id in (select id from mm_exch);
  insert into public.data_removal_reconciliation (category, reference, note)
    select 'exchange_reversed', e.exchange_no, 'Exchange belonged to a deleted membership invoice'
      from public.product_exchanges e join mm_exch x on x.id = e.id;
  delete from public.product_exchanges where id in (select id from mm_exch);

  -- 2h. Delete everything that hangs off the invoice ITEMS of these invoices.
  for v_r in
    select c.conrelid::regclass::text as tbl, a.attname as col
      from pg_constraint c
      join lateral unnest(c.conkey) k(attnum) on true
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
     where c.contype = 'f' and c.confrelid = 'public.invoice_items'::regclass
       and c.conrelid <> 'public.invoice_items'::regclass
  loop
    execute format(
      'delete from %s where %I in (select ii.id from public.invoice_items ii join mm_inv m on m.id = ii.invoice_id)',
      v_r.tbl, v_r.col);
  end loop;

  -- 2i. Delete everything that references the INVOICES themselves.
  for v_r in
    select c.conrelid::regclass::text as tbl, a.attname as col
      from pg_constraint c
      join lateral unnest(c.conkey) k(attnum) on true
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
     where c.contype = 'f' and c.confrelid = 'public.invoices'::regclass
       and c.conrelid <> 'public.invoices'::regclass
  loop
    execute format('delete from %s where %I in (select id from mm_inv)', v_r.tbl, v_r.col);
  end loop;

  -- 2j. Finally the invoice items and the invoices.
  delete from public.invoice_items where invoice_id in (select id from mm_inv);
  update public.invoices set topup_of_invoice_id = null
   where topup_of_invoice_id in (select id from mm_inv);
  delete from public.invoices where id in (select id from mm_inv);

  -- 2k. Recalculate the payout batches that lost allocations. Unrelated
  --     allocations in the same batch are untouched.
  update public.commission_payouts po
     set total_tier1  = coalesce((select sum(c.commission_amount) from public.commissions c
                                   where c.payout_id = po.id and c.tier = 'tier1'), 0),
         total_tier2  = coalesce((select sum(c.commission_amount) from public.commissions c
                                   where c.payout_id = po.id and c.tier = 'tier2'), 0),
         total_amount = coalesce((select sum(c.commission_amount) from public.commissions c
                                   where c.payout_id = po.id), 0)
   where po.id in (select id from mm_payout);

  update public.staff_commission_payouts po
     set total_amount = coalesce((select sum(sc.commission_amount) from public.staff_commissions sc
                                   where sc.payout_id = po.id), 0)
   where po.id in (select id from mm_spayout);

  -- 2l. Membership data itself.
  delete from public.member_id_reservations;
  delete from public.member_ids;
  delete from public.customer_memberships;
  delete from public.membership_plan_store_prices;
  delete from public.membership_plans;

  -- 2m. Affiliates that were inactive ONLY because of Membership are
  --     recorded here so Phase 20 can reactivate exactly those.
  insert into public.data_removal_reconciliation (category, reference, party, customer_id, note)
  select 'affiliate_inactive_due_to_membership', a.status, c.full_name, a.customer_id,
         'Affiliate was inactive only because of Membership — eligible for Phase 20 reactivation'
    from public.customer_affiliates a
    left join public.customers c on c.id = a.customer_id
   where a.deleted_at is null and not coalesce(a.manually_suspended,false)
     and a.status in ('inactive_membership_expired','inactive_missing_member_id','inactive_no_membership');

  -- 2n. Membership audit history.
  delete from public.audit_logs
   where table_name in ('customer_memberships','membership_plans','membership_plan_store_prices',
                        'member_ids','member_id_reservations')
      or module = 'membership'
      or action ilike '%membership%' or action ilike '%member_id%'
      or action ilike '%member_price%' or action ilike '%non_member%';

  -- 2o. Historical BLOCKED commissions stay blocked, with a neutral reason.
  update public.commissions
     set block_reason = 'Historical eligibility block'
   where status = 'blocked'
     and (block_reason is null or block_reason ilike '%member%');

  select count(*), coalesce(sum(amount),0) into v_n, v_amt
    from public.data_removal_reconciliation where category like '%manual_reconciliation%';
  raise notice 'Phase 19: reversal complete. % manual reconciliation item(s), total %', v_n, v_amt;
end $$;

-- ---------------------------------------------------------------------
-- 3. RE-ISSUE THE SHARED FUNCTIONS WITHOUT MEMBERSHIP.
--    The former Member Price is now the single normal selling price and
--    promotions are available to every customer.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_invoice(p_store_id uuid, p_customer_id uuid, p_affiliate_id uuid, p_items jsonb, p_discount_total numeric DEFAULT 0, p_notes text DEFAULT NULL::text, p_discount_voucher_id uuid DEFAULT NULL::uuid, p_service_staff jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_item jsonb; v_kind text; v_product_id uuid; v_voucher_id uuid; v_promo_id uuid;
  v_qty integer; v_price numeric; v_subtotal numeric := 0; v_line_total numeric;
  v_invoice_id uuid; v_invoice_no text; v_manual numeric := coalesce(p_discount_total,0);
  v_has_promo boolean := false; v_promo public.promotions%rowtype;
  v_line_voucher uuid; v_line_disc numeric; v_line_disc_sum numeric := 0;
  v_lv public.vouchers%rowtype; v_discount numeric;
  v_grp record; v_sel jsonb; v_opt jsonb; v_provided integer; v_required integer;
  v_item_id uuid; v_sel_group uuid; v_ok boolean; v_topup numeric;
  v_ptype text; v_third_sum numeric := 0; v_discountable numeric; v_wbase numeric;
  v_ss jsonb; v_ss_id uuid; v_ss_role user_role;
  v_is_member boolean := true;
  v_mode_ovr text; v_ovr_reason text; v_pj jsonb; v_use_member boolean; v_mode text;
  v_therapy_pkg uuid; v_therapy_name text; v_therapy_months integer;
  -- FOC additions
  v_foc_qty integer; v_foc_amt numeric; v_gross numeric;
  v_foc_rid uuid; v_foc_rtext text; v_foc_resolved text; v_foc_total numeric := 0;
begin
  if public.current_user_role() is null then raise exception 'No profile for current user'; end if;
  if not public.user_has_store_access(p_store_id) then raise exception 'You do not have access to this store'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'At least one item is required'; end if;
  if p_customer_id is null then raise exception 'A customer is required'; end if;
  if public.current_user_role() = 'inventory_manager'
     and exists (select 1 from jsonb_array_elements(p_items) x
                  where coalesce((x->>'foc_quantity')::integer,0) > 0 or coalesce((x->>'is_foc')::boolean,false)) then
    raise exception 'Inventory Manager cannot apply FOC';
  end if;

  -- Phase 19: Membership has been removed. Every customer receives the single
  -- normal selling price, and promotions are open to all customers.
  if exists (select 1 from jsonb_array_elements(p_items) x
              where coalesce(x->>'kind','product') = 'membership') then
    raise exception 'Membership is no longer sold';
  end if;
  v_is_member := true;

  -- PASS 1: validate + price + accumulate CHARGED value.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantity must be greater than zero'; end if;
    v_mode_ovr := null; v_ovr_reason := null;   -- Phase 19: no Member/Non-Member modes
    v_use_member := true;

    -- FOC parsing + mandatory reason.
    v_foc_qty := coalesce((v_item->>'foc_quantity')::integer, 0);
    if coalesce((v_item->>'is_foc')::boolean,false) then v_foc_qty := v_qty; end if;
    if v_foc_qty < 0 then raise exception 'FOC quantity cannot be negative'; end if;
    if v_foc_qty > v_qty then
      raise exception 'FOC quantity (%) cannot exceed the line quantity (%)', v_foc_qty, v_qty; end if;
    if v_foc_qty > 0 then
      v_foc_rid := nullif(v_item->>'foc_reason_id','')::uuid;
      v_foc_rtext := nullif(trim(coalesce(v_item->>'foc_reason','')),'');
      perform public.foc_reason_resolve(v_foc_rid, v_foc_rtext);
    end if;

    if v_kind = 'promotion' then
      v_has_promo := true;
      v_promo_id := (v_item->>'promotion_id')::uuid;
      select * into v_promo from public.promotions where id = v_promo_id and deleted_at is null;
      if not found then raise exception 'Promotion not found'; end if;
      if not v_promo.is_active then raise exception 'Promotion "%" is not active', v_promo.name; end if;
      if v_promo.start_date is not null and now()::date < v_promo.start_date then raise exception 'Promotion "%" has not started yet', v_promo.name; end if;
      if v_promo.end_date is not null and now()::date > v_promo.end_date then raise exception 'Promotion "%" has ended', v_promo.name; end if;

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
              if v_grp.item_kind = 'voucher' then
                select exists (
                  select 1 from public.promotion_choice_options o
                  where o.group_id = v_grp.id
                    and (v_opt->>'voucher_id') is not null and o.voucher_id = (v_opt->>'voucher_id')::uuid
                ) into v_ok;
                if not v_ok then raise exception 'A selected voucher does not belong to choice group "%"', v_grp.label; end if;
              else
                if (v_opt->>'product_id') is null then raise exception 'Choice group "%" expects product selections', v_grp.label; end if;
                select exists (
                  select 1 from public.store_product_prices
                  where store_id = p_store_id and product_id = (v_opt->>'product_id')::uuid
                    and is_active = true and deleted_at is null
                ) into v_ok;
                if not v_ok then
                  raise exception 'Product "%" has no price at this store, so it cannot be chosen in "%"',
                    (select name from public.products where id = (v_opt->>'product_id')::uuid), v_grp.label;
                end if;
              end if;
              v_provided := v_provided + (v_opt->>'quantity')::integer;
            end loop;
          end if;
        end loop;
        if v_provided <> v_required then
          raise exception 'Choice group "%" requires % selection(s), got %', v_grp.label, v_required, v_provided;
        end if;
      end loop;

      v_pj := public.promotion_price_for(p_store_id, v_promo_id, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Promotion "%" is missing its % price at this store', v_promo.name,
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_topup := public.promotion_selections_topup(v_promo_id, p_store_id, v_item->'selections', v_use_member);
      v_gross := ((v_pj->>'price')::numeric * v_qty) + v_topup;

    elsif v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      perform 1 from public.vouchers where id = v_voucher_id and is_active = true and deleted_at is null;
      if not found then raise exception 'Voucher not found or inactive'; end if;
      v_pj := public.voucher_price_for(p_store_id, v_voucher_id, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Voucher "%" is missing its % price at this store',
          (select name from public.vouchers where id = v_voucher_id),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_gross := (v_pj->>'price')::numeric * v_qty;

    elsif v_kind = 'therapy' then
      if v_qty <> 1 then raise exception 'A therapy line must have quantity 1'; end if;
      v_therapy_pkg := (v_item->>'therapy_package_id')::uuid;
      perform 1 from public.unlimited_therapy_packages where id = v_therapy_pkg and is_active = true and deleted_at is null;
      if not found then raise exception 'Therapy package not found or inactive'; end if;
      if exists (select 1 from public.purchased_therapy_entitlements
                  where customer_id = p_customer_id and package_id = v_therapy_pkg
                    and status in ('active','scheduled','pending_activation')) then
        raise exception 'This customer already has a current entitlement for this therapy package'; end if;
      v_pj := public.therapy_price_for(p_store_id, v_therapy_pkg, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Therapy package "%" is missing its % price at this store',
          (select name from public.unlimited_therapy_packages where id = v_therapy_pkg),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_gross := (v_pj->>'price')::numeric * v_qty;

    else
      v_product_id := (v_item->>'product_id')::uuid;
      select p.product_type::text into v_ptype from public.products p where p.id = v_product_id;
      v_pj := public.product_price_for(p_store_id, v_product_id, v_use_member);
      if not coalesce((v_pj->>'found')::boolean,false) then
        raise exception 'No price set for "%" in this store',
          (select name from public.products where id = v_product_id); end if;
      if v_mode_ovr is null and not coalesce((v_pj->>'eligible')::boolean,false) then
        raise exception 'Product "%" is % — not sellable to this customer without a manual override',
          (select name from public.products where id = v_product_id),
          replace(v_pj->>'eligibility','_',' '); end if;
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Product "%" is missing its % price at this store',
          (select name from public.products where id = v_product_id),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_price := (v_pj->>'price')::numeric;
      v_gross := v_price * v_qty;
    end if;

    -- FOC split (uniform across every line kind).
    v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
    v_line_total := round(v_gross - v_foc_amt, 2);
    v_subtotal := v_subtotal + v_line_total;
    v_foc_total := v_foc_total + v_foc_amt;

    -- Third-party + per-line voucher rules operate on the CHARGED value.
    if v_kind not in ('promotion','voucher','therapy') then
      if v_ptype = 'third_party' then v_third_sum := v_third_sum + v_line_total; end if;
      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      if v_line_voucher is not null then
        if v_ptype = 'third_party' then
          raise exception 'Discounts cannot be applied to third-party products ("%")',
            (select name from public.products where id = v_product_id);
        end if;
        select * into v_lv from public.vouchers where id = v_line_voucher and deleted_at is null;
        if not found then raise exception 'Line voucher not found'; end if;
        if v_lv.voucher_kind = 'normal' then raise exception 'Voucher "%" is not a discount voucher', v_lv.name; end if;
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
        v_line_disc_sum := v_line_disc_sum + v_line_disc;
      end if;
    end if;
  end loop;

  if p_discount_voucher_id is not null and v_has_promo then
    raise exception 'A whole-invoice discount voucher cannot be used when the invoice contains a promotion/bundle. Use per-product vouchers instead.';
  end if;

  -- Discounts apply to the paid value only (v_subtotal is already net of FOC).
  v_discountable := v_subtotal - v_third_sum;
  v_discount := v_manual + v_line_disc_sum;
  if p_discount_voucher_id is not null then
    v_wbase := v_discountable - v_manual - v_line_disc_sum;
    if v_wbase < 0 then v_wbase := 0; end if;
    v_discount := v_discount + public.voucher_discount_amount(p_discount_voucher_id, v_wbase);
  end if;
  if v_discount > v_discountable then v_discount := v_discountable; end if;
  if v_discount < 0 then v_discount := 0; end if;

  v_invoice_no := public.next_invoice_no();
  insert into public.invoices
    (invoice_no, store_id, customer_id, affiliate_id, created_by, status,
     subtotal, discount_total, manual_discount, total_amount, paid_amount, notes, discount_voucher_id,
     foc_total, has_foc, is_full_foc)
  values (v_invoice_no, p_store_id, p_customer_id, p_affiliate_id, auth.uid(), 'unpaid',
          v_subtotal, v_discount, v_manual, v_subtotal - v_discount, 0, p_notes, p_discount_voucher_id,
          v_foc_total, v_foc_total > 0, (v_foc_total > 0 and v_subtotal <= 0))
  returning id into v_invoice_id;

  for v_ss in select * from jsonb_array_elements(coalesce(p_service_staff, '[]'::jsonb))
  loop
    v_ss_id := (v_ss#>>'{}')::uuid;
    if v_ss_id is null then continue; end if;
    select role into v_ss_role from public.profiles where id = v_ss_id and is_active = true and deleted_at is null;
    if v_ss_role is null then raise exception 'A selected service staff was not found or is inactive'; end if;
    if v_ss_role not in ('owner','manager','staff') then
      raise exception 'Service staff must be Owner, Manager, or Staff (got %)', v_ss_role;
    end if;
    insert into public.invoice_service_staff (invoice_id, staff_id)
    values (v_invoice_id, v_ss_id) on conflict (invoice_id, staff_id) do nothing;
  end loop;

  -- PASS 2: insert lines with permanent snapshots (incl. FOC snapshots).
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    v_mode_ovr := nullif(v_item->>'price_mode_override','');
    v_ovr_reason := nullif(trim(coalesce(v_item->>'override_reason','')),'');
    v_use_member := coalesce(v_mode_ovr = 'member', v_is_member);
    v_mode := case when v_use_member then 'member' else 'non_member' end;

    v_foc_qty := coalesce((v_item->>'foc_quantity')::integer, 0);
    if coalesce((v_item->>'is_foc')::boolean,false) then v_foc_qty := v_qty; end if;
    v_foc_rid := nullif(v_item->>'foc_reason_id','')::uuid;
    v_foc_rtext := nullif(trim(coalesce(v_item->>'foc_reason','')),'');
    v_foc_resolved := case when v_foc_qty > 0 then public.foc_reason_resolve(v_foc_rid, v_foc_rtext) else null end;

    if v_kind = 'promotion' then
      v_promo_id := (v_item->>'promotion_id')::uuid;
      v_pj := public.promotion_price_for(p_store_id, v_promo_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_topup := public.promotion_selections_topup(v_promo_id, p_store_id, v_item->'selections', v_use_member);
      v_gross := (v_price * v_qty) + v_topup;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      insert into public.invoice_items
        (invoice_id, line_kind, promotion_id, product_id, quantity, unit_price, line_total, topup_amount,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         price_overridden, override_reason, override_by, override_at,
         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (v_invoice_id, 'promotion', v_promo_id, null, v_qty, v_price, v_line_total, v_topup,
              v_mode, case when v_mode_ovr is null then 'promotion' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, p_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end)
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
      v_pj := public.voucher_price_for(p_store_id, v_voucher_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_gross := v_price * v_qty;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      insert into public.invoice_items
        (invoice_id, line_kind, voucher_id, product_id, quantity, unit_price, line_total,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         price_overridden, override_reason, override_by, override_at,
         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (v_invoice_id, 'voucher', v_voucher_id, null, v_qty, v_price, v_line_total,
              v_mode, case when v_mode_ovr is null then 'voucher' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, p_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);

    elsif v_kind = 'therapy' then
      v_therapy_pkg := (v_item->>'therapy_package_id')::uuid;
      v_pj := public.therapy_price_for(p_store_id, v_therapy_pkg, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_gross := v_price;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      select name, duration_months into v_therapy_name, v_therapy_months
        from public.unlimited_therapy_packages where id = v_therapy_pkg;
      insert into public.invoice_items
        (invoice_id, line_kind, product_id, therapy_package_id, quantity, unit_price, line_total,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         plan_name_snapshot, plan_months_snapshot,
         price_overridden, override_reason, override_by, override_at,
         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (v_invoice_id, 'therapy', null, v_therapy_pkg, 1, v_price, v_line_total,
              v_mode, case when v_mode_ovr is null then 'therapy' else 'manual_override' end,
              v_therapy_pkg, p_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_therapy_name, v_therapy_months,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);
    else
      v_product_id := (v_item->>'product_id')::uuid;
      v_pj := public.product_price_for(p_store_id, v_product_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_gross := v_price * v_qty;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      v_line_disc := 0;
      if v_line_voucher is not null then
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
      end if;
      insert into public.invoice_items
        (invoice_id, line_kind, product_id, quantity, unit_price, line_total, line_voucher_id, line_discount,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         price_overridden, override_reason, override_by, override_at,
         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (v_invoice_id, 'product', v_product_id, v_qty, v_price, v_line_total, v_line_voucher, v_line_disc,
              v_mode, case when v_mode_ovr is null then 'product' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, p_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);
    end if;
  end loop;

  perform public.write_audit('invoices', v_invoice_id, 'invoice_created', null,
    jsonb_build_object('invoice_no', v_invoice_no, 'total', v_subtotal - v_discount,
                       'has_promotion', v_has_promo, 'third_party_total', v_third_sum,
                       'foc_total', v_foc_total, 'is_full_foc', (v_foc_total > 0 and v_subtotal <= 0)));
  if v_foc_total > 0 then
    perform public.write_audit_ex('invoices', v_invoice_id, 'invoice_foc_created', null,
      jsonb_build_object('invoice_no', v_invoice_no, 'foc_total', v_foc_total,
                         'charged_total', v_subtotal - v_discount),
      'foc', null, p_store_id);
  end if;
  return v_invoice_id;
end; $function$;


CREATE OR REPLACE FUNCTION public.update_invoice(p_invoice_id uuid, p_customer_id uuid, p_affiliate_id uuid, p_items jsonb, p_discount_total numeric DEFAULT 0, p_notes text DEFAULT NULL::text, p_discount_voucher_id uuid DEFAULT NULL::uuid, p_service_staff jsonb DEFAULT '[]'::jsonb, p_edit_reason text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_item jsonb; v_kind text; v_product_id uuid; v_voucher_id uuid; v_promo_id uuid;
  v_qty integer; v_price numeric; v_subtotal numeric := 0; v_line_total numeric;
  v_invoice_id uuid; v_invoice_no text; v_manual numeric := coalesce(p_discount_total,0);
  v_has_promo boolean := false; v_promo public.promotions%rowtype;
  v_line_voucher uuid; v_line_disc numeric; v_line_disc_sum numeric := 0;
  v_lv public.vouchers%rowtype; v_discount numeric;
  v_grp record; v_sel jsonb; v_opt jsonb; v_provided integer; v_required integer;
  v_item_id uuid; v_sel_group uuid; v_ok boolean; v_topup numeric;
  v_ptype text; v_third_sum numeric := 0; v_discountable numeric; v_wbase numeric;
  v_ss jsonb; v_ss_id uuid; v_ss_role user_role;
  v_is_member boolean := true;
  v_mode_ovr text; v_ovr_reason text; v_pj jsonb; v_use_member boolean; v_mode text;
  v_therapy_pkg uuid; v_therapy_name text; v_therapy_months integer;
  -- Phase 13 edit context
  v_store_id uuid; v_old public.invoices%rowtype; v_rev integer; v_snapshot jsonb;
  -- FOC additions
  v_foc_qty integer; v_foc_amt numeric; v_gross numeric;
  v_foc_rid uuid; v_foc_rtext text; v_foc_resolved text; v_foc_total numeric := 0;
begin
  -- ============ PHASE 13 EDIT GUARDS ============
  select * into v_old from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if v_old.deleted_at is not null then raise exception 'Invoice has been deleted'; end if;
  if coalesce(v_old.is_topup,false) then raise exception 'A refund top-up invoice is system-generated and cannot be edited'; end if;
  if coalesce(v_old.is_exchange,false) then raise exception 'An exchange invoice is system-generated and cannot be edited'; end if;
  if v_old.status not in ('draft','unpaid') then
    raise exception 'Only Draft or Unpaid invoices can be edited (this one is %)', v_old.status; end if;
  if coalesce(v_old.paid_amount,0) > 0 then
    raise exception 'This invoice has payments recorded (S$%.2f) and is locked for editing', v_old.paid_amount; end if;
  if exists (select 1 from public.invoice_payments where invoice_id = p_invoice_id) then
    raise exception 'This invoice has payment records and is locked for editing'; end if;
  if v_old.locked_at is not null then raise exception 'Invoice is locked'; end if;
  v_store_id := v_old.store_id;             -- store is NOT editable
  v_invoice_no := v_old.invoice_no;         -- invoice number is NOT editable

  -- Revision snapshot (rolled back automatically if any validation fails).
  select coalesce(max(revision_no),0) + 1 into v_rev from public.invoice_revisions where invoice_id = p_invoice_id;
  v_snapshot := jsonb_build_object(
    'invoice', to_jsonb(v_old),
    'items', (select coalesce(jsonb_agg(to_jsonb(ii) order by ii.id), '[]'::jsonb)
                from public.invoice_items ii where ii.invoice_id = p_invoice_id),
    'selections', (select coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
                     from public.invoice_promotion_selections s
                     join public.invoice_items ii on ii.id = s.invoice_item_id
                    where ii.invoice_id = p_invoice_id),
    'service_staff', (select coalesce(jsonb_agg(staff_id), '[]'::jsonb)
                        from public.invoice_service_staff where invoice_id = p_invoice_id));
  insert into public.invoice_revisions (invoice_id, revision_no, snapshot, edited_by, edit_reason)
  values (p_invoice_id, v_rev, v_snapshot, auth.uid(), p_edit_reason);

  -- (Phase 19: no reservations to release.)
  -- ============ END EDIT GUARDS ============

  if public.current_user_role() is null then raise exception 'No profile for current user'; end if;
  if not public.user_has_store_access(v_store_id) then raise exception 'You do not have access to this store'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'At least one item is required'; end if;
  if p_customer_id is null then raise exception 'A customer is required'; end if;
  if public.current_user_role() = 'inventory_manager'
     and exists (select 1 from jsonb_array_elements(p_items) x
                  where coalesce((x->>'foc_quantity')::integer,0) > 0 or coalesce((x->>'is_foc')::boolean,false)) then
    raise exception 'Inventory Manager cannot apply FOC';
  end if;

  -- Phase 19: Membership has been removed. Every customer receives the single
  -- normal selling price, and promotions are open to all customers.
  if exists (select 1 from jsonb_array_elements(p_items) x
              where coalesce(x->>'kind','product') = 'membership') then
    raise exception 'Membership is no longer sold';
  end if;
  v_is_member := true;

  -- PASS 1: validate + price + accumulate CHARGED value.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Quantity must be greater than zero'; end if;
    v_mode_ovr := null; v_ovr_reason := null;   -- Phase 19: no Member/Non-Member modes
    v_use_member := true;

    -- FOC parsing + mandatory reason.
    v_foc_qty := coalesce((v_item->>'foc_quantity')::integer, 0);
    if coalesce((v_item->>'is_foc')::boolean,false) then v_foc_qty := v_qty; end if;
    if v_foc_qty < 0 then raise exception 'FOC quantity cannot be negative'; end if;
    if v_foc_qty > v_qty then
      raise exception 'FOC quantity (%) cannot exceed the line quantity (%)', v_foc_qty, v_qty; end if;
    if v_foc_qty > 0 then
      v_foc_rid := nullif(v_item->>'foc_reason_id','')::uuid;
      v_foc_rtext := nullif(trim(coalesce(v_item->>'foc_reason','')),'');
      perform public.foc_reason_resolve(v_foc_rid, v_foc_rtext);
    end if;

    if v_kind = 'promotion' then
      v_has_promo := true;
      v_promo_id := (v_item->>'promotion_id')::uuid;
      select * into v_promo from public.promotions where id = v_promo_id and deleted_at is null;
      if not found then raise exception 'Promotion not found'; end if;
      if not v_promo.is_active then raise exception 'Promotion "%" is not active', v_promo.name; end if;
      if v_promo.start_date is not null and now()::date < v_promo.start_date then raise exception 'Promotion "%" has not started yet', v_promo.name; end if;
      if v_promo.end_date is not null and now()::date > v_promo.end_date then raise exception 'Promotion "%" has ended', v_promo.name; end if;

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
              if v_grp.item_kind = 'voucher' then
                select exists (
                  select 1 from public.promotion_choice_options o
                  where o.group_id = v_grp.id
                    and (v_opt->>'voucher_id') is not null and o.voucher_id = (v_opt->>'voucher_id')::uuid
                ) into v_ok;
                if not v_ok then raise exception 'A selected voucher does not belong to choice group "%"', v_grp.label; end if;
              else
                if (v_opt->>'product_id') is null then raise exception 'Choice group "%" expects product selections', v_grp.label; end if;
                select exists (
                  select 1 from public.store_product_prices
                  where store_id = v_store_id and product_id = (v_opt->>'product_id')::uuid
                    and is_active = true and deleted_at is null
                ) into v_ok;
                if not v_ok then
                  raise exception 'Product "%" has no price at this store, so it cannot be chosen in "%"',
                    (select name from public.products where id = (v_opt->>'product_id')::uuid), v_grp.label;
                end if;
              end if;
              v_provided := v_provided + (v_opt->>'quantity')::integer;
            end loop;
          end if;
        end loop;
        if v_provided <> v_required then
          raise exception 'Choice group "%" requires % selection(s), got %', v_grp.label, v_required, v_provided;
        end if;
      end loop;

      v_pj := public.promotion_price_for(v_store_id, v_promo_id, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Promotion "%" is missing its % price at this store', v_promo.name,
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_topup := public.promotion_selections_topup(v_promo_id, v_store_id, v_item->'selections', v_use_member);
      v_gross := ((v_pj->>'price')::numeric * v_qty) + v_topup;

    elsif v_kind = 'voucher' then
      v_voucher_id := (v_item->>'voucher_id')::uuid;
      perform 1 from public.vouchers where id = v_voucher_id and is_active = true and deleted_at is null;
      if not found then raise exception 'Voucher not found or inactive'; end if;
      v_pj := public.voucher_price_for(v_store_id, v_voucher_id, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Voucher "%" is missing its % price at this store',
          (select name from public.vouchers where id = v_voucher_id),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_gross := (v_pj->>'price')::numeric * v_qty;

    elsif v_kind = 'therapy' then
      if v_qty <> 1 then raise exception 'A therapy line must have quantity 1'; end if;
      v_therapy_pkg := (v_item->>'therapy_package_id')::uuid;
      perform 1 from public.unlimited_therapy_packages where id = v_therapy_pkg and is_active = true and deleted_at is null;
      if not found then raise exception 'Therapy package not found or inactive'; end if;
      if exists (select 1 from public.purchased_therapy_entitlements
                  where customer_id = p_customer_id and package_id = v_therapy_pkg
                    and status in ('active','scheduled','pending_activation')) then
        raise exception 'This customer already has a current entitlement for this therapy package'; end if;
      v_pj := public.therapy_price_for(v_store_id, v_therapy_pkg, v_use_member);
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Therapy package "%" is missing its % price at this store',
          (select name from public.unlimited_therapy_packages where id = v_therapy_pkg),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_gross := (v_pj->>'price')::numeric * v_qty;

    else
      v_product_id := (v_item->>'product_id')::uuid;
      select p.product_type::text into v_ptype from public.products p where p.id = v_product_id;
      v_pj := public.product_price_for(v_store_id, v_product_id, v_use_member);
      if not coalesce((v_pj->>'found')::boolean,false) then
        raise exception 'No price set for "%" in this store',
          (select name from public.products where id = v_product_id); end if;
      if v_mode_ovr is null and not coalesce((v_pj->>'eligible')::boolean,false) then
        raise exception 'Product "%" is % — not sellable to this customer without a manual override',
          (select name from public.products where id = v_product_id),
          replace(v_pj->>'eligibility','_',' '); end if;
      if not coalesce((v_pj->>'has_price')::boolean,false) then
        raise exception 'Product "%" is missing its % price at this store',
          (select name from public.products where id = v_product_id),
          case when v_use_member then 'Member' else 'Non-Member' end; end if;
      v_price := (v_pj->>'price')::numeric;
      v_gross := v_price * v_qty;
    end if;

    -- FOC split (uniform across every line kind).
    v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
    v_line_total := round(v_gross - v_foc_amt, 2);
    v_subtotal := v_subtotal + v_line_total;
    v_foc_total := v_foc_total + v_foc_amt;

    -- Third-party + per-line voucher rules operate on the CHARGED value.
    if v_kind not in ('promotion','voucher','therapy') then
      if v_ptype = 'third_party' then v_third_sum := v_third_sum + v_line_total; end if;
      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      if v_line_voucher is not null then
        if v_ptype = 'third_party' then
          raise exception 'Discounts cannot be applied to third-party products ("%")',
            (select name from public.products where id = v_product_id);
        end if;
        select * into v_lv from public.vouchers where id = v_line_voucher and deleted_at is null;
        if not found then raise exception 'Line voucher not found'; end if;
        if v_lv.voucher_kind = 'normal' then raise exception 'Voucher "%" is not a discount voucher', v_lv.name; end if;
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
        v_line_disc_sum := v_line_disc_sum + v_line_disc;
      end if;
    end if;
  end loop;

  if p_discount_voucher_id is not null and v_has_promo then
    raise exception 'A whole-invoice discount voucher cannot be used when the invoice contains a promotion/bundle. Use per-product vouchers instead.';
  end if;

  -- Discounts apply to the paid value only (v_subtotal is already net of FOC).
  v_discountable := v_subtotal - v_third_sum;
  v_discount := v_manual + v_line_disc_sum;
  if p_discount_voucher_id is not null then
    v_wbase := v_discountable - v_manual - v_line_disc_sum;
    if v_wbase < 0 then v_wbase := 0; end if;
    v_discount := v_discount + public.voucher_discount_amount(p_discount_voucher_id, v_wbase);
  end if;
  if v_discount > v_discountable then v_discount := v_discountable; end if;
  if v_discount < 0 then v_discount := 0; end if;

  -- All validation passed — now replace the invoice's contents in place.
  -- (Store, invoice number, creation date and creator are untouched.)
  delete from public.invoice_promotion_selections s
   using public.invoice_items ii
   where s.invoice_item_id = ii.id and ii.invoice_id = p_invoice_id;
  delete from public.invoice_items where invoice_id = p_invoice_id;
  delete from public.invoice_service_staff where invoice_id = p_invoice_id;

  update public.invoices
     set customer_id = p_customer_id,
         affiliate_id = p_affiliate_id,
         notes = p_notes,
         discount_voucher_id = p_discount_voucher_id,
         subtotal = v_subtotal,
         manual_discount = v_manual,
         discount_total = v_discount,
         total_amount = v_subtotal - v_discount,
         foc_total = v_foc_total,
         has_foc = v_foc_total > 0,
         is_full_foc = (v_foc_total > 0 and v_subtotal <= 0)
   where id = p_invoice_id;
  v_invoice_id := p_invoice_id;

  for v_ss in select * from jsonb_array_elements(coalesce(p_service_staff, '[]'::jsonb))
  loop
    v_ss_id := (v_ss#>>'{}')::uuid;
    if v_ss_id is null then continue; end if;
    select role into v_ss_role from public.profiles where id = v_ss_id and is_active = true and deleted_at is null;
    if v_ss_role is null then raise exception 'A selected service staff was not found or is inactive'; end if;
    if v_ss_role not in ('owner','manager','staff') then
      raise exception 'Service staff must be Owner, Manager, or Staff (got %)', v_ss_role;
    end if;
    insert into public.invoice_service_staff (invoice_id, staff_id)
    values (v_invoice_id, v_ss_id) on conflict (invoice_id, staff_id) do nothing;
  end loop;

  -- PASS 2: insert lines with permanent snapshots (incl. FOC snapshots).
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_kind := coalesce(v_item->>'kind','product');
    v_qty := (v_item->>'quantity')::integer;
    v_mode_ovr := nullif(v_item->>'price_mode_override','');
    v_ovr_reason := nullif(trim(coalesce(v_item->>'override_reason','')),'');
    v_use_member := coalesce(v_mode_ovr = 'member', v_is_member);
    v_mode := case when v_use_member then 'member' else 'non_member' end;

    v_foc_qty := coalesce((v_item->>'foc_quantity')::integer, 0);
    if coalesce((v_item->>'is_foc')::boolean,false) then v_foc_qty := v_qty; end if;
    v_foc_rid := nullif(v_item->>'foc_reason_id','')::uuid;
    v_foc_rtext := nullif(trim(coalesce(v_item->>'foc_reason','')),'');
    v_foc_resolved := case when v_foc_qty > 0 then public.foc_reason_resolve(v_foc_rid, v_foc_rtext) else null end;

    if v_kind = 'promotion' then
      v_promo_id := (v_item->>'promotion_id')::uuid;
      v_pj := public.promotion_price_for(v_store_id, v_promo_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_topup := public.promotion_selections_topup(v_promo_id, v_store_id, v_item->'selections', v_use_member);
      v_gross := (v_price * v_qty) + v_topup;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      insert into public.invoice_items
        (invoice_id, line_kind, promotion_id, product_id, quantity, unit_price, line_total, topup_amount,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         price_overridden, override_reason, override_by, override_at,
         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (v_invoice_id, 'promotion', v_promo_id, null, v_qty, v_price, v_line_total, v_topup,
              v_mode, case when v_mode_ovr is null then 'promotion' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, v_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end)
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
      v_pj := public.voucher_price_for(v_store_id, v_voucher_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_gross := v_price * v_qty;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      insert into public.invoice_items
        (invoice_id, line_kind, voucher_id, product_id, quantity, unit_price, line_total,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         price_overridden, override_reason, override_by, override_at,
         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (v_invoice_id, 'voucher', v_voucher_id, null, v_qty, v_price, v_line_total,
              v_mode, case when v_mode_ovr is null then 'voucher' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, v_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);

    elsif v_kind = 'therapy' then
      v_therapy_pkg := (v_item->>'therapy_package_id')::uuid;
      v_pj := public.therapy_price_for(v_store_id, v_therapy_pkg, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_gross := v_price;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      select name, duration_months into v_therapy_name, v_therapy_months
        from public.unlimited_therapy_packages where id = v_therapy_pkg;
      insert into public.invoice_items
        (invoice_id, line_kind, product_id, therapy_package_id, quantity, unit_price, line_total,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         plan_name_snapshot, plan_months_snapshot,
         price_overridden, override_reason, override_by, override_at,
         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (v_invoice_id, 'therapy', null, v_therapy_pkg, 1, v_price, v_line_total,
              v_mode, case when v_mode_ovr is null then 'therapy' else 'manual_override' end,
              v_therapy_pkg, v_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_therapy_name, v_therapy_months,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);
    else
      v_product_id := (v_item->>'product_id')::uuid;
      v_pj := public.product_price_for(v_store_id, v_product_id, v_use_member);
      v_price := (v_pj->>'price')::numeric;
      v_gross := v_price * v_qty;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      v_line_voucher := nullif(v_item->>'line_voucher_id','')::uuid;
      v_line_disc := 0;
      if v_line_voucher is not null then
        v_line_disc := public.voucher_discount_amount(v_line_voucher, v_line_total);
      end if;
      insert into public.invoice_items
        (invoice_id, line_kind, product_id, quantity, unit_price, line_total, line_voucher_id, line_discount,
         price_mode, price_source, price_source_id, store_id_snapshot,
         member_price_snapshot, non_member_price_snapshot, original_price,
         price_overridden, override_reason, override_by, override_at,
         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (v_invoice_id, 'product', v_product_id, v_qty, v_price, v_line_total, v_line_voucher, v_line_disc,
              v_mode, case when v_mode_ovr is null then 'product' else 'manual_override' end,
              (v_pj->>'source_id')::uuid, v_store_id,
              (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric, v_price,
              v_mode_ovr is not null, v_ovr_reason,
              case when v_mode_ovr is not null then auth.uid() end,
              case when v_mode_ovr is not null then now() end,
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end);
    end if;
  end loop;

  -- Save Earth (columns preserved on the header) re-enters through the
  -- canonical discount refresh, capped at the charged subtotal.
  perform public.refresh_invoice_discount_total(v_invoice_id);
  update public.invoices set discount_total = least(coalesce(discount_total,0), subtotal) where id = v_invoice_id;
  update public.invoices i set total_amount = greatest(0, i.subtotal - coalesce(i.discount_total,0)) where i.id = v_invoice_id;

  perform public.write_audit_ex('invoices', v_invoice_id, 'invoice_edited',
    jsonb_build_object('subtotal', v_old.subtotal, 'discount_total', v_old.discount_total,
                       'total_amount', v_old.total_amount, 'customer_id', v_old.customer_id,
                       'affiliate_id', v_old.affiliate_id),
    jsonb_build_object('invoice_no', v_invoice_no, 'revision_no', v_rev,
                       'subtotal', v_subtotal, 'discount_total', v_discount,
                       'total', v_subtotal - v_discount,
                       'has_promotion', v_has_promo,
                       'foc_total', v_foc_total),
    'invoice_edit', p_edit_reason, v_store_id);
  if v_foc_total > 0 then
    perform public.write_audit_ex('invoices', v_invoice_id, 'invoice_foc_created', null,
      jsonb_build_object('invoice_no', v_invoice_no, 'foc_total', v_foc_total,
                         'charged_total', v_subtotal - v_discount),
      'foc', null, v_store_id);
  end if;
  return v_invoice_id;
end; $function$;


CREATE OR REPLACE FUNCTION public.pay_invoice(p_invoice_id uuid, p_payments jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_inv public.invoices%rowtype; v_pay jsonb; v_method uuid; v_amount numeric;
  v_total_paying numeric := 0; v_already_paid numeric; v_new_paid numeric;
  v_req record; v_available integer; v_li record;
  v_is_member boolean := true; v_will_be_full boolean;
  v_old_total numeric; v_changes jsonb;
begin
  -- 1. Lock invoice.
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  -- 2. Role/store access.
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access to this invoice''s store'; end if;
  -- 3. Editable/payable + customer present.
  if v_inv.status in ('paid','cancelled','refunded') then raise exception 'Invoice is already %', v_inv.status; end if;
  -- Phase 12: a confirmed FOC invoice is closed; a fully-FOC invoice has no balance.
  if v_inv.status = 'completed_foc' then
    raise exception 'This invoice was completed as FOC and cannot take a payment'; end if;
  if coalesce(v_inv.is_full_foc,false) and coalesce(v_inv.total_amount,0) <= 0.001 then
    raise exception 'This invoice is fully FOC — use Confirm FOC Invoice instead of taking a payment'; end if;
  if v_inv.customer_id is null then raise exception 'Invoice has no customer'; end if;
  if p_payments is null or jsonb_array_length(p_payments) = 0 then raise exception 'At least one payment is required'; end if;

  -- Phase 19: Membership removed; every customer receives the normal price.

  -- 6. Reprice all applicable non-overridden lines (strict prices + eligibility
  --    enforced inside; raises with the line name if anything is missing).
  v_old_total := v_inv.total_amount;
  v_changes := public.reprice_invoice_lines(p_invoice_id, v_is_member);
  select * into v_inv from public.invoices where id = p_invoice_id;   -- fresh totals

  -- 7. If anything changed, persist the repriced invoice, record NO payment,
  --    and return a structured review request.
  if jsonb_array_length(v_changes) > 0 then
    perform public.write_audit('invoices', p_invoice_id, 'payment_price_review', null,
      jsonb_build_object('invoice_no', v_inv.invoice_no, 'old_total', v_old_total,
                         'new_total', v_inv.total_amount, 'changes', v_changes));
    return jsonb_build_object(
      'success', false, 'review_required', true,
      'old_total', v_old_total, 'new_total', v_inv.total_amount, 'changes', v_changes);
  end if;


  -- 13. Validate payment amounts.
  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_amount := (v_pay->>'amount')::numeric;
    if v_amount is null or v_amount <= 0 then raise exception 'Payment amount must be positive'; end if;
    v_total_paying := v_total_paying + v_amount;
  end loop;
  v_already_paid := v_inv.paid_amount;
  v_new_paid := v_already_paid + v_total_paying;
  if v_new_paid > v_inv.total_amount + 0.001 then raise exception 'Payment exceeds remaining balance'; end if;
  v_will_be_full := v_new_paid >= v_inv.total_amount - 0.001;

  -- 12. Stock check (only matters when this payment completes the invoice).
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

  -- 14. Record payments.
  for v_pay in select * from jsonb_array_elements(p_payments)
  loop
    v_method := (v_pay->>'payment_method_id')::uuid;
    v_amount := (v_pay->>'amount')::numeric;
    insert into public.invoice_payments (invoice_id, payment_method_id, amount, payment_reference, received_by)
    values (p_invoice_id, v_method, v_amount, v_pay->>'reference', auth.uid());
  end loop;

  if v_will_be_full then
    -- 15. Deduct stock.
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

    -- 16. Mark paid + lock.
    update public.invoices set status = 'paid', paid_amount = v_new_paid, paid_at = now(), locked_at = now()
      where id = p_invoice_id;

    -- Voucher redemptions (preserved).
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


    -- 19. Commissions.
    perform public.earn_invoice_commission(p_invoice_id);
    perform public.earn_staff_commission(p_invoice_id);

    -- 20. Audit.
    perform public.write_audit('invoices', p_invoice_id, 'invoice_paid', null,
      jsonb_build_object('paid_amount', v_new_paid, 'invoice_no', v_inv.invoice_no,
                         'foc_total', coalesce(v_inv.foc_total,0),
                         'mixed_foc', coalesce(v_inv.has_foc,false)));
    return jsonb_build_object('success', true, 'status', 'paid', 'paid_amount', v_new_paid);
  else
    -- Partial payment: money recorded, NOTHING activates, no stock moves.
    update public.invoices set paid_amount = v_new_paid, status = 'partially_paid' where id = p_invoice_id;
    perform public.write_audit('invoices', p_invoice_id, 'invoice_partial_payment', null,
      jsonb_build_object('paid_amount', v_new_paid));
    return jsonb_build_object('success', true, 'status', 'partially_paid', 'paid_amount', v_new_paid,
                              'remaining', v_inv.total_amount - v_new_paid);
  end if;
end; $function$;


CREATE OR REPLACE FUNCTION public.confirm_foc_invoice(p_invoice_id uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_inv public.invoices%rowtype; v_req record; v_available integer; v_li record;
  v_is_member boolean := true; v_changes jsonb;
  v_old_total numeric;
begin
  -- 1. Lock invoice.
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if v_inv.deleted_at is not null then raise exception 'Invoice has been deleted'; end if;

  -- 2. Access + role.
  if auth.uid() is not null then
    if public.current_user_role() is null then raise exception 'No profile for current user'; end if;
    if public.current_user_role() = 'inventory_manager' then
      raise exception 'Inventory Manager cannot confirm FOC invoices'; end if;
    if not public.user_has_store_access(v_inv.store_id) then
      raise exception 'No access to this invoice''s store'; end if;
  end if;

  -- 3. State gates.
  if v_inv.status in ('paid','cancelled','refunded') then raise exception 'Invoice is already %', v_inv.status; end if;
  if v_inv.status = 'completed_foc' then raise exception 'This FOC invoice has already been confirmed'; end if;
  if v_inv.customer_id is null then raise exception 'Invoice has no customer'; end if;
  if not coalesce(v_inv.has_foc,false) then raise exception 'This invoice has no FOC lines'; end if;
  if coalesce(v_inv.paid_amount,0) > 0 then
    raise exception 'This invoice already has payments — settle it through payment, not FOC confirmation'; end if;
  if coalesce(v_inv.total_amount,0) > 0.001 then
    raise exception 'This invoice still has a payable balance of %.2f — only a fully FOC invoice can be confirmed without payment',
      v_inv.total_amount; end if;

  -- Phase 19: Membership removed; every customer receives the normal price.

  -- 5. Reprice (keeps eligibility + FOC snapshots honest); surface any change.
  v_old_total := v_inv.total_amount;
  v_changes := public.reprice_invoice_lines(p_invoice_id, v_is_member);
  select * into v_inv from public.invoices where id = p_invoice_id;
  if jsonb_array_length(v_changes) > 0 then
    perform public.write_audit('invoices', p_invoice_id, 'foc_price_review', null,
      jsonb_build_object('invoice_no', v_inv.invoice_no, 'changes', v_changes));
    return jsonb_build_object('success', false, 'review_required', true,
      'old_total', v_old_total, 'new_total', v_inv.total_amount, 'changes', v_changes);
  end if;
  if coalesce(v_inv.total_amount,0) > 0.001 then
    raise exception 'Repricing left a payable balance of %.2f — this is no longer a fully FOC invoice', v_inv.total_amount; end if;


  -- 8. Stock check — FOC consumes real stock, so the same gate applies.
  for v_req in select * from public.invoice_required_stock(p_invoice_id)
  loop
    if v_req.kind = 'product' then
      select current_qty into v_available from public.store_inventory
        where store_id = v_inv.store_id and product_id = v_req.item_id for update;
      if coalesce(v_available,0) < v_req.quantity then
        raise exception 'Insufficient store stock for % (have %, need % incl. bundles). FOC blocked.',
          (select name from public.products where id = v_req.item_id), coalesce(v_available,0), v_req.quantity;
      end if;
    else
      select current_qty into v_available from public.voucher_store_stock
        where store_id = v_inv.store_id and voucher_id = v_req.item_id for update;
      if coalesce(v_available,0) < v_req.quantity then
        raise exception 'Insufficient voucher stock for % (have %, need % incl. bundles). FOC blocked.',
          (select name from public.vouchers where id = v_req.item_id), coalesce(v_available,0), v_req.quantity;
      end if;
    end if;
  end loop;

  -- 9. Deduct stock (products, vouchers, promotion components alike).
  for v_req in select * from public.invoice_required_stock(p_invoice_id)
  loop
    if v_req.kind = 'product' then
      update public.store_inventory set current_qty = current_qty - v_req.quantity, updated_at = now()
        where store_id = v_inv.store_id and product_id = v_req.item_id;
      insert into public.stock_movements (product_id, movement_type, from_store_id, invoice_id, quantity, notes, created_by)
      values (v_req.item_id, 'store_sale', v_inv.store_id, p_invoice_id, v_req.quantity,
              'FOC — '||v_inv.invoice_no, auth.uid());
    else
      update public.voucher_store_stock set current_qty = current_qty - v_req.quantity, updated_at = now()
        where store_id = v_inv.store_id and voucher_id = v_req.item_id;
      perform public.write_audit('vouchers', v_req.item_id, 'voucher_sold', null,
        jsonb_build_object('invoice_no', v_inv.invoice_no, 'qty', v_req.quantity, 'foc', true));
    end if;
  end loop;

  -- 10. Close the invoice (no payment rows are written).
  update public.invoices
     set status = 'completed_foc', paid_amount = 0, paid_at = now(), locked_at = now(),
         foc_confirmed_at = now(), foc_confirmed_by = auth.uid()
   where id = p_invoice_id;

  -- 11. Voucher redemptions (a FOC line can still carry a discount voucher).
  if v_inv.discount_voucher_id is not null then
    insert into public.voucher_redemptions (voucher_id, invoice_id, customer_id, discount_applied, redeemed_by)
    values (v_inv.discount_voucher_id, p_invoice_id, v_inv.customer_id,
            coalesce(v_inv.discount_total,0) - coalesce((select sum(line_discount) from public.invoice_items where invoice_id = p_invoice_id),0),
            auth.uid());
    perform public.write_audit('vouchers', v_inv.discount_voucher_id, 'voucher_redeemed', null,
      jsonb_build_object('invoice_no', v_inv.invoice_no, 'foc', true));
  end if;
  for v_li in select line_voucher_id, line_discount from public.invoice_items
    where invoice_id = p_invoice_id and line_voucher_id is not null
  loop
    insert into public.voucher_redemptions (voucher_id, invoice_id, customer_id, discount_applied, redeemed_by)
    values (v_li.line_voucher_id, p_invoice_id, v_inv.customer_id, v_li.line_discount, auth.uid());
    perform public.write_audit('vouchers', v_li.line_voucher_id, 'voucher_redeemed', null,
      jsonb_build_object('invoice_no', v_inv.invoice_no, 'line_discount', v_li.line_discount, 'foc', true));
  end loop;


  -- 13. Commissions. Both bases are the CHARGED value, which is zero here,
  --      so these are deliberate no-ops that keep the code path identical.
  perform public.earn_invoice_commission(p_invoice_id);
  perform public.earn_staff_commission(p_invoice_id);

  -- 14. Audit.
  perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_foc_confirmed', null,
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'foc_total', v_inv.foc_total,
                       'is_topup', coalesce(v_inv.is_topup,false)),
    'foc', p_note, v_inv.store_id);

  return jsonb_build_object('success', true, 'status', 'completed_foc',
    'foc_total', v_inv.foc_total, 'paid_amount', 0);
end $function$;


CREATE OR REPLACE FUNCTION public.customer_affiliate_state(p_customer_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_a public.customer_affiliates%rowtype; v_c public.customers%rowtype;
  v_state text; v_eligible boolean := false; v_reason text := null;
begin
  select * into v_c from public.customers where id = p_customer_id;
  select * into v_a from public.customer_affiliates where customer_id = p_customer_id and deleted_at is null;

  -- Phase 19: eligibility no longer depends on Membership or a Member ID.
  if v_a.id is null then
    v_state := 'not_activated'; v_reason := 'Affiliate Not Activated';
  elsif v_a.manually_suspended then
    v_state := 'suspended_manual'; v_reason := 'Affiliate Suspended';
  elsif v_c.id is null or v_c.deleted_at is not null then
    v_state := 'inactive'; v_reason := 'Customer Inactive';
  else
    v_state := 'active'; v_eligible := true;
  end if;

  return jsonb_build_object(
    'eligible', v_eligible, 'state', v_state, 'block_reason', v_reason,
    'has_profile', v_a.id is not null, 'manually_suspended', coalesce(v_a.manually_suspended,false),
    'store_id', v_a.store_id);
end $function$;


CREATE OR REPLACE FUNCTION public.activate_affiliate(p_customer_id uuid, p_store_id uuid DEFAULT NULL::uuid)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_id uuid; v_c public.customers%rowtype;
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can activate affiliates'; end if;
  select * into v_c from public.customers where id = p_customer_id and deleted_at is null;
  if not found then raise exception 'Customer not found or inactive'; end if;

  -- Phase 19: no Membership or Member ID prerequisite; Owner/Manager approval only.
  insert into public.customer_affiliates (customer_id, status, manually_suspended, store_id, activated_at, activated_by, created_by, updated_by)
  values (p_customer_id, 'active', false, p_store_id, now(), auth.uid(), auth.uid(), auth.uid())
  on conflict (customer_id) do update
    set manually_suspended = false, status = 'active', deleted_at = null,
        store_id = coalesce(excluded.store_id, public.customer_affiliates.store_id),
        reactivated_at = now(), reactivated_by = auth.uid(), updated_by = auth.uid(), updated_at = now()
  returning id into v_id;

  perform public.write_audit_ex('customer_affiliates', v_id, 'affiliate_activated',
    null, jsonb_build_object('customer', v_c.full_name, 'store', p_store_id), 'affiliates', null, p_store_id);
  return v_id;
end $function$;


CREATE OR REPLACE FUNCTION public.refresh_affiliate_statuses()
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_n integer := 0; v_a record; v_state jsonb; v_new text;
begin
  for v_a in select * from public.customer_affiliates where deleted_at is null loop
    v_state := public.customer_affiliate_state(v_a.customer_id);
    v_new := case
      when v_a.manually_suspended then 'suspended_manual'
      when coalesce((v_state->>'eligible')::boolean,false) then 'active'
      else v_state->>'state' end;
    if v_new is distinct from v_a.status then
      update public.customer_affiliates set status = v_new, updated_at = now() where id = v_a.id;
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end $function$;


CREATE OR REPLACE FUNCTION public.affiliate_directory()
 RETURNS TABLE(customer_id uuid, full_name text, phone text, member_id text, membership_status text, membership_plan text, membership_expiry date, affiliate_state text, block_reason text, store_id uuid, store_name text, direct_referrals integer, downline integer, lifetime_earned numeric, unpaid_payable numeric, blocked_commission numeric, last_commission_date date, has_profile boolean, manually_suspended boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with affs as (
    select distinct c.id as customer_id
    from public.customers c
    where c.deleted_at is null and (
      exists (select 1 from public.customer_affiliates a where a.customer_id = c.id and a.deleted_at is null)
      or exists (select 1 from public.customers r where r.referred_by = c.id)
      or exists (select 1 from public.commissions cm where cm.referrer_customer_id = c.id)
    )
  )
  select
    c.id, c.full_name, c.phone,
    null::text, null::text, null::text, null::date,
    st->>'state', st->>'block_reason',
    a.store_id, s.name,
    (select count(*)::int from public.customers r where r.referred_by = c.id),
    (select count(*)::int from public.customers r1
      where r1.referred_by = c.id
         or r1.referred_by in (select id from public.customers r2 where r2.referred_by = c.id)),
    coalesce((select sum(commission_amount) from public.commissions cm where cm.referrer_customer_id = c.id and cm.status in ('earned','paid')),0),
    coalesce((select sum(commission_amount) from public.commissions cm where cm.referrer_customer_id = c.id and cm.status = 'earned' and cm.payout_id is null),0),
    coalesce((select sum(commission_amount) from public.commissions cm where cm.referrer_customer_id = c.id and cm.status = 'blocked'),0),
    (select max(invoice_paid_date) from public.commissions cm where cm.referrer_customer_id = c.id),
    a.id is not null, coalesce(a.manually_suspended,false)
  from affs
  join public.customers c on c.id = affs.customer_id
  left join public.customer_affiliates a on a.customer_id = c.id and a.deleted_at is null
  left join public.stores s on s.id = a.store_id
  cross join lateral public.customer_affiliate_state(c.id) st
  order by c.full_name;
$function$;


CREATE OR REPLACE FUNCTION public.add_therapy_line(p_invoice_id uuid, p_package_id uuid, p_mode text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_inv public.invoices%rowtype; v_pkg public.unlimited_therapy_packages%rowtype;
        v_ms jsonb; v_member boolean; v_pj jsonb; v_price numeric; v_item_id uuid; v_mode text;
begin
  if public.current_user_role() = 'inventory_manager' then raise exception 'Inventory Manager cannot sell therapy'; end if;
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_inv.store_id) then raise exception 'No access to this store'; end if;
  if v_inv.status in ('paid','partially_paid','cancelled','refunded') or coalesce(v_inv.paid_amount,0) > 0 then
    raise exception 'Cannot change a paid or locked invoice'; end if;
  if v_inv.customer_id is null then raise exception 'Invoice has no customer'; end if;

  select * into v_pkg from public.unlimited_therapy_packages where id = p_package_id and deleted_at is null and is_active = true;
  if not found then raise exception 'Therapy package not found or inactive'; end if;

  -- One entitlement per package per active window: block if the customer already
  -- has an active/scheduled entitlement for this package (overlap rule).
  if exists (select 1 from public.purchased_therapy_entitlements
              where customer_id = v_inv.customer_id and package_id = p_package_id
                and status in ('active','scheduled','pending_activation')) then
    raise exception 'This customer already has a current entitlement for this package'; end if;

  -- Resolve applied mode: explicit override, else membership-derived.
  v_member := true;   -- Phase 19: single normal price for every customer
  if p_mode in ('member','non_member') then v_member := (p_mode = 'member'); end if;
  v_mode := case when v_member then 'member' else 'non_member' end;

  v_pj := public.therapy_price_for(v_inv.store_id, p_package_id, v_member);
  if not coalesce((v_pj->>'has_price')::boolean,false) then
    raise exception 'Therapy package "%" is missing its % price at this store', v_pkg.name,
      case when v_member then 'Member' else 'Non-Member' end; end if;
  v_price := (v_pj->>'price')::numeric;

  insert into public.invoice_items (
    invoice_id, line_kind, product_id, therapy_package_id, quantity, unit_price, line_total,
    price_mode, price_source, price_source_id, store_id_snapshot,
    member_price_snapshot, non_member_price_snapshot,
    plan_name_snapshot, plan_months_snapshot)
  values (
    p_invoice_id, 'therapy', null, p_package_id, 1, v_price, v_price,
    v_mode, 'therapy', p_package_id, v_inv.store_id,
    (v_pj->>'member_price')::numeric, (v_pj->>'non_member_price')::numeric,
    v_pkg.name, v_pkg.duration_months)
  returning id into v_item_id;

  update public.invoices set
    subtotal = coalesce((select sum(line_total) from public.invoice_items where invoice_id = p_invoice_id),0)
   where id = p_invoice_id;
  update public.invoices i set total_amount = greatest(0, i.subtotal - coalesce(i.discount_total,0)) where i.id = p_invoice_id;

  perform public.write_audit_ex('invoice_items', v_item_id, 'therapy_line_added',
    null, jsonb_build_object('package', v_pkg.name, 'price', v_price, 'mode', v_mode), 'therapy', null, v_inv.store_id);
  return v_item_id;
end $function$;


CREATE OR REPLACE FUNCTION public.audit_create_time_override(p_item_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_li public.invoice_items%rowtype; v_inv public.invoices%rowtype;
        v_auto_member boolean; v_auto_price numeric; v_ms jsonb;
begin
  select * into v_li from public.invoice_items where id = p_item_id;
  if not found or not coalesce(v_li.price_overridden,false) then return; end if;
  select * into v_inv from public.invoices where id = v_li.invoice_id;

  -- Automatic mode = what the customer would get without the override.
  v_auto_member := true;   -- Phase 19: single normal price
  v_auto_price := case when v_auto_member then v_li.member_price_snapshot else v_li.non_member_price_snapshot end;

  -- original_price should reflect the AUTOMATIC price, not the applied override.
  update public.invoice_items
     set original_price = coalesce(v_auto_price, original_price)
   where id = p_item_id;

  perform public.write_audit_ex('invoice_items', p_item_id, 'line_price_overridden',
    jsonb_build_object('previous_mode', case when v_auto_member then 'member' else 'non_member' end,
                       'previous_price', v_auto_price),
    jsonb_build_object('new_mode', v_li.price_mode, 'applied_price', v_li.unit_price,
                       'member_snapshot', v_li.member_price_snapshot,
                       'non_member_snapshot', v_li.non_member_price_snapshot,
                       'reason', v_li.override_reason, 'line_kind', v_li.line_kind,
                       'source_id', v_li.price_source_id, 'invoice_item_id', p_item_id,
                       'invoice_id', v_inv.id, 'customer_id', v_inv.customer_id),
    'pricing', v_li.override_reason, v_inv.store_id);
end $function$;


CREATE OR REPLACE FUNCTION public.report_pricing()
 RETURNS TABLE(invoice_id uuid, invoice_no text, paid_date date, store_id uuid, store_name text, customer_name text, line_kind text, item_name text, quantity integer, unit_price numeric, price_mode text, price_overridden boolean, override_reason text, member_price numeric, non_member_price numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    i.id, i.invoice_no, i.paid_at::date, i.store_id, s.name, c.full_name,
    ii.line_kind,
    coalesce(p.name, ii.plan_name_snapshot, v.name, 'item'),
    ii.quantity, ii.unit_price, ii.price_mode,
    coalesce(ii.price_overridden,false), ii.override_reason,
    ii.member_price_snapshot, ii.non_member_price_snapshot
  from public.invoice_items ii
  join public.invoices i on i.id = ii.invoice_id
  left join public.customers c on c.id = i.customer_id
  left join public.stores s on s.id = i.store_id
  left join public.products p on p.id = ii.product_id
  left join public.vouchers v on v.id = ii.voucher_id
  where i.status = 'paid'
  order by i.paid_at desc;
$function$;


CREATE OR REPLACE FUNCTION public.customer_purchase_timeline(p_customer_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(row order by row->>'date' desc nulls last), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'invoice_id', i.id,
      'invoice_no', i.invoice_no,
      'date', coalesce(i.paid_at, i.created_at),
      'status', i.status,
      'store', s.name,
      'total', i.total_amount,
      'paid', i.paid_amount,
      'is_topup', coalesce(i.is_topup, false),
      'save_earth', case when i.save_earth_applied then coalesce(i.save_earth_amount,0) else 0 end,
      'items', coalesce((
        select jsonb_agg(jsonb_build_object(
          'kind', ii.line_kind,
          'name', coalesce(p.name, ii.plan_name_snapshot, v.name, pr.name, 'item'),
          'qty', ii.quantity,
          'unit_price', ii.unit_price,
          'line_total', ii.line_total,
          'price_mode', ii.price_mode
        ) order by ii.id)
        from public.invoice_items ii
        left join public.products p on p.id = ii.product_id
        left join public.vouchers v on v.id = ii.voucher_id
        left join public.promotions pr on pr.id = ii.promotion_id
        where ii.invoice_id = i.id), '[]'::jsonb)
    ) as row
    from public.invoices i
    left join public.stores s on s.id = i.store_id
    where i.customer_id = p_customer_id and i.deleted_at is null
  ) t;
$function$;


CREATE OR REPLACE FUNCTION public.refund_invoice_line(p_invoice_item_id uuid, p_reason text, p_return_stock boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_li public.invoice_items%rowtype; v_inv public.invoices%rowtype;
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can refund directly. Staff/Admin submit a request.'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'A refund reason is required'; end if;

  select * into v_li from public.invoice_items where id = p_invoice_item_id;
  if not found then raise exception 'Line not found'; end if;
  select * into v_inv from public.invoices where id = v_li.invoice_id for update;
  if v_inv.status <> 'paid' then raise exception 'Only paid invoices can have lines refunded'; end if;

  -- Therapy: only before activation.
  if v_li.line_kind = 'therapy' then
    if exists (select 1 from public.purchased_therapy_entitlements
                where invoice_item_id = p_invoice_item_id and status in ('active','expired')) then
      raise exception 'Therapy cannot be refunded after activation'; end if;
    update public.purchased_therapy_entitlements set status = 'refunded', updated_at = now()
     where invoice_item_id = p_invoice_item_id and status in ('pending_activation','scheduled');
  end if;

  -- Return stock only for physical products, only if requested.
  if p_return_stock and v_li.line_kind = 'product' and v_li.product_id is not null then
    update public.store_inventory set current_qty = current_qty + v_li.quantity, updated_at = now()
     where store_id = v_inv.store_id and product_id = v_li.product_id;
    insert into public.stock_movements (product_id, movement_type, to_store_id, invoice_id, quantity, notes, created_by)
    values (v_li.product_id, 'refund_return', v_inv.store_id, v_inv.id, v_li.quantity, 'Line refund — '||v_inv.invoice_no, auth.uid());
  end if;

  -- Reverse this line's commissions (affiliate + staff).
  update public.commissions set status = 'reversed', reversal_reason = 'Line refunded: ' || p_reason
   where invoice_item_id = p_invoice_item_id and status in ('earned');
  perform public.reverse_staff_commission_line(p_invoice_item_id, 'Line refunded');

  insert into public.invoice_refunds (invoice_id, invoice_item_id, amount, reason, kind, return_stock, refunded_by)
  values (v_inv.id, p_invoice_item_id, v_li.line_total - coalesce(v_li.line_discount,0), p_reason,
          v_li.line_kind, p_return_stock, auth.uid())
  on conflict do nothing;

  perform public.write_audit_ex('invoice_items', p_invoice_item_id, 'line_refunded',
    null, jsonb_build_object('kind', v_li.line_kind, 'return_stock', p_return_stock), 'refunds', p_reason, v_inv.store_id);
end $function$;


CREATE OR REPLACE FUNCTION public.override_invoice_line_price(p_item_id uuid, p_mode text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_li public.invoice_items%rowtype; v_inv public.invoices%rowtype; v_pj jsonb;
        v_new numeric; v_role user_role; v_member boolean;
begin
  v_role := public.current_user_role();
  if v_role is null or v_role = 'inventory_manager' then raise exception 'Not permitted'; end if;
  if p_mode not in ('member','non_member') then raise exception 'Invalid price mode'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'An override reason is required'; end if;

  select * into v_li from public.invoice_items where id = p_item_id;
  if not found then raise exception 'Line not found'; end if;
  if v_li.line_kind not in ('product','voucher','promotion') then
    raise exception 'This line kind cannot be overridden'; end if;

  -- LOCK the invoice, then re-check everything that a concurrent payment
  -- could have changed while we waited for the lock.
  select * into v_inv from public.invoices where id = v_li.invoice_id for update;
  if v_inv.status in ('paid','cancelled','refunded') or v_inv.locked_at is not null then
    raise exception 'Invoice is locked'; end if;
  if coalesce(v_inv.paid_amount,0) > 0 then
    raise exception 'Lines cannot be changed after a payment has been recorded'; end if;
  if not (public.is_manager_or_above() or public.user_has_store_access(v_inv.store_id)) then
    raise exception 'No access to this invoice''s store'; end if;
  -- Re-read the line under the invoice lock (it may have been repriced).
  select * into v_li from public.invoice_items where id = p_item_id;
  if not found then raise exception 'Line not found'; end if;

  v_member := (p_mode = 'member');
  if v_li.line_kind = 'product' then
    v_pj := public.product_price_for(v_inv.store_id, v_li.product_id, v_member);
  elsif v_li.line_kind = 'voucher' then
    v_pj := public.voucher_price_for(v_inv.store_id, v_li.voucher_id, v_member);
  else
    v_pj := public.promotion_price_for(v_inv.store_id, v_li.promotion_id, v_member);
  end if;
  if not coalesce((v_pj->>'has_price')::boolean,false) then
    raise exception 'No % price is set for this line at this store', p_mode; end if;
  v_new := (v_pj->>'price')::numeric;

  update public.invoice_items
     set unit_price = v_new,
         line_total = (v_new * quantity) + coalesce(topup_amount,0),
         line_discount = case when line_voucher_id is not null
           then public.voucher_discount_amount(line_voucher_id, v_new * quantity)
           else line_discount end,
         price_mode = p_mode, price_source = 'manual_override',
         price_source_id = (v_pj->>'source_id')::uuid,
         member_price_snapshot = (v_pj->>'member_price')::numeric,
         non_member_price_snapshot = (v_pj->>'non_member_price')::numeric,
         original_price = coalesce(original_price, v_li.unit_price),
         price_overridden = true, override_reason = trim(p_reason),
         override_by = auth.uid(), override_at = now()
   where id = p_item_id;

  update public.invoices set subtotal =
    coalesce((select sum(line_total) from public.invoice_items where invoice_id = v_inv.id),0)
   where id = v_inv.id;
  perform public.refresh_invoice_discount_total(v_inv.id);
  update public.invoices i set total_amount = greatest(0, i.subtotal - coalesce(i.discount_total,0))
   where i.id = v_inv.id;

  perform public.write_audit_ex('invoice_items', p_item_id, 'line_price_overridden',
    jsonb_build_object('old_mode', v_li.price_mode, 'old_price', v_li.unit_price),
    jsonb_build_object('new_mode', p_mode, 'new_price', v_new), 'pricing', p_reason, v_inv.store_id);
end $function$;


CREATE OR REPLACE FUNCTION public.dashboard_summary()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_role text := public.current_user_role(); v_today date := public.sg_today(); v_out jsonb;
begin
  v_out := jsonb_build_object(
    'role', v_role,
    'today_sales', coalesce((select sum(total_amount) from public.invoices where status='paid' and paid_at::date = v_today),0),
    'today_count', coalesce((select count(*) from public.invoices where status='paid' and paid_at::date = v_today),0),
    'blocked_commission', coalesce((select sum(commission_amount) from public.commissions where status='blocked'),0),
    'therapy_awaiting', coalesce((select count(*) from public.purchased_therapy_entitlements where status='pending_activation'),0),
    'therapy_deadline_warn', coalesce((select count(*) from public.purchased_therapy_entitlements
       where status='pending_activation' and activation_deadline <= v_today + 30),0),
    'discount_today', coalesce((select sum(discount_total) from public.invoices where status='paid' and paid_at::date = v_today),0)
  );
  return v_out;
end $function$;


CREATE OR REPLACE FUNCTION public.customer_overview(p_customer_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_out jsonb;
begin
  v_out := jsonb_build_object(
    'affiliate_state', public.customer_affiliate_state(p_customer_id),
    'refunds', coalesce((select jsonb_agg(jsonb_build_object(
        'invoice', i.invoice_no, 'amount', r.amount, 'kind', r.kind, 'reason', r.reason, 'date', r.created_at) order by r.created_at desc)
      from public.invoice_refunds r join public.invoices i on i.id = r.invoice_id
      where i.customer_id = p_customer_id), '[]'::jsonb),
    'purchased_therapy', coalesce((select jsonb_agg(jsonb_build_object(
        'no', e.entitlement_no, 'package', e.package_name, 'status', e.status,
        'purchase', e.purchase_date, 'deadline', e.activation_deadline,
        'activation', e.activation_date, 'expiry', e.expiry_date) order by e.created_at desc)
      from public.purchased_therapy_entitlements e where e.customer_id = p_customer_id), '[]'::jsonb),
    'legacy_therapy', coalesce((select jsonb_agg(jsonb_build_object(
        'no', le.entitlement_no, 'package', le.package_name, 'status', le.status,
        'deadline', le.activation_deadline) order by le.created_at desc)
      from public.therapy_entitlements le where le.customer_id = p_customer_id), '[]'::jsonb),
    'deleted_invoices', coalesce((select jsonb_agg(jsonb_build_object(
        'invoice', i.invoice_no, 'total', i.total_amount, 'deleted_at', i.deleted_at) order by i.deleted_at desc)
      from public.invoices i where i.customer_id = p_customer_id and i.deleted_at is not null), '[]'::jsonb)
  );
  return v_out;
end $function$;
-- ---------------------------------------------------------------------
-- 4. DROP MEMBERSHIP DATABASE OBJECTS
--    Signatures are inspected from pg_proc rather than assumed, and only
--    the explicitly named Membership-only functions are dropped.
-- ---------------------------------------------------------------------
do $$
declare v_r record;
begin
  for v_r in
    select p.oid::regprocedure::text as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in (
         'commit_member_id','customer_membership_status','customer_owned_member_id',
         'edit_membership','invoice_membership_line','member_id_available',
         'membership_anniversary','membership_effective_status','membership_expiry',
         'membership_price_for','membership_renewal_start','next_membership_number',
         'reassign_member_id','refresh_membership_statuses','refund_membership_line',
         'release_member_id_reservation','release_member_id_reservations_for_invoice',
         'remove_membership_line','replace_invoice_member_id','report_memberships',
         'reserve_member_id','set_membership_member_id','set_membership_plan_price',
         'set_membership_status','set_membership_warn_thresholds','soft_delete_membership_plan',
         'trg_membership_line_guard','upsert_membership_plan',
         'trg_release_reservations_dead_invoice')
  loop
    execute 'drop function if exists ' || v_r.sig || ' cascade';
  end loop;
end $$;

-- Triggers that enforced Membership rules.
drop trigger if exists membership_line_guard on public.invoice_items;
drop trigger if exists release_reservations_dead_invoice on public.invoices;

-- Membership-only constraints and indexes on shared tables.
alter table public.invoice_items drop constraint if exists chk_membership_qty_one;
drop index if exists public.uq_invoice_one_membership;

-- Membership tables (their RLS policies, indexes and FKs go with them).
drop table if exists public.member_id_reservations cascade;
drop table if exists public.member_ids cascade;
drop table if exists public.customer_memberships cascade;
drop table if exists public.membership_plan_store_prices cascade;
drop table if exists public.membership_plans cascade;

-- Membership-only columns on shared tables. The plan_name/plan_months
-- snapshots stay: Purchasable Unlimited Therapy uses them.
alter table public.invoice_items drop column if exists membership_plan_id;
alter table public.invoice_items drop column if exists member_id_snapshot;
alter table public.customer_affiliates drop column if exists membership_expired_at;
alter table public.app_settings drop column if exists membership_warn_months_1;
alter table public.app_settings drop column if exists membership_warn_months_2;

-- ---------------------------------------------------------------------
-- 5. Affiliate statuses lose their Membership vocabulary. The affiliates
--    that were inactive only because of Membership were logged in step 2m
--    so Phase 20 can reactivate exactly those.
-- ---------------------------------------------------------------------
alter table public.customer_affiliates drop constraint if exists customer_affiliates_status_check;
update public.customer_affiliates
   set status = case
     when status in ('inactive_membership_expired','inactive_missing_member_id','inactive_no_membership')
       then 'inactive' else status end
 where status in ('inactive_membership_expired','inactive_missing_member_id','inactive_no_membership');
alter table public.customer_affiliates
  add constraint customer_affiliates_status_check
  check (status in ('active','suspended_manual','inactive','soft_deleted'));

-- ---------------------------------------------------------------------
-- 6. Remove 'membership' from the invoice line-kind enum. Only
--    invoice_items.line_kind uses this type.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
              where t.typname = 'invoice_line_kind' and e.enumlabel = 'membership') then
    alter type public.invoice_line_kind rename to invoice_line_kind_pre19;
    create type public.invoice_line_kind as enum ('product','voucher','promotion','therapy');
    alter table public.invoice_items alter column line_kind drop default;
    alter table public.invoice_items
      alter column line_kind type public.invoice_line_kind
      using line_kind::text::public.invoice_line_kind;
    alter table public.invoice_items alter column line_kind set default 'product';
    drop type public.invoice_line_kind_pre19;
  end if;
end $$;

notify pgrst, 'reload schema';
