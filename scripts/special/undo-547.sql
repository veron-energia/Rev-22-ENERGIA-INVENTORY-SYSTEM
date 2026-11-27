-- UNDO of 547 (with the user's go-ahead): special, consignment and rental items leave an invoice's
-- Goods collected again. MADE BY gen_undo547.py with 547.
--
-- It refuses, with nothing changed, unless every function 547 changed or added is exactly 547's (so
-- it runs BEFORE any older UNDO, scripts/permissions/undo-546.sql included), and while staff have
-- recorded anything under 547 (a Collected / Delivered record, a return, a special sale's stock back
-- as "item returned"): undoing would lose those records and leave the sales and rentals they raised
-- waiting. A test file that runs it inside its own rolled-back transaction, only to put the
-- functions back as before 547, sets energia.undo547_test_only to on (session-local) first: then
-- whatever was recorded under 547 goes with the tables (and the special sales' 'item returned' stock
-- rows), and the flag is cleared again. A real undo never sets it. The records 547 itself made of the items released before it (headers with source
-- 'migration' and their lines) are removed, and invoice_handovers_source_check gets its three
-- sources again. Decide with the Owner what to keep first; a test file empties its own (rolled-back) rows
-- before running it.
--
-- What it does: puts back the nine patched functions by reversing 547's own patches (each exactly as
-- often as 547 made it), the four replaced ones from their texts as production had them after 546,
-- drops the eight new functions and the two tables, and gives special_sale_returns_why_check its
-- three reasons again. Afterwards every changed function's md5 must be its BEFORE (production after
-- 546: fingerprint f5f09a8bf80f379ccdf38b6edaad0dbc/1462). Pages: revert the page commit too (the
-- pages of 547 work without it: no "specials", nothing shown). One transaction; waits at most 5
-- seconds for a lock. The 547 row in supabase_migrations.schema_migrations stays; with the user's
-- OK, remove that one row or record this UNDO beside it.
set lock_timeout = '5s';
do $undo$
declare
  c_before_0 constant text := $def$CREATE OR REPLACE FUNCTION public.invoice_handover_internal(p_invoice_id uuid, p_handover jsonb, p_request_id uuid, p_source text, p_settlement_request_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 399: what the customer took before paying in full (the Owner, 6 Oct 2026).
--   p_handover  {"none": true}: "Nothing taken", recorded as such;
--               {"items": [{"product_id": ..., "qty": n}, ...]}: each product
--               leaves the invoice's store now, up to what is still to
--               collect (invoice_stock_to_deduct, the figure full payment
--               takes), as a store_sale linked to the invoice; refused when
--               the store is short or the invoice fulfils from a warehouse.
--   p_source    'payment' (with a part payment, from
--               record_invoice_settlement) or 'button' ("Hand over items").
-- The same request id with the same answer returns what it wrote; with a
-- different answer it is refused. A settlement that paid the invoice in full
-- skips it: every item left the store with that payment.
declare
  i public.invoices%rowtype; h public.invoice_handovers%rowtype;
  v_none boolean; v_raw jsonb; v_items jsonb; v_hash text; e jsonb; x record;
  v_left integer; v_have integer; v_name text; v_store text; v_mov uuid; v_id uuid;
  v_replayed boolean := false; v_res jsonb;
begin
  if p_request_id is null then raise exception 'A request ID is required'; end if;
  if p_source is null or p_source not in ('payment', 'button') then
    raise exception 'Unknown hand-over source %', p_source; end if;
  select * into i from public.invoices where id = p_invoice_id for update;
  if not found or i.deleted_at is not null then raise exception 'Invoice not found'; end if;

  if jsonb_typeof(p_handover) is distinct from 'object' then
    raise exception 'Say what the customer took now: "Nothing taken" or the items taken'; end if;
  if p_handover ? 'none' and jsonb_typeof(p_handover->'none') <> 'boolean' then
    raise exception 'Say what the customer took now: "Nothing taken" or the items taken'; end if;
  v_none := coalesce((p_handover->>'none')::boolean, false);
  v_raw := coalesce(p_handover->'items', '[]'::jsonb);
  if jsonb_typeof(v_raw) <> 'array' then raise exception 'The items taken must be a list'; end if;
  if v_none and jsonb_array_length(v_raw) > 0 then
    raise exception 'Choose "Nothing taken" or the items taken, not both'; end if;
  if not v_none and jsonb_array_length(v_raw) = 0 then
    raise exception 'Say what the customer took now: "Nothing taken" or at least one item'; end if;
  for e in select q.value from jsonb_array_elements(v_raw) q loop
    if jsonb_typeof(e) <> 'object'
       or coalesce(e->>'product_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'Every item taken needs its product'; end if;
    if jsonb_typeof(e->'qty') is distinct from 'number'
       or (e->>'qty')::numeric <> trunc((e->>'qty')::numeric)
       or (e->>'qty')::numeric < 1 or (e->>'qty')::numeric > 100000 then
      raise exception 'Every item taken needs a whole quantity of at least 1'; end if;
  end loop;
  -- One row per product, quantities added up, in a fixed order, so a retry
  -- with the same answer hashes the same.
  select coalesce(jsonb_agg(jsonb_build_object('product_id', s.product_id, 'qty', s.qty) order by s.product_id), '[]'::jsonb)
    into v_items
    from (select (q.value->>'product_id')::uuid as product_id, sum((q.value->>'qty')::integer)::integer as qty
            from jsonb_array_elements(v_raw) q group by 1) s;
  v_hash := md5(jsonb_build_object('invoice', i.id, 'none', v_none, 'items', v_items)::text);

  select * into h from public.invoice_handovers where request_id = p_request_id;
  if found then
    -- A retry: what it wrote, nothing written again.
    if h.invoice_id <> i.id or h.kind = 'return' or h.request_hash <> v_hash then
      raise exception 'Request % was already used for a different hand-over', p_request_id; end if;
    v_id := h.id; v_replayed := true;
  else
    if p_source = 'payment' and i.status::text in ('paid', 'completed_foc') then
      -- This very settlement paid the invoice in full: every item left the
      -- store with the payment (deduct_invoice_stock).
      return jsonb_build_object('skipped', 'paid_in_full',
        'message', 'Paid in full: every item was taken out of stock with the payment.');
    end if;
    if i.status::text not in ('unpaid', 'partially_paid') then
      raise exception 'Goods are handed over this way only on an unpaid or part-paid invoice (% is %)',
        i.invoice_no, replace(i.status::text, '_', ' '); end if;
    if not v_none and i.fulfil_warehouse_id is not null then
      raise exception '% is set to fulfil from a warehouse, so its goods leave the warehouse when it is paid in full. To hand goods over from the store now, set "Fulfil from" back to this store''s stock first.',
        i.invoice_no; end if;
    select s.name into v_store from public.stores s where s.id = i.store_id;

    insert into public.invoice_handovers
      (invoice_id, store_id, kind, source, request_id, request_hash, settlement_request_id, created_by)
    values (i.id, i.store_id, case when v_none then 'nothing_taken' else 'handover' end, p_source,
            p_request_id, v_hash, p_settlement_request_id, auth.uid())
    returning id into v_id;

    for x in select (q.value->>'product_id')::uuid as product_id, (q.value->>'qty')::integer as qty
               from jsonb_array_elements(v_items) q
    loop
      select p.name into v_name from public.products p where p.id = x.product_id;
      if not exists (select 1 from public.invoice_required_stock(i.id) r
                      where r.kind = 'product' and r.item_id = x.product_id) then
        raise exception '"%" is not on %', coalesce(v_name, x.product_id::text), i.invoice_no; end if;
      select coalesce(sum(t.quantity), 0)::integer into v_left
        from public.invoice_stock_to_deduct(i.id) t
       where t.kind = 'product' and t.item_id = x.product_id;
      if x.qty > v_left then
        raise exception 'Only % of "%" is still to collect on % (handing over %)',
          v_left, v_name, i.invoice_no, x.qty; end if;
      update public.store_inventory set current_qty = current_qty - x.qty, updated_at = now()
       where store_id = i.store_id and product_id = x.product_id and current_qty >= x.qty;
      if not found then
        select coalesce(si.current_qty, 0) into v_have from public.store_inventory si
         where si.store_id = i.store_id and si.product_id = x.product_id;
        raise exception 'Not enough stock at % for "%": handing over %, the store has %',
          coalesce(v_store, 'this store'), v_name, x.qty, coalesce(v_have, 0); end if;
      insert into public.stock_movements
        (product_id, movement_type, from_store_id, invoice_id, quantity, notes, created_by)
      values (x.product_id, 'store_sale'::stock_movement_type, i.store_id, i.id, x.qty,
              'Handed over before full payment — ' || i.invoice_no, auth.uid())
      returning id into v_mov;
      insert into public.invoice_handover_lines (handover_id, invoice_id, product_id, quantity, movement_id)
      values (v_id, i.id, x.product_id, x.qty, v_mov);
    end loop;

    perform public.write_audit_ex('invoices', i.id,
      case when v_none then 'invoice_goods_nothing_taken' else 'invoice_goods_handed_over' end, null,
      jsonb_build_object('invoice_no', i.invoice_no, 'handover_id', v_id, 'source', p_source,
                         'settlement_request_id', p_settlement_request_id, 'items', v_items),
      'inventory', null, i.store_id);
  end if;

  select jsonb_build_object('success', true, 'replayed', v_replayed, 'handover_id', h2.id,
           'kind', h2.kind, 'source', h2.source, 'invoice_id', h2.invoice_id, 'invoice_no', i.invoice_no,
           'created_at', h2.created_at,
           'items', coalesce((select jsonb_agg(jsonb_build_object('product_id', l.product_id, 'name', p.name,
                                                 'quantity', l.quantity) order by p.name, l.product_id)
                                from public.invoice_handover_lines l
                                left join public.products p on p.id = l.product_id
                               where l.handover_id = h2.id), '[]'::jsonb))
    into v_res
    from public.invoice_handovers h2 where h2.id = v_id;
  return v_res;
end $function$
$def$;
  c_before_1 constant text := $def$CREATE OR REPLACE FUNCTION public.record_invoice_goods_return(p_invoice_id uuid, p_items jsonb, p_reason text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 399: "Record items returned" (the Owner, 6 Oct 2026): goods handed over
-- before full payment that came back, or are written off, so a correction
-- may take them off the invoice. Owner/Manager, on an unpaid or part-paid
-- invoice (a paid one goes through Refund / Cancel). Per product:
--   good          back into the store it left, with an invoice_cancel_return
--                 movement pointing at the hand-over (as restore_invoice_stock
--                 puts a cancelled sale back);
--   damaged,      written off through the existing dispositions
--   not_returned  (invoice_stock_dispositions), as a cancellation or refund
--                 records them.
-- Spread over the product's movements still out, oldest first. The same
-- request id with the same answer returns what it wrote.
declare
  i public.invoices%rowtype; h public.invoice_handovers%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  e jsonb; k text; v_items jsonb; v_hash text; x record; g record; v_name text; v_out integer;
  tg integer; td integer; tn integer; v_good integer; v_dam integer; v_nr integer;
  v_ret uuid; v_disp uuid; v_id uuid; v_replayed boolean := false; v_res jsonb;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can record items returned' using errcode = '42501'; end if;
  if p_request_id is null then raise exception 'A request ID is required'; end if;
  select * into i from public.invoices where id = p_invoice_id for update;
  if not found or i.deleted_at is not null then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(i.store_id) then
    raise exception 'No access to this invoice' using errcode = '42501'; end if;
  if v_reason is null then raise exception 'Give the reason the goods came back'; end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Choose at least one item and say how it came back'; end if;
  for e in select q.value from jsonb_array_elements(p_items) q loop
    if jsonb_typeof(e) <> 'object'
       or coalesce(e->>'product_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'Every item returned needs its product'; end if;
    foreach k in array array['good', 'damaged', 'not_returned'] loop
      if e ? k and (jsonb_typeof(e->k) <> 'number' or (e->>k)::numeric <> trunc((e->>k)::numeric)
                    or (e->>k)::numeric < 0 or (e->>k)::numeric > 100000) then
        raise exception 'Good, damaged and not returned are whole numbers, 0 or more'; end if;
    end loop;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('product_id', s.product_id, 'good', s.good,
           'damaged', s.damaged, 'not_returned', s.not_returned) order by s.product_id), '[]'::jsonb)
    into v_items
    from (select (q.value->>'product_id')::uuid as product_id,
                 sum(coalesce((q.value->>'good')::integer, 0))::integer as good,
                 sum(coalesce((q.value->>'damaged')::integer, 0))::integer as damaged,
                 sum(coalesce((q.value->>'not_returned')::integer, 0))::integer as not_returned
            from jsonb_array_elements(p_items) q group by 1) s
   where s.good + s.damaged + s.not_returned > 0;
  if jsonb_array_length(v_items) = 0 then
    raise exception 'Choose at least one item and say how it came back'; end if;
  v_hash := md5(jsonb_build_object('invoice', i.id, 'items', v_items, 'reason', v_reason)::text);

  select * into h from public.invoice_handovers where request_id = p_request_id;
  if found then
    if h.invoice_id <> i.id or h.kind <> 'return' or h.request_hash <> v_hash then
      raise exception 'Request % was already used for something else', p_request_id; end if;
    v_id := h.id; v_replayed := true;
  else
    if i.status::text not in ('draft', 'unpaid', 'partially_paid')
       or not public.invoice_before_full_payment(i.id) then
      raise exception 'Items returned are recorded here only on an unpaid or part-paid invoice not yet paid in full. % is %: use Refund / Cancel, which asks what came back.',
        i.invoice_no, replace(i.status::text, '_', ' '); end if;
    insert into public.invoice_handovers
      (invoice_id, store_id, kind, source, request_id, request_hash, reason, created_by)
    values (i.id, i.store_id, 'return', 'return', p_request_id, v_hash, v_reason, auth.uid())
    returning id into v_id;

    for x in select (q.value->>'product_id')::uuid as product_id, (q.value->>'good')::integer as good,
                    (q.value->>'damaged')::integer as damaged, (q.value->>'not_returned')::integer as not_returned
               from jsonb_array_elements(v_items) q
    loop
      select p.name into v_name from public.products p where p.id = x.product_id;
      select coalesce(sum(o.quantity), 0)::integer into v_out
        from public.invoice_goods_out(i.id) o where o.product_id = x.product_id;
      if x.good + x.damaged + x.not_returned > v_out then
        raise exception 'Only % of "%" is out with the customer on % (recording %)',
          v_out, coalesce(v_name, x.product_id::text), i.invoice_no, x.good + x.damaged + x.not_returned; end if;
      tg := x.good; td := x.damaged; tn := x.not_returned;
      for g in select o.* from public.invoice_goods_out(i.id) o
                where o.product_id = x.product_id order by o.created_at, o.movement_id
      loop
        exit when tg + td + tn = 0;
        v_good := least(g.quantity, tg);
        v_dam := least(g.quantity - v_good, td);
        v_nr := least(g.quantity - v_good - v_dam, tn);
        tg := tg - v_good; td := td - v_dam; tn := tn - v_nr;
        v_ret := null; v_disp := null;
        if v_good > 0 then
          insert into public.store_inventory (store_id, product_id, current_qty)
          values (g.store_id, x.product_id, v_good)
          on conflict (store_id, product_id)
            do update set current_qty = public.store_inventory.current_qty + excluded.current_qty, updated_at = now();
          insert into public.stock_movements
            (product_id, movement_type, to_store_id, invoice_id, quantity, notes, created_by, reversed_sale_id)
          values (x.product_id, 'invoice_cancel_return'::stock_movement_type, g.store_id, i.id, v_good,
                  'Returned before full payment — ' || i.invoice_no || ': ' || v_reason, auth.uid(), g.movement_id)
          returning id into v_ret;
        end if;
        if v_dam + v_nr > 0 then
          insert into public.invoice_stock_dispositions
            (invoice_id, movement_id, request_id, sellable_quantity, damaged_quantity, not_returned_quantity, reason, created_by)
          values (i.id, g.movement_id, p_request_id, 0, v_dam, v_nr, v_reason, auth.uid())
          returning id into v_disp;
        end if;
        if v_good + v_dam + v_nr > 0 then
          insert into public.invoice_handover_return_lines
            (handover_id, invoice_id, product_id, sale_movement_id, good_quantity, damaged_quantity,
             not_returned_quantity, return_movement_id, disposition_id)
          values (v_id, i.id, x.product_id, g.movement_id, v_good, v_dam, v_nr, v_ret, v_disp);
        end if;
      end loop;
    end loop;

    perform public.write_audit_ex('invoices', i.id, 'invoice_goods_returned', null,
      jsonb_build_object('invoice_no', i.invoice_no, 'handover_id', v_id, 'items', v_items),
      'inventory', v_reason, i.store_id);
  end if;

  select jsonb_build_object('success', true, 'replayed', v_replayed, 'handover_id', v_id,
           'invoice_id', i.id, 'invoice_no', i.invoice_no,
           'items', coalesce((select jsonb_agg(jsonb_build_object('product_id', r.product_id, 'name', p.name,
                                                 'good', r.good, 'damaged', r.damaged, 'not_returned', r.not_returned)
                                               order by p.name, r.product_id)
                                from (select rl.product_id, sum(rl.good_quantity)::integer as good,
                                             sum(rl.damaged_quantity)::integer as damaged,
                                             sum(rl.not_returned_quantity)::integer as not_returned
                                        from public.invoice_handover_return_lines rl
                                       where rl.handover_id = v_id group by rl.product_id) r
                                left join public.products p on p.id = r.product_id), '[]'::jsonb))
    into v_res;
  return v_res;
end $function$
$def$;
  c_before_2 constant text := $def$CREATE OR REPLACE FUNCTION public.invoice_goods_status(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 399: the goods of an invoice for its page and its copies (the Owner, 6 Oct
-- 2026). Per product: required (lines, promotion contents and picks),
-- collected and still to collect (invoice_stock_to_deduct: what full payment
-- would take), out with the customer and not yet returned or written off
-- (invoice_goods_out: what "Record items returned" can take back), in the
-- store now, and the promotions it comes through; then every hand-over,
-- "Nothing taken" and return, oldest first, with who recorded it. Only an
-- invoice before full payment ("open") has anything to collect: once paid,
-- completed FOC, cancelled or refunded, "to collect" is 0 and "collected" is
-- what the customer is counted as having (0 after a cancellation that put the
-- goods back; less a refund's returns).
declare
  i public.invoices%rowtype; v_products jsonb; v_history jsonb;
  v_required integer; v_collected integer; v_to_collect integer; v_out integer;
  v_open boolean;
begin
  perform public.inventory_manager_guard('stock');  -- 540 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026: "Stock only")
  select * into i from public.invoices where id = p_invoice_id and deleted_at is null;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(i.store_id) then
    raise exception 'No access to this invoice' using errcode = '42501'; end if;
  v_open := i.status::text in ('draft', 'unpaid', 'partially_paid') and public.invoice_before_full_payment(i.id);

  with req as (select r.item_id as product_id, sum(r.quantity)::integer as qty
                 from public.invoice_required_stock(i.id) r where r.kind = 'product' group by 1),
       tod as (select t.item_id as product_id, sum(t.quantity)::integer as qty
                 from public.invoice_stock_to_deduct(i.id) t where t.kind = 'product' group by 1),
       gone as (select g.product_id, sum(g.quantity)::integer as qty
                  from public.invoice_goods_out(i.id) g group by 1),
       -- 481 (the Owner, 29 Oct 2026, Q2): the units a refund by line paid
       -- back since the last reopening (or the sale), no longer to collect
       -- (invoice_stock_to_deduct takes them off), and those the customer
       -- kept (Not returned).
       refd as (select u.item_id as product_id, sum(u.quantity)::integer as qty
                  from public.invoice_refunded_stock(i.id) u where u.kind = 'product' group by 1),
       kept as (select m.product_id, sum(d.not_returned_quantity)::integer as qty
                  from public.invoice_stock_dispositions d join public.stock_movements m on m.id = d.movement_id
                 where d.invoice_id = i.id group by 1),
       via as (select c.item_id as product_id,
                      jsonb_agg(distinct coalesce(pr.name, 'Promotion'))
                        filter (where it.line_kind::text <> 'product') as names
                 from public.invoice_stock_components c
                 join public.invoice_items it on it.id = c.invoice_item_id
                 left join public.promotions pr on pr.id = it.promotion_id
                where it.invoice_id = i.id and c.kind = 'product' group by 1),
       ids as (select req.product_id from req union select gone.product_id from gone)
  select coalesce(jsonb_agg(jsonb_build_object(
           'product_id', ids.product_id,
           'name', coalesce(p.name, 'Unknown product'),
           'required', coalesce(req.qty, 0),
           -- 481: with a refund by line since the last reopening, what the
           -- customer has (out, or kept as Not returned), up to the lines'.
           'collected', case when coalesce(refd.qty, 0) = 0 then greatest(coalesce(req.qty, 0) - coalesce(tod.qty, 0), 0)
                             else greatest(least(coalesce(req.qty, 0), coalesce(gone.qty, 0) + coalesce(kept.qty, 0)), 0) end,
           'to_collect', case when v_open then coalesce(tod.qty, 0) else 0 end,
           'out', coalesce(gone.qty, 0),
           'in_store', coalesce(si.current_qty, 0),
           'via', coalesce(via.names, '[]'::jsonb))
           order by p.name, ids.product_id), '[]'::jsonb)
    into v_products
    from ids
    left join req on req.product_id = ids.product_id
    left join tod on tod.product_id = ids.product_id
    left join gone on gone.product_id = ids.product_id
    left join refd on refd.product_id = ids.product_id
    left join kept on kept.product_id = ids.product_id
    left join via on via.product_id = ids.product_id
    left join public.products p on p.id = ids.product_id
    left join public.store_inventory si on si.store_id = i.store_id and si.product_id = ids.product_id;

  select coalesce(sum((e->>'required')::integer), 0), coalesce(sum((e->>'collected')::integer), 0),
         coalesce(sum((e->>'to_collect')::integer), 0), coalesce(sum((e->>'out')::integer), 0)
    into v_required, v_collected, v_to_collect, v_out
    from jsonb_array_elements(v_products) e;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', h.id, 'kind', h.kind, 'source', h.source, 'created_at', h.created_at,
           'created_by_name', pf.full_name, 'reason', h.reason,
           'items', case when h.kind = 'return' then
               coalesce((select jsonb_agg(jsonb_build_object('product_id', r.product_id, 'name', p.name,
                                            'good', r.good, 'damaged', r.damaged, 'not_returned', r.not_returned)
                                          order by p.name, r.product_id)
                           from (select rl.product_id, sum(rl.good_quantity)::integer as good,
                                        sum(rl.damaged_quantity)::integer as damaged,
                                        sum(rl.not_returned_quantity)::integer as not_returned
                                   from public.invoice_handover_return_lines rl
                                  where rl.handover_id = h.id group by rl.product_id) r
                           left join public.products p on p.id = r.product_id), '[]'::jsonb)
             else
               coalesce((select jsonb_agg(jsonb_build_object('product_id', l.product_id, 'name', p.name,
                                            'quantity', l.quantity) order by p.name, l.product_id)
                           from public.invoice_handover_lines l
                           left join public.products p on p.id = l.product_id
                          where l.handover_id = h.id), '[]'::jsonb) end)
           order by h.created_at, h.id), '[]'::jsonb)
    into v_history
    from public.invoice_handovers h
    left join public.profiles pf on pf.id = h.created_by
   where h.invoice_id = i.id;

  return jsonb_build_object(
    'invoice_id', i.id, 'invoice_no', i.invoice_no, 'status', i.status, 'store_id', i.store_id,
    'store_name', (select s.name from public.stores s where s.id = i.store_id),
    'open', v_open, 'fulfil_from_warehouse', i.fulfil_warehouse_id is not null,
    'required_total', v_required, 'collected_total', v_collected,
    'to_collect_total', v_to_collect, 'out_total', v_out,
    'can_hand_over', i.status::text in ('unpaid', 'partially_paid') and i.fulfil_warehouse_id is null
                     and v_to_collect > 0,
    'can_record_return', v_open and v_out > 0 and public.is_owner_or_manager(),
    'products', v_products, 'history', v_history);
