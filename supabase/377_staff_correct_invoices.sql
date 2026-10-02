-- 377_staff_correct_invoices.sql
--
-- STAFF CORRECT PAID INVOICES (the owner's decisions of 2 Oct 2026, final:
-- "Direct, money edits kept back" and "Paid and part-paid, any date")
--
--   Until now only an Owner or Manager could correct an invoice once money
--   had been taken on it. A staff member who keyed the wrong quantity, the
--   wrong customer or the wrong payment method had to find one of them.
--
--   1. Who and which invoices. A staff member (role 'staff', active, not
--      deleted) corrects an invoice of a store they work at
--      (user_has_store_access, which already limits staff to their assigned
--      stores) when it is paid or part-paid, whatever its date, and not
--      deleted. Not a cancelled, refunded, refund-requested,
--      cancellation-requested or FOC-completed invoice, not an unpaid one
--      that has payment history, not a refund top-up, exchange or
--      voucher-claim document (the system makes those: a voucher claim is a
--      S$0 "paid" record of a hand-over, and adding a line to it would turn
--      it into a sale), and not while a refund or cancellation request on it
--      is waiting for approval. Those stay with an Owner or Manager.
--      staff_may_correct_invoice holds this rule, in one place.
--   2. What staff change, directly, with a reason, audited exactly as an
--      Owner's correction is (a revision with before and after, and an audit
--      row): the lines and their quantities at the catalogue price, the
--      customer (keeping or moving the benefits, as today), the referrer, the
--      service staff, the payment METHOD of a payment that stands, the
--      business date, the notes and the instalment details.
--   3. What stays with an Owner or Manager ("money edits kept back"):
--        - a unit price or any other price override (refused to staff
--          already, on unpaid invoices too). Now also a saved line's price
--          sent with ANOTHER catalogue item: picking another product (or
--          voucher, promotion, therapy, credit package, premium bundle,
--          special product, ticket option, or a rental's other rate or
--          length) while the line keeps the price it was sold at. Refused
--          with the same words as any other override: "Only an Owner or
--          Manager can override invoice prices". Sent without its old price,
--          the new item is charged at its catalogue price, as before;
--        - adding units to a saved line at a price below what the item costs
--          today, or at a special price an Owner or Manager set (owner, 2 Oct
--          2026). Lowering the quantity or removing the line is not refused,
--          nor adding units at a saved price equal to or above today's. See
--          "Adding units to a saved line" below;
--        - a payment's amount or date, removing a payment as recorded by
--          mistake, and splitting a payment (correct_invoice_payment,
--          remove_invoice_payment and split_invoice_payment keep their own
--          Owner-or-Manager check; unchanged, and guarded below);
--        - the method of a payment that does not stand: a correction's
--          reversal, a receipt or replacement a correction has reversed, a
--          payment with money refunded against it, or any payment of an
--          invoice with an older refund that names no payment (its money
--          cannot be traced to one, so it may be any of them). New refusal
--          below: "Only an Owner or Manager can change the method of a
--          reversal, or of a payment that was reversed or refunded". The page
--          never shows staff the first two; a refunded one it does show is
--          refused when saved;
--        - moving the invoice to another store, even to another store the
--          staff member works at (new refusal below);
--        - who raised the invoice (unchanged: the server allows a Manager,
--          the page offers it to the Owner);
--        - the evidence reviews (rebuild_invoice_stock_components, the
--          voucher and credit evidence). When a staff member's correction or
--          edit (paid or unpaid) is refused because one is needed, the
--          message now says to ask an Owner or Manager.
--   4. Manual discount, FOC and the discount voucher follow what staff may
--      already do when they create or edit an unpaid invoice, where none of
--      the three is refused to staff (owner, 2 Oct 2026: kept). So staff give
--      or change them in a correction too, under the same rules: a reason for
--      a new or changed manual discount, a reason for FOC, no FOC change on a
--      credit package or premium bundle, no invoice voucher beside a
--      promotion.
--
--   Adding units to a saved line (update_invoice_internal, for anyone but an
--   Owner or Manager raising a saved line's quantity at its saved price). The
--   extra units would be sold at the saved price, so, in this order:
--     a) a special price an Owner or Manager set, as the line's own record
--        shows it, is refused with "Only an Owner or Manager can add units at
--        a special price.": the line is marked price_overridden (the printed
--        "Manual Override"), or, for a product, voucher, promotion or
--        therapy-package line, its saved price is neither of the catalogue
--        prices recorded on it when it was written (member_price_snapshot /
--        non_member_price_snapshot). The schema stores no other mark for a
--        typed unit price (a price typed in Correct Invoice leaves
--        price_overridden false);
--     b) else a saved price BELOW the item's catalogue price at the
--        invoice's store, from the same price function pass 2 charges a new
--        line of that kind with (product_price_for, voucher_price_for,
--        promotion_price_for, therapy_price_for, therapy_service_price,
--        special_line_price, the package's or bundle's own price), is refused
--        with "Add the extra units as a new line at today's price, or ask an
--        Owner or Manager." (owner, 2 Oct 2026): an old lower price, or a
--        special price the line cannot show (a therapy session, special
--        product, rental or ticket records no catalogue price). A ticket's
--        price follows the invoice's business date (the owner's early-bird
--        rule, 370): its price on that date (event_ticket_price, which pass 2
--        charges through event_ticket_line_check) is its catalogue price
--        here, so the early-bird price a Manager gave a back-dated invoice is
--        not below it, and staff may add a person at it (as 370's own suite
--        expects: events.sql V4). But staff may change the business date in
--        a correction, and correct_invoice writes the new date before it
--        prices the lines. So the date that counts is one staff cannot move:
--        the ticket's catalogue price here is the HIGHEST of its price on the
--        invoice's date now, its price on the date the invoice had before
--        its first correction (the business date in the snapshot of its
--        first invoice_revisions row that holds the invoice; every change of
--        the date writes that snapshot first; no such row: the date now),
--        and the price pass 2 actually charged whoever created the invoice:
--        an Owner, Admin or Manager is charged the price of that first date;
--        anyone else is charged the price of the later of that date and the
--        day the invoice was made (370 gives staff no back-dated early
--        bird), so an early-bird date staff chose when creating the invoice
--        does not count either. Back-dating the invoice into the early bird,
--        in the same save or an earlier one, does not lower it. Pass 2 itself would price a NEW
--        person staff add without the saved price at today's price
--        (event_ticket_price_date: 370 gives staff no back-dated early bird);
--        a person added at the saved price is not a new sale back-dated into
--        the early bird;
--     c) else (a saved price equal to or above that catalogue price) the
--        units are added at the saved price.
--   False positives (a refusal where no one set a special price): under (a)
--   a line that was rewritten at its old price after the catalogue price
--   changed (any later change to that line saved with the saved price), and
--   a line the old member/non-member override marked at the catalogue price;
--   under (b) a ticket at the early-bird price on an invoice that was first
--   dated after the early bird and that an Owner or Manager later back-dated
--   into it, or that staff created back-dated and an Owner or Manager then
--   priced at the early-bird price.
--   Not covered (owner's call): staff add a NEW ticket line to an invoice an
--   Owner or Manager dated in the early bird (pass 2 charges them today's
--   price), an Owner or Manager then gives that line a special price between
--   the early-bird price and today's, and staff add people at it. Closing it
--   needs a per-line record of what pass 2 charged, or today's price for
--   staff (which 370's events.sql V4 would then have to change). Staff can still add the units as a new line at today's price,
--   or ask.
--   The rule looks at units added, not at units charged: staff who raise
--   the quantity of such a line and make the extra unit FOC in the same save
--   are refused too (it fails safe; they add the free unit as a new line, or
--   ask). A change that keeps the quantity (FOC, a line voucher, a rental's
--   return date) is not refused.
--
--   371 (a saved price stays with what was sold) was written but never
--   applied; its server rule is now part of 377. Do NOT apply 371: its guard
--   (e30b0445…) is stale, and once 377 is in, update_invoice_internal's md5
--   differs from what 371 expects. If 371 were applied first, 377's guard
--   below refuses.
--
-- WHAT THIS CHANGES
--
--   * staff_may_correct_invoice(invoice): new. True only for a staff member,
--     for an invoice described in (1).
--   * correct_invoice: lets staff through the Owner-or-Manager gate when
--     staff_may_correct_invoice says so (a reason is still required); tells
--     staff why when it does not; refuses staff a store move; and adds "ask
--     an Owner or Manager" to five refusals that need their review or action,
--     for any staff member (paid or unpaid). The messages an Owner, Manager,
--     Admin or Inventory Manager sees are unchanged, word for word.
--   * update_invoice_internal: the settled-invoice gate lets staff through on
--     the same rule. The unit price check also counts a saved price sent with
--     another catalogue item as an override, and refuses adding units at a
--     special price or below today's price, for anyone but an Owner or
--     Manager.
--   * correct_invoice_payment_methods: staff may change the method of a
--     payment that stands, on the same rule (it is reached only through
--     correct_invoice).
--   * trg_lock_invoice_payments: a settled payment's method may be changed by
--     staff on the same rule. Its amount and invoice stay locked for everyone,
--     and it still cannot be deleted.
--
-- NOT CHANGED
--
--   * Every Owner and Manager path. An Admin or Inventory Manager is still
--     refused a settled invoice.
--   * The unpaid-invoice edit path (update_invoice, and correct_invoice on a
--     draft or unpaid invoice with no payments), except the two price rules
--     in (3), which hold there for anyone but an Owner or Manager, and the
--     staff hint.
--   * correct_invoice_payment, remove_invoice_payment, split_invoice_payment,
--     can_edit_invoice, rebuild_invoice_stock_components, edit_paid_invoice
--     (service only).
--   * preview_invoice_correction: production's checks only store access, so
--     staff could already ask it what a correction would do.
--
-- SAFETY
--
-- Apart from the lock timeout set first (which installs nothing), the whole
-- migration is ONE statement (a single DO block), so it is atomic whatever
-- runs it: inside or outside a transaction, with or without psql's
-- ON_ERROR_STOP or ON_ERROR_ROLLBACK. It checks everything first and creates
-- nothing unless every check passes: the md5(prosrc) of production (2 Oct
-- 2026) for the role helpers the rule reads, for the three payment functions
-- and can_edit_invoice that now hold the money back from staff on their own,
-- for the price and payment readers the new checks rely on (event_ticket_price
-- and event_ticket_price_date, 370; invoice_payment_remaining, 175), and for
-- the four functions patched here (skipped for one already carrying
-- "377:", so a second run changes nothing), and each patch's anchors, which
-- must each match exactly once. Only then does it create the new function
-- and install the four patched ones. New function: SECURITY DEFINER, for
-- signed-in users (339). Functions only; no data changes.
--
-- AFTER (md5(prosrc) once applied, for later guards; energia_events, 2 Oct 2026):
--   correct_invoice(uuid,jsonb,jsonb,text,uuid)                    83a2d4d1445683b628daab8b0236fc4c
--   update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)
--                                                                  e4cfc6432345d996cf4b25392d0d1887
--   correct_invoice_payment_methods(uuid,jsonb,text)               ac3e9c27b52cde69b2cd9d3e2abf95c3
--   trg_lock_invoice_payments()                                    28a7b9ba2832297bdba9cad137df3462
--   staff_may_correct_invoice(uuid)                                1241e859686c3690bc3c9bec570ac611

set lock_timeout = '5s';

do $mig$
declare
  r record; v text; d text; k int; n int; p jsonb;
  v_from text[]; v_to text[]; v_patches jsonb; v_install text[] := '{}';
begin
  -- ── 0. Guards: nothing below is created unless all of these pass ─────────
  for r in select * from (values
    -- The rule below reads these as they are in production; a different
    -- version could widen it.
    ('public.is_owner_or_manager()', '7f888d6df058283917622c3ad03ddd91'),
    ('public.user_has_store_access(uuid)', '1a7f0aa1ec24e2712e96dc791d673778'),
    ('public.current_user_role()', '38683d3be39913aba404fa202d77f1c8'),
    -- Once staff pass correct_invoice's gate on a settled invoice, these alone
    -- keep a payment's amount, date, removal and split, and the unpaid edit
    -- rule, as they are.
    ('public.correct_invoice_payment(uuid,numeric,date,uuid,text,uuid)', 'fe7576245995c64e4608f0c6d1634c9f'),
    ('public.remove_invoice_payment(uuid,text,uuid)', '86aec76ea8d12fc6afb1fafd5f9f9420'),
    ('public.split_invoice_payment(uuid,jsonb,text,uuid)', '9889a8aaf2d13d3b018ca60cbe9a9d8b'),
    ('public.can_edit_invoice(uuid)', '80815a8387c1afdc94a5c3a79f252003'),
    -- The price and payment checks below read these as they are in
    -- production: a ticket's price on a date (event_ticket_price); pass 2
    -- keeping staff at today's ticket price (event_ticket_price_date); and
    -- what is left of a payment once refunds are counted
    -- (invoice_payment_remaining). A different version could widen them.
    ('public.event_ticket_price(uuid,date)', '3978a78664e462439ffe5b06c6237299'),
    ('public.event_ticket_price_date(date)', 'a208908691424af1350a7eade61b549b'),
    ('public.invoice_payment_remaining(uuid)', '7dd8d7f7361384fa039a46c74d086f95')) x(fn, want)
  loop
    if to_regprocedure(r.fn) is null then raise exception '377: % is missing', r.fn; end if;
    select md5(prosrc) into v from pg_proc where oid = to_regprocedure(r.fn);
    if v <> r.want then
      raise exception '377: % is not the version this was tested against (md5 %)', r.fn, v; end if;
  end loop;

  -- The four patches, by exact text: each anchor (from) is replaced by its
  -- replacement (to).
  v_patches := jsonb_build_array(

  -- ── 1. correct_invoice ────────────────────────────────────────────────────
  jsonb_build_object('fn', 'public.correct_invoice(uuid,jsonb,jsonb,text,uuid)',
  'md5', '47212881ad80eb0ff7e96bb2c4b8820b',
  'from', jsonb_build_array(
    $a$ v362_before jsonb; v362_therapy jsonb := '{}'::jsonb;$a$,
    $a$   if not public.is_owner_or_manager() then raise exception 'Only an Owner or Manager can correct this invoice'; end if;$a$,
    $a$ if p_header ? 'store_id' then n.store_id:=nullif(p_header->>'store_id','')::uuid; end if;$a$,
    $a$  raise exception 'Review the original issued voucher units before changing their customer, store or invoice allocation';$a$,
    $a$   raise exception 'Historical component snapshots need review before changing stock or selections; metadata can still be corrected'; end if;$a$,
    $a$   raise exception 'Resolve the consumed therapy entitlement before changing its customer, store or invoice lines'; end if;$a$,
    $a$   raise exception 'Issued credit allocation requires reconciliation before changing its line or recipient'; end if;$a$,
    $a$   raise exception 'Restore the original customer’s wallet-funded payment before changing the invoice customer'; end if;$a$
  ),
  'to', jsonb_build_array(
    $r$ v362_before jsonb; v362_therapy jsonb := '{}'::jsonb;
 -- 377: v377_staff, a staff member correcting a settled invoice they may
 -- (staff_may_correct_invoice). v377_ask, added to a refusal only an Owner or
 -- Manager can resolve, for any staff member (paid or unpaid); empty for
 -- every other role, whose messages stay word for word.
 v377_staff boolean := false;
 v377_ask text := case when public.current_user_role() = 'staff'
                       then '. Only an Owner or Manager can do this, so ask one to do it first' else '' end;$r$,
    $r$   -- 377: staff correct a paid or part-paid invoice of their own store
   -- (staff_may_correct_invoice); the money in it stays with an Owner or
   -- Manager, through the payment and price checks further down.
   v377_staff := public.staff_may_correct_invoice(i.id);
   if not public.is_owner_or_manager() and not v377_staff then
     if public.current_user_role() = 'staff' then
       raise exception 'Only an Owner or Manager can correct this invoice. Staff can correct a paid or part-paid invoice of their own store while no refund or cancellation request is waiting on it'; end if;
     raise exception 'Only an Owner or Manager can correct this invoice'; end if;$r$,
    $r$ if p_header ? 'store_id' then n.store_id:=nullif(p_header->>'store_id','')::uuid; end if;
 -- 377: a store move takes the sale, its stock and its commission to another
 -- store, so it stays with an Owner or Manager, even between two stores the
 -- staff member works at.
 if v377_staff and n.store_id is distinct from i.store_id then
   raise exception 'Only an Owner or Manager can move an invoice to another store'; end if;$r$,
    $r$  raise exception 'Review the original issued voucher units before changing their customer, store or invoice allocation%', v377_ask;$r$,
    $r$   raise exception 'Historical component snapshots need review before changing stock or selections; metadata can still be corrected%', v377_ask; end if;$r$,
    $r$   raise exception 'Resolve the consumed therapy entitlement before changing its customer, store or invoice lines%', v377_ask; end if;$r$,
    $r$   raise exception 'Issued credit allocation requires reconciliation before changing its line or recipient%', v377_ask; end if;$r$,
    $r$   raise exception 'Restore the original customer’s wallet-funded payment before changing the invoice customer%', v377_ask; end if;$r$
  )),

  -- ── 2. update_invoice_internal: the settled-invoice gate and the prices ───
  jsonb_build_object('fn', 'public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)',
  'md5', 'ef14f880a76ed5cfbb2c7929d02c665d',
  'from', jsonb_build_array(
    $a$  if p_allow_settled and not public.is_owner_or_manager() then$a$,
    $a$      if (v_original_line.id is null or v_price is distinct from v_original_line.unit_price) and not public.is_owner_or_manager() then
        raise exception 'Only an Owner or Manager can override invoice prices'; end if;$a$
  ),
  'to', jsonb_build_array(
    $r$  -- 377: or a staff member, on a paid or part-paid invoice of their own
  -- store (staff_may_correct_invoice). The price checks below still refuse
  -- them a price change.
  if p_allow_settled and not public.is_owner_or_manager()
     and not public.staff_may_correct_invoice(p_invoice_id) then$r$,
    $r$      -- 377: a saved price stays with what was sold (371's rule, never
      -- applied on its own). Sent with another catalogue item, compared per
      -- kind as pass 2 writes it, or with a rental's other rate or length,
      -- it is a price override too.
      if (v_original_line.id is null or v_price is distinct from v_original_line.unit_price
          or case v_kind
               when 'promotion' then v_original_line.promotion_id is distinct from (v_item->>'promotion_id')::uuid
               when 'voucher' then v_original_line.voucher_id is distinct from (v_item->>'voucher_id')::uuid
               when 'therapy' then
                 case when nullif(v_item->>'therapy_service_id','') is not null
                      then v_original_line.therapy_service_id is distinct from (v_item->>'therapy_service_id')::uuid
                      else v_original_line.therapy_package_id is distinct from (v_item->>'therapy_package_id')::uuid end
               when 'special_product' then v_original_line.special_product_id is distinct from (v_item->>'special_product_id')::uuid
               when 'rental' then
                 (v_original_line.special_product_id, v_original_line.rental_rate_type, coalesce(v_original_line.rental_periods, 1))
                 is distinct from ((v_item->>'special_product_id')::uuid,
                                   nullif(v_item->>'rental_rate_type', '')::public.special_rate_type,
                                   coalesce((v_item->>'rental_periods')::integer, 1))
               when 'event_ticket' then v_original_line.event_ticket_option_id is distinct from (v_ev->>'option_id')::uuid
               when 'credit_package' then v_original_line.credit_package_id is distinct from (v_item->>'credit_package_id')::uuid
               when 'premium_bundle' then v_original_line.premium_bundle_id is distinct from (v_item->>'premium_bundle_id')::uuid
               else v_original_line.product_id is distinct from (v_item->>'product_id')::uuid
             end)
         and not public.is_owner_or_manager() then
        raise exception 'Only an Owner or Manager can override invoice prices'; end if;
      -- 377: units added to a saved line at its saved price are sold at that
      -- price, so for anyone but an Owner or Manager (owner, 2 Oct 2026;
      -- lowering the quantity or removing the line is not refused):
      --   a) a special price an Owner or Manager set, as the line itself
      --      shows it (marked as a manual override, or not one of the
      --      catalogue prices recorded on a product, voucher, promotion or
      --      therapy-package line), is refused;
      --   b) else a saved price below the item's catalogue price at this
      --      store (the price function pass 2 charges a new line of that
      --      kind by) is refused: the extra units go on a new line at today's
      --      price. A ticket's price follows the invoice's business date
      --      (370, the owner's early-bird rule), so a person added at the
      --      early-bird price of an invoice dated in the early bird is not
      --      below it (370's own suite). Staff may move that date in a
      --      correction, so it is the highest of the ticket's price on the
      --      date now, on the date before the invoice's first correction
      --      (its first revision's snapshot; none yet: the date now), and on
      --      the date pass 2 charged its creator (staff: not before the day
      --      the invoice was made).
      -- A saved price equal to or above that catalogue price is allowed.
      if v_original_line.id is not null and v_qty > v_original_line.quantity
         and not public.is_owner_or_manager() then
        if coalesce(v_original_line.price_overridden, false)
           or (coalesce(v_original_line.member_price_snapshot, v_original_line.non_member_price_snapshot) is not null
               and v_original_line.unit_price is distinct from v_original_line.member_price_snapshot
               and v_original_line.unit_price is distinct from v_original_line.non_member_price_snapshot) then
          raise exception 'Only an Owner or Manager can add units at a special price.'; end if;
        if v_original_line.unit_price < (case
             when v_kind = 'promotion' then (public.promotion_price_for(v_store_id, (v_item->>'promotion_id')::uuid, v_use_member)->>'price')::numeric
             when v_kind = 'voucher' then (public.voucher_price_for(v_store_id, (v_item->>'voucher_id')::uuid, v_use_member)->>'price')::numeric
             when v_kind = 'therapy' and nullif(v_item->>'therapy_service_id','') is not null
               then public.therapy_service_price((v_item->>'therapy_service_id')::uuid, v_store_id)
             when v_kind = 'therapy' then (public.therapy_price_for(v_store_id, (v_item->>'therapy_package_id')::uuid, v_use_member)->>'price')::numeric
             when v_kind in ('special_product','rental') then round(public.special_line_price((v_item->>'special_product_id')::uuid, v_kind,
                                 nullif(v_item->>'rental_rate_type', '')::public.special_rate_type,
                                 coalesce((v_item->>'rental_periods')::integer, 1)), 2)
             when v_kind = 'event_ticket' then (select greatest(
               public.event_ticket_price(v_original_line.event_ticket_option_id, v_old.business_date),
               public.event_ticket_price(v_original_line.event_ticket_option_id, x.bd),
               public.event_ticket_price(v_original_line.event_ticket_option_id,
                 case when exists (select 1 from public.profiles pf where pf.id = x.cb and pf.role in ('owner','admin','manager'))
                      then x.bd else greatest(x.bd, (v_old.created_at at time zone 'Asia/Singapore')::date) end))
               from (select coalesce((select (r.snapshot->'invoice'->>'business_date')::date from public.invoice_revisions r
                                       where r.invoice_id = p_invoice_id and r.snapshot ? 'invoice' order by r.revision_no limit 1),
                                     v_old.business_date) as bd,
                            coalesce((select (r.snapshot->'invoice'->>'created_by')::uuid from public.invoice_revisions r
                                       where r.invoice_id = p_invoice_id and r.snapshot ? 'invoice' order by r.revision_no limit 1),
                                     v_old.created_by) as cb) x)
             when v_kind = 'credit_package' then (select customer_price from public.credit_packages where id = (v_item->>'credit_package_id')::uuid)
             when v_kind = 'premium_bundle' then (select customer_payment_amount from public.premium_bundles where id = (v_item->>'premium_bundle_id')::uuid)
             else (public.product_price_for(v_store_id, (v_item->>'product_id')::uuid, v_use_member)->>'price')::numeric
           end) then
          raise exception 'Add the extra units as a new line at today''s price, or ask an Owner or Manager.'; end if;
      end if;$r$
  )),

  -- ── 3. correct_invoice_payment_methods ────────────────────────────────────
  jsonb_build_object('fn', 'public.correct_invoice_payment_methods(uuid,jsonb,text)',
  'md5', '99f4925105b096148ba94e495f0ab1a4',
  'from', jsonb_build_array(
    $a$  if not public.is_owner_or_manager() then$a$,
    $a$    if v_pay.payment_method_id = v_new_method then continue; end if;$a$
  ),
  'to', jsonb_build_array(
    $r$  -- 377: staff too, on an invoice they may correct. Only the method: an
  -- amount, a date, a removal or a split goes through correct_invoice_payment,
  -- remove_invoice_payment or split_invoice_payment, which refuse staff.
  if not public.is_owner_or_manager() and not public.staff_may_correct_invoice(p_invoice_id) then$r$,
    $r$    if v_pay.payment_method_id = v_new_method then continue; end if;
    -- 377: and only a payment that stands: a receipt or a correction's
    -- replacement that no correction has reversed and nothing was refunded
    -- against (invoice_payment_remaining counts refunds against it and
    -- against the receipt it replaced), on an invoice with no older refund
    -- that names no payment (that money may have come from any of them). A
    -- reversal, or money already reversed or refunded, keeps the method it
    -- was recorded with, or the takings by method stop adding up.
    if not public.is_owner_or_manager()
       and (v_pay.entry_kind not in ('receipt','correction_replacement')
            or exists (select 1 from public.invoice_payments x
                        where x.corrects_payment_id = v_pay.id and x.entry_kind = 'correction_reversal')
            or public.invoice_payment_remaining(v_pay.id) < v_pay.amount
            or exists (select 1 from public.invoice_refunds f
                        where f.invoice_id = v_pay.invoice_id and f.payment_id is null)) then
      raise exception 'Only an Owner or Manager can change the method of a reversal, or of a payment that was reversed or refunded'; end if;$r$
  )),

  -- ── 4. trg_lock_invoice_payments ──────────────────────────────────────────
  jsonb_build_object('fn', 'public.trg_lock_invoice_payments()',
  'md5', '6098c9275cb0102f80aebc82dc485b0e',
  'from', jsonb_build_array(
    $a$              and not public.is_owner_or_manager())) then$a$
  ),
  'to', jsonb_build_array(
    $r$              and not public.is_owner_or_manager()
              -- 377: or a staff member's method fix on an invoice they may
              -- correct. The amount and the invoice stay locked for everyone.
              and not public.staff_may_correct_invoice(new.invoice_id))) then$r$
  )));

  -- Each patched function: present; left alone when it already carries
  -- "377:"; else the tested version, with every anchor found exactly once.
  -- The patched text is only built here; nothing is installed yet.
  for p in select x from jsonb_array_elements(v_patches) x
  loop
    if to_regprocedure(p->>'fn') is null then raise exception '377: % is missing', p->>'fn'; end if;
    d := pg_get_functiondef(to_regprocedure(p->>'fn'));
    if position('377:' in d) > 0 then raise notice '377: % already patched; left alone.', p->>'fn'; continue; end if;
    select md5(prosrc) into v from pg_proc where oid = to_regprocedure(p->>'fn');
    if v <> p->>'md5' then
      raise exception '377: % is not the version this was tested against (md5 %)', p->>'fn', v; end if;
    v_from := array(select e from jsonb_array_elements_text(p->'from') with ordinality t(e, i) order by i);
    v_to := array(select e from jsonb_array_elements_text(p->'to') with ordinality t(e, i) order by i);
    for k in 1 .. cardinality(v_from) loop
      n := (length(d) - length(replace(d, v_from[k], ''))) / length(v_from[k]);
      if n <> 1 then raise exception '377: % anchor % found % times', p->>'fn', k, n; end if;
    end loop;
    for k in 1 .. cardinality(v_from) loop
      d := replace(d, v_from[k], v_to[k]);
    end loop;
    v_install := v_install || d;
  end loop;

  -- ── 5. Every check passed: the rule, in one place ─────────────────────────
  execute $ddl$
