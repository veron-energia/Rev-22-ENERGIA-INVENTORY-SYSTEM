-- Save Earth is withdrawn (330); history is kept.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; c uuid; prod uuid; inv uuid; it uuid; items jsonb;
begin
 insert into auth.users(id,email) values(own,'se-own@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','se-own@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('SE Store','SES','SG') returning id into st;
 insert into customers(full_name,phone) values('SE Buyer','+6598913201') returning id into c;
 insert into products(name,sku,product_type) values('SE Item','SE-1','own') returning id into prod;
 insert into store_inventory(store_id,product_id,current_qty) values(st,prod,1000);
 perform set_product_prices(st,prod,100,100,'available');
 items:=jsonb_build_array(jsonb_build_object('kind','product','product_id',prod,'quantity',1));

 if to_regprocedure('public.set_invoice_save_earth(uuid,boolean,text,numeric)') is not null
    or to_regprocedure('public.set_save_earth_defaults(text,numeric)') is not null then
  raise exception 'FAIL: a Save Earth function is still installed'; end if;

 -- A header that still asks for it is ignored: no deduction, no label.
 inv:=create_invoice_with_details(st,c,items,jsonb_build_object('business_date',sg_today(),'save_earth_applied',true,'save_earth_label','Save Earth Project','save_earth_amount',1));
 if (select save_earth_applied from invoices where id=inv) or (select total_amount from invoices where id=inv)<>100 then
  raise exception 'FAIL: a new invoice applied Save Earth'; end if;

 -- History: an invoice that carried the deduction keeps its totals.
 update invoices set save_earth_applied=true, save_earth_label='Save Earth Project', save_earth_amount=1 where id=inv;
 perform refresh_invoice_discount_total(inv);
 -- refresh_invoice_discount_total owns discount_total; the total itself is
 -- re-derived by the invoice's own recalculation paths.
 if (select discount_total from invoices where id=inv)<>1 then
  raise exception 'FAIL: a historical Save Earth deduction no longer counts (discount_total %)',
    (select discount_total from invoices where id=inv); end if;
 -- ...and a correction leaves it exactly as it was, whatever the header says.
 select id into it from invoice_items where invoice_id=inv;
 perform correct_invoice(inv,jsonb_build_array(jsonb_build_object('invoice_item_id',it,'kind','product','product_id',prod,'quantity',1)),
   jsonb_build_object('notes','still here','save_earth_applied',false,'save_earth_amount',0),'unrelated',gen_random_uuid());
 if not (select save_earth_applied from invoices where id=inv) or (select save_earth_amount from invoices where id=inv)<>1 then
  raise exception 'FAIL: a correction changed a historical Save Earth record'; end if;

 raise notice 'PASS: the Save Earth functions are gone, a header asking for it is ignored, and an invoice that carried it keeps its deduction through totals and corrections';
end $$;
rollback;
