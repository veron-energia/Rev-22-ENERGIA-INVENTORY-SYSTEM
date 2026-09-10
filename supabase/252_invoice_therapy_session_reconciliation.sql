begin;
-- Integrate the session sale added by 244 with the audited invoice lifecycle.
alter table public.customer_therapy_sessions
 add column quantity_refunded integer not null default 0 check(quantity_refunded>=0),
 add column quantity_cancelled integer not null default 0 check(quantity_cancelled>=0),
 add column paid_value_snapshot numeric(12,2),
 add column is_current boolean not null default true,
 add constraint therapy_session_available_quantity check(quantity_used+quantity_refunded+quantity_cancelled<=quantity_purchased);
alter table public.customer_therapy_sessions drop constraint customer_therapy_sessions_invoice_item_id_key;
create unique index therapy_session_current_line on public.customer_therapy_sessions(invoice_item_id) where is_current;
-- Historical rights stay intact. No paid amount is inferred during migration.
create table public.invoice_therapy_session_events(
 id uuid primary key default gen_random_uuid(),session_id uuid not null references public.customer_therapy_sessions(id),
 invoice_id uuid not null references public.invoices(id),request_id uuid,event_kind text not null,
 quantity integer not null, before_snapshot jsonb not null,reason text not null,
 created_at timestamptz not null default clock_timestamp(),created_by uuid references public.profiles(id));
alter table public.invoice_therapy_session_events enable row level security;
create policy invoice_therapy_session_events_read on public.invoice_therapy_session_events for select to authenticated
 using(exists(select 1 from public.invoices i where i.id=invoice_id and public.user_has_store_access(i.store_id)));
create table public.invoice_reopen_sessions(
 id uuid primary key default gen_random_uuid(),invoice_id uuid not null references public.invoices(id),
 session_id uuid not null references public.customer_therapy_sessions(id),request_id uuid not null,
 quantity integer not null check(quantity>0),applied_at timestamptz,unique(session_id,request_id));
alter table public.invoice_reopen_sessions enable row level security;
create policy invoice_reopen_sessions_read on public.invoice_reopen_sessions for select to authenticated
 using(exists(select 1 from public.invoices i where i.id=invoice_id and public.user_has_store_access(i.store_id)));

