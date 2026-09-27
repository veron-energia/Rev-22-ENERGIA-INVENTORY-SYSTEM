-- PLATFORM FINANCE ROWS IMPORT WITHOUT VIOLATING THE txn_class CHECK
begin;
do $t$
declare
  v_o uuid := gen_random_uuid(); v_st uuid; v_batch uuid; v_n integer; v_row record;
begin
  insert into auth.users(id,email) values (v_o,'fin@x.com');
  insert into public.profiles(id,full_name,email,role,is_active) values (v_o,'FIN','fin@x.com','owner',true);
  perform set_config('request.jwt.claims', json_build_object('sub',v_o::text)::text, true);
  perform set_config('request.jwt.claim.sub', v_o::text, true);
  insert into public.stores(name,code,country_code) values ('FIN Store','FINS','SG') returning id into v_st;
  -- A confirmed order for the Order rows to match against.
  insert into public.tiktok_order_state(store_id, order_id, seller_sku, last_status)
  values (v_st,'585386780484273402','SKU-1','confirmed'),
         (v_st,'585244041338652508','SKU-1','confirmed') on conflict do nothing;

  -- The real file's shape: 3 ad rows, several Order rows, one repeated order.
  v_batch := public.stage_tiktok_settlement(v_st, 'settlement.xlsx', 'Sheet1', jsonb_build_array(
    jsonb_build_object('order_id','3679669423061370507','transaction_type','GMV payment for TikTok Ads','settlement_amount','120.00'),
    jsonb_build_object('order_id','3679583967964792459','transaction_type','GMV payment for TikTok Ads','settlement_amount','80.00'),
    jsonb_build_object('order_id','3679434095785117323','transaction_type','GMV payment for TikTok Ads','settlement_amount','60.00'),
    jsonb_build_object('order_id','585386780484273402','transaction_type','Order','settlement_amount','45.10'),
    jsonb_build_object('order_id','585244041338652508','transaction_type','Order','settlement_amount','30.00'),
    jsonb_build_object('order_id','585244041338652508','transaction_type','Order','settlement_amount','12.75')
  ));

  -- ===== 1. THE IMPORT SUCCEEDS AT ALL =====
  select count(*) into v_n from public.tiktok_settlement_rows where batch_id = v_batch;
  if v_n <> 6 then raise exception 'FAIL 1: all 6 rows should stage, got %', v_n; end if;
  raise notice 'PASS 1: the import no longer fails — all 6 rows staged';

  -- ===== 2. AD ROWS ARE STORED AS finance =====
  select count(*) into v_n from public.tiktok_settlement_rows
   where batch_id = v_batch and txn_class = 'finance';
  if v_n <> 3 then raise exception 'FAIL 2: the 3 ad rows should be finance, got %', v_n; end if;
  raise notice 'PASS 2: the three ad payments are stored as platform finance rows';

  -- ===== 3. AND MATCH NO CUSTOMER ORDER =====
  select count(*) into v_n from public.tiktok_settlement_rows
   where batch_id = v_batch and txn_class = 'finance' and matched_order_id is not null;
  if v_n <> 0 then raise exception 'FAIL 3: a finance row must not be matched, got %', v_n; end if;
  raise notice 'PASS 3: no ad row is attached to a customer order';

  -- ===== 4. IDS ARE STORED DIGIT-PERFECT =====
  if not exists (select 1 from public.tiktok_settlement_rows
                  where batch_id = v_batch and order_id = '3679669423061370507') then
    raise exception 'FAIL 4: the 19-digit id should be stored exactly'; end if;
  raise notice 'PASS 4: 3679669423061370507 is stored exactly, no rounding';

  -- ===== 5. THE REPEATED ORDER KEEPS BOTH LINES =====
  select count(*) into v_n from public.tiktok_settlement_rows
   where batch_id = v_batch and order_id = '585244041338652508' and staging_status is distinct from 'Duplicate Row';
  if v_n <> 2 then raise exception 'FAIL 5: both settlement lines should survive, got %', v_n; end if;
  raise notice 'PASS 5: the order settled twice keeps both lines';

  -- ===== 6. ORDER ROWS STILL MATCH =====
  select count(*) into v_n from public.tiktok_settlement_rows
   where batch_id = v_batch and txn_class = 'order' and matched_order_id is not null;
  if v_n < 1 then raise exception 'FAIL 6: Order rows should match a confirmed order'; end if;
  raise notice 'PASS 6: Order rows match their confirmed TikTok orders';

  -- ===== 7. THE STAGED TOTAL INCLUDES THE AD ROWS =====
  -- report_tiktok_settlement() counts CONFIRMED rows only, and these are merely
  -- staged, so the staged figures are checked directly.
  declare v_tot numeric; v_fin numeric; begin
    select coalesce(sum(settlement_amount),0) into v_tot
      from public.tiktok_settlement_rows where batch_id = v_batch;
    if v_tot <> 347.85 then
      raise exception 'FAIL 7: staged total should be 347.85, got %', v_tot; end if;
    select coalesce(sum(settlement_amount),0) into v_fin
      from public.tiktok_settlement_rows where batch_id = v_batch and txn_class = 'finance';
    if v_fin <> 260 then
      raise exception 'FAIL 7: the ad rows should total 260, got %', v_fin; end if;
  end;
  raise notice 'PASS 7: the staged total is 347.85, of which 260 is platform finance';

  raise notice '=== FINANCE ROWS IMPORT CORRECTLY ===';
end $t$;
rollback;
