-- 495_services_hold_no_stock.sql
--
-- A SERVICE HOLDS NO STOCK (the user, 6 Nov 2026: "As for service, since it is
-- service, it should not have stock.")
--
-- (The number 495 is this file's name, its errors' prefix, its self-test's
-- error code P0495 and its suite's; if it changes at commit, change it in these
-- places alone: the file name, the "495:" messages, P0495, the suite, the UNDO
-- file, and the "-- 495" comments in the patched functions.)
--
-- WHAT WAS WRONG
--
--   A Service is a product typed No commission (the user: "All the 'no
--   commission' will go to Service"; the Products page's Service tab, d5e2dcf).
--   The database treated it as any other product. Paying an invoice took it
--   from the store's stock, and refused the payment when there was none
--   ("Insufficient store stock"); the invoice form lists only products with
--   stock. So staff typed 1,000 as "Opening stock" on the services they sell:
--   made-up stock, which the Reports page counts as units on the shelf
--   (production, 6 Nov 2026, read only: 3 of the 7 services, 4 stock rows,
--   3,995 units).
--
-- WHAT THIS DOES
--
--   * product_is_service(id) (new): the one place that says what a Service is.
--   * invoice_required_stock: an invoice owes no stock for a service. Everything
--     that takes stock for an invoice reads it (or invoice_stock_to_deduct, which
--     reads it): full payment and its stock check, Confirm FOC, a correction, a
--     hand-over, the Goods panel, the store-change preview, the stock reports.
--     A promotion holding a service owes none for it either.
--   * A sale of a service from before this file (it took 1 of the made-up stock)
--     has nothing to give back: invoice_goods_out (the Goods panel, Record items
--     returned, the list's goods out, delete), restore_invoice_stock (a Cancel, a
--     correction) and the Finance panel's stock questions
--     (invoice_refund_options_before_sessions, and so the guided plan) leave it
--     out.
--   * refund_invoice_recorded: refunding a service line asks nothing about stock,
--     even on an invoice that also sold a real product; and a product line's
--     refund does not wait on an old sale of a service.
--   * Fulfil from a warehouse (trg_fulfil_from_warehouse and its setter
--     set_invoice_fulfilment_warehouse): a service line asks nothing of the
--     warehouse, and its stock is not "given back" to the store.
--   * trg_service_holds_no_stock (new), on store_inventory and
--     warehouse_inventory: stock cannot go up on a service, by any path (Stock In,
--     an approved adjustment, a transfer received, a return, the API, the SQL
--     editor). Going down is never stopped, so the made-up stock can be removed
--     with a normal adjustment, and a row at 0 (a low-stock threshold) is allowed.
--   * trg_product_becomes_service (new), on products: a product becomes a service
--     (its type changes to No commission) only when stock_retire_blockers says
--     nothing stands in the way: stock, an open transfer, stock out on loan, a
--     live promotion, a special product, a stock correction waiting for approval.
--     A service can go back to Own or 3rd Party at any time.
--
-- WHAT IT DOES NOT DO
--
--   * It changes no rows. The made-up stock is removed afterwards with a normal
--     adjustment (DEPLOY ORDER, step 4), with the user's go-ahead (given 6 Nov
--     2026: "Build, remove it").
--   * Past stock movements, invoices, prices and commission stay as they are. A
--     service still earns no commission, and is still a 'product' line on an
--     invoice. Nothing is added to or taken from an invoice's money.
--   * invoice_stock_components still records a service line (the trigger does not
--     read the type): invoice_required_stock is where it stops counting, so old
--     and new lines behave the same.
--
-- KNOWN
--
--   * A physical item typed No commission cannot hold stock: on 6 Nov 2026 all 7
--     are services.
--   * A whole-bundle exchange of a promotion holding a service puts its contents
--     back in stock, which trg_service_holds_no_stock refuses, in those words. No
--     promotion holds a service on 6 Nov 2026.
--   * A service changed back to Own or 3rd Party owes stock again on any open
--     invoice that has it, and the stock report lists its past sales.
--
-- DEPLOY ORDER
--
--   1. Dry run on a copy of production at this head (the suite, on a fresh copy).
--   2. Apply this file.
--   3. Deploy the pages (Invoice Service category, stock pages without services).
--      The old pages keep working in between: they still find the made-up stock.
--   4. Remove the made-up stock with a normal adjustment, as
--      scripts/products/remove-service-stock-495.sql does (its counted totals are
--      guarded, and it refuses anything else).
--
-- UNDO: scripts/products/undo-495.sql (the suite runs it). It does not bring the
-- made-up stock back.
--
-- Run: psql -X -v ON_ERROR_STOP=1 -d <copy> -f scripts/products/tests/service-no-stock-495.sql
do $mig$
declare
  -- The functions this patches: BEFORE (production now) and AFTER md5s
  c_sig constant text[] := array[
    'invoice_required_stock(uuid)',
    'invoice_goods_out(uuid)',
    'restore_invoice_stock(uuid,text)',
    'invoice_refund_options_before_sessions(uuid)',
    'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
    'trg_fulfil_from_warehouse()',
    'set_invoice_fulfilment_warehouse(uuid,uuid)'];
  c_before constant text[] := array[
    'c91dc1eb4f2b7b465de5fe4a8fb2ca0c',
    '15ffed0ff0d5d9cc5685af8e834302ae',
    '092316c3af22361f80d186e38fe49bf3',
    'bd3afcc79cd2f06f983607d54fed167c',
    '804ecd829cfecf713783a09a05d93c7e',
    'e1d41bce9c53d21ac2ab727042663cfb',
    '66bf7f38e06bf48116b63b71ca7663cb'];
  c_after constant text[] := array[
    'b14a1511d15457de4787df8d040e415f',
    'bb002119b3cb779a4b1c8bb79e08ae25',
    'fe23a3b4e428641b5aed19580614070a',
    '947f461d4581b2e7a32058b42c8250c4',
    '3280f4ed6afb93aed7366eaf100c6383',
    'ccc8ee71452ee75773a93fbe298bfe35',
    '817367d336fe41970118eb5ec8d71fc0'];
  -- Each patch: which function (its place in c_sig), the text found exactly once
  -- in it, and the text put in its place. The UNDO file swaps them back.
  c_fn constant int[] := array[1, 1, 2, 3, 4, 5, 5, 6, 7];
  c_anchor constant text[] := array[
$a$         or not exists (select 1 from public.invoices v where v.id = it.invoice_id and v.is_exchange))
   group by c.kind,c.item_id;$a$,
