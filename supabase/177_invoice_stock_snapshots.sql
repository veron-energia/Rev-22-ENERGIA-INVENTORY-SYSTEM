begin;
alter table public.invoices add column if not exists stock_snapshot_version integer;
alter table public.invoices alter column stock_snapshot_version set default 1;
create table public.invoice_stock_components(
 id uuid primary key default gen_random_uuid(),invoice_item_id uuid not null references public.invoice_items(id) on delete cascade,
 kind text not null check(kind in ('product','voucher')),item_id uuid not null,
 quantity integer not null check(quantity>0),component_source text not null check(component_source in ('fixed','selection')),
 unique(invoice_item_id,kind,item_id,component_source));
alter table public.invoice_stock_components enable row level security;
create policy invoice_components_read on public.invoice_stock_components for select to authenticated using(
 exists(select 1 from public.invoice_items it join public.invoices i on i.id=it.invoice_id where it.id=invoice_item_id and public.user_has_store_access(i.store_id)));
create table public.invoice_voucher_movements(
 id uuid primary key default gen_random_uuid(),invoice_id uuid not null references public.invoices(id),
 voucher_id uuid not null references public.vouchers(id),store_id uuid not null references public.stores(id),
 quantity integer not null check(quantity<>0),reason text not null,created_by uuid references public.profiles(id),created_at timestamptz not null default now());
alter table public.invoice_voucher_movements enable row level security;
create policy invoice_voucher_movements_read on public.invoice_voucher_movements for select to authenticated using(public.user_has_store_access(store_id));

create or replace function public.capture_invoice_stock_components()
returns trigger language plpgsql security definer set search_path=public as $$
declare it public.invoice_items%rowtype; v_id uuid;
begin
 if tg_table_name='invoice_items' then
  if tg_op='UPDATE' then
   if (new.line_kind,new.product_id,new.voucher_id,new.promotion_id,new.premium_bundle_id) is not distinct from
      (old.line_kind,old.product_id,old.voucher_id,old.promotion_id,old.premium_bundle_id) then
    if new.quantity<>old.quantity then
      update public.invoice_stock_components set quantity=quantity/old.quantity*new.quantity
       where invoice_item_id=new.id and component_source='fixed';
    end if;
    return new;
   end if;
  end if;
  it:=new;
  if not exists(select 1 from public.invoices where id=it.invoice_id and stock_snapshot_version=1) then return new; end if;
  delete from public.invoice_stock_components where invoice_item_id=it.id and component_source='fixed';
  if it.line_kind='product' and it.product_id is not null then
   insert into public.invoice_stock_components(invoice_item_id,kind,item_id,quantity,component_source) values(it.id,'product',it.product_id,it.quantity,'fixed');
  elsif it.line_kind='voucher' and exists(select 1 from public.vouchers where id=it.voucher_id and qty_type='limited') then
   insert into public.invoice_stock_components(invoice_item_id,kind,item_id,quantity,component_source) values(it.id,'voucher',it.voucher_id,it.quantity,'fixed');
  elsif it.line_kind='promotion' and it.promotion_id is not null then
   insert into public.invoice_stock_components(invoice_item_id,kind,item_id,quantity,component_source)
    select it.id,r.kind,r.item_id,sum(r.quantity)::int,'fixed' from public.promotion_stock_items(it.promotion_id,it.quantity) r group by r.kind,r.item_id;
  end if;
  return new;
 end if;
 v_id:=case when tg_op='DELETE' then old.invoice_item_id else new.invoice_item_id end;
 select * into it from public.invoice_items where id=v_id;
 if exists(select 1 from public.invoices where id=it.invoice_id and stock_snapshot_version=1) then
  delete from public.invoice_stock_components where invoice_item_id=v_id and component_source='selection';
  insert into public.invoice_stock_components(invoice_item_id,kind,item_id,quantity,component_source)
   select v_id,case when s.product_id is not null then 'product' else 'voucher' end,coalesce(s.product_id,s.voucher_id),sum(s.quantity)::int,'selection'
   from public.invoice_promotion_selections s left join public.vouchers v on v.id=s.voucher_id
   where s.invoice_item_id=v_id and (s.product_id is not null or v.qty_type='limited')
   group by s.product_id,s.voucher_id;
 end if;
 return coalesce(new,old);
end $$;
create trigger invoice_stock_components_capture after insert or update on public.invoice_items for each row execute function public.capture_invoice_stock_components();
create trigger invoice_stock_selections_capture after insert or update or delete on public.invoice_promotion_selections for each row execute function public.capture_invoice_stock_components();

