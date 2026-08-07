-- =====================================================================
-- ENERGIA — FIX: MULTI-WAREHOUSE APPROVAL DEDUCTED FROM ONE WAREHOUSE
--
-- Migration 97 recorded per-line warehouse allocations, but then delegated the
-- dispatch to approve_transfer(), which deducts the WHOLE approved quantity
-- from a single source. The allocations were therefore decorative: a transfer
-- approved as 5 from Second, 3 from Third and 2 from Main took all 10 out of
-- Main, and logged one movement from Main.
--
-- That is a stock-accuracy bug, not a cosmetic one — two warehouses were left
-- overstated and one understated. It is corrected here by performing the
-- dispatch directly from the allocations, so each warehouse gives up exactly
-- what it was allocated and each leg appears in Stock History.
--
-- A reconciliation report is included so any transfer already approved through
-- the broken path can be found and corrected.
--
-- Additive and idempotent. Run AFTER 97.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- Dispatch a request from its recorded per-line allocations.
--
-- Deliberately does NOT call approve_transfer(): that function's single-source
-- deduction is precisely what has to be replaced. The status change, the
-- partial flag and the audit entry follow the same shape it uses, so the rest
-- of the transfer lifecycle — receipt, discrepancies, reporting — is unchanged.
-- ---------------------------------------------------------------------
create or replace function public.approve_transfer_multi(
  p_request_id uuid,
  p_approved_lines jsonb default null,
  p_note text default null,
  p_source_warehouse_id uuid default null,
  p_line_sources jsonb default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_req public.transfer_requests%rowtype;
  v_entry jsonb; v_src jsonb; v_line public.transfer_request_lines%rowtype;
  v_line_id uuid; v_wh uuid; v_qty integer; v_sum integer; v_approved integer;
  v_have integer; v_short text[] := '{}'; v_used uuid[] := '{}';
  v_dst_wh uuid; v_dst_st uuid; v_movement text;
  v_is_partial boolean := false; v_a record; v_total integer := 0;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can approve a transfer'; end if;

  select * into v_req from public.transfer_requests where id = p_request_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if v_req.status <> 'pending' then
    raise exception 'This request is % and can no longer be approved', v_req.status; end if;

  -- No per-line sourcing: the original single-warehouse path is correct.
  if p_line_sources is null or jsonb_array_length(p_line_sources) = 0 then
    return public.approve_transfer(p_request_id, p_approved_lines, p_note, p_source_warehouse_id);
  end if;

  v_dst_wh := case when v_req.dest_type = 'warehouse' then v_req.dest_id end;
  v_dst_st := case when v_req.dest_type = 'store' then v_req.dest_id end;
  v_movement := case when v_req.dest_type = 'store' then 'warehouse_to_store'
                     else 'warehouse_to_warehouse' end;

  -- ---- 1. Apply the approved quantities, as approve_transfer would ----
  if p_approved_lines is not null then
    for v_entry in select * from jsonb_array_elements(p_approved_lines) loop
      update public.transfer_request_lines
         set approved_quantity = (v_entry->>'quantity')::integer
       where transfer_request_id = p_request_id
         and product_id = (v_entry->>'product_id')::uuid;
    end loop;
  end if;
  update public.transfer_request_lines
     set approved_quantity = coalesce(approved_quantity, quantity)
   where transfer_request_id = p_request_id;

  select bool_or(coalesce(approved_quantity, quantity) < quantity) into v_is_partial
    from public.transfer_request_lines where transfer_request_id = p_request_id;

  -- ---- 2. Record and validate the split ----
  for v_entry in select * from jsonb_array_elements(p_line_sources)
  loop
    v_line_id := (v_entry->>'line_id')::uuid;
    select * into v_line from public.transfer_request_lines
     where id = v_line_id and transfer_request_id = p_request_id;
    if not found then raise exception 'Line % does not belong to this request', v_line_id; end if;

    v_approved := coalesce(v_line.approved_quantity, v_line.quantity);
    v_sum := 0;
    delete from public.transfer_line_sources where line_id = v_line_id;

    for v_src in select * from jsonb_array_elements(coalesce(v_entry->'sources','[]'::jsonb))
    loop
      v_wh := (v_src->>'warehouse_id')::uuid;
      v_qty := coalesce((v_src->>'quantity')::integer, 0);
      if v_qty <= 0 then continue; end if;

      select coalesce(current_qty,0) into v_have from public.warehouse_inventory
       where warehouse_id = v_wh and product_id = v_line.product_id for update;
      if coalesce(v_have,0) < v_qty then
        v_short := array_append(v_short,
          (select name from public.products where id = v_line.product_id)
          || ' at ' || (select name from public.warehouses where id = v_wh)
          || ' (need ' || v_qty || ', have ' || coalesce(v_have,0) || ')');
      end if;

      insert into public.transfer_line_sources (line_id, source_type, source_id, quantity, created_by)
      values (v_line_id, 'warehouse', v_wh, v_qty, auth.uid());
      v_sum := v_sum + v_qty;
      if not (v_wh = any(v_used)) then v_used := array_append(v_used, v_wh); end if;
    end loop;

    if v_sum <> v_approved then
      raise exception 'Line "%" is approved for % but % was allocated across warehouses',
        (select name from public.products where id = v_line.product_id), v_approved, v_sum;
    end if;
  end loop;

  if array_length(v_short,1) is not null then
    raise exception 'Not enough stock: %', array_to_string(v_short, '; ');
  end if;

  -- ---- 3. Dispatch: each warehouse gives up exactly its allocation ----
  for v_a in
    select ts.source_id as warehouse_id, l.product_id, sum(ts.quantity)::integer as qty
      from public.transfer_line_sources ts
      join public.transfer_request_lines l on l.id = ts.line_id
     where l.transfer_request_id = p_request_id
     group by ts.source_id, l.product_id
  loop
    update public.warehouse_inventory
       set current_qty = current_qty - v_a.qty, updated_at = now()
     where warehouse_id = v_a.warehouse_id and product_id = v_a.product_id;

    -- One movement per warehouse, so Stock History shows where it really came
    -- from rather than attributing everything to one site.
    insert into public.stock_movements
      (product_id, movement_type, from_warehouse_id, to_warehouse_id,
       from_store_id, to_store_id, quantity, notes, created_by)
    values (v_a.product_id, v_movement::stock_movement_type, v_a.warehouse_id, v_dst_wh,
       null, v_dst_st, v_a.qty,
       coalesce(p_note, 'Transfer dispatched — in transit')
         || ' (from ' || (select name from public.warehouses where id = v_a.warehouse_id) || ')',
       auth.uid());
    v_total := v_total + v_a.qty;
  end loop;

  -- ---- 4. Same status transition the single-source path performs ----
  update public.transfer_requests set
    status = 'in_transit'::approval_status,
    was_partial = coalesce(v_is_partial, false),
    -- The header keeps one warehouse for continuity with existing screens and
    -- reports; transfer_line_sources is the authority on the real split.
    source_type = 'warehouse',
    source_id = coalesce(v_req.source_id, p_source_warehouse_id, v_used[1]),
    approved_by = auth.uid(), approved_at = now(),
    dispatched_at = now(), completed_at = null
  where id = p_request_id;

  perform public.write_audit_ex('transfer_requests', p_request_id, 'transfer_dispatched', null,
    jsonb_build_object('approved_lines', p_approved_lines,
      'warehouses_used', array_length(v_used,1),
      'multi_source', array_length(v_used,1) > 1,
      'units_dispatched', v_total, 'partial', coalesce(v_is_partial,false)),
    'transfers', p_note, coalesce(v_dst_st, v_dst_wh));

  return jsonb_build_object('success', true, 'status', 'in_transit',
    'warehouses_used', array_length(v_used,1),
    'multi_source', array_length(v_used,1) > 1,
    'units_dispatched', v_total, 'partial', coalesce(v_is_partial,false));
end $function$;

-- ---------------------------------------------------------------------
-- Which transfers were dispatched before this fix, and what the correction is.
--
-- For each, it shows what each warehouse SHOULD have given up against what the
-- movements actually recorded, so the difference can be put right with a stock
-- adjustment rather than guessed at.
-- ---------------------------------------------------------------------
create or replace function public.report_multi_source_stock_drift()
returns table(
  request_id uuid, dispatched_at timestamptz, product_id uuid, product_name text,
  warehouse_id uuid, warehouse_name text,
  should_have_given integer, actually_recorded integer, correction integer)
language sql stable security definer set search_path to 'public' as $function$
  with allocated as (
    select l.transfer_request_id as req, l.product_id, ts.source_id as wh,
           sum(ts.quantity)::integer as qty
      from public.transfer_line_sources ts
      join public.transfer_request_lines l on l.id = ts.line_id
     group by l.transfer_request_id, l.product_id, ts.source_id
  ),
  -- Requests whose allocations name more than one warehouse.
  multi as (
    select req from allocated group by req having count(distinct wh) > 1
  ),
  recorded as (
    select r.id as req, sm.product_id, sm.from_warehouse_id as wh,
           sum(sm.quantity)::integer as qty
      from public.transfer_requests r
      join public.stock_movements sm
        on sm.created_at between r.dispatched_at - interval '2 minutes'
                            and r.dispatched_at + interval '2 minutes'
       and sm.movement_type::text in ('warehouse_to_store','warehouse_to_warehouse')
     where r.dispatched_at is not null
     group by r.id, sm.product_id, sm.from_warehouse_id
  )
  select a.req, r.dispatched_at, a.product_id, p.name, a.wh, w.name,
         a.qty, coalesce(rec.qty, 0),
         a.qty - coalesce(rec.qty, 0)
    from allocated a
    join multi m on m.req = a.req
    join public.transfer_requests r on r.id = a.req
    join public.products p on p.id = a.product_id
    join public.warehouses w on w.id = a.wh
    left join recorded rec on rec.req = a.req and rec.product_id = a.product_id and rec.wh = a.wh
   where a.qty <> coalesce(rec.qty, 0)
   order by r.dispatched_at desc, p.name, w.name
$function$;

notify pgrst, 'reload schema';
