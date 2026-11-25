-- A change made straight on a settings table or a staff profile is recorded in the audit log, a
-- Manager changes only their own stores, a payment method's wallet settings are locked, and the
-- write rules no page uses are closed (532; security audit of 17 Nov 2026, M7 and M8; the user,
-- 20 Nov 2026).
--
-- Every change is made as the pages make it: through the table API as a signed-in login (the
-- authenticated role, its JWT, row rules on: an Owner, a Manager working at stores A and M, an
-- Admin, an Inventory Manager, Staff of store A), through a page's server function as that login,
-- or with the secret key (the service_role role). The entries are read straight from audit_logs.
--
--   R  The report's local check: a Manager not working at store B changes its PayNow UEN straight
--      on the table: since 532 no row changes and no entry is written. At their own stores A and
--      M it is changed, with exactly 1 audit row (the old and the new UEN, the Manager, the
--      store, 'stores'); an Owner changes any store. Admin, Inventory Manager and Staff change
--      none; only an Owner adds a store. soft_delete_store and restore_store refuse a Manager on
--      a store they do not work at, and work on their own (their own entry only); the secret key
--      still restores any store.
--   T  Each of the twelve tables: an insert records the row (<noun>_created), an update only the
--      columns changed (<noun>_updated), deleted_at set and cleared (<noun>_deleted, _restored), a
--      delete the old row (<noun>_removed); the record (a promotion item, choice group and choice
--      option under the promotion), the store (a store's own, a survey link's), the module
--      ('catalogue' for special products and promotion items, 'promotions' for promotions and
--      their choices, the table's own name for the rest) and the actor.
--   N  An update that changes nothing, or only updated_at, records nothing.
--   F  A change made inside a server function gives only that function's own entry:
--      soft_delete_store, restore_store, soft_delete_warehouse, restore_warehouse,
--      add_promotion_item, upsert_special_product_from_product, set_special_product_consignment.
--   C  A cascade gives no entry of its own: deleting a choice group with two options, or a
--      promotion with its choices, items and prices, gives 1 entry.
--   S  The secret key's direct change gives 1 entry (no login, actor_role 'service_role'); the
--      database owner's none; a store deleted outright is recorded with no store (the audit log's
--      store must exist). Deleting outright and editing a choice in place, which no login may do
--      since 532 (Q), are recorded through the secret key.
--   P  Each of the 24 dropped rules: the direct write is refused (an insert raises, an update or
--      delete changes no row) for the role it used to let through, while the page's server
--      function still saves; the rules kept (product links' read, promotion items' delete,
--      special products' update) still work.
--   Q  Nine more rules no page uses: an Owner's outright delete of a brand, category, supplier,
--      payment method, promotion, survey link or voucher, and a Manager's edit of a choice group or
--      option in place, change nothing; deleting a choice and soft_delete_voucher still work.
--   A  The store images (storage.objects, bucket store-assets): a Manager adds a file into their
--      own store's folder, not another's; nobody overwrites (in place or by upsert) or removes a
--      file; an Owner adds into any store's folder; a file outside a store's folder is refused;
--      Admin, Staff and Inventory Manager add none; the files are still read.
--   D  set_store_policy_text records the policy text before and after (once; nothing for the same
--      text); a signed-in login still cannot call it.
--   W  A payment method's wallet settings (is_wallet_credit, wallet_category, wallet_source,
--      is_system): no Owner, Manager or secret key sets them on a new method or changes them
--      ("A payment method's wallet settings cannot be changed here."); the defaults sent as they
--      are, a rename and a switch-off go through and are recorded; a migration (the database
--      owner) still sets them.
--   M8 A staff profile: an Owner changing a Staff login's role gives one entry
--      (staff_role_changed, the old and the new role, the Owner); a Manager's refused change none;
--      a login editing its own phone one (staff_profile_updated); a save changing only updated_at
--      none; a login switched off or on gives only 412's entry when 412 records it, and this one
--      when 412 does not (a login 412 never blocked); the secret key's change one, and its switch
--      alone 532's (service_role) beside 412's (no actor); a profile made or removed with the
--      secret key one (staff_profile_created, staff_profile_removed); the database owner's none.
--   G  532's fixed parts: the two functions' md5 and rights, the thirteen triggers and the wallet
--      lock's, the 33 rules and the two store-assets rules gone, the store and store-assets rules
--      and the three store functions, the relied-on functions unchanged; installed here, only the
--      two new functions, the three store functions, the two store rules, store-assets write and
--      the 35 rules dropped differ from before.
--   U  scripts/audit-log/undo-532.sql refuses while another trigger uses 532's functions, puts
--      back the rules and the functions exactly as before 532, refuses a second time; 532 again
--      makes exactly what it made.
--   M  532 a second time refuses ("532 is already in") and changes nothing.
--
-- Disposable local database only; everything is rolled back. Every name and code is invented
-- (M532-…, @example.invalid); phones are the fictional +61 491 570 nnn range. Run it on a copy
-- of production without 532 (it applies 532, then again); with -v skip_install=1 where 532 is
-- already in (G is partly skipped, U and M are skipped); with -v control=1 on a copy WITHOUT 532
-- (it does not install it, skips G, U and M, and fails on exactly the checks 532 makes pass).
-- Every check runs, then the file fails if any did.
--   psql -X -v ON_ERROR_STOP=1 -f scripts/audit-log/tests/direct-changes-recorded-532.sql
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '300s';
-- 535 (security audit of 17 Nov 2026, M12) extends trg_audit_direct_change() and attaches it to
-- three more tables (app_settings, credit_packages, premium_bundles): where 535 is in, 535's UNDO
-- puts back 532's function and its thirteen triggers, for this run only (rolled back with
-- everything here). This suite tests 532.
select to_regclass('public.invoice_affiliate_rates') is not null as m532_535_in \gset
\if :m532_535_in
-- 538 (security audit of 17 Nov 2026, M12) builds on 535: where it is in, its UNDO goes first
-- (this run only).
select to_regclass('public.invoice_line_commission_kinds') is not null as m532_538_in \gset
\if :m532_538_in
\ir ../../commissions/undo-538.sql
\endif
\ir ../../commissions/undo-535.sql
\endif
-- Before: every function's text and rights, and every rule of public.
create temp table fn0 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
create function pg_temp.pol_set() returns table(tbl text, name text, cmd text, roles text, perm boolean, qual text, chk text)
  language sql as $f$
  select case when c.relnamespace = 'public'::regnamespace then c.relname::text else 'storage.' || c.relname end,
         p.polname::text, p.polcmd::text, p.polroles::regrole[]::text, p.polpermissive,
         pg_get_expr(p.polqual, p.polrelid), pg_get_expr(p.polwithcheck, p.polrelid)
    from pg_policy p join pg_class c on c.oid = p.polrelid
   where c.relnamespace = 'public'::regnamespace or c.oid = 'storage.objects'::regclass $f$;
create temp table pol0 as select * from pg_temp.pol_set();
select position('532 (security audit' in coalesce(pg_get_functiondef(to_regprocedure('public.trg_audit_direct_change()')), '')) > 0 as had532 \gset
\if :{?control}
\if :had532
\echo control: 532 is in on this copy; run -v control=1 on a copy without it
select 1/0;
\endif
\set mode control
\elif :{?skip_install}
\if :had532
\else
\echo 532 is not in: run without -v skip_install
select 1/0;
\endif
\set mode skip
\elif :had532
\echo 532 is already in: run with -v skip_install=1
select 1/0;
\else
\ir ../../../supabase/532_changes_made_straight_on_the_tables_are_recorded.sql
\set mode install
\endif
create temp table fn1 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p');
create temp table pol1 as select * from pg_temp.pol_set();
select :'mode' = 'install' as by_us, :'mode' = 'control' as is_control \gset

create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.put(key text, val uuid) returns uuid language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v returning v $$;
-- An id as its fixture's key ('-' for none), so expected entries read plainly.
create function pg_temp.k(val uuid) returns text language sql as
$$ select case when val is null then '-' else coalesce((select min(k) from fx where v = val), val::text) end $$;
create temp table sfx as select lower(substr(md5(gen_random_uuid()::text), 1, 6)) as s;
create function pg_temp.sfx() returns text language sql as $$ select s from sfx $$;

-- One statement as someone: 'own', 'mgr', 'inv', 'stf' (signed-in logins), 'svc' (the secret key)
-- or 'pg' (the database owner; 'pg:<login>' with that login's claims). 'ok:<first column>', or 'ERR <sqlstate> <message>'.
create function pg_temp.as_(who text, q text) returns text language plpgsql as $f$
declare v text; s text; m text;
begin
  begin
    if who = 'svc' then
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', 'service_role', true);
      perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
      execute 'set local role service_role';
    elsif who = 'pg' then
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', '', true);
      perform set_config('request.jwt.claims', '', true);
    elsif who like 'pg:%' then
      -- The database owner with a login's claims (as inside a server function's own call).
      perform set_config('request.jwt.claim.sub', pg_temp.fx(substr(who, 4))::text, true);
      perform set_config('request.jwt.claim.role', 'authenticated', true);
      perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(substr(who, 4)), 'role', 'authenticated')::text, true);
    else
      perform set_config('request.jwt.claim.sub', pg_temp.fx(who)::text, true);
      perform set_config('request.jwt.claim.role', 'authenticated', true);
      perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(who), 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    execute q into v;
    execute 'reset role';
    return 'ok:' || coalesce(v, '');
  exception when others then
    get stacked diagnostics s = returned_sqlstate, m = message_text;
    execute 'reset role';
    return 'ERR ' || s || ' ' || m;
  end;
end $f$;
-- A write as someone: how many rows it changed ('ok:<n>'), or the error.
create function pg_temp.n(who text, dml text) returns text language sql as
$$ select pg_temp.as_(who, format('with x as (%s returning 1) select count(*)::text from x', dml)) $$;

-- The audit entries written since the last mark.
create temp table seen(id uuid primary key);
create function pg_temp.mark() returns void language sql as
$$ insert into seen select id from public.audit_logs on conflict do nothing $$;
create function pg_temp.fresh() returns setof public.audit_logs language sql as
$$ select a.* from public.audit_logs a where not exists (select 1 from seen s where s.id = a.id) order by a.table_name, a.action $$;
-- table/action/record/store/module/actor of each, by fixture key.
create function pg_temp.saw() returns text language sql as
$$ select coalesce(string_agg(format('%s/%s/%s/%s/%s/%s', a.table_name, a.action, pg_temp.k(a.record_id), pg_temp.k(a.store_id),
                                     coalesce(a.module, '-'), pg_temp.k(a.changed_by)), ' ; '), '') from pg_temp.fresh() a $$;
-- table/action of each.
create function pg_temp.acts() returns text language sql as
$$ select coalesce(string_agg(a.table_name || '/' || a.action, ' ; '), '') from pg_temp.fresh() a $$;
-- The one fresh entry's old and new data (null when not exactly one).
create function pg_temp.od() returns jsonb language sql as
$$ select case when (select count(*) from pg_temp.fresh()) = 1 then (select old_data from pg_temp.fresh()) end $$;
create function pg_temp.nd() returns jsonb language sql as
$$ select case when (select count(*) from pg_temp.fresh()) = 1 then (select new_data from pg_temp.fresh()) end $$;
create function pg_temp.role_of() returns text language sql as
$$ select case when (select count(*) from pg_temp.fresh()) = 1 then (select coalesce(actor_role, '-') from pg_temp.fresh()) end $$;

