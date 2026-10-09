-- 408_exchanges_settle_money_and_stock_once.sql
--
-- WHAT WAS WRONG (audit of 8 Oct 2026: SALES-EXTRAS-M1, -2, -1, -4, -M2 and
-- the affiliate foreign key of the first draft's EXC-3; production read on
-- 9 Oct 2026)
--
--   1. A Wallet method paid an exchange's top-up without taking any credit
--      (SALES-EXTRAS-M1). The Exchanges page offered all five "Wallet - ..."
--      methods; the three exchange creators copied the payment into the
--      replacement invoice, which was marked paid and earned commission, and
--      no wallet was charged or even checked.
--   2. A whole-bundle exchange showed no amount due and checked only an
--      over-payment (SALES-EXTRAS-2). A payment on a swap into a cheaper
--      bundle was dropped with no record; too little on a dearer one was
--      accepted. Bundles with choice groups were valued and stocked on their
--      fixed items only; vouchers and therapy of either bundle were neither
--      taken back nor issued; a line of N bundles returned every unit's
--      components but credited and replaced one; the new bundle was not
--      checked as active, in date or sold at the store; a bundle edited after
--      the sale was valued and returned as it is now, not as it was sold.
--      (Production: no whole-bundle exchange has been done.)
--   3. Exchanges and invoice cancel / refund ignored each other
--      (SALES-EXTRAS-1). Cancelling an exchanged invoice put the returned
--      item back on the shelf a second time and left the replacement out with
--      no sale behind it; a refund could pay for goods already swapped; a
--      line already refunded could still be exchanged. The creators checked
--      the invoice before locking it, so a refund or cancellation that held
--      the lock at that moment was not seen once it committed.
--   4. A component exchange followed by a whole-bundle exchange of the same
--      line restocked the component twice and credited the full bundle
--      (SALES-EXTRAS-4): create_bundle_exchange looked only at exchanged_at,
--      which a component exchange does not set.
--   5. Paying a part-paid replacement invoice took the replacement out of
--      stock a second time (SALES-EXTRAS-M2): the exchange's own
--      exchange_replacement_out movement is not tied to the replacement
--      invoice, so the stock engine (invoice_required_stock) still counted
--      the replacement lines as owed. Production: invoice_stock_to_deduct
--      reports 1 unit owed on each of the 4 replacement invoices (all paid,
--      so nothing has been taken twice yet). Cancelling a replacement invoice
--      put nothing back either.
--   6. Every exchange of an invoice with an affiliate failed at the very end
--      with a foreign-key error (EXC-3): the creators copied
--      invoices.affiliate_id (a customer_affiliates id) into
--      product_exchanges.affiliate_id, which references the empty legacy
--      affiliates table. exchange_original_context read the same id as a
--      customer id, so the page always said "The original sale had no
--      affiliate", and "inherit" handed the exchange no affiliate.
--
-- THE RULES (the Owner approved fixing the Money & stock batch, 9 Oct 2026;
-- where a business choice was not settled this takes the conservative one
-- and the question is listed for the Owner)
--
--   1. An exchange's additional payment is never a Wallet method (a method
--      with is_wallet_credit), and a payment is never taken when nothing is
--      due (an even swap, a cheaper replacement, an FOC exchange). The page
--      offers no Wallet method; the server refuses one.
--   2. A whole-bundle exchange takes exactly the top-up, and is shown before
--      Confirm: credit, replacement value, the top-up or the unused
--      (non-refundable) value. It is done only when it can be done
--      completely, so it is refused when either bundle (or a bundle inside
--      it) has choice groups or holds anything but products (vouchers,
--      therapy, treatments, credit packages), when the line has choices or
--      issued benefits recorded, when the line holds more than one bundle,
--      when an item of it was already exchanged on its own, when the bundle
--      sold no longer holds the items the invoice recorded selling (it was
--      edited after the sale, or the sale is older than those records), when
--      the new bundle is not active, not in its dates (Singapore date) or not
--      sold at the processing store, or when a product of either bundle has
--      no price at that store. Bundle component exchange is unchanged and is
--      the way to exchange items of such bundles.
--   3. An exchange is final until the Owner decides how one is undone. So,
--      by any path (the buttons, approvals, corrections):
--      * an invoice with a completed exchange cannot be cancelled, asked to
--        be cancelled or deleted, and its exchanged lines cannot be refunded
--        or removed or changed by a correction (its other lines can still be
--        refunded or corrected);
--      * a replacement invoice cannot be cancelled, refunded (or asked to
--        be), deleted, or have its exchange lines removed or changed;
--      * when a transaction commits, for each product that came back on an
--        invoice an exchange is part of, what came back (by the invoice's
--        own returns and by its exchanges) is never more than the invoice
--        itself took out. So an exchanged item never comes back twice, and an
--        exchange line of a replacement invoice (which the exchange, not the
--        invoice, took out) never comes back on that invoice; a correction
--        that puts the invoice's stock back and takes it again (another
--        line's quantity, the store) still goes through.
--      Refuse, rather than net the money: netting would still leave the
--      replacement with the customer and its credit unfunded.
--   4. A line of an invoice that already has a refund recorded cannot be
--      exchanged (the whole invoice is refused, the conservative reading).
--      The exchange creators check this, and the rest of the eligibility,
--      again once they hold the invoice's lock.
--   5. The replacement lines of an exchange are not owed by the stock engine:
--      the exchange took them out itself. Paying a part-paid replacement
--      invoice no longer takes them out again.
--   6. The legacy product_exchanges.affiliate_id is no longer written. An
--      exchange left as "the same as the original sale" (the page's empty
--      choice, 'inherit') carries the original invoice's affiliate in
--      exchange_affiliate_id when that affiliate is not deleted and is still
--      eligible (as for one chosen by hand), and the replacement invoice
--      credits them as before. "None" stays none.
--
-- WHAT THIS DOES
--
--   New, internal (revoked from public, anon and authenticated; the service
--   role's, 339):
--   * exchange_inherited_affiliate(affiliate_id): rule 6's affiliate.
--   * exchange_assert_payments(payments, due, exact): rule 1, and for a
--     whole bundle (exact) rule 2's exact top-up. Each payment needs an
--     active, not deleted method and an amount above zero.
--   * exchange_bundle_quote(invoice, store, line, new bundle): rule 2: the
--     credit, replacement, top-up and unused value of a whole-bundle swap and
--     what goes each way, or the reason it cannot be done.
--   * exchange_invoice_hold(invoice, lines): rule 3's reason, or ''.
--   * Trigger functions trg_invoice_exchange_hold, trg_invoice_refund_
--     exchange_hold, trg_stock_return_exchange_hold and trg_invoice_item_
--     exchange_hold, and their triggers (row level):
--       invoice_exchange_hold        BEFORE update of status, deleted_at on
--                                    invoices
--       invoice_refund_exchange_hold BEFORE insert on invoice_refunds
--       stock_return_exchange_hold   a constraint trigger, AFTER insert on
--                                    stock_movements, DEFERRABLE INITIALLY
--                                    DEFERRED (checked at commit), of a stock
--                                    return on an invoice (invoice_cancel_return,
--                                    invoice_refund_return, refund_return)
--       invoice_item_exchange_hold   BEFORE delete, and update of line_kind,
--                                    product_id, promotion_id, quantity,
--                                    price_source, on invoice_items
--   New, staff's (authenticated and the service role; not signed out):
--   * exchange_bundle_preview(invoice, store, line, new bundle): the quote
--     for the page, for a signed-in profile with access to the processing
--     store and to the original invoice's store (as exchange_original_context
--     requires).
--   Patched (exact-once anchors; CREATE OR REPLACE keeps owner and grants):
--   * create_product_exchange, create_bundle_component_exchange,
--     create_bundle_exchange (internal): exchange_affiliate_id instead of the
--     legacy column (rule 6); exchange_assert_payments before the exchange is
--     written (rules 1 and 2). create_product_exchange and create_bundle_
--     component_exchange run exchange_ineligibility_reason again right after
--     the invoice is locked (rule 4). create_bundle_exchange refuses what
--     exchange_bundle_quote refuses (rule 2, SALES-EXTRAS-4), and the quote,
--     made after its locks, runs that eligibility again too.
--   * exchange_ineligibility_reason (staff): rule 4, before the window check.
--   * exchange_original_context (staff): the affiliate's name and
--     eligibility through customer_affiliates, and affiliate_inherited_id.
--   * invoice_required_stock (internal): rule 5, in both its snapshot and
--     its legacy branch (a line with no price source still counts).
--
-- NOT CHANGED
--
--   * No table, column, constraint or row. No data is repaired: the 4
--     exchanges in production (3 product, 1 bundle component; originals
--     INV-2026-0029, 0215, 0230 and 0308, all paid) are consistent, and
--     their 4 replacement invoices (SG-RETAIL-ADELPHI-EX-INV-2026-00001 to
--     00004) are paid. From this migration those 8 invoices can no longer be
--     cancelled, and the exchanged lines and the replacement invoices can no
--     longer be refunded (rule 3); invoice_stock_to_deduct reports nothing
--     owed on the 4 replacement invoices (it reported 1 unit each).
--   * The credit an exchange gives (the current store price; SALES-EXTRAS-5
--     is the Owner's question), the 5-day window, who may exchange, the
--     instalment arrangements of product and component exchanges (part of a
--     top-up may still be owed there), create_exchange_with_details,
--     set_exchange_details, create_exchange_invoice and the stock engine's
--     other functions (they read invoice_required_stock).
--   * cancel_invoice_recorded, refund_invoice_recorded,
--     resolve_invoice_action_v2, correct_invoice, record_invoice_goods_return
--     and delete_invoice are not patched: the triggers hold whatever path
--     reaches the tables. A correction that changes only an invoice's header
--     (its affiliate, notes, date) rewrites no line and is not affected. One
--     that changes another line or the store puts the invoice's stock back
--     and takes it again (restore_invoice_stock, then deduct_invoice_stock);
--     that passes, because the stock check is made on the result at commit.
--     One that rewrites an exchanged line or a replacement invoice's exchange
--     line with another kind, product, bundle, quantity or price source is
--     refused.
--
-- SAFETY
--
-- Apart from the lock timeout, the migration is one statement (a DO block),
-- so it is atomic however it is run. Every guard and anchor is checked, and
-- every patched text built, before anything is installed. md5(pg_get_
-- functiondef) of each patched function must be the production version read
-- on 9 Oct 2026 (BEFORE), or already this migration's version (AFTER), which
-- is left alone so a re-run changes nothing. The functions relied on but not
-- changed must be the versions read on 9 Oct 2026. Each new function must be
-- missing or already this version, and each trigger missing or already this
-- one. The columns and enum labels the triggers read must exist. Every
-- anchor must match exactly once. No overload is added (another function of
-- any of these names refuses). The definitions are read and compared with
-- the search path set to public. After installing, every function must have
-- its AFTER md5, the patched ones the grants they had, the internal ones no
-- client role, the preview staff's and not signed out's, and the four
-- triggers must be on their tables as tested and enabled (the stock one
-- deferred to commit). No data changes. The stock check meets the 4
-- production exchanges as consistent (each original sold 1 and its exchange
-- took 1 back; nothing was returned on them).
--
-- BEFORE (production, 9 Oct 2026 after 406 and 407, md5 of pg_get_functiondef;
-- 406 added its staff check to exchange_ineligibility_reason,
-- bundle_line_components and promotion_original_total, so their md5s here
-- are 406's AFTER ones; the preview's first statement is 406's check):
--   create_product_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text,boolean,uuid,text)         2da9188664a5f359f1b0c5cbb7a4fa24
--   create_bundle_component_exchange(uuid,uuid,uuid,uuid,integer,jsonb,jsonb,text,text)      169cd5dbd41f29458bbfeec7d4a31438
--   create_bundle_exchange(uuid,uuid,uuid,uuid,jsonb,text,text)                              6c60d8d1381ca569c77dcfac925f62a9
--   exchange_ineligibility_reason(uuid)                                                      c6bebabc448b888a525ef895d5551859
--   exchange_original_context(uuid)                                                          dd77922b013ef7cd455d38ba3d604469
--   invoice_required_stock(uuid)                                                             83bb2e1f6f8d6cb5c9287a29b2df8cf8
--   (new, missing) exchange_inherited_affiliate, exchange_assert_payments,
--   exchange_bundle_quote, exchange_bundle_preview, exchange_invoice_hold and
--   the four trigger functions
--   (relied on, not changed)
--   create_exchange_with_details(text,jsonb)                                                 b804b14bd80fff3e813d801eb789e83d
--   set_exchange_details(uuid,jsonb,jsonb,uuid,date,text)                                    352b1277be6e3ef60dda4cce80949aff
--   create_exchange_invoice(uuid)                                                            d30f8a2740154353e9f65e2bb64963fa
--   trg_exchange_invoice()                                                                   f4a84ead2fd5fa51d2e50d70da206e38
--   bundle_line_components(uuid)                                                             93ebc0e25991428c5e94a71879bbef41
--   promotion_original_total(uuid,uuid)                                                      2480074e2b77e313b052cc225493087c
--   promotion_stock_items(uuid,integer)                                                      82dd6bdac5566fce0b75470eb45444d1
--   is_eligible_affiliate(uuid)                                                              2dfbe1cee8c2be5b5e14a0d19f0553c4
--   invoice_required_stock_legacy(uuid)                                                      2e0bc2497901c2690a74205bdd3a0a5f
--   invoice_stock_to_deduct(uuid)                                                            6356494ccb8545d46c56b788f8f85f54
--   deduct_invoice_stock(uuid,text)                                                          32183fe9e7c15ed0b11307c48289831a
--   restore_invoice_stock(uuid,text)                                                         092316c3af22361f80d186e38fe49bf3
--   record_invoice_stock_return(uuid,jsonb,text,uuid)                                        6b125cb5df1eb103781662bef41e9417
--   require_active_staff(text[])                                                             877b3aa74cea559881979bb161c450e2
--   user_has_store_access(uuid)                                                              8c82c6bcb64f496c5a05a2b8dafa95f8
--   sg_today()                                                                               1c1289f18e24d8370e9a6364c9c06fca
-- AFTER (for later guards):
--   create_product_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text,boolean,uuid,text)         74be7ea5da53738cbc81db4e69ed8362
--   create_bundle_component_exchange(uuid,uuid,uuid,uuid,integer,jsonb,jsonb,text,text)      35af27479da6083ce5297b4a86e7d8cb
--   create_bundle_exchange(uuid,uuid,uuid,uuid,jsonb,text,text)                              ef9775bc5650a8e0da377af9b9fdd18f
--   exchange_ineligibility_reason(uuid)                                                      869985df7601d401df40f44c40dd2d6e
--   exchange_original_context(uuid)                                                          45cfb42ee4c91a983e3cc546f4a655b3
--   invoice_required_stock(uuid)                                                             c91dc1eb4f2b7b465de5fe4a8fb2ca0c
--   exchange_inherited_affiliate(uuid)                                                       c08af4b9c6b1afd98ae5bb9f0628a81a
--   exchange_assert_payments(jsonb,numeric,boolean)                                          d6fd63cf456a5f1557405e70a1e81440
--   exchange_bundle_quote(uuid,uuid,uuid,uuid)                                               cf07451f61cc45b1cef2bd8e31141330
--   exchange_bundle_preview(uuid,uuid,uuid,uuid)                                             c09fce506c8b92c321e8cf0f589691ff
--   exchange_invoice_hold(uuid,uuid[])                                                       d55f4696593447039aa45eeeae9b66d7
--   trg_invoice_exchange_hold()                                                              a94932825d1a9c4b6cd322bf355633bc
--   trg_invoice_refund_exchange_hold()                                                       2a6169a4f683a1c6217381b792dea472
--   trg_stock_return_exchange_hold()                                                         6f9af8dd208b7203565ed1f5f90d781a
--   trg_invoice_item_exchange_hold()                                                         41b69477b351c47a8070f25b61a8285f
--
-- DEPLOY ORDER: after 406-407 (the staff guard); this, then the page. The
-- page live now keeps working against this: it never sends a payment when
-- nothing is due in product or component mode, and in bundle mode a payment
-- that is not exactly the top-up is now refused with the reason (it was
-- dropped or accepted short); the Wallet methods it still lists are refused
-- by name. The new page against a database without this cannot preview a
-- whole-bundle swap (the call fails, and the page says so and refuses
-- Confirm in bundle mode).
--
-- Test: scripts/exchanges/tests/money-and-stock.sql, with attribution.sql,
-- commission.sql and instalments.sql (npm run test:exchanges); the page and its
-- rules: scripts/exchanges/tests/exchanges-page.test.mjs and rules.test.mjs
-- (npm run test:exchanges:page).

