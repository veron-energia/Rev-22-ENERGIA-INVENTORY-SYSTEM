-- =====================================================================
-- ENERGIA — STOCK MAY SHIP FROM A STORE, NOT ONLY A WAREHOUSE
--
-- Two flows could only take stock out of a warehouse:
--
--   1. RELEASING a special sale or rental. fulfil_special_doc() deducted from
--      warehouse_inventory only, so a machine sitting in a shop could not be
--      handed over without first transferring it.
--
--   2. APPROVING a transfer. transfer_request_sourcing() cross-joined
--      warehouses alone, and approve_transfer_multi() wrote
--      source_type = 'warehouse' and deducted from warehouse_inventory — even
--      though transfer_line_sources has always had a source_type column ready
--      for it.
--
-- Both now accept a store as the source. What is deliberately preserved:
--
--   * PENDING transfer requests still hold stock back, at a store exactly as at
--     a warehouse, so the last unit cannot be released from under a request;
--   * a store cannot ship to ITSELF;
--   * every movement is still recorded with the correct from-location, so Stock
--     History shows where the goods actually came from.
--
-- Additive and idempotent. Run AFTER 116.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Availability at any location, honouring pending transfer claims.
-- ---------------------------------------------------------------------
create or replace function public.location_available_qty(
  p_location_type public.location_type, p_location_id uuid, p_product_id uuid)
returns table(on_hand integer, reserved integer, available integer)
language sql stable security definer set search_path to 'public' as $function$
  with hand as (
    select case when p_location_type = 'warehouse'
      then coalesce((select wi.current_qty from public.warehouse_inventory wi
                      where wi.warehouse_id = p_location_id and wi.product_id = p_product_id), 0)
      else coalesce((select si.current_qty from public.store_inventory si
                      where si.store_id = p_location_id and si.product_id = p_product_id), 0)
    end::integer as q
  ),
  claimed as (
    -- Pending requests already sourced from here, plus deferred requests that
    -- have not had a source picked yet: both are real claims on this stock.
    select coalesce(sum(l.quantity), 0)::integer as q
      from public.transfer_request_lines l
      join public.transfer_requests r on r.id = l.transfer_request_id
     where r.status = 'pending'
       and l.product_id = p_product_id
       and ((r.source_type = p_location_type and r.source_id = p_location_id)
            or exists (select 1 from public.transfer_line_sources ts
                        where ts.line_id = l.id
                          and ts.source_type = p_location_type
                          and ts.source_id = p_location_id)
            or (r.source_id is null
                and not exists (select 1 from public.transfer_line_sources ts2
                                 where ts2.line_id = l.id)))
  )
  select coalesce((select q from hand), 0),
         coalesce((select q from claimed), 0),
         greatest(coalesce((select q from hand), 0) - coalesce((select q from claimed), 0), 0)
$function$;

-- ---------------------------------------------------------------------
-- 2. Where a special product can be released from — warehouses AND stores.
-- ---------------------------------------------------------------------
-- The shape changes (a location_type column is added), so the old one goes first.
drop function if exists public.special_product_availability(uuid);

create or replace function public.special_product_availability(p_special_product_id uuid)
returns table(location_type text, warehouse_id uuid, warehouse_name text,
              on_hand integer, reserved integer, available integer)
language sql stable security definer set search_path to 'public' as $function$
  select 'warehouse', w.id, w.name, a.on_hand, a.reserved, a.available
    from public.warehouses w
    join public.special_products sp on sp.id = p_special_product_id
    cross join lateral public.location_available_qty('warehouse', w.id, sp.product_id) a
   where w.deleted_at is null
  union all
  select 'store', s.id, s.name, a.on_hand, a.reserved, a.available
    from public.stores s
    join public.special_products sp on sp.id = p_special_product_id
    cross join lateral public.location_available_qty('store', s.id, sp.product_id) a
   where s.deleted_at is null
   order by 6 desc, 3
$function$;

