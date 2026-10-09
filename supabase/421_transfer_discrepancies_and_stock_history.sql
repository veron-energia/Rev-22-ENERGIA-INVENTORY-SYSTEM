-- 421_transfer_discrepancies_and_stock_history.sql
--
-- WHAT WAS WRONG (the audit of 9 Oct 2026: STOCK-M2, STOCK-11, STOCK-14
-- item 2, STOCK-15, and the transfer part of X-9 / STOCK-1)
--
--   Resolve Discrepancy acted at the wrong place (STOCK-M2). "Correct source
--   stock" and "Return excess to source" moved stock at the transfer's header
--   source. Since an approver chooses where each line comes from, a line can
--   be sent from somewhere else: on production on 9 Oct 2026, 3 of the 18
--   transfers with allocations had a line sent from another place than the
--   header. Resolving such a line gave the header place units it never sent,
--   and left the real source wrong. With no header source, "Return excess"
--   took the units off the destination and wrote no movement at all. On a
--   line with extra units, "Create linked inventory adjustment" changed no
--   stock but wrote a movement of those units arriving. Neither option has
--   been used (accept_loss twice, accept_surplus once, nothing open today).
--
--   Taking extra units off a place that no longer holds them (they were sold)
--   failed with "Stock cannot go negative (only confirmed TikTok sales ...)"
--   at a store, or a raw check-constraint error at a warehouse (STOCK-11).
--
--   A transfer's note could not be cleared (STOCK-14 item 2): the edit kept
--   the old note whenever the new one was empty.
--
--   Stock History said "Older transfer movements have no exact transfer link"
--   for any period, October included, for the 23 products with dispatches
--   from before stock history began (STOCK-15): it counted every unlinked
--   dispatch before the end of the period. The transfer integrity report
--   listed the 28 lines of those 15 transfers (30 Jul to 7 Sep, 193 units, no
--   source allocation) as errors. All 28 are before the observation start
--   (10 Sep 2026, 15:00 UTC); none is after it.
--
--   A member of staff who works at two stores and sent a transfer request
--   with no store had it sent to the store they were assigned to first
--   (STOCK-1, the transfer part of X-9). The page sent that store itself;
--   the page is fixed beside this, and the server now refuses the gap.
--
-- THE RULES
--
--   1. "Correct source stock" and "Return excess to source" act where the
--      line was sent from: its own source allocation. A line sent from
--      several places is refused for these two ("This line came from several
--      places; accept it, or record an adjustment at the right place"). A
--      line with no allocation (from before allocations) uses the transfer's
--      source, as before; with none there either, both are refused.
--   2. Before units are taken off a place, its row is locked and checked. If
--      it holds fewer than the extra units, the resolution is refused with a
--      plain message naming the place and the numbers.
--   3. "Create linked inventory adjustment" adds missing units at the
--      destination, as before. It is refused on a line with extra units,
--      where it changed nothing but wrote a movement.
--   4. A transfer's note: left out (null) keeps it; sent empty (or only
--      spaces, tabs or line breaks) clears it; anything else replaces it,
--      trimmed of spaces, tabs and line breaks at both ends. A
--      store-to-warehouse return keeps its required reason (unchanged: an
--      empty reason is still refused).
--   5. A staff transfer request with no store: a person who works at one
--      store gets that store, as before; someone at two or more is asked to
--      choose ("Choose which store this request is for.").
--   6. Stock History warns about unlinked transfer dispatches only when one
--      falls inside the period. Every one on production is from before the
--      observation start, so the warning now shows only for periods that
--      start before then, where the opening balance is already unknown.
--   7. The integrity report lists a line sent before the observation start
--      with no source allocation as 'legacy_unallocated_dispatch', severity
--      'info', not as an error. The same gap after that date stays an error,
--      and so does a line with no dispatch time (none on production), so no
--      line drops out of the report. Production after this: 0 such errors,
--      28 info lines on 15 transfers (193 units), as read on 9 Oct 2026.
--
-- WHAT THIS DOES
--
--   * resolve_transfer_discrepancy(uuid,jsonb,text) (replaced whole; grants
--     kept): rules 1 to 3. The movement notes are unchanged, so
--     stock_history_effect still scores every resolution. The audit row also
--     names the source used, when one was.
--   * edit_transfer_request(...) (patched; grants kept): rule 4, and the edit
--     history records the note as saved.
--   * create_staff_transfer_request(jsonb,text,uuid) (patched; grants kept):
--     rule 5. "One store" is one of the stores my_assigned_stores() lists (a
--     live store), the list the page shows.
--   * stock_history_table(jsonb,integer,integer,timestamptz) (patched; grants
--     kept): rule 6. The warning text is unchanged.
--   * stock_private_report_transfer_stock_integrity() (patched; grants kept,
--     the service role's alone): rule 7. report_transfer_stock_integrity()
--     reads it unchanged.
--
-- NOT CHANGED
--
--   * Who may do what: Owners and Managers resolve discrepancies; requesters,
--     Owners and Managers edit pending transfers; only Staff raise staff
--     requests. Every function keeps its arguments, results and grants.
--   * Accept loss, Accept surplus, Other, and Correct destination on a line
--     with missing units. Receiving, dispatch, review and rejection.
--   * No table, column, index, constraint or row. The 28 legacy lines stay as
--     they are; they are only reported differently.
--   * my_assigned_store_id() and its other callers (exchanges, TikTok and
--     therapy are their own batches).
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. Every
--   check is made and every new text built before anything is installed:
--     * each changed function is the production version read on 9 Oct 2026
--       (BEFORE), or already this migration's (AFTER), which is left alone, so
--       a re-run changes nothing;
--     * the functions relied on are the versions read on 9 Oct 2026, and
--       transfer_line_sources and stock_history_observation have the columns
--       read that day;
--     * no other function takes any of the changed names (the API picks an
--       overload by name);
--     * every anchor occurs exactly once, and each text built has its AFTER
--       md5 before it is installed.
--   The texts are executed as CREATE OR REPLACE with the same arguments and
--   result types, which keeps owner and grants. The definitions are read and
--   compared with the search path set to public. Afterwards every function
--   has its AFTER md5 and the grants it had. Then, inside a block that is
--   always undone, with made-up people, stores, warehouses and a product
--   (@sig.invalid, names starting "421 check"): a line sent from another
--   warehouse than the header is corrected at that warehouse; extra units
--   already sold are refused with the plain message, then returned to the
--   line's source; the adjustment is refused on extra units; a line from two
--   places is refused; a note is kept, is not changed by tabs and line
--   breaks round it, then is cleared; a member of staff at
--   two stores is asked to choose; the integrity report and Stock History
--   treat a dispatch from before the observation start as described, and a
--   line with no dispatch time stays an error in the report. Nothing
--   is printed and no row remains.
--
-- BEFORE (production, 9 Oct 2026, after 413; md5 of pg_get_functiondef,
-- search_path public):
--   changed
--   resolve_transfer_discrepancy(uuid,jsonb,text)                  8b387cbec43f41fc64406ed3a901c7cb
--   edit_transfer_request(uuid,integer,text,location_type,uuid,location_type,uuid,jsonb,text)
--                                                                  b150a0ce6de9584ef344e6ee1730a66b
--   create_staff_transfer_request(jsonb,text,uuid)                 1dd8c2ee3e45c340c0378d4f61338b07
--   stock_history_table(jsonb,integer,integer,timestamp with time zone)
--                                                                  52c71fac2ccaa5b6e580476871555fae
--   stock_private_report_transfer_stock_integrity()                b9980473a9722b64094ddfd5413fea23
--   relied on, not changed
--   stock_history_effect(uuid,text)                                fba6f63412970dbf6ac83e567c4d85e2
--   stock_history_location_name(text,uuid)                         559c810b99da9a4fc0e0b4152be90b6e
--   my_assigned_stores()                                           9aea3b976867b849e4c879dd5151d84b
--   is_owner_or_manager()                                          125dec10ce33b84ff5fb40a9bd455235
--   review_and_dispatch_transfer(uuid,jsonb,text)                  6db84d9ecca1d40b4858b4291401fbc0
--   receive_transfer(uuid,jsonb,text,boolean)                      04be775f33e550da46a7ed8054b359ce
--   report_transfer_stock_integrity()                              6b9c59a87b084d49a8f981da354ce455
--   read, not relied on: reject_transfer(uuid,text) 78942901accf9c2c6b49e48432833f33
--   (the page now words a rejection itself), cancel_transfer_request(uuid)
--   b12baadcf077487a6c275877275c4750 (Owners and Managers may cancel any
--   pending request; the page now offers it).
--   public function fingerprint (production after 413)             675ac22c631079b58f06813d0d463fa3
-- AFTER (for later guards):
--   resolve_transfer_discrepancy(uuid,jsonb,text)                  9b526acc4fbf00839c9ef4acd5af7856
--   edit_transfer_request(...)                                     d9cec0b343afaea0171952cbcda80b61
--   create_staff_transfer_request(jsonb,text,uuid)                 cc32ec91b2e223c67da957dd792af12e
--   stock_history_table(...)                                       8f7783f4c5731fb409ad61744dfd1c55
--   stock_private_report_transfer_stock_integrity()                7e7d4acdae67439d64079dbe357ad971
--
-- DEPLOY ORDER: this, then the Transfers page (pushing to main deploys it).
-- The page live now keeps working against this: it never sends a staff
-- request without a store, its edit sends the old note when unchanged, and
-- the two options it offers on a line from several places, or the adjustment
-- on extra units, are refused with the reason. The new page against a
-- database without this hides those options and asks two-store staff to
-- choose a store; its "clear the note" would be stored as an empty note.
--
-- 421 goes before 430 (B17), which changes is_owner_or_manager(). After 430,
-- 421 refuses to re-run (is_owner_or_manager() is one of the functions it
-- relies on). Re-guard it against 430's md5 rather than re-applying it. The
-- tests below apply 421 only while its functions are still at BEFORE, so they
-- keep running after 421 and 430 are live.
--
-- Test: scripts/transfers/tests/discrepancy-sources.sql (rules 1 to 5, a
-- re-run, the grants), scripts/stock-history/tests/database.sql (rules 6 and
-- 7), scripts/transfers/tests/store-to-warehouse.sql and
-- scripts/stock-history/tests/lifecycle.sql (unchanged behaviour; on a
-- database after 339 lifecycle stops at its call of the revoked
-- report_transfers_in_transit, with or without 421),
-- scripts/permissions/tests/function-grants.sql and
-- scripts/permissions/tests/staff-only-functions.sql; the page:
-- scripts/transfers/tests/transfers-page.test.mjs.

set lock_timeout = '5s';

do $mig$
declare
  -- ── resolve_transfer_discrepancy: replaced whole (rules 1 to 3) ──────────
  c_resolve_def constant text := $def$CREATE OR REPLACE FUNCTION public.resolve_transfer_discrepancy(p_request_id uuid, p_resolutions jsonb, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_req public.transfer_requests%rowtype; v_e jsonb; v_l public.transfer_request_lines%rowtype;
  v_line_id uuid; v_res text; v_reason text; v_diff integer; v_mag integer; v_unresolved integer;
  v_src_wh uuid; v_dst_wh uuid; v_src_st uuid; v_dst_st uuid;
  v_sources integer; v_from_type public.location_type; v_from_id uuid; v_from_wh uuid; v_from_st uuid; v_have integer;
begin
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can resolve transfer discrepancies'; end if;
  select * into v_req from public.transfer_requests where id=p_request_id for update;
  if not found then raise exception 'Transfer not found'; end if;
  if v_req.status<>'received_with_discrepancy' then raise exception 'This transfer has no unresolved receipt discrepancy'; end if;
  v_src_wh:=case when v_req.source_type='warehouse' then v_req.source_id end;
  v_src_st:=case when v_req.source_type='store' then v_req.source_id end;
  v_dst_wh:=case when v_req.dest_type='warehouse' then v_req.dest_id end;
  v_dst_st:=case when v_req.dest_type='store' then v_req.dest_id end;

  for v_e in select * from jsonb_array_elements(coalesce(p_resolutions,'[]'::jsonb)) loop
    v_line_id:=nullif(v_e->>'line_id','')::uuid;
    if v_line_id is not null then
      select * into v_l from public.transfer_request_lines where id=v_line_id and transfer_request_id=p_request_id for update;
    else
      select * into v_l from public.transfer_request_lines where transfer_request_id=p_request_id and product_id=nullif(v_e->>'product_id','')::uuid for update;
    end if;
    if not found then raise exception 'Transfer discrepancy line not found'; end if;
    if coalesce(v_l.discrepancy_quantity,0)=0 or v_l.discrepancy_resolved_at is not null then continue; end if;
    v_res:=coalesce(nullif(v_e->>'resolution',''),'other'); v_reason:=nullif(btrim(coalesce(v_e->>'reason','')),'');
    if v_res='other' and v_reason is null then raise exception 'A reason is required for an Other resolution'; end if;
    v_diff:=v_l.discrepancy_quantity; v_mag:=abs(v_diff);

    -- 421: "Return excess" and "Correct source" act where this line was sent
    -- from: its own source allocation, not the transfer's header (an approver
    -- may source a line elsewhere). A line sent from several places is refused.
    -- A line with no allocation (from before allocations) uses the header.
    v_from_type:=null; v_from_id:=null; v_from_wh:=null; v_from_st:=null;
    if v_l.line_kind<>'manual' and ((v_res='return_excess' and v_diff>0) or v_res='correct_source') then
      select count(*) into v_sources
        from (select distinct s.source_type,s.source_id from public.transfer_line_sources s where s.line_id=v_l.id) x;
      if v_sources>1 then
        raise exception 'This line came from several places; accept it, or record an adjustment at the right place'; end if;
      if v_sources=1 then
        select s.source_type,s.source_id into v_from_type,v_from_id from public.transfer_line_sources s where s.line_id=v_l.id limit 1;
      else
        v_from_type:=v_req.source_type; v_from_id:=v_req.source_id;
      end if;
      if v_from_type is null or v_from_id is null then
        raise exception 'This line has no recorded source; accept it, or record an adjustment at the right place'; end if;
      v_from_wh:=case when v_from_type='warehouse' then v_from_id end;
      v_from_st:=case when v_from_type='store' then v_from_id end;
    end if;

    -- 421: before taking units off a place, lock its row and check it still
    -- holds them, so the message is plain rather than a stock-rule error.
    if v_l.line_kind<>'manual' and v_diff>0 and v_res in ('return_excess','correct_destination') then
      if v_req.dest_type='warehouse' then
        select current_qty into v_have from public.warehouse_inventory where warehouse_id=v_req.dest_id and product_id=v_l.product_id for update;
      else
        select current_qty into v_have from public.store_inventory where store_id=v_req.dest_id and product_id=v_l.product_id for update;
      end if;
      if coalesce(v_have,0)<v_mag then
        raise exception 'Only % of the % extra units are still at %. Accept the extra as surplus, or record a stock adjustment there.',
          greatest(coalesce(v_have,0),0),v_mag,public.stock_history_location_name(v_req.dest_type::text,v_req.dest_id); end if;
    elsif v_l.line_kind<>'manual' and v_diff>0 and v_res='correct_source' then
      if v_from_type='warehouse' then
        select current_qty into v_have from public.warehouse_inventory where warehouse_id=v_from_id and product_id=v_l.product_id for update;
      else
        select current_qty into v_have from public.store_inventory where store_id=v_from_id and product_id=v_l.product_id for update;
      end if;
      if coalesce(v_have,0)<v_mag then
        raise exception '% holds only %, so the % extra units cannot be taken off there. Accept the extra as surplus, or record a stock adjustment there.',
          public.stock_history_location_name(v_from_type::text,v_from_id),greatest(coalesce(v_have,0),0),v_mag; end if;
    end if;

    if v_l.line_kind='manual' then
      if v_res not in ('accept_loss','accept_surplus','other') then
        raise exception 'Manual/non-inventory discrepancies are acknowledgement-only and cannot change inventory';
      end if;
    elsif v_res='return_excess' then
      if v_diff<=0 then raise exception 'Return excess applies only when more was received than approved'; end if;
      if v_req.dest_type='warehouse' then update public.warehouse_inventory set current_qty=current_qty-v_mag,updated_at=now() where warehouse_id=v_req.dest_id and product_id=v_l.product_id;
      else update public.store_inventory set current_qty=current_qty-v_mag,updated_at=now() where store_id=v_req.dest_id and product_id=v_l.product_id; end if;
      if v_from_type='warehouse' then insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values(v_from_id,v_l.product_id,v_mag)
        on conflict(warehouse_id,product_id) do update set current_qty=public.warehouse_inventory.current_qty+v_mag,updated_at=now();
      else insert into public.store_inventory(store_id,product_id,current_qty) values(v_from_id,v_l.product_id,v_mag)
        on conflict(store_id,product_id) do update set current_qty=public.store_inventory.current_qty+v_mag,updated_at=now(); end if;
      insert into public.stock_movements(product_id,movement_type,from_warehouse_id,to_warehouse_id,from_store_id,to_store_id,quantity,notes,created_by,transfer_request_id,transfer_request_line_id)
      values(v_l.product_id,'transfer_discrepancy',v_dst_wh,v_from_wh,v_dst_st,v_from_st,v_mag,'Discrepancy: returned excess to source',auth.uid(),p_request_id,v_l.id);
    elsif v_res='correct_source' then
      if v_diff<0 then
        if v_from_type='warehouse' then insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values(v_from_id,v_l.product_id,v_mag)
          on conflict(warehouse_id,product_id) do update set current_qty=public.warehouse_inventory.current_qty+v_mag,updated_at=now();
        else insert into public.store_inventory(store_id,product_id,current_qty) values(v_from_id,v_l.product_id,v_mag)
          on conflict(store_id,product_id) do update set current_qty=public.store_inventory.current_qty+v_mag,updated_at=now(); end if;
      else
        if v_from_type='warehouse' then update public.warehouse_inventory set current_qty=current_qty-v_mag,updated_at=now() where warehouse_id=v_from_id and product_id=v_l.product_id;
        else update public.store_inventory set current_qty=current_qty-v_mag,updated_at=now() where store_id=v_from_id and product_id=v_l.product_id; end if;
      end if;
      insert into public.stock_movements(product_id,movement_type,from_warehouse_id,to_warehouse_id,from_store_id,to_store_id,quantity,notes,created_by,transfer_request_id,transfer_request_line_id)
      values(v_l.product_id,'transfer_discrepancy',v_from_wh,v_dst_wh,v_from_st,v_dst_st,v_mag,'Discrepancy: corrected source',auth.uid(),p_request_id,v_l.id);
    elsif v_res='correct_destination' then
      if v_diff>0 then
        if v_req.dest_type='warehouse' then update public.warehouse_inventory set current_qty=current_qty-v_mag,updated_at=now() where warehouse_id=v_req.dest_id and product_id=v_l.product_id;
        else update public.store_inventory set current_qty=current_qty-v_mag,updated_at=now() where store_id=v_req.dest_id and product_id=v_l.product_id; end if;
      else
        if v_req.dest_type='warehouse' then insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values(v_req.dest_id,v_l.product_id,v_mag)
          on conflict(warehouse_id,product_id) do update set current_qty=public.warehouse_inventory.current_qty+v_mag,updated_at=now();
        else insert into public.store_inventory(store_id,product_id,current_qty) values(v_req.dest_id,v_l.product_id,v_mag)
          on conflict(store_id,product_id) do update set current_qty=public.store_inventory.current_qty+v_mag,updated_at=now(); end if;
      end if;
      insert into public.stock_movements(product_id,movement_type,to_warehouse_id,to_store_id,quantity,notes,created_by,transfer_request_id,transfer_request_line_id)
      values(v_l.product_id,'transfer_discrepancy',v_dst_wh,v_dst_st,v_mag,'Discrepancy: corrected destination to approved qty',auth.uid(),p_request_id,v_l.id);
    elsif v_res='inventory_adjustment' then
      -- 421: it adds missing units at the destination. On a line with extra
      -- units it changed no stock but wrote a movement of them arriving.
      if v_diff>0 then
        raise exception 'A linked inventory adjustment only adds missing units. For extra units, accept them as surplus, return them to the source, or correct the destination stock.'; end if;
      if v_req.dest_type='warehouse' then insert into public.warehouse_inventory(warehouse_id,product_id,current_qty) values(v_req.dest_id,v_l.product_id,v_mag)
        on conflict(warehouse_id,product_id) do update set current_qty=public.warehouse_inventory.current_qty+v_mag,updated_at=now();
      else insert into public.store_inventory(store_id,product_id,current_qty) values(v_req.dest_id,v_l.product_id,v_mag)
        on conflict(store_id,product_id) do update set current_qty=public.store_inventory.current_qty+v_mag,updated_at=now(); end if;
      insert into public.stock_movements(product_id,movement_type,to_warehouse_id,to_store_id,quantity,notes,created_by,transfer_request_id,transfer_request_line_id)
      values(v_l.product_id,'inventory_adjustment',v_dst_wh,v_dst_st,v_mag,'Discrepancy: linked inventory adjustment ('||coalesce(v_reason,'no note')||')',auth.uid(),p_request_id,v_l.id);
    elsif v_res in ('accept_loss','accept_surplus','other') then null;
    else raise exception 'Unknown discrepancy resolution: %',v_res;
    end if;

    update public.transfer_request_lines set discrepancy_resolution=v_res,discrepancy_reason=coalesce(v_reason,discrepancy_reason),discrepancy_resolved_at=now() where id=v_l.id;
    perform public.write_audit_ex('transfer_request_lines',v_l.id,'transfer_discrepancy_resolved',jsonb_build_object('discrepancy',v_diff),
      jsonb_build_object('resolution',v_res,'reason',v_reason,'manual',v_l.line_kind='manual')
        ||case when v_from_id is not null then jsonb_build_object('source_type',v_from_type,'source_id',v_from_id) else '{}'::jsonb end,
      'transfers',coalesce(v_reason,p_note),coalesce(v_dst_st,v_src_st));
  end loop;

  select count(*) into v_unresolved from public.transfer_request_lines where transfer_request_id=p_request_id and coalesce(discrepancy_quantity,0)<>0 and discrepancy_resolved_at is null;
  if v_unresolved=0 then
    update public.transfer_requests set discrepancy_resolved=true,status='completed'::public.approval_status,completed_at=now() where id=p_request_id;
    perform public.write_audit_ex('transfer_requests',p_request_id,'transfer_discrepancy_all_resolved',null,jsonb_build_object('resolved',true),'transfers',p_note,coalesce(v_dst_st,v_src_st));
  end if;
  return jsonb_build_object('success',true,'completed',v_unresolved=0,'remaining',v_unresolved);
end
$function$
$def$;

  -- ── edit_transfer_request: the note can be cleared (rule 4) ──────────────
  c_edit_decl_a constant text := $q$  v_snapshot jsonb; v_summary jsonb := '{}'::jsonb;
$q$;
  c_edit_decl_r constant text := $q$  v_snapshot jsonb; v_summary jsonb := '{}'::jsonb; v_new_note text;
$q$;
  c_edit_note_a constant text := $q$  if coalesce(p_note,v_req.note) is distinct from v_req.note then
    v_summary := v_summary || jsonb_build_object('note',jsonb_build_object('from',v_req.note,'to',p_note)); end if;
$q$;
  c_edit_note_r constant text := $q$  -- 421: a note left out (null) is kept; one sent empty clears it; anything
  -- else replaces it, with spaces, tabs and line breaks trimmed off both ends.
  -- A return's required reason is checked above.
  v_new_note := case when p_note is null then v_req.note
                     when p_note !~ '[^[:space:]]' then null
                     when regexp_replace(p_note, '^[[:space:]]+|[[:space:]]+$', '', 'g')
                          = regexp_replace(coalesce(v_req.note,''), '^[[:space:]]+|[[:space:]]+$', '', 'g') then v_req.note
                     else regexp_replace(p_note, '^[[:space:]]+|[[:space:]]+$', '', 'g') end;
  if v_new_note is distinct from v_req.note then
    v_summary := v_summary || jsonb_build_object('note',jsonb_build_object('from',v_req.note,'to',v_new_note)); end if;
$q$;
  c_edit_set_a constant text := $q$note=coalesce(p_note,note),version=version+1$q$;
  c_edit_set_r constant text := $q$note=v_new_note,version=version+1$q$;

  -- ── create_staff_transfer_request: two stores, choose one (rule 5) ───────
  c_staff_a constant text := $q$  else
    v_store_id := public.my_assigned_store_id();
  end if;
$q$;
  c_staff_r constant text := $q$  else
    -- 421: with no store chosen, only someone who works at one store has an
    -- obvious one. Someone at two or more stores must choose (it used to go
    -- to the store they were assigned to first).
    if (select count(*) from public.my_assigned_stores()) > 1 then
      raise exception 'Choose which store this request is for.';
    end if;
    v_store_id := (select s.store_id from public.my_assigned_stores() s);
  end if;
$q$;

  -- ── stock_history_table: unlinked dispatches inside the period (rule 6) ─
  c_table_a constant text := $q$  count(*) filter(where q.transfer_request_id is null) unlinked from (
  select sm.quantity,sm.transfer_request_id,
$q$;
  c_table_r constant text := $q$  -- 421: unlinked dispatches inside the period only. All are from before stock
  -- history began, so this warns only for periods that start before then.
  count(*) filter(where q.transfer_request_id is null and q.recorded_at>=first_at) unlinked from (
  select sm.quantity,sm.transfer_request_id,coalesce(sm.stock_history_recorded_at,sm.created_at) recorded_at,
$q$;

  -- ── the integrity report: legacy lines are info (rule 7) ─────────────────
  c_report_a constant text := $q$    from line_base b where b.line_kind='product' and b.status in ('in_transit','received','received_with_discrepancy','completed') and b.allocated<>coalesce(b.in_transit_quantity,0)
  union all
$q$;
  c_report_r constant text := $q$    from line_base b where b.line_kind='product' and b.status in ('in_transit','received','received_with_discrepancy','completed') and b.allocated<>coalesce(b.in_transit_quantity,0)
     and not coalesce(b.allocated=0 and b.dispatched_at<(select o.started_at from public.stock_history_observation o),false)
  union all
  -- 421: a line sent before stock history began with no source allocation came
  -- from the older dispatch path. It stays as history: listed, not an error.
  select 'legacy_unallocated_dispatch','info',b.request_id,b.line_id,b.product_id,null::text,null::uuid,
         coalesce(b.in_transit_quantity,0),b.allocated,'Sent before stock history began, with no source allocation recorded. Kept as history.'
    from line_base b where b.line_kind='product' and b.status in ('in_transit','received','received_with_discrepancy','completed') and b.allocated<>coalesce(b.in_transit_quantity,0)
     and b.allocated=0 and b.dispatched_at<(select o.started_at from public.stock_history_observation o)
  union all
$q$;

  c_resolve_after constant text := '9b526acc4fbf00839c9ef4acd5af7856';
  c_edit_after constant text := 'd9cec0b343afaea0171952cbcda80b61';
  c_staff_after constant text := 'cc32ec91b2e223c67da957dd792af12e';
  c_table_after constant text := '8f7783f4c5731fb409ad61744dfd1c55';
  c_report_after constant text := '7e7d4acdae67439d64079dbe357ad971';

  c_changed constant text[] := array[
    'resolve_transfer_discrepancy(uuid,jsonb,text)',
    'edit_transfer_request(uuid,integer,text,location_type,uuid,location_type,uuid,jsonb,text)',
    'create_staff_transfer_request(jsonb,text,uuid)',
    'stock_history_table(jsonb,integer,integer,timestamp with time zone)',
    'stock_private_report_transfer_stock_integrity()'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  r record; d text; v text; n int; k int; i int; v_bad text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[];
  -- the behaviour check
  v_owner uuid; v_staff uuid; v_tag text; v_s1 uuid; v_s2 uuid; v_w1 uuid; v_w2 uuid; v_p uuid;
  v_r uuid; v_l uuid; v_r2 uuid; v_l2 uuid; v_obs timestamptz; v_x jsonb;
begin
  -- The definitions are read and compared with public alone on the search
  -- path, as they were read on 9 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── Guards, anchors and new texts: nothing is installed unless all pass ────
  for r in select * from (values
    ('resolve_transfer_discrepancy(uuid,jsonb,text)', '8b387cbec43f41fc64406ed3a901c7cb', c_resolve_after,
     c_resolve_def, null::text[]),
    ('edit_transfer_request(uuid,integer,text,location_type,uuid,location_type,uuid,jsonb,text)',
     'b150a0ce6de9584ef344e6ee1730a66b', c_edit_after, null::text,
     array[[c_edit_decl_a, c_edit_decl_r], [c_edit_note_a, c_edit_note_r], [c_edit_set_a, c_edit_set_r]]),
    ('create_staff_transfer_request(jsonb,text,uuid)', '1dd8c2ee3e45c340c0378d4f61338b07', c_staff_after, null::text,
     array[[c_staff_a, c_staff_r]]),
    ('stock_history_table(jsonb,integer,integer,timestamp with time zone)', '52c71fac2ccaa5b6e580476871555fae',
     c_table_after, null::text, array[[c_table_a, c_table_r]]),
    ('stock_private_report_transfer_stock_integrity()', 'b9980473a9722b64094ddfd5413fea23', c_report_after, null::text,
     array[[c_report_a, c_report_r]])
  ) x(fn, before_md5, after_md5, whole, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '421: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '421: public.% is already this version; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '421: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    if r.edits is null then
      d := r.whole;
    else
      for k in 1 .. array_length(r.edits, 1) loop
        n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
        if n <> 1 then
          raise exception '421: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
        d := replace(d, r.edits[k][1], r.edits[k][2]);
      end loop;
    end if;
    if md5(d) <> r.after_md5 then
      raise exception '421: the text built for public.% is not the tested one (md5 %)', r.fn, md5(d); end if;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;

  -- Relied on, not changed: the versions read on 9 Oct 2026 (how Stock History
  -- scores a resolution's movement and names a place, the stores a member of
  -- staff works at, the Owner/Manager gate, how review writes a line's
  -- sources and the header's, receipt, and the report's wrapper).
  for r in select * from (values
    ('stock_history_effect(uuid,text)', 'fba6f63412970dbf6ac83e567c4d85e2'),
    ('stock_history_location_name(text,uuid)', '559c810b99da9a4fc0e0b4152be90b6e'),
    ('my_assigned_stores()', '9aea3b976867b849e4c879dd5151d84b'),
    ('is_owner_or_manager()', '125dec10ce33b84ff5fb40a9bd455235'),
    ('review_and_dispatch_transfer(uuid,jsonb,text)', '6db84d9ecca1d40b4858b4291401fbc0'),
    ('receive_transfer(uuid,jsonb,text,boolean)', '04be775f33e550da46a7ed8054b359ce'),
    ('report_transfer_stock_integrity()', '6b9c59a87b084d49a8f981da354ce455')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '421: public.% is missing or not the version read on 9 Oct 2026. Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;
  -- The tables read, as read on 9 Oct 2026.
  if (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), ',' order by a.attnum)
        from pg_attribute a where a.attrelid = 'public.transfer_line_sources'::regclass and a.attnum > 0 and not a.attisdropped)
     is distinct from 'id uuid,line_id uuid,source_type location_type,source_id uuid,quantity integer,created_by uuid,created_at timestamp with time zone' then
    raise exception '421: public.transfer_line_sources is not as read on 9 Oct 2026'; end if;
  if (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), ',' order by a.attnum)
        from pg_attribute a where a.attrelid = 'public.stock_history_observation'::regclass and a.attnum > 0 and not a.attisdropped)
     is distinct from 'id boolean,started_at timestamp with time zone'
     or not exists (select 1 from pg_constraint c where c.conrelid = 'public.stock_history_observation'::regclass
                     and c.contype = 'p') then
    raise exception '421: public.stock_history_observation is not the one-row table read on 9 Oct 2026'; end if;
  -- No other function takes these names (the API picks an overload by name).
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('resolve_transfer_discrepancy', 'edit_transfer_request', 'create_staff_transfer_request',
                                'stock_history_table', 'stock_private_report_transfer_stock_integrity')
              and p.oid::regprocedure::text <> all (c_changed)) then
    raise exception '421: another overload of a function this changes exists'; end if;
  -- The grants of the functions changed, to compare after.
  select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
    into v_acl
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = any (c_changed);

  -- ── Install ───────────────────────────────────────────────────────────────
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
  end loop;

  -- ── Installed exactly as tested, with the grants they had ─────────────────
  for r in select * from (values
    ('resolve_transfer_discrepancy(uuid,jsonb,text)', c_resolve_after),
    ('edit_transfer_request(uuid,integer,text,location_type,uuid,location_type,uuid,jsonb,text)', c_edit_after),
    ('create_staff_transfer_request(jsonb,text,uuid)', c_staff_after),
    ('stock_history_table(jsonb,integer,integer,timestamp with time zone)', c_table_after),
    ('stock_private_report_transfer_stock_integrity()', c_report_after)) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '421: installed with md5s other than the tested ones: %', v_bad; end if;
  if (select array_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
        from pg_proc p
       where p.pronamespace = 'public'::regnamespace and p.oid::regprocedure::text = any (c_changed))
     is distinct from v_acl then
    raise exception '421: the grants of the changed functions changed'; end if;
  -- The report stays the service role's alone; the others stay callable by
  -- signed-in staff (their own checks decide who may do what).
  if has_function_privilege('anon', 'public.stock_private_report_transfer_stock_integrity()', 'execute')
     or has_function_privilege('authenticated', 'public.stock_private_report_transfer_stock_integrity()', 'execute') then
    raise exception '421: the integrity report is callable by a client role'; end if;
  foreach v in array c_changed[1:4] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or not has_function_privilege('authenticated', 'public.' || v, 'execute') then
      raise exception '421: public.% is not callable by signed-in staff alone', v; end if;
  end loop;

  -- ── Behaviour, inside a block that is always undone ───────────────────────
  -- Made-up people (@sig.invalid), stores, warehouses and a product; nothing
  -- is printed and no row remains.
  begin
    -- Only the claims below name the caller (undone with the block).
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', '', true);
    insert into auth.users (id, email) values (gen_random_uuid(), '421-check-owner-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_owner;
    insert into auth.users (id, email) values (gen_random_uuid(), '421-check-staff-' || gen_random_uuid() || '@sig.invalid')
      returning id into v_staff;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '421 check', u.email, x.role::public.user_role, true
      from auth.users u join (values (v_owner, 'owner'), (v_staff, 'staff')) x(id, role) on x.id = u.id;
    v_tag := substr(md5(gen_random_uuid()::text), 1, 8);
    insert into public.stores (name, code, country_code) values ('421 check A ' || v_tag, '421A' || v_tag, 'SG') returning id into v_s1;
    insert into public.stores (name, code, country_code) values ('421 check B ' || v_tag, '421B' || v_tag, 'SG') returning id into v_s2;
    insert into public.warehouses (name, code) values ('421 check W1 ' || v_tag, '421W1' || v_tag) returning id into v_w1;
    insert into public.warehouses (name, code) values ('421 check W2 ' || v_tag, '421W2' || v_tag) returning id into v_w2;
    insert into public.products (name, sku, product_type) values ('421 check product', '421-P-' || v_tag, 'own') returning id into v_p;
    insert into public.store_product_prices (store_id, product_id, selling_price) values (v_s1, v_p, 10), (v_s2, v_p, 10);
    insert into public.user_store_assignments (user_id, store_id) values (v_staff, v_s1), (v_staff, v_s2);
    insert into public.warehouse_inventory (warehouse_id, product_id, current_qty) values (v_w1, v_p, 10), (v_w2, v_p, 10);
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);

    -- Rule 1: the header says W1; the line was sent from W2. Two arrive short.
    v_r := (public.create_transfer_request('warehouse_to_store', 'warehouse', v_w1, 'store', v_s1,
             jsonb_build_array(jsonb_build_object('product_id', v_p, 'quantity', 5)), null) ->> 'id')::uuid;
    select l.id into v_l from public.transfer_request_lines l where l.transfer_request_id = v_r;
    perform public.review_and_dispatch_transfer(v_r, jsonb_build_array(jsonb_build_object('line_id', v_l, 'approved_quantity', 5,
      'sources', jsonb_build_array(jsonb_build_object('source_type', 'warehouse', 'source_id', v_w2, 'quantity', 5)))), null);
    perform public.receive_transfer(v_r, jsonb_build_array(jsonb_build_object('line_id', v_l, 'received_quantity', 3)), '421 check: two short', false);
    perform public.resolve_transfer_discrepancy(v_r, jsonb_build_array(jsonb_build_object('line_id', v_l, 'resolution', 'correct_source')), null);
    if (select current_qty from public.warehouse_inventory where warehouse_id = v_w2 and product_id = v_p) <> 7
       or (select current_qty from public.warehouse_inventory where warehouse_id = v_w1 and product_id = v_p) <> 10
       or not exists (select 1 from public.stock_movements m where m.transfer_request_line_id = v_l
                       and m.notes = 'Discrepancy: corrected source' and m.from_warehouse_id = v_w2 and m.quantity = 2)
       or public.stock_history_effect((select m.id from public.stock_movements m where m.transfer_request_line_id = v_l
                                        and m.notes = 'Discrepancy: corrected source'), 'warehouse:' || v_w2) <> 2 then
      raise exception '421: Correct source did not act where the line was sent from'; end if;

    -- Rule 2: two extra arrive at store A, and all but one are sold.
    v_r := (public.create_transfer_request('warehouse_to_store', 'warehouse', v_w1, 'store', v_s1,
             jsonb_build_array(jsonb_build_object('product_id', v_p, 'quantity', 2)), null) ->> 'id')::uuid;
    select l.id into v_l from public.transfer_request_lines l where l.transfer_request_id = v_r;
    perform public.review_and_dispatch_transfer(v_r, jsonb_build_array(jsonb_build_object('line_id', v_l, 'approved_quantity', 2,
      'sources', jsonb_build_array(jsonb_build_object('source_type', 'warehouse', 'source_id', v_w2, 'quantity', 2)))), null);
    perform public.receive_transfer(v_r, jsonb_build_array(jsonb_build_object('line_id', v_l, 'received_quantity', 4)), '421 check: two extra', false);
    update public.store_inventory set current_qty = 1 where store_id = v_s1 and product_id = v_p;
    begin
      perform public.resolve_transfer_discrepancy(v_r, jsonb_build_array(jsonb_build_object('line_id', v_l, 'resolution', 'return_excess')), null);
      raise exception '421: Return excess took more than the store holds';
    exception when others then
      if sqlerrm not like 'Only 1 of the 2 extra units are still at 421 check A %' then raise; end if;
    end;
    -- Rule 3: no adjustment on extra units.
    begin
      perform public.resolve_transfer_discrepancy(v_r, jsonb_build_array(jsonb_build_object('line_id', v_l, 'resolution', 'inventory_adjustment')), null);
      raise exception '421: an adjustment was accepted on extra units';
    exception when others then
      if sqlerrm not like 'A linked inventory adjustment only adds missing units.%' then raise; end if;
    end;
    -- With the units back on the shelf, they go back to the line's source.
    update public.store_inventory set current_qty = 7 where store_id = v_s1 and product_id = v_p;
    perform public.resolve_transfer_discrepancy(v_r, jsonb_build_array(jsonb_build_object('line_id', v_l, 'resolution', 'return_excess')), null);
    if (select current_qty from public.store_inventory where store_id = v_s1 and product_id = v_p) <> 5
       or (select current_qty from public.warehouse_inventory where warehouse_id = v_w2 and product_id = v_p) <> 7
       or (select current_qty from public.warehouse_inventory where warehouse_id = v_w1 and product_id = v_p) <> 10
       or (select status::text from public.transfer_requests where id = v_r) <> 'completed' then
      raise exception '421: Return excess did not go back to the line''s source'; end if;

    -- Rule 1: a line sent from two places is refused for these two options.
    v_r := (public.create_transfer_request('warehouse_to_store', 'warehouse', v_w1, 'store', v_s1,
             jsonb_build_array(jsonb_build_object('product_id', v_p, 'quantity', 2)), null) ->> 'id')::uuid;
    select l.id into v_l from public.transfer_request_lines l where l.transfer_request_id = v_r;
    perform public.review_and_dispatch_transfer(v_r, jsonb_build_array(jsonb_build_object('line_id', v_l, 'approved_quantity', 2,
      'sources', jsonb_build_array(jsonb_build_object('source_type', 'warehouse', 'source_id', v_w1, 'quantity', 1),
                                   jsonb_build_object('source_type', 'warehouse', 'source_id', v_w2, 'quantity', 1)))), null);
    perform public.receive_transfer(v_r, jsonb_build_array(jsonb_build_object('line_id', v_l, 'received_quantity', 1)), '421 check: one short', false);
    begin
      perform public.resolve_transfer_discrepancy(v_r, jsonb_build_array(jsonb_build_object('line_id', v_l, 'resolution', 'correct_source')), null);
      raise exception '421: Correct source was accepted on a line from two places';
    exception when others then
      if sqlerrm <> 'This line came from several places; accept it, or record an adjustment at the right place' then raise; end if;
    end;

    -- Rule 4: a note left out stays; one sent empty clears it.
    v_r := (public.create_transfer_request('warehouse_to_store', 'warehouse', v_w1, 'store', v_s1,
             jsonb_build_array(jsonb_build_object('product_id', v_p, 'quantity', 1)), '421 check note') ->> 'id')::uuid;
    perform public.edit_transfer_request(v_r, null, '421 check', null, null, null, null, null, null);
    if (select note from public.transfer_requests where id = v_r) is distinct from '421 check note' then
      raise exception '421: an edit without a note lost the note'; end if;
    perform public.edit_transfer_request(v_r, null, '421 check tabs', null, null, null, null, null, E'\t421 check note \n');
    if (select note from public.transfer_requests where id = v_r) is distinct from '421 check note'
       or (select rv.changed_summary ? 'note' from public.transfer_request_revisions rv
            where rv.transfer_request_id = v_r and rv.reason = '421 check tabs') then
      raise exception '421: tabs and line breaks round the same note counted as a change'; end if;
    perform public.edit_transfer_request(v_r, null, '421 check', null, null, null, null, null, '');
    if (select note from public.transfer_requests where id = v_r) is not null then
      raise exception '421: an empty note did not clear the note'; end if;

    -- Rule 5: a member of staff at two stores chooses one.
    perform set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
    begin
      perform public.create_staff_transfer_request(jsonb_build_array(jsonb_build_object('product_id', v_p, 'quantity', 1)), null, null);
      raise exception '421: a two-store request with no store was accepted';
    exception when others then
      if sqlerrm <> 'Choose which store this request is for.' then raise; end if;
    end;
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);

    -- Rules 6 and 7: a dispatch from before the observation start (made here
    -- when the database has none, as a test copy may not).
    if not exists (select 1 from public.stock_history_observation) then
      insert into public.stock_history_observation (id, started_at) values (true, now() - interval '1 day'); end if;
    select o.started_at into v_obs from public.stock_history_observation o;
    insert into public.transfer_requests (transfer_type, source_type, source_id, dest_type, dest_id, status, requested_by, dispatched_at, received_at)
    values ('warehouse_to_store', 'warehouse', v_w1, 'store', v_s2, 'received', v_owner, v_obs - interval '2 days', v_obs - interval '2 days')
    returning id into v_r;
    insert into public.transfer_request_lines (transfer_request_id, line_kind, product_id, quantity, approved_quantity, in_transit_quantity, received_quantity, discrepancy_quantity)
    values (v_r, 'product', v_p, 3, 3, 3, 3, 0) returning id into v_l;
    insert into public.transfer_requests (transfer_type, source_type, source_id, dest_type, dest_id, status, requested_by, dispatched_at, received_at)
    values ('warehouse_to_store', 'warehouse', v_w1, 'store', v_s2, 'received', v_owner, now(), now())
    returning id into v_r2;
    insert into public.transfer_request_lines (transfer_request_id, line_kind, product_id, quantity, approved_quantity, in_transit_quantity, received_quantity, discrepancy_quantity)
    values (v_r2, 'product', v_p, 3, 3, 3, 3, 0) returning id into v_l2;
    if not exists (select 1 from public.stock_private_report_transfer_stock_integrity() x
                    where x.line_id = v_l and x.issue_type = 'legacy_unallocated_dispatch' and x.severity = 'info')
       or exists (select 1 from public.stock_private_report_transfer_stock_integrity() x where x.line_id = v_l and x.severity <> 'info')
       or not exists (select 1 from public.stock_private_report_transfer_stock_integrity() x
                       where x.line_id = v_l2 and x.issue_type = 'allocation_vs_in_transit_mismatch' and x.severity = 'error') then
      raise exception '421: the integrity report does not tell legacy lines from new ones'; end if;
    -- A line with no dispatch time is not taken for a legacy one.
    update public.transfer_requests set dispatched_at = null where id = v_r2;
    if not exists (select 1 from public.stock_private_report_transfer_stock_integrity() x
                    where x.line_id = v_l2 and x.issue_type = 'allocation_vs_in_transit_mismatch' and x.severity = 'error') then
      raise exception '421: a line with no dispatch time dropped out of the integrity report'; end if;
    insert into public.stock_movements (product_id, movement_type, from_warehouse_id, to_store_id, quantity, notes, created_by, created_at, stock_history_recorded_at)
    values (v_p, 'transfer_dispatch', v_w1, v_s2, 3, '421 check: unlinked dispatch', v_owner, v_obs - interval '2 days', v_obs - interval '2 days');
    v_x := public.stock_history_table(jsonb_build_object('from', public.sg_today(), 'to', public.sg_today(),
             'products', jsonb_build_array(v_p), 'locations', jsonb_build_array('store:' || v_s2))) -> 'rows' -> 0;
    if v_x is null or coalesce(v_x ->> 'warning', '') like '%no exact transfer link%' then
      raise exception '421: Stock History still warns about an old unlinked dispatch for today'; end if;
    v_x := public.stock_history_table(jsonb_build_object('from', ((v_obs - interval '3 days') at time zone 'Asia/Singapore')::date,
             'to', public.sg_today(), 'products', jsonb_build_array(v_p), 'locations', jsonb_build_array('store:' || v_s2))) -> 'rows' -> 0;
    if v_x is null or coalesce(v_x ->> 'warning', '') not like '%no exact transfer link%' then
      raise exception '421: Stock History no longer warns for a period holding an unlinked dispatch'; end if;

    raise exception using errcode = 'P0421', message = '421: check done, undone';
  exception when sqlstate 'P0421' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
