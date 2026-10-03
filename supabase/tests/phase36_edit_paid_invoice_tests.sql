-- EDITING A PAID INVOICE
-- (Owner / Manager through edit_paid_invoice; since 377 staff also correct a
-- paid invoice of their own store through correct_invoice, prices and payment
-- amounts kept back.)
begin;

do $t$
declare
  v_o uuid := gen_random_uuid(); v_stf uuid := gen_random_uuid();
  v_store uuid; v_p1 uuid; v_p2 uuid; v_pm uuid; v_c uuid; v_ref uuid;
  v_inv uuid; v_res jsonb; v_n integer; v_num numeric; v_stock integer;
begin
  insert into auth.users(id,email) values (v_o,'ei-o@x.com'),(v_stf,'ei-s@x.com');
  insert into public.profiles(id,full_name,email,role,is_active) values
    (v_o,'EI Owner','ei-o@x.com','owner',true),
    (v_stf,'EI Staff','ei-s@x.com','staff',true);
  perform set_config('request.jwt.claims', json_build_object('sub',v_o::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_o::text, true);

  insert into public.stores(name,code,country_code) values ('EI Store','EIS','SG') returning id into v_store;
  insert into public.user_store_assignments(user_id,store_id) values (v_stf,v_store);
  update public.app_settings set staff_commission_rate = 5 where id = true;
  insert into public.payment_methods(name) values ('EI Cash') returning id into v_pm;
  insert into public.products(name,sku,product_type) values ('EI A','EI-1','own') returning id into v_p1;
  insert into public.products(name,sku,product_type) values ('EI B','EI-2','own') returning id into v_p2;
  insert into public.store_inventory(store_id,product_id,current_qty) values (v_store,v_p1,100),(v_store,v_p2,100);
  perform public.set_product_prices(v_store, v_p1, 100, 100, 'available');
  perform public.set_product_prices(v_store, v_p2, 50, 50, 'available');
  insert into public.customers(full_name,phone,is_referrer) values ('EI Ref','+6590360001',true) returning id into v_ref;
  insert into public.customers(full_name,phone,referred_by) values ('EI Cust','+6590360002',v_ref) returning id into v_c;

  -- Pay an invoice: 5 x A = 500.
  v_inv := public.create_invoice(v_store, v_c, null,
    jsonb_build_array(jsonb_build_object('kind','product','product_id',v_p1,'quantity',5)), 0, 'EI');
  perform public.pay_invoice(v_inv, jsonb_build_array(jsonb_build_object('payment_method_id',v_pm,'amount',500)));

  select current_qty into v_stock from public.store_inventory where store_id=v_store and product_id=v_p1;
  if v_stock <> 95 then raise exception 'SETUP: stock should be 95, got %', v_stock; end if;
  select count(*) into v_n from public.staff_commissions where invoice_id=v_inv and status='earned';
  if v_n <> 1 then raise exception 'SETUP: expected staff commission, got % rows', v_n; end if;

  -- ===== 1. STAFF CORRECT A PAID INVOICE OF THEIR STORE (377), PRICES KEPT BACK =====
  perform set_config('request.jwt.claim.sub', v_stf::text, true);
  -- The old Owner/Manager wrapper still refuses them.
  begin
    perform public.edit_paid_invoice(v_inv,
      jsonb_build_array(jsonb_build_object('kind','product','product_id',v_p1,'quantity',3)), 'try');
    raise exception 'FAIL 1: edit_paid_invoice must stay Owner / Manager only';
  exception when others then
    if sqlerrm like '%Owner or Manager%' then null; else raise; end if;
  end;
  -- The correction the page uses lets them change the quantity at the saved
  -- price. Undone straight away: the steps below start from the paid 5 x A.
  begin
    perform public.correct_invoice(v_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id',(select id from public.invoice_items where invoice_id=v_inv),
        'kind','product','product_id',v_p1,'quantity',3,'unit_price',100)), '{}'::jsonb,
      'Customer returned two units', gen_random_uuid());
    if (select total_amount from public.invoices where id=v_inv) <> 300 then
      raise exception 'FAIL 1: a staff correction to 3 x A should total 300'; end if;
    raise exception 'UNDO 1';
  exception when others then
    if sqlerrm = 'UNDO 1' then null; else raise; end if;
  end;
  -- But not its price.
  begin
    perform public.correct_invoice(v_inv,
      jsonb_build_array(jsonb_build_object('invoice_item_id',(select id from public.invoice_items where invoice_id=v_inv),
        'kind','product','product_id',v_p1,'quantity',5,'unit_price',90)), '{}'::jsonb,
      'Cheaper price', gen_random_uuid());
    raise exception 'FAIL 1: a staff member must not be able to change a price on a paid invoice';
  exception when others then
    if sqlerrm like '%Only an Owner or Manager can override invoice prices%' then null; else raise; end if;
  end;
  if (select total_amount from public.invoices where id=v_inv) <> 500 then
    raise exception 'FAIL 1: the staff attempts must leave the invoice at 500'; end if;
  raise notice 'PASS 1: staff correct a paid invoice of their store (quantity) but not its price; edit_paid_invoice stays Owner / Manager';
  perform set_config('request.jwt.claim.sub', v_o::text, true);

  -- ===== 2. A REASON IS REQUIRED =====
  begin
    perform public.edit_paid_invoice(v_inv,
      jsonb_build_array(jsonb_build_object('kind','product','product_id',v_p1,'quantity',3)), '   ');
    raise exception 'FAIL 2: an edit without a reason must be refused';
  exception when others then
    if sqlerrm like '%reason is required%' then null; else raise; end if;
  end;
  raise notice 'PASS 2: a reason is required and recorded';

  -- ===== 3. EDIT DOWN: 5 x A -> 3 x A (500 -> 300), 200 overpaid =====
  v_res := public.edit_paid_invoice(v_inv,
    jsonb_build_array(jsonb_build_object('kind','product','product_id',v_p1,'quantity',3)),
    'Customer returned two units');
  if (v_res->>'new_total')::numeric <> 300 then
    raise exception 'FAIL 3: new total should be 300, got %', v_res->>'new_total'; end if;
  if (v_res->>'refund_due')::numeric <> 200 then
    raise exception 'FAIL 3: a 200 refund should be due, got %', v_res->>'refund_due'; end if;
  raise notice 'PASS 3: reducing a paid invoice records the refund due (200), not silently absorbed';

  -- Stock: 5 returned then 3 taken -> 95 + 5 - 3 = 97.
  select current_qty into v_stock from public.store_inventory where store_id=v_store and product_id=v_p1;
  if v_stock <> 97 then raise exception 'FAIL 3: stock should be 97, got %', v_stock; end if;
  raise notice 'PASS 3b: stock is returned for the old lines and deducted for the new (97)';

  -- Old commission reversed, new commission earned on 300.
  select count(*) into v_n from public.staff_commissions where invoice_id=v_inv and status='reversed';
  if v_n < 1 then raise exception 'FAIL 3: the original staff commission should be reversed'; end if;
  select coalesce(sum(commission_amount),0) into v_num from public.staff_commissions
   where invoice_id=v_inv and status='earned';
  if v_num <> 15 then
    raise exception 'FAIL 3: staff commission should be 5%% of 300 = 15, got %', v_num; end if;
  raise notice 'PASS 3c: commission is reversed and re-earned on the corrected total (15)';

  -- The old rows survive: append-only.
  select count(*) into v_n from public.staff_commissions where invoice_id=v_inv;
  if v_n < 2 then raise exception 'FAIL 3: the original commission row must be kept, not deleted'; end if;
  raise notice 'PASS 3d: reversed commission rows are kept, never deleted';

  -- ===== 4. A REVISION SNAPSHOT PRESERVES THE OLD STATE =====
  select count(*) into v_n from public.invoice_revisions where invoice_id=v_inv;
  if v_n < 1 then raise exception 'FAIL 4: a revision should have been written'; end if;
  select old_total into v_num from public.invoice_revision_history(v_inv) limit 1;
  if v_num <> 500 then
    raise exception 'FAIL 4: the revision should preserve the old total of 500, got %', v_num; end if;
  raise notice 'PASS 4: the invoice as it stood is preserved in the revision history (500)';

  -- ===== 5. EDIT UP: leaves a balance owing =====
  v_res := public.edit_paid_invoice(v_inv,
    jsonb_build_array(
      jsonb_build_object('kind','product','product_id',v_p1,'quantity',3),
      jsonb_build_object('kind','product','product_id',v_p2,'quantity',4)),
    'Customer added four of B');
  if (v_res->>'new_total')::numeric <> 500 then
    raise exception 'FAIL 5: new total should be 300+200=500, got %', v_res->>'new_total'; end if;
  if (v_res->>'balance_due')::numeric <> 0 then
    raise exception 'FAIL 5: 500 was paid so nothing more is owed, got %', v_res->>'balance_due'; end if;
  if (v_res->>'status') <> 'paid' then
    raise exception 'FAIL 5: it should be paid again, got %', v_res->>'status'; end if;
  raise notice 'PASS 5: raising the total back to what was paid settles it again';

  v_res := public.edit_paid_invoice(v_inv,
    jsonb_build_array(jsonb_build_object('kind','product','product_id',v_p1,'quantity',8)),
    'Customer took three more of A');
  if (v_res->>'balance_due')::numeric <> 300 then
    raise exception 'FAIL 5: 800 owed against 500 paid leaves 300, got %', v_res->>'balance_due'; end if;
  if (v_res->>'status') <> 'partially_paid' then
    raise exception 'FAIL 5: it should be partially paid, got %', v_res->>'status'; end if;
  raise notice 'PASS 5b: raising it above what was paid leaves a balance and marks it partially paid';

  -- ===== 6. STOCK IS NOT ALLOWED TO GO NEGATIVE =====
  begin
    perform public.edit_paid_invoice(v_inv,
      jsonb_build_array(jsonb_build_object('kind','product','product_id',v_p1,'quantity',99999)),
      'Impossible quantity');
    raise exception 'FAIL 6: an edit beyond available stock must be refused';
  exception when others then
    if sqlerrm like '%Not enough stock%' then null; else raise; end if;
  end;
  raise notice 'PASS 6: an edit that would drive stock negative is refused';

  -- ===== 7. AN EMPTY INVOICE IS REFUSED =====
  begin
    perform public.edit_paid_invoice(v_inv, '[]'::jsonb, 'Remove everything');
    raise exception 'FAIL 7: emptying an invoice must be refused';
  exception when others then
    if sqlerrm like '%at least one line%' then null; else raise; end if;
  end;
  raise notice 'PASS 7: emptying an invoice is refused — cancel or refund it instead';

  raise notice '=== PAID INVOICE EDITING VERIFIED ===';
