begin;
-- A correction posts an outgoing/incoming pair. It never changes ownership
-- or the grant amount of an existing credit lot or a redeemed voucher.
create table public.invoice_benefit_transfers(
 id uuid primary key default gen_random_uuid(),invoice_id uuid not null references public.invoices(id),
 source_benefit_id uuid not null references public.invoice_benefit_values(id),
 replacement_benefit_id uuid references public.invoice_benefit_values(id),
 customer_id uuid not null references public.customers(id),store_id uuid not null references public.stores(id),
 transferred_value numeric(12,2) not null check(transferred_value>0),
 request_id uuid not null,request_hash text not null,reason text not null,
 before_snapshot jsonb not null,after_snapshot jsonb,
 created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),
 unique(invoice_id,request_id));
alter table public.invoice_benefit_transfers enable row level security;
create policy invoice_benefit_transfers_read on public.invoice_benefit_transfers for select to authenticated using(
 exists(select 1 from public.invoices i where i.id=invoice_id and public.user_has_store_access(i.store_id)));

create function public.transfer_invoice_unused_benefit(p_benefit_id uuid,p_customer_id uuid,p_store_id uuid,p_reason text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare b public.invoice_benefit_values%rowtype; i public.invoices%rowtype;
 l public.customer_credit_lots%rowtype; v public.customer_reward_vouchers%rowtype;
 t public.invoice_benefit_transfers%rowtype; moved numeric; wallet uuid; replacement uuid;
 new_benefit uuid; transfer_id uuid:=gen_random_uuid(); h text; old_snapshot jsonb; new_snapshot jsonb;
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can correct benefit recipients'; end if;
 if nullif(trim(p_reason),'') is null or p_request_id is null then raise exception 'A reason and request ID are required'; end if;
 select * into b from public.invoice_benefit_values where id=p_benefit_id;
 select * into i from public.invoices where id=b.invoice_id for update;
 if not found or i.deleted_at is not null or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 if not public.user_has_store_access(p_store_id) then raise exception 'No access to the destination store'; end if;
 h:=md5(jsonb_build_object('benefit',p_benefit_id,'customer',p_customer_id,'store',p_store_id,'reason',p_reason)::text);
 select * into t from public.invoice_benefit_transfers where invoice_id=i.id and request_id=p_request_id;
 if found then
  if t.request_hash<>h then raise exception 'This transfer request ID was already used for different details'; end if;
  return jsonb_build_object('success',true,'replayed',true,'transferred_value',t.transferred_value,'benefit_id',t.replacement_benefit_id);
 end if;
 if not exists(select 1 from public.customers where id=p_customer_id and deleted_at is null) then raise exception 'Choose a non-deleted recipient'; end if;
 if i.status in ('cancelled','refunded','cancellation_requested','refund_requested') then
  raise exception 'Resolve the invoice status and explicitly reopen it before moving spendable benefits'; end if;
 if exists(select 1 from public.invoice_reopen_benefits where invoice_id=i.id and applied_at is null)
  or exists(select 1 from public.invoice_reopen_vouchers where invoice_id=i.id and applied_at is null) then
  raise exception 'Settle the reopened invoice before moving its reinstated benefits'; end if;
 select * into b from public.invoice_benefit_values where id=p_benefit_id for update;
 if b.cancelled_unused_value>0 then raise exception 'Resolve reserved cancelled benefits before moving this allocation'; end if;
 if b.lot_id is not null then
  select * into l from public.customer_credit_lots where id=b.lot_id for update;
  if l.status<>'active' or l.is_locked then raise exception 'This credit lot is locked or reversed'; end if;
  if (l.customer_id,l.store_id) is not distinct from (p_customer_id,p_store_id) then raise exception 'Choose a different recipient or store'; end if;
  moved:=l.remaining_amount; old_snapshot:=to_jsonb(l);
 else
  select * into v from public.customer_reward_vouchers where id=b.reward_voucher_id for update;
  if v.status<>'held' then raise exception 'Only unused held vouchers can move; redeemed records remain with their original recipient'; end if;
  if (v.customer_id,v.store_id) is not distinct from (p_customer_id,p_store_id) then raise exception 'Choose a different recipient or store'; end if;
  moved:=v.quantity; old_snapshot:=to_jsonb(v);
 end if;
 if moved is null or moved<=0 then raise exception 'No unused value remains to move'; end if;
 insert into public.invoice_benefit_transfers(id,invoice_id,source_benefit_id,customer_id,store_id,transferred_value,request_id,request_hash,reason,before_snapshot,created_by)
  values(transfer_id,i.id,b.id,p_customer_id,p_store_id,moved,p_request_id,h,p_reason,old_snapshot,auth.uid());
 replacement:=gen_random_uuid();
 if b.lot_id is not null then
  insert into public.customer_credit_wallets(customer_id) values(p_customer_id) on conflict(customer_id) do nothing;
  select id into wallet from public.customer_credit_wallets where customer_id=p_customer_id;
  update public.customer_credit_lots set remaining_amount=0,updated_at=now() where id=l.id;
  insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
   values(l.wallet_id,l.customer_id,'adjust_decrease',l.category,moved,l.id,'invoice_benefit_transfer_out',transfer_id,l.store_id,p_reason,auth.uid(),auth.uid());
  -- Carry eligibility, expiry/restrictions and original purchase date, so a
  -- recipient correction cannot turn bonus credit into unrestricted paid credit.
  insert into public.customer_credit_lots select (jsonb_populate_record(null::public.customer_credit_lots,to_jsonb(l)||jsonb_build_object(
   'id',replacement,'wallet_id',wallet,'customer_id',p_customer_id,'store_id',p_store_id,
   'original_amount',moved,'remaining_amount',moved,'source_type','invoice_benefit_transfer','source_record_id',transfer_id,
   'reference_no',null,'reason',p_reason,'reversal_of_lot_id',null,'created_by',auth.uid(),'approved_by',auth.uid(),'created_at',now(),'updated_at',now()))).*;
  insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
   values(wallet,p_customer_id,'grant',l.category,moved,replacement,'invoice_benefit_transfer_in',transfer_id,p_store_id,p_reason,auth.uid(),auth.uid());
  select to_jsonb(q) into new_snapshot from public.customer_credit_lots q where id=replacement;
 else
  if v.store_id is distinct from p_store_id and exists(select 1 from public.vouchers where id=v.voucher_id and qty_type='limited') then
   update public.voucher_store_stock set current_qty=current_qty-v.quantity where voucher_id=v.voucher_id and store_id=p_store_id and current_qty>=v.quantity;
   if not found then raise exception 'Not enough voucher stock at the destination store'; end if;
   insert into public.voucher_store_stock(voucher_id,store_id,current_qty) values(v.voucher_id,v.store_id,v.quantity)
    on conflict(voucher_id,store_id) do update set current_qty=public.voucher_store_stock.current_qty+excluded.current_qty;
  end if;
  update public.customer_reward_vouchers set status='revoked',notes=concat_ws(E'\n',notes,'Unused units moved by invoice correction '||transfer_id) where id=v.id;
  insert into public.customer_reward_vouchers(id,customer_id,voucher_id,store_id,quantity,status,issued_by,source_type,source_id,notes)
   values(replacement,p_customer_id,v.voucher_id,p_store_id,v.quantity,'held',auth.uid(),'invoice_benefit_transfer',transfer_id,'Original voucher '||v.id||': '||p_reason);
  select to_jsonb(q) into new_snapshot from public.customer_reward_vouchers q where id=replacement;
 end if;
 insert into public.invoice_benefit_values(invoice_id,invoice_item_id,lot_id,reward_voucher_id,paid_value,granted_value,evidence,created_by)
  values(i.id,b.invoice_item_id,case when b.lot_id is not null then replacement end,case when b.reward_voucher_id is not null then replacement end,
   round(b.paid_value*moved/b.granted_value,2),moved,'Unused portion transferred from recorded allocation '||b.id||'; transfer '||transfer_id,auth.uid()) returning id into new_benefit;
 update public.invoice_benefit_transfers set replacement_benefit_id=new_benefit,after_snapshot=new_snapshot where id=transfer_id;
 update public.invoices set edit_count=coalesce(edit_count,0)+1,edited_at=now(),edited_by=auth.uid() where id=i.id;
 perform public.write_audit_ex('invoices',i.id,'unused_benefit_recipient_corrected',old_snapshot,new_snapshot,'invoices',p_reason,i.store_id);
 return jsonb_build_object('success',true,'transferred_value',moved,'benefit_id',new_benefit);
end $$;
revoke all on function public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid) from public,anon;
grant execute on function public.transfer_invoice_unused_benefit(uuid,uuid,uuid,text,uuid) to authenticated;
-- Distinguish the buyer on the invoice from actual gifted/split recipients.
-- Header corrections require an explicit acknowledgement of retained recipients.
do $$ declare f text; anchor text; begin
 select pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure) into f;
 anchor:=' if (not same_lines or n.customer_id<>i.customer_id) and exists(select 1 from public.invoice_items it where it.invoice_id=i.id';
 if position(anchor in f)=0 then raise exception 'Unexpected issued-benefit header guard'; end if;
 f:=replace(f,anchor,' if not same_lines and exists(select 1 from public.invoice_items it where it.invoice_id=i.id');
 f:=replace(f,'and it.credit_issued_at is not null and (n.customer_id<>i.customer_id or not exists(', 'and it.credit_issued_at is not null and (not exists(');
 anchor:=' if n.customer_id<>i.customer_id and exists(select 1 from public.invoice_line_credit_allocations';
 if position(anchor in f)=0 then raise exception 'Unexpected wallet customer guard'; end if;
 f:=replace(f,anchor,$patch$ if (n.customer_id,n.store_id) is distinct from (i.customer_id,i.store_id)
   and exists(select 1 from public.invoice_items where invoice_id=i.id and credit_issued_at is not null)
   and not coalesce((p_header->>'preserve_issued_recipients')::boolean,false) then
  raise exception 'Review the issued recipients first. Move unused benefits in Invoice settlement if needed, then explicitly confirm that the recorded recipients and benefit stores should remain unchanged.';
 end if;
$patch$||anchor);
 execute f;
 -- Expose both ownership and original allocated values for a concrete preview.
 select pg_get_functiondef('public.invoice_refund_options(uuid)'::regprocedure) into f;
 anchor:='''customer_name'',c.full_name,';
 if position(anchor in f)=0 then raise exception 'Unexpected benefit preview definition'; end if;
 execute replace(f,anchor,anchor||'''customer_id'',c.id,''store_id'',coalesce(l.store_id,v.store_id),''benefit_kind'',case when l.id is not null then l.category else ''voucher'' end,');
end $$;
notify pgrst,'reload schema';
commit;
