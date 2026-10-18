-- One-off repair: P00039's opening stock was entered twice at WH-0906 (420, STOCK-5).
--
-- WHAT IS WRONG
--
--   On 30 Jul 2026, before go-live, the opening stock of P00039 (Energia
--   Mattress Pad - Queen) at warehouse WH-0906 was entered as three Stock Ins,
--   all with the reason "Opening stock" (Singapore time):
--     12:17  3   movement a399b487-c2a0-4777-b407-43957de95db8
--     12:37  3   movement 1f43e3c0-2cdb-4290-9ee0-794d3ad90f48   <- the same 3 again
--     12:49  74  movement d25c032f-612a-41a3-b827-3839c4eec763
--   The second 3 is the first entered twice, so WH-0906 shows 3 more than are
--   there. Production, read 9 Oct 2026 (read only): WH-0906 holds 77 of P00039
--   (80 in, then 3 out by transfer on 31 Aug, 7 Sep and 28 Sep). No stock
--   correction for P00039 at WH-0906 was ever asked for or made, and none waits.
--
-- THE RULE (the Owner, 9 Oct 2026)
--
--   Yes, the pair was entered twice. Remove the duplicate 3 as a stock
--   correction, with the reason in Stock History, checking the stock first.
--   Run once at deploy, with the Owner's go-ahead.
--
-- WHAT IT DOES (one DO block, so all of it or none)
--
--   * One stock correction of 3 out of WH-0906 for P00039: a movement of type
--     inventory_adjustment (Stock History shows it as an Adjustment) whose note
--     is the reason below, and WH-0906's P00039 stock down by 3 (77 -> 74 as
--     read on 9 Oct 2026). Stock History records the change itself.
--   * One audit row (warehouse_inventory, 'duplicate_stock_in_removed') with
--     the stock before and after and the two Stock Ins.
--   * It prints one line: what it did, or that it was already done.
--   It writes no approval request (a request needs a person who asked), so the
--   correction shows in Stock History and the Audit Log, not on Adjustments.
--
-- SAFETY
--
--   It refuses, changing nothing, when:
--   * P00039 or WH-0906 is not there exactly once;
--   * the two Stock Ins of 30 Jul are not exactly as read (3 each, "Opening
--     stock", into WH-0906 for P00039, the second after the first, that day);
--   * a stock correction for P00039 at WH-0906 was made or approved after the
--     first of them (a count may already have taken the 3 off: ask the Owner),
--     or one waits for approval (approve or reject it first);
--   * WH-0906 holds fewer than 3 of P00039 now (count the shelf first).
--   If the stock is no longer 77 (sales or transfers since 9 Oct), it still
--   takes the 3 off and says from what to what. A second run finds its own
--   correction and changes nothing. It needs nothing from migration 420.
--
-- HOW TO RUN
--
--   As the database owner (the SQL editor, the MCP execute_sql tool, or psql
--   as postgres). Try it between begin; and rollback; first, then run it once.
--
-- Test: scripts/repairs/tests/p00039-duplicate-opening-stock.sql (fixtures only).

do $repair$
declare
  c_sku constant text := 'P00039';
  c_wh_code constant text := 'WH-0906';
  c_first constant uuid := 'a399b487-c2a0-4777-b407-43957de95db8';
  c_dup constant uuid := '1f43e3c0-2cdb-4290-9ee0-794d3ad90f48';
  c_qty constant integer := 3;
  c_read_qty constant integer := 77;   -- WH-0906's P00039 stock, read 9 Oct 2026
  c_note constant text := 'Adjustment: Opening stock of 30 Jul 2026 was entered twice (3 at 12:17, the same 3 again at 12:37). '
                          || 'The second 3 is taken off, as the Owner decided on 9 Oct 2026.';
  v_path text := current_setting('search_path');
  v_p uuid; v_wh uuid; v_first public.stock_movements%rowtype; v_dup public.stock_movements%rowtype;
  v_inv uuid; v_now integer; v_mid uuid; n integer;
begin
  perform set_config('search_path', 'public', true);
  if to_regprocedure('public.write_audit(text,uuid,text,jsonb,jsonb)') is null then
    raise exception 'repair: write_audit is missing; nothing was changed'; end if;

  select count(*), min(p.id::text)::uuid into n, v_p from public.products p where p.sku = c_sku;
  if n <> 1 then raise exception 'repair: % products have the SKU %, not 1; nothing was changed', n, c_sku; end if;
  select count(*), min(w.id::text)::uuid into n, v_wh from public.warehouses w where w.code = c_wh_code;
  if n <> 1 then raise exception 'repair: % warehouses have the code %, not 1; nothing was changed', n, c_wh_code; end if;

  -- Already done by an earlier run: its own correction is there.
  if exists (select 1 from public.stock_movements m
              where m.product_id = v_p and m.from_warehouse_id = v_wh and m.movement_type = 'inventory_adjustment'
                and m.quantity = c_qty and m.notes = c_note) then
    raise notice 'repair: already done (the correction of the duplicate opening stock of % at % is there); nothing was changed',
      c_sku, c_wh_code;
    perform set_config('search_path', v_path, true);
    return;
  end if;

  -- The two Stock Ins, exactly as read on 9 Oct 2026.
  select * into v_first from public.stock_movements where id = c_first;
  select * into v_dup from public.stock_movements where id = c_dup;
  if v_first.id is null or v_dup.id is null
     or v_first.product_id is distinct from v_p or v_dup.product_id is distinct from v_p
     or v_first.movement_type::text <> 'warehouse_stock_in' or v_dup.movement_type::text <> 'warehouse_stock_in'
     or v_first.to_warehouse_id is distinct from v_wh or v_dup.to_warehouse_id is distinct from v_wh
     or v_first.quantity <> c_qty or v_dup.quantity <> c_qty
     or v_first.notes is distinct from 'Opening stock' or v_dup.notes is distinct from 'Opening stock'
     or (v_first.created_at at time zone 'Asia/Singapore')::date <> date '2026-07-30'
     or (v_dup.created_at at time zone 'Asia/Singapore')::date <> date '2026-07-30'
     or v_dup.created_at <= v_first.created_at then
    raise exception 'repair: the two Opening stock entries of 30 Jul 2026 for % at % are not as read on 9 Oct 2026; re-read them; nothing was changed',
      c_sku, c_wh_code; end if;

  -- A count since then may already have taken the 3 off.
  if exists (select 1 from public.approval_requests a
              where a.request_type = 'adjustment' and a.status = 'pending'
                and a.payload ->> 'product_id' = v_p::text and a.payload ->> 'location_id' = v_wh::text) then
    raise exception 'repair: a stock correction for % at % waits for approval; approve or reject it first; nothing was changed',
      c_sku, c_wh_code; end if;
  if exists (select 1 from public.stock_movements m
              where m.product_id = v_p and m.movement_type = 'inventory_adjustment'
                and (m.from_warehouse_id = v_wh or m.to_warehouse_id = v_wh) and m.created_at > v_first.created_at)
     or exists (select 1 from public.approval_requests a
                 where a.request_type = 'adjustment' and a.status = 'approved' and a.created_at > v_first.created_at
                   and a.payload ->> 'product_id' = v_p::text and a.payload ->> 'location_id' = v_wh::text) then
    raise exception 'repair: % at % was counted and corrected after 30 Jul 2026, so the duplicate may already be gone; ask the Owner; nothing was changed',
      c_sku, c_wh_code; end if;

  -- The stock now (locked until the end).
  select wi.id, wi.current_qty into v_inv, v_now from public.warehouse_inventory wi
   where wi.warehouse_id = v_wh and wi.product_id = v_p for update;
  if v_inv is null or v_now < c_qty then
    raise exception 'repair: % holds % of % now, fewer than the % to take off; count the shelf first; nothing was changed',
      c_wh_code, coalesce(v_now, 0), c_sku, c_qty; end if;

  insert into public.stock_movements (product_id, movement_type, from_warehouse_id, quantity, notes, created_by)
  values (v_p, 'inventory_adjustment', v_wh, c_qty, c_note, null)
  returning id into v_mid;
  update public.warehouse_inventory set current_qty = current_qty - c_qty, updated_at = now() where id = v_inv;
  perform public.write_audit('warehouse_inventory', v_p, 'duplicate_stock_in_removed',
    jsonb_build_object('sku', c_sku, 'warehouse', c_wh_code, 'qty', v_now, 'stock_ins', jsonb_build_array(c_first, c_dup)),
    jsonb_build_object('sku', c_sku, 'warehouse', c_wh_code, 'qty', v_now - c_qty, 'movement_id', v_mid, 'note', c_note,
                       'repair', '420 p00039-duplicate-opening-stock'));

  raise notice '%', format('repair: took the duplicate %s off %s at %s: %s -> %s%s', c_qty, c_sku, c_wh_code, v_now, v_now - c_qty,
    case when v_now = c_read_qty then '' else ' (it was ' || c_read_qty || ' on 9 Oct 2026; the stock moved since)' end);
  perform set_config('search_path', v_path, true);
end $repair$;
