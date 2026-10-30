-- Staff see a customer's full Profile and their Downline (453).
--
-- The Owner's answers, 22 Oct 2026 (item 7, the recommendations accepted): Owners, Admins, Managers and
-- Staff, the roles that add and edit customers (418), see the Profile's figures (Paid purchases, Total
-- spend, Customers referred, Referred by), the purchase timeline from every store, the phone history and
-- the Downline (Tier 1 and Tier 2, with its export); Inventory Managers keep the Limited view; commission
-- amounts stay hidden from Staff exactly as now. customer_profile_stats, customer_purchase_timeline and
-- customer_downline_visits change their role check only.
--
--   G  The md5s and the grants: the three at 453's AFTER, the functions they rely on unchanged; each
--      callable by signed-in logins and the service role, not signed out, the grants as on 450.
--   R  As each role, through the API's own role (set local role): the Manager's answers on a fixture
--      (two paid invoices and an unpaid one, at two stores; a referrer, their friend and that friend's
--      friend); the Owner, the Admin and Staff (at one store) get exactly the same; the Inventory Manager
--      is refused with 42501 "Your role cannot do this."; an affiliate portal login, a login with no
--      profile, a deactivated employee, a pending and a cancelled invitee with 42501 "Only active
--      Energia staff can do this."; signed out with 42501 (no grant); the server and the service role
--      pass (406's rule 4; NOT COVERED 1 for the downline).
--   S  Every store (rule 3): Staff at store A see store B's invoices in the timeline (and in Total
--      spend), which the invoices table's own rule does not show them directly.
--   P  Phone history: Staff read the customer's old numbers from the table, as the Profile does (430's
--      rule; no change); an Inventory Manager can too (KNOWN: only the page keeps it from them).
--   N  No new data: each answer has the keys it had (no commission figure); the Commissions page's
--      referrer_downline still refuses Staff.
--   M  453 twice changes nothing; its first run changes only the three functions (none added or
--      dropped); its self-test leaves no row (when this file installs it). A function changed since
--      450 is refused and nothing is changed (every run).
--
-- Disposable local database only (a copy of production as it is: run it on 450's copy, where it
-- installs 453 twice, or with -v skip_install=1 where 453 is already in, and always once 480 is: 453's
-- installer then refuses, as it should, since 480 changed customer_downline_visits); everything is
-- rolled back.
-- Every name and email is invented (@example.com); phones are ACMA's fictional ranges
-- (+61 2 5550 ....), found free at run time. Every check runs, then the file fails if any did.
--   psql -X -v ON_ERROR_STOP=1 [-v skip_install=1] -f scripts/customers/tests/staff-profile-453.sql
\set ON_ERROR_STOP on
begin;
create function pg_temp.row_counts() returns jsonb language plpgsql as
$$declare r record; n bigint; v jsonb := '{}'::jsonb;
begin
  for r in select c.oid::regclass::text as t from pg_class c join pg_namespace s on s.oid = c.relnamespace
            where s.nspname in ('public', 'auth') and c.relkind = 'r' order by 1 loop
    execute format('select count(*) from %s', r.t) into n;
    v := v || jsonb_build_object(r.t, n);
  end loop;
  return v;
end$$;
-- md5 of each public function's definition, read with public alone on the search path.
create function pg_temp.fn_md5s() returns table(fn text, md5 text) language sql set search_path = public as
$$ select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' $$;
\if :{?skip_install}
\else
create temp table b453 as select * from pg_temp.fn_md5s();
create temp table r453 as select pg_temp.row_counts() as before;
\ir ../../../supabase/453_staff_see_customer_profile_and_downline.sql
create temp table m453 as select * from pg_temp.fn_md5s();
alter table r453 add column after1 jsonb;
update r453 set after1 = pg_temp.row_counts();
\ir ../../../supabase/453_staff_see_customer_profile_and_downline.sql
\endif
set local lock_timeout = '10s';
set local statement_timeout = '300s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create temp table tx(k text primary key, v text);
grant all on fx, tx to authenticated, anon, service_role;
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.put(key text, val text) returns void language sql as
$$ insert into tx values (key, val) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.putx(key text, val uuid) returns void language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v $$;
-- Run q as a login (a fixture key), 'anon' (signed out), 'service' (the service role) or 'server' (no
-- request at all), through the API's own database role, as the pages do: 'ok', a tab and the answer, or
-- the SQLSTATE, a tab and the message.
create function pg_temp.try_as(who text, q text) returns text language plpgsql as
$$declare v_out text; v_state text; v_msg text;
begin
  begin
    if who = 'server' then
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', '', true);
    elsif who = 'anon' then
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', '', true);
      execute 'set local role anon';
    elsif who = 'service' then
      perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', '', true);
      execute 'set local role service_role';
    else
      perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(who), 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', '', true);
      execute 'set local role authenticated';
    end if;
    execute q into v_out;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    return 'ok' || chr(9) || coalesce(v_out, '');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    perform set_config('request.jwt.claims', '', true);
    return v_state || chr(9) || v_msg;
  end;