-- ═════ Fixtures (invented), as the database owner ═════
do $fx$
declare r record; u uuid; s text := pg_temp.sfx();
begin
  for r in select * from (values ('own', 'owner'), ('mgr', 'manager'), ('inv', 'inventory_manager'), ('stf', 'staff'),
                                 ('adm', 'admin'), ('stf2', 'staff'), ('stf3', 'staff'), ('stf4', 'staff')) t(k, role) loop
    insert into auth.users(id, email, email_confirmed_at)
    values (gen_random_uuid(), 'm532-' || r.k || '-' || s || '@example.invalid', now()) returning id into u;
    insert into public.profiles(id, full_name, email, role, is_active)
    values (u, 'M532 ' || r.k, 'm532-' || r.k || '-' || s || '@example.invalid', r.role::public.user_role, true);
    perform pg_temp.put(r.k, u);
  end loop;
  insert into public.stores(name, code, paynow_uen) values ('M532 Store A', 'M532-A-' || s, 'UEN-A-OLD') returning id into u; perform pg_temp.put('sa', u);
  insert into public.stores(name, code, paynow_uen) values ('M532 Store B', 'M532-B-' || s, 'UEN-B-OLD') returning id into u; perform pg_temp.put('sb', u);
  insert into public.stores(name, code) values ('M532 Store F', 'M532-F-' || s) returning id into u; perform pg_temp.put('sf', u);
  insert into public.stores(name, code) values ('M532 Store Gone', 'M532-G-' || s) returning id into u; perform pg_temp.put('sgone', u);
  insert into public.stores(name, code) values ('M532 Store M', 'M532-M-' || s) returning id into u; perform pg_temp.put('sm', u);
  -- The Manager works at stores A and M, Staff at store A.
  insert into public.user_store_assignments(user_id, store_id)
  values (pg_temp.fx('mgr'), pg_temp.fx('sa')), (pg_temp.fx('mgr'), pg_temp.fx('sm')), (pg_temp.fx('stf'), pg_temp.fx('sa'));
  -- A login switched off before 412 (no block of 412's): off, and its block taken away.
  update public.profiles set is_active = false where id = pg_temp.fx('stf4');
  delete from public.staff_login_blocks where user_id = pg_temp.fx('stf4');
  insert into public.warehouses(name, code) values ('M532 Warehouse F', 'M532-WF-' || s) returning id into u; perform pg_temp.put('wf', u);
  insert into public.warehouses(name, code) values ('M532 Warehouse Gone', 'M532-WG-' || s) returning id into u; perform pg_temp.put('wgone', u);
  insert into public.products(name, sku) values ('M532 Product 1', 'M532-P1-' || s) returning id into u; perform pg_temp.put('pr1', u);
  insert into public.products(name, sku) values ('M532 Product 2', 'M532-P2-' || s) returning id into u; perform pg_temp.put('pr2', u);
  insert into public.products(name, sku) values ('M532 Product 3', 'M532-P3-' || s) returning id into u; perform pg_temp.put('pr3', u);
  insert into public.vouchers(name, code) values ('M532 Voucher', 'M532-V-' || s) returning id into u; perform pg_temp.put('v1', u);
  insert into public.categories(name) values ('M532 Category ' || s) returning id into u; perform pg_temp.put('c1', u);
  insert into public.suppliers(name) values ('M532 Supplier ' || s) returning id into u; perform pg_temp.put('su1', u);
  insert into public.product_categories(product_id, category_id) values (pg_temp.fx('pr1'), pg_temp.fx('c1'));
  insert into public.product_suppliers(product_id, supplier_id) values (pg_temp.fx('pr1'), pg_temp.fx('su1'));
  insert into public.health_surveys(survey_no, full_name, first_name, phone, occupation)
  values ('M532-S1-' || s, 'M532 Surveyed', 'M532', '+61491570532', 'Before') returning id into u; perform pg_temp.put('hs', u);
  insert into public.health_symptom_options(category, label) values ('M532', 'M532 Symptom ' || s) returning id into u; perform pg_temp.put('hso', u);
  -- A promotion to take apart, with a choice group of two options, an item and a price.
  insert into public.promotions(name, code) values ('M532 Promo X', 'M532-PX-' || s) returning id into u; perform pg_temp.put('px', u);
  insert into public.promotion_choice_groups(promotion_id, label, item_kind, choose_qty)
  values (pg_temp.fx('px'), 'M532 Group X', 'product', 1) returning id into u; perform pg_temp.put('gx', u);
  insert into public.promotion_choice_options(group_id, product_id) values (pg_temp.fx('gx'), pg_temp.fx('pr1'));
  insert into public.promotion_choice_options(group_id, product_id) values (pg_temp.fx('gx'), pg_temp.fx('pr2'));
  insert into public.promotion_items(promotion_id, item_type, product_id, quantity) values (pg_temp.fx('px'), 'product', pg_temp.fx('pr1'), 1);
  insert into public.promotion_store_prices(promotion_id, store_id, selling_price) values (pg_temp.fx('px'), pg_temp.fx('sa'), 10);
  -- A promotion for the items and prices, and one group whose options cascade.
  insert into public.promotions(name, code) values ('M532 Promo Y', 'M532-PY-' || s) returning id into u; perform pg_temp.put('py', u);
  insert into public.promotion_choice_groups(promotion_id, label, item_kind, choose_qty)
  values (pg_temp.fx('py'), 'M532 Group Y', 'product', 1) returning id into u; perform pg_temp.put('gy', u);
  insert into public.promotion_choice_options(group_id, product_id) values (pg_temp.fx('gy'), pg_temp.fx('pr1'));
  insert into public.promotion_choice_options(group_id, product_id) values (pg_temp.fx('gy'), pg_temp.fx('pr2'));
end $fx$;
-- Prices, stock, a special product and an item, through the pages' functions as the Owner.
do $fx2$
declare t text;
begin
  t := pg_temp.as_('own', format('select public.set_product_prices(%L, %L, 20, 20, %L)::text', pg_temp.fx('sa'), pg_temp.fx('pr1'), 'available'));
  if t not like 'ok:%' then raise exception 'FIXTURE set_product_prices: %', t; end if;
  t := pg_temp.as_('own', format('select public.set_voucher_prices(%L, %L, 30, 30, true)::text', pg_temp.fx('v1'), pg_temp.fx('sa')));
  if t not like 'ok:%' then raise exception 'FIXTURE set_voucher_prices: %', t; end if;
  t := pg_temp.as_('own', format('select public.voucher_stock_in(%L, %L, 5, null, %L)::text', pg_temp.fx('v1'), pg_temp.fx('sa'), gen_random_uuid()));
  if t not like 'ok:%' then raise exception 'FIXTURE voucher_stock_in: %', t; end if;
  t := pg_temp.as_('own', format('select public.set_promotion_prices(%L, %L, 40, 40, true)::text', pg_temp.fx('py'), pg_temp.fx('sa')));
  if t not like 'ok:%' then raise exception 'FIXTURE set_promotion_prices: %', t; end if;
  t := pg_temp.as_('own', format('select public.upsert_special_product_from_product(null, %L, 100)::text', pg_temp.fx('pr1')));
  if t not like 'ok:%' then raise exception 'FIXTURE upsert_special_product_from_product: %', t; end if;
  perform pg_temp.put('sp1', substr(t, 4)::uuid);
end $fx2$;
select pg_temp.put('spp1', id) from public.store_product_prices where store_id = pg_temp.fx('sa') and product_id = pg_temp.fx('pr1');
select pg_temp.put('vsp1', id) from public.voucher_store_prices where store_id = pg_temp.fx('sa') and voucher_id = pg_temp.fx('v1');
select pg_temp.put('vss1', id) from public.voucher_store_stock where store_id = pg_temp.fx('sa') and voucher_id = pg_temp.fx('v1');
select pg_temp.put('psp1', id) from public.promotion_store_prices where store_id = pg_temp.fx('sa') and promotion_id = pg_temp.fx('py');
select pg_temp.put('pix', id) from public.promotion_items where promotion_id = pg_temp.fx('px');
do $$ begin
  if pg_temp.fx('sp1') is null or pg_temp.fx('spp1') is null or pg_temp.fx('vsp1') is null or pg_temp.fx('vss1') is null
     or pg_temp.fx('psp1') is null or pg_temp.fx('pix') is null then
    raise exception 'FIXTURE: a price, stock, special product or item row is missing'; end if;
end $$;

-- ═════ R The report's local check, and the stores rule ═════
-- The report's check as written: a Manager not working at store B changes its PayNow UEN straight
-- on the table. Since 532 (the user: "Managers: own stores only") nothing changes and nothing is
-- recorded; at their own store it is changed and recorded, and an Owner changes every store.
do $R$
declare t text; c int;
begin
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('update public.stores set paynow_uen = %L where id = %L', 'TEST-UEN', pg_temp.fx('sb')));
  select count(*) into c from public.audit_logs where table_name = 'stores' and created_at > now() - interval '1 minute'
     and not exists (select 1 from seen s where s.id = audit_logs.id);
  perform pg_temp.check(t = 'ok:0' and c = 0 and (select paynow_uen from public.stores where id = pg_temp.fx('sb')) = 'UEN-B-OLD',
    'R1 the report''s check: a Manager of stores A and M changes store B''s PayNow UEN straight: no row changed, 0 audit rows: ' || t || ' / ' || c);
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('update public.stores set paynow_uen = %L where id = %L', 'TEST-UEN', pg_temp.fx('sa')));
  select count(*) into c from public.audit_logs where table_name = 'stores' and created_at > now() - interval '1 minute'
     and not exists (select 1 from seen s where s.id = audit_logs.id);
  perform pg_temp.check(t = 'ok:1' and c = 1, 'R2 the Manager changes their own store A''s PayNow UEN: 1 row, exactly 1 audit row for stores: ' || t || ' / ' || c);
  perform pg_temp.check(pg_temp.saw() = 'stores/store_updated/sa/sa/stores/mgr', 'R3 store_updated, under store A, the Manager, module stores: ' || pg_temp.saw());
  perform pg_temp.check(pg_temp.od() = '{"paynow_uen": "UEN-A-OLD"}' and pg_temp.nd() = '{"paynow_uen": "TEST-UEN"}' and pg_temp.role_of() = 'manager',
    'R4 the old and the new UEN only, and the role: ' || coalesce(pg_temp.od()::text, 'null') || ' -> ' || coalesce(pg_temp.nd()::text, 'null'));
  perform pg_temp.mark();
  t := pg_temp.n('own', format('update public.stores set paynow_uen = %L where id = %L', 'UEN-B-NEW', pg_temp.fx('sb')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'stores/store_updated/sb/sb/stores/own' and pg_temp.nd() = '{"paynow_uen": "UEN-B-NEW"}',
    'R5 the Owner changes store B (any store), recorded: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('update public.stores set bank_account = %L where id = %L', '999', pg_temp.fx('sm')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'stores/store_updated/sm/sm/stores/mgr', 'R6 the Manager changes their other store M: ' || t || ' / ' || pg_temp.saw());
  t := pg_temp.n('adm', format('update public.stores set bank_account = %L where id = %L', '111', pg_temp.fx('sa')));
  perform pg_temp.check(t = 'ok:0', 'R7 an Admin changes no store (read-only, as before): ' || t);
  t := pg_temp.n('stf', format('update public.stores set bank_account = %L where id = %L', '111', pg_temp.fx('sa')));
  perform pg_temp.check(t = 'ok:0', 'R8 Staff of store A change no store: ' || t);
  t := pg_temp.n('inv', format('update public.stores set bank_account = %L where id = %L', '111', pg_temp.fx('sa')));
  perform pg_temp.check(t = 'ok:0', 'R9 an Inventory Manager changes no store: ' || t);
  perform pg_temp.mark();
  t := pg_temp.as_('mgr', format('insert into public.stores(name, code) values (%L, %L) returning id::text', 'M532 Store X', 'M532-X-' || pg_temp.sfx()));
  perform pg_temp.check(t like 'ERR 42501 new row violates row-level security policy%' and pg_temp.saw() = '', 'R10 a Manager cannot add a store: ' || t);
  t := pg_temp.as_('adm', format('insert into public.stores(name, code) values (%L, %L) returning id::text', 'M532 Store Y', 'M532-Y-' || pg_temp.sfx()));
  perform pg_temp.check(t like 'ERR 42501 new row violates row-level security policy%', 'R11 an Admin cannot add a store: ' || t);
  -- (an Owner adds one: T1a)
  t := pg_temp.n('mgr', format('update public.stores set id = %L where id = %L', gen_random_uuid(), pg_temp.fx('sm')));
  perform pg_temp.check(t like 'ERR 42501 new row violates row-level security policy%', 'R12 the Manager cannot move their store''s row out of their stores (WITH CHECK): ' || t);
  -- Delete and Restore on the Stores page.
  perform pg_temp.mark();
  t := pg_temp.as_('mgr', format('select public.soft_delete_store(%L)::text', pg_temp.fx('sb')));
  perform pg_temp.check(t = 'ERR 42501 A Manager can delete only the stores they work at.' and pg_temp.saw() = ''
    and (select deleted_at is null from public.stores where id = pg_temp.fx('sb')), 'R13 a Manager cannot delete a store they do not work at: ' || t);
  perform pg_temp.mark();
  t := pg_temp.as_('mgr', format('select public.soft_delete_store(%L)::text', pg_temp.fx('sm')));
  perform pg_temp.check(t like 'ok:%"already": false%' and pg_temp.acts() = 'stores/store_deleted', 'R14 the Manager deletes their own store M (its own entry only): ' || t || ' / ' || pg_temp.acts());
  perform pg_temp.mark();
  t := pg_temp.as_('mgr', format('select public.restore_store(%L)::text', pg_temp.fx('sm')));
  perform pg_temp.check(t like 'ok:%"already": false%' and pg_temp.acts() = 'stores/store_restored', 'R15 and restores it: ' || t || ' / ' || pg_temp.acts());
  t := pg_temp.as_('own', format('select public.soft_delete_store(%L)::text', pg_temp.fx('sb')));
  perform pg_temp.mark();
  t := pg_temp.as_('mgr', format('select public.restore_store(%L)::text', pg_temp.fx('sb')));
  perform pg_temp.check(t = 'ERR 42501 A Manager can restore only the stores they work at.' and pg_temp.saw() = ''
    and (select deleted_at is not null from public.stores where id = pg_temp.fx('sb')), 'R16 a Manager cannot restore a store they do not work at: ' || t);
  t := pg_temp.as_('svc', format('select public.restore_store(%L)::text', pg_temp.fx('sb')));
  perform pg_temp.check(t like 'ok:%"already": false%' and (select deleted_at is null from public.stores where id = pg_temp.fx('sb')),
    'R17 the secret key still restores any store (no login: require_active_staff gives no role): ' || t);
end $R$;

-- ═════ T Each table ═════
-- T1 stores (the Stores page: insert, update; deleted_at set and cleared straight).
do $T$
declare t text; v uuid; s text := pg_temp.sfx();
begin
  perform pg_temp.mark();
  t := pg_temp.as_('own', format('insert into public.stores(name, code, bank_account) values (%L, %L, %L) returning id::text', 'M532 Store N', 'M532-N-' || s, '000-111'));
  if t like 'ok:%' then v := pg_temp.put('sn', substr(t, 4)::uuid); end if;
  perform pg_temp.check(t like 'ok:%' and pg_temp.saw() = 'stores/store_created/sn/sn/stores/own' and pg_temp.od() is null
    and pg_temp.nd() ->> 'bank_account' = '000-111' and pg_temp.nd() ->> 'id' = v::text,
    'T1a a store added straight: store_created with the whole new row: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('own', format('update public.stores set gst_enabled = true, gst_rate = 9, qr_paynow_url = %L where id = %L', 'https://example.invalid/qr', v));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'stores/store_updated/sn/sn/stores/own'
    and pg_temp.od() = '{"gst_enabled": false, "qr_paynow_url": null}' and pg_temp.nd() = '{"gst_enabled": true, "qr_paynow_url": "https://example.invalid/qr"}',
    'T1b an update records only the columns changed (gst_rate 9 = 9.0 is no change): ' || coalesce(pg_temp.od()::text, pg_temp.saw()) || ' -> ' || coalesce(pg_temp.nd()::text, ''));
  perform pg_temp.mark();
  t := pg_temp.n('own', format('update public.stores set deleted_at = now(), is_active = false where id = %L', v));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'stores/store_deleted/sn/sn/stores/own' and pg_temp.nd() ? 'deleted_at',
    'T1c deleted_at set: store_deleted: ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('own', format('update public.stores set deleted_at = null, is_active = true where id = %L', v));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'stores/store_restored/sn/sn/stores/own', 'T1d deleted_at cleared: store_restored: ' || pg_temp.saw());
end $T$;
-- T2 warehouses.
do $T$
declare t text; v uuid; s text := pg_temp.sfx();
begin
  perform pg_temp.mark();
  t := pg_temp.as_('mgr', format('insert into public.warehouses(name, code) values (%L, %L) returning id::text', 'M532 Warehouse N', 'M532-WN-' || s));
  if t like 'ok:%' then v := pg_temp.put('wn', substr(t, 4)::uuid); end if;
  perform pg_temp.check(t like 'ok:%' and pg_temp.saw() = 'warehouses/warehouse_created/wn/-/warehouses/mgr', 'T2a warehouse_created: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('update public.warehouses set name = %L where id = %L', 'M532 Warehouse N2', v));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'warehouses/warehouse_updated/wn/-/warehouses/mgr'
    and pg_temp.od() = '{"name": "M532 Warehouse N"}' and pg_temp.nd() = '{"name": "M532 Warehouse N2"}', 'T2b warehouse_updated, the name only: ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('update public.warehouses set deleted_at = now(), is_active = false where id = %L', v));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'warehouses/warehouse_deleted/wn/-/warehouses/mgr', 'T2c warehouse_deleted: ' || pg_temp.saw());
end $T$;
-- T3 payment_methods (the Payment Methods page: insert, rename, delete, restore; a hard delete).
do $T$
declare t text; v uuid; s text := pg_temp.sfx();
begin
  perform pg_temp.mark();
  t := pg_temp.as_('own', format('insert into public.payment_methods(name) values (%L) returning id::text', 'M532 Pay ' || s));
  if t like 'ok:%' then v := pg_temp.put('pm', substr(t, 4)::uuid); end if;
  perform pg_temp.check(t like 'ok:%' and pg_temp.saw() = 'payment_methods/payment_method_created/pm/-/payment_methods/own'
    and pg_temp.nd() ->> 'is_wallet_credit' = 'false', 'T3a payment_method_created with its wallet settings: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('own', format('update public.payment_methods set name = %L, is_active = false where id = %L', 'M532 Pay Renamed ' || s, v));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'payment_methods/payment_method_updated/pm/-/payment_methods/own'
    and pg_temp.od() = jsonb_build_object('name', 'M532 Pay ' || s, 'is_active', true) and pg_temp.nd() = jsonb_build_object('name', 'M532 Pay Renamed ' || s, 'is_active', false),
    'T3b renamed and switched off: recorded, before and after: ' || coalesce(pg_temp.nd()::text, pg_temp.saw()));
  perform pg_temp.mark();
  t := pg_temp.n('own', format('update public.payment_methods set deleted_at = now(), is_active = false where id = %L', v));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'payment_methods/payment_method_deleted/pm/-/payment_methods/own', 'T3c payment_method_deleted: ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('own', format('update public.payment_methods set deleted_at = null, is_active = true where id = %L', v));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'payment_methods/payment_method_restored/pm/-/payment_methods/own', 'T3d payment_method_restored: ' || pg_temp.saw());
  perform pg_temp.mark();
  -- (Since 532 no login deletes a payment method outright: P; the secret key still can.)
  t := pg_temp.n('svc', format('delete from public.payment_methods where id = %L', v));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'payment_methods/payment_method_removed/pm/-/payment_methods/-'
    and pg_temp.od() ->> 'id' = v::text and pg_temp.nd() is null and pg_temp.role_of() = 'service_role',
    'T3e payment_method_removed (the secret key) with the old row: ' || pg_temp.saw());
end $T$;
-- T4 promotions (the Promotions page: insert, update, delete).
do $T$
declare t text; v uuid; s text := pg_temp.sfx();
begin
  perform pg_temp.mark();
  t := pg_temp.as_('mgr', format('insert into public.promotions(name, code, fixed_price) values (%L, %L, 99) returning id::text', 'M532 Promo N', 'M532-PN-' || s));
  if t like 'ok:%' then v := pg_temp.put('pn', substr(t, 4)::uuid); end if;
  perform pg_temp.check(t like 'ok:%' and pg_temp.saw() = 'promotions/promotion_created/pn/-/promotions/mgr', 'T4a promotion_created, module promotions: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('update public.promotions set fixed_price = 89, terms = %L where id = %L', 'M532 terms', v));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'promotions/promotion_updated/pn/-/promotions/mgr'
    and pg_temp.od() = '{"terms": null, "fixed_price": 99.00}' and pg_temp.nd() = '{"terms": "M532 terms", "fixed_price": 89.00}', 'T4b promotion_updated: ' || coalesce(pg_temp.nd()::text, pg_temp.saw()));
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('update public.promotions set deleted_at = now(), is_active = false where id = %L', v));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'promotions/promotion_deleted/pn/-/promotions/mgr', 'T4c the page''s Delete: promotion_deleted: ' || pg_temp.saw());
end $T$;
-- T5 promotion_choice_groups and T6 promotion_choice_options (insert, update, delete).
do $T$
declare t text; g uuid; o uuid;
begin
  perform pg_temp.mark();
  t := pg_temp.as_('mgr', format('insert into public.promotion_choice_groups(promotion_id, label, item_kind, choose_qty) values (%L, %L, %L, 1) returning id::text',
    pg_temp.fx('py'), 'M532 Group N', 'product'));
  if t like 'ok:%' then g := pg_temp.put('gn', substr(t, 4)::uuid); end if;
  perform pg_temp.check(t like 'ok:%' and pg_temp.saw() = 'promotion_choice_groups/promotion_choice_group_created/py/-/promotions/mgr'
    and pg_temp.nd() ->> 'id' = g::text, 'T5a a choice group added: under its promotion, its own id in the data: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  -- (Since 532 no login edits a choice in place: P; the secret key still can.)
  t := pg_temp.n('svc', format('update public.promotion_choice_groups set choose_qty = 2 where id = %L', g));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'promotion_choice_groups/promotion_choice_group_updated/py/-/promotions/-'
    and pg_temp.od() = '{"choose_qty": 1}' and pg_temp.nd() = jsonb_build_object('choose_qty', 2, 'row_id', g), 'T5b a choice group changed: row_id kept: ' || coalesce(pg_temp.nd()::text, pg_temp.saw()));
  perform pg_temp.mark();
  t := pg_temp.as_('mgr', format('insert into public.promotion_choice_options(group_id, product_id) values (%L, %L) returning id::text', g, pg_temp.fx('pr3')));
  if t like 'ok:%' then o := pg_temp.put('on', substr(t, 4)::uuid); end if;
  perform pg_temp.check(t like 'ok:%' and pg_temp.saw() = 'promotion_choice_options/promotion_choice_option_created/py/-/promotions/mgr'
    and pg_temp.nd() ->> 'id' = o::text and pg_temp.nd() ->> 'group_id' = g::text, 'T6a a choice option added: under its group''s promotion: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('svc', format('update public.promotion_choice_options set product_id = %L where id = %L', pg_temp.fx('pr2'), o));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'promotion_choice_options/promotion_choice_option_updated/py/-/promotions/-'
    and pg_temp.nd() = jsonb_build_object('product_id', pg_temp.fx('pr2'), 'row_id', o), 'T6b a choice option changed: ' || coalesce(pg_temp.nd()::text, pg_temp.saw()));
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('delete from public.promotion_choice_options where id = %L', o));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'promotion_choice_options/promotion_choice_option_removed/py/-/promotions/mgr'
    and pg_temp.od() ->> 'id' = o::text, 'T6c a choice option removed: ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('delete from public.promotion_choice_groups where id = %L', g));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'promotion_choice_groups/promotion_choice_group_removed/py/-/promotions/mgr', 'T5c an empty choice group removed: ' || pg_temp.saw());
