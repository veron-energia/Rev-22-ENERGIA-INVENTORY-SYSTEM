-- scripts/special/undo-496.sql
--
-- UNDO of supabase/496_released_special_sale_stock_comes_back.sql: puts the seven functions
-- it patched back to their BEFORE texts and drops the four it added. After it, a refund or a
-- cancellation of a released special sale asks nothing and returns nothing again, as before 496.
--
-- It KEEPS special_sales.release_movement_id and the table special_sale_returns, and what
-- they hold (an unused column and table cost nothing, and units already settled stay
-- settled; a sale whose stock came back stays cancelled, its stock back). Dropping them is
-- a separate, deliberate step and loses that record.
--
-- Checked first, changed after, in ONE statement: each patched function must be its AFTER
-- (put back) or its BEFORE (left alone), anything else is refused. Run it on a copy first.
--
--   psql -X -v ON_ERROR_STOP=1 -d <database> -f scripts/special/undo-496.sql
set lock_timeout = '5s';

do $undo$
declare
  c_sig constant text[] := array['fulfil_special_doc(text,uuid,uuid,text)', 'invoice_refund_options(uuid)', 'invoice_action_plan(uuid,text,jsonb)', 'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)', 'record_invoice_stock_return(uuid,jsonb,text,uuid)', 'cancel_invoice_recorded(uuid,text,uuid)', 'create_special_docs_for_invoice(uuid)'];
  c_before constant text[] := array['e2fd9fca6842b5193ec7020445a45189', '689a71c246260d2c10ec44dd94eb7139', '383d618edb28c3c9a360242d038a022c', '3280f4ed6afb93aed7366eaf100c6383', '6b125cb5df1eb103781662bef41e9417', 'de52d9dbaef8ab15163bef35cb9d733d', '429f4ac315cb5d0557c2005807bad115'];
  c_after constant text[] := array['9b4520efc9d06b04360bacc2c035215b', '0a9276f8b967b24a040e486287182072', 'd8bf5ea6c92c49be3b53547e6f407278', '49f6880e4e6395b1468f32e4126472eb', '065df9ace464185d8cf44aba7a12dec9', '5490e4b48dfdab63b6dc5a0aa78d4bc7', '540b98385d9632abcc5fe35c23c00bb5'];
  c_before_alt constant text[] := array[null, null, null, '804ecd829cfecf713783a09a05d93c7e', null, null, null];
  c_after_alt constant text[] := array[null, null, null, '3fb10ac55903b9346c4898d988b808ce', null, null, null];
  c_fn constant int[] := array[1, 1, 1, 1, 1, 2, 3, 4, 4, 5, 6, 7, 7, 7, 7, 7];
  c_anchor constant text[] := array[
$a1$  v458_inv text; v458_owing numeric;  -- 458$a1$,
$a2$  if p_doc_kind = 'special_sale' then
    select special_product_id, quantity, sale_no into v_sp, v_qty, v_no$a2$,
$a3$      case when p_doc_kind = 'rental' then 'Rental released — ' else 'Special sale released — ' end || v_no,
      auth.uid());
  else$a3$,
$a4$        || ' (from store)',
      auth.uid());
  end if;$a4$,
$a5$           status = 'completed', fulfilled_at = now(), fulfilled_by = auth.uid()
     where id = p_doc_id;$a5$,
