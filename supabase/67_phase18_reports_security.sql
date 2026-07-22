-- =====================================================================
-- ENERGIA — PHASE 18: REPORTS, DASHBOARD, SECURITY, FINAL VALIDATION
--
--  * Completes the reporting surface over Phases 10–17:
--    TikTok (settlement by created/settled date, by store, quantity sold
--    by SKU/product/voucher/promotion, orders by status, unmatched SKUs,
--    orders-without-settlement, settlements-without-order, reconciliation
--    differences, stock deductions/returns/corrections, import
--    discrepancies), transfers (receipts, discrepancies, overdue),
--    exchange invoices, and a TikTok vs general sales reconciliation that
--    NEVER double-counts (normal invoices exclude exchange invoices;
--    TikTok creates no invoices at all — proven by the Phase 16 tests).
--  * One dashboard summary function feeds the operations alert cards
--    (transfers / TikTok / surveys / FOC).
--  * Security stays enforced by RLS + SECURITY DEFINER functions; the
--    Phase 18 test file is the cross-phase verification battery.
--
-- Additive + idempotent. Run AFTER 66.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Transfer reports (receipts / overdue). Discrepancies + in-transit
--    reports already exist from Phase 11 and stay untouched.
-- ---------------------------------------------------------------------
create or replace function public.report_transfer_receipts(
  p_from date default null, p_to date default null
) returns table (
  transfer_id uuid, transfer_type text, source_name text, dest_name text,
  status text, dispatched_at timestamptz, received_at timestamptz,
  received_by_name text, line_count bigint, received_units bigint,
  had_discrepancy boolean, discrepancy_resolved boolean
) language sql stable security definer set search_path = public as $$
  select t.id, t.transfer_type,
         coalesce(sw.name, ss.name), coalesce(dw.name, ds.name),
         t.status::text, t.dispatched_at, t.received_at, p.full_name,
         (select count(*) from public.transfer_request_lines l where l.transfer_request_id = t.id),
         (select coalesce(sum(l.received_quantity),0) from public.transfer_request_lines l where l.transfer_request_id = t.id),
         t.has_discrepancy, t.discrepancy_resolved
    from public.transfer_requests t
    left join public.warehouses sw on t.source_type = 'warehouse' and sw.id = t.source_id
    left join public.stores ss on t.source_type = 'store' and ss.id = t.source_id
    left join public.warehouses dw on t.dest_type = 'warehouse' and dw.id = t.dest_id
    left join public.stores ds on t.dest_type = 'store' and ds.id = t.dest_id
    left join public.profiles p on p.id = t.received_by
   where t.status in ('received','received_with_discrepancy','completed')
     and t.received_at is not null
     and (p_from is null or t.received_at::date >= p_from)
     and (p_to is null or t.received_at::date <= p_to)
   order by t.received_at desc
$$;

create or replace function public.report_transfers_overdue(p_days integer default 7)
returns table (
  transfer_id uuid, transfer_type text, source_name text, dest_name text,
  dispatched_at timestamptz, days_in_transit integer, line_count bigint, units_in_transit bigint
) language sql stable security definer set search_path = public as $$
  select t.id, t.transfer_type,
         coalesce(sw.name, ss.name), coalesce(dw.name, ds.name),
         t.dispatched_at,
         greatest(0, (extract(epoch from (now() - t.dispatched_at)) / 86400)::integer),
         (select count(*) from public.transfer_request_lines l where l.transfer_request_id = t.id),
         (select coalesce(sum(l.in_transit_quantity),0) from public.transfer_request_lines l where l.transfer_request_id = t.id)
    from public.transfer_requests t
    left join public.warehouses sw on t.source_type = 'warehouse' and sw.id = t.source_id
    left join public.stores ss on t.source_type = 'store' and ss.id = t.source_id
    left join public.warehouses dw on t.dest_type = 'warehouse' and dw.id = t.dest_id
    left join public.stores ds on t.dest_type = 'store' and ds.id = t.dest_id
   where t.status = 'in_transit' and t.dispatched_at is not null
     and t.dispatched_at < now() - make_interval(days => greatest(1, p_days))
   order by t.dispatched_at
