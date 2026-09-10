begin;
-- Reprice the saved FOC allocation without consulting the current catalogue.
-- The former credit-purchase flow also supported a monetary FOC amount on a
-- single unit. Preserve that historical amount instead of interpreting its
-- foc_quantity=1 marker as a newly free whole package.
create function public.invoice_benefit_corrected_foc(p_item_id uuid,p_unit_price numeric)
returns numeric language sql stable security definer set search_path=public as $$
 select case
  when coalesce(it.foc_quantity,0)<=0 then 0
  when it.foc_quantity=it.quantity and not coalesce(it.is_foc,false)
   and it.foc_amount>0
   then least(it.foc_amount,round(p_unit_price*it.quantity,2))
  else least(round(p_unit_price*coalesce(it.foc_quantity,0),2),round(p_unit_price*it.quantity,2))
 end from public.invoice_items it where it.id=p_item_id
$$;
revoke all on function public.invoice_benefit_corrected_foc(uuid,numeric) from public,anon,authenticated;

do $$ declare f text; anchor text; begin
 select pg_get_functiondef('public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)'::regprocedure) into f;
 anchor:='      v_original_line.line_total:=round((v_item->>''unit_price'')::numeric*v_original_line.quantity,2);';
 if position(anchor in f)=0 then raise exception 'Unexpected benefit price accumulator'; end if;
 f:=replace(f,anchor,$patch$      v_original_line.foc_amount:=public.invoice_benefit_corrected_foc(v_original_line.id,(v_item->>'unit_price')::numeric);
      v_original_line.line_total:=round((v_item->>'unit_price')::numeric*v_original_line.quantity,2)-v_original_line.foc_amount;$patch$);
 anchor:='        line_total=round((v_item->>''unit_price'')::numeric*quantity,2),';
 if position(anchor in f)=0 then raise exception 'Unexpected benefit price writer'; end if;
 execute replace(f,anchor,$patch$        line_total=round((v_item->>'unit_price')::numeric*quantity,2)-public.invoice_benefit_corrected_foc(id,(v_item->>'unit_price')::numeric),
        foc_amount=public.invoice_benefit_corrected_foc(id,(v_item->>'unit_price')::numeric),$patch$);

 -- A benefit's store may have been corrected independently of the buyer's
 -- invoice. Reopening must use that recorded store for both stock and ownership.
 select pg_get_functiondef('public.apply_reopened_invoice_vouchers()'::regprocedure) into f;
 anchor:='  select * into v from public.customer_reward_vouchers where id=b.reward_voucher_id for update;';
 if position(anchor in f)=0 then raise exception 'Unexpected reopened voucher source'; end if;
 f:=replace(f,anchor,anchor||chr(10)||'  if v.store_id is null then raise exception ''Review the original voucher store before reopening this benefit''; end if;');
 anchor:='store_id=new.store_id and current_qty>=q.quantity';
 if position(anchor in f)=0 then raise exception 'Unexpected reopened voucher stock location'; end if;
 f:=replace(f,anchor,'store_id=v.store_id and current_qty>=q.quantity');
 anchor:='values(v.customer_id,v.voucher_id,new.store_id,q.quantity';
 if position(anchor in f)=0 then raise exception 'Unexpected reopened voucher recipient location'; end if;
 execute replace(f,anchor,'values(v.customer_id,v.voucher_id,v.store_id,q.quantity');
end $$;
notify pgrst,'reload schema';
commit;
