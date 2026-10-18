-- One-off repair: the stock left under three deleted products (420, STOCK-7).
--
-- WHAT IS WRONG
--
--   Before 420 a product could be deleted while stock was still recorded
--   under it. Three were (production, read 9 Oct 2026):
--     PK00031            Queen Sleeping System Set   3 at RETAIL-ADELPHI  (deleted 7 Aug 2026)
--     Zhimalaya          Himalaya Salt              13 at RETAIL-ADELPHI  (deleted 14 Sep 2026)
--     ZPILLOWCASEFLORAL  Pillow Case Floral          5 at WH-0906         (deleted 14 Sep 2026)
--   21 units in all. None is on an invoice line or an open transfer. Nobody
--   can sell, move or count them, and they show only in Stock History.
--
-- THE RULE (the Owner, 9 Oct 2026, Q12 option 3)
--
--   After a shelf check, bring back the products still on the shelf and still
--   sold, and write off the rest. The Owner says which. From 420 on, the app
--   refuses to delete a product, store or warehouse that still holds stock.
--
-- HOW TO USE IT
--
--   1. Do the shelf check. Then, in the list just below, replace each '?'
--      with one of:
--        'restore'    bring the product back: active again, with its SKU,
--                     category and supplier links and its store prices as
--                     they were. Its stock is counted as it stands; correct it
--                     afterwards with a normal adjustment if the shelf differs.
--        'write_off'  set the product's stock to 0 at every place, with a
--                     stock movement for the full quantity whose note gives
--                     the reason, so Stock History shows why. The product
--                     stays deleted.
--        'leave'      change nothing for this product now.
--      Put the reason in the note, for example 'Not on the shelf at the
--      shelf check of 10 Oct 2026'. A write-off needs a note.
--   2. Run the whole file as the database owner (the SQL editor, the MCP
--      execute_sql tool, or psql as postgres). The changes are one statement
--      (the DO block), so they all happen or none does. To try it first, run
--      it between begin; and rollback;.
--   3. It prints counts only. A second run changes nothing.
--
-- SAFETY
--
--   It refuses, changing nothing, while any choice is still '?', when a
--   product is not deleted (and not already restored by this repair), or when
--   a product's stock is not exactly what was read on 9 Oct 2026 (re-read it
--   then, and update the list in the DO block). A restore needs an active
--   store price wherever the product has store stock: it switches back on a
--   price that was switched off, and otherwise refuses (give the price in the
--   store_price column). Every change writes an audit row. The write-off's
--   movement is an inventory_adjustment out of the place, as an approved
--   correction to 0 would be.
--
-- Test: scripts/repairs/tests/deleted-products-stock.sql (fixtures only).

create temp table if not exists repair_420_choices (
  sku text primary key,
  action text not null check (action in ('?', 'restore', 'write_off', 'leave')),
  note text,
  store_price numeric(12,2) check (store_price is null or store_price >= 0)
);
-- ── 1. The choices: fill in after the shelf check ─────────────────────────
insert into repair_420_choices (sku, action, note, store_price) values
  ('PK00031',           '?', null, null),   -- Queen Sleeping System Set: 3 at RETAIL-ADELPHI
  ('Zhimalaya',         '?', null, null),   -- Himalaya Salt: 13 at RETAIL-ADELPHI
  ('ZPILLOWCASEFLORAL', '?', null, null)    -- Pillow Case Floral: 5 at WH-0906
on conflict (sku) do nothing;

-- ── 2. The repair: do not edit below ─────────────────────────────────────
do $repair$
declare
  -- Each product's stock as read on 9 Oct 2026: sku|store or warehouse|place code|quantity.
  c_expected constant text[] := array[
    'PK00031|store|RETAIL-ADELPHI|3',
    'Zhimalaya|store|RETAIL-ADELPHI|13',
    'ZPILLOWCASEFLORAL|warehouse|WH-0906|5'];
  v_path text := current_setting('search_path');
  r record; s record; v_p public.products%rowtype; v_rows text; v_want text; v_note text;
  n_restored int := 0; n_written int := 0; n_units int := 0; n_left int := 0; n_already int := 0;
