-- 420_stock_adjustments_stock_in_and_products.sql
--
-- WHAT WAS WRONG (the audit of 9 Oct 2026, re-checked on production that day)
--
--   Stock corrections (STOCK-3, STOCK-4)
--   * Approve set the counted total whatever the stock was by then. A sale,
--     a delivery or a transfer between the count and the approval was erased
--     without a trace. (169 approvals so far; none was hit.)
--   * A count that matched the system could be asked for but not approved:
--     the approval tried to write a movement of 0 and failed with a raw
--     check-constraint error. 10 of the 11 rejected requests were these.
--   * A correction could be asked for a deleted or switched-off product, at a
--     closed place, and twice for the same product and place.
--   Saving several lines (STOCK-5)
--   * Stock In and New Adjustment saved line by line. When line 3 failed,
--     lines 1 and 2 were already saved but stayed on the form, so pressing
--     again saved them twice.
--   Deleting (STOCK-7)
--   * Products, stores and warehouses were deleted by a direct update that
--     checked nothing. Three products were deleted while 21 units were still
--     recorded under them, which nobody can now sell, move or count. The
--     product rule even allowed a hard DELETE through the API. There was no
--     Restore.
--   Who may do what (STOCK-12a, STOCK-12b, ADMIN-AUTH-15)
--   * The products rule let an Inventory Manager edit products, but their
--     category and supplier ticks were refused without a word (those rules
--     were Owner or Manager), and the page's save wrote the product and its
--     links in five separate calls, ignoring errors.
--   * Owners, Admins, Managers and Inventory Managers could change stock
--     quantities and movements directly through the API, with no approval
--     and no record of why. The app never does this.
--   * A Manager could put anyone, themselves or an Owner included, on any
--     store, by a direct write to user_store_assignments.
--   * transfer_request_lines had a write rule no client could use (no grant).
--
-- THE RULES (the Owner, 9 Oct 2026)
--
--   Q11  Approving a correction stops with "Stock changed since this count
--        (was X, now Y)" when the stock moved after the count. The Approvals
--        card shows the live number.
--   Q12  The app refuses to delete a product, store or warehouse that still
--        holds stock. The 21 units wait for the owner's shelf check: the
--        repair is scripts/repairs/deleted-products-stock.sql, not this.
--   Q13  An Inventory Manager handles warehouse stock and product details
--        (name, SKU, cost, category, supplier). An Admin looks but does not
--        change products. Managers may put Staff and Inventory Managers on the
--        stores they work at; only an Owner changes a Manager's stores. (Admin
--        is no longer offered for new staff: that is the Users page, B15.)
--   Later answers, the same day:
--   *    Managers see only the stores they work at on Store Stock, like
--        Staff. Owners (and Admins, as today) see every store. The page does
--        this; the server still lets a Manager read every store's stock, as
--        other pages need it (see Rules below).
--   *    A store or warehouse is not switched off (Active unticked) while it
--        still holds stock.
--   *    Rejecting a stock correction needs a reason, kept with the request and
--        shown to the person who asked, like invoice requests.
--   *    The 30 Jul 2026 'Opening stock' of 3 for P00039 was entered twice.
--        The fix is scripts/repairs/p00039-duplicate-opening-stock.sql, run once
--        at deploy with the Owner's go-ahead, not this.
--
-- WHAT THIS DOES
--
--   Replaced (CREATE OR REPLACE, grants kept; each now starts with 406's
--   require_active_staff()):
--   * request_inventory_adjustment(location_type,uuid,uuid,integer,text,text):
--     a counted total of 0 or more, for a live product at an open place the
--     person may count, that differs from the system ("The count matches the
--     system (N), so nothing needs adjusting"); one correction per product
--     and place waits at a time (an advisory lock, then a check).
--   * resolve_inventory_adjustment(uuid,boolean,text): approving locks the
--     stock row and compares it with the count; if it moved, it stops with
--     "Stock changed since this count (was X, now Y). Reject this request and
--     count again." and changes nothing. A product switched off or a place
--     closed since also stops it. A request whose count matched (from before
--     this) is approved with no movement. Rejecting needs a reason ("Give a
--     reason for rejecting this correction..."); it is kept as the request's
--     response_note and rejection_reason, as an invoice request's is, and the
--     Adjustments page shows it to the person who asked.
--   * warehouse_stock_in(uuid,uuid,integer,text,text,text): only a live
--     product goes in, only into an open warehouse.
--   New, for the pages (signed-in staff; each starts with require_active_staff):
--   * warehouse_stock_ins(uuid,jsonb,text,text,text,uuid): a Stock In of
--     several lines in one transaction, every line through warehouse_stock_in.
--     A quantity is a whole number from 1 to 999,999, as on the page ("A
--     quantity can be at most 999,999" above that).
--     A retry with the same request id and the same form adds nothing again
--     and answers with what was added; a changed form under that id is
--     refused. The replay record is the new table below.
--   * request_inventory_adjustments(text,uuid,jsonb,text,text,uuid): the
--     corrections of one count in one go, every line through
--     request_inventory_adjustment. A line whose count matches is left out
--     and named; any other refusal sends nothing. The request id and a hash
--     of the form are kept in each request's payload, for the same replay.
--   * pending_adjustments_live(): for an Owner or Manager, each pending
--     correction's stock now, and whether its product and place are live
--     (at every place, as they approve at every place).
--   * can_edit_products(): Owner, Manager or Inventory Manager (security
--     invoker; the rules below and the functions use it).
--   * save_product(uuid,jsonb,uuid[],uuid[]): Add and Edit on the Products
--     page. The product and its category and supplier links are saved
--     together or not at all, and every refusal is said (a SKU in use, or one
--     of a deleted product; a cost with more than 2 decimals; a brand,
--     category or supplier that no longer exists; a link the product already
--     has stays).
--   * soft_delete_product / restore_product(uuid) (product editors),
--     soft_delete_store / restore_store(uuid) and soft_delete_warehouse /
--     restore_warehouse(uuid) (Owner or Manager): hide and bring back, with an
--     audit row. Restore is never stopped.
--   * assign_user_store(uuid,uuid,boolean): who works at which store, under
--     Q13 and the roles the invitations use (can_assign_role,
--     assignable_store_ids). Nobody changes their own stores; Owners and
--     Admins are not put on one; a closed store takes nobody. Audit row.
--   New, internal (the service role alone, 339):
--   * stock_retire_blockers(text,uuid): what stands in the way of retiring a
--     product, store or warehouse: stock not 0 (named by place), an open
--     transfer, an open loan, a pending correction; for a product also a live
--     promotion and an active special product; for a store a rental released
--     from it and not yet put back; for a warehouse also special stock and a
--     rental of its own not yet put back (rental_put_back_stock returns
--     rentals to these places). A rental counts while it is open, and also
--     when it was cancelled while still with the customer (released or
--     activated, not put back: rental_awaiting_return's test).
--   * trg_stock_place_retire() and the triggers products_retire_check,
--     stores_retire_check and warehouses_retire_check (before update of
--     is_active or deleted_at, when the product, store or warehouse is being
--     deleted or switched off): refuse with "<name> cannot be deleted
--     (switched off) yet. Still open: ...", for example "Store A cannot be
--     switched off yet. Still open: stock of 2 products (5 units).". Every
--     path passes here: the pages, the functions, the API, the SQL editor.
--     Switching a store or warehouse off is checked as deleting it is: stock
--     there, or stock still coming back or waiting there (an open transfer,
--     loan or rental, a correction waiting for approval, special stock).
--   Table: warehouse_stock_in_batches (request_id pk, warehouse_id,
--   requested_by, reason, note, reference, lines, movement_ids, created_at):
--   row level security on, no rule, no client grant, the service role reads.
--   Rules (in (select ...) form; B17's sweep leaves them):
--   * products: "manage products" (FOR ALL) becomes "insert products" and
--     "update products", both can_edit_products(). No DELETE.
--   * stores, warehouses: "manage ..." (FOR ALL) becomes "insert ..." and
--     "update ..." for an Owner or Manager, as before. No DELETE.
--   * product_categories, product_suppliers writes: can_edit_products().
--   * store_inventory: "managers read store inventory" (SELECT,
--     is_manager_or_above()), new; see below.
--   * Dropped: "manage assignments" (user_store_assignments), "write store
--     inventory", "write warehouse inventory", and the dead "write transfer
--     lines".
--   * "write store inventory" (FOR ALL) also let Owners, Admins and Managers
--     read every store's stock. Its read part stays as the new "managers
--     read store inventory" (SELECT, is_manager_or_above()), so who reads
--     store stock does not change: Owners, Admins and Managers every store,
--     everyone else the stores they work at. Every page that reads store
--     stock directly works for a Manager as before (Reports, Transfers and
--     its returns from a store, Invoices, Special, Exchanges, the
--     Dashboard's low-stock alerts and the referral promotion panel's Mark
--     reward given). Only Store Stock and New Adjustment list a Manager's
--     own stores (the Owner's later answer above; a Manager counts only
--     those, as before). Warehouse stock reads are unchanged.
--   Grants: anon and authenticated lose INSERT, UPDATE, DELETE, TRUNCATE on
--   store_inventory, warehouse_inventory, stock_movements and
--   user_store_assignments, DELETE and TRUNCATE on products, stores and
--   warehouses; anon loses its writes on products, stores, warehouses and
--   the two link tables, authenticated TRUNCATE on the link tables. Every
--   SELECT stays.
--
-- NOT CHANGED
--
--   * The brands, categories and suppliers lists stay Owner or Manager.
--   * products_sku_key stays unique over deleted products too: Restore
--     replaces re-creating, and save_product says when a SKU is a deleted
--     product's.
--   * Every function that writes stock already runs as the owner (none is
--     security invoker; production, 9 Oct 2026), so revoking the client
--     grants changes none of them. stock_history_capture_inventory still
--     records every change.
--   * Who reads stores, warehouses, products, warehouse stock and store
--     stock. Managers still read every store's stock on the server ("managers
--     read store inventory" keeps the read part of "write store inventory";
--     the other read rules stay as they are). my_assigned_stores() still
--     lists every open store for an Owner, Admin or Manager (other pages use
--     it, and Managers still run every store on the Stores page); only Store
--     Stock and New Adjustment list, for a Manager, the stores they work at.
--   * user_admin_role, assignable_roles, assignable_store_ids,
--     can_assign_role and trg_guard_profile_privileges (Users & Roles, B15).
--   * edit_transfer_request, cancel_transfer_request and the Transfers page
--     (STOCK-14 items 1 to 3 and 5 are another batch's).
--   * resolve_invoice_action_v2: the Approvals page now asks for a reason to
--     reject an invoice request; the database check is another batch's.
--   * No row. The 21 units under three deleted products wait for the
--     owner's shelf check (the repair script above), and the P00039
--     duplicate has its own script (above).
--
-- SAFETY
--
--   Apart from the lock timeout this is one DO block, so it is atomic. It
--   refuses unless: require_active_staff(text[]) is 406's and write_audit the
--   version read on 9 Oct 2026; the role helpers it calls exist with their
--   result types (other batches may change their bodies, so they are checked
--   by behaviour below); the three replaced functions are the versions read
--   on 9 Oct 2026 or already this migration's, and the new ones are missing
--   or already this migration's, all together; no other function takes one
--   of these names; products, stores and warehouses, the unique keys and the
--   stock_movements quantity check are as read that day, and so are
--   approval_requests' response_note and rejection_reason; the three tables
--   have no trigger but this migration's; the write rules on the nine tables
--   are exactly as read that day or exactly this migration's, and so are
--   the read rules on store_inventory; the new table is missing or exactly
--   this. Every function text has its AFTER md5 before
--   it is installed. Afterwards the md5s, the triggers, the rules, row level
--   security and every grant are checked against what was tested, and,
--   switching role: a signed-in login with no profile is refused by the new
--   functions and cannot call the internal one; then, inside a block that is
--   always undone, a made-up Inventory Manager adds stock in one form twice
--   (added once), counts it, a delivery arrives, a direct write to stock is
--   refused, a made-up Manager's approval stops with "Stock changed since
--   this count (was 5, now 15)", rejecting it with no reason is refused, the
--   warehouse cannot be switched off and the product cannot be deleted while
--   they hold stock, the Manager puts Staff on their store but cannot change
--   their own stores or write an assignment directly, and the Staff read the
--   stock of the store they work at only, while the Manager and an Owner
--   read every store. Nothing is printed and no row remains. A second run
--   changes nothing.
--
-- BEFORE (production, 9 Oct 2026; md5 of pg_get_functiondef, search_path public):
--   replaced
--   request_inventory_adjustment(location_type,uuid,uuid,integer,text,text)  5d561e99d3e0cf2ec71ec07df33a15ea
--   resolve_inventory_adjustment(uuid,boolean,text)                          df89435e34bcf0858ade6f2d91cdbefe
--   warehouse_stock_in(uuid,uuid,integer,text,text,text)                     394999b1b4dc942c8d03735cf367a247
--   relied on, not changed
--   require_active_staff(text[])                                             877b3aa74cea559881979bb161c450e2  (406's)
--   write_audit(text,uuid,text,jsonb,jsonb)                                  19cd6b07bdbb6c73c26fb8aa83d2463e
--   read, not relied on by md5 (checked by name, result and behaviour)
--   can_assign_role(user_role)                                               c7c9b29b1be64baa32aa2005f7d7cb12
--   assignable_store_ids()                                                   d8a2d86b0fd4f9993b5272e7567111d3
--   user_has_store_access(uuid)                                              8c82c6bcb64f496c5a05a2b8dafa95f8
--   can_manage_warehouse_stock()                                             b51c6f1c0e77a277d8757d824cb198dd
--   is_owner_or_manager()                                                    125dec10ce33b84ff5fb40a9bd455235
--   is_manager_or_above()                                                    f12b9ed342070fa4defa30e4da2ba655
--   current_user_role()                                                      519b0a33a3548f970c5d585b6e76a389
--   public function fingerprint                                              675ac22c631079b58f06813d0d463fa3  (1229 functions, after 413)
--     414, 421 and 428 went in later that day: 897ad364eff917861989315bb2fa0e43 (1235 functions),
--     and 415 on 10 Oct 2026: 566e76f702c89c9846968e6fdd89cc45 (1237 functions).
--     They touch none of the objects above; every guard here was re-read on production after them
--     (9 Oct 2026, evening, and 10 Oct 2026, after 415): the md5s above, the nine tables' rules,
--     the read rules on store stock, no trigger, none of the new names.
-- AFTER (for later guards):
--   request_inventory_adjustment(location_type,uuid,uuid,integer,text,text)  f46897361f4d9f80694a8267e44d2cfa
--   resolve_inventory_adjustment(uuid,boolean,text)                          94c01092a241f8c441bfc9c13ca5cc7f
--   warehouse_stock_in(uuid,uuid,integer,text,text,text)                     48514d10c2c6ecabbbf890827e27b770
--   stock_retire_blockers(text,uuid)                                         7c2a2d19f96ddd3a05dd65f72dd15f63
--   trg_stock_place_retire()                                                 341848851fa75b9bd1dd221aed594215
--   can_edit_products()                                                      9d157e1434cb0c22a833303bbbade8bb
--   save_product(uuid,jsonb,uuid[],uuid[])                                   905cdc6ded1a0f3cda513a1884ee238a
--   soft_delete_product(uuid)                                                fbb87549e22a26f0db4a52849b9903a8
--   restore_product(uuid)                                                    ed39a80dabc21a2bfa5116e925e2e141
--   soft_delete_store(uuid)                                                  61020273511f69bac2dd86d530d38d2e
--   restore_store(uuid)                                                      a29cb102c967cc5a2939a1a334e86b07
--   soft_delete_warehouse(uuid)                                              c784eb4c546517953face2380216e2f4
--   restore_warehouse(uuid)                                                  e55ad0e4a8a95c849f46cd8535a6c05a
--   warehouse_stock_ins(uuid,jsonb,text,text,text,uuid)                      4e9ebc1f3971c591a509837b2c734baa
--   request_inventory_adjustments(text,uuid,jsonb,text,text,uuid)            a8b7d46da5b22c24e61d565a41d489e5
--   pending_adjustments_live()                                               9c2ed0a5814bc829a06b56d4648ad3bd
--   assign_user_store(uuid,uuid,boolean)                                     d52aee001ec2343f1fe3699843c3df71
--   public function fingerprint, production as on 10 Oct 2026 (after 415)    5bb4426237ac3ff6c5ef3421cc8c4f00  (1251 functions)
--     (on a copy of production after 428: 15dcd5ca7fecf9c13b09fedf2b607528, 1249 functions;
--     after 413 alone: 33847bb4f777823fa3958c4c20df6b0d, 1243 functions)
--
-- DEPLOY ORDER: this, then the front end straight after (Adjustments,
-- Approvals, Warehouse Stock, Store Stock, Products, Price List, Stores and
-- Warehouses). The pages live now keep adding stock and asking for
-- corrections against this (the one-line functions stay), but between the
-- two: their Delete on Products, Stores and Warehouses is refused while
-- something holds stock and they do not say so; Products' category and
-- supplier ticks save as before for Owners and Managers; and the Stores
-- page's Staff ticks are refused (they wrote the table directly) without a
-- word. The new pages against a database without this fail on every save, so
-- this goes first. Then, after the owner's shelf check, the repair script
-- scripts/repairs/deleted-products-stock.sql once; and, with the Owner's
-- go-ahead, scripts/repairs/p00039-duplicate-opening-stock.sql once (it needs
-- nothing from this migration).
-- Before 431. 431 replaces write_audit (AFTER b194f839993670c5b5dd28e934c2a829);
-- if 431 is in first, 420's write_audit guard refuses ("420: write_audit is
-- not the version read on 9 Oct 2026; re-read and re-test") and nothing is
-- changed.
-- Rentals: a rental cancelled while still with the customer counts as open
-- where it comes back. On 10 Oct 2026 one does: RENT-2026-0002 (cancelled,
-- activated, not put back) at warehouse WH-0906, so WH-0906 cannot be deleted
-- or switched off until B03's repair for that rental runs (WH-0906 holds
-- stock anyway). No cancelled rental released from a store is still out.
--
-- Test: scripts/adjustments/tests/approve-live.sql (corrections, approval
-- against the live stock, several lines, direct writes refused),
-- scripts/stock-in/tests/batch.sql (Stock In of several lines, replay),
-- scripts/products/tests/delete-restore.sql (product editing, delete and
-- restore of products, stores and warehouses on every path, store
-- assignments), scripts/repairs/tests/deleted-products-stock.sql,
-- scripts/repairs/tests/p00039-duplicate-opening-stock.sql,
-- scripts/adjustments/tests/stock-pages.test.mjs (the pages, in jsdom),
-- scripts/permissions/tests/function-grants.sql and
-- scripts/permissions/tests/staff-only-functions.sql.

set lock_timeout = '5s';

do $mig$
declare
  -- ── Replaced whole (grants kept) ─────────────────────────────────────────
  c_request_def constant text := $def$CREATE OR REPLACE FUNCTION public.request_inventory_adjustment(p_location_type location_type, p_location_id uuid, p_product_id uuid, p_new_qty integer, p_reason text, p_reference text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_current integer; v_req_id uuid; v_product text; v_place text;
begin
  perform public.require_active_staff();  -- 420: active staff only (406)
  -- 420: a correction is a counted total of 0 or more, for a live product at
  -- an open place, that differs from the system (STOCK-4). One correction per
  -- product and place waits for approval at a time.
  if p_new_qty is null then raise exception 'Enter the counted total'; end if;
  if p_new_qty < 0 then raise exception 'Adjusted quantity cannot be negative'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason is required'; end if;
  if p_location_type is null or p_location_id is null or p_product_id is null then
    raise exception 'Choose a place and a product'; end if;

  if p_location_type = 'store' then
    if not public.user_has_store_access(p_location_id) then raise exception 'You can only adjust your assigned store'; end if;
    select s.name into v_place from public.stores s
     where s.id = p_location_id and s.deleted_at is null and s.is_active for share;
    if not found then raise exception 'This store is closed or deleted, so its stock cannot be corrected'; end if;
  else
    if not public.can_manage_warehouse_stock() then raise exception 'Not authorized to adjust warehouse stock'; end if;
    select w.name into v_place from public.warehouses w
     where w.id = p_location_id and w.deleted_at is null and w.is_active for share;
    if not found then raise exception 'This warehouse is closed or deleted, so its stock cannot be corrected'; end if;
  end if;
  select p.name into v_product from public.products p
   where p.id = p_product_id and p.deleted_at is null and p.is_active for share;
  if not found then
    raise exception 'This product is switched off or deleted. Restore it on the Products page first.'; end if;

  -- Two requests for one product and place at once: the second waits here.
  perform pg_advisory_xact_lock(hashtextextended('inventory_adjustment:' || p_location_type::text || ':'
    || p_location_id::text || ':' || p_product_id::text, 0));
  if exists (select 1 from public.approval_requests a
              where a.request_type = 'adjustment' and a.status = 'pending'
                and a.payload ->> 'location_type' = p_location_type::text
                and a.payload ->> 'location_id' = p_location_id::text
                and a.payload ->> 'product_id' = p_product_id::text) then
    raise exception '% at % already has a correction waiting for approval. Approve or reject that one first.', v_product, v_place;
  end if;

  if p_location_type = 'store' then
    select current_qty into v_current from public.store_inventory where store_id = p_location_id and product_id = p_product_id;
  else
    select current_qty into v_current from public.warehouse_inventory where warehouse_id = p_location_id and product_id = p_product_id;
  end if;
  v_current := coalesce(v_current, 0);
  if p_new_qty = v_current then
    raise exception 'The count matches the system (%), so nothing needs adjusting', v_current; end if;

  insert into public.approval_requests (request_type, status, requested_by, related_record_id, reason, payload)
  values ('adjustment', 'pending', auth.uid(), p_product_id, p_reason,
    jsonb_build_object('location_type', p_location_type, 'location_id', p_location_id,
      'product_id', p_product_id, 'current_qty', v_current, 'new_qty', p_new_qty,
      'difference', p_new_qty - v_current, 'reference', p_reference))
  returning id into v_req_id;

  perform public.write_audit('inventory_adjustment', p_product_id, 'adjustment_requested', null,
    jsonb_build_object('from', v_current, 'to', p_new_qty));
  return v_req_id;
end; $function$
$def$;
  c_resolve_def constant text := $def$CREATE OR REPLACE FUNCTION public.resolve_inventory_adjustment(p_request_id uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_req public.approval_requests%rowtype; v_loc_type location_type; v_loc_id uuid;
  v_product_id uuid; v_new_qty integer; v_counted integer; v_current integer; v_diff integer; n integer;
  v_movement_type stock_movement_type := 'inventory_adjustment';
begin
  perform public.require_active_staff();  -- 420: active staff only (406)
  if not public.is_owner_or_manager() then raise exception 'Only Owner or Manager can approve adjustments'; end if;
  if p_approve is null then raise exception 'Approve or reject the request'; end if;
  select * into v_req from public.approval_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request is not pending'; end if;
  if v_req.request_type <> 'adjustment' then raise exception 'Not an adjustment request'; end if;

  if not p_approve then
    -- 420 (the Owner, 9 Oct 2026): a rejection says why, as an invoice
    -- request's does. The person who asked sees it on the Adjustments page.
    -- A reason of only spaces, tabs or new lines is no reason.
    if p_note is null or p_note !~ '\S' then
      raise exception 'Give a reason for rejecting this correction. The person who asked will see it.'; end if;
    update public.approval_requests set status = 'rejected', approved_by = auth.uid(), approved_at = now(),
      response_note = btrim(p_note, E' \t\r\n'), rejection_reason = btrim(p_note, E' \t\r\n') where id = p_request_id;
    return jsonb_build_object('success', true, 'status', 'rejected');
  end if;

  v_loc_type := (v_req.payload->>'location_type')::location_type;
  v_loc_id := (v_req.payload->>'location_id')::uuid;
  v_product_id := (v_req.payload->>'product_id')::uuid;
  v_new_qty := (v_req.payload->>'new_qty')::integer;
  v_counted := (v_req.payload->>'current_qty')::integer;
  if v_loc_type is null or v_loc_id is null or v_product_id is null or v_new_qty is null or v_new_qty < 0
     or v_counted is null then
    raise exception 'This request is incomplete. Reject it and count again.'; end if;

  -- 420: only a live product at an open place is corrected. The share locks
  -- keep either from being deleted meanwhile.
  perform 1 from public.products p where p.id = v_product_id and p.deleted_at is null and p.is_active for share;
  if not found then
    raise exception 'This product was switched off or deleted after the count. Reject this request.'; end if;
  if v_loc_type = 'store' then
    perform 1 from public.stores s where s.id = v_loc_id and s.deleted_at is null and s.is_active for share;
  else
    perform 1 from public.warehouses w where w.id = v_loc_id and w.deleted_at is null and w.is_active for share;
  end if;
  if not found then
    raise exception 'This % was closed or deleted after the count. Reject this request.', v_loc_type; end if;

  -- 420 (the Owner, 9 Oct 2026): a count is applied only to the stock it
  -- counted. If a sale, a delivery or a transfer moved that stock since, stop.
  if v_loc_type = 'store' then
    select current_qty into v_current from public.store_inventory
      where store_id = v_loc_id and product_id = v_product_id for update;
  else
    select current_qty into v_current from public.warehouse_inventory
      where warehouse_id = v_loc_id and product_id = v_product_id for update;
  end if;
  v_current := coalesce(v_current, 0);
  if v_current <> v_counted then
    raise exception 'Stock changed since this count (was %, now %). Reject this request and count again.', v_counted, v_current;
  end if;

  -- A count that matched the system (a request from before 420) is approved
  -- with no movement: a movement of 0 is not allowed (STOCK-4).
  v_diff := v_new_qty - v_current;
  if v_diff <> 0 then
    if v_loc_type = 'store' then
      insert into public.store_inventory (store_id, product_id, current_qty)
      values (v_loc_id, v_product_id, v_new_qty)
      on conflict (store_id, product_id) do update set current_qty = excluded.current_qty, updated_at = now()
        where store_inventory.current_qty = v_current;
      get diagnostics n = row_count;
      if n = 0 then
        select current_qty into v_current from public.store_inventory where store_id = v_loc_id and product_id = v_product_id;
        raise exception 'Stock changed since this count (was %, now %). Reject this request and count again.', v_counted, coalesce(v_current, 0);
      end if;
      insert into public.stock_movements (product_id, movement_type, to_store_id, from_store_id, quantity, notes, created_by)
      values (v_product_id, v_movement_type,
        case when v_diff > 0 then v_loc_id end,
        case when v_diff < 0 then v_loc_id end,
        abs(v_diff), 'Adjustment: '||coalesce(v_req.reason,''), auth.uid());
    else
      insert into public.warehouse_inventory (warehouse_id, product_id, current_qty)
      values (v_loc_id, v_product_id, v_new_qty)
      on conflict (warehouse_id, product_id) do update set current_qty = excluded.current_qty, updated_at = now()
        where warehouse_inventory.current_qty = v_current;
      get diagnostics n = row_count;
      if n = 0 then
        select current_qty into v_current from public.warehouse_inventory where warehouse_id = v_loc_id and product_id = v_product_id;
        raise exception 'Stock changed since this count (was %, now %). Reject this request and count again.', v_counted, coalesce(v_current, 0);
      end if;
      insert into public.stock_movements (product_id, movement_type, to_warehouse_id, from_warehouse_id, quantity, notes, created_by)
      values (v_product_id, v_movement_type,
        case when v_diff > 0 then v_loc_id end,
        case when v_diff < 0 then v_loc_id end,
        abs(v_diff), 'Adjustment: '||coalesce(v_req.reason,''), auth.uid());
    end if;
  end if;

  update public.approval_requests set status = 'approved', approved_by = auth.uid(),
    approved_at = now(), response_note = p_note where id = p_request_id;
  perform public.write_audit('inventory_adjustment', v_product_id, 'adjustment_approved', null,
    jsonb_build_object('from', v_current, 'to', v_new_qty));
  return jsonb_build_object('success', true, 'status', 'approved', 'new_qty', v_new_qty, 'moved', abs(v_diff));
end; $function$
$def$;
  c_stock_in_def constant text := $def$CREATE OR REPLACE FUNCTION public.warehouse_stock_in(p_warehouse_id uuid, p_product_id uuid, p_quantity integer, p_reason text, p_note text DEFAULT NULL::text, p_reference text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_new_qty integer; v_movement_id uuid;
begin
  perform public.require_active_staff();  -- 420: active staff only (406)
  if not public.can_manage_warehouse_stock() then raise exception 'Not authorized to add warehouse stock'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be greater than zero'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason for stock-in is required'; end if;
  -- 420: stock goes only into an open warehouse, for a live product. The share
  -- locks keep either from being deleted while this adds to it.
  perform 1 from public.warehouses w where w.id = p_warehouse_id and w.deleted_at is null and w.is_active for share;
  if not found then raise exception 'This warehouse is closed or deleted, so it cannot take stock'; end if;
  perform 1 from public.products p where p.id = p_product_id and p.deleted_at is null and p.is_active for share;
  if not found then
    raise exception 'This product is switched off or deleted, so no stock can be added to it. Restore it on the Products page first.'; end if;

  insert into public.warehouse_inventory (warehouse_id, product_id, current_qty)
  values (p_warehouse_id, p_product_id, p_quantity)
  on conflict (warehouse_id, product_id)
  do update set current_qty = public.warehouse_inventory.current_qty + excluded.current_qty, updated_at = now()
  returning current_qty into v_new_qty;

  insert into public.stock_movements (product_id, movement_type, to_warehouse_id, quantity, notes, created_by)
  values (p_product_id, 'warehouse_stock_in', p_warehouse_id, p_quantity,
    trim(coalesce(p_reason,'') || case when p_note is not null then ' — ' || p_note else '' end
      || case when p_reference is not null then ' (ref: ' || p_reference || ')' else '' end), auth.uid())
  returning id into v_movement_id;

  perform public.write_audit('warehouse_inventory', p_product_id, 'stock_in', null,
    jsonb_build_object('warehouse_id', p_warehouse_id, 'quantity', p_quantity, 'new_qty', v_new_qty, 'reason', p_reason));
  return v_movement_id;
end; $function$
$def$;

  -- ── New: what stops a product, store or warehouse being retired ─────────
  c_blockers_def constant text := $def$CREATE OR REPLACE FUNCTION public.stock_retire_blockers(p_kind text, p_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 420 (the Owner, 9 Oct 2026): a product, a store or a warehouse is not
-- deleted or switched off while it still holds stock or has stock on the way.
-- Lists what stands in the way, in short plain phrases joined by '; ', or
-- returns null when nothing does. Internal: the retire trigger calls it.
declare v_out text[] := '{}'; v text; n integer; m bigint;
begin
  if p_kind = 'product' then
    select string_agg(x.qty || ' at ' || x.place, ', ' order by x.place) into v from (
      select si.current_qty as qty, s.name as place
        from public.store_inventory si join public.stores s on s.id = si.store_id
       where si.product_id = p_id and si.current_qty <> 0
      union all
      select wi.current_qty, w.name
        from public.warehouse_inventory wi join public.warehouses w on w.id = wi.warehouse_id
       where wi.product_id = p_id and wi.current_qty <> 0) x;
    if v is not null then v_out := v_out || ('stock (' || v || ')'); end if;
    select count(distinct r.id) into n
      from public.transfer_request_lines l join public.transfer_requests r on r.id = l.transfer_request_id
     where l.product_id = p_id
       and r.status in ('pending', 'approved', 'partially_approved', 'in_transit', 'received_with_discrepancy');
    if n > 0 then v_out := v_out || (n || ' open transfer' || case when n = 1 then '' else 's' end); end if;
    select string_agg(distinct s.loan_no, ', ') into v
      from public.stock_loan_lines ll join public.stock_loans s on s.id = ll.loan_id
     where ll.product_id = p_id and s.status = 'open'
       and ll.qty_out - ll.qty_returned - ll.qty_used - ll.qty_lost > 0;
    if v is not null then v_out := v_out || ('stock out on loan (' || v || ')'); end if;
    select string_agg(distinct pr.name, ', ') into v from public.promotions pr
     where pr.is_active and pr.deleted_at is null
       and (pr.end_date is null or pr.end_date >= public.sg_today())
       and (exists (select 1 from public.promotion_items i where i.promotion_id = pr.id and i.product_id = p_id)
            or exists (select 1 from public.promotion_choice_groups g
                         join public.promotion_choice_options o on o.group_id = g.id
                        where g.promotion_id = pr.id and o.product_id = p_id));
    if v is not null then v_out := v_out || ('a live promotion (' || v || ')'); end if;
    select string_agg(sp.name, ', ') into v from public.special_products sp
     where sp.product_id = p_id and sp.is_active and sp.deleted_at is null;
    if v is not null then v_out := v_out || ('a special product (' || v || ')'); end if;
    select count(*) into n from public.approval_requests a
     where a.request_type = 'adjustment' and a.status = 'pending' and a.payload ->> 'product_id' = p_id::text;
    if n > 0 then v_out := v_out || 'a stock correction waiting for approval'::text; end if;
  elsif p_kind in ('store', 'warehouse') then
    if p_kind = 'store' then
      select count(*), sum(si.current_qty) into n, m from public.store_inventory si
       where si.store_id = p_id and si.current_qty <> 0;
    else
      select count(*), sum(wi.current_qty) into n, m from public.warehouse_inventory wi
       where wi.warehouse_id = p_id and wi.current_qty <> 0;
    end if;
    if n > 0 then
      v_out := v_out || ('stock of ' || n || ' product' || case when n = 1 then '' else 's' end || ' (' || m || ' units)'); end if;
    select count(*) into n from public.transfer_requests r
     where r.status in ('pending', 'approved', 'partially_approved', 'in_transit', 'received_with_discrepancy')
       and ((r.source_type::text = p_kind and r.source_id = p_id)
            or (r.dest_type::text = p_kind and r.dest_id = p_id)
            or exists (select 1 from public.transfer_request_lines l
                         join public.transfer_line_sources ls on ls.line_id = l.id
                        where l.transfer_request_id = r.id and ls.source_type::text = p_kind and ls.source_id = p_id));
    if n > 0 then v_out := v_out || (n || ' open transfer' || case when n = 1 then '' else 's' end); end if;
    select count(*) into n from public.stock_loans s
     where s.status = 'open' and s.location_type = p_kind and coalesce(s.store_id, s.warehouse_id) = p_id;
    if n > 0 then v_out := v_out || (n || ' open loan' || case when n = 1 then '' else 's' end); end if;
    select count(*) into n from public.approval_requests a
     where a.request_type = 'adjustment' and a.status = 'pending'
       and a.payload ->> 'location_type' = p_kind and a.payload ->> 'location_id' = p_id::text;
    if n > 0 then
      v_out := v_out || (n || ' stock correction' || case when n = 1 then '' else 's' end || ' waiting for approval'); end if;
    if p_kind = 'warehouse' then
      select coalesce(sum(ss.current_qty), 0) into m from public.special_product_stock ss
       where ss.warehouse_id = p_id and ss.current_qty <> 0;
      if m <> 0 then v_out := v_out || ('special stock (' || m || ' units)'); end if;
    end if;
    -- A rental not yet put back comes back here: to the store it was released
    -- from (source_store_id), or to its warehouse (rental_put_back_stock).
    -- A rental cancelled while still with the customer comes back too (the
    -- same test as rental_awaiting_return).
    select count(*) into n from public.rentals rt
     where case when p_kind = 'store' then rt.source_store_id else rt.warehouse_id end = p_id
       and (rt.status in ('awaiting_fulfilment', 'draft', 'paid', 'active', 'overdue')
            or (rt.status = 'cancelled' and (rt.fulfilled_at is not null or rt.activated_at is not null)))
       and not coalesce(rt.stock_returned, false);
    if n > 0 then v_out := v_out || (n || ' open rental' || case when n = 1 then '' else 's' end); end if;
  else
    raise exception 'stock_retire_blockers: unknown kind %', p_kind;
  end if;
  return case when cardinality(v_out) = 0 then null else array_to_string(v_out, '; ') end;
end $function$
$def$;
  c_trg_def constant text := $def$CREATE OR REPLACE FUNCTION public.trg_stock_place_retire()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v text;
begin
  -- 420: a product, store or warehouse being deleted or switched off (the
  -- triggers' conditions say which) must hold no stock and have nothing on
  -- the way (stock_retire_blockers). Every path passes here: the pages, the
  -- delete functions, the API and the SQL editor. Bringing one back is never
  -- stopped.
  v := public.stock_retire_blockers(
         case tg_table_name when 'products' then 'product' when 'stores' then 'store' else 'warehouse' end, new.id);
  if v is not null then
    raise exception '% cannot be % yet. Still open: %.', new.name,
      case when new.deleted_at is not null and old.deleted_at is null then 'deleted' else 'switched off' end, v;
  end if;
  return new;
end $function$
$def$;

  -- ── New: who edits products, and the Products page's save ───────────────
  c_can_edit_def constant text := $def$CREATE OR REPLACE FUNCTION public.can_edit_products()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- 420 (the Owner, 9 Oct 2026): who adds products and changes their details
  -- (name, SKU, cost, category, supplier): an active Owner, Manager or
  -- Inventory Manager. An Admin looks but does not change. The product rules,
  -- the product link rules, save_product and the delete functions use it. It
  -- runs as the caller and reads only current_user_role().
  select coalesce(public.current_user_role() in ('owner', 'manager', 'inventory_manager'), false)
$function$
$def$;
  c_save_def constant text := $def$CREATE OR REPLACE FUNCTION public.save_product(p_id uuid, p_fields jsonb, p_category_ids uuid[] DEFAULT NULL::uuid[], p_supplier_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 420: the Products page's Add and Edit (STOCK-12a). The product and its
-- category and supplier links are saved together or not at all, and every
-- refusal is said. Who: can_edit_products(). p_id null adds a product.
-- p_fields: name, sku, product_type, category, brand, brand_id, uom, barcode,
-- description, supplier_name, default_cost_price, is_active; a key left out
-- keeps what is saved (on Add, the column's default). p_category_ids and
-- p_supplier_ids replace the links; null leaves them as they are. Switching a
-- product off is checked by the retire trigger.
declare
  c_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  v_role public.user_role; v_old public.products%rowtype; v_new public.products%rowtype;
  v_dup public.products%rowtype; v_id uuid; v text;
begin
  v_role := public.require_active_staff();  -- 420: active staff only (406)
  if v_role is not null and not public.can_edit_products() then
    raise exception 'Only an Owner, Manager or Inventory Manager can add or change products.' using errcode = '42501'; end if;
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' then raise exception 'Nothing to save'; end if;
  if p_id is not null then
    select * into v_old from public.products where id = p_id for update;
    if not found then raise exception 'Product not found'; end if;
    if v_old.deleted_at is not null then raise exception 'This product is deleted. Restore it first.'; end if;
    v_new := v_old;
  else
    v_new.product_type := 'own'; v_new.uom := 'pcs'; v_new.default_cost_price := 0; v_new.is_active := true;
  end if;

  if p_fields ? 'name' then v_new.name := nullif(btrim(coalesce(p_fields->>'name', '')), ''); end if;
  if p_fields ? 'sku' then v_new.sku := nullif(btrim(coalesce(p_fields->>'sku', '')), ''); end if;
  if v_new.name is null then raise exception 'Product name is required.'; end if;
  if v_new.sku is null then raise exception 'SKU / product code is required.'; end if;
  if p_fields ? 'product_type' then
    if coalesce(p_fields->>'product_type', '') not in ('own', 'third_party', 'no_commission') then
      raise exception 'Choose the product type.'; end if;
    v_new.product_type := (p_fields->>'product_type')::public.product_type;
  end if;
  if p_fields ? 'uom' then v_new.uom := coalesce(nullif(btrim(coalesce(p_fields->>'uom', '')), ''), 'pcs'); end if;
  if p_fields ? 'default_cost_price' then
    v := btrim(coalesce(p_fields->>'default_cost_price', '0'));
    if v !~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' then
      raise exception 'Cost price must be 0 or more, with at most 2 decimal places.'; end if;
    v_new.default_cost_price := v::numeric;
  end if;
  if p_fields ? 'is_active' then
    if jsonb_typeof(p_fields->'is_active') <> 'boolean' then raise exception 'Active must be ticked or not.'; end if;
    v_new.is_active := (p_fields->>'is_active')::boolean;
  end if;
  if p_fields ? 'brand_id' then
    v := nullif(btrim(coalesce(p_fields->>'brand_id', '')), '');
    -- A deleted brand the product already has may stay; a new one may not.
    if v is not null and (v !~* c_uuid or not exists (select 1 from public.brands b where b.id = v::uuid
                                                       and (b.deleted_at is null or b.id = v_old.brand_id))) then
      raise exception 'Choose a brand from the list.'; end if;
    v_new.brand_id := v::uuid;
  end if;
  if p_fields ? 'category' then v_new.category := nullif(btrim(coalesce(p_fields->>'category', '')), ''); end if;
  if p_fields ? 'brand' then v_new.brand := nullif(btrim(coalesce(p_fields->>'brand', '')), ''); end if;
  if p_fields ? 'barcode' then v_new.barcode := nullif(btrim(coalesce(p_fields->>'barcode', '')), ''); end if;
  if p_fields ? 'description' then v_new.description := nullif(btrim(coalesce(p_fields->>'description', '')), ''); end if;
  if p_fields ? 'supplier_name' then v_new.supplier_name := nullif(btrim(coalesce(p_fields->>'supplier_name', '')), ''); end if;

  -- A SKU is unique over every product, deleted ones included.
  select * into v_dup from public.products p where p.sku = v_new.sku and p.id is distinct from p_id limit 1;
  if found then
    if v_dup.deleted_at is not null then
      raise exception 'That SKU belongs to a deleted product (%). Tick "Show deleted" and restore it instead.', v_dup.name; end if;
    raise exception 'That SKU already exists (%). Use a unique product code.', v_dup.name;
  end if;
  -- A link the product already has stays even when its category or supplier
  -- was deleted since (the page keeps it); a new link must be to a live one.
  if exists (select 1 from unnest(coalesce(p_category_ids, '{}'::uuid[])) x
              where x is null or not exists (select 1 from public.categories c where c.id = x
                and (c.deleted_at is null or exists (select 1 from public.product_categories pc
                                                      where pc.product_id = p_id and pc.category_id = x)))) then
    raise exception 'A chosen category no longer exists. Refresh the page and try again.'; end if;
  if exists (select 1 from unnest(coalesce(p_supplier_ids, '{}'::uuid[])) x
              where x is null or not exists (select 1 from public.suppliers s where s.id = x
                and (s.deleted_at is null or exists (select 1 from public.product_suppliers ps
                                                      where ps.product_id = p_id and ps.supplier_id = x)))) then
    raise exception 'A chosen supplier no longer exists. Refresh the page and try again.'; end if;

  begin
    if p_id is null then
      insert into public.products (name, sku, product_type, category, brand, brand_id, uom, barcode, description,
                                   supplier_name, default_cost_price, is_active)
      values (v_new.name, v_new.sku, v_new.product_type, v_new.category, v_new.brand, v_new.brand_id, v_new.uom,
              v_new.barcode, v_new.description, v_new.supplier_name, v_new.default_cost_price, v_new.is_active)
      returning id into v_id;
    else
      update public.products
         set name = v_new.name, sku = v_new.sku, product_type = v_new.product_type, category = v_new.category,
             brand = v_new.brand, brand_id = v_new.brand_id, uom = v_new.uom, barcode = v_new.barcode,
             description = v_new.description, supplier_name = v_new.supplier_name,
             default_cost_price = v_new.default_cost_price, is_active = v_new.is_active, updated_at = now()
       where id = p_id;
      v_id := p_id;
    end if;
  exception when unique_violation then
    raise exception 'That SKU already exists. Use a unique product code.';
  end;

  if p_category_ids is not null then
    delete from public.product_categories pc where pc.product_id = v_id and not (pc.category_id = any (p_category_ids));
    insert into public.product_categories (product_id, category_id)
    select distinct v_id, x from unnest(p_category_ids) x on conflict do nothing;
  end if;
  if p_supplier_ids is not null then
    delete from public.product_suppliers ps where ps.product_id = v_id and not (ps.supplier_id = any (p_supplier_ids));
    insert into public.product_suppliers (product_id, supplier_id)
    select distinct v_id, x from unnest(p_supplier_ids) x on conflict do nothing;
  end if;

  perform public.write_audit('products', v_id, case when p_id is null then 'product_created' else 'product_updated' end,
    case when p_id is null then null else to_jsonb(v_old) end,
    (select to_jsonb(p) from public.products p where p.id = v_id)
      || jsonb_build_object('category_ids', p_category_ids, 'supplier_ids', p_supplier_ids));
  return jsonb_build_object('success', true, 'product_id', v_id, 'created', p_id is null);
end $function$
$def$;

  -- ── New: delete and restore (soft) ──────────────────────────────────────
  c_del_product_def constant text := $def$CREATE OR REPLACE FUNCTION public.soft_delete_product(p_product_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 420 (the Owner, 9 Oct 2026): Delete on the Products page. Refused, saying
-- why, while the product holds stock or has stock on the way (the retire
-- trigger). The product is hidden, not removed: restore_product brings it back.
declare v_role public.user_role; v_p public.products%rowtype;
begin
  v_role := public.require_active_staff();  -- 420: active staff only (406)
  if v_role is not null and not public.can_edit_products() then
    raise exception 'Only an Owner, Manager or Inventory Manager can delete products.' using errcode = '42501'; end if;
  select * into v_p from public.products where id = p_product_id for update;
  if not found then raise exception 'Product not found'; end if;
  if v_p.deleted_at is not null then return jsonb_build_object('success', true, 'already', true); end if;
  update public.products set deleted_at = now(), is_active = false, updated_at = now() where id = p_product_id;
  perform public.write_audit('products', p_product_id, 'product_deleted',
    jsonb_build_object('name', v_p.name, 'sku', v_p.sku, 'is_active', v_p.is_active), null);
  return jsonb_build_object('success', true, 'already', false);
end $function$
$def$;
  c_res_product_def constant text := $def$CREATE OR REPLACE FUNCTION public.restore_product(p_product_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 420: Restore on the Products page ("Show deleted"). The product comes back
-- active, with its SKU, links and prices as they were.
declare v_role public.user_role; v_p public.products%rowtype;
begin
  v_role := public.require_active_staff();  -- 420: active staff only (406)
  if v_role is not null and not public.can_edit_products() then
    raise exception 'Only an Owner, Manager or Inventory Manager can restore products.' using errcode = '42501'; end if;
  select * into v_p from public.products where id = p_product_id for update;
  if not found then raise exception 'Product not found'; end if;
  if v_p.deleted_at is null then return jsonb_build_object('success', true, 'already', true); end if;
  update public.products set deleted_at = null, is_active = true, updated_at = now() where id = p_product_id;
  perform public.write_audit('products', p_product_id, 'product_restored', null,
    jsonb_build_object('name', v_p.name, 'sku', v_p.sku, 'deleted_at', v_p.deleted_at));
  return jsonb_build_object('success', true, 'already', false);
end $function$
$def$;
  c_del_store_def constant text := $def$CREATE OR REPLACE FUNCTION public.soft_delete_store(p_store_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 420 (the Owner, 9 Oct 2026): Delete on the Stores page, for an Owner or a
-- Manager. Refused, saying why, while the store holds stock or has stock on
-- the way (the retire trigger). Hidden, not removed: restore_store.
declare v_role public.user_role; v_s public.stores%rowtype;
begin
  v_role := public.require_active_staff();  -- 420: active staff only (406)
  if v_role is not null and v_role not in ('owner', 'manager') then
    raise exception 'Only an Owner or Manager can delete stores.' using errcode = '42501'; end if;
  select * into v_s from public.stores where id = p_store_id for update;
  if not found then raise exception 'Store not found'; end if;
  if v_s.deleted_at is not null then return jsonb_build_object('success', true, 'already', true); end if;
  update public.stores set deleted_at = now(), is_active = false where id = p_store_id;
  perform public.write_audit('stores', p_store_id, 'store_deleted',
    jsonb_build_object('name', v_s.name, 'code', v_s.code, 'is_active', v_s.is_active), null);
  return jsonb_build_object('success', true, 'already', false);
end $function$
$def$;
  c_res_store_def constant text := $def$CREATE OR REPLACE FUNCTION public.restore_store(p_store_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 420: Restore on the Stores page ("Show deleted"), for an Owner or a Manager.
declare v_role public.user_role; v_s public.stores%rowtype;
begin
  v_role := public.require_active_staff();  -- 420: active staff only (406)
  if v_role is not null and v_role not in ('owner', 'manager') then
    raise exception 'Only an Owner or Manager can restore stores.' using errcode = '42501'; end if;
  select * into v_s from public.stores where id = p_store_id for update;
  if not found then raise exception 'Store not found'; end if;
  if v_s.deleted_at is null then return jsonb_build_object('success', true, 'already', true); end if;
  update public.stores set deleted_at = null, is_active = true where id = p_store_id;
  perform public.write_audit('stores', p_store_id, 'store_restored', null,
    jsonb_build_object('name', v_s.name, 'code', v_s.code, 'deleted_at', v_s.deleted_at));
  return jsonb_build_object('success', true, 'already', false);
end $function$
$def$;
  c_del_wh_def constant text := $def$CREATE OR REPLACE FUNCTION public.soft_delete_warehouse(p_warehouse_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 420 (the Owner, 9 Oct 2026): Delete on the Warehouses page, for an Owner or
-- a Manager. Refused, saying why, while the warehouse holds stock or has stock
-- on the way (the retire trigger). Hidden, not removed: restore_warehouse.
declare v_role public.user_role; v_w public.warehouses%rowtype;
begin
  v_role := public.require_active_staff();  -- 420: active staff only (406)
  if v_role is not null and v_role not in ('owner', 'manager') then
    raise exception 'Only an Owner or Manager can delete warehouses.' using errcode = '42501'; end if;
  select * into v_w from public.warehouses where id = p_warehouse_id for update;
  if not found then raise exception 'Warehouse not found'; end if;
  if v_w.deleted_at is not null then return jsonb_build_object('success', true, 'already', true); end if;
  update public.warehouses set deleted_at = now(), is_active = false where id = p_warehouse_id;
  perform public.write_audit('warehouses', p_warehouse_id, 'warehouse_deleted',
    jsonb_build_object('name', v_w.name, 'code', v_w.code, 'is_active', v_w.is_active), null);
  return jsonb_build_object('success', true, 'already', false);
end $function$
$def$;
  c_res_wh_def constant text := $def$CREATE OR REPLACE FUNCTION public.restore_warehouse(p_warehouse_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 420: Restore on the Warehouses page ("Show deleted"), for an Owner or a Manager.
declare v_role public.user_role; v_w public.warehouses%rowtype;
begin
  v_role := public.require_active_staff();  -- 420: active staff only (406)
  if v_role is not null and v_role not in ('owner', 'manager') then
    raise exception 'Only an Owner or Manager can restore warehouses.' using errcode = '42501'; end if;
  select * into v_w from public.warehouses where id = p_warehouse_id for update;
  if not found then raise exception 'Warehouse not found'; end if;
  if v_w.deleted_at is null then return jsonb_build_object('success', true, 'already', true); end if;
  update public.warehouses set deleted_at = null, is_active = true where id = p_warehouse_id;
  perform public.write_audit('warehouses', p_warehouse_id, 'warehouse_restored', null,
    jsonb_build_object('name', v_w.name, 'code', v_w.code, 'deleted_at', v_w.deleted_at));
  return jsonb_build_object('success', true, 'already', false);
end $function$
$def$;

  -- ── New: several lines in one go, replayable ────────────────────────────
  c_stock_ins_def constant text := $def$CREATE OR REPLACE FUNCTION public.warehouse_stock_ins(p_warehouse_id uuid, p_lines jsonb, p_reason text, p_note text DEFAULT NULL::text, p_reference text DEFAULT NULL::text, p_request_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 420: a Stock In of several products, in one transaction (STOCK-5): every
-- line is added or none is. Each line goes through warehouse_stock_in,
-- unchanged, so a line here is exactly a single stock-in: its checks, its
-- movement and its audit row. p_lines is [{"product_id": "<uuid>",
-- "quantity": n}], each product once, n a whole number from 1 to 999,999.
-- A retry with the same p_request_id (the
-- screen makes one per form) adds nothing again and answers with what was
-- added, but only when it is the same form: the same person, warehouse,
-- products, quantities, reason, note and reference. A form changed after a
-- failed save is refused rather than answered as if its changes were kept.
declare
  c_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  v_reason text := btrim(coalesce(p_reason, ''));
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_ref text := nullif(btrim(coalesce(p_reference, '')), '');
  e jsonb; r record; v_pid uuid; v_seen uuid[] := '{}'; v_lines jsonb; v_bad text;
  v_b public.warehouse_stock_in_batches%rowtype; v_mid uuid; v_mids uuid[] := '{}';
  v_out jsonb := '[]'::jsonb; v_qty integer;
begin
  perform public.require_active_staff();  -- 420: active staff only (406)
  if not public.can_manage_warehouse_stock() then raise exception 'Not authorized to add warehouse stock'; end if;
  -- The form's own rules first. They depend on nothing saved, so the same
  -- form sent again passes them again.
  if p_warehouse_id is null then raise exception 'Choose the warehouse'; end if;
  if v_reason = '' then raise exception 'A reason for stock-in is required'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Add at least one product with a quantity'; end if;
  for e in select x from jsonb_array_elements(p_lines) x loop
    if jsonb_typeof(e) <> 'object' or coalesce(e->>'product_id', '') !~* c_uuid then
      raise exception 'Every line needs a product'; end if;
    if coalesce(e->>'quantity', '') !~ '^[0-9]+$' or ltrim(e->>'quantity', '0') = '' then
      raise exception 'Every product needs a whole quantity greater than zero'; end if;
    -- The page allows the same (STOCK-5).
    if length(ltrim(e->>'quantity', '0')) > 6 then
      raise exception 'A quantity can be at most 999,999'; end if;
    v_pid := (e->>'product_id')::uuid;
    if v_pid = any (v_seen) then raise exception 'The same product is listed more than once'; end if;
    v_seen := v_seen || v_pid;
  end loop;
  select jsonb_agg(jsonb_build_object('product_id', (x->>'product_id')::uuid, 'quantity', (x->>'quantity')::integer)
                   order by (x->>'product_id')::uuid)
    into v_lines from jsonb_array_elements(p_lines) x;

  if p_request_id is not null then
    -- Two presses at once: the second waits here for the first, then finds it.
    perform pg_advisory_xact_lock(hashtextextended('warehouse_stock_ins:' || p_request_id::text, 0));
    select * into v_b from public.warehouse_stock_in_batches b where b.request_id = p_request_id;
    if found then
      if v_b.requested_by is distinct from auth.uid() or v_b.warehouse_id is distinct from p_warehouse_id then
        raise exception 'This form was already used for another stock-in. Close it and start again.'; end if;
      if v_b.lines is distinct from v_lines or v_b.reason is distinct from v_reason
         or v_b.note is distinct from v_note or v_b.reference is distinct from v_ref then
        raise exception 'This form was already saved, and has been changed since: nothing more was added. Close it, and add anything else as a new stock-in.'; end if;
      return jsonb_build_object('success', true, 'replayed', true, 'lines',
        (select jsonb_agg(jsonb_build_object('product_id', m.product_id, 'quantity', m.quantity, 'movement_id', m.id)
                          order by m.product_id)
           from public.stock_movements m where m.id = any (v_b.movement_ids)));
    end if;
  end if;

  -- Every product live, named when not, before anything is added.
  select string_agg(coalesce(p.name, 'a product that does not exist'), ', ' order by p.name) into v_bad
    from jsonb_array_elements(v_lines) x left join public.products p on p.id = (x->>'product_id')::uuid
   where p.id is null or p.deleted_at is not null or not p.is_active;
  if v_bad is not null then
    raise exception 'Nothing was added. Switched off or deleted: %. Restore it on the Products page, or take it off the form.', v_bad; end if;

  -- In product order, so two forms at once lock the same rows in the same order.
  for r in select (x->>'product_id')::uuid as product_id, (x->>'quantity')::integer as quantity
             from jsonb_array_elements(v_lines) x order by 1
  loop
    v_mid := public.warehouse_stock_in(p_warehouse_id, r.product_id, r.quantity, v_reason, v_note, v_ref);
    v_mids := v_mids || v_mid;
    select wi.current_qty into v_qty from public.warehouse_inventory wi
     where wi.warehouse_id = p_warehouse_id and wi.product_id = r.product_id;
    v_out := v_out || jsonb_build_object('product_id', r.product_id, 'quantity', r.quantity,
                                         'movement_id', v_mid, 'new_qty', v_qty);
  end loop;
  if p_request_id is not null then
    insert into public.warehouse_stock_in_batches (request_id, warehouse_id, requested_by, reason, note, reference, lines, movement_ids)
    values (p_request_id, p_warehouse_id, auth.uid(), v_reason, v_note, v_ref, v_lines, v_mids);
  end if;
  return jsonb_build_object('success', true, 'replayed', false, 'lines', v_out);
end $function$
$def$;
  c_requests_def constant text := $def$CREATE OR REPLACE FUNCTION public.request_inventory_adjustments(p_location_type text, p_location_id uuid, p_lines jsonb, p_reason text, p_reference text DEFAULT NULL::text, p_request_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 420: the stock corrections of one count, in one go (STOCK-5). Each line
-- becomes its own approval request through request_inventory_adjustment,
-- unchanged, so a line here is exactly a single request: its checks, its
-- payload and its audit row. p_lines is [{"product_id": "<uuid>", "new_qty": n}],
-- each product once, n the counted total. A line whose count matches the
-- system is not a correction (STOCK-4): it is left out and listed under
-- 'unchanged'; when every line matches, nothing is sent and the answer says
-- so. Any other refusal sends nothing at all. A retry with the same
-- p_request_id (the screen makes one per form) sends nothing again and
-- answers with what was sent, but only when it is the same form: the same
-- person, place, lines, reason and reference.
declare
  c_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  v_reason text := btrim(coalesce(p_reason, ''));
  v_ref text := nullif(btrim(coalesce(p_reference, '')), '');
  v_type public.location_type; e jsonb; r record; v_pid uuid; v_seen uuid[] := '{}';
  v_lines jsonb; v_hash text; v_id uuid; v_live integer; v_same text[] := '{}';
  v_requests jsonb := '[]'::jsonb; v_unchanged jsonb := '[]'::jsonb;
begin
  perform public.require_active_staff();  -- 420: active staff only (406)
  if p_location_type is null or p_location_type not in ('store', 'warehouse') then
    raise exception 'Location must be a store or a warehouse'; end if;
  v_type := p_location_type::public.location_type;
  if p_location_id is null then raise exception 'Choose where the stock was counted'; end if;
  if v_reason = '' then raise exception 'A reason is required'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Add at least one product with its counted total'; end if;
  for e in select x from jsonb_array_elements(p_lines) x loop
    if jsonb_typeof(e) <> 'object' or coalesce(e->>'product_id', '') !~* c_uuid then
      raise exception 'Every line needs a product'; end if;
    if coalesce(e->>'new_qty', '') !~ '^[0-9]{1,7}$' then
      raise exception 'Every product needs a whole counted total of 0 or more'; end if;
    v_pid := (e->>'product_id')::uuid;
    if v_pid = any (v_seen) then raise exception 'The same product is listed more than once'; end if;
    v_seen := v_seen || v_pid;
  end loop;
  -- The place first, so nobody learns another place's stock from the answer.
  if v_type = 'store' then
    if not public.user_has_store_access(p_location_id) then raise exception 'You can only adjust your assigned store'; end if;
  elsif not public.can_manage_warehouse_stock() then
    raise exception 'Not authorized to adjust warehouse stock';
  end if;
  select jsonb_agg(jsonb_build_array((x->>'product_id')::uuid, (x->>'new_qty')::integer) order by (x->>'product_id')::uuid)
    into v_lines from jsonb_array_elements(p_lines) x;
  v_hash := md5(jsonb_build_array(p_location_type, p_location_id, v_lines, v_reason, v_ref)::text);

  if p_request_id is not null then
    -- Two presses at once: the second waits here for the first, then finds it.
    perform pg_advisory_xact_lock(hashtextextended('request_inventory_adjustments:' || p_request_id::text, 0));
    if exists (select 1 from public.approval_requests a
                where a.request_type = 'adjustment' and a.payload ->> 'request_id' = p_request_id::text) then
      if exists (select 1 from public.approval_requests a
                  where a.request_type = 'adjustment' and a.payload ->> 'request_id' = p_request_id::text
                    and (a.requested_by is distinct from auth.uid() or a.payload ->> 'form_hash' is distinct from v_hash)) then
        raise exception 'This form was already sent, and has been changed since: nothing more was sent. Close it, and send any other correction as a new request.'; end if;
      return jsonb_build_object('success', true, 'replayed', true,
        'requests', (select jsonb_agg(jsonb_build_object('request_id', a.id, 'product_id', a.payload->>'product_id',
                       'current_qty', (a.payload->>'current_qty')::integer, 'new_qty', (a.payload->>'new_qty')::integer,
                       'difference', (a.payload->>'difference')::integer) order by a.payload->>'product_id')
                       from public.approval_requests a
                      where a.request_type = 'adjustment' and a.payload ->> 'request_id' = p_request_id::text),
        'unchanged', coalesce((select jsonb_agg(jsonb_build_object('product_id', l->>0, 'current_qty', (l->>1)::integer)
                                                order by l->>0)
                                 from jsonb_array_elements(v_lines) l
                                where not exists (select 1 from public.approval_requests a
                                                   where a.request_type = 'adjustment'
                                                     and a.payload ->> 'request_id' = p_request_id::text
                                                     and a.payload ->> 'product_id' = l->>0)), '[]'::jsonb));
    end if;
  end if;

  -- In product order, so two forms at once take their locks in the same order.
  for r in select (l->>0)::uuid as product_id, (l->>1)::integer as new_qty, p.name
             from jsonb_array_elements(v_lines) l left join public.products p on p.id = (l->>0)::uuid
            order by 1
  loop
    if v_type = 'store' then
      select si.current_qty into v_live from public.store_inventory si
       where si.store_id = p_location_id and si.product_id = r.product_id;
    else
      select wi.current_qty into v_live from public.warehouse_inventory wi
       where wi.warehouse_id = p_location_id and wi.product_id = r.product_id;
    end if;
    v_live := coalesce(v_live, 0);
    if r.new_qty = v_live then
      v_unchanged := v_unchanged || jsonb_build_object('product_id', r.product_id, 'current_qty', v_live);
      v_same := v_same || (coalesce(r.name, 'a product') || ' (' || v_live || ')');
      continue;
    end if;
    begin
      v_id := public.request_inventory_adjustment(v_type, p_location_id, r.product_id, r.new_qty, v_reason, v_ref);
    exception when raise_exception then
      raise exception '%: %', coalesce(r.name, 'A product'), sqlerrm;
    end;
    if p_request_id is not null then
      update public.approval_requests a
         set payload = a.payload || jsonb_build_object('request_id', p_request_id, 'form_hash', v_hash)
       where a.id = v_id;
    end if;
    v_requests := v_requests || jsonb_build_object('request_id', v_id, 'product_id', r.product_id,
      'current_qty', v_live, 'new_qty', r.new_qty, 'difference', r.new_qty - v_live);
  end loop;
  if jsonb_array_length(v_requests) = 0 then
    raise exception 'The count matches the system for every product (%), so nothing needs adjusting',
      array_to_string(v_same, ', '); end if;
  return jsonb_build_object('success', true, 'replayed', false, 'requests', v_requests, 'unchanged', v_unchanged);
end $function$
$def$;
  c_live_def constant text := $def$CREATE OR REPLACE FUNCTION public.pending_adjustments_live()
 RETURNS TABLE(request_id uuid, live_qty integer, product_live boolean, place_open boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 420 (the Owner, 9 Oct 2026): the Approvals card shows today's number beside
-- the count. For each pending stock correction: the stock there now, whether
-- the product is still live and whether the place is still open. An Owner or
-- Manager reads every place, as they approve at every place.
begin
  perform public.require_active_staff('{owner,manager}');  -- 420: the Approvals page's roles
  return query
  select a.id,
         coalesce(case when a.payload ->> 'location_type' = 'store'
                       then (select si.current_qty from public.store_inventory si
                              where si.store_id = (a.payload ->> 'location_id')::uuid
                                and si.product_id = (a.payload ->> 'product_id')::uuid)
                       else (select wi.current_qty from public.warehouse_inventory wi
                              where wi.warehouse_id = (a.payload ->> 'location_id')::uuid
                                and wi.product_id = (a.payload ->> 'product_id')::uuid) end, 0),
         exists (select 1 from public.products p where p.id = (a.payload ->> 'product_id')::uuid
                    and p.deleted_at is null and p.is_active),
         case when a.payload ->> 'location_type' = 'store'
              then exists (select 1 from public.stores s where s.id = (a.payload ->> 'location_id')::uuid
                              and s.deleted_at is null and s.is_active)
              else exists (select 1 from public.warehouses w where w.id = (a.payload ->> 'location_id')::uuid
                              and w.deleted_at is null and w.is_active) end
    from public.approval_requests a
   where a.request_type = 'adjustment' and a.status = 'pending'
     and a.payload ->> 'location_type' in ('store', 'warehouse')
     and a.payload ->> 'location_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     and a.payload ->> 'product_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   order by a.created_at;
end $function$
$def$;

  -- ── New: store assignments through the server ───────────────────────────
  c_assign_def constant text := $def$CREATE OR REPLACE FUNCTION public.assign_user_store(p_user_id uuid, p_store_id uuid, p_assigned boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 420 (the Owner, 9 Oct 2026; ADMIN-AUTH-15): who works at which store.
-- Managers put Staff and Inventory Managers on the stores they work at; only
-- an Owner changes a Manager's stores; nobody changes their own. Owners and
-- Admins work at every store and are not put on one. The roles a caller may
-- place are the ones the invitations use (can_assign_role), and a Manager's
-- stores are assignable_store_ids(). Every change leaves an audit row; asking
-- for what is already so changes nothing.
declare v_role public.user_role; v_t public.profiles%rowtype; v_s public.stores%rowtype; v_had boolean;
begin
  v_role := public.require_active_staff('{owner,admin,manager}');  -- 420: who manages store staff
  if p_user_id is null or p_store_id is null or p_assigned is null then
    raise exception 'Choose a person, a store, and whether they work there'; end if;
  select * into v_t from public.profiles where id = p_user_id for share;
  if not found or v_t.deleted_at is not null then raise exception 'That person is not on the staff list'; end if;
  select * into v_s from public.stores where id = p_store_id;
  if not found then raise exception 'Store not found'; end if;
  if p_assigned and (v_s.deleted_at is not null or not v_s.is_active) then
    raise exception '% is closed or deleted, so nobody can be put on it', v_s.name; end if;
  if p_assigned and v_t.role in ('owner', 'admin') then
    raise exception 'Owners and Admins work at every store, so they are not put on one'; end if;
  if v_role is not null then
    if p_user_id = auth.uid() then
      raise exception 'You cannot change your own stores. Ask an Owner.' using errcode = '42501'; end if;
    if v_t.role = 'manager' and v_role <> 'owner' then
      raise exception 'Only an Owner can change a Manager''s stores.' using errcode = '42501'; end if;
    if not public.can_assign_role(v_t.role) then
      raise exception 'Your role cannot change this person''s stores.' using errcode = '42501'; end if;
    if v_role = 'manager' and not (p_store_id = any (public.assignable_store_ids())) then
      raise exception 'You can only put people on the stores you work at.' using errcode = '42501'; end if;
  end if;

  v_had := exists (select 1 from public.user_store_assignments u where u.user_id = p_user_id and u.store_id = p_store_id);
  if p_assigned = v_had then
    return jsonb_build_object('success', true, 'assigned', p_assigned, 'changed', false); end if;
  if p_assigned then
    insert into public.user_store_assignments (user_id, store_id) values (p_user_id, p_store_id)
    on conflict (user_id, store_id) do nothing;
  else
    delete from public.user_store_assignments u where u.user_id = p_user_id and u.store_id = p_store_id;
  end if;
  perform public.write_audit('user_store_assignments', p_user_id,
    case when p_assigned then 'store_assigned' else 'store_unassigned' end, null,
    jsonb_build_object('store_id', p_store_id, 'store', v_s.name, 'role', v_t.role));
  return jsonb_build_object('success', true, 'assigned', p_assigned, 'changed', true);
end $function$
$def$;

  -- ── Production, 9 Oct 2026 (after 413) ──────────────────────────────────
  c_request_before constant text := '5d561e99d3e0cf2ec71ec07df33a15ea';
  c_resolve_before constant text := 'df89435e34bcf0858ade6f2d91cdbefe';
  c_stock_in_before constant text := '394999b1b4dc942c8d03735cf367a247';
  c_staff_406 constant text := '877b3aa74cea559881979bb161c450e2';  -- require_active_staff(text[])
  c_audit_406 constant text := '19cd6b07bdbb6c73c26fb8aa83d2463e';  -- write_audit(text,uuid,text,jsonb,jsonb)

  -- AFTER md5s, in the order of v_sigs below.
  c_after constant text[] := array[
    'f46897361f4d9f80694a8267e44d2cfa', '94c01092a241f8c441bfc9c13ca5cc7f', '48514d10c2c6ecabbbf890827e27b770',
    '7c2a2d19f96ddd3a05dd65f72dd15f63', '341848851fa75b9bd1dd221aed594215', '9d157e1434cb0c22a833303bbbade8bb',
    '905cdc6ded1a0f3cda513a1884ee238a', 'fbb87549e22a26f0db4a52849b9903a8', 'ed39a80dabc21a2bfa5116e925e2e141',
    '61020273511f69bac2dd86d530d38d2e', 'a29cb102c967cc5a2939a1a334e86b07', 'c784eb4c546517953face2380216e2f4',
    'e55ad0e4a8a95c849f46cd8535a6c05a', '4e9ebc1f3971c591a509837b2c734baa', 'a8b7d46da5b22c24e61d565a41d489e5',
    '9c2ed0a5814bc829a06b56d4648ad3bd', 'd52aee001ec2343f1fe3699843c3df71'];
  v_sigs constant text[] := array[
    'request_inventory_adjustment(location_type,uuid,uuid,integer,text,text)',
    'resolve_inventory_adjustment(uuid,boolean,text)',
    'warehouse_stock_in(uuid,uuid,integer,text,text,text)',
    'stock_retire_blockers(text,uuid)', 'trg_stock_place_retire()', 'can_edit_products()',
    'save_product(uuid,jsonb,uuid[],uuid[])',
    'soft_delete_product(uuid)', 'restore_product(uuid)', 'soft_delete_store(uuid)', 'restore_store(uuid)',
    'soft_delete_warehouse(uuid)', 'restore_warehouse(uuid)',
    'warehouse_stock_ins(uuid,jsonb,text,text,text,uuid)',
    'request_inventory_adjustments(text,uuid,jsonb,text,text,uuid)',
    'pending_adjustments_live()', 'assign_user_store(uuid,uuid,boolean)'];
  -- Who may call each new one: 'client' = signed-in staff (and the service
  -- role); 'internal' = the service role alone (339). The three replaced keep
  -- their grants.
  v_kind constant text[] := array['kept', 'kept', 'kept',
    'internal', 'internal', 'client', 'client',
    'client', 'client', 'client', 'client', 'client', 'client', 'client', 'client', 'client', 'client'];

  -- The table rules this replaces, as read on 9 Oct 2026: table|name|cmd|using|with check.
  c_rules_before constant text[] := array[
    'products|manage products|ALL|can_manage_warehouse_stock()|can_manage_warehouse_stock()',
    'stores|manage stores|ALL|is_owner_or_manager()|is_owner_or_manager()',
    'warehouses|manage warehouses|ALL|is_owner_or_manager()|is_owner_or_manager()',
    'product_categories|product_categories write|ALL|is_owner_or_manager()|is_owner_or_manager()',
    'product_suppliers|product_suppliers write|ALL|is_owner_or_manager()|is_owner_or_manager()',
    'user_store_assignments|manage assignments|ALL|is_manager_or_above()|is_manager_or_above()',
    'store_inventory|write store inventory|ALL|is_manager_or_above()|is_manager_or_above()',
    'warehouse_inventory|write warehouse inventory|ALL|can_manage_warehouse_stock()|can_manage_warehouse_stock()',
    'transfer_request_lines|write transfer lines|ALL|(current_user_role() IS NOT NULL)|(current_user_role() IS NOT NULL)'];
  -- ...and the rules it leaves (the write rules of these nine tables, after).
  c_rules_after constant text :=
       'product_categories|product_categories write|ALL|( SELECT can_edit_products() AS can_edit_products)|( SELECT can_edit_products() AS can_edit_products)'
    || chr(10) || 'product_suppliers|product_suppliers write|ALL|( SELECT can_edit_products() AS can_edit_products)|( SELECT can_edit_products() AS can_edit_products)'
    || chr(10) || 'products|insert products|INSERT|-|( SELECT can_edit_products() AS can_edit_products)'
    || chr(10) || 'products|update products|UPDATE|( SELECT can_edit_products() AS can_edit_products)|( SELECT can_edit_products() AS can_edit_products)'
    || chr(10) || 'stores|insert stores|INSERT|-|( SELECT is_owner_or_manager() AS is_owner_or_manager)'
    || chr(10) || 'stores|update stores|UPDATE|( SELECT is_owner_or_manager() AS is_owner_or_manager)|( SELECT is_owner_or_manager() AS is_owner_or_manager)'
    || chr(10) || 'warehouses|insert warehouses|INSERT|-|( SELECT is_owner_or_manager() AS is_owner_or_manager)'
    || chr(10) || 'warehouses|update warehouses|UPDATE|( SELECT is_owner_or_manager() AS is_owner_or_manager)|( SELECT is_owner_or_manager() AS is_owner_or_manager)';
  -- The read rules on store_inventory, as read on 9 Oct 2026 (before), and
  -- after: "write store inventory" (FOR ALL) also let Owners, Admins and
  -- Managers read every store's stock, so its read part stays as "managers
  -- read store inventory". Who reads store stock does not change.
  -- name|cmd|permissive|roles|using|with check, by name.
  c_store_reads constant text :=
       'read store inventory|SELECT|PERMISSIVE|authenticated|user_has_store_access(store_id)|-'
    || chr(10) || 'stock_history_store_scope|SELECT|RESTRICTIVE|authenticated|stock_history_location(''store''::text, store_id)|-';
  c_store_reads_after constant text :=
       'managers read store inventory|SELECT|PERMISSIVE|authenticated|( SELECT is_manager_or_above() AS is_manager_or_above)|-'
    || chr(10) || c_store_reads;
  c_tables constant text[] := array['products', 'stores', 'warehouses', 'product_categories', 'product_suppliers',
    'user_store_assignments', 'store_inventory', 'warehouse_inventory', 'transfer_request_lines'];

  -- The retire triggers, as pg_get_triggerdef gives them.
  c_triggers constant text :=
       'CREATE TRIGGER products_retire_check BEFORE UPDATE OF is_active, deleted_at ON public.products FOR EACH ROW WHEN ((((old.deleted_at IS NULL) AND (new.deleted_at IS NOT NULL)) OR (old.is_active AND (NOT new.is_active)))) EXECUTE FUNCTION trg_stock_place_retire()'
    || chr(10) || 'CREATE TRIGGER stores_retire_check BEFORE UPDATE OF is_active, deleted_at ON public.stores FOR EACH ROW WHEN ((((old.deleted_at IS NULL) AND (new.deleted_at IS NOT NULL)) OR (old.is_active AND (NOT new.is_active)))) EXECUTE FUNCTION trg_stock_place_retire()'
    || chr(10) || 'CREATE TRIGGER warehouses_retire_check BEFORE UPDATE OF is_active, deleted_at ON public.warehouses FOR EACH ROW WHEN ((((old.deleted_at IS NULL) AND (new.deleted_at IS NOT NULL)) OR (old.is_active AND (NOT new.is_active)))) EXECUTE FUNCTION trg_stock_place_retire()';

  -- warehouse_stock_in_batches as this makes it: columns, then constraints.
  c_cols constant text := 'request_id uuid not null|warehouse_id uuid not null|requested_by uuid|reason text not null|note text|reference text|lines jsonb not null|movement_ids uuid[] not null|created_at timestamp with time zone not null default now()';
  c_cons constant text := 'FOREIGN KEY (warehouse_id) REFERENCES warehouses(id)|PRIMARY KEY (request_id)';

  v_defs text[];
  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_claim_role text := current_setting('request.jwt.claim.role', true);
  v_state text[] := '{}';       -- per function: 'before', 'after' or 'missing'
  v text; v_bad text; v_rules text; i int; n int; v_md5 text;
  v_table_new boolean; v_rules_new boolean; v_trg_new boolean;
  v_owner uuid; v_mgr uuid; v_inv uuid; v_staff uuid; v_st uuid; v_st2 uuid; v_wh uuid; v_p uuid; v_r jsonb; v_req uuid;
  v_rid uuid := gen_random_uuid();
begin
  perform set_config('search_path', 'public', true);
  v_defs := array[c_request_def, c_resolve_def, c_stock_in_def, c_blockers_def, c_trg_def, c_can_edit_def, c_save_def,
                  c_del_product_def, c_res_product_def, c_del_store_def, c_res_store_def, c_del_wh_def, c_res_wh_def,
                  c_stock_ins_def, c_requests_def, c_live_def, c_assign_def];

  -- ── Guards: nothing changes unless all pass ──────────────────────────────
  -- 406's checks and the audit writer, as 406 left them.
  if to_regprocedure('public.require_active_staff(text[])') is null
     or md5(pg_get_functiondef('public.require_active_staff(text[])'::regprocedure)) <> c_staff_406 then
    raise exception '420: require_active_staff(text[]) is not 406''s version; re-read and re-test'; end if;
  if to_regprocedure('public.write_audit(text,uuid,text,jsonb,jsonb)') is null
     or md5(pg_get_functiondef('public.write_audit(text,uuid,text,jsonb,jsonb)'::regprocedure)) <> c_audit_406 then
    raise exception '420: write_audit is not the version read on 9 Oct 2026; re-read and re-test'; end if;
  -- The role helpers this calls. Other batches may change their bodies (B15:
  -- can_assign_role, user_admin_role, assignable_store_ids; B17:
  -- user_has_store_access, is_owner_or_manager, current_user_role), so they
  -- are checked by name and result here, and by behaviour below.
  select string_agg(x.sig, ', ') into v_bad from (values
      ('user_has_store_access(uuid)', 'boolean'), ('can_manage_warehouse_stock()', 'boolean'),
      ('is_owner_or_manager()', 'boolean'), ('is_manager_or_above()', 'boolean'), ('current_user_role()', 'user_role'),
      ('can_assign_role(user_role)', 'boolean'), ('assignable_store_ids()', 'uuid[]'), ('sg_today()', 'date')) x(sig, ret)
   where to_regprocedure('public.' || x.sig) is null
      or format_type((select p.prorettype from pg_proc p where p.oid = to_regprocedure('public.' || x.sig)), null) <> x.ret;
  if v_bad is not null then raise exception '420: a helper this relies on is missing or changed its result: %', v_bad; end if;

  -- Each function: the version read on 9 Oct 2026 (the three replaced), missing
  -- (the new ones), or already this migration's.
  for i in 1 .. array_length(v_sigs, 1) loop
    if to_regprocedure('public.' || v_sigs[i]) is null then
      if i <= 3 then raise exception '420: public.% is missing', v_sigs[i]; end if;
      v_state := v_state || 'missing'::text;
    else
      v_md5 := md5(pg_get_functiondef(to_regprocedure('public.' || v_sigs[i])));
      if v_md5 = c_after[i] then v_state := v_state || 'after'::text;
      elsif i = 1 and v_md5 = c_request_before or i = 2 and v_md5 = c_resolve_before
            or i = 3 and v_md5 = c_stock_in_before then v_state := v_state || 'before'::text;
      else raise exception '420: public.% is neither the version read on 9 Oct 2026 nor this migration''s (md5 %)', v_sigs[i], v_md5;
      end if;
    end if;
  end loop;
  -- No other function takes one of these names (the API picks by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname = any (array(select split_part(s, '(', 1) from unnest(v_sigs) s))
     and not (p.oid::regprocedure::text = any (v_sigs));
  if v_bad is not null then raise exception '420: another function takes one of these names: %', v_bad; end if;

  -- The tables, as read on 9 Oct 2026.
  select string_agg(c.relname || '.' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by c.relname, a.attname) into v
    from pg_attribute a join pg_class c on c.oid = a.attrelid
   where c.relnamespace = 'public'::regnamespace and not a.attisdropped
     and c.relname in ('products', 'stores', 'warehouses') and a.attname in ('id', 'name', 'is_active', 'deleted_at');
  if v is distinct from 'products.deleted_at timestamp with time zone|products.id uuid|products.is_active boolean|products.name text|stores.deleted_at timestamp with time zone|stores.id uuid|stores.is_active boolean|stores.name text|warehouses.deleted_at timestamp with time zone|warehouses.id uuid|warehouses.is_active boolean|warehouses.name text' then
    raise exception '420: products, stores or warehouses are not shaped as read on 9 Oct 2026 (%)', v; end if;
  if not exists (select 1 from pg_constraint k where k.conrelid = 'public.store_inventory'::regclass and pg_get_constraintdef(k.oid) = 'UNIQUE (store_id, product_id)')
     or not exists (select 1 from pg_constraint k where k.conrelid = 'public.warehouse_inventory'::regclass and pg_get_constraintdef(k.oid) = 'UNIQUE (warehouse_id, product_id)')
     or not exists (select 1 from pg_constraint k where k.conrelid = 'public.user_store_assignments'::regclass and pg_get_constraintdef(k.oid) = 'UNIQUE (user_id, store_id)')
     or not exists (select 1 from pg_constraint k where k.conrelid = 'public.product_categories'::regclass and pg_get_constraintdef(k.oid) = 'PRIMARY KEY (product_id, category_id)')
     or not exists (select 1 from pg_constraint k where k.conrelid = 'public.product_suppliers'::regclass and pg_get_constraintdef(k.oid) = 'PRIMARY KEY (product_id, supplier_id)')
     or not exists (select 1 from pg_constraint k where k.conrelid = 'public.stock_movements'::regclass and pg_get_constraintdef(k.oid) = 'CHECK ((quantity > 0))') then
    raise exception '420: a key or check this relies on is not as read on 9 Oct 2026'; end if;
  -- Where a rejection's reason is kept (as resolve_invoice_action_v2 keeps it).
  select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), '|' order by a.attname) into v
    from pg_attribute a where a.attrelid = 'public.approval_requests'::regclass and not a.attisdropped
     and a.attname in ('rejection_reason', 'response_note');
  if v is distinct from 'rejection_reason text|response_note text' then
    raise exception '420: approval_requests.response_note and rejection_reason are not as read on 9 Oct 2026 (%)', v; end if;
  -- No trigger of another kind on the three tables; ours all there or none.
  select string_agg(pg_get_triggerdef(t.oid), chr(10) order by t.tgname) into v
    from pg_trigger t where t.tgrelid in ('public.products'::regclass, 'public.stores'::regclass, 'public.warehouses'::regclass)
     and not t.tgisinternal;
  if v is not null and v is distinct from c_triggers then
    raise exception '420: products, stores or warehouses have triggers other than this migration''s (%)', v; end if;
  v_trg_new := v is null;

  -- The table rules: as read on 9 Oct 2026, or already this migration's.
  select string_agg(p.tablename || '|' || p.policyname || '|' || p.cmd || '|' || coalesce(p.qual, '-') || '|' || coalesce(p.with_check, '-'),
                    chr(10) order by p.tablename, p.policyname) into v_rules
    from pg_policies p where p.schemaname = 'public' and p.tablename = any (c_tables) and p.cmd <> 'SELECT';
  if v_rules = array_to_string(array(select x from unnest(c_rules_before) x order by x collate "C"), chr(10)) then
    v_rules_new := true;
  elsif v_rules = c_rules_after then
    v_rules_new := false;
  else
    raise exception '420: the write rules on the stock and product tables are not as read on 9 Oct 2026: %', v_rules;
  end if;
  -- The read rules on store stock: as read on 9 Oct 2026, or already this
  -- migration's (with the write rules above).
  select string_agg(p.policyname || '|' || p.cmd || '|' || p.permissive || '|' || array_to_string(p.roles, ',')
                    || '|' || coalesce(p.qual, '-') || '|' || coalesce(p.with_check, '-'), chr(10) order by p.policyname) into v
    from pg_policies p where p.schemaname = 'public' and p.tablename = 'store_inventory' and p.cmd = 'SELECT';
  if v is distinct from (case when v_rules_new then c_store_reads else c_store_reads_after end) then
    raise exception '420: the read rules on store_inventory are not as read on 9 Oct 2026 nor this migration''s: %', coalesce(v, '<none>'); end if;

  -- The batch table: missing, or already exactly this.
  v_table_new := to_regclass('public.warehouse_stock_in_batches') is null;
  if not v_table_new then
    select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
                      || case when a.attnotnull then ' not null' else '' end
                      || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), ''), '|' order by a.attnum) into v
      from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
     where a.attrelid = 'public.warehouse_stock_in_batches'::regclass and a.attnum > 0 and not a.attisdropped;
    if v is distinct from c_cols then raise exception '420: warehouse_stock_in_batches is not this migration''s (%)', v; end if;
    select string_agg(pg_get_constraintdef(k.oid), '|' order by pg_get_constraintdef(k.oid)) into v
      from pg_constraint k where k.conrelid = 'public.warehouse_stock_in_batches'::regclass;
    if v is distinct from c_cons then raise exception '420: warehouse_stock_in_batches has other constraints (%)', v; end if;
  end if;
  -- All of this migration, or none of it.
  if (select count(distinct s) from unnest(v_state[1:3]) s) <> 1
     or (select count(distinct s) from unnest(v_state[4:17]) s) <> 1
     or (v_state[1] = 'after') <> (v_state[4] = 'after')
     or (v_state[4] = 'missing') <> v_table_new or (v_state[4] = 'missing') <> v_trg_new
     or (v_state[4] = 'missing') <> v_rules_new then
    raise exception '420: only part of this migration is installed; re-read and re-test'; end if;

  -- The texts are the tested ones.
  select string_agg(v_sigs[k] || ' ' || md5(v_defs[k]), '; ') into v_bad
    from generate_subscripts(v_sigs, 1) k where md5(v_defs[k]) <> c_after[k];
  if v_bad is not null then raise exception '420: a text is not the tested one: %', v_bad; end if;

  -- ── Change ───────────────────────────────────────────────────────────────
  if v_table_new then
    create table public.warehouse_stock_in_batches (
      request_id uuid primary key,
      warehouse_id uuid not null references public.warehouses(id),
      requested_by uuid,
      reason text not null,
      note text,
      reference text,
      lines jsonb not null,
      movement_ids uuid[] not null,
      created_at timestamptz not null default now());
    comment on table public.warehouse_stock_in_batches is
      '420: one row per multi-line Stock In sent with a request id, so a retry of the same form adds nothing again. Written by warehouse_stock_ins() only.';
  end if;
  alter table public.warehouse_stock_in_batches enable row level security;
  revoke all on table public.warehouse_stock_in_batches from public, anon, authenticated, service_role;
  grant select on table public.warehouse_stock_in_batches to service_role;

  -- Helpers first, then what calls them.
  for i in 1 .. array_length(v_sigs, 1) loop
    if v_state[i] <> 'after' then
      execute v_defs[i];
      if v_kind[i] = 'internal' then
        execute format('revoke all on function public.%s from public, anon, authenticated', v_sigs[i]);
        execute format('grant execute on function public.%s to service_role', v_sigs[i]);
      elsif v_kind[i] = 'client' then
        execute format('revoke all on function public.%s from public, anon', v_sigs[i]);
        execute format('grant execute on function public.%s to authenticated, service_role', v_sigs[i]);
      end if;
    end if;
  end loop;

  if v_trg_new then
    create trigger products_retire_check before update of is_active, deleted_at on public.products
      for each row when ((old.deleted_at is null and new.deleted_at is not null) or (old.is_active and not new.is_active))
      execute function public.trg_stock_place_retire();
    -- A store or warehouse: deleting it or switching it off (the Owner, 9 Oct
    -- 2026: not while it still holds stock).
    create trigger stores_retire_check before update of is_active, deleted_at on public.stores
      for each row when ((old.deleted_at is null and new.deleted_at is not null) or (old.is_active and not new.is_active))
      execute function public.trg_stock_place_retire();
    create trigger warehouses_retire_check before update of is_active, deleted_at on public.warehouses
      for each row when ((old.deleted_at is null and new.deleted_at is not null) or (old.is_active and not new.is_active))
      execute function public.trg_stock_place_retire();
  end if;

  if v_rules_new then
    -- Products: added and changed by can_edit_products(); never removed.
    drop policy "manage products" on public.products;
    create policy "insert products" on public.products for insert to authenticated
      with check ((select public.can_edit_products()));
    create policy "update products" on public.products for update to authenticated
      using ((select public.can_edit_products())) with check ((select public.can_edit_products()));
    -- Stores and warehouses: added and changed by an Owner or Manager, as
    -- before; removed only through soft_delete_*.
    drop policy "manage stores" on public.stores;
    create policy "insert stores" on public.stores for insert to authenticated
      with check ((select public.is_owner_or_manager()));
    create policy "update stores" on public.stores for update to authenticated
      using ((select public.is_owner_or_manager())) with check ((select public.is_owner_or_manager()));
    drop policy "manage warehouses" on public.warehouses;
    create policy "insert warehouses" on public.warehouses for insert to authenticated
      with check ((select public.is_owner_or_manager()));
    create policy "update warehouses" on public.warehouses for update to authenticated
      using ((select public.is_owner_or_manager())) with check ((select public.is_owner_or_manager()));
    -- A product's category and supplier links: whoever edits products (the
    -- lists of brands, categories and suppliers stay with Owners and Managers).
    drop policy "product_categories write" on public.product_categories;
    create policy "product_categories write" on public.product_categories for all to authenticated
      using ((select public.can_edit_products())) with check ((select public.can_edit_products()));
    drop policy "product_suppliers write" on public.product_suppliers;
    create policy "product_suppliers write" on public.product_suppliers for all to authenticated
      using ((select public.can_edit_products())) with check ((select public.can_edit_products()));
    -- Written by the server only: store assignments (assign_user_store), stock
    -- (the stock functions), and transfer lines (a dead rule: no client grant).
    drop policy "manage assignments" on public.user_store_assignments;
    -- "write store inventory" (FOR ALL) also let Owners, Admins and Managers
    -- read every store's stock. Its read part stays: Reports, Transfers,
    -- Invoices, Special, Exchanges, the Dashboard and the referral panel read
    -- other stores' stock for a Manager. Store Stock and New Adjustment list
    -- a Manager's own stores only (the Owner, 9 Oct 2026: on Store Stock).
    drop policy "write store inventory" on public.store_inventory;
    create policy "managers read store inventory" on public.store_inventory for select to authenticated
      using ((select public.is_manager_or_above()));
    drop policy "write warehouse inventory" on public.warehouse_inventory;
    drop policy "write transfer lines" on public.transfer_request_lines;
  end if;
  -- Grants (each line is a no-op on a re-run). Reading is unchanged.
  revoke insert, update, delete, truncate on table public.store_inventory, public.warehouse_inventory,
    public.stock_movements, public.user_store_assignments from anon, authenticated;
  revoke delete, truncate on table public.products, public.stores, public.warehouses from anon, authenticated;
  revoke insert, update on table public.products, public.stores, public.warehouses from anon;
  revoke insert, update, delete, truncate on table public.product_categories, public.product_suppliers from anon;
  revoke truncate on table public.product_categories, public.product_suppliers from authenticated;

  -- ── As tested ────────────────────────────────────────────────────────────
  select string_agg(v_sigs[k], ', ') into v_bad from generate_subscripts(v_sigs, 1) k
   where md5(pg_get_functiondef(to_regprocedure('public.' || v_sigs[k]))) <> c_after[k];
  if v_bad is not null then raise exception '420: installed with md5s other than the tested ones: %', v_bad; end if;
  select string_agg(pg_get_triggerdef(t.oid), chr(10) order by t.tgname) into v
    from pg_trigger t where t.tgrelid in ('public.products'::regclass, 'public.stores'::regclass, 'public.warehouses'::regclass)
     and not t.tgisinternal and t.tgenabled = 'O';
  if v is distinct from c_triggers then raise exception '420: the retire triggers are not as tested (%)', v; end if;
  select string_agg(p.tablename || '|' || p.policyname || '|' || p.cmd || '|' || coalesce(p.qual, '-') || '|' || coalesce(p.with_check, '-'),
                    chr(10) order by p.tablename, p.policyname) into v
    from pg_policies p where p.schemaname = 'public' and p.tablename = any (c_tables) and p.cmd <> 'SELECT';
  if v is distinct from c_rules_after then raise exception '420: the write rules are not as tested: %', v; end if;
  select string_agg(p.policyname || '|' || p.cmd || '|' || p.permissive || '|' || array_to_string(p.roles, ',')
                    || '|' || coalesce(p.qual, '-') || '|' || coalesce(p.with_check, '-'), chr(10) order by p.policyname) into v
    from pg_policies p where p.schemaname = 'public' and p.tablename = 'store_inventory' and p.cmd = 'SELECT';
  if v is distinct from c_store_reads_after then raise exception '420: the read rules on store_inventory are not as tested: %', v; end if;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.warehouse_stock_in_batches'::regclass)
     or exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'warehouse_stock_in_batches') then
    raise exception '420: warehouse_stock_in_batches must have row level security on and no rule'; end if;

  -- ── Grants, by the catalogue ─────────────────────────────────────────────
  for i in 1 .. array_length(v_sigs, 1) loop
    if has_function_privilege('anon', 'public.' || v_sigs[i], 'execute')
       or not has_function_privilege('service_role', 'public.' || v_sigs[i], 'execute')
       or has_function_privilege('authenticated', 'public.' || v_sigs[i], 'execute') <> (v_kind[i] <> 'internal') then
      raise exception '420: the grants on public.% are not as tested', v_sigs[i]; end if;
  end loop;
  foreach v in array array['store_inventory', 'warehouse_inventory', 'stock_movements', 'user_store_assignments'] loop
    if has_table_privilege('anon', 'public.' || v, 'insert,update,delete,truncate')
       or has_table_privilege('authenticated', 'public.' || v, 'insert,update,delete,truncate')
       or not has_table_privilege('authenticated', 'public.' || v, 'select') then
      raise exception '420: the grants on public.% are not as tested', v; end if;
  end loop;
  foreach v in array array['products', 'stores', 'warehouses'] loop
    if has_table_privilege('anon', 'public.' || v, 'insert,update,delete,truncate')
       or has_table_privilege('authenticated', 'public.' || v, 'delete,truncate')
       or not has_table_privilege('authenticated', 'public.' || v, 'select')
       or not has_table_privilege('authenticated', 'public.' || v, 'insert')
       or not has_table_privilege('authenticated', 'public.' || v, 'update') then
      raise exception '420: the grants on public.% are not as tested', v; end if;
  end loop;
  if has_table_privilege('anon', 'public.warehouse_stock_in_batches', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'public.warehouse_stock_in_batches', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('service_role', 'public.warehouse_stock_in_batches', 'insert,update,delete,truncate,references,trigger')
     or not has_table_privilege('service_role', 'public.warehouse_stock_in_batches', 'select') then
    raise exception '420: the grants on public.warehouse_stock_in_batches are not as tested'; end if;

  -- ── Behaviour, switching role (nothing is printed, no row remains) ───────
  -- A signed-in login with no profile is refused by the new client functions.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    perform public.warehouse_stock_ins(null, null, null);
    raise exception '420: a login with no profile reached warehouse_stock_ins';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.assign_user_store(null, null, null);
    raise exception '420: a login with no profile reached assign_user_store';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.stock_retire_blockers('product', gen_random_uuid());
    raise exception '420: a signed-in login may call stock_retire_blockers';
  exception when insufficient_privilege then null;
  end;
  execute 'reset role';

  -- The pages' work, inside a block that is always undone: a made-up Owner,
  -- Manager, Inventory Manager and member of Staff (@sig.invalid), a store, a
  -- warehouse and a product.
  begin
    perform set_config('request.jwt.claims', '', true);
    insert into auth.users (id, email)
    select gen_random_uuid(), '420-check-' || k || '-' || gen_random_uuid() || '@sig.invalid'
      from unnest(array['owner', 'manager', 'invman', 'staff']) k;
    select u.id into v_owner from auth.users u where u.email like '420-check-owner-%@sig.invalid';
    select u.id into v_mgr from auth.users u where u.email like '420-check-manager-%@sig.invalid';
    select u.id into v_inv from auth.users u where u.email like '420-check-invman-%@sig.invalid';
    select u.id into v_staff from auth.users u where u.email like '420-check-staff-%@sig.invalid';
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '420 check', u.email, x.role::public.user_role, true
      from auth.users u join (values (v_owner, 'owner'), (v_mgr, 'manager'), (v_inv, 'inventory_manager'),
                                     (v_staff, 'staff')) x(id, role) on x.id = u.id;
    insert into public.stores (name, code, country_code) values ('420 check store', '420-CHECK-' || gen_random_uuid(), 'SG')
      returning id into v_st;
    insert into public.warehouses (name, code) values ('420 check warehouse', '420-CHECK-' || gen_random_uuid())
      returning id into v_wh;
    insert into public.products (name, sku) values ('420 check product', '420-CHECK-' || gen_random_uuid())
      returning id into v_p;
    insert into public.user_store_assignments (user_id, store_id) values (v_mgr, v_st);

    -- An Inventory Manager adds 5 in one form; the same form again adds nothing.
    perform set_config('request.jwt.claims', json_build_object('sub', v_inv, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_r := public.warehouse_stock_ins(v_wh, jsonb_build_array(jsonb_build_object('product_id', v_p, 'quantity', 5)), 'Delivery', null, null, v_rid);
    if (public.warehouse_stock_ins(v_wh, jsonb_build_array(jsonb_build_object('product_id', v_p, 'quantity', 5)), 'Delivery', null, null, v_rid)
          -> 'lines' -> 0 ->> 'movement_id') is distinct from (v_r -> 'lines' -> 0 ->> 'movement_id') then
      raise exception '420: the same Stock In form sent again was not answered with what it added'; end if;
    -- They count 3; a delivery of 10 arrives before the approval.
    v_r := public.request_inventory_adjustments('warehouse', v_wh, jsonb_build_array(jsonb_build_object('product_id', v_p, 'new_qty', 3)),
                                                'Count', null, gen_random_uuid());
    v_req := (v_r -> 'requests' -> 0 ->> 'request_id')::uuid;
    perform public.warehouse_stock_in(v_wh, v_p, 10, 'Delivery');
    -- A direct write to stock is refused.
    begin
      update public.warehouse_inventory set current_qty = 0 where warehouse_id = v_wh;
      raise exception '420: an Inventory Manager changed warehouse stock directly';
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';

    perform set_config('request.jwt.claims', json_build_object('sub', v_mgr, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      perform public.resolve_inventory_adjustment(v_req, true, null);
      raise exception '420: a count was approved over a delivery that came after it';
    exception when raise_exception then
      if sqlerrm not like 'Stock changed since this count (was 5, now 15).%' then raise; end if;
    end;
    -- Rejecting it needs a reason.
    begin
      perform public.resolve_inventory_adjustment(v_req, false, '  ');
      raise exception '420: a stock correction was rejected without a reason';
    exception when raise_exception then
      if sqlerrm not like 'Give a reason for rejecting this correction.%' then raise; end if;
    end;
    -- The warehouse cannot be switched off while it holds stock.
    begin
      update public.warehouses set is_active = false where id = v_wh;
      raise exception '420: a warehouse holding stock was switched off';
    exception when raise_exception then
      if sqlerrm not like '420 check warehouse cannot be switched off yet. Still open: stock of 1 product (15 units)%' then raise; end if;
    end;
    -- The product cannot be deleted while it holds stock.
    begin
      perform public.soft_delete_product(v_p);
      raise exception '420: a product holding stock was deleted';
    exception when raise_exception then
      if sqlerrm not like '420 check product cannot be deleted yet. Still open: stock (15 at 420 check warehouse)%' then raise; end if;
    end;
    -- A Manager puts Staff on their store, and cannot put themselves or another store.
    if (public.assign_user_store(v_staff, v_st, true) ->> 'changed') is distinct from 'true' then
      raise exception '420: a Manager could not put Staff on their store'; end if;
    begin
      perform public.assign_user_store(v_mgr, v_st, false);
      raise exception '420: a Manager changed their own stores';
    exception when insufficient_privilege then null;
    end;
    begin
      insert into public.user_store_assignments (user_id, store_id) values (v_inv, v_st);
      raise exception '420: a Manager wrote a store assignment directly';
    exception when insufficient_privilege then null;
    end;
    execute 'reset role';
    -- Who reads store stock is as before: an Owner and a Manager every store,
    -- Staff only the stores they work at.
    perform set_config('request.jwt.claims', '', true);
    insert into public.stores (name, code, country_code) values ('420 check other store', '420-CHECK-' || gen_random_uuid(), 'SG')
      returning id into v_st2;
    insert into public.store_inventory (store_id, product_id, current_qty) values (v_st2, v_p, 4), (v_st, v_p, 2);
    perform set_config('request.jwt.claims', json_build_object('sub', v_mgr, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    if (select count(*) from public.store_inventory where store_id = v_st2) <> 1 then
      raise exception '420: a Manager cannot read the stock of a store they do not work at'; end if;
    if (select count(*) from public.store_inventory where store_id = v_st) <> 1 then
      raise exception '420: a Manager cannot read the stock of a store they work at'; end if;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    if (select count(*) from public.store_inventory where store_id = v_st2) <> 1 then
      raise exception '420: an Owner cannot read the stock of every store'; end if;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    if (select count(*) from public.store_inventory where store_id = v_st2) <> 0 then
      raise exception '420: Staff read the stock of a store they do not work at'; end if;
    execute 'reset role';
    raise exception using errcode = 'P0420', message = '420: check done, undone';
  exception when sqlstate 'P0420' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_claim_role, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