-- ---------------------------------------------------------------------
-- 2b. Where a released document came FROM.
--
--     rentals.warehouse_id and special_sales.warehouse_id have a foreign key to
--     warehouses, so a store id cannot be stored there. Rather than weaken that
--     constraint, the source is recorded in its own pair of columns and
--     warehouse_id is left for warehouse releases only — so existing reports
--     and joins that read warehouse_id keep working unchanged.
-- ---------------------------------------------------------------------
alter table public.rentals add column if not exists source_type public.location_type;
alter table public.rentals add column if not exists source_store_id uuid references public.stores(id);
alter table public.special_sales add column if not exists source_type public.location_type;
alter table public.special_sales add column if not exists source_store_id uuid references public.stores(id);

-- Anything already released came from a warehouse.
update public.rentals set source_type = 'warehouse'
 where warehouse_id is not null and source_type is null;
update public.special_sales set source_type = 'warehouse'
 where warehouse_id is not null and source_type is null;

-- ---------------------------------------------------------------------
-- 3. Release from a warehouse OR a store.
-- ---------------------------------------------------------------------
create or replace function public.fulfil_special_doc(
  p_doc_kind text, p_doc_id uuid, p_warehouse_id uuid,
  p_location_type public.location_type)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_sp uuid; v_qty integer; v_no text; v_prod uuid; v_name text;
  v_avail record; v_loc_name text;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can choose where stock is released from'; end if;
  if p_warehouse_id is null then raise exception 'Choose where the stock comes from'; end if;

  if p_location_type = 'warehouse' then
    select name into v_loc_name from public.warehouses
     where id = p_warehouse_id and deleted_at is null;
    if v_loc_name is null then raise exception 'That warehouse does not exist'; end if;
  else
    select name into v_loc_name from public.stores
     where id = p_warehouse_id and deleted_at is null;
    if v_loc_name is null then raise exception 'That store does not exist'; end if;
  end if;

  if p_doc_kind = 'special_sale' then
    select special_product_id, quantity, sale_no into v_sp, v_qty, v_no
      from public.special_sales where id = p_doc_id
        and warehouse_id is null and source_store_id is null
        and status <> 'cancelled' for update;
    if v_sp is null then raise exception 'That sale is not awaiting a location'; end if;
  elsif p_doc_kind = 'rental' then
    select special_product_id, quantity, rental_no into v_sp, v_qty, v_no
      from public.rentals where id = p_doc_id
        and warehouse_id is null and source_store_id is null
        and status <> 'cancelled' for update;
    if v_sp is null then raise exception 'That rental is not awaiting a location'; end if;
  else
    raise exception 'Unknown document kind "%"', p_doc_kind;
  end if;

  select product_id into v_prod from public.special_products where id = v_sp;
  if v_prod is null then
    raise exception 'This special product is not linked to a warehouse product yet'; end if;
  v_name := public.special_product_name(v_sp);

  select * into v_avail from public.location_available_qty(p_location_type, p_warehouse_id, v_prod);

  if v_avail.available < v_qty then
    if v_avail.on_hand >= v_qty then
      raise exception
        'Only % of "%" free at % (% on hand, % already claimed by pending transfer requests). Approve or reject those first.',
        v_avail.available, v_name, v_loc_name, v_avail.on_hand, v_avail.reserved;
    end if;
    raise exception 'Not enough "%" at %: % needed, % on hand',
      v_name, v_loc_name, v_qty, v_avail.on_hand;
  end if;

  if p_location_type = 'warehouse' then
    update public.warehouse_inventory
       set current_qty = current_qty - v_qty, updated_at = now()
     where warehouse_id = p_warehouse_id and product_id = v_prod;
    insert into public.stock_movements
      (product_id, movement_type, from_warehouse_id, quantity, notes, created_by)
    values (v_prod, 'store_sale'::stock_movement_type, p_warehouse_id, v_qty,
      case when p_doc_kind = 'rental' then 'Rental released — ' else 'Special sale released — ' end || v_no,
      auth.uid());
  else
    update public.store_inventory
       set current_qty = current_qty - v_qty, updated_at = now()
     where store_id = p_warehouse_id and product_id = v_prod;
    insert into public.stock_movements
      (product_id, movement_type, from_store_id, quantity, notes, created_by)
    values (v_prod, 'store_sale'::stock_movement_type, p_warehouse_id, v_qty,
      case when p_doc_kind = 'rental' then 'Rental released — ' else 'Special sale released — ' end || v_no
        || ' (from store)',
      auth.uid());
  end if;

  -- warehouse_id carries the source id whichever kind it is; the movement
  -- above records which sort of location it actually was.
  if p_doc_kind = 'special_sale' then
    update public.special_sales
       set warehouse_id = case when p_location_type = 'warehouse' then p_warehouse_id end,
           source_store_id = case when p_location_type = 'store' then p_warehouse_id end,
           source_type = p_location_type,
           status = 'completed', fulfilled_at = now(), fulfilled_by = auth.uid()
     where id = p_doc_id;
  else
    update public.rentals
       set warehouse_id = case when p_location_type = 'warehouse' then p_warehouse_id end,
           source_store_id = case when p_location_type = 'store' then p_warehouse_id end,
           source_type = p_location_type,
           status = 'active', activated_at = now(),
           fulfilled_at = now(), fulfilled_by = auth.uid()
     where id = p_doc_id;
  end if;

  perform public.write_audit_ex(p_doc_kind, p_doc_id, 'special_doc_fulfilled', null,
    jsonb_build_object('location_type', p_location_type, 'location', p_warehouse_id,
      'location_name', v_loc_name, 'product', v_name, 'quantity', v_qty, 'doc_no', v_no),
    'special', null, null);

  return jsonb_build_object('success', true, 'doc_no', v_no,
    'location_type', p_location_type, 'location_name', v_loc_name,
    'quantity', v_qty, 'product', v_name);
