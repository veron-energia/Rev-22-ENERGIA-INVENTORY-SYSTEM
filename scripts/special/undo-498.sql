-- UNDO of 498 (with the user's go-ahead; the suite runs it). It puts the four patched
-- functions back to their BEFORE texts. It refuses unless each function is exactly 498's
-- version, so a later version is never overwritten. Sales that already moved stay moved.
-- Undo 498 before 497. One transaction, all or nothing.
do $undo$
declare
  c_sig constant text[] := array[
    'invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)',
    'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    'fulfil_special_doc(text,uuid,uuid,text)',
    'release_special_sale_to_supplier(uuid,uuid,text)'];
  c_before constant text[] := array[
    '630cd846df0cb44a2b6038e83a46a18d',
    '9aac5395dd18fd8349727d6c8aa0c633',
    '9b4520efc9d06b04360bacc2c035215b',
    '15b36ba68fd7b70a1361e80f5e5fad4e'];
  c_after constant text[] := array[
    '3cf6cfd8a22e5776e7b77e8d5ff3753d',
    'cea93a5dd73d429f6437f4c9a8fcaa52',
    'f21b8f6e42e7f17aa8c15b7ab0976935',
    'aaea37ea6d5b2c00e24738c678028b66'];
  c_fn constant int[] := array[1, 1, 2, 3, 4, 4, 4];
  c_anchor constant text[] := array[
$a$--   * A cancelled or refunded invoice, and a rental's line, are left as they are.
-- Internal. Answers [{sale_no, state, what}], state: waiting_off, back, stays, raised.$a$,
$a$  end loop;
  return v_list;
end $function$$a$,
$a$ if not same_lines then
   v497_special := public.invoice_special_sales_follow_lines(i.id,v_snapshot->'items',p_reason,p_request_id);$a$,
$a$      raise exception '% cannot be released yet: its invoice % has S$% owing. Take the payment first, then release it.',
        v_no, v458_inv, to_char(v458_owing, 'FM999999990.00');
    end if;
  end if;$a$,
$a$  v_note text := nullif(btrim(coalesce(p_deliver_to, '')), '');$a$,
$a$  select * into v_sale from public.special_sales where id = p_sale_id
     and warehouse_id is null and source_store_id is null and supplier_id is null$a$,
$a$    raise exception '% cannot be released: %. It is no longer waiting for a warehouse.', v_sale.sale_no, v_problem;
  end if;$a$];
  c_new constant text[] := array[
$n$--   * 498 (the user, 7 Nov 2026): a sale still waiting takes the invoice's customer and
--     store whenever they differ, whichever line it is on. A released one keeps them:
--     the machine went to that customer from there.
--   * A cancelled or refunded invoice, and a rental's line, are left as they are.
-- Internal. Answers [{sale_no, state, what}], state: waiting_off, back, stays, raised, moved.$n$,
$n$  end loop;

  -- 498: a sale still waiting follows the invoice's customer and store.
  for r in select s.id, s.sale_no, s.special_product_id, s.customer_id, s.store_id
             from public.special_sales s
            where s.invoice_id = p_invoice_id and s.status <> 'cancelled'
              and s.warehouse_id is null and s.source_store_id is null and s.supplier_id is null
              and (s.customer_id, s.store_id) is distinct from (v_inv.customer_id, v_inv.store_id)
            order by s.sale_no for update
  loop
    update public.special_sales
       set customer_id = v_inv.customer_id, store_id = v_inv.store_id,
           notes = concat_ws(E'\n', notes, 'Follows invoice ' || coalesce(v_inv.invoice_no, '') || ' as corrected: ' || v_reason)
     where id = r.id;
    perform public.write_audit_ex('special_sales', r.id, 'special_sale_follows_invoice',
      jsonb_build_object('customer_id', r.customer_id, 'store_id', r.store_id),
      jsonb_build_object('customer_id', v_inv.customer_id, 'store_id', v_inv.store_id, 'doc_no', r.sale_no, 'invoice_id', p_invoice_id),
      'special', v_reason, v_inv.store_id);
    v_list := v_list || jsonb_build_array(jsonb_build_object('sale_no', r.sale_no, 'state', 'moved',
      'what', r.sale_no || ': ' || public.special_product_name(r.special_product_id) || ' moves to '
        || concat_ws(' and ',
             case when v_inv.customer_id is distinct from r.customer_id
                  then coalesce((select c.full_name from public.customers c where c.id = v_inv.customer_id), 'the invoice''s customer') end,
             case when v_inv.store_id is distinct from r.store_id
                  then coalesce((select t.name from public.stores t where t.id = v_inv.store_id), 'the invoice''s store') end)));
  end loop;
  return v_list;
end $function$$n$,
$n$ if not same_lines or (n.customer_id, n.store_id) is distinct from (i.customer_id, i.store_id) then  -- 498: a sale still waiting follows these too
   v497_special := public.invoice_special_sales_follow_lines(i.id,v_snapshot->'items',p_reason,p_request_id);$n$,
$n$      raise exception '% cannot be released yet: its invoice % has S$% owing. Take the payment first, then release it.',
        v_no, v458_inv, to_char(v458_owing, 'FM999999990.00');
    end if;
  end if;
  -- 498 (the user, 7 Nov 2026): and so does a special sale: raised once its invoice is
  -- paid, it can find itself on one that owes after a correction or a payment taken back.
  if p_doc_kind = 'special_sale' then
    select i.invoice_no, greatest(public.invoice_charge_total(i.id) - public.invoice_net_received(i.id), 0)
      into v458_inv, v458_owing
      from public.special_sales x join public.invoices i on i.id = x.invoice_id
     where x.id = p_doc_id and i.status in ('unpaid', 'partially_paid');
    if coalesce(v458_owing, 0) > 0 then
      raise exception '% cannot be released yet: its invoice % has S$% owing. Take the payment first, then release it.',
        v_no, v458_inv, to_char(v458_owing, 'FM999999990.00');
    end if;
  end if;$n$,
$n$  v_note text := nullif(btrim(coalesce(p_deliver_to, '')), '');
  v498_inv text; v498_owing numeric;  -- 498$n$,
$n$  -- 498: the invoice first, shared, as fulfil_special_doc takes it (496), so the check below
  -- and a correction or a payment of that invoice wait for one another.
  perform 1 from public.invoices v
   where v.id = (select s0.invoice_id from public.special_sales s0 where s0.id = p_sale_id)
     for share;
  select * into v_sale from public.special_sales where id = p_sale_id
     and warehouse_id is null and source_store_id is null and supplier_id is null$n$,
$n$    raise exception '% cannot be released: %. It is no longer waiting for a warehouse.', v_sale.sale_no, v_problem;
  end if;
  -- 498 (the user, 7 Nov 2026): it waits for its invoice to be paid in full, as fulfil_special_doc.
  select i.invoice_no, greatest(public.invoice_charge_total(i.id) - public.invoice_net_received(i.id), 0)
    into v498_inv, v498_owing
    from public.invoices i
   where i.id = v_sale.invoice_id and i.status in ('unpaid', 'partially_paid');
  if coalesce(v498_owing, 0) > 0 then
    raise exception '% cannot be released yet: its invoice % has S$% owing. Take the payment first, then release it.',
      v_sale.sale_no, v498_inv, to_char(v498_owing, 'FM999999990.00');
  end if;$n$];

  v_path text := current_setting('search_path');
  v_def text[] := array_fill(null::text, array[4]);
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  for i in 1 .. cardinality(c_sig) loop
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) <> c_after[i] then
      raise exception 'UNDO 498: public.% is not 498''s version (md5 %); nothing changed', c_sig[i], md5(d); end if;
    v_def[i] := d;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'UNDO 498: patch % is not found exactly once in public.%', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_before[i] then
      raise exception 'UNDO 498: the text worked back for public.% is not the BEFORE one (md5 %)', c_sig[i], md5(v_def[i]); end if;
    execute v_def[i];
  end loop;
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