$a$   where x.product_id is null or r.quantity-x.quantity>0;$a$,
$a$     and m.movement_type::text = 'store_sale'
     and x.left_qty > 0$a$,
$a$from public.stock_movements m where m.invoice_id=p_invoice_id and m.movement_type::text='store_sale' order by m.id for update of m loop$a$,
$a$from public.stock_movements m join public.products p on p.id=m.product_id where m.invoice_id=i.id and m.movement_type::text='store_sale'),$a$,
$a$   if it.id is not null and it.line_kind in ('product','promotion') and jsonb_array_length(coalesce(p_stock,'[]'))=0$a$,
$a$    and exists(select 1 from public.stock_movements qs where qs.invoice_id=i.id and qs.movement_type::text='store_sale'$a$,
$a$     where ii.invoice_id = new.id and ii.line_kind = 'product' and ii.product_id is not null$a$,
$a$     where ii.invoice_id = p_invoice_id and ii.line_kind = 'product' and ii.product_id is not null$a$];
  c_new constant text[] := array[
$n$         or not exists (select 1 from public.invoices v where v.id = it.invoice_id and v.is_exchange))
    -- 495 (the user, 6 Nov 2026): a service holds no stock, so no invoice owes any
    -- for one, on its own line or inside a promotion.
    and not (c.kind='product' and public.product_is_service(c.item_id))
   group by c.kind,c.item_id;$n$,