$$;

-- ---------------------------------------------------------------------
-- 2. Exchange invoice report.
-- ---------------------------------------------------------------------
create or replace function public.report_exchange_invoices(
  p_store_id uuid default null, p_from date default null, p_to date default null
) returns table (
  exchange_id uuid, exchange_no text, invoice_no text, store_name text,
  customer_name text, created_at timestamptz,
  returned_credit numeric, replacement_total numeric, topup_amount numeric,
  nonrefundable_amount numeric, is_foc boolean, foc_amount numeric
) language sql stable security definer set search_path = public as $$
  select e.id, e.exchange_no, i.invoice_no, s.name, c.full_name, e.created_at,
         e.returned_credit_total, e.replacement_total, e.topup_amount,
         e.nonrefundable_amount, coalesce(e.is_foc,false), coalesce(e.foc_amount,0)
    from public.product_exchanges e
    left join public.invoices i on i.exchange_id = e.id and i.is_exchange = true
    join public.stores s on s.id = e.processing_store_id
    left join public.customers c on c.id = e.customer_id
   where (p_store_id is null or e.processing_store_id = p_store_id)
     and (p_from is null or e.created_at::date >= p_from)
     and (p_to is null or e.created_at::date <= p_to)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(e.processing_store_id))
   order by e.created_at desc
$$;

-- ---------------------------------------------------------------------
-- 3. TikTok reports.
-- ---------------------------------------------------------------------
-- Settlement per day, by Order Created date (default) or Settled date.
create or replace function public.report_tiktok_settlement_daily(
  p_store_id uuid default null, p_from date default null, p_to date default null,
  p_basis text default 'created'
) returns table (
  day date, transactions bigint, settlement numeric, revenue numeric, fees numeric
) language sql stable security definer set search_path = public as $$
  select d.day, count(*), coalesce(sum(r.settlement_amount),0),
         coalesce(sum(r.revenue_amount),0), coalesce(sum(r.fee_amount),0)
    from public.tiktok_settlement_rows r
    cross join lateral (select case when p_basis = 'settled'
        then (r.settled_time at time zone 'Asia/Singapore')::date
        else coalesce(r.order_created_time at time zone 'Asia/Singapore',
                      r.settled_time at time zone 'Asia/Singapore')::date end as day) d
   where r.confirmed and r.is_current and d.day is not null
     and (p_store_id is null or r.store_id = p_store_id)
     and (p_from is null or d.day >= p_from) and (p_to is null or d.day <= p_to)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(r.store_id))
   group by d.day order by d.day desc
$$;

create or replace function public.report_tiktok_settlement_by_store(
  p_from date default null, p_to date default null
) returns table (
  store_name text, transactions bigint, settlement numeric, revenue numeric, fees numeric,
  pending_count bigint, unreconciled_count bigint
) language sql stable security definer set search_path = public as $$
  select s.name, count(*), coalesce(sum(r.settlement_amount),0),
         coalesce(sum(r.revenue_amount),0), coalesce(sum(r.fee_amount),0),
         count(*) filter (where r.match_status = 'pending'),
         count(*) filter (where r.reconciled is false)
    from public.tiktok_settlement_rows r
    join public.stores s on s.id = r.store_id
   where r.confirmed and r.is_current
     and (p_from is null or coalesce(r.order_created_time, r.settled_time)::date >= p_from)
     and (p_to is null or coalesce(r.order_created_time, r.settled_time)::date <= p_to)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(r.store_id))
   group by s.name order by 3 desc
$$;

