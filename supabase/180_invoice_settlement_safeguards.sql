begin;
alter table public.stock_movements add column if not exists reversed_sale_id uuid references public.stock_movements(id);
-- Line refunds release the corresponding charge. Overpayment refunds do not.
-- Explicit reopening starts a new charge cycle while retaining every old refund.
create or replace function public.invoice_charge_total(p_invoice_id uuid)
returns numeric language sql stable security definer set search_path=public as $$
 select greatest(0,i.total_amount-coalesce((select sum((x->>'amount')::numeric)
 from public.invoice_refunds r cross join lateral jsonb_array_elements(coalesce(r.outcome->'lines','[]')) x
 where r.invoice_id=i.id and nullif(x->>'invoice_item_id','') is not null and not coalesce((x->>'overpayment')::boolean,false)
 and (i.reopened_at is null or r.created_at>i.reopened_at)),0)) from public.invoices i where i.id=p_invoice_id
$$;
create or replace function public.invoice_discounted_line_value(p_item_id uuid)
returns numeric language sql stable security definer set search_path=public as $$
 select round(greatest(it.line_total-coalesce(it.line_discount,0),0)*i.total_amount/
 nullif((select sum(greatest(l.line_total-coalesce(l.line_discount,0),0)) from public.invoice_items l where l.invoice_id=i.id),0),2)
 from public.invoice_items it join public.invoices i on i.id=it.invoice_id where it.id=p_item_id
$$;
create or replace function public.invoice_financial_position(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare i public.invoices%rowtype; n numeric; charge numeric;
begin
 select * into i from public.invoices where id=p_invoice_id;
 if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 n:=public.invoice_net_received(i.id); charge:=public.invoice_charge_total(i.id);
 return jsonb_build_object('total',i.total_amount,'net_received',n,'remaining_charge',charge,
 'outstanding',case when i.status in ('cancelled','refunded') then 0 else greatest(charge-n,0) end,
 'refund_due',greatest(n-charge,0),'overpayment_refundable',greatest(n-i.total_amount,0),
 'refunded',coalesce((select sum(amount) from public.invoice_refunds where invoice_id=i.id),0),'status',i.status,'business_date',i.business_date);
end $$;
create or replace function public.invoice_refund_options(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare i public.invoices%rowtype;
begin
 select * into i from public.invoices where id=p_invoice_id;
 if not found or not public.user_has_store_access(i.store_id) then raise exception 'Invoice not accessible'; end if;
 return jsonb_build_object('financial',public.invoice_financial_position(i.id),
 'lines',(select coalesce(jsonb_agg(jsonb_build_object('invoice_item_id',it.id,'name',coalesce(p.name,pr.name,v.name,it.plan_name_snapshot,it.line_kind::text),
   'line_kind',it.line_kind,'remaining',greatest(0,coalesce(public.invoice_discounted_line_value(it.id),0)-coalesce((select sum((x->>'amount')::numeric)
   from public.invoice_refunds r cross join lateral jsonb_array_elements(coalesce(r.outcome->'lines','[]')) x where r.invoice_id=i.id
   and (i.reopened_at is null or r.created_at>i.reopened_at) and x->>'invoice_item_id'=it.id::text),0)))),'[]')
   from public.invoice_items it left join public.products p on p.id=it.product_id left join public.promotions pr on pr.id=it.promotion_id
   left join public.vouchers v on v.id=it.voucher_id where it.invoice_id=i.id),
 'sources',(select coalesce(jsonb_agg(jsonb_build_object('payment_id',p.id,'method',m.name,'wallet',m.is_wallet_credit,'remaining',public.invoice_payment_remaining(p.id))),'[]')
   from public.invoice_payments p join public.payment_methods m on m.id=p.payment_method_id where p.invoice_id=i.id
   and p.entry_kind<>'correction_reversal' and not exists(select 1 from public.invoice_payments v where v.corrects_payment_id=p.id and v.entry_kind='correction_reversal')),
 'stock',(select coalesce(jsonb_agg(jsonb_build_object('movement_id',m.id,'product_id',m.product_id,'product_name',p.name,'store_id',m.from_store_id,'quantity',m.quantity,
   'resolved_quantity',coalesce((select sum(d.sellable_quantity+d.damaged_quantity+d.not_returned_quantity) from public.invoice_stock_dispositions d where d.movement_id=m.id),0)+coalesce((select sum(v.quantity) from public.stock_movements v where v.reversed_sale_id=m.id and v.movement_type::text='invoice_cancel_return'),0))),'[]')
   from public.stock_movements m join public.products p on p.id=m.product_id where m.invoice_id=i.id and m.movement_type::text='store_sale'),
 'review_required',exists(select 1 from public.invoice_refunds where invoice_id=i.id and payment_id is null),
 'benefits',(select coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object('customer_name',c.full_name,
    'remaining_value',coalesce(l.remaining_amount,case when v.status='held' then v.quantity else 0 end,0)+b.cancelled_unused_value,
    'max_refund',round(b.paid_value*(coalesce(l.remaining_amount,case when v.status='held' then v.quantity else 0 end,0)+b.cancelled_unused_value)/b.granted_value,2))),'[]')
   from public.invoice_benefit_values b left join public.customer_credit_lots l on l.id=b.lot_id
   left join public.customer_reward_vouchers v on v.id=b.reward_voucher_id left join public.customers c on c.id=coalesce(l.customer_id,v.customer_id) where b.invoice_id=i.id));
