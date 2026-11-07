-- 501_product_page_price_sets_special_sale_price.sql
--
-- SAVING A PRODUCT ALSO SETS ITS SALE PRICE ON THE SPECIAL PAGE
-- (the user, 7 Nov 2026: asked whether saving a product should update its Special page sale price
-- as well, "Yes, update the Special page sale price too")
--
-- (The number 501 is this file's name, its errors' prefix, its self-test's error code P0501,
-- its suite's and its UNDO's; if it changes at commit, change it in these places alone.)
--
-- WHAT WAS WRONG
--
--   Since 499 saving a product sets its price at every store, but a Special Product line on an
--   invoice takes special_products.sale_price, which saving never touched. Consignment products are
--   sold that way, so a price changed on the Product page did not reach their sales.
--
-- WHAT THIS DOES
--
--   save_product: when an Owner or Manager saves a product with a price, and it has an entry on the
--   Special page, the entry's sale price is set to that price where it differs. It is part of the
--   same save: all or nothing. An Audit Log entry (special_product_sale_price) says what it was and
--   what it is now. The answer gains special_price_set, for the page to say so.
--
-- WHAT THIS LEAVES ALONE
--
--   * A blank price; a save by an Inventory Manager; a machine on the Special page with no sale price,
--     which only rents, such as Toyota Van Rental: as 499, and its sale price stays 0.
--   * The Special page: its form still sets the sale price alone. That price lasts until the product
--     is next saved, even for a small edit, as the Price List page's does (the user's "One store only").
--   * The entry's rental rates, late fee, name, SKU, description and tabs.
--   * Invoices already raised and their sales, which hold their own prices.
--
-- UNDO: scripts/products/undo-501.sql (refuses unless the function is 501's version; prices already
-- set stay set). Undo 501 before 499. A later migration changing this function must pin 501's AFTER
-- md5 below.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- The function this patches: BEFORE (production now) and AFTER md5s
  c_sig constant text[] := array[
    'save_product(uuid,jsonb,uuid[],uuid[])'];
  c_before constant text[] := array[
    '151ad4be5fe4742573ef6ec1b2cbe78a'];
  c_after constant text[] := array[
    '2b16ba59e2024b024317a642fa50b62b'];
  -- Each patch: which function (its place in c_sig), the text found exactly once
  -- in it, and the text put in its place. The UNDO file swaps them back.
  c_fn constant int[] := array[1, 1, 1];
  c_anchor constant text[] := array[
$a$-- prices_set says how many stores changed.
declare$a$,
$a$v_store uuid; v_prices int := 0;$a$,
$a$      v_prices := v_prices + 1;
    end loop;
  end if;
  return jsonb_build_object('success', true, 'product_id', v_id, 'created', p_id is null, 'prices_set', v_prices);$a$];
  c_new constant text[] := array[
$n$-- prices_set says how many stores changed.
-- 501 (the user, 7 Nov 2026): its sale price on the Special page follows too, with an Audit Log
-- entry saying what it was; special_price_set says whether it changed.
declare$n$,
$n$v_store uuid; v_prices int := 0; v_sp record; v_special int := 0;$n$,
$n$      v_prices := v_prices + 1;
    end loop;
    -- 501: the check above has left out a machine that only rents.
    for v_sp in select sp.id, sp.name, sp.sku, sp.sale_price from public.special_products sp
                 where sp.product_id = v_id and sp.deleted_at is null and sp.sale_price <> v_new.default_cost_price
    loop
      update public.special_products set sale_price = v_new.default_cost_price where id = v_sp.id;
      perform public.write_audit_ex('special_products', v_sp.id, 'special_product_sale_price',
        jsonb_build_object('sale_price', v_sp.sale_price),
        jsonb_build_object('sale_price', v_new.default_cost_price, 'product', v_sp.name, 'sku', v_sp.sku), 'catalogue', null, null);
      v_special := v_special + 1;
    end loop;
  end if;
  return jsonb_build_object('success', true, 'product_id', v_id, 'created', p_id is null, 'prices_set', v_prices, 'special_price_set', v_special);$n$];

  -- Relied on, not changed (production now)
  c_relied constant text[] := array[
    'set_product_prices(uuid,uuid,numeric,numeric,text)',
    'is_owner_or_manager()',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)'];
  c_relied_md5 constant text[] := array[
    'aef4792013bc3a56f8ee62bc1a7d686a',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    'c705c733e213a27f0dc32d54322cc855'];

  v_path text := current_setting('search_path');
  v_def text[] := array_fill(null::text, array[1]);
  v_make boolean[] := array_fill(false, array[1]);
  v_acl text[] := array_fill(null::text, array[1]);
  d text; i int;
  -- the self-test's made-up records
  t_sfx text; t_owner uuid; t_inv uuid; t_store uuid; t_prd uuid; t_sp uuid; t_rent uuid; t_rent_sp uuid; t_got jsonb;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '501: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The function it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '501: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '501: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '501: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '501: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '501: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '501: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    -- compared as sets: production lists them in another order than a local copy
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '501: the grants of public.% changed', c_sig[i]; end if;
  end loop;

  -- 4. Self-test, in a block that is always undone
  -- Made-up records only ("501 Check", @example.invalid). It ends by raising P0501, which undoes
  -- all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    insert into auth.users (id, email) values (gen_random_uuid(), '501chk-owner-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '501 Check Owner', '501chk-owner-' || t_sfx || '@example.invalid', 'owner', true);
    insert into auth.users (id, email) values (gen_random_uuid(), '501chk-inv-' || t_sfx || '@example.invalid') returning id into t_inv;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_inv, '501 Check Inventory', '501chk-inv-' || t_sfx || '@example.invalid', 'inventory_manager', true);
    insert into public.stores (name, code, country_code) values ('501 Check ' || t_sfx, '501-' || t_sfx, 'SG') returning id into t_store;
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', t_owner, 'role', 'authenticated')::text, true);

    t_prd := (public.save_product(null, jsonb_build_object('name', '501 Check ' || t_sfx, 'sku', '501-P-' || t_sfx, 'default_cost_price', '10'))->>'product_id')::uuid;
    t_sp := public.upsert_special_product_from_product(null, t_prd, 10, 0, 0, 7, 0, 0);
    -- A new price follows, with the Audit Log's old and new price; the rest of the entry stays.
    t_got := public.save_product(t_prd, jsonb_build_object('default_cost_price', '20'));
    if (t_got->>'special_price_set')::int <> 1
       or (select sale_price from public.special_products where id = t_sp) <> 20
       or (select rate_month from public.special_products where id = t_sp) <> 7 then
      raise exception '501: a new price did not reach the Special page: %', t_got; end if;
    if (select count(*) from public.audit_logs where table_name = 'special_products' and record_id = t_sp and action = 'special_product_sale_price'
         and (old_data->>'sale_price')::numeric = 10 and (new_data->>'sale_price')::numeric = 20) <> 1 then
      raise exception '501: the Audit Log does not say what the sale price was'; end if;
    -- The same price again changes nothing.
    t_got := public.save_product(t_prd, jsonb_build_object('description', '501 self-test'));
    if (t_got->>'special_price_set')::int <> 0 then raise exception '501: a save with the same price changed it: %', t_got; end if;
    -- A price set on the Special page goes back at the next save.
    perform public.upsert_special_product_from_product(t_sp, t_prd, 15);
    t_got := public.save_product(t_prd, jsonb_build_object('description', '501 self-test again'));
    if (t_got->>'special_price_set')::int <> 1 or (select sale_price from public.special_products where id = t_sp) <> 20 then
      raise exception '501: a price set on the Special page did not go back: %', t_got; end if;
    -- A blank price leaves it alone.
    t_got := public.save_product(t_prd, jsonb_build_object('default_cost_price', '0'));
    if (t_got->>'special_price_set')::int <> 0 or (select sale_price from public.special_products where id = t_sp) <> 20 then
      raise exception '501: a blank price changed the Special page: %', t_got; end if;
    -- A machine that only rents keeps no sale price.
    t_rent := (public.save_product(null, jsonb_build_object('name', '501 Check Rental ' || t_sfx, 'sku', '501-R-' || t_sfx))->>'product_id')::uuid;
    t_rent_sp := public.upsert_special_product_from_product(null, t_rent, 0, 100);
    t_got := public.save_product(t_rent, jsonb_build_object('default_cost_price', '100'));
    if (t_got->>'special_price_set')::int <> 0 or (select sale_price from public.special_products where id = t_rent_sp) <> 0 then
      raise exception '501: a machine that only rents was given a sale price: %', t_got; end if;
    -- An Inventory Manager saves the product; the sale price stays.
    perform set_config('request.jwt.claim.sub', t_inv::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', t_inv, 'role', 'authenticated')::text, true);
    t_got := public.save_product(t_prd, jsonb_build_object('default_cost_price', '30'));
    if (t_got->>'special_price_set')::int <> 0 or (select sale_price from public.special_products where id = t_sp) <> 20 then
      raise exception '501: an Inventory Manager''s save changed a sale price: %', t_got; end if;

    raise exception using errcode = 'P0501', message = '501: self-test done, undone';
  exception when sqlstate 'P0501' then null;
  end;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
