-- 452_transfers_need_no_store_price.sql
--
-- A TRANSFER INTO A STORE NO LONGER NEEDS THE STORE TO HAVE A PRICE FOR THE
-- PRODUCT (the owner's change list, 22 Oct 2026, item 11)
--
-- WHAT WAS WRONG / WHY
--
--   Migration 46 added a rule that a product cannot be moved into a store
--   until the store has a price for it ("or the stock cannot be sold on
--   arrival", 97 and 159). 69, 97 and 159 carried it forward: every transfer
--   into a store calls assert_transfer_prices_ok, which raised "Cannot
--   transfer to this store — missing prices: <name> (no price row for this
--   store)". The Transfers page copied the rule by leaving such products out
--   of its lists, so a store with no price list was offered no products at
--   all. Reproduced on a copy of production (22 Oct 2026, made-up records):
--   an Owner's Warehouse → Store request for a product with no price at the
--   store was refused.
--   The rule protects nothing: selling already checks for a price
--   (create_invoice: 'No price set for "%" in this store'; create_product_
--   exchange refuses an unpriced replacement), stock-in and adjustments into a
--   store need no price, and no transfer stores or reads a price (no price or
--   value column on transfer_requests, transfer_request_lines,
--   transfer_line_sources or stock_movements; the transfer reports and the
--   Xero export read none).
--
-- THE RULES (binding: the owner, 22 Oct 2026)
--
--   * "A transfer must work even when the destination store has no price for
--     the product."
--   * The transfer screen lists every product and tags the unpriced ones "No
--     price at this store — set one in Price List before selling" (the
--     owner accepted the recommendation).
--   * "No reminder after receipt."
--   * Selling still needs a price: create_invoice already refuses an unpriced
--     product, and is not changed.
--
-- WHAT THIS DOES
--
--   assert_transfer_prices_ok(uuid,uuid[]) (the service role's alone; only the
--   transfer functions call it) keeps its signature, language, volatility,
--   security and settings, and its body now returns without raising (one
--   comment says why). Its five callers are left as they are, so a product
--   with no price at the destination store now goes through each of them:
--   create_transfer_request and create_staff_transfer_request (the page's New
--   Transfer), edit_transfer_request (Edit), review_and_dispatch_transfer
--   (Review, the products added there included) and
--   create_deferred_transfer_request (the service role's; the app does not
--   call it). receive_transfer never checked a price: the stock arrives at
--   the store as before.
--   The page (src/pages/TransfersPage.tsx, not this file) lists every product
--   in New Transfer, Edit and Review's Add Product, tags an unpriced one with
--   the owner's words (and a requested line Review shows), and reads the
--   store prices in pages of a thousand (it read only the first thousand
--   rows, so products that had a price could be left out too). The Price
--   List page's two hints no longer say a price is needed to transfer in.
--
-- NOT CHANGED
--
--   * The five callers, receive_transfer and every other transfer function:
--     source stock, allocation, dispatch, receipt, discrepancies, staff store
--     access, the 364 return rules. Their md5s are pinned below and checked
--     again after.
--   * Selling: create_invoice and product_price_for (an active, not deleted
--     price row at the store) are pinned and unchanged; the self-test checks
--     the invoice still refuses the product at that store.
--   * transfer_price_blockers(uuid,uuid[]) (69) is left as it is; nothing
--     calls it any more (only assert_transfer_prices_ok's old text did). The
--     old trigger function trg_block_unpriced_store_stock (attached to
--     nothing) is left as it is.
--   * No table, column, row or grant. assert_transfer_prices_ok keeps its
--     grant (create or replace keeps it; checked after).
--
-- NOT COVERED (to tell the owner)
--
--   * Unpriced stock can now arrive at a store and wait there, unsellable,
--     until a price is set in Price List: as stock-in and adjustments into a
--     store could already. Nothing reminds anyone after receipt (the owner's
--     answer). The tag on the transfer screen is the only warning.
--   * The tag reads a price as the invoice does (an active, not deleted row
--     at that store). The old database check counted an inactive or deleted
--     row as a price; it checks nothing now.
--   * Staff can request an unpriced product too (the owner chose to list every
--     product, not to keep it for Owners and Managers).
--   * A later clean-up could drop transfer_price_blockers and
--     trg_block_unpriced_store_stock, both unused (not done here: nothing is
--     dropped).
--
-- DEPLOY ORDER (each step with the owner's go-ahead)
--
--   Production now (after 450: 63219badeea67a5d401d5af2aeb88f19, 1371
--   functions) -> 452. No other item of the 22 Oct change list, as
--   investigated, changes the functions this file pins (the printed invoice
--   note patches create_invoice_with_details, not create_invoice); if one
--   goes in first and changes any of them, this file refuses, changing
--   nothing: re-read and re-test it then.
--   1. Dry run on a copy of production as it is then: apply this file twice.
--      The first run ends at the fingerprint below; the second says "already
--      this version; left alone" and changes nothing.
--   2. Apply this file (the CLI, or the MCP's apply_migration with this text
--      verbatim). It checks itself.
--   3. Then deploy the page (TransfersPage.tsx and PriceListPage.tsx's two
--      hints). Before 452 is in, the page would offer an unpriced product
--      that the server still refuses ("Cannot transfer to this store —
--      missing prices"), so the database goes first.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the replacement text is the tested one (its AFTER md5);
--   * assert_transfer_prices_ok is its BEFORE (46's text, as on production:
--     replaced) or its AFTER (left alone, so a second run changes nothing);
--     anything else is refused; no other function takes its name;
--   * the functions it relies on are as read on production (below);
--   * afterwards: its md5 is the AFTER one, its grant is the same set as
--     before and still the service role's alone (not anon's, not signed-in
--     staff's), and the relied-on functions still have their md5s;
--   * then a self-test, in a block that is always undone (it ends by raising
--     P0452, so it leaves no row): a made-up Owner, warehouse (20 units),
--     store and product with no price at the store, and a customer (a
--     fictional ACMA phone no customer has): an Owner's Warehouse → Store
--     request for 2 is created, reviewed and dispatched, and received in
--     full (status received; the store holds 2, the warehouse 18); an
--     invoice for it at that store is still refused ("No price set for").
--   Locks: assert_transfer_prices_ok's catalogue row, to the end of the
--   apply. A transfer running at that moment finishes on the text it started
--   with.
--
-- BEFORE (production after 450, 22 Oct 2026, read on a copy; md5 of
-- pg_get_functiondef with search_path public)
--   changed
--   assert_transfer_prices_ok(uuid,uuid[])                          9eb52cd482756e9f3355ddd8066da86d  (46)
--   relied on, not changed
--   create_transfer_request(text,text,uuid,text,uuid,jsonb,text)   99d7e65385165464fb6e4395f4d4c25f  (a caller; the self-test)
--   create_staff_transfer_request(jsonb,text,uuid)                 cc32ec91b2e223c67da957dd792af12e  (a caller, 421)
--   edit_transfer_request(uuid,integer,text,location_type,uuid,location_type,uuid,jsonb,text)
--                                                                  d9cec0b343afaea0171952cbcda80b61  (a caller, 421)
--   review_and_dispatch_transfer(uuid,jsonb,text)                  6db84d9ecca1d40b4858b4291401fbc0  (a caller, 364; the self-test)
--   create_deferred_transfer_request(location_type,uuid,jsonb,text) 17a3ab718ac521d0fbd89e73c00d3f9e  (a caller, the service role's)
--   receive_transfer(uuid,jsonb,text,boolean)                      04be775f33e550da46a7ed8054b359ce  (the self-test)
--   create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)   80c80d386a5241e63b353e35e13ef250  (still refuses; the self-test)
--   product_price_for(uuid,uuid,boolean)                           c6ece3be741f0b3849c9f5679c27a400  (the price the invoice reads)
--   public function fingerprint, production now (450 in)           63219badeea67a5d401d5af2aeb88f19 (1371 functions)
-- AFTER (for later guards)
--   assert_transfer_prices_ok(uuid,uuid[])                          5ffab5ce54c8456886b6a77f5663218a
--   public function fingerprint, on a copy of production (22 Oct 2026):
--     production now (450 in) -> 452 (a second run the same)       e5024e82f6079001d67c8a3b167138a9 (1371 functions: none added or dropped)
--
-- Test: scripts/transfers/tests/no-store-price-452.sql (begin ... rollback; it
-- installs this file twice; -v skip_install=1 where it is in): an unpriced
-- product through an Owner's Warehouse → Store and Store → Store request, a
-- Staff request, an edit to an unpriced store, Review's added product,
-- dispatch and receipt (the stock rises), and create_invoice still refusing it
-- at that store until a price is set. store-to-warehouse.sql and
-- discrepancy-sources.sql (they set prices) pass with it, and
-- scripts/permissions/tests/function-grants.sql and staff-only-functions.sql
-- pass after it. Fixtures only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The function this replaces: BEFORE (46, as on production) and AFTER ══
  c_sig constant text := 'assert_transfer_prices_ok(uuid,uuid[])';
  c_before constant text := '9eb52cd482756e9f3355ddd8066da86d';
  c_after constant text := '5ffab5ce54c8456886b6a77f5663218a';
  c_acl constant text := '{postgres=X/postgres,service_role=X/postgres}';
  c_def constant text :=
$def$CREATE OR REPLACE FUNCTION public.assert_transfer_prices_ok(p_store_id uuid, p_product_ids uuid[])
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 452 (the owner, 22 Oct 2026): a transfer into a store goes through whether
-- or not the store has a price for the product. This check, called by every
-- transfer into a store (create_transfer_request,
-- create_staff_transfer_request, edit_transfer_request,
-- review_and_dispatch_transfer, create_deferred_transfer_request), no longer
-- refuses anything. Selling still needs a price: create_invoice refuses a
-- product with no price at the store ("No price set for ... in this store"),
-- so the stock waits there, unsold, until one is set in Price List.
begin
  return;
end $function$
$def$;

  -- ══ What it relies on and does not change: as on production (22 Oct 2026) ══
  c_relied constant text[] := array[
    'create_transfer_request(text,text,uuid,text,uuid,jsonb,text)',
    'create_staff_transfer_request(jsonb,text,uuid)',
    'edit_transfer_request(uuid,integer,text,location_type,uuid,location_type,uuid,jsonb,text)',
    'review_and_dispatch_transfer(uuid,jsonb,text)',
    'create_deferred_transfer_request(location_type,uuid,jsonb,text)',
    'receive_transfer(uuid,jsonb,text,boolean)',
    'create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    'product_price_for(uuid,uuid,boolean)'];
  c_relied_md5 constant text[] := array[
    '99d7e65385165464fb6e4395f4d4c25f',
    'cc32ec91b2e223c67da957dd792af12e',
    'd9cec0b343afaea0171952cbcda80b61',
    '6db84d9ecca1d40b4858b4291401fbc0',
    '17a3ab718ac521d0fbd89e73c00d3f9e',
    '04be775f33e550da46a7ed8054b359ce',
    '80c80d386a5241e63b353e35e13ef250',
    'c6ece3be741f0b3849c9f5679c27a400'];

  v_path text := current_setting('search_path');
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_crole text := current_setting('request.jwt.claim.role', true);
  v text; d text; i int; v_install boolean := false; v_acl text;
  -- the self-test's made-up records
  t_sfx text; t_phone text; t_owner uuid; t_store uuid; t_wh uuid; t_prod uuid; t_cust uuid;
  t_req uuid; t_line uuid; t_msg text;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── Checks: nothing is changed before all of them pass ──────────────────
  -- The replacement text is the tested one.
  if md5(c_def) <> c_after then
    raise exception '452: the text of public.% is not the tested one (md5 %)', c_sig, md5(c_def); end if;

  -- The functions relied on are as read on production (22 Oct 2026).
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '452: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;

  -- No other function takes its name (the callers pick it by name).
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'assert_transfer_prices_ok'
     and p.oid::regprocedure::text <> c_sig;
  if v is not null then raise exception '452: another function takes the name of the one this changes: %', v; end if;

  -- The function: its BEFORE (replaced) or its AFTER (left alone).
  if to_regprocedure('public.' || c_sig) is null then
    raise exception '452: public.% is missing (is 46 applied?)', c_sig; end if;
  d := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  if md5(d) = c_after then
    raise notice '452: public.% is already this version; left alone', c_sig;
  elsif md5(d) <> c_before then
    raise exception '452: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig, md5(d);
  else
    v_install := true;
  end if;
  -- Its grant, to compare after (as a set: production may list it in another
  -- order than a local copy does).
  v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig));

  -- ── Install ───────────────────────────────────────────────────────────────
  if v_install then execute c_def; end if;

  -- ── Afterwards: installed exactly as tested, grant as before ────────────
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_after then
    raise exception '452: public.% was installed with an md5 other than the tested one', c_sig; end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig)) is distinct from v_acl
     or (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig))
        is distinct from (select array_agg(x::text order by x::text) from unnest(c_acl::aclitem[]) x)
     or has_function_privilege('anon', 'public.' || c_sig, 'execute')
     or has_function_privilege('authenticated', 'public.' || c_sig, 'execute')
     or not has_function_privilege('service_role', 'public.' || c_sig, 'execute') then
    raise exception '452: the grant of public.% changed (it is the service role''s alone)', c_sig; end if;
  for i in 1 .. cardinality(c_relied) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '452: public.% changed while this was applied', c_relied[i]; end if;
  end loop;

  -- ── Self-test, in a block that is always undone ─────────────────────────
  -- Made-up records only ("452 check", @example.invalid, a fictional ACMA
  -- phone no customer uses); it ends by raising P0452, which undoes all it
  -- wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    select p into t_phone from unnest(array['+61491570737', '+61491572983', '+61491573770', '+61491570006']) p
     where public.normalize_customer_phone(p) = p
       and not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = p)
     order by p limit 1;
    if t_phone is null then raise exception '452: the self-test found no unused fictional phone'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '452-check-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '452 check', '452-check-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    insert into public.stores (name, code, country_code) values ('452 check ' || t_sfx, '452-' || t_sfx, 'SG') returning id into t_store;
    insert into public.warehouses (name, code) values ('452 check ' || t_sfx, '452W-' || t_sfx) returning id into t_wh;
    insert into public.products (name, sku, product_type) values ('452 Check Pillow', '452-P-' || t_sfx, 'own') returning id into t_prod;
    insert into public.warehouse_inventory (warehouse_id, product_id, current_qty) values (t_wh, t_prod, 20);
    insert into public.customers (full_name, phone) values ('452 Check Buyer ' || t_sfx, t_phone) returning id into t_cust;
    if exists (select 1 from public.store_product_prices sp where sp.store_id = t_store and sp.product_id = t_prod) then
      raise exception '452: the self-test''s product has a price at its store'; end if;

    -- An Owner's Warehouse → Store request, reviewed, dispatched and received.
    t_req := (public.create_transfer_request('warehouse_to_store', 'warehouse', t_wh, 'store', t_store,
                jsonb_build_array(jsonb_build_object('line_kind', 'product', 'product_id', t_prod, 'quantity', 2)), '452 check')->>'id')::uuid;
    select l.id into t_line from public.transfer_request_lines l where l.transfer_request_id = t_req;
    perform public.review_and_dispatch_transfer(t_req, jsonb_build_array(jsonb_build_object('line_id', t_line, 'approved_quantity', 2,
      'sources', jsonb_build_array(jsonb_build_object('source_type', 'warehouse', 'source_id', t_wh, 'quantity', 2)))), '452 check');
    perform public.receive_transfer(t_req, null, '452 check', true);
    if (select r.status::text from public.transfer_requests r where r.id = t_req) <> 'received'
       or (select s.current_qty from public.store_inventory s where s.store_id = t_store and s.product_id = t_prod) is distinct from 2
       or (select w.current_qty from public.warehouse_inventory w where w.warehouse_id = t_wh and w.product_id = t_prod) is distinct from 18 then
      raise exception '452: the unpriced product''s transfer did not arrive as tested (status %)',
        (select r.status from public.transfer_requests r where r.id = t_req); end if;

    -- Selling it there is still refused.
    t_msg := null;
    begin
      perform public.create_invoice(t_store, t_cust, null,
        jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', t_prod, 'quantity', 1)));
    exception when others then t_msg := sqlerrm;
    end;
    if t_msg is null or t_msg not like 'No price set for "452 Check Pillow" in this store%' then
      raise exception '452: an invoice for the unpriced product was not refused as tested (%)', coalesce(t_msg, 'created'); end if;

    raise exception using errcode = 'P0452', message = '452: self-test done, undone';
  exception when sqlstate 'P0452' then null;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_crole, ''), true);

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
