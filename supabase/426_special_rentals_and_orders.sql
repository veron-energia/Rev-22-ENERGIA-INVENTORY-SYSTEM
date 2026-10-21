-- 426_special_rentals_and_orders.sql
--
-- THE SPECIAL PAGE: CHANGING A RENTAL STILL WAITING, A DESCRIPTION THAT CAN
-- BE CLEARED, AND THE OLD SALE, RENTAL AND WALLET PATHS CLOSED
--
-- WHAT WAS WRONG (audit of 9 Oct 2026, re-read on production 18 Oct 2026)
--
--   SALES-EXTRAS-7. update_pending_rental ("Change rental terms" in the
--   waiting list) refused only a rental with a warehouse. A rental released
--   from a store (source_store_id), a returned one and a cancelled one still
--   passed, so a window left open could change the fee and the quantity of a
--   rental already out or finished (reproduced: quantity 1 -> 3, fee S$500 ->
--   S$3,000). A change to the rate or the periods kept the old "Due back",
--   which is what late fees are counted from. On 18 Oct one rental is waiting
--   (RNT-2026-0009), so this is no longer only a risk.
--
--   Found in the 18 Oct review (older than this file): every change priced
--   the rental again at the list rate x periods x quantity, so a FOC line or
--   a line discount was lost. Moving only the start or "Due back" of a free
--   rental asked staff to collect the full fee (reproduced on a test copy: a
--   free month, S$0, became S$949), and adding a day to a rental sold half
--   FOC charged both machines. On 18 Oct the one rental waiting was sold
--   with neither; two rentals already returned were sold with S$40 off.
--
--   SALES-EXTRAS-16. upsert_special_product_from_product kept the old
--   description when the page sent an empty one (coalesce), so a description
--   could never be removed.
--
--   SALES-EXTRAS-12 (with THERAPY-M3). Seven functions of the old Special page
--   are still granted to every signed-in login, though no screen reaches them
--   (sales and rentals are raised on invoices now): create_special_sale,
--   pay_rental, cancel_rental and cancel_special_sale write the retired
--   special_product_stock table; create_rental and activate_rental start and
--   activate rentals of that old kind; and pay_special_with_credit spends a
--   customer's wallet credit without checking that the document exists, is
--   that customer's or that store's, or is still owed (purchase_category
--   never allows rentals or special products, so it always fails today). 406
--   limited the last to active Owners and Managers; the other six refuse
--   anyone else with their own message.
--
-- THE RULES
--
--   * The audit plan the owner approved on 9 Oct 2026: only a rental still
--     waiting for a warehouse can have its terms changed; "Due back" follows
--     the start, the rate and the periods unless a date is given; an emptied
--     description clears it; the old paths are closed, not dropped.
--   * The owner, 18 Oct 2026 (W4-B12-RENTAL-FEE, "Keep the same discount";
--     it replaces the earlier "full list rate" answer): when a waiting rental
--     sold FOC or at a discount has its quantity, rate type or number of
--     periods changed, the new fee keeps the same FOC share, or the same
--     amount or percentage off, as sold. A change of the dates alone keeps
--     the fee as sold.
--   * The owner, 10 Oct 2026 (W2-B03-RENTAL-BUTTON): the Rentals tab gets a
--     "Receive returned item" button for a rental cancelled while still with
--     the customer, using 417's receive_returned_rental. That is page work;
--     this file only checks that 417 is in (DEPLOY ORDER).
--
-- WHAT THIS DOES
--
--   1. update_pending_rental (replaced whole; grants kept):
--      * require_active_staff('{owner,manager}') first, as 406 did for the
--        waiting list it is opened from; the Owner/Manager check stays;
--      * only a rental with status awaiting_fulfilment, no warehouse and no
--        source store, whose invoice is not deleted, refunded or cancelled and
--        whose line is still on it (special_doc_invoice_problem, 393): the
--        same rentals the waiting list shows. Anything else is refused with
--        the reason in words;
--      * with no return date given, "Due back" is worked out again from the
--        start (the one given, else the rental's own) and the periods: days,
--        weeks of 7 days, calendar months or years (a month after 31 Jan is
--        28 Feb, or 29 Feb in a leap year). A date given is kept. Either way
--        it may not be before the start;
--      * how the discount was given is read from the invoice line that sold
--        the rental: its FOC (foc_quantity of quantity, or the whole line), or
--        its one line discount (a manual amount in S$, or a percentage). The
--        fee as sold is the line's value (FOC already off) less that
--        discount, never below S$0. The fee before (what the rental charges
--        now) is that fee as sold whenever the rental's terms are the line's
--        (its quantity, rate type and periods), whatever fee the rental
--        carries: create_special_docs_for_invoice records the value before a
--        line discount, and a correction of the line's price alone (a machine
--        made FOC, say) leaves the rental's fee as it was. Otherwise (the
--        terms were changed here since) it is the rental's own fee;
--      * a change of dates alone (the same quantity, rate type and periods)
--        keeps that fee and the rate, so a free or discounted rental stays as
--        it was sold (a rental raised at S$120 with S$25 off is saved at the
--        S$95 sold);
--      * a change of the quantity, the rate type or the periods takes the
--        product's rate x periods x quantity (the list fee) less the same FOC
--        share (rounded to the cent as the invoice rounds it), the same
--        percentage off (likewise), or the same S$ amount off, never below
--        S$0. The rate saved is the list rate, as before;
--      * the answer gives the fee saved, the fee it charged before
--        (invoiced_fee), the difference, the list fee, the discount kept in
--        words and the due date saved. The audit row's old data has the terms
--        and the fee on record before; its new data the terms, the fee before
--        and after (fee_was, fee_now), the list fee, the discount kept, and
--        the start and the due date before and after.
--   2. upsert_special_product_from_product (3 anchors; grants kept):
--      require_active_staff('{owner,manager}') first; a description sent
--      empty or as spaces clears it; null (left out) keeps it; a description
--      given is saved without leading or trailing spaces.
--   3. Revokes EXECUTE from public, anon and authenticated (keeps the service
--      role) on create_special_sale(uuid,uuid,uuid,integer,uuid,text,text),
--      create_rental(uuid,uuid,uuid,integer,special_rate_type,integer,date,date,text),
--      pay_rental(uuid,uuid,text), activate_rental(uuid),
--      cancel_rental(uuid,boolean,text), cancel_special_sale(uuid,boolean,text)
--      and pay_special_with_credit(text,uuid,uuid,numeric,uuid). Their text
--      is not changed. The page stops calling them in the same release.
--
-- NOT CHANGED
--
--   * Who may change a waiting rental: an active Owner or Manager, of any
--     store, as the waiting list and Release (fulfil_special_doc) already
--     allow. Store scoping is the permissions sweep's (430).
--   * The invoice itself: the fee changes on the rental only, and the page
--     still says the difference to collect or refund on the invoice. A
--     discount on the whole invoice (its manual discount or discount voucher)
--     is not the line's, so it is not carried over. The FOC share is kept as a
--     share (half of the machines free stays half), not as a number of free
--     machines.
--   * create_special_docs_for_invoice still records a rental sold with a line
--     discount at the line's value before that discount (its receipt shows
--     S$120 for S$95 paid; on 18 Oct two returned rentals in production are
--     recorded at S$200 for S$160 paid); update_pending_rental works from the
--     fee as sold whichever way it is recorded.
--   * correct_invoice still leaves the rental's fee as it was when only the
--     line's price is corrected (a machine made FOC, or a discount given,
--     afterwards; the 18 Oct review). While the rental's terms are the line's,
--     update_pending_rental reads the line instead. A rental whose terms were
--     changed here and whose line is price-corrected after that still charges
--     its own fee: bringing the rental into line belongs in correct_invoice (a
--     follow-up, not this file). On 18 Oct the one waiting rental has had no
--     correction.
--   * special_product_stock, special_credit_allocations and every past sale,
--     rental and wallet payment stay as history. return_rental and foc_rental
--     are already the service role's alone and stay so. special_stock_in, Release,
--     Return (return_rental_with_fee) and 417's receive_returned_rental are
--     not touched. Wallet credit for rentals, if ever wanted, belongs on the
--     invoice (owner question 8, THERAPY-6).
--
-- SAFETY
--
--   ONE statement (a single DO block), atomic whatever runs it, every check
--   before anything changes:
--   * update_pending_rental and upsert_special_product_from_product must be
--     the versions read on production on 18 Oct 2026 (BEFORE), or already
--     this file's (AFTER, left alone). Each upsert anchor must occur exactly
--     once, and each text built must have its tested md5 before it is
--     installed.
--   * The seven revoked functions must exist with the md5s read on 18 Oct
--     2026; their text is not changed.
--   * When something is to be installed: special_doc_invoice_problem must be
--     as read on 18 Oct 2026, and receive_returned_rental and
--     rental_awaiting_return as 417 leaves them (the page's Receive button
--     needs 417's version).
--   * Afterwards the two patched functions have their AFTER md5s and their
--     grants as before (signed-in logins, not anon); the seven are the
--     service role's alone.
--   * A self-test as a made-up Owner ("426 check", @sig.invalid, a deleted
--     customer on an invented number, a draft invoice "426-CHECK-..." whose
--     three rental lines are FOC 1 of 2 (given after the rental was raised),
--     S$7 off and 25% off) runs in a block that is always undone: it leaves
--     no row.
--   A second run changes nothing.
--
-- BEFORE (production, 18 Oct 2026, after 433; md5 of pg_get_functiondef with
-- search_path public):
--   update_pending_rental(uuid,integer,special_rate_type,integer,date,date,text)        3d3a3bf6e35570f561e7d6d5293f23a8
--   upsert_special_product_from_product(uuid,uuid,numeric,numeric,numeric,numeric,numeric,numeric,text,boolean)
--                                                                                       68078cbecf81c8e86ae1ef97f04290f8
--   revoked, text not changed:
--   create_special_sale(uuid,uuid,uuid,integer,uuid,text,text)                         96d0fd05b64c19268847563993e8863a
--   create_rental(uuid,uuid,uuid,integer,special_rate_type,integer,date,date,text)      27c79d29f99c682052b082caa821f25a
--   pay_rental(uuid,uuid,text)                                                          817e3892058a68b00388e44c5a837c91
--   activate_rental(uuid)                                                               5ff1419a0c601f5968bfadc4d6a16bb8
--   cancel_rental(uuid,boolean,text)                                                    9aa4712e981691a430828e9d9f9c372a
--   cancel_special_sale(uuid,boolean,text)                                              30db6f6a4fe49e53e878b7d6e17c7275
--   pay_special_with_credit(text,uuid,uuid,numeric,uuid)                                5496ea7f657d49629653defc905c88f2
--   relied on, not changed:
--   special_doc_invoice_problem(uuid,uuid)                                              be2b8ec5a4003a1dca34e17a82f89932
--   receive_returned_rental(uuid,uuid,text,text,uuid)   (after 417)                     362b0175b60e12c97e427b5180e01960
--   rental_awaiting_return(uuid)                                                        88ba77463d293bc77fba5e5cad3d3210
--   public function fingerprint, production 18 Oct 2026 (after 433)                     ff637c8e7adc37a4892a6bf361290c4b
--   the same with 417                                                                   a7e2aed5a97673fa51b563143a47b94a
-- AFTER (for later guards; update_pending_rental replaces the 7668e242... of
-- the version before the owner's 18 Oct answer and the ae4d2172... of the
-- version before the price-corrected line was followed, neither applied):
--   update_pending_rental(...)                                                          1022ecdafb4e1e2f21e7dc051376b028
--   upsert_special_product_from_product(...)                                            312e25496c17975e56065e968a9b6c59
--   public function fingerprint, production 18 Oct 2026 + 417 + 426                     8b64c6cfdcb6ecfa187a36f5b4f3fc05
--   in the stack's order (418, 420, 431, 429, 417, 422, 423, 424, 427, 419, 425;
--   63b8c75c9ce52b5e167bf2942fa65dac), then 426                                  5224cfea3be58850de1752083ab2e8de
--   in the planned order (418, 420, 431, 429, 417, 434, 422, 423, 424, 427, 419,
--   425; a12649fa5deaef9e19445f2b9fa638a7), then 426                             d0cf560f40c5d1f47cca01b5c52c94c4
--   (those two with the files as on 18 Oct at 14:00: 418 2a69d5a3..., 420
--   9d2d95ce..., 431 cf50e4be..., 429 86dbb0e8..., 417 c5c96d76..., 434
--   3678516a..., 422 6e689f26..., 423 a92aa00a..., 424 9915ae1d..., 427
--   37256b4f..., 419 dd1fb998..., 425 5ae0ec88...; another version of them
--   changes the fingerprints, not this file's guards)
--
-- DEPLOY ORDER: after 417 (refused without it). Then the Special page,
-- straight after, never before: its fee preview shows the fee this file
-- saves, and the old function would save the full list rate instead. (The
-- old page never reaches the revoked functions, so this file is safe under
-- it; the Receive button needs 417, and the cleared description and the new
-- "Due back" need this file.) Independent of 418-425, 427-429 and 431-434;
-- before 430, which pins update_pending_rental at
-- 1022ecdafb4e1e2f21e7dc051376b028 (re-pinned from 7668e242... and ae4d2172...).
-- Run B03's scripts/repairs/rent-2026-0002-nothing-to-receive.sql before the
-- new Special page goes live. Until it runs, the Rentals tab shows
-- RENT-2026-0002 (a duplicate that never took stock) as "Cancelled, still
-- with customer" and offers "Receive returned item" on it. Release check:
--   select public.rental_awaiting_return(id) from rentals where rental_no = 'RENT-2026-0002';
-- must return false. If the owner holds the repair back, hold the Special
-- page with it.
--
-- Test: scripts/rentals/tests/special-page-426.sql (begin ... rollback; with
-- -v mig=supabase/426_special_rentals_and_orders.sql it installs this file,
-- twice; 1b has the FOC, amount-off and percentage-off cases for quantity,
-- rate type, periods and dates alone), scripts/special/tests/special-page.test.mjs
-- (the window's fee preview) and scripts/special/tests/rental-terms.test.mjs
-- (termsFee: the same cases, with the same numbers).

set lock_timeout = '5s';

do $mig$
declare
  c_upr constant text := 'public.update_pending_rental(uuid,integer,special_rate_type,integer,date,date,text)';
  c_upr_before constant text := '3d3a3bf6e35570f561e7d6d5293f23a8';
  c_upr_after constant text := '1022ecdafb4e1e2f21e7dc051376b028';
  c_ups constant text := 'public.upsert_special_product_from_product(uuid,uuid,numeric,numeric,numeric,numeric,numeric,numeric,text,boolean)';
  c_ups_before constant text := '68078cbecf81c8e86ae1ef97f04290f8';
  c_ups_after constant text := '312e25496c17975e56065e968a9b6c59';

  -- ── update_pending_rental, as pg_get_functiondef gives it back ───────────
  c_upr_def constant text := $def$CREATE OR REPLACE FUNCTION public.update_pending_rental(p_rental_id uuid, p_quantity integer DEFAULT NULL::integer, p_rate_type special_rate_type DEFAULT NULL::special_rate_type, p_periods integer DEFAULT NULL::integer, p_start_date date DEFAULT NULL::date, p_expected_return_date date DEFAULT NULL::date, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_r public.rentals%rowtype; sp public.special_products%rowtype; v_li public.invoice_items%rowtype;
        v_rate numeric; v_qty integer; v_per integer; v_type public.special_rate_type;
        v_fee numeric; v_start date; v_due date; v_why text;
        v_lq integer; v_foc integer; v_list numeric; v_before numeric; v_how text;
begin
  perform public.require_active_staff('{owner,manager}');  -- 426: active Owners and Managers only
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can change a rental'; end if;

  select * into v_r from public.rentals where id = p_rental_id for update;
  if not found then raise exception 'Rental not found'; end if;
  -- 426: only a rental still waiting for a warehouse, as the waiting list
  -- shows it. A window left open must not change the fee or the quantity of a
  -- rental released from a store or a warehouse, returned or cancelled.
  if v_r.warehouse_id is not null or v_r.source_store_id is not null then
    raise exception 'This rental has already been released — the stock has gone out. Handle changes through the return.';
  end if;
  if v_r.status <> 'awaiting_fulfilment' then
    raise exception '% is not waiting for a warehouse any more (it is %), so its terms cannot be changed.',
      v_r.rental_no, replace(v_r.status::text, '_', ' ');
  end if;
  v_why := public.special_doc_invoice_problem(v_r.invoice_id, v_r.invoice_item_id);
  if v_why is not null then
    raise exception '% cannot be changed: %.', v_r.rental_no, v_why;
  end if;

  select * into sp from public.special_products where id = v_r.special_product_id;
  v_type := coalesce(p_rate_type, v_r.rate_type);
  v_per  := greatest(coalesce(p_periods, v_r.periods), 1);
  v_qty  := greatest(coalesce(p_quantity, v_r.quantity), 1);

  -- 426: the sale, as its invoice line has it. The line's value (its FOC
  -- already taken off) less its discount is what the rental was sold for.
  -- While the rental's terms are the line's (quantity, rate type, periods),
  -- what it charges now is what the line charges, whatever fee the rental
  -- carries: the invoice raises it at the line's value before that discount,
  -- and a correction of the line's price alone does not change it. A rental
  -- whose terms were changed here since charges its own fee.
  v_before := v_r.rental_fee;
  select * into v_li from public.invoice_items
   where id = v_r.invoice_item_id and invoice_id = v_r.invoice_id;
  if found then
    v_lq := greatest(coalesce(v_li.quantity, 1), 1);
    if (v_r.quantity, v_r.rate_type, v_r.periods)
       is not distinct from (v_lq, coalesce(v_li.rental_rate_type, 'day'),
                             greatest(coalesce(v_li.rental_periods, 1), 1)) then
      v_before := greatest(round(coalesce(v_li.line_total, 0) - coalesce(v_li.line_discount, 0), 2), 0);
    end if;
  end if;

  if v_qty = v_r.quantity and v_type = v_r.rate_type and v_per = v_r.periods then
    -- 426: a change of dates alone keeps the fee as sold (or as last
    -- changed) and the rate.
    v_fee := v_before; v_rate := v_r.rate_amount;
  else
    v_rate := case v_type
      when 'day' then sp.rate_day when 'week' then sp.rate_week
      when 'month' then sp.rate_month when 'year' then sp.rate_year end;
    if coalesce(v_rate,0) <= 0 then
      raise exception '"%" has no % rate set', sp.name, v_type; end if;
    v_list := round(v_rate * v_per * v_qty, 2);
    -- 426 (the owner, 18 Oct 2026: "Keep the same discount"): the list fee
    -- for the new terms less the same FOC share, or the same amount or
    -- percentage off, as the invoice line sold it; never below S$0.
    v_foc := case when v_li.id is null then 0
                  when coalesce(v_li.is_foc, false) then v_lq
                  else least(greatest(coalesce(v_li.foc_quantity, 0), 0), v_lq) end;
    if v_foc > 0 then
      v_fee := v_list - round(v_list * v_foc / v_lq, 2);
      v_how := case when v_foc = v_lq then 'FOC, as sold'
                    else format('the same FOC share as sold (%s of %s free)', v_foc, v_lq) end;
    elsif v_li.line_discount_type = 'percentage' and coalesce(v_li.line_discount_percent, 0) > 0 then
      v_fee := v_list - round(v_list * least(v_li.line_discount_percent, 100) / 100, 2);
      v_how := format('the same %s%% off as sold',
                      rtrim(rtrim(to_char(v_li.line_discount_percent, 'FM9990.000'), '0'), '.'));
    elsif coalesce(v_li.line_discount, 0) > 0 then
      v_fee := v_list - round(v_li.line_discount, 2);
      v_how := format('the same S$%s off as sold', to_char(round(v_li.line_discount, 2), 'FM999999990.00'));
    else
      v_fee := v_list;
    end if;
    v_fee := greatest(round(v_fee, 2), 0);
  end if;

  -- 426: with no return date given, it is worked out again from the start and
  -- the periods (a month after 31 Jan is the last day of February). A date
  -- given is kept, but never before the start.
  v_start := coalesce(p_start_date, v_r.start_date);
  v_due := coalesce(p_expected_return_date,
    (v_start + case v_type
       when 'day' then make_interval(days => v_per)
       when 'week' then make_interval(days => 7 * v_per)
       when 'month' then make_interval(months => v_per)
       else make_interval(years => v_per) end)::date);
  if v_due < v_start then
    raise exception 'The return date cannot be before the start date'; end if;

  update public.rentals set
    quantity = v_qty, rate_type = v_type, rate_amount = v_rate, periods = v_per,
    rental_fee = v_fee,
    start_date = v_start,
    expected_return_date = v_due,
    notes = coalesce(p_notes, notes)
  where id = p_rental_id;

  -- 426: the terms and the fee before (old) and after (new), in words.
  perform public.write_audit_ex('rental', p_rental_id, 'pending_rental_edited',
    jsonb_build_object('quantity', v_r.quantity, 'rate_type', v_r.rate_type, 'periods', v_r.periods,
      'rental_fee', v_r.rental_fee, 'start_date', v_r.start_date, 'expected_return_date', v_r.expected_return_date),
    jsonb_build_object('quantity', v_qty, 'rate_type', v_type, 'periods', v_per,
      'fee_was', v_before, 'fee_now', v_fee, 'list_fee', v_list, 'discount_kept', v_how,
      'start_date', v_start, 'due_was', v_r.expected_return_date, 'due_now', v_due), 'special', null, null);

  -- The fee may now differ from what was invoiced; the caller is told so it can
  -- be said plainly rather than discovered later.
  return jsonb_build_object('success', true, 'rental_fee', v_fee,
    'invoiced_fee', v_before,
    'difference', round(v_fee - coalesce(v_before,0), 2),
    'list_fee', v_list, 'discount_kept', v_how,
    'expected_return_date', v_due);
end $function$
$def$;

  -- ── upsert_special_product_from_product: each anchor becomes its patch ───
  c_ups_anchors constant text[] := array[
$a$  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can manage special products'; end if;$a$,
$a$coalesce(p_late_fee_per_day,0), p_description,$a$,
$a$      description = coalesce(p_description, description),$a$];
  c_ups_patches constant text[] := array[
$r$  perform public.require_active_staff('{owner,manager}');  -- 426: active Owners and Managers only
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can manage special products'; end if;$r$,
$r$coalesce(p_late_fee_per_day,0), nullif(btrim(p_description), ''),$r$,
$r$      -- 426: an emptied description clears it; left out (null), it stays.
      description = case when p_description is null then description
                         else nullif(btrim(p_description), '') end,$r$];

  -- ── The old Special page paths: revoked, text unchanged ─────────────────
  c_revoke constant text[][] := array[
    ['create_special_sale(uuid,uuid,uuid,integer,uuid,text,text)',                    '96d0fd05b64c19268847563993e8863a'],
    ['create_rental(uuid,uuid,uuid,integer,special_rate_type,integer,date,date,text)', '27c79d29f99c682052b082caa821f25a'],
    ['pay_rental(uuid,uuid,text)',                                                     '817e3892058a68b00388e44c5a837c91'],
    ['activate_rental(uuid)',                                                          '5ff1419a0c601f5968bfadc4d6a16bb8'],
    ['cancel_rental(uuid,boolean,text)',                                               '9aa4712e981691a430828e9d9f9c372a'],
    ['cancel_special_sale(uuid,boolean,text)',                                         '30db6f6a4fe49e53e878b7d6e17c7275'],
    ['pay_special_with_credit(text,uuid,uuid,numeric,uuid)',                           '5496ea7f657d49629653defc905c88f2']];

  -- ── Relied on when installing ───────────────────────────────────────────
  c_relied constant text[][] := array[
    ['special_doc_invoice_problem(uuid,uuid)',            'be2b8ec5a4003a1dca34e17a82f89932'],
    ['receive_returned_rental(uuid,uuid,text,text,uuid)', '362b0175b60e12c97e427b5180e01960'],
    ['rental_awaiting_return(uuid)',                      '88ba77463d293bc77fba5e5cad3d3210']];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  d text; n int; k int; v text;
  v_do_upr boolean := false; v_do_ups boolean := false; v_ups_def text;
  v_upr_acl text; v_ups_acl text;
  -- the self-test's made-up records
  v_owner uuid; v_st uuid; v_prod uuid; v_sp uuid; v_cust uuid;
  v_r1 uuid; v_r2 uuid; v_r3 uuid; v_r4 uuid; v_x jsonb; v_tag text := substr(md5(gen_random_uuid()::text), 1, 10);
  v_inv uuid; v_l1 uuid; v_l2 uuid; v_l3 uuid; v_r5 uuid; v_r6 uuid; v_r7 uuid;
begin
  -- Definitions are read and compared with public alone on the search path,
  -- as they were read on 18 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── 1. Guards: nothing changes unless all pass ──────────────────────────
  for k in 1 .. array_length(c_revoke, 1) loop
    if to_regprocedure('public.' || c_revoke[k][1]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_revoke[k][1]))) <> c_revoke[k][2] then
      raise exception '426: public.% is missing or not the version read on 18 Oct 2026. Re-read it from production and re-test before applying.', c_revoke[k][1];
    end if;
  end loop;

  if md5(c_upr_def) <> c_upr_after then
    raise exception '426: the text of % is not the tested one (md5 %)', c_upr, md5(c_upr_def); end if;
  if to_regprocedure(c_upr) is null then raise exception '426: % is missing', c_upr; end if;
  d := pg_get_functiondef(c_upr::regprocedure);
  if md5(d) = c_upr_after then
    raise notice '426: % is already this version; left alone', c_upr;
  elsif md5(d) <> c_upr_before then
    raise exception '426: % is not the version read on 18 Oct 2026 (md5 %). Re-read it from production and re-test before applying.', c_upr, md5(d);
  else
    v_do_upr := true;
  end if;

  if to_regprocedure(c_ups) is null then raise exception '426: % is missing', c_ups; end if;
  d := pg_get_functiondef(c_ups::regprocedure);
  if md5(d) = c_ups_after then
    raise notice '426: % is already this version; left alone', c_ups;
  elsif md5(d) <> c_ups_before then
    raise exception '426: % is not the version read on 18 Oct 2026 (md5 %). Re-read it from production and re-test before applying.', c_ups, md5(d);
  else
    for k in 1 .. cardinality(c_ups_anchors) loop
      n := (length(d) - length(replace(d, c_ups_anchors[k], ''))) / length(c_ups_anchors[k]);
      if n <> 1 then
        raise exception '426: anchor % of % was found % times, not once', k, c_ups, n; end if;
      d := replace(d, c_ups_anchors[k], c_ups_patches[k]);
    end loop;
    if md5(d) <> c_ups_after then
      raise exception '426: the text built for % is not the tested one (md5 %)', c_ups, md5(d); end if;
    v_ups_def := d; v_do_ups := true;
  end if;

  -- 417 must be in, and the invoice check as read, before anything is installed.
  if v_do_upr or v_do_ups then
    for k in 1 .. array_length(c_relied, 1) loop
      if to_regprocedure('public.' || c_relied[k][1]) is null
         or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[k][1]))) <> c_relied[k][2] then
        raise exception '426: public.% is missing or not as 417 leaves it (apply 417 first). Re-read it from production and re-test before applying.', c_relied[k][1];
      end if;
    end loop;
  end if;

  select coalesce(p.proacl::text, '') into v_upr_acl from pg_proc p where p.oid = c_upr::regprocedure;
  select coalesce(p.proacl::text, '') into v_ups_acl from pg_proc p where p.oid = c_ups::regprocedure;

  -- ── 2. Install ──────────────────────────────────────────────────────────
  if v_do_upr then execute c_upr_def; end if;
  if v_do_ups then execute v_ups_def; end if;
  for k in 1 .. array_length(c_revoke, 1) loop
    if has_function_privilege('anon', 'public.' || c_revoke[k][1], 'execute')
       or has_function_privilege('authenticated', 'public.' || c_revoke[k][1], 'execute')
       or not has_function_privilege('service_role', 'public.' || c_revoke[k][1], 'execute') then
      execute format('revoke all on function public.%s from public, anon, authenticated', c_revoke[k][1]);
      execute format('grant execute on function public.%s to service_role', c_revoke[k][1]);
    else
      raise notice '426: public.% is already the service role''s alone; left alone', c_revoke[k][1];
    end if;
  end loop;

  -- ── 3. Checks after installing ──────────────────────────────────────────
  if md5(pg_get_functiondef(c_upr::regprocedure)) <> c_upr_after then
    raise exception '426: % was installed with an md5 other than the tested one', c_upr; end if;
  if md5(pg_get_functiondef(c_ups::regprocedure)) <> c_ups_after then
    raise exception '426: % was installed with an md5 other than the tested one', c_ups; end if;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = c_upr::regprocedure) is distinct from v_upr_acl
     or (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = c_ups::regprocedure) is distinct from v_ups_acl then
    raise exception '426: the grants of update_pending_rental or upsert_special_product_from_product changed'; end if;
  foreach v in array array[c_upr, c_ups] loop
    if not has_function_privilege('authenticated', v, 'execute') or has_function_privilege('anon', v, 'execute') then
      raise exception '426: % is not callable by signed-in logins alone', v; end if;
  end loop;
  for k in 1 .. array_length(c_revoke, 1) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_revoke[k][1]))) <> c_revoke[k][2] then
      raise exception '426: the text of public.% changed', c_revoke[k][1]; end if;
    if has_function_privilege('anon', 'public.' || c_revoke[k][1], 'execute')
       or has_function_privilege('authenticated', 'public.' || c_revoke[k][1], 'execute')
       or not has_function_privilege('service_role', 'public.' || c_revoke[k][1], 'execute') then
      raise exception '426: public.% is not the service role''s alone', c_revoke[k][1]; end if;
  end loop;

  -- ── 4. Behaviour, as a made-up Owner, in a block that is always undone ──
  -- Made-up records only ("426 check", @sig.invalid, a deleted customer on an
  -- invented number); nothing is printed and nothing is kept.
  begin
    insert into auth.users (id, email) values (gen_random_uuid(), '426-check-' || v_tag || '@sig.invalid')
      returning id into v_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    select u.id, '426 check', u.email, 'owner', true from auth.users u where u.id = v_owner;
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    insert into public.stores (name, code, country_code) values ('426 check', '426-' || v_tag, 'SG') returning id into v_st;
    insert into public.products (name, sku, product_type) values ('426 check', '426-' || v_tag, 'own') returning id into v_prod;
    insert into public.customers (full_name, phone, deleted_at) values ('426 check', '+61491570006', now()) returning id into v_cust;

    -- A description: trimmed when given, cleared when emptied, kept when left out.
    v_sp := public.upsert_special_product_from_product(null, v_prod, 0, 10, 50, 100, 1000, 0, '  426 check note  ', true);
    if (select description from public.special_products where id = v_sp) is distinct from '426 check note' then
      raise exception '426: a description given was not saved trimmed'; end if;
    perform public.upsert_special_product_from_product(v_sp, v_prod, 0, 10, 50, 100, 1000, 0, null, true);
    if (select description from public.special_products where id = v_sp) is distinct from '426 check note' then
      raise exception '426: a description left out (null) was not kept'; end if;
    perform public.upsert_special_product_from_product(v_sp, v_prod, 0, 10, 50, 100, 1000, 0, '   ', true);
    if (select description from public.special_products where id = v_sp) is not null then
      raise exception '426: an emptied description was not cleared'; end if;

    insert into public.rentals (rental_no, special_product_id, customer_id, store_id, quantity, rate_type,
                                rate_amount, periods, rental_fee, start_date, expected_return_date, status)
    values ('426-CHECK-' || v_tag || '-1', v_sp, v_cust, v_st, 1, 'day', 10, 2, 20, date '2027-01-31', date '2027-02-02', 'awaiting_fulfilment'),
           ('426-CHECK-' || v_tag || '-2', v_sp, v_cust, v_st, 1, 'day', 10, 2, 20, date '2027-01-31', date '2027-02-02', 'returned'),
           ('426-CHECK-' || v_tag || '-3', v_sp, v_cust, v_st, 1, 'day', 10, 2, 20, date '2027-01-31', date '2027-02-02', 'cancelled');
    insert into public.rentals (rental_no, special_product_id, customer_id, store_id, source_store_id, quantity, rate_type,
                                rate_amount, periods, rental_fee, start_date, expected_return_date, status)
    values ('426-CHECK-' || v_tag || '-4', v_sp, v_cust, v_st, v_st, 1, 'day', 10, 2, 20, date '2027-01-31', date '2027-02-02', 'awaiting_fulfilment');
    select id into v_r1 from public.rentals where rental_no = '426-CHECK-' || v_tag || '-1';
    select id into v_r2 from public.rentals where rental_no = '426-CHECK-' || v_tag || '-2';
    select id into v_r3 from public.rentals where rental_no = '426-CHECK-' || v_tag || '-3';
    select id into v_r4 from public.rentals where rental_no = '426-CHECK-' || v_tag || '-4';

    -- "Due back" follows the rate and the periods when no date is given.
    v_x := public.update_pending_rental(v_r1, null, 'month', 1, null, null, null);
    if (select (expected_return_date, rental_fee) from public.rentals where id = v_r1) is distinct from (date '2027-02-28', 100.00::numeric(12,2))
       or v_x->>'expected_return_date' is distinct from '2027-02-28' then
      raise exception '426: a month from 31 Jan is not 28 Feb, or the fee is not the month rate: %', v_x; end if;
    perform public.update_pending_rental(v_r1, 2, 'day', 3, date '2027-03-01', null, null);
    if (select (start_date, expected_return_date, rental_fee) from public.rentals where id = v_r1)
       is distinct from (date '2027-03-01', date '2027-03-04', 60.00::numeric(12,2)) then
      raise exception '426: 3 days from a new start were not worked out'; end if;
    perform public.update_pending_rental(v_r1, 2, 'week', 2, null, null, null);
    if (select expected_return_date from public.rentals where id = v_r1) is distinct from date '2027-03-15' then
      raise exception '426: 2 weeks were not 14 days'; end if;
    perform public.update_pending_rental(v_r1, 1, 'day', 3, null, date '2027-03-20', null);
    if (select expected_return_date from public.rentals where id = v_r1) is distinct from date '2027-03-20' then
      raise exception '426: a return date given was not kept'; end if;
    -- A change of dates alone keeps a discounted fee and its rate.
    update public.rentals set rental_fee = 5, rate_amount = 0 where id = v_r1;
    v_x := public.update_pending_rental(v_r1, 1, 'day', 3, date '2027-03-02', date '2027-03-25', null);
    if (select (rental_fee, rate_amount, start_date, expected_return_date) from public.rentals where id = v_r1)
       is distinct from (5.00::numeric(12,2), 0.00::numeric(12,2), date '2027-03-02', date '2027-03-25')
       or (v_x->>'difference')::numeric <> 0 then
      raise exception '426: a change of dates alone priced the rental again: %', v_x; end if;
    begin
      perform public.update_pending_rental(v_r1, 1, 'day', 3, null, date '2027-02-27', null);
      raise exception '426: a return date before the start was taken';
    exception when others then
      if sqlerrm <> 'The return date cannot be before the start date' then raise; end if;
    end;
    -- Only a rental still waiting.
    foreach v in array array['2', '3', '4'] loop
      begin
        perform public.update_pending_rental(case v when '2' then v_r2 when '3' then v_r3 else v_r4 end, 3, 'day', 5, null, null, null);
        raise exception '426: rental % (not waiting) was changed', v;
      exception when others then
        if sqlerrm not like '%is not waiting for a warehouse any more%' and sqlerrm not like 'This rental has already been released%' then raise; end if;
      end;
    end loop;
    if (select count(*) from public.rentals where id in (v_r2, v_r3, v_r4) and quantity = 1 and rental_fee = 20) <> 3 then
      raise exception '426: a rental that is not waiting was changed'; end if;

    -- The same discount as sold (the owner, 18 Oct 2026), read from the
    -- invoice line: S$10 a day, S$50 a week. A draft invoice of three lines:
    -- 2 for 2 days with 1 FOC (S$20), 1 for 2 days with S$7 off (S$13), and
    -- 1 for 2 days with 25% off (S$15). Each rental has the line's terms; the
    -- first carries S$40, as if raised before the line was corrected to 1 FOC,
    -- the others the line's value before its discount, as the invoice raises it.
    insert into public.invoices (invoice_no, store_id, customer_id, created_by)
    values ('426-CHECK-' || v_tag, v_st, v_cust, v_owner) returning id into v_inv;
    insert into public.invoice_items (invoice_id, line_kind, quantity, unit_price, line_total, special_product_id,
                                      rental_rate_type, rental_periods, foc_quantity, is_foc, foc_amount, foc_reason)
    values (v_inv, 'rental', 2, 20, 20, v_sp, 'day', 2, 1, false, 20, '426 check') returning id into v_l1;
    insert into public.invoice_items (invoice_id, line_kind, quantity, unit_price, line_total, special_product_id,
                                      rental_rate_type, rental_periods, line_discount_type, line_discount, line_discount_reason)
    values (v_inv, 'rental', 1, 20, 20, v_sp, 'day', 2, 'manual', 7, '426 check') returning id into v_l2;
    insert into public.invoice_items (invoice_id, line_kind, quantity, unit_price, line_total, special_product_id,
                                      rental_rate_type, rental_periods, line_discount_type, line_discount, line_discount_percent, line_discount_reason)
    values (v_inv, 'rental', 1, 20, 20, v_sp, 'day', 2, 'percentage', 5, 25, '426 check') returning id into v_l3;
    insert into public.rentals (rental_no, special_product_id, customer_id, store_id, quantity, rate_type, rate_amount,
                                periods, rental_fee, start_date, expected_return_date, status, invoice_id, invoice_item_id)
    values ('426-CHECK-' || v_tag || '-5', v_sp, v_cust, v_st, 2, 'day', 10, 2, 40, date '2027-01-31', date '2027-02-02', 'awaiting_fulfilment', v_inv, v_l1),
           ('426-CHECK-' || v_tag || '-6', v_sp, v_cust, v_st, 1, 'day', 10, 2, 20, date '2027-01-31', date '2027-02-02', 'awaiting_fulfilment', v_inv, v_l2),
           ('426-CHECK-' || v_tag || '-7', v_sp, v_cust, v_st, 1, 'day', 10, 2, 20, date '2027-01-31', date '2027-02-02', 'awaiting_fulfilment', v_inv, v_l3);
    select id into v_r5 from public.rentals where rental_no = '426-CHECK-' || v_tag || '-5';
    select id into v_r6 from public.rentals where rental_no = '426-CHECK-' || v_tag || '-6';
    select id into v_r7 from public.rentals where rental_no = '426-CHECK-' || v_tag || '-7';
    -- 4 days instead of 2: S$80 at the list rate, half FOC as sold: S$40, S$20
    -- more than the S$20 the line charges (the rental still carries the S$40
    -- it was raised at before the line's price was corrected to 1 FOC).
    v_x := public.update_pending_rental(v_r5, 2, 'day', 4, null, null, null);
    if (v_x->>'rental_fee')::numeric <> 40 or (v_x->>'invoiced_fee')::numeric <> 20 or (v_x->>'difference')::numeric <> 20 then
      raise exception '426: the FOC share was not kept, or the fee before is not what the line charges: %', v_x; end if;
    -- 3 machines instead of 1: S$60 less the same S$7: S$53, S$40 more than the S$13 sold.
    v_x := public.update_pending_rental(v_r6, 3, 'day', 2, null, null, null);
    if (v_x->>'rental_fee')::numeric <> 53 or (v_x->>'invoiced_fee')::numeric <> 13 or (v_x->>'difference')::numeric <> 40 then
      raise exception '426: the amount off was not kept: %', v_x; end if;
    -- The dates alone: the S$15 sold. Then a week: S$50 less the same 25%: S$37.50.
    v_x := public.update_pending_rental(v_r7, 1, 'day', 2, date '2027-02-01', null, null);
    if (v_x->>'rental_fee')::numeric <> 15 or (v_x->>'difference')::numeric <> 0 then
      raise exception '426: a change of dates alone did not keep the fee as sold: %', v_x; end if;
    v_x := public.update_pending_rental(v_r7, 1, 'week', 1, null, null, null);
    if (v_x->>'rental_fee')::numeric <> 37.50 or (v_x->>'difference')::numeric <> 22.50 then
      raise exception '426: the percentage off was not kept: %', v_x; end if;

    raise exception using errcode = 'P0426', message = '426: check done, undone';
  exception when sqlstate 'P0426' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
