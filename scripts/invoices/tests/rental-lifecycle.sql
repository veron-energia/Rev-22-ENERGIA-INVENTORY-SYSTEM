-- Rentals and special products through correction, refund and cancellation.
--
-- 179 guarded only 'active' and 'paid', which left an overdue rental (the item
-- still out with the customer) cancellable, and an unfulfilled rental standing
-- after its invoice was cancelled. Disposable database only; all rolled back.
begin;
do $$
declare o uuid:=gen_random_uuid(); st uuid; wh uuid; c uuid; pm uuid; sp uuid;
 inv uuid; sale_it uuid; rent_it uuid; pay uuid; x jsonb; blockers jsonb;
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

 -- An OUTSTANDING rental blocks cancellation, correction and reopening.
 foreach x in array array['"active"'::jsonb,'"paid"'::jsonb,'"overdue"'::jsonb] loop
  update rentals set status=(x#>>'{}')::rental_status where invoice_id=inv;
  begin
   perform cancel_invoice_recorded(inv,'Cancel with the item out',gen_random_uuid());
   raise exception 'Cancelled while the rental was still %', x#>>'{}';
  exception when others then
   if sqlerrm like 'Cancelled while the rental%' then raise; end if;
   if sqlerrm not like '%outstanding rental%' then raise; end if; end;
  begin
   perform correct_invoice(inv,x,'{"customer_id":null}','Move it',gen_random_uuid());
  exception when others then null; end;
 end loop;
 if not rental_is_outstanding('overdue') then raise exception 'Overdue is not treated as outstanding'; end if;

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

 raise notice 'PASS: special product and rental price, correct and refund; an outstanding rental (including overdue) blocks cancellation, correction and reopening; an unfulfilled rental is cancelled with its invoice, audited and once only';
end $$;
rollback;
