-- =====================================================================
-- ENERGIA — STOCK USE IN THE HISTORY, AND A SEARCHABLE HISTORY
--
-- 1. record_stock_use() deducted stock and wrote a stock_uses row, but never a
--    stock_movement. Stock Movement History calls itself "every stock change",
--    and it was missing one: a tester or demo unit left the shelf with no line
--    in the permanent record. Now it writes a movement like any other change.
--
-- 2. Stock Movement History could not be searched. A function is added that
--    searches product name and SKU, warehouse and store names, the person who
--    made the change, the movement type and the note — so "Emi", "P00201",
--    "Adelphi" or "opening" all find the right rows.
--
-- Additive and idempotent. Run AFTER 110.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. A stock use is a stock change, so it belongs in the history.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'record_stock_use';
  if v_def is null then raise exception 'record_stock_use not found'; end if;
  if position('stock_movements' in v_def) > 0 then
    raise notice 'record_stock_use already records a movement'; return;
  end if;

  -- Inserted immediately after the stock_uses row, so the movement carries the
  -- same use number and reason and the two can be reconciled.
  v_new := replace(v_def,
    '  perform public.write_audit_ex(''stock_uses'', v_id, ''stock_used'', null,',
    '  insert into public.stock_movements' || chr(10) ||
    '    (product_id, movement_type, from_store_id, from_warehouse_id,' || chr(10) ||
    '     quantity, notes, created_by)' || chr(10) ||
    '  values (p_product_id, ''inventory_adjustment''::stock_movement_type,' || chr(10) ||
    '    case when p_location_type = ''store'' then p_location_id end,' || chr(10) ||
    '    case when p_location_type = ''warehouse'' then p_location_id end,' || chr(10) ||
    '    p_quantity,' || chr(10) ||
    '    ''Stock use '' || v_no || '' — '' || trim(p_reason)' || chr(10) ||
    '      || coalesce('' ('' || nullif(trim(p_note), '''') || '')'', ''''),' || chr(10) ||
    '    auth.uid());' || chr(10) || chr(10) ||
    '  perform public.write_audit_ex(''stock_uses'', v_id, ''stock_used'', null,');

  if position('stock_movements' in v_new) = 0 then
    raise exception 'Could not add the movement to record_stock_use';
  end if;
  execute v_new;
  raise notice 'record_stock_use now writes a stock movement';
end $patch$;

-- ---------------------------------------------------------------------
-- 2. Searchable stock movement history.
--
--    Everything a person might type is matched: the product name or SKU, the
--    warehouse or store at either end, who made the change, the movement type,
--    and the note (which carries invoice and document numbers).
-- ---------------------------------------------------------------------
create or replace function public.search_stock_movements(
  p_query text default null, p_type text default null,
  p_from date default null, p_to date default null,
  p_limit integer default 200, p_offset integer default 0)
returns table(
  id uuid, created_at timestamptz, movement_type text,
  product_id uuid, product_name text, product_sku text,
  from_name text, to_name text, quantity integer,
  by_name text, notes text, total_count bigint)
language sql stable security definer set search_path to 'public' as $function$
  with base as (
    select sm.id, sm.created_at, sm.movement_type::text as movement_type,
           sm.product_id, p.name as product_name, p.sku as product_sku,
           coalesce(fw.name, fs.name) as from_name,
           coalesce(tw.name, ts.name) as to_name,
           sm.quantity, pr.full_name as by_name, sm.notes
      from public.stock_movements sm
      left join public.products p on p.id = sm.product_id
      left join public.warehouses fw on fw.id = sm.from_warehouse_id
      left join public.warehouses tw on tw.id = sm.to_warehouse_id
      left join public.stores fs on fs.id = sm.from_store_id
      left join public.stores ts on ts.id = sm.to_store_id
      left join public.profiles pr on pr.id = sm.created_by
  ),
  filtered as (
    select * from base b
     where (p_type is null or p_type = 'all' or b.movement_type = p_type)
       and (p_from is null or (b.created_at at time zone 'Asia/Singapore')::date >= p_from)
       and (p_to   is null or (b.created_at at time zone 'Asia/Singapore')::date <= p_to)
       and (
         nullif(trim(coalesce(p_query, '')), '') is null
         or concat_ws(' ',
              b.product_name, b.product_sku, b.from_name, b.to_name,
              b.by_name, b.notes, replace(b.movement_type, '_', ' '))
            ilike '%' || trim(p_query) || '%'
       )
  )
  select f.id, f.created_at, f.movement_type, f.product_id, f.product_name,
         f.product_sku, f.from_name, f.to_name, f.quantity, f.by_name, f.notes,
         count(*) over () as total_count
    from filtered f
   order by f.created_at desc
   limit greatest(coalesce(p_limit, 200), 1)
  offset greatest(coalesce(p_offset, 0), 0)
$function$;

notify pgrst, 'reload schema';
