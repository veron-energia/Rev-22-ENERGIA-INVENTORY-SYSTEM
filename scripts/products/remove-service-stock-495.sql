-- 495, DEPLOY ORDER step 4 (the user, 6 Nov 2026: "Build, remove it"): takes the
-- stock typed onto services down to 0 with a normal adjustment, an Owner approving
-- each line, so the Adjustments page, Approvals, the movements and the stock
-- history all say what happened and why. Past movements and invoices stay.
--
-- One transaction, and all or nothing. Run after 495, with the recording account
-- set first in the same transaction, for example:
--   select set_config('request.jwt.claim.sub', '<an Owner''s id>', true),
--          set_config('request.jwt.claim.role', 'authenticated', true),
--          set_config('request.jwt.claims', '{"sub":"<an Owner''s id>","role":"authenticated"}', true);
-- It refuses unless what it finds is what was read on production on 6 Nov 2026 (4
-- rows, 3,995 units), so a count that moved since is looked at first. Run again,
-- it refuses and changes nothing.
do $rm$
declare
  c_rows constant int := 4;
  c_units constant bigint := 3995;
  c_reason constant text := 'A service holds no stock: this was typed in only so that it could be sold on an invoice';
  v_rows int; v_units bigint; v_moves bigint; r record; a jsonb; q jsonb; n int := 0;
begin
  if coalesce(current_setting('request.jwt.claim.sub', true), '') = '' then
    raise exception '495 stock: set the recording account first'; end if;
  if to_regprocedure('public.product_is_service(uuid)') is null then
    raise exception '495 stock: 495 is not in'; end if;

  select count(*), coalesce(sum(x.q), 0) into v_rows, v_units
    from (select si.current_qty as q from public.store_inventory si
           where si.current_qty <> 0 and public.product_is_service(si.product_id)
          union all
          select wi.current_qty from public.warehouse_inventory wi
           where wi.current_qty <> 0 and public.product_is_service(wi.product_id)) x;
  if v_rows <> c_rows or v_units <> c_units then
    raise exception '495 stock: found % rows and % units on services, not % and %. Nothing changed.', v_rows, v_units, c_rows, c_units; end if;
  select count(*) into v_moves from public.stock_movements where movement_type = 'inventory_adjustment';

  -- One form per place, as the Adjustments page sends it: counted totals of 0.
  for r in
    select x.kind, x.place, jsonb_agg(jsonb_build_object('product_id', x.product_id, 'new_qty', 0) order by x.product_id) as lines
      from (select 'store' as kind, si.store_id as place, si.product_id from public.store_inventory si
             where si.current_qty <> 0 and public.product_is_service(si.product_id)
            union all
            select 'warehouse', wi.warehouse_id, wi.product_id from public.warehouse_inventory wi
             where wi.current_qty <> 0 and public.product_is_service(wi.product_id)) x
     group by x.kind, x.place order by x.kind, x.place
  loop
    a := public.request_inventory_adjustments(r.kind, r.place, r.lines, c_reason, '495',
           md5('495-remove-service-stock/' || r.kind || '/' || r.place::text)::uuid);
    for q in select e from jsonb_array_elements(a->'requests') e loop
      perform public.resolve_inventory_adjustment((q->>'request_id')::uuid, true, '495: a service holds no stock');
      n := n + 1;
    end loop;
  end loop;

  -- What it leaves: no stock on any service, and one movement per row.
  if n <> c_rows then raise exception '495 stock: % requests approved, not %', n, c_rows; end if;
  if exists (select 1 from public.store_inventory si where si.current_qty <> 0 and public.product_is_service(si.product_id))
     or exists (select 1 from public.warehouse_inventory wi where wi.current_qty <> 0 and public.product_is_service(wi.product_id)) then
    raise exception '495 stock: a service still holds stock'; end if;
  if (select count(*) from public.stock_movements where movement_type = 'inventory_adjustment') <> v_moves + c_rows then
    raise exception '495 stock: not one movement per row'; end if;
end $rm$;
