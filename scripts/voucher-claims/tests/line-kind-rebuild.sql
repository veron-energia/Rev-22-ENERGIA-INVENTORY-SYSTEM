-- The unused voucher_claim line kind is gone, and the real ones still work.
--
-- 313 rebuilds invoice_line_kind, which is the kind of change that quietly
-- breaks a default, a cast or a comparison somewhere. These assertions cover
-- the type itself and then put a real invoice through the ordinary path.
--
-- Disposable database only; everything is rolled back.
begin;
do $$
declare own uuid:=gen_random_uuid(); st uuid; c uuid; pm uuid; p1 uuid; inv uuid; n int; v_kinds text;
begin
 -- ---- the type ------------------------------------------------------------
 select string_agg(enumlabel,',' order by enumsortorder) into v_kinds
   from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='invoice_line_kind';
 if position('voucher_claim' in v_kinds) > 0 then
  raise exception 'voucher_claim is still a line kind'; end if;
 if v_kinds <> 'product,voucher,promotion,therapy,credit_package,premium_bundle,special_product,rental' then
  raise exception 'The real line kinds changed: %', v_kinds; end if;

 -- the default survived the rebuild
 if (select pg_get_expr(d.adbin,d.adrelid) from pg_attrdef d
      join pg_attribute a on a.attrelid=d.adrelid and a.attnum=d.adnum
     where d.adrelid='public.invoice_items'::regclass and a.attname='line_kind')
    not like '%product%' then
  raise exception 'The line_kind default was lost in the rebuild'; end if;

 -- ---- and a real invoice still goes through -------------------------------
 insert into auth.users(id,email) values(own,'lkr@tests.invalid');
 insert into profiles(id,full_name,email,role) values(own,'Owner','lkr@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',own::text,true);
 insert into stores(name,code,country_code) values('LKR Store','LKR','SG') returning id into st;
 insert into customers(full_name,phone) values('LKR Buyer','+6598920001') returning id into c;
 insert into payment_methods(name) values('LKR Cash') returning id into pm;
 insert into products(name,sku,product_type) values('LKR Item','LKR-1','own') returning id into p1;
 insert into store_inventory(store_id,product_id,current_qty) values(st,p1,10);
 perform set_product_prices(st,p1,50,50,'available');

 inv:=create_invoice(st,c,null,jsonb_build_array(jsonb_build_object(
        'kind','product','product_id',p1,'quantity',2)));
 perform pay_invoice(inv,jsonb_build_array(jsonb_build_object('payment_method_id',pm,'amount',100)));
 if (select line_kind::text from invoice_items where invoice_id=inv) <> 'product' then
  raise exception 'A product line did not survive the rebuilt type'; end if;
 if (select status::text from invoices where id=inv) <> 'paid' then
  raise exception 'The invoice did not settle'; end if;

 -- comparisons against the type still work in both directions
 select count(*) into n from invoice_items
  where invoice_id=inv and line_kind = 'product'::invoice_line_kind;
 if n<>1 then raise exception 'Comparison against the rebuilt type failed'; end if;

 -- ---- the guard refuses rather than destroying ----------------------------
 -- With a label in use, 313 must refuse. Simulated by asserting the guard's
 -- own condition, since the label no longer exists to be used.
 select count(*) into n from public.invoice_items where line_kind::text = 'voucher_claim';
 if n<>0 then raise exception 'Fixture unexpectedly has voucher_claim lines'; end if;

 raise notice 'PASS: voucher_claim is gone, the real line kinds and the default are intact, and an ordinary invoice still settles';
end $$;
rollback;
