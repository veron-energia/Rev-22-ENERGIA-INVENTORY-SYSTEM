-- Every table rule asks who you are once per read, and still lets in the same
-- people (430, X-11).
--
-- Before 430, 129 rules called a helper such as current_user_role(),
-- is_owner_or_manager() or user_has_store_access(store_id) once for every
-- row. 430 asks each once per query: (select f()), and for a store test
-- (select is_owner_or_admin()) or store_id = any ((select current_user_store_ids())::uuid[]).
-- This suite checks, on a fixture with rows in both stores, that nothing else
-- changed:
--   1. Before 430, as 15 logins (Owner, Admin, Managers at one and two stores,
--      Inventory Managers at one store and none, Staff at one, two and no
--      store, a deactivated one, an active one whose invitation is pending, a
--      deleted Manager, a login with no profile, an affiliate, and the public
--      key), it reads every table with row-level security and the storage
--      objects, and tries an update and a delete on every table with a write
--      rule, and an insert on the simple ones and on every table whose write
--      rule 430 splits (each has rows). It also asks the old helpers over
--      every store, and times them called once per row and the Dashboard's
--      sales read.
--   2. It applies 430 (-v mig=supabase/430_policies_store_scoped_and_fast.sql).
--   3. The same reads and writes again. Every login sees exactly the rows it
--      saw, with two kinds of difference only, both intended:
--        * invoice lines, revisions, promotion picks, refunds and credit
--          splits (X-10): exactly the rows of the reader's stores;
--        * the pending and the deleted login (CUSTOMERS-N3): only fewer rows,
--          and no write.
--      The new store test equals the old user_has_store_access() for every
--      active login and store, and the stock-history tests equal the old
--      stock_history_location() and stock_history_movement(). The affiliate
--      reads its own account and claim only, Owners and Managers read every
--      one, and staff and a login with no profile read none. The helpers
--      called per row and the Dashboard's sales read are no slower (within
--      half again plus 2 ms, for noise): a helper that calls another helper
--      is planned again on every call.
--   4. As Staff at one store, no plan calls a helper per row (but the three
--      rules 430 leaves), and every read with a helper rule has an InitPlan.
--      Every function a rule calls is STABLE or IMMUTABLE. Every rule's text,
--      as pg_policies prints it (and pg_dump writes it), reads back to itself.
--
--   psql -X -v ON_ERROR_STOP=1 -v mig=supabase/430_policies_store_scoped_and_fast.sql \
--        -f scripts/permissions/tests/policy-initplan.sql
-- It needs a database with every batch before 430 applied (430 refuses
-- otherwise). Disposable database only; everything is rolled back. Fixture
-- names carry PIX, phones are ACMA's fictional +61 4915 numbers, emails
-- @example.com. The timing adds 300 invoices inside a block that is then
-- undone, so no other check sees them.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local client_min_messages = warning;

create temp table pix(k text primary key, id uuid not null);
create temp table pix_res(phase text, who text, what text, res text, primary key (phase, who, what));
create temp table pix_fail(n serial, msg text);
create function pg_temp.pix_id(p text) returns uuid language sql stable as $f$ select id from pix where k = p $f$;
create function pg_temp.pix_fail(p text) returns void language sql as $f$ insert into pix_fail(msg) values (p) $f$;

