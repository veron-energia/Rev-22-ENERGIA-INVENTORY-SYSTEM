-- 364_transfers_work_again_and_stores_return_to_warehouses.sql
--
-- WHAT WAS WRONG (reported 26 Sep 2026)
--
-- 1. Every transfer an Owner or Manager created failed with "Could not choose
--    the best candidate function between: public.create_transfer_request(...
--    text ...), public.create_transfer_request(... location_type ...)".
--    Two functions of that name exist with the same parameter names: the
--    current one (159, text types) and the original (05, location_type). The
--    API server picks an overload by parameter NAMES only, and it does so
--    without looking at who may execute which, so the revoke in 348 changed
--    nothing. The last owner transfer that went through was on 7 Sep.
-- 2. Approving or receiving a transfer INTO a warehouse wrote the warehouse's
--    id into audit_logs.store_id, which references stores, so the whole
--    approval or receipt failed. No Warehouse -> Warehouse transfer could
--    finish (none ever has in production).
--
-- WHAT THIS CHANGES
--
--   1. The original create_transfer_request(text, location_type, ...) is
--      dropped. Nothing calls it: the app sends the current one's fields, SQL
--      callers resolve to the current one, and nothing depends on it.
--   2. review_and_dispatch_transfer / receive_transfer record the destination
--      store in the audit row, or, for a warehouse destination, the source store
--      (or none). A warehouse is never written as a store.
--   3. A new transfer type, store_to_warehouse: stock returned from a store to a
--      warehouse. As the owner decided:
--        * only an Owner or Manager may create one;
--        * it follows the same steps as every transfer: request, then an Owner
--          or Manager reviews and dispatches it (the stock leaves the store and
--          is in transit), then an Owner or Manager confirms receipt at the
--          warehouse (the stock arrives, all of it as sellable stock);
--        * a reason is required (spaces, tabs or line breaks alone are not
--          one), and an edit cannot blank it;
--        * the stock can only come from the store named on the request (the
--          review's source list and the dispatch both enforce it), and an edit
--          cannot turn it into anything but a store-to-warehouse return;
--        * any request from a store to a warehouse must be one: another label,
--          at creation or by an edit, is refused (none has ever existed in
--          production, 26 Sep 2026), so the rules above cannot be sidestepped;
--        * no destination price is needed (a warehouse sells nothing).
--
--   4. create_transfer_request refuses a request that does not say whether its
--      source and destination are a store or a warehouse. Left blank, the
--      staff store-access checks and the rules above were all skipped: staff
--      could request stock from a store they are not assigned to. The app
--      always sends both.
--
-- NOT CHANGED: the other three types, approval and receipt rules, reports,
-- discrepancy handling, and everything 159/272 check.
--
-- SAFETY: every patched function is guarded by the md5 of its production
-- version (26 Sep 2026) and by anchors that must occur the stated number of
-- times; a function already carrying "364:" is left alone. The drop is guarded
-- by the md5 of the dropped function, and the migration fails unless exactly
-- one create_transfer_request remains afterwards.

set lock_timeout = '5s';

-- ── 1. one create_transfer_request ──────────────────────────────────────────
do $mig$
declare v_md5 text;
begin
  if to_regprocedure('public.create_transfer_request(text,public.location_type,uuid,public.location_type,uuid,jsonb,text)') is not null then
    v_md5 := md5(pg_get_functiondef('public.create_transfer_request(text,public.location_type,uuid,public.location_type,uuid,jsonb,text)'::regprocedure));
    if v_md5 <> 'ca113bb0a4e22206bdee40586ccee3cf' then
      raise exception '364: the old create_transfer_request is not the version expected (md5 %)', v_md5; end if;
    drop function public.create_transfer_request(text, public.location_type, uuid, public.location_type, uuid, jsonb, text);
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'create_transfer_request') <> 1 then
    raise exception '364: expected exactly one create_transfer_request after the drop'; end if;
end $mig$;

