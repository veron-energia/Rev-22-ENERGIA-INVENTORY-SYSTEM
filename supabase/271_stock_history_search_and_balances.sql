begin;
-- Observe the existing inventory baseline without changing a single quantity.
-- Complete future deltas make subsequent date boundaries reconstructible.
lock table public.store_inventory,public.warehouse_inventory,public.stock_movements in share row exclusive mode;
-- Future event times follow the actual stock write, including transactions
-- started before midnight. Legacy document times remain untouched.
alter table public.stock_movements add column stock_history_recorded_at timestamptz;
alter table public.stock_movements alter column stock_history_recorded_at set default clock_timestamp();
create table public.stock_history_observation(id boolean primary key default true check(id),started_at timestamptz not null);
insert into public.stock_history_observation values(true,clock_timestamp());
create table public.stock_history_baselines(product_id uuid not null,location_key text not null,quantity bigint not null,primary key(product_id,location_key));
insert into public.stock_history_baselines select product_id,'store:'||store_id,current_qty from public.store_inventory
 union all select product_id,'warehouse:'||warehouse_id,current_qty from public.warehouse_inventory;
create table public.stock_history_inventory_changes(
 id bigint generated always as identity primary key,product_id uuid not null,location_key text not null,
 delta bigint not null,before_quantity bigint not null,after_quantity bigint not null,occurred_at timestamptz not null default clock_timestamp(),
 actor_id uuid,transaction_id bigint not null default txid_current());
create index stock_history_changes_lookup on public.stock_history_inventory_changes(product_id,location_key,occurred_at);
alter table public.stock_history_observation enable row level security;
alter table public.stock_history_baselines enable row level security;
alter table public.stock_history_inventory_changes enable row level security;
revoke all on public.stock_history_observation,public.stock_history_baselines,public.stock_history_inventory_changes from public,anon,authenticated;
create function public.stock_history_capture_inventory() returns trigger language plpgsql security definer set search_path=public as $$
declare old_row jsonb; new_row jsonb; kind text; old_key text; new_key text; old_qty bigint; new_qty bigint;
begin
 old_row:=case when tg_op<>'INSERT' then to_jsonb(old) end; new_row:=case when tg_op<>'DELETE' then to_jsonb(new) end;
 kind:=case when tg_table_name='store_inventory' then 'store' else 'warehouse' end;
 old_key:=kind||':'||(old_row->>(kind||'_id')); new_key:=kind||':'||(new_row->>(kind||'_id'));
 old_qty:=coalesce((old_row->>'current_qty')::bigint,0);new_qty:=coalesce((new_row->>'current_qty')::bigint,0);
 if tg_op='UPDATE' and (old_key,old_row->>'product_id') is distinct from (new_key,new_row->>'product_id') then
  insert into public.stock_history_inventory_changes(product_id,location_key,delta,before_quantity,after_quantity,actor_id)
   values((old_row->>'product_id')::uuid,old_key,-old_qty,old_qty,0,auth.uid()),((new_row->>'product_id')::uuid,new_key,new_qty,0,new_qty,auth.uid());
 elsif old_qty<>new_qty then
  insert into public.stock_history_inventory_changes(product_id,location_key,delta,before_quantity,after_quantity,actor_id)
   values(coalesce(new_row->>'product_id',old_row->>'product_id')::uuid,coalesce(new_key,old_key),new_qty-old_qty,old_qty,new_qty,auth.uid());
 end if;
 return null;
end $$;
revoke all on function public.stock_history_capture_inventory() from public,anon,authenticated;
create trigger stock_history_store_delta after insert or update or delete on public.store_inventory for each row execute function public.stock_history_capture_inventory();
create trigger stock_history_warehouse_delta after insert or update or delete on public.warehouse_inventory for each row execute function public.stock_history_capture_inventory();

create function public.stock_history_locations() returns table(value text,label text) language sql stable security definer set search_path=public as $$
 select 'store:'||id,name||' (Store)' from public.stores where public.stock_history_location('store',id)
 union all select 'warehouse:'||id,name||' (Warehouse)' from public.warehouses where public.stock_history_location('warehouse',id)
