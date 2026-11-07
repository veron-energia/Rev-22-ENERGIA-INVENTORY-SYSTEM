-- UNDO of 500 (with the user's go-ahead; the suite runs it). It puts the two patched
-- functions back to their BEFORE texts. It refuses unless each function is exactly 500's
-- version, so a later version is never overwritten. Sales that already followed stay as they
-- are. Undo 500 before 498. One transaction, all or nothing.
do $undo$
declare
  c_sig constant text[] := array[
    'invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)',
    'preview_invoice_correction(uuid,jsonb)'];
  c_before constant text[] := array[
    '3cf6cfd8a22e5776e7b77e8d5ff3753d',
    '13b0925c29bd8ca14d8d8b7bd961fef8'];
  c_after constant text[] := array[
    '933ef75eaa654cbcef7ad8671c63d812',
    '23c180873b6545bd83fb20d21708aa9e'];
  c_fn constant int[] := array[1, 1, 1, 2];
  c_anchor constant text[] := array[
$a$--   * 498 (the user, 7 Nov 2026): a sale still waiting takes the invoice's customer and
--     store whenever they differ, whichever line it is on. A released one keeps them:
--     the machine went to that customer from there.
--   * A cancelled or refunded invoice, and a rental's line, are left as they are.
-- Internal. Answers [{sale_no, state, what}], state: waiting_off, back, stays, raised, moved.$a$,
$a$  -- 498: a sale still waiting follows the invoice's customer and store.
  for r in select s.id, s.sale_no, s.special_product_id, s.customer_id, s.store_id
             from public.special_sales s
            where s.invoice_id = p_invoice_id and s.status <> 'cancelled'
              and s.warehouse_id is null and s.source_store_id is null and s.supplier_id is null
              and (s.customer_id, s.store_id) is distinct from (v_inv.customer_id, v_inv.store_id)$a$,
$a$      'what', r.sale_no || ': ' || public.special_product_name(r.special_product_id) || ' moves to '
        || concat_ws(' and ',
             case when v_inv.customer_id is distinct from r.customer_id
                  then coalesce((select c.full_name from public.customers c where c.id = v_inv.customer_id), 'the invoice''s customer') end,
             case when v_inv.store_id is distinct from r.store_id
                  then coalesce((select t.name from public.stores t where t.id = v_inv.store_id), 'the invoice''s store') end)));
  end loop;
  return v_list;$a$,
$a$    elsif coalesce(p_header->>'benefit_action','') = '' then
      v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(
        'area','benefits',$a$];
  c_new constant text[] := array[
$n$--   * 498, 500 (the user, 7 Nov 2026): every sale not cancelled takes the invoice's customer
--     and store whenever they differ, whichever line it is on: waiting, released or sent by a
--     supplier. Where it left from stays, and no stock moves.
--   * 500: and its line's price, on a line still holding the same machine: the price before any
--     discount, as it was raised and as a rental's fee. No money and no stock moves: the invoice
--     stays the record of what is owed.
--   * A cancelled or refunded invoice, and a rental's line, are left as they are.
-- Internal. Answers [{sale_no, state, what}], state: waiting_off, back, stays, raised, moved, repriced.$n$,
$n$  -- 498, 500: every sale not cancelled follows the invoice's customer and store.
  for r in select s.id, s.sale_no, s.special_product_id, s.customer_id, s.store_id,
                  (s.warehouse_id is not null or s.source_store_id is not null or s.supplier_id is not null) as is_out
             from public.special_sales s
            where s.invoice_id = p_invoice_id and s.status <> 'cancelled'
              and (s.customer_id, s.store_id) is distinct from (v_inv.customer_id, v_inv.store_id)$n$,
$n$      'what', r.sale_no || ': ' || public.special_product_name(r.special_product_id)
        || case when r.is_out then ', already released, now shows ' else ' moves to ' end
        || concat_ws(' and ',
             case when v_inv.customer_id is distinct from r.customer_id
                  then coalesce((select c.full_name from public.customers c where c.id = v_inv.customer_id), 'the invoice''s customer') end,
             case when v_inv.store_id is distinct from r.store_id
                  then coalesce((select t.name from public.stores t where t.id = v_inv.store_id), 'the invoice''s store') end)
        || case when r.is_out then '; no stock moves' else '' end));
  end loop;

  -- 500: and each takes its line's price.
  for r in select s.id, s.sale_no, s.special_product_id, s.quantity, s.unit_price, s.total_amount,
                  round(coalesce(it.unit_price, 0), 2) as line_price
             from public.special_sales s
             join public.invoice_items it on it.id = s.invoice_item_id and it.invoice_id = s.invoice_id
            where s.invoice_id = p_invoice_id and s.status <> 'cancelled'
              and it.line_kind::text = 'special_product' and it.special_product_id = s.special_product_id
              and (s.unit_price, s.total_amount) is distinct from
                  (round(coalesce(it.unit_price, 0), 2), round(coalesce(it.unit_price, 0), 2) * s.quantity)
            order by s.sale_no for update of s
  loop
    update public.special_sales
       set unit_price = r.line_price, total_amount = r.line_price * r.quantity,
           notes = case when strpos(coalesce(notes, ''), 'Follows invoice ' || coalesce(v_inv.invoice_no, '') || ' as corrected: ' || v_reason) > 0 then notes
                        else concat_ws(E'\n', notes, 'Follows invoice ' || coalesce(v_inv.invoice_no, '') || ' as corrected: ' || v_reason) end
     where id = r.id;
    perform public.write_audit_ex('special_sales', r.id, 'special_sale_price_follows_invoice',
      jsonb_build_object('unit_price', r.unit_price, 'total_amount', r.total_amount),
      jsonb_build_object('unit_price', r.line_price, 'total_amount', r.line_price * r.quantity, 'doc_no', r.sale_no, 'invoice_id', p_invoice_id),
      'special', v_reason, v_inv.store_id);
    v_list := v_list || jsonb_build_array(jsonb_build_object('sale_no', r.sale_no, 'state', 'repriced',
      'what', r.sale_no || ': ' || public.special_product_name(r.special_product_id)
        || ' now shows S$' || to_char(r.line_price * r.quantity, 'FM999999990.00')
        || ', was S$' || to_char(r.total_amount, 'FM999999990.00')));
  end loop;
  return v_list;$n$,
$n$    elsif coalesce(p_header->>'benefit_action','') = ''
          and exists (select 1 from public.invoice_transferable_benefits(p_invoice_id)) then  -- 500: only when the save would ask
      v_reviews := v_reviews || jsonb_build_array(jsonb_build_object(
        'area','benefits',$n$];

  v_path text := current_setting('search_path');
  v_def text[] := array_fill(null::text, array[2]);
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  for i in 1 .. cardinality(c_sig) loop
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) <> c_after[i] then
      raise exception 'UNDO 500: public.% is not 500''s version (md5 %); nothing changed', c_sig[i], md5(d); end if;
    v_def[i] := d;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'UNDO 500: patch % is not found exactly once in public.%', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_before[i] then
      raise exception 'UNDO 500: the text worked back for public.% is not the BEFORE one (md5 %)', c_sig[i], md5(v_def[i]); end if;
    execute v_def[i];
  end loop;
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