-- ── 2 + 3. create: returns ──────────────────────────────────────────────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.create_transfer_request(text,text,uuid,text,uuid,jsonb,text)'::regprocedure);
  if position('364:' in d) > 0 then raise notice '364: create_transfer_request already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> 'b842f26488c8e58dd472d2c52692ab74' then
    raise exception '364: create_transfer_request is not the version this was tested against (md5 %)', v_md5; end if;
  a := $a$  if p_source_id is null or p_dest_id is null then raise exception 'Source and destination are required'; end if;
$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '364: create_transfer_request anchor found % times', n; end if;
  execute replace(d, a, a || $r$  -- 364: a transfer names what its source and destination are. Every
  -- location rule that follows, staff store access included, reads them; left
  -- blank, none of them applied.
  if v_src_type is null or v_dst_type is null then
    raise exception 'Say whether the source and destination are a store or a warehouse'; end if;
  -- 364: stock returned from a store to a warehouse. Owner or Manager only,
  -- from a store to a warehouse, and always with a reason. Any move from a
  -- store to a warehouse is a return, whatever it is labelled.
  if v_src_type = 'store' and v_dst_type = 'warehouse' and p_transfer_type is distinct from 'store_to_warehouse' then
    raise exception 'To send stock from a store to a warehouse, choose Store → Warehouse: it is a return, and needs a reason'; end if;
  if p_transfer_type = 'store_to_warehouse' then
    if not public.is_owner_or_manager() then
      raise exception 'Only an Owner or Manager can return stock from a store to a warehouse'; end if;
    if v_src_type is distinct from 'store' or v_dst_type is distinct from 'warehouse' then
      raise exception 'A store-to-warehouse return must go from a store to a warehouse'; end if;
    if coalesce(p_note, '') !~ '[^[:space:]]' then
      raise exception 'Give the reason for returning this stock to the warehouse'; end if;
  end if;
$r$);
end $mig$;

-- ── 3. edit: a return stays a return ────────────────────────────────────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.edit_transfer_request(uuid,integer,text,public.location_type,uuid,public.location_type,uuid,jsonb,text)'::regprocedure);
  if position('364:' in d) > 0 then raise notice '364: edit_transfer_request already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '8f5c465e22248ff7cddc10e16dd92139' then
    raise exception '364: edit_transfer_request is not the version this was tested against (md5 %)', v_md5; end if;
  a := $a$  if v_new_source_id is not null and v_new_source_type=v_new_dest_type and v_new_source_id=v_new_dest_id then raise exception 'Source and destination must be different'; end if;
$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '364: edit_transfer_request anchor found % times', n; end if;
  execute replace(d, a, a || $r$  -- 364: a store-to-warehouse return can move to another store or warehouse,
  -- but stays a return from a store to a warehouse, and keeps a reason. No
  -- other transfer can be edited into a move from a store to a warehouse.
  if v_req.transfer_type = 'store_to_warehouse' then
    if v_new_source_type is distinct from 'store' or v_new_dest_type is distinct from 'warehouse' then
      raise exception 'A store-to-warehouse return must stay from a store to a warehouse'; end if;
    if coalesce(p_note, v_req.note, '') !~ '[^[:space:]]' then
      raise exception 'Give the reason for returning this stock to the warehouse'; end if;
  elsif v_new_source_type = 'store' and v_new_dest_type = 'warehouse' then
    raise exception 'To send stock from a store to a warehouse, raise a Store → Warehouse return: it needs a reason'; end if;
$r$);
end $mig$;

-- ── 2 + 3. review and dispatch ──────────────────────────────────────────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.review_and_dispatch_transfer(uuid,jsonb,text)'::regprocedure);
  if position('364:' in d) > 0 then raise notice '364: review_and_dispatch_transfer already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> '400741800d2567c2846d0f467bd141f1' then
    raise exception '364: review_and_dispatch_transfer is not the version this was tested against (md5 %)', v_md5; end if;

  -- a return takes stock only from the store it was requested from
  a := $a$      if v_src.source_type=v_req.dest_type and v_src.source_id=v_req.dest_id then raise exception 'The destination cannot act as its own source'; end if;