end $function$
$def$;
  c_before_3 constant text := $def$CREATE OR REPLACE FUNCTION public.invoice_list_goods_out(p_invoice_ids uuid[])
 RETURNS TABLE(invoice_id uuid, quantity integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.inventory_manager_guard('stock');  -- 540 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026: "Stock only")
  -- 399: the Invoices list's "Goods out" badge: of the invoices asked about,
  -- the unpaid and part-paid ones of the caller's stores with goods out with
  -- the customer, and how many.
  select i.id, sum(g.quantity)::integer
    from public.invoices i
    cross join lateral public.invoice_goods_out(i.id) g
   where i.id = any(coalesce(p_invoice_ids, '{}'::uuid[]))
     and cardinality(coalesce(p_invoice_ids, '{}'::uuid[])) <= 1000
     and i.deleted_at is null
     and i.status::text in ('draft', 'unpaid', 'partially_paid')
     and public.invoice_before_full_payment(i.id)
     and public.current_user_role() is not null
     and public.user_has_store_access(i.store_id)
   group by i.id
$function$
$def$;
  c_changed constant text[][] := array[
    ['create_special_docs_for_invoice(uuid)', '1fb8c1a00ef107535a6c08020ee7e78f', 'e4dbc424f10cebfa90de3e56677f3a5e'],
    ['invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)', 'c11c6685d6e0072d96b586471cb1d450', 'e57d1774e2ded552780071d7078f5f89'],
    ['correct_invoice(uuid,jsonb,jsonb,text,uuid)', '095c047730808bd69b87d5623386b52b', '8de40251441091ec08e72499c49adc50'],
    ['cancel_invoice_recorded(uuid,text,uuid)', 'c16247ad7c5f1a80c1a57efdef5a0d7d', 'a09497ec2f1d267592788ac80b0eb008'],
    ['refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)', '7802bc26966f422978e2b764b289944f', '10926314097ca6bdbeeb766d7c2ca58c'],
    ['delete_invoice(uuid,text)', 'b9e3d48b177595858e3966571023b4d0', '9f766c64742ac431c36619f0fdd887ac'],
    ['fulfil_special_doc(text,uuid,uuid,text)', 'cd2ffb8913e60c56e32db817fe1401bb', '3d96a80f7fa97766543dd23340b9f3f6'],
    ['release_special_sale_to_supplier(uuid,uuid,text)', 'c32733b054230d1b6548741c3d78a0ef', '9671a311db74aa9e18fbc4b3a32bba12'],
    ['return_released_special_stock(uuid,uuid,integer,integer,integer,uuid,text,text)', 'e9f575b72cb1c5b8f98500aebbd23b7f', '32dae626d73b4aa8582f2af94c05ff2f'],
    ['invoice_handover_internal(uuid,jsonb,uuid,text,uuid)', '151e5d3d40d83ec45564eac554d4a154', '9c59d949e21038078ad82c66d5e7268f'],
    ['record_invoice_goods_return(uuid,jsonb,text,uuid)', '35f9ffb9b370407a0fda3aabe664faf2', '5df5d911d2c814b1fb70c87c68b3fb91'],
    ['invoice_goods_status(uuid)', '4cef49907477dcc4abc24f72166214ea', '39d072fdd8470e2f32eca57d82f1095b'],
    ['invoice_list_goods_out(uuid[])', '0c8c82d9832995e164d1271fb3e6b2a2', '3f785416c55ebe8d72744a698d28aa1e']
  ];
  c_new_sigs constant text[][] := array[
    ['special_waiting_collected(uuid[])', '49012eecc99ca8128c780479db683a8d'],
    ['invoice_special_collect_internal(uuid,uuid,jsonb)', 'ecedcfb87bbb9cacde6cc3c613d3c48c'],
    ['invoice_special_refund_check(uuid,uuid,boolean,jsonb,jsonb)', 'e788ddb40f0da357c2457cea8b374259'],
    ['invoice_special_goods_block(uuid,text)', 'e7ce1c0f3bf0d489da02efa94c9afa4c'],
    ['invoice_special_kept_check(uuid)', '5f485793a470315a1b837d0bf1d45e8f'],
    ['special_doc_collected(text,uuid)', '99071814bbbea40893e9bf1da0da6ee6'],
    ['invoice_special_lines(uuid)', '41721086125e3568f5a30b406dbf921b'],
    ['invoice_special_goods_out(uuid)', '81e3e1bc5140850dae4bb9fb2f184335']
  ];
  v_path text := current_setting('search_path'); v_def text; v_defs text[] := '{}'; v_n integer; k integer;
  v_backfill integer;
  v_test boolean := coalesce(current_setting('energia.undo547_test_only', true), '') = 'on';