$a6$ return result||jsonb_build_object('therapy_sessions',(select coalesce(jsonb_agg(jsonb_build_object($a6$,
$a7$  -- ---- stock actually deducted for this line ----------------------------
  if it.line_kind::text in ('product','promotion') then
   for s in select * from jsonb_array_elements(coalesce(o->'stock','[]')) loop$a7$,
$a8$     raise exception 'Record the returned-and-sellable, damaged, or not-returned quantities for this product refund'; end if;
   v_total:=v_total+v_amount;$a8$,
$a9$   select * into sm from public.stock_movements where id=(x->>'movement_id')::uuid and invoice_id=i.id and movement_type::text='store_sale' for update;$a9$,
$a10$  select * into sm from public.stock_movements
   where id=(x->>'movement_id')::uuid and invoice_id=p_invoice_id and movement_type::text='store_sale' for update;$a10$,
$a11$ perform public.restore_invoice_stock(i.id,'Cancelled invoice: '||p_reason);$a11$,
$a12$  v458_units integer; v458_have integer; v458_cnt integer; v458_r public.rentals%rowtype;  -- 458$a12$,
$a13$    -- Already raised for this line: never duplicate on a re-run or a correction.$a13$,
$a14$                and (status <> 'cancelled' or warehouse_id is not null or source_store_id is not null$a14$,
$a15$                     or coalesce(cancelled_at, 'infinity') > coalesce(v_inv.reopened_at, '-infinity'))) then
      continue;
    end if;$a15$,
$a16$      for v_i in 1 .. greatest(coalesce(v_it.quantity,1), 1) loop$a16$];
  c_new constant text[] := array[
$n1$  v458_inv text; v458_owing numeric;  -- 458
  v496_mv uuid;  -- 496: the stock movement this release writes$n1$,
$n2$  -- 496 (the user, 6 Nov 2026): the invoice first, shared, as a refund takes it (for update), so a
  -- release and a refund of one invoice wait for one another instead of meeting on the stock row,
  -- or releasing what a refund has just taken back. A sale with no invoice waits for nothing.
  perform 1 from public.invoices v
   where v.id = (select d.invoice_id from (select s0.invoice_id from public.special_sales s0 where p_doc_kind = 'special_sale' and s0.id = p_doc_id
                                           union all
                                           select r0.invoice_id from public.rentals r0 where p_doc_kind = 'rental' and r0.id = p_doc_id) d limit 1)
     for share;
  if p_doc_kind = 'special_sale' then
    select special_product_id, quantity, sale_no into v_sp, v_qty, v_no$n2$,
$n3$      case when p_doc_kind = 'rental' then 'Rental released — ' else 'Special sale released — ' end || v_no,
      auth.uid())
    returning id into v496_mv;  -- 496
  else$n3$,
$n4$        || ' (from store)',
      auth.uid())
    returning id into v496_mv;  -- 496
  end if;$n4$,
$n5$           status = 'completed', fulfilled_at = now(), fulfilled_by = auth.uid(),
           release_movement_id = v496_mv  -- 496 (the user, 6 Nov 2026): a refund or a cancellation finds the unit by it
     where id = p_doc_id;$n5$,
$n6$ return result||jsonb_build_object(
  -- 496 (the user, 6 Nov 2026): the units released for this invoice's special sales are
  -- offered as stock to take back, as a product's deduction is (the same fields, and
  -- the sale, its line and the shelf it left, a warehouse or a store).
  'stock',coalesce(result->'stock','[]'::jsonb)||coalesce((select jsonb_agg(jsonb_build_object(
      'movement_id',r.movement_id,'product_id',r.product_id,'product_name',r.product_name,'store_id',r.store_id,
      'quantity',r.quantity,'resolved_quantity',r.resolved_quantity,'special_sale_id',r.special_sale_id,'sale_no',r.sale_no,
      'invoice_item_id',r.invoice_item_id,'location_type',r.location_type,'location_id',r.location_id,
      'location_name',r.location_name) order by r.sale_no)
    from public.special_release_rows(p_invoice_id) r),'[]'::jsonb),
  'therapy_sessions',(select coalesce(jsonb_agg(jsonb_build_object($n6$,
$n7$  -- ---- 496 (the user, 6 Nov 2026): the units released for this special sale line ----
  -- A special sale is one unit, and its stock was taken when it was released from a
  -- warehouse or a store, which no product line's deduction records. As many units as
  -- are being taken back (all of them for a cancellation or a full refund), by sale
  -- number, with the same fields as a product's deduction; store_name names the shelf
  -- it left, a store or a warehouse, so the screens need no change.
  if it.line_kind::text = 'special_product' then
   declare k496 int:=0; w496 int:=0;
   begin
    -- A part refund of some units while others of the line still wait: a waiting one the staff
    -- said "no" to (393's answers, carried on the lines as "waiting": the customer is not taking
    -- it) is a unit refunded first, so the released units asked about are the rest.
    if p_action='refund_partial' then
     select count(*) into w496
       from jsonb_array_elements(coalesce(p_lines,'[]')) pl,
            jsonb_array_elements(case when jsonb_typeof(pl->'waiting')='array' then pl->'waiting' else '[]'::jsonb end) q
      where jsonb_typeof(q->'still_taking')='boolean' and not (q->>'still_taking')::boolean
        and exists(select 1 from public.special_sales ws
                    where ws.id::text=lower(q->>'doc_id') and ws.invoice_item_id=it.id and ws.status='pending');
    end if;
    for s in select e.value from jsonb_array_elements(coalesce(o->'stock','[]')) e
              where e.value->>'invoice_item_id'=it.id::text and e.value->>'special_sale_id' is not null
              order by e.value->>'sale_no' loop
     exit when k496>=greatest(v_qty-w496,0);
     v_returnable:=coalesce((s->>'quantity')::int,0)-coalesce((s->>'resolved_quantity')::int,0);
     if v_returnable<=0 then continue; end if;
     v_returnable:=least(v_returnable,greatest(v_qty-w496,0)-k496);
     k496:=k496+v_returnable;
     v_stock:=v_stock||jsonb_build_array(jsonb_build_object(
       'movement_id',s->>'movement_id','product_name',s->>'product_name','store_id',s->>'store_id',
       'outstanding',coalesce((s->>'quantity')::int,0)-coalesce((s->>'resolved_quantity')::int,0),
       'proposed_sellable',v_returnable,'damaged_quantity',0,'not_returned_quantity',0,
       'store_name',s->>'location_name','location_type',s->>'location_type','location_id',s->>'location_id',
       'special_sale_id',s->>'special_sale_id','sale_no',s->>'sale_no'));
    end loop;
   end;
  end if;
  -- ---- stock actually deducted for this line ----------------------------
  if it.line_kind::text in ('product','promotion') then
   for s in select * from jsonb_array_elements(coalesce(o->'stock','[]')) loop
    continue when s->>'special_sale_id' is not null;  -- 496: a special sale's units are listed above, on their own line$n7$,
$n8$     raise exception 'Record the returned-and-sellable, damaged, or not-returned quantities for this product refund'; end if;
   -- 496 (the user, 6 Nov 2026): a special sale's line is asked what a product's is, for the units
   -- released for it that nobody has settled: back and sellable, damaged, or not returned. A refund
   -- that takes the whole of the line answers for every one of them (once the invoice is refunded
   -- nothing can ask again); a part refund answers for some at least, unless what it refunds is a
   -- waiting unit the staff said "no" to (the customer is not taking it).
   if it.id is not null and it.line_kind::text='special_product' then
    declare o496 int; u496 int; e496 boolean; bad496 boolean;
    begin
     select count(*) filter (where r.quantity>r.resolved_quantity),
            count(*) filter (where r.quantity>r.resolved_quantity
                              and not exists(select 1 from jsonb_array_elements(coalesce(p_stock,'[]')) ans where ans->>'movement_id'=r.movement_id::text))
       into o496,u496 from public.special_release_rows(i.id) r where r.invoice_item_id=it.id;
     e496:=exists(select 1 from jsonb_array_elements(coalesce(p_lines,'[]')) pl,
                        jsonb_array_elements(case when jsonb_typeof(pl->'waiting')='array' then pl->'waiting' else '[]'::jsonb end) q
                   where jsonb_typeof(q->'still_taking')='boolean' and not (q->>'still_taking')::boolean
                     and exists(select 1 from public.special_sales ws
                                 where ws.id::text=lower(q->>'doc_id') and ws.invoice_item_id=it.id and ws.status='pending'));
     bad496:=o496>0 and case when v_amount>=greatest(v_line_paid-v_refunded,0) then u496>0
                             else jsonb_array_length(coalesce(p_stock,'[]'))=0 and not e496 end;
     if bad496 then
       raise exception 'Record the returned-and-sellable, damaged, or not-returned quantities for this special sale refund'; end if;
    end;
   end if;
   v_total:=v_total+v_amount;$n8$,
$n9$   -- 496: a unit released for a special sale of this invoice goes back on the shelf it
   -- left, a warehouse or a store, by its own rule (special_sale_returns): only a unit of a
   -- line this refund is for, so a line still billed is never settled by another's answer.
   if exists(select 1 from public.special_release_rows(i.id) r where r.movement_id=(x->>'movement_id')::uuid) then
     if not exists(select 1 from public.special_release_rows(i.id) r
                    where r.movement_id=(x->>'movement_id')::uuid
                      and exists(select 1 from jsonb_array_elements(p_lines) pl where pl->>'invoice_item_id'=r.invoice_item_id::text)) then
       raise exception 'Answer for the units of the lines being refunded: that unit is on a line this refund does not cover'; end if;
     perform public.return_released_special_stock(i.id,(x->>'movement_id')::uuid,
       coalesce((x->>'sellable_quantity')::int,0),coalesce((x->>'damaged_quantity')::int,0),coalesce((x->>'not_returned_quantity')::int,0),
       p_request_id,p_reason,'refunded');
     continue;
   end if;
   select * into sm from public.stock_movements where id=(x->>'movement_id')::uuid and invoice_id=i.id and movement_type::text='store_sale' for update;$n9$,
$n10$  -- 496 (the user, 6 Nov 2026): a unit released for a special sale of this invoice goes
  -- back on the shelf it left by its own rule (special_sale_returns). This is the
  -- cancellation's step, taken before the cancellation puts back the rest.
  if exists(select 1 from public.special_release_rows(p_invoice_id) r where r.movement_id=(x->>'movement_id')::uuid) then
   perform public.return_released_special_stock(p_invoice_id,(x->>'movement_id')::uuid,
     coalesce((x->>'sellable_quantity')::int,0),coalesce((x->>'damaged_quantity')::int,0),coalesce((x->>'not_returned_quantity')::int,0),
     p_request_id,p_reason,'invoice cancelled');
   n:=n+1; continue;
  end if;
  select * into sm from public.stock_movements
   where id=(x->>'movement_id')::uuid and invoice_id=p_invoice_id and movement_type::text='store_sale' for update;$n10$,
$n11$ perform public.restore_invoice_stock(i.id,'Cancelled invoice: '||p_reason);
 -- 496 (the user, 6 Nov 2026): and the units released for its special sales, to the shelf they left.
 perform public.restore_released_special_stock(i.id,'Cancelled invoice: '||p_reason,p_request_id);$n11$,
$n12$  v458_units integer; v458_have integer; v458_cnt integer; v458_r public.rentals%rowtype;  -- 458
  v496_back integer := 0;  -- 496: units of a line whose stock came back, to raise again$n12$,
$n13$    v496_back := 0;  -- 496
    -- Already raised for this line: never duplicate on a re-run or a correction.$n13$,
$n14$                and (status <> 'cancelled' or ((warehouse_id is not null or source_store_id is not null) and not coalesce(stock_returned, false))  -- 496: one whose stock came back no longer counts$n14$,
$n15$                     or coalesce(cancelled_at, 'infinity') > coalesce(v_inv.reopened_at, '-infinity'))) then
      -- 496 (the user, 6 Nov 2026): the units of this line whose stock came back (a refund or a
      -- cancellation put them on the shelf) before the invoice was last reopened are raised again,
      -- as many as they are, but never more than the line holds beyond the units that still count:
      -- one damaged or not returned stays released and is not raised twice, nor is a unit raised
      -- again once it is. With none that came back, as before.
      if v_it.line_kind::text = 'special_product' and v_inv.reopened_at is not null then
        select least(count(*) filter (where status = 'cancelled' and coalesce(stock_returned, false) and cancelled_at <= v_inv.reopened_at),
                     greatest(coalesce(v_it.quantity, 1), 1)
                       - count(*) filter (where status <> 'cancelled'
                                             or ((warehouse_id is not null or source_store_id is not null) and not coalesce(stock_returned, false))
                                             or coalesce(cancelled_at, 'infinity') > v_inv.reopened_at))
          into v496_back from public.special_sales where invoice_item_id = v_it.id;
      end if;
      continue when coalesce(v496_back, 0) <= 0;
    end if;$n15$,
$n16$      for v_i in 1 .. (case when v496_back > 0 then v496_back else greatest(coalesce(v_it.quantity,1), 1) end) loop$n16$];
  c_add_sig constant text[] := array['special_release_rows(uuid)', 'return_released_special_stock(uuid,uuid,integer,integer,integer,uuid,text,text)', 'restore_released_special_stock(uuid,text,uuid)', 'link_released_special_movements()'];

  v_path text := current_setting('search_path');
  v_def text[] := array_fill(null::text, array[7]);
  v_make boolean[] := array_fill(false, array[7]);
  v_target text[] := array_fill(null::text, array[7]);
  v_acl text[] := array_fill(null::text, array[7]);
  d text; m text; i int;
begin
  perform set_config('search_path', 'public', true);

  -- 1. Checks
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception 'undo 496: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    m := md5(d);
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if m = c_before[i] or m = c_before_alt[i] then
      raise notice 'undo 496: public.% is already its BEFORE; left alone', c_sig[i];
    elsif m = c_after[i] then
      v_make[i] := true; v_def[i] := d; v_target[i] := c_before[i];
    elsif m = c_after_alt[i] then
      v_make[i] := true; v_def[i] := d; v_target[i] := c_before_alt[i];
    else
      raise exception 'undo 496: public.% is neither the version 496 left nor the one before it (md5 %). Nothing was changed.', c_sig[i], m;
    end if;
  end loop;
  -- The patches, last first: each one's replacement is found exactly once and gives its text back.
  for i in reverse cardinality(c_fn) .. 1 loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_new[i], ''))) / length(c_new[i]) <> 1 then
        raise exception 'undo 496: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_new[i], c_anchor[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> v_target[i] then
      raise exception 'undo 496: the restored text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Put the patched functions back, then drop what only they called
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_add_sig) loop
    if to_regprocedure('public.' || c_add_sig[i]) is not null then
      execute format('drop function public.%s', c_add_sig[i]);
    end if;
  end loop;

  -- 3. Checks after
  for i in 1 .. cardinality(c_sig) loop
    m := md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i])));
    if m <> c_before[i] and m is distinct from c_before_alt[i] then
      raise exception 'undo 496: public.% was restored to an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception 'undo 496: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
