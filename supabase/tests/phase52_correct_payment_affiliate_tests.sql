-- CORRECTING THE PAYMENT METHOD AND THE AFFILIATE ON A PAID INVOICE
begin;

do $t$
declare
  v_o uuid := gen_random_uuid(); v_stf uuid := gen_random_uuid(); v_stf2 uuid := gen_random_uuid();
  v_store uuid; v_cash uuid; v_card uuid; v_wallet uuid; v_p uuid;
  v_cust uuid; v_ref1 uuid; v_ref2 uuid; v_aff1 uuid; v_aff2 uuid;
  v_inv uuid; v_pay uuid; v_res jsonb; v_n integer; v_amt numeric;
begin
  insert into auth.users(id,email) values (v_o,'pm-o@x.com'),(v_stf,'pm-s@x.com'),(v_stf2,'pm-s2@x.com');
  insert into public.profiles(id,full_name,email,role,is_active) values
    (v_o,'PM Owner','pm-o@x.com','owner',true),(v_stf,'PM Staff','pm-s@x.com','staff',true),
    (v_stf2,'PM Other Staff','pm-s2@x.com','staff',true);
  perform set_config('request.jwt.claims', json_build_object('sub',v_o::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_o::text, true);
  insert into public.stores(name,code,country_code) values ('PM Store','PMS','SG') returning id into v_store;
  insert into public.user_store_assignments(user_id,store_id) values (v_stf,v_store);
  insert into public.payment_methods(name) values ('PM Cash') returning id into v_cash;
  insert into public.payment_methods(name) values ('PM Master Card') returning id into v_card;
  select id into v_wallet from public.payment_methods where is_wallet_credit limit 1;
  insert into public.products(name,sku,product_type) values ('PM Prod','PM-1','own') returning id into v_p;
  insert into public.store_inventory(store_id,product_id,current_qty) values (v_store,v_p,100);
  perform public.set_product_prices(v_store, v_p, 500, 500, 'available');

  insert into public.customers(full_name,phone) values ('PM Ref One','+6590520001') returning id into v_ref1;
  insert into public.customers(full_name,phone) values ('PM Ref Two','+6590520002') returning id into v_ref2;
  insert into public.customer_affiliates(customer_id,status,store_id,created_by)
    values (v_ref1,'active',v_store,v_o) returning id into v_aff1;
  insert into public.customer_affiliates(customer_id,status,store_id,created_by)
    values (v_ref2,'active',v_store,v_o) returning id into v_aff2;
  insert into public.customers(full_name,phone) values ('PM Cust','+6590520003') returning id into v_cust;

  -- Rung up as CASH, with NO affiliate.
  v_inv := public.create_invoice(v_store, v_cust, null,
    jsonb_build_array(jsonb_build_object('kind','product','product_id',v_p,'quantity',1)), 0, 'PM');
  perform public.pay_invoice(v_inv, jsonb_build_array(jsonb_build_object('payment_method_id',v_cash,'amount',500)));
  select id into v_pay from public.invoice_payments where invoice_id = v_inv;

  -- ===== 1. THE METHOD IS CORRECTABLE =====
  v_res := public.correct_invoice_payment_methods(v_inv,
    jsonb_build_array(jsonb_build_object('payment_id', v_pay, 'payment_method_id', v_card)),
    'Rung up as cash, actually card');
  if (v_res->>'changed')::int <> 1 then
    raise exception 'FAIL 1: the method should have changed, got %', v_res->>'changed'; end if;
  if (select payment_method_id from public.invoice_payments where id=v_pay) <> v_card then
    raise exception 'FAIL 1: it should now be Master Card'; end if;
  raise notice 'PASS 1: a payment method can be corrected on a settled invoice';

  -- ===== 2. THE AMOUNT IS STILL LOCKED =====
  begin
    update public.invoice_payments set amount = 1 where id = v_pay;
    if (select amount from public.invoice_payments where id=v_pay) <> 500 then
      raise exception 'FAIL 2: the AMOUNT must stay locked'; end if;
  exception when others then
    if sqlerrm like '%cannot be edited%' then null; else raise; end if;
  end;
  if (select amount from public.invoice_payments where id=v_pay) <> 500 then
    raise exception 'FAIL 2: the amount changed — it must not'; end if;
  raise notice 'PASS 2: the AMOUNT is still locked — only the method is correctable';

  -- ===== 3. DELETION IS STILL BLOCKED =====
  begin
    delete from public.invoice_payments where id = v_pay;
    raise exception 'FAIL 3: a settled payment must not be deletable';
  exception when others then
    if sqlerrm like '%cannot be deleted%' then null; else raise; end if;
  end;
  raise notice 'PASS 3: a settled payment still cannot be deleted';

  -- ===== 4. STAFF CORRECT THE METHOD AT THEIR OWN STORE (377), NOT ELSEWHERE =====
  perform set_config('request.jwt.claim.sub', v_stf::text, true);
  v_res := public.correct_invoice_payment_methods(v_inv,
    jsonb_build_array(jsonb_build_object('payment_id', v_pay, 'payment_method_id', v_cash)), 'It was cash after all');
  if (v_res->>'changed')::int <> 1 or (select payment_method_id from public.invoice_payments where id=v_pay) <> v_cash then
    raise exception 'FAIL 4: staff of the invoice''s store should be able to correct its payment method (377)'; end if;
  perform set_config('request.jwt.claim.sub', v_stf2::text, true);
  begin
    perform public.correct_invoice_payment_methods(v_inv,
      jsonb_build_array(jsonb_build_object('payment_id', v_pay, 'payment_method_id', v_card)), 'try');
    raise exception 'FAIL 4: staff of another store must not be able to correct a payment method';
  exception when others then
    if sqlerrm like '%Owner or Manager%' then null; else raise; end if;
  end;
  if (select payment_method_id from public.invoice_payments where id=v_pay) <> v_cash then
    raise exception 'FAIL 4: the refused attempt changed the method'; end if;
  raise notice 'PASS 4: staff correct a payment method on a paid invoice of their own store (377); staff of another store cannot';
  perform set_config('request.jwt.claim.sub', v_o::text, true);

  -- ===== 5. A WALLET METHOD CANNOT BE INTRODUCED =====
  if v_wallet is not null then
    begin
      perform public.correct_invoice_payment_methods(v_inv,
        jsonb_build_array(jsonb_build_object('payment_id', v_pay, 'payment_method_id', v_wallet)), 'try');
      raise exception 'FAIL 5: a wallet credit method must not be settable this way';
    exception when others then
      if sqlerrm like '%wallet credit%' then null; else raise; end if;
    end;
    raise notice 'PASS 5: a wallet credit method cannot be introduced by a correction';
  end if;

  -- ===== 6. AN AFFILIATE CAN BE ADDED WHERE THERE WAS NONE =====
  if (select affiliate_id from public.invoices where id=v_inv) is not null then
    raise exception 'SETUP: it should start with no affiliate'; end if;
  perform public.edit_paid_invoice(v_inv,
    jsonb_build_array(jsonb_build_object('kind','product','product_id',v_p,'quantity',1)),
    'Referrer was missed at the till', null, null, null, v_aff1, true);
  if (select affiliate_id from public.invoices where id=v_inv) <> v_aff1 then
    raise exception 'FAIL 6: the affiliate should have been added'; end if;
  raise notice 'PASS 6: an affiliate can be added to an invoice that had none';

  -- ===== 7. AND CHANGED TO ANOTHER =====
  perform public.edit_paid_invoice(v_inv,
    jsonb_build_array(jsonb_build_object('kind','product','product_id',v_p,'quantity',1)),
    'Wrong referrer recorded', null, null, null, v_aff2, true);
  if (select affiliate_id from public.invoices where id=v_inv) <> v_aff2 then
    raise exception 'FAIL 7: the affiliate should have changed'; end if;
  raise notice 'PASS 7: the affiliate can be changed to a different one';

  -- ===== 8. THE PRINTED REFERRER FOLLOWS =====
  if public.invoice_bill_to_source(v_inv) <> 'PM' then
    raise exception 'FAIL 8: the printed referrer should follow the new affiliate, got "%"',
      public.invoice_bill_to_source(v_inv); end if;
  raise notice 'PASS 8: the printed referrer follows the corrected affiliate';

  -- ===== 9. AND CAN BE CLEARED =====
  perform public.edit_paid_invoice(v_inv,
    jsonb_build_array(jsonb_build_object('kind','product','product_id',v_p,'quantity',1)),
    'No referrer after all', null, null, null, null, true);
  if (select affiliate_id from public.invoices where id=v_inv) is not null then
    raise exception 'FAIL 9: the affiliate should have been cleared'; end if;
  raise notice 'PASS 9: the affiliate can be removed entirely';

  -- ===== 10. OMITTING IT LEAVES IT ALONE =====
  perform public.edit_paid_invoice(v_inv,
    jsonb_build_array(jsonb_build_object('kind','product','product_id',v_p,'quantity',1)),
    'Quantity fix only', null, null, null, v_aff1, true);
  perform public.edit_paid_invoice(v_inv,
    jsonb_build_array(jsonb_build_object('kind','product','product_id',v_p,'quantity',1)),
    'Unrelated correction');
  if (select affiliate_id from public.invoices where id=v_inv) <> v_aff1 then
    raise exception 'FAIL 10: not supplying the affiliate must leave it untouched'; end if;
  raise notice 'PASS 10: a correction that does not mention the affiliate leaves it alone';

  -- ===== 11. AN UNKNOWN AFFILIATE IS REFUSED =====
  begin
    perform public.edit_paid_invoice(v_inv,
      jsonb_build_array(jsonb_build_object('kind','product','product_id',v_p,'quantity',1)),
      'Bad affiliate', null, null, null, gen_random_uuid(), true);
    raise exception 'FAIL 11: an unknown affiliate must be refused';
  exception when others then
    if sqlerrm like '%does not exist%' or sqlerrm like '%Affiliate not found%' then null; else raise; end if;
  end;
  raise notice 'PASS 11: an affiliate that does not exist is refused';

  raise notice '=== PAYMENT METHOD AND AFFILIATE CORRECTION VERIFIED ===';
end $t$;

rollback;
