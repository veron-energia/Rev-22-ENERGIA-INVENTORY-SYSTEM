-- 399_part_paid_handover.sql
--
-- WHAT WAS WRONG (found 6 Oct 2026)
--
-- Stock leaves a store only when an invoice is paid in full: a part payment
-- records the money and nothing else ("money recorded, NOTHING activates, no
-- stock moves"). Customers often take goods home on a part-paid or even an
-- unpaid invoice and come back later to pay the rest, so:
--
--   * the shelf showed goods that had already gone, until the last payment;
--     staff covered the gap with stock adjustments that are not linked to the
--     invoice, and the final payment then took the same goods out a second
--     time (it cannot know they already went);
--   * nothing recorded what a customer took, when, or from whom: the printed
--     invoice said "GOODS AND SERVICES HAVE BEEN CHECKED AND COLLECTED" on
--     part-paid and unpaid invoices alike;
--   * the paths that do touch an open invoice's stock would mishandle such a
--     hand-over if one were recorded as a store_sale linked to the invoice:
--     Correct Invoice put every store_sale back on the shelf and then took
--     the whole corrected invoice out (no status gate), so a part-paid
--     invoice became "all collected" (it already did so for an invoice
--     reopened after a cancellation and corrected while unpaid: its old,
--     returned sale was enough to make the correction take every line before
--     any payment); Confirm FOC took the full required stock, not net of
--     anything already out; Delete Invoice soft-deleted an unpaid invoice
--     with goods out and no stock handling; and the warehouse-fulfilment
--     trigger takes every product line from the warehouse and gives the store
--     the same back, so goods handed over from the store would have been
--     counted out of both.
--
-- THE RULES (the Owner, 6 Oct 2026, final)
--
--   1. Whenever staff record a PART payment (less than the balance) on an
--      invoice that still has goods to collect, the payment form requires an
--      answer before it saves: "Nothing taken" or the products the customer
--      takes now (per product, up to what is still to collect, single
--      products inside promotions and picks included). The hand-over is saved
--      in the same transaction as the payment. Callers that do not send it
--      (website orders, exchanges, other paths) keep working.
--   2. A "Hand over items" button on any unpaid or part-paid invoice with
--      goods still to collect, for a later visit with no payment. Any staff
--      with access to the invoice's store, like Record Payment.
--   3. A hand-over is a store_sale movement from the invoice's store, linked
--      to the invoice, noted "Handed over before full payment — <invoice no>",
--      with an audit row and a hand-over record (header and lines, a request
--      id for retries, who and when). It is refused when the store is short
--      (as today) or the invoice is set to fulfil from a warehouse. Full
--      payment then takes only what was not handed over, and the guarantee
--      trigger finds nothing missing.
--   4. A correction that would remove or reduce a product already handed over
--      is refused, clearly, until those goods are recorded as returned or
--      written off: "Record items returned" on the invoice (Owner/Manager):
--      Good goes back into the store's stock with an invoice_cancel_return
--      movement; Damaged or Not returned is written off through the existing
--      dispositions. A correction that does not touch handed-over goods works
--      as today and never puts them back on the shelf.
--   5. Confirm FOC takes only what was not handed over; Delete Invoice refuses
--      while goods are out; warehouse fulfilment never counts goods twice.
--   6. The printed, PDF, image, WhatsApp and email copies of a part-paid or
--      unpaid invoice show Collected / To collect instead of the blanket line;
--      fully paid invoices keep it. (The page's.)
--   7. The invoice shows what was collected and what is still to collect;
--      the list shows "Goods out" on unpaid and part-paid invoices with goods
--      out. (The page's, from invoice_goods_status and
--      invoice_list_goods_out.)
--   8. No production data is changed (the invoices already part-paid or
--      unpaid on 6 Oct 2026 are left as they are).
--
-- WHAT THIS DOES
--
--   * invoice_handovers (header: invoice, store, kind 'handover' |
--     'nothing_taken' | 'return', source 'payment' | 'button' | 'return',
--     request_id unique with the hash of what was asked, the settlement's
--     request id when it came with a payment, reason, created_by, created_at),
--     invoice_handover_lines (a hand-over's products, each with the store_sale
--     movement it wrote) and invoice_handover_return_lines (what "Record
--     items returned" resolved: per hand-over movement, good / damaged / not
--     returned, with the invoice_cancel_return movement and the disposition
--     it wrote). Row-level security: staff read the rows of their stores;
--     only these functions write.
--   * invoice_goods_out(invoice): per store_sale movement, what is still with
--     the customer and not yet returned or written off: the same netting as
--     restore_invoice_stock, record_invoice_stock_return and
--     refund_invoice_recorded (the movement, less invoice_cancel_return
--     movements pointing at it, less its dispositions). Internal.
--   * invoice_handover_internal(invoice, answer, request, source, settlement
--     request): rules 1 and 3. Locks the invoice; {"none": true} records
--     "Nothing taken"; {"items": [{"product_id", "qty"}]} takes each product
--     out of the invoice's store (refused when short), up to what
--     invoice_stock_to_deduct still has to collect (the figure full payment
--     takes), as a store_sale linked to the invoice with the note above.
--     The same request id and answer returns what it wrote; a different
--     answer is refused. Called with a part payment by
--     record_invoice_settlement (after its receipts, in its transaction) and
--     by the button. A settlement that paid the invoice in full skips it:
--     full payment took every item out already. Internal.
--   * record_invoice_handover(invoice, answer, request): the "Hand over items"
--     button (rule 2). Any active staff member with access to the invoice's
--     store. Granted to staff.
--   * record_invoice_goods_return(invoice, items, reason, request): "Record
--     items returned" (rule 4). Owner/Manager, on an unpaid or part-paid
--     invoice before full payment (a paid one goes through Refund / Cancel),
--     per product: good (back into the store it left, an
--     invoice_cancel_return pointing at the hand-over movement), damaged and
--     not returned (an invoice_stock_dispositions row, the existing
--     write-off). Spread over the product's movements oldest first.
--     Idempotent by request id. Granted to staff (it checks the role).
--   * invoice_goods_status(invoice): per product, required, collected, still
--     to collect, out with the customer and in the store, the promotions it
--     comes through, and the hand-over history. Read by the page and its
--     copies. Only an invoice before full payment has anything to collect: on
--     a paid, FOC, cancelled or refunded one "to collect" is 0 and
--     "collected" is what the customer is counted as having (after a
--     cancellation that put the goods back, 0). Granted to staff (store
--     access checked).
--   * invoice_list_goods_out(invoice ids): the list's "Goods out" badge.
--     Granted to staff (store access checked).
--   * invoice_goods_kept_check(invoice): refuses (GOODS_HANDED_OVER: ...)
--     when the lines no longer require a product the customer still has.
--     Internal.
--   * record_invoice_settlement: payload.handover, when present and not null,
--     goes to invoice_handover_internal after the receipts and arrangements;
--     its answer is returned as "handover". Without the key it is unchanged.
--   * invoice_before_full_payment(invoice): draft, unpaid or part-paid (or
--     a request waiting on one), not settled (locked_at, paid_at) since it
--     was opened or last reopened. An invoice paid in full and later
--     corrected up to part-paid released its goods when it was settled and
--     is not one. Internal.
--   * correct_invoice: an invoice before full payment holds no sale to put
--     back: any store_sale on it is goods the customer took early. So on
--     such an invoice restore_invoice_stock is not run (the goods stay out);
--     the store cannot change while goods are out (they left that store); the
--     corrected lines must keep every product the customer has, at least as
--     many as are out (invoice_goods_kept_check: reducing a product to no
--     fewer than the units out is allowed, those units stay on the invoice;
--     removing it or reducing below them is refused, naming them); and stock
--     is taken only when the correction leaves the invoice paid or completed
--     FOC, net (deduct_invoice_stock). Every other correction runs exactly as
--     before: a paid invoice's restore-then-deduct nets to the difference, as
--     it always did, and so does one paid in full and later corrected up to
--     part-paid (its goods left at that payment; a correction adding to it
--     still takes the added goods at once, as before).
--   * confirm_foc_invoice: a product's stock check and deduction are net of
--     what was handed over (invoice_stock_to_deduct); nothing is taken for a
--     product handed over in full. Vouchers as before.
--   * delete_invoice: refused while goods are out.
--   * set_invoice_fulfilment_warehouse: a warehouse cannot be chosen while
--     any of the invoice's goods count as with the customer from this store:
--     a store_sale less the invoice_cancel_return movements pointing at it
--     and its Good (sellable) and Damaged dispositions. That is the goods out
--     AND the units recorded as Not returned (the customer kept them, so
--     they count as collected: full payment does not take them again, while
--     the warehouse would send every line). Units back as Good or written off
--     as Damaged no longer count: the warehouse then sends the whole line and
--     the store keeps only the damaged write-off, which is right. Choosing
--     the store's stock again is always allowed.
--   * trg_fulfil_from_warehouse: the same test on the hand-over movements
--     (the payment's own deduction is on the invoice by then): refuses to
--     settle from a warehouse rather than count goods twice (a backstop: the
--     setter and the hand-over refuse the combination first).
--   * invoice_product_net_deducted (the guarantee trigger's figure, also
--     invoice_stock_gaps and invoice_stock_diagnostic): also takes off the
--     units "Record items returned" wrote off as Damaged. Those came back
--     before full payment and the invoice still owes the customer them, so a
--     settlement that does not run deduct_invoice_stock (Correct amount on a
--     payment, a correction of the header only, such as a manual discount)
--     now has the guarantee take the replacement; before, it counted the
--     damaged unit as delivered and the replacement never left the shelf.
--     Nothing else changes: other dispositions (a refund's, a cancellation's)
--     are not taken off, as before.
--
-- NOT CHANGED
--
--   * invoice_record_payments_internal, deduct_invoice_stock and the
--     guarantee trigger (ensure_invoice_stock_deducted, trg_guarantee_
--     invoice_stock): full payment already takes only what
--     invoice_stock_to_deduct says is still owed, which nets store_sale
--     movements of the invoice by product, so a hand-over is never taken
--     twice; the guarantee then finds nothing missing. Verified, not patched.
--   * The two "already deducted" figures are not merged, on purpose; for
--     everything a hand-over writes they agree.
--     invoice_stock_to_deduct (payment, deduct_invoice_stock, Confirm FOC
--     with 399) answers "what must still leave the store for the customer to
--     hold every unit the lines require", so it takes off returns of every
--     kind and damaged write-offs. invoice_product_net_deducted (the
--     guarantee trigger, invoice_stock_gaps, invoice_stock_diagnostic)
--     answers "has this sale been recorded", counting only cancellation
--     returns. A refund does not change an invoice's lines, so on a paid
--     invoice partly refunded with goods back the first says 1 still to take
--     and the second 0: switching the guarantee or the gaps report to the
--     first would show every such invoice as missing stock (and the
--     guarantee would take it again if the invoice became paid again);
--     switching payment to the second would not take again, when a reopened
--     invoice is paid, the units its cancellation wrote off as damaged.
--     For hand-overs they agree: a hand-over is a store_sale (both count
--     it), Good comes back as an invoice_cancel_return (both take it off),
--     Not returned stays a sale (neither takes it off), Damaged from "Record
--     items returned" is taken off by both (the second with the patch above,
--     limited to those write-offs), and full payment, by any path, ends with
--     both at zero. Only the dispositions of refunds and cancellations still
--     differ, as before 399.
--   * Cancel and refund. Both already list an invoice's store_sale movements
--     (hand-overs included) for Good / Damaged / Not returned
--     (invoice_action_plan, record_invoice_stock_return), a refund insists on
--     it, and a cancellation puts back whatever is still unresolved
--     (restore_invoice_stock). Tested with hand-overs, not patched.
--   * reopen_invoice (deducts only when it reopens to paid), Record Use, the
--     stock history (a hand-over shows as a Sale, its return as a cancelled
--     invoice's return), the reports, and limited vouchers (no hand-over:
--     production has none; they still leave at full payment).
--   * No data: invoices already part-paid or unpaid keep their figures;
--     nothing is moved or linked.
--
-- SAFETY
--
-- Apart from the lock timeout, the migration is one statement (a DO block),
-- so it is atomic however it is run. Every guard and anchor is checked, and
-- every patched text built, before anything is installed. md5(pg_get_
-- functiondef) of each patched function must be the production version read
-- on 6 Oct 2026 (BEFORE), or already this migration's version (AFTER), which
-- is left alone so a re-run changes nothing. The functions relied on but not
-- changed must be the versions read on 6 Oct 2026. A new function that
-- exists with any other text refuses. Every anchor must match exactly once.
-- Patches are executed as CREATE OR REPLACE, which keeps owner and grants.
-- The new internal functions are revoked from public, anon and authenticated
-- and granted to service_role (339); the four the page calls are granted to
-- authenticated and check access themselves. Tables, constraints, indexes and
-- policies are created only if missing. After installing, every function must
-- have its AFTER md5 and the grants are checked. No data changes.
--
-- BEFORE (production, 6 Oct 2026, md5 of pg_get_functiondef):
--   record_invoice_settlement(uuid,jsonb,uuid)               09c2e5e90c2ae018ffbbb90c60b60164
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)              978805ed25f2a44a6f6c5a5b94b10b3c
--   confirm_foc_invoice(uuid,text)                           0f1cb37a25666b0155553b127e05b208
--   delete_invoice(uuid)                                     abd48c36bfe712fbfba38742304fec7b
--   set_invoice_fulfilment_warehouse(uuid,uuid)              e4603b4444b003ae1adf0109bbd4faea
--   trg_fulfil_from_warehouse()                              5ecb3cb431e9e538d65310a3648a43b1
--   invoice_product_net_deducted(uuid,uuid)                  35544da14c1872413cc6da51cb9b7ae6
--   (relied on, not changed)
--   invoice_stock_to_deduct(uuid)                            6356494ccb8545d46c56b788f8f85f54
--   invoice_required_stock(uuid)                             83bb2e1f6f8d6cb5c9287a29b2df8cf8
--   deduct_invoice_stock(uuid,text)                          32183fe9e7c15ed0b11307c48289831a
--   invoice_record_payments_internal(uuid,jsonb)             5c2559f7cf4dbca5dec4fdd55d00ae34
--   ensure_invoice_stock_deducted(uuid,text)                 3c7ca7893f359f380a340cec07f21a1f
--   trg_guarantee_invoice_stock()                            b4d922c6238f50137941a85a590600c8
--   restore_invoice_stock(uuid,text)                         092316c3af22361f80d186e38fe49bf3
-- AFTER (for later guards):
--   record_invoice_settlement(uuid,jsonb,uuid)               8c8778af82899c6aaada62371d13802f
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)              5158303778516180bab171ba951d8385
--   confirm_foc_invoice(uuid,text)                           42a6bdb4a1a693c5c83a4fa601abc551
--   delete_invoice(uuid)                                     5b09daf60b404444618197c478842d4a
--   set_invoice_fulfilment_warehouse(uuid,uuid)              389eea0434e50337c9a90bc79937f5e2
--   trg_fulfil_from_warehouse()                              4abf4bf68e4f00658a8da66469e7059e
--   invoice_product_net_deducted(uuid,uuid)                  f6288d8eb44af4cd4dbed11f63d3427a
--   invoice_goods_out(uuid)                                  15ffed0ff0d5d9cc5685af8e834302ae
--   invoice_before_full_payment(uuid)                        532d7690367fc674737b20420e7fb16c
--   invoice_goods_kept_check(uuid)                           c79ebaa50a099564d1b2ccd63aea5444
--   invoice_handover_internal(uuid,jsonb,uuid,text,uuid)     51f5adaddbe447e8fcbeaabab03a054a
--   record_invoice_handover(uuid,jsonb,uuid)                 1132398e57a234deb60c972fc89a8ffa
--   record_invoice_goods_return(uuid,jsonb,text,uuid)        e1a3242f7bfc66fb4f6ea162d823137f
--   invoice_goods_status(uuid)                               651039eac932b5d1f51fc75313ed4320
--   invoice_list_goods_out(uuid[])                           6c9da48db53c8febe2cb7a7188740398
--
-- Test: scripts/invoices/tests/part-paid-handover.sql.

