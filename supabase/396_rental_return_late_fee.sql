-- 396_rental_return_late_fee.sql
--
-- WHAT WAS WRONG (found 6 Oct 2026)
--
-- The Return on the Special page's Rentals tab (return_rental, 23b):
--
--   * charged a late fee only as a figure on the rental row: no invoice, no
--     payment on any invoice, so the money was in no report and no export;
--     and it could not be waived, reduced or discounted. Its payment method
--     defaulted to the first in the list (American Express);
--   * counted late days to today, so a return that happened earlier could not
--     be recorded as it was;
--   * put stock back the wrong way round. Ticked ("Return 1 to warehouse
--     stock") it added the unit to special_product_stock, retired since 108,
--     and real stock never came back; unticked (lost or unusable) the rental
--     trigger (trg_rental_stock_back -> return_rental_to_warehouse) put it
--     back into the warehouse anyway. A rental released from a store was
--     never put back into the store, and ticked it failed outright
--     (special_product_stock needs a warehouse). An old-style rental (RENT-,
--     create_rental and pay_rental) is the exception: pay_rental takes it
--     from special_product_stock, never from warehouse stock, so for it the
--     tick was right and the trigger, unticked, added a warehouse unit that
--     had never left;
--   * said "Returned on time — no late fee" for a late rental whose daily
--     late fee is S$0 (every active special product's, today).
--
-- THE RULES (the Owner, 6 Oct 2026, final)
--
--   1. A rental returned after its due date offers "No late fee" (the
--      default, no reason needed) or "Charge late fee".
--   2. Charge late fee: the days start at the days late and may only be
--      fewer (1 up to the days late); the daily rate is typed at the return
--      (prefilled from the rental's late_fee_per_day) and must be more than
--      S$0; an optional discount, an amount (S$) or a percentage as on
--      invoice lines, needs a reason, which is internal and never printed.
--      Total = days x rate x quantity - discount, more than S$0.
--   3. The fee is paid at the return: one payment method (not wallet credit,
--      none preselected) and an optional reference. Confirm Return records,
--      in one transaction, the return, an invoice of its own with a normal
--      INV number for the late fee only (in the rental's store, else the
--      store it was released from, else its invoice's store; staff choose one
--      for an old-style rental with none), for the rental's customer, dated
--      the return date, with one line describing the rental and the discount
--      as that line's Discount, and the payment, so the invoice is paid at
--      once. The rental keeps a link to it.
--   4. No commission of any kind on a late fee: no affiliate commission (the
--      invoice has no affiliate, explicitly), no staff commission, no
--      staff-sales credit, no affiliate qualification. It is sales revenue in
--      the reports like any receipt.
--   5. Return stays Owner/Manager only. Ticked, the unit goes back into real
--      stock where it came from (warehouse_inventory for a warehouse release,
--      store_inventory for a store release) with a stock movement, exactly
--      once, never into the retired special_product_stock; unticked (lost or
--      unusable), no stock changes. An old-style rental whose special product
--      is not a warehouse product has nowhere to go back to: its return is
--      recorded without a stock change, and the screen says so.
--      (Not the Owner's words, to be confirmed: an old-style rental of a
--      warehouse product never left warehouse stock, so it does not go back
--      into it. Ticked, it goes back into special_product_stock, where
--      pay_rental took it from and where cancel_rental puts it back, as the
--      old Return did; warehouse and store stock do not change. A lost unit
--      is never ticked: the Return refuses "lost" with the tick.)
--   6. A "Returned on" date (today by default, not in the future, not before
--      the rental started); the late days count to it.
--   8. The late-fee line is safe everywhere: no stock; it cannot be added
--      from the Invoices page; Correct Invoice neither changes nor removes
--      it; a refund and a cancellation of its invoice work as for any other.
--   (7 and 9 are the screen's: the wording, and the Rentals tab showing the
--   fee and its invoice.)
--
-- WHAT THIS DOES
--
--   * rentals gains late_fee_invoice_id (the late fee's invoice, one per
--     rental), late_fee_days (the days charged), late_fee_rate (the daily
--     rate typed) and late_fee_waived (true: returned late, "No late fee";
--     false: charged; null: on time or before 396). late_days stays the days
--     late and late_fee_total what was charged after the discount; the
--     discount itself is the invoice line's Discount (385's columns), so it
--     has one home.
--   * return_rental_with_fee(...): the Return, rules 1 to 6. Owner/Manager
--     only, granted to staff (it checks). The invoice is written straight,
--     as create_credit_purchase_invoice and create_topup_invoice write theirs,
--     and paid through invoice_record_payments_internal, the payment path
--     every invoice takes (status, paid_at, the lock, stock and commission
--     steps, all of which find nothing to do on a late fee).
--   * rental_put_back_stock(rental): rule 5's stock, for the Return and for
--     the rental trigger. A rental released by fulfil_special_doc
--     (fulfilled_at set) goes back to the store or warehouse it was released
--     from, with a movement; an old-style one (no invoice, never released)
--     back into special_product_stock, with no movement, as pay_rental took
--     it. Internal (339).
--   * invoice_is_late_fee(invoice): whether an invoice holds a late fee.
--     Internal.
--   * trg_invoice_item_late_fee_guard, before insert, update or delete on
--     invoice_items: a late-fee line is written only by the Return (which
--     names its invoice in the transaction's energia.late_fee_invoice
--     setting), alone on an invoice of its own, and is never changed or
--     removed; nothing else is added to a late-fee invoice. Every path is
--     covered, the Invoices page, a correction, Make FOC, a price override,
--     an exchange, whatever comes later.
--   * trg_rental_stock_back: puts stock back only for a return that did not
--     say whether it went back (stock_returned still null), through
--     rental_put_back_stock (where it was taken from). A return
--     that said true (already put back) or false (lost or unusable) is left
--     alone: the stock moves once, and never when unticked.
--   * correct_invoice: a correction that would rewrite the lines of a
--     late-fee invoice (its lines, discounts or service staff), or give it an
--     affiliate, is refused. The Invoices page does not offer Correct Invoice
--     on one: a wrong payment method, amount or date is corrected on the
--     payment itself (correct_invoice_payment, "Correct amount / date"), and
--     money goes back by a refund or a cancellation. The late fee itself is
--     set once, at the Return.
--   * No commission (rule 4): earn_invoice_commission and
--     invoice_affiliate_commission_preview skip a late-fee line;
--     invoice_commission_basis is 0 for a late-fee invoice (staff commission
--     at settlement and on part payments); reearn_invoice_staff_commission
--     and preview_commission_rebase_effect leave late-fee invoices out;
--     invoice_staff_sales_ledger credits them to nobody;
--     invoice_qualifying_paid counts a late-fee line as it counts a credit
--     purchase: never.
--   * report_sales_by_service_staff (Reports, "Sales by Service Staff")
--     keeps late fees in its revenue, so it still equals the headline, and
--     returns them as late_fees_not_credited: staff total + late fees not
--     credited = revenue (+ moved in - moved out), and the difference stays 0.
--   * dashboard_sales: "Items sold" leaves late-fee lines out (their quantity
--     is days, not items).
--   * return_rental_to_warehouse, no longer called by anything, is revoked
--     from staff (it was already internal in the local databases; the revoke
--     makes sure). return_rental, the old Return, is left callable here so
--     the page now live keeps working until the new one is deployed; 397
--     revokes it after that.
--
-- NOT CHANGED
--
--   * The late-fee invoice in the reports: it is revenue on its payment's
--     date like every receipt (invoice_sales_ledger reads payments), in the
--     Xero export, the payment summary and the Dashboard. Its payment is
--     dated the return date when the return is recorded afterwards, so
--     revenue and business date agree.
--   * Refunds and cancellations of a late-fee invoice: the normal guided
--     actions; the line takes no stock, so none comes back; the rental keeps
--     its link and its return. The five-day window applies as for any line
--     that is not a rental.
--   * receive_returned_rental (300): a rental cancelled with its invoice
--     while still out is received from the invoice, as before. It sets
--     stock_returned before 'returned', so the trigger leaves it alone, as it
--     did.
--   * cancel_rental, pay_rental, create_rental (the old direct rentals).
--     special_product_stock is written only by an old-style rental's ticked
--     return, as the old Return wrote it, and never for an invoice's rental.
--   * The Invoices page's Correct Invoice stays hidden on a late-fee invoice:
--     its customer, store and date are the rental's and the return's, and
--     its payments have their own correction.
--   * Rentals returned before 396 keep their late_fee_total and payment
--     method; nothing is moved onto invoices.
--   * The Excel export of invoices, which has no lines. create_invoice and
--     update_invoice_internal never write a late_fee line: an unknown kind is
--     a product to them (it needs a product and a price), and the guard
--     refuses the kind from anyone but the Return.
--   * Of the 101 functions that read line_kind, the 97 not patched here were
--     reviewed. They name the kinds they act on (stock: product, voucher,
--     promotion, premium_bundle; credit and bundles; therapy; event tickets;
--     special products and rentals; transfers' own line kinds), so a
--     late_fee line passes them by; or they show the kind or the line's name
--     as text (reports, the purchase timeline, refund and reopen previews);
--     or they treat any other kind generically and correctly (refunds, the
--     refund plan, line matching, the discount total). create_invoice and
--     update_invoice_internal take an unknown kind for a product, which needs
--     a product and a price, so they cannot write one; the guard refuses it
--     from them anyway. invoice_line_credit_purpose gives 'late_fee', which no
--     wallet credit allows, so wallet credit cannot pay a late fee either.
--     dashboard_sales and report_sales_by_service_staff do not read line_kind;
--     they are patched for the reasons above.
--
-- SAFETY
--
-- Needs 395 committed first (checked). Apart from the lock timeout, the
-- migration is one statement (a DO block), so it is atomic however it is
-- run. Every guard and anchor is checked, and every patched text built,
-- before anything is installed. md5(pg_get_functiondef) of each patched
-- function must be the production version read on 6 Oct 2026 (BEFORE), or
-- already this migration's version (AFTER), which is left alone so a re-run
-- changes nothing. A new function that exists with any other text refuses.
-- Every anchor must match exactly once. Patches are executed as CREATE OR
-- REPLACE, which keeps owner and grants. The new internal functions are
-- revoked from public, anon and authenticated and granted to service_role
-- (339); return_rental_with_fee is granted to authenticated and checks the
-- role itself. Columns, constraints, the index and the trigger are added
-- only if missing. After installing, every function must have its AFTER md5
-- and the grants are checked. No data changes: rentals already returned are
-- left as they are.
--
-- The late-fee kind is compared as text everywhere here ('late_fee' is never
-- cast to the enum when a function is created), so nothing in this file
-- depends on 395's value being usable in the same transaction.
--
-- BEFORE (production, 6 Oct 2026, md5 of pg_get_functiondef):
--   trg_rental_stock_back()                                  01c80e4d1440178f2d24978f9917541d
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)              dee0cc78f37f8444c6d13547648e7529
--   earn_invoice_commission(uuid)                            669ed0046d5783a63f82c1308222d45f
--   invoice_affiliate_commission_preview(uuid)               d66b3d40daff42712e17cd21e1d7ff88
--   invoice_commission_basis(uuid)                           7f62b00df60a79144d9aaba71c90eb6e
--   invoice_qualifying_paid(uuid)                            82ace3fd0d5d0042d7c772a5ca027f23
--   invoice_staff_sales_ledger()                             9933fe34ead6279d3bcea338d81fd105
--   reearn_invoice_staff_commission(uuid,text)               6b5f9383c2763e0a70da5f21a368b5cd
--   preview_commission_rebase_effect(date,date)              587e3d4acbe250931969265ee52ddf33
--   dashboard_sales(text,date,date,uuid)                     6afc5193c91f8792df394fa6b1e524ad
--   report_sales_by_service_staff(date,date,uuid)            6f487dfbf27cf0057b8c8719fe34ee26
--   (revoked, not changed)
--   return_rental_to_warehouse(uuid)                         2b0c4b0bbb04c032343d35653713a6ce
-- AFTER (for later guards):
--   trg_rental_stock_back()                                  a75c600cd86edc5b43fb464a5bfe34a8
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)              978805ed25f2a44a6f6c5a5b94b10b3c
--   earn_invoice_commission(uuid)                            6156b2e1ee51da5146a5a7acc16091ce
--   invoice_affiliate_commission_preview(uuid)               f42363390bc620c1b7ee35efbfed20fc
--   invoice_commission_basis(uuid)                           cfdf307e91eeb8fe4b26560d8b2c3cee
--   invoice_qualifying_paid(uuid)                            98e1682550b467c90b7390ecb3aef7dc
--   invoice_staff_sales_ledger()                             761ae09c59a171a2f25dc0867d1d55ee
--   reearn_invoice_staff_commission(uuid,text)               b83f9ca72f583fc69670a11186778019
--   preview_commission_rebase_effect(date,date)              4aa9ebaf897a1c3aa97cac944a8180e4
--   dashboard_sales(text,date,date,uuid)                     879b0e3b479420e45e86fdfabe16211e
--   report_sales_by_service_staff(date,date,uuid)            aefb014cad824706711b13f9a7720c97
--   invoice_is_late_fee(uuid)                               5d2ac1859d94733623c53bdee83dc822
--   rental_put_back_stock(uuid)                              8ca55272c76c62b295d5001b0943e85a
--   trg_invoice_item_late_fee_guard()                        94ceb0d89605f6d9f8e23c53974d6011
--   return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text)
--                                                            659a74da796b7360a3730347730e0d65
--
-- DEPLOY ORDER: 395, then 396 (the page now live keeps working: return_rental
-- is still granted), then the new page, then 397 (revokes return_rental).
--
-- Test: scripts/rentals/tests/return-late-fee.sql.