begin
  perform set_config('search_path', 'public', true);
  -- A test file's flag is for this one run.
  perform set_config('energia.undo547_test_only', '', true);
  -- 1. Checks: nothing changes before all pass.
  for k in 1 .. array_length(c_changed, 1) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_changed[k][1]))) is distinct from c_changed[k][3] then
      raise exception 'undo 547: public.% is not 547''s version (undo 547 runs before any older UNDO, 546''s included). Nothing was changed.', c_changed[k][1]; end if;
  end loop;
  for k in 1 .. array_length(c_new_sigs, 1) loop
    if to_regprocedure('public.' || c_new_sigs[k][1]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sigs[k][1]))) <> c_new_sigs[k][2] then
      raise exception 'undo 547: public.% is not 547''s. Nothing was changed.', c_new_sigs[k][1]; end if;
  end loop;
  -- Only the migration's own records (source 'migration') may go; anything staff recorded refuses,
  -- but in a test file's rolled-back run (its flag), which takes everything 547 recorded away.
  if not v_test and (exists (select 1 from public.invoice_special_handover_lines l join public.invoice_handovers h on h.id = l.handover_id
              where h.source <> 'migration')
     or exists (select 1 from public.invoice_special_handover_returns)
     or exists (select 1 from public.invoice_handovers h where h.source = 'migration'
                  and not exists (select 1 from public.invoice_special_handover_lines l where l.handover_id = h.id))
     or exists (select 1 from public.special_sale_returns where why = 'item returned')) then
    raise exception 'undo 547: items have been recorded as collected, delivered or returned since 547; undoing would lose those records (and leave the sales and rentals they raised). Nothing was changed. Decide with the Owner what to keep first.'; end if;
  -- 2. The patched texts put back, each patch exactly as often as 547 put it in.
  v_def := pg_get_functiondef('public.create_special_docs_for_invoice(uuid)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $r$      -- 547 (the Owner, 27 Nov 2026): a line with units recorded as collected before full payment
      -- holds only the sales raised for them: this raises the rest, as many as the line holds beyond
      -- the sales that still count, one Record items returned ended excepted.
      if v_it.line_kind::text = 'special_product'
         and exists (select 1 from public.invoice_special_handover_lines h547 where h547.invoice_item_id = v_it.id) then
        select greatest(coalesce(v_it.quantity, 1), 1) - count(*)::integer into v496_back
          from public.special_sales s547
         where s547.invoice_item_id = v_it.id
           and (s547.status <> 'cancelled'
                or ((s547.warehouse_id is not null or s547.source_store_id is not null) and not coalesce(s547.stock_returned, false))
                or coalesce(s547.cancelled_at, 'infinity') > coalesce(v_inv.reopened_at, '-infinity'))
           and not exists (select 1 from public.invoice_special_handover_returns b547 where b547.ended_sale_id = s547.id);
      end if;
      continue when coalesce(v496_back, 0) <= 0;
$r$, ''))) / length($r$      -- 547 (the Owner, 27 Nov 2026): a line with units recorded as collected before full payment
      -- holds only the sales raised for them: this raises the rest, as many as the line holds beyond
      -- the sales that still count, one Record items returned ended excepted.
      if v_it.line_kind::text = 'special_product'
         and exists (select 1 from public.invoice_special_handover_lines h547 where h547.invoice_item_id = v_it.id) then
        select greatest(coalesce(v_it.quantity, 1), 1) - count(*)::integer into v496_back
          from public.special_sales s547
         where s547.invoice_item_id = v_it.id
           and (s547.status <> 'cancelled'
                or ((s547.warehouse_id is not null or s547.source_store_id is not null) and not coalesce(s547.stock_returned, false))
                or coalesce(s547.cancelled_at, 'infinity') > coalesce(v_inv.reopened_at, '-infinity'))
           and not exists (select 1 from public.invoice_special_handover_returns b547 where b547.ended_sale_id = s547.id);
      end if;
      continue when coalesce(v496_back, 0) <= 0;
$r$);
  if v_n <> 1 then raise exception 'undo 547: patch 1 of public.create_special_docs_for_invoice(uuid) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $r$      -- 547 (the Owner, 27 Nov 2026): a line with units recorded as collected before full payment
      -- holds only the sales raised for them: this raises the rest, as many as the line holds beyond
      -- the sales that still count, one Record items returned ended excepted.
      if v_it.line_kind::text = 'special_product'
         and exists (select 1 from public.invoice_special_handover_lines h547 where h547.invoice_item_id = v_it.id) then
        select greatest(coalesce(v_it.quantity, 1), 1) - count(*)::integer into v496_back
          from public.special_sales s547
         where s547.invoice_item_id = v_it.id
           and (s547.status <> 'cancelled'
                or ((s547.warehouse_id is not null or s547.source_store_id is not null) and not coalesce(s547.stock_returned, false))
                or coalesce(s547.cancelled_at, 'infinity') > coalesce(v_inv.reopened_at, '-infinity'))
           and not exists (select 1 from public.invoice_special_handover_returns b547 where b547.ended_sale_id = s547.id);
      end if;
      continue when coalesce(v496_back, 0) <= 0;