-- Run p_sql as a login and roll it back, whatever it did. The answer is
-- 'ok', a tab, and what p_sql returned (for a write, its row count), or the
-- SQLSTATE. p_who: a login key, 'anon' (the public key) or 'server'.
create function pg_temp.pix_try(p_who text, p_sql text, p_write boolean default false) returns text
language plpgsql as $f$
declare v_out text; v_state text; v_msg text; n bigint;
begin
  begin
    if p_who = 'anon' then
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
      execute 'set local role anon';
    elsif p_who <> 'server' then
      perform set_config('request.jwt.claims',
        json_build_object('sub', pg_temp.pix_id(p_who), 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    if p_write then
      execute p_sql; get diagnostics n = row_count; v_out := n::text;
    else
      execute p_sql into v_out;
    end if;
    raise exception using errcode = 'PIX01', message = coalesce(v_out, '');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    if v_state = 'PIX01' then return 'ok' || chr(9) || v_msg; end if;
    return v_state;
  end;
end $f$;

-- ── Fixture (as the server; triggers and foreign keys off while it is written) ──
do $$
declare
  k text; v uuid; st_a uuid; st_b uuid; wh uuid; prod uuid; c1 uuid; c2 uuid; c3 uuid; pm uuid;
  inv_a uuid; inv_b uuid; it_a uuid; it_b uuid; hs_a uuid; hs_b uuid; hs_n uuid; te_a uuid; te_b uuid;
  tr_a uuid; tr_b uuid; tr_w uuid; ln uuid; vo uuid; vo_del uuid; pr uuid; pr_del uuid; cg uuid; prod2 uuid;
  c4 uuid; c5 uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  set local session_replication_role = replica;
  foreach k in array array['owner', 'admin', 'mgr_a', 'mgr_ab', 'im_a', 'im_none', 'staff_a', 'staff_ab',
                           'staff_none', 'inactive', 'pending', 'deleted', 'nostaff', 'aff', 'aff2'] loop
    insert into auth.users(id, email) values (gen_random_uuid(), 'pix-' || replace(k, '_', '-') || '@example.com') returning id into v;
    insert into pix values (k, v);
  end loop;
  insert into public.profiles(id, full_name, email, role, is_active, invitation_status, deleted_at, created_at, updated_at)
  select s.id, 'PIX ' || s.k, 'pix-' || replace(s.k, '_', '-') || '@example.com', x.role::public.user_role, x.active, x.inv,
         case when s.k = 'deleted' then now() end, now(), now()
    from pix s join (values ('owner', 'owner', true, null), ('admin', 'admin', true, null),
                            ('mgr_a', 'manager', true, null), ('mgr_ab', 'manager', true, 'accepted'),
                            ('im_a', 'inventory_manager', true, null), ('im_none', 'inventory_manager', true, null),
                            ('staff_a', 'staff', true, null), ('staff_ab', 'staff', true, 'accepted'),
                            ('staff_none', 'staff', true, null), ('inactive', 'staff', false, null),
                            ('pending', 'staff', true, 'pending'), ('deleted', 'manager', true, null))
                     x(k, role, active, inv) on x.k = s.k;

  insert into public.stores(name, code, country_code) values ('PIX Store A', 'PIXA', 'SG') returning id into st_a;
  insert into public.stores(name, code, country_code) values ('PIX Store B', 'PIXB', 'SG') returning id into st_b;
  insert into public.warehouses(name, code) values ('PIX Warehouse', 'PIXW') returning id into wh;
  insert into pix values ('store_a', st_a), ('store_b', st_b), ('warehouse', wh);
  insert into public.user_store_assignments(user_id, store_id)
  select pg_temp.pix_id(x.k), x.st
    from (values ('mgr_a', st_a), ('mgr_ab', st_a), ('mgr_ab', st_b), ('im_a', st_a), ('staff_a', st_a),
                 ('staff_ab', st_a), ('staff_ab', st_b), ('inactive', st_a), ('pending', st_a),
                 ('deleted', st_a)) x(k, st);

  insert into public.products(name, sku) values ('PIX Product', 'PIX-1') returning id into prod;
  insert into public.store_product_prices(store_id, product_id, selling_price) values (st_a, prod, 10), (st_b, prod, 10);
  insert into public.store_inventory(store_id, product_id, current_qty) values (st_a, prod, 5), (st_b, prod, 5);
  insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (wh, prod, 5);
  insert into public.payment_methods(name) values ('PIX Cash') returning id into pm;
  insert into public.brands(name) values ('PIX Brand');
  insert into public.categories(name) values ('PIX Category');
  insert into public.suppliers(name) values ('PIX Supplier');
  insert into public.promotions(name, code) values ('PIX Promo', 'PIXP1') returning id into pr;
  insert into public.promotions(name, code, deleted_at) values ('PIX Old Promo', 'PIXP2', now()) returning id into pr_del;
  insert into public.vouchers(name, code) values ('PIX Voucher', 'PIXV1') returning id into vo;
  insert into public.vouchers(name, code, deleted_at) values ('PIX Old Voucher', 'PIXV2', now()) returning id into vo_del;
  insert into public.survey_links(token, store_id) values ('pix-link-a', st_a), ('pix-link-b', st_b);
  -- A row in every table whose write rules 430 splits, so each split rule is compared.
  insert into public.products(name, sku) values ('PIX Product Two', 'PIX-2') returning id into prod2;
  insert into public.promotion_items(promotion_id, item_type, product_id, quantity) values (pr, 'product', prod, 1);
  insert into public.promotion_choice_groups(promotion_id, label, item_kind, choose_qty) values (pr, 'PIX Group', 'product', 1) returning id into cg;
  insert into public.promotion_choice_options(group_id, product_id) values (cg, prod);
  insert into public.promotion_store_prices(promotion_id, store_id, selling_price) values (pr, st_a, 10), (pr, st_b, 10);
  insert into public.voucher_store_prices(voucher_id, store_id, selling_price) values (vo, st_a, 10), (vo, st_b, 10);
  insert into public.voucher_store_stock(voucher_id, store_id, current_qty) values (vo, st_a, 1), (vo, st_b, 1);
  insert into public.health_symptom_options(category, label) values ('PIX', 'PIX Symptom');
  insert into pix values ('promo', pr), ('promo_old', pr_del), ('voucher_old', vo_del), ('product', prod), ('product2', prod2),
                         ('group', cg), ('pm', pm);

  insert into public.customers(full_name, phone, email) values ('PIX Customer One', '+61491570006', 'pix-c1@example.com') returning id into c1;
  insert into public.customers(full_name, phone, email) values ('PIX Customer Two', '+61491570156', 'pix-c2@example.com') returning id into c2;
  insert into public.customers(full_name, phone, email, deleted_at) values ('PIX Customer Gone', '+61491570157', 'pix-c3@example.com', now()) returning id into c3;
  insert into public.customer_reward_vouchers(customer_id, voucher_id, quantity, store_id) values (c1, vo, 1, st_a), (c2, vo, 1, st_b);
  insert into pix values ('customer', c1);
  -- Two affiliates: portal logins with no staff profile, each with its own
  -- account and claim, and one sign-up event.
  insert into public.customers(full_name, phone, email) values ('PIX Affiliate One', '+61491570737', 'pix-c4@example.com') returning id into c4;
  insert into public.customers(full_name, phone, email) values ('PIX Affiliate Two', '+61491571266', 'pix-c5@example.com') returning id into c5;
  insert into public.affiliate_accounts(auth_user_id, customer_id, status)
    values (pg_temp.pix_id('aff'), c4, 'claimed'), (pg_temp.pix_id('aff2'), c5, 'claimed');
  insert into public.affiliate_account_claims(auth_user_id, status)
    values (pg_temp.pix_id('aff'), 'resolved'), (pg_temp.pix_id('aff2'), 'pending');
  insert into public.referral_signup_events(referral_code, referrer_customer_id, new_customer_id, outcome)
    values ('PIXREF', c4, c5, 'PIX');

  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, business_date)
    values ('PIX-INV-A', st_a, c1, pg_temp.pix_id('owner'), 'unpaid', 10, 10, current_date) returning id into inv_a;
  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, business_date)
    values ('PIX-INV-B', st_b, c2, pg_temp.pix_id('owner'), 'unpaid', 10, 10, current_date) returning id into inv_b;
  insert into public.invoice_items(invoice_id, product_id, line_kind, quantity, unit_price, line_total)
    values (inv_a, prod, 'product', 1, 10, 10) returning id into it_a;
  insert into public.invoice_items(invoice_id, product_id, line_kind, quantity, unit_price, line_total)
    values (inv_b, prod, 'product', 1, 10, 10) returning id into it_b;
  insert into public.invoice_revisions(invoice_id, revision_no, snapshot) values (inv_a, 1, '{}'), (inv_b, 1, '{}');
  insert into public.invoice_promotion_selections(invoice_item_id, product_id, quantity) values (it_a, prod, 1), (it_b, prod, 1);
  insert into public.invoice_refunds(invoice_id, amount) values (inv_a, 1), (inv_b, 1);
  insert into public.invoice_credit_splits(invoice_id, invoice_item_id, customer_id, amount) values (inv_a, it_a, c1, 1), (inv_b, it_b, c2, 1);
  insert into public.invoice_payments(invoice_id, payment_method_id, amount, received_by)
    values (inv_a, pm, 1, pg_temp.pix_id('owner')), (inv_b, pm, 1, pg_temp.pix_id('owner'));
  insert into public.invoice_voucher_movements(invoice_id, voucher_id, store_id, quantity, reason)
    values (inv_a, vo, st_a, 1, 'PIX'), (inv_b, vo, st_b, 1, 'PIX');
  insert into public.staff_commissions(invoice_id, staff_id, store_id, invoice_total, share_ratio, rate, commission_amount)
    values (inv_a, pg_temp.pix_id('staff_a'), st_a, 10, 1, 0.03, 0.3), (inv_b, pg_temp.pix_id('staff_ab'), st_b, 10, 1, 0.03, 0.3);
  insert into public.approval_requests(request_type, status, requested_by, payload)
    values ('adjustment', 'pending', pg_temp.pix_id('staff_a'), '{}'), ('adjustment', 'pending', pg_temp.pix_id('deleted'), '{}');
  insert into public.audit_logs(table_name, action) values ('pix', 'pix');
  insert into public.product_exchanges(exchange_no, original_invoice_id, customer_id, processing_store_id)
    values ('PIX-EX-A', inv_a, c1, st_a), ('PIX-EX-B', inv_b, c2, st_b);

  insert into public.stock_movements(product_id, movement_type, quantity, to_warehouse_id) values (prod, 'warehouse_stock_in', 1, wh);
  insert into public.stock_movements(product_id, movement_type, quantity, from_warehouse_id, to_store_id) values (prod, 'warehouse_to_store', 1, wh, st_a);
  insert into public.stock_movements(product_id, movement_type, quantity, from_warehouse_id, to_store_id) values (prod, 'warehouse_to_store', 1, wh, st_b);
  insert into public.stock_movements(product_id, movement_type, quantity, from_store_id, to_store_id) values (prod, 'store_to_store', 1, st_a, st_b);
  insert into public.stock_movements(product_id, movement_type, quantity, from_store_id, invoice_id) values (prod, 'store_sale', 1, st_b, inv_b);
  insert into public.stock_loans(loan_no, location_type, store_id, expected_return_date, borrower_name)
    values ('PIX-L1', 'store', st_a, current_date, 'PIX Borrower'), ('PIX-L2', 'store', st_b, current_date, 'PIX Borrower');
  insert into public.stock_loans(loan_no, location_type, warehouse_id, expected_return_date, borrower_name)
    values ('PIX-L3', 'warehouse', wh, current_date, 'PIX Borrower');

  insert into public.transfer_requests(transfer_type, dest_type, dest_id, status, requested_by)
    values ('warehouse_to_store', 'store', st_a, 'pending', pg_temp.pix_id('staff_a')) returning id into tr_a;
  insert into public.transfer_requests(transfer_type, dest_type, dest_id, status, requested_by)
    values ('warehouse_to_store', 'store', st_b, 'pending', pg_temp.pix_id('staff_ab')) returning id into tr_b;
  insert into public.transfer_requests(transfer_type, dest_type, dest_id, status, requested_by)
    values ('warehouse_to_warehouse', 'warehouse', wh, 'pending', pg_temp.pix_id('owner')) returning id into tr_w;
  insert into public.transfer_request_lines(transfer_request_id, product_id, quantity) values (tr_a, prod, 1) returning id into ln;
  insert into public.transfer_line_sources(line_id, source_type, source_id, quantity) values (ln, 'warehouse', wh, 1);
  insert into public.transfer_request_lines(transfer_request_id, product_id, quantity) values (tr_b, prod, 1) returning id into ln;
  insert into public.transfer_line_sources(line_id, source_type, source_id, quantity) values (ln, 'store', st_a, 1);
  insert into public.transfer_request_lines(transfer_request_id, product_id, quantity) values (tr_w, prod, 1);

  insert into public.health_surveys(survey_no, customer_id, full_name, phone, source, store_id)
    values ('PIX-HS-A', c1, 'PIX Customer One', '+61491570006', 'consultant', st_a) returning id into hs_a;
  insert into public.health_surveys(survey_no, customer_id, full_name, phone, source, store_id)
    values ('PIX-HS-B', c2, 'PIX Customer Two', '+61491570156', 'consultant', st_b) returning id into hs_b;
  insert into public.health_surveys(survey_no, customer_id, full_name, phone, source)
    values ('PIX-HS-N', null, 'PIX Customer Two', '+61491570156', 'public_form') returning id into hs_n;
  insert into public.health_survey_attachments(survey_id, storage_path, file_name)
    values (hs_a, st_a || '/pix-a.jpg', 'pix-a.jpg'), (hs_b, st_b || '/pix-b.jpg', 'pix-b.jpg'), (hs_n, 'pix-n.jpg', 'pix-n.jpg');
  insert into public.therapy_entitlements(entitlement_no, customer_id, store_id, package_name, entitlement_kind,
                                          qualifying_amount, qualified_value, activation_deadline)
    values ('PIX-TE-A', c1, st_a, 'PIX', 'legacy', 1, 1, current_date) returning id into te_a;
  insert into public.therapy_entitlements(entitlement_no, customer_id, store_id, package_name, entitlement_kind,
                                          qualifying_amount, qualified_value, activation_deadline)
    values ('PIX-TE-B', c2, st_b, 'PIX', 'legacy', 1, 1, current_date) returning id into te_b;
  insert into public.voucher_claims(entitlement_id, customer_id, store_id, quantity, selections)
    values (te_a, c1, st_a, 1, '[]'), (te_b, c2, st_b, 1, '[]');

  insert into storage.objects(bucket_id, name) values
    ('invoice-pdfs', st_a || '/invoice/PIX-INV-A.pdf'), ('invoice-pdfs', st_b || '/invoice/PIX-INV-B.pdf'),
    ('survey-attachments', st_a || '/pix-a.jpg'), ('survey-attachments', st_b || '/pix-b.jpg'),
    ('store-assets', st_a || '/pix-logo.png'),
    -- Files filed under no store (production holds 143 such).
    ('invoice-pdfs', 'invoice/PIX-NOSTORE.pdf'), ('survey-attachments', 'pix-nostore.jpg');
  set local session_replication_role = origin;
