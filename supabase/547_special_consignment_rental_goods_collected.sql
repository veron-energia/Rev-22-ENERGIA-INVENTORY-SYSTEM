-- 547_special_consignment_rental_goods_collected.sql
--
-- SPECIAL, CONSIGNMENT AND RENTAL ITEMS JOIN AN INVOICE'S "GOODS COLLECTED"
--
--   The Owner, 27 Nov 2026: "For good collected, the special product or consignment don't have goods
--   collected. So can you help me add them to be able to list good collected?" 399's hand-over
--   (Goods collected / To collect, "Hand over items", "Record items returned") covers store products
--   only. MADE BY gen547.py from production's functions after 546 (function fingerprint
--   f5f09a8bf80f379ccdf38b6edaad0dbc/1462); after: 73d175b2e8d324bb524127497fe3d02b/1470 (rebuilt
--   with the header's last words; see the md5s below). It refuses on any other base and changes
--   nothing. (The number 547 is this file's name and its errors' prefix.)
--
-- THE OWNER'S ANSWERS (27 Nov 2026; the data contract, not changed here)
--
--   1. Where: on the invoice's goods list and its printed copies (Collected / To collect), and in
--      Record Payment's part-payment question "Did the customer take any goods now?".
--   2. Before full payment: a customer may take a special or consignment item.
--   3. Collected is its own record: staff record it on the invoice when the customer picks the item
--      up, apart from the warehouse release on Special & Rentals; the two can be days apart.
--   4. Delivered: when the supplier delivers a consignment item to the customer's address, the
--      invoice says "Delivered" instead of "Collected"; staff record which.
--   5. Rentals: rented special and consignment items (rental lines) are included.
--   6. A PAID invoice still shows a special, consignment or rental item not collected as "To collect".
--   7. No warehouse choice for staff: recorded as collected before full payment, the item appears in
--      "Waiting for a warehouse", where an Owner or Manager chooses and releases it, as after full
--      payment (for consignment, the existing release to the supplier).
--   8. Blocked until returned: cancelling the invoice, or removing or reducing the line (correction,
--      edit, refund), while such an item is collected or delivered, is refused until it is recorded
--      as returned, as for products.
--   9. Who: staff of the invoice's store record Collected / Delivered (as for products); returns
--      follow "Record items returned"'s rights (Owner or Manager of the store).
--
-- HOW IT IS BUILT (the choices made, for the Owner to see)
--
--   * The record: invoice_special_handover_lines, under 399's invoice_handovers header (same kinds,
--     sources, request ids and retries): per invoice line, Collected or Delivered, the units, and the
--     special sale (one unit each) or the rental it was. NOT a stock movement: stock moves only when
--     an Owner or Manager releases the item (fulfil_special_doc, release_special_sale_to_supplier).
--     Returns: invoice_special_handover_returns, under a 'return' header.
--   * Delivered is offered only for a consignment product's sale line (special_products.
--     is_consignment). A rental is always Collected (consignment rentals come from own stock, 494).
--   * Before full payment (answers 2 and 7): recording an item as collected raises its special sale
--     (one per unit) or the line's rental now, waiting for a warehouse, as the full payment raises
--     them. The full payment (create_special_docs_for_invoice, from Record Payment, Confirm FOC, a
--     correction or a reopening) then raises only the rest: a line's units beyond the sales that
--     still count; never a second one. A rental is collected whole (all its units at once), since it
--     goes out as one rental.
--   * An item the customer has may be released while the invoice still owes money (answer 7; 458/498
--     otherwise keep a waiting item until it is paid in full; an item nobody has collected still
--     waits for the payment).
--   * Order free (answer 3): Collected may come before or after the release. A unit collected takes
--     what the line already has, released units first, then waiting ones.
--   * Rentals: Collected is the pick-up. The rental's own return stays as it is (return_rental_with_
--     fee on Special & Rentals, late fee and all); once back, it is with the customer no more.
--   * Paid invoices (answer 6): invoice_goods_status lists the special lines and what is still to
--     collect whatever the payment; the copies of a paid invoice list Collected / Delivered / To
--     collect while a special item is still to collect (the page's).
--   * Blocked until returned (answer 8): Cancel (cancel_invoice_recorded), Delete (delete_invoice),
--     a correction that removes the line, puts another machine on it or lowers it below the units out
--     (correct_invoice, paid or not), and a refund that takes the line's whole value back, answers for
--     the stock of a unit the customer has, says the customer is not taking a unit they have, is on a
--     rental's line, or closes the invoice (refund_invoice_recorded): refused, naming the items ("The
--     customer has ..."; a correction's refusal starts GOODS_HANDED_OVER: as 399's, which the page
--     strips). A correction that keeps them (or lowers the line to no fewer than are out) goes through
--     and takes an uncollected unit first.
--   * Returns (record_invoice_goods_return, {"invoice_item_id", "returned": n}; Owner or Manager of
--     the store; unpaid, part-paid, paid or completed FOC): the item came back.
--       - not yet released: no stock moves; before full payment its sale or rental is cancelled (off
--         the waiting list) and the full payment raises it again; after, it simply waits again;
--       - released from a warehouse or a store: back on that shelf, by 496's own path
--         (return_released_special_stock, why 'item returned'), the sale ends;
--       - sent by its supplier: back to the supplier, no stock moves (494's rule), the sale ends;
--       - after full payment, a sale that ended is raised again in its place, waiting (the line is
--         still sold, to collect again, answer 6);
--       - a rental released from a warehouse or a store is refused here: it comes back with its own
--         Return on Special & Rentals.
--     Only "returned": a special item that comes back damaged is returned, and the Owner adjusts the
--     stock (no damaged / not-returned write-off is offered for special items).
--   * Products are exactly as 399 has them: a paid invoice's products still go through Refund / Cancel;
--     the answers, hashes, figures and flags of a products-only invoice are unchanged.
--   * Items released before 547 (the Owner, 27 Nov 2026, "continue"): recorded once, by this migration,
--     as already collected, so a paid invoice does not list them as To collect: every COMPLETED
--     special sale on a live invoice (not deleted; paid, completed FOC, part-paid or unpaid) as
--     Delivered when its supplier sent it, otherwise Collected; every rental of such an invoice that
--     is active, overdue or returned as Collected (whole). Each gets its own 399 hand-over header with
--     source 'migration' (a new value of invoice_handovers_source_check, so it is told apart from
--     anything staff record), no person (created_by null), dated when it was released (the sale's
--     fulfilled_at; the rental's fulfilled_at, else activated_at, its start or its creation), its
--     request id md5('547 backfill <kind> <id>') (a re-run adds nothing), and its note in the
--     header's reason, which the invoice's history shows: "Released before 547 (27 Nov 2026):
--     recorded as collected or delivered by the migration, not by staff". Not recorded: a waiting
--     (pending) sale, which stays To collect; a sale whose line is gone or holds another machine; a
--     sale whose released unit a refund already settled (back, damaged or not returned answered: no
--     return could be recorded for it). No stock, sale or rental changes; no audit row (the header
--     is the record). The block checks every such item has its record and says how many it made
--     (NOTICE); the counts read on production on 27 Nov 2026 were 16 completed sales (4 sent by a
--     supplier, 12 from a warehouse or store) and 13 rentals (2 active, 11 returned).
--   * "Waiting for a warehouse" marks what the customer already has: special_waiting_collected (the
--     page's, Owners and Managers of the invoice's store) says, of the waiting items, which are
--     recorded as Collected or Delivered and not returned.
--
-- WHAT THIS DOES
--
--   New tables: invoice_special_handover_lines, invoice_special_handover_returns (signed-in staff of
--   the invoice's store read them, an Inventory Manager none; only these functions write).
--   special_sale_returns_why_check: also 'item returned'.
--   New internal functions (service_role only): invoice_special_goods_out (what is with the customer),
--   invoice_special_lines (per line: units, collected, delivered, out, to collect),
--   special_doc_collected (a sale or rental the customer has), invoice_special_kept_check (the
--   correction's refusal), invoice_special_goods_block (cancel, delete, a closing refund),
--   invoice_special_refund_check (a refund's line), invoice_special_collect_internal (records them).
--   New for the page: special_waiting_collected(uuid[]) (signed-in; it lets active Owners and Managers
--   by, as the waiting list does, and answers only for invoices of their stores).
--   invoice_handovers_source_check: also 'migration' (the backfill's headers).
--   Replaced whole (each its 399 text with 547's lines added, BEFORE pinned):
--     invoice_handover_internal: "specials" in the answer and its hash; on a paid or completed-FOC
--       invoice too; a settlement that paid in full records the specials alone.
--     record_invoice_goods_return: {"invoice_item_id", "returned"} entries, on a paid invoice too.
--     invoice_goods_status: "specials", their totals, can_collect_special, can_record_special_return,
--       and the special items in the history. Every 399 key is as before.
--     invoice_list_goods_out: special items out count in the "Goods out" badge.
--   Patched by anchors (each exactly as often as said):
--     create_special_docs_for_invoice: on a line with a 547 record, raises only the units missing
--       (and pays an early rental); otherwise as before.
--     invoice_special_sales_follow_lines: a lowered line takes what the customer has last; before full
--       payment a raised line with a 547 record waits for the payment.
--     correct_invoice: invoice_special_kept_check after the lines, in the preview and the save.
--     cancel_invoice_recorded, delete_invoice: invoice_special_goods_block first.
--     refund_invoice_recorded: invoice_special_refund_check per special or rental line; the block
--       when the refund closes the invoice.
--     fulfil_special_doc, release_special_sale_to_supplier: the "owing" refusal skips an item the
--       customer has.
--     return_released_special_stock: also 'item returned'.
--   Every new and changed owner-rights function: search_path public, pg_temp (546's rule).
--
-- NOT CHANGED: record_invoice_handover (the button: active staff of the store, as 399; it passes
--   "specials" through), record_invoice_settlement, invoice_record_payments_internal, confirm_foc_
--   invoice, reopen_invoice, invoice_rentals_follow_lines (an early rental is the line's whole rental,
--   so it follows as 458 has it), the waiting list (special_docs_awaiting_fulfilment lists the early
--   items as any waiting one), the reports. No data changes but the backfill's records above.
--
-- SAFETY: one DO block after the lock timeout, so atomic however it is run. Every guard and anchor is
--   checked, and every patched text built, before anything is installed. A database where every
--   function is already 547's says so and changes nothing; one partly there refuses. After
--   installing, every md5 is checked, the new functions are internal, the tables read-only for
--   logins, and every changed function searches pg_temp last. Then the backfill, in the same
--   transaction, which refuses (undoing everything) if any released item is left without a record.
--   A re-run on a database where 547 is in stops at "already in" and records nothing more.
--
-- GO-LIVE: after 546 (it refuses before it). Page changes ship with it (src/lib/invoices/handover.mjs,
--   src/components/invoices/InvoiceGoods.tsx, src/pages/InvoicesPage.tsx, src/lib/invoicePdf.ts,
--   src/pages/SpecialPage.tsx); the
--   pages of before keep working with it (every 399 key of invoice_goods_status is unchanged), and the
--   new pages read nothing new until it is in (no "specials": none shown).
--
-- UNDO: scripts/special/undo-547.sql (before any older UNDO, 546's included). It removes the
--   migration's own records (source 'migration') and refuses once staff recorded anything as
--   collected, delivered or returned under 547.
--
-- TESTS: scripts/special/tests/goods-collected-547.sql; scripts/invoices/tests/
--   goods-collected-special-547.test.mjs and goods-collected-special-547-browser.mjs (the pages),
--   scripts/special/tests/special-page.test.mjs (its 547 test: the waiting list marks).
--
-- BEFORE -> AFTER (md5 of pg_get_functiondef; BEFORE is production after 546):
--   create_special_docs_for_invoice(uuid)                                  1fb8c1a00ef107535a6c08020ee7e78f -> e4dbc424f10cebfa90de3e56677f3a5e
--   invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)               c11c6685d6e0072d96b586471cb1d450 -> e57d1774e2ded552780071d7078f5f89
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                            095c047730808bd69b87d5623386b52b -> 8de40251441091ec08e72499c49adc50
--   cancel_invoice_recorded(uuid,text,uuid)                                c16247ad7c5f1a80c1a57efdef5a0d7d -> a09497ec2f1d267592788ac80b0eb008
--   refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)              7802bc26966f422978e2b764b289944f -> 10926314097ca6bdbeeb766d7c2ca58c
--   delete_invoice(uuid,text)                                              b9e3d48b177595858e3966571023b4d0 -> 9f766c64742ac431c36619f0fdd887ac
--   fulfil_special_doc(text,uuid,uuid,text)                                cd2ffb8913e60c56e32db817fe1401bb -> 3d96a80f7fa97766543dd23340b9f3f6
--   release_special_sale_to_supplier(uuid,uuid,text)                       c32733b054230d1b6548741c3d78a0ef -> 9671a311db74aa9e18fbc4b3a32bba12
--   return_released_special_stock(uuid,uuid,integer,integer,integer,uuid,text,text) e9f575b72cb1c5b8f98500aebbd23b7f -> 32dae626d73b4aa8582f2af94c05ff2f
--   invoice_handover_internal(uuid,jsonb,uuid,text,uuid)                   151e5d3d40d83ec45564eac554d4a154 -> 9c59d949e21038078ad82c66d5e7268f
--   record_invoice_goods_return(uuid,jsonb,text,uuid)                      35f9ffb9b370407a0fda3aabe664faf2 -> 5df5d911d2c814b1fb70c87c68b3fb91
--   invoice_goods_status(uuid)                                             4cef49907477dcc4abc24f72166214ea -> 39d072fdd8470e2f32eca57d82f1095b
--   invoice_list_goods_out(uuid[])                                         0c8c82d9832995e164d1271fb3e6b2a2 -> 3f785416c55ebe8d72744a698d28aa1e
-- NEW (AFTER):
--   invoice_special_goods_out(uuid)                                        81e3e1bc5140850dae4bb9fb2f184335
--   invoice_special_lines(uuid)                                            41721086125e3568f5a30b406dbf921b
--   special_doc_collected(text,uuid)                                       99071814bbbea40893e9bf1da0da6ee6
--   invoice_special_kept_check(uuid)                                       5f485793a470315a1b837d0bf1d45e8f
--   invoice_special_goods_block(uuid,text)                                 e7ce1c0f3bf0d489da02efa94c9afa4c
--   invoice_special_refund_check(uuid,uuid,boolean,jsonb,jsonb)            e788ddb40f0da357c2457cea8b374259
--   invoice_special_collect_internal(uuid,uuid,jsonb)                      ecedcfb87bbb9cacde6cc3c613d3c48c
--   special_waiting_collected(uuid[])                                      49012eecc99ca8128c780479db683a8d
-- RELIED ON, NOT CHANGED (production after 546):
--   invoice_goods_out(uuid)                                                fe2f1027d909ad583d543705032a3a1e
--   invoice_before_full_payment(uuid)                                      3cce8331cd3e70533476d496b3136ac6
--   invoice_goods_kept_check(uuid)                                         41a35dbcdb5a0a6f1e7c00b744c9ee69
--   record_invoice_handover(uuid,jsonb,uuid)                               7234e8bb7f2ed2cfefa8354bb9843d2d
--   record_invoice_settlement(uuid,jsonb,uuid)                             bec4ba292611157069c6813d22d04b9b
--   special_release_rows(uuid)                                             c1e16752967057f76eb137715f9e0fba
--   cancel_waiting_special_docs(uuid,text,text,uuid,uuid[])                55a131c9d24d99dd2d94944adafb792f
--   special_docs_awaiting_fulfilment()                                     21f5ba85c24a12e8d66861bf39cd6965
--   special_doc_invoice_problem(uuid,uuid)                                 4e01429ca76a96693413c2a114cc68a2
--   invoice_rentals_follow_lines(uuid,jsonb,text)                          3e085fe3fe9d100238c21616b8e55ef4
--   settle_waiting_special_docs_on_refund(uuid,jsonb,text)                 a3c4c94656a56eb371ced34ea0ac1db3
--   rentals_follow_refund(uuid,jsonb,text)                                 fdb2ac652f54e682508bc07d7f13dccb
--   invoice_record_payments_internal(uuid,jsonb)                           b37cdee8b7f914ed2d625b8b0620dbfd
--   confirm_foc_invoice(uuid,text)                                         3e5cbdb24584c5e2e39cf9009ba53233
--   reopen_invoice(uuid,text,uuid)                                         bc8a4eaba95f928f2e9718a90d9fdd56
--   return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text) 64bfeda29df82a38145a56c53e8a657f
--   cancel_invoice_rentals(uuid,text)                                      28a1904b1766601d41a36864b053c60a
--   special_product_name(uuid)                                             a2a04103c9cdbf21073dd01fa476c8d0
--   rental_is_outstanding(text)                                            076549a44bc057cd529aac5542c4d06e
--   user_has_store_access(uuid)                                            d5a5806b9f7352d8ecc34c77fa8af1d9
--   is_owner_or_manager()                                                  98600ad0a0afb459eae90645dac27b08
--   inventory_manager_guard(text)                                          c470323811ae7acd8049d51f9c2d8f6f
--   invoice_required_stock(uuid)                                           dfb1cb171b0a1cc6d9524b7be1bd890e
--   invoice_stock_to_deduct(uuid)                                          0e26025476f6eecfccdf3f4ae806d643
--   sg_today()                                                             1c1289f18e24d8370e9a6364c9c06fca
--   invoice_charge_total(uuid)                                             af05fb2013665d886fb4d3b95946b9e3
--   invoice_net_received(uuid)                                             d7198edbdf9f28269d4a42e2d3dd2141
--   invoice_discounted_line_value(uuid)                                    8e5617c9262781652e6c63a255766d16
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)    6f3e0aa6b4b117c160d8c4e488bb29ed
--   require_active_staff(text[])                                           93662edd89c9fe60216a7756e1f1e8e9

set lock_timeout = '5s';

do $mig$
declare
  c_new_0 constant text := $def$create or replace function public.invoice_special_goods_out(p_invoice_id uuid)
returns table(collection_id uuid, invoice_item_id uuid, line_kind text, special_product_id uuid, how text,
              special_sale_id uuid, rental_id uuid, quantity integer, created_at timestamptz)
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  -- 547 (the Owner, 27 Nov 2026): the special, consignment and rental items of an invoice that
  -- staff recorded as Collected or Delivered and that are still with the customer: each record's
  -- units, less those "Record items returned" took back. A rental back through its own Return on
  -- Special & Rentals (returned, or its stock back) is with the customer no longer. Records with
  -- nothing left are left out. Internal.
  select h.id, h.invoice_item_id, h.line_kind, h.special_product_id, h.how, h.special_sale_id, h.rental_id,
         x.left_qty, h.created_at
    from public.invoice_special_handover_lines h
    left join public.rentals r on r.id = h.rental_id
    cross join lateral (select (h.quantity - coalesce((select sum(b.quantity) from public.invoice_special_handover_returns b
                                                         where b.collection_id = h.id), 0))::integer as left_qty) x
   where h.invoice_id = p_invoice_id
     and x.left_qty > 0
     and not (h.rental_id is not null and (r.status::text = 'returned' or coalesce(r.stock_returned, false)))
$fn$;
$def$;
  c_new_1 constant text := $def$create or replace function public.invoice_special_lines(p_invoice_id uuid)
returns table(invoice_item_id uuid, line_kind text, special_product_id uuid, name text, is_consignment boolean,
              quantity integer, collected integer, delivered integer, out_qty integer, to_collect integer)
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  -- 547 (the Owner, 27 Nov 2026): an invoice's special, consignment and rental lines and their
  -- goods: the line's units; Collected and Delivered (recorded by staff, less what "Record items
  -- returned" took back; a rental back through its own Return still counts as collected); out
  -- with the customer (invoice_special_goods_out); and still to collect. Still to collect is
  --   * the units raised for the line (a special sale or a rental, not cancelled) that nobody has
  --     recorded as collected, a special sale settled by a refund (its unit answered damaged or not
  --     returned) and a rental back or ended excepted;
  --   * and, on an invoice not yet paid in full, the units not raised yet: the full payment raises
  --     them, or recording them as collected does now (the Owner's answer 7);
  --   * never more than the units on the line less those out, and none on a cancelled or refunded
  --     invoice, one deleted, or one waiting on a cancellation or refund request.
  -- On a paid invoice too (the Owner's answer 6). Internal: invoice_goods_status and the
  -- hand-over read it.
  with inv as (
         select v.id, public.invoice_before_full_payment(v.id) as early,
                (v.deleted_at is not null
                 or v.status::text in ('cancelled', 'refunded', 'cancellation_requested', 'refund_requested')) as closed
           from public.invoices v where v.id = p_invoice_id),
       ln as (
         select it.id, it.line_kind::text as kind, it.special_product_id,
                greatest(coalesce(it.quantity, 1), 1)::integer as qty
           from public.invoice_items it
          where it.invoice_id = p_invoice_id
            and it.line_kind::text in ('special_product', 'rental')
            and it.special_product_id is not null),
       rec as (
         select h.invoice_item_id,
                sum(h.quantity - coalesce(b.back, 0)) filter (where h.how = 'collected')::integer as collected,
                sum(h.quantity - coalesce(b.back, 0)) filter (where h.how = 'delivered')::integer as delivered
           from public.invoice_special_handover_lines h
           left join lateral (select sum(x.quantity) as back from public.invoice_special_handover_returns x
                               where x.collection_id = h.id) b on true
          where h.invoice_id = p_invoice_id
          group by h.invoice_item_id),
       gone as (
         select g.invoice_item_id, g.special_sale_id, g.rental_id, g.quantity
           from public.invoice_special_goods_out(p_invoice_id) g),
       gone_line as (
         select g.invoice_item_id, sum(g.quantity)::integer as qty from gone g group by g.invoice_item_id),
       sale as (
         select s.invoice_item_id, count(*)::integer as live,
                count(*) filter (where not exists (select 1 from gone o where o.special_sale_id = s.id)
                                   and not coalesce((select rr.quantity - rr.resolved_quantity <= 0
                                                       from public.special_release_rows(p_invoice_id) rr
                                                      where rr.movement_id = s.release_movement_id), false))::integer as free
           from public.special_sales s
          where s.invoice_id = p_invoice_id and s.status <> 'cancelled'
          group by s.invoice_item_id),
       rent as (
         select r.invoice_item_id, coalesce(sum(r.quantity), 0)::integer as live,
                coalesce(sum(greatest(r.quantity - coalesce((select sum(o.quantity) from gone o where o.rental_id = r.id), 0), 0))
                           filter (where (r.status::text = 'awaiting_fulfilment' or public.rental_is_outstanding(r.status::text))
                                     and not coalesce(r.stock_returned, false)), 0)::integer as free
           from public.rentals r
          where r.invoice_id = p_invoice_id and r.status::text <> 'cancelled'
          group by r.invoice_item_id)
  select ln.id, ln.kind, ln.special_product_id,
         coalesce(public.special_product_name(ln.special_product_id), 'Special product')
           || case when ln.kind = 'rental' then ' (rental)' else '' end,
         coalesce(sp.is_consignment, false),
         ln.qty,
         coalesce(rec.collected, 0), coalesce(rec.delivered, 0),
         coalesce(o.qty, 0),
         case when inv.closed then 0
              else greatest(least(
                     case when ln.kind = 'rental' then coalesce(rent.free, 0) else coalesce(sale.free, 0) end
                     + case when inv.early
                            then greatest(ln.qty - case when ln.kind = 'rental' then coalesce(rent.live, 0)
                                                        else coalesce(sale.live, 0) end, 0)
                            else 0 end,
                     ln.qty - coalesce(o.qty, 0)), 0) end
    from ln
    cross join inv
    left join public.special_products sp on sp.id = ln.special_product_id
    left join rec on rec.invoice_item_id = ln.id
    left join gone_line o on o.invoice_item_id = ln.id
    left join sale on sale.invoice_item_id = ln.id and ln.kind = 'special_product'
    left join rent on rent.invoice_item_id = ln.id and ln.kind = 'rental'
$fn$;
$def$;
  c_new_2 constant text := $def$create or replace function public.special_doc_collected(p_doc_kind text, p_doc_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  -- 547 (the Owner, 27 Nov 2026, answer 7): a special sale or rental (fulfil_special_doc's kinds)
  -- with units staff recorded as Collected or Delivered and still with the customer. Such an item
  -- may be released from a warehouse, a store or to its supplier while its invoice still owes
  -- money: the customer has it already. Internal.
  select exists (
    select 1 from public.invoice_special_handover_lines h
      left join public.rentals r on r.id = h.rental_id
     where ((p_doc_kind = 'special_sale' and h.special_sale_id = p_doc_id)
            or (p_doc_kind = 'rental' and h.rental_id = p_doc_id))
       and h.quantity > coalesce((select sum(b.quantity) from public.invoice_special_handover_returns b
                                   where b.collection_id = h.id), 0)
       and not (h.rental_id is not null and (r.status::text = 'returned' or coalesce(r.stock_returned, false))))
$fn$;

create or replace function public.invoice_special_kept_check(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
-- 547 (the Owner, 27 Nov 2026, answer 8): a correction (or an edit) may not take off a special,
-- consignment or rental item the customer has (recorded as Collected or Delivered, not recorded
-- as returned): its line must still be there, with the same special product and kind, and at
-- least as many units as are out. Paid or not. correct_invoice calls it after rewriting the
-- lines, inside its transaction, so a refusal undoes the whole correction.
declare v_list text;
begin
  select string_agg(format('"%s" (%s %s, the corrected invoice keeps %s)',
                           coalesce(public.special_product_name(o.special_product_id), 'a special product')
                             || case when o.line_kind = 'rental' then ' (rental)' else '' end,
                           o.qty, case when o.delivered then 'collected or delivered' else 'collected' end,
                           case when it.id is null or it.line_kind::text <> o.line_kind
                                     or it.special_product_id is distinct from o.special_product_id then 0
                                else greatest(coalesce(it.quantity, 1), 1) end), '; ' order by o.invoice_item_id)
    into v_list
    from (select g.invoice_item_id, g.line_kind, g.special_product_id, sum(g.quantity)::integer as qty,
                 bool_or(g.how = 'delivered') as delivered
            from public.invoice_special_goods_out(p_invoice_id) g
           group by g.invoice_item_id, g.line_kind, g.special_product_id) o
    left join public.invoice_items it on it.id = o.invoice_item_id and it.invoice_id = p_invoice_id
   where it.id is null or it.line_kind::text <> o.line_kind
      or it.special_product_id is distinct from o.special_product_id
      or greatest(coalesce(it.quantity, 1), 1) < o.qty;
  if v_list is not null then
    raise exception 'GOODS_HANDED_OVER: This correction takes off items the customer already has: %. Record them as returned first (Record items returned on the invoice, Owner or Manager; a rental already released comes back with its Return on Special & Rentals), then correct the invoice.', v_list;
  end if;
end $fn$;

create or replace function public.invoice_special_goods_block(p_invoice_id uuid, p_what text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
-- 547 (the Owner, 27 Nov 2026, answer 8): an invoice with a special, consignment or rental item
-- the customer has (recorded as Collected or Delivered, not recorded as returned) is not
-- cancelled, refunded in full or deleted until the item is recorded as returned. p_what is
-- 'cancel', 'refund' or 'delete', for the words. Internal.
declare v_list text; v_no text;
begin
  select string_agg(format('"%s" × %s', coalesce(public.special_product_name(o.special_product_id), 'a special product')
                             || case when o.line_kind = 'rental' then ' (rental)' else '' end, o.qty), ', '
                    order by o.invoice_item_id)
    into v_list
    from (select g.invoice_item_id, g.line_kind, g.special_product_id, sum(g.quantity)::integer as qty
            from public.invoice_special_goods_out(p_invoice_id) g
           group by g.invoice_item_id, g.line_kind, g.special_product_id) o;
  if v_list is null then return; end if;
  select i.invoice_no into v_no from public.invoices i where i.id = p_invoice_id;
  raise exception 'The customer has % from %, recorded as collected or delivered. Record it as returned first (Record items returned on the invoice, Owner or Manager; a rental already released comes back with its Return on Special & Rentals), then %.',
    v_list, coalesce(v_no, 'this invoice'),
    case p_what when 'cancel' then 'cancel the invoice' when 'delete' then 'delete the invoice'
                else 'refund it' end;
end $fn$;

create or replace function public.invoice_special_refund_check(p_invoice_id uuid, p_invoice_item_id uuid,
  p_whole boolean, p_lines jsonb, p_stock jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
-- 547 (the Owner, 27 Nov 2026, answer 8): a refund may not take back a special, consignment or
-- rental item the customer has (recorded as Collected or Delivered, not recorded as returned).
-- On a line with such units, refund_invoice_recorded's line is refused when it
--   * takes the line's whole value back;
--   * is a rental's line (a rental out with the customer comes back through its own Return);
--   * answers for the stock of a unit the customer has (back, damaged or not returned); or
--   * says the customer is not taking a waiting unit that the customer has.
-- A part refund on such a line that answers only for other units goes through. Internal.
declare v_out integer; v_kind text; v_name text;
begin
  select coalesce(sum(g.quantity), 0)::integer, min(g.line_kind),
         min(coalesce(public.special_product_name(g.special_product_id), 'a special product'))
    into v_out, v_kind, v_name
    from public.invoice_special_goods_out(p_invoice_id) g where g.invoice_item_id = p_invoice_item_id;
  if v_out = 0 then return; end if;
  if p_whole or v_kind = 'rental'
     or exists (select 1 from jsonb_array_elements(case when jsonb_typeof(p_stock) = 'array' then p_stock else '[]'::jsonb end) a
                  join public.special_sales s on s.release_movement_id::text = a->>'movement_id'
                 where s.invoice_id = p_invoice_id and s.invoice_item_id = p_invoice_item_id
                   and public.special_doc_collected('special_sale', s.id))
     or exists (select 1 from jsonb_array_elements(case when jsonb_typeof(p_lines) = 'array' then p_lines else '[]'::jsonb end) pl,
                     jsonb_array_elements(case when jsonb_typeof(pl->'waiting') = 'array' then pl->'waiting' else '[]'::jsonb end) q
                 where jsonb_typeof(q->'still_taking') = 'boolean' and not (q->>'still_taking')::boolean
                   and (public.special_doc_collected('special_sale', (select s.id from public.special_sales s
                                                                       where s.id::text = lower(q->>'doc_id') and s.invoice_id = p_invoice_id))
                        or public.special_doc_collected('rental', (select r.id from public.rentals r
                                                                     where r.id::text = lower(q->>'doc_id') and r.invoice_id = p_invoice_id)))) then
    raise exception 'The customer has % of "%"%, recorded as collected or delivered. Record it as returned first (Record items returned on the invoice, Owner or Manager; a rental already released comes back with its Return on Special & Rentals), then refund it.',
      v_out, v_name, case when v_kind = 'rental' then ' (rental)' else '' end;
  end if;
end $fn$;
$def$;
  c_new_3 constant text := $def$create or replace function public.invoice_special_collect_internal(p_invoice_id uuid, p_handover_id uuid, p_specials jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
-- 547 (the Owner, 27 Nov 2026): special, consignment and rental items the customer picked up
-- (Collected), or a supplier brought to the customer's address (Delivered: a consignment
-- product's line only), recorded on the invoice under a hand-over (invoice_handover_internal,
-- which has locked the invoice and checked who and when). p_specials is
-- [{"invoice_item_id": ..., "qty": n, "how": "collected" | "delivered"}], already checked and in
-- order. No stock moves here: stock moves only when an Owner or Manager releases the item on
-- Special & Rentals ("Waiting for a warehouse", answer 7), before or after this, days apart or
-- not (answer 3). Each unit is taken from what the line already has, released units first, then
-- those waiting; on an invoice not yet paid in full, the units not raised yet are raised now, so
-- they wait for a warehouse (a special sale per unit; a rental for the whole line, collected
-- whole), and the full payment does not raise them again (create_special_docs_for_invoice).
-- Answers [{invoice_item_id, name, quantity, how, docs}].
declare
  i public.invoices%rowtype; e jsonb; li public.invoice_items%rowtype; sp public.special_products%rowtype;
  v_how text; v_qty integer; v_left integer; v_name text; v_early boolean; s record; r record;
  v_take integer; v_sale uuid; v_rent uuid; v_docs text[]; v_units integer; v_live integer;
  v_res jsonb := '[]'::jsonb; v_no text;
begin
  select * into i from public.invoices where id = p_invoice_id;
  v_early := public.invoice_before_full_payment(i.id);
  for e in select q.value from jsonb_array_elements(coalesce(p_specials, '[]'::jsonb)) q loop
    v_qty := (e->>'qty')::integer; v_how := e->>'how'; v_docs := '{}';
    select * into li from public.invoice_items
     where id = (e->>'invoice_item_id')::uuid and invoice_id = i.id
       and line_kind::text in ('special_product', 'rental') and special_product_id is not null;
    if not found then
      raise exception 'That special, consignment or rental item is not on %', i.invoice_no; end if;
    select * into sp from public.special_products where id = li.special_product_id;
    v_name := coalesce(public.special_product_name(li.special_product_id), 'Special product')
              || case when li.line_kind::text = 'rental' then ' (rental)' else '' end;
    if v_how = 'delivered' and not (li.line_kind::text = 'special_product' and coalesce(sp.is_consignment, false)) then
      raise exception '"%" cannot be recorded as Delivered: only a consignment product that its supplier sends to the customer is. Record it as Collected.', v_name; end if;
    select l.to_collect into v_left from public.invoice_special_lines(i.id) l where l.invoice_item_id = li.id;
    if v_qty > coalesce(v_left, 0) then
      raise exception 'Only % of "%" is still to collect on % (recording %)', coalesce(v_left, 0), v_name, i.invoice_no, v_qty; end if;

    if li.line_kind::text = 'special_product' then
      v_take := v_qty;
      -- What the line has: released units first (oldest release), then those waiting.
      for s in select x.id, x.sale_no from public.special_sales x
                where x.invoice_id = i.id and x.invoice_item_id = li.id and x.status <> 'cancelled'
                  and not public.special_doc_collected('special_sale', x.id)
                  and not coalesce((select rr.quantity - rr.resolved_quantity <= 0 from public.special_release_rows(i.id) rr
                                     where rr.movement_id = x.release_movement_id), false)
                order by (x.warehouse_id is null and x.source_store_id is null and x.supplier_id is null),
                         x.fulfilled_at, x.sale_no
                for update
      loop
        exit when v_take <= 0;
        insert into public.invoice_special_handover_lines
          (handover_id, invoice_id, invoice_item_id, line_kind, special_product_id, how, quantity, special_sale_id, created_by)
        values (p_handover_id, i.id, li.id, 'special_product', li.special_product_id, v_how, 1, s.id, auth.uid());
        v_docs := v_docs || s.sale_no; v_take := v_take - 1;
      end loop;
      -- The units not raised yet, on an invoice not yet paid in full: raised now, one sale each,
      -- as create_special_docs_for_invoice raises them, so they wait for a warehouse.
      if v_take > 0 then
        select count(*)::integer into v_live from public.special_sales x
         where x.invoice_id = i.id and x.invoice_item_id = li.id and x.status <> 'cancelled';
        if not v_early or v_take > greatest(coalesce(li.quantity, 1), 1) - v_live then
          raise exception 'Only % of "%" is still to collect on % (recording %)', v_qty - v_take, v_name, i.invoice_no, v_qty; end if;
        for k in 1 .. v_take loop
          v_no := 'SPS-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.special_sale_no_seq')::text, 4, '0');
          insert into public.special_sales
            (sale_no, special_product_id, warehouse_id, customer_id, store_id, quantity,
             unit_price, total_amount, payment_method_id, notes, status, sold_by,
             invoice_id, invoice_item_id)
          values (v_no, li.special_product_id, null, i.customer_id, i.store_id, 1,
                  round(coalesce(li.unit_price, 0), 2), round(coalesce(li.unit_price, 0), 2),
                  null, 'From invoice ' || i.invoice_no || ', '
                        || case when v_how = 'delivered' then 'delivered' else 'collected' end || ' before full payment',
                  'pending', auth.uid(), i.id, li.id)
          returning id into v_sale;
          insert into public.invoice_special_handover_lines
            (handover_id, invoice_id, invoice_item_id, line_kind, special_product_id, how, quantity, special_sale_id, created_by)
          values (p_handover_id, i.id, li.id, 'special_product', li.special_product_id, v_how, 1, v_sale, auth.uid());
          v_docs := v_docs || v_no;
        end loop;
        perform public.write_audit_ex('invoices', i.id, 'special_docs_awaiting_fulfilment', null,
          jsonb_build_object('count', v_take, 'invoice_no', i.invoice_no, 'invoice_item_id', li.id,
                             'collected_before_full_payment', true, 'handover_id', p_handover_id),
          'special', null, i.store_id);
      end if;
    else
      v_take := v_qty;
      -- The line's rentals still to collect: out with the customer first, then those waiting.
      for r in select x.id, x.rental_no,
                      greatest(x.quantity - coalesce((select sum(g.quantity) from public.invoice_special_goods_out(i.id) g
                                                       where g.rental_id = x.id), 0), 0)::integer as free
                 from public.rentals x
                where x.invoice_id = i.id and x.invoice_item_id = li.id
                  and (x.status::text = 'awaiting_fulfilment' or public.rental_is_outstanding(x.status::text))
                  and not coalesce(x.stock_returned, false)
                order by (x.status::text = 'awaiting_fulfilment'), x.fulfilled_at, x.rental_no
                for update
      loop
        exit when v_take <= 0;
        continue when r.free <= 0;
        insert into public.invoice_special_handover_lines
          (handover_id, invoice_id, invoice_item_id, line_kind, special_product_id, how, quantity, rental_id, created_by)
        values (p_handover_id, i.id, li.id, 'rental', li.special_product_id, v_how, least(r.free, v_take), r.id, auth.uid());
        v_docs := v_docs || r.rental_no; v_take := v_take - least(r.free, v_take);
      end loop;
      if v_take > 0 then
        -- Not raised yet, on an invoice not yet paid in full: the line's rental is raised now, as
        -- the full payment raises it (create_special_docs_for_invoice), for all its units, so a
        -- rental is collected whole.
        v_units := greatest(coalesce(li.quantity, 1), 1);
        select coalesce(sum(x.quantity), 0)::integer into v_live from public.rentals x
         where x.invoice_id = i.id and x.invoice_item_id = li.id and x.status::text <> 'cancelled';
        if not v_early or v_live > 0 or v_take > v_units then
          raise exception 'Only % of "%" is still to collect on % (recording %)', v_qty - v_take, v_name, i.invoice_no, v_qty; end if;
        if v_take <> v_units then
          raise exception 'A rental is collected whole: record all % of "%" on %, as it goes out together.', v_units, v_name, i.invoice_no; end if;
        v_no := 'RNT-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.rental_no_seq')::text, 4, '0');
        insert into public.rentals
          (rental_no, special_product_id, warehouse_id, customer_id, store_id, quantity,
           rate_type, rate_amount, periods, rental_fee, start_date, expected_return_date,
           status, notes, created_by, invoice_id, invoice_item_id, late_fee_per_day, paid_at)
        values (v_no, li.special_product_id, null, i.customer_id, i.store_id, v_units,
           coalesce(li.rental_rate_type, 'day'),
           round(round(coalesce(li.line_total, 0), 2) / greatest(coalesce(li.rental_periods, 1), 1), 2),
           greatest(coalesce(li.rental_periods, 1), 1),
           round(coalesce(li.line_total, 0), 2),
           coalesce(li.rental_start_date, public.sg_today()),
           coalesce(li.rental_return_date,
             (coalesce(li.rental_start_date, public.sg_today()) + case coalesce(li.rental_rate_type, 'day')
                when 'day' then make_interval(days => greatest(coalesce(li.rental_periods, 1), 1))
                when 'week' then make_interval(days => 7 * greatest(coalesce(li.rental_periods, 1), 1))
                when 'month' then make_interval(months => greatest(coalesce(li.rental_periods, 1), 1))
                else make_interval(years => greatest(coalesce(li.rental_periods, 1), 1)) end)::date),
           'awaiting_fulfilment', 'From invoice ' || i.invoice_no || ', collected before full payment', auth.uid(),
           i.id, li.id, coalesce(sp.late_fee_per_day, 0), null)
        returning id into v_rent;
        insert into public.invoice_special_handover_lines
          (handover_id, invoice_id, invoice_item_id, line_kind, special_product_id, how, quantity, rental_id, created_by)
        values (p_handover_id, i.id, li.id, 'rental', li.special_product_id, v_how, v_units, v_rent, auth.uid());
        v_docs := v_docs || v_no;
        perform public.write_audit_ex('invoices', i.id, 'special_docs_awaiting_fulfilment', null,
          jsonb_build_object('count', 1, 'invoice_no', i.invoice_no, 'invoice_item_id', li.id,
                             'collected_before_full_payment', true, 'handover_id', p_handover_id),
          'special', null, i.store_id);
      end if;
    end if;
    v_res := v_res || jsonb_build_array(jsonb_build_object('invoice_item_id', li.id, 'name', v_name,
               'quantity', v_qty, 'how', v_how, 'docs', to_jsonb(v_docs)));
  end loop;
  return v_res;
end $fn$;
$def$;
  c_new_4 constant text := $def$create or replace function public.special_waiting_collected(p_doc_ids uuid[])
returns table(doc_kind text, doc_id uuid, how text)
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select public.require_active_staff('{owner,manager}');  -- as the waiting list itself (406)
  -- 547 (the Owner, 27 Nov 2026): of the items asked about (the "Waiting for a warehouse" list),
  -- those the customer already has: recorded on the invoice as Collected or, sent by a supplier,
  -- Delivered, and not recorded as returned; 'delivered' when any of its units was. So an Owner or
  -- Manager sees what to release first. Only invoices of the caller's stores; at most 1,000 asked.
  select case when h.special_sale_id is not null then 'special_sale' else 'rental' end,
         coalesce(h.special_sale_id, h.rental_id),
         case when bool_or(h.how = 'delivered') then 'delivered' else 'collected' end
    from public.invoice_special_handover_lines h
    join public.invoices i on i.id = h.invoice_id
   where coalesce(h.special_sale_id, h.rental_id) = any (coalesce(p_doc_ids, '{}'::uuid[]))
     and cardinality(coalesce(p_doc_ids, '{}'::uuid[])) <= 1000
     and i.deleted_at is null
     and public.user_has_store_access(i.store_id)
     and public.special_doc_collected(case when h.special_sale_id is not null then 'special_sale' else 'rental' end,
                                      coalesce(h.special_sale_id, h.rental_id))
   group by 1, 2
$fn$;
$def$;
  c_rep_0 constant text := $def$create or replace function public.invoice_handover_internal(p_invoice_id uuid, p_handover jsonb, p_request_id uuid, p_source text, p_settlement_request_id uuid DEFAULT NULL::uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
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
-- 547 (the Owner, 27 Nov 2026): and "specials": [{"invoice_item_id": ...,
--               "qty": n, "how": "collected" | "delivered"}], the special,
--               consignment and rental items the customer picked up or a
--               supplier delivered (invoice_special_collect_internal: no stock
--               moves; on an invoice not yet paid in full they now wait for a
--               warehouse). With or without products, on an unpaid, part-paid,
--               paid or completed-FOC invoice (answer 6); products only before
--               full payment, as 399. A settlement that paid the invoice in
--               full records the specials alone. Without "specials" all is as
--               399.
-- The same request id with the same answer returns what it wrote; with a
-- different answer it is refused. A settlement that paid the invoice in full
-- skips the products: every item left the store with that payment.
declare
  i public.invoices%rowtype; h public.invoice_handovers%rowtype;
  v_none boolean; v_raw jsonb; v_items jsonb; v_hash text; e jsonb; x record;
  v_left integer; v_have integer; v_name text; v_store text; v_mov uuid; v_id uuid;
  v_replayed boolean := false; v_res jsonb;
  v547_raw jsonb; v547_specials jsonb; v547_done jsonb := '[]'::jsonb; v547_skip_products boolean := false;  -- 547
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
  -- 547: the special, consignment and rental items.
  v547_raw := coalesce(p_handover->'specials', '[]'::jsonb);
  if jsonb_typeof(v547_raw) <> 'array' then raise exception 'The special items taken must be a list'; end if;
  if v_none and (jsonb_array_length(v_raw) > 0 or jsonb_array_length(v547_raw) > 0) then
    raise exception 'Choose "Nothing taken" or the items taken, not both'; end if;
  if not v_none and jsonb_array_length(v_raw) = 0 and jsonb_array_length(v547_raw) = 0 then
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
  for e in select q.value from jsonb_array_elements(v547_raw) q loop
    if jsonb_typeof(e) <> 'object'
       or coalesce(e->>'invoice_item_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'Every special item taken needs its invoice line'; end if;
    if jsonb_typeof(e->'qty') is distinct from 'number'
       or (e->>'qty')::numeric <> trunc((e->>'qty')::numeric)
       or (e->>'qty')::numeric < 1 or (e->>'qty')::numeric > 100000 then
      raise exception 'Every item taken needs a whole quantity of at least 1'; end if;
    if e ? 'how' and (jsonb_typeof(e->'how') is distinct from 'string' or e->>'how' not in ('collected', 'delivered')) then
      raise exception 'Say whether each special item was Collected or Delivered'; end if;
  end loop;
  -- One row per product, quantities added up, in a fixed order, so a retry
  -- with the same answer hashes the same.
  select coalesce(jsonb_agg(jsonb_build_object('product_id', s.product_id, 'qty', s.qty) order by s.product_id), '[]'::jsonb)
    into v_items
    from (select (q.value->>'product_id')::uuid as product_id, sum((q.value->>'qty')::integer)::integer as qty
            from jsonb_array_elements(v_raw) q group by 1) s;
  -- 547: and one per line and how, the same way.
  select coalesce(jsonb_agg(jsonb_build_object('invoice_item_id', s.line_id, 'qty', s.qty, 'how', s.how)
                            order by s.line_id, s.how), '[]'::jsonb)
    into v547_specials
    from (select (q.value->>'invoice_item_id')::uuid as line_id, coalesce(q.value->>'how', 'collected') as how,
                 sum((q.value->>'qty')::integer)::integer as qty
            from jsonb_array_elements(v547_raw) q group by 1, 2) s;
  v_hash := md5((jsonb_build_object('invoice', i.id, 'none', v_none, 'items', v_items)
                 || case when jsonb_array_length(v547_specials) > 0
                         then jsonb_build_object('specials', v547_specials) else '{}'::jsonb end)::text);  -- 547: as 399 without specials

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
      if jsonb_array_length(v547_specials) = 0 then  -- 547: the special items are still recorded
        return jsonb_build_object('skipped', 'paid_in_full',
          'message', 'Paid in full: every item was taken out of stock with the payment.');
      end if;
      v547_skip_products := true;
    end if;
    if v_none or (jsonb_array_length(v_items) > 0 and not v547_skip_products) then  -- 547: products as 399
      if i.status::text not in ('unpaid', 'partially_paid') then
        raise exception 'Goods are handed over this way only on an unpaid or part-paid invoice (% is %)',
          i.invoice_no, replace(i.status::text, '_', ' '); end if;
      if not v_none and i.fulfil_warehouse_id is not null then
        raise exception '% is set to fulfil from a warehouse, so its goods leave the warehouse when it is paid in full. To hand goods over from the store now, set "Fulfil from" back to this store''s stock first.',
          i.invoice_no; end if;
    end if;
    -- 547 (answers 2 and 6): special, consignment and rental items, before or after full payment.
    if jsonb_array_length(v547_specials) > 0 and i.status::text not in ('unpaid', 'partially_paid', 'paid', 'completed_foc') then
      raise exception 'Special, consignment and rental items are recorded as collected only on an unpaid, part-paid or paid invoice (% is %)',
        i.invoice_no, replace(i.status::text, '_', ' '); end if;
    select s.name into v_store from public.stores s where s.id = i.store_id;

    insert into public.invoice_handovers
      (invoice_id, store_id, kind, source, request_id, request_hash, settlement_request_id, created_by)
    values (i.id, i.store_id, case when v_none then 'nothing_taken' else 'handover' end, p_source,
            p_request_id, v_hash, p_settlement_request_id, auth.uid())
    returning id into v_id;

    for x in select (q.value->>'product_id')::uuid as product_id, (q.value->>'qty')::integer as qty
               from jsonb_array_elements(case when v547_skip_products then '[]'::jsonb else v_items end) q  -- 547
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
    -- 547: the special, consignment and rental items.
    if jsonb_array_length(v547_specials) > 0 then
      v547_done := public.invoice_special_collect_internal(i.id, v_id, v547_specials);
    end if;

    perform public.write_audit_ex('invoices', i.id,
      case when v_none then 'invoice_goods_nothing_taken' else 'invoice_goods_handed_over' end, null,
      jsonb_build_object('invoice_no', i.invoice_no, 'handover_id', v_id, 'source', p_source,
                         'settlement_request_id', p_settlement_request_id,
                         'items', case when v547_skip_products then '[]'::jsonb else v_items end)
        || case when jsonb_array_length(v547_specials) > 0 then jsonb_build_object('specials', v547_done) else '{}'::jsonb end,  -- 547
      'inventory', null, i.store_id);
  end if;

  select jsonb_build_object('success', true, 'replayed', v_replayed, 'handover_id', h2.id,
           'kind', h2.kind, 'source', h2.source, 'invoice_id', h2.invoice_id, 'invoice_no', i.invoice_no,
           'created_at', h2.created_at,
           'items', coalesce((select jsonb_agg(jsonb_build_object('product_id', l.product_id, 'name', p.name,
                                                 'quantity', l.quantity) order by p.name, l.product_id)
                                from public.invoice_handover_lines l
                                left join public.products p on p.id = l.product_id
                               where l.handover_id = h2.id), '[]'::jsonb),
           -- 547: and the special, consignment and rental items, by line and how.
           'specials', coalesce((select jsonb_agg(jsonb_build_object('invoice_item_id', sl.invoice_item_id,
                                                    'name', sl.name, 'quantity', sl.quantity, 'how', sl.how)
                                                  order by sl.name, sl.invoice_item_id, sl.how)
                                   from (select l.invoice_item_id, l.how, sum(l.quantity)::integer as quantity,
                                                coalesce(public.special_product_name(min(l.special_product_id::text)::uuid), 'Special product')
                                                  || case when min(l.line_kind) = 'rental' then ' (rental)' else '' end as name
                                           from public.invoice_special_handover_lines l
                                          where l.handover_id = h2.id group by l.invoice_item_id, l.how) sl), '[]'::jsonb))
    into v_res
    from public.invoice_handovers h2 where h2.id = v_id;
  return v_res;
end $fn$;
$def$;
  c_rep_1 constant text := $def$create or replace function public.record_invoice_goods_return(p_invoice_id uuid, p_items jsonb, p_reason text, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
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
-- 547 (the Owner, 27 Nov 2026, answers 8 and 9): and the special, consignment and
-- rental items recorded as Collected or Delivered: {"invoice_item_id": ..., "returned": n}
-- (they came back), on an unpaid, part-paid, paid or completed-FOC invoice, so it may then be
-- cancelled, corrected or refunded. Spread over the line's records still out, oldest first:
--   * not yet released: no stock moves (none left); on an invoice not yet paid in full the
--     item raised for it is cancelled, and the full payment raises it again; on a paid one it
--     waits for a warehouse again;
--   * released from a warehouse or a store: it goes back on that shelf, as a refund's Back and
--     sellable (return_released_special_stock), and its sale ends;
--   * sent by its supplier: back to the supplier, no stock moves (the consignment rule), and
--     its sale ends;
--   * on a paid invoice a sale that ended is raised again, waiting for a warehouse: the line is
--     still sold, to collect again (answer 6);
--   * a rental released from a warehouse or a store comes back with its own Return on Special &
--     Rentals (late fee and all), not here; a rental not yet released comes back whole.
declare
  i public.invoices%rowtype; h public.invoice_handovers%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  e jsonb; k text; v_items jsonb; v_hash text; x record; g record; v_name text; v_out integer;
  tg integer; td integer; tn integer; v_good integer; v_dam integer; v_nr integer;
  v_ret uuid; v_disp uuid; v_id uuid; v_replayed boolean := false; v_res jsonb;
  v547_specials jsonb; v547_early boolean; v547_left integer; c record; v547_s public.special_sales%rowtype;
  v547_r public.rentals%rowtype; v547_ended_sale uuid; v547_ended_rental uuid; v547_raised uuid;
  v547_mv uuid; v547_no text; v547_products integer;
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
    -- 547: a special, consignment or rental line, by its invoice line.
    if jsonb_typeof(e) = 'object' and e ? 'invoice_item_id' and not e ? 'product_id' then
      if coalesce(e->>'invoice_item_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        raise exception 'Every special item returned needs its invoice line'; end if;
      if jsonb_typeof(e->'returned') is distinct from 'number' or (e->>'returned')::numeric <> trunc((e->>'returned')::numeric)
         or (e->>'returned')::numeric < 0 or (e->>'returned')::numeric > 100000 then
        raise exception 'Returned is a whole number, 0 or more'; end if;
      continue;
    end if;
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
            from jsonb_array_elements(p_items) q where q.value ? 'product_id' group by 1) s
   where s.good + s.damaged + s.not_returned > 0;
  -- 547: one per line, added up, in a fixed order.
  select coalesce(jsonb_agg(jsonb_build_object('invoice_item_id', s.line_id, 'returned', s.n) order by s.line_id), '[]'::jsonb)
    into v547_specials
    from (select (q.value->>'invoice_item_id')::uuid as line_id, sum((q.value->>'returned')::integer)::integer as n
            from jsonb_array_elements(p_items) q where not q.value ? 'product_id' group by 1) s
   where s.n > 0;
  if jsonb_array_length(v_items) = 0 and jsonb_array_length(v547_specials) = 0 then
    raise exception 'Choose at least one item and say how it came back'; end if;
  v_hash := md5((jsonb_build_object('invoice', i.id, 'items', v_items, 'reason', v_reason)
                 || case when jsonb_array_length(v547_specials) > 0
                         then jsonb_build_object('specials', v547_specials) else '{}'::jsonb end)::text);  -- 547: as 399 without specials

  select * into h from public.invoice_handovers where request_id = p_request_id;
  if found then
    if h.invoice_id <> i.id or h.kind <> 'return' or h.request_hash <> v_hash then
      raise exception 'Request % was already used for something else', p_request_id; end if;
    v_id := h.id; v_replayed := true;
  else
    if jsonb_array_length(v_items) > 0  -- 547: products as 399
       and (i.status::text not in ('draft', 'unpaid', 'partially_paid')
            or not public.invoice_before_full_payment(i.id)) then
      raise exception 'Items returned are recorded here only on an unpaid or part-paid invoice not yet paid in full. % is %: use Refund / Cancel, which asks what came back.',
        i.invoice_no, replace(i.status::text, '_', ' '); end if;
    if jsonb_array_length(v547_specials) > 0
       and i.status::text not in ('draft', 'unpaid', 'partially_paid', 'paid', 'completed_foc') then
      raise exception 'Special, consignment and rental items are recorded as returned here only on an unpaid, part-paid or paid invoice (% is %).',
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

    -- 547: the special, consignment and rental items.
    v547_early := i.status::text in ('draft', 'unpaid', 'partially_paid') and public.invoice_before_full_payment(i.id);
    for x in select (q.value->>'invoice_item_id')::uuid as line_id, (q.value->>'returned')::integer as n
               from jsonb_array_elements(v547_specials) q
    loop
      select coalesce(sum(o.quantity), 0)::integer,
             min(coalesce(public.special_product_name(o.special_product_id), 'Special product')
                 || case when o.line_kind = 'rental' then ' (rental)' else '' end)
        into v_out, v_name
        from public.invoice_special_goods_out(i.id) o where o.invoice_item_id = x.line_id;
      if x.n > v_out then
        raise exception 'Only % of "%" is out with the customer on % (recording %)',
          v_out, coalesce(v_name, 'that item'), i.invoice_no, x.n; end if;
      v547_left := x.n;
      for c in select o.* from public.invoice_special_goods_out(i.id) o
                where o.invoice_item_id = x.line_id order by o.created_at, o.collection_id
      loop
        exit when v547_left <= 0;
        v547_ended_sale := null; v547_ended_rental := null; v547_raised := null; v547_mv := null;
        if c.special_sale_id is not null then
          select * into v547_s from public.special_sales where id = c.special_sale_id for update;
          if v547_s.warehouse_id is not null or v547_s.source_store_id is not null then
            -- Released from a warehouse or a store: back on that shelf (496's own path).
            if v547_s.release_movement_id is null or exists (
                 select 1 from public.special_release_rows(i.id) rr
                  where rr.movement_id = v547_s.release_movement_id and rr.quantity - rr.resolved_quantity <= 0) then
              raise exception '%: the stock of % has already been settled, so it cannot come back here.', v547_s.sale_no, v_name; end if;
            perform public.return_released_special_stock(i.id, v547_s.release_movement_id, 1, 0, 0, p_request_id, v_reason, 'item returned');
            select ssr.return_movement_id into v547_mv from public.special_sale_returns ssr
             where ssr.movement_id = v547_s.release_movement_id and ssr.request_id = p_request_id;
            v547_ended_sale := v547_s.id;
          elsif v547_s.supplier_id is not null then
            -- Sent by its supplier: back to the supplier; no stock moves (494).
            update public.special_sales
               set status = 'cancelled', cancelled_at = now(),
                   notes = concat_ws(E'\n', notes, 'Returned to ' || coalesce((select u.name from public.suppliers u where u.id = v547_s.supplier_id), 'the supplier')
                                     || ', no stock moves (' || i.invoice_no || '): ' || v_reason)
             where id = v547_s.id;
            perform public.write_audit_ex('special_sales', v547_s.id, 'special_sale_returned', jsonb_build_object('status', v547_s.status),
              jsonb_build_object('status', 'cancelled', 'doc_no', v547_s.sale_no, 'why', 'item returned', 'supplier_id', v547_s.supplier_id,
                                 'invoice_id', i.id, 'request_id', p_request_id),
              'special', v_reason, v547_s.store_id);
            v547_ended_sale := v547_s.id;
          elsif v547_early then
            -- Not released, on an invoice not yet paid in full: off the waiting list; the full
            -- payment raises the unit again.
            perform public.cancel_waiting_special_docs(i.id, 'returned before full payment', v_reason, null, array[v547_s.id]);
            v547_ended_sale := v547_s.id;
          end if;
          -- On a paid invoice the line still holds the unit: it waits for a warehouse again.
          if v547_ended_sale is not null and not v547_early then
            v547_no := 'SPS-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.special_sale_no_seq')::text, 4, '0');
            insert into public.special_sales
              (sale_no, special_product_id, warehouse_id, customer_id, store_id, quantity,
               unit_price, total_amount, payment_method_id, notes, status, sold_by, invoice_id, invoice_item_id)
            select v547_no, v547_s.special_product_id, null, i.customer_id, i.store_id, 1,
                   round(coalesce(it.unit_price, v547_s.unit_price, 0), 2), round(coalesce(it.unit_price, v547_s.unit_price, 0), 2),
                   null, 'From invoice ' || i.invoice_no || ', in place of ' || v547_s.sale_no || ', returned', 'pending', auth.uid(),
                   i.id, v547_s.invoice_item_id
              from (select 1) one left join public.invoice_items it on it.id = v547_s.invoice_item_id
            returning id into v547_raised;
            perform public.write_audit_ex('invoices', i.id, 'special_docs_awaiting_fulfilment', null,
              jsonb_build_object('count', 1, 'invoice_no', i.invoice_no, 'invoice_item_id', v547_s.invoice_item_id,
                                 'in_place_of', v547_s.sale_no, 'request_id', p_request_id),
              'special', v_reason, i.store_id);
          end if;
          insert into public.invoice_special_handover_returns
            (handover_id, invoice_id, collection_id, quantity, ended_sale_id, raised_sale_id, return_movement_id, created_by)
          values (v_id, i.id, c.collection_id, 1, v547_ended_sale, v547_raised, v547_mv, auth.uid());
          v547_left := v547_left - 1;
        else
          select * into v547_r from public.rentals where id = c.rental_id for update;
          if v547_r.warehouse_id is not null or v547_r.source_store_id is not null then
            raise exception '% (%) is out with the customer from % and comes back with its own Return on Special & Rentals, which puts it back in stock (and asks about a late fee). Record that Return first.',
              v547_r.rental_no, v_name,
              coalesce((select w.name from public.warehouses w where w.id = v547_r.warehouse_id),
                       (select t.name from public.stores t where t.id = v547_r.source_store_id), 'stock');
          end if;
          if v547_early then
            -- Not released, on an invoice not yet paid in full: a rental comes back whole, off the
            -- waiting list; the full payment raises it again.
            if v547_left < c.quantity then
              raise exception 'A rental comes back whole: record all % of "%" (%) as returned.', c.quantity, v_name, v547_r.rental_no; end if;
            perform public.cancel_waiting_special_docs(i.id, 'returned before full payment', v_reason, null, array[v547_r.id]);
            v547_ended_rental := v547_r.id;
          end if;
          insert into public.invoice_special_handover_returns
            (handover_id, invoice_id, collection_id, quantity, ended_rental_id, created_by)
          values (v_id, i.id, c.collection_id, least(c.quantity, v547_left), v547_ended_rental, auth.uid());
          v547_left := v547_left - least(c.quantity, v547_left);
        end if;
      end loop;
    end loop;

    perform public.write_audit_ex('invoices', i.id, 'invoice_goods_returned', null,
      jsonb_build_object('invoice_no', i.invoice_no, 'handover_id', v_id, 'items', v_items)
        || case when jsonb_array_length(v547_specials) > 0 then jsonb_build_object('specials', v547_specials) else '{}'::jsonb end,  -- 547
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
                                left join public.products p on p.id = r.product_id), '[]'::jsonb),
           -- 547: and the special, consignment and rental items, by line.
           'specials', coalesce((select jsonb_agg(jsonb_build_object('invoice_item_id', q.invoice_item_id, 'name', q.name,
                                                    'returned', q.n) order by q.name, q.invoice_item_id)
                                   from (select l.invoice_item_id, sum(b.quantity)::integer as n,
                                                coalesce(public.special_product_name(min(l.special_product_id::text)::uuid), 'Special product')
                                                  || case when min(l.line_kind) = 'rental' then ' (rental)' else '' end as name
                                           from public.invoice_special_handover_returns b
                                           join public.invoice_special_handover_lines l on l.id = b.collection_id
                                          where b.handover_id = v_id group by l.invoice_item_id) q), '[]'::jsonb))
    into v_res;
  return v_res;
end $fn$;
$def$;
  c_rep_2 constant text := $def$create or replace function public.invoice_goods_status(p_invoice_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
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
-- 547 (the Owner, 27 Nov 2026): and "specials", per special, consignment or
-- rental line (invoice_special_lines): its units, Collected and Delivered as
-- staff recorded them, out with the customer, and still to collect, on a
-- paid invoice too (answer 6); "can_collect_special" for the hand-over's
-- Collected / Delivered (staff of the invoice's store, answer 9), and
-- "can_record_special_return" for Record items returned (Owner/Manager).
-- The history lists the special items each hand-over and return recorded.
-- The products and their flags are as 399's.
declare
  i public.invoices%rowtype; v_products jsonb; v_history jsonb;
  v_required integer; v_collected integer; v_to_collect integer; v_out integer;
  v_open boolean;
  v547_specials jsonb; v547_collected integer; v547_delivered integer; v547_out integer; v547_to_collect integer;  -- 547
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

  -- 547: the special, consignment and rental lines.
  select coalesce(jsonb_agg(jsonb_build_object(
           'invoice_item_id', l.invoice_item_id, 'line_kind', l.line_kind, 'special_product_id', l.special_product_id,
           'name', l.name, 'is_consignment', l.is_consignment, 'quantity', l.quantity,
           'collected', l.collected, 'delivered', l.delivered, 'out', l.out_qty, 'to_collect', l.to_collect,
           'can_deliver', l.line_kind = 'special_product' and l.is_consignment)
           order by l.name, l.invoice_item_id), '[]'::jsonb),
         coalesce(sum(l.collected), 0)::integer, coalesce(sum(l.delivered), 0)::integer,
         coalesce(sum(l.out_qty), 0)::integer, coalesce(sum(l.to_collect), 0)::integer
    into v547_specials, v547_collected, v547_delivered, v547_out, v547_to_collect
    from public.invoice_special_lines(i.id) l;

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
                          where l.handover_id = h.id), '[]'::jsonb) end
           -- 547: and its special, consignment and rental items.
           || case when h.kind = 'return' then
               coalesce((select jsonb_agg(jsonb_build_object('invoice_item_id', q.invoice_item_id, 'name', q.name,
                                            'returned', q.n, 'special', true) order by q.name, q.invoice_item_id)
                           from (select sl.invoice_item_id, sum(b.quantity)::integer as n,
                                        coalesce(public.special_product_name(min(sl.special_product_id::text)::uuid), 'Special product')
                                          || case when min(sl.line_kind) = 'rental' then ' (rental)' else '' end as name
                                   from public.invoice_special_handover_returns b
                                   join public.invoice_special_handover_lines sl on sl.id = b.collection_id
                                  where b.handover_id = h.id group by sl.invoice_item_id) q), '[]'::jsonb)
             else
               coalesce((select jsonb_agg(jsonb_build_object('invoice_item_id', q.invoice_item_id, 'name', q.name,
                                            'quantity', q.n, 'how', q.how, 'special', true) order by q.name, q.invoice_item_id, q.how)
                           from (select sl.invoice_item_id, sl.how, sum(sl.quantity)::integer as n,
                                        coalesce(public.special_product_name(min(sl.special_product_id::text)::uuid), 'Special product')
                                          || case when min(sl.line_kind) = 'rental' then ' (rental)' else '' end as name
                                   from public.invoice_special_handover_lines sl
                                  where sl.handover_id = h.id group by sl.invoice_item_id, sl.how) q), '[]'::jsonb) end)
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
    'products', v_products, 'history', v_history,
    -- 547
    'specials', v547_specials, 'special_collected_total', v547_collected, 'special_delivered_total', v547_delivered,
    'special_out_total', v547_out, 'special_to_collect_total', v547_to_collect,
    'can_collect_special', i.status::text in ('unpaid', 'partially_paid', 'paid', 'completed_foc') and v547_to_collect > 0,
    'can_record_special_return', i.status::text in ('draft', 'unpaid', 'partially_paid', 'paid', 'completed_foc')
                                 and v547_out > 0 and public.is_owner_or_manager());
end $fn$;
$def$;
  c_rep_3 constant text := $def$create or replace function public.invoice_list_goods_out(p_invoice_ids uuid[])
returns table(invoice_id uuid, quantity integer)
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select public.inventory_manager_guard('stock');  -- 540 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026: "Stock only")
  -- 399: the Invoices list's "Goods out" badge: of the invoices asked about,
  -- the unpaid and part-paid ones of the caller's stores with goods out with
  -- the customer, and how many.
  -- 547 (the Owner, 27 Nov 2026): special, consignment and rental items recorded as
  -- collected or delivered and not returned count too.
  select i.id, sum(g.quantity)::integer
    from public.invoices i
    cross join lateral (select o.quantity from public.invoice_goods_out(i.id) o
                        union all
                        select so.quantity from public.invoice_special_goods_out(i.id) so) g
   where i.id = any(coalesce(p_invoice_ids, '{}'::uuid[]))
     and cardinality(coalesce(p_invoice_ids, '{}'::uuid[])) <= 1000
     and i.deleted_at is null
     and i.status::text in ('draft', 'unpaid', 'partially_paid')
     and public.invoice_before_full_payment(i.id)
     and public.current_user_role() is not null
     and public.user_has_store_access(i.store_id)
   group by i.id
$fn$;
$def$;
  c_tables constant text := $ddl$    create table public.invoice_special_handover_lines (
      id uuid primary key default gen_random_uuid(),
      handover_id uuid not null references public.invoice_handovers(id),
      invoice_id uuid not null references public.invoices(id),
      invoice_item_id uuid not null,
      line_kind text not null check (line_kind in ('special_product', 'rental')),
      special_product_id uuid not null references public.special_products(id),
      how text not null check (how in ('collected', 'delivered')),
      quantity integer not null check (quantity > 0),
      special_sale_id uuid references public.special_sales(id),
      rental_id uuid references public.rentals(id),
      created_by uuid references public.profiles(id),
      created_at timestamptz not null default clock_timestamp(),
      constraint invoice_special_handover_lines_doc check (
        (line_kind = 'special_product' and special_sale_id is not null and rental_id is null and quantity = 1)
        or (line_kind = 'rental' and rental_id is not null and special_sale_id is null)),
      constraint invoice_special_handover_lines_delivered check (how = 'collected' or line_kind = 'special_product'));
    create index invoice_special_handover_lines_by_invoice on public.invoice_special_handover_lines (invoice_id, created_at);
    create index invoice_special_handover_lines_by_line on public.invoice_special_handover_lines (invoice_item_id);
    create index invoice_special_handover_lines_by_sale on public.invoice_special_handover_lines (special_sale_id) where special_sale_id is not null;
    create index invoice_special_handover_lines_by_rental on public.invoice_special_handover_lines (rental_id) where rental_id is not null;
    comment on table public.invoice_special_handover_lines is
      '547: special, consignment and rental items recorded on an invoice as Collected (the customer picked it up) or Delivered (its supplier brought it to the customer). No stock moves: an Owner or Manager releases the item on Special & Rentals.';
    create table public.invoice_special_handover_returns (
      id uuid primary key default gen_random_uuid(),
      handover_id uuid not null references public.invoice_handovers(id),
      invoice_id uuid not null references public.invoices(id),
      collection_id uuid not null references public.invoice_special_handover_lines(id),
      quantity integer not null check (quantity > 0),
      ended_sale_id uuid references public.special_sales(id),
      ended_rental_id uuid references public.rentals(id),
      raised_sale_id uuid references public.special_sales(id),
      return_movement_id uuid references public.stock_movements(id),
      created_by uuid references public.profiles(id),
      created_at timestamptz not null default clock_timestamp());
    create index invoice_special_handover_returns_by_invoice on public.invoice_special_handover_returns (invoice_id);
    create index invoice_special_handover_returns_by_collection on public.invoice_special_handover_returns (collection_id);
    create index invoice_special_handover_returns_by_ended_sale on public.invoice_special_handover_returns (ended_sale_id) where ended_sale_id is not null;
    create index invoice_special_handover_returns_by_ended_rental on public.invoice_special_handover_returns (ended_rental_id) where ended_rental_id is not null;
    comment on table public.invoice_special_handover_returns is
      '547: Record items returned for special, consignment and rental items recorded as Collected or Delivered: the sale or rental it ended, the sale raised in its place on a paid invoice, the stock movement that put it back.';
    alter table public.invoice_special_handover_lines enable row level security;
    alter table public.invoice_special_handover_returns enable row level security;
    create policy invoice_special_handover_lines_read on public.invoice_special_handover_lines for select to authenticated
      using ((select public.current_user_role()) is distinct from 'inventory_manager'::public.user_role
             and exists (select 1 from public.invoices i where i.id = invoice_special_handover_lines.invoice_id
                           and ((select public.is_owner_or_admin()) or i.store_id = any ((select public.current_user_store_ids())::uuid[]))));
    create policy invoice_special_handover_returns_read on public.invoice_special_handover_returns for select to authenticated
      using ((select public.current_user_role()) is distinct from 'inventory_manager'::public.user_role
             and exists (select 1 from public.invoices i where i.id = invoice_special_handover_returns.invoice_id
                           and ((select public.is_owner_or_admin()) or i.store_id = any ((select public.current_user_store_ids())::uuid[]))));
    revoke all on table public.invoice_special_handover_lines, public.invoice_special_handover_returns from public, anon, authenticated;
    grant select on table public.invoice_special_handover_lines, public.invoice_special_handover_returns to authenticated;
    grant all on table public.invoice_special_handover_lines, public.invoice_special_handover_returns to service_role;
    alter table public.special_sale_returns drop constraint special_sale_returns_why_check;
    alter table public.special_sale_returns add constraint special_sale_returns_why_check
      check (why = any (array['refunded'::text, 'invoice cancelled'::text, 'line corrected'::text, 'item returned'::text]));
    alter table public.invoice_handovers drop constraint invoice_handovers_source_check;
    alter table public.invoice_handovers add constraint invoice_handovers_source_check
      check (source = any (array['payment'::text, 'button'::text, 'return'::text, 'migration'::text]));
$ddl$;
  -- Relied on, not changed: signature, md5 (production after 546).
  c_relied constant text[][] := array[
    ['invoice_goods_out(uuid)', 'fe2f1027d909ad583d543705032a3a1e'],
    ['invoice_before_full_payment(uuid)', '3cce8331cd3e70533476d496b3136ac6'],
    ['invoice_goods_kept_check(uuid)', '41a35dbcdb5a0a6f1e7c00b744c9ee69'],
    ['record_invoice_handover(uuid,jsonb,uuid)', '7234e8bb7f2ed2cfefa8354bb9843d2d'],
    ['record_invoice_settlement(uuid,jsonb,uuid)', 'bec4ba292611157069c6813d22d04b9b'],
    ['special_release_rows(uuid)', 'c1e16752967057f76eb137715f9e0fba'],
    ['cancel_waiting_special_docs(uuid,text,text,uuid,uuid[])', '55a131c9d24d99dd2d94944adafb792f'],
    ['special_docs_awaiting_fulfilment()', '21f5ba85c24a12e8d66861bf39cd6965'],
    ['special_doc_invoice_problem(uuid,uuid)', '4e01429ca76a96693413c2a114cc68a2'],
    ['invoice_rentals_follow_lines(uuid,jsonb,text)', '3e085fe3fe9d100238c21616b8e55ef4'],
    ['settle_waiting_special_docs_on_refund(uuid,jsonb,text)', 'a3c4c94656a56eb371ced34ea0ac1db3'],
    ['rentals_follow_refund(uuid,jsonb,text)', 'fdb2ac652f54e682508bc07d7f13dccb'],
    ['invoice_record_payments_internal(uuid,jsonb)', 'b37cdee8b7f914ed2d625b8b0620dbfd'],
    ['confirm_foc_invoice(uuid,text)', '3e5cbdb24584c5e2e39cf9009ba53233'],
    ['reopen_invoice(uuid,text,uuid)', 'bc8a4eaba95f928f2e9718a90d9fdd56'],
    ['return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text)', '64bfeda29df82a38145a56c53e8a657f'],
    ['cancel_invoice_rentals(uuid,text)', '28a1904b1766601d41a36864b053c60a'],
    ['special_product_name(uuid)', 'a2a04103c9cdbf21073dd01fa476c8d0'],
    ['rental_is_outstanding(text)', '076549a44bc057cd529aac5542c4d06e'],
    ['user_has_store_access(uuid)', 'd5a5806b9f7352d8ecc34c77fa8af1d9'],
    ['is_owner_or_manager()', '98600ad0a0afb459eae90645dac27b08'],
    ['inventory_manager_guard(text)', 'c470323811ae7acd8049d51f9c2d8f6f'],
    ['invoice_required_stock(uuid)', 'dfb1cb171b0a1cc6d9524b7be1bd890e'],
    ['invoice_stock_to_deduct(uuid)', '0e26025476f6eecfccdf3f4ae806d643'],
    ['sg_today()', '1c1289f18e24d8370e9a6364c9c06fca'],
    ['invoice_charge_total(uuid)', 'af05fb2013665d886fb4d3b95946b9e3'],
    ['invoice_net_received(uuid)', 'd7198edbdf9f28269d4a42e2d3dd2141'],
    ['invoice_discounted_line_value(uuid)', '8e5617c9262781652e6c63a255766d16'],
    ['write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', '6f3e0aa6b4b117c160d8c4e488bb29ed'],
    ['require_active_staff(text[])', '93662edd89c9fe60216a7756e1f1e8e9']
  ];
  -- Changed: signature, BEFORE (production after 546), AFTER.
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
  -- New: signature, AFTER.
  c_new_sigs constant text[][] := array[
    ['invoice_special_goods_out(uuid)', '81e3e1bc5140850dae4bb9fb2f184335'],
    ['invoice_special_lines(uuid)', '41721086125e3568f5a30b406dbf921b'],
    ['special_doc_collected(text,uuid)', '99071814bbbea40893e9bf1da0da6ee6'],
    ['invoice_special_kept_check(uuid)', '5f485793a470315a1b837d0bf1d45e8f'],
    ['invoice_special_goods_block(uuid,text)', 'e7ce1c0f3bf0d489da02efa94c9afa4c'],
    ['invoice_special_refund_check(uuid,uuid,boolean,jsonb,jsonb)', 'e788ddb40f0da357c2457cea8b374259'],
    ['invoice_special_collect_internal(uuid,uuid,jsonb)', 'ecedcfb87bbb9cacde6cc3c613d3c48c'],
    ['special_waiting_collected(uuid[])', '49012eecc99ca8128c780479db683a8d']
  ];
  c_check_after constant boolean := true;
  v_path text := current_setting('search_path');
  v_def text; v_defs text[] := '{}'; v_n integer; v_md5 text; v_at_after integer := 0; v_at_before integer := 0;
  v_new_there integer := 0; v_tables integer; k integer;
begin
  perform set_config('search_path', 'public', true);
  -- 0. Already in? Every changed and new function at its AFTER text and the tables there.
  select count(*) into v_tables from pg_class where relnamespace = 'public'::regnamespace
     and relname in ('invoice_special_handover_lines', 'invoice_special_handover_returns') and relkind = 'r';
  for k in 1 .. array_length(c_changed, 1) loop
    v_md5 := md5(pg_get_functiondef(to_regprocedure('public.' || c_changed[k][1])));
    if v_md5 = c_changed[k][3] then v_at_after := v_at_after + 1;
    elsif v_md5 = c_changed[k][2] then v_at_before := v_at_before + 1;
    else raise exception '547: public.% is not the version this was made for (md5 %). Is 546 in? Nothing was changed.', c_changed[k][1], v_md5; end if;
  end loop;
  for k in 1 .. array_length(c_new_sigs, 1) loop
    if to_regprocedure('public.' || c_new_sigs[k][1]) is not null then
      v_new_there := v_new_there + 1;
      if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sigs[k][1]))) <> c_new_sigs[k][2] then
        raise exception '547: public.% already exists with another text. Nothing was changed.', c_new_sigs[k][1]; end if;
    end if;
  end loop;
  if c_check_after and v_at_after = array_length(c_changed, 1) and v_new_there = array_length(c_new_sigs, 1) and v_tables = 2 then
    raise notice '547 is already in on this database; nothing was changed.';
    perform set_config('search_path', v_path, true);
    return;
  end if;
  if v_at_before <> array_length(c_changed, 1) or v_new_there > 0 or v_tables > 0 then
    raise exception '547 is partly in on this database (% of % functions changed, % of % new ones there, % of 2 tables). Nothing was changed.',
      v_at_after, array_length(c_changed, 1), v_new_there, array_length(c_new_sigs, 1), v_tables; end if;
  -- 1. What it relies on, unchanged.
  for k in 1 .. array_length(c_relied, 1) loop
    v_md5 := md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[k][1])));
    if v_md5 is distinct from c_relied[k][2] then
      raise exception '547: public.% is not the version this was tested against (md5 %). Nothing was changed.', c_relied[k][1], v_md5; end if;
  end loop;
  if not exists (select 1 from pg_constraint where conname = 'special_sale_returns_why_check'
                  and conrelid = 'public.special_sale_returns'::regclass
                  and pg_get_constraintdef(oid) = 'CHECK ((why = ANY (ARRAY[''refunded''::text, ''invoice cancelled''::text, ''line corrected''::text])))') then
    raise exception '547: special_sale_returns_why_check is not 497''s. Nothing was changed.'; end if;
  if not exists (select 1 from pg_constraint where conname = 'invoice_handovers_source_check'
                  and conrelid = 'public.invoice_handovers'::regclass
                  and pg_get_constraintdef(oid) = 'CHECK ((source = ANY (ARRAY[''payment''::text, ''button''::text, ''return''::text])))') then
    raise exception '547: invoice_handovers_source_check is not 399''s. Nothing was changed.'; end if;
  -- 2. Every patched text built before anything is installed; each anchor exactly as often as expected.
  v_def := pg_get_functiondef('public.create_special_docs_for_invoice(uuid)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $a$      continue when coalesce(v496_back, 0) <= 0;
$a$, ''))) / length($a$      continue when coalesce(v496_back, 0) <= 0;
$a$);
  if v_n <> 1 then raise exception '547: anchor 1 of public.create_special_docs_for_invoice(uuid) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $a$      continue when coalesce(v496_back, 0) <= 0;