set lock_timeout = '5s';

do $mig$
declare
  -- ── New functions ──────────────────────────────────────────────────────────
  c_goods_out_def constant text := $def$
create or replace function public.invoice_goods_out(p_invoice_id uuid)
returns table(movement_id uuid, product_id uuid, store_id uuid, quantity integer, created_at timestamptz)
language sql
stable
security definer
set search_path = public
as $fn$
  -- 399: the goods of an invoice that are with the customer and not yet
  -- returned or written off, per store_sale movement: its quantity, less every
  -- invoice_cancel_return pointing back at it and every disposition (good,
  -- damaged or not returned) recorded against it. The netting
  -- restore_invoice_stock, record_invoice_stock_return and
  -- refund_invoice_recorded use, so what is out here is exactly what a
  -- cancellation would put back. Movements with nothing left are left out.
  -- created_at is when the movement was written (stock_history_recorded_at,
  -- the clock time), so two hand-overs in one transaction keep their order.
  select m.id, m.product_id, m.from_store_id, x.left_qty,
         coalesce(m.stock_history_recorded_at, m.created_at)
    from public.stock_movements m
    cross join lateral (select (m.quantity
        - coalesce((select sum(d.sellable_quantity + d.damaged_quantity + d.not_returned_quantity)
                      from public.invoice_stock_dispositions d where d.movement_id = m.id), 0)
        - coalesce((select sum(v.quantity) from public.stock_movements v
                     where v.reversed_sale_id = m.id and v.movement_type::text = 'invoice_cancel_return'), 0)
      )::integer as left_qty) x
   where m.invoice_id = p_invoice_id
     and m.movement_type::text = 'store_sale'
     and x.left_qty > 0