$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '364: review_and_dispatch_transfer source anchor found % times', n; end if;
  d := replace(d, a, a || $r$      -- 364: a return takes stock only from the store it was requested from.
      if v_req.transfer_type = 'store_to_warehouse'
         and not (v_src.source_type = 'store' and v_src.source_id = v_req.source_id) then
        raise exception 'A return to a warehouse can only take stock from the store it was requested from'; end if;
$r$);

  -- the audit row names a store, never a warehouse
  a := $a$    'transfers',p_note,coalesce(v_dst_st,v_dst_wh));$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '364: review_and_dispatch_transfer audit anchor found % times', n; end if;
  d := replace(d, a, $r$    'transfers',p_note,
    -- 364: the audit row's store is a store: the destination store, or for a
    -- warehouse destination the source store (a warehouse id broke the insert).
    coalesce(v_dst_st, case when v_req.source_type = 'store' then v_req.source_id end));$r$);
  execute d;
end $mig$;

-- ── 2. receive ──────────────────────────────────────────────────────────────
do $mig$
declare d text; n int; v_md5 text; a text;
begin
  d := pg_get_functiondef('public.receive_transfer(uuid,jsonb,text,boolean)'::regprocedure);
  if position('364:' in d) > 0 then raise notice '364: receive_transfer already patched; left alone.'; return; end if;
  v_md5 := md5(d);
  if v_md5 <> 'b85019a8dec93ff99cc6828fe0402b8a' then
    raise exception '364: receive_transfer is not the version this was tested against (md5 %)', v_md5; end if;
  a := $a$'transfers',p_note,coalesce(v_dst_st,v_dst_wh));$a$;
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  if n <> 1 then raise exception '364: receive_transfer audit anchor found % times', n; end if;
  execute replace(d, a, $r$'transfers',p_note,
    -- 364: the audit row's store is a store, never a warehouse.
    coalesce(v_dst_st, case when v_req.source_type = 'store' then v_req.source_id end));$r$);
end $mig$;

-- ── 3. review's source lists: a return offers only its own store ────────────
do $mig$
declare f record; d text; n int; v_md5 text;
        a_wh text := $a$     and not (r.dest_type = 'warehouse' and r.dest_id = w.id)$a$;
        a_st text := $a$     and not (r.dest_type = 'store' and r.dest_id = s.id)$a$;
begin
  for f in select * from (values
      ('public.stock_private_transfer_request_sourcing(uuid)', '687bd280c4bc4f5a5876aacf7837f283'),
      ('public.stock_private_transfer_product_sourcing(uuid,uuid)', 'bf234bcd95b16751c048cc875e6fccfb')) v(sig, want)
  loop
    d := pg_get_functiondef(f.sig::regprocedure);
    if position('364:' in d) > 0 then raise notice '364: % already patched; left alone.', f.sig; continue; end if;
    v_md5 := md5(d);
    if v_md5 <> f.want then raise exception '364: % is not the version this was tested against (md5 %)', f.sig, v_md5; end if;
    n := (length(d) - length(replace(d, a_wh, ''))) / length(a_wh);
    if n <> 1 then raise exception '364: % warehouse anchor found % times', f.sig, n; end if;
    n := (length(d) - length(replace(d, a_st, ''))) / length(a_st);
    if n <> 1 then raise exception '364: % store anchor found % times', f.sig, n; end if;
    d := replace(d, a_wh, a_wh || $r$
     -- 364: a store-to-warehouse return is sourced from its own store only
     and r.transfer_type is distinct from 'store_to_warehouse'$r$);
    d := replace(d, a_st, a_st || $r$
     and (r.transfer_type is distinct from 'store_to_warehouse'
          or (r.source_type = 'store' and r.source_id = s.id))$r$);
    execute d;
  end loop;
end $mig$;

notify pgrst, 'reload schema';
