begin;
create or replace function public.create_invoice_with_details(p_store_id uuid,p_customer_id uuid,p_items jsonb,p_header jsonb default '{}')
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 if nullif(p_header->>'business_date','') is null then raise exception 'Invoice business date is required'; end if;
 v_id:=public.create_invoice(p_store_id,p_customer_id,nullif(p_header->>'affiliate_id','')::uuid,p_items,
  coalesce((p_header->>'manual_discount')::numeric,0),p_header->>'notes',nullif(p_header->>'discount_voucher_id','')::uuid,
  coalesce(p_header->'service_staff','[]'));
 update public.invoices set business_date=(p_header->>'business_date')::date,
  instalment_category=nullif(p_header->>'instalment_category',''),
  instalment_method_id=nullif(p_header->>'instalment_method_id','')::uuid,
  instalment_months=nullif(p_header->>'instalment_months','')::int where id=v_id;
 if coalesce((p_header->>'save_earth_applied')::boolean,false) then
  perform public.set_invoice_save_earth(v_id,true,p_header->>'save_earth_label',coalesce((p_header->>'save_earth_amount')::numeric,0)); end if;
 return v_id;
end $$;
revoke all on function public.create_invoice_with_details(uuid,uuid,jsonb,jsonb) from public,anon;
grant execute on function public.create_invoice_with_details(uuid,uuid,jsonb,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
