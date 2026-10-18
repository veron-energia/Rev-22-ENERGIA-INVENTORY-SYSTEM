-- 424: a promotion's Original, what a bundle line sold, one code per live
-- promotion, and a price at every store that keeps each store's on/off.
--
--   * promotion_original_total counts each choice group at its base option
--     (the cheapest, or the dearest when a products group says so; as at the
--     till, any other group counts its cheapest whatever it says), choose_qty
--     times, priced like the fixed items: products and therapy at the store's
--     price, vouchers at their price, a promotion at its own Original. An
--     option with no price at the store is left out (SALES-EXTRAS-13).
--   * bundle_line_components reads what the sale recorded (the stock
--     snapshot), so a bundle edited after the sale still shows what was sold;
--     a sale from before the snapshot follows the bundle as it is now, with
--     the choices made at the till (SALES-EXTRAS-13).
--   * Two live promotions never share a code, ignoring case and surrounding
--     spaces; a deleted promotion does not count (SALES-EXTRAS-11).
--   * A price set at every store with "available" sent as null keeps each
--     store's on/off choice, and a store with no price yet starts on; true or
--     false is set as given; left out, it is true as before (the Prices window
--     always gives it); only an Owner or Manager may set it (SALES-EXTRAS-10).
-- Fixtures only (made-up names, @sig.invalid emails).
-- Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;
do $$
declare
  own uuid := gen_random_uuid(); stf uuid := gen_random_uuid();
  st uuid; st2 uuid; cust uuid; pm uuid;
  pa uuid; pb uuid; pc uuid; pd uuid; pe uuid; v1 uuid; v2 uuid; t1 uuid; t2 uuid;
  pr uuid; ch1 uuid; ch2 uuid; g uuid; gp uuid; gv uuid; bun uuid; bg uuid; p1 uuid; p2 uuid;
  inv uuid; inv2 uuid; li uuid; li2 uuid; n numeric; v text;
