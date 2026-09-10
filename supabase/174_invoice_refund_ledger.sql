begin;
-- Attach exact payment provenance to new wallet allocations. Existing ambiguous
-- allocation history remains NULL and is reported instead of assigned arbitrarily.
alter table public.invoice_line_credit_allocations add column if not exists payment_id uuid references public.invoice_payments(id) deferrable initially deferred;
create table public.invoice_stock_dispositions(
 id uuid primary key default gen_random_uuid(), invoice_id uuid not null references public.invoices(id),
 movement_id uuid not null references public.stock_movements(id), request_id uuid not null,
 sellable_quantity integer not null default 0 check(sellable_quantity>=0),
 damaged_quantity integer not null default 0 check(damaged_quantity>=0),
 not_returned_quantity integer not null default 0 check(not_returned_quantity>=0),
 reason text not null, created_by uuid references public.profiles(id),created_at timestamptz not null default now(),
 unique(invoice_id,request_id,movement_id),
 check(sellable_quantity+damaged_quantity+not_returned_quantity>0));
alter table public.invoice_stock_dispositions enable row level security;
create policy invoice_stock_dispositions_read on public.invoice_stock_dispositions for select to authenticated
 using(exists(select 1 from public.invoices i where i.id=invoice_id and public.user_has_store_access(i.store_id)));

-- Recorded paid-value allocations for compound benefits. Legacy bundles that
-- sold vouchers plus credit must have documentary evidence before allocating
-- their payment between those components. This table stores that evidence.
create table public.invoice_benefit_values(
 id uuid primary key default gen_random_uuid(),invoice_id uuid not null references public.invoices(id),
 invoice_item_id uuid not null references public.invoice_items(id),
 lot_id uuid references public.customer_credit_lots(id),reward_voucher_id uuid references public.customer_reward_vouchers(id),
 paid_value numeric(12,2) not null check(paid_value>=0),granted_value numeric(12,2) not null check(granted_value>0),
 evidence text not null,created_by uuid references public.profiles(id),created_at timestamptz not null default now(),
 check((lot_id is not null)::int+(reward_voucher_id is not null)::int=1));
create unique index invoice_benefit_lot_unique on public.invoice_benefit_values(lot_id) where lot_id is not null;
create unique index invoice_benefit_voucher_unique on public.invoice_benefit_values(reward_voucher_id) where reward_voucher_id is not null;
alter table public.invoice_benefit_values enable row level security;
create policy invoice_benefit_values_read on public.invoice_benefit_values for select to authenticated
 using(exists(select 1 from public.invoices i where i.id=invoice_id and public.user_has_store_access(i.store_id)));

create or replace function public.invoice_refund_options(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare i public.invoices%rowtype;
begin
 select * into i from public.invoices where id=p_invoice_id;
 if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 return jsonb_build_object('financial',public.invoice_financial_position(i.id),
 'sources',(select coalesce(jsonb_agg(jsonb_build_object('payment_id',p.id,'method',m.name,'wallet',m.is_wallet_credit,
   'remaining',p.amount-coalesce((select sum(r.amount) from public.invoice_refunds r where r.payment_id=p.id),0))),'[]')
   from public.invoice_payments p join public.payment_methods m on m.id=p.payment_method_id where p.invoice_id=i.id
   and p.entry_kind<>'correction_reversal' and not exists(select 1 from public.invoice_payments v where v.corrects_payment_id=p.id and v.entry_kind='correction_reversal')),
 'stock',(select coalesce(jsonb_agg(jsonb_build_object('movement_id',m.id,'product_id',m.product_id,'product_name',p.name,
   'store_id',m.from_store_id,'quantity',m.quantity,'resolved_quantity',coalesce((select sum(d.sellable_quantity+d.damaged_quantity+d.not_returned_quantity)
     from public.invoice_stock_dispositions d where d.movement_id=m.id),0))),'[]')
   from public.stock_movements m join public.products p on p.id=m.product_id where m.invoice_id=i.id and m.movement_type::text='store_sale'),
 'review_required',exists(select 1 from public.invoice_refunds where invoice_id=i.id and payment_id is null),
 'benefits',(select coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object('remaining_value',l.remaining_amount,
    'max_refund',round(b.paid_value*l.remaining_amount/b.granted_value,2))),'[]')
   from public.invoice_benefit_values b left join public.customer_credit_lots l on l.id=b.lot_id where b.invoice_id=i.id));
