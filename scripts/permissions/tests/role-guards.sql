-- A caller with no staff role is refused (340).
--
-- An affiliate signs in like anyone else: an ordinary authenticated session,
-- but with no profiles row. current_user_role() therefore returns NULL for
-- them, and a guard written as "if role not in ('owner','manager')" evaluated
-- to NULL and let them straight through. This drives the eight real functions
-- as a real affiliate and asserts each one refuses.
--
-- The assertion is on the REASON, not merely on failure: an affiliate must be
-- stopped by the role guard itself, and an Owner must never be. That is what
-- separates a working guard from a call that happened to fail on its
-- arguments, which is how this test first passed for the wrong reason.
--
-- Disposable local database only; the fixture rolls back.
\set ON_ERROR_STOP on
begin;
do $$
declare
  own uuid := gen_random_uuid();
  mgr uuid := gen_random_uuid();
  aff_user uuid := gen_random_uuid();
  st uuid; cust uuid; aff uuid; batch uuid; opt uuid; inv uuid; prod uuid; mapping uuid;
  stmts text[]; s text; n int := 0; leaked text := ''; blocked text := '';
begin
  insert into auth.users(id, email) values
    (own, 'rg-owner@tests.invalid'), (mgr, 'rg-manager@tests.invalid'), (aff_user, 'rg-affiliate@tests.invalid');
  insert into profiles(id, full_name, email, role) values
    (own, 'RG Owner', 'rg-owner@tests.invalid', 'owner'),
    (mgr, 'RG Manager', 'rg-manager@tests.invalid', 'manager');
  perform set_config('request.jwt.claim.sub', own::text, true);

  insert into stores(name, code, country_code) values ('RG Store', 'RGS', 'SG') returning id into st;
  insert into customers(full_name, phone) values ('RG Customer', '+6591118961') returning id into cust;
  insert into customer_affiliates(customer_id, status, store_id, activated_at)
    values (cust, 'active', st, now()) returning id into aff;
  -- The affiliate account: an auth user with NO profiles row, which is exactly
  -- what makes current_user_role() return NULL.
  insert into affiliate_accounts(auth_user_id, customer_id, affiliate_id, status)
    values (aff_user, cust, aff, 'claimed');
  insert into products(name, sku) values ('RG Item', 'RG-1') returning id into prod;
  insert into store_inventory(store_id, product_id, current_qty) values (st, prod, 10);
  perform set_product_prices(st, prod, 50, 50, 'available');
  inv := create_invoice(st, cust, null, jsonb_build_array(jsonb_build_object('kind','product','product_id',prod,'quantity',1)));
  insert into tiktok_import_batches(store_id, file_kind, file_name, uploaded_by)
    values (st, 'order', 'rg.csv', own) returning id into batch;
  opt := upsert_customer_source_option('RG Source', 1, false, true, null);
  mapping := upsert_tiktok_status_mapping('RG Fixture Status', 'none', false, true);

  -- Every function 340 rewrote, called the way the application calls it.
  stmts := array[
    format('select public.upsert_customer_source_option(%L, 9, false, true, null)', 'RG Other Source'),
    format('select public.set_customer_source_option_active(%L::uuid, false)', opt),
    format('select public.reorder_customer_source_options(jsonb_build_array(%L))', opt::text),
    format('select public.upsert_tiktok_status_mapping(%L, %L, true, true)', 'RG Other Status', 'none'),
    format('select public.set_tiktok_status_mapping_active(%L::uuid, false)', mapping),
    format('select public.correct_invoice_created_by(%L::uuid, %L::uuid, %L)', inv, mgr, 'RG note'),
    format('select public.create_tiktok_correction_batch(%L::uuid, %L::jsonb, %L)', batch, '[]', 'RG reason'),
    format('select public.delete_tiktok_batch(%L::uuid)', batch)
  ];

  -- As the affiliate: each call must be stopped by the role guard, whose
  -- messages all begin "Only ...". Any other outcome — success, or a failure
  -- further inside the function — means the guard did not hold.
  perform set_config('request.jwt.claim.sub', aff_user::text, true);
  if public.current_user_role() is not null then
    raise exception 'FIXTURE: the affiliate should have no staff role, got %', public.current_user_role(); end if;

  foreach s in array stmts loop
    begin
      execute s;
      leaked := leaked || E'\n  allowed through: ' || s;
    exception when others then
      if sqlerrm like 'Only %' then n := n + 1;
      else leaked := leaked || E'\n  got past the role guard and failed later (' || sqlerrm || '): ' || s; end if;
    end;
  end loop;
  if leaked <> '' then
    raise exception 'FAIL: a signed-in caller with no staff role was not refused:%', leaked; end if;

  -- And the Owner still gets through: the fix refuses NULL, not everyone. Some
  -- of these legitimately fail on their arguments for an Owner (an empty
  -- correction batch, say); what must never happen is a role refusal.
  perform set_config('request.jwt.claim.sub', own::text, true);
  foreach s in array stmts loop
    begin
      execute s;
    exception when others then
      if sqlerrm like 'Only %' then blocked := blocked || E'\n  ' || sqlerrm || ': ' || s; end if;
    end;
  end loop;
  if blocked <> '' then
    raise exception 'FAIL: an Owner was refused by a role guard:%', blocked; end if;

  raise notice 'PASS: % guarded functions refuse a signed-in caller with no staff role (an affiliate), and none of them refuses an Owner', n;
end $$;
rollback;