set lock_timeout = '5s';

do $mig$
declare
  -- ── New functions ──────────────────────────────────────────────────────────
  c_inherit_def constant text := $def$
create or replace function public.exchange_inherited_affiliate(p_affiliate_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $fn$
  -- 408: the affiliate an exchange carries over from its original sale when
  -- nobody chose one ('inherit'): the invoice's own customer_affiliates row,
  -- when it is not deleted and that affiliate is still eligible, as
  -- set_exchange_details requires of one chosen by hand; otherwise none.
  select ca.id
    from public.customer_affiliates ca
   where ca.id = p_affiliate_id
     and ca.deleted_at is null
     and public.is_eligible_affiliate(ca.customer_id)
$fn$;
$def$;

  c_pay_def constant text := $def$
create or replace function public.exchange_assert_payments(p_payments jsonb, p_due numeric, p_exact boolean)
returns void
language plpgsql
stable
security definer
set search_path = public
as $fn$
-- 408: the money an exchange takes now, checked against what is due. Never a
-- Wallet method: an exchange copies its payments into the replacement invoice
-- and takes no credit, so a wallet payment marked the invoice paid with
-- nothing taken. Never a payment when nothing is due: the creators drop it
-- without a record. Never more than is due, and for a whole bundle (p_exact)
-- exactly what is due.
declare
  x jsonb; m public.payment_methods%rowtype; v_amount numeric; v_sum numeric := 0;
  v_due numeric := round(greatest(coalesce(p_due, 0), 0), 2);
begin
  if p_payments is not null and jsonb_typeof(p_payments) <> 'array' then
    raise exception 'The exchange''s payments must be a list'; end if;
  for x in select * from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) loop
    v_amount := round((x->>'amount')::numeric, 2);
    if v_amount is null or v_amount <= 0 then
      raise exception 'Each payment on an exchange needs an amount above zero'; end if;
    select * into m from public.payment_methods where id = nullif(x->>'payment_method_id', '')::uuid;
    if not found or m.deleted_at is not null or not m.is_active then
      raise exception 'Choose an active payment method for each payment on an exchange'; end if;
    if coalesce(m.is_wallet_credit, false) then
      raise exception '"%" is wallet credit, which cannot pay an exchange: the exchange would record it as paid without taking any credit. Take the payment with another method.', m.name; end if;
    v_sum := v_sum + v_amount;
  end loop;
  if v_due = 0 and v_sum > 0 then
    raise exception 'Nothing is due on this exchange, so no payment can be taken (S$% was entered). Remove the payment.',
      to_char(v_sum, 'FM9999999990.00'); end if;
  if v_sum > v_due then
    raise exception 'Top-up payment (S$%) is more than the amount due (S$%)',
      to_char(v_sum, 'FM9999999990.00'), to_char(v_due, 'FM9999999990.00'); end if;
  if coalesce(p_exact, false) and v_sum <> v_due then
    raise exception 'This exchange needs exactly S$% paid now: S$% was entered.',
      to_char(v_due, 'FM9999999990.00'), to_char(v_sum, 'FM9999999990.00'); end if;
