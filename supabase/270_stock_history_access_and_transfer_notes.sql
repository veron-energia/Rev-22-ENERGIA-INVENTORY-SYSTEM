begin;
-- Read scope is independent of transfer/stock mutation permissions.
create function public.stock_history_global() returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.profiles where id=auth.uid() and is_active and deleted_at is null and role in ('owner','admin','manager','inventory_manager'))
$$;
create function public.stock_history_location(p_kind text,p_id uuid) returns boolean language sql stable security definer set search_path=public as $$
 select p_id is not null and (public.stock_history_global() or (p_kind='store' and exists(
  select 1 from public.user_store_assignments a join public.profiles p on p.id=a.user_id
  where a.user_id=auth.uid() and a.store_id=p_id and p.is_active and p.deleted_at is null and p.role='staff')))
$$;
create function public.stock_history_transfer(p_id uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.transfer_requests r where r.id=p_id and (public.stock_history_global()
  or public.stock_history_location(r.dest_type::text,r.dest_id)
  or public.stock_history_location(r.source_type::text,r.source_id)
  or exists(select 1 from public.transfer_request_lines l join public.transfer_line_sources s on s.line_id=l.id
   where l.transfer_request_id=r.id and public.stock_history_location(s.source_type::text,s.source_id))))
$$;
create function public.stock_history_transfer_line(p_id uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.transfer_request_lines l join public.transfer_requests r on r.id=l.transfer_request_id
  where l.id=p_id and (public.stock_history_global() or public.stock_history_location(r.dest_type::text,r.dest_id)
   or exists(select 1 from public.transfer_line_sources s where s.line_id=l.id and public.stock_history_location(s.source_type::text,s.source_id))
   or (not exists(select 1 from public.transfer_line_sources s where s.line_id=l.id) and public.stock_history_location(r.source_type::text,r.source_id))))
$$;
create function public.stock_history_movement(p_from_wh uuid,p_to_wh uuid,p_from_store uuid,p_to_store uuid,p_transfer uuid default null,p_line uuid default null)
returns boolean language sql stable security definer set search_path=public as $$
 select public.stock_history_global() or public.stock_history_location('store',p_from_store) or public.stock_history_location('store',p_to_store)
$$;
-- Restrictive policies prevent an older permissive policy from widening scope.
create policy stock_history_scope on public.stock_movements as restrictive for select to authenticated using(public.stock_history_movement(from_warehouse_id,to_warehouse_id,from_store_id,to_store_id,transfer_request_id,transfer_request_line_id));
create policy stock_history_read on public.stock_movements for select to authenticated using(public.stock_history_movement(from_warehouse_id,to_warehouse_id,from_store_id,to_store_id,transfer_request_id,transfer_request_line_id));
create policy stock_history_warehouse_scope on public.warehouse_inventory as restrictive for select to authenticated using(public.stock_history_location('warehouse',warehouse_id));
create policy stock_history_store_scope on public.store_inventory as restrictive for select to authenticated using(public.stock_history_location('store',store_id));
create policy stock_history_transfer_scope on public.transfer_requests as restrictive for select to authenticated using(public.stock_history_transfer(id));
create policy stock_history_line_scope on public.transfer_request_lines as restrictive for select to authenticated using(public.stock_history_transfer_line(id));
create policy stock_history_source_scope on public.transfer_line_sources as restrictive for select to authenticated using(
 public.stock_history_global() or public.stock_history_location(source_type::text,source_id) or exists(
 select 1 from public.transfer_request_lines l join public.transfer_requests r on r.id=l.transfer_request_id
 where l.id=line_id and public.stock_history_location(r.dest_type::text,r.dest_id)));
-- Raw revision snapshots may include other legs. Staff receive scalar notes via
-- the checked API below instead of complete snapshots of unrelated legs.
create policy stock_history_revision_scope on public.transfer_request_revisions as restrictive for select to authenticated using(public.stock_history_global());
revoke insert,update,delete on public.transfer_requests,public.transfer_request_lines,public.transfer_line_sources,public.transfer_request_revisions from authenticated,anon;

create function public.stock_history_location_name(p_kind text,p_id uuid) returns text language sql stable security definer set search_path=public as $$
 select case when p_kind='warehouse' then (select name from public.warehouses where id=p_id) else (select name from public.stores where id=p_id) end
$$;
revoke all on function public.stock_history_location_name(text,uuid) from public,anon,authenticated;