set lock_timeout = '5s';

do $mig$
declare
  -- ── New functions ──────────────────────────────────────────────────────────
  c_is_late_fee_def constant text := $def$
create or replace function public.invoice_is_late_fee(p_invoice_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  -- 396: whether the invoice holds a rental's late fee. A late-fee invoice
  -- holds nothing else (trg_invoice_item_late_fee_guard), so the whole
  -- invoice is the late fee.
  select exists (select 1 from public.invoice_items ii
                  where ii.invoice_id = p_invoice_id and ii.line_kind::text = 'late_fee')
$fn$
$def$;
  c_put_back_def constant text := $def$
create or replace function public.rental_put_back_stock(p_rental_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
-- 396: puts a returned rental back where it was taken from, once. A rental
-- released by fulfil_special_doc (fulfilled_at set) goes back into real
-- stock: the store it was released from (store_inventory) or its warehouse
-- (warehouse_inventory), with a stock movement saying so, never the retired
-- special_product_stock. An old-style rental (create_rental, pay_rental: no
-- invoice, never released) was taken from special_product_stock and never
-- from warehouse stock, so it goes back there, as cancel_rental puts it back,
-- and warehouse stock does not change. A rental already put back, one with
-- nowhere it came from, or one whose special product is not a warehouse
-- product (an old-style rental of a deleted special product) moves nothing
-- and says why.
declare r public.rentals%rowtype; v_prod uuid; v_name text;
begin
  select * into r from public.rentals where id = p_rental_id for update;
  if not found then raise exception 'Rental not found'; end if;
  if coalesce(r.stock_returned, false) then
    return jsonb_build_object('quantity', 0, 'reason', 'already_put_back',
      'message', r.rental_no || ' was already put back into stock.');
  end if;
  select sp.product_id into v_prod from public.special_products sp where sp.id = r.special_product_id;
  if v_prod is null then
    return jsonb_build_object('quantity', 0, 'reason', 'no_stock_home',
      'message', 'Its special product is not a warehouse product, so there is no stock to put it back into.');
  end if;

  if r.fulfilled_at is null and r.invoice_id is null then
    if r.warehouse_id is null then
      return jsonb_build_object('quantity', 0, 'reason', 'no_stock_home',
        'message', 'It names no warehouse, so there is no stock to put it back into.');
    end if;
    select w.name into v_name from public.warehouses w where w.id = r.warehouse_id;
    insert into public.special_product_stock (special_product_id, warehouse_id, current_qty)
    values (r.special_product_id, r.warehouse_id, r.quantity)
    on conflict (special_product_id, warehouse_id)
      do update set current_qty = public.special_product_stock.current_qty + excluded.current_qty,
                    updated_at = now();
    update public.rentals set stock_returned = true where id = r.id;
    return jsonb_build_object('quantity', r.quantity, 'location_type', 'special_stock',
      'location_id', r.warehouse_id, 'location_name', v_name, 'product_id', v_prod,
      'message', 'An old-style rental: back into the old special-product stock at ' || coalesce(v_name, 'its warehouse')
                 || ', where it was taken from. Warehouse stock does not change.');
  end if;

  if r.fulfilled_at is null then
    return jsonb_build_object('quantity', 0, 'reason', 'no_stock_home',
      'message', 'It was never released from a warehouse or a store, so there is no stock to put it back into.');
  elsif r.source_store_id is not null then
    select s.name into v_name from public.stores s where s.id = r.source_store_id;
    insert into public.store_inventory (store_id, product_id, current_qty)
    values (r.source_store_id, v_prod, r.quantity)
    on conflict (store_id, product_id)
      do update set current_qty = public.store_inventory.current_qty + excluded.current_qty,
                    updated_at = now();
    insert into public.stock_movements
      (product_id, movement_type, to_store_id, quantity, notes, created_by)
    values (v_prod, 'invoice_cancel_return'::stock_movement_type, r.source_store_id,
      r.quantity, 'Rental returned — ' || r.rental_no || ' (to store)', auth.uid());
    update public.rentals set stock_returned = true where id = r.id;
    return jsonb_build_object('quantity', r.quantity, 'location_type', 'store',
      'location_id', r.source_store_id, 'location_name', v_name, 'product_id', v_prod);
  elsif r.warehouse_id is not null then
    select w.name into v_name from public.warehouses w where w.id = r.warehouse_id;
    insert into public.warehouse_inventory (warehouse_id, product_id, current_qty)
    values (r.warehouse_id, v_prod, r.quantity)
    on conflict (warehouse_id, product_id)
      do update set current_qty = public.warehouse_inventory.current_qty + excluded.current_qty,
                    updated_at = now();
    insert into public.stock_movements
      (product_id, movement_type, to_warehouse_id, quantity, notes, created_by)
    values (v_prod, 'invoice_cancel_return'::stock_movement_type, r.warehouse_id,
      r.quantity, 'Rental returned — ' || r.rental_no, auth.uid());
    update public.rentals set stock_returned = true where id = r.id;
    return jsonb_build_object('quantity', r.quantity, 'location_type', 'warehouse',
      'location_id', r.warehouse_id, 'location_name', v_name, 'product_id', v_prod);
  end if;
  return jsonb_build_object('quantity', 0, 'reason', 'no_stock_home',
    'message', 'It was never released from a warehouse or a store, so there is no stock to put it back into.');
end $fn$
$def$;
  c_guard_def constant text := $def$
create or replace function public.trg_invoice_item_late_fee_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
-- 396: a rental's late fee is written by its Return alone
-- (return_rental_with_fee, which names the invoice it is writing in the
-- transaction's energia.late_fee_invoice setting), on an invoice of its own,
-- and is never changed or removed afterwards: not by a correction, Make FOC,
-- a price override, an exchange or any later path. Nothing else is added to
-- a late-fee invoice. Its money goes back through a refund or a cancellation.
declare v_writer text := coalesce(current_setting('energia.late_fee_invoice', true), '');
begin
  if tg_op = 'INSERT' then
    if new.line_kind::text = 'late_fee' then
      if v_writer is distinct from new.invoice_id::text then
        raise exception 'A late fee is charged at the rental''s Return on the Special page; it cannot be added to an invoice.'; end if;
      if exists (select 1 from public.invoice_items x where x.invoice_id = new.invoice_id) then
        raise exception 'A late fee is invoiced on an invoice of its own.'; end if;
    elsif public.invoice_is_late_fee(new.invoice_id) then
      raise exception 'This invoice is a rental''s late fee and holds nothing else.'; end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    if old.line_kind::text = 'late_fee' and v_writer is distinct from old.invoice_id::text then
      raise exception 'A rental''s late fee cannot be removed from its invoice. To give the money back, refund or cancel the invoice.'; end if;
    return old;
  end if;

  if (old.line_kind::text = 'late_fee' or new.line_kind::text = 'late_fee')
     and to_jsonb(new) is distinct from to_jsonb(old)
     and v_writer is distinct from old.invoice_id::text then
    raise exception 'A rental''s late fee is set at its Return and cannot be changed on its invoice. To give money back, refund or cancel the invoice.'; end if;
  if new.invoice_id is distinct from old.invoice_id and public.invoice_is_late_fee(new.invoice_id) then
    raise exception 'This invoice is a rental''s late fee and holds nothing else.'; end if;
  return new;
end $fn$
$def$;
  c_return_def constant text := $def$
create or replace function public.return_rental_with_fee(
  p_rental_id uuid,
  p_condition public.return_condition,
  p_return_stock boolean,
  p_returned_on date default null,
  p_charge_late_fee boolean default false,
  p_late_days integer default null,
  p_daily_rate numeric default null,
  p_discount_type text default null,
  p_discount_amount numeric default null,
  p_discount_percent numeric default null,
  p_discount_reason text default null,
  p_payment_method_id uuid default null,
  p_payment_reference text default null,
  p_store_id uuid default null,
  p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
-- 396: a rental's Return (the Owner, 6 Oct 2026). Records the return on the
-- date it happened (today by default), puts the unit back into real stock
-- where it came from when ticked, and, when "Charge late fee" is chosen for a
-- late return, invoices the fee on an invoice of its own and records its
-- payment, all in this one transaction. "No late fee" needs no reason.
--   p_returned_on        not in the future, not before the rental started;
--                        the late days count to it
--   p_charge_late_fee    false: no late fee (the default)
--   p_late_days          the days charged: 1 up to the days late (default all)
--   p_daily_rate         typed at the return; more than S$0
--   p_discount_type      null, 'manual' (p_discount_amount, S$) or
--                        'percentage' (p_discount_percent), with
--                        p_discount_reason; the fee after it is more than S$0
--   p_payment_method_id  how the fee is paid: active, not wallet credit
--   p_store_id           the store to invoice in, only for a rental with no
--                        store of its own (an old-style one)
declare
  r public.rentals%rowtype; m public.payment_methods%rowtype;
  v_today date := public.sg_today(); v_on date; v_charge boolean := coalesce(p_charge_late_fee, false);
  v_late integer; v_days integer; v_rate numeric; v_gross numeric; v_unit numeric;
  v_type text; v_amount numeric := 0; v_pct numeric; v_reason text; v_total numeric := 0;
  v_store uuid; v_store_name text; v_stock jsonb := jsonb_build_object('quantity', 0);
  v_back boolean := false; v_inv uuid; v_inv_no text; v_desc text; v_paid jsonb;
begin
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can record a rental''s return'; end if;
  select * into r from public.rentals where id = p_rental_id for update;
  if not found then raise exception 'Rental not found'; end if;
  if r.status::text = 'returned' then
    raise exception '% was already returned', r.rental_no; end if;
  if r.status::text not in ('paid', 'active', 'overdue') then
    raise exception 'Only a rental that is out with the customer can be returned (% is %)',
      r.rental_no, replace(r.status::text, '_', ' '); end if;
  if p_condition is null then raise exception 'Record the condition it came back in: good, damaged or lost'; end if;
  if p_return_stock is null then raise exception 'Say whether it goes back into stock'; end if;
  if p_condition::text = 'lost' and p_return_stock then
    raise exception 'A lost unit cannot go back into stock. Untick the stock box for a lost rental.'; end if;

  v_on := coalesce(p_returned_on, v_today);
  if v_on > v_today then raise exception 'The return date cannot be in the future'; end if;
  if v_on < r.start_date then
    raise exception 'The return date cannot be before the rental started (%)', to_char(r.start_date, 'DD Mon YYYY'); end if;
  v_late := greatest(0, v_on - r.expected_return_date);

  if v_charge then
    if v_late = 0 then
      raise exception '% is not late on %, so there is no late fee to charge', r.rental_no, to_char(v_on, 'DD Mon YYYY'); end if;
    v_days := coalesce(p_late_days, v_late);
    if v_days < 1 or v_days > v_late then
      raise exception 'Charge between 1 and % day(s): % was % day(s) late', v_late, r.rental_no, v_late; end if;
    v_rate := round(p_daily_rate, 2);
    if v_rate is null or v_rate <= 0 then raise exception 'Type the daily late fee (more than S$0)'; end if;
    v_unit := round(v_rate * r.quantity, 2);
    v_gross := round(v_days * v_unit, 2);
    -- The line's Discount as on invoice lines (385): an amount kept to the
    -- cent, or a percentage kept to 3 decimals and worked out to the cent;
    -- either with an internal reason.
    v_type := nullif(btrim(coalesce(p_discount_type, '')), '');
    v_reason := nullif(btrim(coalesce(p_discount_reason, '')), '');
    if v_type = 'manual' then
      v_amount := round(p_discount_amount, 2);
      if v_amount is null or v_amount <= 0 then raise exception 'Enter the discount in S$ (more than 0)'; end if;
    elsif v_type = 'percentage' then
      v_pct := round(p_discount_percent, 3);
      if v_pct is null or v_pct <= 0 or p_discount_percent > 100 then
        raise exception 'The percentage discount must be more than 0%% and at most 100%%'; end if;
      v_amount := round(v_gross * v_pct / 100, 2);
    elsif v_type is not null then
      raise exception 'Choose the discount as an amount (S$) or a percentage'; end if;
    if v_type is not null and v_reason is null then
      raise exception 'Give the reason for the discount. It stays on the invoice for staff and is never printed.'; end if;
    if v_type is null then v_reason := null; end if;
    v_total := v_gross - v_amount;
    if v_total <= 0 then
      raise exception 'The late fee after the discount must be more than S$0. Choose "No late fee" instead.'; end if;

    if p_payment_method_id is null then raise exception 'Choose how the late fee is paid'; end if;
    select * into m from public.payment_methods where id = p_payment_method_id;
    if not found or not m.is_active or m.deleted_at is not null then
      raise exception 'Choose an active payment method'; end if;
    if coalesce(m.is_wallet_credit, false) then
      raise exception 'Wallet credit cannot pay a late fee. Choose another payment method.'; end if;

    -- The rental's store, else the store it was released from, else its
    -- invoice's; an old-style rental has none, and staff choose one.
    v_store := coalesce(r.store_id, r.source_store_id,
                        (select i.store_id from public.invoices i where i.id = r.invoice_id), p_store_id);
    if v_store is null then
      raise exception 'Choose the store to invoice this late fee in: % has no store of its own', r.rental_no; end if;
    select s.name into v_store_name from public.stores s where s.id = v_store and s.deleted_at is null;
    if v_store_name is null then raise exception 'That store does not exist'; end if;
    if not public.user_has_store_access(v_store) then
      raise exception 'You do not have access to %, where this late fee is invoiced', v_store_name; end if;
  end if;

  -- Ticked: back into real stock where it came from. Unticked (lost or
  -- unusable): no stock moves. stock_returned says which either way, so the
  -- rental trigger leaves the stock alone (it acts only when that is unset).
  if p_return_stock then
    v_stock := public.rental_put_back_stock(r.id);
    v_back := coalesce((v_stock->>'quantity')::integer, 0) > 0;
  end if;

  update public.rentals
     set status = 'returned',
         -- A return recorded later is kept at midday on its own date, which
         -- reads as that date in Singapore and in UTC alike.
         returned_at = case when v_on = v_today then now()
                            else (v_on + time '12:00') at time zone 'Asia/Singapore' end,
         return_condition = p_condition,
         stock_returned = v_back,
         late_days = v_late,
         late_fee_days = case when v_charge then v_days end,
         late_fee_rate = case when v_charge then v_rate end,
         late_fee_total = v_total,
         late_fee_waived = case when v_late > 0 then not v_charge end,
         late_payment_method_id = case when v_charge then m.id end,
         late_payment_reference = case when v_charge then nullif(btrim(coalesce(p_payment_reference, '')), '') end,
         notes = case when nullif(btrim(coalesce(p_note, '')), '') is null then notes
                      else concat_ws(E'\n', notes, 'Return: ' || btrim(p_note)) end
   where id = r.id;

  if v_charge then
    v_inv_no := public.next_invoice_no();
    insert into public.invoices
      (invoice_no, store_id, customer_id, affiliate_id, affiliate_selection_explicit, created_by, status,
       subtotal, discount_total, manual_discount, total_amount, paid_amount, notes, business_date)
    values (v_inv_no, v_store, r.customer_id, null, true, auth.uid(), 'unpaid',
       v_gross, v_amount, 0, v_total, 0, 'Late return fee for rental ' || r.rental_no, v_on)
    returning id into v_inv;
    v_desc := 'Late return fee — ' || r.rental_no
           || coalesce(' (' || nullif(btrim(public.special_product_name(r.special_product_id)), '') || ')', '')
           || ': ' || v_days || case when v_days = 1 then ' day' else ' days' end
           || ' × S$' || to_char(v_rate, 'FM999999990.00')
           || case when r.quantity > 1 then ' × ' || r.quantity || ' units' else '' end;
    -- The guard lets this one line onto this one invoice.
    perform set_config('energia.late_fee_invoice', v_inv::text, true);
    insert into public.invoice_items
      (invoice_id, line_kind, product_id, quantity, unit_price, line_total,
       line_discount, line_discount_type, line_discount_percent, line_discount_reason,
       line_discount_by, line_discount_at,
       price_source, price_source_id, store_id_snapshot, original_price, item_name_snapshot)
    values (v_inv, 'late_fee', null, v_days, v_unit, v_gross,
       v_amount, v_type, v_pct, v_reason,
       case when v_type is not null then auth.uid() end, case when v_type is not null then now() end,
       'late_fee', r.id, v_store, v_unit, v_desc);
    perform set_config('energia.late_fee_invoice', '', true);
    -- Paid at once, the way every invoice is paid. A return recorded later
    -- dates the payment on the return date, as the invoice is.
    v_paid := public.invoice_record_payments_internal(v_inv, jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'payment_method_id', m.id, 'amount', v_total,
      'reference', nullif(btrim(coalesce(p_payment_reference, '')), ''),
      'payment_date', case when v_on < v_today then v_on end))));
    if v_paid->>'status' is distinct from 'paid' then
      raise exception 'The late fee could not be recorded as paid: %', v_paid; end if;
    update public.rentals set late_fee_invoice_id = v_inv where id = r.id;
  end if;

  perform public.write_audit_ex('rentals', r.id, 'rental_returned', to_jsonb(r),
    jsonb_build_object('rental_no', r.rental_no, 'returned_on', v_on, 'condition', p_condition,
      'stock_returned', v_back, 'stock', v_stock, 'late_days', v_late,
      'late_fee_waived', v_late > 0 and not v_charge,
      'late_fee', case when v_charge then jsonb_build_object('days', v_days, 'rate', v_rate,
         'gross', v_gross, 'discount_type', v_type, 'discount', v_amount, 'total', v_total,
         'invoice_id', v_inv, 'invoice_no', v_inv_no, 'payment_method_id', m.id) end),
    'rentals', nullif(btrim(coalesce(p_note, '')), ''), coalesce(v_store, r.store_id, r.source_store_id));

  return jsonb_build_object('success', true, 'rental_id', r.id, 'rental_no', r.rental_no,
    'returned_on', v_on, 'late_days', v_late, 'charged_days', v_days, 'late_fee_total', v_total,
    'invoice_id', v_inv, 'invoice_no', v_inv_no, 'store_name', v_store_name,
    'restocked_quantity', coalesce((v_stock->>'quantity')::integer, 0),
    'stock_location_type', v_stock->>'location_type', 'stock_location_name', v_stock->>'location_name',
    'stock_note', case when p_return_stock and not v_back then v_stock->>'message' end);
end $fn$
$def$;

  -- ── Anchors and their replacements ─────────────────────────────────────────
  c_stock_back_a constant text :=
       E'  if new.status::text = ''returned'' and coalesce(old.status::text,'''') <> ''returned'' then\n'
    || E'    perform public.return_rental_to_warehouse(new.id);\n'
    || E'  end if;\n';
  c_stock_back_r constant text :=
       E'  -- 396: only a return that did not say whether it went back into stock\n'
    || E'  -- (stock_returned still unset) is put back here, where it was taken from\n'
    || E'  -- (rental_put_back_stock). A return that said so (true: already put back;\n'
    || E'  -- false: lost or unusable) is left alone, so stock moves once, and never\n'
    || E'  -- when unticked.\n'
    || E'  if new.status::text = ''returned'' and coalesce(old.status::text,'''') <> ''returned''\n'
    || E'     and new.stock_returned is null then\n'
    || E'    perform public.rental_put_back_stock(new.id);\n'
    || E'  end if;\n';

  c_correct_a constant text :=
       E'  perform set_config(''invoice.manual_discount_reason'',coalesce(n.manual_discount_reason,''''),true);\n';
  c_correct_r constant text :=
       E'  -- 396: a rental''s late fee is set at its return and never rewritten here.\n'
    || E'  if public.invoice_is_late_fee(i.id) then\n'
    || E'    raise exception ''This invoice is a rental''''s late fee, set at its Return: its line cannot be corrected. Correct a wrong payment on the payment itself (Correct amount / date); to give money back, refund or cancel the invoice.''; end if;\n'
    || E'  perform set_config(''invoice.manual_discount_reason'',coalesce(n.manual_discount_reason,''''),true);\n';
  c_correct_aff_a constant text :=
       E' if n.affiliate_id is not null and not exists(select 1 from public.customer_affiliates where id=n.affiliate_id and deleted_at is null) then raise exception ''Affiliate not found''; end if;\n';
  c_correct_aff_r constant text :=
       E' if n.affiliate_id is not null and not exists(select 1 from public.customer_affiliates where id=n.affiliate_id and deleted_at is null) then raise exception ''Affiliate not found''; end if;\n'
    || E' -- 396: a rental''s late fee has no affiliate, explicitly (the Owner, 6 Oct 2026).\n'
    || E' if n.affiliate_id is not null and public.invoice_is_late_fee(i.id) then\n'
    || E'   raise exception ''This invoice is a rental''''s late fee: it has no affiliate and earns no commission.''; end if;\n';

  c_dash_a constant text :=
       E'  ''invoice_count'',v_count,''items_sold'',(select coalesce(sum(it.quantity),0) from public.invoice_items it join public.invoices i on i.id=it.invoice_id\n'
    || E'    where public.user_has_store_access(i.store_id)';
  c_dash_r constant text :=
       E'  ''invoice_count'',v_count,''items_sold'',(select coalesce(sum(it.quantity),0) from public.invoice_items it join public.invoices i on i.id=it.invoice_id\n'
    || E'    -- 396: a rental''s late fee is no item; its quantity is the days charged.\n'
    || E'    where it.line_kind::text <> ''late_fee'' and public.user_has_store_access(i.store_id)';

  c_staff_cte_a constant text :=
       E'     group by pi.staff_id, p.full_name, p.is_active\n'
    || E'  )\n'
    || E'  select jsonb_build_object(\n';
  c_staff_cte_r constant text :=
       E'     group by pi.staff_id, p.full_name, p.is_active\n'
    || E'  ), lf as (\n'
    || E'    -- 396: a rental''s late fee is revenue credited to no member of staff\n'
    || E'    -- (the Owner, 6 Oct 2026); invoice_staff_sales_ledger leaves it out.\n'
    || E'    select coalesce(sum(l.amount), 0) as amount\n'
    || E'      from public.invoice_sales_ledger() l join public.invoices i on i.id = l.invoice_id\n'
    || E'     where public.invoice_is_late_fee(l.invoice_id)\n'
    || E'       and (p_store_id is null or i.store_id = p_store_id)\n'
    || E'       and (p_from is null or l.sales_date >= p_from) and (p_to is null or l.sales_date <= p_to)\n'
    || E'  )\n'
    || E'  select jsonb_build_object(\n';
  c_staff_rev_a constant text :=
       E'    ''revenue'',      (select coalesce(sum(ev.event_amount), 0) from ev where ev.sold_in),\n';
  c_staff_rev_r constant text :=
       E'    ''revenue'',      (select coalesce(sum(ev.event_amount), 0) from ev where ev.sold_in) + (select lf.amount from lf),\n'
    || E'    ''late_fees_not_credited'', (select lf.amount from lf),\n';
  c_staff_diff_a constant text :=
       E'  return v || jsonb_build_object(''difference'',\n'
    || E'    (v->>''staff_total'')::numeric - ((v->>''revenue'')::numeric + (v->>''backfill_in'')::numeric - (v->>''backfill_out'')::numeric));\n';
  c_staff_diff_r constant text :=
       E'  return v || jsonb_build_object(''difference'',\n'
    || E'    (v->>''staff_total'')::numeric + (v->>''late_fees_not_credited'')::numeric\n'
    || E'    - ((v->>''revenue'')::numeric + (v->>''backfill_in'')::numeric - (v->>''backfill_out'')::numeric));\n';

  c_earn_a constant text :=
       E'      and ii.line_kind not in (''credit_package'',''premium_bundle'')\n'
    || E'      and coalesce(p.product_type::text, ''own'') <> ''no_commission''\n';
  c_earn_r constant text :=
       E'      and ii.line_kind not in (''credit_package'',''premium_bundle'')\n'
    || E'      and ii.line_kind::text <> ''late_fee''  -- 396: a rental''s late fee earns none\n'
    || E'      and coalesce(p.product_type::text, ''own'') <> ''no_commission''\n';

  c_basis_a constant text :=
       E'     /public.invoice_net_received(i.id))) else 0 end,2)\n'
    || E' from public.invoices i where i.id=p_invoice_id\n';
  c_basis_r constant text :=
       E'     /public.invoice_net_received(i.id))) else 0 end,2)\n'
    || E'   -- 396: a rental''s late fee earns no staff commission (the Owner, 6 Oct 2026).\n'
    || E'   * case when public.invoice_is_late_fee(i.id) then 0 else 1 end\n'
    || E' from public.invoices i where i.id=p_invoice_id\n';

  c_qual_a constant text :=
       E'       and ii.line_kind in (''credit_package'',''premium_bundle'')\n';
  c_qual_r constant text :=
       E'       -- 396: nor does a rental''s late fee (the Owner, 6 Oct 2026).\n'
    || E'       and ii.line_kind::text in (''credit_package'',''premium_bundle'',''late_fee'')\n';

  c_ledger_a constant text :=
       E'    cross join lateral public.invoice_sales_credit_split(l.invoice_id, l.amount) s\n';
  c_ledger_r constant text :=
       E'    cross join lateral public.invoice_sales_credit_split(l.invoice_id, l.amount) s\n'
    || E'   -- 396: a rental''s late fee is credited to no member of staff (the Owner, 6 Oct 2026).\n'
    || E'   where not public.invoice_is_late_fee(l.invoice_id)\n';

  c_reearn_a constant text :=
       E'  if not found then return jsonb_build_object(''skipped'', ''invoice not found''); end if;\n';
  c_reearn_r constant text :=
       E'  if not found then return jsonb_build_object(''skipped'', ''invoice not found''); end if;\n'
    || E'  -- 396: a rental''s late fee earns no staff commission (the Owner, 6 Oct 2026).\n'
    || E'  if public.invoice_is_late_fee(p_invoice_id) then\n'
    || E'    return jsonb_build_object(''skipped'', ''a rental late fee earns no staff commission''); end if;\n';

  c_rebase_a constant text :=
       E'       and i.deleted_at is null\n';
  c_rebase_r constant text :=
       E'       and i.deleted_at is null\n'
    || E'       and not public.invoice_is_late_fee(i.id)  -- 396: a rental''s late fee earns none\n';

  r record; d text; v text; n int; k int; i int; v_bad text;
  v_fns text[] := '{}'; v_defs text[] := '{}';
begin
  -- ── 395 first ─────────────────────────────────────────────────────────────
  if not exists (select 1 from pg_enum e
                  where e.enumtypid = 'public.invoice_line_kind'::regtype and e.enumlabel = 'late_fee') then
    raise exception '396: invoice_line_kind has no late_fee value. Apply 395 first.'; end if;

  -- ── Guards, anchors and patched texts: nothing is installed unless all pass ──
  for r in select * from (values
    ('trg_rental_stock_back()',
     '01c80e4d1440178f2d24978f9917541d', 'a75c600cd86edc5b43fb464a5bfe34a8', array[[c_stock_back_a, c_stock_back_r]]),
    ('correct_invoice(uuid,jsonb,jsonb,text,uuid)',
     'dee0cc78f37f8444c6d13547648e7529', '978805ed25f2a44a6f6c5a5b94b10b3c',
     array[[c_correct_a, c_correct_r], [c_correct_aff_a, c_correct_aff_r]]),
    ('earn_invoice_commission(uuid)',
     '669ed0046d5783a63f82c1308222d45f', '6156b2e1ee51da5146a5a7acc16091ce', array[[c_earn_a, c_earn_r]]),
    ('invoice_affiliate_commission_preview(uuid)',
     'd66b3d40daff42712e17cd21e1d7ff88', 'f42363390bc620c1b7ee35efbfed20fc', array[[c_earn_a, c_earn_r]]),
    ('invoice_commission_basis(uuid)',
     '7f62b00df60a79144d9aaba71c90eb6e', 'cfdf307e91eeb8fe4b26560d8b2c3cee', array[[c_basis_a, c_basis_r]]),
    ('invoice_qualifying_paid(uuid)',
     '82ace3fd0d5d0042d7c772a5ca027f23', '98e1682550b467c90b7390ecb3aef7dc', array[[c_qual_a, c_qual_r]]),
    ('invoice_staff_sales_ledger()',
     '9933fe34ead6279d3bcea338d81fd105', '761ae09c59a171a2f25dc0867d1d55ee', array[[c_ledger_a, c_ledger_r]]),
    ('reearn_invoice_staff_commission(uuid,text)',
     '6b5f9383c2763e0a70da5f21a368b5cd', 'b83f9ca72f583fc69670a11186778019', array[[c_reearn_a, c_reearn_r]]),
    ('preview_commission_rebase_effect(date,date)',
     '587e3d4acbe250931969265ee52ddf33', '4aa9ebaf897a1c3aa97cac944a8180e4', array[[c_rebase_a, c_rebase_r]]),
    ('dashboard_sales(text,date,date,uuid)',
     '6afc5193c91f8792df394fa6b1e524ad', '879b0e3b479420e45e86fdfabe16211e', array[[c_dash_a, c_dash_r]]),
    ('report_sales_by_service_staff(date,date,uuid)',
     '6f487dfbf27cf0057b8c8719fe34ee26', 'aefb014cad824706711b13f9a7720c97',
     array[[c_staff_cte_a, c_staff_cte_r], [c_staff_rev_a, c_staff_rev_r], [c_staff_diff_a, c_staff_diff_r]])
  ) x(fn, before_md5, after_md5, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '396: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '396: public.% is already this version; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '396: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    for k in 1 .. array_length(r.edits, 1) loop
      n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
      if n <> 1 then
        raise exception '396: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
      d := replace(d, r.edits[k][1], r.edits[k][2]);
    end loop;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;
  -- Revoked, not changed: the version it was read at.
  for r in select * from (values
    ('return_rental_to_warehouse(uuid)', '2b0c4b0bbb04c032343d35653713a6ce')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '396: public.% is missing or not the version read on 6 Oct 2026', r.fn; end if;
  end loop;
  for r in select * from (values
    ('invoice_is_late_fee(uuid)', '5d2ac1859d94733623c53bdee83dc822'),
    ('rental_put_back_stock(uuid)', '8ca55272c76c62b295d5001b0943e85a'),
    ('trg_invoice_item_late_fee_guard()', '94ceb0d89605f6d9f8e23c53974d6011'),
    ('return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text)',
     '659a74da796b7360a3730347730e0d65')) x(fn, after_md5)
  loop
    if to_regprocedure('public.' || r.fn) is not null
       and md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.after_md5 then
      raise exception '396: a different public.% already exists (md5 %)', r.fn,
        md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))); end if;
  end loop;

  -- ── The rental's late fee ───────────────────────────────────────────────────
  alter table public.rentals
    add column if not exists late_fee_invoice_id uuid references public.invoices(id),
    add column if not exists late_fee_days integer,
    add column if not exists late_fee_rate numeric(12,2),
    add column if not exists late_fee_waived boolean;
  alter table public.rentals drop constraint if exists rentals_late_fee_days_check;
  alter table public.rentals add constraint rentals_late_fee_days_check
    check (late_fee_days is null or late_fee_days > 0);
  alter table public.rentals drop constraint if exists rentals_late_fee_rate_check;
  alter table public.rentals add constraint rentals_late_fee_rate_check
    check (late_fee_rate is null or late_fee_rate > 0);
  create unique index if not exists rentals_late_fee_invoice_once
    on public.rentals (late_fee_invoice_id) where late_fee_invoice_id is not null;

  -- ── Install: the helpers first, then the functions that call them ─────────
  execute c_is_late_fee_def;
  execute c_put_back_def;
  execute c_guard_def;
  execute c_return_def;
  foreach v in array array['invoice_is_late_fee(uuid)', 'rental_put_back_stock(uuid)',
                           'trg_invoice_item_late_fee_guard()', 'return_rental_to_warehouse(uuid)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', v);
    execute format('grant execute on function public.%s to service_role', v);
  end loop;
  execute 'revoke all on function public.return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text) from public, anon';
  execute 'grant execute on function public.return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text) to authenticated, service_role';
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
  end loop;
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'public.invoice_items'::regclass
                    and tgname = 'invoice_item_late_fee_guard' and not tgisinternal) then
    create trigger invoice_item_late_fee_guard before insert or update or delete on public.invoice_items
      for each row execute function public.trg_invoice_item_late_fee_guard();
  end if;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  for r in select * from (values
    ('trg_rental_stock_back()', 'a75c600cd86edc5b43fb464a5bfe34a8'),
    ('correct_invoice(uuid,jsonb,jsonb,text,uuid)', '978805ed25f2a44a6f6c5a5b94b10b3c'),
    ('earn_invoice_commission(uuid)', '6156b2e1ee51da5146a5a7acc16091ce'),
    ('invoice_affiliate_commission_preview(uuid)', 'f42363390bc620c1b7ee35efbfed20fc'),
    ('invoice_commission_basis(uuid)', 'cfdf307e91eeb8fe4b26560d8b2c3cee'),
    ('invoice_qualifying_paid(uuid)', '98e1682550b467c90b7390ecb3aef7dc'),
    ('invoice_staff_sales_ledger()', '761ae09c59a171a2f25dc0867d1d55ee'),
    ('reearn_invoice_staff_commission(uuid,text)', 'b83f9ca72f583fc69670a11186778019'),
    ('preview_commission_rebase_effect(date,date)', '4aa9ebaf897a1c3aa97cac944a8180e4'),
    ('dashboard_sales(text,date,date,uuid)', '879b0e3b479420e45e86fdfabe16211e'),
    ('report_sales_by_service_staff(date,date,uuid)', 'aefb014cad824706711b13f9a7720c97'),
    ('invoice_is_late_fee(uuid)', '5d2ac1859d94733623c53bdee83dc822'),
    ('rental_put_back_stock(uuid)', '8ca55272c76c62b295d5001b0943e85a'),
    ('trg_invoice_item_late_fee_guard()', '94ceb0d89605f6d9f8e23c53974d6011'),
    ('return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text)',
     '659a74da796b7360a3730347730e0d65')) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '396: installed with md5s other than the tested ones: %', v_bad; end if;
  -- The pages still reach what they call: the new Return, and until 397 the
  -- old one (the page now live calls it); the helpers are endpoints for nobody.
  foreach v in array array['correct_invoice(uuid,jsonb,jsonb,text,uuid)',
                           'dashboard_sales(text,date,date,uuid)',
                           'report_sales_by_service_staff(date,date,uuid)',
                           'return_rental(uuid,return_condition,boolean,uuid,text,text)',
                           'return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text)'] loop
    if not has_function_privilege('authenticated', 'public.' || v, 'execute') then
      raise exception '396: public.% is not callable by staff', v; end if;
  end loop;
  foreach v in array array['invoice_is_late_fee(uuid)', 'rental_put_back_stock(uuid)',
                           'trg_invoice_item_late_fee_guard()', 'return_rental_to_warehouse(uuid)'] loop
    if has_function_privilege('anon', 'public.' || v, 'execute')
       or has_function_privilege('authenticated', 'public.' || v, 'execute') then
      raise exception '396: public.% is callable by a client role', v; end if;
  end loop;
  if has_function_privilege('anon', 'public.return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text)', 'execute') then
    raise exception '396: the Return is callable signed out'; end if;

  perform pg_notify('pgrst', 'reload schema');
end $mig$;
