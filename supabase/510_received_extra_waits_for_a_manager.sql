-- 510_received_extra_waits_for_a_manager.sql
--
-- UNITS RECEIVED ABOVE WHAT WAS SENT WAIT FOR AN OWNER OR MANAGER
--
--   From the security audit of 17 Nov 2026 (finding M10).
--   The BEFORE md5s below were read from production (head 502) on 17 Nov 2026 and match
--   the local copy built to production's function fingerprint. If production's text
--   differs when this is applied, this file refuses and changes nothing: re-read and re-test.
--   (The number 510 is this file's name and its errors' prefix; if it changes at commit,
--   change it in those places alone.)
--
-- THE OWNER'S DECISION (17 Nov 2026, "extra waits"): when a place receives a transfer, only
-- what was sent is added to its stock at receipt. Any extra typed in is added only when an
-- Owner or Manager resolves the discrepancy.
--
-- WHAT WAS WRONG
--
--   receive_transfer added the typed received quantity to the destination at once, with no
--   upper bound. Whoever may receive (Staff and Inventory Managers at their own store too)
--   could type 500 for a line of 2 and have 498 units to sell straight away. The transfer
--   was flagged for a Manager afterwards, but the stock was already there.
--
-- WHAT THIS DOES
--
--   1. A new column, transfer_request_lines.extra_waiting_quantity (0 unless something
--      waits): the units typed above what was sent that have not been added to stock.
--   2. receive_transfer adds least(received, sent) of a product line to the destination,
--      with its stock movement of that many, and keeps the rest in extra_waiting_quantity.
--      The line still records what was typed (received_quantity) and its discrepancy
--      against the approved quantity, exactly as before, and the transfer is "received with
--      discrepancy" as before. The receipt's audit row and the function's answer also give
--      the number of units waiting (extra_waiting).
--   3. resolve_transfer_discrepancy (Owner or Manager only), for a line it resolves that has
--      units waiting, first adds them to the destination, with a transfer-receipt movement
--      "Transfer received: extra units added when the discrepancy was resolved", and sets
--      the column back to 0. The chosen resolution then works exactly as before. So every
--      resolution ends with the stock it gave before 510: "Accept extra as surplus" keeps the
--      extra; "Return excess" and "Correct destination" take it off again; "Correct source"
--      keeps it and takes it off the source. The line's audit row records extra_added.
--   4. The stock integrity report (stock_private_report_transfer_stock_integrity) compares a
--      line's receipt movements with the received quantity less the units still waiting,
--      so a transfer that waits for review is not listed as a receipt mismatch.
--
--   A receipt of exactly what was sent, or less, is unchanged: everything typed is added
--   at receipt and nothing waits. Manual (non-inventory) lines never change stock and never
--   wait. "Fill approved" (p_confirm_all) receives what was sent and is unchanged.
--
-- WHAT THIS LEAVES ALONE
--
--   * Who may receive (can_receive_transfer) and who may resolve (Owner or Manager).
--   * A shortfall: as before, the missing units are not added and a Manager resolves them.
--   * Transfers received before 510: their extra was added at receipt and their column is
--     0, so resolving them adds nothing more. Production on 17 Nov 2026 had no open
--     transfer with a line received above what was sent, and none in transit.
--   * Dispatch always sends the approved quantity (review_and_dispatch_transfer). If a line
--     were ever sent with less than approved and received above what was sent but not above
--     what was approved, there would be no discrepancy for a Manager to resolve, so the
--     waiting units could never be added; receive_transfer refuses that case instead.
--   * Reports of what was received (report_transfer_receipts, the discrepancy report) show
--     the typed quantity, as before.
--
-- UNDO: add the waiting units of any unresolved line by hand (or resolve them), run this
-- file's patches backwards (swap c_anchor and c_new and swap c_before and c_after), then
-- drop the column.
--
-- NO SELF-TEST INSIDE; the suite is scripts/transfers/tests/extra-waits-510.sql.
--
-- One transaction with its history row, by the usual wrapper; nothing else is written.

