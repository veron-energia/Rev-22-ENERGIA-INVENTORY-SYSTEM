begin;
-- Reopening creates replacement voucher records. Redeemed/revoked originals
-- remain historical evidence, with an explicit link to the replacement.
create table public.invoice_reopen_vouchers(
 id uuid primary key default gen_random_uuid(),invoice_id uuid not null references public.invoices(id),
 benefit_id uuid not null references public.invoice_benefit_values(id),request_id uuid not null,
 quantity integer not null check(quantity>0),replacement_voucher_id uuid references public.customer_reward_vouchers(id),
 created_at timestamptz not null default now(),applied_at timestamptz,unique(invoice_id,request_id,benefit_id));
alter table public.invoice_reopen_vouchers enable row level security;
create policy reopen_vouchers_read on public.invoice_reopen_vouchers for select to authenticated using(
 exists(select 1 from public.invoices i where i.id=invoice_id and public.user_has_store_access(i.store_id)));

create or replace function public.invoice_voucher_reopen_candidates(p_invoice_id uuid)
returns table(benefit_id uuid,quantity integer)
language sql stable security definer set search_path=public as $$
 select b.id,least(b.granted_value,b.cancelled_unused_value+coalesce((
  select sum(round((z->>'amount')::numeric*b.granted_value/nullif(b.paid_value,0)))
  from public.invoice_refunds r cross join lateral jsonb_array_elements(coalesce(r.outcome->'lines','[]')) x
  cross join lateral jsonb_array_elements(coalesce(x->'benefits','[]')) z
  where r.invoice_id=i.id and z->>'benefit_id'=b.id::text and (i.reopened_at is null or r.created_at>i.reopened_at)),0))::int
 from public.invoice_benefit_values b join public.invoices i on i.id=b.invoice_id
 where b.invoice_id=p_invoice_id and b.reward_voucher_id is not null
$$;
create or replace function public.apply_reopened_invoice_vouchers()
returns trigger language plpgsql security definer set search_path=public as $$
declare q record; b public.invoice_benefit_values%rowtype; v public.customer_reward_vouchers%rowtype; replacement uuid;
begin
 if new.status not in ('paid','completed_foc') then return new; end if;
 for q in select * from public.invoice_reopen_vouchers where invoice_id=new.id and applied_at is null order by id for update loop
  select * into b from public.invoice_benefit_values where id=q.benefit_id for update;
  select * into v from public.customer_reward_vouchers where id=b.reward_voucher_id for update;
  if exists(select 1 from public.vouchers where id=v.voucher_id and qty_type='limited') then
   update public.voucher_store_stock set current_qty=current_qty-q.quantity where voucher_id=v.voucher_id and store_id=new.store_id and current_qty>=q.quantity;
   if not found then raise exception 'Not enough voucher stock to settle this reopened invoice'; end if;
  end if;
  insert into public.customer_reward_vouchers(customer_id,voucher_id,store_id,quantity,status,issued_by,source_type,source_id,notes)
   values(v.customer_id,v.voucher_id,new.store_id,q.quantity,'held',auth.uid(),'invoice_reopen',q.id,'Replacement after explicit reopening; original voucher '||v.id)
   returning id into replacement;
  insert into public.invoice_benefit_values(invoice_id,invoice_item_id,reward_voucher_id,paid_value,granted_value,evidence,created_by)
   values(new.id,b.invoice_item_id,replacement,round(b.paid_value*q.quantity/b.granted_value,2),q.quantity,
     'Reopened replacement; original recorded allocation '||b.id,auth.uid());
  update public.invoice_benefit_values set cancelled_unused_value=0 where id=b.id;
  update public.invoice_reopen_vouchers set replacement_voucher_id=replacement,applied_at=now() where id=q.id;
 end loop;
 return new;
end $$;
create trigger invoice_reopen_vouchers_settled after update of status on public.invoices for each row execute function public.apply_reopened_invoice_vouchers();
-- A damaged returned unit is no longer with the customer and needs replacement
-- on reopening. A not-returned unit remains with them and is not issued twice.
create or replace function public.invoice_stock_to_deduct(p_invoice_id uuid)
returns table(kind text,item_id uuid,quantity integer) language sql stable security definer set search_path=public as $$
 select r.kind,r.item_id,greatest(0,r.quantity-case when r.kind='product' then
 coalesce((select sum(case when m.movement_type::text='store_sale' then m.quantity else -m.quantity end)
 from public.stock_movements m where m.invoice_id=p_invoice_id and m.product_id=r.item_id
 and m.movement_type::text in ('store_sale','invoice_cancel_return','invoice_refund_return','refund_return')),0)
 -coalesce((select sum(d.damaged_quantity) from public.invoice_stock_dispositions d join public.stock_movements m on m.id=d.movement_id
 where d.invoice_id=p_invoice_id and m.product_id=r.item_id),0)
 else coalesce((select sum(m.quantity) from public.invoice_voucher_movements m where m.invoice_id=p_invoice_id and m.voucher_id=r.item_id),0) end)::int
 from public.invoice_required_stock(p_invoice_id) r
$$;

do $$ declare f text; a int; z int; anchor text; begin
 select pg_get_functiondef('public.invoice_reopen_preview(uuid)'::regprocedure) into f;
 a:=position(' if exists(select 1 from public.invoice_stock_dispositions' in f);
 z:=position(' select coalesce(sum(l.amount),0) into credits' in f);
 if a=0 or z<=a then raise exception 'Unexpected reopening preview definition'; end if;
 f:=substr(f,1,a-1)||substr(f,z);
 f:=replace(f,'''credit_to_reinstate_after_settlement'',credits,',
  '''credit_to_reinstate_after_settlement'',credits,''voucher_units_to_reinstate_after_settlement'',(select coalesce(sum(quantity),0) from public.invoice_voucher_reopen_candidates(i.id)),');
 f:=replace(f,'coalesce(jsonb_agg(to_jsonb(s)),''[]'')',
  'coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object(''item_name'',case when s.kind=''product'' then (select name from public.products where id=s.item_id) else (select name from public.vouchers where id=s.item_id) end)),''[]'')');
 execute f;
 select pg_get_functiondef('public.reopen_invoice(uuid,text,uuid)'::regprocedure) into f;
 anchor:=' n:=public.invoice_net_received(i.id);';
 if position(anchor in f)=0 then raise exception 'Unexpected reopening definition'; end if;
 execute replace(f,anchor,
  ' insert into public.invoice_reopen_vouchers(invoice_id,benefit_id,request_id,quantity)'||chr(10)||
  ' select i.id,c.benefit_id,p_request_id,c.quantity from public.invoice_voucher_reopen_candidates(i.id) c where c.quantity>0;'||chr(10)||anchor);
end $$;
revoke all on function public.invoice_voucher_reopen_candidates(uuid),public.apply_reopened_invoice_vouchers(),public.invoice_stock_to_deduct(uuid) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