end $$;

-- What a phase reads and writes, as every login.
create function pg_temp.pix_run(p_phase text) returns void language plpgsql as $f$
declare
  c_who constant text[] := array['owner', 'admin', 'mgr_a', 'mgr_ab', 'im_a', 'im_none', 'staff_a', 'staff_ab',
                                 'staff_none', 'inactive', 'pending', 'deleted', 'nostaff', 'aff', 'anon'];
  r record; w text; v text; st_a text := pg_temp.pix_id('store_a')::text; st_b text := pg_temp.pix_id('store_b')::text;
  pr text := pg_temp.pix_id('promo')::text; pr_old text := pg_temp.pix_id('promo_old')::text;
  vo_old text := pg_temp.pix_id('voucher_old')::text; prod2 text := pg_temp.pix_id('product2')::text;
  cg text := pg_temp.pix_id('group')::text;
begin
  for r in
    select n.nspname s, c.relname t from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where c.relkind = 'r' and c.relrowsecurity
       and (n.nspname = 'public' or (n.nspname = 'storage' and c.relname = 'objects'))
     order by 1, 2
  loop
    foreach w in array c_who loop
      v := pg_temp.pix_try(w, format('select count(*)::text || chr(9) || coalesce(string_agg(x.ctid::text, '','' order by x.ctid), '''') from %I.%I x', r.s, r.t));
      insert into pix_res values (p_phase, w, 'read ' || r.s || '.' || r.t, v);
    end loop;
  end loop;
  -- An update and a delete on every table with a write rule.
  for r in
    select distinct p.schemaname s, p.tablename t from pg_policies p
     where p.schemaname in ('public', 'storage') and p.cmd in ('UPDATE', 'DELETE', 'ALL')
     order by 1, 2
  loop
    foreach w in array c_who loop
      insert into pix_res values (p_phase, w, 'update ' || r.s || '.' || r.t,
        pg_temp.pix_try(w, format('update %I.%I set id = id', r.s, r.t), true));
      insert into pix_res values (p_phase, w, 'delete ' || r.s || '.' || r.t,
        pg_temp.pix_try(w, format('delete from %I.%I', r.s, r.t), true));
    end loop;
  end loop;
  -- An insert on the simple ones.
  for r in select * from (values
    ('brands', 'insert into public.brands(name) values (''PIX New'')'),
    ('categories', 'insert into public.categories(name) values (''PIX New'')'),
    ('suppliers', 'insert into public.suppliers(name) values (''PIX New'')'),
    ('payment_methods', 'insert into public.payment_methods(name) values (''PIX New'')'),
    ('health_symptom_options', 'insert into public.health_symptom_options(category, label) values (''PIX'', ''PIX New'')'),
    ('promotions', 'insert into public.promotions(name, code) values (''PIX New'', ''PIXP9'')'),
    ('vouchers', 'insert into public.vouchers(name, code) values (''PIX New'', ''PIXV9'')'),
    ('survey_links', format('insert into public.survey_links(token, store_id) values (''pix-new'', %L)', st_a)),
    ('special_products', 'insert into public.special_products(name, sku) values (''PIX New'', ''PIX-S9'')'),
    -- The split tables not above (the unused pairs avoid the unique keys).
    ('promotion_items', format('insert into public.promotion_items(promotion_id, item_type, product_id, quantity) values (%L, ''product'', %L, 1)', pr, prod2)),
    ('promotion_choice_groups', format('insert into public.promotion_choice_groups(promotion_id, label, item_kind, choose_qty) values (%L, ''PIX New'', ''product'', 1)', pr)),
    ('promotion_choice_options', format('insert into public.promotion_choice_options(group_id, product_id) values (%L, %L)', cg, prod2)),
    ('promotion_store_prices', format('insert into public.promotion_store_prices(promotion_id, store_id, selling_price) values (%L, %L, 10)', pr_old, st_a)),
    ('voucher_store_prices', format('insert into public.voucher_store_prices(voucher_id, store_id, selling_price) values (%L, %L, 10)', vo_old, st_a)),
    ('voucher_store_stock', format('insert into public.voucher_store_stock(voucher_id, store_id, current_qty) values (%L, %L, 1)', vo_old, st_a)),
    ('store_product_prices', format('insert into public.store_product_prices(store_id, product_id, selling_price) values (%L, %L, 10)', st_a, prod2)),
    ('pdf a', format('insert into storage.objects(bucket_id, name) values (''invoice-pdfs'', %L)', st_a || '/invoice/PIX-new.pdf')),
    ('pdf b', format('insert into storage.objects(bucket_id, name) values (''invoice-pdfs'', %L)', st_b || '/invoice/PIX-new.pdf')),
    ('attachment a', format('insert into storage.objects(bucket_id, name) values (''survey-attachments'', %L)', st_a || '/pix-new.jpg')),
    ('asset a', format('insert into storage.objects(bucket_id, name) values (''store-assets'', %L)', st_a || '/pix-new.png'))
  ) x(what, sql) loop
    foreach w in array c_who loop
      insert into pix_res values (p_phase, w, 'insert ' || r.what, pg_temp.pix_try(w, r.sql, true));
    end loop;
  end loop;
end $f$;

-- The store and stock-history tests over every login and place.
create temp table pix_helper(phase text, who text, what text, res text, primary key (phase, who, what));
create function pg_temp.pix_helpers(p_phase text) returns void language plpgsql as $f$
declare
  c_who constant text[] := array['owner', 'admin', 'mgr_a', 'mgr_ab', 'im_a', 'im_none', 'staff_a', 'staff_ab',
                                 'staff_none', 'inactive', 'pending', 'deleted', 'nostaff', 'aff'];
  w text; x record; v_places text;
begin
  foreach w in array c_who loop
    perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.pix_id(w), 'role', 'authenticated')::text, true);
    for x in select * from (values ('A', pg_temp.pix_id('store_a')), ('B', pg_temp.pix_id('store_b')),
                                   ('null', null::uuid), ('other', '00000000-0000-4000-8000-000000000001'::uuid)) v(k, id) loop
      insert into pix_helper values (p_phase, w, 'store ' || x.k, public.user_has_store_access(x.id)::text);
      insert into pix_helper values (p_phase, w, 'history store ' || x.k, public.stock_history_location('store', x.id)::text);
      insert into pix_helper values (p_phase, w, 'history warehouse ' || x.k, public.stock_history_location('warehouse', x.id)::text);
      insert into pix_helper values (p_phase, w, 'movement from ' || x.k,
        public.stock_history_movement(null, null, x.id, null, null, null)::text);
      insert into pix_helper values (p_phase, w, 'movement to ' || x.k,
        public.stock_history_movement(null, null, null, x.id, null, null)::text);
      if p_phase = 'after' then
        -- The rewritten rules' forms, once per query.
        insert into pix_helper values ('rule', w, 'store ' || x.k,
          coalesce((select public.is_owner_or_admin()) or x.id = any ((select public.current_user_store_ids())::uuid[]), false)::text);
        insert into pix_helper values ('rule', w, 'history store ' || x.k,
          coalesce(x.id is not null and ((select public.stock_history_global()) or x.id = any ((select public.current_user_store_ids())::uuid[])), false)::text);
        insert into pix_helper values ('rule', w, 'history warehouse ' || x.k,
          coalesce(x.id is not null and (select public.stock_history_global()), false)::text);
        insert into pix_helper values ('rule', w, 'movement from ' || x.k,
          coalesce((select public.stock_history_global()) or x.id = any ((select public.current_user_store_ids())::uuid[]), false)::text);
        insert into pix_helper values ('rule', w, 'movement to ' || x.k,
          coalesce((select public.stock_history_global()) or x.id = any ((select public.current_user_store_ids())::uuid[]), false)::text);
      end if;
    end loop;
    insert into pix_helper values (p_phase, w, 'roles',
      concat_ws(',', public.is_owner_or_manager(), public.is_manager_or_above(), public.is_owner_or_admin(),
                public.can_manage_warehouse_stock(), public.can_view_customer_credit(),
                public.invoice_date_recovery_access(), public.stock_history_global(), public.is_owner()));
  end loop;
  perform set_config('request.jwt.claims', '', true);
end $f$;

-- The helpers called once per row, and the Dashboard's sales read, timed as
-- Staff at both stores, a Manager at one and the Owner: median of 7 runs. It
-- adds 300 paid invoices (one line and one payment each) inside a block that
-- is then undone, so the other checks never see them.
create temp table pix_speed(phase text, who text, what text, ms numeric, primary key (phase, who, what));
create function pg_temp.pix_speed(p_phase text) returns void language plpgsql as $f$
declare
  c_q constant text[][] := array[
    ['store access per row', 'select count(*)::text from (select (array[%L::uuid, %L::uuid])[1 + g %% 2] sid from generate_series(1, 2000) g) y where public.user_has_store_access(y.sid)'],
    ['stock history per row', 'select count(*)::text from (select (array[%L::uuid, %L::uuid])[1 + g %% 2] sid from generate_series(1, 2000) g) y where public.stock_history_location(''store'', y.sid)'],
    ['dashboard sales', 'select length(public.dashboard_sales(''month'', current_date - 30, current_date)::text)::text']];
  st_a uuid := pg_temp.pix_id('store_a'); st_b uuid := pg_temp.pix_id('store_b');
  w text; i int; k int; t numeric[]; t0 timestamptz; v text; v_out text := ''; inv uuid;
begin
  begin
    perform set_config('request.jwt.claims', '', true);
    set local session_replication_role = replica;
    for i in 1 .. 300 loop
      insert into public.invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, business_date)
        values ('PIX-SPEED-' || i, case when i % 2 = 0 then st_a else st_b end, pg_temp.pix_id('customer'),
                pg_temp.pix_id('owner'), 'paid', 10, 10, current_date - (i % 25)) returning id into inv;
      insert into public.invoice_items(invoice_id, product_id, line_kind, quantity, unit_price, line_total)
        values (inv, pg_temp.pix_id('product'), 'product', 1, 10, 10);
      insert into public.invoice_payments(invoice_id, payment_method_id, amount, received_by)
        values (inv, pg_temp.pix_id('pm'), 10, pg_temp.pix_id('owner'));
    end loop;
    set local session_replication_role = origin;
    foreach w in array array['staff_ab', 'mgr_a', 'owner'] loop
      perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.pix_id(w), 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
      for k in 1 .. array_length(c_q, 1) loop
        t := '{}';
        for i in 1 .. 7 loop
          t0 := clock_timestamp();
          execute format(c_q[k][2], st_a, st_b) into v;
          t := t || (extract(epoch from clock_timestamp() - t0) * 1000)::numeric;
        end loop;
        v_out := v_out || w || '|' || c_q[k][1] || '|'
                 || round((select percentile_cont(0.5) within group (order by x) from unnest(t) x)::numeric, 2) || ';';
      end loop;
      execute 'reset role';
    end loop;
    raise exception using errcode = 'PIX01', message = v_out;
  exception when sqlstate 'PIX01' then
    get stacked diagnostics v_out = message_text;
  end;
  perform set_config('request.jwt.claims', '', true);
  insert into pix_speed
  select p_phase, split_part(x, '|', 1), split_part(x, '|', 2), split_part(x, '|', 3)::numeric
    from unnest(string_to_array(rtrim(v_out, ';'), ';')) x;
end $f$;

select pg_temp.pix_run('before');
select pg_temp.pix_helpers('before');
select pg_temp.pix_speed('before');

-- ── 430 ──────────────────────────────────────────────────────────────────────
\i :mig
reset role;
select set_config('request.jwt.claims', '', true);
set local client_min_messages = warning;

select pg_temp.pix_run('after');
select pg_temp.pix_helpers('after');
select pg_temp.pix_speed('after');

-- ── 3. Compare ───────────────────────────────────────────────────────────────
do $$
declare
  c_x10 constant text[] := array['read public.invoice_items', 'read public.invoice_revisions',
    'read public.invoice_promotion_selections', 'read public.invoice_refunds', 'read public.invoice_credit_splits'];
  c_closed constant text[] := array['pending', 'deleted'];
  r record; v_exp text; n_same int := 0; n_x10 int := 0; n_closed int := 0; n_anon int := 0;
  a_before text[]; a_after text[];
begin
  for r in select b.who, b.what, b.res rb, a.res ra from pix_res b join pix_res a on a.who = b.who and a.what = b.what
            where b.phase = 'before' and a.phase = 'after' order by 1, 2 loop
    if r.what = any (c_x10) then
      -- Exactly the rows of the reader's stores (as the server reads them).
      v_exp := pg_temp.pix_try('server', format($q$
        select count(*)::text || chr(9) || coalesce(string_agg(x.ctid::text, ',' order by x.ctid), '')
          from %s x
         where %L in ('owner', 'admin', 'mgr_a', 'mgr_ab', 'im_a', 'im_none', 'staff_a', 'staff_ab', 'staff_none')
           and exists (select 1 from public.invoices i %s
                        where %s
                          and (%L in ('owner', 'admin')
                               or i.store_id in (select usa.store_id from public.user_store_assignments usa
                                                  where usa.user_id = %L)))$q$,
        substr(r.what, 6), r.who,
        case when r.what like '%selections' then 'join public.invoice_items it on it.invoice_id = i.id' else '' end,
        case when r.what like '%selections' then 'it.id = x.invoice_item_id' else 'i.id = x.invoice_id' end,
        r.who, pg_temp.pix_id(r.who)));
      if r.who = 'anon' then
        -- The public key read nothing, and now holds no grant either.
        if r.ra not in ('42501', 'ok' || chr(9) || '0' || chr(9)) then
          perform pg_temp.pix_fail(format('X-10 %s as anon: %s -> %s', r.what, r.rb, r.ra)); end if;
      elsif r.ra <> v_exp then
        perform pg_temp.pix_fail(format('X-10 %s as %s: %s, expected %s', r.what, r.who, r.ra, v_exp));
      end if;
      if r.ra <> r.rb then n_x10 := n_x10 + 1; end if;
    elsif r.ra = r.rb then
      n_same := n_same + 1;
    elsif r.who = 'anon' and r.rb = 'ok' || chr(9) || '0' || chr(9) and r.ra = '42501' then
      -- Three rules apply to every role (invoice_payment_arrangements,
      -- invoice_arrangement_receipts, product_exchange_service_staff). The
      -- public key may not run the helpers, so on an EMPTY table it read 0
      -- rows and now gets "permission denied"; on a table with rows it got
      -- "permission denied" before too. Either way it reads nothing.
      n_anon := n_anon + 1;
    elsif r.who = any (c_closed) then
      -- Fewer rows only, and no write.
      if split_part(r.ra, chr(9), 1) = 'ok' and r.what like 'read %' then
        a_before := string_to_array(split_part(r.rb, chr(9), 3), ',');
        a_after := string_to_array(split_part(r.ra, chr(9), 3), ',');
        if split_part(r.rb, chr(9), 1) <> 'ok' or not (coalesce(a_after, '{}') <@ coalesce(a_before, '{}')) then
          perform pg_temp.pix_fail(format('%s as %s gained rows: %s -> %s', r.what, r.who, r.rb, r.ra)); end if;
      elsif split_part(r.ra, chr(9), 1) = 'ok' and r.what not like 'read %' and split_part(r.ra, chr(9), 2) <> '0' then
        perform pg_temp.pix_fail(format('%s as %s still writes: %s -> %s', r.what, r.who, r.rb, r.ra));
      end if;
      n_closed := n_closed + 1;
    else
      perform pg_temp.pix_fail(format('%s as %s changed: %s -> %s', r.what, r.who, r.rb, r.ra));
    end if;
  end loop;
  if (select count(*) from pix_res where phase = 'before') <> (select count(*) from pix_res where phase = 'after') then
    perform pg_temp.pix_fail('the two phases did not try the same things'); end if;
  -- The fixture is not empty where it matters (else "the same" proves nothing).
  if (select count(*) from pix_res where phase = 'after' and what like 'read %' and split_part(res, chr(9), 1) = 'ok'
         and split_part(res, chr(9), 2) <> '0') < 40 then
    perform pg_temp.pix_fail('fewer than 40 non-empty reads: the fixture is too thin'); end if;
  if n_x10 = 0 then perform pg_temp.pix_fail('X-10 changed nothing for any login'); end if;
  raise warning 'PIX: % reads and writes the same, % X-10 reads now limited to the reader''s stores, % changes for the pending or deleted login, % empty reads by the public key now refused',
    n_same, n_x10, n_closed, n_anon;

  -- The helpers: the same for every active login; nothing for the pending and the deleted.
  for r in select b.who, b.what, b.res rb, a.res ra from pix_helper b join pix_helper a on a.who = b.who and a.what = b.what
            where b.phase = 'before' and a.phase = 'after' loop
    if r.who = any (c_closed) then
      if r.ra ~ 'true' then perform pg_temp.pix_fail(format('helper %s still lets %s in: %s', r.what, r.who, r.ra)); end if;
    elsif r.ra is distinct from r.rb then
      perform pg_temp.pix_fail(format('helper %s for %s: %s -> %s', r.what, r.who, r.rb, r.ra));
    end if;
  end loop;
  for r in select b.who, b.what, b.res rb, a.res ra from pix_helper b join pix_helper a on a.who = b.who and a.what = b.what
            where b.phase = 'before' and a.phase = 'rule' loop
    if r.who = any (c_closed) then
      if r.ra <> 'false' then perform pg_temp.pix_fail(format('rule form %s lets %s in', r.what, r.who)); end if;
    elsif r.ra is distinct from r.rb then
      perform pg_temp.pix_fail(format('rule form %s for %s is %s, the old helper said %s', r.what, r.who, r.ra, r.rb));
    end if;
  end loop;
  if (select count(*) from pix_helper where phase = 'rule') <> 14 * 4 * 5 then
    perform pg_temp.pix_fail('the rule forms were not all asked'); end if;

  -- The affiliate rules on real rows, before and after: the affiliate reads
  -- its own account and claim only, Owners and Managers every one, and Admin,
  -- staff and a login with no profile none.
  for r in
    select x.who, x.what, x.n, b.res rb, a.res ra
      from (values ('aff', 'affiliate_accounts', 1), ('aff', 'affiliate_account_claims', 1), ('aff', 'referral_signup_events', 0),
                   ('owner', 'affiliate_accounts', 2), ('owner', 'affiliate_account_claims', 2), ('owner', 'referral_signup_events', 1),
                   ('mgr_a', 'affiliate_accounts', 2), ('mgr_a', 'affiliate_account_claims', 2), ('mgr_a', 'referral_signup_events', 1),
                   ('mgr_ab', 'affiliate_accounts', 2), ('mgr_ab', 'affiliate_account_claims', 2), ('mgr_ab', 'referral_signup_events', 1),
                   ('admin', 'affiliate_accounts', 0), ('staff_ab', 'affiliate_accounts', 0), ('staff_ab', 'affiliate_account_claims', 0),
                   ('nostaff', 'affiliate_accounts', 0), ('nostaff', 'affiliate_account_claims', 0), ('nostaff', 'referral_signup_events', 0)) x(who, what, n)
      left join pix_res b on b.phase = 'before' and b.who = x.who and b.what = 'read public.' || x.what
      left join pix_res a on a.phase = 'after' and a.who = x.who and a.what = 'read public.' || x.what
  loop
    if split_part(r.rb, chr(9), 1) <> 'ok' or split_part(r.rb, chr(9), 2) <> r.n::text
       or split_part(r.ra, chr(9), 1) <> 'ok' or split_part(r.ra, chr(9), 2) <> r.n::text then
      perform pg_temp.pix_fail(format('%s as %s: expected %s rows, got %s before and %s after', r.what, r.who, r.n, r.rb, r.ra));
    end if;
  end loop;
  foreach v_exp in array array['affiliate_accounts', 'affiliate_account_claims'] loop
    if pg_temp.pix_try('aff', format('select count(*) filter (where auth_user_id = %L)::text || ''/'' || count(*)::text from public.%I',
                                     pg_temp.pix_id('aff'), v_exp)) <> 'ok' || chr(9) || '1/1' then
      perform pg_temp.pix_fail(format('the affiliate does not read only its own row of %s', v_exp)); end if;
  end loop;

  -- No slower: each time after 430 within half again the time before, plus
  -- 2 ms for noise.
  for r in select b.who, b.what, b.ms mb, a.ms ma from pix_speed b join pix_speed a on a.who = b.who and a.what = b.what
            where b.phase = 'before' and a.phase = 'after' order by 1, 2 loop
    if r.ma > r.mb * 1.5 + 2 then
      perform pg_temp.pix_fail(format('%s as %s got slower: %s ms -> %s ms', r.what, r.who, r.mb, r.ma)); end if;
  end loop;
  if (select count(*) from pix_speed where phase = 'before') <> 9 or (select count(*) from pix_speed where phase = 'after') <> 9 then
    perform pg_temp.pix_fail('the timings were not all taken'); end if;
  raise warning 'PIX: times before -> after (ms): %', (
    select string_agg(b.who || ' ' || b.what || ' ' || b.ms || ' -> ' || a.ms, '; ' order by b.what, b.who)
      from pix_speed b join pix_speed a on a.who = b.who and a.what = b.what where b.phase = 'before' and a.phase = 'after');
end $$;

-- ── 4. Plans, volatility and the rule texts ──────────────────────────────────
do $$
declare
  c_left constant text[] := array['public.purchased_therapy_entitlements', 'public.health_survey_pdfs', 'public.transfer_requests'];
  c_helpers constant text := 'current_user_role|is_owner_or_manager|is_manager_or_above|is_owner_or_admin|is_owner'
    || '|can_manage_warehouse_stock|can_view_customer_credit|invoice_date_recovery_access|user_admin_role'
    || '|user_has_store_access|stock_history_global|stock_history_location|stock_history_movement'
    || '|stock_history_transfer|current_user_store_ids|can_view_health_data|can_edit_products';
  r record; p record; v_plan text; n_plans int := 0; n_init int := 0; n_via_left int := 0; v_md5 text; n int := 0;
begin
  for r in
    select n2.nspname s, c.relname t,
           exists (select 1 from pg_policies q where q.schemaname = n2.nspname and q.tablename = c.relname
                    and q.cmd in ('SELECT', 'ALL')
                    and coalesce(q.qual, '') ~ ('(' || c_helpers || ')\(')) uses_helper
      from pg_class c join pg_namespace n2 on n2.oid = c.relnamespace
     where c.relkind = 'r' and c.relrowsecurity
       and (n2.nspname = 'public' or (n2.nspname = 'storage' and c.relname = 'objects'))
     order by 1, 2
  loop
    -- EXPLAIN as Staff at one store.
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.pix_id('staff_a'), 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
      v_plan := '';
      for p in execute format('explain (costs off) select * from %I.%I', r.s, r.t) loop
        v_plan := v_plan || p."QUERY PLAN" || chr(10);
      end loop;
      raise exception using errcode = 'PIX01', message = v_plan;
    exception when others then
      get stacked diagnostics v_plan = message_text;
    end;
    n_plans := n_plans + 1;
    if (r.s || '.' || r.t) = any (c_left) then continue; end if;
    if v_plan ~ ('(^|[^a-z_.])(' || c_helpers || ')\(') then
      -- A rule that reads one of the three tables 430 leaves (its EXISTS) meets
      -- that table's own per-row rule there: reported, not a fault of this rule.
      if v_plan ~ ' on (purchased_therapy_entitlements|health_survey_pdfs|transfer_requests)( |$|\n)' then
        n_via_left := n_via_left + 1;
        raise warning 'PIX: %.% asks per row only inside a table 430 leaves', r.s, r.t;
      else
        perform pg_temp.pix_fail(format('the plan of %s.%s still calls a helper per row: %s', r.s, r.t, v_plan));
      end if;
    end if;
    if r.uses_helper then
      if v_plan !~ 'InitPlan' then
        perform pg_temp.pix_fail(format('the plan of %s.%s has no InitPlan: %s', r.s, r.t, v_plan)); end if;
      n_init := n_init + 1;
    end if;
  end loop;
  raise warning 'PIX: % plans read as Staff at one store, % with InitPlans; none calls a helper per row but the 3 left and % reading one of them', n_plans, n_init, n_via_left;

  -- Every function a rule calls is STABLE or IMMUTABLE.
  for r in
    select distinct pr.oid::regprocedure::text sig, pr.provolatile
      from pg_policies q
      cross join lateral regexp_matches(coalesce(q.qual, '') || ' ' || coalesce(q.with_check, ''), '([a-z_]+)\(', 'g') m
      join pg_proc pr on pr.proname = m[1] and pr.pronamespace = 'public'::regnamespace
     where q.schemaname in ('public', 'storage')
  loop
    if r.provolatile not in ('s', 'i') then
      perform pg_temp.pix_fail(format('%s, called by a rule, is VOLATILE', r.sig)); end if;
  end loop;

  -- Each rule's text, as printed, reads back to itself (what pg_dump relies on).
  for r in select * from pg_policies q where q.schemaname in ('public', 'storage') order by 1, 2, 3 loop
    v_md5 := md5(r.permissive || '|' || array_to_string(r.roles, ',') || '|' || r.cmd || '|'
                 || coalesce(r.qual, '') || '|' || coalesce(r.with_check, ''));
    begin
      perform set_config('search_path', 'public', true);
      if r.cmd = 'INSERT' then
        execute format('alter policy %I on %I.%I with check (%s)', r.policyname, r.schemaname, r.tablename, r.with_check);
      elsif r.qual is not null and r.with_check is not null then
        execute format('alter policy %I on %I.%I using (%s) with check (%s)', r.policyname, r.schemaname, r.tablename, r.qual, r.with_check);
      elsif r.qual is not null then
        execute format('alter policy %I on %I.%I using (%s)', r.policyname, r.schemaname, r.tablename, r.qual);
      end if;
      select md5(q.permissive || '|' || array_to_string(q.roles, ',') || '|' || q.cmd || '|'
                 || coalesce(q.qual, '') || '|' || coalesce(q.with_check, ''))
        into v_md5 from pg_policies q where q.schemaname = r.schemaname and q.tablename = r.tablename
                                       and q.policyname = r.policyname;
      raise exception using errcode = 'PIX01', message = v_md5;
    exception when others then
      get stacked diagnostics v_md5 = message_text;
    end;
    n := n + 1;
    if v_md5 is distinct from md5(r.permissive || '|' || array_to_string(r.roles, ',') || '|' || r.cmd || '|'
                                   || coalesce(r.qual, '') || '|' || coalesce(r.with_check, '')) then
      perform pg_temp.pix_fail(format('the rule "%s" on %s.%s does not read back to itself: %s', r.policyname, r.schemaname, r.tablename, v_md5));
    end if;
  end loop;
  raise warning 'PIX: % rule texts read back to themselves', n;
end $$;

do $$
declare v text;
begin
  select string_agg(msg, E'\n' order by n) into v from pix_fail;
  if v is not null then raise exception E'FAIL (% problems):\n%', (select count(*) from pix_fail), v; end if;
  raise warning 'PASS: every rule lets in the same people as before 430 (but X-10''s five tables, now by store, and the pending and deleted logins, now nobody); the affiliate reads its own rows only; no plan calls a helper per row but the three rules 430 leaves; the helpers called per row and the Dashboard''s sales read are no slower; every rule''s helper is STABLE; every rule text reads back to itself';
end $$;
rollback;