$$;
create function public.stock_history_validate(p_filters jsonb) returns boolean language plpgsql stable security definer set search_path=public as $$
declare key text; f date; t date;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and is_active and deleted_at is null and role in ('owner','admin','manager','inventory_manager','staff')) then raise exception 'Stock History is available to internal staff only'; end if;
 f:=nullif(p_filters->>'from','')::date;t:=nullif(p_filters->>'to','')::date;
 if f is null or t is null or f>t or t>public.sg_today() then raise exception 'Choose a valid date range ending today or earlier'; end if;
 foreach key in array array['products','locations','people','types'] loop
  if p_filters ? key and jsonb_typeof(p_filters->key)<>'array' then raise exception 'Invalid % filter',key;end if;
 end loop;
 if exists(select 1 from jsonb_array_elements_text(coalesce(p_filters->'locations','[]')) v where not exists(select 1 from public.stock_history_locations() l where l.value=v)) then raise exception 'A selected location is no longer available for your assignments'; end if;
 return exists(select 1 from public.stock_history_locations());
end $$;
create function public.stock_history_type_label(p_type text) returns text language sql immutable as $$
 select case p_type when 'warehouse_stock_in' then 'Stock In' when 'warehouse_to_store' then 'WH → Store' when 'warehouse_to_warehouse' then 'WH → WH'
 when 'store_to_store' then 'Store → Store' when 'store_sale' then 'Sale' when 'invoice_cancel_return' then 'Cancel Return'
 when 'invoice_refund_return' then 'Refund Return' when 'inventory_adjustment' then 'Adjustment'
 when 'transfer_dispatch' then 'Transfer Dispatch' when 'transfer_receipt' then 'Transfer Receipt' when 'transfer_discrepancy' then 'Transfer Discrepancy'
 else initcap(replace(p_type,'_',' ')) end
$$;
create function public.stock_history_rows(p_filters jsonb,p_as_of timestamptz)
returns table(id uuid,created_at timestamptz,movement_type text,type_label text,product_id uuid,product_name text,product_sku text,
 from_key text,to_key text,from_name text,to_name text,quantity integer,actor_id uuid,by_name text,notes text,transfer_request_id uuid,transfer_request_line_id uuid)
language sql stable security definer set search_path=public as $$
 with base(id,created_at,movement_type,type_label,product_id,product_name,product_sku,from_key,to_key,from_name,to_name,quantity,actor_id,by_name,notes,transfer_request_id,transfer_request_line_id) as (
 select m.id,coalesce(m.stock_history_recorded_at,m.created_at),m.movement_type::text,public.stock_history_type_label(m.movement_type::text),m.product_id,p.name,p.sku,
  case when m.from_store_id is not null then 'store:'||m.from_store_id when m.from_warehouse_id is not null then 'warehouse:'||m.from_warehouse_id end,
  case when m.to_store_id is not null then 'store:'||m.to_store_id when m.to_warehouse_id is not null then 'warehouse:'||m.to_warehouse_id end,
  coalesce(fs.name,fw.name),coalesce(ts.name,tw.name),m.quantity,m.created_by,pr.full_name,m.notes,m.transfer_request_id,m.transfer_request_line_id
 from public.stock_movements m left join public.products p on p.id=m.product_id
 left join public.stores fs on fs.id=m.from_store_id left join public.warehouses fw on fw.id=m.from_warehouse_id
 left join public.stores ts on ts.id=m.to_store_id left join public.warehouses tw on tw.id=m.to_warehouse_id
 left join public.profiles pr on pr.id=m.created_by
 where public.stock_history_movement(m.from_warehouse_id,m.to_warehouse_id,m.from_store_id,m.to_store_id,m.transfer_request_id,m.transfer_request_line_id)
  and coalesce(m.stock_history_recorded_at,m.created_at)<=p_as_of
  and coalesce(m.stock_history_recorded_at,m.created_at)>=((p_filters->>'from')::date::timestamp at time zone 'Asia/Singapore')
  and coalesce(m.stock_history_recorded_at,m.created_at)<(((p_filters->>'to')::date+1)::timestamp at time zone 'Asia/Singapore')
 ), named as(select b.* from base b)
 select * from named b where
 (coalesce(jsonb_array_length(p_filters->'products'),0)=0 or p_filters->'products' ? b.product_id::text)
 and (coalesce(jsonb_array_length(p_filters->'locations'),0)=0 or p_filters->'locations' ? b.from_key or p_filters->'locations' ? b.to_key)
 and (coalesce(jsonb_array_length(p_filters->'people'),0)=0 or p_filters->'people' ? b.actor_id::text)
 and (coalesce(jsonb_array_length(p_filters->'types'),0)=0 or p_filters->'types' ? b.movement_type)
 and (nullif(btrim(p_filters->>'search'),'') is null or position(lower(btrim(p_filters->>'search')) in lower(concat_ws(' ',b.product_name,b.product_sku,b.from_name,b.to_name,b.by_name,b.type_label,b.movement_type,replace(b.movement_type,'_',' '),b.notes,b.quantity::text,to_char(b.created_at at time zone 'Asia/Singapore','DD/MM/YYYY'),to_char(b.created_at at time zone 'Asia/Singapore','YYYY-MM-DD'))))>0)