create function public.stock_transfer_details(p_request_id uuid) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare r public.transfer_requests%rowtype; history jsonb; line_data jsonb;
begin
 if not public.stock_history_transfer(p_request_id) then raise exception 'This transfer is not available for your assigned locations'; end if;
 select * into r from public.transfer_requests where id=p_request_id;
 with audit_notes as (
  select a.id::text event_id,a.created_at happened_at,a.changed_by author_id,
   replace(a.action,'_',' ') stage,
   concat_ws(E'\n',nullif(a.reason,''),case when a.action='transfer_edited' then nullif(a.new_data->'note'->>'to','') end) note,
   case when a.table_name='transfer_request_lines' then a.record_id end line_id
  from public.audit_logs a where (a.table_name='transfer_requests' and a.record_id=r.id
   or a.table_name='transfer_request_lines' and exists(select 1 from public.transfer_request_lines l where l.id=a.record_id and l.transfer_request_id=r.id and public.stock_history_transfer_line(l.id)))
   and a.action like 'transfer_%'
 ), receipt_lines as (
  -- Resolution replaces the line's current reason. The receipt audit retains
  -- the original per-line reason, actor and time without modifying history.
  select a.id::text||'-receipt-'||l.id event_id,a.created_at happened_at,a.changed_by author_id,
   'Receipt discrepancy'::text stage,e.value->>'reason' note,l.id line_id
  from public.audit_logs a cross join lateral jsonb_array_elements(
   case when jsonb_typeof(a.new_data->'lines')='array' then a.new_data->'lines' else '[]'::jsonb end) e(value)
  join public.transfer_request_lines l on l.id::text=e.value->>'line_id' and l.transfer_request_id=r.id
  where a.table_name='transfer_requests' and a.record_id=r.id and a.action like 'transfer_received%'
   and public.stock_history_transfer_line(l.id) and nullif(btrim(e.value->>'reason'),'') is not null
 ), candidates as (
  select * from audit_notes where nullif(note,'') is not null
  union all select * from receipt_lines
  union all
  select 'request',r.created_at,r.requested_by,'Request',
   case when exists(select 1 from public.transfer_request_revisions v where v.transfer_request_id=r.id) then (select v.snapshot->>'note' from public.transfer_request_revisions v where v.transfer_request_id=r.id order by v.version,v.id limit 1) else r.note end,null::uuid
  where not exists(select 1 from audit_notes where stage in ('transfer requested','transfer requested by staff') and nullif(note,'') is not null)
  union all
  select 'receipt',r.received_at,r.received_by,'Receipt',r.receipt_note,null::uuid
  where not exists(select 1 from audit_notes where stage like 'transfer received%' and note=r.receipt_note)
  union all
  select 'rejected',r.approved_at,r.approved_by,'Rejected',r.rejection_reason,null::uuid
  where not exists(select 1 from audit_notes where stage like '%reject%' and note=r.rejection_reason)
  union all
  select 'revision-'||v.id,v.created_at,v.edited_by,'Transfer edited',concat_ws(E'\n',v.reason,v.changed_summary->'note'->>'to'),null::uuid
  from public.transfer_request_revisions v where v.transfer_request_id=r.id
   and not exists(select 1 from audit_notes a where a.stage='transfer edited' and a.happened_at=v.created_at and a.author_id is not distinct from v.edited_by)
  union all
  select 'line-receipt-'||l.id,r.received_at,r.received_by,'Receipt discrepancy',l.discrepancy_reason,l.id
  from public.transfer_request_lines l where l.transfer_request_id=r.id and public.stock_history_transfer_line(l.id)
   and l.discrepancy_resolved_at is null
   and not exists(select 1 from receipt_lines a where a.line_id=l.id)
  union all
  select 'line-resolution-'||l.id,null::timestamptz,null::uuid,'Historical discrepancy note',l.discrepancy_reason,l.id
  from public.transfer_request_lines l where l.transfer_request_id=r.id and public.stock_history_transfer_line(l.id)
   and l.discrepancy_resolved_at is not null
   and not exists(select 1 from audit_notes a where a.line_id=l.id and a.stage='transfer discrepancy resolved')
   and not exists(select 1 from receipt_lines a where a.line_id=l.id and a.note=l.discrepancy_reason)
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',c.event_id,'at',c.happened_at,'author',coalesce(p.full_name,'Author unavailable'),
  'stage',c.stage,'text',c.note,'line_id',c.line_id,'product',coalesce(pr.name,ln.manual_item_name)) order by c.happened_at nulls last,c.event_id),'[]') into history
 from candidates c left join public.profiles p on p.id=c.author_id left join public.transfer_request_lines ln on ln.id=c.line_id
 left join public.products pr on pr.id=ln.product_id where nullif(btrim(c.note),'') is not null;
 select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'product',coalesce(p.name,l.manual_item_name),'sku',p.sku,'uom',coalesce(l.manual_uom,'units'),
  'quantity',case when public.stock_history_global() or public.stock_history_location(r.dest_type::text,r.dest_id) then coalesce(l.approved_quantity,l.quantity)
   else coalesce((select sum(s.quantity) from public.transfer_line_sources s where s.line_id=l.id and public.stock_history_location(s.source_type::text,s.source_id)),l.quantity) end,
  'sources',(select coalesce(jsonb_agg(jsonb_build_object('name',public.stock_history_location_name(s.source_type::text,s.source_id),'quantity',s.quantity)),'[]')
   from public.transfer_line_sources s where s.line_id=l.id and (public.stock_history_global() or public.stock_history_location(r.dest_type::text,r.dest_id) or public.stock_history_location(s.source_type::text,s.source_id)))) order by l.id),'[]')
 into line_data from public.transfer_request_lines l left join public.products p on p.id=l.product_id
 where l.transfer_request_id=r.id and public.stock_history_transfer_line(l.id);
 return jsonb_build_object('id',r.id,'status',r.status,'destination',public.stock_history_location_name(r.dest_type::text,r.dest_id),'notes',history,'lines',line_data);
