begin;
alter table public.credit_package_sales add column if not exists bonus_credit_lot_id uuid references public.customer_credit_lots(id);
-- Save the exact bonus lot while the issuing function still owns its id.
-- This also covers each legacy split recipient without guessing by timestamps.
do $$ declare f text; sig text; anchor text:='return jsonb_build_object(''sale_id'', v_sale'; begin
 foreach sig in array array['public.issue_credit_package(uuid,uuid,uuid,numeric,uuid)', 'public.issue_credit_package_invoice_item(uuid)'] loop
  select pg_get_functiondef(sig::regprocedure) into f;
  if position(anchor in f)=0 then raise exception 'Unexpected credit issuance definition: %',sig; end if;
  execute replace(f,anchor,'update public.credit_package_sales set bonus_credit_lot_id=v_bonus_lot where id=v_sale;'||chr(10)||'  '||anchor);
 end loop;
end $$;
-- Capture refund values only for benefits issued after this migration. Historical
-- compound allocations are never fabricated from today's catalogue.
create or replace function public.capture_invoice_benefit_values(p_item_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare it public.invoice_items%rowtype; s record; l record; v record; parts jsonb; x jsonb;
 total_weight numeric; value_left numeric; n int; k int; paid numeric; price jsonb;
begin
 select * into it from public.invoice_items where id=p_item_id;
 for s in
  select c.id,c.external_paid,c.credit_lot_id paid_lot,c.bonus_credit_lot_id bonus_lot,0 vouchers from public.credit_package_sales c
   where c.invoice_id=it.invoice_id and c.package_id=it.credit_package_id and c.sold_at>=transaction_timestamp()
  union all select b.id,b.external_paid,b.paid_credit_lot_id,b.bonus_credit_lot_id,b.vouchers_issued from public.premium_bundle_sales b
   where b.invoice_id=it.invoice_id and b.bundle_id=it.premium_bundle_id and b.sold_at>=transaction_timestamp()
 loop
  if exists(select 1 from public.invoice_benefit_values where lot_id in(s.paid_lot,s.bonus_lot)) then continue; end if;
  parts:='[]'; total_weight:=0;
  for l in select * from public.customer_credit_lots where id in(s.paid_lot,s.bonus_lot) order by id loop
   parts:=parts||jsonb_build_array(jsonb_build_object('lot_id',l.id,'granted',l.original_amount,'weight',l.original_amount));
   total_weight:=total_weight+l.original_amount;
  end loop;
  for v in select * from public.customer_reward_vouchers where source_id=s.id order by id loop
   price:=public.voucher_price_for(v.store_id,v.voucher_id,true);
   if not coalesce((price->>'has_price')::boolean,false) or coalesce((price->>'price')::numeric,0)<=0 then
    perform public.write_audit_ex('invoice_items',it.id,'benefit_allocation_review_required',null,jsonb_build_object('sale_id',s.id,'reason','Voucher component has no documented value'),'refunds',null,null);
    return;
   end if;
   parts:=parts||jsonb_build_array(jsonb_build_object('reward_voucher_id',v.id,'granted',v.quantity,'weight',(price->>'price')::numeric*v.quantity));
   total_weight:=total_weight+(price->>'price')::numeric*v.quantity;
  end loop;
  if total_weight<=0 then continue; end if;
  value_left:=s.external_paid; n:=jsonb_array_length(parts); k:=0;
  for x in select * from jsonb_array_elements(parts) loop
   k:=k+1; paid:=case when k=n then value_left else round(s.external_paid*(x->>'weight')::numeric/total_weight,2) end;
   value_left:=value_left-paid;
   insert into public.invoice_benefit_values(invoice_id,invoice_item_id,lot_id,reward_voucher_id,paid_value,granted_value,evidence,created_by)
   values(it.invoice_id,it.id,(x->>'lot_id')::uuid,(x->>'reward_voucher_id')::uuid,paid,(x->>'granted')::numeric,
    'Allocated at issuance from actual discounted external payment, proportional to granted credit and voucher value; sale '||s.id,auth.uid());
  end loop;
 end loop;
end $$;
do $$
declare f text; anchor text:='    update public.invoice_items set credit_issued_at = now() where id = v_it.id;';
begin
 select pg_get_functiondef('public.issue_credit_lines_for_invoice(uuid)'::regprocedure) into f;
 if position(anchor in f)=0 then raise exception 'Unexpected credit issuance definition'; end if;
 execute replace(f,anchor,'    perform public.capture_invoice_benefit_values(v_it.id);'||chr(10)||anchor);
end $$;

create or replace function public.record_invoice_benefit_values(p_item_id uuid,p_allocations jsonb,p_evidence text)
returns void language plpgsql security definer set search_path=public as $$
declare it public.invoice_items%rowtype; i public.invoices%rowtype; x jsonb; paid numeric; granted numeric; total numeric:=0;
begin
 if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can resolve benefit values'; end if;
 if length(trim(coalesce(p_evidence,'')))<10 then raise exception 'Describe the historical evidence supporting these allocations'; end if;
 select * into it from public.invoice_items where id=p_item_id;
 select * into i from public.invoices where id=it.invoice_id for update;
 if not found or it.line_kind not in ('credit_package','premium_bundle') then raise exception 'Credit/bundle line not found'; end if;
 if exists(select 1 from public.invoice_benefit_values where invoice_item_id=it.id) then raise exception 'This line already has recorded allocations'; end if;
 if jsonb_typeof(p_allocations) is distinct from 'array' or jsonb_array_length(p_allocations)=0 then raise exception 'Record each original benefit allocation'; end if;
 for x in select * from jsonb_array_elements(p_allocations) loop
  paid:=(x->>'paid_value')::numeric; granted:=(x->>'granted_value')::numeric;
  if paid is null or paid<0 or granted is null or granted<=0 then raise exception 'Valid paid and granted values are required'; end if;
  if x->>'lot_id' is not null then
   if not exists(select 1 from public.customer_credit_lots l where l.id=(x->>'lot_id')::uuid and l.original_amount=granted
    and (exists(select 1 from public.credit_package_sales c where c.invoice_id=i.id and c.credit_lot_id=l.id and c.package_id=it.credit_package_id)
     or exists(select 1 from public.premium_bundle_sales b where b.invoice_id=i.id and l.id in(b.paid_credit_lot_id,b.bonus_credit_lot_id) and b.bundle_id=it.premium_bundle_id))) then
    raise exception 'Credit lot is not an original benefit of this invoice'; end if;
  elsif not exists(select 1 from public.customer_reward_vouchers v join public.premium_bundle_sales b on b.id=v.source_id
    where v.id=(x->>'reward_voucher_id')::uuid and b.invoice_id=i.id and b.bundle_id=it.premium_bundle_id and v.quantity=granted) then
    raise exception 'Voucher is not an original benefit of this invoice';
  end if;
  insert into public.invoice_benefit_values(invoice_id,invoice_item_id,lot_id,reward_voucher_id,paid_value,granted_value,evidence,created_by)
   values(i.id,it.id,(x->>'lot_id')::uuid,(x->>'reward_voucher_id')::uuid,paid,granted,p_evidence,auth.uid());
  total:=total+paid;
 end loop;
 if total>greatest(it.line_total-coalesce(it.line_discount,0),0) or total>public.invoice_net_received(i.id)+coalesce((select sum(amount) from public.invoice_refunds where invoice_id=i.id),0) then
  raise exception 'Recorded benefit values exceed the actual paid line value'; end if;
 perform public.write_audit_ex('invoice_items',it.id,'benefit_values_reviewed',null,p_allocations,'refunds',p_evidence,i.store_id);
end $$;
revoke all on function public.capture_invoice_benefit_values(uuid) from public,anon,authenticated;
revoke all on function public.record_invoice_benefit_values(uuid,jsonb,text) from public,anon;
grant execute on function public.record_invoice_benefit_values(uuid,jsonb,text) to authenticated;
notify pgrst,'reload schema';
commit;