create or replace function public.create_therapy_sessions_for_invoice(p_invoice_id uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare inv public.invoices%rowtype; it record; count_created integer:=0;
begin
 select * into inv from public.invoices where id=p_invoice_id for update;
 if not found or inv.customer_id is null or inv.deleted_at is not null
  or inv.status not in ('paid','completed_foc') then return 0; end if;
 for it in select * from public.invoice_items where invoice_id=inv.id and therapy_service_id is not null order by id loop
  if exists(select 1 from public.customer_therapy_sessions where invoice_item_id=it.id and is_current) then continue; end if;
  insert into public.customer_therapy_sessions(customer_id,service_id,store_id,invoice_id,invoice_item_id,
   service_name_snapshot,service_minutes_snapshot,unit_price_snapshot,quantity_purchased,paid_value_snapshot,purchased_at)
  values(inv.customer_id,it.therapy_service_id,inv.store_id,inv.id,it.id,it.therapy_service_name_snapshot,
   it.therapy_service_minutes_snapshot,it.unit_price,it.quantity,public.invoice_discounted_line_value(it.id),coalesce(inv.paid_at,now()));
  count_created:=count_created+1;
 end loop;
 return count_created;
end $$;
revoke all on function public.create_therapy_sessions_for_invoice(uuid) from public,anon,authenticated;

create function public.refund_invoice_therapy_sessions(p_item_id uuid,p_amount numeric,p_reason text,p_request_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare s public.customer_therapy_sessions%rowtype; units integer; reserve integer;
begin
 select * into s from public.customer_therapy_sessions where invoice_item_id=p_item_id and is_current for update;
 if not found then raise exception 'Therapy session grant is missing; review the original payment and session evidence'; end if;
 if s.paid_value_snapshot is null or s.paid_value_snapshot<=0 then raise exception 'Original paid session value requires review before a refund'; end if;
 units:=round(p_amount*s.quantity_purchased/s.paid_value_snapshot)::integer;
 if units<=0 or units>s.quantity_purchased-s.quantity_used-s.quantity_refunded
  or round(s.paid_value_snapshot*(s.quantity_refunded+units)/s.quantity_purchased,2)-round(s.paid_value_snapshot*s.quantity_refunded/s.quantity_purchased,2)<>p_amount then
  raise exception 'Refund whole unused therapy sessions at their original paid value; % of % sessions remain refundable',s.quantity_purchased-s.quantity_used-s.quantity_refunded,s.quantity_purchased;
 end if;
 if exists(select 1 from public.invoice_reopen_sessions where session_id=s.id and applied_at is null) then raise exception 'Settle the reopened invoice before changing its queued sessions'; end if;
 reserve:=least(s.quantity_cancelled,units);
 insert into public.invoice_therapy_session_events(session_id,invoice_id,request_id,event_kind,quantity,before_snapshot,reason,created_by)
 values(s.id,s.invoice_id,p_request_id,'refund',-units,to_jsonb(s),p_reason,auth.uid());
 update public.customer_therapy_sessions set quantity_refunded=quantity_refunded+units,quantity_cancelled=quantity_cancelled-reserve,
  status=case when quantity_purchased-quantity_used-quantity_refunded-units-quantity_cancelled+reserve>0 then 'available'
    when quantity_used>0 then 'used' else 'refunded' end where id=s.id;
end $$;
revoke all on function public.refund_invoice_therapy_sessions(uuid,numeric,text,uuid) from public,anon,authenticated;

create function public.correct_invoice_therapy_sessions(p_invoice_id uuid,p_items jsonb,p_customer uuid,p_store uuid,p_reason text,p_request uuid)
returns void language plpgsql security definer set search_path=public as $$
declare s public.customer_therapy_sessions%rowtype; x jsonb; changed boolean; it public.invoice_items%rowtype;
begin
 for s in select * from public.customer_therapy_sessions where invoice_id=p_invoice_id and is_current order by id for update loop
  select value into x from jsonb_array_elements(p_items) where value->>'invoice_item_id'=s.invoice_item_id::text;
  select * into it from public.invoice_items where id=s.invoice_item_id;
  changed:=x is null or (nullif(x->>'therapy_service_id','')::uuid,(x->>'quantity')::integer,p_customer,p_store)
    is distinct from (s.service_id,s.quantity_purchased,s.customer_id,s.store_id);
  if not changed then continue; end if;
  if s.quantity_used>0 then raise exception 'Used therapy sessions must keep their original customer, service and invoice allocation; correct only unused purchases'; end if;
  if exists(select 1 from public.invoice_reopen_sessions where session_id=s.id and applied_at is null) then raise exception 'Settle the pending session reopening before changing its allocation'; end if;
  insert into public.invoice_therapy_session_events(session_id,invoice_id,request_id,event_kind,quantity,before_snapshot,reason,created_by)
   values(s.id,s.invoice_id,p_request,'correction',-(s.quantity_purchased-s.quantity_refunded-s.quantity_cancelled),to_jsonb(s),coalesce(p_reason,'Invoice correction'),auth.uid());
  update public.customer_therapy_sessions set is_current=false,status='cancelled',quantity_cancelled=quantity_purchased-quantity_refunded where id=s.id;
 end loop;
end $$;
revoke all on function public.correct_invoice_therapy_sessions(uuid,jsonb,uuid,uuid,text,uuid) from public,anon,authenticated;

create or replace function public.trg_create_therapy_sessions_on_paid()
returns trigger language plpgsql security definer set search_path=public as $$
declare s public.customer_therapy_sessions%rowtype; q record; unused integer;
begin
 if new.status in ('paid','completed_foc') then
  -- Only an explicit reopening queues reinstatement. An ordinary terminal edit
  -- cannot cause this branch to restore refunded or cancelled rights.
  for q in select * from public.invoice_reopen_sessions where invoice_id=new.id and applied_at is null order by id for update loop
   select * into s from public.customer_therapy_sessions where id=q.session_id for update;
   if not s.is_current or q.quantity<>s.quantity_refunded+s.quantity_cancelled then raise exception 'Therapy session reopening changed; reload its original evidence'; end if;
   insert into public.invoice_therapy_session_events(session_id,invoice_id,request_id,event_kind,quantity,before_snapshot,reason,created_by)
    values(s.id,new.id,q.request_id,'reopen',q.quantity,to_jsonb(s),'Explicit reopening settled',auth.uid());
   update public.customer_therapy_sessions set quantity_refunded=0,quantity_cancelled=0,status='available' where id=s.id;
   update public.invoice_reopen_sessions set applied_at=clock_timestamp() where id=q.id;
  end loop;
  perform public.create_therapy_sessions_for_invoice(new.id);
 end if;
 if new.status='cancelled' and old.status is distinct from new.status then
  for s in select * from public.customer_therapy_sessions where invoice_id=new.id and is_current order by id for update loop
   unused:=s.quantity_purchased-s.quantity_used-s.quantity_refunded-s.quantity_cancelled;
   if unused<=0 then continue; end if;
   insert into public.invoice_therapy_session_events(session_id,invoice_id,event_kind,quantity,before_snapshot,reason,created_by)
    values(s.id,new.id,'cancel',-unused,to_jsonb(s),'Invoice cancelled; payments remain separately recorded',auth.uid());
   update public.customer_therapy_sessions set quantity_cancelled=quantity_cancelled+unused,
    status=case when quantity_used>0 then 'used' else 'cancelled' end where id=s.id;
  end loop;
 end if;
 return null;
end $$;
revoke all on function public.trg_create_therapy_sessions_on_paid() from public,anon,authenticated;
drop trigger create_therapy_sessions_on_paid on public.invoices;
create trigger create_therapy_sessions_on_paid after update of status on public.invoices
 for each row execute function public.trg_create_therapy_sessions_on_paid();

-- Extend the canonical invoice matcher and builder; do not replace accumulated
-- financial guards or the new service creator in244.
do $$ declare f text; anchor text; replacement text; sig text; begin
 select pg_get_functiondef('public.invoice_line_matches(uuid,jsonb)'::regprocedure) into f;
 anchor:='''therapy_package_id'',''special_product_id''';
 if position(anchor in f)=0 then raise exception 'Unexpected line matcher'; end if;
 execute replace(f,anchor,'''therapy_package_id'',''therapy_service_id'',''special_product_id''');
 select pg_get_functiondef('public.invoice_benefit_price_only(uuid,jsonb)'::regprocedure) into f;
 execute replace(f,'it.line_kind in (''credit_package'',''premium_bundle'')','(it.line_kind in (''credit_package'',''premium_bundle'') or it.therapy_service_id is not null)');
 select pg_get_functiondef('public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)'::regprocedure) into f;
 anchor:='    elsif v_kind = ''therapy'' then'||chr(10)||'      if v_qty <> 1';
 replacement:=$patch$    elsif v_kind = 'therapy' and nullif(v_item->>'therapy_service_id','') is not null then
      if not public.therapy_service_available_at((v_item->>'therapy_service_id')::uuid,v_store_id) then raise exception 'Therapy session is not offered at this store'; end if;
      v_price:=public.therapy_service_price((v_item->>'therapy_service_id')::uuid,v_store_id);
      if v_price is null then raise exception 'Set a price for this therapy session'; end if;
      v_gross:=v_price*v_qty;
$patch$;
 if position(anchor in f)=0 then raise exception 'Unexpected session validator anchor'; end if;
 f:=replace(f,anchor,replacement||anchor);
 anchor:='    elsif v_kind = ''therapy'' then'||chr(10)||'      v_therapy_pkg := (v_item->>''therapy_package_id'')::uuid;';
 replacement:=$patch$    elsif v_kind = 'therapy' and nullif(v_item->>'therapy_service_id','') is not null then
      v_price:=coalesce((v_item->>'unit_price')::numeric,public.therapy_service_price((v_item->>'therapy_service_id')::uuid,v_store_id));
      v_gross:=v_price*v_qty;
      v_foc_amt:=case when v_foc_qty>0 then round(v_gross*v_foc_qty/v_qty,2) else 0 end;
      insert into public.invoice_items(id,invoice_id,line_kind,therapy_service_id,quantity,unit_price,line_total,price_mode,price_source,
       store_id_snapshot,original_price,therapy_service_name_snapshot,therapy_service_minutes_snapshot,
       foc_quantity,is_foc,foc_amount,foc_original_unit_price,foc_reason_id,foc_reason,foc_by,foc_at)
      select coalesce(nullif(v_item->>'invoice_item_id','')::uuid,gen_random_uuid()),p_invoice_id,'therapy',s.id,v_qty,v_price,v_gross-v_foc_amt,v_mode,'therapy',
       v_store_id,v_price,s.name,s.duration_minutes,v_foc_qty,v_foc_qty=v_qty,v_foc_amt,case when v_foc_qty>0 then v_price end,v_foc_rid,v_foc_resolved,
       case when v_foc_qty>0 then auth.uid() end,case when v_foc_qty>0 then now() end
      from public.therapy_services s where s.id=(v_item->>'therapy_service_id')::uuid
      on conflict(id) do update set therapy_package_id=null,therapy_service_id=excluded.therapy_service_id,quantity=excluded.quantity,
       unit_price=excluded.unit_price,line_total=excluded.line_total,therapy_service_name_snapshot=excluded.therapy_service_name_snapshot,
       therapy_service_minutes_snapshot=excluded.therapy_service_minutes_snapshot,foc_quantity=excluded.foc_quantity,is_foc=excluded.is_foc,
       foc_amount=excluded.foc_amount,foc_original_unit_price=excluded.foc_original_unit_price,foc_reason_id=excluded.foc_reason_id,
       foc_reason=excluded.foc_reason,foc_by=excluded.foc_by,foc_at=excluded.foc_at;
$patch$;
 if position(anchor in f)=0 then raise exception 'Unexpected session writer anchor'; end if;
 f:=replace(f,anchor,replacement||anchor);
 -- Switching an unissued session to a package must clear its discriminator.
 f:=replace(f,'therapy_package_id=excluded.therapy_package_id,quantity','therapy_package_id=excluded.therapy_package_id,therapy_service_id=null,quantity');
 f:=replace(f,'therapy_package_id=excluded.therapy_package_id, quantity','therapy_package_id=excluded.therapy_package_id, therapy_service_id=null, quantity');
 execute f;
 select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
 anchor:=' select coalesce(max(revision_no),0)+1 into v_rev';
 if position(anchor in f)=0 then raise exception 'Unexpected correction session guard'; end if;
 f:=replace(f,anchor,' perform public.correct_invoice_therapy_sessions(i.id,p_items,n.customer_id,n.store_id,p_reason,p_request_id);'||chr(10)||anchor);
 -- Existing sessions suppress duplicate grants during intermediate header updates.
 -- The final status update will create corrected unused allocations if settled.
 execute f;
 select pg_get_functiondef('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'::regprocedure) into f;
 anchor:='     elsif it.line_kind=''therapy'' then';
 if position(anchor in f)=0 then raise exception 'Unexpected therapy refund branch'; end if;
 execute replace(f,anchor,'     elsif it.therapy_service_id is not null then'||chr(10)||'       perform public.refund_invoice_therapy_sessions(it.id,v_amount,p_reason,p_request_id);'||chr(10)||anchor);
 select pg_get_functiondef('public.reopen_invoice(uuid,text,uuid)'::regprocedure) into f;
 anchor:=' n:=public.invoice_net_received(i.id);';
 if position(anchor in f)=0 then raise exception 'Unexpected session reopening anchor'; end if;
 execute replace(f,anchor,$patch$ insert into public.invoice_reopen_sessions(invoice_id,session_id,request_id,quantity)
 select i.id,s.id,p_request_id,s.quantity_refunded+s.quantity_cancelled from public.customer_therapy_sessions s
 where s.invoice_id=i.id and s.is_current and s.quantity_refunded+s.quantity_cancelled>0;
$patch$||anchor);
 foreach sig in array array['public.customer_therapy_session_balance(uuid)','public.therapy_customer_entitlements(uuid,date)'] loop
  select pg_get_functiondef(sig::regprocedure) into f;
  if position('s.quantity_purchased - s.quantity_used' in f)=0 then raise exception 'Unexpected session rights reader: %',sig; end if;
  execute replace(f,'s.quantity_purchased - s.quantity_used','s.quantity_purchased - s.quantity_used - s.quantity_refunded - s.quantity_cancelled');
 end loop;
end $$;
-- Add useful review information without changing existing refund/reopen fields.
alter function public.invoice_refund_options(uuid) rename to invoice_refund_options_before_sessions;
revoke all on function public.invoice_refund_options_before_sessions(uuid) from public,anon,authenticated;
create function public.invoice_refund_options(p_invoice_id uuid) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb; begin
 result:=public.invoice_refund_options_before_sessions(p_invoice_id);
 return result||jsonb_build_object('therapy_sessions',(select coalesce(jsonb_agg(jsonb_build_object(
  'invoice_item_id',s.invoice_item_id,'name',s.service_name_snapshot,'used',s.quantity_used,
  'unused',s.quantity_purchased-s.quantity_used-s.quantity_refunded,'paid_value',s.paid_value_snapshot,
  'max_refund',round(s.paid_value_snapshot*(s.quantity_purchased-s.quantity_used)/s.quantity_purchased,2)-round(s.paid_value_snapshot*s.quantity_refunded/s.quantity_purchased,2))),'[]')
  from public.customer_therapy_sessions s where s.invoice_id=p_invoice_id and s.is_current));
end $$;
revoke all on function public.invoice_refund_options(uuid) from public,anon;
grant execute on function public.invoice_refund_options(uuid) to authenticated;
alter function public.invoice_reopen_preview(uuid) rename to invoice_reopen_preview_before_sessions;
revoke all on function public.invoice_reopen_preview_before_sessions(uuid) from public,anon,authenticated;
create function public.invoice_reopen_preview(p_invoice_id uuid) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb; begin
 result:=public.invoice_reopen_preview_before_sessions(p_invoice_id);
 return result||jsonb_build_object('sessions_to_reinstate_after_settlement',(select coalesce(sum(quantity_refunded+quantity_cancelled),0)
  from public.customer_therapy_sessions where invoice_id=p_invoice_id and is_current));
end $$;
revoke all on function public.invoice_reopen_preview(uuid) from public,anon;
grant execute on function public.invoice_reopen_preview(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
