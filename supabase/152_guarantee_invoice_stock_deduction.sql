-- =====================================================================
-- ENERGIA — GUARANTEE THAT A SETTLED INVOICE DEDUCTS EVERY PHYSICAL ITEM
--
-- ROOT CAUSE
-- ----------
-- The single function that decides what an invoice consumes,
-- invoice_required_stock(), correctly expands a promotion / premium bundle
-- into the products (and limited vouchers) it contains, including the
-- customer's chosen options. But whether that function is the one the
-- SETTLEMENT path actually uses depends on which historical definition is
-- live — and this project carries several, plus UPGRADE_to_current.sql, which
-- sorts AFTER every numbered migration and whose pay_invoice deducts stock by
-- walking invoice_items directly (v_item.product_id / v_item.quantity). A
-- promotion line has product_id NULL and its goods live in promotion_items,
-- so that older settlement path counts nothing for a promotion's contents —
-- exactly the symptom: direct products deduct, promotion/bundle products do
-- not. The premium_bundle branch of invoice_required_stock also only arrived
-- in 137, so any environment running an earlier definition never deducts a
-- bundle's stock at all.
--
-- A second, data-level cause exists independently: a promotion with no rows in
-- promotion_items, or a choice whose selection was never written to
-- invoice_promotion_selections, has nothing to expand and so consumes nothing.
--
-- WHAT THIS MIGRATION DOES
-- ------------------------
--   1. Re-establishes the canonical expansion (promotion_stock_items,
--      invoice_required_stock) so the source of truth is correct here,
--      regardless of what an older file left behind.
--   2. Adds ensure_invoice_stock_deducted(): one idempotent, net-aware
--      deduction built on invoice_required_stock(). It deducts only the
--      MISSING quantity, writes the stock movement, and refuses to over-sell.
--   3. Fires it from an AFTER-UPDATE trigger the moment an invoice becomes
--      paid / completed_foc. Because it is net-aware it never double-deducts
--      alongside the existing settlement code, and because it is a trigger it
--      keeps working even if pay_invoice is later reverted to an older
--      definition by a rebuild — UPGRADE_to_current.sql does not know to drop
--      it. This is the guarantee that a paid invoice cannot leave stock behind.
--   4. Adds read-only diagnostics and gap reports, and a PREVIEW-FIRST,
--      Owner/Manager-only repair for invoices already paid before this fix.
--   5. Asserts, at the end, that the live functions really contain the
--      canonical logic — so a wrong older definition cannot silently win.
--
-- Nothing here changes credit issuance, wallet, commission, FOC, therapy,
-- special-product / rental fulfilment, refunds, exchanges or corrections.
-- It only guarantees the physical-stock deduction those flows already intend.
--
-- Additive and idempotent. Run AFTER 151.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Canonical promotion expansion (recursive through nested promotions).
--    Re-affirmed so an older definition cannot be the live one.
-- ---------------------------------------------------------------------
create or replace function public.promotion_stock_items(p_promotion_id uuid, p_multiplier integer default 1)
returns table (kind text, item_id uuid, quantity integer)
language plpgsql stable security definer set search_path = public as $function$
declare v_item record;
begin
  if p_promotion_id is null then return; end if;
  for v_item in select * from public.promotion_items where promotion_id = p_promotion_id
  loop
    if v_item.item_type = 'product' then
      kind := 'product'; item_id := v_item.product_id;
      quantity := v_item.quantity * p_multiplier; return next;
    elsif v_item.item_type = 'voucher' then
      -- Only limited vouchers carry physical stock.
      if exists (select 1 from public.vouchers where id = v_item.voucher_id and qty_type = 'limited') then
        kind := 'voucher'; item_id := v_item.voucher_id;
        quantity := v_item.quantity * p_multiplier; return next;
      end if;
    elsif v_item.item_type = 'promotion' then
      -- Nested promotion: expand recursively, carrying the multiplier.
      return query select * from public.promotion_stock_items(v_item.child_promotion_id, v_item.quantity * p_multiplier);
    end if;
    -- 'treatment' and any other type carry no store stock.
  end loop;
end; $function$;