end $function$;

-- ---------------------------------------------------------------------
-- 4. Transfer sourcing may offer stores too.
-- ---------------------------------------------------------------------
drop function if exists public.transfer_request_sourcing(uuid);

create or replace function public.transfer_request_sourcing(p_request_id uuid)
returns table(line_id uuid, product_id uuid, product_name text, product_sku text,
              requested integer, approved integer,
              source_type text, warehouse_id uuid, warehouse_name text,
              available integer, allocated integer)
language sql stable security definer set search_path to 'public' as $function$
  select l.id, l.product_id, p.name, p.sku,
         l.quantity, coalesce(l.approved_quantity, l.quantity),
         'warehouse', w.id, w.name,
         a.available,
         coalesce((select sum(ts.quantity) from public.transfer_line_sources ts
                    where ts.line_id = l.id and ts.source_id = w.id
                      and ts.source_type = 'warehouse'), 0)::integer
    from public.transfer_request_lines l
    join public.transfer_requests r on r.id = l.transfer_request_id
    join public.products p on p.id = l.product_id
    cross join public.warehouses w
    cross join lateral public.location_available_qty('warehouse', w.id, l.product_id) a
   where l.transfer_request_id = p_request_id and w.deleted_at is null
  union all
  -- Stores may also be a source, except the one the goods are going to: a
  -- store cannot transfer stock to itself.
  select l.id, l.product_id, p.name, p.sku,
         l.quantity, coalesce(l.approved_quantity, l.quantity),
         'store', s.id, s.name,
         a.available,
         coalesce((select sum(ts.quantity) from public.transfer_line_sources ts
                    where ts.line_id = l.id and ts.source_id = s.id
                      and ts.source_type = 'store'), 0)::integer
    from public.transfer_request_lines l
    join public.transfer_requests r on r.id = l.transfer_request_id
    join public.products p on p.id = l.product_id
    cross join public.stores s
    cross join lateral public.location_available_qty('store', s.id, l.product_id) a
   where l.transfer_request_id = p_request_id
     and s.deleted_at is null
     and not (r.dest_type = 'store' and r.dest_id = s.id)
     and a.on_hand > 0        -- only stores that actually hold some
   order by 3, 10 desc, 9