$$;
revoke all on function public.stock_history_rows(jsonb,timestamptz),public.stock_history_validate(jsonb),public.stock_history_locations() from public,anon,authenticated;
create index stock_history_stable_page on public.stock_movements(coalesce(stock_history_recorded_at,created_at) desc,id desc);
create index stock_history_from_store on public.stock_movements(from_store_id,coalesce(stock_history_recorded_at,created_at) desc,id desc);
create index stock_history_to_store on public.stock_movements(to_store_id,coalesce(stock_history_recorded_at,created_at) desc,id desc);
create function public.stock_history_page(p_filters jsonb,p_limit integer default 100,p_offset integer default 0,p_as_of timestamptz default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare allowed boolean; result jsonb; cutoff timestamptz:=least(coalesce(p_as_of,clock_timestamp()),clock_timestamp());
begin
 allowed:=public.stock_history_validate(p_filters);
 with matches as materialized(select * from public.stock_history_rows(p_filters,cutoff)), page as (
  select * from matches order by created_at desc,id desc limit greatest(1,least(coalesce(p_limit,100),1000)) offset greatest(coalesce(p_offset,0),0))
 select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(p) order by created_at desc,id desc) from page p),'[]'),
 'total',(select count(*) from matches),'as_of',cutoff,'has_access',allowed) into result;
 return result;
end $$;
create function public.stock_history_options(p_kind text,p_query text default '',p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and is_active and deleted_at is null and role in ('owner','admin','manager','inventory_manager','staff')) then raise exception 'Stock History is available to internal staff only'; end if;
 if p_kind not in ('products','locations','people','types') then raise exception 'Invalid filter';end if;
 with visible as materialized(select m.* from public.stock_movements m where public.stock_history_movement(m.from_warehouse_id,m.to_warehouse_id,m.from_store_id,m.to_store_id,m.transfer_request_id,m.transfer_request_line_id)),
 options as (
 select p.id::text value,p.name||coalesce(' · '||p.sku,'') label from public.products p where p_kind='products' and (
  exists(select 1 from visible where product_id=p.id) or exists(select 1 from public.store_inventory i where i.product_id=p.id and public.stock_history_location('store',i.store_id))
  or exists(select 1 from public.warehouse_inventory i where i.product_id=p.id and public.stock_history_location('warehouse',i.warehouse_id)))
 union all select * from public.stock_history_locations() where p_kind='locations'
 union all select p.id::text,p.full_name from public.profiles p where p_kind='people' and exists(select 1 from visible where created_by=p.id)
 union all select distinct movement_type::text,public.stock_history_type_label(movement_type::text) from visible where p_kind='types'
 ), matches as materialized(select * from options where position(lower(btrim(coalesce(p_query,''))) in lower(label))>0),
 page as(select * from matches order by label,value limit 100 offset greatest(coalesce(p_offset,0),0))
 select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(p) order by label,value) from page p),'[]'),'total',(select count(*) from matches),
 'has_access',exists(select 1 from public.stock_history_locations())) into result;
 return result;