-- ---------------------------------------------------------------------
-- 2. Canonical required-stock: the ONE source of truth. Aggregates every
--    physical requirement of an invoice by (kind, item_id).
--
--    Covers: direct product lines; limited-voucher lines; the fixed contents
--    of promotions AND premium bundles (both keep contents in promotion_items
--    and both carry a promotion_id); nested promotions (via the recursion
--    above); and the products / limited vouchers the customer chose from
--    option groups (invoice_promotion_selections). Same product from several
--    sources is summed, not de-duplicated.
--
--    Non-stock kinds (therapy, credit_package, special_product, rental) and
--    unlimited vouchers contribute nothing, by construction.
-- ---------------------------------------------------------------------
create or replace function public.invoice_required_stock(p_invoice_id uuid)
returns table (kind text, item_id uuid, quantity bigint)
language sql stable security definer set search_path = public as $function$
  with expanded as (
    -- A. direct product line
    select 'product'::text as kind, ii.product_id as item_id, ii.quantity::bigint as quantity
      from public.invoice_items ii
     where ii.invoice_id = p_invoice_id and ii.line_kind::text = 'product'
       and ii.product_id is not null
    union all
    -- limited-voucher line
    select 'voucher', ii.voucher_id, ii.quantity::bigint
      from public.invoice_items ii
      join public.vouchers v on v.id = ii.voucher_id and v.qty_type = 'limited'
     where ii.invoice_id = p_invoice_id and ii.line_kind::text = 'voucher'
    union all
    -- B/C/D. promotion OR premium-bundle fixed contents, expanded recursively
    select s.kind, s.item_id, (s.quantity)::bigint
      from public.invoice_items ii
      cross join lateral public.promotion_stock_items(ii.promotion_id, ii.quantity) s
     where ii.invoice_id = p_invoice_id
       and ii.line_kind::text in ('promotion', 'premium_bundle')
       and ii.promotion_id is not null
    union all
    -- E/F. products chosen from option groups
    select 'product', ips.product_id, ips.quantity::bigint
      from public.invoice_promotion_selections ips
      join public.invoice_items ii on ii.id = ips.invoice_item_id
     where ii.invoice_id = p_invoice_id and ips.product_id is not null
    union all
    -- limited vouchers chosen from option groups
    select 'voucher', ips.voucher_id, ips.quantity::bigint
      from public.invoice_promotion_selections ips
      join public.invoice_items ii on ii.id = ips.invoice_item_id
      join public.vouchers v on v.id = ips.voucher_id and v.qty_type = 'limited'
     where ii.invoice_id = p_invoice_id and ips.voucher_id is not null
  )
  -- G. group by item and SUM, so the same product from several sources adds up
  select kind, item_id, sum(quantity) as quantity
    from expanded
   where item_id is not null
   group by kind, item_id
$function$;

-- ---------------------------------------------------------------------
-- 3. Net physical stock a PAID invoice has actually taken for one product,
--    from the movement ledger: what left as a sale, minus what a correction
--    returned. This is what "already deducted" means everywhere below.
--
--    Only these two movement types belong to an invoice's own settlement.
--    Refund returns are a deliberate reversal and are NOT added back here,
--    so a refunded item is never re-deducted.
-- ---------------------------------------------------------------------
create or replace function public.invoice_product_net_deducted(p_invoice_id uuid, p_product_id uuid)
returns bigint
language sql stable security definer set search_path = public as $function$
  select coalesce(sum(
           case sm.movement_type
             when 'store_sale'            then sm.quantity
             when 'invoice_cancel_return' then -sm.quantity
             else 0
           end), 0)::bigint
    from public.stock_movements sm
   where sm.invoice_id = p_invoice_id
     and sm.product_id = p_product_id
$function$;

-- ---------------------------------------------------------------------
-- 4. THE canonical, idempotent deduction.
--
--    For a settled invoice, for every physical PRODUCT it requires, deduct
--    only the quantity still missing (required - net already deducted) and
--    record a movement. Do nothing when the correct quantity is already out.
--    Verifies availability for ALL missing quantities BEFORE deducting any,
--    so a shortage fails cleanly and leaves nothing half-applied.
--
--    Limited-voucher stock is intentionally NOT settled here: vouchers keep
--    no movement ledger, so it stays with the existing settlement path
--    (invoice_required_stock is reused there too). Products are the goods that
--    physically leave the shop and the ones this guarantee is about.
--
--    Returns the number of product lines it actually deducted (0 = nothing to do).
-- ---------------------------------------------------------------------
create or replace function public.ensure_invoice_stock_deducted(p_invoice_id uuid, p_note text default null)
returns integer
language plpgsql security definer set search_path = public as $function$
declare
  v_inv public.invoices%rowtype;
  v_req record; v_net bigint; v_missing bigint; v_have integer;
  v_note text; v_src text; v_n integer := 0;
