begin;
-- Raw lines aggregate every source leg. Source-only staff use the checked,
-- projected transfer details API; destination staff may receive all the lines.
drop policy stock_history_line_scope on public.transfer_request_lines;
create policy stock_history_line_scope on public.transfer_request_lines as restrictive for select to authenticated using(
 public.stock_history_global() or exists(select 1 from public.transfer_requests r where r.id=transfer_request_id and public.stock_history_location(r.dest_type::text,r.dest_id)));
create or replace function public.stock_history_transfer(p_id uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.transfer_requests r where r.id=p_id and (public.stock_history_global()
  or public.stock_history_location(r.dest_type::text,r.dest_id)
  or (public.stock_history_location(r.source_type::text,r.source_id) and not exists(select 1 from public.transfer_request_lines l join public.transfer_line_sources s on s.line_id=l.id where l.transfer_request_id=r.id))
  or exists(select 1 from public.transfer_request_lines l join public.transfer_line_sources s on s.line_id=l.id
   where l.transfer_request_id=r.id and public.stock_history_location(s.source_type::text,s.source_id))))
$$;
-- These legacy administrative reports return whole-company or whole-transfer
-- aggregates. Retain their existing management role access. Staff reporting
-- uses the scoped, per-location endpoints introduced in271.
do $$ declare name text; shape text; begin
 foreach name in array array['report_transfers_in_transit','report_transfer_discrepancies','report_multi_source_stock_drift','report_transfer_stock_integrity'] loop
  select pg_get_function_result(('public.'||name||'()')::regprocedure) into shape;
  execute format('alter function public.%I() rename to stock_private_%I',name,name);
  execute format('revoke all on function public.stock_private_%I() from public,anon,authenticated',name);
  execute format('create function public.%I() returns %s language sql stable security definer set search_path=public as $b$ select * from public.stock_private_%I() where public.stock_history_global() $b$',name,shape,name);
  execute format('revoke all on function public.%I() from public,anon',name);
  execute format('grant execute on function public.%I() to authenticated',name);
 end loop;
end $$;
create or replace function public.transfer_receipt_alerts() returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('awaiting_receipt',count(*) filter(where status='in_transit'),
  'overdue',count(*) filter(where status='in_transit' and dispatched_at<now()-interval '7 days'),
  'open_discrepancies',count(*) filter(where status='received_with_discrepancy'))
 from public.transfer_requests where public.stock_history_transfer(id)
$$;
-- Preserve authorized legacy sourced-request creation/editing. Their existing
-- mutation guards still run, while stock validation is private and must not
-- reveal a counterpart's balance in an insufficient-stock error.
do $$ declare name text; sig text; f text; kind_expr text; id_expr text; guard text;begin
 foreach name in array array['create_transfer_request','edit_transfer_request'] loop
  sig:=case when name='create_transfer_request' then 'public.create_transfer_request(text,text,uuid,text,uuid,jsonb,text)'
   else 'public.edit_transfer_request(uuid,integer,text,public.location_type,uuid,public.location_type,uuid,jsonb,text)' end;
  select pg_get_functiondef(sig::regprocedure) into f;
  if position('public.location_available_qty(' in f)=0 then raise exception 'Unexpected sourced-request definition: %',name;end if;
  kind_expr:=case when name='create_transfer_request' then 'v_src_type' else 'v_new_source_type' end;
  id_expr:=case when name='create_transfer_request' then 'p_source_id' else 'v_new_source_id' end;
  guard:=format('if not public.stock_history_location(%s::text,%s) and coalesce(v_av.available,0)<v_qty then raise exception ''Insufficient stock at the requested source. Ask a manager to review the allocation.''; end if; ',kind_expr,id_expr);
  f:=replace(f,'public.location_available_qty(','public.stock_private_location_available_qty(');
  if f !~ 'if coalesce\(v_av.available,0\)\s*<\s*v_qty then' then raise exception 'Unexpected availability check: %',name;end if;
  f:=regexp_replace(f,'if coalesce\(v_av.available,0\)\s*<\s*v_qty then',guard||'if coalesce(v_av.available,0)<v_qty then');
  execute f;
 end loop;
end $$;
-- Preserve the remaining legacy signatures but close their unscoped reads.
do $$ declare f text; sig text;begin
 foreach sig in array array['public.report_transfer_receipts(date,date)','public.report_transfers_overdue(integer)'] loop
  select pg_get_functiondef(sig::regprocedure) into f;
  if position('where t.status' in f)=0 then raise exception 'Unexpected legacy transfer report: %',sig;end if;
  execute replace(f,'where t.status','where public.stock_history_global() and t.status');
 end loop;
 -- The159 integrity report had untyped UNION nulls inferred as text before a
 -- later UUID location_id. Explicit casts preserve its intended output shape.
 select pg_get_functiondef('public.stock_private_report_transfer_stock_integrity()'::regprocedure) into f;
 execute replace(f,'b.product_id,null,null,','b.product_id,null::text,null::uuid,');
end $$;
notify pgrst,'reload schema';
commit;