end $$;

-- Classify historical effects from the actual writer contracts. Stock use uses
-- inventory_adjustment with a from location. A dispatch has a destination label
-- but only deducts its source; receipt is a separate destination-only movement.
create function public.stock_history_effect(p_id uuid,p_location text) returns bigint language plpgsql stable security definer set search_path=public as $$
declare m public.stock_movements%rowtype; src text; dst text; diff integer; qty bigint;
begin
 select * into m from public.stock_movements where id=p_id;
 src:=case when m.from_store_id is not null then 'store:'||m.from_store_id when m.from_warehouse_id is not null then 'warehouse:'||m.from_warehouse_id end;
 dst:=case when m.to_store_id is not null then 'store:'||m.to_store_id when m.to_warehouse_id is not null then 'warehouse:'||m.to_warehouse_id end;
 qty:=abs(m.quantity);
 if m.movement_type='transfer_dispatch' then return case when src=p_location then -qty else 0 end;
 elsif m.movement_type='transfer_receipt' then return case when dst=p_location then qty else 0 end;
 elsif m.movement_type='transfer_discrepancy' or (m.movement_type='inventory_adjustment' and m.notes like 'Discrepancy:%') then
  if m.transfer_request_line_id is null then return null; end if;
  select discrepancy_quantity into diff from public.transfer_request_lines where id=m.transfer_request_line_id;
  if diff is null then return null;end if;
  if m.notes like 'Discrepancy: corrected source%' then return case when src=p_location then -diff else 0 end;
  elsif m.notes like 'Discrepancy: corrected destination%' then return case when dst=p_location then -diff else 0 end;
  elsif m.notes like 'Discrepancy: linked inventory adjustment%' then return case when dst=p_location then greatest(-diff,0) else 0 end;
  elsif m.notes not like 'Discrepancy: returned excess%' then return null;end if;
 end if;
 if src is null and dst is null then return null;end if;
 if src=dst and src=p_location then return null;end if;
 return case when src=p_location then -qty else 0 end+case when dst=p_location then qty else 0 end;
end $$;
revoke all on function public.stock_history_effect(uuid,text) from public,anon,authenticated;