end $T$;
-- T7 promotion_items: the page adds through add_promotion_item (F) and removes straight.
do $T$
declare t text;
begin
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('delete from public.promotion_items where id = %L', pg_temp.fx('pix')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'promotion_items/promotion_item_removed/px/-/catalogue/mgr'
    and pg_temp.od() ->> 'id' = pg_temp.fx('pix')::text, 'T7 the page''s Remove: promotion_item_removed under the promotion, module catalogue: ' || t || ' / ' || pg_temp.saw());
end $T$;
-- T8 special_products: the page's Delete is a straight update.
do $T$
declare t text;
begin
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('update public.special_products set deleted_at = now(), is_active = false where id = %L', pg_temp.fx('sp1')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'special_products/special_product_deleted/sp1/-/catalogue/mgr', 'T8a the Special page''s Delete: special_product_deleted, module catalogue: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('update public.special_products set deleted_at = null, is_active = true where id = %L', pg_temp.fx('sp1')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'special_products/special_product_restored/sp1/-/catalogue/mgr', 'T8b special_product_restored: ' || pg_temp.saw());
end $T$;
-- T9 survey_links (the Surveys page: insert, switch on and off; a delete).
do $T$
declare t text; v uuid;
begin
  perform pg_temp.mark();
  t := pg_temp.as_('mgr', format('insert into public.survey_links(token, store_id, event_name, created_by) values (%L, %L, %L, %L) returning id::text',
    'm532-' || pg_temp.sfx() || '-tok', pg_temp.fx('sb'), 'M532 Event', pg_temp.fx('mgr')));
  if t like 'ok:%' then v := pg_temp.put('sl', substr(t, 4)::uuid); end if;
  perform pg_temp.check(t like 'ok:%' and pg_temp.saw() = 'survey_links/survey_link_created/sl/sb/survey_links/mgr', 'T9a survey_link_created, under the link''s store: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('update public.survey_links set is_active = false where id = %L', v));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'survey_links/survey_link_updated/sl/sb/survey_links/mgr'
    and pg_temp.od() = '{"is_active": true}' and pg_temp.nd() = '{"is_active": false}', 'T9b the page''s switch: survey_link_updated: ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('svc', format('delete from public.survey_links where id = %L', v));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'survey_links/survey_link_removed/sl/sb/survey_links/-', 'T9c survey_link_removed (the secret key): ' || pg_temp.saw());
end $T$;
-- T10-T12 brands, categories, suppliers (the catalogue lists: add, edit, delete, restore; a delete).
do $T$
declare t text; v uuid; r record;
begin
  for r in select * from (values ('brands', 'brand', 'T10'), ('categories', 'category', 'T11'), ('suppliers', 'supplier', 'T12')) x(tb, noun, tag) loop
    perform pg_temp.mark();
    t := pg_temp.as_('own', format('insert into public.%I(name) values (%L) returning id::text', r.tb, 'M532 New ' || r.noun || ' ' || pg_temp.sfx()));
    if t like 'ok:%' then v := pg_temp.put(r.noun, substr(t, 4)::uuid); else v := null; end if;
    perform pg_temp.check(t like 'ok:%' and pg_temp.saw() = format('%s/%s_created/%s/-/%s/own', r.tb, r.noun, r.noun, r.tb), r.tag || 'a ' || r.noun || '_created: ' || t || ' / ' || pg_temp.saw());
    perform pg_temp.mark();
    t := pg_temp.n('own', format('update public.%I set name = %L, updated_at = now() + interval ''1 second'' where id = %L', r.tb, 'M532 Renamed ' || r.noun || ' ' || pg_temp.sfx(), v));
    perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = format('%s/%s_updated/%s/-/%s/own', r.tb, r.noun, r.noun, r.tb)
      and (select array_agg(k order by k) from jsonb_object_keys(pg_temp.nd()) k) = array['name'], r.tag || 'b ' || r.noun || '_updated, the name only (updated_at left out): ' || coalesce(pg_temp.nd()::text, pg_temp.saw()));
    perform pg_temp.mark();
    t := pg_temp.n('own', format('update public.%I set deleted_at = now(), is_active = false where id = %L', r.tb, v));
    perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = format('%s/%s_deleted/%s/-/%s/own', r.tb, r.noun, r.noun, r.tb), r.tag || 'c ' || r.noun || '_deleted: ' || pg_temp.saw());
    perform pg_temp.mark();
    t := pg_temp.n('own', format('update public.%I set deleted_at = null, is_active = true where id = %L', r.tb, v));
    perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = format('%s/%s_restored/%s/-/%s/own', r.tb, r.noun, r.noun, r.tb), r.tag || 'd ' || r.noun || '_restored: ' || pg_temp.saw());
    perform pg_temp.mark();
    t := pg_temp.n('svc', format('delete from public.%I where id = %L', r.tb, v));
    perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = format('%s/%s_removed/%s/-/%s/-', r.tb, r.noun, r.noun, r.tb), r.tag || 'e ' || r.noun || '_removed (the secret key): ' || t || ' / ' || pg_temp.saw());
  end loop;