$r$, $a$      continue when coalesce(v496_back, 0) <= 0;
$a$);
  v_n := (length(v_def) - length(replace(v_def, $r$      -- 547 (the Owner, 27 Nov 2026): a line whose rental was collected before full payment: the
      -- units that still count, one Record items returned ended excepted, and the rest raised; the
      -- rental raised early is paid now.
      if exists (select 1 from public.invoice_special_handover_lines h547 where h547.invoice_item_id = v_it.id) then
        select coalesce(sum(x547.quantity), 0)::integer into v458_have
          from public.rentals x547
         where x547.invoice_item_id = v_it.id
           and (x547.status <> 'cancelled' or coalesce(x547.cancelled_at, 'infinity') > coalesce(v_inv.reopened_at, '-infinity')
                or ((x547.warehouse_id is not null or x547.source_store_id is not null) and not coalesce(x547.stock_returned, false)))
           and not exists (select 1 from public.invoice_special_handover_returns b547 where b547.ended_rental_id = x547.id);
        update public.rentals x547 set paid_at = v_inv.paid_at
         where x547.invoice_item_id = v_it.id and x547.paid_at is null and v_inv.paid_at is not null
           and x547.status <> 'cancelled';
        v458_cnt := 0;
      end if;
      if v458_cnt > 0 and (v458_have >= v458_units or not exists (
$r$, ''))) / length($r$      -- 547 (the Owner, 27 Nov 2026): a line whose rental was collected before full payment: the
      -- units that still count, one Record items returned ended excepted, and the rest raised; the
      -- rental raised early is paid now.
      if exists (select 1 from public.invoice_special_handover_lines h547 where h547.invoice_item_id = v_it.id) then
        select coalesce(sum(x547.quantity), 0)::integer into v458_have
          from public.rentals x547
         where x547.invoice_item_id = v_it.id
           and (x547.status <> 'cancelled' or coalesce(x547.cancelled_at, 'infinity') > coalesce(v_inv.reopened_at, '-infinity')
                or ((x547.warehouse_id is not null or x547.source_store_id is not null) and not coalesce(x547.stock_returned, false)))
           and not exists (select 1 from public.invoice_special_handover_returns b547 where b547.ended_rental_id = x547.id);
        update public.rentals x547 set paid_at = v_inv.paid_at
         where x547.invoice_item_id = v_it.id and x547.paid_at is null and v_inv.paid_at is not null
           and x547.status <> 'cancelled';
        v458_cnt := 0;
      end if;
      if v458_cnt > 0 and (v458_have >= v458_units or not exists (
$r$);
  if v_n <> 1 then raise exception 'undo 547: patch 2 of public.create_special_docs_for_invoice(uuid) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $r$      -- 547 (the Owner, 27 Nov 2026): a line whose rental was collected before full payment: the
      -- units that still count, one Record items returned ended excepted, and the rest raised; the
      -- rental raised early is paid now.
      if exists (select 1 from public.invoice_special_handover_lines h547 where h547.invoice_item_id = v_it.id) then
        select coalesce(sum(x547.quantity), 0)::integer into v458_have
          from public.rentals x547
         where x547.invoice_item_id = v_it.id
           and (x547.status <> 'cancelled' or coalesce(x547.cancelled_at, 'infinity') > coalesce(v_inv.reopened_at, '-infinity')
                or ((x547.warehouse_id is not null or x547.source_store_id is not null) and not coalesce(x547.stock_returned, false)))
           and not exists (select 1 from public.invoice_special_handover_returns b547 where b547.ended_rental_id = x547.id);
        update public.rentals x547 set paid_at = v_inv.paid_at
         where x547.invoice_item_id = v_it.id and x547.paid_at is null and v_inv.paid_at is not null
           and x547.status <> 'cancelled';
        v458_cnt := 0;
      end if;
      if v458_cnt > 0 and (v458_have >= v458_units or not exists (
$r$, $a$      if v458_cnt > 0 and (v458_have >= v458_units or not exists (
$a$);
  v_defs := v_defs || v_def;
  v_def := pg_get_functiondef('public.invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $r$                order by public.special_doc_collected('special_sale', s.id), 10, s.sale_no desc  -- 547: what the customer has goes last
$r$, ''))) / length($r$                order by public.special_doc_collected('special_sale', s.id), 10, s.sale_no desc  -- 547: what the customer has goes last
$r$);
  if v_n <> 1 then raise exception 'undo 547: patch 1 of public.invoice_special_sales_follow_lines(uuid,jsonb,text,uuid) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $r$                order by public.special_doc_collected('special_sale', s.id), 10, s.sale_no desc  -- 547: what the customer has goes last
$r$, $a$                order by 10, s.sale_no desc
$a$);
  v_n := (length(v_def) - length(replace(v_def, $r$                        -- 547: before full payment, a line with units recorded as collected is
                        -- raised by the payment (create_special_docs_for_invoice raises its rest).
                        or not exists (select 1 from public.invoice_special_handover_lines h547 where h547.invoice_item_id = v_line)
                           and exists (select 1 from public.special_sales s
                                    where s.invoice_item_id = v_line
$r$, ''))) / length($r$                        -- 547: before full payment, a line with units recorded as collected is
                        -- raised by the payment (create_special_docs_for_invoice raises its rest).
                        or not exists (select 1 from public.invoice_special_handover_lines h547 where h547.invoice_item_id = v_line)
                           and exists (select 1 from public.special_sales s
                                    where s.invoice_item_id = v_line
$r$);
  if v_n <> 1 then raise exception 'undo 547: patch 2 of public.invoice_special_sales_follow_lines(uuid,jsonb,text,uuid) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $r$                        -- 547: before full payment, a line with units recorded as collected is
                        -- raised by the payment (create_special_docs_for_invoice raises its rest).
                        or not exists (select 1 from public.invoice_special_handover_lines h547 where h547.invoice_item_id = v_line)
                           and exists (select 1 from public.special_sales s
                                    where s.invoice_item_id = v_line
$r$, $a$                        or exists (select 1 from public.special_sales s
                                    where s.invoice_item_id = v_line
$a$);
  v_defs := v_defs || v_def;
  v_def := pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $r$if v399_open then perform public.invoice_goods_kept_check(i.id); end if;
 perform public.invoice_special_kept_check(i.id);  -- 547 (the Owner, 27 Nov 2026, answer 8): paid or not
$r$, ''))) / length($r$if v399_open then perform public.invoice_goods_kept_check(i.id); end if;
 perform public.invoice_special_kept_check(i.id);  -- 547 (the Owner, 27 Nov 2026, answer 8): paid or not
$r$);
  if v_n <> 2 then raise exception 'undo 547: patch 1 of public.correct_invoice(uuid,jsonb,jsonb,text,uuid) found % times, not 2. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $r$if v399_open then perform public.invoice_goods_kept_check(i.id); end if;
 perform public.invoice_special_kept_check(i.id);  -- 547 (the Owner, 27 Nov 2026, answer 8): paid or not
$r$, $a$if v399_open then perform public.invoice_goods_kept_check(i.id); end if;
$a$);
  v_defs := v_defs || v_def;
  v_def := pg_get_functiondef('public.cancel_invoice_recorded(uuid,text,uuid)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $r$ -- 547 (the Owner, 27 Nov 2026, answer 8): not while the customer has a special, consignment or
 -- rental item recorded as collected or delivered and not recorded as returned.
 perform public.invoice_special_goods_block(i.id,'cancel');
 perform public.assert_invoice_credit_source_evidence(i.id);
$r$, ''))) / length($r$ -- 547 (the Owner, 27 Nov 2026, answer 8): not while the customer has a special, consignment or
 -- rental item recorded as collected or delivered and not recorded as returned.
 perform public.invoice_special_goods_block(i.id,'cancel');
 perform public.assert_invoice_credit_source_evidence(i.id);
$r$);
  if v_n <> 1 then raise exception 'undo 547: patch 1 of public.cancel_invoice_recorded(uuid,text,uuid) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $r$ -- 547 (the Owner, 27 Nov 2026, answer 8): not while the customer has a special, consignment or
 -- rental item recorded as collected or delivered and not recorded as returned.
 perform public.invoice_special_goods_block(i.id,'cancel');
 perform public.assert_invoice_credit_source_evidence(i.id);
$r$, $a$ perform public.assert_invoice_credit_source_evidence(i.id);
$a$);
  v_defs := v_defs || v_def;
  v_def := pg_get_functiondef('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $r$   -- 547 (the Owner, 27 Nov 2026, answer 8): not a special, consignment or rental item the customer
   -- has (recorded as collected or delivered, not recorded as returned).
   if it.id is not null and it.line_kind::text in ('special_product','rental') then
     perform public.invoice_special_refund_check(i.id,it.id,v_amount>=greatest(v_line_paid-v_refunded,0),p_lines,p_stock);
   end if;
   if it.id is not null and it.line_kind::text='special_product' then
    declare o496$r$, ''))) / length($r$   -- 547 (the Owner, 27 Nov 2026, answer 8): not a special, consignment or rental item the customer
   -- has (recorded as collected or delivered, not recorded as returned).
   if it.id is not null and it.line_kind::text in ('special_product','rental') then
     perform public.invoice_special_refund_check(i.id,it.id,v_amount>=greatest(v_line_paid-v_refunded,0),p_lines,p_stock);
   end if;
   if it.id is not null and it.line_kind::text='special_product' then
    declare o496$r$);
  if v_n <> 1 then raise exception 'undo 547: patch 1 of public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $r$   -- 547 (the Owner, 27 Nov 2026, answer 8): not a special, consignment or rental item the customer
   -- has (recorded as collected or delivered, not recorded as returned).
   if it.id is not null and it.line_kind::text in ('special_product','rental') then
     perform public.invoice_special_refund_check(i.id,it.id,v_amount>=greatest(v_line_paid-v_refunded,0),p_lines,p_stock);
   end if;
   if it.id is not null and it.line_kind::text='special_product' then
    declare o496$r$, $a$   if it.id is not null and it.line_kind::text='special_product' then
    declare o496$a$);
  v_n := (length(v_def) - length(replace(v_def, $r$ -- 547: and a refund that closes the invoice, not while the customer has one.
 if (select v.status from public.invoices v where v.id=i.id) in ('refunded','cancelled') then
   perform public.invoice_special_goods_block(i.id,'refund'); end if;
 perform public.settle_waiting_special_docs_on_refund(i.id,p_lines,p_reason);
$r$, ''))) / length($r$ -- 547: and a refund that closes the invoice, not while the customer has one.
 if (select v.status from public.invoices v where v.id=i.id) in ('refunded','cancelled') then
   perform public.invoice_special_goods_block(i.id,'refund'); end if;
 perform public.settle_waiting_special_docs_on_refund(i.id,p_lines,p_reason);
$r$);
  if v_n <> 1 then raise exception 'undo 547: patch 2 of public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $r$ -- 547: and a refund that closes the invoice, not while the customer has one.
 if (select v.status from public.invoices v where v.id=i.id) in ('refunded','cancelled') then
   perform public.invoice_special_goods_block(i.id,'refund'); end if;
 perform public.settle_waiting_special_docs_on_refund(i.id,p_lines,p_reason);
