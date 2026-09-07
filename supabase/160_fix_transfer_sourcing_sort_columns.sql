-- Fix Review / Add Product errors: SQLSTATE 42703 (undefined column).
-- Run AFTER 159_transfer_page_review_and_manual_items.sql in Supabase SQL Editor.
-- RETURNS TABLE names do not define aliases inside the SELECT / UNION query.
-- Explicit aliases let ORDER BY resolve product_name and source_name.
-- Only replaces the two read-only sourcing functions; no stock or request changes.

begin;
set local check_function_bodies = on;

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

notify pgrst, 'reload schema';
commit;
