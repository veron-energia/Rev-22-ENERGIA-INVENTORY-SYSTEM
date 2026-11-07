-- UNDO of 499 (with the user's go-ahead; the suite runs it). It puts save_product back to its
-- BEFORE text, so a save no longer sets the Price List. It refuses unless the function is exactly
-- 499's version, so a later version is never overwritten. Prices already set stay set. The page's
-- words stay as they are until the page is put back too. One transaction, all or nothing.
do $undo$
declare
  c_sig constant text[] := array[
    'save_product(uuid,jsonb,uuid[],uuid[])'];
  c_before constant text[] := array[
    '905cdc6ded1a0f3cda513a1884ee238a'];
  c_after constant text[] := array[
    '151ad4be5fe4742573ef6ec1b2cbe78a'];
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


  v_path text := current_setting('search_path');
  v_def text[] := array_fill(null::text, array[1]);
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  for i in 1 .. cardinality(c_sig) loop
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) <> c_after[i] then
      raise exception 'UNDO 499: public.% is not 499''s version (md5 %); nothing changed', c_sig[i], md5(d); end if;
    v_def[i] := d;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'UNDO 499: patch % is not found exactly once in public.%', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_before[i] then
      raise exception 'UNDO 499: the text worked back for public.% is not the BEFORE one (md5 %)', c_sig[i], md5(v_def[i]); end if;
    execute v_def[i];
  end loop;
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