$r$, $a$ perform public.settle_waiting_special_docs_on_refund(i.id,p_lines,p_reason);
$a$);
  v_defs := v_defs || v_def;
  v_def := pg_get_functiondef('public.delete_invoice(uuid,text)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $r$  -- 547 (the Owner, 27 Nov 2026, answer 8): and special, consignment and rental items recorded as
  -- collected or delivered.
  perform public.invoice_special_goods_block(p_invoice_id, 'delete');
  update public.invoices set deleted_at = now() where id = p_invoice_id;
$r$, ''))) / length($r$  -- 547 (the Owner, 27 Nov 2026, answer 8): and special, consignment and rental items recorded as
  -- collected or delivered.
  perform public.invoice_special_goods_block(p_invoice_id, 'delete');
  update public.invoices set deleted_at = now() where id = p_invoice_id;
$r$);
  if v_n <> 1 then raise exception 'undo 547: patch 1 of public.delete_invoice(uuid,text) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $r$  -- 547 (the Owner, 27 Nov 2026, answer 8): and special, consignment and rental items recorded as
  -- collected or delivered.
  perform public.invoice_special_goods_block(p_invoice_id, 'delete');
  update public.invoices set deleted_at = now() where id = p_invoice_id;
$r$, $a$  update public.invoices set deleted_at = now() where id = p_invoice_id;
$a$);
  v_defs := v_defs || v_def;
  v_def := pg_get_functiondef('public.fulfil_special_doc(text,uuid,uuid,text)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $r$     where x.id = p_doc_id and i.status in ('unpaid', 'partially_paid')
       -- 547 (the Owner, 27 Nov 2026, answer 7): unless the customer has it already.
       and not public.special_doc_collected(p_doc_kind, p_doc_id);
$r$, ''))) / length($r$     where x.id = p_doc_id and i.status in ('unpaid', 'partially_paid')
       -- 547 (the Owner, 27 Nov 2026, answer 7): unless the customer has it already.
       and not public.special_doc_collected(p_doc_kind, p_doc_id);
$r$);
  if v_n <> 2 then raise exception 'undo 547: patch 1 of public.fulfil_special_doc(text,uuid,uuid,text) found % times, not 2. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $r$     where x.id = p_doc_id and i.status in ('unpaid', 'partially_paid')
       -- 547 (the Owner, 27 Nov 2026, answer 7): unless the customer has it already.
       and not public.special_doc_collected(p_doc_kind, p_doc_id);