end$$;
create function pg_temp.state(v text) returns text language sql as $$ select split_part(v, chr(9), 1) $$;
create function pg_temp.body(v text) returns text language sql as $$ select substr(v, position(chr(9) in v) + 1) $$;
-- The three calls the Profile and the Downline window make, for one customer.
create function pg_temp.q_stats(key text) returns text language sql as
$$ select format('select public.customer_profile_stats(%L::uuid)::text', pg_temp.fx(key)) $$;
create function pg_temp.q_timeline(key text) returns text language sql as
$$ select format('select public.customer_purchase_timeline(%L::uuid)::text', pg_temp.fx(key)) $$;
create function pg_temp.q_downline(key text) returns text language sql as
$$ select format('select public.customer_downline_visits(%L::uuid)::text', pg_temp.fx(key)) $$;
-- All three as one login: the three answers (or refusals), one per line.
create function pg_temp.all3(who text, key text) returns text language sql as
$$ select pg_temp.try_as(who, pg_temp.q_stats(key)) || chr(10) || pg_temp.try_as(who, pg_temp.q_timeline(key))
          || chr(10) || pg_temp.try_as(who, pg_temp.q_downline(key)) $$;
create function pg_temp.mail(tag text) returns text language sql as
$$ select 'cp453-' || lower(tag) || '-' || pg_temp.tx('sfx') || '@example.com' $$;
create function pg_temp.ph(n int) returns text language sql as
$$ select '+6125550' || lpad((pg_temp.tx('phbase')::int + n)::text, 4, '0') $$;