create function public.stock_history_table(p_filters jsonb,p_limit integer default 100,p_offset integer default 0,p_as_of timestamptz default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare allowed boolean; result jsonb; cutoff timestamptz:=least(coalesce(p_as_of,clock_timestamp()),clock_timestamp());
 first_at timestamptz; end_at timestamptz; observed timestamptz; filtered boolean;
begin
 allowed:=public.stock_history_validate(p_filters);
 first_at:=(p_filters->>'from')::date::timestamp at time zone 'Asia/Singapore';
 end_at:=least(((p_filters->>'to')::date+1)::timestamp at time zone 'Asia/Singapore',cutoff);
 select started_at into observed from public.stock_history_observation;
 filtered:=nullif(btrim(p_filters->>'search'),'') is not null or coalesce(jsonb_array_length(p_filters->'people'),0)>0 or coalesce(jsonb_array_length(p_filters->'types'),0)>0;
 with locations as materialized(select * from public.stock_history_locations() l where coalesce(jsonb_array_length(p_filters->'locations'),0)=0 or p_filters->'locations' ? l.value),
 products as materialized(select p.id,p.name,p.sku from public.products p where
  (coalesce(jsonb_array_length(p_filters->'products'),0)=0 or p_filters->'products' ? p.id::text)
  and (exists(select 1 from public.stock_history_baselines b where b.product_id=p.id and exists(select 1 from public.stock_history_locations() a where a.value=b.location_key))
   or exists(select 1 from public.stock_history_inventory_changes c where c.product_id=p.id and exists(select 1 from public.stock_history_locations() a where a.value=c.location_key))
   or exists(select 1 from public.stock_movements m where m.product_id=p.id and public.stock_history_movement(m.from_warehouse_id,m.to_warehouse_id,m.from_store_id,m.to_store_id,m.transfer_request_id,m.transfer_request_line_id)))),
 pairs as materialized(select p.id product_id,p.name product_name,p.sku product_sku,l.value location_key,l.label location_name from products p cross join locations l),
 page as materialized(select * from pairs order by product_name,product_id,location_name,location_key limit greatest(1,least(coalesce(p_limit,100),1000)) offset greatest(coalesce(p_offset,0),0)),
 matches as materialized(select * from public.stock_history_rows(p_filters,cutoff)),
 rows as (
 select x.*,
 case when first_at>=observed and integrity.actual=integrity.evidenced_qty then coalesce(b.quantity,0)+coalesce(d.before_net,0) end opening_balance,
 case when end_at>=observed and integrity.actual=integrity.evidenced_qty then coalesce(b.quantity,0)+coalesce(d.end_net,0) end closing_balance,
 case when filtered then coalesce(m.inbound,0) else coalesce(h.inbound,0)+coalesce(d.inbound,0) end inbound,
 case when filtered then coalesce(m.outbound,0) else coalesce(h.outbound,0)+coalesce(d.outbound,0) end outbound,
 case when first_at>=observed and filtered and integrity.actual=integrity.evidenced_qty then coalesce(d.period_net,0)-(coalesce(m.inbound,0)-coalesce(m.outbound,0)) end other_movement_net,
 coalesce(tr.incoming,0) in_transit_incoming,coalesce(tr.outgoing,0) in_transit_outgoing,
 concat_ws(' ',case when first_at<observed then 'Opening balance unknown: complete inventory observations began after this range started.' end,
  case when end_at<observed then 'Closing balance unknown: no verified baseline for this date.' end,
  case when integrity.actual<>integrity.evidenced_qty then 'Actual balances unknown: current inventory differs from the observation evidence. Review the missing changes.' end,
  case when coalesce(m.unknown,0)>0 or coalesce(h.unknown,0)>0 then 'Some historical movement effects cannot be established from their records.' end,
  case when coalesce(d.inbound,0)<>coalesce(h.current_inbound,0) or coalesce(d.outbound,0)<>coalesce(h.current_outbound,0) then 'Observed inventory changes differ from linked movement totals; review unrecorded or duplicate effects.' end,
  case when tr.unlinked>0 then 'Older transfer movements have no exact transfer link; historical transit may be incomplete.' end) warning
 from page x left join public.stock_history_baselines b on b.product_id=x.product_id and b.location_key=x.location_key
 left join lateral(select coalesce((select current_qty from public.store_inventory where product_id=x.product_id and 'store:'||store_id=x.location_key),
  (select current_qty from public.warehouse_inventory where product_id=x.product_id and 'warehouse:'||warehouse_id=x.location_key),0) actual,
  coalesce(b.quantity,0)+coalesce((select sum(delta) from public.stock_history_inventory_changes where product_id=x.product_id and location_key=x.location_key),0) evidenced_qty) integrity on true
 left join lateral(select sum(delta) filter(where occurred_at<first_at) before_net,sum(delta) end_net,
  sum(delta) filter(where occurred_at>=first_at) period_net,sum(greatest(delta,0)) filter(where occurred_at>=first_at) inbound,sum(greatest(-delta,0)) filter(where occurred_at>=first_at) outbound
  from public.stock_history_inventory_changes where product_id=x.product_id and location_key=x.location_key and occurred_at<end_at) d on true
 left join lateral(select sum(greatest(e,0)) inbound,sum(greatest(-e,0)) outbound,count(*) filter(where e is null) unknown from (
  select public.stock_history_effect(q.id,x.location_key) e from matches q where q.product_id=x.product_id and (q.from_key=x.location_key or q.to_key=x.location_key)) v) m on true
 left join lateral(select sum(greatest(e,0)) filter(where created_at<observed) inbound,sum(greatest(-e,0)) filter(where created_at<observed) outbound,
  sum(greatest(e,0)) filter(where created_at>=observed) current_inbound,sum(greatest(-e,0)) filter(where created_at>=observed) current_outbound,count(*) filter(where e is null) unknown from (
  select coalesce(sm.stock_history_recorded_at,sm.created_at) created_at,public.stock_history_effect(sm.id,x.location_key) e from public.stock_movements sm where sm.product_id=x.product_id
   and coalesce(sm.stock_history_recorded_at,sm.created_at)>=first_at and coalesce(sm.stock_history_recorded_at,sm.created_at)<end_at and (x.location_key in ('store:'||sm.from_store_id,'store:'||sm.to_store_id,'warehouse:'||sm.from_warehouse_id,'warehouse:'||sm.to_warehouse_id))) z) h on true
 left join lateral(select sum(q.quantity) filter(where q.dest=x.location_key and q.pending) incoming,sum(q.quantity) filter(where q.src=x.location_key and q.pending) outgoing,
  count(*) filter(where q.transfer_request_id is null) unlinked from (
  select sm.quantity,sm.transfer_request_id,
   coalesce('store:'||sm.from_store_id,'warehouse:'||sm.from_warehouse_id) src,
   coalesce('store:'||sm.to_store_id,'warehouse:'||sm.to_warehouse_id) dest,
   sm.transfer_request_id is not null and (r.received_at is null or greatest(r.received_at,(select max(coalesce(receipt.stock_history_recorded_at,receipt.created_at))
    from public.stock_movements receipt where receipt.transfer_request_id=r.id and receipt.movement_type='transfer_receipt'))>=end_at) pending
  from public.stock_movements sm left join public.transfer_requests r on r.id=sm.transfer_request_id
  where sm.product_id=x.product_id and sm.movement_type='transfer_dispatch' and coalesce(sm.stock_history_recorded_at,sm.created_at)<end_at
   and (x.location_key in ('store:'||sm.from_store_id,'store:'||sm.to_store_id,'warehouse:'||sm.from_warehouse_id,'warehouse:'||sm.to_warehouse_id))) q) tr on true
 )
 select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(r) order by product_name,product_id,location_name,location_key) from rows r),'[]'),
 'total',(select count(*) from pairs),'as_of',cutoff,'has_access',allowed,'filtered_movements',filtered,'observations_started_at',observed) into result;
 return result;