begin
  insert into auth.users(id, email) values (own, 'xpo-own@sig.invalid'), (stf, 'xpo-s@sig.invalid');
  insert into profiles(id, full_name, email, role) values
    (own, 'XPO Owner', 'xpo-own@sig.invalid', 'owner'), (stf, 'XPO Staff', 'xpo-s@sig.invalid', 'staff');
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name, code, country_code) values ('XPO Store', 'XPOS', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('XPO Other', 'XPOO', 'SG') returning id into st2;
  insert into user_store_assignments(user_id, store_id) values (stf, st);
  insert into customers(full_name, phone) values ('XPO Buyer', '+61491579455') returning id into cust;
  insert into payment_methods(name, is_active) values ('XPO Cash', true) returning id into pm;
  insert into products(name, sku, product_type) values ('XPO A', 'XPOA', 'own') returning id into pa;
  insert into products(name, sku, product_type) values ('XPO B', 'XPOB', 'own') returning id into pb;
  insert into products(name, sku, product_type) values ('XPO C', 'XPOC', 'own') returning id into pc;
  insert into products(name, sku, product_type) values ('XPO D', 'XPOD', 'own') returning id into pd;
  insert into products(name, sku, product_type) values ('XPO E', 'XPOE', 'own') returning id into pe;   -- no price anywhere
  insert into store_inventory(store_id, product_id, current_qty)
    select st, p, 50 from unnest(array[pa, pb, pc, pd, pe]) p;
  perform set_product_prices(st, pa, 100, 100, 'available');
  perform set_product_prices(st, pb, 30, 30, 'available');
  perform set_product_prices(st, pc, 50, 50, 'available');
  perform set_product_prices(st, pd, 40, 40, 'available');
  insert into vouchers(name, code, selling_price) values ('XPO V20', 'XPOV20', 20) returning id into v1;
  insert into vouchers(name, code, selling_price) values ('XPO V35', 'XPOV35', 35) returning id into v2;
  insert into unlimited_therapy_packages(name, duration_months) values ('XPO Therapy 300', 3) returning id into t1;
  insert into unlimited_therapy_packages(name, duration_months) values ('XPO Therapy unpriced', 3) returning id into t2;
  insert into unlimited_therapy_store_prices(store_id, package_id, selling_price, available_at_store)
    values (st, t1, 300, true);

  -- ════ 1. The Original counts each choice group at its base option ══════════
  insert into promotions(name, code, fixed_price) values ('XPO Child D', 'XPOCD', 35) returning id into ch1;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (ch1, 'product', pd, 1);   -- 40
  insert into promotions(name, code, fixed_price) values ('XPO Child A', 'XPOCA', 90) returning id into ch2;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (ch2, 'product', pa, 1);   -- 100
  insert into promotions(name, code, fixed_price) values ('XPO Bundle', 'XPOB1', 400) returning id into pr;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (pr, 'product', pa, 1);    -- 100
  if promotion_original_total(pr, st) <> 100 then
    raise exception 'FAIL 1: fixed items alone are %, not 100', promotion_original_total(pr, st); end if;
  -- choose 2 products: B 30, C 50, E (no price here, left out)
  insert into promotion_choice_groups(promotion_id, label, item_kind, choose_qty, base_mode)
    values (pr, 'Two products', 'product', 2, 'cheapest') returning id into g;
  insert into promotion_choice_options(group_id, product_id) values (g, pb), (g, pc), (g, pe);
  -- one voucher (20 or 35), one therapy (300, or one with no price here), one promotion (40 or 100)
  insert into promotion_choice_groups(promotion_id, label, item_kind, choose_qty) values (pr, 'A voucher', 'voucher', 1) returning id into gv;
  insert into promotion_choice_options(group_id, voucher_id) values (gv, v1), (gv, v2);
  insert into promotion_choice_groups(promotion_id, label, item_kind, choose_qty) values (pr, 'A therapy', 'therapy', 1) returning id into gp;
  insert into promotion_choice_options(group_id, therapy_package_id) values (gp, t1), (gp, t2);
  insert into promotion_choice_groups(promotion_id, label, item_kind, choose_qty) values (pr, 'A prize', 'promotion', 1) returning id into gp;
  insert into promotion_choice_options(group_id, child_promotion_id) values (gp, ch1), (gp, ch2);
  -- and a group whose only option has no price here counts nothing
  insert into promotion_choice_groups(promotion_id, label, item_kind, choose_qty) values (pr, 'Unpriced', 'product', 1) returning id into gp;
  insert into promotion_choice_options(group_id, product_id) values (gp, pe);
  -- 100 + 2 x 30 + 20 + 300 + 40 + 0
  n := promotion_original_total(pr, st);
  if n <> 520 then raise exception 'FAIL 1: the Original with the cheapest base options is %, not 520', n; end if;
  -- the products group set to its dearest option: 2 x 50 instead of 2 x 30
  update promotion_choice_groups set base_mode = 'highest' where id = g;
  n := promotion_original_total(pr, st);
  if n <> 560 then raise exception 'FAIL 1: the Original with the dearest products is %, not 560', n; end if;
  -- the dearest setting counts for products groups only, as at the till
  -- (promotion_selections_topup): a vouchers group set to its dearest still
  -- counts its cheapest voucher, 20 and not 35
  update promotion_choice_groups set base_mode = 'highest' where id = gv;
  n := promotion_original_total(pr, st);
  if n <> 560 then raise exception 'FAIL 1: a vouchers group set to its dearest made the Original %, not 560', n; end if;
  update promotion_choice_groups set base_mode = 'cheapest' where id = gv;
  -- elsewhere only the voucher (priced everywhere) counts
  n := promotion_original_total(pr, st2);
  if n <> 20 then raise exception 'FAIL 1: at a store with no prices the Original is %, not the 20 voucher', n; end if;
  -- a promotion with only fixed items is unchanged
  if promotion_original_total(ch1, st) <> 40 then
    raise exception 'FAIL 1: a bundle with no choice groups changed its Original'; end if;

  -- ════ 2. A bundle line keeps what it sold ══════════════════════════════════
  insert into promotions(name, code, fixed_price) values ('XPO Pick', 'XPOPK', 120) returning id into bun;
  insert into promotion_items(promotion_id, item_type, product_id, quantity) values (bun, 'product', pa, 1);
  insert into promotion_choice_groups(promotion_id, label, item_kind, choose_qty) values (bun, 'Pick one', 'product', 1) returning id into bg;
  insert into promotion_choice_options(group_id, product_id) values (bg, pb), (bg, pc);
  perform set_promotion_prices(bun, st, 120, 120, true);
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', bun, 'quantity', 1,
           'selections', jsonb_build_array(jsonb_build_object('group_id', bg, 'options',
             jsonb_build_array(jsonb_build_object('product_id', pc, 'quantity', 1)))))), 0, null, null, null);
  inv2 := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind', 'promotion', 'promotion_id', bun, 'quantity', 1,
           'selections', jsonb_build_array(jsonb_build_object('group_id', bg, 'options',
             jsonb_build_array(jsonb_build_object('product_id', pb, 'quantity', 1)))))), 0, null, null, null);
  select id into li from invoice_items where invoice_id = inv and line_kind = 'promotion';
  select id into li2 from invoice_items where invoice_id = inv2 and line_kind = 'promotion';
  -- the second sale is from before the stock snapshot
  update invoices set stock_snapshot_version = null where id = inv2;
  if (select string_agg(b.product_id::text || 'x' || b.quantity, ',' order by b.product_id) from bundle_line_components(li) b)
     is distinct from (select string_agg(x || 'x1', ',' order by x) from unnest(array[pa::text, pc::text]) x) then
    raise exception 'FAIL 2: the sale does not hold A and its chosen C'; end if;
  -- the bundle is edited: A becomes D
  update promotion_items set product_id = pd where promotion_id = bun;
  if (select string_agg(b.product_id::text || 'x' || b.quantity, ',' order by b.product_id) from bundle_line_components(li) b)
     is distinct from (select string_agg(x || 'x1', ',' order by x) from unnest(array[pa::text, pc::text]) x) then
    raise exception 'FAIL 2: after the bundle was edited the sale no longer holds what it sold: %',
      (select string_agg(b.product_id::text || 'x' || b.quantity, ',') from bundle_line_components(li) b); end if;
  -- the sale from before the snapshot follows the bundle as it is now, with its choice
  if (select string_agg(b.product_id::text || 'x' || b.quantity, ',' order by b.product_id) from bundle_line_components(li2) b)
     is distinct from (select string_agg(x || 'x1', ',' order by x) from unnest(array[pd::text, pb::text]) x) then
    raise exception 'FAIL 2: a sale from before the snapshot does not follow the bundle as it is now'; end if;

  -- ════ 3. One code per live promotion ═══════════════════════════════════════
  insert into promotions(name, code) values ('XPO Code One', 'XPO-CODE') returning id into p1;
  begin
    insert into promotions(name, code) values ('XPO Code Two', '  xpo-code ');
    raise exception 'FAIL 3: two live promotions share a code (case and spaces aside)';
  exception when unique_violation then null;
  end;
  update promotions set deleted_at = now(), is_active = false where id = p1;
  insert into promotions(name, code) values ('XPO Code Two', '  xpo-code ') returning id into p2;
  begin
    update promotions set deleted_at = null where id = p1;
    raise exception 'FAIL 3: a deleted promotion came back with a code already in use';
  exception when unique_violation then null;
  end;
  insert into promotions(name, code, deleted_at) values ('XPO Code Three', 'XPO-CODE', now());   -- deleted ones may repeat

  -- ════ 4. One price at every store keeps each store's on/off ═════════════════
  perform set_promotion_prices(pr, st, 100, 100, false);       -- switched off here
  perform set_config('request.jwt.claims', json_build_object('sub', own, 'role', 'authenticated')::text, true);
  perform set_promotion_price_all_stores(pr, 120, null);
  if (select string_agg(s.code || ':' || sp.selling_price::numeric::text || ':' || sp.available_at_store::text, ',' order by s.code)
        from promotion_store_prices sp join stores s on s.id = sp.store_id
       where sp.promotion_id = pr and s.id in (st, st2)) is distinct from 'XPOO:120.00:true,XPOS:120.00:false' then
    raise exception 'FAIL 4: one price everywhere with "available" null gave %',
      (select string_agg(s.code || ':' || sp.selling_price::text || ':' || sp.available_at_store::text, ',' order by s.code)
         from promotion_store_prices sp join stores s on s.id = sp.store_id where sp.promotion_id = pr and s.id in (st, st2)); end if;
  perform set_promotion_price_all_stores(pr, 125, true);
  if exists (select 1 from promotion_store_prices where promotion_id = pr and store_id in (st, st2)
              and (not available_at_store or selling_price <> 125)) then
    raise exception 'FAIL 4: one price everywhere with "available" true did not switch every store on'; end if;
  perform set_promotion_price_all_stores(pr, 125, false);
  if exists (select 1 from promotion_store_prices where promotion_id = pr and store_id in (st, st2) and available_at_store) then
    raise exception 'FAIL 4: one price everywhere with "available" false left a store on'; end if;
  perform set_promotion_prices(pr, st, 130, 130, null);
  if (select available_at_store from promotion_store_prices where promotion_id = pr and store_id = st) then
    raise exception 'FAIL 4: one store''s price with "available" null switched it on'; end if;
  -- "available" left out is true, as before 424 (its default is unchanged).
  perform set_promotion_price_all_stores(pr, 135);
  if exists (select 1 from promotion_store_prices where promotion_id = pr and store_id in (st, st2)
              and (not available_at_store or selling_price <> 135)) then
    raise exception 'FAIL 4: one price everywhere with "available" left out did not switch every store on'; end if;
  perform set_promotion_prices(pr, st, 140, 140, false);
  perform set_promotion_prices(pr, st, 145);
  if not (select available_at_store from promotion_store_prices where promotion_id = pr and store_id = st) then
    raise exception 'FAIL 4: one store''s price with "available" left out did not switch it on'; end if;
  -- only an Owner or Manager
  perform set_config('request.jwt.claims', json_build_object('sub', stf, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', stf::text, true);
  begin
    perform set_promotion_price_all_stores(pr, 1, null);
    raise exception 'FAIL 4: staff set a promotion price at every store';
  exception when others then
    if sqlerrm not like 'Only an Owner or Manager can edit promotion prices%' then raise; end if;
  end;

  raise notice 'PASS: the Original counts each choice group at its base option (products, vouchers, therapy and promotions; unpriced options left out; cheapest, or dearest for a products group only); a sale keeps what it sold after its bundle is edited, and a sale from before the snapshot follows the bundle; two live promotions never share a code; one price at every store keeps each store''s on/off when "available" is null (left out, it is true as before), and is the Owner''s or a Manager''s alone';
end $$;
rollback;