-- ═════ Fixture (written as the server would: no request) ═════
set local client_min_messages = warning;
do $$
declare k text; v uuid; st_a uuid; st_b uuid; cash uuid; vch uuid; r uuid; t1 uuid; t2 uuid; ca uuid; aff uuid; inv uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  perform pg_temp.put('sfx', lower(substr(md5(gen_random_uuid()::text), 1, 8)));
  -- Ten free fictional phones in a row: +61 2 5550 nnnn.
  perform pg_temp.put('phbase', (select min(g)::text from generate_series(4530, 9980, 10) g
                                  where not exists (select 1 from public.customers c
                                                     where public.normalize_customer_phone(c.phone)
                                                           between '+6125550' || lpad(g::text, 4, '0')
                                                               and '+6125550' || lpad((g + 9)::text, 4, '0'))));
  if pg_temp.tx('phbase') is null then raise exception 'no free fictional phones'; end if;
  foreach k in array array['owner', 'admin', 'manager', 'invman', 'staff', 'inactive', 'pending', 'cancelled',
                           'nostaff', 'affiliate'] loop
    insert into auth.users (id, email) values (gen_random_uuid(), pg_temp.mail(k)) returning id into v;
    perform pg_temp.putx(k, v);
  end loop;
  insert into public.profiles (id, full_name, email, role, is_active, invitation_status)
  select pg_temp.fx(x.k), 'Test ' || x.k, pg_temp.mail(x.k), x.role::public.user_role, x.active, x.inv
    from (values ('owner', 'owner', true, null), ('admin', 'admin', true, null), ('manager', 'manager', true, null),
                 ('invman', 'inventory_manager', true, null), ('staff', 'staff', true, 'accepted'),
                 ('inactive', 'staff', false, null), ('pending', 'staff', false, 'pending'),
                 ('cancelled', 'staff', false, 'cancelled')) x(k, role, active, inv);
  insert into public.stores (name, code, country_code) values ('Test Store A ' || pg_temp.tx('sfx'), 'T453A' || pg_temp.tx('sfx'), 'SG')
    returning id into st_a;
  insert into public.stores (name, code, country_code) values ('Test Store B ' || pg_temp.tx('sfx'), 'T453B' || pg_temp.tx('sfx'), 'SG')
    returning id into st_b;
  perform pg_temp.putx('store_a', st_a); perform pg_temp.putx('store_b', st_b);
  -- Staff (and the Inventory Manager, the Manager) at store A only.
  insert into public.user_store_assignments (user_id, store_id)
  select pg_temp.fx(x.k), st_a from unnest(array['manager', 'invman', 'staff', 'inactive', 'pending', 'cancelled']) x(k);
  insert into public.payment_methods (name, is_active) values ('Test Cash ' || pg_temp.tx('sfx'), true) returning id into cash;
  insert into public.vouchers (name, code, voucher_kind, selling_price, qty_type, is_active)
  values ('Test Voucher ' || pg_temp.tx('sfx'), 'T453-' || pg_temp.tx('sfx'), 'normal', 30, 'unlimited', true) returning id into vch;
  insert into public.voucher_store_prices (voucher_id, store_id, selling_price, available_at_store)
  values (vch, st_a, 30, true), (vch, st_b, 30, true);
  -- The referrer, their friend (Tier 1) and that friend's friend (Tier 2); an affiliate with a portal login.
  insert into public.customers (full_name, phone, email) values ('Test Customer ' || pg_temp.tx('sfx'), pg_temp.ph(0), pg_temp.mail('cust'))
    returning id into r;
  insert into public.customers (full_name, phone, referred_by) values ('Test Friend ' || pg_temp.tx('sfx'), pg_temp.ph(1), r)
    returning id into t1;
  insert into public.customers (full_name, phone, referred_by) values ('Test Friend Two ' || pg_temp.tx('sfx'), pg_temp.ph(2), t1)
    returning id into t2;
  insert into public.customers (full_name, phone) values ('Test Affiliate ' || pg_temp.tx('sfx'), pg_temp.ph(3)) returning id into ca;
  insert into public.customer_affiliates (customer_id, status, store_id, activated_at) values (ca, 'active', st_a, now()) returning id into aff;
  insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status) values (pg_temp.fx('affiliate'), ca, aff, 'claimed');
  perform pg_temp.putx('cust', r); perform pg_temp.putx('t1', t1); perform pg_temp.putx('t2', t2);
  -- An old number of the customer's (the Profile's phone history).
  insert into public.customer_phone_history (customer_id, phone, reason) values (r, pg_temp.ph(9), 'Test old number');
  -- Invoices, as the Owner makes them: S$30 paid at store A, S$60 paid at store B, S$30 unpaid at store B.
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  inv := public.create_invoice(st_a, r, null, jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', vch, 'quantity', 1)));
  perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', cash, 'amount', 30)), gen_random_uuid());
  perform pg_temp.putx('inv_a', inv);
  inv := public.create_invoice(st_b, r, null, jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', vch, 'quantity', 2)));
  perform public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', cash, 'amount', 60)), gen_random_uuid());
  perform pg_temp.putx('inv_b', inv);
  inv := public.create_invoice(st_b, r, null, jsonb_build_array(jsonb_build_object('kind', 'voucher', 'voucher_id', vch, 'quantity', 1)));
  perform pg_temp.putx('inv_b2', inv);
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
set local client_min_messages = notice;

-- ═════ G The md5s and the grants ═════
select pg_temp.check((select array_agg(f.fn || ' ' || f.md5 order by f.fn) from pg_temp.fn_md5s() f
                       where f.fn in ('customer_profile_stats(uuid)', 'customer_purchase_timeline(uuid)', 'customer_downline_visits(uuid)'))
    = array['customer_downline_visits(uuid) '
              -- 480 adds each row's cal.com booking to it (its AFTER), the role check as 453 left it.
              || (select case when f.md5 = 'ea3f28ea932506eda6937fa687298d6d' then f.md5 else '5bee190a80a8e9624e7d15e16eb95ca1' end
                    from pg_temp.fn_md5s() f where f.fn = 'customer_downline_visits(uuid)'),
            'customer_profile_stats(uuid) 93c1a7b762b99c7e28fdad0facc17ac8',
            'customer_purchase_timeline(uuid) 9fdfb23164e62e6e9309e02470a3520e'],
  'G1 the three functions are at 453''s AFTER md5s (customer_downline_visits: or 480''s)');
select pg_temp.check((select array_agg(f.fn || ' ' || f.md5 order by f.fn) from pg_temp.fn_md5s() f
                       where f.fn in ('require_active_staff(text[])', 'customer_centre_visits()', 'is_owner_or_manager()',
                                      'referrer_downline(uuid)', 'customer_overview(uuid)'))
    = array['customer_centre_visits() c07a5a0cbbf52ba45e5dc911b20002da',
            'customer_overview(uuid) ' || (select md5 from pg_temp.fn_md5s() where fn = 'customer_overview(uuid)'),
            'is_owner_or_manager() a98e50f1b6d3fa1e6c62cf52a8073cc8',
            'referrer_downline(uuid) a48f44ea378f05c79bf78dd4c8a71b3c',
            'require_active_staff(text[]) 877b3aa74cea559881979bb161c450e2'],
  'G2 what they rely on (require_active_staff, customer_centre_visits) and is_owner_or_manager and referrer_downline are as on 450');
select pg_temp.check(bool_and((select array_agg(x::text order by x::text) from unnest(p.proacl) x)
                              = array['authenticated=X/postgres', 'postgres=X/postgres', 'service_role=X/postgres'])
    and bool_and(not has_function_privilege('anon', p.oid, 'execute'))
    and bool_and(has_function_privilege('authenticated', p.oid, 'execute'))
    and bool_and(has_function_privilege('service_role', p.oid, 'execute'))
    and count(*) = 3,
  'G3 each of the three keeps 450''s grants: signed-in logins and the service role may call it, signed out may not')
  from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('customer_profile_stats', 'customer_purchase_timeline', 'customer_downline_visits');

-- ═════ R As each role ═════
select pg_temp.put('m_stats', pg_temp.try_as('manager', pg_temp.q_stats('cust')));
select pg_temp.put('m_tl', pg_temp.try_as('manager', pg_temp.q_timeline('cust')));
select pg_temp.put('m_dl', pg_temp.try_as('manager', pg_temp.q_downline('cust')));
select pg_temp.check(pg_temp.state(pg_temp.tx('m_stats')) = 'ok'
    and pg_temp.body(pg_temp.tx('m_stats'))::jsonb = jsonb_build_object('purchases', 2, 'total_spend', 90, 'referred_count', 1, 'referrer_name', null),
  'R1 the Manager''s figures: 2 paid purchases, S$90 spent (both stores), 1 referred, no referrer: ' || pg_temp.tx('m_stats'));
select pg_temp.check(pg_temp.state(pg_temp.tx('m_tl')) = 'ok'
    and jsonb_array_length(pg_temp.body(pg_temp.tx('m_tl'))::jsonb) = 3
    and (select array_agg(e->>'invoice_id' order by e->>'invoice_id') from jsonb_array_elements(pg_temp.body(pg_temp.tx('m_tl'))::jsonb) e)
        = (select array_agg(x::text order by x::text) from unnest(array[pg_temp.fx('inv_a'), pg_temp.fx('inv_b'), pg_temp.fx('inv_b2')]) x),
  'R2 the Manager''s timeline: the three invoices, both stores');
select pg_temp.check(pg_temp.state(pg_temp.tx('m_dl')) = 'ok'
    and (select jsonb_array_length(d->'tier1') = 1 and jsonb_array_length(d->'tier2') = 1
                and d->'tier1'->0->>'customer_id' = pg_temp.fx('t1')::text and d->'tier1'->0->>'phone' = pg_temp.ph(1)
                and d->'tier2'->0->>'customer_id' = pg_temp.fx('t2')::text and d->'tier2'->0->>'parent_id' = pg_temp.fx('t1')::text
           from (select pg_temp.body(pg_temp.tx('m_dl'))::jsonb as d) y),
  'R3 the Manager''s downline: the friend in Tier 1 (with phone), the friend''s friend in Tier 2');
select pg_temp.check(pg_temp.all3(w.k, 'cust') = pg_temp.tx('m_stats') || chr(10) || pg_temp.tx('m_tl') || chr(10) || pg_temp.tx('m_dl'),
  format('R4 %s gets exactly the Manager''s figures, timeline and downline', w.label))
  from (values ('owner', 'the Owner'), ('admin', 'the Admin'), ('staff', 'Staff (at store A only)')) w(k, label);
select pg_temp.check(pg_temp.try_as('staff', pg_temp.q_stats('t1')) like 'ok' || chr(9) || '%"referrer_name": "Test Customer %'
    and pg_temp.try_as('staff', pg_temp.q_stats('t1')) = pg_temp.try_as('manager', pg_temp.q_stats('t1')),
  'R5 Staff see who referred the friend (Referred by), as the Manager does');
select pg_temp.check(pg_temp.all3('invman', 'cust') = repeat('42501' || chr(9) || 'Your role cannot do this.' || chr(10), 2)
                                                       || '42501' || chr(9) || 'Your role cannot do this.',
  'R6 the Inventory Manager is refused all three with 42501 "Your role cannot do this.": ' || pg_temp.all3('invman', 'cust'));
select pg_temp.check(pg_temp.all3(w.k, 'cust') = repeat('42501' || chr(9) || 'Only active Energia staff can do this.' || chr(10), 2)
                                                  || '42501' || chr(9) || 'Only active Energia staff can do this.',
  format('R7 %s is refused all three with 42501 "Only active Energia staff can do this.": %s', w.label, pg_temp.all3(w.k, 'cust')))
  from (values ('affiliate', 'an affiliate portal login'), ('nostaff', 'a login with no profile'),
               ('inactive', 'a deactivated employee'), ('pending', 'a pending invitee'), ('cancelled', 'a cancelled invitee')) w(k, label);
select pg_temp.check(pg_temp.state(pg_temp.try_as('anon', pg_temp.q_stats('cust'))) = '42501'
    and pg_temp.state(pg_temp.try_as('anon', pg_temp.q_timeline('cust'))) = '42501'
    and pg_temp.state(pg_temp.try_as('anon', pg_temp.q_downline('cust'))) = '42501',
  'R8 signed out: refused all three with 42501 (no grant)');
select pg_temp.check(pg_temp.all3(w.k, 'cust') = pg_temp.tx('m_stats') || chr(10) || pg_temp.tx('m_tl') || chr(10) || pg_temp.tx('m_dl'),
  format('R9 %s passes the check (406''s rule 4), the downline too since 453 (NOT COVERED 1)', w.label))
  from (values ('service', 'the service role'), ('server', 'the server with no request')) w(k, label);

-- ═════ S Every store ═════
select pg_temp.check(pg_temp.try_as('staff', format('select count(*)::text from public.invoices where customer_id = %L', pg_temp.fx('cust'))) = 'ok' || chr(9) || '1'
    and pg_temp.try_as('staff', pg_temp.q_timeline('cust')) like '%' || pg_temp.fx('inv_b') || '%'
    and pg_temp.try_as('staff', pg_temp.q_timeline('cust')) like '%' || pg_temp.fx('inv_b2') || '%'
    and pg_temp.try_as('staff', pg_temp.q_stats('cust')) like '%"total_spend": 90%',
  'S1 Staff at store A see store B''s invoices in the timeline and in Total spend (rule 3), though the invoices table shows them store A''s alone');

-- ═════ P Phone history ═════
select pg_temp.check(pg_temp.try_as('staff', format('select string_agg(phone || '' '' || reason, '','') from public.customer_phone_history where customer_id = %L', pg_temp.fx('cust')))
                     = 'ok' || chr(9) || pg_temp.ph(9) || ' Test old number',
  'P1 Staff read the customer''s old number and its reason from the table, as the Profile does (430''s rule; no change)');
select pg_temp.check(pg_temp.try_as('invman', format('select count(*)::text from public.customer_phone_history where customer_id = %L', pg_temp.fx('cust')))
                     = 'ok' || chr(9) || '1',
  'P2 KNOWN: an Inventory Manager can read it from the table too; only the page keeps it from them (NOT COVERED 2)');

-- ═════ N No new data ═════
select pg_temp.check((select array_agg(k order by k) from jsonb_object_keys(pg_temp.body(pg_temp.try_as('staff', pg_temp.q_stats('cust')))::jsonb) k)
                       = array['purchases', 'referred_count', 'referrer_name', 'total_spend']
    and (select bool_and(e ?& array['invoice_id', 'invoice_no', 'date', 'status', 'store', 'total', 'paid', 'is_topup', 'save_earth', 'items']
                         and (select count(*) from jsonb_object_keys(e)) = 10)
           from jsonb_array_elements(pg_temp.body(pg_temp.try_as('staff', pg_temp.q_timeline('cust')))::jsonb) e)
    and (select array_agg(k order by k) from jsonb_object_keys(pg_temp.body(pg_temp.try_as('staff', pg_temp.q_downline('cust')))::jsonb) k)
        = array['customer_id', 'name', 'phone', 'tier1', 'tier2']
    and pg_temp.try_as('staff', pg_temp.q_downline('cust')) !~* 'commission|earn|payout|spend',
  'N1 what Staff get has the keys it had (figures, invoices with their lines, Tier 1/2 names, phones and visits): no commission figure');
select pg_temp.check(pg_temp.try_as('staff', format('select count(*)::text from public.referrer_downline(%L)', pg_temp.fx('cust')))
                     = '42501' || chr(9) || 'Commission access denied'
    and pg_temp.state(pg_temp.try_as('manager', format('select count(*)::text from public.referrer_downline(%L)', pg_temp.fx('cust')))) = 'ok',
  'N2 the Commissions page''s referrer_downline (spend per downline member) still refuses Staff (rule 7)');

-- ═════ M 453 twice; a changed function is refused ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m453 m left join pg_temp.fn_md5s() f on f.fn = m.fn where f.fn is null or f.md5 <> m.md5)
    and (select count(*) from pg_temp.fn_md5s()) = (select count(*) from m453),
  'M1 running 453 a second time changed no function');
