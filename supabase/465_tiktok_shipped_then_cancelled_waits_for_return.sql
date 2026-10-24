-- 465_tiktok_shipped_then_cancelled_waits_for_return.sql
--
-- A TIKTOK ORDER SHIPPED AND THEN CANCELLED BEFORE THE IMPORTER FIRST SAW IT
-- IS TAKEN OFF STOCK AND WAITS FOR ITS PHYSICAL RETURN, AS ONE CANCELLED
-- AFTER A SHIPPED IMPORT DOES
--
-- WHAT WAS WRONG / WHY
--
--   The import decides what a row does to stock in tiktok_evaluate (65),
--   called by stage_tiktok_orders (the preview), refresh_tiktok_staging and,
--   twice, confirm_tiktok_batch (which applies it). A row's status maps to
--   deduct / return / none (tiktok_status_mappings). Whether the parcel had
--   left the store was known only from tiktok_order_state.was_shipped, which
--   confirm_tiktok_batch sets when it confirms a row whose STATUS marks
--   shipped (Shipped, In Transit, Delivered, Completed). So:
--   * Seen first as Shipped (deducted, was_shipped), later Canceled: "Awaiting
--     Physical Return", no automatic return; confirm_tiktok_batch opens a
--     tiktok_physical_returns row and staff resolve it as Stock Return or No
--     Stock Return (resolve_tiktok_physical_return). Right.
--   * Seen first already Canceled (or Returned / Refunded), though TikTok's
--     row gives it a shipped time: no state row, so tiktok_evaluate's
--     "cancellation after shipment" branch (v_prev > 0 and v_shipped) does not
--     apply; the target is 0, the delta 0: "Already Imported". confirm then
--     writes state deducted_qty 0, was_shipped false, and no physical return.
--     The parcel that left the store is never taken off and never expected
--     back.
--   * Seen first as To Ship (deducted, not shipped), then shipped and
--     cancelled between two imports: the next import's Canceled row is
--     "Updated — Stock Return" and puts the stock back automatically, though
--     the parcel is with the courier or the buyer.
--   Found on 24 Oct 2026 in an October shelf count: one TikTok order (1 x a
--   S$0.01 product) packed at a store, shipped by courier on 13 Oct 2026 and
--   cancelled on 19 Oct, was first imported on 24 Oct already Canceled (and
--   again in the next day's file): deducted 0, was_shipped false, no
--   physical return.
--
--   Two more faults on the path this reuses:
--   * After a physical return is resolved as No Stock Return the order keeps
--     its deduction, so every later file that still lists the cancelled row
--     (TikTok's "All order" export does, for weeks) was "Awaiting Physical
--     Return" again and its confirm opened ANOTHER physical return for the
--     same parcel; restocking that one would put back stock that never came
--     back.
--   * The TikTok Import page never let staff tick an "Awaiting Physical
--     Return" row (its CONFIRMABLE list left it out), so the row was left
--     unticked and excluded at confirm and no physical return was ever opened
--     (production has never had one). Fixed in src/pages/TikTokImportPage.tsx
--     with this file.
--
-- PRODUCTION (read only, 24 Oct 2026): 181 order rows, 21 order items held in
--   state, no physical return ever. One confirmed row is cancelled with a
--   shipped time: the order above (two rows, one per file). One other
--   cancelled order has a ready-to-ship time and a tracking id but no shipped
--   time (packed, cancelled, never shipped): untouched by this rule. No order
--   batch is staged. This file changes no row: the order above keeps its
--   state (it is seen; see THE RULES), so a later file lists it as "Already
--   Imported" as before. Taking its unit off and opening its physical return
--   is the Owner's decision, separately.
--
-- THE RULES
--
--   * A row says its parcel left the store when TikTok gives it a shipped or
--     a delivered time (raw->>'shipped_time' / 'delivered_time', as the file
--     had it). Read from the row as imported, not from tiktok_order_rows.
--     shipped_time: tiktok_parse_time reads a day of 12 or less as the month
--     (TikTok writes DD/MM/YYYY; '12/10/2026' is stored as 10 Dec), and only
--     whether TikTok gave a time matters here. A ready-to-ship time or a
--     tracking id is not enough: a parcel packed and cancelled before the
--     courier took it is still on the shelf.
--   * A row is shipped when its order item was confirmed shipped before
--     (was_shipped, as now) or the row itself says so.
--   * Cancelled (any 'return' status) and shipped, never seen before (no
--     state row): its quantity is taken off now, as a shipped row's would
--     have been ("New — Will Deduct, Awaiting Return", or "Negative Stock
--     Warning" as any deduction), and confirm opens its physical return
--     (expected: that quantity) and records it deducted and shipped. Staff
--     then confirm the parcel came back (Stock Return puts the stock back)
--     or record why it never will.
--   * Cancelled and shipped, deducted before: "Awaiting Physical Return" as
--     now, also when the earlier import saw it unshipped (To Ship); never an
--     automatic return. Once its physical return is resolved and none waits,
--     a later file's row is "Already Imported": nothing taken, nothing put
--     back, no new physical return.
--   * Cancelled and shipped, seen before and not deducted (a physical return
--     restocked; or the order above): "Already Imported", nothing changes.
--   * Everything else as before: deduct statuses, cancellation before
--     shipment (automatic return), "No Stock Action" statuses, invalid,
--     duplicate and unmatched rows, the negative-stock gate.
--
-- WHAT THIS DOES
--
--   1. New: tiktok_row_shows_shipped(jsonb), the server's alone: whether an
--      imported row's raw values give a shipped or delivered time (anything
--      shaped like a date).
--   2. tiktok_evaluate: the 6-argument function is replaced by one with a
--      seventh argument, p_row_shipped boolean DEFAULT false (what the row
--      says; a caller that does not pass it is evaluated as before). Same
--      result columns, same grants (the server's alone). The rules above.
--   3. stage_tiktok_orders, refresh_tiktok_staging, confirm_tiktok_batch
--      (both of its evaluations) pass tiktok_row_shows_shipped of the row.
--   4. confirm_tiktok_batch: a 'return' row with a positive delta (only the
--      new rule gives one) takes its stock off (apply_tiktok_stock_delta, note
--      'TikTok import <file> (shipped, then <status>)'; the movement row adds
--      '— order <id>'), writes state deducted_qty = its quantity, was_shipped
--      true, opens the physical return once (none awaiting for the item) and
--      counts in the result's awaiting_physical_return as well as
--      units_deducted. A 'return' row that moves nothing keeps the item's
--      deduction (before, always 0 there; now it may be a parcel recorded as
--      never coming back, which a later file must not wipe).
--
-- NOT CHANGED
--
--   resolve_tiktok_physical_return, apply_tiktok_stock_delta,
--   tiktok_projected_short, tiktok_status_effect, tiktok_status_marks_shipped,
--   tiktok_parse_time (its day/month reading is a separate fix: it changes
--   stored dates and reports), create_tiktok_correction_batch, every report,
--   every table, column, policy and grant (the three patched functions keep
--   theirs). No row is changed.
--
-- NOT COVERED (to tell the owner)
--
--   * The order found on 24 Oct (above): not taken off; it needs the Owner's
--     decision (for example: take its unit off at its store and open its
--     physical return, then staff resolve it).
--   * While its physical return waits, and after a No Stock Return, the
--     order holds a deduction, so the Dashboard counts it among "orders
--     awaiting settlement" (deducted, no settlement line), as an order
--     cancelled after a shipped import already is. A Stock Return clears it.
--   * A physical return's expected quantity is the row's quantity; TikTok's
--     own "return quantity" is not read (staff confirm what arrived).
--   * An order whose state row was made by a correction batch alone and
--     never deducted is "seen": a later shipped-and-cancelled row of it takes
--     nothing off.
--   * scripts/tiktok/repair/427-take-off-27-aug-order.sql (not yet run)
--     pinned the three patched functions and the 6-argument tiktok_evaluate;
--     it is updated with this file to accept either version (its order is
--     Completed, which this file does not change).
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (464 in: 432fcb994b57ee8144e8d7e608114a72, 1379
--   functions) -> 465 (this file) -> the Import page (TikTokImportPage.tsx).
--   Either order is safe: the page alone only lets "Awaiting Physical Return"
--   rows be confirmed, which opens their physical return as 65 meant.
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below, the second changes
--      nothing ("already this version; left alone").
--   2. Apply (the MCP's apply_migration with this text verbatim, or the CLI).
--      It checks itself and runs its self-test.
--   3. Deploy the page.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the functions it relies on are as read on production (24 Oct 2026),
--     the columns it reads are there with these types;
--   * tiktok_evaluate is the 6-argument BEFORE and no 7-argument one is there
--     (replaced), or the 7-argument AFTER and no 6-argument one (left alone);
--     the helper is not there (made) or this version (left alone); each
--     patched function is its BEFORE (patched; each anchor found as many
--     times as expected; the text built has the tested AFTER md5) or its
--     AFTER (left alone); no other function takes these names;
--   * afterwards: the md5s are the AFTER ones; the patched functions keep
--     their grants (compared as sets) and stay callable by signed-in staff;
--     tiktok_evaluate and the helper are the server's alone;
--   * then a self-test, in a block that is always undone (it ends by raising
--     P0465, so it leaves no row): a made-up Owner, store, limited voucher
--     (five in stock; a voucher, not a product, so no stock-history row and
--     no sequence is used), its SKU mapping and a 'return' status of its own.
--     An order cancelled with a shipped time, first seen: staged "New — Will
--     Deduct, Awaiting Return", 1; confirmed: 4 left, deducted and shipped,
--     one physical return waiting for 1. The same row in a second file:
--     "Awaiting Physical Return", 0; confirmed: still one. Resolved as No
--     Stock Return (lost), a third file: "Already Imported", 0; confirmed:
--     still one, 4 left, still deducted 1. A second such order restocked: 4
--     left. An order cancelled with no shipped time, first seen: "Already
--     Imported", 0, nothing taken, no physical return.
--   Locks: the four functions' catalogue rows and the self-test's own rows.
--   An import being staged or confirmed at that moment finishes first or
--   waits (the lock timeout gives up after 5 s and changes nothing).
--
-- BEFORE (production now, 24 Oct 2026; md5 of pg_get_functiondef with
-- search_path public)
--   changed
--   tiktok_evaluate(uuid,text,text,integer,text,boolean)           358bf625b34bd1e97586b722df40184a  (as at 65; dropped)
--   stage_tiktok_orders(uuid,text,text,jsonb)                      165118c2a659e3590f84457e9056a307  (as at 65)
--   refresh_tiktok_staging(uuid)                                   fa6368a4ca95b62b0e7920ba7e673fd6  (as at 64)
--   confirm_tiktok_batch(uuid,jsonb,boolean,text)                  f7236b71c8df5d981cbf64e6298fa052  (as at 65)
--   relied on, not changed
--   apply_tiktok_stock_delta(uuid,text,uuid,integer,uuid,text,text,text) e3c9f3c5f2b49fd580b926653ed7e1ac
--   tiktok_projected_short(uuid,text,uuid,integer)                 81a5387a9e046dc431d4711a77aa2ee7
--   tiktok_status_effect(text)                                     61a3a9f5f1b68bc8b208978106c731e8
--   tiktok_status_marks_shipped(text)                              4f511118b8b4d9f7513edf95b284df1c
--   tiktok_access_check(uuid)                                      94b85ae013171b13947013b6e1c06036
--   resolve_tiktok_physical_return(uuid,boolean,text,text)         12ae6689e864b6374f3d5090f5fccb4b  (the self-test)
--   trg_tiktok_row_immutable()                                     e4b60289ccbea8febc55bc09021dff29
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   public function fingerprint, production now                    432fcb994b57ee8144e8d7e608114a72 (1379 functions)
-- AFTER (for later guards)
--   tiktok_evaluate(uuid,text,text,integer,text,boolean,boolean)   e099050c8c43c973721229c21adddfd3
--   tiktok_row_shows_shipped(jsonb)                                6e51262ec7a94429da6f5c397bd0d836  (new)
--   stage_tiktok_orders(uuid,text,text,jsonb)                      9cad8a716950fdaab791f6f42cdddf7c
--   refresh_tiktok_staging(uuid)                                   e86e136864942da175725d394d8f0817
--   confirm_tiktok_batch(uuid,jsonb,boolean,text)                  4b7b3844d884efa3f5f81d7770048daf
--   public function fingerprint: production now -> 465 (a second run the
--   same)                                                          0b8580cda1e2c697a1e9219f95ed3046 (1380 functions: one
--   added, one replaced). Worked out read-only on production (24 Oct 2026)
--   from its own md5 list with these five put in; confirm it on the dry run.
--
-- Test: scripts/tiktok/tests/shipped-then-cancelled-465.sql (begin ...
-- rollback; it installs this file twice). Fixtures only (the repository is
-- public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The three patched functions: BEFORE (production now) and AFTER md5s ══
  c_sigs constant text[] := array[
    'stage_tiktok_orders(uuid,text,text,jsonb)',
    'refresh_tiktok_staging(uuid)',
    'confirm_tiktok_batch(uuid,jsonb,boolean,text)'];
  c_before constant text[] := array[
    '165118c2a659e3590f84457e9056a307',
    'fa6368a4ca95b62b0e7920ba7e673fd6',
    'f7236b71c8df5d981cbf64e6298fa052'];
  c_after constant text[] := array[
    '9cad8a716950fdaab791f6f42cdddf7c',
    'e86e136864942da175725d394d8f0817',
    '4b7b3844d884efa3f5f81d7770048daf'];
  -- each anchor, the function it is in (an index into c_sigs), how many
  -- times it is there (every one is replaced) and its patch, in order
  c_fn constant int[] := array[1, 2, 3, 3, 3];
  c_times constant int[] := array[1, 1, 2, 1, 1];
  c_anchor constant text[] := array[
$a1$    select * into v_eval from public.tiktok_evaluate(p_store_id, v_order, v_sku, v_qty, v_status, v_dup);
$a1$,
$a2$      v_row.staging_status = 'Duplicate Row');
$a2$,
$a3$      v_row.staging_status = 'Duplicate Row');
$a3$,
$a4$      v_awaiting := v_awaiting + 1;
    else
$a4$,
$a5$        do update set deducted_qty = excluded.deducted_qty, last_status = excluded.last_status,
$a5$];
  c_patch constant text[] := array[
$p1$    -- 465: and whether the row itself says its parcel left the store.
    select * into v_eval from public.tiktok_evaluate(p_store_id, v_order, v_sku, v_qty, v_status, v_dup,
                                                     public.tiktok_row_shows_shipped(v_r));
$p1$,
$p2$      v_row.staging_status = 'Duplicate Row', public.tiktok_row_shows_shipped(v_row.raw));  -- 465
$p2$,
$p3$      v_row.staging_status = 'Duplicate Row', public.tiktok_row_shows_shipped(v_row.raw));  -- 465
$p3$,
$p4$      v_awaiting := v_awaiting + 1;
    elsif v_effect = 'return' and v_eval.stock_delta > 0 then
      -- 465: shipped, then cancelled (or returned or refunded) before any
      -- file brought the order in (only this gives a 'return' row a positive
      -- delta). The parcel left the store: its stock is taken off now, as a
      -- shipped row's would have been, the item is recorded deducted and
      -- shipped, and it waits for its physical return like one cancelled
      -- after a shipped import. Before 465 nothing was taken off and nothing
      -- was expected back.
      perform public.apply_tiktok_stock_delta(
        v_row.store_id, v_eval.matched_kind, v_eval.matched_id, v_eval.stock_delta,
        v_row.id, v_row.order_id, v_row.seller_sku,
        'TikTok import ' || coalesce(v_b.file_name,'') || ' (shipped, then ' || lower(coalesce(v_row.order_status,'cancelled')) || ')');
      insert into public.tiktok_order_state (store_id, order_id, seller_sku, deducted_qty, last_status, was_shipped, updated_at)
      values (v_row.store_id, v_row.order_id, v_row.seller_sku, v_eval.stock_delta, v_row.order_status, true, now())
      on conflict (store_id, order_id, seller_sku)
      do update set deducted_qty = excluded.deducted_qty, last_status = excluded.last_status,
                    was_shipped = true, updated_at = now();
      if not exists (select 1 from public.tiktok_physical_returns
                      where store_id = v_row.store_id and order_id = v_row.order_id
                        and seller_sku = v_row.seller_sku and status = 'awaiting') then
        insert into public.tiktok_physical_returns
          (order_row_id, store_id, order_id, seller_sku, expected_qty)
        values (v_row.id, v_row.store_id, v_row.order_id, v_row.seller_sku, v_eval.stock_delta);
      end if;
      v_awaiting := v_awaiting + 1;
    else
$p4$,
$p5$        -- 465: a cancelled row that moves nothing keeps what the item holds:
        -- before 465 its deduction was always 0 here; now it may be a parcel
        -- recorded as never coming back (No Stock Return), which a later
        -- file's row must not wipe.
        do update set deducted_qty = case when v_effect = 'return' and v_eval.stock_delta = 0
                                          then public.tiktok_order_state.deducted_qty
                                          else excluded.deducted_qty end,
                      last_status = excluded.last_status,
$p5$];

  -- ══ tiktok_evaluate: the 6-argument BEFORE, replaced by the 7-argument ══
  c_eval_old constant text := 'tiktok_evaluate(uuid,text,text,integer,text,boolean)';
  c_eval_old_before constant text := '358bf625b34bd1e97586b722df40184a';
  c_eval constant text := 'tiktok_evaluate(uuid,text,text,integer,text,boolean,boolean)';
  c_eval_after constant text := 'e099050c8c43c973721229c21adddfd3';
  c_eval_def constant text :=
$d1$CREATE OR REPLACE FUNCTION public.tiktok_evaluate(p_store_id uuid, p_order_id text, p_seller_sku text, p_quantity integer, p_order_status text, p_is_duplicate boolean, p_row_shipped boolean DEFAULT false)
 RETURNS TABLE(staging_status text, stock_delta integer, matched_kind text, matched_id uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 465: p_row_shipped is what the import row itself says: TikTok gave it a
-- shipped or delivered time (tiktok_row_shows_shipped). Its parcel left the
-- store, whatever status the importer saw it in, first or since. Before 465
-- only a status confirmed as shipped (tiktok_order_state.was_shipped)
-- counted, so an order shipped and cancelled before any file brought it in
-- was never taken off nor expected back, and one first seen To Ship was put
-- back automatically. A caller that does not pass it is evaluated as before.
declare
  v_alias public.tiktok_sku_aliases%rowtype;
  v_effect text; v_prev integer; v_shipped boolean; v_seen boolean; v_target integer; v_delta integer;
begin
  staging_status := null; stock_delta := 0; matched_kind := null; matched_id := null;

  if nullif(trim(coalesce(p_order_id,'')),'') is null
     or nullif(coalesce(p_seller_sku,''),'') is null
     or p_quantity is null or p_quantity <= 0 then
    staging_status := 'Invalid Row'; return next; return;
  end if;
  if p_is_duplicate then
    staging_status := 'Duplicate Row'; return next; return;
  end if;

  select * into v_alias from public.tiktok_sku_aliases
    where store_id = p_store_id and seller_sku = p_seller_sku;
  if found then matched_kind := v_alias.target_kind; matched_id := v_alias.target_id; end if;

  v_effect := public.tiktok_status_effect(p_order_status);
  if v_effect = 'invalid' then
    staging_status := 'Invalid Status'; return next; return;
  end if;

  if matched_id is null then
    staging_status := 'Unmatched SKU'; return next; return;
  end if;

  select coalesce(deducted_qty,0), coalesce(was_shipped,false), true into v_prev, v_shipped, v_seen
    from public.tiktok_order_state
   where store_id = p_store_id and order_id = p_order_id and seller_sku = p_seller_sku;
  v_prev := coalesce(v_prev, 0); v_seen := coalesce(v_seen, false);
  v_shipped := coalesce(v_shipped, false) or coalesce(p_row_shipped, false);  -- 465

  -- 'No Stock Action' statuses never move stock and never touch state.
  if v_effect = 'none' then
    staging_status := 'No Stock Change'; stock_delta := 0; return next; return;
  end if;

  -- Cancellation AFTER shipment: never an automatic return.
  if v_effect = 'return' and v_prev > 0 and v_shipped then
    -- 465: once its physical return is resolved and none waits, a later
    -- file's cancelled row changes nothing (before, each one opened another).
    if exists (select 1 from public.tiktok_physical_returns r
                where r.store_id = p_store_id and r.order_id = p_order_id and r.seller_sku = p_seller_sku)
       and not exists (select 1 from public.tiktok_physical_returns r
                        where r.store_id = p_store_id and r.order_id = p_order_id and r.seller_sku = p_seller_sku
                          and r.status = 'awaiting') then
      staging_status := 'Already Imported'; stock_delta := 0; return next; return;
    end if;
    staging_status := 'Awaiting Physical Return'; stock_delta := 0; return next; return;
  end if;

  -- 465: shipped, then cancelled (or returned or refunded) before any file
  -- brought the order in: its parcel left the store, so its stock is taken
  -- off now, as a shipped row's would have been, and confirm_tiktok_batch
  -- opens its physical return. Before 465: "Already Imported", nothing.
  if v_effect = 'return' and v_shipped and not v_seen then
    stock_delta := p_quantity;
    staging_status := 'New — Will Deduct, Awaiting Return';
    if public.tiktok_projected_short(p_store_id, matched_kind, matched_id, p_quantity) then
      staging_status := 'Negative Stock Warning';
    end if;
    return next; return;
  end if;

  v_target := case when v_effect = 'deduct' then p_quantity else 0 end;
  v_delta := v_target - v_prev;
  stock_delta := v_delta;

  if v_delta = 0 then
    staging_status := case when v_prev > 0 or v_effect = 'return' then 'Already Imported' else 'No Stock Change' end;
  elsif v_delta < 0 then
    staging_status := 'Updated — Stock Return';
  elsif v_prev > 0 then
    staging_status := 'Updated — Additional Deduction';
  else
    staging_status := 'New — Will Deduct';
  end if;

  if v_delta > 0 and public.tiktok_projected_short(p_store_id, matched_kind, matched_id, v_delta) then
    staging_status := 'Negative Stock Warning';
  end if;
  return next;
end $function$
$d1$;

  -- ══ The helper this adds (the server's alone) ═══════════════════════════
  c_ship constant text := 'tiktok_row_shows_shipped(jsonb)';
  c_ship_after constant text := '6e51262ec7a94429da6f5c397bd0d836';
  c_ship_def constant text :=
$d2$CREATE OR REPLACE FUNCTION public.tiktok_row_shows_shipped(p_raw jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  -- 465: an imported TikTok order row says its parcel left the store when
  -- TikTok gives it a shipped or a delivered time. Read from the row as the
  -- file had it (raw), not from tiktok_order_rows.shipped_time:
  -- tiktok_parse_time reads a day of 12 or less as the month (DD/MM/YYYY
  -- read as MM/DD) and a time it cannot read as null, and only whether
  -- TikTok gave a time matters here. A ready-to-ship time or a tracking id
  -- is not enough: a parcel packed and cancelled before the courier took it
  -- is still on the shelf.
  select coalesce(p_raw->>'shipped_time', '') ~ '\d{1,4}[/.-]\d{1,2}[/.-]\d{1,4}'
      or coalesce(p_raw->>'delivered_time', '') ~ '\d{1,4}[/.-]\d{1,2}[/.-]\d{1,4}'
$function$
$d2$;

  c_internal_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';

  -- ══ Relied on, not changed (production now) ═══════════════════════════
  c_relied constant text[] := array[
    'apply_tiktok_stock_delta(uuid,text,uuid,integer,uuid,text,text,text)',
    'tiktok_projected_short(uuid,text,uuid,integer)',
    'tiktok_status_effect(text)',
    'tiktok_status_marks_shipped(text)',
    'tiktok_access_check(uuid)',
    'resolve_tiktok_physical_return(uuid,boolean,text,text)',
    'trg_tiktok_row_immutable()',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)'];
  c_relied_md5 constant text[] := array[
    'e3c9f3c5f2b49fd580b926653ed7e1ac',
    '81a5387a9e046dc431d4711a77aa2ee7',
    '61a3a9f5f1b68bc8b208978106c731e8',
    '4f511118b8b4d9f7513edf95b284df1c',
    '94b85ae013171b13947013b6e1c06036',
    '12ae6689e864b6374f3d5090f5fccb4b',
    'e4b60289ccbea8febc55bc09021dff29',
    'c705c733e213a27f0dc32d54322cc855'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; n int; i int; k int;
  v_texts text[] := array[null, null, null]::text[]; v_acls text[] := array[null, null, null]::text[];
  v_make_eval boolean := false; v_make_ship boolean := false;
  -- the self-test's made-up records
  t_sfx text; t_owner uuid; t_store uuid; t_vch uuid; t_status text; t_sku text; t_rows jsonb;
  t_batch uuid; t_res jsonb; t_pr uuid;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── 1. Checks: nothing is changed before all of them pass ──────────────
  -- What it relies on and does not change: as read on production, 24 Oct 2026.
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '465: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;

  -- The columns it reads and writes, with these types.
  select string_agg(x.t || '.' || x.c || ' ' || x.ty, ', ') into v
    from (values ('tiktok_order_rows', 'id', 'uuid'), ('tiktok_order_rows', 'raw', 'jsonb'),
                 ('tiktok_order_rows', 'order_status', 'text'), ('tiktok_order_rows', 'quantity', 'integer'),
                 ('tiktok_order_state', 'deducted_qty', 'integer'), ('tiktok_order_state', 'was_shipped', 'boolean'),
                 ('tiktok_order_state', 'last_status', 'text'),
                 ('tiktok_physical_returns', 'order_row_id', 'uuid'), ('tiktok_physical_returns', 'store_id', 'uuid'),
                 ('tiktok_physical_returns', 'order_id', 'text'), ('tiktok_physical_returns', 'seller_sku', 'text'),
                 ('tiktok_physical_returns', 'expected_qty', 'integer'), ('tiktok_physical_returns', 'status', 'text')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and not a.attisdropped
                        and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '465: these columns are missing or not of this type: %', v; end if;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('stage_tiktok_orders', 'refresh_tiktok_staging', 'confirm_tiktok_batch',
                       'tiktok_evaluate', 'tiktok_row_shows_shipped')
     and p.oid::regprocedure::text <> all (c_sigs || array[c_eval_old, c_eval, c_ship]);
  if v is not null then raise exception '465: another function takes the name of one this changes: %', v; end if;

  -- The two texts written out here are the tested ones.
  if md5(c_eval_def) <> c_eval_after then
    raise exception '465: the text of public.% is not the tested one (md5 %)', c_eval, md5(c_eval_def); end if;
  if md5(c_ship_def) <> c_ship_after then
    raise exception '465: the text of public.% is not the tested one (md5 %)', c_ship, md5(c_ship_def); end if;

  -- The helper: not there yet (made), or this version (left alone).
  if to_regprocedure('public.' || c_ship) is null then
    v_make_ship := true;
  elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_ship))) <> c_ship_after then
    raise exception '465: public.% is there but not this version (md5 %). Nothing was changed.',
      c_ship, md5(pg_get_functiondef(to_regprocedure('public.' || c_ship)));
  end if;

  -- tiktok_evaluate: the 6-argument BEFORE alone (replaced), or the
  -- 7-argument AFTER alone (left alone).
  if to_regprocedure('public.' || c_eval_old) is not null and to_regprocedure('public.' || c_eval) is null then
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_eval_old))) <> c_eval_old_before then
      raise exception '465: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_eval_old, md5(pg_get_functiondef(to_regprocedure('public.' || c_eval_old))); end if;
    v_make_eval := true;
  elsif to_regprocedure('public.' || c_eval_old) is null and to_regprocedure('public.' || c_eval) is not null then
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_eval))) <> c_eval_after then
      raise exception '465: public.% is there but not this version (md5 %). Nothing was changed.',
        c_eval, md5(pg_get_functiondef(to_regprocedure('public.' || c_eval))); end if;
  else
    raise exception '465: public.tiktok_evaluate is neither the 6-argument version as read nor this file''s 7-argument one alone. Nothing was changed.';
  end if;

  -- Each patched function: its BEFORE (patched; each anchor found as often as
  -- expected; the text built has its AFTER md5) or its AFTER (left alone).
  for k in 1 .. cardinality(c_sigs) loop
    if to_regprocedure('public.' || c_sigs[k]) is null then raise exception '465: public.% is missing', c_sigs[k]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sigs[k]));
    -- its grants, to compare after (as sets: production lists them in
    -- another order than a local copy does)
    v_acls[k] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                    from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[k]));
    if md5(d) = c_after[k] then
      raise notice '465: public.% is already this version; left alone', c_sigs[k];
      continue;
    end if;
    if md5(d) <> c_before[k] then
      raise exception '465: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sigs[k], md5(d); end if;
    for i in 1 .. cardinality(c_anchor) loop
      continue when c_fn[i] <> k;
      n := (length(d) - length(replace(d, c_anchor[i], ''))) / length(c_anchor[i]);
      if n <> c_times[i] then raise exception '465: anchor % of public.% was found % times, not %', i, c_sigs[k], n, c_times[i]; end if;
      d := replace(d, c_anchor[i], c_patch[i]);
    end loop;
    if md5(d) <> c_after[k] then
      raise exception '465: the text built for public.% is not the tested one (md5 %)', c_sigs[k], md5(d); end if;
    v_texts[k] := d;
  end loop;

  -- ── 2. Install: the helper, then tiktok_evaluate (the patched ones call
  -- both), then the patched functions ────────────────────────────────────
  if v_make_ship then
    execute c_ship_def;
    execute format('revoke all on function public.%s from public, anon, authenticated', c_ship);
    execute format('grant execute on function public.%s to service_role', c_ship);
  else
    raise notice '465: public.% is already this version; left alone', c_ship;
  end if;
  if v_make_eval then
    -- The 6-argument one goes: with the default, a 6-argument call would be
    -- ambiguous between the two. plpgsql resolves a call when it runs, so the
    -- callers patched below are the only ones changed (no other function or
    -- view calls it).
    execute format('drop function public.%s', c_eval_old);
    execute c_eval_def;
    execute format('revoke all on function public.%s from public, anon, authenticated', c_eval);
    execute format('grant execute on function public.%s to service_role', c_eval);
  else
    raise notice '465: public.% is already this version; left alone', c_eval;
  end if;
  for k in 1 .. cardinality(c_sigs) loop
    if v_texts[k] is not null then execute v_texts[k]; end if;
  end loop;

  -- ── 3. Checks after installing ──────────────────────────────────────────
  if to_regprocedure('public.' || c_eval_old) is not null
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_eval))) <> c_eval_after
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_ship))) <> c_ship_after then
    raise exception '465: tiktok_evaluate or tiktok_row_shows_shipped is not as tested after installing'; end if;
  foreach v in array array[c_eval, c_ship] loop
    if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || v))
       is distinct from (select array_agg(x::text order by x::text) from unnest(c_internal_acl::aclitem[]) x)
       or has_function_privilege('anon', 'public.' || v, 'execute')
       or has_function_privilege('authenticated', 'public.' || v, 'execute')
       or not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '465: public.% is not the server''s alone', v; end if;
  end loop;
  for k in 1 .. cardinality(c_sigs) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sigs[k]))) <> c_after[k] then
      raise exception '465: public.% was installed with an md5 other than the tested one', c_sigs[k]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sigs[k])) is distinct from v_acls[k]
       or has_function_privilege('anon', 'public.' || c_sigs[k], 'execute')
       or not has_function_privilege('authenticated', 'public.' || c_sigs[k], 'execute')
       or not has_function_privilege('service_role', 'public.' || c_sigs[k], 'execute') then
      raise exception '465: the grants of public.% changed', c_sigs[k]; end if;
  end loop;

  -- ── 4. Self-test, in a block that is always undone ─────────────────────
  -- Made-up records only ("465 check", @example.com), a limited voucher (no
  -- product, so no stock history row and no sequence); it ends by raising
  -- P0465, which undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_status := '465 check cancelled ' || t_sfx;
    t_sku := '465-' || t_sfx;
    insert into auth.users (id, email) values (gen_random_uuid(), '465-check-' || t_sfx || '@example.com') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '465 check', '465-check-' || t_sfx || '@example.com', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('465 check ' || t_sfx, '465-' || t_sfx, 'SG') returning id into t_store;
    insert into public.vouchers (name, code, voucher_kind, selling_price, qty_type, is_active)
    values ('465 check ' || t_sfx, '465-' || t_sfx, 'normal', 10, 'limited', true) returning id into t_vch;
    insert into public.voucher_store_stock (voucher_id, store_id, current_qty) values (t_vch, t_store, 5);
    insert into public.tiktok_sku_aliases (store_id, seller_sku, target_kind, target_id, created_by)
    values (t_store, t_sku, 'voucher', t_vch, t_owner);
    insert into public.tiktok_status_mappings (status_label, status_norm, action, marks_shipped)
    values (t_status, public.tiktok_norm_status(t_status), 'return', false);

    -- Cancelled with a shipped time, first seen: taken off, waits for its
    -- physical return.
    t_rows := jsonb_build_array(jsonb_build_object('order_id', '465CHECK' || t_sfx || 'A', 'seller_sku', t_sku, 'quantity', '1',
      'order_status', t_status, 'shipped_time', '13/10/2026 10:00:00', 'cancelled_time', '19/10/2026 12:00:00'));
    t_batch := public.stage_tiktok_orders(t_store, '465 check 1', null, t_rows);
    if (select (staging_status, stock_delta) is distinct from ('New — Will Deduct, Awaiting Return'::text, 1)
          from public.tiktok_order_rows where batch_id = t_batch) then
      raise exception '465: a cancelled row with a shipped time, first seen, is not staged to deduct and await its return (%)',
        (select staging_status || ' ' || stock_delta from public.tiktok_order_rows where batch_id = t_batch); end if;
    t_res := public.confirm_tiktok_batch(t_batch, null, false, null);
    if (t_res->>'units_deducted')::int <> 1 or (t_res->>'awaiting_physical_return')::int <> 1
       or (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch) <> 4
       or (select (deducted_qty, was_shipped) is distinct from (1, true) from public.tiktok_order_state
            where store_id = t_store and order_id = '465CHECK' || t_sfx || 'A' and seller_sku = t_sku)
       or (select count(*) from public.tiktok_physical_returns where store_id = t_store and status = 'awaiting' and expected_qty = 1) <> 1 then
      raise exception '465: confirmed, the first-seen shipped-and-cancelled row did not take 1 off and open one physical return (%)', t_res; end if;

    -- The same row in a second file: waits, nothing more.
    t_batch := public.stage_tiktok_orders(t_store, '465 check 2', null, t_rows);
    if (select (staging_status, stock_delta) is distinct from ('Awaiting Physical Return'::text, 0)
          from public.tiktok_order_rows where batch_id = t_batch) then
      raise exception '465: the row in a second file is not "Awaiting Physical Return", 0'; end if;
    t_res := public.confirm_tiktok_batch(t_batch, null, false, null);
    if (select count(*) from public.tiktok_physical_returns where store_id = t_store) <> 1
       or (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch) <> 4 then
      raise exception '465: the second file opened another physical return or moved stock'; end if;

    -- Resolved as No Stock Return; a third file: nothing.
    select id into t_pr from public.tiktok_physical_returns where store_id = t_store;
    perform public.resolve_tiktok_physical_return(t_pr, false, 'lost', null);
    t_batch := public.stage_tiktok_orders(t_store, '465 check 3', null, t_rows);
    if (select (staging_status, stock_delta) is distinct from ('Already Imported'::text, 0)
          from public.tiktok_order_rows where batch_id = t_batch) then
      raise exception '465: after a No Stock Return, the row in a third file is not "Already Imported", 0'; end if;
    t_res := public.confirm_tiktok_batch(t_batch, null, false, null);
    if (select count(*) from public.tiktok_physical_returns where store_id = t_store) <> 1
       or (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch) <> 4
       or (select deducted_qty from public.tiktok_order_state
            where store_id = t_store and order_id = '465CHECK' || t_sfx || 'A' and seller_sku = t_sku) <> 1 then
      raise exception '465: after a No Stock Return, a third file opened another physical return, moved stock or wiped the deduction'; end if;

    -- A second such order, restocked: its unit back.
    t_rows := jsonb_build_array(jsonb_build_object('order_id', '465CHECK' || t_sfx || 'B', 'seller_sku', t_sku, 'quantity', '1',
      'order_status', t_status, 'shipped_time', '02/10/2026 09:00:00'));
    t_res := public.confirm_tiktok_batch(public.stage_tiktok_orders(t_store, '465 check 4', null, t_rows), null, false, null);
    select id into t_pr from public.tiktok_physical_returns where store_id = t_store and status = 'awaiting';
    if t_pr is null or (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch) <> 3 then
      raise exception '465: the second shipped-and-cancelled order did not take 1 off and wait for its return'; end if;
    perform public.resolve_tiktok_physical_return(t_pr, true, null, null);
    if (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch) <> 4 then
      raise exception '465: restocking the second order''s physical return did not put its unit back'; end if;

    -- Cancelled with no shipped time (a ready-to-ship time and a tracking id
    -- only), first seen: as before, nothing.
    t_rows := jsonb_build_array(jsonb_build_object('order_id', '465CHECK' || t_sfx || 'C', 'seller_sku', t_sku, 'quantity', '1',
      'order_status', t_status, 'rts_time', '08/10/2026 18:00:00', 'tracking_id', '465TRACK' || t_sfx));
    t_batch := public.stage_tiktok_orders(t_store, '465 check 5', null, t_rows);
    if (select (staging_status, stock_delta) is distinct from ('Already Imported'::text, 0)
          from public.tiktok_order_rows where batch_id = t_batch) then
      raise exception '465: a cancelled row with no shipped time is not "Already Imported", 0'; end if;
    t_res := public.confirm_tiktok_batch(t_batch, null, false, null);
    if (select count(*) from public.tiktok_physical_returns where store_id = t_store) <> 2
       or (select current_qty from public.voucher_store_stock where store_id = t_store and voucher_id = t_vch) <> 4 then
      raise exception '465: a cancelled row with no shipped time moved stock or opened a physical return'; end if;

    raise exception using errcode = 'P0465', message = '465: self-test done, undone';
  exception when sqlstate 'P0465' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