-- Net quantity sold, in four dimensions at once: by Seller SKU and by the
-- mapped product / voucher / promotion. Net = confirmed deltas (deductions
-- minus returns), so it can never double-count re-imports.
create or replace function public.report_tiktok_qty_sold(
  p_store_id uuid default null, p_from date default null, p_to date default null
) returns table (
  dimension text, item_key text, item_name text, orders bigint, net_units bigint
) language sql stable security definer set search_path = public as $$
  with base as (
    select o.* from public.tiktok_order_rows o
     where o.confirmed and o.stock_delta <> 0
       and (p_store_id is null or o.store_id = p_store_id)
       and (p_from is null or o.confirmed_at::date >= p_from)
       and (p_to is null or o.confirmed_at::date <= p_to)
       and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
            or public.user_has_store_access(o.store_id))
  )
  select 'sku', b.seller_sku, b.seller_sku, count(distinct b.order_id), sum(b.stock_delta)::bigint
    from base b group by b.seller_sku
  union all
  select 'product', p.id::text, p.name, count(distinct b.order_id), sum(b.stock_delta)::bigint
    from base b join public.products p on b.matched_kind = 'product' and p.id = b.matched_id
   group by p.id, p.name
  union all
  select 'voucher', v.id::text, v.name, count(distinct b.order_id), sum(b.stock_delta)::bigint
    from base b join public.vouchers v on b.matched_kind = 'voucher' and v.id = b.matched_id
   group by v.id, v.name
  union all
  select 'promotion', pr.id::text, pr.name, count(distinct b.order_id), sum(b.stock_delta)::bigint
    from base b join public.promotions pr on b.matched_kind = 'promotion' and pr.id = b.matched_id
   group by pr.id, pr.name
   order by 1, 5 desc
$$;

create or replace function public.report_tiktok_orders_by_status(p_store_id uuid default null)
returns table (order_status text, order_items bigint, net_deducted bigint)
language sql stable security definer set search_path = public as $$
  select coalesce(s.last_status,'(unknown)'), count(*), coalesce(sum(s.deducted_qty),0)::bigint
    from public.tiktok_order_state s
   where (p_store_id is null or s.store_id = p_store_id)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(s.store_id))
   group by 1 order by 2 desc
$$;

create or replace function public.report_tiktok_unmatched_skus(p_store_id uuid default null)
returns table (store_name text, seller_sku text, occurrences bigint, last_seen timestamptz, still_unmapped boolean)
language sql stable security definer set search_path = public as $$
  select s.name, o.seller_sku, count(*), max(b.uploaded_at),
         not exists (select 1 from public.tiktok_sku_aliases a
                      where a.store_id = o.store_id and a.seller_sku = o.seller_sku)
    from public.tiktok_order_rows o
    join public.tiktok_import_batches b on b.id = o.batch_id
    join public.stores s on s.id = o.store_id
   where o.staging_status = 'Unmatched SKU' and o.seller_sku is not null
     and (p_store_id is null or o.store_id = p_store_id)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(o.store_id))
   group by s.name, o.store_id, o.seller_sku
   order by 3 desc
$$;

-- Reconciliation exceptions, three kinds in one report:
--   order_without_settlement · settlement_without_order · reconciliation_difference
create or replace function public.report_tiktok_recon_exceptions(p_store_id uuid default null)
returns table (kind text, store_name text, order_id text, detail text, amount numeric)
language sql stable security definer set search_path = public as $$
  -- Imported orders with stock deducted but no current settlement yet.
  select 'order_without_settlement', s.name, st.order_id,
         'net deducted ' || sum(st.deducted_qty)::text || ' unit(s)', null::numeric
    from public.tiktok_order_state st
    join public.stores s on s.id = st.store_id
   where st.deducted_qty > 0
     and not exists (select 1 from public.tiktok_settlement_rows r
                      where r.store_id = st.store_id and r.matched_order_id = st.order_id
                        and r.is_current and r.confirmed)
     and (p_store_id is null or st.store_id = p_store_id)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(st.store_id))
   group by s.name, st.store_id, st.order_id
  union all
  -- Confirmed settlements still waiting for their order.
  select 'settlement_without_order', s.name, r.order_id,
         coalesce(r.transaction_type,'') , r.settlement_amount
    from public.tiktok_settlement_rows r
    join public.stores s on s.id = r.store_id
   where r.confirmed and r.is_current and r.match_status = 'pending'
     and (p_store_id is null or r.store_id = p_store_id)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(r.store_id))
  union all
  -- Settlement ≠ Revenue + Fees beyond the $0.01 tolerance.
  select 'reconciliation_difference', s.name, r.order_id,
         'settlement ' || r.settlement_amount::text || ' vs revenue+fees '
           || (coalesce(r.revenue_amount,0) + coalesce(r.fee_amount,0))::text,
         r.settlement_amount - (coalesce(r.revenue_amount,0) + coalesce(r.fee_amount,0))
    from public.tiktok_settlement_rows r
    join public.stores s on s.id = r.store_id
   where r.confirmed and r.is_current and r.reconciled is false
     and (p_store_id is null or r.store_id = p_store_id)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(r.store_id))
   order by 1, 3