$n$   where (x.product_id is null or r.quantity-x.quantity>0)
     -- 495: a service holds no stock, as above.
     and not (r.kind='product' and public.product_is_service(r.item_id));$n$,
$n$     and m.movement_type::text = 'store_sale'
     -- 495 (the user, 6 Nov 2026): a service holds no stock, so a sale of one from
     -- before 495 left nothing with the customer to return.
     and not public.product_is_service(m.product_id)
     and x.left_qty > 0$n$,
$n$from public.stock_movements m where m.invoice_id=p_invoice_id and m.movement_type::text='store_sale'
   -- 495 (the user, 6 Nov 2026): a service holds no stock, so a sale of one from
   -- before 495 puts nothing back.
   and not public.product_is_service(m.product_id) order by m.id for update of m loop$n$,
$n$from public.stock_movements m join public.products p on p.id=m.product_id where m.invoice_id=i.id and m.movement_type::text='store_sale'
   -- 495 (the user, 6 Nov 2026): a service holds no stock, so a sale of one from
   -- before 495 asks nothing.
   and not public.product_is_service(m.product_id)),$n$,
$n$   if it.id is not null and it.line_kind in ('product','promotion') and jsonb_array_length(coalesce(p_stock,'[]'))=0
    -- 495 (the user, 6 Nov 2026): a service line has no stock outcome to ask for,
    -- even with a real product on the invoice ...
    and not (it.line_kind='product' and public.product_is_service(it.product_id))$n$,