end $$;
revoke all on function public.stock_transfer_details(uuid) from public,anon;
grant execute on function public.stock_transfer_details(uuid) to authenticated;

-- Existing transfer-revision API retains its shape, with snapshots limited to
-- managers; staff use the shared note history for authorized transfers.
create or replace function public.transfer_revisions(p_transfer_id uuid)
returns table(version integer,reason text,changed_summary jsonb,snapshot jsonb,editor text,created_at timestamptz)
language sql stable security definer set search_path=public as $$
 select r.version,r.reason,case when public.stock_history_global() then r.changed_summary else '{}'::jsonb end,
 case when public.stock_history_global() then r.snapshot else null end,p.full_name,r.created_at
 from public.transfer_request_revisions r left join public.profiles p on p.id=r.edited_by
 where r.transfer_request_id=p_transfer_id and public.stock_history_transfer(p_transfer_id) order by r.version desc
$$;
-- Existing source-selection APIs reveal inventories: keep them with the roles
-- that already manage/inspect stock. No new staff access is granted by labels.
do $$ declare sig text; f text; name text; args text; argcall text; return_shape text; begin
 foreach name in array array['transfer_request_sourcing','transfer_product_sourcing'] loop
  if name='transfer_request_sourcing' then sig:=name||'(uuid)';args:='p_request_id uuid';argcall:='p_request_id';
  else sig:=name||'(uuid,uuid)';args:='p_request_id uuid,p_product_id uuid';argcall:='p_request_id,p_product_id';end if;
  select pg_get_function_result(('public.'||sig)::regprocedure) into return_shape;
  execute format('alter function public.%s rename to stock_private_%I',sig,name);
  execute format('revoke all on function public.stock_private_%s from public,anon,authenticated',sig);
  execute format('create function public.%I(%s) returns %s language sql stable security definer set search_path=public as $b$ select * from public.stock_private_%I(%s) where public.stock_history_global() $b$',name,args,return_shape,name,argcall);
 end loop;
end $$;
-- The existing availability endpoint also must not expose counterpart balances.
alter function public.location_available_qty(public.location_type,uuid,uuid,uuid) rename to stock_private_location_available_qty;
revoke all on function public.stock_private_location_available_qty(public.location_type,uuid,uuid,uuid) from public,anon,authenticated;
create function public.location_available_qty(p_location_type public.location_type,p_location_id uuid,p_product_id uuid,p_exclude_request_id uuid)
returns table(on_hand integer,reserved integer,available integer) language sql stable security definer set search_path=public as $$
 select * from public.stock_private_location_available_qty(p_location_type,p_location_id,p_product_id,p_exclude_request_id)
 where public.stock_history_location(p_location_type::text,p_location_id)
$$;
revoke all on function public.stock_history_global(),public.stock_history_location(text,uuid),public.stock_history_transfer(uuid),public.stock_history_transfer_line(uuid),public.stock_history_movement(uuid,uuid,uuid,uuid,uuid,uuid) from public,anon;
grant execute on function public.stock_history_global(),public.stock_history_location(text,uuid),public.stock_history_transfer(uuid),public.stock_history_transfer_line(uuid),public.stock_history_movement(uuid,uuid,uuid,uuid,uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