$r$, $a$     where x.id = p_doc_id and i.status in ('unpaid', 'partially_paid');
$a$);
  v_defs := v_defs || v_def;
  v_def := pg_get_functiondef('public.release_special_sale_to_supplier(uuid,uuid,text)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $r$   where i.id = v_sale.invoice_id and i.status in ('unpaid', 'partially_paid')
     -- 547 (the Owner, 27 Nov 2026, answer 7): unless the customer has it already (Delivered).
     and not public.special_doc_collected('special_sale', p_sale_id);
$r$, ''))) / length($r$   where i.id = v_sale.invoice_id and i.status in ('unpaid', 'partially_paid')
     -- 547 (the Owner, 27 Nov 2026, answer 7): unless the customer has it already (Delivered).
     and not public.special_doc_collected('special_sale', p_sale_id);
$r$);
  if v_n <> 1 then raise exception 'undo 547: patch 1 of public.release_special_sale_to_supplier(uuid,uuid,text) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $r$   where i.id = v_sale.invoice_id and i.status in ('unpaid', 'partially_paid')
     -- 547 (the Owner, 27 Nov 2026, answer 7): unless the customer has it already (Delivered).
     and not public.special_doc_collected('special_sale', p_sale_id);
$r$, $a$   where i.id = v_sale.invoice_id and i.status in ('unpaid', 'partially_paid');
$a$);
  v_defs := v_defs || v_def;
  v_def := pg_get_functiondef('public.return_released_special_stock(uuid,uuid,integer,integer,integer,uuid,text,text)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $r$  if p_why is null or p_why not in ('refunded', 'invoice cancelled', 'line corrected', 'item returned') then  -- 497; 547: Record items returned
$r$, ''))) / length($r$  if p_why is null or p_why not in ('refunded', 'invoice cancelled', 'line corrected', 'item returned') then  -- 497; 547: Record items returned
$r$);
  if v_n <> 1 then raise exception 'undo 547: patch 1 of public.return_released_special_stock(uuid,uuid,integer,integer,integer,uuid,text,text) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $r$  if p_why is null or p_why not in ('refunded', 'invoice cancelled', 'line corrected', 'item returned') then  -- 497; 547: Record items returned
