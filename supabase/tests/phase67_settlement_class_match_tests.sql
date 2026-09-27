-- TIKTOK SETTLEMENT: CLASSIFICATION, MATCHING AND DUPLICATE RULES
begin;
do $t$
declare v_o uuid := gen_random_uuid(); v_st uuid; v_n integer; v_txt text;
begin
  insert into auth.users(id,email) values (v_o,'tt@x.com');
  insert into public.profiles(id,full_name,email,role,is_active) values (v_o,'TT','tt@x.com','owner',true);
  perform set_config('request.jwt.claims', json_build_object('sub',v_o::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_o::text, true);
  insert into public.stores(name,code,country_code) values ('TT Store','TTS','SG') returning id into v_st;

  -- ===== 1. GMV ads rows are classified as finance, not order =====
  if public.tiktok_txn_class('GMV payment for TikTok Ads') <> 'finance' then
    raise exception 'FAIL 1: GMV ads should be finance, got %',
      public.tiktok_txn_class('GMV payment for TikTok Ads'); end if;
  raise notice 'PASS 1: "GMV payment for TikTok Ads" is classified as a platform finance row';

  -- ===== 2. AND NEVER MATCH A CUSTOMER ORDER =====
  -- Plant an order whose id equals the ads transaction id: a worst case.
  insert into public.tiktok_order_state(store_id, order_id, seller_sku, last_status)
  values (v_st, '3679669423061370507', 'SKU-1', 'confirmed') on conflict do nothing;
  v_txt := public.tiktok_settlement_match(v_st, '3679669423061370507', null, 'finance');
  if v_txt is not null then
    raise exception 'FAIL 2: a finance row must not match an order, got %', v_txt; end if;
  raise notice 'PASS 2: even with a colliding id, a finance row matches no customer order';

  -- ===== 3. A REAL ORDER ROW STILL MATCHES BY ORDER ID =====
  insert into public.tiktok_order_state(store_id, order_id, seller_sku, last_status)
  values (v_st, '585386780484273402', 'SKU-1', 'confirmed') on conflict do nothing;
  if public.tiktok_settlement_match(v_st, '585386780484273402', null, 'order')
     <> '585386780484273402' then
    raise exception 'FAIL 3: an order row should match on its order id'; end if;
  raise notice 'PASS 3: an Order row matches tiktok_order_state on Order ID';

  -- ===== 4. A REFUND PREFERS THE RELATED ORDER ID =====
  insert into public.tiktok_order_state(store_id, order_id, seller_sku, last_status)
  values (v_st, '585385879167403081', 'SKU-1', 'confirmed') on conflict do nothing;
  if public.tiktok_settlement_match(v_st, 'ADJ-999', '585385879167403081', 'refund')
     <> '585385879167403081' then
    raise exception 'FAIL 4: a refund should prefer the related order id'; end if;
  raise notice 'PASS 4: a refund matches on Related Order ID, not the adjustment id';

  -- ===== 5. THE REFUND FALLBACK STILL WORKS =====
  if public.tiktok_settlement_match(v_st, '585386780484273402', null, 'refund')
     <> '585386780484273402' then
    raise exception 'FAIL 5: with no related id it should fall back to the order id'; end if;
  raise notice 'PASS 5: with no Related Order ID it falls back to Order/Adjustment ID';

  -- ===== 6. THE OTHER CLASSES ARE UNCHANGED =====
  if public.tiktok_txn_class('Order') <> 'order' then raise exception 'FAIL 6: Order'; end if;
  if public.tiktok_txn_class('Customer refund') <> 'refund' then raise exception 'FAIL 6: refund'; end if;
  if public.tiktok_txn_class('Adjustment') <> 'adjustment' then raise exception 'FAIL 6: adjustment'; end if;
  raise notice 'PASS 6: Order, refund and adjustment classification is unchanged';

  raise notice '=== SETTLEMENT CLASSIFICATION AND MATCHING VERIFIED ===';
end $t$;
rollback;