$n$    and exists(select 1 from public.stock_movements qs where qs.invoice_id=i.id and qs.movement_type::text='store_sale'
      -- 495: ... and an old sale of a service holds up no product line's refund.
      and not public.product_is_service(qs.product_id)$n$,
$n$     where ii.invoice_id = new.id and ii.line_kind = 'product' and ii.product_id is not null
       -- 495 (the user, 6 Nov 2026): a service holds no stock, so it asks nothing
       -- of the warehouse and the store is given nothing back for it.
       and not public.product_is_service(ii.product_id)$n$,
$n$     where ii.invoice_id = p_invoice_id and ii.line_kind = 'product' and ii.product_id is not null
       -- 495 (the user, 6 Nov 2026): a service holds no stock, so the warehouse need
       -- not cover it.
       and not public.product_is_service(ii.product_id)$n$];

  -- The functions this adds
  c_add_sig constant text[] := array['product_is_service(uuid)', 'trg_service_holds_no_stock()', 'trg_product_becomes_service()'];
  c_add_md5 constant text[] := array['17ff7af48b038d03b81e7957ef557943', '84d4ee855b8ebe7b751b00022f91265f', '2891939e0c79985b91df31808294a07a'];
  c_add_def constant text[] := array[
$d1$CREATE OR REPLACE FUNCTION public.product_is_service(p_product_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 495 (the user, 6 Nov 2026): a Service is a product typed No commission ("All
  -- the 'no commission' will go to Service"; the Products page's Service tab). It
  -- holds no stock. Internal: the stock functions and triggers call it.
  select exists (select 1 from public.products p
                  where p.id = p_product_id and p.product_type = 'no_commission')
$function$
$d1$,
$d2$CREATE OR REPLACE FUNCTION public.trg_service_holds_no_stock()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_name text;
begin
  -- 495 (the user, 6 Nov 2026): stock cannot go up on a service. Every path passes
  -- here: Stock In, an approved adjustment, a transfer received, a return, the API
  -- and the SQL editor. Going down is never stopped, so stock already there can be
  -- removed with a normal adjustment, and a row at 0 (a low-stock threshold) is
  -- allowed.
  if new.current_qty > 0
     and (tg_op = 'INSERT' or new.product_id is distinct from old.product_id or new.current_qty > old.current_qty) then
    select p.name into v_name from public.products p
     where p.id = new.product_id and p.product_type = 'no_commission';
    if found then raise exception '% is a service, so it holds no stock.', v_name; end if;
  end if;
  return new;
end $function$
$d2$,
$d3$CREATE OR REPLACE FUNCTION public.trg_product_becomes_service()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v text;
begin
  -- 495 (the user, 6 Nov 2026): a product becomes a service (its type changes to
  -- No commission) only when nothing stands in the way, as for switching it off:
  -- stock, an open transfer, stock out on loan, a live promotion, a special
  -- product, a stock correction waiting for approval. Every path passes here: the
  -- Products page, the API and the SQL editor.
  v := public.stock_retire_blockers('product', new.id);
  if v is not null then
    raise exception '% cannot become a service yet: a service holds no stock. Still open: %.', new.name, v;
  end if;
  return new;
end $function$
$d3$];

  -- The triggers this adds, as pg_get_triggerdef prints them
  c_trg_name constant text[] := array['service_holds_no_stock', 'service_holds_no_stock', 'products_become_service_check'];
  c_trg_table constant text[] := array['store_inventory', 'warehouse_inventory', 'products'];
  c_trg constant text[] := array[
    'CREATE TRIGGER service_holds_no_stock BEFORE INSERT OR UPDATE OF current_qty, product_id ON public.store_inventory FOR EACH ROW EXECUTE FUNCTION trg_service_holds_no_stock()',
    'CREATE TRIGGER service_holds_no_stock BEFORE INSERT OR UPDATE OF current_qty, product_id ON public.warehouse_inventory FOR EACH ROW EXECUTE FUNCTION trg_service_holds_no_stock()',
    'CREATE TRIGGER products_become_service_check BEFORE UPDATE OF product_type ON public.products FOR EACH ROW WHEN (((new.product_type = ''no_commission''::product_type) AND (old.product_type IS DISTINCT FROM ''no_commission''::product_type))) EXECUTE FUNCTION trg_product_becomes_service()'];

  -- Relied on, not changed (production now)
  c_relied constant text[] := array[
    'invoice_stock_to_deduct(uuid)',
    'deduct_invoice_stock(uuid,text)',
    'ensure_invoice_stock_deducted(uuid,text)',
    'stock_retire_blockers(text,uuid)'];
  c_relied_md5 constant text[] := array[
    '5480e6042b4521829ebce1ef14937162',
    '32183fe9e7c15ed0b11307c48289831a',
    '3c7ca7893f359f380a340cec07f21a1f',
    '7c2a2d19f96ddd3a05dd65f72dd15f63'];

  v_path text := current_setting('search_path');
  v_def text[] := array_fill(null::text, array[7]);
  v_make boolean[] := array_fill(false, array[7]);
  v_acl text[] := array_fill(null::text, array[7]);
  v_add_make boolean[] := array_fill(false, array[3]);
  d text; i int;
  -- the self-test's made-up records
  t_sfx text; t_base int; t_owner uuid; t_store uuid; t_wh uuid; t_cust uuid; t_svc uuid; t_prd uuid; t_inv uuid; t_refused boolean; t_got text;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- 1. Checks: nothing is changed before all of them pass
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '495: public.% is missing or not the version this was tested against. Re-read it and re-test before applying.', c_relied[i];
    end if;
  end loop;

  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                  where t.typname = 'product_type' and e.enumlabel = 'no_commission') then
    raise exception '495: the product type no_commission is missing'; end if;

  -- The functions it patches: BEFORE (patched) or AFTER (left alone).
  for i in 1 .. cardinality(c_sig) loop
    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '495: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '495: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      v_make[i] := true;
      v_def[i] := d;
    else
      raise exception '495: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- Each patch's text is found exactly once, and gives the tested text.
  for i in 1 .. cardinality(c_fn) loop
    if v_make[c_fn[i]] then
      if (length(v_def[c_fn[i]]) - length(replace(v_def[c_fn[i]], c_anchor[i], ''))) / length(c_anchor[i]) <> 1 then
        raise exception '495: patch % does not find its text exactly once in public.%', i, c_sig[c_fn[i]]; end if;
      v_def[c_fn[i]] := replace(v_def[c_fn[i]], c_anchor[i], c_new[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] and md5(v_def[i]) <> c_after[i] then
      raise exception '495: the patched text of public.% is not the tested one (md5 %)', c_sig[i], md5(v_def[i]); end if;
  end loop;

  -- The functions it adds: not there yet, or as tested.
  for i in 1 .. cardinality(c_add_sig) loop
    if md5(c_add_def[i]) <> c_add_md5[i] then
      raise exception '495: the text of public.% is not the tested one (md5 %)', c_add_sig[i], md5(c_add_def[i]); end if;
    if to_regprocedure('public.' || c_add_sig[i]) is null then
      v_add_make[i] := true;
    elsif md5(pg_get_functiondef(to_regprocedure('public.' || c_add_sig[i]))) <> c_add_md5[i] then
      raise exception '495: public.% is there already and is not this version (md5 %)', c_add_sig[i],
        md5(pg_get_functiondef(to_regprocedure('public.' || c_add_sig[i]))); end if;
  end loop;

  -- 2. Install: what they call comes first
  for i in 1 .. cardinality(c_add_sig) loop
    if v_add_make[i] then
      execute c_add_def[i];
      -- Functions are not endpoints (339): internal, as the other stock helpers.
      execute format('revoke all on function public.%s from public, anon, authenticated', c_add_sig[i]);
      execute format('grant execute on function public.%s to service_role', c_add_sig[i]);
    end if;
  end loop;
  for i in 1 .. cardinality(c_sig) loop
    if v_make[i] then execute v_def[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_trg) loop
    if not exists (select 1 from pg_trigger t where not t.tgisinternal and t.tgname = c_trg_name[i]
                    and t.tgrelid = ('public.' || c_trg_table[i])::regclass) then
      execute c_trg[i];
    end if;
  end loop;

  -- 3. Checks after installing
  for i in 1 .. cardinality(c_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '495: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    -- compared as sets: production lists them in another order than a local copy
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '495: the grants of public.% changed', c_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_add_sig) loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_add_sig[i]))) <> c_add_md5[i] then
      raise exception '495: public.% was installed with an md5 other than the tested one', c_add_sig[i]; end if;
    if has_function_privilege('anon', 'public.' || c_add_sig[i], 'execute')
       or has_function_privilege('authenticated', 'public.' || c_add_sig[i], 'execute')
       or not has_function_privilege('service_role', 'public.' || c_add_sig[i], 'execute') then
      raise exception '495: the grants of public.% are not as written', c_add_sig[i]; end if;
  end loop;
  for i in 1 .. cardinality(c_trg) loop
    if not exists (select 1 from pg_trigger t where not t.tgisinternal and t.tgenabled = 'O' and pg_get_triggerdef(t.oid) = c_trg[i]) then
      raise exception '495: this trigger is missing, switched off or not as tested: %', c_trg[i]; end if;
  end loop;

  -- 4. Self-test, in a block that is always undone
  -- Made-up records only ("495 Check", @example.invalid, a fictional +61 2 5550
  -- phone); the invoice is written straight to its table with its own number, so
  -- no sequence is used, and nothing is paid. It ends by raising P0495, which
  -- undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    -- A fictional phone no customer holds, in use or deleted. (range scans of the
    -- two partial phone indexes, as 486's)
    select min(g) into t_base from generate_series(2000, 9980, 10) g
     where not exists (select 1 from public.customers c
                        where c.deleted_at is null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'))
       and not exists (select 1 from public.customers c
                        where c.deleted_at is not null and public.normalize_customer_phone(c.phone)
                              between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 9)::text, 4, '0'));
    if t_base is null then raise exception '495: the self-test found no free fictional phone'; end if;
    insert into auth.users (id, email) values (gen_random_uuid(), '495chk-owner-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '495 Check Owner', '495chk-owner-' || t_sfx || '@example.invalid', 'owner', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', t_owner, 'role', 'authenticated')::text, true);
    insert into public.stores (name, code, country_code) values ('495 Check ' || t_sfx, '495-' || t_sfx, 'SG') returning id into t_store;
    insert into public.warehouses (name, code) values ('495 Check ' || t_sfx, '495-' || t_sfx) returning id into t_wh;
    insert into public.customers (full_name, phone) values ('495 Check', '+6125550' || lpad(t_base::text, 4, '0')) returning id into t_cust;
    insert into public.products (name, sku, product_type) values ('495 Check Service ' || t_sfx, '495-S-' || t_sfx, 'no_commission') returning id into t_svc;
    insert into public.products (name, sku, product_type) values ('495 Check Product ' || t_sfx, '495-P-' || t_sfx, 'own') returning id into t_prd;
    insert into public.invoices (invoice_no, store_id, customer_id, created_by)
    values ('495-CHECK-' || t_sfx, t_store, t_cust, t_owner) returning id into t_inv;
    insert into public.invoice_items (invoice_id, line_kind, product_id, quantity, unit_price, line_total)
    values (t_inv, 'product', t_svc, 1, 10, 10), (t_inv, 'product', t_prd, 2, 10, 20);

    -- An invoice owes stock for the product and not for the service, both ways of
    -- counting it.
    select string_agg(r.item_id::text || ' ' || r.quantity, ', ') into t_got from public.invoice_required_stock(t_inv) r;
    if t_got is distinct from t_prd::text || ' 2' then raise exception '495: the invoice owes %', coalesce(t_got, 'nothing'); end if;
    update public.invoices set stock_snapshot_version = null where id = t_inv;
    select string_agg(r.item_id::text || ' ' || r.quantity, ', ') into t_got from public.invoice_required_stock(t_inv) r;
    if t_got is distinct from t_prd::text || ' 2' then raise exception '495: the invoice, no snapshot, owes %', coalesce(t_got, 'nothing'); end if;
    update public.invoices set stock_snapshot_version = 1 where id = t_inv;

    -- A sale of the service from before 495 has nothing to give back or to ask.
    insert into public.stock_movements (product_id, movement_type, from_store_id, invoice_id, quantity, notes)
    values (t_svc, 'store_sale', t_store, t_inv, 1, '495 check');
    if exists (select 1 from public.invoice_goods_out(t_inv)) then raise exception '495: an old service sale counts as goods out'; end if;
    if public.restore_invoice_stock(t_inv, '495 check') <> 0 then raise exception '495: a Cancel puts an old service sale back'; end if;
    if jsonb_array_length(public.invoice_refund_options_before_sessions(t_inv)->'stock') <> 0 then
      raise exception '495: the refund asks about an old service sale'; end if;

    -- Stock cannot go up on a service, in a store or a warehouse; 0 is allowed.
    t_refused := false;
    begin
      insert into public.store_inventory (store_id, product_id, current_qty) values (t_store, t_svc, 1);
    exception when others then t_refused := sqlerrm like '%is a service, so it holds no stock.'; end;
    if not t_refused then raise exception '495: a store took stock of a service'; end if;
    t_refused := false;
    begin
      insert into public.warehouse_inventory (warehouse_id, product_id, current_qty) values (t_wh, t_svc, 1);
    exception when others then t_refused := sqlerrm like '%is a service, so it holds no stock.'; end;
    if not t_refused then raise exception '495: a warehouse took stock of a service'; end if;
    insert into public.store_inventory (store_id, product_id, current_qty) values (t_store, t_svc, 0);

    -- A product holding stock cannot become a service; one holding none can.
    insert into public.store_inventory (store_id, product_id, current_qty) values (t_store, t_prd, 3);
    t_refused := false;
    begin
      update public.products set product_type = 'no_commission' where id = t_prd;
    exception when others then t_refused := sqlerrm like '%cannot become a service yet%'; end;
    if not t_refused then raise exception '495: a product holding stock became a service'; end if;
    update public.store_inventory set current_qty = 0 where store_id = t_store and product_id = t_prd;
    update public.products set product_type = 'no_commission' where id = t_prd;

    raise exception using errcode = 'P0495', message = '495: self-test done, undone';
  exception when sqlstate 'P0495' then null;
  end;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