$r$, $a$  if p_why is null or p_why not in ('refunded', 'invoice cancelled', 'line corrected') then  -- 497
$a$);
  v_defs := v_defs || v_def;
  foreach v_def in array v_defs loop execute v_def; end loop;
  execute c_before_0;
  execute c_before_1;
  execute c_before_2;
  execute c_before_3;
  -- 3. What 547 added goes, its own records of the items released before it included.
  drop function public.special_waiting_collected(uuid[]);
  drop function public.invoice_special_collect_internal(uuid,uuid,jsonb);
  drop function public.invoice_special_refund_check(uuid,uuid,boolean,jsonb,jsonb);
  drop function public.invoice_special_goods_block(uuid,text);
  drop function public.invoice_special_kept_check(uuid);
  drop function public.special_doc_collected(text,uuid);
  drop function public.invoice_special_lines(uuid);
  drop function public.invoice_special_goods_out(uuid);
  drop table public.invoice_special_handover_returns;
  drop table public.invoice_special_handover_lines;
  if v_test then delete from public.special_sale_returns where why = 'item returned'; end if;
  delete from public.invoice_handovers where source = 'migration';
  get diagnostics v_backfill = row_count;
  alter table public.invoice_handovers drop constraint invoice_handovers_source_check;
  alter table public.invoice_handovers add constraint invoice_handovers_source_check
    check (source = any (array['payment'::text, 'button'::text, 'return'::text]));
  alter table public.special_sale_returns drop constraint special_sale_returns_why_check;
  alter table public.special_sale_returns add constraint special_sale_returns_why_check
    check (why = any (array['refunded'::text, 'invoice cancelled'::text, 'line corrected'::text]));
  -- 4. Checks after.
  for k in 1 .. array_length(c_changed, 1) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_changed[k][1]))) is distinct from c_changed[k][2] then
      raise exception 'undo 547: public.% is not as before 547 after putting it back', c_changed[k][1]; end if;
  end loop;
  raise notice 'undo 547: % record(s) the migration made of items released before it were removed.', v_backfill;
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $undo$;
