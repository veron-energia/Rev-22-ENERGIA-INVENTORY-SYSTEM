-- 483_chosen_promotion_takes_its_stock.sql
--
-- A PROMOTION PICKED IN A CHOICE GROUP (A BLIND BOX'S PRIZE) TAKES ITS
-- PRODUCTS OUT OF STOCK
--
-- (The number 483 is this file's name, its errors' prefix, its self-test's
-- error code P0483 and its suite's; if it changes at commit, change it in
-- these places alone.)
--
-- WHAT WAS WRONG
--
--   346 let a choice group offer promotions, 347 let the till accept such a
--   pick and 349 let it record one (invoice_promotion_selections.
--   child_promotion_id). 349 said, of the pick it stored, that "the chosen
--   item contributes nothing to the stock components captured from
--   selections", and nothing has changed that since: the selection branch of
--   capture_invoice_stock_components records a product picked directly, or a
--   limited voucher, and nothing else. invoice_required_stock reads only those
--   components, so ensure_invoice_stock_deducted never takes a chosen
--   promotion's products out of stock.
--
--   The blind boxes are exactly that: each ($50, $100, $200, $500, $1,886) is
--   one group, "Choose your blind box products", whose options are promotions
--   (e.g. "Corset + Knee Brace + MEOL x 20"). Found on production, 31 Oct
--   2026, in a check of October's invoices against their stock: all 12 blind
--   box lines ever sold (10 on 22-23 Sep, INV-2026-0415 and INV-2026-0416 on
--   19 Oct) record their prize and have no stock component, and none took
--   anything out of stock. Every other promotion line, product line and pick
--   of October took exactly its stock.
--
-- WHAT THIS DOES
--
--   The selection branch also records a picked promotion with what it holds:
--   promotion_stock_items(child, the pick's quantity), the same function and
--   the same rule the line's own included items follow (products, and
--   vouchers only when limited; a promotion nested inside the prize is
--   expanded too). A product that is both picked directly and inside a
--   picked promotion becomes one component, summed (the components are
--   unique per line, kind, item and source). Nothing else in the function
--   changes.
--
--   So from now on a blind box's prize is taken out of the store's stock
--   when the invoice is paid in full, like any promotion's contents, and a
--   refund, cancellation or exchange of the line finds those products where
--   every other reader looks for them (invoice_line_stock_products already
--   lists a chosen promotion's products, since 361).
--
-- WHAT IT DOES NOT DO
--
--   * The 12 blind box lines already sold are left as they are: no
--     components are added to them and no stock is taken. Back-filling their
--     components would make invoice_required_stock report stock owed that the
--     next settlement or correction of the invoice would then take, at that
--     moment, after the shelves were counted. Whether to take INV-2026-0415's
--     Corset 2.0 and Knee Brace out of the Van is a separate repair, with its
--     own go-ahead. A later edit that rewrites one of those lines' picks would
--     record its prize, and the settlement after it would take the prize.
--   * Paying an invoice whose prize is not in the store's stock is refused,
--     as for any product ("Insufficient store stock for ... (have 1, need 2
--     incl. bundles). Payment blocked."). At a roadshow, the Van needs the
--     prizes in its stock before the sale.
--   * invoice_stock_component_evidence and invoice_required_stock_legacy, which
--     read only invoices recorded before stock snapshots (stock_snapshot_version
--     null, older than any promotion offered in a choice group), are not
--     changed.
--
-- DEPLOY ORDER (each step with the Owner's go-ahead)
--
--   production now (480 in: 6a7a72ebbb3a21e3a0df0ddd84efbcce, 1396 functions)
--   -> 483 (this file).
--   * Other sessions hold 479 and 481 (therapy refunds; stock a settlement
--     takes after a refund) and 482 (downline bookings). None of them changes
--     capture_invoice_stock_components, promotion_stock_items or
--     invoice_required_stock, so the order does not matter; if one goes
--     first, the fingerprints below differ (re-work them out from production's
--     md5 list) but nothing this file checks does.
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the first run ends at the fingerprint below, the second changes
--      nothing ("already this version; left alone").
--   2. Apply (the MCP's apply_migration with this text verbatim, or the CLI).
--      It checks itself and runs its self-test.
--   3. No page change.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * the functions it relies on are as read on production (31 Oct 2026),
--     the two triggers that call it are as read there, and the columns and
--     the unique key it writes are there;
--   * capture_invoice_stock_components is its BEFORE (replaced; the text
--     written here has the tested AFTER md5) or its AFTER (left alone);
--   * afterwards: the md5 is the AFTER one, the grants are as before
--     (compared as sets; only the owner and the service role may call it, as
--     a trigger function), and it is still a security definer trigger;
--   * then a self-test, in a block that is always undone (it ends by raising
--     P0483, so it leaves no row): a made-up box offering two made-up
--     promotions, and a product group, on a made-up invoice (written straight
--     to the tables with its own number, so no sequence is used and no stock
--     is touched); the components and invoice_required_stock follow each pick
--     as it is added, changed and taken off.
--   Locks: the function's catalogue row and the self-test's own rows. An
--   invoice being saved at that moment finishes first or waits (the lock
--   timeout gives up after 5 s and changes nothing).
--
-- BEFORE (production now, 31 Oct 2026; md5 of pg_get_functiondef with
-- search_path public)
--   changed:
--   * capture_invoice_stock_components(): 9f68df58f5cefced3cd68eb62a8877a7
--     (as at 177)
--   relied on, not changed:
--   * promotion_stock_items(uuid,integer): 82dd6bdac5566fce0b75470eb45444d1
--     (the new branch)
--   * invoice_required_stock(uuid): c91dc1eb4f2b7b465de5fe4a8fb2ca0c (the
--     self-test)
--   * public function fingerprint, production now:
--     6a7a72ebbb3a21e3a0df0ddd84efbcce (1396 functions)
-- AFTER (for later guards)
--   * capture_invoice_stock_components(): a7922878b6b73925de975bb7fa51ea1d
--   * public function fingerprint, production now -> 483 (a second run the
--     same): 93185a28ecc013afa5214340fdb2fa04 (1396 functions: one
--     replaced). Worked out on a copy of production at 480 (rc480_live,
--     6a7a72eb) and confirmed on the dry runs.
--
-- Test: scripts/promotions/tests/chosen-promotion-takes-stock-483.sql (begin
-- ... rollback; it installs this file twice, then sells, pays, corrects and
-- refunds blind boxes through the app's own calls). Fixtures only (the
-- repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The function this replaces: BEFORE (production now) and AFTER md5s ══
  c_sig constant text := 'capture_invoice_stock_components()';
  c_before constant text := '9f68df58f5cefced3cd68eb62a8877a7';
  c_after constant text := 'a7922878b6b73925de975bb7fa51ea1d';
  c_def constant text :=
$d1$CREATE OR REPLACE FUNCTION public.capture_invoice_stock_components()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.invoice_items%rowtype; v_id uuid;
begin
 if tg_table_name='invoice_items' then
  if tg_op='UPDATE' then
   if (new.line_kind,new.product_id,new.voucher_id,new.promotion_id,new.premium_bundle_id) is not distinct from
      (old.line_kind,old.product_id,old.voucher_id,old.promotion_id,old.premium_bundle_id) then
    if new.quantity<>old.quantity then
      update public.invoice_stock_components set quantity=quantity/old.quantity*new.quantity
       where invoice_item_id=new.id and component_source='fixed';
    end if;
    return new;
   end if;
  end if;
  it:=new;
  if not exists(select 1 from public.invoices where id=it.invoice_id and stock_snapshot_version=1) then return new; end if;
  delete from public.invoice_stock_components where invoice_item_id=it.id and component_source='fixed';
  if it.line_kind='product' and it.product_id is not null then
   insert into public.invoice_stock_components(invoice_item_id,kind,item_id,quantity,component_source) values(it.id,'product',it.product_id,it.quantity,'fixed');
  elsif it.line_kind='voucher' and exists(select 1 from public.vouchers where id=it.voucher_id and qty_type='limited') then
   insert into public.invoice_stock_components(invoice_item_id,kind,item_id,quantity,component_source) values(it.id,'voucher',it.voucher_id,it.quantity,'fixed');
  elsif it.line_kind='promotion' and it.promotion_id is not null then
   insert into public.invoice_stock_components(invoice_item_id,kind,item_id,quantity,component_source)
    select it.id,r.kind,r.item_id,sum(r.quantity)::int,'fixed' from public.promotion_stock_items(it.promotion_id,it.quantity) r group by r.kind,r.item_id;
  end if;
  return new;
 end if;
 v_id:=case when tg_op='DELETE' then old.invoice_item_id else new.invoice_item_id end;
 select * into it from public.invoice_items where id=v_id;
 if exists(select 1 from public.invoices where id=it.invoice_id and stock_snapshot_version=1) then
  delete from public.invoice_stock_components where invoice_item_id=v_id and component_source='selection';
  -- 483: a promotion picked in a choice group (a blind box's prize) is
  -- recorded with what it holds, as promotion_stock_items gives it for the
  -- number of times it was picked (products, limited vouchers), the same as
  -- the line's own included items. Before 483 only a product or a limited
  -- voucher picked directly was recorded, so a prize took nothing out of
  -- stock. A product picked directly and inside a prize is one component.
  insert into public.invoice_stock_components(invoice_item_id,kind,item_id,quantity,component_source)
   select v_id,x.kind,x.item_id,sum(x.quantity)::int,'selection'
   from (select case when s.product_id is not null then 'product' else 'voucher' end as kind,
                coalesce(s.product_id,s.voucher_id) as item_id,s.quantity
           from public.invoice_promotion_selections s left join public.vouchers v on v.id=s.voucher_id
          where s.invoice_item_id=v_id and (s.product_id is not null or v.qty_type='limited')
         union all
         select r.kind,r.item_id,r.quantity
           from public.invoice_promotion_selections s
           cross join lateral public.promotion_stock_items(s.child_promotion_id,s.quantity) r
          where s.invoice_item_id=v_id and s.child_promotion_id is not null) x
   group by x.kind,x.item_id;
 end if;
 return coalesce(new,old);
end $function$
$d1$;

  -- ══ Relied on, not changed (production now) ══
  c_relied constant text[] := array[
    'promotion_stock_items(uuid,integer)',
    'invoice_required_stock(uuid)'];
  c_relied_md5 constant text[] := array[
    '82dd6bdac5566fce0b75470eb45444d1',
    'c91dc1eb4f2b7b465de5fe4a8fb2ca0c'];

  -- ══ The two triggers that call it (production now) ══
  c_trg constant text[] := array[
    'CREATE TRIGGER invoice_stock_components_capture AFTER INSERT OR UPDATE ON public.invoice_items FOR EACH ROW EXECUTE FUNCTION capture_invoice_stock_components()',
    'CREATE TRIGGER invoice_stock_selections_capture AFTER INSERT OR DELETE OR UPDATE ON public.invoice_promotion_selections FOR EACH ROW EXECUTE FUNCTION capture_invoice_stock_components()'];

  v_path text := current_setting('search_path');
  v text; d text; i int; v_acl text; v_make boolean := false;
  -- the self-test's made-up records
  t_sfx text; t_owner uuid; t_store uuid; t_cust uuid; t_p1 uuid; t_p2 uuid;
  t_box uuid; t_a uuid; t_b uuid; t_gp uuid; t_gx uuid; t_inv uuid; t_item uuid;
  t_pick uuid; t_direct uuid; t_got text; t_want text;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── 1. Checks: nothing is changed before all of them pass ──
  -- What it relies on and does not change: as read on production, 31 Oct 2026.
  for i in 1 .. cardinality(c_relied) loop
    if to_regprocedure('public.' || c_relied[i]) is null
       or md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i]))) <> c_relied_md5[i] then
      raise exception '483: public.% is missing or not the version this was tested against (md5 %). Re-read it and re-test before applying.',
        c_relied[i], md5(pg_get_functiondef(to_regprocedure('public.' || c_relied[i])));
    end if;
  end loop;

  -- The two triggers that call it, as they are on production.
  for i in 1 .. cardinality(c_trg) loop
    if not exists (select 1 from pg_trigger t
                    where not t.tgisinternal and t.tgenabled = 'O' and pg_get_triggerdef(t.oid) = c_trg[i]) then
      raise exception '483: this trigger is missing, switched off or not as tested: %', c_trg[i]; end if;
  end loop;

  -- The columns the function reads and writes, with these types, and the
  -- key its summing relies on.
  select string_agg(x.t || '.' || x.c || ' ' || x.ty, ', ') into v
    from (values ('invoice_promotion_selections', 'invoice_item_id', 'uuid'),
                 ('invoice_promotion_selections', 'product_id', 'uuid'),
                 ('invoice_promotion_selections', 'voucher_id', 'uuid'),
                 ('invoice_promotion_selections', 'child_promotion_id', 'uuid'),
                 ('invoice_promotion_selections', 'quantity', 'integer'),
                 ('invoice_stock_components', 'invoice_item_id', 'uuid'),
                 ('invoice_stock_components', 'kind', 'text'),
                 ('invoice_stock_components', 'item_id', 'uuid'),
                 ('invoice_stock_components', 'quantity', 'integer'),
                 ('invoice_stock_components', 'component_source', 'text')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = ('public.' || x.t)::regclass and a.attname = x.c and not a.attisdropped
                        and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '483: these columns are missing or not of this type: %', v; end if;
  if not exists (select 1 from pg_constraint c
                  where c.conrelid = 'public.invoice_stock_components'::regclass and c.contype = 'u'
                    and pg_get_constraintdef(c.oid) = 'UNIQUE (invoice_item_id, kind, item_id, component_source)') then
    raise exception '483: invoice_stock_components no longer has its unique key on (invoice_item_id, kind, item_id, component_source)'; end if;

  -- The text written out here is the tested one.
  if md5(c_def) <> c_after then
    raise exception '483: the text of public.% is not the tested one (md5 %)', c_sig, md5(c_def); end if;

  -- The function: its BEFORE (replaced) or its AFTER (left alone).
  if to_regprocedure('public.' || c_sig) is null then raise exception '483: public.% is missing', c_sig; end if;
  d := pg_get_functiondef(to_regprocedure('public.' || c_sig));
  -- its grants, to compare after (as sets: production lists them in another
  -- order than a local copy does)
  v_acl := (select coalesce(string_agg(x::text, ',' order by x::text), '')
              from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig));
  if md5(d) = c_after then
    raise notice '483: public.% is already this version; left alone', c_sig;
  elsif md5(d) = c_before then
    v_make := true;
  else
    raise exception '483: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig, md5(d);
  end if;

  -- ── 2. Install ──
  if v_make then execute c_def; end if;

  -- ── 3. Checks after installing ──
  if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig))) <> c_after then
    raise exception '483: public.% was installed with an md5 other than the tested one', c_sig; end if;
  if (select coalesce(string_agg(x::text, ',' order by x::text), '')
        from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig)) is distinct from v_acl
     or has_function_privilege('anon', 'public.' || c_sig, 'execute')
     or has_function_privilege('authenticated', 'public.' || c_sig, 'execute') then
    raise exception '483: the grants of public.% changed', c_sig; end if;
  if (select not prosecdef or prolang <> (select oid from pg_language where lanname = 'plpgsql')
             or prorettype <> 'trigger'::regtype
        from pg_proc where oid = to_regprocedure('public.' || c_sig)) then
    raise exception '483: public.% is not a security definer plpgsql trigger function', c_sig; end if;

  -- ── 4. Self-test, in a block that is always undone ──
  -- Made-up records only ("483 check", @example.com); the invoice is written
  -- straight to its table with its own number, so no sequence is used, and
  -- nothing is paid, so no stock moves. It ends by raising P0483, which
  -- undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    insert into auth.users (id, email) values (gen_random_uuid(), '483-check-' || t_sfx || '@example.com') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '483 check', '483-check-' || t_sfx || '@example.com', 'owner', true);
    insert into public.stores (name, code, country_code) values ('483 check ' || t_sfx, '483-' || t_sfx, 'SG') returning id into t_store;
    -- +65 98 and six digits: a valid Singapore mobile (99 is not one)
    insert into public.customers (full_name, phone)
    values ('483 check', '+6598' || lpad((floor(random() * 900000) + 100000)::int::text, 6, '0')) returning id into t_cust;
    insert into public.products (name, sku) values ('483 check one ' || t_sfx, '483-1-' || t_sfx) returning id into t_p1;
    insert into public.products (name, sku) values ('483 check two ' || t_sfx, '483-2-' || t_sfx) returning id into t_p2;

    -- Two prizes, and a box offering them; the box also has a product group.
    insert into public.promotions (name, code) values ('483 check prize A ' || t_sfx, '483-A-' || t_sfx) returning id into t_a;
    insert into public.promotions (name, code) values ('483 check prize B ' || t_sfx, '483-B-' || t_sfx) returning id into t_b;
    insert into public.promotion_items (promotion_id, item_type, product_id, quantity)
    values (t_a, 'product', t_p1, 1), (t_b, 'product', t_p1, 1), (t_b, 'product', t_p2, 2);
    insert into public.promotions (name, code) values ('483 check box ' || t_sfx, '483-X-' || t_sfx) returning id into t_box;
    insert into public.promotion_choice_groups (promotion_id, label, item_kind, choose_qty)
    values (t_box, 'Choose your prize', 'promotion', 1) returning id into t_gx;
    insert into public.promotion_choice_options (group_id, child_promotion_id) values (t_gx, t_a), (t_gx, t_b);
    insert into public.promotion_choice_groups (promotion_id, label, item_kind, choose_qty)
    values (t_box, 'Choose a product', 'product', 1) returning id into t_gp;
    insert into public.promotion_choice_options (group_id, product_id) values (t_gp, t_p1);

    insert into public.invoices (invoice_no, store_id, customer_id, created_by)
    values ('483-CHECK-' || t_sfx, t_store, t_cust, t_owner) returning id into t_inv;
    insert into public.invoice_items (invoice_id, line_kind, promotion_id, quantity, unit_price, line_total)
    values (t_inv, 'promotion', t_box, 1, 0, 0) returning id into t_item;

    -- each step: the line's components, then what the invoice owes
    -- 1. prize B picked, and product one picked directly: one 2, two 2
    insert into public.invoice_promotion_selections (invoice_item_id, group_id, child_promotion_id, quantity)
    values (t_item, t_gx, t_b, 1) returning id into t_pick;
    insert into public.invoice_promotion_selections (invoice_item_id, group_id, product_id, quantity)
    values (t_item, t_gp, t_p1, 1) returning id into t_direct;
    t_want := 'one 2, two 2';
    select string_agg(case c.item_id when t_p1 then 'one' when t_p2 then 'two' else '?' end || ' ' || c.quantity, ', ' order by c.item_id = t_p2, c.item_id)
      into t_got from public.invoice_stock_components c
     where c.invoice_item_id = t_item and c.kind = 'product' and c.component_source = 'selection';
    if t_got is distinct from t_want then
      raise exception '483: prize B and product one picked: the components are %, not %', coalesce(t_got, 'none'), t_want; end if;
    select string_agg(case r.item_id when t_p1 then 'one' when t_p2 then 'two' else '?' end || ' ' || r.quantity, ', ' order by r.item_id = t_p2, r.item_id)
      into t_got from public.invoice_required_stock(t_inv) r where r.kind = 'product';
    if t_got is distinct from t_want then
      raise exception '483: prize B and product one picked: the invoice owes %, not %', coalesce(t_got, 'none'), t_want; end if;
    -- the box has no included items, so nothing is recorded as fixed
    if exists (select 1 from public.invoice_stock_components c where c.invoice_item_id = t_item and c.component_source = 'fixed') then
      raise exception '483: a box with no included items has fixed components'; end if;

    -- 2. the prize changed to A: one 2
    update public.invoice_promotion_selections set child_promotion_id = t_a where id = t_pick;
    t_want := 'one 2';
    select string_agg(case r.item_id when t_p1 then 'one' when t_p2 then 'two' else '?' end || ' ' || r.quantity, ', ' order by r.item_id = t_p2, r.item_id)
      into t_got from public.invoice_required_stock(t_inv) r where r.kind = 'product';
    if t_got is distinct from t_want then
      raise exception '483: the prize changed to A: the invoice owes %, not %', coalesce(t_got, 'none'), t_want; end if;

    -- 3. prize A picked twice (as for a line of two boxes): one 3
    update public.invoice_promotion_selections set quantity = 2 where id = t_pick;
    t_want := 'one 3';
    select string_agg(case r.item_id when t_p1 then 'one' when t_p2 then 'two' else '?' end || ' ' || r.quantity, ', ' order by r.item_id = t_p2, r.item_id)
      into t_got from public.invoice_required_stock(t_inv) r where r.kind = 'product';
    if t_got is distinct from t_want then
      raise exception '483: prize A picked twice: the invoice owes %, not %', coalesce(t_got, 'none'), t_want; end if;

    -- 4. the direct pick taken off: one 2; then the prize too: nothing
    delete from public.invoice_promotion_selections where id = t_direct;
    t_want := 'one 2';
    select string_agg(case r.item_id when t_p1 then 'one' when t_p2 then 'two' else '?' end || ' ' || r.quantity, ', ' order by r.item_id = t_p2, r.item_id)
      into t_got from public.invoice_required_stock(t_inv) r where r.kind = 'product';
    if t_got is distinct from t_want then
      raise exception '483: the direct pick taken off: the invoice owes %, not %', coalesce(t_got, 'none'), t_want; end if;
    delete from public.invoice_promotion_selections where id = t_pick;
    if exists (select 1 from public.invoice_stock_components c where c.invoice_item_id = t_item) then
      raise exception '483: every pick taken off, yet the line still has components'; end if;

    raise exception using errcode = 'P0483', message = '483: self-test done, undone';
  exception when sqlstate 'P0483' then null;
  end;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
