-- Selling a credit package or premium bundle to a SINGLE customer.
--
-- Reproduces the live database's condition exactly -- a create_invoice whose
-- item loop has no credit_package or premium_bundle branch -- shows that it
-- produces the reported error, and proves 302 repairs it.
--
-- The live fault came from migration 151 selecting the function to patch by
-- name alone while two overloads existed, so it patched the one nothing calls.
-- Disposable database only; all DDL and data are rolled back.
begin;
do $$
declare
 o uuid:=gen_random_uuid(); st uuid; c uuid; cp uuid; pb uuid; v uuid; inv uuid;
 f text; broken text; msg text; n int;
begin
 insert into auth.users(id,email) values(o,'pkg@tests.invalid');
 insert into profiles(id,full_name,email,role) values(o,'Owner','pkg@tests.invalid','owner');
 perform set_config('request.jwt.claim.sub',o::text,true);
 insert into stores(name,code,country_code) values('Energia Rev 22 (Adelphi)','ADL','SG') returning id into st;
 insert into customers(full_name,phone) values('Single Buyer','+6598894001') returning id into c;
 insert into credit_packages(name,customer_price,paid_credit_amount,bonus_enabled,bonus_mode,bonus_value,allow_product,allow_therapy)
   values('$1,000 Credit Package',1000,1000,true,'fixed',50,true,true) returning id into cp;
 insert into credit_package_stores(package_id,store_id) values(cp,st);
 insert into vouchers(name,code,qty_type,reward_eligible) values('Reward Voucher','PKG-RV','unlimited',true) returning id into v;
 insert into voucher_store_prices(voucher_id,store_id,selling_price,available_at_store) values(v,st,100,true);
 insert into premium_bundles(name,customer_payment_amount,paid_credit_amount,bonus_credit_amount,free_voucher_qty,grants_reward)
   values('$15,000 bundle',15000,15000,0,150,true) returning id into pb;
 insert into premium_bundle_stores(bundle_id,store_id) values(pb,st);
 insert into premium_bundle_vouchers(bundle_id,voucher_id) values(pb,v);

 -- ---- the repaired database sells both to one customer -------------------
 inv:=create_invoice_with_details(st,c,
   jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 if (select total_amount from invoices where id=inv)<>1000 then
  raise exception 'Single-customer credit package priced at % instead of its configured 1000',
    (select total_amount from invoices where id=inv); end if;
 if (select line_kind::text from invoice_items where invoice_id=inv)<>'credit_package' then
  raise exception 'The package was recorded as something other than a credit package line'; end if;
 -- the configured price and the package identity are snapshotted, not re-derived
 if (select credit_package_id from invoice_items where invoice_id=inv) is distinct from cp then
  raise exception 'The line lost its package identity'; end if;
 if (select credit_paid_snapshot from invoice_items where invoice_id=inv)<>1000 then
  raise exception 'The paid-credit snapshot was not taken'; end if;

 inv:=create_invoice_with_details(st,c,
   jsonb_build_array(jsonb_build_object('kind','premium_bundle','premium_bundle_id',pb,'quantity',1,
     'voucher_selection',jsonb_build_array(jsonb_build_object('voucher_id',v,'quantity',150)))),
   jsonb_build_object('business_date',sg_today()::text));
 if (select total_amount from invoices where id=inv)<>15000 then
  raise exception 'Single-customer bundle priced at % instead of its configured 15000',
    (select total_amount from invoices where id=inv); end if;
 if (select bundle_voucher_selection from invoice_items where invoice_id=inv) is null then
  raise exception 'The chosen reward vouchers were not recorded on the line'; end if;

 -- An incomplete voucher selection is still refused, by name, not by <NULL>.
 begin
  perform create_invoice_with_details(st,c,
    jsonb_build_array(jsonb_build_object('kind','premium_bundle','premium_bundle_id',pb,'quantity',1,
      'voucher_selection',jsonb_build_array(jsonb_build_object('voucher_id',v,'quantity',3)))),
    jsonb_build_object('business_date',sg_today()::text));
  raise exception 'An incomplete reward-voucher selection was accepted';
 exception when others then
  msg:=sqlerrm;
  if msg like '%An incomplete reward%' then raise; end if;
  if msg not like '%reward voucher%' then raise exception 'Unhelpful refusal: %',msg; end if;
  if msg like '%<NULL>%' then raise exception 'The refusal named the item as <NULL>'; end if;
 end;

 -- ---- now reproduce the live fault, and repair it -------------------------
 select pg_get_functiondef('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)'::regprocedure) into f;
 -- Strip both package branches from BOTH loops, leaving the product branch —
 -- exactly the shape the live function is in.
 broken:=regexp_replace(f,
   E'    elsif v_kind = ''credit_package'' then.*?\\n(?=    else\\n      v_product_id :=)','','gs');
 if broken=f then raise exception 'Could not simulate the live fault; the branch shape has changed'; end if;
 execute broken;
 -- Only the BRANCH must be gone; the name still appears in the exclusion guard.
 if position('v_kind = ''credit_package''' in pg_get_functiondef('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)'::regprocedure))>0 then
  raise exception 'The simulated fault did not remove the branches'; end if;

 begin
  perform create_invoice_with_details(st,c,
    jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)),
    jsonb_build_object('business_date',sg_today()::text));
  raise exception 'The simulated fault did not break creation';
 exception when others then
  msg:=sqlerrm;
  if msg like 'The simulated fault%' then raise; end if;
  if msg not like 'No price set for%' then
   raise exception 'Expected the reported error, got: %',msg; end if;
  if msg not like '%<NULL>%' then
   raise exception 'Expected the reported <NULL> item name, got: %',msg; end if;
 end;

 raise notice 'Reproduced the live fault: %',msg;

 -- ---- 302 repairs it ------------------------------------------------------
 if (public.repair_create_invoice_package_branches()->>'patched')::int < 1 then
  raise exception 'The repair reported patching nothing on a database that needed it'; end if;

 inv:=create_invoice_with_details(st,c,
   jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',cp,'quantity',1)),
   jsonb_build_object('business_date',sg_today()::text));
 if (select total_amount from invoices where id=inv)<>1000 then
  raise exception 'After the repair the package priced at %, not its configured 1000',
    (select total_amount from invoices where id=inv); end if;
 if (select credit_paid_snapshot from invoice_items where invoice_id=inv)<>1000 then
  raise exception 'After the repair the paid-credit snapshot was lost'; end if;

 inv:=create_invoice_with_details(st,c,
   jsonb_build_array(jsonb_build_object('kind','premium_bundle','premium_bundle_id',pb,'quantity',1,
     'voucher_selection',jsonb_build_array(jsonb_build_object('voucher_id',v,'quantity',150)))),
   jsonb_build_object('business_date',sg_today()::text));
 if (select total_amount from invoices where id=inv)<>15000 then
  raise exception 'After the repair the bundle priced at %, not its configured 15000',
    (select total_amount from invoices where id=inv); end if;

 -- Re-running the repair is a no-op, not a second patch.
 if (public.repair_create_invoice_package_branches()->>'patched')::int <> 0 then
  raise exception 'The repair patched an already-correct function a second time'; end if;

 -- A failed creation leaves nothing behind.
 select count(*) into n from invoices where customer_id=c;
 begin
  perform create_invoice_with_details(st,c,
    jsonb_build_array(jsonb_build_object('kind','credit_package','credit_package_id',gen_random_uuid(),'quantity',1)),
    jsonb_build_object('business_date',sg_today()::text));
  raise exception 'An unknown package identifier was accepted';
 exception when others then
  if sqlerrm like 'An unknown package%' then raise; end if;
  if sqlerrm not like '%Credit package not found%' then
   raise exception 'Unhelpful refusal for an invalid identifier: %',sqlerrm; end if;
 end;
 if (select count(*) from invoices where customer_id=c)<>n then
  raise exception 'A failed creation left a partial invoice behind'; end if;

 raise notice 'PASS: single-customer credit package and premium bundle sell at their configured prices with their snapshots; the live overload fault is reproduced and repaired; the repair is idempotent; invalid identifiers and incomplete voucher selections are refused by name, never as <NULL>, and leave no partial invoice';
end $$;
rollback;
