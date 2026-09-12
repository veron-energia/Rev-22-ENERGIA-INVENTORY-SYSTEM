begin;
-- =====================================================================
-- CANCELLING AN INVOICE NO LONGER REQUIRES THE RENTAL BACK FIRST
--
-- cancel_invoice_recorded() refused outright:
--   'Return or resolve the outstanding rental before cancelling this invoice'
-- and cancel_invoice_rentals() only touched rentals that had never been handed
-- out. So an invoice whose rented item was still with the customer could not
-- be cancelled at all -- the one case where cancelling is most likely.
--
-- A rental may now be cancelled while it is still out. The asset is NOT
-- returned to stock by that act, because cancelling a contract is not the same
-- as somebody carrying the item back through the door. It becomes
-- AWAITING RETURN until a person confirms the destination and the condition.
--
-- "Awaiting return" is not a new status: it is the combination that already
-- described it -- cancelled, but the stock never came back. Adding an enum
-- value would have forced a second migration before it could be used, for no
-- extra meaning.
--
-- Requires 295. Idempotent.
-- =====================================================================

-- A cancelled rental whose asset is still out there.
create or replace function public.rental_awaiting_return(p_rental_id uuid)
returns boolean language sql stable security definer set search_path to 'public' as $$
 select coalesce(r.status::text='cancelled' and not coalesce(r.stock_returned,false)
        and (r.fulfilled_at is not null or r.activated_at is not null),false)
 from public.rentals r where r.id=p_rental_id
$$;
grant execute on function public.rental_awaiting_return(uuid) to authenticated;