$$;

-- Stock activity: deductions, returns and corrections in one stream.
create or replace function public.report_tiktok_stock_activity(
  p_store_id uuid default null, p_from date default null, p_to date default null
) returns table (
  kind text, store_name text, order_id text, seller_sku text,
  units integer, occurred_at timestamptz, reason text
) language sql stable security definer set search_path = public as $$
  select case when o.stock_delta > 0 then 'deduction' else 'return' end,
         s.name, o.order_id, o.seller_sku, abs(o.stock_delta), o.confirmed_at, o.order_status
    from public.tiktok_order_rows o
    join public.stores s on s.id = o.store_id
   where o.confirmed and o.stock_delta <> 0
     and (p_store_id is null or o.store_id = p_store_id)
     and (p_from is null or o.confirmed_at::date >= p_from)
     and (p_to is null or o.confirmed_at::date <= p_to)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(o.store_id))
  union all
  select 'correction', s.name, o2.order_id, o2.seller_sku, c.qty_delta, c.created_at, c.reason
    from public.tiktok_corrections c
    left join public.tiktok_order_rows o2 on o2.id = c.order_row_id
    join public.stores s on s.id = c.store_id
   where (p_store_id is null or c.store_id = p_store_id)
     and (p_from is null or c.created_at::date >= p_from)
     and (p_to is null or c.created_at::date <= p_to)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(c.store_id))
   order by 6 desc
$$;

-- Import discrepancies: what each batch could NOT apply, and why.
create or replace function public.report_tiktok_import_discrepancies(p_store_id uuid default null)
returns table (
  batch_id uuid, store_name text, file_name text, uploaded_at timestamptz,
  invalid_rows bigint, duplicate_rows bigint, unmatched_rows bigint,
  invalid_status_rows bigint, excluded_rows bigint
) language sql stable security definer set search_path = public as $$
  select b.id, s.name, b.file_name, b.uploaded_at,
         count(*) filter (where o.staging_status = 'Invalid Row'),
         count(*) filter (where o.staging_status = 'Duplicate Row'),
         count(*) filter (where o.staging_status = 'Unmatched SKU'),
         count(*) filter (where o.staging_status = 'Invalid Status'),
         count(*) filter (where o.excluded and not o.confirmed)
    from public.tiktok_import_batches b
    join public.stores s on s.id = b.store_id
    join public.tiktok_order_rows o on o.batch_id = b.id
   where b.deleted_at is null and b.file_kind = 'order'
     and (p_store_id is null or b.store_id = p_store_id)
     and (public.current_user_role() in ('owner','manager','admin','inventory_manager')
          or public.user_has_store_access(b.store_id))
   group by b.id, s.name, b.file_name, b.uploaded_at
  having count(*) filter (where o.staging_status in ('Invalid Row','Duplicate Row','Unmatched SKU','Invalid Status')
                          or (o.excluded and not o.confirmed)) > 0
   order by b.uploaded_at desc
$$;

