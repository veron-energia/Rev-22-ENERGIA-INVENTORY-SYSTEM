-- 499_product_page_price_sets_both_stores.sql
--
-- SAVING A PRODUCT SETS ITS PRICE AT EVERY STORE
-- (the user, 7 Nov 2026: asked whether saving a product on the Product page should set that
-- price at both stores, "Yes, make it set both stores automatically"; the Price List page
-- stays "One store only"; "Cost" becomes "Price" on the Product page)
--
-- (The number 499 is this file's name, its errors' prefix, its self-test's error code P0499,
-- its suite's and its UNDO's; if it changes at commit, change it in these places alone.)
--
-- WHAT WAS WRONG
--
--   The Product page's figure (products.default_cost_price, shown as Cost) works as the selling
--   price, but a sale reads store_product_prices, and saving a product never touched that. So
--   the two drifted: an Owner account raised five figures on the Product page on 27 Oct and the
--   Price List kept the old ones; many products had a price at one store or none. All of that
--   was set right by hand on 7 Nov (111 changes); nothing kept it right afterwards.
--
-- WHAT THIS DOES
--
--   save_product: when an Owner or Manager adds or saves a product, its price is set on the
--   Price List of every active store where it differs, through set_product_prices, the Price
--   List page's own function, so each change has that function's Audit Log entry. It is part of
--   the same save: all or nothing. The answer gains prices_set, how many stores changed, for the
--   page to say so. The price refusal now says "Price" where it said "Cost price".
--
-- WHAT THIS LEAVES ALONE
--
--   * A blank price (0): nothing is set, and prices already there stay, so nothing goes on sale
--     for nothing.
--   * A machine on the Special page with no sale price, which only rents, such as Toyota Van
--     Rental (the user, 7 Nov 2026: "Leave it off"). A price would let staff sell it as an item.
--     The Price List page can still price one by hand.
--   * A save by an Inventory Manager: they change product details, cost among them (the Owner,
--     9 Oct 2026), and only an Owner or Manager sets a selling price (set_product_prices).
--   * The Price List page: it still sets one store. That store keeps its price until the product
--     is next saved, even for a small edit, which sets every store back.
--   * Invoices already raised, which hold their own prices; restoring a deleted product ("prices
--     as they were"); the Special page's own prices; vouchers, promotions and therapy packages.
--
-- UNDO: scripts/products/undo-499.sql (refuses unless the function is 499's version; prices already
-- set stay set). A later migration changing this function must pin 499's AFTER md5 below.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- The function this patches: BEFORE (production now) and AFTER md5s
  c_sig constant text[] := array[
    'save_product(uuid,jsonb,uuid[],uuid[])'];
  c_before constant text[] := array[
    '905cdc6ded1a0f3cda513a1884ee238a'];
  c_after constant text[] := array[
    '151ad4be5fe4742573ef6ec1b2cbe78a'];
  -- Each patch: which function (its place in c_sig), the text found exactly once
  -- in it, and the text put in its place. The UNDO file swaps them back.
  c_fn constant int[] := array[1, 1, 1, 1];
  c_anchor constant text[] := array[
$a$-- product off is checked by the retire trigger.
declare$a$,
$a$  v_dup public.products%rowtype; v_id uuid; v text;$a$,
$a$      raise exception 'Cost price must be 0 or more, with at most 2 decimal places.'; end if;$a$,
$a$  return jsonb_build_object('success', true, 'product_id', v_id, 'created', p_id is null);$a$];
  c_new constant text[] := array[
$n$-- product off is checked by the retire trigger.
-- 499 (the user, 7 Nov 2026): default_cost_price, shown as Price, is the selling price. When an
-- Owner or Manager saves, it is set on the Price List of every active store where it differs.
-- Left alone: a blank price; a machine on the Special page that only rents. The answer's
-- prices_set says how many stores changed.
declare$n$,
$n$  v_dup public.products%rowtype; v_id uuid; v text; v_store uuid; v_prices int := 0;$n$,
$n$      raise exception 'Price must be 0 or more, with at most 2 decimal places.'; end if;$n$,
$n$  -- 499: the Price List page's own function, as the caller, with its Audit Log entry.
  if v_new.default_cost_price > 0 and public.is_owner_or_manager()
     and not exists (select 1 from public.special_products sp
                      where sp.product_id = v_id and sp.deleted_at is null and sp.sale_price = 0) then
    for v_store in
      select st.id from public.stores st
       where st.deleted_at is null and st.is_active
         and not exists (select 1 from public.store_product_prices s
                          where s.store_id = st.id and s.product_id = v_id and s.deleted_at is null
                            and s.selling_price = v_new.default_cost_price)
       order by st.id
    loop
      perform public.set_product_prices(v_store, v_id, v_new.default_cost_price, v_new.default_cost_price, 'available');
      v_prices := v_prices + 1;
    end loop;
  end if;
  return jsonb_build_object('success', true, 'product_id', v_id, 'created', p_id is null, 'prices_set', v_prices);$n$];

  -- Relied on, not changed (production now)
  c_relied constant text[] := array[
    'set_product_prices(uuid,uuid,numeric,numeric,text)',
    'is_owner_or_manager()'];
  c_relied_md5 constant text[] := array[
    'aef4792013bc3a56f8ee62bc1a7d686a',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8'];

  v_path text := current_setting('search_path');
  v_def text[] := array_fill(null::text, array[1]);
  v_make boolean[] := array_fill(false, array[1]);
  v_acl text[] := array_fill(null::text, array[1]);
  d text; i int;
  -- the self-test's made-up records
  t_sfx text; t_owner uuid; t_inv uuid; t_store uuid; t_prd uuid; t_rent uuid; t_stores int; t_got jsonb; t_msg text;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '499: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The function it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '499: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '499: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '499: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '499: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '499: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '499: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    -- compared as sets: production lists them in another order than a local copy
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '499: the grants of public.% changed', c_sig[i]; end if;
  end loop;

  -- 4. Self-test, in a block that is always undone
  -- Made-up records only ("499 Check", @example.invalid). It ends by raising P0499, which undoes
  -- all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    insert into auth.users (id, email) values (gen_random_uuid(), '499chk-owner-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '499 Check Owner', '499chk-owner-' || t_sfx || '@example.invalid', 'owner', true);
    insert into auth.users (id, email) values (gen_random_uuid(), '499chk-inv-' || t_sfx || '@example.invalid') returning id into t_inv;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_inv, '499 Check Inventory', '499chk-inv-' || t_sfx || '@example.invalid', 'inventory_manager', true);
    insert into public.stores (name, code, country_code) values ('499 Check ' || t_sfx, '499-' || t_sfx, 'SG') returning id into t_store;
    t_stores := (select count(*) from public.stores where deleted_at is null and is_active);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', t_owner, 'role', 'authenticated')::text, true);

    -- A new product with a price goes on every store's Price List.
    t_got := public.save_product(null, jsonb_build_object('name', '499 Check ' || t_sfx, 'sku', '499-P-' || t_sfx, 'default_cost_price', '12.50'));
    t_prd := (t_got->>'product_id')::uuid;
    if (t_got->>'prices_set')::int <> t_stores
       or (select count(*) from public.store_product_prices where product_id = t_prd and selling_price = 12.50 and deleted_at is null) <> t_stores then
      raise exception '499: a new product''s price did not reach every store: %', t_got; end if;
    -- The same price again changes nothing.
    t_got := public.save_product(t_prd, jsonb_build_object('description', '499 self-test'));
    if (t_got->>'prices_set')::int <> 0 then raise exception '499: a save with the same price changed prices: %', t_got; end if;
    -- A new price follows.
    t_got := public.save_product(t_prd, jsonb_build_object('default_cost_price', '20'));
    if (t_got->>'prices_set')::int <> t_stores
       or (select count(*) from public.store_product_prices where product_id = t_prd and selling_price = 20 and deleted_at is null) <> t_stores then
      raise exception '499: a new price did not reach every store: %', t_got; end if;
    -- One store set on its own on the Price List goes back at the next save, and only that one.
    perform public.set_product_prices(t_store, t_prd, 5, 5, 'available');
    t_got := public.save_product(t_prd, jsonb_build_object('description', '499 self-test again'));
    if (t_got->>'prices_set')::int <> 1
       or (select selling_price from public.store_product_prices where product_id = t_prd and store_id = t_store) <> 20 then
      raise exception '499: one store''s own price did not go back: %', t_got; end if;
    -- A blank price leaves the Price List alone.
    t_got := public.save_product(t_prd, jsonb_build_object('default_cost_price', '0'));
    if (t_got->>'prices_set')::int <> 0
       or (select selling_price from public.store_product_prices where product_id = t_prd and store_id = t_store) <> 20 then
      raise exception '499: a blank price changed the Price List: %', t_got; end if;
    -- A machine that only rents stays off.
    t_rent := (public.save_product(null, jsonb_build_object('name', '499 Check Rental ' || t_sfx, 'sku', '499-R-' || t_sfx))->>'product_id')::uuid;
    insert into public.special_products (name, sku, sale_price, rate_day, product_id)
    values ('499 Check Rental ' || t_sfx, '499-R-' || t_sfx, 0, 100, t_rent);
    t_got := public.save_product(t_rent, jsonb_build_object('default_cost_price', '100'));
    if (t_got->>'prices_set')::int <> 0 or exists (select 1 from public.store_product_prices where product_id = t_rent) then
      raise exception '499: a machine that only rents went on the Price List: %', t_got; end if;
    -- The price refusal says Price.
    t_msg := null;
    begin perform public.save_product(t_prd, jsonb_build_object('default_cost_price', '1.234'));
    exception when others then t_msg := sqlerrm; end;
    if t_msg is distinct from 'Price must be 0 or more, with at most 2 decimal places.' then
      raise exception '499: the price refusal said: %', coalesce(t_msg, 'nothing'); end if;
    -- An Inventory Manager saves the product; the selling price stays.
    perform set_config('request.jwt.claim.sub', t_inv::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', t_inv, 'role', 'authenticated')::text, true);
    t_got := public.save_product(t_prd, jsonb_build_object('default_cost_price', '30'));
    if (t_got->>'prices_set')::int <> 0
       or (select default_cost_price from public.products where id = t_prd) <> 30
       or (select selling_price from public.store_product_prices where product_id = t_prd and store_id = t_store) <> 20 then
      raise exception '499: an Inventory Manager''s save changed a selling price: %', t_got; end if;

    raise exception using errcode = 'P0499', message = '499: self-test done, undone';
  exception when sqlstate 'P0499' then null;
  end;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
