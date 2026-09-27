-- =====================================================================
-- PHASE 15 — TIKTOK IMPORT FOUNDATION TESTS — run AFTER 64.
-- One transaction, ROLLED BACK. Seeds prefixed 'ZZP15-'.
-- =====================================================================

begin;

do $$
declare
  v_owner uuid := gen_random_uuid();
  v_staff uuid := gen_random_uuid();
  v_store uuid; v_store2 uuid; v_prod uuid; v_prod2 uuid; v_vch uuid; v_promo uuid; v_inact uuid;
  v_batch uuid; v_batch2 uuid; v_batch3 uuid; v_res jsonb; v_cnt integer; v_num integer; v_txt text;
  v_row record; v_rowid uuid;
  -- A 19-digit TikTok order id: far beyond JS Number.MAX_SAFE_INTEGER.
  v_bigid text := '5764613744902348861';
begin
  -- =================== SEED ===================
  insert into auth.users (id, email) values (v_owner, 'zzp15.owner@example.com');
  insert into public.profiles (id, full_name, email, role) values (v_owner, 'ZZP15 Owner', 'zzp15.owner@example.com', 'owner');
  insert into auth.users (id, email) values (v_staff, 'zzp15.staff@example.com');
  insert into public.profiles (id, full_name, email, role) values (v_staff, 'ZZP15 Staff', 'zzp15.staff@example.com', 'staff');
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);

  insert into public.stores (name, code, country_code) values ('ZZP15 Store','ZZP15A','SG') returning id into v_store;
  insert into public.stores (name, code, country_code) values ('ZZP15 Other','ZZP15B','SG') returning id into v_store2;
  insert into public.user_store_assignments (user_id, store_id) values (v_staff, v_store);

  insert into public.products (name, sku, product_type) values ('ZZP15 Widget','ZZP15-W','own') returning id into v_prod;
  insert into public.products (name, sku, product_type) values ('ZZP15 Gadget','ZZP15-G','own') returning id into v_prod2;
  insert into public.products (name, sku, product_type, is_active) values ('ZZP15 Dead','ZZP15-D','own', false) returning id into v_inact;
  insert into public.store_inventory (store_id, product_id, current_qty) values (v_store, v_prod, 10), (v_store, v_prod2, 100);

  insert into public.vouchers (name, code, voucher_kind, qty_type) values ('ZZP15 V','ZZP15V','normal','limited') returning id into v_vch;
  insert into public.voucher_store_stock (voucher_id, store_id, current_qty) values (v_vch, v_store, 5);

  insert into public.promotions (name, code) values ('ZZP15 Bundle','ZZP15B') returning id into v_promo;
  insert into public.promotion_items (promotion_id, item_type, product_id, quantity) values (v_promo, 'product', v_prod2, 2);
  insert into public.promotion_items (promotion_id, item_type, voucher_id, quantity) values (v_promo, 'voucher', v_vch, 1);

  -- 1. Aliases: exact case-sensitive, remembered per store, inactive blocked.
  perform public.upsert_tiktok_sku_alias(v_store, 'TT-WIDGET', 'product', v_prod);
  perform public.upsert_tiktok_sku_alias(v_store, 'TT-VOUCH', 'voucher', v_vch);
  perform public.upsert_tiktok_sku_alias(v_store, 'TT-BUNDLE', 'promotion', v_promo);
  begin
    perform public.upsert_tiktok_sku_alias(v_store, 'TT-DEAD', 'product', v_inact);
    raise exception 'FAIL: mapping to an inactive product must be blocked';
  exception when others then
    if sqlerrm like '%inactive%' then null; else raise; end if;
  end;
  raise notice 'PASS: SKU aliases map to product/voucher/promotion per store; inactive targets are blocked';

  -- 2. Staging: statuses computed, huge IDs exact, and NO stock movement.
  v_batch := public.stage_tiktok_orders(v_store, 'weird file name (7).xlsx', 'Sheet3',
    jsonb_build_array(
      jsonb_build_object('order_id', v_bigid, 'seller_sku','TT-WIDGET','quantity','3','order_status','To ship',
                         'product_name','Widget','created_time','2026-07-01 10:00:00','payment_method','TikTok Pay'),
      jsonb_build_object('order_id', v_bigid, 'seller_sku','TT-WIDGET','quantity','3','order_status','To ship'),      -- dup in-file
      jsonb_build_object('order_id','ORD-2','seller_sku','tt-widget','quantity','1','order_status','To ship'),        -- case mismatch
      jsonb_build_object('order_id','ORD-3','seller_sku','TT-WIDGET','quantity','2','order_status','Weird Status'),   -- invalid status
      jsonb_build_object('order_id','','seller_sku','TT-WIDGET','quantity','1','order_status','To ship'),             -- invalid row
      jsonb_build_object('order_id','ORD-5','seller_sku','TT-WIDGET','quantity','99','order_status','Delivered'),     -- neg stock warn
      jsonb_build_object('order_id','ORD-6','seller_sku','TT-VOUCH','quantity','2','order_status','Awaiting Shipment'),
      jsonb_build_object('order_id','ORD-7','seller_sku','TT-BUNDLE','quantity','3','order_status','Shipped')
    ));

  select count(*) into v_cnt from public.tiktok_order_rows where batch_id = v_batch;
  if v_cnt <> 8 then raise exception 'FAIL: expected 8 staged rows, got %', v_cnt; end if;
  select order_id into v_txt from public.tiktok_order_rows where batch_id = v_batch and row_no = 1;
  if v_txt <> v_bigid then raise exception 'FAIL: 19-digit order ID must stay exact, got %', v_txt; end if;
  select staging_status into v_txt from public.tiktok_order_rows where batch_id = v_batch and row_no = 1;
  if v_txt <> 'New — Will Deduct' then raise exception 'FAIL: row1 should be New — Will Deduct, got %', v_txt; end if;
  select staging_status into v_txt from public.tiktok_order_rows where batch_id = v_batch and row_no = 2;
  if v_txt <> 'Duplicate Row' then raise exception 'FAIL: in-file duplicate should be Duplicate Row, got %', v_txt; end if;
  select staging_status into v_txt from public.tiktok_order_rows where batch_id = v_batch and row_no = 3;
  if v_txt <> 'Unmatched SKU' then raise exception 'FAIL: lowercase sku must NOT match (case-sensitive), got %', v_txt; end if;
  select staging_status into v_txt from public.tiktok_order_rows where batch_id = v_batch and row_no = 4;
  if v_txt <> 'Invalid Status' then raise exception 'FAIL: unknown status should be Invalid Status, got %', v_txt; end if;
  select staging_status into v_txt from public.tiktok_order_rows where batch_id = v_batch and row_no = 5;
  if v_txt <> 'Invalid Row' then raise exception 'FAIL: missing order id should be Invalid Row, got %', v_txt; end if;
  select staging_status into v_txt from public.tiktok_order_rows where batch_id = v_batch and row_no = 6;
  if v_txt <> 'Negative Stock Warning' then raise exception 'FAIL: 99 > 10 in stock should warn, got %', v_txt; end if;
  select current_qty into v_cnt from public.store_inventory where store_id = v_store and product_id = v_prod;
  if v_cnt <> 10 then raise exception 'FAIL: staging must not touch stock (widget), got %', v_cnt; end if;
  select current_qty into v_cnt from public.voucher_store_stock where store_id = v_store and voucher_id = v_vch;
  if v_cnt <> 5 then raise exception 'FAIL: staging must not touch voucher stock, got %', v_cnt; end if;
  select created_time into v_row from public.tiktok_order_rows where batch_id = v_batch and row_no = 1;
  if to_char(v_row.created_time at time zone 'Asia/Singapore', 'YYYY-MM-DD HH24:MI') <> '2026-07-01 10:00' then
    raise exception 'FAIL: times must be interpreted in Singapore time'; end if;
  raise notice 'PASS: staging computes every status, keeps 19-digit IDs exact, stores SG times, and moves NO stock';

  -- 3. Mapping later + refresh turns Unmatched into confirmable.
  perform public.upsert_tiktok_sku_alias(v_store, 'tt-widget', 'product', v_prod2);
  perform public.refresh_tiktok_staging(v_batch);
  select staging_status into v_txt from public.tiktok_order_rows where batch_id = v_batch and row_no = 3;
  if v_txt <> 'New — Will Deduct' then raise exception 'FAIL: after mapping, row3 should become confirmable, got %', v_txt; end if;
  raise notice 'PASS: manual mapping is remembered and re-staging updates statuses';

  -- 4. Row management: exclude + remove staged rows.
  select id into v_rowid from public.tiktok_order_rows where batch_id = v_batch and row_no = 6;
  perform public.set_tiktok_row_excluded(v_rowid, true);        -- keep the 99-qty out
  select id into v_rowid from public.tiktok_order_rows where batch_id = v_batch and row_no = 4;
  perform public.delete_tiktok_row(v_rowid);
  select count(*) into v_cnt from public.tiktok_order_rows where batch_id = v_batch;
  if v_cnt <> 7 then raise exception 'FAIL: expected 7 rows after removal, got %', v_cnt; end if;
  raise notice 'PASS: staged rows can be excluded and removed';

  -- 5. Confirm: product, voucher (with unassigned issuance) and promotion
  --    components all deduct; duplicates/invalid/excluded rows do not.
  v_res := public.confirm_tiktok_batch(v_batch, null);
  select current_qty into v_cnt from public.store_inventory where store_id = v_store and product_id = v_prod;
  if v_cnt <> 7 then raise exception 'FAIL: widget stock should be 10-3=7, got %', v_cnt; end if;
  -- prod2: ORD-2 (1) + bundle ORD-7 (3 x 2 components = 6) = 7 -> 93
  select current_qty into v_cnt from public.store_inventory where store_id = v_store and product_id = v_prod2;
  if v_cnt <> 93 then raise exception 'FAIL: gadget stock should be 100-1-6=93, got %', v_cnt; end if;
  -- voucher: ORD-6 (2) + bundle component (3 x 1 = 3) = 5 -> 0
  select current_qty into v_cnt from public.voucher_store_stock where store_id = v_store and voucher_id = v_vch;
  if v_cnt <> 0 then raise exception 'FAIL: voucher stock should be 5-2-3=0, got %', v_cnt; end if;
  select count(*), coalesce(sum(quantity),0) into v_cnt, v_num from public.tiktok_voucher_sales
    where store_id = v_store and voucher_id = v_vch and order_row_id is not null;
  if v_cnt <> 1 or v_num <> 2 then
    raise exception 'FAIL: expected one unassigned voucher issuance of 2 linked to the order row, got %/%', v_cnt, v_num; end if;
  select status into v_txt from public.tiktok_import_batches where id = v_batch;
  if v_txt <> 'confirmed' then raise exception 'FAIL: batch should be confirmed'; end if;
  raise notice 'PASS: confirmation deducts product, voucher (+unassigned linked issuance, no customer) and promotion components';

  -- 6. Confirmed batches are locked (staging + delete + re-confirm refused).
  select id into v_rowid from public.tiktok_order_rows where batch_id = v_batch and row_no = 1;
  begin
    perform public.set_tiktok_row_excluded(v_rowid, true);
    raise exception 'FAIL: confirmed batch rows must be locked';
  exception when others then
    if sqlerrm like '%locked%' then null; else raise; end if;
  end;
  begin
    v_res := public.confirm_tiktok_batch(v_batch, null);
    raise exception 'FAIL: double confirmation must be refused';
  exception when others then
    if sqlerrm like '%already confirmed%' then null; else raise; end if;
  end;
  begin
    perform public.delete_tiktok_batch(v_batch);
    raise exception 'FAIL: confirmed batch must not be deletable';
  exception when others then
    if sqlerrm like '%correction instead%' then null; else raise; end if;
  end;
  raise notice 'PASS: confirmed batches are locked';

  -- 7. Re-import same order: Already Imported (no change), higher qty:
  --    Additional Deduction, cancelled: Stock Return.
  v_batch2 := public.stage_tiktok_orders(v_store, 're-export.csv', null,
    jsonb_build_array(
      jsonb_build_object('order_id', v_bigid, 'seller_sku','TT-WIDGET','quantity','3','order_status','Delivered'),
      jsonb_build_object('order_id','ORD-2','seller_sku','tt-widget','quantity','4','order_status','Shipped'),
      jsonb_build_object('order_id','ORD-6','seller_sku','TT-VOUCH','quantity','2','order_status','Cancelled')
    ));
  select staging_status into v_txt from public.tiktok_order_rows where batch_id = v_batch2 and row_no = 1;
  if v_txt <> 'Already Imported' then raise exception 'FAIL: same qty re-import should be Already Imported, got %', v_txt; end if;
  select staging_status, stock_delta into v_row from public.tiktok_order_rows where batch_id = v_batch2 and row_no = 2;
  if v_row.staging_status <> 'Updated — Additional Deduction' or v_row.stock_delta <> 3 then
    raise exception 'FAIL: 1->4 should be Additional Deduction of 3, got % / %', v_row.staging_status, v_row.stock_delta; end if;
  select staging_status, stock_delta into v_row from public.tiktok_order_rows where batch_id = v_batch2 and row_no = 3;
  if v_row.staging_status <> 'Updated — Stock Return' or v_row.stock_delta <> -2 then
    raise exception 'FAIL: cancellation should be Stock Return of -2, got % / %', v_row.staging_status, v_row.stock_delta; end if;
  v_res := public.confirm_tiktok_batch(v_batch2, null);
  select current_qty into v_cnt from public.store_inventory where store_id = v_store and product_id = v_prod2;
  if v_cnt <> 90 then raise exception 'FAIL: gadget should be 93-3=90 after additional deduction, got %', v_cnt; end if;
  select current_qty into v_cnt from public.voucher_store_stock where store_id = v_store and voucher_id = v_vch;
  if v_cnt <> 2 then raise exception 'FAIL: voucher should be 0+2=2 after return, got %', v_cnt; end if;
  raise notice 'PASS: cumulative state drives Already Imported / Additional Deduction / Stock Return correctly';

  -- 8. Staff: pinned to their assigned store; other stores refused.
  perform set_config('request.jwt.claims', json_build_object('sub', v_staff::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_staff::text, true);
  v_batch3 := public.stage_tiktok_orders(v_store, 'staff.csv', null,
    jsonb_build_array(jsonb_build_object('order_id','ORD-S1','seller_sku','TT-WIDGET','quantity','1','order_status','To ship')));
  begin
    perform public.stage_tiktok_orders(v_store2, 'staff.csv', null,
      jsonb_build_array(jsonb_build_object('order_id','ORD-S2','seller_sku','X','quantity','1','order_status','To ship')));
    raise exception 'FAIL: staff must not import for other stores';
  exception when others then
    if sqlerrm like '%assigned store%' then null; else raise; end if;
  end;
  -- Staff cannot delete batches or correct confirmed rows.
  begin
    perform public.delete_tiktok_batch(v_batch3);
    raise exception 'FAIL: staff must not delete batches';
  exception when others then
    if sqlerrm like '%Owners and Managers%' then null; else raise; end if;
  end;
  select id into v_rowid from public.tiktok_order_rows where batch_id = v_batch and row_no = 1;
  begin
    perform public.correct_tiktok_row(v_rowid, -1, 'staff tries');
    raise exception 'FAIL: staff must not create corrections';
  exception when others then
    if sqlerrm like '%Owners and Managers%' then null; else raise; end if;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  raise notice 'PASS: staff limited to assigned store; batch deletion and corrections are Owner/Manager only';

  -- 9. Owner deletes an unconfirmed batch; owner corrects a confirmed row.
  perform public.delete_tiktok_batch(v_batch3);
  select deleted_at is not null into v_row from public.tiktok_import_batches where id = v_batch3;
  select current_qty into v_cnt from public.store_inventory where store_id = v_store and product_id = v_prod;
  if v_cnt <> 7 then raise exception 'FAIL: deleting a staged batch must not touch stock, got %', v_cnt; end if;
  select id into v_rowid from public.tiktok_order_rows where batch_id = v_batch and row_no = 1;   -- widget, deducted 3
  perform public.correct_tiktok_row(v_rowid, -1, 'one unit came back damaged');
  select current_qty into v_cnt from public.store_inventory where store_id = v_store and product_id = v_prod;
  if v_cnt <> 8 then raise exception 'FAIL: correction of -1 should return one widget (7->8), got %', v_cnt; end if;
  select count(*) into v_cnt from public.tiktok_corrections where order_row_id = v_rowid;
  if v_cnt <> 1 then raise exception 'FAIL: correction record missing'; end if;
  raise notice 'PASS: Owner/Manager delete staged batches (no stock effect) and correct confirmed rows (stock + record)';

  -- 10. Settlement file staging stores rows with exact IDs; report works.
  v_batch3 := public.stage_tiktok_settlement(v_store, 'settlement Q3 (final).xlsx', 'income',
    jsonb_build_array(jsonb_build_object('order_id', v_bigid, 'settlement_amount','48.35','fee_amount','1.65','currency','SGD',
                                         'settled_time','2026-07-02 09:30:00')));
  select order_id into v_txt from public.tiktok_settlement_rows where batch_id = v_batch3;
  if v_txt <> v_bigid then raise exception 'FAIL: settlement order id must stay exact'; end if;
  select count(*) into v_cnt from public.report_tiktok_imports(v_store, null, null);
  if v_cnt < 3 then raise exception 'FAIL: report should list the batches, got %', v_cnt; end if;
  raise notice 'PASS: settlement files stage with exact IDs; import report lists batches';

  raise notice '=== ALL PHASE 15 TIKTOK IMPORT DB TESTS PASSED ===';
end $$;

rollback;