$a$, $r$      -- 547 (the Owner, 27 Nov 2026): a line with units recorded as collected before full payment
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
  v_n := (length(v_def) - length(replace(v_def, $a$      if v458_cnt > 0 and (v458_have >= v458_units or not exists (
$a$, ''))) / length($a$      if v458_cnt > 0 and (v458_have >= v458_units or not exists (
$a$);
  if v_n <> 1 then raise exception '547: anchor 2 of public.create_special_docs_for_invoice(uuid) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $a$      if v458_cnt > 0 and (v458_have >= v458_units or not exists (
$a$, $r$      -- 547 (the Owner, 27 Nov 2026): a line whose rental was collected before full payment: the
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
  v_defs := v_defs || v_def;
  v_def := pg_get_functiondef('public.invoice_special_sales_follow_lines(uuid,jsonb,text,uuid)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $a$                order by 10, s.sale_no desc
$a$, ''))) / length($a$                order by 10, s.sale_no desc
$a$);
  if v_n <> 1 then raise exception '547: anchor 1 of public.invoice_special_sales_follow_lines(uuid,jsonb,text,uuid) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $a$                order by 10, s.sale_no desc
$a$, $r$                order by public.special_doc_collected('special_sale', s.id), 10, s.sale_no desc  -- 547: what the customer has goes last
$r$);
  v_n := (length(v_def) - length(replace(v_def, $a$                        or exists (select 1 from public.special_sales s
                                    where s.invoice_item_id = v_line
$a$, ''))) / length($a$                        or exists (select 1 from public.special_sales s
                                    where s.invoice_item_id = v_line
$a$);
  if v_n <> 1 then raise exception '547: anchor 2 of public.invoice_special_sales_follow_lines(uuid,jsonb,text,uuid) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $a$                        or exists (select 1 from public.special_sales s
                                    where s.invoice_item_id = v_line
$a$, $r$                        -- 547: before full payment, a line with units recorded as collected is
                        -- raised by the payment (create_special_docs_for_invoice raises its rest).
                        or not exists (select 1 from public.invoice_special_handover_lines h547 where h547.invoice_item_id = v_line)
                           and exists (select 1 from public.special_sales s
                                    where s.invoice_item_id = v_line
$r$);
  v_defs := v_defs || v_def;
  v_def := pg_get_functiondef('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $a$if v399_open then perform public.invoice_goods_kept_check(i.id); end if;
$a$, ''))) / length($a$if v399_open then perform public.invoice_goods_kept_check(i.id); end if;
$a$);
  if v_n <> 2 then raise exception '547: anchor 1 of public.correct_invoice(uuid,jsonb,jsonb,text,uuid) found % times, not 2. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $a$if v399_open then perform public.invoice_goods_kept_check(i.id); end if;
$a$, $r$if v399_open then perform public.invoice_goods_kept_check(i.id); end if;
 perform public.invoice_special_kept_check(i.id);  -- 547 (the Owner, 27 Nov 2026, answer 8): paid or not
$r$);
  v_defs := v_defs || v_def;
  v_def := pg_get_functiondef('public.cancel_invoice_recorded(uuid,text,uuid)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $a$ perform public.assert_invoice_credit_source_evidence(i.id);
$a$, ''))) / length($a$ perform public.assert_invoice_credit_source_evidence(i.id);
$a$);
  if v_n <> 1 then raise exception '547: anchor 1 of public.cancel_invoice_recorded(uuid,text,uuid) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $a$ perform public.assert_invoice_credit_source_evidence(i.id);
