-- =====================================================================
-- PHASE 16 — TIKTOK STATUS + STOCK LIFECYCLE TESTS — run AFTER 65.
-- One transaction, ROLLED BACK. Seeds prefixed 'ZZP16-'.
-- =====================================================================

begin;

do $$
declare
  v_owner uuid := gen_random_uuid();
  v_staff uuid := gen_random_uuid();
  v_staff2 uuid := gen_random_uuid();
  v_invmgr uuid := gen_random_uuid();
  v_store uuid; v_store2 uuid; v_prod uuid; v_prod2 uuid;
  b1 uuid; b2 uuid; b3 uuid; b4 uuid; v_cb uuid;
  v_res jsonb; v_cnt integer; v_txt text; v_row record; v_rowid uuid; v_prid uuid;
  v_inv_before bigint; v_aff_before bigint; v_stf_before bigint;
begin
  -- =================== SEED ===================
  insert into auth.users (id, email) values (v_owner,'zzp16.o@example.com'),(v_staff,'zzp16.s@example.com'),
                                            (v_staff2,'zzp16.s2@example.com'),(v_invmgr,'zzp16.im@example.com');
  insert into public.profiles (id, full_name, email, role) values
    (v_owner,'ZZP16 Owner','zzp16.o@example.com','owner'),
    (v_staff,'ZZP16 Staff','zzp16.s@example.com','staff'),
    (v_staff2,'ZZP16 Staff2','zzp16.s2@example.com','staff'),
    (v_invmgr,'ZZP16 IM','zzp16.im@example.com','inventory_manager');
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);

  insert into public.stores (name, code, country_code) values ('ZZP16 Store','ZZP16A','SG') returning id into v_store;
  insert into public.stores (name, code, country_code) values ('ZZP16 Other','ZZP16B','SG') returning id into v_store2;
  insert into public.user_store_assignments (user_id, store_id) values (v_staff, v_store);

  insert into public.products (name, sku, product_type) values ('ZZP16 Widget','ZZP16-W','own') returning id into v_prod;
  insert into public.products (name, sku, product_type) values ('ZZP16 Tiny','ZZP16-T','own') returning id into v_prod2;
  insert into public.store_inventory (store_id, product_id, current_qty) values (v_store, v_prod, 20), (v_store, v_prod2, 1);
  perform public.upsert_tiktok_sku_alias(v_store, 'TT16-W', 'product', v_prod);
  perform public.upsert_tiktok_sku_alias(v_store, 'TT16-T', 'product', v_prod2);

  select count(*) into v_inv_before from public.invoices;
  select count(*) into v_aff_before from public.commissions;
  select count(*) into v_stf_before from public.staff_commissions;

  -- 1. Mappings: seeded deduct set incl. Paid / Ready to Ship; O/M-only
  --    management; custom deduct + 'No Stock Action' statuses work.
  select count(*) into v_cnt from public.tiktok_status_mappings
   where action = 'deduct' and status_norm in
     ('paid','to ship','awaiting shipment','ready to ship','shipped','in transit','delivered','completed');
  if v_cnt <> 8 then raise exception 'FAIL: expected the 8 seeded deducting statuses, got %', v_cnt; end if;
  perform public.upsert_tiktok_status_mapping('Preparing Gift', 'deduct', false, true);
  if public.tiktok_status_effect('preparing  gift') <> 'deduct' then
    raise exception 'FAIL: custom status mapping should deduct (normalised match)'; end if;
  perform public.upsert_tiktok_status_mapping('Arranging', 'none', false, true);
  if public.tiktok_status_effect('Arranging') <> 'none' then
    raise exception 'FAIL: No Stock Action mapping should return none'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_staff::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_staff::text, true);
  begin
    perform public.upsert_tiktok_status_mapping('Hacked', 'deduct', false, true);
    raise exception 'FAIL: staff must not manage status mappings';
  exception when others then
    if sqlerrm like '%Owners and Managers%' then null; else raise; end if;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  raise notice 'PASS: configurable status mappings (deduct/return/none) seeded; Owner/Manager only';

  -- 2. Stock deducts ONLY ONCE across the status lifecycle.
  b1 := public.stage_tiktok_orders(v_store, 'p16-a.xlsx', null, jsonb_build_array(
    jsonb_build_object('order_id','P16-1','seller_sku','TT16-W','quantity','1','order_status','Paid')));
  v_res := public.confirm_tiktok_batch(b1, null);
  select current_qty into v_cnt from public.store_inventory where store_id = v_store and product_id = v_prod;
  if v_cnt <> 19 then raise exception 'FAIL: Paid q1 should deduct 1 (20->19), got %', v_cnt; end if;
  b2 := public.stage_tiktok_orders(v_store, 'p16-b.xlsx', null, jsonb_build_array(
    jsonb_build_object('order_id','P16-1','seller_sku','TT16-W','quantity','1','order_status','Shipped')));
  select staging_status into v_txt from public.tiktok_order_rows where batch_id = b2;
  if v_txt <> 'Already Imported' then raise exception 'FAIL: Shipped q1 after Paid q1 should be Already Imported, got %', v_txt; end if;
  v_res := public.confirm_tiktok_batch(b2, null);
  b3 := public.stage_tiktok_orders(v_store, 'p16-c.xlsx', null, jsonb_build_array(
    jsonb_build_object('order_id','P16-1','seller_sku','TT16-W','quantity','1','order_status','Completed')));
  v_res := public.confirm_tiktok_batch(b3, null);
  select current_qty into v_cnt from public.store_inventory where store_id = v_store and product_id = v_prod;
  if v_cnt <> 19 then raise exception 'FAIL: stock must never deduct twice (still 19), got %', v_cnt; end if;
  raise notice 'PASS: To Ship/Paid -> Shipped -> Completed deducts exactly once';

  -- 3. Quantity changes apply only differences (up AND down-before-shipment).
  b1 := public.stage_tiktok_orders(v_store, 'p16-d.xlsx', null, jsonb_build_array(
    jsonb_build_object('order_id','P16-2','seller_sku','TT16-W','quantity','1','order_status','To Ship')));
  v_res := public.confirm_tiktok_batch(b1, null);   -- 19 -> 18
  b2 := public.stage_tiktok_orders(v_store, 'p16-e.xlsx', null, jsonb_build_array(
    jsonb_build_object('order_id','P16-2','seller_sku','TT16-W','quantity','3','order_status','To Ship')));
  select staging_status, stock_delta into v_row from public.tiktok_order_rows where batch_id = b2;
  if v_row.staging_status <> 'Updated — Additional Deduction' or v_row.stock_delta <> 2 then
    raise exception 'FAIL: 1->3 should deduct only the difference (2), got % / %', v_row.staging_status, v_row.stock_delta; end if;
  v_res := public.confirm_tiktok_batch(b2, null);   -- 18 -> 16
  b3 := public.stage_tiktok_orders(v_store, 'p16-f.xlsx', null, jsonb_build_array(
    jsonb_build_object('order_id','P16-2','seller_sku','TT16-W','quantity','2','order_status','Awaiting Shipment')));
  select staging_status, stock_delta into v_row from public.tiktok_order_rows where batch_id = b3;
  if v_row.staging_status <> 'Updated — Stock Return' or v_row.stock_delta <> -1 then
    raise exception 'FAIL: 3->2 before shipment should return only the difference (-1), got % / %', v_row.staging_status, v_row.stock_delta; end if;
  v_res := public.confirm_tiktok_batch(b3, null);   -- 16 -> 17
  select current_qty into v_cnt from public.store_inventory where store_id = v_store and product_id = v_prod;
  if v_cnt <> 17 then raise exception 'FAIL: after 1,+2,-1 stock should be 17, got %', v_cnt; end if;
  raise notice 'PASS: quantity increases deduct only the difference; decreases before shipment return only the difference';

  -- 4. Cancellation BEFORE shipment: automatic staged return, applied at confirm.
  b1 := public.stage_tiktok_orders(v_store, 'p16-g.xlsx', null, jsonb_build_array(
    jsonb_build_object('order_id','P16-2','seller_sku','TT16-W','quantity','2','order_status','Cancelled')));
  select staging_status, stock_delta into v_row from public.tiktok_order_rows where batch_id = b1;
  if v_row.staging_status <> 'Updated — Stock Return' or v_row.stock_delta <> -2 then
    raise exception 'FAIL: pre-shipment cancellation should stage an automatic return of -2, got % / %', v_row.staging_status, v_row.stock_delta; end if;
  v_res := public.confirm_tiktok_batch(b1, null);   -- 17 -> 19
  select current_qty into v_cnt from public.store_inventory where store_id = v_store and product_id = v_prod;
  if v_cnt <> 19 then raise exception 'FAIL: pre-shipment cancellation should restock (19), got %', v_cnt; end if;
  raise notice 'PASS: cancellation before shipment stages an automatic return, applied on confirmation';

  -- 5. Cancellation AFTER shipment: NO automatic return -> Awaiting Physical Return.
  --    (P16-1 was confirmed Shipped/Completed above, so it is marked shipped.)
  b2 := public.stage_tiktok_orders(v_store, 'p16-h.xlsx', null, jsonb_build_array(
    jsonb_build_object('order_id','P16-1','seller_sku','TT16-W','quantity','1','order_status','Cancelled')));
  select staging_status, stock_delta into v_row from public.tiktok_order_rows where batch_id = b2;
  if v_row.staging_status <> 'Awaiting Physical Return' or v_row.stock_delta <> 0 then
    raise exception 'FAIL: post-shipment cancellation must not auto-return, got % / %', v_row.staging_status, v_row.stock_delta; end if;
  v_res := public.confirm_tiktok_batch(b2, null);
  select current_qty into v_cnt from public.store_inventory where store_id = v_store and product_id = v_prod;
  if v_cnt <> 19 then raise exception 'FAIL: post-shipment cancellation must not move stock, got %', v_cnt; end if;
  select id, expected_qty into v_prid, v_cnt from public.tiktok_physical_returns
   where store_id = v_store and order_id = 'P16-1' and status = 'awaiting';
  if v_prid is null or v_cnt <> 1 then
    raise exception 'FAIL: an awaiting physical-return record (qty 1) should exist'; end if;
  raise notice 'PASS: cancellation after shipment marks Awaiting Physical Return without touching stock';

  -- 6. Physical return: assigned-store Staff may restock; others may not.
  perform set_config('request.jwt.claims', json_build_object('sub', v_invmgr::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_invmgr::text, true);
  begin
    perform public.resolve_tiktok_physical_return(v_prid, true, null, null);
    raise exception 'FAIL: inventory manager is not in the physical-return confirmer list';
  exception when others then
    if sqlerrm like '%Staff assigned to this store%' then null; else raise; end if;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', v_staff2::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_staff2::text, true);
  begin
    perform public.resolve_tiktok_physical_return(v_prid, true, null, null);
    raise exception 'FAIL: staff of another store must not confirm';
  exception when others then
    if sqlerrm like '%Staff assigned to this store%' then null; else raise; end if;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', v_staff::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_staff::text, true);
  perform public.resolve_tiktok_physical_return(v_prid, true, null, 'came back sealed');
  select current_qty into v_cnt from public.store_inventory where store_id = v_store and product_id = v_prod;
  if v_cnt <> 20 then raise exception 'FAIL: restocked physical return should add 1 back (20), got %', v_cnt; end if;
  select deducted_qty into v_cnt from public.tiktok_order_state
   where store_id = v_store and order_id = 'P16-1' and seller_sku = 'TT16-W';
  if v_cnt <> 0 then raise exception 'FAIL: state should drop to 0 after restock, got %', v_cnt; end if;
  raise notice 'PASS: physical returns restock via Owner/Manager or assigned-store Staff only';

  -- 7. No Stock Return: mandatory categorised reason; no stock movement.
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  b1 := public.stage_tiktok_orders(v_store, 'p16-i.xlsx', null, jsonb_build_array(
    jsonb_build_object('order_id','P16-3','seller_sku','TT16-W','quantity','2','order_status','Delivered')));
  v_res := public.confirm_tiktok_batch(b1, null);   -- 20 -> 18, shipped
  b2 := public.stage_tiktok_orders(v_store, 'p16-j.xlsx', null, jsonb_build_array(
    jsonb_build_object('order_id','P16-3','seller_sku','TT16-W','quantity','2','order_status','Returned')));
  v_res := public.confirm_tiktok_batch(b2, null);
  select id into v_prid from public.tiktok_physical_returns
   where store_id = v_store and order_id = 'P16-3' and status = 'awaiting';
  begin
    perform public.resolve_tiktok_physical_return(v_prid, false, null, null);
    raise exception 'FAIL: No Stock Return without a reason must be refused';
  exception when others then
    if sqlerrm like '%requires a reason%' then null; else raise; end if;
  end;
  begin
    perform public.resolve_tiktok_physical_return(v_prid, false, 'other', null);
    raise exception 'FAIL: reason "other" without a note must be refused';
  exception when others then
    if sqlerrm like '%describe the reason%' then null; else raise; end if;
  end;
  perform public.resolve_tiktok_physical_return(v_prid, false, 'damaged', null);
  select current_qty into v_cnt from public.store_inventory where store_id = v_store and product_id = v_prod;
  if v_cnt <> 18 then raise exception 'FAIL: No Stock Return must not move stock (18), got %', v_cnt; end if;
  begin
    perform public.resolve_tiktok_physical_return(v_prid, true, null, null);
    raise exception 'FAIL: an already-resolved return must be refused';
  exception when others then
    if sqlerrm like '%already resolved%' then null; else raise; end if;
  end;
  raise notice 'PASS: No Stock Return demands a categorised reason (note for other) and leaves stock alone';

  -- 8. Negative stock: explicit gate, TikTok-only.
  b1 := public.stage_tiktok_orders(v_store, 'p16-k.xlsx', null, jsonb_build_array(
    jsonb_build_object('order_id','P16-4','seller_sku','TT16-T','quantity','3','order_status','To Ship')));
  select staging_status into v_txt from public.tiktok_order_rows where batch_id = b1;
  if v_txt <> 'Negative Stock Warning' then raise exception 'FAIL: 3 > 1 in stock should warn, got %', v_txt; end if;
  begin
    v_res := public.confirm_tiktok_batch(b1, null);
    raise exception 'FAIL: confirming into negative without the explicit flag must be refused';
  exception when others then
    if sqlerrm like '%NEGATIVE_STOCK_CONFIRMATION_REQUIRED%' then null; else raise; end if;
  end;
  begin
    v_res := public.confirm_tiktok_batch(b1, null, true, null);
    raise exception 'FAIL: negative confirmation without a reason must be refused';
  exception when others then
    if sqlerrm like '%reason is required%' then null; else raise; end if;
  end;
  -- Staff may confirm negative TikTok stock (per spec).
  perform set_config('request.jwt.claims', json_build_object('sub', v_staff::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_staff::text, true);
  v_res := public.confirm_tiktok_batch(b1, null, true, 'TikTok LIVE oversold; replenishment already ordered');
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  select current_qty into v_cnt from public.store_inventory where store_id = v_store and product_id = v_prod2;
  if v_cnt <> -2 then raise exception 'FAIL: confirmed TikTok sale should drive stock to -2, got %', v_cnt; end if;
  select count(*) into v_cnt from public.audit_logs
   where action = 'tiktok_negative_stock_confirmed' and record_id = b1;
  if v_cnt <> 1 then raise exception 'FAIL: negative confirmation must write an audit entry'; end if;
  select count(*) into v_cnt from public.tiktok_negative_stock_alerts() where current_qty < 0;
  if v_cnt < 1 then raise exception 'FAIL: dashboard alert should list negative TikTok stock'; end if;
  -- Everything else keeps blocking negative stock.
  begin
    update public.store_inventory set current_qty = -5 where store_id = v_store and product_id = v_prod;
    raise exception 'FAIL: non-TikTok paths must still block negative stock';
  exception when others then
    if sqlerrm like '%cannot go negative%' then null; else raise; end if;
  end;
  raise notice 'PASS: negative stock needs warning + explicit confirmation + reason + audit + alert, and stays TikTok-only';

  -- 9. Versioning: linked immutable versions with previous values and
  --    stock/financial differences.
  b2 := public.stage_tiktok_orders(v_store, 'p16-l.xlsx', null, jsonb_build_array(
    jsonb_build_object('order_id','P16-5','seller_sku','TT16-W','quantity','1','order_status','To Ship','sku_subtotal_after','50.00')));
  v_res := public.confirm_tiktok_batch(b2, null);   -- 18 -> 17
  b3 := public.stage_tiktok_orders(v_store, 'p16-m.xlsx', null, jsonb_build_array(
    jsonb_build_object('order_id','P16-5','seller_sku','TT16-W','quantity','2','order_status','To Ship','sku_subtotal_after','95.00')));
  select * into v_row from public.tiktok_order_rows where batch_id = b3;
  select id into v_rowid from public.tiktok_order_rows where batch_id = b2;
  if v_row.previous_row_id is distinct from v_rowid then raise exception 'FAIL: v2 must link the confirmed v1 row'; end if;
  if v_row.version_no <> 2 then raise exception 'FAIL: version_no should be 2, got %', v_row.version_no; end if;
  if v_row.prev_quantity <> 1 or v_row.prev_order_status <> 'To Ship' then
    raise exception 'FAIL: previous values must be carried on the new version'; end if;
  if v_row.stock_delta <> 1 then raise exception 'FAIL: stock difference should be +1, got %', v_row.stock_delta; end if;
  if v_row.financial_delta <> 45.00 then raise exception 'FAIL: financial difference should be 45.00, got %', v_row.financial_delta; end if;
  -- Old confirmed version is immutable.
  begin
    update public.tiktok_order_rows set quantity = 99 where id = v_rowid;
    raise exception 'FAIL: confirmed rows must be immutable';
  exception when others then
    if sqlerrm like '%immutable%' then null; else raise; end if;
  end;
  begin
    delete from public.tiktok_order_rows where id = v_rowid;
    raise exception 'FAIL: confirmed rows must not be deletable';
  exception when others then
    if sqlerrm like '%immutable%' then null; else raise; end if;
  end;
  select quantity into v_cnt from public.tiktok_order_rows where id = v_rowid;
  if v_cnt <> 1 then raise exception 'FAIL: v1 values must remain available'; end if;
  raise notice 'PASS: re-imports create linked immutable versions with previous values + stock/financial differences';

  -- 10. Correction batches: Owner/Manager only, reversing stock movements,
  --     linked + audited; confirmed batches still undeletable.
  perform set_config('request.jwt.claims', json_build_object('sub', v_staff::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_staff::text, true);
  begin
    v_cb := public.create_tiktok_correction_batch(b2,
      jsonb_build_array(jsonb_build_object('row_id', v_rowid, 'qty_delta', -1)), 'staff tries');
    raise exception 'FAIL: staff must not create correction batches';
  exception when others then
    if sqlerrm like '%Owners and Managers%' then null; else raise; end if;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  v_cb := public.create_tiktok_correction_batch(b2,
    jsonb_build_array(jsonb_build_object('row_id', v_rowid, 'qty_delta', -1)), 'one unit refunded off-platform');
  select file_kind, corrects_batch_id into v_row from public.tiktok_import_batches where id = v_cb;
  if v_row.file_kind <> 'correction' or v_row.corrects_batch_id <> b2 then
    raise exception 'FAIL: correction batch must be linked to the corrected batch'; end if;
  select count(*) into v_cnt from public.tiktok_corrections where correction_batch_id = v_cb;
  if v_cnt <> 1 then raise exception 'FAIL: correction row must reference the correction batch'; end if;
  select count(*) into v_cnt from public.stock_movements
   where product_id = v_prod and movement_type = 'inventory_adjustment' and notes like 'TikTok correction%';
  if v_cnt < 1 then raise exception 'FAIL: corrections must use reversing stock movements'; end if;
  begin
    perform public.delete_tiktok_batch(b2);
    raise exception 'FAIL: confirmed batches must not be deletable';
  exception when others then
    if sqlerrm like '%correction instead%' then null; else raise; end if;
  end;
  raise notice 'PASS: correction batches are Owner/Manager-only, use reversing movements, and are linked + audited';

  -- 11. The whole TikTok flow created no invoices and no commissions.
  select count(*) - v_inv_before into v_cnt from public.invoices;
  if v_cnt <> 0 then raise exception 'FAIL: TikTok imports must not create invoices, created %', v_cnt; end if;
  select count(*) - v_aff_before into v_cnt from public.commissions;
  if v_cnt <> 0 then raise exception 'FAIL: TikTok imports must not create affiliate commissions'; end if;
  select count(*) - v_stf_before into v_cnt from public.staff_commissions;
  if v_cnt <> 0 then raise exception 'FAIL: TikTok imports must not create staff commissions'; end if;
  raise notice 'PASS: no invoices and no affiliate/staff commissions from the entire TikTok lifecycle';

  raise notice '=== ALL PHASE 16 TIKTOK LIFECYCLE DB TESTS PASSED ===';
end $$;

rollback;