select pg_temp.check((select coalesce(array_agg(m.fn order by m.fn), '{}') from m453 m left join b453 b on b.fn = m.fn
                       where b.fn is null or b.md5 <> m.md5)
                     = array['customer_downline_visits(uuid)', 'customer_profile_stats(uuid)', 'customer_purchase_timeline(uuid)']
    and (select count(*) from m453) = (select count(*) from b453),
  'M2 its first run changed the three functions alone (no function added or dropped)');
select pg_temp.check((select before = after1 from r453),
  'M3 453''s self-test left no row (every table of public and auth counts the same before and after it)');
\endif
-- A function changed since (here: a comment added to customer_profile_stats): 453 refuses, changing nothing.
savepoint m4;
do $$ begin
  perform set_config('search_path', 'public', true);
  execute regexp_replace(pg_get_functiondef('public.customer_profile_stats(uuid)'::regprocedure),
                         'AS \$function\$', 'AS $function$ -- changed by the 453 suite');
end $$;
reset search_path;
\echo 'M4: 453 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/453_staff_see_customer_profile_and_downline.sql
\set ON_ERROR_STOP on
\set m4_msg :LAST_ERROR_MESSAGE
rollback to savepoint m4;
select pg_temp.check(:'m4_msg' like '453: %public.customer_profile_stats(uuid)%' and :'m4_msg' like '%Re-read it and re-test before applying.',
  'M4 a changed customer_profile_stats is refused (all undone): ' || :'m4_msg');
select pg_temp.check((select md5 from pg_temp.fn_md5s() where fn = 'customer_profile_stats(uuid)') = '93c1a7b762b99c7e28fdad0facc17ac8',
  'M5 after the refusal customer_profile_stats is still 453''s');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 453 checks passed.';
end $$;
rollback;
