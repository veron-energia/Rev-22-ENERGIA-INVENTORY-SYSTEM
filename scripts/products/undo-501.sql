-- UNDO of 501 (with the user's go-ahead; the suite runs it). It puts save_product back to 499's
-- text: a save still sets the Price List, and no longer the Special page's sale price. It refuses
-- unless the function is exactly 501's version, so a later version is never overwritten. Sale
-- prices already set stay set. The page's words stay as they are until the page is put back too.
-- Undo 501 before 499. One transaction, all or nothing.
do $undo$
declare
  c_sig constant text[] := array[
    'save_product(uuid,jsonb,uuid[],uuid[])'];
  c_before constant text[] := array[
    '151ad4be5fe4742573ef6ec1b2cbe78a'];
  c_after constant text[] := array[
    '2b16ba59e2024b024317a642fa50b62b'];
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


  v_path text := current_setting('search_path');
  v_def text[] := array_fill(null::text, array[1]);
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  for i in 1 .. cardinality(c_sig) loop
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) <> c_after[i] then
      raise exception 'UNDO 501: public.% is not 501''s version (md5 %); nothing changed', c_sig[i], md5(d); end if;
    v_def[i] := d;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'UNDO 501: patch % is not found exactly once in public.%', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_before[i] then
      raise exception 'UNDO 501: the text worked back for public.% is not the BEFORE one (md5 %)', c_sig[i], md5(v_def[i]); end if;
    execute v_def[i];
  end loop;
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
