-- An exchange counts each returned line once (506).
--
-- The old 'product' kind of create_exchange_with_details credited a purchased
-- line once for each time it was listed. This pays an invoice and sends an
-- exchange that lists its one line twice (also with the id in capitals); it
-- must be refused. The same request with the line listed once goes through:
-- one returned row, the line marked exchanged, its one unit back on the shelf.
--
--   sh scripts/invoices/local-sql.sh -f scripts/exchanges/tests/returned-line-once-506.sql
-- 506 is installed here when it is not in yet. Disposable local database only;
-- everything is rolled back. Made-up records only (X506, @example.invalid, the fictional +6149157xxxx).
\set ON_ERROR_STOP on
begin;
select position('506:' in pg_get_functiondef('public.create_product_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text,boolean,uuid,text)'::regprocedure)) > 0 as m506_in \gset
\if :m506_in
\else
\ir ../../../supabase/506_an_exchange_counts_each_returned_line_once.sql
\endif
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;

do $$
declare own uuid := gen_random_uuid(); st uuid; cust uuid; prod uuid; inv uuid; line uuid; pm uuid; v_msg text; v_pay jsonb; v_res jsonb; v_ex uuid;
begin
  insert into auth.users(id, email, email_confirmed_at) values (own, 'x506-owner@example.invalid', now());
  insert into public.profiles(id, full_name, email, role, is_active) values (own, 'X506 Owner', 'x506-owner@example.invalid', 'owner', true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  insert into public.stores(name, code, country_code) values ('X506 Store', 'X506', 'SG') returning id into st;
  insert into public.customers(full_name, phone) values ('X506 Customer', '+61491578506') returning id into cust;
  insert into public.products(name, sku) values ('X506 Item', 'X506-1') returning id into prod;
  insert into public.store_inventory(store_id, product_id, current_qty) values (st, prod, 10);
  perform public.set_product_prices(st, prod, 50, 50, 'available');
  select id into pm from public.payment_methods
   where is_active and deleted_at is null and not coalesce(is_wallet_credit, false) order by name limit 1;
  if pm is null then insert into public.payment_methods(name) values ('X506 Cash') returning id into pm; end if;
  inv := public.create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind','product','product_id',prod,'quantity',1)));
  perform public.record_invoice_settlement(inv, jsonb_build_object('receipts', jsonb_build_array(
    jsonb_build_object('key','r1','payment_method_id',pm,'amount',(select total_amount from public.invoices where id = inv)))), gen_random_uuid());
  select id into line from public.invoice_items where invoice_id = inv;
  perform pg_temp.check(public.exchange_ineligibility_reason(inv) = '', 'the fixture''s paid invoice may be exchanged');

  -- 1. the same line twice: refused
  v_pay := jsonb_build_object('original_invoice_id', inv, 'processing_store_id', st, 'reason', 'X506 check', 'served_by', jsonb_build_array(own::text),
    'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', line), jsonb_build_object('invoice_item_id', line)),
    'replacement', jsonb_build_array(jsonb_build_object('product_id', prod, 'quantity', 2)));
  begin
    perform public.create_exchange_with_details('product', v_pay);
    v_msg := 'accepted';
  exception when others then v_msg := sqlerrm; end;
  perform pg_temp.check(v_msg = 'The same purchased item is listed more than once in this exchange.',
    '1 a returned line listed twice is refused: ' || v_msg);
  perform pg_temp.check((select exchanged_at is null from public.invoice_items where id = line)
    and (select current_qty from public.store_inventory where store_id = st and product_id = prod) = 9,
    '1 nothing was exchanged and no stock moved');

  -- 1b. the same line twice, once with its id in capitals: still the same line
  v_pay := jsonb_set(v_pay, '{returned}', jsonb_build_array(jsonb_build_object('invoice_item_id', line),
    jsonb_build_object('invoice_item_id', upper(line::text))));
  begin
    perform public.create_exchange_with_details('product', v_pay);
    v_msg := 'accepted';
  exception when others then v_msg := sqlerrm; end;
  perform pg_temp.check(v_msg = 'The same purchased item is listed more than once in this exchange.',
    '1b the same line with its id in capitals is refused too: ' || v_msg);

  -- 1c. a missing id keeps the loop's own message
  v_pay := jsonb_set(v_pay, '{returned}', jsonb_build_array(jsonb_build_object('quantity', 1)));
  begin
    perform public.create_exchange_with_details('product', v_pay);
    v_msg := 'accepted';
  exception when others then v_msg := sqlerrm; end;
  perform pg_temp.check(v_msg = 'A returned item is not part of the original invoice',
    '1c a returned entry with no id is refused by the loop as before: ' || v_msg);

  -- 2. the same line once: an ordinary exchange goes through
  v_pay := jsonb_set(v_pay, '{returned}', jsonb_build_array(jsonb_build_object('invoice_item_id', line)));
  v_pay := jsonb_set(v_pay, '{replacement}', jsonb_build_array(jsonb_build_object('product_id', prod, 'quantity', 1)));
  v_res := public.create_exchange_with_details('product', v_pay);
  v_ex := coalesce(nullif(v_res->>'exchange_id','')::uuid, nullif(v_res->>'id','')::uuid);
  perform pg_temp.check(v_ex is not null, '2 the line listed once is exchanged: ' || v_res::text);
  perform pg_temp.check((select count(*) from public.product_exchange_items where exchange_id = v_ex and direction = 'returned') = 1
    and (select exchange_id = v_ex and exchanged_at is not null from public.invoice_items where id = line),
    '2 one returned row, and the purchased line is marked exchanged');
  perform pg_temp.check((select current_qty from public.store_inventory where store_id = st and product_id = prod) = 9,
    '2 one unit back and one unit out: the shelf is where it was (9)');
end $$;
rollback;