create or replace function public.staff_may_correct_invoice(p_invoice_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $f$
  -- A staff member may correct this invoice: a paid or part-paid sale of a
  -- store they work at, with no refund or cancellation request waiting on
  -- it. Not a document the system makes (a refund top-up, an exchange or a
  -- voucher claim). Owners and Managers do not need this (false for them):
  -- their own checks are unchanged.
  select exists (
    select 1
      from public.profiles p
      join public.invoices i on i.id = p_invoice_id
     where p.id = auth.uid()
       and p.role = 'staff' and p.is_active and p.deleted_at is null
       and i.deleted_at is null
       and i.status in ('paid','partially_paid')
       and not coalesce(i.is_topup, false)
       and not coalesce(i.is_exchange, false)
       and not coalesce(i.is_voucher_claim, false)
       and public.user_has_store_access(i.store_id)
       and not exists (select 1 from public.approval_requests r
                        where r.related_record_id = i.id and r.status = 'pending'))
$f$
$ddl$;
  execute 'revoke all on function public.staff_may_correct_invoice(uuid) from public, anon';
  execute 'grant execute on function public.staff_may_correct_invoice(uuid) to authenticated, service_role';

  -- ── 6. And the four patched functions ─────────────────────────────────────
  foreach d in array v_install loop
    execute d;
  end loop;

  perform pg_notify('pgrst', 'reload schema');
end $mig$;