end $$;

-- Damaged/not-returned units are resolved dispositions, never sellable returns.
create or replace function public.restore_invoice_stock(p_invoice_id uuid,p_note text default null)
returns integer language plpgsql security definer set search_path=public as $$
declare r record; n int:=0;
begin
 perform 1 from public.invoices where id=p_invoice_id for update;
 if exists(select 1 from public.stock_movements where invoice_id=p_invoice_id and reversed_sale_id is null
  and movement_type::text in ('invoice_cancel_return','invoice_refund_return','refund_return')) then
  raise exception 'Historical stock returns need source-movement review before cancellation or stock correction'; end if;
 for r in select m.id,m.product_id,m.from_store_id store_id,
   m.quantity-coalesce((select sum(d.sellable_quantity+d.damaged_quantity+d.not_returned_quantity) from public.invoice_stock_dispositions d where d.movement_id=m.id),0)
   -coalesce((select sum(v.quantity) from public.stock_movements v where v.reversed_sale_id=m.id and v.movement_type::text='invoice_cancel_return'),0) qty
   from public.stock_movements m where m.invoice_id=p_invoice_id and m.movement_type::text='store_sale' order by m.id for update of m loop
  if r.qty<=0 then continue; end if;
  insert into public.store_inventory(store_id,product_id,current_qty) values(r.store_id,r.product_id,r.qty)
   on conflict(store_id,product_id) do update set current_qty=public.store_inventory.current_qty+excluded.current_qty,updated_at=now();
  insert into public.stock_movements(product_id,movement_type,to_store_id,invoice_id,quantity,notes,created_by,reversed_sale_id)
   values(r.product_id,'invoice_cancel_return',r.store_id,p_invoice_id,r.qty,p_note,auth.uid(),r.id); n:=n+1;
 end loop;
 return n;
end $$;

-- Keep the established allocator but release capacity after a traced reversal.
do $$ declare f text; begin
 select pg_get_functiondef('public.allocate_invoice_wallet_credit(uuid,numeric,text)'::regprocedure) into f;
 if position('coalesce(sum(a.amount),0)' in f)=0 then raise exception 'Unexpected wallet allocator definition'; end if;
 execute replace(f,'coalesce(sum(a.amount),0)','coalesce(sum(a.amount-a.reversed_amount),0)');
 -- Settled charge after line refunds, rather than the original refunded price.
 select pg_get_functiondef('public.invoice_record_payments_internal(uuid,jsonb)'::regprocedure) into f;
 execute replace(f,'v_inv.total_amount','public.invoice_charge_total(v_inv.id)');
 select pg_get_functiondef('public.correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)'::regprocedure) into f;
 execute replace(f,'when n>=total_amount','when n>=public.invoice_charge_total(i.id)');
end $$;

-- Unsafe historical entry points cannot bypass source allocation and stock evidence.
create or replace function public.refund_invoice_line(p_invoice_item_id uuid,p_reason text,p_return_stock boolean default true)
returns void language plpgsql security definer set search_path=public as $$
begin raise exception 'Open this invoice and use Record full / partial refund to allocate payment sources and confirm stock outcomes'; end $$;
create or replace function public.refund_credit_purchase(p_invoice_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin raise exception 'Open this invoice and use Record full / partial refund to review each recipient and unused benefit'; end $$;
create or replace function public.refund_credit_funded_item(p_invoice_item_id uuid,p_amount numeric,p_reason text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin raise exception 'Open this invoice and use Record full / partial refund to restore the exact original wallet source'; end $$;
-- Revoke internal helpers which previously allowed refunding without the invoice transaction.
revoke all on function public.restore_invoice_stock(uuid,text),public.deduct_invoice_stock(uuid,text),public.invoice_charge_total(uuid),public.invoice_discounted_line_value(uuid) from public,anon,authenticated;
revoke all on function public.invoice_refund_options(uuid),public.invoice_financial_position(uuid) from public,anon;
grant execute on function public.invoice_refund_options(uuid),public.invoice_financial_position(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