begin
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then return 0; end if;
  -- Physical stock is only settled for settled invoices.
  if v_inv.status not in ('paid','completed_foc') then return 0; end if;

  -- Pass 1 — verify availability for every missing product first.
  for v_req in select * from public.invoice_required_stock(p_invoice_id) where kind = 'product'
  loop
    v_net := public.invoice_product_net_deducted(p_invoice_id, v_req.item_id);
    v_missing := v_req.quantity - v_net;
    if v_missing > 0 then
      select coalesce(current_qty, 0) into v_have from public.store_inventory
        where store_id = v_inv.store_id and product_id = v_req.item_id for update;
      if coalesce(v_have, 0) < v_missing then
        raise exception 'Insufficient stock for "%": need % more (incl. promotions/bundles), have %',
          coalesce((select name from public.products where id = v_req.item_id), v_req.item_id::text),
          v_missing, coalesce(v_have, 0);
      end if;
    end if;
  end loop;

  -- Pass 2 — deduct only the missing quantity and record the movement.
  for v_req in select * from public.invoice_required_stock(p_invoice_id) where kind = 'product'
  loop
    v_net := public.invoice_product_net_deducted(p_invoice_id, v_req.item_id);
    v_missing := v_req.quantity - v_net;
    if v_missing <= 0 then continue; end if;

    update public.store_inventory
       set current_qty = current_qty - v_missing, updated_at = now()
     where store_id = v_inv.store_id and product_id = v_req.item_id;

    -- Best-effort provenance for the history note (secondary to the quantity).
    select string_agg(distinct pr.name, ', ') into v_src
      from public.invoice_items ii
      join public.promotions pr on pr.id = ii.promotion_id
     where ii.invoice_id = p_invoice_id
       and ii.line_kind::text in ('promotion','premium_bundle')
       and exists (select 1 from public.promotion_stock_items(ii.promotion_id, ii.quantity) s
                    where s.item_id = v_req.item_id);
    v_note := coalesce(p_note, 'Sale — ' || v_inv.invoice_no)
              || case when v_src is not null then ' (via ' || v_src || ')' else '' end;

    insert into public.stock_movements
      (product_id, movement_type, from_store_id, invoice_id, quantity, notes, created_by)
    values (v_req.item_id, 'store_sale'::stock_movement_type, v_inv.store_id, p_invoice_id,
            v_missing, v_note, auth.uid());
    v_n := v_n + 1;
  end loop;

  return v_n;
end; $function$;

-- ---------------------------------------------------------------------
-- 5. The guarantee: settle stock the instant an invoice becomes paid /
--    completed_foc. Net-aware, so it composes with the existing settlement
--    and correction code instead of double-deducting; trigger-based, so it
--    survives an older pay_invoice being reinstalled by a rebuild.
-- ---------------------------------------------------------------------
create or replace function public.trg_guarantee_invoice_stock() returns trigger
language plpgsql security definer set search_path = public as $function$
begin
  if new.status in ('paid','completed_foc') and old.status is distinct from new.status then
    perform public.ensure_invoice_stock_deducted(new.id, 'Sale — ' || new.invoice_no);
  end if;
  return null;
end; $function$;

drop trigger if exists guarantee_invoice_stock on public.invoices;
create trigger guarantee_invoice_stock
  after update of status on public.invoices
  for each row execute function public.trg_guarantee_invoice_stock();

-- ---------------------------------------------------------------------
-- 6. Per-invoice diagnostic (req 13): every physical requirement, where it
--    comes from, how much is required, how much is recorded, and a verdict.
--    A promotion with no stock-bearing contents is shown explicitly instead
--    of silently contributing nothing.
-- ---------------------------------------------------------------------
create or replace function public.invoice_stock_diagnostic(p_invoice_no text)
returns table (
  invoice_no text, status text, store_name text,
  line_kind text, promotion_name text, promotion_qty integer,
  product_name text, source text,
  required_qty bigint, recorded_qty bigint, missing_qty bigint, verdict text)