$function$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- 5. Approval: validate, record and dispatch against the chosen SOURCE TYPE.
--
--    Three places assumed a warehouse: the availability check, the
--    transfer_line_sources insert, and the dispatch loop. Each is patched to
--    read the source type the approver actually chose.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'approve_transfer_multi';
  if v_def is null then raise exception 'approve_transfer_multi not found'; end if;
  if position('v_src_type' in v_def) > 0 then
    raise notice 'approve_transfer_multi already handles store sources'; return;
  end if;

  -- (a) Read the source type alongside the id, defaulting to warehouse so any
  --     caller that does not send one behaves exactly as before.
  v_new := replace(v_def,
    '      v_wh := (v_src->>''warehouse_id'')::uuid;',
    '      v_wh := (v_src->>''warehouse_id'')::uuid;' || chr(10) ||
    '      v_src_type := coalesce(nullif(v_src->>''source_type'',''''), ''warehouse'')::public.location_type;');

  -- (b) Check availability at whichever kind of location it is.
  v_new := replace(v_new,
    '      select coalesce(current_qty,0) into v_have from public.warehouse_inventory' || chr(10) ||
    '       where warehouse_id = v_wh and product_id = v_line.product_id for update;',
    '      if v_src_type = ''warehouse'' then' || chr(10) ||
    '        select coalesce(current_qty,0) into v_have from public.warehouse_inventory' || chr(10) ||
    '         where warehouse_id = v_wh and product_id = v_line.product_id for update;' || chr(10) ||
    '      else' || chr(10) ||
    '        select coalesce(current_qty,0) into v_have from public.store_inventory' || chr(10) ||
    '         where store_id = v_wh and product_id = v_line.product_id for update;' || chr(10) ||
    '      end if;');

  -- (c) Name the location correctly when reporting a shortfall.
  v_new := replace(v_new,
    '          || '' at '' || (select name from public.warehouses where id = v_wh)',
    '          || '' at '' || coalesce((select name from public.warehouses where id = v_wh),' || chr(10) ||
    '                                  (select name from public.stores where id = v_wh))');

  -- (d) Record the source with its real type.
  v_new := replace(v_new,
    '      values (v_line_id, ''warehouse'', v_wh, v_qty, auth.uid());',
    '      values (v_line_id, v_src_type, v_wh, v_qty, auth.uid());');

  -- (e) Dispatch from the right table, grouping by type as well as id.
  v_new := replace(v_new,
    '    select ts.source_id as warehouse_id, l.product_id, sum(ts.quantity)::integer as qty' || chr(10) ||
    '      from public.transfer_line_sources ts' || chr(10) ||
    '      join public.transfer_request_lines l on l.id = ts.line_id' || chr(10) ||
    '     where l.transfer_request_id = p_request_id' || chr(10) ||
    '     group by ts.source_id, l.product_id',
    '    select ts.source_id as warehouse_id, ts.source_type, l.product_id,' || chr(10) ||
    '           sum(ts.quantity)::integer as qty' || chr(10) ||
    '      from public.transfer_line_sources ts' || chr(10) ||
    '      join public.transfer_request_lines l on l.id = ts.line_id' || chr(10) ||
    '     where l.transfer_request_id = p_request_id' || chr(10) ||
    '     group by ts.source_id, ts.source_type, l.product_id');

  v_new := replace(v_new,
    '    update public.warehouse_inventory' || chr(10) ||
    '       set current_qty = current_qty - v_a.qty, updated_at = now()' || chr(10) ||
    '     where warehouse_id = v_a.warehouse_id and product_id = v_a.product_id;',
    '    if v_a.source_type = ''warehouse'' then' || chr(10) ||
    '      update public.warehouse_inventory' || chr(10) ||
    '         set current_qty = current_qty - v_a.qty, updated_at = now()' || chr(10) ||
    '       where warehouse_id = v_a.warehouse_id and product_id = v_a.product_id;' || chr(10) ||
    '    else' || chr(10) ||
    '      update public.store_inventory' || chr(10) ||
    '         set current_qty = current_qty - v_a.qty, updated_at = now()' || chr(10) ||
    '       where store_id = v_a.warehouse_id and product_id = v_a.product_id;' || chr(10) ||
    '    end if;');

  -- Declare the new variable.
  v_new := replace(v_new, 'v_short text[] := ''{}'';',
                          'v_short text[] := ''{}''; v_src_type public.location_type;');

  if position('v_src_type' in v_new) = 0 then
    raise exception 'Could not add store sourcing to approve_transfer_multi';
  end if;
  execute v_new;
  raise notice 'approve_transfer_multi can now dispatch from a store';
end $patch$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- 6. The waiting queue: "awaiting" now means no source of EITHER kind.
--    Without this, a document released from a store would keep appearing in
--    the queue as though it were still unfulfilled.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'special_docs_awaiting_fulfilment';
  if v_def is null then raise notice 'queue function not found'; return; end if;
  if position('source_store_id is null' in v_def) > 0 then
    raise notice 'the waiting queue already accounts for store releases'; return;
  end if;

  v_new := replace(v_def,
    'where s.warehouse_id is null and s.status <> ''cancelled''',
    'where s.warehouse_id is null and s.source_store_id is null and s.status <> ''cancelled''');
  v_new := replace(v_new,
    'where r.warehouse_id is null and r.status <> ''cancelled''',
    'where r.warehouse_id is null and r.source_store_id is null and r.status <> ''cancelled''');

  if position('source_store_id is null' in v_new) = 0 then
    raise exception 'Could not update the waiting queue';
  end if;
  execute v_new;
  raise notice 'the waiting queue now excludes documents released from a store';