end $$;

create or replace function public.refund_invoice_recorded(
 p_invoice_id uuid,p_lines jsonb,p_sources jsonb,p_stock jsonb,p_reason text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare i public.invoices%rowtype; it public.invoice_items%rowtype; p public.invoice_payments%rowtype;
 m public.payment_methods%rowtype; b public.invoice_benefit_values%rowtype; l public.customer_credit_lots%rowtype;
 x jsonb; z jsonb; v_amount numeric; v_total numeric:=0; v_source_total numeric:=0; v_remaining numeric;
 v_line_paid numeric; v_refunded numeric; v_grant numeric; v_revoke numeric; a record; v_left numeric; v_take numeric;
 sm public.stock_movements%rowtype; sq int; dq int; nq int; v_resolved int; v_first boolean:=true;
 v_payload jsonb; v_hash text; v_request uuid; v_entry uuid; rv public.customer_reward_vouchers%rowtype; v_units int; v_reserved numeric;
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can record a refund'; end if;
 if nullif(trim(p_reason),'') is null or p_request_id is null then raise exception 'Refund reason and request ID are required'; end if;
 select * into i from public.invoices where id=p_invoice_id for update;
 if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 v_payload:=jsonb_build_object('lines',p_lines,'sources',p_sources,'stock',p_stock,'reason',p_reason);
 v_hash:=md5(v_payload::text);
 if exists(select 1 from public.invoice_refunds where invoice_id=i.id and request_id=p_request_id) then
   if not exists(select 1 from public.invoice_refunds where invoice_id=i.id and request_id=p_request_id and outcome->>'hash'=v_hash) then
     raise exception 'This refund request ID was already used for different details'; end if;
   return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'replayed',true);
 end if;
 if exists(select 1 from public.invoice_refunds where invoice_id=i.id and payment_id is null) then
   raise exception 'Historical refunds need payment-source review before another refund'; end if;
 if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_typeof(p_sources) is distinct from 'array'
   or jsonb_array_length(p_lines)=0 or jsonb_array_length(p_sources)=0 then raise exception 'Allocate the refund to lines and original payment sources'; end if;
 if exists(select j.value->>'invoice_item_id' from jsonb_array_elements(p_lines) j(value) group by 1 having count(*)>1) then raise exception 'Submit each refund line once'; end if;
 for x in select * from jsonb_array_elements(p_lines) loop
   v_amount:=round((x->>'amount')::numeric,2);
   if v_amount is null or v_amount<=0 then raise exception 'Refund amount must be positive'; end if;
   it:=null;
   if nullif(x->>'invoice_item_id','') is null then
     if exists(select 1 from public.invoice_items where invoice_id=i.id and credit_issued_at is not null) then
       raise exception 'Allocate a correction refund to the original unused purchased benefits; it cannot be cashed out as an unallocated overpayment'; end if;
     if v_amount>greatest(public.invoice_net_received(i.id)-i.total_amount,0) then raise exception 'Amount exceeds the correction refund due'; end if;
   else
     select * into it from public.invoice_items where id=(x->>'invoice_item_id')::uuid and invoice_id=i.id for update;
     if not found then raise exception 'Refund line does not belong to this invoice'; end if;
     v_line_paid:=coalesce(public.invoice_discounted_line_value(it.id),0);
     select coalesce(sum((e->>'amount')::numeric),0) into v_refunded from public.invoice_refunds r,
       jsonb_array_elements(coalesce(r.outcome->'lines','[]')) e where r.invoice_id=i.id and (i.reopened_at is null or r.created_at>i.reopened_at) and e->>'invoice_item_id'=it.id::text;
     if coalesce((x->>'overpayment')::boolean,false) then
       if it.line_kind not in ('credit_package','premium_bundle') or v_amount>greatest(public.invoice_net_received(i.id)-i.total_amount,0) then
         raise exception 'Allocate correction overpayments to unused purchased benefits within the refund due'; end if;
     elsif v_amount>greatest(v_line_paid-v_refunded,0) then raise exception 'Refund exceeds the remaining discounted line value'; end if;
     if it.line_kind in ('credit_package','premium_bundle') then
       if jsonb_typeof(x->'benefits') is distinct from 'array' or jsonb_array_length(x->'benefits')=0 then
         raise exception 'Select recorded unused benefit allocations for this credit/bundle refund'; end if;
       if (select sum((q->>'amount')::numeric) from jsonb_array_elements(x->'benefits') q)<>v_amount then raise exception 'Benefit refunds must equal the line refund'; end if;
       for z in select * from jsonb_array_elements(x->'benefits') loop
         select * into b from public.invoice_benefit_values where id=(z->>'benefit_id')::uuid and invoice_item_id=it.id for update;
         if not found then raise exception 'Recorded benefit allocation not found; historical allocations require review'; end if;
         if b.lot_id is not null then
           select * into l from public.customer_credit_lots where id=b.lot_id for update;
           v_grant:=(z->>'amount')::numeric;
           if v_grant is null or v_grant<=0 or b.paid_value<=0 or v_grant>round(b.paid_value*(l.remaining_amount+b.cancelled_unused_value)/b.granted_value,2) then
             raise exception 'Refund exceeds the unused paid value of this benefit'; end if;
           v_revoke:=least(l.remaining_amount+b.cancelled_unused_value,round(v_grant*b.granted_value/b.paid_value,2));
           v_reserved:=least(b.cancelled_unused_value,v_revoke);
           update public.invoice_benefit_values set cancelled_unused_value=cancelled_unused_value-v_reserved where id=b.id;
           v_revoke:=v_revoke-v_reserved;
           update public.customer_credit_lots set remaining_amount=remaining_amount-v_revoke,updated_at=now() where id=l.id;
           if v_revoke>0 then
           insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,created_by,approved_by)
            values(l.wallet_id,l.customer_id,'adjust_decrease',l.category,v_revoke,l.id,'invoice_benefit_refund',p_request_id,l.store_id,p_reason,auth.uid(),auth.uid());
           end if;
         else
           select * into rv from public.customer_reward_vouchers where id=b.reward_voucher_id for update;
           v_grant:=(z->>'amount')::numeric;
           v_remaining:=case when rv.status='held' then rv.quantity else 0 end+b.cancelled_unused_value;
           if v_grant is null or v_grant<=0 or b.paid_value<=0 or v_grant>round(b.paid_value*v_remaining/b.granted_value,2) then
             raise exception 'Refund exceeds the unused paid value of this voucher'; end if;
           v_units:=round(v_grant*b.granted_value/b.paid_value)::int;
           if v_units<=0 or round(v_units*b.paid_value/b.granted_value,2)<>v_grant then
             raise exception 'Voucher refund must cover whole unused units at their allocated paid value'; end if;
           v_reserved:=least(b.cancelled_unused_value,v_units);
           update public.invoice_benefit_values set cancelled_unused_value=cancelled_unused_value-v_reserved where id=b.id;
           v_units:=v_units-v_reserved::int;
           if v_units>0 then
             update public.customer_reward_vouchers set status=case when quantity=v_units then 'revoked' else status end,
               quantity=case when quantity=v_units then quantity else quantity-v_units end,
               notes=concat_ws(E'\n',notes,'Refunded '||v_units||' unused unit(s): '||p_reason) where id=rv.id;
             if exists(select 1 from public.vouchers where id=rv.voucher_id and qty_type='limited') then
               update public.voucher_store_stock set current_qty=current_qty+v_units where store_id=rv.store_id and voucher_id=rv.voucher_id;
             end if;
             perform public.write_audit_ex('customer_reward_vouchers',rv.id,'unused_voucher_refund',to_jsonb(rv),
               jsonb_build_object('revoked_units',v_units,'request_id',p_request_id),'refunds',p_reason,rv.store_id);
           end if;
         end if;
       end loop;
     elsif it.line_kind='therapy' then
       if exists(select 1 from public.purchased_therapy_entitlements where invoice_item_id=it.id and status in ('active','expired')) then
         raise exception 'Consumed or activated therapy cannot be refunded'; end if;
       if v_amount<>greatest(v_line_paid-v_refunded,0) then raise exception 'Refund the whole unused therapy entitlement'; end if;
       update public.purchased_therapy_entitlements set status='refunded',updated_at=now() where invoice_item_id=it.id and status in ('pending_activation','scheduled');
     end if;
   end if;
   if it.id is not null and it.line_kind in ('product','promotion') and jsonb_array_length(coalesce(p_stock,'[]'))=0
    and exists(select 1 from public.stock_movements qs where qs.invoice_id=i.id and qs.movement_type::text='store_sale'
      and qs.quantity>coalesce((select sum(d.sellable_quantity+d.damaged_quantity+d.not_returned_quantity) from public.invoice_stock_dispositions d where d.movement_id=qs.id),0)
       +coalesce((select sum(v.quantity) from public.stock_movements v where v.reversed_sale_id=qs.id and v.movement_type::text='invoice_cancel_return'),0)) then
     raise exception 'Record the returned-and-sellable, damaged, or not-returned quantities for this product refund'; end if;
   v_total:=v_total+v_amount;
 end loop;
 if v_total>public.invoice_net_received(i.id) then raise exception 'Refund exceeds net payments still held'; end if;
 for x in select * from jsonb_array_elements(p_sources) loop
   select * into p from public.invoice_payments where id=(x->>'payment_id')::uuid and invoice_id=i.id for update;
   if not found or p.entry_kind='correction_reversal' or exists(select 1 from public.invoice_payments where corrects_payment_id=p.id and entry_kind='correction_reversal') then
     raise exception 'Choose a current original payment source'; end if;
   select * into m from public.payment_methods where id=p.payment_method_id;
   v_amount:=round((x->>'amount')::numeric,2);
   v_remaining:=public.invoice_payment_remaining(p.id);
   if v_amount is null or v_amount<=0 or v_amount>v_remaining then raise exception 'Refund exceeds the remaining amount for this payment'; end if;
   if coalesce(m.is_wallet_credit,false) then
     v_left:=v_amount;
     for a in select * from public.invoice_line_credit_allocations where payment_id=p.id and amount>reversed_amount order by id for update loop
       exit when v_left<=0;
       v_take:=least(v_left,a.amount-a.reversed_amount);
       select * into l from public.customer_credit_lots where id=a.lot_id for update;
       update public.customer_credit_lots set remaining_amount=remaining_amount+v_take,status='active',updated_at=now() where id=l.id;
       insert into public.customer_credit_ledger(wallet_id,customer_id,entry_type,category,amount,lot_id,source_type,source_record_id,store_id,reason,reverses_entry_id,created_by,approved_by)
         values(l.wallet_id,l.customer_id,'reverse',l.category,v_take,l.id,'invoice_payment_refund',p_request_id,l.store_id,p_reason,a.ledger_entry_id,auth.uid(),auth.uid());
       update public.invoice_line_credit_allocations set reversed_amount=reversed_amount+v_take where id=a.id;
       v_left:=v_left-v_take;
     end loop;
     if v_left>0 then raise exception 'Legacy wallet payment has no exact source allocation; review is required'; end if;
   end if;
   insert into public.invoice_refunds(invoice_id,payment_id,amount,reason,kind,refunded_by,request_id,credit_returned,outcome,created_at)
    values(i.id,p.id,v_amount,p_reason,'allocated',auth.uid(),p_request_id,case when m.is_wallet_credit then v_amount else 0 end,
      jsonb_build_object('hash',v_hash)||case when v_first then jsonb_build_object('lines',p_lines,'stock',p_stock) else '{}'::jsonb end,clock_timestamp());
   v_first:=false; v_source_total:=v_source_total+v_amount;
 end loop;
 if v_source_total<>v_total then raise exception 'Payment-source allocations must equal the refund total'; end if;
 for x in select * from jsonb_array_elements(coalesce(p_stock,'[]')) loop
   select * into sm from public.stock_movements where id=(x->>'movement_id')::uuid and invoice_id=i.id and movement_type::text='store_sale' for update;
   if not found then raise exception 'Stock return must reference an actual invoice deduction'; end if;
   sq:=coalesce((x->>'sellable_quantity')::int,0); dq:=coalesce((x->>'damaged_quantity')::int,0); nq:=coalesce((x->>'not_returned_quantity')::int,0);
   select coalesce(sum(sellable_quantity+damaged_quantity+not_returned_quantity),0) into v_resolved from public.invoice_stock_dispositions where movement_id=sm.id;
   v_resolved:=v_resolved+coalesce((select sum(quantity) from public.stock_movements where reversed_sale_id=sm.id and movement_type::text='invoice_cancel_return'),0);
   if sq<0 or dq<0 or nq<0 or sq+dq+nq<=0 or sq+dq+nq>sm.quantity-v_resolved then raise exception 'Stock disposition exceeds the unresolved deduction'; end if;
   if exists(select 1 from public.stock_movements where invoice_id=i.id and product_id=sm.product_id and reversed_sale_id is null and movement_type::text in ('invoice_cancel_return','invoice_refund_return','refund_return'))
      and not exists(select 1 from public.invoice_stock_dispositions where invoice_id=i.id and movement_id=sm.id) then
     raise exception 'Historical stock returns require source review before another return'; end if;
   insert into public.invoice_stock_dispositions(invoice_id,movement_id,request_id,sellable_quantity,damaged_quantity,not_returned_quantity,reason,created_by)
    values(i.id,sm.id,p_request_id,sq,dq,nq,p_reason,auth.uid());
   if sq>0 then
     update public.store_inventory set current_qty=current_qty+sq,updated_at=now() where store_id=sm.from_store_id and product_id=sm.product_id;
     if not found then raise exception 'Original stock location no longer exists'; end if;
     insert into public.stock_movements(product_id,movement_type,to_store_id,invoice_id,quantity,notes,created_by,reversed_sale_id)
      values(sm.product_id,'invoice_refund_return',sm.from_store_id,i.id,sq,'Confirmed sellable return: '||p_reason,auth.uid(),sm.id);
   end if;
 end loop;
 update public.invoices set paid_amount=public.invoice_net_received(i.id),
   status=case when status<>'cancelled' and public.invoice_charge_total(i.id)<=0 then 'refunded'::invoice_status else status end where id=i.id;
 perform public.reconcile_invoice_commissions(i.id,'Refund: '||p_reason);
 perform public.write_audit_ex('invoices',i.id,'allocated_refund',null,v_payload,'refunds',p_reason,i.store_id);
 return public.invoice_financial_position(i.id)||jsonb_build_object('success',true,'refunded_amount',v_total);
end $$;
revoke all on function public.invoice_refund_options(uuid),public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid) from public,anon;
grant execute on function public.invoice_refund_options(uuid),public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
