-- =====================================================================
-- ENERGIA — TRANSFER REVIEW REWORK + MANUAL / NON-INVENTORY ITEMS
--
-- Authoritative transfer change after migration 158.
-- Preserves the Phase 11 two-step lifecycle and the Phase 54-56 multi-source
-- behaviour while fixing deferred-source reservations, atomic review/dispatch,
-- owner approval adjustments, approver-added products, and manual items.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Transfer line shape: catalogue product OR transfer-only manual item.
-- ---------------------------------------------------------------------
alter table public.transfer_request_lines alter column product_id drop not null;
alter table public.transfer_request_lines add column if not exists line_kind text not null default 'product';
alter table public.transfer_request_lines add column if not exists manual_item_name text;
alter table public.transfer_request_lines add column if not exists manual_uom text;
alter table public.transfer_request_lines add column if not exists added_by_approver boolean not null default false;
alter table public.transfer_request_lines add column if not exists added_by uuid references public.profiles(id);

update public.transfer_request_lines
   set line_kind = 'product'
 where line_kind is null or line_kind not in ('product','manual');

alter table public.transfer_request_lines drop constraint if exists transfer_request_lines_line_kind_check;
alter table public.transfer_request_lines drop constraint if exists transfer_request_lines_product_or_manual_check;
alter table public.transfer_request_lines
  add constraint transfer_request_lines_line_kind_check
  check (line_kind in ('product','manual'));
alter table public.transfer_request_lines
  add constraint transfer_request_lines_product_or_manual_check
  check (
    (line_kind = 'product'
      and product_id is not null
      and nullif(btrim(coalesce(manual_item_name,'')), '') is null)
    or
    (line_kind = 'manual'
      and product_id is null
      and nullif(btrim(coalesce(manual_item_name,'')), '') is not null
      and nullif(btrim(coalesce(manual_uom,'')), '') is not null)
  );

create index if not exists idx_transfer_lines_product
  on public.transfer_request_lines(transfer_request_id, product_id)
  where line_kind = 'product' and product_id is not null;

-- Link new transfer stock movements to the exact transfer/line. Historical
-- movements remain nullable and are handled by the legacy drift report.
alter table public.stock_movements add column if not exists transfer_request_id uuid references public.transfer_requests(id);
alter table public.stock_movements add column if not exists transfer_request_line_id uuid references public.transfer_request_lines(id);
create index if not exists idx_stock_movements_transfer_request on public.stock_movements(transfer_request_id);
create index if not exists idx_stock_movements_transfer_line on public.stock_movements(transfer_request_line_id);

-- ---------------------------------------------------------------------
-- 2. Correct availability. Unsourced demand is NOT a reservation.
--    The 4-arg overload lets review/edit exclude the transfer being worked on.
-- ---------------------------------------------------------------------
create or replace function public.location_available_qty(
  p_location_type public.location_type,
  p_location_id uuid,
  p_product_id uuid,
  p_exclude_request_id uuid)
returns table(on_hand integer, reserved integer, available integer)
language sql stable security definer set search_path = public as $function$
  with hand as (
    select case when p_location_type = 'warehouse'
      then coalesce((select wi.current_qty from public.warehouse_inventory wi
                      where wi.warehouse_id = p_location_id and wi.product_id = p_product_id), 0)
      else coalesce((select si.current_qty from public.store_inventory si
                      where si.store_id = p_location_id and si.product_id = p_product_id), 0)
    end::integer as q
  ),
  claimed as (
    select coalesce(sum(
      case
        -- If a pending line has explicit source allocations, only those exact
        -- allocations reserve stock at their exact locations.
        when exists (select 1 from public.transfer_line_sources tsa where tsa.line_id = l.id)
          then coalesce((select sum(ts.quantity)
                           from public.transfer_line_sources ts
                          where ts.line_id = l.id
                            and ts.source_type = p_location_type
                            and ts.source_id = p_location_id), 0)
        -- Otherwise a sourced pending request reserves its requested quantity
        -- only at its header source.
        when r.source_type = p_location_type and r.source_id = p_location_id
          then l.quantity
        -- A deferred / unsourced request is unallocated demand and reserves 0.
        else 0
      end), 0)::integer as q
      from public.transfer_request_lines l
      join public.transfer_requests r on r.id = l.transfer_request_id
     where r.status = 'pending'
       and l.line_kind = 'product'
       and l.product_id = p_product_id
       and (p_exclude_request_id is null or r.id <> p_exclude_request_id)
  )
  select h.q,
         c.q,
         greatest(h.q - c.q, 0)::integer
    from hand h cross join claimed c
$function$;

-- Keep the established 3-argument API for special-product and other callers.
create or replace function public.location_available_qty(
  p_location_type public.location_type, p_location_id uuid, p_product_id uuid)
returns table(on_hand integer, reserved integer, available integer)
language sql stable security definer set search_path = public as $function$
  select * from public.location_available_qty(p_location_type, p_location_id, p_product_id, null::uuid)
$function$;

-- ---------------------------------------------------------------------
-- 3. Review source data with real On Hand / Reserved / Available numbers.
-- ---------------------------------------------------------------------
drop function if exists public.transfer_request_sourcing(uuid);
create or replace function public.transfer_request_sourcing(p_request_id uuid)
returns table(
  line_id uuid, product_id uuid, product_name text, product_sku text,
  requested integer, approved integer,
  source_type text, source_id uuid, source_name text,
  -- Legacy aliases kept so Phase 55 and any older clients that still read
  -- warehouse_id/warehouse_name continue to work for both warehouses/stores.
  warehouse_id uuid, warehouse_name text,
  on_hand integer, reserved integer, available integer, allocated integer)
language sql stable security definer set search_path = public as $function$
  select l.id, l.product_id, p.name as product_name, p.sku,
         l.quantity, coalesce(l.approved_quantity, l.quantity),
         'warehouse'::text, w.id, w.name as source_name, w.id, w.name,
         a.on_hand, a.reserved, a.available,
         coalesce((select sum(ts.quantity) from public.transfer_line_sources ts
                    where ts.line_id = l.id and ts.source_type = 'warehouse' and ts.source_id = w.id),0)::integer
    from public.transfer_request_lines l
    join public.transfer_requests r on r.id = l.transfer_request_id
    join public.products p on p.id = l.product_id
    join public.warehouses w on w.deleted_at is null and coalesce(w.is_active,true)
    cross join lateral public.location_available_qty('warehouse', w.id, l.product_id, p_request_id) a
   where l.transfer_request_id = p_request_id
     and l.line_kind = 'product'
     and not (r.dest_type = 'warehouse' and r.dest_id = w.id)
  union all
  select l.id, l.product_id, p.name as product_name, p.sku,
         l.quantity, coalesce(l.approved_quantity, l.quantity),
         'store'::text, s.id, s.name as source_name, s.id, s.name,
         a.on_hand, a.reserved, a.available,
         coalesce((select sum(ts.quantity) from public.transfer_line_sources ts
                    where ts.line_id = l.id and ts.source_type = 'store' and ts.source_id = s.id),0)::integer
    from public.transfer_request_lines l
    join public.transfer_requests r on r.id = l.transfer_request_id
    join public.products p on p.id = l.product_id
    join public.stores s on s.deleted_at is null and coalesce(s.is_active,true)
    cross join lateral public.location_available_qty('store', s.id, l.product_id, p_request_id) a
   where l.transfer_request_id = p_request_id
     and l.line_kind = 'product'
     and not (r.dest_type = 'store' and r.dest_id = s.id)
   order by product_name, available desc, source_name
$function$;

