-- 455_exchange_several_items.sql
--
-- SEVERAL ITEMS IN ONE EXCHANGE: PLAIN PRODUCT LINES AND ITEMS OF BUNDLES, IN
-- ANY MIX, ONE EXCHANGE NUMBER AND ONE REPLACEMENT INVOICE; AND THE EXCHANGE'S
-- NOTE FOR ITS REPLACEMENT INVOICE (the Owner, 22 Oct 2026, items 2 and 6)
--
-- WHAT WAS WRONG / WHY
--
--   Item 2, "Exchange more than one product at a time". The Exchanges page had
--   three modes. Product took several plain product lines at once (each whole;
--   create_product_exchange pools their credit). Bundle component took ONE item
--   of ONE bundle per exchange: the page kept one component and
--   create_bundle_component_exchange takes one p_component_product_id and one
--   p_component_qty. A plain product and an item of a bundle could never go in
--   the same exchange. So a customer bringing back two items of a bundle, or a
--   product and an item of a bundle, needed two or more exchanges: two EX
--   numbers, two replacement invoices, and each exchange left its own
--   non-refundable remainder where one exchange would have pooled the value.
--   create_exchange_with_details routes 'product' | 'bundle' |
--   'bundle_component' to the three creators, and nothing combined them.
--
--   Item 6 (the exchange half), "the note should be in exchange invoice as
--   well". product_exchanges.notes is saved (the page's Notes, set_exchange_
--   details) but nothing read it back: exchange_invoice_details, which the
--   Invoices page reads to print and PDF a replacement invoice's Exchange
--   Details, returned no notes.
--
-- THE RULES (binding; the Owner's answers, 22 Oct 2026)
--
--   Item 2: "Both kinds, any mix": one 'Items to return' list where plain
--   product lines (returned whole) and items from a bundle (with a quantity up
--   to what is held, not already exchanged) can be ticked together, giving ONE
--   exchange number and ONE replacement invoice; the value of everything
--   returned is pooled (as plain lines already pool); keep one product type per
--   exchange (own vs third-party, enforced on the server); keep part-quantity
--   rules as they are; whole-bundle exchange stays its own mode.
--   Item 6 (exchange half): the exchange's Notes is returned by
--   exchange_invoice_details as 'notes' so the replacement invoice can print
--   it; notes are entered when the exchange is made; no later editing.
--   How it reads (this file):
--   * Each returned item keeps the rules of the creator of its kind, word for
--     word: a plain line is a 'product' line not exchanged, returned whole
--     ("Return the full quantity of the purchased line in 3A");
--     an item of a bundle is a product the bundle line holds
--     (bundle_line_components), 1 to what it holds, on a line not exchanged
--     whole, and that product of that line not exchanged before (one exchange
--     of any quantity of it closes it, as now). The same item twice in one
--     exchange is refused.
--   * Its credit is exchange_credit_value's (424, the Owner's Q17: the lower
--     of today's price and what was paid; for a bundle item its share of what
--     the line was paid), item by item; the exchange's credit is their sum, so
--     a remainder on one item counts towards the replacement of another.
--   * One product type: every returned and replacement item own, or every one
--     third-party (the Phase 3A rule; the same two messages).
--   * Money: what the replacement costs beyond the credit is the top-up
--     (408's exchange_assert_payments: never a Wallet method, nothing when
--     nothing is due, never more than is due); a credit beyond it is
--     non-refundable, as now.
--   * Stock: every returned item back to the processing store, every
--     replacement out of it, a movement each (exchange_return_in,
--     exchange_replacement_out); replacement stock is checked for the SUM of
--     the rows of one product (before, each row alone, so two rows of one
--     product passed the check and were stopped only by the stock trigger).
--   * Marks: a plain line's exchanged_at and exchange_id; a bundle item an
--     entry {product_id, qty, exchange_id} in its line's component_exchanged,
--     exactly as the single-item creators write them, so 408's holds and
--     exchange_bundle_quote's refusal of a whole-bundle swap read them as
--     before.
--   * Its number: EX- when every item is a plain line (kind 'product'), EXC-
--     otherwise (kind 'bundle_component' when every item is of a bundle,
--     'items' for a mix). Nothing reads exchange_kind (no check constraint;
--     only the creators write it).
--
-- WHAT THIS DOES (one function added, the service role's alone; two patched at
-- anchors, their grants kept; no table, row or other function changes)
--
--   1. create_items_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text) (new; the
--      server's alone, like the three creators): one exchange of the returned
--      entries p_returned ([{invoice_item_id, quantity?}] for a plain line,
--      [{invoice_item_id, product_id, quantity}] for an item of a bundle, in
--      any mix) for the replacement rows p_replacement, by the rules above. It
--      checks eligibility before and after locking the invoice (408), the
--      processing store (424, X-9), the reason, and locks each returned line.
--      It writes one product_exchanges row (status 'completed', so the
--      deferred exchange_creates_invoice trigger makes ONE replacement invoice,
--      create_exchange_invoice unchanged: lines at full value, the credit as
--      line discounts, commission on the top-up only), a returned row per item
--      (its credit as line_total), the replacement rows, the payments, and one
--      audit row ('exchange_completed', listing every item with its credit,
--      today's price and what was paid behind it).
--   2. create_exchange_with_details(text,jsonb) (the page's call): a new kind
--      'items' routes there (two anchors: the list of kinds, and a branch
--      before the bundle_component one). 'product', 'bundle' and
--      'bundle_component' are unchanged, so an older page still works;
--      set_exchange_details, the instalment label and arrangements run after
--      it as for every kind.
--   3. exchange_invoice_details(uuid): returns 'notes' (the exchange's note,
--      null when none) beside 'reason' (one anchor).
--
-- NOT CHANGED
--
--   create_product_exchange, create_bundle_component_exchange,
--   create_bundle_exchange (and so the whole-bundle mode), create_exchange_
--   invoice, set_exchange_details, exchange_credit_value, exchange_credit_
--   preview (it already gives every item of every bundle line at each
--   quantity, which the page sums), bundle_line_components, exchange_
--   ineligibility_reason (several exchanges of one invoice stay allowed),
--   exchange_assert_payments, exchange_inherited_affiliate, 408's holds
--   (exchange_invoice_hold and its triggers: they read returned rows and the
--   marks per line, as written here), report_exchange_invoices, exchange_
--   payment_position, record_document_printed: pinned below where relied on.
--   Wallet credit: untouched (exchanges never credit or debit a wallet).
--   Commission: earned on the replacement invoice's top-up only, as for every
--   exchange. The Invoices page's print and PDF of a replacement invoice
--   (printing the note it now gets) is another change of 22 Oct 2026.
--
-- NOT COVERED (to tell the Owner)
--
--   1. FOC on a several-item exchange: the page has never sent FOC on an
--      exchange; create_product_exchange's p_foc stays for the 'product' kind
--      only, and 'items' has none.
--   2. Part quantities are as before: a plain line is returned whole; once
--      any quantity of an item of a bundle line is exchanged, the rest of that
--      item of that line can never be (the Owner kept both rules).
--   3. 408's exchange_bundle_quote (and create_bundle_exchange, which raises
--      its answer) still names the old mode in four refusals of a whole-bundle
--      swap: an item already exchanged on its own and a line of several
--      bundles ("Exchange its [other] items with Bundle component instead"),
--      items chosen at the till on the line, and a returned or replacement
--      bundle with choice groups ("...; use Bundle component"). The page now
--      calls that mode Items, and shows these four in its own words ("under
--      Items instead", "exchange item by item under Items instead"). It greys
--      out the first two kinds of bundle itself; the other two it can only
--      learn from the server, so staff see them when they pick such a bundle.
--      Rewording them on the server needs exchange_bundle_quote changed and
--      re-pinned: not done here.
--   4. The note cannot be changed after the exchange is saved (the Owner: no
--      later editing). set_exchange_details still writes it only when one is
--      given, as before.
--   5. A long exchange makes a long printed half-page (the A5 copies; the
--      Owner's item 5 is about long documents).
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (450 in: 63219badeea67a5d401d5af2aeb88f19, 1371
--   functions) -> 455 -> the Exchanges page that sends 'items'. The page
--   BEFORE the migration would fail every Items exchange ("Unknown exchange
--   kind items"), so the migration goes first; an older page keeps working
--   after it (its three kinds are unchanged). Other files of 22 Oct 2026: this
--   file pins only exchange and shared staff-check functions (below); a file
--   that changes one of them makes this one refuse, naming it, and changes
--   nothing (re-read, re-test, re-pin). Checked on a copy, 22 Oct 2026: 450 ->
--   452, 453 and 454 as they stood that day (of the functions pinned here
--   they use only create_invoice and require_active_staff, and change none)
--   -> 455 applies, and its suite and the two permission suites pass.
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below, the second changes
--      nothing ("already this version; left alone" three times).
--   2. Apply (the CLI, or the MCP's apply_migration with this text verbatim).
--      It checks itself.
--   3. Then deploy the page (ExchangesPage.tsx and src/lib/exchanges, the
--      print in src/lib/printDoc.ts).
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the new function's text is the tested one (its AFTER md5); it is absent
--     (created) or this version (left alone);
--   * each patched function is its BEFORE (production, 22 Oct 2026, at 450;
--     patched, each anchor found once, the text built has the tested AFTER
--     md5) or its AFTER (left alone), so a second run changes nothing; no
--     other function takes the three names;
--   * the functions it relies on are as read on production (below); the
--     columns it writes and reads are there with these types;
--   * afterwards: the three md5s are the AFTER ones; the two patched keep
--     their grants (compared as sets) and stay callable by signed-in staff and
--     not by anon; the new one is the service role's alone (revoked from
--     public, anon and signed-in staff; granted to the service role);
--   * then a self-test, in a block that is always undone (it ends by raising
--     P0455, so it leaves no row): a made-up Owner, store, buyer (a fictional
--     ACMA phone no customer has), own products A, B, C and D and a bundle of
--     A and B, sold with a plain line of D, paid. One 'items' exchange of D
--     whole and A and B of the bundle for two C, with a note: one exchange
--     (EXC-, kind items), three returned rows adding up to its credit (50 +
--     75 + 75), S$40 paid, stock back for A, B and D and two C out, the plain
--     line and both bundle items marked; its ONE replacement invoice (S$40,
--     its line discounts the S$200 credit); exchange_invoice_details returns
--     the note; the same bundle item again, and own for third-party, are
--     refused. If the shared settings row (commission rates) is missing, as
--     on a bare local copy, the self-test adds it for itself (undone with it).
--   It reads only, apart from the three functions and the self-test's rows
--   (undone). Locks: the three functions' catalogue rows, to the end of the
--   apply. An exchange running at that moment finishes on the text it
--   started with.
--
-- BEFORE (production, 22 Oct 2026, at 450, read on a copy of it; md5 of
-- pg_get_functiondef with search_path public)
--   changed
--   create_exchange_with_details(text,jsonb)                       bceb96b473d2c153c871e9547769bb29  (424's)
--   exchange_invoice_details(uuid)                                 9b8f97630794150edae2753469c0a99a  (406's)
--   create_items_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text)   (not there)
--   relied on, not changed
--   create_product_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text,boolean,uuid,text) 48679d09a214c9dcf8850be51110d8bc  (424's)
--   create_bundle_component_exchange(uuid,uuid,uuid,uuid,integer,jsonb,jsonb,text,text) 8d588d7f856fca85356e293a8af3ecef  (424's)
--   create_bundle_exchange(uuid,uuid,uuid,uuid,jsonb,text,text)    c552d1734cd4e8052b113a6026d8a6b2  (424's)
--   create_exchange_invoice(uuid)                                  6392abd80baad4b1a2a5069654c994c1  (424's: the replacement invoice)
--   trg_exchange_invoice()                                         f4a84ead2fd5fa51d2e50d70da206e38
--   set_exchange_details(uuid,jsonb,jsonb,uuid,date,text)          f317e42aae09809c46625f47eb884298
--   exchange_credit_value(uuid,uuid,uuid,integer)                  8998ee93a6fce8ce3a82e2a8c49aa95a
--   exchange_credit_preview(uuid,uuid)                             263bb91b1ed38c6b53767c4d0182595c  (the page's figures)
--   bundle_line_components(uuid)                                   794ad28556de3e53d945e9ff742697a0
--   exchange_ineligibility_reason(uuid)                            869985df7601d401df40f44c40dd2d6e
--   exchange_assert_payments(jsonb,numeric,boolean)                d6fd63cf456a5f1557405e70a1e81440
--   exchange_inherited_affiliate(uuid)                             c08af4b9c6b1afd98ae5bb9f0628a81a
--   exchange_invoice_hold(uuid,uuid[])                             d55f4696593447039aa45eeeae9b66d7
--   trg_stock_return_exchange_hold()                               6f9af8dd208b7203565ed1f5f90d781a
--   trg_invoice_item_exchange_hold()                               41b69477b351c47a8070f25b61a8285f
--   exchange_bundle_quote(uuid,uuid,uuid,uuid)                     447b48555da3e278bf2adb4cde3c155b  (reads the marks)
--   user_has_store_access(uuid)                                    708992afaa6c3951f6329239b742987c
--   current_user_role()                                            519b0a33a3548f970c5d585b6e76a389
--   require_active_staff(text[])                                   877b3aa74cea559881979bb161c450e2
--   require_store_access(uuid)                                     f9332fd2f0092337d64501d8a647c23f
--   write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text) c705c733e213a27f0dc32d54322cc855
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)   80c80d386a5241e63b353e35e13ef250  (the self-test)
--   record_invoice_payment(uuid,jsonb,uuid)                        9c70097ed4da614fb9dcc66fdfcdb7d6  (the self-test)
--   public function fingerprint, production now (450 in)           63219badeea67a5d401d5af2aeb88f19 (1371 functions)
-- AFTER (for later guards)
--   create_exchange_with_details(text,jsonb)                       82cdd84bf325a4ea5a49ea665f2d3404
--   exchange_invoice_details(uuid)                                 45791e627e1616ab7edad181139a2d83
--   create_items_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text)   39d3bf8e11dcf34425cb7bce4ea51a6d  (new; service role alone)
--   public function fingerprint, worked out on a copy of production (22 Oct 2026):
--     production now (450 in) -> 455 (a second run the same)       50fcdb82cb6f3e9d290e76fd1f3d4ee4 (1372 functions: one new, none dropped)
--
-- Test: scripts/exchanges/tests/several-items-455.sql (begin ... rollback; it
-- installs this file twice; -v skip_install=1 where it is in): two items of
-- one bundle; a plain line with items of two bundles (pooled credit, a
-- non-refundable remainder, a payment refused, the note back through
-- exchange_invoice_details); plain lines only, the same as the 'product'
-- kind; 20 refusals that write nothing; items already exchanged (an item, a
-- line, a bundle swapped whole), the whole-bundle swap after its items and a
-- cancellation refused; the old kinds and an instalment; the md5s and grants;
-- a second run changes nothing and the self-test leaves no row.
-- scripts/permissions/tests/function-grants.sql lists create_items_exchange
-- among the internals no client role may call. Fixtures only (the
-- repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The two functions this patches: BEFORE (production, 22 Oct 2026, at
  -- 450) and AFTER md5s ═══════════════════════════════════════════════════════
  c_wd constant text := 'create_exchange_with_details(text,jsonb)';
  c_ed constant text := 'exchange_invoice_details(uuid)';
  c_wd_before constant text := 'bceb96b473d2c153c871e9547769bb29';
  c_wd_after  constant text := '82cdd84bf325a4ea5a49ea665f2d3404';
  c_ed_before constant text := '9b8f97630794150edae2753469c0a99a';
  c_ed_after  constant text := '45791e627e1616ab7edad181139a2d83';

  -- ══ The function this adds (the server's alone) ══════════════════════════
  c_h constant text := 'create_items_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text)';
  c_h_after constant text := '39d3bf8e11dcf34425cb7bce4ea51a6d';
  c_h_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';
  c_h_def constant text :=
$def$CREATE OR REPLACE FUNCTION public.create_items_exchange(p_original_invoice_id uuid, p_processing_store_id uuid, p_returned jsonb, p_replacement jsonb, p_payments jsonb DEFAULT '[]'::jsonb, p_reason text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 455 (the Owner, 22 Oct 2026: "Both kinds, any mix"): one exchange of several
-- returned items, in any mix: plain product lines, each returned whole, and
-- items of bundles, each for a quantity up to what its bundle line holds and
-- not exchanged before. One exchange number and one replacement invoice (the
-- deferred exchange_creates_invoice trigger, as for every exchange). The credit
-- of everything returned is pooled, as several product lines already were.
-- Each item keeps the rules of the creator of its kind, unchanged:
--   * a plain line (no product_id): create_product_exchange's (a 'product'
--     line, not exchanged, its whole quantity);
--   * a bundle item (product_id, quantity): create_bundle_component_exchange's
--     (a bundle line not exchanged whole, a product it holds, 1 to what it
--     holds, that product of the line not exchanged before), and the same item
--     never twice in one exchange;
--   * every returned and replacement item one product type, own or
--     third-party (the Phase 3A rule);
--   * credit: exchange_credit_value, item by item (424, Q17); payments:
--     exchange_assert_payments (408); stock back to the processing store per
--     item, replacements out of it, checked against their sum per product.
-- The page reaches it through create_exchange_with_details('items', ...); it
-- is the server's alone.
-- p_returned: [{invoice_item_id, quantity?} | {invoice_item_id, product_id, quantity}]
-- p_replacement: [{product_id, quantity}]
declare
  v_inv public.invoices%rowtype; v_item public.invoice_items%rowtype;
  v_reason text; v_role user_role; v_ex_id uuid; v_no text; v_kind text;
  v_line jsonb; v_lines jsonb := '[]'::jsonb; v_seen text[] := '{}'; v_key text;
  v_prod uuid; v_qty integer; v_have bigint; v_ptype product_type; v_side_type product_type;
  v_price numeric; v_avail integer; v_c jsonb; v_cr numeric; v_bundle boolean;
  v_credit numeric := 0; v_todays numeric := 0; v_paid numeric := 0; v_repl numeric := 0;
  v_topup numeric; v_nonref numeric := 0; v_plain integer := 0; v_comp integer := 0;
  r record;
begin
  v_role := public.current_user_role();
  if v_role is null then raise exception 'No profile for current user'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'A reason is required for the exchange'; end if;

  -- Eligibility, checked again once the invoice is locked (408).
  v_reason := public.exchange_ineligibility_reason(p_original_invoice_id);
  if v_reason <> '' then raise exception '%', v_reason; end if;
  select * into v_inv from public.invoices where id = p_original_invoice_id for update;
  v_reason := public.exchange_ineligibility_reason(p_original_invoice_id);
  if v_reason <> '' then raise exception '%', v_reason; end if;
  -- 424 (X-9): staff exchange at any store they work at.
  if not public.user_has_store_access(p_processing_store_id) then
    raise exception 'You do not have access to the processing store'; end if;

  if p_returned is null or jsonb_typeof(p_returned) <> 'array' or jsonb_array_length(p_returned) = 0 then
    raise exception 'Select at least one item to return'; end if;
  if p_replacement is null or jsonb_typeof(p_replacement) <> 'array' or jsonb_array_length(p_replacement) = 0 then
    raise exception 'Select at least one replacement product'; end if;

  -- ---- Returned side: each item by the rules of its kind, then its credit ----
  for v_line in select * from jsonb_array_elements(p_returned) loop
    if jsonb_typeof(v_line) <> 'object' then raise exception 'A returned item is not part of the original invoice'; end if;
    select * into v_item from public.invoice_items
     where id = nullif(v_line->>'invoice_item_id', '')::uuid and invoice_id = p_original_invoice_id for update;
    if not found then raise exception 'A returned item is not part of the original invoice'; end if;
    v_prod := nullif(v_line->>'product_id', '')::uuid;
    v_bundle := v_prod is not null;
    v_key := v_item.id::text || '/' || coalesce(v_prod::text, '');
    if v_key = any (v_seen) then raise exception 'The same item is listed twice in this exchange'; end if;
    v_seen := v_seen || v_key;

    if not v_bundle then
      -- A plain product line, returned whole (create_product_exchange).
      if v_item.line_kind <> 'product' then
        raise exception 'A bundle is returned item by item here (name the product of it being returned), or whole as a bundle exchange'; end if;
      if v_item.exchanged_at is not null then raise exception 'An item on this invoice has already been exchanged'; end if;
      v_qty := coalesce(nullif(v_line->>'quantity', '')::integer, v_item.quantity);
      if v_qty <> v_item.quantity then raise exception 'Return the full quantity of the purchased line in 3A'; end if;
      v_prod := v_item.product_id;
      select selling_price into v_price from public.store_product_prices
       where store_id = p_processing_store_id and product_id = v_prod and is_active = true;
      if v_price is null then raise exception 'Returned product has no active price at the processing store'; end if;
      v_c := public.exchange_credit_value(v_item.id, p_processing_store_id, null, null);
      v_plain := v_plain + 1;
    else
      -- An item of a bundle (create_bundle_component_exchange).
      if v_item.line_kind <> 'promotion' then raise exception 'That line is not a bundle'; end if;
      if v_item.exchanged_at is not null then raise exception 'This bundle has already been fully exchanged'; end if;
      select b.quantity into v_have from public.bundle_line_components(v_item.id) b where b.product_id = v_prod;
      if v_have is null then raise exception 'That product is not a component of this bundle'; end if;
      v_qty := nullif(v_line->>'quantity', '')::integer;
      if v_qty is null or v_qty <= 0 or v_qty > v_have then
        raise exception 'Invalid component quantity (bundle has % of that product)', v_have; end if;
      if exists (select 1 from jsonb_array_elements(coalesce(v_item.component_exchanged, '[]'::jsonb)) e
                  where (e->>'product_id')::uuid = v_prod) then
        raise exception 'That component has already been exchanged'; end if;
      select selling_price into v_price from public.store_product_prices
       where store_id = p_processing_store_id and product_id = v_prod and is_active = true;
      if v_price is null then raise exception 'Component has no active price at the processing store'; end if;
      v_c := public.exchange_credit_value(v_item.id, p_processing_store_id, v_prod, v_qty);
      v_comp := v_comp + 1;
    end if;

    select product_type into v_ptype from public.products where id = v_prod;
    if v_side_type is null then v_side_type := v_ptype;
    elsif v_ptype is distinct from v_side_type then raise exception 'All returned items must be the same product type'; end if;

    -- 424 (the Owner, Q17): the lower of today's price and what was paid (for
    -- a bundle item, its share of what the line was paid).
    v_cr := (v_c->>'credit')::numeric;
    if v_cr is null then raise exception 'A returned item could not be valued at the processing store'; end if;
    v_credit := v_credit + v_cr;
    v_todays := v_todays + coalesce((v_c->>'todays')::numeric, 0);
    v_paid := v_paid + coalesce((v_c->>'paid')::numeric, 0);
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('invoice_item_id', v_item.id, 'product_id', v_prod,
      'quantity', v_qty, 'credit', v_cr, 'bundle_item', v_bundle));
  end loop;

  -- ---- Replacement side: the same type, a price here, the stock for their sum ----
  for v_line in select * from jsonb_array_elements(p_replacement) loop
    v_prod := nullif(v_line->>'product_id', '')::uuid;
    v_qty := nullif(v_line->>'quantity', '')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Replacement quantity must be greater than zero'; end if;
    select product_type into v_ptype from public.products where id = v_prod;
    if v_ptype is null then raise exception 'Replacement product not found'; end if;
    if v_ptype <> v_side_type then
      raise exception 'Own products may only be exchanged for own products, and third-party for third-party'; end if;
    select selling_price into v_price from public.store_product_prices
     where store_id = p_processing_store_id and product_id = v_prod and is_active = true;
    if v_price is null then raise exception 'A replacement product has no active price at the processing store'; end if;
    v_repl := v_repl + v_price * v_qty;
  end loop;
  -- Two rows of one product are checked together, not each alone.
  for r in select (x->>'product_id')::uuid as product_id, sum((x->>'quantity')::integer) as qty
             from jsonb_array_elements(p_replacement) x group by 1 loop
    select current_qty into v_avail from public.store_inventory
     where store_id = p_processing_store_id and product_id = r.product_id for update;
    if coalesce(v_avail, 0) < r.qty then
      raise exception 'Insufficient replacement stock at the processing store: % has %, and % is asked for',
        (select name from public.products where id = r.product_id), coalesce(v_avail, 0), r.qty; end if;
  end loop;

  -- ---- Money: the pooled credit against the replacement ----
  v_credit := round(v_credit, 2);
  v_topup := round(v_repl - v_credit, 2);
  if v_topup < 0 then v_nonref := -v_topup; v_topup := 0; end if;   -- non-refundable, no money moves
  -- 408: never a Wallet method, nothing when nothing is due, never more than
  -- is due. Part of a top-up may still be owed on the replacement invoice.
  perform public.exchange_assert_payments(p_payments, v_topup, false);

  -- ---- The exchange: plain lines only keep the EX- number and kind 'product',
  -- bundle items only the EXC- number and 'bundle_component'; a mix is EXC-
  -- and 'items' ----
  v_kind := case when v_comp = 0 then 'product' when v_plain = 0 then 'bundle_component' else 'items' end;
  v_no := case when v_comp = 0 then 'EX-' else 'EXC-' end
          || to_char(now() at time zone 'Asia/Singapore', 'YYYYMMDD') || '-' || substr(gen_random_uuid()::text, 1, 6);
  insert into public.product_exchanges
    (exchange_no, original_invoice_id, customer_id, processing_store_id, exchange_affiliate_id,
     returned_credit_total, replacement_total, topup_amount, nonrefundable_amount,
     status, exchange_kind, reason, notes, created_by, locked_at)
  values (v_no, p_original_invoice_id, v_inv.customer_id, p_processing_store_id, public.exchange_inherited_affiliate(v_inv.affiliate_id),
     v_credit, v_repl, v_topup, v_nonref, 'completed', v_kind, p_reason, p_notes, auth.uid(), now())
  returning id into v_ex_id;

  -- ---- Returned items: a row each with its credit, stock back, the line marked ----
  for v_line in select * from jsonb_array_elements(v_lines) loop
    v_prod := (v_line->>'product_id')::uuid;
    v_qty := (v_line->>'quantity')::integer;
    v_cr := (v_line->>'credit')::numeric;
    insert into public.product_exchange_items (exchange_id, direction, original_invoice_item_id, product_id, quantity, unit_price, line_total)
    values (v_ex_id, 'returned', (v_line->>'invoice_item_id')::uuid, v_prod, v_qty, round(v_cr / v_qty, 2), v_cr);
    insert into public.store_inventory (store_id, product_id, current_qty)
      values (p_processing_store_id, v_prod, v_qty)
      on conflict (store_id, product_id) do update set current_qty = public.store_inventory.current_qty + excluded.current_qty, updated_at = now();
    insert into public.stock_movements (product_id, movement_type, to_store_id, quantity, notes, created_by)
      values (v_prod, 'exchange_return_in', p_processing_store_id, v_qty, 'Exchange ' || v_no || ' — returned', auth.uid());
    if (v_line->>'bundle_item')::boolean then
      -- The bundle line stays: this item of it is marked exchanged.
      update public.invoice_items
         set component_exchanged = coalesce(component_exchanged, '[]'::jsonb)
               || jsonb_build_object('product_id', v_prod, 'qty', v_qty, 'exchange_id', v_ex_id)
       where id = (v_line->>'invoice_item_id')::uuid;
    else
      update public.invoice_items set exchanged_at = now(), exchange_id = v_ex_id
       where id = (v_line->>'invoice_item_id')::uuid;
    end if;
  end loop;

  -- ---- Replacement items: record, deduct stock ----
  for v_line in select * from jsonb_array_elements(p_replacement) loop
    v_prod := (v_line->>'product_id')::uuid;
    v_qty := (v_line->>'quantity')::integer;
    select selling_price into v_price from public.store_product_prices
     where store_id = p_processing_store_id and product_id = v_prod and is_active = true;
    insert into public.product_exchange_items (exchange_id, direction, product_id, quantity, unit_price, line_total)
    values (v_ex_id, 'replacement', v_prod, v_qty, v_price, v_price * v_qty);
    update public.store_inventory set current_qty = current_qty - v_qty, updated_at = now()
     where store_id = p_processing_store_id and product_id = v_prod;
    insert into public.stock_movements (product_id, movement_type, from_store_id, quantity, notes, created_by)
      values (v_prod, 'exchange_replacement_out', p_processing_store_id, v_qty, 'Exchange ' || v_no || ' — replacement', auth.uid());
  end loop;

  -- ---- Top-up payments ----
  if v_topup > 0 then
    for v_line in select * from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) loop
      insert into public.product_exchange_payments (exchange_id, payment_method_id, amount, reference)
      values (v_ex_id, nullif(v_line->>'payment_method_id', '')::uuid, (v_line->>'amount')::numeric, nullif(v_line->>'reference', ''));
    end loop;
  end if;

  perform public.write_audit_ex('product_exchanges', v_ex_id, 'exchange_completed', null,
    jsonb_build_object('exchange_no', v_no, 'kind', v_kind, 'returned', v_lines,
                       'credit', v_credit, 'replacement', v_repl, 'topup', v_topup, 'nonrefundable', v_nonref,
                       'credit_todays_price', round(v_todays, 2), 'credit_paid', round(v_paid, 2)),
    'exchanges', p_reason, p_processing_store_id);

  return jsonb_build_object('success', true, 'id', v_ex_id, 'exchange_no', v_no, 'kind', v_kind,
    'credit', v_credit, 'replacement', v_repl, 'topup', v_topup, 'nonrefundable', v_nonref);
end $function$
$def$;

  -- ══ create_exchange_with_details: the kinds, and the route to the new one ═
  c_wd_a1 constant text := $a$ if p_kind not in ('product','bundle','bundle_component') then
  raise exception 'Unknown exchange kind %',p_kind; end if;
$a$;
  c_wd_r1 constant text := $r$ -- 455: 'items', several returned items in any mix (create_items_exchange)
 if p_kind not in ('product','bundle','bundle_component','items') then
  raise exception 'Unknown exchange kind %',p_kind; end if;
$r$;
  c_wd_a2 constant text := $a$ else
  v_res:=public.create_bundle_component_exchange(
$a$;
  c_wd_r2 constant text := $r$ elsif p_kind='items' then
  -- 455 (the Owner, 22 Oct 2026: "Both kinds, any mix"): plain product lines
  -- and items of bundles returned together, in one exchange.
  v_res:=public.create_items_exchange(
    (p_payload->>'original_invoice_id')::uuid,(p_payload->>'processing_store_id')::uuid,
    coalesce(p_payload->'returned','[]'::jsonb),coalesce(p_payload->'replacement','[]'::jsonb),
    coalesce(p_payload->'payments','[]'::jsonb),p_payload->>'reason',p_payload->>'notes');
 else
  v_res:=public.create_bundle_component_exchange(
$r$;

  -- ══ exchange_invoice_details: the note ═════════════════════════════════════
  c_ed_a constant text := $a$    'reason', v_ex.reason,
$a$;
  c_ed_r constant text := $r$    'reason', v_ex.reason,
    -- 455 (the Owner, 22 Oct 2026): the exchange's note, which prints on its
    -- replacement invoice as on the exchange.
    'notes', v_ex.notes,
$r$;

  -- ══ Relied on, not changed (production, 22 Oct 2026, at 450) ═════════════
  c_relied constant text[] := array[
    'create_product_exchange(uuid,uuid,jsonb,jsonb,jsonb,text,text,boolean,uuid,text)',
    'create_bundle_component_exchange(uuid,uuid,uuid,uuid,integer,jsonb,jsonb,text,text)',
    'create_bundle_exchange(uuid,uuid,uuid,uuid,jsonb,text,text)',
    'create_exchange_invoice(uuid)',
    'trg_exchange_invoice()',
    'set_exchange_details(uuid,jsonb,jsonb,uuid,date,text)',
    'exchange_credit_value(uuid,uuid,uuid,integer)',
    'exchange_credit_preview(uuid,uuid)',
    'bundle_line_components(uuid)',
    'exchange_ineligibility_reason(uuid)',
    'exchange_assert_payments(jsonb,numeric,boolean)',
    'exchange_inherited_affiliate(uuid)',
    'exchange_invoice_hold(uuid,uuid[])',
    'trg_stock_return_exchange_hold()',
    'trg_invoice_item_exchange_hold()',
    'exchange_bundle_quote(uuid,uuid,uuid,uuid)',
    'user_has_store_access(uuid)',
    'current_user_role()',
    'require_active_staff(text[])',
    'require_store_access(uuid)',
    'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    'record_invoice_payment(uuid,jsonb,uuid)'];
  c_relied_md5 constant text[] := array[
    '48679d09a214c9dcf8850be51110d8bc',
    '8d588d7f856fca85356e293a8af3ecef',
    'c552d1734cd4e8052b113a6026d8a6b2',
    '6392abd80baad4b1a2a5069654c994c1',
    'f4a84ead2fd5fa51d2e50d70da206e38',
    'f317e42aae09809c46625f47eb884298',
    '8998ee93a6fce8ce3a82e2a8c49aa95a',
    '263bb91b1ed38c6b53767c4d0182595c',
    '794ad28556de3e53d945e9ff742697a0',
    '869985df7601d401df40f44c40dd2d6e',
    'd6fd63cf456a5f1557405e70a1e81440',
    'c08af4b9c6b1afd98ae5bb9f0628a81a',
    'd55f4696593447039aa45eeeae9b66d7',
    '6f9af8dd208b7203565ed1f5f90d781a',
    '41b69477b351c47a8070f25b61a8285f',
    '447b48555da3e278bf2adb4cde3c155b',
    '708992afaa6c3951f6329239b742987c',
    '519b0a33a3548f970c5d585b6e76a389',
    '877b3aa74cea559881979bb161c450e2',
    'f9332fd2f0092337d64501d8a647c23f',
    'c705c733e213a27f0dc32d54322cc855',
    '80c80d386a5241e63b353e35e13ef250',
    '9c70097ed4da614fb9dcc66fdfcdb7d6'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; d2 text; n int; k int; i int;
  v_anchors text[]; v_patches text[]; v_before text; v_after text;
  v_fns text[] := '{}'; v_defs text[] := '{}'; v_acl text[] := '{}'; v_new boolean := false;
  -- the self-test's made-up records
  t_sfx text; t_phones text[]; t_owner uuid; t_store uuid; t_cash uuid; t_buyer uuid;
  t_a uuid; t_b uuid; t_c uuid; t_d uuid; t_t uuid; t_ab uuid; t_inv uuid; t_bl uuid; t_dl uuid;
  t_res jsonb; t_ex uuid; t_exinv uuid; t_q int[]; t_msg text;
  t_note constant text := E'455 check note\nprinted on both copies';
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The new function's text is the tested one.
  if md5(c_h_def) <> c_h_after then
    raise exception '455: the text of public.% is not the tested one (md5 %)', c_h, md5(c_h_def); end if;

  -- The functions relied on are as read on production (22 Oct 2026, at 450).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '455: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;

  -- The columns the new function writes and reads, with these types.
  select string_agg(x.t || '.' || x.c, ', ') into v
    from (values ('product_exchanges', 'id', 'uuid'), ('product_exchanges', 'exchange_no', 'text'),
                 ('product_exchanges', 'original_invoice_id', 'uuid'), ('product_exchanges', 'customer_id', 'uuid'),
                 ('product_exchanges', 'processing_store_id', 'uuid'), ('product_exchanges', 'exchange_affiliate_id', 'uuid'),
                 ('product_exchanges', 'returned_credit_total', 'numeric(12,2)'), ('product_exchanges', 'replacement_total', 'numeric(12,2)'),
                 ('product_exchanges', 'topup_amount', 'numeric(12,2)'), ('product_exchanges', 'nonrefundable_amount', 'numeric(12,2)'),
                 ('product_exchanges', 'status', 'text'), ('product_exchanges', 'exchange_kind', 'text'),
                 ('product_exchanges', 'reason', 'text'), ('product_exchanges', 'notes', 'text'),
                 ('product_exchanges', 'created_by', 'uuid'), ('product_exchanges', 'locked_at', 'timestamp with time zone'),
                 ('product_exchange_items', 'exchange_id', 'uuid'), ('product_exchange_items', 'direction', 'text'),
                 ('product_exchange_items', 'original_invoice_item_id', 'uuid'), ('product_exchange_items', 'product_id', 'uuid'),
                 ('product_exchange_items', 'quantity', 'integer'), ('product_exchange_items', 'unit_price', 'numeric(12,2)'),
                 ('product_exchange_items', 'line_total', 'numeric(12,2)'),
                 ('product_exchange_payments', 'exchange_id', 'uuid'), ('product_exchange_payments', 'payment_method_id', 'uuid'),
                 ('product_exchange_payments', 'amount', 'numeric(12,2)'), ('product_exchange_payments', 'reference', 'text'),
                 ('invoice_items', 'id', 'uuid'), ('invoice_items', 'invoice_id', 'uuid'), ('invoice_items', 'line_kind', 'invoice_line_kind'),
                 ('invoice_items', 'product_id', 'uuid'), ('invoice_items', 'quantity', 'integer'),
                 ('invoice_items', 'exchanged_at', 'timestamp with time zone'), ('invoice_items', 'exchange_id', 'uuid'),
                 ('invoice_items', 'component_exchanged', 'jsonb'),
                 ('store_inventory', 'store_id', 'uuid'), ('store_inventory', 'product_id', 'uuid'),
                 ('store_inventory', 'current_qty', 'integer'), ('store_inventory', 'updated_at', 'timestamp with time zone'),
                 ('store_product_prices', 'store_id', 'uuid'), ('store_product_prices', 'product_id', 'uuid'),
                 ('store_product_prices', 'selling_price', 'numeric(12,2)'), ('store_product_prices', 'is_active', 'boolean'),
                 ('stock_movements', 'product_id', 'uuid'), ('stock_movements', 'movement_type', 'stock_movement_type'),
                 ('stock_movements', 'to_store_id', 'uuid'), ('stock_movements', 'from_store_id', 'uuid'),
                 ('stock_movements', 'quantity', 'integer'), ('stock_movements', 'notes', 'text'), ('stock_movements', 'created_by', 'uuid'),
                 ('products', 'id', 'uuid'), ('products', 'name', 'text'), ('products', 'product_type', 'product_type')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = to_regclass('public.' || x.t) and a.attname = x.c and a.attnum > 0
                        and not a.attisdropped and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '455: these columns are missing or not as read on 22 Oct 2026: %', v; end if;

  -- No other function takes these names (the API picks an overload by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('create_exchange_with_details', 'exchange_invoice_details', 'create_items_exchange')
     and p.oid::regprocedure::text not in (c_wd, c_ed, c_h);
  if v is not null then raise exception '455: another function takes the name of one this changes: %', v; end if;

  -- The new function: not there yet (created), or this version (left alone).
  if to_regprocedure('public.' || c_h) is not null then
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_h))) <> c_h_after then
      raise exception '455: public.% is there but not this version (md5 %). Nothing was changed.',
        c_h, md5(pg_get_functiondef(to_regprocedure('public.' || c_h))); end if;
  else
    v_new := true;
  end if;

  -- Each patched function: its BEFORE (patched; each anchor found once; the
  -- text built has its AFTER md5) or its AFTER (left alone).
  foreach v in array array[c_wd, c_ed] loop
    if to_regprocedure('public.' || v) is null then raise exception '455: public.% is missing', v; end if;
    if v = c_wd then
      v_anchors := array[c_wd_a1, c_wd_a2]; v_patches := array[c_wd_r1, c_wd_r2]; v_before := c_wd_before; v_after := c_wd_after;
    else
      v_anchors := array[c_ed_a]; v_patches := array[c_ed_r]; v_before := c_ed_before; v_after := c_ed_after;
    end if;
    d := pg_get_functiondef(to_regprocedure('public.' || v));
    if md5(d) = v_after then
      raise notice '455: public.% is already this version; left alone', v;
      continue;
    end if;
    d2 := d;
    for k in 1 .. cardinality(v_anchors) loop
      n := (length(d) - length(replace(d, v_anchors[k], ''))) / length(v_anchors[k]);
      if n <> 1 then
        raise exception '455: the anchor % of public.% is found % times, not once (md5 %). Re-read it and re-test before applying.', k, v, n, md5(d); end if;
      d2 := replace(d2, v_anchors[k], v_patches[k]);
    end loop;
    if md5(d) <> v_before then
      raise exception '455: public.% is not the version this was tested against (md5 %; patched it would be md5 %). Re-read it and re-test before applying.', v, md5(d), md5(d2); end if;
    if md5(d2) <> v_after then
      raise exception '455: the text built for public.% is not the tested one (md5 %)', v, md5(d2); end if;
    v_fns := v_fns || v;
    v_defs := v_defs || d2;
  end loop;

  -- The grants of the two, to compare after (as sets: production lists them
  -- in another order than a local copy does).
  foreach v in array array[c_wd, c_ed] loop
    v_acl := v_acl || (select coalesce(string_agg(x::text, ',' order by x::text), '')
                         from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || v));
  end loop;

  -- ── Install ───────────────────────────────────────────────────────────────
  -- The new function first: the patched router calls it.
  if v_new then
    execute c_h_def;
    execute format('revoke all on function public.%s from public, anon, authenticated', c_h);
    execute format('grant execute on function public.%s to service_role', c_h);
  else
    raise notice '455: public.% is already this version; left alone', c_h;
  end if;
  for k in 1 .. coalesce(cardinality(v_fns), 0) loop
    execute v_defs[k];
  end loop;

  -- ── Afterwards: installed exactly as tested, grants as before ────────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_h))) <> c_h_after then
    raise exception '455: public.% was installed with an md5 other than the tested one', c_h; end if;
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_wd))) <> c_wd_after
     or md5(pg_get_functiondef(to_regprocedure('public.' || c_ed))) <> c_ed_after then
    raise exception '455: public.% or public.% is not at its AFTER md5 (% / %)', c_wd, c_ed,
      md5(pg_get_functiondef(to_regprocedure('public.' || c_wd))), md5(pg_get_functiondef(to_regprocedure('public.' || c_ed))); end if;
  k := 0;
  foreach v in array array[c_wd, c_ed] loop
    k := k + 1;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || v)) is distinct from v_acl[k] then
      raise exception '455: the grants of public.% changed', v; end if;
  end loop;
  if (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_h))
     is distinct from (select array_agg(x::text order by x::text) from unnest(c_h_acl::aclitem[]) x)
     or has_function_privilege('anon', 'public.' || c_h, 'execute')
     or has_function_privilege('authenticated', 'public.' || c_h, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_h, 'execute') then
    raise exception '455: public.% is not the server''s alone', c_h; end if;
  if has_function_privilege('anon', 'public.' || c_wd, 'execute')
     or not has_function_privilege('authenticated', 'public.' || c_wd, 'execute')
     or has_function_privilege('anon', 'public.' || c_ed, 'execute')
     or not has_function_privilege('authenticated', 'public.' || c_ed, 'execute') then
    raise exception '455: who may call public.% or public.% is not as before', c_wd, c_ed; end if;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("455 check", @example.com, fictional ACMA phones
  -- no customer uses); it ends by raising P0455, which undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    t_phones := array(select p from unnest(array['+61491570737', '+61491572983', '+61491573770', '+61491570006']) p
                       where public.normalize_customer_phone(p) = p
                         and not exists (select 1 from public.customers c where c.phone = p)
                       order by p limit 1);
    if coalesce(cardinality(t_phones), 0) < 1 then raise exception '455: the self-test found no unused fictional phone'; end if;
    -- The shared settings row (commission rates) production has; a bare local
    -- copy may lack it.
    insert into public.app_settings default values on conflict do nothing;
    insert into auth.users (id, email) values (gen_random_uuid(), '455-check-' || t_sfx || '@example.com') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '455 check', '455-check-' || t_sfx || '@example.com', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('455 check ' || t_sfx, '455-' || t_sfx, 'SG') returning id into t_store;
    insert into public.payment_methods (name, is_active) values ('455 check cash ' || t_sfx, true) returning id into t_cash;
    insert into public.customers (full_name, phone) values ('455 Check Buyer ' || t_sfx, t_phones[1]) returning id into t_buyer;
    insert into public.products (name, sku, product_type) values ('455 check A ' || t_sfx, '455A-' || t_sfx, 'own') returning id into t_a;
    insert into public.products (name, sku, product_type) values ('455 check B ' || t_sfx, '455B-' || t_sfx, 'own') returning id into t_b;
    insert into public.products (name, sku, product_type) values ('455 check C ' || t_sfx, '455C-' || t_sfx, 'own') returning id into t_c;
    insert into public.products (name, sku, product_type) values ('455 check D ' || t_sfx, '455D-' || t_sfx, 'own') returning id into t_d;
    insert into public.products (name, sku, product_type) values ('455 check T ' || t_sfx, '455T-' || t_sfx, 'third_party') returning id into t_t;
    insert into public.store_inventory (store_id, product_id, current_qty)
      select t_store, p, 10 from unnest(array[t_a, t_b, t_c, t_d, t_t]) p;
    perform public.set_product_prices(t_store, x.p, x.v, x.v, 'available')
       from (values (t_a, 100::numeric), (t_b, 100), (t_c, 120), (t_d, 50), (t_t, 80)) x(p, v);
    insert into public.promotions (name, code, fixed_price) values ('455 check AB ' || t_sfx, '455AB-' || t_sfx, 150) returning id into t_ab;
    insert into public.promotion_items (promotion_id, item_type, product_id, quantity) values (t_ab, 'product', t_a, 1), (t_ab, 'product', t_b, 1);
    perform public.set_promotion_prices(t_ab, t_store, 150, 150, true);
    t_inv := public.create_invoice(t_store, t_buyer, null, jsonb_build_array(
      jsonb_build_object('kind', 'product', 'product_id', t_d, 'quantity', 1),
      jsonb_build_object('kind', 'promotion', 'promotion_id', t_ab, 'quantity', 1)), 0, null, null, null);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 200)), gen_random_uuid());
    select id into t_dl from public.invoice_items where invoice_id = t_inv and line_kind::text = 'product';
    select id into t_bl from public.invoice_items where invoice_id = t_inv and line_kind::text = 'promotion';
    t_q := array(select coalesce((select s.current_qty from public.store_inventory s where s.store_id = t_store and s.product_id = p), 0)
                   from unnest(array[t_a, t_b, t_c, t_d]) with ordinality u(p, o) order by o);

    -- D whole and A and B of the bundle, for two C, S$40 paid, with a note.
    t_res := public.create_exchange_with_details('items', jsonb_build_object(
      'original_invoice_id', t_inv, 'processing_store_id', t_store,
      'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', t_dl, 'quantity', 1),
                                    jsonb_build_object('invoice_item_id', t_bl, 'product_id', t_a, 'quantity', 1),
                                    jsonb_build_object('invoice_item_id', t_bl, 'product_id', t_b, 'quantity', 1)),
      'replacement', jsonb_build_array(jsonb_build_object('product_id', t_c, 'quantity', 2)),
      'payments', jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 40)),
      'reason', '455 check', 'notes', t_note, 'served_by', jsonb_build_array(t_owner::text)));
    t_ex := (t_res->>'id')::uuid;
    if t_res->>'exchange_no' not like 'EXC-%' or t_res->>'kind' <> 'items'
       or (select count(*) from public.product_exchanges where original_invoice_id = t_inv) <> 1
       or (select returned_credit_total::text || '/' || replacement_total::text || '/' || topup_amount::text || '/' || nonrefundable_amount::text
             from public.product_exchanges where id = t_ex) <> '200.00/240.00/40.00/0.00'
       or (select count(*)::text || '/' || sum(line_total)::text from public.product_exchange_items
            where exchange_id = t_ex and direction = 'returned') <> '3/200.00' then
      raise exception '455: the several-item exchange is not one exchange of S$200 credit in three rows (%)', t_res; end if;
    if array(select coalesce((select s.current_qty from public.store_inventory s where s.store_id = t_store and s.product_id = p), 0)
               from unnest(array[t_a, t_b, t_c, t_d]) with ordinality u(p, o) order by o)
       <> array[t_q[1] + 1, t_q[2] + 1, t_q[3] - 2, t_q[4] + 1] then
      raise exception '455: the stock did not move once per item'; end if;
    if (select exchange_id from public.invoice_items where id = t_dl) is distinct from t_ex
       or (select count(*) from public.invoice_items it, jsonb_array_elements(it.component_exchanged) e
            where it.id = t_bl and (e->>'exchange_id')::uuid = t_ex) <> 2 then
      raise exception '455: the plain line and the two bundle items are not marked exchanged'; end if;
    set constraints public.exchange_creates_invoice immediate;
    set constraints public.exchange_creates_invoice deferred;
    select id into t_exinv from public.invoices where exchange_id = t_ex and is_exchange;
    if (select count(*) from public.invoices where exchange_id = t_ex and is_exchange) <> 1
       or (select total_amount from public.invoices where id = t_exinv) <> 40
       or (select sum(line_discount) from public.invoice_items where invoice_id = t_exinv) <> 200 then
      raise exception '455: the exchange did not make ONE replacement invoice of S$40 with S$200 of credit'; end if;
    if public.exchange_invoice_details(t_exinv)->>'notes' is distinct from t_note then
      raise exception '455: exchange_invoice_details does not return the note (%)', public.exchange_invoice_details(t_exinv); end if;
    -- The same bundle item again, and own for third-party: refused.
    t_msg := null;
    begin
      perform public.create_exchange_with_details('items', jsonb_build_object(
        'original_invoice_id', t_inv, 'processing_store_id', t_store,
        'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', t_bl, 'product_id', t_a, 'quantity', 1)),
        'replacement', jsonb_build_array(jsonb_build_object('product_id', t_c, 'quantity', 1)),
        'reason', '455 check', 'served_by', jsonb_build_array(t_owner::text)));
    exception when others then t_msg := sqlerrm;
    end;
    if t_msg is distinct from 'That component has already been exchanged' then
      raise exception '455: an item exchanged already was not refused (%)', coalesce(t_msg, 'accepted'); end if;
    t_inv := public.create_invoice(t_store, t_buyer, null, jsonb_build_array(
      jsonb_build_object('kind', 'promotion', 'promotion_id', t_ab, 'quantity', 1)), 0, null, null, null);
    perform public.record_invoice_payment(t_inv, jsonb_build_array(jsonb_build_object('payment_method_id', t_cash, 'amount', 150)), gen_random_uuid());
    t_msg := null;
    begin
      perform public.create_exchange_with_details('items', jsonb_build_object(
        'original_invoice_id', t_inv, 'processing_store_id', t_store,
        'returned', jsonb_build_array(jsonb_build_object('invoice_item_id', (select id from public.invoice_items where invoice_id = t_inv),
                                                         'product_id', t_a, 'quantity', 1)),
        'replacement', jsonb_build_array(jsonb_build_object('product_id', t_t, 'quantity', 1)),
        'reason', '455 check', 'served_by', jsonb_build_array(t_owner::text)));
    exception when others then t_msg := sqlerrm;
    end;
    if t_msg is distinct from 'Own products may only be exchanged for own products, and third-party for third-party' then
      raise exception '455: own for third-party was not refused (%)', coalesce(t_msg, 'accepted'); end if;

    raise exception using errcode = 'P0455', message = '455: self-test done, undone';
  exception when sqlstate 'P0455' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
