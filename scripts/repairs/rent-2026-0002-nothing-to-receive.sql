-- One-off repair: RENT-2026-0002 has nothing to come back.
--
-- Audit finding INVOICES-AFTER-7 (its data part). RENT-2026-0002 is the old-
-- style duplicate of RNT-2026-0003 that the Owner had closed on 6 Oct 2026
-- "as a duplicate, with no stock change" (one machine, paid once; RNT-2026-0003
-- was returned on 9 Sep 2026). Cancelling it left stock_returned false, so
-- rental_awaiting_return reads it as an item still with the customer, and the
-- "Cancelled, still with customer" lists 417 adds would show it. It never
-- took stock: no stock movement names it, it was never released from a
-- warehouse or a store, and it is on no invoice.
--
-- WHAT THIS DOES: marks it settled with no stock movement (stock_returned
-- true, its status stays cancelled, so no trigger moves stock) and adds a
-- note, with one audit row (rental_settled_no_stock).
--
-- SAFETY: one DO block, atomic. It refuses unless RENT-2026-0002 is still a
-- cancelled rental on no invoice, never released, named by no stock
-- movement, and RNT-2026-0003 is returned with its stock back. Already
-- settled by this: it says so and changes nothing. It prints numbers only.
--
-- RUN: once, after 417, as the database owner (the SQL editor, the MCP
-- execute_sql tool, or psql as postgres). NOT RUN YET.
-- Test (fixtures only): scripts/repairs/tests/rent-2026-0002-nothing-to-receive.sql.

do $repair$
declare r public.rentals%rowtype;
  c_note constant text := 'Nothing to receive: a duplicate of RNT-2026-0003 that never took stock (closed with no stock change, the Owner 6 Oct 2026; settled by the 417 repair).';
  v_path text := current_setting('search_path');
begin
  perform set_config('search_path', 'public', true);
  select * into r from public.rentals where rental_no = 'RENT-2026-0002' for update;
  if not found then raise exception 'RENT-2026-0002 is not there; nothing was changed'; end if;
  if r.stock_returned and position(c_note in coalesce(r.notes, '')) > 0 then
    raise notice 'RENT-2026-0002 is already settled; nothing changed';
    perform set_config('search_path', v_path, true);
    return;
  end if;
  if r.status::text <> 'cancelled' or coalesce(r.stock_returned, false) or r.invoice_id is not null
     or r.fulfilled_at is not null or r.source_store_id is not null then
    raise exception 'RENT-2026-0002 is no longer the cancelled duplicate found on 9 Oct 2026; nothing was changed'; end if;
  if exists (select 1 from public.stock_movements m where m.notes like '%RENT-2026-0002%') then
    raise exception 'A stock movement names RENT-2026-0002, so it did take stock; nothing was changed'; end if;
  if not exists (select 1 from public.rentals k where k.rental_no = 'RNT-2026-0003' and k.status::text = 'returned' and k.stock_returned) then
    raise exception 'RNT-2026-0003 is not returned with its stock back; nothing was changed'; end if;

  update public.rentals set stock_returned = true, notes = concat_ws(E'\n', notes, c_note) where id = r.id;
  perform public.write_audit_ex('rentals', r.id, 'rental_settled_no_stock',
    jsonb_build_object('status', r.status, 'stock_returned', r.stock_returned),
    jsonb_build_object('status', r.status, 'stock_returned', true, 'stock_moved', 0, 'duplicate_of', 'RNT-2026-0003'),
    'rentals', c_note, r.store_id);
  if public.rental_awaiting_return(r.id) then
    raise exception 'RENT-2026-0002 still reads as waiting to come back; nothing was changed'; end if;
  raise notice 'RENT-2026-0002 settled with no stock movement';
  perform set_config('search_path', v_path, true);
end $repair$;