$a$, $r$ -- 547 (the Owner, 27 Nov 2026, answer 8): not while the customer has a special, consignment or
 -- rental item recorded as collected or delivered and not recorded as returned.
 perform public.invoice_special_goods_block(i.id,'cancel');
 perform public.assert_invoice_credit_source_evidence(i.id);
$r$);
  v_defs := v_defs || v_def;
  v_def := pg_get_functiondef('public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $a$   if it.id is not null and it.line_kind::text='special_product' then
    declare o496$a$, ''))) / length($a$   if it.id is not null and it.line_kind::text='special_product' then
    declare o496$a$);
  if v_n <> 1 then raise exception '547: anchor 1 of public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $a$   if it.id is not null and it.line_kind::text='special_product' then
    declare o496$a$, $r$   -- 547 (the Owner, 27 Nov 2026, answer 8): not a special, consignment or rental item the customer
   -- has (recorded as collected or delivered, not recorded as returned).
   if it.id is not null and it.line_kind::text in ('special_product','rental') then
     perform public.invoice_special_refund_check(i.id,it.id,v_amount>=greatest(v_line_paid-v_refunded,0),p_lines,p_stock);
   end if;
   if it.id is not null and it.line_kind::text='special_product' then
    declare o496$r$);
  v_n := (length(v_def) - length(replace(v_def, $a$ perform public.settle_waiting_special_docs_on_refund(i.id,p_lines,p_reason);
$a$, ''))) / length($a$ perform public.settle_waiting_special_docs_on_refund(i.id,p_lines,p_reason);
$a$);
  if v_n <> 1 then raise exception '547: anchor 2 of public.refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $a$ perform public.settle_waiting_special_docs_on_refund(i.id,p_lines,p_reason);