end $$;
-- The old search endpoint must enforce identical authorization and search rules.
create or replace function public.search_stock_movements(p_query text default null,p_type text default null,p_from date default null,p_to date default null,p_limit integer default 200,p_offset integer default 0)
returns table(id uuid,created_at timestamptz,movement_type text,product_id uuid,product_name text,product_sku text,from_name text,to_name text,quantity integer,by_name text,notes text,total_count bigint)
language sql stable security definer set search_path=public as $$
 with data as(select public.stock_history_page(jsonb_build_object('from',coalesce(p_from,'1900-01-01'::date),'to',coalesce(p_to,public.sg_today()),'search',p_query,
 'types',case when p_type is null or p_type='all' then '[]'::jsonb else jsonb_build_array(p_type) end),p_limit,p_offset) r)
 select x.id,x.created_at,x.movement_type,x.product_id,x.product_name,x.product_sku,x.from_name,x.to_name,x.quantity,x.by_name,x.notes,(r->>'total')::bigint
 from data,jsonb_to_recordset(r->'rows') as x(id uuid,created_at timestamptz,movement_type text,product_id uuid,product_name text,product_sku text,from_name text,to_name text,quantity integer,by_name text,notes text)
$$;
revoke all on function public.stock_history_page(jsonb,integer,integer,timestamptz),public.stock_history_table(jsonb,integer,integer,timestamptz),public.stock_history_options(text,text,integer),public.search_stock_movements(text,text,date,date,integer,integer) from public,anon;
grant execute on function public.stock_history_page(jsonb,integer,integer,timestamptz),public.stock_history_table(jsonb,integer,integer,timestamptz),public.stock_history_options(text,text,integer),public.search_stock_movements(text,text,date,date,integer,integer) to authenticated;
notify pgrst,'reload schema';
commit;
