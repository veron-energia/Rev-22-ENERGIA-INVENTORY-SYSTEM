-- UNDO of 495 (with the user's go-ahead; the suite runs it). It puts the seven
-- patched functions back to their BEFORE texts, and drops the triggers and the three
-- functions 495 added. It refuses unless each function is exactly 495's version, so
-- a later version is never overwritten. The made-up stock it does not bring back, and
-- pages already deployed keep listing a service under Service on the invoice, which
-- then asks for stock again. One transaction, all or nothing.
do $undo$
declare
  c_sig constant text[] := array[
    'invoice_required_stock(uuid)',
    'invoice_goods_out(uuid)',
    'restore_invoice_stock(uuid,text)',
    'invoice_refund_options_before_sessions(uuid)',
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'trg_fulfil_from_warehouse()',
    'set_invoice_fulfilment_warehouse(uuid,uuid)'];
  c_before constant text[] := array[
    'c91dc1eb4f2b7b465de5fe4a8fb2ca0c',
    '15ffed0ff0d5d9cc5685af8e834302ae',
    '092316c3af22361f80d186e38fe49bf3',
    'bd3afcc79cd2f06f983607d54fed167c',
    '804ecd829cfecf713783a09a05d93c7e',
    'e1d41bce9c53d21ac2ab727042663cfb',
    '66bf7f38e06bf48116b63b71ca7663cb'];
  c_after constant text[] := array[
    'b14a1511d15457de4787df8d040e415f',
    'bb002119b3cb779a4b1c8bb79e08ae25',
    'fe23a3b4e428641b5aed19580614070a',
    '947f461d4581b2e7a32058b42c8250c4',
    '3280f4ed6afb93aed7366eaf100c6383',
    'ccc8ee71452ee75773a93fbe298bfe35',
    '817367d336fe41970118eb5ec8d71fc0'];
  c_fn constant int[] := array[1, 1, 2, 3, 4, 5, 5, 6, 7];
  c_anchor constant text[] := array[
$a$         or not exists (select 1 from public.invoices v where v.id = it.invoice_id and v.is_exchange))
   group by c.kind,c.item_id;$a$,
$a$   where x.product_id is null or r.quantity-x.quantity>0;$a$,
$a$     and m.movement_type::text = 'store_sale'
     and x.left_qty > 0$a$,
$a$from public.stock_movements m where m.invoice_id=p_invoice_id and m.movement_type::text='store_sale' order by m.id for update of m loop$a$,
$a$from public.stock_movements m join public.products p on p.id=m.product_id where m.invoice_id=i.id and m.movement_type::text='store_sale'),$a$,
$a$   if it.id is not null and it.line_kind in ('product','promotion') and jsonb_array_length(coalesce(p_stock,'[]'))=0$a$,
$a$    and exists(select 1 from public.stock_movements qs where qs.invoice_id=i.id and qs.movement_type::text='store_sale'$a$,
$a$     where ii.invoice_id = new.id and ii.line_kind = 'product' and ii.product_id is not null$a$,
$a$     where ii.invoice_id = p_invoice_id and ii.line_kind = 'product' and ii.product_id is not null$a$];
  c_new constant text[] := array[
$n$         or not exists (select 1 from public.invoices v where v.id = it.invoice_id and v.is_exchange))
    -- 495 (the user, 6 Nov 2026): a service holds no stock, so no invoice owes any
    -- for one, on its own line or inside a promotion.
    and not (c.kind='product' and public.product_is_service(c.item_id))
   group by c.kind,c.item_id;$n$,
$n$   where (x.product_id is null or r.quantity-x.quantity>0)
     -- 495: a service holds no stock, as above.
     and not (r.kind='product' and public.product_is_service(r.item_id));$n$,
$n$     and m.movement_type::text = 'store_sale'
     -- 495 (the user, 6 Nov 2026): a service holds no stock, so a sale of one from
     -- before 495 left nothing with the customer to return.
     and not public.product_is_service(m.product_id)
     and x.left_qty > 0$n$,
$n$from public.stock_movements m where m.invoice_id=p_invoice_id and m.movement_type::text='store_sale'
   -- 495 (the user, 6 Nov 2026): a service holds no stock, so a sale of one from
   -- before 495 puts nothing back.
   and not public.product_is_service(m.product_id) order by m.id for update of m loop$n$,
$n$from public.stock_movements m join public.products p on p.id=m.product_id where m.invoice_id=i.id and m.movement_type::text='store_sale'
   -- 495 (the user, 6 Nov 2026): a service holds no stock, so a sale of one from
   -- before 495 asks nothing.
   and not public.product_is_service(m.product_id)),$n$,
$n$   if it.id is not null and it.line_kind in ('product','promotion') and jsonb_array_length(coalesce(p_stock,'[]'))=0
    -- 495 (the user, 6 Nov 2026): a service line has no stock outcome to ask for,
    -- even with a real product on the invoice ...
    and not (it.line_kind='product' and public.product_is_service(it.product_id))$n$,
$n$    and exists(select 1 from public.stock_movements qs where qs.invoice_id=i.id and qs.movement_type::text='store_sale'
      -- 495: ... and an old sale of a service holds up no product line's refund.
      and not public.product_is_service(qs.product_id)$n$,
$n$     where ii.invoice_id = new.id and ii.line_kind = 'product' and ii.product_id is not null
       -- 495 (the user, 6 Nov 2026): a service holds no stock, so it asks nothing
       -- of the warehouse and the store is given nothing back for it.
       and not public.product_is_service(ii.product_id)$n$,
$n$     where ii.invoice_id = p_invoice_id and ii.line_kind = 'product' and ii.product_id is not null
       -- 495 (the user, 6 Nov 2026): a service holds no stock, so the warehouse need
       -- not cover it.
       and not public.product_is_service(ii.product_id)$n$];

  v_path text := current_setting('search_path');
  v_def text[] := array_fill(null::text, array[7]);
  d text; i int;
begin
  perform set_config('search_path', 'public', true);
  for i in 1 .. cardinality(c_sig) loop
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    if md5(d) <> c_after[i] then
      raise exception 'UNDO 495: public.% is not 495''s version (md5 %); nothing changed', c_sig[i], md5(d); end if;
    v_def[i] := d;
  end loop;
  for i in 1 .. cardinality(c_fn) loop
    if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
      raise exception 'UNDO 495: patch % is not found exactly once in public.%', i, c_sig[c_fn[i]]; end if;
    v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if md5(v_def[i]) <> c_before[i] then
      raise exception 'UNDO 495: the text worked back for public.% is not the BEFORE one (md5 %)', c_sig[i], md5(v_def[i]); end if;
    execute v_def[i];
  end loop;
  drop trigger service_holds_no_stock on public.store_inventory;
  drop trigger service_holds_no_stock on public.warehouse_inventory;
  drop trigger products_become_service_check on public.products;
  drop function public.trg_service_holds_no_stock();
  drop function public.trg_product_becomes_service();
  drop function public.product_is_service(uuid);
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