do $mig$
declare
  -- The functions this patches: BEFORE (production, 17 Nov 2026) and AFTER md5s
  c_sig constant text[] := array[
    'receive_transfer(uuid,jsonb,text,boolean)',
    'resolve_transfer_discrepancy(uuid,jsonb,text)',
    'stock_private_report_transfer_stock_integrity()'];
  c_before constant text[] := array[
    '04be775f33e550da46a7ed8054b359ce',
    '9b526acc4fbf00839c9ef4acd5af7856',
    '7e7d4acdae67439d64079dbe357ad971'];
  c_after constant text[] := array[
    '9abfa008ba3ff2525f28bff56592d9e0',
    '9e9e324415e20981b5b416a5a37bf951',
    'f95d3830d1be9d316396ee85386b152f'];
  -- Each patch: which function (its place in c_sig), the text found exactly once
  -- in it, and the text put in its place. An undo swaps them back.
  c_fn constant int[] := array[1, 1, 1, 1, 2, 2, 3, 3];
  c_anchor constant text[] := array[
-- 1 receive_transfer: its variables
$a$v_actual integer; v_diff integer; v_any boolean:=false; v_reason text;$a$,
-- 2 receive_transfer: each line
$a$    v_diff:=v_actual-coalesce(v_l.approved_quantity,v_l.in_transit_quantity,0);
    if v_diff<>0 then v_any:=true; end if;
    update public.transfer_request_lines set received_quantity=v_actual,discrepancy_quantity=v_diff,
      discrepancy_reason=case when v_diff<>0 then v_reason else null end where id=v_l.id;

    if v_l.line_kind='product' and v_actual>0 then
      if v_req.dest_type='warehouse' then
        insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values(v_req.dest_id,v_l.product_id,v_actual)
        on conflict(warehouse_id,product_id) do update set current_qty=public.warehouse_inventory.current_qty+v_actual,updated_at=now();
      else
        insert into public.store_inventory(store_id,product_id,current_qty) values(v_req.dest_id,v_l.product_id,v_actual)
        on conflict(store_id,product_id) do update set current_qty=public.store_inventory.current_qty+v_actual,updated_at=now();
      end if;
      insert into public.stock_movements(product_id,movement_type,to_warehouse_id,to_store_id,quantity,notes,created_by,transfer_request_id,transfer_request_line_id)
      values(v_l.product_id,'transfer_receipt',v_dst_wh,v_dst_st,v_actual,coalesce(p_note,'Transfer received'),auth.uid(),p_request_id,v_l.id);
    end if;$a$,
-- 3 receive_transfer: its audit row
$a$jsonb_build_object('lines',p_lines,'confirm_all',p_confirm_all,'discrepancy',v_any)$a$,
-- 4 receive_transfer: its answer
$a$'discrepancy',v_any);$a$,
-- 5 resolve_transfer_discrepancy: each line, before the resolution acts
$a$    v_diff:=v_l.discrepancy_quantity; v_mag:=abs(v_diff);$a$,
-- 6 resolve_transfer_discrepancy: the line's audit row
$a$jsonb_build_object('resolution',v_res,'reason',v_reason,'manual',v_l.line_kind='manual')$a$,
-- 7 integrity report: the line's columns
$a$l.quantity,l.approved_quantity,l.in_transit_quantity,l.received_quantity,$a$,
-- 8 integrity report: receipt movements against what was added
$a$and rr.line_id is not null and coalesce(b.received_quantity,0)<>coalesce(rr.qty,0)$a$];
  c_new constant text[] := array[
$n$v_actual integer; v_diff integer; v_any boolean:=false; v_reason text;
  v_add integer; v_wait integer; v_wait_total integer:=0;$n$,
$n$    v_diff:=v_actual-coalesce(v_l.approved_quantity,v_l.in_transit_quantity,0);
    -- 510: only what was sent is added now (the Owner, 17 Nov 2026). Units
    -- typed above it wait in extra_waiting_quantity until an Owner or Manager
    -- resolves the discrepancy (resolve_transfer_discrepancy adds them then).
    -- The line still records what was typed and its discrepancy.
    v_add:=case when v_l.line_kind='product' then least(v_actual,coalesce(v_l.in_transit_quantity,0)) else v_actual end;
    v_wait:=case when v_l.line_kind='product' then v_actual-v_add else 0 end;
    if v_wait>0 and v_diff<=0 then
      raise exception 'More was received than was sent for this line, but not more than was approved, so there is nothing for a Manager to review. Ask an Owner or Manager to check the transfer.'; end if;
    v_wait_total:=v_wait_total+v_wait;
    if v_diff<>0 then v_any:=true; end if;
    update public.transfer_request_lines set received_quantity=v_actual,discrepancy_quantity=v_diff,extra_waiting_quantity=v_wait,
      discrepancy_reason=case when v_diff<>0 then v_reason else null end where id=v_l.id;

    if v_l.line_kind='product' and v_add>0 then
      if v_req.dest_type='warehouse' then
        insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values(v_req.dest_id,v_l.product_id,v_add)
        on conflict(warehouse_id,product_id) do update set current_qty=public.warehouse_inventory.current_qty+v_add,updated_at=now();
      else
        insert into public.store_inventory(store_id,product_id,current_qty) values(v_req.dest_id,v_l.product_id,v_add)
        on conflict(store_id,product_id) do update set current_qty=public.store_inventory.current_qty+v_add,updated_at=now();
      end if;
      insert into public.stock_movements(product_id,movement_type,to_warehouse_id,to_store_id,quantity,notes,created_by,transfer_request_id,transfer_request_line_id)
      values(v_l.product_id,'transfer_receipt',v_dst_wh,v_dst_st,v_add,coalesce(p_note,'Transfer received'),auth.uid(),p_request_id,v_l.id);
    end if;$n$,
$n$jsonb_build_object('lines',p_lines,'confirm_all',p_confirm_all,'discrepancy',v_any,'extra_waiting',v_wait_total)$n$,
$n$'discrepancy',v_any,'extra_waiting',v_wait_total);$n$,
$n$    v_diff:=v_l.discrepancy_quantity; v_mag:=abs(v_diff);
    -- 510: units received above what was sent waited for this decision. They
    -- are added to the destination now, as the rest of the receipt was, and
    -- the resolution then works as before, so each choice ends with the stock
    -- it gave before 510 (accept keeps them, return or correct takes them off).
    if v_l.line_kind='product' and coalesce(v_l.extra_waiting_quantity,0)>0 then
      if v_req.dest_type='warehouse' then
        insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values(v_req.dest_id,v_l.product_id,v_l.extra_waiting_quantity)
        on conflict(warehouse_id,product_id) do update set current_qty=public.warehouse_inventory.current_qty+v_l.extra_waiting_quantity,updated_at=now();
      else
        insert into public.store_inventory(store_id,product_id,current_qty) values(v_req.dest_id,v_l.product_id,v_l.extra_waiting_quantity)
        on conflict(store_id,product_id) do update set current_qty=public.store_inventory.current_qty+v_l.extra_waiting_quantity,updated_at=now();
      end if;
      insert into public.stock_movements(product_id,movement_type,to_warehouse_id,to_store_id,quantity,notes,created_by,transfer_request_id,transfer_request_line_id)
      values(v_l.product_id,'transfer_receipt',v_dst_wh,v_dst_st,v_l.extra_waiting_quantity,
             'Transfer received: extra units added when the discrepancy was resolved',auth.uid(),p_request_id,v_l.id);
      update public.transfer_request_lines set extra_waiting_quantity=0 where id=v_l.id;
    end if;$n$,