end $t$;

rollback;

begin;

do $t$
declare v_o uuid := gen_random_uuid(); v_store uuid; v_p uuid; v_pm uuid; v_c uuid; v_inv uuid;
begin
  insert into auth.users(id,email) values (v_o,'ei2@x.com');
  insert into public.profiles(id,full_name,email,role) values (v_o,'EI2','ei2@x.com','owner');
  perform set_config('request.jwt.claim.sub', v_o::text, true);
  insert into public.stores(name,code,country_code) values ('EI2 Store','EI2S','SG') returning id into v_store;
  insert into public.payment_methods(name) values ('EI2 Cash') returning id into v_pm;
  insert into public.products(name,sku,product_type) values ('EI2 P','EI2-1','own') returning id into v_p;
  insert into public.store_inventory(store_id,product_id,current_qty) values (v_store,v_p,100);
  perform public.set_product_prices(v_store, v_p, 100, 100, 'available');
  insert into public.customers(full_name,phone) values ('EI2 C','+6590360003') returning id into v_c;

  v_inv := public.create_invoice(v_store, v_c, null,
    jsonb_build_array(jsonb_build_object('kind','product','product_id',v_p,'quantity',2)), 0, 'EI2');
  perform public.pay_invoice(v_inv, jsonb_build_array(jsonb_build_object('payment_method_id',v_pm,'amount',200)));

  -- The ORDINARY edit path must still refuse a settled invoice.
  begin
    perform public.update_invoice(v_inv, v_c, null,
      jsonb_build_array(jsonb_build_object('kind','product','product_id',v_p,'quantity',1)),
      0, null, null, null, 'sneaky');
    raise exception 'FAIL: the ordinary edit path must still refuse a settled invoice';
  exception when others then
    if sqlerrm like '%locked%' or sqlerrm like '%Draft or Unpaid%' or sqlerrm like '%correction workflow%' then null; else raise; end if;
  end;
  raise notice 'PASS: the ordinary edit path still refuses settled invoices — the escape is not a general loophole';

  -- Payment rows are untouched by a corrective edit.
  perform public.edit_paid_invoice(v_inv,
    jsonb_build_array(jsonb_build_object('kind','product','product_id',v_p,'quantity',1)),
    'Corrected quantity');
  if (select count(*) from public.invoice_payments where invoice_id=v_inv) <> 1 then
    raise exception 'FAIL: the payment record must survive the edit'; end if;
  if (select amount from public.invoice_payments where invoice_id=v_inv) <> 200 then
    raise exception 'FAIL: the payment amount must be unchanged'; end if;
  raise notice 'PASS: the original payment record survives the edit, unchanged';

  if (select edit_count from public.invoices where id=v_inv) <> 1 then
    raise exception 'FAIL: the edit should be counted on the invoice'; end if;
  raise notice 'PASS: the invoice records that it has been edited';
  raise notice '=== EDIT SAFEGUARDS VERIFIED ===';
end $t$;

rollback;
