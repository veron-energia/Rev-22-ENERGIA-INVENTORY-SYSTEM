-- An affiliate login is not a staff login (342, 343).
--
-- Most read policies here were written "to authenticated using (true)" when the
-- only way to hold the authenticated role was to be a member of staff. Affiliate
-- self-service logins (155) are ordinary authenticated sessions with no profiles
-- row, so those policies had quietly opened the customer, medical and financial
-- record to every affiliate — and the INSERT policy on profiles let one make
-- itself an Owner.
--
-- This drives the real policies as a real affiliate and as a real Owner. It
-- grants what Supabase grants inside the transaction, because the disposable
-- cluster does not replicate the platform's default privileges and the point of
-- the test is the POLICY, not the grant.
--
-- Disposable database only; everything is rolled back.
\set ON_ERROR_STOP on
begin;

-- What Supabase gives these roles on a public table, applied here so the test
-- reaches the policies instead of stopping at a missing grant.
grant usage on schema public to authenticated, anon;
grant select, insert, update, delete on all tables in schema public to authenticated;

do $$
declare
  own uuid := gen_random_uuid();
  aff_user uuid := gen_random_uuid();
  st uuid; cust uuid; aff uuid; other uuid;
  leaked text := ''; blocked text := '';
  t text; n int; v_msg text;
  -- Tables an affiliate must not be able to read at all.
  closed constant text[] := array[
    'customers','profiles','health_surveys','consultant_notes','customer_remarks',
    'customer_phone_history','invoice_items','invoice_refunds','customer_reward_vouchers',
    'purchased_therapy_entitlements','credit_package_sales','user_store_assignments',
    'commission_corrections','credit_package_progress_lots'];
begin
  insert into auth.users(id,email) values (own,'rls-owner@tests.invalid'), (aff_user,'rls-aff@tests.invalid');
  insert into profiles(id,full_name,email,role) values (own,'RLS Owner','rls-owner@tests.invalid','owner');
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name,code,country_code) values ('RLS Store','RLSS','SG') returning id into st;
  insert into customers(full_name,phone) values ('RLS Customer','+6591117411') returning id into cust;
  insert into customers(full_name,phone) values ('RLS Other','+6591117412') returning id into other;
  insert into customer_affiliates(customer_id,status,store_id,activated_at)
    values (cust,'active',st,now()) returning id into aff;
  -- An affiliate account: an auth user with NO profiles row.
  insert into affiliate_accounts(auth_user_id,customer_id,affiliate_id,status)
    values (aff_user,cust,aff,'claimed');
  insert into health_surveys(survey_no, customer_id, full_name, phone)
    values ('RLS-SURVEY-1', cust, 'RLS Customer', '+6591117411');

  -- ---- as the affiliate -------------------------------------------------
  perform set_config('request.jwt.claim.sub', aff_user::text, true);
  if public.current_user_role() is not null then
    raise exception 'FIXTURE: the affiliate should have no staff role'; end if;
  execute 'set local role authenticated';

  foreach t in array closed loop
    execute format('select count(*) from public.%I', t) into n;
    if n > 0 then leaked := leaked || t || '(' || n || ' rows) '; end if;
  end loop;

  -- The escalation: create my own profile as an Owner.
  begin
    execute format('insert into public.profiles(id, full_name, email, role) values (%L, %L, %L, %L)',
                   aff_user, 'Affiliate', 'rls-aff@tests.invalid', 'owner');
    leaked := leaked || 'CREATED ITS OWN OWNER PROFILE ';
  exception when others then null; end;

  -- Rewriting a customer, including the referral chain commission reads.
  begin
    execute format('update public.customers set full_name = %L, referred_by = %L where id = %L',
                   'Renamed by an affiliate', other, cust);
    get diagnostics n = row_count;
    if n > 0 then leaked := leaked || 'REWROTE A CUSTOMER '; end if;
  exception when others then null; end;

  execute 'reset role';
  if leaked <> '' then
    raise exception 'FAIL: an affiliate session still reached: %', leaked; end if;

  -- ---- as an Owner ------------------------------------------------------
  -- The same policies must not have cost staff anything.
  perform set_config('request.jwt.claim.sub', own::text, true);
  execute 'set local role authenticated';

  foreach t in array closed loop
    -- The two deny-by-default tables are reachable only through their definer
    -- functions, so an Owner sees nothing there either. That is the design.
    if t in ('commission_corrections','credit_package_progress_lots') then continue; end if;
    begin
      execute format('select count(*) from public.%I', t) into n;
    exception when others then
      get stacked diagnostics v_msg = message_text;
      blocked := blocked || t || ' (' || v_msg || ') '; continue;
    end;
    if n = 0 and t in ('customers','profiles','health_surveys') then
      blocked := blocked || t || ' (an Owner sees no rows) '; end if;
  end loop;

  begin
    execute format('update public.customers set full_name = %L where id = %L', 'Renamed by an Owner', cust);
    get diagnostics n = row_count;
    if n <> 1 then blocked := blocked || 'an Owner could not rename a customer '; end if;
  exception when others then
    get stacked diagnostics v_msg = message_text;
    blocked := blocked || 'an Owner could not rename a customer (' || v_msg || ') ';
  end;
  execute 'reset role';

  if blocked <> '' then
    raise exception 'FAIL: the tightened policies cost staff access to: %', blocked; end if;

  raise notice 'PASS: an affiliate session reaches none of the % protected tables, cannot create its own Owner profile and cannot rewrite a customer; an Owner still reads and writes everything it did', array_length(closed,1);
end $$;
rollback;
