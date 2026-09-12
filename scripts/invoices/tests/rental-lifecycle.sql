-- Rentals and special products through correction, refund and cancellation.
--
-- 179 guarded only 'active' and 'paid', which left an overdue rental (the item
-- still out with the customer) cancellable, and an unfulfilled rental standing
-- after its invoice was cancelled. Disposable database only; all rolled back.
begin;
do $$
declare o uuid:=gen_random_uuid(); st uuid; wh uuid; c uuid; pm uuid; sp uuid;
 inv uuid; sale_it uuid; rent_it uuid; pay uuid; x jsonb; blockers jsonb;
 qty_before int; rent_id uuid;
begin
 insert into auth.users(id,email) values(o,'rental@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Owner','rental@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Rental Test','RNT','SG') returning id into st;
 insert into warehouses(name,code) values('Rental WH','RNTW') returning id into wh;
 insert into customers(full_name,phone) values('Rental Buyer','+6595550001') returning id into c;
 insert into payment_methods(name,is_active) values('Rental Cash',true) returning id into pm;
 insert into special_products(name,sku,sale_price,rate_day,is_active)
  values('Rental Item','RNT-1',200,20,true) returning id into sp;
 insert into special_product_stock(special_product_id,warehouse_id,current_qty) values(sp,wh,5);

 -- A mixed invoice: one outright sale and one three-day rental.
 inv:=create_invoice(st,c,null,jsonb_build_array(
   jsonb_build_object('kind','special_product','special_product_id',sp,'quantity',1),
   jsonb_build_object('kind','rental','special_product_id',sp,'quantity',1,'rental_rate_type','day','rental_periods',3)));
 if (select total_amount from invoices where id=inv)<>260 then
  raise exception 'Special product and rental did not price to 200 + 3 x 20'; end if;
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',260)));
 select id into sale_it from invoice_items where invoice_id=inv and line_kind='special_product';
 select id into rent_it from invoice_items where invoice_id=inv and line_kind='rental';
 select id into pay from invoice_payments where invoice_id=inv;
 if (select count(*) from rentals where invoice_id=inv)<>1 then
  raise exception 'Paying the invoice created no rental record'; end if;

 -- A metadata correction leaves both lines alone.
 x:=(select jsonb_agg(jsonb_build_object('invoice_item_id',id,'kind',line_kind::text,'quantity',quantity,
      'special_product_id',special_product_id,'rental_rate_type',rental_rate_type,
      'rental_periods',rental_periods,'unit_price',unit_price) order by id)
     from invoice_items where invoice_id=inv);
 perform correct_invoice(inv,x,'{"notes":"Corrected"}','Metadata only',gen_random_uuid());
 if (select count(*) from invoice_items where invoice_id=inv)<>2 then
  raise exception 'Correction rebuilt the special/rental lines'; end if;
 if sale_it is distinct from (select id from invoice_items where invoice_id=inv and line_kind='special_product') then
  raise exception 'Correction did not preserve the special-product line id'; end if;

 -- The outright sale line refunds against its original payment.
 perform refund_invoice_recorded(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',sale_it,'amount',200)),
  jsonb_build_array(jsonb_build_object('payment_id',pay,'amount',200)),'[]','Item returned',gen_random_uuid());
 if (select coalesce(sum(amount),0) from invoice_refunds where invoice_id=inv)<>200 then
  raise exception 'Special-product refund was not recorded'; end if;

 -- 300: an OUTSTANDING rental no longer blocks cancellation. A customer may
 -- cancel while the item is still with them; what must not happen is the item
 -- silently reappearing in stock because a contract was cancelled.
 if not rental_is_outstanding('overdue') then raise exception 'Overdue is not treated as outstanding'; end if;
 update rentals set status='active',fulfilled_at=now(),stock_returned=false where invoice_id=inv;
 qty_before:=(select current_qty from special_product_stock where special_product_id=sp and warehouse_id=wh);
 perform cancel_invoice_recorded(inv,'Cancel with the item still out',gen_random_uuid());
 if (select status::text from rentals where invoice_id=inv)<>'cancelled' then
  raise exception 'Cancelling did not cancel the outstanding rental'; end if;
 if not rental_awaiting_return((select id from rentals where invoice_id=inv)) then
  raise exception 'A rental cancelled while out must read as awaiting return'; end if;
 if (select current_qty from special_product_stock where special_product_id=sp and warehouse_id=wh)<>qty_before then
  raise exception 'Cancelling a live rental put the item back in stock without anyone returning it'; end if;
 if jsonb_array_length(invoice_rentals_awaiting_return(inv))<>1 then
  raise exception 'The invoice does not report the rental as awaiting return'; end if;
 if not exists(select 1 from audit_logs where table_name='rentals' and action='rental_cancelled_awaiting_return') then
  raise exception 'Cancelling a live rental was not audited as awaiting return'; end if;

 -- Receiving it is a separate, confirmed event with a destination and a condition.
 rent_id:=(select id from rentals where invoice_id=inv);
 begin
  perform receive_returned_rental(rent_id,gen_random_uuid(),'good','Back today',gen_random_uuid());
  raise exception 'Accepted an unknown warehouse as the destination';
 exception when others then
  if sqlerrm not like '%active warehouse%' then raise; end if; end;
 begin
  perform receive_returned_rental(rent_id,wh,'melted','Back today',gen_random_uuid());
  raise exception 'Accepted a condition that is not good, damaged or lost';
 exception when others then
  if sqlerrm not like '%good, damaged or lost%' then raise; end if; end;
 if (select current_qty from special_product_stock where special_product_id=sp and warehouse_id=wh)<>qty_before then
  raise exception 'A refused return changed stock'; end if;

 -- Damaged goods are resolved but never made available again.
 if (receive_returned_rental(rent_id,wh,'damaged','Came back cracked',gen_random_uuid())->>'made_available')::boolean then
  raise exception 'A damaged rental was made available for sale'; end if;
 if (select coalesce(current_qty,0) from warehouse_inventory wi
      join special_products spx on spx.product_id=wi.product_id
     where spx.id=sp and wi.warehouse_id=wh)>0 then
  raise exception 'A damaged rental was added to warehouse stock'; end if;
 -- and the same asset cannot be taken back a second time by any route.
 if not (receive_returned_rental(rent_id,wh,'good','Trying again',gen_random_uuid())->>'already_returned')::boolean then
  raise exception 'The same rental asset was received twice'; end if;
 if return_rental_to_warehouse(rent_id)<>0 then
  raise exception 'Rental completion returned an asset that cancellation had already resolved'; end if;

 -- Back to an unfulfilled rental for the remaining assertions.
 update rentals set status='awaiting_fulfilment',stock_returned=false,returned_at=null,
   return_condition=null,cancelled_at=null where invoice_id=inv;
 update invoices set status='paid' where id=inv;

 -- An UNFULFILLED rental is cancelled with the invoice instead of blocking it.
 update rentals set status='awaiting_fulfilment' where invoice_id=inv;
 perform cancel_invoice_recorded(inv,'Cancel before handover',gen_random_uuid());
 if (select status::text from rentals where invoice_id=inv)<>'cancelled' then
  raise exception 'Cancelled invoice left an unfulfilled rental standing'; end if;
 if (select cancelled_at from rentals where invoice_id=inv) is null then
  raise exception 'Cancelled rental has no cancellation time'; end if;
 if not exists(select 1 from audit_logs where table_name='rentals' and action='rental_cancelled_with_invoice') then
  raise exception 'Rental cancellation was not audited'; end if;

 -- Repeating it must not act twice.
 if cancel_invoice_rentals(inv,'Again')<>0 then
  raise exception 'Rental cancellation repeated on an already cancelled rental'; end if;

 raise notice 'PASS: special product and rental price, correct and refund; a live rental is cancelled with its invoice and left awaiting return without touching stock; receiving it needs a real warehouse and a valid condition; damaged goods never return to sale; no asset is received twice by either route; an unfulfilled rental is cancelled with its invoice, audited and once only';
end $$;
rollback;