-- What the invoice and the guided flow show, and what a return needs.
create or replace function public.invoice_rentals_awaiting_return(p_invoice_id uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $$
 select coalesce(jsonb_agg(jsonb_build_object(
   'rental_id',r.id,'rental_no',r.rental_no,'quantity',r.quantity,
   'item',coalesce(sp.name,'Special product'),
   'default_warehouse_id',r.warehouse_id,
   'default_warehouse',(select w.name from public.warehouses w where w.id=r.warehouse_id),
   'cancelled_at',r.cancelled_at,'status',r.status)),'[]'::jsonb)
 from public.rentals r
 left join public.special_products sp on sp.id=r.special_product_id
 join public.invoices i on i.id=r.invoice_id
 where r.invoice_id=p_invoice_id and public.user_has_store_access(i.store_id)
   and public.rental_awaiting_return(r.id)
$$;
grant execute on function public.invoice_rentals_awaiting_return(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Cancelling an invoice cancels its rentals, handed out or not.
-- ---------------------------------------------------------------------
create or replace function public.cancel_invoice_rentals(p_invoice_id uuid, p_reason text)
returns integer language plpgsql security definer set search_path to 'public' as $$
declare r record; n integer:=0;
begin
 for r in select * from public.rentals
           where invoice_id=p_invoice_id
             and (public.rental_is_unfulfilled(status::text) or public.rental_is_outstanding(status::text))
           for update
 loop
  update public.rentals
     set status='cancelled',cancelled_at=now(),
         notes=concat_ws(E'\n',notes,
           case when public.rental_is_outstanding(r.status::text)
             then 'Cancelled with its invoice while still out; awaiting physical return: '
             else 'Cancelled with its invoice: ' end||coalesce(p_reason,''))
   where id=r.id;
  perform public.write_audit_ex('rentals',r.id,
    case when public.rental_is_outstanding(r.status::text) then 'rental_cancelled_awaiting_return'
         else 'rental_cancelled_with_invoice' end,
    to_jsonb(r),
    jsonb_build_object('invoice_id',p_invoice_id,'reason',p_reason,
      'stock_returned',coalesce(r.stock_returned,false)),'rentals',null,r.store_id);
  n:=n+1;
 end loop;
 return n;
end $$;

-- ---------------------------------------------------------------------
-- Drop the refusal. Everything else about cancellation is untouched.
-- ---------------------------------------------------------------------
do $do$
declare f text; v_old text;
begin
 select pg_get_functiondef('public.cancel_invoice_recorded(uuid,text,uuid)'::regprocedure) into f;
 if position('Return or resolve the outstanding rental' in f)=0 then
  raise notice 'cancellation already allows an outstanding rental'; return; end if;
 v_old:=' if exists(select 1 from public.rentals where invoice_id=i.id and public.rental_is_outstanding(status::text)) then raise exception ''Return or resolve the outstanding rental before cancelling this invoice''; end if;';
 if position(v_old in f)=0 then
  raise exception 'The rental guard in cancel_invoice_recorded does not match what 300 expects — align it by hand'; end if;
 execute replace(f,v_old,
  ' -- An outstanding rental no longer blocks cancellation: cancel_invoice_rentals'||E'\n'||
  ' -- leaves it AWAITING RETURN, and its stock stays out until somebody confirms'||E'\n'||
  ' -- the item is actually back and in what condition.');
 raise notice 'an invoice with a rental still out can now be cancelled';
end $do$;

-- ---------------------------------------------------------------------
-- RECEIVING THE ITEM IS A SEPARATE, CONFIRMED EVENT
--
-- Used both for a rental cancelled mid-term and for one that simply ended, so
-- the two cannot drift apart. stock_returned is the single guard against the
-- same asset being taken back twice, whichever route it comes by.
-- ---------------------------------------------------------------------
create or replace function public.receive_returned_rental(
  p_rental_id uuid, p_warehouse_id uuid, p_condition text, p_reason text, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r public.rentals%rowtype; v_prod uuid; v_ok boolean; v_qty int:=0;
begin
 if not public.is_owner_or_manager() then
  raise exception 'Only an Owner or Manager can receive a returned rental'; end if;
 if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'A note is required'; end if;
 if coalesce(p_condition,'') not in ('good','damaged','lost') then
  raise exception 'Record the condition as good, damaged or lost'; end if;
 select * into r from public.rentals where id=p_rental_id for update;
 if not found then raise exception 'Rental not found'; end if;
 if not public.user_has_store_access(r.store_id) then raise exception 'Rental not accessible'; end if;
 if coalesce(r.stock_returned,false) then
  -- Completion and cancellation cannot both take the same asset back.
  return jsonb_build_object('rental_id',r.id,'already_returned',true,'returned_quantity',0); end if;

 -- The destination must be a real, usable warehouse.
 select is_active and deleted_at is null into v_ok from public.warehouses where id=p_warehouse_id;
 if not coalesce(v_ok,false) then
  raise exception 'Choose an active warehouse to receive this item'; end if;

 select product_id into v_prod from public.special_products where id=r.special_product_id;

 -- Only goods confirmed back AND sellable rejoin stock. Damaged and lost are
 -- resolved so they cannot be returned twice, but never become available.
 if p_condition='good' and v_prod is not null then
  insert into public.warehouse_inventory(warehouse_id,product_id,current_qty)
   values(p_warehouse_id,v_prod,r.quantity)
   on conflict(warehouse_id,product_id) do update
     set current_qty=public.warehouse_inventory.current_qty+excluded.current_qty,updated_at=now();
  insert into public.stock_movements(product_id,movement_type,to_warehouse_id,quantity,notes,created_by)
   values(v_prod,'invoice_cancel_return'::stock_movement_type,p_warehouse_id,r.quantity,
     'Rental returned in good condition — '||r.rental_no||': '||p_reason,auth.uid());
  v_qty:=r.quantity;
 end if;

 update public.rentals
    set stock_returned=true,returned_at=coalesce(returned_at,now()),
        return_condition=p_condition::return_condition,
        status=case when status::text='cancelled' then status else 'returned'::rental_status end,
        notes=concat_ws(E'\n',notes,'Received '||p_condition||': '||p_reason)
  where id=r.id;
 perform public.write_audit_ex('rentals',r.id,'rental_received',to_jsonb(r),
   jsonb_build_object('condition',p_condition,'warehouse_id',p_warehouse_id,
     'returned_quantity',v_qty,'request_id',p_request_id),'rentals',p_reason,r.store_id);
 return jsonb_build_object('rental_id',r.id,'returned_quantity',v_qty,'condition',p_condition,
   'made_available',p_condition='good');
end $$;
grant execute on function public.receive_returned_rental(uuid,uuid,text,text,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