begin
  perform set_config('search_path', 'public', true);
  if to_regprocedure('public.write_audit(text,uuid,text,jsonb,jsonb)') is null then
    raise exception 'repair: write_audit is missing; nothing was changed'; end if;
  if exists (select 1 from repair_420_choices where action = '?') then
    raise exception 'repair: fill in a choice for every product after the shelf check (restore, write_off or leave); nothing was changed'; end if;
  if exists (select 1 from repair_420_choices c
              where c.sku not in (select split_part(e, '|', 1) from unnest(c_expected) e)) then
    raise exception 'repair: a choice names a product this repair does not cover; nothing was changed'; end if;
  if exists (select 1 from repair_420_choices where action = 'write_off' and nullif(btrim(coalesce(note, '')), '') is null) then
    raise exception 'repair: a write-off needs a note saying why (it goes into Stock History); nothing was changed'; end if;

  for r in select c.* from repair_420_choices c order by c.sku loop
    if r.action = 'leave' then n_left := n_left + 1; continue; end if;
    select * into v_p from public.products p where p.sku = r.sku for update;
    if not found then raise exception 'repair: no product has the SKU %; nothing was changed', r.sku; end if;

    -- The stock now, as text in the list's form.
    select string_agg(x, ',' order by x) into v_rows from (
      select r.sku || '|store|' || st.code || '|' || si.current_qty as x
        from public.store_inventory si join public.stores st on st.id = si.store_id
       where si.product_id = v_p.id and si.current_qty <> 0
      union all
      select r.sku || '|warehouse|' || w.code || '|' || wi.current_qty
        from public.warehouse_inventory wi join public.warehouses w on w.id = wi.warehouse_id
       where wi.product_id = v_p.id and wi.current_qty <> 0) q;
    select string_agg(e, ',' order by e) into v_want from unnest(c_expected) e where split_part(e, '|', 1) = r.sku;

    -- Already done by an earlier run: restored, or written off to 0.
    if (r.action = 'restore' and v_p.deleted_at is null and v_p.is_active)
       or (r.action = 'write_off' and v_p.deleted_at is not null and v_rows is null
           and exists (select 1 from public.audit_logs a where a.record_id = v_p.id
                        and a.action = 'deleted_product_stock_written_off')) then
      n_already := n_already + 1; continue;
    end if;
    if v_p.deleted_at is null then
      raise exception 'repair: % is not deleted any more; re-read it; nothing was changed', r.sku; end if;
    if v_rows is distinct from v_want then
      raise exception 'repair: the stock of % is % now, not % as read on 9 Oct 2026; re-read it; nothing was changed',
        r.sku, coalesce(v_rows, 'none'), v_want; end if;

    if r.action = 'restore' then
      -- A price wherever it has store stock, so it can be sold there.
      for s in select si.store_id, st.code from public.store_inventory si join public.stores st on st.id = si.store_id
                where si.product_id = v_p.id and si.current_qty <> 0 loop
        if not exists (select 1 from public.store_product_prices pr where pr.product_id = v_p.id and pr.store_id = s.store_id
                         and pr.is_active and pr.deleted_at is null) then
          if exists (select 1 from public.store_product_prices pr where pr.product_id = v_p.id and pr.store_id = s.store_id) then
            update public.store_product_prices pr set is_active = true, deleted_at = null
             where pr.product_id = v_p.id and pr.store_id = s.store_id;
          elsif r.store_price is not null then
            insert into public.store_product_prices (store_id, product_id, selling_price) values (s.store_id, v_p.id, r.store_price);
          else
            raise exception 'repair: % has no price at %; give one in store_price; nothing was changed', r.sku, s.code;
          end if;
        end if;
      end loop;
      update public.products set deleted_at = null, is_active = true, updated_at = now() where id = v_p.id;
      perform public.write_audit('products', v_p.id, 'deleted_product_restored',
        jsonb_build_object('sku', v_p.sku, 'deleted_at', v_p.deleted_at),
        jsonb_build_object('sku', v_p.sku, 'note', r.note, 'stock', v_rows, 'repair', '420 deleted-products-stock'));
      n_restored := n_restored + 1;
    else
      v_note := 'Written off: product deleted ' || to_char(v_p.deleted_at at time zone 'Asia/Singapore', 'FMDD Mon YYYY')
                || '. ' || btrim(r.note);
      for s in select 'store' as kind, si.store_id as place_id, si.current_qty as qty
                 from public.store_inventory si where si.product_id = v_p.id and si.current_qty <> 0
               union all
               select 'warehouse', wi.warehouse_id, wi.current_qty
                 from public.warehouse_inventory wi where wi.product_id = v_p.id and wi.current_qty <> 0 loop
        if s.kind = 'store' then
          insert into public.stock_movements (product_id, movement_type, from_store_id, to_store_id, quantity, notes, created_by)
          values (v_p.id, 'inventory_adjustment',
                  case when s.qty > 0 then s.place_id end, case when s.qty < 0 then s.place_id end,
                  abs(s.qty), v_note, null);
          update public.store_inventory set current_qty = 0, updated_at = now()
           where store_id = s.place_id and product_id = v_p.id;
        else
          insert into public.stock_movements (product_id, movement_type, from_warehouse_id, to_warehouse_id, quantity, notes, created_by)
          values (v_p.id, 'inventory_adjustment',
                  case when s.qty > 0 then s.place_id end, case when s.qty < 0 then s.place_id end,
                  abs(s.qty), v_note, null);
          update public.warehouse_inventory set current_qty = 0, updated_at = now()
           where warehouse_id = s.place_id and product_id = v_p.id;
        end if;
        n_units := n_units + abs(s.qty);
      end loop;
      perform public.write_audit('products', v_p.id, 'deleted_product_stock_written_off',
        jsonb_build_object('sku', v_p.sku, 'stock', v_rows),
        jsonb_build_object('sku', v_p.sku, 'stock', 'none', 'note', v_note, 'repair', '420 deleted-products-stock'));
      n_written := n_written + 1;
    end if;
  end loop;

  raise notice 'repair: % restored, % written off (% units), % left as they are, % already done',
    n_restored, n_written, n_units, n_left, n_already;
  perform set_config('search_path', v_path, true);
end $repair$;