language plpgsql stable security definer set search_path = public as $function$
declare v_inv public.invoices%rowtype;
begin
  select * into v_inv from public.invoices where invoice_no = p_invoice_no limit 1;
  if not found then return; end if;

  return query
  with rows as (
    -- Direct product lines.
    select 'product'::text as lk, null::uuid as promo_id, ii.product_id as pid,
           ii.quantity::bigint as req, 'Direct'::text as src
      from public.invoice_items ii
     where ii.invoice_id = v_inv.id and ii.line_kind::text = 'product' and ii.product_id is not null
    union all
    -- Promotion / premium-bundle fixed + nested contents.
    select ii.line_kind::text, ii.promotion_id, s.item_id, s.quantity::bigint,
           case
             when ii.line_kind::text = 'premium_bundle' then 'Premium Bundle'
             when exists (select 1 from public.promotion_items pit
                           where pit.promotion_id = ii.promotion_id
                             and pit.item_type = 'product' and pit.product_id = s.item_id)
               then 'Fixed Promotion Item'
             else 'Nested Promotion'
           end
      from public.invoice_items ii
      cross join lateral public.promotion_stock_items(ii.promotion_id, ii.quantity) s
     where ii.invoice_id = v_inv.id
       and ii.line_kind::text in ('promotion','premium_bundle')
       and ii.promotion_id is not null and s.kind = 'product'
    union all
    -- Chosen products from option groups.
    select ii.line_kind::text, ii.promotion_id, ips.product_id, ips.quantity::bigint, 'Promotion Choice'
      from public.invoice_promotion_selections ips
      join public.invoice_items ii on ii.id = ips.invoice_item_id
     where ii.invoice_id = v_inv.id and ips.product_id is not null
    union all
    -- Promotions / bundles that expand to NOTHING (mis-configured or no choice recorded).
    select ii.line_kind::text, ii.promotion_id, null::uuid, 0::bigint, '(no stock-bearing items)'
      from public.invoice_items ii
     where ii.invoice_id = v_inv.id
       and ii.line_kind::text in ('promotion','premium_bundle') and ii.promotion_id is not null
       and not exists (select 1 from public.promotion_stock_items(ii.promotion_id, ii.quantity) s where s.kind = 'product')
       and not exists (select 1 from public.invoice_promotion_selections ips
                        join public.invoice_items ii2 on ii2.id = ips.invoice_item_id
                       where ii2.id = ii.id and ips.product_id is not null)
  ),
  agg as (
    select lk, promo_id, pid, src, sum(req) as req
      from rows group by lk, promo_id, pid, src
  )
  select
    v_inv.invoice_no, v_inv.status::text,
    (select name from public.stores where id = v_inv.store_id),
    a.lk,
    (select name from public.promotions where id = a.promo_id),
    (select ii.quantity from public.invoice_items ii
      where ii.invoice_id = v_inv.id and ii.promotion_id = a.promo_id
      order by ii.ctid limit 1),
    (select name from public.products where id = a.pid),
    a.src,
    a.req,
    case when a.pid is null then 0
         else public.invoice_product_net_deducted(v_inv.id, a.pid) end,
    case when a.pid is null then 0
         else greatest(0, (select sum(r2.quantity) from public.invoice_required_stock(v_inv.id) r2
                            where r2.item_id = a.pid and r2.kind = 'product')
                          - public.invoice_product_net_deducted(v_inv.id, a.pid)) end,
    case
      when a.pid is null then 'PROMOTION HAS NO STOCK-BEARING ITEMS'
      when v_inv.status not in ('paid','completed_foc') then 'not settled yet'
      when (select sum(r3.quantity) from public.invoice_required_stock(v_inv.id) r3
             where r3.item_id = a.pid and r3.kind = 'product')
           <= public.invoice_product_net_deducted(v_inv.id, a.pid)
        then 'OK'
      else 'MISSING'
    end
  from agg a
  order by a.src, product_name;
end; $function$;

-- ---------------------------------------------------------------------
-- 7. Read-only historical gap report (req 14). Settled invoices only.
--    required - net_recorded = missing, for every physical product.
-- ---------------------------------------------------------------------
create or replace function public.invoice_stock_gaps(
  p_invoice_no text default null, p_store_id uuid default null,
  p_from date default null, p_to date default null)
returns table (
  invoice_id uuid, invoice_no text, invoice_status text, store_id uuid,
  paid_at timestamptz, product_id uuid, product_name text,
  required bigint, net_recorded bigint, missing bigint)
language sql stable security definer set search_path = public as $function$
  select i.id, i.invoice_no, i.status::text, i.store_id, i.paid_at,
         r.item_id,
         (select name from public.products where id = r.item_id),
         r.quantity,
         public.invoice_product_net_deducted(i.id, r.item_id),
         r.quantity - public.invoice_product_net_deducted(i.id, r.item_id)
    from public.invoices i
    cross join lateral public.invoice_required_stock(i.id) r
   where i.deleted_at is null
     and i.status in ('paid','completed_foc')
     and r.kind = 'product'
     and (p_invoice_no is null or i.invoice_no = p_invoice_no)
     and (p_store_id  is null or i.store_id = p_store_id)
     and (p_from is null or (i.paid_at at time zone 'Asia/Singapore')::date >= p_from)
     and (p_to   is null or (i.paid_at at time zone 'Asia/Singapore')::date <= p_to)
     and r.quantity - public.invoice_product_net_deducted(i.id, r.item_id) <> 0
   order by i.paid_at desc nulls last, i.invoice_no