-- Keep the original expansion only as a legacy reader. New invoices use the
-- components captured when each line/selection was saved.
alter function public.invoice_required_stock(uuid) rename to invoice_required_stock_legacy;
revoke all on function public.invoice_required_stock_legacy(uuid) from public,anon,authenticated;
create or replace function public.invoice_required_stock(p_invoice_id uuid)
returns table(kind text,item_id uuid,quantity integer)
language plpgsql stable security definer set search_path=public as $$
begin
 if exists(select 1 from public.invoices where id=p_invoice_id and stock_snapshot_version=1) then
  return query select c.kind,c.item_id,sum(c.quantity)::int from public.invoice_stock_components c
   join public.invoice_items it on it.id=c.invoice_item_id where it.invoice_id=p_invoice_id group by c.kind,c.item_id;
 else
  return query select r.kind,r.item_id,r.quantity from public.invoice_required_stock_legacy(p_invoice_id) r;
 end if;
end $$;
create or replace function public.deduct_invoice_stock(p_invoice_id uuid,p_note text default null)
returns integer language plpgsql security definer set search_path=public as $$
declare i public.invoices%rowtype; r record; n int:=0; v_qty int;
begin
 select * into i from public.invoices where id=p_invoice_id for update;
 for r in select * from public.invoice_stock_to_deduct(i.id) order by kind,item_id loop
  if r.quantity<=0 then continue; end if;
  if r.kind='product' then
   update public.store_inventory set current_qty=current_qty-r.quantity,updated_at=now()
    where store_id=i.store_id and product_id=r.item_id and current_qty>=r.quantity;
   if not found then raise exception 'Not enough stock for invoice product %',r.item_id; end if;
   insert into public.stock_movements(product_id,movement_type,from_store_id,invoice_id,quantity,notes,created_by)
    values(r.item_id,'store_sale',i.store_id,i.id,r.quantity,coalesce(p_note,'Invoice issue'),auth.uid());
  else
   update public.voucher_store_stock set current_qty=current_qty-r.quantity,updated_at=now()
    where store_id=i.store_id and voucher_id=r.item_id and current_qty>=r.quantity;
   if not found then raise exception 'Not enough voucher stock'; end if;
   insert into public.invoice_voucher_movements(invoice_id,voucher_id,store_id,quantity,reason,created_by)
    values(i.id,r.item_id,i.store_id,r.quantity,coalesce(p_note,'Invoice voucher issue'),auth.uid());
  end if;
  n:=n+1;
 end loop;
 return n;
end $$;
create or replace function public.invoice_stock_to_deduct(p_invoice_id uuid)
returns table(kind text,item_id uuid,quantity integer) language sql stable security definer set search_path=public as $$
 select r.kind,r.item_id,greatest(0,r.quantity-case when r.kind='product' then coalesce((
  select sum(case when m.movement_type::text='store_sale' then m.quantity else -m.quantity end)
  from public.stock_movements m where m.invoice_id=p_invoice_id and m.product_id=r.item_id
   and m.movement_type::text in ('store_sale','invoice_cancel_return','invoice_refund_return','refund_return')),0)
  else coalesce((select sum(m.quantity) from public.invoice_voucher_movements m where m.invoice_id=p_invoice_id and m.voucher_id=r.item_id),0) end)::int
 from public.invoice_required_stock(p_invoice_id) r
$$;
-- One deduction path for payment and corrections; removes the second, divergent
-- stock writer in pay_invoice while retaining the existing settlement triggers.
do $$
declare f text; a int; b int;
begin
 select pg_get_functiondef('public.invoice_record_payments_internal(uuid,jsonb)'::regprocedure) into f;
 a:=position('    -- 15. Deduct stock.' in f); b:=position('    -- 16. Mark paid + lock.' in f);
 if a=0 or b<=a then raise exception 'Unexpected payment stock function; review migration source before continuing'; end if;
 f:=substr(f,1,a-1)||'    perform public.deduct_invoice_stock(p_invoice_id,''Invoice payment settled'');'||chr(10)||substr(f,b);
 f:=replace(f,'    loop'||chr(10)||'      if v_req.kind', '    loop'||chr(10)||'      if v_req.quantity<=0 then continue; end if;'||chr(10)||'      if v_req.kind');
 execute f;
end $$;
revoke all on function public.capture_invoice_stock_components(),public.deduct_invoice_stock(uuid,text),public.invoice_required_stock(uuid) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
