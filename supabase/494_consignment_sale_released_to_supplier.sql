-- 494_consignment_sale_released_to_supplier.sql
--
-- A CONSIGNMENT PRODUCT'S SALE CAN GO TO A SUPPLIER, WHO SENDS IT DIRECTLY TO
-- THE CUSTOMER (the user's design in chat, 6 Nov 2026)
--
-- (The number 494 is this file's name, its errors' prefix, its self-test's
-- error code P0494 and its suite's; if it changes at commit, change it in
-- these places alone.)
--
-- WHAT WAS ASKED
--
--   Some products may not be in stock: when a customer buys one, Energia calls
--   the supplier, who sends it directly to the customer. The user's design:
--   a "Consignment" tab on the Special page only; for a product in consignment,
--   "Waiting for a warehouse" lets an Owner or Manager choose a warehouse, a
--   store or a supplier; the suppliers come from the product on the Products
--   page. The answers: a "Deliver to" note when a supplier is chosen; each
--   product on one tab; delivery is not tracked; sales only (rentals always
--   come from Energia's stock); a return goes back to the supplier, so stock
--   does not change.
--
-- WHAT HAPPENS TODAY
--
--   Stock leaves a special sale only when it is released from the waiting list
--   (fulfil_special_doc): the invoice line itself never takes stock. So a sale
--   with nothing on hand already goes through and waits there, and what is
--   missing is a way out of the list that takes no stock. Staff instead add
--   stock by an adjustment just to release it.
--
-- WHAT THIS DOES
--
--   1. special_products.is_consignment (new, false): the product is listed on
--      the Consignment tab, and a supplier can be chosen for its sales.
--      set_special_product_consignment(id, on) sets it, Owners and Managers,
--      with an Audit Log entry.
--   2. special_sales.supplier_id and deliver_to (new, empty): the supplier it
--      was released to, and the note typed with it. A sale with a supplier has
--      neither a warehouse nor a store (a check says so).
--   3. release_special_sale_to_supplier(sale, supplier, deliver_to): Owners and
--      Managers, as fulfil_special_doc. Only a sale still waiting, of a
--      consignment product, whose invoice still sells it (393's rule), to an
--      active supplier linked to that product on the Products page
--      (product_suppliers). The sale becomes 'completed', as a release does,
--      with the same 'special_doc_fulfilled' Audit Log entry. NO stock moves
--      and no stock movement is written.
--   4. fulfil_special_doc and special_docs_awaiting_fulfilment: "waiting" also
--      means no supplier. Those two lines are the only change to each.
--
-- WHAT IT DOES NOT CHANGE
--
--   * The invoice, payment, commission (489: a special product earns like the
--     machine it is), vouchers, promotions and Reports. Every product starts
--     with is_consignment false, so nothing changes until one is ticked.
--   * A warehouse or store release, and every rental: a supplier is refused for
--     a rental by having no way to be named (this function takes sales alone).
--   * A refund. A released sale's refund has never moved stock or asked about
--     it, which is the answer given here for a supplier's sale; the page says
--     "Invoice refunded" beside it. A sale still waiting is cancelled as before
--     (393), whichever product it is.
--   * create_special_docs_for_invoice: a released sale counts by its status, so
--     reopening an invoice raises no second sale. cancel_waiting_special_docs
--     and settle_waiting_special_docs_on_refund read status 'pending' alone.
--
-- NOT COVERED (told to the user)
--
--   * Only a Special Product line reaches the waiting list. An ordinary product
--     line with no stock is still refused at payment, as today: staff must
--     pick the Special Product on the invoice.
--   * An item reaches the list once its invoice is paid in full or confirmed
--     FOC, as today. After a deposit a supplier can still be phoned; Supplier
--     is chosen once it is paid.
--   * Nothing tracks whether the supplier delivered.
--   * A partial refund (the invoice stays paid) shows no note on the Sales tab.
--
-- UNDO
--
--   Untick Consignment on each product: no sale can then go to a supplier, and
--   those already sent keep their record. The columns and the functions can
--   stay. To remove them entirely, first restore the two functions from BEFORE.
--
-- DEPLOY ORDER (each step with the user's go-ahead in chat)
--
--   1. Dry run on a copy of production as it is then: apply this file twice;
--      the second run changes nothing ("already this version").
--   2. Apply. It checks itself and runs its self-test.
--   3. Deploy the pages. Before this step the page ignores the new columns;
--      after step 3 without step 2 the Consignment tab would be empty and a
--      tick would be refused, so 2 goes first.
--
-- SAFETY
--
--   Apart from the lock timeout, ONE statement (a single DO block), atomic
--   whatever runs it; every check comes before anything changes:
--   * both patched functions are their BEFORE (patched; each anchor found
--     exactly once, the text built having the tested md5) or their AFTER (left
--     alone); anything else is refused;
--   * the new functions' texts have their tested md5s, and no other function
--     has either name;
--   * the columns read and the functions relied on are there;
--   * afterwards: the md5s are the AFTER ones and the patched functions' grants
--     are as before (compared as sets); only signed-in logins and the service
--     role may call the new ones;
--   * then a self-test, in a block that is always undone (it ends by raising
--     P0494, so it leaves no row, and it names its sales itself, so no number
--     is used up): made-up records ("494 Check", @example.invalid). No customer
--     is read or written.
--   Locks: two brief ACCESS EXCLUSIVE locks for the new columns and the check
--   (special_sales: 11 rows on 6 Nov 2026), the two functions' catalogue rows
--   and the self-test's own rows. The lock timeout gives up after 5 s and
--   changes nothing.
--
-- BEFORE (production, 6 Nov 2026: head 20261106025726, 493; md5 of
-- pg_get_functiondef with search_path public)
--   fulfil_special_doc(text,uuid,uuid,text):  9c3072e11013e8943b28d8a46854edc4
--   special_docs_awaiting_fulfilment():       aed7e3b24ff192cbe09935c5e7488881
--   public function fingerprint: 94df2f805bd9045a4effffb1abbf6097 (1415)
-- AFTER (for later guards)
--   fulfil_special_doc(text,uuid,uuid,text):  e2fd9fca6842b5193ec7020445a45189
--   special_docs_awaiting_fulfilment():       fdaf5aca81c63cc99f8fddcfcf10564c
--   set_special_product_consignment(uuid,boolean):      186d77949f84b3327c96db3cc022b234
--   release_special_sale_to_supplier(uuid,uuid,text):   15b36ba68fd7b70a1361e80f5e5fad4e
--   public function fingerprint: 05142a644ba2739f64e10f8a6c1d5035 (1417: two added, two replaced)
--
-- Test: scripts/special/tests/consignment-494.sql (begin ... rollback; it
-- installs this file twice, or with -v skip_install=1 where it is in, and sells,
-- pays, releases, refunds and reopens through the app's own calls). Fixtures
-- only (the repository is public).

set lock_timeout = '5s';

do $mig$
declare
  -- ══ The functions patched: BEFORE (production now), AFTER, and the one change in each ══
  c_sig constant text[] := array['fulfil_special_doc(text,uuid,uuid,text)', 'special_docs_awaiting_fulfilment()'];
  c_before constant text[] := array['9c3072e11013e8943b28d8a46854edc4', 'aed7e3b24ff192cbe09935c5e7488881'];
  c_after constant text[] := array['e2fd9fca6842b5193ec7020445a45189', 'fdaf5aca81c63cc99f8fddcfcf10564c'];
  c_anchor constant text[] := array[
$a1$      from public.special_sales where id = p_doc_id
        and warehouse_id is null and source_store_id is null
        and status <> 'cancelled' for update;
$a1$,
$a2$   where s.warehouse_id is null and s.source_store_id is null and s.status <> 'cancelled'
$a2$];
  c_patch constant text[] := array[
$p1$      from public.special_sales where id = p_doc_id
        and warehouse_id is null and source_store_id is null and supplier_id is null  -- 494
        and status <> 'cancelled' for update;
$p1$,
$p2$   where s.warehouse_id is null and s.source_store_id is null and s.supplier_id is null and s.status <> 'cancelled'  -- 494
$p2$];
  -- ══ The functions added ══
  c_new_sig constant text[] := array['set_special_product_consignment(uuid,boolean)', 'release_special_sale_to_supplier(uuid,uuid,text)'];
  c_new_after constant text[] := array['186d77949f84b3327c96db3cc022b234', '15b36ba68fd7b70a1361e80f5e5fad4e'];
  c_new_def constant text[] := array[
$d1$CREATE OR REPLACE FUNCTION public.set_special_product_consignment(p_id uuid, p_on boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 494: the Consignment tick on the Special page's product form, Owners and
-- Managers. A supplier can be chosen for the sales of a product that has it.
declare v public.special_products%rowtype;
begin
  perform public.require_active_staff('{owner,manager}');
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can manage special products'; end if;
  if p_on is null then raise exception 'Say whether this is a consignment product'; end if;
  select * into v from public.special_products where id = p_id and deleted_at is null for update;
  if not found then raise exception 'That special product does not exist'; end if;
  if v.is_consignment = p_on then return; end if;
  update public.special_products set is_consignment = p_on where id = p_id;
  perform public.write_audit_ex('special_products', p_id, 'special_product_consignment',
    jsonb_build_object('is_consignment', v.is_consignment),
    jsonb_build_object('is_consignment', p_on, 'product', v.name, 'sku', v.sku), 'catalogue', null, null);
end $function$
$d1$,
$d2$CREATE OR REPLACE FUNCTION public.release_special_sale_to_supplier(p_sale_id uuid, p_supplier_id uuid, p_deliver_to text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 494: "Waiting for a warehouse", choosing a supplier, who sends it directly to
-- the customer. Owners and Managers, as fulfil_special_doc. No stock moves.
declare
  v_sale public.special_sales%rowtype; v_sp public.special_products%rowtype;
  v_sup public.suppliers%rowtype; v_problem text; v_name text;
  v_note text := nullif(btrim(coalesce(p_deliver_to, '')), '');
begin
  perform public.require_active_staff('{owner,manager}');
  if not public.is_owner_or_manager() then
    raise exception 'Only an Owner or Manager can choose where stock is released from'; end if;
  if p_supplier_id is null then raise exception 'Choose the supplier'; end if;
  if length(v_note) > 500 then raise exception 'The delivery note is too long (500 characters at most)'; end if;

  select * into v_sale from public.special_sales where id = p_sale_id
     and warehouse_id is null and source_store_id is null and supplier_id is null
     and status <> 'cancelled' for update;
  if not found then raise exception 'That sale is not awaiting a location'; end if;

  -- 393's rule: never release an item its invoice no longer sells.
  v_problem := public.special_doc_invoice_problem(v_sale.invoice_id, v_sale.invoice_item_id);
  if v_problem is not null then
    raise exception '% cannot be released: %. It is no longer waiting for a warehouse.', v_sale.sale_no, v_problem;
  end if;

  select * into v_sp from public.special_products where id = v_sale.special_product_id;
  v_name := public.special_product_name(v_sale.special_product_id);
  if not coalesce(v_sp.is_consignment, false) then
    raise exception '"%" is not a consignment product, so a supplier cannot be chosen for it', v_name; end if;

  select s.* into v_sup from public.suppliers s
   where s.id = p_supplier_id and s.deleted_at is null and s.is_active
     and exists (select 1 from public.product_suppliers ps
                  where ps.supplier_id = s.id and ps.product_id = v_sp.product_id);
  if not found then
    raise exception 'That supplier is not linked to "%" on the Products page', v_name; end if;

  update public.special_sales
     set supplier_id = v_sup.id, deliver_to = v_note,
         status = 'completed', fulfilled_at = now(), fulfilled_by = auth.uid()
   where id = p_sale_id;

  perform public.write_audit_ex('special_sale', p_sale_id, 'special_doc_fulfilled', null,
    jsonb_build_object('location_type', 'supplier', 'location', v_sup.id, 'location_name', v_sup.name,
      'product', v_name, 'quantity', v_sale.quantity, 'doc_no', v_sale.sale_no, 'deliver_to', v_note),
    'special', null, null);

  return jsonb_build_object('success', true, 'doc_no', v_sale.sale_no,
    'location_type', 'supplier', 'location_name', v_sup.name,
    'quantity', v_sale.quantity, 'product', v_name);
end $function$
$d2$];

  v_path text := current_setting('search_path');
  d text; v text; i int; n int;
  v_built text[] := array[null, null]::text[];
  v_make boolean[] := array[false, false];
  v_acl text[] := array[null, null]::text[];
  -- the self-test's made-up records
  t_sfx text; t_owner uuid; t_staff uuid; t_wh uuid; t_p_con uuid; t_p_plain uuid; t_sup uuid; t_sup_other uuid;
  t_sp_con uuid; t_sp_plain uuid; t_sale uuid; t_sale_plain uuid; t_msg text; t_row public.special_sales%rowtype;
begin
  -- Definitions are read and compared with public alone on the search path.
  perform set_config('search_path', 'public', true);

  -- ── 1. Checks: nothing is changed before all of them pass ──
  select string_agg(x.t || '.' || x.c || ' ' || x.ty, ', ') into v
    from (values ('special_sales', 'warehouse_id', 'uuid'), ('special_sales', 'source_store_id', 'uuid'),
                 ('special_sales', 'status', 'text'), ('special_sales', 'fulfilled_at', 'timestamp with time zone'),
                 ('special_sales', 'fulfilled_by', 'uuid'), ('special_sales', 'invoice_id', 'uuid'),
                 ('special_sales', 'invoice_item_id', 'uuid'), ('special_products', 'product_id', 'uuid'),
                 ('suppliers', 'is_active', 'boolean'), ('suppliers', 'deleted_at', 'timestamp with time zone'),
                 ('product_suppliers', 'product_id', 'uuid'), ('product_suppliers', 'supplier_id', 'uuid')) x(t, c, ty)
   where not exists (select 1 from pg_attribute a
                      where a.attrelid = ('public.' || x.t)::regclass and a.attname = x.c and not a.attisdropped
                        and format_type(a.atttypid, a.atttypmod) = x.ty);
  if v is not null then raise exception '494: these columns are missing or not of this type: %', v; end if;

  select string_agg(f, ', ') into v
    from unnest(array['require_active_staff(text[])', 'is_owner_or_manager()', 'special_doc_invoice_problem(uuid,uuid)',
                      'special_product_name(uuid)', 'write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)',
                      'upsert_special_product_from_product(uuid,uuid,numeric,numeric,numeric,numeric,numeric,numeric,text,boolean)']) f
   where to_regprocedure('public.' || f) is null;
  if v is not null then raise exception '494: these functions are missing: %', v; end if;

  for i in 1 .. 2 loop
    if md5(c_new_def[i]) <> c_new_after[i] then
      raise exception '494: the text of public.% is not the tested one (md5 %)', c_new_sig[i], md5(c_new_def[i]); end if;
    if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                and p.proname = split_part(c_new_sig[i], '(', 1)
                and p.oid::regprocedure::text <> c_new_sig[i]) then
      raise exception '494: another function takes the name of public.%', c_new_sig[i]; end if;

    if to_regprocedure('public.' || c_sig[i]) is null then raise exception '494: public.% is missing', c_sig[i]; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || c_sig[i]));
    -- its grants, to compare after (as sets: production lists them in another
    -- order than a local copy does)
    v_acl[i] := (select coalesce(string_agg(x::text, ',' order by x::text), '')
                   from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i]));
    if md5(d) = c_after[i] then
      raise notice '494: public.% is already this version; left alone', c_sig[i];
    elsif md5(d) = c_before[i] then
      n := (length(d) - length(replace(d, c_anchor[i], ''))) / length(c_anchor[i]);
      if n <> 1 then raise exception '494: public.%: its anchor is found % times, not once', c_sig[i], n; end if;
      v_built[i] := replace(d, c_anchor[i], c_patch[i]);
      if md5(v_built[i]) <> c_after[i] then
        raise exception '494: the text built for public.% is not the tested one (md5 %)', c_sig[i], md5(v_built[i]); end if;
      v_make[i] := true;
    else
      raise exception '494: public.% is not the version this was tested against (md5 %). Re-read it and re-test before applying.', c_sig[i], md5(d);
    end if;
  end loop;

  -- ── 2. Install ──
  alter table public.special_products add column if not exists is_consignment boolean not null default false;
  comment on column public.special_products.is_consignment is
    '494: a supplier can send it directly to the customer: a sale of it can be released to one of its product''s suppliers. Listed on the Special page''s Consignment tab.';
  alter table public.special_sales add column if not exists supplier_id uuid references public.suppliers(id);
  alter table public.special_sales add column if not exists deliver_to text;
  comment on column public.special_sales.supplier_id is
    '494: released to this supplier, who sends it directly (no warehouse, no store, no stock moved).';
  comment on column public.special_sales.deliver_to is
    '494: the note typed when it was released to a supplier.';
  if not exists (select 1 from pg_constraint where conrelid = 'public.special_sales'::regclass
                  and conname = 'special_sales_supplier_has_no_location') then
    alter table public.special_sales add constraint special_sales_supplier_has_no_location
      check (supplier_id is null or (warehouse_id is null and source_store_id is null));
  end if;

  for i in 1 .. 2 loop
    if v_make[i] then execute v_built[i]; end if;
    execute c_new_def[i];
    execute format('revoke all on function public.%s from public, anon', c_new_sig[i]);
    execute format('grant execute on function public.%s to authenticated, service_role', c_new_sig[i]);
  end loop;

  -- ── 3. Checks after installing ──
  for i in 1 .. 2 loop
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_sig[i]))) <> c_after[i] then
      raise exception '494: public.% was installed with an md5 other than the tested one', c_sig[i]; end if;
    if (select coalesce(string_agg(x::text, ',' order by x::text), '')
          from pg_proc p, unnest(p.proacl) x where p.oid = to_regprocedure('public.' || c_sig[i])) is distinct from v_acl[i] then
      raise exception '494: the grants of public.% changed', c_sig[i]; end if;
    if md5(pg_get_functiondef(to_regprocedure('public.' || c_new_sig[i]))) <> c_new_after[i] then
      raise exception '494: public.% was installed with an md5 other than the tested one', c_new_sig[i]; end if;
    if has_function_privilege('anon', to_regprocedure('public.' || c_new_sig[i]), 'execute')
       or not has_function_privilege('authenticated', to_regprocedure('public.' || c_new_sig[i]), 'execute')
       or not has_function_privilege('service_role', to_regprocedure('public.' || c_new_sig[i]), 'execute') then
      raise exception '494: the grants of public.% are not as written', c_new_sig[i]; end if;
  end loop;

  -- ── 4. Self-test, in a block that is always undone ──
  -- Made-up records only. It ends by raising P0494, which undoes all it wrote.
  begin
    t_sfx := lower(substr(md5(gen_random_uuid()::text), 1, 8));
    insert into auth.users (id, email) values (gen_random_uuid(), '494chk-owner-' || t_sfx || '@example.invalid') returning id into t_owner;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_owner, '494 Check Owner', '494chk-owner-' || t_sfx || '@example.invalid', 'owner', true);
    insert into auth.users (id, email) values (gen_random_uuid(), '494chk-staff-' || t_sfx || '@example.invalid') returning id into t_staff;
    insert into public.profiles (id, full_name, email, role, is_active)
    values (t_staff, '494 Check Staff', '494chk-staff-' || t_sfx || '@example.invalid', 'staff', true);
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', t_owner, 'role', 'authenticated')::text, true);

    insert into public.warehouses (name, code) values ('494 Check ' || t_sfx, '494-' || t_sfx) returning id into t_wh;
    insert into public.products (name, sku, product_type) values ('494 Check Consignment', '494-C-' || t_sfx, 'third_party') returning id into t_p_con;
    insert into public.products (name, sku, product_type) values ('494 Check Plain', '494-P-' || t_sfx, 'third_party') returning id into t_p_plain;
    insert into public.warehouse_inventory (warehouse_id, product_id, current_qty) values (t_wh, t_p_con, 5);
    insert into public.suppliers (name) values ('494 Check Supplier ' || t_sfx) returning id into t_sup;
    insert into public.suppliers (name) values ('494 Check Other ' || t_sfx) returning id into t_sup_other;
    insert into public.product_suppliers (product_id, supplier_id) values (t_p_con, t_sup), (t_p_plain, t_sup);
    t_sp_con := public.upsert_special_product_from_product(null, t_p_con, 100);
    t_sp_plain := public.upsert_special_product_from_product(null, t_p_plain, 100);
    if (select is_consignment from public.special_products where id = t_sp_con) then
      raise exception '494: a new special product started as consignment'; end if;
    perform public.set_special_product_consignment(t_sp_con, true);
    if not (select is_consignment from public.special_products where id = t_sp_con) then
      raise exception '494: the Consignment tick did not hold'; end if;

    -- Named here, so no sale number is used up. No invoice: nothing to check against.
    insert into public.special_sales (sale_no, special_product_id, quantity, unit_price, total_amount, status, notes)
    values ('494-CHECK-A-' || t_sfx, t_sp_con, 1, 100, 100, 'pending', '494 self-test') returning id into t_sale;
    insert into public.special_sales (sale_no, special_product_id, quantity, unit_price, total_amount, status, notes)
    values ('494-CHECK-B-' || t_sfx, t_sp_plain, 1, 100, 100, 'pending', '494 self-test') returning id into t_sale_plain;
    if not exists (select 1 from public.special_docs_awaiting_fulfilment() w where w.doc_id = t_sale) then
      raise exception '494: a sale waiting is not on the waiting list'; end if;

    -- Refused: a product not in consignment, a supplier not linked, a login not an Owner or Manager.
    t_msg := null;
    begin perform public.release_special_sale_to_supplier(t_sale_plain, t_sup, null);
    exception when others then t_msg := sqlerrm; end;
    if t_msg is null or t_msg not like '%is not a consignment product%' then
      raise exception '494: a sale of a product not in consignment was answered: %', t_msg; end if;
    t_msg := null;
    begin perform public.release_special_sale_to_supplier(t_sale, t_sup_other, null);
    exception when others then t_msg := sqlerrm; end;
    if t_msg is null or t_msg not like '%is not linked to%' then
      raise exception '494: a supplier not linked to the product was answered: %', t_msg; end if;
    perform set_config('request.jwt.claim.sub', t_staff::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', t_staff, 'role', 'authenticated')::text, true);
    t_msg := null;
    begin perform public.release_special_sale_to_supplier(t_sale, t_sup, null);
    exception when others then t_msg := sqlerrm; end;
    if t_msg is distinct from 'Your role cannot do this.' then
      raise exception '494: a member of staff was answered: %', t_msg; end if;
    perform set_config('request.jwt.claim.sub', t_owner::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', t_owner, 'role', 'authenticated')::text, true);

    -- Released to the supplier: it leaves the list, and no stock moves.
    perform public.release_special_sale_to_supplier(t_sale, t_sup, '  12 Check Road  ');
    select * into t_row from public.special_sales where id = t_sale;
    if t_row.status <> 'completed' or t_row.supplier_id is distinct from t_sup or t_row.deliver_to is distinct from '12 Check Road'
       or t_row.warehouse_id is not null or t_row.source_store_id is not null or t_row.fulfilled_by is distinct from t_owner then
      raise exception '494: the released sale is not as it should be: %', to_jsonb(t_row); end if;
    if exists (select 1 from public.special_docs_awaiting_fulfilment() w where w.doc_id = t_sale) then
      raise exception '494: a sale released to a supplier is still on the waiting list'; end if;
    if (select current_qty from public.warehouse_inventory where warehouse_id = t_wh and product_id = t_p_con) <> 5
       or exists (select 1 from public.stock_movements where product_id = t_p_con) then
      raise exception '494: releasing to a supplier moved stock'; end if;

    -- And it cannot be released again, either way.
    t_msg := null;
    begin perform public.release_special_sale_to_supplier(t_sale, t_sup, null);
    exception when others then t_msg := sqlerrm; end;
    if t_msg is distinct from 'That sale is not awaiting a location' then
      raise exception '494: releasing to a supplier twice was answered: %', t_msg; end if;
    t_msg := null;
    begin perform public.fulfil_special_doc('special_sale', t_sale, t_wh, 'warehouse');
    exception when others then t_msg := sqlerrm; end;
    if t_msg is distinct from 'That sale is not awaiting a location' then
      raise exception '494: a warehouse release after a supplier was answered: %', t_msg; end if;

    raise exception using errcode = 'P0494', message = '494: self-test done, undone';
  exception when sqlstate 'P0494' then null;
  end;

  perform set_config('search_path', v_path, true);
  perform pg_notify('pgrst', 'reload schema');
end $mig$;
