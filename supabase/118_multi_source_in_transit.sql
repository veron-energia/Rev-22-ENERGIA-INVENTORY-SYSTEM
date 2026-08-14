-- =====================================================================
-- ENERGIA — MULTI-SOURCE APPROVAL LEFT STOCK STRANDED IN TRANSIT
--
-- approve_transfer_multi() set approved_quantity but never in_transit_quantity.
-- The single-source approve_transfer() sets both:
--
--     set approved_quantity = v_qty, in_transit_quantity = v_qty
--
-- The Receive dialog lists lines where in_transit_quantity > 0, so after a
-- multi-source approval it found nothing and showed an empty list — while the
-- stock had genuinely left the source.
--
-- Reproduced before fixing: a request for 10 approved at 6 from one warehouse.
-- The warehouse dropped from 20 to 14, approved_quantity was 6, and
-- in_transit_quantity was NULL. Six units were in transit with no way to
-- receive them.
--
-- This affected EVERY multi-source approval, not only partial ones — a full
-- approval through that path was equally stuck.
--
-- The fix sets in_transit_quantity from what was actually dispatched, and
-- backfills any transfer already stranded.
--
-- Additive and idempotent. Run AFTER 117.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Set in_transit_quantity when dispatching.
--
--    Taken from the sum of the line's allocations, which is what physically
--    left, rather than from approved_quantity — the two are validated equal at
--    approval, and using the dispatched figure keeps this honest if that ever
--    changes.
-- ---------------------------------------------------------------------
do $patch$
declare v_def text; v_new text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'approve_transfer_multi';
  if v_def is null then raise exception 'approve_transfer_multi not found'; end if;
  if position('in_transit_quantity' in v_def) > 0 then
    raise notice 'approve_transfer_multi already sets in_transit_quantity'; return;
  end if;

  -- After the dispatch loop, before the status transition.
  v_new := replace(v_def,
    '  -- ---- 4. Same status transition the single-source path performs ----',
    '  -- ---- 3b. Mark what is in transit ----' || chr(10) ||
    '  -- Without this the Receive screen has nothing to list, even though the' || chr(10) ||
    '  -- stock has already left the source.' || chr(10) ||
    '  update public.transfer_request_lines l' || chr(10) ||
    '     set in_transit_quantity = coalesce((' || chr(10) ||
    '           select sum(ts.quantity)::integer from public.transfer_line_sources ts' || chr(10) ||
    '            where ts.line_id = l.id), 0)' || chr(10) ||
    '   where l.transfer_request_id = p_request_id;' || chr(10) || chr(10) ||
    '  -- ---- 4. Same status transition the single-source path performs ----');

  if position('in_transit_quantity' in v_new) = 0 then
    raise exception 'Could not set in_transit_quantity in approve_transfer_multi';
  end if;
  execute v_new;
  raise notice 'approve_transfer_multi now marks the dispatched quantity as in transit';
end $patch$;

-- ---------------------------------------------------------------------
-- 2. Rescue transfers already stranded by this.
--
--    Any approved, not-yet-received line that has allocations but no
--    in_transit_quantity was dispatched by the broken path. Its stock is out
--    there; this makes it receivable. Nothing else is touched, and the figure
--    comes from what was actually allocated.
-- ---------------------------------------------------------------------
do $$
declare v_n integer;
begin
  update public.transfer_request_lines l
     set in_transit_quantity = src.qty
    from (select ts.line_id, sum(ts.quantity)::integer as qty
            from public.transfer_line_sources ts
           group by ts.line_id) src
   where src.line_id = l.id
     and coalesce(l.in_transit_quantity, 0) = 0
     and coalesce(l.received_quantity, 0) = 0
     and src.qty > 0
     and exists (select 1 from public.transfer_requests r
                  where r.id = l.transfer_request_id
                    and r.status in ('approved','in_transit'));
  get diagnostics v_n = row_count;
  if v_n > 0 then
    raise notice 'Rescued % stranded transfer line(s) — they can now be received', v_n;
  else
    raise notice 'No stranded transfer lines found';
  end if;
end $$;

notify pgrst, 'reload schema';