end $patch$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- 7. The dispatch MOVEMENT must record a store source in from_store_id.
--    It wrote the source id into from_warehouse_id unconditionally, which a
--    foreign key rightly refused for a store.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'approve_transfer_multi';
  if v_def is null then raise exception 'approve_transfer_multi not found'; end if;
  if position('then v_a.warehouse_id end, v_dst_wh' in v_def) > 0 then
    raise notice 'the dispatch movement already handles a store source'; return;
  end if;

  v_new := replace(v_def,
    '    values (v_a.product_id, v_movement::stock_movement_type, v_a.warehouse_id, v_dst_wh,' || chr(10) ||
    '       null, v_dst_st, v_a.qty,' || chr(10) ||
    '       coalesce(p_note, ''Transfer dispatched — in transit'')' || chr(10) ||
    '         || '' (from '' || (select name from public.warehouses where id = v_a.warehouse_id) || '')'',',
    '    values (v_a.product_id, v_movement::stock_movement_type,' || chr(10) ||
    '       case when v_a.source_type = ''warehouse'' then v_a.warehouse_id end, v_dst_wh,' || chr(10) ||
    '       case when v_a.source_type = ''store'' then v_a.warehouse_id end, v_dst_st, v_a.qty,' || chr(10) ||
    '       coalesce(p_note, ''Transfer dispatched — in transit'')' || chr(10) ||
    '         || '' (from '' || coalesce(' || chr(10) ||
    '              (select name from public.warehouses where id = v_a.warehouse_id),' || chr(10) ||
    '              (select name from public.stores where id = v_a.warehouse_id)) || '')'',');

  if position('then v_a.warehouse_id end, v_dst_wh' in v_new) = 0 then
    raise exception 'Could not correct the dispatch movement';
  end if;
  execute v_new;
  raise notice 'the dispatch movement now records a store source correctly';
end $patch$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- 8. Keep the original three-argument form working.
--
--    Adding a defaulted fourth parameter did NOT preserve the old signature:
--    PostgreSQL treats it as a different function, and a three-argument call
--    stopped resolving. Any caller still passing three arguments — including
--    a browser session running the previous build during a deploy — would
--    break. This overload forwards to the new one, defaulting to a warehouse.
-- ---------------------------------------------------------------------
create or replace function public.fulfil_special_doc(
  p_doc_kind text, p_doc_id uuid, p_warehouse_id uuid)
returns jsonb language sql security definer set search_path to 'public' as $function$
  select public.fulfil_special_doc(p_doc_kind, p_doc_id, p_warehouse_id, 'warehouse'::public.location_type)
$function$;

notify pgrst, 'reload schema';