$n$jsonb_build_object('resolution',v_res,'reason',v_reason,'manual',v_l.line_kind='manual','extra_added',coalesce(v_l.extra_waiting_quantity,0))$n$,
$n$l.quantity,l.approved_quantity,l.in_transit_quantity,l.received_quantity,l.extra_waiting_quantity,$n$,
$n$and rr.line_id is not null and coalesce(b.received_quantity,0)-coalesce(b.extra_waiting_quantity,0)<>coalesce(rr.qty,0)$n$];
  -- Relied on, not changed
  c_relied constant text[] := array[
    'can_receive_transfer(uuid)',
    'is_owner_or_manager()',
    'review_and_dispatch_transfer(uuid,jsonb,text)',
    'stock_history_effect(uuid,text)'];
  c_relied_md5 constant text[] := array[
    '7b97a75b8508c3db9eb9c090b493e3a0',
    'a98e50f1b6d3fa1e6c62cf52a8073cc8',
    '6db84d9ecca1d40b4858b4291401fbc0',
    'fba6f63412970dbf6ac83e567c4d85e2'];

  v_path text := current_setting('search_path');
  v_lock text := current_setting('lock_timeout');
  v_def text[] := array_fill(null::text, array[3]);
  v_make boolean[] := array_fill(false, array[3]);
  v_acl text[] := array_fill(null::text, array[3]);
  v_col text;
  d text; i int;
begin
  perform set_config('lock_timeout', '5s', true);
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '510: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  -- The column: absent (added) or exactly as this file makes it (left alone).
  select format_type(a.atttypid, a.atttypmod) || ' ' || a.attnotnull::text || ' ' || coalesce(pg_get_expr(ad.adbin, ad.adrelid), '')
    into v_col
    from pg_attribute a left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
   where a.attrelid = 'public.transfer_request_lines'::regclass and a.attname = 'extra_waiting_quantity' and not a.attisdropped;
  if v_col is not null and v_col <> 'integer true 0' then
    raise exception '510: transfer_request_lines.extra_waiting_quantity exists but is not this file''s column (%).', v_col; end if;

  -- The functions it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '510: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      if v_col is null then raise exception '510: public.% is already the new version but the column is missing', c_sig[i]; end if;
      raise notice '510: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '510: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '510: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '510: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- 2. Install: the column first, as the new functions read it.
  if v_col is null then
    alter table public.transfer_request_lines
      add column extra_waiting_quantity integer not null default 0
      constraint transfer_request_lines_extra_waiting_quantity_check check (extra_waiting_quantity >= 0);
    comment on column public.transfer_request_lines.extra_waiting_quantity is
      '510: units typed at receipt above what was sent, not yet added to the destination. resolve_transfer_discrepancy adds them and sets this to 0.';
  end if;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '510: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    -- compared as sets: production lists them in another order than a local copy
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '510: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  if exists (select 1 from public.transfer_request_lines where extra_waiting_quantity <> 0) and v_col is null then
    raise exception '510: a line has units waiting straight after the column was added'; end if;

  perform set_config('search_path', v_path, true);
  perform set_config('lock_timeout', v_lock, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