$a$, $r$ -- 547: and a refund that closes the invoice, not while the customer has one.
 if (select v.status from public.invoices v where v.id=i.id) in ('refunded','cancelled') then
   perform public.invoice_special_goods_block(i.id,'refund'); end if;
 perform public.settle_waiting_special_docs_on_refund(i.id,p_lines,p_reason);
$r$);
  v_defs := v_defs || v_def;
  v_def := pg_get_functiondef('public.delete_invoice(uuid,text)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $a$  update public.invoices set deleted_at = now() where id = p_invoice_id;
$a$, ''))) / length($a$  update public.invoices set deleted_at = now() where id = p_invoice_id;
$a$);
  if v_n <> 1 then raise exception '547: anchor 1 of public.delete_invoice(uuid,text) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $a$  update public.invoices set deleted_at = now() where id = p_invoice_id;
$a$, $r$  -- 547 (the Owner, 27 Nov 2026, answer 8): and special, consignment and rental items recorded as
  -- collected or delivered.
  perform public.invoice_special_goods_block(p_invoice_id, 'delete');
  update public.invoices set deleted_at = now() where id = p_invoice_id;
$r$);
  v_defs := v_defs || v_def;
  v_def := pg_get_functiondef('public.fulfil_special_doc(text,uuid,uuid,text)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $a$     where x.id = p_doc_id and i.status in ('unpaid', 'partially_paid');
$a$, ''))) / length($a$     where x.id = p_doc_id and i.status in ('unpaid', 'partially_paid');
$a$);
  if v_n <> 2 then raise exception '547: anchor 1 of public.fulfil_special_doc(text,uuid,uuid,text) found % times, not 2. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $a$     where x.id = p_doc_id and i.status in ('unpaid', 'partially_paid');