create or replace function public.transfer_product_sourcing(p_request_id uuid, p_product_id uuid)
returns table(
  source_type text, source_id uuid, source_name text,
  on_hand integer, reserved integer, available integer)
language sql stable security definer set search_path = public as $function$
  select 'warehouse'::text, w.id, w.name as source_name, a.on_hand, a.reserved, a.available
    from public.transfer_requests r
    join public.warehouses w on w.deleted_at is null and coalesce(w.is_active,true)
    cross join lateral public.location_available_qty('warehouse', w.id, p_product_id, p_request_id) a
   where r.id = p_request_id
     and not (r.dest_type = 'warehouse' and r.dest_id = w.id)
  union all
  select 'store'::text, s.id, s.name as source_name, a.on_hand, a.reserved, a.available
    from public.transfer_requests r
    join public.stores s on s.deleted_at is null and coalesce(s.is_active,true)
    cross join lateral public.location_available_qty('store', s.id, p_product_id, p_request_id) a
   where r.id = p_request_id
     and not (r.dest_type = 'store' and r.dest_id = s.id)
   order by available desc, source_name
$function$;

-- ---------------------------------------------------------------------
-- 4. Staff request creation: chosen assigned store + products + manual lines.
-- ---------------------------------------------------------------------
create or replace function public.create_staff_transfer_request(
  p_lines jsonb, p_note text default null, p_store_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  v_role public.user_role; v_store_id uuid; v_line jsonb; v_kind text;
  v_product_id uuid; v_qty integer; v_name text; v_uom text; v_request_id uuid;
  v_seen uuid[] := '{}'::uuid[];
begin
  v_role := public.current_user_role();
  if v_role is null then raise exception 'No profile found for current user'; end if;
  if v_role <> 'staff' then raise exception 'This request type is for Staff only'; end if;

  if p_store_id is not null then
    if not public.user_has_store_access(p_store_id) then raise exception 'You are not assigned to that store.'; end if;
    v_store_id := p_store_id;
  else
    v_store_id := public.my_assigned_store_id();
  end if;
  if v_store_id is null then
    raise exception 'You are not assigned to a store, so you cannot request a transfer. Ask an Owner or Manager to assign you.';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'At least one item line is required';
  end if;

  -- Validate everything before inserting the request.
  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_kind := coalesce(nullif(v_line->>'line_kind',''), case when nullif(v_line->>'product_id','') is null then 'manual' else 'product' end);
    v_qty := nullif(v_line->>'quantity','')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Each line quantity must be greater than zero'; end if;

    if v_kind = 'product' then
      v_product_id := nullif(v_line->>'product_id','')::uuid;
      if v_product_id is null or not exists (select 1 from public.products p where p.id=v_product_id and p.deleted_at is null and p.is_active) then
        raise exception 'Choose a valid active product';
      end if;
      if v_product_id = any(v_seen) then raise exception 'The same product cannot appear twice in one transfer'; end if;
      v_seen := array_append(v_seen, v_product_id);
      perform public.assert_transfer_prices_ok(v_store_id, array[v_product_id]);
    elsif v_kind = 'manual' then
      v_name := btrim(coalesce(v_line->>'manual_item_name',''));
      v_uom := btrim(coalesce(v_line->>'manual_uom',''));
      if v_name = '' then raise exception 'Manual item name is required'; end if;
      if v_uom = '' then raise exception 'Manual item unit/UOM is required'; end if;
    else
      raise exception 'Invalid transfer line kind: %', v_kind;
    end if;
  end loop;

  insert into public.transfer_requests
    (transfer_type, source_type, source_id, dest_type, dest_id, status, note, requested_by)
  values ('warehouse_to_store', null, null, 'store', v_store_id, 'pending', p_note, auth.uid())
  returning id into v_request_id;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_kind := coalesce(nullif(v_line->>'line_kind',''), case when nullif(v_line->>'product_id','') is null then 'manual' else 'product' end);
    v_qty := (v_line->>'quantity')::integer;
    insert into public.transfer_request_lines
      (transfer_request_id, line_kind, product_id, manual_item_name, manual_uom, quantity, added_by)
    values
      (v_request_id, v_kind,
       case when v_kind='product' then nullif(v_line->>'product_id','')::uuid end,
       case when v_kind='manual' then btrim(v_line->>'manual_item_name') end,
       case when v_kind='manual' then btrim(v_line->>'manual_uom') end,
       v_qty, auth.uid());
  end loop;

  perform public.write_audit_ex('transfer_requests', v_request_id, 'transfer_requested_by_staff', null,
    jsonb_build_object('dest_store',v_store_id,'source','deferred','lines',p_lines), 'transfers', p_note, v_store_id);
  return jsonb_build_object('success',true,'id',v_request_id);
end
$function$;

-- ---------------------------------------------------------------------
-- 5. Full sourced request creation, retaining existing role/store rules and
--    adding manual lines. Product stock uses AVAILABLE, not raw current_qty.
-- ---------------------------------------------------------------------
create or replace function public.create_transfer_request(
  p_transfer_type text, p_source_type text, p_source_id uuid,
  p_dest_type text, p_dest_id uuid, p_lines jsonb, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  v_role public.user_role; v_line jsonb; v_kind text; v_product_id uuid;
  v_qty integer; v_name text; v_uom text; v_av record; v_request_id uuid;
  v_src_type public.location_type; v_dst_type public.location_type;
  v_seen uuid[] := '{}'::uuid[];
begin
  v_role := public.current_user_role();
  if v_role is null then raise exception 'No profile found for current user'; end if;
  v_src_type := p_source_type::public.location_type;
  v_dst_type := p_dest_type::public.location_type;
  if p_source_id is null or p_dest_id is null then raise exception 'Source and destination are required'; end if;

  if v_role = 'staff' then
    if v_src_type='warehouse' and v_dst_type='warehouse' then raise exception 'Staff cannot request warehouse-to-warehouse transfers'; end if;
    if v_src_type='store' and not public.user_has_store_access(p_source_id) then raise exception 'Staff can only transfer from their assigned store'; end if;
    if v_dst_type='store' and not public.user_has_store_access(p_dest_id) then raise exception 'Staff can only transfer to their assigned store'; end if;
  end if;
  if v_src_type=v_dst_type and p_source_id=p_dest_id then raise exception 'Source and destination must be different'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'At least one item line is required'; end if;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_kind := coalesce(nullif(v_line->>'line_kind',''), case when nullif(v_line->>'product_id','') is null then 'manual' else 'product' end);
    v_qty := nullif(v_line->>'quantity','')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Each line quantity must be greater than zero'; end if;
    if v_kind='product' then
      v_product_id := nullif(v_line->>'product_id','')::uuid;
      if v_product_id is null or not exists(select 1 from public.products p where p.id=v_product_id and p.deleted_at is null and p.is_active) then raise exception 'Choose a valid active product'; end if;
      if v_product_id=any(v_seen) then raise exception 'The same product cannot appear twice in one transfer'; end if;
      v_seen := array_append(v_seen,v_product_id);
      select * into v_av from public.location_available_qty(v_src_type,p_source_id,v_product_id,null);
      if coalesce(v_av.available,0) < v_qty then
        raise exception 'Insufficient available stock at source for "%" (on hand %, reserved %, available %, need %)',
          (select name from public.products where id=v_product_id), coalesce(v_av.on_hand,0), coalesce(v_av.reserved,0), coalesce(v_av.available,0), v_qty;
      end if;
      if v_dst_type='store' then perform public.assert_transfer_prices_ok(p_dest_id,array[v_product_id]); end if;
    elsif v_kind='manual' then
      v_name := btrim(coalesce(v_line->>'manual_item_name','')); v_uom := btrim(coalesce(v_line->>'manual_uom',''));
      if v_name='' then raise exception 'Manual item name is required'; end if;
      if v_uom='' then raise exception 'Manual item unit/UOM is required'; end if;
    else raise exception 'Invalid transfer line kind: %',v_kind;
    end if;
  end loop;

  insert into public.transfer_requests(transfer_type,source_type,source_id,dest_type,dest_id,status,note,requested_by)
  values(p_transfer_type,v_src_type,p_source_id,v_dst_type,p_dest_id,'pending',p_note,auth.uid()) returning id into v_request_id;
  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_kind := coalesce(nullif(v_line->>'line_kind',''), case when nullif(v_line->>'product_id','') is null then 'manual' else 'product' end);
    insert into public.transfer_request_lines
      (transfer_request_id,line_kind,product_id,manual_item_name,manual_uom,quantity,added_by)
    values(v_request_id,v_kind,
      case when v_kind='product' then nullif(v_line->>'product_id','')::uuid end,
      case when v_kind='manual' then btrim(v_line->>'manual_item_name') end,
      case when v_kind='manual' then btrim(v_line->>'manual_uom') end,
      (v_line->>'quantity')::integer,auth.uid());
  end loop;
  perform public.write_audit_ex('transfer_requests',v_request_id,'transfer_requested',null,
    jsonb_build_object('transfer_type',p_transfer_type,'lines',p_lines),'transfers',p_note,
    case when v_dst_type='store' then p_dest_id end);
  return jsonb_build_object('success',true,'id',v_request_id);
end
$function$;

-- ---------------------------------------------------------------------
-- 6. Pending edit: manual lines supported; deferred-source edits skip stock.
-- ---------------------------------------------------------------------
create or replace function public.edit_transfer_request(
  p_transfer_id uuid, p_expected_version integer, p_reason text,
  p_source_type public.location_type default null, p_source_id uuid default null,
  p_dest_type public.location_type default null, p_dest_id uuid default null,
  p_lines jsonb default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  v_req public.transfer_requests%rowtype; v_role public.user_role;
  v_new_source_type public.location_type; v_new_source_id uuid;
  v_new_dest_type public.location_type; v_new_dest_id uuid;
  v_line jsonb; v_kind text; v_product_id uuid; v_qty integer;
  v_name text; v_uom text; v_av record; v_seen uuid[] := '{}'::uuid[];
  v_snapshot jsonb; v_summary jsonb := '{}'::jsonb;
begin
  v_role := public.current_user_role();
  if v_role is null then raise exception 'No profile found for current user'; end if;
  if coalesce(btrim(p_reason),'')='' then raise exception 'An edit reason is required'; end if;

  select * into v_req from public.transfer_requests where id=p_transfer_id for update;
  if not found then raise exception 'Transfer not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Only pending transfers can be edited (this one is %)',v_req.status; end if;
  if p_expected_version is not null and p_expected_version <> v_req.version then
    raise exception 'This transfer was changed by someone else (expected version %, current %). Please reload and try again.',p_expected_version,v_req.version;
  end if;
  if not public.is_owner_or_manager() and v_req.requested_by <> auth.uid() then raise exception 'You can only edit your own pending transfer requests'; end if;

  v_new_source_type := coalesce(p_source_type,v_req.source_type);
  v_new_source_id := coalesce(p_source_id,v_req.source_id);
  v_new_dest_type := coalesce(p_dest_type,v_req.dest_type);
  v_new_dest_id := coalesce(p_dest_id,v_req.dest_id);

  if not public.is_owner_or_manager() then
    if v_new_source_type is distinct from v_req.source_type or v_new_source_id is distinct from v_req.source_id
       or v_new_dest_type is distinct from v_req.dest_type or v_new_dest_id is distinct from v_req.dest_id then
      raise exception 'Only an Owner or Manager can change the source or destination of a transfer';
    end if;
  end if;
  if v_new_source_id is not null and v_new_source_type=v_new_dest_type and v_new_source_id=v_new_dest_id then raise exception 'Source and destination must be different'; end if;

  v_snapshot := jsonb_build_object(
    'source_type',v_req.source_type,'source_id',v_req.source_id,'dest_type',v_req.dest_type,'dest_id',v_req.dest_id,'note',v_req.note,
    'lines',coalesce((select jsonb_agg(jsonb_build_object(
      'id',l.id,'line_kind',l.line_kind,'product_id',l.product_id,'manual_item_name',l.manual_item_name,'manual_uom',l.manual_uom,'quantity',l.quantity))
      from public.transfer_request_lines l where l.transfer_request_id=p_transfer_id),'[]'::jsonb));

  if v_new_source_id is distinct from v_req.source_id or v_new_source_type is distinct from v_req.source_type then
    v_summary := v_summary || jsonb_build_object('source',jsonb_build_object('from',v_req.source_id,'to',v_new_source_id)); end if;
  if v_new_dest_id is distinct from v_req.dest_id or v_new_dest_type is distinct from v_req.dest_type then
    v_summary := v_summary || jsonb_build_object('dest',jsonb_build_object('from',v_req.dest_id,'to',v_new_dest_id)); end if;
  if coalesce(p_note,v_req.note) is distinct from v_req.note then
    v_summary := v_summary || jsonb_build_object('note',jsonb_build_object('from',v_req.note,'to',p_note)); end if;

  if p_lines is not null then
    if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'At least one item line is required'; end if;
    for v_line in select * from jsonb_array_elements(p_lines) loop
      v_kind := coalesce(nullif(v_line->>'line_kind',''),case when nullif(v_line->>'product_id','') is null then 'manual' else 'product' end);
      v_qty := nullif(v_line->>'quantity','')::integer;
      if v_qty is null or v_qty<=0 then raise exception 'Each line quantity must be greater than zero'; end if;
      if v_kind='product' then
        v_product_id := nullif(v_line->>'product_id','')::uuid;
        if v_product_id is null or not exists(select 1 from public.products p where p.id=v_product_id and p.deleted_at is null and p.is_active) then raise exception 'Choose a valid active product'; end if;
        if v_product_id=any(v_seen) then raise exception 'The same product cannot appear twice in one transfer'; end if;
        v_seen := array_append(v_seen,v_product_id);
        -- IMPORTANT: deferred Staff requests have no source. They are demand,
        -- not a reservation, so there is nothing to validate here.
        if v_new_source_id is not null and v_new_source_type is not null then
          select * into v_av from public.location_available_qty(v_new_source_type,v_new_source_id,v_product_id,p_transfer_id);
          if coalesce(v_av.available,0) < v_qty then
            raise exception 'Insufficient available stock at source for "%" (on hand %, reserved by other requests %, available %, need %)',
              (select name from public.products where id=v_product_id),coalesce(v_av.on_hand,0),coalesce(v_av.reserved,0),coalesce(v_av.available,0),v_qty;
          end if;
        end if;
        if v_new_dest_type='store' then perform public.assert_transfer_prices_ok(v_new_dest_id,array[v_product_id]); end if;
      elsif v_kind='manual' then
        v_name:=btrim(coalesce(v_line->>'manual_item_name','')); v_uom:=btrim(coalesce(v_line->>'manual_uom',''));
        if v_name='' then raise exception 'Manual item name is required'; end if;
        if v_uom='' then raise exception 'Manual item unit/UOM is required'; end if;
      else raise exception 'Invalid transfer line kind: %',v_kind;
      end if;
    end loop;

    v_summary := v_summary || jsonb_build_object('lines_changed',true);
    delete from public.transfer_request_lines where transfer_request_id=p_transfer_id;
    for v_line in select * from jsonb_array_elements(p_lines) loop
      v_kind := coalesce(nullif(v_line->>'line_kind',''),case when nullif(v_line->>'product_id','') is null then 'manual' else 'product' end);
      insert into public.transfer_request_lines(transfer_request_id,line_kind,product_id,manual_item_name,manual_uom,quantity,added_by)
      values(p_transfer_id,v_kind,
        case when v_kind='product' then nullif(v_line->>'product_id','')::uuid end,
        case when v_kind='manual' then btrim(v_line->>'manual_item_name') end,
        case when v_kind='manual' then btrim(v_line->>'manual_uom') end,
        (v_line->>'quantity')::integer,auth.uid());
    end loop;
  end if;

  insert into public.transfer_request_revisions(transfer_request_id,version,reason,changed_summary,snapshot,edited_by)
  values(p_transfer_id,v_req.version,p_reason,v_summary,v_snapshot,auth.uid());
  update public.transfer_requests set
    source_type=v_new_source_type,source_id=v_new_source_id,dest_type=v_new_dest_type,dest_id=v_new_dest_id,
    note=coalesce(p_note,note),version=version+1,edit_count=edit_count+1,edited_at=now(),edited_by=auth.uid()
  where id=p_transfer_id;
  perform public.write_audit_ex('transfer_requests',p_transfer_id,'transfer_edited',v_snapshot,v_summary,'transfers',p_reason,null);
  return jsonb_build_object('id',p_transfer_id,'new_version',v_req.version+1,'edit_count',v_req.edit_count+1);
end
$function$;

-- ---------------------------------------------------------------------
-- 7. Atomic Review + Dispatch. p_lines is authoritative review input:
--    [{line_id?, line_kind, product_id?, manual_item_name?, manual_uom?,
--      approved_quantity, sources:[{source_type,source_id,quantity}]}]
-- ---------------------------------------------------------------------
create or replace function public.review_and_dispatch_transfer(
  p_request_id uuid, p_lines jsonb, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  v_req public.transfer_requests%rowtype; v_entry jsonb; v_src record;
  v_line public.transfer_request_lines%rowtype; v_line_id uuid; v_kind text;
  v_product_id uuid; v_approved integer; v_existing_count integer; v_seen_count integer := 0;
  v_seen_lines uuid[] := '{}'::uuid[]; v_seen_products uuid[] := '{}'::uuid[];
  v_source_sum integer; v_av record; v_loc_name text; v_dst_wh uuid; v_dst_st uuid;
  v_first_type public.location_type; v_first_id uuid; v_partial boolean := false;
  v_units integer := 0; v_added integer := 0;
begin
  if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can review and dispatch transfers'; end if;
  select * into v_req from public.transfer_requests where id=p_request_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'This request is % and can no longer be approved',v_req.status; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' then raise exception 'Review lines are required'; end if;

  select count(*) into v_existing_count from public.transfer_request_lines where transfer_request_id=p_request_id;
  v_dst_wh := case when v_req.dest_type='warehouse' then v_req.dest_id end;
  v_dst_st := case when v_req.dest_type='store' then v_req.dest_id end;

  -- Pre-lock every referenced source inventory row in deterministic order. This
  -- prevents two competing approvals from both consuming the same units and
  -- reduces deadlock risk for multi-location approvals.
  for v_src in
    with entries as (
      select e,
             coalesce(nullif(e->>'product_id','')::uuid,l.product_id) as product_id,
             coalesce(nullif(e->>'line_kind',''),l.line_kind,'product') as line_kind
        from jsonb_array_elements(p_lines) e
        left join public.transfer_request_lines l
          on l.id = nullif(e->>'line_id','')::uuid and l.transfer_request_id=p_request_id
    ), srcs as (
      select en.product_id,en.line_kind,
             coalesce(nullif(s->>'source_type',''),'warehouse')::public.location_type as source_type,
             coalesce(nullif(s->>'source_id',''),nullif(s->>'warehouse_id',''))::uuid as source_id
        from entries en cross join lateral jsonb_array_elements(coalesce(en.e->'sources','[]'::jsonb)) s
    )
    select distinct product_id,source_type,source_id from srcs
     where line_kind='product' and product_id is not null and source_id is not null
     order by source_type,source_id,product_id
  loop
    if v_src.source_type='warehouse' then
      perform 1 from public.warehouse_inventory where warehouse_id=v_src.source_id and product_id=v_src.product_id for update;
    else
      perform 1 from public.store_inventory where store_id=v_src.source_id and product_id=v_src.product_id for update;
    end if;
  end loop;

  -- Replace any stale pending allocations for this request inside this same
  -- transaction. If anything below fails, this deletion rolls back too.
  delete from public.transfer_line_sources
   where line_id in (select id from public.transfer_request_lines where transfer_request_id=p_request_id);

  for v_entry in select * from jsonb_array_elements(p_lines) loop
    v_line_id := nullif(v_entry->>'line_id','')::uuid;
    if v_line_id is not null then
      if v_line_id=any(v_seen_lines) then raise exception 'A transfer line was submitted more than once'; end if;
      select * into v_line from public.transfer_request_lines where id=v_line_id and transfer_request_id=p_request_id for update;
      if not found then raise exception 'Line % does not belong to this request',v_line_id; end if;
      v_seen_lines:=array_append(v_seen_lines,v_line_id); v_seen_count:=v_seen_count+1;
      v_kind:=v_line.line_kind; v_product_id:=v_line.product_id;
      if v_kind='product' then
        if v_product_id=any(v_seen_products) then raise exception 'The same product cannot appear twice in one transfer'; end if;
        v_seen_products:=array_append(v_seen_products,v_product_id);
      end if;
    else
      v_kind:=coalesce(nullif(v_entry->>'line_kind',''),case when nullif(v_entry->>'product_id','') is null then 'manual' else 'product' end);
      v_approved:=coalesce(nullif(v_entry->>'approved_quantity','')::integer,nullif(v_entry->>'quantity','')::integer,0);
      if v_approved <= 0 then raise exception 'A line added during review must have an approved quantity greater than zero'; end if;
      if v_kind='product' then
        v_product_id:=nullif(v_entry->>'product_id','')::uuid;
        if v_product_id is null or not exists(select 1 from public.products p where p.id=v_product_id and p.deleted_at is null and p.is_active) then raise exception 'Choose a valid active product to add during review'; end if;
        if v_product_id=any(v_seen_products) or exists(select 1 from public.transfer_request_lines l where l.transfer_request_id=p_request_id and l.line_kind='product' and l.product_id=v_product_id) then
          raise exception 'The same product cannot appear twice in one transfer';
        end if;
        insert into public.transfer_request_lines(transfer_request_id,line_kind,product_id,quantity,approved_quantity,in_transit_quantity,added_by_approver,added_by)
        values(p_request_id,'product',v_product_id,v_approved,v_approved,v_approved,true,auth.uid()) returning * into v_line;
        v_seen_products:=array_append(v_seen_products,v_product_id);
      elsif v_kind='manual' then
        if btrim(coalesce(v_entry->>'manual_item_name',''))='' then raise exception 'Manual item name is required'; end if;
        if btrim(coalesce(v_entry->>'manual_uom',''))='' then raise exception 'Manual item unit/UOM is required'; end if;
        insert into public.transfer_request_lines(transfer_request_id,line_kind,product_id,manual_item_name,manual_uom,quantity,approved_quantity,in_transit_quantity,added_by_approver,added_by)
        values(p_request_id,'manual',null,btrim(v_entry->>'manual_item_name'),btrim(v_entry->>'manual_uom'),v_approved,v_approved,v_approved,true,auth.uid()) returning * into v_line;
        v_product_id:=null;
      else raise exception 'Invalid transfer line kind: %',v_kind;
      end if;
      v_line_id:=v_line.id; v_added:=v_added+1;
      perform public.write_audit_ex('transfer_request_lines',v_line_id,'transfer_line_added_during_review',null,
        jsonb_build_object('line_kind',v_kind,'product_id',v_product_id,'manual_item_name',v_line.manual_item_name,'approved_quantity',v_approved),
        'transfers',p_note,case when v_req.dest_type='store' then v_req.dest_id end);
    end if;

    v_approved:=coalesce(nullif(v_entry->>'approved_quantity','')::integer,nullif(v_entry->>'quantity','')::integer,v_line.quantity);
    if v_approved < 0 then raise exception 'Approved quantity cannot be negative'; end if;
    if not v_line.added_by_approver and v_approved < v_line.quantity then v_partial:=true; end if;

    if v_kind='manual' then
      -- Manual lines never allocate/deduct Product inventory.
      if exists(select 1 from jsonb_array_elements(coalesce(v_entry->'sources','[]'::jsonb)) s where coalesce(nullif(s->>'quantity','')::integer,0)>0) then
        raise exception 'Manual/non-inventory items cannot have warehouse/store stock allocations';
      end if;
      update public.transfer_request_lines set approved_quantity=v_approved,in_transit_quantity=v_approved where id=v_line_id;
      continue;
    end if;

    if v_req.dest_type='store' then perform public.assert_transfer_prices_ok(v_req.dest_id,array[v_product_id]); end if;

    v_source_sum:=0;
    for v_src in
      select coalesce(nullif(s->>'source_type',''),'warehouse')::public.location_type as source_type,
             coalesce(nullif(s->>'source_id',''),nullif(s->>'warehouse_id',''))::uuid as source_id,
             sum(coalesce(nullif(s->>'quantity','')::integer,0))::integer as quantity
        from jsonb_array_elements(coalesce(v_entry->'sources','[]'::jsonb)) s
       group by 1,2
       order by 1,2
    loop
      if coalesce(v_src.quantity,0)<=0 then continue; end if;
      if v_src.source_id is null then raise exception 'Every stock allocation needs a source location'; end if;
      if v_src.source_type=v_req.dest_type and v_src.source_id=v_req.dest_id then raise exception 'The destination cannot act as its own source'; end if;
      if v_src.source_type='warehouse' then
        if not exists(select 1 from public.warehouses w where w.id=v_src.source_id and w.deleted_at is null and coalesce(w.is_active,true)) then raise exception 'Invalid source warehouse'; end if;
        select name into v_loc_name from public.warehouses where id=v_src.source_id;
      else
        if not exists(select 1 from public.stores s where s.id=v_src.source_id and s.deleted_at is null and coalesce(s.is_active,true)) then raise exception 'Invalid source store'; end if;
        select name into v_loc_name from public.stores where id=v_src.source_id;
      end if;

      select * into v_av from public.location_available_qty(v_src.source_type,v_src.source_id,v_product_id,p_request_id);
      if coalesce(v_av.available,0) < v_src.quantity then
        raise exception 'Insufficient available stock for "%" at "%" (On Hand %, Reserved %, Available %, allocating %)',
          (select name from public.products where id=v_product_id),v_loc_name,coalesce(v_av.on_hand,0),coalesce(v_av.reserved,0),coalesce(v_av.available,0),v_src.quantity;
      end if;

      insert into public.transfer_line_sources(line_id,source_type,source_id,quantity,created_by)
      values(v_line_id,v_src.source_type,v_src.source_id,v_src.quantity,auth.uid());
      v_source_sum:=v_source_sum+v_src.quantity;
      if v_first_id is null then v_first_type:=v_src.source_type; v_first_id:=v_src.source_id; end if;
    end loop;

    if v_source_sum <> v_approved then
      raise exception 'Line "%" is approved for % but % is allocated across sources',
        (select name from public.products where id=v_product_id),v_approved,v_source_sum;
    end if;

    update public.transfer_request_lines set approved_quantity=v_approved,in_transit_quantity=v_approved where id=v_line_id;

    -- Dispatch one movement per actual source allocation. Destination remains
    -- untouched until receive_transfer().
    for v_src in select source_type,source_id,quantity from public.transfer_line_sources where line_id=v_line_id order by source_type,source_id loop
      if v_src.source_type='warehouse' then
        update public.warehouse_inventory set current_qty=current_qty-v_src.quantity,updated_at=now()
         where warehouse_id=v_src.source_id and product_id=v_product_id;
      else
        update public.store_inventory set current_qty=current_qty-v_src.quantity,updated_at=now()
         where store_id=v_src.source_id and product_id=v_product_id;
      end if;
      insert into public.stock_movements(
        product_id,movement_type,from_warehouse_id,to_warehouse_id,from_store_id,to_store_id,
        quantity,notes,created_by,transfer_request_id,transfer_request_line_id)
      values(v_product_id,'transfer_dispatch',
        case when v_src.source_type='warehouse' then v_src.source_id end,v_dst_wh,
        case when v_src.source_type='store' then v_src.source_id end,v_dst_st,
        v_src.quantity,coalesce(p_note,'Transfer dispatched — in transit')||' (source allocation)',auth.uid(),p_request_id,v_line_id);
      v_units:=v_units+v_src.quantity;
    end loop;
  end loop;

  if v_seen_count <> v_existing_count then
    raise exception 'Every existing transfer line must be included in the review (% of % supplied)',v_seen_count,v_existing_count;
  end if;

  update public.transfer_requests set
    status='in_transit'::public.approval_status,
    was_partial=v_partial,
    source_type=coalesce(v_req.source_type,v_first_type),
    source_id=coalesce(v_req.source_id,v_first_id),
    approved_by=auth.uid(),approved_at=now(),dispatched_at=now(),completed_at=null
  where id=p_request_id;

  perform public.write_audit_ex('transfer_requests',p_request_id,'transfer_reviewed_and_dispatched',null,
    jsonb_build_object('review_lines',p_lines,'units_dispatched',v_units,'added_during_review',v_added,'partial',v_partial),
    'transfers',p_note,coalesce(v_dst_st,v_dst_wh));
  return jsonb_build_object('success',true,'status','in_transit','units_dispatched',v_units,'added_during_review',v_added,'partial',v_partial);
end
$function$;

-- ---------------------------------------------------------------------
-- 8. Backward-compatible approval APIs now forward to the authoritative
--    atomic review function. They keep older app sessions/tests working.
-- ---------------------------------------------------------------------
create or replace function public.approve_transfer(
  p_request_id uuid, p_approved_lines jsonb, p_note text default null,
  p_source_warehouse_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare v_req public.transfer_requests%rowtype; v_l public.transfer_request_lines%rowtype;
  v_qty integer; v_payload jsonb := '[]'::jsonb; v_src_type public.location_type; v_src_id uuid;
begin
  select * into v_req from public.transfer_requests where id=p_request_id;
  if not found then raise exception 'Transfer request not found'; end if;
  v_src_type:=coalesce(v_req.source_type,'warehouse'::public.location_type);
  v_src_id:=coalesce(v_req.source_id,p_source_warehouse_id);
  for v_l in select * from public.transfer_request_lines where transfer_request_id=p_request_id order by created_at,id loop
    if v_l.line_kind='product' then
      select coalesce((e->>'quantity')::integer,v_l.quantity) into v_qty
        from jsonb_array_elements(coalesce(p_approved_lines,'[]'::jsonb)) e
       where nullif(e->>'product_id','')::uuid=v_l.product_id limit 1;
      v_qty:=coalesce(v_qty,v_l.quantity);
      if v_qty>0 and v_src_id is null then raise exception 'This request has no source yet — choose a source to approve it.'; end if;
      v_payload:=v_payload||jsonb_build_array(jsonb_build_object(
        'line_id',v_l.id,'line_kind','product','approved_quantity',v_qty,
        'sources',case when v_qty>0 then jsonb_build_array(jsonb_build_object('source_type',v_src_type,'source_id',v_src_id,'quantity',v_qty)) else '[]'::jsonb end));
    else
      v_payload:=v_payload||jsonb_build_array(jsonb_build_object(
        'line_id',v_l.id,'line_kind','manual','approved_quantity',v_l.quantity,'sources','[]'::jsonb));
    end if;
  end loop;
  return public.review_and_dispatch_transfer(p_request_id,v_payload,p_note);
end
$function$;

create or replace function public.approve_transfer_multi(
  p_request_id uuid, p_approved_lines jsonb default null, p_note text default null,
  p_source_warehouse_id uuid default null, p_line_sources jsonb default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare v_l public.transfer_request_lines%rowtype; v_qty integer; v_sources jsonb; v_payload jsonb:='[]'::jsonb;
  v_req public.transfer_requests%rowtype; v_default_type public.location_type; v_default_id uuid;
begin
  select * into v_req from public.transfer_requests where id=p_request_id;
  if not found then raise exception 'Transfer request not found'; end if;
  v_default_type:=coalesce(v_req.source_type,'warehouse'::public.location_type);
  v_default_id:=coalesce(v_req.source_id,p_source_warehouse_id);
  for v_l in select * from public.transfer_request_lines where transfer_request_id=p_request_id order by created_at,id loop
    if v_l.line_kind='product' then
      select (e->>'quantity')::integer into v_qty from jsonb_array_elements(coalesce(p_approved_lines,'[]'::jsonb)) e
       where nullif(e->>'product_id','')::uuid=v_l.product_id limit 1;
      v_qty:=coalesce(v_qty,v_l.quantity);
      select coalesce(jsonb_agg(jsonb_build_object(
        'source_type',coalesce(nullif(s->>'source_type',''),'warehouse'),
        'source_id',coalesce(nullif(s->>'source_id',''),nullif(s->>'warehouse_id','')),
        'quantity',coalesce((s->>'quantity')::integer,0))), '[]'::jsonb)
        into v_sources
        from jsonb_array_elements(coalesce((select e->'sources' from jsonb_array_elements(coalesce(p_line_sources,'[]'::jsonb)) e where nullif(e->>'line_id','')::uuid=v_l.id limit 1),'[]'::jsonb)) s;
      if jsonb_array_length(v_sources)=0 and v_qty>0 and v_default_id is not null then
        v_sources:=jsonb_build_array(jsonb_build_object('source_type',v_default_type,'source_id',v_default_id,'quantity',v_qty));
      end if;
      v_payload:=v_payload||jsonb_build_array(jsonb_build_object('line_id',v_l.id,'line_kind','product','approved_quantity',v_qty,'sources',v_sources));
    else
      v_payload:=v_payload||jsonb_build_array(jsonb_build_object('line_id',v_l.id,'line_kind','manual','approved_quantity',v_l.quantity,'sources','[]'::jsonb));
    end if;
  end loop;
  return public.review_and_dispatch_transfer(p_request_id,v_payload,p_note);
end
$function$;

-- ---------------------------------------------------------------------
-- 9. Receipt keyed by line_id (product_id fallback retained for old clients).
--    Manual lines record receipt/discrepancy only; no inventory or movement.
-- ---------------------------------------------------------------------
create or replace function public.receive_transfer(
  p_request_id uuid, p_lines jsonb default null, p_note text default null,
  p_confirm_all boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  v_req public.transfer_requests%rowtype; v_l public.transfer_request_lines%rowtype;
  v_actual integer; v_diff integer; v_any boolean:=false; v_reason text;
  v_dst_wh uuid; v_dst_st uuid;
begin
  select * into v_req from public.transfer_requests where id=p_request_id for update;
  if not found then raise exception 'Transfer not found'; end if;
  if v_req.status<>'in_transit' or v_req.received_at is not null then
    raise exception 'This transfer is not awaiting receipt (status %). Receipt can only be confirmed once.',v_req.status; end if;
  if auth.uid() is not null and not public.can_receive_transfer(p_request_id) then
    if v_req.dest_type='warehouse' then raise exception 'Warehouse receipts must be confirmed by an Owner or Manager';
    else raise exception 'You can only receive transfers into a store you are assigned to'; end if;
  end if;
  v_dst_wh:=case when v_req.dest_type='warehouse' then v_req.dest_id end;
  v_dst_st:=case when v_req.dest_type='store' then v_req.dest_id end;

  for v_l in select * from public.transfer_request_lines where transfer_request_id=p_request_id and coalesce(in_transit_quantity,0)>0 order by created_at,id loop
    if p_confirm_all then v_actual:=coalesce(v_l.in_transit_quantity,0); v_reason:=null;
    else
      select (e->>'received_quantity')::integer,e->>'reason' into v_actual,v_reason
        from jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) e
       where (nullif(e->>'line_id','')::uuid=v_l.id)
          or (v_l.product_id is not null and nullif(e->>'line_id','') is null and nullif(e->>'product_id','')::uuid=v_l.product_id)
       limit 1;
      if v_actual is null then raise exception 'A received quantity is required for every transfer line (missing line %).',v_l.id; end if;
    end if;
    if v_actual<0 then raise exception 'Received quantity cannot be negative'; end if;
    v_diff:=v_actual-coalesce(v_l.approved_quantity,v_l.in_transit_quantity,0);
    if v_diff<>0 then v_any:=true; end if;
    update public.transfer_request_lines set received_quantity=v_actual,discrepancy_quantity=v_diff,
      discrepancy_reason=case when v_diff<>0 then v_reason else null end where id=v_l.id;

    if v_l.line_kind='product' and v_actual>0 then
      if v_req.dest_type='warehouse' then
        insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values(v_req.dest_id,v_l.product_id,v_actual)
        on conflict(warehouse_id,product_id) do update set current_qty=public.warehouse_inventory.current_qty+v_actual,updated_at=now();
      else
        insert into public.store_inventory(store_id,product_id,current_qty) values(v_req.dest_id,v_l.product_id,v_actual)
        on conflict(store_id,product_id) do update set current_qty=public.store_inventory.current_qty+v_actual,updated_at=now();
      end if;
      insert into public.stock_movements(product_id,movement_type,to_warehouse_id,to_store_id,quantity,notes,created_by,transfer_request_id,transfer_request_line_id)
      values(v_l.product_id,'transfer_receipt',v_dst_wh,v_dst_st,v_actual,coalesce(p_note,'Transfer received'),auth.uid(),p_request_id,v_l.id);
    end if;
  end loop;
  if v_any and coalesce(btrim(p_note),'')='' then raise exception 'A mismatch reason is required when the received quantity differs from the approved quantity.'; end if;
  update public.transfer_requests set received_at=now(),received_by=auth.uid(),receipt_note=p_note,has_discrepancy=v_any,
    status=case when v_any then 'received_with_discrepancy' else 'received' end::public.approval_status,
    completed_at=case when v_any then null else now() end where id=p_request_id;
  perform public.write_audit_ex('transfer_requests',p_request_id,
    case when v_any then 'transfer_received_with_discrepancy' else 'transfer_received' end,null,
    jsonb_build_object('lines',p_lines,'confirm_all',p_confirm_all,'discrepancy',v_any),'transfers',p_note,coalesce(v_dst_st,v_dst_wh));
  return jsonb_build_object('success',true,'status',case when v_any then 'received_with_discrepancy' else 'received' end,'discrepancy',v_any);
end
$function$;

-- ---------------------------------------------------------------------
-- 10. Discrepancy resolution keyed by line_id. Manual items are acknowledgement
--     only and can never invoke inventory corrections.
-- ---------------------------------------------------------------------
create or replace function public.resolve_transfer_discrepancy(
  p_request_id uuid, p_resolutions jsonb, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  v_req public.transfer_requests%rowtype; v_e jsonb; v_l public.transfer_request_lines%rowtype;
  v_line_id uuid; v_res text; v_reason text; v_diff integer; v_mag integer; v_unresolved integer;
  v_src_wh uuid; v_dst_wh uuid; v_src_st uuid; v_dst_st uuid;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can resolve transfer discrepancies'; end if;
  select * into v_req from public.transfer_requests where id=p_request_id for update;
  if not found then raise exception 'Transfer not found'; end if;
  if v_req.status<>'received_with_discrepancy' then raise exception 'This transfer has no unresolved receipt discrepancy'; end if;
  v_src_wh:=case when v_req.source_type='warehouse' then v_req.source_id end;
  v_src_st:=case when v_req.source_type='store' then v_req.source_id end;
  v_dst_wh:=case when v_req.dest_type='warehouse' then v_req.dest_id end;
  v_dst_st:=case when v_req.dest_type='store' then v_req.dest_id end;

  for v_e in select * from jsonb_array_elements(coalesce(p_resolutions,'[]'::jsonb)) loop
    v_line_id:=nullif(v_e->>'line_id','')::uuid;
    if v_line_id is not null then
      select * into v_l from public.transfer_request_lines where id=v_line_id and transfer_request_id=p_request_id for update;
    else
      select * into v_l from public.transfer_request_lines where transfer_request_id=p_request_id and product_id=nullif(v_e->>'product_id','')::uuid for update;
    end if;
    if not found then raise exception 'Transfer discrepancy line not found'; end if;
    if coalesce(v_l.discrepancy_quantity,0)=0 or v_l.discrepancy_resolved_at is not null then continue; end if;
    v_res:=coalesce(nullif(v_e->>'resolution',''),'other'); v_reason:=nullif(btrim(coalesce(v_e->>'reason','')),'');
    if v_res='other' and v_reason is null then raise exception 'A reason is required for an Other resolution'; end if;
    v_diff:=v_l.discrepancy_quantity; v_mag:=abs(v_diff);

    if v_l.line_kind='manual' then
      if v_res not in ('accept_loss','accept_surplus','other') then
        raise exception 'Manual/non-inventory discrepancies are acknowledgement-only and cannot change inventory';
      end if;
    elsif v_res='return_excess' then
      if v_diff<=0 then raise exception 'Return excess applies only when more was received than approved'; end if;
      if v_req.dest_type='warehouse' then update public.warehouse_inventory set current_qty=current_qty-v_mag,updated_at=now() where warehouse_id=v_req.dest_id and product_id=v_l.product_id;
      else update public.store_inventory set current_qty=current_qty-v_mag,updated_at=now() where store_id=v_req.dest_id and product_id=v_l.product_id; end if;
      if v_req.source_id is not null then
        if v_req.source_type='warehouse' then insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values(v_req.source_id,v_l.product_id,v_mag)
          on conflict(warehouse_id,product_id) do update set current_qty=public.warehouse_inventory.current_qty+v_mag,updated_at=now();
        else insert into public.store_inventory(store_id,product_id,current_qty) values(v_req.source_id,v_l.product_id,v_mag)
          on conflict(store_id,product_id) do update set current_qty=public.store_inventory.current_qty+v_mag,updated_at=now(); end if;
        insert into public.stock_movements(product_id,movement_type,from_warehouse_id,to_warehouse_id,from_store_id,to_store_id,quantity,notes,created_by,transfer_request_id,transfer_request_line_id)
        values(v_l.product_id,'transfer_discrepancy',v_dst_wh,v_src_wh,v_dst_st,v_src_st,v_mag,'Discrepancy: returned excess to source',auth.uid(),p_request_id,v_l.id);
      end if;
    elsif v_res='correct_source' then
      if v_req.source_id is null then raise exception 'Cannot correct source inventory because this transfer has no single header source; use an acknowledgement or explicit inventory adjustment instead'; end if;
      if v_diff<0 then
        if v_req.source_type='warehouse' then insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values(v_req.source_id,v_l.product_id,v_mag)
          on conflict(warehouse_id,product_id) do update set current_qty=public.warehouse_inventory.current_qty+v_mag,updated_at=now();
        else insert into public.store_inventory(store_id,product_id,current_qty) values(v_req.source_id,v_l.product_id,v_mag)
          on conflict(store_id,product_id) do update set current_qty=public.store_inventory.current_qty+v_mag,updated_at=now(); end if;
      else
        if v_req.source_type='warehouse' then update public.warehouse_inventory set current_qty=current_qty-v_mag,updated_at=now() where warehouse_id=v_req.source_id and product_id=v_l.product_id;
        else update public.store_inventory set current_qty=current_qty-v_mag,updated_at=now() where store_id=v_req.source_id and product_id=v_l.product_id; end if;
      end if;
      insert into public.stock_movements(product_id,movement_type,from_warehouse_id,to_warehouse_id,from_store_id,to_store_id,quantity,notes,created_by,transfer_request_id,transfer_request_line_id)
      values(v_l.product_id,'transfer_discrepancy',v_src_wh,v_dst_wh,v_src_st,v_dst_st,v_mag,'Discrepancy: corrected source',auth.uid(),p_request_id,v_l.id);
    elsif v_res='correct_destination' then
      if v_diff>0 then
        if v_req.dest_type='warehouse' then update public.warehouse_inventory set current_qty=current_qty-v_mag,updated_at=now() where warehouse_id=v_req.dest_id and product_id=v_l.product_id;
        else update public.store_inventory set current_qty=current_qty-v_mag,updated_at=now() where store_id=v_req.dest_id and product_id=v_l.product_id; end if;
      else
        if v_req.dest_type='warehouse' then insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values(v_req.dest_id,v_l.product_id,v_mag)
          on conflict(warehouse_id,product_id) do update set current_qty=public.warehouse_inventory.current_qty+v_mag,updated_at=now();
        else insert into public.store_inventory(store_id,product_id,current_qty) values(v_req.dest_id,v_l.product_id,v_mag)
          on conflict(store_id,product_id) do update set current_qty=public.store_inventory.current_qty+v_mag,updated_at=now(); end if;
      end if;
      insert into public.stock_movements(product_id,movement_type,to_warehouse_id,to_store_id,quantity,notes,created_by,transfer_request_id,transfer_request_line_id)
      values(v_l.product_id,'transfer_discrepancy',v_dst_wh,v_dst_st,v_mag,'Discrepancy: corrected destination to approved qty',auth.uid(),p_request_id,v_l.id);
    elsif v_res='inventory_adjustment' then
      if v_diff<0 then
        if v_req.dest_type='warehouse' then insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values(v_req.dest_id,v_l.product_id,v_mag)
          on conflict(warehouse_id,product_id) do update set current_qty=public.warehouse_inventory.current_qty+v_mag,updated_at=now();
        else insert into public.store_inventory(store_id,product_id,current_qty) values(v_req.dest_id,v_l.product_id,v_mag)
          on conflict(store_id,product_id) do update set current_qty=public.store_inventory.current_qty+v_mag,updated_at=now(); end if;
      end if;
      insert into public.stock_movements(product_id,movement_type,to_warehouse_id,to_store_id,quantity,notes,created_by,transfer_request_id,transfer_request_line_id)
      values(v_l.product_id,'inventory_adjustment',v_dst_wh,v_dst_st,v_mag,'Discrepancy: linked inventory adjustment ('||coalesce(v_reason,'no note')||')',auth.uid(),p_request_id,v_l.id);
    elsif v_res in ('accept_loss','accept_surplus','other') then null;
    else raise exception 'Unknown discrepancy resolution: %',v_res;
    end if;

    update public.transfer_request_lines set discrepancy_resolution=v_res,discrepancy_reason=coalesce(v_reason,discrepancy_reason),discrepancy_resolved_at=now() where id=v_l.id;
    perform public.write_audit_ex('transfer_request_lines',v_l.id,'transfer_discrepancy_resolved',jsonb_build_object('discrepancy',v_diff),
      jsonb_build_object('resolution',v_res,'reason',v_reason,'manual',v_l.line_kind='manual'),'transfers',coalesce(v_reason,p_note),coalesce(v_dst_st,v_src_st));
  end loop;

  select count(*) into v_unresolved from public.transfer_request_lines where transfer_request_id=p_request_id and coalesce(discrepancy_quantity,0)<>0 and discrepancy_resolved_at is null;
  if v_unresolved=0 then
    update public.transfer_requests set discrepancy_resolved=true,status='completed'::public.approval_status,completed_at=now() where id=p_request_id;
    perform public.write_audit_ex('transfer_requests',p_request_id,'transfer_discrepancy_all_resolved',null,jsonb_build_object('resolved',true),'transfers',p_note,coalesce(v_dst_st,v_src_st));
  end if;
  return jsonb_build_object('success',true,'completed',v_unresolved=0,'remaining',v_unresolved);
end
$function$;

-- ---------------------------------------------------------------------
-- 11. Stock-integrity preview. Read-only; never changes live stock.
-- ---------------------------------------------------------------------
create or replace function public.report_transfer_stock_integrity()
returns table(
  issue_type text, severity text, request_id uuid, line_id uuid, product_id uuid,
  location_type text, location_id uuid, expected_qty integer, actual_qty integer, details text)
language sql stable security definer set search_path = public as $function$
  with line_base as (
    select r.id request_id,r.status,r.dispatched_at,r.received_at,l.id line_id,l.line_kind,l.product_id,
           l.quantity,l.approved_quantity,l.in_transit_quantity,l.received_quantity,
           coalesce((select sum(ts.quantity) from public.transfer_line_sources ts where ts.line_id=l.id),0)::integer allocated
      from public.transfer_requests r join public.transfer_request_lines l on l.transfer_request_id=r.id
  ), linked_dispatch as (
    select sm.transfer_request_line_id line_id,sum(sm.quantity)::integer qty
      from public.stock_movements sm where sm.movement_type='transfer_dispatch' and sm.transfer_request_line_id is not null group by sm.transfer_request_line_id
  ), linked_receipt as (
    select sm.transfer_request_line_id line_id,sum(sm.quantity)::integer qty
      from public.stock_movements sm where sm.movement_type='transfer_receipt' and sm.transfer_request_line_id is not null group by sm.transfer_request_line_id
  )
  select 'approved_vs_in_transit_mismatch','error',b.request_id,b.line_id,b.product_id,null,null,
         coalesce(b.approved_quantity,0),coalesce(b.in_transit_quantity,0),'Approved quantity does not match in-transit quantity.'
    from line_base b where b.status in ('in_transit','received','received_with_discrepancy','completed') and coalesce(b.approved_quantity,0)<>coalesce(b.in_transit_quantity,0)
  union all
  select 'allocation_vs_in_transit_mismatch','error',b.request_id,b.line_id,b.product_id,null,null,
         coalesce(b.in_transit_quantity,0),b.allocated,'Source allocation total does not match dispatched/in-transit total.'
    from line_base b where b.line_kind='product' and b.status in ('in_transit','received','received_with_discrepancy','completed') and b.allocated<>coalesce(b.in_transit_quantity,0)
  union all
  select 'dispatch_movement_mismatch','error',b.request_id,b.line_id,b.product_id,null,null,
         b.allocated,coalesce(d.qty,0),'Linked transfer-dispatch movements do not match source allocations.'
    from line_base b left join linked_dispatch d on d.line_id=b.line_id
   where b.line_kind='product' and d.line_id is not null and b.allocated<>coalesce(d.qty,0)
  union all
  select 'duplicate_or_excess_dispatch','error',b.request_id,b.line_id,b.product_id,null,null,
         b.allocated,d.qty,'More stock was recorded as dispatched than allocated; possible duplicate deduction.'
    from line_base b join linked_dispatch d on d.line_id=b.line_id where b.line_kind='product' and d.qty>b.allocated
  union all
  select 'receipt_movement_mismatch','error',b.request_id,b.line_id,b.product_id,null,null,
         coalesce(b.received_quantity,0),coalesce(rr.qty,0),'Linked receipt movement does not match received quantity.'
    from line_base b left join linked_receipt rr on rr.line_id=b.line_id
   where b.line_kind='product' and rr.line_id is not null and coalesce(b.received_quantity,0)<>coalesce(rr.qty,0)
  union all
  select 'stranded_in_transit','error',b.request_id,b.line_id,b.product_id,null,null,
         coalesce(b.approved_quantity,0),coalesce(b.in_transit_quantity,0),'Approved stock has no in-transit quantity and may be stranded.'
    from line_base b where b.status in ('approved','in_transit') and coalesce(b.approved_quantity,0)>0 and coalesce(b.in_transit_quantity,0)=0
  union all
  select 'pending_unallocated_demand','info',r.id,l.id,l.product_id,null,null,0,0,
         'Deferred pending request has no source allocation. Correct reservation is zero at every location.'
    from public.transfer_requests r join public.transfer_request_lines l on l.transfer_request_id=r.id
   where r.status='pending' and r.source_id is null and l.line_kind='product'
     and not exists(select 1 from public.transfer_line_sources ts where ts.line_id=l.id)
  union all
  select 'negative_warehouse_inventory','critical',null,null,wi.product_id,'warehouse',wi.warehouse_id,0,wi.current_qty,'Warehouse inventory is negative.'
    from public.warehouse_inventory wi where wi.current_qty<0
  union all
  select 'negative_store_inventory','critical',null,null,si.product_id,'store',si.store_id,0,si.current_qty,'Store inventory is negative.'
    from public.store_inventory si where si.current_qty<0
  union all
  select 'historical_multi_source_drift','error',d.request_id,null,d.product_id,'warehouse',d.warehouse_id,
         d.should_have_given,d.actually_recorded,'Historical allocation/movement mismatch from the legacy multi-source path.'
    from public.report_multi_source_stock_drift() d
$function$;

-- ---------------------------------------------------------------------
-- 12. Tighten direct writes: transfer mutations must go through audited RPCs.
--     SELECT visibility is unchanged. SECURITY DEFINER functions above remain
--     authoritative and enforce requester/role rules server-side.
-- ---------------------------------------------------------------------
drop policy if exists "insert transfer requests" on public.transfer_requests;
drop policy if exists "update transfer requests" on public.transfer_requests;
drop policy if exists "write transfer request lines" on public.transfer_request_lines;

-- Keep explicit read policies from earlier migrations; no new permissive write
-- policy is introduced here.

notify pgrst, 'reload schema';