end $fn$;
$def$;

  c_quote_def constant text := $def$
create or replace function public.exchange_bundle_quote(p_original_invoice_id uuid, p_processing_store_id uuid,
  p_original_invoice_item_id uuid, p_new_promotion_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
-- 408: what a whole-bundle exchange of one invoice line for another bundle
-- would credit and charge, and what goes each way, or the reason it cannot be
-- done ('problem'). create_bundle_exchange refuses whatever this refuses, and
-- the Exchanges page shows it before Confirm (exchange_bundle_preview), so the
-- two never disagree. It is done only when it can be done completely: the
-- exchange returns and hands over the bundles' products and nothing else.
declare
  v_reason text; it public.invoice_items%rowtype; v_new public.promotions%rowtype;
  v_pid uuid; v_label text; v_name text; v_nos text; v_credit numeric; v_repl numeric;
  v_topup numeric; v_have integer; r record;
begin
  v_reason := public.exchange_ineligibility_reason(p_original_invoice_id);
  if v_reason <> '' then return jsonb_build_object('problem', v_reason); end if;
  select * into it from public.invoice_items
   where id = p_original_invoice_item_id and invoice_id = p_original_invoice_id;
  if not found then
    return jsonb_build_object('problem', 'Bundle line not found on the original invoice'); end if;
  if it.line_kind <> 'promotion' or it.promotion_id is null then
    return jsonb_build_object('problem', 'That line is not a bundle'); end if;
  if it.exchanged_at is not null then
    return jsonb_build_object('problem', 'This bundle has already been exchanged'); end if;
  if jsonb_typeof(it.component_exchanged) = 'array' and jsonb_array_length(it.component_exchanged) > 0 then
    select string_agg(distinct e.exchange_no, ', ' order by e.exchange_no) into v_nos
      from jsonb_array_elements(it.component_exchanged) c
      join public.product_exchanges e on e.id = nullif(c->>'exchange_id', '')::uuid;
    return jsonb_build_object('problem', format(
      'An item of this bundle was already exchanged on its own (%s), so the whole bundle can no longer be exchanged. Exchange its other items with Bundle component instead.',
      coalesce(v_nos, 'a component exchange'))); end if;
  if it.quantity <> 1 then
    return jsonb_build_object('problem', format(
      'This line holds %s bundles. A whole-bundle exchange swaps exactly one bundle, so it cannot be used on this line. Exchange its items with Bundle component instead.',
      it.quantity)); end if;
  if exists (select 1 from public.invoice_promotion_selections s where s.invoice_item_id = it.id) then
    return jsonb_build_object('problem',
      'Items of this bundle were chosen at the till. A whole-bundle exchange cannot take back or hand over chosen items yet; use Bundle component.'); end if;
  if it.credit_issued_at is not null
     or exists (select 1 from public.invoice_benefit_values b where b.invoice_item_id = it.id)
     or exists (select 1 from public.purchased_therapy_entitlements t where t.invoice_item_id = it.id) then
    return jsonb_build_object('problem',
      'Vouchers, credit or therapy were issued with this bundle. A whole-bundle exchange cannot take them back yet.'); end if;

  select * into v_new from public.promotions where id = p_new_promotion_id and deleted_at is null;
  if not found then return jsonb_build_object('problem', 'Replacement bundle not found'); end if;
  if not v_new.is_active then
    return jsonb_build_object('problem', format('Bundle "%s" is not active', v_new.name)); end if;
  if v_new.start_date is not null and public.sg_today() < v_new.start_date then
    return jsonb_build_object('problem', format('Bundle "%s" has not started yet', v_new.name)); end if;
  if v_new.end_date is not null and public.sg_today() > v_new.end_date then
    return jsonb_build_object('problem', format('Bundle "%s" has ended', v_new.name)); end if;
  if not exists (select 1 from public.promotion_store_prices sp
                  where sp.promotion_id = v_new.id and sp.store_id = p_processing_store_id
                    and sp.deleted_at is null and sp.available_at_store) then
    return jsonb_build_object('problem', format('Bundle "%s" is not sold at this store', v_new.name)); end if;

  -- Both bundles, with every bundle inside them: products only, no choices.
  foreach v_pid in array array[it.promotion_id, v_new.id] loop
    select name into v_label from public.promotions where id = v_pid;
    if exists (
      with recursive t(pid, depth) as (
        select v_pid, 0
        union all
        select pi.child_promotion_id, t.depth + 1 from public.promotion_items pi join t on pi.promotion_id = t.pid
         where pi.item_type::text = 'promotion' and pi.child_promotion_id is not null and t.depth < 10)
      select 1 from t join public.promotion_choice_groups g on g.promotion_id = t.pid) then
      return jsonb_build_object('problem', format(
        'Bundle "%s" has items chosen at the till. A whole-bundle exchange cannot take back or hand over chosen items yet; use Bundle component.',
        v_label)); end if;
    if exists (
      with recursive t(pid, depth) as (
        select v_pid, 0
        union all
        select pi.child_promotion_id, t.depth + 1 from public.promotion_items pi join t on pi.promotion_id = t.pid
         where pi.item_type::text = 'promotion' and pi.child_promotion_id is not null and t.depth < 10)
      select 1 from t join public.promotion_items pi on pi.promotion_id = t.pid
       where pi.item_type::text not in ('product', 'promotion')) then
      return jsonb_build_object('problem', format(
        'Bundle "%s" includes vouchers, therapy or other benefits. A whole-bundle exchange swaps bundles of products only, because those cannot be taken back or issued here yet.',
        v_label)); end if;
    if not exists (select 1 from public.promotion_stock_items(v_pid, 1) s where s.kind = 'product') then
      return jsonb_build_object('problem', format('Bundle "%s" holds no products, so it cannot be exchanged as a whole', v_label)); end if;
    select p.name into v_name
      from public.promotion_stock_items(v_pid, 1) s join public.products p on p.id = s.item_id
     where s.kind = 'product'
       and not exists (select 1 from public.store_product_prices pr
                        where pr.store_id = p_processing_store_id and pr.product_id = s.item_id
                          and pr.is_active and pr.deleted_at is null)
     order by p.name limit 1;
    if v_name is not null then
      return jsonb_build_object('problem', format(
        'Bundle "%s" includes %s, which has no price at this store, so the bundle cannot be valued here', v_label, v_name)); end if;
  end loop;

  -- The bundle is valued and its items taken back as it is now, so it must
  -- still hold exactly what the invoice recorded selling (its stock
  -- snapshot). A bundle edited after the sale, or a sale from before the
  -- snapshot, would take back items that were never sold.
  select name into v_label from public.promotions where id = it.promotion_id;
  if not exists (select 1 from public.invoices where id = p_original_invoice_id and stock_snapshot_version = 1) then
    return jsonb_build_object('problem', format(
      'This sale of bundle "%s" was recorded before the items of each bundle sold were kept with the invoice, so what it sold cannot be checked and a whole-bundle exchange is refused. Ask the Owner.',
      v_label)); end if;
  if exists (
    (select c.kind, c.item_id, sum(c.quantity)::bigint
       from public.invoice_stock_components c where c.invoice_item_id = it.id group by c.kind, c.item_id
     except
     select 'product'::text, b.product_id, b.quantity::bigint from public.bundle_line_components(it.id) b)
    union all
    (select 'product'::text, b.product_id, b.quantity::bigint from public.bundle_line_components(it.id) b
     except
     select c.kind, c.item_id, sum(c.quantity)::bigint
       from public.invoice_stock_components c where c.invoice_item_id = it.id group by c.kind, c.item_id)) then
    return jsonb_build_object('problem', format(
      'Bundle "%s" was changed after this sale: it no longer holds the items this invoice sold, so a whole-bundle exchange would take back the wrong items and is refused. Ask the Owner.',
      v_label)); end if;

  v_credit := public.promotion_original_total(it.promotion_id, p_processing_store_id);
  v_repl := public.promotion_original_total(v_new.id, p_processing_store_id);
  if v_credit is null or v_repl is null then
    return jsonb_build_object('problem', 'Bundle price unavailable at the processing store'); end if;
  for r in select s.item_id, sum(s.quantity)::int as quantity
             from public.promotion_stock_items(v_new.id, 1) s where s.kind = 'product' group by s.item_id loop
    select coalesce(si.current_qty, 0) into v_have from public.store_inventory si
     where si.store_id = p_processing_store_id and si.product_id = r.item_id;
    if coalesce(v_have, 0) < r.quantity then
      return jsonb_build_object('problem', format(
        'Not enough %s at this store for the replacement bundle (needs %s, has %s)',
        (select name from public.products where id = r.item_id), r.quantity, coalesce(v_have, 0))); end if;
  end loop;
  v_topup := round(v_repl - v_credit, 2);
  return jsonb_build_object(
    'problem', null,
    'credit', v_credit,
    'replacement', v_repl,
    'topup', greatest(v_topup, 0),
    'nonrefundable', greatest(-v_topup, 0),
    'returned', (select coalesce(jsonb_agg(jsonb_build_object('product_id', b.product_id, 'name', p.name,
                                                              'quantity', b.quantity) order by p.name), '[]'::jsonb)
                   from public.bundle_line_components(it.id) b left join public.products p on p.id = b.product_id),
    'replacement_items', (select coalesce(jsonb_agg(jsonb_build_object('product_id', s.item_id, 'name', p.name,
                                                                       'quantity', s.quantity) order by p.name), '[]'::jsonb)
                            from (select item_id, sum(quantity)::int as quantity from public.promotion_stock_items(v_new.id, 1)
                                   where kind = 'product' group by item_id) s
                            left join public.products p on p.id = s.item_id));
end $fn$;
$def$;

  c_preview_def constant text := $def$
create or replace function public.exchange_bundle_preview(p_original_invoice_id uuid, p_processing_store_id uuid,
  p_original_invoice_item_id uuid, p_new_promotion_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
-- 408: the Exchanges page's whole-bundle preview: exchange_bundle_quote, for
-- active staff (406's check) with access to the processing store (as the exchange
-- itself requires) and to the original invoice's store (as
-- exchange_original_context, which the page reads first, requires). Reads
-- only.
declare v_store uuid;
begin
  perform public.require_active_staff();  -- 406: active staff only, else 42501
  if p_processing_store_id is null or not public.user_has_store_access(p_processing_store_id) then
    raise exception 'You do not have access to the processing store' using errcode = '42501'; end if;
  select store_id into v_store from public.invoices where id = p_original_invoice_id;
  if v_store is null or not public.user_has_store_access(v_store) then
    raise exception 'Invoice not accessible' using errcode = '42501'; end if;
  return public.exchange_bundle_quote(p_original_invoice_id, p_processing_store_id,
                                      p_original_invoice_item_id, p_new_promotion_id);
end $fn$;
$def$;

  c_hold_def constant text := $def$
create or replace function public.exchange_invoice_hold(p_invoice_id uuid, p_items uuid[] default null)
returns text
language plpgsql
stable
security definer
set search_path = public
as $fn$
-- 408: why an invoice, or the lines of it named in p_items (all of them when
-- null), cannot be cancelled, refunded, deleted or changed because of an
-- exchange; '' when nothing holds it. An exchange is final until the Owner
-- decides how one is undone:
--   * a replacement invoice: its exchange took the replacement out of stock
--     itself and put the returned items back, so nothing done to this
--     invoice alone would undo it;
--   * an original invoice with a completed exchange of those lines: the
--     exchange already put them back on the shelf, and the customer holds
--     the replacement.
declare i public.invoices%rowtype; v_nos text;
begin
  select * into i from public.invoices where id = p_invoice_id;
  if not found then return ''; end if;
  if coalesce(i.is_exchange, false) and i.exchange_id is not null
     and (p_items is null or exists (select 1 from public.invoice_items it
                                      where it.invoice_id = i.id and it.id = any (p_items)
                                        and it.price_source = 'exchange')) then
    return format('%s is the replacement invoice of exchange %s, which took the replacement out of stock itself and put the returned items back on the shelf. Cancelling, refunding, deleting or changing its exchange lines here would not undo the exchange, so it is refused. Ask the Owner how to undo the exchange.',
      i.invoice_no, coalesce((select e.exchange_no from public.product_exchanges e where e.id = i.exchange_id), 'an exchange'));
  end if;
  select string_agg(distinct e.exchange_no, ', ' order by e.exchange_no) into v_nos
    from public.product_exchanges e
    join public.product_exchange_items x on x.exchange_id = e.id and x.direction = 'returned'
   where e.original_invoice_id = i.id and e.status = 'completed'
     and (p_items is null or x.original_invoice_item_id = any (p_items));
  if v_nos is not null then
    return format('Items on %s were exchanged (%s): the exchange already put them back on the shelf and gave the customer the replacement. Cancelling, refunding or changing those lines here would count them twice and leave the replacement unpaid for, so it is refused. Ask the Owner how to undo the exchange.',
      i.invoice_no, v_nos);
  end if;
  return '';
end $fn$;
$def$;

  c_t_inv_def constant text := $def$
create or replace function public.trg_invoice_exchange_hold()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
-- 408: an invoice an exchange settled cannot be cancelled, asked to be
-- cancelled, or deleted; a replacement invoice cannot be refunded (or asked
-- to be) either. An original invoice's other lines can still be refunded:
-- invoice_refunds' own trigger refuses only the exchanged lines.
declare v text;
begin
  if (new.status is distinct from old.status
        and (new.status::text in ('cancelled', 'cancellation_requested')
             or (coalesce(new.is_exchange, false) and new.status::text in ('refunded', 'refund_requested'))))
     or (new.deleted_at is not null and old.deleted_at is null) then
    v := public.exchange_invoice_hold(new.id);
    if v <> '' then raise exception '%', v; end if;
  end if;
  return new;
end $fn$;
$def$;

  c_t_ref_def constant text := $def$
create or replace function public.trg_invoice_refund_exchange_hold()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
-- 408: a refund that includes a line an exchange settled is refused
-- (exchange_invoice_hold). Refunds of an invoice's other lines, and money
-- refunded against no line (an overpayment), are not affected.
declare v_items uuid[]; v text;
begin
  select array_agg(distinct (e->>'invoice_item_id')::uuid) into v_items
    from jsonb_array_elements(case when jsonb_typeof(new.outcome->'lines') = 'array'
                                   then new.outcome->'lines' else '[]'::jsonb end) e
   where nullif(e->>'invoice_item_id', '') is not null;
  if new.invoice_item_id is not null then
    v_items := array_append(coalesce(v_items, '{}'::uuid[]), new.invoice_item_id); end if;
  if coalesce(cardinality(v_items), 0) = 0 then return new; end if;
  v := public.exchange_invoice_hold(new.invoice_id, v_items);
  if v <> '' then raise exception '%', v; end if;
  return new;
end $fn$;
$def$;

  c_t_stock_def constant text := $def$
create or replace function public.trg_stock_return_exchange_hold()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
-- 408: a deferred constraint trigger, so this runs when the transaction
-- commits, once for each product that came back on an invoice (a
-- cancellation, a refund's sellable return, a goods return, a correction's
-- restore). Where an exchange is part of that invoice (it took this product
-- back from it, or the invoice is its replacement invoice with this product
-- on an exchange line), what came back for the product on the invoice, by
-- the invoice's own returns and by its completed exchanges, must not be more
-- than the invoice itself took out (its store_sale movements). So an
-- exchanged item never goes back on the shelf twice, and an exchange line of
-- a replacement invoice (taken out by the exchange, not by the invoice)
-- never comes back here. A correction that puts the invoice's stock back and
-- takes it again in the same transaction is judged on the result. Invoices
-- no exchange is part of are not looked at.
declare
  v_nos text; v_repl text; v_exch numeric; v_sold numeric; v_back numeric; v_inv text; v_name text;
begin
  select coalesce(sum(x.quantity), 0), string_agg(distinct e.exchange_no, ', ' order by e.exchange_no)
    into v_exch, v_nos
    from public.product_exchanges e
    join public.product_exchange_items x on x.exchange_id = e.id and x.direction = 'returned'
   where e.original_invoice_id = new.invoice_id and e.status = 'completed' and x.product_id = new.product_id;
  select e.exchange_no into v_repl
    from public.invoices i join public.product_exchanges e on e.id = i.exchange_id
   where i.id = new.invoice_id and i.is_exchange
     and exists (select 1 from public.invoice_items it
                  where it.invoice_id = i.id and it.price_source = 'exchange' and it.product_id = new.product_id);
  if v_nos is null and v_repl is null then return null; end if;
  select coalesce(sum(m.quantity) filter (where m.movement_type::text = 'store_sale'), 0),
         coalesce(sum(m.quantity) filter (where m.movement_type::text in
                    ('invoice_cancel_return', 'invoice_refund_return', 'refund_return')), 0)
    into v_sold, v_back
    from public.stock_movements m
   where m.invoice_id = new.invoice_id and m.product_id = new.product_id;
  if v_back + v_exch <= v_sold then return null; end if;
  select invoice_no into v_inv from public.invoices where id = new.invoice_id;
  select name into v_name from public.products where id = new.product_id;
  if v_nos is null then
    raise exception '% on % came from exchange %, which took it out of stock itself. Putting it back here would not undo the exchange, so it is refused. Ask the Owner how to undo the exchange.',
      coalesce(v_name, 'This product'), v_inv, v_repl;
  end if;
  raise exception '% on % was already put back on the shelf by exchange %. Putting it back again would count it twice, so it is refused. Ask the Owner how to undo the exchange.',
    coalesce(v_name, 'This product'), v_inv, v_nos;
end $fn$;
$def$;

  c_t_item_def constant text := $def$
create or replace function public.trg_invoice_item_exchange_hold()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
-- 408: a line an exchange settled (an original line it took back, or a
-- replacement invoice's exchange line) cannot be deleted, or have its kind,
-- product, bundle, quantity or price source changed: a correction would lose
-- the exchange's marks or move stock the exchange already moved. Rewriting
-- the same values (a correction that keeps the line) is not a change.
declare v text;
begin
  if tg_op = 'UPDATE'
     and new.line_kind is not distinct from old.line_kind
     and new.product_id is not distinct from old.product_id
     and new.promotion_id is not distinct from old.promotion_id
     and new.quantity is not distinct from old.quantity
     and new.price_source is not distinct from old.price_source then
    return new;
  end if;
  v := public.exchange_invoice_hold(old.invoice_id, array[old.id]);
  if v <> '' then raise exception '%', v; end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $fn$;
$def$;

  -- ── Anchors and their replacements ─────────────────────────────────────────
  -- All three creators: the affiliate goes in exchange_affiliate_id (rule 6).
  c_cols_a constant text :=
       E'    (exchange_no, original_invoice_id, customer_id, processing_store_id, affiliate_id,\n';
  c_cols_r constant text :=
       E'    -- 408: the original sale''s affiliate goes in exchange_affiliate_id, which\n'
    || E'    -- references customer_affiliates as invoices.affiliate_id does. The legacy\n'
    || E'    -- affiliate_id references the empty affiliates table, so every exchange of\n'
    || E'    -- an invoice with an affiliate was refused; it is no longer written.\n'
    || E'    (exchange_no, original_invoice_id, customer_id, processing_store_id, exchange_affiliate_id,\n';
  c_vals_a constant text :=
       E'  values (v_no, p_original_invoice_id, v_inv.customer_id, p_processing_store_id, v_inv.affiliate_id,\n';
  c_vals_r constant text :=
       E'  values (v_no, p_original_invoice_id, v_inv.customer_id, p_processing_store_id, public.exchange_inherited_affiliate(v_inv.affiliate_id),\n';

  c_prod_pay_a constant text :=
       E'  -- ---- Create exchange header ----\n';
  c_prod_pay_r constant text :=
       E'  -- 408: the money taken now, against what is due (exchange_assert_payments):\n'
    || E'  -- never a Wallet method, nothing when nothing is due (an even swap, a\n'
    || E'  -- cheaper replacement, FOC), never more than is due. Part of a top-up may\n'
    || E'  -- still be owed on the replacement invoice.\n'
    || E'  perform public.exchange_assert_payments(p_payments, v_topup, false);\n'
    || E'\n'
    || E'  -- ---- Create exchange header ----\n';

  c_comp_pay_a constant text :=
       E'  v_no := ''EXC-'' || to_char(now() at time zone ''Asia/Singapore'',''YYYYMMDD'') || ''-'' || substr(gen_random_uuid()::text,1,6);\n';
  c_comp_pay_r constant text :=
       E'  -- 408: the money taken now, against what is due (exchange_assert_payments):\n'
    || E'  -- never a Wallet method, nothing when nothing is due, never more than is due.\n'
    || E'  perform public.exchange_assert_payments(p_payments, v_topup, false);\n'
    || E'\n'
    || E'  v_no := ''EXC-'' || to_char(now() at time zone ''Asia/Singapore'',''YYYYMMDD'') || ''-'' || substr(gen_random_uuid()::text,1,6);\n';

  -- The product and component creators: the eligibility again once the
  -- invoice is locked (the bundle creator's exchange_bundle_quote, called
  -- after its locks, runs it again already).
  c_lock_a constant text :=
       E'  select * into v_inv from public.invoices where id = p_original_invoice_id for update;\n';
  c_lock_r constant text :=
       E'  select * into v_inv from public.invoices where id = p_original_invoice_id for update;\n'
    || E'  -- 408: checked again now the invoice is locked. A refund or cancellation\n'
    || E'  -- that held the lock during the first check is seen once it commits.\n'
    || E'  v_reason := public.exchange_ineligibility_reason(p_original_invoice_id);\n'
    || E'  if v_reason <> '''' then raise exception ''%'', v_reason; end if;\n';

  c_bund_decl_a constant text :=
       E'  v_comp record; v_price numeric; v_avail integer; v_line jsonb;\n';
  c_bund_decl_r constant text :=
       E'  v_comp record; v_price numeric; v_avail integer; v_line jsonb;\n'
    || E'  v408_quote jsonb;  -- 408: what the swap credits and charges, or why it cannot be done\n';
  c_bund_quote_a constant text :=
       E'  if v_item.exchanged_at is not null then raise exception ''This bundle has already been exchanged''; end if;\n';
  c_bund_quote_r constant text :=
       E'  if v_item.exchanged_at is not null then raise exception ''This bundle has already been exchanged''; end if;\n'
    || E'  -- 408: a whole-bundle swap is done only when it can be done completely.\n'
    || E'  -- exchange_bundle_quote refuses bundles with choices, vouchers, therapy or\n'
    || E'  -- other benefits, a line of more than one bundle, a line with an item\n'
    || E'  -- already exchanged on its own, and a replacement bundle that is not on\n'
    || E'  -- sale at this store today; the page shows the same before Confirm.\n'
    || E'  v408_quote := public.exchange_bundle_quote(p_original_invoice_id, p_processing_store_id,\n'
    || E'    p_original_invoice_item_id, p_new_promotion_id);\n'
    || E'  if coalesce(v408_quote->>''problem'', '''') <> '''' then raise exception ''%'', v408_quote->>''problem''; end if;\n';
  c_bund_pay_a constant text :=
       E'  v_no := ''EXB-'' || to_char(now() at time zone ''Asia/Singapore'',''YYYYMMDD'') || ''-'' || substr(gen_random_uuid()::text,1,6);\n';
  c_bund_pay_r constant text :=
       E'  -- 408: exactly the top-up, by a method that is not wallet credit; nothing\n'
    || E'  -- when nothing is due (a payment on a cheaper bundle was dropped unrecorded).\n'
    || E'  perform public.exchange_assert_payments(p_payments, v_topup, true);\n'
    || E'\n'
    || E'  v_no := ''EXB-'' || to_char(now() at time zone ''Asia/Singapore'',''YYYYMMDD'') || ''-'' || substr(gen_random_uuid()::text,1,6);\n';

  c_elig_a constant text :=
       E'  v_paid_date := (v_inv.paid_at at time zone ''Asia/Singapore'')::date;\n';
  c_elig_r constant text :=
       E'  -- 408: once money has been refunded on the invoice, its lines are not\n'
    || E'  -- exchanged as well (the refund may already cover them).\n'
    || E'  if exists (select 1 from public.invoice_refunds r where r.invoice_id = p_invoice_id) then\n'
    || E'    return ''A refund has already been recorded on this invoice, so its items can no longer be exchanged'';\n'
    || E'  end if;\n'
    || E'  v_paid_date := (v_inv.paid_at at time zone ''Asia/Singapore'')::date;\n';

  c_ctx_a constant text :=
       E'   ''affiliate'',(select full_name from public.customers where id=i.affiliate_id),\n'
    || E'   ''affiliate_still_eligible'',case when i.affiliate_id is not null\n'
    || E'                                   then public.is_eligible_affiliate(i.affiliate_id) end);\n';
  c_ctx_r constant text :=
       E'   -- 408: invoices.affiliate_id is a customer_affiliates id, so the name and\n'
    || E'   -- the eligibility are those of the customer it names (it was read as a\n'
    || E'   -- customer id, so every sale looked as if it had no affiliate).\n'
    || E'   ''affiliate'',(select c.full_name from public.customer_affiliates ca\n'
    || E'                  join public.customers c on c.id=ca.customer_id where ca.id=i.affiliate_id),\n'
    || E'   ''affiliate_still_eligible'',case when i.affiliate_id is not null\n'
    || E'                                   then public.exchange_inherited_affiliate(i.affiliate_id) is not null end,\n'
    || E'   -- 408: who an exchange left as the same as the original sale is credited to.\n'
    || E'   ''affiliate_inherited_id'',public.exchange_inherited_affiliate(i.affiliate_id));\n';

  c_req_snap_a constant text :=
       E'   join public.invoice_items it on it.id=c.invoice_item_id where it.invoice_id=p_invoice_id group by c.kind,c.item_id;\n';
  c_req_snap_r constant text :=
       E'   join public.invoice_items it on it.id=c.invoice_item_id where it.invoice_id=p_invoice_id\n'
    || E'    -- 408: an exchange''s replacement lines were taken out of stock by the\n'
    || E'    -- exchange itself (exchange_replacement_out), so nothing is owed for them\n'
    || E'    -- here: paying a part-paid replacement invoice took them out again.\n'
    || E'    -- (A line with no price source still counts.)\n'
    || E'    and (it.price_source is distinct from ''exchange''\n'
    || E'         or not exists (select 1 from public.invoices v where v.id = it.invoice_id and v.is_exchange))\n'
    || E'   group by c.kind,c.item_id;\n';
  c_req_legacy_a constant text :=
       E'  return query select r.kind,r.item_id,r.quantity::int from public.invoice_required_stock_legacy(p_invoice_id) r;\n';
  c_req_legacy_r constant text :=
       E'  -- 408: less an exchange''s replacement lines, as above.\n'
    || E'  return query select r.kind,r.item_id,(r.quantity-coalesce(x.quantity,0))::int\n'
    || E'    from public.invoice_required_stock_legacy(p_invoice_id) r\n'
    || E'    left join (select it.product_id,sum(it.quantity) as quantity from public.invoice_items it\n'
    || E'                where it.invoice_id=p_invoice_id and it.line_kind::text=''product'' and it.price_source=''exchange''\n'
    || E'                  and exists (select 1 from public.invoices v where v.id=p_invoice_id and v.is_exchange)\n'
    || E'                group by it.product_id) x on r.kind=''product'' and x.product_id=r.item_id\n'
    || E'   where x.product_id is null or r.quantity-x.quantity>0;\n';

  -- ── Signatures and AFTER md5s ──────────────────────────────────────────────
  c_new constant text[] := array[
    'exchange_inherited_affiliate(uuid)', 'exchange_assert_payments(jsonb,numeric,boolean)',
    'exchange_bundle_quote(uuid,uuid,uuid,uuid)', 'exchange_invoice_hold(uuid,uuid[])',
    'trg_invoice_exchange_hold()', 'trg_invoice_refund_exchange_hold()',
    'trg_stock_return_exchange_hold()', 'trg_invoice_item_exchange_hold()',
    'exchange_bundle_preview(uuid,uuid,uuid,uuid)'];
  c_new_after constant text[] := array[
    'c08af4b9c6b1afd98ae5bb9f0628a81a', 'd6fd63cf456a5f1557405e70a1e81440', 'cf07451f61cc45b1cef2bd8e31141330', 'd55f4696593447039aa45eeeae9b66d7',
    'a94932825d1a9c4b6cd322bf355633bc', '2a6169a4f683a1c6217381b792dea472', '6f9af8dd208b7203565ed1f5f90d781a', '41b69477b351c47a8070f25b61a8285f',
    'c09fce506c8b92c321e8cf0f589691ff'];
  c_new_names constant text[] := array[
    'exchange_inherited_affiliate', 'exchange_assert_payments', 'exchange_bundle_quote', 'exchange_invoice_hold',
    'trg_invoice_exchange_hold', 'trg_invoice_refund_exchange_hold', 'trg_stock_return_exchange_hold',
    'trg_invoice_item_exchange_hold', 'exchange_bundle_preview'];
  c_patched constant text[] := array[
    'create_product_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text,boolean,uuid,text)',
    'create_bundle_component_exchange(uuid,uuid,uuid,uuid,integer,jsonb,jsonb,text,text)',
    'create_bundle_exchange(uuid,uuid,uuid,uuid,jsonb,text,text)',
    'exchange_ineligibility_reason(uuid)', 'exchange_original_context(uuid)', 'invoice_required_stock(uuid)'];
  c_product_after constant text := '74be7ea5da53738cbc81db4e69ed8362';
  c_component_after constant text := '35af27479da6083ce5297b4a86e7d8cb';
  c_bundle_after constant text := 'ef9775bc5650a8e0da377af9b9fdd18f';
  c_elig_after constant text := '869985df7601d401df40f44c40dd2d6e';
  c_ctx_after constant text := '45cfb42ee4c91a983e3cc546f4a655b3';
  c_req_after constant text := 'c91dc1eb4f2b7b465de5fe4a8fb2ca0c';

  -- ── The triggers, as pg_get_triggerdef shows them with search_path public ──
  c_triggers constant text[] := array[
    'CREATE TRIGGER invoice_exchange_hold BEFORE UPDATE OF status, deleted_at ON public.invoices FOR EACH ROW EXECUTE FUNCTION trg_invoice_exchange_hold()',
    'CREATE TRIGGER invoice_refund_exchange_hold BEFORE INSERT ON public.invoice_refunds FOR EACH ROW EXECUTE FUNCTION trg_invoice_refund_exchange_hold()',
    'CREATE CONSTRAINT TRIGGER stock_return_exchange_hold AFTER INSERT ON public.stock_movements DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (((new.invoice_id IS NOT NULL) AND ((new.movement_type)::text = ANY (ARRAY[''invoice_cancel_return''::text, ''invoice_refund_return''::text, ''refund_return''::text])))) EXECUTE FUNCTION trg_stock_return_exchange_hold()',
    'CREATE TRIGGER invoice_item_exchange_hold BEFORE DELETE OR UPDATE OF line_kind, product_id, promotion_id, quantity, price_source ON public.invoice_items FOR EACH ROW EXECUTE FUNCTION trg_invoice_item_exchange_hold()'];
  c_trigger_tables constant text[] := array['invoices', 'invoice_refunds', 'stock_movements', 'invoice_items'];
  c_trigger_names constant text[] := array['invoice_exchange_hold', 'invoice_refund_exchange_hold',
                                           'stock_return_exchange_hold', 'invoice_item_exchange_hold'];

  v_path text := current_setting('search_path');
  r record; d text; v text; n int; k int; i int; v_bad text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[];
  v_new_install boolean[] := '{}';
begin
  -- pg_get_functiondef names a parameter's type as the search path shows it,
  -- so the definitions are read and compared with public alone, as they were
  -- read on 9 Oct 2026.
  perform set_config('search_path', 'public', true);

  -- ── What the new functions and triggers read ──────────────────────────────
  for r in select * from (values
    ('invoice_refunds', 'outcome'), ('invoice_refunds', 'invoice_item_id'), ('invoices', 'is_exchange'),
    ('invoices', 'exchange_id'), ('invoices', 'deleted_at'), ('invoice_items', 'price_source'),
    ('invoice_items', 'component_exchanged'), ('invoice_items', 'exchanged_at'), ('invoice_items', 'credit_issued_at'),
    ('product_exchange_items', 'original_invoice_item_id'), ('product_exchanges', 'status'),
    ('product_exchanges', 'exchange_affiliate_id'), ('promotion_store_prices', 'available_at_store'),
    ('promotion_choice_groups', 'promotion_id'), ('invoice_promotion_selections', 'invoice_item_id'),
    ('invoice_benefit_values', 'invoice_item_id'), ('purchased_therapy_entitlements', 'invoice_item_id'),
    ('customer_affiliates', 'customer_id'), ('customer_affiliates', 'deleted_at'),
    ('payment_methods', 'is_wallet_credit'), ('store_product_prices', 'deleted_at'),
    ('invoices', 'stock_snapshot_version'), ('invoice_stock_components', 'invoice_item_id'),
    ('invoice_stock_components', 'kind'), ('invoice_stock_components', 'item_id'),
    ('invoice_stock_components', 'quantity'), ('stock_movements', 'invoice_id'),
    ('stock_movements', 'product_id'), ('stock_movements', 'quantity')) x(t, c)
  loop
    if not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = r.t and column_name = r.c) then
      raise exception '408: public.%.% is missing', r.t, r.c; end if;
  end loop;
  if (select count(*) from pg_enum where enumtypid = 'public.invoice_status'::regtype
        and enumlabel in ('cancelled', 'cancellation_requested', 'refunded', 'refund_requested')) <> 4
     or (select count(*) from pg_enum where enumtypid = 'public.stock_movement_type'::regtype
        and enumlabel in ('invoice_cancel_return', 'invoice_refund_return', 'store_sale',
                          'exchange_return_in', 'exchange_replacement_out')) <> 5 then
    raise exception '408: the invoice statuses or stock movement types are not the ones read on 9 Oct 2026'; end if;
  if exists (select 1 from public.product_exchanges where status <> 'completed') then
    raise exception '408: an exchange that is not completed exists; the holds read completed exchanges only'; end if;

  -- ── Guards, anchors and patched texts: nothing is installed unless all pass ──
  for r in select * from (values
    (c_patched[1], '2da9188664a5f359f1b0c5cbb7a4fa24', c_product_after,
     array[[c_lock_a, c_lock_r], [c_cols_a, c_cols_r], [c_vals_a, c_vals_r], [c_prod_pay_a, c_prod_pay_r]]),
    (c_patched[2], '169cd5dbd41f29458bbfeec7d4a31438', c_component_after,
     array[[c_lock_a, c_lock_r], [c_cols_a, c_cols_r], [c_vals_a, c_vals_r], [c_comp_pay_a, c_comp_pay_r]]),
    (c_patched[3], '6c60d8d1381ca569c77dcfac925f62a9', c_bundle_after,
     array[[c_bund_decl_a, c_bund_decl_r], [c_bund_quote_a, c_bund_quote_r], [c_cols_a, c_cols_r],
           [c_vals_a, c_vals_r], [c_bund_pay_a, c_bund_pay_r]]),
    (c_patched[4], 'c6bebabc448b888a525ef895d5551859', c_elig_after, array[[c_elig_a, c_elig_r]]),
    (c_patched[5], 'dd77922b013ef7cd455d38ba3d604469', c_ctx_after, array[[c_ctx_a, c_ctx_r]]),
    (c_patched[6], '83bb2e1f6f8d6cb5c9287a29b2df8cf8', c_req_after,
     array[[c_req_snap_a, c_req_snap_r], [c_req_legacy_a, c_req_legacy_r]])
  ) x(fn, before_md5, after_md5, edits)
  loop
    if to_regprocedure('public.' || r.fn) is null then
      raise exception '408: public.% is missing', r.fn; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.fn));
    v := md5(d);
    if v = r.after_md5 then
      raise notice '408: public.% is already this version; left alone', r.fn;
      continue;
    elsif v <> r.before_md5 then
      raise exception '408: public.% is not the version this was tested against (md5 %). Re-read it from production and re-test before applying.', r.fn, v;
    end if;
    for k in 1 .. array_length(r.edits, 1) loop
      n := (length(d) - length(replace(d, r.edits[k][1], ''))) / length(r.edits[k][1]);
      if n <> 1 then
        raise exception '408: anchor % of public.% was found % times, not once', k, r.fn, n; end if;
      d := replace(d, r.edits[k][1], r.edits[k][2]);
    end loop;
    v_fns := v_fns || r.fn;
    v_defs := v_defs || d;
  end loop;
  -- Relied on, not changed: the versions read on 9 Oct 2026 (the one call the
  -- page makes and what it does after the creators: the details, the
  -- replacement invoice and its trigger; the bundle's components, value and
  -- stock items; the affiliate's eligibility; the stock engine around
  -- invoice_required_stock and the two returns the stock trigger meets; who
  -- is asking).
  for r in select * from (values
    ('create_exchange_with_details(text,jsonb)', 'b804b14bd80fff3e813d801eb789e83d'),
    ('set_exchange_details(uuid,jsonb,jsonb,uuid,date,text)', '352b1277be6e3ef60dda4cce80949aff'),
    ('create_exchange_invoice(uuid)', 'd30f8a2740154353e9f65e2bb64963fa'),
    ('trg_exchange_invoice()', 'f4a84ead2fd5fa51d2e50d70da206e38'),
    ('bundle_line_components(uuid)', '93ebc0e25991428c5e94a71879bbef41'),
    ('promotion_original_total(uuid,uuid)', '2480074e2b77e313b052cc225493087c'),
    ('promotion_stock_items(uuid,integer)', '82dd6bdac5566fce0b75470eb45444d1'),
    ('is_eligible_affiliate(uuid)', '2dfbe1cee8c2be5b5e14a0d19f0553c4'),
    ('invoice_required_stock_legacy(uuid)', '2e0bc2497901c2690a74205bdd3a0a5f'),
    ('invoice_stock_to_deduct(uuid)', '6356494ccb8545d46c56b788f8f85f54'),
    ('deduct_invoice_stock(uuid,text)', '32183fe9e7c15ed0b11307c48289831a'),
    ('restore_invoice_stock(uuid,text)', '092316c3af22361f80d186e38fe49bf3'),
    ('record_invoice_stock_return(uuid,jsonb,text,uuid)', '6b125cb5df1eb103781662bef41e9417'),
    ('require_active_staff(text[])', '877b3aa74cea559881979bb161c450e2'),
    ('user_has_store_access(uuid)', '8c82c6bcb64f496c5a05a2b8dafa95f8'),
    ('sg_today()', '1c1289f18e24d8370e9a6364c9c06fca')) x(fn, md5)
  loop
    if to_regprocedure('public.' || r.fn) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || r.fn))) <> r.md5 then
      raise exception '408: public.% is missing or not the version read on 9 Oct 2026. Re-read it from production and re-test before applying.', r.fn; end if;
  end loop;
  -- New functions: missing, or already this version.
  for i in 1 .. array_length(c_new, 1) loop
    if to_regprocedure('public.' || c_new[i]) is null then
      v_new_install := v_new_install || true;
    elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_new[i]))) = c_new_after[i] then
      v_new_install := v_new_install || false;
    else
      raise exception '408: a different public.% already exists (md5 %)', c_new[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_new[i]))); end if;
  end loop;
  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname = any (c_new_names || array['create_product_exchange', 'create_bundle_component_exchange',
                                               'create_bundle_exchange', 'exchange_ineligibility_reason',
                                               'exchange_original_context', 'invoice_required_stock'])
     and p.oid::regprocedure::text <> all (c_new || c_patched);
  if v_bad is not null then
    raise exception '408: another overload exists: %', v_bad; end if;
  -- The triggers: absent, or already these.
  for i in 1 .. array_length(c_triggers, 1) loop
    select pg_get_triggerdef(t.oid) into v from pg_trigger t
     where t.tgrelid = ('public.' || c_trigger_tables[i])::regclass and t.tgname = c_trigger_names[i] and not t.tgisinternal;
    if v is not null and v <> c_triggers[i] then
      raise exception '408: a different trigger % is on public.%: %', c_trigger_names[i], c_trigger_tables[i], v; end if;
  end loop;
  select array_agg(coalesce(p.proacl::text, '') order by p.oid::regprocedure::text) into v_acl
    from pg_proc p where p.oid = any (array(select to_regprocedure('public.' || f) from unnest(c_patched) f));

  -- ── Install: the new functions first, then the patched ones that call them ──
  for i in 1 .. array_length(c_new, 1) loop
    if v_new_install[i] then
      execute (array[c_inherit_def, c_pay_def, c_quote_def, c_hold_def, c_t_inv_def, c_t_ref_def,
                     c_t_stock_def, c_t_item_def, c_preview_def])[i];
    end if;
    execute format('revoke all on function public.%s from public, anon', c_new[i]);
    if c_new[i] = 'exchange_bundle_preview(uuid,uuid,uuid,uuid)' then
      execute format('grant execute on function public.%s to authenticated, service_role', c_new[i]);
    else
      execute format('revoke all on function public.%s from authenticated', c_new[i]);
      execute format('grant execute on function public.%s to service_role', c_new[i]);
    end if;
  end loop;
  for i in 1 .. coalesce(array_length(v_fns, 1), 0) loop
    execute v_defs[i];
  end loop;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.invoices'::regclass
                  and tgname = 'invoice_exchange_hold' and not tgisinternal) then
    create trigger invoice_exchange_hold before update of status, deleted_at on public.invoices
      for each row execute function public.trg_invoice_exchange_hold();
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.invoice_refunds'::regclass
                  and tgname = 'invoice_refund_exchange_hold' and not tgisinternal) then
    create trigger invoice_refund_exchange_hold before insert on public.invoice_refunds
      for each row execute function public.trg_invoice_refund_exchange_hold();
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.stock_movements'::regclass
                  and tgname = 'stock_return_exchange_hold' and not tgisinternal) then
    -- Deferred to commit: a correction puts the invoice's stock back and takes
    -- it again in one transaction, and only the result is judged.
    create constraint trigger stock_return_exchange_hold after insert on public.stock_movements
      deferrable initially deferred
      for each row
      when (new.invoice_id is not null
            and new.movement_type::text in ('invoice_cancel_return', 'invoice_refund_return', 'refund_return'))
      execute function public.trg_stock_return_exchange_hold();
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.invoice_items'::regclass
                  and tgname = 'invoice_item_exchange_hold' and not tgisinternal) then
    create trigger invoice_item_exchange_hold
      before delete or update of line_kind, product_id, promotion_id, quantity, price_source on public.invoice_items
      for each row execute function public.trg_invoice_item_exchange_hold();
  end if;

  -- ── Installed exactly as tested ───────────────────────────────────────────
  for r in select * from (values
    (c_patched[1], c_product_after), (c_patched[2], c_component_after), (c_patched[3], c_bundle_after),
    (c_patched[4], c_elig_after), (c_patched[5], c_ctx_after), (c_patched[6], c_req_after)) x(fn, after_md5)
  loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || r.fn)));
    if v <> r.after_md5 then
      v_bad := concat_ws('; ', v_bad, r.fn || ' ' || v); end if;
  end loop;
  for i in 1 .. array_length(c_new, 1) loop
    v := md5(pg_get_functiondef(to_regprocedure('public.' || c_new[i])));
    if v <> c_new_after[i] then
      v_bad := concat_ws('; ', v_bad, c_new[i] || ' ' || v); end if;
  end loop;
  if v_bad is not null then
    raise exception '408: installed with md5s other than the tested ones: %', v_bad; end if;
  -- The patched functions keep the grants they had: the creators and the
  -- stock engine the service role's alone, the eligibility and the original
  -- sale's context staff's; none callable signed out.
  if (select array_agg(coalesce(p.proacl::text, '') order by p.oid::regprocedure::text)
        from pg_proc p where p.oid = any (array(select to_regprocedure('public.' || f) from unnest(c_patched) f)))
     is distinct from v_acl then
    raise exception '408: the grants of a patched function changed'; end if;
  foreach v in array c_patched || c_new loop
    if has_function_privilege('anon', 'public.' || v, 'execute') then
      raise exception '408: public.% is callable signed out', v; end if;
    if v in ('exchange_ineligibility_reason(uuid)', 'exchange_original_context(uuid)',
             'exchange_bundle_preview(uuid,uuid,uuid,uuid)') then
      if not has_function_privilege('authenticated', 'public.' || v, 'execute') then
        raise exception '408: public.% is not callable by staff', v; end if;
    elsif has_function_privilege('authenticated', 'public.' || v, 'execute') then
      raise exception '408: public.% is callable by a client role', v;
    end if;
    if not has_function_privilege('service_role', 'public.' || v, 'execute') then
      raise exception '408: public.% is not the service role''s', v; end if;
  end loop;
  for i in 1 .. array_length(c_triggers, 1) loop
    if (select count(*) from pg_trigger t
         where t.tgrelid = ('public.' || c_trigger_tables[i])::regclass and t.tgname = c_trigger_names[i]
           and not t.tgisinternal and t.tgenabled = 'O' and pg_get_triggerdef(t.oid) = c_triggers[i]) <> 1 then
      raise exception '408: the trigger % is not on public.% as tested', c_trigger_names[i], c_trigger_tables[i]; end if;
  end loop;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