-- ---------------------------------------------------------------------
-- 4. TikTok vs general sales reconciliation — one row per channel,
--    counted from disjoint sources so nothing is ever double-counted:
--      invoice_sales     -> paid amounts on NON-exchange invoices
--      exchange_invoices -> paid amounts on exchange invoices (top-ups)
--      tiktok_settlement -> current confirmed settlement (creates NO invoices)
-- ---------------------------------------------------------------------
create or replace function public.report_sales_reconciliation(
  p_store_id uuid default null, p_from date default null, p_to date default null
) returns table (channel text, transactions bigint, amount numeric)
language sql stable security definer set search_path = public as $$
  select 'invoice_sales', count(*), coalesce(sum(i.paid_amount),0)
    from public.invoices i
   where i.is_exchange is not true and i.paid_amount > 0
     and i.status in ('paid','partially_paid','completed_foc')
     and (p_store_id is null or i.store_id = p_store_id)
     and (p_from is null or coalesce(i.paid_at, i.created_at)::date >= p_from)
     and (p_to is null or coalesce(i.paid_at, i.created_at)::date <= p_to)
  union all
  select 'exchange_invoices', count(*), coalesce(sum(i.paid_amount),0)
    from public.invoices i
   where i.is_exchange is true and i.paid_amount > 0
     and (p_store_id is null or i.store_id = p_store_id)
     and (p_from is null or coalesce(i.paid_at, i.created_at)::date >= p_from)
     and (p_to is null or coalesce(i.paid_at, i.created_at)::date <= p_to)
  union all
  select 'tiktok_settlement', count(*), coalesce(sum(r.settlement_amount),0)
    from public.tiktok_settlement_rows r
   where r.confirmed and r.is_current
     and (p_store_id is null or r.store_id = p_store_id)
     and (p_from is null or coalesce(r.order_created_time, r.settled_time)::date >= p_from)
     and (p_to is null or coalesce(r.order_created_time, r.settled_time)::date <= p_to)
$$;

-- ---------------------------------------------------------------------
-- 5. Dashboard alerts summary (single round-trip for the alert cards).
-- ---------------------------------------------------------------------
create or replace function public.dashboard_alerts_summary()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'transfers', jsonb_build_object(
      'awaiting_receipt', (select count(*) from public.transfer_requests t where t.status = 'in_transit'),
      'overdue_7d', (select count(*) from public.transfer_requests t
                      where t.status = 'in_transit' and t.dispatched_at < now() - interval '7 days'),
      'open_discrepancies', (select count(*) from public.transfer_requests t
                              where t.has_discrepancy and not coalesce(t.discrepancy_resolved,false))),
    'tiktok', jsonb_build_object(
      'imported_orders', (select count(distinct (store_id, order_id)) from public.tiktok_order_state),
      'unmatched_skus', (select count(distinct (o.store_id, o.seller_sku)) from public.tiktok_order_rows o
                          where o.staging_status = 'Unmatched SKU'
                            and not exists (select 1 from public.tiktok_sku_aliases a
                                             where a.store_id = o.store_id and a.seller_sku = o.seller_sku)),
      'staged_batches', (select count(*) from public.tiktok_import_batches b
                          where b.status = 'staged' and b.deleted_at is null),
      'orders_awaiting_settlement', (select count(*) from public.tiktok_order_state st
                                      where st.deducted_qty > 0
                                        and not exists (select 1 from public.tiktok_settlement_rows r
                                                         where r.store_id = st.store_id and r.matched_order_id = st.order_id
                                                           and r.is_current and r.confirmed)),
      'settlement_mismatches', (select count(*) from public.tiktok_settlement_rows r
                                 where r.confirmed and r.is_current and r.reconciled is false),
      'awaiting_physical_return', (select count(*) from public.tiktok_physical_returns pr where pr.status = 'awaiting'),
      'negative_stock', (select count(*) from public.tiktok_negative_stock_alerts())),
    'surveys', jsonb_build_object(
      'customers_without_source', (select count(*) from public.customers c
                                    where c.deleted_at is null and c.source_option_id is null)),
    'foc', jsonb_build_object(
      'value_30d', coalesce((select sum(il.foc_amount) from public.invoice_items il
                              join public.invoices i on i.id = il.invoice_id
                             where il.is_foc and i.created_at > now() - interval '30 days'), 0))
  )
$$;

notify pgrst, 'reload schema';