$a$, $r$     where x.id = p_doc_id and i.status in ('unpaid', 'partially_paid')
       -- 547 (the Owner, 27 Nov 2026, answer 7): unless the customer has it already.
       and not public.special_doc_collected(p_doc_kind, p_doc_id);
$r$);
  v_defs := v_defs || v_def;
  v_def := pg_get_functiondef('public.release_special_sale_to_supplier(uuid,uuid,text)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $a$   where i.id = v_sale.invoice_id and i.status in ('unpaid', 'partially_paid');
$a$, ''))) / length($a$   where i.id = v_sale.invoice_id and i.status in ('unpaid', 'partially_paid');
$a$);
  if v_n <> 1 then raise exception '547: anchor 1 of public.release_special_sale_to_supplier(uuid,uuid,text) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $a$   where i.id = v_sale.invoice_id and i.status in ('unpaid', 'partially_paid');
$a$, $r$   where i.id = v_sale.invoice_id and i.status in ('unpaid', 'partially_paid')
     -- 547 (the Owner, 27 Nov 2026, answer 7): unless the customer has it already (Delivered).
     and not public.special_doc_collected('special_sale', p_sale_id);
$r$);
  v_defs := v_defs || v_def;
  v_def := pg_get_functiondef('public.return_released_special_stock(uuid,uuid,integer,integer,integer,uuid,text,text)'::regprocedure);
  v_n := (length(v_def) - length(replace(v_def, $a$  if p_why is null or p_why not in ('refunded', 'invoice cancelled', 'line corrected') then  -- 497
$a$, ''))) / length($a$  if p_why is null or p_why not in ('refunded', 'invoice cancelled', 'line corrected') then  -- 497
$a$);
  if v_n <> 1 then raise exception '547: anchor 1 of public.return_released_special_stock(uuid,uuid,integer,integer,integer,uuid,text,text) found % times, not 1. Nothing was changed.', v_n; end if;
  v_def := replace(v_def, $a$  if p_why is null or p_why not in ('refunded', 'invoice cancelled', 'line corrected') then  -- 497
$a$, $r$  if p_why is null or p_why not in ('refunded', 'invoice cancelled', 'line corrected', 'item returned') then  -- 497; 547: Record items returned
$r$);
  v_defs := v_defs || v_def;
  -- 3. Install: the tables, the new functions, the replaced ones, the patched ones.
  execute c_tables;
  execute c_new_0;
  execute c_new_1;
  execute c_new_2;
  execute c_new_3;
  execute c_new_4;
  execute c_rep_0;
  execute c_rep_1;
  execute c_rep_2;
  execute c_rep_3;
  foreach v_def in array v_defs loop execute v_def; end loop;
  -- 4. Grants: the new functions are internal (339): service_role only; the waiting list's marks, signed-in staff (it checks who).
  revoke all on function public.invoice_special_goods_out(uuid) from public, anon, authenticated;
  grant execute on function public.invoice_special_goods_out(uuid) to service_role;
  revoke all on function public.invoice_special_lines(uuid) from public, anon, authenticated;
  grant execute on function public.invoice_special_lines(uuid) to service_role;
  revoke all on function public.special_doc_collected(text,uuid) from public, anon, authenticated;
  grant execute on function public.special_doc_collected(text,uuid) to service_role;
  revoke all on function public.invoice_special_kept_check(uuid) from public, anon, authenticated;
  grant execute on function public.invoice_special_kept_check(uuid) to service_role;
  revoke all on function public.invoice_special_goods_block(uuid,text) from public, anon, authenticated;
  grant execute on function public.invoice_special_goods_block(uuid,text) to service_role;
  revoke all on function public.invoice_special_refund_check(uuid,uuid,boolean,jsonb,jsonb) from public, anon, authenticated;
  grant execute on function public.invoice_special_refund_check(uuid,uuid,boolean,jsonb,jsonb) to service_role;
  revoke all on function public.invoice_special_collect_internal(uuid,uuid,jsonb) from public, anon, authenticated;
  grant execute on function public.invoice_special_collect_internal(uuid,uuid,jsonb) to service_role;
  revoke all on function public.special_waiting_collected(uuid[]) from public, anon;
  grant execute on function public.special_waiting_collected(uuid[]) to authenticated, service_role;
  -- 5. Checks after.
  if c_check_after then
    for k in 1 .. array_length(c_changed, 1) loop
      if md5(pg_get_functiondef(to_regprocedure('public.' || c_changed[k][1]))) <> c_changed[k][3] then
        raise exception '547: public.% is not the tested version after installing', c_changed[k][1]; end if;
    end loop;
    for k in 1 .. array_length(c_new_sigs, 1) loop
      if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sigs[k][1]))) <> c_new_sigs[k][2] then
        raise exception '547: public.% is not the tested version after installing', c_new_sigs[k][1]; end if;
    end loop;
  end if;
  for k in 1 .. array_length(c_new_sigs, 1) loop
    if has_function_privilege('anon', 'public.' || c_new_sigs[k][1], 'execute')
       or (has_function_privilege('authenticated', 'public.' || c_new_sigs[k][1], 'execute')
           and c_new_sigs[k][1] not in ('special_waiting_collected(uuid[])')) then
      raise exception '547: public.% is callable by a login', c_new_sigs[k][1]; end if;
  end loop;
  for k in 1 .. array_length(c_changed, 1) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure('public.' || c_changed[k][1])
                    and p.prosecdef and 'search_path=public, pg_temp' = any (p.proconfig)) then
      raise exception '547: public.% does not search pg_temp last', c_changed[k][1]; end if;
  end loop;
  if has_table_privilege('anon', 'public.invoice_special_handover_lines', 'select')
     or has_table_privilege('authenticated', 'public.invoice_special_handover_lines', 'insert')
     or has_table_privilege('authenticated', 'public.invoice_special_handover_returns', 'truncate') then
    raise exception '547: the new tables give a login more than reading'; end if;
  -- 6. The items released before 547 (the Owner, 27 Nov 2026: "continue"): recorded as already
  --    collected, or delivered when a supplier sent it, so a paid invoice does not ask for them
  --    again. Each one gets its own hand-over header (source 'migration', no person, its reason
  --    the note below, dated when it was released) and one record line. Only on a live invoice
  --    (not deleted; paid, completed FOC, part-paid or unpaid) and its line as it is (the same
  --    special product, still on the invoice). A special sale: completed (released from a
  --    warehouse or a store, or sent by a supplier), not one whose unit a refund has already
  --    settled (special_release_rows: back, damaged or not returned answered; it is with nobody in
  --    the books, and no return could be recorded for it). A rental: active, overdue or returned
  --    (the whole rental). Waiting items stay to collect. No stock, sale or rental changes. A
  --    re-run (or one already recorded) adds nothing: one per item, by its request id.
  declare
    b record; v_h uuid;
    n_sc integer := 0; n_sd integer := 0; n_ra integer := 0; n_rr integer := 0; n_left integer; n_pending integer;
    c_reason constant text := 'Released before 547 (27 Nov 2026): recorded as collected or delivered by the migration, not by staff';
  begin
    for b in
      select 'special_sale'::text as kind, s.id as doc_id, s.invoice_id, it.id as line_id, s.special_product_id, i.store_id,
             'special_product'::text as line_kind,
             case when s.supplier_id is not null then 'delivered' else 'collected' end as how, 1 as qty,
             coalesce(s.fulfilled_at, s.created_at) as at, null::text as rstatus
        from public.special_sales s
        join public.invoices i on i.id = s.invoice_id
        join public.invoice_items it on it.id = s.invoice_item_id and it.invoice_id = i.id
                                    and it.line_kind::text = 'special_product' and it.special_product_id = s.special_product_id
       where s.status = 'completed'
         and i.deleted_at is null and i.status::text in ('paid', 'completed_foc', 'partially_paid', 'unpaid')
         and not exists (select 1 from public.special_release_rows(i.id) rr
                          where rr.movement_id = s.release_movement_id and rr.quantity - rr.resolved_quantity <= 0)
         and not exists (select 1 from public.invoice_special_handover_lines h where h.special_sale_id = s.id)
      union all
      select 'rental', r.id, r.invoice_id, it.id, r.special_product_id, i.store_id, 'rental', 'collected', r.quantity,
             coalesce(r.fulfilled_at, r.activated_at, (r.start_date::timestamp at time zone 'Asia/Singapore'), r.created_at),
             r.status::text
        from public.rentals r
        join public.invoices i on i.id = r.invoice_id
        join public.invoice_items it on it.id = r.invoice_item_id and it.invoice_id = i.id and it.line_kind::text = 'rental'
       where r.status::text in ('active', 'overdue', 'returned')
         and i.deleted_at is null and i.status::text in ('paid', 'completed_foc', 'partially_paid', 'unpaid')
         and not exists (select 1 from public.invoice_special_handover_lines h where h.rental_id = r.id)
      order by 10, 2
    loop
      v_h := null;
      insert into public.invoice_handovers
        (invoice_id, store_id, kind, source, request_id, request_hash, reason, created_by, created_at)
      values (b.invoice_id, b.store_id, 'handover', 'migration', md5('547 backfill ' || b.kind || ' ' || b.doc_id)::uuid,
              md5('547 backfill ' || b.kind || ' ' || b.doc_id), c_reason, null, b.at)
      on conflict (request_id) do nothing
      returning id into v_h;
      continue when v_h is null;
      insert into public.invoice_special_handover_lines
        (handover_id, invoice_id, invoice_item_id, line_kind, special_product_id, how, quantity, special_sale_id, rental_id,
         created_by, created_at)
      values (v_h, b.invoice_id, b.line_id, b.line_kind, b.special_product_id, b.how, b.qty,
              case when b.kind = 'special_sale' then b.doc_id end, case when b.kind = 'rental' then b.doc_id end, null, b.at);
      if b.kind = 'special_sale' and b.how = 'delivered' then n_sd := n_sd + 1;
      elsif b.kind = 'special_sale' then n_sc := n_sc + 1;
      elsif b.rstatus = 'returned' then n_rr := n_rr + 1;
      else n_ra := n_ra + 1; end if;
    end loop;
    -- Every such item now has its record (made now or before).
    select count(*) into n_left from (
      select s.id from public.special_sales s
        join public.invoices i on i.id = s.invoice_id
        join public.invoice_items it on it.id = s.invoice_item_id and it.invoice_id = i.id
                                    and it.line_kind::text = 'special_product' and it.special_product_id = s.special_product_id
       where s.status = 'completed' and i.deleted_at is null and i.status::text in ('paid', 'completed_foc', 'partially_paid', 'unpaid')
         and not exists (select 1 from public.special_release_rows(i.id) rr
                          where rr.movement_id = s.release_movement_id and rr.quantity - rr.resolved_quantity <= 0)
         and not exists (select 1 from public.invoice_special_handover_lines h where h.special_sale_id = s.id)
      union all
      select r.id from public.rentals r
        join public.invoices i on i.id = r.invoice_id
        join public.invoice_items it on it.id = r.invoice_item_id and it.invoice_id = i.id and it.line_kind::text = 'rental'
       where r.status::text in ('active', 'overdue', 'returned')
         and i.deleted_at is null and i.status::text in ('paid', 'completed_foc', 'partially_paid', 'unpaid')
         and not exists (select 1 from public.invoice_special_handover_lines h where h.rental_id = r.id)) x;
    if n_left > 0 then
      raise exception '547: % released item(s) were not recorded as collected or delivered. Nothing was changed.', n_left; end if;
    select count(*) into n_pending from public.special_sales s join public.invoices i on i.id = s.invoice_id
     where s.status = 'pending' and i.deleted_at is null and i.status::text in ('paid', 'completed_foc', 'partially_paid', 'unpaid');
    raise notice '547 backfill: % special sale(s) recorded Collected, % Delivered (supplier), % rental(s) Collected (% out, % returned); % waiting sale(s) left to collect.',
      n_sc, n_sd, n_ra + n_rr, n_ra, n_rr, n_pending;
  end;
  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
