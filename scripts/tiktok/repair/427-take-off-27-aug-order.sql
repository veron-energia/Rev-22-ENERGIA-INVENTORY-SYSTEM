-- 427 repair: take the stock off for the TikTok order of 28 August 2026
-- (Singapore time; the Owner's "27 August" order in Q20).
--
-- TikTok settled (paid out) one order placed on 28 Aug 2026 (S$256.51,
-- settled 3 Sep 2026), at Energia Rev 22 (Adelphi). TikTok's own
-- file dates it 28 Aug 2026; the app stores it as 27 Aug 16:00 UTC, which is
-- why the audit and Q20 call it the 27 August order. No order file
-- ever brought it in, so its items never left Adelphi's stock. The Owner said
-- on 9 Oct 2026 (Q20): take the stock off for it, after checking it against
-- the paused September stock count.
--
-- The app has no record of what the order held: TikTok Seller Center does.
-- So this takes the order's lines as they are in Seller Center's order export
-- and imports that one order through the TikTok Import page's own functions
-- (stage_tiktok_orders, then confirm_tiktok_batch), as the Owner named below,
-- in one statement. Stock History then shows each item taken off at Adelphi
-- as "TikTok import Seller Center order <the order> ... — order <the
-- order>", the import list shows the file, both are audited, and the
-- settlement line is matched to its order (it leaves the Dashboard's
-- "Settled with no imported order").
--
-- Before running, in the same session:
--   0. Give the ids. They are not in this file (the repository is public):
--      the hand-off lists them.
--        select set_config('repair427.actor', '<the Owner''s profile id>', false),
--               set_config('repair427.store', '<Adelphi''s store id>', false),
--               set_config('repair427.aug_row', '<the settlement line id>', false),
--               set_config('repair427.aug_order', '<the TikTok order id>', false);
--   1. Give the order's lines from Seller Center (the columns of the order
--      export; the order id is filled in here):
--        select set_config('repair427.order_lines', '[
--          {"seller_sku": "P00000", "quantity": 1, "order_status": "Completed",
--           "product_name": "...", "sku_subtotal_after": "0.00",
--           "created_time": "28/08/2026 12:00:00"}
--        ]', false);
--      (Paste Seller Center's own Created Time; the time above is only an
--      example.)
--   2. Run this once: it changes nothing yet. It checks the lines and prints,
--      for each item, Adelphi's stock now and the stock adjustments made at
--      Adelphi since 27 Aug (a day before the order, to be safe; the
--      September count's included). Check them against the paused September
--      count: if the count already took these items off, they must not be
--      taken off again, and this is not run (the line can be reviewed as
--      needing no stock instead, like the July ones).
--   3. With the Owner's go-ahead:
--        select set_config('repair427.checked_against_count', 'yes', false);
--      and run this again, as the database owner (the SQL editor, the MCP
--      execute_sql tool, or psql as postgres). It is one statement, so it is
--      atomic.
--   The settings last for the session only: where each run is a session of
--   its own (the MCP execute_sql tool, the SQL editor), send the set_config
--   lines and this file's text together, in one run.
-- It acts only while the settlement line given is as read on 10 Oct 2026
-- (the order given, S$256.51, ordered on 28 Aug 2026 Singapore time, at the
-- store given) and still waiting for its order, the actor given is an active
-- Owner, no file holds the order, every line's SKU is mapped to an item at
-- Adelphi, and Adelphi has the stock; otherwise it changes nothing and says
-- why. A second run, once done, changes nothing. It prints SKUs, ids,
-- quantities and amounts only, never a name.
--
-- repair427.actor is the Owner account the import is recorded under
-- (uploaded_by, confirmed_by, the stock movements and the audit rows), as in
-- 414's repair.
--
-- To check afterwards (ids and amounts only):
--   select r.match_status, r.matched_order_id from public.tiktok_settlement_rows r
--    where r.id = '<the settlement line id>';      -- matched, <the order>
--   select m.product_id, m.quantity, m.created_at from public.stock_movements m
--    where m.notes like '%order <the order>%';

do $repair$
declare
  c_amount constant numeric := 256.51;
  c_day    constant date := date '2026-08-28';  -- the order's day, Singapore time
  c_since  constant timestamptz := timestamptz '2026-08-27 00:00:00+08';  -- a day before the order (28 Aug), to be safe
  -- The ids, given in the session (the hand-off lists them).
  c_actor uuid; c_store uuid; c_row uuid; c_order text; c_file text;
  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_lines jsonb; v_checked text := coalesce(current_setting('repair427.checked_against_count', true), '');
  v_rows jsonb := '[]'; v_line jsonb; r record; s record; v_eval record; v_note text; v_short text; v_low text;
  v_have int; v_adj text; v_batch uuid; v_res jsonb; v_units int := 0;
begin
  perform set_config('search_path', 'public', true);
  -- The Import page's functions, as read on 10 Oct 2026, and 427.
  for r in select * from (values
    ('stage_tiktok_orders(uuid,text,text,jsonb)', '165118c2a659e3590f84457e9056a307'),
    ('confirm_tiktok_batch(uuid,jsonb,boolean,text)', 'f7236b71c8df5d981cbf64e6298fa052'),
    ('tiktok_evaluate(uuid,text,text,integer,text,boolean)', '358bf625b34bd1e97586b722df40184a'),
    ('tiktok_projected_short(uuid,text,uuid,integer)', '81a5387a9e046dc431d4711a77aa2ee7'),
    ('apply_tiktok_stock_delta(uuid,text,uuid,integer,uuid,text,text,text)', 'e3c9f3c5f2b49fd580b926653ed7e1ac'),
    ('rematch_tiktok_settlements(uuid,text)', 'b50a3627d49347019b81b88b75b4528e'),
    ('trg_tiktok_state_rematch()', '9ce866c8a8bc93d3983f0d6e07a6b7a6'),
    ('dashboard_alerts_summary()', '2b632d0dcc23b82c6ef4e1438271debf')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '427 repair: public.% is missing or not the version read on 10 Oct 2026 (is 427 in?); nothing was changed', r.fn; end if;
  end loop;

  -- The ids.
  begin
    c_actor := nullif(btrim(coalesce(current_setting('repair427.actor', true), '')), '')::uuid;
    c_store := nullif(btrim(coalesce(current_setting('repair427.store', true), '')), '')::uuid;
    c_row   := nullif(btrim(coalesce(current_setting('repair427.aug_row', true), '')), '')::uuid;
  exception when others then
    raise exception '427 repair: repair427.actor, repair427.store and repair427.aug_row must be ids; nothing was changed'; end;
  c_order := nullif(btrim(coalesce(current_setting('repair427.aug_order', true), '')), '');
  if c_actor is null or c_store is null or c_row is null or c_order is null then
    raise exception '427 repair: give the ids first (repair427.actor, repair427.store, repair427.aug_row, repair427.aug_order; the hand-off lists them); nothing was changed'; end if;
  if not exists (select 1 from public.profiles p where p.id = c_actor and p.role = 'owner' and p.is_active and p.deleted_at is null) then
    raise exception '427 repair: repair427.actor is not an active Owner; nothing was changed'; end if;
  c_file := format('Seller Center order %s (28 Aug 2026), imported by the 427 repair', c_order);

  -- The settlement line, as read on 10 Oct 2026.
  select * into s from public.tiktok_settlement_rows t where t.id = c_row;
  if not found or s.store_id <> c_store or s.order_id is distinct from c_order or s.settlement_amount is distinct from c_amount
     or not s.confirmed or not s.is_current or s.txn_class is distinct from 'order'
     or (s.order_created_time at time zone 'Asia/Singapore')::date is distinct from c_day then
    raise exception '427 repair: settlement line % is not as given or as read on 10 Oct 2026 (missing, changed or superseded); nothing was changed', c_row; end if;

  -- A second run: the order is in and the line matched; leave it.
  if s.match_status = 'matched' then
    if exists (select 1 from public.tiktok_order_state st where st.store_id = c_store and st.order_id = c_order) then
      raise notice '427 repair: already done (order % is imported and its settlement matched); nothing changed', c_order;
      perform set_config('search_path', v_path, true);
      return;
    end if;
    raise exception '427 repair: the settlement line is matched but the order holds no stock record; nothing was changed. Re-read it with the Owner.'; end if;
  if s.match_status <> 'pending' then
    raise exception '427 repair: the settlement line is %, not waiting for its order; nothing was changed', s.match_status; end if;
  if exists (select 1 from public.tiktok_settlement_reviews v where v.settlement_row_id = c_row) then
    raise exception '427 repair: the settlement line was reviewed as needing no stock taken off; nothing was changed. Re-read it with the Owner.'; end if;
  if exists (select 1 from public.tiktok_order_rows o join public.tiktok_import_batches b on b.id = o.batch_id
              where o.store_id = c_store and o.order_id = c_order and b.deleted_at is null) then
    raise exception '427 repair: a file already holds order % (staged or confirmed); confirm it on the TikTok Import page instead. Nothing was changed.', c_order; end if;

  -- The order's lines, from Seller Center.
  begin
    v_lines := nullif(btrim(coalesce(current_setting('repair427.order_lines', true), '')), '')::jsonb;
  exception when others then
    raise exception '427 repair: repair427.order_lines is not valid JSON; nothing was changed'; end;
  if v_lines is null or jsonb_typeof(v_lines) <> 'array' or jsonb_array_length(v_lines) = 0 then
    raise exception '427 repair: give the order''s lines from Seller Center first: select set_config(''repair427.order_lines'', ''[{"seller_sku": ..., "quantity": ..., "order_status": ...}]'', false); nothing was changed'; end if;
  if jsonb_array_length(v_lines) > 50 then
    raise exception '427 repair: % lines is more than one order holds; nothing was changed', jsonb_array_length(v_lines); end if;
  for v_line in select * from jsonb_array_elements(v_lines) loop
    if jsonb_typeof(v_line) <> 'object' or nullif(btrim(coalesce(v_line->>'seller_sku', '')), '') is null
       or coalesce(v_line->>'quantity', '') !~ '^[1-9][0-9]{0,3}$' or nullif(btrim(coalesce(v_line->>'order_status', '')), '') is null then
      raise exception '427 repair: each line needs a seller_sku, a whole quantity of 1 or more, and an order_status (%); nothing was changed', v_line; end if;
    if v_line ? 'order_id' and v_line->>'order_id' is distinct from c_order then
      raise exception '427 repair: a line names order %, not %; nothing was changed', v_line->>'order_id', c_order; end if;
    v_rows := v_rows || jsonb_build_array(v_line || jsonb_build_object('order_id', c_order));
  end loop;
  if (select count(distinct x->>'seller_sku') from jsonb_array_elements(v_rows) x) <> jsonb_array_length(v_rows) then
    raise exception '427 repair: a SKU is given twice; give each SKU once, with its whole quantity; nothing was changed'; end if;

  -- Each line as the Import page would stage it, and Adelphi's stock now.
  for v_line in select * from jsonb_array_elements(v_rows) loop
    select * into v_eval from public.tiktok_evaluate(c_store, c_order, v_line->>'seller_sku', (v_line->>'quantity')::int,
                                                     v_line->>'order_status', false);
    if v_eval.staging_status = 'Negative Stock Warning' then
      v_low := concat_ws(', ', v_low, v_line->>'seller_sku');
    elsif v_eval.staging_status is distinct from 'New — Will Deduct' then
      v_short := concat_ws('; ', v_short, format('%s: %s', v_line->>'seller_sku', v_eval.staging_status));
      continue;
    end if;
    v_note := format('%s x %s -> %s %s', v_line->>'seller_sku', v_line->>'quantity', v_eval.matched_kind, v_eval.matched_id);
    if v_eval.matched_kind = 'product' then
      select coalesce(max(si.current_qty), 0) into v_have from public.store_inventory si
       where si.store_id = c_store and si.product_id = v_eval.matched_id;
      select format('%s adjustment(s) since 27 Aug, net %s', count(*),
                    coalesce(sum(case when m.to_store_id = c_store then m.quantity else -m.quantity end), 0)) into v_adj
        from public.stock_movements m
       where m.product_id = v_eval.matched_id and m.movement_type = 'inventory_adjustment'
         and (m.from_store_id = c_store or m.to_store_id = c_store) and m.created_at >= c_since;
      v_note := v_note || format(': Adelphi holds %s now; %s', v_have, v_adj);
    elsif v_eval.matched_kind = 'promotion' then
      v_note := v_note || ': takes off ' || coalesce((select string_agg(format('%s %s x %s (Adelphi holds %s)', c.kind, c.item_id, c.quantity,
                   coalesce(case when c.kind = 'product' then (select si.current_qty from public.store_inventory si where si.store_id = c_store and si.product_id = c.item_id)
                                 else (select vs.current_qty from public.voucher_store_stock vs where vs.store_id = c_store and vs.voucher_id = c.item_id) end, 0)), ', ')
                 from public.promotion_stock_items(v_eval.matched_id, (v_line->>'quantity')::int) c), 'nothing');
    else
      v_note := v_note || format(': Adelphi holds %s now', coalesce((select vs.current_qty from public.voucher_store_stock vs
                                                                       where vs.store_id = c_store and vs.voucher_id = v_eval.matched_id), 0));
    end if;
    raise notice '427 repair: %', v_note;
  end loop;
  if v_short is not null then
    raise exception '427 repair: these lines would not take stock off as given (%). Map an unmatched SKU on the TikTok Import page, or a status in its status settings, and run again; nothing was changed', v_short; end if;
  if v_low is not null then
    raise exception '427 repair: Adelphi does not hold enough of % to take it off; recount the shelf with the Owner. Nothing was changed', v_low; end if;
  if v_checked is distinct from 'yes' then
    raise notice '427 repair: checked; nothing changed. Compare the stock above with the paused September count. If the items are to be taken off, select set_config(''repair427.checked_against_count'', ''yes'', false) and run again';
    perform set_config('search_path', v_path, true);
    return;
  end if;
  select string_agg(x->>'seller_sku', ', ') into v_short from jsonb_array_elements(v_rows) x,
         lateral public.tiktok_evaluate(c_store, c_order, x->>'seller_sku', (x->>'quantity')::int, x->>'order_status', false) e
   where public.tiktok_projected_short(c_store, e.matched_kind, e.matched_id, e.stock_delta);
  if v_short is not null then
    raise exception '427 repair: Adelphi does not hold enough of % to take it off; recount the shelf with the Owner. Nothing was changed', v_short; end if;

  -- The import, as the Owner, through the Import page's functions.
  perform set_config('request.jwt.claims', json_build_object('sub', c_actor, 'role', 'authenticated')::text, true);
  v_batch := public.stage_tiktok_orders(c_store, c_file, 'repair 427', v_rows);
  v_res := public.confirm_tiktok_batch(v_batch, null, false, null);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  select coalesce(sum(o.stock_delta), 0) into v_units from public.tiktok_order_rows o where o.batch_id = v_batch and o.confirmed;
  if (select t.match_status from public.tiktok_settlement_rows t where t.id = c_row) is distinct from 'matched'
     or (v_res->>'applied')::int <> jsonb_array_length(v_rows) or (v_res->>'skipped')::int <> 0 then
    raise exception '427 repair: the import did not go as checked (%); nothing was changed', v_res; end if;
  raise notice '427 repair: order % imported (batch %): % line(s), % unit(s) taken off at Adelphi; its settlement line is matched',
    c_order, v_batch, v_res->>'applied', v_units;
  perform set_config('search_path', v_path, true);
end $repair$;