$fn$
$def$;
  c_before_full_def constant text := $def$
create or replace function public.invoice_before_full_payment(p_invoice_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  -- 399: the invoice has not been settled since it was opened (or last
  -- reopened), so any store_sale on it is goods the customer took early:
  -- draft, unpaid or part-paid, or a request waiting on one, never settled
  -- since. Settled is locked_at (set whenever an invoice becomes paid or
  -- completed FOC, by any path, a correction included, and never cleared) or
  -- paid_at (set by a full payment), after the last reopening. An invoice
  -- paid in full and later corrected up to part-paid released its goods when
  -- it was settled, and is not one of these.
  select i.status::text in ('draft', 'unpaid', 'partially_paid', 'cancellation_requested', 'refund_requested')
         and not ((i.locked_at is not null and (i.reopened_at is null or i.locked_at > i.reopened_at))
                  or (i.paid_at is not null and (i.reopened_at is null or i.paid_at > i.reopened_at)))
    from public.invoices i where i.id = p_invoice_id
$fn$
$def$;
  c_kept_check_def constant text := $def$
create or replace function public.invoice_goods_kept_check(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
-- 399: a correction may not take off goods the customer already took before
-- paying in full (the Owner, 6 Oct 2026). Every product still out with the
-- customer (invoice_goods_out) must still be required by the corrected lines
-- (invoice_required_stock: product lines, promotion contents and picks), at
-- least as many. correct_invoice calls this after rewriting the lines, inside
-- its transaction, so a refusal undoes the whole correction.
declare v_list text;
begin
  select string_agg(format('"%s" (%s with the customer, the corrected invoice keeps %s)',
                           coalesce(p.name, 'a product'), o.qty, coalesce(r.qty, 0)), '; ' order by p.name)
    into v_list
    from (select g.product_id, sum(g.quantity)::integer as qty
            from public.invoice_goods_out(p_invoice_id) g group by g.product_id) o
    left join (select s.item_id, sum(s.quantity)::integer as qty
                 from public.invoice_required_stock(p_invoice_id) s
                where s.kind = 'product' group by s.item_id) r on r.item_id = o.product_id
    left join public.products p on p.id = o.product_id
   where coalesce(r.qty, 0) < o.qty;
  if v_list is not null then
    raise exception 'GOODS_HANDED_OVER: This correction takes off goods the customer already took: %. Record them as returned or written off first (Record items returned on the invoice, Owner or Manager), then correct the invoice.', v_list;
  end if;
end $fn$
$def$;
  c_internal_def constant text := $def$
create or replace function public.invoice_handover_internal(
  p_invoice_id uuid,
  p_handover jsonb,
  p_request_id uuid,
  p_source text,
  p_settlement_request_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
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
end $fn$
$def$;
  c_handover_def constant text := $def$
create or replace function public.record_invoice_handover(p_invoice_id uuid, p_handover jsonb, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
-- 399: "Hand over items" (the Owner, 6 Oct 2026): goods a customer takes on
-- an unpaid or part-paid invoice with no payment, for instance on a later
-- visit. Any active staff member with access to the invoice's store, as for
-- Record Payment. p_handover is {"items": [{"product_id": ..., "qty": n}]};
-- the rules are invoice_handover_internal's.
declare v_store uuid;
begin
  if not exists (select 1 from public.profiles
                  where id = auth.uid() and coalesce(is_active, true) and deleted_at is null) then
    raise exception 'Only an active user can hand over goods' using errcode = '42501'; end if;
  select i.store_id into v_store from public.invoices i where i.id = p_invoice_id and i.deleted_at is null;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(v_store) then
    raise exception 'No access to this invoice' using errcode = '42501'; end if;
  if jsonb_typeof(p_handover) = 'object' and jsonb_typeof(p_handover->'none') = 'boolean'
     and (p_handover->>'none')::boolean then
    raise exception 'Hand over items records the goods a customer takes. Choose at least one item.'; end if;
  return public.invoice_handover_internal(p_invoice_id, p_handover, p_request_id, 'button', null);
end $fn$
$def$;
  c_return_def constant text := $def$
create or replace function public.record_invoice_goods_return(
  p_invoice_id uuid, p_items jsonb, p_reason text, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
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
end $fn$
$def$;
  c_status_def constant text := $def$
create or replace function public.invoice_goods_status(p_invoice_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
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
           'collected', greatest(coalesce(req.qty, 0) - coalesce(tod.qty, 0), 0),
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
end $fn$
$def$;
  c_list_def constant text := $def$
create or replace function public.invoice_list_goods_out(p_invoice_ids uuid[])
returns table(invoice_id uuid, quantity integer)
language sql
stable
security definer
set search_path = public
as $fn$
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
$fn$
$def$;

  -- ── Anchors and their replacements ─────────────────────────────────────────
  c_settle_decl_a constant text :=
       E' v_target uuid; v_amount numeric;\n';
  c_settle_decl_r constant text :=
       E' v_target uuid; v_amount numeric;\n'
    || E' v399_handover jsonb;  -- 399: what the customer took with this payment\n';
  c_settle_ret_a constant text :=
       E' return public.invoice_arrangement_balances(p_invoice_id)\n'
    || E'   || jsonb_build_object(''arrangements_recorded'',v_new,''receipts_linked'',v_linked,\n'
    || E'                         ''receipts_recorded'',jsonb_array_length(v_receipts));\n';
  c_settle_ret_r constant text :=
       E' -- 399: the goods the customer took with a part payment, saved with it\n'
    || E' -- (the Owner, 6 Oct 2026): payload.handover is {"none": true} or\n'
    || E' -- {"items": [{"product_id": ..., "qty": n}]}. Under its own request id,\n'
    || E' -- derived from this one, so a replay finds what it wrote. Without the key\n'
    || E' -- (website orders, exchanges, other callers) nothing changes.\n'
    || E' if p_payload ? ''handover'' and jsonb_typeof(p_payload->''handover'') <> ''null'' then\n'
    || E'  v399_handover:=public.invoice_handover_internal(p_invoice_id,p_payload->''handover'',\n'
    || E'    md5(p_request_id::text||'':handover'')::uuid,''payment'',p_request_id);\n'
    || E' end if;\n'
    || E' return public.invoice_arrangement_balances(p_invoice_id)\n'
    || E'   || jsonb_build_object(''arrangements_recorded'',v_new,''receipts_linked'',v_linked,\n'
    || E'                         ''receipts_recorded'',jsonb_array_length(v_receipts))\n'
    || E'   || case when v399_handover is not null then jsonb_build_object(''handover'',v399_handover) else ''{}''::jsonb end;\n';

  c_correct_decl_a constant text :=
       E' v393_before uuid[];  -- 393: the lines before this correction\n';
  c_correct_decl_r constant text :=
       E' v393_before uuid[];  -- 393: the lines before this correction\n'
    || E' v399_open boolean := false;  -- 399: not yet paid in full: stock moves only if this settles it\n';
  c_correct_restore_a constant text :=
       E' if v_stock_change and i.status not in (''cancelled'',''refunded'') and v_had_stock then\n'
    || E'   perform public.restore_invoice_stock(i.id,''Invoice correction: ''||p_reason); end if;\n';
  c_correct_restore_r constant text :=
       E' -- 399: an invoice not yet paid in full holds no sale to put back: any\n'
    || E' -- store_sale on it is goods the customer took before paying in full (the\n'
    || E' -- Owner, 6 Oct 2026), and they stay out. So nothing is put back on the\n'
    || E' -- shelf here; the corrected lines must keep every product the customer\n'
    || E' -- has (invoice_goods_kept_check, below); and the goods left this store,\n'
    || E' -- so the store cannot change while they are out.\n'
    || E' v399_open := public.invoice_before_full_payment(i.id);\n'
    || E' if v399_open and n.store_id is distinct from i.store_id\n'
    || E'    and exists(select 1 from public.invoice_goods_out(i.id)) then\n'
    || E'   raise exception ''GOODS_HANDED_OVER: Goods on this invoice were handed over from its store before full payment, so it cannot move to another store. Record them as returned first (Record items returned on the invoice, Owner or Manager).''; end if;\n'
    || E' if v_stock_change and i.status not in (''cancelled'',''refunded'') and v_had_stock and not v399_open then\n'
    || E'   perform public.restore_invoice_stock(i.id,''Invoice correction: ''||p_reason); end if;\n';
  c_correct_deduct_a constant text :=
       E' if v_stock_change and i.status not in (''cancelled'',''refunded'') and v_had_stock then\n'
    || E'   perform public.deduct_invoice_stock(i.id,''Invoice correction: ''||p_reason); end if;\n';
  c_correct_deduct_r constant text :=
       E' -- 399: on an invoice not yet paid in full the corrected lines keep the\n'
    || E' -- goods the customer has, and stock is taken only if the correction\n'
    || E' -- settles it, then only what is not out already (deduct_invoice_stock is\n'
    || E' -- net). Before 399 every line was taken here, paid or not.\n'
    || E' if v399_open then perform public.invoice_goods_kept_check(i.id); end if;\n'
    || E' if v_stock_change and i.status not in (''cancelled'',''refunded'') and v_had_stock\n'
    || E'    and (not v399_open or v_status in (''paid'',''completed_foc'')) then\n'
    || E'   perform public.deduct_invoice_stock(i.id,''Invoice correction: ''||p_reason); end if;\n';

  c_foc_check_a constant text :=
       E'  for v_req in select * from public.invoice_required_stock(p_invoice_id)\n'
    || E'  loop\n'
    || E'    if v_req.kind = ''product'' then\n'
    || E'      select current_qty into v_available from public.store_inventory\n';
  c_foc_check_r constant text :=
       E'  -- 399: a product net of what was handed over before Make FOC\n'
    || E'  -- (invoice_stock_to_deduct), so goods the customer took are not counted\n'
    || E'  -- out twice; vouchers as before.\n'
    || E'  for v_req in select r.kind, r.item_id,\n'
    || E'                      case when r.kind = ''product''\n'
    || E'                           then (select coalesce(sum(t.quantity), 0) from public.invoice_stock_to_deduct(p_invoice_id) t\n'
    || E'                                  where t.kind = ''product'' and t.item_id = r.item_id)::integer\n'
    || E'                           else r.quantity end as quantity\n'
    || E'                 from public.invoice_required_stock(p_invoice_id) r\n'
    || E'  loop\n'
    || E'    if v_req.kind = ''product'' then\n'
    || E'      select current_qty into v_available from public.store_inventory\n';
  c_foc_deduct_a constant text :=
       E'  for v_req in select * from public.invoice_required_stock(p_invoice_id)\n'
    || E'  loop\n'
    || E'    if v_req.kind = ''product'' then\n'
    || E'      update public.store_inventory set current_qty = current_qty - v_req.quantity, updated_at = now()\n';
  c_foc_deduct_r constant text :=
       E'  for v_req in select r.kind, r.item_id,\n'
    || E'                      case when r.kind = ''product''\n'
    || E'                           then (select coalesce(sum(t.quantity), 0) from public.invoice_stock_to_deduct(p_invoice_id) t\n'
    || E'                                  where t.kind = ''product'' and t.item_id = r.item_id)::integer\n'
    || E'                           else r.quantity end as quantity\n'
    || E'                 from public.invoice_required_stock(p_invoice_id) r\n'
    || E'  loop\n'
    || E'    -- 399: nothing to take for a product handed over in full.\n'
    || E'    if v_req.quantity <= 0 then continue; end if;\n'
    || E'    if v_req.kind = ''product'' then\n'
    || E'      update public.store_inventory set current_qty = current_qty - v_req.quantity, updated_at = now()\n';

  c_delete_a constant text :=
       E'  update public.invoices set deleted_at = now() where id = p_invoice_id;\n';
  c_delete_r constant text :=
       E'  -- 399: goods handed over before full payment are with the customer; the\n'
    || E'  -- invoice stays until they are recorded as returned or written off.\n'
    || E'  if exists (select 1 from public.invoice_goods_out(p_invoice_id)) then\n'
    || E'    raise exception ''Goods on this invoice were handed over to the customer. Record them as returned or written off first (Record items returned on the invoice, Owner or Manager), then delete it.''; end if;\n'
    || E'  update public.invoices set deleted_at = now() where id = p_invoice_id;\n';

  c_setfulfil_a constant text :=
       E'  if not exists (select 1 from public.warehouses where id = p_warehouse_id and deleted_at is null) then\n'
    || E'    raise exception ''Warehouse not found''; end if;\n';
  c_setfulfil_r constant text :=
       E'  if not exists (select 1 from public.warehouses where id = p_warehouse_id and deleted_at is null) then\n'
    || E'    raise exception ''Warehouse not found''; end if;\n'
    || E'  -- 399: settling from a warehouse takes every product line from it and\n'
    || E'  -- gives the store the same back, so goods that already left this store\n'
    || E'  -- with the customer would be counted out of both: those handed over\n'
    || E'  -- before full payment and still out, and those the customer kept (Not\n'
    || E'  -- returned: they count as collected, so full payment does not take them\n'
    || E'  -- again). Per store_sale: its quantity less the invoice_cancel_return\n'
    || E'  -- movements pointing at it and its Good and Damaged dispositions.\n'
    || E'  if exists (select 1 from public.stock_movements m\n'
    || E'              where m.invoice_id = p_invoice_id and m.movement_type::text = ''store_sale''\n'
    || E'                and m.quantity\n'
    || E'                    - coalesce((select sum(v.quantity) from public.stock_movements v\n'
    || E'                                 where v.reversed_sale_id = m.id and v.movement_type::text = ''invoice_cancel_return''), 0)\n'
    || E'                    - coalesce((select sum(d.sellable_quantity + d.damaged_quantity) from public.invoice_stock_dispositions d\n'
    || E'                                 where d.movement_id = m.id), 0) > 0) then\n'
    || E'    raise exception ''Goods on this invoice already left this store with the customer (handed over before full payment, or kept as not returned), so it cannot also be fulfilled from a warehouse: the warehouse would send them again. Keep this store''''s stock.''; end if;\n';

  c_trgfulfil_a constant text :=
       E'  if new.status not in (''paid'',''completed_foc'') or old.status is not distinct from new.status then\n'
    || E'    return null; end if;\n';
  c_trgfulfil_r constant text :=
       E'  if new.status not in (''paid'',''completed_foc'') or old.status is not distinct from new.status then\n'
    || E'    return null; end if;\n'
    || E'  -- 399: goods handed over from the store before full payment are out of\n'
    || E'  -- the store already (still out, or kept as Not returned); taking every\n'
    || E'  -- line from the warehouse as well would count them twice. The setter\n'
    || E'  -- and the hand-over refuse the combination; this is the backstop. Only\n'
    || E'  -- the hand-over movements: the payment''s own deduction is on the invoice\n'
    || E'  -- by now.\n'
    || E'  if exists (select 1 from public.invoice_handover_lines hl\n'
    || E'               join public.stock_movements m on m.id = hl.movement_id\n'
    || E'              where hl.invoice_id = new.id\n'
    || E'                and m.quantity\n'
    || E'                    - coalesce((select sum(v.quantity) from public.stock_movements v\n'
    || E'                                 where v.reversed_sale_id = m.id and v.movement_type::text = ''invoice_cancel_return''), 0)\n'
    || E'                    - coalesce((select sum(d.sellable_quantity + d.damaged_quantity) from public.invoice_stock_dispositions d\n'
    || E'                                 where d.movement_id = m.id), 0) > 0) then\n'
    || E'    raise exception ''Goods on % were handed over from the store before it was paid in full, so it cannot also be fulfilled from a warehouse. Set "Fulfil from" back to the store''''s stock and try again.'', new.invoice_no; end if;\n';

  c_netded_a constant text :=
       E'           end), 0)::bigint\n'
    || E'    from public.stock_movements sm\n';
  c_netded_r constant text :=
       E'           end), 0)::bigint\n'
    || E'         -- 399: less the units "Record items returned" wrote off as Damaged\n'
    || E'         -- before full payment: they came back, and the invoice still owes\n'
    || E'         -- the customer them, as invoice_stock_to_deduct says. So a settlement\n'
    || E'         -- that runs no deduction (Correct amount, a header-only correction)\n'
    || E'         -- has the guarantee take the replacement. Other dispositions (a\n'
    || E'         -- refund''s, a cancellation''s) are not taken off, as before.\n'
    || E'         - coalesce((select sum(rl.damaged_quantity) from public.invoice_handover_return_lines rl\n'
    || E'                      where rl.invoice_id = p_invoice_id and rl.product_id = p_product_id), 0)::bigint\n'
    || E'    from public.stock_movements sm\n';

  r record; d text; v text; n int; k int; i int; v_bad text;
  v_fns text[] := '{}'; v_defs text[] := '{}';
begin
  -- ── Guards, anchors and patched texts: nothing is installed unless all pass ──
  for r in select * from (values
    ('record_invoice_settlement(uuid,jsonb,uuid)',
     '09c2e5e90c2ae018ffbbb90c60b60164', '8c8778af82899c6aaada62371d13802f',
     array[[c_settle_decl_a, c_settle_decl_r], [c_settle_ret_a, c_settle_ret_r]]),
    ('correct_invoice(uuid,jsonb,jsonb,text,uuid)',
     '978805ed25f2a44a6f6c5a5b94b10b3c', '5158303778516180bab171ba951d8385',
     array[[c_correct_decl_a, c_correct_decl_r], [c_correct_restore_a, c_correct_restore_r],
           [c_correct_deduct_a, c_correct_deduct_r]]),
    ('confirm_foc_invoice(uuid,text)',
     '0f1cb37a25666b0155553b127e05b208', '42a6bdb4a1a693c5c83a4fa601abc551',
     array[[c_foc_check_a, c_foc_check_r], [c_foc_deduct_a, c_foc_deduct_r]]),
    ('delete_invoice(uuid)',
     'abd48c36bfe712fbfba38742304fec7b', '5b09daf60b404444618197c478842d4a', array[[c_delete_a, c_delete_r]]),
    ('set_invoice_fulfilment_warehouse(uuid,uuid)',
     'e4603b4444b003ae1adf0109bbd4faea', '389eea0434e50337c9a90bc79937f5e2', array[[c_setfulfil_a, c_setfulfil_r]]),
    ('trg_fulfil_from_warehouse()',
     '5ecb3cb431e9e538d65310a3648a43b1', '4abf4bf68e4f00658a8da66469e7059e', array[[c_trgfulfil_a, c_trgfulfil_r]]),
    ('invoice_product_net_deducted(uuid,uuid)',
     '35544da14c1872413cc6da51cb9b7ae6', 'f6288d8eb44af4cd4dbed11f63d3427a', array[[c_netded_a, c_netded_r]])
  ) x(fn, before_md5, after_md5, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '399: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '399: public.% is already this version; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '399: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    for k in 1 .. array_length(r.edits, 1) loop
      n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
      if n <> 1 then
        raise exception '399: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
      d := replace(d, r.edits[k][1], r.edits[k][2]);
    end loop;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;
  -- Relied on, not changed: the versions read on 6 Oct 2026 (full payment
  -- takes only what is still owed; the guarantee finds nothing missing;
  -- a cancellation puts back what is unresolved).
  for r in select * from (values
    ('invoice_stock_to_deduct(uuid)', '6356494ccb8545d46c56b788f8f85f54'),
    ('invoice_required_stock(uuid)', '83bb2e1f6f8d6cb5c9287a29b2df8cf8'),
    ('deduct_invoice_stock(uuid,text)', '32183fe9e7c15ed0b11307c48289831a'),
    ('invoice_record_payments_internal(uuid,jsonb)', '5c2559f7cf4dbca5dec4fdd55d00ae34'),
    ('ensure_invoice_stock_deducted(uuid,text)', '3c7ca7893f359f380a340cec07f21a1f'),
    ('trg_guarantee_invoice_stock()', 'b4d922c6238f50137941a85a590600c8'),
    ('restore_invoice_stock(uuid,text)', '092316c3af22361f80d186e38fe49bf3')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '399: public.% is missing or not the version read on 6 Oct 2026. Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;
  for r in select * from (values
    ('invoice_goods_out(uuid)', '15ffed0ff0d5d9cc5685af8e834302ae'),
    ('invoice_before_full_payment(uuid)', '532d7690367fc674737b20420e7fb16c'),
    ('invoice_goods_kept_check(uuid)', 'c79ebaa50a099564d1b2ccd63aea5444'),
    ('invoice_handover_internal(uuid,jsonb,uuid,text,uuid)', '51f5adaddbe447e8fcbeaabab03a054a'),
    ('record_invoice_handover(uuid,jsonb,uuid)', '1132398e57a234deb60c972fc89a8ffa'),
    ('record_invoice_goods_return(uuid,jsonb,text,uuid)', 'e1a3242f7bfc66fb4f6ea162d823137f'),
    ('invoice_goods_status(uuid)', '651039eac932b5d1f51fc75313ed4320'),
    ('invoice_list_goods_out(uuid[])', '6c9da48db53c8febe2cb7a7188740398')) x(fn, after_md5)
  loop
    if to_regprocedure('public.' || r.fn) is not null
       and md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.after_md5 then
      raise exception '399: a different public.% already exists (md5 %)', r.fn,
        md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))); end if;
  end loop;
  -- No other function takes these names (the API picks an overload by name).
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('invoice_goods_out', 'invoice_before_full_payment', 'invoice_goods_kept_check', 'invoice_handover_internal',
                                'record_invoice_handover', 'record_invoice_goods_return',
                                'invoice_goods_status', 'invoice_list_goods_out')
              and p.oid::regprocedure::text not in (
                'invoice_goods_out(uuid)', 'invoice_before_full_payment(uuid)', 'invoice_goods_kept_check(uuid)',
                'invoice_handover_internal(uuid,jsonb,uuid,text,uuid)', 'record_invoice_handover(uuid,jsonb,uuid)',
                'record_invoice_goods_return(uuid,jsonb,text,uuid)', 'invoice_goods_status(uuid)',
                'invoice_list_goods_out(uuid[])')) then
    raise exception '399: another overload of a hand-over function exists'; end if;

  -- ── The hand-over records ──────────────────────────────────────────────────
  create table if not exists public.invoice_handovers (
    id uuid primary key default gen_random_uuid(),
    invoice_id uuid not null references public.invoices(id),
    store_id uuid not null references public.stores(id),
    kind text not null constraint invoice_handovers_kind_check
      check (kind in ('handover', 'nothing_taken', 'return')),
    source text not null constraint invoice_handovers_source_check
      check (source in ('payment', 'button', 'return')),
    request_id uuid not null constraint invoice_handovers_request_once unique,
    request_hash text not null,
    settlement_request_id uuid,
    reason text,
    created_by uuid references public.profiles(id),
    created_at timestamptz not null default clock_timestamp(),
    constraint invoice_handovers_return_shape check ((kind = 'return') = (source = 'return'))
  );
  create index if not exists invoice_handovers_by_invoice on public.invoice_handovers (invoice_id, created_at);
  create table if not exists public.invoice_handover_lines (
    id uuid primary key default gen_random_uuid(),
    handover_id uuid not null references public.invoice_handovers(id),
    invoice_id uuid not null references public.invoices(id),
    product_id uuid not null references public.products(id),
    quantity integer not null constraint invoice_handover_lines_quantity_check check (quantity > 0),
    movement_id uuid not null references public.stock_movements(id)
      constraint invoice_handover_lines_movement_once unique,
    constraint invoice_handover_lines_product_once unique (handover_id, product_id)
  );
  create index if not exists invoice_handover_lines_by_invoice on public.invoice_handover_lines (invoice_id);
  create table if not exists public.invoice_handover_return_lines (
    id uuid primary key default gen_random_uuid(),
    handover_id uuid not null references public.invoice_handovers(id),
    invoice_id uuid not null references public.invoices(id),
    product_id uuid not null references public.products(id),
    sale_movement_id uuid not null references public.stock_movements(id),
    good_quantity integer not null default 0,
    damaged_quantity integer not null default 0,
    not_returned_quantity integer not null default 0,
    return_movement_id uuid references public.stock_movements(id),
    disposition_id uuid references public.invoice_stock_dispositions(id),
    constraint invoice_handover_return_lines_quantities check
      (good_quantity >= 0 and damaged_quantity >= 0 and not_returned_quantity >= 0
       and good_quantity + damaged_quantity + not_returned_quantity > 0),
    constraint invoice_handover_return_lines_shape check
      ((good_quantity > 0) = (return_movement_id is not null)
       and (damaged_quantity + not_returned_quantity > 0) = (disposition_id is not null))
  );
  create index if not exists invoice_handover_return_lines_by_invoice
    on public.invoice_handover_return_lines (invoice_id);
  alter table public.invoice_handovers enable row level security;
  alter table public.invoice_handover_lines enable row level security;
  alter table public.invoice_handover_return_lines enable row level security;
  foreach v in array array['invoice_handovers', 'invoice_handover_lines', 'invoice_handover_return_lines'] loop
    execute format('revoke all on table public.%I from anon, authenticated', v);
    execute format('grant select on table public.%I to authenticated', v);
    execute format('grant all on table public.%I to service_role', v);
  end loop;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'invoice_handovers'
                  and policyname = 'invoice_handovers_read') then
    create policy invoice_handovers_read on public.invoice_handovers for select to authenticated
      using (public.user_has_store_access(store_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'invoice_handover_lines'
                  and policyname = 'invoice_handover_lines_read') then
    create policy invoice_handover_lines_read on public.invoice_handover_lines for select to authenticated
      using (exists (select 1 from public.invoices i
                      where i.id = invoice_handover_lines.invoice_id and public.user_has_store_access(i.store_id)));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'invoice_handover_return_lines'
                  and policyname = 'invoice_handover_return_lines_read') then
    create policy invoice_handover_return_lines_read on public.invoice_handover_return_lines for select to authenticated
      using (exists (select 1 from public.invoices i
                      where i.id = invoice_handover_return_lines.invoice_id and public.user_has_store_access(i.store_id)));
  end if;

  -- ── Install: the helpers first, then the functions that call them ─────────
  execute c_goods_out_def;
  execute c_before_full_def;
  execute c_kept_check_def;
  execute c_internal_def;
  execute c_handover_def;
  execute c_return_def;
  execute c_status_def;
  execute c_list_def;
  foreach v in array array['invoice_goods_out(uuid)', 'invoice_before_full_payment(uuid)', 'invoice_goods_kept_check(uuid)',
                           'invoice_handover_internal(uuid,jsonb,uuid,text,uuid)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', v);
    execute format('grant execute on function public.%s to service_role', v);
  end loop;
  foreach v in array array['record_invoice_handover(uuid,jsonb,uuid)', 'record_invoice_goods_return(uuid,jsonb,text,uuid)',
                           'invoice_goods_status(uuid)', 'invoice_list_goods_out(uuid[])'] loop
    execute format('revoke all on function public.%s from public, anon', v);
    execute format('grant execute on function public.%s to authenticated, service_role', v);
  end loop;
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
  end loop;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  for r in select * from (values
    ('record_invoice_settlement(uuid,jsonb,uuid)', '8c8778af82899c6aaada62371d13802f'),
    ('correct_invoice(uuid,jsonb,jsonb,text,uuid)', '5158303778516180bab171ba951d8385'),
    ('confirm_foc_invoice(uuid,text)', '42a6bdb4a1a693c5c83a4fa601abc551'),
    ('delete_invoice(uuid)', '5b09daf60b404444618197c478842d4a'),
    ('set_invoice_fulfilment_warehouse(uuid,uuid)', '389eea0434e50337c9a90bc79937f5e2'),
    ('trg_fulfil_from_warehouse()', '4abf4bf68e4f00658a8da66469e7059e'),
    ('invoice_product_net_deducted(uuid,uuid)', 'f6288d8eb44af4cd4dbed11f63d3427a'),
    ('invoice_goods_out(uuid)', '15ffed0ff0d5d9cc5685af8e834302ae'),
    ('invoice_before_full_payment(uuid)', '532d7690367fc674737b20420e7fb16c'),
    ('invoice_goods_kept_check(uuid)', 'c79ebaa50a099564d1b2ccd63aea5444'),
    ('invoice_handover_internal(uuid,jsonb,uuid,text,uuid)', '51f5adaddbe447e8fcbeaabab03a054a'),
    ('record_invoice_handover(uuid,jsonb,uuid)', '1132398e57a234deb60c972fc89a8ffa'),
    ('record_invoice_goods_return(uuid,jsonb,text,uuid)', 'e1a3242f7bfc66fb4f6ea162d823137f'),
    ('invoice_goods_status(uuid)', '651039eac932b5d1f51fc75313ed4320'),
    ('invoice_list_goods_out(uuid[])', '6c9da48db53c8febe2cb7a7188740398')) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '399: installed with md5s other than the tested ones: %', v_bad; end if;
  -- The page reaches what it calls; the helpers are endpoints for nobody.
  foreach v in array array['record_invoice_settlement(uuid,jsonb,uuid)', 'correct_invoice(uuid,jsonb,jsonb,text,uuid)',
                           'confirm_foc_invoice(uuid,text)', 'delete_invoice(uuid)',
                           'set_invoice_fulfilment_warehouse(uuid,uuid)',
                           'record_invoice_handover(uuid,jsonb,uuid)', 'record_invoice_goods_return(uuid,jsonb,text,uuid)',
                           'invoice_goods_status(uuid)', 'invoice_list_goods_out(uuid[])'] loop
    if not has_function_privilege('authenticated', 'public.' || v, 'execute') then
      raise exception '399: public.% is not callable by staff', v; end if;
    if has_function_privilege('anon', 'public.' || v, 'execute') then
      raise exception '399: public.% is callable signed out', v; end if;
  end loop;
  foreach v in array array['invoice_goods_out(uuid)', 'invoice_before_full_payment(uuid)', 'invoice_goods_kept_check(uuid)',
                           'invoice_handover_internal(uuid,jsonb,uuid,text,uuid)', 'trg_fulfil_from_warehouse()'] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or has_function_privilege('authenticated', 'public.' || v, 'execute') then
      raise exception '399: public.% is callable by a client role', v; end if;
  end loop;
  foreach v in array array['invoice_handovers', 'invoice_handover_lines', 'invoice_handover_return_lines'] loop
    if has_table_privilege('authenticated', 'public.' || v, 'insert')
       or has_table_privilege('authenticated', 'public.' || v, 'update')
       or has_table_privilege('authenticated', 'public.' || v, 'delete')
       or has_table_privilege('anon', 'public.' || v, 'select') then
      raise exception '399: public.% is writable by staff or readable signed out', v; end if;
  end loop;

  perform pg_notify('pgrst', 'reload schema');
end $mig$;