end $T$;

-- ═════ N No change, no entry ═════
do $N$
declare t text;
begin
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('update public.stores set name = name, paynow_uen = paynow_uen where id = %L', pg_temp.fx('sa')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = '', 'N1 a store saved with nothing changed: no entry: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('own', format('update public.suppliers set updated_at = now() + interval ''1 minute'' where id = %L', pg_temp.fx('su1')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = '', 'N2 only updated_at changed: no entry: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('update public.promotions set name = %L, fixed_price = 0, is_active = true where id = %L', 'M532 Promo Y', pg_temp.fx('py')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = '', 'N3 a promotion saved again as it is: no entry: ' || t || ' / ' || pg_temp.saw());
end $N$;

-- ═════ F A server function: its own entry only ═════
do $F$
declare t text;
begin
  perform pg_temp.mark();
  t := pg_temp.as_('own', format('select public.soft_delete_store(%L)::text', pg_temp.fx('sf')));
  perform pg_temp.check(t like 'ok:%' and pg_temp.acts() = 'stores/store_deleted' and pg_temp.od() ? 'name',
    'F1 soft_delete_store (the Owner, any store): only its own store_deleted: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.as_('own', format('select public.restore_store(%L)::text', pg_temp.fx('sf')));
  perform pg_temp.check(t like 'ok:%' and pg_temp.acts() = 'stores/store_restored' and pg_temp.od() is null,
    'F2 restore_store: only its own store_restored: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.as_('mgr', format('select public.soft_delete_warehouse(%L)::text', pg_temp.fx('wf')));
  perform pg_temp.check(t like 'ok:%' and pg_temp.acts() = 'warehouses/warehouse_deleted' and pg_temp.od() ? 'name',
    'F3 soft_delete_warehouse: only its own entry: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.as_('mgr', format('select public.restore_warehouse(%L)::text', pg_temp.fx('wf')));
  perform pg_temp.check(t like 'ok:%' and pg_temp.acts() = 'warehouses/warehouse_restored', 'F4 restore_warehouse: only its own entry: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.as_('mgr', format('select public.add_promotion_item(%L, %L, %L)::text', pg_temp.fx('py'), 'product', pg_temp.fx('pr2')));
  perform pg_temp.check(t like 'ok:%' and pg_temp.acts() = 'promotion_items/promotion_item_added',
    'F5 add_promotion_item (the page''s Add): only its own promotion_item_added: ' || t || ' / ' || pg_temp.acts());
  perform pg_temp.mark();
  t := pg_temp.as_('own', format('select public.upsert_special_product_from_product(null, %L, 150)::text', pg_temp.fx('pr2')));
  if t like 'ok:%' then perform pg_temp.put('sp2', substr(t, 4)::uuid); end if;
  perform pg_temp.check(t like 'ok:%' and pg_temp.acts() = 'special_products/special_product_saved',
    'F6 upsert_special_product_from_product (the Special page''s Save): only its own special_product_saved: ' || t || ' / ' || pg_temp.acts());
  perform pg_temp.mark();
  t := pg_temp.as_('own', format('select public.upsert_special_product_from_product(%L, %L, 160)::text', pg_temp.fx('sp2'), pg_temp.fx('pr2')));
  perform pg_temp.check(t like 'ok:%' and pg_temp.acts() not like '%special_product_updated%' and pg_temp.acts() not like '%special_product_created%',
    'F7 the same Save again with a new price: no entry of the trigger: ' || t || ' / ' || pg_temp.acts());
  perform pg_temp.mark();
  t := pg_temp.as_('own', format('select public.set_special_product_consignment(%L, true)::text', pg_temp.fx('sp2')));
  perform pg_temp.check(t like 'ok:%' and pg_temp.acts() = 'special_products/special_product_consignment',
    'F8 set_special_product_consignment: only its own entry: ' || t || ' / ' || pg_temp.acts());
end $F$;

-- ═════ C A cascade: one entry ═════
do $C$
declare t text;
begin
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('delete from public.promotion_choice_groups where id = %L', pg_temp.fx('gy')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'promotion_choice_groups/promotion_choice_group_removed/py/-/promotions/mgr'
    and not exists (select 1 from public.promotion_choice_options where group_id = pg_temp.fx('gy')),
    'C1 a choice group with two options deleted: its options go, 1 entry: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('delete from public.promotions where id = %L', pg_temp.fx('px')));
  perform pg_temp.check(t = 'ok:0' and pg_temp.saw() = '' and exists (select 1 from public.promotions where id = pg_temp.fx('px')),
    'C2a a Manager cannot delete a promotion outright (since 532): ' || t);
  perform pg_temp.mark();
  t := pg_temp.n('svc', format('delete from public.promotions where id = %L', pg_temp.fx('px')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'promotions/promotion_removed/px/-/promotions/-'
    and not exists (select 1 from public.promotion_choice_groups where promotion_id = pg_temp.fx('px'))
    and not exists (select 1 from public.promotion_store_prices where promotion_id = pg_temp.fx('px')),
    'C2 a promotion with its choices, item and price deleted (the secret key): 1 entry: ' || t || ' / ' || pg_temp.saw());
end $C$;

-- ═════ S The secret key and the database owner ═════
do $S$
declare t text;
begin
  perform pg_temp.mark();
  t := pg_temp.n('svc', format('update public.stores set bank_account = %L where id = %L', '222-333', pg_temp.fx('sb')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'stores/store_updated/sb/sb/stores/-' and pg_temp.nd() = '{"bank_account": "222-333"}'
    and pg_temp.role_of() = 'service_role',
    'S1 the secret key''s direct change: 1 entry, no login, actor_role service_role: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('pg', format('update public.stores set bank_account = %L where id = %L', '444-555', pg_temp.fx('sb')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = '', 'S2 the database owner''s change (the SQL editor): no entry: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('svc', format('delete from public.stores where id = %L', pg_temp.fx('sgone')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'stores/store_removed/sgone/-/stores/-' and pg_temp.od() ->> 'id' = pg_temp.fx('sgone')::text,
    'S3 a store deleted outright: store_removed with the old row and no store: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('svc', format('delete from public.warehouses where id = %L', pg_temp.fx('wgone')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'warehouses/warehouse_removed/wgone/-/warehouses/-', 'S4 warehouse_removed: ' || t || ' / ' || pg_temp.saw());
end $S$;

-- ═════ P The dropped rules: a direct write refused, the page's function saves ═════
-- A refused insert: an error of row level security; a refused update or delete: no row changed.
create function pg_temp.refused(t text) returns boolean language sql as
$$ select t like 'ERR 42501 new row violates row-level security policy%' or t = 'ok:0' $$;
do $P$
declare t text; t2 text; s text := pg_temp.sfx();
begin
  -- health_surveys "update surveys"
  t := pg_temp.n('own', format('update public.health_surveys set occupation = %L where id = %L', 'Changed straight', pg_temp.fx('hs')));
  t2 := pg_temp.as_('own', format('select public.update_survey_particulars_v2(%L, %L::jsonb)::text', pg_temp.fx('hs'), '{"occupation": "Changed by the page"}'));
  perform pg_temp.check(t = 'ok:0' and t2 like 'ok:%' and (select occupation from public.health_surveys where id = pg_temp.fx('hs')) = 'Changed by the page',
    'P1 health_surveys: an Owner''s direct update changes nothing; Edit details (update_survey_particulars_v2) saves: ' || t || ' / ' || t2);
  -- health_symptom_options insert / update / delete (no page writes it)
  t := pg_temp.n('own', format('insert into public.health_symptom_options(category, label) values (%L, %L)', 'M532', 'M532 Straight ' || s));
  perform pg_temp.check(pg_temp.refused(t) and t <> 'ok:0', 'P2 health_symptom_options: an Owner''s direct insert is refused: ' || t);
  t := pg_temp.n('own', format('update public.health_symptom_options set label = %L where id = %L', 'M532 Changed', pg_temp.fx('hso')));
  perform pg_temp.check(t = 'ok:0', 'P3 health_symptom_options: a direct update changes nothing: ' || t);
  t := pg_temp.n('own', format('delete from public.health_symptom_options where id = %L', pg_temp.fx('hso')));
  perform pg_temp.check(t = 'ok:0' and exists (select 1 from public.health_symptom_options where id = pg_temp.fx('hso')), 'P4 health_symptom_options: a direct delete changes nothing: ' || t);
  t := pg_temp.as_('stf', format('select count(*)::text from public.health_symptom_options where id = %L', pg_temp.fx('hso')));
  perform pg_temp.check(t = 'ok:1', 'P4r the symptom list is still read: ' || t);
  -- product_categories / product_suppliers "write" (ALL), as an Inventory Manager
  t := pg_temp.n('inv', format('insert into public.product_categories(product_id, category_id) values (%L, %L)', pg_temp.fx('pr2'), pg_temp.fx('c1')));
  t2 := pg_temp.n('inv', format('delete from public.product_categories where product_id = %L', pg_temp.fx('pr1')));
  perform pg_temp.check(pg_temp.refused(t) and t <> 'ok:0' and t2 = 'ok:0', 'P5 product_categories: an Inventory Manager''s direct insert and delete are refused: ' || t || ' / ' || t2);
  t := pg_temp.n('inv', format('insert into public.product_suppliers(product_id, supplier_id) values (%L, %L)', pg_temp.fx('pr2'), pg_temp.fx('su1')));
  t2 := pg_temp.n('inv', format('delete from public.product_suppliers where product_id = %L', pg_temp.fx('pr1')));
  perform pg_temp.check(pg_temp.refused(t) and t <> 'ok:0' and t2 = 'ok:0', 'P6 product_suppliers: an Inventory Manager''s direct insert and delete are refused: ' || t || ' / ' || t2);
  t := pg_temp.as_('inv', format('select public.save_product(%L, %L::jsonb, array[%L]::uuid[], array[%L]::uuid[])::text',
    pg_temp.fx('pr2'), '{}', pg_temp.fx('c1'), pg_temp.fx('su1')));
  perform pg_temp.check(t like 'ok:%' and exists (select 1 from public.product_categories where product_id = pg_temp.fx('pr2') and category_id = pg_temp.fx('c1'))
    and exists (select 1 from public.product_suppliers where product_id = pg_temp.fx('pr2') and supplier_id = pg_temp.fx('su1')),
    'P5s/P6s the Products page''s Save (save_product) sets the category and supplier: ' || t);
  t := pg_temp.as_('stf', format('select (select count(*) from public.product_categories where product_id = %L) || ''/'' || (select count(*) from public.product_suppliers where product_id = %L)', pg_temp.fx('pr2'), pg_temp.fx('pr2')));
  perform pg_temp.check(t = 'ok:1/1', 'P5r/P6r Staff still read the product''s category and supplier (the "read" rules stay): ' || t);
  -- products "insert products", "update products", as an Inventory Manager
  t := pg_temp.n('inv', format('insert into public.products(name, sku) values (%L, %L)', 'M532 Straight', 'M532-ST-' || s));
  perform pg_temp.check(pg_temp.refused(t) and t <> 'ok:0', 'P7 products: an Inventory Manager''s direct insert is refused: ' || t);
  t := pg_temp.n('inv', format('update public.products set default_cost_price = 1 where id = %L', pg_temp.fx('pr1')));
  perform pg_temp.check(t = 'ok:0', 'P8 products: a direct update changes nothing: ' || t);
  t := pg_temp.as_('inv', format('select public.save_product(null, %L::jsonb)::text', jsonb_build_object('name', 'M532 Saved', 'sku', 'M532-SV-' || s, 'default_cost_price', '7')));
  t2 := case when t like 'ok:%' then pg_temp.as_('inv', format('select public.save_product(%L, %L::jsonb)::text', (substr(t, 4)::jsonb ->> 'product_id'), '{"default_cost_price": "8"}')) end;
  perform pg_temp.check(t like 'ok:%' and t2 like 'ok:%' and (select default_cost_price from public.products where id = (substr(t, 4)::jsonb ->> 'product_id')::uuid) = 8,
    'P7s/P8s save_product adds and changes a product: ' || t || ' / ' || coalesce(t2, ''));
  -- promotion_items "insert promotion items", "update promotion items", as a Manager
  t := pg_temp.n('mgr', format('insert into public.promotion_items(promotion_id, item_type, product_id, quantity) values (%L, %L, %L, 1)', pg_temp.fx('py'), 'product', pg_temp.fx('pr1')));
  perform pg_temp.check(pg_temp.refused(t) and t <> 'ok:0', 'P9 promotion_items: a Manager''s direct insert is refused (the page adds through add_promotion_item, F5): ' || t);
  t := pg_temp.n('mgr', format('update public.promotion_items set quantity = 9 where promotion_id = %L', pg_temp.fx('py')));
  perform pg_temp.check(t = 'ok:0', 'P10 promotion_items: a direct update changes nothing: ' || t);
  -- special_products "insert special products", "delete special products"
  t := pg_temp.n('mgr', format('insert into public.special_products(name, sku) values (%L, %L)', 'M532 Special Straight', 'M532-SPS-' || s));
  perform pg_temp.check(pg_temp.refused(t) and t <> 'ok:0', 'P11 special_products: a Manager''s direct insert is refused (the page saves through upsert_special_product_from_product, F6): ' || t);
  t := pg_temp.n('mgr', format('delete from public.special_products where id = %L', pg_temp.fx('sp1')));
  perform pg_temp.check(t = 'ok:0' and exists (select 1 from public.special_products where id = pg_temp.fx('sp1')),
    'P12 special_products: a direct delete changes nothing (the page''s Delete is the update kept, T8): ' || t);
  -- store_product_prices, as a Manager
  t := pg_temp.n('mgr', format('insert into public.store_product_prices(store_id, product_id, selling_price) values (%L, %L, 1)', pg_temp.fx('sb'), pg_temp.fx('pr1')));
  perform pg_temp.check(pg_temp.refused(t) and t <> 'ok:0', 'P13 store_product_prices: a direct insert is refused: ' || t);
  t := pg_temp.n('mgr', format('update public.store_product_prices set selling_price = 1 where id = %L', pg_temp.fx('spp1')));
  perform pg_temp.check(t = 'ok:0', 'P14 store_product_prices: a direct update changes nothing: ' || t);
  t := pg_temp.n('mgr', format('delete from public.store_product_prices where id = %L', pg_temp.fx('spp1')));
  perform pg_temp.check(t = 'ok:0', 'P15 store_product_prices: a direct delete changes nothing: ' || t);
  t := pg_temp.as_('mgr', format('select public.set_product_prices(%L, %L, 25, 25, %L)::text', pg_temp.fx('sa'), pg_temp.fx('pr1'), 'available'));
  perform pg_temp.check(t like 'ok:%' and (select selling_price from public.store_product_prices where id = pg_temp.fx('spp1')) = 25,
    'P13s-P15s the Price List''s Save (set_product_prices) changes the price: ' || t);
  -- promotion_store_prices, as a Manager
  t := pg_temp.n('mgr', format('insert into public.promotion_store_prices(promotion_id, store_id, selling_price) values (%L, %L, 1)', pg_temp.fx('py'), pg_temp.fx('sb')));
  perform pg_temp.check(pg_temp.refused(t) and t <> 'ok:0', 'P16 promotion_store_prices: a direct insert is refused: ' || t);
  t := pg_temp.n('mgr', format('update public.promotion_store_prices set selling_price = 1 where id = %L', pg_temp.fx('psp1')));
  perform pg_temp.check(t = 'ok:0', 'P17 promotion_store_prices: a direct update changes nothing: ' || t);
  t := pg_temp.n('mgr', format('delete from public.promotion_store_prices where id = %L', pg_temp.fx('psp1')));
  perform pg_temp.check(t = 'ok:0', 'P18 promotion_store_prices: a direct delete changes nothing: ' || t);
  t := pg_temp.as_('mgr', format('select public.set_promotion_prices(%L, %L, 45, 45, true)::text', pg_temp.fx('py'), pg_temp.fx('sa')));
  t2 := pg_temp.as_('mgr', format('select public.set_promotion_price_all_stores(%L, 50, true)::text', pg_temp.fx('py')));
  perform pg_temp.check(t like 'ok:%' and t2 like 'ok:%'
    and (select selling_price from public.promotion_store_prices where promotion_id = pg_temp.fx('py') and store_id = pg_temp.fx('sb') and deleted_at is null) = 50,
    'P16s-P18s set_promotion_prices and set_promotion_price_all_stores save: ' || t || ' / ' || t2);
  -- voucher_store_prices, as a Manager
  t := pg_temp.n('mgr', format('insert into public.voucher_store_prices(voucher_id, store_id, selling_price) values (%L, %L, 1)', pg_temp.fx('v1'), pg_temp.fx('sb')));
  perform pg_temp.check(pg_temp.refused(t) and t <> 'ok:0', 'P19 voucher_store_prices: a direct insert is refused: ' || t);
  t := pg_temp.n('mgr', format('update public.voucher_store_prices set selling_price = 1 where id = %L', pg_temp.fx('vsp1')));
  perform pg_temp.check(t = 'ok:0', 'P20 voucher_store_prices: a direct update changes nothing: ' || t);
  t := pg_temp.n('mgr', format('delete from public.voucher_store_prices where id = %L', pg_temp.fx('vsp1')));
  perform pg_temp.check(t = 'ok:0', 'P21 voucher_store_prices: a direct delete changes nothing: ' || t);
  t := pg_temp.as_('mgr', format('select public.set_voucher_prices(%L, %L, 35, 35, true)::text', pg_temp.fx('v1'), pg_temp.fx('sa')));
  t2 := pg_temp.as_('mgr', format('select public.set_voucher_price_all_stores(%L, 36, true)::text', pg_temp.fx('v1')));
  perform pg_temp.check(t like 'ok:%' and t2 like 'ok:%'
    and (select selling_price from public.voucher_store_prices where voucher_id = pg_temp.fx('v1') and store_id = pg_temp.fx('sb') and deleted_at is null) = 36,
    'P19s-P21s set_voucher_prices and set_voucher_price_all_stores save: ' || t || ' / ' || t2);
  -- voucher_store_stock, as a Manager
  t := pg_temp.n('mgr', format('insert into public.voucher_store_stock(voucher_id, store_id, current_qty) values (%L, %L, 99)', pg_temp.fx('v1'), pg_temp.fx('sb')));
  perform pg_temp.check(pg_temp.refused(t) and t <> 'ok:0', 'P22 voucher_store_stock: a direct insert is refused: ' || t);
  t := pg_temp.n('mgr', format('update public.voucher_store_stock set current_qty = 99 where id = %L', pg_temp.fx('vss1')));
  perform pg_temp.check(t = 'ok:0', 'P23 voucher_store_stock: a direct update changes nothing: ' || t);
  t := pg_temp.n('mgr', format('delete from public.voucher_store_stock where id = %L', pg_temp.fx('vss1')));
  perform pg_temp.check(t = 'ok:0', 'P24 voucher_store_stock: a direct delete changes nothing: ' || t);
  t := pg_temp.as_('mgr', format('select public.voucher_stock_in(%L, %L, 3, null, %L)::text', pg_temp.fx('v1'), pg_temp.fx('sa'), gen_random_uuid()));
  perform pg_temp.check(t like 'ok:%' and (select current_qty from public.voucher_store_stock where id = pg_temp.fx('vss1')) = 8,
    'P22s-P24s the Vouchers page''s Stock in (voucher_stock_in) adds 3 to 5: ' || t);
end $P$;

-- ═════ Q Nine more rules no page uses: deleting outright, editing a choice in place ═════
do $Q$
declare t text; r record; s text := pg_temp.sfx(); v uuid; g uuid; o uuid;
begin
  insert into public.brands(name) values ('M532 Brand Q ' || s) returning id into v; perform pg_temp.put('bq', v);
  insert into public.payment_methods(name) values ('M532 Pay Q ' || s) returning id into v; perform pg_temp.put('pmq', v);
  insert into public.survey_links(token, store_id) values ('m532-q-' || s, pg_temp.fx('sa')) returning id into v; perform pg_temp.put('slq', v);
  insert into public.promotion_choice_groups(promotion_id, label, item_kind, choose_qty)
  values (pg_temp.fx('py'), 'M532 Group Q', 'product', 1) returning id into g;
  insert into public.promotion_choice_options(group_id, product_id) values (g, pg_temp.fx('pr1')) returning id into o;
  for r in select * from (values
      ('Q1', 'brands', 'bq'), ('Q2', 'categories', 'c1'), ('Q3', 'suppliers', 'su1'), ('Q4', 'payment_methods', 'pmq'),
      ('Q5', 'promotions', 'py'), ('Q6', 'survey_links', 'slq'), ('Q7', 'vouchers', 'v1')) x(tag, tb, k) loop
    perform pg_temp.mark();
    t := pg_temp.n('own', format('delete from public.%I where id = %L', r.tb, pg_temp.fx(r.k)));
    perform pg_temp.check(t = 'ok:0' and pg_temp.saw() = '', r.tag || ' an Owner''s outright delete on ' || r.tb || ' changes nothing: ' || t);
  end loop;
  t := pg_temp.n('mgr', format('update public.promotion_choice_groups set choose_qty = 3 where id = %L', g));
  perform pg_temp.check(t = 'ok:0', 'Q8 a Manager''s edit of a choice group in place changes nothing: ' || t);
  t := pg_temp.n('mgr', format('update public.promotion_choice_options set product_id = %L where id = %L', pg_temp.fx('pr2'), o));
  perform pg_temp.check(t = 'ok:0', 'Q9 nor of a choice option: ' || t);
  -- The pages' ways stay: delete a choice and add another; switch a row off (T); soft_delete_voucher.
  t := pg_temp.n('mgr', format('delete from public.promotion_choice_options where id = %L', o));
  perform pg_temp.check(t = 'ok:1', 'Q10 the Promotions page still deletes a choice option: ' || t);
  t := pg_temp.n('mgr', format('delete from public.promotion_choice_groups where id = %L', g));
  perform pg_temp.check(t = 'ok:1', 'Q11 and a choice group: ' || t);
  perform pg_temp.mark();
  t := pg_temp.as_('own', format('select public.soft_delete_voucher(%L, %L, true)::text', pg_temp.fx('v1'), 'M532 test'));
  perform pg_temp.check(t like 'ok:%' and (select deleted_at is not null from public.vouchers where id = pg_temp.fx('v1'))
    and pg_temp.acts() = 'vouchers/voucher_deleted', 'Q12 the Vouchers page''s Delete (soft_delete_voucher) still works, recorded by 423: ' || t || ' / ' || pg_temp.acts());
end $Q$;

-- ═════ A The store images (storage, bucket store-assets) ═════
do $A$
declare t text; s text := pg_temp.sfx();
begin
  insert into storage.objects(bucket_id, name) values ('store-assets', pg_temp.fx('sa') || '/m532-qr-paynow.png'), ('store-assets', pg_temp.fx('sb') || '/m532-qr-paynow.png');
  t := pg_temp.n('mgr', format('insert into storage.objects(bucket_id, name) values (%L, %L)', 'store-assets', pg_temp.fx('sa') || '/m532-new-' || s || '.png'));
  perform pg_temp.check(t = 'ok:1', 'A1 a Manager adds an image into their own store A''s folder: ' || t);
  t := pg_temp.n('mgr', format('insert into storage.objects(bucket_id, name) values (%L, %L)', 'store-assets', pg_temp.fx('sb') || '/m532-new-' || s || '.png'));
  perform pg_temp.check(t like 'ERR 42501 new row violates row-level security policy%', 'A2 but not into store B''s: ' || t);
  t := pg_temp.n('mgr', format('update storage.objects set metadata = %L where bucket_id = %L and name = %L', '{"m532": 1}', 'store-assets', pg_temp.fx('sa') || '/m532-qr-paynow.png'));
  perform pg_temp.check(t = 'ok:0', 'A3 nor overwrite a file in place, even their own store''s: ' || t);
  t := pg_temp.n('mgr', format('insert into storage.objects(bucket_id, name, metadata) values (%L, %L, %L) on conflict (bucket_id, name) do update set metadata = excluded.metadata',
    'store-assets', pg_temp.fx('sa') || '/m532-qr-paynow.png', '{"m532": 2}'));
  perform pg_temp.check(t like 'ERR 42501 %' and (select metadata is null from storage.objects where bucket_id = 'store-assets' and name = pg_temp.fx('sa') || '/m532-qr-paynow.png'),
    'A4 nor upsert over it: ' || t);
  t := pg_temp.n('mgr', format('delete from storage.objects where bucket_id = %L and name = %L', 'store-assets', pg_temp.fx('sa') || '/m532-qr-paynow.png'));
  perform pg_temp.check(t = 'ok:0', 'A5 nor remove one: ' || t);
  t := pg_temp.n('own', format('insert into storage.objects(bucket_id, name) values (%L, %L)', 'store-assets', pg_temp.fx('sb') || '/m532-own-' || s || '.png'));
  perform pg_temp.check(t = 'ok:1', 'A6 an Owner adds an image into any store''s folder: ' || t);
  t := pg_temp.n('own', format('update storage.objects set metadata = %L where bucket_id = %L and name = %L', '{"m532": 1}', 'store-assets', pg_temp.fx('sb') || '/m532-qr-paynow.png'));
  perform pg_temp.check(t = 'ok:0', 'A7 an Owner overwrites none in place either: ' || t);
  t := pg_temp.n('own', format('delete from storage.objects where bucket_id = %L and name = %L', 'store-assets', pg_temp.fx('sb') || '/m532-qr-paynow.png'));
  perform pg_temp.check(t = 'ok:0', 'A8 nor removes one: ' || t);
  t := pg_temp.n('own', format('insert into storage.objects(bucket_id, name) values (%L, %L)', 'store-assets', 'm532-loose-' || s || '.png'));
  perform pg_temp.check(t like 'ERR 42501 new row violates row-level security policy%', 'A9 a file in no store''s folder is refused: ' || t);
  t := pg_temp.n('adm', format('insert into storage.objects(bucket_id, name) values (%L, %L)', 'store-assets', pg_temp.fx('sa') || '/m532-adm-' || s || '.png'));
  perform pg_temp.check(t like 'ERR 42501 new row violates row-level security policy%', 'A10 an Admin adds none: ' || t);
  t := pg_temp.n('stf', format('insert into storage.objects(bucket_id, name) values (%L, %L)', 'store-assets', pg_temp.fx('sa') || '/m532-stf-' || s || '.png'));
  perform pg_temp.check(t like 'ERR 42501 new row violates row-level security policy%', 'A11 Staff of store A add none: ' || t);
  t := pg_temp.n('inv', format('insert into storage.objects(bucket_id, name) values (%L, %L)', 'store-assets', pg_temp.fx('sa') || '/m532-inv-' || s || '.png'));
  perform pg_temp.check(t like 'ERR 42501 new row violates row-level security policy%', 'A12 an Inventory Manager adds none: ' || t);
  t := pg_temp.as_('stf', format('select count(*)::text from storage.objects where bucket_id = %L and name like %L', 'store-assets', '%/m532-qr-paynow.png'));
  perform pg_temp.check(t = 'ok:2', 'A13 the images are still read (the till): ' || t);
end $A$;

-- ═════ D set_store_policy_text records its change ═════
do $D$
declare t text;
begin
  perform pg_temp.mark();
  t := pg_temp.as_('pg:own', format('select public.set_store_policy_text(%L, %L)::text', pg_temp.fx('sa'), 'M532 policy'));
  perform pg_temp.check(t like 'ok:%' and pg_temp.saw() = 'stores/store_updated/sa/sa/stores/own'
    and pg_temp.od() = '{"policy_text": null}' and pg_temp.nd() = '{"policy_text": "M532 policy"}' and pg_temp.role_of() = 'owner',
    'D1 set_store_policy_text (with an Owner''s claims) records the policy text before and after: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.as_('pg:own', format('select public.set_store_policy_text(%L, %L)::text', pg_temp.fx('sa'), '  M532 policy  '));
  perform pg_temp.check(t like 'ok:%' and pg_temp.saw() = '', 'D2 the same text again: no entry: ' || t || ' / ' || pg_temp.saw());
  t := pg_temp.as_('own', format('select public.set_store_policy_text(%L, %L)::text', pg_temp.fx('sa'), 'x'));
  perform pg_temp.check(t like 'ERR 42501 permission denied for function set_store_policy_text%', 'D3 a signed-in login still cannot call it: ' || t);
end $D$;

-- ═════ W A payment method's wallet settings are locked ═════
create function pg_temp.locked(t text) returns boolean language sql as
$$ select t = 'ERR 42501 A payment method''s wallet settings cannot be changed here.' $$;
do $W$
declare t text; v uuid; s text := pg_temp.sfx();
begin
  perform pg_temp.mark();
  t := pg_temp.as_('own', format('insert into public.payment_methods(name, is_wallet_credit, wallet_category) values (%L, true, %L) returning id::text', 'M532 Wallet ' || s, 'paid'));
  perform pg_temp.check(pg_temp.locked(t) and pg_temp.saw() = '', 'W1 an Owner cannot add a wallet-credit payment method: ' || t);
  t := pg_temp.as_('own', format('insert into public.payment_methods(name, is_system) values (%L, true) returning id::text', 'M532 System ' || s));
  perform pg_temp.check(pg_temp.locked(t), 'W2 nor a "system" one: ' || t);
  t := pg_temp.as_('own', format('insert into public.payment_methods(name, is_wallet_credit, wallet_category, wallet_source, is_system) values (%L, false, null, null, false) returning id::text', 'M532 Plain ' || s));
  if t like 'ok:%' then v := pg_temp.put('pmw', substr(t, 4)::uuid); end if;
  perform pg_temp.check(t like 'ok:%', 'W3 the defaults sent as they are: added: ' || t);
  perform pg_temp.mark();
  t := pg_temp.n('own', format('update public.payment_methods set is_wallet_credit = true, wallet_category = %L where id = %L', 'paid', v));
  perform pg_temp.check(pg_temp.locked(t) and pg_temp.saw() = '' and (select not is_wallet_credit from public.payment_methods where id = v),
    'W4 an Owner cannot flip "wallet credit": ' || t);
  t := pg_temp.n('mgr', format('update public.payment_methods set wallet_category = %L where id = %L', 'bonus', v));
  perform pg_temp.check(pg_temp.locked(t), 'W5 a Manager cannot set a wallet category: ' || t);
  t := pg_temp.n('own', format('update public.payment_methods set is_system = true where id = %L', v));
  perform pg_temp.check(pg_temp.locked(t), 'W6 nor make it a system method: ' || t);
  t := pg_temp.n('svc', format('update public.payment_methods set is_wallet_credit = true, wallet_category = %L where id = %L', 'paid', v));
  perform pg_temp.check(pg_temp.locked(t), 'W7 the secret key cannot either: ' || t);
  t := pg_temp.as_('svc', format('insert into public.payment_methods(name, is_wallet_credit, wallet_category) values (%L, true, %L) returning id::text', 'M532 Wallet SR ' || s, 'paid'));
  perform pg_temp.check(pg_temp.locked(t), 'W8 nor add a wallet one: ' || t);
  perform pg_temp.mark();
  t := pg_temp.n('own', format('update public.payment_methods set name = %L, is_wallet_credit = is_wallet_credit, wallet_category = wallet_category, wallet_source = wallet_source, is_system = is_system where id = %L', 'M532 Plain Renamed ' || s, v));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'payment_methods/payment_method_updated/pmw/-/payment_methods/own',
    'W9 a rename that sends the wallet settings unchanged is saved and recorded: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('pg', format('update public.payment_methods set is_wallet_credit = true, wallet_category = %L where id = %L', 'paid', v));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = '', 'W10 a migration (the database owner) still sets them, unrecorded: ' || t);
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('update public.payment_methods set is_active = false where id = %L', v));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'payment_methods/payment_method_updated/pmw/-/payment_methods/mgr',
    'W11 a wallet method is still switched off by a Manager (its settings left as they are), recorded: ' || t || ' / ' || pg_temp.saw());
end $W$;

-- ═════ M8 A staff profile ═════
do $M8$
declare t text; v uuid;
begin
  perform pg_temp.mark();
  -- The Users & Roles page's save.
  t := pg_temp.n('own', format('update public.profiles set full_name = full_name, role = %L, work_phone = work_phone, personal_phone = personal_phone, personal_email = personal_email, updated_at = now() + interval ''1 second'' where id = %L',
    'inventory_manager', pg_temp.fx('stf2')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'profiles/staff_role_changed/stf2/-/users/own'
    and pg_temp.od() = '{"role": "staff"}' and pg_temp.nd() = '{"role": "inventory_manager"}' and pg_temp.role_of() = 'owner',
    'M8a an Owner makes a Staff login an Inventory Manager: one entry, the old and the new role, the Owner: ' || t || ' / ' || pg_temp.saw() || ' ' || coalesce(pg_temp.nd()::text, ''));
  perform pg_temp.mark();
  t := pg_temp.n('mgr', format('update public.profiles set role = %L where id = %L', 'owner', pg_temp.fx('stf2')));
  perform pg_temp.check(t like 'ERR 42501 %' and pg_temp.saw() = '' and (select role::text from public.profiles where id = pg_temp.fx('stf2')) = 'inventory_manager',
    'M8b a Manager''s refused change (making someone an Owner): no entry: ' || t);
  t := pg_temp.n('mgr', format('update public.profiles set work_phone = %L where id = %L', '+61491570599', pg_temp.fx('own')));
  perform pg_temp.check(t = 'ok:0' and pg_temp.saw() = '', 'M8c a Manager''s edit of an Owner''s row changes nothing: no entry: ' || t);
  perform pg_temp.mark();
  t := pg_temp.n('stf', format('update public.profiles set work_phone = %L, updated_at = now() + interval ''2 seconds'' where id = %L', '+61491570532', pg_temp.fx('stf')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'profiles/staff_profile_updated/stf/-/users/stf'
    and pg_temp.od() = '{"work_phone": null}' and pg_temp.nd() = '{"work_phone": "+61491570532"}',
    'M8d a login edits its own phone: one entry, by that login: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('stf', format('update public.profiles set work_phone = work_phone, updated_at = now() + interval ''3 seconds'' where id = %L', pg_temp.fx('stf')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = '', 'M8e a save with nothing changed but updated_at: no entry: ' || t);
  -- Switched off and on: 412 records it (with the actor); one entry each.
  perform pg_temp.mark();
  t := pg_temp.n('own', format('update public.profiles set is_active = false where id = %L', pg_temp.fx('stf3')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'profiles/staff_login_blocked/stf3/-/users/own',
    'M8f a login switched off: only 412''s staff_login_blocked, with the Owner: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('own', format('update public.profiles set is_active = true where id = %L', pg_temp.fx('stf3')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'profiles/staff_login_unblocked/stf3/-/users/own',
    'M8g switched on again: only 412''s staff_login_unblocked: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('own', format('update public.profiles set is_active = true where id = %L', pg_temp.fx('stf4')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'profiles/staff_profile_updated/stf4/-/users/own'
    and pg_temp.od() = '{"is_active": false}' and pg_temp.nd() = '{"is_active": true}',
    'M8h a login switched on that 412 never blocked (412 records nothing): recorded here: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('own', format('update public.profiles set is_active = false, full_name = %L where id = %L', 'M532 stf4 Renamed', pg_temp.fx('stf4')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.acts() = 'profiles/staff_login_blocked ; profiles/staff_profile_updated',
    'M8i switched off and renamed in one save: the name change here, the switch by 412: ' || t || ' / ' || pg_temp.acts());
  perform pg_temp.mark();
  t := pg_temp.n('svc', format('update public.profiles set personal_phone = %L where id = %L', '+61491570533', pg_temp.fx('stf2')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'profiles/staff_profile_updated/stf2/-/users/-' and pg_temp.role_of() = 'service_role',
    'M8j the secret key''s change: recorded, no login, actor_role service_role: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('pg', format('update public.profiles set personal_phone = %L where id = %L', '+61491570534', pg_temp.fx('stf2')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = '', 'M8k the database owner''s change: none: ' || t);
  -- Made and removed outright with the secret key (no rule lets a login).
  insert into auth.users(id, email, email_confirmed_at) values (gen_random_uuid(), 'm532-sk-' || pg_temp.sfx() || '@example.invalid', now())
    returning id into v;
  perform pg_temp.put('sk', v);
  perform pg_temp.mark();
  t := pg_temp.n('svc', format('insert into public.profiles(id, full_name, email, role, is_active) values (%L, %L, %L, %L, true)',
    v, 'M532 Made By Key', 'm532-sk-' || pg_temp.sfx() || '@example.invalid', 'staff'));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'profiles/staff_profile_created/sk/-/users/-' and pg_temp.role_of() = 'service_role'
    and pg_temp.nd() ->> 'id' = v::text and pg_temp.nd() ->> 'role' = 'staff' and pg_temp.od() is null,
    'M8l a profile made with the secret key: one staff_profile_created, the new row, actor_role service_role, no login: ' || t || ' / ' || pg_temp.saw());
  perform pg_temp.mark();
  t := pg_temp.n('svc', format('delete from public.profiles where id = %L', v));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'profiles/staff_profile_removed/sk/-/users/-' and pg_temp.role_of() = 'service_role'
    and pg_temp.od() ->> 'id' = v::text and pg_temp.od() ->> 'full_name' = 'M532 Made By Key' and pg_temp.nd() is null,
    'M8m removed with the secret key: staff_profile_removed with the old row: ' || t || ' / ' || pg_temp.saw());
  t := pg_temp.n('own', format('delete from public.profiles where id = %L', pg_temp.fx('stf4')));
  perform pg_temp.check(t = 'ok:0', 'M8m2 a login removes no profile (no rule): ' || t);
  -- Switched off by the secret key alone: 412's entry names nobody, so 532's is written too.
  perform pg_temp.mark();
  t := pg_temp.n('svc', format('update public.profiles set is_active = false where id = %L', pg_temp.fx('stf2')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.acts() = 'profiles/staff_login_blocked ; profiles/staff_profile_updated'
    and (select a.actor_role from pg_temp.fresh() a where a.action = 'staff_profile_updated') = 'service_role'
    and (select a.old_data::text || ' -> ' || a.new_data::text from pg_temp.fresh() a where a.action = 'staff_profile_updated') = '{"is_active": true} -> {"is_active": false}',
    'M8n a login switched off by the secret key alone: 532''s entry (service_role) beside 412''s: ' || t || ' / ' || pg_temp.acts());
  -- Switched on by an Owner from the Users & Roles page (its whole save): one entry, 412's.
  perform pg_temp.mark();
  t := pg_temp.n('own', format('update public.profiles set full_name = full_name, role = role, is_active = true, work_phone = work_phone, personal_phone = personal_phone, personal_email = personal_email, updated_at = now() + interval ''4 seconds'' where id = %L and is_active = false',
    pg_temp.fx('stf2')));
  perform pg_temp.check(t = 'ok:1' and pg_temp.saw() = 'profiles/staff_login_unblocked/stf2/-/users/own',
    'M8o an Owner''s switch alone on the page still gives exactly one entry (412''s, with the Owner): ' || t || ' / ' || pg_temp.saw());
end $M8$;

-- ═════ G 532's fixed parts ═════
\if :is_control
\echo NOTE  G, U and M are skipped (control)
\else
do $G$
declare r record; i int := 0; d text;
begin
  perform pg_temp.check(md5(pg_get_functiondef('public.trg_audit_direct_change()'::regprocedure)) = 'b2ac8670825d1daf73a27c74e64bd66a'
    and md5(pg_get_functiondef('public.trg_payment_method_wallet_locked()'::regprocedure)) = '3b6d9b8590d7bdec9df746cff62024f5',
    'G1 trg_audit_direct_change() and trg_payment_method_wallet_locked() are 532''s (md5 b2ac8670..., 3b6d9b85...)');
  perform pg_temp.check((select count(*) from pg_proc p where p.oid in ('public.trg_audit_direct_change()'::regprocedure, 'public.trg_payment_method_wallet_locked()'::regprocedure)
                           and (select string_agg(x::text, ',' order by x::text) from unnest(p.proacl) x) = 'postgres=X/postgres,service_role=X/postgres'
                           and not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')) = 2,
    'G2 their rights: the owner and the service role only');
  for r in select * from unnest(array['stores', 'warehouses', 'payment_methods', 'promotions', 'promotion_choice_groups', 'promotion_choice_options',
                               'promotion_items', 'special_products', 'survey_links', 'brands', 'categories', 'suppliers', 'profiles']) tb loop
    select pg_get_triggerdef(t.oid) into d from pg_trigger t where t.tgrelid = ('public.' || r.tb)::regclass and t.tgname = 'audit_direct_change';
    if d = format('CREATE TRIGGER audit_direct_change AFTER %s ON public.%s FOR EACH ROW WHEN ((CURRENT_USER = ANY (ARRAY[''anon''::name, ''authenticated''::name, ''service_role''::name]))) EXECUTE FUNCTION trg_audit_direct_change()',
                  'INSERT OR DELETE OR UPDATE', r.tb) then
      i := i + 1; end if;
  end loop;
  perform pg_temp.check(i = 13 and (select count(*) from pg_trigger where tgfoid = 'public.trg_audit_direct_change()'::regprocedure) = 13,
    'G3 the thirteen triggers, as tested, and no other: ' || i);
  perform pg_temp.check((select string_agg(pg_get_triggerdef(t.oid), ';') from pg_trigger t where t.tgfoid = 'public.trg_payment_method_wallet_locked()'::regprocedure)
    = 'CREATE TRIGGER payment_method_wallet_locked BEFORE INSERT OR UPDATE ON public.payment_methods FOR EACH ROW WHEN ((CURRENT_USER = ANY (ARRAY[''anon''::name, ''authenticated''::name, ''service_role''::name]))) EXECUTE FUNCTION trg_payment_method_wallet_locked()',
    'G3b the wallet lock''s trigger, as tested');
  perform pg_temp.check(not exists (select 1 from pg_trigger t where t.tgname = 'audit_direct_change'
                                     and t.tgrelid in ('public.vouchers'::regclass, 'public.voucher_store_prices'::regclass)),
    'G4 vouchers and their prices stay with 423''s trigger');
  perform pg_temp.check((select count(*) from pg_temp.pol_set() p
                          where (p.tbl, p.name) in (('health_surveys', 'update surveys'), ('health_symptom_options', 'insert symptom options'),
                            ('health_symptom_options', 'update symptom options'), ('health_symptom_options', 'delete symptom options'),
                            ('product_categories', 'product_categories write'), ('product_suppliers', 'product_suppliers write'),
                            ('products', 'insert products'), ('products', 'update products'),
                            ('promotion_items', 'insert promotion items'), ('promotion_items', 'update promotion items'),
                            ('special_products', 'insert special products'), ('special_products', 'delete special products'),
                            ('store_product_prices', 'insert store prices'), ('store_product_prices', 'update store prices'), ('store_product_prices', 'delete store prices'),
                            ('promotion_store_prices', 'insert promotion prices'), ('promotion_store_prices', 'update promotion prices'), ('promotion_store_prices', 'delete promotion prices'),
                            ('voucher_store_prices', 'insert voucher prices'), ('voucher_store_prices', 'update voucher prices'), ('voucher_store_prices', 'delete voucher prices'),
                            ('voucher_store_stock', 'insert voucher stock'), ('voucher_store_stock', 'update voucher stock'), ('voucher_store_stock', 'delete voucher stock'),
                            ('brands', 'brands delete'), ('categories', 'categories delete'), ('suppliers', 'suppliers delete'),
                            ('payment_methods', 'delete payment methods'), ('promotions', 'delete promotions'), ('survey_links', 'delete survey links'),
                            ('vouchers', 'delete vouchers'), ('promotion_choice_groups', 'update choice groups'), ('promotion_choice_options', 'update choice options'),
                            ('storage.objects', 'store-assets update'), ('storage.objects', 'store-assets delete'))) = 0,
    'G5 the 33 write rules and the store-assets update and delete rules are gone');
  perform pg_temp.check((select count(*) from pg_temp.pol_set() p
                          where (p.tbl, p.name, p.cmd) in (('product_categories', 'product_categories read', 'r'), ('product_suppliers', 'product_suppliers read', 'r'),
                                                           ('promotion_items', 'delete promotion items', 'd'), ('special_products', 'update special products', 'w'))) = 4,
    'G6 the rules the pages use stay: the product links'' read, promotion items'' delete, special products'' update');
  perform pg_temp.check((select count(*) from pg_proc p where p.oid in (to_regprocedure('public.current_user_role()'), to_regprocedure('public.audit_module(text,text)'),
                           to_regprocedure('public.trg_audit_logs_fill_module()'), to_regprocedure('public.trg_audit_voucher_change()'),
                           to_regprocedure('public.is_owner_or_manager()'), to_regprocedure('public.current_user_store_ids()'),
                           to_regprocedure('public.staff_login_sync(uuid)'), to_regprocedure('public.trg_staff_login_follows_profile()'))
                           and md5(pg_get_functiondef(p.oid)) in ('519b0a33a3548f970c5d585b6e76a389', 'daf0c43e9e9578e78048b2f6d7cba57e',
                                                                  '417a84925a3e465bcc9f11f7c13bb673', '59793e632d567d28a5917066a187411d',
                                                                  'a98e50f1b6d3fa1e6c62cf52a8073cc8', '54191b973c31654b903d48bea01ce533',
                                                                  '9259111deccca8c66e95469acfdd250f', 'a3a60fef98d7755b7104a5d96c4e38f8')) = 8
    and has_function_privilege('authenticated', 'public.current_user_role()', 'execute')
    and has_function_privilege('authenticated', 'public.is_owner_or_manager()', 'execute')
    and has_function_privilege('authenticated', 'public.current_user_store_ids()', 'execute'),
    'G7 the relied-on functions are as tested, and the three the store rules call are open to signed-in logins');
  perform pg_temp.check(md5(pg_get_functiondef('public.soft_delete_store(uuid)'::regprocedure)) = '3bf8f7b89f34cffae2d46c97a8462c07'
    and md5(pg_get_functiondef('public.restore_store(uuid)'::regprocedure)) = '54c3b5e1275429b73b6e6506a2b31ddd'
    and md5(pg_get_functiondef('public.set_store_policy_text(uuid,text)'::regprocedure)) = '807d49611ca6fb2896cde9ee9413def9',
    'G7b soft_delete_store, restore_store and set_store_policy_text are 532''s (md5 3bf8f7b8..., 54c3b5e1..., 807d4961...)');
  perform pg_temp.check((select string_agg(p.cmd || ' ' || p.name || ' ' || p.roles || ' ' || coalesce(p.qual, '-') || ' / ' || coalesce(p.chk, '-'), E'\n' order by p.name)
                           from pg_temp.pol_set() p where p.tbl = 'storage.objects' and p.name like 'store-assets%')
    = 'r store-assets read {-} (bucket_id = ''store-assets''::text) / -' || E'\n'
      || 'a store-assets write {authenticated} - / ((bucket_id = ''store-assets''::text) AND ( SELECT is_owner_or_manager() AS is_owner_or_manager) AND (survey_attachment_store(name) = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])))'
    and has_function_privilege('authenticated', 'public.survey_attachment_store(text)', 'execute'),
    'G7d the store images: read as before; added by an Owner, or a Manager into their own stores'' folders; no update or delete rule');
  perform pg_temp.check((select string_agg(p.cmd || ' ' || p.name || ' ' || coalesce(p.qual, '-') || ' / ' || coalesce(p.chk, '-'), E'\n' order by p.name)
                           from pg_temp.pol_set() p where p.tbl = 'stores' and p.cmd <> 'r')
    = 'a insert stores - / (( SELECT current_user_role() AS current_user_role) = ''owner''::user_role)' || E'\n'
      || 'w update stores ((( SELECT current_user_role() AS current_user_role) = ''owner''::user_role) OR (( SELECT is_owner_or_manager() AS is_owner_or_manager) AND (id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[])))) / ((( SELECT current_user_role() AS current_user_role) = ''owner''::user_role) OR (( SELECT is_owner_or_manager() AS is_owner_or_manager) AND (id = ANY (( SELECT current_user_store_ids() AS current_user_store_ids)::uuid[]))))',
    'G7c the store rules: an Owner adds; an Owner, or a Manager at their own stores, changes');
end $G$;
\if :by_us
select pg_temp.check(
  (select string_agg(fn, ',' order by fn) from fn1 a full join fn0 b using (fn) where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl)
    = 'restore_store(uuid),set_store_policy_text(uuid,text),soft_delete_store(uuid),trg_audit_direct_change(),trg_payment_method_wallet_locked()'
  and not exists (select 1 from fn0 where fn in ('trg_audit_direct_change()', 'trg_payment_method_wallet_locked()')),
  'G8 installed here: the two new functions and the three store functions changed, every other function and its rights unchanged');
select pg_temp.check((select count(*) from pol0) - (select count(*) from pol1) = 35
  and (select string_agg(tbl || '.' || name, ',' order by name) from (select * from pol1 except select * from pol0) x)
      = 'stores.insert stores,storage.objects.store-assets write,stores.update stores',
  'G9 installed here: 35 rules fewer (' || (select count(*) from pol0) || ' -> ' || (select count(*) from pol1) || ', public and storage.objects), only the two store rules and store-assets write changed');
\endif

-- ═════ U The undo, and M 532 a second time ═════
\if :by_us
-- U1 refused while another trigger uses the function.
savepoint u1;
create trigger m532_other after update on public.health_symptom_options for each row execute function public.trg_audit_direct_change();
\set ON_ERROR_STOP off
\ir ../undo-532.sql
\set ON_ERROR_STOP on
rollback to savepoint u1;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'undo 532: 532''s functions are also used by%', 'U1 the undo refuses while another trigger uses the function: ' || :'LAST_ERROR_MESSAGE');
-- U2 the undo puts everything back.
\ir ../undo-532.sql
select pg_temp.check(not exists (select * from pol0 except select * from pg_temp.pol_set()) and not exists (select * from pg_temp.pol_set() except select * from pol0),
  'U2 after the undo the rules are exactly those of before 532');
select pg_temp.check(not exists (select 1 from (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                                  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) a
                                  full join fn0 b using (fn) where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl)
  and not exists (select 1 from pg_trigger where tgname in ('audit_direct_change', 'payment_method_wallet_locked')),
  'U3 after the undo every function and its rights are those of before 532, and no trigger is left');
-- U4 a second undo refuses.
savepoint u4;
\set ON_ERROR_STOP off
\ir ../undo-532.sql
\set ON_ERROR_STOP on
rollback to savepoint u4;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'undo 532: public.trg_audit_direct_change() is not there%', 'U4 the undo a second time refuses: ' || :'LAST_ERROR_MESSAGE');
-- U5 532 again makes exactly what it made.
\ir ../../../supabase/532_changes_made_straight_on_the_tables_are_recorded.sql
select pg_temp.check(not exists (select * from pol1 except select * from pg_temp.pol_set()) and not exists (select * from pg_temp.pol_set() except select * from pol1)
  and not exists (select 1 from (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5, p.proacl::text as acl
                                   from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')) a
                   full join fn1 b using (fn) where a.md5 is distinct from b.md5 or a.acl is distinct from b.acl)
  and (select count(*) from pg_trigger where tgname = 'audit_direct_change') = 13,
  'U5 532 after the undo makes exactly what it made the first time');
-- M 532 a second time refuses and changes nothing.
savepoint m1;
\set ON_ERROR_STOP off
\ir ../../../supabase/532_changes_made_straight_on_the_tables_are_recorded.sql
\set ON_ERROR_STOP on
rollback to savepoint m1;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '532 is already in on this database%', 'M1 532 a second time refuses: ' || :'LAST_ERROR_MESSAGE');
select pg_temp.check(not exists (select * from pol1 except select * from pg_temp.pol_set()) and (select count(*) from pg_trigger where tgname = 'audit_direct_change') = 13,
  'M2 and changes nothing');
\else
\echo NOTE  U and M are skipped (532 was not installed by this file)
\endif
\endif

select count(*) as n_failed from failed \gset
\if :is_control
\echo control: :n_failed checks failed without 532 (each is one 532 makes pass)
rollback;
\else
do $$ begin
  if (select count(*) from failed) > 0 then
    raise exception '% check(s) failed: %', (select count(*) from failed), (select string_agg(msg, E'\n' order by n) from failed);
  end if;
  raise notice 'ALL PASSED';
end $$;
rollback;
\endif