$function$;

-- ---------------------------------------------------------------------
-- 8. PREVIEW-FIRST repair (req 15). Owner/Manager only. Default is preview:
--    it changes nothing and shows exactly what it would deduct. Executing it
--    reuses the idempotent ensure_ function (deducts only positive missing,
--    checks inventory, writes movements) and audits the repair. Idempotent:
--    a second run finds no gap and deducts nothing.
-- ---------------------------------------------------------------------
create or replace function public.repair_invoice_stock_gap(p_invoice_id uuid, p_preview boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $function$
declare
  v_inv public.invoices%rowtype; v_gap jsonb; v_before jsonb; v_after jsonb; v_deducted integer;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can repair stock gaps';
  end if;
  select * into v_inv from public.invoices where id = p_invoice_id;
  if not found then raise exception 'Invoice not found'; end if;
  if v_inv.status not in ('paid','completed_foc') then
    raise exception 'Only a settled (paid / completed FOC) invoice can be reconciled';
  end if;

  -- The gap, per product, right now.
  select coalesce(jsonb_agg(jsonb_build_object(
           'product_id', g.product_id, 'product', g.product_name,
           'required', g.required, 'recorded', g.net_recorded, 'missing', g.missing)
           order by g.product_name), '[]'::jsonb)
    into v_gap
    from public.invoice_stock_gaps(v_inv.invoice_no) g
   where g.invoice_id = p_invoice_id and g.missing > 0;

  if v_gap = '[]'::jsonb then
    return jsonb_build_object('invoice_no', v_inv.invoice_no, 'preview', p_preview,
                              'gap', '[]'::jsonb, 'message', 'No stock gap found', 'deducted', 0);
  end if;

  if p_preview then
    return jsonb_build_object('invoice_no', v_inv.invoice_no, 'preview', true,
                              'gap', v_gap, 'message', 'Preview only — nothing was changed');
  end if;

  -- Execute: idempotent, net-aware deduction of only the missing quantity.
  v_deducted := public.ensure_invoice_stock_deducted(p_invoice_id,
                  'Stock reconciliation — ' || v_inv.invoice_no);

  perform public.write_audit_ex('invoices', p_invoice_id, 'stock_gap_repaired', null,
    jsonb_build_object('invoice_no', v_inv.invoice_no, 'gap', v_gap,
                       'products_deducted', v_deducted, 'repaired_by', auth.uid()),
    'inventory', 'historical stock reconciliation', v_inv.store_id);

  return jsonb_build_object('invoice_no', v_inv.invoice_no, 'preview', false,
                            'gap', v_gap, 'deducted', v_deducted,
                            'message', 'Repaired: deducted the missing quantity and recorded movements');
end; $function$;

-- ---------------------------------------------------------------------
-- 9. Assertions — a wrong older definition must not silently win (req 17).
-- ---------------------------------------------------------------------
do $$
declare v_req text; v_promo text;
begin
  select prosrc into v_req from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'invoice_required_stock';
  select prosrc into v_promo from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'promotion_stock_items';

  if v_req is null then raise exception 'invoice_required_stock is not installed'; end if;
  if position('promotion_stock_items' in v_req) = 0 then
    raise exception 'invoice_required_stock does not expand promotions'; end if;
  if position('invoice_promotion_selections' in v_req) = 0 then
    raise exception 'invoice_required_stock ignores promotion choice selections'; end if;
  if position('premium_bundle' in v_req) = 0 then
    raise exception 'invoice_required_stock ignores premium bundles'; end if;
  if v_promo is null or position('child_promotion_id' in v_promo) = 0 then
    raise exception 'promotion_stock_items does not recurse nested promotions'; end if;

  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname='public' and p.proname='ensure_invoice_stock_deducted') then
    raise exception 'ensure_invoice_stock_deducted is missing'; end if;
  if not exists (select 1 from pg_trigger where tgname = 'guarantee_invoice_stock' and not tgisinternal) then
    raise exception 'guarantee_invoice_stock trigger is not installed'; end if;

  raise notice 'Confirmed: canonical required-stock is active, and settlement now guarantees deduction.';
  raise notice 'To inspect one invoice:  select * from public.invoice_stock_diagnostic(''INV-2026-XXXX'');';
  raise notice 'To find historical gaps:  select * from public.invoice_stock_gaps();';
  raise notice 'To preview a repair:      select public.repair_invoice_stock_gap(''<invoice uuid>'');   -- preview by default';
end $$;

notify pgrst, 'reload schema';
